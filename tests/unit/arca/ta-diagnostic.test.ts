import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import forge from "node-forge";
import {
  getArcaHomologationConfig,
  resetArcaEnvFileLoadedForTests,
} from "@/server/arca/config";
import {
  clearTaCacheForTests,
  clearTaMemoryCacheForTests,
  getValidTa,
  taCacheStats,
} from "@/server/arca/ta-cache";
import {
  clearHomoTaFileCacheForTests,
  getHomoTaCachePath,
  isTaFresh,
  readHomoTaFileCache,
  writeHomoTaFileCache,
} from "@/server/arca/ta-file-cache";
import { buildGateFailureReport } from "@/server/arca/gate-failure";
import { ArcaSanitizedError } from "@/server/arca/errors";
import {
  ARCA_WSAA_HOMO_URL,
  ARCA_WSFE_HOMO_URL,
} from "@/server/arca/constants";
import type { WsaaTicket } from "@/server/arca/wsaa";

function makeSelfSignedPemPair() {
  const keys = forge.pki.rsa.generateKeyPair(2048);
  const cert = forge.pki.createCertificate();
  cert.publicKey = keys.publicKey;
  cert.serialNumber = "01";
  cert.validity.notBefore = new Date(Date.now() - 60_000);
  cert.validity.notAfter = new Date(Date.now() + 24 * 60 * 60_000);
  const attrs = [{ name: "commonName", value: "TEST-HOMO" }];
  cert.setSubject(attrs);
  cert.setIssuer(attrs);
  cert.sign(keys.privateKey, forge.md.sha256.create());
  return {
    privateKeyPem: forge.pki.privateKeyToPem(keys.privateKey),
    certificatePem: forge.pki.certificateToPem(cert),
  };
}

describe("uncertain WSAA diagnostic + TA file reuse", () => {
  const original = { ...process.env };
  let tmpDir = "";

  beforeEach(() => {
    process.env = { ...original };
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "arca-ta-"));
    process.env.ARCA_HOMO_TA_CACHE_DIR = tmpDir;
    resetArcaEnvFileLoadedForTests();
    clearTaCacheForTests();
  });

  afterEach(() => {
    process.env = original;
    resetArcaEnvFileLoadedForTests();
    clearTaCacheForTests();
    try {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    } catch {
      /* ignore */
    }
    vi.unstubAllGlobals();
  });

  function homoConfig() {
    const pair = makeSelfSignedPemPair();
    process.env.ARCA_ENV = "homologation";
    process.env.ARCA_REPRESENTED_CUIT = "20111111112";
    process.env.ARCA_HOMO_PRIVATE_KEY_B64 = Buffer.from(pair.privateKeyPem).toString(
      "base64"
    );
    process.env.ARCA_HOMO_CERT_B64 = Buffer.from(pair.certificatePem).toString(
      "base64"
    );
    process.env.ARCA_HOMO_PTO_VENTA = "10";
    process.env.ARCA_WSAA_URL = ARCA_WSAA_HOMO_URL;
    process.env.ARCA_WSFE_URL = ARCA_WSFE_HOMO_URL;
    process.env.ARCA_WSAA_SERVICE = "wsfe";
    return getArcaHomologationConfig();
  }

  it("WSAA fault preserves sanitized ROOT_CAUSE and pre-issuance evidence", () => {
    const err = new ArcaSanitizedError(
      "WSAA_FAULT",
      "wsaa",
      "WSAA HTTP 500: coe.alreadyAuthenticated [soap:Server]"
    );
    const fail = buildGateFailureReport(err, { fecaeCallCount: 0 });
    expect(fail.BLOCKER).toBe("WSAA_FAULT");
    expect(fail.ROOT_CAUSE).toMatch(/coe\.alreadyAuthenticated/);
    expect(fail.STAGE).toBe("wsaa");
    expect(fail.WSAA_HOMOLOGATION).toBe("FAIL");
    expect(fail.FECAESOLICITAR_CALL_COUNT).toBe(0);
    expect(fail.FECAESOLICITAR_SENT).toBe("NO");
    expect(fail.AUTOMATIC_RETRY).toBe("NO");
    expect(fail.ROOT_CAUSE).not.toMatch(/token|sign|BEGIN |CUIT/i);
  });

  it("empty message still yields non-empty ROOT_CAUSE placeholder", () => {
    const err = new ArcaSanitizedError("WSAA_FAULT", "wsaa", "");
    const fail = buildGateFailureReport(err, { fecaeCallCount: 0 });
    expect(fail.ROOT_CAUSE.length).toBeGreaterThan(0);
    expect(fail.FECAESOLICITAR_SENT).toBe("NO");
  });

  it("expired TA is not reused", () => {
    expect(isTaFresh(Date.now() - 1000)).toBe(false);
    expect(isTaFresh(Date.now() + 120_000)).toBe(true);
    const config = homoConfig();
    const ticket: WsaaTicket = {
      token: "tok",
      sign: "sig",
      generationTime: new Date().toISOString(),
      expirationTime: new Date(Date.now() - 60_000).toISOString(),
      service: "wsfe",
    };
    writeHomoTaFileCache(config, ticket);
    // write skips near-expiry/expired
    expect(readHomoTaFileCache(config)).toBeNull();
  });

  it("valid TA is reused from file across memory clears (no LoginCms)", async () => {
    const config = homoConfig();
    const ticket: WsaaTicket = {
      token: "tok-file",
      sign: "sig-file",
      generationTime: new Date().toISOString(),
      expirationTime: new Date(Date.now() + 10 * 60_000).toISOString(),
      service: "wsfe",
    };
    writeHomoTaFileCache(config, ticket);
    expect(fs.existsSync(getHomoTaCachePath())).toBe(true);

    let loginCalls = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        loginCalls += 1;
        throw new Error("should not LoginCms");
      })
    );

    // Simulate a new Node process: empty memory, durable file retained.
    clearTaMemoryCacheForTests();
    const got = await getValidTa(config);
    expect(got.token).toBe("tok-file");
    expect(got.sign).toBe("sig-file");
    expect(loginCalls).toBe(0);
    expect(taCacheStats().file_cache.strategy).toBe(
      "LOCALAPPDATA_HOMOLOGATION_ONLY_TA_FILE"
    );
    expect(isTaFresh(Date.now() - 1)).toBe(false);
    expect(readHomoTaFileCache(config)?.token).toBe("tok-file");
  });

  it("Production cannot use homologation file cache write", () => {
    const config = homoConfig();
    const bad = { ...config, env: "production" as const };
    expect(() =>
      writeHomoTaFileCache(bad as unknown as typeof config, {
        token: "t",
        sign: "s",
        generationTime: "x",
        expirationTime: new Date(Date.now() + 600_000).toISOString(),
        service: "wsfe",
      })
    ).toThrow(/homologation-only/i);
  });

  it("no automatic retry field is always NO", () => {
    const fail = buildGateFailureReport(new Error("x"), { fecaeCallCount: 0 });
    expect(fail.AUTOMATIC_RETRY).toBe("NO");
  });
});
