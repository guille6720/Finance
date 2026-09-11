# Roadmap

## Phase 1 — Platform foundation (this phase)

Auth, tenancy, RLS, onboarding, shell, features, audit, docs, tests.

## Phase 2 — Accounting core

Chart of accounts, journal entries/lines, posting service, reversals, immutable posted entries.

## Phase 3 — Customers + suppliers

Party master data, balances in plain language.

## Phase 4 — Sales

Sales documents, collections, automatic posting hooks.

## Phase 5 — ARCA Fiscal Gateway

```
F5_HOMOLOGATION        = PASS
F5_TECHNICAL_STATUS    = COMPLETE
ARCA_PRODUCTION        = NOT_AUTHORIZED
```

Homologation proven (WSAA, FEDummy, catalogs, CondicionIVAReceptor, Factura C authorize / reject / uncertain-reconcile, accounting post-once).
Production ARCA is **not** authorized. See `docs/qa/phase5/ARCA-F5-FINAL-GATE.md`.

## Phase 6 — Purchases

Purchases/expenses and payables.

## Phase 7 — Cash + banks

Cash register, bank accounts, reconciliation foundations.

## Phase 8 — Inventory + products

Stock movements linked to sales/purchases.

## Phase 9 — POS

Counter sales for retail/kiosk.

## Phase 10 — Taxes

Tax books and liquidations (specialist review required).

## Phase 11 — Management dashboard

Real KPIs from posted operational data.

## Phase 12 — Industry packs / modular configurator

Vertical packs (healthcare, medical-legal, etc.) with separate security domains where needed.

## Phase 13 — Readiness / hardening (IN PROGRESS)

Local/staging clean-room rebuild, SECURITY DEFINER audit, cross-tenant matrix, k6 capacity, ops runbooks.

**Not complete** until DB + Storage restore drills prove RPO ≤ 5 minutes and RTO ≤ 4 hours.

See `docs/qa/phase13/PHASE-13-STATUS.md`.

## Phase 14 — Controlled pilot & go-live readiness (IN PROGRESS)

Pre-pilot gates only. `PUBLIC_PRODUCTION_LAUNCH` is not authorized until Phase 13 DR is measured and a controlled environment is explicitly approved.

ARCA homologation for F5 is PASS; F14 remains IN_PROGRESS because Production/pilot launch gates stay blocked pending F13 DR (RPO/RTO unproven).

See `docs/qa/phase14/PHASE-14-PRE-PILOT-REPORT.md`.

---

Do **not** start Phase 2 automatically after Phase 1.
Do **not** treat the product as Production-ready.
