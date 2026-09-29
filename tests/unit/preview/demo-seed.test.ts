/**
 * Public preview demo setup: the app only decides whether to call the database seed;
 * eligibility and the data itself live in seed_preview_demo_data (see the migration
 * contract test). The seed runs with the tester's own client, never the service role.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { createFakeSupabase, OWNER, ORG_A, ORG_B, demoDb } from "../../helpers/fake-supabase";

const admin = {
  calls: [] as { name: string; args: Record<string, unknown> }[],
  configured: true,
};

vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: () => {
    if (!admin.configured) throw new Error("SUPABASE_SERVICE_ROLE_KEY is required");
    return {
      rpc: async (name: string, args: Record<string, unknown>) => {
        admin.calls.push({ name, args });
        return { data: null, error: null };
      },
    };
  },
}));

import {
  isTesterLimitError,
  loadPreviewDemoStatus,
  runPreviewDemoSetup,
  testerLimitMessage,
  TESTER_LIMIT_CODE,
} from "@/lib/preview/demo-seed";

const ON = { VERCEL_ENV: "preview" };
const OFF = { VERCEL_ENV: "production" };

/** Minimal stand-in for the database seed: keyed rows, so re-runs reuse them. */
function seedModel(eligibleOrgs: string[]) {
  const rows = new Map<string, Set<string>>();
  const keys = [
    ...["DEMO-CUST-001", "DEMO-CUST-002", "DEMO-CUST-003", "DEMO-CUST-004", "DEMO-CUST-005"],
    ...["DEMO-SUP-001", "DEMO-SUP-002", "DEMO-SUP-003", "DEMO-SUP-004", "DEMO-SUP-005"],
    "staging-demo-opening-cash",
    "staging-demo-collection-001",
    "staging-demo-payment-001",
    "staging-demo-transfer-001",
    "staging-demo-sale-001",
    "staging-demo-sale-002",
    "staging-demo-sale-003",
    "staging-demo-purchase-001",
    "staging-demo-purchase-002",
  ];
  const summary = (org: string) => {
    const set = rows.get(org) ?? new Set<string>();
    const n = (prefix: string) => [...set].filter((k) => k.startsWith(prefix)).length;
    return {
      customers: n("DEMO-CUST"),
      suppliers: n("DEMO-SUP"),
      treasury_posted: n("staging-demo-") - n("staging-demo-sale") - n("staging-demo-purchase"),
      sales_orders: n("staging-demo-sale"),
      purchases_posted: n("staging-demo-purchase"),
      cash_balance: set.size ? 163000 : 0,
    };
  };
  return {
    rows,
    handlers: {
      preview_demo_seed_status: (args: Record<string, unknown>) => {
        const org = args.p_organization_id as string;
        return { eligible: eligibleOrgs.includes(org), complete: (rows.get(org)?.size ?? 0) === keys.length };
      },
      seed_preview_demo_data: (args: Record<string, unknown>) => {
        const org = args.p_organization_id as string;
        const set = rows.get(org) ?? new Set<string>();
        for (const k of keys) set.add(k);
        rows.set(org, set);
        return summary(org);
      },
    },
  };
}

