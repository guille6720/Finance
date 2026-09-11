#!/usr/bin/env node
/**
 * Phase 13D — Staging schema forensics (READ-ONLY).
 * Parses pg_dump schema SQL (no live DB connection) into structured JSON.
 */
import fs from "node:fs";
import path from "node:path";
import { ROOT, MIGRATIONS_DIR, PHASE13_DIR } from "./env.mjs";

const DUMP_PATH = path.join(
  PHASE13_DIR,
  "forensics",
  "staging-public-schema.sql"
);
const FORENSICS_OUT = path.join(PHASE13_DIR, "staging-schema-forensics.json");
const DOMAIN_MAP_OUT = path.join(PHASE13_DIR, "staging-domain-map.json");
const PHASE10_GAP_OUT = path.join(
  PHASE13_DIR,
  "forensics",
  "phase10-zero-statement-gap.json"
);

const PHASE_LABELS = {
  1: "platform",
  2: "accounting",
  3: "counterparties",
  4: "sales",
  5: "fiscal",
  6: "purchases",
  7: "treasury",
  8: "products/inventory",
  9: "POS",
  10: "taxes",
  11: "dashboard/reporting",
  12: "configurator/entitlements",
};

const EMPTY_MIGRATION_RE = /^\s*(\{\}|;)\s*$/s;

function unquoteIdent(s) {
  const m = s.match(/^"([^"]+)"$/);
  return m ? m[1] : s;
}

function splitTopLevelComma(text) {
  const parts = [];
  let depth = 0;
  let cur = "";
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === "(") depth++;
    else if (ch === ")") depth--;
    else if (ch === "," && depth === 0) {
      parts.push(cur.trim());
      cur = "";
      continue;
    }
    cur += ch;
  }
  if (cur.trim()) parts.push(cur.trim());
  return parts;
}

function parseColumnLine(line) {
  const colMatch = line.match(
    /^"([^"]+)"\s+([\s\S]+)$/
  );
  if (!colMatch) return null;
  const name = colMatch[1];
  let rest = colMatch[2].trim();
  const generated =
    /GENERATED ALWAYS AS IDENTITY/i.test(rest) ||
    /GENERATED ALWAYS AS \(/i.test(rest);
  const nullable = !/\bNOT NULL\b/i.test(rest);
  let defaultVal = null;
  const defMatch = rest.match(/\bDEFAULT\s+([\s\S]+?)(?:\s+NOT NULL|\s+GENERATED|$)/i);
  if (defMatch) defaultVal = defMatch[1].trim();
  const typeMatch = rest.match(
    /^((?:"[^"]+"\.|"public"\.)?[^,\s]+(?:\([^)]*\))?(?:\s+"[^"]+"\.[^,\s]+(?:\([^)]*\))?)*)/i
  );
  const type = typeMatch ? typeMatch[1].trim() : rest.split(/\s+/)[0];
  return {
    name,
    type,
    nullable,
    default: defaultVal,
    generated,
    identity: /GENERATED ALWAYS AS IDENTITY/i.test(rest),
  };
}

function parseTableBody(body) {
  const columns = [];
  const inline_constraints = [];
  for (const item of splitTopLevelComma(body)) {
    if (/^CONSTRAINT\s/i.test(item)) {
      const cName = item.match(/^CONSTRAINT\s+"([^"]+)"/i)?.[1] ?? null;
      let kind = "CHECK";
      if (/PRIMARY KEY/i.test(item)) kind = "PRIMARY KEY";
      else if (/UNIQUE/i.test(item)) kind = "UNIQUE";
      else if (/FOREIGN KEY/i.test(item)) kind = "FOREIGN KEY";
      else if (/EXCLUDE/i.test(item)) kind = "EXCLUDE";
      inline_constraints.push({ name: cName, type: kind, definition: item });
    } else {
      const col = parseColumnLine(item);
      if (col) columns.push(col);
    }
  }
  return { columns, inline_constraints };
}

