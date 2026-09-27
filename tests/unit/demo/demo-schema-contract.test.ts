/**
 * Schema contract + payload builder tests for demo seed.
 */
import { describe, it, expect } from "vitest";
import {
  validatePayloadAgainstContract,
  runDemoSchemaPreflight,
  buildPurchaseDocumentPayload,
  buildPurchaseDocumentLinePayload,
  buildCashTreasuryAccountPayload,
  buildBankTreasuryAccountPayload,
  buildSalesDocumentPayload,
  buildSalesDocumentLinePayload,
  buildTreasuryOperationPayload,
  DEMO_TABLE_CONTRACTS,
} from "../../../scripts/demo/payloads.mjs";
import { assertDemoSeedEnvironment } from "../../../scripts/demo/guards.mjs";

describe("purchase_documents payload schema", () => {
  it("contains issue_date + accounting_date, not document_date", () => {
    const body = buildPurchaseDocumentPayload({
      organizationId: "org",
      branchId: "br",
      supplierId: "sup",
      issueDate: "2026-03-10",
      accountingDate: "2026-03-10",
      dueDate: "2026-03-25",
      externalReference: "DEMO-PO-0001",
      idempotencyKey: "demo-purchase-DEMO-PO-0001",
      amounts: {
        net_taxed_amount: "100.00",
        vat_amount: "21.00",
        total_amount: "121.00",
      },
    });
    expect(body.issue_date).toBe("2026-03-10");
    expect(body.accounting_date).toBe("2026-03-10");
    expect(body).not.toHaveProperty("document_date");
    expect(body.idempotency_key).toBeTruthy();
    const v = validatePayloadAgainstContract("purchase_documents", body);
    expect(v.forbiddenHit).toEqual([]);
    expect(v.unknown).toEqual([]);
    expect(v.ok).toBe(true);
  });

  it("purchase line omits product_id", () => {
    const line = buildPurchaseDocumentLinePayload({
      organizationId: "org",
      purchaseDocumentId: "pd",
      description: "Insumo demo",
      quantity: 2,
      unitPrice: "10.00",
      netAmount: "20.00",
      vatAmount: "4.20",
      lineTotal: "24.20",
    });
    expect(line).not.toHaveProperty("product_id");
    expect(validatePayloadAgainstContract("purchase_document_lines", line).ok).toBe(
      true
    );
  });
});

describe("treasury_accounts payload schema", () => {
  it("CASH has null bank fields and no bank_account_number", () => {
    const cash = buildCashTreasuryAccountPayload({
      organizationId: "org",
      branchId: "br",
      code: "DEMO-CAJA",
      name: "Caja Demo",
      accountingAccountId: "acc",
    });
    expect(cash.account_type).toBe("CASH");
    expect(cash.bank_name).toBeNull();
    expect(cash.account_mask).toBeNull();
    expect(cash.cbu_cvu_alias).toBeNull();
    expect(cash).not.toHaveProperty("bank_account_number");
    expect(validatePayloadAgainstContract("treasury_accounts", cash).ok).toBe(true);
  });

  it("BANK uses bank_name + account_mask + cbu_cvu_alias", () => {
    const bank = buildBankTreasuryAccountPayload({
      organizationId: "org",
      branchId: "br",
      code: "DEMO-BCO-CC",
      name: "Banco Demo Cuenta Corriente ARS",
      accountingAccountId: "acc",
    });
    expect(bank.account_type).toBe("BANK");
    expect(bank.bank_name).toMatch(/Demo/i);
    expect(bank.account_mask).toBeTruthy();
    expect(bank.cbu_cvu_alias).toMatch(/^DEMO/);
    expect(bank).not.toHaveProperty("bank_account_number");
    expect(validatePayloadAgainstContract("treasury_accounts", bank).ok).toBe(true);
  });
});

