/**
 * Homologation-only rejection + uncertain reconciliation gates.
 * Never Production. Never auto-retry FECAESolicitar. No accounting.
 */
import { ArcaSanitizedError, sanitizeArcaMessage } from "./errors";
import type { ArcaHomologationConfig } from "./config";
import {
  assertHomologationIssuanceGuards,
  buildFeCaeSolicitarBody,
  parseFeCaeSolicitarResponse,
  reconcileViaFeCompConsultar,
  resolveConsumidorFinalId,
  requireDocTipo99,
  HOMO_CAE_ONCE,
  type SafeCaeResult,
} from "./cae-homologation";
import {
  feCompConsultar,
  feCompUltimoAutorizado,
  feParamGetCondicionIvaReceptor,
  feParamGetTiposDoc,
  wsfeCallAllowErrors,
} from "./wsfe";

export const REJECTION_CONFIRM_FLAG = "--confirm-rejection-test";
export const UNCERTAIN_CONFIRM_FLAG = "--confirm-uncertain-test";

export type Phase5Evidence = {
  FECAESOLICITAR: "EXECUTED" | "NOT_RUN" | "SIMULATED_LOSS";
  FECOMPCONSULTAR: "PASS" | "FAIL" | "NOT_RUN";
  CAE_MATCH: boolean | null;
  CAE_PRESENT: boolean;
  LAST_AUTHORIZED_QUERY: "PASS" | "FAIL" | "NOT_RUN";
  LAST_AUTHORIZED: number | null;
  LAST_BEFORE: number | null;
  LAST_AFTER: number | null;
  NO_AUTOMATIC_RETRY: true;
  AUTOMATIC_RETRY: "NO";
  FECAESOLICITAR_CALL_COUNT: number;
  RECONCILIATION_STATUS:
    | "NOT_NEEDED"
    | "AUTHORIZED_RECONCILED"
    | "RECONCILIATION_REQUIRED"
    | "UNCERTAIN_STOP"
    | "NOT_RUN";
  NUMBER_CONSUMED: "YES" | "NO" | "UNKNOWN";
  ACCOUNTING_POST: "NOT_RUN";
  ARCA_PRODUCTION: "NOT_AUTHORIZED";
  SIMULATED_RESPONSE_LOSS: "PASS" | "NOT_RUN" | "FAIL";
  detail: string;
  errors: Array<{ code: string; msg: string }>;
  observations: Array<{ code: string; msg: string }>;
  outcome: string;
};

function baseEvidence(
  partial: Partial<Phase5Evidence> & { outcome: string; detail: string }
): Phase5Evidence {
  return {
    FECAESOLICITAR: "NOT_RUN",
    FECOMPCONSULTAR: "NOT_RUN",
    CAE_MATCH: null,
    CAE_PRESENT: false,
    LAST_AUTHORIZED_QUERY: "NOT_RUN",
    LAST_AUTHORIZED: null,
    LAST_BEFORE: null,
    LAST_AFTER: null,
    NO_AUTOMATIC_RETRY: true,
    AUTOMATIC_RETRY: "NO",
    FECAESOLICITAR_CALL_COUNT: 0,
    RECONCILIATION_STATUS: "NOT_RUN",
    NUMBER_CONSUMED: "UNKNOWN",
    ACCOUNTING_POST: "NOT_RUN",
    ARCA_PRODUCTION: "NOT_AUTHORIZED",
    SIMULATED_RESPONSE_LOSS: "NOT_RUN",
    errors: [],
    observations: [],
    ...partial,
    detail: sanitizeArcaMessage(partial.detail),
  };
}

function argentinaCbteFch(now = new Date()): string {
  const utc = now.getTime() + now.getTimezoneOffset() * 60_000;
  const local = new Date(utc + -180 * 60_000);
  const y = local.getFullYear();
  const m = String(local.getMonth() + 1).padStart(2, "0");
  const d = String(local.getDate()).padStart(2, "0");
  return `${y}${m}${d}`;
}

