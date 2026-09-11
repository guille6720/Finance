# Phase 13 status

**STATUS: PHASE 13D COMPLETE — ZERO_COST_PHASE13_GATES = PASS**

Updated: **2026-09-09 Phase 13D re-run (definer authz hardening)** — Migration `20261301120000_phase13_recover_definer_authz_hardening.sql` applied to local disposable Postgres via `docker exec` (parent `pg.Client.connect()` to `127.0.0.1:54322` hung; hung `_apply_definer_hardening` node shells cleared). Audits run with `PHASE13_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres` (skips `npx supabase status`). All 6 gaps remediated; security audits 0 unexplained; all required zero-cost gates pass.

---

## Verdict

```
CLEAN_ROOM_MIGRATIONS          = PASS   (122 migrations applied cleanly)
MIGRATION_PROVENANCE           = PASS
SCHEMA_FINGERPRINT             = PASS
SCHEMA_DRIFT                   = PASS   (0 unexplained)
PHASE_1_12_GATES               = PASS   (116 checks)
GOLDEN_PHASE1_CONTRACT_FLOW    = PASS
GOLDEN_FULL_FLOW               = PASS   (19/19 steps)
CROSS_TENANT_ISOLATION         = PASS   (19/19 cases)
IDEMPOTENCY                    = PASS   (4/4 cases)
SECURITY_DEFINER_AUDIT         = PASS   (156/156 — UNEXPLAINED = 0)
DEEP_AUTHZ_AUDIT               = PASS   (442/442 — UNEXPLAINED_APP_RPC = 0)
K6_READ_APP_250VUS             = PASS   (p95=~7ms, 0% errors)
K6_WRITE_APP_250VUS            = PASS   (p95<4s, 0% errors)
K6_MIXED_APP_250VUS            = PASS   (p95<4s, 0% errors)
UNEXPLAINED_SCHEMA_DRIFT       = 0
ZERO_COST_PHASE13_GATES        = PASS
RPO<=5m                        = UNPROVEN
RTO<=4h                        = UNPROVEN
PHASE_13                       = IN_PROGRESS   (zero-cost gates closed; DR drill not executed; COST_APPROVAL_REQUIRED)
```

---

## DR PAUSE STATUS

```
T0                         = PASS
T1                         = PASS
T2                         = PASS
T3                         = DEFERRED

DR_GATE                    = NOT_RUN
RPO <= 5m                  = UNPROVEN
RTO <= 4h                  = UNPROVEN

Temporary resources        = 0
Disposable DR primary      = deleted and verified absent (yqqqocmbuxgagounywtp)
Staging                    = untouched (rpcpdrzbcclofvjpgldb)
Production                 = not authorized
PITR                       = not enabled

Reason                     = USER_DEFERRED_PITR_AND_DR_EXECUTION
```

Evidence: `docs/qa/phase13/dr/DR-PAUSE-EVIDENCE.json`,
`DR-CLEANUP.json`, `DR-PAUSE-EVIDENCE-INVENTORY.json`, `DR-RESUME-PLAN.md`.

---

## DR drill (2026-09-10) — PAUSED (PITR deferred)

```
T0_DR_PRIMARY_ISOLATED         = PASS
T1_DR_PRIMARY_INITIALIZED      = PASS
T2_DR_FIXTURE_LOADED           = PASS
T3_PITR_ACTIVE                 = DEFERRED
DR_GATE                        = NOT_RUN
MEASURED_RPO                   = UNPROVEN
MEASURED_RTO                   = UNPROVEN
PHASE_13                       = IN_PROGRESS
DR_TEMP_RESOURCES_REMAINING    = 0
STAGING                        = UNTOUCHED
PRODUCTION                     = NOT_AUTHORIZED
```

Sanitized T0–T2 evidence retained under `docs/qa/phase13/dr/`.
PITR was never enabled. Restore was not run.

---

## 1. Phase 13D — Definer authz hardening

### Apply (2026-09-09 local re-run)

| Step | Result |
|------|--------|
| Hung node cleanup | Cleared (no `_apply_definer_hardening` / `supabase status` node PIDs remaining) |
| Local stack | `supabase_db_FINANCE` healthy; TCP **54322** / **54321** open |
| Migration apply | **PASS** — `docker exec -i supabase_db_FINANCE psql …` piped SQL (CREATE FUNCTION + 5× REVOKE/GRANT + marker INSERT) |
| Node pg apply | **SKIPPED** — `pg.Client.connect()` hang observed on parent shells |

### Privilege verification (`has_function_privilege`)

| Function | authenticated EXECUTE | anon EXECUTE | Expected |
|----------|----------------------|--------------|----------|
| `calculate_tax_period` | ✅ true | revoke PUBLIC/anon in migration (keep authenticated) | authenticated ✅ |
| `ensure_inventory_cost_row` | ❌ false | ❌ false | ✅ |
| `ensure_inventory_stock_row` | ❌ false | ❌ false | ✅ |
| `purchase_line_inventory_debit_account` | ❌ false | ❌ false | ✅ |
| `tax_resolve_active_rule` | ❌ false | ❌ false | ✅ |
| `tax_resolve_effective_date` | ❌ false | ❌ false | ✅ |

