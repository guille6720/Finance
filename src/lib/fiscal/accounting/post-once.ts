/**
 * Fiscal → GL accounting post exactly once.
 * Posts ONLY for AUTHORIZED / AUTHORIZED_RECONCILED application states.
 * Relies on DB unique keys + post_fiscal_document_accounting RPC.
 * No live ARCA calls.
 */

export const ARCA_AUTHORIZED_EVENT = "ARCA_AUTHORIZED" as const;

/** Application-level fiscal states relevant to accounting gates. */
export type FiscalAccountingGateState =
  | "DRAFT"
  | "READY"
  | "READY_TO_AUTHORIZE"
  | "AUTHORIZING"
  | "AUTHORIZED"
  | "AUTHORIZED_RECONCILED"
  | "REJECTED"
  | "RECONCILIATION_REQUIRED"
  | "UNCERTAIN_STOP"
  | "STOP_TRANSPORT"
  | "STOP_AUTH"
  | "STOP_UNKNOWN"
  | "ERROR";

export type AccountingPostDecision =
  | { allow: true; reason: "AUTHORIZED" | "AUTHORIZED_RECONCILED" }
  | { allow: false; reason: string };

const BLOCKED = new Set<string>([
  "DRAFT",
  "READY",
  "READY_TO_AUTHORIZE",
  "AUTHORIZING",
  "REJECTED",
  "RECONCILIATION_REQUIRED",
  "UNCERTAIN_STOP",
  "STOP_TRANSPORT",
  "STOP_AUTH",
  "STOP_UNKNOWN",
  "ERROR",
  "UNCERTAIN",
]);

/**
 * Core rule: accounting may occur ONLY when fiscal state is AUTHORIZED
 * or AUTHORIZED_RECONCILED (app semantic for reconciled CAE).
 */
export function decideFiscalAccountingPost(
  state: FiscalAccountingGateState | string
): AccountingPostDecision {
  const s = String(state).toUpperCase();
  if (s === "AUTHORIZED") {
    return { allow: true, reason: "AUTHORIZED" };
  }
  if (s === "AUTHORIZED_RECONCILED" || s === "RECONCILED_AUTHORIZED") {
    return { allow: true, reason: "AUTHORIZED_RECONCILED" };
  }
  if (BLOCKED.has(s) || s.startsWith("STOP_")) {
    return { allow: false, reason: `blocked:${s}` };
  }
  return { allow: false, reason: `blocked:unknown:${s}` };
}

export function accountingSourceKey(
  organizationId: string,
  fiscalDocumentId: string,
  event: typeof ARCA_AUTHORIZED_EVENT = ARCA_AUTHORIZED_EVENT
): string {
  return `${organizationId}:${fiscalDocumentId}:${event}`;
}

export type SimulatedJournal = {
  id: string;
  organizationId: string;
  fiscalDocumentId: string;
  status: "POSTED" | "REVERSED";
  debit: number;
  credit: number;
  lines: Array<{ account: string; debit: number; credit: number }>;
  reversedById?: string;
  reversalOfId?: string;
};

export type SimulatedFiscalDoc = {
  id: string;
  organizationId: string;
  status: FiscalAccountingGateState | string;
  accountingStatus: "PENDING" | "POSTED" | "NOT_APPLICABLE" | "ERROR";
  journalEntryId: string | null;
  accountingPostedAt: string | null;
  totalAmount: number;
  netAmount: number;
  vatAmount: number;
};

/**
 * Deterministic in-memory engine mirroring DB exactly-once semantics
 * for unit / concurrency / failure tests (no live ARCA, no DB required).
 */
export class FiscalAccountingPostOnceSimulator {
  private journals = new Map<string, SimulatedJournal>();
  private sourceKeys = new Map<string, string>();
  private docs = new Map<string, SimulatedFiscalDoc>();
  private locks = new Map<string, Promise<void>>();
  private failBeforeCommit = new Set<string>();
  private seq = 0;

  seedDoc(doc: SimulatedFiscalDoc): void {
    this.docs.set(doc.id, { ...doc });
  }

  getDoc(id: string): SimulatedFiscalDoc | undefined {
    const d = this.docs.get(id);
    return d ? { ...d } : undefined;
  }

  getJournal(id: string): SimulatedJournal | undefined {
    const j = this.journals.get(id);
    return j ? { ...j, lines: j.lines.map((l) => ({ ...l })) } : undefined;
  }

  journalCountForFiscal(fiscalDocumentId: string): number {
    let n = 0;
    for (const j of this.journals.values()) {
      if (j.fiscalDocumentId === fiscalDocumentId && !j.reversalOfId) n += 1;
    }
    return n;
  }

  /** Simulate DB transaction abort before journal commit. */
  armFailBeforeCommit(fiscalDocumentId: string): void {
    this.failBeforeCommit.add(fiscalDocumentId);
  }

  private async withLock<T>(key: string, fn: () => Promise<T> | T): Promise<T> {
    const prev = this.locks.get(key) ?? Promise.resolve();
    let release!: () => void;
    const gate = new Promise<void>((r) => {
      release = r;
    });
    this.locks.set(
      key,
      prev.then(() => gate)
    );
    await prev;
    try {
      return await fn();
    } finally {
      release();
    }
  }

  async post(fiscalDocumentId: string): Promise<{ journalId: string; created: boolean }> {
    return this.withLock(fiscalDocumentId, () => this.postLocked(fiscalDocumentId));
  }

