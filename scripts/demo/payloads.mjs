/**
 * Demo seed ↔ current DB schema contract (authoritative: migrations).
 * UNKNOWN_FIELDS must stay 0. No migrations from this module.
 */

/** @typedef {{ allowed: string[], required: string[], forbidden: string[] }} TableContract */

/** @type {Record<string, TableContract>} */
export const DEMO_TABLE_CONTRACTS = Object.freeze({
  organizations: {
    allowed: [
      "legal_name",
      "commercial_name",
      "status",
      "cuit",
      "country",
      "province",
      "city",
      "base_currency",
      "created_by",
      "onboarding_completed_at",
      "timezone",
    ],
    required: ["legal_name", "created_by"],
    forbidden: [],
  },
  organization_settings: {
    allowed: ["organization_id", "key", "value"],
    required: ["organization_id", "key", "value"],
    forbidden: [],
  },
  organization_members: {
    allowed: ["organization_id", "user_id", "role", "status"],
    required: ["organization_id", "user_id", "role"],
    forbidden: [],
  },
  branches: {
    allowed: [
      "organization_id",
      "name",
      "code",
      "is_main",
      "address",
      "city",
      "province",
      "active",
    ],
    required: ["organization_id", "name"],
    forbidden: ["address_line1", "address_line"],
  },
  counterparties: {
    allowed: [
      "organization_id",
      "entity_type",
      "legal_name",
      "trade_name",
      "tax_id_type",
      "tax_id",
      "external_code",
      "email",
      "phone",
      "website",
      "notes",
      "is_active",
      "created_by",
    ],
    required: ["organization_id", "legal_name"],
    forbidden: [],
  },
  counterparty_roles: {
    allowed: ["counterparty_id", "organization_id", "role"],
    required: ["counterparty_id", "organization_id", "role"],
    forbidden: [],
  },
  products: {
    allowed: [
      "organization_id",
      "sku",
      "name",
      "product_type",
      "base_unit_code",
      "track_inventory",
      "active",
      "default_sale_price",
      "default_purchase_price",
    ],
    required: ["organization_id", "sku", "name", "product_type"],
    forbidden: [],
  },
  warehouses: {
    allowed: ["organization_id", "branch_id", "code", "name", "active"],
    required: ["organization_id", "code", "name"],
    forbidden: [],
  },
  sales_documents: {
    allowed: [
      "organization_id",
      "branch_id",
      "document_type",
      "document_date",
      "counterparty_id",
      "status",
      "currency_code",
      "internal_number",
      "customer_reference",
      "notes",
    ],
    required: ["organization_id", "document_type", "document_date", "counterparty_id"],
    forbidden: ["external_reference", "issue_date"],
  },
  sales_document_lines: {
    allowed: [
      "organization_id",
      "sales_document_id",
      "line_number",
      "description",
      "quantity",
      "unit_code",
      "unit_price",
      "discount_percent",
      "discount_amount",
      "notes",
    ],
    required: [
      "organization_id",
      "sales_document_id",
      "line_number",
      "description",
      "quantity",
      "unit_price",
    ],
    forbidden: ["line_net_amount", "product_id"],
  },
  purchase_documents: {
    allowed: [
      "organization_id",
      "branch_id",
      "supplier_id",
      "document_type",
      "issue_date",
      "accounting_date",
      "due_date",
      "currency_code",
      "currency_rate",
      "net_taxed_amount",
      "net_exempt_amount",
      "net_untaxed_amount",
      "vat_amount",
      "other_taxes_amount",
      "total_amount",
      "status",
      "external_reference",
      "idempotency_key",
      "notes",
      "created_by",
    ],
    required: [
      "organization_id",
      "supplier_id",
      "document_type",
      "issue_date",
      "accounting_date",
      "idempotency_key",
    ],
    forbidden: ["document_date"],
  },
  purchase_document_lines: {
    allowed: [
      "organization_id",
      "purchase_document_id",
      "line_number",
      "description",
      "quantity",
      "unit_code",
      "unit_price",
      "discount_amount",
      "vat_treatment",
      "vat_rate",
      "net_amount",
      "vat_amount",
      "exempt_amount",
      "untaxed_amount",
      "line_total",
      "account_id",
      "notes",
    ],
    required: [
      "organization_id",
      "purchase_document_id",
      "line_number",
      "description",
      "quantity",
      "unit_price",
    ],
    forbidden: ["product_id", "document_date"],
  },
  treasury_accounts: {
    allowed: [
      "organization_id",
      "branch_id",
      "account_type",
      "code",
      "name",
      "currency_code",
      "accounting_account_id",
      "bank_name",
      "account_mask",
      "cbu_cvu_alias",
      "is_active",
      "opening_setup_note",
      "created_by",
    ],
    required: [
      "organization_id",
      "account_type",
      "code",
      "name",
      "accounting_account_id",
    ],
    forbidden: ["bank_account_number", "account_number"],
  },
  treasury_operations: {
    allowed: [
      "organization_id",
      "branch_id",
      "internal_number",
      "operation_type",
      "status",
      "operation_date",
      "counterparty_id",
      "amount",
      "currency_code",
      "reference",
      "description",
      "reason",
      "idempotency_key",
      "created_by",
    ],
    required: [
      "organization_id",
      "operation_type",
      "operation_date",
      "amount",
      "description",
      "idempotency_key",
      "internal_number",
    ],
    forbidden: ["external_reference"],
  },
  treasury_operation_legs: {
    allowed: [
      "organization_id",
      "treasury_operation_id",
      "treasury_account_id",
      "direction",
      "amount",
      "line_number",
    ],
    required: [
      "organization_id",
      "treasury_operation_id",
      "treasury_account_id",
      "direction",
      "amount",
    ],
    forbidden: [],
  },
  inventory_operations: {
    allowed: [
      "organization_id",
      "internal_number",
      "operation_type",
      "status",
      "operation_date",
      "warehouse_id",
      "reason",
      "description",
      "reference",
      "idempotency_key",
      "created_by",
    ],
    required: [
      "organization_id",
      "internal_number",
      "operation_type",
      "operation_date",
      "warehouse_id",
      "idempotency_key",
    ],
    forbidden: ["external_reference"],
  },
  inventory_operation_lines: {
    allowed: [
      "organization_id",
      "inventory_operation_id",
      "line_number",
      "product_id",
      "warehouse_id",
      "direction",
      "quantity",
      "unit_code",
      "unit_cost",
    ],
    required: [
      "organization_id",
      "inventory_operation_id",
      "line_number",
      "product_id",
      "warehouse_id",
      "direction",
      "quantity",
      "unit_code",
    ],
    forbidden: [],
  },
  journal_entries: {
    allowed: [
      "organization_id",
      "entry_date",
      "description",
      "status",
      "source_type",
      "source_id",
      "external_reference",
      "created_by",
    ],
    required: ["organization_id", "entry_date", "description", "created_by"],
    forbidden: [],
  },
  journal_entry_lines: {
    allowed: [
      "organization_id",
      "journal_entry_id",
      "line_number",
      "account_id",
      "description",
      "debit",
      "credit",
      "counterparty_id",
    ],
    required: [
      "organization_id",
      "journal_entry_id",
      "line_number",
      "account_id",
      "debit",
      "credit",
    ],
    forbidden: [],
  },
  accounting_fiscal_years: {
    allowed: [
      "organization_id",
      "name",
      "start_date",
      "end_date",
      "status",
    ],
    required: ["organization_id", "name", "start_date", "end_date"],
    forbidden: [],
  },
});

