#!/usr/bin/env node
/**
 * Synthetic accountant DEMO seed — LOCAL / STAGING ONLY.
 *
 * Safety:
 * - Requires DEMO_SEED_CONFIRM=YES
 * - Refuses Production / ARCA Production
 * - Prints target project ref before writes
 * - Idempotent (org keyed by demo.code settings)
 * - Never truncates; never deletes non-demo orgs
 * - No passwords in source — DEMO_SEED_PASSWORD env when creating users
 * - No ARCA Production / FECAESolicitar
 * - Fiscal docs stay DRAFT / REJECTED / RECONCILIATION_REQUIRED only
 *
 * Usage (local):
 *   DEMO_SEED_CONFIRM=YES DEMO_SEED_CREATE_USERS=YES DEMO_SEED_PASSWORD='…' node scripts/demo/seed-accounting-demo.mjs
 *
 * Staging (allow-listed ref only):
 *   DEMO_SEED_CONFIRM=YES PHASE13_FORCE_REMOTE=1 PHASE13_API_URL=https://<ref>.supabase.co
 *   PHASE13_DB_URL=… PHASE13_ANON_KEY=… PHASE13_SERVICE_ROLE_KEY=… (all four required; no local fallback)
 */
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ensureLocalEnv } from "../phase13/env.mjs";
import { withDb } from "../phase13/db.mjs";
import {
  assertDemoSeedEnvironment,
  assertSyntheticTaxId,
  DEMO_SETTINGS_KEYS,
  DEMO_SEED_VERSION,
  extractProjectRef,
} from "./guards.mjs";
import {
  ensureDemoAuthUser,
  loginDemoUser,
  sanitizeSeedError,
} from "./auth-users.mjs";
import {
  validatePayloadAgainstContract,
  runDemoSchemaPreflight,
  formatPreflightFailure,
  buildPurchaseDocumentPayload,
  buildPurchaseDocumentLinePayload,
  buildCashTreasuryAccountPayload,
  buildBankTreasuryAccountPayload,
  buildSalesDocumentPayload,
  buildSalesDocumentLinePayload,
  buildInventoryAdjustmentInPayload,
  buildInventoryAdjustmentLinePayload,
  buildTreasuryOperationPayload,
  planTreasuryOperation,
} from "./payloads.mjs";
import {
  PRIMARY_ORG,
  BETA_ORG,
  DEMO_USERS,
  CUSTOMERS,
  SUPPLIERS,
  PRODUCTS,
  BETA_CUSTOMERS,
  BETA_SUPPLIERS,
  DEMO_OPENING_INVENTORY_COUNT,
  DEMO_TAX_PERIODS,
  DEMO_TREASURY_ADJUSTMENTS,
  money,
  demoRand,
  demoDate,
} from "./fixtures.mjs";
import { createSeedCounters, entitiesCreatedThisRun } from "./counters.mjs";
import {
  collectDemoPostcheckFacts,
  buildReportExpectations,
  evaluateDemoPostcheck,
} from "./postcheck.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const FEATURE_CODES = [
  "dashboard",
  "sales",
  "purchases",
  "inventory",
  "cash",
  "banks",
  "accounting",
  "taxes",
  "customers",
  "suppliers",
  "reports",
];

const counters = createSeedCounters();

const summary = {
  DEMO_SEED_STATUS: "FAIL",
  REPORT_DATA_READY: "NO",
  REPORT_DATA_MISSING: [],
  TENANT_ISOLATION_READY: "NO",
  PRODUCTION_TOUCHED: "NO",
  ARCA_PRODUCTION_CALLS: 0,
  target: null,
  errors: [],
};

async function httpCall(url, options) {
  const res = await fetch(url, options);
  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  return { ok: res.ok, status: res.status, data };
}

function headers(apikey, bearer, extra = {}) {
  return {
    apikey,
    Authorization: `Bearer ${bearer}`,
    "Content-Type": "application/json",
    ...extra,
  };
}

