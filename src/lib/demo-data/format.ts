/**
 * Display helpers for read-only demo modules. Labels translate stored enum values
 * only; they add no accounting or legal interpretation.
 */

const ARS = new Intl.NumberFormat("es-AR", {
  style: "currency",
  currency: "ARS",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

/** numeric(19,4) values are handled as integers scaled by 10^4 to avoid float drift. */
export const MONEY_SCALE = BigInt(10_000);

/** Parses a PostgREST numeric (string or number) into scaled units. Invalid input → 0. */
export function toUnits(value: unknown): bigint {
  if (value === null || value === undefined) return BigInt(0);
  const raw = typeof value === "number" ? value.toFixed(4) : String(value).trim();
  const match = /^(-)?(\d+)(?:\.(\d+))?$/.exec(raw);
  if (!match) return BigInt(0);
  const [, sign, int, frac = ""] = match;
  const units = BigInt(int) * MONEY_SCALE + BigInt((frac + "0000").slice(0, 4));
  return sign ? -units : units;
}

export function unitsToNumber(units: bigint): number {
  return Number(units) / Number(MONEY_SCALE);
}

export function formatARS(value: number | bigint | string | null | undefined): string {
  const n =
    typeof value === "bigint" ? unitsToNumber(value) : unitsToNumber(toUnits(value ?? 0));
  return ARS.format(n);
}

export function formatCount(value: number): string {
  return new Intl.NumberFormat("es-AR").format(value);
}

/** Dates are stored as `YYYY-MM-DD` (date) or ISO timestamps; rendered as DD/MM/YYYY. */
export function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  if (!m) return "—";
  return `${m[3]}/${m[2]}/${m[1]}`;
}

export function formatPeriod(year: number, month: number | null): string {
  if (!month) return String(year);
  return `${String(month).padStart(2, "0")}/${year}`;
}

type Tone = "neutral" | "success" | "warning" | "danger" | "primary";

const DOCUMENT_STATUS: Record<string, { label: string; tone: Tone }> = {
  DRAFT: { label: "Borrador", tone: "neutral" },
  POSTED: { label: "Contabilizado", tone: "success" },
  REVERSED: { label: "Revertido", tone: "warning" },
};

export function documentStatusLabel(status: string | null | undefined) {
  return DOCUMENT_STATUS[status ?? ""] ?? { label: status || "—", tone: "neutral" as Tone };
}

export function activeLabel(isActive: boolean | null | undefined) {
  return isActive
    ? { label: "Activo", tone: "success" as Tone }
    : { label: "Inactivo", tone: "neutral" as Tone };
}

const TREASURY_OPERATION_TYPE: Record<string, string> = {
  OPENING_BALANCE: "Saldo inicial",
  PAYMENT: "Pago",
  COLLECTION: "Cobranza",
  TRANSFER: "Transferencia",
  ADJUSTMENT: "Ajuste",
};

export function treasuryOperationTypeLabel(type: string | null | undefined) {
  return TREASURY_OPERATION_TYPE[type ?? ""] ?? (type || "—");
}

export function legDirectionLabel(direction: string | null | undefined) {
  if (direction === "INFLOW") return { label: "Ingreso", tone: "success" as Tone };
  if (direction === "OUTFLOW") return { label: "Egreso", tone: "danger" as Tone };
  return { label: direction || "—", tone: "neutral" as Tone };
}

const JOURNAL_SOURCE: Record<string, string> = {
  MANUAL: "Manual",
  SALE: "Venta",
  PURCHASE: "Compra",
  PAYMENT: "Pago",
  COLLECTION: "Cobranza",
  BANK: "Banco",
  INVENTORY: "Inventario",
  PAYROLL: "Sueldos",
  TAX: "Impuestos",
  SYSTEM: "Sistema",
};

export function journalSourceLabel(source: string | null | undefined) {
  return JOURNAL_SOURCE[source ?? ""] ?? (source || "—");
}

const TAX_CODE: Record<string, string> = {
  IVA: "IVA",
  IIBB_LOCAL: "IIBB local",
  IIBB_CM: "IIBB Convenio Multilateral",
  GANANCIAS: "Ganancias",
  OTHER: "Otro",
};

export function taxCodeLabel(code: string | null | undefined) {
  return TAX_CODE[code ?? ""] ?? (code || "—");
}

/** Internal workflow state of the period; none of these mean "presented to ARCA". */
const TAX_PERIOD_STATUS: Record<string, { label: string; tone: Tone }> = {
  OPEN: { label: "Abierto", tone: "primary" },
  IN_REVIEW: { label: "En revisión", tone: "warning" },
  REVIEWED: { label: "Revisado", tone: "success" },
  CLOSED: { label: "Cerrado", tone: "neutral" },
  REOPENED: { label: "Reabierto", tone: "warning" },
};

export function taxPeriodStatusLabel(status: string | null | undefined) {
  return TAX_PERIOD_STATUS[status ?? ""] ?? { label: status || "—", tone: "neutral" as Tone };
}

const FEATURE_STATUS: Record<string, { label: string; tone: Tone }> = {
  enabled: { label: "Habilitado", tone: "success" },
  restricted: { label: "Restringido", tone: "warning" },
  disabled: { label: "Deshabilitado", tone: "neutral" },
};

export function featureStatusLabel(status: string | null | undefined) {
  return FEATURE_STATUS[status ?? ""] ?? { label: status || "—", tone: "neutral" as Tone };
}

const MEMBER_STATUS: Record<string, { label: string; tone: Tone }> = {
  active: { label: "Activo", tone: "success" },
  invited: { label: "Invitado", tone: "primary" },
  disabled: { label: "Deshabilitado", tone: "neutral" },
};

export function memberStatusLabel(status: string | null | undefined) {
  return MEMBER_STATUS[status ?? ""] ?? { label: status || "—", tone: "neutral" as Tone };
}

/** Stored descriptions may embed raw document-type codes (e.g. "Compra SUPPLIER_INVOICE"). */
const DOCUMENT_TYPE_WORDS: Record<string, string> = {
  SUPPLIER_INVOICE: "factura de proveedor",
  SUPPLIER_CREDIT_NOTE: "nota de crédito de proveedor",
  SUPPLIER_DEBIT_NOTE: "nota de débito de proveedor",
  SALES_ORDER: "pedido de venta",
  SALES_QUOTE: "presupuesto",
  SALES_INVOICE: "factura de venta",
};

const DOCUMENT_TYPE_PATTERN = new RegExp(`\\b(${Object.keys(DOCUMENT_TYPE_WORDS).join("|")})\\b`, "g");

export function humanizeDescription(text: string | null | undefined): string {
  if (!text) return "—";
  return text.replace(DOCUMENT_TYPE_PATTERN, (code) => DOCUMENT_TYPE_WORDS[code]);
}

export function counterpartyDisplayName(row: {
  legal_name: string;
  trade_name: string | null;
}) {
  return row.trade_name?.trim() || row.legal_name;
}
