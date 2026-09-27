/**
 * Idempotent demo auth-user provisioning (LOCAL / STAGING only).
 * Password mutation is allowlist-only and requires DEMO_SEED_CREATE_USERS=YES.
 * Never logs passwords.
 */

export const DEMO_AUTH_EMAILS = Object.freeze([
  "owner.demo@example.invalid",
  "admin.demo@example.invalid",
  "contador.demo@example.invalid",
  "operador.demo@example.invalid",
  "auditor.demo@example.invalid",
  "isolation.demo@example.invalid",
]);

const DEMO_AUTH_EMAIL_SET = new Set(
  DEMO_AUTH_EMAILS.map((e) => e.toLowerCase())
);

export function isAllowlistedDemoAuthEmail(email) {
  return DEMO_AUTH_EMAIL_SET.has(String(email || "").trim().toLowerCase());
}

/**
 * Strip secrets from error/log strings.
 * @param {unknown} value
 * @param {string[]} [secrets]
 */
export function sanitizeSeedError(value, secrets = []) {
  let text =
    typeof value === "string"
      ? value
      : value instanceof Error
        ? value.message
        : JSON.stringify(value);
  if (!text) text = "unknown_error";
  const denylist = [
    ...secrets.filter(Boolean),
    process.env.DEMO_SEED_PASSWORD,
    process.env.PHASE13_SERVICE_ROLE_KEY,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
  ].filter(Boolean);
  for (const s of denylist) {
    if (!s || s.length < 4) continue;
    text = text.split(s).join("[REDACTED]");
  }
  // JWT-ish / bearer tokens
  text = text.replace(
    /eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/g,
    "[REDACTED_JWT]"
  );
  text = text.replace(/Bearer\s+[^\s"']+/gi, "Bearer [REDACTED]");
  return text.slice(0, 500);
}

/**
 * Credential mutation gate.
 * @param {{
 *   email: string,
 *   createUsers: boolean,
 *   envGate: { mode: "LOCAL" | "STAGING" },
 *   confirm: boolean,
 *   arcaEnv?: string | null,
 *   fiscalEnv?: string | null,
 * }} opts
 */
export function assertDemoAuthMutationAllowed(opts) {
  const email = String(opts.email || "").trim().toLowerCase();
  if (!opts.confirm) {
    throw new Error("DEMO_AUTH_REFUSED: DEMO_SEED_CONFIRM must be YES");
  }
  if (opts.arcaEnv === "production" || opts.fiscalEnv === "production") {
    throw new Error("DEMO_AUTH_REFUSED: production fiscal/ARCA environment");
  }
  if (!opts.envGate || (opts.envGate.mode !== "LOCAL" && opts.envGate.mode !== "STAGING")) {
    throw new Error("DEMO_AUTH_REFUSED: environment mode must be LOCAL or STAGING");
  }
  if (!opts.createUsers) {
    throw new Error(
      "DEMO_AUTH_REFUSED: credential create/update requires DEMO_SEED_CREATE_USERS=YES"
    );
  }
  if (!isAllowlistedDemoAuthEmail(email)) {
    throw new Error(
      `DEMO_AUTH_REFUSED: email is not an allowlisted demo identity (${email || "empty"})`
    );
  }
  return true;
}

/**
 * Pure decision helper for tests / orchestration.
 * @returns {"create"|"update_password"|"login_only"|"refuse"}
 */
export function decideDemoAuthAction({
  userExists,
  createUsers,
  email,
  envGate,
  confirm,
  arcaEnv,
  fiscalEnv,
}) {
  if (!isAllowlistedDemoAuthEmail(email)) {
    return "refuse";
  }
  if (arcaEnv === "production" || fiscalEnv === "production") {
    return "refuse";
  }
  if (!confirm || !envGate || (envGate.mode !== "LOCAL" && envGate.mode !== "STAGING")) {
    return "refuse";
  }
  if (!createUsers) {
    return "login_only";
  }
  return userExists ? "update_password" : "create";
}

/**
 * Ensure allowlisted demo user exists and matches current password when CREATE_USERS=YES.
 *
 * @param {{
 *   env: { apiUrl: string, serviceRoleKey: string, anonKey: string },
 *   email: string,
 *   full_name: string,
 *   password: string,
 *   createUsers: boolean,
 *   envGate: { mode: "LOCAL" | "STAGING" },
 *   httpCall: Function,
 *   headers: Function,
 * }} args
 */
export async function ensureDemoAuthUser(args) {
  const {
    env,
    email,
    full_name,
    password,
    createUsers,
    envGate,
    httpCall,
    headers,
  } = args;

  const normalizedEmail = String(email).trim().toLowerCase();
  const confirm = process.env.DEMO_SEED_CONFIRM === "YES";
  const arcaEnv = process.env.ARCA_ENV || null;
  const fiscalEnv = process.env.FISCAL_GATEWAY_ENV || null;

  // Find existing user via admin list (paginated first page is enough for tiny demo set;
  // also try email filter if supported).
  const list = await httpCall(
    `${env.apiUrl}/auth/v1/admin/users?page=1&per_page=200`,
    { method: "GET", headers: headers(env.serviceRoleKey, env.serviceRoleKey) }
  );
  const users = Array.isArray(list.data?.users) ? list.data.users : [];
  const existing = users.find(
    (u) => String(u.email || "").toLowerCase() === normalizedEmail
  );

  const action = decideDemoAuthAction({
    userExists: Boolean(existing),
    createUsers,
    email: normalizedEmail,
    envGate,
    confirm,
    arcaEnv,
    fiscalEnv,
  });

  if (action === "refuse") {
    throw new Error(
      sanitizeSeedError(
        `DEMO_AUTH_REFUSED: cannot provision ${normalizedEmail} in this context`
      )
    );
  }

  if (action === "login_only") {
    if (!existing) {
      throw new Error(
        `DEMO_AUTH_LOGIN_ONLY: user ${normalizedEmail} does not exist. Re-run with DEMO_SEED_CREATE_USERS=YES and DEMO_SEED_PASSWORD set.`
      );
    }
    return { user: existing, action: "login_only", created: false, passwordUpdated: false };
  }

  // Mutation path — re-assert guards
  assertDemoAuthMutationAllowed({
    email: normalizedEmail,
    createUsers: true,
    envGate,
    confirm,
    arcaEnv,
    fiscalEnv,
  });

  if (!password || String(password).length < 12) {
    throw new Error(
      "DEMO_AUTH_REFUSED: DEMO_SEED_PASSWORD required (≥12 chars) when DEMO_SEED_CREATE_USERS=YES"
    );
  }

  if (action === "create") {
    const created = await httpCall(`${env.apiUrl}/auth/v1/admin/users`, {
      method: "POST",
      headers: headers(env.serviceRoleKey, env.serviceRoleKey),
      body: JSON.stringify({
        email: normalizedEmail,
        password,
        email_confirm: true,
        user_metadata: { full_name, demo: true, seed: "accounting-demo" },
      }),
    });
    if (!created.ok) {
      throw new Error(
        sanitizeSeedError(
          `create user ${normalizedEmail} failed: status=${created.status} body=${JSON.stringify(created.data).slice(0, 180)}`,
          [password]
        )
      );
    }
    return {
      user: created.data,
      action: "create",
      created: true,
      passwordUpdated: false,
    };
  }

  // update_password
  const uid = existing.id;
  const updated = await httpCall(`${env.apiUrl}/auth/v1/admin/users/${uid}`, {
    method: "PUT",
    headers: headers(env.serviceRoleKey, env.serviceRoleKey),
    body: JSON.stringify({
      password,
      email_confirm: true,
      user_metadata: {
        ...(existing.user_metadata || {}),
        full_name,
        demo: true,
        seed: "accounting-demo",
      },
    }),
  });
  if (!updated.ok) {
    throw new Error(
      sanitizeSeedError(
        `update password for ${normalizedEmail} failed: status=${updated.status}`,
        [password]
      )
    );
  }
  return {
    user: updated.data || existing,
    action: "update_password",
    created: false,
    passwordUpdated: true,
  };
}

/**
 * Password grant login. Never echoes password.
 */
export async function loginDemoUser(env, email, password, { httpCall, createUsers }) {
  const r = await httpCall(`${env.apiUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey: env.anonKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ email, password }),
  });
  if (r.ok) return r.data.access_token;

  const code = r.data?.error_code || r.data?.error || r.status;
  if (!createUsers) {
    throw new Error(
      sanitizeSeedError(
        `login failed for ${email} (${code}). Credentials were NOT mutated because DEMO_SEED_CREATE_USERS is not YES. Fix password or re-run with DEMO_SEED_CREATE_USERS=YES.`
      )
    );
  }
  throw new Error(
    sanitizeSeedError(
      `login failed for ${email} after provision (${code}). Check GoTrue admin API / email confirmation.`,
      [password]
    )
  );
}
