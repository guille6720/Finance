#!/usr/bin/env node
/**
 * Phase 13 clean-room rebuild (LOCAL disposable DB only).
 * Does NOT touch Production or paid remote resources.
 */
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { ROOT, PHASE13_DIR } from "./env.mjs";
import { verifyProvenance, writeProvenance } from "./provenance.mjs";
import { compareFingerprint } from "./fingerprint.mjs";
import { runPhase1to12Gates } from "./gates-phase1-12.mjs";

function section(title) {
  console.log(`\n=== ${title} ===`);
}

function printResult(name, result) {
  console.log(`${name}: ${result.status}`);
  if (result.detail) console.log(`  ${result.detail}`);
  if (result.drift?.length) {
    for (const d of result.drift) console.log(`  drift: ${d}`);
  }
  if (result.failed?.length) {
    for (const f of result.failed.slice(0, 20)) {
      console.log(`  fail: ${f.id}${f.note ? ` (${f.note})` : ""}`);
    }
  }
}

async function main() {
  fs.mkdirSync(PHASE13_DIR, { recursive: true });
  const results = {};

  section("CLEAN ROOM MIGRATIONS");
  try {
    execSync("npx supabase db reset --yes", {
      cwd: ROOT,
      stdio: "inherit",
      env: process.env,
    });
    results.CLEAN_ROOM_MIGRATIONS = {
      status: "PASS",
      detail: "db reset applied all migrations + seed.sql",
    };
  } catch (err) {
    results.CLEAN_ROOM_MIGRATIONS = {
      status: "FAIL",
      detail: String(err?.message || err),
    };
  }
  printResult("CLEAN ROOM MIGRATIONS", results.CLEAN_ROOM_MIGRATIONS);

  section("MIGRATION PROVENANCE");
  // First cleanroom creates provenance; later runs verify unless explicitly updated.
  if (!fs.existsSync(path.join(PHASE13_DIR, "migration-provenance.json"))) {
    writeProvenance();
  }
  results.MIGRATION_PROVENANCE = verifyProvenance();
  printResult("MIGRATION PROVENANCE", results.MIGRATION_PROVENANCE);

  section("SCHEMA FINGERPRINT");
  const fpUpdate =
    process.env.PHASE13_UPDATE_FINGERPRINT === "1" ||
    !fs.existsSync(path.join(PHASE13_DIR, "schema-fingerprint.expected.json"));
  results.SCHEMA_FINGERPRINT = await compareFingerprint({ update: fpUpdate });
  printResult("SCHEMA FINGERPRINT", results.SCHEMA_FINGERPRINT);

  section("SCHEMA DRIFT");
  const driftCount = results.SCHEMA_FINGERPRINT.drift?.length || 0;
  results.SCHEMA_DRIFT = {
    status: driftCount === 0 ? "PASS" : "FAIL",
    detail: `SCHEMA DRIFT: ${driftCount} unexplained`,
    drift: results.SCHEMA_FINGERPRINT.drift || [],
  };
  printResult("SCHEMA DRIFT", results.SCHEMA_DRIFT);

  section("PHASE 1–12 GATES FROM EMPTY DB");
  results.PHASE_1_12_GATES = await runPhase1to12Gates();
  printResult("PHASE 1–12 GATES FROM EMPTY DB", results.PHASE_1_12_GATES);

  const required = [
    ["CLEAN ROOM MIGRATIONS", results.CLEAN_ROOM_MIGRATIONS],
    ["MIGRATION PROVENANCE", results.MIGRATION_PROVENANCE],
    ["SCHEMA FINGERPRINT", results.SCHEMA_FINGERPRINT],
    ["SCHEMA DRIFT", results.SCHEMA_DRIFT],
    ["PHASE 1–12 GATES FROM EMPTY DB", results.PHASE_1_12_GATES],
  ];

  const allPass = required.every(([, r]) => r.status === "PASS");
  results.CLEAN_ROOM_REBUILD = {
    status: allPass ? "PASS" : "FAIL",
    detail: allPass
      ? "all clean-room requirements passed"
      : "one or more clean-room requirements failed",
  };

  section("SUMMARY");
  printResult("CLEAN-ROOM REBUILD", results.CLEAN_ROOM_REBUILD);
  for (const [name, r] of required) printResult(name, r);

  const outPath = path.join(PHASE13_DIR, "cleanroom-last-run.json");
  fs.writeFileSync(outPath, JSON.stringify(results, null, 2) + "\n");
  console.log(`\nWrote ${outPath}`);

  if (!allPass) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
