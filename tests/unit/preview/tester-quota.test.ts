/**
 * External tester quota reporting. The database decides who may read it (exempt
 * accounts only) and what counts (slots of non-exempt users); the app only renders it.
 */
import { describe, it, expect, vi } from "vitest";
import { createFakeSupabase, OWNER, demoDb } from "../../helpers/fake-supabase";

vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: () => {
    throw new Error("must not be called");
  },
}));

import { loadTesterQuota, testerQuotaLabel } from "@/lib/preview/demo-seed";

const ON = { VERCEL_ENV: "preview" };
const OFF = { VERCEL_ENV: "production" };

describe("loadTesterQuota", () => {
  it("is hidden and never queries when the preview is off", async () => {
    const fake = createFakeSupabase(demoDb(), OWNER, {
      rpcHandlers: { preview_tester_quota: () => ({ used: 0, max: 5 }) },
    });
    expect(await loadTesterQuota(fake.client as never, OFF)).toEqual({ kind: "hidden" });
    expect(fake.rpcs).toHaveLength(0);
  });

  it("is hidden for non-internal accounts (the database answers null)", async () => {
    const fake = createFakeSupabase(demoDb(), OWNER, { rpcHandlers: { preview_tester_quota: () => null } });
    expect(await loadTesterQuota(fake.client as never, ON)).toEqual({ kind: "hidden" });
  });

  it("reports 0 / 5 external testers when only exempt accounts exist", async () => {
    const fake = createFakeSupabase(demoDb(), OWNER, {
      rpcHandlers: { preview_tester_quota: () => ({ enabled: true, used: 0, max: 5 }) },
    });
    const quota = await loadTesterQuota(fake.client as never, ON);
    expect(quota).toEqual({ kind: "ok", used: 0, max: 5 });
    expect(fake.rpcs).toEqual([{ name: "preview_tester_quota", args: {} }]);
    if (quota.kind === "ok") expect(testerQuotaLabel(quota)).toBe("Testers externos: 0 / 5");
  });

  it("surfaces a failure instead of an empty quota", async () => {
    const fake = createFakeSupabase(demoDb(), OWNER, {
      failRpcs: { preview_tester_quota: { code: "42501", message: "permission denied" } },
    });
    expect(await loadTesterQuota(fake.client as never, ON)).toEqual({ kind: "error" });
  });

  it("rejects malformed answers", async () => {
    const fake = createFakeSupabase(demoDb(), OWNER, {
      rpcHandlers: { preview_tester_quota: () => ({ used: "x", max: 5 }) },
    });
    expect(await loadTesterQuota(fake.client as never, ON)).toEqual({ kind: "error" });
  });
});

describe("testerQuotaLabel", () => {
  it("uses the external testers wording", () => {
    expect(testerQuotaLabel({ used: 3, max: 5 })).toBe("Testers externos: 3 / 5");
  });
});
