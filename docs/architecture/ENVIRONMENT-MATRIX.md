# Environment topology (Phase 14)

```
LOCAL (disposable)
  → STAGING (connected project, read/write only with explicit local/staging work)
    → REHEARSAL (future, unpaid until authorized)
      → PRODUCTION (FUTURE ONLY — not provisioned)
```

Production is **not authorized**. Phase 13 RPO/RTO remain **UNPROVEN**.

## Matrix

| Field | LOCAL | STAGING | REHEARSAL | PRODUCTION |
|-------|-------|---------|-----------|------------|
| Class | disposable Docker | existing Staging SA | future isolated project | **NOT CREATED** |
| App URL | `http://127.0.0.1:3000` | staging hostname TBD | rehearsal hostname TBD | **forbidden** |
| Supabase ref | local (`127.0.0.1:54321`) | `rpcpdrzbcclofvjpgldb` (placeholder class: staging) | `REHEARSAL_SUPABASE_PROJECT_REF` | `PRODUCTION_SUPABASE_PROJECT_REF` (unset) |
| Database | local Postgres `:54322` | Staging Postgres (no Phase 14 DDL from this repo gate) | future | **not provisioned** |
| Storage | local | staging buckets | future | **not provisioned** |
| Auth | local GoTrue demo keys | staging Auth | future | **not provisioned** |
| Secrets | `.env.local` only | staging vault | future | **must not appear in local/staging** |
| ARCA | `disabled` | `homologation` only | `homologation` | **blocked** |
| Observability | health + correlation id | same + future remote | future | **not claimed** |
| Backup | local volumes (not RPO/RTO) | Staging native (unproven RPO/RTO) | future | **COST_APPROVAL_REQUIRED** |
| Deploy branch | working tree | `main` candidate | release tag | **not deployed** |
| Domain | localhost | staging domain TBD | rehearsal domain TBD | **not configured** |

## Fail-closed combinations

Implemented in `src/config/env.ts` (startup throws):

- Production app + Staging database
- Staging/local/rehearsal app + ARCA Production
- Local app + Production project URL/secrets
- Production app + localhost DB or local demo JWT
- Shared project ref across staging/rehearsal/production
- Any `ARCA_ENV=production` (Phase 5 homologation pending)

## Isolation rule

No environment may silently inherit another environment’s URL, keys, or ARCA target.
