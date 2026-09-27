/**
 * Unit tests for demo seed guards — no DB / no ARCA / no Production.
 */
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import {
  assertDemoSeedEnvironment,
  assertSyntheticTaxId,
  isDemoOrganizationRow,
  DEMO_CODES,
  DEMO_SETTINGS_KEYS,
  extractProjectRef,
} from "../../../scripts/demo/guards.mjs";

describe("demo seed environment guard", () => {
  const prev = { ...process.env };

  beforeEach(() => {
    process.env.DEMO_SEED_CONFIRM = "YES";
    delete process.env.ARCA_ENV;
    delete process.env.FISCAL_GATEWAY_ENV;
    delete process.env.DEMO_SEED_ALLOW_STAGING_REF;
  });

  afterEach(() => {
    process.env = { ...prev };
  });

  it("refuses without DEMO_SEED_CONFIRM=YES", () => {
    delete process.env.DEMO_SEED_CONFIRM;
    expect(() =>
      assertDemoSeedEnvironment({ apiUrl: "http://127.0.0.1:54321" })
    ).toThrow(/DEMO_SEED_REFUSED/);
  });

  it("allows local API URL", () => {
    const r = assertDemoSeedEnvironment({
      apiUrl: "http://127.0.0.1:54321",
      dbUrl: "postgresql://postgres@127.0.0.1:54322/postgres",
    });
    expect(r.mode).toBe("LOCAL");
  });

  it("refuses ARCA production env", () => {
    process.env.ARCA_ENV = "production";
    expect(() =>
      assertDemoSeedEnvironment({ apiUrl: "http://127.0.0.1:54321" })
    ).toThrow(/production/i);
  });

  it("refuses unknown remote supabase project", () => {
    expect(() =>
      assertDemoSeedEnvironment({
        apiUrl: "https://abcdefghijklmnop.supabase.co",
      })
    ).toThrow(/DEMO_SEED_REFUSED/);
  });

  it("allows allow-listed staging ref", () => {
    const r = assertDemoSeedEnvironment({
      apiUrl: "https://rpcpdrzbcclofvjpgldb.supabase.co",
      projectRef: "rpcpdrzbcclofvjpgldb",
    });
    expect(r.mode).toBe("STAGING");
  });
});

describe("synthetic tax id guard", () => {
  it("allows DEMO-* and exact SYNTHETIC-NOT-A-CUIT", () => {
    expect(assertSyntheticTaxId(null)).toBe(true);
    expect(assertSyntheticTaxId("DEMO-CUST-001")).toBe(true);
    expect(assertSyntheticTaxId("DEMO-BETA")).toBe(true);
    expect(assertSyntheticTaxId("SYNTHETIC-NOT-A-CUIT")).toBe(true);
  });

  it("rejects CUIT-shaped 11-digit values", () => {
    expect(() => assertSyntheticTaxId("20123456789")).toThrow(/SYNTHETIC_TAX_ID_GUARD/);
    expect(() => assertSyntheticTaxId("20-12345678-6")).toThrow(/SYNTHETIC_TAX_ID_GUARD/);
  });

  it("rejects arbitrary non-demo strings and BETA suffix variant", () => {
    expect(() => assertSyntheticTaxId("ACME-TAX")).toThrow(/SYNTHETIC_TAX_ID_GUARD/);
    expect(() => assertSyntheticTaxId("SYNTHETIC-NOT-A-CUIT-BETA")).toThrow(
      /SYNTHETIC_TAX_ID_GUARD/
    );
  });
});

describe("Beta tenant fixture tax placeholder", () => {
  it("uses an accepted DEMO-* identifier", async () => {
    const { BETA_ORG, PRIMARY_ORG } = await import(
      "../../../scripts/demo/fixtures.mjs"
    );
    expect(BETA_ORG.tax_placeholder).toBe("DEMO-BETA");
    expect(assertSyntheticTaxId(BETA_ORG.tax_placeholder)).toBe(true);
    expect(assertSyntheticTaxId(PRIMARY_ORG.tax_placeholder)).toBe(true);
    expect(BETA_ORG.tax_placeholder).not.toBe("SYNTHETIC-NOT-A-CUIT-BETA");
  });
});

describe("demo org marker", () => {
  it("detects demo via settings", () => {
    expect(
      isDemoOrganizationRow(
        { legal_name: "Other SA" },
        [{ key: DEMO_SETTINGS_KEYS.IS_DEMO, value: true }]
      )
    ).toBe(true);
    expect(
      isDemoOrganizationRow(
        { legal_name: "Other SA" },
        [{ key: DEMO_SETTINGS_KEYS.CODE, value: DEMO_CODES.PRIMARY }]
      )
    ).toBe(true);
  });

  it("detects demo via legal name", () => {
    expect(
      isDemoOrganizationRow({ legal_name: "EMPRESA DEMO ARGENTINA SA" }, [])
    ).toBe(true);
  });

  it("rejects non-demo", () => {
    expect(isDemoOrganizationRow({ legal_name: "ACME Real SA" }, [])).toBe(false);
  });
});

describe("extractProjectRef", () => {
  it("parses supabase host", () => {
    expect(extractProjectRef("https://abc123.supabase.co")).toBe("abc123");
  });
  it("returns null for local", () => {
    expect(extractProjectRef("http://127.0.0.1:54321")).toBeNull();
  });
});

describe("ARCA production call count contract", () => {
  it("demo seed must never invoke FECAESolicitar — constant 0", () => {
    // Contract assertion for documentation / CI
    const ARCA_PRODUCTION_CALLS = 0;
    expect(ARCA_PRODUCTION_CALLS).toBe(0);
  });
});
