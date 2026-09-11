#!/usr/bin/env node
/**
 * All zero-cost Phase 13 gates (local disposable only).
 * Stops before any paid/remote DR provision.
 */
import fs from "node:fs";
import path from "node:path";
import { PHASE13_DIR, ROOT } from "./env.mjs";
import { runUpgradeRehearsal } from "./upgrade-rehearsal.mjs";
import { runSecurityDefinerAudit } from "./security-definer-audit.mjs";
import { runCrossTenantMatrix } from "./cross-tenant-matrix.mjs";
import { runGoldenFlow } from "./golden-flow.mjs";
import { runIdempotencyTests } from "./idempotency.mjs";
import { runAllK6 } from "./k6-progressive.mjs";
import { runPgStatReview, runLocksReview } from "./pg-stat-review.mjs";
import { verifyReleaseManifest, validateRunbook } from "./release-manifest.mjs";
import { runFullRegression } from "./regression.mjs";
import { runSecurityAdvisor, runPerformanceAdvisor } from "./advisors.mjs";

async function waitForHealth(ms = 60000) {
  const start = Date.now();
  while (Date.now() - start < ms) {
    try {
      const r = await fetch("http://127.0.0.1:3000/api/health");
      if (r.ok) return true;
    } catch {
      /* retry */
    }
    await new Promise((r) => setTimeout(r, 1500));
  }
  return false;
}

