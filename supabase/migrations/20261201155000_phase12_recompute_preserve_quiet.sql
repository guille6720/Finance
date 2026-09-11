-- Phase 12.6b — Fix quiet migration recompute to PRESERVE existing effective statuses
-- (Applied after 150000; required before backfill verification.)

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

      if v_quiet and coalesce(v_had, false) then
        update public.organization_features
        set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
              'reason', v_eval->>'reason',
              'source', p_source,
              'evaluated_status', v_new_status
            )
        where organization_id = p_organization_id and feature_id = v_feat.id;
        continue;
      end if;

      if not coalesce(v_had, false) then
        if v_quiet then
          v_new_status := 'disabled'::public.feature_status;
        end if;
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
    exit when v_pass_changed = 0 or v_quiet;
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
