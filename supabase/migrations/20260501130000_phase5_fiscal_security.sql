-- Phase 5 — Fiscal RLS + feature enablement for synthetic QA orgs

alter table public.fiscal_rule_versions enable row level security;
alter table public.fiscal_document_types enable row level security;
alter table public.fiscal_parameter_catalogs enable row level security;
alter table public.fiscal_points_of_sale enable row level security;
alter table public.fiscal_credential_metadata enable row level security;
alter table public.fiscal_service_profiles enable row level security;
alter table public.fiscal_documents enable row level security;
alter table public.fiscal_document_lines enable row level security;
alter table public.fiscal_tax_summaries enable row level security;
alter table public.fiscal_authorization_attempts enable row level security;
alter table public.fiscal_accounting_mappings enable row level security;
-- Global catalogs readable by authenticated
drop policy if exists fiscal_document_types_select on public.fiscal_document_types;
create policy fiscal_document_types_select
  on public.fiscal_document_types for select to authenticated
  using (true);
drop policy if exists fiscal_rule_versions_select on public.fiscal_rule_versions;
create policy fiscal_rule_versions_select
  on public.fiscal_rule_versions for select to authenticated
  using (
    organization_id is null
    or (select public.is_org_member(organization_id))
  );
drop policy if exists fiscal_parameter_catalogs_select on public.fiscal_parameter_catalogs;
create policy fiscal_parameter_catalogs_select
  on public.fiscal_parameter_catalogs for select to authenticated
  using (
    organization_id is null
    or (select public.is_org_member(organization_id))
  );
-- Points of sale
drop policy if exists fiscal_points_of_sale_select on public.fiscal_points_of_sale;
create policy fiscal_points_of_sale_select
  on public.fiscal_points_of_sale for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists fiscal_points_of_sale_write on public.fiscal_points_of_sale;
create policy fiscal_points_of_sale_write
  on public.fiscal_points_of_sale for all to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
-- Credential metadata (no secrets in table)
drop policy if exists fiscal_credential_metadata_select on public.fiscal_credential_metadata;
create policy fiscal_credential_metadata_select
  on public.fiscal_credential_metadata for select to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
drop policy if exists fiscal_credential_metadata_write on public.fiscal_credential_metadata;
create policy fiscal_credential_metadata_write
  on public.fiscal_credential_metadata for all to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin']::public.member_role[]
  )));
-- Service profiles
drop policy if exists fiscal_service_profiles_select on public.fiscal_service_profiles;
create policy fiscal_service_profiles_select
  on public.fiscal_service_profiles for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists fiscal_service_profiles_write on public.fiscal_service_profiles;
create policy fiscal_service_profiles_write
  on public.fiscal_service_profiles for all to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
-- Fiscal documents
drop policy if exists fiscal_documents_select on public.fiscal_documents;
create policy fiscal_documents_select
  on public.fiscal_documents for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists fiscal_documents_insert on public.fiscal_documents;
create policy fiscal_documents_insert
  on public.fiscal_documents for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
drop policy if exists fiscal_documents_update on public.fiscal_documents;
create policy fiscal_documents_update
  on public.fiscal_documents for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
drop policy if exists fiscal_documents_delete on public.fiscal_documents;
create policy fiscal_documents_delete
  on public.fiscal_documents for delete to authenticated
  using (
    status in ('DRAFT', 'REJECTED')
    and (select public.has_org_role(
      organization_id, array['owner','admin','accountant']::public.member_role[]
    ))
  );
-- Lines
drop policy if exists fiscal_document_lines_select on public.fiscal_document_lines;
create policy fiscal_document_lines_select
  on public.fiscal_document_lines for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists fiscal_document_lines_write on public.fiscal_document_lines;
create policy fiscal_document_lines_write
  on public.fiscal_document_lines for all to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
-- Tax summaries
drop policy if exists fiscal_tax_summaries_select on public.fiscal_tax_summaries;
create policy fiscal_tax_summaries_select
  on public.fiscal_tax_summaries for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists fiscal_tax_summaries_write on public.fiscal_tax_summaries;
create policy fiscal_tax_summaries_write
  on public.fiscal_tax_summaries for all to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
-- Attempts: read members; insert via engine roles
drop policy if exists fiscal_authorization_attempts_select on public.fiscal_authorization_attempts;
create policy fiscal_authorization_attempts_select
  on public.fiscal_authorization_attempts for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists fiscal_authorization_attempts_insert on public.fiscal_authorization_attempts;
create policy fiscal_authorization_attempts_insert
  on public.fiscal_authorization_attempts for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
-- Accounting mappings
drop policy if exists fiscal_accounting_mappings_select on public.fiscal_accounting_mappings;
create policy fiscal_accounting_mappings_select
  on public.fiscal_accounting_mappings for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists fiscal_accounting_mappings_write on public.fiscal_accounting_mappings;
create policy fiscal_accounting_mappings_write
  on public.fiscal_accounting_mappings for all to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
-- Grants
grant select on public.fiscal_document_types to authenticated;
grant select on public.fiscal_rule_versions to authenticated;
grant select on public.fiscal_parameter_catalogs to authenticated;
grant select, insert, update, delete on public.fiscal_points_of_sale to authenticated;
grant select, insert, update, delete on public.fiscal_credential_metadata to authenticated;
grant select, insert, update, delete on public.fiscal_service_profiles to authenticated;
grant select, insert, update, delete on public.fiscal_documents to authenticated;
grant select, insert, update, delete on public.fiscal_document_lines to authenticated;
grant select, insert, update, delete on public.fiscal_tax_summaries to authenticated;
grant select, insert on public.fiscal_authorization_attempts to authenticated;
grant select, insert, update, delete on public.fiscal_accounting_mappings to authenticated;
revoke all on public.fiscal_rule_versions from anon;
revoke all on public.fiscal_document_types from anon;
revoke all on public.fiscal_parameter_catalogs from anon;
revoke all on public.fiscal_points_of_sale from anon;
revoke all on public.fiscal_credential_metadata from anon;
revoke all on public.fiscal_service_profiles from anon;
revoke all on public.fiscal_documents from anon;
revoke all on public.fiscal_document_lines from anon;
revoke all on public.fiscal_tax_summaries from anon;
revoke all on public.fiscal_authorization_attempts from anon;
revoke all on public.fiscal_accounting_mappings from anon;
-- Enable fiscal_invoicing only for synthetic Demo QA orgs that already have sales
insert into public.organization_features (organization_id, feature_id, status, enabled_at)
select distinct c.organization_id, fc.id, 'enabled'::public.feature_status, timezone('utc', now())
from public.counterparties c
inner join public.feature_catalog fc on fc.code = 'fiscal_invoicing'
where c.legal_name ilike '%Demo%'
on conflict (organization_id, feature_id) do update
  set status = excluded.status,
      enabled_at = coalesce(public.organization_features.enabled_at, excluded.enabled_at);
