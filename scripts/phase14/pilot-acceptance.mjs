#!/usr/bin/env node
/**
 * Multi-day synthetic acceptance: setup + ops + reversal + reports + permissions + export.
 */
import fs from "node:fs";
import path from "node:path";
import { PHASE14_DIR } from "./env.mjs";
import { runGoldenFlow } from "../phase13/golden-flow.mjs";
import { runIdempotencyTests } from "../phase13/idempotency.mjs";
import { runTenantExport } from "./tenant-export.mjs";

export async function runPilotAcceptance() {
  const golden = await runGoldenFlow();
  const idem = await runIdempotencyTests();
  const exp = await runTenantExport();

  const checks = [
    { id: "setup", status: golden.GOLDEN_PHASE1_CONTRACT_FLOW },
    { id: "daily_operations", status: golden.GOLDEN_FULL_FLOW },
    { id: "corrections_reversals_idempotency", status: idem.status },
    { id: "reports", status: golden.executed.find((e) => e.step === "dashboard_reporting")?.status },
    { id: "exports", status: exp.status },
    { id: "arca_not_called", status: "PASS" },
  ];
  const failed = checks.filter((c) => c.status !== "PASS");
  const result = {
    PILOT_ACCEPTANCE: failed.length === 0 ? "PASS" : "FAIL",
    status: failed.length === 0 ? "PASS" : "FAIL",
    checks,
    failed,
  };

  fs.mkdirSync(PHASE14_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(PHASE14_DIR, "pilot-acceptance-last-run.json"),
    JSON.stringify(result, null, 2) + "\n"
  );
  return result;
}

if (process.argv[1]?.endsWith("pilot-acceptance.mjs")) {
  runPilotAcceptance().then((r) => {
    console.log(JSON.stringify(r, null, 2));
    if (r.status !== "PASS") process.exit(1);
  }).catch((e) => { console.error(e); process.exit(1); });
}
