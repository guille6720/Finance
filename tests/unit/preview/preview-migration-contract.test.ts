/**
 * Static contract for the public-preview migration: the rules the Staging database
 * enforces (tester slots, eligibility, idempotent seed through the posting engines)
 * are asserted against the SQL that is actually applied.
 */
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, it, expect } from "vitest";

const sql = readFileSync(
  path.join(process.cwd(), "supabase/migrations/20261401100000_preview_tester_slots_and_demo_seed.sql"),
  "utf8"
);
const code = sql
  .split("\n")
  .filter((l) => !l.trim().startsWith("--"))
  .join("\n");

function fn(name: string) {
  const start = code.indexOf(`create or replace function public.${name}(`);
  expect(start, name).toBeGreaterThanOrEqual(0);
  const end = code.indexOf("$function$;", start);
  return code.slice(start, end > 0 ? end : undefined);
}

const trigger = fn("staging_reserve_tester_and_seed");
const seed = fn("seed_preview_demo_data");

function valuesRows(block: string, marker: string) {
  const start = block.indexOf(marker);
  const end = block.indexOf(") as x(", start);
  return block.slice(start, end);
}

describe("tester slots", () => {
  it("reconciles the table without duplicating it: one slot per user and per organization, slots 1..5", () => {
    expect(code).toContain("create table if not exists public.staging_tester_slots");
    expect(code).toMatch(/slot_no smallint primary key check \(slot_no >= 1 and slot_no <= 5\)/);
    expect(code).toMatch(/user_id uuid not null unique/);
    expect(code).toMatch(/organization_id uuid not null unique/);
    expect(code).not.toMatch(/create table public\.staging_tester_slots/);
  });

  it("allocates the lowest free slot under an advisory lock (slot 1 first, concurrency-safe)", () => {
    expect(trigger).toContain("pg_advisory_xact_lock(hashtext('finance_staging_public_tester_slots_v1'))");
    expect(trigger).toMatch(/generate_series\(1, v_settings\.max_testers\)[\s\S]*order by gs\s+limit 1/);
    expect(code).toMatch(/max_testers smallint not null default 5 check \(max_testers >= 1 and max_testers <= 5\)/);
  });

  it("the sixth tester is rejected with a coded error that the app translates", () => {
    expect(trigger).toMatch(/if v_slot is null then\s+raise exception using\s+errcode = 'P0001',\s+message = 'STAGING_TESTER_LIMIT_REACHED'/);
  });

  it("a retry by a user who already holds a slot never consumes another one", () => {
    const lock = trigger.indexOf("pg_advisory_xact_lock");
    const reuse = trigger.indexOf("where s.user_id = new.created_by");
    const allocate = trigger.indexOf("generate_series");
    expect(lock).toBeLessThan(reuse);
    expect(reuse).toBeLessThan(allocate);
  });

  it("is inert unless enabled, and exempts internal/demo accounts and pre-existing users", () => {
    expect(trigger).toMatch(/if not found or not v_settings\.enabled or new\.created_by is null then\s+return new;/);
    expect(trigger).toContain("v_user_created_at < v_settings.enabled_since");
    expect(trigger).toContain("= any (v_settings.exempt_email_domains)");
    expect(code).toContain("default array['example.invalid']::text[]");
    expect(code).not.toMatch(/insert into public\.preview_demo_settings/);
  });

  it("slot and settings tables are closed to clients", () => {
    expect(code).toContain("revoke all on table public.staging_tester_slots from public, anon, authenticated;");
    expect(code).toContain("revoke all on table public.preview_demo_settings from public, anon, authenticated;");
    expect(code).toContain("alter table public.staging_tester_slots enable row level security;");
  });
});

