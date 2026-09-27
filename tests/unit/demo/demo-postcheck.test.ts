/**
 * Demo seed post-check: counter semantics, DB-postcondition readiness,
 * duplicate detection and safety signals. No database access (dbq is mocked).
 */
import { describe, it, expect } from "vitest";
import {
  createSeedCounters,
  entitiesCreatedThisRun,
  DEMO_COUNTER_ENTITIES,
} from "../../../scripts/demo/counters.mjs";
import {
  DEMO_DUPLICATE_CHECKS,
  collectDemoPostcheckFacts,
  buildReportExpectations,
  evaluateReportReadiness,
  evaluateDemoPostcheck,
} from "../../../scripts/demo/postcheck.mjs";
import { assertDemoSeedEnvironment } from "../../../scripts/demo/guards.mjs";
import {
  CUSTOMERS,
  SUPPLIERS,
  PRODUCTS,
  DEMO_OPENING_INVENTORY_COUNT,
  DEMO_TAX_PERIODS,
} from "../../../scripts/demo/fixtures.mjs";

const EXPECTATIONS = buildReportExpectations({
  customers: CUSTOMERS.length,
  suppliers: SUPPLIERS.length,
  products: PRODUCTS.length,
  inventoryOperations: DEMO_OPENING_INVENTORY_COUNT,
});

function completePrimary(overrides: Record<string, number> = {}) {
  return {
    customers: 12,
    suppliers: 9,
    products: 22,
    warehouses: 2,
    sales: 58,
    salesNonDraft: 42,
    purchases: 36,
    purchasesPosted: 21,
    journalsPosted: 50,
    journalReversals: 8,
    trialBalanceDiff: 0,
    fiscalYears: 1,
    periods: 12,
    treasuryPosted: 5,
    treasuryDraft: 0,
    inventoryPosted: 8,
    inventoryDraft: 0,
    stockRowsPositive: 8,
    negativeStockRows: 0,
    taxPeriods: 3,
    ...overrides,
  };
}

function zeroDuplicates(): Record<string, number> {
  return Object.fromEntries(DEMO_DUPLICATE_CHECKS.map((c) => [c.entity, 0]));
}

function facts(overrides: Partial<{
  primary: Record<string, number> | null;
  duplicates: Record<string, number>;
  betaOrgFound: boolean;
  isolationUserInBeta: boolean | null;
}> = {}) {
  return {
    primaryOrgFound: overrides.primary !== null,
    betaOrgFound: overrides.betaOrgFound ?? true,
    duplicates: overrides.duplicates ?? zeroDuplicates(),
    primary: overrides.primary === undefined ? completePrimary() : overrides.primary,
    isolationUserInBeta: overrides.isolationUserInBeta ?? false,
  };
}

