-- Phase 2 — Accounting core (STAGING)
-- Project: rpcpdrzbcclofvjpgldb
-- Additive only — does not rewrite Phase 1 migrations.
-- Money: numeric(19,4) only. Never float/double.

create extension if not exists btree_gist;
-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.account_type as enum (
    'ASSET', 'LIABILITY', 'EQUITY', 'REVENUE', 'EXPENSE', 'MEMORANDUM'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.normal_balance as enum ('DEBIT', 'CREDIT');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.fiscal_year_status as enum ('OPEN', 'CLOSED');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.period_status as enum ('OPEN', 'CLOSED');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.journal_entry_status as enum ('DRAFT', 'POSTED', 'REVERSED');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.journal_source_type as enum (
    'MANUAL', 'SALE', 'PURCHASE', 'PAYMENT', 'COLLECTION',
    'BANK', 'INVENTORY', 'PAYROLL', 'TAX', 'SYSTEM'
  );
exception when duplicate_object then null;
end $$;
-- ---------------------------------------------------------------------------
-- accounting_fiscal_years
-- ---------------------------------------------------------------------------

create table if not exists public.accounting_fiscal_years (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  start_date date not null,
  end_date date not null,
  status public.fiscal_year_status not null default 'OPEN',
  closed_at timestamptz,
  closed_by uuid references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint accounting_fiscal_years_range check (start_date < end_date),
  constraint accounting_fiscal_years_name_len check (char_length(name) between 1 and 120)
);
create unique index if not exists accounting_fiscal_years_org_name_uidx
  on public.accounting_fiscal_years (organization_id, name);
create index if not exists accounting_fiscal_years_org_idx
  on public.accounting_fiscal_years (organization_id);
create index if not exists accounting_fiscal_years_org_dates_idx
  on public.accounting_fiscal_years (organization_id, start_date, end_date);
-- Prevent overlapping fiscal years per organization
alter table public.accounting_fiscal_years
  drop constraint if exists accounting_fiscal_years_no_overlap;
alter table public.accounting_fiscal_years
  add constraint accounting_fiscal_years_no_overlap
  exclude using gist (
    organization_id with =,
    daterange(start_date, end_date, '[]') with &&
  );
create trigger accounting_fiscal_years_set_updated_at
before update on public.accounting_fiscal_years
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- Adapt accounting_periods
-- ---------------------------------------------------------------------------

alter table public.accounting_periods
  add column if not exists fiscal_year_id uuid references public.accounting_fiscal_years (id);
alter table public.accounting_periods
  add column if not exists status public.period_status;
alter table public.accounting_periods
  add column if not exists reopened_at timestamptz;
alter table public.accounting_periods
  add column if not exists reopened_by uuid references public.profiles (id);
alter table public.accounting_periods
  add column if not exists reopen_reason text;
-- Backfill: one fiscal year per existing period, then link (idempotent)
do $$
declare
  r record;
  fy_id uuid;
begin
  for r in
    select * from public.accounting_periods
    where fiscal_year_id is null
  loop
    insert into public.accounting_fiscal_years (
      organization_id, name, start_date, end_date, status
    ) values (
      r.organization_id,
      r.name,
      r.starts_on,
      r.ends_on,
      case when r.is_closed then 'CLOSED'::public.fiscal_year_status else 'OPEN'::public.fiscal_year_status end
    )
    returning id into fy_id;

    update public.accounting_periods
    set
      fiscal_year_id = fy_id,
      status = case when r.is_closed then 'CLOSED'::public.period_status else 'OPEN'::public.period_status end
    where id = r.id;
  end loop;

  update public.accounting_periods
  set status = case when is_closed then 'CLOSED'::public.period_status else 'OPEN'::public.period_status end
  where status is null;
end $$;
-- Only enforce NOT NULL if backfill completed
do $$
begin
  if exists (select 1 from public.accounting_periods where fiscal_year_id is null) then
    raise exception 'accounting_periods backfill incomplete';
  end if;
end $$;
alter table public.accounting_periods
  alter column fiscal_year_id set not null;
alter table public.accounting_periods
  alter column status set not null;
alter table public.accounting_periods
  alter column status set default 'OPEN';
create index if not exists accounting_periods_fy_idx
  on public.accounting_periods (fiscal_year_id);
create index if not exists accounting_periods_org_status_idx
  on public.accounting_periods (organization_id, status);
alter table public.accounting_periods
  drop constraint if exists accounting_periods_no_overlap;
alter table public.accounting_periods
  add constraint accounting_periods_no_overlap
  exclude using gist (
    organization_id with =,
    daterange(starts_on, ends_on, '[]') with &&
  );
-- Keep is_closed synchronized with status
create or replace function public.sync_period_closed_flag()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.is_closed := (new.status = 'CLOSED');
  if new.status = 'CLOSED' and old.status is distinct from 'CLOSED' then
    new.closed_at := coalesce(new.closed_at, timezone('utc', now()));
  end if;
  if new.status = 'OPEN' and old.status = 'CLOSED' then
    new.reopened_at := coalesce(new.reopened_at, timezone('utc', now()));
  end if;
  return new;
end;
$$;
drop trigger if exists accounting_periods_sync_closed on public.accounting_periods;
create trigger accounting_periods_sync_closed
before insert or update of status on public.accounting_periods
for each row execute function public.sync_period_closed_flag();
-- ---------------------------------------------------------------------------
-- accounts (chart of accounts)
-- ---------------------------------------------------------------------------

create table if not exists public.accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  parent_id uuid references public.accounts (id) on delete restrict,
  code text not null,
  name text not null,
  account_type public.account_type not null,
  normal_balance public.normal_balance not null,
  level int not null default 1 check (level between 1 and 10),
  is_postable boolean not null default true,
  is_active boolean not null default true,
  system_role text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint accounts_code_len check (char_length(code) between 1 and 32),
  constraint accounts_name_len check (char_length(name) between 1 and 200),
  unique (organization_id, code)
);
create index if not exists accounts_org_idx on public.accounts (organization_id);
create index if not exists accounts_org_parent_idx on public.accounts (organization_id, parent_id);
create index if not exists accounts_org_type_idx on public.accounts (organization_id, account_type);
create index if not exists accounts_org_active_idx on public.accounts (organization_id, is_active);
create trigger accounts_set_updated_at
before update on public.accounts
for each row execute function public.set_updated_at();
-- Parent same org + no cycles + level
create or replace function public.validate_account_hierarchy()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  walk uuid;
  hops int := 0;
  parent_org uuid;
  parent_level int;
