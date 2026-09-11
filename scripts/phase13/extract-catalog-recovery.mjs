/**
 * extract-catalog-recovery.mjs
 *
 * Reads staging-public-schema.sql and extracts DDL blocks for specified
 * objects (tables, enums, functions) in dependency-safe order.
 *
 * Writes:
 *   supabase/migrations/20260801205000_phase13_recover_phase8_products_inventory.sql
 *   supabase/migrations/20261001260500_phase13_recover_phase10_taxes.sql
 *   docs/qa/phase13/forensics/catalog-recovery-coverage.json
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '../..');

const SCHEMA_FILE = resolve(ROOT, 'docs/qa/phase13/forensics/staging-public-schema.sql');
const OUT_PHASE8  = resolve(ROOT, 'supabase/migrations/20260801205000_phase13_recover_phase8_products_inventory.sql');
const OUT_PHASE10 = resolve(ROOT, 'supabase/migrations/20261001260500_phase13_recover_phase10_taxes.sql');
const OUT_COVERAGE = resolve(ROOT, 'docs/qa/phase13/forensics/catalog-recovery-coverage.json');

// ---------------------------------------------------------------------------
// Target object lists
// ---------------------------------------------------------------------------
const PHASE8_ENUMS = [
  'product_type',
  'inventory_unit_code',
  'inventory_operation_type',
  'inventory_operation_status',
  'inventory_line_direction',
  'inventory_reservation_status',
  'inventory_accounting_status',
];

const PHASE8_TABLES = [
  'product_categories',
  'products',
  'warehouses',
  'inventory_operations',
  'inventory_operation_lines',
  'inventory_operation_sequences',
  'inventory_reservations',
  'inventory_stock_state',
  'inventory_cost_state',
  'inventory_ledger_entries',
  'inventory_accounting_mappings',
];

const PHASE8_FUNCTIONS = [
  'create_inventory_reservation',
  'post_inventory_operation',
  'reverse_inventory_operation',
  'next_inventory_operation_number',
  'deactivate_product',
  'ensure_inventory_chart_accounts',
  'ensure_inventory_cost_row',
  'ensure_inventory_stock_row',
  'inventory_assert_feature',
  'inventory_round_avg',
  'inventory_round_value',
  'prevent_inventory_ledger_mutation',
  'prevent_inventory_projection_client_write',
  'prevent_posted_inventory_line_mutation',
  'prevent_posted_inventory_op_mutation',
  'prevent_reservation_client_mutate',
  'release_inventory_reservation',
  'purchase_line_inventory_debit_account',
  // pos_assert_session_actor - Phase 9 handles this
  // finalize_pos_sale_impl   - staging-only refactor, Phase 9 uses finalize_pos_sale; SKIP
];

const PHASE10_ENUMS = [
  'iibb_distribution_method',
  'iibb_sales_allocation_strategy',
  'tax_adjustment_direction',
  'tax_adjustment_status',
  'tax_cm_form_code',
  'tax_code',
  'tax_determination_line_kind',
  'tax_determination_status',
  'tax_filing_kind',
  'tax_filing_status',
  'tax_obligation_status',
  'tax_obligation_type',
  'tax_period_status',
  'tax_registration_status',
  'tax_rule_status',
  'tax_source_domain',
  'tax_workspace_environment',
  'tax_wp_status',
  'tax_wp_type',
  'vat_credit_classification',
];

const PHASE10_TABLES = [
  'tax_jurisdictions',
  'tax_rule_sets',
  'tax_rule_versions',
  'organization_tax_registrations',
  'tax_periods',
  'tax_determinations',
  'tax_determination_sources',
  'tax_determination_lines',
  'tax_determination_rule_snapshots',
  'vat_purchase_classifications',
  'tax_obligations',
  'tax_filing_records',
  'tax_payment_records',
  'tax_adjustments',
  'tax_withholdings_perceptions',
  'iibb_cm_coefficients',
  'iibb_jurisdiction_allocations',
];

const PHASE10_FUNCTIONS = [
  'activate_tax_rule_version',
  'calculate_tax_determination',
  'calculate_tax_period',
  'close_tax_period',
  'create_tax_obligation',
  'ensure_tax_period',
  'reconcile_vat_accounting',
  'record_tax_filing_external',
  'record_tax_payment_external',
  'register_tax_wp',
  'reopen_tax_period',
  'revalidate_tax_determination_sources',
  'review_tax_period',
  'tax_assert_feature',
  'tax_assert_role',
  'tax_assert_service_role',
  'tax_canonical_fiscal_hash',
  'tax_canonical_purchase_hash',
  'tax_fiscal_vat_economic_sign',
  'tax_obligation_outstanding',
  'tax_resolve_active_rule',
  'tax_resolve_effective_date',
  'tax_sha256',
  'tax_test_fixture_purchase_iva_components',
  'upsert_iibb_jurisdiction_allocation',
  'upsert_organization_tax_registration',
  'upsert_vat_purchase_classification',
  'prevent_active_tax_rule_mutation',
  'prevent_tax_determination_client_mutation',
  'prevent_tax_filing_mutation',
  'prevent_tax_payment_mutation',
  'prevent_tax_period_status_forgery',
];

// ---------------------------------------------------------------------------
// Parser: split the dump into labeled blocks
// ---------------------------------------------------------------------------

/**
 * Each block represents a single DDL statement (or ALTER / GRANT cluster).
 * { kind, name, sql }
 */
