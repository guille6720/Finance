#!/usr/bin/env node
/**
 * Upgrade rehearsal: empty DB → migrations, then re-apply via db reset
 * and verify fingerprint stable (forward-only local rehearsal).
 */
import { execSync } from "node:child_process";
import { ROOT } from "./env.mjs";
import { generateFingerprint } from "./fingerprint.mjs";
import { listMigrations } from "./provenance.mjs";

export async function runUpgradeRehearsal() {
  const migrations = listMigrations();
  execSync("npx supabase db reset --yes", {
    cwd: ROOT,
    stdio: "pipe",
    env: process.env,
  });
  const afterFirst = await generateFingerprint();

  // Second reset simulates rebuild/upgrade from migrations only
  execSync("npx supabase db reset --yes", {
    cwd: ROOT,
    stdio: "pipe",
    env: process.env,
  });
  const afterSecond = await generateFingerprint();

  const stable = afterFirst.sha256 === afterSecond.sha256;
  return {
    status: stable ? "PASS" : "FAIL",
    detail: stable
      ? `upgrade rehearsal stable across 2 resets; migrations=${migrations.length}`
      : "fingerprint changed between consecutive resets",
    migrations: migrations.map((m) => m.name),
    sha256: afterSecond.sha256,
  };
}

if (process.argv[1]?.endsWith("upgrade-rehearsal.mjs")) {
  runUpgradeRehearsal()
    .then((r) => {
      console.log(JSON.stringify(r, null, 2));
      if (r.status !== "PASS") process.exit(1);
    })
    .catch((e) => {
      console.error(e);
      process.exit(1);
    });
}
