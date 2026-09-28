/**
 * Business vs accounting UI mode: server-readable cookie preference, mode-specific
 * dashboards, sidebar emphasis, the topbar switcher and the persistence endpoint.
 * The mode is presentation-only; tenant isolation must hold in both modes.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { NextRequest } from "next/server";
import { createFakeSupabase, OWNER, type FakeDb } from "../../helpers/fake-supabase";
import {
  demoModulesDb,
  EMPRESA_DEMO_MARKERS,
  FOREIGN_MARKERS,
  ORG_A,
  ORG_B,
} from "../../helpers/demo-modules-fixture";

const state: { client: unknown; cookies: Map<string, string>; pathname: string } = {
  client: null,
  cookies: new Map(),
  pathname: "/dashboard",
};

vi.mock("@/lib/supabase/server", () => ({ createClient: async () => state.client }));
vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({ auth: { signOut: async () => ({ error: null }) } }),
}));
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
  usePathname: () => state.pathname,
  useRouter: () => ({ push: () => {}, refresh: () => {}, replace: () => {} }),
}));
vi.mock("next/link", () => ({
  default: ({ href, children, ...rest }: { href: string; children: unknown }) =>
    createElement("a", { href, ...rest }, children as never),
}));

import DashboardPage from "@/app/(app)/dashboard/page";
import { POST } from "@/app/api/preferences/ux-mode/route";
import { AppSidebar, navigationForMode } from "@/components/shell/app-sidebar";
import { AppTopbar } from "@/components/shell/app-topbar";
import { requestUxMode } from "@/components/shell/ux-mode-switcher";
import { ACTIVE_ORG_COOKIE } from "@/lib/authz/active-organization";
import {
  DEFAULT_UX_MODE,
  UX_MODE_COOKIE,
  UX_MODE_ENDPOINT,
  isUxMode,
  parseUxMode,
} from "@/lib/ui-mode/constants";
import { LOAD_ERROR_MESSAGE } from "@/components/demo/module-ui";
import {
  featureStatusLabel,
  formatARS,
  humanizeDescription,
  memberStatusLabel,
  toUnits,
} from "@/lib/demo-data/format";
import {
  buildMonthlyActivity,
  buildRecentActivity,
  type CashMovement,
  type ConfirmedSaleRow,
  type PostedPurchaseRow,
} from "@/lib/demo-data/loaders";

function asUser(
  userId: string | null,
  { org, mode, db = demoModulesDb(), failTables }: { org?: string; mode?: string; db?: FakeDb; failTables?: string[] } = {}
) {
  const fake = createFakeSupabase(db, userId, { failTables });
  state.client = fake.client;
  state.cookies = new Map();
  if (org) state.cookies.set(ACTIVE_ORG_COOKIE, org);
  if (mode !== undefined) state.cookies.set(UX_MODE_COOKIE, mode);
  return fake;
}

async function renderDashboard() {
  return renderToStaticMarkup((await DashboardPage()) as never);
}

function stat(html: string, testId: string): string {
  const re = new RegExp(`data-testid="${testId}"[\\s\\S]*?<h3[^>]*>([\\s\\S]*?)</h3>`);
  const m = re.exec(html);
  if (!m) throw new Error(`stat ${testId} not found`);
  return m[1].replace(/<!-- -->/g, "").trim();
}

/** Outer HTML of the element carrying the test id (balanced by tag name). */
function section(html: string, testId: string): string {
  const attr = html.indexOf(`data-testid="${testId}"`);
  if (attr < 0) throw new Error(`section ${testId} not found`);
  const start = html.lastIndexOf("<", attr);
  const tag = /^<([a-z0-9]+)/i.exec(html.slice(start))![1];
  const re = new RegExp(`<${tag}[\\s>]|</${tag}>`, "gi");
  re.lastIndex = start;
  let depth = 0;
  for (let m = re.exec(html); m; m = re.exec(html)) {
    depth += m[0].startsWith("</") ? -1 : 1;
    if (depth === 0) return html.slice(start, m.index + m[0].length);
  }
  throw new Error(`section ${testId} is not closed`);
}

