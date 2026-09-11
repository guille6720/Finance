#!/usr/bin/env node
/**
 * Provision deterministic synthetic fixtures for APP load tests.
 * Creates one org + owner; writes LOAD_FIXTURE_PATH JSON for k6.
 */
import fs from "node:fs";
import path from "node:path";
import { ensureLocalEnv, PHASE13_DIR } from "./env.mjs";

const FIXTURE = path.join(PHASE13_DIR, "load-fixture.json");

async function admin(env, p, init = {}) {
  const res = await fetch(`${env.apiUrl}${p}`, {
    ...init,
    headers: {
      apikey: env.serviceRoleKey,
      Authorization: `Bearer ${env.serviceRoleKey}`,
      "Content-Type": "application/json",
      ...(init.headers || {}),
    },
  });
  const text = await res.text();
  let body;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  if (!res.ok) throw new Error(`${p} ${res.status} ${text}`);
  return body;
}

async function rest(env, token, p, init = {}) {
  const res = await fetch(`${env.apiUrl}/rest/v1/${p}`, {
    method: init.method || "GET",
    headers: {
      apikey: env.anonKey,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Prefer: init.prefer || "return=representation",
    },
    body: init.body ? JSON.stringify(init.body) : undefined,
  });
  const data = await res.json().catch(() => null);
  if (!res.ok) throw new Error(`${p} ${res.status} ${JSON.stringify(data)}`);
  return data;
}

export async function provisionLoadFixture() {
  const env = ensureLocalEnv();
  const stamp = "phase13-load-fixed";
  const email = `${stamp}@example.com`;
  const password = "Phase13-Test-Only-1!";

  // idempotent-ish: try login first
  let login = await fetch(`${env.apiUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: env.anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  }).then((r) => r.json());

  if (!login.access_token) {
    await admin(env, "/auth/v1/admin/users", {
      method: "POST",
      body: JSON.stringify({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name: "Load Fixture" },
      }),
    });
    login = await fetch(`${env.apiUrl}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { apikey: env.anonKey, "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    }).then((r) => r.json());
  }

  const token = login.access_token;
  const userId = login.user.id;

  let orgs = await rest(
    env,
    token,
    "organizations?select=id,legal_name&limit=1"
  );
  let orgId = orgs?.[0]?.id;
  if (!orgId) {
    const created = await rest(env, token, "organizations", {
      method: "POST",
      body: {
        legal_name: "Phase13 Load Org",
        created_by: userId,
        status: "active",
      },
    });
    orgId = created[0].id;
    await rest(env, token, "organization_members", {
      method: "POST",
      body: {
        organization_id: orgId,
        user_id: userId,
        role: "owner",
        status: "active",
      },
    });
    await rest(env, token, "branches", {
      method: "POST",
      body: { organization_id: orgId, name: "HQ", code: "HQ", is_main: true },
    }).catch(() => {}); // may fail if RLS blocks or already exists

    // Bootstrap platform features so the fixture org is fully operational
    for (const fCode of ["dashboard","sales","purchases","inventory","cash","banks","accounting","taxes","pos","customers","suppliers","reports"]) {
      await fetch(`${env.apiUrl}/rest/v1/rpc/platform_enable_organization_feature`, {
        method: "POST",
        headers: { apikey: env.serviceRoleKey, Authorization: `Bearer ${env.serviceRoleKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ p_organization_id: orgId, p_feature_code: fCode }),
      }).catch(() => {});
    }

    // Seed chart of accounts (authenticated RPC)
    await fetch(`${env.apiUrl}/rest/v1/rpc/seed_starter_chart_of_accounts`, {
      method: "POST",
      headers: { apikey: env.anonKey, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ p_organization_id: orgId }),
    }).catch(() => {});

    // Create fiscal year + accounting periods
    const fyRes = await rest(env, token, "accounting_fiscal_years", {
      method: "POST",
      body: { organization_id: orgId, name: "FY 2026", start_date: "2026-01-01", end_date: "2026-12-31", status: "OPEN" },
    }).catch(() => null);
    const fyId = fyRes?.[0]?.id;
    if (fyId) {
      await fetch(`${env.apiUrl}/rest/v1/rpc/ensure_monthly_periods`, {
        method: "POST",
        headers: { apikey: env.anonKey, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({ p_fiscal_year_id: fyId }),
      }).catch(() => {});
    }
  }

  const fixture = {
    email,
    password,
    userId,
    orgId,
    loadApi: process.env.PHASE13_LOAD_URL || "http://127.0.0.1:3013",
    supabaseUrl: env.apiUrl,
    anonKey: env.anonKey,
  };
  fs.mkdirSync(PHASE13_DIR, { recursive: true });
  fs.writeFileSync(FIXTURE, JSON.stringify(fixture, null, 2) + "\n");
  return fixture;
}

if (process.argv[1]?.endsWith("provision-load-fixture.mjs")) {
  provisionLoadFixture()
    .then((f) => {
      console.log(JSON.stringify({ ok: true, orgId: f.orgId, email: f.email }, null, 2));
    })
    .catch((e) => {
      console.error(e);
      process.exit(1);
    });
}
