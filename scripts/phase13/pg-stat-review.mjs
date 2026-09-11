#!/usr/bin/env node
import { withDb } from "./db.mjs";

export async function runPgStatReview() {
  return withDb(async (client) => {
    const ext = await client.query(
      `select exists(select 1 from pg_extension where extname='pg_stat_statements') as ok`
    );
    if (!ext.rows[0].ok) {
      return {
        status: "FAIL",
        detail: "pg_stat_statements extension missing",
        top: [],
      };
    }

    const { rows } = await client.query(`
      select queryid::text,
             left(query, 160) as query,
             calls,
             round(total_exec_time::numeric, 2) as total_ms,
             round(mean_exec_time::numeric, 2) as mean_ms
      from pg_stat_statements
      where query not ilike '%pg_stat_statements%'
      order by total_exec_time desc
      limit 15
    `);

    return {
      status: "PASS",
      detail: `reviewed top ${rows.length} statements by total_exec_time`,
      top: rows,
    };
  });
}

export async function runLocksReview() {
  return withDb(async (client) => {
    const locks = await client.query(`
      select count(*)::int as lock_count
      from pg_locks
      where NOT granted
    `);
    const blocked = await client.query(`
      select count(*)::int as blocked
      from pg_stat_activity
      where wait_event_type = 'Lock'
    `);
    const deadlocks = await client.query(`
      select deadlocks from pg_stat_database where datname = current_database()
    `);

    const waiting = locks.rows[0].lock_count;
    const blockedN = blocked.rows[0].blocked;
    const deadlockN = Number(deadlocks.rows[0].deadlocks || 0);

    return {
      status: waiting === 0 && blockedN === 0 ? "PASS" : "FAIL",
      detail: `ungranted_locks=${waiting}; blocked=${blockedN}; deadlocks_counter=${deadlockN}`,
      ungranted_locks: waiting,
      blocked: blockedN,
      deadlocks: deadlockN,
    };
  });
}

if (process.argv[1]?.endsWith("pg-stat-review.mjs")) {
  runPgStatReview()
    .then((r) => {
      console.log(JSON.stringify(r, null, 2));
      if (r.status !== "PASS") process.exit(1);
    })
    .catch((e) => {
      console.error(e);
      process.exit(1);
    });
}
