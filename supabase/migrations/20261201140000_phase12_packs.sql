-- Phase 12.5 — Module packs (presets; never entitlements)

do $$ begin
  create type public.module_pack_type as enum (
    'STARTER',
    'FUNCTIONAL',
    'VERTICAL'
  );
exception when duplicate_object then null;
end $$;
create table if not exists public.module_packs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  pack_type public.module_pack_type not null,
  active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint module_packs_code_norm check (code = upper(btrim(code)))
);
create trigger module_packs_set_updated_at
before update on public.module_packs
for each row execute function public.set_updated_at();
create table if not exists public.module_pack_features (
  id uuid primary key default gen_random_uuid(),
  pack_id uuid not null references public.module_packs (id) on delete cascade,
  feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  recommended_enabled boolean not null default true,
  required_in_pack boolean not null default false,
  sort_order int not null default 0,
  constraint module_pack_features_pack_feature_uidx unique (pack_id, feature_id)
);
create index if not exists module_pack_features_feature_idx
  on public.module_pack_features (feature_id);
create table if not exists public.organization_pack_applications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  pack_id uuid not null references public.module_packs (id) on delete restrict,
  applied_by uuid references auth.users (id),
  applied_at timestamptz not null default timezone('utc', now()),
  configuration_before_hash text not null,
  configuration_after_hash text not null,
  result_snapshot jsonb not null default '{}'::jsonb
);
create index if not exists organization_pack_applications_org_applied_idx
  on public.organization_pack_applications (organization_id, applied_at desc);
create index if not exists organization_pack_applications_pack_idx
  on public.organization_pack_applications (pack_id);
create index if not exists organization_pack_applications_applied_by_idx
  on public.organization_pack_applications (applied_by)
  where applied_by is not null;
alter table public.module_packs enable row level security;
alter table public.module_pack_features enable row level security;
alter table public.organization_pack_applications enable row level security;
drop policy if exists module_packs_select on public.module_packs;
create policy module_packs_select
  on public.module_packs for select to authenticated
  using (active = true);
drop policy if exists module_pack_features_select on public.module_pack_features;
create policy module_pack_features_select
  on public.module_pack_features for select to authenticated
  using (
    exists (
      select 1 from public.module_packs p
      where p.id = pack_id and p.active
    )
  );
drop policy if exists organization_pack_applications_select on public.organization_pack_applications;
create policy organization_pack_applications_select
  on public.organization_pack_applications for select to authenticated
  using (
    public.has_org_role(
      organization_id,
      array['owner', 'admin', 'manager']::public.member_role[]
    )
  );
revoke all on table public.module_packs from public, anon;
revoke all on table public.module_pack_features from public, anon;
revoke all on table public.organization_pack_applications from public, anon;
grant select on table public.module_packs to authenticated;
grant select on table public.module_pack_features to authenticated;
grant select on table public.organization_pack_applications to authenticated;
revoke insert, update, delete on table public.module_packs from authenticated;
revoke insert, update, delete on table public.module_pack_features from authenticated;
revoke insert, update, delete on table public.organization_pack_applications from authenticated;
grant all on table public.module_packs to service_role;
grant all on table public.module_pack_features to service_role;
grant all on table public.organization_pack_applications to service_role;
-- Seed packs
insert into public.module_packs (code, name, description, pack_type, sort_order) values
  ('STARTER_COMERCIO', 'Comercio inicial', 'Clientes, ventas, caja y reportes', 'STARTER', 10),
  ('GESTION_COMPRAS', 'Gestión de compras', 'Proveedores y compras', 'FUNCTIONAL', 20),
  ('OPERACION_STOCK', 'Operación de stock', 'Inventario', 'FUNCTIONAL', 30),
  ('MOSTRADOR_POS', 'Mostrador / POS', 'Punto de venta con ventas y caja', 'FUNCTIONAL', 40),
  ('FINANZAS_TESORERIA', 'Tesorería', 'Caja y bancos', 'FUNCTIONAL', 50),
  ('REPORTES_GERENCIALES', 'Reportes gerenciales', 'Reportes', 'FUNCTIONAL', 60),
  ('COMERCIO', 'Vertical comercio', 'Combinación comercio + stock + compras', 'VERTICAL', 70),
  ('SERVICIOS', 'Vertical servicios', 'Clientes, ventas, caja, reportes', 'VERTICAL', 80),
  ('GESTION_INTEGRAL', 'Gestión integral', 'Comercio + tesorería + reportes', 'VERTICAL', 90)