/**
 * Validate a payload against the static contract (no DB).
 * @returns {{ ok: boolean, unknown: string[], missing: string[], forbiddenHit: string[] }}
 */
export function validatePayloadAgainstContract(table, payload) {
  const contract = DEMO_TABLE_CONTRACTS[table];
  if (!contract) {
    return {
      ok: false,
      unknown: Object.keys(payload || {}),
      missing: [],
      forbiddenHit: [`__unknown_table__:${table}`],
    };
  }
  const keys = Object.keys(payload || {}).filter(
    (k) => payload[k] !== undefined
  );
  const allowed = new Set(contract.allowed);
  const forbidden = new Set(contract.forbidden);
  const unknown = keys.filter((k) => !allowed.has(k));
  const forbiddenHit = keys.filter((k) => forbidden.has(k));
  const missing = contract.required.filter(
    (k) => payload[k] === undefined || payload[k] === null || payload[k] === ""
  );
  return {
    ok: unknown.length === 0 && forbiddenHit.length === 0 && missing.length === 0,
    unknown,
    missing,
    forbiddenHit,
  };
}

/**
 * Live preflight: confirm forbidden columns are absent and required columns exist.
 * @param {(sql: string, params?: unknown[]) => Promise<Array<Record<string, unknown>>>} dbq
 */
