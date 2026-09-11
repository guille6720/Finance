# Phase 5 — Accounting post exactly once

STAGING / TESTS ONLY. No ARCA Production. No live FECAESolicitar / FEComp* / WSAA in this gate.

## Deliverables

| Artifact | Path |
| --- | --- |
| Migration | `supabase/migrations/20260501210000_phase5_fiscal_accounting_post_once.sql` |
| App gate + simulator | `src/lib/fiscal/accounting/post-once.ts` |
| Unit / integration tests | `tests/unit/fiscal/accounting-post-once.test.ts` |
| Evidence JSON | `docs/qa/phase5/ARCA-ACCOUNTING-POST-ONCE.json` |

## Semantics

- Accounting posts **only** when fiscal application state is `AUTHORIZED` or `AUTHORIZED_RECONCILED` (DB status `AUTHORIZED` after APPROVED or RECONCILED_AUTHORIZED).
- Blocked: DRAFT, READY*, AUTHORIZING, REJECTED, RECONCILIATION_REQUIRED, UNCERTAIN_STOP, STOP_*, ERROR.
- Source key: `(organization_id, fiscal_document_id, event=ARCA_AUTHORIZED)` in `fiscal_accounting_post_keys` + unique SALE `(organization_id, source_type, source_id)` on `journal_entries`.
- Atomic path: lock fiscal doc → idempotency check → DRAFT journal + lines → `post_journal_entry` → link + `accounting_posted_at`. DRAFT deleted on post failure.
- Immutability: posted journals unchanged; corrections via `reverse_journal_entry`. Economic reporting keeps original + reversal (POSTED + REVERSED).

## Evidence

See `ARCA-ACCOUNTING-POST-ONCE.json`.

## Live ARCA

`ARCA_LIVE_CALLS = NOT_RUN`  
`ARCA_PRODUCTION = NOT_AUTHORIZED`
