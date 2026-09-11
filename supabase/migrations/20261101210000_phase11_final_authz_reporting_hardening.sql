-- Phase 11 STAGING: final authz / reporting / RLS initplan hardening
-- Additive only. Do not modify older migrations.
-- search_path='' everywhere. Money: numeric(19,4). No FLOAT.

-- =============================================================================
-- 1) saved_reports RLS: (select auth.uid()) initplan fix
-- =============================================================================

drop policy if exists saved_reports_select on public.saved_reports;
create policy saved_reports_select on public.saved_reports
  for select to authenticated
  using (
    public.is_org_member(organization_id)
    and (
      visibility = 'ORGANIZATION'::public.saved_report_visibility
      or owner_user_id = (select auth.uid())
    )
  );
drop policy if exists saved_reports_insert on public.saved_reports;
create policy saved_reports_insert on public.saved_reports
  for insert to authenticated
  with check (
    public.is_org_member(organization_id)
    and owner_user_id = (select auth.uid())
  );
drop policy if exists saved_reports_update on public.saved_reports;
create policy saved_reports_update on public.saved_reports
  for update to authenticated
  using (
    owner_user_id = (select auth.uid())
    and public.is_org_member(organization_id)
  )
  with check (
    owner_user_id = (select auth.uid())
    and public.is_org_member(organization_id)
  );
drop policy if exists saved_reports_delete on public.saved_reports;
create policy saved_reports_delete on public.saved_reports
  for delete to authenticated
  using (
    owner_user_id = (select auth.uid())
    and public.is_org_member(organization_id)
  );
-- =============================================================================
-- 2) analytics_capability enum + helpers
-- =============================================================================

do $$ begin
  create type public.analytics_capability as enum (
    'DASHBOARD_BASIC',
    'DASHBOARD_FINANCIAL',
    'DASHBOARD_TAX',
    'DASHBOARD_INVENTORY',
    'DASHBOARD_POS_SENSITIVE',
    'REPORT_FINANCIAL',
    'REPORT_TAX',
    'REPORT_OPERATIONAL',
    'ALERT_READ',
    'ALERT_ACK',
    'ALERT_EVALUATE'
  );
exception when duplicate_object then null;
end $$;
create or replace function public.analytics_member_role(p_org_id uuid)
returns public.member_role
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
  from public.organization_members m
  where m.organization_id = p_org_id
    and m.user_id = (select auth.uid())
    and m.status = 'active'
  limit 1;
$$;
revoke all on function public.analytics_member_role(uuid) from public, anon, authenticated;
create or replace function public.analytics_has_capability(
  p_org_id uuid,
  p_capability public.analytics_capability
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role public.member_role;
begin
  v_role := public.analytics_member_role(p_org_id);
  if v_role is null then
    return false;
  end if;

  return case p_capability
    when 'DASHBOARD_BASIC'::public.analytics_capability then
      v_role in (
        'owner'::public.member_role, 'admin'::public.member_role,
        'manager'::public.member_role, 'accountant'::public.member_role,
        'operator'::public.member_role, 'viewer'::public.member_role
      )
    when 'DASHBOARD_FINANCIAL'::public.analytics_capability then
      v_role in (
        'owner'::public.member_role, 'admin'::public.member_role,
        'manager'::public.member_role, 'accountant'::public.member_role
      )
    when 'DASHBOARD_TAX'::public.analytics_capability then
      v_role in (
        'owner'::public.member_role, 'admin'::public.member_role,
        'accountant'::public.member_role
      )
    when 'DASHBOARD_INVENTORY'::public.analytics_capability then
      v_role in (
        'owner'::public.member_role, 'admin'::public.member_role,
        'manager'::public.member_role, 'accountant'::public.member_role
      )
    when 'DASHBOARD_POS_SENSITIVE'::public.analytics_capability then
      v_role in (
        'owner'::public.member_role, 'admin'::public.member_role,
        'manager'::public.member_role
      )
    when 'REPORT_FINANCIAL'::public.analytics_capability then
      v_role in (
        'owner'::public.member_role, 'admin'::public.member_role,
        'manager'::public.member_role, 'accountant'::public.member_role
      )
    when 'REPORT_TAX'::public.analytics_capability then
      v_role in (
        'owner'::public.member_role, 'admin'::public.member_role,
        'accountant'::public.member_role
      )
    when 'REPORT_OPERATIONAL'::public.analytics_capability then
      v_role in (
        'owner'::public.member_role, 'admin'::public.member_role,
        'manager'::public.member_role, 'accountant'::public.member_role
      )
    when 'ALERT_READ'::public.analytics_capability then
      v_role in (
        'owner'::public.member_role, 'admin'::public.member_role,
        'manager'::public.member_role, 'accountant'::public.member_role,
        'operator'::public.member_role
      )
    when 'ALERT_ACK'::public.analytics_capability then
      v_role in (
        'owner'::public.member_role, 'admin'::public.member_role,
        'manager'::public.member_role, 'accountant'::public.member_role
      )
    when 'ALERT_EVALUATE'::public.analytics_capability then
      v_role in (
        'owner'::public.member_role, 'admin'::public.member_role,
        'manager'::public.member_role, 'accountant'::public.member_role
      )
    else false
  end;
end;
$$;
revoke all on function public.analytics_has_capability(uuid, public.analytics_capability)
  from public, anon, authenticated;
create or replace function public.analytics_assert_capability(
  p_org_id uuid,
  p_capability public.analytics_capability
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.analytics_has_capability(p_org_id, p_capability) then
    raise exception 'insufficient analytics capability: %', p_capability::text;
  end if;
end;
$$;
revoke all on function public.analytics_assert_capability(uuid, public.analytics_capability)
  from public, anon, authenticated;
-- =============================================================================
-- 3) get_dashboard_summary — capability-gated tiles
-- =============================================================================

create or replace function public.get_dashboard_summary(
  p_organization_id uuid,
  p_period_preset text default 'THIS_MONTH',
  p_from date default null,
  p_to date default null,
  p_compare_mode text default 'PREV_PERIOD'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_start date;
  v_end date;
  v_pstart date;
  v_pend date;
  v_now timestamptz := timezone('utc', now());
  v_metrics jsonb := '{}'::jsonb;
  v_sections jsonb;
  v_do_compare boolean := upper(coalesce(p_compare_mode, 'PREV_PERIOD')) = 'PREV_PERIOD';
  v_feat_taxes boolean;
  v_feat_inventory boolean;
  v_feat_pos boolean;
  v_feat_fiscal boolean;
  v_feat_cash boolean;
  v_feat_banks boolean;
  v_feat_accounting boolean;
  v_feat_purchases boolean;
  v_feat_sales boolean;
  v_cap_fin boolean;
  v_cap_tax boolean;
  v_cap_inv boolean;
  v_cap_alert boolean;
  v_val numeric(19, 4);
  v_prev numeric(19, 4);
  v_pnl jsonb;
  v_tax numeric(19, 4);
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, 'dashboard');
  perform public.analytics_assert_capability(
    p_organization_id, 'DASHBOARD_BASIC'::public.analytics_capability
  );

  select pb.period_start, pb.period_end into v_start, v_end
  from public.analytics_period_bounds(p_organization_id, p_period_preset, p_from, p_to) pb;

  select pp.period_start, pp.period_end into v_pstart, v_pend
  from public.analytics_prev_period_bounds(v_start, v_end) pp;

  v_feat_taxes := public.analytics_feature_enabled(p_organization_id, 'taxes');
  v_feat_inventory := public.analytics_feature_enabled(p_organization_id, 'inventory');
  v_feat_pos := public.analytics_feature_enabled(p_organization_id, 'pos');
  v_feat_fiscal := public.analytics_feature_enabled(p_organization_id, 'fiscal_invoicing');
  v_feat_cash := public.analytics_feature_enabled(p_organization_id, 'cash');
  v_feat_banks := public.analytics_feature_enabled(p_organization_id, 'banks');
  v_feat_accounting := public.analytics_feature_enabled(p_organization_id, 'accounting');
  v_feat_purchases := public.analytics_feature_enabled(p_organization_id, 'purchases');
  v_feat_sales := public.analytics_feature_enabled(p_organization_id, 'sales');

  v_cap_fin := public.analytics_has_capability(
    p_organization_id, 'DASHBOARD_FINANCIAL'::public.analytics_capability
  );
  v_cap_tax := public.analytics_has_capability(
    p_organization_id, 'DASHBOARD_TAX'::public.analytics_capability
  );
  v_cap_inv := public.analytics_has_capability(
    p_organization_id, 'DASHBOARD_INVENTORY'::public.analytics_capability
  );
  v_cap_alert := public.analytics_has_capability(
    p_organization_id, 'ALERT_READ'::public.analytics_capability
  );

  v_sections := jsonb_build_object(
    'resumen', true,
    'finanzas', v_cap_fin and (v_feat_cash or v_feat_banks or v_feat_accounting),
    'ventas', v_cap_fin and (v_feat_sales or v_feat_fiscal),
    'compras', v_cap_fin and v_feat_purchases,
    'stock', v_cap_inv and v_feat_inventory,
    'impuestos', v_cap_tax and v_feat_taxes,
    'atencion', v_cap_alert
  );

  if v_cap_fin and v_feat_fiscal then
    v_val := public.analytics_sales_fiscal_gross(p_organization_id, v_start, v_end, null);
    v_prev := case when v_do_compare
      then public.analytics_sales_fiscal_gross(p_organization_id, v_pstart, v_pend, null)
      else null end;
    v_metrics := v_metrics || jsonb_build_object(
      'SALES_FISCAL_GROSS_AUTHORIZED',
      public.analytics_metric_payload(
        'SALES_FISCAL_GROSS_AUTHORIZED', v_val,
        'Ventas facturadas brutas autorizadas', 'CURRENCY', v_prev, v_do_compare
      )
    );
    v_val := public.analytics_sales_fiscal_net(p_organization_id, v_start, v_end, null);
    v_prev := case when v_do_compare
      then public.analytics_sales_fiscal_net(p_organization_id, v_pstart, v_pend, null)
      else null end;
    v_metrics := v_metrics || jsonb_build_object(
      'SALES_FISCAL_NET_AUTHORIZED',
      public.analytics_metric_payload(
        'SALES_FISCAL_NET_AUTHORIZED', v_val,
        'Ventas facturadas netas autorizadas', 'CURRENCY', v_prev, v_do_compare
      )
    );
  end if;

  if v_cap_fin and (v_feat_cash or v_feat_banks) then
    v_metrics := v_metrics || jsonb_build_object(
      'CASH_INTERNAL',
      public.analytics_metric_payload(
        'CASH_INTERNAL',
        public.analytics_treasury_type_balance(p_organization_id, 'CASH'::public.treasury_account_type),
        'Saldo de caja interno', 'CURRENCY'
      )
    );
    v_metrics := v_metrics || jsonb_build_object(
      'BANK_INTERNAL',
      public.analytics_metric_payload(
        'BANK_INTERNAL',
        public.analytics_treasury_type_balance(p_organization_id, 'BANK'::public.treasury_account_type),
        'Saldo bancario interno', 'CURRENCY'
      )
    );
  end if;

  if v_cap_fin and v_feat_pos then
    v_metrics := v_metrics || jsonb_build_object(
      'CLEARING_PENDING',
      public.analytics_metric_payload(
        'CLEARING_PENDING',
        public.analytics_treasury_type_balance(p_organization_id, 'CLEARING'::public.treasury_account_type),
        'Tarjetas/QR pendientes', 'CURRENCY'
      )
    );
  end if;

  if v_cap_fin and v_feat_sales then
    v_metrics := v_metrics || jsonb_build_object(
      'AR_OPEN',
      public.analytics_metric_payload(
        'AR_OPEN', public.analytics_ar_open_total(p_organization_id),
        'Cuentas por cobrar abiertas', 'CURRENCY'
      )
    );
  end if;

  if v_cap_fin and v_feat_purchases then
    v_metrics := v_metrics || jsonb_build_object(
      'AP_OPEN',
      public.analytics_metric_payload(
        'AP_OPEN', public.analytics_ap_open_total(p_organization_id),
        'Cuentas por pagar abiertas', 'CURRENCY'
      )
    );
  end if;

  if v_cap_inv and v_feat_inventory then
    select coalesce(sum(ics.inventory_value), 0)::numeric(19, 4) into v_val
    from public.inventory_cost_state ics
    where ics.organization_id = p_organization_id;
    v_metrics := v_metrics || jsonb_build_object(
      'INVENTORY_VALUE',
      public.analytics_metric_payload('INVENTORY_VALUE', v_val, 'Inventario valorizado', 'CURRENCY')
    );
  end if;

  if v_cap_tax and v_feat_taxes then
    select coalesce(
      (
        select (td.totals_snapshot->>'saldo_estimado')::numeric(19, 4)
        from public.tax_determinations td
        join public.tax_periods tp on tp.id = td.tax_period_id
        where td.organization_id = p_organization_id
          and td.is_current
          and td.totals_snapshot ? 'saldo_estimado'
        order by tp.period_end desc nulls last, td.calculated_at desc nulls last
        limit 1
      ),
      0
    ) into v_tax;
    v_metrics := v_metrics || jsonb_build_object(
      'TAX_IVA_SALDO_ESTIMADO',
      public.analytics_metric_payload(
        'TAX_IVA_SALDO_ESTIMADO', coalesce(v_tax, 0),
        'IVA — saldo estimado', 'CURRENCY'
      ) || jsonb_build_object(
        'disclaimer', 'Saldo estimado según Contabilium — no es IVA definitivo a pagar'
      )
    );
  end if;

  if v_cap_fin and v_feat_accounting then
    v_pnl := public.analytics_management_pnl(p_organization_id, v_start, v_end);
    v_metrics := v_metrics || jsonb_build_object(
      'MANAGEMENT_GROSS_RESULT',
      public.analytics_metric_payload(
        'MANAGEMENT_GROSS_RESULT',
        coalesce((v_pnl->>'gross_result')::numeric, 0),
        'Resultado bruto gerencial', 'CURRENCY'
      )
    );
    v_metrics := v_metrics || jsonb_build_object(
      'ACCT_RESULT_EST',
      public.analytics_metric_payload(
        'ACCT_RESULT_EST',
        coalesce((v_pnl->>'management_result')::numeric, 0),
        'Resultado estimado (gerencial)', 'CURRENCY'
      )
    );
    select coalesce(sum(
      public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
    ), 0)::numeric(19, 4) into v_val
    from public.analytics_journal_economic_lines(p_organization_id) l
    where l.account_type = 'REVENUE'::public.account_type
      and l.entry_date >= v_start and l.entry_date <= v_end;
    v_metrics := v_metrics || jsonb_build_object(
      'ACCT_REVENUE',
      public.analytics_metric_payload('ACCT_REVENUE', v_val, 'Ingresos contables', 'CURRENCY')
    );
  end if;

  if v_cap_fin and (v_feat_cash or v_feat_banks) then
    select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_val
    from public.treasury_operations o
    where o.organization_id = p_organization_id
      and o.operation_type = 'COLLECTION'::public.treasury_operation_type
      and o.status = 'POSTED'::public.treasury_operation_status
      and o.operation_date >= v_start and o.operation_date <= v_end;
    select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_prev
    from public.treasury_operations o
    where v_do_compare
      and o.organization_id = p_organization_id
      and o.operation_type = 'COLLECTION'::public.treasury_operation_type
      and o.status = 'POSTED'::public.treasury_operation_status
      and o.operation_date >= v_pstart and o.operation_date <= v_pend;
    v_metrics := v_metrics || jsonb_build_object(
      'COLLECTIONS_POSTED',
      public.analytics_metric_payload(
        'COLLECTIONS_POSTED', v_val, 'Cobros reales', 'CURRENCY', v_prev, v_do_compare
      )
    );
  end if;

  return jsonb_build_object(
    'metrics', v_metrics,
    'sections', v_sections,
    'period_start', v_start,
    'period_end', v_end,
    'data_as_of', v_now,
    'generated_at', v_now,
    'calculation_version', 1,
    'generated_by', v_uid
  );
end;
$$;
revoke all on function public.get_dashboard_summary(uuid, text, date, date, text) from public, anon;
grant execute on function public.get_dashboard_summary(uuid, text, date, date, text) to authenticated;
comment on function public.get_dashboard_summary(uuid, text, date, date, text) is
  'SECURITY DEFINER intentional: dashboard KPIs; membership + dashboard feature + analytics_capability gates.';
-- =============================================================================
-- 4) get_financial_dashboard / get_ar_aging / get_ap_aging
-- =============================================================================

