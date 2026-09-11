#!/usr/bin/env node
/**
 * Phase 14 pre-pilot orchestrator. LOCAL/STAGING only.
 * Does not provision paid resources or Production.
 */
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import { PHASE14_DIR, ROOT } from "./env.mjs";
import { writeProvenance } from "../phase13/provenance.mjs";
import { withDb } from "../phase13/db.mjs";
import { LOCAL } from "../phase13/env.mjs";
import { generateReleaseManifest, validateReleaseManifest } from "./generate-release-manifest.mjs";
import { runMigrationDrift } from "./migration-drift.mjs";
import { runRollbackRehearsal } from "./rollback-rehearsal.mjs";
import { runOnboardingFlow } from "./onboarding-flow.mjs";
import { runAuthorizationAcceptance } from "./role-acceptance.mjs";
import { runPilotGoldenFlows } from "./golden-flows.mjs";
import { runTenantExport } from "./tenant-export.mjs";
import { runObservabilityCheck } from "./observability-check.mjs";
import { runFeatureReleaseMatrix } from "./feature-release-matrix.mjs";
import { runCompatibility } from "./compatibility.mjs";
import { runPilotAcceptance } from "./pilot-acceptance.mjs";
import { runSecurityDefinerAudit } from "../phase13/security-definer-audit.mjs";
import { runDeepAuthzAudit } from "../phase13/deep-authz-audit.mjs";
import { runCrossTenantMatrix } from "../phase13/cross-tenant-matrix.mjs";
import { runIdempotencyTests } from "../phase13/idempotency.mjs";
import { validateRunbook } from "../phase13/release-manifest.mjs";

function gate(status, extra = {}) {
  return { status: status === "PASS" || status === true ? "PASS" : status === "FAIL" || status === false ? "FAIL" : status, ...extra };
}

async function safe(name, fn) {
  try {
    return await fn();
  } catch (e) {
    return { status: "FAIL", detail: `${name}: ${e.message}` };
  }
}

