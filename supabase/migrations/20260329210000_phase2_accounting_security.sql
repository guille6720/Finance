-- Phase 2 — Accounting RLS + EXECUTE hardening (STAGING)
-- Project: rpcpdrzbcclofvjpgldb

-- ---------------------------------------------------------------------------
-- Enable RLS
-- ---------------------------------------------------------------------------

alter table public.accounting_fiscal_years enable row level security;
alter table public.accounts enable row level security;
alter table public.accounting_sequences enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_entry_lines enable row level security;
-- ---------------------------------------------------------------------------
-- accounting_fiscal_years
-- ---------------------------------------------------------------------------

drop policy if exists accounting_fiscal_years_select on public.accounting_fiscal_years;
create policy accounting_fiscal_years_select
  on public.accounting_fiscal_years for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists accounting_fiscal_years_insert on public.accounting_fiscal_years;
create policy accounting_fiscal_years_insert
  on public.accounting_fiscal_years for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
drop policy if exists accounting_fiscal_years_update on public.accounting_fiscal_years;
create policy accounting_fiscal_years_update
  on public.accounting_fiscal_years for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
drop policy if exists accounting_fiscal_years_delete on public.accounting_fiscal_years;
create policy accounting_fiscal_years_delete
  on public.accounting_fiscal_years for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- accounts
-- ---------------------------------------------------------------------------

drop policy if exists accounts_select on public.accounts;
create policy accounts_select
  on public.accounts for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists accounts_insert on public.accounts;
create policy accounts_insert
  on public.accounts for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
drop policy if exists accounts_update on public.accounts;
create policy accounts_update
  on public.accounts for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
drop policy if exists accounts_delete on public.accounts;
create policy accounts_delete
  on public.accounts for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- accounting_sequences — no direct client writes; engines use SECURITY DEFINER
-- ---------------------------------------------------------------------------

drop policy if exists accounting_sequences_select on public.accounting_sequences;
create policy accounting_sequences_select
  on public.accounting_sequences for select to authenticated
  using ((select public.is_org_member(organization_id)));
-- No insert/update/delete policies for authenticated (engine bypasses RLS as definer)

-- ---------------------------------------------------------------------------
-- journal_entries
-- ---------------------------------------------------------------------------

drop policy if exists journal_entries_select on public.journal_entries;
create policy journal_entries_select
  on public.journal_entries for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists journal_entries_insert on public.journal_entries;
create policy journal_entries_insert
  on public.journal_entries for insert to authenticated
  with check (
    (select public.has_org_role(
      organization_id, array['owner','admin','accountant','manager']::public.member_role[]
    ))
    and created_by = (select auth.uid())
    and status = 'DRAFT'
  );
drop policy if exists journal_entries_update on public.journal_entries;
create policy journal_entries_update
  on public.journal_entries for update to authenticated
  using (
    status = 'DRAFT'
    and (select public.has_org_role(
      organization_id, array['owner','admin','accountant','manager']::public.member_role[]
    ))
  )
  with check (
    status = 'DRAFT'
    and (select public.has_org_role(
      organization_id, array['owner','admin','accountant','manager']::public.member_role[]
    ))
  );
drop policy if exists journal_entries_delete on public.journal_entries;
create policy journal_entries_delete
  on public.journal_entries for delete to authenticated
  using (
    status = 'DRAFT'
    and (select public.has_org_role(
      organization_id, array['owner','admin','accountant']::public.member_role[]
    ))
  );
-- ---------------------------------------------------------------------------
-- journal_entry_lines
-- ---------------------------------------------------------------------------

drop policy if exists journal_entry_lines_select on public.journal_entry_lines;
create policy journal_entry_lines_select
  on public.journal_entry_lines for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists journal_entry_lines_insert on public.journal_entry_lines;
create policy journal_entry_lines_insert
  on public.journal_entry_lines for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant','manager']::public.member_role[]
  )));
drop policy if exists journal_entry_lines_update on public.journal_entry_lines;
create policy journal_entry_lines_update
  on public.journal_entry_lines for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant','manager']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant','manager']::public.member_role[]
  )));
drop policy if exists journal_entry_lines_delete on public.journal_entry_lines;
create policy journal_entry_lines_delete
  on public.journal_entry_lines for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant','manager']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- Cost centers: allow accountant to manage (Phase 2 alignment)
-- ---------------------------------------------------------------------------

drop policy if exists cost_centers_insert on public.cost_centers;
create policy cost_centers_insert
  on public.cost_centers for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','accountant']::public.member_role[]
  )));
drop policy if exists cost_centers_update on public.cost_centers;
create policy cost_centers_update
  on public.cost_centers for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','accountant']::public.member_role[]
  )));
drop policy if exists cost_centers_delete on public.cost_centers;
create policy cost_centers_delete
  on public.cost_centers for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- Function grants — revoke anon; engines for authenticated only
-- ---------------------------------------------------------------------------

revoke all on function public.sync_period_closed_flag() from public, anon, authenticated;
revoke all on function public.validate_account_hierarchy() from public, anon, authenticated;
revoke all on function public.prevent_account_delete_with_movements() from public, anon, authenticated;
revoke all on function public.validate_journal_line_tenancy() from public, anon, authenticated;
revoke all on function public.prevent_posted_journal_mutation() from public, anon, authenticated;
revoke all on function public.prevent_posted_line_mutation() from public, anon, authenticated;
revoke all on function public.resolve_open_period(uuid, date) from public, anon;
grant execute on function public.resolve_open_period(uuid, date) to authenticated;
revoke all on function public.next_journal_entry_number(uuid, uuid) from public, anon, authenticated;
revoke all on function public.accounting_write_audit(uuid, uuid, text, text, text, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.post_journal_entry(uuid) from public, anon;
grant execute on function public.post_journal_entry(uuid) to authenticated;
revoke all on function public.reverse_journal_entry(uuid, date, text) from public, anon;
grant execute on function public.reverse_journal_entry(uuid, date, text) to authenticated;
revoke all on function public.close_accounting_period(uuid) from public, anon;
grant execute on function public.close_accounting_period(uuid) to authenticated;
revoke all on function public.reopen_accounting_period(uuid, text) from public, anon;
grant execute on function public.reopen_accounting_period(uuid, text) to authenticated;
revoke all on function public.seed_starter_chart_of_accounts(uuid) from public, anon;
grant execute on function public.seed_starter_chart_of_accounts(uuid) to authenticated;
revoke all on function public.ensure_monthly_periods(uuid) from public, anon;
grant execute on function public.ensure_monthly_periods(uuid) to authenticated;