begin
  if new.parent_id is null then
    new.level := 1;
    return new;
  end if;

  if new.parent_id = new.id then
    raise exception 'account cannot be its own parent';
  end if;

  select organization_id, level into parent_org, parent_level
  from public.accounts where id = new.parent_id;

  if parent_org is null then
    raise exception 'parent account not found';
  end if;
  if parent_org <> new.organization_id then
    raise exception 'parent account must belong to same organization';
  end if;

  new.level := parent_level + 1;

  walk := new.parent_id;
  while walk is not null loop
    hops := hops + 1;
    if hops > 20 then
      raise exception 'account hierarchy too deep or cyclic';
    end if;
    if walk = new.id then
      raise exception 'circular account hierarchy is not allowed';
    end if;
    select parent_id into walk from public.accounts where id = walk;
  end loop;

  return new;
end;
$$;
drop trigger if exists accounts_validate_hierarchy on public.accounts;
create trigger accounts_validate_hierarchy
before insert or update of parent_id, organization_id on public.accounts
for each row execute function public.validate_account_hierarchy();
-- Prevent hard-delete when account has posted lines
create or replace function public.prevent_account_delete_with_movements()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.journal_entry_lines jel
    join public.journal_entries je on je.id = jel.journal_entry_id
    where jel.account_id = old.id
      and je.status in ('POSTED', 'REVERSED')
  ) then
    raise exception 'cannot delete account with posted movements; deactivate instead';
  end if;
  return old;
