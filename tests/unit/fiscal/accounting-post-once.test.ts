/**
 * Unit / integration-style tests for fiscal accounting post exactly once.
 * Uses deterministic fixtures — NO live ARCA (no WSAA/WSFE).
 */
import { describe, it, expect } from "vitest";
import {
  decideFiscalAccountingPost,
  accountingSourceKey,
  FiscalAccountingPostOnceSimulator,
  postFiscalDocumentAccountingOnce,
  ARCA_AUTHORIZED_EVENT,
} from "@/lib/fiscal/accounting/post-once";

describe("decideFiscalAccountingPost — state matrix", () => {
  it("AUTHORIZED → POST ONCE allowed", () => {
    expect(decideFiscalAccountingPost("AUTHORIZED")).toEqual({
      allow: true,
      reason: "AUTHORIZED",
    });
  });

  it("AUTHORIZED_RECONCILED → POST ONCE allowed", () => {
    expect(decideFiscalAccountingPost("AUTHORIZED_RECONCILED")).toEqual({
      allow: true,
      reason: "AUTHORIZED_RECONCILED",
    });
  });

  it.each([
    "REJECTED",
    "RECONCILIATION_REQUIRED",
    "UNCERTAIN_STOP",
    "AUTHORIZING",
    "DRAFT",
    "READY",
    "READY_TO_AUTHORIZE",
    "ERROR",
    "STOP_TRANSPORT",
  ] as const)("%s → NO POST", (state) => {
    const d = decideFiscalAccountingPost(state);
    expect(d.allow).toBe(false);
  });
});

describe("accountingSourceKey", () => {
  it("builds org + fiscal + ARCA_AUTHORIZED", () => {
    expect(accountingSourceKey("org-1", "fd-1")).toBe(
      `org-1:fd-1:${ARCA_AUTHORIZED_EVENT}`
    );
  });
});

