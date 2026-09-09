# Module / feature system

## Tables

- `feature_catalog` — platform module definitions
- `organization_features` — per-org status: `enabled` | `disabled` | `restricted`

## Independence from billing

Entitlements are **not** tied to subscription plans in Phase 1. Billing can later map plans → feature sets without changing UI checks.

## UI rules

- Enabled → usable route/actions
- Disabled / restricted → “Próximamente” or hidden
- Never fake working modules

## Catalog (seeded)

dashboard, sales, purchases, customers, suppliers, cash, banks, inventory, pos, accounting, taxes, payroll, projects, assets, reports, medical_legal

## Medical-legal note

`medical_legal` defaults to `restricted`. Health data must use a separate security domain in a later phase — not the accounting core.
