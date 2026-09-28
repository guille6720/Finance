"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { roleHasPermission } from "@/lib/authz/permissions";
import { writeAuditEvent } from "@/lib/audit/write-audit-event";
import { requireActiveOrganization } from "@/lib/demo-data/organization-context";
import {
  COUNTERPARTY_ROLES,
  counterpartyFormFromData,
  counterpartyFormSchema,
  normalizeTaxId,
  type CounterpartyRoleCode,
} from "@/lib/counterparties/schema";

export type CounterpartyFormState = {
  error?: string;
  fieldErrors?: Partial<Record<string, string>>;
  values?: Record<string, string | boolean>;
};

const ROLE_COPY: Record<CounterpartyRoleCode, { singular: string; path: string }> = {
  CUSTOMER: { singular: "cliente", path: "/customers" },
  SUPPLIER: { singular: "proveedor", path: "/suppliers" },
};

const GENERIC_ERROR = "No pudimos guardar los datos. Intentá de nuevo en unos minutos.";

function otherRole(role: CounterpartyRoleCode): CounterpartyRoleCode {
  return role === "CUSTOMER" ? "SUPPLIER" : "CUSTOMER";
}

export async function createCounterparty(
  role: CounterpartyRoleCode,
  _prev: CounterpartyFormState,
  formData: FormData
): Promise<CounterpartyFormState> {
  if (!COUNTERPARTY_ROLES.includes(role)) return { error: GENERIC_ERROR };
  const copy = ROLE_COPY[role];

  const raw = counterpartyFormFromData(formData);
  const parsed = counterpartyFormSchema.safeParse(raw);
  if (!parsed.success) {
    const fieldErrors: Record<string, string> = {};
    for (const issue of parsed.error.issues) {
      const key = String(issue.path[0] ?? "form");
      fieldErrors[key] ??= issue.message;
    }
    return { fieldErrors, values: raw };
  }
  const input = parsed.data;

  const { supabase, user, organizationId, role: memberRole } = await requireActiveOrganization();
  if (!memberRole || !roleHasPermission(memberRole, "counterparties.create")) {
    return { error: `Tu rol no permite crear ${copy.singular}s.`, values: raw };
  }

  const roles: CounterpartyRoleCode[] = input.alsoOtherRole ? [role, otherRole(role)] : [role];
  const taxIdNormalized = normalizeTaxId(input.taxIdType, input.taxId);

  let counterpartyId!: string;
  let reused = false;

  if (taxIdNormalized) {
    const { data: existing, error: lookupError } = await supabase
      .from("counterparties")
      .select("id, legal_name, counterparty_roles ( role )")
      .eq("organization_id", organizationId)
      .eq("tax_id_normalized", taxIdNormalized)
      .maybeSingle();
    if (lookupError) {
      console.error("[counterparties] duplicate lookup failed", { code: lookupError.code });
      return { error: GENERIC_ERROR, values: raw };
    }
    if (existing) {
      const current = new Set(
        ((existing.counterparty_roles as { role: string }[] | null) ?? []).map((r) => r.role)
      );
      if (current.has(role)) {
        return {
          fieldErrors: {
            taxId: `Ya existe un ${copy.singular} con ese documento: ${existing.legal_name}.`,
          },
          values: raw,
        };
      }
      counterpartyId = existing.id as string;
      reused = true;
      roles.splice(0, roles.length, ...roles.filter((r) => !current.has(r)));
    }
  }

  if (!reused) {
    const { data: created, error: insertError } = await supabase
      .from("counterparties")
      .insert({
        organization_id: organizationId,
        entity_type: input.entityType,
        legal_name: input.legalName,
        trade_name: input.tradeName,
        tax_id_type: input.taxIdType,
        tax_id: input.taxIdType === "NONE" ? null : input.taxId,
        email: input.email,
        phone: input.phone,
        is_active: true,
        created_by: user.id,
      })
      .select("id")
      .single();
    if (insertError || !created) {
      console.error("[counterparties] insert failed", { code: insertError?.code });
      if (insertError?.code === "23505") {
        return { fieldErrors: { taxId: "Ya existe un registro con ese documento." }, values: raw };
      }
      if (insertError?.code === "42501") {
        return { error: `Tu rol no permite crear ${copy.singular}s.`, values: raw };
      }
      if (insertError?.message?.includes("invalid tax id")) {
        return { fieldErrors: { taxId: "El documento no es válido." }, values: raw };
      }
      return { error: GENERIC_ERROR, values: raw };
    }
    counterpartyId = created.id as string;
  }

  const { error: roleError } = await supabase.from("counterparty_roles").insert(
    roles.map((r) => ({
      counterparty_id: counterpartyId,
      organization_id: organizationId,
      role: r,
      created_by: user.id,
    }))
  );
  if (roleError) {
    console.error("[counterparties] role insert failed", { code: roleError.code, reused });
    if (!reused) {
      const { error: cleanupError } = await supabase
        .from("counterparties")
        .delete()
        .eq("id", counterpartyId)
        .eq("organization_id", organizationId);
      if (cleanupError) {
        console.error("[counterparties] orphan cleanup failed", { code: cleanupError.code });
      }
    }
    return { error: GENERIC_ERROR, values: raw };
  }

  await writeAuditEvent({
    organizationId,
    eventType: reused ? "counterparty.role_added" : "counterparty.created",
    entityType: "counterparty",
    entityId: counterpartyId,
    action: reused ? "update" : "create",
    metadata: { roles },
  });

  revalidatePath("/customers");
  revalidatePath("/suppliers");
  revalidatePath("/dashboard");
  redirect(`${copy.path}?${reused ? "actualizado" : "creado"}=1`);
}

