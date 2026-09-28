import { z } from "zod";
import { isValidCuit, isValidEmail } from "@/lib/validations/argentina";

export const COUNTERPARTY_ROLES = ["CUSTOMER", "SUPPLIER"] as const;
export type CounterpartyRoleCode = (typeof COUNTERPARTY_ROLES)[number];

export const TAX_ID_TYPES = ["CUIT", "CUIL", "DNI", "PASSPORT", "NONE"] as const;
export type TaxIdType = (typeof TAX_ID_TYPES)[number];

export const TAX_ID_TYPE_LABELS: Record<TaxIdType, string> = {
  CUIT: "CUIT",
  CUIL: "CUIL",
  DNI: "DNI",
  PASSPORT: "Pasaporte",
  NONE: "Sin documento",
};

export const ENTITY_TYPES = ["LEGAL_ENTITY", "INDIVIDUAL"] as const;
export const ENTITY_TYPE_LABELS: Record<(typeof ENTITY_TYPES)[number], string> = {
  LEGAL_ENTITY: "Empresa",
  INDIVIDUAL: "Persona",
};

/** Mirrors public.normalize_counterparty_tax_id so duplicates are found before insert. */
export function normalizeTaxId(type: TaxIdType, value: string | null | undefined): string | null {
  if (type === "NONE" || !value?.trim()) return null;
  if (type === "CUIT" || type === "CUIL" || type === "DNI") return value.replace(/\D/g, "");
  return value.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
}

function taxIdError(type: TaxIdType, value: string): string | null {
  const normalized = normalizeTaxId(type, value) ?? "";
  if (type === "CUIT" || type === "CUIL") {
    return isValidCuit(normalized) ? null : `El ${type} no es válido. Revisá los 11 dígitos.`;
  }
  if (type === "DNI") {
    return /^\d{7,8}$/.test(normalized) ? null : "El DNI debe tener 7 u 8 dígitos.";
  }
  return normalized.length >= 3 ? null : "El documento es demasiado corto.";
}

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max, `Máximo ${max} caracteres.`)
    .transform((v) => (v === "" ? null : v));

export const counterpartyFormSchema = z
  .object({
    legalName: z
      .string()
      .trim()
      .min(2, "Ingresá la razón social o el nombre (al menos 2 caracteres).")
      .max(200, "Máximo 200 caracteres."),
    tradeName: optionalText(200),
    entityType: z.enum(ENTITY_TYPES, "Elegí si es una empresa o una persona."),
    taxIdType: z.enum(TAX_ID_TYPES, "Elegí el tipo de documento."),
    taxId: optionalText(30),
    email: optionalText(200).refine((v) => v === null || isValidEmail(v), "El email no es válido."),
    phone: optionalText(50),
    alsoOtherRole: z.boolean(),
  })
  .superRefine((data, ctx) => {
    if (data.taxIdType === "NONE") return;
    if (!data.taxId) {
      ctx.addIssue({ code: "custom", path: ["taxId"], message: "Ingresá el número de documento." });
      return;
    }
    const error = taxIdError(data.taxIdType, data.taxId);
    if (error) ctx.addIssue({ code: "custom", path: ["taxId"], message: error });
  });

export type CounterpartyFormInput = z.infer<typeof counterpartyFormSchema>;

export function counterpartyFormFromData(formData: FormData) {
  const text = (key: string) => {
    const v = formData.get(key);
    return typeof v === "string" ? v : "";
  };
  return {
    legalName: text("legalName"),
    tradeName: text("tradeName"),
    entityType: text("entityType"),
    taxIdType: text("taxIdType"),
    taxId: text("taxId"),
    email: text("email"),
    phone: text("phone"),
    alsoOtherRole: formData.get("alsoOtherRole") === "on",
  };
}
