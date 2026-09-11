-- Phase 12.15 — Final entitlement / ACL security hardening
-- STAGING ONLY (rpcpdrzbcclofvjpgldb)
-- P0: bootstrap must not allow tenant self-grant of entitlements
-- P1: authenticated table ACL = SELECT only (no TRUNCATE/TRIGGER/REFERENCES)

-- ---------------------------------------------------------------------------
-- P0: Drop tenant-callable bootstrap that accepted optional feature codes
-- ---------------------------------------------------------------------------
drop function if exists public.bootstrap_organization_modules(uuid, text[]);
create or replace function public.platform_bootstrap_organization_modules(
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_fid uuid;
  v_codes text[] := array['dashboard', 'accounting'];
begin
  perform public.modules_assert_service_role();

  if not exists (select 1 from public.organizations o where o.id = p_organization_id) then
    raise exception 'ORGANIZATION_NOT_FOUND';
  end if;

  perform public.modules_lock_organization(p_organization_id);

  foreach v_code in array v_codes loop
    select id into v_fid from public.feature_catalog where code = v_code and active;
    if v_fid is null then
      raise exception 'FEATURE_NOT_FOUND:%', v_code;
    end if;

    insert into public.organization_feature_entitlements (
      organization_id, feature_id, status, source_type, metadata, granted_at
    ) values (
      p_organization_id, v_fid, 'GRANTED', 'SYSTEM',
      jsonb_build_object(
        'bootstrap', true,
        'mandatory_core', true,
        'platform_bootstrap', true
      ),
      timezone('utc', now())
    )
    on conflict (organization_id, feature_id) do update set
      status = 'GRANTED'::public.feature_entitlement_status,
      source_type = 'SYSTEM'::public.feature_entitlement_source,
      revoked_at = null,
      metadata = coalesce(public.organization_feature_entitlements.metadata, '{}'::jsonb)
        || jsonb_build_object('platform_bootstrap', true, 'mandatory_core', true),
      updated_at = timezone('utc', now());

    insert into public.organization_feature_preferences (
      organization_id, feature_id, desired_enabled
    ) values (p_organization_id, v_fid, true)
    on conflict (organization_id, feature_id) do update set
      desired_enabled = true,
      updated_at = timezone('utc', now());
  end loop;

  -- medical_legal: explicit RESTRICTED entitlement marker (never GRANTED here)
  select id into v_fid from public.feature_catalog where code = 'medical_legal' and active;
  if v_fid is not null then
    insert into public.organization_feature_entitlements (
      organization_id, feature_id, status, source_type, metadata
    ) values (
      p_organization_id, v_fid, 'RESTRICTED', 'SYSTEM',
      jsonb_build_object('bootstrap', true, 'platform_bootstrap', true)
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
    'platform_bootstrap'
  );
end;
$$;
revoke all on function public.platform_bootstrap_organization_modules(uuid)
  from public, anon, authenticated;
grant execute on function public.platform_bootstrap_organization_modules(uuid)
  to service_role;
comment on function public.platform_bootstrap_organization_modules(uuid) is
  'PLATFORM/service_role only. Provisions mandatory core (dashboard+accounting) entitlements+preferences. Never accepts tenant optional feature lists. Optional modules require prior GRANTED entitlement + set_organization_feature_preference.';
-- Compatibility stub: if anything still calls the old name with optional codes, deny hard.
create or replace function public.bootstrap_organization_modules(
  p_organization_id uuid,
  p_enable_feature_codes text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'BOOTSTRAP_PLATFORM_ONLY: use platform_bootstrap_organization_modules via service_role; optional codes are preference-only';
end;
$$;
revoke all on function public.bootstrap_organization_modules(uuid, text[])
  from public, anon, authenticated;
-- Intentionally NO grant to authenticated/anon. service_role may execute only to receive the deny message in tests.
grant execute on function public.bootstrap_organization_modules(uuid, text[])
  to service_role;
comment on function public.bootstrap_organization_modules(uuid, text[]) is
  'REMOVED tenant capability. Always raises BOOTSTRAP_PLATFORM_ONLY. Optional module selection must use set_organization_feature_preference after platform entitlement grant.';
-- ---------------------------------------------------------------------------
-- P1: Authenticated ACL = SELECT only on Phase 12 governance / projection tables
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
  tables text[] := array[
    'feature_catalog',
    'feature_release_controls',
    'feature_dependencies',
    'module_packs',
    'module_pack_features',
    'organization_feature_entitlements',
    'organization_feature_preferences',
    'organization_features',
    'organization_pack_applications'
  ];
begin
  foreach t in array tables loop
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant select on table public.%I to authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;
-- Snapshot / migration audit tables stay service_role only (no authenticated)
do $$
begin
  if to_regclass('public.phase12_migration_effective_snapshot') is not null then
    revoke all on table public.phase12_migration_effective_snapshot from public, anon, authenticated;
    grant all on table public.phase12_migration_effective_snapshot to service_role;
  end if;
  if to_regclass('public.phase12_migration_effective_diff') is not null then
    revoke all on table public.phase12_migration_effective_diff from public, anon, authenticated;
    grant all on table public.phase12_migration_effective_diff to service_role;
  end if;
end $$;
-- Reaffirm platform RPCs are not tenant-executable
revoke all on function public.platform_enable_organization_feature(uuid, text)
  from public, anon, authenticated;
grant execute on function public.platform_enable_organization_feature(uuid, text) to service_role;
revoke all on function public.platform_disable_organization_feature(uuid, text)
  from public, anon, authenticated;
grant execute on function public.platform_disable_organization_feature(uuid, text) to service_role;
revoke all on function public.platform_grant_feature_entitlement(uuid, text, public.feature_entitlement_source, jsonb)
  from public, anon, authenticated;
grant execute on function public.platform_grant_feature_entitlement(uuid, text, public.feature_entitlement_source, jsonb)
  to service_role;
revoke all on function public.platform_revoke_feature_entitlement(uuid, text)
  from public, anon, authenticated;
grant execute on function public.platform_revoke_feature_entitlement(uuid, text) to service_role;
revoke all on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text)
  from public, anon, authenticated;
grant execute on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text)
  to service_role;
