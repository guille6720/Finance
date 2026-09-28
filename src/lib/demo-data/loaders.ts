/**
 * Read-only loaders for the demo modules. Every query uses the caller's RLS-scoped
 * client AND an explicit organization_id filter for the resolved active organization.
 * Embeds always name the FK: several of these tables have more than one relationship
 * to the embedded table (PostgREST PGRST201).
 */
import type { SupabaseClient } from "@supabase/supabase-js";
import { allRows, count, rows, type QueryResult } from "@/lib/demo-data/query";
import { toUnits } from "@/lib/demo-data/format";

export const COUNTERPARTY_ROLE_SELECT =
  "counterparty_id, counterparties!counterparty_roles_counterparty_id_fkey ( id, organization_id, legal_name, trade_name, tax_id, email, phone, is_active )";

export const CASH_LEG_SELECT =
  "id, treasury_account_id, direction, amount, treasury_operations!treasury_legs_org_op_fk!inner ( id, organization_id, internal_number, operation_type, status, operation_date, description, created_at )";

export const JOURNAL_LINE_TOTALS_SELECT =
  "id, debit, credit, journal_entries!journal_entry_lines_journal_entry_id_fkey!inner ( status )";

/** Commercial sales orders that are confirmed; quotes, drafts and cancellations are excluded. */
export const CONFIRMED_SALES_ORDER_STATUSES = ["CONFIRMED", "READY_TO_INVOICE", "INVOICED"] as const;
export const BOOKED_JOURNAL_STATUSES = ["POSTED", "REVERSED"] as const;

type Client = SupabaseClient;

function one<T>(value: T | T[] | null | undefined): T | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}

// ---------------------------------------------------------------------------
// Counterparties (customers / suppliers)
// ---------------------------------------------------------------------------

export type CounterpartyRole = "CUSTOMER" | "SUPPLIER";

export type CounterpartyRow = {
  id: string;
  legal_name: string;
  trade_name: string | null;
  tax_id: string | null;
  email: string | null;
  phone: string | null;
  is_active: boolean;
};

export type CounterpartySummary = {
  counterparties: CounterpartyRow[];
  total: number;
  active: number;
  withDocuments: number;
};

type RoleRow = {
  counterparty_id: string;
  counterparties: (CounterpartyRow & { organization_id: string }) | (CounterpartyRow & { organization_id: string })[] | null;
};

export function summarizeCounterparties(
  roleRows: RoleRow[],
  documentCounterpartyIds: readonly (string | null)[],
  organizationId: string
): CounterpartySummary {
  const byId = new Map<string, CounterpartyRow>();
  for (const r of roleRows) {
    const cp = one(r.counterparties);
    if (!cp || cp.organization_id !== organizationId || cp.id !== r.counterparty_id) continue;
    const { organization_id: _org, ...rest } = cp;
    void _org;
    byId.set(cp.id, rest);
  }
  const referenced = new Set(documentCounterpartyIds.filter((id): id is string => Boolean(id)));
  const counterparties = [...byId.values()].sort((a, b) =>
    (a.trade_name?.trim() || a.legal_name).localeCompare(b.trade_name?.trim() || b.legal_name, "es")
  );
  return {
    counterparties,
    total: counterparties.length,
    active: counterparties.filter((c) => c.is_active).length,
    withDocuments: counterparties.filter((c) => referenced.has(c.id)).length,
  };
}

export async function loadCounterparties(
  supabase: Client,
  organizationId: string,
  role: CounterpartyRole
): Promise<QueryResult<CounterpartySummary>> {
  const docs =
    role === "CUSTOMER"
      ? ({ table: "sales_documents", column: "counterparty_id" } as const)
      : ({ table: "purchase_documents", column: "supplier_id" } as const);

  const [roleRows, docRows] = await Promise.all([
    allRows<RoleRow>(`counterparty_roles.${role}`, (from, to) =>
      supabase
        .from("counterparty_roles")
        .select(COUNTERPARTY_ROLE_SELECT)
        .eq("organization_id", organizationId)
        .eq("role", role)
        .order("id", { ascending: true })
        .range(from, to)
    ),
    allRows<Record<string, string | null>>(`${docs.table}.${docs.column}`, (from, to) =>
      (role === "CUSTOMER"
        ? supabase.from("sales_documents").select("id, counterparty_id")
        : supabase.from("purchase_documents").select("id, supplier_id")
      )
        .eq("organization_id", organizationId)
        .order("id", { ascending: true })
        .range(from, to)
    ),
  ]);
  if (!roleRows.ok || !docRows.ok) return { ok: false };
  return {
    ok: true,
    data: summarizeCounterparties(
      roleRows.data,
      docRows.data.map((d) => d[docs.column]),
      organizationId
    ),
  };
}

