import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { writeAuditEvent } from "@/lib/audit/write-audit-event";

const EXPORT_TABLES = [
  "organizations",
  "organization_members",
  "branches",
  "business_profiles",
  "fiscal_profiles",
  "counterparties",
  "products",
  "sales_documents",
  "purchase_documents",
  "purchase_orders",
  "treasury_accounts",
  "inventory_operations",
  "journal_entries",
  "tax_determinations",
  "tax_periods",
] as const;

/**
 * Tenant-scoped export. Uses the caller's JWT + RLS.
 * Never accepts a service-role key from the client.
 * Does not log document payloads.
 */
export async function POST(request: NextRequest) {
  const correlationId =
    request.headers.get("x-request-id") ||
    request.headers.get("x-correlation-id") ||
    crypto.randomUUID();

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json(
      { error: "UNAUTHORIZED", correlation_id: correlationId },
      { status: 401, headers: { "x-request-id": correlationId } }
    );
  }

  let organizationId: string | undefined;
  try {
    const body = await request.json();
    organizationId = body?.organization_id;
  } catch {
    organizationId = undefined;
  }

  if (!organizationId) {
    return NextResponse.json(
      { error: "organization_id required", correlation_id: correlationId },
      { status: 400, headers: { "x-request-id": correlationId } }
    );
  }

  const membership = await supabase
    .from("organization_members")
    .select("id, role, status")
    .eq("organization_id", organizationId)
    .eq("user_id", user.id)
    .eq("status", "active")
    .maybeSingle();

  if (!membership.data) {
    return NextResponse.json(
      { error: "FORBIDDEN", correlation_id: correlationId },
      { status: 403, headers: { "x-request-id": correlationId } }
    );
  }

  const bundle: Record<string, unknown> = {
    exported_at: new Date().toISOString(),
    organization_id: organizationId,
    correlation_id: correlationId,
    tables: {},
  };

  for (const table of EXPORT_TABLES) {
    const filter =
      table === "organizations"
        ? supabase.from(table).select("*").eq("id", organizationId)
        : supabase.from(table).select("*").eq("organization_id", organizationId);
    const { data, error } = await filter.limit(5000);
    if (error) {
      (bundle.tables as Record<string, unknown>)[table] = {
        error: error.code ?? "QUERY_FAILED",
        count: 0,
      };
      continue;
    }
    (bundle.tables as Record<string, unknown>)[table] = {
      count: data?.length ?? 0,
      rows: data ?? [],
    };
  }

  await writeAuditEvent({
    organizationId,
    eventType: "tenant.export",
    entityType: "organization",
    entityId: organizationId,
    action: "export",
    metadata: {
      correlation_id: correlationId,
      table_count: EXPORT_TABLES.length,
    },
  });

  return NextResponse.json(bundle, {
    headers: {
      "x-request-id": correlationId,
      "x-correlation-id": correlationId,
      "content-disposition": `attachment; filename="org-${organizationId}-export.json"`,
    },
  });
}
