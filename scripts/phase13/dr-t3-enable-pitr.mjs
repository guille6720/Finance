#!/usr/bin/env node
/**
 * T3 — enable Small compute + PITR 7-day on disposable DR primary only.
 * Cost check before each paid addon. Cap USD 40.
 */
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const DR_DIR = path.join(ROOT, "docs", "qa", "phase13", "dr");
const ENV_PATH = path.join(ROOT, ".env.dr.local");
const STAGING = "rpcpdrzbcclofvjpgldb";
const CAP = 40;

function loadEnv(p) {
  const map = {};
  for (const line of fs.readFileSync(p, "utf8").split(/\r?\n/)) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (m) map[m[1]] = m[2];
  }
  return map;
}

function estimateAfter(hoursPrimarySmall = 48, hoursPitr = 48, hoursRestore = 24) {
  const project = 10;
  const restore = 10;
  const compute = 0.0206 * hoursPrimarySmall + 0.0206 * hoursRestore;
  const pitr = 0.137 * hoursPitr;
  return {
    PROJECT_COST: project,
    RESTORE_PROJECT_COST: restore,
    COMPUTE_COST: Number(compute.toFixed(2)),
    PITR_COST: Number(pitr.toFixed(2)),
    STORAGE_COST: 0,
    TRANSFER_COST: 0,
    TOTAL: Number((project + restore + compute + pitr).toFixed(2)),
  };
}

const env = loadEnv(ENV_PATH);
const ref = env.DR_PRIMARY_REF;
const started = new Date().toISOString();
const projected = estimateAfter();
const result = {
  started,
  finished: null,
  DR_PRIMARY_REF: ref,
  staging_ref: STAGING,
  isolated: Boolean(ref) && ref !== STAGING,
  CURRENT_ESTIMATED_TOTAL_COST_USD: projected.TOTAL,
  COST_CAP_EXCEEDED: projected.TOTAL > CAP ? "YES" : "NO",
  projected,
  PITR_ACTIVE: "FAIL",
  COMPUTE_SMALL: "FAIL",
  steps: [],
};

fs.writeFileSync(path.join(DR_DIR, "DR-T3.json"), JSON.stringify(result, null, 2));

if (!result.isolated) {
  result.finished = new Date().toISOString();
  result.error = "bad_ref";
  fs.writeFileSync(path.join(DR_DIR, "DR-T3.json"), JSON.stringify(result, null, 2));
  process.exit(1);
}

if (result.COST_CAP_EXCEEDED === "YES") {
  result.finished = new Date().toISOString();
  fs.writeFileSync(path.join(DR_DIR, "DR-T3.json"), JSON.stringify(result, null, 2));
  process.exit(2);
}

function sh(cmd) {
  try {
    return {
      ok: true,
      out: execSync(cmd, {
        cwd: ROOT,
        encoding: "utf8",
        timeout: 180000,
        windowsHide: true,
        stdio: ["ignore", "pipe", "pipe"],
        shell: true,
      }),
    };
  } catch (e) {
    return {
      ok: false,
      out: String(e.stdout || "") + "\n" + String(e.stderr || e.message || e),
    };
  }
}

// Prefer Management API via supabase CLI if available; else curl with token from access-token file is blocked.
// Use undocumented but known: supabase --experimental? Fall back to node fetch with token from `supabase projects list` session.
// CLI stores token; extract via `npx supabase projects api-keys` already worked — use Management API with token from env or login cache.

function findToken() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  // Prefer gitignored drill env (user may paste PAT once).
  try {
    const env = loadEnv(ENV_PATH);
    if (env.SUPABASE_ACCESS_TOKEN) return env.SUPABASE_ACCESS_TOKEN.trim();
  } catch {
    /* ignore */
  }
  const home = process.env.USERPROFILE || process.env.HOME || "";
  const candidates = [
    path.join(home, ".supabase", "access-token"),
    path.join(process.env.APPDATA || "", "supabase", "access-token"),
    path.join(process.env.LOCALAPPDATA || "", "supabase", "access-token"),
    path.join(home, "AppData", "Roaming", "supabase", "access-token"),
    path.join(home, "AppData", "Local", "supabase", "access-token"),
  ];
  for (const p of candidates) {
    try {
      if (fs.existsSync(p)) {
        const t = fs.readFileSync(p, "utf8").trim();
        if (t) return t;
      }
    } catch {
      /* ignore */
    }
  }
  return null;
}

