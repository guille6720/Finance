-- Phase 12.7 — Before snapshot + entitlement/preference backfill + verify
-- INTENTIONAL CAPABILITY NARROWING: disabled optional rows do NOT receive GRANTED.

create table if not exists public.phase12_migration_effective_snapshot (
  organization_id uuid not null,
  feature_id uuid not null,
  feature_code text not null,
  row_exists boolean not null,
  effective_status text not null,
  snapshotted_at timestamptz not null default timezone('utc', now()),
  primary key (organization_id, feature_id)
);
revoke all on table public.phase12_migration_effective_snapshot from public, anon, authenticated;
grant all on table public.phase12_migration_effective_snapshot to service_role;
-- Snapshot EVERY org × active catalog feature (missing row = disabled)
insert into public.phase12_migration_effective_snapshot (
  organization_id, feature_id, feature_code, row_exists, effective_status
)
select
  o.id,
  c.id,
  c.code,
  (ofe.id is not null),
  case
    when ofe.id is null then 'disabled'
    else ofe.status::text
  end
from public.organizations o
cross join public.feature_catalog c
left join public.organization_features ofe
  on ofe.organization_id = o.id and ofe.feature_id = c.id
where c.active
on conflict do nothing;
-- Backfill entitlements + preferences from snapshot rules
do $$
declare
  r record;
  v_ent public.feature_entitlement_status;
  v_src public.feature_entitlement_source;
  v_meta jsonb;
  v_pref boolean;
  v_grant boolean;
begin
  for r in
    select s.*, rc.mandatory_core_policy, rc.release_status
    from public.phase12_migration_effective_snapshot s
    left join public.feature_release_controls rc on rc.feature_id = s.feature_id
  loop
    v_grant := false;
    v_pref := false;
    v_ent := 'REVOKED'::public.feature_entitlement_status;
    v_src := 'MIGRATION'::public.feature_entitlement_source;
    v_meta := '{}'::jsonb;

    if r.effective_status = 'enabled' then
      v_grant := true;
      v_ent := 'GRANTED';
      v_pref := true;
      v_meta := jsonb_build_object('migration', 'enabled');
    elsif r.effective_status = 'restricted' then
      v_grant := true;
      v_ent := 'RESTRICTED';
      v_pref := false;
      v_meta := jsonb_build_object('migration', 'restricted');
    elsif r.feature_code = 'dashboard' then
      -- mandatory core always entitled
      v_grant := true;
      v_ent := 'GRANTED';
      v_src := 'SYSTEM';
      v_pref := true;
      v_meta := jsonb_build_object('migration', 'dashboard_core');
    elsif r.feature_code = 'accounting' and r.effective_status = 'disabled' then
      -- LEGACY_CORE_EXEMPTION: entitled but preference off; effective stays disabled
      v_grant := true;
      v_ent := 'GRANTED';
      v_src := 'SYSTEM';
      v_pref := false;
      v_meta := jsonb_build_object(
        'migration', 'accounting_legacy',
        'legacy_core_exemption', true
      );
    elsif r.feature_code = 'medical_legal' then
      v_grant := true;
      v_ent := 'RESTRICTED';
      v_pref := false;
      v_meta := jsonb_build_object('migration', 'medical_legal');
    else
      -- DISABLED optional / coming-soon: NO GRANTED (capability narrowing)
      v_grant := false;
      v_pref := false;
    end if;

    if v_grant then
      insert into public.organization_feature_entitlements (
        organization_id, feature_id, status, source_type, metadata, granted_at
      ) values (
        r.organization_id, r.feature_id, v_ent, v_src, v_meta,
        case when v_ent = 'GRANTED' then timezone('utc', now()) else null end
      )
      on conflict (organization_id, feature_id) do update set
        status = excluded.status,
        source_type = excluded.source_type,
        metadata = excluded.metadata,
        updated_at = timezone('utc', now());
    end if;

    insert into public.organization_feature_preferences (
      organization_id, feature_id, desired_enabled
    ) values (
      r.organization_id, r.feature_id, v_pref
    )
    on conflict (organization_id, feature_id) do update set
      desired_enabled = excluded.desired_enabled,
      updated_at = timezone('utc', now());
  end loop;
end $$;
-- Quiet recompute all orgs (preserve effective; fill missing rows)
do $$
declare
  v_org uuid;
begin
  perform set_config('modules.migration_quiet', '1', true);
  perform set_config('modules.migration_skip_hard_deps', '1', true);
  for v_org in select id from public.organizations order by created_at loop
    perform public.recompute_organization_features(v_org, null, 'phase12_migration');
  end loop;
  perform set_config('modules.migration_skip_hard_deps', '', true);
  perform set_config('modules.migration_quiet', '', true);
end $$;
-- Verification table
create table if not exists public.phase12_migration_effective_diff (
  organization_id uuid not null,
  feature_code text not null,
  old_effective_status text not null,
  new_effective_status text not null,
  primary key (organization_id, feature_code)
);
revoke all on table public.phase12_migration_effective_diff from public, anon, authenticated;
grant all on table public.phase12_migration_effective_diff to service_role;
truncate public.phase12_migration_effective_diff;
insert into public.phase12_migration_effective_diff (
  organization_id, feature_code, old_effective_status, new_effective_status
)
select
  s.organization_id,
  s.feature_code,
  s.effective_status,
  case
    when ofe.id is null then 'disabled'
    else ofe.status::text
  end
from public.phase12_migration_effective_snapshot s
left join public.organization_features ofe
  on ofe.organization_id = s.organization_id and ofe.feature_id = s.feature_id
where s.effective_status is distinct from case
  when ofe.id is null then 'disabled'
  else ofe.status::text
end;
do $$
declare
  v_n int;
begin
  select count(*)::int into v_n from public.phase12_migration_effective_diff;
  if v_n > 0 then
    raise exception 'PHASE12_UNEXPECTED_EFFECTIVE_DIFFS count=% — STOP migration', v_n;
  end if;
  raise notice 'PHASE12 migration verify: unexpected_effective_diff_count=0';
end $$;