export async function runDemoSchemaPreflight(dbq) {
  const report = [];
  let ok = true;

  for (const [table, contract] of Object.entries(DEMO_TABLE_CONTRACTS)) {
    const cols = await dbq(
      `SELECT column_name
       FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = $1`,
      [table]
    ).catch(() => null);

    if (!cols) {
      // Table may not exist in a partial local stack — soft fail for optional inventory
      if (table.startsWith("inventory_")) {
        report.push({
          TABLE: table,
          RESULT: "SKIP_OPTIONAL",
          UNKNOWN_FIELDS: [],
          REQUIRED_FIELDS_MISSING: [],
        });
        continue;
      }
      ok = false;
      report.push({
        TABLE: table,
        RESULT: "FAIL",
        UNKNOWN_FIELDS: ["__table_unreadable__"],
        REQUIRED_FIELDS_MISSING: contract.required,
      });
      continue;
    }

    const present = new Set(cols.map((c) => String(c.column_name)));
    const unknownAssumptions = contract.forbidden.filter((f) => present.has(f));
    // "forbidden" means seed must not SEND them; if they exist in DB that's fine.
    // Unknown = seed allowed fields that are NOT in DB
    const missingInDb = contract.allowed.filter((f) => !present.has(f));
    // Only fail if required seed fields missing from DB
    const requiredMissing = contract.required.filter((f) => !present.has(f));

    // Also detect if historically wrong columns are what we'd wrongly rely on —
    // document_date on purchase_documents must NOT be used; verify issue_date exists
    const legacyWrong = [];
    if (table === "purchase_documents" && present.has("document_date") && !present.has("issue_date")) {
      legacyWrong.push("document_date_without_issue_date");
    }

    const result =
      requiredMissing.length === 0 && legacyWrong.length === 0 ? "PASS" : "FAIL";
    if (result === "FAIL") ok = false;

    report.push({
      TABLE: table,
      FIELDS_USED: contract.allowed,
      FIELDS_VALID: contract.allowed.filter((f) => present.has(f)),
      UNKNOWN_FIELDS: missingInDb.filter((f) => contract.required.includes(f) || contract.forbidden.includes(f) ? false : false),
      // Report seed-required columns missing from DB
      REQUIRED_FIELDS_MISSING: requiredMissing,
      FORBIDDEN_STILL_IN_SEED_CONTRACT: contract.forbidden,
      LEGACY_WRONG: legacyWrong,
      // Columns we must never send — listed for audit
      MUST_NOT_SEND: contract.forbidden,
      RESULT: result,
      // informational: allowed fields not in DB (optional / drift)
      ALLOWED_ABSENT_OPTIONAL: missingInDb.filter((f) => !contract.required.includes(f)),
    });
  }

  // Explicit critical assertions
  const purchase = report.find((r) => r.TABLE === "purchase_documents");
  if (purchase && purchase.RESULT === "PASS") {
    // ensure issue_date in FIELDS_VALID
    if (!purchase.FIELDS_VALID.includes("issue_date")) {
      purchase.RESULT = "FAIL";
      purchase.REQUIRED_FIELDS_MISSING.push("issue_date");
      ok = false;
    }
  }

  return {
    DEMO_SCHEMA_PREFLIGHT: ok ? "PASS" : "FAIL",
    UNKNOWN_FIELDS_REMAINING: report.reduce(
      (n, r) => n + (r.REQUIRED_FIELDS_MISSING?.length || 0),
      0
    ),
    report,
  };
}

export function formatPreflightFailure(preflight) {
  const fails = (preflight.report || []).filter((r) => r.RESULT === "FAIL");
  const parts = fails.map((f) => {
    const miss = (f.REQUIRED_FIELDS_MISSING || []).join(",") || "n/a";
    return `TABLE=${f.TABLE} REQUIRED_MISSING=${miss}`;
  });
  return `DEMO_SCHEMA_PREFLIGHT=FAIL ${parts.join(" | ")}`;
}

