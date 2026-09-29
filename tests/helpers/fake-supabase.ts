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

export type FakeQueryLog = {
  table: string;
  columns?: string;
  filters: [string, unknown][];
  inFilters?: [string, unknown[]][];
}[];

type Relation = { name: string; from: string; to: string; local: string; foreign: string };

/** FK relationships as they exist in the real schema (names from pg_constraint). */
const RELATIONS: Relation[] = [
  { name: "organization_members_organization_id_fkey", from: "organization_members", to: "organizations", local: "organization_id", foreign: "id" },
  { name: "organization_members_user_id_fkey", from: "organization_members", to: "profiles", local: "user_id", foreign: "id" },
  { name: "organization_members_invited_by_fkey", from: "organization_members", to: "profiles", local: "invited_by", foreign: "id" },
  { name: "fiscal_profiles_fiscal_condition_id_fkey", from: "fiscal_profiles", to: "fiscal_conditions", local: "fiscal_condition_id", foreign: "id" },
  { name: "organization_features_feature_id_fkey", from: "organization_features", to: "feature_catalog", local: "feature_id", foreign: "id" },
  { name: "counterparty_roles_counterparty_id_fkey", from: "counterparty_roles", to: "counterparties", local: "counterparty_id", foreign: "id" },
  { name: "journal_entry_lines_journal_entry_id_fkey", from: "journal_entry_lines", to: "journal_entries", local: "journal_entry_id", foreign: "id" },
  { name: "journal_entry_lines_account_id_fkey", from: "journal_entry_lines", to: "accounts", local: "account_id", foreign: "id" },
  { name: "journal_entry_lines_counterparty_tenant_fk", from: "journal_entry_lines", to: "counterparties", local: "counterparty_id", foreign: "id" },
  { name: "treasury_legs_org_op_fk", from: "treasury_operation_legs", to: "treasury_operations", local: "treasury_operation_id", foreign: "id" },
  { name: "treasury_legs_org_account_fk", from: "treasury_operation_legs", to: "treasury_accounts", local: "treasury_account_id", foreign: "id" },
  { name: "purchase_documents_journal_fk", from: "purchase_documents", to: "journal_entries", local: "journal_entry_id", foreign: "id" },
  { name: "purchase_documents_reverse_journal_fk", from: "purchase_documents", to: "journal_entries", local: "reverse_journal_entry_id", foreign: "id" },
];

/** Catalog tables readable by any authenticated user. */
const GLOBAL_TABLES = new Set(["feature_catalog", "fiscal_conditions"]);

type Embed = { key: string; relation: Relation; inner: boolean; many?: boolean };
type PgErr = { code: string; message: string; details?: string };

/** Resolves `rel ( … )`, `rel!fk ( … )`, `rel!fk!inner ( … )` like PostgREST does. */
function parseEmbeds(table: string, columns: string): { embeds: Embed[]; error: PgErr | null } {
  const embeds: Embed[] = [];
  const re = /([a-z_]+)((?:![a-z_]+)*)\s*\(/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(columns))) {
    const target = m[1];
    const modifiers = m[2].split("!").filter(Boolean);
    const inner = modifiers.includes("inner");
    const hint = modifiers.find((x) => x !== "inner" && x !== "left");
    const forward = RELATIONS.filter(
      (r) => r.from === table && r.to === target && (!hint || r.name === hint)
    );
    const reverse = RELATIONS.filter(
      (r) => r.to === table && r.from === target && (!hint || r.name === hint)
    );
    if (forward.length === 0 && reverse.length === 1) {
      embeds.push({ key: target, relation: reverse[0], inner, many: true });
      continue;
    }
    const candidates = forward;
    if (candidates.length === 0) {
      return { embeds, error: { code: "PGRST200", message: "Could not find a relationship" } };
    }
    if (candidates.length > 1) {
      return {
        embeds,
        error: {
          code: "PGRST201",
          message: `Could not embed because more than one relationship was found for '${table}' and '${target}'`,
        },
      };
    }
    embeds.push({ key: target, relation: candidates[0], inner });
  }
  return { embeds, error: null };
}

