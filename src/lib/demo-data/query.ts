/**
 * Query result wrappers: a failed query is never turned into an empty dataset.
 * Only the label and PostgREST error code are logged (no messages/details).
 */

export type QueryResult<T> = { ok: true; data: T } | { ok: false };

type PgError = { code?: string | null } | null | undefined;
type RowsResponse<T> = { data: T[] | null; error: PgError };
type CountResponse = { count: number | null; error: PgError };

export const PAGE_SIZE = 1000;
/** Above this, totals would be computed from a partial set → treated as a failure. */
export const MAX_ROWS = 20_000;

export function logQueryFailure(label: string, error: PgError | "row_limit") {
  console.error("[demo-data] query failed", {
    query: label,
    code: error === "row_limit" ? "ROW_LIMIT" : (error?.code ?? "UNKNOWN"),
  });
}

export async function rows<T>(
  label: string,
  query: PromiseLike<RowsResponse<T>>
): Promise<QueryResult<T[]>> {
  const { data, error } = await query;
  if (error) {
    logQueryFailure(label, error);
    return { ok: false };
  }
  return { ok: true, data: data ?? [] };
}

export async function count(
  label: string,
  query: PromiseLike<CountResponse>
): Promise<QueryResult<number>> {
  const { count: n, error } = await query;
  if (error || typeof n !== "number") {
    logQueryFailure(label, error);
    return { ok: false };
  }
  return { ok: true, data: n };
}

/** Pages through a query (which must have a stable order) until exhausted. */
export async function allRows<T>(
  label: string,
  page: (from: number, to: number) => PromiseLike<RowsResponse<T>>
): Promise<QueryResult<T[]>> {
  const out: T[] = [];
  for (let from = 0; from < MAX_ROWS; from += PAGE_SIZE) {
    const { data, error } = await page(from, from + PAGE_SIZE - 1);
    if (error) {
      logQueryFailure(label, error);
      return { ok: false };
    }
    const chunk = data ?? [];
    out.push(...chunk);
    if (chunk.length < PAGE_SIZE) return { ok: true, data: out };
  }
  logQueryFailure(label, "row_limit");
  return { ok: false };
}

export function allOk<T extends readonly QueryResult<unknown>[]>(
  results: T
): results is { [K in keyof T]: Extract<T[K], { ok: true }> } {
  return results.every((r) => r.ok);
}
