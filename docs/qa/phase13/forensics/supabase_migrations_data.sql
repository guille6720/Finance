SET session_replication_role = replica;

--
-- PostgreSQL database dump
--

-- \restrict FnbKyiUf9sc9f5QvemEtdw8cOr8jB3bMhNxpmVmHoPJhbyT63pRsN7a9VOCXLyo

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: supabase_migrations; Owner: postgres
--

INSERT INTO "supabase_migrations"."schema_migrations" ("version", "statements", "name") VALUES
	('20260329000001', '{"-- Phase 1 foundation schema
-- Neutral technical names only. No brand-specific identifiers.
-- Staging and Production MUST use separate Supabase projects.

create extension if not exists \"pgcrypto\"","-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.organization_status as enum (
  ''draft'',
  ''active'',
  ''suspended'',
  ''closed''
)","create type public.member_role as enum (
  ''owner'',
  ''admin'',
  ''manager'',
  ''operator'',
  ''accountant'',
  ''viewer''
)","create type public.member_status as enum (
  ''invited'',
  ''active'',
  ''disabled''
)","create type public.feature_status as enum (
  ''enabled'',
  ''disabled'',
  ''restricted''
)","create type public.business_type as enum (
  ''kiosk'',
  ''retail'',
  ''professional'',
  ''services'',
  ''accounting_firm'',
  ''healthcare'',
  ''medical_legal'',
  ''industry'',
  ''other''
)","create type public.ux_mode as enum (
  ''business'',
  ''accountant''
)","-- ---------------------------------------------------------------------------
-- Helper: updated_at trigger
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone(''utc'', now());
  return new;
end;
$$","-- ---------------------------------------------------------------------------
-- profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  full_name text not null default '''',
  avatar_url text,
  preferred_ux_mode public.ux_mode not null default ''business'',
  locale text not null default ''es-AR'',
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now())
)","create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at()","create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    coalesce(new.email, ''''),
    coalesce(new.raw_user_meta_data ->> ''full_name'', '''')
  )
  on conflict (id) do nothing;
  return new;
end;
$$","create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user()","-- ---------------------------------------------------------------------------
-- organizations
-- ---------------------------------------------------------------------------

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null,
  commercial_name text,
  cuit text,
  country text not null default ''AR'',
  province text,
  city text,
  timezone text not null default ''America/Argentina/Buenos_Aires'',
  base_currency text not null default ''ARS'',
  status public.organization_status not null default ''draft'',
  onboarding_completed_at timestamptz,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint organizations_cuit_format check (
    cuit is null or cuit ~ ''^\\d{11}$''
  )
)","create index organizations_status_idx on public.organizations (status)","create index organizations_cuit_idx on public.organizations (cuit)","create trigger organizations_set_updated_at
before update on public.organizations
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- organization_members
-- ---------------------------------------------------------------------------

create table public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role public.member_role not null default ''viewer'',
  status public.member_status not null default ''active'',
  invited_by uuid references public.profiles (id),
  invited_at timestamptz,
  joined_at timestamptz default timezone(''utc'', now()),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (organization_id, user_id)
)","create index organization_members_user_idx on public.organization_members (user_id)","create index organization_members_org_idx on public.organization_members (organization_id)","create trigger organization_members_set_updated_at
before update on public.organization_members
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- branches
-- ---------------------------------------------------------------------------

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  code text,
  is_main boolean not null default false,
  address text,
  city text,
  province text,
  active boolean not null default true,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now())
)","create index branches_org_idx on public.branches (organization_id)","create trigger branches_set_updated_at
before update on public.branches
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- fiscal_conditions (catalog)
-- ---------------------------------------------------------------------------

create table public.fiscal_conditions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_business text not null,
  name_accountant text not null,
  description text,
  active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default timezone(''utc'', now())
)","-- ---------------------------------------------------------------------------
-- fiscal_profiles
-- ---------------------------------------------------------------------------

create table public.fiscal_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null unique references public.organizations (id) on delete cascade,
  fiscal_condition_id uuid references public.fiscal_conditions (id),
  fiscal_address text,
  province text,
  city text,
  gross_income_number text,
  activity_start_date date,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now())
)","create trigger fiscal_profiles_set_updated_at
before update on public.fiscal_profiles
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- business_profiles (onboarding answers)
-- ---------------------------------------------------------------------------

create table public.business_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null unique references public.organizations (id) on delete cascade,
  business_type public.business_type not null default ''other'',
  business_type_other text,
  sells_products boolean not null default false,
  sells_services boolean not null default false,
  manages_inventory boolean not null default false,
  has_employees boolean not null default false,
  has_multiple_branches boolean not null default false,
  needs_projects boolean not null default false,
  needs_cost_centers boolean not null default false,
  invoices_customers boolean not null default false,
  works_with_suppliers boolean not null default false,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now())
)","create trigger business_profiles_set_updated_at
before update on public.business_profiles
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- accounting_periods (structure only; no posting logic)
-- ---------------------------------------------------------------------------

create table public.accounting_periods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  starts_on date not null,
  ends_on date not null,
  is_closed boolean not null default false,
  closed_at timestamptz,
  closed_by uuid references public.profiles (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint accounting_periods_range check (ends_on >= starts_on)
)","create index accounting_periods_org_idx on public.accounting_periods (organization_id)","create trigger accounting_periods_set_updated_at
before update on public.accounting_periods
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- cost_centers (structure only)
-- ---------------------------------------------------------------------------

create table public.cost_centers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  code text not null,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (organization_id, code)
)","create index cost_centers_org_idx on public.cost_centers (organization_id)","create trigger cost_centers_set_updated_at
before update on public.cost_centers
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- feature_catalog / organization_features
-- ---------------------------------------------------------------------------

create table public.feature_catalog (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  category text not null default ''general'',
  default_status public.feature_status not null default ''disabled'',
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default timezone(''utc'', now())
)","create table public.organization_features (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  status public.feature_status not null default ''disabled'',
  enabled_at timestamptz,
  metadata jsonb not null default ''{}''::jsonb,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (organization_id, feature_id)
)","create index organization_features_org_idx on public.organization_features (organization_id)","create trigger organization_features_set_updated_at
before update on public.organization_features
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- app_settings / organization_settings
-- ---------------------------------------------------------------------------

create table public.app_settings (
  key text primary key,
  value jsonb not null default ''{}''::jsonb,
  description text,
  updated_at timestamptz not null default timezone(''utc'', now())
)","create table public.organization_settings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  key text not null,
  value jsonb not null default ''{}''::jsonb,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (organization_id, key)
)","create trigger organization_settings_set_updated_at
before update on public.organization_settings
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- audit_events (append-only)
-- ---------------------------------------------------------------------------

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations (id) on delete set null,
  actor_user_id uuid references public.profiles (id) on delete set null,
  event_type text not null,
  entity_type text not null,
  entity_id text,
  action text not null,
  metadata jsonb not null default ''{}''::jsonb,
  ip_address text,
  user_agent text,
  created_at timestamptz not null default timezone(''utc'', now())
)","create index audit_events_org_created_idx on public.audit_events (organization_id, created_at desc)","create index audit_events_entity_idx on public.audit_events (entity_type, entity_id)","create index audit_events_type_idx on public.audit_events (event_type)","create or replace function public.prevent_audit_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception ''audit_events is append-only'';
end;
$$","create trigger audit_events_no_update
before update on public.audit_events
for each row execute function public.prevent_audit_mutation()","create trigger audit_events_no_delete
before delete on public.audit_events
for each row execute function public.prevent_audit_mutation()","-- ---------------------------------------------------------------------------
-- Membership helpers (SECURITY DEFINER, bypass RLS carefully)
-- ---------------------------------------------------------------------------

create or replace function public.is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organization_members m
    where m.organization_id = p_org_id
      and m.user_id = auth.uid()
      and m.status = ''active''
  );
$$","create or replace function public.has_org_role(p_org_id uuid, p_roles public.member_role[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organization_members m
    where m.organization_id = p_org_id
      and m.user_id = auth.uid()
      and m.status = ''active''
      and m.role = any (p_roles)
  );
$$","create or replace function public.can_mutate_org(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_org_role(
    p_org_id,
    array[''owner'', ''admin'', ''manager'']::public.member_role[]
  );
$$","revoke all on function public.is_org_member(uuid) from public","revoke all on function public.has_org_role(uuid, public.member_role[]) from public","revoke all on function public.can_mutate_org(uuid) from public","grant execute on function public.is_org_member(uuid) to authenticated","grant execute on function public.has_org_role(uuid, public.member_role[]) to authenticated","grant execute on function public.can_mutate_org(uuid) to authenticated","-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security","alter table public.organizations enable row level security","alter table public.organization_members enable row level security","alter table public.branches enable row level security","alter table public.fiscal_conditions enable row level security","alter table public.fiscal_profiles enable row level security","alter table public.business_profiles enable row level security","alter table public.accounting_periods enable row level security","alter table public.cost_centers enable row level security","alter table public.feature_catalog enable row level security","alter table public.organization_features enable row level security","alter table public.app_settings enable row level security","alter table public.organization_settings enable row level security","alter table public.audit_events enable row level security","-- profiles
create policy profiles_select_own
  on public.profiles for select
  to authenticated
  using (id = auth.uid())","create policy profiles_update_own
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid())","create policy profiles_select_same_org
  on public.profiles for select
  to authenticated
  using (
    exists (
      select 1
      from public.organization_members me
      join public.organization_members other
        on other.organization_id = me.organization_id
      where me.user_id = auth.uid()
        and me.status = ''active''
        and other.user_id = profiles.id
        and other.status = ''active''
    )
  )","-- organizations
create policy organizations_select_member
  on public.organizations for select
  to authenticated
  using (public.is_org_member(id))","create policy organizations_insert_authenticated
  on public.organizations for insert
  to authenticated
  with check (auth.uid() is not null and created_by = auth.uid())","create policy organizations_update_admins
  on public.organizations for update
  to authenticated
  using (public.can_mutate_org(id))
  with check (public.can_mutate_org(id))","-- organization_members
create policy members_select_same_org
  on public.organization_members for select
  to authenticated
  using (public.is_org_member(organization_id))","create policy members_insert_owner_bootstrap_or_admin
  on public.organization_members for insert
  to authenticated
  with check (
    (
      user_id = auth.uid()
      and role = ''owner''
      and exists (
        select 1 from public.organizations o
        where o.id = organization_id
          and o.created_by = auth.uid()
      )
    )
    or public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )","create policy members_update_admins
  on public.organization_members for update
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )","-- Generic org-scoped tables
create policy branches_select on public.branches for select to authenticated
  using (public.is_org_member(organization_id))","create policy branches_insert on public.branches for insert to authenticated
  with check (public.can_mutate_org(organization_id))","create policy branches_update on public.branches for update to authenticated
  using (public.can_mutate_org(organization_id))
  with check (public.can_mutate_org(organization_id))","create policy fiscal_profiles_select on public.fiscal_profiles for select to authenticated
  using (public.is_org_member(organization_id))","create policy fiscal_profiles_insert on public.fiscal_profiles for insert to authenticated
  with check (public.can_mutate_org(organization_id))","create policy fiscal_profiles_update on public.fiscal_profiles for update to authenticated
  using (public.can_mutate_org(organization_id))
  with check (public.can_mutate_org(organization_id))","create policy business_profiles_select on public.business_profiles for select to authenticated
  using (public.is_org_member(organization_id))","create policy business_profiles_insert on public.business_profiles for insert to authenticated
  with check (public.can_mutate_org(organization_id))","create policy business_profiles_update on public.business_profiles for update to authenticated
  using (public.can_mutate_org(organization_id))
  with check (public.can_mutate_org(organization_id))","create policy accounting_periods_select on public.accounting_periods for select to authenticated
  using (public.is_org_member(organization_id))","create policy accounting_periods_mutate on public.accounting_periods for all to authenticated
  using (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'', ''accountant'']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'', ''accountant'']::public.member_role[]
    )
  )","create policy cost_centers_select on public.cost_centers for select to authenticated
  using (public.is_org_member(organization_id))","create policy cost_centers_mutate on public.cost_centers for all to authenticated
  using (public.can_mutate_org(organization_id))
  with check (public.can_mutate_org(organization_id))","create policy organization_features_select on public.organization_features for select to authenticated
  using (public.is_org_member(organization_id))","create policy organization_features_mutate on public.organization_features for all to authenticated
  using (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )","create policy organization_settings_select on public.organization_settings for select to authenticated
  using (public.is_org_member(organization_id))","create policy organization_settings_mutate on public.organization_settings for all to authenticated
  using (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )","-- Catalogs (read for authenticated)
create policy fiscal_conditions_select on public.fiscal_conditions for select to authenticated
  using (active = true)","create policy feature_catalog_select on public.feature_catalog for select to authenticated
  using (active = true)","-- app_settings: no client writes; authenticated read only of non-sensitive keys if needed later
create policy app_settings_select_authenticated on public.app_settings for select to authenticated
  using (true)","-- audit_events: members can read own org; inserts via authenticated member or service role
create policy audit_events_select on public.audit_events for select to authenticated
  using (
    organization_id is not null
    and public.is_org_member(organization_id)
  )","create policy audit_events_insert on public.audit_events for insert to authenticated
  with check (
    actor_user_id = auth.uid()
    and (
      organization_id is null
      or public.is_org_member(organization_id)
    )
  )","-- No update/delete policies for audit_events → blocked for clients

-- ---------------------------------------------------------------------------
-- Seed catalogs
-- ---------------------------------------------------------------------------

insert into public.fiscal_conditions (code, name_business, name_accountant, description, sort_order) values
  (''monotributo'', ''Monotributo'', ''Monotributista'', ''Régimen simplificado'', 1),
  (''responsable_inscripto'', ''Responsable inscripto'', ''Responsable Inscripto'', ''IVA responsable inscripto'', 2),
  (''exento'', ''Exento de IVA'', ''Exento'', ''Exento en IVA'', 3),
  (''consumidor_final'', ''Consumidor final'', ''Consumidor Final'', ''Sin actividad gravada formal'', 4)","insert into public.feature_catalog (code, name, description, category, default_status, sort_order) values
  (''dashboard'', ''Panel'', ''Panel principal de la empresa'', ''core'', ''enabled'', 10),
  (''sales'', ''Ventas'', ''Registro de ventas y cobros'', ''gestion'', ''disabled'', 20),
  (''purchases'', ''Compras'', ''Compras y gastos'', ''gestion'', ''disabled'', 30),
  (''customers'', ''Clientes'', ''Agenda de clientes'', ''gestion'', ''disabled'', 40),
  (''suppliers'', ''Proveedores'', ''Agenda de proveedores'', ''gestion'', ''disabled'', 50),
  (''cash'', ''Caja'', ''Caja diaria'', ''finanzas'', ''disabled'', 60),
  (''banks'', ''Bancos'', ''Cuentas bancarias'', ''finanzas'', ''disabled'', 70),
  (''inventory'', ''Inventario'', ''Stock de productos'', ''operaciones'', ''disabled'', 80),
  (''pos'', ''Punto de venta'', ''POS / mostrador'', ''operaciones'', ''disabled'', 90),
  (''accounting'', ''Contabilidad'', ''Contabilidad avanzada'', ''contabilidad'', ''disabled'', 100),
  (''taxes'', ''Impuestos'', ''Impuestos y liquidaciones'', ''contabilidad'', ''disabled'', 110),
  (''payroll'', ''Sueldos'', ''Liquidación de sueldos'', ''rrhh'', ''disabled'', 120),
  (''projects'', ''Proyectos'', ''Gestión por proyectos'', ''operaciones'', ''disabled'', 130),
  (''assets'', ''Bienes de uso'', ''Activos fijos'', ''contabilidad'', ''disabled'', 140),
  (''reports'', ''Reportes'', ''Reportes de gestión'', ''reportes'', ''disabled'', 150),
  (''medical_legal'', ''Médico-legal'', ''Módulo médico-legal (dominio separado)'', ''vertical'', ''restricted'', 160)","insert into public.app_settings (key, value, description) values
  (''platform.phase'', ''\"1\"''::jsonb, ''Current platform phase''),
  (''platform.accounting_core_enabled'', ''false''::jsonb, ''Accounting posting engine not enabled in Phase 1'')"}', 'phase1_foundation'),
	('20260329180000', '{"-- Phase 1 security hardening (STAGING)
-- Project: rpcpdrzbcclofvjpgldb
-- Does not rewrite 20260329000001; additive hardening only.
--
-- Findings addressed:
-- 1) function_search_path_mutable on set_updated_at / prevent_audit_mutation
-- 2) anon EXECUTE on SECURITY DEFINER helpers (default PUBLIC/anon grants)
-- 3) handle_new_user exposed as callable RPC
--
-- Design notes:
-- * RLS helpers remain SECURITY DEFINER to avoid recursive RLS on
--   organization_members while evaluating membership/role checks.
-- * Identity source is only auth.uid() — no trusted user_id argument.
-- * authenticated EXECUTE on helpers is required so RLS policy expressions
--   can invoke them at runtime. Direct PostgREST RPC is possible but safe
--   because helpers only return boolean based on auth.uid() + org_id.

-- ---------------------------------------------------------------------------
-- Trigger helpers: pin search_path, revoke API exposure
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  new.updated_at = timezone(''utc'', now());
  return new;
end;
$$","create or replace function public.prevent_audit_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  raise exception ''audit_events is append-only'';
end;
$$","revoke all on function public.set_updated_at() from public","revoke all on function public.set_updated_at() from anon","revoke all on function public.set_updated_at() from authenticated","revoke all on function public.prevent_audit_mutation() from public","revoke all on function public.prevent_audit_mutation() from anon","revoke all on function public.prevent_audit_mutation() from authenticated","-- ---------------------------------------------------------------------------
-- Auth trigger: keep SECURITY DEFINER, pin search_path, hide from RPC
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''''
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    coalesce(new.email, ''''),
    coalesce(new.raw_user_meta_data ->> ''full_name'', '''')
  )
  on conflict (id) do nothing;
  return new;
end;
$$","revoke all on function public.handle_new_user() from public","revoke all on function public.handle_new_user() from anon","revoke all on function public.handle_new_user() from authenticated","-- Trigger owner (postgres/supabase_admin) retains EXECUTE via ownership.

-- ---------------------------------------------------------------------------
-- RLS helpers: SECURITY DEFINER + empty search_path + no anon EXECUTE
-- ---------------------------------------------------------------------------

create or replace function public.is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''''
as $$
  select exists (
    select 1
    from public.organization_members m
    where m.organization_id = p_org_id
      and m.user_id = (select auth.uid())
      and m.status = ''active''
  );
$$","create or replace function public.has_org_role(
  p_org_id uuid,
  p_roles public.member_role[]
)
returns boolean
language sql
stable
security definer
set search_path = ''''
as $$
  select exists (
    select 1
    from public.organization_members m
    where m.organization_id = p_org_id
      and m.user_id = (select auth.uid())
      and m.status = ''active''
      and m.role = any (p_roles)
  );
$$","create or replace function public.can_mutate_org(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''''
as $$
  select public.has_org_role(
    p_org_id,
    array[''owner'', ''admin'', ''manager'']::public.member_role[]
  );
$$","revoke all on function public.is_org_member(uuid) from public","revoke all on function public.is_org_member(uuid) from anon","revoke all on function public.is_org_member(uuid) from authenticated","revoke all on function public.has_org_role(uuid, public.member_role[]) from public","revoke all on function public.has_org_role(uuid, public.member_role[]) from anon","revoke all on function public.has_org_role(uuid, public.member_role[]) from authenticated","revoke all on function public.can_mutate_org(uuid) from public","revoke all on function public.can_mutate_org(uuid) from anon","revoke all on function public.can_mutate_org(uuid) from authenticated","-- Required for RLS policy evaluation under the authenticated role.
grant execute on function public.is_org_member(uuid) to authenticated","grant execute on function public.has_org_role(uuid, public.member_role[]) to authenticated","grant execute on function public.can_mutate_org(uuid) to authenticated","-- Explicitly ensure anon cannot execute any of the above.
revoke execute on function public.is_org_member(uuid) from anon","revoke execute on function public.has_org_role(uuid, public.member_role[]) from anon","revoke execute on function public.can_mutate_org(uuid) from anon","revoke execute on function public.handle_new_user() from anon","revoke execute on function public.set_updated_at() from anon","revoke execute on function public.prevent_audit_mutation() from anon"}', 'phase1_security_hardening'),
	('20260329181000', '{"-- Phase 1: allow organization bootstrap without widening anon access.
--
-- INSERT ... RETURNING requires the new row to satisfy SELECT policies.
-- organizations_select_member previously required is_org_member(id), but
-- membership is created AFTER the organization row. That blocked onboarding.
--
-- Fix: creators may SELECT their own organization via created_by = auth.uid().
-- Membership remains the primary tenant gate for everyone else.

drop policy if exists organizations_select_member on public.organizations","create policy organizations_select_member
  on public.organizations
  for select
  to authenticated
  using (
    public.is_org_member(id)
    or created_by = (select auth.uid())
  )"}', 'phase1_org_bootstrap_select'),
	('20260329190000', '{"-- Phase 1 final performance hardening (STAGING only)
-- Project: rpcpdrzbcclofvjpgldb
-- Additive migration. Does not rewrite earlier migrations.
--
-- 1) auth_rls_initplan: wrap auth.uid() as (select auth.uid())
-- 2) multiple_permissive_policies: narrow FOR ALL mutate policies so they
--    do not also provide SELECT (SELECT stays on dedicated policies)
--    and consolidate profiles SELECT into one clear OR policy
-- 3) unindexed_foreign_keys: add covering indexes
--
-- Authorization semantics intentionally unchanged for tenant isolation.

-- ---------------------------------------------------------------------------
-- Foreign-key covering indexes
-- ---------------------------------------------------------------------------

create index if not exists accounting_periods_closed_by_idx
  on public.accounting_periods (closed_by)","create index if not exists audit_events_actor_user_id_idx
  on public.audit_events (actor_user_id)","create index if not exists fiscal_profiles_fiscal_condition_id_idx
  on public.fiscal_profiles (fiscal_condition_id)","create index if not exists organization_features_feature_id_idx
  on public.organization_features (feature_id)","create index if not exists organization_members_invited_by_idx
  on public.organization_members (invited_by)","create index if not exists organizations_created_by_idx
  on public.organizations (created_by)","-- ---------------------------------------------------------------------------
-- profiles: single SELECT policy + initplan-safe auth.uid()
-- ---------------------------------------------------------------------------

drop policy if exists profiles_select_own on public.profiles","drop policy if exists profiles_select_same_org on public.profiles","drop policy if exists profiles_update_own on public.profiles","create policy profiles_select_visible
  on public.profiles
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1
      from public.organization_members me
      join public.organization_members other
        on other.organization_id = me.organization_id
      where me.user_id = (select auth.uid())
        and me.status = ''active''
        and other.user_id = profiles.id
        and other.status = ''active''
    )
  )","create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()))","-- ---------------------------------------------------------------------------
-- organizations insert: initplan-safe auth.uid()
-- ---------------------------------------------------------------------------

drop policy if exists organizations_insert_authenticated on public.organizations","create policy organizations_insert_authenticated
  on public.organizations
  for insert
  to authenticated
  with check (
    (select auth.uid()) is not null
    and created_by = (select auth.uid())
  )","-- ---------------------------------------------------------------------------
-- organization_members insert: initplan-safe auth.uid()
-- ---------------------------------------------------------------------------

drop policy if exists members_insert_owner_bootstrap_or_admin
  on public.organization_members","create policy members_insert_owner_bootstrap_or_admin
  on public.organization_members
  for insert
  to authenticated
  with check (
    (
      user_id = (select auth.uid())
      and role = ''owner''
      and exists (
        select 1
        from public.organizations o
        where o.id = organization_id
          and o.created_by = (select auth.uid())
      )
    )
    or public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )","-- ---------------------------------------------------------------------------
-- audit_events insert: initplan-safe auth.uid()
-- ---------------------------------------------------------------------------

drop policy if exists audit_events_insert on public.audit_events","create policy audit_events_insert
  on public.audit_events
  for insert
  to authenticated
  with check (
    actor_user_id = (select auth.uid())
    and (
      organization_id is null
      or public.is_org_member(organization_id)
    )
  )","-- ---------------------------------------------------------------------------
-- Narrow FOR ALL mutate policies → write-only (no overlapping SELECT)
-- Keeps dedicated SELECT policies as the single SELECT path.
-- ---------------------------------------------------------------------------

-- accounting_periods
drop policy if exists accounting_periods_mutate on public.accounting_periods","create policy accounting_periods_insert
  on public.accounting_periods
  for insert
  to authenticated
  with check (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'', ''accountant'']::public.member_role[]
    )
  )","create policy accounting_periods_update
  on public.accounting_periods
  for update
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'', ''accountant'']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'', ''accountant'']::public.member_role[]
    )
  )","create policy accounting_periods_delete
  on public.accounting_periods
  for delete
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'', ''accountant'']::public.member_role[]
    )
  )","-- cost_centers
drop policy if exists cost_centers_mutate on public.cost_centers","create policy cost_centers_insert
  on public.cost_centers
  for insert
  to authenticated
  with check (public.can_mutate_org(organization_id))","create policy cost_centers_update
  on public.cost_centers
  for update
  to authenticated
  using (public.can_mutate_org(organization_id))
  with check (public.can_mutate_org(organization_id))","create policy cost_centers_delete
  on public.cost_centers
  for delete
  to authenticated
  using (public.can_mutate_org(organization_id))","-- organization_features
drop policy if exists organization_features_mutate on public.organization_features","create policy organization_features_insert
  on public.organization_features
  for insert
  to authenticated
  with check (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )","create policy organization_features_update
  on public.organization_features
  for update
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )","create policy organization_features_delete
  on public.organization_features
  for delete
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )","-- organization_settings
drop policy if exists organization_settings_mutate on public.organization_settings","create policy organization_settings_insert
  on public.organization_settings
  for insert
  to authenticated
  with check (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )","create policy organization_settings_update
  on public.organization_settings
  for update
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )","create policy organization_settings_delete
  on public.organization_settings
  for delete
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'']::public.member_role[]
    )
  )"}', 'phase1_performance_hardening'),
	('20260329200000', '{"-- Phase 2 — Accounting core (STAGING)
-- Project: rpcpdrzbcclofvjpgldb
-- Additive only — does not rewrite Phase 1 migrations.
-- Money: numeric(19,4) only. Never float/double.

create extension if not exists btree_gist","-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.account_type as enum (
    ''ASSET'', ''LIABILITY'', ''EQUITY'', ''REVENUE'', ''EXPENSE'', ''MEMORANDUM''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.normal_balance as enum (''DEBIT'', ''CREDIT'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.fiscal_year_status as enum (''OPEN'', ''CLOSED'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.period_status as enum (''OPEN'', ''CLOSED'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.journal_entry_status as enum (''DRAFT'', ''POSTED'', ''REVERSED'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.journal_source_type as enum (
    ''MANUAL'', ''SALE'', ''PURCHASE'', ''PAYMENT'', ''COLLECTION'',
    ''BANK'', ''INVENTORY'', ''PAYROLL'', ''TAX'', ''SYSTEM''
  );
exception when duplicate_object then null;
end $$","-- ---------------------------------------------------------------------------
-- accounting_fiscal_years
-- ---------------------------------------------------------------------------

create table if not exists public.accounting_fiscal_years (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  start_date date not null,
  end_date date not null,
  status public.fiscal_year_status not null default ''OPEN'',
  closed_at timestamptz,
  closed_by uuid references public.profiles (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint accounting_fiscal_years_range check (start_date < end_date),
  constraint accounting_fiscal_years_name_len check (char_length(name) between 1 and 120)
)","create unique index if not exists accounting_fiscal_years_org_name_uidx
  on public.accounting_fiscal_years (organization_id, name)","create index if not exists accounting_fiscal_years_org_idx
  on public.accounting_fiscal_years (organization_id)","create index if not exists accounting_fiscal_years_org_dates_idx
  on public.accounting_fiscal_years (organization_id, start_date, end_date)","-- Prevent overlapping fiscal years per organization
alter table public.accounting_fiscal_years
  drop constraint if exists accounting_fiscal_years_no_overlap","alter table public.accounting_fiscal_years
  add constraint accounting_fiscal_years_no_overlap
  exclude using gist (
    organization_id with =,
    daterange(start_date, end_date, ''[]'') with &&
  )","create trigger accounting_fiscal_years_set_updated_at
before update on public.accounting_fiscal_years
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- Adapt accounting_periods
-- ---------------------------------------------------------------------------

alter table public.accounting_periods
  add column if not exists fiscal_year_id uuid references public.accounting_fiscal_years (id)","alter table public.accounting_periods
  add column if not exists status public.period_status","alter table public.accounting_periods
  add column if not exists reopened_at timestamptz","alter table public.accounting_periods
  add column if not exists reopened_by uuid references public.profiles (id)","alter table public.accounting_periods
  add column if not exists reopen_reason text","-- Backfill: one fiscal year per existing period, then link (idempotent)
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
      case when r.is_closed then ''CLOSED''::public.fiscal_year_status else ''OPEN''::public.fiscal_year_status end
    )
    returning id into fy_id;

    update public.accounting_periods
    set
      fiscal_year_id = fy_id,
      status = case when r.is_closed then ''CLOSED''::public.period_status else ''OPEN''::public.period_status end
    where id = r.id;
  end loop;

  update public.accounting_periods
  set status = case when is_closed then ''CLOSED''::public.period_status else ''OPEN''::public.period_status end
  where status is null;
end $$","-- Only enforce NOT NULL if backfill completed
do $$
begin
  if exists (select 1 from public.accounting_periods where fiscal_year_id is null) then
    raise exception ''accounting_periods backfill incomplete'';
  end if;
end $$","alter table public.accounting_periods
  alter column fiscal_year_id set not null","alter table public.accounting_periods
  alter column status set not null","alter table public.accounting_periods
  alter column status set default ''OPEN''","create index if not exists accounting_periods_fy_idx
  on public.accounting_periods (fiscal_year_id)","create index if not exists accounting_periods_org_status_idx
  on public.accounting_periods (organization_id, status)","alter table public.accounting_periods
  drop constraint if exists accounting_periods_no_overlap","alter table public.accounting_periods
  add constraint accounting_periods_no_overlap
  exclude using gist (
    organization_id with =,
    daterange(starts_on, ends_on, ''[]'') with &&
  )","-- Keep is_closed synchronized with status
create or replace function public.sync_period_closed_flag()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  new.is_closed := (new.status = ''CLOSED'');
  if new.status = ''CLOSED'' and old.status is distinct from ''CLOSED'' then
    new.closed_at := coalesce(new.closed_at, timezone(''utc'', now()));
  end if;
  if new.status = ''OPEN'' and old.status = ''CLOSED'' then
    new.reopened_at := coalesce(new.reopened_at, timezone(''utc'', now()));
  end if;
  return new;
end;
$$","drop trigger if exists accounting_periods_sync_closed on public.accounting_periods","create trigger accounting_periods_sync_closed
before insert or update of status on public.accounting_periods
for each row execute function public.sync_period_closed_flag()","-- ---------------------------------------------------------------------------
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
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint accounts_code_len check (char_length(code) between 1 and 32),
  constraint accounts_name_len check (char_length(name) between 1 and 200),
  unique (organization_id, code)
)","create index if not exists accounts_org_idx on public.accounts (organization_id)","create index if not exists accounts_org_parent_idx on public.accounts (organization_id, parent_id)","create index if not exists accounts_org_type_idx on public.accounts (organization_id, account_type)","create index if not exists accounts_org_active_idx on public.accounts (organization_id, is_active)","create trigger accounts_set_updated_at
before update on public.accounts
for each row execute function public.set_updated_at()","-- Parent same org + no cycles + level
create or replace function public.validate_account_hierarchy()
returns trigger
language plpgsql
security invoker
set search_path = ''''
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
    raise exception ''account cannot be its own parent'';
  end if;

  select organization_id, level into parent_org, parent_level
  from public.accounts where id = new.parent_id;

  if parent_org is null then
    raise exception ''parent account not found'';
  end if;
  if parent_org <> new.organization_id then
    raise exception ''parent account must belong to same organization'';
  end if;

  new.level := parent_level + 1;

  walk := new.parent_id;
  while walk is not null loop
    hops := hops + 1;
    if hops > 20 then
      raise exception ''account hierarchy too deep or cyclic'';
    end if;
    if walk = new.id then
      raise exception ''circular account hierarchy is not allowed'';
    end if;
    select parent_id into walk from public.accounts where id = walk;
  end loop;

  return new;
end;
$$","drop trigger if exists accounts_validate_hierarchy on public.accounts","create trigger accounts_validate_hierarchy
before insert or update of parent_id, organization_id on public.accounts
for each row execute function public.validate_account_hierarchy()","-- Prevent hard-delete when account has posted lines
create or replace function public.prevent_account_delete_with_movements()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if exists (
    select 1
    from public.journal_entry_lines jel
    join public.journal_entries je on je.id = jel.journal_entry_id
    where jel.account_id = old.id
      and je.status in (''POSTED'', ''REVERSED'')
  ) then
    raise exception ''cannot delete account with posted movements; deactivate instead'';
  end if;
  return old;
end;
$$","-- ---------------------------------------------------------------------------
-- accounting_sequences (concurrency-safe entry numbers per org + fiscal year)
-- ---------------------------------------------------------------------------

create table if not exists public.accounting_sequences (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  fiscal_year_id uuid not null references public.accounting_fiscal_years (id) on delete cascade,
  last_value bigint not null default 0 check (last_value >= 0),
  updated_at timestamptz not null default timezone(''utc'', now()),
  primary key (organization_id, fiscal_year_id)
)","-- ---------------------------------------------------------------------------
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
  status public.journal_entry_status not null default ''DRAFT'',
  source_type public.journal_source_type not null default ''MANUAL'',
  source_id uuid,
  external_reference text,
  reversal_of_entry_id uuid references public.journal_entries (id),
  reversed_by_entry_id uuid references public.journal_entries (id),
  reversal_reason text,
  created_by uuid not null references public.profiles (id),
  posted_by uuid references public.profiles (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  posted_at timestamptz,
  constraint journal_entries_description_len check (char_length(description) between 1 and 500),
  constraint journal_entries_posted_shape check (
    (status = ''DRAFT'' and entry_number is null and posted_at is null and posted_by is null)
    or (status in (''POSTED'', ''REVERSED'') and entry_number is not null and posted_at is not null and posted_by is not null)
  ),
  constraint journal_entries_reversal_reason check (
    reversal_of_entry_id is null or (reversal_reason is not null and char_length(reversal_reason) >= 3)
  )
)","create unique index if not exists journal_entries_org_fy_number_uidx
  on public.journal_entries (organization_id, fiscal_year_id, entry_number)
  where entry_number is not null","create index if not exists journal_entries_org_date_idx
  on public.journal_entries (organization_id, entry_date)","create index if not exists journal_entries_org_status_idx
  on public.journal_entries (organization_id, status)","create index if not exists journal_entries_period_idx
  on public.journal_entries (period_id)","create index if not exists journal_entries_source_idx
  on public.journal_entries (organization_id, source_type, source_id)","create index if not exists journal_entries_reversal_of_idx
  on public.journal_entries (reversal_of_entry_id)","create trigger journal_entries_set_updated_at
before update on public.journal_entries
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
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
  metadata jsonb not null default ''{}''::jsonb,
  created_at timestamptz not null default timezone(''utc'', now()),
  constraint journal_entry_lines_debit_nonneg check (debit >= 0),
  constraint journal_entry_lines_credit_nonneg check (credit >= 0),
  constraint journal_entry_lines_one_side check (
    (debit > 0 and credit = 0) or (credit > 0 and debit = 0)
  ),
  unique (journal_entry_id, line_number)
)","create index if not exists journal_entry_lines_entry_idx
  on public.journal_entry_lines (journal_entry_id)","create index if not exists journal_entry_lines_account_idx
  on public.journal_entry_lines (account_id)","create index if not exists journal_entry_lines_org_idx
  on public.journal_entry_lines (organization_id)","create index if not exists journal_entry_lines_cost_center_idx
  on public.journal_entry_lines (cost_center_id)","-- Now attach account delete guard (depends on journal_entry_lines)
drop trigger if exists accounts_prevent_delete_movements on public.accounts","create trigger accounts_prevent_delete_movements
before delete on public.accounts
for each row execute function public.prevent_account_delete_with_movements()","-- Line tenant / account / cost center consistency
create or replace function public.validate_journal_line_tenancy()
returns trigger
language plpgsql
security invoker
set search_path = ''''
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
    raise exception ''journal entry not found'';
  end if;
  if entry_status <> ''DRAFT'' then
    raise exception ''cannot modify lines of a non-draft journal entry'';
  end if;
  if new.organization_id <> entry_org then
    raise exception ''line organization must match journal entry'';
  end if;

  select organization_id, is_active, is_postable
    into acct_org, acct_active, acct_postable
  from public.accounts where id = new.account_id;

  if acct_org is null then
    raise exception ''account not found'';
  end if;
  if acct_org <> new.organization_id then
    raise exception ''account must belong to same organization'';
  end if;
  if not acct_active then
    if current_setting(''accounting.engine_write'', true) is distinct from ''1'' then
      raise exception ''inactive accounts cannot receive journal lines'';
    end if;
  end if;
  if not acct_postable then
    if current_setting(''accounting.engine_write'', true) is distinct from ''1'' then
      raise exception ''non-postable accounts cannot receive journal lines'';
    end if;
  end if;

  if new.cost_center_id is not null then
    select organization_id, active into cc_org, cc_active
    from public.cost_centers where id = new.cost_center_id;
    if cc_org is null then
      raise exception ''cost center not found'';
    end if;
    if cc_org <> new.organization_id then
      raise exception ''cost center must belong to same organization'';
    end if;
    if not cc_active then
      raise exception ''inactive cost centers cannot receive journal lines'';
    end if;
  end if;

  return new;
end;
$$","drop trigger if exists journal_entry_lines_validate_tenancy on public.journal_entry_lines","create trigger journal_entry_lines_validate_tenancy
before insert or update on public.journal_entry_lines
for each row execute function public.validate_journal_line_tenancy()","-- ---------------------------------------------------------------------------
-- Immutability of posted / reversed entries
-- ---------------------------------------------------------------------------

create or replace function public.prevent_posted_journal_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if tg_op = ''DELETE'' then
    if old.status in (''POSTED'', ''REVERSED'') then
      raise exception ''posted journal entries cannot be deleted'';
    end if;
    return old;
  end if;

  -- Allow controlled transitions via SECURITY DEFINER engines only:
  -- engines set a session GUC flag accounting.engine_write = ''1''
  if current_setting(''accounting.engine_write'', true) = ''1'' then
    return new;
  end if;

  if old.status in (''POSTED'', ''REVERSED'') then
    raise exception ''posted journal entries are immutable; use reversal'';
  end if;

  -- Draft edits allowed for non-status-protected fields
  if new.status is distinct from old.status and new.status <> ''DRAFT'' then
    raise exception ''status changes must go through posting/reversal engine'';
  end if;

  return new;
end;
$$","drop trigger if exists journal_entries_immutability on public.journal_entries","create trigger journal_entries_immutability
before update or delete on public.journal_entries
for each row execute function public.prevent_posted_journal_mutation()","create or replace function public.prevent_posted_line_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  st public.journal_entry_status;
  entry_id uuid;
begin
  entry_id := coalesce(new.journal_entry_id, old.journal_entry_id);
  select status into st from public.journal_entries where id = entry_id;

  if current_setting(''accounting.engine_write'', true) = ''1'' then
    if tg_op = ''DELETE'' then return old; end if;
    return new;
  end if;

  if st in (''POSTED'', ''REVERSED'') then
    raise exception ''lines of posted journal entries are immutable'';
  end if;

  if tg_op = ''DELETE'' then return old; end if;
  return new;
end;
$$","drop trigger if exists journal_entry_lines_immutability on public.journal_entry_lines","create trigger journal_entry_lines_immutability
before update or delete on public.journal_entry_lines
for each row execute function public.prevent_posted_line_mutation()","-- ---------------------------------------------------------------------------
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
set search_path = ''''
as $$
begin
  return query
  select ap.id, ap.fiscal_year_id
  from public.accounting_periods ap
  join public.accounting_fiscal_years fy on fy.id = ap.fiscal_year_id
  where ap.organization_id = p_organization_id
    and ap.status = ''OPEN''
    and fy.status = ''OPEN''
    and p_entry_date between ap.starts_on and ap.ends_on
  limit 1;
end;
$$","-- ---------------------------------------------------------------------------
-- Next entry number (row lock)
-- ---------------------------------------------------------------------------

create or replace function public.next_journal_entry_number(
  p_organization_id uuid,
  p_fiscal_year_id uuid
)
returns text
language plpgsql
security invoker
set search_path = ''''
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
  set last_value = v, updated_at = timezone(''utc'', now())
  where organization_id = p_organization_id
    and fiscal_year_id = p_fiscal_year_id;

  return lpad(v::text, 8, ''0'');
end;
$$","-- ---------------------------------------------------------------------------
-- Audit helper (internal)
-- ---------------------------------------------------------------------------

create or replace function public.accounting_write_audit(
  p_organization_id uuid,
  p_actor uuid,
  p_event_type text,
  p_entity_type text,
  p_entity_id text,
  p_action text,
  p_metadata jsonb default ''{}''::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''''
as $$
begin
  insert into public.audit_events (
    organization_id, actor_user_id, event_type, entity_type, entity_id, action, metadata
  ) values (
    p_organization_id, p_actor, p_event_type, p_entity_type, p_entity_id, p_action,
    coalesce(p_metadata, ''{}''::jsonb)
  );
end;
$$","-- ---------------------------------------------------------------------------
-- POSTING ENGINE
-- ---------------------------------------------------------------------------

create or replace function public.post_journal_entry(p_entry_id uuid)
returns public.journal_entries
language plpgsql
security definer
set search_path = ''''
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
    raise exception ''not authenticated'';
  end if;

  select * into v_entry
  from public.journal_entries
  where id = p_entry_id
  for update;

  if not found then
    raise exception ''journal entry not found'';
  end if;

  if not public.is_org_member(v_entry.organization_id) then
    raise exception ''not a member of organization'';
  end if;

  if not public.has_org_role(
    v_entry.organization_id,
    array[''owner'',''admin'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role to post journal entries'';
  end if;

  if v_entry.status <> ''DRAFT'' then
    raise exception ''only DRAFT entries can be posted'';
  end if;

  select period_id, fiscal_year_id into v_period_id, v_fy_id
  from public.resolve_open_period(v_entry.organization_id, v_entry.entry_date);

  if v_period_id is null then
    raise exception ''no OPEN period (and OPEN fiscal year) covers entry_date'';
  end if;

  select
    count(*)::int,
    coalesce(sum(debit), 0),
    coalesce(sum(credit), 0)
  into v_line_count, v_debit, v_credit
  from public.journal_entry_lines
  where journal_entry_id = p_entry_id;

  if v_line_count < 2 then
    raise exception ''posted entries require at least two lines'';
  end if;

  if v_debit <> v_credit then
    raise exception ''unbalanced entry: debit % <> credit %'', v_debit, v_credit;
  end if;

  if v_debit <= 0 then
    raise exception ''posted entry totals must be greater than zero'';
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
    raise exception ''one or more lines reference invalid accounts'';
  end if;

  v_number := public.next_journal_entry_number(v_entry.organization_id, v_fy_id);

  perform set_config(''accounting.engine_write'', ''1'', true);

  update public.journal_entries
  set
    status = ''POSTED'',
    entry_number = v_number,
    period_id = v_period_id,
    fiscal_year_id = v_fy_id,
    posted_by = v_uid,
    posted_at = timezone(''utc'', now())
  where id = p_entry_id
  returning * into v_entry;

  perform set_config(''accounting.engine_write'', ''0'', true);

  perform public.accounting_write_audit(
    v_entry.organization_id,
    v_uid,
    ''journal.posted'',
    ''journal_entry'',
    v_entry.id::text,
    ''post'',
    jsonb_build_object(
      ''entry_number'', v_entry.entry_number,
      ''entry_date'', v_entry.entry_date,
      ''debit_total'', v_debit,
      ''credit_total'', v_credit,
      ''period_id'', v_period_id
    )
  );

  return v_entry;
end;
$$","-- ---------------------------------------------------------------------------
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
set search_path = ''''
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
    raise exception ''not authenticated'';
  end if;

  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception ''reversal reason is required'';
  end if;

  select * into v_orig
  from public.journal_entries
  where id = p_original_entry_id
  for update;

  if not found then
    raise exception ''journal entry not found'';
  end if;

  if not public.is_org_member(v_orig.organization_id) then
    raise exception ''not a member of organization'';
  end if;

  if not public.has_org_role(
    v_orig.organization_id,
    array[''owner'',''admin'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role to reverse journal entries'';
  end if;

  if v_orig.status <> ''POSTED'' then
    raise exception ''only POSTED entries can be reversed'';
  end if;

  if v_orig.reversed_by_entry_id is not null then
    raise exception ''entry already reversed'';
  end if;

  select period_id, fiscal_year_id into v_period_id, v_fy_id
  from public.resolve_open_period(v_orig.organization_id, p_reversal_date);

  if v_period_id is null then
    raise exception ''no OPEN period (and OPEN fiscal year) covers reversal_date'';
  end if;

  perform set_config(''accounting.engine_write'', ''1'', true);

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
    ''Reversión de asiento '' || coalesce(v_orig.entry_number, v_orig.id::text) || '': '' || v_orig.description,
    ''DRAFT'',
    ''SYSTEM'',
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
      coalesce(r.description, ''Reversión''),
      r.credit,
      r.debit,
      r.line_number,
      coalesce(r.metadata, ''{}''::jsonb) || jsonb_build_object(''reversed_from_line_id'', r.id)
    );
  end loop;

  select count(*)::int, coalesce(sum(debit), 0), coalesce(sum(credit), 0)
  into v_line_count, v_debit, v_credit
  from public.journal_entry_lines
  where journal_entry_id = v_rev.id;

  if v_line_count < 2 or v_debit <> v_credit or v_debit <= 0 then
    raise exception ''reversal entry failed balance validation'';
  end if;

  v_number := public.next_journal_entry_number(v_orig.organization_id, v_fy_id);

  update public.journal_entries
  set
    status = ''POSTED'',
    entry_number = v_number,
    posted_by = v_uid,
    posted_at = timezone(''utc'', now())
  where id = v_rev.id
  returning * into v_rev;

  update public.journal_entries
  set
    status = ''REVERSED'',
    reversed_by_entry_id = v_rev.id
  where id = v_orig.id;

  perform set_config(''accounting.engine_write'', ''0'', true);

  perform public.accounting_write_audit(
    v_orig.organization_id,
    v_uid,
    ''journal.reversed'',
    ''journal_entry'',
    v_orig.id::text,
    ''reverse'',
    jsonb_build_object(
      ''original_entry_number'', v_orig.entry_number,
      ''reversal_entry_id'', v_rev.id,
      ''reversal_entry_number'', v_rev.entry_number,
      ''reason'', trim(p_reason)
    )
  );

  return v_rev;
end;
$$","-- ---------------------------------------------------------------------------
-- Period close / reopen
-- ---------------------------------------------------------------------------

create or replace function public.close_accounting_period(p_period_id uuid)
returns public.accounting_periods
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_period public.accounting_periods;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_period from public.accounting_periods where id = p_period_id for update;
  if not found then raise exception ''period not found''; end if;

  if not public.has_org_role(
    v_period.organization_id,
    array[''owner'',''admin'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role to close period'';
  end if;

  if v_period.status = ''CLOSED'' then
    raise exception ''period already closed'';
  end if;

  if exists (
    select 1 from public.journal_entries
    where organization_id = v_period.organization_id
      and entry_date between v_period.starts_on and v_period.ends_on
      and status = ''DRAFT''
  ) then
    raise exception ''period has DRAFT entries; post or delete drafts before closing'';
  end if;

  update public.accounting_periods
  set status = ''CLOSED'', closed_by = v_uid, closed_at = timezone(''utc'', now())
  where id = p_period_id
  returning * into v_period;

  perform public.accounting_write_audit(
    v_period.organization_id, v_uid, ''period.closed'', ''accounting_period'',
    v_period.id::text, ''close'',
    jsonb_build_object(''name'', v_period.name, ''starts_on'', v_period.starts_on, ''ends_on'', v_period.ends_on)
  );

  return v_period;
end;
$$","create or replace function public.reopen_accounting_period(
  p_period_id uuid,
  p_reason text
)
returns public.accounting_periods
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_period public.accounting_periods;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception ''reopen reason is required'';
  end if;

  select * into v_period from public.accounting_periods where id = p_period_id for update;
  if not found then raise exception ''period not found''; end if;

  -- Privileged: owner/admin only (accountant may close but reopen is exceptional)
  if not public.has_org_role(
    v_period.organization_id,
    array[''owner'',''admin'']::public.member_role[]
  ) then
    raise exception ''insufficient role to reopen period'';
  end if;

  if v_period.status <> ''CLOSED'' then
    raise exception ''period is not closed'';
  end if;

  -- Fiscal year must still be OPEN
  if exists (
    select 1 from public.accounting_fiscal_years
    where id = v_period.fiscal_year_id and status = ''CLOSED''
  ) then
    raise exception ''cannot reopen period in a CLOSED fiscal year'';
  end if;

  update public.accounting_periods
  set
    status = ''OPEN'',
    reopened_by = v_uid,
    reopened_at = timezone(''utc'', now()),
    reopen_reason = trim(p_reason),
    closed_at = null,
    closed_by = null
  where id = p_period_id
  returning * into v_period;

  perform public.accounting_write_audit(
    v_period.organization_id, v_uid, ''period.reopened'', ''accounting_period'',
    v_period.id::text, ''reopen'',
    jsonb_build_object(''name'', v_period.name, ''reason'', trim(p_reason))
  );

  return v_period;
end;
$$","-- ---------------------------------------------------------------------------
-- Starter chart of accounts template (replaceable)
-- ---------------------------------------------------------------------------

create or replace function public.seed_starter_chart_of_accounts(p_organization_id uuid)
returns int
language plpgsql
security definer
set search_path = ''''
as $$
declare
  n int := 0;
  id_1 uuid; id_11 uuid; id_12 uuid;
  id_2 uuid; id_21 uuid; id_22 uuid;
  id_3 uuid; id_4 uuid; id_5 uuid; id_6 uuid;
begin
  if not public.has_org_role(
    p_organization_id,
    array[''owner'',''admin'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role to seed chart of accounts'';
  end if;

  if exists (select 1 from public.accounts where organization_id = p_organization_id) then
    return 0;
  end if;

  insert into public.accounts (organization_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, ''1'', ''ACTIVO'', ''ASSET'', ''DEBIT'', false, ''group_asset'')
  returning id into id_1;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_1, ''1.1'', ''Activo corriente'', ''ASSET'', ''DEBIT'', false, ''group_asset_current'')
  returning id into id_11;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values
    (p_organization_id, id_11, ''1.1.01'', ''Caja'', ''ASSET'', ''DEBIT'', true, ''cash''),
    (p_organization_id, id_11, ''1.1.02'', ''Bancos'', ''ASSET'', ''DEBIT'', true, ''bank''),
    (p_organization_id, id_11, ''1.1.03'', ''Clientes'', ''ASSET'', ''DEBIT'', true, ''receivables'');

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_1, ''1.2'', ''Activo no corriente'', ''ASSET'', ''DEBIT'', false, ''group_asset_noncurrent'')
  returning id into id_12;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_12, ''1.2.01'', ''Bienes de uso'', ''ASSET'', ''DEBIT'', true, ''fixed_assets'');

  insert into public.accounts (organization_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, ''2'', ''PASIVO'', ''LIABILITY'', ''CREDIT'', false, ''group_liability'')
  returning id into id_2;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_2, ''2.1'', ''Pasivo corriente'', ''LIABILITY'', ''CREDIT'', false, ''group_liability_current'')
  returning id into id_21;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values
    (p_organization_id, id_21, ''2.1.01'', ''Proveedores'', ''LIABILITY'', ''CREDIT'', true, ''payables''),
    (p_organization_id, id_21, ''2.1.02'', ''Obligaciones a pagar'', ''LIABILITY'', ''CREDIT'', true, null);

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_2, ''2.2'', ''Pasivo no corriente'', ''LIABILITY'', ''CREDIT'', false, ''group_liability_noncurrent'')
  returning id into id_22;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_22, ''2.2.01'', ''Deudas a largo plazo'', ''LIABILITY'', ''CREDIT'', true, null);

  insert into public.accounts (organization_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, ''3'', ''PATRIMONIO NETO'', ''EQUITY'', ''CREDIT'', false, ''group_equity'')
  returning id into id_3;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_3, ''3.1.01'', ''Capital'', ''EQUITY'', ''CREDIT'', true, ''capital'');

  insert into public.accounts (organization_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, ''4'', ''INGRESOS'', ''REVENUE'', ''CREDIT'', false, ''group_revenue'')
  returning id into id_4;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_4, ''4.1.01'', ''Ventas'', ''REVENUE'', ''CREDIT'', true, ''sales'');

  insert into public.accounts (organization_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, ''5'', ''COSTOS'', ''EXPENSE'', ''DEBIT'', false, ''group_cogs'')
  returning id into id_5;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, id_5, ''5.1.01'', ''Costo de mercaderías vendidas'', ''EXPENSE'', ''DEBIT'', true, ''cogs'');

  insert into public.accounts (organization_id, code, name, account_type, normal_balance, is_postable, system_role)
  values (p_organization_id, ''6'', ''GASTOS'', ''EXPENSE'', ''DEBIT'', false, ''group_expense'')
  returning id into id_6;

  insert into public.accounts (organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role)
  values
    (p_organization_id, id_6, ''6.1.01'', ''Gastos de administración'', ''EXPENSE'', ''DEBIT'', true, null),
    (p_organization_id, id_6, ''6.1.02'', ''Gastos de comercialización'', ''EXPENSE'', ''DEBIT'', true, null);

  select count(*)::int into n from public.accounts where organization_id = p_organization_id;
  return n;
end;
$$","-- ---------------------------------------------------------------------------
-- Ensure monthly periods helper for a fiscal year
-- ---------------------------------------------------------------------------

create or replace function public.ensure_monthly_periods(p_fiscal_year_id uuid)
returns int
language plpgsql
security definer
set search_path = ''''
as $$
declare
  fy public.accounting_fiscal_years;
  d date;
  month_end date;
  created int := 0;
  month_names text[] := array[
    ''Enero'',''Febrero'',''Marzo'',''Abril'',''Mayo'',''Junio'',
    ''Julio'',''Agosto'',''Septiembre'',''Octubre'',''Noviembre'',''Diciembre''
  ];
begin
  select * into fy from public.accounting_fiscal_years where id = p_fiscal_year_id;
  if not found then raise exception ''fiscal year not found''; end if;

  if not public.has_org_role(
    fy.organization_id,
    array[''owner'',''admin'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role'';
  end if;

  d := date_trunc(''month'', fy.start_date::timestamp)::date;
  while d <= fy.end_date loop
    month_end := (date_trunc(''month'', d::timestamp) + interval ''1 month - 1 day'')::date;
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
      month_names[extract(month from d)::int] || '' '' || extract(year from d)::text,
      greatest(d, fy.start_date),
      month_end,
      ''OPEN'',
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

    d := (date_trunc(''month'', d::timestamp) + interval ''1 month'')::date;
  end loop;

  return created;
end;
$$","-- Flip platform flags (staging)
update public.app_settings
set value = ''2''::jsonb, updated_at = timezone(''utc'', now())
where key = ''platform.phase''","update public.app_settings
set value = ''true''::jsonb, updated_at = timezone(''utc'', now())
where key = ''platform.accounting_core_enabled''","update public.feature_catalog
set default_status = ''enabled''
where code = ''accounting''"}', 'phase2_accounting_core'),
	('20260329210000', '{"-- Phase 2 — Accounting RLS + EXECUTE hardening (STAGING)
-- Project: rpcpdrzbcclofvjpgldb

-- ---------------------------------------------------------------------------
-- Enable RLS
-- ---------------------------------------------------------------------------

alter table public.accounting_fiscal_years enable row level security","alter table public.accounts enable row level security","alter table public.accounting_sequences enable row level security","alter table public.journal_entries enable row level security","alter table public.journal_entry_lines enable row level security","-- ---------------------------------------------------------------------------
-- accounting_fiscal_years
-- ---------------------------------------------------------------------------

drop policy if exists accounting_fiscal_years_select on public.accounting_fiscal_years","create policy accounting_fiscal_years_select
  on public.accounting_fiscal_years for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists accounting_fiscal_years_insert on public.accounting_fiscal_years","create policy accounting_fiscal_years_insert
  on public.accounting_fiscal_years for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","drop policy if exists accounting_fiscal_years_update on public.accounting_fiscal_years","create policy accounting_fiscal_years_update
  on public.accounting_fiscal_years for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","drop policy if exists accounting_fiscal_years_delete on public.accounting_fiscal_years","create policy accounting_fiscal_years_delete
  on public.accounting_fiscal_years for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- accounts
-- ---------------------------------------------------------------------------

drop policy if exists accounts_select on public.accounts","create policy accounts_select
  on public.accounts for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists accounts_insert on public.accounts","create policy accounts_insert
  on public.accounts for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","drop policy if exists accounts_update on public.accounts","create policy accounts_update
  on public.accounts for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","drop policy if exists accounts_delete on public.accounts","create policy accounts_delete
  on public.accounts for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- accounting_sequences — no direct client writes; engines use SECURITY DEFINER
-- ---------------------------------------------------------------------------

drop policy if exists accounting_sequences_select on public.accounting_sequences","create policy accounting_sequences_select
  on public.accounting_sequences for select to authenticated
  using ((select public.is_org_member(organization_id)))","-- No insert/update/delete policies for authenticated (engine bypasses RLS as definer)

-- ---------------------------------------------------------------------------
-- journal_entries
-- ---------------------------------------------------------------------------

drop policy if exists journal_entries_select on public.journal_entries","create policy journal_entries_select
  on public.journal_entries for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists journal_entries_insert on public.journal_entries","create policy journal_entries_insert
  on public.journal_entries for insert to authenticated
  with check (
    (select public.has_org_role(
      organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
    ))
    and created_by = (select auth.uid())
    and status = ''DRAFT''
  )","drop policy if exists journal_entries_update on public.journal_entries","create policy journal_entries_update
  on public.journal_entries for update to authenticated
  using (
    status = ''DRAFT''
    and (select public.has_org_role(
      organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
    ))
  )
  with check (
    status = ''DRAFT''
    and (select public.has_org_role(
      organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
    ))
  )","drop policy if exists journal_entries_delete on public.journal_entries","create policy journal_entries_delete
  on public.journal_entries for delete to authenticated
  using (
    status = ''DRAFT''
    and (select public.has_org_role(
      organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
    ))
  )","-- ---------------------------------------------------------------------------
-- journal_entry_lines
-- ---------------------------------------------------------------------------

drop policy if exists journal_entry_lines_select on public.journal_entry_lines","create policy journal_entry_lines_select
  on public.journal_entry_lines for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists journal_entry_lines_insert on public.journal_entry_lines","create policy journal_entry_lines_insert
  on public.journal_entry_lines for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
  )))","drop policy if exists journal_entry_lines_update on public.journal_entry_lines","create policy journal_entry_lines_update
  on public.journal_entry_lines for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
  )))","drop policy if exists journal_entry_lines_delete on public.journal_entry_lines","create policy journal_entry_lines_delete
  on public.journal_entry_lines for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- Cost centers: allow accountant to manage (Phase 2 alignment)
-- ---------------------------------------------------------------------------

drop policy if exists cost_centers_insert on public.cost_centers","create policy cost_centers_insert
  on public.cost_centers for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[]
  )))","drop policy if exists cost_centers_update on public.cost_centers","create policy cost_centers_update
  on public.cost_centers for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[]
  )))","drop policy if exists cost_centers_delete on public.cost_centers","create policy cost_centers_delete
  on public.cost_centers for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- Function grants — revoke anon; engines for authenticated only
-- ---------------------------------------------------------------------------

revoke all on function public.sync_period_closed_flag() from public, anon, authenticated","revoke all on function public.validate_account_hierarchy() from public, anon, authenticated","revoke all on function public.prevent_account_delete_with_movements() from public, anon, authenticated","revoke all on function public.validate_journal_line_tenancy() from public, anon, authenticated","revoke all on function public.prevent_posted_journal_mutation() from public, anon, authenticated","revoke all on function public.prevent_posted_line_mutation() from public, anon, authenticated","revoke all on function public.resolve_open_period(uuid, date) from public, anon","grant execute on function public.resolve_open_period(uuid, date) to authenticated","revoke all on function public.next_journal_entry_number(uuid, uuid) from public, anon, authenticated","revoke all on function public.accounting_write_audit(uuid, uuid, text, text, text, text, jsonb)
  from public, anon, authenticated","revoke all on function public.post_journal_entry(uuid) from public, anon","grant execute on function public.post_journal_entry(uuid) to authenticated","revoke all on function public.reverse_journal_entry(uuid, date, text) from public, anon","grant execute on function public.reverse_journal_entry(uuid, date, text) to authenticated","revoke all on function public.close_accounting_period(uuid) from public, anon","grant execute on function public.close_accounting_period(uuid) to authenticated","revoke all on function public.reopen_accounting_period(uuid, text) from public, anon","grant execute on function public.reopen_accounting_period(uuid, text) to authenticated","revoke all on function public.seed_starter_chart_of_accounts(uuid) from public, anon","grant execute on function public.seed_starter_chart_of_accounts(uuid) to authenticated","revoke all on function public.ensure_monthly_periods(uuid) from public, anon","grant execute on function public.ensure_monthly_periods(uuid) to authenticated"}', 'phase2_accounting_security'),
	('20260501180000', '{"-- Phase 5 — Split FOR ALL RLS policies (eliminate multiple permissive SELECT)
-- Preserve authorization semantics exactly.

-- fiscal_points_of_sale
drop policy if exists fiscal_points_of_sale_write on public.fiscal_points_of_sale","drop policy if exists fiscal_points_of_sale_insert on public.fiscal_points_of_sale","drop policy if exists fiscal_points_of_sale_update on public.fiscal_points_of_sale","drop policy if exists fiscal_points_of_sale_delete on public.fiscal_points_of_sale","create policy fiscal_points_of_sale_insert
  on public.fiscal_points_of_sale for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","create policy fiscal_points_of_sale_update
  on public.fiscal_points_of_sale for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","create policy fiscal_points_of_sale_delete
  on public.fiscal_points_of_sale for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","-- fiscal_credential_metadata
drop policy if exists fiscal_credential_metadata_write on public.fiscal_credential_metadata","drop policy if exists fiscal_credential_metadata_insert on public.fiscal_credential_metadata","drop policy if exists fiscal_credential_metadata_update on public.fiscal_credential_metadata","drop policy if exists fiscal_credential_metadata_delete on public.fiscal_credential_metadata","create policy fiscal_credential_metadata_insert
  on public.fiscal_credential_metadata for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'']::public.member_role[]
  )))","create policy fiscal_credential_metadata_update
  on public.fiscal_credential_metadata for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'']::public.member_role[]
  )))","create policy fiscal_credential_metadata_delete
  on public.fiscal_credential_metadata for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'']::public.member_role[]
  )))","-- fiscal_service_profiles
drop policy if exists fiscal_service_profiles_write on public.fiscal_service_profiles","drop policy if exists fiscal_service_profiles_insert on public.fiscal_service_profiles","drop policy if exists fiscal_service_profiles_update on public.fiscal_service_profiles","drop policy if exists fiscal_service_profiles_delete on public.fiscal_service_profiles","create policy fiscal_service_profiles_insert
  on public.fiscal_service_profiles for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","create policy fiscal_service_profiles_update
  on public.fiscal_service_profiles for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","create policy fiscal_service_profiles_delete
  on public.fiscal_service_profiles for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","-- fiscal_document_lines
drop policy if exists fiscal_document_lines_write on public.fiscal_document_lines","drop policy if exists fiscal_document_lines_insert on public.fiscal_document_lines","drop policy if exists fiscal_document_lines_update on public.fiscal_document_lines","drop policy if exists fiscal_document_lines_delete on public.fiscal_document_lines","create policy fiscal_document_lines_insert
  on public.fiscal_document_lines for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy fiscal_document_lines_update
  on public.fiscal_document_lines for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy fiscal_document_lines_delete
  on public.fiscal_document_lines for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","-- fiscal_tax_summaries
drop policy if exists fiscal_tax_summaries_write on public.fiscal_tax_summaries","drop policy if exists fiscal_tax_summaries_insert on public.fiscal_tax_summaries","drop policy if exists fiscal_tax_summaries_update on public.fiscal_tax_summaries","drop policy if exists fiscal_tax_summaries_delete on public.fiscal_tax_summaries","create policy fiscal_tax_summaries_insert
  on public.fiscal_tax_summaries for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy fiscal_tax_summaries_update
  on public.fiscal_tax_summaries for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy fiscal_tax_summaries_delete
  on public.fiscal_tax_summaries for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","-- fiscal_accounting_mappings
drop policy if exists fiscal_accounting_mappings_write on public.fiscal_accounting_mappings","drop policy if exists fiscal_accounting_mappings_insert on public.fiscal_accounting_mappings","drop policy if exists fiscal_accounting_mappings_update on public.fiscal_accounting_mappings","drop policy if exists fiscal_accounting_mappings_delete on public.fiscal_accounting_mappings","create policy fiscal_accounting_mappings_insert
  on public.fiscal_accounting_mappings for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","create policy fiscal_accounting_mappings_update
  on public.fiscal_accounting_mappings for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","create policy fiscal_accounting_mappings_delete
  on public.fiscal_accounting_mappings for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))"}', 'phase5_rls_policy_split'),
	('20260501190000', '{"-- Phase 5 — SECURITY DEFINER trust boundary
-- Trusted ARCA adapter operations: service_role ONLY (no authenticated EXECUTE).
-- See docs/architecture/PHASE5-SECURITY-DEFINER.md

create or replace function public.fiscal_assert_service_role()
returns void
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if auth.role() is distinct from ''service_role'' then
    raise exception ''trusted fiscal adapter operation requires service_role'';
  end if;
end;
$$","revoke all on function public.fiscal_assert_service_role() from public, anon, authenticated","grant execute on function public.fiscal_assert_service_role() to service_role","-- Recreate trusted functions with service_role gate (not auth.uid()/has_org_role)
create or replace function public.begin_fiscal_authorization(
  p_fiscal_document_id uuid,
  p_intended_document_number bigint,
  p_certificate_fingerprint text,
  p_request_hash text,
  p_correlation_id text
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_doc public.fiscal_documents%rowtype;
  v_attempt_id uuid;
  v_attempt_no int;
begin
  perform public.fiscal_assert_service_role();

  if p_intended_document_number is null or p_intended_document_number <= 0 then
    raise exception ''intended document number required'';
  end if;

  select * into v_doc
  from public.fiscal_documents
  where id = p_fiscal_document_id
  for update;

  if not found then
    raise exception ''fiscal document not found'';
  end if;

  perform public.fiscal_assert_feature(v_doc.organization_id);

  if v_doc.fiscal_environment = ''PRODUCTION'' then
    raise exception ''PRODUCTION ARCA blocked'';
  end if;

  if v_doc.status = ''AUTHORIZED'' then
    raise exception ''already authorized'';
  end if;

  if v_doc.status = ''AUTHORIZING'' then
    raise exception ''authorization already in progress; reconcile first'';
  end if;

  if v_doc.status = ''RECONCILIATION_REQUIRED'' then
    raise exception ''uncertain outcome: reconcile before new FECAE; do not allocate a new number'';
  end if;

  if v_doc.status is distinct from ''READY_TO_AUTHORIZE'' then
    raise exception ''document must be READY_TO_AUTHORIZE'';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      v_doc.organization_id::text || '':'' || v_doc.fiscal_environment::text
      || '':'' || v_doc.arca_point_of_sale::text || '':'' || v_doc.arca_cbte_tipo::text
    )
  );

  select coalesce(max(attempt_number), 0) + 1 into v_attempt_no
  from public.fiscal_authorization_attempts
  where fiscal_document_id = p_fiscal_document_id;

  insert into public.fiscal_authorization_attempts (
    fiscal_document_id, organization_id, attempt_number, environment, service,
    requested_pos, requested_cbte_tipo, requested_document_number,
    certificate_fingerprint, request_hash, correlation_id, outcome
  ) values (
    p_fiscal_document_id, v_doc.organization_id, v_attempt_no, v_doc.fiscal_environment, ''wsfe'',
    v_doc.arca_point_of_sale, v_doc.arca_cbte_tipo, p_intended_document_number,
    p_certificate_fingerprint, p_request_hash, p_correlation_id, null
  )
  returning id into v_attempt_id;

  update public.fiscal_documents
  set status = ''AUTHORIZING'',
      document_number = p_intended_document_number,
      credential_fingerprint = p_certificate_fingerprint,
      updated_at = timezone(''utc'', now())
  where id = p_fiscal_document_id;

  return v_attempt_id;
end;
$$","create or replace function public.complete_fiscal_authorization(
  p_attempt_id uuid,
  p_outcome public.fiscal_authorization_outcome,
  p_cae text default null,
  p_cae_expiration date default null,
  p_arca_error_codes jsonb default ''[]''::jsonb,
  p_arca_observation_codes jsonb default ''[]''::jsonb,
  p_transport_error_class text default null,
  p_arca_result jsonb default ''{}''::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_attempt public.fiscal_authorization_attempts%rowtype;
  v_doc public.fiscal_documents%rowtype;
begin
  perform public.fiscal_assert_service_role();

  select * into v_attempt
  from public.fiscal_authorization_attempts
  where id = p_attempt_id
  for update;

  if not found then
    raise exception ''attempt not found'';
  end if;

  select * into v_doc
  from public.fiscal_documents
  where id = v_attempt.fiscal_document_id
  for update;

  perform set_config(''fiscal.engine_write'', ''1'', true);

  update public.fiscal_authorization_attempts
  set completed_at = timezone(''utc'', now()),
      outcome = p_outcome,
      cae = p_cae,
      cae_expiration_date = p_cae_expiration,
      arca_error_codes = coalesce(p_arca_error_codes, ''[]''::jsonb),
      arca_observation_codes = coalesce(p_arca_observation_codes, ''[]''::jsonb),
      transport_error_class = p_transport_error_class
  where id = p_attempt_id;

  if p_outcome in (''APPROVED'', ''RECONCILED_AUTHORIZED'') then
    if p_cae is null or p_cae_expiration is null then
      raise exception ''CAE and expiration required for approved outcome'';
    end if;

    update public.fiscal_documents
    set status = ''AUTHORIZED'',
        cae = p_cae,
        cae_expiration_date = p_cae_expiration,
        arca_result = coalesce(p_arca_result, ''{}''::jsonb),
        arca_observations = coalesce(p_arca_observation_codes, ''[]''::jsonb),
        authorized_at = timezone(''utc'', now()),
        accounting_status = ''PENDING'',
        updated_at = timezone(''utc'', now())
    where id = v_doc.id;

    if v_doc.sales_document_id is not null and v_doc.relationship_type is null then
      update public.sales_documents
      set status = ''INVOICED'',
          invoiced_fiscal_document_id = v_doc.id,
          updated_at = timezone(''utc'', now())
      where id = v_doc.sales_document_id
        and organization_id = v_doc.organization_id
        and status = ''READY_TO_INVOICE'';
    end if;

  elsif p_outcome = ''REJECTED'' then
    update public.fiscal_documents
    set status = ''REJECTED'',
        document_number = null,
        arca_result = coalesce(p_arca_result, ''{}''::jsonb),
        arca_observations = coalesce(p_arca_observation_codes, ''[]''::jsonb),
        updated_at = timezone(''utc'', now())
    where id = v_doc.id;

  elsif p_outcome in (''TRANSPORT_ERROR'', ''UNCERTAIN'', ''AUTH_ERROR'') then
    update public.fiscal_documents
    set status = ''RECONCILIATION_REQUIRED'',
        arca_result = coalesce(p_arca_result, ''{}''::jsonb),
        updated_at = timezone(''utc'', now())
    where id = v_doc.id;

  elsif p_outcome = ''RECONCILED_NOT_FOUND'' then
    update public.fiscal_documents
    set status = ''READY_TO_AUTHORIZE'',
        document_number = null,
        updated_at = timezone(''utc'', now())
    where id = v_doc.id;

  elsif p_outcome = ''BUSINESS_VALIDATION_ERROR'' then
    update public.fiscal_documents
    set status = ''REJECTED'',
        document_number = null,
        arca_result = coalesce(p_arca_result, ''{}''::jsonb),
        updated_at = timezone(''utc'', now())
    where id = v_doc.id;
  else
    raise exception ''unsupported outcome %'', p_outcome;
  end if;

  return v_doc.id;
end;
$$","create or replace function public.set_fiscal_qr_payload(
  p_fiscal_document_id uuid,
  p_qr_payload text
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_doc public.fiscal_documents%rowtype;
begin
  perform public.fiscal_assert_service_role();

  select * into v_doc from public.fiscal_documents where id = p_fiscal_document_id for update;
  if not found then raise exception ''fiscal document not found''; end if;
  if v_doc.status is distinct from ''AUTHORIZED'' then
    raise exception ''QR only after AUTHORIZED'';
  end if;
  perform set_config(''fiscal.engine_write'', ''1'', true);
  update public.fiscal_documents
  set qr_payload = p_qr_payload, updated_at = timezone(''utc'', now())
  where id = p_fiscal_document_id;
  return p_fiscal_document_id;
end;
$$","revoke all on function public.begin_fiscal_authorization(uuid, bigint, text, text, text)
  from public, anon, authenticated","revoke all on function public.complete_fiscal_authorization(
  uuid, public.fiscal_authorization_outcome, text, date, jsonb, jsonb, text, jsonb
) from public, anon, authenticated","revoke all on function public.set_fiscal_qr_payload(uuid, text)
  from public, anon, authenticated","grant execute on function public.begin_fiscal_authorization(uuid, bigint, text, text, text)
  to service_role","grant execute on function public.complete_fiscal_authorization(
  uuid, public.fiscal_authorization_outcome, text, date, jsonb, jsonb, text, jsonb
) to service_role","grant execute on function public.set_fiscal_qr_payload(uuid, text)
  to service_role","-- Reaffirm USER-CALLABLE grants (INTENTIONAL_AND_DOCUMENTED)
revoke all on function public.prepare_fiscal_invoice_from_sales_order(uuid, uuid, text, date, int)
  from public, anon","revoke all on function public.prepare_fiscal_note(uuid, text, public.fiscal_relationship_type, date, text)
  from public, anon","revoke all on function public.mark_fiscal_ready_to_authorize(uuid)
  from public, anon","revoke all on function public.resolve_fiscal_rule_version(uuid, date)
  from public, anon","grant execute on function public.prepare_fiscal_invoice_from_sales_order(uuid, uuid, text, date, int)
  to authenticated, service_role","grant execute on function public.prepare_fiscal_note(uuid, text, public.fiscal_relationship_type, date, text)
  to authenticated, service_role","grant execute on function public.mark_fiscal_ready_to_authorize(uuid)
  to authenticated, service_role","grant execute on function public.resolve_fiscal_rule_version(uuid, date)
  to authenticated, service_role","comment on function public.begin_fiscal_authorization(uuid, bigint, text, text, text) is
  ''TRUSTED SERVER ONLY (service_role) — ARCA adapter after UltimoAutorizado.''","comment on function public.complete_fiscal_authorization(uuid, public.fiscal_authorization_outcome, text, date, jsonb, jsonb, text, jsonb) is
  ''TRUSTED SERVER ONLY (service_role) — CAE forgery protection; browser cannot RPC APPROVED.''","comment on function public.set_fiscal_qr_payload(uuid, text) is
  ''TRUSTED SERVER ONLY (service_role) — QR forgery protection.''","comment on function public.prepare_fiscal_invoice_from_sales_order(uuid, uuid, text, date, int) is
  ''INTENTIONAL_AND_DOCUMENTED — USER-CALLABLE SECURITY DEFINER; DRAFT only.''","comment on function public.prepare_fiscal_note(uuid, text, public.fiscal_relationship_type, date, text) is
  ''INTENTIONAL_AND_DOCUMENTED — USER-CALLABLE SECURITY DEFINER; DRAFT note only.''","comment on function public.mark_fiscal_ready_to_authorize(uuid) is
  ''INTENTIONAL_AND_DOCUMENTED — USER-CALLABLE SECURITY DEFINER; never sets CAE.''"}', 'phase5_security_definer_trust'),
	('20260329220000', '{"-- Phase 2 hardening: relocate btree_gist out of public (STAGING)
-- Project: rpcpdrzbcclofvjpgldb
--
-- Exclusion constraints depending on btree_gist:
--   accounting_fiscal_years_no_overlap
--   accounting_periods_no_overlap
--
-- Strategy: ALTER EXTENSION … SET SCHEMA (relocatable=true).
-- Does NOT drop constraints or accounting data.
-- Idempotent if already in extensions.

create schema if not exists extensions","do $$
declare
  current_schema text;
begin
  select n.nspname
    into current_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = ''btree_gist'';

  if current_schema is null then
    execute ''create extension btree_gist with schema extensions'';
  elsif current_schema = ''public'' then
    execute ''alter extension btree_gist set schema extensions'';
  end if;
  -- else already in extensions (or other non-public) — leave as-is
end $$","-- Sanity: exclusion constraints must still exist after relocate
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = ''accounting_fiscal_years_no_overlap''
  ) then
    raise exception ''accounting_fiscal_years_no_overlap missing after btree_gist relocate'';
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = ''accounting_periods_no_overlap''
  ) then
    raise exception ''accounting_periods_no_overlap missing after btree_gist relocate'';
  end if;
end $$"}', 'phase2_btree_gist_extensions_schema'),
	('20260329230000', '{"-- Phase 2 hardening: covering indexes for unindexed FKs (STAGING)
-- Project: rpcpdrzbcclofvjpgldb
--
-- Only add indexes where the FK column is not already the *leading*
-- column of an existing index.

-- accounting_fiscal_years.closed_by
create index if not exists accounting_fiscal_years_closed_by_idx
  on public.accounting_fiscal_years (closed_by)","-- accounting_periods.reopened_by
create index if not exists accounting_periods_reopened_by_idx
  on public.accounting_periods (reopened_by)","-- accounting_sequences.fiscal_year_id
-- PK is (organization_id, fiscal_year_id) — fiscal_year_id is not leading
create index if not exists accounting_sequences_fiscal_year_id_idx
  on public.accounting_sequences (fiscal_year_id)","-- accounts.parent_id
-- existing accounts_org_parent_idx is (organization_id, parent_id) — parent_id not leading
create index if not exists accounts_parent_id_idx
  on public.accounts (parent_id)","-- journal_entries.created_by
create index if not exists journal_entries_created_by_idx
  on public.journal_entries (created_by)","-- journal_entries.fiscal_year_id
-- unique (organization_id, fiscal_year_id, entry_number) does not lead with fiscal_year_id
create index if not exists journal_entries_fiscal_year_id_idx
  on public.journal_entries (fiscal_year_id)","-- journal_entries.posted_by
create index if not exists journal_entries_posted_by_idx
  on public.journal_entries (posted_by)","-- journal_entries.reversed_by_entry_id
-- (reversal_of_entry_id already indexed; this is the inverse link)
create index if not exists journal_entries_reversed_by_entry_id_idx
  on public.journal_entries (reversed_by_entry_id)"}', 'phase2_fk_covering_indexes'),
	('20260331100000', '{"-- Phase 3 — Unified counterparties (STAGING)
-- Project: rpcpdrzbcclofvjpgldb

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.counterparty_entity_type as enum (''INDIVIDUAL'', ''LEGAL_ENTITY'', ''OTHER'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.tax_id_type as enum (
    ''CUIT'', ''CUIL'', ''DNI'', ''PASSPORT'', ''FOREIGN_TAX_ID'', ''NONE''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.counterparty_role as enum (''CUSTOMER'', ''SUPPLIER'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.counterparty_address_type as enum (
    ''FISCAL'', ''COMMERCIAL'', ''DELIVERY'', ''OTHER''
  );
exception when duplicate_object then null;
end $$","-- ---------------------------------------------------------------------------
-- Tax ID normalization + validation (server-side)
-- ---------------------------------------------------------------------------

create or replace function public.normalize_counterparty_tax_id(
  p_type public.tax_id_type,
  p_value text
)
returns text
language plpgsql
immutable
set search_path = ''''
as $$
declare
  v_clean text;
  v_sum int;
  v_rem int;
  v_expected int;
  v_multipliers int[] := array[5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  i int;
begin
  if p_type is null or p_type = ''NONE'' then
    return null;
  end if;

  if p_value is null or trim(p_value) = '''' then
    return null;
  end if;

  v_clean := regexp_replace(trim(p_value), ''[^0-9A-Za-z]'', '''', ''g'');

  if p_type in (''CUIT'', ''CUIL'') then
    v_clean := regexp_replace(trim(p_value), ''[^0-9]'', '''', ''g'');
    if length(v_clean) <> 11 then
      raise exception ''invalid tax id: CUIT/CUIL must have 11 digits'';
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
      raise exception ''invalid tax id: check digit mismatch'';
    end if;

    return v_clean;
  end if;

  if p_type = ''DNI'' then
    v_clean := regexp_replace(trim(p_value), ''[^0-9]'', '''', ''g'');
    if length(v_clean) < 7 or length(v_clean) > 8 then
      raise exception ''invalid tax id: DNI must have 7-8 digits'';
    end if;
    return v_clean;
  end if;

  -- PASSPORT / FOREIGN_TAX_ID — store trimmed uppercase alphanumeric
  v_clean := upper(regexp_replace(trim(p_value), ''[^0-9A-Za-z]'', '''', ''g''));
  if length(v_clean) < 3 then
    raise exception ''invalid tax id: value too short'';
  end if;
  return v_clean;
end;
$$","-- ---------------------------------------------------------------------------
-- counterparties
-- ---------------------------------------------------------------------------

create table public.counterparties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  entity_type public.counterparty_entity_type not null default ''LEGAL_ENTITY'',
  legal_name text not null,
  trade_name text,
  tax_id_type public.tax_id_type not null default ''NONE'',
  tax_id text,
  tax_id_normalized text,
  external_code text,
  email text,
  phone text,
  website text,
  notes text,
  is_active boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint counterparties_legal_name_not_blank check (length(trim(legal_name)) >= 2),
  constraint counterparties_org_id_unique unique (organization_id, id)
)","create index counterparties_org_active_idx
  on public.counterparties (organization_id, is_active)","create index counterparties_org_legal_name_idx
  on public.counterparties (organization_id, legal_name)","create index counterparties_org_trade_name_idx
  on public.counterparties (organization_id, trade_name)
  where trade_name is not null","create unique index counterparties_org_tax_id_unique
  on public.counterparties (organization_id, tax_id_normalized)
  where tax_id_normalized is not null","create trigger counterparties_set_updated_at
before update on public.counterparties
for each row execute function public.set_updated_at()","create or replace function public.counterparties_normalize_tax_id()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if new.tax_id_type = ''NONE'' or new.tax_id is null or trim(new.tax_id) = '''' then
    new.tax_id_normalized := null;
    new.tax_id := null;
    return new;
  end if;

  new.tax_id_normalized := public.normalize_counterparty_tax_id(new.tax_id_type, new.tax_id);
  return new;
end;
$$","create trigger counterparties_normalize_tax_id_trg
before insert or update of tax_id_type, tax_id on public.counterparties
for each row execute function public.counterparties_normalize_tax_id()","-- ---------------------------------------------------------------------------
-- counterparty_roles
-- ---------------------------------------------------------------------------

create table public.counterparty_roles (
  id uuid primary key default gen_random_uuid(),
  counterparty_id uuid not null references public.counterparties (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  role public.counterparty_role not null,
  created_at timestamptz not null default timezone(''utc'', now()),
  created_by uuid references auth.users (id),
  constraint counterparty_roles_unique unique (counterparty_id, role)
)","create index counterparty_roles_org_role_idx
  on public.counterparty_roles (organization_id, role)","create index counterparty_roles_counterparty_idx
  on public.counterparty_roles (counterparty_id)","-- ---------------------------------------------------------------------------
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
  country_code text not null default ''AR'',
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now())
)","create trigger counterparty_fiscal_profiles_set_updated_at
before update on public.counterparty_fiscal_profiles
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- counterparty_addresses
-- ---------------------------------------------------------------------------

create table public.counterparty_addresses (
  id uuid primary key default gen_random_uuid(),
  counterparty_id uuid not null references public.counterparties (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  address_type public.counterparty_address_type not null default ''COMMERCIAL'',
  label text,
  street text,
  number text,
  floor text,
  unit text,
  city text,
  province text,
  postal_code text,
  country_code text not null default ''AR'',
  is_primary boolean not null default false,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now())
)","create index counterparty_addresses_counterparty_idx
  on public.counterparty_addresses (counterparty_id)","create trigger counterparty_addresses_set_updated_at
before update on public.counterparty_addresses
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
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
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint counterparty_contacts_name_not_blank check (length(trim(name)) >= 2)
)","create index counterparty_contacts_counterparty_idx
  on public.counterparty_contacts (counterparty_id)","create trigger counterparty_contacts_set_updated_at
before update on public.counterparty_contacts
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- Tenant consistency on child tables
-- ---------------------------------------------------------------------------

create or replace function public.validate_counterparty_child_tenancy()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  cp_org uuid;
begin
  select organization_id into cp_org
  from public.counterparties
  where id = new.counterparty_id;

  if cp_org is null then
    raise exception ''counterparty not found'';
  end if;

  if new.organization_id <> cp_org then
    raise exception ''child organization must match counterparty organization'';
  end if;

  return new;
end;
$$","create trigger counterparty_roles_validate_tenancy
before insert or update on public.counterparty_roles
for each row execute function public.validate_counterparty_child_tenancy()","create trigger counterparty_fiscal_profiles_validate_tenancy
before insert or update on public.counterparty_fiscal_profiles
for each row execute function public.validate_counterparty_child_tenancy()","create trigger counterparty_addresses_validate_tenancy
before insert or update on public.counterparty_addresses
for each row execute function public.validate_counterparty_child_tenancy()","create trigger counterparty_contacts_validate_tenancy
before insert or update on public.counterparty_contacts
for each row execute function public.validate_counterparty_child_tenancy()","-- ---------------------------------------------------------------------------
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
set search_path = ''''
as $$
  select c.id, ''similar_name''::text
  from public.counterparties c
  where c.organization_id = p_organization_id
    and (p_exclude_id is null or c.id <> p_exclude_id)
    and lower(trim(c.legal_name)) = lower(trim(p_legal_name))
  union all
  select c.id, ''same_email''::text
  from public.counterparties c
  where c.organization_id = p_organization_id
    and (p_exclude_id is null or c.id <> p_exclude_id)
    and p_email is not null
    and trim(p_email) <> ''''
    and lower(trim(c.email)) = lower(trim(p_email))
  union all
  select c.id, ''same_phone''::text
  from public.counterparties c
  where c.organization_id = p_organization_id
    and (p_exclude_id is null or c.id <> p_exclude_id)
    and p_phone is not null
    and trim(p_phone) <> ''''
    and regexp_replace(coalesce(c.phone, ''''), ''[^0-9]'', '''', ''g'')
      = regexp_replace(p_phone, ''[^0-9]'', '''', ''g'');
$$","revoke all on function public.find_counterparty_soft_duplicates(uuid, text, text, text, uuid) from public","grant execute on function public.find_counterparty_soft_duplicates(uuid, text, text, text, uuid) to authenticated"}', 'phase3_counterparties_core'),
	('20260331110000', '{"-- Phase 3 — Counterparty accounting dimension + reversal (STAGING)

-- ---------------------------------------------------------------------------
-- journal_entry_lines.counterparty_id
-- ---------------------------------------------------------------------------

alter table public.journal_entry_lines
  add column if not exists counterparty_id uuid","create index if not exists journal_entry_lines_counterparty_idx
  on public.journal_entry_lines (counterparty_id)
  where counterparty_id is not null","create index if not exists journal_entry_lines_org_counterparty_idx
  on public.journal_entry_lines (organization_id, counterparty_id)
  where counterparty_id is not null","alter table public.journal_entry_lines
  drop constraint if exists journal_entry_lines_counterparty_tenant_fk","alter table public.journal_entry_lines
  add constraint journal_entry_lines_counterparty_tenant_fk
  foreign key (organization_id, counterparty_id)
  references public.counterparties (organization_id, id)
  on delete restrict","-- ---------------------------------------------------------------------------
-- Extend line tenancy validation
-- ---------------------------------------------------------------------------

create or replace function public.validate_journal_line_tenancy()
returns trigger
language plpgsql
security invoker
set search_path = ''''
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
    raise exception ''journal entry not found'';
  end if;
  if entry_status <> ''DRAFT'' then
    raise exception ''cannot modify lines of a non-draft journal entry'';
  end if;
  if new.organization_id <> entry_org then
    raise exception ''line organization must match journal entry'';
  end if;

  select organization_id, is_active, is_postable
    into acct_org, acct_active, acct_postable
  from public.accounts where id = new.account_id;

  if acct_org is null then
    raise exception ''account not found'';
  end if;
  if acct_org <> new.organization_id then
    raise exception ''account must belong to same organization'';
  end if;
  if not acct_active then
    if current_setting(''accounting.engine_write'', true) is distinct from ''1'' then
      raise exception ''inactive accounts cannot receive journal lines'';
    end if;
  end if;
  if not acct_postable then
    if current_setting(''accounting.engine_write'', true) is distinct from ''1'' then
      raise exception ''non-postable accounts cannot receive journal lines'';
    end if;
  end if;

  if new.cost_center_id is not null then
    select organization_id, active into cc_org, cc_active
    from public.cost_centers where id = new.cost_center_id;
    if cc_org is null then
      raise exception ''cost center not found'';
    end if;
    if cc_org <> new.organization_id then
      raise exception ''cost center must belong to same organization'';
    end if;
    if not cc_active then
      raise exception ''inactive cost centers cannot receive journal lines'';
    end if;
  end if;

  if new.counterparty_id is not null then
    select organization_id, is_active into cp_org, cp_active
    from public.counterparties where id = new.counterparty_id;
    if cp_org is null then
      raise exception ''counterparty not found'';
    end if;
    if cp_org <> new.organization_id then
      raise exception ''counterparty must belong to same organization'';
    end if;
    if not cp_active then
      if current_setting(''accounting.engine_write'', true) is distinct from ''1'' then
        raise exception ''inactive counterparties cannot receive journal lines'';
      end if;
    end if;
  end if;

  return new;
end;
$$","-- ---------------------------------------------------------------------------
-- Counterparty delete guard (now that journal lines can reference)
-- ---------------------------------------------------------------------------

create or replace function public.prevent_counterparty_delete_with_movements()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if exists (
    select 1 from public.journal_entry_lines
    where counterparty_id = old.id
  ) then
    raise exception ''counterparty with journal references cannot be deleted; deactivate instead'';
  end if;
  return old;
end;
$$","drop trigger if exists counterparties_prevent_delete_movements on public.counterparties","create trigger counterparties_prevent_delete_movements
before delete on public.counterparties
for each row execute function public.prevent_counterparty_delete_with_movements()","-- ---------------------------------------------------------------------------
-- Reversal engine — preserve counterparty_id
-- ---------------------------------------------------------------------------

create or replace function public.reverse_journal_entry(
  p_entry_id uuid,
  p_reason text
)
returns public.journal_entries
language plpgsql
security definer
set search_path = ''''
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
    raise exception ''authentication required'';
  end if;

  select * into v_orig
  from public.journal_entries
  where id = p_entry_id
  for update;

  if v_orig.id is null then
    raise exception ''journal entry not found'';
  end if;

  if not public.has_org_role(
    v_orig.organization_id,
    array[''owner'',''admin'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role to reverse journal entries'';
  end if;

  if v_orig.status <> ''POSTED'' then
    raise exception ''only posted entries can be reversed'';
  end if;

  if v_orig.reversed_by_entry_id is not null then
    raise exception ''entry already reversed'';
  end if;

  if trim(coalesce(p_reason, '''')) = '''' then
    raise exception ''reversal reason is required'';
  end if;

  v_fy_id := v_orig.fiscal_year_id;

  perform set_config(''accounting.engine_write'', ''1'', true);

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
    ''Reversión: '' || coalesce(v_orig.description, v_orig.entry_number::text),
    ''DRAFT'',
    ''REVERSAL'',
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
      coalesce(r.description, ''Reversión''),
      r.credit,
      r.debit,
      r.line_number,
      coalesce(r.metadata, ''{}''::jsonb) || jsonb_build_object(''reversed_from_line_id'', r.id)
    );
  end loop;

  select count(*)::int, coalesce(sum(debit), 0), coalesce(sum(credit), 0)
  into v_line_count, v_debit, v_credit
  from public.journal_entry_lines
  where journal_entry_id = v_rev.id;

  if v_line_count < 2 or v_debit <> v_credit or v_debit <= 0 then
    raise exception ''reversal entry failed balance validation'';
  end if;

  v_number := public.next_journal_entry_number(v_orig.organization_id, v_fy_id);

  update public.journal_entries
  set
    status = ''POSTED'',
    entry_number = v_number,
    posted_by = v_uid,
    posted_at = timezone(''utc'', now())
  where id = v_rev.id
  returning * into v_rev;

  update public.journal_entries
  set
    status = ''REVERSED'',
    reversed_by_entry_id = v_rev.id
  where id = v_orig.id;

  perform set_config(''accounting.engine_write'', ''0'', true);

  perform public.accounting_write_audit(
    v_orig.organization_id,
    v_uid,
    ''journal.reversed'',
    ''journal_entry'',
    v_orig.id::text,
    ''reverse'',
    jsonb_build_object(
      ''original_entry_number'', v_orig.entry_number,
      ''reversal_entry_id'', v_rev.id,
      ''reversal_entry_number'', v_rev.entry_number,
      ''reason'', trim(p_reason)
    )
  );

  return v_rev;
end;
$$","revoke all on function public.reverse_journal_entry(uuid, text) from public","grant execute on function public.reverse_journal_entry(uuid, text) to authenticated"}', 'phase3_counterparty_accounting_dimension'),
	('20260331120000', '{"-- Phase 3 — Counterparty RLS + grants (STAGING)

alter table public.counterparties enable row level security","alter table public.counterparty_roles enable row level security","alter table public.counterparty_fiscal_profiles enable row level security","alter table public.counterparty_addresses enable row level security","alter table public.counterparty_contacts enable row level security","-- ---------------------------------------------------------------------------
-- counterparties
-- ---------------------------------------------------------------------------

drop policy if exists counterparties_select on public.counterparties","create policy counterparties_select
  on public.counterparties for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists counterparties_insert on public.counterparties","create policy counterparties_insert
  on public.counterparties for insert to authenticated
  with check ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","drop policy if exists counterparties_update on public.counterparties","create policy counterparties_update
  on public.counterparties for update to authenticated
  using ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","drop policy if exists counterparties_delete on public.counterparties","create policy counterparties_delete
  on public.counterparties for delete to authenticated
  using ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- counterparty_roles
-- ---------------------------------------------------------------------------

drop policy if exists counterparty_roles_select on public.counterparty_roles","create policy counterparty_roles_select
  on public.counterparty_roles for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists counterparty_roles_insert on public.counterparty_roles","create policy counterparty_roles_insert
  on public.counterparty_roles for insert to authenticated
  with check ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","drop policy if exists counterparty_roles_delete on public.counterparty_roles","create policy counterparty_roles_delete
  on public.counterparty_roles for delete to authenticated
  using ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- counterparty_fiscal_profiles
-- ---------------------------------------------------------------------------

drop policy if exists counterparty_fiscal_profiles_select on public.counterparty_fiscal_profiles","create policy counterparty_fiscal_profiles_select
  on public.counterparty_fiscal_profiles for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists counterparty_fiscal_profiles_insert on public.counterparty_fiscal_profiles","create policy counterparty_fiscal_profiles_insert
  on public.counterparty_fiscal_profiles for insert to authenticated
  with check ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[]
  )))","drop policy if exists counterparty_fiscal_profiles_update on public.counterparty_fiscal_profiles","create policy counterparty_fiscal_profiles_update
  on public.counterparty_fiscal_profiles for update to authenticated
  using ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- counterparty_addresses
-- ---------------------------------------------------------------------------

drop policy if exists counterparty_addresses_select on public.counterparty_addresses","create policy counterparty_addresses_select
  on public.counterparty_addresses for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists counterparty_addresses_insert on public.counterparty_addresses","create policy counterparty_addresses_insert
  on public.counterparty_addresses for insert to authenticated
  with check ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","drop policy if exists counterparty_addresses_update on public.counterparty_addresses","create policy counterparty_addresses_update
  on public.counterparty_addresses for update to authenticated
  using ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","drop policy if exists counterparty_addresses_delete on public.counterparty_addresses","create policy counterparty_addresses_delete
  on public.counterparty_addresses for delete to authenticated
  using ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- counterparty_contacts
-- ---------------------------------------------------------------------------

drop policy if exists counterparty_contacts_select on public.counterparty_contacts","create policy counterparty_contacts_select
  on public.counterparty_contacts for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists counterparty_contacts_insert on public.counterparty_contacts","create policy counterparty_contacts_insert
  on public.counterparty_contacts for insert to authenticated
  with check ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","drop policy if exists counterparty_contacts_update on public.counterparty_contacts","create policy counterparty_contacts_update
  on public.counterparty_contacts for update to authenticated
  using ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

grant select, insert, update, delete on public.counterparties to authenticated","grant select, insert, delete on public.counterparty_roles to authenticated","grant select, insert, update on public.counterparty_fiscal_profiles to authenticated","grant select, insert, update, delete on public.counterparty_addresses to authenticated","grant select, insert, update on public.counterparty_contacts to authenticated","revoke all on public.counterparties from anon","revoke all on public.counterparty_roles from anon","revoke all on public.counterparty_fiscal_profiles from anon","revoke all on public.counterparty_addresses from anon","revoke all on public.counterparty_contacts from anon","-- ---------------------------------------------------------------------------
-- STAGING synthetic fixtures (clearly fake tax IDs)
-- ---------------------------------------------------------------------------

do $$
declare
  v_org_id uuid;
  v_fc_id uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_c3 uuid;
begin
  select id into v_org_id
  from public.organizations
  where legal_name ilike ''%demo%'' or commercial_name ilike ''%demo%''
  order by created_at
  limit 1;

  if v_org_id is null then
    select id into v_org_id from public.organizations order by created_at limit 1;
  end if;

  if v_org_id is null then
    raise notice ''phase3 fixtures skipped: no organization'';
    return;
  end if;

  select id into v_fc_id
  from public.fiscal_conditions
  where code = ''responsable_inscripto''
  limit 1;

  -- Synthetic CUITs (valid check digit, non-real entities)
  insert into public.counterparties (
    organization_id, entity_type, legal_name, trade_name,
    tax_id_type, tax_id, email, phone, is_active
  ) values (
    v_org_id, ''LEGAL_ENTITY'', ''Cliente Demo Uno SA'', ''Demo Uno'',
    ''CUIT'', ''30-99999900-6'', ''cliente.demo@example.invalid'', ''+54 11 4000-0001'', true
  )
  on conflict do nothing
  returning id into v_c1;

  if v_c1 is null then
    select id into v_c1 from public.counterparties
    where organization_id = v_org_id and legal_name = ''Cliente Demo Uno SA'';
  end if;

  insert into public.counterparty_roles (counterparty_id, organization_id, role)
  values (v_c1, v_org_id, ''CUSTOMER'')
  on conflict do nothing;

  insert into public.counterparty_fiscal_profiles (
    counterparty_id, organization_id, fiscal_condition_id,
    fiscal_address, province, city, postal_code
  ) values (
    v_c1, v_org_id, v_fc_id,
    ''Av. Demo 100'', ''CABA'', ''CABA'', ''C1000''
  )
  on conflict (counterparty_id) do nothing;

  insert into public.counterparties (
    organization_id, entity_type, legal_name, trade_name,
    tax_id_type, tax_id, email, phone, is_active
  ) values (
    v_org_id, ''LEGAL_ENTITY'', ''Proveedor Demo Dos SRL'', ''Demo Dos'',
    ''CUIT'', ''30-99999901-4'', ''proveedor.demo@example.invalid'', ''+54 11 4000-0002'', true
  )
  on conflict do nothing
  returning id into v_c2;

  if v_c2 is null then
    select id into v_c2 from public.counterparties
    where organization_id = v_org_id and legal_name = ''Proveedor Demo Dos SRL'';
  end if;

  insert into public.counterparty_roles (counterparty_id, organization_id, role)
  values (v_c2, v_org_id, ''SUPPLIER'')
  on conflict do nothing;

  insert into public.counterparties (
    organization_id, entity_type, legal_name, trade_name,
    tax_id_type, tax_id, email, phone, is_active
  ) values (
    v_org_id, ''LEGAL_ENTITY'', ''Contraparte Demo Mixta SA'', ''Mixta Demo'',
    ''CUIT'', ''30-99999902-2'', ''mixta.demo@example.invalid'', ''+54 11 4000-0003'', true
  )
  on conflict do nothing
  returning id into v_c3;

  if v_c3 is null then
    select id into v_c3 from public.counterparties
    where organization_id = v_org_id and legal_name = ''Contraparte Demo Mixta SA'';
  end if;

  insert into public.counterparty_roles (counterparty_id, organization_id, role)
  values
    (v_c3, v_org_id, ''CUSTOMER''),
    (v_c3, v_org_id, ''SUPPLIER'')
  on conflict do nothing;

  raise notice ''phase3 fixtures applied for org %'', v_org_id;
end $$"}', 'phase3_counterparties_security'),
	('20260331130000', '{"-- Phase 3 fix — restore reverse_journal_entry signature + counterparty_id copy

create or replace function public.reverse_journal_entry(
  p_original_entry_id uuid,
  p_reversal_date date,
  p_reason text
)
returns public.journal_entries
language plpgsql
security definer
set search_path = ''''
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
    raise exception ''not authenticated'';
  end if;

  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception ''reversal reason is required'';
  end if;

  select * into v_orig
  from public.journal_entries
  where id = p_original_entry_id
  for update;

  if not found then
    raise exception ''journal entry not found'';
  end if;

  if not public.is_org_member(v_orig.organization_id) then
    raise exception ''not a member of organization'';
  end if;

  if not public.has_org_role(
    v_orig.organization_id,
    array[''owner'',''admin'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role to reverse journal entries'';
  end if;

  if v_orig.status <> ''POSTED'' then
    raise exception ''only POSTED entries can be reversed'';
  end if;

  if v_orig.reversed_by_entry_id is not null then
    raise exception ''entry already reversed'';
  end if;

  select period_id, fiscal_year_id into v_period_id, v_fy_id
  from public.resolve_open_period(v_orig.organization_id, p_reversal_date);

  if v_period_id is null then
    raise exception ''no OPEN period (and OPEN fiscal year) covers reversal_date'';
  end if;

  perform set_config(''accounting.engine_write'', ''1'', true);

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
    ''Reversión de asiento '' || coalesce(v_orig.entry_number, v_orig.id::text) || '': '' || v_orig.description,
    ''DRAFT'',
    ''SYSTEM'',
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
      coalesce(r.description, ''Reversión''),
      r.credit,
      r.debit,
      r.line_number,
      coalesce(r.metadata, ''{}''::jsonb) || jsonb_build_object(''reversed_from_line_id'', r.id)
    );
  end loop;

  select count(*)::int, coalesce(sum(debit), 0), coalesce(sum(credit), 0)
  into v_line_count, v_debit, v_credit
  from public.journal_entry_lines
  where journal_entry_id = v_rev.id;

  if v_line_count < 2 or v_debit <> v_credit or v_debit <= 0 then
    raise exception ''reversal entry failed balance validation'';
  end if;

  v_number := public.next_journal_entry_number(v_orig.organization_id, v_fy_id);

  update public.journal_entries
  set
    status = ''POSTED'',
    entry_number = v_number,
    posted_by = v_uid,
    posted_at = timezone(''utc'', now())
  where id = v_rev.id
  returning * into v_rev;

  update public.journal_entries
  set
    status = ''REVERSED'',
    reversed_by_entry_id = v_rev.id
  where id = v_orig.id;

  perform set_config(''accounting.engine_write'', ''0'', true);

  perform public.accounting_write_audit(
    v_orig.organization_id,
    v_uid,
    ''journal.reversed'',
    ''journal_entry'',
    v_orig.id::text,
    ''reverse'',
    jsonb_build_object(
      ''original_entry_number'', v_orig.entry_number,
      ''reversal_entry_id'', v_rev.id,
      ''reversal_entry_number'', v_rev.entry_number,
      ''reason'', trim(p_reason)
    )
  );

  return v_rev;
end;
$$","revoke all on function public.reverse_journal_entry(uuid, date, text) from public","grant execute on function public.reverse_journal_entry(uuid, date, text) to authenticated"}', 'phase3_fix_reversal_engine'),
	('20260331140000', '{"-- Phase 3 final hardening — security + performance (STAGING)
-- Project: rpcpdrzbcclofvjpgldb

-- ---------------------------------------------------------------------------
-- 1. Remove obsolete two-argument reversal overload (accidental Phase 3 artifact)
-- Canonical signature: reverse_journal_entry(uuid, date, text)
-- ---------------------------------------------------------------------------

drop function if exists public.reverse_journal_entry(uuid, text)","-- ---------------------------------------------------------------------------
-- 2. Minimum privilege — revoke anon table access on private accounting tables
-- ---------------------------------------------------------------------------

revoke all on table public.journal_entries from anon","revoke all on table public.journal_entry_lines from anon","revoke all on table public.accounts from anon","revoke all on table public.accounting_periods from anon","revoke all on table public.accounting_fiscal_years from anon","revoke all on table public.accounting_sequences from anon","-- Preserve authenticated access (Supabase default + Phase 2 RLS)
grant select, insert, update, delete on table public.journal_entries to authenticated","grant select, insert, update, delete on table public.journal_entry_lines to authenticated","grant select, insert, update, delete on table public.accounts to authenticated","grant select, insert, update, delete on table public.accounting_periods to authenticated","grant select, insert, update, delete on table public.accounting_fiscal_years to authenticated","grant select on table public.accounting_sequences to authenticated","-- ---------------------------------------------------------------------------
-- 3. Covering indexes for unindexed foreign keys (Performance Advisor)
-- ---------------------------------------------------------------------------

create index if not exists counterparties_created_by_idx
  on public.counterparties (created_by)","create index if not exists counterparty_addresses_organization_id_idx
  on public.counterparty_addresses (organization_id)","create index if not exists counterparty_contacts_organization_id_idx
  on public.counterparty_contacts (organization_id)","create index if not exists counterparty_fiscal_profiles_fiscal_condition_id_idx
  on public.counterparty_fiscal_profiles (fiscal_condition_id)","create index if not exists counterparty_fiscal_profiles_organization_id_idx
  on public.counterparty_fiscal_profiles (organization_id)","create index if not exists counterparty_roles_created_by_idx
  on public.counterparty_roles (created_by)"}', 'phase3_hardening_security'),
	('20260401100000', '{"-- Phase 4 — Sales core (STAGING)
-- Commercial documents only — NOT fiscal invoices

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.sales_document_type as enum (''QUOTE'', ''SALES_ORDER'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.sales_document_status as enum (
    ''DRAFT'', ''SENT'', ''ACCEPTED'', ''REJECTED'', ''CANCELLED'', ''CONVERTED'',
    ''CONFIRMED'', ''READY_TO_INVOICE''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.sales_discount_input_mode as enum (''PERCENT'', ''AMOUNT'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.sales_line_unit_code as enum (
    ''UNIT'', ''HOUR'', ''KG'', ''M'', ''OTHER''
  );
exception when duplicate_object then null;
end $$","-- Branch composite FK support
alter table public.branches
  drop constraint if exists branches_org_id_unique","alter table public.branches
  add constraint branches_org_id_unique unique (organization_id, id)","-- ---------------------------------------------------------------------------
-- sales_document_sequences
-- ---------------------------------------------------------------------------

create table public.sales_document_sequences (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  document_type public.sales_document_type not null,
  sequence_year int not null check (sequence_year >= 2000 and sequence_year <= 2100),
  last_value bigint not null default 0 check (last_value >= 0),
  updated_at timestamptz not null default timezone(''utc'', now()),
  primary key (organization_id, document_type, sequence_year)
)","-- ---------------------------------------------------------------------------
-- sales_documents
-- ---------------------------------------------------------------------------

create table public.sales_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  document_type public.sales_document_type not null,
  internal_number text not null,
  counterparty_id uuid not null,
  status public.sales_document_status not null default ''DRAFT'',
  document_date date not null default (timezone(''utc'', now()))::date,
  valid_until date,
  expected_delivery_date date,
  currency_code text not null default ''ARS'' check (currency_code ~ ''^[A-Z]{3}$''),
  description text,
  customer_reference text,
  payment_terms_text text,
  payment_due_days int check (payment_due_days is null or payment_due_days >= 0),
  notes text,
  internal_notes text,
  source_document_id uuid references public.sales_documents (id) on delete restrict,
  converted_to_order_id uuid unique,
  counterparty_snapshot jsonb not null default ''{}''::jsonb,
  subtotal numeric(19, 4) not null default 0 check (subtotal >= 0),
  discount_total numeric(19, 4) not null default 0 check (discount_total >= 0),
  total numeric(19, 4) not null default 0 check (total >= 0),
  is_commercially_frozen boolean not null default false,
  created_by uuid references auth.users (id),
  confirmed_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
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
)","create index sales_documents_org_type_status_idx
  on public.sales_documents (organization_id, document_type, status)","create index sales_documents_org_date_idx
  on public.sales_documents (organization_id, document_date desc)","create index sales_documents_org_number_idx
  on public.sales_documents (organization_id, internal_number)","create index sales_documents_counterparty_idx
  on public.sales_documents (counterparty_id)","create index sales_documents_source_idx
  on public.sales_documents (source_document_id)
  where source_document_id is not null","alter table public.sales_documents
  add constraint sales_documents_converted_order_fk
  foreign key (converted_to_order_id)
  references public.sales_documents (id)
  on delete restrict","create trigger sales_documents_set_updated_at
before update on public.sales_documents
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- sales_document_lines
-- ---------------------------------------------------------------------------

create table public.sales_document_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  sales_document_id uuid not null references public.sales_documents (id) on delete cascade,
  line_number int not null check (line_number > 0),
  description text not null check (length(trim(description)) >= 1),
  quantity numeric(18, 4) not null check (quantity > 0),
  unit_code public.sales_line_unit_code not null default ''UNIT'',
  unit_price numeric(19, 4) not null check (unit_price >= 0),
  discount_input_mode public.sales_discount_input_mode not null default ''PERCENT'',
  discount_percent numeric(7, 4) not null default 0 check (discount_percent >= 0 and discount_percent <= 100),
  discount_amount numeric(19, 4) not null default 0 check (discount_amount >= 0),
  line_subtotal numeric(19, 4) not null default 0 check (line_subtotal >= 0),
  line_total numeric(19, 4) not null default 0 check (line_total >= 0),
  notes text,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (sales_document_id, line_number),
  constraint sales_document_lines_org_doc_fk
    foreign key (organization_id, sales_document_id)
    references public.sales_documents (organization_id, id)
    on delete cascade
)","create index sales_document_lines_document_idx
  on public.sales_document_lines (sales_document_id)","create trigger sales_document_lines_set_updated_at
before update on public.sales_document_lines
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- Status validation per document type
-- ---------------------------------------------------------------------------

create or replace function public.validate_sales_document_status_for_type()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if new.document_type = ''QUOTE'' then
    if new.status not in (''DRAFT'', ''SENT'', ''ACCEPTED'', ''REJECTED'', ''CANCELLED'', ''CONVERTED'') then
      raise exception ''invalid quote status: %'', new.status;
    end if;
  elsif new.document_type = ''SALES_ORDER'' then
    if new.status not in (''DRAFT'', ''CONFIRMED'', ''READY_TO_INVOICE'', ''CANCELLED'') then
      raise exception ''invalid sales order status: %'', new.status;
    end if;
  end if;
  return new;
end;
$$","create trigger sales_documents_validate_status
before insert or update of status, document_type on public.sales_documents
for each row execute function public.validate_sales_document_status_for_type()","-- ---------------------------------------------------------------------------
-- Line discount + totals (authoritative)
-- ---------------------------------------------------------------------------

create or replace function public.recalculate_sales_line_amounts()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  v_subtotal numeric(19, 4);
  v_discount numeric(19, 4);
begin
  v_subtotal := round(new.quantity * new.unit_price, 4);

  if new.discount_input_mode = ''PERCENT'' then
    if new.discount_percent < 0 or new.discount_percent > 100 then
      raise exception ''invalid discount percent'';
    end if;
    v_discount := round(v_subtotal * new.discount_percent / 100, 4);
    new.discount_amount := v_discount;
  else
    v_discount := round(new.discount_amount, 4);
    if v_discount < 0 then
      raise exception ''discount amount cannot be negative'';
    end if;
    if v_discount > v_subtotal then
      raise exception ''discount cannot exceed line subtotal'';
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
    raise exception ''line total cannot be negative'';
  end if;
  return new;
end;
$$","create trigger sales_document_lines_recalc
before insert or update on public.sales_document_lines
for each row execute function public.recalculate_sales_line_amounts()","create or replace function public.refresh_sales_document_totals(p_document_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''''
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
$$","create or replace function public.sales_document_lines_refresh_header()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if tg_op = ''DELETE'' then
    perform public.refresh_sales_document_totals(old.sales_document_id);
    return old;
  end if;
  perform public.refresh_sales_document_totals(new.sales_document_id);
  return new;
end;
$$","create trigger sales_document_lines_refresh_header_trg
after insert or update or delete on public.sales_document_lines
for each row execute function public.sales_document_lines_refresh_header()","-- ---------------------------------------------------------------------------
-- Customer validation helper
-- ---------------------------------------------------------------------------

create or replace function public.validate_sales_customer(
  p_organization_id uuid,
  p_counterparty_id uuid
)
returns void
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  v_active boolean;
  v_has_customer boolean;
begin
  select c.is_active into v_active
  from public.counterparties c
  where c.id = p_counterparty_id and c.organization_id = p_organization_id;

  if v_active is null then
    raise exception ''counterparty not found'';
  end if;
  if not v_active then
    raise exception ''customer is inactive'';
  end if;

  select exists (
    select 1 from public.counterparty_roles r
    where r.counterparty_id = p_counterparty_id
      and r.organization_id = p_organization_id
      and r.role = ''CUSTOMER''
  ) into v_has_customer;

  if not v_has_customer then
    raise exception ''counterparty must have CUSTOMER role'';
  end if;
end;
$$","-- ---------------------------------------------------------------------------
-- Counterparty snapshot builder
-- ---------------------------------------------------------------------------

create or replace function public.build_counterparty_snapshot(
  p_organization_id uuid,
  p_counterparty_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''''
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
    raise exception ''counterparty not found'';
  end if;

  select fc.name_business into v_fc_name
  from public.counterparty_fiscal_profiles fp
  left join public.fiscal_conditions fc on fc.id = fp.fiscal_condition_id
  where fp.counterparty_id = p_counterparty_id;

  select coalesce(
    nullif(trim(concat_ws('' '', a.street, a.number, a.city, a.province)), ''''),
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
    ''legal_name'', v_cp.legal_name,
    ''trade_name'', v_cp.trade_name,
    ''tax_id_type'', v_cp.tax_id_type,
    ''tax_id'', v_cp.tax_id,
    ''tax_id_normalized'', v_cp.tax_id_normalized,
    ''fiscal_condition_business'', v_fc_name,
    ''commercial_address'', v_addr,
    ''snapshot_at'', timezone(''utc'', now())
  );
end;
$$","-- ---------------------------------------------------------------------------
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
set search_path = ''''
as $$
declare
  v_year int := extract(year from p_document_date)::int;
  v_seq bigint;
  v_prefix text;
begin
  if p_document_type = ''QUOTE'' then
    v_prefix := ''PRES'';
  else
    v_prefix := ''PED'';
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
  set last_value = v_seq, updated_at = timezone(''utc'', now())
  where organization_id = p_organization_id
    and document_type = p_document_type
    and sequence_year = v_year;

  return v_prefix || ''-'' || v_year::text || ''-'' || lpad(v_seq::text, 6, ''0'');
end;
$$","-- ---------------------------------------------------------------------------
-- Commercial freeze guards
-- ---------------------------------------------------------------------------

create or replace function public.prevent_frozen_sales_document_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if tg_op = ''DELETE'' then
    if old.is_commercially_frozen then
      if current_setting(''sales.engine_write'', true) is distinct from ''1'' then
        raise exception ''frozen sales document cannot be deleted'';
      end if;
    end if;
    return old;
  end if;

  if old.is_commercially_frozen
    and current_setting(''sales.engine_write'', true) is distinct from ''1'' then
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
      raise exception ''commercial fields are frozen on this document'';
    end if;
  end if;

  return new;
end;
$$","create trigger sales_documents_prevent_frozen_mutation
before update or delete on public.sales_documents
for each row execute function public.prevent_frozen_sales_document_mutation()","create or replace function public.prevent_frozen_sales_line_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  v_frozen boolean;
  v_status public.sales_document_status;
begin
  select is_commercially_frozen, status
    into v_frozen, v_status
  from public.sales_documents
  where id = coalesce(new.sales_document_id, old.sales_document_id);

  if v_frozen and current_setting(''sales.engine_write'', true) is distinct from ''1'' then
    raise exception ''lines are frozen on this document'';
  end if;

  if v_status <> ''DRAFT'' and tg_op <> ''DELETE'' then
    if current_setting(''sales.engine_write'', true) is distinct from ''1'' then
      raise exception ''cannot modify lines on non-draft document'';
    end if;
  end if;

  if tg_op = ''DELETE'' then return old; end if;
  return new;
end;
$$","create trigger sales_document_lines_prevent_frozen_mutation
before insert or update or delete on public.sales_document_lines
for each row execute function public.prevent_frozen_sales_line_mutation()","-- Line tenant consistency
create or replace function public.validate_sales_line_tenancy()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  doc_org uuid;
begin
  select organization_id into doc_org
  from public.sales_documents where id = new.sales_document_id;
  if doc_org is null then raise exception ''sales document not found''; end if;
  if new.organization_id <> doc_org then
    raise exception ''line organization must match document'';
  end if;
  return new;
end;
$$","create trigger sales_document_lines_validate_tenancy
before insert or update on public.sales_document_lines
for each row execute function public.validate_sales_line_tenancy()","revoke all on function public.refresh_sales_document_totals(uuid) from public","grant execute on function public.refresh_sales_document_totals(uuid) to authenticated","revoke all on function public.validate_sales_customer(uuid, uuid) from public","grant execute on function public.validate_sales_customer(uuid, uuid) to authenticated","revoke all on function public.build_counterparty_snapshot(uuid, uuid) from public","grant execute on function public.build_counterparty_snapshot(uuid, uuid) to authenticated","revoke all on function public.next_sales_internal_number(uuid, public.sales_document_type, date) from public","grant execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) to authenticated"}', 'phase4_sales_core'),
	('20260401110000', '{"-- Phase 4 — Sales transition RPCs (STAGING)

create or replace function public.sales_assert_role(
  p_organization_id uuid,
  p_roles public.member_role[]
)
returns void
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if not public.has_org_role(p_organization_id, p_roles) then
    raise exception ''insufficient role for sales action'';
  end if;
end;
$$","create or replace function public.sales_write_audit(
  p_org_id uuid,
  p_uid uuid,
  p_event text,
  p_entity_id uuid,
  p_action text,
  p_metadata jsonb default ''{}''::jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  insert into public.audit_events (
    organization_id, actor_user_id, event_type, entity_type, entity_id, action, metadata
  ) values (
    p_org_id, p_uid, p_event, ''sales_document'', p_entity_id::text, p_action, p_metadata
  );
end;
$$","-- ---------------------------------------------------------------------------
-- send_quote — freeze on SENT + snapshot at send time
-- ---------------------------------------------------------------------------

create or replace function public.send_quote(p_document_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
  v_line_count int;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_doc from public.sales_documents where id = p_document_id for update;
  if v_doc.id is null then raise exception ''document not found''; end if;
  if v_doc.document_type <> ''QUOTE'' then raise exception ''not a quote''; end if;

  perform public.sales_assert_role(v_doc.organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]);

  if v_doc.status <> ''DRAFT'' then raise exception ''only draft quotes can be sent''; end if;

  select count(*) into v_line_count from public.sales_document_lines where sales_document_id = v_doc.id;
  if v_line_count < 1 then raise exception ''quote must have at least one line''; end if;

  perform public.validate_sales_customer(v_doc.organization_id, v_doc.counterparty_id);
  perform public.refresh_sales_document_totals(v_doc.id);

  perform set_config(''sales.engine_write'', ''1'', true);

  update public.sales_documents
  set
    status = ''SENT'',
    counterparty_snapshot = public.build_counterparty_snapshot(v_doc.organization_id, v_doc.counterparty_id),
    is_commercially_frozen = true
  where id = v_doc.id
  returning * into v_doc;

  perform set_config(''sales.engine_write'', ''0'', true);

  perform public.sales_write_audit(
    v_doc.organization_id, v_uid, ''sales.quote.sent'', v_doc.id, ''send'',
    jsonb_build_object(''internal_number'', v_doc.internal_number, ''total'', v_doc.total, ''currency_code'', v_doc.currency_code)
  );

  return v_doc;
end;
$$","-- ---------------------------------------------------------------------------
-- accept_quote — reuse frozen snapshot
-- ---------------------------------------------------------------------------

create or replace function public.accept_quote(p_document_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_doc from public.sales_documents where id = p_document_id for update;
  if v_doc.id is null then raise exception ''document not found''; end if;
  if v_doc.document_type <> ''QUOTE'' then raise exception ''not a quote''; end if;

  perform public.sales_assert_role(v_doc.organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]);

  if v_doc.status <> ''SENT'' then raise exception ''only sent quotes can be accepted''; end if;

  if v_doc.valid_until is not null and v_doc.valid_until < (timezone(''utc'', now()))::date then
    raise exception ''quote is expired'';
  end if;

  perform set_config(''sales.engine_write'', ''1'', true);

  update public.sales_documents
  set status = ''ACCEPTED'', confirmed_by = v_uid, confirmed_at = timezone(''utc'', now())
  where id = v_doc.id
  returning * into v_doc;

  perform set_config(''sales.engine_write'', ''0'', true);

  perform public.sales_write_audit(
    v_doc.organization_id, v_uid, ''sales.quote.accepted'', v_doc.id, ''accept'',
    jsonb_build_object(''internal_number'', v_doc.internal_number)
  );

  return v_doc;
end;
$$","create or replace function public.reject_quote(
  p_document_id uuid,
  p_reason text default null
)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_doc from public.sales_documents where id = p_document_id for update;
  if v_doc.document_type <> ''QUOTE'' then raise exception ''not a quote''; end if;
  perform public.sales_assert_role(v_doc.organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]);
  if v_doc.status not in (''SENT'', ''ACCEPTED'') then raise exception ''quote cannot be rejected from this status''; end if;

  perform set_config(''sales.engine_write'', ''1'', true);
  update public.sales_documents
  set status = ''REJECTED'', cancelled_at = timezone(''utc'', now()), cancel_reason = nullif(trim(p_reason), '''')
  where id = p_document_id returning * into v_doc;
  perform set_config(''sales.engine_write'', ''0'', true);

  perform public.sales_write_audit(v_doc.organization_id, v_uid, ''sales.quote.rejected'', v_doc.id, ''reject'', ''{}''::jsonb);
  return v_doc;
end;
$$","create or replace function public.cancel_sales_document(
  p_document_id uuid,
  p_reason text default null
)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_doc from public.sales_documents where id = p_document_id for update;
  perform public.sales_assert_role(v_doc.organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]);

  if v_doc.document_type = ''QUOTE'' and v_doc.status in (''CONVERTED'', ''REJECTED'', ''CANCELLED'') then
    raise exception ''quote cannot be cancelled'';
  end if;
  if v_doc.document_type = ''SALES_ORDER'' and v_doc.status in (''READY_TO_INVOICE'', ''CANCELLED'') then
    raise exception ''order cannot be cancelled'';
  end if;

  perform set_config(''sales.engine_write'', ''1'', true);
  update public.sales_documents
  set status = ''CANCELLED'', cancelled_at = timezone(''utc'', now()), cancel_reason = nullif(trim(p_reason), '''')
  where id = p_document_id returning * into v_doc;
  perform set_config(''sales.engine_write'', ''0'', true);

  perform public.sales_write_audit(
    v_doc.organization_id, v_uid,
    case when v_doc.document_type = ''QUOTE'' then ''sales.quote.cancelled'' else ''sales.order.cancelled'' end,
    v_doc.id, ''cancel'', ''{}''::jsonb
  );
  return v_doc;
end;
$$","-- ---------------------------------------------------------------------------
-- convert_quote_to_order — idempotent
-- ---------------------------------------------------------------------------

create or replace function public.convert_quote_to_order(p_quote_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_quote public.sales_documents;
  v_order public.sales_documents;
  v_number text;
  r record;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_quote from public.sales_documents where id = p_quote_id for update;
  if v_quote.document_type <> ''QUOTE'' then raise exception ''not a quote''; end if;

  perform public.sales_assert_role(v_quote.organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]);

  if v_quote.converted_to_order_id is not null then
    select * into v_order from public.sales_documents where id = v_quote.converted_to_order_id;
    return v_order;
  end if;

  if v_quote.status <> ''ACCEPTED'' then raise exception ''only accepted quotes can be converted''; end if;

  perform public.validate_sales_customer(v_quote.organization_id, v_quote.counterparty_id);

  v_number := public.next_sales_internal_number(v_quote.organization_id, ''SALES_ORDER'', v_quote.document_date);

  perform set_config(''sales.engine_write'', ''1'', true);

  insert into public.sales_documents (
    organization_id, branch_id, document_type, internal_number, counterparty_id, status,
    document_date, expected_delivery_date, currency_code, description, customer_reference,
    payment_terms_text, payment_due_days, notes, source_document_id,
    counterparty_snapshot, subtotal, discount_total, total,
    is_commercially_frozen, created_by
  ) values (
    v_quote.organization_id, v_quote.branch_id, ''SALES_ORDER'', v_number, v_quote.counterparty_id, ''DRAFT'',
    v_quote.document_date, v_quote.expected_delivery_date, v_quote.currency_code, v_quote.description,
    v_quote.customer_reference, v_quote.payment_terms_text, v_quote.payment_due_days, v_quote.notes,
    v_quote.id, v_quote.counterparty_snapshot, v_quote.subtotal, v_quote.discount_total, v_quote.total,
    true, v_uid
  ) returning * into v_order;

  for r in select * from public.sales_document_lines where sales_document_id = v_quote.id order by line_number loop
    insert into public.sales_document_lines (
      organization_id, sales_document_id, line_number, description, quantity, unit_code,
      unit_price, discount_input_mode, discount_percent, discount_amount,
      line_subtotal, line_total, notes
    ) values (
      r.organization_id, v_order.id, r.line_number, r.description, r.quantity, r.unit_code,
      r.unit_price, r.discount_input_mode, r.discount_percent, r.discount_amount,
      r.line_subtotal, r.line_total, r.notes
    );
  end loop;

  update public.sales_documents
  set status = ''CONVERTED'', converted_to_order_id = v_order.id
  where id = v_quote.id;

  perform set_config(''sales.engine_write'', ''0'', true);

  perform public.sales_write_audit(
    v_quote.organization_id, v_uid, ''sales.quote.converted'', v_quote.id, ''convert'',
    jsonb_build_object(''order_id'', v_order.id, ''order_number'', v_order.internal_number)
  );
  perform public.sales_write_audit(
    v_order.organization_id, v_uid, ''sales.order.created'', v_order.id, ''create'',
    jsonb_build_object(''source_quote_id'', v_quote.id, ''from_conversion'', true)
  );

  return v_order;
end;
$$","-- ---------------------------------------------------------------------------
-- confirm_sales_order — snapshot on confirm for direct orders
-- ---------------------------------------------------------------------------

create or replace function public.confirm_sales_order(p_order_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
  v_lines int;
  v_snapshot jsonb;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_doc from public.sales_documents where id = p_order_id for update;
  if v_doc.document_type <> ''SALES_ORDER'' then raise exception ''not a sales order''; end if;
  perform public.sales_assert_role(v_doc.organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]);
  if v_doc.status <> ''DRAFT'' then raise exception ''only draft orders can be confirmed''; end if;

  perform public.validate_sales_customer(v_doc.organization_id, v_doc.counterparty_id);
  select count(*) into v_lines from public.sales_document_lines where sales_document_id = v_doc.id;
  if v_lines < 1 then raise exception ''order must have at least one line''; end if;

  perform public.refresh_sales_document_totals(v_doc.id);

  if v_doc.source_document_id is null then
    v_snapshot := public.build_counterparty_snapshot(v_doc.organization_id, v_doc.counterparty_id);
  else
    v_snapshot := v_doc.counterparty_snapshot;
  end if;

  perform set_config(''sales.engine_write'', ''1'', true);

  update public.sales_documents
  set
    status = ''CONFIRMED'',
    confirmed_by = v_uid,
    confirmed_at = timezone(''utc'', now()),
    counterparty_snapshot = v_snapshot,
    is_commercially_frozen = true
  where id = v_doc.id returning * into v_doc;

  perform set_config(''sales.engine_write'', ''0'', true);

  perform public.sales_write_audit(
    v_doc.organization_id, v_uid, ''sales.order.confirmed'', v_doc.id, ''confirm'',
    jsonb_build_object(''internal_number'', v_doc.internal_number, ''total'', v_doc.total)
  );

  return v_doc;
end;
$$","create or replace function public.mark_order_ready_to_invoice(p_order_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_doc from public.sales_documents where id = p_order_id for update;
  if v_doc.document_type <> ''SALES_ORDER'' then raise exception ''not a sales order''; end if;
  perform public.sales_assert_role(v_doc.organization_id, array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[]);

  if v_doc.status = ''READY_TO_INVOICE'' then return v_doc; end if;
  if v_doc.status <> ''CONFIRMED'' then raise exception ''only confirmed orders can be marked ready to invoice''; end if;

  perform set_config(''sales.engine_write'', ''1'', true);
  update public.sales_documents set status = ''READY_TO_INVOICE'' where id = p_order_id returning * into v_doc;
  perform set_config(''sales.engine_write'', ''0'', true);

  perform public.sales_write_audit(
    v_doc.organization_id, v_uid, ''sales.order.ready_to_invoice'', v_doc.id, ''ready'',
    jsonb_build_object(''internal_number'', v_doc.internal_number)
  );

  return v_doc;
end;
$$","revoke all on function public.send_quote(uuid) from public","revoke all on function public.accept_quote(uuid) from public","revoke all on function public.reject_quote(uuid, text) from public","revoke all on function public.cancel_sales_document(uuid, text) from public","revoke all on function public.convert_quote_to_order(uuid) from public","revoke all on function public.confirm_sales_order(uuid) from public","revoke all on function public.mark_order_ready_to_invoice(uuid) from public","grant execute on function public.send_quote(uuid) to authenticated","grant execute on function public.accept_quote(uuid) to authenticated","grant execute on function public.reject_quote(uuid, text) to authenticated","grant execute on function public.cancel_sales_document(uuid, text) to authenticated","grant execute on function public.convert_quote_to_order(uuid) to authenticated","grant execute on function public.confirm_sales_order(uuid) to authenticated","grant execute on function public.mark_order_ready_to_invoice(uuid) to authenticated"}', 'phase4_sales_functions'),
	('20260401120000', '{"-- Phase 4 — Sales RLS + grants (STAGING)

alter table public.sales_document_sequences enable row level security","alter table public.sales_documents enable row level security","alter table public.sales_document_lines enable row level security","-- sequences: read only for authenticated members
drop policy if exists sales_document_sequences_select on public.sales_document_sequences","create policy sales_document_sequences_select
  on public.sales_document_sequences for select to authenticated
  using ((select public.is_org_member(organization_id)))","-- sales_documents
drop policy if exists sales_documents_select on public.sales_documents","create policy sales_documents_select
  on public.sales_documents for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists sales_documents_insert on public.sales_documents","create policy sales_documents_insert
  on public.sales_documents for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","drop policy if exists sales_documents_update on public.sales_documents","create policy sales_documents_update
  on public.sales_documents for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","drop policy if exists sales_documents_delete on public.sales_documents","create policy sales_documents_delete
  on public.sales_documents for delete to authenticated
  using (
    status = ''DRAFT''
    and is_commercially_frozen = false
    and (select public.has_org_role(
      organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]
    ))
  )","-- lines
drop policy if exists sales_document_lines_select on public.sales_document_lines","create policy sales_document_lines_select
  on public.sales_document_lines for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists sales_document_lines_insert on public.sales_document_lines","create policy sales_document_lines_insert
  on public.sales_document_lines for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","drop policy if exists sales_document_lines_update on public.sales_document_lines","create policy sales_document_lines_update
  on public.sales_document_lines for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","drop policy if exists sales_document_lines_delete on public.sales_document_lines","create policy sales_document_lines_delete
  on public.sales_document_lines for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","grant select on public.sales_document_sequences to authenticated","grant select, insert, update, delete on public.sales_documents to authenticated","grant select, insert, update, delete on public.sales_document_lines to authenticated","revoke all on public.sales_document_sequences from anon","revoke all on public.sales_documents from anon","revoke all on public.sales_document_lines from anon","revoke all on function public.sales_assert_role(uuid, public.member_role[]) from public","revoke all on function public.sales_write_audit(uuid, uuid, text, uuid, text, jsonb) from public","-- Enable sales feature for staging orgs with synthetic demo counterparties (QA only)
insert into public.organization_features (organization_id, feature_id, status, enabled_at)
select distinct c.organization_id, fc.id, ''enabled''::public.feature_status, timezone(''utc'', now())
from public.counterparties c
inner join public.feature_catalog fc on fc.code = ''sales''
where c.legal_name ilike ''%Demo%''
on conflict (organization_id, feature_id) do update
  set status = excluded.status,
      enabled_at = coalesce(public.organization_features.enabled_at, excluded.enabled_at)"}', 'phase4_sales_security'),
	('20260401130000', '{"-- Phase 4 fix — sequence allocation must bypass sequences RLS (read-only policy)

create or replace function public.next_sales_internal_number(
  p_organization_id uuid,
  p_document_type public.sales_document_type,
  p_document_date date
)
returns text
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_year int := extract(year from p_document_date)::int;
  v_seq bigint;
  v_prefix text;
begin
  if auth.uid() is null then
    raise exception ''not authenticated'';
  end if;

  if not public.is_org_member(p_organization_id) then
    raise exception ''not a member of organization'';
  end if;

  if p_document_type = ''QUOTE'' then
    v_prefix := ''PRES'';
  else
    v_prefix := ''PED'';
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
  set last_value = v_seq, updated_at = timezone(''utc'', now())
  where organization_id = p_organization_id
    and document_type = p_document_type
    and sequence_year = v_year;

  return v_prefix || ''-'' || v_year::text || ''-'' || lpad(v_seq::text, 6, ''0'');
end;
$$","revoke all on function public.next_sales_internal_number(uuid, public.sales_document_type, date) from public","grant execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) to authenticated"}', 'phase4_sales_sequences_fix'),
	('20260401140000', '{"-- Phase 4 final hardening (STAGING)
-- 1) Remove anon/PUBLIC EXECUTE from sales SECURITY DEFINER RPCs
-- 2) Harden next_sales_internal_number authorization
-- 3) Minimal FK covering indexes (no duplicates)

-- ---------------------------------------------------------------------------
-- 1. ACL: revoke PUBLIC + anon; retain authenticated + service_role
-- ---------------------------------------------------------------------------

revoke execute on function public.send_quote(uuid) from public","revoke execute on function public.send_quote(uuid) from anon","grant execute on function public.send_quote(uuid) to authenticated","grant execute on function public.send_quote(uuid) to service_role","revoke execute on function public.accept_quote(uuid) from public","revoke execute on function public.accept_quote(uuid) from anon","grant execute on function public.accept_quote(uuid) to authenticated","grant execute on function public.accept_quote(uuid) to service_role","revoke execute on function public.reject_quote(uuid, text) from public","revoke execute on function public.reject_quote(uuid, text) from anon","grant execute on function public.reject_quote(uuid, text) to authenticated","grant execute on function public.reject_quote(uuid, text) to service_role","revoke execute on function public.cancel_sales_document(uuid, text) from public","revoke execute on function public.cancel_sales_document(uuid, text) from anon","grant execute on function public.cancel_sales_document(uuid, text) to authenticated","grant execute on function public.cancel_sales_document(uuid, text) to service_role","revoke execute on function public.convert_quote_to_order(uuid) from public","revoke execute on function public.convert_quote_to_order(uuid) from anon","grant execute on function public.convert_quote_to_order(uuid) to authenticated","grant execute on function public.convert_quote_to_order(uuid) to service_role","revoke execute on function public.confirm_sales_order(uuid) from public","revoke execute on function public.confirm_sales_order(uuid) from anon","grant execute on function public.confirm_sales_order(uuid) to authenticated","grant execute on function public.confirm_sales_order(uuid) to service_role","revoke execute on function public.mark_order_ready_to_invoice(uuid) from public","revoke execute on function public.mark_order_ready_to_invoice(uuid) from anon","grant execute on function public.mark_order_ready_to_invoice(uuid) to authenticated","grant execute on function public.mark_order_ready_to_invoice(uuid) to service_role","revoke execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) from public","revoke execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) from anon","grant execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) to authenticated","grant execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) to service_role","-- ---------------------------------------------------------------------------
-- 2. Harden next_sales_internal_number
--    Must not burn sequences for arbitrary orgs / read-only members.
--    Requires authenticated identity + sales write roles on the target org.
-- ---------------------------------------------------------------------------

create or replace function public.next_sales_internal_number(
  p_organization_id uuid,
  p_document_type public.sales_document_type,
  p_document_date date
)
returns text
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_year int := extract(year from p_document_date)::int;
  v_seq bigint;
  v_prefix text;
begin
  if v_uid is null then
    raise exception ''not authenticated'';
  end if;

  -- Tenant-scoped: caller must hold a sales write role on the target org
  if not public.has_org_role(
    p_organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  ) then
    raise exception ''insufficient role for sales numbering'';
  end if;

  if p_document_date is null then
    raise exception ''document date required'';
  end if;

  if p_document_type = ''QUOTE'' then
    v_prefix := ''PRES'';
  elsif p_document_type = ''SALES_ORDER'' then
    v_prefix := ''PED'';
  else
    raise exception ''unsupported sales document type'';
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
  set last_value = v_seq, updated_at = timezone(''utc'', now())
  where organization_id = p_organization_id
    and document_type = p_document_type
    and sequence_year = v_year;

  return v_prefix || ''-'' || v_year::text || ''-'' || lpad(v_seq::text, 6, ''0'');
end;
$$","revoke execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) from public","revoke execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) from anon","grant execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) to authenticated","grant execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) to service_role","-- ---------------------------------------------------------------------------
-- 3. Minimal FK covering indexes
--    Inspected existing indexes; do not duplicate.
--    Composite (organization_id, …) covers organization_id single-column FK.
-- ---------------------------------------------------------------------------

-- Covers: sales_document_lines_org_doc_fk + sales_document_lines_organization_id_fkey
-- Existing sales_document_lines_document_idx is (sales_document_id) only — does not cover org leftmost.
create index if not exists sales_document_lines_org_doc_idx
  on public.sales_document_lines (organization_id, sales_document_id)","-- Covers: sales_documents_org_branch_fk
create index if not exists sales_documents_org_branch_idx
  on public.sales_documents (organization_id, branch_id)","-- Covers: sales_documents_org_counterparty_fk
-- Existing sales_documents_counterparty_idx is (counterparty_id) only — does not cover org leftmost.
create index if not exists sales_documents_org_counterparty_idx
  on public.sales_documents (organization_id, counterparty_id)","-- Covers: sales_documents_created_by_fkey
create index if not exists sales_documents_created_by_idx
  on public.sales_documents (created_by)","-- Covers: sales_documents_confirmed_by_fkey
create index if not exists sales_documents_confirmed_by_idx
  on public.sales_documents (confirmed_by)"}', 'phase4_sales_hardening'),
	('20260501100000', '{"-- Phase 5 — Fiscal core (STAGING / HOMOLOGATION)
-- No production ARCA. CAEA disabled by default.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.fiscal_environment as enum (''HOMOLOGATION'', ''PRODUCTION'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.fiscal_document_status as enum (
    ''DRAFT'', ''READY_TO_AUTHORIZE'', ''AUTHORIZING'', ''AUTHORIZED'',
    ''REJECTED'', ''RECONCILIATION_REQUIRED''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.fiscal_accounting_status as enum (
    ''NOT_APPLICABLE'', ''PENDING'', ''POSTED'', ''ERROR'', ''REQUIRES_REVIEW''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.fiscal_authorization_outcome as enum (
    ''APPROVED'', ''REJECTED'', ''TRANSPORT_ERROR'', ''AUTH_ERROR'',
    ''BUSINESS_VALIDATION_ERROR'', ''UNCERTAIN'',
    ''RECONCILED_AUTHORIZED'', ''RECONCILED_NOT_FOUND''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.fiscal_issuance_method as enum (
    ''WSFE_CAE'', ''WSFE_CAEA'', ''OTHER''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.fiscal_credential_status as enum (
    ''ACTIVE'', ''EXPIRING'', ''EXPIRED'', ''REVOKED''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.fiscal_vat_treatment as enum (
    ''TAXED'', ''EXEMPT'', ''NOT_TAXED''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.fiscal_document_class as enum (
    ''A'', ''B'', ''C'', ''M'', ''E'', ''OTHER''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.fiscal_operation_kind as enum (
    ''INVOICE'', ''CREDIT_NOTE'', ''DEBIT_NOTE'', ''OTHER''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.fiscal_rule_status as enum (
    ''DRAFT'', ''REVIEWED'', ''ACTIVE'', ''RETIRED''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.fiscal_relationship_type as enum (
    ''CREDIT_NOTE'', ''DEBIT_NOTE''
  );
exception when duplicate_object then null;
end $$","-- Sales handoff: INVOICED
do $$ begin
  alter type public.sales_document_status add value if not exists ''INVOICED'';
exception when duplicate_object then null;
end $$","-- Feature catalog
insert into public.feature_catalog (code, name, description, category, default_status, sort_order)
values (
  ''fiscal_invoicing'',
  ''Facturación fiscal'',
  ''Emisión electrónica ARCA (CAE). Depende conceptualmente de ventas y contabilidad.'',
  ''contabilidad'',
  ''disabled'',
  105
)
on conflict (code) do nothing","-- ---------------------------------------------------------------------------
-- fiscal_rule_versions
-- ---------------------------------------------------------------------------

create table public.fiscal_rule_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations (id) on delete cascade,
  code text not null,
  version int not null check (version > 0),
  effective_from date not null,
  effective_to date,
  source_reference text not null,
  source_document text,
  status public.fiscal_rule_status not null default ''DRAFT'',
  rules jsonb not null default ''{}''::jsonb,
  reviewed_by uuid references auth.users (id),
  reviewed_at timestamptz,
  activated_by uuid references auth.users (id),
  activated_at timestamptz,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint fiscal_rule_versions_dates check (
    effective_to is null or effective_to >= effective_from
  ),
  unique (organization_id, code, version)
)","create unique index fiscal_rule_versions_global_code_version_uidx
  on public.fiscal_rule_versions (code, version)
  where organization_id is null","create trigger fiscal_rule_versions_set_updated_at
before update on public.fiscal_rule_versions
for each row execute function public.set_updated_at()","-- ACTIVE rules immutable
create or replace function public.prevent_active_fiscal_rule_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if tg_op = ''DELETE'' then
    if old.status = ''ACTIVE'' then
      raise exception ''active fiscal rule versions cannot be deleted'';
    end if;
    return old;
  end if;
  if old.status = ''ACTIVE'' then
    if new.status is distinct from old.status
      or new.rules is distinct from old.rules
      or new.effective_from is distinct from old.effective_from
      or new.effective_to is distinct from old.effective_to
      or new.source_reference is distinct from old.source_reference
      or new.code is distinct from old.code
      or new.version is distinct from old.version
    then
      if current_setting(''fiscal.engine_write'', true) is distinct from ''1'' then
        raise exception ''active fiscal rule versions are immutable; create a new version'';
      end if;
    end if;
  end if;
  return new;
end;
$$","create trigger fiscal_rule_versions_immutable_active
before update or delete on public.fiscal_rule_versions
for each row execute function public.prevent_active_fiscal_rule_mutation()","-- ---------------------------------------------------------------------------
-- fiscal_document_types
-- ---------------------------------------------------------------------------

create table public.fiscal_document_types (
  id uuid primary key default gen_random_uuid(),
  internal_code text not null unique,
  arca_cbte_tipo int not null,
  name text not null,
  document_class public.fiscal_document_class not null,
  operation_kind public.fiscal_operation_kind not null,
  enabled_phase5 boolean not null default false,
  effective_from date not null default ''2000-01-01'',
  effective_to date,
  metadata jsonb not null default ''{}''::jsonb,
  created_at timestamptz not null default timezone(''utc'', now())
)","create index fiscal_document_types_arca_idx on public.fiscal_document_types (arca_cbte_tipo)","-- ---------------------------------------------------------------------------
-- fiscal_parameter_catalogs
-- ---------------------------------------------------------------------------

create table public.fiscal_parameter_catalogs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations (id) on delete cascade,
  environment public.fiscal_environment not null,
  catalog_kind text not null,
  code text not null,
  label text not null,
  valid_from date,
  valid_to date,
  raw jsonb not null default ''{}''::jsonb,
  fetched_at timestamptz not null default timezone(''utc'', now()),
  unique (organization_id, environment, catalog_kind, code)
)","create index fiscal_parameter_catalogs_kind_idx
  on public.fiscal_parameter_catalogs (environment, catalog_kind)","-- ---------------------------------------------------------------------------
-- fiscal_points_of_sale
-- ---------------------------------------------------------------------------

create table public.fiscal_points_of_sale (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  environment public.fiscal_environment not null default ''HOMOLOGATION'',
  arca_point_of_sale int not null check (arca_point_of_sale > 0),
  description text,
  issuance_method public.fiscal_issuance_method not null default ''WSFE_CAE'',
  is_active boolean not null default true,
  effective_from date,
  effective_to date,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (organization_id, environment, arca_point_of_sale),
  constraint fiscal_pos_org_id_unique unique (organization_id, id),
  constraint fiscal_pos_org_branch_fk
    foreign key (organization_id, branch_id)
    references public.branches (organization_id, id)
    on delete restrict
)","create trigger fiscal_points_of_sale_set_updated_at
before update on public.fiscal_points_of_sale
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- fiscal_credential_metadata (NO secrets)
-- ---------------------------------------------------------------------------

create table public.fiscal_credential_metadata (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  environment public.fiscal_environment not null,
  certificate_alias text not null,
  certificate_fingerprint text not null,
  valid_from timestamptz,
  valid_to timestamptz,
  status public.fiscal_credential_status not null default ''ACTIVE'',
  secret_provider text not null default ''env_file'',
  secret_ref text not null,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (organization_id, environment, certificate_fingerprint)
)","create trigger fiscal_credential_metadata_set_updated_at
before update on public.fiscal_credential_metadata
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- fiscal_service_profiles
-- ---------------------------------------------------------------------------

create table public.fiscal_service_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  environment public.fiscal_environment not null default ''HOMOLOGATION'',
  wsaa_service_name text not null default ''wsfe'',
  enabled_methods jsonb not null default ''{\"cae\": true, \"caea\": false}''::jsonb,
  timeouts_ms jsonb not null default ''{\"connect\": 10000, \"request\": 60000}''::jsonb,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (organization_id, environment)
)","create trigger fiscal_service_profiles_set_updated_at
before update on public.fiscal_service_profiles
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- fiscal_documents
-- ---------------------------------------------------------------------------

create table public.fiscal_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  sales_document_id uuid,
  fiscal_environment public.fiscal_environment not null default ''HOMOLOGATION'',
  service_provider text not null default ''ARCA_WSFE'',
  document_type_id uuid not null references public.fiscal_document_types (id),
  document_class public.fiscal_document_class not null,
  arca_cbte_tipo int not null,
  point_of_sale_id uuid not null,
  arca_point_of_sale int not null,
  document_number bigint,
  issue_date date not null,
  counterparty_id uuid not null,
  issuer_snapshot jsonb not null default ''{}''::jsonb,
  receiver_snapshot jsonb not null default ''{}''::jsonb,
  currency_code text not null default ''PES'' check (currency_code ~ ''^[A-Z]{3}$''),
  currency_rate numeric(19, 6) not null default 1 check (currency_rate > 0),
  concept_type int not null default 1 check (concept_type between 1 and 3),
  net_taxed_amount numeric(19, 4) not null default 0 check (net_taxed_amount >= 0),
  net_exempt_amount numeric(19, 4) not null default 0 check (net_exempt_amount >= 0),
  net_untaxed_amount numeric(19, 4) not null default 0 check (net_untaxed_amount >= 0),
  vat_amount numeric(19, 4) not null default 0 check (vat_amount >= 0),
  other_taxes_amount numeric(19, 4) not null default 0 check (other_taxes_amount >= 0),
  total_amount numeric(19, 4) not null default 0 check (total_amount >= 0),
  status public.fiscal_document_status not null default ''DRAFT'',
  accounting_status public.fiscal_accounting_status not null default ''NOT_APPLICABLE'',
  journal_entry_id uuid,
  cae text,
  cae_expiration_date date,
  arca_result jsonb not null default ''{}''::jsonb,
  arca_observations jsonb not null default ''[]''::jsonb,
  authorized_at timestamptz,
  related_fiscal_document_id uuid,
  relationship_type public.fiscal_relationship_type,
  fiscal_rule_version_id uuid not null references public.fiscal_rule_versions (id),
  credential_fingerprint text,
  idempotency_key text not null,
  qr_payload text,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint fiscal_documents_org_id_unique unique (organization_id, id),
  constraint fiscal_documents_idempotency_unique unique (organization_id, idempotency_key),
  constraint fiscal_documents_org_counterparty_fk
    foreign key (organization_id, counterparty_id)
    references public.counterparties (organization_id, id)
    on delete restrict,
  constraint fiscal_documents_org_branch_fk
    foreign key (organization_id, branch_id)
    references public.branches (organization_id, id)
    on delete restrict,
  constraint fiscal_documents_org_pos_fk
    foreign key (organization_id, point_of_sale_id)
    references public.fiscal_points_of_sale (organization_id, id)
    on delete restrict,
  constraint fiscal_documents_sales_fk
    foreign key (sales_document_id)
    references public.sales_documents (id)
    on delete restrict,
  constraint fiscal_documents_related_fk
    foreign key (related_fiscal_document_id)
    references public.fiscal_documents (id)
    on delete restrict,
  constraint fiscal_documents_journal_fk
    foreign key (journal_entry_id)
    references public.journal_entries (id)
    on delete restrict,
  constraint fiscal_documents_ars_rate_check check (
    currency_code not in (''PES'', ''ARS'') or currency_rate = 1
  )
)","create unique index fiscal_documents_primary_invoice_per_order_uidx
  on public.fiscal_documents (organization_id, sales_document_id)
  where sales_document_id is not null and relationship_type is null","create unique index fiscal_documents_voucher_uidx
  on public.fiscal_documents (
    organization_id, fiscal_environment, arca_point_of_sale, arca_cbte_tipo, document_number
  )
  where document_number is not null","create index fiscal_documents_org_status_date_idx
  on public.fiscal_documents (organization_id, status, issue_date desc)","create index fiscal_documents_sales_idx
  on public.fiscal_documents (sales_document_id)
  where sales_document_id is not null","create trigger fiscal_documents_set_updated_at
before update on public.fiscal_documents
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- fiscal_document_lines
-- ---------------------------------------------------------------------------

create table public.fiscal_document_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  fiscal_document_id uuid not null,
  line_number int not null check (line_number > 0),
  source_sales_line_id uuid,
  description text not null check (length(trim(description)) >= 1),
  quantity numeric(18, 4) not null check (quantity > 0),
  unit_price numeric(19, 4) not null check (unit_price >= 0),
  discount_amount numeric(19, 4) not null default 0 check (discount_amount >= 0),
  vat_treatment public.fiscal_vat_treatment not null default ''TAXED'',
  vat_rate_code text,
  vat_rate numeric(7, 4) check (vat_rate is null or (vat_rate >= 0 and vat_rate <= 100)),
  net_amount numeric(19, 4) not null default 0 check (net_amount >= 0),
  vat_amount numeric(19, 4) not null default 0 check (vat_amount >= 0),
  exempt_amount numeric(19, 4) not null default 0 check (exempt_amount >= 0),
  untaxed_amount numeric(19, 4) not null default 0 check (untaxed_amount >= 0),
  line_total numeric(19, 4) not null default 0 check (line_total >= 0),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (fiscal_document_id, line_number),
  constraint fiscal_document_lines_org_doc_fk
    foreign key (organization_id, fiscal_document_id)
    references public.fiscal_documents (organization_id, id)
    on delete cascade
)","create index fiscal_document_lines_org_doc_idx
  on public.fiscal_document_lines (organization_id, fiscal_document_id)","create trigger fiscal_document_lines_set_updated_at
before update on public.fiscal_document_lines
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- fiscal_tax_summaries
-- ---------------------------------------------------------------------------

create table public.fiscal_tax_summaries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  fiscal_document_id uuid not null,
  summary_kind text not null check (summary_kind in (''IVA'', ''TRIBUTO'')),
  code text not null,
  base_amount numeric(19, 4) not null default 0,
  rate numeric(7, 4),
  amount numeric(19, 4) not null default 0,
  unique (fiscal_document_id, summary_kind, code),
  constraint fiscal_tax_summaries_org_doc_fk
    foreign key (organization_id, fiscal_document_id)
    references public.fiscal_documents (organization_id, id)
    on delete cascade
)","-- ---------------------------------------------------------------------------
-- fiscal_authorization_attempts (append-oriented; no raw SOAP by default)
-- ---------------------------------------------------------------------------

create table public.fiscal_authorization_attempts (
  id uuid primary key default gen_random_uuid(),
  fiscal_document_id uuid not null,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  attempt_number int not null check (attempt_number > 0),
  environment public.fiscal_environment not null,
  service text not null default ''wsfe'',
  requested_pos int not null,
  requested_cbte_tipo int not null,
  requested_document_number bigint,
  certificate_fingerprint text,
  request_hash text,
  started_at timestamptz not null default timezone(''utc'', now()),
  completed_at timestamptz,
  outcome public.fiscal_authorization_outcome,
  arca_error_codes jsonb not null default ''[]''::jsonb,
  arca_observation_codes jsonb not null default ''[]''::jsonb,
  transport_error_class text,
  correlation_id text not null,
  cae text,
  cae_expiration_date date,
  unique (fiscal_document_id, attempt_number),
  constraint fiscal_auth_attempts_org_doc_fk
    foreign key (organization_id, fiscal_document_id)
    references public.fiscal_documents (organization_id, id)
    on delete cascade
)","create index fiscal_authorization_attempts_doc_idx
  on public.fiscal_authorization_attempts (fiscal_document_id, attempt_number)","-- ---------------------------------------------------------------------------
-- Authorized immutability
-- ---------------------------------------------------------------------------

create or replace function public.prevent_authorized_fiscal_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if tg_op = ''DELETE'' then
    if old.status = ''AUTHORIZED'' then
      raise exception ''authorized fiscal documents cannot be deleted'';
    end if;
    return old;
  end if;

  if old.status = ''AUTHORIZED''
    and current_setting(''fiscal.engine_write'', true) is distinct from ''1'' then
    if new.issuer_snapshot is distinct from old.issuer_snapshot
      or new.receiver_snapshot is distinct from old.receiver_snapshot
      or new.document_type_id is distinct from old.document_type_id
      or new.arca_cbte_tipo is distinct from old.arca_cbte_tipo
      or new.arca_point_of_sale is distinct from old.arca_point_of_sale
      or new.document_number is distinct from old.document_number
      or new.issue_date is distinct from old.issue_date
      or new.currency_code is distinct from old.currency_code
      or new.currency_rate is distinct from old.currency_rate
      or new.net_taxed_amount is distinct from old.net_taxed_amount
      or new.net_exempt_amount is distinct from old.net_exempt_amount
      or new.net_untaxed_amount is distinct from old.net_untaxed_amount
      or new.vat_amount is distinct from old.vat_amount
      or new.other_taxes_amount is distinct from old.other_taxes_amount
      or new.total_amount is distinct from old.total_amount
      or new.cae is distinct from old.cae
      or new.cae_expiration_date is distinct from old.cae_expiration_date
      or new.sales_document_id is distinct from old.sales_document_id
      or new.related_fiscal_document_id is distinct from old.related_fiscal_document_id
      or new.qr_payload is distinct from old.qr_payload
      or new.status is distinct from old.status
    then
      raise exception ''authorized fiscal documents are commercially/fiscally immutable'';
    end if;
  end if;
  return new;
end;
$$","create trigger fiscal_documents_prevent_authorized_mutation
before update or delete on public.fiscal_documents
for each row execute function public.prevent_authorized_fiscal_mutation()","create or replace function public.prevent_authorized_fiscal_line_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  v_status public.fiscal_document_status;
begin
  select status into v_status
  from public.fiscal_documents
  where id = coalesce(new.fiscal_document_id, old.fiscal_document_id);

  if v_status = ''AUTHORIZED''
    and current_setting(''fiscal.engine_write'', true) is distinct from ''1'' then
    raise exception ''lines on authorized fiscal documents cannot be modified'';
  end if;

  if tg_op = ''DELETE'' then return old; end if;
  return new;
end;
$$","create trigger fiscal_document_lines_prevent_authorized_mutation
before insert or update or delete on public.fiscal_document_lines
for each row execute function public.prevent_authorized_fiscal_line_mutation()","create or replace function public.prevent_authorized_fiscal_summary_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  v_status public.fiscal_document_status;
begin
  select status into v_status
  from public.fiscal_documents
  where id = coalesce(new.fiscal_document_id, old.fiscal_document_id);

  if v_status = ''AUTHORIZED''
    and current_setting(''fiscal.engine_write'', true) is distinct from ''1'' then
    raise exception ''tax summaries on authorized fiscal documents cannot be modified'';
  end if;

  if tg_op = ''DELETE'' then return old; end if;
  return new;
end;
$$","create trigger fiscal_tax_summaries_prevent_authorized_mutation
before insert or update or delete on public.fiscal_tax_summaries
for each row execute function public.prevent_authorized_fiscal_summary_mutation()"}', 'phase5_fiscal_core'),
	('20260501110000', '{"-- Phase 5 — Fiscal catalogs + seed rule version (STAGING)

-- Official WSFE voucher types (Phase 5 enabled subset)
insert into public.fiscal_document_types (
  internal_code, arca_cbte_tipo, name, document_class, operation_kind, enabled_phase5, effective_from
) values
  (''INVOICE_A'', 1, ''Factura A'', ''A'', ''INVOICE'', true, ''2000-01-01''),
  (''DEBIT_NOTE_A'', 2, ''Nota de Débito A'', ''A'', ''DEBIT_NOTE'', true, ''2000-01-01''),
  (''CREDIT_NOTE_A'', 3, ''Nota de Crédito A'', ''A'', ''CREDIT_NOTE'', true, ''2000-01-01''),
  (''INVOICE_B'', 6, ''Factura B'', ''B'', ''INVOICE'', true, ''2000-01-01''),
  (''DEBIT_NOTE_B'', 7, ''Nota de Débito B'', ''B'', ''DEBIT_NOTE'', true, ''2000-01-01''),
  (''CREDIT_NOTE_B'', 8, ''Nota de Crédito B'', ''B'', ''CREDIT_NOTE'', true, ''2000-01-01''),
  (''INVOICE_C'', 11, ''Factura C'', ''C'', ''INVOICE'', true, ''2000-01-01''),
  (''DEBIT_NOTE_C'', 12, ''Nota de Débito C'', ''C'', ''DEBIT_NOTE'', true, ''2000-01-01''),
  (''CREDIT_NOTE_C'', 13, ''Nota de Crédito C'', ''C'', ''CREDIT_NOTE'', true, ''2000-01-01''),
  -- Disabled Phase 5 (architecture: prepare but do not enable)
  (''INVOICE_M'', 51, ''Factura M'', ''M'', ''INVOICE'', false, ''2000-01-01''),
  (''INVOICE_E'', 19, ''Factura E'', ''E'', ''INVOICE'', false, ''2000-01-01'')
on conflict (internal_code) do update set
  arca_cbte_tipo = excluded.arca_cbte_tipo,
  name = excluded.name,
  document_class = excluded.document_class,
  operation_kind = excluded.operation_kind,
  enabled_phase5 = excluded.enabled_phase5","-- Unique for global (organization_id null) catalogs — Postgres UNIQUE treats NULLs as distinct
create unique index if not exists fiscal_parameter_catalogs_global_uidx
  on public.fiscal_parameter_catalogs (environment, catalog_kind, code)
  where organization_id is null","-- Seed CondicionIVAReceptor catalog placeholders (codes refreshed via FEParamGetCondicionIvaReceptor)
-- These are bootstrap labels only; live homologation must refresh from ARCA.
insert into public.fiscal_parameter_catalogs (
  organization_id, environment, catalog_kind, code, label, valid_from, raw, fetched_at
)
select null, v.environment::public.fiscal_environment, v.catalog_kind, v.code, v.label, v.valid_from::date, v.raw::jsonb, timezone(''utc'', now())
from (values
  (''HOMOLOGATION'', ''CONDICION_IVA_RECEPTOR'', ''1'', ''IVA Responsable Inscripto'', ''2025-04-15'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetCondicionIvaReceptor\",\"refresh_required\":true}''),
  (''HOMOLOGATION'', ''CONDICION_IVA_RECEPTOR'', ''4'', ''IVA Sujeto Exento'', ''2025-04-15'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetCondicionIvaReceptor\",\"refresh_required\":true}''),
  (''HOMOLOGATION'', ''CONDICION_IVA_RECEPTOR'', ''5'', ''Consumidor Final'', ''2025-04-15'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetCondicionIvaReceptor\",\"refresh_required\":true}''),
  (''HOMOLOGATION'', ''CONDICION_IVA_RECEPTOR'', ''6'', ''Responsable Monotributo'', ''2025-04-15'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetCondicionIvaReceptor\",\"refresh_required\":true}''),
  (''HOMOLOGATION'', ''CONDICION_IVA_RECEPTOR'', ''8'', ''Proveedor del Exterior'', ''2025-04-15'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetCondicionIvaReceptor\",\"refresh_required\":true}''),
  (''HOMOLOGATION'', ''CONDICION_IVA_RECEPTOR'', ''9'', ''Cliente del Exterior'', ''2025-04-15'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetCondicionIvaReceptor\",\"refresh_required\":true}''),
  (''HOMOLOGATION'', ''CONDICION_IVA_RECEPTOR'', ''10'', ''IVA Liberado – Ley N° 19.640'', ''2025-04-15'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetCondicionIvaReceptor\",\"refresh_required\":true}''),
  (''HOMOLOGATION'', ''CONDICION_IVA_RECEPTOR'', ''13'', ''Monotributista Social'', ''2025-04-15'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetCondicionIvaReceptor\",\"refresh_required\":true}''),
  (''HOMOLOGATION'', ''CONDICION_IVA_RECEPTOR'', ''15'', ''IVA No Alcanzado'', ''2025-04-15'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetCondicionIvaReceptor\",\"refresh_required\":true}''),
  (''HOMOLOGATION'', ''TIPOS_IVA'', ''5'', ''21%'', ''2000-01-01'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetTiposIva\",\"Id\":5,\"Desc\":\"21%\",\"Aliq\":21}''),
  (''HOMOLOGATION'', ''TIPOS_IVA'', ''4'', ''10.5%'', ''2000-01-01'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetTiposIva\",\"Id\":4,\"Desc\":\"10.5%\",\"Aliq\":10.5}''),
  (''HOMOLOGATION'', ''TIPOS_IVA'', ''3'', ''0%'', ''2000-01-01'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetTiposIva\",\"Id\":3,\"Desc\":\"0%\",\"Aliq\":0}''),
  (''HOMOLOGATION'', ''TIPOS_IVA'', ''6'', ''27%'', ''2000-01-01'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetTiposIva\",\"Id\":6,\"Desc\":\"27%\",\"Aliq\":27}''),
  (''HOMOLOGATION'', ''MONEDAS'', ''PES'', ''Pesos Argentinos'', ''2000-01-01'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetTiposMonedas\",\"Id\":\"PES\",\"Desc\":\"Pesos Argentinos\",\"phase5_mvp\":true}''),
  (''HOMOLOGATION'', ''MONEDAS'', ''DOL'', ''Dólar Estadounidense'', ''2000-01-01'',
   ''{\"source\":\"bootstrap\",\"method\":\"FEParamGetTiposMonedas\",\"Id\":\"DOL\",\"Desc\":\"Dólar Estadounidense\",\"phase5_mvp_enabled\":false}'')
) as v(environment, catalog_kind, code, label, valid_from, raw)
where not exists (
  select 1 from public.fiscal_parameter_catalogs c
  where c.organization_id is null
    and c.environment = v.environment::public.fiscal_environment
    and c.catalog_kind = v.catalog_kind
    and c.code = v.code
)","-- Platform fiscal rule version (ACTIVE for homologation engine; LEGAL_REVIEW_STATUS remains REVIEW_REQUIRED)
insert into public.fiscal_rule_versions (
  organization_id,
  code,
  version,
  effective_from,
  effective_to,
  source_reference,
  source_document,
  status,
  rules,
  reviewed_at,
  activated_at
) values (
  null,
  ''RULES_2026_Q3'',
  1,
  ''2025-04-15'',
  null,
  ''RG 5616/2024; WSFEv1 Manual V4.8 (RG 4291); CondicionIVAReceptorId mandatory per official manual timeline'',
  ''https://www.arca.gob.ar/fe/ayuda/documentos/wsfev1-RG-4291.pdf'',
  ''ACTIVE'',
  jsonb_build_object(
    ''schema_version'', 1,
    ''manual'', jsonb_build_object(
      ''name'', ''Manual del Desarrollador WSFEv1'',
      ''version'', ''4.8'',
      ''project'', ''RG 4291 – Proyecto FE v4.8'',
      ''source_url'', ''https://www.arca.gob.ar/fe/ayuda/documentos/wsfev1-RG-4291.pdf'',
      ''verified_at'', ''2026-09-04''
    ),
    ''currency'', jsonb_build_object(
      ''mvp_enabled'', jsonb_build_array(''PES''),
      ''foreign_disabled'', true,
      ''require_official_rate'', true
    ),
    ''receiver'', jsonb_build_object(
      ''condicion_iva_receptor_required'', true,
      ''condicion_iva_receptor_method'', ''FEParamGetCondicionIvaReceptor'',
      ''snapshot_field'', ''CondicionIVAReceptorId''
    ),
    ''document_matrix'', jsonb_build_object(
      ''enabled_internal_codes'', jsonb_build_array(
        ''INVOICE_A'',''INVOICE_B'',''INVOICE_C'',
        ''CREDIT_NOTE_A'',''CREDIT_NOTE_B'',''CREDIT_NOTE_C'',
        ''DEBIT_NOTE_A'',''DEBIT_NOTE_B'',''DEBIT_NOTE_C''
      ),
      ''disabled_until_separate_gate'', jsonb_build_array(''INVOICE_M'',''INVOICE_E'',''FCE'')
    ),
    ''vat'', jsonb_build_object(
      ''default_rate_code'', ''5'',
      ''default_rate'', 21,
      ''reconcile_tolerance'', 0.01
    ),
    ''qr'', jsonb_build_object(
      ''enabled_after_authorized'', true,
      ''schema_version'', 1
    ),
    ''wsaa'', jsonb_build_object(
      ''service_name'', ''wsfe''
    ),
    ''legal_review_status'', ''REVIEW_REQUIRED''
  ),
  null,
  timezone(''utc'', now())
)
on conflict do nothing","-- If unique conflict path differs for null org, ensure one ACTIVE platform rule exists
do $$
begin
  if not exists (
    select 1 from public.fiscal_rule_versions
    where organization_id is null and code = ''RULES_2026_Q3'' and version = 1
  ) then
    insert into public.fiscal_rule_versions (
      organization_id, code, version, effective_from, source_reference, source_document, status, rules, activated_at
    ) values (
      null, ''RULES_2026_Q3'', 1, ''2025-04-15'',
      ''RG 5616/2024; WSFEv1 Manual V4.8'',
      ''https://www.arca.gob.ar/fe/ayuda/documentos/wsfev1-RG-4291.pdf'',
      ''ACTIVE'',
      ''{\"schema_version\":1,\"legal_review_status\":\"REVIEW_REQUIRED\"}''::jsonb,
      timezone(''utc'', now())
    );
  end if;
end $$"}', 'phase5_fiscal_catalogs'),
	('20260501120000', '{"-- Phase 5 — Fiscal accounting mappings + sales handoff columns

-- Ensure accounts have composite unique for FKs (before mapping table)
do $$ begin
  alter table public.accounts
    add constraint accounts_org_id_unique unique (organization_id, id);
exception
  when duplicate_object then null;
end $$","create table public.fiscal_accounting_mappings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  sales_account_id uuid not null,
  vat_output_account_id uuid not null,
  receivables_account_id uuid not null,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (organization_id),
  constraint fiscal_accounting_mappings_sales_fk
    foreign key (organization_id, sales_account_id)
    references public.accounts (organization_id, id)
    on delete restrict,
  constraint fiscal_accounting_mappings_vat_fk
    foreign key (organization_id, vat_output_account_id)
    references public.accounts (organization_id, id)
    on delete restrict,
  constraint fiscal_accounting_mappings_recv_fk
    foreign key (organization_id, receivables_account_id)
    references public.accounts (organization_id, id)
    on delete restrict
)","create trigger fiscal_accounting_mappings_set_updated_at
before update on public.fiscal_accounting_mappings
for each row execute function public.set_updated_at()","-- Sales handoff pointer (set only by fiscal engine)
alter table public.sales_documents
  add column if not exists invoiced_fiscal_document_id uuid","do $$ begin
  alter table public.sales_documents
    add constraint sales_documents_invoiced_fiscal_fk
    foreign key (invoiced_fiscal_document_id)
    references public.fiscal_documents (id)
    on delete restrict;
exception when duplicate_object then null;
end $$","create index if not exists sales_documents_invoiced_fiscal_idx
  on public.sales_documents (invoiced_fiscal_document_id)
  where invoiced_fiscal_document_id is not null","comment on table public.fiscal_accounting_mappings is
  ''Per-org mapping for fiscal sale posting: sales revenue, IVA débito fiscal, receivables.''"}', 'phase5_fiscal_accounting'),
	('20260501130000', '{"-- Phase 5 — Fiscal RLS + feature enablement for synthetic QA orgs

alter table public.fiscal_rule_versions enable row level security","alter table public.fiscal_document_types enable row level security","alter table public.fiscal_parameter_catalogs enable row level security","alter table public.fiscal_points_of_sale enable row level security","alter table public.fiscal_credential_metadata enable row level security","alter table public.fiscal_service_profiles enable row level security","alter table public.fiscal_documents enable row level security","alter table public.fiscal_document_lines enable row level security","alter table public.fiscal_tax_summaries enable row level security","alter table public.fiscal_authorization_attempts enable row level security","alter table public.fiscal_accounting_mappings enable row level security","-- Global catalogs readable by authenticated
drop policy if exists fiscal_document_types_select on public.fiscal_document_types","create policy fiscal_document_types_select
  on public.fiscal_document_types for select to authenticated
  using (true)","drop policy if exists fiscal_rule_versions_select on public.fiscal_rule_versions","create policy fiscal_rule_versions_select
  on public.fiscal_rule_versions for select to authenticated
  using (
    organization_id is null
    or (select public.is_org_member(organization_id))
  )","drop policy if exists fiscal_parameter_catalogs_select on public.fiscal_parameter_catalogs","create policy fiscal_parameter_catalogs_select
  on public.fiscal_parameter_catalogs for select to authenticated
  using (
    organization_id is null
    or (select public.is_org_member(organization_id))
  )","-- Points of sale
drop policy if exists fiscal_points_of_sale_select on public.fiscal_points_of_sale","create policy fiscal_points_of_sale_select
  on public.fiscal_points_of_sale for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists fiscal_points_of_sale_write on public.fiscal_points_of_sale","create policy fiscal_points_of_sale_write
  on public.fiscal_points_of_sale for all to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","-- Credential metadata (no secrets in table)
drop policy if exists fiscal_credential_metadata_select on public.fiscal_credential_metadata","create policy fiscal_credential_metadata_select
  on public.fiscal_credential_metadata for select to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","drop policy if exists fiscal_credential_metadata_write on public.fiscal_credential_metadata","create policy fiscal_credential_metadata_write
  on public.fiscal_credential_metadata for all to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'']::public.member_role[]
  )))","-- Service profiles
drop policy if exists fiscal_service_profiles_select on public.fiscal_service_profiles","create policy fiscal_service_profiles_select
  on public.fiscal_service_profiles for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists fiscal_service_profiles_write on public.fiscal_service_profiles","create policy fiscal_service_profiles_write
  on public.fiscal_service_profiles for all to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","-- Fiscal documents
drop policy if exists fiscal_documents_select on public.fiscal_documents","create policy fiscal_documents_select
  on public.fiscal_documents for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists fiscal_documents_insert on public.fiscal_documents","create policy fiscal_documents_insert
  on public.fiscal_documents for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","drop policy if exists fiscal_documents_update on public.fiscal_documents","create policy fiscal_documents_update
  on public.fiscal_documents for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","drop policy if exists fiscal_documents_delete on public.fiscal_documents","create policy fiscal_documents_delete
  on public.fiscal_documents for delete to authenticated
  using (
    status in (''DRAFT'', ''REJECTED'')
    and (select public.has_org_role(
      organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
    ))
  )","-- Lines
drop policy if exists fiscal_document_lines_select on public.fiscal_document_lines","create policy fiscal_document_lines_select
  on public.fiscal_document_lines for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists fiscal_document_lines_write on public.fiscal_document_lines","create policy fiscal_document_lines_write
  on public.fiscal_document_lines for all to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","-- Tax summaries
drop policy if exists fiscal_tax_summaries_select on public.fiscal_tax_summaries","create policy fiscal_tax_summaries_select
  on public.fiscal_tax_summaries for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists fiscal_tax_summaries_write on public.fiscal_tax_summaries","create policy fiscal_tax_summaries_write
  on public.fiscal_tax_summaries for all to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","-- Attempts: read members; insert via engine roles
drop policy if exists fiscal_authorization_attempts_select on public.fiscal_authorization_attempts","create policy fiscal_authorization_attempts_select
  on public.fiscal_authorization_attempts for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists fiscal_authorization_attempts_insert on public.fiscal_authorization_attempts","create policy fiscal_authorization_attempts_insert
  on public.fiscal_authorization_attempts for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","-- Accounting mappings
drop policy if exists fiscal_accounting_mappings_select on public.fiscal_accounting_mappings","create policy fiscal_accounting_mappings_select
  on public.fiscal_accounting_mappings for select to authenticated
  using ((select public.is_org_member(organization_id)))","drop policy if exists fiscal_accounting_mappings_write on public.fiscal_accounting_mappings","create policy fiscal_accounting_mappings_write
  on public.fiscal_accounting_mappings for all to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","-- Grants
grant select on public.fiscal_document_types to authenticated","grant select on public.fiscal_rule_versions to authenticated","grant select on public.fiscal_parameter_catalogs to authenticated","grant select, insert, update, delete on public.fiscal_points_of_sale to authenticated","grant select, insert, update, delete on public.fiscal_credential_metadata to authenticated","grant select, insert, update, delete on public.fiscal_service_profiles to authenticated","grant select, insert, update, delete on public.fiscal_documents to authenticated","grant select, insert, update, delete on public.fiscal_document_lines to authenticated","grant select, insert, update, delete on public.fiscal_tax_summaries to authenticated","grant select, insert on public.fiscal_authorization_attempts to authenticated","grant select, insert, update, delete on public.fiscal_accounting_mappings to authenticated","revoke all on public.fiscal_rule_versions from anon","revoke all on public.fiscal_document_types from anon","revoke all on public.fiscal_parameter_catalogs from anon","revoke all on public.fiscal_points_of_sale from anon","revoke all on public.fiscal_credential_metadata from anon","revoke all on public.fiscal_service_profiles from anon","revoke all on public.fiscal_documents from anon","revoke all on public.fiscal_document_lines from anon","revoke all on public.fiscal_tax_summaries from anon","revoke all on public.fiscal_authorization_attempts from anon","revoke all on public.fiscal_accounting_mappings from anon","-- Enable fiscal_invoicing only for synthetic Demo QA orgs that already have sales
insert into public.organization_features (organization_id, feature_id, status, enabled_at)
select distinct c.organization_id, fc.id, ''enabled''::public.feature_status, timezone(''utc'', now())
from public.counterparties c
inner join public.feature_catalog fc on fc.code = ''fiscal_invoicing''
where c.legal_name ilike ''%Demo%''
on conflict (organization_id, feature_id) do update
  set status = excluded.status,
      enabled_at = coalesce(public.organization_features.enabled_at, excluded.enabled_at)"}', 'phase5_fiscal_security'),
	('20260501140000', '{"-- Phase 5 — Fiscal RPCs (prepare / ready / complete / reconcile / notes / accounting)
-- ARCA SOAP stays in application layer. These RPCs coordinate DB state + locks.

create or replace function public.fiscal_assert_feature(p_org_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  v_ok boolean;
begin
  select exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = ''fiscal_invoicing''
      and ofeat.status = ''enabled''
  ) into v_ok;

  if not coalesce(v_ok, false) then
    raise exception ''fiscal_invoicing feature is not enabled for this organization'';
  end if;
end;
$$","create or replace function public.fiscal_assert_role(
  p_org_id uuid,
  p_roles public.member_role[]
)
returns void
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if not public.has_org_role(p_org_id, p_roles) then
    raise exception ''insufficient role for fiscal operation'';
  end if;
end;
$$","create or replace function public.resolve_fiscal_rule_version(
  p_org_id uuid,
  p_issue_date date
)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''''
as $$
declare
  v_id uuid;
begin
  select id into v_id
  from public.fiscal_rule_versions
  where status = ''ACTIVE''
    and effective_from <= p_issue_date
    and (effective_to is null or effective_to >= p_issue_date)
    and (organization_id = p_org_id or organization_id is null)
  order by
    case when organization_id = p_org_id then 0 else 1 end,
    effective_from desc,
    version desc
  limit 1;

  if v_id is null then
    raise exception ''no ACTIVE fiscal rule version for issue_date %'', p_issue_date;
  end if;
  return v_id;
end;
$$","-- Prepare primary invoice from READY_TO_INVOICE sales order (idempotent)
create or replace function public.prepare_fiscal_invoice_from_sales_order(
  p_sales_document_id uuid,
  p_point_of_sale_id uuid,
  p_document_type_internal_code text,
  p_issue_date date default current_date,
  p_condicion_iva_receptor_id int default null
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_sales public.sales_documents%rowtype;
  v_pos public.fiscal_points_of_sale%rowtype;
  v_dtype public.fiscal_document_types%rowtype;
  v_rule_id uuid;
  v_existing uuid;
  v_doc_id uuid;
  v_org public.organizations%rowtype;
  v_fp record;
  v_cp record;
  v_line record;
  v_line_no int := 0;
  v_net_taxed numeric(19,4) := 0;
  v_vat numeric(19,4) := 0;
  v_total numeric(19,4) := 0;
  v_line_net numeric(19,4);
  v_line_vat numeric(19,4);
  v_line_total numeric(19,4);
  v_idem text;
  v_receiver jsonb;
begin
  if v_uid is null then
    raise exception ''authentication required'';
  end if;

  select * into v_sales
  from public.sales_documents
  where id = p_sales_document_id
  for update;

  if not found then
    raise exception ''sales document not found'';
  end if;

  perform public.fiscal_assert_feature(v_sales.organization_id);
  perform public.fiscal_assert_role(
    v_sales.organization_id,
    array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  );

  if v_sales.document_type is distinct from ''SALES_ORDER'' then
    raise exception ''only SALES_ORDER can be prepared for fiscal invoice'';
  end if;
  if v_sales.status is distinct from ''READY_TO_INVOICE'' then
    raise exception ''sales order must be READY_TO_INVOICE (got %)'', v_sales.status;
  end if;

  v_idem := ''invoice:'' || p_sales_document_id::text;

  select id into v_existing
  from public.fiscal_documents
  where organization_id = v_sales.organization_id
    and idempotency_key = v_idem;

  if v_existing is not null then
    return v_existing;
  end if;

  select * into v_pos
  from public.fiscal_points_of_sale
  where id = p_point_of_sale_id
    and organization_id = v_sales.organization_id
    and is_active
  for share;

  if not found then
    raise exception ''active fiscal point of sale not found'';
  end if;
  if v_pos.environment = ''PRODUCTION'' then
    raise exception ''PRODUCTION fiscal environment is blocked in Phase 5'';
  end if;
  if v_pos.issuance_method is distinct from ''WSFE_CAE'' then
    raise exception ''only WSFE_CAE issuance is enabled in Phase 5'';
  end if;

  select * into v_dtype
  from public.fiscal_document_types
  where internal_code = p_document_type_internal_code
    and enabled_phase5
    and operation_kind = ''INVOICE'';

  if not found then
    raise exception ''document type % not enabled for Phase 5 invoice'', p_document_type_internal_code;
  end if;

  v_rule_id := public.resolve_fiscal_rule_version(v_sales.organization_id, p_issue_date);

  select * into v_org from public.organizations where id = v_sales.organization_id;
  if v_org.cuit is null then
    raise exception ''organization CUIT required for fiscal issuance'';
  end if;

  select fc.code as condition_code, fp.fiscal_address, fp.gross_income_number, fp.activity_start_date
  into v_fp
  from public.fiscal_profiles fp
  left join public.fiscal_conditions fc on fc.id = fp.fiscal_condition_id
  where fp.organization_id = v_sales.organization_id
  limit 1;

  select c.id, c.tax_id, c.tax_id_type, c.legal_name, c.trade_name,
         fc.code as fiscal_condition_code, cfp.fiscal_address
  into v_cp
  from public.counterparties c
  left join public.counterparty_fiscal_profiles cfp
    on cfp.organization_id = c.organization_id and cfp.counterparty_id = c.id
  left join public.fiscal_conditions fc on fc.id = cfp.fiscal_condition_id
  where c.organization_id = v_sales.organization_id
    and c.id = v_sales.counterparty_id;

  if p_condicion_iva_receptor_id is null then
    raise exception ''CondicionIVAReceptorId is required'';
  end if;

  -- Validate receptor condition exists in catalog (bootstrap or refreshed)
  if not exists (
    select 1 from public.fiscal_parameter_catalogs
    where catalog_kind = ''CONDICION_IVA_RECEPTOR''
      and environment = v_pos.environment
      and code = p_condicion_iva_receptor_id::text
      and (organization_id is null or organization_id = v_sales.organization_id)
  ) then
    raise exception ''CondicionIVAReceptorId % not found in fiscal_parameter_catalogs'', p_condicion_iva_receptor_id;
  end if;

  v_receiver := jsonb_build_object(
    ''counterparty_id'', v_cp.id,
    ''tax_id'', v_cp.tax_id,
    ''tax_id_type'', v_cp.tax_id_type,
    ''legal_name'', v_cp.legal_name,
    ''trade_name'', v_cp.trade_name,
    ''fiscal_condition_code'', v_cp.fiscal_condition_code,
    ''fiscal_address'', v_cp.fiscal_address,
    ''CondicionIVAReceptorId'', p_condicion_iva_receptor_id
  );

  insert into public.fiscal_documents (
    organization_id,
    branch_id,
    sales_document_id,
    fiscal_environment,
    document_type_id,
    document_class,
    arca_cbte_tipo,
    point_of_sale_id,
    arca_point_of_sale,
    issue_date,
    counterparty_id,
    issuer_snapshot,
    receiver_snapshot,
    currency_code,
    currency_rate,
    concept_type,
    status,
    accounting_status,
    fiscal_rule_version_id,
    idempotency_key,
    created_by
  ) values (
    v_sales.organization_id,
    v_sales.branch_id,
    v_sales.id,
    v_pos.environment,
    v_dtype.id,
    v_dtype.document_class,
    v_dtype.arca_cbte_tipo,
    v_pos.id,
    v_pos.arca_point_of_sale,
    p_issue_date,
    v_sales.counterparty_id,
    jsonb_build_object(
      ''cuit'', v_org.cuit,
      ''legal_name'', v_org.legal_name,
      ''commercial_name'', v_org.commercial_name,
      ''fiscal_condition_code'', v_fp.condition_code,
      ''fiscal_address'', v_fp.fiscal_address,
      ''gross_income_number'', v_fp.gross_income_number,
      ''activity_start_date'', v_fp.activity_start_date
    ),
    v_receiver,
    ''PES'',
    1,
    1,
    ''DRAFT'',
    ''NOT_APPLICABLE'',
    v_rule_id,
    v_idem,
    v_uid
  )
  returning id into v_doc_id;

  for v_line in
    select *
    from public.sales_document_lines
    where sales_document_id = v_sales.id
    order by line_number
  loop
    v_line_no := v_line_no + 1;
    v_line_net := round((v_line.quantity * v_line.unit_price) - coalesce(v_line.discount_amount, 0), 4);
    -- Phase 5 default: 21% taxed until line-level VAT treatment is configured
    v_line_vat := round(v_line_net * 0.21, 4);
    v_line_total := v_line_net + v_line_vat;
    v_net_taxed := v_net_taxed + v_line_net;
    v_vat := v_vat + v_line_vat;
    v_total := v_total + v_line_total;

    insert into public.fiscal_document_lines (
      organization_id, fiscal_document_id, line_number, source_sales_line_id,
      description, quantity, unit_price, discount_amount,
      vat_treatment, vat_rate_code, vat_rate,
      net_amount, vat_amount, exempt_amount, untaxed_amount, line_total
    ) values (
      v_sales.organization_id, v_doc_id, v_line_no, v_line.id,
      v_line.description, v_line.quantity, v_line.unit_price, coalesce(v_line.discount_amount, 0),
      ''TAXED'', ''5'', 21,
      v_line_net, v_line_vat, 0, 0, v_line_total
    );
  end loop;

  if v_line_no = 0 then
    raise exception ''sales order has no lines'';
  end if;

  insert into public.fiscal_tax_summaries (
    organization_id, fiscal_document_id, summary_kind, code, base_amount, rate, amount
  ) values (
    v_sales.organization_id, v_doc_id, ''IVA'', ''5'', v_net_taxed, 21, v_vat
  );

  update public.fiscal_documents
  set net_taxed_amount = v_net_taxed,
      vat_amount = v_vat,
      total_amount = v_total,
      updated_at = timezone(''utc'', now())
  where id = v_doc_id;

  return v_doc_id;
end;
$$","create or replace function public.mark_fiscal_ready_to_authorize(p_fiscal_document_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_doc public.fiscal_documents%rowtype;
begin
  select * into v_doc
  from public.fiscal_documents
  where id = p_fiscal_document_id
  for update;

  if not found then
    raise exception ''fiscal document not found'';
  end if;

  perform public.fiscal_assert_feature(v_doc.organization_id);
  perform public.fiscal_assert_role(
    v_doc.organization_id,
    array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  );

  if v_doc.status not in (''DRAFT'', ''REJECTED'') then
    raise exception ''cannot mark ready from status %'', v_doc.status;
  end if;
  if v_doc.currency_code not in (''PES'', ''ARS'') then
    raise exception ''Phase 5 homologation MVP allows ARS/PES only'';
  end if;
  if coalesce((v_doc.receiver_snapshot->>''CondicionIVAReceptorId'')::int, 0) <= 0 then
    raise exception ''CondicionIVAReceptorId missing on receiver snapshot'';
  end if;
  if v_doc.total_amount <= 0 then
    raise exception ''total_amount must be positive'';
  end if;
  if abs(
    (v_doc.net_taxed_amount + v_doc.net_exempt_amount + v_doc.net_untaxed_amount
      + v_doc.vat_amount + v_doc.other_taxes_amount) - v_doc.total_amount
  ) > 0.01 then
    raise exception ''totals do not reconcile'';
  end if;

  update public.fiscal_documents
  set status = ''READY_TO_AUTHORIZE'',
      updated_at = timezone(''utc'', now())
  where id = p_fiscal_document_id;

  return p_fiscal_document_id;
end;
$$","-- Begin authorization: lock + AUTHORIZING + attempt row. Number provided by app after UltimoAutorizado.
create or replace function public.begin_fiscal_authorization(
  p_fiscal_document_id uuid,
  p_intended_document_number bigint,
  p_certificate_fingerprint text,
  p_request_hash text,
  p_correlation_id text
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_doc public.fiscal_documents%rowtype;
  v_attempt_id uuid;
  v_attempt_no int;
begin
  if p_intended_document_number is null or p_intended_document_number <= 0 then
    raise exception ''intended document number required'';
  end if;

  select * into v_doc
  from public.fiscal_documents
  where id = p_fiscal_document_id
  for update;

  if not found then
    raise exception ''fiscal document not found'';
  end if;

  perform public.fiscal_assert_feature(v_doc.organization_id);
  -- authorize roles: owner, admin, accountant (manager excluded by default)
  perform public.fiscal_assert_role(
    v_doc.organization_id,
    array[''owner'',''admin'',''accountant'']::public.member_role[]
  );

  if v_doc.fiscal_environment = ''PRODUCTION'' then
    raise exception ''PRODUCTION ARCA blocked'';
  end if;

  if v_doc.status = ''AUTHORIZED'' then
    raise exception ''already authorized'';
  end if;

  if v_doc.status = ''AUTHORIZING'' then
    raise exception ''authorization already in progress; reconcile first'';
  end if;

  if v_doc.status = ''RECONCILIATION_REQUIRED'' then
    raise exception ''uncertain outcome: reconcile before new FECAE; do not allocate a new number'';
  end if;

  if v_doc.status is distinct from ''READY_TO_AUTHORIZE'' then
    raise exception ''document must be READY_TO_AUTHORIZE'';
  end if;

  -- Advisory lock key: org + env + POS + cbte tipo
  perform pg_advisory_xact_lock(
    hashtext(
      v_doc.organization_id::text || '':'' || v_doc.fiscal_environment::text
      || '':'' || v_doc.arca_point_of_sale::text || '':'' || v_doc.arca_cbte_tipo::text
    )
  );

  select coalesce(max(attempt_number), 0) + 1 into v_attempt_no
  from public.fiscal_authorization_attempts
  where fiscal_document_id = p_fiscal_document_id;

  insert into public.fiscal_authorization_attempts (
    fiscal_document_id, organization_id, attempt_number, environment, service,
    requested_pos, requested_cbte_tipo, requested_document_number,
    certificate_fingerprint, request_hash, correlation_id, outcome
  ) values (
    p_fiscal_document_id, v_doc.organization_id, v_attempt_no, v_doc.fiscal_environment, ''wsfe'',
    v_doc.arca_point_of_sale, v_doc.arca_cbte_tipo, p_intended_document_number,
    p_certificate_fingerprint, p_request_hash, p_correlation_id, null
  )
  returning id into v_attempt_id;

  update public.fiscal_documents
  set status = ''AUTHORIZING'',
      document_number = p_intended_document_number,
      credential_fingerprint = p_certificate_fingerprint,
      updated_at = timezone(''utc'', now())
  where id = p_fiscal_document_id;

  return v_attempt_id;
end;
$$","create or replace function public.complete_fiscal_authorization(
  p_attempt_id uuid,
  p_outcome public.fiscal_authorization_outcome,
  p_cae text default null,
  p_cae_expiration date default null,
  p_arca_error_codes jsonb default ''[]''::jsonb,
  p_arca_observation_codes jsonb default ''[]''::jsonb,
  p_transport_error_class text default null,
  p_arca_result jsonb default ''{}''::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_attempt public.fiscal_authorization_attempts%rowtype;
  v_doc public.fiscal_documents%rowtype;
begin
  select * into v_attempt
  from public.fiscal_authorization_attempts
  where id = p_attempt_id
  for update;

  if not found then
    raise exception ''attempt not found'';
  end if;

  select * into v_doc
  from public.fiscal_documents
  where id = v_attempt.fiscal_document_id
  for update;

  perform public.fiscal_assert_role(
    v_doc.organization_id,
    array[''owner'',''admin'',''accountant'']::public.member_role[]
  );

  perform set_config(''fiscal.engine_write'', ''1'', true);

  update public.fiscal_authorization_attempts
  set completed_at = timezone(''utc'', now()),
      outcome = p_outcome,
      cae = p_cae,
      cae_expiration_date = p_cae_expiration,
      arca_error_codes = coalesce(p_arca_error_codes, ''[]''::jsonb),
      arca_observation_codes = coalesce(p_arca_observation_codes, ''[]''::jsonb),
      transport_error_class = p_transport_error_class
  where id = p_attempt_id;

  if p_outcome in (''APPROVED'', ''RECONCILED_AUTHORIZED'') then
    if p_cae is null or p_cae_expiration is null then
      raise exception ''CAE and expiration required for approved outcome'';
    end if;

    update public.fiscal_documents
    set status = ''AUTHORIZED'',
        cae = p_cae,
        cae_expiration_date = p_cae_expiration,
        arca_result = coalesce(p_arca_result, ''{}''::jsonb),
        arca_observations = coalesce(p_arca_observation_codes, ''[]''::jsonb),
        authorized_at = timezone(''utc'', now()),
        accounting_status = ''PENDING'',
        updated_at = timezone(''utc'', now())
    where id = v_doc.id;

    if v_doc.sales_document_id is not null and v_doc.relationship_type is null then
      update public.sales_documents
      set status = ''INVOICED'',
          invoiced_fiscal_document_id = v_doc.id,
          updated_at = timezone(''utc'', now())
      where id = v_doc.sales_document_id
        and organization_id = v_doc.organization_id
        and status = ''READY_TO_INVOICE'';
    end if;

  elsif p_outcome = ''REJECTED'' then
    update public.fiscal_documents
    set status = ''REJECTED'',
        document_number = null,
        arca_result = coalesce(p_arca_result, ''{}''::jsonb),
        arca_observations = coalesce(p_arca_observation_codes, ''[]''::jsonb),
        updated_at = timezone(''utc'', now())
    where id = v_doc.id;

  elsif p_outcome in (''TRANSPORT_ERROR'', ''UNCERTAIN'', ''AUTH_ERROR'') then
    -- Keep intended number; do not burn a new one
    update public.fiscal_documents
    set status = ''RECONCILIATION_REQUIRED'',
        arca_result = coalesce(p_arca_result, ''{}''::jsonb),
        updated_at = timezone(''utc'', now())
    where id = v_doc.id;

  elsif p_outcome = ''RECONCILED_NOT_FOUND'' then
    update public.fiscal_documents
    set status = ''READY_TO_AUTHORIZE'',
        document_number = null,
        updated_at = timezone(''utc'', now())
    where id = v_doc.id;

  elsif p_outcome = ''BUSINESS_VALIDATION_ERROR'' then
    update public.fiscal_documents
    set status = ''REJECTED'',
        document_number = null,
        arca_result = coalesce(p_arca_result, ''{}''::jsonb),
        updated_at = timezone(''utc'', now())
    where id = v_doc.id;
  else
    raise exception ''unsupported outcome %'', p_outcome;
  end if;

  return v_doc.id;
end;
$$","create or replace function public.set_fiscal_qr_payload(
  p_fiscal_document_id uuid,
  p_qr_payload text
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_doc public.fiscal_documents%rowtype;
begin
  select * into v_doc from public.fiscal_documents where id = p_fiscal_document_id for update;
  if not found then raise exception ''fiscal document not found''; end if;
  if v_doc.status is distinct from ''AUTHORIZED'' then
    raise exception ''QR only after AUTHORIZED'';
  end if;
  perform public.fiscal_assert_role(
    v_doc.organization_id,
    array[''owner'',''admin'',''accountant'']::public.member_role[]
  );
  perform set_config(''fiscal.engine_write'', ''1'', true);
  update public.fiscal_documents
  set qr_payload = p_qr_payload, updated_at = timezone(''utc'', now())
  where id = p_fiscal_document_id;
  return p_fiscal_document_id;
end;
$$","-- Credit / debit note prepare from authorized parent
create or replace function public.prepare_fiscal_note(
  p_parent_fiscal_document_id uuid,
  p_document_type_internal_code text,
  p_relationship public.fiscal_relationship_type,
  p_issue_date date default current_date,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_parent public.fiscal_documents%rowtype;
  v_dtype public.fiscal_document_types%rowtype;
  v_rule_id uuid;
  v_doc_id uuid;
  v_idem text;
  v_existing uuid;
  v_line record;
  v_roles public.member_role[];
begin
  select * into v_parent
  from public.fiscal_documents
  where id = p_parent_fiscal_document_id
  for share;

  if not found then raise exception ''parent fiscal document not found''; end if;
  if v_parent.status is distinct from ''AUTHORIZED'' then
    raise exception ''parent must be AUTHORIZED'';
  end if;

  perform public.fiscal_assert_feature(v_parent.organization_id);

  if p_relationship = ''CREDIT_NOTE'' then
    v_roles := array[''owner'',''admin'',''accountant'']::public.member_role[];
  else
    v_roles := array[''owner'',''admin'',''accountant'']::public.member_role[];
  end if;
  perform public.fiscal_assert_role(v_parent.organization_id, v_roles);

  select * into v_dtype
  from public.fiscal_document_types
  where internal_code = p_document_type_internal_code
    and enabled_phase5
    and operation_kind = case
      when p_relationship = ''CREDIT_NOTE'' then ''CREDIT_NOTE''::public.fiscal_operation_kind
      else ''DEBIT_NOTE''::public.fiscal_operation_kind
    end;

  if not found then
    raise exception ''note document type not enabled'';
  end if;
  if v_dtype.document_class is distinct from v_parent.document_class then
    raise exception ''note class must match parent class'';
  end if;

  v_idem := coalesce(p_idempotency_key, lower(p_relationship::text) || '':'' || p_parent_fiscal_document_id::text || '':'' || p_issue_date::text);
  select id into v_existing
  from public.fiscal_documents
  where organization_id = v_parent.organization_id and idempotency_key = v_idem;
  if v_existing is not null then return v_existing; end if;

  v_rule_id := public.resolve_fiscal_rule_version(v_parent.organization_id, p_issue_date);

  insert into public.fiscal_documents (
    organization_id, branch_id, sales_document_id, fiscal_environment,
    document_type_id, document_class, arca_cbte_tipo,
    point_of_sale_id, arca_point_of_sale, issue_date, counterparty_id,
    issuer_snapshot, receiver_snapshot, currency_code, currency_rate, concept_type,
    net_taxed_amount, net_exempt_amount, net_untaxed_amount, vat_amount,
    other_taxes_amount, total_amount, status, accounting_status,
    related_fiscal_document_id, relationship_type, fiscal_rule_version_id,
    idempotency_key, created_by
  ) values (
    v_parent.organization_id, v_parent.branch_id, null, v_parent.fiscal_environment,
    v_dtype.id, v_dtype.document_class, v_dtype.arca_cbte_tipo,
    v_parent.point_of_sale_id, v_parent.arca_point_of_sale, p_issue_date, v_parent.counterparty_id,
    v_parent.issuer_snapshot, v_parent.receiver_snapshot, v_parent.currency_code, v_parent.currency_rate, v_parent.concept_type,
    v_parent.net_taxed_amount, v_parent.net_exempt_amount, v_parent.net_untaxed_amount, v_parent.vat_amount,
    v_parent.other_taxes_amount, v_parent.total_amount, ''DRAFT'', ''NOT_APPLICABLE'',
    v_parent.id, p_relationship, v_rule_id,
    v_idem, auth.uid()
  )
  returning id into v_doc_id;

  insert into public.fiscal_document_lines (
    organization_id, fiscal_document_id, line_number, description, quantity, unit_price,
    discount_amount, vat_treatment, vat_rate_code, vat_rate,
    net_amount, vat_amount, exempt_amount, untaxed_amount, line_total
  )
  select
    organization_id, v_doc_id, line_number, description, quantity, unit_price,
    discount_amount, vat_treatment, vat_rate_code, vat_rate,
    net_amount, vat_amount, exempt_amount, untaxed_amount, line_total
  from public.fiscal_document_lines
  where fiscal_document_id = v_parent.id;

  insert into public.fiscal_tax_summaries (
    organization_id, fiscal_document_id, summary_kind, code, base_amount, rate, amount
  )
  select organization_id, v_doc_id, summary_kind, code, base_amount, rate, amount
  from public.fiscal_tax_summaries
  where fiscal_document_id = v_parent.id;

  return v_doc_id;
end;
$$","revoke all on function public.fiscal_assert_feature(uuid) from public, anon","revoke all on function public.fiscal_assert_role(uuid, public.member_role[]) from public, anon","revoke all on function public.resolve_fiscal_rule_version(uuid, date) from public, anon","revoke all on function public.prepare_fiscal_invoice_from_sales_order(uuid, uuid, text, date, int) from public, anon","revoke all on function public.mark_fiscal_ready_to_authorize(uuid) from public, anon","revoke all on function public.begin_fiscal_authorization(uuid, bigint, text, text, text) from public, anon","revoke all on function public.complete_fiscal_authorization(uuid, public.fiscal_authorization_outcome, text, date, jsonb, jsonb, text, jsonb) from public, anon","revoke all on function public.set_fiscal_qr_payload(uuid, text) from public, anon","revoke all on function public.prepare_fiscal_note(uuid, text, public.fiscal_relationship_type, date, text) from public, anon","grant execute on function public.resolve_fiscal_rule_version(uuid, date) to authenticated","grant execute on function public.prepare_fiscal_invoice_from_sales_order(uuid, uuid, text, date, int) to authenticated","grant execute on function public.mark_fiscal_ready_to_authorize(uuid) to authenticated","grant execute on function public.begin_fiscal_authorization(uuid, bigint, text, text, text) to authenticated","grant execute on function public.complete_fiscal_authorization(uuid, public.fiscal_authorization_outcome, text, date, jsonb, jsonb, text, jsonb) to authenticated","grant execute on function public.set_fiscal_qr_payload(uuid, text) to authenticated","grant execute on function public.prepare_fiscal_note(uuid, text, public.fiscal_relationship_type, date, text) to authenticated"}', 'phase5_fiscal_functions'),
	('20260501150000', '{"-- Phase 5 — Performance/security hardening (FK indexes, enum probe)

-- Covering indexes for FKs / common filters (Performance Advisor)
create index if not exists fiscal_documents_created_by_idx
  on public.fiscal_documents (created_by)
  where created_by is not null","create index if not exists fiscal_documents_journal_entry_id_idx
  on public.fiscal_documents (journal_entry_id)
  where journal_entry_id is not null","create index if not exists fiscal_documents_related_idx
  on public.fiscal_documents (related_fiscal_document_id)
  where related_fiscal_document_id is not null","create index if not exists fiscal_documents_rule_version_idx
  on public.fiscal_documents (fiscal_rule_version_id)","create index if not exists fiscal_documents_document_type_idx
  on public.fiscal_documents (document_type_id)","create index if not exists fiscal_points_of_sale_org_env_active_idx
  on public.fiscal_points_of_sale (organization_id, environment, is_active)","create index if not exists fiscal_credential_metadata_org_env_idx
  on public.fiscal_credential_metadata (organization_id, environment)","create index if not exists fiscal_authorization_attempts_org_idx
  on public.fiscal_authorization_attempts (organization_id)","-- Ensure INVOICED exists on sales_document_status (idempotent)
do $$ begin
  alter type public.sales_document_status add value if not exists ''INVOICED'';
exception when duplicate_object then null;
end $$","-- Attempts should not be updatable by authenticated (append-only from client perspective)
revoke update, delete on public.fiscal_authorization_attempts from authenticated"}', 'phase5_fiscal_hardening'),
	('20260501160000', '{"-- Phase 5 — lint fix for prepare_fiscal_note unused variable

create or replace function public.prepare_fiscal_note(
  p_parent_fiscal_document_id uuid,
  p_document_type_internal_code text,
  p_relationship public.fiscal_relationship_type,
  p_issue_date date default current_date,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_parent public.fiscal_documents%rowtype;
  v_dtype public.fiscal_document_types%rowtype;
  v_rule_id uuid;
  v_doc_id uuid;
  v_idem text;
  v_existing uuid;
  v_roles public.member_role[];
begin
  select * into v_parent
  from public.fiscal_documents
  where id = p_parent_fiscal_document_id
  for share;

  if not found then raise exception ''parent fiscal document not found''; end if;
  if v_parent.status is distinct from ''AUTHORIZED'' then
    raise exception ''parent must be AUTHORIZED'';
  end if;

  perform public.fiscal_assert_feature(v_parent.organization_id);

  v_roles := array[''owner'',''admin'',''accountant'']::public.member_role[];
  perform public.fiscal_assert_role(v_parent.organization_id, v_roles);

  select * into v_dtype
  from public.fiscal_document_types
  where internal_code = p_document_type_internal_code
    and enabled_phase5
    and operation_kind = case
      when p_relationship = ''CREDIT_NOTE'' then ''CREDIT_NOTE''::public.fiscal_operation_kind
      else ''DEBIT_NOTE''::public.fiscal_operation_kind
    end;

  if not found then
    raise exception ''note document type not enabled'';
  end if;
  if v_dtype.document_class is distinct from v_parent.document_class then
    raise exception ''note class must match parent class'';
  end if;

  v_idem := coalesce(p_idempotency_key, lower(p_relationship::text) || '':'' || p_parent_fiscal_document_id::text || '':'' || p_issue_date::text);
  select id into v_existing
  from public.fiscal_documents
  where organization_id = v_parent.organization_id and idempotency_key = v_idem;
  if v_existing is not null then return v_existing; end if;

  v_rule_id := public.resolve_fiscal_rule_version(v_parent.organization_id, p_issue_date);

  insert into public.fiscal_documents (
    organization_id, branch_id, sales_document_id, fiscal_environment,
    document_type_id, document_class, arca_cbte_tipo,
    point_of_sale_id, arca_point_of_sale, issue_date, counterparty_id,
    issuer_snapshot, receiver_snapshot, currency_code, currency_rate, concept_type,
    net_taxed_amount, net_exempt_amount, net_untaxed_amount, vat_amount,
    other_taxes_amount, total_amount, status, accounting_status,
    related_fiscal_document_id, relationship_type, fiscal_rule_version_id,
    idempotency_key, created_by
  ) values (
    v_parent.organization_id, v_parent.branch_id, null, v_parent.fiscal_environment,
    v_dtype.id, v_dtype.document_class, v_dtype.arca_cbte_tipo,
    v_parent.point_of_sale_id, v_parent.arca_point_of_sale, p_issue_date, v_parent.counterparty_id,
    v_parent.issuer_snapshot, v_parent.receiver_snapshot, v_parent.currency_code, v_parent.currency_rate, v_parent.concept_type,
    v_parent.net_taxed_amount, v_parent.net_exempt_amount, v_parent.net_untaxed_amount, v_parent.vat_amount,
    v_parent.other_taxes_amount, v_parent.total_amount, ''DRAFT'', ''NOT_APPLICABLE'',
    v_parent.id, p_relationship, v_rule_id,
    v_idem, auth.uid()
  )
  returning id into v_doc_id;

  insert into public.fiscal_document_lines (
    organization_id, fiscal_document_id, line_number, description, quantity, unit_price,
    discount_amount, vat_treatment, vat_rate_code, vat_rate,
    net_amount, vat_amount, exempt_amount, untaxed_amount, line_total
  )
  select
    organization_id, v_doc_id, line_number, description, quantity, unit_price,
    discount_amount, vat_treatment, vat_rate_code, vat_rate,
    net_amount, vat_amount, exempt_amount, untaxed_amount, line_total
  from public.fiscal_document_lines
  where fiscal_document_id = v_parent.id;

  insert into public.fiscal_tax_summaries (
    organization_id, fiscal_document_id, summary_kind, code, base_amount, rate, amount
  )
  select organization_id, v_doc_id, summary_kind, code, base_amount, rate, amount
  from public.fiscal_tax_summaries
  where fiscal_document_id = v_parent.id;

  return v_doc_id;
end;
$$"}', 'phase5_prepare_note_lint_fix'),
	('20260501170000', '{"-- Phase 5 — Advisor FK covering indexes (documentation + NEW indexes only)
--
-- Source audit: migrations 20260501100000 … 20260501160000
-- Findings: docs/qa/PHASE5-ADVISOR-AUDIT-FINDINGS.md
-- Script: scripts/phase5-advisor-audit.mjs
--
-- Scope: public.fiscal_* tables only.
-- Does NOT change RLS / FOR ALL policies (listed in findings; apply separately).
-- Idempotent: create index if not exists — no duplicates of indexes from
-- 20260501100000 / 20260501150000.
--
-- Already covered (do NOT recreate):
--   fiscal_documents_created_by_idx, fiscal_documents_journal_entry_id_idx,
--   fiscal_documents_related_idx, fiscal_documents_rule_version_idx,
--   fiscal_documents_document_type_idx, fiscal_documents_sales_idx,
--   fiscal_documents_org_status_date_idx, fiscal_documents_org_id_unique,
--   fiscal_document_lines_org_doc_idx, fiscal_authorization_attempts_doc_idx,
--   fiscal_authorization_attempts_org_idx, fiscal_points_of_sale unique/org indexes,
--   fiscal_credential_metadata_org_env_idx, fiscal_accounting_mappings UNIQUE(organization_id)

-- ---------------------------------------------------------------------------
-- Missing FK covering indexes
-- ---------------------------------------------------------------------------

-- fiscal_rule_versions_reviewed_by_fkey
create index if not exists fiscal_rule_versions_reviewed_by_idx
  on public.fiscal_rule_versions (reviewed_by)
  where reviewed_by is not null","-- fiscal_rule_versions_activated_by_fkey
create index if not exists fiscal_rule_versions_activated_by_idx
  on public.fiscal_rule_versions (activated_by)
  where activated_by is not null","-- fiscal_pos_org_branch_fk
create index if not exists fiscal_points_of_sale_org_branch_idx
  on public.fiscal_points_of_sale (organization_id, branch_id)","-- fiscal_documents_org_counterparty_fk
create index if not exists fiscal_documents_org_counterparty_idx
  on public.fiscal_documents (organization_id, counterparty_id)","-- fiscal_documents_org_branch_fk
create index if not exists fiscal_documents_org_branch_idx
  on public.fiscal_documents (organization_id, branch_id)","-- fiscal_documents_org_pos_fk
create index if not exists fiscal_documents_org_pos_idx
  on public.fiscal_documents (organization_id, point_of_sale_id)","-- fiscal_tax_summaries_organization_id_fkey + fiscal_tax_summaries_org_doc_fk
-- (unique on fiscal_document_id,… does not lead with organization_id)
create index if not exists fiscal_tax_summaries_org_doc_idx
  on public.fiscal_tax_summaries (organization_id, fiscal_document_id)","-- fiscal_auth_attempts_org_doc_fk
-- (org_idx + doc_idx exist separately; composite FK needs joint leading columns)
create index if not exists fiscal_authorization_attempts_org_doc_idx
  on public.fiscal_authorization_attempts (organization_id, fiscal_document_id)","-- fiscal_accounting_mappings_sales_fk
create index if not exists fiscal_accounting_mappings_sales_account_idx
  on public.fiscal_accounting_mappings (organization_id, sales_account_id)","-- fiscal_accounting_mappings_vat_fk
create index if not exists fiscal_accounting_mappings_vat_account_idx
  on public.fiscal_accounting_mappings (organization_id, vat_output_account_id)","-- fiscal_accounting_mappings_recv_fk
create index if not exists fiscal_accounting_mappings_recv_account_idx
  on public.fiscal_accounting_mappings (organization_id, receivables_account_id)"}', 'phase5_advisor_fk_indexes'),
	('20260501200000', '{"-- Phase 5 — pre-live selfcheck RPC (service_role) for FK indexes + RLS + grants

create or replace function public.phase5_prelive_selfcheck()
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_missing_indexes text[] := array[]::text[];
  v_for_all_policies text[] := array[]::text[];
  v_auth_trusted text[] := array[]::text[];
  v_idx text;
  v_needed text[] := array[
    ''fiscal_rule_versions_reviewed_by_idx'',
    ''fiscal_rule_versions_activated_by_idx'',
    ''fiscal_points_of_sale_org_branch_idx'',
    ''fiscal_documents_org_counterparty_idx'',
    ''fiscal_documents_org_branch_idx'',
    ''fiscal_documents_org_pos_idx'',
    ''fiscal_tax_summaries_org_doc_idx'',
    ''fiscal_authorization_attempts_org_doc_idx'',
    ''fiscal_accounting_mappings_sales_account_idx'',
    ''fiscal_accounting_mappings_vat_account_idx'',
    ''fiscal_accounting_mappings_recv_account_idx''
  ];
begin
  if auth.role() is distinct from ''service_role'' then
    raise exception ''service_role required'';
  end if;

  foreach v_idx in array v_needed loop
    if not exists (
      select 1 from pg_indexes
      where schemaname = ''public'' and indexname = v_idx
    ) then
      v_missing_indexes := array_append(v_missing_indexes, v_idx);
    end if;
  end loop;

  select coalesce(array_agg(policyname order by policyname), array[]::text[])
  into v_for_all_policies
  from pg_policies
  where schemaname = ''public''
    and tablename like ''fiscal_%''
    and cmd = ''ALL'';

  select coalesce(array_agg(p.proname::text order by p.proname), array[]::text[])
  into v_auth_trusted
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = ''public''
    and p.proname in (
      ''begin_fiscal_authorization'',
      ''complete_fiscal_authorization'',
      ''set_fiscal_qr_payload''
    )
    and has_function_privilege(''authenticated'', p.oid, ''EXECUTE'');

  return jsonb_build_object(
    ''missing_fk_indexes'', to_jsonb(v_missing_indexes),
    ''fiscal_for_all_policies'', to_jsonb(v_for_all_policies),
    ''authenticated_can_execute_trusted'', to_jsonb(v_auth_trusted),
    ''ok'', (
      coalesce(array_length(v_missing_indexes, 1), 0) = 0
      and coalesce(array_length(v_for_all_policies, 1), 0) = 0
      and coalesce(array_length(v_auth_trusted, 1), 0) = 0
    )
  );
end;
$$","revoke all on function public.phase5_prelive_selfcheck() from public, anon, authenticated","grant execute on function public.phase5_prelive_selfcheck() to service_role"}', 'phase5_prelive_selfcheck'),
	('20260601100000', '{"-- Phase 6 — Purchases core (STAGING)
-- Approved adjustments: COMPLETED (not RECEIVED), ARS MVP, AP direction model

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.purchase_order_status as enum (
    ''DRAFT'', ''APPROVED'', ''COMPLETED'', ''CANCELLED''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.purchase_document_type as enum (
    ''SUPPLIER_INVOICE'', ''SUPPLIER_CREDIT_NOTE'', ''SUPPLIER_DEBIT_NOTE''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.purchase_document_status as enum (
    ''DRAFT'', ''REVIEWED'', ''POSTED'', ''REVERSED'', ''REJECTED''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.purchase_accounting_status as enum (
    ''NOT_APPLICABLE'', ''PENDING'', ''POSTED'', ''ERROR'', ''ACCOUNTING_REQUIRES_REVIEW''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.accounts_payable_status as enum (
    ''OPEN'', ''PARTIALLY_PAID'', ''PAID'', ''VOID''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.accounts_payable_direction as enum (
    ''AP_INCREASE'', ''AP_DECREASE''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.purchase_vat_treatment as enum (
    ''TAXED'', ''EXEMPT'', ''NOT_TAXED''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.purchase_relationship_type as enum (
    ''CREDIT_NOTE'', ''DEBIT_NOTE''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.purchase_attachment_kind as enum (
    ''SUPPLIER_PDF'', ''SCAN'', ''SUPPORTING_RECEIPT'', ''OTHER''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.purchase_line_unit_code as enum (
    ''UNIT'', ''HOUR'', ''KG'', ''M'', ''OTHER''
  );
exception when duplicate_object then null;
end $$","-- ---------------------------------------------------------------------------
-- Sequences
-- ---------------------------------------------------------------------------

create table public.purchase_order_sequences (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  sequence_year int not null check (sequence_year >= 2000 and sequence_year <= 2100),
  last_value bigint not null default 0 check (last_value >= 0),
  updated_at timestamptz not null default timezone(''utc'', now()),
  primary key (organization_id, sequence_year)
)","-- ---------------------------------------------------------------------------
-- purchase_orders
-- ---------------------------------------------------------------------------

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  supplier_id uuid not null,
  internal_number text not null,
  status public.purchase_order_status not null default ''DRAFT'',
  order_date date not null default (timezone(''utc'', now()))::date,
  expected_delivery_date date,
  currency_code text not null default ''ARS'' check (currency_code ~ ''^[A-Z]{3}$''),
  supplier_snapshot jsonb not null default ''{}''::jsonb,
  subtotal numeric(19, 4) not null default 0 check (subtotal >= 0),
  discount_total numeric(19, 4) not null default 0 check (discount_total >= 0),
  total numeric(19, 4) not null default 0 check (total >= 0),
  notes text,
  internal_notes text,
  created_by uuid references auth.users (id),
  approved_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  approved_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  constraint purchase_orders_org_id_unique unique (organization_id, id),
  constraint purchase_orders_internal_number_unique unique (organization_id, internal_number),
  constraint purchase_orders_org_supplier_fk
    foreign key (organization_id, supplier_id)
    references public.counterparties (organization_id, id)
    on delete restrict,
  constraint purchase_orders_org_branch_fk
    foreign key (organization_id, branch_id)
    references public.branches (organization_id, id)
    on delete restrict,
  constraint purchase_orders_ars_mvp check (currency_code = ''ARS'')
)","create index purchase_orders_org_status_date_idx
  on public.purchase_orders (organization_id, status, order_date desc)","create index purchase_orders_org_supplier_idx
  on public.purchase_orders (organization_id, supplier_id)","create index purchase_orders_created_by_idx
  on public.purchase_orders (created_by) where created_by is not null","create trigger purchase_orders_set_updated_at
before update on public.purchase_orders
for each row execute function public.set_updated_at()","create table public.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  purchase_order_id uuid not null,
  line_number int not null check (line_number > 0),
  description text not null check (length(trim(description)) >= 1),
  quantity numeric(18, 4) not null check (quantity > 0),
  unit_code public.purchase_line_unit_code not null default ''UNIT'',
  unit_price numeric(19, 4) not null check (unit_price >= 0),
  discount_amount numeric(19, 4) not null default 0 check (discount_amount >= 0),
  line_total numeric(19, 4) not null default 0 check (line_total >= 0),
  future_product_id uuid,
  notes text,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (purchase_order_id, line_number),
  constraint purchase_order_lines_org_po_fk
    foreign key (organization_id, purchase_order_id)
    references public.purchase_orders (organization_id, id)
    on delete cascade
)","create index purchase_order_lines_org_po_idx
  on public.purchase_order_lines (organization_id, purchase_order_id)","create trigger purchase_order_lines_set_updated_at
before update on public.purchase_order_lines
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- purchase_documents
-- ---------------------------------------------------------------------------

create table public.purchase_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  supplier_id uuid not null,
  purchase_order_id uuid,
  document_type public.purchase_document_type not null,
  document_class text,
  arca_cbte_tipo int,
  point_of_sale int check (point_of_sale is null or point_of_sale > 0),
  document_number bigint check (document_number is null or document_number > 0),
  issue_date date not null,
  accounting_date date not null,
  due_date date,
  payment_due_days int check (payment_due_days is null or payment_due_days >= 0),
  currency_code text not null default ''ARS'' check (currency_code ~ ''^[A-Z]{3}$''),
  currency_rate numeric(19, 6) not null default 1 check (currency_rate > 0),
  supplier_snapshot jsonb not null default ''{}''::jsonb,
  supplier_tax_id_normalized text,
  net_taxed_amount numeric(19, 4) not null default 0 check (net_taxed_amount >= 0),
  net_exempt_amount numeric(19, 4) not null default 0 check (net_exempt_amount >= 0),
  net_untaxed_amount numeric(19, 4) not null default 0 check (net_untaxed_amount >= 0),
  vat_amount numeric(19, 4) not null default 0 check (vat_amount >= 0),
  other_taxes_amount numeric(19, 4) not null default 0 check (other_taxes_amount >= 0),
  total_amount numeric(19, 4) not null default 0 check (total_amount >= 0),
  status public.purchase_document_status not null default ''DRAFT'',
  accounting_status public.purchase_accounting_status not null default ''NOT_APPLICABLE'',
  journal_entry_id uuid,
  reverse_journal_entry_id uuid,
  related_purchase_document_id uuid,
  relationship_type public.purchase_relationship_type,
  external_cae text,
  external_cae_expiration date,
  external_reference text,
  idempotency_key text not null,
  notes text,
  internal_notes text,
  created_by uuid references auth.users (id),
  reviewed_by uuid references auth.users (id),
  posted_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  reviewed_at timestamptz,
  posted_at timestamptz,
  constraint purchase_documents_org_id_unique unique (organization_id, id),
  constraint purchase_documents_idempotency_unique unique (organization_id, idempotency_key),
  constraint purchase_documents_org_supplier_fk
    foreign key (organization_id, supplier_id)
    references public.counterparties (organization_id, id)
    on delete restrict,
  constraint purchase_documents_org_branch_fk
    foreign key (organization_id, branch_id)
    references public.branches (organization_id, id)
    on delete restrict,
  constraint purchase_documents_org_po_fk
    foreign key (organization_id, purchase_order_id)
    references public.purchase_orders (organization_id, id)
    on delete restrict,
  constraint purchase_documents_related_fk
    foreign key (related_purchase_document_id)
    references public.purchase_documents (id)
    on delete restrict,
  constraint purchase_documents_journal_fk
    foreign key (journal_entry_id)
    references public.journal_entries (id)
    on delete restrict,
  constraint purchase_documents_reverse_journal_fk
    foreign key (reverse_journal_entry_id)
    references public.journal_entries (id)
    on delete restrict,
  constraint purchase_documents_ars_mvp check (
    currency_code = ''ARS'' and currency_rate = 1
  )
)","-- Normalized duplicate identity (POS/number as integers — no zero-padding ambiguity)
create unique index purchase_documents_supplier_voucher_uidx
  on public.purchase_documents (
    organization_id, supplier_id, document_type, point_of_sale, document_number
  )
  where point_of_sale is not null
    and document_number is not null
    and status is distinct from ''REJECTED''","create index purchase_documents_org_status_date_idx
  on public.purchase_documents (organization_id, status, issue_date desc)","create index purchase_documents_org_supplier_idx
  on public.purchase_documents (organization_id, supplier_id, issue_date desc)","create index purchase_documents_org_due_idx
  on public.purchase_documents (organization_id, due_date)
  where due_date is not null","create index purchase_documents_po_idx
  on public.purchase_documents (purchase_order_id)
  where purchase_order_id is not null","create index purchase_documents_journal_idx
  on public.purchase_documents (journal_entry_id)
  where journal_entry_id is not null","create index purchase_documents_related_idx
  on public.purchase_documents (related_purchase_document_id)
  where related_purchase_document_id is not null","create index purchase_documents_created_by_idx
  on public.purchase_documents (created_by)
  where created_by is not null","create trigger purchase_documents_set_updated_at
before update on public.purchase_documents
for each row execute function public.set_updated_at()","create table public.purchase_document_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  purchase_document_id uuid not null,
  line_number int not null check (line_number > 0),
  description text not null check (length(trim(description)) >= 1),
  quantity numeric(18, 4) not null check (quantity > 0),
  unit_code public.purchase_line_unit_code not null default ''UNIT'',
  unit_price numeric(19, 4) not null check (unit_price >= 0),
  discount_amount numeric(19, 4) not null default 0 check (discount_amount >= 0),
  vat_treatment public.purchase_vat_treatment not null default ''TAXED'',
  vat_rate_code text,
  vat_rate numeric(7, 4) check (vat_rate is null or (vat_rate >= 0 and vat_rate <= 100)),
  net_amount numeric(19, 4) not null default 0 check (net_amount >= 0),
  vat_amount numeric(19, 4) not null default 0 check (vat_amount >= 0),
  exempt_amount numeric(19, 4) not null default 0 check (exempt_amount >= 0),
  untaxed_amount numeric(19, 4) not null default 0 check (untaxed_amount >= 0),
  line_total numeric(19, 4) not null default 0 check (line_total >= 0),
  account_id uuid,
  cost_center_id uuid,
  future_product_id uuid,
  notes text,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (purchase_document_id, line_number),
  constraint purchase_document_lines_org_doc_fk
    foreign key (organization_id, purchase_document_id)
    references public.purchase_documents (organization_id, id)
    on delete cascade,
  constraint purchase_document_lines_org_account_fk
    foreign key (organization_id, account_id)
    references public.accounts (organization_id, id)
    on delete restrict
)","create index purchase_document_lines_org_doc_idx
  on public.purchase_document_lines (organization_id, purchase_document_id)","create index purchase_document_lines_account_idx
  on public.purchase_document_lines (organization_id, account_id)
  where account_id is not null","create trigger purchase_document_lines_set_updated_at
before update on public.purchase_document_lines
for each row execute function public.set_updated_at()","create table public.purchase_document_tax_summaries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  purchase_document_id uuid not null,
  summary_kind text not null check (summary_kind in (''IVA'', ''OTHER'')),
  code text not null,
  base_amount numeric(19, 4) not null default 0,
  rate numeric(7, 4),
  amount numeric(19, 4) not null default 0,
  unique (purchase_document_id, summary_kind, code),
  constraint purchase_tax_summaries_org_doc_fk
    foreign key (organization_id, purchase_document_id)
    references public.purchase_documents (organization_id, id)
    on delete cascade
)","create index purchase_tax_summaries_org_doc_idx
  on public.purchase_document_tax_summaries (organization_id, purchase_document_id)","comment on column public.purchase_documents.vat_amount is
  ''IVA INFORMADO on supplier document capture — NOT automatic IVA crédito fiscal eligibility.''"}', 'phase6_purchases_core'),
	('20260601110000', '{"-- Phase 6 — Accounts payable + accounting mappings + immutability

create table public.accounts_payable_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  supplier_id uuid not null,
  purchase_document_id uuid not null,
  direction public.accounts_payable_direction not null,
  original_amount numeric(19, 4) not null check (original_amount >= 0),
  open_amount numeric(19, 4) not null check (open_amount >= 0),
  currency_code text not null default ''ARS'' check (currency_code = ''ARS''),
  due_date date,
  status public.accounts_payable_status not null default ''OPEN'',
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (purchase_document_id),
  constraint accounts_payable_items_org_id_unique unique (organization_id, id),
  constraint accounts_payable_items_org_supplier_fk
    foreign key (organization_id, supplier_id)
    references public.counterparties (organization_id, id)
    on delete restrict,
  constraint accounts_payable_items_org_doc_fk
    foreign key (organization_id, purchase_document_id)
    references public.purchase_documents (organization_id, id)
    on delete restrict,
  constraint accounts_payable_open_lte_original check (open_amount <= original_amount)
)","create index accounts_payable_items_org_status_due_idx
  on public.accounts_payable_items (organization_id, status, due_date)","create index accounts_payable_items_org_supplier_idx
  on public.accounts_payable_items (organization_id, supplier_id)","create trigger accounts_payable_items_set_updated_at
before update on public.accounts_payable_items
for each row execute function public.set_updated_at()","-- Browser must not rewrite AP balances
create or replace function public.prevent_ap_client_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if tg_op = ''DELETE'' then
    if current_setting(''purchase.engine_write'', true) is distinct from ''1'' then
      raise exception ''accounts payable items cannot be deleted directly'';
    end if;
    return old;
  end if;
  if current_setting(''purchase.engine_write'', true) is distinct from ''1'' then
    if new.open_amount is distinct from old.open_amount
      or new.original_amount is distinct from old.original_amount
      or new.direction is distinct from old.direction
      or new.status is distinct from old.status
      or new.purchase_document_id is distinct from old.purchase_document_id
      or new.supplier_id is distinct from old.supplier_id
    then
      raise exception ''accounts payable monetary/status fields are engine-only'';
    end if;
  end if;
  return new;
end;
$$","create trigger accounts_payable_items_engine_only
before update or delete on public.accounts_payable_items
for each row execute function public.prevent_ap_client_mutation()","-- Purchase accounting mappings
create table public.purchase_accounting_mappings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  accounts_payable_account_id uuid not null,
  vat_input_account_id uuid not null,
  default_expense_account_id uuid,
  other_taxes_account_id uuid,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  unique (organization_id),
  constraint purchase_acct_map_ap_fk
    foreign key (organization_id, accounts_payable_account_id)
    references public.accounts (organization_id, id) on delete restrict,
  constraint purchase_acct_map_vat_fk
    foreign key (organization_id, vat_input_account_id)
    references public.accounts (organization_id, id) on delete restrict,
  constraint purchase_acct_map_expense_fk
    foreign key (organization_id, default_expense_account_id)
    references public.accounts (organization_id, id) on delete restrict,
  constraint purchase_acct_map_other_fk
    foreign key (organization_id, other_taxes_account_id)
    references public.accounts (organization_id, id) on delete restrict
)","create index purchase_acct_map_ap_idx
  on public.purchase_accounting_mappings (organization_id, accounts_payable_account_id)","create index purchase_acct_map_vat_idx
  on public.purchase_accounting_mappings (organization_id, vat_input_account_id)","create index purchase_acct_map_expense_idx
  on public.purchase_accounting_mappings (organization_id, default_expense_account_id)
  where default_expense_account_id is not null","create index purchase_acct_map_other_idx
  on public.purchase_accounting_mappings (organization_id, other_taxes_account_id)
  where other_taxes_account_id is not null","create trigger purchase_accounting_mappings_set_updated_at
before update on public.purchase_accounting_mappings
for each row execute function public.set_updated_at()","-- Attachments metadata
create table public.purchase_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  purchase_document_id uuid not null,
  kind public.purchase_attachment_kind not null default ''SUPPLIER_PDF'',
  storage_bucket text not null default ''purchase-evidence'',
  storage_path text not null,
  original_filename text not null,
  mime_type text not null,
  size_bytes bigint not null check (size_bytes >= 0),
  sha256_hash text,
  uploaded_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  constraint purchase_attachments_org_doc_fk
    foreign key (organization_id, purchase_document_id)
    references public.purchase_documents (organization_id, id)
    on delete cascade,
  unique (organization_id, storage_path)
)","create index purchase_attachments_org_doc_idx
  on public.purchase_attachments (organization_id, purchase_document_id)","create index purchase_attachments_uploaded_by_idx
  on public.purchase_attachments (uploaded_by)
  where uploaded_by is not null","comment on column public.purchase_attachments.sha256_hash is
  ''Evidence integrity only — NOT a legal digital signature.''","-- Posted document immutability
create or replace function public.prevent_posted_purchase_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if tg_op = ''DELETE'' then
    if old.status in (''POSTED'', ''REVERSED'') then
      raise exception ''posted/reversed purchase documents cannot be deleted'';
    end if;
    return old;
  end if;

  if old.status in (''POSTED'', ''REVERSED'')
    and current_setting(''purchase.engine_write'', true) is distinct from ''1'' then
    if new.supplier_id is distinct from old.supplier_id
      or new.document_type is distinct from old.document_type
      or new.point_of_sale is distinct from old.point_of_sale
      or new.document_number is distinct from old.document_number
      or new.issue_date is distinct from old.issue_date
      or new.total_amount is distinct from old.total_amount
      or new.vat_amount is distinct from old.vat_amount
      or new.net_taxed_amount is distinct from old.net_taxed_amount
      or new.supplier_snapshot is distinct from old.supplier_snapshot
      or new.currency_code is distinct from old.currency_code
      or new.status is distinct from old.status
      or new.related_purchase_document_id is distinct from old.related_purchase_document_id
    then
      raise exception ''posted purchase documents are commercially immutable'';
    end if;
  end if;
  return new;
end;
$$","create trigger purchase_documents_prevent_posted_mutation
before update or delete on public.purchase_documents
for each row execute function public.prevent_posted_purchase_mutation()","create or replace function public.prevent_posted_purchase_line_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  v_status public.purchase_document_status;
begin
  select status into v_status
  from public.purchase_documents
  where id = coalesce(new.purchase_document_id, old.purchase_document_id);

  if v_status in (''POSTED'', ''REVERSED'')
    and current_setting(''purchase.engine_write'', true) is distinct from ''1'' then
    raise exception ''lines on posted purchase documents cannot be modified'';
  end if;
  if tg_op = ''DELETE'' then return old; end if;
  return new;
end;
$$","create trigger purchase_document_lines_prevent_posted_mutation
before insert or update or delete on public.purchase_document_lines
for each row execute function public.prevent_posted_purchase_line_mutation()"}', 'phase6_accounts_payable'),
	('20260601120000', '{"-- Phase 6 — Purchase RPCs (numbering, approve OC, review, post, reverse)

create or replace function public.purchase_assert_feature(p_org_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''''
as $$
declare v_ok boolean;
begin
  select exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = ''purchases''
      and ofeat.status = ''enabled''
  ) into v_ok;
  if not coalesce(v_ok, false) then
    raise exception ''purchases feature is not enabled for this organization'';
  end if;
end;
$$","create or replace function public.purchase_assert_role(
  p_org_id uuid,
  p_roles public.member_role[]
)
returns void
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if not public.has_org_role(p_org_id, p_roles) then
    raise exception ''insufficient role for purchase operation'';
  end if;
end;
$$","create or replace function public.assert_active_supplier(
  p_org_id uuid,
  p_supplier_id uuid
)
returns void
language plpgsql
security invoker
set search_path = ''''
as $$
declare v_active boolean; v_role boolean;
begin
  select c.is_active into v_active
  from public.counterparties c
  where c.organization_id = p_org_id and c.id = p_supplier_id;
  if not found then raise exception ''supplier not found''; end if;
  if not coalesce(v_active, false) then raise exception ''supplier is inactive''; end if;

  select exists (
    select 1 from public.counterparty_roles r
    where r.organization_id = p_org_id
      and r.counterparty_id = p_supplier_id
      and r.role = ''SUPPLIER''
  ) into v_role;
  if not coalesce(v_role, false) then
    raise exception ''counterparty does not have SUPPLIER role'';
  end if;
end;
$$","create or replace function public.next_purchase_order_number(p_org_id uuid)
returns text
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_year int := extract(year from timezone(''utc'', now()))::int;
  v_next bigint;
begin
  if auth.uid() is null then raise exception ''authentication required''; end if;
  perform public.purchase_assert_feature(p_org_id);
  perform public.purchase_assert_role(
    p_org_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  );

  insert into public.purchase_order_sequences (organization_id, sequence_year, last_value)
  values (p_org_id, v_year, 1)
  on conflict (organization_id, sequence_year)
  do update set
    last_value = public.purchase_order_sequences.last_value + 1,
    updated_at = timezone(''utc'', now())
  returning last_value into v_next;

  return ''OC-'' || v_year::text || ''-'' || lpad(v_next::text, 6, ''0'');
end;
$$","create or replace function public.build_supplier_snapshot(
  p_org_id uuid,
  p_supplier_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''''
as $$
declare v_snap jsonb;
begin
  select jsonb_build_object(
    ''counterparty_id'', c.id,
    ''legal_name'', c.legal_name,
    ''trade_name'', c.trade_name,
    ''tax_id_type'', c.tax_id_type,
    ''tax_id'', c.tax_id,
    ''tax_id_normalized'', c.tax_id_normalized,
    ''fiscal_condition_code'', fc.code,
    ''fiscal_address'', cfp.fiscal_address
  )
  into v_snap
  from public.counterparties c
  left join public.counterparty_fiscal_profiles cfp
    on cfp.organization_id = c.organization_id and cfp.counterparty_id = c.id
  left join public.fiscal_conditions fc on fc.id = cfp.fiscal_condition_id
  where c.organization_id = p_org_id and c.id = p_supplier_id;

  if v_snap is null then raise exception ''supplier not found for snapshot''; end if;
  return v_snap;
end;
$$","create or replace function public.approve_purchase_order(p_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_po public.purchase_orders%rowtype;
begin
  if v_uid is null then raise exception ''authentication required''; end if;

  select * into v_po from public.purchase_orders where id = p_order_id for update;
  if not found then raise exception ''purchase order not found''; end if;

  perform public.purchase_assert_feature(v_po.organization_id);
  perform public.purchase_assert_role(
    v_po.organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]
  );
  perform public.assert_active_supplier(v_po.organization_id, v_po.supplier_id);

  if v_po.status is distinct from ''DRAFT'' then
    raise exception ''only DRAFT purchase orders can be approved'';
  end if;
  if not exists (
    select 1 from public.purchase_order_lines where purchase_order_id = p_order_id
  ) then
    raise exception ''purchase order has no lines'';
  end if;

  update public.purchase_orders
  set status = ''APPROVED'',
      approved_by = v_uid,
      approved_at = timezone(''utc'', now()),
      supplier_snapshot = public.build_supplier_snapshot(v_po.organization_id, v_po.supplier_id),
      updated_at = timezone(''utc'', now())
  where id = p_order_id;

  return p_order_id;
end;
$$","create or replace function public.complete_purchase_order(p_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare v_po public.purchase_orders%rowtype;
begin
  if auth.uid() is null then raise exception ''authentication required''; end if;
  select * into v_po from public.purchase_orders where id = p_order_id for update;
  if not found then raise exception ''purchase order not found''; end if;
  perform public.purchase_assert_feature(v_po.organization_id);
  perform public.purchase_assert_role(
    v_po.organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]
  );
  if v_po.status is distinct from ''APPROVED'' then
    raise exception ''only APPROVED purchase orders can be completed'';
  end if;
  -- COMPLETED = commercial/documentary completion — NOT inventory receiving
  update public.purchase_orders
  set status = ''COMPLETED'',
      completed_at = timezone(''utc'', now()),
      updated_at = timezone(''utc'', now())
  where id = p_order_id;
  return p_order_id;
end;
$$","create or replace function public.mark_purchase_reviewed(p_document_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare v_doc public.purchase_documents%rowtype;
begin
  if auth.uid() is null then raise exception ''authentication required''; end if;
  select * into v_doc from public.purchase_documents where id = p_document_id for update;
  if not found then raise exception ''purchase document not found''; end if;
  perform public.purchase_assert_feature(v_doc.organization_id);
  perform public.purchase_assert_role(
    v_doc.organization_id,
    array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[]
  );
  if v_doc.status not in (''DRAFT'', ''REJECTED'') then
    raise exception ''cannot review from status %'', v_doc.status;
  end if;
  if v_doc.currency_code is distinct from ''ARS'' then
    raise exception ''Phase 6 MVP allows ARS only'';
  end if;
  if abs(
    (v_doc.net_taxed_amount + v_doc.net_exempt_amount + v_doc.net_untaxed_amount
      + v_doc.vat_amount + v_doc.other_taxes_amount) - v_doc.total_amount
  ) > 0.01 then
    raise exception ''purchase totals do not reconcile'';
  end if;
  if not exists (
    select 1 from public.purchase_document_lines where purchase_document_id = p_document_id
  ) then
    raise exception ''purchase document has no lines'';
  end if;

  update public.purchase_documents
  set status = ''REVIEWED'',
      reviewed_by = auth.uid(),
      reviewed_at = timezone(''utc'', now()),
      updated_at = timezone(''utc'', now())
  where id = p_document_id;
  return p_document_id;
end;
$$","create or replace function public.post_purchase_document(p_document_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.purchase_documents%rowtype;
  v_map public.purchase_accounting_mappings%rowtype;
  v_period_id uuid;
  v_entry_id uuid;
  v_existing uuid;
  v_direction public.accounts_payable_direction;
  v_expense_account uuid;
  v_line record;
  v_line_no int := 0;
  v_expense_total numeric(19,4);
  v_ap_total numeric(19,4);
  v_lines_expense numeric(19,4);
  v_snap jsonb;
begin
  if v_uid is null then raise exception ''authentication required''; end if;

  select * into v_doc from public.purchase_documents where id = p_document_id for update;
  if not found then raise exception ''purchase document not found''; end if;

  perform public.purchase_assert_feature(v_doc.organization_id);
  perform public.purchase_assert_role(
    v_doc.organization_id,
    array[''owner'',''admin'',''accountant'']::public.member_role[]
  );

  -- Idempotent: already posted
  if v_doc.status = ''POSTED'' and v_doc.journal_entry_id is not null then
    return p_document_id;
  end if;

  if v_doc.status is distinct from ''REVIEWED'' then
    raise exception ''document must be REVIEWED before posting'';
  end if;

  if v_doc.currency_code is distinct from ''ARS'' then
    raise exception ''unsupported currency for Phase 6: %'', v_doc.currency_code;
  end if;

  perform public.assert_active_supplier(v_doc.organization_id, v_doc.supplier_id);

  if abs(
    (v_doc.net_taxed_amount + v_doc.net_exempt_amount + v_doc.net_untaxed_amount
      + v_doc.vat_amount + v_doc.other_taxes_amount) - v_doc.total_amount
  ) > 0.01 then
    raise exception ''purchase totals do not reconcile'';
  end if;

  select * into v_map
  from public.purchase_accounting_mappings
  where organization_id = v_doc.organization_id;
  if not found then
    raise exception ''Falta configurar el mapeo contable de compras'';
  end if;

  if v_doc.other_taxes_amount > 0 and v_map.other_taxes_account_id is null then
    raise exception ''Falta configurar la cuenta contable para otros impuestos.'';
  end if;

  -- Closed period → require review, no partial journal, never rewrite issue_date
  -- Persist status and return (do not RAISE — that would roll back the status write).
  select period_id into v_period_id
  from public.resolve_open_period(v_doc.organization_id, v_doc.accounting_date);
  if v_period_id is null then
    perform set_config(''purchase.engine_write'', ''1'', true);
    update public.purchase_documents
    set accounting_status = ''ACCOUNTING_REQUIRES_REVIEW'',
        updated_at = timezone(''utc'', now())
    where id = p_document_id;
    return p_document_id;
  end if;

  -- Existing journal for this source? (idempotent retry)
  select id into v_existing
  from public.journal_entries
  where organization_id = v_doc.organization_id
    and source_type = ''PURCHASE''
    and source_id = p_document_id
    and status = ''POSTED''
  limit 1;
  if v_existing is not null then
    perform set_config(''purchase.engine_write'', ''1'', true);
    update public.purchase_documents
    set status = ''POSTED'',
        journal_entry_id = v_existing,
        accounting_status = ''POSTED'',
        supplier_snapshot = case
          when supplier_snapshot = ''{}''::jsonb
            then public.build_supplier_snapshot(v_doc.organization_id, v_doc.supplier_id)
          else supplier_snapshot
        end,
        posted_by = coalesce(posted_by, v_uid),
        posted_at = coalesce(posted_at, timezone(''utc'', now())),
        updated_at = timezone(''utc'', now())
    where id = p_document_id;

    insert into public.accounts_payable_items (
      organization_id, supplier_id, purchase_document_id, direction,
      original_amount, open_amount, currency_code, due_date, status
    ) values (
      v_doc.organization_id, v_doc.supplier_id, p_document_id,
      case
        when v_doc.document_type = ''SUPPLIER_CREDIT_NOTE''
          then ''AP_DECREASE''::public.accounts_payable_direction
        else ''AP_INCREASE''::public.accounts_payable_direction
      end,
      v_doc.total_amount, v_doc.total_amount, ''ARS'', v_doc.due_date, ''OPEN''
    )
    on conflict (purchase_document_id) do nothing;

    return p_document_id;
  end if;

  v_snap := public.build_supplier_snapshot(v_doc.organization_id, v_doc.supplier_id);
  v_direction := case
    when v_doc.document_type = ''SUPPLIER_CREDIT_NOTE'' then ''AP_DECREASE''::public.accounts_payable_direction
    else ''AP_INCREASE''::public.accounts_payable_direction
  end;

  v_expense_total := v_doc.net_taxed_amount + v_doc.net_exempt_amount + v_doc.net_untaxed_amount;
  v_ap_total := v_doc.total_amount;

  select coalesce(sum(net_amount + exempt_amount + untaxed_amount), 0)
    into v_lines_expense
  from public.purchase_document_lines
  where purchase_document_id = p_document_id;

  if abs(v_lines_expense - v_expense_total) > 0.01 then
    raise exception ''line net totals do not match document expense totals'';
  end if;

  insert into public.journal_entries (
    organization_id, entry_date, description, status, source_type, source_id, created_by
  ) values (
    v_doc.organization_id,
    v_doc.accounting_date,
    ''Compra '' || v_doc.document_type::text || '' '' || coalesce(v_doc.point_of_sale::text || ''-'', '''') || coalesce(v_doc.document_number::text, ''''),
    ''DRAFT'',
    ''PURCHASE'',
    p_document_id,
    v_uid
  )
  returning id into v_entry_id;

  -- Build lines depending on direction
  if v_direction = ''AP_INCREASE'' then
    -- Debit expenses (from lines or default)
    for v_line in
      select * from public.purchase_document_lines
      where purchase_document_id = p_document_id
      order by line_number
    loop
      v_line_no := v_line_no + 1;
      v_expense_account := coalesce(v_line.account_id, v_map.default_expense_account_id);
      if v_expense_account is null then
        raise exception ''Falta cuenta de gasto en línea % o mapeo default_expense_account'', v_line.line_number;
      end if;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id, cost_center_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_expense_account, v_line.description,
        v_line.net_amount + v_line.exempt_amount + v_line.untaxed_amount, 0,
        v_doc.supplier_id, v_line.cost_center_id
      );
    end loop;

    if v_doc.vat_amount > 0 then
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_map.vat_input_account_id,
        ''IVA informado (captura comprobante)'',
        v_doc.vat_amount, 0, v_doc.supplier_id
      );
    end if;

    if v_doc.other_taxes_amount > 0 then
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_map.other_taxes_account_id,
        ''Otros impuestos del comprobante'',
        v_doc.other_taxes_amount, 0, v_doc.supplier_id
      );
    end if;

    v_line_no := v_line_no + 1;
    insert into public.journal_entry_lines (
      organization_id, journal_entry_id, line_number, account_id, description,
      debit, credit, counterparty_id
    ) values (
      v_doc.organization_id, v_entry_id, v_line_no, v_map.accounts_payable_account_id,
      ''Proveedores'',
      0, v_ap_total, v_doc.supplier_id
    );
  else
    -- AP_DECREASE (credit note): debit AP, credit expense/VAT/other
    v_line_no := 1;
    insert into public.journal_entry_lines (
      organization_id, journal_entry_id, line_number, account_id, description,
      debit, credit, counterparty_id
    ) values (
      v_doc.organization_id, v_entry_id, v_line_no, v_map.accounts_payable_account_id,
      ''Proveedores (NC)'',
      v_ap_total, 0, v_doc.supplier_id
    );

    for v_line in
      select * from public.purchase_document_lines
      where purchase_document_id = p_document_id
      order by line_number
    loop
      v_line_no := v_line_no + 1;
      v_expense_account := coalesce(v_line.account_id, v_map.default_expense_account_id);
      if v_expense_account is null then
        raise exception ''Falta cuenta de gasto en línea % o mapeo default_expense_account'', v_line.line_number;
      end if;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id, cost_center_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_expense_account, v_line.description,
        0, v_line.net_amount + v_line.exempt_amount + v_line.untaxed_amount,
        v_doc.supplier_id, v_line.cost_center_id
      );
    end loop;

    if v_doc.vat_amount > 0 then
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_map.vat_input_account_id,
        ''IVA informado (NC)'',
        0, v_doc.vat_amount, v_doc.supplier_id
      );
    end if;

    if v_doc.other_taxes_amount > 0 then
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_map.other_taxes_account_id,
        ''Otros impuestos (NC)'',
        0, v_doc.other_taxes_amount, v_doc.supplier_id
      );
    end if;
  end if;

  -- Post via Phase 2 engine; clean up DRAFT on failure (no partial journal)
  begin
    perform public.post_journal_entry(v_entry_id);
  exception when others then
    delete from public.journal_entries where id = v_entry_id and status = ''DRAFT'';
    raise;
  end;

  perform set_config(''purchase.engine_write'', ''1'', true);

  update public.purchase_documents
  set status = ''POSTED'',
      accounting_status = ''POSTED'',
      journal_entry_id = v_entry_id,
      supplier_snapshot = v_snap,
      supplier_tax_id_normalized = v_snap->>''tax_id_normalized'',
      posted_by = v_uid,
      posted_at = timezone(''utc'', now()),
      updated_at = timezone(''utc'', now())
  where id = p_document_id;

  -- AP item (idempotent via unique purchase_document_id)
  insert into public.accounts_payable_items (
    organization_id, supplier_id, purchase_document_id, direction,
    original_amount, open_amount, currency_code, due_date, status
  ) values (
    v_doc.organization_id, v_doc.supplier_id, p_document_id, v_direction,
    v_ap_total, v_ap_total, ''ARS'', v_doc.due_date, ''OPEN''
  )
  on conflict (purchase_document_id) do nothing;

  return p_document_id;
end;
$$","create or replace function public.reverse_purchase_document(
  p_document_id uuid,
  p_reversal_date date default current_date,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_doc public.purchase_documents%rowtype;
  v_rev public.journal_entries%rowtype;
begin
  if auth.uid() is null then raise exception ''authentication required''; end if;
  select * into v_doc from public.purchase_documents where id = p_document_id for update;
  if not found then raise exception ''purchase document not found''; end if;
  perform public.purchase_assert_feature(v_doc.organization_id);
  perform public.purchase_assert_role(
    v_doc.organization_id,
    array[''owner'',''admin'',''accountant'']::public.member_role[]
  );

  if v_doc.status = ''REVERSED'' then
    return p_document_id; -- idempotent
  end if;
  if v_doc.status is distinct from ''POSTED'' or v_doc.journal_entry_id is null then
    raise exception ''only POSTED purchases with journal can be reversed'';
  end if;

  select * into v_rev from public.reverse_journal_entry(
    v_doc.journal_entry_id, p_reversal_date, coalesce(p_reason, ''Reversión compra'')
  );

  perform set_config(''purchase.engine_write'', ''1'', true);

  update public.purchase_documents
  set status = ''REVERSED'',
      reverse_journal_entry_id = v_rev.id,
      accounting_status = ''POSTED'',
      updated_at = timezone(''utc'', now())
  where id = p_document_id;

  update public.accounts_payable_items
  set status = ''VOID'',
      open_amount = 0,
      updated_at = timezone(''utc'', now())
  where purchase_document_id = p_document_id;

  return p_document_id;
end;
$$","create or replace function public.supplier_ap_net_open(p_org_id uuid, p_supplier_id uuid)
returns numeric
language sql
stable
security invoker
set search_path = ''''
as $$
  select coalesce(sum(
    case
      when direction = ''AP_INCREASE'' then open_amount
      when direction = ''AP_DECREASE'' then -open_amount
      else 0
    end
  ), 0)
  from public.accounts_payable_items
  where organization_id = p_org_id
    and supplier_id = p_supplier_id
    and status = ''OPEN'';
$$","revoke all on function public.purchase_assert_feature(uuid) from public, anon","revoke all on function public.purchase_assert_role(uuid, public.member_role[]) from public, anon","revoke all on function public.assert_active_supplier(uuid, uuid) from public, anon","revoke all on function public.next_purchase_order_number(uuid) from public, anon","revoke all on function public.build_supplier_snapshot(uuid, uuid) from public, anon","revoke all on function public.approve_purchase_order(uuid) from public, anon","revoke all on function public.complete_purchase_order(uuid) from public, anon","revoke all on function public.mark_purchase_reviewed(uuid) from public, anon","revoke all on function public.post_purchase_document(uuid) from public, anon","revoke all on function public.reverse_purchase_document(uuid, date, text) from public, anon","revoke all on function public.supplier_ap_net_open(uuid, uuid) from public, anon","grant execute on function public.next_purchase_order_number(uuid) to authenticated","grant execute on function public.build_supplier_snapshot(uuid, uuid) to authenticated","grant execute on function public.approve_purchase_order(uuid) to authenticated","grant execute on function public.complete_purchase_order(uuid) to authenticated","grant execute on function public.mark_purchase_reviewed(uuid) to authenticated","grant execute on function public.post_purchase_document(uuid) to authenticated","grant execute on function public.reverse_purchase_document(uuid, date, text) to authenticated","grant execute on function public.supplier_ap_net_open(uuid, uuid) to authenticated","grant execute on function public.assert_active_supplier(uuid, uuid) to authenticated"}', 'phase6_purchase_functions'),
	('20260601130000', '{"-- Phase 6 — RLS, grants, private storage, feature enable (STAGING QA only)

-- ---------------------------------------------------------------------------
-- RLS enable
-- ---------------------------------------------------------------------------

alter table public.purchase_order_sequences enable row level security","alter table public.purchase_orders enable row level security","alter table public.purchase_order_lines enable row level security","alter table public.purchase_documents enable row level security","alter table public.purchase_document_lines enable row level security","alter table public.purchase_document_tax_summaries enable row level security","alter table public.accounts_payable_items enable row level security","alter table public.purchase_accounting_mappings enable row level security","alter table public.purchase_attachments enable row level security","-- ---------------------------------------------------------------------------
-- purchase_order_sequences
-- ---------------------------------------------------------------------------

create policy purchase_order_sequences_select
  on public.purchase_order_sequences for select to authenticated
  using ((select public.is_org_member(organization_id)))","-- ---------------------------------------------------------------------------
-- purchase_orders
-- ---------------------------------------------------------------------------

create policy purchase_orders_select
  on public.purchase_orders for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy purchase_orders_insert
  on public.purchase_orders for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","create policy purchase_orders_update
  on public.purchase_orders for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","create policy purchase_orders_delete
  on public.purchase_orders for delete to authenticated
  using (
    status = ''DRAFT''
    and (select public.has_org_role(
      organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]
    ))
  )","-- ---------------------------------------------------------------------------
-- purchase_order_lines
-- ---------------------------------------------------------------------------

create policy purchase_order_lines_select
  on public.purchase_order_lines for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy purchase_order_lines_insert
  on public.purchase_order_lines for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","create policy purchase_order_lines_update
  on public.purchase_order_lines for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","create policy purchase_order_lines_delete
  on public.purchase_order_lines for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- purchase_documents
-- ---------------------------------------------------------------------------

create policy purchase_documents_select
  on public.purchase_documents for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy purchase_documents_insert
  on public.purchase_documents for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","create policy purchase_documents_update
  on public.purchase_documents for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy purchase_documents_delete
  on public.purchase_documents for delete to authenticated
  using (
    status = ''DRAFT''
    and (select public.has_org_role(
      organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]
    ))
  )","-- ---------------------------------------------------------------------------
-- purchase_document_lines
-- ---------------------------------------------------------------------------

create policy purchase_document_lines_select
  on public.purchase_document_lines for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy purchase_document_lines_insert
  on public.purchase_document_lines for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","create policy purchase_document_lines_update
  on public.purchase_document_lines for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","create policy purchase_document_lines_delete
  on public.purchase_document_lines for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- tax summaries
-- ---------------------------------------------------------------------------

create policy purchase_tax_summaries_select
  on public.purchase_document_tax_summaries for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy purchase_tax_summaries_insert
  on public.purchase_document_tax_summaries for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy purchase_tax_summaries_update
  on public.purchase_document_tax_summaries for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy purchase_tax_summaries_delete
  on public.purchase_document_tax_summaries for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- AP: SELECT only for clients — engine writes via SECURITY DEFINER
-- ---------------------------------------------------------------------------

create policy accounts_payable_items_select
  on public.accounts_payable_items for select to authenticated
  using ((select public.is_org_member(organization_id)))","-- ---------------------------------------------------------------------------
-- purchase_accounting_mappings
-- ---------------------------------------------------------------------------

create policy purchase_accounting_mappings_select
  on public.purchase_accounting_mappings for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy purchase_accounting_mappings_insert
  on public.purchase_accounting_mappings for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","create policy purchase_accounting_mappings_update
  on public.purchase_accounting_mappings for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","create policy purchase_accounting_mappings_delete
  on public.purchase_accounting_mappings for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- attachments metadata
-- ---------------------------------------------------------------------------

create policy purchase_attachments_select
  on public.purchase_attachments for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy purchase_attachments_insert
  on public.purchase_attachments for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy purchase_attachments_delete
  on public.purchase_attachments for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]
  )))","-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

grant select on public.purchase_order_sequences to authenticated","grant select, insert, update, delete on public.purchase_orders to authenticated","grant select, insert, update, delete on public.purchase_order_lines to authenticated","grant select, insert, update, delete on public.purchase_documents to authenticated","grant select, insert, update, delete on public.purchase_document_lines to authenticated","grant select, insert, update, delete on public.purchase_document_tax_summaries to authenticated","grant select on public.accounts_payable_items to authenticated","grant select, insert, update, delete on public.purchase_accounting_mappings to authenticated","grant select, insert, delete on public.purchase_attachments to authenticated","revoke all on public.purchase_order_sequences from anon","revoke all on public.purchase_orders from anon","revoke all on public.purchase_order_lines from anon","revoke all on public.purchase_documents from anon","revoke all on public.purchase_document_lines from anon","revoke all on public.purchase_document_tax_summaries from anon","revoke all on public.accounts_payable_items from anon","revoke all on public.purchase_accounting_mappings from anon","revoke all on public.purchase_attachments from anon","-- ---------------------------------------------------------------------------
-- Private storage bucket (NEVER public)
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  ''purchase-evidence'',
  ''purchase-evidence'',
  false,
  15728640, -- 15 MB
  array[''application/pdf'', ''image/jpeg'', ''image/png'', ''image/webp'']::text[]
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types","-- Path convention: {organization_id}/{purchase_document_id}/{filename}
create policy purchase_evidence_select
  on storage.objects for select to authenticated
  using (
    bucket_id = ''purchase-evidence''
    and (select public.is_org_member((storage.foldername(name))[1]::uuid))
  )","create policy purchase_evidence_insert
  on storage.objects for insert to authenticated
  with check (
    bucket_id = ''purchase-evidence''
    and (select public.has_org_role(
      (storage.foldername(name))[1]::uuid,
      array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
    ))
  )","create policy purchase_evidence_delete
  on storage.objects for delete to authenticated
  using (
    bucket_id = ''purchase-evidence''
    and (select public.has_org_role(
      (storage.foldername(name))[1]::uuid,
      array[''owner'',''admin'',''manager'']::public.member_role[]
    ))
  )","-- ---------------------------------------------------------------------------
-- Enable purchases ONLY for staging Demo QA orgs (never global prod)
-- ---------------------------------------------------------------------------

insert into public.organization_features (organization_id, feature_id, status, enabled_at)
select distinct c.organization_id, fc.id, ''enabled''::public.feature_status, timezone(''utc'', now())
from public.counterparties c
inner join public.feature_catalog fc on fc.code = ''purchases''
where c.legal_name ilike ''%Demo%''
on conflict (organization_id, feature_id) do update
  set status = excluded.status,
      enabled_at = coalesce(public.organization_features.enabled_at, excluded.enabled_at)"}', 'phase6_purchase_security'),
	('20260601140000', '{"-- Phase 6 — Advisor FK covering indexes

create index if not exists purchase_orders_approved_by_idx
  on public.purchase_orders (approved_by)
  where approved_by is not null","create index if not exists purchase_documents_reviewed_by_idx
  on public.purchase_documents (reviewed_by)
  where reviewed_by is not null","create index if not exists purchase_documents_posted_by_idx
  on public.purchase_documents (posted_by)
  where posted_by is not null","create index if not exists purchase_documents_reverse_journal_idx
  on public.purchase_documents (reverse_journal_entry_id)
  where reverse_journal_entry_id is not null","create index if not exists purchase_document_lines_cost_center_idx
  on public.purchase_document_lines (cost_center_id)
  where cost_center_id is not null","create index if not exists accounts_payable_items_doc_idx
  on public.accounts_payable_items (purchase_document_id)","create index if not exists purchase_attachments_uploaded_by_idx
  on public.purchase_attachments (uploaded_by)
  where uploaded_by is not null"}', 'phase6_advisor_indexes'),
	('20260601150000', '{"-- Phase 6 FINAL LIVE ADVISOR HARDENING (STAGING)
-- Covers 4 unindexed composite FKs reported by Performance Advisor.
--
-- Audit of CURRENT indexes (before this migration):
--
-- accounts_payable_items_org_doc_fk (organization_id, purchase_document_id)
--   HAD: unique(purchase_document_id), accounts_payable_items_doc_idx(purchase_document_id)
--   MISSING: left-prefix (organization_id, purchase_document_id)
--   NOTE: single-column doc_idx is redundant with UNIQUE(purchase_document_id)
--
-- purchase_documents_org_branch_fk (organization_id, branch_id)
--   HAD: org_status_date / org_supplier / org_due — none lead with (org, branch)
--   MISSING: (organization_id, branch_id)
--
-- purchase_documents_org_po_fk (organization_id, purchase_order_id)
--   HAD: purchase_documents_po_idx (purchase_order_id) WHERE NOT NULL
--   MISSING: left-prefix (organization_id, purchase_order_id)
--   REPLACE: drop single-column po_idx after creating composite (same access pattern
--            always scoped by organization_id in app queries; left-prefix covers FK)
--
-- purchase_orders_org_branch_fk (organization_id, branch_id)
--   HAD: org_status_date / org_supplier — none lead with (org, branch)
--   MISSING: (organization_id, branch_id)
--
-- Do NOT drop indexes solely for unused_index INFO (synthetic staging traffic).

-- 1) AP → purchase document composite FK
create index if not exists accounts_payable_items_org_doc_idx
  on public.accounts_payable_items (organization_id, purchase_document_id)","-- Redundant with UNIQUE(purchase_document_id); keep UNIQUE, drop duplicate btree
drop index if exists public.accounts_payable_items_doc_idx","-- 2) Purchase documents → branch composite FK (nullable branch)
create index if not exists purchase_documents_org_branch_idx
  on public.purchase_documents (organization_id, branch_id)
  where branch_id is not null","-- 3) Purchase documents → purchase order composite FK
--    Replaces purchase_documents_po_idx (purchase_order_id) — left-prefix covers FK
--    and org-scoped PO lookups.
create index if not exists purchase_documents_org_po_idx
  on public.purchase_documents (organization_id, purchase_order_id)
  where purchase_order_id is not null","drop index if exists public.purchase_documents_po_idx","-- 4) Purchase orders → branch composite FK (nullable branch)
create index if not exists purchase_orders_org_branch_idx
  on public.purchase_orders (organization_id, branch_id)
  where branch_id is not null","comment on index public.accounts_payable_items_org_doc_idx is
  ''Covers accounts_payable_items_org_doc_fk (organization_id, purchase_document_id)''","comment on index public.purchase_documents_org_branch_idx is
  ''Covers purchase_documents_org_branch_fk (organization_id, branch_id)''","comment on index public.purchase_documents_org_po_idx is
  ''Covers purchase_documents_org_po_fk; replaces purchase_documents_po_idx''","comment on index public.purchase_orders_org_branch_idx is
  ''Covers purchase_orders_org_branch_fk (organization_id, branch_id)''"}', 'phase6_final_advisor_fk_indexes'),
	('20260701100000', '{"-- Phase 7 — Treasury core (STAGING)
-- Approved: CASH|BANK only; OPENING_BALANCE|PAYMENT|COLLECTION|TRANSFER|ADJUSTMENT
-- No CLEARING. No cash_sessions. No editable current_balance truth.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.treasury_account_type as enum (''CASH'', ''BANK'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.treasury_operation_type as enum (
    ''OPENING_BALANCE'', ''PAYMENT'', ''COLLECTION'', ''TRANSFER'', ''ADJUSTMENT''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.treasury_operation_status as enum (
    ''DRAFT'', ''POSTED'', ''REVERSED''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.treasury_accounting_status as enum (
    ''PENDING'', ''POSTED'', ''ACCOUNTING_REQUIRES_REVIEW'', ''ERROR''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.treasury_leg_direction as enum (''INFLOW'', ''OUTFLOW'');
exception when duplicate_object then null;
end $$","-- ---------------------------------------------------------------------------
-- Sequences
-- ---------------------------------------------------------------------------

create table public.treasury_operation_sequences (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  operation_type public.treasury_operation_type not null,
  sequence_year int not null check (sequence_year >= 2000 and sequence_year <= 2100),
  last_value bigint not null default 0 check (last_value >= 0),
  updated_at timestamptz not null default timezone(''utc'', now()),
  primary key (organization_id, operation_type, sequence_year)
)","-- ---------------------------------------------------------------------------
-- treasury_accounts
-- ---------------------------------------------------------------------------

create table public.treasury_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  account_type public.treasury_account_type not null,
  code text not null check (length(trim(code)) >= 1),
  name text not null check (length(trim(name)) >= 1),
  currency_code text not null default ''ARS'' check (currency_code = ''ARS''),
  accounting_account_id uuid not null,
  bank_name text,
  account_mask text,
  cbu_cvu_alias text,
  is_active boolean not null default true,
  -- UX hint only — NOT monetary source of truth (truth = POSTED OPENING_BALANCE leg)
  opening_setup_note text,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
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
    account_type = ''BANK''
    or (bank_name is null and account_mask is null and cbu_cvu_alias is null)
  )
)","create index treasury_accounts_org_type_active_idx
  on public.treasury_accounts (organization_id, account_type, is_active)","create index treasury_accounts_org_branch_idx
  on public.treasury_accounts (organization_id, branch_id)
  where branch_id is not null","create index treasury_accounts_created_by_idx
  on public.treasury_accounts (created_by)
  where created_by is not null","create trigger treasury_accounts_set_updated_at
before update on public.treasury_accounts
for each row execute function public.set_updated_at()","comment on column public.treasury_accounts.opening_setup_note is
  ''Optional onboarding UX note only — monetary opening is OPENING_BALANCE treasury operation.''","-- ---------------------------------------------------------------------------
-- treasury_operations
-- ---------------------------------------------------------------------------

create table public.treasury_operations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  internal_number text not null,
  operation_type public.treasury_operation_type not null,
  status public.treasury_operation_status not null default ''DRAFT'',
  accounting_status public.treasury_accounting_status not null default ''PENDING'',
  operation_date date not null,
  counterparty_id uuid,
  amount numeric(19, 4) not null check (amount > 0),
  currency_code text not null default ''ARS'' check (currency_code = ''ARS''),
  reference text,
  description text not null check (length(trim(description)) >= 1),
  reason text,
  idempotency_key text not null,
  journal_entry_id uuid,
  reverse_journal_entry_id uuid,
  created_by uuid references auth.users (id),
  posted_by uuid references auth.users (id),
  reversed_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
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
    operation_type not in (''PAYMENT'', ''COLLECTION'') or counterparty_id is not null
  )
)","create index treasury_operations_org_status_date_idx
  on public.treasury_operations (organization_id, status, operation_date desc)","create index treasury_operations_org_type_date_idx
  on public.treasury_operations (organization_id, operation_type, operation_date desc)","create index treasury_operations_org_cp_date_idx
  on public.treasury_operations (organization_id, counterparty_id, operation_date desc)
  where counterparty_id is not null","create index treasury_operations_journal_idx
  on public.treasury_operations (journal_entry_id)
  where journal_entry_id is not null","create index treasury_operations_reverse_journal_idx
  on public.treasury_operations (reverse_journal_entry_id)
  where reverse_journal_entry_id is not null","create index treasury_operations_created_by_idx
  on public.treasury_operations (created_by)
  where created_by is not null","create index treasury_operations_posted_by_idx
  on public.treasury_operations (posted_by)
  where posted_by is not null","create index treasury_operations_org_branch_idx
  on public.treasury_operations (organization_id, branch_id)
  where branch_id is not null","create trigger treasury_operations_set_updated_at
before update on public.treasury_operations
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
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
  created_at timestamptz not null default timezone(''utc'', now()),
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
)","create index treasury_legs_org_account_op_idx
  on public.treasury_operation_legs (organization_id, treasury_account_id, treasury_operation_id)","create index treasury_legs_op_idx
  on public.treasury_operation_legs (treasury_operation_id)","create index treasury_legs_account_idx
  on public.treasury_operation_legs (treasury_account_id)","-- ---------------------------------------------------------------------------
-- Posted operation immutability (client)
-- ---------------------------------------------------------------------------

create or replace function public.prevent_posted_treasury_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if tg_op = ''DELETE'' then
    if old.status in (''POSTED'', ''REVERSED'')
      and current_setting(''treasury.engine_write'', true) is distinct from ''1'' then
      raise exception ''posted/reversed treasury operations cannot be deleted'';
    end if;
    return old;
  end if;

  if old.status in (''POSTED'', ''REVERSED'')
    and current_setting(''treasury.engine_write'', true) is distinct from ''1'' then
    if new.status is distinct from old.status
      or new.amount is distinct from old.amount
      or new.operation_type is distinct from old.operation_type
      or new.operation_date is distinct from old.operation_date
      or new.counterparty_id is distinct from old.counterparty_id
      or new.journal_entry_id is distinct from old.journal_entry_id
      or new.currency_code is distinct from old.currency_code
      or new.internal_number is distinct from old.internal_number
    then
      raise exception ''posted treasury operations are immutable; use reversal'';
    end if;
  end if;
  return new;
end;
$$","create trigger treasury_operations_prevent_posted_mutation
before update or delete on public.treasury_operations
for each row execute function public.prevent_posted_treasury_mutation()","create or replace function public.prevent_posted_treasury_leg_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  v_status public.treasury_operation_status;
begin
  select status into v_status
  from public.treasury_operations
  where id = coalesce(new.treasury_operation_id, old.treasury_operation_id);

  if v_status in (''POSTED'', ''REVERSED'')
    and current_setting(''treasury.engine_write'', true) is distinct from ''1'' then
    raise exception ''legs on posted treasury operations cannot be modified'';
  end if;
  if tg_op = ''DELETE'' then return old; end if;
  return new;
end;
$$","create trigger treasury_legs_prevent_posted_mutation
before insert or update or delete on public.treasury_operation_legs
for each row execute function public.prevent_posted_treasury_leg_mutation()","-- ---------------------------------------------------------------------------
-- Derived balance (POSTED legs only; REVERSED excluded)
-- ---------------------------------------------------------------------------

create or replace function public.treasury_account_balance(p_account_id uuid)
returns numeric
language sql
stable
security invoker
set search_path = ''''
as $$
  select coalesce(sum(
    case
      when l.direction = ''INFLOW'' then l.amount
      when l.direction = ''OUTFLOW'' then -l.amount
      else 0
    end
  ), 0)
  from public.treasury_operation_legs l
  join public.treasury_operations o
    on o.id = l.treasury_operation_id
   and o.organization_id = l.organization_id
  where l.treasury_account_id = p_account_id
    and o.status = ''POSTED'';
$$","comment on function public.treasury_account_balance(uuid) is
  ''INTERNAL treasury balance from POSTED legs only. Not bank-confirmed.''"}', 'phase7_treasury_core'),
	('20260701110000', '{"-- Phase 7 — Accounts receivable + Phase 5 handoff (NEW integration only)

do $$ begin
  create type public.accounts_receivable_direction as enum (
    ''AR_INCREASE'', ''AR_DECREASE''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.accounts_receivable_status as enum (
    ''OPEN'', ''PARTIALLY_COLLECTED'', ''COLLECTED'', ''VOID''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.ar_source_type as enum (''FISCAL_DOCUMENT'');
exception when duplicate_object then null;
end $$","create table public.accounts_receivable_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  customer_id uuid not null,
  source_type public.ar_source_type not null default ''FISCAL_DOCUMENT'',
  source_id uuid not null,
  fiscal_document_id uuid not null,
  direction public.accounts_receivable_direction not null,
  original_amount numeric(19, 4) not null check (original_amount >= 0),
  open_amount numeric(19, 4) not null check (open_amount >= 0),
  currency_code text not null default ''ARS'' check (currency_code = ''ARS''),
  due_date date,
  status public.accounts_receivable_status not null default ''OPEN'',
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
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
)","create index accounts_receivable_org_status_due_idx
  on public.accounts_receivable_items (organization_id, status, due_date)","create index accounts_receivable_org_customer_idx
  on public.accounts_receivable_items (organization_id, customer_id)","create index accounts_receivable_source_idx
  on public.accounts_receivable_items (organization_id, source_type, source_id)","create trigger accounts_receivable_items_set_updated_at
before update on public.accounts_receivable_items
for each row execute function public.set_updated_at()","comment on column public.accounts_receivable_items.due_date is
  ''Nullable — do not invent payment terms; UI may show Sin vencimiento informado.''","-- Engine-only AR mutation
create or replace function public.prevent_ar_client_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if tg_op = ''DELETE'' then
    if current_setting(''treasury.engine_write'', true) is distinct from ''1'' then
      raise exception ''accounts receivable items cannot be deleted directly'';
    end if;
    return old;
  end if;
  if current_setting(''treasury.engine_write'', true) is distinct from ''1'' then
    if new.open_amount is distinct from old.open_amount
      or new.original_amount is distinct from old.original_amount
      or new.direction is distinct from old.direction
      or new.status is distinct from old.status
      or new.fiscal_document_id is distinct from old.fiscal_document_id
      or new.customer_id is distinct from old.customer_id
      or new.source_id is distinct from old.source_id
    then
      raise exception ''accounts receivable monetary/status fields are engine-only'';
    end if;
  end if;
  return new;
end;
$$","create trigger accounts_receivable_items_engine_only
before update or delete on public.accounts_receivable_items
for each row execute function public.prevent_ar_client_mutation()","-- Extend Phase 6 AP trigger to also accept treasury.engine_write (NEW migration replaces fn)
create or replace function public.prevent_ap_client_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if tg_op = ''DELETE'' then
    if current_setting(''purchase.engine_write'', true) is distinct from ''1''
      and current_setting(''treasury.engine_write'', true) is distinct from ''1'' then
      raise exception ''accounts payable items cannot be deleted directly'';
    end if;
    return old;
  end if;
  if current_setting(''purchase.engine_write'', true) is distinct from ''1''
    and current_setting(''treasury.engine_write'', true) is distinct from ''1'' then
    if new.open_amount is distinct from old.open_amount
      or new.original_amount is distinct from old.original_amount
      or new.direction is distinct from old.direction
      or new.status is distinct from old.status
      or new.purchase_document_id is distinct from old.purchase_document_id
      or new.supplier_id is distinct from old.supplier_id
    then
      raise exception ''accounts payable monetary/status fields are engine-only'';
    end if;
  end if;
  return new;
end;
$$","-- Explicit trusted AR ensure (NOT called from SELECT/page render)
create or replace function public.ensure_ar_from_fiscal_document(p_fiscal_document_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.fiscal_documents%rowtype;
  v_existing uuid;
  v_direction public.accounts_receivable_direction;
  v_id uuid;
begin
  if v_uid is null then raise exception ''authentication required''; end if;

  select * into v_doc from public.fiscal_documents where id = p_fiscal_document_id for update;
  if not found then raise exception ''fiscal document not found''; end if;

  if not public.is_org_member(v_doc.organization_id) then
    raise exception ''not a member of organization'';
  end if;
  if not public.has_org_role(
    v_doc.organization_id,
    array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
  ) then
    raise exception ''insufficient role to create receivable'';
  end if;

  select id into v_existing
  from public.accounts_receivable_items
  where fiscal_document_id = p_fiscal_document_id;
  if v_existing is not null then
    return v_existing;
  end if;

  if v_doc.status is distinct from ''AUTHORIZED'' then
    raise exception ''only AUTHORIZED fiscal documents may create AR items'';
  end if;

  if v_doc.currency_code not in (''ARS'', ''PES'') then
    raise exception ''Phase 7 MVP AR requires ARS/PES fiscal documents'';
  end if;

  if v_doc.total_amount <= 0 then
    raise exception ''fiscal document total must be positive'';
  end if;

  v_direction := case
    when v_doc.document_class = ''CREDIT_NOTE'' then ''AR_DECREASE''::public.accounts_receivable_direction
    else ''AR_INCREASE''::public.accounts_receivable_direction
  end;

  perform set_config(''treasury.engine_write'', ''1'', true);

  insert into public.accounts_receivable_items (
    organization_id, customer_id, source_type, source_id, fiscal_document_id,
    direction, original_amount, open_amount, currency_code, due_date, status
  ) values (
    v_doc.organization_id, v_doc.counterparty_id, ''FISCAL_DOCUMENT'', v_doc.id, v_doc.id,
    v_direction, v_doc.total_amount, v_doc.total_amount, ''ARS'', null, ''OPEN''
  )
  on conflict (fiscal_document_id) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.accounts_receivable_items where fiscal_document_id = p_fiscal_document_id;
  end if;

  return v_id;
end;
$$","revoke all on function public.ensure_ar_from_fiscal_document(uuid) from public, anon","grant execute on function public.ensure_ar_from_fiscal_document(uuid) to authenticated","grant execute on function public.treasury_account_balance(uuid) to authenticated"}', 'phase7_accounts_receivable'),
	('20260701120000', '{"-- Phase 7 — Allocations + open-item compensations

do $$ begin
  create type public.open_item_domain as enum (''AP'', ''AR'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.compensation_status as enum (''POSTED'', ''REVERSED'');
exception when duplicate_object then null;
end $$","create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  treasury_operation_id uuid not null,
  accounts_payable_item_id uuid not null,
  allocated_amount numeric(19, 4) not null check (allocated_amount > 0),
  created_at timestamptz not null default timezone(''utc'', now()),
  unique (treasury_operation_id, accounts_payable_item_id),
  constraint payment_allocations_org_op_fk
    foreign key (organization_id, treasury_operation_id)
    references public.treasury_operations (organization_id, id)
    on delete cascade,
  constraint payment_allocations_org_ap_fk
    foreign key (organization_id, accounts_payable_item_id)
    references public.accounts_payable_items (organization_id, id)
    on delete restrict
)","create index payment_allocations_op_idx
  on public.payment_allocations (treasury_operation_id)","create index payment_allocations_ap_idx
  on public.payment_allocations (organization_id, accounts_payable_item_id)","create table public.collection_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  treasury_operation_id uuid not null,
  accounts_receivable_item_id uuid not null,
  allocated_amount numeric(19, 4) not null check (allocated_amount > 0),
  created_at timestamptz not null default timezone(''utc'', now()),
  unique (treasury_operation_id, accounts_receivable_item_id),
  constraint collection_allocations_org_op_fk
    foreign key (organization_id, treasury_operation_id)
    references public.treasury_operations (organization_id, id)
    on delete cascade,
  constraint collection_allocations_org_ar_fk
    foreign key (organization_id, accounts_receivable_item_id)
    references public.accounts_receivable_items (organization_id, id)
    on delete restrict
)","create index collection_allocations_op_idx
  on public.collection_allocations (treasury_operation_id)","create index collection_allocations_ar_idx
  on public.collection_allocations (organization_id, accounts_receivable_item_id)","create table public.open_item_compensations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  domain public.open_item_domain not null,
  increase_item_id uuid not null,
  decrease_item_id uuid not null,
  amount numeric(19, 4) not null check (amount > 0),
  status public.compensation_status not null default ''POSTED'',
  idempotency_key text not null,
  created_by uuid references auth.users (id),
  reversed_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  reversed_at timestamptz,
  unique (organization_id, idempotency_key),
  constraint open_item_compensations_distinct check (increase_item_id <> decrease_item_id)
)","create index open_item_compensations_org_domain_idx
  on public.open_item_compensations (organization_id, domain, status)","create index open_item_compensations_increase_idx
  on public.open_item_compensations (increase_item_id)","create index open_item_compensations_decrease_idx
  on public.open_item_compensations (decrease_item_id)","-- Block client mutation of allocations once operation is POSTED
create or replace function public.prevent_posted_allocation_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  v_status public.treasury_operation_status;
  v_op uuid := coalesce(new.treasury_operation_id, old.treasury_operation_id);
begin
  select status into v_status from public.treasury_operations where id = v_op;
  if v_status in (''POSTED'', ''REVERSED'')
    and current_setting(''treasury.engine_write'', true) is distinct from ''1'' then
    raise exception ''allocations on posted treasury operations are immutable'';
  end if;
  if tg_op = ''DELETE'' then return old; end if;
  return new;
end;
$$","create trigger payment_allocations_prevent_posted
before insert or update or delete on public.payment_allocations
for each row execute function public.prevent_posted_allocation_mutation()","create trigger collection_allocations_prevent_posted
before insert or update or delete on public.collection_allocations
for each row execute function public.prevent_posted_allocation_mutation()","-- Treasury accounting mappings
create table public.treasury_accounting_mappings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  accounts_payable_account_id uuid,
  accounts_receivable_account_id uuid,
  opening_equity_account_id uuid,
  adjustment_offset_account_id uuid,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
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
)","create index treasury_acct_map_ap_idx
  on public.treasury_accounting_mappings (organization_id, accounts_payable_account_id)
  where accounts_payable_account_id is not null","create index treasury_acct_map_ar_idx
  on public.treasury_accounting_mappings (organization_id, accounts_receivable_account_id)
  where accounts_receivable_account_id is not null","create index treasury_acct_map_equity_idx
  on public.treasury_accounting_mappings (organization_id, opening_equity_account_id)
  where opening_equity_account_id is not null","create index treasury_acct_map_adj_idx
  on public.treasury_accounting_mappings (organization_id, adjustment_offset_account_id)
  where adjustment_offset_account_id is not null","create trigger treasury_accounting_mappings_set_updated_at
before update on public.treasury_accounting_mappings
for each row execute function public.set_updated_at()"}', 'phase7_allocations'),
	('20260701130000', '{"-- Phase 7 — Treasury posting / reverse / compensation RPCs

create or replace function public.treasury_assert_feature(
  p_org_id uuid,
  p_codes text[]
)
returns void
language plpgsql
security invoker
set search_path = ''''
as $$
declare v_ok boolean;
begin
  select exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = any(p_codes)
      and ofeat.status = ''enabled''
  ) into v_ok;
  if not coalesce(v_ok, false) then
    raise exception ''required treasury feature not enabled (cash and/or banks)'';
  end if;
end;
$$","create or replace function public.next_treasury_operation_number(
  p_org_id uuid,
  p_operation_type public.treasury_operation_type
)
returns text
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_year int := extract(year from timezone(''utc'', now()))::int;
  v_next bigint;
  v_prefix text;
begin
  if auth.uid() is null then raise exception ''authentication required''; end if;
  perform public.treasury_assert_feature(p_org_id, array[''cash'',''banks'']);
  if not public.has_org_role(
    p_org_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role'';
  end if;

  v_prefix := case p_operation_type
    when ''OPENING_BALANCE'' then ''OPN''
    when ''PAYMENT'' then ''PAY''
    when ''COLLECTION'' then ''COL''
    when ''TRANSFER'' then ''TRF''
    when ''ADJUSTMENT'' then ''ADJ''
  end;

  insert into public.treasury_operation_sequences (organization_id, operation_type, sequence_year, last_value)
  values (p_org_id, p_operation_type, v_year, 1)
  on conflict (organization_id, operation_type, sequence_year)
  do update set
    last_value = public.treasury_operation_sequences.last_value + 1,
    updated_at = timezone(''utc'', now())
  returning last_value into v_next;

  return v_prefix || ''-'' || v_year::text || ''-'' || lpad(v_next::text, 6, ''0'');
end;
$$","create or replace function public.resolve_ap_account(p_org_id uuid)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''''
as $$
declare v_id uuid;
begin
  select accounts_payable_account_id into v_id
  from public.treasury_accounting_mappings where organization_id = p_org_id;
  if v_id is null then
    select accounts_payable_account_id into v_id
    from public.purchase_accounting_mappings where organization_id = p_org_id;
  end if;
  if v_id is null then
    select id into v_id from public.accounts
    where organization_id = p_org_id and system_role = ''payables'' and is_postable and is_active
    limit 1;
  end if;
  if v_id is null then raise exception ''Falta cuenta contable de proveedores''; end if;
  return v_id;
end;
$$","create or replace function public.resolve_ar_account(p_org_id uuid)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''''
as $$
declare v_id uuid;
begin
  select accounts_receivable_account_id into v_id
  from public.treasury_accounting_mappings where organization_id = p_org_id;
  if v_id is null then
    select receivables_account_id into v_id
    from public.fiscal_accounting_mappings where organization_id = p_org_id;
  end if;
  if v_id is null then
    select id into v_id from public.accounts
    where organization_id = p_org_id and system_role = ''receivables'' and is_postable and is_active
    limit 1;
  end if;
  if v_id is null then raise exception ''Falta cuenta contable de clientes''; end if;
  return v_id;
end;
$$","create or replace function public.resolve_opening_equity_account(p_org_id uuid)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''''
as $$
declare v_id uuid;
begin
  select opening_equity_account_id into v_id
  from public.treasury_accounting_mappings where organization_id = p_org_id;
  if v_id is null then
    select id into v_id from public.accounts
    where organization_id = p_org_id and system_role = ''capital'' and is_postable and is_active
    limit 1;
  end if;
  if v_id is null then raise exception ''Falta cuenta de patrimonio para saldo inicial''; end if;
  return v_id;
end;
$$","create or replace function public.resolve_adjustment_offset_account(p_org_id uuid)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''''
as $$
declare v_id uuid;
begin
  select adjustment_offset_account_id into v_id
  from public.treasury_accounting_mappings where organization_id = p_org_id;
  if v_id is null then
    raise exception ''Falta configurar la cuenta contrapartida de ajustes de tesorería'';
  end if;
  return v_id;
end;
$$","create or replace function public.post_open_item_compensation(
  p_domain public.open_item_domain,
  p_increase_item_id uuid,
  p_decrease_item_id uuid,
  p_amount numeric,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_org uuid;
  v_existing uuid;
  v_inc_open numeric(19,4);
  v_dec_open numeric(19,4);
  v_inc_dir text;
  v_dec_dir text;
  v_inc_cp uuid;
  v_dec_cp uuid;
  v_inc_status text;
  v_dec_status text;
  v_id uuid;
  v_ids uuid[];
begin
  if v_uid is null then raise exception ''authentication required''; end if;
  if p_amount is null or p_amount <= 0 then raise exception ''amount must be positive''; end if;
  if p_increase_item_id = p_decrease_item_id then raise exception ''items must differ''; end if;

  -- Lock in stable order
  v_ids := array(
    select x from unnest(array[p_increase_item_id, p_decrease_item_id]) as x order by 1
  );

  if p_domain = ''AP'' then
    select organization_id into v_org from public.accounts_payable_items where id = p_increase_item_id;
  else
    select organization_id into v_org from public.accounts_receivable_items where id = p_increase_item_id;
  end if;
  if v_org is null then raise exception ''increase item not found''; end if;

  if not public.has_org_role(
    v_org, array[''owner'',''admin'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role for compensation'';
  end if;

  select id into v_existing
  from public.open_item_compensations
  where organization_id = v_org and idempotency_key = p_idempotency_key;
  if v_existing is not null then return v_existing; end if;

  perform set_config(''treasury.engine_write'', ''1'', true);

  if p_domain = ''AP'' then
    perform 1 from public.accounts_payable_items where id = any(v_ids) order by id for update;
    select open_amount, direction::text, supplier_id, status::text
      into v_inc_open, v_inc_dir, v_inc_cp, v_inc_status
    from public.accounts_payable_items where id = p_increase_item_id;
    select open_amount, direction::text, supplier_id, status::text
      into v_dec_open, v_dec_dir, v_dec_cp, v_dec_status
    from public.accounts_payable_items where id = p_decrease_item_id;
    if v_inc_dir is distinct from ''AP_INCREASE'' or v_dec_dir is distinct from ''AP_DECREASE'' then
      raise exception ''AP compensation requires INCREASE and DECREASE items'';
    end if;
    if v_inc_cp is distinct from v_dec_cp then raise exception ''AP compensation requires same supplier''; end if;
    if p_amount > v_inc_open or p_amount > v_dec_open then
      raise exception ''compensation exceeds open amounts'';
    end if;
    update public.accounts_payable_items
    set open_amount = open_amount - p_amount,
        status = case
          when open_amount - p_amount = 0 then ''PAID''::public.accounts_payable_status
          else ''PARTIALLY_PAID''::public.accounts_payable_status
        end,
        updated_at = timezone(''utc'', now())
    where id = p_increase_item_id;
    update public.accounts_payable_items
    set open_amount = open_amount - p_amount,
        status = case
          when open_amount - p_amount = 0 then ''PAID''::public.accounts_payable_status
          else ''PARTIALLY_PAID''::public.accounts_payable_status
        end,
        updated_at = timezone(''utc'', now())
    where id = p_decrease_item_id;
  else
    perform 1 from public.accounts_receivable_items where id = any(v_ids) order by id for update;
    select open_amount, direction::text, customer_id, status::text
      into v_inc_open, v_inc_dir, v_inc_cp, v_inc_status
    from public.accounts_receivable_items where id = p_increase_item_id;
    select open_amount, direction::text, customer_id, status::text
      into v_dec_open, v_dec_dir, v_dec_cp, v_dec_status
    from public.accounts_receivable_items where id = p_decrease_item_id;
    if v_inc_dir is distinct from ''AR_INCREASE'' or v_dec_dir is distinct from ''AR_DECREASE'' then
      raise exception ''AR compensation requires INCREASE and DECREASE items'';
    end if;
    if v_inc_cp is distinct from v_dec_cp then raise exception ''AR compensation requires same customer''; end if;
    if p_amount > v_inc_open or p_amount > v_dec_open then
      raise exception ''compensation exceeds open amounts'';
    end if;
    update public.accounts_receivable_items
    set open_amount = open_amount - p_amount,
        status = case
          when open_amount - p_amount = 0 then ''COLLECTED''::public.accounts_receivable_status
          else ''PARTIALLY_COLLECTED''::public.accounts_receivable_status
        end,
        updated_at = timezone(''utc'', now())
    where id = p_increase_item_id;
    update public.accounts_receivable_items
    set open_amount = open_amount - p_amount,
        status = case
          when open_amount - p_amount = 0 then ''COLLECTED''::public.accounts_receivable_status
          else ''PARTIALLY_COLLECTED''::public.accounts_receivable_status
        end,
        updated_at = timezone(''utc'', now())
    where id = p_decrease_item_id;
  end if;

  insert into public.open_item_compensations (
    organization_id, domain, increase_item_id, decrease_item_id, amount,
    status, idempotency_key, created_by
  ) values (
    v_org, p_domain, p_increase_item_id, p_decrease_item_id, p_amount,
    ''POSTED'', p_idempotency_key, v_uid
  )
  returning id into v_id;

  return v_id;
end;
$$"}', 'phase7_accounting_helpers'),
	('20260701140000', '{"-- Phase 7 — post_treasury_operation + reverse_treasury_operation

create or replace function public.post_treasury_operation(p_operation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''''
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
  if v_uid is null then raise exception ''authentication required''; end if;

  select * into v_op from public.treasury_operations where id = p_operation_id for update;
  if not found then raise exception ''treasury operation not found''; end if;

  -- Tenant from protected row
  perform public.treasury_assert_feature(v_op.organization_id, array[''cash'',''banks'']);

  if v_op.status = ''POSTED'' and v_op.journal_entry_id is not null then
    return p_operation_id;
  end if;
  if v_op.status is distinct from ''DRAFT'' then
    raise exception ''only DRAFT operations can be posted'';
  end if;
  if v_op.currency_code is distinct from ''ARS'' then
    raise exception ''unsupported currency for Phase 7: %'', v_op.currency_code;
  end if;

  -- Permissions by type
  if v_op.operation_type = ''ADJUSTMENT'' then
    if not public.has_org_role(
      v_op.organization_id, array[''owner'',''accountant'']::public.member_role[]
    ) then
      raise exception ''only owner/accountant may post adjustments'';
    end if;
    if v_op.reason is null or char_length(trim(v_op.reason)) < 3 then
      raise exception ''adjustment reason is required'';
    end if;
  elsif v_op.operation_type in (''PAYMENT'', ''COLLECTION'', ''TRANSFER'', ''OPENING_BALANCE'') then
    if not public.has_org_role(
      v_op.organization_id,
      array[''owner'',''admin'',''accountant'']::public.member_role[]
    ) then
      raise exception ''insufficient role to post treasury operation'';
    end if;
  end if;

  -- Idempotent journal reuse
  select id into v_existing
  from public.journal_entries
  where organization_id = v_op.organization_id
    and source_id = p_operation_id
    and status = ''POSTED''
    and source_type in (''PAYMENT'',''COLLECTION'',''BANK'',''SYSTEM'')
  limit 1;
  if v_existing is not null then
    perform set_config(''treasury.engine_write'', ''1'', true);
    update public.treasury_operations
    set status = ''POSTED'', journal_entry_id = v_existing, accounting_status = ''POSTED'',
        posted_by = coalesce(posted_by, v_uid),
        posted_at = coalesce(posted_at, timezone(''utc'', now()))
    where id = p_operation_id;
    return p_operation_id;
  end if;

  select period_id into v_period_id
  from public.resolve_open_period(v_op.organization_id, v_op.operation_date);
  if v_period_id is null then
    perform set_config(''treasury.engine_write'', ''1'', true);
    update public.treasury_operations
    set accounting_status = ''ACCOUNTING_REQUIRES_REVIEW'', updated_at = timezone(''utc'', now())
    where id = p_operation_id;
    return p_operation_id;
  end if;

  select count(*)::int,
         coalesce(sum(case when direction=''INFLOW'' then amount else 0 end),0),
         coalesce(sum(case when direction=''OUTFLOW'' then amount else 0 end),0)
  into v_leg_count, v_inflow, v_outflow
  from public.treasury_operation_legs
  where treasury_operation_id = p_operation_id;

  -- Validate legs by type
  if v_op.operation_type = ''PAYMENT'' then
    if v_leg_count <> 1 or v_outflow <> v_op.amount or v_inflow <> 0 then
      raise exception ''PAYMENT requires exactly one OUTFLOW equal to amount'';
    end if;
  elsif v_op.operation_type = ''COLLECTION'' then
    if v_leg_count <> 1 or v_inflow <> v_op.amount or v_outflow <> 0 then
      raise exception ''COLLECTION requires exactly one INFLOW equal to amount'';
    end if;
  elsif v_op.operation_type = ''TRANSFER'' then
    if v_leg_count <> 2 or v_inflow <> v_op.amount or v_outflow <> v_op.amount then
      raise exception ''TRANSFER requires equal INFLOW and OUTFLOW'';
    end if;
    select treasury_account_id into v_src_acct from public.treasury_operation_legs
    where treasury_operation_id = p_operation_id and direction = ''OUTFLOW'';
    select treasury_account_id into v_dst_acct from public.treasury_operation_legs
    where treasury_operation_id = p_operation_id and direction = ''INFLOW'';
    if v_src_acct is not distinct from v_dst_acct then
      raise exception ''TRANSFER source and destination must differ'';
    end if;
  elsif v_op.operation_type = ''OPENING_BALANCE'' then
    if v_leg_count <> 1 or (v_inflow + v_outflow) <> v_op.amount then
      raise exception ''OPENING_BALANCE requires exactly one leg equal to amount'';
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
        and o.operation_type = ''OPENING_BALANCE''
        and o.status = ''POSTED''
        and o.id <> p_operation_id
    ) then
      raise exception ''treasury account already has a POSTED opening balance'';
    end if;
  elsif v_op.operation_type = ''ADJUSTMENT'' then
    if v_leg_count <> 1 or (v_inflow + v_outflow) <> v_op.amount then
      raise exception ''ADJUSTMENT requires exactly one leg equal to amount'';
    end if;
  end if;

  -- Active accounts
  for v_leg in
    select l.*, ta.accounting_account_id, ta.is_active, ta.currency_code as tac
    from public.treasury_operation_legs l
    join public.treasury_accounts ta on ta.id = l.treasury_account_id
    where l.treasury_operation_id = p_operation_id
  loop
    if not v_leg.is_active then raise exception ''treasury account inactive''; end if;
    if v_leg.tac is distinct from ''ARS'' then raise exception ''treasury account currency must be ARS''; end if;
  end loop;

  -- PAYMENT allocations + AP locks (stable id order)
  if v_op.operation_type = ''PAYMENT'' then
    select coalesce(sum(allocated_amount),0) into v_alloc_sum
    from public.payment_allocations where treasury_operation_id = p_operation_id;
    if v_alloc_sum <> v_op.amount then
      raise exception ''payment allocations must equal payment amount'';
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
      if v_alloc.ap_dir is distinct from ''AP_INCREASE'' then
        raise exception ''payments may only allocate to AP_INCREASE items'';
      end if;
      if v_alloc.ap_supplier is distinct from v_op.counterparty_id then
        raise exception ''AP allocation supplier mismatch'';
      end if;
      if v_alloc.allocated_amount > v_alloc.ap_open then
        raise exception ''allocation exceeds AP open amount (concurrency)'';
      end if;
    end loop;
  end if;

  if v_op.operation_type = ''COLLECTION'' then
    select coalesce(sum(allocated_amount),0) into v_alloc_sum
    from public.collection_allocations where treasury_operation_id = p_operation_id;
    if v_alloc_sum <> v_op.amount then
      raise exception ''collection allocations must equal collection amount'';
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
      if v_alloc.ar_dir is distinct from ''AR_INCREASE'' then
        raise exception ''collections may only allocate to AR_INCREASE items'';
      end if;
      if v_alloc.ar_customer is distinct from v_op.counterparty_id then
        raise exception ''AR allocation customer mismatch'';
      end if;
      if v_alloc.allocated_amount > v_alloc.ar_open then
        raise exception ''allocation exceeds AR open amount (concurrency)'';
      end if;
    end loop;
  end if;

  -- Build journal
  v_source := case v_op.operation_type
    when ''PAYMENT'' then ''PAYMENT''::public.journal_source_type
    when ''COLLECTION'' then ''COLLECTION''::public.journal_source_type
    when ''TRANSFER'' then ''BANK''::public.journal_source_type
    when ''OPENING_BALANCE'' then ''SYSTEM''::public.journal_source_type
    when ''ADJUSTMENT'' then ''SYSTEM''::public.journal_source_type
  end;
  v_desc := left(v_op.operation_type::text || '' '' || v_op.internal_number || '' '' || v_op.description, 500);

  insert into public.journal_entries (
    organization_id, entry_date, description, status, source_type, source_id, created_by
  ) values (
    v_op.organization_id, v_op.operation_date, v_desc, ''DRAFT'', v_source, p_operation_id, v_uid
  ) returning id into v_entry_id;

  begin
    if v_op.operation_type = ''PAYMENT'' then
      v_ap_coa := public.resolve_ap_account(v_op.organization_id);
      select ta.accounting_account_id into v_src_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = ''OUTFLOW'';
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit, counterparty_id
      ) values
        (v_op.organization_id, v_entry_id, 1, v_ap_coa, ''Pago proveedores'', v_op.amount, 0, v_op.counterparty_id),
        (v_op.organization_id, v_entry_id, 2, v_src_coa, ''Egreso tesorería'', 0, v_op.amount, v_op.counterparty_id);

    elsif v_op.operation_type = ''COLLECTION'' then
      v_ar_coa := public.resolve_ar_account(v_op.organization_id);
      select ta.accounting_account_id into v_dst_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = ''INFLOW'';
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit, counterparty_id
      ) values
        (v_op.organization_id, v_entry_id, 1, v_dst_coa, ''Ingreso tesorería'', v_op.amount, 0, v_op.counterparty_id),
        (v_op.organization_id, v_entry_id, 2, v_ar_coa, ''Cobro clientes'', 0, v_op.amount, v_op.counterparty_id);

    elsif v_op.operation_type = ''TRANSFER'' then
      select ta.accounting_account_id into v_src_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = ''OUTFLOW'';
      select ta.accounting_account_id into v_dst_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = ''INFLOW'';
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit
      ) values
        (v_op.organization_id, v_entry_id, 1, v_dst_coa, ''Transferencia destino'', v_op.amount, 0),
        (v_op.organization_id, v_entry_id, 2, v_src_coa, ''Transferencia origen'', 0, v_op.amount);

    elsif v_op.operation_type = ''OPENING_BALANCE'' then
      v_eq_coa := public.resolve_opening_equity_account(v_op.organization_id);
      select ta.accounting_account_id, l.direction into v_src_coa, v_desc
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id;
      if v_desc = ''INFLOW'' then
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_src_coa, ''Saldo inicial tesorería'', v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_eq_coa, ''Contrapartida saldo inicial'', 0, v_op.amount);
      else
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_eq_coa, ''Contrapartida saldo inicial'', v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_src_coa, ''Saldo inicial tesorería'', 0, v_op.amount);
      end if;

    elsif v_op.operation_type = ''ADJUSTMENT'' then
      v_adj_coa := public.resolve_adjustment_offset_account(v_op.organization_id);
      select ta.accounting_account_id, l.direction into v_src_coa, v_desc
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id;
      if v_desc = ''INFLOW'' then
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_src_coa, ''Ajuste tesorería'', v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_adj_coa, coalesce(v_op.reason,''Ajuste''), 0, v_op.amount);
      else
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_adj_coa, coalesce(v_op.reason,''Ajuste''), v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_src_coa, ''Ajuste tesorería'', 0, v_op.amount);
      end if;
    end if;

    perform public.post_journal_entry(v_entry_id);
  exception when others then
    delete from public.journal_entries where id = v_entry_id and status = ''DRAFT'';
    raise;
  end;

  perform set_config(''treasury.engine_write'', ''1'', true);

  -- Apply AP allocations
  if v_op.operation_type = ''PAYMENT'' then
    for v_alloc in
      select * from public.payment_allocations
      where treasury_operation_id = p_operation_id
      order by accounts_payable_item_id
    loop
      update public.accounts_payable_items
      set open_amount = open_amount - v_alloc.allocated_amount,
          status = case
            when open_amount - v_alloc.allocated_amount = 0 then ''PAID''::public.accounts_payable_status
            else ''PARTIALLY_PAID''::public.accounts_payable_status
          end,
          updated_at = timezone(''utc'', now())
      where id = v_alloc.accounts_payable_item_id
        and open_amount >= v_alloc.allocated_amount;
      if not found then
        raise exception ''AP concurrent update failed'';
      end if;
    end loop;
  end if;

  if v_op.operation_type = ''COLLECTION'' then
    for v_alloc in
      select * from public.collection_allocations
      where treasury_operation_id = p_operation_id
      order by accounts_receivable_item_id
    loop
      update public.accounts_receivable_items
      set open_amount = open_amount - v_alloc.allocated_amount,
          status = case
            when open_amount - v_alloc.allocated_amount = 0 then ''COLLECTED''::public.accounts_receivable_status
            else ''PARTIALLY_COLLECTED''::public.accounts_receivable_status
          end,
          updated_at = timezone(''utc'', now())
      where id = v_alloc.accounts_receivable_item_id
        and open_amount >= v_alloc.allocated_amount;
      if not found then
        raise exception ''AR concurrent update failed'';
      end if;
    end loop;
  end if;

  update public.treasury_operations
  set status = ''POSTED'',
      accounting_status = ''POSTED'',
      journal_entry_id = v_entry_id,
      posted_by = v_uid,
      posted_at = timezone(''utc'', now()),
      updated_at = timezone(''utc'', now())
  where id = p_operation_id;

  return p_operation_id;
end;
$$"}', 'phase7_post_treasury'),
	('20260901150000', '{"-- Phase 9: RLS, grants, feature enable Demo QA, revoke internal helpers

alter table public.pos_settings enable row level security","alter table public.pos_terminals enable row level security","alter table public.pos_sessions enable row level security","alter table public.pos_sales enable row level security","alter table public.pos_tenders enable row level security","alter table public.pos_terminal_tender_accounts enable row level security","-- SELECT
drop policy if exists pos_settings_select on public.pos_settings","create policy pos_settings_select on public.pos_settings for select to authenticated
  using (public.is_org_member(organization_id))","drop policy if exists pos_terminals_select on public.pos_terminals","create policy pos_terminals_select on public.pos_terminals for select to authenticated
  using (public.is_org_member(organization_id))","drop policy if exists pos_sessions_select on public.pos_sessions","create policy pos_sessions_select on public.pos_sessions for select to authenticated
  using (public.is_org_member(organization_id))","drop policy if exists pos_sales_select on public.pos_sales","create policy pos_sales_select on public.pos_sales for select to authenticated
  using (public.is_org_member(organization_id))","drop policy if exists pos_tenders_select on public.pos_tenders","create policy pos_tenders_select on public.pos_tenders for select to authenticated
  using (public.is_org_member(organization_id))","drop policy if exists pos_tta_select on public.pos_terminal_tender_accounts","create policy pos_tta_select on public.pos_terminal_tender_accounts for select to authenticated
  using (public.is_org_member(organization_id))","-- Config writes (settings / terminals / tender accounts)
drop policy if exists pos_settings_insert on public.pos_settings","create policy pos_settings_insert on public.pos_settings for insert to authenticated
  with check (public.has_org_role(organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]))","drop policy if exists pos_settings_update on public.pos_settings","create policy pos_settings_update on public.pos_settings for update to authenticated
  using (public.has_org_role(organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]))
  with check (public.has_org_role(organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]))","drop policy if exists pos_terminals_insert on public.pos_terminals","create policy pos_terminals_insert on public.pos_terminals for insert to authenticated
  with check (public.has_org_role(organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]))","drop policy if exists pos_terminals_update on public.pos_terminals","create policy pos_terminals_update on public.pos_terminals for update to authenticated
  using (public.has_org_role(organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]))
  with check (public.has_org_role(organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]))","drop policy if exists pos_tta_insert on public.pos_terminal_tender_accounts","create policy pos_tta_insert on public.pos_terminal_tender_accounts for insert to authenticated
  with check (public.has_org_role(organization_id, array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[]))","drop policy if exists pos_tta_update on public.pos_terminal_tender_accounts","create policy pos_tta_update on public.pos_terminal_tender_accounts for update to authenticated
  using (public.has_org_role(organization_id, array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[]))
  with check (public.has_org_role(organization_id, array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[]))","drop policy if exists pos_tta_delete on public.pos_terminal_tender_accounts","create policy pos_tta_delete on public.pos_terminal_tender_accounts for delete to authenticated
  using (public.has_org_role(organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]))","-- Cart lines tenders: insert/update/delete DRAFT via client before checkout
drop policy if exists pos_tenders_insert on public.pos_tenders","create policy pos_tenders_insert on public.pos_tenders for insert to authenticated
  with check (
    public.has_org_role(organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[])
    and status = ''DRAFT''
    and treasury_operation_id is null
  )","drop policy if exists pos_tenders_update on public.pos_tenders","create policy pos_tenders_update on public.pos_tenders for update to authenticated
  using (
    public.has_org_role(organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[])
    and status = ''DRAFT''
  )
  with check (
    public.has_org_role(organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[])
    and status = ''DRAFT''
    and treasury_operation_id is null
  )","drop policy if exists pos_tenders_delete on public.pos_tenders","create policy pos_tenders_delete on public.pos_tenders for delete to authenticated
  using (
    public.has_org_role(organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[])
    and status = ''DRAFT''
  )","-- Sessions/sales: no direct client INSERT/UPDATE (RPCs only)
-- (SELECT already granted)

grant select on public.pos_settings to authenticated","grant select, insert, update on public.pos_terminals to authenticated","grant select on public.pos_sessions to authenticated","grant select on public.pos_sales to authenticated","grant select, insert, update, delete on public.pos_tenders to authenticated","grant select, insert, update, delete on public.pos_terminal_tender_accounts to authenticated","grant select, insert, update on public.pos_settings to authenticated","revoke all on public.pos_settings from anon","revoke all on public.pos_terminals from anon","revoke all on public.pos_sessions from anon","revoke all on public.pos_sales from anon","revoke all on public.pos_tenders from anon","revoke all on public.pos_terminal_tender_accounts from anon","-- Internal helpers: no client EXECUTE
revoke all on function public.pos_assert_feature(uuid) from public, anon, authenticated","revoke all on function public.pos_assert_feature_code(uuid, text) from public, anon, authenticated","revoke all on function public.pos_validate_walk_in_customer(uuid, uuid) from public, anon, authenticated","revoke all on function public.pos_validate_tender_account(uuid, uuid, public.pos_tender_method, uuid)
  from public, anon, authenticated","-- Enable pos (+ typical deps) for Demo QA orgs
insert into public.organization_features (organization_id, feature_id, status, enabled_at)
select o.id, fc.id, ''enabled'', timezone(''utc'', now())
from public.organizations o
cross join public.feature_catalog fc
where fc.code in (''pos'', ''sales'', ''cash'', ''banks'', ''inventory'', ''fiscal_invoicing'', ''accounting'')
  and (
    o.legal_name ilike ''%demo%''
    or o.commercial_name ilike ''%demo%''
    or o.legal_name ilike ''%qa%''
  )
on conflict (organization_id, feature_id) do update
set status = ''enabled'',
    enabled_at = coalesce(public.organization_features.enabled_at, excluded.enabled_at)"}', 'phase9_pos_security'),
	('20260701150000', '{"-- Phase 7 — reverse_treasury_operation + grants for posting RPCs

create or replace function public.reverse_treasury_operation(
  p_operation_id uuid,
  p_reversal_date date default current_date,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_op public.treasury_operations%rowtype;
  v_rev public.journal_entries%rowtype;
  v_alloc record;
begin
  if v_uid is null then raise exception ''authentication required''; end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception ''reversal reason is required'';
  end if;

  select * into v_op from public.treasury_operations where id = p_operation_id for update;
  if not found then raise exception ''treasury operation not found''; end if;

  perform public.treasury_assert_feature(v_op.organization_id, array[''cash'',''banks'']);

  if v_op.operation_type = ''ADJUSTMENT'' then
    if not public.has_org_role(
      v_op.organization_id, array[''owner'',''accountant'']::public.member_role[]
    ) then
      raise exception ''only owner/accountant may reverse adjustments'';
    end if;
  else
    if not public.has_org_role(
      v_op.organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
    ) then
      raise exception ''insufficient role to reverse treasury operation'';
    end if;
  end if;

  if v_op.status = ''REVERSED'' then
    return p_operation_id;
  end if;
  if v_op.status is distinct from ''POSTED'' or v_op.journal_entry_id is null then
    raise exception ''only POSTED operations with journal can be reversed'';
  end if;

  -- Lock open items before restore
  if v_op.operation_type = ''PAYMENT'' then
    perform 1 from public.accounts_payable_items ap
    where ap.id in (
      select accounts_payable_item_id from public.payment_allocations
      where treasury_operation_id = p_operation_id
    )
    order by ap.id for update;
  elsif v_op.operation_type = ''COLLECTION'' then
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

  perform set_config(''treasury.engine_write'', ''1'', true);

  if v_op.operation_type = ''PAYMENT'' then
    for v_alloc in
      select * from public.payment_allocations
      where treasury_operation_id = p_operation_id
      order by accounts_payable_item_id
    loop
      update public.accounts_payable_items
      set open_amount = open_amount + v_alloc.allocated_amount,
          status = case
            when open_amount + v_alloc.allocated_amount >= original_amount
              then ''OPEN''::public.accounts_payable_status
            else ''PARTIALLY_PAID''::public.accounts_payable_status
          end,
          updated_at = timezone(''utc'', now())
      where id = v_alloc.accounts_payable_item_id;
    end loop;
  elsif v_op.operation_type = ''COLLECTION'' then
    for v_alloc in
      select * from public.collection_allocations
      where treasury_operation_id = p_operation_id
      order by accounts_receivable_item_id
    loop
      update public.accounts_receivable_items
      set open_amount = open_amount + v_alloc.allocated_amount,
          status = case
            when open_amount + v_alloc.allocated_amount >= original_amount
              then ''OPEN''::public.accounts_receivable_status
            else ''PARTIALLY_COLLECTED''::public.accounts_receivable_status
          end,
          updated_at = timezone(''utc'', now())
      where id = v_alloc.accounts_receivable_item_id;
    end loop;
  end if;

  -- Domain status REVERSED; original journal stays REVERSED in Phase 2 with reversal pair
  update public.treasury_operations
  set status = ''REVERSED'',
      reverse_journal_entry_id = v_rev.id,
      reversed_by = v_uid,
      reversed_at = timezone(''utc'', now()),
      reason = coalesce(reason, trim(p_reason)),
      updated_at = timezone(''utc'', now())
  where id = p_operation_id;

  return p_operation_id;
end;
$$","revoke all on function public.treasury_assert_feature(uuid, text[]) from public, anon","revoke all on function public.next_treasury_operation_number(uuid, public.treasury_operation_type) from public, anon","revoke all on function public.post_treasury_operation(uuid) from public, anon","revoke all on function public.reverse_treasury_operation(uuid, date, text) from public, anon","revoke all on function public.post_open_item_compensation(public.open_item_domain, uuid, uuid, numeric, text) from public, anon","revoke all on function public.resolve_ap_account(uuid) from public, anon","revoke all on function public.resolve_ar_account(uuid) from public, anon","revoke all on function public.resolve_opening_equity_account(uuid) from public, anon","revoke all on function public.resolve_adjustment_offset_account(uuid) from public, anon","grant execute on function public.next_treasury_operation_number(uuid, public.treasury_operation_type) to authenticated","grant execute on function public.post_treasury_operation(uuid) to authenticated","grant execute on function public.reverse_treasury_operation(uuid, date, text) to authenticated","grant execute on function public.post_open_item_compensation(public.open_item_domain, uuid, uuid, numeric, text) to authenticated","grant execute on function public.resolve_ap_account(uuid) to authenticated","grant execute on function public.resolve_ar_account(uuid) to authenticated","grant execute on function public.resolve_opening_equity_account(uuid) to authenticated","grant execute on function public.resolve_adjustment_offset_account(uuid) to authenticated"}', 'phase7_reverse_treasury'),
	('20260701160000', '{"-- Phase 7 — Bank statements + 1:1 reconciliation (evidence only, no auto-post)

do $$ begin
  create type public.bank_statement_match_status as enum (
    ''UNMATCHED'', ''MATCHED'', ''IGNORED''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.bank_import_status as enum (''IMPORTED'', ''VOID'');
exception when duplicate_object then null;
end $$","create table public.bank_statement_imports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  treasury_account_id uuid not null,
  source_filename text,
  source_hash text not null,
  row_count int not null default 0 check (row_count >= 0),
  status public.bank_import_status not null default ''IMPORTED'',
  imported_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  unique (organization_id, treasury_account_id, source_hash),
  constraint bank_statement_imports_org_id_unique unique (organization_id, id),
  constraint bank_statement_imports_org_account_fk
    foreign key (organization_id, treasury_account_id)
    references public.treasury_accounts (organization_id, id)
    on delete restrict
)","create index bank_statement_imports_org_account_date_idx
  on public.bank_statement_imports (organization_id, treasury_account_id, created_at desc)","create index bank_statement_imports_imported_by_idx
  on public.bank_statement_imports (imported_by)
  where imported_by is not null","create table public.bank_statement_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  import_id uuid not null,
  treasury_account_id uuid not null,
  value_date date not null,
  description text,
  reference text,
  debit numeric(19, 4) not null default 0 check (debit >= 0),
  credit numeric(19, 4) not null default 0 check (credit >= 0),
  line_hash text not null,
  match_status public.bank_statement_match_status not null default ''UNMATCHED'',
  ignore_reason text,
  created_at timestamptz not null default timezone(''utc'', now()),
  constraint bank_statement_lines_one_side check (
    (debit > 0 and credit = 0) or (credit > 0 and debit = 0)
  ),
  unique (organization_id, treasury_account_id, line_hash),
  constraint bank_statement_lines_org_id_unique unique (organization_id, id),
  constraint bank_statement_lines_org_import_fk
    foreign key (organization_id, import_id)
    references public.bank_statement_imports (organization_id, id)
    on delete cascade,
  constraint bank_statement_lines_org_account_fk
    foreign key (organization_id, treasury_account_id)
    references public.treasury_accounts (organization_id, id)
    on delete restrict,
  constraint bank_statement_lines_ignore_reason check (
    match_status <> ''IGNORED'' or (ignore_reason is not null and char_length(trim(ignore_reason)) >= 3)
  )
)","create index bank_statement_lines_import_idx
  on public.bank_statement_lines (import_id)","create index bank_statement_lines_org_account_date_idx
  on public.bank_statement_lines (organization_id, treasury_account_id, value_date)","create index bank_statement_lines_match_status_idx
  on public.bank_statement_lines (organization_id, treasury_account_id, match_status)","create table public.bank_reconciliation_matches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  statement_line_id uuid not null,
  treasury_operation_id uuid not null,
  treasury_operation_leg_id uuid,
  amount numeric(19, 4) not null check (amount > 0),
  created_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  -- MVP 1:1
  unique (statement_line_id),
  unique (treasury_operation_id),
  constraint bank_recon_matches_org_line_fk
    foreign key (organization_id, statement_line_id)
    references public.bank_statement_lines (organization_id, id)
    on delete cascade,
  constraint bank_recon_matches_org_op_fk
    foreign key (organization_id, treasury_operation_id)
    references public.treasury_operations (organization_id, id)
    on delete restrict,
  constraint bank_recon_matches_org_leg_fk
    foreign key (organization_id, treasury_operation_leg_id)
    references public.treasury_operation_legs (organization_id, id)
    on delete restrict
)","create index bank_recon_matches_op_idx
  on public.bank_reconciliation_matches (treasury_operation_id)","create index bank_recon_matches_leg_idx
  on public.bank_reconciliation_matches (treasury_operation_leg_id)
  where treasury_operation_leg_id is not null","create index bank_recon_matches_created_by_idx
  on public.bank_reconciliation_matches (created_by)
  where created_by is not null","comment on table public.bank_statement_lines is
  ''External bank evidence only — never auto-posts accounting.''","comment on table public.bank_reconciliation_matches is
  ''1:1 match metadata; does not create/alter journals or amounts.''","-- Match / unmatch / ignore RPCs (no journal side effects)
create or replace function public.match_bank_statement_line(
  p_statement_line_id uuid,
  p_treasury_operation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_line public.bank_statement_lines%rowtype;
  v_op public.treasury_operations%rowtype;
  v_amount numeric(19,4);
  v_id uuid;
begin
  if v_uid is null then raise exception ''authentication required''; end if;
  select * into v_line from public.bank_statement_lines where id = p_statement_line_id for update;
  if not found then raise exception ''statement line not found''; end if;
  if not public.has_org_role(
    v_line.organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role to reconcile'';
  end if;
  perform public.treasury_assert_feature(v_line.organization_id, array[''banks'']);

  if v_line.match_status is distinct from ''UNMATCHED'' then
    raise exception ''statement line is not unmatched'';
  end if;

  select * into v_op from public.treasury_operations where id = p_treasury_operation_id for update;
  if not found then raise exception ''treasury operation not found''; end if;
  if v_op.organization_id is distinct from v_line.organization_id then
    raise exception ''cross-tenant match denied'';
  end if;
  if v_op.status is distinct from ''POSTED'' then
    raise exception ''only POSTED operations can be matched'';
  end if;

  v_amount := case when v_line.debit > 0 then v_line.debit else v_line.credit end;
  if v_amount <> v_op.amount then
    raise exception ''MVP 1:1 match requires equal amounts'';
  end if;

  if exists (
    select 1 from public.bank_reconciliation_matches where treasury_operation_id = p_treasury_operation_id
  ) then
    raise exception ''operation already matched'';
  end if;

  insert into public.bank_reconciliation_matches (
    organization_id, statement_line_id, treasury_operation_id, amount, created_by
  ) values (
    v_line.organization_id, p_statement_line_id, p_treasury_operation_id, v_amount, v_uid
  ) returning id into v_id;

  update public.bank_statement_lines
  set match_status = ''MATCHED''
  where id = p_statement_line_id;

  return v_id;
end;
$$","create or replace function public.unmatch_bank_statement_line(p_statement_line_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_line public.bank_statement_lines%rowtype;
begin
  if auth.uid() is null then raise exception ''authentication required''; end if;
  select * into v_line from public.bank_statement_lines where id = p_statement_line_id for update;
  if not found then raise exception ''statement line not found''; end if;
  if not public.has_org_role(
    v_line.organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role'';
  end if;
  delete from public.bank_reconciliation_matches where statement_line_id = p_statement_line_id;
  update public.bank_statement_lines
  set match_status = ''UNMATCHED'', ignore_reason = null
  where id = p_statement_line_id;
  return p_statement_line_id;
end;
$$","create or replace function public.ignore_bank_statement_line(
  p_statement_line_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_line public.bank_statement_lines%rowtype;
begin
  if auth.uid() is null then raise exception ''authentication required''; end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception ''ignore reason required'';
  end if;
  select * into v_line from public.bank_statement_lines where id = p_statement_line_id for update;
  if not found then raise exception ''statement line not found''; end if;
  if not public.has_org_role(
    v_line.organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role'';
  end if;
  if v_line.match_status = ''MATCHED'' then
    raise exception ''unmatch before ignore'';
  end if;
  update public.bank_statement_lines
  set match_status = ''IGNORED'', ignore_reason = trim(p_reason)
  where id = p_statement_line_id;
  return p_statement_line_id;
end;
$$","revoke all on function public.match_bank_statement_line(uuid, uuid) from public, anon","revoke all on function public.unmatch_bank_statement_line(uuid) from public, anon","revoke all on function public.ignore_bank_statement_line(uuid, text) from public, anon","grant execute on function public.match_bank_statement_line(uuid, uuid) to authenticated","grant execute on function public.unmatch_bank_statement_line(uuid) to authenticated","grant execute on function public.ignore_bank_statement_line(uuid, text) to authenticated"}', 'phase7_bank_reconciliation'),
	('20260701170000', '{"-- Phase 7 — RLS, grants, feature enable (Demo QA staging only)

alter table public.treasury_operation_sequences enable row level security","alter table public.treasury_accounts enable row level security","alter table public.treasury_operations enable row level security","alter table public.treasury_operation_legs enable row level security","alter table public.accounts_receivable_items enable row level security","alter table public.payment_allocations enable row level security","alter table public.collection_allocations enable row level security","alter table public.open_item_compensations enable row level security","alter table public.treasury_accounting_mappings enable row level security","alter table public.bank_statement_imports enable row level security","alter table public.bank_statement_lines enable row level security","alter table public.bank_reconciliation_matches enable row level security","-- sequences
create policy treasury_operation_sequences_select
  on public.treasury_operation_sequences for select to authenticated
  using ((select public.is_org_member(organization_id)))","-- treasury_accounts
create policy treasury_accounts_select
  on public.treasury_accounts for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy treasury_accounts_insert
  on public.treasury_accounts for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
  )))","create policy treasury_accounts_update
  on public.treasury_accounts for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
  )))","-- treasury_operations
create policy treasury_operations_select
  on public.treasury_operations for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy treasury_operations_insert
  on public.treasury_operations for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy treasury_operations_update
  on public.treasury_operations for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy treasury_operations_delete
  on public.treasury_operations for delete to authenticated
  using (
    status = ''DRAFT''
    and (select public.has_org_role(
      organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]
    ))
  )","-- legs
create policy treasury_legs_select
  on public.treasury_operation_legs for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy treasury_legs_insert
  on public.treasury_operation_legs for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy treasury_legs_update
  on public.treasury_operation_legs for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy treasury_legs_delete
  on public.treasury_operation_legs for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","-- AR: select for members; insert only via engine ensure (still allow accountant insert of drafts? ensure is DEFINER)
-- Allow no client insert of AR monetary rows except engine — only SELECT grant for AR items
create policy accounts_receivable_items_select
  on public.accounts_receivable_items for select to authenticated
  using ((select public.is_org_member(organization_id)))","-- allocations draft writable
create policy payment_allocations_select
  on public.payment_allocations for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy payment_allocations_write
  on public.payment_allocations for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy payment_allocations_update
  on public.payment_allocations for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy payment_allocations_delete
  on public.payment_allocations for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy collection_allocations_select
  on public.collection_allocations for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy collection_allocations_insert
  on public.collection_allocations for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy collection_allocations_update
  on public.collection_allocations for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy collection_allocations_delete
  on public.collection_allocations for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  )))","create policy open_item_compensations_select
  on public.open_item_compensations for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy treasury_accounting_mappings_select
  on public.treasury_accounting_mappings for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy treasury_accounting_mappings_insert
  on public.treasury_accounting_mappings for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","create policy treasury_accounting_mappings_update
  on public.treasury_accounting_mappings for update to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","create policy treasury_accounting_mappings_delete
  on public.treasury_accounting_mappings for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array[''owner'',''admin'']::public.member_role[]
  )))","-- bank
create policy bank_statement_imports_select
  on public.bank_statement_imports for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy bank_statement_imports_insert
  on public.bank_statement_imports for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","create policy bank_statement_lines_select
  on public.bank_statement_lines for select to authenticated
  using ((select public.is_org_member(organization_id)))","create policy bank_statement_lines_insert
  on public.bank_statement_lines for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
  )))","create policy bank_recon_matches_select
  on public.bank_reconciliation_matches for select to authenticated
  using ((select public.is_org_member(organization_id)))","-- Grants
grant select on public.treasury_operation_sequences to authenticated","grant select, insert, update on public.treasury_accounts to authenticated","grant select, insert, update, delete on public.treasury_operations to authenticated","grant select, insert, update, delete on public.treasury_operation_legs to authenticated","grant select on public.accounts_receivable_items to authenticated","grant select, insert, update, delete on public.payment_allocations to authenticated","grant select, insert, update, delete on public.collection_allocations to authenticated","grant select on public.open_item_compensations to authenticated","grant select, insert, update, delete on public.treasury_accounting_mappings to authenticated","grant select, insert on public.bank_statement_imports to authenticated","grant select, insert on public.bank_statement_lines to authenticated","grant select on public.bank_reconciliation_matches to authenticated","revoke all on public.treasury_operation_sequences from anon","revoke all on public.treasury_accounts from anon","revoke all on public.treasury_operations from anon","revoke all on public.treasury_operation_legs from anon","revoke all on public.accounts_receivable_items from anon","revoke all on public.payment_allocations from anon","revoke all on public.collection_allocations from anon","revoke all on public.open_item_compensations from anon","revoke all on public.treasury_accounting_mappings from anon","revoke all on public.bank_statement_imports from anon","revoke all on public.bank_statement_lines from anon","revoke all on public.bank_reconciliation_matches from anon","-- Enable cash + banks for Demo QA orgs only
insert into public.organization_features (organization_id, feature_id, status, enabled_at)
select distinct c.organization_id, fc.id, ''enabled''::public.feature_status, timezone(''utc'', now())
from public.counterparties c
inner join public.feature_catalog fc on fc.code in (''cash'', ''banks'')
where c.legal_name ilike ''%Demo%''
on conflict (organization_id, feature_id) do update
  set status = excluded.status,
      enabled_at = coalesce(public.organization_features.enabled_at, excluded.enabled_at)"}', 'phase7_security'),
	('20260701180000', '{"-- applied via db query; see repo migration file"}', 'phase7_hardening'),
	('20260701190000', '{"-- applied via db query; see repo migration file"}', 'phase7_final_advisor_fk_indexes'),
	('20260801100000', '{q}', 'phase8_products'),
	('20260801110000', '{q}', 'phase8_warehouses_inventory_core'),
	('20260801120000', '{q}', 'phase8_stock_cost_reservations'),
	('20260801130000', '{q}', 'phase8_accounting_helpers'),
	('20260801140000', '{q}', 'phase8_reservations_rpc'),
	('20260801150000', '{q}', 'phase8_post_inventory'),
	('20260801160000', '{q}', 'phase8_reverse_inventory'),
	('20260801170000', '{q}', 'phase8_commercial_integration'),
	('20260801180000', '{q}', 'phase8_security'),
	('20260801190000', '{q}', 'phase8_advisor_hardening'),
	('20260801200000', '{q}', 'phase8_final_security_rls_hardening'),
	('20261001100000', '{}', 'phase10_tax_reference_core'),
	('20261001110000', '{}', 'phase10_tax_registrations_rules'),
	('20261001120000', '{}', 'phase10_tax_periods'),
	('20261001130000', '{}', 'phase10_vat_classification_wp'),
	('20261001140000', '{}', 'phase10_tax_determinations'),
	('20261001150000', '{}', 'phase10_iibb'),
	('20261001160000', '{}', 'phase10_filing_obligations'),
	('20261001170000', '{}', 'phase10_tax_helpers'),
	('20261001180000', '{}', 'phase10_calculate_vat'),
	('20261001190000', '{}', 'phase10_period_filing_rpcs'),
	('20261001200000', '{}', 'phase10_security'),
	('20261001210000', NULL, NULL),
	('20261001220000', NULL, NULL),
	('20260901190000', NULL, NULL),
	('20261001230000', NULL, NULL),
	('20261001240000', NULL, NULL),
	('20261001250000', NULL, NULL),
	('20261001260000', NULL, NULL),
	('20260901100000', '{"-- Phase 9: CLEARING treasury account type + CoA system_role helper
-- STAGING ONLY — NEW migration; do not edit Phase 1–8 files.

do $$ begin
  alter type public.treasury_account_type add value if not exists ''CLEARING'';
exception when duplicate_object then null;
end $$","-- Allow CLEARING accounts without bank metadata (reuse bank_meta_check via replace)
alter table public.treasury_accounts
  drop constraint if exists treasury_accounts_bank_meta_check","alter table public.treasury_accounts
  add constraint treasury_accounts_bank_meta_check check (
    account_type = ''BANK''
    or (bank_name is null and account_mask is null and cbu_cvu_alias is null)
  )","comment on type public.treasury_account_type is
  ''CASH | BANK | CLEARING (Phase 9 POS card/QR processor receivables).''","-- Additive CoA: payment processor clearing asset
create or replace function public.ensure_treasury_clearing_coa(p_org_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_parent uuid;
  v_id uuid;
begin
  if v_uid is null then raise exception ''authentication required''; end if;
  if not public.has_org_role(p_org_id, array[''owner'',''admin'',''accountant'']::public.member_role[]) then
    raise exception ''insufficient role'';
  end if;

  select id into v_id
  from public.accounts
  where organization_id = p_org_id
    and system_role = ''clearing''
    and is_postable
  limit 1;

  if v_id is not null then
    return v_id;
  end if;

  select id into v_parent
  from public.accounts
  where organization_id = p_org_id and code = ''1.1''
  limit 1;

  if v_parent is null then
    raise exception ''missing CoA parent 1.1 for clearing account'';
  end if;

  if not exists (
    select 1 from public.accounts where organization_id = p_org_id and code = ''1.1.06''
  ) then
    insert into public.accounts (
      organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role
    ) values (
      p_org_id, v_parent, ''1.1.06'', ''Medios electrónicos a cobrar / clearing'',
      ''ASSET'', ''DEBIT'', true, ''clearing''
    )
    returning id into v_id;
  else
    update public.accounts
    set system_role = ''clearing'', is_postable = true, updated_at = timezone(''utc'', now())
    where organization_id = p_org_id and code = ''1.1.06''
    returning id into v_id;
  end if;

  return v_id;
end;
$$","revoke all on function public.ensure_treasury_clearing_coa(uuid) from public, anon","grant execute on function public.ensure_treasury_clearing_coa(uuid) to authenticated","comment on function public.ensure_treasury_clearing_coa(uuid) is
  ''Phase 9: ensure postable accounts.system_role=clearing (1.1.06).''"}', 'phase9_clearing'),
	('20260901110000', '{"-- Phase 9: POS core enums + tables
-- Orchestration only — commercial truth remains sales_documents / lines.

do $$ begin
  create type public.pos_session_status as enum (''OPEN'', ''CLOSED'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.pos_sale_status as enum (
    ''DRAFT'',
    ''READY_TO_CHECKOUT'',
    ''STOCK_RESERVED'',
    ''WAITING_FISCAL'',
    ''FISCAL_AUTHORIZED'',
    ''FINALIZING'',
    ''COMPLETED'',
    ''CANCELLED'',
    ''RECONCILIATION_REQUIRED''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.pos_tender_method as enum (
    ''CASH'', ''BANK_TRANSFER'', ''CARD'', ''QR''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.pos_tender_status as enum (
    ''DRAFT'', ''POSTED'', ''REVERSED''
  );
exception when duplicate_object then null;
end $$","-- ---------------------------------------------------------------------------
-- pos_settings (1:1 org)
-- ---------------------------------------------------------------------------

create table if not exists public.pos_settings (
  organization_id uuid primary key references public.organizations (id) on delete cascade,
  default_walk_in_customer_id uuid not null,
  default_document_type_internal_code text,
  default_condicion_iva_receptor_id int,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint pos_settings_walk_in_fk
    foreign key (organization_id, default_walk_in_customer_id)
    references public.counterparties (organization_id, id)
    on delete restrict
)","create index if not exists pos_settings_walk_in_idx
  on public.pos_settings (default_walk_in_customer_id)","create trigger pos_settings_set_updated_at
before update on public.pos_settings
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- pos_terminals
-- ---------------------------------------------------------------------------

create table if not exists public.pos_terminals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid not null,
  code text not null,
  name text not null,
  warehouse_id uuid not null,
  default_customer_id uuid,
  fiscal_point_of_sale_id uuid,
  active boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint pos_terminals_org_id_unique unique (organization_id, id),
  constraint pos_terminals_code_unique unique (organization_id, code),
  constraint pos_terminals_code_check check (length(btrim(code)) >= 1 and length(btrim(code)) <= 32),
  constraint pos_terminals_name_check check (length(btrim(name)) >= 1),
  constraint pos_terminals_org_branch_fk
    foreign key (organization_id, branch_id)
    references public.branches (organization_id, id) on delete restrict,
  constraint pos_terminals_org_wh_fk
    foreign key (organization_id, warehouse_id)
    references public.warehouses (organization_id, id) on delete restrict,
  constraint pos_terminals_org_customer_fk
    foreign key (organization_id, default_customer_id)
    references public.counterparties (organization_id, id) on delete restrict,
  constraint pos_terminals_fiscal_pos_fk
    foreign key (fiscal_point_of_sale_id)
    references public.fiscal_points_of_sale (id) on delete restrict
)","create index if not exists pos_terminals_org_branch_idx
  on public.pos_terminals (organization_id, branch_id)","create index if not exists pos_terminals_warehouse_idx
  on public.pos_terminals (organization_id, warehouse_id)","create index if not exists pos_terminals_fiscal_pos_idx
  on public.pos_terminals (fiscal_point_of_sale_id)
  where fiscal_point_of_sale_id is not null","create index if not exists pos_terminals_created_by_idx
  on public.pos_terminals (created_by) where created_by is not null","create trigger pos_terminals_set_updated_at
before update on public.pos_terminals
for each row execute function public.set_updated_at()","comment on column public.pos_terminals.code is
  ''Internal retail terminal code (e.g. POS-01). NOT an ARCA punto de venta.''","-- ---------------------------------------------------------------------------
-- pos_sessions
-- ---------------------------------------------------------------------------

create table if not exists public.pos_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  terminal_id uuid not null,
  cashier_id uuid not null references auth.users (id),
  status public.pos_session_status not null default ''OPEN'',
  opened_at timestamptz not null default timezone(''utc'', now()),
  closed_at timestamptz,
  opening_expected_cash numeric(19, 4) not null default 0,
  opening_counted_cash numeric(19, 4),
  closing_expected_cash numeric(19, 4),
  closing_counted_cash numeric(19, 4),
  closing_difference numeric(19, 4),
  idempotency_key text not null,
  created_at timestamptz not null default timezone(''utc'', now()),
  constraint pos_sessions_org_id_unique unique (organization_id, id),
  constraint pos_sessions_idempotency_unique unique (organization_id, idempotency_key),
  constraint pos_sessions_org_terminal_fk
    foreign key (organization_id, terminal_id)
    references public.pos_terminals (organization_id, id) on delete restrict,
  constraint pos_sessions_closed_check check (
    (status = ''OPEN'' and closed_at is null)
    or (status = ''CLOSED'' and closed_at is not null)
  )
)","create unique index if not exists pos_sessions_one_open_per_terminal
  on public.pos_sessions (terminal_id)
  where status = ''OPEN''","create index if not exists pos_sessions_org_cashier_idx
  on public.pos_sessions (organization_id, cashier_id, opened_at desc)","create index if not exists pos_sessions_terminal_idx
  on public.pos_sessions (terminal_id, status)","-- ---------------------------------------------------------------------------
-- pos_sales
-- ---------------------------------------------------------------------------

create table if not exists public.pos_sales (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  terminal_id uuid not null,
  session_id uuid not null,
  sales_document_id uuid not null,
  fiscal_document_id uuid,
  status public.pos_sale_status not null default ''DRAFT'',
  idempotency_key text not null,
  cash_received numeric(19, 4),
  change_given numeric(19, 4),
  checkout_started_at timestamptz,
  completed_at timestamptz,
  inventory_operation_id uuid,
  created_by uuid references auth.users (id),
  completed_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint pos_sales_org_id_unique unique (organization_id, id),
  constraint pos_sales_sales_doc_unique unique (sales_document_id),
  constraint pos_sales_idempotency_unique unique (organization_id, idempotency_key),
  constraint pos_sales_inventory_op_unique unique (inventory_operation_id),
  constraint pos_sales_org_terminal_fk
    foreign key (organization_id, terminal_id)
    references public.pos_terminals (organization_id, id) on delete restrict,
  constraint pos_sales_org_session_fk
    foreign key (organization_id, session_id)
    references public.pos_sessions (organization_id, id) on delete restrict,
  constraint pos_sales_sales_doc_fk
    foreign key (sales_document_id)
    references public.sales_documents (id) on delete restrict,
  constraint pos_sales_fiscal_doc_fk
    foreign key (fiscal_document_id)
    references public.fiscal_documents (id) on delete restrict,
  constraint pos_sales_inventory_op_fk
    foreign key (inventory_operation_id)
    references public.inventory_operations (id) on delete restrict,
  constraint pos_sales_change_check check (
    (cash_received is null and change_given is null)
    or (cash_received is not null and change_given is not null and cash_received >= 0 and change_given >= 0)
  )
)","create index if not exists pos_sales_session_status_idx
  on public.pos_sales (session_id, status)","create index if not exists pos_sales_org_status_idx
  on public.pos_sales (organization_id, status, created_at desc)","create index if not exists pos_sales_fiscal_idx
  on public.pos_sales (fiscal_document_id) where fiscal_document_id is not null","create index if not exists pos_sales_terminal_idx
  on public.pos_sales (terminal_id, created_at desc)","create trigger pos_sales_set_updated_at
before update on public.pos_sales
for each row execute function public.set_updated_at()","-- ---------------------------------------------------------------------------
-- pos_tenders
-- ---------------------------------------------------------------------------

create table if not exists public.pos_tenders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  pos_sale_id uuid not null,
  method public.pos_tender_method not null,
  treasury_account_id uuid not null,
  amount numeric(19, 4) not null check (amount > 0),
  cash_received numeric(19, 4),
  change_given numeric(19, 4),
  reference text,
  provider_label text,
  status public.pos_tender_status not null default ''DRAFT'',
  treasury_operation_id uuid,
  idempotency_key text not null,
  created_at timestamptz not null default timezone(''utc'', now()),
  constraint pos_tenders_org_id_unique unique (organization_id, id),
  constraint pos_tenders_idempotency_unique unique (organization_id, idempotency_key),
  constraint pos_tenders_treasury_op_unique unique (treasury_operation_id),
  constraint pos_tenders_org_sale_fk
    foreign key (organization_id, pos_sale_id)
    references public.pos_sales (organization_id, id) on delete cascade,
  constraint pos_tenders_org_account_fk
    foreign key (organization_id, treasury_account_id)
    references public.treasury_accounts (organization_id, id) on delete restrict,
  constraint pos_tenders_treasury_op_fk
    foreign key (treasury_operation_id)
    references public.treasury_operations (id) on delete restrict,
  constraint pos_tenders_cash_meta_check check (
    (
      method = ''CASH''
      and (
        cash_received is null
        or (
          cash_received >= amount
          and change_given is not null
          and change_given = cash_received - amount
        )
      )
    )
    or (
      method <> ''CASH''
      and cash_received is null
      and change_given is null
    )
  ),
  constraint pos_tenders_no_card_pan_check check (
    reference is null or length(reference) <= 128
  ),
  constraint pos_tenders_provider_check check (
    provider_label is null or length(provider_label) <= 64
  )
)","create index if not exists pos_tenders_sale_idx
  on public.pos_tenders (pos_sale_id)","create index if not exists pos_tenders_account_idx
  on public.pos_tenders (treasury_account_id)","-- ---------------------------------------------------------------------------
-- pos_terminal_tender_accounts
-- ---------------------------------------------------------------------------

create table if not exists public.pos_terminal_tender_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  terminal_id uuid not null,
  method public.pos_tender_method not null,
  treasury_account_id uuid not null,
  active boolean not null default true,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint pos_tta_org_id_unique unique (organization_id, id),
  constraint pos_tta_org_terminal_fk
    foreign key (organization_id, terminal_id)
    references public.pos_terminals (organization_id, id) on delete cascade,
  constraint pos_tta_org_account_fk
    foreign key (organization_id, treasury_account_id)
    references public.treasury_accounts (organization_id, id) on delete restrict
)","create unique index if not exists pos_tta_terminal_method_active
  on public.pos_terminal_tender_accounts (terminal_id, method)
  where active","-- One CASH drawer account → one terminal (deterministic session cash)
create unique index if not exists pos_tta_cash_account_one_terminal
  on public.pos_terminal_tender_accounts (treasury_account_id)
  where method = ''CASH'' and active","create index if not exists pos_tta_account_idx
  on public.pos_terminal_tender_accounts (treasury_account_id)","create trigger pos_tta_set_updated_at
before update on public.pos_terminal_tender_accounts
for each row execute function public.set_updated_at()"}', 'phase9_pos_core'),
	('20260901120000', '{"-- Phase 9: POS helpers, engine guards, tender validation

create or replace function public.pos_assert_feature(p_org_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''''
as $$
begin
  if not exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = ''pos''
      and ofeat.status = ''enabled''
  ) then
    raise exception ''feature pos is not enabled'';
  end if;

  if not exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = ''sales''
      and ofeat.status = ''enabled''
  ) then
    raise exception ''feature sales is required for POS'';
  end if;
end;
$$","create or replace function public.pos_assert_feature_code(p_org_id uuid, p_code text)
returns void
language plpgsql
stable
security definer
set search_path = ''''
as $$
begin
  if not exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = p_code
      and ofeat.status = ''enabled''
  ) then
    raise exception ''feature % is required'', p_code;
  end if;
end;
$$","create or replace function public.pos_expected_account_type(p_method public.pos_tender_method)
returns public.treasury_account_type
language sql
immutable
set search_path = ''''
as $$
  select case p_method
    when ''CASH'' then ''CASH''::public.treasury_account_type
    when ''BANK_TRANSFER'' then ''BANK''::public.treasury_account_type
    when ''CARD'' then ''CLEARING''::public.treasury_account_type
    when ''QR'' then ''CLEARING''::public.treasury_account_type
  end;
$$","create or replace function public.pos_validate_walk_in_customer(
  p_org_id uuid,
  p_customer_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''''
as $$
begin
  if not exists (
    select 1
    from public.counterparties c
    join public.counterparty_roles r
      on r.counterparty_id = c.id and r.organization_id = c.organization_id
    where c.organization_id = p_org_id
      and c.id = p_customer_id
      and c.is_active
      and r.role = ''CUSTOMER''
  ) then
    raise exception ''walk-in customer must be active CUSTOMER in same organization'';
  end if;
end;
$$","create or replace function public.pos_validate_tender_account(
  p_org_id uuid,
  p_terminal_id uuid,
  p_method public.pos_tender_method,
  p_treasury_account_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_ta public.treasury_accounts%rowtype;
  v_expected public.treasury_account_type;
begin
  v_expected := public.pos_expected_account_type(p_method);

  select * into v_ta
  from public.treasury_accounts
  where id = p_treasury_account_id
    and organization_id = p_org_id;

  if not found then
    raise exception ''treasury account not found'';
  end if;
  if not v_ta.is_active then
    raise exception ''treasury account is inactive'';
  end if;
  if v_ta.currency_code is distinct from ''ARS'' then
    raise exception ''POS tenders require ARS treasury accounts'';
  end if;
  if v_ta.account_type is distinct from v_expected then
    raise exception ''tender method % requires treasury_account_type % (got %)'',
      p_method, v_expected, v_ta.account_type;
  end if;

  if not exists (
    select 1 from public.pos_terminal_tender_accounts
    where organization_id = p_org_id
      and terminal_id = p_terminal_id
      and method = p_method
      and treasury_account_id = p_treasury_account_id
      and active
  ) then
    raise exception ''treasury account not mapped for terminal method %'', p_method;
  end if;
end;
$$","create or replace function public.prevent_pos_sale_engine_forgery()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if current_setting(''pos.engine_write'', true) = ''1'' then
    return new;
  end if;

  if tg_op = ''UPDATE'' then
    if new.status is distinct from old.status
      or new.fiscal_document_id is distinct from old.fiscal_document_id
      or new.inventory_operation_id is distinct from old.inventory_operation_id
      or new.completed_at is distinct from old.completed_at
      or new.completed_by is distinct from old.completed_by
      or new.checkout_started_at is distinct from old.checkout_started_at
      or new.sales_document_id is distinct from old.sales_document_id
      or new.session_id is distinct from old.session_id
      or new.terminal_id is distinct from old.terminal_id
    then
      raise exception ''pos_sales engine fields are trusted-only'';
    end if;
  end if;
  return new;
end;
$$","drop trigger if exists pos_sales_engine_guard on public.pos_sales","create trigger pos_sales_engine_guard
before update on public.pos_sales
for each row execute function public.prevent_pos_sale_engine_forgery()","create or replace function public.prevent_pos_tender_engine_forgery()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if current_setting(''pos.engine_write'', true) = ''1'' then
    return new;
  end if;

  if tg_op = ''UPDATE'' then
    if old.status = ''POSTED'' or new.status = ''POSTED'' or new.treasury_operation_id is not null then
      if current_setting(''pos.engine_write'', true) is distinct from ''1'' then
        raise exception ''pos_tenders engine fields are trusted-only'';
      end if;
    end if;
    -- DRAFT tender edits allowed until FINALIZING/COMPLETED/CANCELLED
    if exists (
      select 1 from public.pos_sales s
      where s.id = old.pos_sale_id
        and s.status in (''FINALIZING'', ''COMPLETED'', ''CANCELLED'', ''RECONCILIATION_REQUIRED'')
    ) then
      raise exception ''cannot mutate tenders in status %'', (
        select status from public.pos_sales where id = old.pos_sale_id
      );
    end if;
  end if;

  if tg_op = ''INSERT'' then
    if new.status is distinct from ''DRAFT'' or new.treasury_operation_id is not null then
      if current_setting(''pos.engine_write'', true) is distinct from ''1'' then
        raise exception ''pos_tenders insert must be DRAFT without treasury_operation_id'';
      end if;
    end if;
  end if;

  return new;
end;
$$","drop trigger if exists pos_tenders_engine_guard on public.pos_tenders","create trigger pos_tenders_engine_guard
before insert or update on public.pos_tenders
for each row execute function public.prevent_pos_tender_engine_forgery()","create or replace function public.prevent_pos_session_expected_forgery()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if current_setting(''pos.engine_write'', true) = ''1'' then
    return new;
  end if;
  if tg_op = ''UPDATE'' then
    if new.opening_expected_cash is distinct from old.opening_expected_cash
      or new.closing_expected_cash is distinct from old.closing_expected_cash
      or new.closing_difference is distinct from old.closing_difference
      or new.status is distinct from old.status
      or new.closed_at is distinct from old.closed_at
    then
      raise exception ''pos_sessions expected/close fields are trusted-only'';
    end if;
  end if;
  return new;
end;
$$","drop trigger if exists pos_sessions_engine_guard on public.pos_sessions","create trigger pos_sessions_engine_guard
before update on public.pos_sessions
for each row execute function public.prevent_pos_session_expected_forgery()","create or replace function public.pos_tta_validate_before_write()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  v_ta public.treasury_accounts%rowtype;
  v_expected public.treasury_account_type;
begin
  v_expected := public.pos_expected_account_type(new.method);
  select * into v_ta from public.treasury_accounts where id = new.treasury_account_id;
  if not found or v_ta.organization_id is distinct from new.organization_id then
    raise exception ''invalid treasury account for tender mapping'';
  end if;
  if not v_ta.is_active then raise exception ''treasury account inactive''; end if;
  if v_ta.currency_code is distinct from ''ARS'' then raise exception ''ARS required''; end if;
  if v_ta.account_type is distinct from v_expected then
    raise exception ''method % requires account_type %'', new.method, v_expected;
  end if;
  return new;
end;
$$","drop trigger if exists pos_tta_validate_trg on public.pos_terminal_tender_accounts","create trigger pos_tta_validate_trg
before insert or update on public.pos_terminal_tender_accounts
for each row execute function public.pos_tta_validate_before_write()","create or replace function public.pos_terminal_validate_before_write()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  v_fpos public.fiscal_points_of_sale%rowtype;
begin
  if new.fiscal_point_of_sale_id is not null then
    select * into v_fpos from public.fiscal_points_of_sale where id = new.fiscal_point_of_sale_id;
    if not found then raise exception ''fiscal point of sale not found''; end if;
    if v_fpos.organization_id is distinct from new.organization_id then
      raise exception ''fiscal point of sale organization mismatch'';
    end if;
    if not v_fpos.is_active then raise exception ''fiscal point of sale inactive''; end if;
    if v_fpos.environment = ''PRODUCTION'' then
      raise exception ''PRODUCTION fiscal point of sale blocked for POS staging'';
    end if;
    if v_fpos.branch_id is not null and v_fpos.branch_id is distinct from new.branch_id then
      raise exception ''fiscal point of sale branch mismatch'';
    end if;
  end if;

  if new.default_customer_id is not null then
    perform public.pos_validate_walk_in_customer(new.organization_id, new.default_customer_id);
  end if;

  return new;
end;
$$","drop trigger if exists pos_terminals_validate_trg on public.pos_terminals","create trigger pos_terminals_validate_trg
before insert or update on public.pos_terminals
for each row execute function public.pos_terminal_validate_before_write()","create or replace function public.pos_settings_validate_before_write()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  perform public.pos_validate_walk_in_customer(new.organization_id, new.default_walk_in_customer_id);
  return new;
end;
$$","drop trigger if exists pos_settings_validate_trg on public.pos_settings","create trigger pos_settings_validate_trg
before insert or update on public.pos_settings
for each row execute function public.pos_settings_validate_before_write()","revoke all on function public.pos_assert_feature(uuid) from public, anon, authenticated","revoke all on function public.pos_assert_feature_code(uuid, text) from public, anon, authenticated","revoke all on function public.pos_validate_walk_in_customer(uuid, uuid) from public, anon, authenticated","revoke all on function public.pos_validate_tender_account(uuid, uuid, public.pos_tender_method, uuid)
  from public, anon, authenticated","revoke all on function public.pos_expected_account_type(public.pos_tender_method) from public, anon","grant execute on function public.pos_expected_account_type(public.pos_tender_method) to authenticated"}', 'phase9_pos_helpers'),
	('20260901130000', '{"-- Phase 9: POS session + checkout RPCs (STAGING ONLY)
-- Depends on: phase9_pos_core, phase9_pos_helpers
-- All RPCs: SECURITY DEFINER, search_path='''', grant authenticated / revoke public+anon
-- Engine GUC pos.engine_write=''1'' required for pos_sales status / pos_sessions expected fields.
-- Engine GUC sales.engine_write=''1'' required for sales_documents status transitions.

-- ===========================================================================
-- 1. open_pos_session
-- ===========================================================================

create or replace function public.open_pos_session(
  p_terminal_id         uuid,
  p_opening_counted_cash numeric,
  p_idempotency_key     text
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid        uuid := auth.uid();
  v_terminal   public.pos_terminals%rowtype;
  v_cash_acct  uuid;
  v_expected   numeric;
  v_session_id uuid;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  -- Lock terminal to prevent concurrent opens
  select * into v_terminal
  from public.pos_terminals
  where id = p_terminal_id
  for update;

  if not found then raise exception ''terminal not found''; end if;
  if not v_terminal.active then raise exception ''terminal is not active''; end if;

  if not public.has_org_role(
    v_terminal.organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  ) then
    raise exception ''insufficient role to open POS session'';
  end if;

  perform public.pos_assert_feature(v_terminal.organization_id);

  -- Idempotency
  select id into v_session_id
  from public.pos_sessions
  where organization_id = v_terminal.organization_id
    and idempotency_key = p_idempotency_key;
  if v_session_id is not null then return v_session_id; end if;

  -- Require an active CASH tender account mapping for this terminal
  select treasury_account_id into v_cash_acct
  from public.pos_terminal_tender_accounts
  where terminal_id = p_terminal_id
    and method = ''CASH''
    and active
  limit 1;

  if v_cash_acct is null then
    raise exception ''terminal has no active CASH tender account; configure pos_terminal_tender_accounts first'';
  end if;

  -- Opening expected = current ledger balance of the CASH account (POSTED legs only)
  v_expected := public.treasury_account_balance(v_cash_acct);

  perform set_config(''pos.engine_write'', ''1'', true);

  insert into public.pos_sessions (
    organization_id, terminal_id, cashier_id, status,
    opening_expected_cash, opening_counted_cash, idempotency_key
  ) values (
    v_terminal.organization_id, p_terminal_id, v_uid, ''OPEN'',
    v_expected, p_opening_counted_cash, p_idempotency_key
  )
  returning id into v_session_id;
  -- Unique index pos_sessions_one_open_per_terminal enforces one OPEN per terminal.

  return v_session_id;
end;
$$","-- ===========================================================================
-- 2. close_pos_session
-- ===========================================================================

create or replace function public.close_pos_session(
  p_session_id          uuid,
  p_closing_counted_cash numeric,
  p_idempotency_key     text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid             uuid := auth.uid();
  v_session         public.pos_sessions%rowtype;
  v_opening_base    numeric;
  v_cash_posted     numeric;
  v_closing_expected numeric;
  v_difference      numeric;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_session
  from public.pos_sessions
  where id = p_session_id
  for update;

  if not found then raise exception ''session not found''; end if;

  if not public.has_org_role(
    v_session.organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  ) then
    raise exception ''insufficient role to close POS session'';
  end if;

  perform public.pos_assert_feature(v_session.organization_id);

  -- Idempotent if already closed
  if v_session.status = ''CLOSED'' then return v_session.id; end if;

  -- Block on dangerous in-flight states
  if exists (
    select 1 from public.pos_sales
    where session_id = p_session_id
      and status in (
        ''STOCK_RESERVED'',''WAITING_FISCAL'',''FISCAL_AUTHORIZED'',
        ''FINALIZING'',''RECONCILIATION_REQUIRED''
      )
  ) then
    raise exception ''session has sales in pending states (STOCK_RESERVED/WAITING_FISCAL/...); ''
                    ''complete or reconcile them before closing'';
  end if;

  -- Block on unresolved open sales
  if exists (
    select 1 from public.pos_sales
    where session_id = p_session_id
      and status in (''DRAFT'',''READY_TO_CHECKOUT'')
  ) then
    raise exception ''session has open sales (DRAFT/READY_TO_CHECKOUT); ''
                    ''cancel them explicitly before closing'';
  end if;

  -- Closing expected:
  --   base = opening_counted_cash (actual counted) or opening_expected_cash if not counted
  --   + sum of all POSTED CASH tender amounts for COMPLETED sales in this session
  v_opening_base := coalesce(v_session.opening_counted_cash, v_session.opening_expected_cash);

  select coalesce(sum(pt.amount), 0) into v_cash_posted
  from public.pos_tenders pt
  join public.pos_sales ps on ps.id = pt.pos_sale_id
  where ps.session_id = p_session_id
    and ps.status = ''COMPLETED''
    and pt.method = ''CASH''
    and pt.status = ''POSTED'';

  v_closing_expected := v_opening_base + v_cash_posted;
  v_difference       := coalesce(p_closing_counted_cash, 0) - v_closing_expected;

  perform set_config(''pos.engine_write'', ''1'', true);

  update public.pos_sessions
  set status                = ''CLOSED'',
      closed_at             = timezone(''utc'', now()),
      closing_counted_cash  = p_closing_counted_cash,
      closing_expected_cash = v_closing_expected,
      closing_difference    = v_difference
  where id = p_session_id;

  return p_session_id;
end;
$$","-- ===========================================================================
-- 3. start_pos_sale
-- ===========================================================================

create or replace function public.start_pos_sale(
  p_session_id      uuid,
  p_idempotency_key text,
  p_customer_id     uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid            uuid := auth.uid();
  v_org_id         uuid;
  v_session        public.pos_sessions%rowtype;
  v_terminal       public.pos_terminals%rowtype;
  v_settings       public.pos_settings%rowtype;
  v_customer_id    uuid;
  v_internal_num   text;
  v_sales_doc_id   uuid;
  v_pos_sale_id    uuid;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  -- Fast idempotency check before locking
  select organization_id into v_org_id
  from public.pos_sessions
  where id = p_session_id;

  if v_org_id is null then raise exception ''session not found''; end if;

  select id into v_pos_sale_id
  from public.pos_sales
  where organization_id = v_org_id
    and idempotency_key = p_idempotency_key;
  if v_pos_sale_id is not null then return v_pos_sale_id; end if;

  select * into v_session
  from public.pos_sessions
  where id = p_session_id
  for share;

  if v_session.status <> ''OPEN'' then
    raise exception ''session is not OPEN (status: %)'', v_session.status;
  end if;

  if not public.has_org_role(
    v_session.organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  ) then
    raise exception ''insufficient role to start POS sale'';
  end if;

  perform public.pos_assert_feature(v_session.organization_id);

  select * into v_terminal
  from public.pos_terminals
  where id = v_session.terminal_id
    and organization_id = v_session.organization_id;
  if not found then raise exception ''terminal not found''; end if;

  select * into v_settings
  from public.pos_settings
  where organization_id = v_session.organization_id;

  -- Customer: explicit arg > terminal default > org walk-in default
  v_customer_id := coalesce(
    p_customer_id,
    v_terminal.default_customer_id,
    v_settings.default_walk_in_customer_id
  );

  if v_customer_id is null then
    raise exception ''no customer resolved; set pos_settings.default_walk_in_customer_id'';
  end if;

  perform public.pos_validate_walk_in_customer(v_session.organization_id, v_customer_id);

  -- Allocate sales internal number
  v_internal_num := public.next_sales_internal_number(
    v_session.organization_id,
    ''SALES_ORDER''::public.sales_document_type,
    current_date
  );

  perform set_config(''sales.engine_write'', ''1'', true);

  insert into public.sales_documents (
    organization_id, branch_id, document_type, internal_number,
    counterparty_id, status, document_date, currency_code, created_by
  ) values (
    v_session.organization_id, v_terminal.branch_id, ''SALES_ORDER'', v_internal_num,
    v_customer_id, ''DRAFT'', current_date, ''ARS'', v_uid
  )
  returning id into v_sales_doc_id;

  perform set_config(''sales.engine_write'', ''0'', true);
  perform set_config(''pos.engine_write'', ''1'', true);

  insert into public.pos_sales (
    organization_id, terminal_id, session_id, sales_document_id,
    status, idempotency_key, created_by
  ) values (
    v_session.organization_id, v_session.terminal_id, p_session_id, v_sales_doc_id,
    ''DRAFT'', p_idempotency_key, v_uid
  )
  returning id into v_pos_sale_id;

  return v_pos_sale_id;
end;
$$","-- ===========================================================================
-- 4. cancel_pos_sale_draft
-- ===========================================================================

create or replace function public.cancel_pos_sale_draft(
  p_pos_sale_id uuid,
  p_reason      text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid    uuid := auth.uid();
  v_sale   public.pos_sales%rowtype;
  v_res_id uuid;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id
  for update;

  if not found then raise exception ''POS sale not found''; end if;

  if not public.has_org_role(
    v_sale.organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  ) then
    raise exception ''insufficient role to cancel POS sale'';
  end if;

  perform public.pos_assert_feature(v_sale.organization_id);

  -- Idempotent
  if v_sale.status = ''CANCELLED'' then return v_sale.id; end if;

  -- Hard deny for fiscal / completed states
  if v_sale.status in (
    ''WAITING_FISCAL'',''FISCAL_AUTHORIZED'',''FINALIZING'',
    ''COMPLETED'',''RECONCILIATION_REQUIRED''
  ) then
    raise exception ''cannot cancel POS sale in status %'', v_sale.status;
  end if;

  if v_sale.status not in (''DRAFT'',''READY_TO_CHECKOUT'',''STOCK_RESERVED'') then
    raise exception ''unexpected POS sale status: %'', v_sale.status;
  end if;

  -- For STOCK_RESERVED: release active inventory reservations
  if v_sale.status = ''STOCK_RESERVED'' then
    for v_res_id in
      select ir.id
      from public.inventory_reservations ir
      join public.sales_document_lines sdl
        on sdl.id = ir.sales_document_line_id
      where sdl.sales_document_id = v_sale.sales_document_id
        and ir.organization_id    = v_sale.organization_id
        and ir.status             = ''ACTIVE''
    loop
      perform public.release_inventory_reservation(v_res_id);
    end loop;
  end if;

  -- Cancel the underlying sales document directly.
  -- We bypass cancel_sales_document() because:
  --   (a) operators lack the manager+ role it requires, and
  --   (b) READY_TO_INVOICE orders are blocked by it for STOCK_RESERVED path.
  perform set_config(''sales.engine_write'', ''1'', true);
  update public.sales_documents
  set status       = ''CANCELLED'',
      cancelled_at = timezone(''utc'', now()),
      cancel_reason = nullif(trim(coalesce(p_reason, '''')), '''')
  where id = v_sale.sales_document_id;
  perform set_config(''sales.engine_write'', ''0'', true);

  perform set_config(''pos.engine_write'', ''1'', true);
  update public.pos_sales
  set status = ''CANCELLED''
  where id = p_pos_sale_id;

  return p_pos_sale_id;
end;
$$","-- ===========================================================================
-- 5. set_pos_tenders
-- ===========================================================================

create or replace function public.set_pos_tenders(
  p_pos_sale_id uuid,
  p_tenders     jsonb
)
returns void
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid           uuid := auth.uid();
  v_sale          public.pos_sales%rowtype;
  v_item          jsonb;
  v_method        public.pos_tender_method;
  v_amount        numeric;
  v_account_id    uuid;
  v_cash_received numeric;
  v_change_given  numeric;
  v_idem          text;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id
  for update;

  if not found then raise exception ''POS sale not found''; end if;

  if not public.has_org_role(
    v_sale.organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  ) then
    raise exception ''insufficient role to set tenders'';
  end if;

  perform public.pos_assert_feature(v_sale.organization_id);

  if v_sale.status not in (
    ''DRAFT'',''READY_TO_CHECKOUT'',''STOCK_RESERVED'',''WAITING_FISCAL'',''FISCAL_AUTHORIZED''
  ) then
    raise exception ''cannot set tenders in status %'', v_sale.status;
  end if;

  -- Replace all DRAFT tenders (POSTED/REVERSED are untouched)
  delete from public.pos_tenders
  where pos_sale_id = p_pos_sale_id
    and status = ''DRAFT'';

  for v_item in select * from jsonb_array_elements(p_tenders)
  loop
    v_method := (v_item->>''method'')::public.pos_tender_method;
    v_amount := (v_item->>''amount'')::numeric;

    if v_method is null then raise exception ''tender method is required''; end if;
    if v_amount is null or v_amount <= 0 then
      raise exception ''tender amount must be positive (got %)'', v_amount;
    end if;

    -- Resolve treasury account: explicit param > terminal mapping
    v_account_id := (v_item->>''treasury_account_id'')::uuid;

    if v_account_id is null then
      select treasury_account_id into v_account_id
      from public.pos_terminal_tender_accounts
      where terminal_id = v_sale.terminal_id
        and method      = v_method
        and active
      limit 1;

      if v_account_id is null then
        raise exception
          ''no treasury account for method % on terminal; ''
          ''provide treasury_account_id or configure pos_terminal_tender_accounts'',
          v_method;
      end if;
    end if;

    -- Full validation: type, org, active, mapping
    perform public.pos_validate_tender_account(
      v_sale.organization_id, v_sale.terminal_id, v_method, v_account_id
    );

    -- CASH change math
    v_cash_received := null;
    v_change_given  := null;

    if v_method = ''CASH'' and (v_item->>''cash_received'') is not null then
      v_cash_received := (v_item->>''cash_received'')::numeric;
      if v_cash_received < v_amount then
        raise exception ''cash_received (%) must be >= amount (%)'', v_cash_received, v_amount;
      end if;
      v_change_given := v_cash_received - v_amount;
    end if;

    -- Use provided idempotency_key or generate one
    v_idem := coalesce(
      nullif(trim(coalesce(v_item->>''idempotency_key'', '''')), ''''),
      gen_random_uuid()::text
    );

    insert into public.pos_tenders (
      organization_id, pos_sale_id, method, treasury_account_id,
      amount, cash_received, change_given,
      reference, provider_label, status, idempotency_key
    ) values (
      v_sale.organization_id, p_pos_sale_id, v_method, v_account_id,
      v_amount, v_cash_received, v_change_given,
      nullif(trim(coalesce(v_item->>''reference'', '''')), ''''),
      nullif(trim(coalesce(v_item->>''provider_label'', '''')), ''''),
      ''DRAFT'', v_idem
    );
  end loop;
end;
$$","-- ===========================================================================
-- 6. begin_pos_checkout
-- ===========================================================================

create or replace function public.begin_pos_checkout(
  p_pos_sale_id     uuid,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid        uuid := auth.uid();
  v_sale       public.pos_sales%rowtype;
  v_terminal   public.pos_terminals%rowtype;
  v_doc        public.sales_documents%rowtype;
  v_snapshot   jsonb;
  v_line_count int;
  v_line       record;
  v_has_stock  boolean := false;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id
  for update;

  if not found then raise exception ''POS sale not found''; end if;

  if not public.has_org_role(
    v_sale.organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  ) then
    raise exception ''insufficient role for POS checkout'';
  end if;

  perform public.pos_assert_feature(v_sale.organization_id);

  -- Idempotent: already past checkout initiation
  if v_sale.status in (
    ''STOCK_RESERVED'',''WAITING_FISCAL'',''FISCAL_AUTHORIZED'',''FINALIZING'',''COMPLETED''
  ) then
    return v_sale.id;
  end if;

  if v_sale.status not in (''DRAFT'',''READY_TO_CHECKOUT'') then
    raise exception ''begin_pos_checkout requires DRAFT or READY_TO_CHECKOUT (got %)'', v_sale.status;
  end if;

  -- Lock and read the underlying sales document
  select * into v_doc
  from public.sales_documents
  where id = v_sale.sales_document_id
  for update;

  if v_doc.status not in (''DRAFT'') then
    raise exception ''sales document is already frozen (status %); cannot re-checkout'', v_doc.status;
  end if;

  -- Must have at least one line
  select count(*) into v_line_count
  from public.sales_document_lines
  where sales_document_id = v_sale.sales_document_id;

  if v_line_count < 1 then raise exception ''POS sale must have at least one line before checkout''; end if;

  -- Currency guard
  if v_doc.currency_code is distinct from ''ARS'' then
    raise exception ''POS sales must be in ARS (got %)'', v_doc.currency_code;
  end if;

  select * into v_terminal
  from public.pos_terminals
  where id = v_sale.terminal_id
    and organization_id = v_sale.organization_id;

  if not found then raise exception ''terminal not found''; end if;

  -- Refresh totals before freezing
  perform public.refresh_sales_document_totals(v_sale.sales_document_id);

  -- Build counterparty snapshot
  v_snapshot := public.build_counterparty_snapshot(v_sale.organization_id, v_doc.counterparty_id);

  -- Freeze the sales document: DRAFT → CONFIRMED → READY_TO_INVOICE
  -- Done inline to allow ''operator'' role (confirm_sales_order requires manager+).
  perform set_config(''sales.engine_write'', ''1'', true);

  update public.sales_documents
  set status                 = ''CONFIRMED'',
      confirmed_by           = v_uid,
      confirmed_at           = timezone(''utc'', now()),
      counterparty_snapshot  = v_snapshot,
      is_commercially_frozen = true
  where id = v_sale.sales_document_id
    and status = ''DRAFT'';

  update public.sales_documents
  set status = ''READY_TO_INVOICE''
  where id = v_sale.sales_document_id
    and status = ''CONFIRMED'';

  perform set_config(''sales.engine_write'', ''0'', true);

  -- Create inventory reservations for STOCK_ITEM lines only
  for v_line in
    select sdl.*
    from public.sales_document_lines sdl
    join public.products p
      on p.id = sdl.product_id
     and p.organization_id = sdl.organization_id
    where sdl.sales_document_id = v_sale.sales_document_id
      and p.product_type    = ''STOCK_ITEM''
      and p.track_inventory = true
      and p.active          = true
  loop
    -- Assert inventory feature once (on first STOCK_ITEM hit)
    if not v_has_stock then
      perform public.pos_assert_feature_code(v_sale.organization_id, ''inventory'');
      v_has_stock := true;
    end if;

    perform public.create_inventory_reservation(
      v_sale.organization_id,
      v_line.product_id,
      v_terminal.warehouse_id,
      v_sale.sales_document_id,
      v_line.id,
      v_line.quantity,
      ''pos-res:'' || v_line.id::text   -- idempotency_key: stable per sale line
    );
  end loop;
  -- SERVICE / NON_STOCK lines: no reservation needed, skip.

  -- Transition POS sale to STOCK_RESERVED
  perform set_config(''pos.engine_write'', ''1'', true);

  update public.pos_sales
  set status              = ''STOCK_RESERVED'',
      checkout_started_at = timezone(''utc'', now())
  where id = p_pos_sale_id;

  return p_pos_sale_id;
end;
$$","-- ===========================================================================
-- 7. reset_pos_checkout
-- For STOCK_RESERVED only.  Releases reservations and cancels via the standard
-- cancel path.  Editable state (DRAFT lines) is NOT recoverable once the sales
-- order is commercially frozen — the correct flow is to cancel and open a new
-- sale.  See design doc D6.
-- ===========================================================================

create or replace function public.reset_pos_checkout(p_pos_sale_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid  uuid := auth.uid();
  v_sale public.pos_sales%rowtype;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id;

  if not found then raise exception ''POS sale not found''; end if;

  if not public.has_org_role(
    v_sale.organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  ) then
    raise exception ''insufficient role to reset POS checkout'';
  end if;

  if v_sale.status <> ''STOCK_RESERVED'' then
    raise exception ''reset_pos_checkout only allowed in STOCK_RESERVED (got %)'', v_sale.status;
  end if;

  -- Delegate: releases reservations + cancels sales doc + sets pos CANCELLED
  return public.cancel_pos_sale_draft(p_pos_sale_id, ''checkout reset by operator'');
end;
$$","-- ===========================================================================
-- 8. prepare_pos_fiscal_handoff
-- ===========================================================================

create or replace function public.prepare_pos_fiscal_handoff(
  p_pos_sale_id                  uuid,
  p_document_type_internal_code  text default null,
  p_condicion_iva_receptor_id    int  default null
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid       uuid := auth.uid();
  v_sale      public.pos_sales%rowtype;
  v_terminal  public.pos_terminals%rowtype;
  v_settings  public.pos_settings%rowtype;
  v_doc_type  text;
  v_condicion int;
  v_fiscal_id uuid;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id
  for update;

  if not found then raise exception ''POS sale not found''; end if;

  if not public.has_org_role(
    v_sale.organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  ) then
    raise exception ''insufficient role for POS fiscal handoff'';
  end if;

  perform public.pos_assert_feature(v_sale.organization_id);
  perform public.pos_assert_feature_code(v_sale.organization_id, ''fiscal_invoicing'');

  -- Idempotent: already in or past fiscal flow
  if v_sale.status in (''WAITING_FISCAL'',''FISCAL_AUTHORIZED'',''FINALIZING'',''COMPLETED'') then
    return v_sale.fiscal_document_id;
  end if;

  if v_sale.status <> ''STOCK_RESERVED'' then
    raise exception ''prepare_pos_fiscal_handoff requires STOCK_RESERVED (got %)'', v_sale.status;
  end if;

  select * into v_terminal
  from public.pos_terminals
  where id = v_sale.terminal_id
    and organization_id = v_sale.organization_id;

  if not found then raise exception ''terminal not found''; end if;

  if v_terminal.fiscal_point_of_sale_id is null then
    raise exception ''terminal.fiscal_point_of_sale_id is not configured'';
  end if;

  select * into v_settings
  from public.pos_settings
  where organization_id = v_sale.organization_id;

  -- Resolve document type: arg > setting > default
  v_doc_type := coalesce(
    nullif(trim(coalesce(p_document_type_internal_code, '''')), ''''),
    v_settings.default_document_type_internal_code,
    ''INVOICE_C''
  );

  -- Resolve condición IVA receptor: arg > setting > 5 (Consumidor Final)
  v_condicion := coalesce(
    p_condicion_iva_receptor_id,
    v_settings.default_condicion_iva_receptor_id,
    5
  );

  -- Prepare fiscal invoice from the READY_TO_INVOICE sales order
  v_fiscal_id := public.prepare_fiscal_invoice_from_sales_order(
    v_sale.sales_document_id,
    v_terminal.fiscal_point_of_sale_id,
    v_doc_type,
    current_date,
    v_condicion
  );

  -- Mark READY_TO_AUTHORIZE so the application layer can call ARCA FECAE
  perform public.mark_fiscal_ready_to_authorize(v_fiscal_id);

  -- Link fiscal doc + transition POS sale
  perform set_config(''pos.engine_write'', ''1'', true);

  update public.pos_sales
  set status             = ''WAITING_FISCAL'',
      fiscal_document_id = v_fiscal_id
  where id = p_pos_sale_id;

  return v_fiscal_id;
end;
$$","-- ===========================================================================
-- 9. sync_pos_fiscal_status
-- Reads the linked fiscal_document status and advances pos_sale status accordingly.
-- The application must call this after complete_fiscal_authorization to advance
-- a WAITING_FISCAL sale to FISCAL_AUTHORIZED (or RECONCILIATION_REQUIRED).
-- ===========================================================================

create or replace function public.sync_pos_fiscal_status(p_pos_sale_id uuid)
returns text
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid            uuid := auth.uid();
  v_sale           public.pos_sales%rowtype;
  v_fiscal_status  text;
  v_new_status     public.pos_sale_status;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id
  for update;

  if not found then raise exception ''POS sale not found''; end if;

  if not public.has_org_role(
    v_sale.organization_id,
    array[''owner'',''admin'',''manager'',''operator'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role to sync fiscal status'';
  end if;

  perform public.pos_assert_feature(v_sale.organization_id);

  if v_sale.fiscal_document_id is null then
    raise exception ''no fiscal document linked to this POS sale'';
  end if;

  -- Only meaningful while in fiscal flow
  if v_sale.status not in (''WAITING_FISCAL'',''FISCAL_AUTHORIZED'',''RECONCILIATION_REQUIRED'') then
    return v_sale.status::text;
  end if;

  select status::text into v_fiscal_status
  from public.fiscal_documents
  where id = v_sale.fiscal_document_id;

  if v_fiscal_status is null then raise exception ''fiscal document not found''; end if;

  v_new_status := case v_fiscal_status
    when ''AUTHORIZED''              then ''FISCAL_AUTHORIZED''::public.pos_sale_status
    when ''RECONCILIATION_REQUIRED'' then ''RECONCILIATION_REQUIRED''::public.pos_sale_status
    -- REJECTED: stay in WAITING_FISCAL so operator can fix and retry
    when ''REJECTED''                then ''WAITING_FISCAL''::public.pos_sale_status
    -- AUTHORIZING, READY_TO_AUTHORIZE, DRAFT: no change
    else v_sale.status
  end;

  if v_new_status is distinct from v_sale.status then
    perform set_config(''pos.engine_write'', ''1'', true);
    update public.pos_sales
    set status = v_new_status
    where id = p_pos_sale_id;
  end if;

  return v_new_status::text;
end;
$$","-- ===========================================================================
-- 10. ensure_pos_walk_in_and_settings
-- Idempotent bootstrap: creates walk-in counterparty + CUSTOMER role +
-- pos_settings if any are missing for the org.
-- ===========================================================================

create or replace function public.ensure_pos_walk_in_and_settings(
  p_org_id    uuid,
  p_legal_name text default ''Consumidor Final''
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid         uuid := auth.uid();
  v_customer_id uuid;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;

  if not public.has_org_role(
    p_org_id,
    array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
  ) then
    raise exception ''insufficient role for POS settings setup'';
  end if;

  perform public.pos_assert_feature(p_org_id);

  -- Find or create walk-in counterparty
  select id into v_customer_id
  from public.counterparties
  where organization_id = p_org_id
    and legal_name       = p_legal_name
    and is_active        = true
  order by created_at asc
  limit 1;

  if v_customer_id is null then
    insert into public.counterparties (
      organization_id, legal_name, is_active, created_by
    ) values (
      p_org_id, p_legal_name, true, v_uid
    )
    returning id into v_customer_id;
  end if;

  -- Ensure CUSTOMER role (idempotent)
  insert into public.counterparty_roles (organization_id, counterparty_id, role)
  values (p_org_id, v_customer_id, ''CUSTOMER'')
  on conflict do nothing;

  -- Ensure pos_settings row.
  -- The pos_settings_validate_trg trigger fires BEFORE INSERT and calls
  -- pos_validate_walk_in_customer, so the CUSTOMER role must exist first (above).
  insert into public.pos_settings (organization_id, default_walk_in_customer_id)
  values (p_org_id, v_customer_id)
  on conflict (organization_id) do nothing;

  return v_customer_id;
end;
$$","-- ===========================================================================
-- Grant / Revoke
-- Pattern: revoke from public + anon (belt-and-suspenders), grant authenticated.
-- Internal helpers remain revoked from all client roles.
-- ===========================================================================

-- open_pos_session
revoke all on function public.open_pos_session(uuid, numeric, text)
  from public, anon","grant execute on function public.open_pos_session(uuid, numeric, text)
  to authenticated","-- close_pos_session
revoke all on function public.close_pos_session(uuid, numeric, text)
  from public, anon","grant execute on function public.close_pos_session(uuid, numeric, text)
  to authenticated","-- start_pos_sale
revoke all on function public.start_pos_sale(uuid, text, uuid)
  from public, anon","grant execute on function public.start_pos_sale(uuid, text, uuid)
  to authenticated","-- cancel_pos_sale_draft
revoke all on function public.cancel_pos_sale_draft(uuid, text)
  from public, anon","grant execute on function public.cancel_pos_sale_draft(uuid, text)
  to authenticated","-- set_pos_tenders
revoke all on function public.set_pos_tenders(uuid, jsonb)
  from public, anon","grant execute on function public.set_pos_tenders(uuid, jsonb)
  to authenticated","-- begin_pos_checkout
revoke all on function public.begin_pos_checkout(uuid, text)
  from public, anon","grant execute on function public.begin_pos_checkout(uuid, text)
  to authenticated","-- reset_pos_checkout
revoke all on function public.reset_pos_checkout(uuid)
  from public, anon","grant execute on function public.reset_pos_checkout(uuid)
  to authenticated","-- prepare_pos_fiscal_handoff
revoke all on function public.prepare_pos_fiscal_handoff(uuid, text, int)
  from public, anon","grant execute on function public.prepare_pos_fiscal_handoff(uuid, text, int)
  to authenticated","-- sync_pos_fiscal_status
revoke all on function public.sync_pos_fiscal_status(uuid)
  from public, anon","grant execute on function public.sync_pos_fiscal_status(uuid)
  to authenticated","-- ensure_pos_walk_in_and_settings
revoke all on function public.ensure_pos_walk_in_and_settings(uuid, text)
  from public, anon","grant execute on function public.ensure_pos_walk_in_and_settings(uuid, text)
  to authenticated"}', 'phase9_pos_session_checkout'),
	('20260901140000', '{"-- =============================================================================
-- Phase 9: POS finalize + treasury permission boundary + staging fiscal fixture
-- =============================================================================
--
-- INTENTIONAL CLIENT RPCs (callable by role = authenticated):
--
--   public.finalize_pos_sale(p_pos_sale_id uuid, p_idempotency_key text)
--     → Called by POS cashier / manager after fiscal authorization.
--       Idempotent: safe to retry after crash (FINALIZING recovery path).
--       Roles: owner, admin, manager, operator.
--
-- SERVICE_ROLE-ONLY (NOT exported to authenticated users):
--
--   public.pos_test_fixture_mark_fiscal_authorized(
--       p_fiscal_document_id uuid,
--       p_cae text,
--       p_cae_expiration date
--   )
--     → Staging / CI fixture only. Marks a fiscal document AUTHORIZED without
--       going through ARCA, exactly mirroring complete_fiscal_authorization
--       success path. NEVER grant to authenticated or anon.
--
-- NOTE: post_treasury_operation is NOT broadened for generic operator use.
-- The POS finalize gate (treasury.pos_finalize = ''1'') is COLLECTION-only and
-- requires validated tender linkage to a FINALIZING sale. ADJUSTMENT / PAYMENT /
-- TRANSFER / OPENING_BALANCE require the usual owner/admin/accountant roles.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. Patch public.post_treasury_operation
--    Source: Phase 7 (20260701140000_phase7_post_treasury.sql) reprinted
--    verbatim. ONLY CHANGE: PAYMENT/COLLECTION/TRANSFER/OPENING_BALANCE role
--    gate now includes POS-finalize contextual authorization for COLLECTION
--    when treasury.pos_finalize = ''1''. All other logic is identical.
-- ---------------------------------------------------------------------------

create or replace function public.post_treasury_operation(p_operation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid       uuid := auth.uid();
  v_op        public.treasury_operations%rowtype;
  v_period_id uuid;
  v_entry_id  uuid;
  v_existing  uuid;
  v_leg       record;
  v_leg_count int;
  v_inflow    numeric(19,4);
  v_outflow   numeric(19,4);
  v_src_acct  uuid;
  v_dst_acct  uuid;
  v_src_coa   uuid;
  v_dst_coa   uuid;
  v_ap_coa    uuid;
  v_ar_coa    uuid;
  v_eq_coa    uuid;
  v_adj_coa   uuid;
  v_alloc     record;
  v_alloc_sum numeric(19,4);
  v_open      numeric(19,4);
  v_source    public.journal_source_type;
  v_desc      text;
begin
  if v_uid is null then raise exception ''authentication required''; end if;

  select * into v_op
  from public.treasury_operations
  where id = p_operation_id
  for update;
  if not found then raise exception ''treasury operation not found''; end if;

  -- Tenant feature gate from the protected row
  perform public.treasury_assert_feature(v_op.organization_id, array[''cash'',''banks'']);

  if v_op.status = ''POSTED'' and v_op.journal_entry_id is not null then
    return p_operation_id;
  end if;
  if v_op.status is distinct from ''DRAFT'' then
    raise exception ''only DRAFT operations can be posted'';
  end if;
  if v_op.currency_code is distinct from ''ARS'' then
    raise exception ''unsupported currency for Phase 7: %'', v_op.currency_code;
  end if;

  -- -------------------------------------------------------------------------
  -- Permissions by operation type
  -- -------------------------------------------------------------------------
  if v_op.operation_type = ''ADJUSTMENT'' then
    if not public.has_org_role(
      v_op.organization_id, array[''owner'',''accountant'']::public.member_role[]
    ) then
      raise exception ''only owner/accountant may post adjustments'';
    end if;
    if v_op.reason is null or char_length(trim(v_op.reason)) < 3 then
      raise exception ''adjustment reason is required'';
    end if;

  elsif v_op.operation_type in (''PAYMENT'', ''COLLECTION'', ''TRANSFER'', ''OPENING_BALANCE'') then
    -- -----------------------------------------------------------------------
    -- Phase 9 POS finalize gate — COLLECTION only, context-validated.
    -- treasury.pos_finalize = ''1'' is set exclusively by finalize_pos_sale.
    -- The two OR-branches below cover the live path and the idempotent-retry
    -- path (tender already linked and op re-posted while sale is FINALIZING
    -- or just-COMPLETED).
    -- ADJUSTMENT / PAYMENT / TRANSFER / OPENING_BALANCE are NOT affected.
    -- -----------------------------------------------------------------------
    if current_setting(''treasury.pos_finalize'', true) = ''1''
       and v_op.operation_type = ''COLLECTION'' then
      if not exists (
        select 1
        from public.pos_tenders t
        join public.pos_sales   s on s.id = t.pos_sale_id
        where t.treasury_operation_id = p_operation_id
          and s.status = ''FINALIZING''
          and t.status = ''DRAFT''
      ) and not exists (
        -- idempotent retry: tender already linked to this posted op while
        -- sale is FINALIZING or just reached COMPLETED
        select 1
        from public.pos_tenders t
        join public.pos_sales   s on s.id = t.pos_sale_id
        where t.treasury_operation_id = p_operation_id
          and s.status in (''FINALIZING'', ''COMPLETED'')
          and t.status in (''DRAFT'', ''POSTED'')
      ) then
        raise exception ''POS finalize treasury context invalid'';
      end if;
    elsif not public.has_org_role(
      v_op.organization_id,
      array[''owner'',''admin'',''accountant'']::public.member_role[]
    ) then
      raise exception ''insufficient role to post treasury operation'';
    end if;
  end if;

  -- Idempotent journal reuse
  select id into v_existing
  from public.journal_entries
  where organization_id = v_op.organization_id
    and source_id        = p_operation_id
    and status           = ''POSTED''
    and source_type in (''PAYMENT'',''COLLECTION'',''BANK'',''SYSTEM'')
  limit 1;
  if v_existing is not null then
    perform set_config(''treasury.engine_write'', ''1'', true);
    update public.treasury_operations
    set status            = ''POSTED'',
        journal_entry_id  = v_existing,
        accounting_status = ''POSTED'',
        posted_by         = coalesce(posted_by, v_uid),
        posted_at         = coalesce(posted_at, timezone(''utc'', now()))
    where id = p_operation_id;
    return p_operation_id;
  end if;

  select period_id into v_period_id
  from public.resolve_open_period(v_op.organization_id, v_op.operation_date);
  if v_period_id is null then
    perform set_config(''treasury.engine_write'', ''1'', true);
    update public.treasury_operations
    set accounting_status = ''ACCOUNTING_REQUIRES_REVIEW'',
        updated_at        = timezone(''utc'', now())
    where id = p_operation_id;
    return p_operation_id;
  end if;

  select count(*)::int,
         coalesce(sum(case when direction = ''INFLOW''  then amount else 0 end), 0),
         coalesce(sum(case when direction = ''OUTFLOW'' then amount else 0 end), 0)
  into v_leg_count, v_inflow, v_outflow
  from public.treasury_operation_legs
  where treasury_operation_id = p_operation_id;

  -- Validate legs by type
  if v_op.operation_type = ''PAYMENT'' then
    if v_leg_count <> 1 or v_outflow <> v_op.amount or v_inflow <> 0 then
      raise exception ''PAYMENT requires exactly one OUTFLOW equal to amount'';
    end if;
  elsif v_op.operation_type = ''COLLECTION'' then
    if v_leg_count <> 1 or v_inflow <> v_op.amount or v_outflow <> 0 then
      raise exception ''COLLECTION requires exactly one INFLOW equal to amount'';
    end if;
  elsif v_op.operation_type = ''TRANSFER'' then
    if v_leg_count <> 2 or v_inflow <> v_op.amount or v_outflow <> v_op.amount then
      raise exception ''TRANSFER requires equal INFLOW and OUTFLOW'';
    end if;
    select treasury_account_id into v_src_acct
    from public.treasury_operation_legs
    where treasury_operation_id = p_operation_id and direction = ''OUTFLOW'';
    select treasury_account_id into v_dst_acct
    from public.treasury_operation_legs
    where treasury_operation_id = p_operation_id and direction = ''INFLOW'';
    if v_src_acct is not distinct from v_dst_acct then
      raise exception ''TRANSFER source and destination must differ'';
    end if;
  elsif v_op.operation_type = ''OPENING_BALANCE'' then
    if v_leg_count <> 1 or (v_inflow + v_outflow) <> v_op.amount then
      raise exception ''OPENING_BALANCE requires exactly one leg equal to amount'';
    end if;
    if exists (
      select 1
      from public.treasury_operation_legs l
      join public.treasury_operations     o on o.id = l.treasury_operation_id
      where l.treasury_account_id = (
        select treasury_account_id
        from public.treasury_operation_legs
        where treasury_operation_id = p_operation_id
        limit 1
      )
        and o.operation_type = ''OPENING_BALANCE''
        and o.status         = ''POSTED''
        and o.id             <> p_operation_id
    ) then
      raise exception ''treasury account already has a POSTED opening balance'';
    end if;
  elsif v_op.operation_type = ''ADJUSTMENT'' then
    if v_leg_count <> 1 or (v_inflow + v_outflow) <> v_op.amount then
      raise exception ''ADJUSTMENT requires exactly one leg equal to amount'';
    end if;
  end if;

  -- All legs must be active ARS accounts
  for v_leg in
    select l.*, ta.accounting_account_id, ta.is_active,
           ta.currency_code as tac
    from public.treasury_operation_legs l
    join public.treasury_accounts        ta on ta.id = l.treasury_account_id
    where l.treasury_operation_id = p_operation_id
  loop
    if not v_leg.is_active then
      raise exception ''treasury account inactive'';
    end if;
    if v_leg.tac is distinct from ''ARS'' then
      raise exception ''treasury account currency must be ARS'';
    end if;
  end loop;

  -- PAYMENT: validate allocations and lock AP items
  if v_op.operation_type = ''PAYMENT'' then
    select coalesce(sum(allocated_amount), 0) into v_alloc_sum
    from public.payment_allocations
    where treasury_operation_id = p_operation_id;
    if v_alloc_sum <> v_op.amount then
      raise exception ''payment allocations must equal payment amount'';
    end if;

    perform 1
    from public.accounts_payable_items ap
    where ap.id in (
      select accounts_payable_item_id
      from public.payment_allocations
      where treasury_operation_id = p_operation_id
    )
    order by ap.id
    for update;

    for v_alloc in
      select pa.*,
             ap.open_amount as ap_open,
             ap.direction   as ap_dir,
             ap.supplier_id as ap_supplier
      from public.payment_allocations pa
      join public.accounts_payable_items ap
        on ap.id = pa.accounts_payable_item_id
      where pa.treasury_operation_id = p_operation_id
      order by pa.accounts_payable_item_id
    loop
      if v_alloc.ap_dir is distinct from ''AP_INCREASE'' then
        raise exception ''payments may only allocate to AP_INCREASE items'';
      end if;
      if v_alloc.ap_supplier is distinct from v_op.counterparty_id then
        raise exception ''AP allocation supplier mismatch'';
      end if;
      if v_alloc.allocated_amount > v_alloc.ap_open then
        raise exception ''allocation exceeds AP open amount (concurrency)'';
      end if;
    end loop;
  end if;

  -- COLLECTION: validate allocations and lock AR items
  if v_op.operation_type = ''COLLECTION'' then
    select coalesce(sum(allocated_amount), 0) into v_alloc_sum
    from public.collection_allocations
    where treasury_operation_id = p_operation_id;
    if v_alloc_sum <> v_op.amount then
      raise exception ''collection allocations must equal collection amount'';
    end if;

    perform 1
    from public.accounts_receivable_items ar
    where ar.id in (
      select accounts_receivable_item_id
      from public.collection_allocations
      where treasury_operation_id = p_operation_id
    )
    order by ar.id
    for update;

    for v_alloc in
      select ca.*,
             ar.open_amount as ar_open,
             ar.direction   as ar_dir,
             ar.customer_id as ar_customer
      from public.collection_allocations ca
      join public.accounts_receivable_items ar
        on ar.id = ca.accounts_receivable_item_id
      where ca.treasury_operation_id = p_operation_id
      order by ca.accounts_receivable_item_id
    loop
      if v_alloc.ar_dir is distinct from ''AR_INCREASE'' then
        raise exception ''collections may only allocate to AR_INCREASE items'';
      end if;
      if v_alloc.ar_customer is distinct from v_op.counterparty_id then
        raise exception ''AR allocation customer mismatch'';
      end if;
      if v_alloc.allocated_amount > v_alloc.ar_open then
        raise exception ''allocation exceeds AR open amount (concurrency)'';
      end if;
    end loop;
  end if;

  -- Build journal
  v_source := case v_op.operation_type
    when ''PAYMENT''         then ''PAYMENT''   ::public.journal_source_type
    when ''COLLECTION''      then ''COLLECTION''::public.journal_source_type
    when ''TRANSFER''        then ''BANK''      ::public.journal_source_type
    when ''OPENING_BALANCE'' then ''SYSTEM''    ::public.journal_source_type
    when ''ADJUSTMENT''      then ''SYSTEM''    ::public.journal_source_type
  end;
  v_desc := left(
    v_op.operation_type::text || '' '' || v_op.internal_number || '' '' || v_op.description,
    500
  );

  insert into public.journal_entries (
    organization_id, entry_date, description,
    status, source_type, source_id, created_by
  ) values (
    v_op.organization_id, v_op.operation_date, v_desc,
    ''DRAFT'', v_source, p_operation_id, v_uid
  ) returning id into v_entry_id;

  begin
    if v_op.operation_type = ''PAYMENT'' then
      v_ap_coa := public.resolve_ap_account(v_op.organization_id);
      select ta.accounting_account_id into v_src_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = ''OUTFLOW'';
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number,
        account_id, description, debit, credit, counterparty_id
      ) values
        (v_op.organization_id, v_entry_id, 1,
         v_ap_coa, ''Pago proveedores'',  v_op.amount, 0,            v_op.counterparty_id),
        (v_op.organization_id, v_entry_id, 2,
         v_src_coa, ''Egreso tesorería'', 0,            v_op.amount, v_op.counterparty_id);

    elsif v_op.operation_type = ''COLLECTION'' then
      v_ar_coa := public.resolve_ar_account(v_op.organization_id);
      select ta.accounting_account_id into v_dst_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = ''INFLOW'';
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number,
        account_id, description, debit, credit, counterparty_id
      ) values
        (v_op.organization_id, v_entry_id, 1,
         v_dst_coa, ''Ingreso tesorería'', v_op.amount, 0,            v_op.counterparty_id),
        (v_op.organization_id, v_entry_id, 2,
         v_ar_coa,  ''Cobro clientes'',    0,            v_op.amount, v_op.counterparty_id);

    elsif v_op.operation_type = ''TRANSFER'' then
      select ta.accounting_account_id into v_src_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = ''OUTFLOW'';
      select ta.accounting_account_id into v_dst_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = ''INFLOW'';
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number,
        account_id, description, debit, credit
      ) values
        (v_op.organization_id, v_entry_id, 1, v_dst_coa, ''Transferencia destino'', v_op.amount, 0),
        (v_op.organization_id, v_entry_id, 2, v_src_coa, ''Transferencia origen'',  0, v_op.amount);

    elsif v_op.operation_type = ''OPENING_BALANCE'' then
      v_eq_coa := public.resolve_opening_equity_account(v_op.organization_id);
      select ta.accounting_account_id, l.direction into v_src_coa, v_desc
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id;
      if v_desc = ''INFLOW'' then
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_src_coa, ''Saldo inicial tesorería'',   v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_eq_coa,  ''Contrapartida saldo inicial'', 0, v_op.amount);
      else
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_eq_coa,  ''Contrapartida saldo inicial'', v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_src_coa, ''Saldo inicial tesorería'',   0, v_op.amount);
      end if;

    elsif v_op.operation_type = ''ADJUSTMENT'' then
      v_adj_coa := public.resolve_adjustment_offset_account(v_op.organization_id);
      select ta.accounting_account_id, l.direction into v_src_coa, v_desc
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id;
      if v_desc = ''INFLOW'' then
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_src_coa,  ''Ajuste tesorería'',             v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_adj_coa,  coalesce(v_op.reason,''Ajuste''), 0, v_op.amount);
      else
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_adj_coa,  coalesce(v_op.reason,''Ajuste''), v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_src_coa,  ''Ajuste tesorería'',             0, v_op.amount);
      end if;
    end if;

    perform public.post_journal_entry(v_entry_id);
  exception when others then
    delete from public.journal_entries where id = v_entry_id and status = ''DRAFT'';
    raise;
  end;

  perform set_config(''treasury.engine_write'', ''1'', true);

  -- Apply AP allocations
  if v_op.operation_type = ''PAYMENT'' then
    for v_alloc in
      select *
      from public.payment_allocations
      where treasury_operation_id = p_operation_id
      order by accounts_payable_item_id
    loop
      update public.accounts_payable_items
      set open_amount = open_amount - v_alloc.allocated_amount,
          status      = case
            when open_amount - v_alloc.allocated_amount = 0
              then ''PAID''::public.accounts_payable_status
            else ''PARTIALLY_PAID''::public.accounts_payable_status
          end,
          updated_at  = timezone(''utc'', now())
      where id = v_alloc.accounts_payable_item_id
        and open_amount >= v_alloc.allocated_amount;
      if not found then
        raise exception ''AP concurrent update failed'';
      end if;
    end loop;
  end if;

  -- Apply AR allocations
  if v_op.operation_type = ''COLLECTION'' then
    for v_alloc in
      select *
      from public.collection_allocations
      where treasury_operation_id = p_operation_id
      order by accounts_receivable_item_id
    loop
      update public.accounts_receivable_items
      set open_amount = open_amount - v_alloc.allocated_amount,
          status      = case
            when open_amount - v_alloc.allocated_amount = 0
              then ''COLLECTED''::public.accounts_receivable_status
            else ''PARTIALLY_COLLECTED''::public.accounts_receivable_status
          end,
          updated_at  = timezone(''utc'', now())
      where id = v_alloc.accounts_receivable_item_id
        and open_amount >= v_alloc.allocated_amount;
      if not found then
        raise exception ''AR concurrent update failed'';
      end if;
    end loop;
  end if;

  update public.treasury_operations
  set status            = ''POSTED'',
      accounting_status = ''POSTED'',
      journal_entry_id  = v_entry_id,
      posted_by         = v_uid,
      posted_at         = timezone(''utc'', now()),
      updated_at        = timezone(''utc'', now())
  where id = p_operation_id;

  return p_operation_id;
end;
$$","revoke all on function public.post_treasury_operation(uuid) from public, anon","grant execute on function public.post_treasury_operation(uuid) to authenticated","-- ---------------------------------------------------------------------------
-- 2. finalize_pos_sale
--    Orchestrates the FISCAL_AUTHORIZED → COMPLETED lifecycle.
--    Crash-safe: re-entrant on FINALIZING status (recovery path).
--    One DB transaction; no autonomous sub-transactions; no ARCA calls.
-- ---------------------------------------------------------------------------

create or replace function public.finalize_pos_sale(
  p_pos_sale_id     uuid,
  p_idempotency_key text default null  -- reserved; sale lock is the idempotency handle
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid           uuid := auth.uid();
  v_sale          public.pos_sales%rowtype;
  v_session       public.pos_sessions%rowtype;
  v_sales_doc     public.sales_documents%rowtype;
  v_fiscal_doc    public.fiscal_documents%rowtype;
  v_terminal      public.pos_terminals%rowtype;
  v_tender        record;
  v_line          record;
  v_ar_id         uuid;
  v_op_id         uuid;
  v_inv_op_id     uuid;
  v_num           text;
  v_inv_num       text;
  v_inv_line_no   int;
  v_tenders_total numeric(19,4);
  v_fiscal_net    numeric(19,4);
  v_cash_received numeric(19,4);
  v_change_given  numeric(19,4);
begin
  -- 1. Require authenticated caller
  if v_uid is null then raise exception ''authentication required''; end if;

  -- 2. Lock pos_sale row (prevents concurrent finalization of the same sale)
  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id
  for update;
  if not found then raise exception ''POS sale not found''; end if;

  -- 3. Idempotent: already COMPLETED
  if v_sale.status = ''COMPLETED'' then
    return v_sale.id;
  end if;

  -- 4+5. Status gate: FINALIZING = crash recovery (continue same checks)
  if v_sale.status not in (''FISCAL_AUTHORIZED'', ''FINALIZING'') then
    raise exception ''POS sale must be FISCAL_AUTHORIZED or FINALIZING (got %)'', v_sale.status;
  end if;

  -- 6. Feature + role gate
  perform public.pos_assert_feature(v_sale.organization_id);
  if not public.has_org_role(
    v_sale.organization_id,
    array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]
  ) then
    raise exception ''insufficient role to finalize POS sale'';
  end if;

  -- 7. Session must be OPEN
  select * into v_session
  from public.pos_sessions
  where id = v_sale.session_id
    and organization_id = v_sale.organization_id;
  if not found or v_session.status is distinct from ''OPEN'' then
    raise exception ''POS session must be OPEN to finalize sale'';
  end if;

  -- Load terminal (warehouse_id + branch_id used throughout)
  select * into v_terminal
  from public.pos_terminals
  where id              = v_sale.terminal_id
    and organization_id = v_sale.organization_id;
  if not found then raise exception ''POS terminal not found''; end if;

  -- 8. Sales document: must be commercially frozen and ARS
  select * into v_sales_doc
  from public.sales_documents
  where id              = v_sale.sales_document_id
    and organization_id = v_sale.organization_id;
  if not found then raise exception ''linked sales document not found''; end if;
  if not v_sales_doc.is_commercially_frozen then
    raise exception ''sales document must be commercially frozen before finalization'';
  end if;
  if v_sales_doc.currency_code is distinct from ''ARS'' then
    raise exception ''POS finalize requires ARS sales document (got %)'', v_sales_doc.currency_code;
  end if;

  -- 9. Fiscal document: must be AUTHORIZED, same org, same sales_document_id
  if v_sale.fiscal_document_id is null then
    raise exception ''POS sale has no linked fiscal document'';
  end if;
  select * into v_fiscal_doc
  from public.fiscal_documents
  where id              = v_sale.fiscal_document_id
    and organization_id = v_sale.organization_id;
  if not found then raise exception ''fiscal document not found''; end if;
  if v_fiscal_doc.status is distinct from ''AUTHORIZED'' then
    raise exception ''fiscal document must be AUTHORIZED (got %)'', v_fiscal_doc.status;
  end if;
  if v_fiscal_doc.sales_document_id is distinct from v_sale.sales_document_id then
    raise exception ''fiscal document sales_document_id does not match POS sale'';
  end if;

  -- 10. Total validations (exact numeric match)
  --     a) sales.total == fiscal net (taxed + exempt + untaxed); no VAT here
  v_fiscal_net := v_fiscal_doc.net_taxed_amount
                + v_fiscal_doc.net_exempt_amount
                + v_fiscal_doc.net_untaxed_amount;
  if v_sales_doc.total <> v_fiscal_net then
    raise exception ''POS_TOTAL_MISMATCH: sales.total % <> fiscal net %'',
      v_sales_doc.total, v_fiscal_net;
  end if;
  --     b) sum(DRAFT|POSTED tender amounts) == fiscal.total_amount (gross, incl. 21% VAT)
  select coalesce(sum(t.amount), 0) into v_tenders_total
  from public.pos_tenders t
  where t.pos_sale_id = p_pos_sale_id
    and t.status in (''DRAFT'', ''POSTED'');
  if v_tenders_total <> v_fiscal_doc.total_amount then
    raise exception ''POS_TOTAL_MISMATCH: tenders sum % <> fiscal.total_amount %'',
      v_tenders_total, v_fiscal_doc.total_amount;
  end if;

  -- 11. Transition to FINALIZING (or re-arm engine_write for crash recovery)
  perform set_config(''pos.engine_write'', ''1'', true);
  perform set_config(''treasury.pos_finalize'', ''1'', true);
  if v_sale.status = ''FISCAL_AUTHORIZED'' then
    update public.pos_sales
    set status     = ''FINALIZING'',
        updated_at = timezone(''utc'', now())
    where id = p_pos_sale_id;
  end if;

  -- 12. Ensure AR item from fiscal document; lock for update
  --     Note: ensure_ar_from_fiscal_document allows operator only when
  --     treasury.pos_finalize=1 and sale is FINALIZING.
  v_ar_id := public.ensure_ar_from_fiscal_document(v_sale.fiscal_document_id);
  perform 1 from public.accounts_receivable_items where id = v_ar_id for update;

  -- 13. Process each DRAFT tender in stable id order
  for v_tender in
    select t.*
    from public.pos_tenders t
    where t.pos_sale_id = p_pos_sale_id
      and t.status = ''DRAFT''
    order by t.id
  loop
    v_op_id := v_tender.treasury_operation_id;

    -- If tender already links a POSTED treasury op, just ensure tender is POSTED and move on
    if v_op_id is not null then
      if exists (
        select 1 from public.treasury_operations
        where id = v_op_id and status = ''POSTED''
      ) then
        perform set_config(''pos.engine_write'', ''1'', true);
        update public.pos_tenders
        set status = ''POSTED''
        where id = v_tender.id and status = ''DRAFT'';
        continue;
      end if;
      -- Op exists but not yet POSTED (very unlikely partial crash): fall through to post it
    else
      -- No treasury op yet → validate account, feature, then create
      perform public.pos_validate_tender_account(
        v_sale.organization_id,
        v_sale.terminal_id,
        v_tender.method,
        v_tender.treasury_account_id
      );
      -- Feature: CASH → cash feature; BANK_TRANSFER → banks; CARD/QR clearing → cash|banks
      perform public.treasury_assert_feature(v_sale.organization_id, array[''cash'',''banks'']);

      -- Check idempotency key before consuming a sequence number (crash-recovery path)
      select id into v_op_id
      from public.treasury_operations
      where organization_id = v_sale.organization_id
        and idempotency_key = ''pos-col:'' || v_tender.id::text;

      if v_op_id is null then
        v_num := public.next_treasury_operation_number(v_sale.organization_id, ''COLLECTION'');
        insert into public.treasury_operations (
          organization_id,
          branch_id,
          internal_number,
          operation_type,
          status,
          operation_date,
          counterparty_id,
          amount,
          currency_code,
          description,
          idempotency_key,
          created_by
        ) values (
          v_sale.organization_id,
          v_terminal.branch_id,
          v_num,
          ''COLLECTION'',
          ''DRAFT'',
          current_date,
          v_sales_doc.counterparty_id,
          v_tender.amount,
          ''ARS'',
          left(''Cobro POS '' || v_sales_doc.internal_number
               || '' '' || v_tender.method::text, 500),
          ''pos-col:'' || v_tender.id::text,
          v_uid
        )
        returning id into v_op_id;
      end if;
    end if;

    -- Idempotent INFLOW leg (line 1)
    insert into public.treasury_operation_legs (
      organization_id,
      treasury_operation_id,
      treasury_account_id,
      direction,
      amount,
      line_number
    ) values (
      v_sale.organization_id,
      v_op_id,
      v_tender.treasury_account_id,
      ''INFLOW'',
      v_tender.amount,
      1
    )
    on conflict (treasury_operation_id, line_number) do nothing;

    -- Idempotent collection allocation to the AR item
    perform set_config(''treasury.engine_write'', ''1'', true);
    insert into public.collection_allocations (
      organization_id,
      treasury_operation_id,
      accounts_receivable_item_id,
      allocated_amount
    ) values (
      v_sale.organization_id,
      v_op_id,
      v_ar_id,
      v_tender.amount
    )
    on conflict (treasury_operation_id, accounts_receivable_item_id) do nothing;

    -- Arm POS finalize context:
    --   treasury.pos_finalize = ''1''  → post_treasury_operation accepts COLLECTION
    --                                   without standard role gate (see role-check patch)
    --   treasury.engine_write = ''1''  → AR mutation guard bypass
    --   pos.engine_write      = ''1''  → pos_tenders / pos_sales guard bypass
    perform set_config(''treasury.pos_finalize'', ''1'', true);
    perform set_config(''treasury.engine_write'',  ''1'', true);
    perform set_config(''pos.engine_write'',        ''1'', true);

    -- Link tender.treasury_operation_id BEFORE posting so that the context
    -- validation in post_treasury_operation finds the DRAFT tender in the
    -- FINALIZING sale and approves the COLLECTION.
    if v_tender.treasury_operation_id is null then
      update public.pos_tenders
      set treasury_operation_id = v_op_id
      where id = v_tender.id;
    end if;

    -- Post the COLLECTION (builds journal, applies AR allocation; idempotent if already POSTED)
    perform public.post_treasury_operation(v_op_id);

    -- Mark tender POSTED
    perform set_config(''pos.engine_write'', ''1'', true);
    update public.pos_tenders
    set status = ''POSTED''
    where id = v_tender.id;

  end loop; -- end tender loop

  -- Optional cash rollup: populate pos_sales.cash_received / change_given from CASH tenders
  select
    coalesce(sum(coalesce(t.cash_received, t.amount)), 0),
    coalesce(sum(coalesce(t.change_given,  0)),         0)
  into v_cash_received, v_change_given
  from public.pos_tenders t
  where t.pos_sale_id = p_pos_sale_id
    and t.method      = ''CASH''
    and t.status      = ''POSTED'';

  -- 14. Inventory: ISSUE for STOCK_ITEM lines with ACTIVE reservations
  --     Skipped entirely when inventory_operation_id is already set (crash recovery).
  if v_sale.inventory_operation_id is null then

    if exists (
      select 1
      from public.sales_document_lines sdl
      join public.products pr
        on pr.id              = sdl.product_id
       and pr.organization_id = sdl.organization_id
      join public.inventory_reservations ir
        on ir.sales_document_line_id = sdl.id
       and ir.status in (''ACTIVE'', ''CONSUMED'')
      where sdl.sales_document_id = v_sale.sales_document_id
        and pr.product_type        = ''STOCK_ITEM''
    ) then

      -- Idempotency: re-use existing op if crash happened between create and link
      select id into v_inv_op_id
      from public.inventory_operations
      where organization_id = v_sale.organization_id
        and idempotency_key = ''pos-issue:'' || p_pos_sale_id::text;

      if v_inv_op_id is null then
        v_inv_num := public.next_inventory_operation_number(v_sale.organization_id, ''ISSUE'');
        perform set_config(''inventory.engine_write'', ''1'', true);
        insert into public.inventory_operations (
          organization_id,
          internal_number,
          operation_type,
          status,
          operation_date,
          warehouse_id,
          source_sales_document_id,
          description,
          idempotency_key,
          created_by
        ) values (
          v_sale.organization_id,
          v_inv_num,
          ''ISSUE'',
          ''DRAFT'',
          current_date,
          v_terminal.warehouse_id,
          v_sale.sales_document_id,
          left(''POS issue '' || v_inv_num || '' venta '' || v_sales_doc.internal_number, 500),
          ''pos-issue:'' || p_pos_sale_id::text,
          v_uid
        )
        returning id into v_inv_op_id;
      end if;

      perform set_config(''inventory.engine_write'', ''1'', true);

      -- Starting line_number (allows re-entry without duplicate line conflicts)
      v_inv_line_no := coalesce((
        select max(line_number)
        from public.inventory_operation_lines
        where inventory_operation_id = v_inv_op_id
      ), 0);

      -- Insert OUT lines for each ACTIVE reservation (CONSUMED = already issued, skip)
      for v_line in
        select
          sdl.id            as sdl_id,
          sdl.quantity,
          pr.id             as product_id,
          pr.base_unit_code,
          ir.id             as reservation_id,
          ir.warehouse_id
        from public.sales_document_lines sdl
        join public.products pr
          on pr.id              = sdl.product_id
         and pr.organization_id = sdl.organization_id
        join public.inventory_reservations ir
          on ir.sales_document_line_id = sdl.id
         and ir.status = ''ACTIVE''
        where sdl.sales_document_id = v_sale.sales_document_id
          and pr.product_type        = ''STOCK_ITEM''
        order by sdl.line_number, ir.id
      loop
        -- Skip if this reservation already has a line in this operation (idempotent)
        if exists (
          select 1 from public.inventory_operation_lines
          where inventory_operation_id = v_inv_op_id
            and reservation_id         = v_line.reservation_id
        ) then
          continue;
        end if;

        v_inv_line_no := v_inv_line_no + 1;

        insert into public.inventory_operation_lines (
          organization_id,
          inventory_operation_id,
          line_number,
          product_id,
          warehouse_id,
          direction,
          quantity,
          unit_code,
          reservation_id,
          source_sales_line_id
        ) values (
          v_sale.organization_id,
          v_inv_op_id,
          v_inv_line_no,
          v_line.product_id,
          v_line.warehouse_id,      -- reservation''s warehouse (where stock is reserved)
          ''OUT'',
          v_line.quantity,
          v_line.base_unit_code,    -- product base unit (matches inventory ledger)
          v_line.reservation_id,
          v_line.sdl_id
        );
      end loop;

      -- Post the ISSUE operation (idempotent; updates stock state, cost state, ledger)
      perform public.post_inventory_operation(v_inv_op_id);

      -- Link inventory_operation_id to the POS sale
      perform set_config(''pos.engine_write'', ''1'', true);
      update public.pos_sales
      set inventory_operation_id = v_inv_op_id,
          updated_at              = timezone(''utc'', now())
      where id = p_pos_sale_id;

    end if; -- has stock items
  end if;   -- inventory_operation_id is null

  -- 15. Mark COMPLETED
  --     If all tenders were already POSTED and inventory done mid-way, we still
  --     reach here and flip to COMPLETED.
  perform set_config(''pos.engine_write'', ''1'', true);
  update public.pos_sales
  set status       = ''COMPLETED'',
      completed_at = timezone(''utc'', now()),
      completed_by = v_uid,
      -- cash_received / change_given: both set or both null (constraint)
      cash_received = case when v_cash_received > 0 then v_cash_received else null end,
      change_given  = case when v_cash_received > 0 then v_change_given  else null end,
      updated_at    = timezone(''utc'', now())
  where id = p_pos_sale_id;

  -- 16. Return sale id
  return p_pos_sale_id;
end;
$$","revoke all on function public.finalize_pos_sale(uuid, text) from public, anon","grant execute on function public.finalize_pos_sale(uuid, text) to authenticated","comment on function public.finalize_pos_sale(uuid, text) is
  ''Phase 9 — POS sale finalization (FISCAL_AUTHORIZED → COMPLETED). ''
  ''Idempotent; crash-safe via FINALIZING recovery path. ''
  ''Intentional client RPC: authenticated + roles owner/admin/manager/operator.''","-- ---------------------------------------------------------------------------
-- 3. pos_test_fixture_mark_fiscal_authorized
--    Staging / CI test fixture only. Marks a fiscal document AUTHORIZED and
--    the linked sales order INVOICED, bypassing the ARCA WSFE round-trip.
--    Mirrors the success path of complete_fiscal_authorization (APPROVED).
--    NEVER grant to authenticated or anon.
-- ---------------------------------------------------------------------------

create or replace function public.pos_test_fixture_mark_fiscal_authorized(
  p_fiscal_document_id uuid,
  p_cae                text default ''TESTCAE0001'',
  p_cae_expiration     date default (current_date + 30)
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_doc public.fiscal_documents%rowtype;
begin
  -- Only the trusted server adapter (service_role JWT) may call this fixture.
  -- fiscal_assert_service_role checks auth.role() = ''service_role''.
  perform public.fiscal_assert_service_role();

  select * into v_doc
  from public.fiscal_documents
  where id = p_fiscal_document_id
  for update;
  if not found then raise exception ''fiscal document not found''; end if;

  -- Idempotent: already AUTHORIZED
  if v_doc.status = ''AUTHORIZED'' then
    return p_fiscal_document_id;
  end if;

  if v_doc.status not in (''DRAFT'', ''READY_TO_AUTHORIZE'', ''AUTHORIZING'') then
    raise exception
      ''fixture requires DRAFT / READY_TO_AUTHORIZE / AUTHORIZING (got %)'',
      v_doc.status;
  end if;

  perform set_config(''fiscal.engine_write'', ''1'', true);
  perform set_config(''sales.engine_write'', ''1'', true);

  update public.fiscal_documents
  set status              = ''AUTHORIZED'',
      cae                 = p_cae,
      cae_expiration_date = p_cae_expiration,
      authorized_at       = timezone(''utc'', now()),
      accounting_status   = ''PENDING'',
      arca_result         = ''{}''::jsonb,
      arca_observations   = ''[]''::jsonb,
      updated_at          = timezone(''utc'', now())
  where id = p_fiscal_document_id;

  if v_doc.sales_document_id is not null and v_doc.relationship_type is null then
    update public.sales_documents
    set status                      = ''INVOICED'',
        invoiced_fiscal_document_id = v_doc.id,
        updated_at                  = timezone(''utc'', now())
    where id              = v_doc.sales_document_id
      and organization_id = v_doc.organization_id
      and status          = ''READY_TO_INVOICE'';
  end if;

  return p_fiscal_document_id;
end;
$$","-- NEVER expose to authenticated users — service_role (CI / staging adapter) only
revoke all on function public.pos_test_fixture_mark_fiscal_authorized(uuid, text, date)
  from public, anon, authenticated","grant execute on function public.pos_test_fixture_mark_fiscal_authorized(uuid, text, date)
  to service_role","comment on function public.pos_test_fixture_mark_fiscal_authorized(uuid, text, date) is
  ''Phase 9 staging fixture ONLY — marks fiscal document AUTHORIZED without ARCA. ''
  ''service_role only. Do NOT use in production.''","-- ---------------------------------------------------------------------------
-- Patch ensure_ar_from_fiscal_document: allow operator during POS finalize only
-- (treasury.pos_finalize=1). Does NOT broaden generic AR creation for cashiers.
-- ---------------------------------------------------------------------------
create or replace function public.ensure_ar_from_fiscal_document(p_fiscal_document_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.fiscal_documents%rowtype;
  v_existing uuid;
  v_direction public.accounts_receivable_direction;
  v_id uuid;
  v_dtype_kind text;
begin
  if v_uid is null then raise exception ''authentication required''; end if;

  select * into v_doc from public.fiscal_documents where id = p_fiscal_document_id for update;
  if not found then raise exception ''fiscal document not found''; end if;

  if not public.is_org_member(v_doc.organization_id) then
    raise exception ''not a member of organization'';
  end if;

  if current_setting(''treasury.pos_finalize'', true) = ''1'' then
    if not public.has_org_role(
      v_doc.organization_id,
      array[''owner'',''admin'',''accountant'',''manager'',''operator'']::public.member_role[]
    ) then
      raise exception ''insufficient role to create receivable (POS finalize)'';
    end if;
    if not exists (
      select 1 from public.pos_sales s
      where s.fiscal_document_id = p_fiscal_document_id
        and s.status = ''FINALIZING''
    ) then
      raise exception ''POS finalize AR context invalid'';
    end if;
  elsif not public.has_org_role(
    v_doc.organization_id,
    array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
  ) then
    raise exception ''insufficient role to create receivable'';
  end if;

  select id into v_existing
  from public.accounts_receivable_items
  where fiscal_document_id = p_fiscal_document_id;
  if v_existing is not null then
    return v_existing;
  end if;

  if v_doc.status is distinct from ''AUTHORIZED'' then
    raise exception ''only AUTHORIZED fiscal documents may create AR items'';
  end if;

  if v_doc.currency_code not in (''ARS'', ''PES'') then
    raise exception ''Phase 7 MVP AR requires ARS/PES fiscal documents'';
  end if;

  if v_doc.total_amount <= 0 then
    raise exception ''fiscal document total must be positive'';
  end if;

  if v_doc.relationship_type = ''CREDIT_NOTE'' then
    v_direction := ''AR_DECREASE'';
  elsif v_doc.relationship_type = ''DEBIT_NOTE'' then
    v_direction := ''AR_INCREASE'';
  else
    select fdt.operation_kind::text into v_dtype_kind
    from public.fiscal_document_types fdt
    where fdt.id = v_doc.document_type_id;
    if v_dtype_kind = ''CREDIT_NOTE'' then
      v_direction := ''AR_DECREASE'';
    else
      v_direction := ''AR_INCREASE'';
    end if;
  end if;

  perform set_config(''treasury.engine_write'', ''1'', true);

  insert into public.accounts_receivable_items (
    organization_id, customer_id, source_type, source_id, fiscal_document_id,
    direction, original_amount, open_amount, currency_code, due_date, status
  ) values (
    v_doc.organization_id, v_doc.counterparty_id, ''FISCAL_DOCUMENT'', v_doc.id, v_doc.id,
    v_direction, v_doc.total_amount, v_doc.total_amount, ''ARS'', null, ''OPEN''
  )
  on conflict (fiscal_document_id) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.accounts_receivable_items where fiscal_document_id = p_fiscal_document_id;
  end if;

  return v_id;
end;
$$","revoke all on function public.ensure_ar_from_fiscal_document(uuid) from public, anon","grant execute on function public.ensure_ar_from_fiscal_document(uuid) to authenticated"}', 'phase9_pos_finalize'),
	('20260901160000', '{"-- Phase 9 advisor hardening — FK covering indexes

create index if not exists pos_terminals_default_customer_idx
  on public.pos_terminals (organization_id, default_customer_id)
  where default_customer_id is not null","create index if not exists pos_terminals_org_fiscal_pos_idx
  on public.pos_terminals (organization_id, fiscal_point_of_sale_id)
  where fiscal_point_of_sale_id is not null","create index if not exists pos_sessions_org_terminal_idx
  on public.pos_sessions (organization_id, terminal_id)","create index if not exists pos_sales_org_terminal_idx
  on public.pos_sales (organization_id, terminal_id)","create index if not exists pos_sales_org_session_idx
  on public.pos_sales (organization_id, session_id)","create index if not exists pos_sales_org_sales_doc_idx
  on public.pos_sales (organization_id, sales_document_id)","create index if not exists pos_tenders_org_sale_idx
  on public.pos_tenders (organization_id, pos_sale_id)","create index if not exists pos_tenders_org_account_idx
  on public.pos_tenders (organization_id, treasury_account_id)","create index if not exists pos_tta_org_terminal_idx
  on public.pos_terminal_tender_accounts (organization_id, terminal_id)","create index if not exists pos_tta_org_account_idx
  on public.pos_terminal_tender_accounts (organization_id, treasury_account_id)"}', 'phase9_pos_advisor_hardening'),
	('20260901170000', '{"-- Phase 9: allow SALES_ORDER status INVOICED (Phase 5 added enum; trigger never updated)

create or replace function public.validate_sales_document_status_for_type()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if new.document_type = ''QUOTE'' then
    if new.status not in (''DRAFT'', ''SENT'', ''ACCEPTED'', ''REJECTED'', ''CANCELLED'', ''CONVERTED'') then
      raise exception ''invalid quote status: %'', new.status;
    end if;
  elsif new.document_type = ''SALES_ORDER'' then
    if new.status not in (
      ''DRAFT'', ''CONFIRMED'', ''READY_TO_INVOICE'', ''INVOICED'', ''CANCELLED''
    ) then
      raise exception ''invalid sales order status: %'', new.status;
    end if;
  end if;
  return new;
end;
$$","comment on function public.validate_sales_document_status_for_type() is
  ''Phase 9: includes INVOICED for SALES_ORDER (Phase 5 fiscal handoff).''"}', 'phase9_sales_invoiced_status_fix'),
	('20260901180000', '{"-- Phase 9: remaining FK covering indexes (advisor)

create index if not exists pos_sales_created_by_idx
  on public.pos_sales (created_by) where created_by is not null","create index if not exists pos_sales_completed_by_idx
  on public.pos_sales (completed_by) where completed_by is not null","create index if not exists pos_sessions_cashier_idx
  on public.pos_sessions (cashier_id)","create index if not exists pos_settings_walk_in_covering_idx
  on public.pos_settings (organization_id, default_walk_in_customer_id)"}', 'phase9_pos_fk_indexes'),
	('20261001270000', '{"-- Phase 10 hardening: reuse fixture counterparty (idempotent CN/DN fixtures)

create or replace function public.tax_test_fixture_authorized_fiscal(
  p_organization_id uuid,
  p_issue_date date,
  p_fiscal_environment public.fiscal_environment,
  p_vat_amount numeric,
  p_net_taxed numeric default null,
  p_counterparty_id uuid default null,
  p_point_of_sale_id uuid default null,
  p_document_type_internal_code text default ''INVOICE_A''
)
returns uuid
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_dtype public.fiscal_document_types%rowtype;
  v_doc_id uuid;
  v_net numeric(19,4) := coalesce(p_net_taxed, round(p_vat_amount / 0.21, 4));
  v_cp uuid := p_counterparty_id;
  v_pos uuid := p_point_of_sale_id;
  v_pos_n int;
  v_rule uuid;
  v_fixture_tax_id text := ''20111111112'';
begin
  if auth.role() is distinct from ''service_role'' then
    raise exception ''tax_test_fixture_authorized_fiscal is service_role only'';
  end if;

  select * into v_dtype
  from public.fiscal_document_types
  where internal_code = coalesce(p_document_type_internal_code, ''INVOICE_A'')
  limit 1;
  if not found then
    select * into v_dtype from public.fiscal_document_types
    where operation_kind = ''INVOICE'' limit 1;
  end if;
  if v_dtype.id is null then
    raise exception ''TAX_FIXTURE_NO_DOCUMENT_TYPE'';
  end if;

  if v_cp is null then
    select c.id into v_cp
    from public.counterparties c
    where c.organization_id = p_organization_id
      and c.tax_id_normalized = public.normalize_counterparty_tax_id(''CUIT'', v_fixture_tax_id)
    limit 1;

    if v_cp is null then
      insert into public.counterparties (
        organization_id, legal_name, tax_id_type, tax_id, is_active
      ) values (
        p_organization_id, ''Tax Fixture Customer'', ''CUIT'', v_fixture_tax_id, true
      )
      returning id into v_cp;
    end if;

    insert into public.counterparty_roles (organization_id, counterparty_id, role)
    values (p_organization_id, v_cp, ''CUSTOMER'')
    on conflict do nothing;
  end if;

  if v_pos is null then
    insert into public.fiscal_points_of_sale (
      organization_id, environment, arca_point_of_sale, description, is_active
    ) values (
      p_organization_id, p_fiscal_environment, 99, ''Tax fixture POS'', true
    )
    on conflict (organization_id, environment, arca_point_of_sale) do update
      set description = excluded.description
    returning id into v_pos;
    if v_pos is null then
      select id into v_pos from public.fiscal_points_of_sale
      where organization_id = p_organization_id
        and environment = p_fiscal_environment
        and arca_point_of_sale = 99;
    end if;
  end if;

  select arca_point_of_sale into v_pos_n
  from public.fiscal_points_of_sale where id = v_pos;

  select id into v_rule
  from public.fiscal_rule_versions
  where organization_id = p_organization_id
    and status = ''ACTIVE''
  order by effective_from desc
  limit 1;
  if v_rule is null then
    insert into public.fiscal_rule_versions (
      organization_id, code, version, effective_from, source_reference, status, rules
    ) values (
      p_organization_id, ''TAX_FIXTURE'', 1, ''2020-01-01'',
      ''Phase10 staging fixture'', ''ACTIVE'', ''{}''::jsonb
    )
    returning id into v_rule;
  end if;

  perform set_config(''fiscal.engine_write'', ''1'', true);

  insert into public.fiscal_documents (
    organization_id, document_type_id, document_class, arca_cbte_tipo,
    point_of_sale_id, arca_point_of_sale, document_number,
    status, fiscal_environment, issue_date, counterparty_id,
    currency_code, currency_rate,
    net_taxed_amount, net_exempt_amount, net_untaxed_amount,
    vat_amount, other_taxes_amount, total_amount,
    cae, authorized_at, fiscal_rule_version_id, idempotency_key
  ) values (
    p_organization_id, v_dtype.id, v_dtype.document_class, v_dtype.arca_cbte_tipo,
    v_pos, v_pos_n, (extract(epoch from clock_timestamp()) * 1000)::bigint,
    ''AUTHORIZED'', p_fiscal_environment, p_issue_date, v_cp,
    ''PES'', 1,
    v_net, 0, 0,
    p_vat_amount, 0, v_net + p_vat_amount,
    ''TESTCAE'' || substr(replace(gen_random_uuid()::text, ''-'', ''''), 1, 10),
    timezone(''utc'', now()), v_rule, ''tax-fix-fd-'' || gen_random_uuid()::text
  )
  returning id into v_doc_id;

  insert into public.fiscal_tax_summaries (
    organization_id, fiscal_document_id, summary_kind, code, base_amount, rate, amount
  ) values (
    p_organization_id, v_doc_id, ''IVA'', ''5'', v_net, 21.0000, p_vat_amount
  );

  return v_doc_id;
end;
$$","revoke all on function public.tax_test_fixture_authorized_fiscal(uuid, date, public.fiscal_environment, numeric, numeric, uuid, uuid, text)
  from public, anon, authenticated","grant execute on function public.tax_test_fixture_authorized_fiscal(uuid, date, public.fiscal_environment, numeric, numeric, uuid, uuid, text)
  to service_role"}', 'phase10_hardening_fixture_counterparty_reuse'),
	('20261001280000', '{"-- Phase 10 hardening: cover composite rectification FK for Performance Advisor

create index if not exists tax_filing_supersedes_org_idx
  on public.tax_filing_records (organization_id, supersedes_filing_id)"}', 'phase10_hardening_filing_fk_index'),
	('20261101100000', '{"-- Phase 11: analytics metric registry (GLOBAL catalog)
-- STAGING ONLY — additive. Do not rewrite Phase 1–10 migrations.
-- Money / units: never FLOAT. Metric formulas live in reviewed server code keyed by code + calculation_version.

do $$ begin
  create type public.analytics_metric_unit_type as enum (
    ''CURRENCY'', ''COUNT'', ''PERCENT'', ''QUANTITY'', ''DAYS''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.analytics_metric_domain as enum (
    ''EXECUTIVE'',
    ''FINANCIAL'',
    ''SALES'',
    ''PURCHASES'',
    ''TREASURY'',
    ''AR'',
    ''AP'',
    ''INVENTORY'',
    ''POS'',
    ''TAX'',
    ''ACCOUNTING''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.analytics_metric_comparison as enum (
    ''PREV_PERIOD'', ''PREV_YEAR'', ''NONE''
  );
exception when duplicate_object then null;
end $$","create table if not exists public.analytics_metric_definitions (
  code text primary key
    check (char_length(code) between 2 and 64 and code = upper(code)),
  name_business text not null check (char_length(trim(name_business)) >= 1),
  name_accountant text not null check (char_length(trim(name_accountant)) >= 1),
  description text not null default '''',
  domain public.analytics_metric_domain not null,
  unit_type public.analytics_metric_unit_type not null,
  calculation_version int not null default 1 check (calculation_version >= 1),
  default_comparison public.analytics_metric_comparison not null default ''PREV_PERIOD'',
  required_feature text,
  required_permission text,
  active boolean not null default true,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now())
)","create index if not exists analytics_metric_definitions_domain_idx
  on public.analytics_metric_definitions (domain, active)","create index if not exists analytics_metric_definitions_feature_idx
  on public.analytics_metric_definitions (required_feature)
  where required_feature is not null","drop trigger if exists analytics_metric_definitions_set_updated_at
  on public.analytics_metric_definitions","create trigger analytics_metric_definitions_set_updated_at
before update on public.analytics_metric_definitions
for each row execute function public.set_updated_at()","comment on table public.analytics_metric_definitions is
  ''GLOBAL controlled metric registry. System-seeded only; no user SQL / no organization_id.''","-- Seed MVP metrics (calculation_version = 1)
insert into public.analytics_metric_definitions (
  code, name_business, name_accountant, description, domain, unit_type,
  calculation_version, default_comparison, required_feature, required_permission, active
) values
  (
    ''SALES_FISCAL_GROSS_AUTHORIZED'',
    ''Ventas facturadas brutas autorizadas'',
    ''Fiscal AUTHORIZED total_amount × economic sign'',
    ''Sum fiscal_documents.total_amount with INVOICE/DN +1, CN -1; status=AUTHORIZED; issue_date in period.'',
    ''SALES'', ''CURRENCY'', 1, ''PREV_PERIOD'', ''fiscal_invoicing'', null, true
  ),
  (
    ''SALES_FISCAL_NET_AUTHORIZED'',
    ''Ventas facturadas netas autorizadas'',
    ''Fiscal AUTHORIZED net bases × economic sign'',
    ''Sum (net_taxed+net_exempt+net_untaxed) × economic sign; status=AUTHORIZED; issue_date in period.'',
    ''SALES'', ''CURRENCY'', 1, ''PREV_PERIOD'', ''fiscal_invoicing'', null, true
  ),
  (
    ''SALES_COMMERCIAL_CONFIRMED'',
    ''Ventas comerciales confirmadas'',
    ''Commercial confirmed/invoiced pipeline (secondary)'',
    ''Sales documents in confirmed/invoiced pipeline — not default Ventas KPI.'',
    ''SALES'', ''CURRENCY'', 1, ''PREV_PERIOD'', ''sales'', null, true
  ),
  (
    ''MANAGEMENT_GROSS_RESULT'',
    ''Resultado bruto gerencial'',
    ''Revenue − COGS (management P&L)'',
    ''From analytics_management_pnl: revenue − cogs. Subject to mapping review.'',
    ''ACCOUNTING'', ''CURRENCY'', 1, ''PREV_PERIOD'', ''accounting'', null, true
  ),
  (
    ''GROSS_MARGIN'',
    ''Margen bruto'',
    ''Fiscal net sales − inventory COGS'',
    ''Authorized fiscal net basis for stocked goods minus Phase 8 COGS only.'',
    ''SALES'', ''CURRENCY'', 1, ''PREV_PERIOD'', ''inventory'', null, true
  ),
  (
    ''GROSS_MARGIN_PCT'',
    ''Margen bruto %'',
    ''Gross margin / sales base'',
    ''Server percent; zero denominator → Sin base comparable.'',
    ''SALES'', ''PERCENT'', 1, ''PREV_PERIOD'', ''inventory'', null, true
  ),
  (
    ''COGS_INVENTORY'',
    ''Costo de mercadería vendida'',
    ''Inventory issue COGS in period'',
    ''Phase 8 inventory COGS linked to completed/authorized sales basis.'',
    ''INVENTORY'', ''CURRENCY'', 1, ''PREV_PERIOD'', ''inventory'', null, true
  ),
  (
    ''CASH_INTERNAL'',
    ''Saldo de caja interno'',
    ''Sum treasury_account_balance(CASH)'',
    ''Internal cash from POSTED treasury legs only — not bank-confirmed.'',
    ''TREASURY'', ''CURRENCY'', 1, ''NONE'', ''cash'', null, true
  ),
  (
    ''BANK_INTERNAL'',
    ''Saldo bancario interno'',
    ''Sum treasury_account_balance(BANK)'',
    ''Internal bank books balance — never labeled bank-confirmed.'',
    ''TREASURY'', ''CURRENCY'', 1, ''NONE'', ''banks'', null, true
  ),
  (
    ''CLEARING_PENDING'',
    ''Tarjetas/QR pendientes de acreditación'',
    ''Sum treasury_account_balance(CLEARING)'',
    ''Processor clearing receivable; separate from cash/bank.'',
    ''TREASURY'', ''CURRENCY'', 1, ''NONE'', ''pos'', null, true
  ),
  (
    ''AR_OPEN'',
    ''Cuentas por cobrar abiertas'',
    ''AR open_amount OPEN+PARTIALLY_COLLECTED'',
    ''Signed by AR direction; open_amount > 0.'',
    ''AR'', ''CURRENCY'', 1, ''NONE'', ''sales'', null, true
  ),
  (
    ''AP_OPEN'',
    ''Cuentas por pagar abiertas'',
    ''AP open_amount OPEN+PARTIALLY_PAID'',
    ''Signed by AP direction; open_amount > 0.'',
    ''AP'', ''CURRENCY'', 1, ''NONE'', ''purchases'', null, true
  ),
  (
    ''INVENTORY_VALUE'',
    ''Inventario valorizado'',
    ''Sum inventory_cost_state.inventory_value'',
    ''Engine projection valuation at org+product.'',
    ''INVENTORY'', ''CURRENCY'', 1, ''NONE'', ''inventory'', null, true
  ),
  (
    ''TAX_IVA_SALDO_ESTIMADO'',
    ''IVA — saldo estimado'',
    ''tax_determinations.totals_snapshot.saldo_estimado'',
    ''Read-only Phase 10 estimate. Label: Saldo estimado según Contabilium — never definitive DDJJ.'',
    ''TAX'', ''CURRENCY'', 1, ''NONE'', ''taxes'', null, true
  ),
  (
    ''TAX_OBLIGATIONS_NEAR'',
    ''Obligaciones próximas'',
    ''Open tax obligations near due'',
    ''Count/list near-due tax_obligations (config days).'',
    ''TAX'', ''COUNT'', 1, ''NONE'', ''taxes'', null, true
  ),
  (
    ''COLLECTIONS_POSTED'',
    ''Cobros reales'',
    ''Posted COLLECTION treasury ops in period'',
    ''Sum amount of treasury_operations type COLLECTION status POSTED by operation_date.'',
    ''TREASURY'', ''CURRENCY'', 1, ''PREV_PERIOD'', ''cash'', null, true
  ),
  (
    ''PAYMENTS_POSTED'',
    ''Pagos reales'',
    ''Posted PAYMENT treasury ops in period'',
    ''Sum amount of treasury_operations type PAYMENT status POSTED by operation_date.'',
    ''TREASURY'', ''CURRENCY'', 1, ''PREV_PERIOD'', ''cash'', null, true
  ),
  (
    ''ACCT_REVENUE'',
    ''Ingresos contables'',
    ''GL REVENUE credit−debit POSTED+REVERSED'',
    ''Economic journal scope status IN (POSTED, REVERSED).'',
    ''ACCOUNTING'', ''CURRENCY'', 1, ''PREV_PERIOD'', ''accounting'', null, true
  ),
  (
    ''ACCT_RESULT_EST'',
    ''Resultado estimado (gerencial)'',
    ''Management P&L net'',
    ''analytics_management_pnl.management_result — gerencial interno.'',
    ''ACCOUNTING'', ''CURRENCY'', 1, ''PREV_PERIOD'', ''accounting'', null, true
  ),
  (
    ''POS_COMPLETED_COUNT'',
    ''Ventas POS completadas'',
    ''pos_sales status=COMPLETED count'',
    ''Completed POS sales in period (completed_at / sale date).'',
    ''POS'', ''COUNT'', 1, ''PREV_PERIOD'', ''pos'', null, true
  ),
  (
    ''PURCHASES_POSTED'',
    ''Compras contabilizadas'',
    ''purchase_documents status=POSTED total signed'',
    ''POSTED purchases in period by accounting_date; CN/DN as separate docs.'',
    ''PURCHASES'', ''CURRENCY'', 1, ''PREV_PERIOD'', ''purchases'', null, true
  )
on conflict (code) do update set
  name_business = excluded.name_business,
  name_accountant = excluded.name_accountant,
  description = excluded.description,
  domain = excluded.domain,
  unit_type = excluded.unit_type,
  calculation_version = excluded.calculation_version,
  default_comparison = excluded.default_comparison,
  required_feature = excluded.required_feature,
  required_permission = excluded.required_permission,
  active = excluded.active,
  updated_at = timezone(''utc'', now())","alter table public.analytics_metric_definitions enable row level security","drop policy if exists analytics_metric_definitions_select on public.analytics_metric_definitions","create policy analytics_metric_definitions_select
  on public.analytics_metric_definitions
  for select to authenticated
  using (true)","-- No insert/update/delete for authenticated (service_role bypasses RLS)
revoke all on table public.analytics_metric_definitions from public, anon","grant select on table public.analytics_metric_definitions to authenticated","grant all on table public.analytics_metric_definitions to service_role"}', 'phase11_metric_registry'),
	('20261101110000', '{"-- Phase 11: saved_reports (org-scoped named report configs)
-- Filters/columns/sort are allowlisted JSON only — never SQL fragments.

do $$ begin
  create type public.saved_report_visibility as enum (''PRIVATE'', ''ORGANIZATION'');
exception when duplicate_object then null;
end $$","create table if not exists public.saved_reports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  owner_user_id uuid not null references auth.users (id) on delete cascade,
  report_code text not null check (char_length(trim(report_code)) >= 2),
  name text not null check (char_length(trim(name)) between 1 and 120),
  filters_json jsonb not null default ''{}''::jsonb,
  columns_json jsonb not null default ''[]''::jsonb,
  sort_json jsonb not null default ''[]''::jsonb,
  visibility public.saved_report_visibility not null default ''PRIVATE'',
  calculation_version int not null default 1 check (calculation_version >= 1),
  active boolean not null default true,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint saved_reports_org_id_unique unique (organization_id, id),
  constraint saved_reports_org_owner_name_unique unique (organization_id, owner_user_id, name)
)","create index if not exists saved_reports_org_idx
  on public.saved_reports (organization_id, active)","create index if not exists saved_reports_owner_idx
  on public.saved_reports (owner_user_id)","create index if not exists saved_reports_org_report_code_idx
  on public.saved_reports (organization_id, report_code)","create index if not exists saved_reports_org_owner_idx
  on public.saved_reports (organization_id, owner_user_id)","drop trigger if exists saved_reports_set_updated_at on public.saved_reports","create trigger saved_reports_set_updated_at
before update on public.saved_reports
for each row execute function public.set_updated_at()","comment on table public.saved_reports is
  ''Named filter/column/sort configs against approved report_code. No user SQL.''","alter table public.saved_reports enable row level security","-- PRIVATE: owner only; ORGANIZATION: same-org members
drop policy if exists saved_reports_select on public.saved_reports","create policy saved_reports_select on public.saved_reports
  for select to authenticated
  using (
    public.is_org_member(organization_id)
    and (
      visibility = ''ORGANIZATION''
      or owner_user_id = auth.uid()
    )
  )","drop policy if exists saved_reports_insert on public.saved_reports","create policy saved_reports_insert on public.saved_reports
  for insert to authenticated
  with check (
    public.is_org_member(organization_id)
    and owner_user_id = auth.uid()
  )","drop policy if exists saved_reports_update on public.saved_reports","create policy saved_reports_update on public.saved_reports
  for update to authenticated
  using (owner_user_id = auth.uid() and public.is_org_member(organization_id))
  with check (owner_user_id = auth.uid() and public.is_org_member(organization_id))","drop policy if exists saved_reports_delete on public.saved_reports","create policy saved_reports_delete on public.saved_reports
  for delete to authenticated
  using (owner_user_id = auth.uid() and public.is_org_member(organization_id))","revoke all on table public.saved_reports from public, anon","grant select, insert, update, delete on table public.saved_reports to authenticated","grant all on table public.saved_reports to service_role"}', 'phase11_saved_reports'),
	('20261101120000', '{"-- Phase 11: analytics alerts + inventory thresholds
-- Attention Center events are derived; never rewrite source economics.

do $$ begin
  create type public.analytics_alert_severity as enum (''INFO'', ''WARNING'', ''CRITICAL'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.analytics_alert_status as enum (''OPEN'', ''ACKNOWLEDGED'', ''RESOLVED'');
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.analytics_alert_domain as enum (
    ''FINANCE'', ''SALES'', ''PURCHASES'', ''INVENTORY'', ''POS'', ''FISCAL'', ''TAX'', ''ACCOUNTING'', ''TREASURY''
  );
exception when duplicate_object then null;
end $$","-- ---------------------------------------------------------------------------
-- analytics_alert_settings
-- ---------------------------------------------------------------------------

create table if not exists public.analytics_alert_settings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  rule_code text not null check (char_length(trim(rule_code)) >= 2),
  enabled boolean not null default true,
  threshold_json jsonb not null default ''{}''::jsonb,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint analytics_alert_settings_org_id_unique unique (organization_id, id),
  constraint analytics_alert_settings_org_rule_unique unique (organization_id, rule_code)
)","create index if not exists analytics_alert_settings_org_idx
  on public.analytics_alert_settings (organization_id, enabled)","drop trigger if exists analytics_alert_settings_set_updated_at on public.analytics_alert_settings","create trigger analytics_alert_settings_set_updated_at
before update on public.analytics_alert_settings
for each row execute function public.set_updated_at()","comment on table public.analytics_alert_settings is
  ''Org enable/threshold overrides for Attention Center rules. Validated JSON only.''","-- ---------------------------------------------------------------------------
-- analytics_alert_events
-- ---------------------------------------------------------------------------

create table if not exists public.analytics_alert_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  rule_code text not null check (char_length(trim(rule_code)) >= 2),
  domain public.analytics_alert_domain not null,
  entity_type text,
  entity_id uuid,
  dedup_key text not null check (char_length(trim(dedup_key)) >= 1),
  severity public.analytics_alert_severity not null default ''WARNING'',
  status public.analytics_alert_status not null default ''OPEN'',
  first_detected_at timestamptz not null default timezone(''utc'', now()),
  last_detected_at timestamptz not null default timezone(''utc'', now()),
  resolved_at timestamptz,
  acknowledged_at timestamptz,
  acknowledged_by uuid references auth.users (id) on delete set null,
  payload_snapshot jsonb not null default ''{}''::jsonb,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint analytics_alert_events_org_id_unique unique (organization_id, id),
  constraint analytics_alert_events_org_dedup_unique unique (organization_id, dedup_key)
)","create index if not exists analytics_alert_events_org_status_idx
  on public.analytics_alert_events (organization_id, status, severity)","create index if not exists analytics_alert_events_org_rule_idx
  on public.analytics_alert_events (organization_id, rule_code, status)","create index if not exists analytics_alert_events_acknowledged_by_idx
  on public.analytics_alert_events (acknowledged_by)
  where acknowledged_by is not null","create index if not exists analytics_alert_events_entity_idx
  on public.analytics_alert_events (organization_id, entity_type, entity_id)
  where entity_id is not null","drop trigger if exists analytics_alert_events_set_updated_at on public.analytics_alert_events","create trigger analytics_alert_events_set_updated_at
before update on public.analytics_alert_events
for each row execute function public.set_updated_at()","comment on table public.analytics_alert_events is
  ''Deduped Attention Center events. ACK ≠ fix; source clear → RESOLVED via evaluate RPC.''","-- ---------------------------------------------------------------------------
-- analytics_inventory_thresholds
-- ---------------------------------------------------------------------------

create table if not exists public.analytics_inventory_thresholds (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  product_id uuid not null,
  warehouse_id uuid,
  minimum_available_quantity numeric(18, 4) not null check (minimum_available_quantity >= 0),
  warning_quantity numeric(18, 4) check (warning_quantity is null or warning_quantity >= 0),
  active boolean not null default true,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint analytics_inventory_thresholds_org_id_unique unique (organization_id, id),
  constraint analytics_inventory_thresholds_product_fk
    foreign key (organization_id, product_id)
    references public.products (organization_id, id) on delete cascade,
  constraint analytics_inventory_thresholds_warehouse_fk
    foreign key (organization_id, warehouse_id)
    references public.warehouses (organization_id, id) on delete cascade,
  constraint analytics_inventory_thresholds_warn_lte_min check (
    warning_quantity is null or warning_quantity <= minimum_available_quantity
  )
)","-- Unique: one threshold per org+product+warehouse (null warehouse = org-wide)
create unique index if not exists analytics_inventory_thresholds_scope_uidx
  on public.analytics_inventory_thresholds (
    organization_id,
    product_id,
    (coalesce(warehouse_id, ''00000000-0000-0000-0000-000000000000''::uuid))
  )","create index if not exists analytics_inventory_thresholds_org_idx
  on public.analytics_inventory_thresholds (organization_id, active)","create index if not exists analytics_inventory_thresholds_product_idx
  on public.analytics_inventory_thresholds (organization_id, product_id)","create index if not exists analytics_inventory_thresholds_warehouse_idx
  on public.analytics_inventory_thresholds (organization_id, warehouse_id)
  where warehouse_id is not null","drop trigger if exists analytics_inventory_thresholds_set_updated_at
  on public.analytics_inventory_thresholds","create trigger analytics_inventory_thresholds_set_updated_at
before update on public.analytics_inventory_thresholds
for each row execute function public.set_updated_at()","comment on table public.analytics_inventory_thresholds is
  ''Low-stock warning thresholds only — does not change stock engine rules.''","-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.analytics_alert_settings enable row level security","alter table public.analytics_alert_events enable row level security","alter table public.analytics_inventory_thresholds enable row level security","drop policy if exists analytics_alert_settings_select on public.analytics_alert_settings","create policy analytics_alert_settings_select on public.analytics_alert_settings
  for select to authenticated using (public.is_org_member(organization_id))","drop policy if exists analytics_alert_settings_write on public.analytics_alert_settings","create policy analytics_alert_settings_insert on public.analytics_alert_settings
  for insert to authenticated
  with check (
    public.has_org_role(organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[])
  )","create policy analytics_alert_settings_update on public.analytics_alert_settings
  for update to authenticated
  using (
    public.has_org_role(organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[])
  )
  with check (
    public.has_org_role(organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[])
  )","create policy analytics_alert_settings_delete on public.analytics_alert_settings
  for delete to authenticated
  using (
    public.has_org_role(organization_id, array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[])
  )","drop policy if exists analytics_alert_events_select on public.analytics_alert_events","create policy analytics_alert_events_select on public.analytics_alert_events
  for select to authenticated using (public.is_org_member(organization_id))","-- Mutations via SECURITY DEFINER RPCs only (no direct client write)
revoke insert, update, delete on table public.analytics_alert_events from authenticated","drop policy if exists analytics_inventory_thresholds_select on public.analytics_inventory_thresholds","create policy analytics_inventory_thresholds_select on public.analytics_inventory_thresholds
  for select to authenticated using (public.is_org_member(organization_id))","drop policy if exists analytics_inventory_thresholds_write on public.analytics_inventory_thresholds","create policy analytics_inventory_thresholds_insert on public.analytics_inventory_thresholds
  for insert to authenticated
  with check (
    public.has_org_role(organization_id, array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[])
  )","create policy analytics_inventory_thresholds_update on public.analytics_inventory_thresholds
  for update to authenticated
  using (
    public.has_org_role(organization_id, array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[])
  )
  with check (
    public.has_org_role(organization_id, array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[])
  )","create policy analytics_inventory_thresholds_delete on public.analytics_inventory_thresholds
  for delete to authenticated
  using (
    public.has_org_role(organization_id, array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[])
  )","revoke all on table public.analytics_alert_settings from public, anon","revoke all on table public.analytics_alert_events from public, anon","revoke all on table public.analytics_inventory_thresholds from public, anon","grant select, insert, update, delete on table public.analytics_alert_settings to authenticated","grant select on table public.analytics_alert_events to authenticated","grant select, insert, update, delete on table public.analytics_inventory_thresholds to authenticated","grant all on table public.analytics_alert_settings to service_role","grant all on table public.analytics_alert_events to service_role","grant all on table public.analytics_inventory_thresholds to service_role"}', 'phase11_alerts_thresholds'),
	('20261101130000', '{"-- Phase 11: core analytics helpers
-- search_path='''' everywhere. Internal helpers REVOKE from public/anon/authenticated.
-- Canonical GL economic scope: journal_entries.status IN (''POSTED'',''REVERSED'')

-- ---------------------------------------------------------------------------
-- 1) analytics_assert_service_role
-- ---------------------------------------------------------------------------

create or replace function public.analytics_assert_service_role()
returns void
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if auth.role() is distinct from ''service_role'' then
    raise exception ''analytics platform operation requires service_role'';
  end if;
end;
$$","revoke all on function public.analytics_assert_service_role() from public, anon, authenticated","grant execute on function public.analytics_assert_service_role() to service_role","-- ---------------------------------------------------------------------------
-- 2) analytics_assert_member
-- ---------------------------------------------------------------------------

create or replace function public.analytics_assert_member(p_org_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception ''authentication required'';
  end if;
  if p_org_id is null then
    raise exception ''organization_id required'';
  end if;
  if not public.is_org_member(p_org_id) then
    raise exception ''not a member of organization'';
  end if;
  return v_uid;
end;
$$","revoke all on function public.analytics_assert_member(uuid) from public, anon, authenticated","-- ---------------------------------------------------------------------------
-- Feature helpers
-- ---------------------------------------------------------------------------

create or replace function public.analytics_feature_enabled(
  p_org_id uuid,
  p_feature_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''''
as $$
  select exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = p_feature_code
      and ofeat.status = ''enabled''
  );
$$","revoke all on function public.analytics_feature_enabled(uuid, text) from public, anon, authenticated","create or replace function public.analytics_assert_feature(
  p_org_id uuid,
  p_feature_code text
)
returns void
language plpgsql
stable
security definer
set search_path = ''''
as $$
begin
  if not public.analytics_feature_enabled(p_org_id, p_feature_code) then
    raise exception ''feature % is not enabled'', p_feature_code;
  end if;
end;
$$","revoke all on function public.analytics_assert_feature(uuid, text) from public, anon, authenticated","create or replace function public.analytics_assert_any_feature(
  p_org_id uuid,
  p_feature_codes text[]
)
returns void
language plpgsql
stable
security definer
set search_path = ''''
as $$
begin
  if not exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = any (p_feature_codes)
      and ofeat.status = ''enabled''
  ) then
    raise exception ''required analytics feature not enabled (% )'', array_to_string(p_feature_codes, '','');
  end if;
end;
$$","revoke all on function public.analytics_assert_any_feature(uuid, text[]) from public, anon, authenticated","-- ---------------------------------------------------------------------------
-- 3) analytics_org_timezone
-- ---------------------------------------------------------------------------

create or replace function public.analytics_org_timezone(p_org_id uuid)
returns text
language sql
stable
security definer
set search_path = ''''
as $$
  select coalesce(
    (select o.timezone from public.organizations o where o.id = p_org_id),
    ''America/Argentina/Buenos_Aires''
  );
$$","revoke all on function public.analytics_org_timezone(uuid) from public, anon, authenticated","-- ---------------------------------------------------------------------------
-- 4) analytics_period_bounds
-- Presets use organizations.timezone for \"today\"/week/month boundaries.
-- DATE columns remain DATE (no timestamptz shift on stored dates).
-- ---------------------------------------------------------------------------

create or replace function public.analytics_period_bounds(
  p_org_id uuid,
  p_preset text,
  p_from date default null,
  p_to date default null
)
returns table (period_start date, period_end date)
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_tz text;
  v_today date;
  v_preset text := upper(coalesce(nullif(trim(p_preset), ''''), ''THIS_MONTH''));
  v_month_start date;
  v_q_month int;
begin
  v_tz := public.analytics_org_timezone(p_org_id);
  v_today := (timezone(v_tz, timezone(''utc'', now())))::date;

  if v_preset = ''CUSTOM'' then
    if p_from is null or p_to is null then
      raise exception ''CUSTOM period requires p_from and p_to'';
    end if;
    if p_from > p_to then
      raise exception ''period_start must be <= period_end'';
    end if;
    period_start := p_from;
    period_end := p_to;
    return next;
    return;
  end if;

  if v_preset = ''TODAY'' then
    period_start := v_today;
    period_end := v_today;
  elsif v_preset = ''THIS_WEEK'' then
    -- ISO week: Monday start
    period_start := v_today - ((extract(isodow from v_today)::int) - 1);
    period_end := period_start + 6;
  elsif v_preset = ''THIS_MONTH'' then
    period_start := date_trunc(''month'', v_today::timestamp)::date;
    period_end := (date_trunc(''month'', v_today::timestamp) + interval ''1 month'' - interval ''1 day'')::date;
  elsif v_preset = ''PREV_MONTH'' then
    v_month_start := (date_trunc(''month'', v_today::timestamp) - interval ''1 month'')::date;
    period_start := v_month_start;
    period_end := (date_trunc(''month'', v_today::timestamp) - interval ''1 day'')::date;
  elsif v_preset = ''THIS_QUARTER'' then
    v_q_month := ((extract(month from v_today)::int - 1) / 3) * 3 + 1;
    period_start := make_date(extract(year from v_today)::int, v_q_month, 1);
    period_end := (period_start + interval ''3 months'' - interval ''1 day'')::date;
  elsif v_preset = ''THIS_YEAR'' then
    period_start := make_date(extract(year from v_today)::int, 1, 1);
    period_end := make_date(extract(year from v_today)::int, 12, 31);
  else
    raise exception ''unsupported period preset: %'', p_preset;
  end if;

  return next;
end;
$$","revoke all on function public.analytics_period_bounds(uuid, text, date, date)
  from public, anon, authenticated","-- ---------------------------------------------------------------------------
-- 5) analytics_fiscal_economic_sign — thin wrapper → tax_fiscal_vat_economic_sign
-- ---------------------------------------------------------------------------

create or replace function public.analytics_fiscal_economic_sign(
  p_operation_kind public.fiscal_operation_kind
)
returns numeric
language sql
immutable
set search_path = ''''
as $$
  select public.tax_fiscal_vat_economic_sign(p_operation_kind);
$$","revoke all on function public.analytics_fiscal_economic_sign(public.fiscal_operation_kind)
  from public, anon, authenticated","comment on function public.analytics_fiscal_economic_sign(public.fiscal_operation_kind) is
  ''Thin wrapper over tax_fiscal_vat_economic_sign: INVOICE/DN +1, CN -1.''","-- ---------------------------------------------------------------------------
-- 6) Economic journal status helpers
-- Canonical: status IN (''POSTED'',''REVERSED'')
-- ---------------------------------------------------------------------------

create or replace function public.analytics_is_economic_journal_status(
  p_status public.journal_entry_status
)
returns boolean
language sql
immutable
set search_path = ''''
as $$
  select p_status in (''POSTED''::public.journal_entry_status, ''REVERSED''::public.journal_entry_status);
$$","revoke all on function public.analytics_is_economic_journal_status(public.journal_entry_status)
  from public, anon, authenticated","comment on function public.analytics_is_economic_journal_status(public.journal_entry_status) is
  ''Canonical GL economic scope: POSTED + REVERSED (original REVERSED + reversing POSTED net to 0).''","create or replace function public.analytics_journal_economic_lines(p_org_id uuid)
returns table (
  journal_entry_id uuid,
  entry_date date,
  account_id uuid,
  account_type public.account_type,
  normal_balance public.normal_balance,
  system_role text,
  account_code text,
  parent_id uuid,
  debit numeric(19, 4),
  credit numeric(19, 4),
  line_id uuid
)
language sql
stable
security definer
set search_path = ''''
as $$
  select
    je.id as journal_entry_id,
    je.entry_date,
    jel.account_id,
    a.account_type,
    a.normal_balance,
    a.system_role,
    a.code as account_code,
    a.parent_id,
    jel.debit::numeric(19, 4),
    jel.credit::numeric(19, 4),
    jel.id as line_id
  from public.journal_entry_lines jel
  join public.journal_entries je
    on je.id = jel.journal_entry_id
   and je.organization_id = jel.organization_id
  join public.accounts a
    on a.id = jel.account_id
   and a.organization_id = jel.organization_id
  where jel.organization_id = p_org_id
    and public.analytics_is_economic_journal_status(je.status)
    and a.account_type is distinct from ''MEMORANDUM''::public.account_type;
$$","revoke all on function public.analytics_journal_economic_lines(uuid) from public, anon, authenticated","-- COGS account predicate: system_role cogs OR ancestor group_cogs
create or replace function public.analytics_account_is_cogs(p_account_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  walk uuid := p_account_id;
  hops int := 0;
  v_role text;
begin
  while walk is not null loop
    hops := hops + 1;
    if hops > 30 then
      return false;
    end if;
    select system_role, parent_id into v_role, walk
    from public.accounts
    where id = walk;
    if not found then
      return false;
    end if;
    if v_role in (''cogs'', ''group_cogs'') then
      return true;
    end if;
  end loop;
  return false;
end;
$$","revoke all on function public.analytics_account_is_cogs(uuid) from public, anon, authenticated","-- ---------------------------------------------------------------------------
-- 7–8) Fiscal sales aggregates
-- ---------------------------------------------------------------------------

create or replace function public.analytics_sales_fiscal_net(
  p_org_id uuid,
  p_from date,
  p_to date,
  p_env text default null
)
returns numeric
language sql
stable
security definer
set search_path = ''''
as $$
  select coalesce(sum(
    (
      coalesce(fd.net_taxed_amount, 0)
      + coalesce(fd.net_exempt_amount, 0)
      + coalesce(fd.net_untaxed_amount, 0)
    ) * public.analytics_fiscal_economic_sign(fdt.operation_kind)
  ), 0)::numeric(19, 4)
  from public.fiscal_documents fd
  join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
  where fd.organization_id = p_org_id
    and fd.status = ''AUTHORIZED''::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to
    and (
      p_env is null
      or fd.fiscal_environment::text = p_env
    );
$$","revoke all on function public.analytics_sales_fiscal_net(uuid, date, date, text)
  from public, anon, authenticated","create or replace function public.analytics_sales_fiscal_gross(
  p_org_id uuid,
  p_from date,
  p_to date,
  p_env text default null
)
returns numeric
language sql
stable
security definer
set search_path = ''''
as $$
  select coalesce(sum(
    coalesce(fd.total_amount, 0) * public.analytics_fiscal_economic_sign(fdt.operation_kind)
  ), 0)::numeric(19, 4)
  from public.fiscal_documents fd
  join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
  where fd.organization_id = p_org_id
    and fd.status = ''AUTHORIZED''::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to
    and (
      p_env is null
      or fd.fiscal_environment::text = p_env
    );
$$","revoke all on function public.analytics_sales_fiscal_gross(uuid, date, date, text)
  from public, anon, authenticated","-- Signed money helper by normal balance
create or replace function public.analytics_signed_balance(
  p_debit numeric,
  p_credit numeric,
  p_normal public.normal_balance
)
returns numeric
language sql
immutable
set search_path = ''''
as $$
  select case p_normal
    when ''DEBIT''::public.normal_balance then (coalesce(p_debit, 0) - coalesce(p_credit, 0))
    else (coalesce(p_credit, 0) - coalesce(p_debit, 0))
  end::numeric(19, 4);
$$","revoke all on function public.analytics_signed_balance(numeric, numeric, public.normal_balance)
  from public, anon, authenticated","-- Previous period bounds (same length immediately before)
create or replace function public.analytics_prev_period_bounds(
  p_start date,
  p_end date
)
returns table (period_start date, period_end date)
language sql
immutable
set search_path = ''''
as $$
  select
    (p_start - (p_end - p_start + 1))::date,
    (p_start - 1)::date;
$$","revoke all on function public.analytics_prev_period_bounds(date, date)
  from public, anon, authenticated"}', 'phase11_helpers_core'),
	('20261101140000', '{"-- Phase 11: management P&L + balance sheet RPCs
-- Economic GL scope: POSTED + REVERSED. No balancing plug journals.
-- Label: gerencial interno — sujeto a revisión profesional.

create or replace function public.analytics_management_pnl(
  p_org_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_revenue numeric(19, 4) := 0;
  v_cogs numeric(19, 4) := 0;
  v_opex numeric(19, 4) := 0;
  v_other numeric(19, 4) := 0;
  v_gross numeric(19, 4);
  v_mgmt numeric(19, 4);
  v_has_cogs_mapping boolean := false;
  v_cogs_activity boolean := false;
  v_mapping_status text := ''OK'';
  v_now timestamptz := timezone(''utc'', now());
begin
  v_uid := public.analytics_assert_member(p_org_id);
  perform public.analytics_assert_feature(p_org_id, ''accounting'');

  if p_from is null or p_to is null or p_from > p_to then
    raise exception ''invalid period for management pnl'';
  end if;

  select exists (
    select 1
    from public.accounts a
    where a.organization_id = p_org_id
      and (
        a.system_role in (''cogs'', ''group_cogs'')
        or public.analytics_account_is_cogs(a.id)
      )
  ) into v_has_cogs_mapping;

  select
    coalesce(sum(
      case
        when l.account_type = ''REVENUE''::public.account_type
          then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0
      end
    ), 0)::numeric(19, 4),
    coalesce(sum(
      case
        when public.analytics_account_is_cogs(l.account_id)
          then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0
      end
    ), 0)::numeric(19, 4),
    coalesce(sum(
      case
        when l.account_type = ''EXPENSE''::public.account_type
          and not public.analytics_account_is_cogs(l.account_id)
          then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0
      end
    ), 0)::numeric(19, 4)
  into v_revenue, v_cogs, v_opex
  from public.analytics_journal_economic_lines(p_org_id) l
  where l.entry_date >= p_from
    and l.entry_date <= p_to;

  v_other := 0;
  v_gross := (v_revenue - v_cogs)::numeric(19, 4);
  v_mgmt := (v_revenue - v_cogs - v_opex - v_other)::numeric(19, 4);
  v_cogs_activity := abs(v_cogs) > 0.0001;

  if not v_has_cogs_mapping then
    v_mapping_status := ''REPORT_MAPPING_REQUIRES_REVIEW'';
  elsif v_revenue <> 0 and not v_cogs_activity and not v_has_cogs_mapping then
    v_mapping_status := ''REPORT_MAPPING_REQUIRES_REVIEW'';
  end if;

  return jsonb_build_object(
    ''revenue'', v_revenue,
    ''cogs'', v_cogs,
    ''gross_result'', v_gross,
    ''opex'', v_opex,
    ''other'', v_other,
    ''management_result'', v_mgmt,
    ''mapping_status'', v_mapping_status,
    ''mapping_ok'', (v_mapping_status = ''OK''),
    ''has_cogs_mapping'', v_has_cogs_mapping,
    ''disclaimer'', ''Reporte gerencial interno — sujeto a revisión profesional'',
    ''calculation_version'', 1,
    ''period_start'', p_from,
    ''period_end'', p_to,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''generated_by'', v_uid
  );
end;
$$","revoke all on function public.analytics_management_pnl(uuid, date, date) from public, anon","grant execute on function public.analytics_management_pnl(uuid, date, date) to authenticated","comment on function public.analytics_management_pnl(uuid, date, date) is
  ''SECURITY DEFINER intentional: org-scoped management P&L; auth via analytics_assert_member + accounting feature.''","create or replace function public.analytics_management_balance_sheet(
  p_org_id uuid,
  p_as_of date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_assets numeric(19, 4) := 0;
  v_liabilities numeric(19, 4) := 0;
  v_equity numeric(19, 4) := 0;
  v_ytd_revenue numeric(19, 4) := 0;
  v_ytd_expense numeric(19, 4) := 0;
  v_period_result numeric(19, 4) := 0;
  v_rhs numeric(19, 4);
  v_diff numeric(19, 4);
  v_status text := ''OK'';
  v_year_start date;
  v_now timestamptz := timezone(''utc'', now());
begin
  v_uid := public.analytics_assert_member(p_org_id);
  perform public.analytics_assert_feature(p_org_id, ''accounting'');

  if p_as_of is null then
    raise exception ''p_as_of required'';
  end if;

  -- Calendar year containing as_of (Jan 1 → as_of)
  v_year_start := make_date(extract(year from p_as_of)::int, 1, 1);

  select
    coalesce(sum(
      case when l.account_type = ''ASSET''::public.account_type
        then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0 end
    ), 0)::numeric(19, 4),
    coalesce(sum(
      case when l.account_type = ''LIABILITY''::public.account_type
        then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0 end
    ), 0)::numeric(19, 4),
    coalesce(sum(
      case when l.account_type = ''EQUITY''::public.account_type
        then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0 end
    ), 0)::numeric(19, 4)
  into v_assets, v_liabilities, v_equity
  from public.analytics_journal_economic_lines(p_org_id) l
  where l.entry_date <= p_as_of
    and l.account_type in (
      ''ASSET''::public.account_type,
      ''LIABILITY''::public.account_type,
      ''EQUITY''::public.account_type
    );

  -- YTD P&L net (revenue − expenses including COGS)
  select
    coalesce(sum(
      case when l.account_type = ''REVENUE''::public.account_type
        then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0 end
    ), 0)::numeric(19, 4),
    coalesce(sum(
      case when l.account_type = ''EXPENSE''::public.account_type
        then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0 end
    ), 0)::numeric(19, 4)
  into v_ytd_revenue, v_ytd_expense
  from public.analytics_journal_economic_lines(p_org_id) l
  where l.entry_date >= v_year_start
    and l.entry_date <= p_as_of
    and l.account_type in (
      ''REVENUE''::public.account_type,
      ''EXPENSE''::public.account_type
    );

  v_period_result := (v_ytd_revenue - v_ytd_expense)::numeric(19, 4);
  v_rhs := (v_liabilities + v_equity + v_period_result)::numeric(19, 4);
  v_diff := (v_assets - v_rhs)::numeric(19, 4);

  if abs(v_diff) > 0.01 then
    v_status := ''REPORT_ACCOUNTING_MISMATCH'';
  end if;

  return jsonb_build_object(
    ''as_of'', p_as_of,
    ''assets'', v_assets,
    ''liabilities'', v_liabilities,
    ''equity'', v_equity,
    ''resultado_del_periodo'', v_period_result,
    ''ytd_start'', v_year_start,
    ''equation_rhs'', v_rhs,
    ''difference'', v_diff,
    ''status'', v_status,
    ''disclaimer'', ''Reporte gerencial interno — sujeto a revisión profesional. Sin asiento de balanceo.'',
    ''calculation_version'', 1,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''generated_by'', v_uid
  );
end;
$$","revoke all on function public.analytics_management_balance_sheet(uuid, date) from public, anon","grant execute on function public.analytics_management_balance_sheet(uuid, date) to authenticated","comment on function public.analytics_management_balance_sheet(uuid, date) is
  ''SECURITY DEFINER intentional: management BS as-of; no plug journal; mismatch reported when |diff|>0.01.''"}', 'phase11_accounting_reports'),
	('20261101150000', '{"-- Phase 11: dashboard client RPCs
-- Auth: auth.uid + membership + feature gates. SECURITY DEFINER with intentional grants.

create or replace function public.analytics_metric_payload(
  p_code text,
  p_value numeric,
  p_label text,
  p_unit text,
  p_compare_value numeric default null,
  p_compare_available boolean default false
)
returns jsonb
language sql
immutable
set search_path = ''''
as $$
  select jsonb_build_object(
    ''code'', p_code,
    ''value'', p_value,
    ''label'', p_label,
    ''unit'', p_unit,
    ''calculation_version'', 1,
    ''comparison'', case
      when p_compare_available then jsonb_build_object(
        ''mode'', ''PREV_PERIOD'',
        ''value'', p_compare_value,
        ''delta'', (p_value - coalesce(p_compare_value, 0))
      )
      else jsonb_build_object(''mode'', ''NONE'', ''available'', false, ''message'', ''Sin período comparable'')
    end
  );
$$","revoke all on function public.analytics_metric_payload(text, numeric, text, text, numeric, boolean)
  from public, anon, authenticated","-- ---------------------------------------------------------------------------
-- AR / AP open helpers
-- ---------------------------------------------------------------------------

create or replace function public.analytics_ar_open_total(p_org_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''''
as $$
  select coalesce(sum(
    case
      when ari.direction = ''AR_INCREASE''::public.accounts_receivable_direction then ari.open_amount
      else -ari.open_amount
    end
  ), 0)::numeric(19, 4)
  from public.accounts_receivable_items ari
  where ari.organization_id = p_org_id
    and ari.status in (
      ''OPEN''::public.accounts_receivable_status,
      ''PARTIALLY_COLLECTED''::public.accounts_receivable_status
    )
    and ari.open_amount > 0;
$$","revoke all on function public.analytics_ar_open_total(uuid) from public, anon, authenticated","create or replace function public.analytics_ap_open_total(p_org_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''''
as $$
  select coalesce(sum(
    case
      when api.direction = ''AP_INCREASE''::public.accounts_payable_direction then api.open_amount
      else -api.open_amount
    end
  ), 0)::numeric(19, 4)
  from public.accounts_payable_items api
  where api.organization_id = p_org_id
    and api.status in (
      ''OPEN''::public.accounts_payable_status,
      ''PARTIALLY_PAID''::public.accounts_payable_status
    )
    and api.open_amount > 0;
$$","revoke all on function public.analytics_ap_open_total(uuid) from public, anon, authenticated","create or replace function public.analytics_treasury_type_balance(
  p_org_id uuid,
  p_account_type public.treasury_account_type
)
returns numeric
language sql
stable
security definer
set search_path = ''''
as $$
  select coalesce(sum(public.treasury_account_balance(ta.id)), 0)::numeric(19, 4)
  from public.treasury_accounts ta
  where ta.organization_id = p_org_id
    and ta.account_type = p_account_type
    and ta.is_active;
$$","revoke all on function public.analytics_treasury_type_balance(uuid, public.treasury_account_type)
  from public, anon, authenticated","create or replace function public.analytics_aging_bucket(
  p_due_date date,
  p_as_of date
)
returns text
language sql
immutable
set search_path = ''''
as $$
  select case
    when p_due_date is null then ''NO_DUE_DATE''
    when p_due_date >= p_as_of then ''NOT_DUE''
    when (p_as_of - p_due_date) between 1 and 30 then ''OVERDUE_1_30''
    when (p_as_of - p_due_date) between 31 and 60 then ''OVERDUE_31_60''
    when (p_as_of - p_due_date) between 61 and 90 then ''OVERDUE_61_90''
    else ''OVERDUE_90_PLUS''
  end;
$$","revoke all on function public.analytics_aging_bucket(date, date) from public, anon, authenticated","-- ---------------------------------------------------------------------------
-- get_ar_aging / get_ap_aging
-- ---------------------------------------------------------------------------

create or replace function public.get_ar_aging(
  p_organization_id uuid,
  p_as_of date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_as_of date;
  v_now timestamptz := timezone(''utc'', now());
  v_rows jsonb;
  v_totals jsonb;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_any_feature(p_organization_id, array[''dashboard'',''reports'',''sales'']);

  v_as_of := coalesce(
    p_as_of,
    (timezone(public.analytics_org_timezone(p_organization_id), timezone(''utc'', now())))::date
  );

  select coalesce(jsonb_agg(x.row_obj order by x.sort_key), ''[]''::jsonb)
  into v_rows
  from (
    select
      case b.bucket
        when ''NOT_DUE'' then 1
        when ''OVERDUE_1_30'' then 2
        when ''OVERDUE_31_60'' then 3
        when ''OVERDUE_61_90'' then 4
        when ''OVERDUE_90_PLUS'' then 5
        else 6
      end as sort_key,
      jsonb_build_object(
        ''bucket'', b.bucket,
        ''amount'', b.amount,
        ''count'', b.cnt
      ) as row_obj
    from (
      select
        public.analytics_aging_bucket(ari.due_date, v_as_of) as bucket,
        coalesce(sum(
          case
            when ari.direction = ''AR_INCREASE''::public.accounts_receivable_direction then ari.open_amount
            else -ari.open_amount
          end
        ), 0)::numeric(19, 4) as amount,
        count(*)::int as cnt
      from public.accounts_receivable_items ari
      where ari.organization_id = p_organization_id
        and ari.status in (
          ''OPEN''::public.accounts_receivable_status,
          ''PARTIALLY_COLLECTED''::public.accounts_receivable_status
        )
        and ari.open_amount > 0
      group by 1
    ) b
  ) x;

  select jsonb_object_agg(e->>''bucket'', e->''amount'')
  into v_totals
  from jsonb_array_elements(v_rows) e;

  return jsonb_build_object(
    ''as_of'', v_as_of,
    ''rows'', v_rows,
    ''totals'', coalesce(v_totals, ''{}''::jsonb),
    ''open_total'', public.analytics_ar_open_total(p_organization_id),
    ''calculation_version'', 1,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''generated_by'', v_uid
  );
end;
$$","revoke all on function public.get_ar_aging(uuid, date) from public, anon","grant execute on function public.get_ar_aging(uuid, date) to authenticated","create or replace function public.get_ap_aging(
  p_organization_id uuid,
  p_as_of date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_as_of date;
  v_now timestamptz := timezone(''utc'', now());
  v_rows jsonb;
  v_totals jsonb;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_any_feature(p_organization_id, array[''dashboard'',''reports'',''purchases'']);

  v_as_of := coalesce(
    p_as_of,
    (timezone(public.analytics_org_timezone(p_organization_id), timezone(''utc'', now())))::date
  );

  select coalesce(jsonb_agg(x.row_obj order by x.sort_key), ''[]''::jsonb)
  into v_rows
  from (
    select
      case b.bucket
        when ''NOT_DUE'' then 1
        when ''OVERDUE_1_30'' then 2
        when ''OVERDUE_31_60'' then 3
        when ''OVERDUE_61_90'' then 4
        when ''OVERDUE_90_PLUS'' then 5
        else 6
      end as sort_key,
      jsonb_build_object(
        ''bucket'', b.bucket,
        ''amount'', b.amount,
        ''count'', b.cnt
      ) as row_obj
    from (
      select
        public.analytics_aging_bucket(api.due_date, v_as_of) as bucket,
        coalesce(sum(
          case
            when api.direction = ''AP_INCREASE''::public.accounts_payable_direction then api.open_amount
            else -api.open_amount
          end
        ), 0)::numeric(19, 4) as amount,
        count(*)::int as cnt
      from public.accounts_payable_items api
      where api.organization_id = p_organization_id
        and api.status in (
          ''OPEN''::public.accounts_payable_status,
          ''PARTIALLY_PAID''::public.accounts_payable_status
        )
        and api.open_amount > 0
      group by 1
    ) b
  ) x;

  select jsonb_object_agg(e->>''bucket'', e->''amount'')
  into v_totals
  from jsonb_array_elements(v_rows) e;

  return jsonb_build_object(
    ''as_of'', v_as_of,
    ''rows'', v_rows,
    ''totals'', coalesce(v_totals, ''{}''::jsonb),
    ''open_total'', public.analytics_ap_open_total(p_organization_id),
    ''calculation_version'', 1,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''generated_by'', v_uid
  );
end;
$$","revoke all on function public.get_ap_aging(uuid, date) from public, anon","grant execute on function public.get_ap_aging(uuid, date) to authenticated","-- ---------------------------------------------------------------------------
-- get_financial_dashboard
-- ---------------------------------------------------------------------------

create or replace function public.get_financial_dashboard(
  p_organization_id uuid,
  p_period_preset text default ''THIS_MONTH'',
  p_from date default null,
  p_to date default null,
  p_compare_mode text default ''PREV_PERIOD''
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_start date;
  v_end date;
  v_pstart date;
  v_pend date;
  v_now timestamptz := timezone(''utc'', now());
  v_metrics jsonb := ''{}''::jsonb;
  v_do_compare boolean := upper(coalesce(p_compare_mode, ''PREV_PERIOD'')) = ''PREV_PERIOD'';
  v_cash numeric(19, 4);
  v_bank numeric(19, 4);
  v_clearing numeric(19, 4);
  v_coll numeric(19, 4);
  v_pay numeric(19, 4);
  v_coll_prev numeric(19, 4);
  v_pay_prev numeric(19, 4);
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''dashboard'');

  if not public.has_org_role(
    p_organization_id,
    array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
  ) then
    raise exception ''insufficient role for financial dashboard'';
  end if;

  select pb.period_start, pb.period_end
  into v_start, v_end
  from public.analytics_period_bounds(p_organization_id, p_period_preset, p_from, p_to) pb;

  select pp.period_start, pp.period_end into v_pstart, v_pend
  from public.analytics_prev_period_bounds(v_start, v_end) pp;

  v_cash := public.analytics_treasury_type_balance(p_organization_id, ''CASH''::public.treasury_account_type);
  v_bank := public.analytics_treasury_type_balance(p_organization_id, ''BANK''::public.treasury_account_type);
  v_clearing := public.analytics_treasury_type_balance(p_organization_id, ''CLEARING''::public.treasury_account_type);

  select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_coll
  from public.treasury_operations o
  where o.organization_id = p_organization_id
    and o.operation_type = ''COLLECTION''::public.treasury_operation_type
    and o.status = ''POSTED''::public.treasury_operation_status
    and o.operation_date >= v_start and o.operation_date <= v_end;

  select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_pay
  from public.treasury_operations o
  where o.organization_id = p_organization_id
    and o.operation_type = ''PAYMENT''::public.treasury_operation_type
    and o.status = ''POSTED''::public.treasury_operation_status
    and o.operation_date >= v_start and o.operation_date <= v_end;

  if v_do_compare then
    select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_coll_prev
    from public.treasury_operations o
    where o.organization_id = p_organization_id
      and o.operation_type = ''COLLECTION''::public.treasury_operation_type
      and o.status = ''POSTED''::public.treasury_operation_status
      and o.operation_date >= v_pstart and o.operation_date <= v_pend;

    select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_pay_prev
    from public.treasury_operations o
    where o.organization_id = p_organization_id
      and o.operation_type = ''PAYMENT''::public.treasury_operation_type
      and o.status = ''POSTED''::public.treasury_operation_status
      and o.operation_date >= v_pstart and o.operation_date <= v_pend;
  end if;

  v_metrics := v_metrics
    || jsonb_build_object(
      ''CASH_INTERNAL'',
      public.analytics_metric_payload(''CASH_INTERNAL'', v_cash, ''Saldo de caja interno'', ''CURRENCY'')
    )
    || jsonb_build_object(
      ''BANK_INTERNAL'',
      public.analytics_metric_payload(''BANK_INTERNAL'', v_bank, ''Saldo bancario interno'', ''CURRENCY'')
    )
    || jsonb_build_object(
      ''CLEARING_PENDING'',
      public.analytics_metric_payload(''CLEARING_PENDING'', v_clearing, ''Tarjetas/QR pendientes'', ''CURRENCY'')
    )
    || jsonb_build_object(
      ''AR_OPEN'',
      public.analytics_metric_payload(
        ''AR_OPEN'', public.analytics_ar_open_total(p_organization_id),
        ''Cuentas por cobrar abiertas'', ''CURRENCY''
      )
    )
    || jsonb_build_object(
      ''AP_OPEN'',
      public.analytics_metric_payload(
        ''AP_OPEN'', public.analytics_ap_open_total(p_organization_id),
        ''Cuentas por pagar abiertas'', ''CURRENCY''
      )
    )
    || jsonb_build_object(
      ''COLLECTIONS_POSTED'',
      public.analytics_metric_payload(
        ''COLLECTIONS_POSTED'', v_coll, ''Cobros reales'', ''CURRENCY'',
        v_coll_prev, v_do_compare
      )
    )
    || jsonb_build_object(
      ''PAYMENTS_POSTED'',
      public.analytics_metric_payload(
        ''PAYMENTS_POSTED'', v_pay, ''Pagos reales'', ''CURRENCY'',
        v_pay_prev, v_do_compare
      )
    );

  return jsonb_build_object(
    ''metrics'', v_metrics,
    ''period_start'', v_start,
    ''period_end'', v_end,
    ''compare_period_start'', case when v_do_compare then to_jsonb(v_pstart) else ''null''::jsonb end,
    ''compare_period_end'', case when v_do_compare then to_jsonb(v_pend) else ''null''::jsonb end,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''calculation_version'', 1
  );
end;
$$","revoke all on function public.get_financial_dashboard(uuid, text, date, date, text) from public, anon","grant execute on function public.get_financial_dashboard(uuid, text, date, date, text) to authenticated","-- ---------------------------------------------------------------------------
-- get_dashboard_summary
-- ---------------------------------------------------------------------------

create or replace function public.get_dashboard_summary(
  p_organization_id uuid,
  p_period_preset text default ''THIS_MONTH'',
  p_from date default null,
  p_to date default null,
  p_compare_mode text default ''PREV_PERIOD''
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_start date;
  v_end date;
  v_pstart date;
  v_pend date;
  v_now timestamptz := timezone(''utc'', now());
  v_metrics jsonb := ''{}''::jsonb;
  v_sections jsonb;
  v_do_compare boolean := upper(coalesce(p_compare_mode, ''PREV_PERIOD'')) = ''PREV_PERIOD'';
  v_feat_taxes boolean;
  v_feat_inventory boolean;
  v_feat_pos boolean;
  v_feat_fiscal boolean;
  v_feat_cash boolean;
  v_feat_banks boolean;
  v_feat_accounting boolean;
  v_feat_purchases boolean;
  v_feat_sales boolean;
  v_val numeric(19, 4);
  v_prev numeric(19, 4);
  v_pnl jsonb;
  v_tax numeric(19, 4);
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''dashboard'');

  select pb.period_start, pb.period_end into v_start, v_end
  from public.analytics_period_bounds(p_organization_id, p_period_preset, p_from, p_to) pb;

  select pp.period_start, pp.period_end into v_pstart, v_pend
  from public.analytics_prev_period_bounds(v_start, v_end) pp;

  v_feat_taxes := public.analytics_feature_enabled(p_organization_id, ''taxes'');
  v_feat_inventory := public.analytics_feature_enabled(p_organization_id, ''inventory'');
  v_feat_pos := public.analytics_feature_enabled(p_organization_id, ''pos'');
  v_feat_fiscal := public.analytics_feature_enabled(p_organization_id, ''fiscal_invoicing'');
  v_feat_cash := public.analytics_feature_enabled(p_organization_id, ''cash'');
  v_feat_banks := public.analytics_feature_enabled(p_organization_id, ''banks'');
  v_feat_accounting := public.analytics_feature_enabled(p_organization_id, ''accounting'');
  v_feat_purchases := public.analytics_feature_enabled(p_organization_id, ''purchases'');
  v_feat_sales := public.analytics_feature_enabled(p_organization_id, ''sales'');

  v_sections := jsonb_build_object(
    ''resumen'', true,
    ''finanzas'', (v_feat_cash or v_feat_banks or v_feat_accounting),
    ''ventas'', (v_feat_sales or v_feat_fiscal),
    ''compras'', v_feat_purchases,
    ''stock'', v_feat_inventory,
    ''impuestos'', v_feat_taxes,
    ''atencion'', true
  );

  if v_feat_fiscal then
    v_val := public.analytics_sales_fiscal_gross(p_organization_id, v_start, v_end, null);
    v_prev := case when v_do_compare
      then public.analytics_sales_fiscal_gross(p_organization_id, v_pstart, v_pend, null)
      else null end;
    v_metrics := v_metrics || jsonb_build_object(
      ''SALES_FISCAL_GROSS_AUTHORIZED'',
      public.analytics_metric_payload(
        ''SALES_FISCAL_GROSS_AUTHORIZED'', v_val,
        ''Ventas facturadas brutas autorizadas'', ''CURRENCY'', v_prev, v_do_compare
      )
    );
    v_val := public.analytics_sales_fiscal_net(p_organization_id, v_start, v_end, null);
    v_prev := case when v_do_compare
      then public.analytics_sales_fiscal_net(p_organization_id, v_pstart, v_pend, null)
      else null end;
    v_metrics := v_metrics || jsonb_build_object(
      ''SALES_FISCAL_NET_AUTHORIZED'',
      public.analytics_metric_payload(
        ''SALES_FISCAL_NET_AUTHORIZED'', v_val,
        ''Ventas facturadas netas autorizadas'', ''CURRENCY'', v_prev, v_do_compare
      )
    );
  end if;

  if v_feat_cash or v_feat_banks then
    v_metrics := v_metrics || jsonb_build_object(
      ''CASH_INTERNAL'',
      public.analytics_metric_payload(
        ''CASH_INTERNAL'',
        public.analytics_treasury_type_balance(p_organization_id, ''CASH''::public.treasury_account_type),
        ''Saldo de caja interno'', ''CURRENCY''
      )
    );
    v_metrics := v_metrics || jsonb_build_object(
      ''BANK_INTERNAL'',
      public.analytics_metric_payload(
        ''BANK_INTERNAL'',
        public.analytics_treasury_type_balance(p_organization_id, ''BANK''::public.treasury_account_type),
        ''Saldo bancario interno'', ''CURRENCY''
      )
    );
  end if;

  if v_feat_pos then
    v_metrics := v_metrics || jsonb_build_object(
      ''CLEARING_PENDING'',
      public.analytics_metric_payload(
        ''CLEARING_PENDING'',
        public.analytics_treasury_type_balance(p_organization_id, ''CLEARING''::public.treasury_account_type),
        ''Tarjetas/QR pendientes'', ''CURRENCY''
      )
    );
  end if;

  if v_feat_sales then
    v_metrics := v_metrics || jsonb_build_object(
      ''AR_OPEN'',
      public.analytics_metric_payload(
        ''AR_OPEN'', public.analytics_ar_open_total(p_organization_id),
        ''Cuentas por cobrar abiertas'', ''CURRENCY''
      )
    );
  end if;

  if v_feat_purchases then
    v_metrics := v_metrics || jsonb_build_object(
      ''AP_OPEN'',
      public.analytics_metric_payload(
        ''AP_OPEN'', public.analytics_ap_open_total(p_organization_id),
        ''Cuentas por pagar abiertas'', ''CURRENCY''
      )
    );
  end if;

  if v_feat_inventory then
    select coalesce(sum(ics.inventory_value), 0)::numeric(19, 4) into v_val
    from public.inventory_cost_state ics
    where ics.organization_id = p_organization_id;
    v_metrics := v_metrics || jsonb_build_object(
      ''INVENTORY_VALUE'',
      public.analytics_metric_payload(''INVENTORY_VALUE'', v_val, ''Inventario valorizado'', ''CURRENCY'')
    );
  end if;

  if v_feat_taxes
    and public.has_org_role(
      p_organization_id,
      array[''owner'',''admin'',''accountant'']::public.member_role[]
    )
  then
    select coalesce(
      (
        select (td.totals_snapshot->>''saldo_estimado'')::numeric(19, 4)
        from public.tax_determinations td
        join public.tax_periods tp on tp.id = td.tax_period_id
        where td.organization_id = p_organization_id
          and td.is_current
          and td.totals_snapshot ? ''saldo_estimado''
        order by tp.period_end desc nulls last, td.calculated_at desc nulls last
        limit 1
      ),
      0
    ) into v_tax;
    v_metrics := v_metrics || jsonb_build_object(
      ''TAX_IVA_SALDO_ESTIMADO'',
      public.analytics_metric_payload(
        ''TAX_IVA_SALDO_ESTIMADO'', coalesce(v_tax, 0),
        ''IVA — saldo estimado'', ''CURRENCY''
      ) || jsonb_build_object(
        ''disclaimer'', ''Saldo estimado según Contabilium — no es IVA definitivo a pagar''
      )
    );
  end if;

  if v_feat_accounting
    and public.has_org_role(
      p_organization_id,
      array[''owner'',''admin'',''accountant'']::public.member_role[]
    )
  then
    v_pnl := public.analytics_management_pnl(p_organization_id, v_start, v_end);
    v_metrics := v_metrics || jsonb_build_object(
      ''MANAGEMENT_GROSS_RESULT'',
      public.analytics_metric_payload(
        ''MANAGEMENT_GROSS_RESULT'',
        coalesce((v_pnl->>''gross_result'')::numeric, 0),
        ''Resultado bruto gerencial'', ''CURRENCY''
      )
    );
    v_metrics := v_metrics || jsonb_build_object(
      ''ACCT_RESULT_EST'',
      public.analytics_metric_payload(
        ''ACCT_RESULT_EST'',
        coalesce((v_pnl->>''management_result'')::numeric, 0),
        ''Resultado estimado (gerencial)'', ''CURRENCY''
      )
    );
    select coalesce(sum(
      public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
    ), 0)::numeric(19, 4) into v_val
    from public.analytics_journal_economic_lines(p_organization_id) l
    where l.account_type = ''REVENUE''::public.account_type
      and l.entry_date >= v_start and l.entry_date <= v_end;
    v_metrics := v_metrics || jsonb_build_object(
      ''ACCT_REVENUE'',
      public.analytics_metric_payload(''ACCT_REVENUE'', v_val, ''Ingresos contables'', ''CURRENCY'')
    );
  end if;

  if v_feat_cash or v_feat_banks then
    select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_val
    from public.treasury_operations o
    where o.organization_id = p_organization_id
      and o.operation_type = ''COLLECTION''::public.treasury_operation_type
      and o.status = ''POSTED''::public.treasury_operation_status
      and o.operation_date >= v_start and o.operation_date <= v_end;
    select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_prev
    from public.treasury_operations o
    where v_do_compare
      and o.organization_id = p_organization_id
      and o.operation_type = ''COLLECTION''::public.treasury_operation_type
      and o.status = ''POSTED''::public.treasury_operation_status
      and o.operation_date >= v_pstart and o.operation_date <= v_pend;
    v_metrics := v_metrics || jsonb_build_object(
      ''COLLECTIONS_POSTED'',
      public.analytics_metric_payload(
        ''COLLECTIONS_POSTED'', v_val, ''Cobros reales'', ''CURRENCY'', v_prev, v_do_compare
      )
    );
  end if;

  return jsonb_build_object(
    ''metrics'', v_metrics,
    ''sections'', v_sections,
    ''period_start'', v_start,
    ''period_end'', v_end,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''calculation_version'', 1,
    ''generated_by'', v_uid
  );
end;
$$","revoke all on function public.get_dashboard_summary(uuid, text, date, date, text) from public, anon","grant execute on function public.get_dashboard_summary(uuid, text, date, date, text) to authenticated","comment on function public.get_dashboard_summary(uuid, text, date, date, text) is
  ''SECURITY DEFINER intentional: composite dashboard KPIs; membership + dashboard feature; tiles gated by module features/roles.''","comment on function public.get_financial_dashboard(uuid, text, date, date, text) is
  ''SECURITY DEFINER intentional: cash/bank/clearing/AR/AP/collections/payments; role-gated.''","comment on function public.get_ar_aging(uuid, date) is
  ''SECURITY DEFINER intentional: AR aging by due_date vs as_of DATE (no TZ shift on DATE).''","comment on function public.get_ap_aging(uuid, date) is
  ''SECURITY DEFINER intentional: AP aging by due_date vs as_of DATE (no TZ shift on DATE).''"}', 'phase11_dashboard_rpcs'),
	('20261101160000', '{"-- Phase 11: report datasets, alerts evaluation, saved-report RPCs
-- Explicit evaluate only — no background auto-fire in this migration.

-- ---------------------------------------------------------------------------
-- Internal: upsert / resolve alert by dedup_key
-- ---------------------------------------------------------------------------

create or replace function public.analytics_alert_upsert_open(
  p_org_id uuid,
  p_rule_code text,
  p_domain public.analytics_alert_domain,
  p_dedup_key text,
  p_severity public.analytics_alert_severity,
  p_entity_type text,
  p_entity_id uuid,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_now timestamptz := timezone(''utc'', now());
begin
  insert into public.analytics_alert_events (
    organization_id, rule_code, domain, entity_type, entity_id,
    dedup_key, severity, status, first_detected_at, last_detected_at, payload_snapshot
  ) values (
    p_org_id, p_rule_code, p_domain, p_entity_type, p_entity_id,
    p_dedup_key, p_severity, ''OPEN'', v_now, v_now, coalesce(p_payload, ''{}''::jsonb)
  )
  on conflict (organization_id, dedup_key) do update set
    last_detected_at = v_now,
    severity = excluded.severity,
    payload_snapshot = excluded.payload_snapshot,
    domain = excluded.domain,
    entity_type = excluded.entity_type,
    entity_id = excluded.entity_id,
    status = case
      when public.analytics_alert_events.status = ''RESOLVED''::public.analytics_alert_status
        then ''OPEN''::public.analytics_alert_status
      else public.analytics_alert_events.status
    end,
    resolved_at = case
      when public.analytics_alert_events.status = ''RESOLVED''::public.analytics_alert_status
        then null
      else public.analytics_alert_events.resolved_at
    end,
    updated_at = v_now;
end;
$$","revoke all on function public.analytics_alert_upsert_open(
  uuid, text, public.analytics_alert_domain, text, public.analytics_alert_severity, text, uuid, jsonb
) from public, anon, authenticated","create or replace function public.analytics_alert_resolve_missing(
  p_org_id uuid,
  p_rule_code text,
  p_active_dedup_keys text[]
)
returns void
language plpgsql
security definer
set search_path = ''''
as $$
begin
  update public.analytics_alert_events e
  set
    status = ''RESOLVED''::public.analytics_alert_status,
    resolved_at = timezone(''utc'', now()),
    updated_at = timezone(''utc'', now())
  where e.organization_id = p_org_id
    and e.rule_code = p_rule_code
    and e.status in (
      ''OPEN''::public.analytics_alert_status,
      ''ACKNOWLEDGED''::public.analytics_alert_status
    )
    and (
      p_active_dedup_keys is null
      or cardinality(p_active_dedup_keys) = 0
      or e.dedup_key <> all (p_active_dedup_keys)
    );
end;
$$","revoke all on function public.analytics_alert_resolve_missing(uuid, text, text[])
  from public, anon, authenticated","create or replace function public.analytics_alert_rule_enabled(
  p_org_id uuid,
  p_rule_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''''
as $$
  select coalesce(
    (
      select s.enabled
      from public.analytics_alert_settings s
      where s.organization_id = p_org_id
        and s.rule_code = p_rule_code
    ),
    true
  );
$$","revoke all on function public.analytics_alert_rule_enabled(uuid, text)
  from public, anon, authenticated","create or replace function public.analytics_alert_threshold(
  p_org_id uuid,
  p_rule_code text
)
returns jsonb
language sql
stable
security definer
set search_path = ''''
as $$
  select coalesce(
    (
      select s.threshold_json
      from public.analytics_alert_settings s
      where s.organization_id = p_org_id
        and s.rule_code = p_rule_code
    ),
    ''{}''::jsonb
  );
$$","revoke all on function public.analytics_alert_threshold(uuid, text)
  from public, anon, authenticated","-- ---------------------------------------------------------------------------
-- evaluate_analytics_alerts (explicit only)
-- ---------------------------------------------------------------------------

create or replace function public.evaluate_analytics_alerts(p_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_as_of date;
  v_keys text[] := ''{}'';
  v_key text;
  v_opened int := 0;
  v_thr jsonb;
  v_days int;
  v_now timestamptz := timezone(''utc'', now());
  r record;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_any_feature(p_organization_id, array[''dashboard'',''reports'']);

  if not public.has_org_role(
    p_organization_id,
    array[''owner'',''admin'',''accountant'',''manager'']::public.member_role[]
  ) then
    raise exception ''insufficient role to evaluate alerts'';
  end if;

  v_as_of := (timezone(public.analytics_org_timezone(p_organization_id), timezone(''utc'', now())))::date;

  -- AR_OVERDUE
  if public.analytics_alert_rule_enabled(p_organization_id, ''AR_OVERDUE'') then
    v_keys := ''{}'';
    for r in
      select ari.id, ari.open_amount, ari.due_date, ari.customer_id
      from public.accounts_receivable_items ari
      where ari.organization_id = p_organization_id
        and ari.status in (''OPEN'',''PARTIALLY_COLLECTED'')
        and ari.open_amount > 0
        and ari.due_date is not null
        and ari.due_date < v_as_of
    loop
      v_key := ''AR_OVERDUE:'' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''AR_OVERDUE'', ''FINANCE'', v_key, ''WARNING'',
        ''accounts_receivable_items'', r.id,
        jsonb_build_object(''open_amount'', r.open_amount, ''due_date'', r.due_date, ''as_of'', v_as_of)
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''AR_OVERDUE'', v_keys);
  end if;

  -- AP_OVERDUE
  if public.analytics_alert_rule_enabled(p_organization_id, ''AP_OVERDUE'') then
    v_keys := ''{}'';
    for r in
      select api.id, api.open_amount, api.due_date
      from public.accounts_payable_items api
      where api.organization_id = p_organization_id
        and api.status in (''OPEN'',''PARTIALLY_PAID'')
        and api.open_amount > 0
        and api.due_date is not null
        and api.due_date < v_as_of
    loop
      v_key := ''AP_OVERDUE:'' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''AP_OVERDUE'', ''FINANCE'', v_key, ''WARNING'',
        ''accounts_payable_items'', r.id,
        jsonb_build_object(''open_amount'', r.open_amount, ''due_date'', r.due_date, ''as_of'', v_as_of)
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''AP_OVERDUE'', v_keys);
  end if;

  -- TAX_SOURCE_CHANGED
  if public.analytics_alert_rule_enabled(p_organization_id, ''TAX_SOURCE_CHANGED'')
     and public.analytics_feature_enabled(p_organization_id, ''taxes'')
  then
    v_keys := ''{}'';
    for r in
      select tp.id
      from public.tax_periods tp
      where tp.organization_id = p_organization_id
        and tp.source_changed
        and tp.status in (''OPEN'',''IN_REVIEW'',''REVIEWED'',''REOPENED'')
    loop
      v_key := ''TAX_SOURCE_CHANGED:'' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''TAX_SOURCE_CHANGED'', ''TAX'', v_key, ''WARNING'',
        ''tax_periods'', r.id,
        jsonb_build_object(''message'', ''Fuente tributaria modificada — requiere revisión'')
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''TAX_SOURCE_CHANGED'', v_keys);
  end if;

  -- FISCAL_RECON_REQUIRED
  if public.analytics_alert_rule_enabled(p_organization_id, ''FISCAL_RECON_REQUIRED'')
     and public.analytics_feature_enabled(p_organization_id, ''fiscal_invoicing'')
  then
    v_keys := ''{}'';
    for r in
      select fd.id
      from public.fiscal_documents fd
      where fd.organization_id = p_organization_id
        and fd.status = ''RECONCILIATION_REQUIRED''::public.fiscal_document_status
    loop
      v_key := ''FISCAL_RECON_REQUIRED:'' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''FISCAL_RECON_REQUIRED'', ''FISCAL'', v_key, ''CRITICAL'',
        ''fiscal_documents'', r.id,
        jsonb_build_object(''message'', ''Documento fiscal requiere conciliación'')
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''FISCAL_RECON_REQUIRED'', v_keys);
  end if;

  -- POS_RECON_REQUIRED
  if public.analytics_alert_rule_enabled(p_organization_id, ''POS_RECON_REQUIRED'')
     and public.analytics_feature_enabled(p_organization_id, ''pos'')
  then
    v_keys := ''{}'';
    for r in
      select ps.id
      from public.pos_sales ps
      where ps.organization_id = p_organization_id
        and ps.status = ''RECONCILIATION_REQUIRED''::public.pos_sale_status
    loop
      v_key := ''POS_RECON_REQUIRED:'' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''POS_RECON_REQUIRED'', ''POS'', v_key, ''CRITICAL'',
        ''pos_sales'', r.id,
        jsonb_build_object(''message'', ''Venta POS requiere conciliación'')
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''POS_RECON_REQUIRED'', v_keys);
  end if;

  -- STOCK_BELOW_THRESHOLD
  if public.analytics_alert_rule_enabled(p_organization_id, ''STOCK_BELOW_THRESHOLD'')
     and public.analytics_feature_enabled(p_organization_id, ''inventory'')
  then
    v_keys := ''{}'';
    for r in
      select
        t.id as threshold_id,
        t.product_id,
        t.warehouse_id,
        t.minimum_available_quantity,
        coalesce(sum(ss.on_hand_quantity - ss.reserved_quantity), 0)::numeric(18, 4) as available_qty
      from public.analytics_inventory_thresholds t
      left join public.inventory_stock_state ss
        on ss.organization_id = t.organization_id
       and ss.product_id = t.product_id
       and (t.warehouse_id is null or ss.warehouse_id = t.warehouse_id)
      where t.organization_id = p_organization_id
        and t.active
      group by t.id, t.product_id, t.warehouse_id, t.minimum_available_quantity
      having coalesce(sum(ss.on_hand_quantity - ss.reserved_quantity), 0) < t.minimum_available_quantity
    loop
      v_key := ''STOCK_BELOW_THRESHOLD:'' || r.threshold_id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''STOCK_BELOW_THRESHOLD'', ''INVENTORY'', v_key, ''WARNING'',
        ''analytics_inventory_thresholds'', r.threshold_id,
        jsonb_build_object(
          ''product_id'', r.product_id,
          ''warehouse_id'', r.warehouse_id,
          ''available'', r.available_qty,
          ''minimum'', r.minimum_available_quantity
        )
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''STOCK_BELOW_THRESHOLD'', v_keys);
  end if;

  -- CLEARING_AGING (only if threshold set)
  v_thr := public.analytics_alert_threshold(p_organization_id, ''CLEARING_AGING'');
  if public.analytics_alert_rule_enabled(p_organization_id, ''CLEARING_AGING'')
     and (v_thr ? ''max_age_days'')
  then
    v_days := greatest(1, coalesce((v_thr->>''max_age_days'')::int, 7));
    v_keys := ''{}'';
    -- Heuristic: CLEARING balance > 0 and oldest POSTED inflow leg older than threshold
    for r in
      select ta.id as account_id,
             public.treasury_account_balance(ta.id) as bal,
             min(o.operation_date) as oldest_date
      from public.treasury_accounts ta
      join public.treasury_operation_legs l
        on l.treasury_account_id = ta.id
       and l.organization_id = ta.organization_id
      join public.treasury_operations o
        on o.id = l.treasury_operation_id
       and o.organization_id = l.organization_id
      where ta.organization_id = p_organization_id
        and ta.account_type = ''CLEARING''::public.treasury_account_type
        and ta.is_active
        and o.status = ''POSTED''::public.treasury_operation_status
        and l.direction = ''INFLOW''::public.treasury_leg_direction
      group by ta.id
      having public.treasury_account_balance(ta.id) > 0
         and min(o.operation_date) <= (v_as_of - v_days)
    loop
      v_key := ''CLEARING_AGING:'' || r.account_id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''CLEARING_AGING'', ''TREASURY'', v_key, ''INFO'',
        ''treasury_accounts'', r.account_id,
        jsonb_build_object(
          ''balance'', r.bal,
          ''oldest_inflow_date'', r.oldest_date,
          ''max_age_days'', v_days
        )
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''CLEARING_AGING'', v_keys);
  end if;

  return jsonb_build_object(
    ''organization_id'', p_organization_id,
    ''evaluated_at'', v_now,
    ''as_of'', v_as_of,
    ''touched_rules'', v_opened,
    ''evaluated_by'', v_uid
  );
end;
$$","revoke all on function public.evaluate_analytics_alerts(uuid) from public, anon","grant execute on function public.evaluate_analytics_alerts(uuid) to authenticated","comment on function public.evaluate_analytics_alerts(uuid) is
  ''SECURITY DEFINER intentional: explicit alert rebuild/dedup; upserts by dedup_key; resolves when condition gone.''","-- ---------------------------------------------------------------------------
-- ack_analytics_alert
-- ---------------------------------------------------------------------------

create or replace function public.ack_analytics_alert(p_alert_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_row public.analytics_alert_events%rowtype;
begin
  select * into v_row from public.analytics_alert_events where id = p_alert_id;
  if not found then
    raise exception ''alert not found'';
  end if;

  v_uid := public.analytics_assert_member(v_row.organization_id);
  perform public.analytics_assert_any_feature(v_row.organization_id, array[''dashboard'',''reports'']);

  if v_row.status = ''RESOLVED''::public.analytics_alert_status then
    raise exception ''cannot acknowledge a resolved alert'';
  end if;

  update public.analytics_alert_events
  set
    status = ''ACKNOWLEDGED''::public.analytics_alert_status,
    acknowledged_at = timezone(''utc'', now()),
    acknowledged_by = v_uid,
    updated_at = timezone(''utc'', now())
  where id = p_alert_id;

  return jsonb_build_object(''id'', p_alert_id, ''status'', ''ACKNOWLEDGED'', ''acknowledged_by'', v_uid);
end;
$$","revoke all on function public.ack_analytics_alert(uuid) from public, anon","grant execute on function public.ack_analytics_alert(uuid) to authenticated","-- ---------------------------------------------------------------------------
-- Saved reports RPCs
-- ---------------------------------------------------------------------------

create or replace function public.upsert_saved_report(
  p_organization_id uuid,
  p_report_code text,
  p_name text,
  p_filters_json jsonb default ''{}''::jsonb,
  p_columns_json jsonb default ''[]''::jsonb,
  p_sort_json jsonb default ''[]''::jsonb,
  p_visibility text default ''PRIVATE'',
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_id uuid;
  v_vis public.saved_report_visibility;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''reports'');

  v_vis := upper(coalesce(p_visibility, ''PRIVATE''))::public.saved_report_visibility;

  if p_id is not null then
    update public.saved_reports
    set
      report_code = upper(trim(p_report_code)),
      name = trim(p_name),
      filters_json = coalesce(p_filters_json, ''{}''::jsonb),
      columns_json = coalesce(p_columns_json, ''[]''::jsonb),
      sort_json = coalesce(p_sort_json, ''[]''::jsonb),
      visibility = v_vis,
      updated_at = timezone(''utc'', now())
    where id = p_id
      and organization_id = p_organization_id
      and owner_user_id = v_uid
    returning id into v_id;
    if v_id is null then
      raise exception ''saved report not found or not owned'';
    end if;
  else
    insert into public.saved_reports (
      organization_id, owner_user_id, report_code, name,
      filters_json, columns_json, sort_json, visibility
    ) values (
      p_organization_id, v_uid, upper(trim(p_report_code)), trim(p_name),
      coalesce(p_filters_json, ''{}''::jsonb),
      coalesce(p_columns_json, ''[]''::jsonb),
      coalesce(p_sort_json, ''[]''::jsonb),
      v_vis
    )
    returning id into v_id;
  end if;

  return jsonb_build_object(''id'', v_id);
end;
$$","revoke all on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
  from public, anon","grant execute on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
  to authenticated","create or replace function public.list_saved_reports(
  p_organization_id uuid,
  p_report_code text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_rows jsonb;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''reports'');

  select coalesce(jsonb_agg(to_jsonb(s) order by s.updated_at desc), ''[]''::jsonb)
  into v_rows
  from public.saved_reports s
  where s.organization_id = p_organization_id
    and s.active
    and (p_report_code is null or s.report_code = upper(trim(p_report_code)))
    and (
      s.visibility = ''ORGANIZATION''::public.saved_report_visibility
      or s.owner_user_id = v_uid
    );

  return jsonb_build_object(''rows'', v_rows);
end;
$$","revoke all on function public.list_saved_reports(uuid, text) from public, anon","grant execute on function public.list_saved_reports(uuid, text) to authenticated","create or replace function public.delete_saved_report(p_saved_report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_row public.saved_reports%rowtype;
begin
  select * into v_row from public.saved_reports where id = p_saved_report_id;
  if not found then raise exception ''saved report not found''; end if;
  v_uid := public.analytics_assert_member(v_row.organization_id);
  if v_row.owner_user_id is distinct from v_uid then
    raise exception ''only owner can delete saved report'';
  end if;

  update public.saved_reports
  set active = false, updated_at = timezone(''utc'', now())
  where id = p_saved_report_id;

  return jsonb_build_object(''id'', p_saved_report_id, ''active'', false);
end;
$$","revoke all on function public.delete_saved_report(uuid) from public, anon","grant execute on function public.delete_saved_report(uuid) to authenticated","create or replace function public.upsert_analytics_inventory_threshold(
  p_organization_id uuid,
  p_product_id uuid,
  p_minimum_available_quantity numeric,
  p_warehouse_id uuid default null,
  p_warning_quantity numeric default null,
  p_active boolean default true,
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_id uuid;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''inventory'');

  if not public.has_org_role(
    p_organization_id,
    array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[]
  ) then
    raise exception ''insufficient role for inventory thresholds'';
  end if;

  if p_id is not null then
    update public.analytics_inventory_thresholds
    set
      product_id = p_product_id,
      warehouse_id = p_warehouse_id,
      minimum_available_quantity = p_minimum_available_quantity,
      warning_quantity = p_warning_quantity,
      active = coalesce(p_active, true),
      updated_at = timezone(''utc'', now())
    where id = p_id and organization_id = p_organization_id
    returning id into v_id;
    if v_id is null then raise exception ''threshold not found''; end if;
    return jsonb_build_object(''id'', v_id);
  end if;

  select t.id into v_id
  from public.analytics_inventory_thresholds t
  where t.organization_id = p_organization_id
    and t.product_id = p_product_id
    and t.warehouse_id is not distinct from p_warehouse_id
  limit 1;

  if v_id is not null then
    update public.analytics_inventory_thresholds
    set
      minimum_available_quantity = p_minimum_available_quantity,
      warning_quantity = p_warning_quantity,
      active = coalesce(p_active, true),
      updated_at = timezone(''utc'', now())
    where id = v_id;
  else
    insert into public.analytics_inventory_thresholds (
      organization_id, product_id, warehouse_id,
      minimum_available_quantity, warning_quantity, active
    ) values (
      p_organization_id, p_product_id, p_warehouse_id,
      p_minimum_available_quantity, p_warning_quantity, coalesce(p_active, true)
    )
    returning id into v_id;
  end if;

  return jsonb_build_object(''id'', v_id);
end;
$$","revoke all on function public.upsert_analytics_inventory_threshold(
  uuid, uuid, numeric, uuid, numeric, boolean, uuid
) from public, anon","grant execute on function public.upsert_analytics_inventory_threshold(
  uuid, uuid, numeric, uuid, numeric, boolean, uuid
) to authenticated","-- ---------------------------------------------------------------------------
-- get_report_dataset
-- ---------------------------------------------------------------------------

create or replace function public.get_report_dataset(
  p_organization_id uuid,
  p_report_code text,
  p_filters jsonb default ''{}''::jsonb,
  p_limit int default 100,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_code text := upper(trim(p_report_code));
  v_limit int := greatest(1, least(coalesce(p_limit, 100), 500));
  v_offset int := greatest(0, coalesce(p_offset, 0));
  v_from date;
  v_to date;
  v_as_of date;
  v_now timestamptz := timezone(''utc'', now());
  v_rows jsonb := ''[]''::jsonb;
  v_totals jsonb := ''{}''::jsonb;
  v_env text;
  v_pnl jsonb;
  v_bs jsonb;
  v_aging jsonb;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''reports'');

  v_from := nullif(p_filters->>''from'', '''')::date;
  v_to := nullif(p_filters->>''to'', '''')::date;
  v_as_of := coalesce(nullif(p_filters->>''as_of'', '''')::date, v_to, v_from,
    (timezone(public.analytics_org_timezone(p_organization_id), timezone(''utc'', now())))::date);
  v_env := nullif(p_filters->>''fiscal_environment'', '''');

  if v_from is null or v_to is null then
    select pb.period_start, pb.period_end into v_from, v_to
    from public.analytics_period_bounds(
      p_organization_id,
      coalesce(nullif(p_filters->>''period_preset'', ''''), ''THIS_MONTH''),
      v_from, v_to
    ) pb;
  end if;

  case v_code
    when ''AR_AGING'' then
      v_aging := public.get_ar_aging(p_organization_id, v_as_of);
      v_rows := coalesce(v_aging->''rows'', ''[]''::jsonb);
      v_totals := coalesce(v_aging->''totals'', ''{}''::jsonb);

    when ''AP_AGING'' then
      v_aging := public.get_ap_aging(p_organization_id, v_as_of);
      v_rows := coalesce(v_aging->''rows'', ''[]''::jsonb);
      v_totals := coalesce(v_aging->''totals'', ''{}''::jsonb);

    when ''SALES_SUMMARY'' then
      perform public.analytics_assert_feature(p_organization_id, ''fiscal_invoicing'');
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), ''[]''::jsonb),
             jsonb_build_object(
               ''gross'', coalesce(sum(x.gross), 0),
               ''net'', coalesce(sum(x.net), 0),
               ''count'', count(*)::int
             )
      into v_rows, v_totals
      from (
        select
          fd.id,
          fd.issue_date,
          fd.document_number,
          fd.status::text,
          fd.fiscal_environment::text,
          fdt.operation_kind::text,
          (fd.total_amount * public.analytics_fiscal_economic_sign(fdt.operation_kind))::numeric(19, 4) as gross,
          (
            (fd.net_taxed_amount + fd.net_exempt_amount + fd.net_untaxed_amount)
            * public.analytics_fiscal_economic_sign(fdt.operation_kind)
          )::numeric(19, 4) as net
        from public.fiscal_documents fd
        join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
        where fd.organization_id = p_organization_id
          and fd.status = ''AUTHORIZED''::public.fiscal_document_status
          and fd.issue_date >= v_from and fd.issue_date <= v_to
          and (v_env is null or fd.fiscal_environment::text = v_env)
        order by fd.issue_date desc, fd.document_number desc nulls last
        limit v_limit offset v_offset
      ) x;

    when ''CASH_BANK_POSITION'' then
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), ''[]''::jsonb),
             jsonb_build_object(
               ''cash'', public.analytics_treasury_type_balance(p_organization_id, ''CASH''),
               ''bank'', public.analytics_treasury_type_balance(p_organization_id, ''BANK''),
               ''clearing'', public.analytics_treasury_type_balance(p_organization_id, ''CLEARING'')
             )
      into v_rows, v_totals
      from (
        select
          ta.id,
          ta.code,
          ta.name,
          ta.account_type::text,
          public.treasury_account_balance(ta.id)::numeric(19, 4) as balance
        from public.treasury_accounts ta
        where ta.organization_id = p_organization_id
          and ta.is_active
        order by ta.account_type, ta.code
        limit v_limit offset v_offset
      ) x;

    when ''TRIAL_BALANCE_MGMT'' then
      perform public.analytics_assert_feature(p_organization_id, ''accounting'');
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), ''[]''::jsonb),
             jsonb_build_object(
               ''debit_total'', coalesce(sum(x.debit), 0),
               ''credit_total'', coalesce(sum(x.credit), 0)
             )
      into v_rows, v_totals
      from (
        select
          a.code,
          a.name,
          a.account_type::text,
          coalesce(sum(l.debit), 0)::numeric(19, 4) as debit,
          coalesce(sum(l.credit), 0)::numeric(19, 4) as credit,
          public.analytics_signed_balance(
            coalesce(sum(l.debit), 0),
            coalesce(sum(l.credit), 0),
            a.normal_balance
          ) as balance
        from public.accounts a
        left join public.analytics_journal_economic_lines(p_organization_id) l
          on l.account_id = a.id
         and l.entry_date >= v_from
         and l.entry_date <= v_to
        where a.organization_id = p_organization_id
          and a.is_active
          and a.account_type is distinct from ''MEMORANDUM''::public.account_type
        group by a.id, a.code, a.name, a.account_type, a.normal_balance
        having coalesce(sum(l.debit), 0) <> 0 or coalesce(sum(l.credit), 0) <> 0
        order by a.code
        limit v_limit offset v_offset
      ) x;

    when ''MANAGEMENT_PNL'' then
      v_pnl := public.analytics_management_pnl(p_organization_id, v_from, v_to);
      v_rows := jsonb_build_array(v_pnl);
      v_totals := jsonb_build_object(
        ''management_result'', v_pnl->''management_result'',
        ''gross_result'', v_pnl->''gross_result''
      );

    when ''MANAGEMENT_BALANCE_SHEET'' then
      v_bs := public.analytics_management_balance_sheet(p_organization_id, v_as_of);
      v_rows := jsonb_build_array(v_bs);
      v_totals := jsonb_build_object(
        ''assets'', v_bs->''assets'',
        ''liabilities'', v_bs->''liabilities'',
        ''equity'', v_bs->''equity'',
        ''resultado_del_periodo'', v_bs->''resultado_del_periodo'',
        ''difference'', v_bs->''difference'',
        ''status'', v_bs->''status''
      );

    when ''TAX_SUMMARY'' then
      perform public.analytics_assert_feature(p_organization_id, ''taxes'');
      if not public.has_org_role(
        p_organization_id, array[''owner'',''admin'',''accountant'']::public.member_role[]
      ) then
        raise exception ''insufficient role for tax report'';
      end if;
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), ''[]''::jsonb)
      into v_rows
      from (
        select
          tp.id as tax_period_id,
          tp.tax_code::text,
          tp.period_year,
          tp.period_month,
          tp.status::text,
          tp.source_changed,
          td.id as determination_id,
          td.totals_snapshot,
          (td.totals_snapshot->>''saldo_estimado'') as saldo_estimado
        from public.tax_periods tp
        left join public.tax_determinations td
          on td.tax_period_id = tp.id and td.is_current
        where tp.organization_id = p_organization_id
        order by tp.period_year desc, tp.period_month desc nulls last
        limit v_limit offset v_offset
      ) x;
      v_totals := jsonb_build_object(''disclaimer'', ''Saldo estimado — no es DDJJ oficial'');

    when ''INVENTORY_VALUATION'' then
      perform public.analytics_assert_feature(p_organization_id, ''inventory'');
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), ''[]''::jsonb),
             jsonb_build_object(''inventory_value'', coalesce(sum(x.inventory_value), 0))
      into v_rows, v_totals
      from (
        select
          ics.product_id,
          p.sku,
          p.name,
          ics.quantity_on_hand_total,
          ics.average_unit_cost,
          ics.inventory_value
        from public.inventory_cost_state ics
        join public.products p
          on p.id = ics.product_id and p.organization_id = ics.organization_id
        where ics.organization_id = p_organization_id
        order by ics.inventory_value desc
        limit v_limit offset v_offset
      ) x;

    when ''POS_SUMMARY'' then
      perform public.analytics_assert_feature(p_organization_id, ''pos'');
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), ''[]''::jsonb),
             jsonb_build_object(''completed_count'', count(*)::int)
      into v_rows, v_totals
      from (
        select
          ps.id,
          ps.status::text,
          ps.completed_at,
          ps.sales_document_id,
          ps.fiscal_document_id
        from public.pos_sales ps
        where ps.organization_id = p_organization_id
          and ps.status = ''COMPLETED''::public.pos_sale_status
          and (
            (ps.completed_at is not null
              and (timezone(public.analytics_org_timezone(p_organization_id), ps.completed_at))::date
                    between v_from and v_to)
            or (ps.completed_at is null
              and ps.created_at::date between v_from and v_to)
          )
        order by ps.completed_at desc nulls last
        limit v_limit offset v_offset
      ) x;

    when ''TREASURY_MOVEMENTS'' then
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), ''[]''::jsonb),
             jsonb_build_object(
               ''amount_sum'', coalesce(sum(x.amount), 0),
               ''count'', count(*)::int
             )
      into v_rows, v_totals
      from (
        select
          o.id,
          o.internal_number,
          o.operation_type::text,
          o.status::text,
          o.operation_date,
          o.amount,
          o.description
        from public.treasury_operations o
        where o.organization_id = p_organization_id
          and o.status = ''POSTED''::public.treasury_operation_status
          and o.operation_date >= v_from and o.operation_date <= v_to
        order by o.operation_date desc, o.internal_number desc
        limit v_limit offset v_offset
      ) x;

    when ''PURCHASES_SUMMARY'' then
      perform public.analytics_assert_feature(p_organization_id, ''purchases'');
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), ''[]''::jsonb),
             jsonb_build_object(
               ''total'', coalesce(sum(x.signed_total), 0),
               ''count'', count(*)::int
             )
      into v_rows, v_totals
      from (
        select
          pd.id,
          pd.document_type::text,
          pd.document_number,
          pd.issue_date,
          pd.accounting_date,
          pd.status::text,
          pd.total_amount,
          case
            when pd.document_type = ''SUPPLIER_CREDIT_NOTE''::public.purchase_document_type
              then -pd.total_amount
            else pd.total_amount
          end::numeric(19, 4) as signed_total
        from public.purchase_documents pd
        where pd.organization_id = p_organization_id
          and pd.status = ''POSTED''::public.purchase_document_status
          and pd.accounting_date >= v_from and pd.accounting_date <= v_to
        order by pd.accounting_date desc
        limit v_limit offset v_offset
      ) x;

    else
      raise exception ''unsupported report_code: %'', p_report_code;
  end case;

  return jsonb_build_object(
    ''rows'', coalesce(v_rows, ''[]''::jsonb),
    ''totals'', coalesce(v_totals, ''{}''::jsonb),
    ''meta'', jsonb_build_object(
      ''calculation_version'', 1,
      ''data_as_of'', v_now,
      ''generated_at'', v_now,
      ''report_code'', v_code,
      ''period_start'', v_from,
      ''period_end'', v_to,
      ''limit'', v_limit,
      ''offset'', v_offset,
      ''generated_by'', v_uid
    )
  );
end;
$$","revoke all on function public.get_report_dataset(uuid, text, jsonb, int, int) from public, anon","grant execute on function public.get_report_dataset(uuid, text, jsonb, int, int) to authenticated","comment on function public.get_report_dataset(uuid, text, jsonb, int, int) is
  ''SECURITY DEFINER intentional: allowlisted report_code datasets only; requires reports feature.''"}', 'phase11_reports_alerts'),
	('20261101170000', '{"-- Phase 11: security grants documentation + intentional SECURITY DEFINER list
-- Re-revoke internal helpers; grant client RPCs to authenticated only.
-- STAGING ONLY.

-- ---------------------------------------------------------------------------
-- Document: intentional SECURITY DEFINER surface (client-callable)
-- ---------------------------------------------------------------------------
-- get_dashboard_summary(uuid, text, date, date, text)
-- get_financial_dashboard(uuid, text, date, date, text)
-- get_ar_aging(uuid, date)
-- get_ap_aging(uuid, date)
-- analytics_management_pnl(uuid, date, date)
-- analytics_management_balance_sheet(uuid, date)
-- get_report_dataset(uuid, text, jsonb, int, int)
-- evaluate_analytics_alerts(uuid)
-- ack_analytics_alert(uuid)
-- upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
-- list_saved_reports(uuid, text)
-- delete_saved_report(uuid)
-- upsert_analytics_inventory_threshold(uuid, uuid, numeric, uuid, numeric, boolean, uuid)
--
-- Internal (REVOKED from public/anon/authenticated):
-- analytics_assert_service_role, analytics_assert_member, analytics_assert_feature,
-- analytics_assert_any_feature, analytics_feature_enabled, analytics_org_timezone,
-- analytics_period_bounds, analytics_fiscal_economic_sign, analytics_is_economic_journal_status,
-- analytics_journal_economic_lines, analytics_account_is_cogs,
-- analytics_sales_fiscal_net, analytics_sales_fiscal_gross, analytics_signed_balance,
-- analytics_prev_period_bounds, analytics_metric_payload, analytics_ar_open_total,
-- analytics_ap_open_total, analytics_treasury_type_balance, analytics_aging_bucket,
-- analytics_alert_upsert_open, analytics_alert_resolve_missing,
-- analytics_alert_rule_enabled, analytics_alert_threshold

-- ---------------------------------------------------------------------------
-- Re-revoke internals
-- ---------------------------------------------------------------------------

revoke all on function public.analytics_assert_service_role() from public, anon, authenticated","grant execute on function public.analytics_assert_service_role() to service_role","revoke all on function public.analytics_assert_member(uuid) from public, anon, authenticated","revoke all on function public.analytics_feature_enabled(uuid, text) from public, anon, authenticated","revoke all on function public.analytics_assert_feature(uuid, text) from public, anon, authenticated","revoke all on function public.analytics_assert_any_feature(uuid, text[]) from public, anon, authenticated","revoke all on function public.analytics_org_timezone(uuid) from public, anon, authenticated","revoke all on function public.analytics_period_bounds(uuid, text, date, date)
  from public, anon, authenticated","revoke all on function public.analytics_fiscal_economic_sign(public.fiscal_operation_kind)
  from public, anon, authenticated","revoke all on function public.analytics_is_economic_journal_status(public.journal_entry_status)
  from public, anon, authenticated","revoke all on function public.analytics_journal_economic_lines(uuid) from public, anon, authenticated","revoke all on function public.analytics_account_is_cogs(uuid) from public, anon, authenticated","revoke all on function public.analytics_sales_fiscal_net(uuid, date, date, text)
  from public, anon, authenticated","revoke all on function public.analytics_sales_fiscal_gross(uuid, date, date, text)
  from public, anon, authenticated","revoke all on function public.analytics_signed_balance(numeric, numeric, public.normal_balance)
  from public, anon, authenticated","revoke all on function public.analytics_prev_period_bounds(date, date)
  from public, anon, authenticated","revoke all on function public.analytics_metric_payload(text, numeric, text, text, numeric, boolean)
  from public, anon, authenticated","revoke all on function public.analytics_ar_open_total(uuid) from public, anon, authenticated","revoke all on function public.analytics_ap_open_total(uuid) from public, anon, authenticated","revoke all on function public.analytics_treasury_type_balance(uuid, public.treasury_account_type)
  from public, anon, authenticated","revoke all on function public.analytics_aging_bucket(date, date) from public, anon, authenticated","revoke all on function public.analytics_alert_upsert_open(
  uuid, text, public.analytics_alert_domain, text, public.analytics_alert_severity, text, uuid, jsonb
) from public, anon, authenticated","revoke all on function public.analytics_alert_resolve_missing(uuid, text, text[])
  from public, anon, authenticated","revoke all on function public.analytics_alert_rule_enabled(uuid, text)
  from public, anon, authenticated","revoke all on function public.analytics_alert_threshold(uuid, text)
  from public, anon, authenticated","-- ---------------------------------------------------------------------------
-- Client RPCs — authenticated only
-- ---------------------------------------------------------------------------

revoke all on function public.get_dashboard_summary(uuid, text, date, date, text) from public, anon","grant execute on function public.get_dashboard_summary(uuid, text, date, date, text) to authenticated","revoke all on function public.get_financial_dashboard(uuid, text, date, date, text) from public, anon","grant execute on function public.get_financial_dashboard(uuid, text, date, date, text) to authenticated","revoke all on function public.get_ar_aging(uuid, date) from public, anon","grant execute on function public.get_ar_aging(uuid, date) to authenticated","revoke all on function public.get_ap_aging(uuid, date) from public, anon","grant execute on function public.get_ap_aging(uuid, date) to authenticated","revoke all on function public.analytics_management_pnl(uuid, date, date) from public, anon","grant execute on function public.analytics_management_pnl(uuid, date, date) to authenticated","revoke all on function public.analytics_management_balance_sheet(uuid, date) from public, anon","grant execute on function public.analytics_management_balance_sheet(uuid, date) to authenticated","revoke all on function public.get_report_dataset(uuid, text, jsonb, int, int) from public, anon","grant execute on function public.get_report_dataset(uuid, text, jsonb, int, int) to authenticated","revoke all on function public.evaluate_analytics_alerts(uuid) from public, anon","grant execute on function public.evaluate_analytics_alerts(uuid) to authenticated","revoke all on function public.ack_analytics_alert(uuid) from public, anon","grant execute on function public.ack_analytics_alert(uuid) to authenticated","revoke all on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
  from public, anon","grant execute on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
  to authenticated","revoke all on function public.list_saved_reports(uuid, text) from public, anon","grant execute on function public.list_saved_reports(uuid, text) to authenticated","revoke all on function public.delete_saved_report(uuid) from public, anon","grant execute on function public.delete_saved_report(uuid) to authenticated","revoke all on function public.upsert_analytics_inventory_threshold(
  uuid, uuid, numeric, uuid, numeric, boolean, uuid
) from public, anon","grant execute on function public.upsert_analytics_inventory_threshold(
  uuid, uuid, numeric, uuid, numeric, boolean, uuid
) to authenticated","-- ---------------------------------------------------------------------------
-- Table grants (defense in depth)
-- ---------------------------------------------------------------------------

revoke all on table public.analytics_metric_definitions from public, anon","grant select on table public.analytics_metric_definitions to authenticated","grant all on table public.analytics_metric_definitions to service_role","revoke all on table public.saved_reports from public, anon","grant select, insert, update, delete on table public.saved_reports to authenticated","grant all on table public.saved_reports to service_role","revoke all on table public.analytics_alert_settings from public, anon","grant select, insert, update, delete on table public.analytics_alert_settings to authenticated","grant all on table public.analytics_alert_settings to service_role","revoke all on table public.analytics_alert_events from public, anon","grant select on table public.analytics_alert_events to authenticated","grant all on table public.analytics_alert_events to service_role","revoke all on table public.analytics_inventory_thresholds from public, anon","grant select, insert, update, delete on table public.analytics_inventory_thresholds to authenticated","grant all on table public.analytics_inventory_thresholds to service_role","-- ---------------------------------------------------------------------------
-- Extra FK covering indexes (advisor)
-- ---------------------------------------------------------------------------

create index if not exists saved_reports_organization_id_idx
  on public.saved_reports (organization_id)","create index if not exists analytics_alert_settings_organization_id_idx
  on public.analytics_alert_settings (organization_id)","create index if not exists analytics_alert_events_organization_id_idx
  on public.analytics_alert_events (organization_id)","create index if not exists analytics_inventory_thresholds_organization_id_idx
  on public.analytics_inventory_thresholds (organization_id)"}', 'phase11_security_grants'),
	('20261101180000', '{"-- Phase 11: permissions / feature notes
-- Permissions live in TypeScript ROLE_PERMISSIONS (src/config/features.ts),
-- NOT in a DB permissions table. organization_members.role is member_role enum.
-- This migration does NOT seed dashboard.* / reports.* DB rows.
--
-- Optional: enable dashboard + reports for Demo/QA orgs (staging convenience),
-- matching Phase 10 taxes demo enablement pattern.

insert into public.organization_features (organization_id, feature_id, status, enabled_at)
select o.id, fc.id, ''enabled'', timezone(''utc'', now())
from public.organizations o
cross join public.feature_catalog fc
where fc.code in (''dashboard'', ''reports'')
  and (
    o.legal_name ilike ''%demo%''
    or o.commercial_name ilike ''%demo%''
    or o.legal_name ilike ''%qa%''
    or o.commercial_name ilike ''%qa%''
  )
on conflict (organization_id, feature_id) do update
set status = ''enabled'',
    enabled_at = coalesce(public.organization_features.enabled_at, excluded.enabled_at)","comment on function public.get_dashboard_summary(uuid, text, date, date, text) is
  ''SECURITY DEFINER intentional. Authz: membership + feature dashboard + module feature/role gates. Permissions dashboard.* are app-layer (ROLE_PERMISSIONS), not DB.''"}', 'phase11_permissions_seed'),
	('20261101190000', '{"-- Phase 11: attention summary + product margin lineage helper

create or replace function public.get_attention_summary(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_now timestamptz := timezone(''utc'', now());
  v_open int := 0;
  v_ack int := 0;
  v_critical int := 0;
  v_items jsonb := ''[]''::jsonb;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''dashboard'');

  if not public.has_org_role(
    p_organization_id,
    array[''owner'', ''admin'', ''manager'', ''accountant'', ''operator'']::public.member_role[]
  ) then
    raise exception ''insufficient role for attention summary'';
  end if;

  select
    count(*) filter (where status = ''OPEN''),
    count(*) filter (where status = ''ACKNOWLEDGED''),
    count(*) filter (where status in (''OPEN'', ''ACKNOWLEDGED'') and severity = ''CRITICAL'')
  into v_open, v_ack, v_critical
  from public.analytics_alert_events
  where organization_id = p_organization_id
    and status in (''OPEN'', ''ACKNOWLEDGED'');

  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.sort_sev, x.last_detected_at desc), ''[]''::jsonb)
  into v_items
  from (
    select
      e.id,
      e.rule_code,
      e.domain,
      e.severity,
      e.status,
      e.entity_type,
      e.entity_id,
      e.payload_snapshot,
      e.first_detected_at,
      e.last_detected_at,
      case e.severity
        when ''CRITICAL'' then 0
        when ''WARNING'' then 1
        else 2
      end as sort_sev
    from public.analytics_alert_events e
    where e.organization_id = p_organization_id
      and e.status in (''OPEN'', ''ACKNOWLEDGED'')
    order by sort_sev, e.last_detected_at desc
    limit 50
  ) x;

  return jsonb_build_object(
    ''open_count'', coalesce(v_open, 0),
    ''acknowledged_count'', coalesce(v_ack, 0),
    ''critical_count'', coalesce(v_critical, 0),
    ''items'', coalesce(v_items, ''[]''::jsonb),
    ''calculation_version'', 1,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''generated_by'', v_uid,
    ''note'', ''Call evaluate_analytics_alerts explicitly to refresh; dashboard GET does not write alerts.''
  );
end;
$$","revoke all on function public.get_attention_summary(uuid) from public, anon","grant execute on function public.get_attention_summary(uuid) to authenticated","comment on function public.get_attention_summary(uuid) is
  ''SECURITY DEFINER intentional: read-only Attention Center summary; no alert writes.''","-- Product gross margin only when sales-line → inventory ISSUE lineage is proven.
-- Returns status MARGIN_LINEAGE_REQUIRES_REVIEW when incomplete.
create or replace function public.analytics_product_margin_summary(
  p_organization_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_now timestamptz := timezone(''utc'', now());
  v_revenue numeric(19, 4) := 0;
  v_cogs numeric(19, 4) := 0;
  v_linked_lines int := 0;
  v_unlinked_lines int := 0;
  v_status text := ''OK'';
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''fiscal_invoicing'');
  perform public.analytics_assert_feature(p_organization_id, ''inventory'');

  if p_from is null or p_to is null or p_from > p_to then
    raise exception ''invalid period'';
  end if;

  -- Signed net revenue from AUTHORIZED fiscal lines that have source_sales_line_id
  select
    coalesce(sum(
      coalesce(fdl.net_amount, 0) * public.analytics_fiscal_economic_sign(fdt.operation_kind)
    ), 0)::numeric(19, 4),
    count(*) filter (where fdl.source_sales_line_id is not null),
    count(*) filter (where fdl.source_sales_line_id is null)
  into v_revenue, v_linked_lines, v_unlinked_lines
  from public.fiscal_document_lines fdl
  join public.fiscal_documents fd
    on fd.id = fdl.fiscal_document_id
   and fd.organization_id = fdl.organization_id
  join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
  where fdl.organization_id = p_organization_id
    and fd.status = ''AUTHORIZED''::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to;

  -- COGS from inventory ISSUE ledger linked through operation lines → sales_document_line
  select coalesce(sum(abs(ile.total_cost)), 0)::numeric(19, 4)
  into v_cogs
  from public.inventory_ledger_entries ile
  join public.inventory_operation_lines iol
    on iol.id = ile.inventory_operation_line_id
   and iol.organization_id = ile.organization_id
  join public.inventory_operations io
    on io.id = iol.inventory_operation_id
   and io.organization_id = iol.organization_id
  where ile.organization_id = p_organization_id
    and io.status = ''POSTED''::public.inventory_operation_status
    and io.operation_type = ''ISSUE''::public.inventory_operation_type
    and iol.sales_document_line_id is not null
    and exists (
      select 1
      from public.fiscal_document_lines fdl2
      join public.fiscal_documents fd2
        on fd2.id = fdl2.fiscal_document_id
       and fd2.organization_id = fdl2.organization_id
      where fdl2.organization_id = p_organization_id
        and fdl2.source_sales_line_id = iol.sales_document_line_id
        and fd2.status = ''AUTHORIZED''::public.fiscal_document_status
        and fd2.issue_date >= p_from
        and fd2.issue_date <= p_to
    );

  if v_unlinked_lines > 0 or v_linked_lines = 0 then
    v_status := ''MARGIN_LINEAGE_REQUIRES_REVIEW'';
  end if;

  return jsonb_build_object(
    ''status'', v_status,
    ''signed_net_revenue_linked_lines'', v_revenue,
    ''inventory_cogs_linked'', v_cogs,
    ''product_gross_margin'', case
      when v_status = ''OK'' then (v_revenue - v_cogs)::numeric(19, 4)
      else null
    end,
    ''linked_fiscal_lines'', v_linked_lines,
    ''unlinked_fiscal_lines'', v_unlinked_lines,
    ''note'', ''SERVICE/NON_STOCK never receive inventory COGS. Never use default_purchase_price. Never gross-total − COGS.'',
    ''calculation_version'', 1,
    ''period_start'', p_from,
    ''period_end'', p_to,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''generated_by'', v_uid
  );
end;
$$","revoke all on function public.analytics_product_margin_summary(uuid, date, date)
  from public, anon","grant execute on function public.analytics_product_margin_summary(uuid, date, date)
  to authenticated","comment on function public.analytics_product_margin_summary(uuid, date, date) is
  ''SECURITY DEFINER intentional: product margin only with proven sales-line lineage; else MARGIN_LINEAGE_REQUIRES_REVIEW.''"}', 'phase11_attention_product_margin'),
	('20261101200000', '{"-- Fix product margin lineage columns (source_sales_line_id / value_delta)

create or replace function public.analytics_product_margin_summary(
  p_organization_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_now timestamptz := timezone(''utc'', now());
  v_revenue numeric(19, 4) := 0;
  v_cogs numeric(19, 4) := 0;
  v_linked_lines int := 0;
  v_unlinked_lines int := 0;
  v_status text := ''OK'';
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''fiscal_invoicing'');
  perform public.analytics_assert_feature(p_organization_id, ''inventory'');

  if p_from is null or p_to is null or p_from > p_to then
    raise exception ''invalid period'';
  end if;

  select
    coalesce(sum(
      coalesce(fdl.net_amount, 0) * public.analytics_fiscal_economic_sign(fdt.operation_kind)
    ), 0)::numeric(19, 4),
    count(*) filter (where fdl.source_sales_line_id is not null),
    count(*) filter (where fdl.source_sales_line_id is null)
  into v_revenue, v_linked_lines, v_unlinked_lines
  from public.fiscal_document_lines fdl
  join public.fiscal_documents fd
    on fd.id = fdl.fiscal_document_id
   and fd.organization_id = fdl.organization_id
  join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
  where fdl.organization_id = p_organization_id
    and fd.status = ''AUTHORIZED''::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to;

  select coalesce(sum(abs(ile.value_delta)), 0)::numeric(19, 4)
  into v_cogs
  from public.inventory_ledger_entries ile
  join public.inventory_operation_lines iol
    on iol.id = ile.inventory_operation_line_id
   and iol.organization_id = ile.organization_id
  join public.inventory_operations io
    on io.id = iol.inventory_operation_id
   and io.organization_id = iol.organization_id
  where ile.organization_id = p_organization_id
    and io.status = ''POSTED''::public.inventory_operation_status
    and io.operation_type = ''ISSUE''::public.inventory_operation_type
    and iol.source_sales_line_id is not null
    and exists (
      select 1
      from public.fiscal_document_lines fdl2
      join public.fiscal_documents fd2
        on fd2.id = fdl2.fiscal_document_id
       and fd2.organization_id = fdl2.organization_id
      where fdl2.organization_id = p_organization_id
        and fdl2.source_sales_line_id = iol.source_sales_line_id
        and fd2.status = ''AUTHORIZED''::public.fiscal_document_status
        and fd2.issue_date >= p_from
        and fd2.issue_date <= p_to
    );

  if v_unlinked_lines > 0 or v_linked_lines = 0 then
    v_status := ''MARGIN_LINEAGE_REQUIRES_REVIEW'';
  end if;

  return jsonb_build_object(
    ''status'', v_status,
    ''signed_net_revenue_linked_lines'', v_revenue,
    ''inventory_cogs_linked'', v_cogs,
    ''product_gross_margin'', case
      when v_status = ''OK'' then (v_revenue - v_cogs)::numeric(19, 4)
      else null
    end,
    ''linked_fiscal_lines'', v_linked_lines,
    ''unlinked_fiscal_lines'', v_unlinked_lines,
    ''note'', ''SERVICE/NON_STOCK never receive inventory COGS. Never use default_purchase_price. Never gross-total − COGS.'',
    ''calculation_version'', 1,
    ''period_start'', p_from,
    ''period_end'', p_to,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''generated_by'', v_uid
  );
end;
$$"}', 'phase11_fix_product_margin_lineage'),
	('20261101210000', '{"-- Phase 11 STAGING: final authz / reporting / RLS initplan hardening
-- Additive only. Do not modify older migrations.
-- search_path='''' everywhere. Money: numeric(19,4). No FLOAT.

-- =============================================================================
-- 1) saved_reports RLS: (select auth.uid()) initplan fix
-- =============================================================================

drop policy if exists saved_reports_select on public.saved_reports","create policy saved_reports_select on public.saved_reports
  for select to authenticated
  using (
    public.is_org_member(organization_id)
    and (
      visibility = ''ORGANIZATION''::public.saved_report_visibility
      or owner_user_id = (select auth.uid())
    )
  )","drop policy if exists saved_reports_insert on public.saved_reports","create policy saved_reports_insert on public.saved_reports
  for insert to authenticated
  with check (
    public.is_org_member(organization_id)
    and owner_user_id = (select auth.uid())
  )","drop policy if exists saved_reports_update on public.saved_reports","create policy saved_reports_update on public.saved_reports
  for update to authenticated
  using (
    owner_user_id = (select auth.uid())
    and public.is_org_member(organization_id)
  )
  with check (
    owner_user_id = (select auth.uid())
    and public.is_org_member(organization_id)
  )","drop policy if exists saved_reports_delete on public.saved_reports","create policy saved_reports_delete on public.saved_reports
  for delete to authenticated
  using (
    owner_user_id = (select auth.uid())
    and public.is_org_member(organization_id)
  )","-- =============================================================================
-- 2) analytics_capability enum + helpers
-- =============================================================================

do $$ begin
  create type public.analytics_capability as enum (
    ''DASHBOARD_BASIC'',
    ''DASHBOARD_FINANCIAL'',
    ''DASHBOARD_TAX'',
    ''DASHBOARD_INVENTORY'',
    ''DASHBOARD_POS_SENSITIVE'',
    ''REPORT_FINANCIAL'',
    ''REPORT_TAX'',
    ''REPORT_OPERATIONAL'',
    ''ALERT_READ'',
    ''ALERT_ACK'',
    ''ALERT_EVALUATE''
  );
exception when duplicate_object then null;
end $$","create or replace function public.analytics_member_role(p_org_id uuid)
returns public.member_role
language sql
stable
security definer
set search_path = ''''
as $$
  select m.role
  from public.organization_members m
  where m.organization_id = p_org_id
    and m.user_id = (select auth.uid())
    and m.status = ''active''
  limit 1;
$$","revoke all on function public.analytics_member_role(uuid) from public, anon, authenticated","create or replace function public.analytics_has_capability(
  p_org_id uuid,
  p_capability public.analytics_capability
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_role public.member_role;
begin
  v_role := public.analytics_member_role(p_org_id);
  if v_role is null then
    return false;
  end if;

  return case p_capability
    when ''DASHBOARD_BASIC''::public.analytics_capability then
      v_role in (
        ''owner''::public.member_role, ''admin''::public.member_role,
        ''manager''::public.member_role, ''accountant''::public.member_role,
        ''operator''::public.member_role, ''viewer''::public.member_role
      )
    when ''DASHBOARD_FINANCIAL''::public.analytics_capability then
      v_role in (
        ''owner''::public.member_role, ''admin''::public.member_role,
        ''manager''::public.member_role, ''accountant''::public.member_role
      )
    when ''DASHBOARD_TAX''::public.analytics_capability then
      v_role in (
        ''owner''::public.member_role, ''admin''::public.member_role,
        ''accountant''::public.member_role
      )
    when ''DASHBOARD_INVENTORY''::public.analytics_capability then
      v_role in (
        ''owner''::public.member_role, ''admin''::public.member_role,
        ''manager''::public.member_role, ''accountant''::public.member_role
      )
    when ''DASHBOARD_POS_SENSITIVE''::public.analytics_capability then
      v_role in (
        ''owner''::public.member_role, ''admin''::public.member_role,
        ''manager''::public.member_role
      )
    when ''REPORT_FINANCIAL''::public.analytics_capability then
      v_role in (
        ''owner''::public.member_role, ''admin''::public.member_role,
        ''manager''::public.member_role, ''accountant''::public.member_role
      )
    when ''REPORT_TAX''::public.analytics_capability then
      v_role in (
        ''owner''::public.member_role, ''admin''::public.member_role,
        ''accountant''::public.member_role
      )
    when ''REPORT_OPERATIONAL''::public.analytics_capability then
      v_role in (
        ''owner''::public.member_role, ''admin''::public.member_role,
        ''manager''::public.member_role, ''accountant''::public.member_role
      )
    when ''ALERT_READ''::public.analytics_capability then
      v_role in (
        ''owner''::public.member_role, ''admin''::public.member_role,
        ''manager''::public.member_role, ''accountant''::public.member_role,
        ''operator''::public.member_role
      )
    when ''ALERT_ACK''::public.analytics_capability then
      v_role in (
        ''owner''::public.member_role, ''admin''::public.member_role,
        ''manager''::public.member_role, ''accountant''::public.member_role
      )
    when ''ALERT_EVALUATE''::public.analytics_capability then
      v_role in (
        ''owner''::public.member_role, ''admin''::public.member_role,
        ''manager''::public.member_role, ''accountant''::public.member_role
      )
    else false
  end;
end;
$$","revoke all on function public.analytics_has_capability(uuid, public.analytics_capability)
  from public, anon, authenticated","create or replace function public.analytics_assert_capability(
  p_org_id uuid,
  p_capability public.analytics_capability
)
returns void
language plpgsql
stable
security definer
set search_path = ''''
as $$
begin
  if not public.analytics_has_capability(p_org_id, p_capability) then
    raise exception ''insufficient analytics capability: %'', p_capability::text;
  end if;
end;
$$","revoke all on function public.analytics_assert_capability(uuid, public.analytics_capability)
  from public, anon, authenticated","-- =============================================================================
-- 3) get_dashboard_summary — capability-gated tiles
-- =============================================================================

create or replace function public.get_dashboard_summary(
  p_organization_id uuid,
  p_period_preset text default ''THIS_MONTH'',
  p_from date default null,
  p_to date default null,
  p_compare_mode text default ''PREV_PERIOD''
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_start date;
  v_end date;
  v_pstart date;
  v_pend date;
  v_now timestamptz := timezone(''utc'', now());
  v_metrics jsonb := ''{}''::jsonb;
  v_sections jsonb;
  v_do_compare boolean := upper(coalesce(p_compare_mode, ''PREV_PERIOD'')) = ''PREV_PERIOD'';
  v_feat_taxes boolean;
  v_feat_inventory boolean;
  v_feat_pos boolean;
  v_feat_fiscal boolean;
  v_feat_cash boolean;
  v_feat_banks boolean;
  v_feat_accounting boolean;
  v_feat_purchases boolean;
  v_feat_sales boolean;
  v_cap_fin boolean;
  v_cap_tax boolean;
  v_cap_inv boolean;
  v_cap_alert boolean;
  v_val numeric(19, 4);
  v_prev numeric(19, 4);
  v_pnl jsonb;
  v_tax numeric(19, 4);
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''dashboard'');
  perform public.analytics_assert_capability(
    p_organization_id, ''DASHBOARD_BASIC''::public.analytics_capability
  );

  select pb.period_start, pb.period_end into v_start, v_end
  from public.analytics_period_bounds(p_organization_id, p_period_preset, p_from, p_to) pb;

  select pp.period_start, pp.period_end into v_pstart, v_pend
  from public.analytics_prev_period_bounds(v_start, v_end) pp;

  v_feat_taxes := public.analytics_feature_enabled(p_organization_id, ''taxes'');
  v_feat_inventory := public.analytics_feature_enabled(p_organization_id, ''inventory'');
  v_feat_pos := public.analytics_feature_enabled(p_organization_id, ''pos'');
  v_feat_fiscal := public.analytics_feature_enabled(p_organization_id, ''fiscal_invoicing'');
  v_feat_cash := public.analytics_feature_enabled(p_organization_id, ''cash'');
  v_feat_banks := public.analytics_feature_enabled(p_organization_id, ''banks'');
  v_feat_accounting := public.analytics_feature_enabled(p_organization_id, ''accounting'');
  v_feat_purchases := public.analytics_feature_enabled(p_organization_id, ''purchases'');
  v_feat_sales := public.analytics_feature_enabled(p_organization_id, ''sales'');

  v_cap_fin := public.analytics_has_capability(
    p_organization_id, ''DASHBOARD_FINANCIAL''::public.analytics_capability
  );
  v_cap_tax := public.analytics_has_capability(
    p_organization_id, ''DASHBOARD_TAX''::public.analytics_capability
  );
  v_cap_inv := public.analytics_has_capability(
    p_organization_id, ''DASHBOARD_INVENTORY''::public.analytics_capability
  );
  v_cap_alert := public.analytics_has_capability(
    p_organization_id, ''ALERT_READ''::public.analytics_capability
  );

  v_sections := jsonb_build_object(
    ''resumen'', true,
    ''finanzas'', v_cap_fin and (v_feat_cash or v_feat_banks or v_feat_accounting),
    ''ventas'', v_cap_fin and (v_feat_sales or v_feat_fiscal),
    ''compras'', v_cap_fin and v_feat_purchases,
    ''stock'', v_cap_inv and v_feat_inventory,
    ''impuestos'', v_cap_tax and v_feat_taxes,
    ''atencion'', v_cap_alert
  );

  if v_cap_fin and v_feat_fiscal then
    v_val := public.analytics_sales_fiscal_gross(p_organization_id, v_start, v_end, null);
    v_prev := case when v_do_compare
      then public.analytics_sales_fiscal_gross(p_organization_id, v_pstart, v_pend, null)
      else null end;
    v_metrics := v_metrics || jsonb_build_object(
      ''SALES_FISCAL_GROSS_AUTHORIZED'',
      public.analytics_metric_payload(
        ''SALES_FISCAL_GROSS_AUTHORIZED'', v_val,
        ''Ventas facturadas brutas autorizadas'', ''CURRENCY'', v_prev, v_do_compare
      )
    );
    v_val := public.analytics_sales_fiscal_net(p_organization_id, v_start, v_end, null);
    v_prev := case when v_do_compare
      then public.analytics_sales_fiscal_net(p_organization_id, v_pstart, v_pend, null)
      else null end;
    v_metrics := v_metrics || jsonb_build_object(
      ''SALES_FISCAL_NET_AUTHORIZED'',
      public.analytics_metric_payload(
        ''SALES_FISCAL_NET_AUTHORIZED'', v_val,
        ''Ventas facturadas netas autorizadas'', ''CURRENCY'', v_prev, v_do_compare
      )
    );
  end if;

  if v_cap_fin and (v_feat_cash or v_feat_banks) then
    v_metrics := v_metrics || jsonb_build_object(
      ''CASH_INTERNAL'',
      public.analytics_metric_payload(
        ''CASH_INTERNAL'',
        public.analytics_treasury_type_balance(p_organization_id, ''CASH''::public.treasury_account_type),
        ''Saldo de caja interno'', ''CURRENCY''
      )
    );
    v_metrics := v_metrics || jsonb_build_object(
      ''BANK_INTERNAL'',
      public.analytics_metric_payload(
        ''BANK_INTERNAL'',
        public.analytics_treasury_type_balance(p_organization_id, ''BANK''::public.treasury_account_type),
        ''Saldo bancario interno'', ''CURRENCY''
      )
    );
  end if;

  if v_cap_fin and v_feat_pos then
    v_metrics := v_metrics || jsonb_build_object(
      ''CLEARING_PENDING'',
      public.analytics_metric_payload(
        ''CLEARING_PENDING'',
        public.analytics_treasury_type_balance(p_organization_id, ''CLEARING''::public.treasury_account_type),
        ''Tarjetas/QR pendientes'', ''CURRENCY''
      )
    );
  end if;

  if v_cap_fin and v_feat_sales then
    v_metrics := v_metrics || jsonb_build_object(
      ''AR_OPEN'',
      public.analytics_metric_payload(
        ''AR_OPEN'', public.analytics_ar_open_total(p_organization_id),
        ''Cuentas por cobrar abiertas'', ''CURRENCY''
      )
    );
  end if;

  if v_cap_fin and v_feat_purchases then
    v_metrics := v_metrics || jsonb_build_object(
      ''AP_OPEN'',
      public.analytics_metric_payload(
        ''AP_OPEN'', public.analytics_ap_open_total(p_organization_id),
        ''Cuentas por pagar abiertas'', ''CURRENCY''
      )
    );
  end if;

  if v_cap_inv and v_feat_inventory then
    select coalesce(sum(ics.inventory_value), 0)::numeric(19, 4) into v_val
    from public.inventory_cost_state ics
    where ics.organization_id = p_organization_id;
    v_metrics := v_metrics || jsonb_build_object(
      ''INVENTORY_VALUE'',
      public.analytics_metric_payload(''INVENTORY_VALUE'', v_val, ''Inventario valorizado'', ''CURRENCY'')
    );
  end if;

  if v_cap_tax and v_feat_taxes then
    select coalesce(
      (
        select (td.totals_snapshot->>''saldo_estimado'')::numeric(19, 4)
        from public.tax_determinations td
        join public.tax_periods tp on tp.id = td.tax_period_id
        where td.organization_id = p_organization_id
          and td.is_current
          and td.totals_snapshot ? ''saldo_estimado''
        order by tp.period_end desc nulls last, td.calculated_at desc nulls last
        limit 1
      ),
      0
    ) into v_tax;
    v_metrics := v_metrics || jsonb_build_object(
      ''TAX_IVA_SALDO_ESTIMADO'',
      public.analytics_metric_payload(
        ''TAX_IVA_SALDO_ESTIMADO'', coalesce(v_tax, 0),
        ''IVA — saldo estimado'', ''CURRENCY''
      ) || jsonb_build_object(
        ''disclaimer'', ''Saldo estimado según Contabilium — no es IVA definitivo a pagar''
      )
    );
  end if;

  if v_cap_fin and v_feat_accounting then
    v_pnl := public.analytics_management_pnl(p_organization_id, v_start, v_end);
    v_metrics := v_metrics || jsonb_build_object(
      ''MANAGEMENT_GROSS_RESULT'',
      public.analytics_metric_payload(
        ''MANAGEMENT_GROSS_RESULT'',
        coalesce((v_pnl->>''gross_result'')::numeric, 0),
        ''Resultado bruto gerencial'', ''CURRENCY''
      )
    );
    v_metrics := v_metrics || jsonb_build_object(
      ''ACCT_RESULT_EST'',
      public.analytics_metric_payload(
        ''ACCT_RESULT_EST'',
        coalesce((v_pnl->>''management_result'')::numeric, 0),
        ''Resultado estimado (gerencial)'', ''CURRENCY''
      )
    );
    select coalesce(sum(
      public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
    ), 0)::numeric(19, 4) into v_val
    from public.analytics_journal_economic_lines(p_organization_id) l
    where l.account_type = ''REVENUE''::public.account_type
      and l.entry_date >= v_start and l.entry_date <= v_end;
    v_metrics := v_metrics || jsonb_build_object(
      ''ACCT_REVENUE'',
      public.analytics_metric_payload(''ACCT_REVENUE'', v_val, ''Ingresos contables'', ''CURRENCY'')
    );
  end if;

  if v_cap_fin and (v_feat_cash or v_feat_banks) then
    select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_val
    from public.treasury_operations o
    where o.organization_id = p_organization_id
      and o.operation_type = ''COLLECTION''::public.treasury_operation_type
      and o.status = ''POSTED''::public.treasury_operation_status
      and o.operation_date >= v_start and o.operation_date <= v_end;
    select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_prev
    from public.treasury_operations o
    where v_do_compare
      and o.organization_id = p_organization_id
      and o.operation_type = ''COLLECTION''::public.treasury_operation_type
      and o.status = ''POSTED''::public.treasury_operation_status
      and o.operation_date >= v_pstart and o.operation_date <= v_pend;
    v_metrics := v_metrics || jsonb_build_object(
      ''COLLECTIONS_POSTED'',
      public.analytics_metric_payload(
        ''COLLECTIONS_POSTED'', v_val, ''Cobros reales'', ''CURRENCY'', v_prev, v_do_compare
      )
    );
  end if;

  return jsonb_build_object(
    ''metrics'', v_metrics,
    ''sections'', v_sections,
    ''period_start'', v_start,
    ''period_end'', v_end,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''calculation_version'', 1,
    ''generated_by'', v_uid
  );
end;
$$","revoke all on function public.get_dashboard_summary(uuid, text, date, date, text) from public, anon","grant execute on function public.get_dashboard_summary(uuid, text, date, date, text) to authenticated","comment on function public.get_dashboard_summary(uuid, text, date, date, text) is
  ''SECURITY DEFINER intentional: dashboard KPIs; membership + dashboard feature + analytics_capability gates.''","-- =============================================================================
-- 4) get_financial_dashboard / get_ar_aging / get_ap_aging
-- =============================================================================

create or replace function public.get_financial_dashboard(
  p_organization_id uuid,
  p_period_preset text default ''THIS_MONTH'',
  p_from date default null,
  p_to date default null,
  p_compare_mode text default ''PREV_PERIOD''
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_start date;
  v_end date;
  v_pstart date;
  v_pend date;
  v_now timestamptz := timezone(''utc'', now());
  v_metrics jsonb := ''{}''::jsonb;
  v_do_compare boolean := upper(coalesce(p_compare_mode, ''PREV_PERIOD'')) = ''PREV_PERIOD'';
  v_cash numeric(19, 4);
  v_bank numeric(19, 4);
  v_clearing numeric(19, 4);
  v_coll numeric(19, 4);
  v_pay numeric(19, 4);
  v_coll_prev numeric(19, 4);
  v_pay_prev numeric(19, 4);
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''dashboard'');
  perform public.analytics_assert_capability(
    p_organization_id, ''DASHBOARD_FINANCIAL''::public.analytics_capability
  );

  select pb.period_start, pb.period_end
  into v_start, v_end
  from public.analytics_period_bounds(p_organization_id, p_period_preset, p_from, p_to) pb;

  select pp.period_start, pp.period_end into v_pstart, v_pend
  from public.analytics_prev_period_bounds(v_start, v_end) pp;

  v_cash := public.analytics_treasury_type_balance(p_organization_id, ''CASH''::public.treasury_account_type);
  v_bank := public.analytics_treasury_type_balance(p_organization_id, ''BANK''::public.treasury_account_type);
  v_clearing := public.analytics_treasury_type_balance(p_organization_id, ''CLEARING''::public.treasury_account_type);

  select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_coll
  from public.treasury_operations o
  where o.organization_id = p_organization_id
    and o.operation_type = ''COLLECTION''::public.treasury_operation_type
    and o.status = ''POSTED''::public.treasury_operation_status
    and o.operation_date >= v_start and o.operation_date <= v_end;

  select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_pay
  from public.treasury_operations o
  where o.organization_id = p_organization_id
    and o.operation_type = ''PAYMENT''::public.treasury_operation_type
    and o.status = ''POSTED''::public.treasury_operation_status
    and o.operation_date >= v_start and o.operation_date <= v_end;

  if v_do_compare then
    select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_coll_prev
    from public.treasury_operations o
    where o.organization_id = p_organization_id
      and o.operation_type = ''COLLECTION''::public.treasury_operation_type
      and o.status = ''POSTED''::public.treasury_operation_status
      and o.operation_date >= v_pstart and o.operation_date <= v_pend;

    select coalesce(sum(o.amount), 0)::numeric(19, 4) into v_pay_prev
    from public.treasury_operations o
    where o.organization_id = p_organization_id
      and o.operation_type = ''PAYMENT''::public.treasury_operation_type
      and o.status = ''POSTED''::public.treasury_operation_status
      and o.operation_date >= v_pstart and o.operation_date <= v_pend;
  end if;

  v_metrics := v_metrics
    || jsonb_build_object(
      ''CASH_INTERNAL'',
      public.analytics_metric_payload(''CASH_INTERNAL'', v_cash, ''Saldo de caja interno'', ''CURRENCY'')
    )
    || jsonb_build_object(
      ''BANK_INTERNAL'',
      public.analytics_metric_payload(''BANK_INTERNAL'', v_bank, ''Saldo bancario interno'', ''CURRENCY'')
    )
    || jsonb_build_object(
      ''CLEARING_PENDING'',
      public.analytics_metric_payload(''CLEARING_PENDING'', v_clearing, ''Tarjetas/QR pendientes'', ''CURRENCY'')
    )
    || jsonb_build_object(
      ''AR_OPEN'',
      public.analytics_metric_payload(
        ''AR_OPEN'', public.analytics_ar_open_total(p_organization_id),
        ''Cuentas por cobrar abiertas'', ''CURRENCY''
      )
    )
    || jsonb_build_object(
      ''AP_OPEN'',
      public.analytics_metric_payload(
        ''AP_OPEN'', public.analytics_ap_open_total(p_organization_id),
        ''Cuentas por pagar abiertas'', ''CURRENCY''
      )
    )
    || jsonb_build_object(
      ''COLLECTIONS_POSTED'',
      public.analytics_metric_payload(
        ''COLLECTIONS_POSTED'', v_coll, ''Cobros reales'', ''CURRENCY'',
        v_coll_prev, v_do_compare
      )
    )
    || jsonb_build_object(
      ''PAYMENTS_POSTED'',
      public.analytics_metric_payload(
        ''PAYMENTS_POSTED'', v_pay, ''Pagos reales'', ''CURRENCY'',
        v_pay_prev, v_do_compare
      )
    );

  return jsonb_build_object(
    ''metrics'', v_metrics,
    ''period_start'', v_start,
    ''period_end'', v_end,
    ''compare_period_start'', case when v_do_compare then to_jsonb(v_pstart) else ''null''::jsonb end,
    ''compare_period_end'', case when v_do_compare then to_jsonb(v_pend) else ''null''::jsonb end,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''calculation_version'', 1
  );
end;
$$","revoke all on function public.get_financial_dashboard(uuid, text, date, date, text) from public, anon","grant execute on function public.get_financial_dashboard(uuid, text, date, date, text) to authenticated","comment on function public.get_financial_dashboard(uuid, text, date, date, text) is
  ''SECURITY DEFINER intentional: financial dashboard; requires DASHBOARD_FINANCIAL capability.''","create or replace function public.get_ar_aging(
  p_organization_id uuid,
  p_as_of date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_as_of date;
  v_now timestamptz := timezone(''utc'', now());
  v_rows jsonb;
  v_totals jsonb;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_any_feature(p_organization_id, array[''dashboard'',''reports'',''sales'']);
  perform public.analytics_assert_capability(
    p_organization_id, ''DASHBOARD_FINANCIAL''::public.analytics_capability
  );

  v_as_of := coalesce(
    p_as_of,
    (timezone(public.analytics_org_timezone(p_organization_id), timezone(''utc'', now())))::date
  );

  select coalesce(jsonb_agg(x.row_obj order by x.sort_key), ''[]''::jsonb)
  into v_rows
  from (
    select
      case b.bucket
        when ''NOT_DUE'' then 1
        when ''OVERDUE_1_30'' then 2
        when ''OVERDUE_31_60'' then 3
        when ''OVERDUE_61_90'' then 4
        when ''OVERDUE_90_PLUS'' then 5
        else 6
      end as sort_key,
      jsonb_build_object(
        ''bucket'', b.bucket,
        ''amount'', b.amount,
        ''count'', b.cnt
      ) as row_obj
    from (
      select
        public.analytics_aging_bucket(ari.due_date, v_as_of) as bucket,
        coalesce(sum(
          case
            when ari.direction = ''AR_INCREASE''::public.accounts_receivable_direction then ari.open_amount
            else -ari.open_amount
          end
        ), 0)::numeric(19, 4) as amount,
        count(*)::int as cnt
      from public.accounts_receivable_items ari
      where ari.organization_id = p_organization_id
        and ari.status in (
          ''OPEN''::public.accounts_receivable_status,
          ''PARTIALLY_COLLECTED''::public.accounts_receivable_status
        )
        and ari.open_amount > 0
      group by 1
    ) b
  ) x;

  select jsonb_object_agg(e->>''bucket'', e->''amount'')
  into v_totals
  from jsonb_array_elements(v_rows) e;

  return jsonb_build_object(
    ''as_of'', v_as_of,
    ''rows'', v_rows,
    ''totals'', coalesce(v_totals, ''{}''::jsonb),
    ''open_total'', public.analytics_ar_open_total(p_organization_id),
    ''calculation_version'', 1,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''generated_by'', v_uid
  );
end;
$$","revoke all on function public.get_ar_aging(uuid, date) from public, anon","grant execute on function public.get_ar_aging(uuid, date) to authenticated","comment on function public.get_ar_aging(uuid, date) is
  ''SECURITY DEFINER intentional: AR aging; requires DASHBOARD_FINANCIAL.''","create or replace function public.get_ap_aging(
  p_organization_id uuid,
  p_as_of date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_as_of date;
  v_now timestamptz := timezone(''utc'', now());
  v_rows jsonb;
  v_totals jsonb;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_any_feature(p_organization_id, array[''dashboard'',''reports'',''purchases'']);
  perform public.analytics_assert_capability(
    p_organization_id, ''DASHBOARD_FINANCIAL''::public.analytics_capability
  );

  v_as_of := coalesce(
    p_as_of,
    (timezone(public.analytics_org_timezone(p_organization_id), timezone(''utc'', now())))::date
  );

  select coalesce(jsonb_agg(x.row_obj order by x.sort_key), ''[]''::jsonb)
  into v_rows
  from (
    select
      case b.bucket
        when ''NOT_DUE'' then 1
        when ''OVERDUE_1_30'' then 2
        when ''OVERDUE_31_60'' then 3
        when ''OVERDUE_61_90'' then 4
        when ''OVERDUE_90_PLUS'' then 5
        else 6
      end as sort_key,
      jsonb_build_object(
        ''bucket'', b.bucket,
        ''amount'', b.amount,
        ''count'', b.cnt
      ) as row_obj
    from (
      select
        public.analytics_aging_bucket(api.due_date, v_as_of) as bucket,
        coalesce(sum(
          case
            when api.direction = ''AP_INCREASE''::public.accounts_payable_direction then api.open_amount
            else -api.open_amount
          end
        ), 0)::numeric(19, 4) as amount,
        count(*)::int as cnt
      from public.accounts_payable_items api
      where api.organization_id = p_organization_id
        and api.status in (
          ''OPEN''::public.accounts_payable_status,
          ''PARTIALLY_PAID''::public.accounts_payable_status
        )
        and api.open_amount > 0
      group by 1
    ) b
  ) x;

  select jsonb_object_agg(e->>''bucket'', e->''amount'')
  into v_totals
  from jsonb_array_elements(v_rows) e;

  return jsonb_build_object(
    ''as_of'', v_as_of,
    ''rows'', v_rows,
    ''totals'', coalesce(v_totals, ''{}''::jsonb),
    ''open_total'', public.analytics_ap_open_total(p_organization_id),
    ''calculation_version'', 1,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''generated_by'', v_uid
  );
end;
$$","revoke all on function public.get_ap_aging(uuid, date) from public, anon","grant execute on function public.get_ap_aging(uuid, date) to authenticated","comment on function public.get_ap_aging(uuid, date) is
  ''SECURITY DEFINER intentional: AP aging; requires DASHBOARD_FINANCIAL.''","-- =============================================================================
-- 5) get_attention_summary — ALERT_READ + domain sanitization
-- =============================================================================

create or replace function public.get_attention_summary(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_now timestamptz := timezone(''utc'', now());
  v_open int := 0;
  v_ack int := 0;
  v_critical int := 0;
  v_items jsonb := ''[]''::jsonb;
  v_cap_fin boolean;
  v_cap_tax boolean;
  v_cap_pos boolean;
  v_sanitize boolean;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''dashboard'');
  perform public.analytics_assert_capability(
    p_organization_id, ''ALERT_READ''::public.analytics_capability
  );

  v_cap_fin := public.analytics_has_capability(
    p_organization_id, ''DASHBOARD_FINANCIAL''::public.analytics_capability
  );
  v_cap_tax := public.analytics_has_capability(
    p_organization_id, ''DASHBOARD_TAX''::public.analytics_capability
  );
  v_cap_pos := public.analytics_has_capability(
    p_organization_id, ''DASHBOARD_POS_SENSITIVE''::public.analytics_capability
  );
  v_sanitize := not v_cap_fin;

  select
    count(*) filter (where status = ''OPEN''),
    count(*) filter (where status = ''ACKNOWLEDGED''),
    count(*) filter (where status in (''OPEN'', ''ACKNOWLEDGED'') and severity = ''CRITICAL'')
  into v_open, v_ack, v_critical
  from public.analytics_alert_events e
  where e.organization_id = p_organization_id
    and e.status in (''OPEN'', ''ACKNOWLEDGED'')
    and (
      case
        when not v_cap_fin then e.domain in (
          ''POS''::public.analytics_alert_domain,
          ''FISCAL''::public.analytics_alert_domain,
          ''INVENTORY''::public.analytics_alert_domain
        )
        else true
      end
    )
    and (v_cap_tax or e.domain is distinct from ''TAX''::public.analytics_alert_domain)
    and (
      v_cap_pos
      or e.domain is distinct from ''POS''::public.analytics_alert_domain
      or e.rule_code not ilike ''%CASH%''
    )
    and (
      v_cap_pos
      or e.rule_code not ilike ''%DIFF%''
    );

  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.sort_sev, x.last_detected_at desc), ''[]''::jsonb)
  into v_items
  from (
    select
      e.id,
      e.rule_code,
      e.domain,
      e.severity,
      e.status,
      e.entity_type,
      e.entity_id,
      case
        when v_sanitize then jsonb_build_object(
          ''rule_code'', e.rule_code,
          ''message'', coalesce(e.payload_snapshot->>''message'', e.rule_code)
        )
        else e.payload_snapshot
      end as payload_snapshot,
      e.first_detected_at,
      e.last_detected_at,
      case e.severity
        when ''CRITICAL'' then 0
        when ''WARNING'' then 1
        else 2
      end as sort_sev
    from public.analytics_alert_events e
    where e.organization_id = p_organization_id
      and e.status in (''OPEN'', ''ACKNOWLEDGED'')
      and (
        case
          when not v_cap_fin then e.domain in (
            ''POS''::public.analytics_alert_domain,
            ''FISCAL''::public.analytics_alert_domain,
            ''INVENTORY''::public.analytics_alert_domain
          )
          else true
        end
      )
      and (v_cap_tax or e.domain is distinct from ''TAX''::public.analytics_alert_domain)
      and (
        v_cap_pos
        or e.domain is distinct from ''POS''::public.analytics_alert_domain
        or e.rule_code not ilike ''%CASH%''
      )
      and (
        v_cap_pos
        or e.rule_code not ilike ''%DIFF%''
      )
    order by sort_sev, e.last_detected_at desc
    limit 50
  ) x;

  return jsonb_build_object(
    ''open_count'', coalesce(v_open, 0),
    ''acknowledged_count'', coalesce(v_ack, 0),
    ''critical_count'', coalesce(v_critical, 0),
    ''items'', coalesce(v_items, ''[]''::jsonb),
    ''sanitized'', v_sanitize,
    ''calculation_version'', 1,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''generated_by'', v_uid,
    ''note'', ''Call evaluate_analytics_alerts explicitly to refresh; dashboard GET does not write alerts.''
  );
end;
$$","revoke all on function public.get_attention_summary(uuid) from public, anon","grant execute on function public.get_attention_summary(uuid) to authenticated","comment on function public.get_attention_summary(uuid) is
  ''SECURITY DEFINER intentional: Attention Center; ALERT_READ; non-FINANCIAL roles get sanitized operational alerts.''","-- =============================================================================
-- 6) ack_analytics_alert — ALERT_ACK
-- =============================================================================

create or replace function public.ack_analytics_alert(p_alert_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_row public.analytics_alert_events%rowtype;
begin
  select * into v_row from public.analytics_alert_events where id = p_alert_id;
  if not found then
    raise exception ''alert not found'';
  end if;

  v_uid := public.analytics_assert_member(v_row.organization_id);
  perform public.analytics_assert_any_feature(v_row.organization_id, array[''dashboard'',''reports'']);
  perform public.analytics_assert_capability(
    v_row.organization_id, ''ALERT_ACK''::public.analytics_capability
  );

  if v_row.status = ''RESOLVED''::public.analytics_alert_status then
    raise exception ''cannot acknowledge a resolved alert'';
  end if;

  update public.analytics_alert_events
  set
    status = ''ACKNOWLEDGED''::public.analytics_alert_status,
    acknowledged_at = timezone(''utc'', now()),
    acknowledged_by = v_uid,
    updated_at = timezone(''utc'', now())
  where id = p_alert_id;

  return jsonb_build_object(''id'', p_alert_id, ''status'', ''ACKNOWLEDGED'', ''acknowledged_by'', v_uid);
end;
$$","revoke all on function public.ack_analytics_alert(uuid) from public, anon","grant execute on function public.ack_analytics_alert(uuid) to authenticated","comment on function public.ack_analytics_alert(uuid) is
  ''SECURITY DEFINER intentional: acknowledge alert; requires ALERT_ACK capability.''","-- =============================================================================
-- 7) evaluate_analytics_alerts — ALERT_EVALUATE
-- =============================================================================

create or replace function public.evaluate_analytics_alerts(p_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_as_of date;
  v_keys text[] := ''{}'';
  v_key text;
  v_opened int := 0;
  v_thr jsonb;
  v_days int;
  v_now timestamptz := timezone(''utc'', now());
  r record;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_any_feature(p_organization_id, array[''dashboard'',''reports'']);
  perform public.analytics_assert_capability(
    p_organization_id, ''ALERT_EVALUATE''::public.analytics_capability
  );

  v_as_of := (timezone(public.analytics_org_timezone(p_organization_id), timezone(''utc'', now())))::date;

  if public.analytics_alert_rule_enabled(p_organization_id, ''AR_OVERDUE'') then
    v_keys := ''{}'';
    for r in
      select ari.id, ari.open_amount, ari.due_date, ari.customer_id
      from public.accounts_receivable_items ari
      where ari.organization_id = p_organization_id
        and ari.status in (''OPEN'',''PARTIALLY_COLLECTED'')
        and ari.open_amount > 0
        and ari.due_date is not null
        and ari.due_date < v_as_of
    loop
      v_key := ''AR_OVERDUE:'' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''AR_OVERDUE'', ''FINANCE'', v_key, ''WARNING'',
        ''accounts_receivable_items'', r.id,
        jsonb_build_object(''open_amount'', r.open_amount, ''due_date'', r.due_date, ''as_of'', v_as_of)
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''AR_OVERDUE'', v_keys);
  end if;

  if public.analytics_alert_rule_enabled(p_organization_id, ''AP_OVERDUE'') then
    v_keys := ''{}'';
    for r in
      select api.id, api.open_amount, api.due_date
      from public.accounts_payable_items api
      where api.organization_id = p_organization_id
        and api.status in (''OPEN'',''PARTIALLY_PAID'')
        and api.open_amount > 0
        and api.due_date is not null
        and api.due_date < v_as_of
    loop
      v_key := ''AP_OVERDUE:'' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''AP_OVERDUE'', ''FINANCE'', v_key, ''WARNING'',
        ''accounts_payable_items'', r.id,
        jsonb_build_object(''open_amount'', r.open_amount, ''due_date'', r.due_date, ''as_of'', v_as_of)
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''AP_OVERDUE'', v_keys);
  end if;

  if public.analytics_alert_rule_enabled(p_organization_id, ''TAX_SOURCE_CHANGED'')
     and public.analytics_feature_enabled(p_organization_id, ''taxes'')
  then
    v_keys := ''{}'';
    for r in
      select tp.id
      from public.tax_periods tp
      where tp.organization_id = p_organization_id
        and tp.source_changed
        and tp.status in (''OPEN'',''IN_REVIEW'',''REVIEWED'',''REOPENED'')
    loop
      v_key := ''TAX_SOURCE_CHANGED:'' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''TAX_SOURCE_CHANGED'', ''TAX'', v_key, ''WARNING'',
        ''tax_periods'', r.id,
        jsonb_build_object(''message'', ''Fuente tributaria modificada — requiere revisión'')
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''TAX_SOURCE_CHANGED'', v_keys);
  end if;

  if public.analytics_alert_rule_enabled(p_organization_id, ''FISCAL_RECON_REQUIRED'')
     and public.analytics_feature_enabled(p_organization_id, ''fiscal_invoicing'')
  then
    v_keys := ''{}'';
    for r in
      select fd.id
      from public.fiscal_documents fd
      where fd.organization_id = p_organization_id
        and fd.status = ''RECONCILIATION_REQUIRED''::public.fiscal_document_status
    loop
      v_key := ''FISCAL_RECON_REQUIRED:'' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''FISCAL_RECON_REQUIRED'', ''FISCAL'', v_key, ''CRITICAL'',
        ''fiscal_documents'', r.id,
        jsonb_build_object(''message'', ''Documento fiscal requiere conciliación'')
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''FISCAL_RECON_REQUIRED'', v_keys);
  end if;

  if public.analytics_alert_rule_enabled(p_organization_id, ''POS_RECON_REQUIRED'')
     and public.analytics_feature_enabled(p_organization_id, ''pos'')
  then
    v_keys := ''{}'';
    for r in
      select ps.id
      from public.pos_sales ps
      where ps.organization_id = p_organization_id
        and ps.status = ''RECONCILIATION_REQUIRED''::public.pos_sale_status
    loop
      v_key := ''POS_RECON_REQUIRED:'' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''POS_RECON_REQUIRED'', ''POS'', v_key, ''CRITICAL'',
        ''pos_sales'', r.id,
        jsonb_build_object(''message'', ''Venta POS requiere conciliación'')
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''POS_RECON_REQUIRED'', v_keys);
  end if;

  if public.analytics_alert_rule_enabled(p_organization_id, ''STOCK_BELOW_THRESHOLD'')
     and public.analytics_feature_enabled(p_organization_id, ''inventory'')
  then
    v_keys := ''{}'';
    for r in
      select
        t.id as threshold_id,
        t.product_id,
        t.warehouse_id,
        t.minimum_available_quantity,
        coalesce(sum(ss.on_hand_quantity - ss.reserved_quantity), 0)::numeric(18, 4) as available_qty
      from public.analytics_inventory_thresholds t
      left join public.inventory_stock_state ss
        on ss.organization_id = t.organization_id
       and ss.product_id = t.product_id
       and (t.warehouse_id is null or ss.warehouse_id = t.warehouse_id)
      where t.organization_id = p_organization_id
        and t.active
      group by t.id, t.product_id, t.warehouse_id, t.minimum_available_quantity
      having coalesce(sum(ss.on_hand_quantity - ss.reserved_quantity), 0) < t.minimum_available_quantity
    loop
      v_key := ''STOCK_BELOW_THRESHOLD:'' || r.threshold_id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''STOCK_BELOW_THRESHOLD'', ''INVENTORY'', v_key, ''WARNING'',
        ''analytics_inventory_thresholds'', r.threshold_id,
        jsonb_build_object(
          ''product_id'', r.product_id,
          ''warehouse_id'', r.warehouse_id,
          ''available'', r.available_qty,
          ''minimum'', r.minimum_available_quantity
        )
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''STOCK_BELOW_THRESHOLD'', v_keys);
  end if;

  v_thr := public.analytics_alert_threshold(p_organization_id, ''CLEARING_AGING'');
  if public.analytics_alert_rule_enabled(p_organization_id, ''CLEARING_AGING'')
     and (v_thr ? ''max_age_days'')
  then
    v_days := greatest(1, coalesce((v_thr->>''max_age_days'')::int, 7));
    v_keys := ''{}'';
    for r in
      select ta.id as account_id,
             public.treasury_account_balance(ta.id) as bal,
             min(o.operation_date) as oldest_date
      from public.treasury_accounts ta
      join public.treasury_operation_legs l
        on l.treasury_account_id = ta.id
       and l.organization_id = ta.organization_id
      join public.treasury_operations o
        on o.id = l.treasury_operation_id
       and o.organization_id = l.organization_id
      where ta.organization_id = p_organization_id
        and ta.account_type = ''CLEARING''::public.treasury_account_type
        and ta.is_active
        and o.status = ''POSTED''::public.treasury_operation_status
        and l.direction = ''INFLOW''::public.treasury_leg_direction
      group by ta.id
      having public.treasury_account_balance(ta.id) > 0
         and min(o.operation_date) <= (v_as_of - v_days)
    loop
      v_key := ''CLEARING_AGING:'' || r.account_id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, ''CLEARING_AGING'', ''TREASURY'', v_key, ''INFO'',
        ''treasury_accounts'', r.account_id,
        jsonb_build_object(
          ''balance'', r.bal,
          ''oldest_inflow_date'', r.oldest_date,
          ''max_age_days'', v_days
        )
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, ''CLEARING_AGING'', v_keys);
  end if;

  return jsonb_build_object(
    ''organization_id'', p_organization_id,
    ''evaluated_at'', v_now,
    ''as_of'', v_as_of,
    ''touched_rules'', v_opened,
    ''evaluated_by'', v_uid
  );
end;
$$","revoke all on function public.evaluate_analytics_alerts(uuid) from public, anon","grant execute on function public.evaluate_analytics_alerts(uuid) to authenticated","comment on function public.evaluate_analytics_alerts(uuid) is
  ''SECURITY DEFINER intentional: explicit alert rebuild; requires ALERT_EVALUATE.''","-- =============================================================================
-- 11) analytics_validate_saved_report_config + upsert_saved_report
-- =============================================================================

create or replace function public.analytics_validate_saved_report_config(
  p_report_code text,
  p_filters jsonb,
  p_columns jsonb,
  p_sort jsonb
)
returns void
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_code text := upper(trim(coalesce(p_report_code, '''')));
  v_key text;
  v_elem jsonb;
  v_field text;
  v_dir text;
  v_forbidden text[] := array[
    ''sql'',''query'',''table'',''schema'',''function'',''expression'',
    ''raw_column'',''organization_id'',''tenant_id'',''org_id''
  ];
  v_filter_allow text[];
  v_col_allow text[] := array[
    ''id'',''issue_date'',''amount'',''code'',''name'',''balance'',''status'',''document_number'',
    ''gross'',''net'',''count'',''bucket'',''debit'',''credit'',''sku'',''product_id'',''operation_type'',
    ''operation_date'',''accounting_date'',''completed_at'',''tax_period_id'',''saldo_estimado'',
    ''inventory_value'',''quantity_on_hand_total'',''average_unit_cost'',''internal_number'',
    ''description'',''document_type'',''fiscal_environment'',''operation_kind'',''signed_total'',
    ''warehouse_id'',''movement_date'',''direction'',''quantity''
  ];
  v_common_filters text[] := array[''from'',''to'',''as_of'',''period_preset'',''fiscal_environment''];
begin
  if v_code = '''' then
    raise exception ''report_code required'';
  end if;

  v_filter_allow := case v_code
    when ''SALES_SUMMARY'' then array[''from'',''to'',''period_preset'',''fiscal_environment'']
    when ''TAX_SUMMARY'' then array[''from'',''to'',''period_preset'',''as_of'']
    when ''AR_AGING'' then array[''as_of'',''period_preset'']
    when ''AP_AGING'' then array[''as_of'',''period_preset'']
    when ''CASH_BANK_POSITION'' then array[''as_of'']
    when ''TREASURY_MOVEMENTS'' then array[''from'',''to'',''period_preset'']
    when ''MANAGEMENT_PNL'' then array[''from'',''to'',''period_preset'']
    when ''MANAGEMENT_BALANCE_SHEET'' then array[''as_of'',''period_preset'']
    when ''TRIAL_BALANCE_MGMT'' then array[''from'',''to'',''period_preset'']
    when ''INVENTORY_VALUATION'' then array[''as_of'']
    when ''INVENTORY_MOVEMENTS'' then array[''from'',''to'',''period_preset'']
    when ''POS_SUMMARY'' then array[''from'',''to'',''period_preset'']
    when ''PURCHASES_SUMMARY'' then array[''from'',''to'',''period_preset'']
    else v_common_filters
  end;

  -- Reject forbidden keys in any jsonb object (filters) or nested objects (sort elems)
  if p_filters is not null and jsonb_typeof(p_filters) = ''object'' then
    for v_key in select jsonb_object_keys(p_filters)
    loop
      if lower(v_key) = any (v_forbidden) then
        raise exception ''saved report filters reject key: %'', v_key;
      end if;
      if not exists (
        select 1 from unnest(v_filter_allow) a where lower(a) = lower(v_key)
      ) then
        raise exception ''saved report filters unknown key: %'', v_key;
      end if;
    end loop;
  elsif p_filters is not null and jsonb_typeof(p_filters) is distinct from ''object'' then
    raise exception ''filters must be a jsonb object'';
  end if;

  if p_columns is not null then
    if jsonb_typeof(p_columns) is distinct from ''array'' then
      raise exception ''columns must be a jsonb array'';
    end if;
    for v_elem in select * from jsonb_array_elements(p_columns)
    loop
      if jsonb_typeof(v_elem) = ''object'' then
        for v_key in select jsonb_object_keys(v_elem)
        loop
          if lower(v_key) = any (v_forbidden) then
            raise exception ''saved report columns reject key: %'', v_key;
          end if;
        end loop;
        v_field := coalesce(v_elem->>''field'', v_elem->>''code'', v_elem->>''name'');
      elsif jsonb_typeof(v_elem) = ''string'' then
        v_field := trim(both ''\"'' from v_elem::text);
      else
        raise exception ''invalid columns element'';
      end if;
      if v_field is not null and v_field <> '''' and not exists (
        select 1 from unnest(v_col_allow) a where lower(a) = lower(v_field)
      ) then
        raise exception ''saved report columns unknown field: %'', v_field;
      end if;
    end loop;
  end if;

  if p_sort is not null then
    if jsonb_typeof(p_sort) is distinct from ''array'' then
      raise exception ''sort must be a jsonb array'';
    end if;
    for v_elem in select * from jsonb_array_elements(p_sort)
    loop
      if jsonb_typeof(v_elem) is distinct from ''object'' then
        raise exception ''sort elements must be objects'';
      end if;
      for v_key in select jsonb_object_keys(v_elem)
      loop
        if lower(v_key) = any (v_forbidden) then
          raise exception ''saved report sort reject key: %'', v_key;
        end if;
        if lower(v_key) not in (''field'', ''direction'') then
          raise exception ''saved report sort unknown key: %'', v_key;
        end if;
      end loop;
      v_field := v_elem->>''field'';
      v_dir := upper(coalesce(v_elem->>''direction'', ''ASC''));
      if v_field is null or v_field = '''' then
        raise exception ''sort.field required'';
      end if;
      if not exists (
        select 1 from unnest(v_col_allow) a where lower(a) = lower(v_field)
      ) then
        raise exception ''saved report sort unknown field: %'', v_field;
      end if;
      if v_dir not in (''ASC'', ''DESC'') then
        raise exception ''sort.direction must be ASC or DESC'';
      end if;
    end loop;
  end if;
end;
$$","revoke all on function public.analytics_validate_saved_report_config(text, jsonb, jsonb, jsonb)
  from public, anon, authenticated","create or replace function public.upsert_saved_report(
  p_organization_id uuid,
  p_report_code text,
  p_name text,
  p_filters_json jsonb default ''{}''::jsonb,
  p_columns_json jsonb default ''[]''::jsonb,
  p_sort_json jsonb default ''[]''::jsonb,
  p_visibility text default ''PRIVATE'',
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_id uuid;
  v_vis public.saved_report_visibility;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''reports'');

  perform public.analytics_validate_saved_report_config(
    p_report_code,
    coalesce(p_filters_json, ''{}''::jsonb),
    coalesce(p_columns_json, ''[]''::jsonb),
    coalesce(p_sort_json, ''[]''::jsonb)
  );

  v_vis := upper(coalesce(p_visibility, ''PRIVATE''))::public.saved_report_visibility;

  if p_id is not null then
    update public.saved_reports
    set
      report_code = upper(trim(p_report_code)),
      name = trim(p_name),
      filters_json = coalesce(p_filters_json, ''{}''::jsonb),
      columns_json = coalesce(p_columns_json, ''[]''::jsonb),
      sort_json = coalesce(p_sort_json, ''[]''::jsonb),
      visibility = v_vis,
      updated_at = timezone(''utc'', now())
    where id = p_id
      and organization_id = p_organization_id
      and owner_user_id = v_uid
    returning id into v_id;
    if v_id is null then
      raise exception ''saved report not found or not owned'';
    end if;
  else
    insert into public.saved_reports (
      organization_id, owner_user_id, report_code, name,
      filters_json, columns_json, sort_json, visibility
    ) values (
      p_organization_id, v_uid, upper(trim(p_report_code)), trim(p_name),
      coalesce(p_filters_json, ''{}''::jsonb),
      coalesce(p_columns_json, ''[]''::jsonb),
      coalesce(p_sort_json, ''[]''::jsonb),
      v_vis
    )
    returning id into v_id;
  end if;

  return jsonb_build_object(''id'', v_id);
end;
$$","revoke all on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
  from public, anon","grant execute on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
  to authenticated","comment on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid) is
  ''SECURITY DEFINER intentional: upsert saved report after allowlist validation; never accepts SQL fragments.''","-- =============================================================================
-- 8) get_report_dataset — capability gates + pagination totals fix
-- =============================================================================

create or replace function public.get_report_dataset(
  p_organization_id uuid,
  p_report_code text,
  p_filters jsonb default ''{}''::jsonb,
  p_limit int default 100,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_code text := upper(trim(p_report_code));
  v_limit int := greatest(1, least(coalesce(p_limit, 100), 500));
  v_offset int := greatest(0, coalesce(p_offset, 0));
  v_from date;
  v_to date;
  v_as_of date;
  v_now timestamptz := timezone(''utc'', now());
  v_rows jsonb := ''[]''::jsonb;
  v_totals jsonb := ''{}''::jsonb;
  v_env text;
  v_pnl jsonb;
  v_bs jsonb;
  v_aging jsonb;
  v_total_count bigint := 0;
  v_page_count int := 0;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''reports'');

  if v_code in (
    ''AR_AGING'', ''AP_AGING'', ''CASH_BANK_POSITION'', ''TREASURY_MOVEMENTS'',
    ''MANAGEMENT_PNL'', ''MANAGEMENT_BALANCE_SHEET'', ''TRIAL_BALANCE_MGMT''
  ) then
    perform public.analytics_assert_capability(
      p_organization_id, ''REPORT_FINANCIAL''::public.analytics_capability
    );
  elsif v_code = ''TAX_SUMMARY'' then
    perform public.analytics_assert_capability(
      p_organization_id, ''REPORT_TAX''::public.analytics_capability
    );
    perform public.analytics_assert_feature(p_organization_id, ''taxes'');
  elsif v_code in (''INVENTORY_VALUATION'', ''INVENTORY_MOVEMENTS'') then
    perform public.analytics_assert_capability(
      p_organization_id, ''REPORT_OPERATIONAL''::public.analytics_capability
    );
    perform public.analytics_assert_feature(p_organization_id, ''inventory'');
  elsif v_code = ''POS_SUMMARY'' then
    perform public.analytics_assert_capability(
      p_organization_id, ''REPORT_OPERATIONAL''::public.analytics_capability
    );
    perform public.analytics_assert_feature(p_organization_id, ''pos'');
  elsif v_code = ''SALES_SUMMARY'' then
    perform public.analytics_assert_capability(
      p_organization_id, ''REPORT_OPERATIONAL''::public.analytics_capability
    );
    perform public.analytics_assert_any_feature(
      p_organization_id, array[''sales'', ''fiscal_invoicing'']
    );
  elsif v_code = ''PURCHASES_SUMMARY'' then
    perform public.analytics_assert_capability(
      p_organization_id, ''REPORT_OPERATIONAL''::public.analytics_capability
    );
    perform public.analytics_assert_feature(p_organization_id, ''purchases'');
  else
    raise exception ''unsupported report_code: %'', p_report_code;
  end if;

  v_from := nullif(p_filters->>''from'', '''')::date;
  v_to := nullif(p_filters->>''to'', '''')::date;
  v_as_of := coalesce(nullif(p_filters->>''as_of'', '''')::date, v_to, v_from,
    (timezone(public.analytics_org_timezone(p_organization_id), timezone(''utc'', now())))::date);
  v_env := nullif(p_filters->>''fiscal_environment'', '''');

  if v_from is null or v_to is null then
    select pb.period_start, pb.period_end into v_from, v_to
    from public.analytics_period_bounds(
      p_organization_id,
      coalesce(nullif(p_filters->>''period_preset'', ''''), ''THIS_MONTH''),
      v_from, v_to
    ) pb;
  end if;

  case v_code
    when ''AR_AGING'' then
      v_aging := public.get_ar_aging(p_organization_id, v_as_of);
      v_rows := coalesce(v_aging->''rows'', ''[]''::jsonb);
      v_totals := coalesce(v_aging->''totals'', ''{}''::jsonb);
      v_total_count := jsonb_array_length(v_rows);
      v_page_count := v_total_count::int;

    when ''AP_AGING'' then
      v_aging := public.get_ap_aging(p_organization_id, v_as_of);
      v_rows := coalesce(v_aging->''rows'', ''[]''::jsonb);
      v_totals := coalesce(v_aging->''totals'', ''{}''::jsonb);
      v_total_count := jsonb_array_length(v_rows);
      v_page_count := v_total_count::int;

    when ''SALES_SUMMARY'' then
      select
        jsonb_build_object(
          ''gross'', coalesce(sum(x.gross), 0)::numeric(19, 4),
          ''net'', coalesce(sum(x.net), 0)::numeric(19, 4),
          ''count'', count(*)::int
        ),
        count(*)
      into v_totals, v_total_count
      from (
        select
          (fd.total_amount * public.analytics_fiscal_economic_sign(fdt.operation_kind))::numeric(19, 4) as gross,
          (
            (fd.net_taxed_amount + fd.net_exempt_amount + fd.net_untaxed_amount)
            * public.analytics_fiscal_economic_sign(fdt.operation_kind)
          )::numeric(19, 4) as net
        from public.fiscal_documents fd
        join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
        where fd.organization_id = p_organization_id
          and fd.status = ''AUTHORIZED''::public.fiscal_document_status
          and fd.issue_date >= v_from and fd.issue_date <= v_to
          and (v_env is null or fd.fiscal_environment::text = v_env)
      ) x;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), ''[]''::jsonb)
      into v_rows
      from (
        select
          fd.id,
          fd.issue_date,
          fd.document_number,
          fd.status::text,
          fd.fiscal_environment::text,
          fdt.operation_kind::text,
          (fd.total_amount * public.analytics_fiscal_economic_sign(fdt.operation_kind))::numeric(19, 4) as gross,
          (
            (fd.net_taxed_amount + fd.net_exempt_amount + fd.net_untaxed_amount)
            * public.analytics_fiscal_economic_sign(fdt.operation_kind)
          )::numeric(19, 4) as net
        from public.fiscal_documents fd
        join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
        where fd.organization_id = p_organization_id
          and fd.status = ''AUTHORIZED''::public.fiscal_document_status
          and fd.issue_date >= v_from and fd.issue_date <= v_to
          and (v_env is null or fd.fiscal_environment::text = v_env)
        order by fd.issue_date desc, fd.document_number desc nulls last
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, ''[]''::jsonb));

    when ''CASH_BANK_POSITION'' then
      v_totals := jsonb_build_object(
        ''cash'', public.analytics_treasury_type_balance(p_organization_id, ''CASH''),
        ''bank'', public.analytics_treasury_type_balance(p_organization_id, ''BANK''),
        ''clearing'', public.analytics_treasury_type_balance(p_organization_id, ''CLEARING'')
      );
      select count(*) into v_total_count
      from public.treasury_accounts ta
      where ta.organization_id = p_organization_id and ta.is_active;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), ''[]''::jsonb)
      into v_rows
      from (
        select
          ta.id,
          ta.code,
          ta.name,
          ta.account_type::text,
          public.treasury_account_balance(ta.id)::numeric(19, 4) as balance
        from public.treasury_accounts ta
        where ta.organization_id = p_organization_id
          and ta.is_active
        order by ta.account_type, ta.code
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, ''[]''::jsonb));

    when ''TRIAL_BALANCE_MGMT'' then
      perform public.analytics_assert_feature(p_organization_id, ''accounting'');
      select
        jsonb_build_object(
          ''debit_total'', coalesce(sum(x.debit), 0)::numeric(19, 4),
          ''credit_total'', coalesce(sum(x.credit), 0)::numeric(19, 4)
        ),
        count(*)
      into v_totals, v_total_count
      from (
        select
          coalesce(sum(l.debit), 0)::numeric(19, 4) as debit,
          coalesce(sum(l.credit), 0)::numeric(19, 4) as credit
        from public.accounts a
        left join public.analytics_journal_economic_lines(p_organization_id) l
          on l.account_id = a.id
         and l.entry_date >= v_from
         and l.entry_date <= v_to
        where a.organization_id = p_organization_id
          and a.is_active
          and a.account_type is distinct from ''MEMORANDUM''::public.account_type
        group by a.id
        having coalesce(sum(l.debit), 0) <> 0 or coalesce(sum(l.credit), 0) <> 0
      ) x;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), ''[]''::jsonb)
      into v_rows
      from (
        select
          a.code,
          a.name,
          a.account_type::text,
          coalesce(sum(l.debit), 0)::numeric(19, 4) as debit,
          coalesce(sum(l.credit), 0)::numeric(19, 4) as credit,
          public.analytics_signed_balance(
            coalesce(sum(l.debit), 0),
            coalesce(sum(l.credit), 0),
            a.normal_balance
          ) as balance
        from public.accounts a
        left join public.analytics_journal_economic_lines(p_organization_id) l
          on l.account_id = a.id
         and l.entry_date >= v_from
         and l.entry_date <= v_to
        where a.organization_id = p_organization_id
          and a.is_active
          and a.account_type is distinct from ''MEMORANDUM''::public.account_type
        group by a.id, a.code, a.name, a.account_type, a.normal_balance
        having coalesce(sum(l.debit), 0) <> 0 or coalesce(sum(l.credit), 0) <> 0
        order by a.code
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, ''[]''::jsonb));

    when ''MANAGEMENT_PNL'' then
      v_pnl := public.analytics_management_pnl(p_organization_id, v_from, v_to);
      v_rows := jsonb_build_array(v_pnl);
      v_totals := jsonb_build_object(
        ''management_result'', v_pnl->''management_result'',
        ''gross_result'', v_pnl->''gross_result''
      );
      v_total_count := 1;
      v_page_count := 1;

    when ''MANAGEMENT_BALANCE_SHEET'' then
      v_bs := public.analytics_management_balance_sheet(p_organization_id, v_as_of);
      v_rows := jsonb_build_array(v_bs);
      v_totals := jsonb_build_object(
        ''assets'', v_bs->''assets'',
        ''liabilities'', v_bs->''liabilities'',
        ''equity'', v_bs->''equity'',
        ''resultado_del_periodo'', v_bs->''resultado_del_periodo'',
        ''difference'', v_bs->''difference'',
        ''status'', v_bs->''status''
      );
      v_total_count := 1;
      v_page_count := 1;

    when ''TAX_SUMMARY'' then
      select count(*) into v_total_count
      from public.tax_periods tp
      where tp.organization_id = p_organization_id;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), ''[]''::jsonb)
      into v_rows
      from (
        select
          tp.id as tax_period_id,
          tp.tax_code::text,
          tp.period_year,
          tp.period_month,
          tp.status::text,
          tp.source_changed,
          td.id as determination_id,
          td.totals_snapshot,
          (td.totals_snapshot->>''saldo_estimado'') as saldo_estimado
        from public.tax_periods tp
        left join public.tax_determinations td
          on td.tax_period_id = tp.id and td.is_current
        where tp.organization_id = p_organization_id
        order by tp.period_year desc, tp.period_month desc nulls last
        limit v_limit offset v_offset
      ) r;
      v_totals := jsonb_build_object(''disclaimer'', ''Saldo estimado — no es DDJJ oficial'');
      v_page_count := jsonb_array_length(coalesce(v_rows, ''[]''::jsonb));

    when ''INVENTORY_VALUATION'' then
      select
        jsonb_build_object(''inventory_value'', coalesce(sum(ics.inventory_value), 0)::numeric(19, 4)),
        count(*)
      into v_totals, v_total_count
      from public.inventory_cost_state ics
      where ics.organization_id = p_organization_id;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), ''[]''::jsonb)
      into v_rows
      from (
        select
          ics.product_id,
          p.sku,
          p.name,
          ics.quantity_on_hand_total,
          ics.average_unit_cost,
          ics.inventory_value
        from public.inventory_cost_state ics
        join public.products p
          on p.id = ics.product_id and p.organization_id = ics.organization_id
        where ics.organization_id = p_organization_id
        order by ics.inventory_value desc
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, ''[]''::jsonb));

    when ''INVENTORY_MOVEMENTS'' then
      select
        jsonb_build_object(
          ''value_sum'', coalesce(sum(abs(ile.value_delta)), 0)::numeric(19, 4),
          ''count'', count(*)::int
        ),
        count(*)
      into v_totals, v_total_count
      from public.inventory_ledger_entries ile
      where ile.organization_id = p_organization_id
        and ile.movement_date >= v_from and ile.movement_date <= v_to;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), ''[]''::jsonb)
      into v_rows
      from (
        select
          ile.id,
          ile.movement_date,
          ile.operation_type::text,
          ile.direction::text,
          ile.product_id,
          ile.warehouse_id,
          ile.quantity,
          ile.value_delta
        from public.inventory_ledger_entries ile
        where ile.organization_id = p_organization_id
          and ile.movement_date >= v_from and ile.movement_date <= v_to
        order by ile.movement_date desc, ile.created_at desc
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, ''[]''::jsonb));

    when ''POS_SUMMARY'' then
      select
        jsonb_build_object(''completed_count'', count(*)::int),
        count(*)
      into v_totals, v_total_count
      from public.pos_sales ps
      where ps.organization_id = p_organization_id
        and ps.status = ''COMPLETED''::public.pos_sale_status
        and (
          (ps.completed_at is not null
            and (timezone(public.analytics_org_timezone(p_organization_id), ps.completed_at))::date
                  between v_from and v_to)
          or (ps.completed_at is null
            and ps.created_at::date between v_from and v_to)
        );

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), ''[]''::jsonb)
      into v_rows
      from (
        select
          ps.id,
          ps.status::text,
          ps.completed_at,
          ps.sales_document_id,
          ps.fiscal_document_id
        from public.pos_sales ps
        where ps.organization_id = p_organization_id
          and ps.status = ''COMPLETED''::public.pos_sale_status
          and (
            (ps.completed_at is not null
              and (timezone(public.analytics_org_timezone(p_organization_id), ps.completed_at))::date
                    between v_from and v_to)
            or (ps.completed_at is null
              and ps.created_at::date between v_from and v_to)
          )
        order by ps.completed_at desc nulls last
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, ''[]''::jsonb));

    when ''TREASURY_MOVEMENTS'' then
      select
        jsonb_build_object(
          ''amount_sum'', coalesce(sum(o.amount), 0)::numeric(19, 4),
          ''count'', count(*)::int
        ),
        count(*)
      into v_totals, v_total_count
      from public.treasury_operations o
      where o.organization_id = p_organization_id
        and o.status = ''POSTED''::public.treasury_operation_status
        and o.operation_date >= v_from and o.operation_date <= v_to;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), ''[]''::jsonb)
      into v_rows
      from (
        select
          o.id,
          o.internal_number,
          o.operation_type::text,
          o.status::text,
          o.operation_date,
          o.amount,
          o.description
        from public.treasury_operations o
        where o.organization_id = p_organization_id
          and o.status = ''POSTED''::public.treasury_operation_status
          and o.operation_date >= v_from and o.operation_date <= v_to
        order by o.operation_date desc, o.internal_number desc
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, ''[]''::jsonb));

    when ''PURCHASES_SUMMARY'' then
      select
        jsonb_build_object(
          ''total'', coalesce(sum(
            case
              when pd.document_type = ''SUPPLIER_CREDIT_NOTE''::public.purchase_document_type
                then -pd.total_amount
              else pd.total_amount
            end
          ), 0)::numeric(19, 4),
          ''count'', count(*)::int
        ),
        count(*)
      into v_totals, v_total_count
      from public.purchase_documents pd
      where pd.organization_id = p_organization_id
        and pd.status = ''POSTED''::public.purchase_document_status
        and pd.accounting_date >= v_from and pd.accounting_date <= v_to;

      select coalesce(jsonb_agg(row_to_json(r)::jsonb), ''[]''::jsonb)
      into v_rows
      from (
        select
          pd.id,
          pd.document_type::text,
          pd.document_number,
          pd.issue_date,
          pd.accounting_date,
          pd.status::text,
          pd.total_amount,
          case
            when pd.document_type = ''SUPPLIER_CREDIT_NOTE''::public.purchase_document_type
              then -pd.total_amount
            else pd.total_amount
          end::numeric(19, 4) as signed_total
        from public.purchase_documents pd
        where pd.organization_id = p_organization_id
          and pd.status = ''POSTED''::public.purchase_document_status
          and pd.accounting_date >= v_from and pd.accounting_date <= v_to
        order by pd.accounting_date desc
        limit v_limit offset v_offset
      ) r;
      v_page_count := jsonb_array_length(coalesce(v_rows, ''[]''::jsonb));
  end case;

  return jsonb_build_object(
    ''rows'', coalesce(v_rows, ''[]''::jsonb),
    ''totals'', coalesce(v_totals, ''{}''::jsonb),
    ''meta'', jsonb_build_object(
      ''calculation_version'', 1,
      ''data_as_of'', v_now,
      ''generated_at'', v_now,
      ''report_code'', v_code,
      ''period_start'', v_from,
      ''period_end'', v_to,
      ''limit'', v_limit,
      ''offset'', v_offset,
      ''total_count'', coalesce(v_total_count, 0),
      ''page_count'', coalesce(v_page_count, 0),
      ''generated_by'', v_uid
    )
  );
end;
$$","revoke all on function public.get_report_dataset(uuid, text, jsonb, int, int) from public, anon","grant execute on function public.get_report_dataset(uuid, text, jsonb, int, int) to authenticated","comment on function public.get_report_dataset(uuid, text, jsonb, int, int) is
  ''SECURITY DEFINER intentional: allowlisted report_code datasets; capability-gated; totals over full filter; rows paginated.''","-- =============================================================================
-- 9) analytics_management_pnl / analytics_management_balance_sheet
-- =============================================================================

create or replace function public.analytics_management_pnl(
  p_org_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_revenue numeric(19, 4) := 0;
  v_cogs numeric(19, 4) := 0;
  v_opex numeric(19, 4) := 0;
  v_other numeric(19, 4) := 0;
  v_gross numeric(19, 4);
  v_mgmt numeric(19, 4);
  v_has_cogs_mapping boolean := false;
  v_cogs_activity boolean := false;
  v_mapping_status text := ''OK'';
  v_now timestamptz := timezone(''utc'', now());
begin
  v_uid := public.analytics_assert_member(p_org_id);
  perform public.analytics_assert_feature(p_org_id, ''accounting'');
  perform public.analytics_assert_capability(
    p_org_id, ''DASHBOARD_FINANCIAL''::public.analytics_capability
  );

  if p_from is null or p_to is null or p_from > p_to then
    raise exception ''invalid period for management pnl'';
  end if;

  select exists (
    select 1
    from public.accounts a
    where a.organization_id = p_org_id
      and (
        a.system_role in (''cogs'', ''group_cogs'')
        or public.analytics_account_is_cogs(a.id)
      )
  ) into v_has_cogs_mapping;

  select
    coalesce(sum(
      case
        when l.account_type = ''REVENUE''::public.account_type
          then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0
      end
    ), 0)::numeric(19, 4),
    coalesce(sum(
      case
        when public.analytics_account_is_cogs(l.account_id)
          then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0
      end
    ), 0)::numeric(19, 4),
    coalesce(sum(
      case
        when l.account_type = ''EXPENSE''::public.account_type
          and not public.analytics_account_is_cogs(l.account_id)
          then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0
      end
    ), 0)::numeric(19, 4)
  into v_revenue, v_cogs, v_opex
  from public.analytics_journal_economic_lines(p_org_id) l
  where l.entry_date >= p_from
    and l.entry_date <= p_to;

  v_other := 0;
  v_gross := (v_revenue - v_cogs)::numeric(19, 4);
  v_mgmt := (v_revenue - v_cogs - v_opex - v_other)::numeric(19, 4);
  v_cogs_activity := abs(v_cogs) > 0.0001;

  if not v_has_cogs_mapping then
    v_mapping_status := ''REPORT_MAPPING_REQUIRES_REVIEW'';
  elsif v_revenue <> 0 and not v_cogs_activity and not v_has_cogs_mapping then
    v_mapping_status := ''REPORT_MAPPING_REQUIRES_REVIEW'';
  end if;

  return jsonb_build_object(
    ''revenue'', v_revenue,
    ''cogs'', v_cogs,
    ''gross_result'', v_gross,
    ''opex'', v_opex,
    ''other'', v_other,
    ''management_result'', v_mgmt,
    ''mapping_status'', v_mapping_status,
    ''mapping_ok'', (v_mapping_status = ''OK''),
    ''has_cogs_mapping'', v_has_cogs_mapping,
    ''disclaimer'', ''Reporte gerencial interno — sujeto a revisión profesional'',
    ''calculation_version'', 1,
    ''period_start'', p_from,
    ''period_end'', p_to,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''generated_by'', v_uid
  );
end;
$$","revoke all on function public.analytics_management_pnl(uuid, date, date) from public, anon","grant execute on function public.analytics_management_pnl(uuid, date, date) to authenticated","comment on function public.analytics_management_pnl(uuid, date, date) is
  ''SECURITY DEFINER intentional: management P&L; accounting feature + DASHBOARD_FINANCIAL.''","create or replace function public.analytics_management_balance_sheet(
  p_org_id uuid,
  p_as_of date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_assets numeric(19, 4) := 0;
  v_liabilities numeric(19, 4) := 0;
  v_equity numeric(19, 4) := 0;
  v_ytd_revenue numeric(19, 4) := 0;
  v_ytd_expense numeric(19, 4) := 0;
  v_period_result numeric(19, 4);
  v_rhs numeric(19, 4);
  v_diff numeric(19, 4);
  v_status text := ''OK'';
  v_year_start date;
  v_fy_found boolean := false;
  v_now timestamptz := timezone(''utc'', now());
  v_result jsonb;
begin
  v_uid := public.analytics_assert_member(p_org_id);
  perform public.analytics_assert_feature(p_org_id, ''accounting'');
  perform public.analytics_assert_capability(
    p_org_id, ''DASHBOARD_FINANCIAL''::public.analytics_capability
  );

  if p_as_of is null then
    raise exception ''p_as_of required'';
  end if;

  select fy.start_date into v_year_start
  from public.accounting_fiscal_years fy
  where fy.organization_id = p_org_id
    and fy.start_date <= p_as_of
    and fy.end_date >= p_as_of
  order by fy.start_date desc
  limit 1;

  v_fy_found := v_year_start is not null;

  select
    coalesce(sum(
      case when l.account_type = ''ASSET''::public.account_type
        then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0 end
    ), 0)::numeric(19, 4),
    coalesce(sum(
      case when l.account_type = ''LIABILITY''::public.account_type
        then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0 end
    ), 0)::numeric(19, 4),
    coalesce(sum(
      case when l.account_type = ''EQUITY''::public.account_type
        then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
        else 0 end
    ), 0)::numeric(19, 4)
  into v_assets, v_liabilities, v_equity
  from public.analytics_journal_economic_lines(p_org_id) l
  where l.entry_date <= p_as_of
    and l.account_type in (
      ''ASSET''::public.account_type,
      ''LIABILITY''::public.account_type,
      ''EQUITY''::public.account_type
    );

  if v_fy_found then
    select
      coalesce(sum(
        case when l.account_type = ''REVENUE''::public.account_type
          then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
          else 0 end
      ), 0)::numeric(19, 4),
      coalesce(sum(
        case when l.account_type = ''EXPENSE''::public.account_type
          then public.analytics_signed_balance(l.debit, l.credit, l.normal_balance)
          else 0 end
      ), 0)::numeric(19, 4)
    into v_ytd_revenue, v_ytd_expense
    from public.analytics_journal_economic_lines(p_org_id) l
    where l.entry_date >= v_year_start
      and l.entry_date <= p_as_of
      and l.account_type in (
        ''REVENUE''::public.account_type,
        ''EXPENSE''::public.account_type
      );

    v_period_result := (v_ytd_revenue - v_ytd_expense)::numeric(19, 4);
    v_rhs := (v_liabilities + v_equity + v_period_result)::numeric(19, 4);
    v_diff := (v_assets - v_rhs)::numeric(19, 4);

    if abs(v_diff) > 0.01 then
      v_status := ''REPORT_ACCOUNTING_MISMATCH'';
    end if;
  else
    v_period_result := null;
    v_rhs := (v_liabilities + v_equity)::numeric(19, 4);
    v_diff := (v_assets - v_rhs)::numeric(19, 4);
    v_status := ''REPORT_FISCAL_YEAR_REQUIRES_CONFIG'';
  end if;

  v_result := jsonb_build_object(
    ''as_of'', p_as_of,
    ''assets'', v_assets,
    ''liabilities'', v_liabilities,
    ''equity'', v_equity,
    ''resultado_del_periodo'', to_jsonb(v_period_result),
    ''ytd_start'', case when v_fy_found then to_jsonb(v_year_start) else ''null''::jsonb end,
    ''equation_rhs'', v_rhs,
    ''difference'', v_diff,
    ''status'', v_status,
    ''disclaimer'', ''Reporte gerencial interno — sujeto a revisión profesional. Sin asiento de balanceo.'',
    ''calculation_version'', 1,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''generated_by'', v_uid
  );

  if v_fy_found then
    v_result := v_result || jsonb_build_object(''fiscal_year_start'', v_year_start);
  end if;

  return v_result;
end;
$$","revoke all on function public.analytics_management_balance_sheet(uuid, date) from public, anon","grant execute on function public.analytics_management_balance_sheet(uuid, date) to authenticated","comment on function public.analytics_management_balance_sheet(uuid, date) is
  ''SECURITY DEFINER intentional: management BS; fiscal year from accounting_fiscal_years (no Jan 1 fallback).''","-- =============================================================================
-- 10) analytics_product_margin_summary — STOCK_ITEM + ISSUE lineage only
-- =============================================================================

create or replace function public.analytics_product_margin_summary(
  p_organization_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_now timestamptz := timezone(''utc'', now());
  v_revenue numeric(19, 4) := 0;
  v_cogs numeric(19, 4) := 0;
  v_stock_with_lineage int := 0;
  v_stock_missing_lineage int := 0;
  v_service_lines int := 0;
  v_unlinked_lines int := 0;
  v_status text := ''OK'';
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, ''fiscal_invoicing'');
  perform public.analytics_assert_feature(p_organization_id, ''inventory'');

  if p_from is null or p_to is null or p_from > p_to then
    raise exception ''invalid period'';
  end if;

  -- Unlinked AUTHORIZED lines (no source_sales_line_id)
  select count(*)::int into v_unlinked_lines
  from public.fiscal_document_lines fdl
  join public.fiscal_documents fd
    on fd.id = fdl.fiscal_document_id
   and fd.organization_id = fdl.organization_id
  where fdl.organization_id = p_organization_id
    and fd.status = ''AUTHORIZED''::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to
    and fdl.source_sales_line_id is null;

  -- SERVICE / NON_STOCK diagnostics (excluded from revenue)
  select count(*)::int into v_service_lines
  from public.fiscal_document_lines fdl
  join public.fiscal_documents fd
    on fd.id = fdl.fiscal_document_id
   and fd.organization_id = fdl.organization_id
  join public.sales_document_lines sdl on sdl.id = fdl.source_sales_line_id
  join public.products p
    on p.id = sdl.product_id
   and p.organization_id = fdl.organization_id
  where fdl.organization_id = p_organization_id
    and fd.status = ''AUTHORIZED''::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to
    and fdl.source_sales_line_id is not null
    and p.product_type in (
      ''SERVICE''::public.product_type,
      ''NON_STOCK''::public.product_type
    );

  -- STOCK_ITEM lines missing ISSUE lineage → review required
  select count(*)::int into v_stock_missing_lineage
  from public.fiscal_document_lines fdl
  join public.fiscal_documents fd
    on fd.id = fdl.fiscal_document_id
   and fd.organization_id = fdl.organization_id
  join public.sales_document_lines sdl on sdl.id = fdl.source_sales_line_id
  join public.products p
    on p.id = sdl.product_id
   and p.organization_id = fdl.organization_id
  where fdl.organization_id = p_organization_id
    and fd.status = ''AUTHORIZED''::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to
    and fdl.source_sales_line_id is not null
    and p.product_type = ''STOCK_ITEM''::public.product_type
    and not exists (
      select 1
      from public.inventory_operation_lines iol
      join public.inventory_operations io
        on io.id = iol.inventory_operation_id
       and io.organization_id = iol.organization_id
      where iol.organization_id = p_organization_id
        and iol.source_sales_line_id = fdl.source_sales_line_id
        and io.status = ''POSTED''::public.inventory_operation_status
        and io.operation_type = ''ISSUE''::public.inventory_operation_type
    );

  -- Revenue ONLY from STOCK_ITEM with ISSUE lineage
  select
    coalesce(sum(
      coalesce(fdl.net_amount, 0) * public.analytics_fiscal_economic_sign(fdt.operation_kind)
    ), 0)::numeric(19, 4),
    count(*)::int
  into v_revenue, v_stock_with_lineage
  from public.fiscal_document_lines fdl
  join public.fiscal_documents fd
    on fd.id = fdl.fiscal_document_id
   and fd.organization_id = fdl.organization_id
  join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
  join public.sales_document_lines sdl on sdl.id = fdl.source_sales_line_id
  join public.products p
    on p.id = sdl.product_id
   and p.organization_id = fdl.organization_id
  where fdl.organization_id = p_organization_id
    and fd.status = ''AUTHORIZED''::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to
    and fdl.source_sales_line_id is not null
    and p.product_type = ''STOCK_ITEM''::public.product_type
    and exists (
      select 1
      from public.inventory_operation_lines iol
      join public.inventory_operations io
        on io.id = iol.inventory_operation_id
       and io.organization_id = iol.organization_id
      where iol.organization_id = p_organization_id
        and iol.source_sales_line_id = fdl.source_sales_line_id
        and io.status = ''POSTED''::public.inventory_operation_status
        and io.operation_type = ''ISSUE''::public.inventory_operation_type
    );

  -- COGS from inventory ISSUE ledger for those same sales lines
  select coalesce(sum(abs(ile.value_delta)), 0)::numeric(19, 4)
  into v_cogs
  from public.inventory_ledger_entries ile
  join public.inventory_operation_lines iol
    on iol.id = ile.inventory_operation_line_id
   and iol.organization_id = ile.organization_id
  join public.inventory_operations io
    on io.id = iol.inventory_operation_id
   and io.organization_id = iol.organization_id
  where ile.organization_id = p_organization_id
    and io.status = ''POSTED''::public.inventory_operation_status
    and io.operation_type = ''ISSUE''::public.inventory_operation_type
    and iol.source_sales_line_id is not null
    and exists (
      select 1
      from public.fiscal_document_lines fdl2
      join public.fiscal_documents fd2
        on fd2.id = fdl2.fiscal_document_id
       and fd2.organization_id = fdl2.organization_id
      join public.sales_document_lines sdl2 on sdl2.id = fdl2.source_sales_line_id
      join public.products p2
        on p2.id = sdl2.product_id
       and p2.organization_id = fdl2.organization_id
      where fdl2.organization_id = p_organization_id
        and fdl2.source_sales_line_id = iol.source_sales_line_id
        and fd2.status = ''AUTHORIZED''::public.fiscal_document_status
        and fd2.issue_date >= p_from
        and fd2.issue_date <= p_to
        and p2.product_type = ''STOCK_ITEM''::public.product_type
    );

  if v_stock_missing_lineage > 0 then
    v_status := ''MARGIN_LINEAGE_REQUIRES_REVIEW'';
  end if;

  return jsonb_build_object(
    ''status'', v_status,
    ''signed_net_revenue_linked_lines'', v_revenue,
    ''inventory_cogs_linked'', v_cogs,
    ''product_gross_margin'', case
      when v_status = ''OK'' then (v_revenue - v_cogs)::numeric(19, 4)
      else null
    end,
    ''stock_lines_with_lineage'', v_stock_with_lineage,
    ''stock_lines_missing_lineage'', v_stock_missing_lineage,
    ''service_non_stock_lines'', v_service_lines,
    ''unlinked_fiscal_lines'', v_unlinked_lines,
    ''linked_fiscal_lines'', v_stock_with_lineage,
    ''note'', ''SERVICE/NON_STOCK excluded from revenue. STOCK_ITEM requires ISSUE lineage. Never use default_purchase_price. Never gross-total − COGS.'',
    ''calculation_version'', 1,
    ''period_start'', p_from,
    ''period_end'', p_to,
    ''data_as_of'', v_now,
    ''generated_at'', v_now,
    ''generated_by'', v_uid
  );
end;
$$","revoke all on function public.analytics_product_margin_summary(uuid, date, date)
  from public, anon","grant execute on function public.analytics_product_margin_summary(uuid, date, date)
  to authenticated","comment on function public.analytics_product_margin_summary(uuid, date, date) is
  ''SECURITY DEFINER intentional: STOCK_ITEM revenue with ISSUE lineage only; SERVICE/NON_STOCK excluded.''","-- =============================================================================
-- 12) Metric registry ACL
-- =============================================================================

revoke insert, update, delete on table public.analytics_metric_definitions from authenticated","grant select on table public.analytics_metric_definitions to authenticated","grant all on table public.analytics_metric_definitions to service_role","-- =============================================================================
-- 13) Grants / comments — helpers internal-only; document intentional client RPCs
-- =============================================================================

revoke all on function public.analytics_member_role(uuid) from public, anon, authenticated","revoke all on function public.analytics_has_capability(uuid, public.analytics_capability)
  from public, anon, authenticated","revoke all on function public.analytics_assert_capability(uuid, public.analytics_capability)
  from public, anon, authenticated","revoke all on function public.analytics_validate_saved_report_config(text, jsonb, jsonb, jsonb)
  from public, anon, authenticated","comment on function public.analytics_member_role(uuid) is
  ''Internal helper: member_role of auth.uid() for org. Not granted to authenticated.''","comment on function public.analytics_has_capability(uuid, public.analytics_capability) is
  ''Internal helper: role→capability map mirroring ROLE_PERMISSIONS. Not granted to authenticated.''","comment on function public.analytics_assert_capability(uuid, public.analytics_capability) is
  ''Internal helper: raise if capability missing. Called from intentional client RPCs.''","comment on function public.analytics_validate_saved_report_config(text, jsonb, jsonb, jsonb) is
  ''Internal helper: allowlist + forbidden-key validation for saved report JSON.''","comment on function public.get_dashboard_summary(uuid, text, date, date, text) is
  ''SECURITY DEFINER intentional client RPC. Authz: member + dashboard + DASHBOARD_BASIC; tiles gated by capability+feature.''","comment on function public.get_financial_dashboard(uuid, text, date, date, text) is
  ''SECURITY DEFINER intentional client RPC. Requires DASHBOARD_FINANCIAL.''","comment on function public.get_ar_aging(uuid, date) is
  ''SECURITY DEFINER intentional client RPC. Requires DASHBOARD_FINANCIAL.''","comment on function public.get_ap_aging(uuid, date) is
  ''SECURITY DEFINER intentional client RPC. Requires DASHBOARD_FINANCIAL.''","comment on function public.get_attention_summary(uuid) is
  ''SECURITY DEFINER intentional client RPC. Requires ALERT_READ; sanitizes for non-FINANCIAL.''","comment on function public.get_report_dataset(uuid, text, jsonb, int, int) is
  ''SECURITY DEFINER intentional client RPC. Capability per report_code; totals over full filter.''","comment on function public.evaluate_analytics_alerts(uuid) is
  ''SECURITY DEFINER intentional client RPC. Requires ALERT_EVALUATE.''","comment on function public.ack_analytics_alert(uuid) is
  ''SECURITY DEFINER intentional client RPC. Requires ALERT_ACK.''","comment on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid) is
  ''SECURITY DEFINER intentional client RPC. Validates config allowlist before write.''","comment on function public.analytics_management_pnl(uuid, date, date) is
  ''SECURITY DEFINER intentional client RPC. accounting + DASHBOARD_FINANCIAL.''","comment on function public.analytics_management_balance_sheet(uuid, date) is
  ''SECURITY DEFINER intentional client RPC. Fiscal year from accounting_fiscal_years; no Jan 1 fallback.''","comment on function public.analytics_product_margin_summary(uuid, date, date) is
  ''SECURITY DEFINER intentional client RPC. STOCK_ITEM + ISSUE lineage margin only.''"}', 'phase11_final_authz_reporting_hardening'),
	('20261101220000', '{"-- Phase 11: service_role-only mixed margin staging fixture (STOCK + SERVICE → expect stock_net - cogs)

create or replace function public.analytics_test_fixture_mixed_product_margin(
  p_organization_id uuid,
  p_issue_date date,
  p_stock_net numeric,
  p_service_net numeric,
  p_cogs numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_stock_prod uuid;
  v_svc_prod uuid;
  v_wh uuid;
  v_branch uuid;
  v_sales_doc uuid;
  v_stock_line uuid;
  v_svc_line uuid;
  v_dtype public.fiscal_document_types%rowtype;
  v_fd uuid;
  v_pos uuid;
  v_pos_n int;
  v_cp uuid;
  v_rule uuid;
  v_op uuid;
  v_iol uuid;
  v_stamp text := substr(replace(gen_random_uuid()::text, ''-'', ''''), 1, 10);
begin
  if auth.role() is distinct from ''service_role'' then
    raise exception ''analytics_test_fixture_mixed_product_margin is service_role only'';
  end if;

  select id into v_branch
  from public.branches
  where organization_id = p_organization_id
  limit 1;

  insert into public.warehouses (
    organization_id, branch_id, code, name, active
  ) values (
    p_organization_id, v_branch, ''WHMGN'' || upper(substr(v_stamp, 1, 4)), ''Margin fixture WH'', true
  )
  returning id into v_wh;

  insert into public.products (
    organization_id, sku, name, product_type, base_unit_code, track_inventory, active
  ) values (
    p_organization_id, ''MGN-S-'' || upper(v_stamp), ''Margin Stock Item'',
    ''STOCK_ITEM'', ''UNIT'', true, true
  )
  returning id into v_stock_prod;

  insert into public.products (
    organization_id, sku, name, product_type, base_unit_code, track_inventory, active
  ) values (
    p_organization_id, ''MGN-V-'' || upper(v_stamp), ''Margin Service'',
    ''SERVICE'', ''UNIT'', false, true
  )
  returning id into v_svc_prod;

  select c.id into v_cp
  from public.counterparties c
  where c.organization_id = p_organization_id
    and c.tax_id_normalized = public.normalize_counterparty_tax_id(''CUIT'', ''20111111112'')
  limit 1;
  if v_cp is null then
    insert into public.counterparties (
      organization_id, legal_name, tax_id_type, tax_id, is_active
    ) values (
      p_organization_id, ''Margin Fixture CP'', ''CUIT'', ''20111111112'', true
    ) returning id into v_cp;
  end if;
  insert into public.counterparty_roles (organization_id, counterparty_id, role)
  values (p_organization_id, v_cp, ''CUSTOMER'')
  on conflict do nothing;

  insert into public.sales_documents (
    organization_id, document_type, internal_number, counterparty_id, status,
    document_date, currency_code, subtotal, discount_total, total, branch_id
  ) values (
    p_organization_id, ''SALES_ORDER'', ''SO-MGN-'' || v_stamp, v_cp, ''CONFIRMED'',
    p_issue_date, ''ARS'', p_stock_net + p_service_net, 0, p_stock_net + p_service_net, v_branch
  )
  returning id into v_sales_doc;

  insert into public.sales_document_lines (
    organization_id, sales_document_id, line_number, product_id,
    description, quantity, unit_code, unit_price, line_subtotal, line_total
  ) values (
    p_organization_id, v_sales_doc, 1, v_stock_prod,
    ''Stock line'', 1, ''UNIT'', p_stock_net, p_stock_net, p_stock_net
  )
  returning id into v_stock_line;

  insert into public.sales_document_lines (
    organization_id, sales_document_id, line_number, product_id,
    description, quantity, unit_code, unit_price, line_subtotal, line_total
  ) values (
    p_organization_id, v_sales_doc, 2, v_svc_prod,
    ''Service line'', 1, ''UNIT'', p_service_net, p_service_net, p_service_net
  )
  returning id into v_svc_line;

  select * into v_dtype from public.fiscal_document_types where internal_code = ''INVOICE_A'' limit 1;

  insert into public.fiscal_points_of_sale (
    organization_id, environment, arca_point_of_sale, description, is_active
  ) values (
    p_organization_id, ''HOMOLOGATION'', 88, ''Margin fixture POS'', true
  )
  on conflict (organization_id, environment, arca_point_of_sale) do update
    set description = excluded.description
  returning id into v_pos;
  if v_pos is null then
    select id into v_pos from public.fiscal_points_of_sale
    where organization_id = p_organization_id
      and environment = ''HOMOLOGATION''
      and arca_point_of_sale = 88;
  end if;
  select arca_point_of_sale into v_pos_n from public.fiscal_points_of_sale where id = v_pos;

  select id into v_rule
  from public.fiscal_rule_versions
  where organization_id = p_organization_id and status = ''ACTIVE''
  order by effective_from desc limit 1;
  if v_rule is null then
    insert into public.fiscal_rule_versions (
      organization_id, code, version, effective_from, source_reference, status, rules
    ) values (
      p_organization_id, ''MGN_FIX'', 1, ''2020-01-01'', ''margin fixture'', ''ACTIVE'', ''{}''::jsonb
    ) returning id into v_rule;
  end if;

  perform set_config(''fiscal.engine_write'', ''1'', true);

  -- Insert AUTHORIZED header first, then lines (engine_write allows line insert)
  insert into public.fiscal_documents (
    organization_id, document_type_id, document_class, arca_cbte_tipo,
    point_of_sale_id, arca_point_of_sale, document_number,
    status, fiscal_environment, issue_date, counterparty_id,
    currency_code, currency_rate,
    net_taxed_amount, net_exempt_amount, net_untaxed_amount,
    vat_amount, other_taxes_amount, total_amount,
    cae, authorized_at, fiscal_rule_version_id, idempotency_key
  ) values (
    p_organization_id, v_dtype.id, v_dtype.document_class, v_dtype.arca_cbte_tipo,
    v_pos, v_pos_n, (extract(epoch from clock_timestamp()) * 1000)::bigint,
    ''AUTHORIZED'', ''HOMOLOGATION'', p_issue_date, v_cp,
    ''PES'', 1,
    p_stock_net + p_service_net, 0, 0,
    0, 0, p_stock_net + p_service_net,
    ''MGNCAE'' || substr(v_stamp, 1, 8),
    timezone(''utc'', now()), v_rule, ''mgn-fix-'' || gen_random_uuid()::text
  )
  returning id into v_fd;

  insert into public.fiscal_document_lines (
    organization_id, fiscal_document_id, line_number,
    description, quantity, unit_price, net_amount, vat_amount, line_total,
    source_sales_line_id
  ) values
    (p_organization_id, v_fd, 1, ''Stock'', 1, p_stock_net, p_stock_net, 0, p_stock_net, v_stock_line),
    (p_organization_id, v_fd, 2, ''Service'', 1, p_service_net, p_service_net, 0, p_service_net, v_svc_line);

  insert into public.fiscal_tax_summaries (
    organization_id, fiscal_document_id, summary_kind, code, base_amount, rate, amount
  ) values (
    p_organization_id, v_fd, ''IVA'', ''5'', p_stock_net + p_service_net, 0, 0
  );

  perform set_config(''inventory.engine_write'', ''1'', true);

  insert into public.inventory_operations (
    organization_id, internal_number, operation_type, status, accounting_status,
    operation_date, warehouse_id, description, idempotency_key, posted_at
  ) values (
    p_organization_id, ''ISS-MGN-'' || v_stamp, ''ISSUE'', ''POSTED'', ''NOT_APPLICABLE'',
    p_issue_date, v_wh, ''margin fixture issue'', ''mgn-iss-'' || gen_random_uuid()::text,
    timezone(''utc'', now())
  )
  returning id into v_op;

  insert into public.inventory_operation_lines (
    organization_id, inventory_operation_id, line_number, product_id, warehouse_id,
    direction, quantity, unit_code, unit_cost, value_delta, source_sales_line_id
  ) values (
    p_organization_id, v_op, 1, v_stock_prod, v_wh,
    ''OUT'', 1, ''UNIT'', p_cogs, p_cogs, v_stock_line
  )
  returning id into v_iol;

  insert into public.inventory_ledger_entries (
    organization_id, inventory_operation_id, inventory_operation_line_id,
    product_id, warehouse_id, movement_date, operation_type, direction,
    quantity, unit_cost, value_delta
  ) values (
    p_organization_id, v_op, v_iol,
    v_stock_prod, v_wh, p_issue_date, ''ISSUE'', ''OUT'',
    1, p_cogs, p_cogs
  );

  return jsonb_build_object(
    ''fiscal_document_id'', v_fd,
    ''stock_sales_line_id'', v_stock_line,
    ''service_sales_line_id'', v_svc_line,
    ''expected_margin'', (p_stock_net - p_cogs)
  );
end;
$$","revoke all on function public.analytics_test_fixture_mixed_product_margin(uuid, date, numeric, numeric, numeric)
  from public, anon, authenticated","grant execute on function public.analytics_test_fixture_mixed_product_margin(uuid, date, numeric, numeric, numeric)
  to service_role"}', 'phase11_margin_fixture'),
	('20261101230000', '{"-- Phase 11: fix mixed margin fixture — sales lines require DRAFT parent

create or replace function public.analytics_test_fixture_mixed_product_margin(
  p_organization_id uuid,
  p_issue_date date,
  p_stock_net numeric,
  p_service_net numeric,
  p_cogs numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_stock_prod uuid;
  v_svc_prod uuid;
  v_wh uuid;
  v_branch uuid;
  v_sales_doc uuid;
  v_stock_line uuid;
  v_svc_line uuid;
  v_dtype public.fiscal_document_types%rowtype;
  v_fd uuid;
  v_pos uuid;
  v_pos_n int;
  v_cp uuid;
  v_rule uuid;
  v_op uuid;
  v_iol uuid;
  v_stamp text := substr(replace(gen_random_uuid()::text, ''-'', ''''), 1, 10);
begin
  if auth.role() is distinct from ''service_role'' then
    raise exception ''analytics_test_fixture_mixed_product_margin is service_role only'';
  end if;

  select id into v_branch
  from public.branches
  where organization_id = p_organization_id
  limit 1;

  insert into public.warehouses (
    organization_id, branch_id, code, name, active
  ) values (
    p_organization_id, v_branch, ''WHMGN'' || upper(substr(v_stamp, 1, 4)), ''Margin fixture WH'', true
  )
  returning id into v_wh;

  insert into public.products (
    organization_id, sku, name, product_type, base_unit_code, track_inventory, active
  ) values (
    p_organization_id, ''MGN-S-'' || upper(v_stamp), ''Margin Stock Item'',
    ''STOCK_ITEM'', ''UNIT'', true, true
  )
  returning id into v_stock_prod;

  insert into public.products (
    organization_id, sku, name, product_type, base_unit_code, track_inventory, active
  ) values (
    p_organization_id, ''MGN-V-'' || upper(v_stamp), ''Margin Service'',
    ''SERVICE'', ''UNIT'', false, true
  )
  returning id into v_svc_prod;

  select c.id into v_cp
  from public.counterparties c
  where c.organization_id = p_organization_id
    and c.tax_id_normalized = public.normalize_counterparty_tax_id(''CUIT'', ''20111111112'')
  limit 1;
  if v_cp is null then
    insert into public.counterparties (
      organization_id, legal_name, tax_id_type, tax_id, is_active
    ) values (
      p_organization_id, ''Margin Fixture CP'', ''CUIT'', ''20111111112'', true
    ) returning id into v_cp;
  end if;
  insert into public.counterparty_roles (organization_id, counterparty_id, role)
  values (p_organization_id, v_cp, ''CUSTOMER'')
  on conflict do nothing;

  insert into public.sales_documents (
    organization_id, document_type, internal_number, counterparty_id, status,
    document_date, currency_code, subtotal, discount_total, total, branch_id
  ) values (
    p_organization_id, ''SALES_ORDER'', ''SO-MGN-'' || v_stamp, v_cp, ''DRAFT'',
    p_issue_date, ''ARS'', p_stock_net + p_service_net, 0, p_stock_net + p_service_net, v_branch
  )
  returning id into v_sales_doc;

  insert into public.sales_document_lines (
    organization_id, sales_document_id, line_number, product_id,
    description, quantity, unit_code, unit_price, line_subtotal, line_total
  ) values (
    p_organization_id, v_sales_doc, 1, v_stock_prod,
    ''Stock line'', 1, ''UNIT'', p_stock_net, p_stock_net, p_stock_net
  )
  returning id into v_stock_line;

  insert into public.sales_document_lines (
    organization_id, sales_document_id, line_number, product_id,
    description, quantity, unit_code, unit_price, line_subtotal, line_total
  ) values (
    p_organization_id, v_sales_doc, 2, v_svc_prod,
    ''Service line'', 1, ''UNIT'', p_service_net, p_service_net, p_service_net
  )
  returning id into v_svc_line;

  update public.sales_documents
  set status = ''CONFIRMED''
  where id = v_sales_doc;

  select * into v_dtype from public.fiscal_document_types where internal_code = ''INVOICE_A'' limit 1;

  insert into public.fiscal_points_of_sale (
    organization_id, environment, arca_point_of_sale, description, is_active
  ) values (
    p_organization_id, ''HOMOLOGATION'', 88, ''Margin fixture POS'', true
  )
  on conflict (organization_id, environment, arca_point_of_sale) do update
    set description = excluded.description
  returning id into v_pos;
  if v_pos is null then
    select id into v_pos from public.fiscal_points_of_sale
    where organization_id = p_organization_id
      and environment = ''HOMOLOGATION''
      and arca_point_of_sale = 88;
  end if;
  select arca_point_of_sale into v_pos_n from public.fiscal_points_of_sale where id = v_pos;

  select id into v_rule
  from public.fiscal_rule_versions
  where organization_id = p_organization_id and status = ''ACTIVE''
  order by effective_from desc limit 1;
  if v_rule is null then
    insert into public.fiscal_rule_versions (
      organization_id, code, version, effective_from, source_reference, status, rules
    ) values (
      p_organization_id, ''MGN_FIX'', 1, ''2020-01-01'', ''margin fixture'', ''ACTIVE'', ''{}''::jsonb
    ) returning id into v_rule;
  end if;

  perform set_config(''fiscal.engine_write'', ''1'', true);

  insert into public.fiscal_documents (
    organization_id, document_type_id, document_class, arca_cbte_tipo,
    point_of_sale_id, arca_point_of_sale, document_number,
    status, fiscal_environment, issue_date, counterparty_id,
    currency_code, currency_rate,
    net_taxed_amount, net_exempt_amount, net_untaxed_amount,
    vat_amount, other_taxes_amount, total_amount,
    cae, authorized_at, fiscal_rule_version_id, idempotency_key,
    sales_document_id
  ) values (
    p_organization_id, v_dtype.id, v_dtype.document_class, v_dtype.arca_cbte_tipo,
    v_pos, v_pos_n, (extract(epoch from clock_timestamp()) * 1000)::bigint,
    ''AUTHORIZED'', ''HOMOLOGATION'', p_issue_date, v_cp,
    ''PES'', 1,
    p_stock_net + p_service_net, 0, 0,
    0, 0, p_stock_net + p_service_net,
    ''MGNCAE'' || substr(v_stamp, 1, 8),
    timezone(''utc'', now()), v_rule, ''mgn-fix-'' || gen_random_uuid()::text,
    v_sales_doc
  )
  returning id into v_fd;

  insert into public.fiscal_document_lines (
    organization_id, fiscal_document_id, line_number,
    description, quantity, unit_price, net_amount, vat_amount, line_total,
    source_sales_line_id
  ) values
    (p_organization_id, v_fd, 1, ''Stock'', 1, p_stock_net, p_stock_net, 0, p_stock_net, v_stock_line),
    (p_organization_id, v_fd, 2, ''Service'', 1, p_service_net, p_service_net, 0, p_service_net, v_svc_line);

  insert into public.fiscal_tax_summaries (
    organization_id, fiscal_document_id, summary_kind, code, base_amount, rate, amount
  ) values (
    p_organization_id, v_fd, ''IVA'', ''5'', p_stock_net + p_service_net, 0, 0
  );

  perform set_config(''inventory.engine_write'', ''1'', true);

  insert into public.inventory_operations (
    organization_id, internal_number, operation_type, status, accounting_status,
    operation_date, warehouse_id, description, idempotency_key, posted_at,
    source_sales_document_id
  ) values (
    p_organization_id, ''ISS-MGN-'' || v_stamp, ''ISSUE'', ''POSTED'', ''NOT_APPLICABLE'',
    p_issue_date, v_wh, ''margin fixture issue'', ''mgn-iss-'' || gen_random_uuid()::text,
    timezone(''utc'', now()), v_sales_doc
  )
  returning id into v_op;

  insert into public.inventory_operation_lines (
    organization_id, inventory_operation_id, line_number, product_id, warehouse_id,
    direction, quantity, unit_code, unit_cost, value_delta, source_sales_line_id
  ) values (
    p_organization_id, v_op, 1, v_stock_prod, v_wh,
    ''OUT'', 1, ''UNIT'', p_cogs, p_cogs, v_stock_line
  )
  returning id into v_iol;

  insert into public.inventory_ledger_entries (
    organization_id, inventory_operation_id, inventory_operation_line_id,
    product_id, warehouse_id, movement_date, operation_type, direction,
    quantity, unit_cost, value_delta
  ) values (
    p_organization_id, v_op, v_iol,
    v_stock_prod, v_wh, p_issue_date, ''ISSUE'', ''OUT'',
    1, p_cogs, p_cogs
  );

  return jsonb_build_object(
    ''fiscal_document_id'', v_fd,
    ''stock_sales_line_id'', v_stock_line,
    ''service_sales_line_id'', v_svc_line,
    ''expected_margin'', (p_stock_net - p_cogs)
  );
end;
$$","revoke all on function public.analytics_test_fixture_mixed_product_margin(uuid, date, numeric, numeric, numeric)
  from public, anon, authenticated","grant execute on function public.analytics_test_fixture_mixed_product_margin(uuid, date, numeric, numeric, numeric)
  to service_role"}', 'phase11_margin_fixture_draft_lines'),
	('20261201100000', '{"-- Phase 12.1 — Release governance (STAGING seeds for rpcpdrzbcclofvjpgldb)
-- Deployment-trusted: this DB is STAGING; seeds reflect STAGING release policy.
-- Do NOT trust client-supplied environment parameters.

do $$ begin
  create type public.feature_release_status as enum (
    ''AVAILABLE'',
    ''PREVIEW'',
    ''COMING_SOON'',
    ''RESTRICTED'',
    ''BLOCKED'',
    ''RETIRED''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.feature_mandatory_core_policy as enum (
    ''NONE'',
    ''ALWAYS'',
    ''NEW_ORGS_ONLY''
  );
exception when duplicate_object then null;
end $$","create table if not exists public.feature_release_controls (
  id uuid primary key default gen_random_uuid(),
  feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  release_status public.feature_release_status not null,
  self_service_allowed boolean not null default false,
  mandatory_core_policy public.feature_mandatory_core_policy not null default ''NONE'',
  requires_legal_review boolean not null default false,
  requires_professional_review boolean not null default false,
  notes text,
  updated_at timestamptz not null default timezone(''utc'', now()),
  updated_by uuid references auth.users (id),
  constraint feature_release_controls_feature_uidx unique (feature_id)
)","create index if not exists feature_release_controls_status_idx
  on public.feature_release_controls (release_status)","create index if not exists feature_release_controls_updated_by_idx
  on public.feature_release_controls (updated_by)
  where updated_by is not null","create trigger feature_release_controls_set_updated_at
before update on public.feature_release_controls
for each row execute function public.set_updated_at()","alter table public.feature_release_controls enable row level security","drop policy if exists feature_release_controls_select on public.feature_release_controls","create policy feature_release_controls_select
  on public.feature_release_controls for select to authenticated
  using (true)","revoke all on table public.feature_release_controls from public, anon","grant select on table public.feature_release_controls to authenticated","grant all on table public.feature_release_controls to service_role","-- STAGING release seeds
insert into public.feature_release_controls (
  feature_id, release_status, self_service_allowed, mandatory_core_policy,
  requires_legal_review, requires_professional_review, notes
)
select c.id, v.release_status, v.self_service, v.core_policy, v.legal, v.prof, v.notes
from public.feature_catalog c
join (
  values
    (''dashboard'', ''AVAILABLE''::public.feature_release_status, false, ''ALWAYS''::public.feature_mandatory_core_policy, false, false, ''Mandatory core''),
    (''accounting'', ''AVAILABLE'', false, ''NEW_ORGS_ONLY'', false, false, ''Mandatory for new orgs; legacy exemption allowed''),
    (''customers'', ''AVAILABLE'', true, ''NONE'', false, false, null),
    (''suppliers'', ''AVAILABLE'', true, ''NONE'', false, false, null),
    (''sales'', ''AVAILABLE'', true, ''NONE'', false, false, null),
    (''purchases'', ''AVAILABLE'', true, ''NONE'', false, false, null),
    (''cash'', ''AVAILABLE'', true, ''NONE'', false, false, null),
    (''banks'', ''AVAILABLE'', true, ''NONE'', false, false, null),
    (''inventory'', ''AVAILABLE'', true, ''NONE'', false, false, null),
    (''pos'', ''AVAILABLE'', true, ''NONE'', false, false, null),
    (''reports'', ''AVAILABLE'', true, ''NONE'', false, false, null),
    (''taxes'', ''PREVIEW'', true, ''NONE'', true, true, ''Phase 10 technical; professional/legal review required''),
    (''fiscal_invoicing'', ''PREVIEW'', true, ''NONE'', true, false, ''STAGING preview; PRODUCTION must be BLOCKED until Phase 5 live gate''),
    (''medical_legal'', ''RESTRICTED'', false, ''NONE'', true, true, ''Regulated vertical — no self-service''),
    (''assets'', ''COMING_SOON'', false, ''NONE'', false, false, ''Not implemented''),
    (''projects'', ''COMING_SOON'', false, ''NONE'', false, false, ''Not implemented''),
    (''payroll'', ''COMING_SOON'', false, ''NONE'', false, false, ''Not implemented'')
) as v(code, release_status, self_service, core_policy, legal, prof, notes)
  on c.code = v.code
on conflict (feature_id) do update set
  release_status = excluded.release_status,
  self_service_allowed = excluded.self_service_allowed,
  mandatory_core_policy = excluded.mandatory_core_policy,
  requires_legal_review = excluded.requires_legal_review,
  requires_professional_review = excluded.requires_professional_review,
  notes = excluded.notes,
  updated_at = timezone(''utc'', now())","comment on table public.feature_release_controls is
  ''PLATFORM GOVERNANCE. STAGING DB seeds = staging policy. Never trust client environment params.''"}', 'phase12_release_governance'),
	('20261201110000', '{"-- Phase 12.2 — Organization feature entitlements (platform-owned)

do $$ begin
  create type public.feature_entitlement_status as enum (
    ''GRANTED'',
    ''RESTRICTED'',
    ''REVOKED'',
    ''EXPIRED''
  );
exception when duplicate_object then null;
end $$","do $$ begin
  create type public.feature_entitlement_source as enum (
    ''MIGRATION'',
    ''MANUAL'',
    ''PLAN'',
    ''TRIAL'',
    ''PROMO'',
    ''SYSTEM''
  );
exception when duplicate_object then null;
end $$","create table if not exists public.organization_feature_entitlements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  status public.feature_entitlement_status not null,
  source_type public.feature_entitlement_source not null,
  source_reference text,
  starts_at timestamptz,
  ends_at timestamptz,
  metadata jsonb not null default ''{}''::jsonb,
  granted_at timestamptz,
  granted_by uuid references auth.users (id),
  revoked_at timestamptz,
  revoked_by uuid references auth.users (id),
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint organization_feature_entitlements_org_feature_uidx
    unique (organization_id, feature_id),
  constraint organization_feature_entitlements_org_id_unique
    unique (organization_id, id)
)","create index if not exists organization_feature_entitlements_org_status_idx
  on public.organization_feature_entitlements (organization_id, status)","create index if not exists organization_feature_entitlements_feature_idx
  on public.organization_feature_entitlements (feature_id)","create index if not exists organization_feature_entitlements_granted_by_idx
  on public.organization_feature_entitlements (granted_by)
  where granted_by is not null","create index if not exists organization_feature_entitlements_revoked_by_idx
  on public.organization_feature_entitlements (revoked_by)
  where revoked_by is not null","create trigger organization_feature_entitlements_set_updated_at
before update on public.organization_feature_entitlements
for each row execute function public.set_updated_at()","alter table public.organization_feature_entitlements enable row level security","drop policy if exists organization_feature_entitlements_select on public.organization_feature_entitlements","create policy organization_feature_entitlements_select
  on public.organization_feature_entitlements for select to authenticated
  using (public.is_org_member(organization_id))","revoke all on table public.organization_feature_entitlements from public, anon","revoke insert, update, delete on table public.organization_feature_entitlements from authenticated","grant select on table public.organization_feature_entitlements to authenticated","grant all on table public.organization_feature_entitlements to service_role","comment on table public.organization_feature_entitlements is
  ''PLATFORM entitlement. Tenant SELECT only. No tenant DML. Pack/preference/onboarding cannot grant. starts_at/ends_at schema-ready; auto-expiry DEFERRED.''"}', 'phase12_entitlements'),
	('20261201120000', '{"-- Phase 12.3 — Organization feature preferences (RPC-only mutation)

create table if not exists public.organization_feature_preferences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  desired_enabled boolean not null default false,
  updated_by uuid references auth.users (id),
  updated_at timestamptz not null default timezone(''utc'', now()),
  created_at timestamptz not null default timezone(''utc'', now()),
  constraint organization_feature_preferences_org_feature_uidx
    unique (organization_id, feature_id),
  constraint organization_feature_preferences_org_id_unique
    unique (organization_id, id)
)","create index if not exists organization_feature_preferences_org_idx
  on public.organization_feature_preferences (organization_id)","create index if not exists organization_feature_preferences_feature_idx
  on public.organization_feature_preferences (feature_id)","create index if not exists organization_feature_preferences_updated_by_idx
  on public.organization_feature_preferences (updated_by)
  where updated_by is not null","create trigger organization_feature_preferences_set_updated_at
before update on public.organization_feature_preferences
for each row execute function public.set_updated_at()","alter table public.organization_feature_preferences enable row level security","drop policy if exists organization_feature_preferences_select on public.organization_feature_preferences","create policy organization_feature_preferences_select
  on public.organization_feature_preferences for select to authenticated
  using (public.is_org_member(organization_id))","revoke all on table public.organization_feature_preferences from public, anon","revoke insert, update, delete on table public.organization_feature_preferences from authenticated","grant select on table public.organization_feature_preferences to authenticated","grant all on table public.organization_feature_preferences to service_role","comment on table public.organization_feature_preferences is
  ''Tenant desired configuration. SELECT ok; mutation ONLY via set_organization_feature_preference / apply_module_pack.''"}', 'phase12_preferences'),
	('20261201130000', '{"-- Phase 12.4 — Feature dependencies (DAG; platform-only writes)

do $$ begin
  create type public.feature_dependency_kind as enum (
    ''HARD'',
    ''RECOMMENDED'',
    ''CONDITIONAL''
  );
exception when duplicate_object then null;
end $$","create table if not exists public.feature_dependencies (
  id uuid primary key default gen_random_uuid(),
  feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  required_feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  dependency_kind public.feature_dependency_kind not null,
  condition_code text,
  active boolean not null default true,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint feature_dependencies_no_self check (feature_id <> required_feature_id),
  constraint feature_dependencies_condition_ck check (
    (dependency_kind = ''CONDITIONAL'' and condition_code is not null and length(btrim(condition_code)) > 0)
    or (dependency_kind <> ''CONDITIONAL'' and condition_code is null)
  )
)","create unique index if not exists feature_dependencies_pair_uidx
  on public.feature_dependencies (
    feature_id,
    required_feature_id,
    dependency_kind,
    coalesce(condition_code, '''')
  )","create index if not exists feature_dependencies_required_idx
  on public.feature_dependencies (required_feature_id)
  where active","create index if not exists feature_dependencies_feature_idx
  on public.feature_dependencies (feature_id)
  where active","create trigger feature_dependencies_set_updated_at
before update on public.feature_dependencies
for each row execute function public.set_updated_at()","-- Cycle detection for HARD edges only (enforced on write)
create or replace function public.feature_dependencies_assert_dag()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
declare
  v_cycle boolean;
begin
  if new.dependency_kind is distinct from ''HARD''::public.feature_dependency_kind then
    return new;
  end if;
  if not coalesce(new.active, true) then
    return new;
  end if;

  with recursive walk as (
    select new.required_feature_id as fid, 1 as depth
    union all
    select d.required_feature_id, w.depth + 1
    from walk w
    join public.feature_dependencies d
      on d.feature_id = w.fid
     and d.active
     and d.dependency_kind = ''HARD''::public.feature_dependency_kind
    where w.depth < 32
  )
  select exists (select 1 from walk where fid = new.feature_id) into v_cycle;

  if v_cycle then
    raise exception ''FEATURE_DEPENDENCY_CYCLE'';
  end if;
  return new;
end;
$$","drop trigger if exists feature_dependencies_dag_trg on public.feature_dependencies","create trigger feature_dependencies_dag_trg
before insert or update on public.feature_dependencies
for each row execute function public.feature_dependencies_assert_dag()","alter table public.feature_dependencies enable row level security","drop policy if exists feature_dependencies_select on public.feature_dependencies","create policy feature_dependencies_select
  on public.feature_dependencies for select to authenticated
  using (active = true)","revoke all on table public.feature_dependencies from public, anon","grant select on table public.feature_dependencies to authenticated","grant all on table public.feature_dependencies to service_role","-- Proven HARD seeds only
insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, ''HARD''::public.feature_dependency_kind, null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = ''sales''
where f.code = ''pos''
on conflict do nothing","insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, ''HARD'', null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = ''sales''
where f.code = ''fiscal_invoicing''
on conflict do nothing","insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, ''HARD'', null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = ''customers''
where f.code = ''sales''
on conflict do nothing","insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, ''HARD'', null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = ''suppliers''
where f.code = ''purchases''
on conflict do nothing","-- RECOMMENDED (non-blocking)
insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, ''RECOMMENDED'', null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = ''inventory''
where f.code = ''pos''
on conflict do nothing","insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, ''RECOMMENDED'', null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = ''fiscal_invoicing''
where f.code = ''pos''
on conflict do nothing","insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, ''RECOMMENDED'', null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = ''cash''
where f.code = ''pos''
on conflict do nothing","-- CONDITIONAL documented codes (engine may surface; runtime POS remains source of truth)
insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, ''CONDITIONAL'', ''POS_HAS_STOCK_LINES'', true
from public.feature_catalog f
join public.feature_catalog r on r.code = ''inventory''
where f.code = ''pos''
on conflict do nothing","insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, ''CONDITIONAL'', ''POS_FISCAL_HANDOFF'', true
from public.feature_catalog f
join public.feature_catalog r on r.code = ''fiscal_invoicing''
where f.code = ''pos''
on conflict do nothing","comment on table public.feature_dependencies is
  ''Platform dependency graph. HARD is a DAG. No accounting HARD unless separately approved.''"}', 'phase12_dependencies'),
	('20261201140000', '{"-- Phase 12.5 — Module packs (presets; never entitlements)

do $$ begin
  create type public.module_pack_type as enum (
    ''STARTER'',
    ''FUNCTIONAL'',
    ''VERTICAL''
  );
exception when duplicate_object then null;
end $$","create table if not exists public.module_packs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  pack_type public.module_pack_type not null,
  active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default timezone(''utc'', now()),
  updated_at timestamptz not null default timezone(''utc'', now()),
  constraint module_packs_code_norm check (code = upper(btrim(code)))
)","create trigger module_packs_set_updated_at
before update on public.module_packs
for each row execute function public.set_updated_at()","create table if not exists public.module_pack_features (
  id uuid primary key default gen_random_uuid(),
  pack_id uuid not null references public.module_packs (id) on delete cascade,
  feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  recommended_enabled boolean not null default true,
  required_in_pack boolean not null default false,
  sort_order int not null default 0,
  constraint module_pack_features_pack_feature_uidx unique (pack_id, feature_id)
)","create index if not exists module_pack_features_feature_idx
  on public.module_pack_features (feature_id)","create table if not exists public.organization_pack_applications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  pack_id uuid not null references public.module_packs (id) on delete restrict,
  applied_by uuid references auth.users (id),
  applied_at timestamptz not null default timezone(''utc'', now()),
  configuration_before_hash text not null,
  configuration_after_hash text not null,
  result_snapshot jsonb not null default ''{}''::jsonb
)","create index if not exists organization_pack_applications_org_applied_idx
  on public.organization_pack_applications (organization_id, applied_at desc)","create index if not exists organization_pack_applications_pack_idx
  on public.organization_pack_applications (pack_id)","create index if not exists organization_pack_applications_applied_by_idx
  on public.organization_pack_applications (applied_by)
  where applied_by is not null","alter table public.module_packs enable row level security","alter table public.module_pack_features enable row level security","alter table public.organization_pack_applications enable row level security","drop policy if exists module_packs_select on public.module_packs","create policy module_packs_select
  on public.module_packs for select to authenticated
  using (active = true)","drop policy if exists module_pack_features_select on public.module_pack_features","create policy module_pack_features_select
  on public.module_pack_features for select to authenticated
  using (
    exists (
      select 1 from public.module_packs p
      where p.id = pack_id and p.active
    )
  )","drop policy if exists organization_pack_applications_select on public.organization_pack_applications","create policy organization_pack_applications_select
  on public.organization_pack_applications for select to authenticated
  using (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'', ''manager'']::public.member_role[]
    )
  )","revoke all on table public.module_packs from public, anon","revoke all on table public.module_pack_features from public, anon","revoke all on table public.organization_pack_applications from public, anon","grant select on table public.module_packs to authenticated","grant select on table public.module_pack_features to authenticated","grant select on table public.organization_pack_applications to authenticated","revoke insert, update, delete on table public.module_packs from authenticated","revoke insert, update, delete on table public.module_pack_features from authenticated","revoke insert, update, delete on table public.organization_pack_applications from authenticated","grant all on table public.module_packs to service_role","grant all on table public.module_pack_features to service_role","grant all on table public.organization_pack_applications to service_role","-- Seed packs
insert into public.module_packs (code, name, description, pack_type, sort_order) values
  (''STARTER_COMERCIO'', ''Comercio inicial'', ''Clientes, ventas, caja y reportes'', ''STARTER'', 10),
  (''GESTION_COMPRAS'', ''Gestión de compras'', ''Proveedores y compras'', ''FUNCTIONAL'', 20),
  (''OPERACION_STOCK'', ''Operación de stock'', ''Inventario'', ''FUNCTIONAL'', 30),
  (''MOSTRADOR_POS'', ''Mostrador / POS'', ''Punto de venta con ventas y caja'', ''FUNCTIONAL'', 40),
  (''FINANZAS_TESORERIA'', ''Tesorería'', ''Caja y bancos'', ''FUNCTIONAL'', 50),
  (''REPORTES_GERENCIALES'', ''Reportes gerenciales'', ''Reportes'', ''FUNCTIONAL'', 60),
  (''COMERCIO'', ''Vertical comercio'', ''Combinación comercio + stock + compras'', ''VERTICAL'', 70),
  (''SERVICIOS'', ''Vertical servicios'', ''Clientes, ventas, caja, reportes'', ''VERTICAL'', 80),
  (''GESTION_INTEGRAL'', ''Gestión integral'', ''Comercio + tesorería + reportes'', ''VERTICAL'', 90)
on conflict (code) do nothing","create or replace function public._phase12_seed_pack_feature(p_pack text, p_feature text, p_sort int)
returns void
language plpgsql
security definer
set search_path = ''''
as $$
begin
  insert into public.module_pack_features (pack_id, feature_id, recommended_enabled, required_in_pack, sort_order)
  select p.id, c.id, true, false, p_sort
  from public.module_packs p
  join public.feature_catalog c on c.code = p_feature
  where p.code = p_pack
  on conflict do nothing;
end;
$$","revoke all on function public._phase12_seed_pack_feature(text, text, int) from public, anon, authenticated","select public._phase12_seed_pack_feature(''STARTER_COMERCIO'', ''customers'', 10)","select public._phase12_seed_pack_feature(''STARTER_COMERCIO'', ''sales'', 20)","select public._phase12_seed_pack_feature(''STARTER_COMERCIO'', ''cash'', 30)","select public._phase12_seed_pack_feature(''STARTER_COMERCIO'', ''reports'', 40)","select public._phase12_seed_pack_feature(''GESTION_COMPRAS'', ''suppliers'', 10)","select public._phase12_seed_pack_feature(''GESTION_COMPRAS'', ''purchases'', 20)","select public._phase12_seed_pack_feature(''OPERACION_STOCK'', ''inventory'', 10)","select public._phase12_seed_pack_feature(''MOSTRADOR_POS'', ''sales'', 10)","select public._phase12_seed_pack_feature(''MOSTRADOR_POS'', ''pos'', 20)","select public._phase12_seed_pack_feature(''MOSTRADOR_POS'', ''cash'', 30)","select public._phase12_seed_pack_feature(''FINANZAS_TESORERIA'', ''cash'', 10)","select public._phase12_seed_pack_feature(''FINANZAS_TESORERIA'', ''banks'', 20)","select public._phase12_seed_pack_feature(''REPORTES_GERENCIALES'', ''reports'', 10)","select public._phase12_seed_pack_feature(''COMERCIO'', ''customers'', 10)","select public._phase12_seed_pack_feature(''COMERCIO'', ''sales'', 20)","select public._phase12_seed_pack_feature(''COMERCIO'', ''suppliers'', 30)","select public._phase12_seed_pack_feature(''COMERCIO'', ''purchases'', 40)","select public._phase12_seed_pack_feature(''COMERCIO'', ''inventory'', 50)","select public._phase12_seed_pack_feature(''COMERCIO'', ''cash'', 60)","select public._phase12_seed_pack_feature(''COMERCIO'', ''reports'', 70)","select public._phase12_seed_pack_feature(''SERVICIOS'', ''customers'', 10)","select public._phase12_seed_pack_feature(''SERVICIOS'', ''sales'', 20)","select public._phase12_seed_pack_feature(''SERVICIOS'', ''cash'', 30)","select public._phase12_seed_pack_feature(''SERVICIOS'', ''reports'', 40)","select public._phase12_seed_pack_feature(''GESTION_INTEGRAL'', ''customers'', 10)","select public._phase12_seed_pack_feature(''GESTION_INTEGRAL'', ''sales'', 20)","select public._phase12_seed_pack_feature(''GESTION_INTEGRAL'', ''suppliers'', 30)","select public._phase12_seed_pack_feature(''GESTION_INTEGRAL'', ''purchases'', 40)","select public._phase12_seed_pack_feature(''GESTION_INTEGRAL'', ''inventory'', 50)","select public._phase12_seed_pack_feature(''GESTION_INTEGRAL'', ''cash'', 60)","select public._phase12_seed_pack_feature(''GESTION_INTEGRAL'', ''banks'', 70)","select public._phase12_seed_pack_feature(''GESTION_INTEGRAL'', ''reports'', 80)","drop function if exists public._phase12_seed_pack_feature(text, text, int)"}', 'phase12_packs'),
	('20261201150000', '{"-- Phase 12.6 — Effective state engine (internal helpers + platform mutate+recompute)

create or replace function public.modules_assert_service_role()
returns void
language plpgsql
stable
security definer
set search_path = ''''
as $$
begin
  if auth.role() is distinct from ''service_role'' then
    raise exception ''MODULES_PLATFORM_ONLY'';
  end if;
end;
$$","revoke all on function public.modules_assert_service_role() from public, anon, authenticated","create or replace function public.modules_lock_organization(p_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = ''''
as $$
begin
  perform 1 from public.organizations where id = p_organization_id for update;
  if not found then
    raise exception ''ORGANIZATION_NOT_FOUND'';
  end if;
  perform pg_advisory_xact_lock(hashtext(''modules:'' || p_organization_id::text));
end;
$$","revoke all on function public.modules_lock_organization(uuid) from public, anon, authenticated","create or replace function public.modules_write_audit(
  p_organization_id uuid,
  p_actor uuid,
  p_event_type text,
  p_action text,
  p_metadata jsonb default ''{}''::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''''
as $$
begin
  insert into public.audit_events (
    organization_id, actor_user_id, event_type, entity_type, entity_id, action, metadata
  ) values (
    p_organization_id, p_actor, p_event_type, ''organization_feature'',
    coalesce(p_metadata->>''feature_code'', p_organization_id::text),
    p_action, coalesce(p_metadata, ''{}''::jsonb)
  );
end;
$$","revoke all on function public.modules_write_audit(uuid, uuid, text, text, jsonb)
  from public, anon, authenticated","create or replace function public.modules_entitlement_is_granted(
  p_organization_id uuid,
  p_feature_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''''
as $$
  select exists (
    select 1
    from public.organization_feature_entitlements e
    where e.organization_id = p_organization_id
      and e.feature_id = p_feature_id
      and e.status = ''GRANTED''::public.feature_entitlement_status
      -- Auto-expiry DEFERRED: ends_at is informational until platform expiration engine exists
  );
$$","revoke all on function public.modules_entitlement_is_granted(uuid, uuid)
  from public, anon, authenticated","create or replace function public.modules_entitlement_is_restricted(
  p_organization_id uuid,
  p_feature_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''''
as $$
  select exists (
    select 1
    from public.organization_feature_entitlements e
    where e.organization_id = p_organization_id
      and e.feature_id = p_feature_id
      and e.status = ''RESTRICTED''::public.feature_entitlement_status
  );
$$","revoke all on function public.modules_entitlement_is_restricted(uuid, uuid)
  from public, anon, authenticated","create or replace function public.modules_preference_desired(
  p_organization_id uuid,
  p_feature_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''''
as $$
  select coalesce(
    (
      select p.desired_enabled
      from public.organization_feature_preferences p
      where p.organization_id = p_organization_id
        and p.feature_id = p_feature_id
    ),
    false
  );
$$","revoke all on function public.modules_preference_desired(uuid, uuid)
  from public, anon, authenticated","-- Returns jsonb: { status: feature_status, reason: text, legacy_exemption: bool }
create or replace function public.modules_evaluate_feature_state(
  p_organization_id uuid,
  p_feature_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_code text;
  v_rel public.feature_release_controls%rowtype;
  v_ent public.organization_feature_entitlements%rowtype;
  v_pref boolean;
  v_dep_code text;
  v_dep_ok boolean;
  v_legacy boolean := false;
begin
  select code into v_code from public.feature_catalog where id = p_feature_id and active;
  if v_code is null then
    return jsonb_build_object(''status'', ''disabled'', ''reason'', ''FEATURE_INACTIVE'');
  end if;

  select * into v_rel from public.feature_release_controls where feature_id = p_feature_id;
  if not found then
    return jsonb_build_object(''status'', ''disabled'', ''reason'', ''RELEASE_MISSING'');
  end if;

  select * into v_ent
  from public.organization_feature_entitlements
  where organization_id = p_organization_id and feature_id = p_feature_id;

  if found and coalesce(v_ent.metadata->>''legacy_core_exemption'', ''false'') = ''true'' then
    v_legacy := true;
  end if;

  v_pref := public.modules_preference_desired(p_organization_id, p_feature_id);

  -- ALWAYS mandatory core: force enabled regardless of preference
  if v_rel.mandatory_core_policy = ''ALWAYS''::public.feature_mandatory_core_policy
     and v_rel.release_status in (
       ''AVAILABLE''::public.feature_release_status,
       ''PREVIEW''::public.feature_release_status
     )
     and public.modules_entitlement_is_granted(p_organization_id, p_feature_id)
  then
    return jsonb_build_object(''status'', ''enabled'', ''reason'', ''ACTIVE'', ''legacy_exemption'', false);
  end if;

  if v_rel.release_status = ''RESTRICTED''::public.feature_release_status
     or public.modules_entitlement_is_restricted(p_organization_id, p_feature_id)
  then
    return jsonb_build_object(''status'', ''restricted'', ''reason'', ''RESTRICTED'', ''legacy_exemption'', v_legacy);
  end if;

  if v_rel.release_status = ''COMING_SOON''::public.feature_release_status then
    return jsonb_build_object(''status'', ''disabled'', ''reason'', ''COMING_SOON'', ''legacy_exemption'', v_legacy);
  end if;

  if v_rel.release_status in (
    ''BLOCKED''::public.feature_release_status,
    ''RETIRED''::public.feature_release_status
  ) then
    return jsonb_build_object(''status'', ''disabled'', ''reason'', ''RELEASE_BLOCKED'', ''legacy_exemption'', v_legacy);
  end if;

  if not public.modules_entitlement_is_granted(p_organization_id, p_feature_id) then
    if v_legacy then
      return jsonb_build_object(''status'', ''disabled'', ''reason'', ''LEGACY_CORE_EXEMPTION'', ''legacy_exemption'', true);
    end if;
    return jsonb_build_object(''status'', ''disabled'', ''reason'', ''NOT_ENTITLED'', ''legacy_exemption'', false);
  end if;

  if not v_pref then
    if v_legacy then
      return jsonb_build_object(''status'', ''disabled'', ''reason'', ''LEGACY_CORE_EXEMPTION'', ''legacy_exemption'', true);
    end if;
    return jsonb_build_object(''status'', ''disabled'', ''reason'', ''PREFERENCE_DISABLED'', ''legacy_exemption'', false);
  end if;

  -- HARD dependencies must be effectively enabled (skipped during migration quiet pass)
  if coalesce(current_setting(''modules.migration_skip_hard_deps'', true), '''') is distinct from ''1'' then
    for v_dep_code in
      select rc.code
      from public.feature_dependencies d
      join public.feature_catalog rc on rc.id = d.required_feature_id
      where d.feature_id = p_feature_id
        and d.active
        and d.dependency_kind = ''HARD''::public.feature_dependency_kind
    loop
      select coalesce(
        (
          select ofe.status = ''enabled''::public.feature_status
          from public.organization_features ofe
          join public.feature_catalog fc on fc.id = ofe.feature_id
          where ofe.organization_id = p_organization_id and fc.code = v_dep_code
        ),
        false
      ) into v_dep_ok;
      if not v_dep_ok then
        return jsonb_build_object(
          ''status'', ''disabled'',
          ''reason'', ''DEPENDENCY_REQUIRED'',
          ''dependency'', v_dep_code,
          ''legacy_exemption'', v_legacy
        );
      end if;
    end loop;
  end if;

  if v_rel.requires_legal_review and v_rel.release_status = ''PREVIEW''::public.feature_release_status then
    -- still usable in staging preview; reason ACTIVE with review flags exposed separately
    null;
  end if;

  return jsonb_build_object(''status'', ''enabled'', ''reason'', ''ACTIVE'', ''legacy_exemption'', v_legacy);
end;
$$","revoke all on function public.modules_evaluate_feature_state(uuid, uuid)
  from public, anon, authenticated","create or replace function public.recompute_organization_features(
  p_organization_id uuid,
  p_actor uuid default null,
  p_source text default ''recompute''
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_feat record;
  v_eval jsonb;
  v_new_status public.feature_status;
  v_old_status public.feature_status;
  v_had boolean;
  v_changed int := 0;
  v_pass_changed int;
  v_pass int;
  v_engine text;
  v_quiet boolean;
begin
  perform public.modules_lock_organization(p_organization_id);
  v_engine := current_setting(''modules.engine_write'', true);
  perform set_config(''modules.engine_write'', ''1'', true);
  v_quiet := coalesce(current_setting(''modules.migration_quiet'', true), '''') = ''1'';

  -- Multi-pass so HARD dependency order converges
  for v_pass in 1..8 loop
    v_pass_changed := 0;
    for v_feat in
      select c.id, c.code
      from public.feature_catalog c
      where c.active
      order by c.sort_order, c.code
    loop
      v_eval := public.modules_evaluate_feature_state(p_organization_id, v_feat.id);
      v_new_status := (v_eval->>''status'')::public.feature_status;

      select true, ofe.status into v_had, v_old_status
      from public.organization_features ofe
      where ofe.organization_id = p_organization_id and ofe.feature_id = v_feat.id;

      if not coalesce(v_had, false) then
        insert into public.organization_features (
          organization_id, feature_id, status, enabled_at, metadata
        ) values (
          p_organization_id, v_feat.id, v_new_status,
          case when v_new_status = ''enabled'' then timezone(''utc'', now()) else null end,
          jsonb_build_object(''reason'', v_eval->>''reason'', ''source'', p_source)
        );
        v_pass_changed := v_pass_changed + 1;
        if not v_quiet then
          perform public.modules_write_audit(
            p_organization_id, p_actor, ''module.effective.changed'', ''create'',
            jsonb_build_object(
              ''feature_code'', v_feat.code,
              ''old_status'', ''disabled'',
              ''new_status'', v_new_status,
              ''reason'', v_eval->>''reason'',
              ''source'', p_source
            )
          );
        end if;
      elsif v_old_status is distinct from v_new_status then
        update public.organization_features
        set status = v_new_status,
            enabled_at = case
              when v_new_status = ''enabled'' then coalesce(enabled_at, timezone(''utc'', now()))
              else enabled_at
            end,
            metadata = coalesce(metadata, ''{}''::jsonb) || jsonb_build_object(
              ''reason'', v_eval->>''reason'',
              ''source'', p_source
            ),
            updated_at = timezone(''utc'', now())
        where organization_id = p_organization_id and feature_id = v_feat.id;
        v_pass_changed := v_pass_changed + 1;
        if not v_quiet then
          perform public.modules_write_audit(
            p_organization_id, p_actor, ''module.effective.changed'', ''update'',
            jsonb_build_object(
              ''feature_code'', v_feat.code,
              ''old_status'', v_old_status,
              ''new_status'', v_new_status,
              ''reason'', v_eval->>''reason'',
              ''source'', p_source
            )
          );
        end if;
      else
        update public.organization_features
        set metadata = coalesce(metadata, ''{}''::jsonb) || jsonb_build_object(
              ''reason'', v_eval->>''reason'',
              ''source'', p_source
            )
        where organization_id = p_organization_id and feature_id = v_feat.id;
      end if;
    end loop;
    v_changed := v_changed + v_pass_changed;
    exit when v_pass_changed = 0;
  end loop;

  if v_engine is null then
    perform set_config(''modules.engine_write'', '''', true);
  else
    perform set_config(''modules.engine_write'', v_engine, true);
  end if;

  return jsonb_build_object(
    ''organization_id'', p_organization_id,
    ''changed'', v_changed,
    ''hash'', public.modules_config_hash(p_organization_id)
  );
end;
$$","revoke all on function public.recompute_organization_features(uuid, uuid, text)
  from public, anon, authenticated","create or replace function public.modules_config_hash(p_organization_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_payload text;
begin
  select string_agg(
    format(
      ''%s|%s|%s|%s|%s'',
      c.code,
      coalesce(r.release_status::text, ''''),
      coalesce(e.status::text, ''NONE''),
      case when coalesce(p.desired_enabled, false) then ''1'' else ''0'' end,
      coalesce(ofe.status::text, ''disabled'')
    ),
    '','' order by c.code
  )
  into v_payload
  from public.feature_catalog c
  left join public.feature_release_controls r on r.feature_id = c.id
  left join public.organization_feature_entitlements e
    on e.organization_id = p_organization_id and e.feature_id = c.id
  left join public.organization_feature_preferences p
    on p.organization_id = p_organization_id and p.feature_id = c.id
  left join public.organization_features ofe
    on ofe.organization_id = p_organization_id and ofe.feature_id = c.id
  where c.active;

  return encode(extensions.digest(convert_to(coalesce(v_payload, ''''), ''UTF8''), ''sha256''), ''hex'');
end;
$$","revoke all on function public.modules_config_hash(uuid) from public, anon, authenticated","-- Disable safety: returns null if ok, else reason code
create or replace function public.modules_disable_block_reason(
  p_organization_id uuid,
  p_feature_code text
)
returns text
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_cnt int;
begin
  if p_feature_code = ''dashboard'' then
    return ''MANDATORY_CORE'';
  end if;

  if p_feature_code = ''fiscal_invoicing'' then
    select count(*)::int into v_cnt from public.fiscal_documents
    where organization_id = p_organization_id
      and status::text in (''AUTHORIZING'', ''RECONCILIATION_REQUIRED'');
    if v_cnt > 0 then return ''FISCAL_UNRESOLVED_TRUTH''; end if;
  end if;

  if p_feature_code = ''pos'' then
    select count(*)::int into v_cnt from public.pos_sessions
    where organization_id = p_organization_id and status::text = ''OPEN'';
    if v_cnt > 0 then return ''POS_OPEN_SESSION''; end if;
    select count(*)::int into v_cnt from public.pos_sales
    where organization_id = p_organization_id
      and status::text in (
        ''STOCK_RESERVED'', ''WAITING_FISCAL'', ''FISCAL_AUTHORIZED'',
        ''FINALIZING'', ''RECONCILIATION_REQUIRED''
      );
    if v_cnt > 0 then return ''POS_UNSAFE_WORKFLOW''; end if;
  end if;

  if p_feature_code = ''taxes'' then
    select count(*)::int into v_cnt from public.tax_periods
    where organization_id = p_organization_id and status::text = ''IN_REVIEW'';
    if v_cnt > 0 then return ''TAX_PERIOD_IN_REVIEW''; end if;
  end if;

  if p_feature_code = ''inventory'' then
    select count(*)::int into v_cnt from public.inventory_reservations
    where organization_id = p_organization_id and status::text = ''ACTIVE'';
    if v_cnt > 0 then return ''INVENTORY_ACTIVE_RESERVATION''; end if;
  end if;

  -- HARD dependents enabled → FEATURE_DEPENDENCY_IN_USE
  select count(*)::int into v_cnt
  from public.feature_dependencies d
  join public.feature_catalog f on f.id = d.feature_id
  join public.feature_catalog r on r.id = d.required_feature_id
  join public.organization_features ofe
    on ofe.organization_id = p_organization_id and ofe.feature_id = f.id
  where r.code = p_feature_code
    and d.active
    and d.dependency_kind = ''HARD''::public.feature_dependency_kind
    and ofe.status = ''enabled''::public.feature_status;
  if v_cnt > 0 then return ''FEATURE_DEPENDENCY_IN_USE''; end if;

  return null;
end;
$$","revoke all on function public.modules_disable_block_reason(uuid, text)
  from public, anon, authenticated","-- Recompute all orgs for one feature (release/entitlement propagation)
create or replace function public.recompute_feature_for_all_organizations(
  p_feature_id uuid,
  p_actor uuid default null,
  p_source text default ''release_change''
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_org uuid;
  v_n int := 0;
begin
  perform public.modules_assert_service_role();
  for v_org in select id from public.organizations order by created_at loop
    perform public.recompute_organization_features(v_org, p_actor, p_source);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object(''organizations_recomputed'', v_n, ''feature_id'', p_feature_id);
end;
$$","revoke all on function public.recompute_feature_for_all_organizations(uuid, uuid, text)
  from public, anon, authenticated","grant execute on function public.recompute_feature_for_all_organizations(uuid, uuid, text)
  to service_role","-- Platform: set release + recompute all
create or replace function public.platform_set_feature_release(
  p_feature_code text,
  p_release_status public.feature_release_status,
  p_self_service_allowed boolean default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_fid uuid;
  v_old public.feature_release_status;
begin
  perform public.modules_assert_service_role();
  select id into v_fid from public.feature_catalog where code = p_feature_code;
  if v_fid is null then raise exception ''FEATURE_NOT_FOUND''; end if;

  select release_status into v_old from public.feature_release_controls where feature_id = v_fid;
  update public.feature_release_controls
  set release_status = p_release_status,
      self_service_allowed = coalesce(p_self_service_allowed, self_service_allowed),
      notes = coalesce(p_notes, notes),
      updated_at = timezone(''utc'', now())
  where feature_id = v_fid;

  perform public.modules_write_audit(
    null, null, ''module.release.changed'', ''update'',
    jsonb_build_object(
      ''feature_code'', p_feature_code,
      ''old_status'', v_old,
      ''new_status'', p_release_status
    )
  );

  return public.recompute_feature_for_all_organizations(v_fid, null, ''release_change'');
end;
$$","revoke all on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text)
  from public, anon, authenticated","grant execute on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text)
  to service_role","create or replace function public.platform_grant_feature_entitlement(
  p_organization_id uuid,
  p_feature_code text,
  p_source_type public.feature_entitlement_source default ''MANUAL'',
  p_metadata jsonb default ''{}''::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_fid uuid;
begin
  perform public.modules_assert_service_role();
  select id into v_fid from public.feature_catalog where code = p_feature_code;
  if v_fid is null then raise exception ''FEATURE_NOT_FOUND''; end if;

  insert into public.organization_feature_entitlements (
    organization_id, feature_id, status, source_type, metadata, granted_at
  ) values (
    p_organization_id, v_fid, ''GRANTED'', p_source_type, coalesce(p_metadata, ''{}''::jsonb),
    timezone(''utc'', now())
  )
  on conflict (organization_id, feature_id) do update set
    status = ''GRANTED''::public.feature_entitlement_status,
    source_type = excluded.source_type,
    metadata = coalesce(public.organization_feature_entitlements.metadata, ''{}''::jsonb)
      || coalesce(excluded.metadata, ''{}''::jsonb),
    granted_at = timezone(''utc'', now()),
    revoked_at = null,
    revoked_by = null,
    updated_at = timezone(''utc'', now());

  perform public.modules_write_audit(
    p_organization_id, null, ''module.entitlement.granted'', ''grant'',
    jsonb_build_object(''feature_code'', p_feature_code, ''source_type'', p_source_type)
  );

  return public.recompute_organization_features(p_organization_id, null, ''entitlement_grant'');
end;
$$","revoke all on function public.platform_grant_feature_entitlement(uuid, text, public.feature_entitlement_source, jsonb)
  from public, anon, authenticated","grant execute on function public.platform_grant_feature_entitlement(uuid, text, public.feature_entitlement_source, jsonb)
  to service_role","create or replace function public.platform_revoke_feature_entitlement(
  p_organization_id uuid,
  p_feature_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_fid uuid;
begin
  perform public.modules_assert_service_role();
  select id into v_fid from public.feature_catalog where code = p_feature_code;
  if v_fid is null then raise exception ''FEATURE_NOT_FOUND''; end if;

  update public.organization_feature_entitlements
  set status = ''REVOKED''::public.feature_entitlement_status,
      revoked_at = timezone(''utc'', now()),
      updated_at = timezone(''utc'', now())
  where organization_id = p_organization_id and feature_id = v_fid;

  perform public.modules_write_audit(
    p_organization_id, null, ''module.entitlement.revoked'', ''revoke'',
    jsonb_build_object(''feature_code'', p_feature_code)
  );

  return public.recompute_organization_features(p_organization_id, null, ''entitlement_revoke'');
end;
$$","revoke all on function public.platform_revoke_feature_entitlement(uuid, text)
  from public, anon, authenticated","grant execute on function public.platform_revoke_feature_entitlement(uuid, text)
  to service_role","comment on function public.recompute_organization_features(uuid, uuid, text) is
  ''INTERNAL effective projection writer. No authenticated EXECUTE.''"}', 'phase12_effective_state_engine'),
	('20261201155000', '{"-- Phase 12.6b — Fix quiet migration recompute to PRESERVE existing effective statuses
-- (Applied after 150000; required before backfill verification.)

create or replace function public.recompute_organization_features(
  p_organization_id uuid,
  p_actor uuid default null,
  p_source text default ''recompute''
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_feat record;
  v_eval jsonb;
  v_new_status public.feature_status;
  v_old_status public.feature_status;
  v_had boolean;
  v_changed int := 0;
  v_pass_changed int;
  v_pass int;
  v_engine text;
  v_quiet boolean;
begin
  perform public.modules_lock_organization(p_organization_id);
  v_engine := current_setting(''modules.engine_write'', true);
  perform set_config(''modules.engine_write'', ''1'', true);
  v_quiet := coalesce(current_setting(''modules.migration_quiet'', true), '''') = ''1'';

  for v_pass in 1..8 loop
    v_pass_changed := 0;
    for v_feat in
      select c.id, c.code
      from public.feature_catalog c
      where c.active
      order by c.sort_order, c.code
    loop
      v_eval := public.modules_evaluate_feature_state(p_organization_id, v_feat.id);
      v_new_status := (v_eval->>''status'')::public.feature_status;

      select true, ofe.status into v_had, v_old_status
      from public.organization_features ofe
      where ofe.organization_id = p_organization_id and ofe.feature_id = v_feat.id;

      if v_quiet and coalesce(v_had, false) then
        update public.organization_features
        set metadata = coalesce(metadata, ''{}''::jsonb) || jsonb_build_object(
              ''reason'', v_eval->>''reason'',
              ''source'', p_source,
              ''evaluated_status'', v_new_status
            )
        where organization_id = p_organization_id and feature_id = v_feat.id;
        continue;
      end if;

      if not coalesce(v_had, false) then
        if v_quiet then
          v_new_status := ''disabled''::public.feature_status;
        end if;
        insert into public.organization_features (
          organization_id, feature_id, status, enabled_at, metadata
        ) values (
          p_organization_id, v_feat.id, v_new_status,
          case when v_new_status = ''enabled'' then timezone(''utc'', now()) else null end,
          jsonb_build_object(''reason'', v_eval->>''reason'', ''source'', p_source)
        );
        v_pass_changed := v_pass_changed + 1;
        if not v_quiet then
          perform public.modules_write_audit(
            p_organization_id, p_actor, ''module.effective.changed'', ''create'',
            jsonb_build_object(
              ''feature_code'', v_feat.code,
              ''old_status'', ''disabled'',
              ''new_status'', v_new_status,
              ''reason'', v_eval->>''reason'',
              ''source'', p_source
            )
          );
        end if;
      elsif v_old_status is distinct from v_new_status then
        update public.organization_features
        set status = v_new_status,
            enabled_at = case
              when v_new_status = ''enabled'' then coalesce(enabled_at, timezone(''utc'', now()))
              else enabled_at
            end,
            metadata = coalesce(metadata, ''{}''::jsonb) || jsonb_build_object(
              ''reason'', v_eval->>''reason'',
              ''source'', p_source
            ),
            updated_at = timezone(''utc'', now())
        where organization_id = p_organization_id and feature_id = v_feat.id;
        v_pass_changed := v_pass_changed + 1;
        if not v_quiet then
          perform public.modules_write_audit(
            p_organization_id, p_actor, ''module.effective.changed'', ''update'',
            jsonb_build_object(
              ''feature_code'', v_feat.code,
              ''old_status'', v_old_status,
              ''new_status'', v_new_status,
              ''reason'', v_eval->>''reason'',
              ''source'', p_source
            )
          );
        end if;
      else
        update public.organization_features
        set metadata = coalesce(metadata, ''{}''::jsonb) || jsonb_build_object(
              ''reason'', v_eval->>''reason'',
              ''source'', p_source
            )
        where organization_id = p_organization_id and feature_id = v_feat.id;
      end if;
    end loop;
    v_changed := v_changed + v_pass_changed;
    exit when v_pass_changed = 0 or v_quiet;
  end loop;

  if v_engine is null then
    perform set_config(''modules.engine_write'', '''', true);
  else
    perform set_config(''modules.engine_write'', v_engine, true);
  end if;

  return jsonb_build_object(
    ''organization_id'', p_organization_id,
    ''changed'', v_changed,
    ''hash'', public.modules_config_hash(p_organization_id)
  );
end;
$$","revoke all on function public.recompute_organization_features(uuid, uuid, text)
  from public, anon, authenticated"}', 'phase12_recompute_preserve_quiet'),
	('20261201160000', '{"-- Phase 12.7 — Before snapshot + entitlement/preference backfill + verify
-- INTENTIONAL CAPABILITY NARROWING: disabled optional rows do NOT receive GRANTED.

create table if not exists public.phase12_migration_effective_snapshot (
  organization_id uuid not null,
  feature_id uuid not null,
  feature_code text not null,
  row_exists boolean not null,
  effective_status text not null,
  snapshotted_at timestamptz not null default timezone(''utc'', now()),
  primary key (organization_id, feature_id)
)","revoke all on table public.phase12_migration_effective_snapshot from public, anon, authenticated","grant all on table public.phase12_migration_effective_snapshot to service_role","-- Snapshot EVERY org × active catalog feature (missing row = disabled)
insert into public.phase12_migration_effective_snapshot (
  organization_id, feature_id, feature_code, row_exists, effective_status
)
select
  o.id,
  c.id,
  c.code,
  (ofe.id is not null),
  case
    when ofe.id is null then ''disabled''
    else ofe.status::text
  end
from public.organizations o
cross join public.feature_catalog c
left join public.organization_features ofe
  on ofe.organization_id = o.id and ofe.feature_id = c.id
where c.active
on conflict do nothing","-- Backfill entitlements + preferences from snapshot rules
do $$
declare
  r record;
  v_ent public.feature_entitlement_status;
  v_src public.feature_entitlement_source;
  v_meta jsonb;
  v_pref boolean;
  v_grant boolean;
begin
  for r in
    select s.*, rc.mandatory_core_policy, rc.release_status
    from public.phase12_migration_effective_snapshot s
    left join public.feature_release_controls rc on rc.feature_id = s.feature_id
  loop
    v_grant := false;
    v_pref := false;
    v_ent := ''REVOKED''::public.feature_entitlement_status;
    v_src := ''MIGRATION''::public.feature_entitlement_source;
    v_meta := ''{}''::jsonb;

    if r.effective_status = ''enabled'' then
      v_grant := true;
      v_ent := ''GRANTED'';
      v_pref := true;
      v_meta := jsonb_build_object(''migration'', ''enabled'');
    elsif r.effective_status = ''restricted'' then
      v_grant := true;
      v_ent := ''RESTRICTED'';
      v_pref := false;
      v_meta := jsonb_build_object(''migration'', ''restricted'');
    elsif r.feature_code = ''dashboard'' then
      -- mandatory core always entitled
      v_grant := true;
      v_ent := ''GRANTED'';
      v_src := ''SYSTEM'';
      v_pref := true;
      v_meta := jsonb_build_object(''migration'', ''dashboard_core'');
    elsif r.feature_code = ''accounting'' and r.effective_status = ''disabled'' then
      -- LEGACY_CORE_EXEMPTION: entitled but preference off; effective stays disabled
      v_grant := true;
      v_ent := ''GRANTED'';
      v_src := ''SYSTEM'';
      v_pref := false;
      v_meta := jsonb_build_object(
        ''migration'', ''accounting_legacy'',
        ''legacy_core_exemption'', true
      );
    elsif r.feature_code = ''medical_legal'' then
      v_grant := true;
      v_ent := ''RESTRICTED'';
      v_pref := false;
      v_meta := jsonb_build_object(''migration'', ''medical_legal'');
    else
      -- DISABLED optional / coming-soon: NO GRANTED (capability narrowing)
      v_grant := false;
      v_pref := false;
    end if;

    if v_grant then
      insert into public.organization_feature_entitlements (
        organization_id, feature_id, status, source_type, metadata, granted_at
      ) values (
        r.organization_id, r.feature_id, v_ent, v_src, v_meta,
        case when v_ent = ''GRANTED'' then timezone(''utc'', now()) else null end
      )
      on conflict (organization_id, feature_id) do update set
        status = excluded.status,
        source_type = excluded.source_type,
        metadata = excluded.metadata,
        updated_at = timezone(''utc'', now());
    end if;

    insert into public.organization_feature_preferences (
      organization_id, feature_id, desired_enabled
    ) values (
      r.organization_id, r.feature_id, v_pref
    )
    on conflict (organization_id, feature_id) do update set
      desired_enabled = excluded.desired_enabled,
      updated_at = timezone(''utc'', now());
  end loop;
end $$","-- Quiet recompute all orgs (preserve effective; fill missing rows)
do $$
declare
  v_org uuid;
begin
  perform set_config(''modules.migration_quiet'', ''1'', true);
  perform set_config(''modules.migration_skip_hard_deps'', ''1'', true);
  for v_org in select id from public.organizations order by created_at loop
    perform public.recompute_organization_features(v_org, null, ''phase12_migration'');
  end loop;
  perform set_config(''modules.migration_skip_hard_deps'', '''', true);
  perform set_config(''modules.migration_quiet'', '''', true);
end $$","-- Verification table
create table if not exists public.phase12_migration_effective_diff (
  organization_id uuid not null,
  feature_code text not null,
  old_effective_status text not null,
  new_effective_status text not null,
  primary key (organization_id, feature_code)
)","revoke all on table public.phase12_migration_effective_diff from public, anon, authenticated","grant all on table public.phase12_migration_effective_diff to service_role","truncate public.phase12_migration_effective_diff","insert into public.phase12_migration_effective_diff (
  organization_id, feature_code, old_effective_status, new_effective_status
)
select
  s.organization_id,
  s.feature_code,
  s.effective_status,
  case
    when ofe.id is null then ''disabled''
    else ofe.status::text
  end
from public.phase12_migration_effective_snapshot s
left join public.organization_features ofe
  on ofe.organization_id = s.organization_id and ofe.feature_id = s.feature_id
where s.effective_status is distinct from case
  when ofe.id is null then ''disabled''
  else ofe.status::text
end","do $$
declare
  v_n int;
begin
  select count(*)::int into v_n from public.phase12_migration_effective_diff;
  if v_n > 0 then
    raise exception ''PHASE12_UNEXPECTED_EFFECTIVE_DIFFS count=% — STOP migration'', v_n;
  end if;
  raise notice ''PHASE12 migration verify: unexpected_effective_diff_count=0'';
end $$"}', 'phase12_migration_backfill'),
	('20261201170000', '{"-- Phase 12.8 — Lock down organization_features: engine-only writes

create or replace function public.organization_features_engine_write_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if current_setting(''modules.engine_write'', true) is distinct from ''1'' then
    raise exception ''organization_features is engine-managed; use set_organization_feature_preference'';
  end if;
  return case when tg_op = ''DELETE'' then old else new end;
end;
$$","drop trigger if exists organization_features_engine_write_trg on public.organization_features","create trigger organization_features_engine_write_trg
before insert or update or delete on public.organization_features
for each row execute function public.organization_features_engine_write_guard()","-- Drop tenant mutate policies
drop policy if exists organization_features_insert on public.organization_features","drop policy if exists organization_features_update on public.organization_features","drop policy if exists organization_features_delete on public.organization_features","drop policy if exists organization_features_mutate on public.organization_features","-- Keep SELECT for members (initplan-safe)
drop policy if exists organization_features_select on public.organization_features","create policy organization_features_select
  on public.organization_features for select to authenticated
  using (
    public.is_org_member(organization_id)
  )","-- ACL: authenticated SELECT only
revoke all on table public.organization_features from public, anon","revoke insert, update, delete on table public.organization_features from authenticated","grant select on table public.organization_features to authenticated","grant all on table public.organization_features to service_role","comment on table public.organization_features is
  ''EFFECTIVE runtime projection. Authenticated SELECT only. Writes via modules engine (modules.engine_write=1).''"}', 'phase12_lockdown_organization_features'),
	('20261201180000', '{"-- Phase 12.9 — Client RPCs (intentional authenticated EXECUTE)

create or replace function public.modules_assert_configure(p_organization_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception ''NOT_AUTHENTICATED''; end if;
  if not public.has_org_role(
    p_organization_id,
    array[''owner'', ''admin'']::public.member_role[]
  ) then
    raise exception ''MODULES_CONFIGURE_DENIED'';
  end if;
  return v_uid;
end;
$$","revoke all on function public.modules_assert_configure(uuid) from public, anon, authenticated","create or replace function public.modules_assert_read(p_organization_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception ''NOT_AUTHENTICATED''; end if;
  if not public.is_org_member(p_organization_id) then
    raise exception ''NOT_ORG_MEMBER'';
  end if;
  return v_uid;
end;
$$","revoke all on function public.modules_assert_read(uuid) from public, anon, authenticated","create or replace function public.get_module_configuration_state(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_items jsonb := ''[]''::jsonb;
  r record;
  v_eval jsonb;
  v_deps jsonb;
begin
  v_uid := public.modules_assert_read(p_organization_id);

  for r in
    select
      c.id, c.code, c.name, c.description, c.category, c.sort_order,
      rc.release_status, rc.self_service_allowed, rc.mandatory_core_policy,
      rc.requires_legal_review, rc.requires_professional_review,
      e.status as entitlement_status,
      coalesce(p.desired_enabled, false) as desired_enabled,
      coalesce(ofe.status::text, ''disabled'') as effective_status
    from public.feature_catalog c
    left join public.feature_release_controls rc on rc.feature_id = c.id
    left join public.organization_feature_entitlements e
      on e.organization_id = p_organization_id and e.feature_id = c.id
    left join public.organization_feature_preferences p
      on p.organization_id = p_organization_id and p.feature_id = c.id
    left join public.organization_features ofe
      on ofe.organization_id = p_organization_id and ofe.feature_id = c.id
    where c.active
    order by c.sort_order, c.code
  loop
    v_eval := public.modules_evaluate_feature_state(p_organization_id, r.id);
    select coalesce(jsonb_agg(jsonb_build_object(
      ''code'', req.code,
      ''kind'', d.dependency_kind,
      ''condition_code'', d.condition_code
    ) order by d.dependency_kind, req.code), ''[]''::jsonb)
    into v_deps
    from public.feature_dependencies d
    join public.feature_catalog req on req.id = d.required_feature_id
    where d.feature_id = r.id and d.active;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      ''feature_code'', r.code,
      ''name'', r.name,
      ''description'', r.description,
      ''category'', r.category,
      ''release_status'', r.release_status,
      ''entitlement_status'', r.entitlement_status,
      ''desired_enabled'', r.desired_enabled,
      ''effective_status'', r.effective_status,
      ''blocking_reason_code'', v_eval->>''reason'',
      ''self_service_allowed'', coalesce(r.self_service_allowed, false),
      ''mandatory_core_policy'', r.mandatory_core_policy,
      ''requires_legal_review'', coalesce(r.requires_legal_review, false),
      ''requires_professional_review'', coalesce(r.requires_professional_review, false),
      ''legacy_exemption'', coalesce((v_eval->>''legacy_exemption'')::boolean, false),
      ''dependencies'', v_deps
    ));
  end loop;

  return jsonb_build_object(
    ''organization_id'', p_organization_id,
    ''configuration_hash'', public.modules_config_hash(p_organization_id),
    ''modules'', v_items,
    ''generated_by'', v_uid
  );
end;
$$","revoke all on function public.get_module_configuration_state(uuid) from public, anon","grant execute on function public.get_module_configuration_state(uuid) to authenticated","create or replace function public.why_feature_unavailable(
  p_organization_id uuid,
  p_feature_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_fid uuid;
  v_eval jsonb;
begin
  perform public.modules_assert_read(p_organization_id);
  select id into v_fid from public.feature_catalog where code = p_feature_code;
  if v_fid is null then raise exception ''FEATURE_NOT_FOUND''; end if;
  v_eval := public.modules_evaluate_feature_state(p_organization_id, v_fid);
  return jsonb_build_object(
    ''feature_code'', p_feature_code,
    ''reason'', v_eval->>''reason'',
    ''status'', v_eval->>''status'',
    ''dependency'', v_eval->>''dependency''
  );
end;
$$","revoke all on function public.why_feature_unavailable(uuid, text) from public, anon","grant execute on function public.why_feature_unavailable(uuid, text) to authenticated","create or replace function public.set_organization_feature_preference(
  p_organization_id uuid,
  p_feature_code text,
  p_desired_enabled boolean,
  p_confirm_dependencies boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_fid uuid;
  v_rel public.feature_release_controls%rowtype;
  v_block text;
  v_hash_before text;
  v_hash_after text;
  v_dep_code text;
  v_dep_fid uuid;
  v_dep_rel public.feature_release_controls%rowtype;
begin
  v_uid := public.modules_assert_configure(p_organization_id);
  perform public.modules_lock_organization(p_organization_id);

  select id into v_fid from public.feature_catalog where code = p_feature_code and active;
  if v_fid is null then raise exception ''FEATURE_NOT_FOUND''; end if;
  select * into v_rel from public.feature_release_controls where feature_id = v_fid;
  if not found then raise exception ''RELEASE_MISSING''; end if;

  v_hash_before := public.modules_config_hash(p_organization_id);

  if v_rel.mandatory_core_policy = ''ALWAYS''::public.feature_mandatory_core_policy
     and not p_desired_enabled then
    raise exception ''MANDATORY_CORE'';
  end if;

  if p_feature_code = ''accounting'' and not p_desired_enabled then
    if exists (
      select 1 from public.organization_features ofe
      where ofe.organization_id = p_organization_id and ofe.feature_id = v_fid
        and ofe.status = ''enabled''
    ) then
      raise exception ''MANDATORY_CORE'';
    end if;
  end if;

  if p_desired_enabled then
    if v_rel.release_status = ''COMING_SOON''::public.feature_release_status then
      raise exception ''FEATURE_NOT_RELEASED'';
    end if;
    if v_rel.release_status in (
      ''BLOCKED''::public.feature_release_status,
      ''RETIRED''::public.feature_release_status
    ) then
      raise exception ''RELEASE_BLOCKED'';
    end if;
    if v_rel.release_status = ''RESTRICTED''::public.feature_release_status then
      raise exception ''RESTRICTED'';
    end if;
    if not coalesce(v_rel.self_service_allowed, false)
       and v_rel.mandatory_core_policy = ''NONE''::public.feature_mandatory_core_policy then
      raise exception ''SELF_SERVICE_DENIED'';
    end if;
    -- NEW_ORGS_ONLY accounting: self-service enable allowed when entitled
    if p_feature_code = ''accounting''
       and not public.modules_entitlement_is_granted(p_organization_id, v_fid) then
      raise exception ''NOT_ENTITLED'';
    end if;
    if p_feature_code <> ''accounting''
       and not public.modules_entitlement_is_granted(p_organization_id, v_fid) then
      raise exception ''NOT_ENTITLED'';
    end if;
    if public.modules_entitlement_is_restricted(p_organization_id, v_fid) then
      raise exception ''RESTRICTED'';
    end if;

    for v_dep_code in
      select req.code
      from public.feature_dependencies d
      join public.feature_catalog req on req.id = d.required_feature_id
      left join public.organization_features ofe
        on ofe.organization_id = p_organization_id and ofe.feature_id = req.id
      where d.feature_id = v_fid
        and d.active
        and d.dependency_kind = ''HARD''::public.feature_dependency_kind
        and coalesce(ofe.status, ''disabled''::public.feature_status)
          is distinct from ''enabled''::public.feature_status
    loop
      if not p_confirm_dependencies then
        raise exception ''DEPENDENCY_REQUIRED:%'', v_dep_code;
      end if;
      select id into v_dep_fid from public.feature_catalog where code = v_dep_code;
      select * into v_dep_rel from public.feature_release_controls where feature_id = v_dep_fid;
      if not public.modules_entitlement_is_granted(p_organization_id, v_dep_fid) then
        raise exception ''NOT_ENTITLED:%'', v_dep_code;
      end if;
      if not coalesce(v_dep_rel.self_service_allowed, false)
         and v_dep_rel.mandatory_core_policy = ''NONE''::public.feature_mandatory_core_policy then
        raise exception ''SELF_SERVICE_DENIED:%'', v_dep_code;
      end if;
      insert into public.organization_feature_preferences (
        organization_id, feature_id, desired_enabled, updated_by
      ) values (p_organization_id, v_dep_fid, true, v_uid)
      on conflict (organization_id, feature_id) do update set
        desired_enabled = true,
        updated_by = excluded.updated_by,
        updated_at = timezone(''utc'', now());
    end loop;
  else
    v_block := public.modules_disable_block_reason(p_organization_id, p_feature_code);
    if v_block is not null then
      perform public.modules_write_audit(
        p_organization_id, v_uid, ''module.disable.blocked'', ''block'',
        jsonb_build_object(''feature_code'', p_feature_code, ''reason'', v_block)
      );
      raise exception ''%'', v_block;
    end if;
  end if;

  insert into public.organization_feature_preferences (
    organization_id, feature_id, desired_enabled, updated_by
  ) values (
    p_organization_id, v_fid, p_desired_enabled, v_uid
  )
  on conflict (organization_id, feature_id) do update set
    desired_enabled = excluded.desired_enabled,
    updated_by = excluded.updated_by,
    updated_at = timezone(''utc'', now());

  if p_feature_code = ''accounting'' and p_desired_enabled then
    update public.organization_feature_entitlements
    set metadata = coalesce(metadata, ''{}''::jsonb)
      || jsonb_build_object(''legacy_core_exemption'', false, ''activated_from_legacy'', true),
        updated_at = timezone(''utc'', now())
    where organization_id = p_organization_id and feature_id = v_fid;
  end if;

  perform public.modules_write_audit(
    p_organization_id, v_uid,
    case when p_desired_enabled then ''module.preference.enabled'' else ''module.preference.disabled'' end,
    ''update'',
    jsonb_build_object(''feature_code'', p_feature_code, ''desired_enabled'', p_desired_enabled)
  );

  perform public.recompute_organization_features(p_organization_id, v_uid, ''preference_change'');
  v_hash_after := public.modules_config_hash(p_organization_id);

  return jsonb_build_object(
    ''feature_code'', p_feature_code,
    ''desired_enabled'', p_desired_enabled,
    ''configuration_before_hash'', v_hash_before,
    ''configuration_after_hash'', v_hash_after
  );
end;
$$","create or replace function public.preview_module_pack(
  p_organization_id uuid,
  p_pack_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_pack public.module_packs%rowtype;
  v_items jsonb := ''[]''::jsonb;
  r record;
  v_class text;
begin
  v_uid := public.modules_assert_configure(p_organization_id);
  select * into v_pack from public.module_packs where id = p_pack_id and active;
  if not found then raise exception ''PACK_NOT_FOUND''; end if;

  for r in
    select
      c.code,
      c.name,
      mpf.recommended_enabled,
      rc.release_status,
      e.status as entitlement_status,
      coalesce(ofe.status::text, ''disabled'') as effective_status
    from public.module_pack_features mpf
    join public.feature_catalog c on c.id = mpf.feature_id
    left join public.feature_release_controls rc on rc.feature_id = c.id
    left join public.organization_feature_entitlements e
      on e.organization_id = p_organization_id and e.feature_id = c.id
    left join public.organization_features ofe
      on ofe.organization_id = p_organization_id and ofe.feature_id = c.id
    where mpf.pack_id = p_pack_id
    order by mpf.sort_order, c.code
  loop
    if r.release_status = ''COMING_SOON''::public.feature_release_status then
      v_class := ''coming_soon'';
    elsif r.release_status = ''RESTRICTED''::public.feature_release_status
         or r.entitlement_status = ''RESTRICTED''::public.feature_entitlement_status then
      v_class := ''restricted'';
    elsif r.release_status in (
      ''BLOCKED''::public.feature_release_status,
      ''RETIRED''::public.feature_release_status
    ) then
      v_class := ''release_blocked'';
    elsif r.entitlement_status is distinct from ''GRANTED''::public.feature_entitlement_status then
      v_class := ''not_entitled'';
    elsif r.effective_status = ''enabled'' then
      v_class := ''already_enabled'';
    else
      v_class := ''available'';
    end if;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      ''feature_code'', r.code,
      ''name'', r.name,
      ''classification'', v_class,
      ''recommended_enabled'', r.recommended_enabled
    ));
  end loop;

  return jsonb_build_object(
    ''pack_id'', p_pack_id,
    ''pack_code'', v_pack.code,
    ''pack_name'', v_pack.name,
    ''configuration_before_hash'', public.modules_config_hash(p_organization_id),
    ''items'', v_items,
    ''generated_by'', v_uid
  );
end;
$$","revoke all on function public.preview_module_pack(uuid, uuid) from public, anon","grant execute on function public.preview_module_pack(uuid, uuid) to authenticated","create or replace function public.apply_module_pack(
  p_organization_id uuid,
  p_pack_id uuid,
  p_expected_configuration_hash text,
  p_confirm boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid;
  v_preview jsonb;
  v_hash text;
  v_item jsonb;
  v_code text;
  v_class text;
  v_enabled int := 0;
  v_skipped int := 0;
  v_after text;
begin
  v_uid := public.modules_assert_configure(p_organization_id);
  if not p_confirm then raise exception ''CONFIRM_REQUIRED''; end if;

  perform public.modules_lock_organization(p_organization_id);
  v_hash := public.modules_config_hash(p_organization_id);
  if v_hash is distinct from p_expected_configuration_hash then
    raise exception ''CONFIGURATION_CHANGED'';
  end if;

  v_preview := public.preview_module_pack(p_organization_id, p_pack_id);

  for v_item in select * from jsonb_array_elements(v_preview->''items'')
  loop
    v_code := v_item->>''feature_code'';
    v_class := v_item->>''classification'';
    if v_class = ''available'' and coalesce((v_item->>''recommended_enabled'')::boolean, true) then
      begin
        perform public.set_organization_feature_preference(
          p_organization_id, v_code, true, true
        );
        v_enabled := v_enabled + 1;
      exception when others then
        v_skipped := v_skipped + 1;
      end;
    else
      v_skipped := v_skipped + 1;
    end if;
  end loop;

  v_after := public.modules_config_hash(p_organization_id);

  insert into public.organization_pack_applications (
    organization_id, pack_id, applied_by,
    configuration_before_hash, configuration_after_hash, result_snapshot
  ) values (
    p_organization_id, p_pack_id, v_uid,
    v_hash, v_after,
    jsonb_build_object(
      ''enabled_count'', v_enabled,
      ''skipped_count'', v_skipped,
      ''preview'', v_preview
    )
  );

  perform public.modules_write_audit(
    p_organization_id, v_uid, ''module.pack.applied'', ''apply'',
    jsonb_build_object(
      ''pack_id'', p_pack_id,
      ''enabled_count'', v_enabled,
      ''configuration_before_hash'', v_hash,
      ''configuration_after_hash'', v_after
    )
  );

  return jsonb_build_object(
    ''pack_id'', p_pack_id,
    ''enabled_count'', v_enabled,
    ''skipped_count'', v_skipped,
    ''configuration_before_hash'', v_hash,
    ''configuration_after_hash'', v_after
  );
end;
$$","revoke all on function public.apply_module_pack(uuid, uuid, text, boolean) from public, anon","grant execute on function public.apply_module_pack(uuid, uuid, text, boolean) to authenticated","comment on function public.apply_module_pack(uuid, uuid, text, boolean) is
  ''SECURITY DEFINER intentional: ADD/ENABLE preferences only. Never grants entitlements.''","comment on function public.get_module_configuration_state(uuid) is
  ''SECURITY DEFINER intentional client RPC: module configurator read model.''"}', 'phase12_client_rpcs'),
	('20261201190000', '{"-- Phase 12.10 — Source feature-guard hardening + new-org bootstrap
-- Restores Phase 4 sales RPC bodies with sales_assert_feature after role checks.

create or replace function public.sales_assert_feature(p_organization_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''''
as $$
begin
  if not exists (
    select 1
    from public.organization_features ofe
    join public.feature_catalog fc on fc.id = ofe.feature_id
    where ofe.organization_id = p_organization_id
      and fc.code = ''sales''
      and ofe.status = ''enabled''::public.feature_status
  ) then
    raise exception ''feature sales is not enabled'';
  end if;
end;
$$","revoke all on function public.sales_assert_feature(uuid) from public, anon, authenticated","create or replace function public.send_quote(p_document_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
  v_line_count int;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;
  select * into v_doc from public.sales_documents where id = p_document_id for update;
  if v_doc.id is null then raise exception ''document not found''; end if;
  if v_doc.document_type <> ''QUOTE'' then raise exception ''not a quote''; end if;
  perform public.sales_assert_role(v_doc.organization_id, array[''owner'',''admin'',''manager'',''operator'']::public.member_role[]);
  perform public.sales_assert_feature(v_doc.organization_id);
  if v_doc.status <> ''DRAFT'' then raise exception ''only draft quotes can be sent''; end if;
  select count(*) into v_line_count from public.sales_document_lines where sales_document_id = v_doc.id;
  if v_line_count < 1 then raise exception ''quote must have at least one line''; end if;
  perform public.validate_sales_customer(v_doc.organization_id, v_doc.counterparty_id);
  perform public.refresh_sales_document_totals(v_doc.id);
  perform set_config(''sales.engine_write'', ''1'', true);
  update public.sales_documents
  set status = ''SENT'',
      counterparty_snapshot = public.build_counterparty_snapshot(v_doc.organization_id, v_doc.counterparty_id),
      is_commercially_frozen = true
  where id = v_doc.id returning * into v_doc;
  perform set_config(''sales.engine_write'', ''0'', true);
  perform public.sales_write_audit(
    v_doc.organization_id, v_uid, ''sales.quote.sent'', v_doc.id, ''send'',
    jsonb_build_object(''internal_number'', v_doc.internal_number, ''total'', v_doc.total, ''currency_code'', v_doc.currency_code)
  );
  return v_doc;
end;
$$","create or replace function public.accept_quote(p_document_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;
  select * into v_doc from public.sales_documents where id = p_document_id for update;
  if v_doc.id is null then raise exception ''document not found''; end if;
  if v_doc.document_type <> ''QUOTE'' then raise exception ''not a quote''; end if;
  perform public.sales_assert_role(v_doc.organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]);
  perform public.sales_assert_feature(v_doc.organization_id);
  if v_doc.status <> ''SENT'' then raise exception ''only sent quotes can be accepted''; end if;
  if v_doc.valid_until is not null and v_doc.valid_until < (timezone(''utc'', now()))::date then
    raise exception ''quote is expired'';
  end if;
  perform set_config(''sales.engine_write'', ''1'', true);
  update public.sales_documents
  set status = ''ACCEPTED'', confirmed_by = v_uid, confirmed_at = timezone(''utc'', now())
  where id = v_doc.id returning * into v_doc;
  perform set_config(''sales.engine_write'', ''0'', true);
  perform public.sales_write_audit(
    v_doc.organization_id, v_uid, ''sales.quote.accepted'', v_doc.id, ''accept'',
    jsonb_build_object(''internal_number'', v_doc.internal_number)
  );
  return v_doc;
end;
$$","create or replace function public.reject_quote(p_document_id uuid, p_reason text default null)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;
  select * into v_doc from public.sales_documents where id = p_document_id for update;
  if v_doc.document_type <> ''QUOTE'' then raise exception ''not a quote''; end if;
  perform public.sales_assert_role(v_doc.organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]);
  perform public.sales_assert_feature(v_doc.organization_id);
  if v_doc.status not in (''SENT'', ''ACCEPTED'') then raise exception ''quote cannot be rejected from this status''; end if;
  perform set_config(''sales.engine_write'', ''1'', true);
  update public.sales_documents
  set status = ''REJECTED'', cancelled_at = timezone(''utc'', now()), cancel_reason = nullif(trim(p_reason), '''')
  where id = p_document_id returning * into v_doc;
  perform set_config(''sales.engine_write'', ''0'', true);
  perform public.sales_write_audit(v_doc.organization_id, v_uid, ''sales.quote.rejected'', v_doc.id, ''reject'', ''{}''::jsonb);
  return v_doc;
end;
$$","create or replace function public.cancel_sales_document(p_document_id uuid, p_reason text default null)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;
  select * into v_doc from public.sales_documents where id = p_document_id for update;
  perform public.sales_assert_role(v_doc.organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]);
  perform public.sales_assert_feature(v_doc.organization_id);
  if v_doc.document_type = ''QUOTE'' and v_doc.status in (''CONVERTED'', ''REJECTED'', ''CANCELLED'') then
    raise exception ''quote cannot be cancelled'';
  end if;
  if v_doc.document_type = ''SALES_ORDER'' and v_doc.status in (''READY_TO_INVOICE'', ''INVOICED'', ''CANCELLED'') then
    raise exception ''order cannot be cancelled'';
  end if;
  perform set_config(''sales.engine_write'', ''1'', true);
  update public.sales_documents
  set status = ''CANCELLED'', cancelled_at = timezone(''utc'', now()), cancel_reason = nullif(trim(p_reason), '''')
  where id = p_document_id returning * into v_doc;
  perform set_config(''sales.engine_write'', ''0'', true);
  perform public.sales_write_audit(
    v_doc.organization_id, v_uid,
    case when v_doc.document_type = ''QUOTE'' then ''sales.quote.cancelled'' else ''sales.order.cancelled'' end,
    v_doc.id, ''cancel'', ''{}''::jsonb
  );
  return v_doc;
end;
$$","create or replace function public.convert_quote_to_order(p_quote_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_quote public.sales_documents;
  v_order public.sales_documents;
  v_number text;
  r record;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;
  select * into v_quote from public.sales_documents where id = p_quote_id for update;
  if v_quote.document_type <> ''QUOTE'' then raise exception ''not a quote''; end if;
  perform public.sales_assert_role(v_quote.organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]);
  perform public.sales_assert_feature(v_quote.organization_id);
  if v_quote.converted_to_order_id is not null then
    select * into v_order from public.sales_documents where id = v_quote.converted_to_order_id;
    return v_order;
  end if;
  if v_quote.status <> ''ACCEPTED'' then raise exception ''only accepted quotes can be converted''; end if;
  perform public.validate_sales_customer(v_quote.organization_id, v_quote.counterparty_id);
  v_number := public.next_sales_internal_number(v_quote.organization_id, ''SALES_ORDER'', v_quote.document_date);
  perform set_config(''sales.engine_write'', ''1'', true);
  insert into public.sales_documents (
    organization_id, branch_id, document_type, internal_number, counterparty_id, status,
    document_date, expected_delivery_date, currency_code, description, customer_reference,
    payment_terms_text, payment_due_days, notes, source_document_id,
    counterparty_snapshot, subtotal, discount_total, total,
    is_commercially_frozen, created_by
  ) values (
    v_quote.organization_id, v_quote.branch_id, ''SALES_ORDER'', v_number, v_quote.counterparty_id, ''DRAFT'',
    v_quote.document_date, v_quote.expected_delivery_date, v_quote.currency_code, v_quote.description,
    v_quote.customer_reference, v_quote.payment_terms_text, v_quote.payment_due_days, v_quote.notes,
    v_quote.id, v_quote.counterparty_snapshot, v_quote.subtotal, v_quote.discount_total, v_quote.total,
    true, v_uid
  ) returning * into v_order;
  for r in select * from public.sales_document_lines where sales_document_id = v_quote.id order by line_number loop
    insert into public.sales_document_lines (
      organization_id, sales_document_id, line_number, description, quantity, unit_code,
      unit_price, discount_input_mode, discount_percent, discount_amount,
      line_subtotal, line_total, notes
    ) values (
      r.organization_id, v_order.id, r.line_number, r.description, r.quantity, r.unit_code,
      r.unit_price, r.discount_input_mode, r.discount_percent, r.discount_amount,
      r.line_subtotal, r.line_total, r.notes
    );
  end loop;
  update public.sales_documents
  set status = ''CONVERTED'', converted_to_order_id = v_order.id
  where id = v_quote.id;
  perform set_config(''sales.engine_write'', ''0'', true);
  perform public.sales_write_audit(
    v_quote.organization_id, v_uid, ''sales.quote.converted'', v_quote.id, ''convert'',
    jsonb_build_object(''order_id'', v_order.id, ''order_number'', v_order.internal_number)
  );
  perform public.sales_write_audit(
    v_order.organization_id, v_uid, ''sales.order.created'', v_order.id, ''create'',
    jsonb_build_object(''source_quote_id'', v_quote.id, ''from_conversion'', true)
  );
  return v_order;
end;
$$","create or replace function public.confirm_sales_order(p_order_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
  v_lines int;
  v_snapshot jsonb;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;
  select * into v_doc from public.sales_documents where id = p_order_id for update;
  if v_doc.document_type <> ''SALES_ORDER'' then raise exception ''not a sales order''; end if;
  perform public.sales_assert_role(v_doc.organization_id, array[''owner'',''admin'',''manager'']::public.member_role[]);
  perform public.sales_assert_feature(v_doc.organization_id);
  if v_doc.status <> ''DRAFT'' then raise exception ''only draft orders can be confirmed''; end if;
  perform public.validate_sales_customer(v_doc.organization_id, v_doc.counterparty_id);
  select count(*) into v_lines from public.sales_document_lines where sales_document_id = v_doc.id;
  if v_lines < 1 then raise exception ''order must have at least one line''; end if;
  perform public.refresh_sales_document_totals(v_doc.id);
  if v_doc.source_document_id is null then
    v_snapshot := public.build_counterparty_snapshot(v_doc.organization_id, v_doc.counterparty_id);
  else
    v_snapshot := v_doc.counterparty_snapshot;
  end if;
  perform set_config(''sales.engine_write'', ''1'', true);
  update public.sales_documents
  set status = ''CONFIRMED'', confirmed_by = v_uid, confirmed_at = timezone(''utc'', now()),
      counterparty_snapshot = v_snapshot, is_commercially_frozen = true
  where id = v_doc.id returning * into v_doc;
  perform set_config(''sales.engine_write'', ''0'', true);
  perform public.sales_write_audit(
    v_doc.organization_id, v_uid, ''sales.order.confirmed'', v_doc.id, ''confirm'',
    jsonb_build_object(''internal_number'', v_doc.internal_number, ''total'', v_doc.total)
  );
  return v_doc;
end;
$$","create or replace function public.mark_order_ready_to_invoice(p_order_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
begin
  if v_uid is null then raise exception ''not authenticated''; end if;
  select * into v_doc from public.sales_documents where id = p_order_id for update;
  if v_doc.document_type <> ''SALES_ORDER'' then raise exception ''not a sales order''; end if;
  perform public.sales_assert_role(v_doc.organization_id, array[''owner'',''admin'',''manager'',''accountant'']::public.member_role[]);
  perform public.sales_assert_feature(v_doc.organization_id);
  if v_doc.status = ''READY_TO_INVOICE'' then return v_doc; end if;
  if v_doc.status <> ''CONFIRMED'' then raise exception ''only confirmed orders can be marked ready to invoice''; end if;
  perform set_config(''sales.engine_write'', ''1'', true);
  update public.sales_documents set status = ''READY_TO_INVOICE'' where id = p_order_id returning * into v_doc;
  perform set_config(''sales.engine_write'', ''0'', true);
  perform public.sales_write_audit(
    v_doc.organization_id, v_uid, ''sales.order.ready_to_invoice'', v_doc.id, ''ready'',
    jsonb_build_object(''internal_number'', v_doc.internal_number)
  );
  return v_doc;
end;
$$","grant execute on function public.send_quote(uuid) to authenticated","grant execute on function public.accept_quote(uuid) to authenticated","grant execute on function public.reject_quote(uuid, text) to authenticated","grant execute on function public.cancel_sales_document(uuid, text) to authenticated","grant execute on function public.convert_quote_to_order(uuid) to authenticated","grant execute on function public.confirm_sales_order(uuid) to authenticated","grant execute on function public.mark_order_ready_to_invoice(uuid) to authenticated","create or replace function public.bootstrap_organization_modules(
  p_organization_id uuid,
  p_enable_feature_codes text[] default ''{}''
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_code text;
  v_fid uuid;
  v_rel public.feature_release_controls%rowtype;
  v_codes text[];
begin
  if v_uid is null then raise exception ''NOT_AUTHENTICATED''; end if;
  if not public.has_org_role(
    p_organization_id,
    array[''owner'', ''admin'']::public.member_role[]
  ) then
    raise exception ''MODULES_CONFIGURE_DENIED'';
  end if;

  perform public.modules_lock_organization(p_organization_id);

  v_codes := array[''dashboard'', ''accounting''];
  foreach v_code in array coalesce(p_enable_feature_codes, ''{}'') loop
    if v_code is null or v_code = any (v_codes) then continue; end if;
    v_codes := array_append(v_codes, v_code);
  end loop;

  foreach v_code in array v_codes loop
    select id into v_fid from public.feature_catalog where code = v_code and active;
    if v_fid is null then continue; end if;
    select * into v_rel from public.feature_release_controls where feature_id = v_fid;

    if v_code = ''medical_legal''
       or coalesce(v_rel.release_status, ''COMING_SOON'') in (
         ''COMING_SOON''::public.feature_release_status,
         ''RESTRICTED''::public.feature_release_status,
         ''BLOCKED''::public.feature_release_status,
         ''RETIRED''::public.feature_release_status
       )
    then
      continue;
    end if;

    insert into public.organization_feature_entitlements (
      organization_id, feature_id, status, source_type, metadata, granted_at, granted_by
    ) values (
      p_organization_id, v_fid, ''GRANTED'', ''SYSTEM'',
      jsonb_build_object(''bootstrap'', true), timezone(''utc'', now()), v_uid
    )
    on conflict (organization_id, feature_id) do update set
      status = ''GRANTED''::public.feature_entitlement_status,
      updated_at = timezone(''utc'', now());

    insert into public.organization_feature_preferences (
      organization_id, feature_id, desired_enabled, updated_by
    ) values (p_organization_id, v_fid, true, v_uid)
    on conflict (organization_id, feature_id) do update set
      desired_enabled = true,
      updated_by = excluded.updated_by,
      updated_at = timezone(''utc'', now());
  end loop;

  select id into v_fid from public.feature_catalog where code = ''medical_legal'';
  if v_fid is not null then
    insert into public.organization_feature_entitlements (
      organization_id, feature_id, status, source_type, metadata
    ) values (
      p_organization_id, v_fid, ''RESTRICTED'', ''SYSTEM'', jsonb_build_object(''bootstrap'', true)
    ) on conflict do nothing;
    insert into public.organization_feature_preferences (
      organization_id, feature_id, desired_enabled, updated_by
    ) values (p_organization_id, v_fid, false, v_uid)
    on conflict do nothing;
  end if;

  return public.recompute_organization_features(p_organization_id, v_uid, ''bootstrap'');
end;
$$","revoke all on function public.bootstrap_organization_modules(uuid, text[]) from public, anon","grant execute on function public.bootstrap_organization_modules(uuid, text[]) to authenticated","comment on function public.bootstrap_organization_modules(uuid, text[]) is
  ''SECURITY DEFINER intentional: new-org bootstrap. Explicit codes only; default_status is not authority.''"}', 'phase12_source_feature_guard_hardening'),
	('20261201200000', '{"-- Phase 12.11 — Security grants / revoke internal helpers / comments

revoke all on function public.modules_assert_service_role() from public, anon, authenticated","revoke all on function public.modules_lock_organization(uuid) from public, anon, authenticated","revoke all on function public.modules_write_audit(uuid, uuid, text, text, jsonb) from public, anon, authenticated","revoke all on function public.modules_entitlement_is_granted(uuid, uuid) from public, anon, authenticated","revoke all on function public.modules_entitlement_is_restricted(uuid, uuid) from public, anon, authenticated","revoke all on function public.modules_preference_desired(uuid, uuid) from public, anon, authenticated","revoke all on function public.modules_evaluate_feature_state(uuid, uuid) from public, anon, authenticated","revoke all on function public.recompute_organization_features(uuid, uuid, text) from public, anon, authenticated","revoke all on function public.modules_config_hash(uuid) from public, anon, authenticated","revoke all on function public.modules_disable_block_reason(uuid, text) from public, anon, authenticated","revoke all on function public.modules_assert_configure(uuid) from public, anon, authenticated","revoke all on function public.modules_assert_read(uuid) from public, anon, authenticated","revoke all on function public.sales_assert_feature(uuid) from public, anon, authenticated","-- Client intentional
grant execute on function public.get_module_configuration_state(uuid) to authenticated","grant execute on function public.why_feature_unavailable(uuid, text) to authenticated","grant execute on function public.set_organization_feature_preference(uuid, text, boolean, boolean) to authenticated","grant execute on function public.preview_module_pack(uuid, uuid) to authenticated","grant execute on function public.apply_module_pack(uuid, uuid, text, boolean) to authenticated","grant execute on function public.bootstrap_organization_modules(uuid, text[]) to authenticated","-- Platform only
revoke all on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text)
  from public, anon, authenticated","grant execute on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text)
  to service_role","revoke all on function public.platform_grant_feature_entitlement(uuid, text, public.feature_entitlement_source, jsonb)
  from public, anon, authenticated","grant execute on function public.platform_grant_feature_entitlement(uuid, text, public.feature_entitlement_source, jsonb)
  to service_role","revoke all on function public.platform_revoke_feature_entitlement(uuid, text)
  from public, anon, authenticated","grant execute on function public.platform_revoke_feature_entitlement(uuid, text)
  to service_role","revoke all on function public.recompute_feature_for_all_organizations(uuid, uuid, text)
  from public, anon, authenticated","grant execute on function public.recompute_feature_for_all_organizations(uuid, uuid, text)
  to service_role","-- Reaffirm table ACL
revoke insert, update, delete on table public.organization_features from authenticated","revoke insert, update, delete on table public.organization_feature_entitlements from authenticated","revoke insert, update, delete on table public.organization_feature_preferences from authenticated","revoke insert, update, delete on table public.feature_release_controls from authenticated","revoke insert, update, delete on table public.feature_dependencies from authenticated","revoke insert, update, delete on table public.module_packs from authenticated","revoke insert, update, delete on table public.module_pack_features from authenticated","revoke insert, update, delete on table public.organization_pack_applications from authenticated","comment on function public.get_module_configuration_state(uuid) is
  ''SECURITY DEFINER intentional client RPC — module configurator read model.''","comment on function public.set_organization_feature_preference(uuid, text, boolean, boolean) is
  ''SECURITY DEFINER intentional client RPC — atomic preference + recompute.''","comment on function public.preview_module_pack(uuid, uuid) is
  ''SECURITY DEFINER intentional client RPC — pack preview read-only.''","comment on function public.apply_module_pack(uuid, uuid, text, boolean) is
  ''SECURITY DEFINER intentional client RPC — ADD/ENABLE only; never grants entitlement.''","comment on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text) is
  ''PLATFORM GOVERNANCE service_role only — updates release and recomputes all orgs.''"}', 'phase12_security'),
	('20261201210000', '{"-- Phase 12.12 — Advisor hardening (RLS reaffirm; ACL)

drop policy if exists organization_feature_entitlements_select on public.organization_feature_entitlements","create policy organization_feature_entitlements_select
  on public.organization_feature_entitlements for select to authenticated
  using (public.is_org_member(organization_id))","drop policy if exists organization_feature_preferences_select on public.organization_feature_preferences","create policy organization_feature_preferences_select
  on public.organization_feature_preferences for select to authenticated
  using (public.is_org_member(organization_id))","drop policy if exists organization_pack_applications_select on public.organization_pack_applications","create policy organization_pack_applications_select
  on public.organization_pack_applications for select to authenticated
  using (
    public.has_org_role(
      organization_id,
      array[''owner'', ''admin'', ''manager'']::public.member_role[]
    )
  )","revoke insert, update, delete on table public.feature_catalog from authenticated","grant select on table public.feature_catalog to authenticated"}', 'phase12_advisor_hardening'),
	('20261201220000', '{"-- Phase 12.13 — Revoke anon EXECUTE on intentional client SECURITY DEFINER RPCs

revoke all on function public.get_module_configuration_state(uuid) from public, anon","grant execute on function public.get_module_configuration_state(uuid) to authenticated","revoke all on function public.why_feature_unavailable(uuid, text) from public, anon","grant execute on function public.why_feature_unavailable(uuid, text) to authenticated","revoke all on function public.set_organization_feature_preference(uuid, text, boolean, boolean) from public, anon","grant execute on function public.set_organization_feature_preference(uuid, text, boolean, boolean) to authenticated","revoke all on function public.preview_module_pack(uuid, uuid) from public, anon","grant execute on function public.preview_module_pack(uuid, uuid) to authenticated","revoke all on function public.apply_module_pack(uuid, uuid, text, boolean) from public, anon","grant execute on function public.apply_module_pack(uuid, uuid, text, boolean) to authenticated","revoke all on function public.bootstrap_organization_modules(uuid, text[]) from public, anon","grant execute on function public.bootstrap_organization_modules(uuid, text[]) to authenticated"}', 'phase12_revoke_anon_execute'),
	('20261201230000', '{"-- Phase 12.14 — service_role OF bypass + platform_enable helper for tests/ops

create or replace function public.organization_features_engine_write_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''''
as $$
begin
  if auth.role() = ''service_role'' then
    return case when tg_op = ''DELETE'' then old else new end;
  end if;
  if current_setting(''modules.engine_write'', true) is distinct from ''1'' then
    raise exception ''organization_features is engine-managed; use set_organization_feature_preference'';
  end if;
  return case when tg_op = ''DELETE'' then old else new end;
end;
$$","create or replace function public.platform_enable_organization_feature(
  p_organization_id uuid,
  p_feature_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_fid uuid;
  v_dep_code text;
begin
  perform public.modules_assert_service_role();
  select id into v_fid from public.feature_catalog where code = p_feature_code and active;
  if v_fid is null then raise exception ''FEATURE_NOT_FOUND''; end if;

  -- Cascade HARD dependencies first so recompute can succeed.
  for v_dep_code in
    select rc.code
    from public.feature_dependencies d
    join public.feature_catalog rc on rc.id = d.required_feature_id
    where d.feature_id = v_fid
      and d.active
      and d.dependency_kind = ''HARD''::public.feature_dependency_kind
  loop
    perform public.platform_enable_organization_feature(p_organization_id, v_dep_code);
  end loop;

  insert into public.organization_feature_entitlements (
    organization_id, feature_id, status, source_type, metadata, granted_at
  ) values (
    p_organization_id, v_fid, ''GRANTED'', ''SYSTEM'',
    jsonb_build_object(''platform_enable'', true), timezone(''utc'', now())
  )
  on conflict (organization_id, feature_id) do update set
    status = ''GRANTED''::public.feature_entitlement_status,
    revoked_at = null,
    updated_at = timezone(''utc'', now());

  insert into public.organization_feature_preferences (
    organization_id, feature_id, desired_enabled
  ) values (p_organization_id, v_fid, true)
  on conflict (organization_id, feature_id) do update set
    desired_enabled = true,
    updated_at = timezone(''utc'', now());

  return public.recompute_organization_features(p_organization_id, null, ''platform_enable'');
end;
$$","revoke all on function public.platform_enable_organization_feature(uuid, text)
  from public, anon, authenticated","grant execute on function public.platform_enable_organization_feature(uuid, text)
  to service_role","create or replace function public.platform_disable_organization_feature(
  p_organization_id uuid,
  p_feature_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_fid uuid;
begin
  perform public.modules_assert_service_role();
  select id into v_fid from public.feature_catalog where code = p_feature_code and active;
  if v_fid is null then raise exception ''FEATURE_NOT_FOUND''; end if;

  insert into public.organization_feature_preferences (
    organization_id, feature_id, desired_enabled
  ) values (p_organization_id, v_fid, false)
  on conflict (organization_id, feature_id) do update set
    desired_enabled = false,
    updated_at = timezone(''utc'', now());

  return public.recompute_organization_features(p_organization_id, null, ''platform_disable'');
end;
$$","revoke all on function public.platform_disable_organization_feature(uuid, text)
  from public, anon, authenticated","grant execute on function public.platform_disable_organization_feature(uuid, text)
  to service_role","comment on function public.platform_enable_organization_feature(uuid, text) is
  ''PLATFORM/service_role only: grant + preference + recompute. Used by staging gates/e2e.''","comment on function public.platform_disable_organization_feature(uuid, text) is
  ''PLATFORM/service_role only: preference off + recompute (entitlement retained).''"}', 'phase12_platform_enable_helper'),
	('20261201240000', '{"-- Phase 12.15 — Final entitlement / ACL security hardening
-- STAGING ONLY (rpcpdrzbcclofvjpgldb)
-- P0: bootstrap must not allow tenant self-grant of entitlements
-- P1: authenticated table ACL = SELECT only (no TRUNCATE/TRIGGER/REFERENCES)

-- ---------------------------------------------------------------------------
-- P0: Drop tenant-callable bootstrap that accepted optional feature codes
-- ---------------------------------------------------------------------------
drop function if exists public.bootstrap_organization_modules(uuid, text[])","create or replace function public.platform_bootstrap_organization_modules(
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  v_code text;
  v_fid uuid;
  v_codes text[] := array[''dashboard'', ''accounting''];
begin
  perform public.modules_assert_service_role();

  if not exists (select 1 from public.organizations o where o.id = p_organization_id) then
    raise exception ''ORGANIZATION_NOT_FOUND'';
  end if;

  perform public.modules_lock_organization(p_organization_id);

  foreach v_code in array v_codes loop
    select id into v_fid from public.feature_catalog where code = v_code and active;
    if v_fid is null then
      raise exception ''FEATURE_NOT_FOUND:%'', v_code;
    end if;

    insert into public.organization_feature_entitlements (
      organization_id, feature_id, status, source_type, metadata, granted_at
    ) values (
      p_organization_id, v_fid, ''GRANTED'', ''SYSTEM'',
      jsonb_build_object(
        ''bootstrap'', true,
        ''mandatory_core'', true,
        ''platform_bootstrap'', true
      ),
      timezone(''utc'', now())
    )
    on conflict (organization_id, feature_id) do update set
      status = ''GRANTED''::public.feature_entitlement_status,
      source_type = ''SYSTEM''::public.feature_entitlement_source,
      revoked_at = null,
      metadata = coalesce(public.organization_feature_entitlements.metadata, ''{}''::jsonb)
        || jsonb_build_object(''platform_bootstrap'', true, ''mandatory_core'', true),
      updated_at = timezone(''utc'', now());

    insert into public.organization_feature_preferences (
      organization_id, feature_id, desired_enabled
    ) values (p_organization_id, v_fid, true)
    on conflict (organization_id, feature_id) do update set
      desired_enabled = true,
      updated_at = timezone(''utc'', now());
  end loop;

  -- medical_legal: explicit RESTRICTED entitlement marker (never GRANTED here)
  select id into v_fid from public.feature_catalog where code = ''medical_legal'' and active;
  if v_fid is not null then
    insert into public.organization_feature_entitlements (
      organization_id, feature_id, status, source_type, metadata
    ) values (
      p_organization_id, v_fid, ''RESTRICTED'', ''SYSTEM'',
      jsonb_build_object(''bootstrap'', true, ''platform_bootstrap'', true)
    )
    on conflict (organization_id, feature_id) do nothing;

    insert into public.organization_feature_preferences (
      organization_id, feature_id, desired_enabled
    ) values (p_organization_id, v_fid, false)
    on conflict (organization_id, feature_id) do nothing;
  end if;

  return public.recompute_organization_features(
    p_organization_id,
    null,
    ''platform_bootstrap''
  );
end;
$$","revoke all on function public.platform_bootstrap_organization_modules(uuid)
  from public, anon, authenticated","grant execute on function public.platform_bootstrap_organization_modules(uuid)
  to service_role","comment on function public.platform_bootstrap_organization_modules(uuid) is
  ''PLATFORM/service_role only. Provisions mandatory core (dashboard+accounting) entitlements+preferences. Never accepts tenant optional feature lists. Optional modules require prior GRANTED entitlement + set_organization_feature_preference.''","-- Compatibility stub: if anything still calls the old name with optional codes, deny hard.
create or replace function public.bootstrap_organization_modules(
  p_organization_id uuid,
  p_enable_feature_codes text[] default ''{}''
)
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
begin
  raise exception ''BOOTSTRAP_PLATFORM_ONLY: use platform_bootstrap_organization_modules via service_role; optional codes are preference-only'';
end;
$$","revoke all on function public.bootstrap_organization_modules(uuid, text[])
  from public, anon, authenticated","-- Intentionally NO grant to authenticated/anon. service_role may execute only to receive the deny message in tests.
grant execute on function public.bootstrap_organization_modules(uuid, text[])
  to service_role","comment on function public.bootstrap_organization_modules(uuid, text[]) is
  ''REMOVED tenant capability. Always raises BOOTSTRAP_PLATFORM_ONLY. Optional module selection must use set_organization_feature_preference after platform entitlement grant.''","-- ---------------------------------------------------------------------------
-- P1: Authenticated ACL = SELECT only on Phase 12 governance / projection tables
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
  tables text[] := array[
    ''feature_catalog'',
    ''feature_release_controls'',
    ''feature_dependencies'',
    ''module_packs'',
    ''module_pack_features'',
    ''organization_feature_entitlements'',
    ''organization_feature_preferences'',
    ''organization_features'',
    ''organization_pack_applications''
  ];
begin
  foreach t in array tables loop
    execute format(''revoke all on table public.%I from public, anon, authenticated'', t);
    execute format(''grant select on table public.%I to authenticated'', t);
    execute format(''grant all on table public.%I to service_role'', t);
  end loop;
end $$","-- Snapshot / migration audit tables stay service_role only (no authenticated)
do $$
begin
  if to_regclass(''public.phase12_migration_effective_snapshot'') is not null then
    revoke all on table public.phase12_migration_effective_snapshot from public, anon, authenticated;
    grant all on table public.phase12_migration_effective_snapshot to service_role;
  end if;
  if to_regclass(''public.phase12_migration_effective_diff'') is not null then
    revoke all on table public.phase12_migration_effective_diff from public, anon, authenticated;
    grant all on table public.phase12_migration_effective_diff to service_role;
  end if;
end $$","-- Reaffirm platform RPCs are not tenant-executable
revoke all on function public.platform_enable_organization_feature(uuid, text)
  from public, anon, authenticated","grant execute on function public.platform_enable_organization_feature(uuid, text) to service_role","revoke all on function public.platform_disable_organization_feature(uuid, text)
  from public, anon, authenticated","grant execute on function public.platform_disable_organization_feature(uuid, text) to service_role","revoke all on function public.platform_grant_feature_entitlement(uuid, text, public.feature_entitlement_source, jsonb)
  from public, anon, authenticated","grant execute on function public.platform_grant_feature_entitlement(uuid, text, public.feature_entitlement_source, jsonb)
  to service_role","revoke all on function public.platform_revoke_feature_entitlement(uuid, text)
  from public, anon, authenticated","grant execute on function public.platform_revoke_feature_entitlement(uuid, text) to service_role","revoke all on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text)
  from public, anon, authenticated","grant execute on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text)
  to service_role","revoke all on function public.recompute_organization_features(uuid, uuid, text)
  from public, anon, authenticated","grant execute on function public.recompute_organization_features(uuid, uuid, text) to service_role","revoke all on function public.recompute_feature_for_all_organizations(uuid, uuid, text)
  from public, anon, authenticated","grant execute on function public.recompute_feature_for_all_organizations(uuid, uuid, text) to service_role","-- Intentional client RPCs remain authenticated (no anon)
revoke all on function public.get_module_configuration_state(uuid) from public, anon","grant execute on function public.get_module_configuration_state(uuid) to authenticated","revoke all on function public.why_feature_unavailable(uuid, text) from public, anon","grant execute on function public.why_feature_unavailable(uuid, text) to authenticated","revoke all on function public.set_organization_feature_preference(uuid, text, boolean, boolean)
  from public, anon","grant execute on function public.set_organization_feature_preference(uuid, text, boolean, boolean)
  to authenticated","revoke all on function public.preview_module_pack(uuid, uuid) from public, anon","grant execute on function public.preview_module_pack(uuid, uuid) to authenticated","revoke all on function public.apply_module_pack(uuid, uuid, text, boolean) from public, anon","grant execute on function public.apply_module_pack(uuid, uuid, text, boolean) to authenticated","-- Privilege probe for gates (service_role only)
create or replace function public.phase12_assert_authenticated_table_acl()
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  t text;
  tables text[] := array[
    ''feature_catalog'',
    ''feature_release_controls'',
    ''feature_dependencies'',
    ''module_packs'',
    ''module_pack_features'',
    ''organization_feature_entitlements'',
    ''organization_feature_preferences'',
    ''organization_features'',
    ''organization_pack_applications''
  ];
  v_trunc int := 0;
  v_trig int := 0;
  v_refs int := 0;
  v_mut int := 0;
  v_missing_select int := 0;
  v_details jsonb := ''[]''::jsonb;
  v_row jsonb;
begin
  perform public.modules_assert_service_role();

  foreach t in array tables loop
    v_row := jsonb_build_object(
      ''table'', t,
      ''select'', has_table_privilege(''authenticated'', format(''%I.%I'', ''public'', t)::regclass, ''SELECT''),
      ''insert'', has_table_privilege(''authenticated'', format(''%I.%I'', ''public'', t)::regclass, ''INSERT''),
      ''update'', has_table_privilege(''authenticated'', format(''%I.%I'', ''public'', t)::regclass, ''UPDATE''),
      ''delete'', has_table_privilege(''authenticated'', format(''%I.%I'', ''public'', t)::regclass, ''DELETE''),
      ''truncate'', has_table_privilege(''authenticated'', format(''%I.%I'', ''public'', t)::regclass, ''TRUNCATE''),
      ''trigger'', has_table_privilege(''authenticated'', format(''%I.%I'', ''public'', t)::regclass, ''TRIGGER''),
      ''references'', has_table_privilege(''authenticated'', format(''%I.%I'', ''public'', t)::regclass, ''REFERENCES'')
    );
    v_details := v_details || jsonb_build_array(v_row);

    if not (v_row->>''select'')::boolean then
      v_missing_select := v_missing_select + 1;
    end if;
    if (v_row->>''insert'')::boolean
       or (v_row->>''update'')::boolean
       or (v_row->>''delete'')::boolean then
      v_mut := v_mut + 1;
    end if;
    if (v_row->>''truncate'')::boolean then
      v_trunc := v_trunc + 1;
    end if;
    if (v_row->>''trigger'')::boolean then
      v_trig := v_trig + 1;
    end if;
    if (v_row->>''references'')::boolean then
      v_refs := v_refs + 1;
    end if;
  end loop;

  return jsonb_build_object(
    ''ok'', v_missing_select = 0 and v_mut = 0 and v_trunc = 0 and v_trig = 0 and v_refs = 0,
    ''missing_select_count'', v_missing_select,
    ''mutation_count'', v_mut,
    ''truncate_count'', v_trunc,
    ''trigger_count'', v_trig,
    ''references_count'', v_refs,
    ''tables'', v_details
  );
end;
$$","revoke all on function public.phase12_assert_authenticated_table_acl()
  from public, anon, authenticated","grant execute on function public.phase12_assert_authenticated_table_acl() to service_role"}', 'phase12_final_entitlement_acl_hardening'),
	('20261201241000', '{"-- Phase 12.16 — Authenticated function EXECUTE ACL probe (service_role only)

create or replace function public.phase12_assert_authenticated_function_acl()
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  fn text;
  sig text;
  leaks int := 0;
  details jsonb := ''[]''::jsonb;
  has_exec boolean;
  funcs text[] := array[
    ''platform_bootstrap_organization_modules(uuid)'',
    ''bootstrap_organization_modules(uuid,text[])'',
    ''platform_enable_organization_feature(uuid,text)'',
    ''platform_disable_organization_feature(uuid,text)'',
    ''platform_grant_feature_entitlement(uuid,text,feature_entitlement_source,jsonb)'',
    ''platform_revoke_feature_entitlement(uuid,text)'',
    ''platform_set_feature_release(text,feature_release_status,boolean,text)'',
    ''recompute_organization_features(uuid,uuid,text)'',
    ''recompute_feature_for_all_organizations(uuid,uuid,text)'',
    ''phase12_assert_authenticated_table_acl()'',
    ''modules_assert_service_role()'',
    ''modules_evaluate_feature_state(uuid,uuid)'',
    ''sales_assert_feature(uuid)''
  ];
begin
  perform public.modules_assert_service_role();

  foreach sig in array funcs loop
    begin
      has_exec := has_function_privilege(
        ''authenticated'',
        (''public.'' || sig)::regprocedure,
        ''EXECUTE''
      );
    exception when undefined_function then
      has_exec := false;
    end;
    if has_exec then
      leaks := leaks + 1;
    end if;
    details := details || jsonb_build_array(
      jsonb_build_object(''function'', sig, ''authenticated_execute'', has_exec)
    );
  end loop;

  return jsonb_build_object(
    ''ok'', leaks = 0,
    ''leak_count'', leaks,
    ''functions'', details
  );
end;
$$","revoke all on function public.phase12_assert_authenticated_function_acl()
  from public, anon, authenticated","grant execute on function public.phase12_assert_authenticated_function_acl()
  to service_role"}', 'phase12_function_acl_probe'),
	('20261201242000', '{"-- Phase 12.17 — Fix function ACL probe schema-qualified enums

create or replace function public.phase12_assert_authenticated_function_acl()
returns jsonb
language plpgsql
security definer
set search_path = ''''
as $$
declare
  sig text;
  leaks int := 0;
  details jsonb := ''[]''::jsonb;
  has_exec boolean;
  funcs text[] := array[
    ''platform_bootstrap_organization_modules(uuid)'',
    ''bootstrap_organization_modules(uuid,text[])'',
    ''platform_enable_organization_feature(uuid,text)'',
    ''platform_disable_organization_feature(uuid,text)'',
    ''platform_grant_feature_entitlement(uuid,text,public.feature_entitlement_source,jsonb)'',
    ''platform_revoke_feature_entitlement(uuid,text)'',
    ''platform_set_feature_release(text,public.feature_release_status,boolean,text)'',
    ''recompute_organization_features(uuid,uuid,text)'',
    ''recompute_feature_for_all_organizations(uuid,uuid,text)'',
    ''phase12_assert_authenticated_table_acl()'',
    ''modules_assert_service_role()'',
    ''modules_evaluate_feature_state(uuid,uuid)'',
    ''sales_assert_feature(uuid)''
  ];
begin
  perform public.modules_assert_service_role();

  foreach sig in array funcs loop
    begin
      has_exec := has_function_privilege(
        ''authenticated'',
        (''public.'' || sig)::regprocedure,
        ''EXECUTE''
      );
    exception when undefined_function then
      has_exec := false;
    end;
    if has_exec then
      leaks := leaks + 1;
    end if;
    details := details || jsonb_build_array(
      jsonb_build_object(''function'', sig, ''authenticated_execute'', has_exec)
    );
  end loop;

  return jsonb_build_object(
    ''ok'', leaks = 0,
    ''leak_count'', leaks,
    ''functions'', details
  );
end;
$$","revoke all on function public.phase12_assert_authenticated_function_acl()
  from public, anon, authenticated","grant execute on function public.phase12_assert_authenticated_function_acl()
  to service_role"}', 'phase12_function_acl_probe_fix'),
	('20261301100000', '{"-- Phase 13.1 — Anon table ACL hardening (least privilege)
-- STAGING ONLY application via linked push after review.
-- Revokes residual anon privileges on public tables.
-- Does NOT weaken authenticated tenant access; RLS remains authoritative.

do $$
declare
  r record;
begin
  for r in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = ''public''
      and c.relkind = ''r''
  loop
    execute format(''revoke all on table public.%I from anon'', r.relname);
  end loop;
end $$","-- Also revoke anon DEFAULT privileges if any (best-effort; may no-op)
alter default privileges in schema public revoke all on tables from anon","comment on schema public is
  ''Phase13: anon has no table privileges on public relations; API access via authenticated + RLS or SECURITY DEFINER RPCs.''"}', 'phase13_anon_table_acl_hardening');


--
-- PostgreSQL database dump complete
--

-- \unrestrict FnbKyiUf9sc9f5QvemEtdw8cOr8jB3bMhNxpmVmHoPJhbyT63pRsN7a9VOCXLyo

RESET ALL;