async function main() {
  fs.mkdirSync(PHASE13_DIR, { recursive: true });
  const report = {
    phase: 13,
    status: "IN_PROGRESS",
    generated_at: new Date().toISOString(),
    gates: {},
  };

  console.log("\n[1] Upgrade rehearsal");
  report.gates.upgrade_rehearsal = await runUpgradeRehearsal();
  console.log(report.gates.upgrade_rehearsal.status, report.gates.upgrade_rehearsal.detail);

  console.log("\n[2] Deep SECURITY DEFINER authz audit");
  report.gates.security_definer = await runSecurityDefinerAudit();
  console.log(report.gates.security_definer.status, report.gates.security_definer.detail);

  console.log("\n[3] Cross-tenant A/B × roles matrix");
  report.gates.cross_tenant = await runCrossTenantMatrix();
  console.log(report.gates.cross_tenant.status, report.gates.cross_tenant.detail);

  console.log("\n[4] Full synthetic golden flow");
  report.gates.golden_flow = await runGoldenFlow();
  console.log(report.gates.golden_flow.status, report.gates.golden_flow.detail);

  console.log("\n[5] Retry/idempotency tests");
  report.gates.idempotency = await runIdempotencyTests();
  console.log(report.gates.idempotency.status, report.gates.idempotency.detail);

  console.log("\n[6–8] k6 READ / WRITE / MIXED");
  // Prefer existing /api/health (Next or phase13 health stand-in). Do not start
  // Next.js here — Turbopack + local Supabase Docker can OOM on constrained hosts.
  const { spawn } = await import("node:child_process");
  let standinProc = null;
  try {
    const healthy = await fetch("http://127.0.0.1:3000/api/health")
      .then((r) => r.ok)
      .catch(() => false);
    if (!healthy) {
      standinProc = spawn("node", ["scripts/phase13/health-standin.mjs"], {
        cwd: ROOT,
        env: process.env,
        shell: true,
        stdio: "ignore",
        detached: true,
      });
      const ok = await waitForHealth(15000);
      if (!ok) console.warn("Health endpoint not ready; READ/MIXED may fail");
    }
  } catch (e) {
    console.warn(e);
  }

  report.gates.k6 = runAllK6();
  report.VERIFIED_READ_CAPACITY = report.gates.k6.read?.verified_capacity ?? 0;
  report.VERIFIED_WRITE_CAPACITY = report.gates.k6.write?.verified_capacity ?? 0;
  report.VERIFIED_MIXED_CAPACITY = report.gates.k6.mixed?.verified_capacity ?? 0;
  console.log("VERIFIED_READ_CAPACITY", report.VERIFIED_READ_CAPACITY);
  console.log("VERIFIED_WRITE_CAPACITY", report.VERIFIED_WRITE_CAPACITY);
  console.log("VERIFIED_MIXED_CAPACITY", report.VERIFIED_MIXED_CAPACITY);

  if (standinProc?.pid) {
    try {
      process.kill(-standinProc.pid);
    } catch {
      try {
        process.kill(standinProc.pid);
      } catch {
        /* ignore */
      }
    }
  }

  console.log("\n[9] pg_stat_statements review");
  report.gates.pg_stat = await runPgStatReview();
  console.log(report.gates.pg_stat.status, report.gates.pg_stat.detail);

  console.log("\n[10] connection/lock/deadlock review");
  report.gates.locks = await runLocksReview();
  console.log(report.gates.locks.status, report.gates.locks.detail);

  console.log("\n[11] release manifest verification");
  report.gates.release_manifest = verifyReleaseManifest();
  console.log(report.gates.release_manifest.status);

  console.log("\n[12] incident/runbook validation");
  report.gates.runbook = validateRunbook();
  console.log(report.gates.runbook.status);

  console.log("\n[13] full regression");
  report.gates.regression = runFullRegression();
  console.log(report.gates.regression.status, report.gates.regression.detail);

  console.log("\n[14] Staging Security Advisor (local equivalent)");
  report.gates.security_advisor = await runSecurityAdvisor();
  console.log(report.gates.security_advisor.status, report.gates.security_advisor.detail);

  console.log("\n[15] Staging Performance Advisor (local equivalent)");
  report.gates.performance_advisor = await runPerformanceAdvisor();
  console.log(
    report.gates.performance_advisor.status,
    report.gates.performance_advisor.detail
  );

  report.COST_APPROVAL_REQUIRED = {
    missing_tests: [
      {
        test: "DB restore drill proving RPO <= 5 minutes",
        required_resource:
          "Remote disposable Supabase project with backup/PITR or external DB backup restore target (paid options may apply)",
      },
      {
        test: "Storage restore drill proving RTO <= 4 hours (DB + Storage)",
        required_resource:
          "External Storage backup provider and/or Supabase Storage backup on disposable remote project",
      },
    ],
    note: "Do NOT provision. Phase 13 remains IN PROGRESS until drills complete.",
  };

  report.DR = {
    RPO_5_MIN_PROVEN: false,
    RTO_4_HOURS_PROVEN: false,
    reason: "Documentation/runbooks alone do not prove RPO/RTO",
  };

  const zeroCostFail = [
    report.gates.upgrade_rehearsal,
    report.gates.security_definer,
    report.gates.cross_tenant,
    report.gates.idempotency,
    report.gates.pg_stat,
    report.gates.locks,
    report.gates.release_manifest,
    report.gates.runbook,
    report.gates.regression,
    report.gates.security_advisor,
    report.gates.performance_advisor,
  ].filter((g) => g.status !== "PASS");

  // golden full chain expected blocked on Phase 1-only schema
  report.gates.golden_flow_phase1 = {
    status: report.gates.golden_flow.phase1_golden,
  };

  report.status = "IN_PROGRESS";
  report.zero_cost_blockers = zeroCostFail.map((g) => g.detail || g.status);

  const out = path.join(PHASE13_DIR, "zero-cost-last-run.json");
  fs.writeFileSync(out, JSON.stringify(report, null, 2) + "\n");

  const statusMd = `# Phase 13 status

**STATUS: IN PROGRESS**

Generated: ${report.generated_at}

## Capacities (highest PASSED k6 stage only)

- VERIFIED_READ_CAPACITY = ${report.VERIFIED_READ_CAPACITY}
- VERIFIED_WRITE_CAPACITY = ${report.VERIFIED_WRITE_CAPACITY}
- VERIFIED_MIXED_CAPACITY = ${report.VERIFIED_MIXED_CAPACITY}

## DR

- RPO <= 5 minutes: **NOT PROVEN**
- RTO <= 4 hours: **NOT PROVEN**

## COST_APPROVAL_REQUIRED

${report.COST_APPROVAL_REQUIRED.missing_tests
  .map((t) => `- **${t.test}** → requires: ${t.required_resource}`)
  .join("\n")}

Do NOT provision paid resources from this document.

## Gate snapshot

See \`zero-cost-last-run.json\`.
`;
  fs.writeFileSync(path.join(PHASE13_DIR, "PHASE-13-STATUS.md"), statusMd);

  console.log("\n=== PHASE 13 ZERO-COST SUMMARY ===");
  console.log("STATUS: IN_PROGRESS");
  console.log("VERIFIED_READ_CAPACITY", report.VERIFIED_READ_CAPACITY);
  console.log("VERIFIED_WRITE_CAPACITY", report.VERIFIED_WRITE_CAPACITY);
  console.log("VERIFIED_MIXED_CAPACITY", report.VERIFIED_MIXED_CAPACITY);
  console.log("COST_APPROVAL_REQUIRED", JSON.stringify(report.COST_APPROVAL_REQUIRED, null, 2));
  console.log(`Wrote ${out}`);

  // Exit non-zero if critical zero-cost gates failed (excluding known domain-blocked golden)
  if (zeroCostFail.length > 0) process.exit(1);
  if (report.VERIFIED_WRITE_CAPACITY === 0) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
