#!/usr/bin/env node
/**
 * Build staging-migration-inventory.json from a saved migration list JSON
 * and local supabase/migrations files. Does not contact Staging.
 */
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { ROOT, PHASE13_DIR } from "./env.mjs";

const listPath = path.join(PHASE13_DIR, "forensics", "migration-list-raw.json");
const migDir = path.join(ROOT, "supabase", "migrations");

function sha256File(p) {
  const body = fs.readFileSync(p);
  return {
    sha256: crypto.createHash("sha256").update(body).digest("hex"),
    bytes: body.length,
    empty: body.toString("utf8").trim().length === 0,
  };
}

const raw = JSON.parse(fs.readFileSync(listPath, "utf8"));
const migrations = raw.migrations || raw;
const localFiles = fs
  .readdirSync(migDir)
  .filter((f) => f.endsWith(".sql"))
  .sort();

const localByVersion = new Map();
for (const f of localFiles) {
  const version = f.slice(0, 14);
  localByVersion.set(version, f);
}

const remoteVersions = [];
for (const row of migrations) {
  const version = row.remote || row.local;
  if (!version) continue;
  if (row.remote) remoteVersions.push(String(row.remote));
}

const uniqueRemote = [...new Set(remoteVersions)].sort();
const rows = [];
const summary = {
  LOCAL_PRESENT: 0,
  STAGING_ONLY_WITH_STATEMENTS: 0,
  STAGING_ONLY_WITHOUT_STATEMENTS: 0,
  LOCAL_ONLY: 0,
  UNKNOWN: 0,
};

for (const version of uniqueRemote) {
  const file = localByVersion.get(version);
  let classification = "UNKNOWN";
  let meta = null;
  if (file) {
    meta = sha256File(path.join(migDir, file));
    classification = meta.empty
      ? "STAGING_ONLY_WITHOUT_STATEMENTS"
      : meta.bytes > 0 && localByVersion.has(version)
        ? file.startsWith(version)
          ? "LOCAL_PRESENT"
          : "UNKNOWN"
        : "UNKNOWN";
    // If file exists and non-empty after fetch, treat as recovered statements present locally
    if (!meta.empty) classification = "LOCAL_PRESENT";
    else classification = "STAGING_ONLY_WITHOUT_STATEMENTS";
  } else {
    classification = "UNKNOWN"; // not fetched yet
  }
  summary[classification] = (summary[classification] || 0) + 1;
  rows.push({
    version,
    name: file || null,
    classification,
    ...(meta || {}),
  });
}

for (const [version, file] of localByVersion) {
  if (!uniqueRemote.includes(version)) {
    const meta = sha256File(path.join(migDir, file));
    summary.LOCAL_ONLY += 1;
    rows.push({
      version,
      name: file,
      classification: "LOCAL_ONLY",
      ...meta,
      note: "Present locally but not in Staging migration history",
    });
  }
}

const out = {
  generated_at: new Date().toISOString(),
  staging_project_ref: "rpcpdrzbcclofvjpgldb",
  staging_project_name: "Finance Staging SA",
  total_remote_versions: uniqueRemote.length,
  local_files: localFiles.length,
  summary,
  migrations: rows.sort((a, b) => String(a.version).localeCompare(String(b.version))),
};

fs.mkdirSync(PHASE13_DIR, { recursive: true });
fs.writeFileSync(
  path.join(PHASE13_DIR, "staging-migration-inventory.json"),
  JSON.stringify(out, null, 2) + "\n"
);
console.log(JSON.stringify({ summary, total_remote: uniqueRemote.length, local_files: localFiles.length }, null, 2));