create or replace function public.get_financial_dashboard(
  p_organization_id uuid,
  p_period_preset text default 'THIS_MONTH',
  p_from date default null,
  p_to date default null,
  p_compare_mode text default 'PREV_PERIOD'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_start date;
  v_end date;
  v_pstart date;
  v_pend date;
  v_now timestamptz := timezone('utc', now());
  v_metrics jsonb := '{}'::jsonb;
  v_do_compare boolean := upper(coalesce(p_compare_mode, 'PREV_PERIOD')) = 'PREV_PERIOD';
  v_cash numeric(19, 4);
  v_bank numeric(19, 4);
  v_clearing numeric(19, 4);
  v_coll numeric(19, 4);
  v_pay numeric(19, 4);
  v_coll_prev numeric(19, 4);
  v_pay_prev numeric(19, 4);
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, 'dashboard');
  perform public.analytics_assert_capability(
    p_organization_id, 'DASHBOARD_FINANCIAL'::public.analytics_capability
  );

  select pb.period_start, pb.period_end
  into v_start, v_end
  from public.analytics_period_bounds(p_organization_id, p_period_preset, p_from, p_to) pb;

  select pp.period_start, pp.period_end into v_pstart, v_pend
  from public.analytics_prev_period_bounds(v_start, v_end) pp;

  v_cash := public.analytics_treasury_type_balance(p_organization_id, 'CASH'::public.treasury_account_type);
  v_bank := public.analytics_treasury_type_balance(p_organization_id, 'BANK'::public.treasury_account_type);
  v_clearing := public.analytics_treasury_type_balance(p_organization_id, 'CLEARING'::public.treasury_account_type);

  select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_coll
  from public.treasury_operations o
  where o.organization_id = p_organization_id
    and o.operation_type = 'COLLECTION'::public.treasury_operation_type
    and o.status = 'POSTED'::public.treasury_operation_status
    and o.operation_date >= v_start and o.operation_date <= v_end;

  select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_pay
  from public.treasury_operations o
  where o.organization_id = p_organization_id
    and o.operation_type = 'PAYMENT'::public.treasury_operation_type
    and o.status = 'POSTED'::public.treasury_operation_status
    and o.operation_date >= v_start and o.operation_date <= v_end;

  if v_do_compare then
    select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_coll_prev
    from public.treasury_operations o
    where o.organization_id = p_organization_id
      and o.operation_type = 'COLLECTION'::public.treasury_operation_type
      and o.status = 'POSTED'::public.treasury_operation_status
      and o.operation_date >= v_pstart and o.operation_date <= v_pend;

    select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_pay_prev
    from public.treasury_operations o
    where o.organization_id = p_organization_id
      and o.operation_type = 'PAYMENT'::public.treasury_operation_type
      and o.status = 'POSTED'::public.treasury_operation_status
      and o.operation_date >= v_pstart and o.operation_date <= v_pend;
  end if;

  v_metrics := v_metrics
    || jsonb_build_object(
      'CASH_INTERNAL',
      public.analytics_metric_payload('CASH_INTERNAL', v_cash, 'Saldo de caja interno', 'CURRENCY')
    )
    || jsonb_build_object(
      'BANK_INTERNAL',
      public.analytics_metric_payload('BANK_INTERNAL', v_bank, 'Saldo bancario interno', 'CURRENCY')
    )
    || jsonb_build_object(
      'CLEARING_PENDING',
      public.analytics_metric_payload('CLEARING_PENDING', v_clearing, 'Tarjetas/QR pendientes', 'CURRENCY')
    )
    || jsonb_build_object(
      'AR_OPEN',
      public.analytics_metric_payload(
        'AR_OPEN', public.analytics_ar_open_total(p_organization_id),
        'Cuentas por cobrar abiertas', 'CURRENCY'
      )
    )
    || jsonb_build_object(
      'AP_OPEN',
      public.analytics_metric_payload(
        'AP_OPEN', public.analytics_ap_open_total(p_organization_id),
        'Cuentas por pagar abiertas', 'CURRENCY'
      )
    )
    || jsonb_build_object(
      'COLLECTIONS_POSTED',
      public.analytics_metric_payload(
        'COLLECTIONS_POSTED', v_coll, 'Cobros reales', 'CURRENCY',
        v_coll_prev, v_do_compare
      )
    )
    || jsonb_build_object(
      'PAYMENTS_POSTED',
      public.analytics_metric_payload(
        'PAYMENTS_POSTED', v_pay, 'Pagos reales', 'CURRENCY',
        v_pay_prev, v_do_compare
      )
    );

  return jsonb_build_object(
    'metrics', v_metrics,
    'period_start', v_start,
    'period_end', v_end,
    'compare_period_start', case when v_do_compare then to_jsonb(v_pstart) else 'null'::jsonb end,
    'compare_period_end', case when v_do_compare then to_jsonb(v_pend) else 'null'::jsonb end,
    'data_as_of', v_now,
    'generated_at', v_now,
    'calculation_version', 1
  );
