# Operations runbook — Phase 13 (local/staging)

## Scope

This runbook covers **local disposable Supabase** and **staging**. It does **not** authorize Production actions.

## Local stack

```bash
npx supabase start
npx supabase status -o env
npm run test:db:phase13:cleanroom
```

Stop:

```bash
npx supabase stop
```

## Incident classes

### RLS / cross-tenant suspicion

1. Do not rotate Production keys from this runbook.
2. On staging/local: reproduce with `npm run test:db:phase13:cross-tenant`.
3. Capture offending policy/function from `docs/qa/phase13/SECURITY-DEFINER-REGISTRY.md`.
4. Ship fix via new migration; re-run clean-room.

### Migration failure

1. `npx supabase db reset --yes` on local only.
2. Inspect failing SQL; never `--force` against remote paid projects from this doc.
3. Re-run provenance + fingerprint gates.

### Capacity degradation

1. Re-run k6 progressive stages (`npm run test:db:phase13:k6`).
2. Record VERIFIED_*_CAPACITY as highest PASS only.
3. Review `pg_stat_statements` via `npm run test:db:phase13:pgstat`.

### Data loss / restore

DB + Storage restore drills that prove RPO/RTO require approved resources
(remote disposable project and/or PITR / backup provider). See COST_APPROVAL_REQUIRED
in Phase 13 status. **Do not provision paid resources from this runbook.**

## Contacts

Fill staging on-call roster before staging soak. No Production contacts in this file until DR proven.
