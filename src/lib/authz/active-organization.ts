import type { SupabaseClient } from "@supabase/supabase-js";
import { ACTIVE_ORG_COOKIE } from "@/lib/authz/context-constants";

export { ACTIVE_ORG_COOKIE };

export type UserOrganization = {
  id: string;
  role: string;
  legalName: string;
  commercialName: string | null;
  displayName: string;
};

type MembershipRow = {
  organization_id: string;
  role: string;
  organizations:
    | { id: string; legal_name: string; commercial_name: string | null }
    | { id: string; legal_name: string; commercial_name: string | null }[]
    | null;
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_RE.test(value);
}

export function organizationDisplayName(org: {
  legal_name: string;
  commercial_name: string | null;
}) {
  return org.commercial_name?.trim() || org.legal_name;
}

/** Rows whose organization is not readable under RLS are dropped. */
export function normalizeMemberships(rows: MembershipRow[] | null | undefined): UserOrganization[] {
  const out: UserOrganization[] = [];
  for (const row of rows ?? []) {
    const org = Array.isArray(row.organizations) ? row.organizations[0] : row.organizations;
    if (!org || org.id !== row.organization_id) continue;
    out.push({
      id: org.id,
      role: row.role,
      legalName: org.legal_name,
      commercialName: org.commercial_name,
      displayName: organizationDisplayName(org),
    });
  }
  return out;
}

/** Cookie value only counts when it matches one of the user's active memberships. */
export function resolveActiveOrganizationId(
  organizationIds: readonly string[],
  cookieValue: string | null | undefined
): string | null {
  if (cookieValue && organizationIds.includes(cookieValue)) return cookieValue;
  return organizationIds[0] ?? null;
}

const LOCAL_HOST_RE = /^(localhost|127\.\d+\.\d+\.\d+|0\.0\.0\.0|\[::1\])(:\d+)?$/i;

/** `secure` is only relaxed for plain-HTTP local development hosts. */
export function activeOrgCookieOptions(request: {
  host: string | null | undefined;
  protocol: string | null | undefined;
}) {
  const isLocalHttp =
    Boolean(request.host && LOCAL_HOST_RE.test(request.host)) && request.protocol !== "https:";
  return {
    httpOnly: true,
    sameSite: "lax" as const,
    secure: !isLocalHttp,
    path: "/",
  };
}

export async function loadUserOrganizations(
  supabase: SupabaseClient,
  userId: string
): Promise<UserOrganization[]> {
  const { data, error } = await supabase
    .from("organization_members")
    .select("organization_id, role, organizations ( id, legal_name, commercial_name )")
    .eq("user_id", userId)
    .eq("status", "active")
    .order("created_at", { ascending: true });
  if (error) return [];
  return normalizeMemberships(data as MembershipRow[] | null);
}

export type SetActiveOrganizationResult =
  | { status: 200; organizationId: string }
  | { status: 400 | 401 | 403; error: string };

/**
 * Validates membership with the caller's JWT (RLS applies) before the cookie may be set.
 */
export async function validateActiveOrganizationSwitch(
  supabase: SupabaseClient,
  requestedOrganizationId: unknown
): Promise<SetActiveOrganizationResult> {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { status: 401, error: "UNAUTHORIZED" };

  if (!isUuid(requestedOrganizationId)) {
    return { status: 400, error: "INVALID_ORGANIZATION_ID" };
  }

  const { data: membership, error } = await supabase
    .from("organization_members")
    .select("organization_id")
    .eq("user_id", user.id)
    .eq("organization_id", requestedOrganizationId)
    .eq("status", "active")
    .maybeSingle();

  if (error || !membership || membership.organization_id !== requestedOrganizationId) {
    return { status: 403, error: "FORBIDDEN" };
  }
  return { status: 200, organizationId: requestedOrganizationId };
}
