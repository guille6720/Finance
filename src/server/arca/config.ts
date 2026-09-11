import fs from "node:fs";
import path from "node:path";
import { ArcaSanitizedError } from "./errors";
import {
  ARCA_PRODUCTION_HOST_FRAGMENTS,
  ARCA_WSAA_HOMO_URL,
  ARCA_WSAA_SERVICE,
  ARCA_WSFE_HOMO_URL,
} from "./constants";

export type ArcaHomologationConfig = {
  env: "homologation";
  representedCuit: string;
  privateKeyPem: string;
  certificatePem: string;
  wsaaService: "wsfe";
  wsaaUrl: string;
  wsfeUrl: string;
  certAlias: string | null;
  /** Explicit homologation point of sale (1..99998). */
  homoPtoVenta: number;
};

let fileLoaded = false;

/** Load gitignored .env.arca.homo.local into process.env (server-only). Never logs values. */
export function loadArcaHomoEnvFile(cwd = process.cwd()): void {
  if (fileLoaded) return;
  fileLoaded = true;
  const p = path.join(cwd, ".env.arca.homo.local");
  if (!fs.existsSync(p)) return;
  const text = fs.readFileSync(p, "utf8");
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (process.env[key] === undefined) process.env[key] = value;
  }
}

export function resetArcaEnvFileLoadedForTests() {
  fileLoaded = false;
}

function decodeB64ToUtf8(label: string, b64: string): string {
  try {
    const buf = Buffer.from(b64.replace(/\s+/g, ""), "base64");
    if (buf.length < 32) {
      throw new Error("too short");
    }
    return buf.toString("utf8");
  } catch {
    throw new ArcaSanitizedError(
      "INVALID_B64",
      "config",
      `${label} is missing or not valid Base64`
    );
  }
}

function assertPem(label: string, pem: string, kind: "PRIVATE KEY" | "CERTIFICATE") {
  const ok =
    kind === "PRIVATE KEY"
      ? /-----BEGIN (?:RSA )?PRIVATE KEY-----/.test(pem) &&
        /-----END (?:RSA )?PRIVATE KEY-----/.test(pem)
      : /-----BEGIN CERTIFICATE-----/.test(pem) &&
        /-----END CERTIFICATE-----/.test(pem);
  if (!ok) {
    throw new ArcaSanitizedError(
      "INVALID_PEM",
      "config",
      `${label} does not look like a PEM ${kind}`
    );
  }
}

function assertHomologationUrl(label: string, url: string, expected: string) {
  if (url !== expected) {
    throw new ArcaSanitizedError(
      "FORBIDDEN_ENDPOINT",
      "config",
      `${label} must equal the homologation endpoint`
    );
  }
  for (const frag of ARCA_PRODUCTION_HOST_FRAGMENTS) {
    if (url.includes(frag) && !url.includes("wsaahomo") && !url.includes("wswhomo")) {
      throw new ArcaSanitizedError(
        "PRODUCTION_ENDPOINT_FORBIDDEN",
        "config",
        `${label} resolves to a production host fragment`
      );
    }
  }
  // Extra belt: reject non-homo AFIP hosts
  if (/wsaa\.afip\.gov\.ar/i.test(url) && !/wsaahomo/i.test(url)) {
    throw new ArcaSanitizedError(
      "PRODUCTION_ENDPOINT_FORBIDDEN",
      "config",
      `${label} must not use production WSAA`
    );
  }
  if (/servicios1\.afip\.gov\.ar/i.test(url)) {
    throw new ArcaSanitizedError(
      "PRODUCTION_ENDPOINT_FORBIDDEN",
      "config",
      `${label} must not use production WSFE`
    );
  }
}

/** Homologation POS: integer 1..99998. Fail closed. */
export function parseArcaHomoPtoVenta(raw: string | undefined): number {
  const s = String(raw ?? "").trim();
  if (!s) {
    throw new ArcaSanitizedError(
      "MISSING_HOMO_PTO_VENTA",
      "config",
      "ARCA_HOMO_PTO_VENTA is required for homologation"
    );
  }
  if (!/^\d+$/.test(s)) {
    throw new ArcaSanitizedError(
      "INVALID_HOMO_PTO_VENTA",
      "config",
      "ARCA_HOMO_PTO_VENTA must be an integer"
    );
  }
  const n = Number(s);
  if (!Number.isInteger(n) || n < 1 || n > 99998) {
    throw new ArcaSanitizedError(
      "INVALID_HOMO_PTO_VENTA",
      "config",
      "ARCA_HOMO_PTO_VENTA must be an integer in range 1..99998"
    );
  }
  return n;
}

