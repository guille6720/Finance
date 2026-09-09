# Architecture overview — Phase 1

## Product principle

Business Mode (default) speaks plain Spanish. Accountant Mode exists as a UX toggle for future advanced terminology. Posted accounting is **not** implemented in Phase 1.

## System shape

```
Browser (Next.js App Router)
    │
    ├─ Supabase Auth (session cookies via @supabase/ssr)
    ├─ Server Components / Server Actions
    └─ PostgreSQL via Supabase (RLS enforced)
```

## Bounded contexts (Phase 1)

| Context | Responsibility |
|---------|----------------|
| Identity | `profiles`, Supabase Auth |
| Tenancy | `organizations`, `organization_members`, branches |
| Onboarding | `business_profiles`, `fiscal_profiles` |
| Entitlements | `feature_catalog`, `organization_features` |
| Audit | append-only `audit_events` |
| Prep | `accounting_periods`, `cost_centers` (structure only) |

## Authorization

Centralized in `src/lib/authz`. Components must not scatter permission checks.

Order of enforcement:

1. Authenticate user
2. Resolve active organization membership (RLS + server)
3. Assert permission for the action

## Environments

LOCAL / STAGING / PRODUCTION. Staging and production never share a Supabase database. Validated in `src/config/env.ts`.

## Non-goals (Phase 1)

- Journal entries / chart of accounts posting
- ARCA electronic invoicing
- Health record storage
- Billing plans
- Mock security bypasses
