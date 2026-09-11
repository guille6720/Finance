-- Phase 1 security hardening (STAGING)
-- Project: rpcpdrzbcclofvjpgldb
-- Does not rewrite 20260329000001; additive hardening only.
--
-- Findings addressed:
-- 1) function_search_path_mutable on set_updated_at / prevent_audit_mutation
-- 2) anon EXECUTE on SECURITY DEFINER helpers (default PUBLIC/anon grants)
-- 3) handle_new_user exposed as callable RPC
--
-- Design notes:
-- * RLS helpers remain SECURITY DEFINER to avoid recursive RLS on
--   organization_members while evaluating membership/role checks.
-- * Identity source is only auth.uid() — no trusted user_id argument.
-- * authenticated EXECUTE on helpers is required so RLS policy expressions
--   can invoke them at runtime. Direct PostgREST RPC is possible but safe
--   because helpers only return boolean based on auth.uid() + org_id.

-- ---------------------------------------------------------------------------
-- Trigger helpers: pin search_path, revoke API exposure
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;
create or replace function public.prevent_audit_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'audit_events is append-only';
end;
$$;
revoke all on function public.set_updated_at() from public;
revoke all on function public.set_updated_at() from anon;
revoke all on function public.set_updated_at() from authenticated;
revoke all on function public.prevent_audit_mutation() from public;
revoke all on function public.prevent_audit_mutation() from anon;
revoke all on function public.prevent_audit_mutation() from authenticated;
-- ---------------------------------------------------------------------------
-- Auth trigger: keep SECURITY DEFINER, pin search_path, hide from RPC
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public;
revoke all on function public.handle_new_user() from anon;
revoke all on function public.handle_new_user() from authenticated;
-- Trigger owner (postgres/supabase_admin) retains EXECUTE via ownership.

-- ---------------------------------------------------------------------------
-- RLS helpers: SECURITY DEFINER + empty search_path + no anon EXECUTE
-- ---------------------------------------------------------------------------

create or replace function public.is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_members m
    where m.organization_id = p_org_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  );
$$;
create or replace function public.has_org_role(
  p_org_id uuid,
  p_roles public.member_role[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_members m
    where m.organization_id = p_org_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role = any (p_roles)
  );
$$;
create or replace function public.can_mutate_org(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_org_role(
    p_org_id,
    array['owner', 'admin', 'manager']::public.member_role[]
  );
$$;
revoke all on function public.is_org_member(uuid) from public;
revoke all on function public.is_org_member(uuid) from anon;
revoke all on function public.is_org_member(uuid) from authenticated;
revoke all on function public.has_org_role(uuid, public.member_role[]) from public;
revoke all on function public.has_org_role(uuid, public.member_role[]) from anon;
revoke all on function public.has_org_role(uuid, public.member_role[]) from authenticated;
revoke all on function public.can_mutate_org(uuid) from public;
revoke all on function public.can_mutate_org(uuid) from anon;
revoke all on function public.can_mutate_org(uuid) from authenticated;
-- Required for RLS policy evaluation under the authenticated role.
grant execute on function public.is_org_member(uuid) to authenticated;
grant execute on function public.has_org_role(uuid, public.member_role[]) to authenticated;
grant execute on function public.can_mutate_org(uuid) to authenticated;
-- Explicitly ensure anon cannot execute any of the above.
revoke execute on function public.is_org_member(uuid) from anon;
revoke execute on function public.has_org_role(uuid, public.member_role[]) from anon;
revoke execute on function public.can_mutate_org(uuid) from anon;
revoke execute on function public.handle_new_user() from anon;
revoke execute on function public.set_updated_at() from anon;
revoke execute on function public.prevent_audit_mutation() from anon;
