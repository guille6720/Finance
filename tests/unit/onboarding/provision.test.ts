/**
 * Provisioning of tester organizations: the platform grant (service_role) only runs
 * for the creator-owner, everything else goes through the user's RLS client, and each
 * step is idempotent.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { createFakeSupabase, OWNER, SOLO, ORG_A, demoDb, type FakeDb } from "../../helpers/fake-supabase";

const admin = {
  calls: [] as { name: string; args: Record<string, unknown> }[],
  configured: true,
  fail: null as string | null,
};

vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: () => {
    if (!admin.configured) throw new Error("SUPABASE_SERVICE_ROLE_KEY is required");
    return {
      rpc: async (name: string, args: Record<string, unknown>) => {
        admin.calls.push({ name, args });
        return { data: null, error: admin.fail === name ? { code: "P0001", message: "x" } : null };
      },
    };
  },
}));

import {
  isOrganizationProvisioned,
  provisionOrganization,
  PROVISIONED_FEATURES,
} from "@/lib/onboarding/provision";

function accounts() {
  const a = (id: string, code: string, system_role: string | null, account_type = "ASSET") => ({
    id,
    organization_id: ORG_A,
    code,
    system_role,
    account_type,
    is_postable: true,
  });
  return [
    a("acc-cash", "1.1.01", "cash"),
    a("acc-bank", "1.1.02", "bank"),
    a("acc-ap", "2.1.01", "payables", "LIABILITY"),
    a("acc-vat", "2.1.02", null, "LIABILITY"),
    a("acc-cogs", "5.1.01", "cogs", "EXPENSE"),
    a("acc-inv", "1.1.04", "inventory"),
    a("acc-clr", "2.1.09", "inventory_purchase_clearing", "LIABILITY"),
    a("acc-gain", "4.9.01", "inventory_adjustment_gain", "REVENUE"),
  ];
}

function db(): FakeDb {
  const d = demoDb();
  d.organizations[0].created_by = OWNER;
  d.branches = [{ id: "br-1", organization_id: ORG_A, is_main: true }];
  d.accounts = [];
  d.accounting_fiscal_years = [];
  d.purchase_accounting_mappings = [];
  d.inventory_accounting_mappings = [];
  d.treasury_accounts = [];
  d.warehouses = [];
  d.feature_catalog = [{ id: "f-acc", code: "accounting" }];
  d.organization_features = [];
  return d;
}

const seedChart = (_args: Record<string, unknown>, data: FakeDb) => {
  if (data.accounts.length === 0) data.accounts.push(...accounts());
  return data.accounts.length;
};

beforeEach(() => {
  admin.calls = [];
  admin.configured = true;
  admin.fail = null;
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("provisionOrganization", () => {
  it("leaves the organization ready: modules, chart, fiscal year, mappings, cash, bank, warehouse", async () => {
    const data = db();
    const fake = createFakeSupabase(data, OWNER, {
      rpcHandlers: { seed_starter_chart_of_accounts: seedChart },
    });
    const res = await provisionOrganization(fake.client as never, OWNER, ORG_A, new Date("2026-09-28"));
    expect(res).toEqual({ ok: true });

    expect(admin.calls[0]).toEqual({
      name: "platform_bootstrap_organization_modules",
      args: { p_organization_id: ORG_A },
    });
    const enabled = admin.calls
      .filter((c) => c.name === "platform_enable_organization_feature")
      .map((c) => c.args.p_feature_code);
    expect(enabled).toEqual([...PROVISIONED_FEATURES]);
    expect(admin.calls.every((c) => c.args.p_organization_id === ORG_A)).toBe(true);

    expect(fake.rpcs.map((r) => r.name)).toEqual([
      "seed_starter_chart_of_accounts",
      "ensure_treasury_clearing_coa",
      "ensure_inventory_chart_accounts",
      "ensure_monthly_periods",
    ]);
    expect(data.accounting_fiscal_years[0]).toMatchObject({
      name: "Ejercicio 2026",
      start_date: "2026-01-01",
      end_date: "2026-12-31",
    });
    expect(data.purchase_accounting_mappings[0]).toMatchObject({
      accounts_payable_account_id: "acc-ap",
      vat_input_account_id: "acc-vat",
    });
    expect(data.inventory_accounting_mappings[0]).toMatchObject({ adjustment_loss_account_id: "acc-cogs" });
    expect(data.treasury_accounts.map((t) => [t.code, t.accounting_account_id])).toEqual([
      ["CAJA", "acc-cash"],
      ["BANCO", "acc-bank"],
    ]);
    expect(data.warehouses[0]).toMatchObject({ code: "PRINCIPAL", branch_id: "br-1" });
  });

  it("is idempotent: a second run creates nothing new", async () => {
    const data = db();
    const opts = { rpcHandlers: { seed_starter_chart_of_accounts: seedChart } };
    await provisionOrganization(createFakeSupabase(data, OWNER, opts).client as never, OWNER, ORG_A);
    const second = createFakeSupabase(data, OWNER, opts);
    expect(await provisionOrganization(second.client as never, OWNER, ORG_A)).toEqual({ ok: true });
    expect(second.inserts).toHaveLength(0);
  });

  it("never calls the platform for a non-owner member", async () => {
    const fake = createFakeSupabase(db(), SOLO);
    expect(await provisionOrganization(fake.client as never, SOLO, ORG_A)).toEqual({
      ok: false,
      step: "not_owner",
    });
    expect(admin.calls).toHaveLength(0);
    expect(fake.rpcs).toHaveLength(0);
  });

  it("never calls the platform for an owner who did not create the organization", async () => {
    const data = db();
    data.organizations[0].created_by = SOLO;
    const fake = createFakeSupabase(data, OWNER);
    expect((await provisionOrganization(fake.client as never, OWNER, ORG_A)).ok).toBe(false);
    expect(admin.calls).toHaveLength(0);
  });

  it("reports a missing service key without touching data", async () => {
    admin.configured = false;
    const fake = createFakeSupabase(db(), OWNER);
    expect(await provisionOrganization(fake.client as never, OWNER, ORG_A)).toEqual({
      ok: false,
      step: "platform_unconfigured",
    });
    expect(fake.inserts).toHaveLength(0);
  });

  it("stops at the failing step", async () => {
    admin.fail = "platform_bootstrap_organization_modules";
    const fake = createFakeSupabase(db(), OWNER);
    expect(await provisionOrganization(fake.client as never, OWNER, ORG_A)).toEqual({
      ok: false,
      step: "platform_bootstrap",
    });
    expect(fake.rpcs).toHaveLength(0);
  });
});

describe("isOrganizationProvisioned", () => {
  it("is false for a bare organization and true once provisioned", async () => {
    const data = db();
    const fake = createFakeSupabase(data, OWNER);
    expect(await isOrganizationProvisioned(fake.client as never, ORG_A)).toBe(false);
    data.accounts.push(...accounts());
    data.accounting_fiscal_years.push({ id: "fy", organization_id: ORG_A, name: "Ejercicio 2026" });
    data.organization_features.push({ id: "of", organization_id: ORG_A, feature_id: "f-acc", status: "enabled" });
    expect(await isOrganizationProvisioned(fake.client as never, ORG_A)).toBe(true);
  });

  it("returns null (unknown) when a query fails, so no banner is forced", async () => {
    const fake = createFakeSupabase(db(), OWNER, { failTables: ["accounts"] });
    expect(await isOrganizationProvisioned(fake.client as never, ORG_A)).toBeNull();
  });
});
