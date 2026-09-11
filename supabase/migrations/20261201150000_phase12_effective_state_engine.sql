-- Phase 12.6 — Effective state engine (internal helpers + platform mutate+recompute)

create or replace function public.modules_assert_service_role()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'MODULES_PLATFORM_ONLY';
  end if;
end;
$$;
revoke all on function public.modules_assert_service_role() from public, anon, authenticated;
create or replace function public.modules_lock_organization(p_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform 1 from public.organizations where id = p_organization_id for update;
  if not found then
    raise exception 'ORGANIZATION_NOT_FOUND';
  end if;
  perform pg_advisory_xact_lock(hashtext('modules:' || p_organization_id::text));
end;
$$;
revoke all on function public.modules_lock_organization(uuid) from public, anon, authenticated;
create or replace function public.modules_write_audit(
  p_organization_id uuid,
  p_actor uuid,
  p_event_type text,
  p_action text,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.audit_events (
    organization_id, actor_user_id, event_type, entity_type, entity_id, action, metadata
  ) values (
    p_organization_id, p_actor, p_event_type, 'organization_feature',
    coalesce(p_metadata->>'feature_code', p_organization_id::text),
    p_action, coalesce(p_metadata, '{}'::jsonb)
  );
end;
$$;
revoke all on function public.modules_write_audit(uuid, uuid, text, text, jsonb)
  from public, anon, authenticated;
create or replace function public.modules_entitlement_is_granted(
  p_organization_id uuid,
  p_feature_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_feature_entitlements e
    where e.organization_id = p_organization_id
      and e.feature_id = p_feature_id
      and e.status = 'GRANTED'::public.feature_entitlement_status
      -- Auto-expiry DEFERRED: ends_at is informational until platform expiration engine exists
  );
$$;
revoke all on function public.modules_entitlement_is_granted(uuid, uuid)
  from public, anon, authenticated;
create or replace function public.modules_entitlement_is_restricted(
  p_organization_id uuid,
  p_feature_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_feature_entitlements e
    where e.organization_id = p_organization_id
      and e.feature_id = p_feature_id
      and e.status = 'RESTRICTED'::public.feature_entitlement_status
  );
$$;
revoke all on function public.modules_entitlement_is_restricted(uuid, uuid)
  from public, anon, authenticated;
create or replace function public.modules_preference_desired(
  p_organization_id uuid,
  p_feature_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
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
$$;
revoke all on function public.modules_preference_desired(uuid, uuid)
  from public, anon, authenticated;
-- Returns jsonb: { status: feature_status, reason: text, legacy_exemption: bool }
create or replace function public.modules_evaluate_feature_state(
  p_organization_id uuid,
  p_feature_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
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
    return jsonb_build_object('status', 'disabled', 'reason', 'FEATURE_INACTIVE');
  end if;

  select * into v_rel from public.feature_release_controls where feature_id = p_feature_id;
  if not found then
    return jsonb_build_object('status', 'disabled', 'reason', 'RELEASE_MISSING');
  end if;

  select * into v_ent
  from public.organization_feature_entitlements
  where organization_id = p_organization_id and feature_id = p_feature_id;

  if found and coalesce(v_ent.metadata->>'legacy_core_exemption', 'false') = 'true' then
    v_legacy := true;
  end if;

  v_pref := public.modules_preference_desired(p_organization_id, p_feature_id);

  -- ALWAYS mandatory core: force enabled regardless of preference
  if v_rel.mandatory_core_policy = 'ALWAYS'::public.feature_mandatory_core_policy
     and v_rel.release_status in (
       'AVAILABLE'::public.feature_release_status,
       'PREVIEW'::public.feature_release_status
     )
     and public.modules_entitlement_is_granted(p_organization_id, p_feature_id)
  then
    return jsonb_build_object('status', 'enabled', 'reason', 'ACTIVE', 'legacy_exemption', false);
  end if;

  if v_rel.release_status = 'RESTRICTED'::public.feature_release_status
     or public.modules_entitlement_is_restricted(p_organization_id, p_feature_id)
  then
    return jsonb_build_object('status', 'restricted', 'reason', 'RESTRICTED', 'legacy_exemption', v_legacy);
  end if;

  if v_rel.release_status = 'COMING_SOON'::public.feature_release_status then
    return jsonb_build_object('status', 'disabled', 'reason', 'COMING_SOON', 'legacy_exemption', v_legacy);
  end if;

  if v_rel.release_status in (
    'BLOCKED'::public.feature_release_status,
    'RETIRED'::public.feature_release_status
  ) then
    return jsonb_build_object('status', 'disabled', 'reason', 'RELEASE_BLOCKED', 'legacy_exemption', v_legacy);
  end if;

  if not public.modules_entitlement_is_granted(p_organization_id, p_feature_id) then
    if v_legacy then
      return jsonb_build_object('status', 'disabled', 'reason', 'LEGACY_CORE_EXEMPTION', 'legacy_exemption', true);
    end if;
    return jsonb_build_object('status', 'disabled', 'reason', 'NOT_ENTITLED', 'legacy_exemption', false);
  end if;

  if not v_pref then
    if v_legacy then
      return jsonb_build_object('status', 'disabled', 'reason', 'LEGACY_CORE_EXEMPTION', 'legacy_exemption', true);
    end if;
    return jsonb_build_object('status', 'disabled', 'reason', 'PREFERENCE_DISABLED', 'legacy_exemption', false);
  end if;

  -- HARD dependencies must be effectively enabled (skipped during migration quiet pass)
  if coalesce(current_setting('modules.migration_skip_hard_deps', true), '') is distinct from '1' then
    for v_dep_code in
      select rc.code
      from public.feature_dependencies d
      join public.feature_catalog rc on rc.id = d.required_feature_id
      where d.feature_id = p_feature_id
        and d.active
        and d.dependency_kind = 'HARD'::public.feature_dependency_kind
    loop
      select coalesce(
        (
          select ofe.status = 'enabled'::public.feature_status
          from public.organization_features ofe
          join public.feature_catalog fc on fc.id = ofe.feature_id
          where ofe.organization_id = p_organization_id and fc.code = v_dep_code
        ),
        false
      ) into v_dep_ok;
      if not v_dep_ok then
        return jsonb_build_object(
          'status', 'disabled',
          'reason', 'DEPENDENCY_REQUIRED',
          'dependency', v_dep_code,
          'legacy_exemption', v_legacy
        );
      end if;
    end loop;
  end if;

  if v_rel.requires_legal_review and v_rel.release_status = 'PREVIEW'::public.feature_release_status then
    -- still usable in staging preview; reason ACTIVE with review flags exposed separately
    null;
  end if;

  return jsonb_build_object('status', 'enabled', 'reason', 'ACTIVE', 'legacy_exemption', v_legacy);
end;
$$;
revoke all on function public.modules_evaluate_feature_state(uuid, uuid)
  from public, anon, authenticated;
create or replace function public.recompute_organization_features(
  p_organization_id uuid,
  p_actor uuid default null,
  p_source text default 'recompute'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
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
  v_engine := current_setting('modules.engine_write', true);
  perform set_config('modules.engine_write', '1', true);
  v_quiet := coalesce(current_setting('modules.migration_quiet', true), '') = '1';

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
      v_new_status := (v_eval->>'status')::public.feature_status;

      select true, ofe.status into v_had, v_old_status
      from public.organization_features ofe
      where ofe.organization_id = p_organization_id and ofe.feature_id = v_feat.id;

      if not coalesce(v_had, false) then
        insert into public.organization_features (
          organization_id, feature_id, status, enabled_at, metadata
        ) values (
          p_organization_id, v_feat.id, v_new_status,
          case when v_new_status = 'enabled' then timezone('utc', now()) else null end,
          jsonb_build_object('reason', v_eval->>'reason', 'source', p_source)
        );
        v_pass_changed := v_pass_changed + 1;
        if not v_quiet then
          perform public.modules_write_audit(
            p_organization_id, p_actor, 'module.effective.changed', 'create',
            jsonb_build_object(
              'feature_code', v_feat.code,
              'old_status', 'disabled',
              'new_status', v_new_status,
              'reason', v_eval->>'reason',
              'source', p_source
            )
          );
        end if;
      elsif v_old_status is distinct from v_new_status then
        update public.organization_features
        set status = v_new_status,
            enabled_at = case
              when v_new_status = 'enabled' then coalesce(enabled_at, timezone('utc', now()))
              else enabled_at
            end,
            metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
              'reason', v_eval->>'reason',
              'source', p_source
            ),
            updated_at = timezone('utc', now())
        where organization_id = p_organization_id and feature_id = v_feat.id;
        v_pass_changed := v_pass_changed + 1;
        if not v_quiet then
          perform public.modules_write_audit(
            p_organization_id, p_actor, 'module.effective.changed', 'update',
            jsonb_build_object(
              'feature_code', v_feat.code,
              'old_status', v_old_status,
              'new_status', v_new_status,
              'reason', v_eval->>'reason',
              'source', p_source
            )
          );
        end if;
      else
        update public.organization_features
        set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
              'reason', v_eval->>'reason',
              'source', p_source
            )
        where organization_id = p_organization_id and feature_id = v_feat.id;
      end if;
    end loop;
    v_changed := v_changed + v_pass_changed;
    exit when v_pass_changed = 0;
  end loop;

  if v_engine is null then
    perform set_config('modules.engine_write', '', true);
  else
    perform set_config('modules.engine_write', v_engine, true);
  end if;

  return jsonb_build_object(
    'organization_id', p_organization_id,
    'changed', v_changed,
    'hash', public.modules_config_hash(p_organization_id)
  );
end;
$$;
revoke all on function public.recompute_organization_features(uuid, uuid, text)
  from public, anon, authenticated;
create or replace function public.modules_config_hash(p_organization_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_payload text;
begin
  select string_agg(
    format(
      '%s|%s|%s|%s|%s',
      c.code,
      coalesce(r.release_status::text, ''),
      coalesce(e.status::text, 'NONE'),
      case when coalesce(p.desired_enabled, false) then '1' else '0' end,
      coalesce(ofe.status::text, 'disabled')
    ),
    ',' order by c.code
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

  return encode(extensions.digest(convert_to(coalesce(v_payload, ''), 'UTF8'), 'sha256'), 'hex');
end;
$$;
revoke all on function public.modules_config_hash(uuid) from public, anon, authenticated;
-- Disable safety: returns null if ok, else reason code
create or replace function public.modules_disable_block_reason(
  p_organization_id uuid,
  p_feature_code text
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cnt int;
begin
  if p_feature_code = 'dashboard' then
    return 'MANDATORY_CORE';
  end if;

  if p_feature_code = 'fiscal_invoicing' then
    select count(*)::int into v_cnt from public.fiscal_documents
    where organization_id = p_organization_id
      and status::text in ('AUTHORIZING', 'RECONCILIATION_REQUIRED');
    if v_cnt > 0 then return 'FISCAL_UNRESOLVED_TRUTH'; end if;
  end if;

  if p_feature_code = 'pos' then
    select count(*)::int into v_cnt from public.pos_sessions
    where organization_id = p_organization_id and status::text = 'OPEN';
    if v_cnt > 0 then return 'POS_OPEN_SESSION'; end if;
    select count(*)::int into v_cnt from public.pos_sales
    where organization_id = p_organization_id
      and status::text in (
        'STOCK_RESERVED', 'WAITING_FISCAL', 'FISCAL_AUTHORIZED',
        'FINALIZING', 'RECONCILIATION_REQUIRED'
      );
    if v_cnt > 0 then return 'POS_UNSAFE_WORKFLOW'; end if;
  end if;

  if p_feature_code = 'taxes' then
    select count(*)::int into v_cnt from public.tax_periods
    where organization_id = p_organization_id and status::text = 'IN_REVIEW';
    if v_cnt > 0 then return 'TAX_PERIOD_IN_REVIEW'; end if;
  end if;

  if p_feature_code = 'inventory' then
    select count(*)::int into v_cnt from public.inventory_reservations
    where organization_id = p_organization_id and status::text = 'ACTIVE';
    if v_cnt > 0 then return 'INVENTORY_ACTIVE_RESERVATION'; end if;
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
    and d.dependency_kind = 'HARD'::public.feature_dependency_kind
    and ofe.status = 'enabled'::public.feature_status;
  if v_cnt > 0 then return 'FEATURE_DEPENDENCY_IN_USE'; end if;

  return null;
end;
$$;
revoke all on function public.modules_disable_block_reason(uuid, text)
  from public, anon, authenticated;
-- Recompute all orgs for one feature (release/entitlement propagation)
create or replace function public.recompute_feature_for_all_organizations(
  p_feature_id uuid,
  p_actor uuid default null,
  p_source text default 'release_change'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
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
  return jsonb_build_object('organizations_recomputed', v_n, 'feature_id', p_feature_id);
end;
$$;
revoke all on function public.recompute_feature_for_all_organizations(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.recompute_feature_for_all_organizations(uuid, uuid, text)
  to service_role;
-- Platform: set release + recompute all
create or replace function public.platform_set_feature_release(
  p_feature_code text,
  p_release_status public.feature_release_status,
  p_self_service_allowed boolean default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fid uuid;
  v_old public.feature_release_status;
begin
  perform public.modules_assert_service_role();
  select id into v_fid from public.feature_catalog where code = p_feature_code;
  if v_fid is null then raise exception 'FEATURE_NOT_FOUND'; end if;

  select release_status into v_old from public.feature_release_controls where feature_id = v_fid;
  update public.feature_release_controls
  set release_status = p_release_status,
      self_service_allowed = coalesce(p_self_service_allowed, self_service_allowed),
      notes = coalesce(p_notes, notes),
      updated_at = timezone('utc', now())
  where feature_id = v_fid;

  perform public.modules_write_audit(
    null, null, 'module.release.changed', 'update',
    jsonb_build_object(
      'feature_code', p_feature_code,
      'old_status', v_old,
      'new_status', p_release_status
    )
  );

  return public.recompute_feature_for_all_organizations(v_fid, null, 'release_change');
end;
$$;
revoke all on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text)
  from public, anon, authenticated;
grant execute on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text)
  to service_role;
create or replace function public.platform_grant_feature_entitlement(
  p_organization_id uuid,
  p_feature_code text,
  p_source_type public.feature_entitlement_source default 'MANUAL',
  p_metadata jsonb default '{}'::jsonb
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
  select id into v_fid from public.feature_catalog where code = p_feature_code;
  if v_fid is null then raise exception 'FEATURE_NOT_FOUND'; end if;

  insert into public.organization_feature_entitlements (
    organization_id, feature_id, status, source_type, metadata, granted_at
  ) values (
    p_organization_id, v_fid, 'GRANTED', p_source_type, coalesce(p_metadata, '{}'::jsonb),
    timezone('utc', now())
  )
  on conflict (organization_id, feature_id) do update set
    status = 'GRANTED'::public.feature_entitlement_status,
    source_type = excluded.source_type,
    metadata = coalesce(public.organization_feature_entitlements.metadata, '{}'::jsonb)
      || coalesce(excluded.metadata, '{}'::jsonb),
    granted_at = timezone('utc', now()),
    revoked_at = null,
    revoked_by = null,
    updated_at = timezone('utc', now());

  perform public.modules_write_audit(
    p_organization_id, null, 'module.entitlement.granted', 'grant',
    jsonb_build_object('feature_code', p_feature_code, 'source_type', p_source_type)
  );

  return public.recompute_organization_features(p_organization_id, null, 'entitlement_grant');
end;
$$;
revoke all on function public.platform_grant_feature_entitlement(uuid, text, public.feature_entitlement_source, jsonb)
  from public, anon, authenticated;
grant execute on function public.platform_grant_feature_entitlement(uuid, text, public.feature_entitlement_source, jsonb)
  to service_role;
create or replace function public.platform_revoke_feature_entitlement(
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
  select id into v_fid from public.feature_catalog where code = p_feature_code;
  if v_fid is null then raise exception 'FEATURE_NOT_FOUND'; end if;

  update public.organization_feature_entitlements
  set status = 'REVOKED'::public.feature_entitlement_status,
      revoked_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where organization_id = p_organization_id and feature_id = v_fid;

  perform public.modules_write_audit(
    p_organization_id, null, 'module.entitlement.revoked', 'revoke',
    jsonb_build_object('feature_code', p_feature_code)
  );

  return public.recompute_organization_features(p_organization_id, null, 'entitlement_revoke');
end;
$$;
revoke all on function public.platform_revoke_feature_entitlement(uuid, text)
  from public, anon, authenticated;
grant execute on function public.platform_revoke_feature_entitlement(uuid, text)
  to service_role;
comment on function public.recompute_organization_features(uuid, uuid, text) is
  'INTERNAL effective projection writer. No authenticated EXECUTE.';
