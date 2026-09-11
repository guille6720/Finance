# DR resume plan (NOT EXECUTED)

**Status:** documentation only. Do not run until explicit future authorization.

The previous disposable primary `yqqqocmbuxgagounywtp` was intentionally deleted.
It **cannot** be assumed restorable. Resume requires a **new** disposable project.

## Preconditions

- `DR_GATE = NOT_RUN` today
- `T3_PITR_ACTIVE = DEFERRED`
- Staging `rpcpdrzbcclofvjpgldb` remains untouched
- Production remains NOT_AUTHORIZED
- ARCA remains BLOCKED_PENDING
- Cost approval required again before any paid resource (project / Small / PITR)

## Future sequence (after explicit authorization)

1. Recreate disposable DR primary in org `qsgnqyleasarodfwzlwe` (not Staging).
2. Verify isolation from Staging (`DR_PRIMARY_ISOLATED = PASS`).
3. Rebuild canonical 107-table schema via migration history.
4. Load deterministic `DR_FIXTURE_*` dataset (synthetic only).
5. Revalidate T0–T2 gates against the new primary.
6. Request/confirm cost approval (max budget stated by user).
7. Enable Compute **Small** + **PITR 7-day** only.
8. Continue from T3 (post-recovery-point writes).
9. Execute isolated restore-to-new-project (Option B).
10. Measure RPO/RTO against targets (≤5m / ≤240m).
11. Cleanup disposable resources; retain sanitized evidence only.

## Forbidden without new authorization

- Enabling PITR now
- Continuing T3–T13 now
- Creating Production
- Touching Staging
- Enabling ARCA / FECAESolicitar
