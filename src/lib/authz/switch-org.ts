"use server";

import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";
import { ACTIVE_ORG_COOKIE, requireUser } from "@/lib/authz/context";
import { writeAuditEvent } from "@/lib/audit/write-audit-event";

export async function switchOrganization(organizationId: string) {
  const { supabase, user } = await requireUser();

  const { data: membership } = await supabase
    .from("organization_members")
    .select("id")
    .eq("user_id", user.id)
    .eq("organization_id", organizationId)
    .eq("status", "active")
    .maybeSingle();

  if (!membership) {
    return { ok: false as const, error: "No tenés acceso a esa empresa" };
  }

  const cookieStore = await cookies();
  cookieStore.set(ACTIVE_ORG_COOKIE, organizationId, {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    secure: process.env.NODE_ENV === "production",
  });

  await writeAuditEvent({
    organizationId,
    eventType: "organization.switched",
    entityType: "organization",
    entityId: organizationId,
    action: "switch",
  });

  revalidatePath("/", "layout");
  return { ok: true as const };
}
