# Legal / compliance gates (Argentina)

Software tests **cannot** replace accountant, tax specialist, or legal review where required.

Status values:

- `NOT_STARTED`
- `REVIEW_REQUIRED`
- `APPROVED_FOR_STAGING`
- `APPROVED_FOR_PRODUCTION`

| Domain | Status | Notes |
|--------|--------|-------|
| PERSONAL DATA | REVIEW_REQUIRED | Profiles, emails, membership — privacy review before production |
| FISCAL DATA | REVIEW_REQUIRED | CUIT, fiscal profiles — specialist review before production fiscal claims |
| ELECTRONIC INVOICING | NOT_STARTED | ARCA / Fiscal Gateway not implemented |
| ACCOUNTING RECORDS | NOT_STARTED | Posting engine not implemented |
| TAX CALCULATIONS | NOT_STARTED | No tax engine in Phase 1 |
| PAYROLL | NOT_STARTED | Module catalog only |
| HEALTH DATA | NOT_STARTED | Explicitly out of accounting core; future separate domain |
| SUBSCRIPTIONS / CONSUMER RULES | NOT_STARTED | No billing yet |

## Rules

1. Do not mark `APPROVED_FOR_PRODUCTION` without documented human approval.
2. Staging approval does not imply production approval.
3. Marketing copy must not claim legal/fiscal compliance automatically.
