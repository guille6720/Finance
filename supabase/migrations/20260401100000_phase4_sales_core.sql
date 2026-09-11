-- Phase 4 — Sales core (STAGING)
-- Commercial documents only — NOT fiscal invoices

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.sales_document_type as enum ('QUOTE', 'SALES_ORDER');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.sales_document_status as enum (
    'DRAFT', 'SENT', 'ACCEPTED', 'REJECTED', 'CANCELLED', 'CONVERTED',
    'CONFIRMED', 'READY_TO_INVOICE'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.sales_discount_input_mode as enum ('PERCENT', 'AMOUNT');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.sales_line_unit_code as enum (
    'UNIT', 'HOUR', 'KG', 'M', 'OTHER'
  );
exception when duplicate_object then null;
end $$;
-- Branch composite FK support
alter table public.branches
  drop constraint if exists branches_org_id_unique;
alter table public.branches
  add constraint branches_org_id_unique unique (organization_id, id);
-- ---------------------------------------------------------------------------
-- sales_document_sequences
-- ---------------------------------------------------------------------------

create table public.sales_document_sequences (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  document_type public.sales_document_type not null,
  sequence_year int not null check (sequence_year >= 2000 and sequence_year <= 2100),
  last_value bigint not null default 0 check (last_value >= 0),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (organization_id, document_type, sequence_year)
);
-- ---------------------------------------------------------------------------
-- sales_documents
-- ---------------------------------------------------------------------------

create table public.sales_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  document_type public.sales_document_type not null,
  internal_number text not null,
  counterparty_id uuid not null,
  status public.sales_document_status not null default 'DRAFT',
  document_date date not null default (timezone('utc', now()))::date,
  valid_until date,
  expected_delivery_date date,
  currency_code text not null default 'ARS' check (currency_code ~ '^[A-Z]{3}$'),
  description text,
  customer_reference text,
  payment_terms_text text,
  payment_due_days int check (payment_due_days is null or payment_due_days >= 0),
  notes text,
  internal_notes text,
  source_document_id uuid references public.sales_documents (id) on delete restrict,
  converted_to_order_id uuid unique,
  counterparty_snapshot jsonb not null default '{}'::jsonb,
  subtotal numeric(19, 4) not null default 0 check (subtotal >= 0),
  discount_total numeric(19, 4) not null default 0 check (discount_total >= 0),
  total numeric(19, 4) not null default 0 check (total >= 0),
  is_commercially_frozen boolean not null default false,
  created_by uuid references auth.users (id),
  confirmed_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  confirmed_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  constraint sales_documents_org_id_unique unique (organization_id, id),
  constraint sales_documents_internal_number_unique unique (organization_id, document_type, internal_number),
  constraint sales_documents_org_counterparty_fk
    foreign key (organization_id, counterparty_id)
    references public.counterparties (organization_id, id)
    on delete restrict,
  constraint sales_documents_org_branch_fk
    foreign key (organization_id, branch_id)
    references public.branches (organization_id, id)
    on delete restrict
);
create index sales_documents_org_type_status_idx
  on public.sales_documents (organization_id, document_type, status);
create index sales_documents_org_date_idx
  on public.sales_documents (organization_id, document_date desc);
create index sales_documents_org_number_idx
  on public.sales_documents (organization_id, internal_number);
create index sales_documents_counterparty_idx
  on public.sales_documents (counterparty_id);
create index sales_documents_source_idx
  on public.sales_documents (source_document_id)
  where source_document_id is not null;
alter table public.sales_documents
  add constraint sales_documents_converted_order_fk
  foreign key (converted_to_order_id)
  references public.sales_documents (id)
  on delete restrict;
create trigger sales_documents_set_updated_at
before update on public.sales_documents
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- sales_document_lines
-- ---------------------------------------------------------------------------

create table public.sales_document_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  sales_document_id uuid not null references public.sales_documents (id) on delete cascade,
  line_number int not null check (line_number > 0),
  description text not null check (length(trim(description)) >= 1),
  quantity numeric(18, 4) not null check (quantity > 0),
  unit_code public.sales_line_unit_code not null default 'UNIT',
  unit_price numeric(19, 4) not null check (unit_price >= 0),
  discount_input_mode public.sales_discount_input_mode not null default 'PERCENT',
  discount_percent numeric(7, 4) not null default 0 check (discount_percent >= 0 and discount_percent <= 100),
  discount_amount numeric(19, 4) not null default 0 check (discount_amount >= 0),
  line_subtotal numeric(19, 4) not null default 0 check (line_subtotal >= 0),
  line_total numeric(19, 4) not null default 0 check (line_total >= 0),
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (sales_document_id, line_number),
  constraint sales_document_lines_org_doc_fk
    foreign key (organization_id, sales_document_id)
    references public.sales_documents (organization_id, id)
    on delete cascade
);
create index sales_document_lines_document_idx
  on public.sales_document_lines (sales_document_id);
create trigger sales_document_lines_set_updated_at
before update on public.sales_document_lines
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- Status validation per document type
-- ---------------------------------------------------------------------------

