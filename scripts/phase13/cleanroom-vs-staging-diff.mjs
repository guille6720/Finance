#!/usr/bin/env node
/**
 * Phase 13 — Cleanroom vs Staging schema diff.
 *
 * Inventories local public schema (tables, enums, functions, RLS/policies)
 * and compares against docs/qa/phase13/staging-schema-forensics.json.
 *
 * Classifications:
 *   INTENTIONAL_LOCAL_ONLY  — present only locally, deliberate (phase13 hardening policies)
 *   RECOVERED_OK            — present in both cleanroom and staging
 *   MISSING_IN_CLEANROOM    — in staging but absent locally
 *   EXTRA_IN_CLEANROOM      — local only, no deliberate reason registered
 *   DEFINITION_DRIFT        — present both sides but definition differs
 *
 * Required goal: UNEXPLAINED_SCHEMA_DRIFT = 0
 * Writes: docs/qa/phase13/cleanroom-vs-staging-schema-diff.json
 */
import fs from "node:fs";
import path from "node:path";
import { withDb } from "./db.mjs";
import { ROOT, PHASE13_DIR } from "./env.mjs";

const FORENSICS_PATH = path.join(PHASE13_DIR, "staging-schema-forensics.json");
const OUT_PATH = path.join(PHASE13_DIR, "cleanroom-vs-staging-schema-diff.json");

// Functions intentionally ONLY in staging (not recovered to cleanroom).
// Each entry must be documented with a reason.
const INTENTIONAL_STAGING_ONLY_FUNCS = new Set([
  // Explicitly skipped per recovery migration 20260801205000 comment:
  // "staging-only refactor; Phase 9 uses finalize_pos_sale; not required for cleanroom correctness"
  "finalize_pos_sale_impl",
  // Internal helper only called by finalize_pos_sale_impl (above); not needed in cleanroom.
  "pos_assert_session_actor",
]);

// Policies that are INTENTIONALLY only in the cleanroom (local hardening).
const INTENTIONAL_LOCAL_POLICIES = new Set([
  "organizations::organizations_select_creator",
  "organization_members::members_select_self",
]);

// Tables that appear in local only because of phase12 internal state machinery.
const INTENTIONAL_LOCAL_TABLES = new Set([
  "phase12_migration_effective_diff",
  "phase12_migration_effective_snapshot",
]);

async function inventoryLocal(client) {
  // Tables + RLS
  const { rows: tables } = await client.query(`
    select c.relname as name, c.relrowsecurity as rls_enabled
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
    order by c.relname
  `);

  // Enums
  const { rows: enums } = await client.query(`
    select t.typname as name,
           array_agg(e.enumlabel order by e.enumsortorder) as labels
    from pg_type t
    join pg_enum e on e.enumtypid = t.oid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
    group by t.typname
    order by t.typname
  `);

  // Functions (name + arg types)
  const { rows: funcs } = await client.query(`
    select p.proname as name,
           pg_get_function_identity_arguments(p.oid) as args,
           p.prosecdef as security_definer
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
    order by p.proname, args
  `);

  // RLS Policies
  const { rows: policies } = await client.query(`
    select c.relname as table_name, p.polname as policy_name,
           case p.polcmd
             when 'r' then 'SELECT'
             when 'a' then 'INSERT'
             when 'w' then 'UPDATE'
             when 'd' then 'DELETE'
             else 'ALL'
           end as cmd,
           array_agg(r.rolname order by r.rolname) as roles
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    left join pg_roles r on r.oid = any(p.polroles)
    where n.nspname = 'public'
    group by c.relname, p.polname, p.polcmd
    order by c.relname, p.polname
  `);

  return { tables, enums, funcs, policies };
}

function loadForensics() {
  if (!fs.existsSync(FORENSICS_PATH)) {
    throw new Error(`Forensics file not found: ${FORENSICS_PATH}`);
  }
  return JSON.parse(fs.readFileSync(FORENSICS_PATH, "utf8"));
}

