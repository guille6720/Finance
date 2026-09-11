import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import forge from "node-forge";
import {
  getArcaHomologationConfig,
  resetArcaEnvFileLoadedForTests,
} from "@/server/arca/config";
import { clearTaCacheForTests } from "@/server/arca/ta-cache";
import {
  ARCA_WSAA_HOMO_URL,
  ARCA_WSFE_HOMO_URL,
} from "@/server/arca/constants";
import {
  runHomologationRejectionGate,
  runHomologationUncertainGate,
  buildInvalidRejectionFeCaeBody,
  assertConfirmationFlag,
  assertNoFullCaeInEvidence,
  REJECTION_CONFIRM_FLAG,
  UNCERTAIN_CONFIRM_FLAG,
} from "@/server/arca/cae-gates";
import { ArcaSanitizedError } from "@/server/arca/errors";

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

function homoConfig() {
  const pair = makeSelfSignedPemPair();
  process.env.ARCA_ENV = "homologation";
  process.env.ARCA_REPRESENTED_CUIT = "20111111112";
  process.env.ARCA_HOMO_PRIVATE_KEY_B64 = Buffer.from(pair.privateKeyPem).toString(
    "base64"
  );
  process.env.ARCA_HOMO_CERT_B64 = Buffer.from(pair.certificatePem).toString("base64");
  process.env.ARCA_HOMO_PTO_VENTA = "10";
  process.env.ARCA_WSAA_URL = ARCA_WSAA_HOMO_URL;
  process.env.ARCA_WSFE_URL = ARCA_WSFE_HOMO_URL;
  process.env.ARCA_WSAA_SERVICE = "wsfe";
  return getArcaHomologationConfig();
}

function wsaaOkBody() {
  const exp = new Date(Date.now() + 5 * 60_000).toISOString();
  const credentials =
    `<loginTicketResponse><header><generationTime>2026-01-01T00:00:00.000-03:00</generationTime>` +
    `<expirationTime>${exp}</expirationTime></header><credentials>` +
    `<token>tok</token><sign>sig</sign></credentials></loginTicketResponse>`;
  return `<Body><loginCmsReturn>${credentials
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")}</loginCmsReturn></Body>`;
}

function catalogOk(soap: string): Response | null {
  if (soap.includes("FEParamGetTiposDoc")) {
    return new Response(
      `<ResultGet><DocTipo><Id>99</Id><Desc>CF</Desc></DocTipo></ResultGet>`,
      { status: 200 }
    );
  }
  if (soap.includes("FEParamGetCondicionIvaReceptor")) {
    return new Response(
      `<ResultGet><CondicionIvaReceptor><Id>5</Id><Desc>Consumidor Final</Desc></CondicionIvaReceptor></ResultGet>`,
      { status: 200 }
    );
  }
  return null;
}

