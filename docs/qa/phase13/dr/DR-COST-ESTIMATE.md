# Phase 13 DR cost estimate

**Generated:** 2026-09-09  
**Prices:** public list (Supabase pricing / backups docs), USD, **INFERRED from vendor documentation — not a quote**.  
**No resources provisioned.**

```
COST_APPROVAL_REQUIRED = YES
```

Any hosted project, PITR add-on, compute upgrade, or object-storage account **can produce a charge**. This prompt is **not** authorization to spend.

---

## Why zero-cost is insufficient

| Approach | FREE_OR_PAID | Can prove RPO ≤ 5 min? |
|----------|----------------|------------------------|
| Local Docker dump | FREE | NO — not hosted DR |
| Staging daily backup | maybe already paid; **do not change Staging** | NO — daily RPO ≫ 5 min |
| New Free remote project | FREE (limits) | NO — no automatic backups; pauses |
| Pro + daily backups only | PAID | NO — up to ~24 h loss |
| Pro + PITR + Storage copy | PAID | YES, *if measured* |

---

## Resources (minimum drill)

| RESOURCE | WHY_REQUIRED | FREE_OR_PAID | EXPECTED_COST | BILLING_UNIT | MINIMUM_DURATION | CAN_BE_DELETED_AFTER_DRILL | ESTIMATED_TOTAL_DRILL_COST |
|----------|--------------|--------------|---------------|--------------|------------------|----------------------------|----------------------------|
| Disposable Supabase **Pro** project (DR primary) | Hosted Postgres + Auth + Storage; PITR not on Free | PAID | ~$25 / month list (proration unknown; assume **month floor**) | month / org | 24–72 h drill but plan may bill month | YES | **$25** |
| **Small** compute add-on | PITR prerequisite (vendor docs) | PAID | ~$15 / month list; ~$0.021 / hour; $10 compute credits / paid org | hour | same as PITR window | YES with project | **$1–15** |
| **PITR 7-day** add-on | Only vendor backup with documented WAL interval that *can* meet ≤5 min | PAID | **$0.137 / hour** (~$100/month) | hour (partial hour billed) | ≥24 h recommended (PITR base backup lag) | YES — disable immediately after | **$3.29 / 24 h** to **~$10 / 72 h** |
| Second Pro project (restore target) | Avoid in-place restore destroying evidence; never use Staging | PAID | second ~$25 month floor | month | 24–48 h | YES | **$0 if in-place** / **+$25 if isolated restore** |
| Object storage (S3/GCS) or Storage dump to local encrypted disk | Independent Storage backup | PAID or FREE (local disk) | S3 ~$0.023/GB-month; drill ≪ 1 GB | GB-month | 72 h | YES | **$0–1** |
| Vercel rehearsal | Optional; not required if app runs locally | PAID if Pro | $0 Hobby / $20 Pro | month | n/a | YES | **$0 recommended** |
| Staging PITR | Forbidden by this plan | PAID | n/a | n/a | n/a | n/a | **DO NOT** |
| Production project | Forbidden | PAID | n/a | n/a | n/a | n/a | **DO NOT** |

### Estimated totals (USD)

| Option | What | ESTIMATED_TOTAL_DRILL_COST |
|--------|------|----------------------------|
| **A — recommended minimum** | 1 Pro + Small + PITR 24–48 h + local Storage copy + local app restore in-place | **$35–55** |
| **B — isolated restore** | A + second Pro restore target | **$60–95** |
| **C — no PITR** | 1 Pro + 5-min logical dumps | **~$25** month floor; **cannot** claim vendor PITR RPO |

Spend cap should stay **enabled**. PITR add-on is often **outside** spend cap (vendor docs) — treat PITR hours as uncapped.

FX / taxes / existing org Pro subscription may change the invoice. **INFERRED.**

---

## COST_APPROVAL_REQUIRED = YES

```
DR_ARCHITECTURE = READY   (design complete; not provisioned)
DR_COST_ESTIMATE = USD 35–55 (option A) / USD 60–95 (option B)
RESOURCES_REQUIRED = [
  disposable_supabase_pro_project,
  small_compute,
  pitr_7day_addon,
  independent_storage_copy,
  optional_second_restore_project,
  local_or_rehearsal_app
]
COST_APPROVAL_REQUIRED = YES
```

**STOP.** Do not enable PITR, create projects, upgrade compute, or buy Storage backup until the user explicitly approves a cost option (A, B, or C).