function postMode(body: unknown, { host = "localhost:3000", proto = "http" } = {}) {
  return POST(
    new NextRequest(`${proto}://${host}${UX_MODE_ENDPOINT}`, {
      method: "POST",
      headers: { "content-type": "application/json", host },
      body: typeof body === "string" ? body : JSON.stringify(body),
    })
  );
}

function linkFor(html: string, href: string): string {
  const m = new RegExp(`<a[^>]*href="${href}"[^>]*>`).exec(html);
  if (!m) throw new Error(`link ${href} not found`);
  return m[0];
}

beforeEach(() => {
  state.cookies = new Map();
  state.pathname = "/dashboard";
});

describe("ux mode preference parsing", () => {
  it("accepts only known modes and falls back to business", () => {
    expect(DEFAULT_UX_MODE).toBe("business");
    expect(parseUxMode("business")).toBe("business");
    expect(parseUxMode("accountant")).toBe("accountant");
    expect(parseUxMode(undefined)).toBe("business");
    expect(parseUxMode(null)).toBe("business");
    expect(parseUxMode("admin")).toBe("business");
    expect(parseUxMode("ACCOUNTANT")).toBe("business");
    expect(isUxMode("accountant")).toBe(true);
    expect(isUxMode({ mode: "accountant" })).toBe(false);
  });
});

describe("business mode rendering", () => {
  it("is the default when no preference cookie exists", async () => {
    asUser(OWNER, { org: ORG_A });
    const html = await renderDashboard();
    expect(html).toContain('data-testid="business-dashboard"');
    expect(html).toContain("Resumen de tu negocio");
    expect(html).not.toContain('data-testid="accounting-dashboard"');
    expect(html).not.toContain("Resumen contable");
  });

  it("shows commercial KPIs, activity chart, module cards and recent activity", async () => {
    asUser(OWNER, { org: ORG_A, mode: "business" });
    const html = await renderDashboard();
    expect(html).toMatch(/data-testid="dashboard-title"[^>]*>Resumen de tu negocio</);
    expect(html).toContain("Empresa Demo");
    expect(stat(html, "kpi-sales")).toBe(formatARS("3000.5"));
    expect(stat(html, "kpi-purchases")).toBe(formatARS("400.25"));
    expect(stat(html, "kpi-cash-balance")).toBe(formatARS("147500"));
    expect(section(html, "kpi-accounting-status")).toContain("Balanceado");
    expect(section(html, "business-accounting-status")).toContain(formatARS("1400.5"));

    const chart = section(html, "activity-chart");
    expect(chart).toMatch(/ene/i);
    expect(chart).toMatch(/feb/i);
    expect(chart).toMatch(/mar/i);

    expect(stat(html, "card-customers")).toBe("3");
    expect(stat(html, "card-suppliers")).toBe("2");
    expect(stat(html, "card-journal")).toBe("2");
    expect(stat(html, "card-cash-movements")).toBe("2");

    const recent = section(html, "recent-activity");
    expect(recent).toContain("PV-0004");
    expect(recent).toContain("0001-00000124");
    expect(recent).toContain("Apertura caja principal");
    expect(recent).not.toContain("PV-0002");
    expect(recent).not.toContain("Cobranza revertida");
    expect(recent).not.toContain("Ajuste en borrador");
  });

  it("does not render invented trends or creation CTAs", async () => {
    asUser(OWNER, { org: ORG_A, mode: "business" });
    const html = await renderDashboard();
    expect(html).not.toMatch(/[+−-]\s?\d+([.,]\d+)?\s?%/);
    expect(html).not.toMatch(/vs\.? mes anterior|crecimiento/i);
    expect(html).not.toMatch(/>(Nueva|Nuevo|Crear|Emitir)\b/);
    const actions = section(html, "quick-actions");
    const hrefs = [...actions.matchAll(/href="([^"]+)"/g)].map((m) => m[1]);
    expect(hrefs.length).toBeGreaterThan(0);
    for (const href of hrefs) {
      expect(["/customers", "/suppliers", "/cash", "/reports", "/company", "/users", "/accounting"]).toContain(href);
    }
  });

  it("shows honest empty states for an organization with no activity", async () => {
    asUser(OWNER, { org: ORG_B, mode: "business" });
    const html = await renderDashboard();
    expect(html).toContain("Demo Beta");
    expect(stat(html, "kpi-sales")).toBe(formatARS("0"));
    expect(section(html, "business-activity")).toContain('data-testid="dashboard-empty"');
    expect(html).not.toContain('data-testid="activity-chart"');
    expect(section(html, "kpi-accounting-status")).toContain("Sin movimientos");
    for (const marker of [...EMPRESA_DEMO_MARKERS, ...FOREIGN_MARKERS]) {
      expect(html).not.toContain(marker);
    }
  });
});

