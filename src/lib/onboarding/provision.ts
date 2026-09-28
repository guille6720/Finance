import type { SupabaseClient } from "@supabase/supabase-js";
import { createAdminClient } from "@/lib/supabase/admin";

/** Modules a tester organization gets; mirrors the Staging demo organizations. */
export const PROVISIONED_FEATURES = [
  "dashboard",
  "accounting",
  "customers",
  "suppliers",
  "sales",
  "purchases",
  "cash",
  "banks",
  "inventory",
  "reports",
] as const;

export type ProvisionResult = { ok: true } | { ok: false; step: string };

type Db = SupabaseClient;

/**
 * Only the creator-owner of an organization may trigger its platform bootstrap.
 * Checked with the caller's own client, so RLS decides what is visible.
 */
async function assertCreatorOwner(supabase: Db, userId: string, organizationId: string) {
  const { data: member, error: memberError } = await supabase
    .from("organization_members")
    .select("role, status")
    .eq("organization_id", organizationId)
    .eq("user_id", userId)
    .maybeSingle();
  if (memberError || !member || member.role !== "owner" || member.status !== "active") return false;
  const { data: org, error: orgError } = await supabase
    .from("organizations")
    .select("id, created_by")
    .eq("id", organizationId)
    .maybeSingle();
  return !orgError && org?.created_by === userId;
}

export async function isOrganizationProvisioned(supabase: Db, organizationId: string) {
  const [features, accounts, years] = await Promise.all([
    supabase
      .from("organization_features")
      .select("status, feature_catalog!inner ( code )")
      .eq("organization_id", organizationId)
      .eq("status", "enabled")
      .eq("feature_catalog.code", "accounting"),
    supabase.from("accounts").select("id", { count: "exact", head: true }).eq("organization_id", organizationId),
    supabase
      .from("accounting_fiscal_years")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId),
  ]);
  if (features.error || accounts.error || years.error) return null;
  return (features.data?.length ?? 0) > 0 && (accounts.count ?? 0) > 0 && (years.count ?? 0) > 0;
}

async function grantModules(organizationId: string): Promise<string | null> {
  let admin;
  try {
    admin = createAdminClient();
  } catch {
    return "platform_unconfigured";
  }
  const boot = await admin.rpc("platform_bootstrap_organization_modules", {
    p_organization_id: organizationId,
  });
  if (boot.error) return "platform_bootstrap";
  for (const code of PROVISIONED_FEATURES) {
    const r = await admin.rpc("platform_enable_organization_feature", {
      p_organization_id: organizationId,
      p_feature_code: code,
    });
    if (r.error) return `platform_enable:${code}`;
  }
  const re = await admin.rpc("recompute_organization_features", { p_organization_id: organizationId });
  if (re.error) return "platform_recompute";
  return null;
}

async function ensureFiscalYear(supabase: Db, organizationId: string, year: number) {
  const name = `Ejercicio ${year}`;
  const { data: existing, error } = await supabase
    .from("accounting_fiscal_years")
    .select("id")
    .eq("organization_id", organizationId)
    .eq("name", name)
    .maybeSingle();
  if (error) return null;
  let id = existing?.id as string | undefined;
  if (!id) {
    const { data, error: insertError } = await supabase
      .from("accounting_fiscal_years")
      .insert({
        organization_id: organizationId,
        name,
        start_date: `${year}-01-01`,
        end_date: `${year}-12-31`,
        status: "OPEN",
      })
      .select("id")
      .single();
    if (insertError || !data) return null;
    id = data.id as string;
  }
  const periods = await supabase.rpc("ensure_monthly_periods", { p_fiscal_year_id: id });
  return periods.error ? null : id;
}

type AccountRow = { id: string; code: string; system_role: string | null; account_type: string; is_postable: boolean };

async function ensureMappings(supabase: Db, organizationId: string, accounts: AccountRow[]) {
  const byRole = (role: string) => accounts.find((a) => a.system_role === role && a.is_postable);
  const payables = byRole("payables");
  const vatInput = accounts.find((a) => a.code === "2.1.02") ?? payables;
  const expense = byRole("cogs") ?? accounts.find((a) => a.account_type === "EXPENSE" && a.is_postable);

  const { data: purchaseMap } = await supabase
    .from("purchase_accounting_mappings")
    .select("id")
    .eq("organization_id", organizationId)
    .maybeSingle();
  if (!purchaseMap && payables && vatInput) {
    const { error } = await supabase.from("purchase_accounting_mappings").insert({
      organization_id: organizationId,
      accounts_payable_account_id: payables.id,
      vat_input_account_id: vatInput.id,
      default_expense_account_id: expense?.id ?? null,
    });
    if (error) return "purchase_mapping";
  }

  const { data: invMap } = await supabase
    .from("inventory_accounting_mappings")
    .select("organization_id")
    .eq("organization_id", organizationId)
    .maybeSingle();
  const asset = byRole("inventory");
  const clearing = byRole("inventory_purchase_clearing");
  const cogs = byRole("cogs");
  const gain = byRole("inventory_adjustment_gain");
  const loss = byRole("inventory_adjustment_loss") ?? cogs;
  if (!invMap && asset && clearing && cogs && gain && loss) {
    const { error } = await supabase.from("inventory_accounting_mappings").insert({
      organization_id: organizationId,
      inventory_asset_account_id: asset.id,
      inventory_purchase_clearing_account_id: clearing.id,
      cogs_account_id: cogs.id,
      adjustment_gain_account_id: gain.id,
      adjustment_loss_account_id: loss.id,
    });
    if (error) return "inventory_mapping";
  }
  return null;
}

