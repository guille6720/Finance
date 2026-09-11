-- Phase 7 — RLS, grants, feature enable (Demo QA staging only)

alter table public.treasury_operation_sequences enable row level security;
alter table public.treasury_accounts enable row level security;
alter table public.treasury_operations enable row level security;
alter table public.treasury_operation_legs enable row level security;
alter table public.accounts_receivable_items enable row level security;
alter table public.payment_allocations enable row level security;
alter table public.collection_allocations enable row level security;
alter table public.open_item_compensations enable row level security;
alter table public.treasury_accounting_mappings enable row level security;
alter table public.bank_statement_imports enable row level security;
alter table public.bank_statement_lines enable row level security;
alter table public.bank_reconciliation_matches enable row level security;
-- sequences
create policy treasury_operation_sequences_select
  on public.treasury_operation_sequences for select to authenticated
  using ((select public.is_org_member(organization_id)));
-- treasury_accounts
create policy treasury_accounts_select
  on public.treasury_accounts for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy treasury_accounts_insert
  on public.treasury_accounts for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant','manager']::public.member_role[]
  )));
create policy treasury_accounts_update
  on public.treasury_accounts for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant','manager']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant','manager']::public.member_role[]
  )));
-- treasury_operations
create policy treasury_operations_select
  on public.treasury_operations for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy treasury_operations_insert
  on public.treasury_operations for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy treasury_operations_update
  on public.treasury_operations for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy treasury_operations_delete
  on public.treasury_operations for delete to authenticated
  using (
    status = 'DRAFT'
    and (select public.has_org_role(
      organization_id, array['owner','admin','manager']::public.member_role[]
    ))
  );
-- legs
create policy treasury_legs_select
  on public.treasury_operation_legs for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy treasury_legs_insert
  on public.treasury_operation_legs for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy treasury_legs_update
  on public.treasury_operation_legs for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy treasury_legs_delete
  on public.treasury_operation_legs for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
-- AR: select for members; insert only via engine ensure (still allow accountant insert of drafts? ensure is DEFINER)
-- Allow no client insert of AR monetary rows except engine — only SELECT grant for AR items
create policy accounts_receivable_items_select
  on public.accounts_receivable_items for select to authenticated
  using ((select public.is_org_member(organization_id)));
-- allocations draft writable
create policy payment_allocations_select
  on public.payment_allocations for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy payment_allocations_write
  on public.payment_allocations for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy payment_allocations_update
  on public.payment_allocations for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy payment_allocations_delete
  on public.payment_allocations for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy collection_allocations_select
  on public.collection_allocations for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy collection_allocations_insert
  on public.collection_allocations for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy collection_allocations_update
  on public.collection_allocations for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy collection_allocations_delete
  on public.collection_allocations for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy open_item_compensations_select
  on public.open_item_compensations for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy treasury_accounting_mappings_select
  on public.treasury_accounting_mappings for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy treasury_accounting_mappings_insert
  on public.treasury_accounting_mappings for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
create policy treasury_accounting_mappings_update
  on public.treasury_accounting_mappings for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
create policy treasury_accounting_mappings_delete
  on public.treasury_accounting_mappings for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin']::public.member_role[]
  )));
-- bank
create policy bank_statement_imports_select
  on public.bank_statement_imports for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy bank_statement_imports_insert
  on public.bank_statement_imports for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
create policy bank_statement_lines_select
  on public.bank_statement_lines for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy bank_statement_lines_insert
  on public.bank_statement_lines for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
create policy bank_recon_matches_select
  on public.bank_reconciliation_matches for select to authenticated
  using ((select public.is_org_member(organization_id)));
-- Grants
grant select on public.treasury_operation_sequences to authenticated;
grant select, insert, update on public.treasury_accounts to authenticated;
grant select, insert, update, delete on public.treasury_operations to authenticated;
grant select, insert, update, delete on public.treasury_operation_legs to authenticated;
grant select on public.accounts_receivable_items to authenticated;
grant select, insert, update, delete on public.payment_allocations to authenticated;
grant select, insert, update, delete on public.collection_allocations to authenticated;
grant select on public.open_item_compensations to authenticated;
grant select, insert, update, delete on public.treasury_accounting_mappings to authenticated;
grant select, insert on public.bank_statement_imports to authenticated;
grant select, insert on public.bank_statement_lines to authenticated;
grant select on public.bank_reconciliation_matches to authenticated;
revoke all on public.treasury_operation_sequences from anon;
revoke all on public.treasury_accounts from anon;
revoke all on public.treasury_operations from anon;
revoke all on public.treasury_operation_legs from anon;
revoke all on public.accounts_receivable_items from anon;
revoke all on public.payment_allocations from anon;
revoke all on public.collection_allocations from anon;
revoke all on public.open_item_compensations from anon;
revoke all on public.treasury_accounting_mappings from anon;
revoke all on public.bank_statement_imports from anon;
revoke all on public.bank_statement_lines from anon;
revoke all on public.bank_reconciliation_matches from anon;
-- Enable cash + banks for Demo QA orgs only
insert into public.organization_features (organization_id, feature_id, status, enabled_at)
select distinct c.organization_id, fc.id, 'enabled'::public.feature_status, timezone('utc', now())
from public.counterparties c
inner join public.feature_catalog fc on fc.code in ('cash', 'banks')
where c.legal_name ilike '%Demo%'
on conflict (organization_id, feature_id) do update
  set status = excluded.status,
      enabled_at = coalesce(public.organization_features.enabled_at, excluded.enabled_at);
