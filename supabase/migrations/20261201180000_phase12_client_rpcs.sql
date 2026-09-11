-- Phase 12.9 — Client RPCs (intentional authenticated EXECUTE)

create or replace function public.modules_assert_configure(p_organization_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.has_org_role(
    p_organization_id,
    array['owner', 'admin']::public.member_role[]
  ) then
    raise exception 'MODULES_CONFIGURE_DENIED';
  end if;
  return v_uid;
end;
$$;
revoke all on function public.modules_assert_configure(uuid) from public, anon, authenticated;
create or replace function public.modules_assert_read(p_organization_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_org_member(p_organization_id) then
    raise exception 'NOT_ORG_MEMBER';
  end if;
  return v_uid;
end;
$$;
revoke all on function public.modules_assert_read(uuid) from public, anon, authenticated;
create or replace function public.get_module_configuration_state(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_items jsonb := '[]'::jsonb;
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
      coalesce(ofe.status::text, 'disabled') as effective_status
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
      'code', req.code,
      'kind', d.dependency_kind,
      'condition_code', d.condition_code
    ) order by d.dependency_kind, req.code), '[]'::jsonb)
    into v_deps
    from public.feature_dependencies d
    join public.feature_catalog req on req.id = d.required_feature_id
    where d.feature_id = r.id and d.active;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'feature_code', r.code,
      'name', r.name,
      'description', r.description,
      'category', r.category,
      'release_status', r.release_status,
      'entitlement_status', r.entitlement_status,
      'desired_enabled', r.desired_enabled,
      'effective_status', r.effective_status,
      'blocking_reason_code', v_eval->>'reason',
      'self_service_allowed', coalesce(r.self_service_allowed, false),
      'mandatory_core_policy', r.mandatory_core_policy,
      'requires_legal_review', coalesce(r.requires_legal_review, false),
      'requires_professional_review', coalesce(r.requires_professional_review, false),
      'legacy_exemption', coalesce((v_eval->>'legacy_exemption')::boolean, false),
      'dependencies', v_deps
    ));
  end loop;

  return jsonb_build_object(
    'organization_id', p_organization_id,
    'configuration_hash', public.modules_config_hash(p_organization_id),
    'modules', v_items,
    'generated_by', v_uid
  );
