-- Phase 7 — Allocations + open-item compensations

do $$ begin
  create type public.open_item_domain as enum ('AP', 'AR');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.compensation_status as enum ('POSTED', 'REVERSED');
exception when duplicate_object then null;
end $$;
create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  treasury_operation_id uuid not null,
  accounts_payable_item_id uuid not null,
  allocated_amount numeric(19, 4) not null check (allocated_amount > 0),
  created_at timestamptz not null default timezone('utc', now()),
  unique (treasury_operation_id, accounts_payable_item_id),
  constraint payment_allocations_org_op_fk
    foreign key (organization_id, treasury_operation_id)
    references public.treasury_operations (organization_id, id)
    on delete cascade,
  constraint payment_allocations_org_ap_fk
    foreign key (organization_id, accounts_payable_item_id)
    references public.accounts_payable_items (organization_id, id)
    on delete restrict
);
create index payment_allocations_op_idx
  on public.payment_allocations (treasury_operation_id);
create index payment_allocations_ap_idx
  on public.payment_allocations (organization_id, accounts_payable_item_id);
create table public.collection_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  treasury_operation_id uuid not null,
  accounts_receivable_item_id uuid not null,
  allocated_amount numeric(19, 4) not null check (allocated_amount > 0),
  created_at timestamptz not null default timezone('utc', now()),
  unique (treasury_operation_id, accounts_receivable_item_id),
  constraint collection_allocations_org_op_fk
    foreign key (organization_id, treasury_operation_id)
    references public.treasury_operations (organization_id, id)
    on delete cascade,
  constraint collection_allocations_org_ar_fk
    foreign key (organization_id, accounts_receivable_item_id)
    references public.accounts_receivable_items (organization_id, id)
    on delete restrict
);
create index collection_allocations_op_idx
  on public.collection_allocations (treasury_operation_id);
create index collection_allocations_ar_idx
  on public.collection_allocations (organization_id, accounts_receivable_item_id);
create table public.open_item_compensations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  domain public.open_item_domain not null,
  increase_item_id uuid not null,
  decrease_item_id uuid not null,
  amount numeric(19, 4) not null check (amount > 0),
  status public.compensation_status not null default 'POSTED',
  idempotency_key text not null,
  created_by uuid references auth.users (id),
  reversed_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  reversed_at timestamptz,
  unique (organization_id, idempotency_key),
  constraint open_item_compensations_distinct check (increase_item_id <> decrease_item_id)
);
create index open_item_compensations_org_domain_idx
  on public.open_item_compensations (organization_id, domain, status);
create index open_item_compensations_increase_idx
  on public.open_item_compensations (increase_item_id);
create index open_item_compensations_decrease_idx
  on public.open_item_compensations (decrease_item_id);
-- Block client mutation of allocations once operation is POSTED
create or replace function public.prevent_posted_allocation_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_status public.treasury_operation_status;
  v_op uuid := coalesce(new.treasury_operation_id, old.treasury_operation_id);
begin
  select status into v_status from public.treasury_operations where id = v_op;
  if v_status in ('POSTED', 'REVERSED')
    and current_setting('treasury.engine_write', true) is distinct from '1' then
    raise exception 'allocations on posted treasury operations are immutable';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger payment_allocations_prevent_posted
before insert or update or delete on public.payment_allocations
for each row execute function public.prevent_posted_allocation_mutation();
create trigger collection_allocations_prevent_posted
before insert or update or delete on public.collection_allocations
for each row execute function public.prevent_posted_allocation_mutation();
-- Treasury accounting mappings
create table public.treasury_accounting_mappings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  accounts_payable_account_id uuid,
  accounts_receivable_account_id uuid,
  opening_equity_account_id uuid,
  adjustment_offset_account_id uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id),
  constraint treasury_acct_map_ap_fk
    foreign key (organization_id, accounts_payable_account_id)
    references public.accounts (organization_id, id) on delete restrict,
  constraint treasury_acct_map_ar_fk
    foreign key (organization_id, accounts_receivable_account_id)
    references public.accounts (organization_id, id) on delete restrict,
  constraint treasury_acct_map_equity_fk
    foreign key (organization_id, opening_equity_account_id)
    references public.accounts (organization_id, id) on delete restrict,
  constraint treasury_acct_map_adj_fk
    foreign key (organization_id, adjustment_offset_account_id)
    references public.accounts (organization_id, id) on delete restrict
);
create index treasury_acct_map_ap_idx
  on public.treasury_accounting_mappings (organization_id, accounts_payable_account_id)
  where accounts_payable_account_id is not null;
create index treasury_acct_map_ar_idx
  on public.treasury_accounting_mappings (organization_id, accounts_receivable_account_id)
  where accounts_receivable_account_id is not null;
create index treasury_acct_map_equity_idx
  on public.treasury_accounting_mappings (organization_id, opening_equity_account_id)
  where opening_equity_account_id is not null;
create index treasury_acct_map_adj_idx
  on public.treasury_accounting_mappings (organization_id, adjustment_offset_account_id)
  where adjustment_offset_account_id is not null;
create trigger treasury_accounting_mappings_set_updated_at
before update on public.treasury_accounting_mappings
for each row execute function public.set_updated_at();