describe("seed counters: created vs reused", () => {
  it("second run over an existing dataset reports CREATED_THIS_RUN = 0", () => {
    const c = createSeedCounters();
    for (let i = 0; i < CUSTOMERS.length; i++) c.record("CUSTOMERS", "reused");
    for (let i = 0; i < SUPPLIERS.length; i++) c.record("SUPPLIERS", "reused");
    for (let i = 0; i < PRODUCTS.length; i++) c.record("PRODUCTS", "reused");
    c.record("SALES", "reused", 58);
    c.record("PURCHASES", "reused", 36);
    const snap = c.snapshot();
    expect(snap.CUSTOMERS_CREATED_THIS_RUN).toBe(0);
    expect(snap.SUPPLIERS_CREATED_THIS_RUN).toBe(0);
    expect(snap.PRODUCTS_CREATED_THIS_RUN).toBe(0);
    expect(snap.SALES_CREATED_THIS_RUN).toBe(0);
    expect(entitiesCreatedThisRun(snap)).toEqual([]);
  });

  it("reused counters equal the fixture sizes on rerun", () => {
    const c = createSeedCounters();
    CUSTOMERS.forEach(() => c.record("CUSTOMERS", "reused"));
    SUPPLIERS.forEach(() => c.record("SUPPLIERS", "reused"));
    PRODUCTS.forEach(() => c.record("PRODUCTS", "reused"));
    const snap = c.snapshot();
    expect(snap.CUSTOMERS_REUSED).toBe(12);
    expect(snap.SUPPLIERS_REUSED).toBe(9);
    expect(snap.PRODUCTS_REUSED).toBe(22);
  });

  it("first run counts only real inserts", () => {
    const c = createSeedCounters();
    c.record("CUSTOMERS", "created", 12);
    c.record("PRODUCTS", "created", 22);
    expect(entitiesCreatedThisRun(c.snapshot()).sort()).toEqual(["CUSTOMERS", "PRODUCTS"]);
  });

  it("completing an existing DRAFT counts as reused + posted, not created", () => {
    const c = createSeedCounters();
    c.record("INVENTORY_OPERATIONS", "reused");
    c.record("INVENTORY_OPERATIONS", "posted");
    const snap = c.snapshot();
    expect(snap.INVENTORY_OPERATIONS_CREATED_THIS_RUN).toBe(0);
    expect(snap.INVENTORY_OPERATIONS_REUSED).toBe(1);
    expect(snap.INVENTORY_OPERATIONS_POSTED_THIS_RUN).toBe(1);
  });

  it("tracks every required entity and rejects unknown ones", () => {
    const snap = createSeedCounters().snapshot();
    for (const e of DEMO_COUNTER_ENTITIES) {
      expect(snap).toHaveProperty(`${e}_CREATED_THIS_RUN`, 0);
      expect(snap).toHaveProperty(`${e}_REUSED`, 0);
    }
    expect(() => createSeedCounters().record("NOPE", "created")).toThrow(/unknown entity/);
    expect(() => createSeedCounters().record("CUSTOMERS", "posted")).toThrow(/not tracked/);
  });
});

describe("REPORT_DATA_READY from DB postconditions", () => {
  it("YES when every postcondition holds, regardless of counters", () => {
    const r = evaluateReportReadiness(completePrimary(), EXPECTATIONS);
    expect(r.REPORT_DATA_READY).toBe("YES");
    expect(r.REPORT_DATA_MISSING).toEqual([]);
  });

  it("missing inventory → PARTIAL with reason", () => {
    const r = evaluateReportReadiness(
      completePrimary({ inventoryPosted: 0, stockRowsPositive: 0 }),
      EXPECTATIONS
    );
    expect(r.REPORT_DATA_READY).toBe("PARTIAL");
    expect(r.REPORT_DATA_MISSING).toContain("inventoryPosted: 0 < 8");
    expect(r.REPORT_DATA_MISSING).toContain("stockRowsPositive: 0 < 1");
  });

  it("missing tax periods or accounting periods → PARTIAL", () => {
    const r = evaluateReportReadiness(
      completePrimary({ taxPeriods: 0, periods: 0 }),
      EXPECTATIONS
    );
    expect(r.REPORT_DATA_READY).toBe("PARTIAL");
    expect(r.REPORT_DATA_MISSING).toContain("taxPeriods: 0 < 1");
    expect(r.REPORT_DATA_MISSING).toContain("periods: 0 < 12");
  });

  it("negative stock or unbalanced trial balance → PARTIAL", () => {
    const r = evaluateReportReadiness(
      completePrimary({ negativeStockRows: 1, trialBalanceDiff: 10 }),
      EXPECTATIONS
    );
    expect(r.REPORT_DATA_READY).toBe("PARTIAL");
    expect(r.REPORT_DATA_MISSING.join("|")).toMatch(/negativeStockRows/);
    expect(r.REPORT_DATA_MISSING.join("|")).toMatch(/trialBalanceDiff/);
  });

  it("no primary org → NO", () => {
    expect(evaluateReportReadiness(null, EXPECTATIONS).REPORT_DATA_READY).toBe("NO");
  });

  it("expects all demo tax periods and opening inventory from fixtures", () => {
    expect(DEMO_TAX_PERIODS.length).toBeGreaterThan(0);
    for (const tp of DEMO_TAX_PERIODS) {
      expect(tp.tax_code).toBe("IVA");
      expect(tp.jurisdiction_code).toBeNull();
    }
    expect(EXPECTATIONS.inventoryPosted).toBe(DEMO_OPENING_INVENTORY_COUNT);
  });
});