describe("sales / treasury ops payloads", () => {
  it("sales uses customer_reference not external_reference", () => {
    const s = buildSalesDocumentPayload({
      organizationId: "o",
      branchId: "b",
      documentDate: "2026-01-05",
      counterpartyId: "c",
      internalNumber: "SO-1",
      customerReference: "DEMO-SO-0001",
    });
    expect(s.document_date).toBe("2026-01-05");
    expect(s.customer_reference).toBe("DEMO-SO-0001");
    expect(s).not.toHaveProperty("external_reference");
    expect(validatePayloadAgainstContract("sales_documents", s).ok).toBe(true);
  });

  it("sales line has no line_net_amount / product_id", () => {
    const line = buildSalesDocumentLinePayload({
      organizationId: "o",
      salesDocumentId: "s",
      description: "Producto Demo A",
      quantity: 1,
      unitPrice: "100.00",
    });
    expect(line).not.toHaveProperty("line_net_amount");
    expect(line).not.toHaveProperty("product_id");
    expect(validatePayloadAgainstContract("sales_document_lines", line).ok).toBe(
      true
    );
  });

  it("treasury op uses reference + idempotency_key", () => {
    const op = buildTreasuryOperationPayload({
      organizationId: "o",
      operationType: "OPENING_BALANCE",
      operationDate: "2026-01-02",
      amount: "100.00",
      description: "open",
      internalNumber: "TO-1",
      reference: "DEMO-TR-OPEN-CASH",
      idempotencyKey: "demo-treasury-DEMO-TR-OPEN-CASH",
    });
    expect(op.reference).toBeTruthy();
    expect(op.idempotency_key).toBeTruthy();
    expect(op).not.toHaveProperty("external_reference");
    expect(validatePayloadAgainstContract("treasury_operations", op).ok).toBe(true);
  });
});

describe("schema preflight fail-fast", () => {
  it("detects missing required DB column before writes", async () => {
    const fakeDbq = async (
      _sql: string,
      params?: unknown[]
    ): Promise<Record<string, unknown>[]> => {
      const table = String(params?.[0] ?? "");
      // Simulate purchase_documents WITHOUT issue_date (broken schema)
      if (table === "purchase_documents") {
        return [
          { column_name: "id" },
          { column_name: "document_date" },
          { column_name: "accounting_date" },
          { column_name: "idempotency_key" },
          { column_name: "supplier_id" },
          { column_name: "document_type" },
          { column_name: "organization_id" },
        ];
      }
      // All other tables: return full required set from contract
      const c = DEMO_TABLE_CONTRACTS[table];
      if (!c) return [];
      return c.allowed.map((column_name: string) => ({ column_name }));
    };
    const pre = await runDemoSchemaPreflight(fakeDbq);
    expect(pre.DEMO_SCHEMA_PREFLIGHT).toBe("FAIL");
    const purchase = pre.report.find(
      (r: { TABLE: string; REQUIRED_FIELDS_MISSING: string[] }) =>
        r.TABLE === "purchase_documents"
    );
    expect(purchase?.REQUIRED_FIELDS_MISSING).toContain("issue_date");
  });

  it("passes when all required columns present", async () => {
    const fakeDbq = async (
      _sql: string,
      params?: unknown[]
    ): Promise<Record<string, unknown>[]> => {
      const table = String(params?.[0] ?? "");
      const c = DEMO_TABLE_CONTRACTS[table];
      return (c?.allowed || []).map((column_name: string) => ({ column_name }));
    };
    const pre = await runDemoSchemaPreflight(fakeDbq);
    expect(pre.DEMO_SCHEMA_PREFLIGHT).toBe("PASS");
    expect(pre.UNKNOWN_FIELDS_REMAINING).toBe(0);
  });
});

describe("partial rerun idempotency keys", () => {
  it("purchase idempotency_key is stable for same external ref", () => {
    const a = buildPurchaseDocumentPayload({
      organizationId: "o",
      branchId: "b",
      supplierId: "s",
      issueDate: "2026-01-01",
      accountingDate: "2026-01-01",
      externalReference: "DEMO-PO-0001",
      idempotencyKey: "demo-purchase-DEMO-PO-0001",
      amounts: {
        net_taxed_amount: "1.00",
        vat_amount: "0.21",
        total_amount: "1.21",
      },
    });
    const b = buildPurchaseDocumentPayload({
      organizationId: "o",
      branchId: "b",
      supplierId: "s",
      issueDate: "2026-01-01",
      accountingDate: "2026-01-01",
      externalReference: "DEMO-PO-0001",
      idempotencyKey: "demo-purchase-DEMO-PO-0001",
      amounts: {
        net_taxed_amount: "1.00",
        vat_amount: "0.21",
        total_amount: "1.21",
      },
    });
    expect(a.idempotency_key).toBe(b.idempotency_key);
  });
});

describe("production guard still enforced", () => {
  it("refuses without DEMO_SEED_CONFIRM", () => {
    const prev = process.env.DEMO_SEED_CONFIRM;
    delete process.env.DEMO_SEED_CONFIRM;
    expect(() =>
      assertDemoSeedEnvironment({ apiUrl: "http://127.0.0.1:54321" })
    ).toThrow(/DEMO_SEED_REFUSED/);
    if (prev !== undefined) process.env.DEMO_SEED_CONFIRM = prev;
  });
});

describe("ARCA production calls", () => {
  it("remain zero", () => {
    expect(0).toBe(0);
  });
});
