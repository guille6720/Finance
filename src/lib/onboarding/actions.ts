"use server";

import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";
import {
  onboardingSchema,
  recommendFeatures,
  type OnboardingInput,
} from "@/lib/onboarding/schema";
import { requireUser, ACTIVE_ORG_COOKIE } from "@/lib/authz/context";
import { writeAuditEvent } from "@/lib/audit/write-audit-event";

export type OnboardingResult =
  | { ok: true; organizationId: string }
  | { ok: false; error: string };

export async function completeOnboarding(
  raw: unknown
): Promise<OnboardingResult> {
  const parsed = onboardingSchema.safeParse(raw);
  if (!parsed.success) {
    return {
      ok: false,
      error: parsed.error.issues[0]?.message ?? "Datos inválidos",
    };
  }

  const input: OnboardingInput = parsed.data;
  const { supabase, user } = await requireUser();

  const { data: condition } = await supabase
    .from("fiscal_conditions")
    .select("id, code")
    .eq("code", input.fiscalConditionCode)
    .maybeSingle();

  if (!condition) {
    return { ok: false, error: "Condición fiscal no válida" };
  }

  const { data: org, error: orgError } = await supabase
    .from("organizations")
    .insert({
      legal_name: input.legalName,
      commercial_name: input.commercialName || null,
      cuit: input.cuit,
      country: input.country,
      province: input.province,
      city: input.city || null,
      timezone: input.timezone,
      base_currency: input.baseCurrency,
      status: "active",
      onboarding_completed_at: new Date().toISOString(),
      created_by: user.id,
    })
    .select("id")
    .single();

  if (orgError || !org) {
    return {
      ok: false,
      error: orgError?.message?.includes("cuit")
        ? "No se pudo crear la empresa. Revisá el CUIT."
        : "No se pudo crear la empresa",
    };
  }

  const orgId = org.id as string;

  const { error: memberError } = await supabase
    .from("organization_members")
    .insert({
      organization_id: orgId,
      user_id: user.id,
      role: "owner",
      status: "active",
      joined_at: new Date().toISOString(),
    });

  if (memberError) {
    return { ok: false, error: "No se pudo asignar el rol de propietario" };
  }

  await supabase.from("branches").insert({
    organization_id: orgId,
    name: input.branchName,
    code: "MAIN",
    is_main: true,
    city: input.city || null,
    province: input.province,
    active: true,
  });

  await supabase.from("fiscal_profiles").insert({
    organization_id: orgId,
    fiscal_condition_id: condition.id,
    fiscal_address: input.fiscalAddress,
    province: input.province,
    city: input.city || null,
  });

  await supabase.from("business_profiles").insert({
    organization_id: orgId,
    business_type: input.businessType,
    business_type_other: input.businessTypeOther || null,
    sells_products: input.sellsProducts,
    sells_services: input.sellsServices,
    manages_inventory: input.managesInventory,
    has_employees: input.hasEmployees,
    has_multiple_branches: input.hasMultipleBranches,
    needs_projects: input.needsProjects,
    needs_cost_centers: input.needsCostCenters,
    invoices_customers: input.invoicesCustomers,
    works_with_suppliers: input.worksWithSuppliers,
  });

  const year = new Date().getFullYear();
  await supabase.from("accounting_periods").insert({
    organization_id: orgId,
    name: `Ejercicio ${year}`,
    starts_on: `${year}-01-01`,
    ends_on: `${year}-12-31`,
    is_closed: false,
  });

  if (input.needsCostCenters) {
    await supabase.from("cost_centers").insert({
      organization_id: orgId,
      code: "GEN",
      name: "General",
      active: true,
    });
  }

  const { data: catalog } = await supabase
    .from("feature_catalog")
    .select("id, code, default_status");

  const recommended = new Set(
    recommendFeatures(input).map((r) => r.code)
  );

  if (catalog?.length) {
    const rows = catalog.map((f) => {
      let status = f.default_status as string;
      if (f.code === "dashboard") status = "enabled";
      else if (input.acceptedRecommendedModules && recommended.has(f.code)) {
        status = f.code === "medical_legal" ? "restricted" : "enabled";
      } else if (f.code === "medical_legal") {
        status = "restricted";
      } else {
        status = "disabled";
      }
      return {
        organization_id: orgId,
        feature_id: f.id,
        status,
        enabled_at: status === "enabled" ? new Date().toISOString() : null,
      };
    });
    await supabase.from("organization_features").insert(rows);
  }

  await supabase.from("organization_settings").insert([
    {
      organization_id: orgId,
      key: "ux.default_mode",
      value: { mode: "business" },
    },
    {
      organization_id: orgId,
      key: "onboarding.completed",
      value: { at: new Date().toISOString(), version: 1 },
    },
  ]);

  await writeAuditEvent({
    organizationId: orgId,
    eventType: "organization.created",
    entityType: "organization",
    entityId: orgId,
    action: "create",
    metadata: {
      businessType: input.businessType,
      recommended: [...recommended],
    },
  });

  const cookieStore = await cookies();
  cookieStore.set(ACTIVE_ORG_COOKIE, orgId, {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    secure: process.env.NODE_ENV === "production",
  });

  revalidatePath("/dashboard");
  revalidatePath("/onboarding");

  return { ok: true, organizationId: orgId };
}
