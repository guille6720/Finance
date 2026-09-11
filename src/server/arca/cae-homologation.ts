/**
 * Homologation-only controlled FECAESolicitar (one-shot).
 * Never use for Production. Never auto-retry.
 */
import { ArcaSanitizedError, sanitizeArcaMessage } from "./errors";
import type { ArcaHomologationConfig } from "./config";
import {
  ARCA_WSAA_HOMO_URL,
  ARCA_WSFE_HOMO_URL,
} from "./constants";
import {
  feCompConsultar,
  feCompUltimoAutorizado,
  feParamGetCondicionIvaReceptor,
  feParamGetTiposDoc,
  parseWsfeErrors,
  parseWsfeEvents,
  wsfeCallAllowErrors,
  type CatalogRow,
  type WsfeCodeMsg,
} from "./wsfe";

export const HOMO_CAE_ONCE = {
  ptoVta: 10,
  cbteTipo: 11,
  concepto: 1,
  docTipo: 99,
  docNro: 0,
  cantReg: 1,
  monId: "PES",
  monCotiz: "1",
  impTotal: "1000.00",
  impTotConc: "0.00",
  impNeto: "1000.00",
  impOpEx: "0.00",
  impTrib: "0.00",
  impIVA: "0.00",
  confirmFlag: "--confirm-homologation-issue",
} as const;

export type CaeOutcome =
  | "AUTHORIZED"
  | "AUTHORIZED_WITH_OBSERVATIONS"
  | "AUTHORIZED_RECONCILED"
  | "REJECTED"
  | "RECONCILIATION_REQUIRED"
  | "UNCERTAIN_STOP"
  | "STOP_BEFORE_FECAE"
  | "STOP_ALREADY_ISSUED"
  | "STOP_CONFIRMATION_REQUIRED"
  | "STOP_GUARD";

export type SafeCaeResult = {
  outcome: CaeOutcome;
  pto_venta: number;
  cbte_tipo: number;
  cbte_nro: number | null;
  resultado: string | null;
  cae_present: boolean;
  cae_length: number | null;
  cae_fch_vto: string | null;
  observations: Array<{ code: string; msg: string }>;
  errors: Array<{ code: string; msg: string }>;
  events: Array<{ code: string; msg: string }>;
  ACCOUNTING_POST: "NOT_RUN";
  ARCA_PRODUCTION: "NOT_AUTHORIZED";
  detail: string;
};

function argentinaCbteFch(now = new Date()): string {
  // Fixed Argentina offset UTC-3 (same approach as TRA formatting)
  const utc = now.getTime() + now.getTimezoneOffset() * 60_000;
  const local = new Date(utc + -180 * 60_000);
  const y = local.getFullYear();
  const m = String(local.getMonth() + 1).padStart(2, "0");
  const d = String(local.getDate()).padStart(2, "0");
  return `${y}${m}${d}`;
}

export function assertHomologationIssuanceGuards(
  config: ArcaHomologationConfig,
  opts: {
    confirmed: boolean;
    expectedPto?: number;
    expectedCbteTipo?: number;
  }
): void {
  if (!opts.confirmed) {
    throw new ArcaSanitizedError(
      "STOP_CONFIRMATION_REQUIRED",
      "cae",
      "Missing --confirm-homologation-issue"
    );
  }
  if (config.env !== "homologation") {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "ARCA_ENV must be homologation"
    );
  }
  if (config.wsaaUrl !== ARCA_WSAA_HOMO_URL) {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "WSAA URL must be homologation LoginCms"
    );
  }
  if (config.wsfeUrl !== ARCA_WSFE_HOMO_URL) {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "WSFE URL must be homologation WSFEv1"
    );
  }
  if (!/wsaahomo\.afip\.gov\.ar/i.test(config.wsaaUrl)) {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "WSAA host must be wsaahomo.afip.gov.ar"
    );
  }
  if (!/wswhomo\.afip\.gov\.ar/i.test(config.wsfeUrl)) {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "WSFE host must be wswhomo.afip.gov.ar"
    );
  }
  if (/wsaa\.afip\.gov\.ar/i.test(config.wsaaUrl) && !/wsaahomo/i.test(config.wsaaUrl)) {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "Production WSAA URL blocked"
    );
  }
  if (/servicios1\.afip\.gov\.ar/i.test(config.wsfeUrl)) {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "Production WSFE URL blocked"
    );
  }
  if (config.wsaaService !== "wsfe") {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "WSAA service must be wsfe"
    );
  }
  const expectedPto = opts.expectedPto ?? HOMO_CAE_ONCE.ptoVta;
  const expectedCbte = opts.expectedCbteTipo ?? HOMO_CAE_ONCE.cbteTipo;
  if (config.homoPtoVenta !== expectedPto) {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      `ARCA_HOMO_PTO_VENTA must be ${expectedPto}`
    );
  }
  if (expectedCbte !== 11) {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "CbteTipo must be 11 (Factura C)"
    );
  }
}

