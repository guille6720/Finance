-- Phase 11: core analytics helpers
-- search_path='' everywhere. Internal helpers REVOKE from public/anon/authenticated.
-- Canonical GL economic scope: journal_entries.status IN ('POSTED','REVERSED')

-- ---------------------------------------------------------------------------
-- 1) analytics_assert_service_role
-- ---------------------------------------------------------------------------

create or replace function public.analytics_assert_service_role()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'analytics platform operation requires service_role';
  end if;
end;
$$;
revoke all on function public.analytics_assert_service_role() from public, anon, authenticated;
grant execute on function public.analytics_assert_service_role() to service_role;
-- ---------------------------------------------------------------------------
-- 2) analytics_assert_member
-- ---------------------------------------------------------------------------

create or replace function public.analytics_assert_member(p_org_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;
  if p_org_id is null then
    raise exception 'organization_id required';
  end if;
  if not public.is_org_member(p_org_id) then
    raise exception 'not a member of organization';
  end if;
  return v_uid;
end;
$$;
revoke all on function public.analytics_assert_member(uuid) from public, anon, authenticated;
-- ---------------------------------------------------------------------------
-- Feature helpers
-- ---------------------------------------------------------------------------

create or replace function public.analytics_feature_enabled(
  p_org_id uuid,
  p_feature_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = p_feature_code
      and ofeat.status = 'enabled'
  );
$$;
revoke all on function public.analytics_feature_enabled(uuid, text) from public, anon, authenticated;
create or replace function public.analytics_assert_feature(
  p_org_id uuid,
  p_feature_code text
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.analytics_feature_enabled(p_org_id, p_feature_code) then
    raise exception 'feature % is not enabled', p_feature_code;
  end if;
end;
$$;
revoke all on function public.analytics_assert_feature(uuid, text) from public, anon, authenticated;
create or replace function public.analytics_assert_any_feature(
  p_org_id uuid,
  p_feature_codes text[]
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = any (p_feature_codes)
      and ofeat.status = 'enabled'
  ) then
    raise exception 'required analytics feature not enabled (% )', array_to_string(p_feature_codes, ',');
  end if;
end;
$$;
revoke all on function public.analytics_assert_any_feature(uuid, text[]) from public, anon, authenticated;
-- ---------------------------------------------------------------------------
-- 3) analytics_org_timezone
-- ---------------------------------------------------------------------------

create or replace function public.analytics_org_timezone(p_org_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select o.timezone from public.organizations o where o.id = p_org_id),
    'America/Argentina/Buenos_Aires'
  );
$$;
revoke all on function public.analytics_org_timezone(uuid) from public, anon, authenticated;
-- ---------------------------------------------------------------------------
-- 4) analytics_period_bounds
-- Presets use organizations.timezone for "today"/week/month boundaries.
-- DATE columns remain DATE (no timestamptz shift on stored dates).
-- ---------------------------------------------------------------------------

create or replace function public.analytics_period_bounds(
  p_org_id uuid,
  p_preset text,
  p_from date default null,
  p_to date default null
)
returns table (period_start date, period_end date)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz text;
  v_today date;
  v_preset text := upper(coalesce(nullif(trim(p_preset), ''), 'THIS_MONTH'));
  v_month_start date;
  v_q_month int;
begin
  v_tz := public.analytics_org_timezone(p_org_id);
  v_today := (timezone(v_tz, timezone('utc', now())))::date;

  if v_preset = 'CUSTOM' then
    if p_from is null or p_to is null then
      raise exception 'CUSTOM period requires p_from and p_to';
    end if;
    if p_from > p_to then
      raise exception 'period_start must be <= period_end';
    end if;
    period_start := p_from;
    period_end := p_to;
    return next;
    return;
  end if;

  if v_preset = 'TODAY' then
    period_start := v_today;
    period_end := v_today;
  elsif v_preset = 'THIS_WEEK' then
    -- ISO week: Monday start
    period_start := v_today - ((extract(isodow from v_today)::int) - 1);
    period_end := period_start + 6;
  elsif v_preset = 'THIS_MONTH' then
    period_start := date_trunc('month', v_today::timestamp)::date;
    period_end := (date_trunc('month', v_today::timestamp) + interval '1 month' - interval '1 day')::date;
  elsif v_preset = 'PREV_MONTH' then
    v_month_start := (date_trunc('month', v_today::timestamp) - interval '1 month')::date;
    period_start := v_month_start;
    period_end := (date_trunc('month', v_today::timestamp) - interval '1 day')::date;
  elsif v_preset = 'THIS_QUARTER' then
    v_q_month := ((extract(month from v_today)::int - 1) / 3) * 3 + 1;
    period_start := make_date(extract(year from v_today)::int, v_q_month, 1);
    period_end := (period_start + interval '3 months' - interval '1 day')::date;
  elsif v_preset = 'THIS_YEAR' then
    period_start := make_date(extract(year from v_today)::int, 1, 1);
    period_end := make_date(extract(year from v_today)::int, 12, 31);
  else
    raise exception 'unsupported period preset: %', p_preset;
  end if;

  return next;
end;
$$;
revoke all on function public.analytics_period_bounds(uuid, text, date, date)
  from public, anon, authenticated;
-- ---------------------------------------------------------------------------
-- 5) analytics_fiscal_economic_sign — thin wrapper → tax_fiscal_vat_economic_sign
-- ---------------------------------------------------------------------------

