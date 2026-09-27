/**
 * DEMO-TR-FEE-1: ADJUSTMENT reason contract and idempotent DRAFT recovery.
 * Domain rule (post_treasury_operation): ADJUSTMENT requires
 * treasury_operations.reason with char_length(trim(reason)) >= 3.
 */
import { describe, it, expect } from "vitest";
import {
  buildTreasuryOperationPayload,
  planTreasuryOperation,
  treasuryReasonSatisfiesDomain,
  validatePayloadAgainstContract,
  TREASURY_ADJUSTMENT_REASON_MIN_LENGTH,
} from "../../../scripts/demo/payloads.mjs";
import { DEMO_TREASURY_ADJUSTMENTS } from "../../../scripts/demo/fixtures.mjs";
import { createSeedCounters, entitiesCreatedThisRun } from "../../../scripts/demo/counters.mjs";
import { assertDemoSeedEnvironment } from "../../../scripts/demo/guards.mjs";

const FEE = DEMO_TREASURY_ADJUSTMENTS.find((a) => a.ref === "DEMO-TR-FEE-1")!;

function feePayload(reason: string | null | undefined = FEE.reason) {
  return buildTreasuryOperationPayload({
    organizationId: "org",
    operationType: FEE.type,
    operationDate: FEE.date,
    amount: "2500.00",
    description: `Demo treasury ${FEE.ref}`,
    internalNumber: "TA-2026-000001",
    reference: FEE.ref,
    idempotencyKey: `demo-treasury-${FEE.ref}`,
    reason,
  });
}

type Op = { id: string; status: string; operation_type: string; reason: string | null; posts: number };

/** In-memory model of the seed loop for one operation (mirrors seedTreasury). */
function runSeedOnce(store: Map<string, Op>, counters: ReturnType<typeof createSeedCounters>) {
  const key = `demo-treasury-${FEE.ref}`;
  const existing = store.get(key);
  const plan = planTreasuryOperation(existing, FEE);
  const post = (op: Op) => {
    if (op.status !== "DRAFT") throw new Error("only DRAFT operations can be posted");
    if (!treasuryReasonSatisfiesDomain(op.operation_type, op.reason)) {
      throw new Error("adjustment reason is required");
    }
    op.status = "POSTED";
    op.posts += 1;
    counters.record("TREASURY_OPERATIONS", "posted");
    counters.record("JOURNAL_ENTRIES", "created");
  };
  if (plan.action === "reuse") {
    counters.record("TREASURY_OPERATIONS", "reused");
    return;
  }
  if (plan.action === "complete_draft") {
    counters.record("TREASURY_OPERATIONS", "reused");
    if (plan.patch) existing!.reason = plan.patch.reason;
    post(existing!);
    return;
  }
  const body = feePayload();
  const op: Op = {
    id: "new",
    status: "DRAFT",
    operation_type: String(body.operation_type),
    reason: (body.reason as string) ?? null,
    posts: 0,
  };
  store.set(key, op);
  counters.record("TREASURY_OPERATIONS", "created");
  post(op);
}

describe("DEMO-TR-FEE-1 adjustment reason", () => {
  it("fixture remains an ADJUSTMENT fee scenario with a valid synthetic reason", () => {
    expect(FEE.type).toBe("ADJUSTMENT");
    expect(FEE.dir).toBe("OUTFLOW");
    expect(FEE.reason.trim().length).toBeGreaterThanOrEqual(TREASURY_ADJUSTMENT_REASON_MIN_LENGTH);
    expect(FEE.reason).toMatch(/demo/i);
    expect(FEE.reason).toMatch(/sintetico/i);
  });

  it("payload carries `reason` and matches the treasury_operations contract", () => {
    const body = feePayload();
    expect(body.reason).toBe(FEE.reason);
    expect(body.status).toBe("DRAFT");
    expect(body.operation_type).toBe("ADJUSTMENT");
    expect(body).not.toHaveProperty("adjustment_reason");
    expect(validatePayloadAgainstContract("treasury_operations", body).ok).toBe(true);
  });

  it("builder refuses an ADJUSTMENT without a domain-valid reason (rule not weakened)", () => {
    expect(() => feePayload(null)).toThrow(/requires reason/);
    expect(() => feePayload("  ")).toThrow(/requires reason/);
    expect(() => feePayload("ab")).toThrow(/requires reason/);
    expect(treasuryReasonSatisfiesDomain("ADJUSTMENT", " abc ")).toBe(true);
    expect(treasuryReasonSatisfiesDomain("OPENING_BALANCE", null)).toBe(true);
  });
});

