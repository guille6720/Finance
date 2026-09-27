/**
 * Demo auth-user idempotency / safety unit tests (no live DB / no ARCA).
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import {
  assertDemoAuthMutationAllowed,
  decideDemoAuthAction,
  ensureDemoAuthUser,
  isAllowlistedDemoAuthEmail,
  sanitizeSeedError,
  DEMO_AUTH_EMAILS,
} from "../../../scripts/demo/auth-users.mjs";

const LOCAL_GATE = { mode: "LOCAL" as const };
const STAGING_GATE = { mode: "STAGING" as const };

describe("demo auth allowlist", () => {
  it("includes required demo emails", () => {
    expect(isAllowlistedDemoAuthEmail("owner.demo@example.invalid")).toBe(true);
    expect(isAllowlistedDemoAuthEmail("admin.demo@example.invalid")).toBe(true);
    expect(isAllowlistedDemoAuthEmail("contador.demo@example.invalid")).toBe(true);
    expect(isAllowlistedDemoAuthEmail("operador.demo@example.invalid")).toBe(true);
    expect(isAllowlistedDemoAuthEmail("auditor.demo@example.invalid")).toBe(true);
    expect(DEMO_AUTH_EMAILS.length).toBeGreaterThanOrEqual(5);
  });

  it("rejects non-demo emails", () => {
    expect(isAllowlistedDemoAuthEmail("real.user@company.com")).toBe(false);
    expect(isAllowlistedDemoAuthEmail("admin@example.com")).toBe(false);
  });
});

describe("decideDemoAuthAction", () => {
  const base = {
    email: "owner.demo@example.invalid",
    envGate: LOCAL_GATE,
    confirm: true,
    arcaEnv: null,
    fiscalEnv: null,
  };

  it("A: absent + CREATE_USERS → create", () => {
    expect(
      decideDemoAuthAction({ ...base, userExists: false, createUsers: true })
    ).toBe("create");
  });

  it("B/C: exists + CREATE_USERS → update_password", () => {
    expect(
      decideDemoAuthAction({ ...base, userExists: true, createUsers: true })
    ).toBe("update_password");
  });

  it("F: CREATE_USERS != YES → login_only", () => {
    expect(
      decideDemoAuthAction({ ...base, userExists: true, createUsers: false })
    ).toBe("login_only");
  });

  it("D: non-demo email → refuse", () => {
    expect(
      decideDemoAuthAction({
        ...base,
        email: "ceo@realcompany.com",
        userExists: true,
        createUsers: true,
      })
    ).toBe("refuse");
  });

  it("E: production ARCA → refuse", () => {
    expect(
      decideDemoAuthAction({
        ...base,
        userExists: false,
        createUsers: true,
        arcaEnv: "production",
      })
    ).toBe("refuse");
  });
});

describe("assertDemoAuthMutationAllowed", () => {
  it("allows local allowlisted mutation", () => {
    expect(
      assertDemoAuthMutationAllowed({
        email: "owner.demo@example.invalid",
        createUsers: true,
        envGate: LOCAL_GATE,
        confirm: true,
      })
    ).toBe(true);
  });

  it("refuses non-demo email", () => {
    expect(() =>
      assertDemoAuthMutationAllowed({
        email: "not-demo@example.com",
        createUsers: true,
        envGate: LOCAL_GATE,
        confirm: true,
      })
    ).toThrow(/DEMO_AUTH_REFUSED/);
  });

  it("refuses without CREATE_USERS", () => {
    expect(() =>
      assertDemoAuthMutationAllowed({
        email: "owner.demo@example.invalid",
        createUsers: false,
        envGate: LOCAL_GATE,
        confirm: true,
      })
    ).toThrow(/DEMO_SEED_CREATE_USERS/);
  });

  it("refuses production fiscal env", () => {
    expect(() =>
      assertDemoAuthMutationAllowed({
        email: "owner.demo@example.invalid",
        createUsers: true,
        envGate: STAGING_GATE,
        confirm: true,
        fiscalEnv: "production",
      })
    ).toThrow(/production/i);
  });
});

describe("sanitizeSeedError", () => {
  it("G: never leaves password in output", () => {
    const pw = "Super-Secret-Demo-Password-99!";
    const out = sanitizeSeedError(`login failed password=${pw} ok`, [pw]);
    expect(out).not.toContain(pw);
    expect(out).toContain("[REDACTED]");
  });

  it("redacts JWT-shaped tokens", () => {
    const jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxIn0.signaturehere";
    expect(sanitizeSeedError(`token ${jwt}`)).not.toContain("eyJ");
  });
});

describe("ensureDemoAuthUser integration (mocked HTTP)", () => {
  const prev = { ...process.env };
  const env = {
    apiUrl: "http://127.0.0.1:54321",
    serviceRoleKey: "service-role-test",
    anonKey: "anon-test",
  };

  beforeEach(() => {
    process.env.DEMO_SEED_CONFIRM = "YES";
    delete process.env.ARCA_ENV;
    delete process.env.FISCAL_GATEWAY_ENV;
  });

  afterEach(() => {
    process.env = { ...prev };
  });

  function headers(a: string, b: string) {
    return { apikey: a, Authorization: `Bearer ${b}` };
  }

  it("A: creates when absent", async () => {
    const calls: string[] = [];
    const httpCall = vi.fn(async (url: string, options: { method?: string; body?: string }) => {
      calls.push(`${options.method || "GET"} ${url}`);
      if (url.includes("/admin/users") && (options.method || "GET") === "GET") {
        return { ok: true, status: 200, data: { users: [] } };
      }
      if ((options.method || "") === "POST" && url.endsWith("/admin/users")) {
        const body = JSON.parse(options.body || "{}");
        expect(body.password).toBe("New-Demo-Password-12");
        expect(body.email_confirm).toBe(true);
        return {
          ok: true,
          status: 200,
          data: { id: "u-new", email: body.email },
        };
      }
      throw new Error(`unexpected ${options.method} ${url}`);
    });

    const r = await ensureDemoAuthUser({
      env,
      email: "owner.demo@example.invalid",
      full_name: "Owner Demo",
      password: "New-Demo-Password-12",
      createUsers: true,
      envGate: LOCAL_GATE,
      httpCall,
      headers,
    });
    expect(r.created).toBe(true);
    expect(r.action).toBe("create");
    expect(r.user.id).toBe("u-new");
  });

  it("B: second run with same password updates (no duplicate create)", async () => {
    let postCount = 0;
    let putCount = 0;
    const httpCall = vi.fn(async (url: string, options: { method?: string; body?: string }) => {
      const method = options.method || "GET";
      if (method === "GET" && url.includes("/admin/users")) {
        return {
          ok: true,
          status: 200,
          data: {
            users: [
              {
                id: "u-existing",
                email: "owner.demo@example.invalid",
                user_metadata: { demo: true },
              },
            ],
          },
        };
      }
      if (method === "POST" && url.endsWith("/admin/users")) {
        postCount += 1;
        return { ok: true, status: 200, data: { id: "dup" } };
      }
      if (method === "PUT" && url.includes("/admin/users/u-existing")) {
        putCount += 1;
        return {
          ok: true,
          status: 200,
          data: { id: "u-existing", email: "owner.demo@example.invalid" },
        };
      }
      throw new Error(`unexpected ${method} ${url}`);
    });

    const r = await ensureDemoAuthUser({
      env,
      email: "owner.demo@example.invalid",
      full_name: "Owner Demo",
      password: "Same-Demo-Password-12",
      createUsers: true,
      envGate: LOCAL_GATE,
      httpCall,
      headers,
    });
    expect(r.created).toBe(false);
    expect(r.passwordUpdated).toBe(true);
    expect(r.action).toBe("update_password");
    expect(postCount).toBe(0);
    expect(putCount).toBe(1);
  });

  it("C: existing user with OLD password — reset to NEW", async () => {
    const httpCall = vi.fn(async (url: string, options: { method?: string; body?: string }) => {
      const method = options.method || "GET";
      if (method === "GET") {
        return {
          ok: true,
          status: 200,
          data: {
            users: [{ id: "u1", email: "admin.demo@example.invalid", user_metadata: {} }],
          },
        };
      }
      if (method === "PUT") {
        const body = JSON.parse(options.body || "{}");
        expect(body.password).toBe("Brand-New-Demo-Pass-99");
        return { ok: true, status: 200, data: { id: "u1" } };
      }
      throw new Error("no create");
    });

    const r = await ensureDemoAuthUser({
      env,
      email: "admin.demo@example.invalid",
      full_name: "Admin Demo",
      password: "Brand-New-Demo-Pass-99",
      createUsers: true,
      envGate: LOCAL_GATE,
      httpCall,
      headers,
    });
    expect(r.passwordUpdated).toBe(true);
  });

  it("D: non-demo email refused even with CREATE_USERS", async () => {
    const httpCall = vi.fn(
      async (_url: string, _options?: { method?: string; body?: string }) => ({
        ok: true,
        status: 200,
        data: { users: [{ id: "x", email: "ceo@acme.com" }] },
      })
    );
    await expect(
      ensureDemoAuthUser({
        env,
        email: "ceo@acme.com",
        full_name: "CEO",
        password: "Whatever-Password-12",
        createUsers: true,
        envGate: LOCAL_GATE,
        httpCall,
        headers,
      })
    ).rejects.toThrow(/DEMO_AUTH_REFUSED/);
    // Must not attempt PUT/POST create
    const mutating = httpCall.mock.calls.filter(
      (c) => c[1]?.method === "PUT" || c[1]?.method === "POST"
    );
    expect(mutating).toHaveLength(0);
  });

  it("E: production mode refuses create/update", async () => {
    process.env.ARCA_ENV = "production";
    const httpCall = vi.fn(async () => ({
      ok: true,
      status: 200,
      data: { users: [] },
    }));
    await expect(
      ensureDemoAuthUser({
        env,
        email: "owner.demo@example.invalid",
        full_name: "Owner",
        password: "Whatever-Password-12",
        createUsers: true,
        envGate: LOCAL_GATE,
        httpCall,
        headers,
      })
    ).rejects.toThrow(/DEMO_AUTH_REFUSED|production/i);
  });

  it("F: CREATE_USERS != YES does not mutate credentials", async () => {
    const httpCall = vi.fn(async (url: string, options: { method?: string }) => {
      if ((options.method || "GET") === "GET") {
        return {
          ok: true,
          status: 200,
          data: {
            users: [{ id: "u1", email: "owner.demo@example.invalid" }],
          },
        };
      }
      throw new Error("mutation not allowed in this test");
    });
    const r = await ensureDemoAuthUser({
      env,
      email: "owner.demo@example.invalid",
      full_name: "Owner",
      password: "Should-Not-Be-Applied-1",
      createUsers: false,
      envGate: LOCAL_GATE,
      httpCall,
      headers,
    });
    expect(r.action).toBe("login_only");
    expect(r.passwordUpdated).toBe(false);
    expect(r.created).toBe(false);
  });
});