export function resolveConsumidorFinalId(rows: CatalogRow[]): number {
  const matches = rows.filter((r) => {
    const desc = String(r.Desc || "")
      .normalize("NFD")
      .replace(/\p{M}/gu, "")
      .toLowerCase();
    return desc.includes("consumidor final");
  });
  if (matches.length !== 1 || !matches[0].Id) {
    throw new ArcaSanitizedError(
      "STOP_BEFORE_FECAE",
      "cae",
      "Unambiguous CondicionIVAReceptor Consumidor Final not found"
    );
  }
  const id = Number(matches[0].Id);
  if (!Number.isInteger(id) || id <= 0) {
    throw new ArcaSanitizedError(
      "STOP_BEFORE_FECAE",
      "cae",
      "Invalid CondicionIVAReceptorId for Consumidor Final"
    );
  }
  return id;
}

export function requireDocTipo99(rows: CatalogRow[]): void {
  const ok = rows.some((r) => String(r.Id) === "99");
  if (!ok) {
    throw new ArcaSanitizedError(
      "STOP_BEFORE_FECAE",
      "cae",
      "DocTipo 99 not present in FEParamGetTiposDoc"
    );
  }
}

export type FeCaeDetPayload = {
  ptoVta: number;
  cbteTipo: number;
  cbteDesde: number;
  cbteHasta: number;
  cbteFch: string;
  condicionIvaReceptorId: number;
};

/** Build FECAESolicitar FeCAEReq inner XML (no Auth). Factura C / PES / no IVA array. */
export function buildFeCaeSolicitarBody(det: FeCaeDetPayload): string {
  if (det.ptoVta !== HOMO_CAE_ONCE.ptoVta) {
    throw new ArcaSanitizedError("STOP_GUARD", "cae", "wrong POS blocked");
  }
  if (det.cbteTipo !== HOMO_CAE_ONCE.cbteTipo) {
    throw new ArcaSanitizedError("STOP_GUARD", "cae", "wrong CbteTipo blocked");
  }
  return (
    `<ar:FeCAEReq>` +
    `<ar:FeCabReq>` +
    `<ar:CantReg>${HOMO_CAE_ONCE.cantReg}</ar:CantReg>` +
    `<ar:PtoVta>${det.ptoVta}</ar:PtoVta>` +
    `<ar:CbteTipo>${det.cbteTipo}</ar:CbteTipo>` +
    `</ar:FeCabReq>` +
    `<ar:FeDetReq>` +
    `<ar:FECAEDetRequest>` +
    `<ar:Concepto>${HOMO_CAE_ONCE.concepto}</ar:Concepto>` +
    `<ar:DocTipo>${HOMO_CAE_ONCE.docTipo}</ar:DocTipo>` +
    `<ar:DocNro>${HOMO_CAE_ONCE.docNro}</ar:DocNro>` +
    `<ar:CbteDesde>${det.cbteDesde}</ar:CbteDesde>` +
    `<ar:CbteHasta>${det.cbteHasta}</ar:CbteHasta>` +
    `<ar:CbteFch>${det.cbteFch}</ar:CbteFch>` +
    `<ar:ImpTotal>${HOMO_CAE_ONCE.impTotal}</ar:ImpTotal>` +
    `<ar:ImpTotConc>${HOMO_CAE_ONCE.impTotConc}</ar:ImpTotConc>` +
    `<ar:ImpNeto>${HOMO_CAE_ONCE.impNeto}</ar:ImpNeto>` +
    `<ar:ImpOpEx>${HOMO_CAE_ONCE.impOpEx}</ar:ImpOpEx>` +
    `<ar:ImpTrib>${HOMO_CAE_ONCE.impTrib}</ar:ImpTrib>` +
    `<ar:ImpIVA>${HOMO_CAE_ONCE.impIVA}</ar:ImpIVA>` +
    `<ar:MonId>${HOMO_CAE_ONCE.monId}</ar:MonId>` +
    `<ar:MonCotiz>${HOMO_CAE_ONCE.monCotiz}</ar:MonCotiz>` +
    `<ar:CondicionIVAReceptorId>${det.condicionIvaReceptorId}</ar:CondicionIVAReceptorId>` +
    `</ar:FECAEDetRequest>` +
    `</ar:FeDetReq>` +
    `</ar:FeCAEReq>`
  );
}

