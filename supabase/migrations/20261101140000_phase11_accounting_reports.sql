-- Phase 11: management P&L + balance sheet RPCs
-- Economic GL scope: POSTED + REVERSED. No balancing plug journals.
-- Label: gerencial interno — sujeto a revisión profesional.

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
  'SECURITY DEFINER intentional: org-scoped management P&L; auth via analytics_assert_member + accounting feature.';
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
  v_period_result numeric(19, 4) := 0;
  v_rhs numeric(19, 4);
  v_diff numeric(19, 4);
  v_status text := 'OK';
  v_year_start date;
  v_now timestamptz := timezone('utc', now());
begin
  v_uid := public.analytics_assert_member(p_org_id);
  perform public.analytics_assert_feature(p_org_id, 'accounting');

  if p_as_of is null then
    raise exception 'p_as_of required';
  end if;

  -- Calendar year containing as_of (Jan 1 → as_of)
  v_year_start := make_date(extract(year from p_as_of)::int, 1, 1);

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

  -- YTD P&L net (revenue − expenses including COGS)
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

  return jsonb_build_object(
    'as_of', p_as_of,
    'assets', v_assets,
    'liabilities', v_liabilities,
    'equity', v_equity,
    'resultado_del_periodo', v_period_result,
    'ytd_start', v_year_start,
    'equation_rhs', v_rhs,
    'difference', v_diff,
    'status', v_status,
    'disclaimer', 'Reporte gerencial interno — sujeto a revisión profesional. Sin asiento de balanceo.',
    'calculation_version', 1,
    'data_as_of', v_now,
    'generated_at', v_now,
    'generated_by', v_uid
  );
end;
$$;
revoke all on function public.analytics_management_balance_sheet(uuid, date) from public, anon;
grant execute on function public.analytics_management_balance_sheet(uuid, date) to authenticated;
comment on function public.analytics_management_balance_sheet(uuid, date) is
  'SECURITY DEFINER intentional: management BS as-of; no plug journal; mismatch reported when |diff|>0.01.';
