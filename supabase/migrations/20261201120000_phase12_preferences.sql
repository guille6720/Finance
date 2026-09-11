-- Phase 12.3 — Organization feature preferences (RPC-only mutation)

create table if not exists public.organization_feature_preferences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  desired_enabled boolean not null default false,
  updated_by uuid references auth.users (id),
  updated_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  constraint organization_feature_preferences_org_feature_uidx
    unique (organization_id, feature_id),
  constraint organization_feature_preferences_org_id_unique
    unique (organization_id, id)
);
create index if not exists organization_feature_preferences_org_idx
  on public.organization_feature_preferences (organization_id);
create index if not exists organization_feature_preferences_feature_idx
  on public.organization_feature_preferences (feature_id);
create index if not exists organization_feature_preferences_updated_by_idx
  on public.organization_feature_preferences (updated_by)
  where updated_by is not null;
create trigger organization_feature_preferences_set_updated_at
before update on public.organization_feature_preferences
for each row execute function public.set_updated_at();
alter table public.organization_feature_preferences enable row level security;
drop policy if exists organization_feature_preferences_select on public.organization_feature_preferences;
create policy organization_feature_preferences_select
  on public.organization_feature_preferences for select to authenticated
  using (public.is_org_member(organization_id));
revoke all on table public.organization_feature_preferences from public, anon;
revoke insert, update, delete on table public.organization_feature_preferences from authenticated;
grant select on table public.organization_feature_preferences to authenticated;
grant all on table public.organization_feature_preferences to service_role;
comment on table public.organization_feature_preferences is
  'Tenant desired configuration. SELECT ok; mutation ONLY via set_organization_feature_preference / apply_module_pack.';
