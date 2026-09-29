-- Public preview: only external testers consume the 5 tester slots.
--
-- Owner, internal and QA/E2E accounts are marked explicitly in
-- public.preview_quota_exemptions, a table only the platform (service_role) can write.
-- Exempt users never take a slot; marking a user exempt releases any slot they held.
-- Exemptions are never derived from company names, email addresses or user_metadata.

create table if not exists public.preview_quota_exemptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reason text not null check (reason in ('owner', 'internal', 'internal_qa', 'e2e')),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.preview_quota_exemptions enable row level security;
revoke all on table public.preview_quota_exemptions from public, anon, authenticated;
grant all on table public.preview_quota_exemptions to service_role;

create or replace function public.preview_is_quota_exempt(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.preview_quota_exemptions e where e.user_id = p_user_id);
$$;

revoke all on function public.preview_is_quota_exempt(uuid) from public, anon, authenticated;
grant execute on function public.preview_is_quota_exempt(uuid) to service_role;

-- Platform-only: mark (or re-mark) an account as exempt and release its tester slot.
-- Serialized with slot allocation through the same advisory lock.
create or replace function public.preview_set_quota_exemption(
  p_user_id uuid,
  p_reason text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform public.modules_assert_service_role();
  perform pg_advisory_xact_lock(hashtext('finance_staging_public_tester_slots_v1'));

  insert into public.preview_quota_exemptions (user_id, reason, note)
  values (p_user_id, p_reason, p_note)
  on conflict (user_id) do update
    set reason = excluded.reason,
        note = coalesce(excluded.note, public.preview_quota_exemptions.note),
        updated_at = now();

  delete from public.staging_tester_slots s where s.user_id = p_user_id;
end;
$function$;

revoke all on function public.preview_set_quota_exemption(uuid, text, text) from public, anon, authenticated;
grant execute on function public.preview_set_quota_exemption(uuid, text, text) to service_role;

-- Slot reservation: exempt accounts are skipped before any slot is considered.
create or replace function public.staging_reserve_tester_and_seed()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $function$
declare
  v_settings public.preview_demo_settings%rowtype;
  v_user_created_at timestamptz;
  v_slot smallint;
begin
  select * into v_settings from public.preview_demo_settings s where s.id;
  if not found or not v_settings.enabled or new.created_by is null then
    return new;
  end if;

  select u.created_at into v_user_created_at from auth.users u where u.id = new.created_by;
  if v_user_created_at is null or v_user_created_at < v_settings.enabled_since then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext('finance_staging_public_tester_slots_v1'));

  if exists (select 1 from public.preview_quota_exemptions e where e.user_id = new.created_by) then
    return new;
  end if;

  if exists (select 1 from public.staging_tester_slots s where s.user_id = new.created_by) then
    return new;
  end if;

  select gs::smallint
    into v_slot
  from generate_series(1, v_settings.max_testers) gs
  where not exists (select 1 from public.staging_tester_slots s where s.slot_no = gs)
  order by gs
  limit 1;

  if v_slot is null then
    raise exception using
      errcode = 'P0001',
      message = 'STAGING_TESTER_LIMIT_REACHED',
      detail = 'Public preview is limited to ' || v_settings.max_testers || ' external tester accounts.';
  end if;

  insert into public.staging_tester_slots (slot_no, user_id, organization_id)
  values (v_slot, new.created_by, new.id);

  return new;
end;
$function$;

revoke all on function public.staging_reserve_tester_and_seed() from public, anon, authenticated;

-- Demo data: organizations of external testers (slot) or created by an exempt account.
create or replace function public.preview_demo_org_eligible(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.preview_demo_enabled()
    and (
      exists (
        select 1 from public.staging_tester_slots s where s.organization_id = p_organization_id
      )
      or exists (
        select 1
        from public.organizations o
        join public.preview_quota_exemptions e on e.user_id = o.created_by
        where o.id = p_organization_id
      )
    )
    and not exists (
      select 1 from public.organization_settings os
      where os.organization_id = p_organization_id and os.key = 'demo.is_demo'
    )
    and public.has_org_role(p_organization_id, array['owner']::public.member_role[]);
$$;

revoke all on function public.preview_demo_org_eligible(uuid) from public, anon;
grant execute on function public.preview_demo_org_eligible(uuid) to authenticated, service_role;

-- Quota report, readable only by exempt (internal) accounts and the platform.
create or replace function public.preview_tester_quota()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.role() is distinct from 'service_role'
     and not public.preview_is_quota_exempt(auth.uid()) then
    return null;
  end if;

  return jsonb_build_object(
    'enabled', public.preview_demo_enabled(),
    'used', (
      select count(*)
      from public.staging_tester_slots s
      where not exists (select 1 from public.preview_quota_exemptions e where e.user_id = s.user_id)
    ),
    'max', coalesce((select s.max_testers from public.preview_demo_settings s where s.id), 5)
  );
end;
$function$;

revoke all on function public.preview_tester_quota() from public, anon;
grant execute on function public.preview_tester_quota() to authenticated, service_role;
