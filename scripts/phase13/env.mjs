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

export const LOCAL = {
  dbUrl:
    process.env.PHASE13_DB_URL ||
    "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
  apiUrl: process.env.PHASE13_API_URL || "http://127.0.0.1:54321",
  anonKey:
    process.env.PHASE13_ANON_KEY ||
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
  serviceRoleKey:
    process.env.PHASE13_SERVICE_ROLE_KEY ||
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU",
  appUrl: process.env.PHASE13_APP_URL || "http://127.0.0.1:3000",
};

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
  if (process.env.PHASE13_FORCE_REMOTE === "1" && process.env.PHASE13_API_URL) {
    return {
      dbUrl: process.env.PHASE13_DB_URL || LOCAL.dbUrl,
      apiUrl: process.env.PHASE13_API_URL,
      anonKey: process.env.PHASE13_ANON_KEY || LOCAL.anonKey,
      serviceRoleKey: process.env.PHASE13_SERVICE_ROLE_KEY || LOCAL.serviceRoleKey,
      appUrl: LOCAL.appUrl,
    };
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