function extractDollarBody(sql, startIdx) {
  const open = sql.indexOf("AS $$", startIdx);
  if (open === -1) return null;
  const bodyStart = open + 5;
  const close = sql.indexOf("\n$$;", bodyStart);
  if (close === -1) return null;
  return {
    body: sql.slice(bodyStart, close + 1),
    end: close + 4,
  };
}

export function parseStagingDump(sql) {
  const enums = [];
  const tables = {};
  const tableOrder = [];
  const functions = [];
  const indexes = [];
  const alterConstraints = [];
  const policies = [];
  const grants = [];
  const rls = {};
  const triggers = [];

  for (const m of sql.matchAll(
    /CREATE TYPE "public"\."([^"]+)" AS ENUM \(([\s\S]*?)\);/g
  )) {
    const labels = [...m[2].matchAll(/'([^']*)'/g)].map((x) => x[1]);
    enums.push({ name: m[1], labels });
  }

  for (const m of sql.matchAll(
    /CREATE TABLE IF NOT EXISTS "public"\."([^"]+)" \(([\s\S]*?)\);/g
  )) {
    const name = m[1];
    const parsed = parseTableBody(m[2]);
    tables[name] = {
      name,
      columns: parsed.columns,
      inline_constraints: parsed.inline_constraints,
    };
    tableOrder.push(name);
  }

  const fnRe =
    /CREATE OR REPLACE FUNCTION "public"\."([^"]+)"\(([\s\S]*?)\) RETURNS ([^\n]+)\n([\s\S]*?)\n\$\$;/g;
  for (const m of sql.matchAll(fnRe)) {
    const headerBlock = m[4];
    const security_definer = /SECURITY DEFINER/i.test(headerBlock);
    const security_invoker = /SECURITY INVOKER/i.test(headerBlock);
    const search_path =
      headerBlock.match(/SET "search_path" TO '([^']*)'/i)?.[1] ??
      headerBlock.match(/SET search_path TO '([^']*)'/i)?.[1] ??
      null;
    const language =
      headerBlock.match(/LANGUAGE "([^"]+)"/i)?.[1] ??
      headerBlock.match(/LANGUAGE (\w+)/i)?.[1] ??
      null;
    const bodyStart = headerBlock.indexOf("AS $$");
    const definition =
      bodyStart >= 0 ? headerBlock.slice(bodyStart + 5).trim() : null;
    functions.push({
      name: m[1],
      args: m[2].replace(/\s+/g, " ").trim(),
      returns: m[3].trim(),
      language,
      security_definer,
      security_invoker: security_invoker || !security_definer,
      search_path,
      definition,
    });
  }

  for (const m of sql.matchAll(
    /CREATE (UNIQUE )?INDEX "([^"]+)" ON "public"\."([^"]+)" ([^;]+);/g
  )) {
    indexes.push({
      name: m[2],
      table: m[3],
      unique: Boolean(m[1]),
      definition: `CREATE ${m[1] || ""}INDEX "${m[2]}" ON "public"."${m[3]}" ${m[4]}`.trim(),
    });
  }

  for (const m of sql.matchAll(
    /ALTER TABLE ONLY "public"\."([^"]+)"\s+ADD CONSTRAINT "([^"]+)" ([^;]+);/g
  )) {
    let type = "UNKNOWN";
    const def = m[3];
    if (/PRIMARY KEY/i.test(def)) type = "PRIMARY KEY";
    else if (/FOREIGN KEY/i.test(def)) type = "FOREIGN KEY";
    else if (/UNIQUE/i.test(def)) type = "UNIQUE";
    else if (/CHECK/i.test(def)) type = "CHECK";
    else if (/EXCLUDE/i.test(def)) type = "EXCLUDE";
    alterConstraints.push({
      table: m[1],
      name: m[2],
      type,
      definition: def.trim(),
    });
  }

  for (const m of sql.matchAll(
    /ALTER TABLE "public"\."([^"]+)" ENABLE ROW LEVEL SECURITY;/g
  )) {
    rls[m[1]] = { ...(rls[m[1]] || {}), enabled: true };
  }
  for (const m of sql.matchAll(
    /ALTER TABLE "public"\."([^"]+)" FORCE ROW LEVEL SECURITY;/g
  )) {
    rls[m[1]] = { ...(rls[m[1]] || {}), forced: true };
  }

  for (const m of sql.matchAll(/CREATE POLICY "([^"]+)" ON "public"\."([^"]+)" ([^;]+);/g)) {
    const rest = m[3];
    const cmd = rest.match(/FOR (\w+)/)?.[1] ?? null;
    const roles = rest.match(/TO "([^"]+)"(?:,\s*"([^"]+)")*/);
    const roleList = [...rest.matchAll(/TO "([^"]+)"/g)].map((x) => x[1]);
    policies.push({
      name: m[1],
      table: m[2],
      cmd,
      roles: roleList,
      definition: rest.trim(),
    });
  }

  for (const m of sql.matchAll(
    /CREATE OR REPLACE TRIGGER "([^"]+)" ([^;]+);/g
  )) {
    triggers.push({ name: m[1], definition: m[2].trim() });
  }

  for (const m of sql.matchAll(/^GRANT (.+);$/gm)) {
    grants.push(m[1].trim());
  }

  const tableList = tableOrder.map((name) => ({
    ...tables[name],
    rls: rls[name] || { enabled: false, forced: false },
  }));

  return {
    enums,
    tables: tableList,
    functions,
    indexes,
    constraints: alterConstraints,
    policies,
    triggers,
    grants,
    sequences: [],
    counts: {
      table_count: tableList.length,
      enum_count: enums.length,
      function_count: functions.length,
      index_count: indexes.length,
      constraint_count: alterConstraints.length,
      policy_count: policies.length,
      trigger_count: triggers.length,
      grant_count: grants.length,
      sequence_count: 0,
      rls_enabled_count: Object.values(rls).filter((r) => r.enabled).length,
      rls_forced_count: Object.values(rls).filter((r) => r.forced).length,
      security_definer_count: functions.filter((f) => f.security_definer).length,
    },
  };
}

