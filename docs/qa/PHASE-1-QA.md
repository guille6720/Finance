# Phase 1 QA checklist

## Automated

- [ ] `npm run typecheck`
- [ ] `npm run lint`
- [ ] `npm run test`
- [ ] `npm run build`
- [ ] `npm run test:e2e` (public paths; auth path if `E2E_*` set)

## Security

- [ ] Migration applied on **staging** only first
- [ ] RLS smoke: `supabase/tests/rls_isolation.sql`
- [ ] User A cannot read/update org B
- [ ] Viewer cannot mutate
- [ ] Operator cannot perform owner-only actions
- [ ] Service role key absent from client bundle
- [ ] Staging and production project refs differ

## Product

- [ ] Onboarding 7 steps complete end-to-end on staging
- [ ] Dashboard shows setup completeness (no fake money)
- [ ] Coming soon modules do not pretend to work
- [ ] Light mode readable
- [ ] Dark mode readable (tables, inputs, placeholders, buttons)
- [ ] Mobile sidebar works
- [ ] Keyboard focus visible

## Docs

- [ ] Architecture docs present
- [ ] LEGAL-GATES present and honest
- [ ] Roadmap present; Phase 2 not started automatically
