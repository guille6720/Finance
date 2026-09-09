-- Phase 1 foundation schema
-- Neutral technical names only. No brand-specific identifiers.
-- Staging and Production MUST use separate Supabase projects.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.organization_status as enum (
  'draft',
  'active',
  'suspended',
  'closed'
);

create type public.member_role as enum (
  'owner',
  'admin',
  'manager',
  'operator',
  'accountant',
  'viewer'
);

create type public.member_status as enum (
  'invited',
  'active',
  'disabled'
);

create type public.feature_status as enum (
  'enabled',
  'disabled',
  'restricted'
);

create type public.business_type as enum (
  'kiosk',
  'retail',
  'professional',
  'services',
  'accounting_firm',
  'healthcare',
  'medical_legal',
  'industry',
  'other'
);

create type public.ux_mode as enum (
  'business',
  'accountant'
);

-- ---------------------------------------------------------------------------
-- Helper: updated_at trigger
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  full_name text not null default '',
  avatar_url text,
  preferred_ux_mode public.ux_mode not null default 'business',
  locale text not null default 'es-AR',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- organizations
-- ---------------------------------------------------------------------------

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null,
  commercial_name text,
  cuit text,
  country text not null default 'AR',
  province text,
  city text,
  timezone text not null default 'America/Argentina/Buenos_Aires',
  base_currency text not null default 'ARS',
  status public.organization_status not null default 'draft',
  onboarding_completed_at timestamptz,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint organizations_cuit_format check (
    cuit is null or cuit ~ '^\d{11}$'
  )
);

create index organizations_status_idx on public.organizations (status);
create index organizations_cuit_idx on public.organizations (cuit);

create trigger organizations_set_updated_at
before update on public.organizations
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- organization_members
-- ---------------------------------------------------------------------------

create table public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role public.member_role not null default 'viewer',
  status public.member_status not null default 'active',
  invited_by uuid references public.profiles (id),
  invited_at timestamptz,
  joined_at timestamptz default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, user_id)
);

create index organization_members_user_idx on public.organization_members (user_id);
create index organization_members_org_idx on public.organization_members (organization_id);

create trigger organization_members_set_updated_at
before update on public.organization_members
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
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
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index branches_org_idx on public.branches (organization_id);

create trigger branches_set_updated_at
before update on public.branches
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
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
  created_at timestamptz not null default timezone('utc', now())
);

-- ---------------------------------------------------------------------------
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
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger fiscal_profiles_set_updated_at
before update on public.fiscal_profiles
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- business_profiles (onboarding answers)
-- ---------------------------------------------------------------------------

create table public.business_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null unique references public.organizations (id) on delete cascade,
  business_type public.business_type not null default 'other',
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
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger business_profiles_set_updated_at
before update on public.business_profiles
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
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
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint accounting_periods_range check (ends_on >= starts_on)
);

create index accounting_periods_org_idx on public.accounting_periods (organization_id);

create trigger accounting_periods_set_updated_at
before update on public.accounting_periods
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- cost_centers (structure only)
-- ---------------------------------------------------------------------------

create table public.cost_centers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  code text not null,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code)
);

create index cost_centers_org_idx on public.cost_centers (organization_id);

create trigger cost_centers_set_updated_at
before update on public.cost_centers
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- feature_catalog / organization_features
-- ---------------------------------------------------------------------------

create table public.feature_catalog (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  category text not null default 'general',
  default_status public.feature_status not null default 'disabled',
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.organization_features (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  status public.feature_status not null default 'disabled',
  enabled_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, feature_id)
);

create index organization_features_org_idx on public.organization_features (organization_id);

create trigger organization_features_set_updated_at
before update on public.organization_features
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- app_settings / organization_settings
-- ---------------------------------------------------------------------------

create table public.app_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  description text,
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.organization_settings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  key text not null,
  value jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, key)
);

create trigger organization_settings_set_updated_at
before update on public.organization_settings
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
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
  metadata jsonb not null default '{}'::jsonb,
  ip_address text,
  user_agent text,
  created_at timestamptz not null default timezone('utc', now())
);

create index audit_events_org_created_idx on public.audit_events (organization_id, created_at desc);
create index audit_events_entity_idx on public.audit_events (entity_type, entity_id);
create index audit_events_type_idx on public.audit_events (event_type);

create or replace function public.prevent_audit_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'audit_events is append-only';
end;
$$;