on conflict (code) do nothing;
create or replace function public._phase12_seed_pack_feature(p_pack text, p_feature text, p_sort int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.module_pack_features (pack_id, feature_id, recommended_enabled, required_in_pack, sort_order)
  select p.id, c.id, true, false, p_sort
  from public.module_packs p
  join public.feature_catalog c on c.code = p_feature
  where p.code = p_pack
  on conflict do nothing;
end;
$$;
revoke all on function public._phase12_seed_pack_feature(text, text, int) from public, anon, authenticated;
select public._phase12_seed_pack_feature('STARTER_COMERCIO', 'customers', 10);
select public._phase12_seed_pack_feature('STARTER_COMERCIO', 'sales', 20);
select public._phase12_seed_pack_feature('STARTER_COMERCIO', 'cash', 30);
select public._phase12_seed_pack_feature('STARTER_COMERCIO', 'reports', 40);
select public._phase12_seed_pack_feature('GESTION_COMPRAS', 'suppliers', 10);
select public._phase12_seed_pack_feature('GESTION_COMPRAS', 'purchases', 20);
select public._phase12_seed_pack_feature('OPERACION_STOCK', 'inventory', 10);
select public._phase12_seed_pack_feature('MOSTRADOR_POS', 'sales', 10);
select public._phase12_seed_pack_feature('MOSTRADOR_POS', 'pos', 20);
select public._phase12_seed_pack_feature('MOSTRADOR_POS', 'cash', 30);
select public._phase12_seed_pack_feature('FINANZAS_TESORERIA', 'cash', 10);
select public._phase12_seed_pack_feature('FINANZAS_TESORERIA', 'banks', 20);
select public._phase12_seed_pack_feature('REPORTES_GERENCIALES', 'reports', 10);
select public._phase12_seed_pack_feature('COMERCIO', 'customers', 10);
select public._phase12_seed_pack_feature('COMERCIO', 'sales', 20);
select public._phase12_seed_pack_feature('COMERCIO', 'suppliers', 30);
select public._phase12_seed_pack_feature('COMERCIO', 'purchases', 40);
select public._phase12_seed_pack_feature('COMERCIO', 'inventory', 50);
select public._phase12_seed_pack_feature('COMERCIO', 'cash', 60);
select public._phase12_seed_pack_feature('COMERCIO', 'reports', 70);
select public._phase12_seed_pack_feature('SERVICIOS', 'customers', 10);
select public._phase12_seed_pack_feature('SERVICIOS', 'sales', 20);
select public._phase12_seed_pack_feature('SERVICIOS', 'cash', 30);
select public._phase12_seed_pack_feature('SERVICIOS', 'reports', 40);
select public._phase12_seed_pack_feature('GESTION_INTEGRAL', 'customers', 10);
select public._phase12_seed_pack_feature('GESTION_INTEGRAL', 'sales', 20);
select public._phase12_seed_pack_feature('GESTION_INTEGRAL', 'suppliers', 30);
select public._phase12_seed_pack_feature('GESTION_INTEGRAL', 'purchases', 40);
select public._phase12_seed_pack_feature('GESTION_INTEGRAL', 'inventory', 50);
select public._phase12_seed_pack_feature('GESTION_INTEGRAL', 'cash', 60);
select public._phase12_seed_pack_feature('GESTION_INTEGRAL', 'banks', 70);
select public._phase12_seed_pack_feature('GESTION_INTEGRAL', 'reports', 80);
drop function if exists public._phase12_seed_pack_feature(text, text, int);
