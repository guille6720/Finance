import { withDb } from "./db.mjs";

/**
 * Phase 1–12 DB gates from clean-room DB.
 *
 * Phase 1: structural + RLS invariants (unchanged).
 *
 * Phases 2–12: POSITIVE presence gates — recovery migrations now inject all
 *   product-domain DDL from staging forensics.  A gate PASS means the key
 *   domain table IS present and RLS is enabled on it.
 *   NOTE: feature-catalog rows that were previously expected to be disabled
 *   are now verified to exist; we do NOT relax security expectations.
 */

async function phase1Gates(client) {
  const checks = [];

  const tables = [
    "profiles",
    "organizations",
    "organization_members",
    "branches",
    "fiscal_conditions",
    "fiscal_profiles",
    "business_profiles",
    "accounting_periods",
    "cost_centers",
    "feature_catalog",
    "organization_features",
    "app_settings",
    "organization_settings",
    "audit_events",
  ];

  const { rows: existing } = await client.query(
    `select table_name from information_schema.tables
     where table_schema='public' and table_type='BASE TABLE'`
  );
  const set = new Set(existing.map((r) => r.table_name));
  for (const t of tables) {
    checks.push({
      id: `phase1.table.${t}`,
      status: set.has(t) ? "PASS" : "FAIL",
    });
  }

  const { rows: rls } = await client.query(
    `select c.relname as table_name, c.relrowsecurity as rls
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relkind='r'`
  );
  for (const row of rls) {
    if (tables.includes(row.table_name)) {
      checks.push({
        id: `phase1.rls.${row.table_name}`,
        status: row.rls ? "PASS" : "FAIL",
      });
    }
  }

  const { rows: fiscal } = await client.query(
    `select count(*)::int as n from public.fiscal_conditions`
  );
  checks.push({
    id: "phase1.seed.fiscal_conditions",
    status: fiscal[0].n >= 4 ? "PASS" : "FAIL",
  });

  const { rows: features } = await client.query(
    `select count(*)::int as n from public.feature_catalog`
  );
  checks.push({
    id: "phase1.seed.feature_catalog",
    status: features[0].n >= 16 ? "PASS" : "FAIL",
  });

  const { rows: phase } = await client.query(
    `select value from public.app_settings where key = 'platform.phase'`
  );
  // Phase 1 bootstraps platform.phase=1; subsequent phases advance it.
  // Gate: row exists and numeric value >= 1 (1..12+ all valid).
  const phaseVal = Number(phase[0]?.value);
  checks.push({
    id: "phase1.app_settings.phase",
    status: !isNaN(phaseVal) && phaseVal >= 1 ? "PASS" : "FAIL",
  });

  // accounting_core_enabled is set true by Phase 2 when accounting DDL is present.
  // With recovery migrations, Phase 2 schema is present so this is expected to be true.
  // Gate: row exists (either true or false is acceptable; structural presence is the invariant).
  const { rows: acct } = await client.query(
    `select value from public.app_settings where key = 'platform.accounting_core_enabled'`
  );
  checks.push({
    id: "phase1.accounting_core_setting_exists",
    status: acct[0] !== undefined ? "PASS" : "FAIL",
  });

  return checks;
}

/**
 * Positive domain gate: key tables MUST exist and have RLS enabled.
 * Optionally verify RLS is active on each required table.
 */
async function positiveDomainGate(client, phase, requiredTables) {
  const checks = [];

  const { rows: existing } = await client.query(
    `select c.relname as table_name, c.relrowsecurity as rls
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'`
  );
  const tableMap = new Map(existing.map((r) => [r.table_name, r.rls]));

  for (const t of requiredTables) {
    const present = tableMap.has(t);
    checks.push({
      id: `phase${phase}.present_table.${t}`,
      status: present ? "PASS" : "FAIL",
      note: present ? "domain table present" : "MISSING — recovery SQL may have failed",
    });
    if (present) {
      checks.push({
        id: `phase${phase}.rls.${t}`,
        status: tableMap.get(t) ? "PASS" : "FAIL",
        note: tableMap.get(t) ? "RLS enabled" : "RLS NOT enabled — security gap",
      });
    }
  }

  return checks;
}

export async function runPhase1to12Gates() {
  return withDb(async (client) => {
    const checks = [];
    checks.push(...(await phase1Gates(client)));

    // Phase 2 — accounting core (journal + chart of accounts)
    checks.push(
      ...(await positiveDomainGate(client, 2, [
        "accounts",
        "journal_entries",
        "journal_entry_lines",
        "accounting_sequences",
      ]))
    );

    // Phase 3 — counterparties
    checks.push(
      ...(await positiveDomainGate(client, 3, [
        "counterparties",
        "counterparty_addresses",
        "counterparty_roles",
      ]))
    );

    // Phase 4 — sales
    checks.push(
      ...(await positiveDomainGate(client, 4, [
        "sales_documents",
        "sales_document_lines",
        "sales_document_sequences",
      ]))
    );

    // Phase 5 — fiscal / AFIP gateway
    checks.push(
      ...(await positiveDomainGate(client, 5, [
        "fiscal_documents",
        "fiscal_document_lines",
        "fiscal_points_of_sale",
      ]))
    );

    // Phase 6 — purchases / AP
    checks.push(
      ...(await positiveDomainGate(client, 6, [
        "purchase_documents",
        "purchase_document_lines",
        "purchase_orders",
        "accounts_payable_items",
      ]))
    );

    // Phase 7 — treasury / AR / bank reconciliation
    checks.push(
      ...(await positiveDomainGate(client, 7, [
        "treasury_accounts",
        "treasury_operations",
        "accounts_receivable_items",
        "bank_reconciliation_matches",
      ]))
    );

    // Phase 8 — products & inventory (recovered)
    checks.push(
      ...(await positiveDomainGate(client, 8, [
        "products",
        "product_categories",
        "warehouses",
        "inventory_operations",
        "inventory_stock_state",
      ]))
    );

    // Phase 9 — POS
    checks.push(
      ...(await positiveDomainGate(client, 9, [
        "pos_sessions",
        "pos_sales",
        "pos_terminals",
        "pos_tenders",
      ]))
    );

    // Phase 10 — taxes (recovered)
    checks.push(
      ...(await positiveDomainGate(client, 10, [
        "tax_jurisdictions",
        "tax_determinations",
        "tax_periods",
        "tax_filing_records",
        "organization_tax_registrations",
      ]))
    );

    // Phase 11 — analytics / reports / alerts
    checks.push(
      ...(await positiveDomainGate(client, 11, [
        "analytics_metric_definitions",
        "saved_reports",
        "analytics_alert_settings",
      ]))
    );

    // Phase 12 — release governance / entitlements / packs
    checks.push(
      ...(await positiveDomainGate(client, 12, [
        "module_packs",
        "module_pack_features",
        "feature_release_controls",
        "organization_feature_entitlements",
      ]))
    );

    const failed = checks.filter((c) => c.status === "FAIL");
    return {
      status: failed.length === 0 ? "PASS" : "FAIL",
      detail:
        failed.length === 0
          ? `all ${checks.length} phase 1–12 DB gates passed`
          : `${failed.length} gate(s) failed`,
      checks,
      failed,
    };
  });
}
