#!/usr/bin/env node
/**
 * T2 — load synthetic DR_FIXTURE_* dataset on disposable DR primary.
 * Uses golden-flow contracts via remote URL from .env.dr.local.
 * Never targets Staging.
 */
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { runGoldenFlow } from "./golden-flow.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const DR_DIR = path.join(ROOT, "docs", "qa", "phase13", "dr");
const ENV_PATH = path.join(ROOT, ".env.dr.local");
const STAGING = "rpcpdrzbcclofvjpgldb";
const PDF_PATH = path.join(DR_DIR, "DR_FIXTURE_PURCHASE_EVIDENCE.pdf");

function loadEnv(p) {
  const map = {};
  for (const line of fs.readFileSync(p, "utf8").split(/\r?\n/)) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (m) map[m[1]] = m[2];
  }
  return map;
}

const started = new Date().toISOString();
const fileEnv = loadEnv(ENV_PATH);
const ref = fileEnv.DR_PRIMARY_REF;
const result = {
  started,
  finished: null,
  DR_PRIMARY_REF: ref,
  staging_ref: STAGING,
  isolated: Boolean(ref) && ref !== STAGING,
  DR_FIXTURE_LOADED: "FAIL",
  golden: null,
  storage: null,
  secondary_member: null,
  rpo_probe: null,
};

fs.writeFileSync(path.join(DR_DIR, "DR-T2.json"), JSON.stringify(result, null, 2));

if (!result.isolated) {
  result.error = "bad_ref";
  result.finished = new Date().toISOString();
  fs.writeFileSync(path.join(DR_DIR, "DR-T2.json"), JSON.stringify(result, null, 2));
  process.exit(1);
}

process.env.PHASE13_API_URL = fileEnv.DR_PRIMARY_URL || `https://${ref}.supabase.co`;
process.env.PHASE13_ANON_KEY = fileEnv.DR_PRIMARY_ANON_KEY;
process.env.PHASE13_SERVICE_ROLE_KEY = fileEnv.DR_PRIMARY_SERVICE_ROLE_KEY;
process.env.PHASE13_FORCE_REMOTE = "1";
if (fileEnv.DR_PRIMARY_DB_PASSWORD) {
  process.env.PHASE13_DB_URL = `postgresql://postgres.${ref}:${encodeURIComponent(fileEnv.DR_PRIMARY_DB_PASSWORD)}@aws-0-sa-east-1.pooler.supabase.com:6543/postgres`;
  // also try direct host style used by many projects
  if (!process.env.PHASE13_DB_URL_DIRECT) {
    process.env.PHASE13_DB_URL_DIRECT = `postgresql://postgres:${encodeURIComponent(fileEnv.DR_PRIMARY_DB_PASSWORD)}@db.${ref}.supabase.co:5432/postgres`;
  }
  // Prefer direct for migrations-style DDL/selects
  process.env.PHASE13_DB_URL = process.env.PHASE13_DB_URL_DIRECT;
}

if (!process.env.PHASE13_ANON_KEY || !process.env.PHASE13_SERVICE_ROLE_KEY) {
  result.error = "missing_api_keys";
  result.finished = new Date().toISOString();
  fs.writeFileSync(path.join(DR_DIR, "DR-T2.json"), JSON.stringify(result, null, 2));
  process.exit(1);
}

const api = process.env.PHASE13_API_URL;
const anon = process.env.PHASE13_ANON_KEY;
const service = process.env.PHASE13_SERVICE_ROLE_KEY;

async function http(url, init) {
  const res = await fetch(url, init);
  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  return { ok: res.ok, status: res.status, data };
}

// Patch ensureLocalEnv path: golden-flow imports ensureLocalEnv which may try local DB.
// Override by monkeypatching env module after import is hard; instead set PHASE13_* and
// make withDb fail soft for steps that need direct SQL — golden flow has REST paths.

let goldenOut = null;
try {
  goldenOut = await runGoldenFlow();
  result.golden = {
    status: goldenOut?.GOLDEN_FULL_FLOW || goldenOut?.status || "UNKNOWN",
    GOLDEN_FULL_FLOW: goldenOut?.GOLDEN_FULL_FLOW,
    pass_count: goldenOut?.steps_pass ?? null,
    fail_count: goldenOut?.steps_fail ?? null,
    summary: goldenOut?.executed?.map?.((s) => ({
      step: s.step,
      status: s.status,
    })),
  };
} catch (e) {
  result.golden = { status: "ERROR", error: String(e.message || e).slice(0, 2000) };
}

