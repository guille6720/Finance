/**
 * Organization switcher: resolution rules, secure endpoint, and page scoping.
 * Supabase is an in-memory double that simulates membership-based RLS.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { NextRequest } from "next/server";
import {
  createFakeSupabase,
  demoDb,
  ORG_A,
  ORG_B,
  ORG_C,
  OWNER,
  SOLO,
  OUTSIDER,
} from "../../helpers/fake-supabase";

const state: {
  client: unknown;
  cookies: Map<string, string>;
} = { client: null, cookies: new Map() };

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => state.client,
}));
vi.mock("@/lib/audit/write-audit-event", () => ({
  writeAuditEvent: vi.fn(async () => undefined),
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
}));
vi.mock("next/link", () => ({
  default: ({ href, children, ...rest }: { href: string; children: unknown }) =>
    createElement("a", { href, ...rest }, children as never),
}));

import {
  ACTIVE_ORG_COOKIE,
  activeOrgCookieOptions,
  isUuid,
  loadUserOrganizations,
  normalizeMemberships,
  resolveActiveOrganizationId,
  validateActiveOrganizationSwitch,
} from "@/lib/authz/active-organization";
import { POST } from "@/app/api/organizations/active/route";
import DashboardPage from "@/app/(app)/dashboard/page";
import UsersPage from "@/app/(app)/users/page";
import { writeAuditEvent } from "@/lib/audit/write-audit-event";
import type { SupabaseClient } from "@supabase/supabase-js";

function asUser(userId: string | null) {
  const fake = createFakeSupabase(demoDb(), userId);
  state.client = fake.client;
  return fake;
}

function postActive(body: unknown, host = "localhost:3000", proto = "http") {
  return POST(
    new NextRequest(`${proto}://${host}/api/organizations/active`, {
      method: "POST",
      headers: { "content-type": "application/json", host },
      body: typeof body === "string" ? body : JSON.stringify(body),
    })
  );
}

beforeEach(() => {
  state.cookies = new Map();
  vi.mocked(writeAuditEvent).mockClear();
});

describe("active organization resolution", () => {
  it("uses the cookie only when it is one of the user's memberships", () => {
    expect(resolveActiveOrganizationId([ORG_A, ORG_B], ORG_B)).toBe(ORG_B);
    expect(resolveActiveOrganizationId([ORG_A, ORG_B], ORG_C)).toBe(ORG_A);
    expect(resolveActiveOrganizationId([ORG_A, ORG_B], undefined)).toBe(ORG_A);
    expect(resolveActiveOrganizationId([ORG_A], "garbage")).toBe(ORG_A);
    expect(resolveActiveOrganizationId([], ORG_A)).toBeNull();
  });

  it("display name prefers commercial_name, falls back to legal_name", () => {
    const orgs = normalizeMemberships([
      {
        organization_id: ORG_A,
        role: "owner",
        organizations: { id: ORG_A, legal_name: "LEGAL A", commercial_name: "Comercial A" },
      },
      {
        organization_id: ORG_C,
        role: "owner",
        organizations: { id: ORG_C, legal_name: "LEGAL C", commercial_name: null },
      },
      { organization_id: ORG_B, role: "owner", organizations: null },
    ]);
    expect(orgs.map((o) => o.displayName)).toEqual(["Comercial A", "LEGAL C"]);
  });

  it("user with one organization gets exactly that organization", async () => {
    const { client } = asUser(SOLO);
    const orgs = await loadUserOrganizations(client as unknown as SupabaseClient, SOLO);
    expect(orgs.map((o) => o.id)).toEqual([ORG_A]);
  });

  it("owner.demo-like user gets both active orgs, never the inactive one", async () => {
    const { client } = asUser(OWNER);
    const orgs = await loadUserOrganizations(client as unknown as SupabaseClient, OWNER);
    expect(orgs.map((o) => o.displayName)).toEqual(["Empresa Demo", "Demo Beta"]);
    expect(orgs.some((o) => o.id === ORG_C)).toBe(false);
  });

  it("cookie options: httpOnly, lax, path=/, secure outside local http", () => {
    expect(activeOrgCookieOptions({ host: "localhost:3000", protocol: "http:" })).toEqual({
      httpOnly: true,
      sameSite: "lax",
      secure: false,
      path: "/",
    });
    expect(activeOrgCookieOptions({ host: "app.example.com", protocol: "https:" }).secure).toBe(true);
    expect(activeOrgCookieOptions({ host: "app.example.com", protocol: "http:" }).secure).toBe(true);
    expect(activeOrgCookieOptions({ host: "localhost:3000", protocol: "https:" }).secure).toBe(true);
    expect(activeOrgCookieOptions({ host: null, protocol: "http:" }).secure).toBe(true);
  });

  it("isUuid rejects non-uuid input", () => {
    expect(isUuid(ORG_A)).toBe(true);
    for (const v of ["", "abc", 123, null, undefined, `${ORG_A}' OR 1=1`]) {
      expect(isUuid(v)).toBe(false);
    }
  });
});

describe("POST /api/organizations/active", () => {
  it("requires an authenticated user (401, no cookie)", async () => {
    asUser(null);
    const res = await postActive({ organizationId: ORG_A });
    expect(res.status).toBe(401);
    expect(res.cookies.get(ACTIVE_ORG_COOKIE)).toBeUndefined();
  });

  it("member can switch between their two organizations; cookie updates", async () => {
    asUser(OWNER);
    const toB = await postActive({ organizationId: ORG_B });
    expect(toB.status).toBe(200);
    const cookieB = toB.cookies.get(ACTIVE_ORG_COOKIE);
    expect(cookieB?.value).toBe(ORG_B);
    expect(cookieB?.httpOnly).toBe(true);
    expect(cookieB?.sameSite).toBe("lax");
    expect(cookieB?.path).toBe("/");

    const toA = await postActive({ organizationId: ORG_A });
    expect(toA.status).toBe(200);
    expect(toA.cookies.get(ACTIVE_ORG_COOKIE)?.value).toBe(ORG_A);
    expect(writeAuditEvent).toHaveBeenCalledTimes(2);
  });

  it("sets secure cookie on non-local https hosts", async () => {
    asUser(OWNER);
    const res = await postActive({ organizationId: ORG_B }, "finance.example.com", "https");
    expect(res.cookies.get(ACTIVE_ORG_COOKIE)?.secure).toBe(true);
  });

  it("403 for an organization where the user is not a member; cookie untouched", async () => {
    asUser(SOLO);
    const res = await postActive({ organizationId: ORG_B });
    expect(res.status).toBe(403);
    expect(res.cookies.get(ACTIVE_ORG_COOKIE)).toBeUndefined();
    expect(writeAuditEvent).not.toHaveBeenCalled();
  });

  it("403 for an organization with only an inactive membership", async () => {
    asUser(OWNER);
    const res = await postActive({ organizationId: ORG_C });
    expect(res.status).toBe(403);
    expect(res.cookies.get(ACTIVE_ORG_COOKIE)).toBeUndefined();
  });

  it("400 for malformed or missing organizationId; never trusts raw input", async () => {
    asUser(OWNER);
    for (const body of [{}, { organizationId: "not-a-uuid" }, { organizationId: 42 }, "{bad json"]) {
      const res = await postActive(body);
      expect(res.status).toBe(400);
      expect(res.cookies.get(ACTIVE_ORG_COOKIE)).toBeUndefined();
    }
  });

  it("membership is checked through the caller-scoped client (RLS path)", async () => {
    const fake = asUser(OUTSIDER);
    const r = await validateActiveOrganizationSwitch(
      fake.client as unknown as SupabaseClient,
      ORG_A
    );
    expect(r.status).toBe(403);
    const q = fake.log.find((l) => l.table === "organization_members");
    expect(q?.filters).toEqual(
      expect.arrayContaining([
        ["user_id", OUTSIDER],
        ["organization_id", ORG_A],
        ["status", "active"],
      ])
    );
  });
});

describe("pages follow the selected organization", () => {
  it("/users shows members of the selected organization only", async () => {
    asUser(OWNER);
    state.cookies.set(ACTIVE_ORG_COOKIE, ORG_A);
    const htmlA = renderToStaticMarkup(await UsersPage());
    expect(htmlA).toContain("contador.demo@example.invalid");
    expect(htmlA).not.toContain("outsider@example.invalid");

    state.cookies.set(ACTIVE_ORG_COOKIE, ORG_B);
    const htmlB = renderToStaticMarkup(await UsersPage());
    expect(htmlB).toContain("owner.demo@example.invalid");
    expect(htmlB).not.toContain("contador.demo@example.invalid");
  });

  it("/dashboard loads the selected organization's data", async () => {
    asUser(OWNER);
    state.cookies.set(ACTIVE_ORG_COOKIE, ORG_B);
    const html = renderToStaticMarkup(await DashboardPage());
    expect(html).toContain("Demo Beta");
    expect(html).not.toContain("Empresa Demo");
  });

  it("forged cookie for a foreign org falls back to the user's own org (no leakage)", async () => {
    const fake = asUser(SOLO);
    state.cookies.set(ACTIVE_ORG_COOKIE, ORG_C);
    const dash = renderToStaticMarkup(await DashboardPage());
    expect(dash).toContain("Empresa Demo");
    expect(dash).not.toContain("OTRA EMPRESA");

    const users = renderToStaticMarkup(await UsersPage());
    expect(users).not.toContain("outsider@example.invalid");
    const scoped = fake.log.filter((l) =>
      l.filters.some(([c, v]) => (c === "organization_id" || c === "id") && v === ORG_C)
    );
    expect(scoped).toEqual([]);
  });

  it("unauthenticated access still redirects to /login", async () => {
    asUser(null);
    await expect(DashboardPage()).rejects.toThrow("REDIRECT:/login");
    await expect(UsersPage()).rejects.toThrow("REDIRECT:/login");
  });
});
