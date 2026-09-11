import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import forge from "node-forge";
import {
  buildLoginTicketRequest,
  formatAfipDateTime,
} from "@/server/arca/tra";
import { sanitizeArcaMessage, ArcaSanitizedError } from "@/server/arca/errors";
import {
  getArcaHomologationConfig,
  resetArcaEnvFileLoadedForTests,
  parseArcaHomoPtoVenta,
} from "@/server/arca/config";
import { clearTaCacheForTests, getValidTa, taCacheStats } from "@/server/arca/ta-cache";
import {
  feCaeSolicitarForbidden,
  parseWsfeErrors,
  parseWsfeEvents,
  assertNoWsfeErrors,
  feParamGetPtosVenta,
  probeHomologationPos,
  feCompUltimoAutorizado,
} from "@/server/arca/wsfe";
import { validateCertKeyMatch } from "@/server/arca/cert";
import { signTraCms } from "@/server/arca/cms";
import {
  parseLoginTicketResponse,
  wsaaLoginCms,
  extractSoapFault,
} from "@/server/arca/wsaa";

/** In-memory self-signed pair — no OpenSSL CLI required. */
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

describe("ARCA homologation unit helpers", () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env = { ...original };
    resetArcaEnvFileLoadedForTests();
    clearTaCacheForTests();
    delete process.env.ARCA_ENV;
    delete process.env.FISCAL_GATEWAY_ENV;
    delete process.env.ARCA_REPRESENTED_CUIT;
    delete process.env.ARCA_HOMO_PRIVATE_KEY_B64;
    delete process.env.ARCA_HOMO_CERT_B64;
    delete process.env.ARCA_WSAA_URL;
  });

  afterEach(() => {
    process.env = original;
    resetArcaEnvFileLoadedForTests();
    clearTaCacheForTests();
  });

  it("formats AFIP datetime with offset", () => {
    const s = formatAfipDateTime(new Date("2026-09-10T16:00:00.000Z"), -180);
    expect(s).toMatch(/2026-09-10T13:00:00\.000-03:00/);
  });

  it("builds TRA with service wsfe", () => {
    const tra = buildLoginTicketRequest("wsfe", new Date("2026-09-10T16:00:00.000Z"));
    expect(tra.service).toBe("wsfe");
    expect(tra.xml).toContain("<service>wsfe</service>");
    expect(tra.xml).toContain("<uniqueId>");
    expect(tra.xml).not.toContain("wsfev1");
  });

  it("hardens TRA generationTime with 10-minute clock skew", () => {
    const now = new Date("2026-09-10T16:00:00.000Z");
    const validitySeconds = 600;
    const tra = buildLoginTicketRequest("wsfe", now, validitySeconds);

    const expectedGen = formatAfipDateTime(new Date(now.getTime() - 10 * 60_000));
    const expectedExp = formatAfipDateTime(
      new Date(now.getTime() + validitySeconds * 1000)
    );

    expect(tra.generationTime).toBe(expectedGen);
    expect(tra.expirationTime).toBe(expectedExp);
    expect(tra.generationTime).toBe("2026-09-10T12:50:00.000-03:00");
    expect(tra.expirationTime).toBe("2026-09-10T13:10:00.000-03:00");
    expect(tra.generationTime).toMatch(
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}-03:00$/
    );
    expect(tra.expirationTime).toMatch(
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}-03:00$/
    );

    const genMs = Date.parse(tra.generationTime);
    const expMs = Date.parse(tra.expirationTime);
    expect(genMs).toBe(now.getTime() - 10 * 60_000);
    expect(expMs).toBeGreaterThan(now.getTime());
    expect(genMs).toBeLessThan(expMs);
    expect(tra.xml).toContain(`<generationTime>${expectedGen}</generationTime>`);
    expect(tra.xml).toContain(`<expirationTime>${expectedExp}</expirationTime>`);
  });

  it("sanitizes PEM and long base64 from errors", () => {
    const raw =
      "fail -----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY----- " +
      "AAAA".repeat(40);
    const s = sanitizeArcaMessage(raw);
    expect(s).not.toContain("BEGIN PRIVATE KEY");
    expect(s).toContain("[REDACTED");
  });

  it("rejects config when ARCA_ENV is not homologation", () => {
    process.env.ARCA_ENV = "disabled";
    expect(() => getArcaHomologationConfig()).toThrow(ArcaSanitizedError);
  });

  it("rejects production ARCA env", () => {
    process.env.ARCA_ENV = "production";
    expect(() => getArcaHomologationConfig()).toThrow(/production/i);
  });

  it("validates CUIT length", () => {
    process.env.ARCA_ENV = "homologation";
    process.env.ARCA_REPRESENTED_CUIT = "123";
    process.env.ARCA_HOMO_PRIVATE_KEY_B64 = Buffer.from(
      "-----BEGIN PRIVATE KEY-----\nMII\n-----END PRIVATE KEY-----\n"
    ).toString("base64");
    process.env.ARCA_HOMO_CERT_B64 = Buffer.from(
      "-----BEGIN CERTIFICATE-----\nMII\n-----END CERTIFICATE-----\n"
    ).toString("base64");
    expect(() => getArcaHomologationConfig()).toThrow(/11 digits/i);
  });

  it("rejects production WSAA URL", () => {
    const pair = makeSelfSignedPemPair();
    process.env.ARCA_ENV = "homologation";
    process.env.ARCA_REPRESENTED_CUIT = "20111111112";
    process.env.ARCA_HOMO_PRIVATE_KEY_B64 = Buffer.from(pair.privateKeyPem).toString(
      "base64"
    );
    process.env.ARCA_HOMO_CERT_B64 = Buffer.from(pair.certificatePem).toString("base64");
    process.env.ARCA_HOMO_PTO_VENTA = "10";
    process.env.ARCA_WSAA_URL = "https://wsaa.afip.gov.ar/ws/services/LoginCms";
    expect(() => getArcaHomologationConfig()).toThrow(/homologation endpoint|forbidden|Production/i);
  });

  it("matches cert and key and returns fingerprint metadata", () => {
    const pair = makeSelfSignedPemPair();
    const meta = validateCertKeyMatch(pair.privateKeyPem, pair.certificatePem);
    expect(meta.key_match).toBe(true);
    expect(meta.fingerprint_sha256).toMatch(/^[a-f0-9]{64}$/);
    expect(meta.not_before).toBeTruthy();
    expect(meta.not_after).toBeTruthy();
  });

  it("signs TRA CMS to base64 without throwing", () => {
    const pair = makeSelfSignedPemPair();
    const tra = buildLoginTicketRequest("wsfe");
    const cms = signTraCms(tra.xml, pair.privateKeyPem, pair.certificatePem);
    expect(cms.length).toBeGreaterThan(100);
    expect(cms).toMatch(/^[A-Za-z0-9+/=]+$/);
  });

  it("TA cache single-flight reuses one refresh", async () => {
    const pair = makeSelfSignedPemPair();
    process.env.ARCA_ENV = "homologation";
    process.env.ARCA_REPRESENTED_CUIT = "20111111112";
    process.env.ARCA_HOMO_PRIVATE_KEY_B64 = Buffer.from(pair.privateKeyPem).toString(
      "base64"
    );
    process.env.ARCA_HOMO_CERT_B64 = Buffer.from(pair.certificatePem).toString("base64");
    process.env.ARCA_HOMO_PTO_VENTA = "10";
    const config = getArcaHomologationConfig();

    let calls = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        calls += 1;
        const exp = new Date(Date.now() + 5 * 60_000).toISOString();
        const credentials =
          `<loginTicketResponse><header><generationTime>2026-01-01T00:00:00.000-03:00</generationTime>` +
          `<expirationTime>${exp}</expirationTime></header><credentials>` +
          `<token>tok-${calls}</token><sign>sig-${calls}</sign></credentials></loginTicketResponse>`;
        const body =
          `<?xml version="1.0"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">` +
          `<soapenv:Body><loginCmsReturn>${credentials
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")}</loginCmsReturn></soapenv:Body></soapenv:Envelope>`;
        return new Response(body, { status: 200 });
      })
    );

    const [a, b] = await Promise.all([getValidTa(config), getValidTa(config)]);
    expect(a.token).toBe(b.token);
    expect(calls).toBe(1);
    const again = await getValidTa(config);
    expect(again.token).toBe(a.token);
    expect(calls).toBe(1);
    expect(taCacheStats().limitation).toBe("SERVERLESS_MEMORY_CACHE_IS_EPHEMERAL");
    vi.unstubAllGlobals();
  });

  it("forbids FECAESolicitar", () => {
    expect(() => feCaeSolicitarForbidden()).toThrow(/not authorized/i);
  });

  it("validates ARCA_HOMO_PTO_VENTA range", () => {
    expect(parseArcaHomoPtoVenta("10")).toBe(10);
    expect(parseArcaHomoPtoVenta("1")).toBe(1);
    expect(parseArcaHomoPtoVenta("99998")).toBe(99998);
    expect(() => parseArcaHomoPtoVenta(undefined)).toThrow(/required/i);
    expect(() => parseArcaHomoPtoVenta("")).toThrow(/required/i);
    expect(() => parseArcaHomoPtoVenta("0")).toThrow(/1\.\.99998/);
    expect(() => parseArcaHomoPtoVenta("99999")).toThrow(/1\.\.99998/);
    expect(() => parseArcaHomoPtoVenta("1.5")).toThrow(/integer/i);
    expect(() => parseArcaHomoPtoVenta("abc")).toThrow(/integer/i);
  });

  it("parses WSAA loginTicketResponse XML", () => {
    const exp = new Date(Date.now() + 120_000).toISOString();
    const xml =
      `<loginTicketResponse><header>` +
      `<generationTime>2026-01-01T00:00:00.000-03:00</generationTime>` +
      `<expirationTime>${exp}</expirationTime></header>` +
      `<credentials><token>abc</token><sign>xyz</sign></credentials></loginTicketResponse>`;
    const t = parseLoginTicketResponse(xml);
    expect(t.token).toBe("abc");
    expect(t.sign).toBe("xyz");
    expect(t.service).toBe("wsfe");
  });

  it("rejects expired WSAA ticket XML", () => {
    const exp = new Date(Date.now() - 60_000).toISOString();
    const xml =
      `<loginTicketResponse><header>` +
      `<generationTime>2026-01-01T00:00:00.000-03:00</generationTime>` +
      `<expirationTime>${exp}</expirationTime></header>` +
      `<credentials><token>abc</token><sign>xyz</sign></credentials></loginTicketResponse>`;
    expect(() => parseLoginTicketResponse(xml)).toThrow(/expiration/i);
  });

  it("refreshes TA after expiry", async () => {
    const pair = makeSelfSignedPemPair();
    process.env.ARCA_ENV = "homologation";
    process.env.ARCA_REPRESENTED_CUIT = "20111111112";
    process.env.ARCA_HOMO_PRIVATE_KEY_B64 = Buffer.from(pair.privateKeyPem).toString(
      "base64"
    );
    process.env.ARCA_HOMO_CERT_B64 = Buffer.from(pair.certificatePem).toString("base64");
    process.env.ARCA_HOMO_PTO_VENTA = "10";
    const config = getArcaHomologationConfig();

    let calls = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        calls += 1;
        const exp =
          calls === 1
            ? new Date(Date.now() + 500).toISOString()
            : new Date(Date.now() + 5 * 60_000).toISOString();
        const credentials =
          `<loginTicketResponse><header><generationTime>2026-01-01T00:00:00.000-03:00</generationTime>` +
          `<expirationTime>${exp}</expirationTime></header><credentials>` +
          `<token>tok-${calls}</token><sign>sig-${calls}</sign></credentials></loginTicketResponse>`;
        const body =
          `<?xml version="1.0"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">` +
          `<soapenv:Body><loginCmsReturn>${credentials
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")}</loginCmsReturn></soapenv:Body></soapenv:Envelope>`;
        return new Response(body, { status: 200 });
      })
    );

    const first = await getValidTa(config);
    expect(first.token).toBe("tok-1");
    await new Promise((r) => setTimeout(r, 700));
    const second = await getValidTa(config);
    expect(second.token).toBe("tok-2");
    expect(calls).toBe(2);
    vi.unstubAllGlobals();
  });
});

