-- Phase 3 — Unified counterparties (STAGING)
-- Project: rpcpdrzbcclofvjpgldb

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.counterparty_entity_type as enum ('INDIVIDUAL', 'LEGAL_ENTITY', 'OTHER');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.tax_id_type as enum (
    'CUIT', 'CUIL', 'DNI', 'PASSPORT', 'FOREIGN_TAX_ID', 'NONE'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.counterparty_role as enum ('CUSTOMER', 'SUPPLIER');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.counterparty_address_type as enum (
    'FISCAL', 'COMMERCIAL', 'DELIVERY', 'OTHER'
  );
exception when duplicate_object then null;
end $$;
-- ---------------------------------------------------------------------------
-- Tax ID normalization + validation (server-side)
-- ---------------------------------------------------------------------------

create or replace function public.normalize_counterparty_tax_id(
  p_type public.tax_id_type,
  p_value text
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_clean text;
  v_sum int;
  v_rem int;
  v_expected int;
  v_multipliers int[] := array[5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  i int;
begin
  if p_type is null or p_type = 'NONE' then
    return null;
  end if;

  if p_value is null or trim(p_value) = '' then
    return null;
  end if;

  v_clean := regexp_replace(trim(p_value), '[^0-9A-Za-z]', '', 'g');

  if p_type in ('CUIT', 'CUIL') then
    v_clean := regexp_replace(trim(p_value), '[^0-9]', '', 'g');
    if length(v_clean) <> 11 then
      raise exception 'invalid tax id: CUIT/CUIL must have 11 digits';
    end if;

    v_sum := 0;
    for i in 1..10 loop
      v_sum := v_sum + (substring(v_clean, i, 1)::int * v_multipliers[i]);
    end loop;
    v_rem := v_sum % 11;
    if v_rem = 0 then
      v_expected := 0;
    elsif v_rem = 1 then
      v_expected := 9;
    else
      v_expected := 11 - v_rem;
    end if;

    if substring(v_clean, 11, 1)::int <> v_expected then
      raise exception 'invalid tax id: check digit mismatch';
    end if;

    return v_clean;
  end if;

  if p_type = 'DNI' then
    v_clean := regexp_replace(trim(p_value), '[^0-9]', '', 'g');
    if length(v_clean) < 7 or length(v_clean) > 8 then
      raise exception 'invalid tax id: DNI must have 7-8 digits';
    end if;
    return v_clean;
  end if;

  -- PASSPORT / FOREIGN_TAX_ID — store trimmed uppercase alphanumeric
  v_clean := upper(regexp_replace(trim(p_value), '[^0-9A-Za-z]', '', 'g'));
  if length(v_clean) < 3 then
    raise exception 'invalid tax id: value too short';
  end if;
  return v_clean;
end;
$$;
-- ---------------------------------------------------------------------------
-- counterparties
-- ---------------------------------------------------------------------------

create table public.counterparties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  entity_type public.counterparty_entity_type not null default 'LEGAL_ENTITY',
  legal_name text not null,
  trade_name text,
  tax_id_type public.tax_id_type not null default 'NONE',
  tax_id text,
  tax_id_normalized text,
  external_code text,
  email text,
  phone text,
  website text,
  notes text,
  is_active boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint counterparties_legal_name_not_blank check (length(trim(legal_name)) >= 2),
  constraint counterparties_org_id_unique unique (organization_id, id)
);
create index counterparties_org_active_idx
  on public.counterparties (organization_id, is_active);
create index counterparties_org_legal_name_idx
  on public.counterparties (organization_id, legal_name);
create index counterparties_org_trade_name_idx
  on public.counterparties (organization_id, trade_name)
  where trade_name is not null;
create unique index counterparties_org_tax_id_unique
  on public.counterparties (organization_id, tax_id_normalized)
  where tax_id_normalized is not null;
create trigger counterparties_set_updated_at
before update on public.counterparties
for each row execute function public.set_updated_at();
create or replace function public.counterparties_normalize_tax_id()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.tax_id_type = 'NONE' or new.tax_id is null or trim(new.tax_id) = '' then
    new.tax_id_normalized := null;
    new.tax_id := null;
    return new;
  end if;

  new.tax_id_normalized := public.normalize_counterparty_tax_id(new.tax_id_type, new.tax_id);
  return new;
end;
$$;
create trigger counterparties_normalize_tax_id_trg
before insert or update of tax_id_type, tax_id on public.counterparties
for each row execute function public.counterparties_normalize_tax_id();
-- ---------------------------------------------------------------------------
-- counterparty_roles
-- ---------------------------------------------------------------------------

create table public.counterparty_roles (
  id uuid primary key default gen_random_uuid(),
  counterparty_id uuid not null references public.counterparties (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  role public.counterparty_role not null,
  created_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users (id),
  constraint counterparty_roles_unique unique (counterparty_id, role)
);
create index counterparty_roles_org_role_idx
  on public.counterparty_roles (organization_id, role);
create index counterparty_roles_counterparty_idx
  on public.counterparty_roles (counterparty_id);
-- ---------------------------------------------------------------------------
-- counterparty_fiscal_profiles (1:1 per counterparty)
-- ---------------------------------------------------------------------------

create table public.counterparty_fiscal_profiles (
  id uuid primary key default gen_random_uuid(),
  counterparty_id uuid not null unique references public.counterparties (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  fiscal_condition_id uuid references public.fiscal_conditions (id),
  gross_income_number text,
  fiscal_address text,
  province text,
  city text,
  postal_code text,
  country_code text not null default 'AR',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);
create trigger counterparty_fiscal_profiles_set_updated_at
before update on public.counterparty_fiscal_profiles
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- counterparty_addresses
-- ---------------------------------------------------------------------------

create table public.counterparty_addresses (
  id uuid primary key default gen_random_uuid(),
  counterparty_id uuid not null references public.counterparties (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  address_type public.counterparty_address_type not null default 'COMMERCIAL',
  label text,
  street text,
  number text,
  floor text,
  unit text,
  city text,
  province text,
  postal_code text,
  country_code text not null default 'AR',
  is_primary boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);
create index counterparty_addresses_counterparty_idx
  on public.counterparty_addresses (counterparty_id);
create trigger counterparty_addresses_set_updated_at
before update on public.counterparty_addresses
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- counterparty_contacts
-- ---------------------------------------------------------------------------

create table public.counterparty_contacts (
  id uuid primary key default gen_random_uuid(),
  counterparty_id uuid not null references public.counterparties (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  position text,
  email text,
  phone text,
  is_primary boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint counterparty_contacts_name_not_blank check (length(trim(name)) >= 2)
);
create index counterparty_contacts_counterparty_idx
  on public.counterparty_contacts (counterparty_id);
create trigger counterparty_contacts_set_updated_at
before update on public.counterparty_contacts
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- Tenant consistency on child tables
-- ---------------------------------------------------------------------------

create or replace function public.validate_counterparty_child_tenancy()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  cp_org uuid;
begin
  select organization_id into cp_org
  from public.counterparties
  where id = new.counterparty_id;

  if cp_org is null then
    raise exception 'counterparty not found';
  end if;

  if new.organization_id <> cp_org then
    raise exception 'child organization must match counterparty organization';
  end if;

  return new;
end;
$$;
create trigger counterparty_roles_validate_tenancy
before insert or update on public.counterparty_roles
for each row execute function public.validate_counterparty_child_tenancy();
create trigger counterparty_fiscal_profiles_validate_tenancy
before insert or update on public.counterparty_fiscal_profiles
for each row execute function public.validate_counterparty_child_tenancy();
create trigger counterparty_addresses_validate_tenancy
before insert or update on public.counterparty_addresses
for each row execute function public.validate_counterparty_child_tenancy();
create trigger counterparty_contacts_validate_tenancy
before insert or update on public.counterparty_contacts
for each row execute function public.validate_counterparty_child_tenancy();
-- ---------------------------------------------------------------------------
-- Soft duplicate hints (non-blocking)
-- ---------------------------------------------------------------------------

create or replace function public.find_counterparty_soft_duplicates(
  p_organization_id uuid,
  p_legal_name text,
  p_email text default null,
  p_phone text default null,
  p_exclude_id uuid default null
)
returns table (
  counterparty_id uuid,
  match_reason text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id, 'similar_name'::text
  from public.counterparties c
  where c.organization_id = p_organization_id
    and (p_exclude_id is null or c.id <> p_exclude_id)
    and lower(trim(c.legal_name)) = lower(trim(p_legal_name))
  union all
  select c.id, 'same_email'::text
  from public.counterparties c
  where c.organization_id = p_organization_id
    and (p_exclude_id is null or c.id <> p_exclude_id)
    and p_email is not null
    and trim(p_email) <> ''
    and lower(trim(c.email)) = lower(trim(p_email))
  union all
  select c.id, 'same_phone'::text
  from public.counterparties c
  where c.organization_id = p_organization_id
    and (p_exclude_id is null or c.id <> p_exclude_id)
    and p_phone is not null
    and trim(p_phone) <> ''
    and regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g')
      = regexp_replace(p_phone, '[^0-9]', '', 'g');
$$;
revoke all on function public.find_counterparty_soft_duplicates(uuid, text, text, text, uuid) from public;
grant execute on function public.find_counterparty_soft_duplicates(uuid, text, text, text, uuid) to authenticated;