describe("accounting mode rendering", () => {
  it("renders the accounting overview from the cookie preference", async () => {
    asUser(OWNER, { org: ORG_A, mode: "accountant" });
    const html = await renderDashboard();
    expect(html).toContain('data-testid="accounting-dashboard"');
    expect(html).toMatch(/data-testid="dashboard-title"[^>]*>Resumen contable</);
    expect(html).not.toContain('data-testid="business-dashboard"');
    expect(html).not.toContain("Resumen de tu negocio");

    expect(stat(html, "kpi-debit")).toBe(formatARS("1400.5"));
    expect(stat(html, "kpi-credit")).toBe(formatARS("1400.5"));
    expect(section(html, "kpi-balance-status")).toContain("Balanceado");
    expect(stat(html, "kpi-posted-entries")).toBe("2");

    const entries = section(html, "latest-entries");
    expect(entries).toContain("Asiento de apertura");
    expect(entries).toContain("Reversión de compra");
    expect(entries).not.toContain("Borrador desbalanceado");

    const periods = section(html, "dashboard-tax-periods");
    expect(periods).toContain("03/2026");
    expect(periods).toContain("02/2026");
    expect(periods).toContain("01/2026");

    expect(stat(html, "card-posted")).toBe("2");
    expect(stat(html, "card-reversed")).toBe("1");
    expect(stat(html, "card-recent-reversals")).toBe("1");
  });

  it("shows different content than business mode for the same organization", async () => {
    asUser(OWNER, { org: ORG_A, mode: "business" });
    const business = await renderDashboard();
    asUser(OWNER, { org: ORG_A, mode: "accountant" });
    const accounting = await renderDashboard();

    for (const id of ["kpi-sales", "kpi-purchases", "kpi-cash-balance", "recent-activity", "business-activity"]) {
      expect(business).toContain(`data-testid="${id}"`);
      expect(accounting).not.toContain(`data-testid="${id}"`);
    }
    for (const id of ["kpi-debit", "kpi-credit", "latest-entries", "dashboard-tax-periods", "card-reversed"]) {
      expect(accounting).toContain(`data-testid="${id}"`);
      expect(business).not.toContain(`data-testid="${id}"`);
    }
  });

  it("falls back to business mode for a tampered cookie value", async () => {
    asUser(OWNER, { org: ORG_A, mode: "superuser" });
    const html = await renderDashboard();
    expect(html).toContain('data-testid="business-dashboard"');
  });

  it("keeps tenant isolation in accounting mode", async () => {
    const fake = asUser(OWNER, { org: ORG_B, mode: "accountant" });
    const html = await renderDashboard();
    expect(html).toContain("Demo Beta");
    for (const marker of [...EMPRESA_DEMO_MARKERS, ...FOREIGN_MARKERS]) {
      expect(html).not.toContain(marker);
    }
    expect(section(html, "kpi-balance-status")).toContain("Sin movimientos");
    const orgFilters = fake.log
      .filter((q) => q.table !== "organization_members")
      .flatMap((q) => q.filters)
      .filter(([column]) => column === "organization_id")
      .map(([, value]) => value);
    expect(orgFilters.length).toBeGreaterThan(0);
    expect(orgFilters.every((v) => v === ORG_B)).toBe(true);
  });

  it("reports query failures without exposing internals or empty data", async () => {
    asUser(OWNER, { org: ORG_A, mode: "accountant", failTables: ["journal_entry_lines"] });
    const html = await renderDashboard();
    expect(html).toContain(LOAD_ERROR_MESSAGE);
    expect(html).not.toContain("secret detail");
    expect(html).not.toContain("XX000");
    expect(html).not.toContain('data-testid="module-empty"');
  });
});