function revalidateCounterparties() {
  revalidatePath("/customers", "layout");
  revalidatePath("/suppliers", "layout");
  revalidatePath("/dashboard");
}

export async function updateCounterparty(
  role: CounterpartyRoleCode,
  counterpartyId: string,
  _prev: CounterpartyFormState,
  formData: FormData
): Promise<CounterpartyFormState> {
  if (!COUNTERPARTY_ROLES.includes(role)) return { error: GENERIC_ERROR };
  const copy = ROLE_COPY[role];
  const raw = counterpartyFormFromData(formData);
  const parsed = counterpartyFormSchema.safeParse(raw);
  if (!parsed.success) {
    const fieldErrors: Record<string, string> = {};
    for (const issue of parsed.error.issues) {
      fieldErrors[String(issue.path[0] ?? "form")] ??= issue.message;
    }
    return { fieldErrors, values: raw };
  }
  const input = parsed.data;

  const { supabase, user, organizationId, role: memberRole } = await requireActiveOrganization();
  if (!roleHasPermission(memberRole, "counterparties.update")) {
    return { error: `Tu rol no permite modificar ${copy.singular}s.`, values: raw };
  }

  const { data: current, error: currentError } = await supabase
    .from("counterparties")
    .select("id, counterparty_roles ( role )")
    .eq("id", counterpartyId)
    .eq("organization_id", organizationId)
    .maybeSingle();
  if (currentError || !current) {
    if (currentError) console.error("[counterparties] load for update failed", { code: currentError.code });
    return { error: "No encontramos el registro en esta empresa.", values: raw };
  }

  const taxIdNormalized = normalizeTaxId(input.taxIdType, input.taxId);
  if (taxIdNormalized) {
    const { data: clash, error: clashError } = await supabase
      .from("counterparties")
      .select("id, legal_name")
      .eq("organization_id", organizationId)
      .eq("tax_id_normalized", taxIdNormalized)
      .maybeSingle();
    if (clashError) {
      console.error("[counterparties] duplicate lookup failed", { code: clashError.code });
      return { error: GENERIC_ERROR, values: raw };
    }
    if (clash && clash.id !== counterpartyId) {
      return {
        fieldErrors: { taxId: `Ese documento ya lo tiene otro registro: ${clash.legal_name}.` },
        values: raw,
      };
    }
  }

  const { error: updateError } = await supabase
    .from("counterparties")
    .update({
      entity_type: input.entityType,
      legal_name: input.legalName,
      trade_name: input.tradeName,
      tax_id_type: input.taxIdType,
      tax_id: input.taxIdType === "NONE" ? null : input.taxId,
      email: input.email,
      phone: input.phone,
    })
    .eq("id", counterpartyId)
    .eq("organization_id", organizationId);
  if (updateError) {
    console.error("[counterparties] update failed", { code: updateError.code });
    if (updateError.code === "23505") {
      return { fieldErrors: { taxId: "Ya existe un registro con ese documento." }, values: raw };
    }
    if (updateError.code === "42501") return { error: `Tu rol no permite modificar ${copy.singular}s.`, values: raw };
    if (updateError.message?.includes("invalid tax id")) {
      return { fieldErrors: { taxId: "El documento no es válido." }, values: raw };
    }
    return { error: GENERIC_ERROR, values: raw };
  }

  const currentRoles = new Set(
    ((current.counterparty_roles as { role: string }[] | null) ?? []).map((r) => r.role)
  );
  const other = otherRole(role);
  if (input.alsoOtherRole && !currentRoles.has(other) && roleHasPermission(memberRole, "counterparties.create")) {
    const { error: roleError } = await supabase.from("counterparty_roles").insert({
      counterparty_id: counterpartyId,
      organization_id: organizationId,
      role: other,
      created_by: user.id,
    });
    if (roleError) console.error("[counterparties] role add on update failed", { code: roleError.code });
  }

  await writeAuditEvent({
    organizationId,
    eventType: "counterparty.updated",
    entityType: "counterparty",
    entityId: counterpartyId,
    action: "update",
  });
  revalidateCounterparties();
  redirect(`${copy.path}?guardado=1`);
}

