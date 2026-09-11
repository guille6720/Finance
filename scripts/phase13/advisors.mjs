#!/usr/bin/env node
/**
 * Staging Security / Performance Advisor gates.
 * Prefer local SQL equivalents when no staging project is configured.
 * Never creates paid remote resources.
 */
import { withDb } from "./db.mjs";

export async function runSecurityAdvisor() {
  return withDb(async (client) => {
    const findings = [];

    const { rows: noRls } = await client.query(`
      select c.relname as table_name
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname='public' and c.relkind='r' and c.relrowsecurity = false
    `);
    for (const r of noRls) {
      findings.push({ level: "ERROR", id: `rls_disabled:${r.table_name}` });
    }

    const { rows: definer } = await client.query(`
      select p.proname as name,
             pg_get_function_identity_arguments(p.oid) as args,
             coalesce(p.proconfig, array[]::text[]) as config
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname='public' and p.prosecdef = true
    `);
    for (const f of definer) {
      const pinned = (f.config || []).some((c) =>
        String(c).toLowerCase().includes("search_path")
      );
      if (!pinned) {
        findings.push({
          level: "ERROR",
          id: `security_definer_search_path:${f.name}(${f.args})`,
        });
      }
    }

    const remote = process.env.STAGING_SUPABASE_PROJECT_REF;
    return {
      status: findings.length === 0 ? "PASS" : "FAIL",
      mode: remote ? "local_equivalent+staging_ref_present" : "local_equivalent",
      detail:
        findings.length === 0
          ? "no security advisor ERROR findings on local disposable DB"
          : `${findings.length} findings`,
      findings,
      note: remote
        ? "Staging project ref present in env; dashboard Advisor UI not auto-called (no paid API)."
        : "No staging project configured; local SQL advisor equivalent executed only.",
    };
  });
}

export async function runPerformanceAdvisor() {
  return withDb(async (client) => {
    const findings = [];

    const { rows: unindexedFks } = await client.query(`
      select c.conrelid::regclass::text as table_name,
             a.attname as column_name
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
      where c.contype = 'f'
        and c.connamespace = 'public'::regnamespace
        and not exists (
          select 1 from pg_index i
          where i.indrelid = c.conrelid
            and a.attnum = any (i.indkey)
        )
    `);
    for (const r of unindexedFks) {
      findings.push({
        level: "WARN",
        id: `fk_without_index:${r.table_name}.${r.column_name}`,
      });
    }

    // WARN does not fail the gate unless PHASE13_ADVISOR_STRICT=1
    const errors = findings.filter((f) => f.level === "ERROR");
    const strict = process.env.PHASE13_ADVISOR_STRICT === "1";
    const fail = errors.length > 0 || (strict && findings.length > 0);

    return {
      status: fail ? "FAIL" : "PASS",
      mode: "local_equivalent",
      detail: `findings=${findings.length}; errors=${errors.length}`,
      findings,
    };
  });
}

if (process.argv[1]?.endsWith("advisors.mjs")) {
  const [sec, perf] = await Promise.all([
    runSecurityAdvisor(),
    runPerformanceAdvisor(),
  ]);
  console.log(JSON.stringify({ security: sec, performance: perf }, null, 2));
  if (sec.status !== "PASS" || perf.status !== "PASS") process.exit(1);
}