describe("mode persistence", () => {
  it("rejects unauthenticated requests without setting a cookie", async () => {
    asUser(null);
    const res = await postMode({ mode: "accountant" });
    expect(res.status).toBe(401);
    expect(res.cookies.get(UX_MODE_COOKIE)).toBeUndefined();
  });

  it("rejects unknown modes and malformed bodies", async () => {
    asUser(OWNER);
    for (const body of [{ mode: "admin" }, { mode: 1 }, {}, "not-json"]) {
      const res = await postMode(body);
      expect(res.status).toBe(400);
      expect(res.cookies.get(UX_MODE_COOKIE)).toBeUndefined();
    }
  });

  it("stores the preference in a long-lived httpOnly cookie", async () => {
    asUser(OWNER);
    const res = await postMode({ mode: "accountant" }, { host: "finance.example.com", proto: "https" });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, mode: "accountant" });
    const cookie = res.cookies.get(UX_MODE_COOKIE);
    expect(cookie?.value).toBe("accountant");
    expect(cookie?.httpOnly).toBe(true);
    expect(cookie?.secure).toBe(true);
    expect(cookie?.sameSite).toBe("lax");
    expect(cookie?.path).toBe("/");
    expect(cookie?.maxAge).toBeGreaterThanOrEqual(60 * 60 * 24 * 365);
  });

  it("the stored cookie drives the next server render", async () => {
    asUser(OWNER, { org: ORG_A });
    const res = await postMode({ mode: "accountant" });
    const saved = res.cookies.get(UX_MODE_COOKIE)!.value;

    asUser(OWNER, { org: ORG_A, mode: saved });
    expect(await renderDashboard()).toContain("Resumen contable");

    const back = await postMode({ mode: "business" });
    asUser(OWNER, { org: ORG_A, mode: back.cookies.get(UX_MODE_COOKIE)!.value });
    expect(await renderDashboard()).toContain("Resumen de tu negocio");
  });

  it("the client helper posts the selected mode to the endpoint", async () => {
    const fetcher = vi.fn(async () => new Response(JSON.stringify({ ok: true }), { status: 200 }));
    const result = await requestUxMode("accountant", fetcher as unknown as typeof fetch);
    expect(result).toEqual({ ok: true, status: 200 });
    expect(fetcher).toHaveBeenCalledTimes(1);
    const [url, init] = fetcher.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe(UX_MODE_ENDPOINT);
    expect(init.method).toBe("POST");
    expect(JSON.parse(String(init.body))).toEqual({ mode: "accountant" });
  });
});

