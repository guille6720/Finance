-- Phase 9: POS helpers, engine guards, tender validation

create or replace function public.pos_assert_feature(p_org_id uuid)
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
      and fc.code = 'pos'
      and ofeat.status = 'enabled'
  ) then
    raise exception 'feature pos is not enabled';
  end if;

  if not exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = 'sales'
      and ofeat.status = 'enabled'
  ) then
    raise exception 'feature sales is required for POS';
  end if;
end;
$$;
create or replace function public.pos_assert_feature_code(p_org_id uuid, p_code text)
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
      and fc.code = p_code
      and ofeat.status = 'enabled'
  ) then
    raise exception 'feature % is required', p_code;
  end if;
end;
$$;
create or replace function public.pos_expected_account_type(p_method public.pos_tender_method)
returns public.treasury_account_type
language sql
immutable
set search_path = ''
as $$
  select case p_method
    when 'CASH' then 'CASH'::public.treasury_account_type
    when 'BANK_TRANSFER' then 'BANK'::public.treasury_account_type
    when 'CARD' then 'CLEARING'::public.treasury_account_type
    when 'QR' then 'CLEARING'::public.treasury_account_type
  end;
$$;
create or replace function public.pos_validate_walk_in_customer(
  p_org_id uuid,
  p_customer_id uuid
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
    from public.counterparties c
    join public.counterparty_roles r
      on r.counterparty_id = c.id and r.organization_id = c.organization_id
    where c.organization_id = p_org_id
      and c.id = p_customer_id
      and c.is_active
      and r.role = 'CUSTOMER'
  ) then
    raise exception 'walk-in customer must be active CUSTOMER in same organization';
  end if;
