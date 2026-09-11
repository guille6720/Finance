-- Phase 7 — Treasury core (STAGING)
-- Approved: CASH|BANK only; OPENING_BALANCE|PAYMENT|COLLECTION|TRANSFER|ADJUSTMENT
-- No CLEARING. No cash_sessions. No editable current_balance truth.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.treasury_account_type as enum ('CASH', 'BANK');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.treasury_operation_type as enum (
    'OPENING_BALANCE', 'PAYMENT', 'COLLECTION', 'TRANSFER', 'ADJUSTMENT'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.treasury_operation_status as enum (
    'DRAFT', 'POSTED', 'REVERSED'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.treasury_accounting_status as enum (
    'PENDING', 'POSTED', 'ACCOUNTING_REQUIRES_REVIEW', 'ERROR'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.treasury_leg_direction as enum ('INFLOW', 'OUTFLOW');
exception when duplicate_object then null;
end $$;
-- ---------------------------------------------------------------------------
-- Sequences
-- ---------------------------------------------------------------------------

create table public.treasury_operation_sequences (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  operation_type public.treasury_operation_type not null,
  sequence_year int not null check (sequence_year >= 2000 and sequence_year <= 2100),
  last_value bigint not null default 0 check (last_value >= 0),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (organization_id, operation_type, sequence_year)
);
-- ---------------------------------------------------------------------------
-- treasury_accounts
-- ---------------------------------------------------------------------------

create table public.treasury_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  account_type public.treasury_account_type not null,
  code text not null check (length(trim(code)) >= 1),
  name text not null check (length(trim(name)) >= 1),
  currency_code text not null default 'ARS' check (currency_code = 'ARS'),
  accounting_account_id uuid not null,
  bank_name text,
  account_mask text,
  cbu_cvu_alias text,
  is_active boolean not null default true,
  -- UX hint only — NOT monetary source of truth (truth = POSTED OPENING_BALANCE leg)
  opening_setup_note text,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint treasury_accounts_org_id_unique unique (organization_id, id),
  constraint treasury_accounts_code_unique unique (organization_id, code),
  constraint treasury_accounts_coa_unique unique (organization_id, accounting_account_id),
  constraint treasury_accounts_org_branch_fk
    foreign key (organization_id, branch_id)
    references public.branches (organization_id, id)
    on delete restrict,
  constraint treasury_accounts_org_coa_fk
    foreign key (organization_id, accounting_account_id)
    references public.accounts (organization_id, id)
    on delete restrict,
  constraint treasury_accounts_bank_meta_check check (
    account_type = 'BANK'
    or (bank_name is null and account_mask is null and cbu_cvu_alias is null)
  )
);
create index treasury_accounts_org_type_active_idx
  on public.treasury_accounts (organization_id, account_type, is_active);
create index treasury_accounts_org_branch_idx
  on public.treasury_accounts (organization_id, branch_id)
  where branch_id is not null;
create index treasury_accounts_created_by_idx
  on public.treasury_accounts (created_by)
  where created_by is not null;
create trigger treasury_accounts_set_updated_at
before update on public.treasury_accounts
for each row execute function public.set_updated_at();
comment on column public.treasury_accounts.opening_setup_note is
  'Optional onboarding UX note only — monetary opening is OPENING_BALANCE treasury operation.';
-- ---------------------------------------------------------------------------
-- treasury_operations
-- ---------------------------------------------------------------------------

create table public.treasury_operations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  internal_number text not null,
  operation_type public.treasury_operation_type not null,
  status public.treasury_operation_status not null default 'DRAFT',
  accounting_status public.treasury_accounting_status not null default 'PENDING',
  operation_date date not null,
  counterparty_id uuid,
  amount numeric(19, 4) not null check (amount > 0),
  currency_code text not null default 'ARS' check (currency_code = 'ARS'),
  reference text,
  description text not null check (length(trim(description)) >= 1),
  reason text,
  idempotency_key text not null,
  journal_entry_id uuid,
  reverse_journal_entry_id uuid,
  created_by uuid references auth.users (id),
  posted_by uuid references auth.users (id),
  reversed_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  posted_at timestamptz,
  reversed_at timestamptz,
  constraint treasury_operations_org_id_unique unique (organization_id, id),
  constraint treasury_operations_number_unique unique (organization_id, internal_number),
  constraint treasury_operations_idempotency_unique unique (organization_id, idempotency_key),
  constraint treasury_operations_org_branch_fk
    foreign key (organization_id, branch_id)
    references public.branches (organization_id, id)
    on delete restrict,
  constraint treasury_operations_org_cp_fk
    foreign key (organization_id, counterparty_id)
    references public.counterparties (organization_id, id)
    on delete restrict,
  constraint treasury_operations_journal_fk
    foreign key (journal_entry_id) references public.journal_entries (id) on delete restrict,
  constraint treasury_operations_reverse_journal_fk
    foreign key (reverse_journal_entry_id) references public.journal_entries (id) on delete restrict,
  constraint treasury_operations_payment_collection_cp check (
    operation_type not in ('PAYMENT', 'COLLECTION') or counterparty_id is not null
  )
);
create index treasury_operations_org_status_date_idx
  on public.treasury_operations (organization_id, status, operation_date desc);
create index treasury_operations_org_type_date_idx
  on public.treasury_operations (organization_id, operation_type, operation_date desc);
create index treasury_operations_org_cp_date_idx
  on public.treasury_operations (organization_id, counterparty_id, operation_date desc)
  where counterparty_id is not null;
create index treasury_operations_journal_idx
  on public.treasury_operations (journal_entry_id)
  where journal_entry_id is not null;
create index treasury_operations_reverse_journal_idx
  on public.treasury_operations (reverse_journal_entry_id)
  where reverse_journal_entry_id is not null;
create index treasury_operations_created_by_idx
  on public.treasury_operations (created_by)
  where created_by is not null;
create index treasury_operations_posted_by_idx
  on public.treasury_operations (posted_by)
  where posted_by is not null;
create index treasury_operations_org_branch_idx
  on public.treasury_operations (organization_id, branch_id)
  where branch_id is not null;
create trigger treasury_operations_set_updated_at
before update on public.treasury_operations
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- treasury_operation_legs
-- ---------------------------------------------------------------------------

create table public.treasury_operation_legs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  treasury_operation_id uuid not null,
  treasury_account_id uuid not null,
  direction public.treasury_leg_direction not null,
  amount numeric(19, 4) not null check (amount > 0),
  line_number int not null check (line_number > 0),
  created_at timestamptz not null default timezone('utc', now()),
  unique (treasury_operation_id, line_number),
  constraint treasury_legs_org_id_unique unique (organization_id, id),
  constraint treasury_legs_org_op_fk
    foreign key (organization_id, treasury_operation_id)
    references public.treasury_operations (organization_id, id)
    on delete cascade,
  constraint treasury_legs_org_account_fk
    foreign key (organization_id, treasury_account_id)
    references public.treasury_accounts (organization_id, id)
    on delete restrict
);
create index treasury_legs_org_account_op_idx
  on public.treasury_operation_legs (organization_id, treasury_account_id, treasury_operation_id);