describe("WSAA SOAP fault diagnostics", () => {
  const original = { ...process.env };

  function homoConfig() {
    const pair = makeSelfSignedPemPair();
    process.env.ARCA_ENV = "homologation";
    process.env.ARCA_REPRESENTED_CUIT = "20111111112";
    process.env.ARCA_HOMO_PRIVATE_KEY_B64 = Buffer.from(pair.privateKeyPem).toString(
      "base64"
    );
    process.env.ARCA_HOMO_CERT_B64 = Buffer.from(pair.certificatePem).toString("base64");
    process.env.ARCA_HOMO_PTO_VENTA = "10";
    return getArcaHomologationConfig();
  }

  beforeEach(() => {
    process.env = { ...original };
    resetArcaEnvFileLoadedForTests();
    clearTaCacheForTests();
  });

  afterEach(() => {
    process.env = original;
    resetArcaEnvFileLoadedForTests();
    clearTaCacheForTests();
    vi.unstubAllGlobals();
  });

  it("extracts plain faultcode and faultstring", () => {
    const f = extractSoapFault(
      `<Fault><faultcode>soap:Server</faultcode><faultstring>cms.cert.Expired</faultstring></Fault>`
    );
    expect(f.faultcode).toBe("soap:Server");
    expect(f.faultstring).toBe("cms.cert.Expired");
  });

  it("extracts namespace-prefixed fault tags", () => {
    const f = extractSoapFault(
      `<soap:Fault><soap:faultcode>soap:Client</soap:faultcode>` +
        `<soap:faultstring>Invalid CMS</soap:faultstring></soap:Fault>`
    );
    expect(f.faultcode).toBe("soap:Client");
    expect(f.faultstring).toBe("Invalid CMS");
  });

  it("HTTP 500 + faultstring throws WSAA_FAULT with sanitized message", async () => {
    const config = homoConfig();
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        const body =
          `<?xml version="1.0"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">` +
          `<soapenv:Body><soapenv:Fault>` +
          `<faultstring>coe.notAuthorized</faultstring>` +
          `</soapenv:Fault></soapenv:Body></soapenv:Envelope>`;
        return new Response(body, { status: 500 });
      })
    );
    try {
      await wsaaLoginCms(config);
      expect.unreachable();
    } catch (e) {
      expect(e).toBeInstanceOf(ArcaSanitizedError);
      const err = e as ArcaSanitizedError;
      expect(err.code).toBe("WSAA_FAULT");
      expect(err.stage).toBe("wsaa");
      expect(err.message).toMatch(/WSAA HTTP 500:.*coe\.notAuthorized/);
      expect(err.message).not.toMatch(/BEGIN |loginCms|in0|Envelope/i);
    }
  });

  it("HTTP 500 + faultcode + faultstring includes sanitized faultcode", async () => {
    const config = homoConfig();
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        const body =
          `<Fault><faultcode>soap:Server</faultcode>` +
          `<faultstring>cms.bad</faultstring></Fault>`;
        return new Response(body, { status: 500 });
      })
    );
    await expect(wsaaLoginCms(config)).rejects.toMatchObject({
      code: "WSAA_FAULT",
      message: expect.stringMatching(/WSAA HTTP 500: cms\.bad \[soap:Server\]/),
    });
  });

  it("HTTP 500 + namespace-prefixed fault throws WSAA_FAULT", async () => {
    const config = homoConfig();
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        const body =
          `<soap:Fault><soap:faultcode>soap:Client</soap:faultcode>` +
          `<soap:faultstring>ns.fault.here</soap:faultstring></soap:Fault>`;
        return new Response(body, { status: 500 });
      })
    );
    await expect(wsaaLoginCms(config)).rejects.toMatchObject({
      code: "WSAA_FAULT",
      message: expect.stringMatching(/WSAA HTTP 500: ns\.fault\.here/),
    });
  });

  it("HTTP 500 without parsable fault does not dump XML body", async () => {
    const config = homoConfig();
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        return new Response(
          `<html><body>gateway error SECRET_BLOB_${"A".repeat(100)}</body></html>`,
          { status: 500 }
        );
      })
    );
    try {
      await wsaaLoginCms(config);
      expect.unreachable();
    } catch (e) {
      const err = e as ArcaSanitizedError;
      expect(err.code).toBe("WSAA_HTTP");
      expect(err.message).toBe(
        "WSAA HTTP 500: SOAP fault could not be safely parsed"
      );
      expect(err.message).not.toContain("SECRET_BLOB");
      expect(err.message).not.toContain("<html");
    }
  });

  it("redacts PEM-like content from faultstring", async () => {
    const config = homoConfig();
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        const pem =
          "-----BEGIN PRIVATE KEY-----\nABC\n-----END PRIVATE KEY-----";
        return new Response(
          `<Fault><faultstring>bad ${pem}</faultstring></Fault>`,
          { status: 500 }
        );
      })
    );
    const err = await wsaaLoginCms(config).catch((e) => e);
    expect(err.code).toBe("WSAA_FAULT");
    expect(err.message).toContain("[REDACTED_PEM]");
    expect(err.message).not.toContain("BEGIN PRIVATE KEY");
  });

  it("successful LoginCms parsing remains unchanged", async () => {
    const config = homoConfig();
    const exp = new Date(Date.now() + 5 * 60_000).toISOString();
    const credentials =
      `<loginTicketResponse><header><generationTime>2026-01-01T00:00:00.000-03:00</generationTime>` +
      `<expirationTime>${exp}</expirationTime></header><credentials>` +
      `<token>tok-ok</token><sign>sig-ok</sign></credentials></loginTicketResponse>`;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (_url: string, init?: RequestInit) => {
        expect(init?.headers).toMatchObject({
          "Content-Type": "text/xml; charset=utf-8",
          SOAPAction: "",
        });
        const body =
          `<?xml version="1.0"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">` +
          `<soapenv:Body><loginCmsReturn>${credentials
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")}</loginCmsReturn></soapenv:Body></soapenv:Envelope>`;
        return new Response(body, { status: 200 });
      })
    );
    const ticket = await wsaaLoginCms(config);
    expect(ticket.token).toBe("tok-ok");
    expect(ticket.sign).toBe("sig-ok");
    expect(ticket.service).toBe("wsfe");
  });
});