describe("sidebar emphasis by mode", () => {
  const hrefs = (mode: "business" | "accountant", emphasis: string) =>
    navigationForMode(mode)
      .filter((g) => g.emphasis === emphasis)
      .flatMap((g) => g.items.map((i) => i.href));

  it("prioritizes business modules in business mode", () => {
    expect(hrefs("business", "primary")).toEqual([
      "/dashboard",
      "/customers",
      "/suppliers",
      "/cash",
      "/banks",
      "/reports",
    ]);
    expect(hrefs("business", "secondary")).toEqual(["/accounting"]);
  });

  it("prioritizes accounting in accounting mode", () => {
    expect(hrefs("accountant", "primary")).toEqual(["/dashboard", "/accounting", "/reports"]);
    expect(hrefs("accountant", "secondary")).toEqual(["/customers", "/suppliers", "/cash", "/banks"]);
  });

  it("keeps every destination reachable in both modes", () => {
    const all = (mode: "business" | "accountant") =>
      navigationForMode(mode)
        .flatMap((g) => g.items.map((i) => i.href))
        .sort();
    expect(all("accountant")).toEqual(all("business"));
    expect(all("business")).toEqual(expect.arrayContaining(["/company", "/users", "/settings"]));
  });

  it("renders emphasis attributes and the active mode label", () => {
    state.pathname = "/accounting";
    const business = renderToStaticMarkup(createElement(AppSidebar, { uxMode: "business" }));
    expect(business).toContain("Modo negocio");
    expect(linkFor(business, "/customers")).toContain('data-emphasis="primary"');
    expect(linkFor(business, "/accounting")).toContain('data-emphasis="secondary"');
    expect(linkFor(business, "/accounting")).toContain('aria-current="page"');

    const accounting = renderToStaticMarkup(createElement(AppSidebar, { uxMode: "accountant" }));
    expect(accounting).toMatch(/data-testid="sidebar-mode"[^>]*>[\s\S]*?Modo contabilidad/);
    expect(linkFor(accounting, "/accounting")).toContain('data-emphasis="primary"');
    expect(linkFor(accounting, "/customers")).toContain('data-emphasis="secondary"');
  });
});

describe("mode switcher", () => {
  it("marks exactly the active mode as pressed", () => {
    const business = renderToStaticMarkup(createElement(AppTopbar, { uxMode: "business" }));
    expect(business).toContain("Modo negocio");
    expect(business).toContain("Modo contabilidad");
    expect(business).toMatch(/aria-pressed="true"[^>]*data-testid="ux-mode-business"/);
    expect(business).toMatch(/aria-pressed="false"[^>]*data-testid="ux-mode-accountant"/);

    const accounting = renderToStaticMarkup(createElement(AppTopbar, { uxMode: "accountant" }));
    expect(accounting).toContain('data-mode="accountant"');
    expect(accounting).toMatch(/aria-pressed="true"[^>]*data-testid="ux-mode-accountant"/);
    expect(accounting).toMatch(/aria-pressed="false"[^>]*data-testid="ux-mode-business"/);
  });
});

