# Phase 5 — ARCA Homologation Fiscal Gateway

**F5_HOMOLOGATION_STATUS = IN_PROGRESS**
**FECAESOLICITAR = NOT_RUN** · **ARCA_PRODUCTION = NOT_AUTHORIZED**

## Verdict (implementation)

| Gate | Status |
|------|--------|
| FISCAL_GATEWAY_IMPLEMENTED | YES |
| ARCA_CONFIG_VALIDATION | PASS (code + unit contract) |
| ARCA_CERT_KEY_MATCH | PASS (helper + unit; live pending secrets) |
| ARCA_SECRET_SAFETY | PASS |
| ARCA_ENVIRONMENT_GUARD | PASS |
| WSAA_HOMOLOGATION | NOT_RUN (live) |
| TA_CACHE | PASS (unit single-flight + refresh; live pending) |
| FEDUMMY | NOT_RUN |
| PARAMETER_SYNC | NOT_RUN |
| CONDICION_IVA_RECEPTOR_SYNC | NOT_RUN |
| PTO_VENTA | NOT_RUN |
| LAST_AUTHORIZED_QUERY | NOT_RUN |
| ARCA_SECRET_SCAN | Run `npm run test:arca:secret-scan` |
| FECAESOLICITAR | NOT_RUN |
| ARCA_PRODUCTION | NOT_AUTHORIZED |

### Current blocker (live)

```
BLOCKER = MISSING_HOMOLOGATION_LOCAL_SECRETS
ROOT_CAUSE = .env.arca.homo.local not present (or required vars empty)
USER_ACTION_REQUIRED = Create .env.arca.homo.local locally via PowerShell Base64 steps below. Do not paste secrets into Cursor chat.
```

After the local file exists: `npm install` (for `node-forge`) → `npm run test:arca:unit` → `npm run test:arca:secret-scan` → `npm run test:arca:homo:live`.

## Scope delivered

Server-only modules under `src/server/arca/`:

- Secret contract + fail-closed config (`config.ts`, `src/config/env.ts`)
- Cert/key match (`cert.ts`)
- TRA + CMS + WSAA `loginCms` with `service=wsfe`
- Ephemeral in-memory TA cache with single-flight (`SERVERLESS_MEMORY_CACHE_IS_EPHEMERAL`)
- WSFEv1 read-only: `FEDummy`, `FEParamGetTiposCbte|TiposDoc|TiposMonedas|CondicionIvaReceptor|PtosVenta`, `FECompUltimoAutorizado`
- Explicit forbid: `feCaeSolicitarForbidden()` — **no CAE path**

## Secret contract (server-only)

| Variable | Role |
|----------|------|
| `ARCA_ENV=homologation` | Enables gateway |
| `ARCA_REPRESENTED_CUIT` | 11 digits (not hardcoded) |
| `ARCA_HOMO_PRIVATE_KEY_B64` | Base64 PEM key |
| `ARCA_HOMO_CERT_B64` | Base64 PEM cert |
| `ARCA_WSAA_SERVICE=wsfe` | Must be `wsfe` |
| `ARCA_WSAA_URL` | `https://wsaahomo.afip.gov.ar/ws/services/LoginCms` only |
| `ARCA_WSFE_URL` | `https://wswhomo.afip.gov.ar/wsfev1/service.asmx` only |
| `ARCA_CERT_ALIAS` | Optional metadata |

Local file: `.env.arca.homo.local` (**gitignored**). Template: `.env.arca.homo.example`.

Never use `NEXT_PUBLIC_` for these secrets.

## Local Base64 setup (PowerShell — your machine only)

Do **not** paste secrets into Cursor chat.

```powershell
$keyPath = "C:\Users\pigus\ARCA-HOMO\contabilium-homo.key"
$certPath = "C:\Users\pigus\ARCA-HOMO\contabilium-homo.pem"
$outEnv = "E:\FINANCE\.env.arca.homo.local"

$keyB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keyPath))
$certB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($certPath))

@"
ARCA_ENV=homologation
ARCA_REPRESENTED_CUIT=REPLACE_WITH_11_DIGIT_CUIT
ARCA_HOMO_PRIVATE_KEY_B64=$keyB64
ARCA_HOMO_CERT_B64=$certB64
ARCA_WSAA_SERVICE=wsfe
ARCA_WSAA_URL=https://wsaahomo.afip.gov.ar/ws/services/LoginCms
ARCA_WSFE_URL=https://wswhomo.afip.gov.ar/wsfev1/service.asmx
ARCA_CERT_ALIAS=CONTABILIUMHOMO01
"@ | Set-Content -Path $outEnv -Encoding utf8

Write-Host "Wrote $outEnv (gitignored). Do not commit or share."
```

Replace `REPLACE_WITH_11_DIGIT_CUIT` with your homologation CUIT before running the live runner.

## Commands

```bash
npm install
npm run test:arca:unit
npm run test:arca:secret-scan
npm run test:arca:homo:live
```

Live evidence (sanitized): `docs/qa/phase5/ARCA-HOMOLOGATION-LIVE.json`
Secret scan: `docs/qa/phase5/ARCA-SECRET-SCAN.json`

## Live execution order (STOP before CAE)

1. Config validation
2. Cert/key match
3. WSAA LoginCms
4. TA cache
5. FEDummy — **STOP on FAIL**
6. Parameter methods + Condicion IVA receptor
7. FEParamGetPtosVenta — **STOP if no usable POS**
8. FECompUltimoAutorizado

**Absolute stop before FECAESolicitar.**

## TA cache limitation

`SERVERLESS_MEMORY_CACHE_IS_EPHEMERAL` — acceptable for homologation testing. No paid cache dependency. Production durable TA caching is a future decision.

## Parameter catalogs

Live runner fetches ARCA `FEParam*` values and maps them via `src/server/arca/catalog-sync.ts` (preserves raw numeric IDs). Bootstrap rows in `fiscal_parameter_catalogs` are marked `refresh_required`. DB upsert is deferred to an existing secure Phase 5 write contract (no ad-hoc service-role writes in this gateway step).
