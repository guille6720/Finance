/**
 * Deterministic synthetic fixtures for accountant demo seed.
 * All identities are fictitious. No real CUITs.
 */

export const PRIMARY_ORG = Object.freeze({
  code: "DEMO-AR-001",
  legal_name: "EMPRESA DEMO ARGENTINA SA",
  commercial_name: "Empresa Demo",
  email: "demo-contador@example.invalid",
  phone: "+54 11 0000 0000",
  address_line: "Av. Demo 1234",
  city: "Ciudad Autónoma de Buenos Aires",
  country: "AR",
  province: "CABA",
  base_currency: "ARS",
  tax_placeholder: "SYNTHETIC-NOT-A-CUIT",
});

export const BETA_ORG = Object.freeze({
  code: "DEMO-AR-BETA-001",
  legal_name: "EMPRESA DEMO BETA SRL",
  commercial_name: "Demo Beta",
  email: "demo-beta@example.invalid",
  phone: "+54 11 0000 0001",
  address_line: "Calle Ficticia 999",
  city: "Rosario",
  country: "AR",
  province: "Santa Fe",
  base_currency: "ARS",
  tax_placeholder: "DEMO-BETA",
});

export const DEMO_USERS = Object.freeze([
  {
    key: "admin",
    full_name: "Admin Demo",
    email: "admin.demo@example.invalid",
    role: "admin",
  },
  {
    key: "accountant",
    full_name: "Contador Demo",
    email: "contador.demo@example.invalid",
    role: "accountant",
  },
  {
    key: "operator",
    full_name: "Operador Demo",
    email: "operador.demo@example.invalid",
    role: "operator",
  },
  {
    key: "auditor",
    full_name: "Auditor Demo",
    email: "auditor.demo@example.invalid",
    role: "viewer",
  },
]);

export const CUSTOMERS = Object.freeze([
  { code: "DEMO-C-001", legal_name: "Cliente Demo Norte", trade_name: "Norte Demo", kind: "RI", tax_id_type: "FOREIGN_TAX_ID", tax_id: "DEMO-CUST-NORTE-001" },
  { code: "DEMO-C-002", legal_name: "Cliente Demo Sur", trade_name: "Sur Demo", kind: "RI", tax_id_type: "FOREIGN_TAX_ID", tax_id: "DEMO-CUST-SUR-002" },
  { code: "DEMO-C-003", legal_name: "Librería Ficticia SRL", trade_name: "Librería Demo", kind: "RI", tax_id_type: "FOREIGN_TAX_ID", tax_id: "DEMO-CUST-LIB-003" },
  { code: "DEMO-C-004", legal_name: "Comercio Ejemplo SA", trade_name: "Comercio Demo", kind: "RI", tax_id_type: "FOREIGN_TAX_ID", tax_id: "DEMO-CUST-COM-004" },
  { code: "DEMO-C-005", legal_name: "Servicios Demo SAS", trade_name: "Servicios Demo", kind: "RI", tax_id_type: "FOREIGN_TAX_ID", tax_id: "DEMO-CUST-SRV-005" },
  { code: "DEMO-C-006", legal_name: "Consumidor Final Demo", trade_name: "CF Demo", kind: "CF", tax_id_type: "NONE", tax_id: null },
  { code: "DEMO-C-007", legal_name: "Monotributo Demo Uno", trade_name: "MT Demo 1", kind: "MT", tax_id_type: "FOREIGN_TAX_ID", tax_id: "DEMO-CUST-MT-007" },
  { code: "DEMO-C-008", legal_name: "Exento Demo Educativo", trade_name: "Exento Demo", kind: "EX", tax_id_type: "FOREIGN_TAX_ID", tax_id: "DEMO-CUST-EX-008" },
  { code: "DEMO-C-009", legal_name: "Cliente Demo Oeste", trade_name: "Oeste Demo", kind: "RI", tax_id_type: "FOREIGN_TAX_ID", tax_id: "DEMO-CUST-OES-009" },
  { code: "DEMO-C-010", legal_name: "Cliente Demo Este", trade_name: "Este Demo", kind: "RI", tax_id_type: "FOREIGN_TAX_ID", tax_id: "DEMO-CUST-EST-010" },
  { code: "DEMO-C-011", legal_name: "Distribuidora Ficticia SA", trade_name: "Dist Demo", kind: "RI", tax_id_type: "FOREIGN_TAX_ID", tax_id: "DEMO-CUST-DIST-011" },
  { code: "DEMO-C-012", legal_name: "Consumidor Final Demo 2", trade_name: "CF Demo 2", kind: "CF", tax_id_type: "NONE", tax_id: null },
]);

