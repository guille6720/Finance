-- Phase 12.2 — Organization feature entitlements (platform-owned)

do $$ begin
  create type public.feature_entitlement_status as enum (
    'GRANTED',
    'RESTRICTED',
    'REVOKED',
    'EXPIRED'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.feature_entitlement_source as enum (
    'MIGRATION',
    'MANUAL',
    'PLAN',
    'TRIAL',
    'PROMO',
    'SYSTEM'
  );
exception when duplicate_object then null;
end $$;
create table if not exists public.organization_feature_entitlements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  status public.feature_entitlement_status not null,
  source_type public.feature_entitlement_source not null,
  source_reference text,
  starts_at timestamptz,
  ends_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  granted_at timestamptz,
  granted_by uuid references auth.users (id),
  revoked_at timestamptz,
  revoked_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint organization_feature_entitlements_org_feature_uidx
    unique (organization_id, feature_id),
  constraint organization_feature_entitlements_org_id_unique
    unique (organization_id, id)
);
create index if not exists organization_feature_entitlements_org_status_idx
  on public.organization_feature_entitlements (organization_id, status);
create index if not exists organization_feature_entitlements_feature_idx
  on public.organization_feature_entitlements (feature_id);
create index if not exists organization_feature_entitlements_granted_by_idx
  on public.organization_feature_entitlements (granted_by)
  where granted_by is not null;
create index if not exists organization_feature_entitlements_revoked_by_idx
  on public.organization_feature_entitlements (revoked_by)
  where revoked_by is not null;
create trigger organization_feature_entitlements_set_updated_at
before update on public.organization_feature_entitlements
for each row execute function public.set_updated_at();
alter table public.organization_feature_entitlements enable row level security;
drop policy if exists organization_feature_entitlements_select on public.organization_feature_entitlements;
create policy organization_feature_entitlements_select
  on public.organization_feature_entitlements for select to authenticated
  using (public.is_org_member(organization_id));
revoke all on table public.organization_feature_entitlements from public, anon;
revoke insert, update, delete on table public.organization_feature_entitlements from authenticated;
grant select on table public.organization_feature_entitlements to authenticated;
grant all on table public.organization_feature_entitlements to service_role;
comment on table public.organization_feature_entitlements is
  'PLATFORM entitlement. Tenant SELECT only. No tenant DML. Pack/preference/onboarding cannot grant. starts_at/ends_at schema-ready; auto-expiry DEFERRED.';