describe("dashboard activity helpers", () => {
  const sale = (id: string, date: string | null, total: string): ConfirmedSaleRow => ({
    id,
    internal_number: id.toUpperCase(),
    document_date: date,
    total,
  });
  const purchase = (id: string, date: string | null, total: string, type = "SUPPLIER_INVOICE"): PostedPurchaseRow => ({
    id,
    document_type: type,
    point_of_sale: 2,
    document_number: 7,
    issue_date: date,
    total_amount: total,
  });

  it("groups by month, zero-fills gaps and subtracts credit notes", () => {
    const out = buildMonthlyActivity(
      [sale("a", "2026-01-10", "100"), sale("b", "2026-03-01", "50.5"), sale("c", "2026-03-31", "0.5")],
      [purchase("p", "2026-01-20", "40"), purchase("n", "2026-03-02", "10", "SUPPLIER_CREDIT_NOTE")]
    );
    expect(out.map((m) => m.month)).toEqual(["2026-01", "2026-02", "2026-03"]);
    expect(out.map((m) => m.sales)).toEqual([toUnits("100"), BigInt(0), toUnits("51")]);
    expect(out.map((m) => m.purchases)).toEqual([toUnits("40"), BigInt(0), -toUnits("10")]);
  });

  it("caps the window at the latest months and crosses year boundaries", () => {
    const out = buildMonthlyActivity(
      [sale("old", "2025-01-05", "1"), sale("a", "2025-11-05", "1"), sale("b", "2026-02-05", "1")],
      [],
      4
    );
    expect(out.map((m) => m.month)).toEqual(["2025-11", "2025-12", "2026-01", "2026-02"]);
  });

  it("returns no chart data when there are no dated documents", () => {
    expect(buildMonthlyActivity([], [])).toEqual([]);
    expect(buildMonthlyActivity([sale("x", null, "5")], [])).toEqual([]);
  });

  it("orders recent activity newest first and skips non-posted cash", () => {
    const movement = (legId: string, date: string, status: string): CashMovement =>
      ({
        legId,
        accountId: "caja",
        direction: "INFLOW",
        amount: toUnits("5"),
        operation: {
          id: `op-${legId}`,
          internal_number: `TR-${legId}`,
          operation_type: "COLLECTION",
          status,
          operation_date: date,
          description: `mov ${legId}`,
        },
      }) as unknown as CashMovement;
    const items = buildRecentActivity(
      [sale("s1", "2026-01-01", "10")],
      [purchase("p1", "2026-01-03", "20")],
      [movement("l1", "2026-01-02", "POSTED"), movement("l2", "2026-01-04", "REVERSED")],
      10
    );
    expect(items.map((i) => i.kind)).toEqual(["purchase", "cash", "sale"]);
    expect(items[0].reference).toBe("0002-00000007");
    expect(items[0].direction).toBe("out");
    expect(items.some((i) => i.description === "mov l2")).toBe(false);
  });

  it("labels purchases without number and humanizes raw document codes", () => {
    const unnumbered = { ...purchase("p2", "2026-01-05", "20"), point_of_sale: null, document_number: null };
    const movement = {
      legId: "l9",
      accountId: "caja",
      direction: "OUTFLOW",
      amount: toUnits("3"),
      operation: {
        id: "op-l9",
        internal_number: "TR-9",
        operation_type: "PAYMENT",
        status: "POSTED",
        operation_date: "2026-01-06",
        description: "Pago SUPPLIER_INVOICE",
      },
    } as unknown as CashMovement;
    const items = buildRecentActivity([], [unnumbered as PostedPurchaseRow], [movement], 10);
    expect(items.find((i) => i.kind === "purchase")?.reference).toBe("Sin número");
    expect(items.find((i) => i.kind === "cash")?.description).toBe("Pago factura de proveedor");
  });
});

describe("display labels", () => {
  it("translates stored codes to Spanish and never shows raw enums", () => {
    expect(humanizeDescription("Compra SUPPLIER_INVOICE")).toBe("Compra factura de proveedor");
    expect(humanizeDescription("NC SUPPLIER_CREDIT_NOTE / SALES_ORDER")).toBe(
      "NC nota de crédito de proveedor / pedido de venta"
    );
    expect(humanizeDescription("MY_SUPPLIER_INVOICE_X")).toBe("MY_SUPPLIER_INVOICE_X");
    expect(humanizeDescription("TRANSFER TRF-2026-000001")).toBe("Transferencia TRF-2026-000001");
    expect(humanizeDescription("Demo-TR-XFER-1")).toBe("Demo-TR-XFER-1");
    expect(humanizeDescription(null)).toBe("—");
    expect(featureStatusLabel("enabled")).toEqual({ label: "Habilitado", tone: "success" });
    expect(featureStatusLabel("disabled").label).toBe("Deshabilitado");
    expect(featureStatusLabel("restricted").label).toBe("Restringido");
    expect(memberStatusLabel("active")).toEqual({ label: "Activo", tone: "success" });
    expect(memberStatusLabel("invited").label).toBe("Invitado");
    expect(memberStatusLabel("disabled").label).toBe("Deshabilitado");
  });
});

describe("mobile sidebar", () => {
  it("offers a close control inside the drawer instead of behind it", () => {
    const html = renderToStaticMarkup(createElement(AppSidebar, { uxMode: "business" }));
    const aside = html.slice(html.indexOf("<aside"));
    expect(aside).toContain('aria-label="Cerrar menú"');
    expect(html.slice(0, html.indexOf("<aside"))).toContain('aria-label="Abrir menú"');
  });
});
