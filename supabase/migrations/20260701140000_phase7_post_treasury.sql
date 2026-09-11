-- Phase 7 — post_treasury_operation + reverse_treasury_operation

create or replace function public.post_treasury_operation(p_operation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_op public.treasury_operations%rowtype;
  v_period_id uuid;
  v_entry_id uuid;
  v_existing uuid;
  v_leg record;
  v_leg_count int;
  v_inflow numeric(19,4);
  v_outflow numeric(19,4);
  v_src_acct uuid;
  v_dst_acct uuid;
  v_src_coa uuid;
  v_dst_coa uuid;
  v_ap_coa uuid;
  v_ar_coa uuid;
  v_eq_coa uuid;
  v_adj_coa uuid;
  v_alloc record;
  v_alloc_sum numeric(19,4);
  v_open numeric(19,4);
  v_source public.journal_source_type;
  v_desc text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select * into v_op from public.treasury_operations where id = p_operation_id for update;
  if not found then raise exception 'treasury operation not found'; end if;

  -- Tenant from protected row
  perform public.treasury_assert_feature(v_op.organization_id, array['cash','banks']);

  if v_op.status = 'POSTED' and v_op.journal_entry_id is not null then
    return p_operation_id;
  end if;
  if v_op.status is distinct from 'DRAFT' then
    raise exception 'only DRAFT operations can be posted';
  end if;
  if v_op.currency_code is distinct from 'ARS' then
    raise exception 'unsupported currency for Phase 7: %', v_op.currency_code;
  end if;

  -- Permissions by type
  if v_op.operation_type = 'ADJUSTMENT' then
    if not public.has_org_role(
      v_op.organization_id, array['owner','accountant']::public.member_role[]
    ) then
      raise exception 'only owner/accountant may post adjustments';
    end if;
    if v_op.reason is null or char_length(trim(v_op.reason)) < 3 then
      raise exception 'adjustment reason is required';
    end if;
  elsif v_op.operation_type in ('PAYMENT', 'COLLECTION', 'TRANSFER', 'OPENING_BALANCE') then
    if not public.has_org_role(
      v_op.organization_id,
      array['owner','admin','accountant']::public.member_role[]
    ) then
      raise exception 'insufficient role to post treasury operation';
    end if;
  end if;

  -- Idempotent journal reuse
  select id into v_existing
  from public.journal_entries
  where organization_id = v_op.organization_id
    and source_id = p_operation_id
    and status = 'POSTED'
    and source_type in ('PAYMENT','COLLECTION','BANK','SYSTEM')
  limit 1;
  if v_existing is not null then
    perform set_config('treasury.engine_write', '1', true);
    update public.treasury_operations
    set status = 'POSTED', journal_entry_id = v_existing, accounting_status = 'POSTED',
        posted_by = coalesce(posted_by, v_uid),
        posted_at = coalesce(posted_at, timezone('utc', now()))
    where id = p_operation_id;
    return p_operation_id;
  end if;

  select period_id into v_period_id
  from public.resolve_open_period(v_op.organization_id, v_op.operation_date);
  if v_period_id is null then
    perform set_config('treasury.engine_write', '1', true);
    update public.treasury_operations
    set accounting_status = 'ACCOUNTING_REQUIRES_REVIEW', updated_at = timezone('utc', now())
    where id = p_operation_id;
    return p_operation_id;
  end if;

  select count(*)::int,
         coalesce(sum(case when direction='INFLOW' then amount else 0 end),0),
         coalesce(sum(case when direction='OUTFLOW' then amount else 0 end),0)
  into v_leg_count, v_inflow, v_outflow
  from public.treasury_operation_legs
  where treasury_operation_id = p_operation_id;

  -- Validate legs by type
  if v_op.operation_type = 'PAYMENT' then
    if v_leg_count <> 1 or v_outflow <> v_op.amount or v_inflow <> 0 then
      raise exception 'PAYMENT requires exactly one OUTFLOW equal to amount';
    end if;
  elsif v_op.operation_type = 'COLLECTION' then
    if v_leg_count <> 1 or v_inflow <> v_op.amount or v_outflow <> 0 then
      raise exception 'COLLECTION requires exactly one INFLOW equal to amount';
    end if;
  elsif v_op.operation_type = 'TRANSFER' then
    if v_leg_count <> 2 or v_inflow <> v_op.amount or v_outflow <> v_op.amount then
      raise exception 'TRANSFER requires equal INFLOW and OUTFLOW';
    end if;
    select treasury_account_id into v_src_acct from public.treasury_operation_legs
    where treasury_operation_id = p_operation_id and direction = 'OUTFLOW';
    select treasury_account_id into v_dst_acct from public.treasury_operation_legs
    where treasury_operation_id = p_operation_id and direction = 'INFLOW';
    if v_src_acct is not distinct from v_dst_acct then
      raise exception 'TRANSFER source and destination must differ';
    end if;
  elsif v_op.operation_type = 'OPENING_BALANCE' then
    if v_leg_count <> 1 or (v_inflow + v_outflow) <> v_op.amount then
      raise exception 'OPENING_BALANCE requires exactly one leg equal to amount';
    end if;
    -- One opening per account
    if exists (
      select 1
      from public.treasury_operation_legs l
      join public.treasury_operations o on o.id = l.treasury_operation_id
      where l.treasury_account_id = (
        select treasury_account_id from public.treasury_operation_legs
        where treasury_operation_id = p_operation_id limit 1
      )
        and o.operation_type = 'OPENING_BALANCE'
        and o.status = 'POSTED'
        and o.id <> p_operation_id
    ) then
      raise exception 'treasury account already has a POSTED opening balance';
    end if;
  elsif v_op.operation_type = 'ADJUSTMENT' then
    if v_leg_count <> 1 or (v_inflow + v_outflow) <> v_op.amount then
      raise exception 'ADJUSTMENT requires exactly one leg equal to amount';
    end if;
  end if;

  -- Active accounts
  for v_leg in
    select l.*, ta.accounting_account_id, ta.is_active, ta.currency_code as tac
    from public.treasury_operation_legs l
    join public.treasury_accounts ta on ta.id = l.treasury_account_id
    where l.treasury_operation_id = p_operation_id
  loop
    if not v_leg.is_active then raise exception 'treasury account inactive'; end if;
    if v_leg.tac is distinct from 'ARS' then raise exception 'treasury account currency must be ARS'; end if;
  end loop;

  -- PAYMENT allocations + AP locks (stable id order)
  if v_op.operation_type = 'PAYMENT' then
    select coalesce(sum(allocated_amount),0) into v_alloc_sum
    from public.payment_allocations where treasury_operation_id = p_operation_id;
    if v_alloc_sum <> v_op.amount then
      raise exception 'payment allocations must equal payment amount';
    end if;

    perform 1 from public.accounts_payable_items ap
    where ap.id in (
      select accounts_payable_item_id from public.payment_allocations
      where treasury_operation_id = p_operation_id
    )
    order by ap.id
    for update;

    for v_alloc in
      select pa.*, ap.open_amount as ap_open, ap.direction as ap_dir, ap.supplier_id as ap_supplier
      from public.payment_allocations pa
      join public.accounts_payable_items ap on ap.id = pa.accounts_payable_item_id
      where pa.treasury_operation_id = p_operation_id
      order by pa.accounts_payable_item_id
    loop
      if v_alloc.ap_dir is distinct from 'AP_INCREASE' then
        raise exception 'payments may only allocate to AP_INCREASE items';
      end if;
      if v_alloc.ap_supplier is distinct from v_op.counterparty_id then
        raise exception 'AP allocation supplier mismatch';
      end if;
      if v_alloc.allocated_amount > v_alloc.ap_open then
        raise exception 'allocation exceeds AP open amount (concurrency)';
      end if;
    end loop;
  end if;

  if v_op.operation_type = 'COLLECTION' then
    select coalesce(sum(allocated_amount),0) into v_alloc_sum
    from public.collection_allocations where treasury_operation_id = p_operation_id;
    if v_alloc_sum <> v_op.amount then
      raise exception 'collection allocations must equal collection amount';
    end if;

    perform 1 from public.accounts_receivable_items ar
    where ar.id in (
      select accounts_receivable_item_id from public.collection_allocations
      where treasury_operation_id = p_operation_id
    )
    order by ar.id
    for update;

    for v_alloc in
      select ca.*, ar.open_amount as ar_open, ar.direction as ar_dir, ar.customer_id as ar_customer
      from public.collection_allocations ca
      join public.accounts_receivable_items ar on ar.id = ca.accounts_receivable_item_id
      where ca.treasury_operation_id = p_operation_id
      order by ca.accounts_receivable_item_id
    loop
      if v_alloc.ar_dir is distinct from 'AR_INCREASE' then
        raise exception 'collections may only allocate to AR_INCREASE items';
      end if;
      if v_alloc.ar_customer is distinct from v_op.counterparty_id then
        raise exception 'AR allocation customer mismatch';
      end if;
      if v_alloc.allocated_amount > v_alloc.ar_open then
        raise exception 'allocation exceeds AR open amount (concurrency)';
      end if;
    end loop;
  end if;

  -- Build journal
  v_source := case v_op.operation_type
    when 'PAYMENT' then 'PAYMENT'::public.journal_source_type
    when 'COLLECTION' then 'COLLECTION'::public.journal_source_type
    when 'TRANSFER' then 'BANK'::public.journal_source_type
    when 'OPENING_BALANCE' then 'SYSTEM'::public.journal_source_type
    when 'ADJUSTMENT' then 'SYSTEM'::public.journal_source_type
  end;
  v_desc := left(v_op.operation_type::text || ' ' || v_op.internal_number || ' ' || v_op.description, 500);

  insert into public.journal_entries (
    organization_id, entry_date, description, status, source_type, source_id, created_by
  ) values (
    v_op.organization_id, v_op.operation_date, v_desc, 'DRAFT', v_source, p_operation_id, v_uid
  ) returning id into v_entry_id;

  begin
    if v_op.operation_type = 'PAYMENT' then
      v_ap_coa := public.resolve_ap_account(v_op.organization_id);
      select ta.accounting_account_id into v_src_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = 'OUTFLOW';
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit, counterparty_id
      ) values
        (v_op.organization_id, v_entry_id, 1, v_ap_coa, 'Pago proveedores', v_op.amount, 0, v_op.counterparty_id),
        (v_op.organization_id, v_entry_id, 2, v_src_coa, 'Egreso tesorería', 0, v_op.amount, v_op.counterparty_id);

    elsif v_op.operation_type = 'COLLECTION' then
      v_ar_coa := public.resolve_ar_account(v_op.organization_id);
      select ta.accounting_account_id into v_dst_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = 'INFLOW';
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit, counterparty_id
      ) values
        (v_op.organization_id, v_entry_id, 1, v_dst_coa, 'Ingreso tesorería', v_op.amount, 0, v_op.counterparty_id),
        (v_op.organization_id, v_entry_id, 2, v_ar_coa, 'Cobro clientes', 0, v_op.amount, v_op.counterparty_id);

    elsif v_op.operation_type = 'TRANSFER' then
      select ta.accounting_account_id into v_src_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = 'OUTFLOW';
      select ta.accounting_account_id into v_dst_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = 'INFLOW';
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit
      ) values
        (v_op.organization_id, v_entry_id, 1, v_dst_coa, 'Transferencia destino', v_op.amount, 0),
        (v_op.organization_id, v_entry_id, 2, v_src_coa, 'Transferencia origen', 0, v_op.amount);

    elsif v_op.operation_type = 'OPENING_BALANCE' then
      v_eq_coa := public.resolve_opening_equity_account(v_op.organization_id);
      select ta.accounting_account_id, l.direction into v_src_coa, v_desc
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id;
      if v_desc = 'INFLOW' then
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_src_coa, 'Saldo inicial tesorería', v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_eq_coa, 'Contrapartida saldo inicial', 0, v_op.amount);
      else
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_eq_coa, 'Contrapartida saldo inicial', v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_src_coa, 'Saldo inicial tesorería', 0, v_op.amount);
      end if;

    elsif v_op.operation_type = 'ADJUSTMENT' then
      v_adj_coa := public.resolve_adjustment_offset_account(v_op.organization_id);
      select ta.accounting_account_id, l.direction into v_src_coa, v_desc
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id;
      if v_desc = 'INFLOW' then
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_src_coa, 'Ajuste tesorería', v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_adj_coa, coalesce(v_op.reason,'Ajuste'), 0, v_op.amount);
      else
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_adj_coa, coalesce(v_op.reason,'Ajuste'), v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_src_coa, 'Ajuste tesorería', 0, v_op.amount);
      end if;
    end if;

    perform public.post_journal_entry(v_entry_id);
  exception when others then
    delete from public.journal_entries where id = v_entry_id and status = 'DRAFT';
    raise;
  end;

  perform set_config('treasury.engine_write', '1', true);

  -- Apply AP allocations
  if v_op.operation_type = 'PAYMENT' then
    for v_alloc in
      select * from public.payment_allocations
      where treasury_operation_id = p_operation_id
      order by accounts_payable_item_id
    loop
      update public.accounts_payable_items
      set open_amount = open_amount - v_alloc.allocated_amount,
          status = case
            when open_amount - v_alloc.allocated_amount = 0 then 'PAID'::public.accounts_payable_status
            else 'PARTIALLY_PAID'::public.accounts_payable_status
          end,
          updated_at = timezone('utc', now())
      where id = v_alloc.accounts_payable_item_id
        and open_amount >= v_alloc.allocated_amount;
      if not found then
        raise exception 'AP concurrent update failed';
      end if;
    end loop;
  end if;

  if v_op.operation_type = 'COLLECTION' then
    for v_alloc in
      select * from public.collection_allocations
      where treasury_operation_id = p_operation_id
      order by accounts_receivable_item_id
    loop
      update public.accounts_receivable_items
      set open_amount = open_amount - v_alloc.allocated_amount,
          status = case
            when open_amount - v_alloc.allocated_amount = 0 then 'COLLECTED'::public.accounts_receivable_status
            else 'PARTIALLY_COLLECTED'::public.accounts_receivable_status
          end,
          updated_at = timezone('utc', now())
      where id = v_alloc.accounts_receivable_item_id
        and open_amount >= v_alloc.allocated_amount;
      if not found then
        raise exception 'AR concurrent update failed';
      end if;
    end loop;
  end if;

  update public.treasury_operations
  set status = 'POSTED',
      accounting_status = 'POSTED',
      journal_entry_id = v_entry_id,
      posted_by = v_uid,
      posted_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where id = p_operation_id;

  return p_operation_id;
end;
$$;
