/**
 * Demo seed counters with explicit created-vs-reused semantics.
 * `*_CREATED_THIS_RUN` only counts rows inserted by the current run;
 * `*_REUSED` counts rows found by deterministic key and left untouched.
 */

export const DEMO_COUNTER_ENTITIES = Object.freeze([
  "ORGANIZATIONS",
  "MEMBERS",
  "CUSTOMERS",
  "SUPPLIERS",
  "PRODUCTS",
  "WAREHOUSES",
  "SALES",
  "PURCHASES",
  "JOURNAL_ENTRIES",
  "TREASURY_OPERATIONS",
  "INVENTORY_OPERATIONS",
  "TAX_PERIODS",
]);

/** Entities whose existing DRAFT rows may be completed (posted) on a later run. */
export const DEMO_POSTABLE_ENTITIES = Object.freeze([
  "INVENTORY_OPERATIONS",
  "TREASURY_OPERATIONS",
]);

/**
 * @param {readonly string[]} [entities]
 */
export function createSeedCounters(entities = DEMO_COUNTER_ENTITIES) {
  /** @type {Record<string, number>} */
  const values = {};
  for (const e of entities) {
    values[`${e}_CREATED_THIS_RUN`] = 0;
    values[`${e}_REUSED`] = 0;
  }
  for (const e of DEMO_POSTABLE_ENTITIES) {
    if (entities.includes(e)) values[`${e}_POSTED_THIS_RUN`] = 0;
  }

  /**
   * @param {string} entity
   * @param {"created" | "reused" | "posted"} outcome
   * @param {number} [n]
   */
  function record(entity, outcome, n = 1) {
    if (!entities.includes(entity)) {
      throw new Error(`DEMO_COUNTERS: unknown entity ${entity}`);
    }
    const suffix =
      outcome === "created"
        ? "CREATED_THIS_RUN"
        : outcome === "reused"
          ? "REUSED"
          : outcome === "posted"
            ? "POSTED_THIS_RUN"
            : null;
    if (!suffix) throw new Error(`DEMO_COUNTERS: unknown outcome ${outcome}`);
    const key = `${entity}_${suffix}`;
    if (!(key in values)) throw new Error(`DEMO_COUNTERS: ${key} not tracked`);
    values[key] += n;
  }

  return {
    record,
    snapshot: () => ({ ...values }),
  };
}

/**
 * Entities that inserted rows in this run. On an idempotent re-run this must be empty.
 * @param {Record<string, number>} snapshot
 */
export function entitiesCreatedThisRun(snapshot) {
  return Object.entries(snapshot)
    .filter(([k, v]) => k.endsWith("_CREATED_THIS_RUN") && v > 0)
    .map(([k]) => k.replace(/_CREATED_THIS_RUN$/, ""));
}