function parseDump(src) {
  const blocks = [];
  // pg_dump separates top-level statements with blank lines; some multi-line
  // objects (functions with $$) span many lines. We split on "--\n\n" comment
  // boundaries and also detect statement starts.
  //
  // Strategy: collect lines into statements by tracking dollar-quoting
  // and statement termination.

  const lines = src.split('\n');
  let stmtLines = [];
  let dollarDepth = 0;
  let dollarTag = null;

  const flush = () => {
    if (stmtLines.length === 0) return;
    const sql = stmtLines.join('\n').trim();
    if (sql && sql !== '' && sql !== '--') {
      blocks.push(sql);
    }
    stmtLines = [];
  };

  for (const line of lines) {
    // Track dollar quoting
    if (dollarDepth === 0) {
      // Check for dollar quote opening
      const dqMatch = line.match(/(\$[^$]*\$)/g);
      if (dqMatch) {
        for (const dq of dqMatch) {
          dollarDepth++;
          dollarTag = dq;
        }
        // If even number, we opened and closed on same line
        if (dqMatch.length % 2 === 0) {
          dollarDepth = 0;
          dollarTag = null;
        }
      }
      stmtLines.push(line);
      // Ends with semicolon outside dollar quoting?
      if (dollarDepth === 0 && line.trimEnd().endsWith(';')) {
        flush();
      }
    } else {
      stmtLines.push(line);
      // Check if dollar tag closes
      if (dollarTag && line.includes(dollarTag)) {
        dollarDepth = 0;
        dollarTag = null;
        // The closing line may still have the semicolon after $$;
        if (line.trimEnd().endsWith(';')) {
          flush();
        }
      }
    }
  }
  flush();

  return blocks;
}

/**
 * Classify a block by kind and extract the primary object name.
 */