end;
$$;
revoke all on function public.get_financial_dashboard(uuid, text, date, date, text) from public, anon;
grant execute on function public.get_financial_dashboard(uuid, text, date, date, text) to authenticated;
comment on function public.get_financial_dashboard(uuid, text, date, date, text) is
  'SECURITY DEFINER intentional: financial dashboard; requires DASHBOARD_FINANCIAL capability.';
create or replace function public.get_ar_aging(
  p_organization_id uuid,
  p_as_of date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_as_of date;
  v_now timestamptz := timezone('utc', now());
  v_rows jsonb;
  v_totals jsonb;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_any_feature(p_organization_id, array['dashboard','reports','sales']);
  perform public.analytics_assert_capability(
    p_organization_id, 'DASHBOARD_FINANCIAL'::public.analytics_capability
  );

  v_as_of := coalesce(
    p_as_of,
    (timezone(public.analytics_org_timezone(p_organization_id), timezone('utc', now())))::date
  );

  select coalesce(jsonb_agg(x.row_obj order by x.sort_key), '[]'::jsonb)
  into v_rows
  from (
    select
      case b.bucket
        when 'NOT_DUE' then 1
        when 'OVERDUE_1_30' then 2
        when 'OVERDUE_31_60' then 3
        when 'OVERDUE_61_90' then 4
        when 'OVERDUE_90_PLUS' then 5
        else 6
      end as sort_key,
      jsonb_build_object(
        'bucket', b.bucket,
        'amount', b.amount,
        'count', b.cnt
      ) as row_obj
    from (
      select
        public.analytics_aging_bucket(ari.due_date, v_as_of) as bucket,
        coalesce(sum(
          case
            when ari.direction = 'AR_INCREASE'::public.accounts_receivable_direction then ari.open_amount
            else -ari.open_amount
          end
        ), 0)::numeric(19, 4) as amount,
        count(*)::int as cnt
      from public.accounts_receivable_items ari
      where ari.organization_id = p_organization_id
        and ari.status in (
          'OPEN'::public.accounts_receivable_status,
          'PARTIALLY_COLLECTED'::public.accounts_receivable_status
        )
        and ari.open_amount > 0
      group by 1
    ) b
  ) x;

  select jsonb_object_agg(e->>'bucket', e->'amount')
  into v_totals
  from jsonb_array_elements(v_rows) e;

  return jsonb_build_object(
    'as_of', v_as_of,
    'rows', v_rows,
    'totals', coalesce(v_totals, '{}'::jsonb),
    'open_total', public.analytics_ar_open_total(p_organization_id),
    'calculation_version', 1,
    'data_as_of', v_now,
    'generated_at', v_now,
    'generated_by', v_uid
  );
end;
$$;
revoke all on function public.get_ar_aging(uuid, date) from public, anon;
grant execute on function public.get_ar_aging(uuid, date) to authenticated;
comment on function public.get_ar_aging(uuid, date) is
  'SECURITY DEFINER intentional: AR aging; requires DASHBOARD_FINANCIAL.';
create or replace function public.get_ap_aging(
  p_organization_id uuid,
  p_as_of date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_as_of date;
  v_now timestamptz := timezone('utc', now());
  v_rows jsonb;
  v_totals jsonb;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_any_feature(p_organization_id, array['dashboard','reports','purchases']);
  perform public.analytics_assert_capability(
    p_organization_id, 'DASHBOARD_FINANCIAL'::public.analytics_capability
  );

  v_as_of := coalesce(
    p_as_of,
    (timezone(public.analytics_org_timezone(p_organization_id), timezone('utc', now())))::date
  );

  select coalesce(jsonb_agg(x.row_obj order by x.sort_key), '[]'::jsonb)
  into v_rows
  from (
    select
      case b.bucket
        when 'NOT_DUE' then 1
        when 'OVERDUE_1_30' then 2
        when 'OVERDUE_31_60' then 3
        when 'OVERDUE_61_90' then 4
        when 'OVERDUE_90_PLUS' then 5
        else 6
      end as sort_key,
      jsonb_build_object(
        'bucket', b.bucket,
        'amount', b.amount,
        'count', b.cnt
      ) as row_obj
    from (
      select
        public.analytics_aging_bucket(api.due_date, v_as_of) as bucket,
        coalesce(sum(
          case
            when api.direction = 'AP_INCREASE'::public.accounts_payable_direction then api.open_amount
            else -api.open_amount
          end
        ), 0)::numeric(19, 4) as amount,
        count(*)::int as cnt
      from public.accounts_payable_items api
      where api.organization_id = p_organization_id
        and api.status in (
          'OPEN'::public.accounts_payable_status,
          'PARTIALLY_PAID'::public.accounts_payable_status
        )
        and api.open_amount > 0
      group by 1
    ) b
  ) x;

  select jsonb_object_agg(e->>'bucket', e->'amount')
  into v_totals
  from jsonb_array_elements(v_rows) e;

  return jsonb_build_object(
    'as_of', v_as_of,
    'rows', v_rows,
    'totals', coalesce(v_totals, '{}'::jsonb),
    'open_total', public.analytics_ap_open_total(p_organization_id),
    'calculation_version', 1,
    'data_as_of', v_now,
    'generated_at', v_now,
    'generated_by', v_uid
  );
end;
$$;
revoke all on function public.get_ap_aging(uuid, date) from public, anon;
grant execute on function public.get_ap_aging(uuid, date) to authenticated;
comment on function public.get_ap_aging(uuid, date) is
  'SECURITY DEFINER intentional: AP aging; requires DASHBOARD_FINANCIAL.';
-- =============================================================================
-- 5) get_attention_summary — ALERT_READ + domain sanitization
-- =============================================================================

create or replace function public.get_attention_summary(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_now timestamptz := timezone('utc', now());
  v_open int := 0;
  v_ack int := 0;
  v_critical int := 0;
  v_items jsonb := '[]'::jsonb;
  v_cap_fin boolean;
  v_cap_tax boolean;
  v_cap_pos boolean;
  v_sanitize boolean;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, 'dashboard');
  perform public.analytics_assert_capability(
    p_organization_id, 'ALERT_READ'::public.analytics_capability
  );

  v_cap_fin := public.analytics_has_capability(
    p_organization_id, 'DASHBOARD_FINANCIAL'::public.analytics_capability
  );
  v_cap_tax := public.analytics_has_capability(
    p_organization_id, 'DASHBOARD_TAX'::public.analytics_capability
  );
  v_cap_pos := public.analytics_has_capability(
    p_organization_id, 'DASHBOARD_POS_SENSITIVE'::public.analytics_capability
  );
  v_sanitize := not v_cap_fin;

  select
    count(*) filter (where status = 'OPEN'),
    count(*) filter (where status = 'ACKNOWLEDGED'),
    count(*) filter (where status in ('OPEN', 'ACKNOWLEDGED') and severity = 'CRITICAL')
  into v_open, v_ack, v_critical
  from public.analytics_alert_events e
  where e.organization_id = p_organization_id
    and e.status in ('OPEN', 'ACKNOWLEDGED')
    and (
      case
        when not v_cap_fin then e.domain in (
          'POS'::public.analytics_alert_domain,
          'FISCAL'::public.analytics_alert_domain,
          'INVENTORY'::public.analytics_alert_domain
        )
        else true
      end
    )
    and (v_cap_tax or e.domain is distinct from 'TAX'::public.analytics_alert_domain)
    and (
      v_cap_pos
      or e.domain is distinct from 'POS'::public.analytics_alert_domain
      or e.rule_code not ilike '%CASH%'
    )
    and (
      v_cap_pos
      or e.rule_code not ilike '%DIFF%'
    );

  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.sort_sev, x.last_detected_at desc), '[]'::jsonb)
  into v_items
  from (
    select
      e.id,
      e.rule_code,
      e.domain,
      e.severity,
      e.status,
      e.entity_type,
      e.entity_id,
      case
        when v_sanitize then jsonb_build_object(
          'rule_code', e.rule_code,
          'message', coalesce(e.payload_snapshot->>'message', e.rule_code)
        )
        else e.payload_snapshot
      end as payload_snapshot,
      e.first_detected_at,
      e.last_detected_at,
      case e.severity
        when 'CRITICAL' then 0
        when 'WARNING' then 1
        else 2
      end as sort_sev
    from public.analytics_alert_events e
    where e.organization_id = p_organization_id
      and e.status in ('OPEN', 'ACKNOWLEDGED')
      and (
        case
          when not v_cap_fin then e.domain in (
            'POS'::public.analytics_alert_domain,
            'FISCAL'::public.analytics_alert_domain,
            'INVENTORY'::public.analytics_alert_domain
          )
          else true
        end
      )
      and (v_cap_tax or e.domain is distinct from 'TAX'::public.analytics_alert_domain)
      and (
        v_cap_pos
        or e.domain is distinct from 'POS'::public.analytics_alert_domain
        or e.rule_code not ilike '%CASH%'
      )
      and (
        v_cap_pos
        or e.rule_code not ilike '%DIFF%'
      )
    order by sort_sev, e.last_detected_at desc
    limit 50
  ) x;

  return jsonb_build_object(
    'open_count', coalesce(v_open, 0),
    'acknowledged_count', coalesce(v_ack, 0),
    'critical_count', coalesce(v_critical, 0),
    'items', coalesce(v_items, '[]'::jsonb),
    'sanitized', v_sanitize,
    'calculation_version', 1,
    'data_as_of', v_now,
    'generated_at', v_now,
    'generated_by', v_uid,
    'note', 'Call evaluate_analytics_alerts explicitly to refresh; dashboard GET does not write alerts.'
  );
end;
$$;
revoke all on function public.get_attention_summary(uuid) from public, anon;
grant execute on function public.get_attention_summary(uuid) to authenticated;
comment on function public.get_attention_summary(uuid) is
  'SECURITY DEFINER intentional: Attention Center; ALERT_READ; non-FINANCIAL roles get sanitized operational alerts.';
