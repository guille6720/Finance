import { ArcaSanitizedError, sanitizeArcaMessage } from "./errors";
import { signTraCms } from "./cms";
import { buildLoginTicketRequest } from "./tra";
import type { ArcaHomologationConfig } from "./config";

export type WsaaTicket = {
  token: string;
  sign: string;
  generationTime: string;
  expirationTime: string;
  service: "wsfe";
};

function extractTag(xml: string, tag: string): string | null {
  const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, "i");
  const m = xml.match(re);
  return m ? m[1].trim() : null;
}

/** Plain or namespace-prefixed SOAP fault tags (e.g. soap:faultstring). */
function extractSoapTagged(xml: string, localName: string): string | null {
  const re = new RegExp(
    `<(?:[\\w.-]+:)?${localName}\\b[^>]*>([\\s\\S]*?)</(?:[\\w.-]+:)?${localName}>`,
    "i"
  );
  const m = xml.match(re);
  return m ? m[1].trim() : null;
}

/** Safe SOAP fault fields only — never returns raw envelope. */
export function extractSoapFault(xml: string): {
  faultcode: string | null;
  faultstring: string | null;
} {
  return {
    faultcode: extractSoapTagged(xml, "faultcode"),
    faultstring: extractSoapTagged(xml, "faultstring"),
  };
}

function buildLoginCmsEnvelope(cmsBase64: string): string {
  return (
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" ` +
    `xmlns:wsaa="http://wsaa.view.sua.dvadac.suba.ar/">` +
    `<soapenv:Header/>` +
    `<soapenv:Body>` +
    `<wsaa:loginCms>` +
    `<wsaa:in0>${cmsBase64}</wsaa:in0>` +
    `</wsaa:loginCms>` +
    `</soapenv:Body>` +
    `</soapenv:Envelope>`
  );
}

/** Exported for unit tests — never log return value. */
export function parseLoginTicketResponse(credentialsXml: string): WsaaTicket {
  // credentialsXml is the inner loginTicketResponse XML (may be XML-escaped once)
  const xml = credentialsXml
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, "&");

  const token = extractTag(xml, "token");
  const sign = extractTag(xml, "sign");
  const generationTime = extractTag(xml, "generationTime");
  const expirationTime = extractTag(xml, "expirationTime");

  if (!token || !sign || !generationTime || !expirationTime) {
    throw new ArcaSanitizedError(
      "WSAA_PARSE_FAILED",
      "wsaa",
      "WSAA response missing required ticket fields"
    );
  }

  const exp = Date.parse(expirationTime);
  if (!Number.isFinite(exp) || exp <= Date.now()) {
    throw new ArcaSanitizedError(
      "WSAA_EXPIRED",
      "wsaa",
      "WSAA ticket expiration is not in the future"
    );
  }

  return {
    token,
    sign,
    generationTime,
    expirationTime,
    service: "wsfe",
  };
}

function throwHttpFault(status: number, body: string): never {
  const { faultcode, faultstring } = extractSoapFault(body);
  if (faultstring) {
    const codePart = faultcode
      ? ` [${sanitizeArcaMessage(faultcode)}]`
      : "";
    throw new ArcaSanitizedError(
      "WSAA_FAULT",
      "wsaa",
      `WSAA HTTP ${status}: ${sanitizeArcaMessage(faultstring)}${codePart}`
    );
  }
  throw new ArcaSanitizedError(
    "WSAA_HTTP",
    "wsaa",
    `WSAA HTTP ${status}: SOAP fault could not be safely parsed`
  );
}

/**
 * WSAA LoginCms against homologation only.
 * Never logs token/sign/CMS.
 */
export async function wsaaLoginCms(
  config: ArcaHomologationConfig
): Promise<WsaaTicket> {
  if (config.wsaaService !== "wsfe") {
    throw new ArcaSanitizedError(
      "INVALID_WSAA_SERVICE",
      "wsaa",
      "Service must be wsfe"
    );
  }

  const tra = buildLoginTicketRequest("wsfe");
  const cms = signTraCms(tra.xml, config.privateKeyPem, config.certificatePem);
  const body = buildLoginCmsEnvelope(cms);

  let res: Response;
  try {
    res = await fetch(config.wsaaUrl, {
      method: "POST",
      headers: {
        "Content-Type": "text/xml; charset=utf-8",
        SOAPAction: "",
      },
      body,
    });
  } catch (e) {
    throw new ArcaSanitizedError(
      "WSAA_NETWORK",
      "wsaa",
      `WSAA network error: ${sanitizeArcaMessage(String((e as Error).message || e))}`
    );
  }

  const text = await res.text();

  // Extract SOAP fault before HTTP status branch so 500 Faults are diagnosable.
  const soapFault = extractSoapFault(text);

  if (!res.ok) {
    throwHttpFault(res.status, text);
  }

  if (soapFault.faultstring && !extractSoapTagged(text, "loginCmsReturn")) {
    throw new ArcaSanitizedError(
      "WSAA_FAULT",
      "wsaa",
      `WSAA fault: ${sanitizeArcaMessage(soapFault.faultstring)}`
    );
  }

  const loginReturn =
    extractSoapTagged(text, "loginCmsReturn") ||
    extractTag(text, "return");

  if (!loginReturn) {
    throw new ArcaSanitizedError(
      "WSAA_EMPTY",
      "wsaa",
      "WSAA empty credentials: response had no loginCmsReturn"
    );
  }

  return parseLoginTicketResponse(loginReturn);
}

/** Safe metadata for reports — never includes token/sign. */
export function wsaaTicketMeta(ticket: WsaaTicket) {
  return {
    service: ticket.service,
    generationTime: ticket.generationTime,
    expirationTime: ticket.expirationTime,
    token_present: Boolean(ticket.token),
    sign_present: Boolean(ticket.sign),
  };
}