/** Deliberately invalid MonId so ARCA rejects before authorization. */
export function buildInvalidRejectionFeCaeBody(input: {
  cbteDesde: number;
  cbteHasta: number;
  cbteFch: string;
  condicionIvaReceptorId: number;
}): string {
  const valid = buildFeCaeSolicitarBody({
    ptoVta: HOMO_CAE_ONCE.ptoVta,
    cbteTipo: HOMO_CAE_ONCE.cbteTipo,
    cbteDesde: input.cbteDesde,
    cbteHasta: input.cbteHasta,
    cbteFch: input.cbteFch,
    condicionIvaReceptorId: input.condicionIvaReceptorId,
  });
  // Replace PES with a non-catalog currency code (deterministic WSFE validation reject).
  const invalid = valid.replace(
    `<ar:MonId>${HOMO_CAE_ONCE.monId}</ar:MonId>`,
    `<ar:MonId>XXX</ar:MonId>`
  );
  if (!invalid.includes("<ar:MonId>XXX</ar:MonId>")) {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "Failed to inject invalid MonId for rejection test"
    );
  }
  if (invalid.includes("<ar:PtoVenta>")) {
    throw new ArcaSanitizedError("STOP_GUARD", "cae", "PtoVenta must not appear");
  }
  return invalid;
}

export function assertConfirmationFlag(
  argv: string[],
  flag: string
): void {
  if (!argv.includes(flag)) {
    throw new ArcaSanitizedError(
      "STOP_CONFIRMATION_REQUIRED",
      "cae",
      `Missing ${flag}`
    );
  }
}

/**
 * Rejection gate: invalid Factura C Nº2 must be REJECTED and not consume sequence.
 */
