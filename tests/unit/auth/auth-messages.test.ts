import { describe, it, expect } from "vitest";
import { authErrorMessage, safeNextPath } from "@/lib/auth/messages";

describe("authErrorMessage", () => {
  it("translates the Supabase errors testers hit most", () => {
    expect(
      authErrorMessage({ code: "email_address_invalid", message: 'Email address "x@example.com" is invalid' }, "signup")
    ).toMatch(/no es válido/);
    expect(authErrorMessage({ code: "user_already_exists", message: "User already registered" }, "signup")).toMatch(
      /Ya existe una cuenta/
    );
    expect(authErrorMessage({ code: "weak_password", message: "Password should be at least" }, "signup")).toMatch(
      /débil/
    );
    expect(authErrorMessage({ code: "email_not_confirmed", message: "Email not confirmed" }, "login")).toMatch(
      /confirmaste/
    );
    expect(authErrorMessage({ code: "over_email_send_rate_limit", status: 429 }, "signup")).toMatch(/intentos/);
  });

  it("never echoes the raw English message", () => {
    const raw = "Database error saving new user: secret";
    expect(authErrorMessage({ message: raw }, "signup")).not.toContain("secret");
    expect(authErrorMessage({ code: "invalid_credentials", message: "Invalid login credentials" }, "login")).toBe(
      "Email o contraseña incorrectos."
    );
  });
});

describe("safeNextPath", () => {
  it("only accepts same-site relative paths", () => {
    expect(safeNextPath("/onboarding")).toBe("/onboarding");
    expect(safeNextPath("https://evil.example")).toBe("/dashboard");
    expect(safeNextPath("//evil.example")).toBe("/dashboard");
    expect(safeNextPath("/\\evil.example")).toBe("/dashboard");
    expect(safeNextPath(null, "/onboarding")).toBe("/onboarding");
  });
});
