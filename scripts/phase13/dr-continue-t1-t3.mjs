#!/usr/bin/env node
/**
 * DR drill continuation: schema verify → fixtures → Small+PITR.
 * Disposable primary only. Cap USD 40. Staging forbidden.
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const DR_DIR = path.join(ROOT, "docs", "qa", "phase13", "dr");
const logPath = path.join(DR_DIR, "DR-CONTINUE.json");

const steps = [
  "dr-t1-schema.mjs",
  "dr-t2-load-fixtures.mjs",
  "dr-t3-enable-pitr.mjs",
];

const report = { started: new Date().toISOString(), steps: [], finished: null };
fs.writeFileSync(logPath, JSON.stringify(report, null, 2));

for (const script of steps) {
  const at = new Date().toISOString();
  const r = spawnSync(process.execPath, [path.join(ROOT, "scripts", "phase13", script)], {
    cwd: ROOT,
    encoding: "utf8",
    timeout: 900000,
    windowsHide: true,
    env: process.env,
  });
  report.steps.push({
    script,
    at,
    finished: new Date().toISOString(),
    exit_code: r.status,
    signal: r.signal,
    stderr: String(r.stderr || "").slice(0, 2000),
    stdout: String(r.stdout || "").slice(0, 1000),
  });
  fs.writeFileSync(logPath, JSON.stringify(report, null, 2));
  if (r.status !== 0) {
    report.finished = new Date().toISOString();
    report.status = "STOPPED";
    fs.writeFileSync(logPath, JSON.stringify(report, null, 2));
    process.exit(r.status || 1);
  }
}

report.finished = new Date().toISOString();
report.status = "OK";
fs.writeFileSync(logPath, JSON.stringify(report, null, 2));
