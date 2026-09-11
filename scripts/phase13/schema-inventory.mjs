#!/usr/bin/env node
/**
 * Exact schema inventory from local disposable DB (clean-room source of truth).
 */
import fs from "node:fs";
import path from "node:path";
import { withDb } from "./db.mjs";
import { PHASE13_DIR } from "./env.mjs";

export async function inventorySchema() {
  return withDb(async (client) => {
    const tables = (
      await client.query(`
        select table_name
        from information_schema.tables
        where table_schema='public' and table_type='BASE TABLE'
        order by 1`)
    ).rows.map((r) => r.table_name);

    const views = (
      await client.query(`
        select table_name
        from information_schema.views
        where table_schema='public'
        order by 1`)
    ).rows.map((r) => r.table_name);

    const enums = (
      await client.query(`
        select t.typname as name,
               array_agg(e.enumlabel order by e.enumsortorder) as labels
        from pg_type t
        join pg_enum e on e.enumtypid = t.oid
        join pg_namespace n on n.oid = t.typnamespace
        where n.nspname='public'
        group by t.typname
        order by 1`)
    ).rows;

    const functions = (
      await client.query(`
        select p.proname as name,
               pg_get_function_identity_arguments(p.oid) as args,
               p.prosecdef as security_definer,
               p.prorettype::regtype::text as returns,
               coalesce(p.proconfig, array[]::text[]) as config,
               has_function_privilege('authenticated', p.oid, 'EXECUTE') as exec_authenticated,
               has_function_privilege('anon', p.oid, 'EXECUTE') as exec_anon
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname='public'
        order by 1, 2`)
    ).rows;

    const constraints = (
      await client.query(`
        select table_name, constraint_name, constraint_type
        from information_schema.table_constraints
        where table_schema='public'
          and not (constraint_type='CHECK' and constraint_name ~ '^[0-9]+_[0-9]+_[0-9]+_not_null$')
        order by 1, 2`)
    ).rows;

    const policies = (
      await client.query(`
        select tablename, policyname, cmd, roles::text, qual, with_check
        from pg_policies
        where schemaname='public'
        order by 1, 2`)
    ).rows;

    const features = (
      await client.query(`
        select code, name, default_status, category, active
        from public.feature_catalog
        order by sort_order`)
    ).rows;

    const appSettings = (
      await client.query(`select key, value from public.app_settings order by 1`)
    ).rows;

    return {
      generated_at: new Date().toISOString(),
      tables,
      views,
      enums,
      functions,
      constraints,
      policies,
      feature_catalog: features,
      app_settings: appSettings,
      counts: {
        tables: tables.length,
        views: views.length,
        enums: enums.length,
        functions: functions.length,
        functions_exec_authenticated: functions.filter((f) => f.exec_authenticated)
          .length,
        security_definer: functions.filter((f) => f.security_definer).length,
        constraints: constraints.length,
        policies: policies.length,
      },
    };
  });
}

const GOLDEN_STEPS = [
  { id: "organization", candidates: ["organizations"] },
  { id: "membership_bootstrap", candidates: ["organization_members"] },
  { id: "modules_entitlements", candidates: ["feature_catalog", "organization_features"] },
  {
    id: "customer",
    candidates: ["customers", "parties", "counterparties", "clients", "partners"],
  },
  {
    id: "supplier",
    candidates: ["suppliers", "vendors", "parties", "counterparties"],
  },
  {
    id: "product",
    candidates: ["products", "items", "sku", "inventory_items", "goods"],
  },
  {
    id: "sale_order",
    candidates: [
      "sales_documents",
      "sales_orders",
      "sales_invoices",
      "orders",
      "invoices",
    ],
  },
  {
    id: "purchase",
    candidates: [
      "purchase_documents",
      "purchase_orders",
      "purchases",
      "payables",
      "expenses",
    ],
  },
  {
    id: "treasury_payment",
    candidates: [
      "treasury_operations",
      "treasury_accounts",
      "treasury_operation_legs",
      "payments",
      "cash_sessions",
      "cash_movements",
      "bank_accounts",
      "treasury_transactions",
      "collections",
    ],
  },
  {
    id: "inventory_impact",
    candidates: [
      "inventory_operations",
      "inventory_ledger_entries",
      "inventory_stock_state",
      "stock_movements",
      "inventory_movements",
      "inventory_ledger",
      "warehouse_stocks",
    ],
  },
  {
    id: "accounting_journal",
    candidates: [
      "journal_entries",
      "journal_lines",
      "ledger_entries",
      "accounts",
      "chart_of_accounts",
    ],
  },
  {
    id: "taxes_projection",
    candidates: [
      "tax_books",
      "tax_liquidations",
      "tax_determinations",
      "iva_books",
      "tax_lines",
    ],
  },
  {
    id: "dashboard_reporting",
    candidates: ["kpi_snapshots", "management_metrics", "reports"],
  },
];

