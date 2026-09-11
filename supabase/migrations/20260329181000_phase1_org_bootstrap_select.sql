-- Phase 1: allow organization bootstrap without widening anon access.
--
-- INSERT ... RETURNING requires the new row to satisfy SELECT policies.
-- organizations_select_member previously required is_org_member(id), but
-- membership is created AFTER the organization row. That blocked onboarding.
--
-- Fix: creators may SELECT their own organization via created_by = auth.uid().
-- Membership remains the primary tenant gate for everyone else.

drop policy if exists organizations_select_member on public.organizations;
create policy organizations_select_member
  on public.organizations
  for select
  to authenticated
  using (
    public.is_org_member(id)
    or created_by = (select auth.uid())
  );