describe("demo seed", () => {
  it("runs as the caller (RLS applies) and only for eligible tester organizations", () => {
    expect(seed).toMatch(/security invoker/);
    expect(seed).toContain("if not public.preview_demo_org_eligible(v_org) then");
    const eligible = code.slice(code.indexOf("function public.preview_demo_org_eligible"));
    expect(eligible).toContain("public.preview_demo_enabled()");
    expect(eligible).toContain("public.staging_tester_slots s where s.organization_id = p_organization_id");
    expect(eligible).toContain("os.key = 'demo.is_demo'");
    expect(eligible).toContain("array['owner']::public.member_role[]");
    expect(code).toContain("revoke all on function public.seed_preview_demo_data(uuid) from public, anon;");
  });

  it("writes only in the requested organization", () => {
    const inserts = seed.match(/insert into public\.\w+ \([^)]*\)\s*values\s*\(\s*\w+/g) ?? [];
    expect(inserts.length).toBeGreaterThanOrEqual(10);
    for (const ins of inserts) {
      expect(ins, ins).toMatch(/organization_id|counterparty_id/);
      expect(ins, ins).toMatch(/\(\s*(v_org|v_id)$/);
    }
    expect(seed).not.toMatch(/\bdelete from\b|\btruncate\b|\bdrop\b/i);
  });

  it("never writes POSTED rows directly: every document goes through its engine", () => {
    for (const engine of [
      "public.mark_purchase_reviewed(v_id)",
      "public.post_purchase_document(v_id)",
      "public.post_treasury_operation(v_id)",
      "public.next_treasury_operation_number(",
      "public.next_sales_internal_number(",
      "public.confirm_sales_order(v_id)",
      "public.mark_order_ready_to_invoice(v_id)",
      "public.ensure_tax_period(v_org, 'IVA', null, 2026, v_month, 'HOMOLOGATION')",
    ]) {
      expect(seed).toContain(engine);
    }
    expect(seed).not.toMatch(/'POSTED',\s*\w/);
    expect(seed).not.toMatch(/fiscal_documents|cae|arca/i);
  });

  it("uses the deterministic idempotency keys", () => {
    for (const key of [
      "staging-demo-opening-cash",
      "staging-demo-collection-001",
      "staging-demo-payment-001",
      "staging-demo-transfer-001",
      "staging-demo-purchase-001",
      "staging-demo-purchase-002",
      "staging-demo-sale-001",
      "staging-demo-sale-002",
      "staging-demo-sale-003",
    ]) {
      expect(seed).toContain(`'${key}'`);
    }
    expect(seed).toContain("where o.organization_id = v_org and o.idempotency_key = v_row.idem");
    expect(seed).toContain("where d.organization_id = v_org and d.idempotency_key = v_row.idem");
    expect(seed).toContain("d.customer_reference = v_row.ref");
    expect(seed).toContain("continue when v_id is not null and v_status <> 'DRAFT'");
  });

  it("creates 5 synthetic customers, 5 suppliers, 3 stock items and 2 services (no tax ids)", () => {
    const cps = valuesRows(seed, "('DEMO-CUST-001'");
    expect(cps.match(/'CUSTOMER'/g)).toHaveLength(5);
    expect(cps.match(/'SUPPLIER'/g)).toHaveLength(5);
    expect(seed).toContain("'LEGAL_ENTITY', v_row.legal_name, v_row.legal_name, 'NONE'");
    const products = valuesRows(seed, "('DEMO-PRD-001'");
    expect(products.match(/'STOCK_ITEM'/g)).toHaveLength(3);
    expect(products.match(/'SERVICE'/g)).toHaveLength(2);
  });

  it("treasury leaves cash at 163.000 and the bank at 30.000", () => {
    const ops = valuesRows(seed, "('staging-demo-opening-cash'");
    const amount = (key: string) => {
      const m = new RegExp(`'${key}', '(\\w+)', date '[\\d-]+', (\\d+)::numeric`).exec(ops);
      expect(m, key).not.toBeNull();
      return { type: m![1], amount: Number(m![2]) };
    };
    const opening = amount("staging-demo-opening-cash");
    const collection = amount("staging-demo-collection-001");
    const payment = amount("staging-demo-payment-001");
    const transfer = amount("staging-demo-transfer-001");
    expect([opening, collection, payment, transfer].map((o) => o.type)).toEqual([
      "OPENING_BALANCE",
      "ADJUSTMENT",
      "PAYMENT",
      "TRANSFER",
    ]);
    expect(opening.amount + collection.amount - payment.amount - transfer.amount).toBe(163000);
    expect(transfer.amount).toBe(30000);
    expect(seed).toMatch(/\(v_org, v_id, v_cash_ta, 'OUTFLOW', v_row\.amount, 1\),\s*\(v_org, v_id, v_bank_ta, 'INFLOW', v_row\.amount, 2\)/);
  });

  it("sales orders total 120.000, 95.000 and 145.000 on different dates", () => {
    const rows = valuesRows(seed, "('staging-demo-sale-001'");
    const re = /'(staging-demo-sale-\d{3})', \d, date '([\d-]+)', '[^']+', '\w+',\s*(\d+)::numeric, (\d+)::numeric, '(\w+)'/g;
    const sales = [...rows.matchAll(re)].map((m) => ({ date: m[2], total: Number(m[3]) * Number(m[4]), target: m[5] }));
    expect(sales.map((s) => s.total)).toEqual([120000, 95000, 145000]);
    expect(new Set(sales.map((s) => s.date)).size).toBe(3);
    expect(sales.map((s) => s.target)).toEqual(["CONFIRMED", "READY_TO_INVOICE", "READY_TO_INVOICE"]);
  });

  it("purchases are 60.000 + 12.600 and 80.000 + 16.800, and accounting stays balanced", () => {
    const rows = valuesRows(seed, "('staging-demo-purchase-001'");
    const purchases = [...rows.matchAll(/(\d+)::numeric, (\d+)::numeric/g)].map((m) => ({
      net: Number(m[1]),
      vat: Number(m[2]),
    }));
    expect(purchases).toEqual([
      { net: 60000, vat: 12600 },
      { net: 80000, vat: 16800 },
    ]);
    expect(purchases.map((p) => p.net + p.vat)).toEqual([72600, 96800]);

    // Engine journal lines: every operation posts equal debit and credit.
    const entries = [
      { debit: 150000, credit: 150000 },
      { debit: 85000, credit: 85000 },
      { debit: 42000, credit: 42000 },
      { debit: 30000, credit: 30000 },
      ...purchases.map((p) => ({ debit: p.net + p.vat, credit: p.net + p.vat })),
    ];
    const debit = entries.reduce((a, e) => a + e.debit, 0);
    const credit = entries.reduce((a, e) => a + e.credit, 0);
    expect(debit).toBe(credit);
    expect(debit).toBe(476400);
  });

  it("the payment settles part of the first demo purchase, same supplier", () => {
    expect(seed).toContain("ap.purchase_document_id = v_purchases[1]");
    expect(seed).toContain("when 'PAYMENT' then v_suppliers[1]");
    expect(seed).toMatch(/\('staging-demo-purchase-001', 1,/);
  });
});

describe("migration safety", () => {
  it("contains no destructive statements and does not touch Phase 13 objects", () => {
    expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|policy)\b/i);
    expect(code).not.toMatch(/\btruncate\b/i);
    expect(code).not.toMatch(/\bdelete\s+from\b/i);
    expect(code).not.toMatch(/phase13|disable row level security/i);
  });
});
