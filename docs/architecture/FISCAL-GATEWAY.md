# Fiscal Gateway (future) — ARCA

Phase 1 does **not** integrate ARCA in production.

## Target design

```
Application (sales / invoices UI)
        ↓
Fiscal Gateway (adapter interface)
        ↓
ARCA (AFIP) connectors
```

## Principles

1. Accounting core does **not** depend on ARCA UI or SOAP clients directly.
2. Homologación and producción are separate credentials and environments.
3. Gateway returns normalized results (`authorized`, `rejected`, `pending`) with correlation IDs.
4. All gateway calls are audited.
5. Activation requires LEGAL-GATES approval for ELECTRONIC INVOICING.

## Interface sketch (not implemented)

```ts
type FiscalAuthorizeRequest = {
  organizationId: string;
  documentType: string;
  payload: unknown;
};

type FiscalAuthorizeResult =
  | { status: "authorized"; cae: string; caeDueDate: string }
  | { status: "rejected"; errors: string[] }
  | { status: "pending"; trackingId: string };
```

## Phase 1 status

Architecture documented only. No production ARCA credentials in the repo.