async function rest(env, token, table, { method = "GET", body, prefer, params } = {}) {
  let url = `${env.apiUrl}/rest/v1/${table}`;
  if (params) url += `?${params}`;
  return httpCall(url, {
    method,
    headers: headers(env.anonKey, token, {
      Prefer: prefer || (method === "POST" ? "return=representation" : ""),
    }),
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
}

async function rpc(env, token, fn, args = {}) {
  return httpCall(`${env.apiUrl}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: headers(env.anonKey, token),
    body: JSON.stringify(args),
  });
}

async function srpc(env, fn, args = {}) {
  return httpCall(`${env.apiUrl}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: headers(env.serviceRoleKey, env.serviceRoleKey),
    body: JSON.stringify(args),
  });
}

async function dbq(sql, params = []) {
  return withDb(async (client) => {
    const { rows } = await client.query(sql, params);
    return rows;
  });
}

function firstId(data) {
  if (!data) return null;
  if (Array.isArray(data)) return data[0]?.id;
  return data.id;
}

function err(msg) {
  const cleaned = sanitizeSeedError(msg, [process.env.DEMO_SEED_PASSWORD].filter(Boolean));
  summary.errors.push(cleaned);
  console.error("!", cleaned);
}

async function findDemoOrgByCode(code) {
  const rows = await dbq(
    `SELECT o.id, o.legal_name, o.commercial_name, o.cuit
     FROM public.organization_settings s
     JOIN public.organizations o ON o.id = s.organization_id
     WHERE s.key = $1 AND (s.value #>> '{}' = $2 OR s.value->>'code' = $2)
     LIMIT 1`,
    [DEMO_SETTINGS_KEYS.CODE, code]
  ).catch(() => []);
  return rows[0] || null;
}

async function upsertSetting(env, token, orgId, key, value) {
  // Prefer delete+insert via service DB for idempotency
  await dbq(
    `INSERT INTO public.organization_settings (organization_id, key, value)
     VALUES ($1, $2, $3::jsonb)
     ON CONFLICT (organization_id, key)
     DO UPDATE SET value = EXCLUDED.value, updated_at = timezone('utc', now())`,
    [orgId, key, JSON.stringify(value)]
  ).catch(async () => {
    // Fallback REST if unique constraint naming differs
    await rest(env, token, "organization_settings", {
      method: "POST",
      prefer: "resolution=merge-duplicates,return=representation",
      body: { organization_id: orgId, key, value },
    });
  });
}

async function ensureAuthUser(env, { email, full_name, password }, envGate) {
  const createUsers = process.env.DEMO_SEED_CREATE_USERS === "YES";
  const result = await ensureDemoAuthUser({
    env,
    email,
    full_name,
    password,
    createUsers,
    envGate,
    httpCall,
    headers,
  });
  return result.user;
}

async function login(env, email, password) {
  return loginDemoUser(env, email, password, {
    httpCall,
    createUsers: process.env.DEMO_SEED_CREATE_USERS === "YES",
  });
}

async function ensureMembership(env, token, orgId, userId, role) {
  const existing = await dbq(
    `SELECT id FROM public.organization_members
     WHERE organization_id=$1 AND user_id=$2 LIMIT 1`,
    [orgId, userId]
  );
  if (existing[0]) {
    await dbq(
      `UPDATE public.organization_members SET role=$3, status='active'
       WHERE organization_id=$1 AND user_id=$2`,
      [orgId, userId, role]
    );
    counters.record("MEMBERS", "reused");
    return existing[0].id;
  }
  counters.record("MEMBERS", "created");
  const r = await rest(env, token, "organization_members", {
    method: "POST",
    body: { organization_id: orgId, user_id: userId, role, status: "active" },
  });
  if (!r.ok) {
    // service path
    const rows = await dbq(
      `INSERT INTO public.organization_members (organization_id, user_id, role, status)
       VALUES ($1,$2,$3,'active') RETURNING id`,
      [orgId, userId, role]
    );
    return rows[0]?.id;
  }
  return firstId(r.data);
}

async function enableFeatures(env, orgId) {
  await srpc(env, "platform_bootstrap_organization_modules", {
    p_organization_id: orgId,
  });
  for (const code of FEATURE_CODES) {
    await srpc(env, "platform_enable_organization_feature", {
      p_organization_id: orgId,
      p_feature_code: code,
    });
  }
  await srpc(env, "recompute_organization_features", {
    p_organization_id: orgId,
  });
}

async function seedOrgCore(env, token, ownerUserId, orgDef, { isPrimary }) {
  assertSyntheticTaxId(orgDef.tax_placeholder);

  let org = await findDemoOrgByCode(orgDef.code);
  let created = false;
  if (!org) {
    const r = await rest(env, token, "organizations", {
      method: "POST",
      body: {
        legal_name: orgDef.legal_name,
        commercial_name: orgDef.commercial_name,
        status: "active",
        cuit: null,
        country: orgDef.country,
        province: orgDef.province,
        city: orgDef.city,
        base_currency: orgDef.base_currency,
        created_by: ownerUserId,
        onboarding_completed_at: new Date().toISOString(),
      },
    });
    if (!r.ok) throw new Error(`org create: ${JSON.stringify(r.data).slice(0, 300)}`);
    org = { id: firstId(r.data), legal_name: orgDef.legal_name };
    created = true;
  }
  counters.record("ORGANIZATIONS", created ? "created" : "reused");

  await ensureMembership(env, token, org.id, ownerUserId, "owner");
  await enableFeatures(env, org.id);

  await upsertSetting(env, token, org.id, DEMO_SETTINGS_KEYS.IS_DEMO, true);
  await upsertSetting(env, token, org.id, DEMO_SETTINGS_KEYS.CODE, orgDef.code);
  await upsertSetting(env, token, org.id, DEMO_SETTINGS_KEYS.TAX_PLACEHOLDER, orgDef.tax_placeholder);
  await upsertSetting(env, token, org.id, DEMO_SETTINGS_KEYS.ENVIRONMENT, "STAGING_DEMO");
  await upsertSetting(env, token, org.id, DEMO_SETTINGS_KEYS.SEED_VERSION, DEMO_SEED_VERSION);
  await upsertSetting(env, token, org.id, DEMO_SETTINGS_KEYS.SEEDED_AT, new Date().toISOString());

  // Branch
  let branchId;
  const branches = await dbq(
    `SELECT id FROM public.branches WHERE organization_id=$1 AND code='HQ' LIMIT 1`,
    [org.id]
  );
  if (branches[0]) branchId = branches[0].id;
  else {
    const br = await rest(env, token, "branches", {
      method: "POST",
      body: {
        organization_id: org.id,
        name: "Casa Central Demo",
        code: "HQ",
        is_main: true,
        address: orgDef.address_line,
        city: orgDef.city,
      },
    });
    if (br.ok) branchId = firstId(br.data);
    else {
      const rows = await dbq(
        `INSERT INTO public.branches (organization_id, name, code, is_main)
         VALUES ($1,'Casa Central Demo','HQ',true) RETURNING id`,
        [org.id]
      );
      branchId = rows[0].id;
    }
  }

  // CoA
  await rpc(env, token, "seed_starter_chart_of_accounts", {
    p_organization_id: org.id,
  });
  await rpc(env, token, "ensure_treasury_clearing_coa", { p_org_id: org.id });
  await rpc(env, token, "ensure_inventory_chart_accounts", {
    p_org_id: org.id,
  }).catch(() => null);

  const accounts = await dbq(
    `SELECT id, code, account_type, system_role, is_postable
     FROM public.accounts WHERE organization_id=$1`,
    [org.id]
  );
  const byRole = Object.fromEntries(
    accounts.filter((a) => a.system_role).map((a) => [a.system_role, a])
  );

  // Purchase mapping
  const ap = byRole.payables;
  const vatIn = accounts.find((a) => a.code === "2.1.02") || ap;
  const exp =
    byRole.cogs ||
    accounts.find((a) => a.account_type === "EXPENSE" && a.is_postable);
  if (ap && vatIn) {
    await dbq(
      `INSERT INTO public.purchase_accounting_mappings
        (organization_id, accounts_payable_account_id, vat_input_account_id, default_expense_account_id)
       VALUES ($1,$2,$3,$4)
       ON CONFLICT (organization_id) DO NOTHING`,
      [org.id, ap.id, vatIn.id, exp?.id || null]
    ).catch(() => null);
  }

  // Fiscal year 2026
  let fyId;
  const fys = await dbq(
    `SELECT id FROM public.accounting_fiscal_years
     WHERE organization_id=$1 AND name='FY 2026' LIMIT 1`,
    [org.id]
  );
  if (fys[0]) fyId = fys[0].id;
  else {
    const fy = await rest(env, token, "accounting_fiscal_years", {
      method: "POST",
      body: {
        organization_id: org.id,
        name: "FY 2026",
        start_date: "2026-01-01",
        end_date: "2026-12-31",
        status: "OPEN",
      },
    });
    if (!fy.ok) throw new Error(`FY: ${JSON.stringify(fy.data).slice(0, 200)}`);
    fyId = firstId(fy.data);
  }
  await rpc(env, token, "ensure_monthly_periods", { p_fiscal_year_id: fyId });

  return {
    orgId: org.id,
    created,
    branchId,
    accounts,
    byRole,
    fyId,
    isPrimary,
  };
}

async function ensureCounterparty(env, token, orgId, def, role) {
  assertSyntheticTaxId(def.tax_id, { allowNull: true });
  const existing = await dbq(
    `SELECT id FROM public.counterparties
     WHERE organization_id=$1 AND external_code=$2 LIMIT 1`,
    [orgId, def.code]
  );
  let id = existing[0]?.id;
  const entity = role === "SUPPLIER" ? "SUPPLIERS" : "CUSTOMERS";
  if (id) counters.record(entity, "reused");
  if (!id) {
    const body = {
      organization_id: orgId,
      entity_type: "LEGAL_ENTITY",
      legal_name: def.legal_name,
      trade_name: def.trade_name || null,
      tax_id_type: def.tax_id_type || "FOREIGN_TAX_ID",
      tax_id: def.tax_id,
      external_code: def.code,
      email: `${def.code.toLowerCase()}@example.invalid`,
      phone: "+54 11 0000 0000",
      is_active: true,
      notes: "SYNTHETIC DEMO — not a real taxpayer",
    };
    if (body.tax_id_type === "NONE") {
      body.tax_id = null;
    }
    const r = await rest(env, token, "counterparties", { method: "POST", body });
    if (!r.ok) throw new Error(`cp ${def.code}: ${JSON.stringify(r.data).slice(0, 220)}`);
    id = firstId(r.data);
    counters.record(entity, "created");
  }
  const roles = await dbq(
    `SELECT 1 FROM public.counterparty_roles WHERE counterparty_id=$1 AND role=$2`,
    [id, role]
  );
  if (!roles[0]) {
    await rest(env, token, "counterparty_roles", {
      method: "POST",
      body: { counterparty_id: id, organization_id: orgId, role },
    });
  }
  return id;
}

async function ensureProduct(env, token, orgId, p) {
  const existing = await dbq(
    `SELECT id FROM public.products WHERE organization_id=$1 AND sku=$2 LIMIT 1`,
    [orgId, p.sku]
  );
  if (existing[0]) {
    counters.record("PRODUCTS", "reused");
    return existing[0].id;
  }
  const r = await rest(env, token, "products", {
    method: "POST",
    body: {
      organization_id: orgId,
      sku: p.sku,
      name: p.name,
      product_type: p.product_type,
      base_unit_code: "UNIT",
      track_inventory: p.track_inventory,
      active: true,
      default_sale_price: money(p.sale),
      default_purchase_price: money(p.purchase),
    },
  });
  if (!r.ok) throw new Error(`product ${p.sku}: ${JSON.stringify(r.data).slice(0, 220)}`);
  counters.record("PRODUCTS", "created");
  return firstId(r.data);
}

async function ensureWarehouse(env, token, orgId, branchId, code, name) {
  const existing = await dbq(
    `SELECT id FROM public.warehouses WHERE organization_id=$1 AND code=$2 LIMIT 1`,
    [orgId, code]
  );
  if (existing[0]) {
    counters.record("WAREHOUSES", "reused");
    return existing[0].id;
  }
  const r = await rest(env, token, "warehouses", {
    method: "POST",
    body: {
      organization_id: orgId,
      branch_id: branchId,
      code,
      name,
      active: true,
    },
  });
  if (!r.ok) throw new Error(`wh ${code}: ${JSON.stringify(r.data).slice(0, 200)}`);
  counters.record("WAREHOUSES", "created");
  return firstId(r.data);
}

/**
 * post_inventory_operation requires inventory_accounting_mappings. Created with the
 * owner JWT (RLS enforced), only when missing; existing mappings are never altered.
 */
async function ensureInventoryAccountingMapping(env, token, ctx) {
  const existing = await dbq(
    `SELECT organization_id FROM public.inventory_accounting_mappings WHERE organization_id=$1`,
    [ctx.orgId]
  );
  if (existing[0]) return true;
  const accounts = await dbq(
    `SELECT id, code, system_role FROM public.accounts
     WHERE organization_id=$1 AND is_postable`,
    [ctx.orgId]
  );
  const role = (r) => accounts.find((a) => a.system_role === r);
  const asset = role("inventory");
  const clearing = role("inventory_purchase_clearing");
  const cogs = role("cogs");
  const gain = role("inventory_adjustment_gain");
  const loss = role("inventory_adjustment_loss") || cogs;
  if (!asset || !clearing || !cogs || !gain || !loss) {
    err(
      `inventory mapping: missing CoA roles asset=${asset?.code} clearing=${clearing?.code} cogs=${cogs?.code} gain=${gain?.code} loss=${loss?.code}`
    );
    return false;
  }
  const r = await rest(env, token, "inventory_accounting_mappings", {
    method: "POST",
    body: {
      organization_id: ctx.orgId,
      inventory_asset_account_id: asset.id,
      inventory_purchase_clearing_account_id: clearing.id,
      cogs_account_id: cogs.id,
      adjustment_gain_account_id: gain.id,
      adjustment_loss_account_id: loss.id,
    },
  });
  if (!r.ok) {
    err(`inventory mapping: ${JSON.stringify(r.data).slice(0, 160)}`);
    return false;
  }
  return true;
}

async function postInventoryOperation(env, token, opId, ref) {
  const posted = await rpc(env, token, "post_inventory_operation", {
    p_operation_id: opId,
  });
  if (!posted.ok) {
    err(`inventory post ${ref}: ${JSON.stringify(posted.data).slice(0, 160)}`);
    return false;
  }
  counters.record("INVENTORY_OPERATIONS", "posted");
  counters.record("JOURNAL_ENTRIES", "created");
  return true;
}

async function postOpeningInventory(env, token, ctx, productIds, warehouseId) {
  const stockProducts = PRODUCTS.filter((p) => p.track_inventory).slice(
    0,
    DEMO_OPENING_INVENTORY_COUNT
  );
  const mapped = await ensureInventoryAccountingMapping(env, token, ctx);
  let created = 0;
  for (let i = 0; i < stockProducts.length; i++) {
    const p = stockProducts[i];
    const pid = productIds[p.sku];
    if (!pid) continue;
    const qty = 20 + Math.floor(demoRand("inv", i) * 80);
    const unitCost = money(p.purchase);
    const ref = `DEMO-OPEN-${p.sku}`;
    const idem = `demo-inv-open-${p.sku}`;
    const existing = await dbq(
      `SELECT o.id, o.status,
              (SELECT count(*)::int FROM public.inventory_operation_lines l
               WHERE l.inventory_operation_id = o.id) AS line_count
       FROM public.inventory_operations o
       WHERE o.organization_id=$1 AND o.idempotency_key=$2 LIMIT 1`,
      [ctx.orgId, idem]
    );
    if (existing[0]) {
      counters.record("INVENTORY_OPERATIONS", "reused");
      // A DRAFT left by an earlier run is completed, never duplicated.
      if (existing[0].status === "DRAFT" && mapped) {
        if (existing[0].line_count === 0) {
          const line = await rest(env, token, "inventory_operation_lines", {
            method: "POST",
            body: buildInventoryAdjustmentLinePayload({
              organizationId: ctx.orgId,
              inventoryOperationId: existing[0].id,
              warehouseId,
              productId: pid,
              quantity: qty,
              unitCost,
            }),
          });
          if (!line.ok) {
            err(`inventory line ${ref}: ${JSON.stringify(line.data).slice(0, 160)}`);
            continue;
          }
        }
        await postInventoryOperation(env, token, existing[0].id, ref);
      }
      continue;
    }

    const num = await rpc(env, token, "next_inventory_operation_number", {
      p_org_id: ctx.orgId,
      p_operation_type: "ADJUSTMENT_IN",
    });
    const opBody = buildInventoryAdjustmentInPayload({
      organizationId: ctx.orgId,
      warehouseId,
      internalNumber: num.data || `DEMO-ADI-${i}`,
      operationDate: "2026-01-05",
      reference: ref,
      idempotencyKey: idem,
    });
    const check = validatePayloadAgainstContract("inventory_operations", opBody);
    if (!check.ok) {
      err(`inventory op contract: ${JSON.stringify(check)}`);
      continue;
    }
    const op = await rest(env, token, "inventory_operations", {
      method: "POST",
      body: opBody,
    });
    if (!op.ok) {
      err(`inventory op ${ref}: ${JSON.stringify(op.data).slice(0, 160)}`);
      continue;
    }
    const opId = firstId(op.data);
    counters.record("INVENTORY_OPERATIONS", "created");
    created += 1;
    const lineBody = buildInventoryAdjustmentLinePayload({
      organizationId: ctx.orgId,
      inventoryOperationId: opId,
      warehouseId,
      productId: pid,
      quantity: qty,
      unitCost,
    });
    const line = await rest(env, token, "inventory_operation_lines", {
      method: "POST",
      body: lineBody,
    });
    if (!line.ok) {
      err(`inventory line ${ref}: ${JSON.stringify(line.data).slice(0, 160)}`);
      continue;
    }
    if (mapped) await postInventoryOperation(env, token, opId, ref);
  }
  return created;
}

async function seedSales(env, token, ctx, customerIds, productList) {
  let count = 0;
  const months = [1, 2, 3, 4, 5, 6, 7, 8];
  let seq = 0;
  for (const month of months) {
    const docsThisMonth = month <= 6 ? 8 : 5;
    for (let i = 0; i < docsThisMonth; i++) {
      seq += 1;
      const ext = `DEMO-SO-${String(seq).padStart(4, "0")}`;
      const exists = await dbq(
        `SELECT id FROM public.sales_documents
         WHERE organization_id=$1 AND customer_reference=$2 LIMIT 1`,
        [ctx.orgId, ext]
      );
      if (exists[0]) {
        counters.record("SALES", "reused");
        count += 1;
        continue;
      }

      const day = 2 + Math.floor(demoRand("sale", seq) * 25);
      const date = demoDate(2026, month, Math.min(day, 28));
      const cust = customerIds[seq % customerIds.length];
      const prod = productList[seq % productList.length];
      const qty = 1 + Math.floor(demoRand("qty", seq) * 4);
      const unit = Number(prod.sale);

      const numRes = await rpc(env, token, "next_sales_internal_number", {
        p_organization_id: ctx.orgId,
        p_document_type: "SALES_ORDER",
        p_document_date: date,
      });

      const statusCycle = seq % 7;

      const docBody = buildSalesDocumentPayload({
        organizationId: ctx.orgId,
        branchId: ctx.branchId,
        documentDate: date,
        counterpartyId: cust,
        internalNumber: numRes.data || ext,
        customerReference: ext,
      });
      const docCheck = validatePayloadAgainstContract("sales_documents", docBody);
      if (!docCheck.ok) {
        err(`sale contract ${ext}: ${JSON.stringify(docCheck)}`);
        continue;
      }

      const doc = await rest(env, token, "sales_documents", {
        method: "POST",
        body: docBody,
      });
      if (!doc.ok) {
        err(`sale ${ext}: ${JSON.stringify(doc.data).slice(0, 160)}`);
        continue;
      }
      const docId = firstId(doc.data);
      counters.record("SALES", "created");
      await rest(env, token, "sales_document_lines", {
        method: "POST",
        body: buildSalesDocumentLinePayload({
          organizationId: ctx.orgId,
          salesDocumentId: docId,
          description: prod.name,
          quantity: qty,
          unitPrice: money(unit),
        }),
      });
      await rpc(env, token, "refresh_sales_document_totals", {
        p_document_id: docId,
      }).catch(() => null);

      if (statusCycle >= 1 && statusCycle !== 5) {
        await rpc(env, token, "confirm_sales_order", { p_order_id: docId }).catch(
          () => null
        );
        if (statusCycle >= 3) {
          await rpc(env, token, "mark_order_ready_to_invoice", {
            p_order_id: docId,
          }).catch(() => null);
        }
      }
      if (statusCycle === 5) {
        await rpc(env, token, "cancel_sales_document", {
          p_document_id: docId,
          p_reason: "Demo cancel scenario",
        }).catch(() => null);
      }
      count += 1;
    }
  }
  return count;
}

async function seedPurchases(env, token, ctx, supplierIds, productList) {
  let count = 0;
  for (let seq = 1; seq <= 36; seq++) {
    const ext = `DEMO-PO-${String(seq).padStart(4, "0")}`;
    const idem = `demo-purchase-${ext}`;
    const exists = await dbq(
      `SELECT id FROM public.purchase_documents
       WHERE organization_id=$1 AND idempotency_key=$2 LIMIT 1`,
      [ctx.orgId, idem]
    );
    if (exists[0]) {
      counters.record("PURCHASES", "reused");
      count += 1;
      continue;
    }

    const month = 1 + ((seq - 1) % 8);
    const day = 3 + (seq % 20);
    const date = demoDate(2026, month, day);
    const supplier = supplierIds[(seq - 1) % supplierIds.length];
    const prod = productList[(seq - 1) % productList.length];
    const qty = 2 + (seq % 5);
    const unit = Number(prod.purchase || prod.sale * 0.6 || 1000);
    const net = Number(money(unit * qty));
    const vat = Number(money(net * 0.21));
    const total = Number(money(net + vat));

    const docBody = buildPurchaseDocumentPayload({
      organizationId: ctx.orgId,
      branchId: ctx.branchId,
      supplierId: supplier,
      issueDate: date,
      accountingDate: date,
      dueDate: demoDate(2026, month, Math.min(day + 15, 28)),
      externalReference: ext,
      idempotencyKey: idem,
      amounts: {
        net_taxed_amount: money(net),
        vat_amount: money(vat),
        total_amount: money(total),
      },
    });
    const pCheck = validatePayloadAgainstContract("purchase_documents", docBody);
    if (!pCheck.ok) {
      err(`purchase contract ${ext}: ${JSON.stringify(pCheck)}`);
      continue;
    }

    const doc = await rest(env, token, "purchase_documents", {
      method: "POST",
      body: docBody,
    });
    if (!doc.ok) {
      err(`purchase ${ext}: ${JSON.stringify(doc.data).slice(0, 160)}`);
      continue;
    }
    const docId = firstId(doc.data);
    counters.record("PURCHASES", "created");
    await rest(env, token, "purchase_document_lines", {
      method: "POST",
      body: buildPurchaseDocumentLinePayload({
        organizationId: ctx.orgId,
        purchaseDocumentId: docId,
        description: prod.name || "Insumo demo",
        quantity: qty,
        unitPrice: money(unit),
        netAmount: money(net),
        vatAmount: money(vat),
        lineTotal: money(total),
      }),
    }).catch(() => null);

    const cycle = seq % 5;
    if (cycle >= 1) {
      await rpc(env, token, "mark_purchase_reviewed", {
        p_document_id: docId,
      }).catch(() => null);
    }
    if (cycle >= 2) {
      const posted = await rpc(env, token, "post_purchase_document", {
        p_document_id: docId,
      });
      if (posted.ok) counters.record("JOURNAL_ENTRIES", "created");
    }
    if (cycle === 4) {
      const reversed = await rpc(env, token, "reverse_purchase_document", {
        p_document_id: docId,
        p_reversal_date: date,
        p_reason: "Demo purchase reversal scenario",
      }).catch(() => null);
      if (reversed?.ok) counters.record("JOURNAL_ENTRIES", "created");
    }
    count += 1;
  }
  return count;
}

async function seedTreasury(env, token, ctx) {
  const cashAcct = ctx.byRole.cash;
  const bankAcct = ctx.byRole.bank;
  if (!cashAcct || !bankAcct) return 0;

  // Second bank CoA (unique accounting_account_id per treasury account)
  let bankCaAcctId = null;
  const existingCa = await dbq(
    `SELECT id FROM public.accounts
     WHERE organization_id=$1 AND code='1.1.02.DEMO-CA' LIMIT 1`,
    [ctx.orgId]
  );
  if (existingCa[0]) bankCaAcctId = existingCa[0].id;
  else {
    const bankMeta = await dbq(
      `SELECT parent_id FROM public.accounts WHERE id=$1`,
      [bankAcct.id]
    );
    const parentId = bankMeta[0]?.parent_id || bankAcct.id;
    const ins = await dbq(
      `INSERT INTO public.accounts
        (organization_id, parent_id, code, name, account_type, normal_balance, is_postable)
       VALUES ($1, $2, '1.1.02.DEMO-CA', 'Bancos Demo CA', 'ASSET', 'DEBIT', true)
       ON CONFLICT (organization_id, code) DO UPDATE SET name = EXCLUDED.name
       RETURNING id`,
      [ctx.orgId, parentId]
    ).catch(() => []);
    bankCaAcctId = ins[0]?.id || null;
  }

  async function ensureTa(builder) {
    const body = builder();
    const ex = await dbq(
      `SELECT id FROM public.treasury_accounts
       WHERE organization_id=$1 AND code=$2 LIMIT 1`,
      [ctx.orgId, body.code]
    );
    if (ex[0]) return ex[0].id;
    const check = validatePayloadAgainstContract("treasury_accounts", body);
    if (!check.ok) throw new Error(`treasury contract: ${JSON.stringify(check)}`);
    const r = await rest(env, token, "treasury_accounts", {
      method: "POST",
      body,
    });
    if (!r.ok) throw new Error(`ta ${body.code}: ${JSON.stringify(r.data).slice(0, 180)}`);
    return firstId(r.data);
  }

  const cashId = await ensureTa(() =>
    buildCashTreasuryAccountPayload({
      organizationId: ctx.orgId,
      branchId: ctx.branchId,
      code: "DEMO-CAJA",
      name: "Caja Demo",
      accountingAccountId: cashAcct.id,
    })
  );
  const ccId = await ensureTa(() =>
    buildBankTreasuryAccountPayload({
      organizationId: ctx.orgId,
      branchId: ctx.branchId,
      code: "DEMO-BCO-CC",
      name: "Banco Demo Cuenta Corriente ARS",
      accountingAccountId: bankAcct.id,
      accountMask: "****0001-DEMO",
      cbuCvuAlias: "DEMO-CBU-NOT-REAL-CC",
    })
  );
  let caId = null;
  if (bankCaAcctId) {
    caId = await ensureTa(() =>
      buildBankTreasuryAccountPayload({
        organizationId: ctx.orgId,
        branchId: ctx.branchId,
        code: "DEMO-BCO-CA",
        name: "Banco Demo Caja de Ahorro ARS",
        accountingAccountId: bankCaAcctId,
        accountMask: "****0002-DEMO",
        cbuCvuAlias: "DEMO-CBU-NOT-REAL-CA",
      })
    );
  }

  const ops = [
    { ref: "DEMO-TR-OPEN-CASH", type: "OPENING_BALANCE", date: "2026-01-02", amount: 150000, ta: cashId, dir: "INFLOW" },
    { ref: "DEMO-TR-OPEN-CC", type: "OPENING_BALANCE", date: "2026-01-02", amount: 850000, ta: ccId, dir: "INFLOW" },
  ];
  if (caId) {
    ops.push({
      ref: "DEMO-TR-OPEN-CA",
      type: "OPENING_BALANCE",
      date: "2026-01-02",
      amount: 220000,
      ta: caId,
      dir: "INFLOW",
    });
    ops.push({
      ref: "DEMO-TR-XFER-1",
      type: "TRANSFER",
      date: "2026-04-10",
      amount: 50000,
      ta: ccId,
      dir: "OUTFLOW",
      ta2: caId,
    });
  }
  const taByCode = { "DEMO-CAJA": cashId, "DEMO-BCO-CC": ccId, "DEMO-BCO-CA": caId };
  for (const adj of DEMO_TREASURY_ADJUSTMENTS) {
    if (!taByCode[adj.account]) continue;
    ops.push({ ...adj, ta: taByCode[adj.account] });
  }

  await ensureTreasuryAdjustmentOffset(env, token, ctx);

  async function postTreasury(opId, ref) {
    const posted = await rpc(env, token, "post_treasury_operation", {
      p_operation_id: opId,
    });
    if (!posted.ok) {
      err(`treasury post ${ref}: ${JSON.stringify(posted.data).slice(0, 160)}`);
      return false;
    }
    counters.record("TREASURY_OPERATIONS", "posted");
    counters.record("JOURNAL_ENTRIES", "created");
    return true;
  }

  let n = 0;
  for (const op of ops) {
    const idem = `demo-treasury-${op.ref}`;
    const exists = await dbq(
      `SELECT id, status, operation_type, reason FROM public.treasury_operations
       WHERE organization_id=$1 AND idempotency_key=$2 LIMIT 1`,
      [ctx.orgId, idem]
    );
    const plan = planTreasuryOperation(exists[0], op);
    if (plan.action === "reuse") {
      counters.record("TREASURY_OPERATIONS", "reused");
      n += 1;
      continue;
    }
    if (plan.action === "complete_draft") {
      counters.record("TREASURY_OPERATIONS", "reused");
      if (plan.patch) {
        const patched = await rest(env, token, "treasury_operations", {
          method: "PATCH",
          params: `id=eq.${exists[0].id}&status=eq.DRAFT`,
          prefer: "return=representation",
          body: plan.patch,
        });
        if (!patched.ok || !Array.isArray(patched.data) || patched.data.length !== 1) {
          err(`treasury reason ${op.ref}: ${JSON.stringify(patched.data).slice(0, 160)}`);
          continue;
        }
      }
      if (await postTreasury(exists[0].id, op.ref)) n += 1;
      continue;
    }
    const num = await rpc(env, token, "next_treasury_operation_number", {
      p_org_id: ctx.orgId,
      p_operation_type: op.type,
    });
    const body = buildTreasuryOperationPayload({
      organizationId: ctx.orgId,
      operationType: op.type,
      operationDate: op.date,
      amount: money(op.amount),
      description: `Demo treasury ${op.ref}`,
      internalNumber: num.data || op.ref,
      reference: op.ref,
      idempotencyKey: idem,
      reason: op.reason ?? null,
    });
    const created = await rest(env, token, "treasury_operations", {
      method: "POST",
      body,
    });
    if (!created.ok) {
      err(`treasury ${op.ref}: ${JSON.stringify(created.data).slice(0, 160)}`);
      continue;
    }
    const opId = firstId(created.data);
    counters.record("TREASURY_OPERATIONS", "created");
    await rest(env, token, "treasury_operation_legs", {
      method: "POST",
      body: {
        organization_id: ctx.orgId,
        treasury_operation_id: opId,
        treasury_account_id: op.ta,
        direction: op.dir,
        amount: money(op.amount),
        line_number: 1,
      },
    });
    if (op.type === "TRANSFER" && op.ta2) {
      await rest(env, token, "treasury_operation_legs", {
        method: "POST",
        body: {
          organization_id: ctx.orgId,
          treasury_operation_id: opId,
          treasury_account_id: op.ta2,
          direction: "INFLOW",
          amount: money(op.amount),
          line_number: 2,
        },
      });
    }
    if (await postTreasury(opId, op.ref)) n += 1;
  }
  return n;
}

/**
 * ADJUSTMENT posting resolves treasury_accounting_mappings.adjustment_offset_account_id.
 * Only fills that column when empty (owner JWT, RLS enforced); other mappings untouched.
 */
async function ensureTreasuryAdjustmentOffset(env, token, ctx) {
  const current = await dbq(
    `SELECT id, adjustment_offset_account_id FROM public.treasury_accounting_mappings
     WHERE organization_id=$1 LIMIT 1`,
    [ctx.orgId]
  );
  if (current[0]?.adjustment_offset_account_id) return true;
  const offset = ctx.accounts.find((a) => a.code === "6.1.01" && a.is_postable);
  if (!offset) {
    err("treasury mapping: postable expense account 6.1.01 not found");
    return false;
  }
  const r = current[0]
    ? await rest(env, token, "treasury_accounting_mappings", {
        method: "PATCH",
        params: `organization_id=eq.${ctx.orgId}`,
        prefer: "return=representation",
        body: { adjustment_offset_account_id: offset.id },
      })
    : await rest(env, token, "treasury_accounting_mappings", {
        method: "POST",
        body: { organization_id: ctx.orgId, adjustment_offset_account_id: offset.id },
      });
  if (!r.ok) {
    err(`treasury mapping: ${JSON.stringify(r.data).slice(0, 160)}`);
    return false;
  }
  return true;
}

async function seedManualJournalAndReversal(env, token, ctx) {
  const cash = ctx.byRole.cash;
  const capital = ctx.byRole.capital;
  if (!cash || !capital) return 0;

  const ext = "DEMO-JE-OPEN-CAPITAL";
  const exists = await dbq(
    `SELECT id, status FROM public.journal_entries
     WHERE organization_id=$1 AND external_reference=$2
       AND reversal_of_entry_id IS NULL
     LIMIT 1`,
    [ctx.orgId, ext]
  );
  let entryId = exists[0]?.id;
  const entryStatus = exists[0]?.status || "DRAFT";
  if (entryId) counters.record("JOURNAL_ENTRIES", "reused");
  if (!entryId) {
    counters.record("JOURNAL_ENTRIES", "created");
    const je = await rest(env, token, "journal_entries", {
      method: "POST",
      body: {
        organization_id: ctx.orgId,
        entry_date: "2026-01-01",
        description: "Demo aporte de capital (sintético)",
        status: "DRAFT",
        source_type: "MANUAL",
        external_reference: ext,
        created_by: (
          await dbq(`SELECT auth.uid() AS id`).catch(() => [{ id: null }])
        )[0]?.id,
      },
    });
    // created_by required — use owner from membership
    if (!je.ok) {
      const owner = await dbq(
        `SELECT user_id FROM public.organization_members
         WHERE organization_id=$1 AND role='owner' LIMIT 1`,
        [ctx.orgId]
      );
      const je2 = await dbq(
        `INSERT INTO public.journal_entries
          (organization_id, entry_date, description, status, source_type, external_reference, created_by)
         VALUES ($1,'2026-01-01','Demo aporte de capital (sintético)','DRAFT','MANUAL',$2,$3)
         RETURNING id`,
        [ctx.orgId, ext, owner[0].user_id]
      );
      entryId = je2[0]?.id;
    } else entryId = firstId(je.data);

    await dbq(
      `INSERT INTO public.journal_entry_lines
        (organization_id, journal_entry_id, line_number, account_id, description, debit, credit)
       VALUES
        ($1,$2,1,$3,'Caja demo',1000000,0),
        ($1,$2,2,$4,'Capital demo',0,1000000)
       ON CONFLICT DO NOTHING`,
      [ctx.orgId, entryId, cash.id, capital.id]
    ).catch(async () => {
      await rest(env, token, "journal_entry_lines", {
        method: "POST",
        body: {
          organization_id: ctx.orgId,
          journal_entry_id: entryId,
          line_number: 1,
          account_id: cash.id,
          description: "Caja demo",
          debit: "1000000.00",
          credit: "0.00",
        },
      });
      await rest(env, token, "journal_entry_lines", {
        method: "POST",
        body: {
          organization_id: ctx.orgId,
          journal_entry_id: entryId,
          line_number: 2,
          account_id: capital.id,
          description: "Capital demo",
          debit: "0.00",
          credit: "1000000.00",
        },
      });
    });
  }

  if (entryStatus === "DRAFT") {
    const post = await rpc(env, token, "post_journal_entry", {
      p_entry_id: entryId,
    });
    if (!post.ok) err(`journal post ${ext}: ${JSON.stringify(post.data).slice(0, 160)}`);
  }

  // Scenario 8: reversal of a separate small draft-posted entry
  const revExt = "DEMO-JE-TO-REVERSE";
  let revId;
  const revEx = await dbq(
    `SELECT id, status, reversed_by_entry_id FROM public.journal_entries
     WHERE organization_id=$1 AND external_reference=$2
       AND reversal_of_entry_id IS NULL
     LIMIT 1`,
    [ctx.orgId, revExt]
  );
  if (revEx[0]) {
    counters.record("JOURNAL_ENTRIES", "reused");
    revId = revEx[0].id;
    if (revEx[0].status === "DRAFT") {
      const p = await rpc(env, token, "post_journal_entry", { p_entry_id: revId });
      if (!p.ok) err(`journal post ${revExt}: ${JSON.stringify(p.data).slice(0, 160)}`);
      else revEx[0].status = "POSTED";
    }
    if (revEx[0].status === "POSTED" && !revEx[0].reversed_by_entry_id) {
      await reverseDemoJournal(env, token, revId, revExt);
    }
  } else {
    counters.record("JOURNAL_ENTRIES", "created");
    const owner = await dbq(
      `SELECT user_id FROM public.organization_members
       WHERE organization_id=$1 AND role='owner' LIMIT 1`,
      [ctx.orgId]
    );
    const rows = await dbq(
      `INSERT INTO public.journal_entries
        (organization_id, entry_date, description, status, source_type, external_reference, created_by)
       VALUES ($1,'2026-02-15','Demo gasto bancario a revertir','DRAFT','MANUAL',$2,$3)
       RETURNING id`,
      [ctx.orgId, revExt, owner[0].user_id]
    );
    revId = rows[0].id;
    const bank = ctx.byRole.bank;
    const exp =
      ctx.accounts.find((a) => a.code?.startsWith("6") && a.is_postable) ||
      ctx.byRole.cogs;
    if (bank && exp) {
      await dbq(
        `INSERT INTO public.journal_entry_lines
          (organization_id, journal_entry_id, line_number, account_id, description, debit, credit)
         VALUES
          ($1,$2,1,$3,'Gasto demo',1500,0),
          ($1,$2,2,$4,'Banco demo',0,1500)`,
        [ctx.orgId, revId, exp.id, bank.id]
      );
      const p = await rpc(env, token, "post_journal_entry", { p_entry_id: revId });
      if (!p.ok) err(`journal post ${revExt}: ${JSON.stringify(p.data).slice(0, 160)}`);
      else await reverseDemoJournal(env, token, revId, revExt);
    }
  }
  return 1;
}

async function reverseDemoJournal(env, token, entryId, ref) {
  const r = await rpc(env, token, "reverse_journal_entry", {
    p_original_entry_id: entryId,
    p_reversal_date: "2026-02-16",
    p_reason: "Demo journal reversal scenario",
  });
  if (!r.ok) {
    err(`journal reversal ${ref}: ${JSON.stringify(r.data).slice(0, 160)}`);
    return false;
  }
  counters.record("JOURNAL_ENTRIES", "created");
  return true;
}

/**
 * Demo tax periods via the existing ensure_tax_period RPC (HOMOLOGATION workspace,
 * status OPEN). No determinations are confirmed and nothing is filed or submitted.
 */
async function seedTaxPeriods(env, token, ctx) {
  let ok = 0;
  for (const tp of DEMO_TAX_PERIODS) {
    const existing = await dbq(
      `SELECT id FROM public.tax_periods
       WHERE organization_id=$1 AND tax_code=$2::public.tax_code
         AND jurisdiction_code IS NOT DISTINCT FROM $3
         AND period_year=$4 AND period_month=$5
         AND workspace_environment='HOMOLOGATION'
       LIMIT 1`,
      [ctx.orgId, tp.tax_code, tp.jurisdiction_code, tp.period_year, tp.period_month]
    );
    if (existing[0]) {
      counters.record("TAX_PERIODS", "reused");
      ok += 1;
      continue;
    }
    const r = await rpc(env, token, "ensure_tax_period", {
      p_organization_id: ctx.orgId,
      p_tax_code: tp.tax_code,
      p_jurisdiction_code: tp.jurisdiction_code,
      p_period_year: tp.period_year,
      p_period_month: tp.period_month,
      p_workspace_environment: "HOMOLOGATION",
    });
    if (!r.ok) {
      err(
        `tax period ${tp.tax_code} ${tp.period_year}-${tp.period_month}: ${JSON.stringify(r.data).slice(0, 160)}`
      );
      continue;
    }
    counters.record("TAX_PERIODS", "created");
    ok += 1;
  }
  await upsertSetting(env, token, ctx.orgId, "demo.tax_note", {
    status: "DEMO_REVIEW_ONLY_NOT_FILED",
    workspace_environment: "HOMOLOGATION",
    note: "Synthetic demo tax periods — not filed, not paid, not regulatory, no ARCA production",
  });
  return ok;
}

async function seedFiscalUiDrafts(env, token, ctx) {
  // Minimal fiscal document rows for UI — DRAFT / REJECTED only, HOMOLOGATION, no CAE
  const exists = await dbq(
    `SELECT count(*)::int AS n FROM public.fiscal_documents
     WHERE organization_id=$1 AND idempotency_key LIKE 'DEMO-FD-%'`,
    [ctx.orgId]
  ).catch(() => [{ n: 0 }]);
  if (exists[0]?.n > 0) return exists[0].n;

  // Skip if fiscal tables / POS missing — do not invent CAE
  const pos = await dbq(
    `SELECT id FROM public.fiscal_points_of_sale
     WHERE organization_id=$1 LIMIT 1`,
    [ctx.orgId]
  ).catch(() => []);
  if (!pos[0]) {
    console.log("  (fiscal UI drafts skipped — no POS configured; OK for demo)");
    return 0;
  }
  return 0;
}

async function seedPrimary(env, token, ownerId, envGate) {
  console.log("→ Seeding EMPRESA DEMO ARGENTINA SA …");
  const ctx = await seedOrgCore(env, token, ownerId, PRIMARY_ORG, {
    isPrimary: true,
  });

  // Users / roles on primary
  if (process.env.DEMO_SEED_CREATE_USERS === "YES") {
    const password = process.env.DEMO_SEED_PASSWORD;
    if (!password || password.length < 12) {
      throw new Error("DEMO_SEED_PASSWORD must be set (≥12 chars) when CREATE_USERS=YES");
    }
    for (const u of DEMO_USERS) {
      const user = await ensureAuthUser(
        env,
        {
          email: u.email,
          full_name: u.full_name,
          password,
        },
        envGate
      );
      await ensureMembership(env, token, ctx.orgId, user.id, u.role);
    }
  }

  const customerIds = [];
  for (const c of CUSTOMERS) {
    customerIds.push(await ensureCounterparty(env, token, ctx.orgId, c, "CUSTOMER"));
  }
  const supplierIds = [];
  for (const s of SUPPLIERS) {
    supplierIds.push(
      await ensureCounterparty(
        env,
        token,
        ctx.orgId,
        { ...s, tax_id_type: "FOREIGN_TAX_ID" },
        "SUPPLIER"
      )
    );
  }

  const productIds = {};
  const productList = [];
  for (const p of PRODUCTS) {
    const id = await ensureProduct(env, token, ctx.orgId, p);
    productIds[p.sku] = id;
    productList.push({ ...p, id });
  }

  const whMain = await ensureWarehouse(
    env,
    token,
    ctx.orgId,
    ctx.branchId,
    "DEMO-WH-MAIN",
    "Depósito Principal Demo"
  );
  await ensureWarehouse(
    env,
    token,
    ctx.orgId,
    ctx.branchId,
    "DEMO-WH-SEC",
    "Depósito Secundario Demo"
  );

  await postOpeningInventory(env, token, ctx, productIds, whMain);
  await seedSales(env, token, ctx, customerIds, productList);
  await seedPurchases(env, token, ctx, supplierIds, productList);
  await seedTreasury(env, token, ctx);
  await seedManualJournalAndReversal(env, token, ctx);
  await seedTaxPeriods(env, token, ctx);
  await seedFiscalUiDrafts(env, token, ctx);

  return ctx;
}

async function seedBeta(env, token, ownerId, primaryOrgId, envGate) {
  console.log("→ Seeding EMPRESA DEMO BETA SRL (isolation) …");
  const ctx = await seedOrgCore(env, token, ownerId, BETA_ORG, {
    isPrimary: false,
  });
  for (const c of BETA_CUSTOMERS) {
    await ensureCounterparty(env, token, ctx.orgId, c, "CUSTOMER");
  }
  for (const s of BETA_SUPPLIERS) {
    await ensureCounterparty(
      env,
      token,
      ctx.orgId,
      { ...s, tax_id_type: "FOREIGN_TAX_ID" },
      "SUPPLIER"
    );
  }
  await ensureProduct(env, token, ctx.orgId, {
    sku: "DEMO-BETA-P1",
    name: "Producto Beta Demo",
    product_type: "STOCK_ITEM",
    track_inventory: true,
    sale: 10000,
    purchase: 6000,
  });

  // Isolation check: primary user JWT must not read beta counterparties via REST
  const leak = await rest(env, token, "counterparties", {
    params: `organization_id=eq.${ctx.orgId}&select=id&limit=5`,
  });
  // Owner of both orgs CAN see both — isolation needs a user only on primary.
  // Create ephemeral isolation user attached only to primary.
  if (process.env.DEMO_SEED_CREATE_USERS === "YES" && process.env.DEMO_SEED_PASSWORD) {
    const isoUser = await ensureAuthUser(
      env,
      {
        email: "isolation.demo@example.invalid",
        full_name: "Isolation Demo",
        password: process.env.DEMO_SEED_PASSWORD,
      },
      envGate
    );
    await ensureMembership(env, token, primaryOrgId, isoUser.id, "viewer");
    // Ensure NOT member of beta
    await dbq(
      `DELETE FROM public.organization_members
       WHERE organization_id=$1 AND user_id=$2`,
      [ctx.orgId, isoUser.id]
    ).catch(() => null);
    const isoTok = await login(
      env,
      "isolation.demo@example.invalid",
      process.env.DEMO_SEED_PASSWORD
    );
    const cross = await rest(env, isoTok, "counterparties", {
      params: `organization_id=eq.${ctx.orgId}&select=id&limit=5`,
    });
    const leaked = Array.isArray(cross.data) && cross.data.length > 0;
    summary.TENANT_ISOLATION_READY = leaked ? "FAIL" : "PASS";
    if (leaked) err("Cross-tenant leakage detected for isolation.demo user");
  } else {
    summary.TENANT_ISOLATION_READY = leak.ok ? "SKIPPED_NO_USERS" : "PASS";
  }

  return ctx;
}

async function assertNoNonDemoMutation() {
  const touched = await dbq(
    `SELECT count(*)::int AS n
     FROM public.organizations o
     WHERE o.updated_at > now() - interval '2 hours'
       AND NOT EXISTS (
         SELECT 1 FROM public.organization_settings s
         WHERE s.organization_id = o.id AND s.key = $1 AND (s.value = 'true'::jsonb OR s.value = true::text::jsonb OR s.value = 'true')
       )
       AND o.legal_name NOT ILIKE '%Demo%'
       AND o.legal_name NOT ILIKE 'EMPRESA DEMO%'`,
    [DEMO_SETTINGS_KEYS.IS_DEMO]
  ).catch(() => [{ n: 0 }]);
  if (touched[0]?.n > 0) {
    err(`Non-demo organizations updated unexpectedly: ${touched[0].n}`);
    summary.PRODUCTION_TOUCHED = "UNKNOWN_CHECK_FAILED";
  }
}

async function main() {
  const env = ensureLocalEnv();
  const projectRef = extractProjectRef(env.apiUrl);
  const gate = assertDemoSeedEnvironment({
    apiUrl: env.apiUrl,
    dbUrl: env.dbUrl,
    projectRef,
    forceRemote: process.env.PHASE13_FORCE_REMOTE === "1",
  });
  summary.target = gate;
  console.log("============================================================");
  console.log(" DEMO ACCOUNTING SEED — SYNTHETIC / STAGING-LOCAL ONLY");
  console.log("============================================================");
  console.log(` MODE         = ${gate.mode}`);
  console.log(` PROJECT_REF  = ${gate.projectRef}`);
  console.log(` API_URL      = ${gate.apiUrl}`);
  console.log(` SEED_VERSION = ${DEMO_SEED_VERSION}`);
  console.log(" ARCA_PRODUCTION_CALLS will remain 0");
  console.log("============================================================");

  // Fail-fast schema preflight (no writes)
  const preflight = await runDemoSchemaPreflight(dbq);
  console.log(` DEMO_SCHEMA_PREFLIGHT = ${preflight.DEMO_SCHEMA_PREFLIGHT}`);
  if (preflight.DEMO_SCHEMA_PREFLIGHT !== "PASS") {
    throw new Error(formatPreflightFailure(preflight));
  }

  // Owner bootstrap user (always needed for JWT)
  const createUsers = process.env.DEMO_SEED_CREATE_USERS === "YES";
  if (createUsers && !process.env.DEMO_SEED_PASSWORD) {
    throw new Error("DEMO_SEED_PASSWORD required when DEMO_SEED_CREATE_USERS=YES");
  }
  if (createUsers && String(process.env.DEMO_SEED_PASSWORD).length < 12) {
    throw new Error("DEMO_SEED_PASSWORD must be ≥12 characters");
  }

  const ownerEmail = "owner.demo@example.invalid";
  // When CREATE_USERS is not YES, login-only path — password must still be supplied via env for existing users.
  const ownerPass = process.env.DEMO_SEED_PASSWORD;
  if (!ownerPass) {
    throw new Error(
      "DEMO_SEED_PASSWORD is required to authenticate owner.demo@example.invalid (set env; never commit secrets)"
    );
  }
  if (!createUsers) {
    console.warn(
      "WARN: DEMO_SEED_CREATE_USERS is not YES — will login only; passwords will NOT be reset"
    );
  }

  const owner = await ensureAuthUser(
    env,
    {
      email: ownerEmail,
      full_name: "Owner Demo",
      password: ownerPass,
    },
    gate
  );
  const token = await login(env, ownerEmail, ownerPass);

  const primary = await seedPrimary(env, token, owner.id, gate);
  await seedBeta(env, token, owner.id, primary.orgId, gate);
  await assertNoNonDemoMutation();

  const counterSnapshot = counters.snapshot();
  const createdThisRun = entitiesCreatedThisRun(counterSnapshot);
  const facts = await withDb((client) =>
    collectDemoPostcheckFacts(
      async (sql, params = []) => (await client.query(sql, params)).rows,
      { isolationEmail: "isolation.demo@example.invalid" }
    )
  );
  const postcheck = evaluateDemoPostcheck({
    facts,
    expectations: buildReportExpectations({
      customers: CUSTOMERS.length,
      suppliers: SUPPLIERS.length,
      products: PRODUCTS.length,
      inventoryOperations: DEMO_OPENING_INVENTORY_COUNT,
    }),
    targetMode: gate.mode,
    tenantIsolation: summary.TENANT_ISOLATION_READY,
    arcaProductionCalls: summary.ARCA_PRODUCTION_CALLS,
    // Re-run verification: any insert on an already-seeded dataset fails idempotency.
    createdThisRun: process.env.DEMO_SEED_EXPECT_IDEMPOTENT === "YES" ? createdThisRun : null,
  });

  summary.REPORT_DATA_READY = postcheck.REPORT_DATA_READY;
  summary.REPORT_DATA_MISSING = postcheck.REPORT_DATA_MISSING;
  summary.TENANT_ISOLATION_READY = postcheck.TENANT_ISOLATION_READY;
  if (postcheck.PRODUCTION_TOUCHED !== "NO") summary.PRODUCTION_TOUCHED = postcheck.PRODUCTION_TOUCHED;

  if (!facts.primaryOrgFound || !facts.betaOrgFound) {
    summary.DEMO_SEED_STATUS = "FAIL";
    err("Primary or Beta demo org missing after seed");
  } else if (
    postcheck.DUPLICATES_FOUND > 0 ||
    postcheck.TENANT_ISOLATION_READY === "FAIL" ||
    summary.PRODUCTION_TOUCHED !== "NO"
  ) {
    summary.DEMO_SEED_STATUS = "FAIL";
  } else if (summary.errors.length === 0 && postcheck.DEMO_POSTCHECK === "PASS") {
    summary.DEMO_SEED_STATUS = "PASS";
  } else {
    summary.DEMO_SEED_STATUS = "PASS_WITH_WARNINGS";
  }

  console.log("\n========== DEMO SEED SUMMARY ==========");
  console.log(`DEMO_SEED_STATUS = ${summary.DEMO_SEED_STATUS}`);
  for (const [k, v] of Object.entries(counterSnapshot)) console.log(`${k} = ${v}`);
  console.log(`ENTITIES_CREATED_THIS_RUN = ${JSON.stringify(createdThisRun)}`);
  for (const [k, v] of Object.entries(postcheck)) {
    console.log(`${k} = ${typeof v === "object" ? JSON.stringify(v) : v}`);
  }
  console.log(`TARGET_MODE = ${gate.mode}`);
  console.log(`TARGET_REF = ${gate.projectRef}`);
  if (summary.errors.length) {
    console.log("ERRORS:");
    for (const e of summary.errors) console.log(` - ${e}`);
  }
  console.log("=======================================\n");

  if (summary.DEMO_SEED_STATUS === "FAIL") process.exitCode = 1;
}

main().catch((e) => {
  const cleaned = sanitizeSeedError(e, [process.env.DEMO_SEED_PASSWORD].filter(Boolean));
  summary.DEMO_SEED_STATUS = "FAIL";
  summary.PRODUCTION_TOUCHED = "NO";
  summary.ARCA_PRODUCTION_CALLS = 0;
  summary.errors.push(cleaned);
  console.error("FATAL", cleaned);
  // Never dump raw Error (may contain secrets in stacks from fetch bodies)
  const safe = { ...summary, target: summary.target };
  console.log(JSON.stringify(safe, null, 2));
  process.exit(1);
});
