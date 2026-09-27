/**
 * Post-seed verification for the synthetic demo dataset (LOCAL / STAGING only).
 * Read-only: every query is a SELECT. Readiness is derived from database
 * postconditions, never from per-run counters.
 */

import { DEMO_CODES, DEMO_SETTINGS_KEYS } from "./guards.mjs";

/**
 * Duplicate detectors keyed by the deterministic identifiers the seed uses.
 * Each query receives $1 = demo organization ids and returns one row per duplicated key.
 */
export const DEMO_DUPLICATE_CHECKS = Object.freeze([
  {
    entity: "ORGANIZATIONS",
    sql: `SELECT value #>> '{}' AS k, count(*)::int AS n
          FROM public.organization_settings
          WHERE key = '${DEMO_SETTINGS_KEYS.CODE}'
          GROUP BY 1 HAVING count(*) > 1`,
    scoped: false,
  },
  {
    entity: "MEMBERS",
    sql: `SELECT organization_id, user_id, count(*)::int AS n
          FROM public.organization_members
          WHERE organization_id = ANY($1)
          GROUP BY 1, 2 HAVING count(*) > 1`,
  },
  {
    entity: "CUSTOMERS",
    sql: `SELECT c.organization_id, c.external_code, count(DISTINCT c.id)::int AS n
          FROM public.counterparties c
          JOIN public.counterparty_roles r ON r.counterparty_id = c.id AND r.role = 'CUSTOMER'
          WHERE c.organization_id = ANY($1) AND c.external_code IS NOT NULL
          GROUP BY 1, 2 HAVING count(DISTINCT c.id) > 1`,
  },
  {
    entity: "SUPPLIERS",
    sql: `SELECT c.organization_id, c.external_code, count(DISTINCT c.id)::int AS n
          FROM public.counterparties c
          JOIN public.counterparty_roles r ON r.counterparty_id = c.id AND r.role = 'SUPPLIER'
          WHERE c.organization_id = ANY($1) AND c.external_code IS NOT NULL
          GROUP BY 1, 2 HAVING count(DISTINCT c.id) > 1`,
  },
  {
    entity: "PRODUCTS",
    sql: `SELECT organization_id, sku, count(*)::int AS n
          FROM public.products
          WHERE organization_id = ANY($1) AND sku IS NOT NULL
          GROUP BY 1, 2 HAVING count(*) > 1`,
  },
  {
    entity: "WAREHOUSES",
    sql: `SELECT organization_id, code, count(*)::int AS n
          FROM public.warehouses
          WHERE organization_id = ANY($1)
          GROUP BY 1, 2 HAVING count(*) > 1`,
  },
  {
    entity: "SALES",
    sql: `SELECT organization_id, customer_reference, count(*)::int AS n
          FROM public.sales_documents
          WHERE organization_id = ANY($1) AND customer_reference IS NOT NULL
          GROUP BY 1, 2 HAVING count(*) > 1`,
  },
  {
    entity: "PURCHASES",
    sql: `SELECT organization_id, idempotency_key, count(*)::int AS n
          FROM public.purchase_documents
          WHERE organization_id = ANY($1)
          GROUP BY 1, 2 HAVING count(*) > 1`,
  },
  {
    entity: "JOURNALS",
    sql: `SELECT organization_id, external_reference AS k, count(*)::int AS n
          FROM public.journal_entries
          WHERE organization_id = ANY($1)
            AND external_reference IS NOT NULL
            AND reversal_of_entry_id IS NULL
          GROUP BY 1, 2 HAVING count(*) > 1
          UNION ALL
          SELECT organization_id, source_type::text || ':' || source_id::text AS k, count(*)::int AS n
          FROM public.journal_entries
          WHERE organization_id = ANY($1)
            AND source_id IS NOT NULL
            AND reversal_of_entry_id IS NULL
            AND status IN ('POSTED', 'REVERSED')
          GROUP BY 1, 2 HAVING count(*) > 1`,
  },
  {
    entity: "TREASURY_OPERATIONS",
    sql: `SELECT organization_id, idempotency_key, count(*)::int AS n
          FROM public.treasury_operations
          WHERE organization_id = ANY($1)
          GROUP BY 1, 2 HAVING count(*) > 1`,
  },
  {
    entity: "TREASURY_ACCOUNTS",
    sql: `SELECT organization_id, code, count(*)::int AS n
          FROM public.treasury_accounts
          WHERE organization_id = ANY($1)
          GROUP BY 1, 2 HAVING count(*) > 1`,
  },
  {
    entity: "INVENTORY_OPERATIONS",
    sql: `SELECT organization_id, idempotency_key, count(*)::int AS n
          FROM public.inventory_operations
          WHERE organization_id = ANY($1)
          GROUP BY 1, 2 HAVING count(*) > 1`,
  },
  {
    entity: "FISCAL_YEARS",
    sql: `SELECT organization_id, name, count(*)::int AS n
          FROM public.accounting_fiscal_years
          WHERE organization_id = ANY($1)
          GROUP BY 1, 2 HAVING count(*) > 1`,
  },
  {
    entity: "PERIODS",
    sql: `SELECT organization_id, fiscal_year_id, starts_on, count(*)::int AS n
          FROM public.accounting_periods
          WHERE organization_id = ANY($1)
          GROUP BY 1, 2, 3 HAVING count(*) > 1`,
  },
  {
    entity: "TAX_PERIODS",
    sql: `SELECT organization_id, tax_code, coalesce(jurisdiction_code, '') AS j,
                 period_year, period_month, workspace_environment, count(*)::int AS n
          FROM public.tax_periods
          WHERE organization_id = ANY($1)
          GROUP BY 1, 2, 3, 4, 5, 6 HAVING count(*) > 1`,
  },
]);

