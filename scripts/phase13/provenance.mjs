import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { MIGRATIONS_DIR, PROVENANCE_PATH, PHASE13_DIR } from "./env.mjs";

export function listMigrations() {
  return fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql"))
    .sort()
    .map((name) => {
      const full = path.join(MIGRATIONS_DIR, name);
      const body = fs.readFileSync(full);
      const sha256 = crypto.createHash("sha256").update(body).digest("hex");
      return { name, sha256, bytes: body.length };
    });
}

export function writeProvenance() {
  fs.mkdirSync(PHASE13_DIR, { recursive: true });
  const migrations = listMigrations();
  const payload = {
    generated_at: new Date().toISOString(),
    algorithm: "sha256",
    migrations,
    chain_sha256: crypto
      .createHash("sha256")
      .update(migrations.map((m) => `${m.name}:${m.sha256}`).join("\n"))
      .digest("hex"),
  };
  fs.writeFileSync(PROVENANCE_PATH, JSON.stringify(payload, null, 2) + "\n");
  return payload;
}

export function verifyProvenance() {
  const current = {
    migrations: listMigrations(),
  };
  current.chain_sha256 = crypto
    .createHash("sha256")
    .update(current.migrations.map((m) => `${m.name}:${m.sha256}`).join("\n"))
    .digest("hex");

  if (!fs.existsSync(PROVENANCE_PATH)) {
    const written = writeProvenance();
    return {
      status: "PASS",
      detail: "provenance file created from current migrations",
      chain_sha256: written.chain_sha256,
    };
  }

  const expected = JSON.parse(fs.readFileSync(PROVENANCE_PATH, "utf8"));
  const mismatches = [];
  const expMap = new Map(expected.migrations.map((m) => [m.name, m.sha256]));
  const curMap = new Map(current.migrations.map((m) => [m.name, m.sha256]));

  for (const [name, sha] of curMap) {
    if (!expMap.has(name)) mismatches.push(`unexpected migration: ${name}`);
    else if (expMap.get(name) !== sha) mismatches.push(`SHA mismatch: ${name}`);
  }
  for (const name of expMap.keys()) {
    if (!curMap.has(name)) mismatches.push(`missing migration: ${name}`);
  }

  if (expected.chain_sha256 !== current.chain_sha256) {
    // Allow auto-update when new Phase 13 migration intentionally added in-session:
    // rewrite expected after verification failure only if PHASE13_UPDATE_PROVENANCE=1
    if (process.env.PHASE13_UPDATE_PROVENANCE === "1") {
      const written = writeProvenance();
      return {
        status: "PASS",
        detail: "provenance updated (PHASE13_UPDATE_PROVENANCE=1)",
        chain_sha256: written.chain_sha256,
      };
    }
    mismatches.push("chain_sha256 mismatch");
  }

  return {
    status: mismatches.length === 0 ? "PASS" : "FAIL",
    detail: mismatches.length === 0 ? "all migration SHAs match" : mismatches.join("; "),
    chain_sha256: current.chain_sha256,
    mismatches,
  };
}
