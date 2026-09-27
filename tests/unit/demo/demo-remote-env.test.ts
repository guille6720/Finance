/**
 * Remote env loading must fail closed (PHASE13_FORCE_REMOTE=1).
 * No network / DB access: pure resolution + mocked `supabase status`.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

vi.mock("node:child_process", () => ({
  execSync: () => {
    throw new Error("supabase status unavailable in unit tests");
  },
}));

import {
  resolveRemoteEnv,
  ensureLocalEnv,
  ALLOWED_REMOTE_STAGING_REFS,
} from "../../../scripts/phase13/env.mjs";
import { assertDemoSeedEnvironment } from "../../../scripts/demo/guards.mjs";

const REF = ALLOWED_REMOTE_STAGING_REFS[0];
const DB_SECRET = "Sup3rS3cretDbPass!";
const ANON_SECRET = "anon-test-key-FAKE-not-real-0001";
const SERVICE_SECRET = "service-test-key-FAKE-not-real-0002";
const LOCAL_DEMO_ANON =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";

function remoteVars(overrides: Record<string, string | undefined> = {}) {
  return {
    PHASE13_FORCE_REMOTE: "1",
    PHASE13_API_URL: `https://${REF}.supabase.co`,
    PHASE13_DB_URL: `postgresql://postgres:${encodeURIComponent(DB_SECRET)}@db.${REF}.supabase.co:5432/postgres`,
    PHASE13_ANON_KEY: ANON_SECRET,
    PHASE13_SERVICE_ROLE_KEY: SERVICE_SECRET,
    ...overrides,
  };
}

function errorOf(fn: () => unknown): string {
  try {
    fn();
  } catch (e) {
    return String((e as Error).message);
  }
  throw new Error("expected function to throw");
}

function expectNoSecrets(message: string) {
  for (const s of [DB_SECRET, encodeURIComponent(DB_SECRET), ANON_SECRET, SERVICE_SECRET, LOCAL_DEMO_ANON]) {
    expect(message).not.toContain(s);
  }
  expect(message).not.toMatch(/postgresql:\/\//);
}

describe("resolveRemoteEnv: fail closed", () => {
  it("remote mode with all four vars => PASS", () => {
    const env = resolveRemoteEnv(remoteVars());
    expect(env.mode).toBe("REMOTE");
    expect(env.projectRef).toBe(REF);
    expect(env.apiUrl).toBe(`https://${REF}.supabase.co`);
    expect(env.dbUrl).toContain(`db.${REF}.supabase.co`);
    expect(env.anonKey).toBe(ANON_SECRET);
    expect(env.serviceRoleKey).toBe(SERVICE_SECRET);
  });

  it("accepts the Supabase pooler form with user postgres.<ref>", () => {
    const env = resolveRemoteEnv(
      remoteVars({
        PHASE13_DB_URL: `postgresql://postgres.${REF}:${encodeURIComponent(DB_SECRET)}@aws-0-sa-east-1.pooler.supabase.com:6543/postgres`,
      })
    );
    expect(env.projectRef).toBe(REF);
  });

  it.each([
    ["PHASE13_API_URL"],
    ["PHASE13_DB_URL"],
    ["PHASE13_ANON_KEY"],
    ["PHASE13_SERVICE_ROLE_KEY"],
  ])("missing %s => FAIL with sanitized message", (name) => {
    for (const value of [undefined, "", "   "]) {
      const msg = errorOf(() => resolveRemoteEnv(remoteVars({ [name]: value })));
      expect(msg).toBe(`REMOTE_ENV_INCOMPLETE: ${name} is required when PHASE13_FORCE_REMOTE=1`);
      expectNoSecrets(msg);
    }
  });

  it("remote API + localhost DB => FAIL", () => {
    for (const host of ["127.0.0.1:54322", "localhost:5432", "0.0.0.0:5432"]) {
      const msg = errorOf(() =>
        resolveRemoteEnv(
          remoteVars({ PHASE13_DB_URL: `postgresql://postgres:${DB_SECRET}@${host}/postgres` })
        )
      );
      expect(msg).toMatch(/REMOTE_ENV_INCOMPLETE: PHASE13_DB_URL must not point to a local host/);
      expectNoSecrets(msg);
    }
  });

  it("DB URL for a different project ref => FAIL", () => {
    const other = "abcdefghijklmnopqrst";
    const msg = errorOf(() =>
      resolveRemoteEnv(
        remoteVars({ PHASE13_DB_URL: `postgresql://postgres:${DB_SECRET}@db.${other}.supabase.co:5432/postgres` })
      )
    );
    expect(msg).toMatch(/does not match PHASE13_API_URL project ref/);
    expectNoSecrets(msg);
  });

  it("DB URL on a non-Supabase host => FAIL (ref not verifiable)", () => {
    const msg = errorOf(() =>
      resolveRemoteEnv(remoteVars({ PHASE13_DB_URL: `postgresql://u:${DB_SECRET}@db.example.com:5432/x` }))
    );
    expect(msg).toMatch(/PHASE13_DB_URL host must be/);
    expectNoSecrets(msg);
  });

  it("API URL must be HTTPS and a supabase.co project host", () => {
    expect(errorOf(() => resolveRemoteEnv(remoteVars({ PHASE13_API_URL: `http://${REF}.supabase.co` })))).toMatch(
      /must use https/
    );
    expect(errorOf(() => resolveRemoteEnv(remoteVars({ PHASE13_API_URL: "https://127.0.0.1:54321" })))).toMatch(
      /must not be a local host/
    );
    expect(errorOf(() => resolveRemoteEnv(remoteVars({ PHASE13_API_URL: "https://api.example.com" })))).toMatch(
      /<project-ref>\.supabase\.co/
    );
  });

  it("non-allow-listed project ref (e.g. Production) => FAIL", () => {
    const prod = "prodprodprodprodprod";
    const msg = errorOf(() =>
      resolveRemoteEnv(
        remoteVars({
          PHASE13_API_URL: `https://${prod}.supabase.co`,
          PHASE13_DB_URL: `postgresql://postgres:${DB_SECRET}@db.${prod}.supabase.co:5432/postgres`,
        })
      )
    );
    expect(msg).toMatch(/not an allow-listed remote project/);
    expectNoSecrets(msg);
  });

  it("explicitly blocked ref wins over allow-list", () => {
    expect(errorOf(() => resolveRemoteEnv(remoteVars({ PHASE13_BLOCK_PROJECT_REF: REF })))).toMatch(
      /explicitly blocked/
    );
  });

  it("local Supabase demo keys or identical keys are rejected in remote mode", () => {
    const msg = errorOf(() => resolveRemoteEnv(remoteVars({ PHASE13_ANON_KEY: LOCAL_DEMO_ANON })));
    expect(msg).toMatch(/local Supabase demo keys/);
    expectNoSecrets(msg);
    expect(
      errorOf(() => resolveRemoteEnv(remoteVars({ PHASE13_ANON_KEY: SERVICE_SECRET })))
    ).toMatch(/must differ/);
  });

  it("ARCA/FISCAL production env is refused in remote mode", () => {
    expect(errorOf(() => resolveRemoteEnv(remoteVars({ ARCA_ENV: "production" })))).toMatch(
      /production environment is not allowed/
    );
    expect(errorOf(() => resolveRemoteEnv(remoteVars({ FISCAL_GATEWAY_ENV: "production" })))).toMatch(
      /production environment is not allowed/
    );
  });
});

describe("ensureLocalEnv integration", () => {
  const KEYS = [
    "PHASE13_FORCE_REMOTE",
    "PHASE13_API_URL",
    "PHASE13_DB_URL",
    "PHASE13_ANON_KEY",
    "PHASE13_SERVICE_ROLE_KEY",
  ];
  let saved: Record<string, string | undefined>;
  beforeEach(() => {
    saved = Object.fromEntries(KEYS.map((k) => [k, process.env[k]]));
  });
  afterEach(() => {
    for (const k of KEYS) {
      if (saved[k] === undefined) delete process.env[k];
      else process.env[k] = saved[k];
    }
  });

  it("FORCE_REMOTE=1 with only API URL no longer falls back to local DB/keys", () => {
    process.env.PHASE13_FORCE_REMOTE = "1";
    process.env.PHASE13_API_URL = `https://${REF}.supabase.co`;
    delete process.env.PHASE13_DB_URL;
    delete process.env.PHASE13_ANON_KEY;
    delete process.env.PHASE13_SERVICE_ROLE_KEY;
    expect(() => ensureLocalEnv()).toThrow(
      "REMOTE_ENV_INCOMPLETE: PHASE13_DB_URL is required when PHASE13_FORCE_REMOTE=1"
    );
  });

  it("FORCE_REMOTE=1 without API URL fails closed instead of silently going local", () => {
    process.env.PHASE13_FORCE_REMOTE = "1";
    delete process.env.PHASE13_API_URL;
    expect(() => ensureLocalEnv()).toThrow(/PHASE13_API_URL is required/);
  });

  it("local mode unchanged: falls back to the local disposable stack", () => {
    delete process.env.PHASE13_FORCE_REMOTE;
    const env = ensureLocalEnv();
    expect(env.apiUrl).toMatch(/127\.0\.0\.1|localhost/);
    expect(env.dbUrl).toMatch(/127\.0\.0\.1|localhost/);
    expect(env.anonKey).toBeTruthy();
    expect(env.serviceRoleKey).toBeTruthy();
    expect(env).not.toHaveProperty("mode", "REMOTE");
  });
});

describe("production guard still blocks Production", () => {
  it("demo seed guard refuses non-allow-listed remote ref", () => {
    const prev = process.env.DEMO_SEED_CONFIRM;
    process.env.DEMO_SEED_CONFIRM = "YES";
    try {
      expect(() =>
        assertDemoSeedEnvironment({ apiUrl: "https://prodprodprodprodprod.supabase.co", dbUrl: "" })
      ).toThrow(/DEMO_SEED_REFUSED/);
      expect(
        assertDemoSeedEnvironment({ apiUrl: `https://${REF}.supabase.co`, dbUrl: "" }).mode
      ).toBe("STAGING");
    } finally {
      if (prev === undefined) delete process.env.DEMO_SEED_CONFIRM;
      else process.env.DEMO_SEED_CONFIRM = prev;
    }
  });
});