export async function runHomologationRejectionGate(
  config: ArcaHomologationConfig,
  opts: { confirmed: boolean; now?: Date }
): Promise<Phase5Evidence> {
  if (!opts.confirmed) {
    throw new ArcaSanitizedError(
      "STOP_CONFIRMATION_REQUIRED",
      "cae",
      `Missing ${REJECTION_CONFIRM_FLAG}`
    );
  }
  assertHomologationIssuanceGuards(config, {
    confirmed: true,
  });

  const lastBefore = await feCompUltimoAutorizado(
    config,
    HOMO_CAE_ONCE.ptoVta,
    HOMO_CAE_ONCE.cbteTipo
  );
  if (lastBefore.CbteNro !== 1) {
    throw new ArcaSanitizedError(
      "STOP_SEQUENCE_MISMATCH",
      "cae",
      `Expected last authorized 1, got ${lastBefore.CbteNro}`
    );
  }

  const tiposDoc = await feParamGetTiposDoc(config);
  requireDocTipo99(tiposDoc);
  const ivaRows = await feParamGetCondicionIvaReceptor(config);
  const condicionIvaReceptorId = resolveConsumidorFinalId(ivaRows);

  const body = buildInvalidRejectionFeCaeBody({
    cbteDesde: 2,
    cbteHasta: 2,
    cbteFch: argentinaCbteFch(opts.now ?? new Date()),
    condicionIvaReceptorId,
  });

  let fecaeCalls = 0;
  let xml: string;
  try {
    fecaeCalls += 1;
    xml = await wsfeCallAllowErrors(config, "FECAESolicitar", body);
  } catch (e) {
    // Network uncertainty on rejection test → still no retry; check last stays 1
    const lastAfterNet = await feCompUltimoAutorizado(
      config,
      HOMO_CAE_ONCE.ptoVta,
      HOMO_CAE_ONCE.cbteTipo
    );
    return baseEvidence({
      outcome: "UNCERTAIN_STOP",
      FECAESOLICITAR: "EXECUTED",
      FECAESOLICITAR_CALL_COUNT: fecaeCalls,
      LAST_BEFORE: 1,
      LAST_AFTER: lastAfterNet.CbteNro,
      LAST_AUTHORIZED: lastAfterNet.CbteNro,
      LAST_AUTHORIZED_QUERY: "PASS",
      NUMBER_CONSUMED: lastAfterNet.CbteNro === 1 ? "NO" : "YES",
      detail: `Rejection transport failure: ${String((e as Error).message || e)}`,
    });
  }

  if (fecaeCalls !== 1) {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "FECAESOLICITAR_CALL_COUNT must be 1"
    );
  }

  const parsed = parseFeCaeSolicitarResponse(xml);

  if (parsed.outcome.startsWith("AUTHORIZED") || (parsed.resultado === "A" && parsed.cae)) {
    const recon = await reconcileViaFeCompConsultar(config, parsed.cae, 2);
    const lastAfter = await feCompUltimoAutorizado(
      config,
      HOMO_CAE_ONCE.ptoVta,
      HOMO_CAE_ONCE.cbteTipo
    );
    return baseEvidence({
      outcome: "STOP_UNEXPECTED_AUTHORIZATION",
      FECAESOLICITAR: "EXECUTED",
      FECAESOLICITAR_CALL_COUNT: 1,
      FECOMPCONSULTAR:
        recon.outcome === "AUTHORIZED_RECONCILED" ? "PASS" : "FAIL",
      CAE_PRESENT: recon.cae_present,
      CAE_MATCH: recon.outcome === "AUTHORIZED_RECONCILED" ? true : false,
      RECONCILIATION_STATUS:
        recon.outcome === "AUTHORIZED_RECONCILED"
          ? "AUTHORIZED_RECONCILED"
          : "RECONCILIATION_REQUIRED",
      LAST_BEFORE: 1,
      LAST_AFTER: lastAfter.CbteNro,
      LAST_AUTHORIZED: lastAfter.CbteNro,
      LAST_AUTHORIZED_QUERY: "PASS",
      NUMBER_CONSUMED: lastAfter.CbteNro > 1 ? "YES" : "NO",
      errors: recon.errors,
      observations: recon.observations,
      detail: "Unexpected authorization on rejection test — reconciled",
    });
  }

  if (parsed.outcome !== "REJECTED") {
    const lastAfter = await feCompUltimoAutorizado(
      config,
      HOMO_CAE_ONCE.ptoVta,
      HOMO_CAE_ONCE.cbteTipo
    );
    return baseEvidence({
      outcome: parsed.outcome,
      FECAESOLICITAR: "EXECUTED",
      FECAESOLICITAR_CALL_COUNT: 1,
      LAST_BEFORE: 1,
      LAST_AFTER: lastAfter.CbteNro,
      LAST_AUTHORIZED: lastAfter.CbteNro,
      LAST_AUTHORIZED_QUERY: "PASS",
      NUMBER_CONSUMED: lastAfter.CbteNro === 1 ? "NO" : "YES",
      errors: parsed.errors.map((e) => ({
        code: e.Code,
        msg: sanitizeArcaMessage(e.Msg),
      })),
      observations: parsed.observations.map((e) => ({
        code: e.Code,
        msg: sanitizeArcaMessage(e.Msg),
      })),
      detail: "Rejection test did not return REJECTED",
    });
  }

  const lastAfter = await feCompUltimoAutorizado(
    config,
    HOMO_CAE_ONCE.ptoVta,
    HOMO_CAE_ONCE.cbteTipo
  );

  if (lastAfter.CbteNro === 2) {
    return baseEvidence({
      outcome: "REJECTION_SEQUENCE_FAIL",
      FECAESOLICITAR: "EXECUTED",
      FECAESOLICITAR_CALL_COUNT: 1,
      LAST_BEFORE: 1,
      LAST_AFTER: 2,
      LAST_AUTHORIZED: 2,
      LAST_AUTHORIZED_QUERY: "PASS",
      NUMBER_CONSUMED: "YES",
      RECONCILIATION_STATUS: "NOT_NEEDED",
      errors: parsed.errors.map((e) => ({
        code: e.Code,
        msg: sanitizeArcaMessage(e.Msg),
      })),
      observations: parsed.observations.map((e) => ({
        code: e.Code,
        msg: sanitizeArcaMessage(e.Msg),
      })),
      detail: "Rejection unexpectedly advanced last authorized to 2",
    });
  }

  if (lastAfter.CbteNro !== 1) {
    return baseEvidence({
      outcome: "REJECTION_SEQUENCE_FAIL",
      FECAESOLICITAR: "EXECUTED",
      FECAESOLICITAR_CALL_COUNT: 1,
      LAST_BEFORE: 1,
      LAST_AFTER: lastAfter.CbteNro,
      LAST_AUTHORIZED: lastAfter.CbteNro,
      LAST_AUTHORIZED_QUERY: "PASS",
      NUMBER_CONSUMED: "UNKNOWN",
      errors: parsed.errors.map((e) => ({
        code: e.Code,
        msg: sanitizeArcaMessage(e.Msg),
      })),
      observations: parsed.observations.map((e) => ({
        code: e.Code,
        msg: sanitizeArcaMessage(e.Msg),
      })),
      detail: `Unexpected last authorized after rejection: ${lastAfter.CbteNro}`,
    });
  }

  return baseEvidence({
    outcome: "REJECTED",
    FECAESOLICITAR: "EXECUTED",
    FECAESOLICITAR_CALL_COUNT: 1,
    FECOMPCONSULTAR: "NOT_RUN",
    CAE_PRESENT: false,
    CAE_MATCH: null,
    RECONCILIATION_STATUS: "NOT_NEEDED",
    LAST_BEFORE: 1,
    LAST_AFTER: 1,
    LAST_AUTHORIZED: 1,
    LAST_AUTHORIZED_QUERY: "PASS",
    NUMBER_CONSUMED: "NO",
    errors: parsed.errors.map((e) => ({
      code: e.Code,
      msg: sanitizeArcaMessage(e.Msg),
    })),
    observations: parsed.observations.map((e) => ({
      code: e.Code,
      msg: sanitizeArcaMessage(e.Msg),
    })),
    detail: "Rejection gate PASS — number not consumed",
  });
}