// ---------------------------------------------------------------------------
// Cash (treasury accounts of type CASH)
// ---------------------------------------------------------------------------

export type CashAccount = {
  id: string;
  code: string;
  name: string;
  currency_code: string;
  is_active: boolean;
};

type CashLegRow = {
  id: string;
  treasury_account_id: string;
  direction: "INFLOW" | "OUTFLOW";
  amount: string | number;
  treasury_operations:
    | CashOperation
    | CashOperation[]
    | null;
};

type CashOperation = {
  id: string;
  organization_id: string;
  internal_number: string;
  operation_type: string;
  status: string;
  operation_date: string;
  description: string;
  created_at: string;
};

export type CashMovement = {
  legId: string;
  accountId: string;
  direction: "INFLOW" | "OUTFLOW";
  amount: bigint;
  operation: CashOperation;
};

export type CashSummary = {
  accounts: (CashAccount & { postedBalance: bigint })[];
  postedOperations: number;
  inflows: bigint;
  outflows: bigint;
  balance: bigint;
  recent: CashMovement[];
};

/**
 * Only POSTED operations move money (treasury truth = posted legs). REVERSED
 * operations are listed but excluded from totals.
 */
export function summarizeCash(
  accounts: CashAccount[],
  legRows: CashLegRow[],
  organizationId: string,
  recentLimit = 15
): CashSummary {
  const cashIds = new Set(accounts.map((a) => a.id));
  const movements: CashMovement[] = [];
  for (const leg of legRows) {
    const op = one(leg.treasury_operations);
    if (!op || op.organization_id !== organizationId) continue;
    if (!cashIds.has(leg.treasury_account_id)) continue;
    movements.push({
      legId: leg.id,
      accountId: leg.treasury_account_id,
      direction: leg.direction,
      amount: toUnits(leg.amount),
      operation: op,
    });
  }

  const zero = BigInt(0);
  let inflows = zero;
  let outflows = zero;
  const perAccount = new Map<string, bigint>();
  const postedOps = new Set<string>();
  for (const m of movements) {
    if (m.operation.status !== "POSTED") continue;
    postedOps.add(m.operation.id);
    const signed = m.direction === "INFLOW" ? m.amount : -m.amount;
    if (m.direction === "INFLOW") inflows += m.amount;
    else if (m.direction === "OUTFLOW") outflows += m.amount;
    perAccount.set(m.accountId, (perAccount.get(m.accountId) ?? zero) + signed);
  }

  const recent = [...movements]
    .sort(
      (a, b) =>
        b.operation.operation_date.localeCompare(a.operation.operation_date) ||
        b.operation.created_at.localeCompare(a.operation.created_at) ||
        b.operation.internal_number.localeCompare(a.operation.internal_number)
    )
    .slice(0, recentLimit);

  return {
    accounts: accounts.map((a) => ({ ...a, postedBalance: perAccount.get(a.id) ?? zero })),
    postedOperations: postedOps.size,
    inflows,
    outflows,
    balance: inflows - outflows,
    recent,
  };
}

export async function loadCash(
  supabase: Client,
  organizationId: string
): Promise<QueryResult<CashSummary>> {
  const accounts = await rows<CashAccount>(
    "treasury_accounts.CASH",
    supabase
      .from("treasury_accounts")
      .select("id, code, name, currency_code, is_active")
      .eq("organization_id", organizationId)
      .eq("account_type", "CASH")
      .order("code", { ascending: true })
  );
  if (!accounts.ok) return { ok: false };
  if (accounts.data.length === 0) {
    return { ok: true, data: summarizeCash([], [], organizationId) };
  }

  const cashIds = accounts.data.map((a) => a.id);
  const legs = await allRows<CashLegRow>("treasury_operation_legs.CASH", (from, to) =>
    supabase
      .from("treasury_operation_legs")
      .select(CASH_LEG_SELECT)
      .eq("organization_id", organizationId)
      .in("treasury_account_id", cashIds)
      .order("id", { ascending: true })
      .range(from, to)
  );
  if (!legs.ok) return { ok: false };
  return { ok: true, data: summarizeCash(accounts.data, legs.data, organizationId) };
}

