# Phase 5 — ARCA Homologation Step 1 (evidence)

**Recorded:** 2026-09-10  
**Scope:** Credential contract + WSAA + safe connectivity  
**Result:** **STOPPED** — gateway and homologation credentials not present in repo.

## Existing configuration contract (names only — no values)

| Contract | Status | Exact name / location |
|----------|--------|------------------------|
| Private key | **NOT_IMPLEMENTED** | No env var. DB: `fiscal_credential_metadata.secret_provider` default `env_file` + `secret_ref` (opaque) |
| Certificate | **NOT_IMPLEMENTED** | Same; metadata only: `certificate_alias`, `certificate_fingerprint` |
| Represented CUIT | **NOT_IMPLEMENTED** as env | Org/fiscal tables hold CUIT in DB; no `ARCA_*CUIT*` env |
| Environment | **IMPLEMENTED** | `ARCA_ENV`, optional `FISCAL_GATEWAY_ENV` → `disabled` \| `homologation` \| `production` (`src/config/env.ts`) |
| WSAA endpoint | **NOT_IMPLEMENTED** | No URL env or constant |
| WSFEv1 endpoint | **NOT_IMPLEMENTED** | No URL env or constant |
| TA cache | **NOT_IMPLEMENTED** | No TA table/module |
| WSAA service id | **DOCUMENTED in DB** | `fiscal_service_profiles.wsaa_service_name` default **`wsfe`** (not `wsfev1`) |

```
ARCA_PRIVATE_KEY_CONFIG       = NOT_IMPLEMENTED
ARCA_CERTIFICATE_CONFIG       = NOT_IMPLEMENTED (metadata columns only)
ARCA_REPRESENTED_CUIT_CONFIG  = NOT_IMPLEMENTED (no dedicated env)
ARCA_ENV_CONFIG               = ARCA_ENV | FISCAL_GATEWAY_ENV
WSAA_ENDPOINT_CONFIG          = NOT_IMPLEMENTED
WSFE_ENDPOINT_CONFIG          = NOT_IMPLEMENTED
TA_CACHE_IMPLEMENTATION       = NOT_IMPLEMENTED
```

## Guards / safety

- `ARCA_ENV=production` → fail-closed (`src/config/env.ts`)
- SQL begin-authorization blocks `PRODUCTION`
- No PEM/key in repo; `.gitignore` includes `*.pem`
- No SOAP caller for LoginCms / FEDummy / FEParam* / FECAESolicitar

```
ARCA_SECRET_SAFETY      = PASS   (no credentials present to leak; server-only pattern for future secrets via env_file + no NEXT_PUBLIC)
ARCA_ENVIRONMENT_GUARD  = PASS   (production ARCA blocked)
```

## Homologation calls

```
WSAA_HOMOLOGATION       = NOT_RUN
FEDUMMY                 = NOT_RUN
PARAMETER_SYNC          = NOT_RUN
PTO_VENTA               = NOT_RUN
LAST_AUTHORIZED_QUERY   = NOT_RUN
FECAESOLICITAR          = NOT_RUN
ARCA_PRODUCTION         = NOT_AUTHORIZED
```

## Blocker

```
BLOCKER = MISSING_FISCAL_GATEWAY_AND_HOMOLOGATION_CREDENTIALS
ROOT_CAUSE = Phase 5 ships DB + env guards + docs only; no WSAA/WSFE SOAP adapter and no local cert/key/CUIT credential binding
USER_ACTION_REQUIRED =
  1) Provide homologation PKCS#12 or cert+key out of band (do not commit)
  2) Agree env contract for secrets (or implement adapter reading fiscal_credential_metadata.secret_ref)
  3) Authorize implementation of Fiscal Gateway WSAA LoginCms + FEDummy + FEParam* (still no FECAESolicitar)
  4) Confirm represented CUIT and that WSASS auth for wsfe is bound to that CUIT
```

User confirmed externally: WSASS certificate created; WSFE authorization PASS for `wsfe` on homologation. That does not yet exist as wired credentials in this repository.
