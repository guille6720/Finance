#!/usr/bin/env node
/**
 * Homologation uncertain / simulated response-loss gate for Factura C Nº2.
 * Usage: npm run test:arca:homo:uncertain -- --confirm-uncertain-test
 *
 * Will issue Nº2 in homologation when explicitly confirmed by the user later.
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
  "ARCA-HOMOLOGATION-UNCERTAIN.json"
);

async function main() {
  const confirmed = process.argv.includes("--confirm-uncertain-test");
  const arca = await import(
    pathToFileURL(path.join(ROOT, "src/server/arca/index.ts")).href
  );
  arca.loadArcaHomoEnvFile(ROOT);
  if (!process.env.ARCA_ENV && process.env.ARCA_HOMO_CERT_B64) {
    process.env.ARCA_ENV = "homologation";
  }

  const report = {
    label: "LIVE_HOMOLOGATION_UNCERTAIN",
    recorded_at: new Date().toISOString(),
    UNCERTAIN_RECONCILIATION: "NOT_RUN",
    SIMULATED_RESPONSE_LOSS: "NOT_RUN",
    WSAA_HOMOLOGATION: "NOT_RUN",
    FECAESOLICITAR_CALL_COUNT: 0,
    FECAESOLICITAR_SENT: "NO",
    AUTOMATIC_RETRY: "NO",
    FECOMPCONSULTAR: "NOT_RUN",
    CAE_PRESENT: false,
    LAST_BEFORE: null,
    LAST_AFTER: null,
    ACCOUNTING_POST: "NOT_RUN",
    ARCA_PRODUCTION: "NOT_AUTHORIZED",
    TA_REUSE_STRATEGY: "LOCALAPPDATA_HOMOLOGATION_ONLY_TA_FILE",
    evidence: null,
    BLOCKER: null,
    ROOT_CAUSE: null,
    STAGE: null,
  };

  function writeOut() {
    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
  }

  if (!confirmed) {
    const fail = arca.buildGateFailureReport(
      new arca.ArcaSanitizedError(
        "STOP_CONFIRMATION_REQUIRED",
        "uncertain",
        "Missing --confirm-uncertain-test"
      ),
      { fecaeCallCount: 0 }
    );
    Object.assign(report, fail);
    writeOut();
    console.log(JSON.stringify({ status: "STOP_CONFIRMATION_REQUIRED", ...fail }, null, 2));
    process.exit(2);
  }

  const cfg = arca.tryGetArcaHomologationConfig();
  if (!cfg.ok) {
    const fail = arca.buildGateFailureReport(cfg.error, { fecaeCallCount: 0 });
    Object.assign(report, fail);
    writeOut();
    console.log(JSON.stringify({ status: "BLOCKED", ...fail }, null, 2));
    process.exit(2);
  }

  try {
    // Warm / reuse homologation TA (memory + LOCALAPPDATA file). No automatic retry on fault.
    await arca.getValidTa(cfg.config);
    report.WSAA_HOMOLOGATION = "PASS";
    report.TA_CACHE_META = arca.taCacheStats().file_cache;

    const evidence = await arca.runHomologationUncertainGate(cfg.config, {
      confirmed: true,
      simulateResponseLoss: true,
    });
    arca.assertNoFullCaeInEvidence(evidence);
    report.evidence = evidence;
    report.SIMULATED_RESPONSE_LOSS = evidence.SIMULATED_RESPONSE_LOSS;
    report.FECAESOLICITAR_CALL_COUNT = evidence.FECAESOLICITAR_CALL_COUNT;
    report.FECAESOLICITAR_SENT =
      evidence.FECAESOLICITAR_CALL_COUNT > 0 ? "YES" : "NO";
    report.FECOMPCONSULTAR = evidence.FECOMPCONSULTAR;
    report.CAE_PRESENT = evidence.CAE_PRESENT;
    report.LAST_BEFORE = evidence.LAST_BEFORE;
    report.LAST_AFTER = evidence.LAST_AFTER;
    report.UNCERTAIN_RECONCILIATION =
      evidence.outcome === "AUTHORIZED_RECONCILED" &&
      evidence.SIMULATED_RESPONSE_LOSS === "PASS" &&
      evidence.FECAESOLICITAR_CALL_COUNT === 1 &&
      evidence.FECOMPCONSULTAR === "PASS" &&
      evidence.CAE_PRESENT === true &&
      evidence.LAST_BEFORE === 1 &&
      evidence.LAST_AFTER === 2
        ? "PASS"
        : "FAIL";

    writeOut();
    console.log(
      JSON.stringify(
        {
          UNCERTAIN_RECONCILIATION: report.UNCERTAIN_RECONCILIATION,
          SIMULATED_RESPONSE_LOSS: report.SIMULATED_RESPONSE_LOSS,
          WSAA_HOMOLOGATION: report.WSAA_HOMOLOGATION,
          FECAESOLICITAR_CALL_COUNT: report.FECAESOLICITAR_CALL_COUNT,
          FECAESOLICITAR_SENT: report.FECAESOLICITAR_SENT,
          AUTOMATIC_RETRY: "NO",
          FECOMPCONSULTAR: report.FECOMPCONSULTAR,
          CAE_PRESENT: report.CAE_PRESENT,
          LAST_BEFORE: report.LAST_BEFORE,
          LAST_AFTER: report.LAST_AFTER,
          ACCOUNTING_POST: "NOT_RUN",
          ARCA_PRODUCTION: "NOT_AUTHORIZED",
        },
        null,
        2
      )
    );
    process.exit(report.UNCERTAIN_RECONCILIATION === "PASS" ? 0 : 1);
  } catch (e) {
    const fail = arca.buildGateFailureReport(e, {
      fecaeCallCount: report.FECAESOLICITAR_CALL_COUNT || 0,
    });
    Object.assign(report, fail);
    // Pre-issuance failure: never claim FECAE was sent
    if (fail.FECAESOLICITAR_SENT === "NO") {
      report.FECAESOLICITAR_CALL_COUNT = 0;
      report.FECAESOLICITAR_SENT = "NO";
    }
    writeOut();
    console.log(
      JSON.stringify(
        {
          status: "STOP",
          BLOCKER: fail.BLOCKER,
          ROOT_CAUSE: fail.ROOT_CAUSE,
          STAGE: fail.STAGE,
          WSAA_HOMOLOGATION: fail.WSAA_HOMOLOGATION,
          FECAESOLICITAR_CALL_COUNT: fail.FECAESOLICITAR_CALL_COUNT,
          FECAESOLICITAR_SENT: fail.FECAESOLICITAR_SENT,
          AUTOMATIC_RETRY: "NO",
          ACCOUNTING_POST: "NOT_RUN",
          ARCA_PRODUCTION: "NOT_AUTHORIZED",
        },
        null,
        2
      )
    );
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(JSON.stringify({ status: "ERROR", message: String(e.message || e) }));
  process.exit(1);
});
