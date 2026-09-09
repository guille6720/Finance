import { z } from "zod";
import { isValidCuit } from "./argentina";

export const loginSchema = z.object({
  email: z.string().email("Email inválido"),
  password: z.string().min(6, "Mínimo 6 caracteres"),
});

export const registerSchema = z.object({
  name: z.string().min(2, "Nombre requerido"),
  email: z.string().email("Email inválido"),
  password: z.string().min(8, "Mínimo 8 caracteres"),
  confirmPassword: z.string(),
}).refine((data) => data.password === data.confirmPassword, {
  message: "Las contraseñas no coinciden",
  path: ["confirmPassword"],
});

export const companySchema = z.object({
  legalName: z.string().min(2, "Razón social requerida"),
  tradeName: z.string().optional(),
  cuit: z.string().refine(isValidCuit, "CUIT inválido"),
  taxCondition: z.enum([
    "MONOTRIBUTISTA",
    "RESPONSABLE_INSCRIPTO",
    "EXENTO",
    "CONSUMIDOR_FINAL",
  ]),
  fiscalAddress: z.string().min(5, "Domicilio fiscal requerido"),
  province: z.string().min(2, "Provincia requerida"),
  mainActivity: z.string().optional(),
  grossIncome: z.string().optional(),
  activityStartDate: z.string().optional(),
  mainCurrency: z.string().default("ARS"),
});

export const clientSchema = z.object({
  name: z.string().min(2, "Nombre requerido"),
  document: z.string().optional(),
  taxCondition: z.enum([
    "MONOTRIBUTISTA",
    "RESPONSABLE_INSCRIPTO",
    "EXENTO",
    "CONSUMIDOR_FINAL",
  ]),
  email: z.string().email("Email inválido").optional().or(z.literal("")),
  phone: z.string().optional(),
  whatsapp: z.string().optional(),
  address: z.string().optional(),
  province: z.string().optional(),
  city: z.string().optional(),
  notes: z.string().optional(),
  active: z.boolean().default(true),
}).refine(
  (data) => {
    if (!data.document) return true;
    if (data.taxCondition === "CONSUMIDOR_FINAL") return true;
    return isValidCuit(data.document);
  },
  { message: "CUIT/CUIL inválido", path: ["document"] }
);

export const supplierSchema = z.object({
  legalName: z.string().min(2, "Razón social requerida"),
  cuit: z.string().optional(),
  taxCondition: z.enum([
    "MONOTRIBUTISTA",
    "RESPONSABLE_INSCRIPTO",
    "EXENTO",
    "CONSUMIDOR_FINAL",
  ]),
  email: z.string().email().optional().or(z.literal("")),
  phone: z.string().optional(),
  address: z.string().optional(),
  category: z.string().optional(),
  notes: z.string().optional(),
  active: z.boolean().default(true),
}).refine(
  (data) => !data.cuit || isValidCuit(data.cuit),
  { message: "CUIT inválido", path: ["cuit"] }
);

export const productSchema = z.object({
  internalCode: z.string().min(1, "Código requerido"),
  barcode: z.string().optional(),
  name: z.string().min(2, "Nombre requerido"),
  description: z.string().optional(),
  categoryId: z.string().optional(),
  type: z.enum(["PRODUCT", "SERVICE"]),
  costPrice: z.coerce.number().min(0),
  salePrice: z.coerce.number().min(0),
  taxRateId: z.string().optional(),
  stock: z.coerce.number().min(0).default(0),
  minStock: z.coerce.number().min(0).default(0),
  unit: z.string().default("unidad"),
  active: z.boolean().default(true),
});

export const saleItemSchema = z.object({
  productId: z.string().optional(),
  name: z.string().min(1),
  quantity: z.coerce.number().positive(),
  unitPrice: z.coerce.number().min(0),
  discount: z.coerce.number().min(0).default(0),
  taxRate: z.coerce.number().min(0).default(21),
});

export const saleSchema = z.object({
  clientId: z.string().optional(),
  date: z.string(),
  voucherType: z.enum([
    "PRESUPUESTO",
    "RECIBO_INTERNO",
    "FACTURA_A",
    "FACTURA_B",
    "FACTURA_C",
    "NOTA_CREDITO",
    "NOTA_DEBITO",
  ]),
  pointOfSale: z.coerce.number().int().min(1).default(1),
  voucherNumber: z.string().min(1),
  paymentMethod: z.enum([
    "EFECTIVO",
    "TRANSFERENCIA",
    "TARJETA_DEBITO",
    "TARJETA_CREDITO",
    "MERCADO_PAGO",
    "CUENTA_CORRIENTE",
    "OTRO",
  ]),
  status: z.enum(["COBRADO", "PENDIENTE", "PARCIAL", "ANULADO"]),
  notes: z.string().optional(),
  items: z.array(saleItemSchema).min(1, "Agregá al menos un producto"),
});

export const expenseSchema = z.object({
  supplierId: z.string().optional(),
  date: z.string(),
  voucherType: z.string().optional(),
  voucherNumber: z.string().optional(),
  category: z.string().min(1, "Categoría requerida"),
  subcategory: z.string().optional(),
  description: z.string().min(2, "Descripción requerida"),
  netAmount: z.coerce.number().min(0),
  taxAmount: z.coerce.number().min(0).default(0),
  perceptions: z.coerce.number().min(0).default(0),
  retentions: z.coerce.number().min(0).default(0),
  total: z.coerce.number().positive(),
  status: z.enum(["PAGADO", "PENDIENTE", "PARCIAL", "VENCIDO", "ANULADO"]),
  paymentMethod: z.enum([
    "EFECTIVO",
    "TRANSFERENCIA",
    "TARJETA_DEBITO",
    "TARJETA_CREDITO",
    "MERCADO_PAGO",
    "CUENTA_CORRIENTE",
    "OTRO",
  ]).optional(),
  dueDate: z.string().optional(),
});

export const cashOpenSchema = z.object({
  openingBalance: z.coerce.number().min(0),
  notes: z.string().optional(),
});

export const cashCloseSchema = z.object({
  actualBalance: z.coerce.number().min(0),
  notes: z.string().optional(),
});

export const cashMovementSchema = z.object({
  type: z.enum(["INGRESO", "EGRESO"]),
  amount: z.coerce.number().positive(),
  description: z.string().min(2),
});