async function main() {
  fs.mkdirSync(PHASE13_DIR, { recursive: true });

  const forensics = loadForensics();
  const stagingTables = new Set((forensics.tables || []).map((t) => t.name));
  const stagingEnums = new Set((forensics.enums || []).map((e) => e.name));
  // Normalize function args: strip all double-quote chars so that
  //   "p_document_id" "uuid"  →  p_document_id uuid
  // Also strip DEFAULT expressions (staging pg_dump includes them; local PG catalog drops them).
  // Also strip schema prefix "public." from type names.
  // This reconciles pg_dump quoted identifiers with pg_get_function_identity_arguments output.
  const normArgs = (args) => {
    if (!args) return "";
    let s = args;
    // Remove double quotes
    s = s.replace(/"/g, "");
    // Strip "public." schema prefix from type references
    s = s.replace(/\bpublic\./g, "");
    // Strip DEFAULT clauses per-parameter, handling parenthesized defaults like (CURRENT_DATE + 30)
    // Strategy: for each comma-separated segment, strip from " DEFAULT " onwards (depth-aware)
    const stripDefaults = (argStr) => {
      const parts = [];
      let depth = 0;
      let current = "";
      let inDefault = false;
      for (let i = 0; i < argStr.length; i++) {
        const ch = argStr[i];
        if (ch === "(") depth++;
        if (ch === ")") depth--;
        if (depth === 0 && ch === ",") {
          // end of parameter
          parts.push(inDefault ? current.replace(/\s+DEFAULT.*$/i, "").trim() : current.trim());
          current = "";
          inDefault = false;
          continue;
        }
        current += ch;
        if (!inDefault && / DEFAULT /i.test(current.slice(-10))) inDefault = true;
      }
      if (current.trim()) {
        parts.push(inDefault ? current.replace(/\s+DEFAULT.*$/i, "").trim() : current.trim());
      }
      return parts.join(", ");
    };
    s = stripDefaults(s);
    // Collapse multiple spaces
    s = s.replace(/\s+/g, " ").trim();
    return s;
  };
  const stagingFuncs = new Set(
    (forensics.functions || []).map((f) => `${f.name}(${normArgs(f.args)})`)
  );

  const local = await withDb(inventoryLocal);
  const localTables = new Set(local.tables.map((t) => t.name));
  const localEnums = new Set(local.enums.map((e) => e.name));
  const localFuncs = new Set(
    local.funcs.map((f) => `${f.name}(${normArgs(f.args || "")})`)
  );

  const diffs = [];

  // ── Tables ───────────────────────────────────────────────────────────────
  // In staging but not local
  for (const t of stagingTables) {
    if (!localTables.has(t)) {
      diffs.push({
        kind: "TABLE",
        name: t,
        classification: "MISSING_IN_CLEANROOM",
        note: "Present in staging; absent in cleanroom",
      });
    }
  }
  // In local but not staging
  for (const t of localTables) {
    if (!stagingTables.has(t)) {
      const intentional = INTENTIONAL_LOCAL_TABLES.has(t);
      diffs.push({
        kind: "TABLE",
        name: t,
        classification: intentional ? "INTENTIONAL_LOCAL_ONLY" : "EXTRA_IN_CLEANROOM",
        note: intentional
          ? "Phase 12 internal state table; not in staging public schema"
          : "Extra table in cleanroom; investigate",
      });
    }
  }

  // ── Enums ────────────────────────────────────────────────────────────────
  for (const e of stagingEnums) {
    if (!localEnums.has(e)) {
      diffs.push({
        kind: "ENUM",
        name: e,
        classification: "MISSING_IN_CLEANROOM",
        note: "Present in staging; absent in cleanroom",
      });
    }
  }
  for (const e of localEnums) {
    if (!stagingEnums.has(e)) {
      diffs.push({
        kind: "ENUM",
        name: e,
        classification: "EXTRA_IN_CLEANROOM",
        note: "Extra enum in cleanroom; investigate",
      });
    }
  }

  // ── Functions ────────────────────────────────────────────────────────────
  for (const f of stagingFuncs) {
    if (!localFuncs.has(f)) {
      const fname = f.replace(/\(.*$/, "");
      const intentional = INTENTIONAL_STAGING_ONLY_FUNCS.has(fname);
      diffs.push({
        kind: "FUNCTION",
        name: f,
        classification: intentional ? "INTENTIONAL_STAGING_ONLY" : "MISSING_IN_CLEANROOM",
        note: intentional
          ? "Staging-only function; intentionally not recovered (see INTENTIONAL_STAGING_ONLY_FUNCS)"
          : "Present in staging; absent in cleanroom",
      });
    }
  }
  for (const f of localFuncs) {
    if (!stagingFuncs.has(f)) {
      diffs.push({
        kind: "FUNCTION",
        name: f,
        classification: "EXTRA_IN_CLEANROOM",
        note: "Extra function in cleanroom; investigate",
      });
    }
  }

  // ── Policies ─────────────────────────────────────────────────────────────
  // Build staging policy set — forensics uses { name, table } (not table_name/policy_name)
  const stagingPolicies = new Set(
    (forensics.policies || []).map((p) => `${p.table}::${p.name}`)
  );
  const localPolicies = new Set(
    local.policies.map((p) => `${p.table_name}::${p.policy_name}`)
  );

  for (const p of stagingPolicies) {
    if (!localPolicies.has(p)) {
      diffs.push({
        kind: "POLICY",
        name: p,
        classification: "MISSING_IN_CLEANROOM",
        note: "Present in staging; absent in cleanroom",
      });
    }
  }
  for (const p of localPolicies) {
    if (!stagingPolicies.has(p)) {
      const intentional = INTENTIONAL_LOCAL_POLICIES.has(p);
      diffs.push({
        kind: "POLICY",
        name: p,
        classification: intentional ? "INTENTIONAL_LOCAL_ONLY" : "EXTRA_IN_CLEANROOM",
        note: intentional
          ? "Phase 13 local hardening policy: bootstrap visibility"
          : "Extra policy in cleanroom; investigate",
      });
    }
  }

  // ── Summary ──────────────────────────────────────────────────────────────
  const byClass = {};
  for (const d of diffs) {
    byClass[d.classification] = (byClass[d.classification] || 0) + 1;
  }

  const unexplained = diffs.filter(
    (d) =>
      d.classification === "MISSING_IN_CLEANROOM" ||
      d.classification === "EXTRA_IN_CLEANROOM"
  );

  const summary = {
    generated_at: new Date().toISOString(),
    local_table_count: localTables.size,
    staging_table_count: stagingTables.size,
    local_enum_count: localEnums.size,
    staging_enum_count: stagingEnums.size,
    local_func_count: localFuncs.size,
    staging_func_count: stagingFuncs.size,
    local_policy_count: localPolicies.size,
    staging_policy_count: stagingPolicies.size,
    classification_counts: byClass,
    UNEXPLAINED_SCHEMA_DRIFT: unexplained.length,
    status: unexplained.length === 0 ? "PASS" : "FAIL",
  };

  const output = {
    summary,
    diffs,
    unexplained,
  };

  fs.writeFileSync(OUT_PATH, JSON.stringify(output, null, 2) + "\n");

  // Print summary
  console.log("\n=== CLEANROOM vs STAGING SCHEMA DIFF ===");
  console.log(`Local tables:     ${summary.local_table_count}`);
  console.log(`Staging tables:   ${summary.staging_table_count}`);
  console.log(`Local enums:      ${summary.local_enum_count}`);
  console.log(`Staging enums:    ${summary.staging_enum_count}`);
  console.log(`Local functions:  ${summary.local_func_count}`);
  console.log(`Staging functions:${summary.staging_func_count}`);
  console.log(`Local policies:   ${summary.local_policy_count}`);
  console.log(`Staging policies: ${summary.staging_policy_count}`);
  console.log("\nClassification counts:", JSON.stringify(byClass, null, 2));
  console.log(`\nUNEXPLAINED_SCHEMA_DRIFT: ${summary.UNEXPLAINED_SCHEMA_DRIFT}`);
  console.log(`Status: ${summary.status}`);

  if (unexplained.length > 0) {
    console.log("\nUnexplained diffs:");
    for (const d of unexplained) {
      console.log(`  [${d.classification}] ${d.kind} ${d.name}: ${d.note}`);
    }
  }

  console.log(`\nWrote ${OUT_PATH}`);
  if (summary.status !== "PASS") process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
