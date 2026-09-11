# Expand / Migrate / Contract

Historical migrations are **immutable**. Fixes are **forward-only**.

## Strategy

1. **EXPAND** — add nullable columns, new tables, new RPCs, new indexes. Old app keeps working.
2. **MIGRATE** — backfill and dual-write. Deploy app that reads new + old.
3. **CONTRACT** — only after old app is gone: drop unused columns/tables in a **new** forward migration that cites this document (`EXPAND-MIGRATE-CONTRACT`).

## Coordinated deployments

A migration requires coordinated app+DB deploy when it:

- renames a column used by PostgREST
- changes RPC argument names
- removes a grant that the previous app bundle still needs

Phase 14 compatibility gate checks that Phase 1 columns still exist (`old app + new DB`).

## Forbidden

- Automatic down/rollback SQL that drops tenant data
- Destructive schema deploy without an EMC plan in the migration comments