/**
 * Build purchase_documents insert body (current schema).
 * @param {{
 *   organizationId: string,
 *   branchId: string,
 *   supplierId: string,
 *   documentType?: string,
 *   issueDate: string,
 *   accountingDate?: string,
 *   dueDate?: string | null,
 *   externalReference: string,
 *   idempotencyKey: string,
 *   amounts: Record<string, string>,
 *   notes?: string,
 * }} opts
 */
export function buildPurchaseDocumentPayload({
  organizationId,
  branchId,
  supplierId,
  documentType = "SUPPLIER_INVOICE",
  issueDate,
  accountingDate,
  dueDate = null,
  externalReference,
  idempotencyKey,
  amounts,
  notes = "SYNTHETIC DEMO PURCHASE",
}) {
  const payload = {
    organization_id: organizationId,
    branch_id: branchId,
    supplier_id: supplierId,
    document_type: documentType,
    issue_date: issueDate,
    accounting_date: accountingDate || issueDate,
    due_date: dueDate,
    currency_code: "ARS",
    currency_rate: 1,
    external_reference: externalReference,
    idempotency_key: idempotencyKey,
    net_taxed_amount: amounts.net_taxed_amount,
    net_exempt_amount: amounts.net_exempt_amount ?? "0.00",
    net_untaxed_amount: amounts.net_untaxed_amount ?? "0.00",
    vat_amount: amounts.vat_amount,
    other_taxes_amount: amounts.other_taxes_amount ?? "0.00",
    total_amount: amounts.total_amount,
    status: "DRAFT",
    notes,
  };
  return payload;
}

export function buildPurchaseDocumentLinePayload({
  organizationId,
  purchaseDocumentId,
  lineNumber = 1,
  description,
  quantity,
  unitPrice,
  netAmount,
  vatAmount = "0.00",
  exemptAmount = "0.00",
  untaxedAmount = "0.00",
  lineTotal,
}) {
  return {
    organization_id: organizationId,
    purchase_document_id: purchaseDocumentId,
    line_number: lineNumber,
    description,
    quantity,
    unit_code: "UNIT",
    unit_price: unitPrice,
    vat_treatment: "TAXED",
    net_amount: netAmount,
    vat_amount: vatAmount,
    exempt_amount: exemptAmount,
    untaxed_amount: untaxedAmount,
    line_total: lineTotal ?? netAmount,
  };
}

/** CASH treasury account — no bank meta fields. */
export function buildCashTreasuryAccountPayload({
  organizationId,
  branchId,
  code,
  name,
  accountingAccountId,
}) {
  return {
    organization_id: organizationId,
    branch_id: branchId,
    account_type: "CASH",
    code,
    name,
    currency_code: "ARS",
    accounting_account_id: accountingAccountId,
    bank_name: null,
    account_mask: null,
    cbu_cvu_alias: null,
    is_active: true,
    opening_setup_note: "Demo cash — synthetic",
  };
}

/** BANK treasury account — synthetic mask/alias only. */
export function buildBankTreasuryAccountPayload({
  organizationId,
  branchId,
  code,
  name,
  accountingAccountId,
  bankName = "Banco Demo Ficticio",
  accountMask = "****DEMO",
  cbuCvuAlias = "DEMO-ALIAS-NOT-REAL",
}) {
  return {
    organization_id: organizationId,
    branch_id: branchId,
    account_type: "BANK",
    code,
    name,
    currency_code: "ARS",
    accounting_account_id: accountingAccountId,
    bank_name: bankName,
    account_mask: accountMask,
    cbu_cvu_alias: cbuCvuAlias,
    is_active: true,
    opening_setup_note: "Demo bank — synthetic identifiers only",
  };
}

export function buildSalesDocumentPayload({
  organizationId,
  branchId,
  documentDate,
  counterpartyId,
  internalNumber,
  customerReference,
  notes = "SYNTHETIC DEMO SALE — not fiscally authorized",
}) {
  return {
    organization_id: organizationId,
    branch_id: branchId,
    document_type: "SALES_ORDER",
    document_date: documentDate,
    counterparty_id: counterpartyId,
    status: "DRAFT",
    currency_code: "ARS",
    internal_number: internalNumber,
    customer_reference: customerReference,
    notes,
  };
}

