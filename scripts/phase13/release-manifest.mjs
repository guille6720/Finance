#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { ROOT } from "./env.mjs";

const REQUIRED = [
  "docs/ops/RELEASE-MANIFEST.md",
  "docs/ops/RUNBOOK.md",
  "docs/ops/INCIDENT-RESPONSE.md",
  "docs/qa/phase13/SECURITY-DEFINER-REGISTRY.md",
  "supabase/migrations",
  "supabase/seed.sql",
  "scripts/phase13/cleanroom.mjs",
  "tests/k6/read.js",
  "tests/k6/write.js",
  "tests/k6/mixed.js",
];

export function verifyReleaseManifest() {
  const missing = [];
  for (const rel of REQUIRED) {
    const full = path.join(ROOT, rel);
    if (!fs.existsSync(full)) missing.push(rel);
  }

  const manifest = fs.readFileSync(
    path.join(ROOT, "docs/ops/RELEASE-MANIFEST.md"),
    "utf8"
  );
  const hasNonClaims =
    manifest.includes("RPO") &&
    manifest.includes("unproven") &&
    manifest.includes("FORBIDDEN");

  return {
    status: missing.length === 0 && hasNonClaims ? "PASS" : "FAIL",
    detail:
      missing.length === 0 && hasNonClaims
        ? "release manifest artifacts present; Production/DR non-claims recorded"
        : `missing=${missing.join(", ") || "none"}; nonclaims=${hasNonClaims}`,
    missing,
  };
}

export function validateRunbook() {
  const runbook = fs.readFileSync(path.join(ROOT, "docs/ops/RUNBOOK.md"), "utf8");
  const incident = fs.readFileSync(
    path.join(ROOT, "docs/ops/INCIDENT-RESPONSE.md"),
    "utf8"
  );
  const checks = [
    {
      id: "runbook.local_start",
      status: runbook.includes("supabase start") ? "PASS" : "FAIL",
    },
    {
      id: "runbook.forbids_paid_provision",
      status: /Do not provision paid|Do not provision any paid/i.test(runbook) ? "PASS" : "FAIL",
    },
    {
      id: "incident.forbids_production",
      status: /Accessing Production/i.test(incident) ? "PASS" : "FAIL",
    },
    {
      id: "incident.forbids_arca",
      status: /ARCA/i.test(incident) ? "PASS" : "FAIL",
    },
    {
      id: "runbook.mentions_rpo_rto_cost_gate",
      status: /COST_APPROVAL_REQUIRED|RPO|RTO/i.test(runbook) ? "PASS" : "FAIL",
    },
  ];
  const failed = checks.filter((c) => c.status === "FAIL");
  return {
    status: failed.length === 0 ? "PASS" : "FAIL",
    detail: `checks=${checks.length}; failed=${failed.length}`,
    checks,
  };
}

if (process.argv[1]?.endsWith("release-manifest.mjs")) {
  const r = verifyReleaseManifest();
  console.log(JSON.stringify(r, null, 2));
  if (r.status !== "PASS") process.exit(1);
}
