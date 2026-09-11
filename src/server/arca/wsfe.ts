import { ArcaSanitizedError, sanitizeArcaMessage } from "./errors";
import type { ArcaHomologationConfig } from "./config";
import { getValidTa } from "./ta-cache";
import type { WsaaTicket } from "./wsaa";

const WSFE_NS = "http://ar.gov.afip.dif.FEV1/";

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

export type WsfeCodeMsg = {
  Code: string;
  Msg: string;
};

/**
 * Parse ARCA Errors/Err (or namespace-prefixed) only — never the first
 * generic Code/Msg anywhere in the SOAP document.
 */
export function parseWsfeErrors(xml: string): WsfeCodeMsg[] {
  const errorsBlocks = extractAllBlocks(xml, "Errors");
  const out: WsfeCodeMsg[] = [];
  for (const block of errorsBlocks) {
    for (const err of extractAllBlocks(block, "Err")) {
      const Code = extractTag(err, "Code");
      const Msg = extractTag(err, "Msg");
      if (Code != null) {
        out.push({ Code, Msg: Msg ?? "" });
      }
    }
  }
  return out;
}

/**
 * Parse ARCA Events/Evt — informational only.
 */
export function parseWsfeEvents(xml: string): WsfeCodeMsg[] {
  const eventsBlocks = extractAllBlocks(xml, "Events");
  const out: WsfeCodeMsg[] = [];
  for (const block of eventsBlocks) {
    for (const evt of extractAllBlocks(block, "Evt")) {
      const Code = extractTag(evt, "Code");
      const Msg = extractTag(evt, "Msg");
      if (Code != null) {
        out.push({ Code, Msg: Msg ?? "" });
      }
    }
  }
  return out;
}

export function wsfeEventsMeta(xml: string) {
  return parseWsfeEvents(xml).map((e) => ({
    event_code: e.Code,
    sanitized_event_message: sanitizeArcaMessage(e.Msg),
  }));
}

/** Fatal if any Err has non-zero Code. Events never fail alone. */
export function assertNoWsfeErrors(xml: string, method: string): void {
  const errors = parseWsfeErrors(xml).filter((e) => e.Code !== "0");
  if (errors.length === 0) return;
  const primary = errors[0];
  const extra =
    errors.length > 1
      ? ` (+${errors.length - 1} more)`
      : "";
  throw new ArcaSanitizedError(
    "WSFE_ERROR",
    "wsfe",
    `${method} ARCA error ${primary.Code}: ${sanitizeArcaMessage(primary.Msg)}${extra}`
  );
}

function authXml(ticket: WsaaTicket, cuit: string): string {
  return (
    `<ar:Auth>` +
    `<ar:Token>${ticket.token}</ar:Token>` +
    `<ar:Sign>${ticket.sign}</ar:Sign>` +
    `<ar:Cuit>${cuit}</ar:Cuit>` +
    `</ar:Auth>`
  );
}

