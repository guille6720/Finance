-- Phase 7 — Accounts receivable + Phase 5 handoff (NEW integration only)

do $$ begin
  create type public.accounts_receivable_direction as enum (
    'AR_INCREASE', 'AR_DECREASE'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.accounts_receivable_status as enum (
    'OPEN', 'PARTIALLY_COLLECTED', 'COLLECTED', 'VOID'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.ar_source_type as enum ('FISCAL_DOCUMENT');
exception when duplicate_object then null;
end $$;
create table public.accounts_receivable_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  customer_id uuid not null,
  source_type public.ar_source_type not null default 'FISCAL_DOCUMENT',
  source_id uuid not null,
  fiscal_document_id uuid not null,
  direction public.accounts_receivable_direction not null,
  original_amount numeric(19, 4) not null check (original_amount >= 0),
  open_amount numeric(19, 4) not null check (open_amount >= 0),
  currency_code text not null default 'ARS' check (currency_code = 'ARS'),
  due_date date,
  status public.accounts_receivable_status not null default 'OPEN',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (fiscal_document_id),
  unique (organization_id, source_type, source_id),
  constraint accounts_receivable_items_org_id_unique unique (organization_id, id),
  constraint accounts_receivable_open_lte_original check (open_amount <= original_amount),
  constraint accounts_receivable_org_customer_fk
    foreign key (organization_id, customer_id)
    references public.counterparties (organization_id, id)
    on delete restrict,
  constraint accounts_receivable_org_fiscal_fk
    foreign key (organization_id, fiscal_document_id)
    references public.fiscal_documents (organization_id, id)
    on delete restrict
);
create index accounts_receivable_org_status_due_idx
  on public.accounts_receivable_items (organization_id, status, due_date);
create index accounts_receivable_org_customer_idx
  on public.accounts_receivable_items (organization_id, customer_id);
create index accounts_receivable_source_idx
  on public.accounts_receivable_items (organization_id, source_type, source_id);
create trigger accounts_receivable_items_set_updated_at
before update on public.accounts_receivable_items
for each row execute function public.set_updated_at();
comment on column public.accounts_receivable_items.due_date is
  'Nullable — do not invent payment terms; UI may show Sin vencimiento informado.';
-- Engine-only AR mutation
create or replace function public.prevent_ar_client_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if current_setting('treasury.engine_write', true) is distinct from '1' then
      raise exception 'accounts receivable items cannot be deleted directly';
    end if;
    return old;
  end if;
  if current_setting('treasury.engine_write', true) is distinct from '1' then
    if new.open_amount is distinct from old.open_amount
      or new.original_amount is distinct from old.original_amount
      or new.direction is distinct from old.direction
      or new.status is distinct from old.status
      or new.fiscal_document_id is distinct from old.fiscal_document_id
      or new.customer_id is distinct from old.customer_id
      or new.source_id is distinct from old.source_id
    then
      raise exception 'accounts receivable monetary/status fields are engine-only';
    end if;
  end if;
  return new;
end;
$$;
create trigger accounts_receivable_items_engine_only
before update or delete on public.accounts_receivable_items
for each row execute function public.prevent_ar_client_mutation();
-- Extend Phase 6 AP trigger to also accept treasury.engine_write (NEW migration replaces fn)
create or replace function public.prevent_ap_client_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if current_setting('purchase.engine_write', true) is distinct from '1'
      and current_setting('treasury.engine_write', true) is distinct from '1' then
      raise exception 'accounts payable items cannot be deleted directly';
    end if;
    return old;
  end if;
  if current_setting('purchase.engine_write', true) is distinct from '1'
    and current_setting('treasury.engine_write', true) is distinct from '1' then
    if new.open_amount is distinct from old.open_amount
      or new.original_amount is distinct from old.original_amount
      or new.direction is distinct from old.direction
      or new.status is distinct from old.status
      or new.purchase_document_id is distinct from old.purchase_document_id
      or new.supplier_id is distinct from old.supplier_id
    then
      raise exception 'accounts payable monetary/status fields are engine-only';
    end if;
  end if;
  return new;
end;
$$;
-- Explicit trusted AR ensure (NOT called from SELECT/page render)
create or replace function public.ensure_ar_from_fiscal_document(p_fiscal_document_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.fiscal_documents%rowtype;
  v_existing uuid;
  v_direction public.accounts_receivable_direction;
  v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select * into v_doc from public.fiscal_documents where id = p_fiscal_document_id for update;
  if not found then raise exception 'fiscal document not found'; end if;

  if not public.is_org_member(v_doc.organization_id) then
    raise exception 'not a member of organization';
  end if;
  if not public.has_org_role(
    v_doc.organization_id,
    array['owner','admin','accountant','manager']::public.member_role[]
  ) then
    raise exception 'insufficient role to create receivable';
  end if;

  select id into v_existing
  from public.accounts_receivable_items
  where fiscal_document_id = p_fiscal_document_id;
  if v_existing is not null then
    return v_existing;
  end if;

  if v_doc.status is distinct from 'AUTHORIZED' then
    raise exception 'only AUTHORIZED fiscal documents may create AR items';
  end if;

  if v_doc.currency_code not in ('ARS', 'PES') then
    raise exception 'Phase 7 MVP AR requires ARS/PES fiscal documents';
  end if;

  if v_doc.total_amount <= 0 then
    raise exception 'fiscal document total must be positive';
  end if;

  v_direction := case
    when v_doc.document_class = 'CREDIT_NOTE' then 'AR_DECREASE'::public.accounts_receivable_direction
    else 'AR_INCREASE'::public.accounts_receivable_direction
  end;

  perform set_config('treasury.engine_write', '1', true);

  insert into public.accounts_receivable_items (
    organization_id, customer_id, source_type, source_id, fiscal_document_id,
    direction, original_amount, open_amount, currency_code, due_date, status
  ) values (
    v_doc.organization_id, v_doc.counterparty_id, 'FISCAL_DOCUMENT', v_doc.id, v_doc.id,
    v_direction, v_doc.total_amount, v_doc.total_amount, 'ARS', null, 'OPEN'
  )
  on conflict (fiscal_document_id) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.accounts_receivable_items where fiscal_document_id = p_fiscal_document_id;
  end if;

  return v_id;
end;
$$;
revoke all on function public.ensure_ar_from_fiscal_document(uuid) from public, anon;
grant execute on function public.ensure_ar_from_fiscal_document(uuid) to authenticated;
grant execute on function public.treasury_account_balance(uuid) to authenticated;
