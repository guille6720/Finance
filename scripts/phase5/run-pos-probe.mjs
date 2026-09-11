#!/usr/bin/env node
/**
 * LIVE_HOMOLOGATION POS probe — read-only.
 * WSAA + FECompUltimoAutorizado for PV 1/2/10, CbteTipo 11.
 * Never calls FEParamGetPtosVenta / FECAESolicitar / FECompConsultar.
 * Never prints secrets/token/sign/CUIT.
 *
 * Usage: npm run test:arca:homo:pos-probe
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const OUT = path.join(ROOT, "docs", "qa", "phase5", "ARCA-HOMOLOGATION-POS-PROBE.json");

async function main() {
  const arca = await import(
    pathToFileURL(path.join(ROOT, "src/server/arca/index.ts")).href
  );

  arca.loadArcaHomoEnvFile(ROOT);
  if (!process.env.ARCA_ENV && process.env.ARCA_HOMO_CERT_B64) {
    process.env.ARCA_ENV = "homologation";
  }

  const report = {
    label: "LIVE_HOMOLOGATION_POS_PROBE",
    recorded_at: new Date().toISOString(),
    methods: ["WSAA loginCms", "FECompUltimoAutorizado"],
    cbte_tipo: 11,
    points: [1, 2, 10],
    forbidden: ["FECAESolicitar", "FECompConsultar", "FEParamGetPtosVenta"],
    WSAA_HOMOLOGATION: "NOT_RUN",
    probes: [],
    FECAESOLICITAR: "NOT_RUN",
    ARCA_PRODUCTION: "NOT_AUTHORIZED",
    BLOCKER: null,
    ROOT_CAUSE: null,
  };

  const cfgTry = arca.tryGetArcaHomologationConfig();
  if (!cfgTry.ok) {
    report.BLOCKER = cfgTry.error.code;
    report.ROOT_CAUSE = cfgTry.error.message;
    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify({ status: "BLOCKED", code: report.BLOCKER }, null, 2));
    process.exit(2);
  }

  const config = cfgTry.config;

  try {
    await arca.getValidTa(config);
    report.WSAA_HOMOLOGATION = "PASS";
  } catch (e) {
    report.WSAA_HOMOLOGATION = "FAIL";
    report.BLOCKER = e.code || "WSAA_FAIL";
    report.ROOT_CAUSE = e.message;
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify({ status: "STOP", stage: "wsaa", code: report.BLOCKER }, null, 2));
    process.exit(1);
  }

  report.probes = await arca.probeHomologationPos(config, [1, 2, 10], 11);

  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + "\n");
  console.log(
    JSON.stringify(
      {
        status: "OK_POS_PROBE",
        WSAA_HOMOLOGATION: report.WSAA_HOMOLOGATION,
        probes: report.probes,
        FECAESOLICITAR: "NOT_RUN",
        ARCA_PRODUCTION: "NOT_AUTHORIZED",
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
