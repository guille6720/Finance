-- Phase 12.14 — service_role OF bypass + platform_enable helper for tests/ops

create or replace function public.organization_features_engine_write_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.role() = 'service_role' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if current_setting('modules.engine_write', true) is distinct from '1' then
    raise exception 'organization_features is engine-managed; use set_organization_feature_preference';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
create or replace function public.platform_enable_organization_feature(
  p_organization_id uuid,
  p_feature_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fid uuid;
  v_dep_code text;
begin
  perform public.modules_assert_service_role();
  select id into v_fid from public.feature_catalog where code = p_feature_code and active;
  if v_fid is null then raise exception 'FEATURE_NOT_FOUND'; end if;

  -- Cascade HARD dependencies first so recompute can succeed.
  for v_dep_code in
    select rc.code
    from public.feature_dependencies d
    join public.feature_catalog rc on rc.id = d.required_feature_id
    where d.feature_id = v_fid
      and d.active
      and d.dependency_kind = 'HARD'::public.feature_dependency_kind
  loop
    perform public.platform_enable_organization_feature(p_organization_id, v_dep_code);
  end loop;

  insert into public.organization_feature_entitlements (
    organization_id, feature_id, status, source_type, metadata, granted_at
  ) values (
    p_organization_id, v_fid, 'GRANTED', 'SYSTEM',
    jsonb_build_object('platform_enable', true), timezone('utc', now())
  )
  on conflict (organization_id, feature_id) do update set
    status = 'GRANTED'::public.feature_entitlement_status,
    revoked_at = null,
    updated_at = timezone('utc', now());

  insert into public.organization_feature_preferences (
    organization_id, feature_id, desired_enabled
  ) values (p_organization_id, v_fid, true)
  on conflict (organization_id, feature_id) do update set
    desired_enabled = true,
    updated_at = timezone('utc', now());

  return public.recompute_organization_features(p_organization_id, null, 'platform_enable');
end;
$$;
revoke all on function public.platform_enable_organization_feature(uuid, text)
  from public, anon, authenticated;
grant execute on function public.platform_enable_organization_feature(uuid, text)
  to service_role;
create or replace function public.platform_disable_organization_feature(
  p_organization_id uuid,
  p_feature_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fid uuid;
begin
  perform public.modules_assert_service_role();
  select id into v_fid from public.feature_catalog where code = p_feature_code and active;
  if v_fid is null then raise exception 'FEATURE_NOT_FOUND'; end if;

  insert into public.organization_feature_preferences (
    organization_id, feature_id, desired_enabled
  ) values (p_organization_id, v_fid, false)
  on conflict (organization_id, feature_id) do update set
    desired_enabled = false,
    updated_at = timezone('utc', now());

  return public.recompute_organization_features(p_organization_id, null, 'platform_disable');
end;
$$;
revoke all on function public.platform_disable_organization_feature(uuid, text)
  from public, anon, authenticated;
grant execute on function public.platform_disable_organization_feature(uuid, text)
  to service_role;
comment on function public.platform_enable_organization_feature(uuid, text) is
  'PLATFORM/service_role only: grant + preference + recompute. Used by staging gates/e2e.';
comment on function public.platform_disable_organization_feature(uuid, text) is
  'PLATFORM/service_role only: preference off + recompute (entitlement retained).';