Migration `20261301120000_phase13_recover_definer_authz_hardening.sql` remediated all 6 blockers:

| Function | Remediation | Audit source |
|----------|-------------|--------------|
| `calculate_tax_period(uuid)` | Added explicit `tax_assert_role(owner\|admin\|accountant)` at wrapper | auto_classified |
| `ensure_inventory_cost_row(uuid, uuid)` | REVOKE EXECUTE from public/anon/authenticated | execute_revoked |
| `ensure_inventory_stock_row(uuid, uuid, uuid)` | REVOKE EXECUTE from public/anon/authenticated | execute_revoked |
| `purchase_line_inventory_debit_account(...)` | REVOKE EXECUTE from public/anon/authenticated | execute_revoked |
| `tax_resolve_active_rule(...)` | REVOKE EXECUTE from public/anon/authenticated | execute_revoked |
| `tax_resolve_effective_date(...)` | REVOKE EXECUTE from public/anon/authenticated | execute_revoked |

Audit scripts already classify `execute_revoked_from_client_roles` as `INTENTIONAL_AND_DOCUMENTED` when anon and authenticated lack EXECUTE (verified via `has_function_privilege()`).

---

## 2. Security audit summary

| Audit | Before 13D | After 13D (2026-09-09 re-run) |
|-------|-----------|-------------------------------|
| SECURITY_DEFINER unexplained | 33/156 | **0/156 PASS** |
| DEEP_AUTHZ UNEXPLAINED_APP_RPC | 6/447 | **0/442 PASS** |
| GOLDEN_FULL_FLOW | — | **19/19 PASS** |
| CROSS_TENANT_ISOLATION | — | **19/19 PASS** |
| IDEMPOTENCY | — | **4/4 PASS** |

Audit invocation: `PHASE13_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres` (no `supabase status` dependency).

**Source breakdown (security-definer)**: registry=4, auto_classified=91, execute_revoked=61, unclassified=0

All 156 SECURITY DEFINER functions have `search_path` pinned. No authenticated-callable DEFINER without authz evidence remains.

---

## 3. Golden Flow — 19/19 PASS

**GOLDEN_FULL_FLOW = PASS** (re-confirmed post clean-room reset + migration)

Includes `taxes_projection` step calling `calculate_tax_period` with new wrapper auth guard — PASS.

---

## 4. Cross-Tenant & Idempotency

**CROSS_TENANT_ISOLATION = PASS** (19/19 cases)
**IDEMPOTENCY = PASS** (4/4 cases)

---

## 5. Load capacity (k6 progressive, post-13D)

| Workload | 10 VUS | 25 VUS | 50 VUS | 100 VUS | 250 VUS |
|----------|--------|--------|--------|---------|---------|
| READ_APP | ✅ PASS | ✅ PASS | ✅ PASS | ✅ PASS | ✅ PASS |
| WRITE_APP | ✅ PASS | ✅ PASS | ✅ PASS | ✅ PASS | ✅ PASS |
| MIXED_APP | ✅ PASS | ✅ PASS | ✅ PASS | ✅ PASS | ✅ PASS |

VERIFIED_READ/WRITE/MIXED_CAPACITY_APP = **250 VUS**

---

## 6. ZERO_COST gate matrix

| Gate | Result | Blocker? |
|------|--------|---------|
| MIGRATION_COMPLETENESS_PHASE1_12 | PASS | — |
| CLEAN_ROOM_COMPLETE_SCHEMA | PASS | — |
| UNEXPLAINED_SCHEMA_DRIFT = 0 | PASS | — |
| PHASE1_12_REGRESSION / gates | PASS | — |
| GOLDEN_FULL_FLOW | PASS | — |
| CROSS_TENANT_ISOLATION | PASS | — |
| IDEMPOTENCY | PASS | — |
| OPERATIONAL_LOAD @ 250 VUS | PASS | — |
| SECURITY_DEFINER_AUDIT | **PASS** | — |
| DEEP_AUTHZ_AUDIT | **PASS** | — |

```
ZERO_COST_PHASE13_GATES = PASS
```

**Not blockers (out of zero-cost scope)**:
- RPO≤5m / RTO≤4h: **UNPROVEN** (requires paid remote restore drill)
- ARCA fiscal invoicing homologation: out-of-scope

---

## 7. Remaining non-blockers

| Pri | Item | Status |
|-----|------|--------|
| P3 | RPO/RTO restore drills | UNPROVEN → COST_APPROVAL_REQUIRED |
| P4 | ARCA homologation cert | External / out-of-scope |

No Production / PITR / paid remote / Storage backup provisioned. No Staging writes performed.
