import { execSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.resolve(__dirname, "../..");
export const MIGRATIONS_DIR = path.join(ROOT, "supabase", "migrations");
export const PHASE13_DIR = path.join(ROOT, "docs", "qa", "phase13");
export const EXPECTED_FINGERPRINT_PATH = path.join(
  PHASE13_DIR,
  "schema-fingerprint.expected.json"
);
export const PROVENANCE_PATH = path.join(PHASE13_DIR, "migration-provenance.json");
export const STATUS_PATH = path.join(PHASE13_DIR, "PHASE-13-STATUS.md");

const LOCAL_DEMO_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";
const LOCAL_DEMO_SERVICE_ROLE_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";

export const LOCAL = {
  dbUrl:
    process.env.PHASE13_DB_URL ||
    "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
  apiUrl: process.env.PHASE13_API_URL || "http://127.0.0.1:54321",
  anonKey: process.env.PHASE13_ANON_KEY || LOCAL_DEMO_ANON_KEY,
  serviceRoleKey: process.env.PHASE13_SERVICE_ROLE_KEY || LOCAL_DEMO_SERVICE_ROLE_KEY,
  appUrl: process.env.PHASE13_APP_URL || "http://127.0.0.1:3000",
};

/** Supabase projects that remote mode may target by default (Contabilium Staging). */
export const ALLOWED_REMOTE_STAGING_REFS = Object.freeze(["rpcpdrzbcclofvjpgldb"]);

export const REMOTE_REQUIRED_VARS = Object.freeze([
  "PHASE13_API_URL",
  "PHASE13_DB_URL",
  "PHASE13_ANON_KEY",
  "PHASE13_SERVICE_ROLE_KEY",
]);

const LOCAL_HOST_RE = /^(localhost|127\.\d+\.\d+\.\d+|0\.0\.0\.0|::1|\[::1\]|host\.docker\.internal)$/i;

function remoteError(message) {
  return new Error(`REMOTE_ENV_INCOMPLETE: ${message}`);
}

/** Project ref from https://<ref>.supabase.co */
function apiProjectRef(hostname) {
  const m = hostname.match(/^([a-z0-9]{20})\.supabase\.co$/i);
  return m ? m[1].toLowerCase() : null;
}

/** Project ref from db.<ref>.supabase.co or pooler user postgres.<ref>. */
function dbProjectRef(url) {
  const direct = url.hostname.match(/^db\.([a-z0-9]{20})\.supabase\.co$/i);
  if (direct) return direct[1].toLowerCase();
  if (/\.pooler\.supabase\.com$/i.test(url.hostname)) {
    const user = decodeURIComponent(url.username || "");
    const m = user.match(/^[a-z_]+\.([a-z0-9]{20})$/i);
    if (m) return m[1].toLowerCase();
  }
  return null;
}

/**
 * Remote (PHASE13_FORCE_REMOTE=1) env resolution. Fails closed: never falls back to
 * LOCAL values. Errors name variables/refs only, never values.
 * Extra non-staging refs (e.g. disposable DR projects) require PHASE13_REMOTE_ALLOWED_REF.
 * @param {Record<string, string | undefined>} [vars]
 */
export function resolveRemoteEnv(vars = process.env) {
  for (const name of REMOTE_REQUIRED_VARS) {
    const v = vars[name];
    if (typeof v !== "string" || v.trim() === "") {
      throw remoteError(`${name} is required when PHASE13_FORCE_REMOTE=1`);
    }
  }

  if (vars.ARCA_ENV === "production" || vars.FISCAL_GATEWAY_ENV === "production") {
    throw remoteError("ARCA/FISCAL production environment is not allowed in remote mode");
  }

  let api;
  try {
    api = new URL(String(vars.PHASE13_API_URL).trim());
  } catch {
    throw remoteError("PHASE13_API_URL is not a valid URL");
  }
  if (api.protocol !== "https:") {
    throw remoteError("PHASE13_API_URL must use https in remote mode");
  }
  if (LOCAL_HOST_RE.test(api.hostname)) {
    throw remoteError("PHASE13_API_URL must not be a local host in remote mode");
  }
  const ref = apiProjectRef(api.hostname);
  if (!ref) {
    throw remoteError("PHASE13_API_URL must be https://<project-ref>.supabase.co");
  }
  const allowed = new Set(ALLOWED_REMOTE_STAGING_REFS);
  const extra = String(vars.PHASE13_REMOTE_ALLOWED_REF || "").trim().toLowerCase();
  if (extra) allowed.add(extra);
  const blocked = [vars.PHASE13_BLOCK_PROJECT_REF, vars.DEMO_SEED_BLOCK_PROJECT_REF]
    .map((r) => String(r || "").trim().toLowerCase())
    .filter(Boolean);
  if (blocked.includes(ref)) {
    throw remoteError(`project ref '${ref}' is explicitly blocked`);
  }
  if (!allowed.has(ref)) {
    throw remoteError(`project ref '${ref}' is not an allow-listed remote project`);
  }

  let db;
  try {
    db = new URL(String(vars.PHASE13_DB_URL).trim());
  } catch {
    throw remoteError("PHASE13_DB_URL is not a valid URL");
  }
  if (db.protocol !== "postgresql:" && db.protocol !== "postgres:") {
    throw remoteError("PHASE13_DB_URL must be a postgresql:// URL");
  }
  if (LOCAL_HOST_RE.test(db.hostname) || db.hostname === "") {
    throw remoteError("PHASE13_DB_URL must not point to a local host in remote mode");
  }
  const dbRef = dbProjectRef(db);
  if (!dbRef) {
    throw remoteError(
      "PHASE13_DB_URL host must be db.<ref>.supabase.co or a Supabase pooler with user postgres.<ref>"
    );
  }
  if (dbRef !== ref) {
    throw remoteError("PHASE13_DB_URL project ref does not match PHASE13_API_URL project ref");
  }

  const anonKey = String(vars.PHASE13_ANON_KEY).trim();
  const serviceRoleKey = String(vars.PHASE13_SERVICE_ROLE_KEY).trim();
  if (anonKey === LOCAL_DEMO_ANON_KEY || serviceRoleKey === LOCAL_DEMO_SERVICE_ROLE_KEY) {
    throw remoteError("local Supabase demo keys cannot be used in remote mode");
  }
  if (anonKey === serviceRoleKey) {
    throw remoteError("PHASE13_ANON_KEY and PHASE13_SERVICE_ROLE_KEY must differ");
  }

  return {
    dbUrl: String(vars.PHASE13_DB_URL).trim(),
    apiUrl: api.origin,
    anonKey,
    serviceRoleKey,
    appUrl: vars.PHASE13_APP_URL || "http://127.0.0.1:3000",
    projectRef: ref,
    mode: "REMOTE",
  };
}

export function supabaseStatus() {
  try {
    const raw = execSync("npx supabase status -o env", {
      cwd: ROOT,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      timeout: 8000,
    });
    const map = {};
    for (const line of raw.split(/\r?\n/)) {
      const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
      if (!m) continue;
      map[m[1]] = m[2].replace(/^"|"$/g, "");
    }
    return map;
  } catch {
    return null;
  }
}

export function ensureLocalEnv() {
  if (process.env.PHASE13_FORCE_REMOTE === "1") {
    return resolveRemoteEnv(process.env);
  }
  const st = supabaseStatus();
  if (st?.DB_URL) {
    return {
      dbUrl: st.DB_URL,
      apiUrl: st.API_URL,
      anonKey: st.ANON_KEY,
      serviceRoleKey: st.SERVICE_ROLE_KEY,
      appUrl: LOCAL.appUrl,
    };
  }
  // Fallback: published local demo defaults (disposable stack).
  return { ...LOCAL };
}