async function ensureOperationalDefaults(supabase: Db, organizationId: string, accounts: AccountRow[]) {
  const { data: branch } = await supabase
    .from("branches")
    .select("id")
    .eq("organization_id", organizationId)
    .order("is_main", { ascending: false })
    .limit(1)
    .maybeSingle();
  const branchId = (branch?.id as string | undefined) ?? null;

  const { data: treasury, error: treasuryError } = await supabase
    .from("treasury_accounts")
    .select("code")
    .eq("organization_id", organizationId);
  if (treasuryError) return "treasury_lookup";
  const codes = new Set((treasury ?? []).map((t) => t.code as string));
  const cash = accounts.find((a) => a.system_role === "cash" && a.is_postable);
  const bank = accounts.find((a) => a.system_role === "bank" && a.is_postable);
  const base = { organization_id: organizationId, branch_id: branchId, currency_code: "ARS", is_active: true };
  if (cash && !codes.has("CAJA")) {
    const { error } = await supabase.from("treasury_accounts").insert({
      ...base,
      account_type: "CASH",
      code: "CAJA",
      name: "Caja principal",
      accounting_account_id: cash.id,
      bank_name: null,
      account_mask: null,
      cbu_cvu_alias: null,
    });
    if (error) return "treasury_cash";
  }
  if (bank && !codes.has("BANCO")) {
    const { error } = await supabase.from("treasury_accounts").insert({
      ...base,
      account_type: "BANK",
      code: "BANCO",
      name: "Cuenta bancaria",
      accounting_account_id: bank.id,
      bank_name: "Banco (prueba)",
      account_mask: null,
      cbu_cvu_alias: null,
    });
    if (error) return "treasury_bank";
  }

  if (branchId) {
    const { data: wh } = await supabase
      .from("warehouses")
      .select("id")
      .eq("organization_id", organizationId)
      .limit(1)
      .maybeSingle();
    if (!wh) {
      const { error } = await supabase.from("warehouses").insert({
        organization_id: organizationId,
        branch_id: branchId,
        code: "PRINCIPAL",
        name: "Depósito principal",
        active: true,
      });
      if (error) return "warehouse";
    }
  }
  return null;
}

/**
 * Leaves a freshly onboarded organization ready to operate: modules granted by the
 * platform, starter chart of accounts, open fiscal year with monthly periods, posting
 * mappings, a cash box, a bank account and a warehouse. Every step is idempotent so
 * it can be retried after a partial failure.
 */
export async function provisionOrganization(
  supabase: Db,
  userId: string,
  organizationId: string,
  now = new Date()
): Promise<ProvisionResult> {
  if (!(await assertCreatorOwner(supabase, userId, organizationId))) {
    return { ok: false, step: "not_owner" };
  }

  const grantError = await grantModules(organizationId);
  if (grantError) return { ok: false, step: grantError };

  const coa = await supabase.rpc("seed_starter_chart_of_accounts", { p_organization_id: organizationId });
  if (coa.error) return { ok: false, step: "chart_of_accounts" };
  const clearing = await supabase.rpc("ensure_treasury_clearing_coa", { p_org_id: organizationId });
  if (clearing.error) return { ok: false, step: "treasury_coa" };
  // Inventory accounts are optional: without them only the inventory mapping is skipped.
  const inventoryCoa = await supabase.rpc("ensure_inventory_chart_accounts", { p_org_id: organizationId });
  if (inventoryCoa.error) {
    console.error("[provision] inventory chart skipped", { code: inventoryCoa.error.code });
  }

  if (!(await ensureFiscalYear(supabase, organizationId, now.getFullYear()))) {
    return { ok: false, step: "fiscal_year" };
  }

  const { data: accounts, error: accountsError } = await supabase
    .from("accounts")
    .select("id, code, system_role, account_type, is_postable")
    .eq("organization_id", organizationId);
  if (accountsError || !accounts) return { ok: false, step: "accounts_lookup" };

  const mappingError = await ensureMappings(supabase, organizationId, accounts as AccountRow[]);
  if (mappingError) return { ok: false, step: mappingError };
  const defaultsError = await ensureOperationalDefaults(supabase, organizationId, accounts as AccountRow[]);
  if (defaultsError) return { ok: false, step: defaultsError };

  return { ok: true };
}
