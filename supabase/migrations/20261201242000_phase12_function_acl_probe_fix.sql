-- Phase 12.17 — Fix function ACL probe schema-qualified enums

create or replace function public.phase12_assert_authenticated_function_acl()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  sig text;
  leaks int := 0;
  details jsonb := '[]'::jsonb;
  has_exec boolean;
  funcs text[] := array[
    'platform_bootstrap_organization_modules(uuid)',
    'bootstrap_organization_modules(uuid,text[])',
    'platform_enable_organization_feature(uuid,text)',
    'platform_disable_organization_feature(uuid,text)',
    'platform_grant_feature_entitlement(uuid,text,public.feature_entitlement_source,jsonb)',
    'platform_revoke_feature_entitlement(uuid,text)',
    'platform_set_feature_release(text,public.feature_release_status,boolean,text)',
    'recompute_organization_features(uuid,uuid,text)',
    'recompute_feature_for_all_organizations(uuid,uuid,text)',
    'phase12_assert_authenticated_table_acl()',
    'modules_assert_service_role()',
    'modules_evaluate_feature_state(uuid,uuid)',
    'sales_assert_feature(uuid)'
  ];
begin
  perform public.modules_assert_service_role();

  foreach sig in array funcs loop
    begin
      has_exec := has_function_privilege(
        'authenticated',
        ('public.' || sig)::regprocedure,
        'EXECUTE'
      );
    exception when undefined_function then
      has_exec := false;
    end;
    if has_exec then
      leaks := leaks + 1;
    end if;
    details := details || jsonb_build_array(
      jsonb_build_object('function', sig, 'authenticated_execute', has_exec)
    );
  end loop;

  return jsonb_build_object(
    'ok', leaks = 0,
    'leak_count', leaks,
    'functions', details
  );
end;
$$;
revoke all on function public.phase12_assert_authenticated_function_acl()
  from public, anon, authenticated;
grant execute on function public.phase12_assert_authenticated_function_acl()
  to service_role;
