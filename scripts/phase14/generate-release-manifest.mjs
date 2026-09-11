#!/usr/bin/env node
import { execSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { ROOT, RELEASE_DIR, RELEASE_MANIFEST_PATH, PHASE13_DIR } from "./env.mjs";
import { listMigrations } from "../phase13/provenance.mjs";

function git(cmd) {
  try {
    return execSync(cmd, { cwd: ROOT, encoding: "utf8" }).trim();
  } catch {
    return null;
  }
}

export function generateReleaseManifest({ environment = "local" } = {}) {
  const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, "package.json"), "utf8"));
  const migrations = listMigrations();
  const chain = crypto
    .createHash("sha256")
    .update(migrations.map((m) => `${m.name}:${m.sha256}`).join("\n"))
    .digest("hex");

  let schemaFingerprint = null;
  const fpPath = path.join(PHASE13_DIR, "schema-fingerprint.expected.json");
  if (fs.existsSync(fpPath)) {
    const fp = JSON.parse(fs.readFileSync(fpPath, "utf8"));
    schemaFingerprint = fp.sha256 || fp.fingerprint || null;
  }

  const sha = git("git rev-parse HEAD");
  const tag = git("git describe --tags --exact-match HEAD") || null;
  const buildTs = new Date().toISOString();
  const releaseTag = tag || `local-${(sha || "unknown").slice(0, 12)}-${buildTs.slice(0, 10)}`;

  const manifest = {
    schema_version: 1,
    git_commit_sha: sha,
    release_tag: releaseTag,
    application_version: pkg.version,
    environment,
    build_timestamp: buildTs,
    rollback_reference: {
      strategy: "FORWARD_CORRECTION_ONLY",
      previous_release_tag: null,
      destructive_downgrade_migrations: false,
      note: "Database rollback is not implemented via automatic down migrations.",
    },
    migration_manifest: migrations.map((m) => ({
      name: m.name,
      sha256: m.sha256,
      bytes: m.bytes,
    })),
    migration_chain_sha256: chain,
    schema_fingerprint_sha256: schemaFingerprint,
    feature_release_matrix: {
      accounting: "controlled",
      sales: "controlled",
      purchases: "controlled",
      treasury: "controlled",
      inventory: "controlled",
      pos: "controlled",
      taxes: "controlled/review",
      dashboard: "controlled",
      fiscal_invoicing: "BLOCKED_PENDING_ARCA_HOMOLOGATION",
      medical_legal: "RESTRICTED",
      future_modules: "COMING_SOON",
    },
    production_authorized: false,
    rpo_5m: "UNPROVEN",
    rto_4h: "UNPROVEN",
  };

  fs.mkdirSync(RELEASE_DIR, { recursive: true });
  fs.writeFileSync(RELEASE_MANIFEST_PATH, JSON.stringify(manifest, null, 2) + "\n");
  return manifest;
}

export function validateReleaseManifest() {
  if (!fs.existsSync(RELEASE_MANIFEST_PATH)) {
    return { status: "FAIL", detail: "docs/release/RELEASE-MANIFEST.json missing" };
  }
  const m = JSON.parse(fs.readFileSync(RELEASE_MANIFEST_PATH, "utf8"));
  const required = [
    "git_commit_sha",
    "release_tag",
    "application_version",
    "migration_manifest",
    "migration_chain_sha256",
    "schema_fingerprint_sha256",
    "feature_release_matrix",
    "environment",
    "build_timestamp",
    "rollback_reference",
  ];
  const missing = required.filter((k) => m[k] == null || m[k] === "");
  const migrations = listMigrations();
  const liveChain = crypto
    .createHash("sha256")
    .update(migrations.map((x) => `${x.name}:${x.sha256}`).join("\n"))
    .digest("hex");
  const drift = liveChain !== m.migration_chain_sha256;
  const fiscalBlocked =
    m.feature_release_matrix?.fiscal_invoicing ===
    "BLOCKED_PENDING_ARCA_HOMOLOGATION";

  const ok =
    missing.length === 0 &&
    !drift &&
    Array.isArray(m.migration_manifest) &&
    m.migration_manifest.length === migrations.length &&
    fiscalBlocked &&
    m.production_authorized === false;

  return {
    status: ok ? "PASS" : "FAIL",
    RELEASE_MANIFEST_VALID: ok ? "PASS" : "FAIL",
    missing,
    migration_count: migrations.length,
    chain_match: !drift,
    detail: ok
      ? `manifest valid; migrations=${migrations.length}`
      : `missing=${missing.join(",") || "none"}; chain_match=${!drift}`,
  };
}

if (process.argv[1]?.endsWith("generate-release-manifest.mjs")) {
  const m = generateReleaseManifest();
  const v = validateReleaseManifest();
  console.log(JSON.stringify({ generated: m.release_tag, validation: v }, null, 2));
  if (v.status !== "PASS") process.exit(1);
}
