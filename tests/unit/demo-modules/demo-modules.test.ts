/**
 * Read-only demo modules (customers, suppliers, cash, accounting, reports, dashboard):
 * active-organization scoping, tenant isolation, business filters and error states.
 * Supabase is an in-memory double that simulates membership-based RLS and PostgREST
 * FK embedding (PGRST200/PGRST201).
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { createFakeSupabase, OWNER, SOLO, OUTSIDER, type FakeDb } from "../../helpers/fake-supabase";
import {
  demoModulesDb,
  EMPRESA_DEMO_MARKERS,
  FOREIGN_MARKERS,
  BETA_MARKERS,
  ORG_A,
  ORG_B,
  ORG_C,
} from "../../helpers/demo-modules-fixture";

const state: { client: unknown; cookies: Map<string, string> } = {
  client: null,
  cookies: new Map(),
};

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
vi.mock("next/link", () => ({
  default: ({ href, children, ...rest }: { href: string; children: unknown }) =>
    createElement("a", { href, ...rest }, children as never),
}));

import CustomersPage from "@/app/(app)/customers/page";
import SuppliersPage from "@/app/(app)/suppliers/page";
import CashPage from "@/app/(app)/cash/page";
import AccountingPage from "@/app/(app)/accounting/page";
import ReportsPage from "@/app/(app)/reports/page";
import DashboardPage from "@/app/(app)/dashboard/page";
import { navigation } from "@/components/shell/app-sidebar";
import { ACTIVE_ORG_COOKIE } from "@/lib/authz/active-organization";
import { LOAD_ERROR_MESSAGE, REPORTS_NOTICE } from "@/components/demo/module-ui";
import { formatARS, toUnits } from "@/lib/demo-data/format";
import { summarizeCash, sumDebitCredit, summarizeCounterparties } from "@/lib/demo-data/loaders";
import { allRows, MAX_ROWS } from "@/lib/demo-data/query";

type Page = () => Promise<unknown>;

const MODULE_PAGES: [string, Page][] = [
  ["customers", CustomersPage as Page],
  ["suppliers", SuppliersPage as Page],
  ["cash", CashPage as Page],
  ["accounting", AccountingPage as Page],
  ["reports", ReportsPage as Page],
];

const MODULE_TABLES = new Set([
  "counterparty_roles",
  "counterparties",
  "sales_documents",
  "purchase_documents",
  "treasury_accounts",
  "treasury_operations",
  "treasury_operation_legs",
  "journal_entries",
  "journal_entry_lines",
  "tax_periods",
]);

function asUser(userId: string | null, cookieOrg?: string, db: FakeDb = demoModulesDb(), failTables?: string[]) {
  const fake = createFakeSupabase(db, userId, { failTables });
  state.client = fake.client;
  state.cookies = new Map(cookieOrg ? [[ACTIVE_ORG_COOKIE, cookieOrg]] : []);
  return fake;
}

async function render(page: Page) {
  return renderToStaticMarkup((await page()) as never);
}

function stat(html: string, testId: string): string {
  const m = new RegExp(`data-testid="${testId}"[\\s\\S]*?<h3[^>]*>([\\s\\S]*?)</h3>`).exec(html);
  if (!m) throw new Error(`stat ${testId} not found`);
  return m[1];
}

function expectNone(html: string, markers: string[]) {
  for (const m of markers) expect(html, `leaked marker: ${m}`).not.toContain(m);
}

let errorSpy: ReturnType<typeof vi.spyOn>;
beforeEach(() => {
  errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
});
afterEach(() => {
  errorSpy.mockRestore();
});

describe("sidebar", () => {
  it("enables the five demo modules and keeps Banks as coming soon", () => {
    const items = navigation.flatMap((g) => g.items);
    const status = (href: string) => items.find((i) => i.href === href)?.status;
    for (const href of ["/customers", "/suppliers", "/cash", "/accounting", "/reports"]) {
      expect(status(href), href).toBe("active");
    }
    expect(status("/banks")).toBe("coming_soon");
    expect(items.filter((i) => i.status === "coming_soon").map((i) => i.href)).toEqual(["/banks"]);
  });
});

describe("customers", () => {
  it("lists only CUSTOMER counterparties of the active organization", async () => {
    asUser(OWNER, ORG_A);
    const html = await render(CustomersPage as Page);
    expect(html).toContain("Clientes registrados para la empresa activa.");
    expect(html).toContain("Alfa Comercial");
    expect(html).toContain("CLIENTE DORMIDO SRL");
    expect(html).toContain("MIXTO SA");
    expect(html).not.toContain("PROVEEDOR GAMMA SRL");
    expectNone(html, [...BETA_MARKERS, ...FOREIGN_MARKERS]);
    expect(stat(html, "stat-total")).toBe("3");
    expect(stat(html, "stat-active")).toBe("2");
    expect(stat(html, "stat-with-documents")).toBe("2");
  });
});

describe("suppliers", () => {
  it("lists only SUPPLIER counterparties of the active organization", async () => {
    asUser(OWNER, ORG_A);
    const html = await render(SuppliersPage as Page);
    expect(html).toContain("PROVEEDOR GAMMA SRL");
    expect(html).toContain("MIXTO SA");
    expect(html).not.toContain("Alfa Comercial");
    expect(html).not.toContain("CLIENTE DORMIDO SRL");
    expectNone(html, [...BETA_MARKERS, ...FOREIGN_MARKERS]);
    expect(stat(html, "stat-total")).toBe("2");
    expect(stat(html, "stat-with-documents")).toBe("2");
  });
});

describe("cash", () => {
  it("only uses CASH accounts and sums POSTED legs by direction", async () => {
    asUser(OWNER, ORG_A);
    const html = await render(CashPage as Page);
    expect(stat(html, "stat-cash-accounts")).toBe("1");
    expect(stat(html, "stat-posted-operations")).toBe("2");
    expect(stat(html, "stat-inflows")).toBe(formatARS("150000"));
    expect(stat(html, "stat-outflows")).toBe(formatARS("2500"));
    expect(html).toContain(formatARS("147500"));
    expect(html).toContain("Caja principal");
    expect(html).not.toContain("Banco Galicia CC");
    expect(html).not.toContain("Valores a depositar");
    expect(html).not.toContain("Apertura cuenta bancaria");
    expect(html).not.toContain("Transferencia a valores");
    // Reversed / draft movements are listed but never added to totals.
    expect(html).toContain("Cobranza revertida");
    expect(html).toContain("Revertido");
    expectNone(html, FOREIGN_MARKERS);
  });
});

describe("accounting", () => {
  it("counts entries and totals debit/credit of POSTED and REVERSED lines only", async () => {
    asUser(OWNER, ORG_A);
    const html = await render(AccountingPage as Page);
    expect(stat(html, "stat-posted-entries")).toBe("2");
    expect(stat(html, "stat-reversed-entries")).toBe("1");
    expect(stat(html, "stat-total-debit")).toBe(formatARS("1400.5"));
    expect(stat(html, "stat-total-credit")).toBe(formatARS("1400.5"));
    expect(html).toContain("Control de partida doble");
    expect(html).toContain("Balanceado");
    expect(html).not.toContain(">Revisar<");
    expect(html).toContain("Asiento de apertura");
    expect(html).not.toContain("Borrador desbalanceado");
    expectNone(html, FOREIGN_MARKERS);
  });

  it("flags 'Revisar' when visible debits and credits differ", async () => {
    const db = demoModulesDb();
    db.journal_entry_lines.push({
      id: "jl-bad",
      organization_id: ORG_A,
      journal_entry_id: "je1",
      account_id: "acc1",
      debit: "0.0100",
      credit: "0",
      line_number: 3,
    });
    asUser(OWNER, ORG_A, db);
    const html = await render(AccountingPage as Page);
    expect(html).toContain("Revisar");
    expect(html).not.toContain(">Balanceado<");
    expect(html).toContain(formatARS("0.01"));
  });
});

describe("reports", () => {
  it("builds the snapshot from the active organization only", async () => {
    asUser(OWNER, ORG_A);
    const html = await render(ReportsPage as Page);
    expect(html).toContain(REPORTS_NOTICE);
    // Sales: confirmed sales orders only (s1 + s5); quote, draft and cancelled excluded.
    expect(html).toContain(formatARS("3000.5"));
    // Purchases: POSTED invoice minus POSTED credit note.
    expect(html).toContain(formatARS("400.25"));
    // Treasury: gross volume of POSTED operations.
    expect(html).toContain(formatARS("1272500"));
    expect(html).toContain("volumen de movimientos, no saldo disponible");
    expect(html).toContain("03/2026");
    expect(html).toContain("02/2026");
    expect(html).toContain("01/2026");
    expect(html).not.toContain("12/2025");
    expect(html).not.toMatch(/presentad[oa]|cumplimiento fiscal|enviado a ARCA/i);
    expectNone(html, FOREIGN_MARKERS);
  });
});

describe("dashboard", () => {
  it("shows real organization metrics instead of placeholders", async () => {
    asUser(OWNER, ORG_A);
    const html = await render(DashboardPage as Page);
    expect(html).not.toContain("Sin datos aún");
    expect(stat(html, "kpi-sales")).toBe(formatARS("3000.5"));
    expect(stat(html, "kpi-purchases")).toBe(formatARS("400.25"));
    expect(stat(html, "kpi-cash-balance")).toBe(formatARS("147500"));
    expect(html).toContain("Tesorería total: 4 operaciones");
    expect(stat(html, "card-journal")).toBe("2");
    expect(stat(html, "card-customers")).toBe("3");
    expect(stat(html, "card-suppliers")).toBe("2");
    expect(stat(html, "card-cash-movements")).toBe("2");
    expect(html).not.toMatch(/Disponible|Clientes que me deben|Proveedores a pagar/);
  });
});

describe("tenant isolation", () => {
  it("Empresa Demo data never appears while Demo Beta is selected", async () => {
    asUser(OWNER, ORG_B);
    for (const [name, page] of [...MODULE_PAGES, ["dashboard", DashboardPage as Page] as const]) {
      const html = await render(page);
      expectNone(html, [...EMPRESA_DEMO_MARKERS, ...FOREIGN_MARKERS]);
      expect(html, name).not.toContain(formatARS("150000"));
      expect(html, name).not.toContain(formatARS("1400.5"));
    }
    const customers = await render(CustomersPage as Page);
    expect(customers).toContain("CLIENTE SOLO BETA SRL");
  });

  it("a personal tenant cannot read demo organization data, even with a forged cookie", async () => {
    const fake = asUser(OUTSIDER, ORG_A);
    for (const [, page] of MODULE_PAGES) {
      const html = await render(page);
      expectNone(html, [...EMPRESA_DEMO_MARKERS, ...BETA_MARKERS]);
    }
    const customers = await render(CustomersPage as Page);
    expect(customers).toContain("CLIENTE AJENO SA");
    const touchedA = fake.log.filter(
      (l) =>
        l.filters.some(([, v]) => v === ORG_A) ||
        (l.inFilters ?? []).some(([, vs]) => vs.includes(ORG_A))
    );
    expect(touchedA).toEqual([]);
  });

  it("forged active_organization_id for another tenant falls back to the user's own org", async () => {
    const fake = asUser(SOLO, ORG_B);
    for (const [, page] of MODULE_PAGES) {
      const html = await render(page);
      expectNone(html, [...BETA_MARKERS, ...FOREIGN_MARKERS]);
    }
    expect(await render(CustomersPage as Page)).toContain("Alfa Comercial");
    expect(fake.log.filter((l) => l.filters.some(([, v]) => v === ORG_B))).toEqual([]);
  });

  it("an inactive membership cookie is ignored", async () => {
    asUser(OWNER, ORG_C);
    const html = await render(CustomersPage as Page);
    expect(html).toContain("Alfa Comercial");
    expect(html).not.toContain("CLIENTE AJENO SA");
  });

  it("every module query is scoped to organization_id = resolved organization", async () => {
    for (const org of [ORG_A, ORG_B]) {
      const fake = asUser(OWNER, org);
      for (const [, page] of [...MODULE_PAGES, ["dashboard", DashboardPage as Page] as const]) {
        await render(page);
      }
      const moduleQueries = fake.log.filter((l) => MODULE_TABLES.has(l.table));
      expect(moduleQueries.length).toBeGreaterThan(10);
      for (const q of moduleQueries) {
        expect(q.filters, `${q.table} ${q.columns}`).toContainEqual(["organization_id", org]);
      }
    }
  });

  it("unauthenticated users are redirected to /login on every page", async () => {
    asUser(null);
    for (const [, page] of [...MODULE_PAGES, ["dashboard", DashboardPage as Page] as const]) {
      await expect(page()).rejects.toThrow("REDIRECT:/login");
    }
  });
});

describe("query failures are never shown as empty data", () => {
  const cases: [string, Page, string][] = [
    ["customers", CustomersPage as Page, "counterparty_roles"],
    ["suppliers", SuppliersPage as Page, "purchase_documents"],
    ["cash", CashPage as Page, "treasury_operation_legs"],
    ["accounting", AccountingPage as Page, "journal_entry_lines"],
    ["reports", ReportsPage as Page, "sales_documents"],
    ["dashboard", DashboardPage as Page, "purchase_documents"],
  ];

  for (const [name, page, table] of cases) {
    it(`${name}: ${table} failure renders a generic error without internals`, async () => {
      asUser(OWNER, ORG_A, demoModulesDb(), [table]);
      const html = await render(page);
      expect(html).toContain(LOAD_ERROR_MESSAGE);
      expect(html).not.toContain('data-testid="module-empty"');
      expect(html).not.toMatch(/Todavía no hay (clientes|proveedores|movimientos|asientos)/);
      expect(html).not.toMatch(/XX000|secret detail|relation /);
      expect(errorSpy).toHaveBeenCalledWith(
        "[demo-data] query failed",
        expect.objectContaining({ code: "XX000" })
      );
    });
  }

  it("the test double enforces PostgREST FK disambiguation (PGRST201)", async () => {
    const { client } = createFakeSupabase(demoModulesDb(), OWNER);
    const r = await (client.from("journal_entry_lines") as unknown as {
      select: (c: string) => PromiseLike<{ error: { code: string } | null }>;
    }).select("id, counterparties ( legal_name )");
    expect(r.error).toBeNull();
    const amb = await (client.from("purchase_documents") as unknown as {
      select: (c: string) => PromiseLike<{ error: { code: string } | null }>;
    }).select("id, journal_entries ( status )");
    expect(amb.error?.code).toBe("PGRST201");
  });

  it("the membership lookup failing does not fall back to any organization", async () => {
    asUser(OWNER, ORG_A, demoModulesDb(), ["organization_members"]);
    await expect(render(CustomersPage as Page)).rejects.toThrow(LOAD_ERROR_MESSAGE);
  });
});

describe("pure calculations", () => {
  it("money arithmetic is exact on numeric(19,4) strings", () => {
    expect(toUnits("0.1") + toUnits("0.2")).toBe(toUnits("0.3"));
    expect(toUnits("1000.5000")).toBe(BigInt(10_005_000));
    expect(toUnits("-2.5")).toBe(BigInt(-25_000));
    expect(toUnits("abc")).toBe(BigInt(0));
    const t = sumDebitCredit([
      { debit: "0.1", credit: "0" },
      { debit: "0.2", credit: "0" },
      { debit: "0", credit: "0.3" },
    ]);
    expect(t.balanced).toBe(true);
    expect(t.difference).toBe(BigInt(0));
  });

  it("summarizeCash ignores non-cash accounts, foreign operations and non-posted totals", () => {
    const summary = summarizeCash(
      [{ id: "cash", code: "C", name: "Caja", currency_code: "ARS", is_active: true }],
      [
        { id: "a", treasury_account_id: "cash", direction: "INFLOW", amount: "100", treasury_operations: { id: "o1", organization_id: "org", internal_number: "1", operation_type: "PAYMENT", status: "POSTED", operation_date: "2026-01-01", description: "ok", created_at: "x" } },
        { id: "b", treasury_account_id: "bank", direction: "INFLOW", amount: "999", treasury_operations: { id: "o2", organization_id: "org", internal_number: "2", operation_type: "PAYMENT", status: "POSTED", operation_date: "2026-01-01", description: "bank", created_at: "x" } },
        { id: "c", treasury_account_id: "cash", direction: "INFLOW", amount: "777", treasury_operations: { id: "o3", organization_id: "other", internal_number: "3", operation_type: "PAYMENT", status: "POSTED", operation_date: "2026-01-01", description: "foreign", created_at: "x" } },
        { id: "d", treasury_account_id: "cash", direction: "OUTFLOW", amount: "40", treasury_operations: { id: "o4", organization_id: "org", internal_number: "4", operation_type: "PAYMENT", status: "REVERSED", operation_date: "2026-01-01", description: "rev", created_at: "x" } },
      ],
      "org"
    );
    expect(summary.inflows).toBe(toUnits("100"));
    expect(summary.outflows).toBe(BigInt(0));
    expect(summary.balance).toBe(toUnits("100"));
    expect(summary.recent.map((m) => m.legId).sort()).toEqual(["a", "d"]);
  });

  it("summarizeCounterparties drops embedded rows from another organization", () => {
    const s = summarizeCounterparties(
      [
        { counterparty_id: "x", counterparties: { id: "x", organization_id: "org", legal_name: "X SA", trade_name: null, tax_id: null, email: null, phone: null, is_active: true } },
        { counterparty_id: "y", counterparties: { id: "y", organization_id: "other", legal_name: "Y SA", trade_name: null, tax_id: null, email: null, phone: null, is_active: true } },
      ],
      ["x", "y", null],
      "org"
    );
    expect(s.counterparties.map((c) => c.id)).toEqual(["x"]);
    expect(s.withDocuments).toBe(1);
  });

  it("allRows pages through results and fails closed past the row cap", async () => {
    const pages: [number, number][] = [];
    const ok = await allRows("t", async (from, to) => {
      pages.push([from, to]);
      const n = from === 0 ? 1000 : 3;
      return { data: Array.from({ length: n }, (_, i) => ({ i: from + i })), error: null };
    });
    expect(ok.ok && ok.data.length).toBe(1003);
    expect(pages).toEqual([
      [0, 999],
      [1000, 1999],
    ]);
    const capped = await allRows("t", async () => ({
      data: Array.from({ length: 1000 }, () => ({})),
      error: null,
    }));
    expect(capped.ok).toBe(false);
    expect(MAX_ROWS).toBeGreaterThan(1000);
  });
});
