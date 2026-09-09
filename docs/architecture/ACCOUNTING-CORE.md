# Accounting core (future) — preparation only

Phase 1 does **not** implement posting. This document locks design rules so Phase 2 does not require rewrites.

## Future entities

- Chart of accounts (`accounts`)
- Journal entries (`journal_entries`)
- Journal lines (`journal_lines`)
- Accounting periods (already seeded structurally)
- Cost centers (already seeded structurally)

## Hard rules (Phase 2+)

1. **Posted entries are immutable.** No silent edit or delete.
2. Corrections use **controlled reversals / rectifications**.
3. Every posting emits an audit event.
4. Automatic posting from operational modules (sales, purchases, cash) goes through a single posting service.
5. Business Mode never requires users to understand debit/credit; Accountant Mode may show traditional terminology.

## Automatic posting (future)

```
Operational event (e.g. sale recorded)
        ↓
Posting service (idempotent)
        ↓
journal_entries (posted) + journal_lines
        ↓
audit_events
```

## Periods

Closing a period must freeze posting into that period. Reopening is an audited, privileged action.

## Separation

Accounting core must not import ARCA UI code. Fiscal authorization is a separate Fiscal Gateway.