function soapEnvelope(innerBody: string): string {
  return (
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ` +
    `xmlns:ar="${WSFE_NS}">` +
    `<soap:Header/>` +
    `<soap:Body>${innerBody}</soap:Body>` +
    `</soap:Envelope>`
  );
}

async function wsfeCall(
  config: ArcaHomologationConfig,
  method: string,
  bodyInner: string,
  options?: { allowArcaErrors?: boolean }
): Promise<string> {
  const ticket = await getValidTa(config);
  const envelope = soapEnvelope(
    `<ar:${method}>${authXml(ticket, config.representedCuit)}${bodyInner}</ar:${method}>`
  );

  let res: Response;
  try {
    res = await fetch(config.wsfeUrl, {
      method: "POST",
      headers: {
        "Content-Type": "text/xml; charset=utf-8",
        SOAPAction: `${WSFE_NS}${method}`,
      },
      body: envelope,
    });
  } catch (e) {
    throw new ArcaSanitizedError(
      "WSFE_NETWORK",
      "wsfe",
      `WSFE network error: ${sanitizeArcaMessage(String((e as Error).message || e))}`
    );
  }

  const text = await res.text();
  if (!res.ok) {
    throw new ArcaSanitizedError(
      "WSFE_HTTP",
      "wsfe",
      `WSFE HTTP ${res.status}: SOAP body omitted`
    );
  }

  const fault = extractTag(text, "faultstring");
  if (fault) {
    throw new ArcaSanitizedError(
      "WSFE_FAULT",
      "wsfe",
      `WSFE fault: ${sanitizeArcaMessage(fault)}`
    );
  }

  if (!options?.allowArcaErrors) {
    assertNoWsfeErrors(text, method);
  }
  return text;
}

/** Low-level POST for methods that must parse Errors/Resultado themselves. */
export async function wsfeCallAllowErrors(
  config: ArcaHomologationConfig,
  method: string,
  bodyInner: string
): Promise<string> {
  return wsfeCall(config, method, bodyInner, { allowArcaErrors: true });
}

export type FeDummyResult = {
  AppServer: string | null;
  DbServer: string | null;
  AuthServer: string | null;
};

export async function feDummy(config: ArcaHomologationConfig): Promise<FeDummyResult> {
  const ticket = await getValidTa(config);
  const envelope = soapEnvelope(
    `<ar:FEDummy>${authXml(ticket, config.representedCuit)}</ar:FEDummy>`
  );

  let res: Response;
  try {
    res = await fetch(config.wsfeUrl, {
      method: "POST",
      headers: {
        "Content-Type": "text/xml; charset=utf-8",
        SOAPAction: `${WSFE_NS}FEDummy`,
      },
      body: envelope,
    });
  } catch (e) {
    throw new ArcaSanitizedError(
      "WSFE_NETWORK",
      "fedummy",
      `FEDummy network error: ${sanitizeArcaMessage(String((e as Error).message || e))}`
    );
  }
  const text = await res.text();
  if (!res.ok) {
    throw new ArcaSanitizedError(
      "WSFE_HTTP",
      "fedummy",
      `FEDummy HTTP ${res.status}: SOAP body omitted`
    );
  }

  let xml = text;
  if (/FEDummy|AppServer/i.test(text) === false || extractTag(text, "faultstring")) {
    const bare = soapEnvelope(`<ar:FEDummy/>`);
    const res2 = await fetch(config.wsfeUrl, {
      method: "POST",
      headers: {
        "Content-Type": "text/xml; charset=utf-8",
        SOAPAction: `${WSFE_NS}FEDummy`,
      },
      body: bare,
    });
    xml = await res2.text();
    if (!res2.ok) {
      throw new ArcaSanitizedError(
        "WSFE_HTTP",
        "fedummy",
        `FEDummy HTTP ${res2.status}: SOAP body omitted`
      );
    }
  }

  const fault = extractTag(xml, "faultstring");
  if (fault) {
    throw new ArcaSanitizedError(
      "WSFE_FAULT",
      "fedummy",
      `FEDummy fault: ${sanitizeArcaMessage(fault)}`
    );
  }
  assertNoWsfeErrors(xml, "FEDummy");

  const result: FeDummyResult = {
    AppServer: extractTag(xml, "AppServer"),
    DbServer: extractTag(xml, "DbServer"),
    AuthServer: extractTag(xml, "AuthServer"),
  };

  if (!result.AppServer || !result.DbServer || !result.AuthServer) {
    throw new ArcaSanitizedError(
      "FEDUMMY_INCOMPLETE",
      "fedummy",
      "FEDummy incomplete: missing AppServer/DbServer/AuthServer"
    );
  }
  return result;
}

export type CatalogRow = Record<string, string | null>;

function rowsFromXml(xml: string, itemTag: string, fields: string[]): CatalogRow[] {
  return extractAllBlocks(xml, itemTag).map((block) => {
    const row: CatalogRow = {};
    for (const f of fields) row[f] = extractTag(block, f);
    return row;
  });
}

export async function feParamGetTiposCbte(config: ArcaHomologationConfig) {
  const xml = await wsfeCall(config, "FEParamGetTiposCbte", "");
  return rowsFromXml(xml, "CbteTipo", ["Id", "Desc", "FchDesde", "FchHasta"]);
}

export async function feParamGetTiposDoc(config: ArcaHomologationConfig) {
  const xml = await wsfeCall(config, "FEParamGetTiposDoc", "");
  return rowsFromXml(xml, "DocTipo", ["Id", "Desc", "FchDesde", "FchHasta"]);
}

export async function feParamGetTiposMonedas(config: ArcaHomologationConfig) {
  const xml = await wsfeCall(config, "FEParamGetTiposMonedas", "");
  return rowsFromXml(xml, "Moneda", ["Id", "Desc", "FchDesde", "FchHasta"]);
}

export async function feParamGetCondicionIvaReceptor(
  config: ArcaHomologationConfig
) {
  const xml = await wsfeCall(config, "FEParamGetCondicionIvaReceptor", "");
  const rows =
    rowsFromXml(xml, "CondicionIvaReceptor", [
      "Id",
      "Desc",
      "FchDesde",
      "FchHasta",
    ]).length > 0
      ? rowsFromXml(xml, "CondicionIvaReceptor", [
          "Id",
          "Desc",
          "FchDesde",
          "FchHasta",
        ])
      : rowsFromXml(xml, "CondicionIVAReceptor", [
          "Id",
          "Desc",
          "FchDesde",
          "FchHasta",
        ]);
  if (rows.length === 0) {
    throw new ArcaSanitizedError(
      "CONDICION_IVA_EMPTY",
      "wsfe",
      "FEParamGetCondicionIvaReceptor returned no rows"
    );
  }
  return rows;
}

export type PtoVentaRow = {
  Nro: string | null;
  EmisionTipo: string | null;
  Bloqueado: string | null;
  FchBaja: string | null;
};

/**
 * Returns [] only when ARCA succeeded (no fatal Errors) and ResultGet has
 * zero PtoVenta rows.
 */
export async function feParamGetPtosVenta(
  config: ArcaHomologationConfig
): Promise<PtoVentaRow[]> {
  const xml = await wsfeCall(config, "FEParamGetPtosVenta", "");
  return extractAllBlocks(xml, "PtoVenta").map((block) => ({
    Nro: extractTag(block, "Nro"),
    EmisionTipo: extractTag(block, "EmisionTipo"),
    Bloqueado: extractTag(block, "Bloqueado"),
    FchBaja: extractTag(block, "FchBaja"),
  }));
}

export type FeCompConsultarResult = {
  found: boolean;
  Resultado: string | null;
  CAE: string | null;
  CAEFchVto: string | null;
  CbteDesde: number | null;
  CbteHasta: number | null;
  ImpTotal: string | null;
  errors: WsfeCodeMsg[];
  observations: WsfeCodeMsg[];
};

export async function feCompConsultar(
  config: ArcaHomologationConfig,
  ptoVta: number,
  cbteTipo: number,
  cbteNro: number
): Promise<FeCompConsultarResult> {
  const xml = await wsfeCallAllowErrors(
    config,
    "FECompConsultar",
    `<ar:FeCompConsReq>` +
      `<ar:CbteTipo>${cbteTipo}</ar:CbteTipo>` +
      `<ar:CbteNro>${cbteNro}</ar:CbteNro>` +
      `<ar:PtoVta>${ptoVta}</ar:PtoVta>` +
      `</ar:FeCompConsReq>`
  );

  const errors = parseWsfeErrors(xml).filter((e) => e.Code !== "0");
  const cae = extractTag(xml, "CodAutorizacion") || extractTag(xml, "CAE");
  const resultado = extractTag(xml, "Resultado");
  const obsBlocks = extractAllBlocks(xml, "Obs");
  const observations = obsBlocks.map((b) => ({
    Code: extractTag(b, "Code") ?? "",
    Msg: extractTag(b, "Msg") ?? "",
  }));

  const cbteDesdeRaw = extractTag(xml, "CbteDesde");
  const cbteHastaRaw = extractTag(xml, "CbteHasta");

  return {
    found: Boolean(cae) || resultado === "A",
    Resultado: resultado,
    CAE: cae,
    CAEFchVto: extractTag(xml, "FchVto") || extractTag(xml, "CAEFchVto"),
    CbteDesde: cbteDesdeRaw != null ? Number(cbteDesdeRaw) : null,
    CbteHasta: cbteHastaRaw != null ? Number(cbteHastaRaw) : null,
    ImpTotal: extractTag(xml, "ImpTotal"),
    errors,
    observations,
  };
}

export type UltimoAutorizado = {
  PtoVenta: number;
  CbteTipo: number;
  CbteNro: number;
};

export async function feCompUltimoAutorizado(
  config: ArcaHomologationConfig,
  ptoVenta: number,
  cbteTipo: number
): Promise<UltimoAutorizado> {
  const xml = await wsfeCall(
    config,
    "FECompUltimoAutorizado",
    `<ar:PtoVta>${ptoVenta}</ar:PtoVta><ar:CbteTipo>${cbteTipo}</ar:CbteTipo>`
  );
  // wsfeCall already throws on ARCA Errors — never coerce those to CbteNro=null.
  const nroRaw = extractTag(xml, "CbteNro");
  if (nroRaw == null || nroRaw === "") {
    throw new ArcaSanitizedError(
      "WSFE_INCOMPLETE",
      "wsfe",
      `FECompUltimoAutorizado missing CbteNro for PtoVenta=${ptoVenta} CbteTipo=${cbteTipo}`
    );
  }
  const CbteNro = Number(nroRaw);
  if (!Number.isFinite(CbteNro)) {
    throw new ArcaSanitizedError(
      "WSFE_INCOMPLETE",
      "wsfe",
      `FECompUltimoAutorizado invalid CbteNro for PtoVenta=${ptoVenta}`
    );
  }
  return {
    PtoVenta: ptoVenta,
    CbteTipo: cbteTipo,
    CbteNro,
  };
}

export type PosProbeRow = {
  pto_venta: number;
  status: "PASS" | "ARCA_ERROR";
  arca_error_code: string | null;
  sanitized_error_message: string | null;
  ultimo_comprobante: number | null;
};

/**
 * Read-only homologation probe: FECompUltimoAutorizado only.
 * Does not call FEParamGetPtosVenta / FECAESolicitar / FECompConsultar.
 */
export async function probeHomologationPos(
  config: ArcaHomologationConfig,
  points: readonly number[] = [1, 2, 10],
  cbteTipo = 11
): Promise<PosProbeRow[]> {
  const rows: PosProbeRow[] = [];
  for (const pto of points) {
    try {
      const ult = await feCompUltimoAutorizado(config, pto, cbteTipo);
      rows.push({
        pto_venta: pto,
        status: "PASS",
        arca_error_code: null,
        sanitized_error_message: null,
        ultimo_comprobante: ult.CbteNro,
      });
    } catch (e) {
      const err = e as ArcaSanitizedError;
      const codeMatch =
        typeof err?.message === "string"
          ? err.message.match(/ARCA error (\d+)/i)
          : null;
      rows.push({
        pto_venta: pto,
        status: "ARCA_ERROR",
        arca_error_code: codeMatch?.[1] ?? err?.code ?? "WSFE_ERROR",
        sanitized_error_message: sanitizeArcaMessage(
          String(err?.message || e)
        ),
        ultimo_comprobante: null,
      });
    }
  }
  return rows;
}

/** Explicitly forbidden — do not implement callers. */
export function feCaeSolicitarForbidden(): never {
  throw new ArcaSanitizedError(
    "FECAESOLICITAR_FORBIDDEN",
    "wsfe",
    "FECAESolicitar is not authorized in this phase"
  );
}
