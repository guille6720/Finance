-- Phase 12.11 — Security grants / revoke internal helpers / comments

revoke all on function public.modules_assert_service_role() from public, anon, authenticated;
revoke all on function public.modules_lock_organization(uuid) from public, anon, authenticated;
revoke all on function public.modules_write_audit(uuid, uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.modules_entitlement_is_granted(uuid, uuid) from public, anon, authenticated;
revoke all on function public.modules_entitlement_is_restricted(uuid, uuid) from public, anon, authenticated;
revoke all on function public.modules_preference_desired(uuid, uuid) from public, anon, authenticated;
revoke all on function public.modules_evaluate_feature_state(uuid, uuid) from public, anon, authenticated;
revoke all on function public.recompute_organization_features(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.modules_config_hash(uuid) from public, anon, authenticated;
revoke all on function public.modules_disable_block_reason(uuid, text) from public, anon, authenticated;
revoke all on function public.modules_assert_configure(uuid) from public, anon, authenticated;
revoke all on function public.modules_assert_read(uuid) from public, anon, authenticated;
revoke all on function public.sales_assert_feature(uuid) from public, anon, authenticated;
-- Client intentional
grant execute on function public.get_module_configuration_state(uuid) to authenticated;
grant execute on function public.why_feature_unavailable(uuid, text) to authenticated;
grant execute on function public.set_organization_feature_preference(uuid, text, boolean, boolean) to authenticated;
grant execute on function public.preview_module_pack(uuid, uuid) to authenticated;
grant execute on function public.apply_module_pack(uuid, uuid, text, boolean) to authenticated;
grant execute on function public.bootstrap_organization_modules(uuid, text[]) to authenticated;
-- Platform only
revoke all on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text)
  from public, anon, authenticated;
grant execute on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text)
  to service_role;
revoke all on function public.platform_grant_feature_entitlement(uuid, text, public.feature_entitlement_source, jsonb)
  from public, anon, authenticated;
grant execute on function public.platform_grant_feature_entitlement(uuid, text, public.feature_entitlement_source, jsonb)
  to service_role;
revoke all on function public.platform_revoke_feature_entitlement(uuid, text)
  from public, anon, authenticated;
grant execute on function public.platform_revoke_feature_entitlement(uuid, text)
  to service_role;
revoke all on function public.recompute_feature_for_all_organizations(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.recompute_feature_for_all_organizations(uuid, uuid, text)
  to service_role;
-- Reaffirm table ACL
revoke insert, update, delete on table public.organization_features from authenticated;
revoke insert, update, delete on table public.organization_feature_entitlements from authenticated;
revoke insert, update, delete on table public.organization_feature_preferences from authenticated;
revoke insert, update, delete on table public.feature_release_controls from authenticated;
revoke insert, update, delete on table public.feature_dependencies from authenticated;
revoke insert, update, delete on table public.module_packs from authenticated;
revoke insert, update, delete on table public.module_pack_features from authenticated;
revoke insert, update, delete on table public.organization_pack_applications from authenticated;
comment on function public.get_module_configuration_state(uuid) is
  'SECURITY DEFINER intentional client RPC — module configurator read model.';
comment on function public.set_organization_feature_preference(uuid, text, boolean, boolean) is
  'SECURITY DEFINER intentional client RPC — atomic preference + recompute.';
comment on function public.preview_module_pack(uuid, uuid) is
  'SECURITY DEFINER intentional client RPC — pack preview read-only.';
comment on function public.apply_module_pack(uuid, uuid, text, boolean) is
  'SECURITY DEFINER intentional client RPC — ADD/ENABLE only; never grants entitlement.';
comment on function public.platform_set_feature_release(text, public.feature_release_status, boolean, text) is
  'PLATFORM GOVERNANCE service_role only — updates release and recomputes all orgs.';
