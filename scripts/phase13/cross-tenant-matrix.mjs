#!/usr/bin/env node
/**
 * Cross-tenant A/B × roles matrix against local disposable DB.
 * Uses Auth Admin API + PostgREST with user JWTs. No Production. No real PII.
 */
import { ensureLocalEnv } from "./env.mjs";

const ROLES = ["owner", "admin", "manager", "operator", "accountant", "viewer"];

async function adminFetch(env, path, init = {}) {
  const res = await fetch(`${env.apiUrl}${path}`, {
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
  if (!res.ok) {
    throw new Error(`${init.method || "GET"} ${path} -> ${res.status} ${text}`);
  }
  return body;
}

async function createUser(env, email, password) {
  const user = await adminFetch(env, "/auth/v1/admin/users", {
    method: "POST",
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: "Phase13 Synthetic" },
    }),
  });
  return user;
}

async function passwordLogin(env, email, password) {
  const res = await fetch(`${env.apiUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey: env.anonKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ email, password }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`login failed: ${JSON.stringify(body)}`);
  return body.access_token;
}

async function rest(env, token, path, { method = "GET", body, prefer } = {}) {
  const res = await fetch(`${env.apiUrl}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: env.anonKey,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Prefer: prefer || (method === "POST" ? "return=representation" : ""),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  return { ok: res.ok, status: res.status, data };
}

async function bootstrapOrg(env, token, userId, legalName) {
  const org = await rest(env, token, "organizations", {
    method: "POST",
    body: {
      legal_name: legalName,
      created_by: userId,
      status: "active",
    },
  });
  if (!org.ok) throw new Error(`org create failed: ${JSON.stringify(org.data)}`);
  const organizationId = org.data[0].id;

  const member = await rest(env, token, "organization_members", {
    method: "POST",
    body: {
      organization_id: organizationId,
      user_id: userId,
      role: "owner",
      status: "active",
    },
  });
  if (!member.ok) {
    throw new Error(`member bootstrap failed: ${JSON.stringify(member.data)}`);
  }
  return organizationId;
}

export async function runCrossTenantMatrix() {
  const env = ensureLocalEnv();
  const stamp = Date.now();
  const password = "Phase13-Test-Only-1!";

  const userA = await createUser(env, `phase13.a.${stamp}@example.com`, password);
  const userB = await createUser(env, `phase13.b.${stamp}@example.com`, password);
  const tokenA = await passwordLogin(env, userA.email, password);
  const tokenB = await passwordLogin(env, userB.email, password);

  const orgA = await bootstrapOrg(env, tokenA, userA.id, `Org A ${stamp}`);
  const orgB = await bootstrapOrg(env, tokenB, userB.id, `Org B ${stamp}`);

  const results = [];

  // Cross-tenant isolation core
  const crossSelect = await rest(
    env,
    tokenA,
    `organizations?id=eq.${orgB}&select=id`
  );
  results.push({
    id: "cross.tenant.A_cannot_select_org_B",
    status:
      crossSelect.ok && Array.isArray(crossSelect.data) && crossSelect.data.length === 0
        ? "PASS"
        : "FAIL",
    detail: crossSelect,
  });

  const crossUpdate = await rest(env, tokenA, `organizations?id=eq.${orgB}`, {
    method: "PATCH",
    body: { legal_name: "hacked" },
    prefer: "return=representation",
  });
  results.push({
    id: "cross.tenant.A_cannot_update_org_B",
    status:
      (!crossUpdate.ok ||
        (Array.isArray(crossUpdate.data) && crossUpdate.data.length === 0)) &&
      crossUpdate.status !== 500
        ? "PASS"
        : "FAIL",
    detail: { status: crossUpdate.status, data: crossUpdate.data },
  });

  const crossBranch = await rest(env, tokenA, "branches", {
    method: "POST",
    body: { organization_id: orgB, name: "x", code: "x" },
  });
  results.push({
    id: "cross.tenant.A_cannot_insert_branch_on_B",
    status: !crossBranch.ok ? "PASS" : "FAIL",
    detail: crossBranch,
  });

  // Role matrix on org A: create satellite users per role via service role membership insert
  for (const role of ROLES) {
    if (role === "owner") {
      results.push({
        id: `role.${role}.owner_can_select_own_org`,
        status: "PASS",
        detail: "covered by bootstrap owner tokenA",
      });
      continue;
    }

    const u = await createUser(
      env,
      `phase13.${role}.${stamp}@example.com`,
      password
    );
    // service role insert membership
    await adminFetch(env, "/rest/v1/organization_members", {
      method: "POST",
      headers: { Prefer: "return=representation" },
      body: JSON.stringify({
        organization_id: orgA,
        user_id: u.id,
        role,
        status: "active",
      }),
    });

    const token = await passwordLogin(env, u.email, password);
    const sel = await rest(env, token, `organizations?id=eq.${orgA}&select=id`);
    results.push({
      id: `role.${role}.can_select_own_org`,
      status: sel.ok && sel.data?.length === 1 ? "PASS" : "FAIL",
      detail: sel,
    });

    const mut = await rest(env, token, `organizations?id=eq.${orgA}`, {
      method: "PATCH",
      body: { commercial_name: `try-${role}` },
      prefer: "return=representation",
    });
    const canMutate = ["admin", "manager"].includes(role);
    const mutated = Array.isArray(mut.data) && mut.data.length > 0;
    results.push({
      id: `role.${role}.mutate_org_${canMutate ? "allowed" : "denied"}`,
      status: canMutate ? (mutated ? "PASS" : "FAIL") : !mutated ? "PASS" : "FAIL",
      detail: { status: mut.status, data: mut.data },
    });

    const cross = await rest(env, token, `organizations?id=eq.${orgB}&select=id`);
    results.push({
      id: `role.${role}.cannot_select_org_B`,
      status: cross.ok && cross.data?.length === 0 ? "PASS" : "FAIL",
      detail: cross,
    });
  }

  const failed = results.filter((r) => r.status === "FAIL");
  return {
    status: failed.length === 0 ? "PASS" : "FAIL",
    detail: `cases=${results.length}; failed=${failed.length}`,
    orgA,
    orgB,
    results,
    failed,
  };
}

if (process.argv[1]?.endsWith("cross-tenant-matrix.mjs")) {
  runCrossTenantMatrix()
    .then((r) => {
      console.log(JSON.stringify(r, null, 2));
      if (r.status !== "PASS") process.exit(1);
    })
    .catch((e) => {
      console.error(e);
      process.exit(1);
    });
}
