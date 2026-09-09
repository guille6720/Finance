# Platform foundation (Phase 1)

Modular accounting and business management SaaS for Argentina.

> **Philosophy:** The user manages the business. The platform handles the accounting underneath.

> **Legal:** This software does **not** claim fiscal, accounting, or privacy compliance by itself. See `docs/compliance/LEGAL-GATES.md`.

## Stack

| Layer | Choice |
|-------|--------|
| App | Next.js 16 (App Router), React 19, TypeScript strict |
| UI | Tailwind CSS 4 + Radix primitives |
| Auth / DB | Supabase Auth + PostgreSQL + RLS |
| Validation | Zod |
| Unit tests | Vitest |
| E2E | Playwright |
| Deploy | Vercel (recommended) |

## Branding

Product name is **not** hardcoded in business logic. Configure via:

```env
NEXT_PUBLIC_APP_NAME=...
NEXT_PUBLIC_APP_SHORT_NAME=...
```

Central config: `src/config/brand.ts`

Place temporary logos in:

- `public/brand/logo-dark.png`
- `public/brand/logo-light.png`

Never put the product name in table names, API routes, or IDs.

## Environments

| Env | Purpose |
|-----|---------|
| local | Developer machine |
| staging | Shared QA — **own** Supabase project |
| production | Live — **different** Supabase project |

Copy `.env.example` → `.env.local` and fill Supabase keys.

Environment validation rejects staging/production project mix-ups (`src/config/env.ts`).

**Never** expose `SUPABASE_SERVICE_ROLE_KEY` to the browser.

## Setup

```bash
npm install
cp .env.example .env.local
# Fill NEXT_PUBLIC_SUPABASE_URL and keys

# Apply SQL migration in Supabase SQL editor or CLI:
# supabase/migrations/20260329000001_phase1_foundation.sql

npm run dev
```

## Scripts

| Command | Description |
|---------|-------------|
| `npm run dev` | Dev server |
| `npm run typecheck` | TypeScript |
| `npm run lint` | ESLint |
| `npm run test` | Vitest |
| `npm run test:e2e` | Playwright |
| `npm run build` | Production build |
| `npm run qa` | typecheck + lint + test + build |

## Phase 1 scope

Included: multi-tenant orgs, auth, RLS, roles, onboarding, shell, feature catalog, audit trail, docs, tests.

**Not** included: sales, purchases, ARCA, journal posting, inventory, POS, payroll.

See `docs/roadmap/ROADMAP.md`.

## Documentation

- `docs/architecture/OVERVIEW.md`
- `docs/architecture/DATABASE.md`
- `docs/architecture/MULTI-TENANCY.md`
- `docs/architecture/ACCOUNTING-CORE.md`
- `docs/architecture/FISCAL-GATEWAY.md`
- `docs/architecture/MODULE-SYSTEM.md`
- `docs/compliance/LEGAL-GATES.md`
- `docs/qa/PHASE-1-QA.md`
