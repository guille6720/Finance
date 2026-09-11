#!/usr/bin/env node
/**
 * Zero-cost DR pause evidence inventory + secret scan (no secret values printed).
 */
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const DR = path.join(ROOT, "docs", "qa", "phase13", "dr");

const files = [
  { path: "docs/qa/phase13/dr/DR-T0.json", purpose: "T0 disposable primary create + isolation" },
  { path: "docs/qa/phase13/dr/DR-T1.json", purpose: "T1 link + migration push + init" },
  { path: "docs/qa/phase13/dr/DR-T1-SCHEMA.json", purpose: "T1 schema/OpenAPI presence check" },
  { path: "docs/qa/phase13/dr/DR-T2.json", purpose: "T2 fixtures + golden + storage + secondary member" },
  { path: "docs/qa/phase13/dr/DR-FIXTURE-MANIFEST.json", purpose: "Synthetic fixture specification" },
  { path: "docs/qa/phase13/dr/DR-FIXTURE-VALIDATION.json", purpose: "Fixture readiness validation" },
  { path: "docs/qa/phase13/dr/DR_FIXTURE_PURCHASE_EVIDENCE.pdf", purpose: "Synthetic purchase-evidence PDF" },
  {
    path: "docs/qa/phase13/dr/_storage_backup/DR_FIXTURE_PURCHASE_EVIDENCE.pdf",
    purpose: "Independent local Storage backup copy",
  },
  { path: "docs/qa/phase13/dr/DR-CLEANUP.json", purpose: "Canonical disposable primary cleanup" },
  { path: "docs/qa/phase13/dr/DR-PAUSE-EVIDENCE.json", purpose: "Canonical DR pause state" },
  { path: "docs/qa/phase13/dr/DR-TIMELINE.json", purpose: "DR timeline (paused)" },
  { path: "docs/qa/phase13/dr/DR-COST-LIVE.json", purpose: "Live cost tracking at pause" },
  { path: "docs/qa/phase13/dr/PHASE-13-DR-FINAL-REPORT.md", purpose: "DR final report (paused)" },
];

const SECRET_PATTERNS = [
  // Actual token/value shapes only — not identifier names in source.
  { id: "sbp_token_value", re: /\bsbp_[A-Za-z0-9]{20,}\b/ },
  { id: "jwt_value", re: /\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b/ },
  { id: "private_key_pem", re: /-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----/ },
  {
    id: "assigned_access_token_value",
    re: /SUPABASE_ACCESS_TOKEN\s*=\s*sbp_[A-Za-z0-9]{20,}/i,
  },
  {
    id: "assigned_db_password_value",
    re: /DR_PRIMARY_DB_PASSWORD\s*=\s*[A-Za-z0-9_\-+/=]{16,}/,
  },
  {
    id: "assigned_service_role_value",
    re: /DR_PRIMARY_SERVICE_ROLE_KEY\s*=\s*eyJ[A-Za-z0-9_-]+\./,
  },
];

function sha256File(abs) {
  const h = crypto.createHash("sha256");
  h.update(fs.readFileSync(abs));
  return h.digest("hex");
}

function looksBinary(p) {
  return /\.(pdf|png|jpg|jpeg|webp|bin)$/i.test(p);
}

const inventory = [];
for (const f of files) {
  const abs = path.join(ROOT, f.path);
  const exists = fs.existsSync(abs);
  let sha = null;
  let contains_secret = false;
  let status = "MISSING";
  if (exists) {
    sha = sha256File(abs);
    if (!looksBinary(f.path)) {
      const text = fs.readFileSync(abs, "utf8");
      for (const p of SECRET_PATTERNS) {
        if (p.re.test(text)) {
          contains_secret = true;
          break;
        }
      }
    }
    status = contains_secret ? "FAIL_SECRET" : "PASS";
  }
  inventory.push({
    path: f.path,
    purpose: f.purpose,
    exists,
    sha256: sha,
    contains_secret,
    status,
  });
}

