/**
 * Demo-module rows on top of demoDb(): ORG_A = Empresa Demo, ORG_B = Demo Beta,
 * ORG_C = a foreign/personal tenant. Includes deliberate traps (quotes, drafts,
 * reversed ops, BANK/CLEARING legs, unbalanced DRAFT entry, foreign rows).
 */
import { demoDb, ORG_A, ORG_B, ORG_C, type FakeDb } from "./fake-supabase";

const ts = (d: string) => `${d}T12:00:00.000Z`;

export function demoModulesDb(): FakeDb {
  const db = demoDb();

  db.counterparties = [
    { id: "cp-a-alfa", organization_id: ORG_A, legal_name: "CLIENTE ALFA SA", trade_name: "Alfa Comercial", tax_id: "30-71111111-1", email: "alfa@example.invalid", phone: "11-4000-0001", is_active: true },
    { id: "cp-a-inactivo", organization_id: ORG_A, legal_name: "CLIENTE DORMIDO SRL", trade_name: null, tax_id: "30-72222222-2", email: null, phone: null, is_active: false },
    { id: "cp-a-mixto", organization_id: ORG_A, legal_name: "MIXTO SA", trade_name: null, tax_id: "30-73333333-3", email: "mixto@example.invalid", phone: null, is_active: true },
    { id: "cp-a-gamma", organization_id: ORG_A, legal_name: "PROVEEDOR GAMMA SRL", trade_name: null, tax_id: "30-74444444-4", email: "gamma@example.invalid", phone: "11-4000-0004", is_active: true },
    { id: "cp-b-solo", organization_id: ORG_B, legal_name: "CLIENTE SOLO BETA SRL", trade_name: null, tax_id: "30-75555555-5", email: "beta.cliente@example.invalid", phone: null, is_active: true },
    { id: "cp-b-prov", organization_id: ORG_B, legal_name: "PROVEEDOR BETA SA", trade_name: null, tax_id: "30-76666666-6", email: null, phone: null, is_active: true },
    { id: "cp-c-ajeno", organization_id: ORG_C, legal_name: "CLIENTE AJENO SA", trade_name: null, tax_id: "30-79999999-9", email: "ajeno@example.invalid", phone: null, is_active: true },
  ];

  db.counterparty_roles = [
    { id: "r1", organization_id: ORG_A, counterparty_id: "cp-a-alfa", role: "CUSTOMER" },
    { id: "r2", organization_id: ORG_A, counterparty_id: "cp-a-inactivo", role: "CUSTOMER" },
    { id: "r3", organization_id: ORG_A, counterparty_id: "cp-a-mixto", role: "CUSTOMER" },
    { id: "r4", organization_id: ORG_A, counterparty_id: "cp-a-mixto", role: "SUPPLIER" },
    { id: "r5", organization_id: ORG_A, counterparty_id: "cp-a-gamma", role: "SUPPLIER" },
    { id: "r6", organization_id: ORG_B, counterparty_id: "cp-b-solo", role: "CUSTOMER" },
    { id: "r7", organization_id: ORG_B, counterparty_id: "cp-b-prov", role: "SUPPLIER" },
    { id: "r8", organization_id: ORG_C, counterparty_id: "cp-c-ajeno", role: "CUSTOMER" },
  ];

  db.sales_documents = [
    { id: "s1", organization_id: ORG_A, document_type: "SALES_ORDER", status: "CONFIRMED", counterparty_id: "cp-a-alfa", total: "1000.5000" },
    { id: "s2", organization_id: ORG_A, document_type: "QUOTE", status: "CONVERTED", counterparty_id: "cp-a-alfa", total: "1000.5000" },
    { id: "s3", organization_id: ORG_A, document_type: "SALES_ORDER", status: "DRAFT", counterparty_id: "cp-a-mixto", total: "999.0000" },
    { id: "s4", organization_id: ORG_A, document_type: "SALES_ORDER", status: "CANCELLED", counterparty_id: "cp-a-mixto", total: "321.0000" },
    { id: "s5", organization_id: ORG_A, document_type: "SALES_ORDER", status: "READY_TO_INVOICE", counterparty_id: "cp-a-alfa", total: "2000.0000" },
    { id: "s-c", organization_id: ORG_C, document_type: "SALES_ORDER", status: "CONFIRMED", counterparty_id: "cp-c-ajeno", total: "777777.0000" },
  ];

  db.purchase_documents = [
    { id: "p1", organization_id: ORG_A, document_type: "SUPPLIER_INVOICE", status: "POSTED", supplier_id: "cp-a-gamma", total_amount: "500.2500" },
    { id: "p2", organization_id: ORG_A, document_type: "SUPPLIER_CREDIT_NOTE", status: "POSTED", supplier_id: "cp-a-gamma", total_amount: "100.0000" },
    { id: "p3", organization_id: ORG_A, document_type: "SUPPLIER_INVOICE", status: "DRAFT", supplier_id: "cp-a-mixto", total_amount: "50.0000" },
    { id: "p4", organization_id: ORG_A, document_type: "SUPPLIER_INVOICE", status: "REVERSED", supplier_id: "cp-a-gamma", total_amount: "9999.0000" },
    { id: "p-c", organization_id: ORG_C, document_type: "SUPPLIER_INVOICE", status: "POSTED", supplier_id: "cp-c-ajeno", total_amount: "888888.0000" },
  ];

  db.treasury_accounts = [
    { id: "ta-a-cash", organization_id: ORG_A, account_type: "CASH", code: "CAJA-01", name: "Caja principal", currency_code: "ARS", is_active: true },
    { id: "ta-a-bank", organization_id: ORG_A, account_type: "BANK", code: "BCO-01", name: "Banco Galicia CC", currency_code: "ARS", is_active: true },
    { id: "ta-a-clear", organization_id: ORG_A, account_type: "CLEARING", code: "CLR-01", name: "Valores a depositar", currency_code: "ARS", is_active: true },
    { id: "ta-c-cash", organization_id: ORG_C, account_type: "CASH", code: "CAJA-X", name: "Caja ajena", currency_code: "ARS", is_active: true },
  ];

  db.treasury_operations = [
    { id: "op1", organization_id: ORG_A, internal_number: "TR-0001", operation_type: "OPENING_BALANCE", status: "POSTED", operation_date: "2026-01-02", amount: "150000.0000", description: "Apertura caja principal", created_at: ts("2026-01-02") },
    { id: "op2", organization_id: ORG_A, internal_number: "TR-0002", operation_type: "PAYMENT", status: "POSTED", operation_date: "2026-01-05", amount: "2500.0000", description: "Pago en efectivo librería", created_at: ts("2026-01-05") },
    { id: "op3", organization_id: ORG_A, internal_number: "TR-0003", operation_type: "COLLECTION", status: "REVERSED", operation_date: "2026-01-06", amount: "999.0000", description: "Cobranza revertida", created_at: ts("2026-01-06") },
    { id: "op4", organization_id: ORG_A, internal_number: "TR-0004", operation_type: "OPENING_BALANCE", status: "POSTED", operation_date: "2026-01-02", amount: "1070000.0000", description: "Apertura cuenta bancaria", created_at: ts("2026-01-02") },
    { id: "op5", organization_id: ORG_A, internal_number: "TR-0005", operation_type: "TRANSFER", status: "POSTED", operation_date: "2026-01-07", amount: "50000.0000", description: "Transferencia a valores", created_at: ts("2026-01-07") },
    { id: "op6", organization_id: ORG_A, internal_number: "TR-0006", operation_type: "ADJUSTMENT", status: "DRAFT", operation_date: "2026-01-08", amount: "10.0000", description: "Ajuste en borrador", created_at: ts("2026-01-08") },
    { id: "op-c", organization_id: ORG_C, internal_number: "TR-9999", operation_type: "OPENING_BALANCE", status: "POSTED", operation_date: "2026-01-02", amount: "555555.0000", description: "Apertura caja ajena", created_at: ts("2026-01-02") },
  ];

  db.treasury_operation_legs = [
    { id: "l1", organization_id: ORG_A, treasury_operation_id: "op1", treasury_account_id: "ta-a-cash", direction: "INFLOW", amount: "150000.0000", line_number: 1 },
    { id: "l2", organization_id: ORG_A, treasury_operation_id: "op2", treasury_account_id: "ta-a-cash", direction: "OUTFLOW", amount: "2500.0000", line_number: 1 },
    { id: "l3", organization_id: ORG_A, treasury_operation_id: "op3", treasury_account_id: "ta-a-cash", direction: "INFLOW", amount: "999.0000", line_number: 1 },
    { id: "l4", organization_id: ORG_A, treasury_operation_id: "op4", treasury_account_id: "ta-a-bank", direction: "INFLOW", amount: "1070000.0000", line_number: 1 },
    { id: "l5", organization_id: ORG_A, treasury_operation_id: "op5", treasury_account_id: "ta-a-bank", direction: "OUTFLOW", amount: "50000.0000", line_number: 1 },
    { id: "l6", organization_id: ORG_A, treasury_operation_id: "op5", treasury_account_id: "ta-a-clear", direction: "INFLOW", amount: "50000.0000", line_number: 2 },
    { id: "l7", organization_id: ORG_A, treasury_operation_id: "op6", treasury_account_id: "ta-a-cash", direction: "INFLOW", amount: "10.0000", line_number: 1 },
    { id: "l-c", organization_id: ORG_C, treasury_operation_id: "op-c", treasury_account_id: "ta-c-cash", direction: "INFLOW", amount: "555555.0000", line_number: 1 },
  ];

  db.journal_entries = [
    { id: "je1", organization_id: ORG_A, entry_number: "A-0001", entry_date: "2026-01-02", description: "Asiento de apertura", status: "POSTED", source_type: "SYSTEM", external_reference: null, reversal_of_entry_id: null, posted_at: ts("2026-01-02") },
    { id: "je2", organization_id: ORG_A, entry_number: "A-0002", entry_date: "2026-01-03", description: "Compra a revertir", status: "REVERSED", source_type: "PURCHASE", external_reference: null, reversal_of_entry_id: null, posted_at: ts("2026-01-03") },
    { id: "je3", organization_id: ORG_A, entry_number: "A-0003", entry_date: "2026-01-04", description: "Reversión de compra", status: "POSTED", source_type: "PURCHASE", external_reference: null, reversal_of_entry_id: "je2", posted_at: ts("2026-01-04") },
    { id: "je4", organization_id: ORG_A, entry_number: null, entry_date: "2026-01-05", description: "Borrador desbalanceado", status: "DRAFT", source_type: "MANUAL", external_reference: null, reversal_of_entry_id: null, posted_at: null },
    { id: "je-c", organization_id: ORG_C, entry_number: "X-0001", entry_date: "2026-01-02", description: "Asiento ajeno", status: "POSTED", source_type: "MANUAL", external_reference: null, reversal_of_entry_id: null, posted_at: ts("2026-01-02") },
  ];

  db.journal_entry_lines = [
    { id: "jl1", organization_id: ORG_A, journal_entry_id: "je1", account_id: "acc1", debit: "1000.1000", credit: "0", line_number: 1 },
    { id: "jl2", organization_id: ORG_A, journal_entry_id: "je1", account_id: "acc2", debit: "0", credit: "1000.1000", line_number: 2 },
    { id: "jl3", organization_id: ORG_A, journal_entry_id: "je2", account_id: "acc1", debit: "200.2000", credit: "0", line_number: 1 },
    { id: "jl4", organization_id: ORG_A, journal_entry_id: "je2", account_id: "acc2", debit: "0", credit: "200.2000", line_number: 2 },
    { id: "jl5", organization_id: ORG_A, journal_entry_id: "je3", account_id: "acc2", debit: "200.2000", credit: "0", line_number: 1 },
    { id: "jl6", organization_id: ORG_A, journal_entry_id: "je3", account_id: "acc1", debit: "0", credit: "200.2000", line_number: 2 },
    { id: "jl7", organization_id: ORG_A, journal_entry_id: "je4", account_id: "acc1", debit: "5000.0000", credit: "0", line_number: 1 },
    { id: "jl-c1", organization_id: ORG_C, journal_entry_id: "je-c", account_id: "acc-c", debit: "123456.0000", credit: "0", line_number: 1 },
    { id: "jl-c2", organization_id: ORG_C, journal_entry_id: "je-c", account_id: "acc-c", debit: "0", credit: "123456.0000", line_number: 2 },
  ];

  db.accounts = [];

  db.tax_periods = [
    { id: "tp1", organization_id: ORG_A, tax_code: "IVA", jurisdiction_code: null, period_year: 2026, period_month: 1, status: "OPEN" },
    { id: "tp2", organization_id: ORG_A, tax_code: "IVA", jurisdiction_code: null, period_year: 2026, period_month: 2, status: "REVIEWED" },
    { id: "tp3", organization_id: ORG_A, tax_code: "IVA", jurisdiction_code: null, period_year: 2026, period_month: 3, status: "CLOSED" },
    { id: "tp0", organization_id: ORG_A, tax_code: "IVA", jurisdiction_code: null, period_year: 2025, period_month: 12, status: "OPEN" },
    { id: "tp-c", organization_id: ORG_C, tax_code: "GANANCIAS", jurisdiction_code: null, period_year: 2026, period_month: 9, status: "IN_REVIEW" },
  ];

  return db;
}

/** Strings that must never render outside their own tenant. */
export const EMPRESA_DEMO_MARKERS = [
  "Alfa Comercial",
  "PROVEEDOR GAMMA SRL",
  "MIXTO SA",
  "Caja principal",
  "Apertura caja principal",
  "Asiento de apertura",
  "Reversión de compra",
];
export const FOREIGN_MARKERS = [
  "CLIENTE AJENO SA",
  "Caja ajena",
  "Apertura caja ajena",
  "Asiento ajeno",
  "Ganancias",
  "777.777",
  "888.888",
  "555.555",
  "123.456",
];
export const BETA_MARKERS = ["CLIENTE SOLO BETA SRL", "PROVEEDOR BETA SA"];

export { ORG_A, ORG_B, ORG_C };
