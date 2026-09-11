-- Phase 13D — SECURITY DEFINER authz hardening: remediate 6 remaining gaps
-- Applies AFTER 20261301110000_phase13_local_hardening.sql
--
-- Policy: strengthen contracts, do not weaken.
-- No Staging writes. Local cleanroom proof only.
--
-- Analysis of each function (via pg_get_functiondef + has_function_privilege):
--
--  1. calculate_tax_period(uuid)
--       → Option B: add explicit tax_assert_role() guard at wrapper level.
--         Golden flow calls this as authenticated; callee calculate_tax_determination
--         already asserts tax_assert_role, but wrapper must be self-contained.
--
--  2. ensure_inventory_cost_row(uuid, uuid)
--       → Option A: REVOKE — internal upsert helper for inventory_cost_state.
--         No authenticated caller is legitimate; only called by post_inventory_* RPCs.
--
--  3. ensure_inventory_stock_row(uuid, uuid, uuid)
--       → Option A: REVOKE — internal upsert helper for inventory_stock_state.
--
--  4. purchase_line_inventory_debit_account(uuid, uuid, uuid)
--       → Option A: REVOKE — internal accounting lookup helper.
--         Reads products + inventory_accounting_mappings for arbitrary org_id.
--         Called only by other SECURITY DEFINER purchase posting functions.
--
--  5. tax_resolve_active_rule(tax_code, text, text, date)
--       → Option A: REVOKE — internal tax engine helper.
--         Called exclusively by calculate_tax_determination (SECURITY DEFINER).
--
--  6. tax_resolve_effective_date(tax_code, tax_source_domain, date, date, tax_rule_versions)
--       → Option A: REVOKE — pure date-resolution helper.
--         Called exclusively by calculate_tax_determination (SECURITY DEFINER).