function classifyBlock(sql) {
  const first = sql.split('\n')[0].trim();

  // Ignore SET / SELECT pg_catalog / COMMENT ON SCHEMA / pure comments
  if (/^(SET |SELECT pg_catalog|--|\s*$)/.test(first)) return null;
  if (/^COMMENT ON SCHEMA/.test(first)) return null;
  if (/^(ALTER SCHEMA|CREATE SCHEMA)/.test(first)) return null;

  // CREATE TYPE ... AS ENUM
  let m = sql.match(/CREATE TYPE\s+"public"\."([^"]+)"\s+AS ENUM/);
  if (m) return { kind: 'enum', name: m[1], sql };

  // CREATE TABLE
  m = sql.match(/CREATE TABLE(?:\s+IF NOT EXISTS)?\s+"public"\."([^"]+)"/);
  if (m) return { kind: 'table', name: m[1], sql };

  // CREATE SEQUENCE
  m = sql.match(/CREATE SEQUENCE(?:\s+IF NOT EXISTS)?\s+"public"\."([^"]+)"/);
  if (m) return { kind: 'sequence', name: m[1], sql };

  // CREATE OR REPLACE FUNCTION / CREATE FUNCTION
  m = sql.match(/CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+"public"\."([^"]+)"/);
  if (m) return { kind: 'function', name: m[1], sql };

  // ALTER TABLE ... (OWNER TO, ADD CONSTRAINT, ENABLE ROW LEVEL SECURITY, etc.)
  m = sql.match(/ALTER TABLE(?:\s+ONLY)?\s+"public"\."([^"]+)"/);
  if (m) return { kind: 'alter_table', name: m[1], sql };

  // ALTER SEQUENCE
  m = sql.match(/ALTER SEQUENCE\s+"public"\."([^"]+)"/);
  if (m) return { kind: 'alter_sequence', name: m[1], sql };

  // ALTER TYPE (OWNER)
  m = sql.match(/ALTER TYPE\s+"public"\."([^"]+)"/);
  if (m) return { kind: 'alter_type', name: m[1], sql };

  // CREATE INDEX
  m = sql.match(/CREATE(?:\s+UNIQUE)?\s+INDEX(?:\s+CONCURRENTLY)?(?:\s+IF NOT EXISTS)?\s+\S+\s+ON(?:\s+ONLY)?\s+"public"\."([^"]+)"/);
  if (m) return { kind: 'index', name: m[1], sql };

  // CREATE TRIGGER
  m = sql.match(/CREATE(?:\s+OR\s+REPLACE)?\s+TRIGGER\s+\S+\s+\w+\s+\w+\s+(?:ON|BEFORE|AFTER)\s+"public"\."([^"]+)"/i);
  if (!m) m = sql.match(/ON\s+"public"\."([^"]+)"/);
  if (m && /CREATE.*TRIGGER/.test(sql)) return { kind: 'trigger', name: m[1], sql };

  // CREATE POLICY
  m = sql.match(/CREATE POLICY\s+\S+\s+ON\s+"public"\."([^"]+)"/);
  if (m) return { kind: 'policy', name: m[1], sql };

  // GRANT / REVOKE on TABLE
  m = sql.match(/GRANT\s+\S[^\n]*\s+ON\s+TABLE\s+"public"\."([^"]+)"/);
  if (m) return { kind: 'grant_table', name: m[1], sql };

  // GRANT / REVOKE on FUNCTION
  m = sql.match(/GRANT\s+\S[^\n]*\s+ON\s+FUNCTION\s+"public"\."([^"]+)"/);
  if (m) return { kind: 'grant_function', name: m[1], sql };

  // REVOKE on TABLE
  m = sql.match(/REVOKE\s+\S[^\n]*\s+ON\s+TABLE\s+"public"\."([^"]+)"/);
  if (m) return { kind: 'revoke_table', name: m[1], sql };

  // REVOKE on FUNCTION
  m = sql.match(/REVOKE\s+\S[^\n]*\s+ON\s+FUNCTION\s+"public"\."([^"]+)"/);
  if (m) return { kind: 'revoke_function', name: m[1], sql };

  // SELECT pg_catalog... (noise)
  if (/^SELECT /.test(first)) return null;
  if (/^COMMENT ON /.test(first)) return null; // skip COMMENTs for brevity

  return null;
}

// ---------------------------------------------------------------------------
// Main extraction logic
// ---------------------------------------------------------------------------

