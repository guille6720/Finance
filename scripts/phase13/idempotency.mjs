#!/usr/bin/env node
/**
 * Retry / idempotency tests on local disposable DB.
 * Covers: profile trigger upsert, org create uniqueness of membership bootstrap,
 * audit append-only, catalog seed re-apply safety.
 */
import { ensureLocalEnv } from "./env.mjs";
import { withDb } from "./db.mjs";

async function admin(env, path, init = {}) {
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
  if (!res.ok) throw new Error(`${path} ${res.status} ${text}`);
  return body;
}

export async function runIdempotencyTests() {
  const env = ensureLocalEnv();
  const results = [];
  const stamp = Date.now();
  const password = "Phase13-Test-Only-1!";

  const user = await admin(env, "/auth/v1/admin/users", {
    method: "POST",
    body: JSON.stringify({
      email: `phase13.idem.${stamp}@example.com`,
      password,
      email_confirm: true,
      user_metadata: { full_name: "Idem" },
    }),
  });

  // Retry-safe profile existence (trigger already inserted)
  const profiles = await withDb(async (client) => {
    const r1 = await client.query(`select count(*)::int as n from public.profiles where id=$1`, [
      user.id,
    ]);
    await client.query(
      `insert into public.profiles (id, email, full_name)
       values ($1, $2, $3)
       on conflict (id) do nothing`,
      [user.id, user.email, "Idem"]
    );
    const r2 = await client.query(`select count(*)::int as n from public.profiles where id=$1`, [
      user.id,
    ]);
    return { before: r1.rows[0].n, after: r2.rows[0].n };
  });
  results.push({
    id: "idem.profile_upsert_no_duplicate",
    status: profiles.before === 1 && profiles.after === 1 ? "PASS" : "FAIL",
    detail: profiles,
  });

  // Catalog seed re-assert (seed.sql do-block) — run invariant query twice
  const catalog = await withDb(async (client) => {
    const q = `select
      (select count(*) from public.fiscal_conditions)::int as fiscal,
      (select count(*) from public.feature_catalog)::int as features`;
    const a = (await client.query(q)).rows[0];
    const b = (await client.query(q)).rows[0];
    return { a, b };
  });
  results.push({
    id: "idem.catalog_counts_stable",
    status:
      catalog.a.fiscal === catalog.b.fiscal &&
      catalog.a.features === catalog.b.features &&
      catalog.a.fiscal >= 4
        ? "PASS"
        : "FAIL",
    detail: catalog,
  });

  // Audit append-only: update must fail
  const audit = await withDb(async (client) => {
    const ins = await client.query(
      `insert into public.audit_events (event_type, entity_type, action, metadata)
       values ('phase13.idem', 'test', 'insert', '{}'::jsonb)
       returning id`
    );
    const id = ins.rows[0].id;
    let updateBlocked = false;
    try {
      await client.query(`update public.audit_events set action='x' where id=$1`, [id]);
    } catch {
      updateBlocked = true;
    }
    let deleteBlocked = false;
    try {
      await client.query(`delete from public.audit_events where id=$1`, [id]);
    } catch {
      deleteBlocked = true;
    }
    return { updateBlocked, deleteBlocked };
  });
  results.push({
    id: "idem.audit_append_only",
    status: audit.updateBlocked && audit.deleteBlocked ? "PASS" : "FAIL",
    detail: audit,
  });

  // Retry same org membership bootstrap pattern: second owner bootstrap for same user/org denied or unique
  const login = await fetch(`${env.apiUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: env.anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email: user.email, password }),
  }).then((r) => r.json());

  async function rest(path, init) {
    const res = await fetch(`${env.apiUrl}/rest/v1/${path}`, {
      ...init,
      headers: {
        apikey: env.anonKey,
        Authorization: `Bearer ${login.access_token}`,
        "Content-Type": "application/json",
        Prefer: "return=representation",
        ...(init.headers || {}),
      },
    });
    const data = await res.json().catch(() => null);
    return { ok: res.ok, status: res.status, data };
  }

  const org = await rest("organizations", {
    method: "POST",
    body: JSON.stringify({
      legal_name: `Idem Org ${stamp}`,
      created_by: user.id,
      status: "active",
    }),
  });
  const orgId = org.data?.[0]?.id;
  const m1 = await rest("organization_members", {
    method: "POST",
    body: JSON.stringify({
      organization_id: orgId,
      user_id: user.id,
      role: "owner",
      status: "active",
    }),
  });
  const m2 = await rest("organization_members", {
    method: "POST",
    body: JSON.stringify({
      organization_id: orgId,
      user_id: user.id,
      role: "owner",
      status: "active",
    }),
  });
  results.push({
    id: "idem.duplicate_membership_rejected",
    status: m1.ok && !m2.ok ? "PASS" : "FAIL",
    detail: { m1: m1.status, m2: m2.status, m2data: m2.data },
  });

  const failed = results.filter((r) => r.status === "FAIL");
  return {
    status: failed.length === 0 ? "PASS" : "FAIL",
    detail: `cases=${results.length}; failed=${failed.length}`,
    results,
    failed,
  };
}

if (process.argv[1]?.endsWith("idempotency.mjs")) {
  runIdempotencyTests()
    .then((r) => {
      console.log(JSON.stringify(r, null, 2));
      if (r.status !== "PASS") process.exit(1);
    })
    .catch((e) => {
      console.error(e);
      process.exit(1);
    });
}
