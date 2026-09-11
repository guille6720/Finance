-- Phase 11: permissions / feature notes
-- Permissions live in TypeScript ROLE_PERMISSIONS (src/config/features.ts),
-- NOT in a DB permissions table. organization_members.role is member_role enum.
-- This migration does NOT seed dashboard.* / reports.* DB rows.
--
-- Optional: enable dashboard + reports for Demo/QA orgs (staging convenience),
-- matching Phase 10 taxes demo enablement pattern.

insert into public.organization_features (organization_id, feature_id, status, enabled_at)
select o.id, fc.id, 'enabled', timezone('utc', now())
from public.organizations o
cross join public.feature_catalog fc
where fc.code in ('dashboard', 'reports')
  and (
    o.legal_name ilike '%demo%'
    or o.commercial_name ilike '%demo%'
    or o.legal_name ilike '%qa%'
    or o.commercial_name ilike '%qa%'
  )
on conflict (organization_id, feature_id) do update
set status = 'enabled',
    enabled_at = coalesce(public.organization_features.enabled_at, excluded.enabled_at);
comment on function public.get_dashboard_summary(uuid, text, date, date, text) is
  'SECURITY DEFINER intentional. Authz: membership + feature dashboard + module feature/role gates. Permissions dashboard.* are app-layer (ROLE_PERMISSIONS), not DB.';