end;
$$;
-- ---------------------------------------------------------------------------
-- accounting_sequences (concurrency-safe entry numbers per org + fiscal year)
-- ---------------------------------------------------------------------------

create table if not exists public.accounting_sequences (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  fiscal_year_id uuid not null references public.accounting_fiscal_years (id) on delete cascade,
  last_value bigint not null default 0 check (last_value >= 0),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (organization_id, fiscal_year_id)
);
-- ---------------------------------------------------------------------------
-- journal_entries
-- ---------------------------------------------------------------------------

create table if not exists public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  fiscal_year_id uuid references public.accounting_fiscal_years (id),
  period_id uuid references public.accounting_periods (id),
  entry_number text,
  entry_date date not null,
  description text not null,
  status public.journal_entry_status not null default 'DRAFT',
  source_type public.journal_source_type not null default 'MANUAL',
  source_id uuid,
  external_reference text,
  reversal_of_entry_id uuid references public.journal_entries (id),
  reversed_by_entry_id uuid references public.journal_entries (id),
  reversal_reason text,
  created_by uuid not null references public.profiles (id),
  posted_by uuid references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  posted_at timestamptz,
  constraint journal_entries_description_len check (char_length(description) between 1 and 500),
  constraint journal_entries_posted_shape check (
    (status = 'DRAFT' and entry_number is null and posted_at is null and posted_by is null)
    or (status in ('POSTED', 'REVERSED') and entry_number is not null and posted_at is not null and posted_by is not null)
  ),
  constraint journal_entries_reversal_reason check (
    reversal_of_entry_id is null or (reversal_reason is not null and char_length(reversal_reason) >= 3)
  )
);
create unique index if not exists journal_entries_org_fy_number_uidx
  on public.journal_entries (organization_id, fiscal_year_id, entry_number)
  where entry_number is not null;
create index if not exists journal_entries_org_date_idx
  on public.journal_entries (organization_id, entry_date);
create index if not exists journal_entries_org_status_idx
  on public.journal_entries (organization_id, status);
create index if not exists journal_entries_period_idx
  on public.journal_entries (period_id);
create index if not exists journal_entries_source_idx
  on public.journal_entries (organization_id, source_type, source_id);
create index if not exists journal_entries_reversal_of_idx
  on public.journal_entries (reversal_of_entry_id);
create trigger journal_entries_set_updated_at
before update on public.journal_entries
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- journal_entry_lines
-- ---------------------------------------------------------------------------

