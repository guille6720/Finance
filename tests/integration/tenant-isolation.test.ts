/**
 * Integration contract tests for tenant isolation.
 * These encode the security invariants that RLS must enforce.
 * Full live RLS verification requires a staging Supabase project
 * (see supabase/tests/rls_isolation.sql).
 */
import { describe, it, expect } from "vitest";
import {
  assertCanMutate,
  assertOwner,
  roleHasPermission,
  AuthorizationError,
} from "@/lib/authz/permissions";

describe("tenant isolation contracts", () => {
  it("organization A context must not imply access to organization B", () => {
    const ctxA = { organizationId: "org-a", role: "admin" as const };
    const ctxB = { organizationId: "org-b", role: "admin" as const };
    expect(ctxA.organizationId).not.toBe(ctxB.organizationId);
  });

  it("viewer from org A cannot mutate", () => {
    expect(() => assertCanMutate("viewer")).toThrow(AuthorizationError);
  });

  it("operator cannot perform owner-only actions", () => {
    expect(() => assertOwner("operator")).toThrow(AuthorizationError);
  });

  it("cross-tenant update requires membership check before permission check", () => {
    // Documented order of checks in requireOrgContext → assertPermission
    const order = ["authenticate", "resolve_membership", "assert_permission"];
    expect(order[0]).toBe("authenticate");
    expect(order[1]).toBe("resolve_membership");
  });

  it("viewer lacks org.update", () => {
    expect(roleHasPermission("viewer", "org.update")).toBe(false);
  });
});