function phaseFromMigrationFile(filename) {
  const phaseMatch = filename.match(/phase(\d+)/i);
  if (phaseMatch) return Number(phaseMatch[1]);
  const version = filename.slice(0, 14);
  const prefix = version.slice(0, 8);
  const map = {
    "20260329": 1,
    "20260331": 3,
    "20260401": 4,
    "20260501": 5,
    "20260601": 6,
    "20260701": 7,
    "20260801": 8,
    "20260901": 9,
    "20261001": 10,
    "20261101": 11,
    "20261201": 12,
    "20261301": 13,
  };
  return map[prefix] ?? null;
}

function extractCreatesFromMigration(content) {
  const objects = [];
  const patterns = [
    { kind: "table", re: /create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-z_][a-z0-9_]*)"?/gi },
    { kind: "function", re: /create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?"?([a-z_][a-z0-9_]*)"?/gi },
    { kind: "type", re: /create\s+type\s+(?:public\.)?"?([a-z_][a-z0-9_]*)"?/gi },
    { kind: "policy", re: /create\s+policy\s+"?([a-z_][a-z0-9_]*)"?/gi },
    { kind: "index", re: /create\s+(?:unique\s+)?index\s+(?:if\s+not\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?/gi },
  ];
  for (const { kind, re } of patterns) {
    for (const m of content.matchAll(re)) {
      objects.push({ kind, name: m[1].toLowerCase() });
    }
  }
  return objects;
}

