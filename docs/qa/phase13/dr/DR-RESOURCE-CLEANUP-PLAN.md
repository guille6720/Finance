# DR resource cleanup plan

Prepared **before** any paid resource exists. Execute **after** evidence JSON is written. This is not authorization to create resources.

## Retain (sanitized)

- `docs/qa/phase13/dr/*` measurements and run JSON
- `docs/operations/DR-RUNBOOK.md`
- MEASURED_RPO / MEASURED_RTO
- Fixture spec (synthetic only)

Do not retain recovery API keys, service_role, or env files with drill secrets.

---

## Destruction order (after evidence)

| Order | Resource | How | Delete trigger |
|------|----------|-----|----------------|
| 1 | PITR 7-day on DR primary | Dashboard → Database → Point in Time → disable | Immediately after T6/T7 evidence |
| 2 | Temporary credentials | Revoke drill anon/service keys; never reuse on Staging | After T13 export |
| 3 | Rehearsal env | Unset `NEXT_PUBLIC_SUPABASE_URL`, service role, `REHEARSAL_SUPABASE_PROJECT_REF` pointing at drill | After T13 |
| 4 | Isolated restore project | Dashboard → Project Settings → Delete project | After Golden Flow + security JSON saved |
| 5 | DR primary project | Delete project (destroys remaining backups) | After restore project deleted and evidence saved |
| 6 | Local Storage copies outside git | Delete extra copies of the synthetic PDF if duplicated | After hash recorded |
| 7 | Confirm Staging | Ref `rpcpdrzbcclofvjpgldb` untouched | Mandatory check |
| 8 | Confirm Production | Still does not exist | Mandatory check |

Billing: compute and PITR stop after the hour in which they are removed. Pro plan ($25) continues until the org plan is changed — do not leave a disposable org on Pro if it was created only for the drill.

---

## Do not

- Leave PITR enabled “just in case”
- Keep a second project as shadow Production
- Disable Spend Cap
- Upgrade Staging compute
- Restore onto Staging
- Enable ARCA / FECAESolicitar
- Commit secrets
