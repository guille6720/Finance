# Incident response — Phase 14 (non-production)

Production is **not authorized**. Do not create Production, enable PITR, or provision paid resources from this runbook.

## Severity

| Sev | Meaning | Detection | Containment | Rollback | Recovery | Validation | Communication | Postmortem |
|-----|---------|-----------|-------------|----------|----------|------------|---------------|------------|
| **P0** | Security / cross-tenant / data integrity / system unavailable | Cross-tenant matrix fail, unexpected authz, health down | Stop soak; revoke leaked grants; disable feature flags | App rollback N (DB forward-fix only) | Restore from authorized backup **only if** COST_APPROVAL | Re-run DEFINER + cross-tenant + fingerprint | Notify staging owners immediately | Required within 5 business days |
| **P1** | Critical business flow unavailable (post/sale/purchase/treasury/inventory/tax calc) | Golden flow / posting errors / 5xx on RPCs | Feature disable via Phase 12 entitlements | Forward correction migration | Replay synthetic fixtures | `PILOT_GOLDEN_FLOWS` | Staging on-call | Required |
| **P2** | Degraded / non-critical | p95 drift, dashboard miss, POS cosmetic | Lower claimed capacity; no Production action | N/A | Tune indexes / queries | k6 regression | Async | Optional |

## Triage

1. Confirm environment (`APP_ENV`). If Production variables are present → **stop** (misconfiguration).
2. Capture `x-correlation-id` from the failing request.
3. Do not paste tokens, passwords, or fiscal document payloads into tickets.

## Forbidden

- Accessing Production
- Creating Production
- Enabling PITR
- Creating paid Supabase branches/projects without COST_APPROVAL
- Calling ARCA production or bank APIs
- Using real customer / accounting / fiscal data
- Weakening RLS to “fix” an incident

## Validation commands

```bash
npm run test:db:phase13:cross-tenant
npm run test:db:phase13:security-definer
npm run test:db:phase13:deep-authz
npm run test:db:phase14:pre-pilot
```
