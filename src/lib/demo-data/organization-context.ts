import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import {
  ACTIVE_ORG_COOKIE,
  resolveActiveOrganizationId,
} from "@/lib/authz/active-organization";
import { logQueryFailure } from "@/lib/demo-data/query";

export type ActiveOrganizationContext = {
  supabase: SupabaseClient;
  user: User;
  organizationId: string;
};

export class OrganizationContextError extends Error {
  constructor() {
    super("No pudimos cargar esta información.");
    this.name = "OrganizationContextError";
  }
}

/**
 * Server-side only. Uses the caller's session (RLS enforced); the cookie is honoured
 * only when it matches one of the user's own active memberships.
 */
export async function requireActiveOrganization(): Promise<ActiveOrganizationContext> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const cookieStore = await cookies();
  const { data: memberships, error } = await supabase
    .from("organization_members")
    .select("organization_id")
    .eq("user_id", user.id)
    .eq("status", "active")
    .order("created_at", { ascending: true });

  if (error) {
    logQueryFailure("organization_members.active", error);
    throw new OrganizationContextError();
  }

  const organizationId = resolveActiveOrganizationId(
    (memberships ?? []).map((m) => m.organization_id as string),
    cookieStore.get(ACTIVE_ORG_COOKIE)?.value
  );
  if (!organizationId) redirect("/onboarding");

  return { supabase, user, organizationId };
}