const PRIMARY_FACT_QUERIES = Object.freeze({
  customers: `SELECT count(DISTINCT c.id)::int AS n FROM public.counterparties c
              JOIN public.counterparty_roles r ON r.counterparty_id = c.id AND r.role = 'CUSTOMER'
              WHERE c.organization_id = $1`,
  suppliers: `SELECT count(DISTINCT c.id)::int AS n FROM public.counterparties c
              JOIN public.counterparty_roles r ON r.counterparty_id = c.id AND r.role = 'SUPPLIER'
              WHERE c.organization_id = $1`,
  products: `SELECT count(*)::int AS n FROM public.products WHERE organization_id = $1`,
  warehouses: `SELECT count(*)::int AS n FROM public.warehouses WHERE organization_id = $1`,
  sales: `SELECT count(*)::int AS n FROM public.sales_documents WHERE organization_id = $1`,
  salesNonDraft: `SELECT count(*)::int AS n FROM public.sales_documents
                  WHERE organization_id = $1 AND status NOT IN ('DRAFT', 'CANCELLED')`,
  purchases: `SELECT count(*)::int AS n FROM public.purchase_documents WHERE organization_id = $1`,
  purchasesPosted: `SELECT count(*)::int AS n FROM public.purchase_documents
                    WHERE organization_id = $1 AND status IN ('POSTED', 'REVERSED')`,
  journalsPosted: `SELECT count(*)::int AS n FROM public.journal_entries
                   WHERE organization_id = $1 AND status IN ('POSTED', 'REVERSED')`,
  journalReversals: `SELECT count(*)::int AS n FROM public.journal_entries
                     WHERE organization_id = $1 AND reversal_of_entry_id IS NOT NULL`,
  trialBalanceDiff: `SELECT coalesce(sum(l.debit) - sum(l.credit), 0)::text AS n
                     FROM public.journal_entry_lines l
                     JOIN public.journal_entries e ON e.id = l.journal_entry_id
                     WHERE e.organization_id = $1 AND e.status IN ('POSTED', 'REVERSED')`,
  fiscalYears: `SELECT count(*)::int AS n FROM public.accounting_fiscal_years WHERE organization_id = $1`,
  periods: `SELECT count(*)::int AS n FROM public.accounting_periods WHERE organization_id = $1`,
  treasuryPosted: `SELECT count(*)::int AS n FROM public.treasury_operations
                   WHERE organization_id = $1 AND status IN ('POSTED', 'REVERSED')`,
  treasuryDraft: `SELECT count(*)::int AS n FROM public.treasury_operations
                  WHERE organization_id = $1 AND status = 'DRAFT'`,
  inventoryPosted: `SELECT count(*)::int AS n FROM public.inventory_operations
                    WHERE organization_id = $1 AND status IN ('POSTED', 'REVERSED')`,
  inventoryDraft: `SELECT count(*)::int AS n FROM public.inventory_operations
                   WHERE organization_id = $1 AND status = 'DRAFT'`,
  stockRowsPositive: `SELECT count(*)::int AS n FROM public.inventory_stock_state
                      WHERE organization_id = $1 AND on_hand_quantity > 0`,
  negativeStockRows: `SELECT count(*)::int AS n FROM public.inventory_stock_state
                      WHERE organization_id = $1 AND (on_hand_quantity < 0 OR reserved_quantity > on_hand_quantity)`,
  taxPeriods: `SELECT count(*)::int AS n FROM public.tax_periods WHERE organization_id = $1`,
});