export function buildDomainMap(catalog) {
  const files = fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql"))
    .sort();

  const firstSeen = new Map();
  for (const file of files) {
    const body = fs.readFileSync(path.join(MIGRATIONS_DIR, file), "utf8");
    if (EMPTY_MIGRATION_RE.test(body)) continue;
    const phase = phaseFromMigrationFile(file);
    for (const obj of extractCreatesFromMigration(body)) {
      const key = `${obj.kind}:${obj.name}`;
      if (!firstSeen.has(key)) {
        firstSeen.set(key, {
          object: obj.name,
          kind: obj.kind,
          phase: phase ?? "UNCLASSIFIED",
          phase_label:
            phase && PHASE_LABELS[phase]
              ? PHASE_LABELS[phase]
              : "UNCLASSIFIED",
          first_migration: file,
          evidence: "CREATE in migration file",
        });
      }
    }
  }

  const stagingObjects = [];
  for (const t of catalog.tables) {
    stagingObjects.push({ kind: "table", name: t.name });
  }
  for (const e of catalog.enums) {
    stagingObjects.push({ kind: "type", name: e.name });
  }
  for (const f of catalog.functions) {
    stagingObjects.push({ kind: "function", name: f.name });
  }

  const mapped = [];
  const unclassified = [];
  for (const obj of stagingObjects) {
    const key = `${obj.kind}:${obj.name}`;
    const hit = firstSeen.get(key);
    if (hit) {
      mapped.push({ ...obj, ...hit });
    } else {
      unclassified.push({
        ...obj,
        phase: "UNCLASSIFIED",
        phase_label: "UNCLASSIFIED",
        first_migration: null,
        evidence: "not found in non-empty local migrations",
      });
    }
  }

  const byPhase = {};
  for (const row of mapped) {
    const p = String(row.phase);
    byPhase[p] = byPhase[p] || { label: row.phase_label, objects: [] };
    byPhase[p].objects.push({ kind: row.kind, name: row.name, first_migration: row.first_migration });
  }

  return {
    generated_at: new Date().toISOString(),
    staging_project_ref: "rpcpdrzbcclofvjpgldb",
    methodology:
      "Map staging catalog objects to phases 1–12 by first CREATE appearance in non-empty supabase/migrations/*.sql; UNCLASSIFIED when no local SQL evidence.",
    phase_labels: PHASE_LABELS,
    summary: {
      staging_object_count: stagingObjects.length,
      classified_count: mapped.length,
      unclassified_count: unclassified.length,
      by_phase: Object.fromEntries(
        Object.entries(byPhase).map(([k, v]) => [k, v.objects.length])
      ),
    },
    classified: mapped.sort((a, b) =>
      String(a.phase).localeCompare(String(b.phase)) ||
      a.kind.localeCompare(b.kind) ||
      a.name.localeCompare(b.name)
    ),
    unclassified: unclassified.sort(
      (a, b) => a.kind.localeCompare(b.kind) || a.name.localeCompare(b.name)
    ),
  };
}

