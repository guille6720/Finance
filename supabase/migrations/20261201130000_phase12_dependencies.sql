-- Phase 12.4 — Feature dependencies (DAG; platform-only writes)

do $$ begin
  create type public.feature_dependency_kind as enum (
    'HARD',
    'RECOMMENDED',
    'CONDITIONAL'
  );
exception when duplicate_object then null;
end $$;
create table if not exists public.feature_dependencies (
  id uuid primary key default gen_random_uuid(),
  feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  required_feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  dependency_kind public.feature_dependency_kind not null,
  condition_code text,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint feature_dependencies_no_self check (feature_id <> required_feature_id),
  constraint feature_dependencies_condition_ck check (
    (dependency_kind = 'CONDITIONAL' and condition_code is not null and length(btrim(condition_code)) > 0)
    or (dependency_kind <> 'CONDITIONAL' and condition_code is null)
  )
);
create unique index if not exists feature_dependencies_pair_uidx
  on public.feature_dependencies (
    feature_id,
    required_feature_id,
    dependency_kind,
    coalesce(condition_code, '')
  );
create index if not exists feature_dependencies_required_idx
  on public.feature_dependencies (required_feature_id)
  where active;
create index if not exists feature_dependencies_feature_idx
  on public.feature_dependencies (feature_id)
  where active;
create trigger feature_dependencies_set_updated_at
before update on public.feature_dependencies
for each row execute function public.set_updated_at();
-- Cycle detection for HARD edges only (enforced on write)
create or replace function public.feature_dependencies_assert_dag()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_cycle boolean;
begin
  if new.dependency_kind is distinct from 'HARD'::public.feature_dependency_kind then
    return new;
  end if;
  if not coalesce(new.active, true) then
    return new;
  end if;

  with recursive walk as (
    select new.required_feature_id as fid, 1 as depth
    union all
    select d.required_feature_id, w.depth + 1
    from walk w
    join public.feature_dependencies d
      on d.feature_id = w.fid
     and d.active
     and d.dependency_kind = 'HARD'::public.feature_dependency_kind
    where w.depth < 32
  )
  select exists (select 1 from walk where fid = new.feature_id) into v_cycle;

  if v_cycle then
    raise exception 'FEATURE_DEPENDENCY_CYCLE';
  end if;
  return new;
end;
$$;
drop trigger if exists feature_dependencies_dag_trg on public.feature_dependencies;
create trigger feature_dependencies_dag_trg
before insert or update on public.feature_dependencies
for each row execute function public.feature_dependencies_assert_dag();
alter table public.feature_dependencies enable row level security;
drop policy if exists feature_dependencies_select on public.feature_dependencies;
create policy feature_dependencies_select
  on public.feature_dependencies for select to authenticated
  using (active = true);
revoke all on table public.feature_dependencies from public, anon;
grant select on table public.feature_dependencies to authenticated;
grant all on table public.feature_dependencies to service_role;
-- Proven HARD seeds only
insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, 'HARD'::public.feature_dependency_kind, null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = 'sales'
where f.code = 'pos'
on conflict do nothing;
insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, 'HARD', null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = 'sales'
where f.code = 'fiscal_invoicing'
on conflict do nothing;
insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, 'HARD', null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = 'customers'
where f.code = 'sales'
on conflict do nothing;
insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, 'HARD', null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = 'suppliers'
where f.code = 'purchases'
on conflict do nothing;
-- RECOMMENDED (non-blocking)
insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, 'RECOMMENDED', null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = 'inventory'
where f.code = 'pos'
on conflict do nothing;
insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, 'RECOMMENDED', null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = 'fiscal_invoicing'
where f.code = 'pos'
on conflict do nothing;
insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, 'RECOMMENDED', null, true
from public.feature_catalog f
join public.feature_catalog r on r.code = 'cash'
where f.code = 'pos'
on conflict do nothing;
-- CONDITIONAL documented codes (engine may surface; runtime POS remains source of truth)
insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, 'CONDITIONAL', 'POS_HAS_STOCK_LINES', true
from public.feature_catalog f
join public.feature_catalog r on r.code = 'inventory'
where f.code = 'pos'
on conflict do nothing;
insert into public.feature_dependencies (feature_id, required_feature_id, dependency_kind, condition_code, active)
select f.id, r.id, 'CONDITIONAL', 'POS_FISCAL_HANDOFF', true
from public.feature_catalog f
join public.feature_catalog r on r.code = 'fiscal_invoicing'
where f.code = 'pos'
on conflict do nothing;
comment on table public.feature_dependencies is
  'Platform dependency graph. HARD is a DAG. No accounting HARD unless separately approved.';