beforeEach(() => {
  admin.calls = [];
  admin.configured = true;
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("runPreviewDemoSetup", () => {
  it("flag OFF: calls nothing, not even the status check", async () => {
    const model = seedModel([ORG_A]);
    const fake = createFakeSupabase(demoDb(), OWNER, { rpcHandlers: model.handlers });
    expect(await runPreviewDemoSetup(fake.client as never, ORG_A, OFF)).toEqual({
      ok: true,
      seeded: false,
      reason: "disabled",
    });
    expect(fake.rpcs).toHaveLength(0);
    expect(admin.calls).toHaveLength(0);
    expect(model.rows.size).toBe(0);
  });

  it("an organization without a tester slot (e.g. Empresa Demo) is left untouched", async () => {
    const model = seedModel([]);
    const fake = createFakeSupabase(demoDb(), OWNER, { rpcHandlers: model.handlers });
    expect(await runPreviewDemoSetup(fake.client as never, ORG_A, ON)).toEqual({
      ok: true,
      seeded: false,
      reason: "not_eligible",
    });
    expect(fake.rpcs.map((r) => r.name)).toEqual(["preview_demo_seed_status"]);
    expect(admin.calls).toHaveLength(0);
  });

  it("eligible: grants the taxes module for that organization only, then seeds with the user client", async () => {
    const model = seedModel([ORG_A]);
    const fake = createFakeSupabase(demoDb(), OWNER, { rpcHandlers: model.handlers });
    const res = await runPreviewDemoSetup(fake.client as never, ORG_A, ON);
    expect(res).toMatchObject({ ok: true, seeded: true, summary: { customers: 5, suppliers: 5, cash_balance: 163000 } });
    expect(admin.calls.map((c) => c.name)).toEqual([
      "platform_enable_organization_feature",
      "recompute_organization_features",
    ]);
    expect(admin.calls[0].args).toEqual({ p_organization_id: ORG_A, p_feature_code: "taxes" });
    expect(admin.calls.every((c) => c.args.p_organization_id === ORG_A)).toBe(true);
    expect(fake.rpcs.map((r) => r.name)).toEqual(["preview_demo_seed_status", "seed_preview_demo_data"]);
    expect(fake.rpcs.every((r) => r.args.p_organization_id === ORG_A)).toBe(true);
    expect([...model.rows.keys()]).toEqual([ORG_A]);
    expect(model.rows.has(ORG_B)).toBe(false);
  });

  it("running recovery twice creates no duplicates", async () => {
    const model = seedModel([ORG_A]);
    const first = await runPreviewDemoSetup(
      createFakeSupabase(demoDb(), OWNER, { rpcHandlers: model.handlers }).client as never,
      ORG_A,
      ON
    );
    const second = await runPreviewDemoSetup(
      createFakeSupabase(demoDb(), OWNER, { rpcHandlers: model.handlers }).client as never,
      ORG_A,
      ON
    );
    expect(second).toEqual(first);
    expect(model.rows.get(ORG_A)?.size).toBe(19);
  });

  it("reports the failing step without leaking database messages", async () => {
    const model = seedModel([ORG_A]);
    const fake = createFakeSupabase(demoDb(), OWNER, {
      rpcHandlers: { preview_demo_seed_status: model.handlers.preview_demo_seed_status },
      failRpcs: { seed_preview_demo_data: { code: "P0001", message: "PREVIEW_DEMO_TREASURY_NOT_POSTED" } },
    });
    expect(await runPreviewDemoSetup(fake.client as never, ORG_A, ON)).toEqual({ ok: false, step: "seed" });
    expect(JSON.stringify(vi.mocked(console.error).mock.calls)).not.toContain("PREVIEW_DEMO_TREASURY_NOT_POSTED");
  });

  it("does not seed when the platform grant is unavailable", async () => {
    admin.configured = false;
    const model = seedModel([ORG_A]);
    const fake = createFakeSupabase(demoDb(), OWNER, { rpcHandlers: model.handlers });
    expect(await runPreviewDemoSetup(fake.client as never, ORG_A, ON)).toEqual({ ok: false, step: "modules" });
    expect(model.rows.size).toBe(0);
  });
});

describe("loadPreviewDemoStatus", () => {
  it("returns null when the status query fails, so no banner is forced", async () => {
    const fake = createFakeSupabase(demoDb(), OWNER, {
      failRpcs: { preview_demo_seed_status: { code: "42883", message: "x" } },
    });
    expect(await loadPreviewDemoStatus(fake.client as never, ORG_A, ON)).toBeNull();
  });
});

describe("tester limit message", () => {
  it("maps the database code to the Spanish message and never shows the code", () => {
    const error = { code: "P0001", message: TESTER_LIMIT_CODE, details: "Public preview is limited to 5 tester accounts." };
    expect(isTesterLimitError(error)).toBe(true);
    expect(isTesterLimitError({ code: "23505", message: "duplicate key" })).toBe(false);
    expect(isTesterLimitError(null)).toBe(false);
    const msg = testerLimitMessage({});
    expect(msg).toBe("Se alcanzó el límite de 5 usuarios de prueba. Contactanos si necesitás acceso.");
    expect(msg).not.toContain(TESTER_LIMIT_CODE);
  });
});