const MIGRATION_NAME_HINTS = {
  "20260901190000_.sql": {
    tables: [],
    functions: [],
    types: [],
    policies: [],
    note:
      "NAME_HINT_NOT_PROOF — unnamed Phase 9 tail migration (after phase9_pos_fk_indexes); no slug tokens",
  },
  "20261001100000_phase10_tax_reference_core.sql": {
    tables: ["tax_jurisdictions", "tax_rule_sets", "tax_rule_versions", "tax_obligations"],
    types: ["tax_code", "tax_obligation_type", "tax_rule_status"],
    functions: ["tax_resolve_active_rule"],
  },
  "20261001110000_phase10_tax_registrations_rules.sql": {
    tables: ["organization_tax_registrations"],
    types: ["tax_registration_status"],
    functions: ["upsert_organization_tax_registration"],
  },
  "20261001120000_phase10_tax_periods.sql": {
    tables: ["tax_periods"],
    types: ["tax_period_status", "tax_workspace_environment"],
    functions: ["ensure_tax_period", "close_tax_period", "reopen_tax_period", "review_tax_period"],
  },
  "20261001130000_phase10_vat_classification_wp.sql": {
    tables: ["vat_purchase_classifications", "tax_withholdings_perceptions"],
    types: ["vat_credit_classification", "tax_wp_type", "tax_wp_status"],
    functions: ["register_tax_wp", "upsert_vat_purchase_classification"],
  },
  "20261001140000_phase10_tax_determinations.sql": {
    tables: [
      "tax_determinations",
      "tax_determination_lines",
      "tax_determination_sources",
      "tax_determination_rule_snapshots",
    ],
    types: ["tax_determination_status", "tax_determination_line_kind", "tax_source_domain"],
    functions: ["calculate_tax_determination", "revalidate_tax_determination_sources"],
  },
  "20261001150000_phase10_iibb.sql": {
    tables: ["iibb_cm_coefficients", "iibb_jurisdiction_allocations"],
    types: ["iibb_distribution_method", "iibb_sales_allocation_strategy", "tax_cm_form_code"],
    functions: ["upsert_iibb_jurisdiction_allocation"],
  },
  "20261001160000_phase10_filing_obligations.sql": {
    tables: ["tax_filing_records", "tax_payment_records", "tax_adjustments"],
    types: ["tax_filing_kind", "tax_filing_status", "tax_obligation_status"],
    functions: ["create_tax_obligation", "record_tax_filing_external", "record_tax_payment_external"],
  },
  "20261001170000_phase10_tax_helpers.sql": {
    functions: [
      "tax_assert_feature",
      "tax_assert_role",
      "tax_assert_service_role",
      "tax_canonical_fiscal_hash",
      "tax_canonical_purchase_hash",
      "tax_fiscal_vat_economic_sign",
      "tax_obligation_outstanding",
      "tax_resolve_effective_date",
      "tax_sha256",
    ],
  },
  "20261001180000_phase10_calculate_vat.sql": {
    functions: ["calculate_tax_period", "reconcile_vat_accounting"],
  },
  "20261001190000_phase10_period_filing_rpcs.sql": {
    functions: [
      "activate_tax_rule_version",
      "calculate_tax_determination",
      "calculate_tax_period",
      "close_tax_period",
      "create_tax_obligation",
      "ensure_tax_period",
      "record_tax_filing_external",
      "record_tax_payment_external",
      "reopen_tax_period",
      "review_tax_period",
    ],
  },
  "20261001200000_phase10_security.sql": {
    policies: ["tax_*"],
    note: "NAME_HINT_NOT_PROOF — security migration implies RLS/policies on tax relations",
  },
  "20261001210000_.sql": {
    note: "NAME_HINT_NOT_PROOF — unnamed Phase 10 placeholder; no slug tokens",
  },
  "20261001220000_.sql": {
    note: "NAME_HINT_NOT_PROOF — unnamed Phase 10 placeholder; no slug tokens",
  },
  "20261001230000_.sql": {
    note: "NAME_HINT_NOT_PROOF — unnamed Phase 10 placeholder; no slug tokens",
  },
  "20261001240000_.sql": {
    note: "NAME_HINT_NOT_PROOF — unnamed Phase 10 placeholder; no slug tokens",
  },
  "20261001250000_.sql": {
    note: "NAME_HINT_NOT_PROOF — unnamed Phase 10 placeholder; no slug tokens",
  },
  "20261001260000_.sql": {
    note: "NAME_HINT_NOT_PROOF — unnamed Phase 10 placeholder; no slug tokens",
  },
};

function nameHintsFromMigration(filename) {
  const preset = MIGRATION_NAME_HINTS[filename];
  if (preset) {
    return {
      tables: preset.tables || [],
      functions: preset.functions || [],
      types: preset.types || [],
      policies: preset.policies || [],
      note: preset.note || "NAME_HINT_NOT_PROOF",
    };
  }
  return {
    tables: [],
    functions: [],
    types: [],
    policies: [],
    note: "NAME_HINT_NOT_PROOF — no preset mapping",
  };
}

function catalogHas(catalog, kind, namePattern) {
  const re = new RegExp(
    "^" + namePattern.replace(/\*/g, ".*").replace(/\?/g, ".") + "$",
    "i"
  );
  if (kind === "table") return catalog.tables.filter((t) => re.test(t.name)).map((t) => t.name);
  if (kind === "function") return catalog.functions.filter((f) => re.test(f.name)).map((f) => f.name);
  if (kind === "type") return catalog.enums.filter((e) => re.test(e.name)).map((e) => e.name);
  if (kind === "policy") return catalog.policies.filter((p) => re.test(p.name)).map((p) => p.name);
  return [];
}

