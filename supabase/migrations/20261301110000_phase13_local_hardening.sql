-- Phase 13 local hardening (local/staging only).
-- Sorts AFTER 20261301100000_phase13_anon_table_acl_hardening.sql.
-- SECURITY DEFINER posture: every elevated function must be intentional,
-- search_path-pinned, and documented in docs/qa/phase13/SECURITY-DEFINER-REGISTRY.md.

-- ---------------------------------------------------------------------------
-- organizations: allow creators to SELECT rows they just inserted.
-- Without this, INSERT ... RETURNING and owner-membership bootstrap fail
-- because organizations_select_member requires is_org_member() before the
-- membership row exists (breaks onboarding).
-- ---------------------------------------------------------------------------

do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'organizations'
      and policyname = 'organizations_select_creator'
  ) then
    execute $p$
      create policy organizations_select_creator
        on public.organizations for select
        to authenticated
        using (created_by = auth.uid())
    $p$;
  end if;
end $$;

comment on policy organizations_select_creator on public.organizations is
  'PHASE13 INTENTIONAL_AND_DOCUMENTED: bootstrap visibility for org creator prior to membership row.';

-- Users must see their own membership rows (RETURNING bootstrap + session resolution).
do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'organization_members'
      and policyname = 'members_select_self'
  ) then
    execute $p$
      create policy members_select_self
        on public.organization_members for select
        to authenticated
        using (user_id = auth.uid())
    $p$;
  end if;
end $$;

comment on policy members_select_self on public.organization_members is
  'PHASE13 INTENTIONAL_AND_DOCUMENTED: self membership visibility for bootstrap RETURNING and session context.';

-- ---------------------------------------------------------------------------
-- handle_new_user: trigger-only; revoke direct client execute
-- ---------------------------------------------------------------------------

revoke all on function public.handle_new_user() from public;
revoke all on function public.handle_new_user() from anon;
revoke all on function public.handle_new_user() from authenticated;

comment on function public.handle_new_user() is
  'PHASE13 INTENTIONAL_AND_DOCUMENTED: auth.users trigger inserts profiles; not callable by clients.';

comment on function public.is_org_member(uuid) is
  'PHASE13 INTENTIONAL_AND_DOCUMENTED: RLS helper; SECURITY DEFINER + search_path=public; scoped to auth.uid().';

comment on function public.has_org_role(uuid, public.member_role[]) is
  'PHASE13 INTENTIONAL_AND_DOCUMENTED: RLS helper; SECURITY DEFINER + search_path=public; scoped to auth.uid().';

comment on function public.can_mutate_org(uuid) is
  'PHASE13 INTENTIONAL_AND_DOCUMENTED: RLS helper wrapping has_org_role(owner|admin|manager).';

-- ---------------------------------------------------------------------------
-- Observability for local/staging capacity reviews (zero-cost)
-- ---------------------------------------------------------------------------

create extension if not exists pg_stat_statements;

-- ---------------------------------------------------------------------------
-- Phase marker (claims Phases 2–12 product domains ARE present via recovery)
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value, description)
values (
  'platform.phase13.status',
  '"in_progress"'::jsonb,
  'Phase 13 readiness: IN PROGRESS until DB+Storage restore drills prove RPO/RTO'
)
on conflict (key) do update
set value = excluded.value,
    description = excluded.description,
    updated_at = timezone('utc', now());

insert into public.app_settings (key, value, description)
values (
  'platform.phase13.dr_rpo_rto_proven',
  'false'::jsonb,
  'Must remain false until actual restore drills prove RPO<=5m and RTO<=4h'
)
on conflict (key) do update
set value = excluded.value,
    description = excluded.description,
    updated_at = timezone('utc', now());
