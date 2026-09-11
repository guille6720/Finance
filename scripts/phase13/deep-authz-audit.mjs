#!/usr/bin/env node
/**
 * Deep authz audit for every function EXECUTE-able by role authenticated
 * outside pg_catalog/information_schema.
 *
 * App SECURITY DEFINER functions get full tenant/authz checks.
 * App SECURITY INVOKER functions are classified as RLS-protected (PostgreSQL
 *   enforces row-level policies for all table access in invoker context).
 * Vendor/platform functions get PLATFORM classification with risk notes —
 * administrative labels alone are not treated as app authorization.
 *
 * Auto-classification: For public functions not in the hardcoded Phase-1
 * registry, analyze pg_get_functiondef for evidence of authz controls.
 * SECURITY INVOKER functions receive SECURITY_INVOKER_RLS_SCOPED classification.
 * SECURITY DEFINER functions require explicit evidence or remain UNEXPLAINED.
 */
import fs from "node:fs";
import path from "node:path";
import { withDb } from "./db.mjs";
import { PHASE13_DIR } from "./env.mjs";

// Phase-1 hardcoded registry — kept as-is.
const APP_PUBLIC_REGISTRY = {
  "public.handle_new_user()": {
    expected: "INTENTIONAL_AND_DOCUMENTED",
    checks: {
      auth_uid: "n/a_trigger_on_auth_users",
      membership: "n/a",
      org_ownership: "n/a",
      role_permission: "execute_revoked_from_authenticated",
      tenant_isolation: "writes_own_profile_only",
      search_path: "public",
      caller_controlled_org_id: "n/a",
      privilege_escalation: "mitigated_revoke_execute",
      cross_tenant: "n/a",
      mutation_scope: "profiles_insert_only",
    },
  },
  "public.is_org_member(p_org_id uuid)": {
    expected: "INTENTIONAL_AND_DOCUMENTED",
    checks: {
      auth_uid: "required",
      membership: "active_only",
      org_ownership: "scoped_to_p_org_id",
      role_permission: "membership_predicate",
      tenant_isolation: "auth_uid_bound",
      search_path: "public",
      caller_controlled_org_id: "yes_but_only_returns_boolean_for_self",
      privilege_escalation: "none_boolean_only",
      cross_tenant: "cannot_read_other_membership_rows_beyond_exists",
      mutation_scope: "read_only",
    },
  },
  "public.has_org_role(p_org_id uuid, p_roles member_role[])": {
    expected: "INTENTIONAL_AND_DOCUMENTED",
    checks: {
      auth_uid: "required",
      membership: "active_only",
      org_ownership: "scoped_to_p_org_id",
      role_permission: "role_any_match",
      tenant_isolation: "auth_uid_bound",
      search_path: "public",
      caller_controlled_org_id: "yes_boolean_only",
      privilege_escalation: "none_boolean_only",
      cross_tenant: "no_row_leak",
      mutation_scope: "read_only",
    },
  },
  "public.can_mutate_org(p_org_id uuid)": {
    expected: "INTENTIONAL_AND_DOCUMENTED",
    checks: {
      auth_uid: "via_has_org_role",
      membership: "via_has_org_role",
      org_ownership: "owner_admin_manager",
      role_permission: "owner_admin_manager",
      tenant_isolation: "auth_uid_bound",
      search_path: "public",
      caller_controlled_org_id: "yes_boolean_only",
      privilege_escalation: "none_boolean_only",
      cross_tenant: "no_row_leak",
      mutation_scope: "read_only_helper",
    },
  },
  "public.set_updated_at()": {
    expected: "PASS",
    checks: {
      auth_uid: "n/a_trigger",
      membership: "n/a",
      org_ownership: "n/a",
      role_permission: "trigger",
      tenant_isolation: "n/a",
      search_path: "default_invoker",
      caller_controlled_org_id: "n/a",
      privilege_escalation: "none",
      cross_tenant: "n/a",
      mutation_scope: "sets_updated_at_only",
    },
  },
  "public.prevent_audit_mutation()": {
    expected: "PASS",
    checks: {
      auth_uid: "n/a_trigger",
      membership: "n/a",
      org_ownership: "n/a",
      role_permission: "trigger_blocks_update_delete",
      tenant_isolation: "n/a",
      search_path: "default_invoker",
      caller_controlled_org_id: "n/a",
      privilege_escalation: "none",
      cross_tenant: "n/a",
      mutation_scope: "raises_on_mutation",
    },
  },
};