-- =============================================================================
-- 6) ack_analytics_alert — ALERT_ACK
-- =============================================================================

create or replace function public.ack_analytics_alert(p_alert_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_row public.analytics_alert_events%rowtype;
begin
  select * into v_row from public.analytics_alert_events where id = p_alert_id;
  if not found then
    raise exception 'alert not found';
  end if;

  v_uid := public.analytics_assert_member(v_row.organization_id);
  perform public.analytics_assert_any_feature(v_row.organization_id, array['dashboard','reports']);
  perform public.analytics_assert_capability(
    v_row.organization_id, 'ALERT_ACK'::public.analytics_capability
  );

  if v_row.status = 'RESOLVED'::public.analytics_alert_status then
    raise exception 'cannot acknowledge a resolved alert';
  end if;

  update public.analytics_alert_events
  set
    status = 'ACKNOWLEDGED'::public.analytics_alert_status,
    acknowledged_at = timezone('utc', now()),
    acknowledged_by = v_uid,
    updated_at = timezone('utc', now())
  where id = p_alert_id;

  return jsonb_build_object('id', p_alert_id, 'status', 'ACKNOWLEDGED', 'acknowledged_by', v_uid);
end;
$$;
revoke all on function public.ack_analytics_alert(uuid) from public, anon;
grant execute on function public.ack_analytics_alert(uuid) to authenticated;
comment on function public.ack_analytics_alert(uuid) is
  'SECURITY DEFINER intentional: acknowledge alert; requires ALERT_ACK capability.';
-- =============================================================================
-- 7) evaluate_analytics_alerts — ALERT_EVALUATE
-- =============================================================================

create or replace function public.evaluate_analytics_alerts(p_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_as_of date;
  v_keys text[] := '{}';
  v_key text;
  v_opened int := 0;
  v_thr jsonb;
  v_days int;
  v_now timestamptz := timezone('utc', now());
  r record;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_any_feature(p_organization_id, array['dashboard','reports']);
  perform public.analytics_assert_capability(
    p_organization_id, 'ALERT_EVALUATE'::public.analytics_capability
  );

  v_as_of := (timezone(public.analytics_org_timezone(p_organization_id), timezone('utc', now())))::date;

  if public.analytics_alert_rule_enabled(p_organization_id, 'AR_OVERDUE') then
    v_keys := '{}';
    for r in
      select ari.id, ari.open_amount, ari.due_date, ari.customer_id
      from public.accounts_receivable_items ari
      where ari.organization_id = p_organization_id
        and ari.status in ('OPEN','PARTIALLY_COLLECTED')
        and ari.open_amount > 0
        and ari.due_date is not null
        and ari.due_date < v_as_of
    loop
      v_key := 'AR_OVERDUE:' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'AR_OVERDUE', 'FINANCE', v_key, 'WARNING',
        'accounts_receivable_items', r.id,
        jsonb_build_object('open_amount', r.open_amount, 'due_date', r.due_date, 'as_of', v_as_of)
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'AR_OVERDUE', v_keys);
  end if;

  if public.analytics_alert_rule_enabled(p_organization_id, 'AP_OVERDUE') then
    v_keys := '{}';
    for r in
      select api.id, api.open_amount, api.due_date
      from public.accounts_payable_items api
      where api.organization_id = p_organization_id
        and api.status in ('OPEN','PARTIALLY_PAID')
        and api.open_amount > 0
        and api.due_date is not null
        and api.due_date < v_as_of
    loop
      v_key := 'AP_OVERDUE:' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'AP_OVERDUE', 'FINANCE', v_key, 'WARNING',
        'accounts_payable_items', r.id,
        jsonb_build_object('open_amount', r.open_amount, 'due_date', r.due_date, 'as_of', v_as_of)
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'AP_OVERDUE', v_keys);
  end if;

  if public.analytics_alert_rule_enabled(p_organization_id, 'TAX_SOURCE_CHANGED')
     and public.analytics_feature_enabled(p_organization_id, 'taxes')
  then
    v_keys := '{}';
    for r in
      select tp.id
      from public.tax_periods tp
      where tp.organization_id = p_organization_id
        and tp.source_changed
        and tp.status in ('OPEN','IN_REVIEW','REVIEWED','REOPENED')
    loop
      v_key := 'TAX_SOURCE_CHANGED:' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'TAX_SOURCE_CHANGED', 'TAX', v_key, 'WARNING',
        'tax_periods', r.id,
        jsonb_build_object('message', 'Fuente tributaria modificada — requiere revisión')
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'TAX_SOURCE_CHANGED', v_keys);
  end if;

  if public.analytics_alert_rule_enabled(p_organization_id, 'FISCAL_RECON_REQUIRED')
     and public.analytics_feature_enabled(p_organization_id, 'fiscal_invoicing')
  then
    v_keys := '{}';
    for r in
      select fd.id
      from public.fiscal_documents fd
      where fd.organization_id = p_organization_id
        and fd.status = 'RECONCILIATION_REQUIRED'::public.fiscal_document_status
    loop
      v_key := 'FISCAL_RECON_REQUIRED:' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'FISCAL_RECON_REQUIRED', 'FISCAL', v_key, 'CRITICAL',
        'fiscal_documents', r.id,
        jsonb_build_object('message', 'Documento fiscal requiere conciliación')
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'FISCAL_RECON_REQUIRED', v_keys);
  end if;

  if public.analytics_alert_rule_enabled(p_organization_id, 'POS_RECON_REQUIRED')
     and public.analytics_feature_enabled(p_organization_id, 'pos')
  then
    v_keys := '{}';
    for r in
      select ps.id
      from public.pos_sales ps
      where ps.organization_id = p_organization_id
        and ps.status = 'RECONCILIATION_REQUIRED'::public.pos_sale_status
    loop
      v_key := 'POS_RECON_REQUIRED:' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'POS_RECON_REQUIRED', 'POS', v_key, 'CRITICAL',
        'pos_sales', r.id,
        jsonb_build_object('message', 'Venta POS requiere conciliación')
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'POS_RECON_REQUIRED', v_keys);
  end if;

  if public.analytics_alert_rule_enabled(p_organization_id, 'STOCK_BELOW_THRESHOLD')
     and public.analytics_feature_enabled(p_organization_id, 'inventory')
  then
    v_keys := '{}';
    for r in
      select
        t.id as threshold_id,
        t.product_id,
        t.warehouse_id,
        t.minimum_available_quantity,
        coalesce(sum(ss.on_hand_quantity - ss.reserved_quantity), 0)::numeric(18, 4) as available_qty
      from public.analytics_inventory_thresholds t
      left join public.inventory_stock_state ss
        on ss.organization_id = t.organization_id
       and ss.product_id = t.product_id
       and (t.warehouse_id is null or ss.warehouse_id = t.warehouse_id)
      where t.organization_id = p_organization_id
        and t.active
      group by t.id, t.product_id, t.warehouse_id, t.minimum_available_quantity
      having coalesce(sum(ss.on_hand_quantity - ss.reserved_quantity), 0) < t.minimum_available_quantity
    loop
      v_key := 'STOCK_BELOW_THRESHOLD:' || r.threshold_id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'STOCK_BELOW_THRESHOLD', 'INVENTORY', v_key, 'WARNING',
        'analytics_inventory_thresholds', r.threshold_id,
        jsonb_build_object(
          'product_id', r.product_id,
          'warehouse_id', r.warehouse_id,
          'available', r.available_qty,
          'minimum', r.minimum_available_quantity
        )
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'STOCK_BELOW_THRESHOLD', v_keys);
  end if;

  v_thr := public.analytics_alert_threshold(p_organization_id, 'CLEARING_AGING');
  if public.analytics_alert_rule_enabled(p_organization_id, 'CLEARING_AGING')
     and (v_thr ? 'max_age_days')
  then
    v_days := greatest(1, coalesce((v_thr->>'max_age_days')::int, 7));
    v_keys := '{}';
    for r in
      select ta.id as account_id,
             public.treasury_account_balance(ta.id) as bal,
             min(o.operation_date) as oldest_date
      from public.treasury_accounts ta
      join public.treasury_operation_legs l
        on l.treasury_account_id = ta.id
       and l.organization_id = ta.organization_id
      join public.treasury_operations o
        on o.id = l.treasury_operation_id
       and o.organization_id = l.organization_id
      where ta.organization_id = p_organization_id
        and ta.account_type = 'CLEARING'::public.treasury_account_type
        and ta.is_active
        and o.status = 'POSTED'::public.treasury_operation_status
        and l.direction = 'INFLOW'::public.treasury_leg_direction
      group by ta.id
      having public.treasury_account_balance(ta.id) > 0
         and min(o.operation_date) <= (v_as_of - v_days)
    loop
      v_key := 'CLEARING_AGING:' || r.account_id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'CLEARING_AGING', 'TREASURY', v_key, 'INFO',
        'treasury_accounts', r.account_id,
        jsonb_build_object(
          'balance', r.bal,
          'oldest_inflow_date', r.oldest_date,
          'max_age_days', v_days
        )
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'CLEARING_AGING', v_keys);
  end if;

  return jsonb_build_object(
    'organization_id', p_organization_id,
    'evaluated_at', v_now,
    'as_of', v_as_of,
    'touched_rules', v_opened,
    'evaluated_by', v_uid
  );
end;
$$;
revoke all on function public.evaluate_analytics_alerts(uuid) from public, anon;
grant execute on function public.evaluate_analytics_alerts(uuid) to authenticated;
comment on function public.evaluate_analytics_alerts(uuid) is
  'SECURITY DEFINER intentional: explicit alert rebuild; requires ALERT_EVALUATE.';
-- =============================================================================
-- 11) analytics_validate_saved_report_config + upsert_saved_report
-- =============================================================================