// ---------------------------------------------------------------------------
// Accounting (journal)
// ---------------------------------------------------------------------------

type JournalLineTotalsRow = {
  debit: string | number;
  credit: string | number;
  journal_entries: { status: string } | { status: string }[] | null;
};

export type DebitCreditTotals = {
  debit: bigint;
  credit: bigint;
  difference: bigint;
  balanced: boolean;
};

export function sumDebitCredit(
  lines: { debit: string | number; credit: string | number }[]
): DebitCreditTotals {
  let debit = BigInt(0);
  let credit = BigInt(0);
  for (const l of lines) {
    debit += toUnits(l.debit);
    credit += toUnits(l.credit);
  }
  return { debit, credit, difference: debit - credit, balanced: debit === credit };
}

/** Lines of POSTED and REVERSED entries (a reversal is itself a POSTED entry). */
export async function loadJournalTotals(
  supabase: Client,
  organizationId: string
): Promise<QueryResult<DebitCreditTotals>> {
  const lines = await allRows<JournalLineTotalsRow>("journal_entry_lines.totals", (from, to) =>
    supabase
      .from("journal_entry_lines")
      .select(JOURNAL_LINE_TOTALS_SELECT)
      .eq("organization_id", organizationId)
      .in("journal_entries.status", [...BOOKED_JOURNAL_STATUSES])
      .order("id", { ascending: true })
      .range(from, to)
  );
  if (!lines.ok) return { ok: false };
  const booked = lines.data.filter((l) => {
    const status = one(l.journal_entries)?.status;
    return status === "POSTED" || status === "REVERSED";
  });
  return { ok: true, data: sumDebitCredit(booked) };
}

export type JournalEntryRow = {
  id: string;
  entry_number: string | null;
  entry_date: string;
  description: string;
  status: string;
  source_type: string;
  external_reference: string | null;
  reversal_of_entry_id: string | null;
};

export type AccountingSummary = {
  postedCount: number;
  reversedCount: number;
  totals: DebitCreditTotals;
  recent: (JournalEntryRow & { debit: bigint; credit: bigint })[];
};

export async function loadAccounting(
  supabase: Client,
  organizationId: string
): Promise<QueryResult<AccountingSummary>> {
  const [posted, reversed, totals, entries] = await Promise.all([
    count(
      "journal_entries.POSTED.count",
      supabase
        .from("journal_entries")
        .select("id", { count: "exact", head: true })
        .eq("organization_id", organizationId)
        .eq("status", "POSTED")
    ),
    count(
      "journal_entries.REVERSED.count",
      supabase
        .from("journal_entries")
        .select("id", { count: "exact", head: true })
        .eq("organization_id", organizationId)
        .eq("status", "REVERSED")
    ),
    loadJournalTotals(supabase, organizationId),
    rows<JournalEntryRow>(
      "journal_entries.recent",
      supabase
        .from("journal_entries")
        .select(
          "id, entry_number, entry_date, description, status, source_type, external_reference, reversal_of_entry_id"
        )
        .eq("organization_id", organizationId)
        .in("status", [...BOOKED_JOURNAL_STATUSES])
        .order("entry_date", { ascending: false })
        .order("posted_at", { ascending: false })
        .limit(15)
    ),
  ]);
  if (!posted.ok || !reversed.ok || !totals.ok || !entries.ok) return { ok: false };

  const ids = entries.data.map((e) => e.id);
  const perEntry = new Map<string, { debit: string | number; credit: string | number }[]>();
  if (ids.length > 0) {
    const lines = await allRows<{ id: string; journal_entry_id: string; debit: string; credit: string }>(
      "journal_entry_lines.recent",
      (from, to) =>
        supabase
          .from("journal_entry_lines")
          .select("id, journal_entry_id, debit, credit")
          .eq("organization_id", organizationId)
          .in("journal_entry_id", ids)
          .order("id", { ascending: true })
          .range(from, to)
    );
    if (!lines.ok) return { ok: false };
    for (const l of lines.data) {
      const list = perEntry.get(l.journal_entry_id) ?? [];
      list.push(l);
      perEntry.set(l.journal_entry_id, list);
    }
  }

  return {
    ok: true,
    data: {
      postedCount: posted.data,
      reversedCount: reversed.data,
      totals: totals.data,
      recent: entries.data.map((e) => {
        const t = sumDebitCredit(perEntry.get(e.id) ?? []);
        return { ...e, debit: t.debit, credit: t.credit };
      }),
    },
  };
}

