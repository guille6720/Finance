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
    process.env = { ...original, ...REQUIRED, APP_ENV: "local" };
  });

  afterEach(() => {
    process.env = original;
    resetEnvCacheForTests();
  });

  it("accepts a valid local configuration", () => {
    const env = getServerEnv();
    expect(env.NEXT_PUBLIC_SUPABASE_URL).toContain("supabase.co");
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
});