create or replace function public.analytics_validate_saved_report_config(
  p_report_code text,
  p_filters jsonb,
  p_columns jsonb,
  p_sort jsonb
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_code text := upper(trim(coalesce(p_report_code, '')));
  v_key text;
  v_elem jsonb;
  v_field text;
  v_dir text;
  v_forbidden text[] := array[
    'sql','query','table','schema','function','expression',
    'raw_column','organization_id','tenant_id','org_id'
  ];
  v_filter_allow text[];
  v_col_allow text[] := array[
    'id','issue_date','amount','code','name','balance','status','document_number',
    'gross','net','count','bucket','debit','credit','sku','product_id','operation_type',
    'operation_date','accounting_date','completed_at','tax_period_id','saldo_estimado',
    'inventory_value','quantity_on_hand_total','average_unit_cost','internal_number',
    'description','document_type','fiscal_environment','operation_kind','signed_total',
    'warehouse_id','movement_date','direction','quantity'
  ];
  v_common_filters text[] := array['from','to','as_of','period_preset','fiscal_environment'];
begin
  if v_code = '' then
    raise exception 'report_code required';
  end if;

  v_filter_allow := case v_code
    when 'SALES_SUMMARY' then array['from','to','period_preset','fiscal_environment']
    when 'TAX_SUMMARY' then array['from','to','period_preset','as_of']
    when 'AR_AGING' then array['as_of','period_preset']
    when 'AP_AGING' then array['as_of','period_preset']
    when 'CASH_BANK_POSITION' then array['as_of']
    when 'TREASURY_MOVEMENTS' then array['from','to','period_preset']
    when 'MANAGEMENT_PNL' then array['from','to','period_preset']
    when 'MANAGEMENT_BALANCE_SHEET' then array['as_of','period_preset']
    when 'TRIAL_BALANCE_MGMT' then array['from','to','period_preset']
    when 'INVENTORY_VALUATION' then array['as_of']
    when 'INVENTORY_MOVEMENTS' then array['from','to','period_preset']
    when 'POS_SUMMARY' then array['from','to','period_preset']
    when 'PURCHASES_SUMMARY' then array['from','to','period_preset']
    else v_common_filters
  end;

  -- Reject forbidden keys in any jsonb object (filters) or nested objects (sort elems)
  if p_filters is not null and jsonb_typeof(p_filters) = 'object' then
    for v_key in select jsonb_object_keys(p_filters)
    loop
      if lower(v_key) = any (v_forbidden) then
        raise exception 'saved report filters reject key: %', v_key;
      end if;
      if not exists (
        select 1 from unnest(v_filter_allow) a where lower(a) = lower(v_key)
      ) then
        raise exception 'saved report filters unknown key: %', v_key;
      end if;
    end loop;
  elsif p_filters is not null and jsonb_typeof(p_filters) is distinct from 'object' then
    raise exception 'filters must be a jsonb object';
  end if;

  if p_columns is not null then
    if jsonb_typeof(p_columns) is distinct from 'array' then
      raise exception 'columns must be a jsonb array';
    end if;
    for v_elem in select * from jsonb_array_elements(p_columns)
    loop
      if jsonb_typeof(v_elem) = 'object' then
        for v_key in select jsonb_object_keys(v_elem)
        loop
          if lower(v_key) = any (v_forbidden) then
            raise exception 'saved report columns reject key: %', v_key;
          end if;
        end loop;
        v_field := coalesce(v_elem->>'field', v_elem->>'code', v_elem->>'name');
      elsif jsonb_typeof(v_elem) = 'string' then
        v_field := trim(both '"' from v_elem::text);
      else
        raise exception 'invalid columns element';
      end if;
      if v_field is not null and v_field <> '' and not exists (
        select 1 from unnest(v_col_allow) a where lower(a) = lower(v_field)
      ) then
        raise exception 'saved report columns unknown field: %', v_field;
      end if;
    end loop;
  end if;

  if p_sort is not null then
    if jsonb_typeof(p_sort) is distinct from 'array' then
      raise exception 'sort must be a jsonb array';
    end if;
    for v_elem in select * from jsonb_array_elements(p_sort)
    loop
      if jsonb_typeof(v_elem) is distinct from 'object' then
        raise exception 'sort elements must be objects';
      end if;
      for v_key in select jsonb_object_keys(v_elem)
      loop
        if lower(v_key) = any (v_forbidden) then
          raise exception 'saved report sort reject key: %', v_key;
        end if;
        if lower(v_key) not in ('field', 'direction') then
          raise exception 'saved report sort unknown key: %', v_key;
        end if;
      end loop;
      v_field := v_elem->>'field';
      v_dir := upper(coalesce(v_elem->>'direction', 'ASC'));
      if v_field is null or v_field = '' then
        raise exception 'sort.field required';
      end if;
      if not exists (
        select 1 from unnest(v_col_allow) a where lower(a) = lower(v_field)
      ) then
        raise exception 'saved report sort unknown field: %', v_field;
      end if;
      if v_dir not in ('ASC', 'DESC') then
        raise exception 'sort.direction must be ASC or DESC';
      end if;
    end loop;
  end if;
end;
$$;
revoke all on function public.analytics_validate_saved_report_config(text, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
create or replace function public.upsert_saved_report(
  p_organization_id uuid,
  p_report_code text,
  p_name text,
  p_filters_json jsonb default '{}'::jsonb,
  p_columns_json jsonb default '[]'::jsonb,
  p_sort_json jsonb default '[]'::jsonb,
  p_visibility text default 'PRIVATE',
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_id uuid;
  v_vis public.saved_report_visibility;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, 'reports');

  perform public.analytics_validate_saved_report_config(
    p_report_code,
    coalesce(p_filters_json, '{}'::jsonb),
    coalesce(p_columns_json, '[]'::jsonb),
    coalesce(p_sort_json, '[]'::jsonb)
  );

  v_vis := upper(coalesce(p_visibility, 'PRIVATE'))::public.saved_report_visibility;

  if p_id is not null then
    update public.saved_reports
    set
      report_code = upper(trim(p_report_code)),
      name = trim(p_name),
      filters_json = coalesce(p_filters_json, '{}'::jsonb),
      columns_json = coalesce(p_columns_json, '[]'::jsonb),
      sort_json = coalesce(p_sort_json, '[]'::jsonb),
      visibility = v_vis,
      updated_at = timezone('utc', now())
    where id = p_id
      and organization_id = p_organization_id
      and owner_user_id = v_uid
    returning id into v_id;
    if v_id is null then
      raise exception 'saved report not found or not owned';
    end if;
  else
    insert into public.saved_reports (
      organization_id, owner_user_id, report_code, name,
      filters_json, columns_json, sort_json, visibility
    ) values (
      p_organization_id, v_uid, upper(trim(p_report_code)), trim(p_name),
      coalesce(p_filters_json, '{}'::jsonb),
      coalesce(p_columns_json, '[]'::jsonb),
      coalesce(p_sort_json, '[]'::jsonb),
      v_vis
    )
    returning id into v_id;
  end if;

  return jsonb_build_object('id', v_id);
end;
$$;
revoke all on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
  from public, anon;
grant execute on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
  to authenticated;
comment on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid) is
  'SECURITY DEFINER intentional: upsert saved report after allowlist validation; never accepts SQL fragments.';
-- =============================================================================
-- 8) get_report_dataset — capability gates + pagination totals fix
-- =============================================================================