// ---------------------------------------------------------------------------
// Executive metrics (reports + dashboard)
// ---------------------------------------------------------------------------

export type AmountMetric = { count: number; amount: bigint };

export type ConfirmedSaleRow = {
  id: string;
  internal_number: string | null;
  document_date: string | null;
  total: string | number;
};

export type PostedPurchaseRow = {
  id: string;
  document_type: string;
  point_of_sale: number | null;
  document_number: number | null;
  issue_date: string | null;
  total_amount: string | number;
};

export function loadConfirmedSalesRows(supabase: Client, organizationId: string) {
  return allRows<ConfirmedSaleRow>("sales_documents.confirmed", (from, to) =>
    supabase
      .from("sales_documents")
      .select("id, internal_number, document_date, total")
      .eq("organization_id", organizationId)
      .eq("document_type", "SALES_ORDER")
      .in("status", [...CONFIRMED_SALES_ORDER_STATUSES])
      .order("id", { ascending: true })
      .range(from, to)
  );
}

export function summarizeSales(rows: ConfirmedSaleRow[]): AmountMetric {
  return {
    count: rows.length,
    amount: rows.reduce((acc, d) => acc + toUnits(d.total), BigInt(0)),
  };
}

export async function loadConfirmedSales(
  supabase: Client,
  organizationId: string
): Promise<QueryResult<AmountMetric>> {
  const docs = await loadConfirmedSalesRows(supabase, organizationId);
  if (!docs.ok) return { ok: false };
  return { ok: true, data: summarizeSales(docs.data) };
}

export function loadPostedPurchasesRows(supabase: Client, organizationId: string) {
  return allRows<PostedPurchaseRow>("purchase_documents.posted", (from, to) =>
    supabase
      .from("purchase_documents")
      .select("id, document_type, point_of_sale, document_number, issue_date, total_amount")
      .eq("organization_id", organizationId)
      .eq("status", "POSTED")
      .order("id", { ascending: true })
      .range(from, to)
  );
}

/** Supplier credit notes subtract. */
export function signedPurchaseAmount(row: Pick<PostedPurchaseRow, "document_type" | "total_amount">) {
  const v = toUnits(row.total_amount);
  return row.document_type === "SUPPLIER_CREDIT_NOTE" ? -v : v;
}

export function summarizePurchases(rows: PostedPurchaseRow[]): AmountMetric {
  return {
    count: rows.length,
    amount: rows.reduce((acc, d) => acc + signedPurchaseAmount(d), BigInt(0)),
  };
}

/** POSTED purchase documents; supplier credit notes subtract. */
export async function loadPostedPurchases(
  supabase: Client,
  organizationId: string
): Promise<QueryResult<AmountMetric>> {
  const docs = await loadPostedPurchasesRows(supabase, organizationId);
  if (!docs.ok) return { ok: false };
  return { ok: true, data: summarizePurchases(docs.data) };
}

export type MonthlyActivity = {
  month: string;
  sales: bigint;
  purchases: bigint;
};

/**
 * Groups by the stored document month (sales: document_date, purchases: issue_date).
 * Returns up to `maxMonths` consecutive months ending at the latest month with data;
 * gaps inside that window are zero-filled. No data → empty array.
 */
export function buildMonthlyActivity(
  sales: ConfirmedSaleRow[],
  purchases: PostedPurchaseRow[],
  maxMonths = 6
): MonthlyActivity[] {
  const zero = BigInt(0);
  const byMonth = new Map<string, { sales: bigint; purchases: bigint }>();
  const bucket = (date: string | null) => {
    const m = date ? /^(\d{4})-(\d{2})/.exec(date) : null;
    if (!m) return null;
    const key = `${m[1]}-${m[2]}`;
    if (!byMonth.has(key)) byMonth.set(key, { sales: zero, purchases: zero });
    return byMonth.get(key)!;
  };
  for (const s of sales) {
    const b = bucket(s.document_date);
    if (b) b.sales += toUnits(s.total);
  }
  for (const p of purchases) {
    const b = bucket(p.issue_date);
    if (b) b.purchases += signedPurchaseAmount(p);
  }
  if (byMonth.size === 0) return [];

  const keys = [...byMonth.keys()].sort();
  const first = keys[0];
  const last = keys[keys.length - 1];
  let [y, mo] = last.split("-").map(Number);
  const out: MonthlyActivity[] = [];
  while (out.length < maxMonths) {
    const key = `${y}-${String(mo).padStart(2, "0")}`;
    const v = byMonth.get(key) ?? { sales: zero, purchases: zero };
    out.unshift({ month: key, ...v });
    if (key === first) break;
    mo -= 1;
    if (mo === 0) {
      mo = 12;
      y -= 1;
    }
  }
  return out;
}

