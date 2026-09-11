# Release manifest — Phase 13 (local/staging)

## Identity

| Field | Value |
|-------|-------|
| Product phase shipped in schema | 1 (+ Phase 13 hardening migration) |
| Environments allowed without extra approval | local, staging |
| Production | FORBIDDEN until Phase 13 DR proven + explicit approval |

## Artifacts

| Artifact | Path |
|----------|------|
| Migrations | `supabase/migrations/*.sql` |
| Reference seeds | `supabase/seed.sql` |
| Migration provenance | `docs/qa/phase13/migration-provenance.json` |
| Schema fingerprint | `docs/qa/phase13/schema-fingerprint.expected.json` |
| SECURITY DEFINER registry | `docs/qa/phase13/SECURITY-DEFINER-REGISTRY.md` |
| Clean-room runner | `scripts/phase13/cleanroom.mjs` |
| Zero-cost suite | `scripts/phase13/run-zero-cost.mjs` |
| k6 workloads | `tests/k6/{read,write,mixed}.js` |

## Pre-release checklist (staging/local)

- [ ] `npm run test:db:phase13:cleanroom` → CLEAN-ROOM REBUILD PASS
- [ ] SECURITY DEFINER deep audit → UNEXPLAINED = 0
- [ ] Cross-tenant A/B × roles matrix PASS
- [ ] k6 capacities recorded (no claim beyond highest PASS)
- [ ] Release manifest verification PASS
- [ ] Incident/runbook validation PASS
- [ ] Full regression PASS
- [ ] DR restore drills (DB + Storage) — **NOT proven by this document alone**

## Explicit non-claims

- RPO ≤ 5 minutes — **unproven** until restore drill
- RTO ≤ 4 hours — **unproven** until restore drill
- Phases 2–12 — recovered in repo as of Phase 13D; still **not Production-authorized**
- ARCA / bank APIs — **not called** in Phase 13 local gates