create or replace function public.get_report_dataset(
  p_organization_id uuid,
  p_report_code text,
  p_filters jsonb default '{}'::jsonb,
  p_limit int default 100,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_code text := upper(trim(p_report_code));
  v_limit int := greatest(1, least(coalesce(p_limit, 100), 500));
  v_offset int := greatest(0, coalesce(p_offset, 0));
  v_from date;
  v_to date;
  v_as_of date;
  v_now timestamptz := timezone('utc', now());
  v_rows jsonb := '[]'::jsonb;
  v_totals jsonb := '{}'::jsonb;
  v_env text;
  v_pnl jsonb;
  v_bs jsonb;
  v_aging jsonb;
  v_total_count bigint := 0;
  v_page_count int := 0;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, 'reports');

  if v_code in (
    'AR_AGING', 'AP_AGING', 'CASH_BANK_POSITION', 'TREASURY_MOVEMENTS',
    'MANAGEMENT_PNL', 'MANAGEMENT_BALANCE_SHEET', 'TRIAL_BALANCE_MGMT'
  ) then
    perform public.analytics_assert_capability(
      p_organization_id, 'REPORT_FINANCIAL'::public.analytics_capability
    );
  elsif v_code = 'TAX_SUMMARY' then
    perform public.analytics_assert_capability(
      p_organization_id, 'REPORT_TAX'::public.analytics_capability
    );
    perform public.analytics_assert_feature(p_organization_id, 'taxes');
  elsif v_code in ('INVENTORY_VALUATION', 'INVENTORY_MOVEMENTS') then
    perform public.analytics_assert_capability(
      p_organization_id, 'REPORT_OPERATIONAL'::public.analytics_capability
    );
    perform public.analytics_assert_feature(p_organization_id, 'inventory');
  elsif v_code = 'POS_SUMMARY' then
    perform public.analytics_assert_capability(
      p_organization_id, 'REPORT_OPERATIONAL'::public.analytics_capability
    );
    perform public.analytics_assert_feature(p_organization_id, 'pos');
  elsif v_code = 'SALES_SUMMARY' then
    perform public.analytics_assert_capability(
      p_organization_id, 'REPORT_OPERATIONAL'::public.analytics_capability
    );
    perform public.analytics_assert_any_feature(
      p_organization_id, array['sales', 'fiscal_invoicing']
    );
  elsif v_code = 'PURCHASES_SUMMARY' then
    perform public.analytics_assert_capability(
      p_organization_id, 'REPORT_OPERATIONAL'::public.analytics_capability
    );
    perform public.analytics_assert_feature(p_organization_id, 'purchases');
  else
    raise exception 'unsupported report_code: %', p_report_code;
  end if;

  v_from := nullif(p_filters->>'from', '')::date;
  v_to := nullif(p_filters->>'to', '')::date;
  v_as_of := coalesce(nullif(p_filters->>'as_of', '')::date, v_to, v_from,
    (timezone(public.analytics_org_timezone(p_organization_id), timezone('utc', now())))::date);
  v_env := nullif(p_filters->>'fiscal_environment', '');

  if v_from is null or v_to is null then
    select pb.period_start, pb.period_end into v_from, v_to
    from public.analytics_period_bounds(
      p_organization_id,
      coalesce(nullif(p_filters->>'period_preset', ''), 'THIS_MONTH'),
      v_from, v_to
    ) pb;
  end if;

  case v_code
    when 'AR_AGING' then
      v_aging := public.get_ar_aging(p_organization_id, v_as_of);
      v_rows := coalesce(v_aging->'rows', '[]'::jsonb);
      v_totals := coalesce(v_aging->'totals', '{}'::jsonb);
      v_total_count := jsonb_array_length(v_rows);
      v_page_count := v_total_count::int;

    when 'AP_AGING' then
      v_aging := public.get_ap_aging(p_organization_id, v_as_of);
      v_rows := coalesce(v_aging->'rows', '[]'::jsonb);
      v_totals := coalesce(v_aging->'totals', '{}'::jsonb);
      v_total_count := jsonb_array_length(v_rows);
      v_page_count := v_total_count::int;

    when 'SALES_SUMMARY' then
      select
        jsonb_build_object(
          'gross', coalesce(sum(x.gross), 0)::numeric(19, 4),
          'net', coalesce(sum(x.net), 0)::numeric(19, 4),
          'count', count(*)::int
        ),
        count(*)
      into v_totals, v_total_count
      from (
        select
          (fd.total_amount * public.analytics_fiscal_economic_sign(fdt.operation_kind))::numeric(19, 4) as gross,
          (
            (fd.net_taxed_amount + fd.net_exempt_amount + fd.net_untaxed_amount)
            * public.analytics_fiscal_economic_sign(fdt.operation_kind)
          )::numeric(19, 4) as net
        from public.fiscal_documents fd
        join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
        where fd.organization_id = p_organization_id
          and fd.status = 'AUTHORIZED'::public.fiscal_document_status
          and fd.issue_date >= v_from and fd.issue_date <= v_to
          and (v_env is null or fd.fiscal_environment::text = v_env)
      ) x;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), '[]'::jsonb)
      into v_rows
      from (
        select
          fd.id,
          fd.issue_date,
          fd.document_number,
          fd.status::text,
          fd.fiscal_environment::text,
          fdt.operation_kind::text,
          (fd.total_amount * public.analytics_fiscal_economic_sign(fdt.operation_kind))::numeric(19, 4) as gross,
          (
            (fd.net_taxed_amount + fd.net_exempt_amount + fd.net_untaxed_amount)
            * public.analytics_fiscal_economic_sign(fdt.operation_kind)
          )::numeric(19, 4) as net
        from public.fiscal_documents fd
        join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
        where fd.organization_id = p_organization_id
          and fd.status = 'AUTHORIZED'::public.fiscal_document_status
          and fd.issue_date >= v_from and fd.issue_date <= v_to
          and (v_env is null or fd.fiscal_environment::text = v_env)
        order by fd.issue_date desc, fd.document_number desc nulls last
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, '[]'::jsonb));

    when 'CASH_BANK_POSITION' then
      v_totals := jsonb_build_object(
        'cash', public.analytics_treasury_type_balance(p_organization_id, 'CASH'),
        'bank', public.analytics_treasury_type_balance(p_organization_id, 'BANK'),
        'clearing', public.analytics_treasury_type_balance(p_organization_id, 'CLEARING')
      );
      select count(*) into v_total_count
      from public.treasury_accounts ta
      where ta.organization_id = p_organization_id and ta.is_active;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), '[]'::jsonb)
      into v_rows
      from (
        select
          ta.id,
          ta.code,
          ta.name,
          ta.account_type::text,
          public.treasury_account_balance(ta.id)::numeric(19, 4) as balance
        from public.treasury_accounts ta
        where ta.organization_id = p_organization_id
          and ta.is_active
        order by ta.account_type, ta.code
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, '[]'::jsonb));

    when 'TRIAL_BALANCE_MGMT' then
      perform public.analytics_assert_feature(p_organization_id, 'accounting');
      select
        jsonb_build_object(
          'debit_total', coalesce(sum(x.debit), 0)::numeric(19, 4),
          'credit_total', coalesce(sum(x.credit), 0)::numeric(19, 4)
        ),
        count(*)
      into v_totals, v_total_count
      from (
        select
          coalesce(sum(l.debit), 0)::numeric(19, 4) as debit,
          coalesce(sum(l.credit), 0)::numeric(19, 4) as credit
        from public.accounts a
        left join public.analytics_journal_economic_lines(p_organization_id) l
          on l.account_id = a.id
         and l.entry_date >= v_from
         and l.entry_date <= v_to
        where a.organization_id = p_organization_id
          and a.is_active
          and a.account_type is distinct from 'MEMORANDUM'::public.account_type
        group by a.id
        having coalesce(sum(l.debit), 0) <> 0 or coalesce(sum(l.credit), 0) <> 0
      ) x;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), '[]'::jsonb)
      into v_rows
      from (
        select
          a.code,
          a.name,
          a.account_type::text,
          coalesce(sum(l.debit), 0)::numeric(19, 4) as debit,
          coalesce(sum(l.credit), 0)::numeric(19, 4) as credit,
          public.analytics_signed_balance(
            coalesce(sum(l.debit), 0),
            coalesce(sum(l.credit), 0),
            a.normal_balance
          ) as balance
        from public.accounts a
        left join public.analytics_journal_economic_lines(p_organization_id) l
          on l.account_id = a.id
         and l.entry_date >= v_from
         and l.entry_date <= v_to
        where a.organization_id = p_organization_id
          and a.is_active
          and a.account_type is distinct from 'MEMORANDUM'::public.account_type
        group by a.id, a.code, a.name, a.account_type, a.normal_balance
        having coalesce(sum(l.debit), 0) <> 0 or coalesce(sum(l.credit), 0) <> 0
        order by a.code
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, '[]'::jsonb));

    when 'MANAGEMENT_PNL' then
      v_pnl := public.analytics_management_pnl(p_organization_id, v_from, v_to);
      v_rows := jsonb_build_array(v_pnl);
      v_totals := jsonb_build_object(
        'management_result', v_pnl->'management_result',
        'gross_result', v_pnl->'gross_result'
      );
      v_total_count := 1;
      v_page_count := 1;

    when 'MANAGEMENT_BALANCE_SHEET' then
      v_bs := public.analytics_management_balance_sheet(p_organization_id, v_as_of);
      v_rows := jsonb_build_array(v_bs);
      v_totals := jsonb_build_object(
        'assets', v_bs->'assets',
        'liabilities', v_bs->'liabilities',
        'equity', v_bs->'equity',
        'resultado_del_periodo', v_bs->'resultado_del_periodo',
        'difference', v_bs->'difference',
        'status', v_bs->'status'
      );
      v_total_count := 1;
      v_page_count := 1;

    when 'TAX_SUMMARY' then
      select count(*) into v_total_count
      from public.tax_periods tp
      where tp.organization_id = p_organization_id;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), '[]'::jsonb)
      into v_rows
      from (
        select
          tp.id as tax_period_id,
          tp.tax_code::text,
          tp.period_year,
          tp.period_month,
          tp.status::text,
          tp.source_changed,
          td.id as determination_id,
          td.totals_snapshot,
          (td.totals_snapshot->>'saldo_estimado') as saldo_estimado
        from public.tax_periods tp
        left join public.tax_determinations td
          on td.tax_period_id = tp.id and td.is_current
        where tp.organization_id = p_organization_id
        order by tp.period_year desc, tp.period_month desc nulls last
        limit v_limit offset v_offset
      ) r;
      v_totals := jsonb_build_object('disclaimer', 'Saldo estimado — no es DDJJ oficial');
      v_page_count := jsonb_array_length(coalesce(v_rows, '[]'::jsonb));

    when 'INVENTORY_VALUATION' then
      select
        jsonb_build_object('inventory_value', coalesce(sum(ics.inventory_value), 0)::numeric(19, 4)),
        count(*)
      into v_totals, v_total_count
      from public.inventory_cost_state ics
      where ics.organization_id = p_organization_id;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), '[]'::jsonb)
      into v_rows
      from (
        select
          ics.product_id,
          p.sku,
          p.name,
          ics.quantity_on_hand_total,
          ics.average_unit_cost,
          ics.inventory_value
        from public.inventory_cost_state ics
        join public.products p
          on p.id = ics.product_id and p.organization_id = ics.organization_id
        where ics.organization_id = p_organization_id
        order by ics.inventory_value desc
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, '[]'::jsonb));

    when 'INVENTORY_MOVEMENTS' then
      select
        jsonb_build_object(
          'value_sum', coalesce(sum(abs(ile.value_delta)), 0)::numeric(19, 4),
          'count', count(*)::int
        ),
        count(*)
      into v_totals, v_total_count
      from public.inventory_ledger_entries ile
      where ile.organization_id = p_organization_id
        and ile.movement_date >= v_from and ile.movement_date <= v_to;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), '[]'::jsonb)
      into v_rows
      from (
        select
          ile.id,
          ile.movement_date,
          ile.operation_type::text,
          ile.direction::text,
          ile.product_id,
          ile.warehouse_id,
          ile.quantity,
          ile.value_delta
        from public.inventory_ledger_entries ile
        where ile.organization_id = p_organization_id
          and ile.movement_date >= v_from and ile.movement_date <= v_to
        order by ile.movement_date desc, ile.created_at desc
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, '[]'::jsonb));

    when 'POS_SUMMARY' then
      select
        jsonb_build_object('completed_count', count(*)::int),
        count(*)
      into v_totals, v_total_count
      from public.pos_sales ps
      where ps.organization_id = p_organization_id
        and ps.status = 'COMPLETED'::public.pos_sale_status
        and (
          (ps.completed_at is not null
            and (timezone(public.analytics_org_timezone(p_organization_id), ps.completed_at))::date
                  between v_from and v_to)
          or (ps.completed_at is null
            and ps.created_at::date between v_from and v_to)
        );

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), '[]'::jsonb)
      into v_rows
      from (
        select
          ps.id,
          ps.status::text,
          ps.completed_at,
          ps.sales_document_id,
          ps.fiscal_document_id
        from public.pos_sales ps
        where ps.organization_id = p_organization_id
          and ps.status = 'COMPLETED'::public.pos_sale_status
          and (
            (ps.completed_at is not null
              and (timezone(public.analytics_org_timezone(p_organization_id), ps.completed_at))::date
                    between v_from and v_to)
            or (ps.completed_at is null
              and ps.created_at::date between v_from and v_to)
          )
        order by ps.completed_at desc nulls last
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, '[]'::jsonb));

    when 'TREASURY_MOVEMENTS' then
      select
        jsonb_build_object(
          'amount_sum', coalesce(sum(o.amount), 0)::numeric(19, 4),
          'count', count(*)::int
        ),
        count(*)
      into v_totals, v_total_count
      from public.treasury_operations o
      where o.organization_id = p_organization_id
        and o.status = 'POSTED'::public.treasury_operation_status
        and o.operation_date >= v_from and o.operation_date <= v_to;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), '[]'::jsonb)
      into v_rows
      from (
        select
          o.id,
          o.internal_number,
          o.operation_type::text,
          o.status::text,
          o.operation_date,
          o.amount,
          o.description
        from public.treasury_operations o
        where o.organization_id = p_organization_id
          and o.status = 'POSTED'::public.treasury_operation_status
          and o.operation_date >= v_from and o.operation_date <= v_to
        order by o.operation_date desc, o.internal_number desc
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, '[]'::jsonb));

    when 'PURCHASES_SUMMARY' then
      select
        jsonb_build_object(
          'total', coalesce(sum(
            case
              when pd.document_type = 'SUPPLIER_CREDIT_NOTE'::public.purchase_document_type
                then -pd.total_amount
              else pd.total_amount
            end
          ), 0)::numeric(19, 4),
          'count', count(*)::int
        ),
        count(*)
      into v_totals, v_total_count
      from public.purchase_documents pd
      where pd.organization_id = p_organization_id
        and pd.status = 'POSTED'::public.purchase_document_status
        and pd.accounting_date >= v_from and pd.accounting_date <= v_to;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), '[]'::jsonb)
      into v_rows
      from (
        select
          pd.id,
          pd.document_type::text,
          pd.document_number,
          pd.issue_date,
          pd.accounting_date,
          pd.status::text,
          pd.total_amount,
          case
            when pd.document_type = 'SUPPLIER_CREDIT_NOTE'::public.purchase_document_type
              then -pd.total_amount
            else pd.total_amount
          end::numeric(19, 4) as signed_total
        from public.purchase_documents pd
        where pd.organization_id = p_organization_id
          and pd.status = 'POSTED'::public.purchase_document_status
          and pd.accounting_date >= v_from and pd.accounting_date <= v_to
        order by pd.accounting_date desc
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, '[]'::jsonb));
  end case;

  return jsonb_build_object(
    'rows', coalesce(v_rows, '[]'::jsonb),
    'totals', coalesce(v_totals, '{}'::jsonb),
    'meta', jsonb_build_object(
      'calculation_version', 1,
      'data_as_of', v_now,
      'generated_at', v_now,
      'report_code', v_code,
      'period_start', v_from,
      'period_end', v_to,
      'limit', v_limit,
      'offset', v_offset,
      'total_count', coalesce(v_total_count, 0),
      'page_count', coalesce(v_page_count, 0),
      'generated_by', v_uid
    )
  );
