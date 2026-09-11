#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { PHASE14_DIR, ROOT } from "./env.mjs";

const REQUIRED_SIGNALS = [
  { id: "http_5xx", files: ["src/proxy.ts", "src/app/api/health/route.ts"] },
  { id: "correlation_id", files: ["src/proxy.ts", "src/app/api/health/route.ts", "src/app/api/org/export/route.ts"] },
  { id: "auth_errors", files: ["src/lib/supabase/middleware.ts"] },
  { id: "audit_immutability", files: ["src/lib/audit/write-audit-event.ts"] },
  { id: "runbook_p0", files: ["docs/ops/INCIDENT-RESPONSE.md"] },
  { id: "slo_doc", files: ["docs/operations/SLO-PILOT.md"] },
];

function noSecretLogging() {
  const audit = fs.readFileSync(
    path.join(ROOT, "src/lib/audit/write-audit-event.ts"),
    "utf8"
  );
  return !/password|access_token|service_role/i.test(audit);
}

export function runObservabilityCheck() {
  const missing = [];
  for (const s of REQUIRED_SIGNALS) {
    const ok = s.files.every((f) => fs.existsSync(path.join(ROOT, f)));
    if (!ok) missing.push(s.id);
  }
  const health = fs.readFileSync(path.join(ROOT, "src/app/api/health/route.ts"), "utf8");
  const proxy = fs.readFileSync(path.join(ROOT, "src/proxy.ts"), "utf8");
  const correlation = /x-correlation-id/.test(health) && /x-correlation-id/.test(proxy);

  const status =
    missing.length === 0 && correlation && noSecretLogging() ? "PASS" : "FAIL";

  const result = {
    OBSERVABILITY: status,
    status,
    signals: REQUIRED_SIGNALS.map((s) => s.id),
    correlation_id: correlation,
    secret_safe_audit_writer: noSecretLogging(),
    missing,
    runbook_links: [
      "docs/ops/INCIDENT-RESPONSE.md",
      "docs/ops/RUNBOOK.md",
      "docs/operations/SLO-PILOT.md",
    ],
  };

  fs.mkdirSync(PHASE14_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(PHASE14_DIR, "observability-last-run.json"),
    JSON.stringify(result, null, 2) + "\n"
  );
  return result;
}

if (process.argv[1]?.endsWith("observability-check.mjs")) {
  const r = runObservabilityCheck();
  console.log(JSON.stringify(r, null, 2));
  if (r.status !== "PASS") process.exit(1);
}
