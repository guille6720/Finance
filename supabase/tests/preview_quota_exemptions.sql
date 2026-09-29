-- Behaviour test for the public-preview tester quota (Staging only).
-- Run in the Supabase SQL editor as postgres. It always ends by raising, so every user,
-- organization and slot it creates is rolled back. Success message:
--   PREVIEW_QUOTA_TEST_PASSED ...
-- Any other exception names the failing scenario.
do $$
declare
  v_max int;
  v_used0 int;
  v_free int;
  v_owner uuid := gen_random_uuid();
  v_qa uuid := gen_random_uuid();
  v_ext uuid[] := array[]::uuid[];
  v_orgs uuid[] := array[]::uuid[];
  v_u uuid;
  v_org uuid;
  v_slots int;
  v_q jsonb;
  v_rejected boolean;
  v_log text := '';
  i int;
begin
  select s.max_testers into v_max from public.preview_demo_settings s where s.id and s.enabled;
  if v_max is null then
    raise exception 'PREVIEW_QUOTA_TEST_SKIPPED preview disabled';
  end if;

  foreach v_u in array array[v_owner, v_qa] loop
    insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
    values (v_u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            v_u::text || '@quota-test.invalid', now(), now());
  end loop;

  execute 'set local role service_role';
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform public.preview_set_quota_exemption(v_owner, 'owner', 'behaviour test');
  perform public.preview_set_quota_exemption(v_qa, 'internal_qa', 'behaviour test');
  v_used0 := (public.preview_tester_quota() ->> 'used')::int;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  v_free := v_max - v_used0;
  v_slots := (select count(*) from public.staging_tester_slots);

  -- owner_no_slot
  insert into public.organizations (legal_name, created_by) values ('Quota test owner', v_owner) returning id into v_org;
  if exists (select 1 from public.staging_tester_slots s where s.user_id = v_owner) then
    raise exception 'FAIL owner_no_slot';
  end if;

  -- internal_qa_no_slot
  insert into public.organizations (legal_name, created_by) values ('Quota test QA', v_qa);
  if exists (select 1 from public.staging_tester_slots s where s.user_id = v_qa) then
    raise exception 'FAIL internal_qa_no_slot';
  end if;

  -- internal_retry_no_slot
  insert into public.organizations (legal_name, created_by) values ('Quota test QA retry', v_qa);
  if (select count(*) from public.staging_tester_slots) <> v_slots then
    raise exception 'FAIL internal_retry_no_slot';
  end if;

  -- external_1_5_accepted
  for i in 1..v_free loop
    v_u := gen_random_uuid();
    insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
    values (v_u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            v_u::text || '@quota-test.invalid', now(), now());
    insert into public.organizations (legal_name, created_by) values ('Quota test external ' || i, v_u)
    returning id into v_org;
    insert into public.organization_members (organization_id, user_id, role, status)
    values (v_org, v_u, 'owner', 'active');
    if not exists (select 1 from public.staging_tester_slots s where s.user_id = v_u and s.organization_id = v_org) then
      raise exception 'FAIL external_1_5_accepted (tester %)', i;
    end if;
    v_ext := v_ext || v_u;
    v_orgs := v_orgs || v_org;
  end loop;
  if (select count(*) from public.staging_tester_slots s
      where not exists (select 1 from public.preview_quota_exemptions e where e.user_id = s.user_id)) <> v_max then
    raise exception 'FAIL external_1_5_accepted (quota not full)';
  end if;

  -- external_6_rejected
  v_u := gen_random_uuid();
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values (v_u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          v_u::text || '@quota-test.invalid', now(), now());
  v_rejected := false;
  begin
    insert into public.organizations (legal_name, created_by) values ('Quota test external over limit', v_u);
  exception when others then
    v_rejected := sqlerrm = 'STAGING_TESTER_LIMIT_REACHED';
  end;
  if not v_rejected or exists (select 1 from public.organizations o where o.created_by = v_u) then
    raise exception 'FAIL external_6_rejected';
  end if;

  -- external_retry_no_new_slot
  v_slots := (select count(*) from public.staging_tester_slots);
  insert into public.organizations (legal_name, created_by) values ('Quota test external retry', v_ext[1]);
  if (select count(*) from public.staging_tester_slots) <> v_slots
     or (select count(*) from public.staging_tester_slots s where s.user_id = v_ext[1]) <> 1 then
    raise exception 'FAIL external_retry_no_new_slot';
  end if;

  -- internal_remark_quota_unchanged / quota_report
  execute 'set local role service_role';
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform public.preview_set_quota_exemption(v_qa, 'e2e', null);
  v_q := public.preview_tester_quota();
  if (v_q ->> 'used')::int <> v_max or (v_q ->> 'max')::int <> v_max then
    raise exception 'FAIL internal_remark_quota_unchanged %', v_q;
  end if;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_ext[1], 'role', 'authenticated')::text, true);
  if public.preview_tester_quota() is not null then
    raise exception 'FAIL quota_report (external tester can read the quota)';
  end if;

  -- tenant_isolation
  if not public.preview_demo_org_eligible(v_orgs[1]) then
    raise exception 'FAIL tenant_isolation (own organization not eligible)';
  end if;
  if v_free >= 2 and public.preview_demo_org_eligible(v_orgs[2]) then
    raise exception 'FAIL tenant_isolation (other tester organization eligible)';
  end if;
  if v_free >= 2 then
    v_rejected := false;
    begin
      perform public.seed_preview_demo_data(v_orgs[2]);
    exception when others then
      v_rejected := sqlerrm = 'PREVIEW_DEMO_NOT_ALLOWED';
    end;
    if not v_rejected then
      raise exception 'FAIL tenant_isolation (seeded another tester organization)';
    end if;
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_qa, 'role', 'authenticated')::text, true);
  if public.preview_tester_quota() is null then
    raise exception 'FAIL quota_report (internal account cannot read the quota)';
  end if;
  if public.preview_demo_org_eligible(v_orgs[1]) then
    raise exception 'FAIL tenant_isolation (exempt account eligible on a tester organization)';
  end if;
  execute 'reset role';

  v_log := 'max=' || v_max || ' external_before=' || v_used0 || ' accepted=' || v_free
    || ' sixth_rejected=true retry_slots=1 internal_slots=0';
  raise exception 'PREVIEW_QUOTA_TEST_PASSED %', v_log;
end;
$$;
