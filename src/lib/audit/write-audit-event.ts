import { createClient } from "@/lib/supabase/server";

export type AuditWriteInput = {
  organizationId?: string | null;
  eventType: string;
  entityType: string;
  entityId?: string | null;
  action: string;
  metadata?: Record<string, unknown>;
  ipAddress?: string | null;
  userAgent?: string | null;
};

/**
 * Append-only audit writer. Never updates or deletes events.
 * Fails soft on write errors so business flows are not blocked, but logs server-side.
 */
export async function writeAuditEvent(input: AuditWriteInput) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase.from("audit_events").insert({
    organization_id: input.organizationId ?? null,
    actor_user_id: user?.id ?? null,
    event_type: input.eventType,
    entity_type: input.entityType,
    entity_id: input.entityId ?? null,
    action: input.action,
    metadata: input.metadata ?? {},
    ip_address: input.ipAddress ?? null,
    user_agent: input.userAgent ?? null,
  });

  if (error) {
    console.error("[audit] write failed", {
      eventType: input.eventType,
      code: error.code,
    });
  }
}
