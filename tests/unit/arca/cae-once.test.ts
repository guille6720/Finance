import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import forge from "node-forge";
import {
  getArcaHomologationConfig,
  resetArcaEnvFileLoadedForTests,
} from "@/server/arca/config";
import { clearTaCacheForTests } from "@/server/arca/ta-cache";
import { feCaeSolicitarForbidden, assertNoWsfeErrors } from "@/server/arca/wsfe";
import {
  assertHomologationIssuanceGuards,
  buildFeCaeSolicitarBody,
  parseFeCaeSolicitarResponse,
  resolveConsumidorFinalId,
  requireDocTipo99,
  feCaeSolicitarHomologationOnce,
  HOMO_CAE_ONCE,
} from "@/server/arca/cae-homologation";
import { ArcaSanitizedError } from "@/server/arca/errors";
import {
  ARCA_WSAA_HOMO_URL,
  ARCA_WSFE_HOMO_URL,
} from "@/server/arca/constants";

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

function homoConfig(overrides?: Partial<{ pto: string }>) {
  const pair = makeSelfSignedPemPair();
  process.env.ARCA_ENV = "homologation";
  process.env.ARCA_REPRESENTED_CUIT = "20111111112";
  process.env.ARCA_HOMO_PRIVATE_KEY_B64 = Buffer.from(pair.privateKeyPem).toString(
    "base64"
  );
  process.env.ARCA_HOMO_CERT_B64 = Buffer.from(pair.certificatePem).toString("base64");
  process.env.ARCA_HOMO_PTO_VENTA = overrides?.pto ?? "10";
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

describe("FECAESolicitar homologation once", () => {
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

  it("keeps default FECAESolicitar forbidden", () => {
    expect(() => feCaeSolicitarForbidden()).toThrow(/not authorized/i);
  });

  it("blocks missing confirmation", () => {
    const config = homoConfig();
    expect(() =>
      assertHomologationIssuanceGuards(config, { confirmed: false })
    ).toThrow(/confirm-homologation-issue/i);
  });

  it("blocks wrong POS", () => {
    const config = homoConfig({ pto: "1" });
    expect(() =>
      assertHomologationIssuanceGuards(config, { confirmed: true })
    ).toThrow(/ARCA_HOMO_PTO_VENTA must be 10/);
  });

  it("blocks wrong CbteTipo", () => {
    const config = homoConfig();
    expect(() =>
      assertHomologationIssuanceGuards(config, {
        confirmed: true,
        expectedCbteTipo: 6,
      })
    ).toThrow(/CbteTipo must be 11/);
  });

  it("Production WSAA URL blocked at config", () => {
    const pair = makeSelfSignedPemPair();
    process.env.ARCA_ENV = "homologation";
    process.env.ARCA_REPRESENTED_CUIT = "20111111112";
    process.env.ARCA_HOMO_PRIVATE_KEY_B64 = Buffer.from(pair.privateKeyPem).toString(
      "base64"
    );
    process.env.ARCA_HOMO_CERT_B64 = Buffer.from(pair.certificatePem).toString("base64");
    process.env.ARCA_HOMO_PTO_VENTA = "10";
    process.env.ARCA_WSAA_URL = "https://wsaa.afip.gov.ar/ws/services/LoginCms";
    expect(() => getArcaHomologationConfig()).toThrow();
  });

  it("Production WSFE URL blocked at config", () => {
    const pair = makeSelfSignedPemPair();
    process.env.ARCA_ENV = "homologation";
    process.env.ARCA_REPRESENTED_CUIT = "20111111112";
    process.env.ARCA_HOMO_PRIVATE_KEY_B64 = Buffer.from(pair.privateKeyPem).toString(
      "base64"
    );
    process.env.ARCA_HOMO_CERT_B64 = Buffer.from(pair.certificatePem).toString("base64");
    process.env.ARCA_HOMO_PTO_VENTA = "10";
    process.env.ARCA_WSFE_URL =
      "https://servicios1.afip.gov.ar/wsfev1/service.asmx";
    expect(() => getArcaHomologationConfig()).toThrow();
  });

  it("Production environment blocked", () => {
    process.env.ARCA_ENV = "production";
    expect(() => getArcaHomologationConfig()).toThrow(/production/i);
  });

  it("serializes PtoVta Factura C amounts without IVA array", () => {
    const body = buildFeCaeSolicitarBody({
      ptoVta: 10,
      cbteTipo: 11,
      cbteDesde: 1,
      cbteHasta: 1,
      cbteFch: "20260910",
      condicionIvaReceptorId: 5,
    });
    expect(body).toContain("<ar:PtoVta>10</ar:PtoVta>");
    expect(body).not.toContain("<ar:PtoVenta>");
    expect(body).toContain("<ar:CbteTipo>11</ar:CbteTipo>");
    expect(body).toContain("<ar:ImpTotal>1000.00</ar:ImpTotal>");
    expect(body).toContain("<ar:ImpNeto>1000.00</ar:ImpNeto>");
    expect(body).toContain("<ar:ImpIVA>0.00</ar:ImpIVA>");
    expect(body).toContain("<ar:MonId>PES</ar:MonId>");
    expect(body).toContain("<ar:MonCotiz>1</ar:MonCotiz>");
    expect(body).toContain("<ar:CondicionIVAReceptorId>5</ar:CondicionIVAReceptorId>");
    expect(body).not.toMatch(/<ar:IVA>/);
    expect(body).not.toMatch(/CanMisMonExt|FchServicio/);
  });

  it("rejects wrong POS/CbteTipo in payload builder", () => {
    expect(() =>
      buildFeCaeSolicitarBody({
        ptoVta: 1,
        cbteTipo: 11,
        cbteDesde: 1,
        cbteHasta: 1,
        cbteFch: "20260910",
        condicionIvaReceptorId: 5,
      })
    ).toThrow(/wrong POS/i);
    expect(() =>
      buildFeCaeSolicitarBody({
        ptoVta: 10,
        cbteTipo: 6,
        cbteDesde: 1,
        cbteHasta: 1,
        cbteFch: "20260910",
        condicionIvaReceptorId: 5,
      })
    ).toThrow(/wrong CbteTipo/i);
  });

  it("resolves Consumidor Final dynamically and blocks ambiguity", () => {
    expect(
      resolveConsumidorFinalId([
        { Id: "1", Desc: "IVA Responsable Inscripto" },
        { Id: "5", Desc: "Consumidor Final" },
      ])
    ).toBe(5);
    expect(() =>
      resolveConsumidorFinalId([{ Id: "1", Desc: "IVA Responsable Inscripto" }])
    ).toThrow(/STOP_BEFORE_FECAE|Consumidor Final/i);
    expect(() =>
      resolveConsumidorFinalId([
        { Id: "5", Desc: "Consumidor Final" },
        { Id: "15", Desc: "Consumidor Final Especial" },
      ])
    ).toThrow(/Unambiguous/);
  });

  it("requires DocTipo 99", () => {
    expect(() => requireDocTipo99([{ Id: "80", Desc: "CUIT" }])).toThrow(
      /DocTipo 99/
    );
    expect(() => requireDocTipo99([{ Id: "99", Desc: "CF" }])).not.toThrow();
  });

  it("parses approved / observations / rejected", () => {
    const approved = parseFeCaeSolicitarResponse(
      `<FECAESolicitarResult><FeDetResp><FECAEDetResponse>` +
        `<Resultado>A</Resultado><CAE>12345678901234</CAE><CAEFchVto>20260920</CAEFchVto>` +
        `<CbteDesde>1</CbteDesde><CbteHasta>1</CbteHasta>` +
        `</FECAEDetResponse></FeDetResp></FECAESolicitarResult>`
    );
    expect(approved.outcome).toBe("AUTHORIZED");
    expect(approved.cae).toBe("12345678901234");

    const obs = parseFeCaeSolicitarResponse(
      `<FECAEDetResponse><Resultado>A</Resultado><CAE>12345678901234</CAE>` +
        `<CAEFchVto>20260920</CAEFchVto>` +
        `<Observaciones><Obs><Code>10017</Code><Msg>note</Msg></Obs></Observaciones>` +
        `</FECAEDetResponse>`
    );
    expect(obs.outcome).toBe("AUTHORIZED_WITH_OBSERVATIONS");

    const rejected = parseFeCaeSolicitarResponse(
      `<FECAEDetResponse><Resultado>R</Resultado></FECAEDetResponse>` +
        `<Errors><Err><Code>10015</Code><Msg>bad</Msg></Err></Errors>`
    );
    expect(rejected.outcome).toBe("REJECTED");
  });

  it("Errors alone are not approval", () => {
    const p = parseFeCaeSolicitarResponse(
      `<Errors><Err><Code>500</Code><Msg>fail</Msg></Err></Errors>`
    );
    expect(p.outcome).toBe("REJECTED");
  });

  it("other WSFE 602 still not silently ignored", () => {
    expect(() =>
      assertNoWsfeErrors(
        `<Errors><Err><Code>602</Code><Msg>x</Msg></Err></Errors>`,
        "FECompUltimoAutorizado"
      )
    ).toThrow(/602/);
  });

  it("last authorized != 0 blocks issuance (STOP_ALREADY_ISSUED)", async () => {
    const config = homoConfig();
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init?: RequestInit) => {
        if (String(url).includes("wsaa")) {
          return new Response(wsaaOkBody(), { status: 200 });
        }
        const soap = String(init?.body ?? "");
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
        if (soap.includes("FECompUltimoAutorizado")) {
          return new Response(
            `<FECompUltimoAutorizadoResult><CbteNro>3</CbteNro></FECompUltimoAutorizadoResult>`,
            { status: 200 }
          );
        }
        throw new Error(`unexpected method`);
      })
    );

    const result = await feCaeSolicitarHomologationOnce(config, {
      confirmed: true,
    });
    expect(result.outcome).toBe("STOP_ALREADY_ISSUED");
    expect(result.ACCOUNTING_POST).toBe("NOT_RUN");
  });

  it("next number calculated as 1 when last is 0; timeout does not retry FECAE", async () => {
    const config = homoConfig();
    let caeCalls = 0;
    let consultCalls = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init?: RequestInit) => {
        if (String(url).includes("wsaa")) {
          return new Response(wsaaOkBody(), { status: 200 });
        }
        const soap = String(init?.body ?? "");
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
        if (soap.includes("FECompUltimoAutorizado")) {
          expect(soap).toContain("<ar:PtoVta>10</ar:PtoVta>");
          return new Response(
            `<FECompUltimoAutorizadoResult><CbteNro>0</CbteNro></FECompUltimoAutorizadoResult>`,
            { status: 200 }
          );
        }
        if (soap.includes("FECAESolicitar")) {
          caeCalls += 1;
          expect(soap).toContain("<ar:PtoVta>10</ar:PtoVta>");
          expect(soap).toContain("<ar:CbteDesde>1</ar:CbteDesde>");
          expect(soap).not.toContain("<ar:PtoVenta>");
          throw new Error("socket hang up");
        }
        if (soap.includes("FECompConsultar")) {
          consultCalls += 1;
          return new Response(
            `<FECompConsultarResult><Resultado>A</Resultado>` +
              `<CodAutorizacion>99998888777766</CodAutorizacion>` +
              `<FchVto>20260920</FchVto></FECompConsultarResult>`,
            { status: 200 }
          );
        }
        throw new Error("unexpected");
      })
    );

    const result = await feCaeSolicitarHomologationOnce(config, {
      confirmed: true,
    });
    expect(caeCalls).toBe(1);
    expect(consultCalls).toBe(1);
    expect(result.outcome).toBe("AUTHORIZED_RECONCILED");
    expect(result.cae_present).toBe(true);
    expect(result.cae_length).toBe(14);
    expect(JSON.stringify(result)).not.toMatch(/99998888777766/);
  });

  it("approved path verifies consult + last number; CAE mismatch -> reconciliation", async () => {
    const config = homoConfig();
    let phase = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init?: RequestInit) => {
        if (String(url).includes("wsaa")) {
          return new Response(wsaaOkBody(), { status: 200 });
        }
        const soap = String(init?.body ?? "");
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
        if (soap.includes("FECompUltimoAutorizado")) {
          phase += 1;
          const nro = phase <= 1 ? 0 : 1;
          return new Response(
            `<FECompUltimoAutorizadoResult><CbteNro>${nro}</CbteNro></FECompUltimoAutorizadoResult>`,
            { status: 200 }
          );
        }
        if (soap.includes("FECAESolicitar")) {
          return new Response(
            `<FECAEDetResponse><Resultado>A</Resultado><CAE>11112222333344</CAE>` +
              `<CAEFchVto>20260920</CAEFchVto><CbteDesde>1</CbteDesde><CbteHasta>1</CbteHasta>` +
              `</FECAEDetResponse>`,
            { status: 200 }
          );
        }
        if (soap.includes("FECompConsultar")) {
          return new Response(
            `<Resultado>A</Resultado><CodAutorizacion>99990000111122</CodAutorizacion><FchVto>20260920</FchVto>`,
            { status: 200 }
          );
        }
        throw new Error("unexpected");
      })
    );

    const mismatch = await feCaeSolicitarHomologationOnce(config, {
      confirmed: true,
    });
    expect(mismatch.outcome).toBe("RECONCILIATION_REQUIRED");
    expect(mismatch.detail).toMatch(/mismatch/i);
  });

  it("successful verified authorization path", async () => {
    const config = homoConfig();
    let ultimoCalls = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init?: RequestInit) => {
        if (String(url).includes("wsaa")) {
          return new Response(wsaaOkBody(), { status: 200 });
        }
        const soap = String(init?.body ?? "");
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
        if (soap.includes("FECompUltimoAutorizado")) {
          ultimoCalls += 1;
          return new Response(
            `<FECompUltimoAutorizadoResult><CbteNro>${
              ultimoCalls === 1 ? 0 : 1
            }</CbteNro></FECompUltimoAutorizadoResult>`,
            { status: 200 }
          );
        }
        if (soap.includes("FECAESolicitar")) {
          return new Response(
            `<FECAEDetResponse><Resultado>A</Resultado><CAE>11112222333344</CAE>` +
              `<CAEFchVto>20260920</CAEFchVto><CbteDesde>1</CbteDesde><CbteHasta>1</CbteHasta>` +
              `</FECAEDetResponse>`,
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

    const ok = await feCaeSolicitarHomologationOnce(config, { confirmed: true });
    expect(ok.outcome).toBe("AUTHORIZED");
    expect(ok.cae_present).toBe(true);
    expect(ok.cbte_nro).toBe(1);
    expect(ok.ACCOUNTING_POST).toBe("NOT_RUN");
    expect(ok.ARCA_PRODUCTION).toBe("NOT_AUTHORIZED");
    expect(HOMO_CAE_ONCE.confirmFlag).toBe("--confirm-homologation-issue");
  });

  it("missing IVA condition blocks before issuance", async () => {
    const config = homoConfig();
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init?: RequestInit) => {
        if (String(url).includes("wsaa")) {
          return new Response(wsaaOkBody(), { status: 200 });
        }
        const soap = String(init?.body ?? "");
        if (soap.includes("FEParamGetTiposDoc")) {
          return new Response(
            `<ResultGet><DocTipo><Id>99</Id><Desc>CF</Desc></DocTipo></ResultGet>`,
            { status: 200 }
          );
        }
        if (soap.includes("FEParamGetCondicionIvaReceptor")) {
          return new Response(
            `<ResultGet><CondicionIvaReceptor><Id>1</Id><Desc>RI</Desc></CondicionIvaReceptor></ResultGet>`,
            { status: 200 }
          );
        }
        throw new Error("should stop before further calls");
      })
    );
    await expect(
      feCaeSolicitarHomologationOnce(config, { confirmed: true })
    ).rejects.toBeInstanceOf(ArcaSanitizedError);
  });
});
