import {
  ROLE_PERMISSIONS,
  type MemberRole,
  type Permission,
} from "@/config/features";

export class AuthorizationError extends Error {
  readonly code = "FORBIDDEN" as const;
  constructor(message = "No tenés permiso para esta acción") {
    super(message);
    this.name = "AuthorizationError";
  }
}

export function roleHasPermission(
  role: MemberRole,
  permission: Permission
): boolean {
  return ROLE_PERMISSIONS[role].includes(permission);
}

export function assertPermission(
  role: MemberRole,
  permission: Permission,
  message?: string
): void {
  if (!roleHasPermission(role, permission)) {
    throw new AuthorizationError(message);
  }
}

export function canMutateData(role: MemberRole): boolean {
  return role !== "viewer";
}

export function isOwnerOnlyAction(role: MemberRole): boolean {
  return role === "owner";
}

export function canManageMembers(role: MemberRole): boolean {
  return roleHasPermission(role, "members.invite");
}

export function canUpdateOrganization(role: MemberRole): boolean {
  return roleHasPermission(role, "org.update");
}

/** Owner-only actions (e.g. transfer ownership, close org). */
export function assertOwner(role: MemberRole): void {
  if (role !== "owner") {
    throw new AuthorizationError(
      "Solo el propietario puede realizar esta acción"
    );
  }
}

export function assertCanMutate(role: MemberRole): void {
  if (!canMutateData(role)) {
    throw new AuthorizationError("Tu rol es de solo lectura");
  }
}
