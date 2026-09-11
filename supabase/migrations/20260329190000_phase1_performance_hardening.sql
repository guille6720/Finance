-- Phase 1 final performance hardening (STAGING only)
-- Project: rpcpdrzbcclofvjpgldb
-- Additive migration. Does not rewrite earlier migrations.
--
-- 1) auth_rls_initplan: wrap auth.uid() as (select auth.uid())
-- 2) multiple_permissive_policies: narrow FOR ALL mutate policies so they
--    do not also provide SELECT (SELECT stays on dedicated policies)
--    and consolidate profiles SELECT into one clear OR policy
-- 3) unindexed_foreign_keys: add covering indexes
--
-- Authorization semantics intentionally unchanged for tenant isolation.

-- ---------------------------------------------------------------------------
-- Foreign-key covering indexes
-- ---------------------------------------------------------------------------

create index if not exists accounting_periods_closed_by_idx
  on public.accounting_periods (closed_by);
create index if not exists audit_events_actor_user_id_idx
  on public.audit_events (actor_user_id);
create index if not exists fiscal_profiles_fiscal_condition_id_idx
  on public.fiscal_profiles (fiscal_condition_id);
create index if not exists organization_features_feature_id_idx
  on public.organization_features (feature_id);
create index if not exists organization_members_invited_by_idx
  on public.organization_members (invited_by);
create index if not exists organizations_created_by_idx
  on public.organizations (created_by);
-- ---------------------------------------------------------------------------
-- profiles: single SELECT policy + initplan-safe auth.uid()
-- ---------------------------------------------------------------------------

drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_select_same_org on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_select_visible
  on public.profiles
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1
      from public.organization_members me
      join public.organization_members other
        on other.organization_id = me.organization_id
      where me.user_id = (select auth.uid())
        and me.status = 'active'
        and other.user_id = profiles.id
        and other.status = 'active'
    )
  );
create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));
-- ---------------------------------------------------------------------------
-- organizations insert: initplan-safe auth.uid()
-- ---------------------------------------------------------------------------

drop policy if exists organizations_insert_authenticated on public.organizations;
create policy organizations_insert_authenticated
  on public.organizations
  for insert
  to authenticated
  with check (
    (select auth.uid()) is not null
    and created_by = (select auth.uid())
  );
-- ---------------------------------------------------------------------------
-- organization_members insert: initplan-safe auth.uid()
-- ---------------------------------------------------------------------------

drop policy if exists members_insert_owner_bootstrap_or_admin
  on public.organization_members;
create policy members_insert_owner_bootstrap_or_admin
  on public.organization_members
  for insert
  to authenticated
  with check (
    (
      user_id = (select auth.uid())
      and role = 'owner'
      and exists (
        select 1
        from public.organizations o
        where o.id = organization_id
          and o.created_by = (select auth.uid())
      )
    )
    or public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  );
-- ---------------------------------------------------------------------------
-- audit_events insert: initplan-safe auth.uid()
-- ---------------------------------------------------------------------------

drop policy if exists audit_events_insert on public.audit_events;
create policy audit_events_insert
  on public.audit_events
  for insert
  to authenticated
  with check (
    actor_user_id = (select auth.uid())
    and (
      organization_id is null
      or public.is_org_member(organization_id)
    )
  );
-- ---------------------------------------------------------------------------
-- Narrow FOR ALL mutate policies → write-only (no overlapping SELECT)
-- Keeps dedicated SELECT policies as the single SELECT path.
-- ---------------------------------------------------------------------------

-- accounting_periods
drop policy if exists accounting_periods_mutate on public.accounting_periods;
create policy accounting_periods_insert
  on public.accounting_periods
  for insert
  to authenticated
  with check (
    public.has_org_role(
      organization_id,
      array['owner', 'admin', 'accountant']::public.member_role[]
    )
  );
create policy accounting_periods_update
  on public.accounting_periods
  for update
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array['owner', 'admin', 'accountant']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array['owner', 'admin', 'accountant']::public.member_role[]
    )
  );
create policy accounting_periods_delete
  on public.accounting_periods
  for delete
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array['owner', 'admin', 'accountant']::public.member_role[]
    )
  );
-- cost_centers
drop policy if exists cost_centers_mutate on public.cost_centers;
create policy cost_centers_insert
  on public.cost_centers
  for insert
  to authenticated
  with check (public.can_mutate_org(organization_id));
create policy cost_centers_update
  on public.cost_centers
  for update
  to authenticated
  using (public.can_mutate_org(organization_id))
  with check (public.can_mutate_org(organization_id));
create policy cost_centers_delete
  on public.cost_centers
  for delete
  to authenticated
  using (public.can_mutate_org(organization_id));
-- organization_features
drop policy if exists organization_features_mutate on public.organization_features;
create policy organization_features_insert
  on public.organization_features
  for insert
  to authenticated
  with check (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  );
create policy organization_features_update
  on public.organization_features
  for update
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  );
create policy organization_features_delete
  on public.organization_features
  for delete
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  );
-- organization_settings
drop policy if exists organization_settings_mutate on public.organization_settings;
create policy organization_settings_insert
  on public.organization_settings
  for insert
  to authenticated
  with check (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  );
create policy organization_settings_update
  on public.organization_settings
  for update
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  )
  with check (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  );
create policy organization_settings_delete
  on public.organization_settings
  for delete
  to authenticated
  using (
    public.has_org_role(
      organization_id,
      array['owner', 'admin']::public.member_role[]
    )
  );