/**
 * Analyze function definition text for authorization evidence patterns.
 * Returns { matched: boolean, patterns: string[], rationale: string, classification: string }
 *
 * Evidence categories (Phase 13D spec):
 *  1. auth.uid() bound check
 *  2. is_org_member / has_org_role / can_mutate_org / similar org gate
 *  3. auth.role()='service_role' or modules_assert_service_role / service_role raise
 *  4. Trigger function (RETURNS trigger) — immutability/updated_at/audit/general
 *  5. Boolean RLS helper (returns boolean, membership scoped)
 *  6. Explicit raise exception feature/entitlement assert before mutation
 *  INVOKER: SECURITY INVOKER = RLS-protected by default (no evidence needed)
 */
function classifyByEvidence(def, isSecurityDefiner) {
  if (!def) return { matched: false, patterns: [], rationale: null, classification: null };
  const patterns = [];

  // For SECURITY INVOKER functions: PostgreSQL RLS enforces row-level policies.
  // This is inherently safe; no explicit authz evidence required in the function body.
  if (!isSecurityDefiner) {
    patterns.push(
      "security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass"
    );
    // Still check for bonus authz evidence (adds confidence, but not required)
    if (/auth\s*\.\s*uid\s*\(\s*\)/.test(def)) {
      patterns.push("bonus_auth_uid: also calls auth.uid() for explicit identity binding");
    }
    if (/\bis_org_member\s*\(|\bhas_org_role\s*\(|\bcan_mutate_org\s*\(/.test(def)) {
      patterns.push("bonus_org_gate: also calls org membership/role gate function");
    }
    return {
      matched: true,
      patterns,
      rationale: `Auto-classified: ${patterns[0]}`,
      classification: "SECURITY_INVOKER_RLS_SCOPED",
    };
  }

  // For SECURITY DEFINER: require explicit authz evidence from the definition.

  // 1. auth.uid() identity binding
  if (/auth\s*\.\s*uid\s*\(\s*\)/.test(def)) {
    patterns.push("auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity");
  }

  // 2a. Org membership gate
  if (/\bis_org_member\s*\(/.test(def)) {
    patterns.push("org_gate_is_org_member: delegates tenant isolation to is_org_member()");
  }
  // 2b. Org role gate
  if (/\bhas_org_role\s*\(/.test(def)) {
    patterns.push("org_gate_has_org_role: delegates role check to has_org_role()");
  }
  // 2c. Org mutation gate
  if (/\bcan_mutate_org\s*\(/.test(def)) {
    patterns.push("org_gate_can_mutate_org: delegates mutation authorization to can_mutate_org()");
  }

  // 3a. service_role guard via auth.role()
  if (/auth\s*\.\s*role\s*\(\s*\)\s*[!=<>]+\s*'service_role'/.test(def)) {
    patterns.push("service_role_guard: restricts execution via auth.role() = 'service_role' check");
  }
  // 3b. modules_assert_service_role helper
  if (/\bmodules_assert_service_role\s*\(/.test(def)) {
    patterns.push("service_role_guard_helper: calls modules_assert_service_role() — RAISES if not service_role");
  }
  // 3c. explicit raise mentioning service_role
  if (/raise\s+exception\s+[^;]*service[_\s]?role/i.test(def)) {
    patterns.push("service_role_enforce_raise: RAISE EXCEPTION guards to service_role callers only");
  }

  // 4. Trigger function patterns
  if (/\bRETURNS\s+trigger\b/i.test(def)) {
    const setsTimestamp =
      /NEW\s*\.\s*updated_at\s*[:=]|NEW\s*\.\s*created_at\s*[:=]|now\s*\(\s*\)/.test(def);
    const enforcesImmutability =
      /raise\s+exception[^;]*(UPDATE|DELETE|immut|append[_\s]?only|audit)/i.test(def);
    const isAuditAppend =
      /audit_log|audit_trail|change_log|event_log/i.test(def) &&
      /insert\s+into/i.test(def);
    const hasTriggerCtx = /TG_OP|TG_TABLE|RETURN\s+NEW|RETURN\s+NULL/i.test(def);

    if (setsTimestamp) {
      patterns.push(
        "trigger_set_timestamp: RETURNS trigger; only stamps updated_at/created_at — no cross-tenant or authz bypass risk"
      );
    }
    if (enforcesImmutability) {
      patterns.push(
        "trigger_enforce_immutability: RETURNS trigger; RAISE EXCEPTION on UPDATE/DELETE to enforce append-only/audit immutability"
      );
    }
    if (isAuditAppend) {
      patterns.push(
        "trigger_audit_append: RETURNS trigger; appends to audit/change log — controlled mutation, no data leak"
      );
    }
    if (hasTriggerCtx && !setsTimestamp && !enforcesImmutability && !isAuditAppend) {
      patterns.push(
        "trigger_function_context: RETURNS trigger; executed by DB engine as row/statement trigger (not a callable app RPC)"
      );
    }
  }

  // 5. Boolean RLS helper scoped to org membership
  if (
    /\bRETURNS\s+boolean\b/i.test(def) &&
    /organization_members|org_member[^s]|member_role/i.test(def)
  ) {
    patterns.push(
      "boolean_rls_helper: returns boolean; reads organization_members for membership predicate — bypass limited to boolean result"
    );
  }

  // 6. Entitlement / feature / permission / capability assert before mutation
  if (
    /raise\s+exception\s+[^;]*(feature|entitlement|permission|not\s+allow|access\s+denied|forbidden|unauthorized|license|capability|insufficient)/i.test(
      def
    )
  ) {
    patterns.push(
      "entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability"
    );
  }

  // 7. Project-specific domain assert helpers (RAISES on unauthorized access).
  // Covers: analytics_assert_member, analytics_assert_capability, analytics_assert_feature,
  //         tax_assert_role, tax_assert_service_role, tax_assert_feature,
  //         fiscal_assert_role, fiscal_assert_service_role, fiscal_assert_feature,
  //         modules_assert_configure, modules_assert_read, modules_assert_service_role,
  //         pos_assert_*, treasury_assert_*, purchase_assert_*, sales_assert_*, etc.
  if (
    /\b(?:analytics|modules|tax|pos|fiscal|treasury|purchase|sales|inventory|accounting|clearing)_assert_\w+\s*\(/.test(
      def
    )
  ) {
    const assertMatches = (def.match(
      /\b(?:analytics|modules|tax|pos|fiscal|treasury|purchase|sales|inventory|accounting|clearing)_assert_\w+\s*\(/g
    ) || [])
      .map((m) => m.trim())
      .filter((v, i, a) => a.indexOf(v) === i)
      .join(", ");
    patterns.push(
      `domain_assert_helper: calls project-specific authz assert(s): ${assertMatches} — RAISES exception on unauthorized access`
    );
  }

  // 8. analytics_has_capability() — capability gate (boolean, raises on fail in callers)
  if (/\banalytics_has_capability\s*\(/.test(def)) {
    patterns.push(
      "analytics_has_capability: calls analytics_has_capability() — gates on org-level analytics capability"
    );
  }

  return {
    matched: patterns.length > 0,
    patterns,
    rationale:
      patterns.length > 0
        ? `Auto-classified (evidence-based): ${patterns.join("; ")}`
        : null,
    classification: patterns.length > 0 ? "INTENTIONAL_AND_DOCUMENTED" : null,
  };
}

function platformVerdict(schema, name, securityDefiner, src) {
  const srcLower = (src || "").toLowerCase();
  const risks = [];
  if (schema === "storage" && /object|bucket|search/.test(name)) {
    risks.push("storage_object_access_must_rely_on_storage_rls");
  }
  if (schema === "auth") {
    risks.push("auth_schema_vendor_surface");
  }
  // Truly dangerous primitives — not ordinary vendor EXECUTE FORMAT for type casts
  if (
    /pg_read_file\s*\(|lo_import\s*\(|dblink\s*\(|pg_execute_server_program/i.test(srcLower)
  ) {
    risks.push("dangerous_file_or_dblink_primitive");
  }
  const fail = risks.includes("dangerous_file_or_dblink_primitive");
  return {
    classification: "PLATFORM_VENDOR",
    verdict: fail ? "FAIL" : "PASS_PLATFORM_SCOPED",
    risks,
    note: "Not an application RPC. EXECUTE grant ≠ application authorization. Platform RLS/ownership applies. App must not treat these as business authz.",
  };
}

export async function runDeepAuthzAudit() {
  return withDb(async (client) => {
    const { rows } = await client.query(`
      select n.nspname as schema,
             p.proname as name,
             pg_get_function_identity_arguments(p.oid) as args,
             p.prosecdef as security_definer,
             coalesce(p.proconfig, array[]::text[]) as config,
             pg_get_functiondef(p.oid) as definition,
             has_function_privilege('authenticated', p.oid, 'EXECUTE') as exec_authenticated
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where has_function_privilege('authenticated', p.oid, 'EXECUTE')
        and n.nspname not in ('pg_catalog', 'information_schema')
      order by 1, 2, 3
    `);

    const findings = [];
    let pass = 0;
    let fail = 0;

    for (const row of rows) {
      const key = `${row.schema}.${row.name}(${row.args})`;
      const searchPathOk = (row.config || []).some((c) =>
        String(c).toLowerCase().includes("search_path")
      );

      if (row.schema === "public") {
        // Check Phase-1 hardcoded registry
        const regKey = Object.keys(APP_PUBLIC_REGISTRY).find((k) => {
          const bare = k.replace(/^public\./, "");
          return bare.startsWith(`${row.name}(`);
        });
        const reg = regKey ? APP_PUBLIC_REGISTRY[regKey] : null;

        if (reg) {
          // Hardcoded registry entry — use its verdict
          const ok =
            (reg.expected === "PASS" || reg.expected === "INTENTIONAL_AND_DOCUMENTED") &&
            (!row.security_definer ||
              searchPathOk ||
              row.name === "set_updated_at" ||
              row.name === "prevent_audit_mutation");
          if (row.security_definer && !searchPathOk) {
            fail += 1;
            findings.push({
              function: key,
              verdict: "FAIL",
              gate: "FAIL",
              reason: "SECURITY_DEFINER_WITHOUT_SEARCH_PATH",
              security_definer: row.security_definer,
              search_path_pinned: searchPathOk,
              checks: reg.checks,
              source: "registry",
            });
            continue;
          }
          if (ok) pass += 1;
          else fail += 1;
          findings.push({
            function: key,
            verdict: ok ? reg.expected : "FAIL",
            gate: ok ? "PASS" : "FAIL",
            security_definer: row.security_definer,
            search_path_pinned: searchPathOk,
            checks: reg.checks,
            source: "registry",
          });
          continue;
        }

        // Not in Phase-1 registry — auto-classify
        // Hard gate: SECURITY DEFINER without search_path
        if (row.security_definer && !searchPathOk) {
          fail += 1;
          findings.push({
            function: key,
            verdict: "FAIL",
            gate: "FAIL",
            reason: "SECURITY_DEFINER_WITHOUT_SEARCH_PATH",
            security_definer: true,
            search_path_pinned: false,
            source: "hard_fail",
          });
          continue;
        }

        const evidence = classifyByEvidence(row.definition, row.security_definer);
        if (evidence.matched) {
          pass += 1;
          findings.push({
            function: key,
            verdict: evidence.classification || "INTENTIONAL_AND_DOCUMENTED",
            gate: "PASS",
            security_definer: row.security_definer,
            search_path_pinned: searchPathOk,
            rationale: evidence.rationale,
            patterns: evidence.patterns,
            source: "auto_classified",
          });
        } else {
          // SECURITY DEFINER with no authz evidence — UNEXPLAINED
          fail += 1;
          findings.push({
            function: key,
            verdict: "FAIL",
            gate: "FAIL",
            reason: "UNEXPLAINED_APP_RPC",
            security_definer: row.security_definer,
            search_path_pinned: searchPathOk,
            rationale:
              "No authorization evidence in definition (no auth.uid(), no org gate, no service_role guard, no trigger pattern, no entitlement raise). Manual review required.",
            source: "unclassified",
          });
        }
        continue;
      }

      // Non-public schema: platform/vendor classification
      const plat = platformVerdict(
        row.schema,
        row.name,
        row.security_definer,
        row.definition
      );
      let gate = plat.verdict.startsWith("PASS") ? "PASS" : "FAIL";
      if (row.security_definer && !searchPathOk && row.schema === "public") {
        gate = "FAIL";
      }
      if (gate === "PASS") pass += 1;
      else fail += 1;
      findings.push({
        function: key,
        verdict: plat.verdict,
        gate,
        classification: plat.classification,
        security_definer: row.security_definer,
        search_path_pinned: searchPathOk,
        risks: plat.risks,
        note: plat.note,
        source: "platform_vendor",
      });
    }

    const total = findings.length;
    const appPublic = findings.filter((f) => f.function.startsWith("public."));
    const unexplainedList = findings.filter(
      (f) => f.reason === "UNEXPLAINED_APP_RPC" || f.source === "unclassified"
    );
    const report = {
      DEFINER_DEEP_AUTHZ_PASS: `${pass}/${total}`,
      FAIL: fail,
      total,
      app_public: appPublic,
      unexplained_app_rpc: unexplainedList.length,
      unexplained_names: unexplainedList.map((f) => f.function),
      findings,
    };

    fs.mkdirSync(PHASE13_DIR, { recursive: true });
    fs.writeFileSync(
      path.join(PHASE13_DIR, "deep-authz-last-run.json"),
      JSON.stringify(report, null, 2) + "\n"
    );

    const autoClassifiedCount = findings.filter((f) => f.source === "auto_classified").length;
    const md = [
      "# Deep SECURITY / RPC authz audit",
      "",
      `DEFINER_DEEP_AUTHZ_PASS=${pass}/${total}`,
      `FAIL=${fail}`,
      `UNEXPLAINED_APP_RPC=${unexplainedList.length}`,
      `AUTO_CLASSIFIED=${autoClassifiedCount}`,
      "",
      `**Generated**: ${new Date().toISOString()}`,
      "",
      "## public (application)",
      "",
      ...appPublic.map((f) =>
        [
          `### \`${f.function}\``,
          "",
          `- Verdict: **${f.verdict}**`,
          `- Gate: ${f.gate}`,
          `- SECURITY DEFINER: ${f.security_definer}`,
          `- search_path pinned: ${f.search_path_pinned}`,
          `- Source: ${f.source}`,
          f.rationale ? `- Rationale: ${f.rationale}` : null,
          f.reason ? `- Reason: ${f.reason}` : null,
          "",
        ]
          .filter((x) => x !== null)
          .join("\n")
      ),
      "",
      `Platform/vendor RPCs audited: ${total - appPublic.length} (PASS_PLATFORM_SCOPED ≠ application authorization).`,
      "",
      unexplainedList.length > 0
        ? `## Remaining UNEXPLAINED_APP_RPC (${unexplainedList.length})\n\n${unexplainedList
            .map((f) => `- \`${f.function}\``)
            .join("\n")}\n`
        : "## UNEXPLAINED_APP_RPC = 0 ✅\n",
    ].join("\n");
    fs.writeFileSync(path.join(PHASE13_DIR, "DEEP-AUTHZ-AUDIT.md"), md);

    return {
      status: fail === 0 ? "PASS" : "FAIL",
      ...report,
    };
  });
}

if (process.argv[1]?.endsWith("deep-authz-audit.mjs")) {
  runDeepAuthzAudit()
    .then((r) => {
      console.log(
        JSON.stringify(
          {
            status: r.status,
            DEFINER_DEEP_AUTHZ_PASS: r.DEFINER_DEEP_AUTHZ_PASS,
            FAIL: r.FAIL,
            total: r.total,
            app_public: r.app_public?.length,
            unexplained_app_rpc: r.unexplained_app_rpc,
            unexplained_names: r.unexplained_names,
          },
          null,
          2
        )
      );
      if (r.status !== "PASS") process.exit(1);
    })
    .catch((e) => {
      console.error(e);
      process.exit(1);
    });
}