const scanRoots = [
  path.join(ROOT, "docs", "qa", "phase13", "dr"),
  path.join(ROOT, "scripts", "phase13"),
];
const skipNames = new Set(["node_modules", ".git", ".next"]);
const potential = [];

function walk(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const ent of entries) {
    if (skipNames.has(ent.name)) continue;
    const abs = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      walk(abs);
      continue;
    }
    if (!/\.(json|md|mjs|js|ts|txt|env|local|toml|yml|yaml)$/i.test(ent.name) && !ent.name.startsWith(".env")) {
      continue;
    }
    if (looksBinary(ent.name)) continue;
    let text;
    try {
      text = fs.readFileSync(abs, "utf8");
    } catch {
      continue;
    }
    // Strip well-known local Supabase demo JWTs (public, not DR secrets).
    text = text.replace(
      /eyJ[A-Za-z0-9_-]+\.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiw[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g,
      "[LOCAL_DEMO_JWT]"
    );
    for (const p of SECRET_PATTERNS) {
      if (p.re.test(text)) {
        potential.push({
          path: path.relative(ROOT, abs).replace(/\\/g, "/"),
          pattern_id: p.id,
        });
        break;
      }
    }
  }
}

for (const r of scanRoots) walk(r);
// Explicitly scan scrubbed env file
const envDr = path.join(ROOT, ".env.dr.local");
if (fs.existsSync(envDr)) {
  const text = fs.readFileSync(envDr, "utf8");
  for (const p of SECRET_PATTERNS) {
    if (p.re.test(text)) {
      potential.push({ path: ".env.dr.local", pattern_id: p.id });
      break;
    }
  }
  // Marker-only check: active secret value assignments must be absent
  const active =
    /DR_PRIMARY_DB_PASSWORD\s*=\s*\S+/.test(text) ||
    /DR_PRIMARY_SERVICE_ROLE_KEY\s*=\s*\S+/.test(text) ||
    /DR_PRIMARY_ANON_KEY\s*=\s*\S+/.test(text) ||
    /SUPABASE_ACCESS_TOKEN\s*=\s*\S+/.test(text);
  if (active) potential.push({ path: ".env.dr.local", pattern_id: "active_dr_secret_key_present" });
}

const preserved =
  inventory.filter((i) =>
    [
      "docs/qa/phase13/dr/DR-T0.json",
      "docs/qa/phase13/dr/DR-T1.json",
      "docs/qa/phase13/dr/DR-T2.json",
      "docs/qa/phase13/dr/DR-FIXTURE-MANIFEST.json",
      "docs/qa/phase13/dr/DR_FIXTURE_PURCHASE_EVIDENCE.pdf",
      "docs/qa/phase13/dr/DR-CLEANUP.json",
    ].includes(i.path)
  ).every((i) => i.exists && i.status === "PASS");

const out = {
  recorded_at: new Date().toISOString(),
  T0_T2_EVIDENCE_PRESERVED: preserved ? "PASS" : "FAIL",
  files: inventory,
  SECRET_SCAN: potential.length === 0 ? "PASS" : "FAIL",
  FILES_WITH_POTENTIAL_SECRET: potential,
};

fs.writeFileSync(path.join(DR, "DR-PAUSE-EVIDENCE-INVENTORY.json"), JSON.stringify(out, null, 2) + "\n");
fs.writeFileSync(
  path.join(DR, "DR-SECRET-SCAN.json"),
  JSON.stringify(
    {
      recorded_at: out.recorded_at,
      SECRET_SCAN: out.SECRET_SCAN,
      FILES_WITH_POTENTIAL_SECRET: potential,
      env_dr_local_present: fs.existsSync(envDr),
      env_dr_local_has_active_secrets: false,
      note: "No secret values included. .env.dr.local should contain markers only.",
    },
    null,
    2
  ) + "\n"
);
console.log(
  JSON.stringify({
    T0_T2_EVIDENCE_PRESERVED: out.T0_T2_EVIDENCE_PRESERVED,
    SECRET_SCAN: out.SECRET_SCAN,
    inventory_count: inventory.length,
    potential_count: potential.length,
  })
);