export const SUPPLIERS = Object.freeze([
  { code: "DEMO-S-001", legal_name: "Proveedor Demo Uno SA", tax_id: "DEMO-SUP-UNO-001" },
  { code: "DEMO-S-002", legal_name: "Insumos Ficticios SRL", tax_id: "DEMO-SUP-INS-002" },
  { code: "DEMO-S-003", legal_name: "Servicios Ejemplo SAS", tax_id: "DEMO-SUP-SRV-003" },
  { code: "DEMO-S-004", legal_name: "Transporte Demo", tax_id: "DEMO-SUP-TRN-004" },
  { code: "DEMO-S-005", legal_name: "Alquileres Demo", tax_id: "DEMO-SUP-ALQ-005" },
  { code: "DEMO-S-006", legal_name: "Utilities Demo SA", tax_id: "DEMO-SUP-UTL-006" },
  { code: "DEMO-S-007", legal_name: "Papelería Ficticia SRL", tax_id: "DEMO-SUP-PAP-007" },
  { code: "DEMO-S-008", legal_name: "Consultora Demo Profesional", tax_id: "DEMO-SUP-CON-008" },
  { code: "DEMO-S-009", legal_name: "Logística Demo Express", tax_id: "DEMO-SUP-LOG-009" },
]);

export const PRODUCTS = Object.freeze([
  { sku: "DEMO-P-A", name: "Producto Demo A", product_type: "STOCK_ITEM", track_inventory: true, sale: 15000, purchase: 9000 },
  { sku: "DEMO-P-B", name: "Producto Demo B", product_type: "STOCK_ITEM", track_inventory: true, sale: 22000, purchase: 13500 },
  { sku: "DEMO-P-C", name: "Producto Demo C", product_type: "STOCK_ITEM", track_inventory: true, sale: 8500, purchase: 5100 },
  { sku: "DEMO-P-D", name: "Producto Demo D", product_type: "STOCK_ITEM", track_inventory: true, sale: 45500, purchase: 28000 },
  { sku: "DEMO-P-E", name: "Producto Demo E", product_type: "STOCK_ITEM", track_inventory: true, sale: 12000, purchase: 7200 },
  { sku: "DEMO-P-F", name: "Insumo Demo", product_type: "STOCK_ITEM", track_inventory: true, sale: 3500, purchase: 2100 },
  { sku: "DEMO-P-G", name: "Repuesto Demo", product_type: "STOCK_ITEM", track_inventory: true, sale: 9800, purchase: 6000 },
  { sku: "DEMO-P-H", name: "Kit Demo", product_type: "STOCK_ITEM", track_inventory: true, sale: 32000, purchase: 20000 },
  { sku: "DEMO-P-I", name: "Pack Demo Oficina", product_type: "STOCK_ITEM", track_inventory: true, sale: 18500, purchase: 11000 },
  { sku: "DEMO-P-J", name: "Mercadería Demo Extra", product_type: "STOCK_ITEM", track_inventory: true, sale: 7600, purchase: 4500 },
  { sku: "DEMO-NS-1", name: "Producto No Inventariable Demo", product_type: "NON_STOCK", track_inventory: false, sale: 5000, purchase: 0 },
  { sku: "DEMO-NS-2", name: "Accesorio Demo", product_type: "NON_STOCK", track_inventory: false, sale: 2500, purchase: 0 },
  { sku: "DEMO-NS-3", name: "Licencia Demo", product_type: "NON_STOCK", track_inventory: false, sale: 40000, purchase: 0 },
  { sku: "DEMO-NS-4", name: "Suscripción Demo", product_type: "NON_STOCK", track_inventory: false, sale: 9900, purchase: 0 },
  { sku: "DEMO-SV-1", name: "Servicio Profesional Demo", product_type: "SERVICE", track_inventory: false, sale: 55000, purchase: 0 },
  { sku: "DEMO-SV-2", name: "Mantenimiento Mensual Demo", product_type: "SERVICE", track_inventory: false, sale: 28000, purchase: 0 },
  { sku: "DEMO-SV-3", name: "Consultoría Demo", product_type: "SERVICE", track_inventory: false, sale: 75000, purchase: 0 },
  { sku: "DEMO-SV-4", name: "Capacitación Demo", product_type: "SERVICE", track_inventory: false, sale: 42000, purchase: 0 },
  { sku: "DEMO-SV-5", name: "Soporte Técnico Demo", product_type: "SERVICE", track_inventory: false, sale: 18000, purchase: 0 },
  { sku: "DEMO-SV-6", name: "Auditoría Interna Demo", product_type: "SERVICE", track_inventory: false, sale: 95000, purchase: 0 },
  { sku: "DEMO-P-K", name: "Producto Demo Premium", product_type: "STOCK_ITEM", track_inventory: true, sale: 88000, purchase: 52000 },
  { sku: "DEMO-P-L", name: "Producto Demo Económico", product_type: "STOCK_ITEM", track_inventory: true, sale: 4200, purchase: 2500 },
]);

