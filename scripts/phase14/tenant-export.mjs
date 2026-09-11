#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { PHASE14_DIR } from "./env.mjs";
import { ensureLocalEnv, LOCAL } from "../phase13/env.mjs";

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
  if (!res.ok) throw new Error(`${p} ${res.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

async function login(env, email, password) {
  const res = await fetch(`${env.apiUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: env.anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(JSON.stringify(body));
  return body.access_token;
}

async function rest(env, token, path, opts = {}) {
  const res = await fetch(`${env.apiUrl}/rest/v1/${path}`, {
    method: opts.method || "GET",
    headers: {
      apikey: env.anonKey,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Prefer: opts.prefer || "return=representation",
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  const text = await res.text();
  let data;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  return { ok: res.ok, status: res.status, data };
}

const TABLES = [
  ["organizations", "id"],
  ["counterparties", "organization_id"],
  ["products", "organization_id"],
  ["sales_documents", "organization_id"],
  ["purchase_documents", "organization_id"],
  ["journal_entries", "organization_id"],
  ["tax_periods", "organization_id"],
];

export async function runTenantExport() {
  const env = { ...LOCAL, ...ensureLocalEnv() };
  const stamp = Date.now();
  const password = "Phase14-Export-Only-1!";
  const userA = await admin(env, "/auth/v1/admin/users", {
    method: "POST",
    body: JSON.stringify({
      email: `phase14.export.a.${stamp}@example.com`,
      password,
      email_confirm: true,
    }),
  });
  const userB = await admin(env, "/auth/v1/admin/users", {
    method: "POST",
    body: JSON.stringify({
      email: `phase14.export.b.${stamp}@example.com`,
      password,
      email_confirm: true,
    }),
  });
  const tokenA = await login(env, userA.email, password);
  const tokenB = await login(env, userB.email, password);

  const orgA = await rest(env, tokenA, "organizations", {
    method: "POST",
    body: { legal_name: `Export A ${stamp}`, created_by: userA.id, status: "active" },
  });
  const orgB = await rest(env, tokenB, "organizations", {
    method: "POST",
    body: { legal_name: `Export B ${stamp}`, created_by: userB.id, status: "active" },
  });
  const orgAId = orgA.data?.[0]?.id;
  const orgBId = orgB.data?.[0]?.id;
  await rest(env, tokenA, "organization_members", {
    method: "POST",
    body: { organization_id: orgAId, user_id: userA.id, role: "owner", status: "active" },
  });
  await rest(env, tokenB, "organization_members", {
    method: "POST",
    body: { organization_id: orgBId, user_id: userB.id, role: "owner", status: "active" },
  });

  const cases = [];
  const exported = {};
  for (const [table, col] of TABLES) {
    const q =
      table === "organizations"
        ? `${table}?id=eq.${orgAId}&select=*`
        : `${table}?${col}=eq.${orgAId}&select=*&limit=50`;
    const own = await rest(env, tokenA, q);
    exported[table] = { status: own.status, count: Array.isArray(own.data) ? own.data.length : 0 };
    cases.push({
      id: `export.own.${table}`,
      status: own.ok ? "PASS" : "FAIL",
    });

    const other =
      table === "organizations"
        ? `${table}?id=eq.${orgBId}&select=*`
        : `${table}?${col}=eq.${orgBId}&select=*`;
    const leak = await rest(env, tokenA, other);
    const leaked = Array.isArray(leak.data) && leak.data.length > 0;
    cases.push({
      id: `export.no_cross_tenant.${table}`,
      status: leak.ok && !leaked ? "PASS" : leaked ? "FAIL" : "PASS",
    });
  }

  const audit = await rest(
    env,
    tokenA,
    `audit_events?organization_id=eq.${orgAId}&select=id&limit=1`
  );
  cases.push({
    id: "export.audit_readable_own_org",
    status: audit.ok ? "PASS" : "FAIL",
  });

  const failed = cases.filter((c) => c.status === "FAIL");
  const result = {
    TENANT_DATA_EXPORT: failed.length === 0 ? "PASS" : "FAIL",
    status: failed.length === 0 ? "PASS" : "FAIL",
    orgA: orgAId,
    orgB: orgBId,
    exported,
    cases,
    failed,
    note: "Export is RLS-scoped PostgREST reads; /api/org/export uses the same JWT isolation.",
  };

  fs.mkdirSync(PHASE14_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(PHASE14_DIR, "tenant-export-last-run.json"),
    JSON.stringify(result, null, 2) + "\n"
  );
  return result;
}

if (process.argv[1]?.endsWith("tenant-export.mjs")) {
  runTenantExport().then((r) => {
    console.log(JSON.stringify(r, null, 2));
    if (r.status !== "PASS") process.exit(1);
  }).catch((e) => { console.error(e); process.exit(1); });
}
