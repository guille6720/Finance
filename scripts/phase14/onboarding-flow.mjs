#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { PHASE14_DIR } from "./env.mjs";
import { runGoldenFlow } from "../phase13/golden-flow.mjs";

const ONBOARDING_STEPS = [
  "auth",
  "organization",
  "membership_bootstrap",
  "modules_entitlements",
  "customer",
  "supplier",
  "product",
  "warehouse",
  "treasury_account_setup",
  "dashboard_reporting",
];

export async function runOnboardingFlow() {
  const started = Date.now();
  const golden = await runGoldenFlow();
  const elapsed_ms = Date.now() - started;
  const byStep = Object.fromEntries(golden.executed.map((e) => [e.step, e]));
  const steps = ONBOARDING_STEPS.map((id) => ({
    step: id,
    status: byStep[id]?.status === "PASS" ? "PASS" : "FAIL",
    note: byStep[id]?.note,
  }));
  const failed = steps.filter((s) => s.status !== "PASS");
  const result = {
    ONBOARDING_FULL_FLOW: failed.length === 0 ? "PASS" : "FAIL",
    status: failed.length === 0 ? "PASS" : "FAIL",
    steps: steps.length,
    elapsed_ms,
    errors: failed.map((f) => f.step),
    manual_interventions: 0,
    executed: steps,
    org_id: golden.context_ids?.org_id ?? null,
  };
  fs.mkdirSync(PHASE14_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(PHASE14_DIR, "onboarding-last-run.json"),
    JSON.stringify(result, null, 2) + "\n"
  );
  return result;
}

if (process.argv[1]?.endsWith("onboarding-flow.mjs")) {
  runOnboardingFlow().then((r) => {
    console.log(JSON.stringify(r, null, 2));
    if (r.status !== "PASS") process.exit(1);
  }).catch((e) => { console.error(e); process.exit(1); });
}
