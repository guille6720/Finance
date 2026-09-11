import crypto from "node:crypto";
import fs from "node:fs";
import { EXPECTED_FINGERPRINT_PATH, PHASE13_DIR } from "./env.mjs";
import { withDb } from "./db.mjs";

const FINGERPRINT_SQL = `
with tables as (
  select table_name
  from information_schema.tables
  where table_schema = 'public' and table_type = 'BASE TABLE'
  order by 1
),
columns as (
  select table_name, column_name, data_type, is_nullable, column_default
  from information_schema.columns
  where table_schema = 'public'
  order by 1, ordinal_position
),
constraints as (
  select tc.table_name, tc.constraint_name, tc.constraint_type
  from information_schema.table_constraints tc
  where tc.table_schema = 'public'
    -- Postgres synthesizes NOT NULL checks with OID-based names that
    -- change across clean-room resets; exclude them from the fingerprint.
    and not (
      tc.constraint_type = 'CHECK'
      and tc.constraint_name ~ '^[0-9]+_[0-9]+_[0-9]+_not_null$'
    )
  order by 1, 2
),
policies as (
  select schemaname, tablename, policyname, cmd, roles::text
  from pg_policies
  where schemaname = 'public'
  order by 1, 2, 3
),
functions as (
  select p.proname as name,
         pg_get_function_identity_arguments(p.oid) as args,
         p.prosecdef as security_definer,
         coalesce(p.proconfig, array[]::text[]) as config
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
  order by 1, 2
)
select jsonb_build_object(
  'tables', (select coalesce(jsonb_agg(table_name), '[]'::jsonb) from tables),
  'columns', (select coalesce(jsonb_agg(jsonb_build_object(
      'table', table_name, 'column', column_name, 'type', data_type,
      'nullable', is_nullable, 'default', column_default
    )), '[]'::jsonb) from columns),
  'constraints', (select coalesce(jsonb_agg(jsonb_build_object(
      'table', table_name, 'name', constraint_name, 'type', constraint_type
    )), '[]'::jsonb) from constraints),
  'policies', (select coalesce(jsonb_agg(jsonb_build_object(
      'table', tablename, 'policy', policyname, 'cmd', cmd, 'roles', roles
    )), '[]'::jsonb) from policies),
  'functions', (select coalesce(jsonb_agg(jsonb_build_object(
      'name', name, 'args', args, 'security_definer', security_definer, 'config', config
    )), '[]'::jsonb) from functions)
) as fingerprint;
`;

export async function generateFingerprint() {
  return withDb(async (client) => {
    const { rows } = await client.query(FINGERPRINT_SQL);
    const schema = rows[0].fingerprint;
    const canonical = JSON.stringify(schema);
    const sha256 = crypto.createHash("sha256").update(canonical).digest("hex");
    return {
      generated_at: new Date().toISOString(),
      sha256,
      schema,
    };
  });
}

export async function compareFingerprint({ update = false } = {}) {
  fs.mkdirSync(PHASE13_DIR, { recursive: true });
  const current = await generateFingerprint();

  if (!fs.existsSync(EXPECTED_FINGERPRINT_PATH) || update) {
    fs.writeFileSync(
      EXPECTED_FINGERPRINT_PATH,
      JSON.stringify(current, null, 2) + "\n"
    );
    return {
      status: "PASS",
      detail: update ? "expected fingerprint updated" : "expected fingerprint created",
      sha256: current.sha256,
      drift: [],
    };
  }

  const expected = JSON.parse(fs.readFileSync(EXPECTED_FINGERPRINT_PATH, "utf8"));
  const drift = [];

  if (expected.sha256 !== current.sha256) {
    const expTables = new Set(expected.schema.tables || []);
    const curTables = new Set(current.schema.tables || []);
    for (const t of curTables) if (!expTables.has(t)) drift.push(`+table:${t}`);
    for (const t of expTables) if (!curTables.has(t)) drift.push(`-table:${t}`);

    const expFns = new Map(
      (expected.schema.functions || []).map((f) => [`${f.name}(${f.args})`, f])
    );
    const curFns = new Map(
      (current.schema.functions || []).map((f) => [`${f.name}(${f.args})`, f])
    );
    for (const k of curFns.keys()) if (!expFns.has(k)) drift.push(`+fn:${k}`);
    for (const k of expFns.keys()) if (!curFns.has(k)) drift.push(`-fn:${k}`);

    if (drift.length === 0) {
      drift.push("fingerprint_sha_mismatch_without_table_fn_diff");
    }
  }

  return {
    status: drift.length === 0 ? "PASS" : "FAIL",
    detail:
      drift.length === 0
        ? "schema fingerprint matches expected"
        : `SCHEMA DRIFT: ${drift.length} unexplained`,
    sha256: current.sha256,
    expected_sha256: expected.sha256,
    drift,
  };
}
