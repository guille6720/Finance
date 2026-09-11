#!/usr/bin/env node
/**
 * Homologation rejection gate — invalid Factura C Nº2.
 * Usage: npm run test:arca:homo:rejection -- --confirm-rejection-test
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const OUT = path.join(
  ROOT,
  "docs",
  "qa",
  "phase5",
  "ARCA-HOMOLOGATION-REJECTION.json"
);

async function main() {
  const confirmed = process.argv.includes("--confirm-rejection-test");
  const arca = await import(
    pathToFileURL(path.join(ROOT, "src/server/arca/index.ts")).href
  );
  arca.loadArcaHomoEnvFile(ROOT);
  if (!process.env.ARCA_ENV && process.env.ARCA_HOMO_CERT_B64) {
    process.env.ARCA_ENV = "homologation";
  }

  const report = {
    label: "LIVE_HOMOLOGATION_REJECTION",
    recorded_at: new Date().toISOString(),
    REJECTION_FLOW: "NOT_RUN",
    REJECTION_RESULT: null,
    LAST_BEFORE: null,
    LAST_AFTER: null,
    NUMBER_CONSUMED: null,
    AUTOMATIC_RETRY: "NO",
    FECAESOLICITAR_CALL_COUNT: 0,
    ACCOUNTING_POST: "NOT_RUN",
    ARCA_PRODUCTION: "NOT_AUTHORIZED",
    evidence: null,
    BLOCKER: null,
  };

  if (!confirmed) {
    report.BLOCKER = "STOP_CONFIRMATION_REQUIRED";
    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify({ status: "STOP_CONFIRMATION_REQUIRED" }, null, 2));
    process.exit(2);
  }

  const cfg = arca.tryGetArcaHomologationConfig();
  if (!cfg.ok) {
    report.BLOCKER = cfg.error.code;
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify({ status: "BLOCKED", code: report.BLOCKER }, null, 2));
    process.exit(2);
  }

  try {
    const evidence = await arca.runHomologationRejectionGate(cfg.config, {
      confirmed: true,
    });
    arca.assertNoFullCaeInEvidence(evidence);
    report.evidence = evidence;
    report.REJECTION_RESULT = evidence.outcome;
    report.LAST_BEFORE = evidence.LAST_BEFORE;
    report.LAST_AFTER = evidence.LAST_AFTER;
    report.NUMBER_CONSUMED = evidence.NUMBER_CONSUMED;
    report.FECAESOLICITAR_CALL_COUNT = evidence.FECAESOLICITAR_CALL_COUNT;
    report.REJECTION_FLOW =
      evidence.outcome === "REJECTED" &&
      evidence.LAST_BEFORE === 1 &&
      evidence.LAST_AFTER === 1 &&
      evidence.NUMBER_CONSUMED === "NO" &&
      evidence.FECAESOLICITAR_CALL_COUNT === 1
        ? "PASS"
        : "FAIL";

    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(
      JSON.stringify(
        {
          REJECTION_FLOW: report.REJECTION_FLOW,
          REJECTION_RESULT: report.REJECTION_RESULT,
          LAST_BEFORE: report.LAST_BEFORE,
          LAST_AFTER: report.LAST_AFTER,
          NUMBER_CONSUMED: report.NUMBER_CONSUMED,
          AUTOMATIC_RETRY: "NO",
          FECAESOLICITAR_CALL_COUNT: report.FECAESOLICITAR_CALL_COUNT,
          ACCOUNTING_POST: "NOT_RUN",
          ARCA_PRODUCTION: "NOT_AUTHORIZED",
        },
        null,
        2
      )
    );
    process.exit(report.REJECTION_FLOW === "PASS" ? 0 : 1);
  } catch (e) {
    report.BLOCKER = e.code || "REJECTION_FAIL";
    report.evidence = { detail: e.message };
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify({ status: "STOP", code: report.BLOCKER }, null, 2));
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(JSON.stringify({ status: "ERROR", message: String(e.message || e) }));
  process.exit(1);
});
