-- Phase 7 — reverse_treasury_operation + grants for posting RPCs

create or replace function public.reverse_treasury_operation(
  p_operation_id uuid,
  p_reversal_date date default current_date,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_op public.treasury_operations%rowtype;
  v_rev public.journal_entries%rowtype;
  v_alloc record;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'reversal reason is required';
  end if;

  select * into v_op from public.treasury_operations where id = p_operation_id for update;
  if not found then raise exception 'treasury operation not found'; end if;

  perform public.treasury_assert_feature(v_op.organization_id, array['cash','banks']);

  if v_op.operation_type = 'ADJUSTMENT' then
    if not public.has_org_role(
      v_op.organization_id, array['owner','accountant']::public.member_role[]
    ) then
      raise exception 'only owner/accountant may reverse adjustments';
    end if;
  else
    if not public.has_org_role(
      v_op.organization_id, array['owner','admin','accountant']::public.member_role[]
    ) then
      raise exception 'insufficient role to reverse treasury operation';
    end if;
  end if;

  if v_op.status = 'REVERSED' then
    return p_operation_id;
  end if;
  if v_op.status is distinct from 'POSTED' or v_op.journal_entry_id is null then
    raise exception 'only POSTED operations with journal can be reversed';
  end if;

  -- Lock open items before restore
  if v_op.operation_type = 'PAYMENT' then
    perform 1 from public.accounts_payable_items ap
    where ap.id in (
      select accounts_payable_item_id from public.payment_allocations
      where treasury_operation_id = p_operation_id
    )
    order by ap.id for update;
  elsif v_op.operation_type = 'COLLECTION' then
    perform 1 from public.accounts_receivable_items ar
    where ar.id in (
      select accounts_receivable_item_id from public.collection_allocations
      where treasury_operation_id = p_operation_id
    )
    order by ar.id for update;
  end if;

  select * into v_rev from public.reverse_journal_entry(
    v_op.journal_entry_id, p_reversal_date, trim(p_reason)
  );

  perform set_config('treasury.engine_write', '1', true);

  if v_op.operation_type = 'PAYMENT' then
    for v_alloc in
      select * from public.payment_allocations
      where treasury_operation_id = p_operation_id
      order by accounts_payable_item_id
    loop
      update public.accounts_payable_items
      set open_amount = open_amount + v_alloc.allocated_amount,
          status = case
            when open_amount + v_alloc.allocated_amount >= original_amount
              then 'OPEN'::public.accounts_payable_status
            else 'PARTIALLY_PAID'::public.accounts_payable_status
          end,
          updated_at = timezone('utc', now())
      where id = v_alloc.accounts_payable_item_id;
    end loop;
  elsif v_op.operation_type = 'COLLECTION' then
    for v_alloc in
      select * from public.collection_allocations
      where treasury_operation_id = p_operation_id
      order by accounts_receivable_item_id
    loop
      update public.accounts_receivable_items
      set open_amount = open_amount + v_alloc.allocated_amount,
          status = case
            when open_amount + v_alloc.allocated_amount >= original_amount
              then 'OPEN'::public.accounts_receivable_status
            else 'PARTIALLY_COLLECTED'::public.accounts_receivable_status
          end,
          updated_at = timezone('utc', now())
      where id = v_alloc.accounts_receivable_item_id;
    end loop;
  end if;

  -- Domain status REVERSED; original journal stays REVERSED in Phase 2 with reversal pair
  update public.treasury_operations
  set status = 'REVERSED',
      reverse_journal_entry_id = v_rev.id,
      reversed_by = v_uid,
      reversed_at = timezone('utc', now()),
      reason = coalesce(reason, trim(p_reason)),
      updated_at = timezone('utc', now())
  where id = p_operation_id;

  return p_operation_id;
end;
$$;
revoke all on function public.treasury_assert_feature(uuid, text[]) from public, anon;
revoke all on function public.next_treasury_operation_number(uuid, public.treasury_operation_type) from public, anon;
revoke all on function public.post_treasury_operation(uuid) from public, anon;
revoke all on function public.reverse_treasury_operation(uuid, date, text) from public, anon;
revoke all on function public.post_open_item_compensation(public.open_item_domain, uuid, uuid, numeric, text) from public, anon;
revoke all on function public.resolve_ap_account(uuid) from public, anon;
revoke all on function public.resolve_ar_account(uuid) from public, anon;
revoke all on function public.resolve_opening_equity_account(uuid) from public, anon;
revoke all on function public.resolve_adjustment_offset_account(uuid) from public, anon;
grant execute on function public.next_treasury_operation_number(uuid, public.treasury_operation_type) to authenticated;
grant execute on function public.post_treasury_operation(uuid) to authenticated;
grant execute on function public.reverse_treasury_operation(uuid, date, text) to authenticated;
grant execute on function public.post_open_item_compensation(public.open_item_domain, uuid, uuid, numeric, text) to authenticated;
grant execute on function public.resolve_ap_account(uuid) to authenticated;
grant execute on function public.resolve_ar_account(uuid) to authenticated;
grant execute on function public.resolve_opening_equity_account(uuid) to authenticated;
grant execute on function public.resolve_adjustment_offset_account(uuid) to authenticated;
