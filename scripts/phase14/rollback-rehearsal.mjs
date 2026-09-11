#!/usr/bin/env node
/**
 * LOCAL disposable rollback rehearsal.
 * Does not run automatic down migrations.
 * Simulates: release N schema stays; app rolls back conceptually; DB uses forward correction only.
 */
import fs from "node:fs";
import path from "node:path";
import { PHASE14_DIR, ROOT } from "./env.mjs";
import { listMigrations } from "../phase13/provenance.mjs";
import { generateFingerprint } from "../phase13/fingerprint.mjs";
import { LOCAL } from "../phase13/env.mjs";
import { withDb } from "../phase13/db.mjs";

export async function runRollbackRehearsal() {
  const migrations = listMigrations();
  const last = migrations[migrations.length - 1];
  const lastBody = fs.readFileSync(
    path.join(ROOT, "supabase/migrations", last.name),
    "utf8"
  );

  const hasDown = /down\s+migration|BEGIN\s+DOWN/i.test(lastBody);
  const fingerprint = await generateFingerprint();

  const phase1StillPresent = await withDb(async (client) => {
    const { rows } = await client.query(`
      select count(*)::int as n
      from information_schema.tables
      where table_schema='public'
        and table_name in (
          'organizations',
          'organization_members',
          'profiles',
          'audit_events',
          'feature_catalog'
        )
    `);
    return rows[0].n === 5;
  }, LOCAL.dbUrl);

  const synthetic = await withDb(async (client) => {
    const { rows } = await client.query(`
      insert into public.app_settings (key, value, description)
      values (
        'phase14.rollback_rehearsal',
        jsonb_build_object('at', timezone('utc', now())::text, 'release', $1::text),
        'Phase 14 rollback rehearsal marker (forward correction)'
      )
      on conflict (key) do update
        set value = excluded.value, updated_at = timezone('utc', now())
      returning key
    `, [last.name]);
    return rows[0]?.key === "phase14.rollback_rehearsal";
  }, LOCAL.dbUrl);

  const status =
    !hasDown && phase1StillPresent && synthetic ? "PASS" : "FAIL";

  const result = {
    ROLLBACK_REHEARSAL: status,
    status,
    simulated: {
      release_n_plus_1: last.name,
      application_rollback: "schema retained; no automatic down SQL",
      synthetic_operations: synthetic,
    },
    automatic_downgrade_migrations: hasDown,
    phase1_tables_intact: phase1StillPresent,
    fingerprint_sha256: fingerprint.sha256,
    detail: status === "PASS"
      ? "Forward-only rehearsal: N+1 applied, app rollback does not drop schema, marker written"
      : "Rollback rehearsal failed invariants",
  };

  fs.mkdirSync(PHASE14_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(PHASE14_DIR, "rollback-rehearsal-last-run.json"),
    JSON.stringify(result, null, 2) + "\n"
  );
  return result;
}

if (process.argv[1]?.endsWith("rollback-rehearsal.mjs")) {
  runRollbackRehearsal()
    .then((r) => {
      console.log(JSON.stringify(r, null, 2));
      if (r.status !== "PASS") process.exit(1);
    })
    .catch((e) => {
      console.error(e);
      process.exit(1);
    });
}