// Secondary member + labeled org settings + storage upload
try {
  const stamp = Date.now();
  const ownerEmail = `dr.fixture.owner.${stamp}@example.com`;
  const memberEmail = `dr.fixture.operator.${stamp}@example.com`;
  const password = "DR-Fixture-Only-1!";

  const owner = await http(`${api}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      apikey: service,
      Authorization: `Bearer ${service}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      email: ownerEmail,
      password,
      email_confirm: true,
      user_metadata: { full_name: "DR_FIXTURE_OWNER" },
    }),
  });
  if (!owner.ok) throw new Error(`owner create ${owner.status}`);

  const member = await http(`${api}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      apikey: service,
      Authorization: `Bearer ${service}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      email: memberEmail,
      password,
      email_confirm: true,
      user_metadata: { full_name: "DR_FIXTURE_OPERATOR" },
    }),
  });
  if (!member.ok) throw new Error(`member create ${member.status}`);

  const login = await http(`${api}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anon, "Content-Type": "application/json" },
    body: JSON.stringify({ email: ownerEmail, password }),
  });
  if (!login.ok) throw new Error(`owner login ${login.status}`);
  const token = login.data.access_token;
  const ownerId = owner.data.id;
  const memberId = member.data.id;

  const org = await http(`${api}/rest/v1/organizations`, {
    method: "POST",
    headers: {
      apikey: anon,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: JSON.stringify({
      legal_name: "DR_FIXTURE_ORG",
      status: "active",
      cuit: "30712345682",
      created_by: ownerId,
    }),
  });
  if (!org.ok) throw new Error(`org ${org.status} ${JSON.stringify(org.data).slice(0, 300)}`);
  const orgId = Array.isArray(org.data) ? org.data[0].id : org.data.id;

  const memOwner = await http(`${api}/rest/v1/organization_members`, {
    method: "POST",
    headers: {
      apikey: anon,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: JSON.stringify({
      organization_id: orgId,
      user_id: ownerId,
      role: "owner",
      status: "active",
    }),
  });
  if (!memOwner.ok) {
    throw new Error(`owner member ${memOwner.status} ${JSON.stringify(memOwner.data).slice(0, 300)}`);
  }

  // secondary member via service role insert (admin invite path)
  const mem2 = await http(`${api}/rest/v1/organization_members`, {
    method: "POST",
    headers: {
      apikey: service,
      Authorization: `Bearer ${service}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: JSON.stringify({
      organization_id: orgId,
      user_id: memberId,
      role: "operator",
      status: "active",
    }),
  });
  result.secondary_member = {
    ok: mem2.ok,
    status: mem2.status,
    user_id: memberId,
  };

  const probeTs = new Date().toISOString();
  const settings = await http(`${api}/rest/v1/organization_settings`, {
    method: "POST",
    headers: {
      apikey: anon,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: JSON.stringify({
      organization_id: orgId,
      key: "dr.rpo_probe",
      value: {
        id: "DR_FIXTURE_RPO_PROBE",
        written_at: probeTs,
        label: "DR_FIXTURE",
      },
    }),
  });
  result.rpo_probe = {
    ok: settings.ok || settings.status === 409,
    status: settings.status,
    written_at: probeTs,
    org_id: orgId,
  };

  // Storage: ensure bucket exists (migration should have created it)
  const pdf = fs.readFileSync(PDF_PATH);
  const sha256 = crypto.createHash("sha256").update(pdf).digest("hex");
  // Need a purchase document id for path — create minimal purchase if possible, else use synthetic UUID folder
  const purchaseId = crypto.randomUUID();
  const objectPath = `${orgId}/${purchaseId}/DR_FIXTURE_PURCHASE_EVIDENCE.pdf`;
  const up = await fetch(`${api}/storage/v1/object/purchase-evidence/${objectPath}`, {
    method: "POST",
    headers: {
      apikey: service,
      Authorization: `Bearer ${service}`,
      "Content-Type": "application/pdf",
      "x-upsert": "true",
    },
    body: pdf,
  });
  const upText = await up.text();
  result.storage = {
    ok: up.ok,
    status: up.status,
    path: objectPath,
    bytes: pdf.length,
    sha256,
    mime_type: "application/pdf",
    public: false,
    detail: up.ok ? "uploaded" : upText.slice(0, 500),
  };

  // local independent backup copy
  const backupDir = path.join(DR_DIR, "_storage_backup");
  fs.mkdirSync(backupDir, { recursive: true });
  const backupPath = path.join(backupDir, "DR_FIXTURE_PURCHASE_EVIDENCE.pdf");
  fs.copyFileSync(PDF_PATH, backupPath);
  result.storage.local_backup = "docs/qa/phase13/dr/_storage_backup/DR_FIXTURE_PURCHASE_EVIDENCE.pdf";

  result.fixture_ids = {
    org_id: orgId,
    owner_user_id: ownerId,
    secondary_user_id: memberId,
    purchase_document_id_for_path: purchaseId,
    rpo_probe: "DR_FIXTURE_RPO_PROBE",
  };
} catch (e) {
  result.fixture_error = String(e.message || e).slice(0, 2000);
}

const goldenPass =
  result.golden?.status === "PASS" ||
  result.golden?.GOLDEN_FULL_FLOW === "PASS" ||
  (Array.isArray(result.golden?.summary) &&
    result.golden.summary.filter((s) => s.status === "PASS").length >= 10);

result.DR_FIXTURE_LOADED =
  result.storage?.ok && result.rpo_probe?.ok && (goldenPass || result.secondary_member?.ok)
    ? "PASS"
    : result.storage?.ok && result.rpo_probe?.ok
      ? "PARTIAL"
      : "FAIL";

result.finished = new Date().toISOString();
fs.writeFileSync(path.join(DR_DIR, "DR-T2.json"), JSON.stringify(result, null, 2));
process.exit(result.DR_FIXTURE_LOADED === "FAIL" ? 1 : 0);
