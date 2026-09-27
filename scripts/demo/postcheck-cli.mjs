#!/usr/bin/env node
/**
 * Read-only demo post-check (LOCAL / allow-listed STAGING). Performs SELECTs only.
 * Usage: node scripts/demo/postcheck-cli.mjs
 */
import { ensureLocalEnv } from "../phase13/env.mjs";
import { withDb } from "../phase13/db.mjs";
import { assertDemoSeedEnvironment, extractProjectRef } from "./guards.mjs";
import { CUSTOMERS, SUPPLIERS, PRODUCTS, DEMO_OPENING_INVENTORY_COUNT } from "./fixtures.mjs";
import {
  collectDemoPostcheckFacts,
  buildReportExpectations,
  evaluateDemoPostcheck,
} from "./postcheck.mjs";

const ISOLATION_EMAIL = "isolation.demo@example.invalid";

async function main() {
  const env = ensureLocalEnv();
  const gate = assertDemoSeedEnvironment(
    { apiUrl: env.apiUrl, dbUrl: env.dbUrl, projectRef: extractProjectRef(env.apiUrl) },
    { readOnly: true }
  );
  const facts = await withDb((client) =>
    collectDemoPostcheckFacts(
      async (sql, params = []) => (await client.query(sql, params)).rows,
      { isolationEmail: ISOLATION_EMAIL }
    )
  );
  const result = evaluateDemoPostcheck({
    facts,
    expectations: buildReportExpectations({
      customers: CUSTOMERS.length,
      suppliers: SUPPLIERS.length,
      products: PRODUCTS.length,
      inventoryOperations: DEMO_OPENING_INVENTORY_COUNT,
    }),
    targetMode: gate.mode,
    tenantIsolation: facts.isolationUserInBeta === false ? "PASS" : "NOT_VERIFIED",
    arcaProductionCalls: 0,
  });

  console.log(`TARGET_MODE = ${gate.mode}`);
  console.log(`TARGET_REF = ${gate.projectRef}`);
  for (const [k, v] of Object.entries(result)) {
    console.log(`${k} = ${typeof v === "object" ? JSON.stringify(v) : v}`);
  }
  if (facts.primary) console.log(`PRIMARY_FACTS = ${JSON.stringify(facts.primary)}`);
  if (result.DEMO_POSTCHECK !== "PASS") process.exitCode = 1;
}

main().catch((e) => {
  console.error("DEMO_POSTCHECK = FAIL");
  console.error(String(e?.message || e).slice(0, 300));
  process.exit(1);
});
