import { ArcaSanitizedError, sanitizeArcaMessage } from "./errors";

export type GateFailureReport = {
  BLOCKER: string;
  ROOT_CAUSE: string;
  STAGE: string;
  WSAA_HOMOLOGATION: "PASS" | "FAIL" | "NOT_RUN";
  FECAESOLICITAR_CALL_COUNT: number;
  FECAESOLICITAR_SENT: "YES" | "NO";
  AUTOMATIC_RETRY: "NO";
  ACCOUNTING_POST: "NOT_RUN";
  ARCA_PRODUCTION: "NOT_AUTHORIZED";
};

/**
 * Build sanitized pre-issuance / gate failure evidence.
 * Never includes token/sign/CUIT/CMS/cert/key/Base64 payloads.
 */
export function buildGateFailureReport(
  err: unknown,
  opts?: { fecaeCallCount?: number }
): GateFailureReport {
  const fecaeCallCount = opts?.fecaeCallCount ?? 0;
  const e = err as Partial<ArcaSanitizedError> & {
    code?: string;
    stage?: string;
    message?: string;
  };
  const code =
    (e instanceof ArcaSanitizedError ? e.code : e.code) || "UNCERTAIN_FAIL";
  const stage =
    (e instanceof ArcaSanitizedError ? e.stage : e.stage) || "uncertain";
  const message = sanitizeArcaMessage(String(e.message || err || "unknown"));
  const wsaaFail =
    stage === "wsaa" ||
    String(code).startsWith("WSAA_") ||
    /wsaa/i.test(String(code));

  return {
    BLOCKER: String(code),
    ROOT_CAUSE: message || "(empty sanitized fault)",
    STAGE: String(stage),
    WSAA_HOMOLOGATION: wsaaFail ? "FAIL" : fecaeCallCount > 0 ? "PASS" : "NOT_RUN",
    FECAESOLICITAR_CALL_COUNT: fecaeCallCount,
    FECAESOLICITAR_SENT: fecaeCallCount > 0 ? "YES" : "NO",
    AUTOMATIC_RETRY: "NO",
    ACCOUNTING_POST: "NOT_RUN",
    ARCA_PRODUCTION: "NOT_AUTHORIZED",
  };
}