create table if not exists public.journal_entry_lines (
  id uuid primary key default gen_random_uuid(),
  journal_entry_id uuid not null references public.journal_entries (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete restrict,
  cost_center_id uuid references public.cost_centers (id) on delete restrict,
  description text,
  debit numeric(19, 4) not null default 0,
  credit numeric(19, 4) not null default 0,
  line_number int not null check (line_number > 0),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  constraint journal_entry_lines_debit_nonneg check (debit >= 0),
  constraint journal_entry_lines_credit_nonneg check (credit >= 0),
  constraint journal_entry_lines_one_side check (
    (debit > 0 and credit = 0) or (credit > 0 and debit = 0)
  ),
  unique (journal_entry_id, line_number)
);
create index if not exists journal_entry_lines_entry_idx
  on public.journal_entry_lines (journal_entry_id);
create index if not exists journal_entry_lines_account_idx
  on public.journal_entry_lines (account_id);
create index if not exists journal_entry_lines_org_idx
  on public.journal_entry_lines (organization_id);
create index if not exists journal_entry_lines_cost_center_idx
  on public.journal_entry_lines (cost_center_id);
-- Now attach account delete guard (depends on journal_entry_lines)
drop trigger if exists accounts_prevent_delete_movements on public.accounts;
create trigger accounts_prevent_delete_movements
before delete on public.accounts
for each row execute function public.prevent_account_delete_with_movements();
-- Line tenant / account / cost center consistency
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

  return new;
end;
$$;
drop trigger if exists journal_entry_lines_validate_tenancy on public.journal_entry_lines;
create trigger journal_entry_lines_validate_tenancy
before insert or update on public.journal_entry_lines
for each row execute function public.validate_journal_line_tenancy();
-- ---------------------------------------------------------------------------
-- Immutability of posted / reversed entries
-- ---------------------------------------------------------------------------

create or replace function public.prevent_posted_journal_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status in ('POSTED', 'REVERSED') then
      raise exception 'posted journal entries cannot be deleted';
    end if;
    return old;
  end if;

  -- Allow controlled transitions via SECURITY DEFINER engines only:
  -- engines set a session GUC flag accounting.engine_write = '1'
  if current_setting('accounting.engine_write', true) = '1' then
    return new;
  end if;

  if old.status in ('POSTED', 'REVERSED') then
    raise exception 'posted journal entries are immutable; use reversal';
  end if;

  -- Draft edits allowed for non-status-protected fields
  if new.status is distinct from old.status and new.status <> 'DRAFT' then
    raise exception 'status changes must go through posting/reversal engine';
  end if;

  return new;
end;
$$;
drop trigger if exists journal_entries_immutability on public.journal_entries;
create trigger journal_entries_immutability
before update or delete on public.journal_entries
for each row execute function public.prevent_posted_journal_mutation();
create or replace function public.prevent_posted_line_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  st public.journal_entry_status;
  entry_id uuid;
begin
  entry_id := coalesce(new.journal_entry_id, old.journal_entry_id);
  select status into st from public.journal_entries where id = entry_id;

  if current_setting('accounting.engine_write', true) = '1' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if st in ('POSTED', 'REVERSED') then
    raise exception 'lines of posted journal entries are immutable';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
drop trigger if exists journal_entry_lines_immutability on public.journal_entry_lines;
create trigger journal_entry_lines_immutability
before update or delete on public.journal_entry_lines
for each row execute function public.prevent_posted_line_mutation();
-- ---------------------------------------------------------------------------
-- Helpers: resolve open period for a date
-- ---------------------------------------------------------------------------

create or replace function public.resolve_open_period(
  p_organization_id uuid,
  p_entry_date date
)
returns table (
  period_id uuid,
  fiscal_year_id uuid
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return query
  select ap.id, ap.fiscal_year_id
  from public.accounting_periods ap
  join public.accounting_fiscal_years fy on fy.id = ap.fiscal_year_id
  where ap.organization_id = p_organization_id
    and ap.status = 'OPEN'
    and fy.status = 'OPEN'
    and p_entry_date between ap.starts_on and ap.ends_on
  limit 1;
end;
$$;
-- ---------------------------------------------------------------------------
-- Next entry number (row lock)
-- ---------------------------------------------------------------------------

create or replace function public.next_journal_entry_number(
  p_organization_id uuid,
  p_fiscal_year_id uuid
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v bigint;
begin
  insert into public.accounting_sequences (organization_id, fiscal_year_id, last_value)
  values (p_organization_id, p_fiscal_year_id, 0)
  on conflict (organization_id, fiscal_year_id) do nothing;

  select last_value into v
  from public.accounting_sequences
  where organization_id = p_organization_id
    and fiscal_year_id = p_fiscal_year_id
  for update;

  v := v + 1;

  update public.accounting_sequences
  set last_value = v, updated_at = timezone('utc', now())
  where organization_id = p_organization_id
    and fiscal_year_id = p_fiscal_year_id;

  return lpad(v::text, 8, '0');
end;
$$;
-- ---------------------------------------------------------------------------
-- Audit helper (internal)
-- ---------------------------------------------------------------------------

create or replace function public.accounting_write_audit(
  p_organization_id uuid,
  p_actor uuid,
  p_event_type text,
  p_entity_type text,
  p_entity_id text,
  p_action text,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.audit_events (
    organization_id, actor_user_id, event_type, entity_type, entity_id, action, metadata
  ) values (
    p_organization_id, p_actor, p_event_type, p_entity_type, p_entity_id, p_action,
    coalesce(p_metadata, '{}'::jsonb)
  );
end;
$$;
-- ---------------------------------------------------------------------------
-- POSTING ENGINE
-- ---------------------------------------------------------------------------

create or replace function public.post_journal_entry(p_entry_id uuid)
returns public.journal_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_entry public.journal_entries;
  v_period_id uuid;
  v_fy_id uuid;
  v_debit numeric(19,4);
  v_credit numeric(19,4);
  v_line_count int;
  v_number text;
  v_bad int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into v_entry
  from public.journal_entries
  where id = p_entry_id
  for update;

  if not found then
    raise exception 'journal entry not found';
  end if;

  if not public.is_org_member(v_entry.organization_id) then
    raise exception 'not a member of organization';
  end if;

  if not public.has_org_role(
    v_entry.organization_id,
    array['owner','admin','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role to post journal entries';
  end if;

  if v_entry.status <> 'DRAFT' then
    raise exception 'only DRAFT entries can be posted';
  end if;

  select period_id, fiscal_year_id into v_period_id, v_fy_id
  from public.resolve_open_period(v_entry.organization_id, v_entry.entry_date);

  if v_period_id is null then
    raise exception 'no OPEN period (and OPEN fiscal year) covers entry_date';
  end if;

  select
    count(*)::int,
    coalesce(sum(debit), 0),
    coalesce(sum(credit), 0)
  into v_line_count, v_debit, v_credit
  from public.journal_entry_lines
  where journal_entry_id = p_entry_id;

  if v_line_count < 2 then
    raise exception 'posted entries require at least two lines';
  end if;

  if v_debit <> v_credit then
    raise exception 'unbalanced entry: debit % <> credit %', v_debit, v_credit;
  end if;

  if v_debit <= 0 then
    raise exception 'posted entry totals must be greater than zero';
  end if;

  select count(*)::int into v_bad
  from public.journal_entry_lines jel
  join public.accounts a on a.id = jel.account_id
  where jel.journal_entry_id = p_entry_id
    and (
      a.organization_id <> v_entry.organization_id
      or not a.is_active
      or not a.is_postable
    );

  if v_bad > 0 then
    raise exception 'one or more lines reference invalid accounts';
  end if;

  v_number := public.next_journal_entry_number(v_entry.organization_id, v_fy_id);

  perform set_config('accounting.engine_write', '1', true);

  update public.journal_entries
  set
    status = 'POSTED',
    entry_number = v_number,
    period_id = v_period_id,
    fiscal_year_id = v_fy_id,
    posted_by = v_uid,
    posted_at = timezone('utc', now())
  where id = p_entry_id
  returning * into v_entry;

  perform set_config('accounting.engine_write', '0', true);

  perform public.accounting_write_audit(
    v_entry.organization_id,
    v_uid,
    'journal.posted',
    'journal_entry',
    v_entry.id::text,
    'post',
    jsonb_build_object(
      'entry_number', v_entry.entry_number,
      'entry_date', v_entry.entry_date,
      'debit_total', v_debit,
      'credit_total', v_credit,
      'period_id', v_period_id
    )
  );

  return v_entry;
end;
$$;
-- ---------------------------------------------------------------------------
-- REVERSAL ENGINE
-- ---------------------------------------------------------------------------

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
-- ---------------------------------------------------------------------------
-- Period close / reopen
-- ---------------------------------------------------------------------------

create or replace function public.close_accounting_period(p_period_id uuid)
returns public.accounting_periods
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_period public.accounting_periods;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_period from public.accounting_periods where id = p_period_id for update;
  if not found then raise exception 'period not found'; end if;

  if not public.has_org_role(
    v_period.organization_id,
    array['owner','admin','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role to close period';
  end if;

  if v_period.status = 'CLOSED' then
    raise exception 'period already closed';
  end if;

  if exists (
    select 1 from public.journal_entries
    where organization_id = v_period.organization_id
      and entry_date between v_period.starts_on and v_period.ends_on
      and status = 'DRAFT'
  ) then
    raise exception 'period has DRAFT entries; post or delete drafts before closing';
  end if;

  update public.accounting_periods
  set status = 'CLOSED', closed_by = v_uid, closed_at = timezone('utc', now())
  where id = p_period_id
  returning * into v_period;

  perform public.accounting_write_audit(
    v_period.organization_id, v_uid, 'period.closed', 'accounting_period',
    v_period.id::text, 'close',
    jsonb_build_object('name', v_period.name, 'starts_on', v_period.starts_on, 'ends_on', v_period.ends_on)
  );

  return v_period;
end;
$$;
create or replace function public.reopen_accounting_period(
  p_period_id uuid,
  p_reason text
)
returns public.accounting_periods
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_period public.accounting_periods;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'reopen reason is required';
  end if;

  select * into v_period from public.accounting_periods where id = p_period_id for update;
  if not found then raise exception 'period not found'; end if;

  -- Privileged: owner/admin only (accountant may close but reopen is exceptional)
  if not public.has_org_role(
    v_period.organization_id,
    array['owner','admin']::public.member_role[]
  ) then
    raise exception 'insufficient role to reopen period';
  end if;

  if v_period.status <> 'CLOSED' then
    raise exception 'period is not closed';
  end if;

  -- Fiscal year must still be OPEN
  if exists (
    select 1 from public.accounting_fiscal_years
    where id = v_period.fiscal_year_id and status = 'CLOSED'
  ) then
    raise exception 'cannot reopen period in a CLOSED fiscal year';
  end if;

  update public.accounting_periods
  set
    status = 'OPEN',
    reopened_by = v_uid,
    reopened_at = timezone('utc', now()),
    reopen_reason = trim(p_reason),
    closed_at = null,
    closed_by = null
  where id = p_period_id
  returning * into v_period;

  perform public.accounting_write_audit(
    v_period.organization_id, v_uid, 'period.reopened', 'accounting_period',
    v_period.id::text, 'reopen',
    jsonb_build_object('name', v_period.name, 'reason', trim(p_reason))
  );

  return v_period;
end;
$$;
-- ---------------------------------------------------------------------------
-- Starter chart of accounts template (replaceable)
-- ---------------------------------------------------------------------------

create or replace function public.seed_starter_chart_of_accounts(p_organization_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  n int := 0;
  id_1 uuid; id_11 uuid; id_12 uuid;
  id_2 uuid; id_21 uuid; id_22 uuid;
  id_3 uuid; id_4 uuid; id_5 uuid; id_6 uuid;
begin
  if not public.has_org_role(
    p_organization_id,
    array['owner','admin','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role to seed chart of accounts';
  end if;

  if exists (select 1 from public.accounts where organization_id = p_organization_id) then
    return 0;
  end if;

  insert into public.accounts (organization_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, '1', 'ACTIVO', 'ASSET', 'DEBIT', false, 'group_asset')
  returning id into id_1;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_1, '1.1', 'Activo corriente', 'ASSET', 'DEBIT', false, 'group_asset_current')
  returning id into id_11;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values
    (p_organization_id, id_11, '1.1.01', 'Caja', 'ASSET', 'DEBIT', true, 'cash'),
    (p_organization_id, id_11, '1.1.02', 'Bancos', 'ASSET', 'DEBIT', true, 'bank'),
    (p_organization_id, id_11, '1.1.03', 'Clientes', 'ASSET', 'DEBIT', true, 'receivables');

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_1, '1.2', 'Activo no corriente', 'ASSET', 'DEBIT', false, 'group_asset_noncurrent')
  returning id into id_12;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_12, '1.2.01', 'Bienes de uso', 'ASSET', 'DEBIT', true, 'fixed_assets');

  insert into public.accounts (organization_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, '2', 'PASIVO', 'LIABILITY', 'CREDIT', false, 'group_liability')
  returning id into id_2;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_2, '2.1', 'Pasivo corriente', 'LIABILITY', 'CREDIT', false, 'group_liability_current')
  returning id into id_21;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values
    (p_organization_id, id_21, '2.1.01', 'Proveedores', 'LIABILITY', 'CREDIT', true, 'payables'),
    (p_organization_id, id_21, '2.1.02', 'Obligaciones a pagar', 'LIABILITY', 'CREDIT', true, null);

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_2, '2.2', 'Pasivo no corriente', 'LIABILITY', 'CREDIT', false, 'group_liability_noncurrent')
  returning id into id_22;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_22, '2.2.01', 'Deudas a largo plazo', 'LIABILITY', 'CREDIT', true, null);

  insert into public.accounts (organization_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, '3', 'PATRIMONIO NETO', 'EQUITY', 'CREDIT', false, 'group_equity')
  returning id into id_3;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_3, '3.1.01', 'Capital', 'EQUITY', 'CREDIT', true, 'capital');

  insert into public.accounts (organization_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, '4', 'INGRESOS', 'REVENUE', 'CREDIT', false, 'group_revenue')
  returning id into id_4;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_4, '4.1.01', 'Ventas', 'REVENUE', 'CREDIT', true, 'sales');

  insert into public.accounts (organization_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, '5', 'COSTOS', 'EXPENSE', 'DEBIT', false, 'group_cogs')
  returning id into id_5;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_5, '5.1.01', 'Costo de mercaderías vendidas', 'EXPENSE', 'DEBIT', true, 'cogs');

  insert into public.accounts (organization_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, '6', 'GASTOS', 'EXPENSE', 'DEBIT', false, 'group_expense')
  returning id into id_6;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values
    (p_organization_id, id_6, '6.1.01', 'Gastos de administración', 'EXPENSE', 'DEBIT', true, null),
    (p_organization_id, id_6, '6.1.02', 'Gastos de comercialización', 'EXPENSE', 'DEBIT', true, null);

  select count(*)::int into n from public.accounts where organization_id = p_organization_id;
  return n;
end;
$$;
-- ---------------------------------------------------------------------------
-- Ensure monthly periods helper for a fiscal year
-- ---------------------------------------------------------------------------

create or replace function public.ensure_monthly_periods(p_fiscal_year_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  fy public.accounting_fiscal_years;
  d date;
  month_end date;
  created int := 0;
  month_names text[] := array[
    'Enero','Febrero','Marzo','Abril','Mayo','Junio',
    'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'
  ];
begin
  select * into fy from public.accounting_fiscal_years where id = p_fiscal_year_id;
  if not found then raise exception 'fiscal year not found'; end if;

  if not public.has_org_role(
    fy.organization_id,
    array['owner','admin','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role';
  end if;

  d := date_trunc('month', fy.start_date::timestamp)::date;
  while d <= fy.end_date loop
    month_end := (date_trunc('month', d::timestamp) + interval '1 month - 1 day')::date;
    if month_end > fy.end_date then
      month_end := fy.end_date;
    end if;
    if d < fy.start_date then
      d := fy.start_date;
    end if;

    insert into public.accounting_periods (
      organization_id, fiscal_year_id, name, starts_on, ends_on, status, is_closed
    )
    select
      fy.organization_id,
      fy.id,
      month_names[extract(month from d)::int] || ' ' || extract(year from d)::text,
      greatest(d, fy.start_date),
      month_end,
      'OPEN',
      false
    where not exists (
      select 1 from public.accounting_periods ap
      where ap.organization_id = fy.organization_id
        and ap.starts_on = greatest(d, fy.start_date)
        and ap.ends_on = month_end
    );

    if found then
      created := created + 1;
    end if;

    d := (date_trunc('month', d::timestamp) + interval '1 month')::date;
  end loop;

  return created;
end;
$$;
-- Flip platform flags (staging)
update public.app_settings
set value = '2'::jsonb, updated_at = timezone('utc', now())
where key = 'platform.phase';
update public.app_settings
set value = 'true'::jsonb, updated_at = timezone('utc', now())
where key = 'platform.accounting_core_enabled';
update public.feature_catalog
set default_status = 'enabled'
where code = 'accounting';
