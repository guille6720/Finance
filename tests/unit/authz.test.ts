import { describe, it, expect } from "vitest";
import {
  assertOwner,
  assertCanMutate,
  assertPermission,
  roleHasPermission,
  AuthorizationError,
} from "@/lib/authz/permissions";

describe("authorization roles", () => {
  it("owner can perform owner-only actions", () => {
    expect(() => assertOwner("owner")).not.toThrow();
  });

  it("operator cannot perform owner-only actions", () => {
    expect(() => assertOwner("operator")).toThrow(AuthorizationError);
  });

  it("viewer cannot mutate data", () => {
    expect(() => assertCanMutate("viewer")).toThrow(AuthorizationError);
    expect(roleHasPermission("viewer", "org.update")).toBe(false);
  });

  it("admin can update organization", () => {
    expect(() => assertPermission("admin", "org.update")).not.toThrow();
  });

  it("accountant can manage periods but not invite members", () => {
    expect(roleHasPermission("accountant", "accounting.manage_periods")).toBe(
      true
    );
    expect(roleHasPermission("accountant", "members.invite")).toBe(false);
  });
});
