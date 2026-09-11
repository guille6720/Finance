#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { ROOT } from "./env.mjs";

export function runFullRegression() {
  const steps = [
    ["typecheck", ["npm", "run", "typecheck"]],
    ["lint", ["npm", "run", "lint"]],
    ["unit", ["npm", "run", "test"]],
  ];
  const results = [];
  for (const [id, cmd] of steps) {
    const r = spawnSync(cmd[0], cmd.slice(1), {
      cwd: ROOT,
      encoding: "utf8",
      env: process.env,
      shell: true,
    });
    results.push({
      id,
      status: r.status === 0 ? "PASS" : "FAIL",
      exitCode: r.status,
      tail: ((r.stdout || "") + (r.stderr || "")).slice(-1500),
    });
  }
  const failed = results.filter((r) => r.status === "FAIL");
  return {
    status: failed.length === 0 ? "PASS" : "FAIL",
    detail: `steps=${results.length}; failed=${failed.length}`,
    results,
  };
}

if (process.argv[1]?.endsWith("regression.mjs")) {
  const r = runFullRegression();
  console.log(JSON.stringify(r, null, 2));
  if (r.status !== "PASS") process.exit(1);
}