/**
 * @param {(sql: string, params?: unknown[]) => Promise<any[]>} dbq
 */
export async function findDemoOrgIds(dbq) {
  const rows = await dbq(
    `SELECT organization_id, value #>> '{}' AS code
     FROM public.organization_settings WHERE key = $1`,
    [DEMO_SETTINGS_KEYS.CODE]
  );
  /** @type {{ primaryOrgId: string | null, betaOrgId: string | null, allDemoOrgIds: string[] }} */
  const out = { primaryOrgId: null, betaOrgId: null, allDemoOrgIds: [] };
  for (const r of rows) {
    out.allDemoOrgIds.push(r.organization_id);
    if (r.code === DEMO_CODES.PRIMARY) out.primaryOrgId = r.organization_id;
    if (r.code === DEMO_CODES.BETA) out.betaOrgId = r.organization_id;
  }
  return out;
}

/**
 * Collect read-only facts about the demo dataset.
 * @param {(sql: string, params?: unknown[]) => Promise<any[]>} dbq
 * @param {{ isolationEmail?: string }} [opts]
 */
export async function collectDemoPostcheckFacts(dbq, opts = {}) {
  const ids = await findDemoOrgIds(dbq);

  /** @type {Record<string, number>} */
  const duplicates = {};
  for (const check of DEMO_DUPLICATE_CHECKS) {
    const rows = await dbq(check.sql, check.scoped === false ? [] : [ids.allDemoOrgIds]);
    duplicates[check.entity] = rows.reduce(
      (acc, r) => acc + Math.max(0, Number(r.n) - 1),
      0
    );
  }

  /** @type {Record<string, number> | null} */
  let primary = null;
  if (ids.primaryOrgId) {
    primary = {};
    for (const [key, sql] of Object.entries(PRIMARY_FACT_QUERIES)) {
      const rows = await dbq(sql, [ids.primaryOrgId]);
      primary[key] = Number(rows[0]?.n ?? 0);
    }
  }

  let isolationUserInBeta = null;
  if (ids.betaOrgId && opts.isolationEmail) {
    const rows = await dbq(
      `SELECT count(*)::int AS n FROM public.organization_members m
       JOIN auth.users u ON u.id = m.user_id
       WHERE m.organization_id = $1 AND lower(u.email) = lower($2)`,
      [ids.betaOrgId, opts.isolationEmail]
    );
    isolationUserInBeta = Number(rows[0]?.n ?? 0) > 0;
  }

  return {
    primaryOrgFound: Boolean(ids.primaryOrgId),
    betaOrgFound: Boolean(ids.betaOrgId),
    duplicates,
    primary,
    isolationUserInBeta,
  };
}

/**
 * Minimum postconditions that make the accountant reports meaningful.
 * @param {{ customers: number, suppliers: number, products: number, inventoryOperations: number }} fixtureCounts
 */
export function buildReportExpectations(fixtureCounts) {
  return Object.freeze({
    customers: fixtureCounts.customers,
    suppliers: fixtureCounts.suppliers,
    products: fixtureCounts.products,
    warehouses: 1,
    sales: 1,
    salesNonDraft: 1,
    purchasesPosted: 1,
    journalsPosted: 1,
    fiscalYears: 1,
    periods: 12,
    treasuryPosted: 1,
    inventoryPosted: fixtureCounts.inventoryOperations,
    stockRowsPositive: 1,
    taxPeriods: 1,
  });
}

/**
 * REPORT_DATA_READY from DB facts. Returns every unmet postcondition.
 * @param {Record<string, number> | null} primary
 * @param {Record<string, number>} expectations
 */
