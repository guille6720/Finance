/**
 * When the Staging trigger rejects a sixth tester, the organization insert fails with
 * STAGING_TESTER_LIMIT_REACHED: onboarding must show the friendly Spanish message,
 * stop there, and never surface the raw code.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { createFakeSupabase, OWNER, demoDb, type FakeDb } from "../../helpers/fake-supabase";

const state = { fake: null as ReturnType<typeof createFakeSupabase> | null };

vi.mock("@/lib/authz/context", () => ({
  ACTIVE_ORG_COOKIE: "active_organization_id",
  requireUser: async () => ({ supabase: state.fake!.client, user: { id: OWNER } }),
}));
vi.mock("next/headers", () => ({ cookies: async () => ({ set: vi.fn(), get: vi.fn() }) }));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("@/lib/audit/write-audit-event", () => ({ writeAuditEvent: vi.fn() }));
vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: () => {
    throw new Error("must not be called");
  },
}));

import { completeOnboarding } from "@/lib/onboarding/actions";

const input = {
  legalName: "Tester SRL",
  cuit: "20123456786",
  province: "Buenos Aires",
  fiscalConditionCode: "RI",
  fiscalAddress: "Calle Falsa 123",
  businessType: "services",
  sellsProducts: false,
  sellsServices: true,
  managesInventory: false,
  hasEmployees: false,
  hasMultipleBranches: false,
  needsProjects: false,
  needsCostCenters: false,
  invoicesCustomers: true,
  worksWithSuppliers: true,
};

function db(): FakeDb {
  const d = demoDb();
  d.fiscal_conditions = [{ id: "fc-ri", code: "RI" }];
  return d;
}

beforeEach(() => {
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("completeOnboarding with the tester limit reached", () => {
  it("returns the Spanish limit message and creates nothing else", async () => {
    state.fake = createFakeSupabase(db(), OWNER, {
      failInserts: {
        organizations: {
          code: "P0001",
          message: "STAGING_TESTER_LIMIT_REACHED",
          details: "Public preview is limited to 5 tester accounts.",
        },
      },
    });
    const res = await completeOnboarding(input);
    expect(res).toEqual({
      ok: false,
      error: "Se alcanzó el límite de 5 usuarios de prueba. Contactanos si necesitás acceso.",
    });
    expect(JSON.stringify(res)).not.toContain("STAGING_TESTER_LIMIT_REACHED");
    expect(state.fake.inserts.filter((i) => i.table !== "organizations")).toHaveLength(0);
    expect(state.fake.rpcs).toHaveLength(0);
  });

  it("other insert failures keep the generic message", async () => {
    state.fake = createFakeSupabase(db(), OWNER, {
      failInserts: { organizations: { code: "23505", message: "duplicate key value" } },
    });
    expect(await completeOnboarding(input)).toEqual({ ok: false, error: "No se pudo crear la empresa" });
  });
});
