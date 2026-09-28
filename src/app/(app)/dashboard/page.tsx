import { requireActiveOrganization } from "@/lib/demo-data/organization-context";
import { logQueryFailure } from "@/lib/demo-data/query";
import { getUxMode } from "@/lib/ui-mode/server";
import { BusinessDashboard } from "@/components/dashboard/business-dashboard";
import { AccountingDashboard } from "@/components/dashboard/accounting-dashboard";
import type { SetupState } from "@/components/dashboard/setup-progress";

export default async function DashboardPage() {
  const { supabase, organizationId: orgId } = await requireActiveOrganization();
  const mode = await getUxMode();

  const [orgRes, fiscalRes, branchRes, businessRes, memberCountRes] = await Promise.all([
    supabase
      .from("organizations")
      .select("id, legal_name, commercial_name, status")
      .eq("id", orgId)
      .maybeSingle(),
    supabase
      .from("fiscal_profiles")
      .select("id, fiscal_condition_id, fiscal_address")
      .eq("organization_id", orgId)
      .maybeSingle(),
    supabase.from("branches").select("id").eq("organization_id", orgId).limit(1).maybeSingle(),
    supabase.from("business_profiles").select("id").eq("organization_id", orgId).maybeSingle(),
    supabase
      .from("organization_members")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", orgId)
      .eq("status", "active"),
  ]);

  const setupErrors = [
    ["organizations", orgRes.error],
    ["fiscal_profiles", fiscalRes.error],
    ["branches", branchRes.error],
    ["business_profiles", businessRes.error],
    ["organization_members.count", memberCountRes.error],
  ] as const;
  for (const [label, error] of setupErrors) {
    if (error) logQueryFailure(`dashboard.${label}`, error);
  }

  const org = orgRes.data;
  const organizationName = org
    ? org.commercial_name?.trim() || org.legal_name
    : "Empresa activa";

  const setup: SetupState = setupErrors.some(([, error]) => Boolean(error))
    ? { ok: false }
    : {
        ok: true,
        checks: {
          orgActive: org?.status === "active",
          fiscal: Boolean(fiscalRes.data?.fiscal_condition_id && fiscalRes.data?.fiscal_address),
          branch: Boolean(branchRes.data?.id),
          business: Boolean(businessRes.data?.id),
          members: (memberCountRes.count ?? 0) > 1,
        },
      };

  if (mode === "accountant") {
    return AccountingDashboard({ supabase, organizationId: orgId, organizationName });
  }
  return BusinessDashboard({ supabase, organizationId: orgId, organizationName, setup });
}
