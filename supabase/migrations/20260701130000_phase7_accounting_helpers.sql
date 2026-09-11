-- Phase 7 — Treasury posting / reverse / compensation RPCs

create or replace function public.treasury_assert_feature(
  p_org_id uuid,
  p_codes text[]
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare v_ok boolean;
begin
  select exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = any(p_codes)
      and ofeat.status = 'enabled'
  ) into v_ok;
  if not coalesce(v_ok, false) then
    raise exception 'required treasury feature not enabled (cash and/or banks)';
  end if;
end;
$$;
create or replace function public.next_treasury_operation_number(
  p_org_id uuid,
  p_operation_type public.treasury_operation_type
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year int := extract(year from timezone('utc', now()))::int;
  v_next bigint;
  v_prefix text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  perform public.treasury_assert_feature(p_org_id, array['cash','banks']);
  if not public.has_org_role(
    p_org_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role';
  end if;

  v_prefix := case p_operation_type
    when 'OPENING_BALANCE' then 'OPN'
    when 'PAYMENT' then 'PAY'
    when 'COLLECTION' then 'COL'
    when 'TRANSFER' then 'TRF'
    when 'ADJUSTMENT' then 'ADJ'
  end;

  insert into public.treasury_operation_sequences (organization_id, operation_type, sequence_year, last_value)
  values (p_org_id, p_operation_type, v_year, 1)
  on conflict (organization_id, operation_type, sequence_year)
  do update set
    last_value = public.treasury_operation_sequences.last_value + 1,
    updated_at = timezone('utc', now())
  returning last_value into v_next;

  return v_prefix || '-' || v_year::text || '-' || lpad(v_next::text, 6, '0');
end;
$$;
create or replace function public.resolve_ap_account(p_org_id uuid)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare v_id uuid;
begin
  select accounts_payable_account_id into v_id
  from public.treasury_accounting_mappings where organization_id = p_org_id;
  if v_id is null then
    select accounts_payable_account_id into v_id
    from public.purchase_accounting_mappings where organization_id = p_org_id;
  end if;
  if v_id is null then
    select id into v_id from public.accounts
    where organization_id = p_org_id and system_role = 'payables' and is_postable and is_active
    limit 1;
  end if;
  if v_id is null then raise exception 'Falta cuenta contable de proveedores'; end if;
  return v_id;
end;
$$;
create or replace function public.resolve_ar_account(p_org_id uuid)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare v_id uuid;
begin
  select accounts_receivable_account_id into v_id
  from public.treasury_accounting_mappings where organization_id = p_org_id;
  if v_id is null then
    select receivables_account_id into v_id
    from public.fiscal_accounting_mappings where organization_id = p_org_id;
  end if;
  if v_id is null then
    select id into v_id from public.accounts
    where organization_id = p_org_id and system_role = 'receivables' and is_postable and is_active
    limit 1;
  end if;
  if v_id is null then raise exception 'Falta cuenta contable de clientes'; end if;
  return v_id;
end;
$$;
create or replace function public.resolve_opening_equity_account(p_org_id uuid)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare v_id uuid;
begin
  select opening_equity_account_id into v_id
  from public.treasury_accounting_mappings where organization_id = p_org_id;
  if v_id is null then
    select id into v_id from public.accounts
    where organization_id = p_org_id and system_role = 'capital' and is_postable and is_active
    limit 1;
  end if;
  if v_id is null then raise exception 'Falta cuenta de patrimonio para saldo inicial'; end if;
  return v_id;
end;
$$;
create or replace function public.resolve_adjustment_offset_account(p_org_id uuid)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare v_id uuid;
begin
  select adjustment_offset_account_id into v_id
  from public.treasury_accounting_mappings where organization_id = p_org_id;
  if v_id is null then
    raise exception 'Falta configurar la cuenta contrapartida de ajustes de tesorería';
  end if;
  return v_id;
end;
$$;
create or replace function public.post_open_item_compensation(
  p_domain public.open_item_domain,
  p_increase_item_id uuid,
  p_decrease_item_id uuid,
  p_amount numeric,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_org uuid;
  v_existing uuid;
  v_inc_open numeric(19,4);
  v_dec_open numeric(19,4);
  v_inc_dir text;
  v_dec_dir text;
  v_inc_cp uuid;
  v_dec_cp uuid;
  v_inc_status text;
  v_dec_status text;
  v_id uuid;
  v_ids uuid[];
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'amount must be positive'; end if;
  if p_increase_item_id = p_decrease_item_id then raise exception 'items must differ'; end if;

  -- Lock in stable order
  v_ids := array(
    select x from unnest(array[p_increase_item_id, p_decrease_item_id]) as x order by 1
  );

  if p_domain = 'AP' then
    select organization_id into v_org from public.accounts_payable_items where id = p_increase_item_id;
  else
    select organization_id into v_org from public.accounts_receivable_items where id = p_increase_item_id;
  end if;
  if v_org is null then raise exception 'increase item not found'; end if;

  if not public.has_org_role(
    v_org, array['owner','admin','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role for compensation';
  end if;

  select id into v_existing
  from public.open_item_compensations
  where organization_id = v_org and idempotency_key = p_idempotency_key;
  if v_existing is not null then return v_existing; end if;

  perform set_config('treasury.engine_write', '1', true);

  if p_domain = 'AP' then
    perform 1 from public.accounts_payable_items where id = any(v_ids) order by id for update;
    select open_amount, direction::text, supplier_id, status::text
      into v_inc_open, v_inc_dir, v_inc_cp, v_inc_status
    from public.accounts_payable_items where id = p_increase_item_id;
    select open_amount, direction::text, supplier_id, status::text
      into v_dec_open, v_dec_dir, v_dec_cp, v_dec_status
    from public.accounts_payable_items where id = p_decrease_item_id;
    if v_inc_dir is distinct from 'AP_INCREASE' or v_dec_dir is distinct from 'AP_DECREASE' then
      raise exception 'AP compensation requires INCREASE and DECREASE items';
    end if;
    if v_inc_cp is distinct from v_dec_cp then raise exception 'AP compensation requires same supplier'; end if;
    if p_amount > v_inc_open or p_amount > v_dec_open then
      raise exception 'compensation exceeds open amounts';
    end if;
    update public.accounts_payable_items
    set open_amount = open_amount - p_amount,
        status = case
          when open_amount - p_amount = 0 then 'PAID'::public.accounts_payable_status
          else 'PARTIALLY_PAID'::public.accounts_payable_status
        end,
        updated_at = timezone('utc', now())
    where id = p_increase_item_id;
    update public.accounts_payable_items
    set open_amount = open_amount - p_amount,
        status = case
          when open_amount - p_amount = 0 then 'PAID'::public.accounts_payable_status
          else 'PARTIALLY_PAID'::public.accounts_payable_status
        end,
        updated_at = timezone('utc', now())
    where id = p_decrease_item_id;
  else
    perform 1 from public.accounts_receivable_items where id = any(v_ids) order by id for update;
    select open_amount, direction::text, customer_id, status::text
      into v_inc_open, v_inc_dir, v_inc_cp, v_inc_status
    from public.accounts_receivable_items where id = p_increase_item_id;
    select open_amount, direction::text, customer_id, status::text
      into v_dec_open, v_dec_dir, v_dec_cp, v_dec_status
    from public.accounts_receivable_items where id = p_decrease_item_id;
    if v_inc_dir is distinct from 'AR_INCREASE' or v_dec_dir is distinct from 'AR_DECREASE' then
      raise exception 'AR compensation requires INCREASE and DECREASE items';
    end if;
    if v_inc_cp is distinct from v_dec_cp then raise exception 'AR compensation requires same customer'; end if;
    if p_amount > v_inc_open or p_amount > v_dec_open then
      raise exception 'compensation exceeds open amounts';
    end if;
    update public.accounts_receivable_items
    set open_amount = open_amount - p_amount,
        status = case
          when open_amount - p_amount = 0 then 'COLLECTED'::public.accounts_receivable_status
          else 'PARTIALLY_COLLECTED'::public.accounts_receivable_status
        end,
        updated_at = timezone('utc', now())
    where id = p_increase_item_id;
    update public.accounts_receivable_items
    set open_amount = open_amount - p_amount,
        status = case
          when open_amount - p_amount = 0 then 'COLLECTED'::public.accounts_receivable_status
          else 'PARTIALLY_COLLECTED'::public.accounts_receivable_status
        end,
        updated_at = timezone('utc', now())
    where id = p_decrease_item_id;
  end if;

  insert into public.open_item_compensations (
    organization_id, domain, increase_item_id, decrease_item_id, amount,
    status, idempotency_key, created_by
  ) values (
    v_org, p_domain, p_increase_item_id, p_decrease_item_id, p_amount,
    'POSTED', p_idempotency_key, v_uid
  )
  returning id into v_id;

  return v_id;
end;
$$;
