/**
 * Server-only ARCA Fiscal Gateway (homologation).
 * Never import from client components.
 */
if (typeof window !== "undefined") {
  throw new Error("ARCA fiscal gateway must not be imported in the browser");
}

export {
  ARCA_WSAA_HOMO_URL,
  ARCA_WSFE_HOMO_URL,
  ARCA_WSAA_SERVICE,
} from "./constants";
export { ArcaSanitizedError, sanitizeArcaMessage } from "./errors";
export {
  getArcaHomologationConfig,
  tryGetArcaHomologationConfig,
  loadArcaHomoEnvFile,
  parseArcaHomoPtoVenta,
  type ArcaHomologationConfig,
} from "./config";
export { validateCertKeyMatch, type CertKeyMatchResult } from "./cert";
export { buildLoginTicketRequest, formatAfipDateTime } from "./tra";
export { signTraCms } from "./cms";
export {
  wsaaLoginCms,
  wsaaTicketMeta,
  extractSoapFault,
  parseLoginTicketResponse,
  type WsaaTicket,
} from "./wsaa";
export { getValidTa, clearTaCacheForTests, clearTaMemoryCacheForTests, taCacheStats } from "./ta-cache";
export {
  readHomoTaFileCache,
  writeHomoTaFileCache,
  clearHomoTaFileCacheForTests,
  isTaFresh,
  getHomoTaCachePath,
  homoTaFileCacheMeta,
  HOMO_TA_FILE_CACHE_STRATEGY,
} from "./ta-file-cache";
export { buildGateFailureReport, type GateFailureReport } from "./gate-failure";
export {
  feDummy,
  feParamGetTiposCbte,
  feParamGetTiposDoc,
  feParamGetTiposMonedas,
  feParamGetCondicionIvaReceptor,
  feParamGetPtosVenta,
  feCompUltimoAutorizado,
  feCaeSolicitarForbidden,
  parseWsfeErrors,
  parseWsfeEvents,
  assertNoWsfeErrors,
  wsfeEventsMeta,
  probeHomologationPos,
  feCompConsultar,
  wsfeCallAllowErrors,
} from "./wsfe";
export {
  feCaeSolicitarHomologationOnce,
  assertHomologationIssuanceGuards,
  buildFeCaeSolicitarBody,
  parseFeCaeSolicitarResponse,
  resolveConsumidorFinalId,
  requireDocTipo99,
  reconcileViaFeCompConsultar,
  HOMO_CAE_ONCE,
  type SafeCaeResult,
  type CaeOutcome,
} from "./cae-homologation";
export {
  runHomologationRejectionGate,
  runHomologationUncertainGate,
  buildInvalidRejectionFeCaeBody,
  assertConfirmationFlag,
  assertNoFullCaeInEvidence,
  REJECTION_CONFIRM_FLAG,
  UNCERTAIN_CONFIRM_FLAG,
  type Phase5Evidence,
} from "./cae-gates";
export {
  mapCondicionIvaReceptor,
  mapTiposCbte,
  mapTiposDoc,
  mapTiposMonedas,
} from "./catalog-sync";
