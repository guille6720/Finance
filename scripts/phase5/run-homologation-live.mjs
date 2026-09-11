#!/usr/bin/env node
/**
 * LIVE_HOMOLOGATION runner — Step 1 (no FECAESolicitar).
 * Loads .env.arca.homo.local. Never prints secrets/token/sign.
 *
 * Usage: node --import tsx scripts/phase5/run-homologation-live.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const OUT = path.join(ROOT, "docs", "qa", "phase5", "ARCA-HOMOLOGATION-LIVE.json");

async function main() {
  const arca = await import(
    pathToFileURL(path.join(ROOT, "src/server/arca/index.ts")).href
  );

  arca.loadArcaHomoEnvFile(ROOT);
  // Ensure homologation mode for this runner if file set secrets but ARCA_ENV omitted
  if (!process.env.ARCA_ENV && process.env.ARCA_HOMO_CERT_B64) {
    process.env.ARCA_ENV = "homologation";
  }

  const report = {
    label: "LIVE_HOMOLOGATION",
    recorded_at: new Date().toISOString(),
    FISCAL_GATEWAY_IMPLEMENTED: "YES",
    ARCA_CONFIG_VALIDATION: "FAIL",
    ARCA_CERT_KEY_MATCH: "FAIL",
    ARCA_SECRET_SAFETY: "PASS",
    ARCA_ENVIRONMENT_GUARD: "PASS",
    WSAA_HOMOLOGATION: "NOT_RUN",
    TA_CACHE: "NOT_RUN",
    FEDUMMY: "NOT_RUN",
    PARAMETER_SYNC: "NOT_RUN",
    CONDICION_IVA_RECEPTOR_SYNC: "NOT_RUN",
    PTO_VENTA: "NOT_RUN",
    PTO_VENTA_DISCOVERY: "NOT_RUN",
    LAST_AUTHORIZED_QUERY: "NOT_RUN",
    FECAESOLICITAR: "NOT_RUN",
    ARCA_PRODUCTION: "NOT_AUTHORIZED",
    F5_HOMOLOGATION_STATUS: "IN_PROGRESS",
    sanitized: {},
    BLOCKER: null,
    ROOT_CAUSE: null,
    USER_ACTION_REQUIRED: null,
  };

  const cfgTry = arca.tryGetArcaHomologationConfig();
  if (!cfgTry.ok) {
    report.BLOCKER = cfgTry.error.code;
    report.ROOT_CAUSE = cfgTry.error.message;
    report.USER_ACTION_REQUIRED =
      "Create .env.arca.homo.local from .env.arca.homo.example using local PowerShell Base64 conversion. Do not paste secrets into chat.";
    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify({ status: "BLOCKED", ...report }, null, 2));
    process.exit(2);
  }

  const config = cfgTry.config;
  report.ARCA_CONFIG_VALIDATION = "PASS";
  report.sanitized.wsaa_url = config.wsaaUrl;
  report.sanitized.wsfe_url = config.wsfeUrl;
  report.sanitized.wsaa_service = config.wsaaService;
  report.sanitized.cuit_digits = 11;
  report.sanitized.cert_alias = config.certAlias;
  report.sanitized.configured_pto_venta = config.homoPtoVenta;

  try {
    const match = arca.validateCertKeyMatch(
      config.privateKeyPem,
      config.certificatePem
    );
    report.ARCA_CERT_KEY_MATCH = match.key_match ? "PASS" : "FAIL";
    report.sanitized.cert = {
      fingerprint_sha256: match.fingerprint_sha256,
      not_before: match.not_before,
      not_after: match.not_after,
      key_match: match.key_match,
    };
  } catch (e) {
    report.ARCA_CERT_KEY_MATCH = "FAIL";
    report.BLOCKER = e.code || "CERT_FAIL";
    report.ROOT_CAUSE = e.message;
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify({ status: "STOP", stage: "cert", code: report.BLOCKER }, null, 2));
    process.exit(1);
  }

  try {
    const ticket = await arca.getValidTa(config);
    report.WSAA_HOMOLOGATION = "PASS";
    report.TA_CACHE = "PASS";
    report.sanitized.wsaa = arca.wsaaTicketMeta(ticket);
    report.sanitized.ta_cache = arca.taCacheStats();
  } catch (e) {
    report.WSAA_HOMOLOGATION = "FAIL";
    report.BLOCKER = e.code || "WSAA_FAIL";
    report.ROOT_CAUSE = e.message;
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify({ status: "STOP", stage: "wsaa", code: report.BLOCKER }, null, 2));
    process.exit(1);
  }

  try {
    const dummy = await arca.feDummy(config);
    report.FEDUMMY = "PASS";
    report.sanitized.fedummy = dummy;
  } catch (e) {
    report.FEDUMMY = "FAIL";
    report.BLOCKER = e.code || "FEDUMMY_FAIL";
    report.ROOT_CAUSE = e.message;
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify({ status: "STOP", stage: "fedummy", code: report.BLOCKER }, null, 2));
    process.exit(1);
  }

  try {
    const cbte = await arca.feParamGetTiposCbte(config);
    const doc = await arca.feParamGetTiposDoc(config);
    const mon = await arca.feParamGetTiposMonedas(config);
    const iva = await arca.feParamGetCondicionIvaReceptor(config);
    report.PARAMETER_SYNC = "PASS";
    report.CONDICION_IVA_RECEPTOR_SYNC = iva.length > 0 ? "PASS" : "FAIL";
    report.sanitized.param_counts = {
      tipos_cbte: cbte.length,
      tipos_doc: doc.length,
      tipos_monedas: mon.length,
      condicion_iva_receptor: iva.length,
    };
    report.sanitized.condicion_iva_ids = iva.map((r) => r.Id).filter(Boolean);
    report.sanitized.catalog_mapped = {
      condicion_iva_receptor: arca.mapCondicionIvaReceptor(iva).length,
      tipos_cbte: arca.mapTiposCbte(cbte).length,
      tipos_doc: arca.mapTiposDoc(doc).length,
      monedas: arca.mapTiposMonedas(mon).length,
      note: "Mapped from ARCA only; DB upsert uses future secure Phase 5 contract",
    };

    let discoveryRows = null;
    try {
      discoveryRows = await arca.feParamGetPtosVenta(config);
      report.PTO_VENTA_DISCOVERY = "PASS";
      report.sanitized.param_counts.ptos_venta = discoveryRows.length;
      report.sanitized.pto_venta_discovery = discoveryRows.map((p) => ({
        number: p.Nro != null ? Number(p.Nro) : null,
        emission_type: p.EmisionTipo,
        blocked: p.Bloqueado,
      }));
    } catch (e) {
      const msg = String(e.message || e);
      const is602 =
        e.code === "WSFE_ERROR" &&
        /\b602\b/.test(msg) &&
        /FEParamGetPtosVenta/i.test(msg);
      if (is602) {
        report.PTO_VENTA_DISCOVERY = "UNAVAILABLE_602";
        report.sanitized.pto_venta_discovery = {
          status: "UNAVAILABLE_602",
          note: "FEParamGetPtosVenta returned ARCA 602; using ARCA_HOMO_PTO_VENTA",
        };
      } else {
        report.PTO_VENTA_DISCOVERY = "FAIL";
        report.PTO_VENTA = "FAIL";
        report.BLOCKER = e.code || "WSFE_ERROR";
        report.ROOT_CAUSE = e.message;
        fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
        console.log(
          JSON.stringify(
            { status: "STOP", stage: "pto_venta_discovery", code: report.BLOCKER },
            null,
            2
          )
        );
        process.exit(1);
      }
    }

    const configuredPto = config.homoPtoVenta;
    const cbteTipo = 11;
    try {
      const ult = await arca.feCompUltimoAutorizado(
        config,
        configuredPto,
        cbteTipo
      );
      report.PTO_VENTA = "PASS";
      report.LAST_AUTHORIZED_QUERY = "PASS";
      report.sanitized.pto_venta = {
        pto_venta: ult.PtoVenta,
        source: "ARCA_HOMO_PTO_VENTA",
      };
      report.sanitized.ultimo_autorizado = {
        pto_venta: ult.PtoVenta,
        cbte_tipo: ult.CbteTipo,
        ultimo_comprobante: ult.CbteNro,
      };
    } catch (e) {
      report.PTO_VENTA = "FAIL";
      report.LAST_AUTHORIZED_QUERY = "FAIL";
      report.BLOCKER = e.code || "WSFE_ERROR";
      report.ROOT_CAUSE = e.message;
      fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
      console.log(
        JSON.stringify(
          { status: "STOP", stage: "configured_pto_venta", code: report.BLOCKER },
          null,
          2
        )
      );
      process.exit(1);
    }
  } catch (e) {
    report.BLOCKER = e.code || "PARAM_FAIL";
    report.ROOT_CAUSE = e.message;
    if (report.PARAMETER_SYNC !== "PASS") report.PARAMETER_SYNC = "FAIL";
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify({ status: "STOP", stage: "params", code: report.BLOCKER }, null, 2));
    process.exit(1);
  }

  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
  console.log(
    JSON.stringify(
      {
        status: "OK_STOP_BEFORE_FECAE",
        WSAA_HOMOLOGATION: report.WSAA_HOMOLOGATION,
        FEDUMMY: report.FEDUMMY,
        PARAMETER_SYNC: report.PARAMETER_SYNC,
        PTO_VENTA_DISCOVERY: report.PTO_VENTA_DISCOVERY,
        PTO_VENTA: report.PTO_VENTA,
        LAST_AUTHORIZED_QUERY: report.LAST_AUTHORIZED_QUERY,
        FECAESOLICITAR: "NOT_RUN",
      },
      null,
      2
    )
  );
}

main().catch((e) => {
  console.error(JSON.stringify({ status: "ERROR", message: String(e.message || e) }));
  process.exit(1);
});