describe("DEMO-TR-FEE-1 idempotent recovery", () => {
  it("existing DRAFT without reason is completed (patched + posted), not duplicated", () => {
    const store = new Map<string, Op>([
      [
        `demo-treasury-${FEE.ref}`,
        { id: "draft-1", status: "DRAFT", operation_type: "ADJUSTMENT", reason: null, posts: 0 },
      ],
    ]);
    const c = createSeedCounters();
    runSeedOnce(store, c);
    const op = store.get(`demo-treasury-${FEE.ref}`)!;
    expect(store.size).toBe(1);
    expect(op.id).toBe("draft-1");
    expect(op.reason).toBe(FEE.reason);
    expect(op.status).toBe("POSTED");
    expect(op.posts).toBe(1);
    const snap = c.snapshot();
    expect(snap.TREASURY_OPERATIONS_CREATED_THIS_RUN).toBe(0);
    expect(snap.TREASURY_OPERATIONS_REUSED).toBe(1);
    expect(snap.TREASURY_OPERATIONS_POSTED_THIS_RUN).toBe(1);
  });

  it("DRAFT that already has a valid reason is posted without patching", () => {
    const plan = planTreasuryOperation(
      { status: "DRAFT", operation_type: "ADJUSTMENT", reason: "Motivo previo valido" },
      FEE
    );
    expect(plan).toEqual({ action: "complete_draft", patch: null });
  });

  it("POSTED (or REVERSED) operation is reused and never reposted", () => {
    for (const status of ["POSTED", "REVERSED"]) {
      expect(
        planTreasuryOperation({ status, operation_type: "ADJUSTMENT", reason: FEE.reason }, FEE)
      ).toEqual({ action: "reuse" });
    }
  });

  it("missing operation is created once with the reason", () => {
    expect(planTreasuryOperation(null, FEE)).toEqual({ action: "create" });
  });

  it("second idempotent run creates and posts nothing", () => {
    const store = new Map<string, Op>();
    runSeedOnce(store, createSeedCounters());
    expect(store.get(`demo-treasury-${FEE.ref}`)!.posts).toBe(1);

    const second = createSeedCounters();
    runSeedOnce(store, second);
    const snap = second.snapshot();
    expect(entitiesCreatedThisRun(snap)).toEqual([]);
    expect(snap.TREASURY_OPERATIONS_POSTED_THIS_RUN).toBe(0);
    expect(snap.TREASURY_OPERATIONS_REUSED).toBe(1);
    expect(store.size).toBe(1);
    expect(store.get(`demo-treasury-${FEE.ref}`)!.posts).toBe(1);
  });
});

describe("production guard stays enforced", () => {
  it("refuses non-allow-listed remote and ARCA production targets", () => {
    const prevConfirm = process.env.DEMO_SEED_CONFIRM;
    const prevArca = process.env.ARCA_ENV;
    process.env.DEMO_SEED_CONFIRM = "YES";
    try {
      expect(() =>
        assertDemoSeedEnvironment({ apiUrl: "https://prodprojectref.supabase.co", dbUrl: "" })
      ).toThrow(/DEMO_SEED_REFUSED/);
      process.env.ARCA_ENV = "production";
      expect(() =>
        assertDemoSeedEnvironment({ apiUrl: "http://127.0.0.1:54321", dbUrl: "" })
      ).toThrow(/ARCA\/FISCAL production/);
    } finally {
      if (prevConfirm === undefined) delete process.env.DEMO_SEED_CONFIRM;
      else process.env.DEMO_SEED_CONFIRM = prevConfirm;
      if (prevArca === undefined) delete process.env.ARCA_ENV;
      else process.env.ARCA_ENV = prevArca;
    }
  });
});
