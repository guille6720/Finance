# DR cost final validation — Option B

**Evidence date:** 2026-09-09
**Sources (fetched this session, not prior estimates):**

- https://supabase.com/pricing
- https://supabase.com/docs/guides/platform/manage-your-usage/compute
- https://supabase.com/docs/guides/platform/manage-your-usage/point-in-time-recovery
- https://supabase.com/docs/guides/platform/backups
- https://supabase.com/docs/guides/platform/clone-project

**This document is not a quote and not spending authorization.**

---

## 1. Organization (OBSERVED)

```
SUPABASE_ORGANIZATION_ID = qsgnqyleasarodfwzlwe
SUPABASE_ORGANIZATION_SLUG = qsgnqyleasarodfwzlwe
```

Evidence: `supabase/.temp/linked-project.json` (CLI link for project `rpcpdrzbcclofvjpgldb` / Finance Staging SA). Organization ID is not a secret.

**Org plan (Free vs Pro): UNKNOWN** — not in that file; dashboard billing was not queried. Two cost scenarios below.
If the org is **Free**, moving it to Pro **would change Staging billing** (no pause, daily backups, $25/month). That conflicts with “do not change current Staging” commercially even if schema is untouched.

---

## 2. Line-item validation (list prices)

| # | Item | Current list | Billable unit | Notes |
|---|------|--------------|---------------|-------|
| 1 | Disposable project (org already Pro) | $0 extra plan | n/a | Plan is org-level |
| 1b | Org Free → Pro | **$25 / month upfront** | month | FAQ: Pro charged up front |
| 2 | Compute for PITR | **Small $0.0206 / hour** (~$15/mo) | hour (partial = full) | PITR requires ≥ Small. **Not covered by Spend Cap** |
| 3 | PITR 7-day | **$0.137 / hour** (~$100/mo) | hour (partial = full) | **Not covered by Spend Cap** |
| 4 | Isolated restore destination | Same compute as source if “Restore to a New Project” mirrors attributes | hour until delete | Paid-plan feature; **does not copy Storage bytes** |
| 5 | Independent Storage backup | **$0** if local encrypted copy of synthetic object only | n/a | Do not buy S3 for 64-byte fixture |
| 6 | Data transfer | **$0 expected** | GB | Synthetic ≪ included egress |
| 7 | Temporary object storage | **$0** | n/a | Local disk |
| 8 | Additional project cost | 2nd compute (Small if mirrored) | hour | Delete after evidence |
| 9 | Taxes | **UNDETERMINED** | % | Vendor: VAT/GST by billing address |
| 10 | Minimum duration | PITR ≥ **24 h** recommended (base backup lag) | hours | Disable PITR immediately after evidence |

Compute credits: **$10 / month / paid org**, apply to compute only, reset monthly. Staging may already consume them.

---

## 3. Option A vs Option B (48 h source, 24 h restore target)

Hourly: Small 0.0206; PITR 0.137.

**If org is already Pro (incremental):**

| | OPTION A in-place | OPTION B isolated |
|--|-------------------|-------------------|
| Plan | $0 | $0 |
| Source Small 48 h | $0.99 | $0.99 |
| PITR 48 h | $6.58 | $6.58 |
| Restore project Small 24 h | $0 | $0.49 |
| Storage / transfer / Vercel | $0 | $0 |
| **Expected USD** | **7.57** | **8.06** |
| **72 h / 36 h restore worst USD** | **11.34** | **12.08** |

**If org is currently Free (must buy Pro):**

| | A | B |
|--|---|---|
| Pro month floor | 25.00 | 25.00 |
| Incremental compute+PITR | 7.57 | 8.06 |
| **Expected USD** | **32.57** | **33.06** |
| **+ 21% VAT if applicable (INFERRED)** | ~39 | ~40 |

```
OPTION_A_ESTIMATED_COST_USD = 7.57   (already Pro) | 32.57 (Free→Pro, pre-tax)
OPTION_B_ESTIMATED_COST_USD = 8.06   (already Pro) | 33.06 (Free→Pro, pre-tax)
OPTION_B_RECOMMENDED = YES
RATIONALE = Isolated restore is required to simulate source-environment loss.
Incremental cost vs A is ~USD 0.50 (24 h extra Small). The architecture is not materially more expensive.
Do not use Staging as source or target.
```