function objectsInLaterMigrations(afterVersion, catalogNames) {
  const files = fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql") && f.slice(0, 14) > afterVersion)
    .sort();
  const proven = [];
  for (const file of files) {
    const body = fs.readFileSync(path.join(MIGRATIONS_DIR, file), "utf8");
    if (EMPTY_MIGRATION_RE.test(body)) continue;
    const lower = body.toLowerCase();
    for (const name of catalogNames) {
      if (
        lower.includes(`create table public.${name}`) ||
        lower.includes(`create table ${name}`) ||
        lower.includes(`function public.${name}`) ||
        lower.includes(`function ${name}(`) ||
        lower.includes(`create type public.${name}`) ||
        lower.includes(`create type ${name}`) ||
        lower.includes(`on public.${name}`) ||
        lower.includes(`on ${name} `)
      ) {
        proven.push({ object: name, migration: file });
      }
    }
  }
  return proven;
}

export function buildPhase10Gap(catalog) {
  const files = fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql"))
    .sort();

  const emptyMigrations = files.filter((f) => {
    const body = fs.readFileSync(path.join(MIGRATIONS_DIR, f), "utf8");
    return EMPTY_MIGRATION_RE.test(body);
  });

  const targetVersions = new Set([
    "20260901190000",
    ...emptyMigrations
      .filter((f) => f.includes("phase10") || f.match(/^20261001/))
      .map((f) => f.slice(0, 14)),
  ]);

  const rows = [];
  for (const file of files) {
    const version = file.slice(0, 14);
    if (!targetVersions.has(version)) continue;
    const body = fs.readFileSync(path.join(MIGRATIONS_DIR, file), "utf8");
    if (!EMPTY_MIGRATION_RE.test(body)) continue;

    const hints = nameHintsFromMigration(file);
    const provenStaging = [];
    for (const name of hints.tables) {
      if (catalog.tables.some((t) => t.name === name)) provenStaging.push(name);
    }
    for (const name of hints.functions) {
      if (catalog.functions.some((f) => f.name === name)) provenStaging.push(name);
    }
    for (const name of hints.types) {
      if (catalog.enums.some((e) => e.name === name)) provenStaging.push(name);
    }
    for (const pat of hints.policies || []) {
      provenStaging.push(...catalogHas(catalog, "policy", pat));
    }

    const uniqueStaging = [...new Set(provenStaging)].sort();
    const later = objectsInLaterMigrations(version, uniqueStaging);
    const laterObjects = [...new Set(later.map((x) => x.object))];

    const hintedObjectCount =
      hints.tables.length + hints.functions.length + hints.types.length + (hints.policies?.length || 0);

    let recovery_policy;
    if (hintedObjectCount === 0) {
      recovery_policy = "BLOCKED_SEMANTIC_PROVENANCE";
    } else if (
      uniqueStaging.length > 0 &&
      laterObjects.length > 0 &&
      laterObjects.length >= uniqueStaging.length
    ) {
      recovery_policy = "PROVEN_BY_LATER_MIGRATIONS";
    } else if (uniqueStaging.length > 0) {
      recovery_policy = "RECOMMEND_CATALOG_RECOVERY";
    } else if (hintedObjectCount > 0) {
      recovery_policy = "RECOMMEND_CATALOG_RECOVERY";
    } else {
      recovery_policy = "BLOCKED_SEMANTIC_PROVENANCE";
    }

    rows.push({
      version,
      name: file,
      classification: "STAGING_HISTORY_WITHOUT_SQL_PAYLOAD",
      objects_expected_by_name: hints,
      objects_proven_in_staging_catalog: uniqueStaging,
      objects_proven_created_by_later_migrations: later,
      recovery_policy,
    });
  }

  const summary = {
    total_empty_analyzed: rows.length,
    recommend_catalog_recovery: rows.filter((r) => r.recovery_policy === "RECOMMEND_CATALOG_RECOVERY").length,
    proven_by_later_migrations: rows.filter((r) => r.recovery_policy === "PROVEN_BY_LATER_MIGRATIONS").length,
    blocked_semantic_provenance: rows.filter((r) => r.recovery_policy === "BLOCKED_SEMANTIC_PROVENANCE").length,
  };

  return {
    generated_at: new Date().toISOString(),
    staging_project_ref: "rpcpdrzbcclofvjpgldb",
    methodology:
      "Empty/noop local migrations compared to staging pg_dump catalog and later non-empty migrations. No SQL invented.",
    summary,
    migrations: rows,
  };
}

