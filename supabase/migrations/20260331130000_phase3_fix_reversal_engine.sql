-- Phase 3 fix — restore reverse_journal_entry signature + counterparty_id copy

create or replace function public.reverse_journal_entry(
  p_original_entry_id uuid,
  p_reversal_date date,
  p_reason text
)
returns public.journal_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_orig public.journal_entries;
  v_rev public.journal_entries;
  v_period_id uuid;
  v_fy_id uuid;
  v_number text;
  v_debit numeric(19,4);
  v_credit numeric(19,4);
  v_line_count int;
  r record;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'reversal reason is required';
  end if;

  select * into v_orig
  from public.journal_entries
  where id = p_original_entry_id
  for update;

  if not found then
    raise exception 'journal entry not found';
  end if;

  if not public.is_org_member(v_orig.organization_id) then
    raise exception 'not a member of organization';
  end if;

  if not public.has_org_role(
    v_orig.organization_id,
    array['owner','admin','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role to reverse journal entries';
  end if;

  if v_orig.status <> 'POSTED' then
    raise exception 'only POSTED entries can be reversed';
  end if;

  if v_orig.reversed_by_entry_id is not null then
    raise exception 'entry already reversed';
  end if;

  select period_id, fiscal_year_id into v_period_id, v_fy_id
  from public.resolve_open_period(v_orig.organization_id, p_reversal_date);

  if v_period_id is null then
    raise exception 'no OPEN period (and OPEN fiscal year) covers reversal_date';
  end if;

  perform set_config('accounting.engine_write', '1', true);

  insert into public.journal_entries (
    organization_id,
    fiscal_year_id,
    period_id,
    entry_date,
    description,
    status,
    source_type,
    source_id,
    external_reference,
    reversal_of_entry_id,
    reversal_reason,
    created_by
  ) values (
    v_orig.organization_id,
    v_fy_id,
    v_period_id,
    p_reversal_date,
    'Reversión de asiento ' || coalesce(v_orig.entry_number, v_orig.id::text) || ': ' || v_orig.description,
    'DRAFT',
    'SYSTEM',
    v_orig.id,
    v_orig.external_reference,
    v_orig.id,
    trim(p_reason),
    v_uid
  )
  returning * into v_rev;

  for r in
    select * from public.journal_entry_lines
    where journal_entry_id = v_orig.id
    order by line_number
  loop
    insert into public.journal_entry_lines (
      journal_entry_id,
      organization_id,
      account_id,
      cost_center_id,
      counterparty_id,
      description,
      debit,
      credit,
      line_number,
      metadata
    ) values (
      v_rev.id,
      r.organization_id,
      r.account_id,
      r.cost_center_id,
      r.counterparty_id,
      coalesce(r.description, 'Reversión'),
      r.credit,
      r.debit,
      r.line_number,
      coalesce(r.metadata, '{}'::jsonb) || jsonb_build_object('reversed_from_line_id', r.id)
    );
  end loop;

  select count(*)::int, coalesce(sum(debit), 0), coalesce(sum(credit), 0)
  into v_line_count, v_debit, v_credit
  from public.journal_entry_lines
  where journal_entry_id = v_rev.id;

  if v_line_count < 2 or v_debit <> v_credit or v_debit <= 0 then
    raise exception 'reversal entry failed balance validation';
  end if;

  v_number := public.next_journal_entry_number(v_orig.organization_id, v_fy_id);

  update public.journal_entries
  set
    status = 'POSTED',
    entry_number = v_number,
    posted_by = v_uid,
    posted_at = timezone('utc', now())
  where id = v_rev.id
  returning * into v_rev;

  update public.journal_entries
  set
    status = 'REVERSED',
    reversed_by_entry_id = v_rev.id
  where id = v_orig.id;

  perform set_config('accounting.engine_write', '0', true);

  perform public.accounting_write_audit(
    v_orig.organization_id,
    v_uid,
    'journal.reversed',
    'journal_entry',
    v_orig.id::text,
    'reverse',
    jsonb_build_object(
      'original_entry_number', v_orig.entry_number,
      'reversal_entry_id', v_rev.id,
      'reversal_entry_number', v_rev.entry_number,
      'reason', trim(p_reason)
    )
  );

  return v_rev;
end;
$$;
revoke all on function public.reverse_journal_entry(uuid, date, text) from public;
grant execute on function public.reverse_journal_entry(uuid, date, text) to authenticated;