create index treasury_legs_op_idx
  on public.treasury_operation_legs (treasury_operation_id);
create index treasury_legs_account_idx
  on public.treasury_operation_legs (treasury_account_id);
-- ---------------------------------------------------------------------------
-- Posted operation immutability (client)
-- ---------------------------------------------------------------------------

create or replace function public.prevent_posted_treasury_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status in ('POSTED', 'REVERSED')
      and current_setting('treasury.engine_write', true) is distinct from '1' then
      raise exception 'posted/reversed treasury operations cannot be deleted';
    end if;
    return old;
  end if;

  if old.status in ('POSTED', 'REVERSED')
    and current_setting('treasury.engine_write', true) is distinct from '1' then
    if new.status is distinct from old.status
      or new.amount is distinct from old.amount
      or new.operation_type is distinct from old.operation_type
      or new.operation_date is distinct from old.operation_date
      or new.counterparty_id is distinct from old.counterparty_id
      or new.journal_entry_id is distinct from old.journal_entry_id
      or new.currency_code is distinct from old.currency_code
      or new.internal_number is distinct from old.internal_number
    then
      raise exception 'posted treasury operations are immutable; use reversal';
    end if;
  end if;
  return new;
end;
$$;
create trigger treasury_operations_prevent_posted_mutation
before update or delete on public.treasury_operations
for each row execute function public.prevent_posted_treasury_mutation();
create or replace function public.prevent_posted_treasury_leg_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_status public.treasury_operation_status;
begin
  select status into v_status
  from public.treasury_operations
  where id = coalesce(new.treasury_operation_id, old.treasury_operation_id);

  if v_status in ('POSTED', 'REVERSED')
    and current_setting('treasury.engine_write', true) is distinct from '1' then
    raise exception 'legs on posted treasury operations cannot be modified';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger treasury_legs_prevent_posted_mutation
before insert or update or delete on public.treasury_operation_legs
for each row execute function public.prevent_posted_treasury_leg_mutation();
-- ---------------------------------------------------------------------------
-- Derived balance (POSTED legs only; REVERSED excluded)
-- ---------------------------------------------------------------------------

create or replace function public.treasury_account_balance(p_account_id uuid)
returns numeric
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(sum(
    case
      when l.direction = 'INFLOW' then l.amount
      when l.direction = 'OUTFLOW' then -l.amount
      else 0
    end
  ), 0)
  from public.treasury_operation_legs l
  join public.treasury_operations o
    on o.id = l.treasury_operation_id
   and o.organization_id = l.organization_id
  where l.treasury_account_id = p_account_id
    and o.status = 'POSTED';
$$;
comment on function public.treasury_account_balance(uuid) is
  'INTERNAL treasury balance from POSTED legs only. Not bank-confirmed.';
