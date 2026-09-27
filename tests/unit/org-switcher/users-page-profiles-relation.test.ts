/**
 * /users must embed the member's profile through organization_members.user_id.
 * A bare `profiles ( … )` embed is ambiguous (user_id + invited_by FKs) → PGRST201.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import { renderToStaticMarkup } from "react-dom/server";
import { createFakeSupabase, demoDb, ORG_A, OWNER } from "../../helpers/fake-supabase";

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

import UsersPage from "@/app/(app)/users/page";
import { ORGANIZATION_MEMBERS_WITH_PROFILE_SELECT } from "@/lib/members/queries";
import { ACTIVE_ORG_COOKIE } from "@/lib/authz/active-organization";

const PAGE_SOURCE = readFileSync(
  path.resolve(__dirname, "../../../src/app/(app)/users/page.tsx"),
  "utf8"
);

let errorSpy: ReturnType<typeof vi.spyOn>;
beforeEach(() => {
  state.cookies = new Map([[ACTIVE_ORG_COOKIE, ORG_A]]);
  errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
});
afterEach(() => {
  errorSpy.mockRestore();
});

describe("Users page profile relation", () => {
  it("select embeds profiles through organization_members_user_id_fkey", () => {
    expect(ORGANIZATION_MEMBERS_WITH_PROFILE_SELECT).toContain(
      "profiles!organization_members_user_id_fkey ( full_name, email )"
    );
    expect(ORGANIZATION_MEMBERS_WITH_PROFILE_SELECT).not.toMatch(/\bprofiles\s*\(/);
    expect(ORGANIZATION_MEMBERS_WITH_PROFILE_SELECT).not.toMatch(/invited_by_fkey/);
  });

  it("page source uses the shared select and no bare profiles embed", () => {
    expect(PAGE_SOURCE).toContain("ORGANIZATION_MEMBERS_WITH_PROFILE_SELECT");
    expect(PAGE_SOURCE).not.toMatch(/\bprofiles\s*\(/);
  });

  it("the ambiguous embed fails like PostgREST (guards the fake itself)", async () => {
    const { client } = createFakeSupabase(demoDb(), OWNER);
    const r = await (client.from("organization_members") as unknown as {
      select: (c: string) => { eq: (c: string, v: unknown) => PromiseLike<{ error: { code: string } | null }> };
    })
      .select("id, profiles ( full_name, email )")
      .eq("organization_id", ORG_A);
    expect(r.error?.code).toBe("PGRST201");
  });

  it("renders members with the profile of user_id (not invited_by)", async () => {
    const db = demoDb();
    // m3 (contador) was invited by OWNER: the listing must still show the contador's own profile.
    db.organization_members = db.organization_members.map((m) =>
      m.id === "m3" ? { ...m, invited_by: OWNER } : m
    );
    state.client = createFakeSupabase(db, OWNER).client;
    const html = renderToStaticMarkup(await UsersPage());
    expect(html).toContain("contador.demo@example.invalid");
    expect(html).toContain("Contador Demo A");
    expect(html).toContain("owner.demo@example.invalid");
    expect(html).not.toContain("users-load-error");
  });

  it("query failure renders a generic message without DB internals", async () => {
    state.client = createFakeSupabase(demoDb(), OWNER, { failSelectWithProfiles: true }).client;
    const html = renderToStaticMarkup(await UsersPage());
    expect(html).toContain("No se pudieron cargar los miembros de la empresa");
    expect(html).not.toMatch(/XX000|secret detail|relation organization_members|PGRST/);
    expect(html).not.toContain("owner.demo@example.invalid");
    expect(errorSpy).toHaveBeenCalledWith("[users] members query failed", { code: "XX000" });
  });
});
