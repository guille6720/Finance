import { z } from "zod";
import { BUSINESS_TYPES } from "@/config/features";
import { isValidCuit, cleanCuit } from "@/lib/validations/argentina";

export const onboardingSchema = z.object({
  legalName: z.string().min(2, "Ingresá la razón social"),
  commercialName: z.string().optional(),
  cuit: z
    .string()
    .min(11, "Ingresá el CUIT")
    .refine((v) => isValidCuit(v), "CUIT inválido")
    .transform((v) => cleanCuit(v)),
  country: z.string().default("AR"),
  province: z.string().min(1, "Seleccioná la provincia"),
  city: z.string().optional(),
  timezone: z.string().default("America/Argentina/Buenos_Aires"),
  baseCurrency: z.string().default("ARS"),
  fiscalConditionCode: z.string().min(1, "Seleccioná la condición fiscal"),
  fiscalAddress: z.string().min(2, "Ingresá el domicilio fiscal"),
  branchName: z.string().min(1).default("Casa central"),
  businessType: z.enum(BUSINESS_TYPES),
  businessTypeOther: z.string().optional(),
  sellsProducts: z.boolean(),
  sellsServices: z.boolean(),
  managesInventory: z.boolean(),
  hasEmployees: z.boolean(),
  hasMultipleBranches: z.boolean(),
  needsProjects: z.boolean(),
  needsCostCenters: z.boolean(),
  invoicesCustomers: z.boolean(),
  worksWithSuppliers: z.boolean(),
  acceptedRecommendedModules: z.boolean().default(true),
});

export type OnboardingInput = z.infer<typeof onboardingSchema>;

export type RecommendedFeature = {
  code: string;
  reason: string;
};

export function recommendFeatures(
  input: Pick<
    OnboardingInput,
    | "sellsProducts"
    | "sellsServices"
    | "managesInventory"
    | "hasEmployees"
    | "hasMultipleBranches"
    | "needsProjects"
    | "needsCostCenters"
    | "invoicesCustomers"
    | "worksWithSuppliers"
    | "businessType"
  >
): RecommendedFeature[] {
  const out: RecommendedFeature[] = [
    { code: "dashboard", reason: "Siempre disponible para ver el estado de tu empresa" },
  ];

  if (input.invoicesCustomers || input.sellsProducts || input.sellsServices) {
    out.push({ code: "customers", reason: "Para llevar tus clientes" });
    out.push({ code: "sales", reason: "Para registrar lo que cobrás" });
  }
  if (input.worksWithSuppliers) {
    out.push({ code: "suppliers", reason: "Para tus proveedores a pagar" });
    out.push({ code: "purchases", reason: "Para registrar compras y gastos" });
  }
  if (input.managesInventory || input.sellsProducts) {
    out.push({ code: "inventory", reason: "Para controlar mercadería" });
  }
  if (input.sellsProducts && input.businessType === "retail") {
    out.push({ code: "pos", reason: "Útil si vendés en mostrador" });
  }
  out.push({ code: "cash", reason: "Para el dinero en caja" });
  out.push({ code: "banks", reason: "Para cuentas bancarias" });
  out.push({ code: "reports", reason: "Para ver resúmenes sin jerga contable" });

  if (input.needsProjects) {
    out.push({ code: "projects", reason: "Indicaste que trabajás por proyectos" });
  }
  if (input.hasEmployees) {
    out.push({ code: "payroll", reason: "Indicaste que tenés empleados (futuro)" });
  }
  if (input.businessType === "medical_legal" || input.businessType === "healthcare") {
    out.push({
      code: "medical_legal",
      reason: "Vertical de salud / médico-legal (dominio separado, restringido)",
    });
  }

  // Deduplicate by code
  const seen = new Set<string>();
  return out.filter((f) => {
    if (seen.has(f.code)) return false;
    seen.add(f.code);
    return true;
  });
}