create or replace function public.validate_sales_document_status_for_type()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.document_type = 'QUOTE' then
    if new.status not in ('DRAFT', 'SENT', 'ACCEPTED', 'REJECTED', 'CANCELLED', 'CONVERTED') then
      raise exception 'invalid quote status: %', new.status;
    end if;
  elsif new.document_type = 'SALES_ORDER' then
    if new.status not in ('DRAFT', 'CONFIRMED', 'READY_TO_INVOICE', 'CANCELLED') then
      raise exception 'invalid sales order status: %', new.status;
    end if;
  end if;
  return new;
end;
$$;
create trigger sales_documents_validate_status
before insert or update of status, document_type on public.sales_documents
for each row execute function public.validate_sales_document_status_for_type();
-- ---------------------------------------------------------------------------
-- Line discount + totals (authoritative)
-- ---------------------------------------------------------------------------

create or replace function public.recalculate_sales_line_amounts()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_subtotal numeric(19, 4);
  v_discount numeric(19, 4);
begin
  v_subtotal := round(new.quantity * new.unit_price, 4);

  if new.discount_input_mode = 'PERCENT' then
    if new.discount_percent < 0 or new.discount_percent > 100 then
      raise exception 'invalid discount percent';
    end if;
    v_discount := round(v_subtotal * new.discount_percent / 100, 4);
    new.discount_amount := v_discount;
  else
    v_discount := round(new.discount_amount, 4);
    if v_discount < 0 then
      raise exception 'discount amount cannot be negative';
    end if;
    if v_discount > v_subtotal then
      raise exception 'discount cannot exceed line subtotal';
    end if;
    if v_subtotal > 0 then
      new.discount_percent := round(v_discount / v_subtotal * 100, 4);
    else
      new.discount_percent := 0;
    end if;
  end if;

  new.line_subtotal := v_subtotal;
  new.line_total := round(v_subtotal - v_discount, 4);
  if new.line_total < 0 then
    raise exception 'line total cannot be negative';
  end if;
  return new;