revoke all on function public.recompute_organization_features(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.recompute_organization_features(uuid, uuid, text) to service_role;
revoke all on function public.recompute_feature_for_all_organizations(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.recompute_feature_for_all_organizations(uuid, uuid, text) to service_role;
-- Intentional client RPCs remain authenticated (no anon)
revoke all on function public.get_module_configuration_state(uuid) from public, anon;
grant execute on function public.get_module_configuration_state(uuid) to authenticated;
revoke all on function public.why_feature_unavailable(uuid, text) from public, anon;
grant execute on function public.why_feature_unavailable(uuid, text) to authenticated;
revoke all on function public.set_organization_feature_preference(uuid, text, boolean, boolean)
  from public, anon;
grant execute on function public.set_organization_feature_preference(uuid, text, boolean, boolean)
  to authenticated;
revoke all on function public.preview_module_pack(uuid, uuid) from public, anon;
grant execute on function public.preview_module_pack(uuid, uuid) to authenticated;
revoke all on function public.apply_module_pack(uuid, uuid, text, boolean) from public, anon;
grant execute on function public.apply_module_pack(uuid, uuid, text, boolean) to authenticated;
-- Privilege probe for gates (service_role only)
create or replace function public.phase12_assert_authenticated_table_acl()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  t text;
  tables text[] := array[
    'feature_catalog',
    'feature_release_controls',
    'feature_dependencies',
    'module_packs',
    'module_pack_features',
    'organization_feature_entitlements',
    'organization_feature_preferences',
    'organization_features',
    'organization_pack_applications'
  ];
  v_trunc int := 0;
  v_trig int := 0;
  v_refs int := 0;
  v_mut int := 0;
  v_missing_select int := 0;
  v_details jsonb := '[]'::jsonb;
  v_row jsonb;
begin
  perform public.modules_assert_service_role();

  foreach t in array tables loop
    v_row := jsonb_build_object(
      'table', t,
      'select', has_table_privilege('authenticated', format('%I.%I', 'public', t)::regclass, 'SELECT'),
      'insert', has_table_privilege('authenticated', format('%I.%I', 'public', t)::regclass, 'INSERT'),
      'update', has_table_privilege('authenticated', format('%I.%I', 'public', t)::regclass, 'UPDATE'),
      'delete', has_table_privilege('authenticated', format('%I.%I', 'public', t)::regclass, 'DELETE'),
      'truncate', has_table_privilege('authenticated', format('%I.%I', 'public', t)::regclass, 'TRUNCATE'),
      'trigger', has_table_privilege('authenticated', format('%I.%I', 'public', t)::regclass, 'TRIGGER'),
      'references', has_table_privilege('authenticated', format('%I.%I', 'public', t)::regclass, 'REFERENCES')
    );
    v_details := v_details || jsonb_build_array(v_row);

    if not (v_row->>'select')::boolean then
      v_missing_select := v_missing_select + 1;
    end if;
    if (v_row->>'insert')::boolean
       or (v_row->>'update')::boolean
       or (v_row->>'delete')::boolean then
      v_mut := v_mut + 1;
    end if;
    if (v_row->>'truncate')::boolean then
      v_trunc := v_trunc + 1;
    end if;
    if (v_row->>'trigger')::boolean then
      v_trig := v_trig + 1;
    end if;
    if (v_row->>'references')::boolean then
      v_refs := v_refs + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', v_missing_select = 0 and v_mut = 0 and v_trunc = 0 and v_trig = 0 and v_refs = 0,
    'missing_select_count', v_missing_select,
    'mutation_count', v_mut,
    'truncate_count', v_trunc,
    'trigger_count', v_trig,
    'references_count', v_refs,
    'tables', v_details
  );
end;
$$;
revoke all on function public.phase12_assert_authenticated_table_acl()
  from public, anon, authenticated;
grant execute on function public.phase12_assert_authenticated_table_acl() to service_role;
