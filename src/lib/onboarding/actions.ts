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
import { requireActiveOrganization } from "@/lib/demo-data/organization-context";
import { provisionOrganization } from "@/lib/onboarding/provision";
import { isTesterLimitError, runPreviewDemoSetup, testerLimitMessage } from "@/lib/preview/demo-seed";

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
    if (isTesterLimitError(orgError)) {
      return { ok: false, error: testerLimitMessage() };
    }
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

  if (input.needsCostCenters) {
    await supabase.from("cost_centers").insert({
      organization_id: orgId,
      code: "GEN",
      name: "General",
      active: true,
    });
  }

  const recommended = new Set(
    recommendFeatures(input).map((r) => r.code)
  );

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

  const provisioned = await provisionOrganization(supabase, user.id, orgId);
  if (!provisioned.ok) {
    console.error("[onboarding] provisioning incomplete", { step: provisioned.step });
  } else {
    const demo = await runPreviewDemoSetup(supabase, orgId);
    if (!demo.ok) console.error("[onboarding] preview demo incomplete", { step: demo.step });
  }

  revalidatePath("/dashboard");
  revalidatePath("/onboarding");

  return { ok: true, organizationId: orgId };
}

export type FinishSetupState = { error?: string };

/**
 * Retries provisioning (and, in the public preview, the demo data) for the active
 * organization; only its creator-owner can run it. Every step is idempotent.
 */
export async function finishOrganizationSetup(): Promise<FinishSetupState> {
  const { supabase, user, organizationId } = await requireActiveOrganization();
  const result = await provisionOrganization(supabase, user.id, organizationId);
  if (!result.ok) {
    console.error("[onboarding] setup retry failed", { step: result.step });
    return {
      error:
        result.step === "not_owner"
          ? "Solo quien creó la empresa puede completar la configuración."
          : "No pudimos completar la configuración. Intentá de nuevo en unos minutos.",
    };
  }
  const demo = await runPreviewDemoSetup(supabase, organizationId);
  if (!demo.ok) {
    console.error("[onboarding] preview demo retry failed", { step: demo.step });
    return { error: "No pudimos cargar los datos de prueba. Intentá de nuevo en unos minutos." };
  }
  revalidatePath("/", "layout");
  return {};
}
