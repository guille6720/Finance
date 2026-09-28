/**
 * Edición, desactivación y borrado de clientes/proveedores: permisos por rol,
 * aislamiento por empresa y mensajes claros cuando la base lo impide.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { createFakeSupabase, OWNER, SOLO, ORG_A, ORG_B, demoDb, type FakeDb } from "../../helpers/fake-supabase";

const state: { client: unknown; cookies: Map<string, string> } = { client: null, cookies: new Map() };

vi.mock("@/lib/supabase/server", () => ({ createClient: async () => state.client }));
vi.mock("next/headers", () => ({
  cookies: async () => ({
    get: (name: string) => (state.cookies.has(name) ? { name, value: state.cookies.get(name) } : undefined),
  }),
}));
vi.mock("next/navigation", () => ({
  redirect: (to: string) => {
    throw new Error(`REDIRECT:${to}`);
  },
  notFound: () => {
    throw new Error("NOT_FOUND");
  },
}));
vi.mock("next/cache", () => ({ revalidatePath: () => {} }));

import { deleteCounterparty, setCounterpartyActive, updateCounterparty } from "@/lib/counterparties/actions";
import { EditCounterpartyPage } from "@/components/counterparties/edit-counterparty-page";
import { ACTIVE_ORG_COOKIE } from "@/lib/authz/context";

const CP = "0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f";
const CP_B = "0e0e0e0e-0e0e-4e0e-8e0e-0e0e0e0e0e0e";
const VIEWER = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const OPERATOR = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";

function db(): FakeDb {
  const d = demoDb();
  d.organization_members.push(
    { id: "m6", organization_id: ORG_A, user_id: VIEWER, role: "viewer", status: "active" },
    { id: "m7", organization_id: ORG_A, user_id: OPERATOR, role: "operator", status: "active" }
  );
  d.counterparties = [
    {
      id: CP,
      organization_id: ORG_A,
      legal_name: "Cliente Uno SA",
      trade_name: null,
      entity_type: "LEGAL_ENTITY",
      tax_id_type: "CUIT",
      tax_id: "20-12345678-6",
      tax_id_normalized: "20123456786",
      email: null,
      phone: null,
      is_active: true,
    },
    { id: CP_B, organization_id: ORG_B, legal_name: "De Beta", tax_id_normalized: "30000000001", is_active: true },
  ];
  d.counterparty_roles = [
    { id: "r1", organization_id: ORG_A, counterparty_id: CP, role: "CUSTOMER" },
    { id: "r2", organization_id: ORG_B, counterparty_id: CP_B, role: "CUSTOMER" },
  ];
  return d;
}

function setup(data: FakeDb, user: string, opts: Parameters<typeof createFakeSupabase>[2] = {}) {
  const fake = createFakeSupabase(data, user, opts);
  state.client = fake.client;
  state.cookies = new Map([[ACTIVE_ORG_COOKIE, ORG_A]]);
  return fake;
}

function form(fields: Record<string, string> = {}) {
  const fd = new FormData();
  const base = {
    legalName: "Cliente Uno Renombrado SA",
    tradeName: "",
    entityType: "LEGAL_ENTITY",
    taxIdType: "CUIT",
    taxId: "20-12345678-6",
    email: "nuevo@cliente.example",
    phone: "",
  };
  for (const [k, v] of Object.entries({ ...base, ...fields })) fd.set(k, v);
  return fd;
}

async function attempt<T>(fn: () => Promise<T>) {
  try {
    return { result: await fn(), redirect: null as string | null };
  } catch (e) {
    const msg = (e as Error).message;
    if (msg.startsWith("REDIRECT:")) return { result: null, redirect: msg.slice(9) };
    throw e;
  }
}

beforeEach(() => {
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("updateCounterparty", () => {
  it("saves the changes and returns to the list", async () => {
    const data = db();
    setup(data, OPERATOR);
    const res = await attempt(() => updateCounterparty("CUSTOMER", CP, {}, form()));
    expect(res.redirect).toBe("/customers?guardado=1");
    expect(data.counterparties[0]).toMatchObject({ legal_name: "Cliente Uno Renombrado SA", email: "nuevo@cliente.example" });
  });

  it("rejects a document that belongs to another record", async () => {
    const data = db();
    data.counterparties.push({ id: "cp-2", organization_id: ORG_A, legal_name: "Otro SA", tax_id_normalized: "30712345671" });
    setup(data, OWNER);
    const res = await attempt(() => updateCounterparty("CUSTOMER", CP, {}, form({ taxId: "30-71234567-1" })));
    expect(res.result?.fieldErrors?.taxId).toBe("Ese documento ya lo tiene otro registro: Otro SA.");
  });

  it("cannot touch a record from another company", async () => {
    const data = db();
    setup(data, OWNER);
    const res = await attempt(() => updateCounterparty("CUSTOMER", CP_B, {}, form()));
    expect(res.result?.error).toBe("No encontramos el registro en esta empresa.");
    expect(data.counterparties[1].legal_name).toBe("De Beta");
  });

  it("rejects viewers", async () => {
    const data = db();
    const fake = setup(data, VIEWER);
    const res = await attempt(() => updateCounterparty("CUSTOMER", CP, {}, form()));
    expect(res.result?.error).toBe("Tu rol no permite modificar clientes.");
    expect(fake.updates).toHaveLength(0);
  });
});

describe("setCounterpartyActive / deleteCounterparty", () => {
  it("deactivates and reactivates", async () => {
    const data = db();
    setup(data, OPERATOR);
    expect((await attempt(() => setCounterpartyActive("CUSTOMER", CP, false))).redirect).toBe(
      `/customers/${CP}?desactivado=1`
    );
    expect(data.counterparties[0].is_active).toBe(false);
  });

  it("only owner/admin can delete", async () => {
    const data = db();
    setup(data, OPERATOR);
    expect((await attempt(() => deleteCounterparty("CUSTOMER", CP))).result?.error).toBe(
      "Tu rol no permite eliminar clientes."
    );
    setup(data, OWNER);
    expect((await attempt(() => deleteCounterparty("CUSTOMER", CP))).redirect).toBe("/customers?eliminado=1");
    expect(data.counterparties.find((c) => c.id === CP)).toBeUndefined();
  });

  it("explains why a record with movements cannot be deleted", async () => {
    setup(db(), OWNER, {
      failDeletes: {
        counterparties: {
          code: "P0001",
          message: "counterparty with journal references cannot be deleted; deactivate instead",
        },
      },
    });
    const res = await attempt(() => deleteCounterparty("CUSTOMER", CP));
    expect(res.result?.error).toMatch(/tiene comprobantes o asientos asociados/);
    expect(res.result?.error).not.toContain("journal");
  });
});

describe("EditCounterpartyPage", () => {
  it("shows the form, deactivate and delete to the owner", async () => {
    setup(db(), OWNER);
    const html = renderToStaticMarkup(await EditCounterpartyPage({ role: "CUSTOMER", id: CP }));
    expect(html).toContain("Guardar cambios");
    expect(html).toContain(">Desactivar</button>");
    expect(html).toContain(">Eliminar</button>");
    expect(html).toContain("También es proveedor");
  });

  it("accountant can edit but not delete nor add roles", async () => {
    setup(db(), SOLO);
    const html = renderToStaticMarkup(await EditCounterpartyPage({ role: "CUSTOMER", id: CP }));
    expect(html).toContain("Guardar cambios");
    expect(html).not.toContain(">Eliminar</button>");
    expect(html).not.toContain("También es proveedor");
  });

  it("viewer sees read-only data", async () => {
    setup(db(), VIEWER);
    const html = renderToStaticMarkup(await EditCounterpartyPage({ role: "CUSTOMER", id: CP }));
    expect(html).not.toContain("Guardar cambios");
    expect(html).toContain("no modificarlos");
  });

  it("404 for another company's record or the wrong role", async () => {
    setup(db(), OWNER);
    await expect(EditCounterpartyPage({ role: "CUSTOMER", id: CP_B })).rejects.toThrow("NOT_FOUND");
    await expect(EditCounterpartyPage({ role: "SUPPLIER", id: CP })).rejects.toThrow("NOT_FOUND");
    await expect(EditCounterpartyPage({ role: "CUSTOMER", id: "no-uuid" })).rejects.toThrow("NOT_FOUND");
  });
});
