-- Phase 11: saved_reports (org-scoped named report configs)
-- Filters/columns/sort are allowlisted JSON only — never SQL fragments.

do $$ begin
  create type public.saved_report_visibility as enum ('PRIVATE', 'ORGANIZATION');
exception when duplicate_object then null;
end $$;
create table if not exists public.saved_reports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  owner_user_id uuid not null references auth.users (id) on delete cascade,
  report_code text not null check (char_length(trim(report_code)) >= 2),
  name text not null check (char_length(trim(name)) between 1 and 120),
  filters_json jsonb not null default '{}'::jsonb,
  columns_json jsonb not null default '[]'::jsonb,
  sort_json jsonb not null default '[]'::jsonb,
  visibility public.saved_report_visibility not null default 'PRIVATE',
  calculation_version int not null default 1 check (calculation_version >= 1),
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint saved_reports_org_id_unique unique (organization_id, id),
  constraint saved_reports_org_owner_name_unique unique (organization_id, owner_user_id, name)
);
create index if not exists saved_reports_org_idx
  on public.saved_reports (organization_id, active);
create index if not exists saved_reports_owner_idx
  on public.saved_reports (owner_user_id);
create index if not exists saved_reports_org_report_code_idx
  on public.saved_reports (organization_id, report_code);
create index if not exists saved_reports_org_owner_idx
  on public.saved_reports (organization_id, owner_user_id);
drop trigger if exists saved_reports_set_updated_at on public.saved_reports;
create trigger saved_reports_set_updated_at
before update on public.saved_reports
for each row execute function public.set_updated_at();
comment on table public.saved_reports is
  'Named filter/column/sort configs against approved report_code. No user SQL.';
alter table public.saved_reports enable row level security;
-- PRIVATE: owner only; ORGANIZATION: same-org members
drop policy if exists saved_reports_select on public.saved_reports;
create policy saved_reports_select on public.saved_reports
  for select to authenticated
  using (
    public.is_org_member(organization_id)
    and (
      visibility = 'ORGANIZATION'
      or owner_user_id = auth.uid()
    )
  );
drop policy if exists saved_reports_insert on public.saved_reports;
create policy saved_reports_insert on public.saved_reports
  for insert to authenticated
  with check (
    public.is_org_member(organization_id)
    and owner_user_id = auth.uid()
  );
drop policy if exists saved_reports_update on public.saved_reports;
create policy saved_reports_update on public.saved_reports
  for update to authenticated
  using (owner_user_id = auth.uid() and public.is_org_member(organization_id))
  with check (owner_user_id = auth.uid() and public.is_org_member(organization_id));
drop policy if exists saved_reports_delete on public.saved_reports;
create policy saved_reports_delete on public.saved_reports
  for delete to authenticated
  using (owner_user_id = auth.uid() and public.is_org_member(organization_id));
revoke all on table public.saved_reports from public, anon;
grant select, insert, update, delete on table public.saved_reports to authenticated;
grant all on table public.saved_reports to service_role;