export type CounterpartyRowActionState = { error?: string };

export async function setCounterpartyActive(
  role: CounterpartyRoleCode,
  counterpartyId: string,
  active: boolean
): Promise<CounterpartyRowActionState> {
  if (!COUNTERPARTY_ROLES.includes(role)) return { error: GENERIC_ERROR };
  const copy = ROLE_COPY[role];
  const { supabase, organizationId, role: memberRole } = await requireActiveOrganization();
  if (!roleHasPermission(memberRole, "counterparties.update")) {
    return { error: `Tu rol no permite modificar ${copy.singular}s.` };
  }
  const { data, error } = await supabase
    .from("counterparties")
    .update({ is_active: active })
    .eq("id", counterpartyId)
    .eq("organization_id", organizationId)
    .select("id");
  if (error || !data?.length) {
    if (error) console.error("[counterparties] toggle active failed", { code: error.code });
    return { error: GENERIC_ERROR };
  }
  await writeAuditEvent({
    organizationId,
    eventType: active ? "counterparty.activated" : "counterparty.deactivated",
    entityType: "counterparty",
    entityId: counterpartyId,
    action: "update",
  });
  revalidateCounterparties();
  redirect(`${copy.path}/${counterpartyId}?${active ? "activado" : "desactivado"}=1`);
}

export async function deleteCounterparty(
  role: CounterpartyRoleCode,
  counterpartyId: string
): Promise<CounterpartyRowActionState> {
  if (!COUNTERPARTY_ROLES.includes(role)) return { error: GENERIC_ERROR };
  const copy = ROLE_COPY[role];
  const { supabase, organizationId, role: memberRole } = await requireActiveOrganization();
  if (!roleHasPermission(memberRole, "counterparties.delete")) {
    return { error: `Tu rol no permite eliminar ${copy.singular}s.` };
  }
  const { data, error } = await supabase
    .from("counterparties")
    .delete()
    .eq("id", counterpartyId)
    .eq("organization_id", organizationId)
    .select("id");
  if (error) {
    console.error("[counterparties] delete failed", { code: error.code });
    if (error.code === "23503" || error.message?.includes("journal references")) {
      return {
        error: `No se puede eliminar porque tiene comprobantes o asientos asociados. Podés desactivarlo para que no se use más.`,
      };
    }
    if (error.code === "42501") return { error: `Tu rol no permite eliminar ${copy.singular}s.` };
    return { error: GENERIC_ERROR };
  }
  if (!data?.length) return { error: "No encontramos el registro en esta empresa." };
  await writeAuditEvent({
    organizationId,
    eventType: "counterparty.deleted",
    entityType: "counterparty",
    entityId: counterpartyId,
    action: "delete",
  });
  revalidateCounterparties();
  redirect(`${copy.path}?eliminado=1`);
}
