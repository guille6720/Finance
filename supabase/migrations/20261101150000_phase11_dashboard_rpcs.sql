-- Phase 11: dashboard client RPCs
-- Auth: auth.uid + membership + feature gates. SECURITY DEFINER with intentional grants.

create or replace function public.analytics_metric_payload(
  p_code text,
  p_value numeric,
  p_label text,
  p_unit text,
  p_compare_value numeric default null,
  p_compare_available boolean default false
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'code', p_code,
    'value', p_value,
    'label', p_label,
    'unit', p_unit,
    'calculation_version', 1,
    'comparison', case
      when p_compare_available then jsonb_build_object(
        'mode', 'PREV_PERIOD',
        'value', p_compare_value,
        'delta', (p_value - coalesce(p_compare_value, 0))
      )
      else jsonb_build_object('mode', 'NONE', 'available', false, 'message', 'Sin período comparable')
    end
  );
$$;
revoke all on function public.analytics_metric_payload(text, numeric, text, text, numeric, boolean)
  from public, anon, authenticated;
-- ---------------------------------------------------------------------------
-- AR / AP open helpers
-- ---------------------------------------------------------------------------

create or replace function public.analytics_ar_open_total(p_org_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(
    case
      when ari.direction = 'AR_INCREASE'::public.accounts_receivable_direction then ari.open_amount
      else -ari.open_amount
    end
  ), 0)::numeric(19, 4)
  from public.accounts_receivable_items ari
  where ari.organization_id = p_org_id
    and ari.status in (
      'OPEN'::public.accounts_receivable_status,
      'PARTIALLY_COLLECTED'::public.accounts_receivable_status
    )
    and ari.open_amount > 0;
$$;
revoke all on function public.analytics_ar_open_total(uuid) from public, anon, authenticated;
create or replace function public.analytics_ap_open_total(p_org_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(
    case
      when api.direction = 'AP_INCREASE'::public.accounts_payable_direction then api.open_amount
      else -api.open_amount
    end
  ), 0)::numeric(19, 4)
  from public.accounts_payable_items api
  where api.organization_id = p_org_id
    and api.status in (
      'OPEN'::public.accounts_payable_status,
      'PARTIALLY_PAID'::public.accounts_payable_status
    )
    and api.open_amount > 0;
$$;
revoke all on function public.analytics_ap_open_total(uuid) from public, anon, authenticated;
create or replace function public.analytics_treasury_type_balance(
  p_org_id uuid,
  p_account_type public.treasury_account_type
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(public.treasury_account_balance(ta.id)), 0)::numeric(19, 4)
  from public.treasury_accounts ta
  where ta.organization_id = p_org_id
    and ta.account_type = p_account_type
    and ta.is_active;
$$;
revoke all on function public.analytics_treasury_type_balance(uuid, public.treasury_account_type)
  from public, anon, authenticated;
create or replace function public.analytics_aging_bucket(
  p_due_date date,
  p_as_of date
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_due_date is null then 'NO_DUE_DATE'
    when p_due_date >= p_as_of then 'NOT_DUE'
    when (p_as_of - p_due_date) between 1 and 30 then 'OVERDUE_1_30'
    when (p_as_of - p_due_date) between 31 and 60 then 'OVERDUE_31_60'
    when (p_as_of - p_due_date) between 61 and 90 then 'OVERDUE_61_90'
    else 'OVERDUE_90_PLUS'
  end;
$$;
revoke all on function public.analytics_aging_bucket(date, date) from public, anon, authenticated;
-- ---------------------------------------------------------------------------
-- get_ar_aging / get_ap_aging
-- ---------------------------------------------------------------------------

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
-- ---------------------------------------------------------------------------
-- get_financial_dashboard
-- ---------------------------------------------------------------------------

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

  if not public.has_org_role(
    p_organization_id,
    array['owner','admin','accountant','manager']::public.member_role[]
  ) then
    raise exception 'insufficient role for financial dashboard';
  end if;

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
-- ---------------------------------------------------------------------------
-- get_dashboard_summary
-- ---------------------------------------------------------------------------

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
  v_val numeric(19, 4);
  v_prev numeric(19, 4);
  v_pnl jsonb;
  v_tax numeric(19, 4);
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, 'dashboard');

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

  v_sections := jsonb_build_object(
    'resumen', true,
    'finanzas', (v_feat_cash or v_feat_banks or v_feat_accounting),
    'ventas', (v_feat_sales or v_feat_fiscal),
    'compras', v_feat_purchases,
    'stock', v_feat_inventory,
    'impuestos', v_feat_taxes,
    'atencion', true
  );

  if v_feat_fiscal then
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

  if v_feat_cash or v_feat_banks then
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

  if v_feat_pos then
    v_metrics := v_metrics || jsonb_build_object(
      'CLEARING_PENDING',
      public.analytics_metric_payload(
        'CLEARING_PENDING',
        public.analytics_treasury_type_balance(p_organization_id, 'CLEARING'::public.treasury_account_type),
        'Tarjetas/QR pendientes', 'CURRENCY'
      )
    );
  end if;

  if v_feat_sales then
    v_metrics := v_metrics || jsonb_build_object(
      'AR_OPEN',
      public.analytics_metric_payload(
        'AR_OPEN', public.analytics_ar_open_total(p_organization_id),
        'Cuentas por cobrar abiertas', 'CURRENCY'
      )
    );
  end if;

  if v_feat_purchases then
    v_metrics := v_metrics || jsonb_build_object(
      'AP_OPEN',
      public.analytics_metric_payload(
        'AP_OPEN', public.analytics_ap_open_total(p_organization_id),
        'Cuentas por pagar abiertas', 'CURRENCY'
      )
    );
  end if;

  if v_feat_inventory then
    select coalesce(sum(ics.inventory_value), 0)::numeric(19, 4) into v_val
    from public.inventory_cost_state ics
    where ics.organization_id = p_organization_id;
    v_metrics := v_metrics || jsonb_build_object(
      'INVENTORY_VALUE',
      public.analytics_metric_payload('INVENTORY_VALUE', v_val, 'Inventario valorizado', 'CURRENCY')
    );
  end if;

  if v_feat_taxes
    and public.has_org_role(
      p_organization_id,
      array['owner','admin','accountant']::public.member_role[]
    )
  then
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

  if v_feat_accounting
    and public.has_org_role(
      p_organization_id,
      array['owner','admin','accountant']::public.member_role[]
    )
  then
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

  if v_feat_cash or v_feat_banks then
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
  'SECURITY DEFINER intentional: composite dashboard KPIs; membership + dashboard feature; tiles gated by module features/roles.';
comment on function public.get_financial_dashboard(uuid, text, date, date, text) is
  'SECURITY DEFINER intentional: cash/bank/clearing/AR/AP/collections/payments; role-gated.';
comment on function public.get_ar_aging(uuid, date) is
  'SECURITY DEFINER intentional: AR aging by due_date vs as_of DATE (no TZ shift on DATE).';
comment on function public.get_ap_aging(uuid, date) is
  'SECURITY DEFINER intentional: AP aging by due_date vs as_of DATE (no TZ shift on DATE).';
