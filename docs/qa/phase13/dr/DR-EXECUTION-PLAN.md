# DR execution plan (NOT EXECUTED)

**Status:** READY as procedure. **COST_APPROVAL_REQUIRED = YES.**
Do not run until the user authorizes **OPTION B** and a **MAXIMUM TOTAL DR BUDGET IN USD**.

Forbidden until then: create project, enable PITR, Small compute, restore destination, paid Storage, Vercel, Production, ARCA.

---

## Sequence (after approval only)

| Step | Action | Clock |
|------|--------|-------|
| T0 | Create DR primary in org `qsgnqyleasarodfwzlwe` (not Staging). Enable Small. Enable PITR 7-day. Wait until PITR restore window is non-empty. | |
| T1 | Record PITR latest restore point = backup confirmed. | T0 backup |
| T2 | Load synthetic tenant (`DR_FIXTURE_*`) + write `organization_settings.dr.rpo_probe`. | T1 critical write |
| T3 | Upload synthetic `application/pdf` to `purchase-evidence` (bucket allowlist rejects text/plain). Copy bytes locally. Record size + sha256. | |
| T4 | Declare simulated disaster of **DR primary** (not Staging). | **T_DISASTER** — start RTO |
| T5 | Restore to **new** disposable project (Dashboard restore-to-new-project / PITR). | |
| T6 | Wait until Postgres+Auth on recovery project accept connections. Validate schema. | |
| T7 | Create `purchase-evidence` bucket on target; upload independent Storage copy; verify hash/size/ACL. | |
| T8 | Local app `APP_ENV=rehearsal`, recovery URL, Staging ref listed only as forbidden peer. | |
| T9 | Auth login + health + PostgREST. | |
| T10 | DEFINER, deep authz, cross-tenant 19/19, storage isolation. | |
| T11 | Journal 1000 ARS, inventory 10 IN, tax period, audit, idempotency — no fake corrective rows. | |
| T12 | Golden Flow. No FECAESolicitar. | |
| T13 | Smoke READ/WRITE/MIXED. Set **T_SERVICE_RECOVERED**. | |

```
MEASURED_RTO_MINUTES = T_SERVICE_RECOVERED - T_DISASTER
MEASURED_RPO_MINUTES = latest_committed_source_ts - latest_recovered_probe_ts
RPO_TARGET_PASS = MEASURED_RPO_MINUTES <= 5
RTO_TARGET_PASS = MEASURED_RTO_MINUTES <= 240
```

Then cleanup per `DR-RESOURCE-CLEANUP-PLAN.md`.

ARCA remains `BLOCKED_PENDING`. Production remains **NOT_AUTHORIZED**. Success ⇒ `PHASE_13 = COMPLETE` and `READY_FOR_CONTROLLED_PILOT_REVIEW = YES` only — **not** public launch.
