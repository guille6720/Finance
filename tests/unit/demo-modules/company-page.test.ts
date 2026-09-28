/**
 * Company page: missing data reads as "Sin cargar"/empty states, never as fake
 * answers, and failed queries surface an error instead of blank values.
 */
import { describe, it, expect, vi } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { createFakeSupabase, OWNER, ORG_A, demoDb, type FakeDb } from "../../helpers/fake-supabase";

const state: { client: unknown; cookies: Map<string, string> } = { client: null, cookies: new Map() };

vi.mock("@/lib/supabase/server", () => ({ createClient: async () => state.client }));
vi.mock("next/headers", () => ({
  cookies: async () => ({
    get: (name: string) =>
      state.cookies.has(name) ? { name, value: state.cookies.get(name) } : undefined,
  }),
}));
vi.mock("next/navigation", () => ({
  redirect: (to: string) => {
    throw new Error(`REDIRECT:${to}`);
  },
}));

import CompanyPage from "@/app/(app)/company/page";
import { ACTIVE_ORG_COOKIE } from "@/lib/authz/context";

async function render(db: FakeDb, failTables?: string[]) {
  state.client = createFakeSupabase(db, OWNER, { failTables }).client;
  state.cookies = new Map([[ACTIVE_ORG_COOKIE, ORG_A]]);
  return renderToStaticMarkup(await CompanyPage());
}

describe("company page", () => {
  it("shows empty states instead of fabricated profile answers", async () => {
    const html = await render(demoDb());
    expect(html).toContain("EMPRESA DEMO ARGENTINA SA");
    expect(html).toContain("Sin cargar");
    expect(html).toContain("Todavía no se completó el perfil del negocio.");
    expect(html).not.toContain("Productos: No");
    expect(html).toContain("Todavía no hay sucursales cargadas.");
  });

  it("translates the business type when the profile exists", async () => {
    const db = demoDb();
    db.business_profiles = [
      { id: "bp", organization_id: ORG_A, business_type: "retail", sells_products: true, sells_services: false, manages_inventory: true, has_employees: false, has_multiple_branches: false },
    ];
    const html = await render(db);
    expect(html).toContain("Comercio minorista");
    expect(html).not.toContain(">retail<");
    expect(html).toContain("Productos: Sí");
  });

  it("surfaces query failures without leaking internals", async () => {
    const html = await render(demoDb(), ["business_profiles", "branches"]);
    expect(html.match(/data-testid="module-load-error"/g)?.length).toBe(2);
    expect(html).not.toContain("secret detail");
    expect(html).not.toContain("Todavía no se completó el perfil del negocio.");
  });
});