function extractTag(xml: string, tag: string): string | null {
  const re = new RegExp(
    `<(?:[\\w.-]+:)?${tag}\\b[^>]*>([\\s\\S]*?)</(?:[\\w.-]+:)?${tag}>`,
    "i"
  );
  const m = xml.match(re);
  return m ? m[1].trim() : null;
}

function extractAllBlocks(xml: string, tag: string): string[] {
  const re = new RegExp(
    `<(?:[\\w.-]+:)?${tag}\\b[^>]*>([\\s\\S]*?)</(?:[\\w.-]+:)?${tag}>`,
    "gi"
  );
  const out: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml))) out.push(m[1]);
  return out;
}

export type ParsedFeCaeResponse = {
  resultado: string | null;
  cae: string | null;
  caeFchVto: string | null;
  cbteDesde: number | null;
  cbteHasta: number | null;
  observations: WsfeCodeMsg[];
  errors: WsfeCodeMsg[];
  events: WsfeCodeMsg[];
  outcome: CaeOutcome;
};

export function parseFeCaeSolicitarResponse(xml: string): ParsedFeCaeResponse {
  const errors = parseWsfeErrors(xml).filter((e) => e.Code !== "0");
  const events = parseWsfeEvents(xml);
  const det =
    extractAllBlocks(xml, "FECAEDetResponse")[0] ||
    extractAllBlocks(xml, "FECAEDetResponse")[0] ||
    xml;
  const resultado =
    extractTag(det, "Resultado") || extractTag(xml, "Resultado");
  const cae = extractTag(det, "CAE") || extractTag(xml, "CAE");
  const caeFchVto =
    extractTag(det, "CAEFchVto") || extractTag(xml, "CAEFchVto");
  const cbteDesdeRaw = extractTag(det, "CbteDesde") || extractTag(xml, "CbteDesde");
  const cbteHastaRaw = extractTag(det, "CbteHasta") || extractTag(xml, "CbteHasta");
  const obsBlocks = [
    ...extractAllBlocks(det, "Obs"),
    ...extractAllBlocks(xml, "Obs"),
  ];
  const observations = obsBlocks.map((b) => ({
    Code: extractTag(b, "Code") ?? "",
    Msg: extractTag(b, "Msg") ?? "",
  }));

  let outcome: CaeOutcome;
  if (errors.length > 0 && !(resultado === "A" && cae)) {
    outcome = "REJECTED";
  } else if (resultado === "A" && cae) {
    outcome =
      observations.length > 0
        ? "AUTHORIZED_WITH_OBSERVATIONS"
        : "AUTHORIZED";
  } else if (resultado === "R" || resultado === "P") {
    outcome = "REJECTED";
  } else if (!resultado && !cae) {
    outcome = "UNCERTAIN_STOP";
  } else {
    outcome = "UNCERTAIN_STOP";
  }

  return {
    resultado,
    cae,
    caeFchVto,
    cbteDesde: cbteDesdeRaw != null ? Number(cbteDesdeRaw) : null,
    cbteHasta: cbteHastaRaw != null ? Number(cbteHastaRaw) : null,
    observations,
    errors,
    events,
    outcome,
  };
}