export function evaluateReportReadiness(primary, expectations) {
  if (!primary) {
    return { REPORT_DATA_READY: "NO", REPORT_DATA_MISSING: ["PRIMARY_DEMO_ORG_NOT_FOUND"] };
  }
  /** @type {string[]} */
  const missing = [];
  for (const [key, min] of Object.entries(expectations)) {
    const actual = Number(primary[key] ?? 0);
    if (actual < min) missing.push(`${key}: ${actual} < ${min}`);
  }
  if (Number(primary.negativeStockRows ?? 0) > 0) {
    missing.push(`negativeStockRows: ${primary.negativeStockRows} > 0`);
  }
  if (Math.abs(Number(primary.trialBalanceDiff ?? 0)) > 0.005) {
    missing.push(`trialBalanceDiff: ${primary.trialBalanceDiff} != 0`);
  }
  return {
    REPORT_DATA_READY: missing.length === 0 ? "YES" : "PARTIAL",
    REPORT_DATA_MISSING: missing,
  };
}

/**
 * Final verdict. Pure function over collected facts + run-level signals.
 * @param {{
 *   facts: Awaited<ReturnType<typeof collectDemoPostcheckFacts>>,
 *   expectations: Record<string, number>,
 *   targetMode: string,
 *   tenantIsolation?: string,
 *   arcaProductionCalls?: number,
 *   createdThisRun?: string[] | null,
 * }} input
 */
export function evaluateDemoPostcheck(input) {
  const { facts, expectations, targetMode } = input;
  const arcaCalls = Number(input.arcaProductionCalls ?? 0);

  const duplicatesFound = Object.values(facts.duplicates).reduce((a, b) => a + b, 0);
  const duplicateEntities = Object.entries(facts.duplicates)
    .filter(([, n]) => n > 0)
    .map(([k, n]) => `DUPLICATE_${k}=${n}`);

  const readiness = evaluateReportReadiness(facts.primary, expectations);

  let tenantIsolation = input.tenantIsolation ?? "NOT_VERIFIED";
  if (facts.isolationUserInBeta === true) tenantIsolation = "FAIL";

  const productionTouched =
    targetMode === "LOCAL" || targetMode === "STAGING" ? "NO" : "UNKNOWN";

  const createdThisRun = input.createdThisRun ?? null;
  const idempotency =
    duplicatesFound > 0
      ? "FAIL"
      : createdThisRun && createdThisRun.length > 0
        ? "FAIL"
        : "PASS";

  /** @type {string[]} */
  const missingPostconditions = [];
  if (!facts.primaryOrgFound) missingPostconditions.push("PRIMARY_DEMO_ORG_NOT_FOUND");
  if (!facts.betaOrgFound) missingPostconditions.push("BETA_DEMO_ORG_NOT_FOUND");
  missingPostconditions.push(...duplicateEntities);
  if (createdThisRun && createdThisRun.length > 0) {
    missingPostconditions.push(`CREATED_ON_RERUN=${createdThisRun.join(",")}`);
  }
  for (const m of readiness.REPORT_DATA_MISSING) {
    if (m !== "PRIMARY_DEMO_ORG_NOT_FOUND") missingPostconditions.push(`REPORT_DATA:${m}`);
  }
  if (tenantIsolation !== "PASS") missingPostconditions.push(`TENANT_ISOLATION=${tenantIsolation}`);
  if (productionTouched !== "NO") missingPostconditions.push(`PRODUCTION_TOUCHED=${productionTouched}`);
  if (arcaCalls !== 0) missingPostconditions.push(`ARCA_PRODUCTION_CALLS=${arcaCalls}`);

  /** @type {string[]} */
  const warnings = [];
  if (facts.primary && facts.primary.treasuryDraft > 0) {
    warnings.push(`TREASURY_OPERATIONS_DRAFT=${facts.primary.treasuryDraft}`);
  }
  if (facts.primary && facts.primary.inventoryDraft > 0) {
    warnings.push(`INVENTORY_OPERATIONS_DRAFT=${facts.primary.inventoryDraft}`);
  }

  return {
    DEMO_POSTCHECK: missingPostconditions.length === 0 ? "PASS" : "FAIL",
    DEMO_IDEMPOTENCY: idempotency,
    DUPLICATES_FOUND: duplicatesFound,
    DUPLICATES_BY_ENTITY: facts.duplicates,
    REPORT_DATA_READY: readiness.REPORT_DATA_READY,
    REPORT_DATA_MISSING: readiness.REPORT_DATA_MISSING,
    TENANT_ISOLATION_READY: tenantIsolation,
    PRODUCTION_TOUCHED: productionTouched,
    ARCA_PRODUCTION_CALLS: arcaCalls,
    MISSING_POSTCONDITIONS: missingPostconditions,
    POSTCHECK_WARNINGS: warnings,
  };
}