describe("DEMO_POSTCHECK verdict", () => {
  it("PASS on a complete, duplicate-free LOCAL dataset", () => {
    const r = evaluateDemoPostcheck({
      facts: facts(),
      expectations: EXPECTATIONS,
      targetMode: "LOCAL",
      tenantIsolation: "PASS",
      arcaProductionCalls: 0,
      createdThisRun: [],
    });
    expect(r.DEMO_POSTCHECK).toBe("PASS");
    expect(r.DEMO_IDEMPOTENCY).toBe("PASS");
    expect(r.DUPLICATES_FOUND).toBe(0);
    expect(r.REPORT_DATA_READY).toBe("YES");
    expect(r.PRODUCTION_TOUCHED).toBe("NO");
    expect(r.ARCA_PRODUCTION_CALLS).toBe(0);
    expect(r.MISSING_POSTCONDITIONS).toEqual([]);
  });

  it("duplicate keys fail idempotency and the post-check", () => {
    const dup = { ...zeroDuplicates(), CUSTOMERS: 2, SALES: 1 };
    const r = evaluateDemoPostcheck({
      facts: facts({ duplicates: dup }),
      expectations: EXPECTATIONS,
      targetMode: "LOCAL",
      tenantIsolation: "PASS",
    });
    expect(r.DUPLICATES_FOUND).toBe(3);
    expect(r.DEMO_IDEMPOTENCY).toBe("FAIL");
    expect(r.DEMO_POSTCHECK).toBe("FAIL");
    expect(r.MISSING_POSTCONDITIONS).toContain("DUPLICATE_CUSTOMERS=2");
    expect(r.MISSING_POSTCONDITIONS).toContain("DUPLICATE_SALES=1");
  });

  it("inserts during an expected-idempotent rerun fail idempotency", () => {
    const r = evaluateDemoPostcheck({
      facts: facts(),
      expectations: EXPECTATIONS,
      targetMode: "LOCAL",
      tenantIsolation: "PASS",
      createdThisRun: ["CUSTOMERS"],
    });
    expect(r.DEMO_IDEMPOTENCY).toBe("FAIL");
    expect(r.MISSING_POSTCONDITIONS).toContain("CREATED_ON_RERUN=CUSTOMERS");
  });

  it("missing inventory lists MISSING_POSTCONDITIONS and fails", () => {
    const r = evaluateDemoPostcheck({
      facts: facts({ primary: completePrimary({ inventoryPosted: 0, inventoryDraft: 8 }) }),
      expectations: EXPECTATIONS,
      targetMode: "LOCAL",
      tenantIsolation: "PASS",
    });
    expect(r.DEMO_POSTCHECK).toBe("FAIL");
    expect(r.REPORT_DATA_READY).toBe("PARTIAL");
    expect(r.MISSING_POSTCONDITIONS).toContain("REPORT_DATA:inventoryPosted: 0 < 8");
    expect(r.POSTCHECK_WARNINGS).toContain("INVENTORY_OPERATIONS_DRAFT=8");
  });

  it("isolation user present in Beta forces TENANT_ISOLATION_READY=FAIL", () => {
    const r = evaluateDemoPostcheck({
      facts: facts({ isolationUserInBeta: true }),
      expectations: EXPECTATIONS,
      targetMode: "LOCAL",
      tenantIsolation: "PASS",
    });
    expect(r.TENANT_ISOLATION_READY).toBe("FAIL");
    expect(r.DEMO_POSTCHECK).toBe("FAIL");
  });

  it("non-LOCAL/STAGING target or ARCA production calls fail the post-check", () => {
    const prod = evaluateDemoPostcheck({
      facts: facts(),
      expectations: EXPECTATIONS,
      targetMode: "PRODUCTION",
      tenantIsolation: "PASS",
    });
    expect(prod.PRODUCTION_TOUCHED).not.toBe("NO");
    expect(prod.DEMO_POSTCHECK).toBe("FAIL");

    const arca = evaluateDemoPostcheck({
      facts: facts(),
      expectations: EXPECTATIONS,
      targetMode: "LOCAL",
      tenantIsolation: "PASS",
      arcaProductionCalls: 1,
    });
    expect(arca.MISSING_POSTCONDITIONS).toContain("ARCA_PRODUCTION_CALLS=1");
    expect(arca.DEMO_POSTCHECK).toBe("FAIL");
  });

  it("missing Beta tenant fails", () => {
    const r = evaluateDemoPostcheck({
      facts: facts({ betaOrgFound: false }),
      expectations: EXPECTATIONS,
      targetMode: "LOCAL",
      tenantIsolation: "PASS",
    });
    expect(r.MISSING_POSTCONDITIONS).toContain("BETA_DEMO_ORG_NOT_FOUND");
  });
});