function safeFromParsed(
  outcome: CaeOutcome,
  parsed: Partial<ParsedFeCaeResponse>,
  cbteNro: number | null,
  detail: string
): SafeCaeResult {
  const cae = parsed.cae ?? null;
  return {
    outcome,
    pto_venta: HOMO_CAE_ONCE.ptoVta,
    cbte_tipo: HOMO_CAE_ONCE.cbteTipo,
    cbte_nro: cbteNro,
    resultado: parsed.resultado ?? null,
    cae_present: Boolean(cae),
    cae_length: cae ? cae.length : null,
    cae_fch_vto: parsed.caeFchVto ?? null,
    observations: (parsed.observations || []).map((o) => ({
      code: o.Code,
      msg: sanitizeArcaMessage(o.Msg),
    })),
    errors: (parsed.errors || []).map((o) => ({
      code: o.Code,
      msg: sanitizeArcaMessage(o.Msg),
    })),
    events: (parsed.events || []).map((o) => ({
      code: o.Code,
      msg: sanitizeArcaMessage(o.Msg),
    })),
    ACCOUNTING_POST: "NOT_RUN",
    ARCA_PRODUCTION: "NOT_AUTHORIZED",
    detail: sanitizeArcaMessage(detail),
  };
}

export async function reconcileViaFeCompConsultar(
  config: ArcaHomologationConfig,
  expectedCae: string | null,
  cbteNro: number
): Promise<SafeCaeResult> {
  try {
    const consulted = await feCompConsultar(
      config,
      HOMO_CAE_ONCE.ptoVta,
      HOMO_CAE_ONCE.cbteTipo,
      cbteNro
    );
    if (consulted.found && consulted.CAE) {
      if (expectedCae && consulted.CAE !== expectedCae) {
        return safeFromParsed(
          "RECONCILIATION_REQUIRED",
          {
            resultado: consulted.Resultado,
            cae: null,
            caeFchVto: consulted.CAEFchVto,
            observations: consulted.observations,
            errors: consulted.errors,
            events: [],
          },
          cbteNro,
          "CAE mismatch between FECAESolicitar and FECompConsultar"
        );
      }
      return safeFromParsed(
        "AUTHORIZED_RECONCILED",
        {
          resultado: consulted.Resultado,
          cae: consulted.CAE,
          caeFchVto: consulted.CAEFchVto,
          observations: consulted.observations,
          errors: consulted.errors,
          events: [],
        },
        cbteNro,
        "Reconciled via FECompConsultar"
      );
    }
    if (consulted.errors.length > 0) {
      return safeFromParsed(
        "REJECTED",
        {
          resultado: consulted.Resultado,
          cae: null,
          caeFchVto: null,
          observations: consulted.observations,
          errors: consulted.errors,
          events: [],
        },
        cbteNro,
        "FECompConsultar indicates nonexistence/rejection"
      );
    }
    return safeFromParsed(
      "UNCERTAIN_STOP",
      {
        resultado: consulted.Resultado,
        cae: null,
        caeFchVto: null,
        observations: consulted.observations,
        errors: consulted.errors,
        events: [],
      },
      cbteNro,
      "FECompConsultar could not determine state"
    );
  } catch (e) {
    return safeFromParsed(
      "UNCERTAIN_STOP",
      {},
      cbteNro,
      `FECompConsultar failed: ${String((e as Error).message || e)}`
    );
  }
}

/**
 * Homologation-only one-shot FECAESolicitar.
 * Impossible when config.env !== homologation (guards).
 * Never retries on uncertainty.
 */