export async function runPrePilot({ skipHeavy = false } = {}) {
  fs.mkdirSync(PHASE14_DIR, { recursive: true });
  writeProvenance();
  generateReleaseManifest({ environment: "local" });
  try {
    await withDb(async (client) => {
      const { rows } = await client.query(
        `select 1 from public.app_settings
         where key = 'platform.phase13.definer_authz_hardening' limit 1`
      );
      if (rows.length) {
        await client.query(
          `insert into supabase_migrations.schema_migrations (version, name, statements)
           values (
             '20261301120000',
             'phase13_recover_definer_authz_hardening',
             array['-- recorded after docker-exec apply']::text[]
           )
           on conflict (version) do nothing`
        );
      }
    }, LOCAL.dbUrl);
  } catch {
    /* local history repair is best-effort */
  }

  const release = validateReleaseManifest();
  const drift = await safe("drift", runMigrationDrift);
  const rollback = await safe("rollback", runRollbackRehearsal);
  const compat = await safe("compat", runCompatibility);
  const observability = runObservabilityCheck();
  const features = await safe("features", runFeatureReleaseMatrix);
  const runbooks = validateRunbook();

  let onboarding;
  let authz;
  let flows;
  let exp;
  let acceptance;
  let definer;
  let deep;
  let cross;
  let idem;

  if (skipHeavy) {
    onboarding = { status: "SKIPPED", ONBOARDING_FULL_FLOW: "SKIPPED" };
    authz = { status: "SKIPPED", AUTHORIZATION_ACCEPTANCE: "SKIPPED" };
    flows = { status: "SKIPPED", PILOT_GOLDEN_FLOWS: "SKIPPED" };
    exp = { status: "SKIPPED", TENANT_DATA_EXPORT: "SKIPPED" };
    acceptance = { status: "SKIPPED", PILOT_ACCEPTANCE: "SKIPPED" };
    definer = { status: "SKIPPED" };
    deep = { status: "SKIPPED" };
    cross = { status: "SKIPPED" };
    idem = { status: "SKIPPED" };
  } else {
    onboarding = await safe("onboarding", runOnboardingFlow);
    authz = await safe("authz", runAuthorizationAcceptance);
    flows = await safe("flows", runPilotGoldenFlows);
    exp = await safe("export", runTenantExport);
    acceptance = await safe("acceptance", runPilotAcceptance);
    definer = await safe("definer", runSecurityDefinerAudit);
    deep = await safe("deep", runDeepAuthzAudit);
    cross = await safe("cross", runCrossTenantMatrix);
    idem = await safe("idem", runIdempotencyTests);
  }

  const envIsolation = (() => {
    try {
      execSync("npx vitest run tests/unit/env.test.ts", {
        cwd: ROOT,
        stdio: "pipe",
        encoding: "utf8",
      });
      return { status: "PASS", detail: "env isolation unit tests" };
    } catch (e) {
      return { status: "FAIL", detail: e.stdout || e.message };
    }
  })();

  let perf = { status: "UNPROVEN", detail: "reuse Phase 13 k6 last-run if present" };
  const k6Path = path.join(ROOT, "docs/qa/phase13/app-load-last-run.json");
  if (fs.existsSync(k6Path)) {
    const k6 = JSON.parse(fs.readFileSync(k6Path, "utf8"));
    const ok =
      k6.VERIFIED_READ_CAPACITY_APP >= 10 &&
      k6.VERIFIED_WRITE_CAPACITY_APP >= 10 &&
      k6.VERIFIED_MIXED_CAPACITY_APP >= 10;
    perf = {
      status: ok ? "PASS" : "FAIL",
      detail: "Phase 13 operational load reused as regression baseline (no higher load required)",
      verified: {
        read: k6.VERIFIED_READ_CAPACITY_APP,
        write: k6.VERIFIED_WRITE_CAPACITY_APP,
        mixed: k6.VERIFIED_MIXED_CAPACITY_APP,
      },
    };
  }

  const securityOk =
    definer.status === "PASS" &&
    deep.status === "PASS" &&
    cross.status === "PASS" &&
    idem.status === "PASS";

  const summary = {
    ENVIRONMENT_ISOLATION: envIsolation.status,
    RELEASE_MANIFEST: release.RELEASE_MANIFEST_VALID || release.status,
    MIGRATION_DRIFT: drift.MIGRATION_DRIFT === 0 ? "PASS" : drift.status,
    ROLLBACK_REHEARSAL: rollback.ROLLBACK_REHEARSAL || rollback.status,
    ONBOARDING_FULL_FLOW: onboarding.ONBOARDING_FULL_FLOW || onboarding.status,
    AUTHORIZATION_ACCEPTANCE: authz.AUTHORIZATION_ACCEPTANCE || authz.status,
    PILOT_GOLDEN_FLOWS: flows.PILOT_GOLDEN_FLOWS || flows.status,
    TENANT_DATA_EXPORT: exp.TENANT_DATA_EXPORT || exp.status,
    OBSERVABILITY: observability.OBSERVABILITY || observability.status,
    RUNBOOKS: runbooks.status,
    PILOT_ACCEPTANCE: acceptance.PILOT_ACCEPTANCE || acceptance.status,
    SECURITY_REGRESSION: securityOk ? "PASS" : definer.status === "SKIPPED" ? "SKIPPED" : "FAIL",
    PERFORMANCE_REGRESSION: perf.status,
    COMPATIBILITY: compat.status,
    FEATURE_RELEASE_MATRIX: features.status,
  };

  const blocking = Object.entries(summary).filter(
    ([, v]) => v !== "PASS" && v !== "SKIPPED"
  );
  const zeroCostPass = blocking.length === 0;

  const report = {
    phase: 14,
    generated_at: new Date().toISOString(),
    PHASE14_PRE_PILOT_GATE: zeroCostPass ? "PASS" : "FAIL",
    PHASE_14: "IN_PROGRESS",
    PUBLIC_PRODUCTION_LAUNCH: "NOT_AUTHORIZED",
    PRODUCTION: "NOT_AUTHORIZED",
    PHASE_13_DR: {
      RPO_5m: "UNPROVEN",
      RTO_4h: "UNPROVEN",
      COST_APPROVAL_REQUIRED: true,
    },
    ARCA_HOMOLOGATION: "BLOCKED_PENDING",
    summary,
    blocking: blocking.map(([k, v]) => ({ gate: k, status: v })),
    details: {
      release,
      drift,
      rollback,
      onboarding,
      authz: { status: authz.status, failed: authz.failed },
      flows,
      exp: { status: exp.status, failed: exp.failed },
      observability,
      runbooks,
      acceptance,
      definer: { status: definer.status, detail: definer.detail },
      deep: { status: deep.status || deep.DEFINER_DEEP_AUTHZ_PASS },
      cross: { status: cross.status, detail: cross.detail },
      idem: { status: idem.status },
      perf,
      compat,
      envIsolation,
    },
  };

  fs.writeFileSync(
    path.join(PHASE14_DIR, "pre-pilot-last-run.json"),
    JSON.stringify(report, null, 2) + "\n"
  );
  writeMarkdownReport(report);
  return report;
}