end;
$$;
revoke all on function public.get_report_dataset(uuid, text, jsonb, int, int) from public, anon;
grant execute on function public.get_report_dataset(uuid, text, jsonb, int, int) to authenticated;
comment on function public.get_report_dataset(uuid, text, jsonb, int, int) is
  'SECURITY DEFINER intentional: allowlisted report_code datasets; capability-gated; totals over full filter; rows paginated.';
-- =============================================================================
-- 9) analytics_management_pnl / analytics_management_balance_sheet
-- =============================================================================

create or replace function public.analytics_management_pnl(
  p_org_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_revenue numeric(19, 4) := 0;
  v_cogs numeric(19, 4) := 0;
  v_opex numeric(19, 4) := 0;
  v_other numeric(19, 4) := 0;
  v_gross numeric(19, 4);
  v_mgmt numeric(19, 4);
  v_has_cogs_mapping boolean := false;
  v_cogs_activity boolean := false;
  v_mapping_status text := 'OK';
  v_now timestamptz := timezone('utc', now());
begin
  v_uid := public.analytics_assert_member(p_org_id);
  perform public.analytics_assert_feature(p_org_id, 'accounting');
  perform public.analytics_assert_capability(
    p_org_id, 'DASHBOARD_FINANCIAL'::public.analytics_capability
  );

  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'invalid period for management pnl';
  end if;

  select exists (
    select 1
    from public.accounts a
    where a.organization_id = p_org_id
      and (
        a.system_role in ('cogs', 'group_cogs')
        or public.analytics_account_is_cogs(a.id)
      )
  ) into v_has_cogs_mapping;

  select
    coalesce(sum(
      case
        when l.account_type = 'REVENUE'::public.account_type
          then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0
      end
    ), 0)::numeric(19, 4),
    coalesce(sum(
      case
        when public.analytics_account_is_cogs(l.account_id)
          then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0
      end
    ), 0)::numeric(19, 4),
    coalesce(sum(
      case
        when l.account_type = 'EXPENSE'::public.account_type
          and not public.analytics_account_is_cogs(l.account_id)
          then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0
      end
    ), 0)::numeric(19, 4)
  into v_revenue, v_cogs, v_opex
  from public.analytics_journal_economic_lines(p_org_id) l
  where l.entry_date >= p_from
    and l.entry_date <= p_to;

  v_other := 0;
  v_gross := (v_revenue - v_cogs)::numeric(19, 4);
  v_mgmt := (v_revenue - v_cogs - v_opex - v_other)::numeric(19, 4);
  v_cogs_activity := abs(v_cogs) > 0.0001;

  if not v_has_cogs_mapping then
    v_mapping_status := 'REPORT_MAPPING_REQUIRES_REVIEW';
  elsif v_revenue <> 0 and not v_cogs_activity and not v_has_cogs_mapping then
    v_mapping_status := 'REPORT_MAPPING_REQUIRES_REVIEW';
  end if;

  return jsonb_build_object(
    'revenue', v_revenue,
    'cogs', v_cogs,
    'gross_result', v_gross,
    'opex', v_opex,
    'other', v_other,
    'management_result', v_mgmt,
    'mapping_status', v_mapping_status,
    'mapping_ok', (v_mapping_status = 'OK'),
    'has_cogs_mapping', v_has_cogs_mapping,
    'disclaimer', 'Reporte gerencial interno — sujeto a revisión profesional',
    'calculation_version', 1,
    'period_start', p_from,
    'period_end', p_to,
    'data_as_of', v_now,
    'generated_at', v_now,
    'generated_by', v_uid
  );
end;
$$;
revoke all on function public.analytics_management_pnl(uuid, date, date) from public, anon;
grant execute on function public.analytics_management_pnl(uuid, date, date) to authenticated;
comment on function public.analytics_management_pnl(uuid, date, date) is
  'SECURITY DEFINER intentional: management P&L; accounting feature + DASHBOARD_FINANCIAL.';
create or replace function public.analytics_management_balance_sheet(
  p_org_id uuid,
  p_as_of date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_assets numeric(19, 4) := 0;
  v_liabilities numeric(19, 4) := 0;
  v_equity numeric(19, 4) := 0;
  v_ytd_revenue numeric(19, 4) := 0;
  v_ytd_expense numeric(19, 4) := 0;
  v_period_result numeric(19, 4);
  v_rhs numeric(19, 4);
  v_diff numeric(19, 4);
  v_status text := 'OK';
  v_year_start date;
  v_fy_found boolean := false;
  v_now timestamptz := timezone('utc', now());
  v_result jsonb;
begin
  v_uid := public.analytics_assert_member(p_org_id);
  perform public.analytics_assert_feature(p_org_id, 'accounting');
  perform public.analytics_assert_capability(
    p_org_id, 'DASHBOARD_FINANCIAL'::public.analytics_capability
  );

  if p_as_of is null then
    raise exception 'p_as_of required';
  end if;

  select fy.start_date into v_year_start
  from public.accounting_fiscal_years fy
  where fy.organization_id = p_org_id
    and fy.start_date <= p_as_of
    and fy.end_date >= p_as_of
  order by fy.start_date desc
  limit 1;

  v_fy_found := v_year_start is not null;

  select
    coalesce(sum(
      case when l.account_type = 'ASSET'::public.account_type
        then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0 end
    ), 0)::numeric(19, 4),
    coalesce(sum(
      case when l.account_type = 'LIABILITY'::public.account_type
        then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0 end
    ), 0)::numeric(19, 4),
    coalesce(sum(
      case when l.account_type = 'EQUITY'::public.account_type
        then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0 end
    ), 0)::numeric(19, 4)
  into v_assets, v_liabilities, v_equity
  from public.analytics_journal_economic_lines(p_org_id) l
  where l.entry_date <= p_as_of
    and l.account_type in (
      'ASSET'::public.account_type,
      'LIABILITY'::public.account_type,
      'EQUITY'::public.account_type
    );

  if v_fy_found then
    select
      coalesce(sum(
        case when l.account_type = 'REVENUE'::public.account_type
          then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
          else 0 end
      ), 0)::numeric(19, 4),
      coalesce(sum(
        case when l.account_type = 'EXPENSE'::public.account_type
          then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
          else 0 end
      ), 0)::numeric(19, 4)
    into v_ytd_revenue, v_ytd_expense
    from public.analytics_journal_economic_lines(p_org_id) l
    where l.entry_date >= v_year_start
      and l.entry_date <= p_as_of
      and l.account_type in (
        'REVENUE'::public.account_type,
        'EXPENSE'::public.account_type
      );

    v_period_result := (v_ytd_revenue - v_ytd_expense)::numeric(19, 4);
    v_rhs := (v_liabilities + v_equity + v_period_result)::numeric(19, 4);
    v_diff := (v_assets - v_rhs)::numeric(19, 4);

    if abs(v_diff) > 0.01 then
      v_status := 'REPORT_ACCOUNTING_MISMATCH';
    end if;
  else
    v_period_result := null;
    v_rhs := (v_liabilities + v_equity)::numeric(19, 4);
    v_diff := (v_assets - v_rhs)::numeric(19, 4);
    v_status := 'REPORT_FISCAL_YEAR_REQUIRES_CONFIG';
  end if;

  v_result := jsonb_build_object(
    'as_of', p_as_of,
    'assets', v_assets,
    'liabilities', v_liabilities,
    'equity', v_equity,
    'resultado_del_periodo', to_jsonb(v_period_result),
    'ytd_start', case when v_fy_found then to_jsonb(v_year_start) else 'null'::jsonb end,
    'equation_rhs', v_rhs,
    'difference', v_diff,
    'status', v_status,
    'disclaimer', 'Reporte gerencial interno — sujeto a revisión profesional. Sin asiento de balanceo.',
    'calculation_version', 1,
    'data_as_of', v_now,
    'generated_at', v_now,
    'generated_by', v_uid
  );

  if v_fy_found then
    v_result := v_result || jsonb_build_object('fiscal_year_start', v_year_start);
  end if;

  return v_result;
end;
$$;
revoke all on function public.analytics_management_balance_sheet(uuid, date) from public, anon;
grant execute on function public.analytics_management_balance_sheet(uuid, date) to authenticated;
comment on function public.analytics_management_balance_sheet(uuid, date) is
  'SECURITY DEFINER intentional: management BS; fiscal year from accounting_fiscal_years (no Jan 1 fallback).';
-- =============================================================================
-- 10) analytics_product_margin_summary — STOCK_ITEM + ISSUE lineage only
-- =============================================================================

create or replace function public.analytics_product_margin_summary(
  p_organization_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_now timestamptz := timezone('utc', now());
  v_revenue numeric(19, 4) := 0;
  v_cogs numeric(19, 4) := 0;
  v_stock_with_lineage int := 0;
  v_stock_missing_lineage int := 0;
  v_service_lines int := 0;
  v_unlinked_lines int := 0;
  v_status text := 'OK';
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, 'fiscal_invoicing');
  perform public.analytics_assert_feature(p_organization_id, 'inventory');

  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'invalid period';
  end if;

  -- Unlinked AUTHORIZED lines (no source_sales_line_id)
  select count(*)::int into v_unlinked_lines
  from public.fiscal_document_lines fdl
  join public.fiscal_documents fd
    on fd.id = fdl.fiscal_document_id
   and fd.organization_id = fdl.organization_id
  where fdl.organization_id = p_organization_id
    and fd.status = 'AUTHORIZED'::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to
    and fdl.source_sales_line_id is null;

  -- SERVICE / NON_STOCK diagnostics (excluded from revenue)
  select count(*)::int into v_service_lines
  from public.fiscal_document_lines fdl
  join public.fiscal_documents fd
    on fd.id = fdl.fiscal_document_id
   and fd.organization_id = fdl.organization_id
  join public.sales_document_lines sdl on sdl.id = fdl.source_sales_line_id
  join public.products p
    on p.id = sdl.product_id
   and p.organization_id = fdl.organization_id
  where fdl.organization_id = p_organization_id
    and fd.status = 'AUTHORIZED'::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to
    and fdl.source_sales_line_id is not null
    and p.product_type in (
      'SERVICE'::public.product_type,
      'NON_STOCK'::public.product_type
    );

  -- STOCK_ITEM lines missing ISSUE lineage → review required
  select count(*)::int into v_stock_missing_lineage
  from public.fiscal_document_lines fdl
  join public.fiscal_documents fd
    on fd.id = fdl.fiscal_document_id
   and fd.organization_id = fdl.organization_id
  join public.sales_document_lines sdl on sdl.id = fdl.source_sales_line_id
  join public.products p
    on p.id = sdl.product_id
   and p.organization_id = fdl.organization_id
  where fdl.organization_id = p_organization_id
    and fd.status = 'AUTHORIZED'::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to
    and fdl.source_sales_line_id is not null
    and p.product_type = 'STOCK_ITEM'::public.product_type
    and not exists (
      select 1
      from public.inventory_operation_lines iol
      join public.inventory_operations io
        on io.id = iol.inventory_operation_id
       and io.organization_id = iol.organization_id
      where iol.organization_id = p_organization_id
        and iol.source_sales_line_id = fdl.source_sales_line_id
        and io.status = 'POSTED'::public.inventory_operation_status
        and io.operation_type = 'ISSUE'::public.inventory_operation_type
    );

  -- Revenue ONLY from STOCK_ITEM with ISSUE lineage
  select
    coalesce(sum(
      coalesce(fdl.net_amount, 0) * public.analytics_fiscal_economic_sign(fdt.operation_kind)
    ), 0)::numeric(19, 4),
    count(*)::int
  into v_revenue, v_stock_with_lineage
  from public.fiscal_document_lines fdl
  join public.fiscal_documents fd
    on fd.id = fdl.fiscal_document_id
   and fd.organization_id = fdl.organization_id
  join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
  join public.sales_document_lines sdl on sdl.id = fdl.source_sales_line_id
  join public.products p
    on p.id = sdl.product_id
   and p.organization_id = fdl.organization_id
  where fdl.organization_id = p_organization_id
    and fd.status = 'AUTHORIZED'::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to
    and fdl.source_sales_line_id is not null
    and p.product_type = 'STOCK_ITEM'::public.product_type
    and exists (
      select 1
      from public.inventory_operation_lines iol
      join public.inventory_operations io
        on io.id = iol.inventory_operation_id
       and io.organization_id = iol.organization_id
      where iol.organization_id = p_organization_id
        and iol.source_sales_line_id = fdl.source_sales_line_id
        and io.status = 'POSTED'::public.inventory_operation_status
        and io.operation_type = 'ISSUE'::public.inventory_operation_type
    );

  -- COGS from inventory ISSUE ledger for those same sales lines
  select coalesce(sum(abs(ile.value_delta)), 0)::numeric(19, 4)
  into v_cogs
  from public.inventory_ledger_entries ile
  join public.inventory_operation_lines iol
    on iol.id = ile.inventory_operation_line_id
   and iol.organization_id = ile.organization_id
  join public.inventory_operations io
    on io.id = iol.inventory_operation_id
   and io.organization_id = iol.organization_id
  where ile.organization_id = p_organization_id
    and io.status = 'POSTED'::public.inventory_operation_status
    and io.operation_type = 'ISSUE'::public.inventory_operation_type
    and iol.source_sales_line_id is not null
    and exists (
      select 1
      from public.fiscal_document_lines fdl2
      join public.fiscal_documents fd2
        on fd2.id = fdl2.fiscal_document_id
       and fd2.organization_id = fdl2.organization_id
      join public.sales_document_lines sdl2 on sdl2.id = fdl2.source_sales_line_id
      join public.products p2
        on p2.id = sdl2.product_id
       and p2.organization_id = fdl2.organization_id
      where fdl2.organization_id = p_organization_id
        and fdl2.source_sales_line_id = iol.source_sales_line_id
        and fd2.status = 'AUTHORIZED'::public.fiscal_document_status
        and fd2.issue_date >= p_from
        and fd2.issue_date <= p_to
        and p2.product_type = 'STOCK_ITEM'::public.product_type
    );

  if v_stock_missing_lineage > 0 then
    v_status := 'MARGIN_LINEAGE_REQUIRES_REVIEW';
  end if;

  return jsonb_build_object(
    'status', v_status,
    'signed_net_revenue_linked_lines', v_revenue,
    'inventory_cogs_linked', v_cogs,
    'product_gross_margin', case
      when v_status = 'OK' then (v_revenue - v_cogs)::numeric(19, 4)
      else null
    end,
    'stock_lines_with_lineage', v_stock_with_lineage,
    'stock_lines_missing_lineage', v_stock_missing_lineage,
    'service_non_stock_lines', v_service_lines,
    'unlinked_fiscal_lines', v_unlinked_lines,
    'linked_fiscal_lines', v_stock_with_lineage,
    'note', 'SERVICE/NON_STOCK excluded from revenue. STOCK_ITEM requires ISSUE lineage. Never use default_purchase_price. Never gross-total − COGS.',
    'calculation_version', 1,
    'period_start', p_from,
    'period_end', p_to,
    'data_as_of', v_now,
    'generated_at', v_now,
    'generated_by', v_uid
  );
end;
$$;
revoke all on function public.analytics_product_margin_summary(uuid, date, date)
  from public, anon;
grant execute on function public.analytics_product_margin_summary(uuid, date, date)
  to authenticated;
comment on function public.analytics_product_margin_summary(uuid, date, date) is
  'SECURITY DEFINER intentional: STOCK_ITEM revenue with ISSUE lineage only; SERVICE/NON_STOCK excluded.';
-- =============================================================================
-- 12) Metric registry ACL
-- =============================================================================

