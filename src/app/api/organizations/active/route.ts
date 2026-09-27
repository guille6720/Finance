import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import {
  ACTIVE_ORG_COOKIE,
  activeOrgCookieOptions,
  validateActiveOrganizationSwitch,
} from "@/lib/authz/active-organization";
import { writeAuditEvent } from "@/lib/audit/write-audit-event";

/**
 * Sets the active organization cookie for the caller.
 * Membership is verified with the caller's JWT (RLS applies); the requested id is never
 * trusted on its own and the cookie is only written after that check passes.
 */
export async function POST(request: NextRequest) {
  let requested: unknown;
  try {
    const body = await request.json();
    requested = body?.organizationId;
  } catch {
    requested = undefined;
  }

  const supabase = await createClient();
  const result = await validateActiveOrganizationSwitch(supabase, requested);

  if (result.status !== 200) {
    return NextResponse.json({ error: result.error }, { status: result.status });
  }

  const response = NextResponse.json({ ok: true, organizationId: result.organizationId });
  response.cookies.set(
    ACTIVE_ORG_COOKIE,
    result.organizationId,
    activeOrgCookieOptions({
      host: request.headers.get("host"),
      protocol: request.nextUrl.protocol,
    })
  );

  await writeAuditEvent({
    organizationId: result.organizationId,
    eventType: "organization.switched",
    entityType: "organization",
    entityId: result.organizationId,
    action: "switch",
  });

  return response;
}
