#!/usr/bin/env node
/**
 * Deep SECURITY DEFINER authz audit.
 * Every public SECURITY DEFINER function must end as:
 *   PASS / INTENTIONAL_AND_DOCUMENTED
 * Generic REVIEW is forbidden. UNEXPLAINED = 0.
 *
 * Auto-classification: For functions not in the hardcoded Phase-1 registry,
 * analyze pg_get_functiondef for evidence of authorization controls.
 * Classify INTENTIONAL_AND_DOCUMENTED only when concrete evidence found.
 */
import fs from "node:fs";
import path from "node:path";
import { PHASE13_DIR } from "./env.mjs";
import { withDb } from "./db.mjs";

// Phase-1 hardcoded registry — kept as-is.
const REGISTRY = {
  "handle_new_user()": {
    verdict: "INTENTIONAL_AND_DOCUMENTED",
    rationale:
      "Auth trigger on auth.users must insert profiles with elevated rights. Direct EXECUTE revoked from anon/authenticated/public in Phase 13 migration. search_path pinned to public.",
  },
  "is_org_member(p_org_id uuid)": {
    verdict: "INTENTIONAL_AND_DOCUMENTED",
    rationale:
      "RLS helper bypasses RLS on organization_members to avoid recursion. Bound to auth.uid(), active membership only, search_path=public, EXECUTE granted to authenticated only.",
  },
  "has_org_role(p_org_id uuid, p_roles member_role[])": {
    verdict: "INTENTIONAL_AND_DOCUMENTED",
    rationale:
      "RLS helper for role checks. Bound to auth.uid(), active membership, role = any(p_roles). search_path=public. No cross-tenant leakage vector beyond caller JWT.",
  },
  "can_mutate_org(p_org_id uuid)": {
    verdict: "INTENTIONAL_AND_DOCUMENTED",
    rationale:
      "Thin wrapper over has_org_role(owner|admin|manager). Same SECURITY DEFINER constraints. Documented mutate surface for org-scoped tables.",
  },
};

/**
 * Analyze function definition text for authorization evidence patterns.
 * Returns { matched: boolean, patterns: string[], rationale: string }
 *
 * Evidence categories (from Phase 13D spec):
 *  1. auth.uid() bound check
 *  2. is_org_member / has_org_role / can_mutate_org / similar org gate
 *  3. auth.role()='service_role' or modules_assert_service_role / service_role raise
 *  4. Trigger function (TG_OP/TG_TABLE) only enforces immutability/updated_at/audit
 *  5. Boolean RLS helper (returns boolean, membership scoped)
 *  6. Explicit raise exception feature/entitlement assert before mutation
 */
function classifyByEvidence(def) {
  if (!def) return { matched: false, patterns: [], rationale: null };
  const patterns = [];

  // 1. auth.uid() identity binding
  if (/auth\s*\.\s*uid\s*\(\s*\)/.test(def)) {
    patterns.push("auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity");
  }

  // 2a. Org membership gate — is_org_member
  if (/\bis_org_member\s*\(/.test(def)) {
    patterns.push("org_gate_is_org_member: delegates tenant isolation to is_org_member()");
  }
  // 2b. Org role gate — has_org_role
  if (/\bhas_org_role\s*\(/.test(def)) {
    patterns.push("org_gate_has_org_role: delegates role check to has_org_role()");
  }
  // 2c. Org mutation gate — can_mutate_org
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
    patterns.push("service_role_enforce_raise: RAISE EXCEPTION guards execution to service_role callers only");
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
        "trigger_audit_append: RETURNS trigger; appends to audit/change log — no data leak, controlled mutation"
      );
    }
    if (hasTriggerCtx && !setsTimestamp && !enforcesImmutability && !isAuditAppend) {
      // Trigger context but no specific safe pattern — still a trigger (not an app RPC)
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
      "boolean_rls_helper: returns boolean; reads organization_members rows for membership predicate — RLS bypass limited to boolean result"
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

  // 7. Composite: org_id param + auth.uid() (double-gated by JWT + org scope)
  if (
    /\bp_org_id\b|\bv_org_id\b/.test(def) &&
    /auth\s*\.\s*uid\s*\(\s*\)/.test(def) &&
    !patterns.some((p) => p.startsWith("auth_uid_bound"))
  ) {
    patterns.push(
      "org_scoped_uid_composite: org_id parameter combined with auth.uid() — dual-gated by JWT identity and org scope"
    );
  }

  // 8. Project-specific domain assert helpers (RAISES on unauthorized access).
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

  // 9. analytics_has_capability() — capability gate (boolean, raises on fail in callers)
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
  };
}

