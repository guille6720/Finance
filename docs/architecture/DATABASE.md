# Database — Phase 1

Migrations live in `supabase/migrations/`. Apply to each environment independently.

## Tables

| Table | Purpose |
|-------|---------|
| `profiles` | App profile linked to `auth.users` |
| `organizations` | Tenant / legal entity |
| `organization_members` | Membership + role |
| `branches` | Locations |
| `fiscal_conditions` | Catalog (business + accountant labels) |
| `fiscal_profiles` | Org fiscal data |
| `business_profiles` | Onboarding answers |
| `accounting_periods` | Period structure (no posting) |
| `cost_centers` | Cost center structure |
| `feature_catalog` | Module definitions |
| `organization_features` | Per-org entitlement status |
| `app_settings` | Global platform settings |
| `organization_settings` | Per-org settings |
| `audit_events` | Append-only audit trail |

## Conventions

- UUID primary keys
- `created_at` / `updated_at` (UTC)
- CUIT stored as 11 digits (`organizations_cuit_format`)
- Neutral names only (no brand strings)

## Audit immutability

`audit_events` has triggers blocking UPDATE and DELETE. Client roles have INSERT + SELECT only (no update/delete policies).

## Reproducibility

1. Create empty Supabase project
2. Run `20260329000001_phase1_foundation.sql`
3. Confirm catalog seed rows for features and fiscal conditions
