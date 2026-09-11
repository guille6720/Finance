#!/usr/bin/env node
/**
 * LIVE homologation ONE-SHOT FECAESolicitar.
 * Requires: --confirm-homologation-issue
 * Never retries. Never Production. No accounting.
 *
 * Usage:
 *   npm run test:arca:homo:cae-once -- --confirm-homologation-issue
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const OUT = path.join(ROOT, "docs", "qa", "phase5", "ARCA-HOMOLOGATION-CAE-ONCE.json");

async function main() {
  const confirmed = process.argv.includes("--confirm-homologation-issue");
  const arca = await import(
    pathToFileURL(path.join(ROOT, "src/server/arca/index.ts")).href
  );

  arca.loadArcaHomoEnvFile(ROOT);
  if (!process.env.ARCA_ENV && process.env.ARCA_HOMO_CERT_B64) {
    process.env.ARCA_ENV = "homologation";
  }

  const report = {
    label: "LIVE_HOMOLOGATION_CAE_ONCE",
    recorded_at: new Date().toISOString(),
    confirmed,
    ACCOUNTING_POST: "NOT_RUN",
    ARCA_PRODUCTION: "NOT_AUTHORIZED",
    LIVE_FECAESOLICITAR: "NOT_RUN",
    result: null,
    BLOCKER: null,
    ROOT_CAUSE: null,
  };

  if (!confirmed) {
    report.BLOCKER = "STOP_CONFIRMATION_REQUIRED";
    report.ROOT_CAUSE =
      "Pass --confirm-homologation-issue to authorize one homologation FECAESolicitar";
    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify({ status: "STOP_CONFIRMATION_REQUIRED" }, null, 2));
    process.exit(2);
  }

  const cfgTry = arca.tryGetArcaHomologationConfig();
  if (!cfgTry.ok) {
    report.BLOCKER = cfgTry.error.code;
    report.ROOT_CAUSE = cfgTry.error.message;
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify({ status: "BLOCKED", code: report.BLOCKER }, null, 2));
    process.exit(2);
  }

  try {
    const result = await arca.feCaeSolicitarHomologationOnce(cfgTry.config, {
      confirmed: true,
    });
    report.result = result;
    report.LIVE_FECAESOLICITAR =
      result.outcome.startsWith("AUTHORIZED") || result.outcome === "REJECTED"
        ? "EXECUTED"
        : result.outcome;
    report.FECAESOLICITAR =
      result.outcome === "STOP_CONFIRMATION_REQUIRED" ||
      result.outcome === "STOP_ALREADY_ISSUED" ||
      result.outcome === "STOP_BEFORE_FECAE" ||
      result.outcome === "STOP_GUARD"
        ? "NOT_RUN"
        : "EXECUTED";
    report.FECOMPCONSULTAR = result.outcome.includes("RECONCIL")
      ? "PASS"
      : result.outcome.startsWith("AUTHORIZED")
        ? "PASS"
        : "NOT_RUN";
    report.CAE_MATCH = result.cae_present ? true : null;
    report.LAST_AUTHORIZED_QUERY = result.cbte_nro != null ? "PASS" : "NOT_RUN";
    report.LAST_AUTHORIZED = result.cbte_nro;
    report.NO_AUTOMATIC_RETRY = true;
    report.FECAESOLICITAR_CALL_COUNT =
      result.outcome === "STOP_ALREADY_ISSUED" ||
      result.outcome === "STOP_BEFORE_FECAE" ||
      result.outcome === "STOP_GUARD" ||
      result.outcome === "STOP_CONFIRMATION_REQUIRED"
        ? 0
        : 1;
    report.RECONCILIATION_STATUS =
      result.outcome === "AUTHORIZED_RECONCILED"
        ? "AUTHORIZED_RECONCILED"
        : result.outcome === "RECONCILIATION_REQUIRED"
          ? "RECONCILIATION_REQUIRED"
          : result.outcome === "UNCERTAIN_STOP"
            ? "UNCERTAIN_STOP"
            : "NOT_NEEDED";
    arca.assertNoFullCaeInEvidence(report);
    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(
      JSON.stringify(
        {
          status: result.outcome,
          pto_venta: result.pto_venta,
          cbte_tipo: result.cbte_tipo,
          cbte_nro: result.cbte_nro,
          cae_present: result.cae_present,
          cae_length: result.cae_length,
          cae_fch_vto: result.cae_fch_vto,
          FECAESOLICITAR: report.FECAESOLICITAR,
          FECOMPCONSULTAR: report.FECOMPCONSULTAR,
          CAE_MATCH: report.CAE_MATCH,
          LAST_AUTHORIZED_QUERY: report.LAST_AUTHORIZED_QUERY,
          LAST_AUTHORIZED: report.LAST_AUTHORIZED,
          NO_AUTOMATIC_RETRY: true,
          FECAESOLICITAR_CALL_COUNT: report.FECAESOLICITAR_CALL_COUNT,
          RECONCILIATION_STATUS: report.RECONCILIATION_STATUS,
          ACCOUNTING_POST: "NOT_RUN",
          ARCA_PRODUCTION: "NOT_AUTHORIZED",
        },
        null,
        2
      )
    );
    process.exit(result.outcome.startsWith("AUTHORIZED") ? 0 : 1);
  } catch (e) {
    report.BLOCKER = e.code || "CAE_FAIL";
    report.ROOT_CAUSE = e.message;
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify({ status: "STOP", code: report.BLOCKER }, null, 2));
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(JSON.stringify({ status: "ERROR", message: String(e.message || e) }));
  process.exit(1);
});