export function classifyGoldenSteps(inventory) {
  const tableSet = new Set(inventory.tables);
  return GOLDEN_STEPS.map((step) => {
    const found = step.candidates.filter((c) => tableSet.has(c));
    if (found.length) {
      return {
        step: step.id,
        determination: "A_EXISTS",
        objects: found,
        note: found[0] === step.candidates[0] ? "canonical name" : "alternate name",
      };
    }
    // Partial Phase-1 substitutes that must NOT be treated as operational domain
    const phase1Adjacent = {
      modules_entitlements: ["feature_catalog", "organization_features"],
      dashboard_reporting: null, // dashboard is app-layer over org completeness, no KPI table
    };
    if (step.id === "organization" || step.id === "membership_bootstrap") {
      return {
        step: step.id,
        determination: "D_MISSING_MIGRATION",
        objects: [],
        note: "unexpected — should exist in Phase 1",
      };
    }
    if (step.id === "modules_entitlements") {
      const ok = phase1Adjacent.modules_entitlements.every((t) => tableSet.has(t));
      return {
        step: step.id,
        determination: ok ? "A_EXISTS" : "D_MISSING_MIGRATION",
        objects: ok ? phase1Adjacent.modules_entitlements : [],
        note: "Phase 1 entitlements catalog (not operational modules runtime)",
      };
    }
    if (step.id === "dashboard_reporting") {
      // App dashboard reads organizations/fiscal/branches — no reporting warehouse
      const dashDeps = ["organizations", "fiscal_profiles", "branches", "business_profiles"];
      const ok = dashDeps.every((t) => tableSet.has(t));
      return {
        step: step.id,
        determination: ok ? "C_TEST_OBSOLETE_FOR_KPI_WAREHOUSE" : "D_MISSING_MIGRATION",
        objects: ok ? dashDeps : [],
        note:
          "Setup-completeness dashboard exists in app over Phase 1 tables; no posted-KPI/reporting warehouse tables",
        real_contract: "app_dashboard_setup_completeness",
      };
    }
    return {
      step: step.id,
      determination: "D_MISSING_MIGRATION",
      objects: [],
      note: `No public table among candidates: ${step.candidates.join(", ")}. Feature catalog may list the module as disabled/coming_soon only.`,
      feature_flags: inventory.feature_catalog
        .filter((f) =>
          JSON.stringify(step.candidates).includes(f.code) ||
          ["customers", "suppliers", "sales", "purchases", "inventory", "pos", "cash", "banks", "accounting", "taxes", "reports"].some(
            (c) => step.id.includes(c.replace(/s$/, "")) || f.code === c
          )
        )
        .map((f) => ({ code: f.code, default_status: f.default_status })),
    };
  });
}

async function main() {
  fs.mkdirSync(PHASE13_DIR, { recursive: true });
  const inventory = await inventorySchema();
  const golden = classifyGoldenSteps(inventory);
  const missing = golden.filter((g) =>
    String(g.determination).startsWith("D_")
  );
  const out = {
    inventory,
    golden_step_classification: golden,
    blocked_steps: missing.map((m) => m.step),
    verdict:
      missing.filter((m) =>
        ![
          "organization",
          "membership_bootstrap",
          "modules_entitlements",
        ].includes(m.step)
      ).length > 0
        ? "BLOCKED_MISSING_MIGRATION_OPERATIONAL_DOMAINS"
        : "READY",
  };
  const file = path.join(PHASE13_DIR, "schema-inventory.json");
  fs.writeFileSync(file, JSON.stringify(out, null, 2) + "\n");
  console.log(JSON.stringify({
    counts: inventory.counts,
    verdict: out.verdict,
    blocked_steps: out.blocked_steps,
    file,
  }, null, 2));
}

if (process.argv[1]?.endsWith("schema-inventory.mjs")) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
