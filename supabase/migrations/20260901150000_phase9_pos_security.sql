-- Phase 9: RLS, grants, feature enable Demo QA, revoke internal helpers

alter table public.pos_settings enable row level security;
alter table public.pos_terminals enable row level security;
alter table public.pos_sessions enable row level security;
alter table public.pos_sales enable row level security;
alter table public.pos_tenders enable row level security;
alter table public.pos_terminal_tender_accounts enable row level security;
-- SELECT
drop policy if exists pos_settings_select on public.pos_settings;
create policy pos_settings_select on public.pos_settings for select to authenticated
  using (public.is_org_member(organization_id));
drop policy if exists pos_terminals_select on public.pos_terminals;
create policy pos_terminals_select on public.pos_terminals for select to authenticated
  using (public.is_org_member(organization_id));
drop policy if exists pos_sessions_select on public.pos_sessions;
create policy pos_sessions_select on public.pos_sessions for select to authenticated
  using (public.is_org_member(organization_id));
drop policy if exists pos_sales_select on public.pos_sales;
create policy pos_sales_select on public.pos_sales for select to authenticated
  using (public.is_org_member(organization_id));
drop policy if exists pos_tenders_select on public.pos_tenders;
create policy pos_tenders_select on public.pos_tenders for select to authenticated
  using (public.is_org_member(organization_id));
drop policy if exists pos_tta_select on public.pos_terminal_tender_accounts;
create policy pos_tta_select on public.pos_terminal_tender_accounts for select to authenticated
  using (public.is_org_member(organization_id));
-- Config writes (settings / terminals / tender accounts)
drop policy if exists pos_settings_insert on public.pos_settings;
create policy pos_settings_insert on public.pos_settings for insert to authenticated
  with check (public.has_org_role(organization_id, array['owner','admin','accountant','manager']::public.member_role[]));
drop policy if exists pos_settings_update on public.pos_settings;
create policy pos_settings_update on public.pos_settings for update to authenticated
  using (public.has_org_role(organization_id, array['owner','admin','accountant','manager']::public.member_role[]))
  with check (public.has_org_role(organization_id, array['owner','admin','accountant','manager']::public.member_role[]));
drop policy if exists pos_terminals_insert on public.pos_terminals;
create policy pos_terminals_insert on public.pos_terminals for insert to authenticated
  with check (public.has_org_role(organization_id, array['owner','admin','manager']::public.member_role[]));
drop policy if exists pos_terminals_update on public.pos_terminals;
create policy pos_terminals_update on public.pos_terminals for update to authenticated
  using (public.has_org_role(organization_id, array['owner','admin','manager']::public.member_role[]))
  with check (public.has_org_role(organization_id, array['owner','admin','manager']::public.member_role[]));
drop policy if exists pos_tta_insert on public.pos_terminal_tender_accounts;
create policy pos_tta_insert on public.pos_terminal_tender_accounts for insert to authenticated
  with check (public.has_org_role(organization_id, array['owner','admin','manager','accountant']::public.member_role[]));
drop policy if exists pos_tta_update on public.pos_terminal_tender_accounts;
create policy pos_tta_update on public.pos_terminal_tender_accounts for update to authenticated
  using (public.has_org_role(organization_id, array['owner','admin','manager','accountant']::public.member_role[]))
  with check (public.has_org_role(organization_id, array['owner','admin','manager','accountant']::public.member_role[]));
drop policy if exists pos_tta_delete on public.pos_terminal_tender_accounts;
create policy pos_tta_delete on public.pos_terminal_tender_accounts for delete to authenticated
  using (public.has_org_role(organization_id, array['owner','admin','manager']::public.member_role[]));
-- Cart lines tenders: insert/update/delete DRAFT via client before checkout
drop policy if exists pos_tenders_insert on public.pos_tenders;
create policy pos_tenders_insert on public.pos_tenders for insert to authenticated
  with check (
    public.has_org_role(organization_id, array['owner','admin','manager','operator']::public.member_role[])
    and status = 'DRAFT'
    and treasury_operation_id is null
  );
drop policy if exists pos_tenders_update on public.pos_tenders;
create policy pos_tenders_update on public.pos_tenders for update to authenticated
  using (
    public.has_org_role(organization_id, array['owner','admin','manager','operator']::public.member_role[])
    and status = 'DRAFT'
  )
  with check (
    public.has_org_role(organization_id, array['owner','admin','manager','operator']::public.member_role[])
    and status = 'DRAFT'
    and treasury_operation_id is null
  );
drop policy if exists pos_tenders_delete on public.pos_tenders;
create policy pos_tenders_delete on public.pos_tenders for delete to authenticated
  using (
    public.has_org_role(organization_id, array['owner','admin','manager','operator']::public.member_role[])
    and status = 'DRAFT'
  );
-- Sessions/sales: no direct client INSERT/UPDATE (RPCs only)
-- (SELECT already granted)

grant select on public.pos_settings to authenticated;
grant select, insert, update on public.pos_terminals to authenticated;
grant select on public.pos_sessions to authenticated;
grant select on public.pos_sales to authenticated;
grant select, insert, update, delete on public.pos_tenders to authenticated;
grant select, insert, update, delete on public.pos_terminal_tender_accounts to authenticated;
grant select, insert, update on public.pos_settings to authenticated;
revoke all on public.pos_settings from anon;
revoke all on public.pos_terminals from anon;
revoke all on public.pos_sessions from anon;
revoke all on public.pos_sales from anon;
revoke all on public.pos_tenders from anon;
revoke all on public.pos_terminal_tender_accounts from anon;
-- Internal helpers: no client EXECUTE
revoke all on function public.pos_assert_feature(uuid) from public, anon, authenticated;
revoke all on function public.pos_assert_feature_code(uuid, text) from public, anon, authenticated;
revoke all on function public.pos_validate_walk_in_customer(uuid, uuid) from public, anon, authenticated;
revoke all on function public.pos_validate_tender_account(uuid, uuid, public.pos_tender_method, uuid)
  from public, anon, authenticated;
-- Enable pos (+ typical deps) for Demo QA orgs
insert into public.organization_features (organization_id, feature_id, status, enabled_at)
select o.id, fc.id, 'enabled', timezone('utc', now())
from public.organizations o
cross join public.feature_catalog fc
where fc.code in ('pos', 'sales', 'cash', 'banks', 'inventory', 'fiscal_invoicing', 'accounting')
  and (
    o.legal_name ilike '%demo%'
    or o.commercial_name ilike '%demo%'
    or o.legal_name ilike '%qa%'
  )
on conflict (organization_id, feature_id) do update
set status = 'enabled',
    enabled_at = coalesce(public.organization_features.enabled_at, excluded.enabled_at);
