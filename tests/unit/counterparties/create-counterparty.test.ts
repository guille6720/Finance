/**
 * Alta de clientes/proveedores: la organización sale de la sesión (nunca del
 * formulario), solo roles con permiso pueden crear, los duplicados se detectan
 * por documento y los errores de base no filtran detalles internos.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import {
  createFakeSupabase,
  OWNER,
  SOLO,
  ORG_A,
  ORG_B,
  demoDb,
  type FakeDb,
} from "../../helpers/fake-supabase";

const state: {
  client: unknown;
  cookies: Map<string, string>;
  revalidated: string[];
} = { client: null, cookies: new Map(), revalidated: [] };

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
vi.mock("next/cache", () => ({
  revalidatePath: (p: string) => {
    state.revalidated.push(p);
  },
}));

import { createCounterparty } from "@/lib/counterparties/actions";
import { counterpartyFormSchema, normalizeTaxId } from "@/lib/counterparties/schema";
import { noticeFromSearchParams } from "@/lib/counterparties/notice";
import { CounterpartyPage } from "@/components/demo/counterparty-page";
import { NewCounterpartyPage } from "@/components/counterparties/new-counterparty-page";
import { ACTIVE_ORG_COOKIE } from "@/lib/authz/context";

const VALID_CUIT = "20-12345678-6";
const VIEWER = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const OPERATOR = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";

function db(): FakeDb {
  const d = demoDb();
  d.organization_members.push(
    { id: "m6", organization_id: ORG_A, user_id: VIEWER, role: "viewer", status: "active" },
    { id: "m7", organization_id: ORG_A, user_id: OPERATOR, role: "operator", status: "active" }
  );
  d.counterparties = [];
  d.counterparty_roles = [];
  return d;
}

function setup(
  data: FakeDb,
  user: string,
  opts: Parameters<typeof createFakeSupabase>[2] = {},
  org = ORG_A
) {
  const fake = createFakeSupabase(data, user, opts);
  state.client = fake.client;
  state.cookies = new Map([[ACTIVE_ORG_COOKIE, org]]);
  return fake;
}

function form(fields: Record<string, string>) {
  const fd = new FormData();
  const base = {
    legalName: "Distribuidora del Sur SA",
    tradeName: "",
    entityType: "LEGAL_ENTITY",
    taxIdType: "CUIT",
    taxId: VALID_CUIT,
    email: "",
    phone: "",
  };
  for (const [k, v] of Object.entries({ ...base, ...fields })) fd.set(k, v);
  return fd;
}

async function submit(role: "CUSTOMER" | "SUPPLIER", fd: FormData) {
  try {
    return { state: await createCounterparty(role, {}, fd), redirect: null as string | null };
  } catch (e) {
    const msg = (e as Error).message;
    if (msg.startsWith("REDIRECT:")) return { state: null, redirect: msg.slice(9) };
    throw e;
  }
}

beforeEach(() => {
  state.revalidated = [];
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("counterparty form schema", () => {
  const parse = (over: Record<string, unknown>) =>
    counterpartyFormSchema.safeParse({
      legalName: "Cliente Uno",
      tradeName: "",
      entityType: "LEGAL_ENTITY",
      taxIdType: "CUIT",
      taxId: VALID_CUIT,
      email: "",
      phone: "",
      alsoOtherRole: false,
      ...over,
    });

  it("accepts a valid CUIT and turns blanks into null", () => {
    const r = parse({});
    expect(r.success).toBe(true);
    if (r.success) {
      expect(r.data.tradeName).toBeNull();
      expect(r.data.email).toBeNull();
    }
  });

  it("rejects a CUIT with a wrong check digit, in Spanish", () => {
    const r = parse({ taxId: "20-12345678-0" });
    expect(r.success).toBe(false);
    if (!r.success) expect(r.error.issues[0].message).toMatch(/CUIT no es válido/);
  });

  it("validates DNI length, email and allows no document", () => {
    expect(parse({ taxIdType: "DNI", taxId: "123" }).success).toBe(false);
    expect(parse({ taxIdType: "DNI", taxId: "30.123.456" }).success).toBe(true);
    expect(parse({ email: "no-es-email" }).success).toBe(false);
    expect(parse({ taxIdType: "NONE", taxId: "" }).success).toBe(true);
    expect(parse({ taxIdType: "CUIT", taxId: "" }).success).toBe(false);
    expect(parse({ legalName: " a " }).success).toBe(false);
  });

  it("normalizes tax ids like the database does", () => {
    expect(normalizeTaxId("CUIT", VALID_CUIT)).toBe("20123456786");
    expect(normalizeTaxId("PASSPORT", "ab-123 x")).toBe("AB123X");
    expect(normalizeTaxId("NONE", "123")).toBeNull();
  });
});

describe("createCounterparty action", () => {
  it("creates a customer in the session organization and redirects", async () => {
    const data = db();
    const fake = setup(data, OWNER);
    const res = await submit("CUSTOMER", form({ email: "compras@sur.example" }));
    expect(res.redirect).toBe("/customers?creado=1");
    const cp = fake.inserts.find((i) => i.table === "counterparties")!.row;
    expect(cp).toMatchObject({
      organization_id: ORG_A,
      legal_name: "Distribuidora del Sur SA",
      tax_id_type: "CUIT",
      email: "compras@sur.example",
      created_by: OWNER,
    });
    const roles = fake.inserts.filter((i) => i.table === "counterparty_roles").map((i) => i.row);
    expect(roles).toEqual([
      expect.objectContaining({ counterparty_id: cp.id, organization_id: ORG_A, role: "CUSTOMER" }),
    ]);
    const audit = fake.inserts.find((i) => i.table === "audit_events")!.row;
    expect(audit).toMatchObject({ event_type: "counterparty.created", organization_id: ORG_A });
    expect(state.revalidated).toEqual(expect.arrayContaining(["/customers", "/suppliers", "/dashboard"]));
  });

  it("ignores any organization sent in the form", async () => {
    const data = db();
    const fake = setup(data, OWNER, {}, ORG_B);
    const fd = form({});
    fd.set("organization_id", ORG_A);
    fd.set("organizationId", ORG_A);
    const res = await submit("SUPPLIER", fd);
    expect(res.redirect).toBe("/suppliers?creado=1");
    expect(fake.inserts.find((i) => i.table === "counterparties")!.row.organization_id).toBe(ORG_B);
  });

  it("adds both roles when 'también es…' is checked", async () => {
    const fake = setup(db(), OPERATOR);
    const fd = form({});
    fd.set("alsoOtherRole", "on");
    const res = await submit("SUPPLIER", fd);
    expect(res.redirect).toBe("/suppliers?creado=1");
    const roles = fake.inserts.filter((i) => i.table === "counterparty_roles").map((i) => i.row.role);
    expect(roles.sort()).toEqual(["CUSTOMER", "SUPPLIER"]);
  });

  it.each([
    ["accountant", SOLO],
    ["viewer", VIEWER],
  ])("rejects %s without writing anything", async (_label, user) => {
    const fake = setup(db(), user);
    const res = await submit("CUSTOMER", form({}));
    expect(res.redirect).toBeNull();
    expect(res.state?.error).toBe("Tu rol no permite crear clientes.");
    expect(fake.inserts).toHaveLength(0);
  });

  it("returns field errors and keeps the typed values", async () => {
    const fake = setup(db(), OWNER);
    const res = await submit("CUSTOMER", form({ legalName: "", taxId: "123" }));
    expect(res.state?.fieldErrors?.legalName).toBeTruthy();
    expect(res.state?.fieldErrors?.taxId).toBeTruthy();
    expect(res.state?.values?.taxId).toBe("123");
    expect(fake.inserts).toHaveLength(0);
  });

  it("rejects a duplicate with the same role", async () => {
    const data = db();
    data.counterparties.push({
      id: "cp-1",
      organization_id: ORG_A,
      legal_name: "Ya Cargado SA",
      tax_id_normalized: "20123456786",
    });
    data.counterparty_roles.push({ id: "r1", organization_id: ORG_A, counterparty_id: "cp-1", role: "CUSTOMER" });
    const fake = setup(data, OWNER);
    const res = await submit("CUSTOMER", form({}));
    expect(res.state?.fieldErrors?.taxId).toBe("Ya existe un cliente con ese documento: Ya Cargado SA.");
    expect(fake.inserts).toHaveLength(0);
  });

  it("reuses an existing supplier and only adds the customer role", async () => {
    const data = db();
    data.counterparties.push({
      id: "cp-1",
      organization_id: ORG_A,
      legal_name: "Proveedor Existente SA",
      tax_id_normalized: "20123456786",
    });
    data.counterparty_roles.push({ id: "r1", organization_id: ORG_A, counterparty_id: "cp-1", role: "SUPPLIER" });
    const fake = setup(data, OWNER);
    const fd = form({});
    fd.set("alsoOtherRole", "on");
    const res = await submit("CUSTOMER", fd);
    expect(res.redirect).toBe("/customers?actualizado=1");
    expect(fake.inserts.filter((i) => i.table === "counterparties")).toHaveLength(0);
    const roles = fake.inserts.filter((i) => i.table === "counterparty_roles").map((i) => i.row);
    expect(roles).toEqual([expect.objectContaining({ counterparty_id: "cp-1", role: "CUSTOMER" })]);
    expect(fake.inserts.find((i) => i.table === "audit_events")!.row.event_type).toBe(
      "counterparty.role_added"
    );
  });

  it("does not see duplicates from another tenant", async () => {
    const data = db();
    data.counterparties.push({
      id: "cp-b",
      organization_id: ORG_B,
      legal_name: "De Otra Empresa",
      tax_id_normalized: "20123456786",
    });
    data.counterparty_roles.push({ id: "rb", organization_id: ORG_B, counterparty_id: "cp-b", role: "CUSTOMER" });
    const fake = setup(data, OPERATOR);
    const res = await submit("CUSTOMER", form({}));
    expect(res.redirect).toBe("/customers?creado=1");
    expect(fake.inserts.find((i) => i.table === "counterparties")!.row.organization_id).toBe(ORG_A);
  });

  it("maps database errors to Spanish without leaking internals", async () => {
    setup(db(), OWNER, {
      failInserts: { counterparties: { code: "23505", message: "duplicate key value violates unique constraint secret_idx" } },
    });
    const dup = await submit("CUSTOMER", form({}));
    expect(dup.state?.fieldErrors?.taxId).toBe("Ya existe un registro con ese documento.");

    setup(db(), OWNER, {
      failInserts: { counterparties: { code: "XX000", message: "internal: secret detail" } },
    });
    const generic = await submit("CUSTOMER", form({}));
    expect(generic.state?.error).toBe("No pudimos guardar los datos. Intentá de nuevo en unos minutos.");
    expect(JSON.stringify(generic.state)).not.toContain("secret");
  });

  it("removes the orphan counterparty when the role insert fails", async () => {
    const data = db();
    const fake = setup(data, OWNER, {
      failInserts: { counterparty_roles: { code: "42501", message: "rls secret detail" } },
    });
    const res = await submit("CUSTOMER", form({}));
    expect(res.state?.error).toBe("No pudimos guardar los datos. Intentá de nuevo en unos minutos.");
    expect(fake.deletes).toEqual([
      expect.objectContaining({ table: "counterparties", count: 1 }),
    ]);
    expect(data.counterparties).toHaveLength(0);
  });
});

describe("counterparty pages", () => {
  it("shows the create button only to roles with permission", async () => {
    setup(db(), OWNER);
    const owner = renderToStaticMarkup(await CounterpartyPage({ role: "CUSTOMER" }));
    expect(owner).toContain('data-testid="counterparty-new"');
    expect(owner).toContain('href="/customers/new"');
    expect(owner).not.toContain("Solo lectura");

    setup(db(), SOLO);
    const accountant = renderToStaticMarkup(await CounterpartyPage({ role: "SUPPLIER" }));
    expect(accountant).not.toContain('data-testid="counterparty-new"');
  });

  it("renders the success notice from the URL", async () => {
    expect(noticeFromSearchParams({ creado: "1" })).toBe("created");
    expect(noticeFromSearchParams({ actualizado: "1" })).toBe("updated");
    expect(noticeFromSearchParams({ creado: "x" })).toBeNull();
    setup(db(), OWNER);
    const html = renderToStaticMarkup(await CounterpartyPage({ role: "SUPPLIER", notice: "created" }));
    expect(html).toContain("Proveedor creado correctamente.");
  });

  it("new page shows the form or a clear message depending on the role", async () => {
    setup(db(), OWNER);
    const allowed = renderToStaticMarkup(await NewCounterpartyPage({ role: "CUSTOMER" }));
    expect(allowed).toContain('data-testid="counterparty-form"');
    expect(allowed).toContain("Guardar cliente");

    setup(db(), SOLO);
    const denied = renderToStaticMarkup(await NewCounterpartyPage({ role: "CUSTOMER" }));
    expect(denied).toContain('data-testid="counterparty-forbidden"');
    expect(denied).not.toContain('data-testid="counterparty-form"');
  });
});