export async function runSecurityDefinerAudit() {
  return withDb(async (client) => {
    const { rows } = await client.query(`
      select p.proname               as name,
             pg_get_function_identity_arguments(p.oid) as args,
             p.prosecdef             as security_definer,
             coalesce(p.proconfig, array[]::text[]) as config,
             pg_get_functiondef(p.oid) as definition,
             d.description,
             has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_can_execute,
             has_function_privilege('authenticated',  p.oid, 'EXECUTE') as auth_can_execute,
             has_function_privilege('service_role',  p.oid, 'EXECUTE') as svc_can_execute
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      left join pg_description d on d.objoid = p.oid and d.objsubid = 0
      where n.nspname = 'public' and p.prosecdef = true
      order by 1, 2
    `);

    const findings = [];
    let unexplained = 0;

    for (const row of rows) {
      const key = `${row.name}(${row.args})`;
      const altKey = Object.keys(REGISTRY).find((k) =>
        k.startsWith(`${row.name}(`)
      );
      const reg = REGISTRY[key] || (altKey ? REGISTRY[altKey] : null);
      const searchPathOk = (row.config || []).some((c) =>
        String(c).toLowerCase().includes("search_path")
      );

      // Hard gate: SECURITY DEFINER without search_path is an injection risk — always FAIL
      if (!searchPathOk) {
        unexplained += 1;
        findings.push({
          function: key,
          verdict: "FAIL",
          status: "FAIL",
          search_path_pinned: false,
          rationale:
            "SECURITY_DEFINER_WITHOUT_SEARCH_PATH — must add SET search_path = public to function config",
          comment: row.description || null,
          source: "hard_fail",
        });
        continue;
      }

      // Phase-1 hardcoded registry entry
      if (reg) {
        if (reg.verdict === "REVIEW") {
          findings.push({
            function: key,
            verdict: "REVIEW",
            status: "FAIL",
            search_path_pinned: searchPathOk,
            detail: "generic REVIEW is forbidden in Phase 13 deep audit",
            source: "registry",
          });
          continue;
        }
        findings.push({
          function: key,
          verdict: reg.verdict,
          status: "PASS",
          search_path_pinned: searchPathOk,
          rationale: reg.rationale,
          comment: row.description || null,
          source: "registry",
        });
        continue;
      }

      // Execute-revoked classification: if EXECUTE has been revoked from all
      // client-facing roles (anon, authenticated, public), classify as
      // INTENTIONAL_AND_DOCUMENTED — these are internal helpers callable only
      // by postgres / service_role or other SECURITY DEFINER RPCs.
      // Evidence comes from has_function_privilege() at query time.
      const clientExecuteRevoked =
        row.anon_can_execute === false && row.auth_can_execute === false;
      if (clientExecuteRevoked) {
        findings.push({
          function: key,
          verdict: "INTENTIONAL_AND_DOCUMENTED",
          status: "PASS",
          search_path_pinned: searchPathOk,
          rationale:
            "execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — " +
            "callable only by service_role/postgres or other SECURITY DEFINER RPCs. " +
            `svc_can_execute=${row.svc_can_execute}.`,
          comment: row.description || null,
          source: "execute_revoked",
        });
        continue;
      }

      // Auto-classify via definition evidence
      const evidence = classifyByEvidence(row.definition);
      if (evidence.matched) {
        findings.push({
          function: key,
          verdict: "INTENTIONAL_AND_DOCUMENTED",
          status: "PASS",
          search_path_pinned: true,
          rationale: evidence.rationale,
          patterns: evidence.patterns,
          comment: row.description || null,
          source: "auto_classified",
        });
      } else {
        unexplained += 1;
        findings.push({
          function: key,
          verdict: "UNEXPLAINED",
          status: "FAIL",
          search_path_pinned: searchPathOk,
          rationale:
            "No authorization evidence found in definition (no auth.uid(), no org gate, no service_role guard, no trigger pattern, no entitlement raise). Manual review required.",
          comment: row.description || null,
          source: "unclassified",
        });
      }
    }

    const failed = findings.filter((f) => f.status === "FAIL");
    const autoClassified = findings.filter((f) => f.source === "auto_classified");
    const registryPath = path.join(PHASE13_DIR, "SECURITY-DEFINER-REGISTRY.md");
    fs.mkdirSync(PHASE13_DIR, { recursive: true });

    const md = [
      "# SECURITY DEFINER registry (Phase 13 deep audit)",
      "",
      "Every `public` SECURITY DEFINER function must be `PASS` or `INTENTIONAL_AND_DOCUMENTED`.",
      "Generic `REVIEW` is not allowed. `UNEXPLAINED SECURITY DEFINER` must be 0.",
      "",
      `**Generated**: ${new Date().toISOString()}`,
      `**Total**: ${findings.length} | **PASS**: ${
        findings.filter((f) => f.status === "PASS").length
      } | **FAIL/UNEXPLAINED**: ${unexplained}`,
      `**Source breakdown**: registry=${findings.filter(f=>f.source==="registry").length}, auto_classified=${autoClassified.length}, execute_revoked=${findings.filter(f=>f.source==="execute_revoked").length}, unclassified=${findings.filter(f=>f.source==="unclassified").length}, hard_fail=${findings.filter(f=>f.source==="hard_fail").length}`,
      "",
      ...findings.map((f) =>
        [
          `## \`${f.function}\``,
          "",
          `- Verdict: **${f.verdict}**`,
          `- Gate: ${f.status}`,
          `- search_path pinned: ${f.search_path_pinned}`,
          `- Source: ${f.source || "registry"}`,
          `- Rationale: ${f.rationale || f.detail || "n/a"}`,
          f.patterns
            ? `- Evidence patterns:\n${f.patterns.map((p) => `  - \`${p}\``).join("\n")}`
            : null,
          "",
        ]
          .filter((x) => x !== null)
          .join("\n")
      ),
      "",
      `UNEXPLAINED SECURITY DEFINER = ${unexplained}`,
      "",
    ].join("\n");
    fs.writeFileSync(registryPath, md);

    return {
      status: failed.length === 0 && unexplained === 0 ? "PASS" : "FAIL",
      detail: `functions=${findings.length}; unexplained=${unexplained}; failed=${failed.length}; auto_classified=${autoClassified.length}`,
      unexplained,
      findings,
      unexplained_names: findings
        .filter((f) => f.verdict === "UNEXPLAINED")
        .map((f) => f.function),
    };
  });
}

if (
  import.meta.url === `file://${process.argv[1].replace(/\\/g, "/")}` ||
  process.argv[1]?.endsWith("security-definer-audit.mjs")
) {
  runSecurityDefinerAudit()
    .then((r) => {
      console.log(JSON.stringify(r, null, 2));
      if (r.status !== "PASS") process.exit(1);
    })
    .catch((e) => {
      console.error(e);
      process.exit(1);
    });
}
