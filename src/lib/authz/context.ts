import { createClient } from "@/lib/supabase/server";
import {
  assertPermission,
  AuthorizationError,
} from "@/lib/authz/permissions";
import type { MemberRole, Permission } from "@/config/features";

export class AuthError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
    this.name = "AuthError";
  }
}

export type OrgContext = {
  userId: string;
  email: string;
  organizationId: string;
  role: MemberRole;
  organization: {
    id: string;
    legal_name: string;
    commercial_name: string | null;
    status: string;
    onboarding_completed_at: string | null;
  };
};

const ACTIVE_ORG_COOKIE = "active_organization_id";

export { ACTIVE_ORG_COOKIE };

export async function requireUser() {
  const supabase = await createClient();
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();
  if (error || !user) {
    throw new AuthError(401, "No autorizado");
  }
  return { supabase, user };
}

export async function getMemberships(userId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("organization_members")
    .select(
      "id, role, status, organization_id, organizations ( id, legal_name, commercial_name, status, onboarding_completed_at )"
    )
    .eq("user_id", userId)
    .eq("status", "active");

  if (error) {
    throw new AuthError(500, "No se pudieron cargar las empresas");
  }
  return data ?? [];
}

export async function requireOrgContext(
  organizationId?: string | null
): Promise<OrgContext> {
  const { supabase, user } = await requireUser();

  let orgId = organizationId ?? null;
  if (!orgId) {
    const { cookies } = await import("next/headers");
    const cookieStore = await cookies();
    orgId = cookieStore.get(ACTIVE_ORG_COOKIE)?.value ?? null;
  }

  if (!orgId) {
    const memberships = await getMemberships(user.id);
    orgId = memberships[0]?.organization_id ?? null;
  }

  if (!orgId) {
    throw new AuthError(400, "No tenés una empresa activa");
  }

  const { data: membership, error } = await supabase
    .from("organization_members")
    .select(
      "role, status, organization_id, organizations ( id, legal_name, commercial_name, status, onboarding_completed_at )"
    )
    .eq("user_id", user.id)
    .eq("organization_id", orgId)
    .eq("status", "active")
    .maybeSingle();

  if (error || !membership || !membership.organizations) {
    throw new AuthError(403, "No tenés acceso a esta empresa");
  }

  const org = membership.organizations as unknown as OrgContext["organization"];

  return {
    userId: user.id,
    email: user.email ?? "",
    organizationId: org.id,
    role: membership.role as MemberRole,
    organization: org,
  };
}

export async function requireOrgPermission(
  permission: Permission,
  organizationId?: string | null
): Promise<OrgContext> {
  const ctx = await requireOrgContext(organizationId);
  try {
    assertPermission(ctx.role, permission);
  } catch (e) {
    if (e instanceof AuthorizationError) {
      throw new AuthError(403, e.message);
    }
    throw e;
  }
  return ctx;
}
