import { TA_REFRESH_SKEW_MS } from "./constants";
import type { ArcaHomologationConfig } from "./config";
import { wsaaLoginCms, type WsaaTicket } from "./wsaa";
import {
  clearHomoTaFileCacheForTests,
  homoTaFileCacheMeta,
  HOMO_TA_FILE_CACHE_STRATEGY,
  readHomoTaFileCache,
  writeHomoTaFileCache,
} from "./ta-file-cache";

/**
 * In-process + optional homologation file TA cache.
 * File cache: LOCALAPPDATA only (not git, not OneDrive). Production never uses it.
 */
type CacheEntry = {
  ticket: WsaaTicket;
  expiresAtMs: number;
};

const cache = new Map<string, CacheEntry>();
const inflight = new Map<string, Promise<WsaaTicket>>();

function cacheKey(config: ArcaHomologationConfig): string {
  return `${config.env}:${config.representedCuit}:${config.wsaaService}`;
}

function isFresh(entry: CacheEntry, now = Date.now()): boolean {
  return entry.expiresAtMs - TA_REFRESH_SKEW_MS > now;
}

export function clearTaCacheForTests() {
  cache.clear();
  inflight.clear();
  clearHomoTaFileCacheForTests();
}

/** Clears in-process cache only (keeps durable homologation file). */
export function clearTaMemoryCacheForTests() {
  cache.clear();
  inflight.clear();
}

export async function getValidTa(config: ArcaHomologationConfig): Promise<WsaaTicket> {
  const key = cacheKey(config);
  const existing = cache.get(key);
  if (existing && isFresh(existing)) {
    return existing.ticket;
  }

  // Homologation-only: reuse durable local TA across Node processes.
  if (config.env === "homologation") {
    const fromFile = readHomoTaFileCache(config);
    if (fromFile) {
      const expiresAtMs = Date.parse(fromFile.expirationTime);
      cache.set(key, { ticket: fromFile, expiresAtMs });
      return fromFile;
    }
  }

  const pending = inflight.get(key);
  if (pending) return pending;

  const job = (async () => {
    const ticket = await wsaaLoginCms(config);
    const expiresAtMs = Date.parse(ticket.expirationTime);
    if (!Number.isFinite(expiresAtMs) || expiresAtMs <= Date.now()) {
      throw new Error("TA expired");
    }
    cache.set(key, { ticket, expiresAtMs });
    if (config.env === "homologation") {
      writeHomoTaFileCache(config, ticket);
    }
    return ticket;
  })();

  inflight.set(key, job);
  try {
    return await job;
  } finally {
    inflight.delete(key);
  }
}

export function taCacheStats() {
  const fileMeta =
    typeof process !== "undefined"
      ? homoTaFileCacheMeta()
      : {
          strategy: HOMO_TA_FILE_CACHE_STRATEGY,
          path_present: false,
          expires_at_ms: null,
          fresh: null,
        };
  return {
    entries: cache.size,
    inflight: inflight.size,
    limitation: "SERVERLESS_MEMORY_CACHE_IS_EPHEMERAL" as const,
    file_cache: fileMeta,
  };
}