/** Opening stock ADJUSTMENT_IN operations (one per tracked product, main warehouse). */
export const DEMO_OPENING_INVENTORY_COUNT = 8;

/**
 * Demo tax periods — HOMOLOGATION workspace only, status OPEN (review), never filed.
 * IVA is national (jurisdiction null).
 */
export const DEMO_TAX_PERIODS = Object.freeze([
  { tax_code: "IVA", jurisdiction_code: null, period_year: 2026, period_month: 1 },
  { tax_code: "IVA", jurisdiction_code: null, period_year: 2026, period_month: 2 },
  { tax_code: "IVA", jurisdiction_code: null, period_year: 2026, period_month: 3 },
]);

/**
 * Treasury ADJUSTMENT scenarios. `account` is a demo treasury account code.
 * Reason is synthetic free text (post_treasury_operation requires >= 3 chars).
 */
export const DEMO_TREASURY_ADJUSTMENTS = Object.freeze([
  {
    ref: "DEMO-TR-FEE-1",
    type: "ADJUSTMENT",
    date: "2026-03-15",
    amount: 2500,
    account: "DEMO-BCO-CC",
    dir: "OUTFLOW",
    reason: "Comision bancaria demo - dato sintetico, no real",
  },
]);

export const BETA_CUSTOMERS = Object.freeze([
  { code: "DEMO-BETA-C-1", legal_name: "Cliente Beta Uno", tax_id_type: "FOREIGN_TAX_ID", tax_id: "DEMO-BETA-CUST-001" },
  { code: "DEMO-BETA-C-2", legal_name: "Cliente Beta Dos", tax_id_type: "NONE", tax_id: null },
]);

export const BETA_SUPPLIERS = Object.freeze([
  { code: "DEMO-BETA-S-1", legal_name: "Proveedor Beta Uno", tax_id: "DEMO-BETA-SUP-001" },
]);

/** Deterministic ARS money helper — integer centavos as string decimal. */
export function money(n) {
  return (Math.round(Number(n) * 100) / 100).toFixed(2);
}

/** Stable pseudo-random in [0,1) from seed string + index */
export function demoRand(seed, i) {
  let h = 2166136261;
  const s = `${seed}:${i}`;
  for (let k = 0; k < s.length; k++) {
    h ^= s.charCodeAt(k);
    h = Math.imul(h, 16777619);
  }
  return ((h >>> 0) % 10000) / 10000;
}

export function demoDate(year, month, day) {
  const m = String(month).padStart(2, "0");
  const d = String(day).padStart(2, "0");
  return `${year}-${m}-${d}`;
}