export type RecentActivityItem = {
  id: string;
  kind: "sale" | "purchase" | "cash";
  date: string;
  reference: string;
  description: string;
  amount: bigint;
  direction: "in" | "out";
};

function purchaseReference(p: PostedPurchaseRow) {
  if (p.point_of_sale && p.document_number) {
    return `${String(p.point_of_sale).padStart(4, "0")}-${String(p.document_number).padStart(8, "0")}`;
  }
  return "—";
}

/** Latest confirmed sales, posted purchases and cash movements, newest first. */
export function buildRecentActivity(
  sales: ConfirmedSaleRow[],
  purchases: PostedPurchaseRow[],
  cash: CashMovement[],
  limit = 8
): RecentActivityItem[] {
  const items: RecentActivityItem[] = [
    ...sales
      .filter((s) => s.document_date)
      .map((s) => ({
        id: `sale-${s.id}`,
        kind: "sale" as const,
        date: s.document_date as string,
        reference: s.internal_number || "—",
        description: "Pedido de venta confirmado",
        amount: toUnits(s.total),
        direction: "in" as const,
      })),
    ...purchases
      .filter((p) => p.issue_date)
      .map((p) => ({
        id: `purchase-${p.id}`,
        kind: "purchase" as const,
        date: p.issue_date as string,
        reference: purchaseReference(p),
        description:
          p.document_type === "SUPPLIER_CREDIT_NOTE"
            ? "Nota de crédito de proveedor"
            : p.document_type === "SUPPLIER_DEBIT_NOTE"
              ? "Nota de débito de proveedor"
              : "Factura de proveedor",
        amount: toUnits(p.total_amount),
        direction: (p.document_type === "SUPPLIER_CREDIT_NOTE" ? "in" : "out") as "in" | "out",
      })),
    ...cash
      .filter((m) => m.operation.status === "POSTED")
      .map((m) => ({
        id: `cash-${m.legId}`,
        kind: "cash" as const,
        date: m.operation.operation_date,
        reference: m.operation.internal_number,
        description: m.operation.description,
        amount: m.amount,
        direction: (m.direction === "INFLOW" ? "in" : "out") as "in" | "out",
      })),
  ];
  return items
    .sort((a, b) => b.date.localeCompare(a.date) || a.id.localeCompare(b.id))
    .slice(0, limit);
}

/** Gross volume of POSTED treasury operations — not a net cash position. */
export async function loadPostedTreasuryVolume(
  supabase: Client,
  organizationId: string
): Promise<QueryResult<AmountMetric>> {
  const ops = await allRows<{ id: string; amount: string | number }>("treasury_operations.posted", (from, to) =>
    supabase
      .from("treasury_operations")
      .select("id, amount")
      .eq("organization_id", organizationId)
      .eq("status", "POSTED")
      .order("id", { ascending: true })
      .range(from, to)
  );
  if (!ops.ok) return { ok: false };
  return {
    ok: true,
    data: {
      count: ops.data.length,
      amount: ops.data.reduce((acc, o) => acc + toUnits(o.amount), BigInt(0)),
    },
  };
}

export function countPostedJournalEntries(supabase: Client, organizationId: string) {
  return count(
    "journal_entries.POSTED.count",
    supabase
      .from("journal_entries")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .eq("status", "POSTED")
  );
}

export function countCounterpartiesByRole(
  supabase: Client,
  organizationId: string,
  role: CounterpartyRole
) {
  return count(
    `counterparty_roles.${role}.count`,
    supabase
      .from("counterparty_roles")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .eq("role", role)
  );
}

export type TaxPeriodRow = {
  id: string;
  tax_code: string;
  jurisdiction_code: string | null;
  period_year: number;
  period_month: number | null;
  status: string;
};

export function loadRecentTaxPeriods(supabase: Client, organizationId: string, limit = 3) {
  return rows<TaxPeriodRow>(
    "tax_periods.recent",
    supabase
      .from("tax_periods")
      .select("id, tax_code, jurisdiction_code, period_year, period_month, status")
      .eq("organization_id", organizationId)
      .order("period_year", { ascending: false })
      .order("period_month", { ascending: false, nullsFirst: false })
      .limit(limit)
  );
}