describe("FiscalAccountingPostOnceSimulator", () => {
  function authDoc(id: string, status: string = "AUTHORIZED") {
    return {
      id,
      organizationId: "org-1",
      status,
      accountingStatus: "PENDING" as const,
      journalEntryId: null,
      accountingPostedAt: null,
      totalAmount: 1210,
      netAmount: 1000,
      vatAmount: 210,
    };
  }

  it("AUTHORIZED_ACCOUNTING_POST", async () => {
    const sim = new FiscalAccountingPostOnceSimulator();
    sim.seedDoc(authDoc("fd-a"));
    const r = await sim.post("fd-a");
    expect(r.created).toBe(true);
    expect(sim.journalCountForFiscal("fd-a")).toBe(1);
    expect(sim.getDoc("fd-a")?.accountingStatus).toBe("POSTED");
  });

  it("AUTHORIZED_RECONCILED_ACCOUNTING_POST", async () => {
    const sim = new FiscalAccountingPostOnceSimulator();
    sim.seedDoc(authDoc("fd-r", "AUTHORIZED_RECONCILED"));
    const r = await sim.post("fd-r");
    expect(r.created).toBe(true);
    expect(sim.journalCountForFiscal("fd-r")).toBe(1);
  });

  it("REJECTED_ACCOUNTING_BLOCK", async () => {
    const sim = new FiscalAccountingPostOnceSimulator();
    sim.seedDoc(authDoc("fd-rej", "REJECTED"));
    await expect(sim.post("fd-rej")).rejects.toThrow(/ACCOUNTING_POST_BLOCKED/);
    expect(sim.journalCountForFiscal("fd-rej")).toBe(0);
  });

  it("UNCERTAIN_ACCOUNTING_BLOCK", async () => {
    const sim = new FiscalAccountingPostOnceSimulator();
    sim.seedDoc(authDoc("fd-u", "UNCERTAIN_STOP"));
    await expect(sim.post("fd-u")).rejects.toThrow(/ACCOUNTING_POST_BLOCKED/);
    expect(sim.journalCountForFiscal("fd-u")).toBe(0);

    sim.seedDoc(authDoc("fd-rr", "RECONCILIATION_REQUIRED"));
    await expect(sim.post("fd-rr")).rejects.toThrow(/ACCOUNTING_POST_BLOCKED/);
    expect(sim.journalCountForFiscal("fd-rr")).toBe(0);
  });

  it("IDEMPOTENCY — same journal on double process", async () => {
    const sim = new FiscalAccountingPostOnceSimulator();
    sim.seedDoc(authDoc("fd-id"));
    const a = await sim.post("fd-id");
    const b = await sim.post("fd-id");
    expect(a.journalId).toBe(b.journalId);
    expect(b.created).toBe(false);
    expect(sim.journalCountForFiscal("fd-id")).toBe(1);
  });

  it("AUTHORIZED_RECONCILED processed twice → same journal", async () => {
    const sim = new FiscalAccountingPostOnceSimulator();
    sim.seedDoc(authDoc("fd-id2", "AUTHORIZED_RECONCILED"));
    const a = await sim.post("fd-id2");
    const b = await sim.post("fd-id2");
    expect(a.journalId).toBe(b.journalId);
    expect(sim.journalCountForFiscal("fd-id2")).toBe(1);
  });

  it("CONCURRENT_DOUBLE_POST_PROTECTION", async () => {
    const sim = new FiscalAccountingPostOnceSimulator();
    sim.seedDoc(authDoc("fd-c"));
    const [w1, w2] = await Promise.all([sim.post("fd-c"), sim.post("fd-c")]);
    expect(w1.journalId).toBe(w2.journalId);
    expect(sim.journalCountForFiscal("fd-c")).toBe(1);
    expect([w1.created, w2.created].filter(Boolean)).toHaveLength(1);
  });

  it("TRANSACTION_ATOMICITY — abort before commit leaves no journal", async () => {
    const sim = new FiscalAccountingPostOnceSimulator();
    sim.seedDoc(authDoc("fd-tx"));
    sim.armFailBeforeCommit("fd-tx");
    await expect(sim.post("fd-tx")).rejects.toThrow(/SIMULATED_TX_ABORT/);
    expect(sim.journalCountForFiscal("fd-tx")).toBe(0);
    expect(sim.getDoc("fd-tx")?.accountingStatus).toBe("PENDING");
    // Retry succeeds once
    const r = await sim.post("fd-tx");
    expect(r.created).toBe(true);
    expect(sim.journalCountForFiscal("fd-tx")).toBe(1);
  });

  it("response lost → retry resolves existing journal", async () => {
    const sim = new FiscalAccountingPostOnceSimulator();
    sim.seedDoc(authDoc("fd-lost"));
    const first = await sim.post("fd-lost");
    // Caller lost response; retry
    const retry = await sim.post("fd-lost");
    expect(retry.journalId).toBe(first.journalId);
    expect(retry.created).toBe(false);
    expect(sim.journalCountForFiscal("fd-lost")).toBe(1);
  });

  it("POSTED_ENTRY_IMMUTABILITY", async () => {
    const sim = new FiscalAccountingPostOnceSimulator();
    sim.seedDoc(authDoc("fd-im"));
    const { journalId } = await sim.post("fd-im");
    expect(() => sim.tryMutatePosted(journalId, 9999)).toThrow(/immutable/);
  });

  it("REVERSAL_SEMANTICS — original + reversal net to zero", async () => {
    const sim = new FiscalAccountingPostOnceSimulator();
    sim.seedDoc(authDoc("fd-rev"));
    const { journalId } = await sim.post("fd-rev");
    sim.reverse(journalId);
    expect(sim.economicNetForFiscal("fd-rev")).toBe(0);
    // Both original (REVERSED) and reversing POSTED remain in economic scope
    expect(sim.getJournal(journalId)?.status).toBe("REVERSED");
  });

  it("reconciled after uncertain → one journal", async () => {
    const sim = new FiscalAccountingPostOnceSimulator();
    sim.seedDoc(authDoc("fd-path", "RECONCILIATION_REQUIRED"));
    await expect(sim.post("fd-path")).rejects.toThrow(/BLOCKED/);
    expect(sim.journalCountForFiscal("fd-path")).toBe(0);
    // After FECompConsultar reconcile
    sim.seedDoc({
      ...authDoc("fd-path", "AUTHORIZED_RECONCILED"),
      accountingStatus: "PENDING",
    });
    const r = await sim.post("fd-path");
    expect(r.created).toBe(true);
    expect(sim.journalCountForFiscal("fd-path")).toBe(1);
  });
});

describe("postFiscalDocumentAccountingOnce orchestration", () => {
  it("blocks before RPC when state is REJECTED", async () => {
    await expect(
      postFiscalDocumentAccountingOnce({
        fiscalDocumentId: "fd-x",
        fiscalState: "REJECTED",
        rpc: async () => ({ data: "should-not-run", error: null }),
      })
    ).rejects.toThrow(/ACCOUNTING_POST_BLOCKED/);
  });

  it("calls RPC when AUTHORIZED", async () => {
    let called = false;
    const r = await postFiscalDocumentAccountingOnce({
      fiscalDocumentId: "fd-y",
      fiscalState: "AUTHORIZED",
      rpc: async (fn, args) => {
        called = true;
        expect(fn).toBe("post_fiscal_document_accounting");
        expect(args.p_fiscal_document_id).toBe("fd-y");
        return { data: "je-uuid", error: null };
      },
    });
    expect(called).toBe(true);
    expect(r.journalEntryId).toBe("je-uuid");
  });
});