create trigger audit_events_no_update
before update on public.audit_events
for each row execute function public.prevent_audit_mutation();

create trigger audit_events_no_delete
before delete on public.audit_events
for each row execute function public.prevent_audit_mutation();

-- ---------------------------------------------------------------------------
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
      and m.status = 'active'
  );
$$;

create or replace function public.has_org_role(p_org_id uuid, p_roles public.member_role[])
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
      and m.status = 'active'
      and m.role = any (p_roles)
  );
$$;

create or replace function public.can_mutate_org(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_org_role(
    p_org_id,
    array['owner', 'admin', 'manager']::public.member_role[]
  );
$$;

revoke all on function public.is_org_member(uuid) from public;
revoke all on function public.has_org_role(uuid, public.member_role[]) from public;
revoke all on function public.can_mutate_org(uuid) from public;
grant execute on function public.is_org_member(uuid) to authenticated;
grant execute on function public.has_org_role(uuid, public.member_role[]) to authenticated;
grant execute on function public.can_mutate_org(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.branches enable row level security;
alter table public.fiscal_conditions enable row level security;
alter table public.fiscal_profiles enable row level security;
alter table public.business_profiles enable row level security;
alter table public.accounting_periods enable row level security;
alter table public.cost_centers enable row level security;
alter table public.feature_catalog enable row level security;
alter table public.organization_features enable row level security;
alter table public.app_settings enable row level security;
alter table public.organization_settings enable row level security;
alter table public.audit_events enable row level security;

-- profiles
create policy profiles_select_own
  on public.profiles for select
  to authenticated
  using (id = auth.uid());

create policy profiles_update_own
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy profiles_select_same_org
  on public.profiles for select
  to authenticated
  using (
    exists (
      select 1
      from public.organization_members me
      join public.organization_members other
        on other.organization_id = me.organization_id
      where me.user_id = auth.uid()
        and me.status = 'active'
        and other.user_id = profiles.id
        and other.status = 'active'
    )
  );

-- organizations
create policy organizations_select_member
  on public.organizations for select
  to authenticated
  using (public.is_org_member(id));

create policy organizations_insert_authenticated
  on public.organizations for insert
  to authenticated
  with check (auth.uid() is not null and created_by = auth.uid());

create policy organizations_update_admins
  on public.organizations for update
  to authenticated
  using (public.can_mutate_org(id))
  with check (public.can_mutate_org(id));

-- organization_members
create policy members_select_same_org
  on public.organization_members for select
  to authenticated
  using (public.is_org_member(organization_id));

create policy members_insert_owner_bootstrap_or_admin
  on public.organization_members for insert
  to authenticated
  with check (
    (
      user_id = auth.uid()
      and role = 'owner'
      and exists (
        select 1 from public.organizations o
        where o.id = organization_id
          and o.created_by = auth.uid()
      )
    )
    or public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  );

create policy members_update_admins
  on public.organization_members for update
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  );

-- Generic org-scoped tables
create policy branches_select on public.branches for select to authenticated
  using (public.is_org_member(organization_id));
create policy branches_insert on public.branches for insert to authenticated
  with check (public.can_mutate_org(organization_id));
create policy branches_update on public.branches for update to authenticated
  using (public.can_mutate_org(organization_id))
  with check (public.can_mutate_org(organization_id));

create policy fiscal_profiles_select on public.fiscal_profiles for select to authenticated
  using (public.is_org_member(organization_id));
create policy fiscal_profiles_insert on public.fiscal_profiles for insert to authenticated
  with check (public.can_mutate_org(organization_id));
create policy fiscal_profiles_update on public.fiscal_profiles for update to authenticated
  using (public.can_mutate_org(organization_id))
  with check (public.can_mutate_org(organization_id));

create policy business_profiles_select on public.business_profiles for select to authenticated
  using (public.is_org_member(organization_id));
create policy business_profiles_insert on public.business_profiles for insert to authenticated
  with check (public.can_mutate_org(organization_id));
create policy business_profiles_update on public.business_profiles for update to authenticated
  using (public.can_mutate_org(organization_id))
  with check (public.can_mutate_org(organization_id));

create policy accounting_periods_select on public.accounting_periods for select to authenticated
  using (public.is_org_member(organization_id));
create policy accounting_periods_mutate on public.accounting_periods for all to authenticated
  using (
    public.has_org_role(
      organization_id,
      array['owner', 'admin', 'accountant']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array['owner', 'admin', 'accountant']::public.member_role[]
    )
  );

create policy cost_centers_select on public.cost_centers for select to authenticated
  using (public.is_org_member(organization_id));
create policy cost_centers_mutate on public.cost_centers for all to authenticated
  using (public.can_mutate_org(organization_id))
  with check (public.can_mutate_org(organization_id));

create policy organization_features_select on public.organization_features for select to authenticated
  using (public.is_org_member(organization_id));
create policy organization_features_mutate on public.organization_features for all to authenticated
  using (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  );

create policy organization_settings_select on public.organization_settings for select to authenticated
  using (public.is_org_member(organization_id));
create policy organization_settings_mutate on public.organization_settings for all to authenticated
  using (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  );

-- Catalogs (read for authenticated)
create policy fiscal_conditions_select on public.fiscal_conditions for select to authenticated
  using (active = true);

create policy feature_catalog_select on public.feature_catalog for select to authenticated
  using (active = true);

-- app_settings: no client writes; authenticated read only of non-sensitive keys if needed later
create policy app_settings_select_authenticated on public.app_settings for select to authenticated
  using (true);

-- audit_events: members can read own org; inserts via authenticated member or service role
create policy audit_events_select on public.audit_events for select to authenticated
  using (
    organization_id is not null
    and public.is_org_member(organization_id)
  );

create policy audit_events_insert on public.audit_events for insert to authenticated
  with check (
    actor_user_id = auth.uid()
    and (
      organization_id is null
      or public.is_org_member(organization_id)
    )
  );

-- No update/delete policies for audit_events → blocked for clients

-- ---------------------------------------------------------------------------
-- Seed catalogs
-- ---------------------------------------------------------------------------

insert into public.fiscal_conditions (code, name_business, name_accountant, description, sort_order) values
  ('monotributo', 'Monotributo', 'Monotributista', 'Régimen simplificado', 1),
  ('responsable_inscripto', 'Responsable inscripto', 'Responsable Inscripto', 'IVA responsable inscripto', 2),
  ('exento', 'Exento de IVA', 'Exento', 'Exento en IVA', 3),
  ('consumidor_final', 'Consumidor final', 'Consumidor Final', 'Sin actividad gravada formal', 4);

insert into public.feature_catalog (code, name, description, category, default_status, sort_order) values
  ('dashboard', 'Panel', 'Panel principal de la empresa', 'core', 'enabled', 10),
  ('sales', 'Ventas', 'Registro de ventas y cobros', 'gestion', 'disabled', 20),
  ('purchases', 'Compras', 'Compras y gastos', 'gestion', 'disabled', 30),
  ('customers', 'Clientes', 'Agenda de clientes', 'gestion', 'disabled', 40),
  ('suppliers', 'Proveedores', 'Agenda de proveedores', 'gestion', 'disabled', 50),
  ('cash', 'Caja', 'Caja diaria', 'finanzas', 'disabled', 60),
  ('banks', 'Bancos', 'Cuentas bancarias', 'finanzas', 'disabled', 70),
  ('inventory', 'Inventario', 'Stock de productos', 'operaciones', 'disabled', 80),
  ('pos', 'Punto de venta', 'POS / mostrador', 'operaciones', 'disabled', 90),
  ('accounting', 'Contabilidad', 'Contabilidad avanzada', 'contabilidad', 'disabled', 100),
  ('taxes', 'Impuestos', 'Impuestos y liquidaciones', 'contabilidad', 'disabled', 110),
  ('payroll', 'Sueldos', 'Liquidación de sueldos', 'rrhh', 'disabled', 120),
  ('projects', 'Proyectos', 'Gestión por proyectos', 'operaciones', 'disabled', 130),
  ('assets', 'Bienes de uso', 'Activos fijos', 'contabilidad', 'disabled', 140),
  ('reports', 'Reportes', 'Reportes de gestión', 'reportes', 'disabled', 150),
  ('medical_legal', 'Médico-legal', 'Módulo médico-legal (dominio separado)', 'vertical', 'restricted', 160);

insert into public.app_settings (key, value, description) values
  ('platform.phase', '"1"'::jsonb, 'Current platform phase'),
  ('platform.accounting_core_enabled', 'false'::jsonb, 'Accounting posting engine not enabled in Phase 1');