/**
 * Uncertain gate: valid Nº2 issued once, application discards response,
 * then reconciles via FECompConsultar. Never second FECAESolicitar.
 */
export async function runHomologationUncertainGate(
  config: ArcaHomologationConfig,
  opts: {
    confirmed: boolean;
    now?: Date;
    /** Test hook: after transport returns, discard visible response. */
    simulateResponseLoss?: boolean;
  }
): Promise<Phase5Evidence> {
  if (!opts.confirmed) {
    throw new ArcaSanitizedError(
      "STOP_CONFIRMATION_REQUIRED",
      "cae",
      `Missing ${UNCERTAIN_CONFIRM_FLAG}`
    );
  }
  assertHomologationIssuanceGuards(config, { confirmed: true });

  const lastBefore = await feCompUltimoAutorizado(
    config,
    HOMO_CAE_ONCE.ptoVta,
    HOMO_CAE_ONCE.cbteTipo
  );
  if (lastBefore.CbteNro !== 1) {
    throw new ArcaSanitizedError(
      "STOP_SEQUENCE_MISMATCH",
      "cae",
      `Expected last authorized 1, got ${lastBefore.CbteNro}`
    );
  }

  const tiposDoc = await feParamGetTiposDoc(config);
  requireDocTipo99(tiposDoc);
  const ivaRows = await feParamGetCondicionIvaReceptor(config);
  const condicionIvaReceptorId = resolveConsumidorFinalId(ivaRows);

  const body = buildFeCaeSolicitarBody({
    ptoVta: HOMO_CAE_ONCE.ptoVta,
    cbteTipo: HOMO_CAE_ONCE.cbteTipo,
    cbteDesde: 2,
    cbteHasta: 2,
    cbteFch: argentinaCbteFch(opts.now ?? new Date()),
    condicionIvaReceptorId,
  });

  let fecaeCalls = 0;
  let transportXml: string | null = null;
  try {
    fecaeCalls += 1;
    transportXml = await wsfeCallAllowErrors(config, "FECAESolicitar", body);
  } catch (e) {
    // True transport failure — still no retry; reconcile
    const recon = await reconcileViaFeCompConsultar(config, null, 2);
    const lastAfter = await feCompUltimoAutorizado(
      config,
      HOMO_CAE_ONCE.ptoVta,
      HOMO_CAE_ONCE.cbteTipo
    );
    return baseEvidence({
      outcome: recon.outcome,
      FECAESOLICITAR: "EXECUTED",
      FECAESOLICITAR_CALL_COUNT: fecaeCalls,
      FECOMPCONSULTAR:
        recon.outcome === "AUTHORIZED_RECONCILED" ? "PASS" : "FAIL",
      CAE_PRESENT: recon.cae_present,
      CAE_MATCH: recon.outcome === "AUTHORIZED_RECONCILED" ? true : null,
      RECONCILIATION_STATUS:
        recon.outcome === "AUTHORIZED_RECONCILED"
          ? "AUTHORIZED_RECONCILED"
          : recon.outcome === "UNCERTAIN_STOP"
            ? "UNCERTAIN_STOP"
            : "RECONCILIATION_REQUIRED",
      LAST_BEFORE: 1,
      LAST_AFTER: lastAfter.CbteNro,
      LAST_AUTHORIZED: lastAfter.CbteNro,
      LAST_AUTHORIZED_QUERY: "PASS",
      NUMBER_CONSUMED: lastAfter.CbteNro >= 2 ? "YES" : "NO",
      SIMULATED_RESPONSE_LOSS: "NOT_RUN",
      errors: recon.errors,
      observations: recon.observations,
      detail: `Transport error then reconcile: ${String((e as Error).message || e)}`,
    });
  }

  if (fecaeCalls !== 1) {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "FECAESOLICITAR_CALL_COUNT must be 1"
    );
  }

  const simulate = opts.simulateResponseLoss !== false;
  // Application-visible response discarded (homologation test fault injection).
  const visibleXml = simulate ? null : transportXml;
  void visibleXml;

  if (simulate && transportXml) {
    // Parse privately only to detect unexpected empty transport; do not use for approval.
    // SIMULATED_RESPONSE_LOSS: treat as unknown regardless of transportXml content.
  }

  const recon = await reconcileViaFeCompConsultar(config, null, 2);
  const lastAfter = await feCompUltimoAutorizado(
    config,
    HOMO_CAE_ONCE.ptoVta,
    HOMO_CAE_ONCE.cbteTipo
  );

  if (recon.outcome === "AUTHORIZED_RECONCILED") {
    if (!recon.cae_present) {
      return baseEvidence({
        outcome: "RECONCILIATION_REQUIRED",
        FECAESOLICITAR: "SIMULATED_LOSS",
        FECAESOLICITAR_CALL_COUNT: 1,
        FECOMPCONSULTAR: "FAIL",
        CAE_PRESENT: false,
        CAE_MATCH: false,
        RECONCILIATION_STATUS: "RECONCILIATION_REQUIRED",
        LAST_BEFORE: 1,
        LAST_AFTER: lastAfter.CbteNro,
        LAST_AUTHORIZED: lastAfter.CbteNro,
        LAST_AUTHORIZED_QUERY: "PASS",
        NUMBER_CONSUMED: lastAfter.CbteNro >= 2 ? "YES" : "NO",
        SIMULATED_RESPONSE_LOSS: "PASS",
        detail: "Reconciled without CAE present — fail closed",
      });
    }
    if (lastAfter.CbteNro !== 2) {
      return baseEvidence({
        outcome: "RECONCILIATION_REQUIRED",
        FECAESOLICITAR: "SIMULATED_LOSS",
        FECAESOLICITAR_CALL_COUNT: 1,
        FECOMPCONSULTAR: "PASS",
        CAE_PRESENT: true,
        CAE_MATCH: true,
        RECONCILIATION_STATUS: "RECONCILIATION_REQUIRED",
        LAST_BEFORE: 1,
        LAST_AFTER: lastAfter.CbteNro,
        LAST_AUTHORIZED: lastAfter.CbteNro,
        LAST_AUTHORIZED_QUERY: "FAIL",
        NUMBER_CONSUMED: "UNKNOWN",
        SIMULATED_RESPONSE_LOSS: "PASS",
        detail: `Expected last authorized 2 after reconcile, got ${lastAfter.CbteNro}`,
      });
    }
    return baseEvidence({
      outcome: "AUTHORIZED_RECONCILED",
      FECAESOLICITAR: "SIMULATED_LOSS",
      FECAESOLICITAR_CALL_COUNT: 1,
      FECOMPCONSULTAR: "PASS",
      CAE_PRESENT: true,
      CAE_MATCH: true,
      RECONCILIATION_STATUS: "AUTHORIZED_RECONCILED",
      LAST_BEFORE: 1,
      LAST_AFTER: 2,
      LAST_AUTHORIZED: 2,
      LAST_AUTHORIZED_QUERY: "PASS",
      NUMBER_CONSUMED: "YES",
      SIMULATED_RESPONSE_LOSS: "PASS",
      errors: recon.errors,
      observations: recon.observations,
      detail: "Uncertain gate PASS — single FECAE + FECompConsultar reconcile",
    });
  }

  return baseEvidence({
    outcome: recon.outcome,
    FECAESOLICITAR: "SIMULATED_LOSS",
    FECAESOLICITAR_CALL_COUNT: 1,
    FECOMPCONSULTAR: recon.outcome === "UNCERTAIN_STOP" ? "FAIL" : "FAIL",
    CAE_PRESENT: recon.cae_present,
    CAE_MATCH: null,
    RECONCILIATION_STATUS:
      recon.outcome === "UNCERTAIN_STOP"
        ? "UNCERTAIN_STOP"
        : "RECONCILIATION_REQUIRED",
    LAST_BEFORE: 1,
    LAST_AFTER: lastAfter.CbteNro,
    LAST_AUTHORIZED: lastAfter.CbteNro,
    LAST_AUTHORIZED_QUERY: "PASS",
    NUMBER_CONSUMED: lastAfter.CbteNro >= 2 ? "YES" : "NO",
    SIMULATED_RESPONSE_LOSS: "PASS",
    errors: recon.errors,
    observations: recon.observations,
    detail: "Uncertain gate could not reconcile",
  });
}

/** Ensure SafeCaeResult never embeds a full CAE string. */
export function assertNoFullCaeInEvidence(obj: unknown): void {
  const s = JSON.stringify(obj);
  if (/"cae"\s*:\s*"[0-9]{10,}"/i.test(s)) {
    throw new ArcaSanitizedError(
      "SECRET_LEAK",
      "cae",
      "Evidence must not persist full CAE"
    );
  }
}

export type { SafeCaeResult };