create or replace function public.analytics_fiscal_economic_sign(
  p_operation_kind public.fiscal_operation_kind
)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select public.tax_fiscal_vat_economic_sign(p_operation_kind);
$$;
revoke all on function public.analytics_fiscal_economic_sign(public.fiscal_operation_kind)
  from public, anon, authenticated;
comment on function public.analytics_fiscal_economic_sign(public.fiscal_operation_kind) is
  'Thin wrapper over tax_fiscal_vat_economic_sign: INVOICE/DN +1, CN -1.';
-- ---------------------------------------------------------------------------
-- 6) Economic journal status helpers
-- Canonical: status IN ('POSTED','REVERSED')
-- ---------------------------------------------------------------------------

create or replace function public.analytics_is_economic_journal_status(
  p_status public.journal_entry_status
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_status in ('POSTED'::public.journal_entry_status, 'REVERSED'::public.journal_entry_status);
$$;
revoke all on function public.analytics_is_economic_journal_status(public.journal_entry_status)
  from public, anon, authenticated;
comment on function public.analytics_is_economic_journal_status(public.journal_entry_status) is
  'Canonical GL economic scope: POSTED + REVERSED (original REVERSED + reversing POSTED net to 0).';
create or replace function public.analytics_journal_economic_lines(p_org_id uuid)
returns table (
  journal_entry_id uuid,
  entry_date date,
  account_id uuid,
  account_type public.account_type,
  normal_balance public.normal_balance,
  system_role text,
  account_code text,
  parent_id uuid,
  debit numeric(19, 4),
  credit numeric(19, 4),
  line_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    je.id as journal_entry_id,
    je.entry_date,
    jel.account_id,
    a.account_type,
    a.normal_balance,
    a.system_role,
    a.code as account_code,
    a.parent_id,
    jel.debit::numeric(19, 4),
    jel.credit::numeric(19, 4),
    jel.id as line_id
  from public.journal_entry_lines jel
  join public.journal_entries je
    on je.id = jel.journal_entry_id
   and je.organization_id = jel.organization_id
  join public.accounts a
    on a.id = jel.account_id
   and a.organization_id = jel.organization_id
  where jel.organization_id = p_org_id
    and public.analytics_is_economic_journal_status(je.status)
    and a.account_type is distinct from 'MEMORANDUM'::public.account_type;
$$;
revoke all on function public.analytics_journal_economic_lines(uuid) from public, anon, authenticated;
-- COGS account predicate: system_role cogs OR ancestor group_cogs
create or replace function public.analytics_account_is_cogs(p_account_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  walk uuid := p_account_id;
  hops int := 0;
  v_role text;
begin
  while walk is not null loop
    hops := hops + 1;
    if hops > 30 then
      return false;
    end if;
    select system_role, parent_id into v_role, walk
    from public.accounts
    where id = walk;
    if not found then
      return false;
    end if;
    if v_role in ('cogs', 'group_cogs') then
      return true;
    end if;
  end loop;
  return false;
end;
$$;
revoke all on function public.analytics_account_is_cogs(uuid) from public, anon, authenticated;
-- ---------------------------------------------------------------------------
-- 7–8) Fiscal sales aggregates
-- ---------------------------------------------------------------------------

create or replace function public.analytics_sales_fiscal_net(
  p_org_id uuid,
  p_from date,
  p_to date,
  p_env text default null
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(
    (
      coalesce(fd.net_taxed_amount, 0)
      + coalesce(fd.net_exempt_amount, 0)
      + coalesce(fd.net_untaxed_amount, 0)
    ) * public.analytics_fiscal_economic_sign(fdt.operation_kind)
  ), 0)::numeric(19, 4)
  from public.fiscal_documents fd
  join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
  where fd.organization_id = p_org_id
    and fd.status = 'AUTHORIZED'::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to
    and (
      p_env is null
      or fd.fiscal_environment::text = p_env
    );
$$;
revoke all on function public.analytics_sales_fiscal_net(uuid, date, date, text)
  from public, anon, authenticated;
create or replace function public.analytics_sales_fiscal_gross(
  p_org_id uuid,
  p_from date,
  p_to date,
  p_env text default null
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(
    coalesce(fd.total_amount, 0) * public.analytics_fiscal_economic_sign(fdt.operation_kind)
  ), 0)::numeric(19, 4)
  from public.fiscal_documents fd
  join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
  where fd.organization_id = p_org_id
    and fd.status = 'AUTHORIZED'::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to
    and (
      p_env is null
      or fd.fiscal_environment::text = p_env
    );
$$;
revoke all on function public.analytics_sales_fiscal_gross(uuid, date, date, text)
  from public, anon, authenticated;
-- Signed money helper by normal balance
create or replace function public.analytics_signed_balance(
  p_debit numeric,
  p_credit numeric,
  p_normal public.normal_balance
)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case p_normal
    when 'DEBIT'::public.normal_balance then (coalesce(p_debit, 0) - coalesce(p_credit, 0))
    else (coalesce(p_credit, 0) - coalesce(p_debit, 0))
  end::numeric(19, 4);
$$;
revoke all on function public.analytics_signed_balance(numeric, numeric, public.normal_balance)
  from public, anon, authenticated;
-- Previous period bounds (same length immediately before)
create or replace function public.analytics_prev_period_bounds(
  p_start date,
  p_end date
)
returns table (period_start date, period_end date)
language sql
immutable
set search_path = ''
as $$
  select
    (p_start - (p_end - p_start + 1))::date,
    (p_start - 1)::date;
$$;
revoke all on function public.analytics_prev_period_bounds(date, date)
  from public, anon, authenticated;
