# Phase 13 DR architecture (plan only — not provisioned)

Evidence: **DOCUMENTED** design. Nothing in this file is MEASURED.

## Why two backup paths

Supabase physical/daily/PITR backups restore **Postgres** (including `auth` if the whole project is restored). They do **not** restore Storage object bytes. Metadata in `storage.objects` without files is a failed restore.

```
DR_PRIMARY (disposable remote, AFTER approval)
   |
   +-- PostgreSQL PITR (or 5-min logical dump — see cost options)
   |        restore --> DR_RECOVERY_DB
   |
   +-- Storage object copy (bucket dump / S3)
            restore --> DR_RECOVERY_STORAGE

DR_RECOVERY must be isolated:
  APP_ENV=rehearsal
  REHEARSAL_SUPABASE_PROJECT_REF=<drill>
  STAGING_SUPABASE_PROJECT_REF=rpcpdrzbcclofvjpgldb
  PRODUCTION_SUPABASE_PROJECT_REF unset
```

Never restore onto Staging. Never create Production as the recovery target.

## Minimum architecture to *attempt* RPO ≤ 5 min and RTO ≤ 4 h

| Path | Mechanism | Why |
|------|-----------|-----|
| Database | **PITR 7-day add-on** on a **disposable Pro** project with **Small** compute (PITR prerequisite) | Daily backups cannot meet 5 min RPO. Free plan has no automatic backups. |
| Storage | Independent copy of `purchase-evidence` (CLI `storage` download/upload or S3) every ≤ 5 min during the drill window, or immediately after each fixture write | DB restore alone is insufficient |
| App | Local Next.js (`npm run start` or `dev`) with rehearsal env | Avoids Vercel cost; still proves Auth + PostgREST + Storage |
| Isolation | Fail-closed env guards | Prevents recovery app from using Staging URL |

### Alternative (no PITR)

Logical `pg_dump` / `supabase db dump` every 5 minutes to off-site storage. Can **measure** RPO as dump lag. Does **not** exercise provider PITR. Still requires a paid or Free remote project if the claim is hosted recoverability. Free project pause/no backups make this a poor Production analogue.

**Recommendation for the target:** Option PITR on disposable Pro (not Staging).

## What local Docker can and cannot prove

| Local volume snapshot + fixture | Hosted PITR + Storage copy |
|--------------------------------|----------------------------|
| Zero cost | Creates charges |
| Can rehearse runbook steps | Required for PHASE_13 COMPLETE |

Local-only restore **must not** be used to mark `MEASURED_RPO` / `MEASURED_RTO` as PASS for Phase 13 completion.