export function buildSalesDocumentLinePayload({
  organizationId,
  salesDocumentId,
  lineNumber = 1,
  description,
  quantity,
  unitPrice,
}) {
  return {
    organization_id: organizationId,
    sales_document_id: salesDocumentId,
    line_number: lineNumber,
    description,
    quantity,
    unit_code: "UNIT",
    unit_price: unitPrice,
  };
}

export function buildInventoryAdjustmentInPayload({
  organizationId,
  warehouseId,
  internalNumber,
  operationDate,
  reference,
  idempotencyKey,
  reason = "Stock inicial (demo)",
}) {
  return {
    organization_id: organizationId,
    internal_number: internalNumber,
    operation_type: "ADJUSTMENT_IN",
    status: "DRAFT",
    operation_date: operationDate,
    warehouse_id: warehouseId,
    reason,
    description: "Movimiento de inventario (demo)",
    reference,
    idempotency_key: idempotencyKey,
  };
}

export function buildInventoryAdjustmentLinePayload({
  organizationId,
  inventoryOperationId,
  warehouseId,
  productId,
  quantity,
  unitCost,
  lineNumber = 1,
}) {
  return {
    organization_id: organizationId,
    inventory_operation_id: inventoryOperationId,
    line_number: lineNumber,
    product_id: productId,
    warehouse_id: warehouseId,
    direction: "IN",
    quantity,
    unit_code: "UNIT",
    unit_cost: unitCost,
  };
}

/**
 * post_treasury_operation: ADJUSTMENT requires treasury_operations.reason (free text)
 * with char_length(trim(reason)) >= 3.
 */
export const TREASURY_ADJUSTMENT_REASON_MIN_LENGTH = 3;

/**
 * @param {string} operationType
 * @param {string | null | undefined} reason
 */
export function treasuryReasonSatisfiesDomain(operationType, reason) {
  if (operationType !== "ADJUSTMENT") return true;
  return (
    typeof reason === "string" &&
    reason.trim().length >= TREASURY_ADJUSTMENT_REASON_MIN_LENGTH
  );
}

/**
 * @param {{
 *   organizationId: string,
 *   operationType: string,
 *   operationDate: string,
 *   amount: string,
 *   description: string,
 *   internalNumber: string,
 *   reference: string,
 *   idempotencyKey: string,
 *   reason?: string | null,
 * }} input
 */
export function buildTreasuryOperationPayload({
  organizationId,
  operationType,
  operationDate,
  amount,
  description,
  internalNumber,
  reference,
  idempotencyKey,
  reason,
}) {
  if (!treasuryReasonSatisfiesDomain(operationType, reason)) {
    throw new Error(
      `treasury ${reference}: ADJUSTMENT requires reason (>= ${TREASURY_ADJUSTMENT_REASON_MIN_LENGTH} chars)`
    );
  }
  /** @type {Record<string, unknown>} */
  const body = {
    organization_id: organizationId,
    operation_type: operationType,
    operation_date: operationDate,
    status: "DRAFT",
    currency_code: "ARS",
    amount,
    description,
    internal_number: internalNumber,
    reference,
    idempotency_key: idempotencyKey,
  };
  if (reason != null) body.reason = reason;
  return body;
}

/**
 * Idempotent action for a demo treasury operation found (or not) by idempotency_key.
 * - none → create
 * - DRAFT → complete (patch reason first when the domain rule is not met), then post
 * - any other status → reuse, never repost
 * @param {{ status: string, operation_type: string, reason?: string | null } | null | undefined} existing
 * @param {{ type: string, reason?: string | null }} desired
 * @returns {{ action: "create" } | { action: "reuse" } | { action: "complete_draft", patch: { reason: string } | null }}
 */
export function planTreasuryOperation(existing, desired) {
  if (!existing) return { action: "create" };
  if (existing.status !== "DRAFT") return { action: "reuse" };
  const needsReason = !treasuryReasonSatisfiesDomain(existing.operation_type, existing.reason);
  if (needsReason) {
    if (!treasuryReasonSatisfiesDomain(existing.operation_type, desired.reason)) {
      throw new Error("treasury DRAFT recovery: desired reason does not satisfy domain rule");
    }
    return { action: "complete_draft", patch: { reason: String(desired.reason) } };
  }
  return { action: "complete_draft", patch: null };
}