export function createFakeSupabase(
  db: FakeDb,
  currentUserId: string | null,
  opts: {
    failSelectWithProfiles?: boolean;
    failTables?: string[];
    failInserts?: Record<string, PgErr>;
    failRpcs?: Record<string, PgErr>;
    failUpdates?: Record<string, PgErr>;
    failDeletes?: Record<string, PgErr>;
    rpcHandlers?: Record<string, (args: Record<string, unknown>, db: FakeDb) => unknown>;
  } = {}
) {
  const rpcs: { name: string; args: Record<string, unknown> }[] = [];
  const log: FakeQueryLog = [];
  const inserts: { table: string; row: Row }[] = [];
  const deletes: { table: string; filters: [string, unknown][]; count: number }[] = [];
  const updates: { table: string; patch: Row; filters: [string, unknown][]; count: number }[] = [];
  let seq = 0;
  /** Simulates an unexpected DB failure (members+profiles listing, or whole tables). */
  function forcedError(table: string, columns: string) {
    if (opts.failSelectWithProfiles && table === "organization_members" && /profiles/.test(columns)) {
      return { code: "XX000", message: "internal: relation organization_members secret detail" };
    }
    if (opts.failTables?.includes(table)) {
      return { code: "XX000", message: `internal: relation ${table} secret detail` };
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
    return GLOBAL_TABLES.has(table);
  }

  function withEmbeds(row: Row, embeds: Embed[]): Row {
    const out: Row = { ...row };
    for (const e of embeds) {
      if (e.many) {
        out[e.key] = (db[e.relation.from] ?? [])
          .filter((x) => x[e.relation.local] === row[e.relation.foreign] && visible(e.relation.from, x))
          .map((x) => ({ ...x }));
        continue;
      }
      const target = (db[e.relation.to] ?? []).find(
        (x) => x[e.relation.foreign] === row[e.relation.local]
      );
      out[e.key] = target && visible(e.relation.to, target) ? { ...target } : null;
    }
    return out;
  }

  function from(table: string) {
    const filters: [string, unknown][] = [];
    const inFilters: [string, unknown[]][] = [];
    const orders: { col: string; ascending: boolean; nullsFirst: boolean }[] = [];
    let columns = "*";
    let head = false;
    let countMode = false;
    let limitN: number | null = null;
    let rangeFrom: number | null = null;
    let rangeTo: number | null = null;
    const entry = { table, columns, filters, inFilters };
    log.push(entry);

    const matches = (row: Row, col: string, test: (v: unknown) => boolean, embeds: Embed[]) => {
      const dot = col.indexOf(".");
      if (dot === -1) return { keep: test(row[col]) };
      const key = col.slice(0, dot);
      const sub = col.slice(dot + 1);
      const embedded = row[key] as Row | null | undefined;
      const embed = embeds.find((e) => e.key === key);
      if (embedded && test(embedded[sub])) return { keep: true };
      // PostgREST: an !inner embed drops the parent; a left embed is nulled out.
      if (embed?.inner) return { keep: false };
      row[key] = null;
      return { keep: true };
    };

    const run = (): { rows: Row[]; total: number } | { error: PgErr } => {
      const parsed = parseEmbeds(table, columns);
      if (parsed.error) return { error: parsed.error };
      let rows = (db[table] ?? [])
        .filter((r) => visible(table, r))
        .map((r) => withEmbeds(r, parsed.embeds));
      for (const [col, val] of filters) {
        rows = rows.filter((r) => matches(r, col, (v) => v === val, parsed.embeds).keep);
      }
      for (const [col, vals] of inFilters) {
        rows = rows.filter((r) => matches(r, col, (v) => vals.includes(v), parsed.embeds).keep);
      }
      rows = rows.filter((r) => parsed.embeds.every((e) => !e.inner || r[e.key] !== null));
      if (orders.length) {
        rows = [...rows].sort((a, b) => {
          for (const o of orders) {
            const av = a[o.col];
            const bv = b[o.col];
            if (av === bv) continue;
            if (av === null || av === undefined) return o.nullsFirst ? -1 : 1;
            if (bv === null || bv === undefined) return o.nullsFirst ? 1 : -1;
            const cmp = (av as string | number) < (bv as string | number) ? -1 : 1;
            return o.ascending ? cmp : -cmp;
          }
          return 0;
        });
      }
      const total = rows.length;
      if (rangeFrom !== null && rangeTo !== null) rows = rows.slice(rangeFrom, rangeTo + 1);
      if (limitN !== null) rows = rows.slice(0, limitN);
      return { rows, total };
    };

    const builder = {
      select(cols = "*", opts?: { count?: string; head?: boolean }) {
        columns = cols;
        entry.columns = cols;
        countMode = opts?.count === "exact";
        head = Boolean(opts?.head);
        return builder;
      },
      eq(col: string, val: unknown) {
        filters.push([col, val]);
        return builder;
      },
      in(col: string, vals: unknown[]) {
        inFilters.push([col, [...vals]]);
        return builder;
      },
      order(col: string, o?: { ascending?: boolean; nullsFirst?: boolean }) {
        const ascending = o?.ascending ?? true;
        orders.push({ col, ascending, nullsFirst: o?.nullsFirst ?? !ascending });
        return builder;
      },
      limit(n: number) {
        limitN = n;
        return builder;
      },
      range(fromIdx: number, toIdx: number) {
        rangeFrom = fromIdx;
        rangeTo = toIdx;
        return builder;
      },
      async maybeSingle() {
        const failure = forcedError(table, columns);
        if (failure) return { data: null, error: failure };
        const r = run();
        if ("error" in r) return { data: null, error: r.error };
        return { data: r.rows[0] ?? null, error: null };
      },
      async single() {
        const failure = forcedError(table, columns);
        if (failure) return { data: null, error: failure };
        const r = run();
        if ("error" in r) return { data: null, error: r.error };
        if (r.rows.length !== 1) return { data: null, error: { code: "PGRST116", message: "not single" } };
        return { data: r.rows[0], error: null };
      },
      insert(input: Row | Row[]) {
        const rows = (Array.isArray(input) ? input : [input]).map((r) => ({
          id: r.id ?? `${table}-${++seq}`,
          ...r,
        }));
        let error: PgErr | null = opts.failInserts?.[table] ?? null;
        if (!error && rows.some((r) => "organization_id" in r && !visible(table, r))) {
          error = { code: "42501", message: `new row violates row-level security policy for table "${table}"` };
        }
        if (!error) {
          for (const row of rows) {
            inserts.push({ table, row });
            (db[table] ??= []).push(row);
          }
        }
        const result = { data: null, error };
        const singleResult = { data: error ? null : { ...rows[0] }, error };
        const chain = {
          select() {
            return { single: async () => singleResult, then: (res: (v: unknown) => unknown) => Promise.resolve(res(singleResult)) };
          },
          then(res: (v: typeof result) => unknown) {
            return Promise.resolve(res(result));
          },
        };
        return chain;
      },
      update(patch: Row) {
        const apply = () => {
          const error: PgErr | null = opts.failUpdates?.[table] ?? null;
          if (error) return { data: null, error };
          const hit = (db[table] ?? []).filter(
            (r) => visible(table, r) && filters.every(([c, v]) => r[c] === v)
          );
          for (const r of hit) Object.assign(r, patch);
          updates.push({ table, patch, filters: [...filters], count: hit.length });
          return { data: hit.map((r) => ({ ...r })), error: null };
        };
        const upd = {
          eq(col: string, val: unknown) {
            filters.push([col, val]);
            return upd;
          },
          select() {
            return { then: (res: (v: unknown) => unknown) => Promise.resolve(res(apply())) };
          },
          then(res: (v: unknown) => unknown) {
            const r = apply();
            return Promise.resolve(res({ data: null, error: r.error }));
          },
        };
        return upd;
      },
      delete() {
        const del = {
          select() {
            return {
              then: (res: (v: unknown) => unknown) => {
                const error: PgErr | null = opts.failDeletes?.[table] ?? null;
                if (error) return Promise.resolve(res({ data: null, error }));
                const before = db[table] ?? [];
                const gone = before.filter(
                  (r) => visible(table, r) && filters.every(([c, v]) => r[c] === v)
                );
                db[table] = before.filter((r) => !gone.includes(r));
                deletes.push({ table, filters: [...filters], count: gone.length });
                return Promise.resolve(res({ data: gone.map((r) => ({ ...r })), error: null }));
              },
            };
          },
          eq(col: string, val: unknown) {
            filters.push([col, val]);
            return del;
          },
          then(res: (v: { data: null; error: PgErr | null }) => unknown) {
            const before = db[table] ?? [];
            const keep = before.filter(
              (r) => !(visible(table, r) && filters.every(([c, v]) => r[c] === v))
            );
            deletes.push({ table, filters: [...filters], count: before.length - keep.length });
            db[table] = keep;
            return Promise.resolve(res({ data: null, error: null }));
          },
        };
        return del;
      },
      then<T>(
        resolve: (v: {
          data: Row[] | null;
          error: { code: string; message: string } | null;
          count?: number;
        }) => T
      ) {
        const failure = forcedError(table, columns);
        if (failure) return Promise.resolve(resolve({ data: null, error: failure }));
        const r = run();
        if ("error" in r) return Promise.resolve(resolve({ data: null, error: r.error }));
        return Promise.resolve(
          resolve({ data: head ? null : r.rows, error: null, count: countMode ? r.total : undefined })
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
    async rpc(name: string, args: Record<string, unknown> = {}) {
      rpcs.push({ name, args });
      const error = opts.failRpcs?.[name] ?? null;
      const handler = opts.rpcHandlers?.[name];
      if (!error && handler) return { data: handler(args, db), error: null };
      return { data: null, error };
    },
  };

  return { client, log, inserts, deletes, updates, rpcs };
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
