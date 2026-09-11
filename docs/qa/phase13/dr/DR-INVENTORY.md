# Phase 13 DR inventory

**Evidence class in this file:** DOCUMENTED / OBSERVED / INFERRED as marked.  
**No secret values.** Variable names only.

Generated: 2026-09-09 (CONTABILIUM / FINANCE repo)

---

## 1. Topology (OBSERVED + DOCUMENTED)

```
LOCAL disposable Docker (supabase_db_FINANCE)
        │  zero-cost gates, fixtures
        ▼
STAGING project class = staging
  ref (documented): rpcpdrzbcclofvjpgldb
  region (prior OBSERVED): sa-east-1
  READ-ONLY for this DR plan — do not change, dump tenant data, or restore over it
        │
        ▼
DR DRILL PRIMARY (NOT PROVISIONED)
  disposable remote project — future, after cost approval
        │
        ├── DATABASE BACKUP / PITR  (independent)
        └── STORAGE BACKUP          (independent)
                    │
                    ▼
DR RECOVERY TARGET (NOT PROVISIONED)
  separate disposable project or in-place restore of drill primary
  MUST NOT be Staging
  MUST NOT be Production (Production does not exist)
```

Production: **NOT CREATED**. Rehearsal: **NOT CREATED**.

---

## 2. PostgreSQL

| Item | Value | Class |
|------|-------|-------|
| Local major version | 17 (`supabase/config.toml` `[db].major_version`) | DOCUMENTED |
| Local instance | Docker `supabase_db_FINANCE`, port 54322 | OBSERVED (prior session) |
| Staging version | not re-queried in this DR-prep pass | UNPROVEN |
| Public tables (clean-room / staging forensics) | 107 | OBSERVED |
| Schema fingerprint SHA256 | `ca472ea6dc3ccf45d9a49929cc84695fba2bdffb3357080d6bf363a690838cf8` | OBSERVED (`schema-fingerprint.expected.json`) |
| Unexplained schema drift | 0 | OBSERVED |

---

## 3. Migrations

| Item | Value | Class |
|------|-------|-------|
| Repository SQL files | 124 (`supabase/migrations/*.sql`) | OBSERVED |
| Staging history rows (Phase 13D) | 118 | OBSERVED (prior) |
| Local apply count (Phase 13D status) | 122 recorded in status + later hardening | OBSERVED |
| Provenance chain | `docs/qa/phase13/migration-provenance.json` | OBSERVED |
| Immutability | historical files forward-only | DOCUMENTED |

---

## 4. Storage buckets (schema — no tenant listing)

| Bucket | Public | Limit | MIME | Path convention | Classification | Priority |
|--------|--------|-------|------|-----------------|----------------|----------|
| `purchase-evidence` | **false** | 15 MiB | pdf, jpeg, png, webp | `{organization_id}/{purchase_document_id}/{filename}` | **CRITICAL** | P0 |

No other `storage.buckets` inserts exist in recovered migrations.

Staging **object count / size were not queried** in this pass (avoid real-file inventory). Local drill will use synthetic objects only (`DR_FIXTURE_*`).

Database backup **does not** restore Storage bytes (Supabase docs: backups store metadata only). Class: **DOCUMENTED**.

---

## 5. Authentication / application

Auth is GoTrue on the same Supabase project as the DB. Restoring Postgres without Auth schema/`auth.users` breaks login. Physical/PITR restore of the project includes Auth; a `public`-only dump does **not**.

App env variable **names** (no values):

- `APP_ENV`, `NEXT_PUBLIC_APP_ENV`
- `NEXT_PUBLIC_APP_URL`, `NEXT_PUBLIC_APP_NAME`, `NEXT_PUBLIC_APP_SHORT_NAME`, `NEXT_PUBLIC_APP_TAGLINE`
- `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_PROJECT_REF`
- `STAGING_SUPABASE_PROJECT_REF`, `REHEARSAL_SUPABASE_PROJECT_REF`, `PRODUCTION_SUPABASE_PROJECT_REF`
- `ARCA_ENV`, `FISCAL_GATEWAY_ENV`

Fail-closed isolation: `src/config/env.ts`. Recovery app **must** use `APP_ENV=rehearsal` and a drill project ref that is not Staging/Production.

---

## 6. Vercel

No Vercel project is wired in this repository (`package.json` has no Vercel scripts). Application recovery for the drill can use **local Next.js** against the recovery URL. Hosting a Vercel rehearsal is **optional** and unpaid until approved.

---

## 7. External dependencies

| Dependency | DR impact | Class |
|------------|-----------|-------|
| ARCA | Must stay disabled (`ARCA_ENV=disabled`) | DOCUMENTED |
| Banks | Not called | DOCUMENTED |
| Email (local Inbucket) | Not required for RPO/RTO proof | DOCUMENTED |
| OpenAI Studio key | Unused by app runtime | DOCUMENTED |

---

## 8. Backup dependencies (current)

| Environment | DB backup | Storage backup | RPO/RTO |
|-------------|-----------|----------------|---------|
| Local Docker | volume / `db dump` only | local Storage container | **UNPROVEN** for hosted |
| Staging | unknown plan (Free = no daily backups; Pro = daily ≈24h RPO) | none designed | **UNPROVEN** |
| Production | N/A | N/A | N/A |

Daily backups **cannot** meet RPO ≤ 5 minutes (DOCUMENTED: up to ~1 day of loss). PITR WAL archive interval is **DOCUMENTED** as worst-case ~2 minutes — **not MEASURED**.

---

## 9. Recovery scope (must survive)

**Database:** organizations, memberships, branches, entitlements, counterparties, products, sales, purchases, treasury, inventory, accounting, taxes, dashboard/reporting configuration, audit metadata, fiscal **metadata** (not ARCA live authorizations).

**Storage:** `purchase-evidence` objects for the synthetic tenant.

**Auth:** users that own the synthetic org.

**App:** env pointing at recovery project; RLS/DEFINER contracts intact.

---

## 10. Future Production (not provisioned)

Separate project, separate secrets, `APP_ENV=production`, `ARCA_ENV` still blocked until homologation. DR architecture for Production would copy this drill pattern **after** the disposable drill PASSes.
