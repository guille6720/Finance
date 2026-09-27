# Accountant Demo Guide — Synthetic Staging Data

**Synthetic demo data. Not valid for tax, accounting, legal, payroll, banking, or regulatory filing.**

Environment: **LOCAL / STAGING ONLY**. Never Production. Never ARCA Production.

---

## What this demo is

A deterministic, idempotent seed that creates two synthetic tenants so an Argentine accountant can exercise Contabilium Finance end-to-end:

| Org | Code | Purpose |
| --- | --- | --- |
| EMPRESA DEMO ARGENTINA SA | `DEMO-AR-001` | Full operational demo |
| EMPRESA DEMO BETA SRL | `DEMO-AR-BETA-001` | Cross-tenant isolation |

Seed script: `scripts/demo/seed-accounting-demo.mjs`

---

## Safety guards

The seed **refuses** to run unless:

- `DEMO_SEED_CONFIRM=YES`
- Target is local (`127.0.0.1` / `localhost`) **or** an allow-listed staging Supabase project ref
- `ARCA_ENV` / `FISCAL_GATEWAY_ENV` are **not** `production`

It will:

- Print `PROJECT_REF` / API URL before writing
- Never truncate tables
- Never delete non-demo organizations
- Never call ARCA Production / FECAESolicitar
- Never store real CUIT values (org `cuit` is `null`; counterparties use `FOREIGN_TAX_ID` / `NONE` with `DEMO-*` placeholders)
- When `DEMO_SEED_CREATE_USERS=YES`, **reset** allowlisted `*.demo@example.invalid` passwords to the current `DEMO_SEED_PASSWORD` (idempotent; no duplicates)
- When `DEMO_SEED_CREATE_USERS` is not `YES`, **login only** — credentials are not mutated
- Never log `DEMO_SEED_PASSWORD`

---

## How to run (local)

Prerequisites: local Supabase stack running (`npx supabase start`), migrations applied.

```bash
# Required confirmation
set DEMO_SEED_CONFIRM=YES

# Optional: create named demo users (password NEVER committed)
set DEMO_SEED_CREATE_USERS=YES
set DEMO_SEED_PASSWORD=Choose-A-Long-Local-Password-1!

npm run demo:seed:accounting
```

PowerShell:

```powershell
$env:DEMO_SEED_CONFIRM="YES"
$env:DEMO_SEED_CREATE_USERS="YES"
$env:DEMO_SEED_PASSWORD="Choose-A-Long-Local-Password-1!"
npm run demo:seed:accounting
```

Re-run is safe (idempotent). Counts may stay stable while existing demo rows are reused.

### Staging (allow-listed only)

```bash
DEMO_SEED_CONFIRM=YES
PHASE13_FORCE_REMOTE=1
PHASE13_API_URL=https://<staging-ref>.supabase.co
PHASE13_ANON_KEY=…
PHASE13_SERVICE_ROLE_KEY=…
PHASE13_DB_URL=…   # optional for direct SQL helpers
DEMO_SEED_CREATE_USERS=YES
DEMO_SEED_PASSWORD=…
npm run demo:seed:accounting
```

Do **not** point this at Production.

---

## Demo users (when CREATE_USERS=YES)

| Role | Name | Email | App role |
| --- | --- | --- | --- |
| Administrator | Admin Demo | `admin.demo@example.invalid` | `admin` |
| Accountant | Contador Demo | `contador.demo@example.invalid` | `accountant` |
| Operator | Operador Demo | `operador.demo@example.invalid` | `operator` |
| Read-only auditor | Auditor Demo | `auditor.demo@example.invalid` | `viewer` |
| Owner (bootstrap) | Owner Demo | `owner.demo@example.invalid` | `owner` |
| Isolation probe | Isolation Demo | `isolation.demo@example.invalid` | `viewer` on primary only |

Password: whatever you set in `DEMO_SEED_PASSWORD` (not stored in the repo).

App URL (local): http://localhost:3000/login

---

