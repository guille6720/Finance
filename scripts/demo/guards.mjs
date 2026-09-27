/**
 * Staging/local demo seed environment guards.
 * Never allow Production / ARCA Production.
 */

export const DEMO_CODES = Object.freeze({
  PRIMARY: "DEMO-AR-001",
  BETA: "DEMO-AR-BETA-001",
});

export const DEMO_SETTINGS_KEYS = Object.freeze({
  IS_DEMO: "demo.is_demo",
  CODE: "demo.code",
  TAX_PLACEHOLDER: "demo.tax_id_placeholder",
  SEEDED_AT: "demo.seeded_at",
  SEED_VERSION: "demo.seed_version",
  ENVIRONMENT: "demo.environment",
});

export const DEMO_SEED_VERSION = "2026.09.1";

/** Known disposable / staging-safe project refs (extend as needed). */
const ALLOWED_STAGING_REFS = new Set([
  "rpcpdrzbcclofvjpgldb", // Contabilium staging (documented in Phase 13 DR)
]);

/**
 * Detect Production-like targets. Throws with DEMO_SEED_REFUSED.
 * `readOnly` (post-check) skips DEMO_SEED_CONFIRM but keeps every target restriction.
 * @param {{ apiUrl: string, dbUrl?: string, projectRef?: string | null, forceRemote?: boolean }} env
 * @param {{ readOnly?: boolean }} [opts]
 */
export function assertDemoSeedEnvironment(env, opts = {}) {
  if (!opts.readOnly && process.env.DEMO_SEED_CONFIRM !== "YES") {
    throw new Error(
      "DEMO_SEED_REFUSED: set DEMO_SEED_CONFIRM=YES to run the synthetic demo seed"
    );
  }

  const apiUrl = String(env.apiUrl || "");
  const dbUrl = String(env.dbUrl || "");

  if (process.env.ARCA_ENV === "production" || process.env.FISCAL_GATEWAY_ENV === "production") {
    throw new Error("DEMO_SEED_REFUSED: ARCA/FISCAL production environment detected");
  }

  const isLocal =
    /127\.0\.0\.1|localhost|0\.0\.0\.0/.test(apiUrl) ||
    /127\.0\.0\.1|localhost/.test(dbUrl);

  const ref = env.projectRef || extractProjectRef(apiUrl);
  const stagingAllowed =
    (ref && ALLOWED_STAGING_REFS.has(ref)) ||
    process.env.DEMO_SEED_ALLOW_STAGING_REF === ref;

  if (!isLocal && !stagingAllowed) {
    throw new Error(
      `DEMO_SEED_REFUSED: target is not local and project ref '${ref || "unknown"}' is not an allow-listed staging project`
    );
  }

  if (!isLocal && /supabase\.co/.test(apiUrl) && !stagingAllowed) {
    throw new Error("DEMO_SEED_REFUSED: remote Supabase host without staging allow-list");
  }

  // Explicit production project blocklist hook
  if (process.env.DEMO_SEED_BLOCK_PROJECT_REF && ref === process.env.DEMO_SEED_BLOCK_PROJECT_REF) {
    throw new Error("DEMO_SEED_REFUSED: project ref is explicitly blocked");
  }

  return {
    mode: isLocal ? "LOCAL" : "STAGING",
    projectRef: ref || (isLocal ? "local-demo" : "unknown"),
    apiUrl,
  };
}

export function extractProjectRef(apiUrl) {
  try {
    const u = new URL(apiUrl);
    // https://<ref>.supabase.co
    const m = u.hostname.match(/^([a-z0-9]+)\.supabase\.co$/i);
    return m ? m[1] : null;
  } catch {
    return null;
  }
}

/**
 * Guard: synthetic tax identifiers must not look like Argentine CUIT/CUIL.
 * Allowed: null/empty, FOREIGN_TAX_ID values starting with DEMO-, or NONE.
 */
export function assertSyntheticTaxId(value, { allowNull = true } = {}) {
  if (value == null || value === "") {
    if (allowNull) return true;
    throw new Error("SYNTHETIC_TAX_ID_GUARD: empty tax id not allowed here");
  }
  const raw = String(value).trim();
  const digits = raw.replace(/\D/g, "");
  if (digits.length === 11 && /^\d{11}$/.test(digits)) {
    throw new Error(
      "SYNTHETIC_TAX_ID_GUARD: 11-digit CUIT/CUIL-shaped values are forbidden in demo seed"
    );
  }
  if (/^\d{2}-\d{8}-\d$/.test(raw)) {
    throw new Error("SYNTHETIC_TAX_ID_GUARD: CUIT-formatted values are forbidden in demo seed");
  }
  if (!raw.toUpperCase().startsWith("DEMO") && raw.toUpperCase() !== "NONE") {
    // Prefer DEMO-* placeholders
    if (!/^DEMO[-_A-Z0-9]+$/i.test(raw) && raw !== "SYNTHETIC-NOT-A-CUIT") {
      throw new Error(
        `SYNTHETIC_TAX_ID_GUARD: tax id '${raw}' must be DEMO-* or SYNTHETIC-NOT-A-CUIT`
      );
    }
  }
  return true;
}

export function isDemoOrganizationRow(org, settingsRows = []) {
  if (!org) return false;
  const name = `${org.legal_name || ""} ${org.commercial_name || ""}`;
  if (/empresa\s+demo/i.test(name) || /\bDEMO-AR-/i.test(name)) return true;
  return settingsRows.some(
    (s) =>
      (s.key === DEMO_SETTINGS_KEYS.IS_DEMO && s.value === true) ||
      (s.key === DEMO_SETTINGS_KEYS.IS_DEMO && s.value?.demo === true) ||
      (s.key === DEMO_SETTINGS_KEYS.CODE &&
        (s.value === DEMO_CODES.PRIMARY ||
          s.value === DEMO_CODES.BETA ||
          s.value?.code === DEMO_CODES.PRIMARY ||
          s.value?.code === DEMO_CODES.BETA))
  );
}
