# Disaster recovery runbook — CONTABILIUM

Audience: a second engineer. **No secret values.**

Production is **not authorized**. Staging must **not** be the restore target. ARCA stays **disabled**.

Paid steps require **explicit cost approval** first (`docs/qa/phase13/dr/DR-COST-ESTIMATE.md`).

---

## 0. Preconditions

- [ ] Cost option A or B approved in writing
- [ ] Drill project refs recorded (not Staging `rpcpdrzbcclofvjpgldb`)
- [ ] `APP_ENV=rehearsal` for recovery app
- [ ] Synthetic fixtures only (`DR_FIXTURE_*`)
- [ ] Spend cap reviewed; PITR may bill outside cap

---

## 1. Disaster declaration

Record `T_DISASTER` UTC in `DR-TIMELINE.json`.
State: DATABASE LOSS + STORAGE LOSS of **drill primary** (not Staging).

## 2. Containment

- Freeze writes to drill primary (pause API keys / enable read-only if available).
- Do not rotate Staging or Production secrets.
- Do not “fix” by pointing the app at Staging.

## 3. Identify recovery point

- PITR: earliest/latest restore points in Dashboard (Database → Backups / PITR).
- Record chosen `recovery_time_target` as T0 if restoring to pre-T1, or post-T1 if proving capture of the probe.
- Storage: identify last successful object copy timestamp independently.

## 4. Restore database

- Restore PITR **to the disposable recovery project** (or in-place on drill primary if option A).
- **Never** restore onto Staging.
- Validate: schema fingerprint, migration history, functions, RLS, grants, sequences, extensions, synthetic rows.
- Write `DR-DATABASE-RESTORE.json` (OBSERVED).

## 5. Restore storage

- Re-upload `purchase-evidence` objects from the independent copy.
- Confirm path `{org}/{doc}/DR_FIXTURE_PURCHASE_EVIDENCE.txt`, size, sha256, private bucket, RLS.
- Write `DR-STORAGE-RESTORE.json`. DB restore alone is **FAIL**.

## 6. Restore secrets/config

Set **names** only on the recovery app:

`APP_ENV=rehearsal`
`NEXT_PUBLIC_SUPABASE_URL` → recovery project
`NEXT_PUBLIC_SUPABASE_ANON_KEY`
`SUPABASE_SERVICE_ROLE_KEY` (server)
`REHEARSAL_SUPABASE_PROJECT_REF`
`STAGING_SUPABASE_PROJECT_REF=rpcpdrzbcclofvjpgldb`
`ARCA_ENV=disabled`

Startup must fail if URL contains Staging/Production refs incorrectly (`src/config/env.ts`).

## 7. Application deployment

Local: `npm run build && npm run start` against recovery URL.
Vercel optional and unpaid unless approved.

## 8. Security verification

```
npm run test:db:phase13:security-definer
npm run test:db:phase13:deep-authz
npm run test:db:phase13:cross-tenant
```

Required: CROSS_TENANT 19/19, DEFINER unexplained = 0.

## 9. Data integrity

Compare `DR-FIXTURE-MANIFEST.json`: journal 1000 ARS, inventory 10 IN, tax period present, audit lineage, idempotency keys.

## 10. Golden Flow

```
npm run test:db:phase13:golden
```

No ARCA `FECAESolicitar`.

## 11. Reopen service

Only the **drill** app. Record `T_SERVICE_RECOVERED`.
Do not reopen Production (does not exist). Do not cut Staging over.

## 12. Communication

Internal: drill complete, MEASURED_RPO_MINUTES, MEASURED_RTO_MINUTES.
No customer notification (synthetic).

## 13. Postmortem

Bottleneck class if fail: BACKUP_FREQUENCY | DATABASE_RESTORE | STORAGE_BACKUP | STORAGE_RESTORE | AUTH | DNS | APP_DEPLOY | MIGRATIONS | SECRETS | MANUAL_PROCEDURE | NETWORK | COMPUTE | OTHER

Do **not** buy more capacity without a new approval.

## 14. Teardown

Disable PITR, delete disposable projects, delete S3 prefix, rotate drill keys. Keep evidence JSON.
