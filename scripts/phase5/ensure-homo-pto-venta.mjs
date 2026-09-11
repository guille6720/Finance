#!/usr/bin/env node
/**
 * Safely ensure ARCA_HOMO_PTO_VENTA=10 exists in .env.arca.homo.local
 * without printing any secret values.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const p = path.join(ROOT, ".env.arca.homo.local");

if (!fs.existsSync(p)) {
  console.log(JSON.stringify({ status: "SKIP", reason: "local_env_missing" }));
  process.exit(0);
}

const text = fs.readFileSync(p, "utf8");
const lines = text.split(/\r?\n/);
const key = "ARCA_HOMO_PTO_VENTA";
let found = false;
const next = lines.map((line) => {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith("#")) return line;
  const eq = trimmed.indexOf("=");
  if (eq <= 0) return line;
  const k = trimmed.slice(0, eq).trim();
  if (k !== key) return line;
  found = true;
  return `${key}=10`;
});

if (!found) {
  if (next.length && next[next.length - 1] !== "") next.push("");
  next.push(`${key}=10`);
}

fs.writeFileSync(p, next.join("\n").replace(/\n*$/, "\n"), "utf8");
console.log(
  JSON.stringify({
    status: "OK",
    action: found ? "updated_key_only" : "appended_key",
    key,
    gitignored: true,
  })
);