export async function feCaeSolicitarHomologationOnce(
  config: ArcaHomologationConfig,
  opts: { confirmed: boolean; now?: Date }
): Promise<SafeCaeResult> {
  assertHomologationIssuanceGuards(config, { confirmed: opts.confirmed });

  const tiposDoc = await feParamGetTiposDoc(config);
  requireDocTipo99(tiposDoc);

  const ivaRows = await feParamGetCondicionIvaReceptor(config);
  const condicionIvaReceptorId = resolveConsumidorFinalId(ivaRows);

  const ultimo = await feCompUltimoAutorizado(
    config,
    HOMO_CAE_ONCE.ptoVta,
    HOMO_CAE_ONCE.cbteTipo
  );
  if (ultimo.CbteNro !== 0) {
    return safeFromParsed(
      "STOP_ALREADY_ISSUED",
      {},
      ultimo.CbteNro,
      `Last authorized is ${ultimo.CbteNro}, expected 0`
    );
  }
  const nextNumber = ultimo.CbteNro + 1;
  if (nextNumber !== 1) {
    return safeFromParsed(
      "STOP_ALREADY_ISSUED",
      {},
      ultimo.CbteNro,
      "nextNumber must be 1"
    );
  }

  const body = buildFeCaeSolicitarBody({
    ptoVta: HOMO_CAE_ONCE.ptoVta,
    cbteTipo: HOMO_CAE_ONCE.cbteTipo,
    cbteDesde: nextNumber,
    cbteHasta: nextNumber,
    cbteFch: argentinaCbteFch(opts.now ?? new Date()),
    condicionIvaReceptorId,
  });

  if (body.includes("<ar:PtoVenta>") || !body.includes("<ar:PtoVta>10</ar:PtoVta>")) {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "FECAESolicitar payload must use PtoVta=10"
    );
  }
  if (/<ar:IVA>|CanMisMonExt|FchServ/i.test(body)) {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "cae",
      "Factura C PES payload must not include IVA/service/CanMisMonExt"
    );
  }

  let xml: string;
  try {
    xml = await wsfeCallAllowErrors(config, "FECAESolicitar", body);
  } catch (e) {
    const err = e as ArcaSanitizedError;
    if (
      err?.code === "WSFE_NETWORK" ||
      err?.code === "WSFE_HTTP" ||
      err?.code === "WSFE_FAULT"
    ) {
      // NEVER retry FECAESolicitar — reconcile once.
      return reconcileViaFeCompConsultar(config, null, nextNumber);
    }
    throw e;
  }

  const parsed = parseFeCaeSolicitarResponse(xml);

  if (
    parsed.outcome === "UNCERTAIN_STOP" ||
    (parsed.outcome.startsWith("AUTHORIZED") && (!parsed.cae || !parsed.caeFchVto))
  ) {
    return reconcileViaFeCompConsultar(config, parsed.cae, nextNumber);
  }

  if (parsed.outcome === "REJECTED") {
    return safeFromParsed(parsed.outcome, parsed, nextNumber, "FECAESolicitar rejected");
  }

  // Approved path: verify CAE, consult, last number
  if (!parsed.cae || !parsed.caeFchVto) {
    return safeFromParsed(
      "RECONCILIATION_REQUIRED",
      parsed,
      nextNumber,
      "Approved response missing CAE or CAEFchVto"
    );
  }

  const consulted = await feCompConsultar(
    config,
    HOMO_CAE_ONCE.ptoVta,
    HOMO_CAE_ONCE.cbteTipo,
    nextNumber
  );
  if (!consulted.CAE || consulted.CAE !== parsed.cae) {
    return safeFromParsed(
      "RECONCILIATION_REQUIRED",
      parsed,
      nextNumber,
      "Post-authorization FECompConsultar CAE mismatch or missing"
    );
  }

  const last = await feCompUltimoAutorizado(
    config,
    HOMO_CAE_ONCE.ptoVta,
    HOMO_CAE_ONCE.cbteTipo
  );
  if (last.CbteNro !== 1) {
    return safeFromParsed(
      "RECONCILIATION_REQUIRED",
      parsed,
      nextNumber,
      `Post-authorization last authorized is ${last.CbteNro}, expected 1`
    );
  }

  return safeFromParsed(parsed.outcome, parsed, nextNumber, "Homologation CAE verified");
}
