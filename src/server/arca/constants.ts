/** Homologation-only ARCA endpoints. Production URLs are forbidden. */
export const ARCA_WSAA_SERVICE = "wsfe" as const;

export const ARCA_WSAA_HOMO_URL =
  "https://wsaahomo.afip.gov.ar/ws/services/LoginCms" as const;

export const ARCA_WSFE_HOMO_URL =
  "https://wswhomo.afip.gov.ar/wsfev1/service.asmx" as const;

/** Known production hosts — must never be configured. */
export const ARCA_PRODUCTION_HOST_FRAGMENTS = [
  "wsaa.afip.gov.ar",
  "servicios1.afip.gov.ar",
  "ws.afip.gov.ar",
] as const;

export const TRA_VALIDITY_SECONDS = 60 * 10; // 10 minutes conservative
export const TA_REFRESH_SKEW_MS = 60_000; // refresh 60s before expiry