revoke insert, update, delete on table public.analytics_metric_definitions from authenticated;
grant select on table public.analytics_metric_definitions to authenticated;
grant all on table public.analytics_metric_definitions to service_role;
-- =============================================================================
-- 13) Grants / comments — helpers internal-only; document intentional client RPCs
-- =============================================================================

revoke all on function public.analytics_member_role(uuid) from public, anon, authenticated;
revoke all on function public.analytics_has_capability(uuid, public.analytics_capability)
  from public, anon, authenticated;
revoke all on function public.analytics_assert_capability(uuid, public.analytics_capability)
  from public, anon, authenticated;
revoke all on function public.analytics_validate_saved_report_config(text, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
comment on function public.analytics_member_role(uuid) is
  'Internal helper: member_role of auth.uid() for org. Not granted to authenticated.';
comment on function public.analytics_has_capability(uuid, public.analytics_capability) is
  'Internal helper: role→capability map mirroring ROLE_PERMISSIONS. Not granted to authenticated.';
comment on function public.analytics_assert_capability(uuid, public.analytics_capability) is
  'Internal helper: raise if capability missing. Called from intentional client RPCs.';
comment on function public.analytics_validate_saved_report_config(text, jsonb, jsonb, jsonb) is
  'Internal helper: allowlist + forbidden-key validation for saved report JSON.';
comment on function public.get_dashboard_summary(uuid, text, date, date, text) is
  'SECURITY DEFINER intentional client RPC. Authz: member + dashboard + DASHBOARD_BASIC; tiles gated by capability+feature.';
comment on function public.get_financial_dashboard(uuid, text, date, date, text) is
  'SECURITY DEFINER intentional client RPC. Requires DASHBOARD_FINANCIAL.';
comment on function public.get_ar_aging(uuid, date) is
  'SECURITY DEFINER intentional client RPC. Requires DASHBOARD_FINANCIAL.';
comment on function public.get_ap_aging(uuid, date) is
  'SECURITY DEFINER intentional client RPC. Requires DASHBOARD_FINANCIAL.';
comment on function public.get_attention_summary(uuid) is
  'SECURITY DEFINER intentional client RPC. Requires ALERT_READ; sanitizes for non-FINANCIAL.';
comment on function public.get_report_dataset(uuid, text, jsonb, int, int) is
  'SECURITY DEFINER intentional client RPC. Capability per report_code; totals over full filter.';
comment on function public.evaluate_analytics_alerts(uuid) is
  'SECURITY DEFINER intentional client RPC. Requires ALERT_EVALUATE.';
comment on function public.ack_analytics_alert(uuid) is
  'SECURITY DEFINER intentional client RPC. Requires ALERT_ACK.';
comment on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid) is
  'SECURITY DEFINER intentional client RPC. Validates config allowlist before write.';
comment on function public.analytics_management_pnl(uuid, date, date) is
  'SECURITY DEFINER intentional client RPC. accounting + DASHBOARD_FINANCIAL.';
comment on function public.analytics_management_balance_sheet(uuid, date) is
  'SECURITY DEFINER intentional client RPC. Fiscal year from accounting_fiscal_years; no Jan 1 fallback.';
comment on function public.analytics_product_margin_summary(uuid, date, date) is
  'SECURITY DEFINER intentional client RPC. STOCK_ITEM + ISSUE lineage margin only.';
