#!/usr/bin/env node
/**
 * Delete disposable DR primary only. Evidence must already be preserved.
 */
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const DR_DIR = path.join(ROOT, "docs", "qa", "phase13", "dr");
const TARGET = "yqqqocmbuxgagounywtp";
const STAGING = "rpcpdrzbcclofvjpgldb";

const required = [
  "DR-T0.json",
  "DR-T1.json",
  "DR-T2.json",
  "DR-FIXTURE-MANIFEST.json",
  "DR-FIXTURE-VALIDATION.json",
  "DR_FIXTURE_PURCHASE_EVIDENCE.pdf",
  "DR-PAUSE-EVIDENCE.json",
];
const missing = required.filter((f) => !fs.existsSync(path.join(DR_DIR, f)));

const out = {
  started: new Date().toISOString(),
  finished: null,
  evidence_ok: missing.length === 0,
  missing,
  target_ref: TARGET,
  staging_ref: STAGING,
  deleted: false,
  error: null,
  manual_delete_url: `https://supabase.com/dashboard/project/${TARGET}/settings/general`,
};

if (TARGET === STAGING || missing.length) {
  out.error = TARGET === STAGING ? "REFUSES_STAGING" : "EVIDENCE_INCOMPLETE";
  out.finished = new Date().toISOString();
  out.DR_TEMP_RESOURCES_REMAINING = 1;
  fs.writeFileSync(path.join(DR_DIR, "DR-CLEANUP.json"), JSON.stringify(out, null, 2));
  process.exit(1);
}

try {
  // Global --yes before subcommand args; ref as positional.
  const raw = execSync(`npx supabase --yes projects delete ${TARGET}`, {
    cwd: ROOT,
    encoding: "utf8",
    timeout: 180000,
    windowsHide: true,
    stdio: ["pipe", "pipe", "pipe"],
    shell: true,
    input: "y\n",
  });
  out.deleted = true;
  out.cli_out = String(raw).slice(0, 2000);
} catch (e) {
  out.error = String(e.stderr || e.stdout || e.message || e).slice(0, 3000);
}

// Verify via projects list if possible
try {
  const list = execSync("npx supabase projects list -o json", {
    cwd: ROOT,
    encoding: "utf8",
    timeout: 120000,
    windowsHide: true,
    stdio: ["ignore", "pipe", "pipe"],
    shell: true,
  });
  const projects = JSON.parse(list);
  const still = projects.find((p) => p.ref === TARGET || p.id === TARGET);
  out.verified_absent = !still;
  if (still) {
    out.deleted = false;
    out.error = (out.error || "") + "\nSTILL_LISTED_AFTER_DELETE";
  } else if (!out.error) {
    out.deleted = true;
  }
} catch (e) {
  out.verify_error = String(e.message || e).slice(0, 500);
}

out.finished = new Date().toISOString();
out.DR_TEMP_RESOURCES_REMAINING = out.deleted && out.verified_absent !== false ? 0 : 1;
if (out.verified_absent === true) out.DR_TEMP_RESOURCES_REMAINING = 0;

fs.writeFileSync(path.join(DR_DIR, "DR-CLEANUP.json"), JSON.stringify(out, null, 2));

const pausePath = path.join(DR_DIR, "DR-PAUSE-EVIDENCE.json");
const pause = JSON.parse(fs.readFileSync(pausePath, "utf8"));
pause.cleanup.status = out.DR_TEMP_RESOURCES_REMAINING === 0 ? "DELETED" : "DELETE_FAILED_MANUAL_REQUIRED";
pause.cleanup.finished = out.finished;
pause.cleanup.DR_TEMP_RESOURCES_REMAINING = out.DR_TEMP_RESOURCES_REMAINING;
pause.cleanup.manual_delete_url = out.manual_delete_url;
fs.writeFileSync(pausePath, JSON.stringify(pause, null, 2));

process.exit(out.DR_TEMP_RESOURCES_REMAINING === 0 ? 0 : 1);