function extractForDomain(allBlocks, targetEnums, targetTables, targetFunctions) {
  const enumSet = new Set(targetEnums);
  const tableSet = new Set(targetTables);
  const funcSet = new Set(targetFunctions);

  // We emit in dependency order:
  // 1. enums (types)
  // 2. sequences owned by target tables
  // 3. tables
  // 4. alter_table OWNER / primary constraints
  // 5. functions
  // 6. indexes on target tables
  // 7. triggers on target tables
  // 8. enable RLS
  // 9. policies
  // 10. grants / revokes

  const sections = {
    enums: [],
    alter_type: [],
    sequences: [],
    tables: [],
    alter_owner: [],    // ALTER TABLE ... OWNER
    alter_pk: [],       // ALTER TABLE ADD CONSTRAINT PRIMARY KEY
    alter_fk: [],       // ALTER TABLE ADD CONSTRAINT FOREIGN KEY
    alter_unique: [],   // ALTER TABLE ADD CONSTRAINT UNIQUE
    alter_check: [],    // ALTER TABLE ADD CONSTRAINT CHECK
    alter_rls: [],      // ALTER TABLE ENABLE ROW LEVEL SECURITY
    functions: [],
    indexes: [],
    triggers: [],
    policies: [],
    grants: [],
  };

  const covered = { enums: [], tables: [], functions: [], skipped: [] };

  for (const block of allBlocks) {
    const cls = classifyBlock(block);
    if (!cls) continue;
    const { kind, name, sql } = cls;

    switch (kind) {
      case 'enum':
        if (enumSet.has(name)) {
          sections.enums.push(sql);
          covered.enums.push(name);
        }
        break;

      case 'alter_type':
        if (enumSet.has(name)) sections.alter_type.push(sql);
        break;

      case 'sequence':
        // sequences often named like tablename_col_seq; check if any target table prefix matches
        if ([...tableSet].some(t => name.startsWith(t + '_') || name === t)) {
          sections.sequences.push(sql);
        }
        break;

      case 'table':
        if (tableSet.has(name)) {
          sections.tables.push(sql);
          covered.tables.push(name);
        }
        break;

      case 'alter_table': {
        if (!tableSet.has(name)) break;
        // Classify ALTER TABLE subtype
        if (/OWNER TO/.test(sql)) {
          sections.alter_owner.push(sql);
        } else if (/ENABLE ROW LEVEL SECURITY/.test(sql) || /FORCE ROW LEVEL SECURITY/.test(sql)) {
          sections.alter_rls.push(sql);
        } else if (/ADD CONSTRAINT .+ PRIMARY KEY/.test(sql)) {
          sections.alter_pk.push(sql);
        } else if (/ADD CONSTRAINT .+ FOREIGN KEY/.test(sql)) {
          sections.alter_fk.push(sql);
        } else if (/ADD CONSTRAINT .+ UNIQUE/.test(sql)) {
          sections.alter_unique.push(sql);
        } else if (/ADD CONSTRAINT .+ CHECK/.test(sql)) {
          sections.alter_check.push(sql);
        } else {
          // Other ALTER (e.g. SET DEFAULT, etc.)
          sections.alter_pk.push(sql);
        }
        break;
      }

      case 'alter_sequence':
        if ([...tableSet].some(t => name.startsWith(t + '_') || name === t)) {
          sections.sequences.push(sql);
        }
        break;

      case 'function':
        if (funcSet.has(name)) {
          sections.functions.push(sql);
          covered.functions.push(name);
        }
        break;

      case 'index':
        if (tableSet.has(name)) sections.indexes.push(sql);
        break;

      case 'trigger':
        if (tableSet.has(name)) sections.triggers.push(sql);
        break;

      case 'policy':
        if (tableSet.has(name)) sections.policies.push(sql);
        break;

      case 'grant_table':
      case 'revoke_table':
        if (tableSet.has(name)) sections.grants.push(sql);
        break;

      case 'grant_function':
      case 'revoke_function':
        if (funcSet.has(name)) sections.grants.push(sql);
        break;
    }
  }

  // Compute missing
  for (const e of targetEnums) {
    if (!covered.enums.includes(e)) covered.skipped.push({ object: e, kind: 'enum', reason: 'NOT_FOUND_IN_DUMP' });
  }
  for (const t of targetTables) {
    if (!covered.tables.includes(t)) covered.skipped.push({ object: t, kind: 'table', reason: 'NOT_FOUND_IN_DUMP' });
  }
  for (const f of targetFunctions) {
    if (!covered.functions.includes(f)) covered.skipped.push({ object: f, kind: 'function', reason: 'NOT_FOUND_IN_DUMP' });
  }

  // Assemble output SQL
  const parts = [
    ...sections.enums,
    ...sections.alter_type,
    ...sections.sequences,
    ...sections.tables,
    ...sections.alter_owner,
    ...sections.alter_pk,
    ...sections.alter_unique,
    ...sections.alter_check,
    ...sections.functions,
    ...sections.indexes,
    ...sections.triggers,
    ...sections.alter_rls,
    ...sections.policies,
    ...sections.grants,
    ...sections.alter_fk,  // FK last (after all tables created)
  ];

  return { sql: parts.join('\n\n'), covered, sections };
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

console.log('Reading staging schema dump...');
const schemaSrc = readFileSync(SCHEMA_FILE, 'utf8');

console.log('Parsing dump into blocks...');
const allBlocks = parseDump(schemaSrc);
console.log(`  Parsed ${allBlocks.length} blocks`);

// ---------------------------------------------------------------------------
// Phase 8
// ---------------------------------------------------------------------------
console.log('\nExtracting Phase 8 objects...');
const p8 = extractForDomain(allBlocks, PHASE8_ENUMS, PHASE8_TABLES, PHASE8_FUNCTIONS);

const PHASE8_HEADER = `-- ORIGINAL_MIGRATION_SQL_UNAVAILABLE
-- RECOVERED_FROM_STAGING_CATALOG
-- SOURCE_OBJECTS: product_categories, products, warehouses, inventory_operations,
--   inventory_operation_lines, inventory_operation_sequences, inventory_reservations,
--   inventory_stock_state, inventory_cost_state, inventory_ledger_entries,
--   inventory_accounting_mappings + enums (product_type, inventory_unit_code,
--   inventory_operation_type, inventory_operation_status, inventory_line_direction,
--   inventory_reservation_status, inventory_accounting_status) + inventory functions
-- SOURCE = docs/qa/phase13/forensics/staging-public-schema.sql
-- STAGING_PROJECT = rpcpdrzbcclofvjpgldb
-- RATIONALE: Phase 8 migration files 20260801100000-20260801200000 contained corrupt
--   '{q}' payloads (non-executable). This forward migration recovers all Phase 8
--   inventory/product DDL from the authoritative staging catalog dump.
--   Sorting: AFTER 20260801200000 (last Phase 8 slot), BEFORE 20260901100000 (Phase 9).
--   Do not edit semantic behavior; DDL is verbatim from staging catalog.

`;

const phase8Out = PHASE8_HEADER + p8.sql + '\n';
writeFileSync(OUT_PHASE8, phase8Out, 'utf8');
console.log(`  Written: ${OUT_PHASE8}`);
console.log(`  Enums covered: ${p8.covered.enums.length}/${PHASE8_ENUMS.length}`);
console.log(`  Tables covered: ${p8.covered.tables.length}/${PHASE8_TABLES.length}`);
console.log(`  Functions covered: ${p8.covered.functions.length}/${PHASE8_FUNCTIONS.length}`);
if (p8.covered.skipped.length) console.log(`  Skipped:`, p8.covered.skipped);

// ---------------------------------------------------------------------------
// Phase 10
// ---------------------------------------------------------------------------
console.log('\nExtracting Phase 10 objects...');
const p10 = extractForDomain(allBlocks, PHASE10_ENUMS, PHASE10_TABLES, PHASE10_FUNCTIONS);

const PHASE10_HEADER = `-- ORIGINAL_MIGRATION_SQL_UNAVAILABLE
-- RECOVERED_FROM_STAGING_CATALOG
-- SOURCE_OBJECTS: tax_jurisdictions, tax_rule_sets, tax_rule_versions,
--   organization_tax_registrations, tax_periods, tax_determinations,
--   tax_determination_sources, tax_determination_lines,
--   tax_determination_rule_snapshots, vat_purchase_classifications,
--   tax_obligations, tax_filing_records, tax_payment_records, tax_adjustments,
--   tax_withholdings_perceptions, iibb_cm_coefficients,
--   iibb_jurisdiction_allocations + tax/iibb enums + tax functions
-- SOURCE = docs/qa/phase13/forensics/staging-public-schema.sql
-- STAGING_PROJECT = rpcpdrzbcclofvjpgldb
-- RATIONALE: Phase 10 migration files 20261001210000-20261001260000 contained corrupt
--   ';' (empty) payloads. This forward migration recovers all Phase 10 tax DDL
--   from the authoritative staging catalog dump.
--   Sorting: AFTER 20261001260000 (last empty Phase 10 slot) as 20261001260500,
--   BEFORE 20261001270000 (phase10_hardening_fixture_counterparty_reuse).
--   Do not edit semantic behavior; DDL is verbatim from staging catalog.
-- SKIPPED: finalize_pos_sale_impl (staging-only refactor; Phase 9 uses
--   finalize_pos_sale; not required for cleanroom correctness).

`;

const phase10Out = PHASE10_HEADER + p10.sql + '\n';
writeFileSync(OUT_PHASE10, phase10Out, 'utf8');
console.log(`  Written: ${OUT_PHASE10}`);
console.log(`  Enums covered: ${p10.covered.enums.length}/${PHASE10_ENUMS.length}`);
console.log(`  Tables covered: ${p10.covered.tables.length}/${PHASE10_TABLES.length}`);
console.log(`  Functions covered: ${p10.covered.functions.length}/${PHASE10_FUNCTIONS.length}`);
if (p10.covered.skipped.length) console.log(`  Skipped:`, p10.covered.skipped);

// ---------------------------------------------------------------------------
// Coverage JSON
// ---------------------------------------------------------------------------
const coverage = {
  generated_at: new Date().toISOString(),
  phase8: {
    enums: { target: PHASE8_ENUMS.length, covered: p8.covered.enums.length, objects: p8.covered.enums },
    tables: { target: PHASE8_TABLES.length, covered: p8.covered.tables.length, objects: p8.covered.tables },
    functions: { target: PHASE8_FUNCTIONS.length, covered: p8.covered.functions.length, objects: p8.covered.functions },
    skipped: p8.covered.skipped,
    output_file: '20260801205000_phase13_recover_phase8_products_inventory.sql',
  },
  phase10: {
    enums: { target: PHASE10_ENUMS.length, covered: p10.covered.enums.length, objects: p10.covered.enums },
    tables: { target: PHASE10_TABLES.length, covered: p10.covered.tables.length, objects: p10.covered.tables },
    functions: { target: PHASE10_FUNCTIONS.length, covered: p10.covered.functions.length, objects: p10.covered.functions },
    skipped: p10.covered.skipped,
    output_file: '20261001260500_phase13_recover_phase10_taxes.sql',
  },
  explicitly_skipped: [
    { object: 'finalize_pos_sale_impl', kind: 'function', reason: 'STAGING_ONLY_REFACTOR — Phase 9 calls finalize_pos_sale; impl variant not required for cleanroom correctness' },
    { object: 'pos_assert_session_actor', kind: 'function', reason: 'Phase 9 domain function — provided by substantive Phase 9 migrations' },
  ],
};
writeFileSync(OUT_COVERAGE, JSON.stringify(coverage, null, 2), 'utf8');
console.log(`\nCoverage JSON written: ${OUT_COVERAGE}`);
console.log('\nDone.');