/**
 * Resolve homologation-only ARCA config.
 * Requires ARCA_ENV=homologation and server secrets.
 * Never returns token/sign/key material to callers beyond PEMs for signing.
 */
export function getArcaHomologationConfig(): ArcaHomologationConfig {
  loadArcaHomoEnvFile();

  const arcaEnv = process.env.FISCAL_GATEWAY_ENV ?? process.env.ARCA_ENV ?? "disabled";
  if (arcaEnv === "production") {
    throw new ArcaSanitizedError(
      "ARCA_PRODUCTION_BLOCKED",
      "config",
      "ARCA production is not authorized"
    );
  }
  if (arcaEnv !== "homologation") {
    throw new ArcaSanitizedError(
      "ARCA_NOT_HOMOLOGATION",
      "config",
      "ARCA_ENV must be homologation to use the fiscal gateway"
    );
  }

  const cuit = (process.env.ARCA_REPRESENTED_CUIT || "").trim();
  if (!/^\d{11}$/.test(cuit)) {
    throw new ArcaSanitizedError(
      "INVALID_CUIT",
      "config",
      "ARCA_REPRESENTED_CUIT must be exactly 11 digits"
    );
  }

  const keyB64 = process.env.ARCA_HOMO_PRIVATE_KEY_B64 || "";
  const certB64 = process.env.ARCA_HOMO_CERT_B64 || "";
  if (!keyB64 || !certB64) {
    throw new ArcaSanitizedError(
      "MISSING_HOMO_SECRETS",
      "config",
      "ARCA_HOMO_PRIVATE_KEY_B64 and ARCA_HOMO_CERT_B64 are required"
    );
  }

  const privateKeyPem = decodeB64ToUtf8("ARCA_HOMO_PRIVATE_KEY_B64", keyB64);
  const certificatePem = decodeB64ToUtf8("ARCA_HOMO_CERT_B64", certB64);
  assertPem("ARCA_HOMO_PRIVATE_KEY_B64", privateKeyPem, "PRIVATE KEY");
  assertPem("ARCA_HOMO_CERT_B64", certificatePem, "CERTIFICATE");

  const wsaaService = (process.env.ARCA_WSAA_SERVICE || ARCA_WSAA_SERVICE).trim();
  if (wsaaService !== "wsfe") {
    throw new ArcaSanitizedError(
      "INVALID_WSAA_SERVICE",
      "config",
      "ARCA_WSAA_SERVICE must equal wsfe"
    );
  }

  const wsaaUrl = (process.env.ARCA_WSAA_URL || ARCA_WSAA_HOMO_URL).trim();
  const wsfeUrl = (process.env.ARCA_WSFE_URL || ARCA_WSFE_HOMO_URL).trim();
  assertHomologationUrl("ARCA_WSAA_URL", wsaaUrl, ARCA_WSAA_HOMO_URL);
  assertHomologationUrl("ARCA_WSFE_URL", wsfeUrl, ARCA_WSFE_HOMO_URL);

  const homoPtoVenta = parseArcaHomoPtoVenta(process.env.ARCA_HOMO_PTO_VENTA);

  return {
    env: "homologation",
    representedCuit: cuit,
    privateKeyPem,
    certificatePem,
    wsaaService: "wsfe",
    wsaaUrl,
    wsfeUrl,
    certAlias: process.env.ARCA_CERT_ALIAS?.trim() || null,
    homoPtoVenta,
  };
}

export function tryGetArcaHomologationConfig():
  | { ok: true; config: ArcaHomologationConfig }
  | { ok: false; error: ArcaSanitizedError } {
  try {
    return { ok: true, config: getArcaHomologationConfig() };
  } catch (e) {
    if (e instanceof ArcaSanitizedError) return { ok: false, error: e };
    return {
      ok: false,
      error: new ArcaSanitizedError("CONFIG_ERROR", "config", "Configuration failed"),
    };
  }
}
