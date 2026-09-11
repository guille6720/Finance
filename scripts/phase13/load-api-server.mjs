#!/usr/bin/env node
/**
 * Lightweight Phase 13 load API — same RLS contracts as the app, without Next.js.
 * Avoids Turbopack OOM next to local Supabase Docker.
 *
 * Auth: Authorization: Bearer <user_access_token>
 * Header: x-organization-id: <uuid>
 */
import http from "node:http";
import { ensureLocalEnv } from "./env.mjs";

const port = Number(process.env.PHASE13_LOAD_PORT || 3013);
const env = ensureLocalEnv();

async function supabaseRest(token, path, init = {}) {
  const res = await fetch(`${env.apiUrl}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: env.anonKey,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Prefer: init.prefer || "",
      ...(init.headers || {}),
    },
    body: init.body ? JSON.stringify(init.body) : undefined,
  });
  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  return { status: res.status, ok: res.ok, data };
}

function json(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  });
  res.end(payload);
}

function domainBlocked(res, domain) {
  json(res, 501, {
    ok: false,
    code: `BLOCKED_MISSING_MIGRATION_${domain}`,
    domain,
    message: "Domain not present in clean-room schema; not faked for load tests",
  });
}

async function requireAuth(req) {
  const auth = req.headers.authorization || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) return { error: { status: 401, body: { ok: false, error: "missing_bearer" } } };
  const orgId = req.headers["x-organization-id"];
  if (!orgId || typeof orgId !== "string") {
    return { error: { status: 400, body: { ok: false, error: "missing_x_organization_id" } } };
  }
  let userId = null;
  try {
    const payload = JSON.parse(
      Buffer.from(token.split(".")[1], "base64url").toString("utf8")
    );
    userId = payload.sub || null;
  } catch {
    return { error: { status: 401, body: { ok: false, error: "invalid_jwt" } } };
  }
  return { token, orgId, userId };
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://127.0.0.1:${port}`);
    const pathName = url.pathname;

    if (req.method === "GET" && pathName === "/api/load/health") {
      return json(res, 200, { ok: true, role: "phase13-load-api" });
    }

    const gate = await requireAuth(req);
    if (gate.error) return json(res, gate.error.status, gate.error.body);
    const { token, orgId, userId } = gate;

    // --- REAL reads (Phase 1 contracts) ---
    if (req.method === "GET" && pathName === "/api/load/dashboard") {
      const [org, fiscal, branch, business, members, features] = await Promise.all([
        supabaseRest(token, `organizations?id=eq.${orgId}&select=id,legal_name,status`),
        supabaseRest(
          token,
          `fiscal_profiles?organization_id=eq.${orgId}&select=id,fiscal_condition_id,fiscal_address`
        ),
        supabaseRest(token, `branches?organization_id=eq.${orgId}&select=id,name&limit=5`),
        supabaseRest(token, `business_profiles?organization_id=eq.${orgId}&select=id,business_type`),
        supabaseRest(
          token,
          `organization_members?organization_id=eq.${orgId}&status=eq.active&select=id,role`
        ),
        supabaseRest(
          token,
          `organization_features?organization_id=eq.${orgId}&select=id,status,feature_id`
        ),
      ]);
      if ([org, fiscal, branch, business, members, features].some((r) => r.status === 401)) {
        return json(res, 401, { ok: false, error: "unauthorized" });
      }
      const checks = {
        org: Boolean(org.data?.[0]),
        fiscal: Boolean(fiscal.data?.[0]?.fiscal_condition_id),
        branch: (branch.data || []).length > 0,
        business: Boolean(business.data?.[0]),
        members: (members.data || []).length > 0,
      };
      return json(res, 200, {
        ok: true,
        organization_id: orgId,
        completeness: checks,
        members: members.data?.length || 0,
        features: features.data?.length || 0,
      });
    }

    if (req.method === "GET" && pathName === "/api/load/features") {
      const r = await supabaseRest(
        token,
        `organization_features?organization_id=eq.${orgId}&select=id,status,feature_id`
      );
      return json(res, r.status, { ok: r.ok, data: r.data });
    }

    if (req.method === "GET" && pathName === "/api/load/branches") {
      const r = await supabaseRest(
        token,
        `branches?organization_id=eq.${orgId}&select=id,name,code,active`
      );
      return json(res, r.status, { ok: r.ok, data: r.data });
    }

    if (req.method === "GET" && pathName === "/api/load/accounting-periods") {
      const r = await supabaseRest(
        token,
        `accounting_periods?organization_id=eq.${orgId}&select=id,name,starts_on,ends_on,is_closed`
      );
      return json(res, r.status, { ok: r.ok, data: r.data });
    }

    if (req.method === "GET" && pathName === "/api/load/audit") {
      const r = await supabaseRest(
        token,
        `audit_events?organization_id=eq.${orgId}&select=id,event_type,action,created_at&order=created_at.desc&limit=20`
      );
      return json(res, r.status, { ok: r.ok, data: r.data });
    }

    // --- Requested domains: honest 501 when missing ---
    if (req.method === "GET" && pathName === "/api/load/counterparties") {
      return domainBlocked(res, "COUNTERPARTIES");
    }
    if (req.method === "GET" && pathName === "/api/load/products") {
      return domainBlocked(res, "PRODUCTS");
    }
    if (req.method === "GET" && pathName === "/api/load/journal") {
      return domainBlocked(res, "JOURNAL");
    }
    if (req.method === "GET" && pathName === "/api/load/tax-report") {
      return domainBlocked(res, "TAX_REPORT");
    }

    // --- Idempotent synthetic write ---
    if (req.method === "POST" && pathName === "/api/load/idempotent-setting") {
      const key = "phase13.load.marker";
      const value = { v: 1, ts: new Date().toISOString(), deterministic: true };
      // upsert via Prefer resolution
      const existing = await supabaseRest(
        token,
        `organization_settings?organization_id=eq.${orgId}&key=eq.${key}&select=id`
      );
      let r;
      if (existing.data?.[0]?.id) {
        r = await supabaseRest(
          token,
          `organization_settings?id=eq.${existing.data[0].id}`,
          {
            method: "PATCH",
            prefer: "return=representation",
            body: { value },
          }
        );
      } else {
        r = await supabaseRest(token, "organization_settings", {
          method: "POST",
          prefer: "return=representation",
          body: { organization_id: orgId, key, value },
        });
      }
      // also append audit (non-idempotent by design but cheap)
      await supabaseRest(token, "audit_events", {
        method: "POST",
        prefer: "return=minimal",
        body: {
          organization_id: orgId,
          actor_user_id: userId,
          event_type: "phase13.load",
          entity_type: "organization_settings",
          entity_id: key,
          action: "upsert",
          metadata: { source: "load-api" },
        },
      });
      return json(res, r.ok ? 200 : r.status, { ok: r.ok, data: r.data });
    }

    json(res, 404, { ok: false, error: "not_found" });
  } catch (e) {
    json(res, 500, { ok: false, error: String(e?.message || e) });
  }
});

server.listen(port, "127.0.0.1", () => {
  console.log(`phase13 load API on http://127.0.0.1:${port}`);
});