end;
$$;
create trigger sales_document_lines_recalc
before insert or update on public.sales_document_lines
for each row execute function public.recalculate_sales_line_amounts();
create or replace function public.refresh_sales_document_totals(p_document_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_sub numeric(19, 4);
  v_disc numeric(19, 4);
  v_total numeric(19, 4);
begin
  select
    coalesce(sum(line_subtotal), 0),
    coalesce(sum(line_subtotal - line_total), 0),
    coalesce(sum(line_total), 0)
  into v_sub, v_disc, v_total
  from public.sales_document_lines
  where sales_document_id = p_document_id;

  update public.sales_documents
  set subtotal = v_sub, discount_total = v_disc, total = v_total
  where id = p_document_id;
end;
$$;
create or replace function public.sales_document_lines_refresh_header()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_sales_document_totals(old.sales_document_id);
    return old;
  end if;
  perform public.refresh_sales_document_totals(new.sales_document_id);
  return new;
end;
$$;
create trigger sales_document_lines_refresh_header_trg
after insert or update or delete on public.sales_document_lines
for each row execute function public.sales_document_lines_refresh_header();
-- ---------------------------------------------------------------------------
-- Customer validation helper
-- ---------------------------------------------------------------------------

create or replace function public.validate_sales_customer(
  p_organization_id uuid,
  p_counterparty_id uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_active boolean;
  v_has_customer boolean;
begin
  select c.is_active into v_active
  from public.counterparties c
  where c.id = p_counterparty_id and c.organization_id = p_organization_id;

  if v_active is null then
    raise exception 'counterparty not found';
  end if;
  if not v_active then
    raise exception 'customer is inactive';
  end if;

  select exists (
    select 1 from public.counterparty_roles r
    where r.counterparty_id = p_counterparty_id
      and r.organization_id = p_organization_id
      and r.role = 'CUSTOMER'
  ) into v_has_customer;

  if not v_has_customer then
    raise exception 'counterparty must have CUSTOMER role';
  end if;
end;
$$;
-- ---------------------------------------------------------------------------
-- Counterparty snapshot builder
-- ---------------------------------------------------------------------------

create or replace function public.build_counterparty_snapshot(
  p_organization_id uuid,
  p_counterparty_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_cp public.counterparties;
  v_fc_name text;
  v_addr text;
begin
  select * into v_cp
  from public.counterparties
  where id = p_counterparty_id and organization_id = p_organization_id;

  if v_cp.id is null then
    raise exception 'counterparty not found';
  end if;

  select fc.name_business into v_fc_name
  from public.counterparty_fiscal_profiles fp
  left join public.fiscal_conditions fc on fc.id = fp.fiscal_condition_id
  where fp.counterparty_id = p_counterparty_id;

  select coalesce(
    nullif(trim(concat_ws(' ', a.street, a.number, a.city, a.province)), ''),
    fp.fiscal_address
  ) into v_addr
  from public.counterparties c
  left join public.counterparty_fiscal_profiles fp on fp.counterparty_id = c.id
  left join lateral (
    select * from public.counterparty_addresses ca
    where ca.counterparty_id = c.id
    order by ca.is_primary desc, ca.created_at
    limit 1
  ) a on true
  where c.id = p_counterparty_id;

  return jsonb_build_object(
    'legal_name', v_cp.legal_name,
    'trade_name', v_cp.trade_name,
    'tax_id_type', v_cp.tax_id_type,
    'tax_id', v_cp.tax_id,
    'tax_id_normalized', v_cp.tax_id_normalized,
    'fiscal_condition_business', v_fc_name,
    'commercial_address', v_addr,
    'snapshot_at', timezone('utc', now())
  );
end;
$$;
-- ---------------------------------------------------------------------------
-- Internal numbering
-- ---------------------------------------------------------------------------

create or replace function public.next_sales_internal_number(
  p_organization_id uuid,
  p_document_type public.sales_document_type,
  p_document_date date
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_year int := extract(year from p_document_date)::int;
  v_seq bigint;
  v_prefix text;
begin
  if p_document_type = 'QUOTE' then
    v_prefix := 'PRES';
  else
    v_prefix := 'PED';
  end if;

  insert into public.sales_document_sequences (organization_id, document_type, sequence_year, last_value)
  values (p_organization_id, p_document_type, v_year, 0)
  on conflict (organization_id, document_type, sequence_year) do nothing;

  select last_value into v_seq
  from public.sales_document_sequences
  where organization_id = p_organization_id
    and document_type = p_document_type
    and sequence_year = v_year
  for update;

  v_seq := v_seq + 1;

  update public.sales_document_sequences
  set last_value = v_seq, updated_at = timezone('utc', now())
  where organization_id = p_organization_id
    and document_type = p_document_type
    and sequence_year = v_year;

  return v_prefix || '-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');
end;
$$;
-- ---------------------------------------------------------------------------
-- Commercial freeze guards
-- ---------------------------------------------------------------------------

create or replace function public.prevent_frozen_sales_document_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.is_commercially_frozen then
      if current_setting('sales.engine_write', true) is distinct from '1' then
        raise exception 'frozen sales document cannot be deleted';
      end if;
    end if;
    return old;
  end if;

  if old.is_commercially_frozen
    and current_setting('sales.engine_write', true) is distinct from '1' then
    if new.counterparty_id is distinct from old.counterparty_id
      or new.currency_code is distinct from old.currency_code
      or new.document_date is distinct from old.document_date
      or new.valid_until is distinct from old.valid_until
      or new.expected_delivery_date is distinct from old.expected_delivery_date
      or new.payment_terms_text is distinct from old.payment_terms_text
      or new.payment_due_days is distinct from old.payment_due_days
      or new.customer_reference is distinct from old.customer_reference
      or new.counterparty_snapshot is distinct from old.counterparty_snapshot
      or new.subtotal is distinct from old.subtotal
      or new.discount_total is distinct from old.discount_total
      or new.total is distinct from old.total
    then
      raise exception 'commercial fields are frozen on this document';
    end if;
  end if;

  return new;
end;
$$;
create trigger sales_documents_prevent_frozen_mutation
before update or delete on public.sales_documents
for each row execute function public.prevent_frozen_sales_document_mutation();
create or replace function public.prevent_frozen_sales_line_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_frozen boolean;
  v_status public.sales_document_status;
begin
  select is_commercially_frozen, status
    into v_frozen, v_status
  from public.sales_documents
  where id = coalesce(new.sales_document_id, old.sales_document_id);

  if v_frozen and current_setting('sales.engine_write', true) is distinct from '1' then
    raise exception 'lines are frozen on this document';
  end if;

  if v_status <> 'DRAFT' and tg_op <> 'DELETE' then
    if current_setting('sales.engine_write', true) is distinct from '1' then
      raise exception 'cannot modify lines on non-draft document';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger sales_document_lines_prevent_frozen_mutation
before insert or update or delete on public.sales_document_lines
for each row execute function public.prevent_frozen_sales_line_mutation();
-- Line tenant consistency
create or replace function public.validate_sales_line_tenancy()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  doc_org uuid;
begin
  select organization_id into doc_org
  from public.sales_documents where id = new.sales_document_id;
  if doc_org is null then raise exception 'sales document not found'; end if;
  if new.organization_id <> doc_org then
    raise exception 'line organization must match document';
  end if;
  return new;
end;
$$;
create trigger sales_document_lines_validate_tenancy
before insert or update on public.sales_document_lines
for each row execute function public.validate_sales_line_tenancy();
revoke all on function public.refresh_sales_document_totals(uuid) from public;
grant execute on function public.refresh_sales_document_totals(uuid) to authenticated;
revoke all on function public.validate_sales_customer(uuid, uuid) from public;
grant execute on function public.validate_sales_customer(uuid, uuid) to authenticated;
revoke all on function public.build_counterparty_snapshot(uuid, uuid) from public;
grant execute on function public.build_counterparty_snapshot(uuid, uuid) to authenticated;
revoke all on function public.next_sales_internal_number(uuid, public.sales_document_type, date) from public;
grant execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) to authenticated;
