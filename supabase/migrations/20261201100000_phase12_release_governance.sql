-- Phase 12.1 — Release governance (STAGING seeds for rpcpdrzbcclofvjpgldb)
-- Deployment-trusted: this DB is STAGING; seeds reflect STAGING release policy.
-- Do NOT trust client-supplied environment parameters.

do $$ begin
  create type public.feature_release_status as enum (
    'AVAILABLE',
    'PREVIEW',
    'COMING_SOON',
    'RESTRICTED',
    'BLOCKED',
    'RETIRED'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.feature_mandatory_core_policy as enum (
    'NONE',
    'ALWAYS',
    'NEW_ORGS_ONLY'
  );
exception when duplicate_object then null;
end $$;
create table if not exists public.feature_release_controls (
  id uuid primary key default gen_random_uuid(),
  feature_id uuid not null references public.feature_catalog (id) on delete cascade,
  release_status public.feature_release_status not null,
  self_service_allowed boolean not null default false,
  mandatory_core_policy public.feature_mandatory_core_policy not null default 'NONE',
  requires_legal_review boolean not null default false,
  requires_professional_review boolean not null default false,
  notes text,
  updated_at timestamptz not null default timezone('utc', now()),
  updated_by uuid references auth.users (id),
  constraint feature_release_controls_feature_uidx unique (feature_id)
);
create index if not exists feature_release_controls_status_idx
  on public.feature_release_controls (release_status);
create index if not exists feature_release_controls_updated_by_idx
  on public.feature_release_controls (updated_by)
  where updated_by is not null;
create trigger feature_release_controls_set_updated_at
before update on public.feature_release_controls
for each row execute function public.set_updated_at();
alter table public.feature_release_controls enable row level security;
drop policy if exists feature_release_controls_select on public.feature_release_controls;
create policy feature_release_controls_select
  on public.feature_release_controls for select to authenticated
  using (true);
revoke all on table public.feature_release_controls from public, anon;
grant select on table public.feature_release_controls to authenticated;
grant all on table public.feature_release_controls to service_role;
-- STAGING release seeds
insert into public.feature_release_controls (
  feature_id, release_status, self_service_allowed, mandatory_core_policy,
  requires_legal_review, requires_professional_review, notes
)
select c.id, v.release_status, v.self_service, v.core_policy, v.legal, v.prof, v.notes
from public.feature_catalog c
join (
  values
    ('dashboard', 'AVAILABLE'::public.feature_release_status, false, 'ALWAYS'::public.feature_mandatory_core_policy, false, false, 'Mandatory core'),
    ('accounting', 'AVAILABLE', false, 'NEW_ORGS_ONLY', false, false, 'Mandatory for new orgs; legacy exemption allowed'),
    ('customers', 'AVAILABLE', true, 'NONE', false, false, null),
    ('suppliers', 'AVAILABLE', true, 'NONE', false, false, null),
    ('sales', 'AVAILABLE', true, 'NONE', false, false, null),
    ('purchases', 'AVAILABLE', true, 'NONE', false, false, null),
    ('cash', 'AVAILABLE', true, 'NONE', false, false, null),
    ('banks', 'AVAILABLE', true, 'NONE', false, false, null),
    ('inventory', 'AVAILABLE', true, 'NONE', false, false, null),
    ('pos', 'AVAILABLE', true, 'NONE', false, false, null),
    ('reports', 'AVAILABLE', true, 'NONE', false, false, null),
    ('taxes', 'PREVIEW', true, 'NONE', true, true, 'Phase 10 technical; professional/legal review required'),
    ('fiscal_invoicing', 'PREVIEW', true, 'NONE', true, false, 'STAGING preview; PRODUCTION must be BLOCKED until Phase 5 live gate'),
    ('medical_legal', 'RESTRICTED', false, 'NONE', true, true, 'Regulated vertical — no self-service'),
    ('assets', 'COMING_SOON', false, 'NONE', false, false, 'Not implemented'),
    ('projects', 'COMING_SOON', false, 'NONE', false, false, 'Not implemented'),
    ('payroll', 'COMING_SOON', false, 'NONE', false, false, 'Not implemented')
) as v(code, release_status, self_service, core_policy, legal, prof, notes)
  on c.code = v.code
on conflict (feature_id) do update set
  release_status = excluded.release_status,
  self_service_allowed = excluded.self_service_allowed,
  mandatory_core_policy = excluded.mandatory_core_policy,
  requires_legal_review = excluded.requires_legal_review,
  requires_professional_review = excluded.requires_professional_review,
  notes = excluded.notes,
  updated_at = timezone('utc', now());
comment on table public.feature_release_controls is
  'PLATFORM GOVERNANCE. STAGING DB seeds = staging policy. Never trust client environment params.';
