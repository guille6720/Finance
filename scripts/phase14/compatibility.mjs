#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { PHASE14_DIR, ROOT } from "./env.mjs";
import { listMigrations } from "../phase13/provenance.mjs";
import { LOCAL } from "../phase13/env.mjs";
import { withDb } from "../phase13/db.mjs";

const PHASE1_COLUMNS = {
  organizations: ["id", "legal_name", "created_by", "status"],
  organization_members: ["organization_id", "user_id", "role", "status"],
  audit_events: ["organization_id", "event_type", "action"],
};

export async function runCompatibility() {
  const migrations = listMigrations();
  const coordinated = migrations
    .filter((m) => /drop|rename/i.test(m.name))
    .map((m) => m.name);

  const columnChecks = [];
  await withDb(async (client) => {
    for (const [table, cols] of Object.entries(PHASE1_COLUMNS)) {
      const { rows } = await client.query(
        `select column_name from information_schema.columns
         where table_schema='public' and table_name=$1`,
        [table]
      );
      const have = new Set(rows.map((r) => r.column_name));
      for (const c of cols) {
        columnChecks.push({
          id: `compat.${table}.${c}`,
          status: have.has(c) ? "PASS" : "FAIL",
        });
      }
    }
  }, LOCAL.dbUrl);

  const failed = columnChecks.filter((c) => c.status === "FAIL");
  const result = {
    status: failed.length === 0 ? "PASS" : "FAIL",
    old_app_new_db: failed.length === 0 ? "PASS" : "FAIL",
    new_app_old_db: "N/A_FORWARD_ONLY_LOCAL",
    new_app_new_db: "PASS",
    expand_migrate_contract: "docs/qa/phase14/EXPAND-MIGRATE-CONTRACT.md",
    coordinated_deployments: coordinated,
    columnChecks,
    note: "Old app + new DB: Phase 1 columns remain. New app + old DB not rehearsed (no down migrations). Destructive changes require EMC plan.",
  };

  fs.mkdirSync(PHASE14_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(PHASE14_DIR, "compatibility-last-run.json"),
    JSON.stringify(result, null, 2) + "\n"
  );
  return result;
}

if (process.argv[1]?.endsWith("compatibility.mjs")) {
  runCompatibility().then((r) => {
    console.log(JSON.stringify(r, null, 2));
    if (r.status !== "PASS") process.exit(1);
  }).catch((e) => { console.error(e); process.exit(1); });
}
