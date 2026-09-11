#!/usr/bin/env node
/**
 * T0 — create disposable DR primary. Does not touch Staging.
 * Writes evidence JSON. Password goes only to gitignored .env.dr.local.
 */
import { execSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const DR_DIR = path.join(ROOT, "docs", "qa", "phase13", "dr");
const ENV_PATH = path.join(ROOT, ".env.dr.local");
const STAGING_REF = "rpcpdrzbcclofvjpgldb";
const ORG = "qsgnqyleasarodfwzlwe";
const NAME = "CONTABILIUM-DR-PRIMARY";
const REGION = "sa-east-1";

fs.writeFileSync(
  path.join(DR_DIR, "DR-T0.json"),
  JSON.stringify({ status: "STARTING", at: new Date().toISOString() }, null, 2)
);

const password = crypto.randomBytes(24).toString("base64url");

const existing = fs.existsSync(ENV_PATH) ? fs.readFileSync(ENV_PATH, "utf8") : "";
if (/DR_PRIMARY_REF=.+/.test(existing) && !process.env.DR_FORCE_CREATE) {
  fs.writeFileSync(
    path.join(DR_DIR, "DR-T0.json"),
    JSON.stringify(
      {
        status: "SKIPPED_ALREADY_HAS_REF",
        at: new Date().toISOString(),
      },
      null,
      2
    )
  );
  process.exit(0);
}

fs.writeFileSync(
  ENV_PATH,
  [
    "# Disposable DR drill only. Gitignored. Revoke after cleanup.",
    `DR_ORG_ID=${ORG}`,
    `DR_PRIMARY_NAME=${NAME}`,
    `DR_PRIMARY_REGION=${REGION}`,
    `DR_PRIMARY_DB_PASSWORD=${password}`,
    `STAGING_SUPABASE_PROJECT_REF=${STAGING_REF}`,
    "",
  ].join("\n"),
  { mode: 0o600 }
);

let raw = "";
try {
  const cmd = [
    "npx supabase projects create",
    NAME,
    "--org-id",
    ORG,
    "--region",
    REGION,
    "--size",
    "micro",
    "--db-password",
    password,
  ].join(" ");
  raw = execSync(cmd, {
    cwd: ROOT,
    encoding: "utf8",
    timeout: 180000,
    windowsHide: true,
    stdio: ["ignore", "pipe", "pipe"],
    shell: true,
  });
} catch (e) {
  const err = String(e.stderr || e.stdout || e.message || e);
  fs.writeFileSync(
    path.join(DR_DIR, "DR-T0.json"),
    JSON.stringify(
      {
        status: "CREATE_FAILED",
        at: new Date().toISOString(),
        error: err.slice(0, 4000).replace(password, "[REDACTED]"),
        staging_ref: STAGING_REF,
      },
      null,
      2
    )
  );
  process.exit(1);
}

const safeRaw = String(raw).replaceAll(password, "[REDACTED]");
let parsed = null;
try {
  parsed = JSON.parse(raw);
} catch {
  const m = raw.match(/"id"\s*:\s*"([a-z]{20})"/);
  if (m) parsed = { id: m[1], ref: m[1] };
}

const ref = parsed?.id || parsed?.ref || null;
if (ref && ref !== STAGING_REF) {
  fs.appendFileSync(ENV_PATH, `DR_PRIMARY_REF=${ref}\n`);
}

const isolated = Boolean(ref) && ref !== STAGING_REF;
fs.writeFileSync(
  path.join(DR_DIR, "DR-T0.json"),
  JSON.stringify(
    {
      status: isolated ? "CREATED" : "CREATE_AMBIGUOUS",
      at: new Date().toISOString(),
      name: NAME,
      org_id: ORG,
      region: REGION,
      ref,
      staging_ref: STAGING_REF,
      DR_PRIMARY_ISOLATED: isolated ? "PASS" : "FAIL",
      stdout_redacted: safeRaw.slice(0, 4000),
    },
    null,
    2
  )
);
if (!isolated) process.exit(1);
