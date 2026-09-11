-- Phase 12.8 — Lock down organization_features: engine-only writes

create or replace function public.organization_features_engine_write_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_setting('modules.engine_write', true) is distinct from '1' then
    raise exception 'organization_features is engine-managed; use set_organization_feature_preference';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
drop trigger if exists organization_features_engine_write_trg on public.organization_features;
create trigger organization_features_engine_write_trg
before insert or update or delete on public.organization_features
for each row execute function public.organization_features_engine_write_guard();
-- Drop tenant mutate policies
drop policy if exists organization_features_insert on public.organization_features;
drop policy if exists organization_features_update on public.organization_features;
drop policy if exists organization_features_delete on public.organization_features;
drop policy if exists organization_features_mutate on public.organization_features;
-- Keep SELECT for members (initplan-safe)
drop policy if exists organization_features_select on public.organization_features;
create policy organization_features_select
  on public.organization_features for select to authenticated
  using (
    public.is_org_member(organization_id)
  );
-- ACL: authenticated SELECT only
revoke all on table public.organization_features from public, anon;
revoke insert, update, delete on table public.organization_features from authenticated;
grant select on table public.organization_features to authenticated;
grant all on table public.organization_features to service_role;
comment on table public.organization_features is
  'EFFECTIVE runtime projection. Authenticated SELECT only. Writes via modules engine (modules.engine_write=1).';
