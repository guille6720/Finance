/**
 * Homologation-only durable TA cache for local consecutive live runners.
 * Stored under LOCALAPPDATA (not OneDrive, not git). Never logs token/sign.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { TA_REFRESH_SKEW_MS } from "./constants";
import type { ArcaHomologationConfig } from "./config";
import type { WsaaTicket } from "./wsaa";
import { ArcaSanitizedError } from "./errors";

export const HOMO_TA_FILE_CACHE_STRATEGY =
  "LOCALAPPDATA_HOMOLOGATION_ONLY_TA_FILE" as const;

type FileEntry = {
  env: "homologation";
  service: "wsfe";
  /** SHA-256 of CUIT — never store raw CUIT */
  cuit_fp: string;
  generationTime: string;
  expirationTime: string;
  token: string;
  sign: string;
  expiresAtMs: number;
};

function cuitFingerprint(cuit: string): string {
  return crypto.createHash("sha256").update(`homo:${cuit}`).digest("hex");
}

/** Absolute path outside repo / OneDrive when LOCALAPPDATA is available. */
export function getHomoTaCachePath(): string {
  const base =
    process.env.ARCA_HOMO_TA_CACHE_DIR?.trim() ||
    process.env.LOCALAPPDATA ||
    path.join(os.homedir(), "AppData", "Local");
  return path.join(base, "contabilium-finance-arca-homo", "ta-cache.json");
}

export function isTaFresh(expiresAtMs: number, now = Date.now()): boolean {
  return expiresAtMs - TA_REFRESH_SKEW_MS > now;
}

function assertHomologationOnly(config: ArcaHomologationConfig): void {
  if (config.env !== "homologation") {
    throw new ArcaSanitizedError(
      "STOP_GUARD",
      "ta-cache",
      "File TA cache is homologation-only"
    );
  }
}

export function readHomoTaFileCache(
  config: ArcaHomologationConfig,
  now = Date.now()
): WsaaTicket | null {
  assertHomologationOnly(config);
  const p = getHomoTaCachePath();
  if (!fs.existsSync(p)) return null;
  try {
    const raw = JSON.parse(fs.readFileSync(p, "utf8")) as FileEntry;
    if (raw.env !== "homologation" || raw.service !== "wsfe") return null;
    if (raw.cuit_fp !== cuitFingerprint(config.representedCuit)) return null;
    if (!raw.token || !raw.sign || !raw.expirationTime) return null;
    if (!isTaFresh(raw.expiresAtMs, now)) return null;
    return {
      token: raw.token,
      sign: raw.sign,
      generationTime: raw.generationTime,
      expirationTime: raw.expirationTime,
      service: "wsfe",
    };
  } catch {
    return null;
  }
}

export function writeHomoTaFileCache(
  config: ArcaHomologationConfig,
  ticket: WsaaTicket
): void {
  assertHomologationOnly(config);
  const expiresAtMs = Date.parse(ticket.expirationTime);
  if (!Number.isFinite(expiresAtMs) || !isTaFresh(expiresAtMs)) {
    return; // do not persist expired/near-expiry
  }
  const dir = path.dirname(getHomoTaCachePath());
  fs.mkdirSync(dir, { recursive: true });
  const entry: FileEntry = {
    env: "homologation",
    service: "wsfe",
    cuit_fp: cuitFingerprint(config.representedCuit),
    generationTime: ticket.generationTime,
    expirationTime: ticket.expirationTime,
    token: ticket.token,
    sign: ticket.sign,
    expiresAtMs,
  };
  const tmp = `${getHomoTaCachePath()}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(entry), { mode: 0o600 });
  fs.renameSync(tmp, getHomoTaCachePath());
}

export function clearHomoTaFileCacheForTests(): void {
  const p = getHomoTaCachePath();
  try {
    if (fs.existsSync(p)) fs.unlinkSync(p);
  } catch {
    /* ignore */
  }
}

/** Safe metadata only — never token/sign. */
export function homoTaFileCacheMeta(): {
  strategy: typeof HOMO_TA_FILE_CACHE_STRATEGY;
  path_present: boolean;
  expires_at_ms: number | null;
  fresh: boolean | null;
} {
  const p = getHomoTaCachePath();
  if (!fs.existsSync(p)) {
    return {
      strategy: HOMO_TA_FILE_CACHE_STRATEGY,
      path_present: false,
      expires_at_ms: null,
      fresh: null,
    };
  }
  try {
    const raw = JSON.parse(fs.readFileSync(p, "utf8")) as FileEntry;
    return {
      strategy: HOMO_TA_FILE_CACHE_STRATEGY,
      path_present: true,
      expires_at_ms: raw.expiresAtMs ?? null,
      fresh: isTaFresh(raw.expiresAtMs),
    };
  } catch {
    return {
      strategy: HOMO_TA_FILE_CACHE_STRATEGY,
      path_present: true,
      expires_at_ms: null,
      fresh: false,
    };
  }
}
