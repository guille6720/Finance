import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { getServerEnv, resetEnvCacheForTests } from "@/config/env";

const REQUIRED = {
  NEXT_PUBLIC_SUPABASE_URL: "https://abcdefghijklmnop.supabase.co",
  NEXT_PUBLIC_SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.anon-key-value-here",
};

describe("environment validation", () => {
  const original = { ...process.env };

  beforeEach(() => {
    resetEnvCacheForTests();
    process.env = { ...original, ...REQUIRED, APP_ENV: "local", ARCA_ENV: "disabled" };
    delete process.env.PRODUCTION_SUPABASE_PROJECT_REF;
    delete process.env.STAGING_SUPABASE_PROJECT_REF;
    delete process.env.REHEARSAL_SUPABASE_PROJECT_REF;
    delete process.env.FISCAL_GATEWAY_ENV;
  });

  afterEach(() => {
    process.env = original;
    resetEnvCacheForTests();
  });

  it("accepts a valid local configuration", () => {
    const env = getServerEnv();
    expect(env.NEXT_PUBLIC_SUPABASE_URL).toContain("supabase.co");
    expect(env.ARCA_ENV).toBe("disabled");
  });

  it("rejects staging and production sharing the same project ref", () => {
    process.env.STAGING_SUPABASE_PROJECT_REF = "same-ref";
    process.env.PRODUCTION_SUPABASE_PROJECT_REF = "same-ref";
    resetEnvCacheForTests();
    expect(() => getServerEnv()).toThrow(/never share/i);
  });

  it("rejects staging URL pointing at production project", () => {
    process.env.APP_ENV = "staging";
    process.env.NEXT_PUBLIC_APP_ENV = "staging";
    process.env.PRODUCTION_SUPABASE_PROJECT_REF = "abcdefghijklmnop";
    process.env.NEXT_PUBLIC_SUPABASE_URL =
      "https://abcdefghijklmnop.supabase.co";
    resetEnvCacheForTests();
    expect(() => getServerEnv()).toThrow(/production project/i);
  });

  it("rejects local app pointed at production project", () => {
    process.env.APP_ENV = "local";
    process.env.PRODUCTION_SUPABASE_PROJECT_REF = "abcdefghijklmnop";
    process.env.NEXT_PUBLIC_SUPABASE_URL =
      "https://abcdefghijklmnop.supabase.co";
    resetEnvCacheForTests();
    expect(() => getServerEnv()).toThrow(/Production secrets/i);
  });

  it("rejects production app on localhost database", () => {
    process.env.APP_ENV = "production";
    process.env.NEXT_PUBLIC_APP_ENV = "production";
    process.env.NEXT_PUBLIC_SUPABASE_URL = "http://127.0.0.1:54321";
    resetEnvCacheForTests();
    expect(() => getServerEnv()).toThrow(/local Supabase URL/i);
  });

  it("rejects ARCA production in any environment", () => {
    process.env.ARCA_ENV = "production";
    resetEnvCacheForTests();
    expect(() => getServerEnv()).toThrow(/ARCA production is blocked/i);
  });

  it("rejects staging app with ARCA production even if homologation intended", () => {
    process.env.APP_ENV = "staging";
    process.env.NEXT_PUBLIC_APP_ENV = "staging";
    process.env.ARCA_ENV = "production";
    resetEnvCacheForTests();
    expect(() => getServerEnv()).toThrow(/ARCA/i);
  });

  it("rejects rehearsal URL pointing at production project", () => {
    process.env.APP_ENV = "rehearsal";
    process.env.NEXT_PUBLIC_APP_ENV = "rehearsal";
    process.env.PRODUCTION_SUPABASE_PROJECT_REF = "abcdefghijklmnop";
    process.env.NEXT_PUBLIC_SUPABASE_URL =
      "https://abcdefghijklmnop.supabase.co";
    resetEnvCacheForTests();
    expect(() => getServerEnv()).toThrow(/rehearsal cannot point/i);
  });
});