## Organization profile

- Legal name: EMPRESA DEMO ARGENTINA SA  
- Trade name: Empresa Demo  
- Internal code: DEMO-AR-001  
- Tax ID: **synthetic placeholder** `SYNTHETIC-NOT-A-CUIT` (org column `cuit` left null — not a real CUIT)  
- Address: Av. Demo 1234, CABA, Argentina  
- Email: demo-contador@example.invalid  
- Phone: +54 11 0000 0000  
- Currency: ARS  
- Marker: `organization_settings` → `demo.is_demo = true`

---

## Scenarios to test

1. **Normal sale** — sales orders confirmed / ready to invoice (no production CAE).  
2. **Credit / AR paths** — purchases posted create AP; treasury openings fund cash/banks.  
3. **Overdue / aging** — multi-month purchase & sales dates (Jan–Aug 2026).  
4. **Inventory purchase on account** — posted supplier invoices with stock items.  
5. **Partial / full AP** — mix of DRAFT / REVIEWED / POSTED / REVERSED purchases.  
6. **Stock reduction** — opening inventory adjustments + sales of stock products.  
7. **Inventory reversal** — use inventory reverse RPC on a posted demo op (manual follow-up if needed).  
8. **Journal reversal** — entry `DEMO-JE-TO-REVERSE` posted then reversed.  
9. **Bank accounts** — Banco Demo CC + CA + transfer + fee adjustment.  
10. **VAT / tax UI** — HOMOLOGATION tax period ensure (marked NOT_FILED / DEMO).  
11. **Period close attempt** — FY 2026 monthly periods exist; try close on an early month carefully.  
12. **Read-only auditor** — login as `auditor.demo@example.invalid` → reports only.  
13. **Cross-tenant isolation** — `isolation.demo` must not see Demo Beta counterparties.

---

## Reports to review

- Trial Balance / Journal / GL  
- P&L and Balance Sheet  
- Customer & supplier lists  
- Inventory stock (main + secondary warehouses)  
- Cash / bank treasury accounts  
- Purchase documents list (posted + reversed)  
- Sales documents list (draft / confirmed / cancelled)  
- Dashboard KPIs  

---

## Expected seed summary fields

```
DEMO_SEED_STATUS = PASS
PRODUCTION_TOUCHED = NO
ARCA_PRODUCTION_CALLS = 0
TENANT_ISOLATION_READY = PASS   # when users were created
REPORT_DATA_READY = YES         # derived from DB postconditions, not counters
DEMO_POSTCHECK = PASS
DEMO_IDEMPOTENCY = PASS
DUPLICATES_FOUND = 0
```

Counters are split into `<ENTITY>_CREATED_THIS_RUN` (rows inserted by this run) and
`<ENTITY>_REUSED` (rows found by deterministic key). On a re-run every
`*_CREATED_THIS_RUN` must be `0`; set `DEMO_SEED_EXPECT_IDEMPOTENT=YES` to make any insert
fail `DEMO_IDEMPOTENCY`. When `REPORT_DATA_READY = PARTIAL`, `REPORT_DATA_MISSING` lists the
unmet postconditions.

Read-only verification (SELECT only, LOCAL / allow-listed staging):

```
npm run demo:postcheck
```

---

## Known limitations

- Fiscal documents are **not** live-authorized; no production CAE/QR.  
- Some inventory/treasury edge fields vary by migration surface — seed skips softly and logs warnings.  
- Bank statement reconciliation lines are minimal; extend manually if UI requires more.  
- AR open items from fiscal AUTHORIZED docs are limited without Homologation authorize.  
- Passwords are never committed; rotate staging passwords regularly.  
- Starter chart of accounts comes from `seed_starter_chart_of_accounts` (existing RPC).

---

## Explicit disclaimer

> **Synthetic demo data. Not valid for tax, accounting, legal, payroll, banking, or regulatory filing.**  
> Do not present these records to AFIP/ARCA, banks, auditors (as evidence), or clients as real activity.
