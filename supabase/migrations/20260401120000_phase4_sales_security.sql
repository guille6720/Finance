-- Phase 4 — Sales RLS + grants (STAGING)

alter table public.sales_document_sequences enable row level security;
alter table public.sales_documents enable row level security;
alter table public.sales_document_lines enable row level security;
-- sequences: read only for authenticated members
drop policy if exists sales_document_sequences_select on public.sales_document_sequences;
create policy sales_document_sequences_select
  on public.sales_document_sequences for select to authenticated
  using ((select public.is_org_member(organization_id)));
-- sales_documents
drop policy if exists sales_documents_select on public.sales_documents;
create policy sales_documents_select
  on public.sales_documents for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists sales_documents_insert on public.sales_documents;
create policy sales_documents_insert
  on public.sales_documents for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
drop policy if exists sales_documents_update on public.sales_documents;
create policy sales_documents_update
  on public.sales_documents for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
drop policy if exists sales_documents_delete on public.sales_documents;
create policy sales_documents_delete
  on public.sales_documents for delete to authenticated
  using (
    status = 'DRAFT'
    and is_commercially_frozen = false
    and (select public.has_org_role(
      organization_id, array['owner','admin','manager']::public.member_role[]
    ))
  );
-- lines
drop policy if exists sales_document_lines_select on public.sales_document_lines;
create policy sales_document_lines_select
  on public.sales_document_lines for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists sales_document_lines_insert on public.sales_document_lines;
create policy sales_document_lines_insert
  on public.sales_document_lines for insert to authenticated
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
drop policy if exists sales_document_lines_update on public.sales_document_lines;
create policy sales_document_lines_update
  on public.sales_document_lines for update to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
drop policy if exists sales_document_lines_delete on public.sales_document_lines;
create policy sales_document_lines_delete
  on public.sales_document_lines for delete to authenticated
  using ((select public.has_org_role(
    organization_id, array['owner','admin','manager','operator']::public.member_role[]
  )));
grant select on public.sales_document_sequences to authenticated;
grant select, insert, update, delete on public.sales_documents to authenticated;
grant select, insert, update, delete on public.sales_document_lines to authenticated;
revoke all on public.sales_document_sequences from anon;
revoke all on public.sales_documents from anon;
revoke all on public.sales_document_lines from anon;
revoke all on function public.sales_assert_role(uuid, public.member_role[]) from public;
revoke all on function public.sales_write_audit(uuid, uuid, text, uuid, text, jsonb) from public;
-- Enable sales feature for staging orgs with synthetic demo counterparties (QA only)
insert into public.organization_features (organization_id, feature_id, status, enabled_at)
select distinct c.organization_id, fc.id, 'enabled'::public.feature_status, timezone('utc', now())
from public.counterparties c
inner join public.feature_catalog fc on fc.code = 'sales'
where c.legal_name ilike '%Demo%'
on conflict (organization_id, feature_id) do update
  set status = excluded.status,
      enabled_at = coalesce(public.organization_features.enabled_at, excluded.enabled_at);