describe("collectDemoPostcheckFacts (mocked, read-only)", () => {
  it("issues SELECT statements only and counts extra rows per duplicated key", async () => {
    const seen: string[] = [];
    const dbq = async (sql: string) => {
      seen.push(sql);
      if (sql.includes("value #>> '{}' AS code")) {
        return [
          { organization_id: "p", code: "DEMO-AR-001" },
          { organization_id: "b", code: "DEMO-AR-BETA-001" },
        ];
      }
      if (sql.includes("FROM public.products") && sql.includes("HAVING")) {
        return [{ organization_id: "p", sku: "DEMO-P-A", n: 3 }];
      }
      if (sql.includes("HAVING")) return [];
      if (sql.includes("auth.users")) return [{ n: 0 }];
      return [{ n: 0 }];
    };
    const f = await collectDemoPostcheckFacts(dbq, {
      isolationEmail: "isolation.demo@example.invalid",
    });
    expect(f.primaryOrgFound).toBe(true);
    expect(f.betaOrgFound).toBe(true);
    expect(f.duplicates.PRODUCTS).toBe(2);
    expect(f.duplicates.CUSTOMERS).toBe(0);
    expect(f.isolationUserInBeta).toBe(false);
    for (const sql of seen) {
      expect(sql.trim()).toMatch(/^SELECT/i);
      expect(sql).not.toMatch(/\b(INSERT|UPDATE|DELETE|TRUNCATE|DROP|ALTER)\b/i);
    }
  });

  it("covers every deterministic key required by the idempotency audit", () => {
    const entities = DEMO_DUPLICATE_CHECKS.map((c) => c.entity);
    for (const e of [
      "ORGANIZATIONS",
      "MEMBERS",
      "CUSTOMERS",
      "SUPPLIERS",
      "PRODUCTS",
      "SALES",
      "PURCHASES",
      "JOURNALS",
      "TREASURY_OPERATIONS",
      "INVENTORY_OPERATIONS",
      "FISCAL_YEARS",
      "PERIODS",
      "TAX_PERIODS",
    ]) {
      expect(entities).toContain(e);
    }
  });
});

describe("read-only post-check keeps production guard", () => {
  it("refuses non-allow-listed remote targets even in readOnly mode", () => {
    const prev = process.env.DEMO_SEED_CONFIRM;
    delete process.env.DEMO_SEED_CONFIRM;
    try {
      expect(() =>
        assertDemoSeedEnvironment(
          { apiUrl: "https://prodprojectref.supabase.co", dbUrl: "" },
          { readOnly: true }
        )
      ).toThrow(/DEMO_SEED_REFUSED/);
      expect(
        assertDemoSeedEnvironment(
          { apiUrl: "http://127.0.0.1:54321", dbUrl: "" },
          { readOnly: true }
        ).mode
      ).toBe("LOCAL");
      expect(() =>
        assertDemoSeedEnvironment({ apiUrl: "http://127.0.0.1:54321", dbUrl: "" })
      ).toThrow(/DEMO_SEED_CONFIRM/);
    } finally {
      if (prev === undefined) delete process.env.DEMO_SEED_CONFIRM;
      else process.env.DEMO_SEED_CONFIRM = prev;
    }
  });

  it("refuses ARCA production environment in readOnly mode", () => {
    const prev = process.env.ARCA_ENV;
    process.env.ARCA_ENV = "production";
    try {
      expect(() =>
        assertDemoSeedEnvironment(
          { apiUrl: "http://127.0.0.1:54321", dbUrl: "" },
          { readOnly: true }
        )
      ).toThrow(/ARCA\/FISCAL production/);
    } finally {
      if (prev === undefined) delete process.env.ARCA_ENV;
      else process.env.ARCA_ENV = prev;
    }
  });
});
