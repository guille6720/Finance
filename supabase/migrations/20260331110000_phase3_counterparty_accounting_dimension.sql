-- Phase 3 — Counterparty accounting dimension + reversal (STAGING)

-- ---------------------------------------------------------------------------
-- journal_entry_lines.counterparty_id
-- ---------------------------------------------------------------------------

alter table public.journal_entry_lines
  add column if not exists counterparty_id uuid;
create index if not exists journal_entry_lines_counterparty_idx
  on public.journal_entry_lines (counterparty_id)
  where counterparty_id is not null;
create index if not exists journal_entry_lines_org_counterparty_idx
  on public.journal_entry_lines (organization_id, counterparty_id)
  where counterparty_id is not null;
alter table public.journal_entry_lines
  drop constraint if exists journal_entry_lines_counterparty_tenant_fk;
alter table public.journal_entry_lines
  add constraint journal_entry_lines_counterparty_tenant_fk
  foreign key (organization_id, counterparty_id)
  references public.counterparties (organization_id, id)
  on delete restrict;
-- ---------------------------------------------------------------------------
-- Extend line tenancy validation
-- ---------------------------------------------------------------------------

create or replace function public.validate_journal_line_tenancy()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  entry_org uuid;
  entry_status public.journal_entry_status;
  acct_org uuid;
  acct_active boolean;
  acct_postable boolean;
  cc_org uuid;
  cc_active boolean;
  cp_org uuid;
  cp_active boolean;
begin
  select organization_id, status into entry_org, entry_status
  from public.journal_entries where id = new.journal_entry_id;

  if entry_org is null then
    raise exception 'journal entry not found';
  end if;
  if entry_status <> 'DRAFT' then
    raise exception 'cannot modify lines of a non-draft journal entry';
  end if;
  if new.organization_id <> entry_org then
    raise exception 'line organization must match journal entry';
  end if;

  select organization_id, is_active, is_postable
    into acct_org, acct_active, acct_postable
  from public.accounts where id = new.account_id;

  if acct_org is null then
    raise exception 'account not found';
  end if;
  if acct_org <> new.organization_id then
    raise exception 'account must belong to same organization';
  end if;
  if not acct_active then
    if current_setting('accounting.engine_write', true) is distinct from '1' then
      raise exception 'inactive accounts cannot receive journal lines';
    end if;
  end if;
  if not acct_postable then
    if current_setting('accounting.engine_write', true) is distinct from '1' then
      raise exception 'non-postable accounts cannot receive journal lines';
    end if;
  end if;

  if new.cost_center_id is not null then
    select organization_id, active into cc_org, cc_active
    from public.cost_centers where id = new.cost_center_id;
    if cc_org is null then
      raise exception 'cost center not found';
    end if;
    if cc_org <> new.organization_id then
      raise exception 'cost center must belong to same organization';
    end if;
    if not cc_active then
      raise exception 'inactive cost centers cannot receive journal lines';
    end if;
  end if;

  if new.counterparty_id is not null then
    select organization_id, is_active into cp_org, cp_active
    from public.counterparties where id = new.counterparty_id;
    if cp_org is null then
      raise exception 'counterparty not found';
    end if;
    if cp_org <> new.organization_id then
      raise exception 'counterparty must belong to same organization';
    end if;
    if not cp_active then
      if current_setting('accounting.engine_write', true) is distinct from '1' then
        raise exception 'inactive counterparties cannot receive journal lines';
      end if;
    end if;
  end if;

  return new;
end;
$$;
-- ---------------------------------------------------------------------------
-- Counterparty delete guard (now that journal lines can reference)
-- ---------------------------------------------------------------------------

create or replace function public.prevent_counterparty_delete_with_movements()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.journal_entry_lines
    where counterparty_id = old.id
  ) then
    raise exception 'counterparty with journal references cannot be deleted; deactivate instead';
  end if;
  return old;
end;
$$;
drop trigger if exists counterparties_prevent_delete_movements on public.counterparties;
create trigger counterparties_prevent_delete_movements
before delete on public.counterparties
for each row execute function public.prevent_counterparty_delete_with_movements();
-- ---------------------------------------------------------------------------
-- Reversal engine — preserve counterparty_id
-- ---------------------------------------------------------------------------

create or replace function public.reverse_journal_entry(
  p_entry_id uuid,
  p_reason text
)
returns public.journal_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_orig public.journal_entries;
  v_rev public.journal_entries;
  v_uid uuid;
  v_fy_id uuid;
  v_number bigint;
  r record;
  v_line_count int;
  v_debit numeric(18, 2);
  v_credit numeric(18, 2);
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  select * into v_orig
  from public.journal_entries
  where id = p_entry_id
  for update;

  if v_orig.id is null then
    raise exception 'journal entry not found';
  end if;

  if not public.has_org_role(
    v_orig.organization_id,
    array['owner','admin','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role to reverse journal entries';
  end if;

  if v_orig.status <> 'POSTED' then
    raise exception 'only posted entries can be reversed';
  end if;

  if v_orig.reversed_by_entry_id is not null then
    raise exception 'entry already reversed';
  end if;

  if trim(coalesce(p_reason, '')) = '' then
    raise exception 'reversal reason is required';
  end if;

  v_fy_id := v_orig.fiscal_year_id;

  perform set_config('accounting.engine_write', '1', true);

  insert into public.journal_entries (
    organization_id,
    fiscal_year_id,
    period_id,
    entry_date,
    description,
    status,
    source,
    external_reference,
    reverses_entry_id,
    reversal_reason,
    created_by
  ) values (
    v_orig.organization_id,
    v_orig.fiscal_year_id,
    v_orig.period_id,
    v_orig.entry_date,
    'Reversión: ' || coalesce(v_orig.description, v_orig.entry_number::text),
    'DRAFT',
    'REVERSAL',
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
revoke all on function public.reverse_journal_entry(uuid, text) from public;
grant execute on function public.reverse_journal_entry(uuid, text) to authenticated;