  private postLocked(fiscalDocumentId: string): {
    journalId: string;
    created: boolean;
  } {
    const doc = this.docs.get(fiscalDocumentId);
    if (!doc) throw new Error("fiscal document not found");

    const decision = decideFiscalAccountingPost(doc.status);
    if (!decision.allow) {
      throw new Error(`ACCOUNTING_POST_BLOCKED:${decision.reason}`);
    }

    const key = accountingSourceKey(doc.organizationId, doc.id);
    const existingId = this.sourceKeys.get(key);
    if (existingId) {
      const existing = this.journals.get(existingId);
      if (!existing) throw new Error("source key orphan");
      doc.journalEntryId = existing.id;
      doc.accountingStatus = "POSTED";
      doc.accountingPostedAt = doc.accountingPostedAt ?? new Date().toISOString();
      return { journalId: existing.id, created: false };
    }

    if (doc.accountingStatus === "POSTED" && doc.journalEntryId) {
      return { journalId: doc.journalEntryId, created: false };
    }

    if (this.failBeforeCommit.has(fiscalDocumentId)) {
      this.failBeforeCommit.delete(fiscalDocumentId);
      throw new Error("SIMULATED_TX_ABORT_BEFORE_JOURNAL_COMMIT");
    }

    this.seq += 1;
    const journalId = `je-${this.seq}`;
    const journal: SimulatedJournal = {
      id: journalId,
      organizationId: doc.organizationId,
      fiscalDocumentId: doc.id,
      status: "POSTED",
      debit: doc.totalAmount,
      credit: doc.totalAmount,
      lines: [
        { account: "receivables", debit: doc.totalAmount, credit: 0 },
        { account: "sales", debit: 0, credit: doc.netAmount },
        ...(doc.vatAmount > 0
          ? [{ account: "vat_out", debit: 0, credit: doc.vatAmount }]
          : []),
      ],
    };

    // Unique source insert — would raise on duplicate
    if (this.sourceKeys.has(key)) {
      const id = this.sourceKeys.get(key)!;
      return { journalId: id, created: false };
    }

    this.journals.set(journalId, journal);
    this.sourceKeys.set(key, journalId);
    doc.journalEntryId = journalId;
    doc.accountingStatus = "POSTED";
    doc.accountingPostedAt = new Date().toISOString();

    return { journalId, created: true };
  }

  /**
   * Immutable posted entries: mutating economic values throws.
   * Corrections via reverse().
   */
  tryMutatePosted(journalId: string, newTotal: number): never | void {
    const j = this.journals.get(journalId);
    if (!j) throw new Error("journal not found");
    if (j.status === "POSTED" || j.status === "REVERSED") {
      throw new Error("posted journal entries are immutable; use reversal");
    }
    j.debit = newTotal;
  }

  reverse(journalId: string): SimulatedJournal {
    const orig = this.journals.get(journalId);
    if (!orig) throw new Error("journal not found");
    if (orig.status !== "POSTED") throw new Error("only POSTED entries can be reversed");
    if (orig.reversedById) throw new Error("entry already reversed");

    this.seq += 1;
    const revId = `je-${this.seq}`;
    const rev: SimulatedJournal = {
      id: revId,
      organizationId: orig.organizationId,
      fiscalDocumentId: orig.fiscalDocumentId,
      status: "POSTED",
      debit: orig.credit,
      credit: orig.debit,
      lines: orig.lines.map((l) => ({
        account: l.account,
        debit: l.credit,
        credit: l.debit,
      })),
      reversalOfId: orig.id,
    };
    orig.status = "REVERSED";
    orig.reversedById = revId;
    this.journals.set(revId, rev);
    return rev;
  }

  /** Economic net of original + reversal (must be 0). Do not filter REVERSED out. */
  economicNetForFiscal(fiscalDocumentId: string): number {
    let net = 0;
    for (const j of this.journals.values()) {
      if (j.fiscalDocumentId !== fiscalDocumentId) continue;
      // Include POSTED and REVERSED originals + reversing POSTED
      const signed =
        j.lines.find((l) => l.account === "receivables")!.debit -
        j.lines.find((l) => l.account === "receivables")!.credit;
      net += signed;
    }
    return Math.round(net * 10000) / 10000;
  }
}

export type PostFiscalAccountingResult = {
  journalEntryId: string;
  alreadyPosted: boolean;
};

/**
 * App-layer orchestration: gate locally, then call DB RPC.
 * Caller supplies an RPC executor (Supabase client).
 */
export async function postFiscalDocumentAccountingOnce(params: {
  fiscalDocumentId: string;
  fiscalState: FiscalAccountingGateState | string;
  rpc: (fn: string, args: { p_fiscal_document_id: string }) => Promise<{
    data: string | null;
    error: { message: string } | null;
  }>;
}): Promise<PostFiscalAccountingResult> {
  const decision = decideFiscalAccountingPost(params.fiscalState);
  if (!decision.allow) {
    throw new Error(`ACCOUNTING_POST_BLOCKED:${decision.reason}`);
  }

  const { data, error } = await params.rpc("post_fiscal_document_accounting", {
    p_fiscal_document_id: params.fiscalDocumentId,
  });

  if (error) throw new Error(error.message);
  if (!data) throw new Error("post_fiscal_document_accounting returned null");

  return { journalEntryId: data, alreadyPosted: false };
}