function localDryCheck() {
  const files = fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql"))
    .sort();
  const phase13Hardening = files.includes("20260909120000_phase13_hardening.sql");
  const phase13MovedAside = fs.existsSync(
    path.join(PHASE13_DIR, "forensics", "20260909120000_phase13_hardening.sql.bak")
  );
  return {
    migration_file_count: files.length,
    phase13_hardening_in_migrations: phase13Hardening,
    phase13_hardening_bak_present: phase13MovedAside,
    phase13_note: phase13Hardening
      ? "LOCAL_PRESENT in supabase/migrations"
      : phase13MovedAside
        ? "LOCAL_ONLY moved aside — docs/qa/phase13/forensics/20260909120000_phase13_hardening.sql.bak"
        : "not found locally",
    phase13_anon_acl: files.filter((f) => f.includes("phase13")),
  };
}

async function main() {
  if (!fs.existsSync(DUMP_PATH)) {
    throw new Error(
      `Missing dump at ${DUMP_PATH}. Run: node node_modules/supabase/dist/supabase.js db dump --project-ref rpcpdrzbcclofvjpgldb -s public -f docs/qa/phase13/forensics/staging-public-schema.sql`
    );
  }

  const sql = fs.readFileSync(DUMP_PATH, "utf8");
  const catalog = parseStagingDump(sql);

  const forensics = {
    generated_at: new Date().toISOString(),
    source: {
      type: "pg_dump_schema_parse",
      project_ref: "rpcpdrzbcclofvjpgldb",
      dump_path: path.relative(ROOT, DUMP_PATH).replace(/\\/g, "/"),
      schema: "public",
      read_only: true,
      tenant_row_data: false,
    },
    ...catalog,
    dry_check: localDryCheck(),
  };

  fs.mkdirSync(path.dirname(PHASE10_GAP_OUT), { recursive: true });
  fs.writeFileSync(FORENSICS_OUT, JSON.stringify(forensics, null, 2) + "\n");

  const domainMap = buildDomainMap(catalog);
  fs.writeFileSync(DOMAIN_MAP_OUT, JSON.stringify(domainMap, null, 2) + "\n");

  const phase10Gap = buildPhase10Gap(catalog);
  fs.writeFileSync(PHASE10_GAP_OUT, JSON.stringify(phase10Gap, null, 2) + "\n");

  console.log(
    JSON.stringify(
      {
        table_count: catalog.counts.table_count,
        expected_tables: 107,
        table_count_match: catalog.counts.table_count === 107,
        counts: catalog.counts,
        artifacts: {
          forensics: path.relative(ROOT, FORENSICS_OUT).replace(/\\/g, "/"),
          domain_map: path.relative(ROOT, DOMAIN_MAP_OUT).replace(/\\/g, "/"),
          phase10_gap: path.relative(ROOT, PHASE10_GAP_OUT).replace(/\\/g, "/"),
          dump: path.relative(ROOT, DUMP_PATH).replace(/\\/g, "/"),
        },
        phase10_gap_summary: phase10Gap.summary,
        dry_check: forensics.dry_check,
      },
      null,
      2
    )
  );
}

if (process.argv[1]?.endsWith("staging-schema-forensics.mjs")) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
