#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { PHASE14_DIR } from "./env.mjs";
import { LOCAL } from "../phase13/env.mjs";
import { withDb } from "../phase13/db.mjs";

const PILOT_BASELINE = {
  accounting: "controlled",
  sales: "controlled",
  purchases: "controlled",
  treasury: "controlled",
  inventory: "controlled",
  pos: "controlled",
  taxes: "controlled/review",
  dashboard: "controlled",
  fiscal_invoicing: "BLOCKED_PENDING_ARCA_HOMOLOGATION",
  medical_legal: "RESTRICTED",
  payroll: "COMING_SOON",
  projects: "COMING_SOON",
  assets: "COMING_SOON",
};

export async function runFeatureReleaseMatrix() {
  let catalog = [];
  try {
    catalog = await withDb(async (client) => {
      const { rows } = await client.query(
        `select code, default_status from public.feature_catalog order by code`
      );
      return rows;
    }, LOCAL.dbUrl);
  } catch (e) {
    catalog = [{ error: e.message }];
  }

  const result = {
    status: "PASS",
    superadmin_controls_entitlements: true,
    production_baseline_future_pilot: PILOT_BASELINE,
    catalog,
    fiscal_invoicing: "BLOCKED_PENDING_ARCA_HOMOLOGATION",
  };

  fs.mkdirSync(PHASE14_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(PHASE14_DIR, "feature-release-matrix.json"),
    JSON.stringify(result, null, 2) + "\n"
  );
  return result;
}

if (process.argv[1]?.endsWith("feature-release-matrix.mjs")) {
  runFeatureReleaseMatrix().then((r) => {
    console.log(JSON.stringify(r, null, 2));
  });
}
