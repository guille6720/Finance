-- Phase 12.12 — Advisor hardening (RLS reaffirm; ACL)

drop policy if exists organization_feature_entitlements_select on public.organization_feature_entitlements;
create policy organization_feature_entitlements_select
  on public.organization_feature_entitlements for select to authenticated
  using (public.is_org_member(organization_id));
drop policy if exists organization_feature_preferences_select on public.organization_feature_preferences;
create policy organization_feature_preferences_select
  on public.organization_feature_preferences for select to authenticated
  using (public.is_org_member(organization_id));
drop policy if exists organization_pack_applications_select on public.organization_pack_applications;
create policy organization_pack_applications_select
  on public.organization_pack_applications for select to authenticated
  using (
    public.has_org_role(
      organization_id,
      array['owner', 'admin', 'manager']::public.member_role[]
    )
  );
revoke insert, update, delete on table public.feature_catalog from authenticated;
grant select on table public.feature_catalog to authenticated;
