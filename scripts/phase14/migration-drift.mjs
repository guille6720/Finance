#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { PHASE14_DIR } from "./env.mjs";
import { listMigrations, verifyProvenance } from "../phase13/provenance.mjs";
import { withDb } from "../phase13/db.mjs";
import { LOCAL } from "../phase13/env.mjs";

const DESTRUCTIVE = /^\s*(DROP\s+TABLE|DROP\s+COLUMN|ALTER\s+TABLE[\s\S]{0,80}DROP\s+COLUMN)/im;

export async function runMigrationDrift() {
  const files = listMigrations();
  const provenance = verifyProvenance();
  const mismatches = [...(provenance.mismatches || [])];

  let history = [];
  try {
    history = await withDb(async (client) => {
      const { rows } = await client.query(`
        select version
        from supabase_migrations.schema_migrations
        order by version
      `);
      return rows.map((r) => String(r.version));
    }, LOCAL.dbUrl);
  } catch (e) {
    mismatches.push(`history_query_failed: ${e.message}`);
  }

  const fileVersions = files.map((f) => f.name.slice(0, 14));
  for (const v of history) {
    if (!fileVersions.includes(v)) {
      mismatches.push(`unexpected migration in DB: ${v}`);
    }
  }
  for (const v of fileVersions) {
    if (history.length && !history.includes(v)) {
      mismatches.push(`missing from DB history: ${v}`);
    }
  }

  const destructive = [];
  for (const f of files) {
    const body = fs.readFileSync(
      path.join(process.cwd(), "supabase/migrations", f.name),
      "utf8"
    );
    if (DESTRUCTIVE.test(body) && !body.includes("EXPAND-MIGRATE-CONTRACT")) {
      destructive.push(f.name);
    }
  }

  const drift = mismatches.length;
  const result = {
    MIGRATION_DRIFT: drift,
    status: drift === 0 ? "PASS" : "FAIL",
    file_count: files.length,
    history_count: history.length,
    provenance: provenance.status,
    mismatches,
    destructive_without_emc_plan: destructive,
  };

  fs.mkdirSync(PHASE14_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(PHASE14_DIR, "migration-drift-last-run.json"),
    JSON.stringify(result, null, 2) + "\n"
  );
  return result;
}

if (process.argv[1]?.endsWith("migration-drift.mjs")) {
  runMigrationDrift()
    .then((r) => {
      console.log(JSON.stringify(r, null, 2));
      if (r.status !== "PASS") process.exit(1);
    })
    .catch((e) => {
      console.error(e);
      process.exit(1);
    });
}