end;
$$;
revoke all on function public.get_module_configuration_state(uuid) from public, anon;
grant execute on function public.get_module_configuration_state(uuid) to authenticated;
create or replace function public.why_feature_unavailable(
  p_organization_id uuid,
  p_feature_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_fid uuid;
  v_eval jsonb;
begin
  perform public.modules_assert_read(p_organization_id);
  select id into v_fid from public.feature_catalog where code = p_feature_code;
  if v_fid is null then raise exception 'FEATURE_NOT_FOUND'; end if;
  v_eval := public.modules_evaluate_feature_state(p_organization_id, v_fid);
  return jsonb_build_object(
    'feature_code', p_feature_code,
    'reason', v_eval->>'reason',
    'status', v_eval->>'status',
    'dependency', v_eval->>'dependency'
  );
end;
$$;
revoke all on function public.why_feature_unavailable(uuid, text) from public, anon;
grant execute on function public.why_feature_unavailable(uuid, text) to authenticated;
create or replace function public.set_organization_feature_preference(
  p_organization_id uuid,
  p_feature_code text,
  p_desired_enabled boolean,
  p_confirm_dependencies boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
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
  if v_fid is null then raise exception 'FEATURE_NOT_FOUND'; end if;
  select * into v_rel from public.feature_release_controls where feature_id = v_fid;
  if not found then raise exception 'RELEASE_MISSING'; end if;

  v_hash_before := public.modules_config_hash(p_organization_id);

  if v_rel.mandatory_core_policy = 'ALWAYS'::public.feature_mandatory_core_policy
     and not p_desired_enabled then
    raise exception 'MANDATORY_CORE';
  end if;

  if p_feature_code = 'accounting' and not p_desired_enabled then
    if exists (
      select 1 from public.organization_features ofe
      where ofe.organization_id = p_organization_id and ofe.feature_id = v_fid
        and ofe.status = 'enabled'
    ) then
      raise exception 'MANDATORY_CORE';
    end if;
  end if;

  if p_desired_enabled then
    if v_rel.release_status = 'COMING_SOON'::public.feature_release_status then
      raise exception 'FEATURE_NOT_RELEASED';
    end if;
    if v_rel.release_status in (
      'BLOCKED'::public.feature_release_status,
      'RETIRED'::public.feature_release_status
    ) then
      raise exception 'RELEASE_BLOCKED';
    end if;
    if v_rel.release_status = 'RESTRICTED'::public.feature_release_status then
      raise exception 'RESTRICTED';
    end if;
    if not coalesce(v_rel.self_service_allowed, false)
       and v_rel.mandatory_core_policy = 'NONE'::public.feature_mandatory_core_policy then
      raise exception 'SELF_SERVICE_DENIED';
    end if;
    -- NEW_ORGS_ONLY accounting: self-service enable allowed when entitled
    if p_feature_code = 'accounting'
       and not public.modules_entitlement_is_granted(p_organization_id, v_fid) then
      raise exception 'NOT_ENTITLED';
    end if;
    if p_feature_code <> 'accounting'
       and not public.modules_entitlement_is_granted(p_organization_id, v_fid) then
      raise exception 'NOT_ENTITLED';
    end if;
    if public.modules_entitlement_is_restricted(p_organization_id, v_fid) then
      raise exception 'RESTRICTED';
    end if;

    for v_dep_code in
      select req.code
      from public.feature_dependencies d
      join public.feature_catalog req on req.id = d.required_feature_id
      left join public.organization_features ofe
        on ofe.organization_id = p_organization_id and ofe.feature_id = req.id
      where d.feature_id = v_fid
        and d.active
        and d.dependency_kind = 'HARD'::public.feature_dependency_kind
        and coalesce(ofe.status, 'disabled'::public.feature_status)
          is distinct from 'enabled'::public.feature_status
    loop
      if not p_confirm_dependencies then
        raise exception 'DEPENDENCY_REQUIRED:%', v_dep_code;
      end if;
      select id into v_dep_fid from public.feature_catalog where code = v_dep_code;
      select * into v_dep_rel from public.feature_release_controls where feature_id = v_dep_fid;
      if not public.modules_entitlement_is_granted(p_organization_id, v_dep_fid) then
        raise exception 'NOT_ENTITLED:%', v_dep_code;
      end if;
      if not coalesce(v_dep_rel.self_service_allowed, false)
         and v_dep_rel.mandatory_core_policy = 'NONE'::public.feature_mandatory_core_policy then
        raise exception 'SELF_SERVICE_DENIED:%', v_dep_code;
      end if;
      insert into public.organization_feature_preferences (
        organization_id, feature_id, desired_enabled, updated_by
      ) values (p_organization_id, v_dep_fid, true, v_uid)
      on conflict (organization_id, feature_id) do update set
        desired_enabled = true,
        updated_by = excluded.updated_by,
        updated_at = timezone('utc', now());
    end loop;
  else
    v_block := public.modules_disable_block_reason(p_organization_id, p_feature_code);
    if v_block is not null then
      perform public.modules_write_audit(
        p_organization_id, v_uid, 'module.disable.blocked', 'block',
        jsonb_build_object('feature_code', p_feature_code, 'reason', v_block)
      );
      raise exception '%', v_block;
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
    updated_at = timezone('utc', now());

  if p_feature_code = 'accounting' and p_desired_enabled then
    update public.organization_feature_entitlements
    set metadata = coalesce(metadata, '{}'::jsonb)
      || jsonb_build_object('legacy_core_exemption', false, 'activated_from_legacy', true),
        updated_at = timezone('utc', now())
    where organization_id = p_organization_id and feature_id = v_fid;
  end if;

  perform public.modules_write_audit(
    p_organization_id, v_uid,
    case when p_desired_enabled then 'module.preference.enabled' else 'module.preference.disabled' end,
    'update',
    jsonb_build_object('feature_code', p_feature_code, 'desired_enabled', p_desired_enabled)
  );

  perform public.recompute_organization_features(p_organization_id, v_uid, 'preference_change');
  v_hash_after := public.modules_config_hash(p_organization_id);

  return jsonb_build_object(
    'feature_code', p_feature_code,
    'desired_enabled', p_desired_enabled,
    'configuration_before_hash', v_hash_before,
    'configuration_after_hash', v_hash_after
  );
end;
$$;
create or replace function public.preview_module_pack(
  p_organization_id uuid,
  p_pack_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_pack public.module_packs%rowtype;
  v_items jsonb := '[]'::jsonb;
  r record;
  v_class text;
begin
  v_uid := public.modules_assert_configure(p_organization_id);
  select * into v_pack from public.module_packs where id = p_pack_id and active;
  if not found then raise exception 'PACK_NOT_FOUND'; end if;

  for r in
    select
      c.code,
      c.name,
      mpf.recommended_enabled,
      rc.release_status,
      e.status as entitlement_status,
      coalesce(ofe.status::text, 'disabled') as effective_status
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
    if r.release_status = 'COMING_SOON'::public.feature_release_status then
      v_class := 'coming_soon';
    elsif r.release_status = 'RESTRICTED'::public.feature_release_status
         or r.entitlement_status = 'RESTRICTED'::public.feature_entitlement_status then
      v_class := 'restricted';
    elsif r.release_status in (
      'BLOCKED'::public.feature_release_status,
      'RETIRED'::public.feature_release_status
    ) then
      v_class := 'release_blocked';
    elsif r.entitlement_status is distinct from 'GRANTED'::public.feature_entitlement_status then
      v_class := 'not_entitled';
    elsif r.effective_status = 'enabled' then
      v_class := 'already_enabled';
    else
      v_class := 'available';
    end if;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'feature_code', r.code,
      'name', r.name,
      'classification', v_class,
      'recommended_enabled', r.recommended_enabled
    ));
  end loop;

  return jsonb_build_object(
    'pack_id', p_pack_id,
    'pack_code', v_pack.code,
    'pack_name', v_pack.name,
    'configuration_before_hash', public.modules_config_hash(p_organization_id),
    'items', v_items,
    'generated_by', v_uid
  );
end;
$$;
revoke all on function public.preview_module_pack(uuid, uuid) from public, anon;
grant execute on function public.preview_module_pack(uuid, uuid) to authenticated;
create or replace function public.apply_module_pack(
  p_organization_id uuid,
  p_pack_id uuid,
  p_expected_configuration_hash text,
  p_confirm boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
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
  if not p_confirm then raise exception 'CONFIRM_REQUIRED'; end if;

  perform public.modules_lock_organization(p_organization_id);
  v_hash := public.modules_config_hash(p_organization_id);
  if v_hash is distinct from p_expected_configuration_hash then
    raise exception 'CONFIGURATION_CHANGED';
  end if;

  v_preview := public.preview_module_pack(p_organization_id, p_pack_id);

  for v_item in select * from jsonb_array_elements(v_preview->'items')
  loop
    v_code := v_item->>'feature_code';
    v_class := v_item->>'classification';
    if v_class = 'available' and coalesce((v_item->>'recommended_enabled')::boolean, true) then
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
      'enabled_count', v_enabled,
      'skipped_count', v_skipped,
      'preview', v_preview
    )
  );

  perform public.modules_write_audit(
    p_organization_id, v_uid, 'module.pack.applied', 'apply',
    jsonb_build_object(
      'pack_id', p_pack_id,
      'enabled_count', v_enabled,
      'configuration_before_hash', v_hash,
      'configuration_after_hash', v_after
    )
  );

  return jsonb_build_object(
    'pack_id', p_pack_id,
    'enabled_count', v_enabled,
    'skipped_count', v_skipped,
    'configuration_before_hash', v_hash,
    'configuration_after_hash', v_after
  );
end;
$$;
revoke all on function public.apply_module_pack(uuid, uuid, text, boolean) from public, anon;
grant execute on function public.apply_module_pack(uuid, uuid, text, boolean) to authenticated;
comment on function public.apply_module_pack(uuid, uuid, text, boolean) is
  'SECURITY DEFINER intentional: ADD/ENABLE preferences only. Never grants entitlements.';
comment on function public.get_module_configuration_state(uuid) is
  'SECURITY DEFINER intentional client RPC: module configurator read model.';