---

## 4. Spending cap proposal (recommendation only)

```
RECOMMENDED_MAX_DR_BUDGET_USD = 80.00
```

Covers: unexpected Free→Pro, 72 h PITR, two Small projects, tax buffer, clone disk upsell warning.

Breakdown (planning numbers, not a bill):

| Line | Expected if already Pro (48/24 h) | Worst within planned drill |
|------|-----------------------------------|----------------------------|
| SUPABASE_PROJECT (plan) | 0.00 | 25.00 |
| COMPUTE | 1.48 | 5.00 |
| PITR | 6.58 | 15.00 |
| RESTORE_TARGET | 0.49 | 5.00 |
| STORAGE_BACKUP | 0.00 | 1.00 |
| TRANSFER | 0.00 | 1.00 |
| OTHER / tax | 0.00 | 15.00 |
| **EXPECTED_TOTAL** | **8.06** | |
| **WORST_CASE_WITHIN_PLANNED_DRILL** | | **80.00** |

Do not authorize spend above a user-stated max without a new STOP.

---

## 5. Resource lifetime

| RESOURCE | START_TRIGGER | EXPECTED_ACTIVE_HOURS | DELETE_TRIGGER | EXPECTED_COST | MAX_EXPECTED_COST |
|----------|---------------|----------------------|----------------|---------------|-------------------|
| DR primary project | After written budget approval | 36–48 | After evidence export | ~$1 compute | $5 |
| Small compute (primary) | Same as PITR enable | 36–48 | Downgrade/delete with project | ~$1 | $5 |
| PITR 7-day | After primary healthy; before T1 | 36–48 | **Immediately after restore evidence** | ~$6.60 | $15 |
| Isolated restore project | Immediately before T5/T6 | 12–24 | After Golden Flow + export | ~$0.50 | $5 |
| Local Storage copy | T3 | until T7 done | Delete synthetic files after evidence | $0 | $1 |
| Rehearsal app env vars | T8 | until T13 | Unset after teardown | $0 | $0 |
| Vercel | **do not create** | 0 | n/a | $0 | $0 |
| Staging PITR | **do not enable** | 0 | n/a | $0 | $0 |

---

## 6. Taxes

Cannot determine. Billing FAQ: tax depends on address. Treat as UNDETERMINED; budget cap includes buffer.

---

## 7. Spend Cap (vendor)

Spend Cap is on by default on Pro. **Compute Hours and PITR are not covered by Spend Cap.** A Spend Cap does not prevent the drill bill for Small + PITR.

---

## 8. PITR RPO (vendor, not measured)

WAL files are backed up at **two-minute intervals** by default (or sooner if large). Documented worst-case RPO is **2 minutes**. That is **DOCUMENTED, not MEASURED**. Daily backups cannot meet RPO ≤ 5 minutes.

PITR requires **≥ Small** compute. Restore-to-new-project **mirrors source compute and disk**; the isolated target will therefore be **Small**, not Micro.

Database restore **does not copy Storage objects**. Bucket `purchase-evidence` must be recreated on the target and objects restored from the independent copy.

---

## 9. Cost minimization (applied to this plan)

- PITR **7-day** only (not 14/28).
- Small only while PITR is on; delete projects after evidence (hourly billing stops).
- No Database Branching, Custom Domain, Log Drain, Image Transformations, or Vercel.
- Storage backup = local copy of the synthetic PDF (~192 bytes), not a paid object store.
- If org is **Free**: do **not** upgrade the Staging org without a further STOP. Prefer a **separate disposable org** so Staging remains Free. That separate org still needs Pro ($25/month upfront) to enable PITR + restore-to-new-project.
- Do not keep PITR after T6 evidence.

---

## 10. Pre-approval confirmation (not authorization)

Confirm in Dashboard **before** creating resources:

1. Org `qsgnqyleasarodfwzlwe` plan = Free or Pro.
2. If Free: whether Pro will be bought on this org or on a new disposable org.
3. User message contains **OPTION B** and **MAXIMUM TOTAL DR BUDGET IN USD**.
4. Projected cost ≤ that maximum.
