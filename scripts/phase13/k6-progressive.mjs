#!/usr/bin/env node
/**
 * Progressive k6 stages: 10 → 25 → 50 → 100 → 250
 * Stop escalating a workload when a stage fails.
 * Capacity claim = highest PASSED stage only.
 */
import { spawnSync } from "node:child_process";
import path from "node:path";
import { ROOT, ensureLocalEnv } from "./env.mjs";

const STAGES = [10, 25, 50, 100, 250];

function runStage(script, vus, env) {
  const file = path.join(ROOT, "tests", "k6", script);
  const result = spawnSync(
    "k6",
    ["run", file],
    {
      cwd: ROOT,
      encoding: "utf8",
      env: {
        ...process.env,
        VUS: String(vus),
        DURATION: process.env.K6_DURATION || "20s",
        BASE_URL: env.appUrl,
        SUPABASE_URL: env.apiUrl,
        SUPABASE_ANON_KEY: env.anonKey,
      },
    }
  );
  return {
    vus,
    exitCode: result.status,
    pass: result.status === 0,
    stderr: (result.stderr || "").slice(-2000),
    stdout: (result.stdout || "").slice(-2000),
  };
}

export function runK6Workload(name, script) {
  let env;
  try {
    env = ensureLocalEnv();
  } catch (e) {
    return {
      workload: name,
      status: "FAIL",
      verified_capacity: 0,
      detail: String(e.message || e),
      stages: [],
    };
  }

  const stages = [];
  let verified = 0;
  for (const vus of STAGES) {
    console.log(`\n[k6 ${name}] stage VUS=${vus}`);
    const r = runStage(script, vus, env);
    stages.push({ vus, status: r.pass ? "PASS" : "FAIL", exitCode: r.exitCode });
    if (!r.pass) {
      console.log(r.stderr || r.stdout);
      break;
    }
    verified = vus;
  }

  return {
    workload: name,
    status: verified > 0 ? "PASS" : "FAIL",
    verified_capacity: verified,
    detail: `highest passed stage = ${verified}`,
    stages,
  };
}

export function runAllK6() {
  // READ needs Next app; if not up, try starting is out of scope — mark fail for read only
  const read = runK6Workload("READ", "read.js");
  const write = runK6Workload("WRITE", "write.js");
  const mixed = runK6Workload("MIXED", "mixed.js");
  return { read, write, mixed };
}

if (process.argv[1]?.endsWith("k6-progressive.mjs")) {
  const which = process.argv[2] || "all";
  let out;
  if (which === "read") out = { read: runK6Workload("READ", "read.js") };
  else if (which === "write") out = { write: runK6Workload("WRITE", "write.js") };
  else if (which === "mixed") out = { mixed: runK6Workload("MIXED", "mixed.js") };
  else out = runAllK6();
  console.log(JSON.stringify(out, null, 2));
  const caps = [out.read, out.write, out.mixed].filter(Boolean);
  if (caps.some((c) => c.verified_capacity === 0)) process.exit(1);
}