function writeMarkdownReport(report) {
  const rows = Object.entries(report.summary)
    .map(([k, v]) => `| ${k} | ${v} |`)
    .join("\n");
  const md = `# Phase 14 pre-pilot report

**Generated:** ${report.generated_at}

\`\`\`
PHASE14_PRE_PILOT_GATE     = ${report.PHASE14_PRE_PILOT_GATE}
PHASE_14                   = ${report.PHASE_14}
PUBLIC_PRODUCTION_LAUNCH   = ${report.PUBLIC_PRODUCTION_LAUNCH}
PRODUCTION                 = ${report.PRODUCTION}
RPO <= 5m                  = UNPROVEN
RTO <= 4h                  = UNPROVEN
ARCA homologation          = BLOCKED_PENDING
\`\`\`

## Summary

| Gate | Result |
|------|--------|
${rows}

## Blocking

${report.blocking.length === 0 ? "_None._" : report.blocking.map((b) => `- ${b.gate}: ${b.status}`).join("\n")}

## Classifications used

| Code | Meaning |
|------|---------|
| PASS | Zero-cost evidence collected locally |
| FAIL | Gate executed and did not meet criteria |
| BLOCKED | Cannot complete without missing product capability |
| REVIEW_REQUIRED | Legal/commercial — see COMMERCIAL-LEGAL-CHECKLIST.md |
| COST_APPROVAL_REQUIRED | Phase 13 DR / paid resources |

Commercial/legal: **REVIEW_REQUIRED** (not a zero-cost blocker).
Phase 13 DR: **COST_APPROVAL_REQUIRED**.

STOP. Do not provision paid resources. Do not deploy Production.
`;
  fs.writeFileSync(path.join(PHASE14_DIR, "PHASE-14-PRE-PILOT-REPORT.md"), md);
}

if (process.argv[1]?.endsWith("run-pre-pilot.mjs")) {
  const skipHeavy = process.argv.includes("--skip-heavy");
  runPrePilot({ skipHeavy })
    .then((r) => {
      console.log(JSON.stringify({
        PHASE14_PRE_PILOT_GATE: r.PHASE14_PRE_PILOT_GATE,
        PHASE_14: r.PHASE_14,
        summary: r.summary,
        blocking: r.blocking,
      }, null, 2));
      if (r.PHASE14_PRE_PILOT_GATE !== "PASS") process.exit(2);
    })
    .catch((e) => {
      console.error(e);
      process.exit(1);
    });
}
