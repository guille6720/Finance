# Pilot SLO targets (not production compliance)

These targets apply to a **future controlled pilot** on an authorized environment.
Local/k6 numbers from Phase 13 are **regression signals**, not production SLO proof.

| SLO | Pilot target | How we will measure | Local evidence |
|-----|--------------|---------------------|----------------|
| Availability | 99.0% monthly (pilot) | HTTP 5xx / health | Not claimed |
| API latency | p95 < 3s read; p95 < 4s write | k6 + future APM | Phase 13 APP k6 p95 well under local |
| Transaction success | ≥ 99% of posted journals/inventory/treasury | failed posting counters | Golden flow PASS locally |
| Auth success | ≥ 99% password grant for valid users | Auth error rate | Local Auth used in gates |
| Critical-op failure | < 1% post/reverse/tax calc | domain error logs | Golden + idempotency PASS |

## Explicit non-claims

- Do **not** claim production SLO compliance from local tests.
- Do **not** use Phase 13 capacity (250 VUs local) as a production capacity rating.

## Alert → runbook

| Signal | Runbook |
|--------|---------|
| HTTP 5xx burst | `docs/ops/INCIDENT-RESPONSE.md` P1 |
| Auth errors | P1 |
| DB locks / saturation | `docs/ops/RUNBOOK.md` capacity |
| Failed accounting/inventory/tax | P1 critical flow |
| Cross-tenant / authz surprise | P0 |
| Fiscal/ARCA errors | P2 (ARCA remains disabled) |
