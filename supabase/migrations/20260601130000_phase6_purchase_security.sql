-- Phase 6 — RLS, grants, private storage, feature enable (STAGING QA only)

-- ---------------------------------------------------------------------------
-- RLS enable
-- ---------------------------------------------------------------------------

alter table public.purchase_order_sequences enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_lines enable row level security;
alter table public.purchase_documents enable row level security;
alter table public.purchase_document_lines enable row level security;
alter table public.purchase_document_tax_summaries enable row level security;
alter table public.accounts_payable_items enable row level security;
alter table public.purchase_accounting_mappings enable row level security;
alter table public.purchase_attachments enable row level security;
-- ---------------------------------------------------------------------------
-- purchase_order_sequences
-- ---------------------------------------------------------------------------

create policy purchase_order_sequences_select
  on public.purchase_order_sequences for select to authenticated
  using ((select public.is_org_member(organization_id)));
-- ---------------------------------------------------------------------------
-- purchase_orders
-- ---------------------------------------------------------------------------

create policy purchase_orders_select
  on public.purchase_orders for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy purchase_orders_insert
  on public.purchase_orders for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
create policy purchase_orders_update
  on public.purchase_orders for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
create policy purchase_orders_delete
  on public.purchase_orders for delete to authenticated
  using (
    status = 'DRAFT'
    and (select public.has_org_role(
      organization_id, array['owner','admin','manager']::public.member_role[]
    ))
  );
-- ---------------------------------------------------------------------------
-- purchase_order_lines
-- ---------------------------------------------------------------------------

create policy purchase_order_lines_select
  on public.purchase_order_lines for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy purchase_order_lines_insert
  on public.purchase_order_lines for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
create policy purchase_order_lines_update
  on public.purchase_order_lines for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
create policy purchase_order_lines_delete
  on public.purchase_order_lines for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- purchase_documents
-- ---------------------------------------------------------------------------

create policy purchase_documents_select
  on public.purchase_documents for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy purchase_documents_insert
  on public.purchase_documents for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
create policy purchase_documents_update
  on public.purchase_documents for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy purchase_documents_delete
  on public.purchase_documents for delete to authenticated
  using (
    status = 'DRAFT'
    and (select public.has_org_role(
      organization_id, array['owner','admin','manager']::public.member_role[]
    ))
  );
-- ---------------------------------------------------------------------------
-- purchase_document_lines
-- ---------------------------------------------------------------------------

create policy purchase_document_lines_select
  on public.purchase_document_lines for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy purchase_document_lines_insert
  on public.purchase_document_lines for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
create policy purchase_document_lines_update
  on public.purchase_document_lines for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
create policy purchase_document_lines_delete
  on public.purchase_document_lines for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- tax summaries
-- ---------------------------------------------------------------------------

create policy purchase_tax_summaries_select
  on public.purchase_document_tax_summaries for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy purchase_tax_summaries_insert
  on public.purchase_document_tax_summaries for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy purchase_tax_summaries_update
  on public.purchase_document_tax_summaries for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy purchase_tax_summaries_delete
  on public.purchase_document_tax_summaries for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- AP: SELECT only for clients — engine writes via SECURITY DEFINER
-- ---------------------------------------------------------------------------

create policy accounts_payable_items_select
  on public.accounts_payable_items for select to authenticated
  using ((select public.is_org_member(organization_id)));
-- ---------------------------------------------------------------------------
-- purchase_accounting_mappings
-- ---------------------------------------------------------------------------

create policy purchase_accounting_mappings_select
  on public.purchase_accounting_mappings for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy purchase_accounting_mappings_insert
  on public.purchase_accounting_mappings for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
create policy purchase_accounting_mappings_update
  on public.purchase_accounting_mappings for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','accountant']::public.member_role[]
  )));
create policy purchase_accounting_mappings_delete
  on public.purchase_accounting_mappings for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- attachments metadata
-- ---------------------------------------------------------------------------

create policy purchase_attachments_select
  on public.purchase_attachments for select to authenticated
  using ((select public.is_org_member(organization_id)));
create policy purchase_attachments_insert
  on public.purchase_attachments for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
create policy purchase_attachments_delete
  on public.purchase_attachments for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

grant select on public.purchase_order_sequences to authenticated;
grant select, insert, update, delete on public.purchase_orders to authenticated;
grant select, insert, update, delete on public.purchase_order_lines to authenticated;
grant select, insert, update, delete on public.purchase_documents to authenticated;
grant select, insert, update, delete on public.purchase_document_lines to authenticated;
grant select, insert, update, delete on public.purchase_document_tax_summaries to authenticated;
grant select on public.accounts_payable_items to authenticated;
grant select, insert, update, delete on public.purchase_accounting_mappings to authenticated;
grant select, insert, delete on public.purchase_attachments to authenticated;
revoke all on public.purchase_order_sequences from anon;
revoke all on public.purchase_orders from anon;
revoke all on public.purchase_order_lines from anon;
revoke all on public.purchase_documents from anon;
revoke all on public.purchase_document_lines from anon;
revoke all on public.purchase_document_tax_summaries from anon;
revoke all on public.accounts_payable_items from anon;
revoke all on public.purchase_accounting_mappings from anon;
revoke all on public.purchase_attachments from anon;
-- ---------------------------------------------------------------------------
-- Private storage bucket (NEVER public)
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'purchase-evidence',
  'purchase-evidence',
  false,
  15728640, -- 15 MB
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;
-- Path convention: {organization_id}/{purchase_document_id}/{filename}
create policy purchase_evidence_select
  on storage.objects for select to authenticated
  using (
    bucket_id = 'purchase-evidence'
    and (select public.is_org_member((storage.foldername(name))[1]::uuid))
  );
create policy purchase_evidence_insert
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'purchase-evidence'
    and (select public.has_org_role(
      (storage.foldername(name))[1]::uuid,
      array['owner','admin','manager','operator','accountant']::public.member_role[]
    ))
  );
create policy purchase_evidence_delete
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'purchase-evidence'
    and (select public.has_org_role(
      (storage.foldername(name))[1]::uuid,
      array['owner','admin','manager']::public.member_role[]
    ))
  );
-- ---------------------------------------------------------------------------
-- Enable purchases ONLY for staging Demo QA orgs (never global prod)
-- ---------------------------------------------------------------------------

insert into public.organization_features (organization_id, feature_id, status, enabled_at)
select distinct c.organization_id, fc.id, 'enabled'::public.feature_status, timezone('utc', now())
from public.counterparties c
inner join public.feature_catalog fc on fc.code = 'purchases'
where c.legal_name ilike '%Demo%'
on conflict (organization_id, feature_id) do update
  set status = excluded.status,
      enabled_at = coalesce(public.organization_features.enabled_at, excluded.enabled_at);