-- ---------------------------------------------------------------------------
-- 1. calculate_tax_period — add explicit org-role assertion at wrapper level
-- ---------------------------------------------------------------------------
-- Before: thin wrapper with no auth; relied on callee's tax_assert_role.
-- After:  wrapper resolves org_id from period and calls tax_assert_role() first,
--         making the authorization contract explicit and self-contained.
-- Behavior: identical to before for legitimate callers; unauthorized callers
--           now get a clear RAISE from the wrapper, not the callee.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_tax_period(p_tax_period_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
declare
  v_org_id uuid;
begin
  -- AUTHORIZATION: resolve org from period, assert caller holds a tax-capable role.
  -- Callee (calculate_tax_determination) also asserts independently; the guard here
  -- makes this wrapper's contract self-contained and passes the security-definer audit.
  select organization_id into v_org_id
  from public.tax_periods
  where id = p_tax_period_id;

  if not found then
    raise exception 'tax period not found';
  end if;

  perform public.tax_assert_role(
    v_org_id,
    array['owner','admin','accountant']::public.member_role[]
  );

  return public.calculate_tax_determination(p_tax_period_id);
end;
$$;

comment on function public.calculate_tax_period(uuid) is
  'PHASE13 INTENTIONAL_AND_DOCUMENTED: authenticated API — tax_assert_role(owner|admin|accountant) enforced at wrapper '
  'and callee. search_path=''''. Internal: delegates to calculate_tax_determination.';

revoke all on function public.calculate_tax_period(uuid) from public;
revoke all on function public.calculate_tax_period(uuid) from anon;
grant execute on function public.calculate_tax_period(uuid) to authenticated;
grant execute on function public.calculate_tax_period(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 2. ensure_inventory_cost_row — internal upsert helper
-- ---------------------------------------------------------------------------
-- Inserts into inventory_cost_state for an arbitrary (org, product) pair.
-- Cross-tenant write risk if authenticated can call directly.
-- Called only by post_inventory_movement and related SECURITY DEFINER RPCs.
-- ---------------------------------------------------------------------------
revoke all on function public.ensure_inventory_cost_row(uuid, uuid) from public;
revoke all on function public.ensure_inventory_cost_row(uuid, uuid) from anon;
revoke all on function public.ensure_inventory_cost_row(uuid, uuid) from authenticated;
grant execute on function public.ensure_inventory_cost_row(uuid, uuid) to service_role;

comment on function public.ensure_inventory_cost_row(uuid, uuid) is
  'PHASE13 INTENTIONAL_AND_DOCUMENTED: internal inventory helper — EXECUTE revoked from anon/authenticated/public. '
  'Callable only by service_role or other SECURITY DEFINER inventory RPCs. search_path=''''.';

-- ---------------------------------------------------------------------------
-- 3. ensure_inventory_stock_row — internal upsert helper
-- ---------------------------------------------------------------------------
-- Inserts into inventory_stock_state for arbitrary (org, warehouse, product).
-- Same cross-tenant write risk as ensure_inventory_cost_row.
-- ---------------------------------------------------------------------------
revoke all on function public.ensure_inventory_stock_row(uuid, uuid, uuid) from public;
revoke all on function public.ensure_inventory_stock_row(uuid, uuid, uuid) from anon;
revoke all on function public.ensure_inventory_stock_row(uuid, uuid, uuid) from authenticated;
grant execute on function public.ensure_inventory_stock_row(uuid, uuid, uuid) to service_role;

comment on function public.ensure_inventory_stock_row(uuid, uuid, uuid) is
  'PHASE13 INTENTIONAL_AND_DOCUMENTED: internal inventory helper — EXECUTE revoked from anon/authenticated/public. '
  'Callable only by service_role or other SECURITY DEFINER inventory RPCs. search_path=''''.';

-- ---------------------------------------------------------------------------
-- 4. purchase_line_inventory_debit_account — internal accounting lookup
-- ---------------------------------------------------------------------------
-- Reads public.products and public.inventory_accounting_mappings for arbitrary org.
-- Cross-tenant read risk; called only by purchase document posting RPCs.
-- ---------------------------------------------------------------------------
revoke all on function public.purchase_line_inventory_debit_account(uuid, uuid, uuid) from public;
revoke all on function public.purchase_line_inventory_debit_account(uuid, uuid, uuid) from anon;
revoke all on function public.purchase_line_inventory_debit_account(uuid, uuid, uuid) from authenticated;
grant execute on function public.purchase_line_inventory_debit_account(uuid, uuid, uuid) to service_role;

comment on function public.purchase_line_inventory_debit_account(uuid, uuid, uuid) is
  'PHASE13 INTENTIONAL_AND_DOCUMENTED: internal purchase/accounting helper — EXECUTE revoked from anon/authenticated/public. '
  'Callable only by service_role or other SECURITY DEFINER purchase posting RPCs. search_path=''''.';

-- ---------------------------------------------------------------------------
-- 5. tax_resolve_active_rule — internal tax engine helper
-- ---------------------------------------------------------------------------
-- Reads tax_rule_versions for an arbitrary (tax_code, jurisdiction, rule_key, date).
-- Called exclusively by calculate_tax_determination (SECURITY DEFINER).
-- Revoking from authenticated prevents direct bypass of the auth wrapper.
-- ---------------------------------------------------------------------------
revoke all on function public.tax_resolve_active_rule(public.tax_code, text, text, date) from public;
revoke all on function public.tax_resolve_active_rule(public.tax_code, text, text, date) from anon;
revoke all on function public.tax_resolve_active_rule(public.tax_code, text, text, date) from authenticated;
grant execute on function public.tax_resolve_active_rule(public.tax_code, text, text, date) to service_role;

comment on function public.tax_resolve_active_rule(public.tax_code, text, text, date) is
  'PHASE13 INTENTIONAL_AND_DOCUMENTED: internal tax engine helper — EXECUTE revoked from anon/authenticated/public. '
  'Callable only by service_role or other SECURITY DEFINER tax RPCs (calculate_tax_determination). search_path=''''.';

-- ---------------------------------------------------------------------------
-- 6. tax_resolve_effective_date — internal tax date-resolution helper
-- ---------------------------------------------------------------------------
-- Pure date-resolution logic (no data written). Called exclusively by
-- calculate_tax_determination (SECURITY DEFINER). Revoke to keep the
-- call graph contained within the tax engine's SECURITY DEFINER boundary.
-- ---------------------------------------------------------------------------
revoke all on function public.tax_resolve_effective_date(
  public.tax_code, public.tax_source_domain, date, date, public.tax_rule_versions
) from public;
revoke all on function public.tax_resolve_effective_date(
  public.tax_code, public.tax_source_domain, date, date, public.tax_rule_versions
) from anon;
revoke all on function public.tax_resolve_effective_date(
  public.tax_code, public.tax_source_domain, date, date, public.tax_rule_versions
) from authenticated;
grant execute on function public.tax_resolve_effective_date(
  public.tax_code, public.tax_source_domain, date, date, public.tax_rule_versions
) to service_role;

comment on function public.tax_resolve_effective_date(
  public.tax_code, public.tax_source_domain, date, date, public.tax_rule_versions
) is
  'PHASE13 INTENTIONAL_AND_DOCUMENTED: internal tax engine helper — EXECUTE revoked from anon/authenticated/public. '
  'Callable only by service_role or other SECURITY DEFINER tax RPCs. search_path=''''.';

-- ---------------------------------------------------------------------------
-- Marker: this migration makes SECURITY_DEFINER_AUDIT UNEXPLAINED = 0
-- (pending security-definer-audit.mjs execute_revoked classification)
-- ---------------------------------------------------------------------------
insert into public.app_settings (key, value, description)
values (
  'platform.phase13.definer_authz_hardening',
  '"complete"'::jsonb,
  'Phase 13D: all 6 authenticated-callable SECURITY DEFINER gaps remediated'
)
on conflict (key) do update
  set value = excluded.value,
      description = excluded.description,
      updated_at = timezone('utc', now());
