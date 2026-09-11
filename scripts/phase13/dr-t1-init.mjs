#!/usr/bin/env node
/**
 * T1 — link disposable DR primary + push canonical migrations.
 * Never links Staging. Never touches Production.
 */
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const DR_DIR = path.join(ROOT, "docs", "qa", "phase13", "dr");
const ENV_PATH = path.join(ROOT, ".env.dr.local");
const STAGING = "rpcpdrzbcclofvjpgldb";

function loadEnv(p) {
  const map = {};
  if (!fs.existsSync(p)) throw new Error(`missing ${p}`);
  for (const line of fs.readFileSync(p, "utf8").split(/\r?\n/)) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (m) map[m[1]] = m[2];
  }
  return map;
}

function redacted(s, secrets) {
  let out = String(s || "");
  for (const sec of secrets) {
    if (sec) out = out.split(sec).join("[REDACTED]");
  }
  return out;
}

function sh(cmd, secrets) {
  try {
    return {
      ok: true,
      out: execSync(cmd, {
        cwd: ROOT,
        encoding: "utf8",
        timeout: 600000,
        windowsHide: true,
        stdio: ["ignore", "pipe", "pipe"],
        shell: true,
      }),
    };
  } catch (e) {
    return {
      ok: false,
      out: redacted(
        String(e.stdout || "") + "\n" + String(e.stderr || e.message || e),
        secrets
      ),
    };
  }
}

const started = new Date().toISOString();
const env = loadEnv(ENV_PATH);
const ref = env.DR_PRIMARY_REF;
const password = env.DR_PRIMARY_DB_PASSWORD;
const secrets = [password];

const result = {
  status: "RUNNING",
  started,
  finished: null,
  DR_PRIMARY_REF: ref,
  staging_ref: STAGING,
  DR_PRIMARY_INITIALIZED: "FAIL",
  steps: [],
};

function step(name, ok, detail) {
  result.steps.push({
    name,
    ok,
    at: new Date().toISOString(),
    detail: redacted(detail, secrets).slice(0, 4000),
  });
}

fs.writeFileSync(path.join(DR_DIR, "DR-T1.json"), JSON.stringify(result, null, 2));

if (!ref || ref === STAGING) {
  result.status = "BLOCKED_BAD_REF";
  result.finished = new Date().toISOString();
  fs.writeFileSync(path.join(DR_DIR, "DR-T1.json"), JSON.stringify(result, null, 2));
  process.exit(1);
}

const link = sh(
  `npx supabase link --project-ref ${ref} --password ${JSON.stringify(password)}`,
  secrets
);
step("link", link.ok, link.out);
if (!link.ok) {
  result.status = "LINK_FAILED";
  result.finished = new Date().toISOString();
  fs.writeFileSync(path.join(DR_DIR, "DR-T1.json"), JSON.stringify(result, null, 2));
  process.exit(1);
}

const push = sh(
  `npx supabase db push --include-all --password ${JSON.stringify(password)}`,
  secrets
);
step("db_push", push.ok, push.out);
if (!push.ok) {
  result.status = "PUSH_FAILED";
  result.finished = new Date().toISOString();
  fs.writeFileSync(path.join(DR_DIR, "DR-T1.json"), JSON.stringify(result, null, 2));
  process.exit(1);
}

const list = sh(`npx supabase migration list --project-ref ${ref}`, secrets);
step("migration_list", list.ok, list.out);

const keys = sh(`npx supabase projects api-keys --project-ref ${ref} -o json`, secrets);
step("api_keys", keys.ok, keys.out.includes("anon") || keys.ok ? "keys retrieved" : keys.out);

if (keys.ok) {
  try {
    const arr = JSON.parse(keys.out);
    const anon = arr.find((k) => k.name === "anon" || k.tags?.includes?.("anon"))?.api_key;
    const service = arr.find(
      (k) => k.name === "service_role" || k.tags?.includes?.("service_role")
    )?.api_key;
    if (anon) {
      fs.appendFileSync(
        ENV_PATH,
        [
          `DR_PRIMARY_URL=https://${ref}.supabase.co`,
          `DR_PRIMARY_ANON_KEY=${anon}`,
          service ? `DR_PRIMARY_SERVICE_ROLE_KEY=${service}` : "",
          "",
        ]
          .filter(Boolean)
          .join("\n") + "\n"
      );
      step("persist_keys", true, "appended to .env.dr.local (gitignored)");
    }
  } catch (e) {
    step("persist_keys", false, String(e.message || e));
  }
}

result.status = push.ok ? "INITIALIZED" : "PARTIAL";
result.DR_PRIMARY_INITIALIZED = push.ok ? "PASS" : "FAIL";
result.finished = new Date().toISOString();
fs.writeFileSync(path.join(DR_DIR, "DR-T1.json"), JSON.stringify(result, null, 2));
process.exit(push.ok ? 0 : 1);