describe("WSFE Errors/Events parsing", () => {
  const original = { ...process.env };

  function homoConfig() {
    const pair = makeSelfSignedPemPair();
    process.env.ARCA_ENV = "homologation";
    process.env.ARCA_REPRESENTED_CUIT = "20111111112";
    process.env.ARCA_HOMO_PRIVATE_KEY_B64 = Buffer.from(pair.privateKeyPem).toString(
      "base64"
    );
    process.env.ARCA_HOMO_CERT_B64 = Buffer.from(pair.certificatePem).toString("base64");
    process.env.ARCA_HOMO_PTO_VENTA = "10";
    return getArcaHomologationConfig();
  }

  function mockWsaaThenWsfe(wsfeBody: string, wsfeStatus = 200) {
    let n = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) => {
        n += 1;
        if (String(url).includes("wsaa")) {
          const exp = new Date(Date.now() + 5 * 60_000).toISOString();
          const credentials =
            `<loginTicketResponse><header><generationTime>2026-01-01T00:00:00.000-03:00</generationTime>` +
            `<expirationTime>${exp}</expirationTime></header><credentials>` +
            `<token>tok</token><sign>sig</sign></credentials></loginTicketResponse>`;
          const body =
            `<?xml version="1.0"?><Envelope><Body><loginCmsReturn>${credentials
              .replace(/</g, "&lt;")
              .replace(/>/g, "&gt;")}</loginCmsReturn></Body></Envelope>`;
          return new Response(body, { status: 200 });
        }
        return new Response(wsfeBody, { status: wsfeStatus });
      })
    );
    return () => n;
  }

  beforeEach(() => {
    process.env = { ...original };
    resetArcaEnvFileLoadedForTests();
    clearTaCacheForTests();
  });

  afterEach(() => {
    process.env = original;
    resetArcaEnvFileLoadedForTests();
    clearTaCacheForTests();
    vi.unstubAllGlobals();
  });

  it("MethodResult + Errors must throw WSFE_ERROR", () => {
    const xml =
      `<FEParamGetPtosVentaResult>` +
      `<Errors><Err><Code>600</Code><Msg>Validacion</Msg></Err></Errors>` +
      `</FEParamGetPtosVentaResult>`;
    expect(() => assertNoWsfeErrors(xml, "FEParamGetPtosVenta")).toThrow(
      ArcaSanitizedError
    );
    try {
      assertNoWsfeErrors(xml, "FEParamGetPtosVenta");
    } catch (e) {
      const err = e as ArcaSanitizedError;
      expect(err.code).toBe("WSFE_ERROR");
      expect(err.message).toMatch(/FEParamGetPtosVenta ARCA error 600/);
    }
  });

  it("FEParamGetPtosVentaResult + error 11002 must NOT return []", async () => {
    const config = homoConfig();
    mockWsaaThenWsfe(
      `<soap:Body><FEParamGetPtosVentaResponse><FEParamGetPtosVentaResult>` +
        `<Errors><Err><Code>11002</Code><Msg>No existen puntos de venta</Msg></Err></Errors>` +
        `</FEParamGetPtosVentaResult></FEParamGetPtosVentaResponse></soap:Body>`
    );
    await expect(feParamGetPtosVenta(config)).rejects.toMatchObject({
      code: "WSFE_ERROR",
      message: expect.stringMatching(/11002/),
    });
  });

  it("genuine empty ResultGet + no Errors returns []", async () => {
    const config = homoConfig();
    mockWsaaThenWsfe(
      `<FEParamGetPtosVentaResult><ResultGet></ResultGet></FEParamGetPtosVentaResult>`
    );
    await expect(feParamGetPtosVenta(config)).resolves.toEqual([]);
  });

  it("parses multiple Errors safely", () => {
    const xml =
      `<Errors>` +
      `<Err><Code>1</Code><Msg>A</Msg></Err>` +
      `<Err><Code>2</Code><Msg>B</Msg></Err>` +
      `</Errors>`;
    expect(parseWsfeErrors(xml)).toEqual([
      { Code: "1", Msg: "A" },
      { Code: "2", Msg: "B" },
    ]);
    expect(() => assertNoWsfeErrors(xml, "X")).toThrow(/\(\+1 more\)/);
  });

  it("Events without Errors do not fail", () => {
    const xml =
      `<Events><Evt><Code>10</Code><Msg>info</Msg></Evt></Events>` +
      `<ResultGet><PtoVenta><Nro>1</Nro></PtoVenta></ResultGet>`;
    expect(parseWsfeEvents(xml)).toEqual([{ Code: "10", Msg: "info" }]);
    expect(() => assertNoWsfeErrors(xml, "FEParamGetPtosVenta")).not.toThrow();
  });

  it("Errors and Events together: Errors win", () => {
    const xml =
      `<Events><Evt><Code>10</Code><Msg>info</Msg></Evt></Events>` +
      `<Errors><Err><Code>99</Code><Msg>fatal</Msg></Err></Errors>`;
    expect(() => assertNoWsfeErrors(xml, "FEDummy")).toThrow(
      /FEDummy ARCA error 99: fatal/
    );
  });

  it("supports namespace-prefixed Errors/Err", () => {
    const xml =
      `<ar:Errors><ar:Err><ar:Code>7</ar:Code><ar:Msg>ns</ar:Msg></ar:Err></ar:Errors>`;
    expect(parseWsfeErrors(xml)).toEqual([{ Code: "7", Msg: "ns" }]);
  });

  it("sanitizes secret-like content in Msg", () => {
    const pem = "-----BEGIN PRIVATE KEY-----\nXYZ\n-----END PRIVATE KEY-----";
    const xml = `<Errors><Err><Code>1</Code><Msg>bad ${pem}</Msg></Err></Errors>`;
    try {
      assertNoWsfeErrors(xml, "FEParamGetTiposCbte");
      expect.unreachable();
    } catch (e) {
      const err = e as ArcaSanitizedError;
      expect(err.message).toContain("[REDACTED_PEM]");
      expect(err.message).not.toContain("BEGIN PRIVATE KEY");
    }
  });

  it("ignores Code/Msg outside Errors container", () => {
    const xml =
      `<Something><Code>999</Code><Msg>not an error</Msg></Something>` +
      `<ResultGet></ResultGet>`;
    expect(parseWsfeErrors(xml)).toEqual([]);
    expect(() => assertNoWsfeErrors(xml, "M")).not.toThrow();
  });

  it("successful PtoVenta row parsing still passes", async () => {
    const config = homoConfig();
    mockWsaaThenWsfe(
      `<FEParamGetPtosVentaResult><ResultGet>` +
        `<PtoVenta><Nro>3</Nro><EmisionTipo>CAE</EmisionTipo><Bloqueado>N</Bloqueado></PtoVenta>` +
        `</ResultGet></FEParamGetPtosVentaResult>`
    );
    const rows = await feParamGetPtosVenta(config);
    expect(rows).toEqual([
      { Nro: "3", EmisionTipo: "CAE", Bloqueado: "N", FchBaja: null },
    ]);
  });

  it("FECompUltimoAutorizado ARCA error is not coerced to CbteNro=null", async () => {
    const config = homoConfig();
    mockWsaaThenWsfe(
      `<FECompUltimoAutorizadoResult>` +
        `<Errors><Err><Code>602</Code><Msg>Sin Resultados</Msg></Err></Errors>` +
        `</FECompUltimoAutorizadoResult>`
    );
    await expect(feCompUltimoAutorizado(config, 1, 11)).rejects.toMatchObject({
      code: "WSFE_ERROR",
      message: expect.stringMatching(/602/),
    });
  });

  it("FECompUltimoAutorizado SOAP uses PtoVta not PtoVenta", async () => {
    const config = homoConfig();
    const bodies: string[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init?: RequestInit) => {
        if (String(url).includes("wsaa")) {
          const exp = new Date(Date.now() + 5 * 60_000).toISOString();
          const credentials =
            `<loginTicketResponse><header><generationTime>2026-01-01T00:00:00.000-03:00</generationTime>` +
            `<expirationTime>${exp}</expirationTime></header><credentials>` +
            `<token>tok</token><sign>sig</sign></credentials></loginTicketResponse>`;
          return new Response(
            `<Body><loginCmsReturn>${credentials
              .replace(/</g, "&lt;")
              .replace(/>/g, "&gt;")}</loginCmsReturn></Body>`,
            { status: 200 }
          );
        }
        bodies.push(String(init?.body ?? ""));
        return new Response(
          `<FECompUltimoAutorizadoResult><CbteNro>42</CbteNro></FECompUltimoAutorizadoResult>`,
          { status: 200 }
        );
      })
    );

    for (const pto of [1, 2, 10]) {
      const ult = await feCompUltimoAutorizado(config, pto, 11);
      expect(ult.CbteNro).toBe(42);
      expect(ult.CbteTipo).toBe(11);
    }

    expect(bodies.length).toBe(3);
    for (const [i, pto] of [1, 2, 10].entries()) {
      expect(bodies[i]).toContain(`<ar:PtoVta>${pto}</ar:PtoVta>`);
      expect(bodies[i]).toContain(`<ar:CbteTipo>11</ar:CbteTipo>`);
      expect(bodies[i]).not.toContain("<ar:PtoVenta>");
    }
  });

  it("probeHomologationPos reports PASS and ARCA_ERROR sanitized rows", async () => {
    const config = homoConfig();
    let call = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) => {
        if (String(url).includes("wsaa")) {
          const exp = new Date(Date.now() + 5 * 60_000).toISOString();
          const credentials =
            `<loginTicketResponse><header><generationTime>2026-01-01T00:00:00.000-03:00</generationTime>` +
            `<expirationTime>${exp}</expirationTime></header><credentials>` +
            `<token>tok</token><sign>sig</sign></credentials></loginTicketResponse>`;
          return new Response(
            `<Body><loginCmsReturn>${credentials
              .replace(/</g, "&lt;")
              .replace(/>/g, "&gt;")}</loginCmsReturn></Body>`,
            { status: 200 }
          );
        }
        call += 1;
        if (call === 1) {
          return new Response(
            `<FECompUltimoAutorizadoResult><CbteNro>0</CbteNro></FECompUltimoAutorizadoResult>`,
            { status: 200 }
          );
        }
        return new Response(
          `<FECompUltimoAutorizadoResult>` +
            `<Errors><Err><Code>602</Code><Msg>Sin Resultados: FECompUltimoAutorizado</Msg></Err></Errors>` +
            `</FECompUltimoAutorizadoResult>`,
          { status: 200 }
        );
      })
    );

    const rows = await probeHomologationPos(config, [1, 2], 11);
    expect(rows).toEqual([
      {
        pto_venta: 1,
        status: "PASS",
        arca_error_code: null,
        sanitized_error_message: null,
        ultimo_comprobante: 0,
      },
      {
        pto_venta: 2,
        status: "ARCA_ERROR",
        arca_error_code: "602",
        sanitized_error_message: expect.stringMatching(/602/),
        ultimo_comprobante: null,
      },
    ]);
    expect(JSON.stringify(rows)).not.toMatch(/token|sign|BEGIN |CUIT/i);
  });

  it("FEParamGetPtosVenta 602 is distinguishable from other 602 errors", async () => {
    const config = homoConfig();
    mockWsaaThenWsfe(
      `<FEParamGetPtosVentaResult>` +
        `<Errors><Err><Code>602</Code><Msg>Sin Resultados: - Metodo FEParamGetPtosVenta</Msg></Err></Errors>` +
        `</FEParamGetPtosVentaResult>`
    );
    const err = await feParamGetPtosVenta(config).catch((e) => e);
    expect(err.code).toBe("WSFE_ERROR");
    expect(err.message).toMatch(/FEParamGetPtosVenta ARCA error 602/);
    // Discovery gate may tolerate this; method itself still throws (not empty []).
  });

  it("configured POS FECompUltimoAutorizado error remains fatal", async () => {
    const config = homoConfig();
    expect(config.homoPtoVenta).toBe(10);
    mockWsaaThenWsfe(
      `<FECompUltimoAutorizadoResult>` +
        `<Errors><Err><Code>600</Code><Msg>Validacion</Msg></Err></Errors>` +
        `</FECompUltimoAutorizadoResult>`
    );
    await expect(feCompUltimoAutorizado(config, config.homoPtoVenta, 11)).rejects.toMatchObject({
      code: "WSFE_ERROR",
      message: expect.stringMatching(/600/),
    });
  });

  it("other WSFE method 602 is NOT silently ignored", () => {
    const xml =
      `<FECompUltimoAutorizadoResult>` +
      `<Errors><Err><Code>602</Code><Msg>Sin Resultados</Msg></Err></Errors>` +
      `</FECompUltimoAutorizadoResult>`;
    expect(() => assertNoWsfeErrors(xml, "FECompUltimoAutorizado")).toThrow(
      /FECompUltimoAutorizado ARCA error 602/
    );
  });
});
