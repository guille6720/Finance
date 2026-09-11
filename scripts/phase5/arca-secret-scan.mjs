#!/usr/bin/env node
/**
 * ARCA_SECRET_SCAN — fail if secrets patterns appear in tracked sources.
 * Does not print secret values.
 */
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";

const ROOT = process.cwd();

const FORBIDDEN_PATHS = [
  ".env.arca.homo.local",
  "contabilium-homo.key",
  "contabilium-homo.pem",
];

const FILE_GLOBS_DENY = [
  /\.pem$/i,
  /\.key$/i,
  /\.p12$/i,
  /\.pfx$/i,
];

const CONTENT_PATTERNS = [
  { id: "BEGIN_PRIVATE_KEY", re: /-----BEGIN (?:RSA )?PRIVATE KEY-----/ },
  { id: "BEGIN_CERTIFICATE_BODY", re: /-----BEGIN CERTIFICATE-----\s*[A-Za-z0-9+/=\r\n]{80,}/ },
  { id: "NEXT_PUBLIC_ARCA_SECRET", re: /NEXT_PUBLIC_ARCA_(?:HOMO_PRIVATE_KEY|HOMO_CERT|REPRESENTED_CUIT)/ },
  { id: "HARDCODED_HOMO_B64_ASSIGN", re: /ARCA_HOMO_(?:PRIVATE_KEY|CERT)_B64\s*=\s*["'][A-Za-z0-9+/]{40,}/ },
];

function listTrackedFiles() {
  try {
    const out = execSync("git ls-files", { encoding: "utf8", cwd: ROOT });
    return out.split(/\r?\n/).filter(Boolean);
  } catch {
    return [];
  }
}

const findings = [];

for (const rel of FORBIDDEN_PATHS) {
  if (fs.existsSync(path.join(ROOT, rel))) {
    // local file ok if gitignored; fail only if tracked
    try {
      execSync(`git ls-files --error-unmatch -- "${rel}"`, {
        cwd: ROOT,
        stdio: "ignore",
      });
      findings.push({ id: "TRACKED_SECRET_FILE", path: rel });
    } catch {
      /* untracked/gitignored — ok */
    }
  }
}

for (const rel of listTrackedFiles()) {
  if (FILE_GLOBS_DENY.some((r) => r.test(rel))) {
    findings.push({ id: "TRACKED_KEY_OR_CERT_FILE", path: rel });
    continue;
  }
  if (!/\.(ts|tsx|js|mjs|cjs|md|json|env|example|toml|yml|yaml)$/i.test(rel)) continue;
  if (rel.startsWith("docs/qa/phase13/") || rel.includes("node_modules")) continue;
  let text;
  try {
    text = fs.readFileSync(path.join(ROOT, rel), "utf8");
  } catch {
    continue;
  }
  for (const p of CONTENT_PATTERNS) {
    if (rel.startsWith("tests/") && p.id === "BEGIN_PRIVATE_KEY") continue;
    if (rel.startsWith("tests/") && p.id === "BEGIN_CERTIFICATE_BODY") continue;
    if (p.id === "BEGIN_CERTIFICATE_BODY" && rel.endsWith(".example")) continue;
    if (p.re.test(text)) {
      findings.push({ id: p.id, path: rel });
    }
  }
}

const pass = findings.length === 0;
const report = {
  ARCA_SECRET_SCAN: pass ? "PASS" : "FAIL",
  findings_count: findings.length,
  findings: findings.map((f) => ({ id: f.id, path: f.path })),
};

const outDir = path.join(ROOT, "docs", "qa", "phase5");
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(
  path.join(outDir, "ARCA-SECRET-SCAN.json"),
  JSON.stringify(report, null, 2) + "\n"
);
console.log(JSON.stringify(report, null, 2));
process.exit(pass ? 0 : 1);
