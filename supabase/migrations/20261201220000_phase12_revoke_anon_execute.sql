-- Phase 12.13 — Revoke anon EXECUTE on intentional client SECURITY DEFINER RPCs

revoke all on function public.get_module_configuration_state(uuid) from public, anon;
grant execute on function public.get_module_configuration_state(uuid) to authenticated;
revoke all on function public.why_feature_unavailable(uuid, text) from public, anon;
grant execute on function public.why_feature_unavailable(uuid, text) to authenticated;
revoke all on function public.set_organization_feature_preference(uuid, text, boolean, boolean) from public, anon;
grant execute on function public.set_organization_feature_preference(uuid, text, boolean, boolean) to authenticated;
revoke all on function public.preview_module_pack(uuid, uuid) from public, anon;
grant execute on function public.preview_module_pack(uuid, uuid) to authenticated;
revoke all on function public.apply_module_pack(uuid, uuid, text, boolean) from public, anon;
grant execute on function public.apply_module_pack(uuid, uuid, text, boolean) to authenticated;
revoke all on function public.bootstrap_organization_modules(uuid, text[]) from public, anon;
grant execute on function public.bootstrap_organization_modules(uuid, text[]) to authenticated;
