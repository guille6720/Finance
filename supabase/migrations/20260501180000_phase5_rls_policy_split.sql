-- Phase 5 — Split FOR ALL RLS policies (eliminate multiple permissive SELECT)
-- Preserve authorization semantics exactly.

-- fiscal_points_of_sale
drop policy if exists fiscal_points_of_sale_write on public.fiscal_points_of_sale;
drop policy if exists fiscal_points_of_sale_insert on public.fiscal_points_of_sale;
drop policy if exists fiscal_points_of_sale_update on public.fiscal_points_of_sale;
drop policy if exists fiscal_points_of_sale_delete on public.fiscal_points_of_sale;
create policy fiscal_points_of_sale_insert
  on public.fiscal_points_of_sale for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
create policy fiscal_points_of_sale_update
  on public.fiscal_points_of_sale for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
create policy fiscal_points_of_sale_delete
  on public.fiscal_points_of_sale for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
-- fiscal_credential_metadata
drop policy if exists fiscal_credential_metadata_write on public.fiscal_credential_metadata;
drop policy if exists fiscal_credential_metadata_insert on public.fiscal_credential_metadata;
drop policy if exists fiscal_credential_metadata_update on public.fiscal_credential_metadata;
drop policy if exists fiscal_credential_metadata_delete on public.fiscal_credential_metadata;
create policy fiscal_credential_metadata_insert
  on public.fiscal_credential_metadata for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin']::public.member_role[]
  )));
create policy fiscal_credential_metadata_update
  on public.fiscal_credential_metadata for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin']::public.member_role[]
  )));
create policy fiscal_credential_metadata_delete
  on public.fiscal_credential_metadata for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin']::public.member_role[]
  )));
-- fiscal_service_profiles
drop policy if exists fiscal_service_profiles_write on public.fiscal_service_profiles;
drop policy if exists fiscal_service_profiles_insert on public.fiscal_service_profiles;
drop policy if exists fiscal_service_profiles_update on public.fiscal_service_profiles;
drop policy if exists fiscal_service_profiles_delete on public.fiscal_service_profiles;
create policy fiscal_service_profiles_insert
  on public.fiscal_service_profiles for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
create policy fiscal_service_profiles_update
  on public.fiscal_service_profiles for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
create policy fiscal_service_profiles_delete
  on public.fiscal_service_profiles for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
-- fiscal_document_lines
drop policy if exists fiscal_document_lines_write on public.fiscal_document_lines;
drop policy if exists fiscal_document_lines_insert on public.fiscal_document_lines;
drop policy if exists fiscal_document_lines_update on public.fiscal_document_lines;
drop policy if exists fiscal_document_lines_delete on public.fiscal_document_lines;
create policy fiscal_document_lines_insert
  on public.fiscal_document_lines for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy fiscal_document_lines_update
  on public.fiscal_document_lines for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy fiscal_document_lines_delete
  on public.fiscal_document_lines for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
-- fiscal_tax_summaries
drop policy if exists fiscal_tax_summaries_write on public.fiscal_tax_summaries;
drop policy if exists fiscal_tax_summaries_insert on public.fiscal_tax_summaries;
drop policy if exists fiscal_tax_summaries_update on public.fiscal_tax_summaries;
drop policy if exists fiscal_tax_summaries_delete on public.fiscal_tax_summaries;
create policy fiscal_tax_summaries_insert
  on public.fiscal_tax_summaries for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy fiscal_tax_summaries_update
  on public.fiscal_tax_summaries for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy fiscal_tax_summaries_delete
  on public.fiscal_tax_summaries for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
-- fiscal_accounting_mappings
drop policy if exists fiscal_accounting_mappings_write on public.fiscal_accounting_mappings;
drop policy if exists fiscal_accounting_mappings_insert on public.fiscal_accounting_mappings;
drop policy if exists fiscal_accounting_mappings_update on public.fiscal_accounting_mappings;
drop policy if exists fiscal_accounting_mappings_delete on public.fiscal_accounting_mappings;
create policy fiscal_accounting_mappings_insert
  on public.fiscal_accounting_mappings for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
create policy fiscal_accounting_mappings_update
  on public.fiscal_accounting_mappings for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
create policy fiscal_accounting_mappings_delete
  on public.fiscal_accounting_mappings for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
