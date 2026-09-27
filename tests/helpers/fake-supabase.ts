/**
 * In-memory Supabase client double for unit tests.
 * Simulates tenant RLS: a row is visible only when the current user has an ACTIVE
 * membership in the row's organization (profiles: self or co-members).
 */
type Row = Record<string, unknown>;

export type FakeDb = {
  organizations: Row[];
  organization_members: Row[];
  profiles: Row[];
  [table: string]: Row[];
};

export type FakeQueryLog = { table: string; filters: [string, unknown][] }[];

export function createFakeSupabase(
  db: FakeDb,
  currentUserId: string | null,
  opts: { failSelectWithProfiles?: boolean } = {}
) {
  const log: FakeQueryLog = [];
  const inserts: { table: string; row: Row }[] = [];
  /** Simulates an unexpected DB failure on the members+profiles listing. */
  function forcedError(table: string, columns: string) {
    if (opts.failSelectWithProfiles && table === "organization_members" && /profiles/.test(columns)) {
      return { code: "XX000", message: "internal: relation organization_members secret detail" };
    }
    return null;
  }

  const activeOrgIds = () =>
    new Set(
      db.organization_members
        .filter((m) => m.user_id === currentUserId && m.status === "active")
        .map((m) => m.organization_id as string)
    );

  function visible(table: string, row: Row): boolean {
    if (!currentUserId) return false;
    const orgs = activeOrgIds();
    if (table === "organizations") return orgs.has(row.id as string);
    if (table === "profiles") {
      if (row.id === currentUserId) return true;
      return db.organization_members.some(
        (m) => m.user_id === row.id && orgs.has(m.organization_id as string)
      );
    }
    if ("organization_id" in row) return orgs.has(row.organization_id as string);
    return false;
  }

  /** organization_members → profiles FKs, as in the real schema. */
  const MEMBER_PROFILE_FKS: Record<string, string> = {
    organization_members_user_id_fkey: "user_id",
    organization_members_invited_by_fkey: "invited_by",
  };

  /** PostgREST rejects an embed that matches more than one FK (PGRST201). */
  function embedError(table: string, columns: string) {
    if (table === "organization_members" && /\bprofiles\s*\(/.test(columns)) {
      return {
        code: "PGRST201",
        message: "Could not embed because more than one relationship was found for 'organization_members' and 'profiles'",
      };
    }
    const hint = columns.match(/\bprofiles!([a-z_]+)\s*\(/);
    if (table === "organization_members" && hint && !MEMBER_PROFILE_FKS[hint[1]]) {
      return { code: "PGRST200", message: "Could not find a relationship" };
    }
    return null;
  }

  function withJoins(table: string, row: Row, columns: string): Row {
    const out: Row = { ...row };
    if (/organizations\s*\(/.test(columns) && table === "organization_members") {
      const org = db.organizations.find((o) => o.id === row.organization_id);
      out.organizations = org && visible("organizations", org) ? { ...org } : null;
    }
    const hint = columns.match(/\bprofiles!([a-z_]+)\s*\(/);
    if (hint && table === "organization_members") {
      const fkColumn = MEMBER_PROFILE_FKS[hint[1]];
      const p = db.profiles.find((x) => x.id === row[fkColumn]);
      out.profiles = p && visible("profiles", p) ? { ...p } : null;
    }
    return out;
  }

  function from(table: string) {
    const filters: [string, unknown][] = [];
    let columns = "*";
    let head = false;
    let countMode = false;
    let limitN: number | null = null;
    log.push({ table, filters });

    const run = () => {
      let rows = (db[table] ?? []).filter((r) => visible(table, r));
      for (const [col, val] of filters) rows = rows.filter((r) => r[col] === val);
      if (limitN !== null) rows = rows.slice(0, limitN);
      return rows.map((r) => withJoins(table, r, columns));
    };

    const builder = {
      select(cols = "*", opts?: { count?: string; head?: boolean }) {
        columns = cols;
        countMode = opts?.count === "exact";
        head = Boolean(opts?.head);
        return builder;
      },
      eq(col: string, val: unknown) {
        filters.push([col, val]);
        return builder;
      },
      order() {
        return builder;
      },
      limit(n: number) {
        limitN = n;
        return builder;
      },
      async maybeSingle() {
        const failure = embedError(table, columns) ?? forcedError(table, columns);
        if (failure) return { data: null, error: failure };
        const rows = run();
        return { data: rows[0] ?? null, error: null };
      },
      insert(row: Row) {
        inserts.push({ table, row });
        return Promise.resolve({ data: null, error: null });
      },
      then<T>(
        resolve: (v: {
          data: Row[] | null;
          error: { code: string; message: string } | null;
          count?: number;
        }) => T
      ) {
        const failure = embedError(table, columns) ?? forcedError(table, columns);
        if (failure) return Promise.resolve(resolve({ data: null, error: failure }));
        const rows = run();
        return Promise.resolve(
          resolve({ data: head ? null : rows, error: null, count: countMode ? rows.length : undefined })
        );
      },
    };
    return builder;
  }

  const client = {
    auth: {
      async getUser() {
        return {
          data: { user: currentUserId ? { id: currentUserId, email: `${currentUserId}@example.invalid` } : null },
          error: null,
        };
      },
    },
    from,
  };

  return { client, log, inserts };
}

export const ORG_A = "11111111-1111-4111-8111-111111111111";
export const ORG_B = "22222222-2222-4222-8222-222222222222";
export const ORG_C = "33333333-3333-4333-8333-333333333333";
export const OWNER = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
export const SOLO = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
export const OUTSIDER = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

/** Owner in A and B (like owner.demo); SOLO only in A; OUTSIDER only in C. */
export function demoDb(): FakeDb {
  return {
    organizations: [
      { id: ORG_A, legal_name: "EMPRESA DEMO ARGENTINA SA", commercial_name: "Empresa Demo", status: "active" },
      { id: ORG_B, legal_name: "EMPRESA DEMO BETA SRL", commercial_name: "Demo Beta", status: "active" },
      { id: ORG_C, legal_name: "OTRA EMPRESA SA", commercial_name: null, status: "active" },
    ],
    organization_members: [
      { id: "m1", organization_id: ORG_A, user_id: OWNER, role: "owner", status: "active" },
      { id: "m2", organization_id: ORG_B, user_id: OWNER, role: "owner", status: "active" },
      { id: "m3", organization_id: ORG_A, user_id: SOLO, role: "accountant", status: "active" },
      { id: "m4", organization_id: ORG_C, user_id: OUTSIDER, role: "owner", status: "active" },
      { id: "m5", organization_id: ORG_C, user_id: OWNER, role: "viewer", status: "inactive" },
    ],
    profiles: [
      { id: OWNER, full_name: "Owner Demo", email: "owner.demo@example.invalid" },
      { id: SOLO, full_name: "Contador Demo A", email: "contador.demo@example.invalid" },
      { id: OUTSIDER, full_name: "Outsider C", email: "outsider@example.invalid" },
    ],
    fiscal_profiles: [],
    branches: [],
    business_profiles: [],
    audit_events: [],
  };
}