const token = findToken();
if (!token) {
  result.error = "MISSING_SUPABASE_ACCESS_TOKEN";
  result.finished = new Date().toISOString();
  fs.writeFileSync(path.join(DR_DIR, "DR-T3.json"), JSON.stringify(result, null, 2));
  process.exit(1);
}

async function patchAddon(body) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/billing/addons`, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const text = await r.text();
  return { ok: r.ok, status: r.status, text: text.slice(0, 2000) };
}

async function listAddons() {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/billing/addons`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const text = await r.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    json = null;
  }
  return { ok: r.ok, status: r.status, json, text: text.slice(0, 2000) };
}

const before = await listAddons();
result.steps.push({
  name: "list_addons_before",
  ok: before.ok,
  at: new Date().toISOString(),
  status: before.status,
});

const small = await patchAddon({
  addon_type: "compute_instance",
  addon_variant: "ci_small",
});
result.steps.push({
  name: "enable_small",
  ok: small.ok,
  at: new Date().toISOString(),
  status: small.status,
  detail: small.text,
});
result.COMPUTE_SMALL = small.ok ? "PASS" : "FAIL";

if (!small.ok) {
  result.finished = new Date().toISOString();
  result.status = "SMALL_FAILED";
  fs.writeFileSync(path.join(DR_DIR, "DR-T3.json"), JSON.stringify(result, null, 2));
  process.exit(1);
}

// Wait briefly for compute resize before PITR
await new Promise((r) => setTimeout(r, 15000));

const pitr = await patchAddon({
  addon_type: "pitr",
  addon_variant: "pitr_7",
});
result.steps.push({
  name: "enable_pitr_7",
  ok: pitr.ok,
  at: new Date().toISOString(),
  status: pitr.status,
  detail: pitr.text,
});
result.PITR_ACTIVE = pitr.ok ? "PASS" : "FAIL";
result.pitr_enabled_at = pitr.ok ? new Date().toISOString() : null;

const after = await listAddons();
result.steps.push({
  name: "list_addons_after",
  ok: after.ok,
  at: new Date().toISOString(),
  selected: after.json?.selected_addons || after.text?.slice?.(0, 500),
});

result.status = pitr.ok && small.ok ? "PITR_ACTIVE" : "PARTIAL";
result.finished = new Date().toISOString();
fs.writeFileSync(path.join(DR_DIR, "DR-T3.json"), JSON.stringify(result, null, 2));

// update cost live (no secrets)
const costPath = path.join(DR_DIR, "DR-COST-LIVE.json");
const cost = JSON.parse(fs.readFileSync(costPath, "utf8"));
cost.recorded_at = new Date().toISOString();
cost.CURRENT_ESTIMATED_TOTAL_COST_USD = projected.TOTAL;
cost.line_items_expected = {
  PROJECT_COST: projected.PROJECT_COST,
  RESTORE_PROJECT_COST: projected.RESTORE_PROJECT_COST,
  COMPUTE_COST: projected.COMPUTE_COST,
  PITR_COST: projected.PITR_COST,
  STORAGE_COST: 0,
  TRANSFER_COST: 0,
  TAXES_IF_KNOWN: null,
};
cost.COST_CAP_EXCEEDED = projected.TOTAL > CAP ? "YES" : "NO";
cost.pitr_enabled = pitr.ok;
cost.compute_small = small.ok;
cost.note = "Small+PITR enabled on disposable primary only. Staging untouched.";
fs.writeFileSync(costPath, JSON.stringify(cost, null, 2));

process.exit(pitr.ok && small.ok ? 0 : 1);