describe("ARCA rejection + uncertain gates", () => {
  const original = { ...process.env };

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

  it("requires confirmation flags", () => {
    expect(() => assertConfirmationFlag([], REJECTION_CONFIRM_FLAG)).toThrow(
      /STOP_CONFIRMATION_REQUIRED|Missing/
    );
    expect(() =>
      assertConfirmationFlag([UNCERTAIN_CONFIRM_FLAG], UNCERTAIN_CONFIRM_FLAG)
    ).not.toThrow();
  });

  it("rejection gate requires confirmation", async () => {
    const config = homoConfig();
    await expect(
      runHomologationRejectionGate(config, { confirmed: false })
    ).rejects.toMatchObject({ code: "STOP_CONFIRMATION_REQUIRED" });
  });

  it("uncertain gate requires confirmation", async () => {
    const config = homoConfig();
    await expect(
      runHomologationUncertainGate(config, { confirmed: false })
    ).rejects.toMatchObject({ code: "STOP_CONFIRMATION_REQUIRED" });
  });

  it("invalid rejection payload uses MonId XXX and PtoVta", () => {
    const body = buildInvalidRejectionFeCaeBody({
      cbteDesde: 2,
      cbteHasta: 2,
      cbteFch: "20260910",
      condicionIvaReceptorId: 5,
    });
    expect(body).toContain("<ar:MonId>XXX</ar:MonId>");
    expect(body).toContain("<ar:PtoVta>10</ar:PtoVta>");
    expect(body).toContain("<ar:CbteDesde>2</ar:CbteDesde>");
    expect(body).not.toContain("<ar:PtoVenta>");
    expect(body).not.toContain("<ar:MonId>PES</ar:MonId>");
  });

  it("rejection does not consume number; accounting not run; single FECAE", async () => {
    const config = homoConfig();
    let fecae = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init?: RequestInit) => {
        if (String(url).includes("wsaa")) {
          return new Response(wsaaOkBody(), { status: 200 });
        }
        const soap = String(init?.body ?? "");
        const cat = catalogOk(soap);
        if (cat) return cat;
        if (soap.includes("FECompUltimoAutorizado")) {
          return new Response(
            `<FECompUltimoAutorizadoResult><CbteNro>1</CbteNro></FECompUltimoAutorizadoResult>`,
            { status: 200 }
          );
        }
        if (soap.includes("FECAESolicitar")) {
          fecae += 1;
          expect(soap).toContain("<ar:MonId>XXX</ar:MonId>");
          return new Response(
            `<FECAEDetResponse><Resultado>R</Resultado></FECAEDetResponse>` +
              `<Errors><Err><Code>10016</Code><Msg>Moneda invalida</Msg></Err></Errors>`,
            { status: 200 }
          );
        }
        throw new Error("unexpected");
      })
    );

    const ev = await runHomologationRejectionGate(config, { confirmed: true });
    expect(ev.outcome).toBe("REJECTED");
    expect(ev.LAST_BEFORE).toBe(1);
    expect(ev.LAST_AFTER).toBe(1);
    expect(ev.NUMBER_CONSUMED).toBe("NO");
    expect(ev.FECAESOLICITAR_CALL_COUNT).toBe(1);
    expect(fecae).toBe(1);
    expect(ev.AUTOMATIC_RETRY).toBe("NO");
    expect(ev.ACCOUNTING_POST).toBe("NOT_RUN");
    expect(ev.errors[0]?.code).toBe("10016");
    assertNoFullCaeInEvidence(ev);
  });

  it("unexpected authorization on rejection enters reconciliation", async () => {
    const config = homoConfig();
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init?: RequestInit) => {
        if (String(url).includes("wsaa")) {
          return new Response(wsaaOkBody(), { status: 200 });
        }
        const soap = String(init?.body ?? "");
        const cat = catalogOk(soap);
        if (cat) return cat;
        if (soap.includes("FECompUltimoAutorizado")) {
          return new Response(
            `<FECompUltimoAutorizadoResult><CbteNro>1</CbteNro></FECompUltimoAutorizadoResult>`,
            { status: 200 }
          );
        }
        if (soap.includes("FECAESolicitar")) {
          return new Response(
            `<FECAEDetResponse><Resultado>A</Resultado><CAE>11112222333344</CAE>` +
              `<CAEFchVto>20260920</CAEFchVto></FECAEDetResponse>`,
            { status: 200 }
          );
        }
        if (soap.includes("FECompConsultar")) {
          return new Response(
            `<Resultado>A</Resultado><CodAutorizacion>11112222333344</CodAutorizacion><FchVto>20260920</FchVto>`,
            { status: 200 }
          );
        }
        throw new Error("unexpected");
      })
    );

    const ev = await runHomologationRejectionGate(config, { confirmed: true });
    expect(ev.outcome).toBe("STOP_UNEXPECTED_AUTHORIZATION");
    expect(ev.FECOMPCONSULTAR).toBe("PASS");
    expect(ev.FECAESOLICITAR_CALL_COUNT).toBe(1);
    expect(JSON.stringify(ev)).not.toMatch(/11112222333344/);
  });

  it("simulated response loss invokes FECompConsultar once; never retries FECAE", async () => {
    const config = homoConfig();
    let fecae = 0;
    let consult = 0;
    let ultimo = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init?: RequestInit) => {
        if (String(url).includes("wsaa")) {
          return new Response(wsaaOkBody(), { status: 200 });
        }
        const soap = String(init?.body ?? "");
        const cat = catalogOk(soap);
        if (cat) return cat;
        if (soap.includes("FECompUltimoAutorizado")) {
          ultimo += 1;
          return new Response(
            `<FECompUltimoAutorizadoResult><CbteNro>${
              ultimo === 1 ? 1 : 2
            }</CbteNro></FECompUltimoAutorizadoResult>`,
            { status: 200 }
          );
        }
        if (soap.includes("FECAESolicitar")) {
          fecae += 1;
          return new Response(
            `<FECAEDetResponse><Resultado>A</Resultado><CAE>55556666777788</CAE>` +
              `<CAEFchVto>20260920</CAEFchVto><CbteDesde>2</CbteDesde></FECAEDetResponse>`,
            { status: 200 }
          );
        }
        if (soap.includes("FECompConsultar")) {
          consult += 1;
          expect(soap).toContain("<ar:PtoVta>10</ar:PtoVta>");
          expect(soap).toContain("<ar:CbteNro>2</ar:CbteNro>");
          return new Response(
            `<Resultado>A</Resultado><CodAutorizacion>55556666777788</CodAutorizacion><FchVto>20260920</FchVto>`,
            { status: 200 }
          );
        }
        throw new Error("unexpected");
      })
    );

    const ev = await runHomologationUncertainGate(config, {
      confirmed: true,
      simulateResponseLoss: true,
    });
    expect(fecae).toBe(1);
    expect(consult).toBe(1);
    expect(ev.FECAESOLICITAR_CALL_COUNT).toBe(1);
    expect(ev.AUTOMATIC_RETRY).toBe("NO");
    expect(ev.SIMULATED_RESPONSE_LOSS).toBe("PASS");
    expect(ev.outcome).toBe("AUTHORIZED_RECONCILED");
    expect(ev.FECOMPCONSULTAR).toBe("PASS");
    expect(ev.CAE_PRESENT).toBe(true);
    expect(ev.LAST_BEFORE).toBe(1);
    expect(ev.LAST_AFTER).toBe(2);
    expect(ev.ACCOUNTING_POST).toBe("NOT_RUN");
    expect(JSON.stringify(ev)).not.toMatch(/55556666777788/);
    assertNoFullCaeInEvidence(ev);
  });

  it("missing CAE on consult fails closed", async () => {
    const config = homoConfig();
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init?: RequestInit) => {
        if (String(url).includes("wsaa")) {
          return new Response(wsaaOkBody(), { status: 200 });
        }
        const soap = String(init?.body ?? "");
        const cat = catalogOk(soap);
        if (cat) return cat;
        if (soap.includes("FECompUltimoAutorizado")) {
          return new Response(
            `<FECompUltimoAutorizadoResult><CbteNro>1</CbteNro></FECompUltimoAutorizadoResult>`,
            { status: 200 }
          );
        }
        if (soap.includes("FECAESolicitar")) {
          return new Response(`<FECAEDetResponse><Resultado>A</Resultado></FECAEDetResponse>`, {
            status: 200,
          });
        }
        if (soap.includes("FECompConsultar")) {
          return new Response(
            `<Errors><Err><Code>602</Code><Msg>Sin Resultados</Msg></Err></Errors>`,
            { status: 200 }
          );
        }
        throw new Error("unexpected");
      })
    );

    const ev = await runHomologationUncertainGate(config, {
      confirmed: true,
      simulateResponseLoss: true,
    });
    expect(ev.FECAESOLICITAR_CALL_COUNT).toBe(1);
    expect(ev.outcome === "REJECTED" || ev.outcome === "UNCERTAIN_STOP").toBe(
      true
    );
    expect(ev.CAE_PRESENT).toBe(false);
  });

  it("Production env blocked for gates via config", () => {
    process.env.ARCA_ENV = "production";
    expect(() => getArcaHomologationConfig()).toThrow(/production/i);
  });

  it("assertNoFullCaeInEvidence detects leaked CAE field", () => {
    expect(() =>
      assertNoFullCaeInEvidence({ cae: "12345678901234" })
    ).toThrow(/SECRET_LEAK|full CAE/);
  });
});