end;
$$;
create or replace function public.pos_validate_tender_account(
  p_org_id uuid,
  p_terminal_id uuid,
  p_method public.pos_tender_method,
  p_treasury_account_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ta public.treasury_accounts%rowtype;
  v_expected public.treasury_account_type;
begin
  v_expected := public.pos_expected_account_type(p_method);

  select * into v_ta
  from public.treasury_accounts
  where id = p_treasury_account_id
    and organization_id = p_org_id;

  if not found then
    raise exception 'treasury account not found';
  end if;
  if not v_ta.is_active then
    raise exception 'treasury account is inactive';
  end if;
  if v_ta.currency_code is distinct from 'ARS' then
    raise exception 'POS tenders require ARS treasury accounts';
  end if;
  if v_ta.account_type is distinct from v_expected then
    raise exception 'tender method % requires treasury_account_type % (got %)',
      p_method, v_expected, v_ta.account_type;
  end if;

  if not exists (
    select 1 from public.pos_terminal_tender_accounts
    where organization_id = p_org_id
      and terminal_id = p_terminal_id
      and method = p_method
      and treasury_account_id = p_treasury_account_id
      and active
  ) then
    raise exception 'treasury account not mapped for terminal method %', p_method;
  end if;
end;
$$;
create or replace function public.prevent_pos_sale_engine_forgery()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_setting('pos.engine_write', true) = '1' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.status is distinct from old.status
      or new.fiscal_document_id is distinct from old.fiscal_document_id
      or new.inventory_operation_id is distinct from old.inventory_operation_id
      or new.completed_at is distinct from old.completed_at
      or new.completed_by is distinct from old.completed_by
      or new.checkout_started_at is distinct from old.checkout_started_at
      or new.sales_document_id is distinct from old.sales_document_id
      or new.session_id is distinct from old.session_id
      or new.terminal_id is distinct from old.terminal_id
    then
      raise exception 'pos_sales engine fields are trusted-only';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists pos_sales_engine_guard on public.pos_sales;
create trigger pos_sales_engine_guard
before update on public.pos_sales
for each row execute function public.prevent_pos_sale_engine_forgery();
create or replace function public.prevent_pos_tender_engine_forgery()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_setting('pos.engine_write', true) = '1' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.status = 'POSTED' or new.status = 'POSTED' or new.treasury_operation_id is not null then
      if current_setting('pos.engine_write', true) is distinct from '1' then
        raise exception 'pos_tenders engine fields are trusted-only';
      end if;
    end if;
    -- DRAFT tender edits allowed until FINALIZING/COMPLETED/CANCELLED
    if exists (
      select 1 from public.pos_sales s
      where s.id = old.pos_sale_id
        and s.status in ('FINALIZING', 'COMPLETED', 'CANCELLED', 'RECONCILIATION_REQUIRED')
    ) then
      raise exception 'cannot mutate tenders in status %', (
        select status from public.pos_sales where id = old.pos_sale_id
      );
    end if;
  end if;

  if tg_op = 'INSERT' then
    if new.status is distinct from 'DRAFT' or new.treasury_operation_id is not null then
      if current_setting('pos.engine_write', true) is distinct from '1' then
        raise exception 'pos_tenders insert must be DRAFT without treasury_operation_id';
      end if;
    end if;
  end if;

  return new;
end;
$$;
drop trigger if exists pos_tenders_engine_guard on public.pos_tenders;
create trigger pos_tenders_engine_guard
before insert or update on public.pos_tenders
for each row execute function public.prevent_pos_tender_engine_forgery();
create or replace function public.prevent_pos_session_expected_forgery()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_setting('pos.engine_write', true) = '1' then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if new.opening_expected_cash is distinct from old.opening_expected_cash
      or new.closing_expected_cash is distinct from old.closing_expected_cash
      or new.closing_difference is distinct from old.closing_difference
      or new.status is distinct from old.status
      or new.closed_at is distinct from old.closed_at
    then
      raise exception 'pos_sessions expected/close fields are trusted-only';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists pos_sessions_engine_guard on public.pos_sessions;
create trigger pos_sessions_engine_guard
before update on public.pos_sessions
for each row execute function public.prevent_pos_session_expected_forgery();
create or replace function public.pos_tta_validate_before_write()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_ta public.treasury_accounts%rowtype;
  v_expected public.treasury_account_type;
begin
  v_expected := public.pos_expected_account_type(new.method);
  select * into v_ta from public.treasury_accounts where id = new.treasury_account_id;
  if not found or v_ta.organization_id is distinct from new.organization_id then
    raise exception 'invalid treasury account for tender mapping';
  end if;
  if not v_ta.is_active then raise exception 'treasury account inactive'; end if;
  if v_ta.currency_code is distinct from 'ARS' then raise exception 'ARS required'; end if;
  if v_ta.account_type is distinct from v_expected then
    raise exception 'method % requires account_type %', new.method, v_expected;
  end if;
  return new;
end;
$$;
drop trigger if exists pos_tta_validate_trg on public.pos_terminal_tender_accounts;
create trigger pos_tta_validate_trg
before insert or update on public.pos_terminal_tender_accounts
for each row execute function public.pos_tta_validate_before_write();
create or replace function public.pos_terminal_validate_before_write()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_fpos public.fiscal_points_of_sale%rowtype;
begin
  if new.fiscal_point_of_sale_id is not null then
    select * into v_fpos from public.fiscal_points_of_sale where id = new.fiscal_point_of_sale_id;
    if not found then raise exception 'fiscal point of sale not found'; end if;
    if v_fpos.organization_id is distinct from new.organization_id then
      raise exception 'fiscal point of sale organization mismatch';
    end if;
    if not v_fpos.is_active then raise exception 'fiscal point of sale inactive'; end if;
    if v_fpos.environment = 'PRODUCTION' then
      raise exception 'PRODUCTION fiscal point of sale blocked for POS staging';
    end if;
    if v_fpos.branch_id is not null and v_fpos.branch_id is distinct from new.branch_id then
      raise exception 'fiscal point of sale branch mismatch';
    end if;
  end if;

  if new.default_customer_id is not null then
    perform public.pos_validate_walk_in_customer(new.organization_id, new.default_customer_id);
  end if;

  return new;
end;
$$;
drop trigger if exists pos_terminals_validate_trg on public.pos_terminals;
create trigger pos_terminals_validate_trg
before insert or update on public.pos_terminals
for each row execute function public.pos_terminal_validate_before_write();
create or replace function public.pos_settings_validate_before_write()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform public.pos_validate_walk_in_customer(new.organization_id, new.default_walk_in_customer_id);
  return new;
end;
$$;
drop trigger if exists pos_settings_validate_trg on public.pos_settings;
create trigger pos_settings_validate_trg
before insert or update on public.pos_settings
for each row execute function public.pos_settings_validate_before_write();
revoke all on function public.pos_assert_feature(uuid) from public, anon, authenticated;
revoke all on function public.pos_assert_feature_code(uuid, text) from public, anon, authenticated;
revoke all on function public.pos_validate_walk_in_customer(uuid, uuid) from public, anon, authenticated;
revoke all on function public.pos_validate_tender_account(uuid, uuid, public.pos_tender_method, uuid)
  from public, anon, authenticated;
revoke all on function public.pos_expected_account_type(public.pos_tender_method) from public, anon;
grant execute on function public.pos_expected_account_type(public.pos_tender_method) to authenticated;
