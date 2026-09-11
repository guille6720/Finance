-- Phase 5 — Performance/security hardening (FK indexes, enum probe)

-- Covering indexes for FKs / common filters (Performance Advisor)
create index if not exists fiscal_documents_created_by_idx
  on public.fiscal_documents (created_by)
  where created_by is not null;
create index if not exists fiscal_documents_journal_entry_id_idx
  on public.fiscal_documents (journal_entry_id)
  where journal_entry_id is not null;
create index if not exists fiscal_documents_related_idx
  on public.fiscal_documents (related_fiscal_document_id)
  where related_fiscal_document_id is not null;
create index if not exists fiscal_documents_rule_version_idx
  on public.fiscal_documents (fiscal_rule_version_id);
create index if not exists fiscal_documents_document_type_idx
  on public.fiscal_documents (document_type_id);
create index if not exists fiscal_points_of_sale_org_env_active_idx
  on public.fiscal_points_of_sale (organization_id, environment, is_active);
create index if not exists fiscal_credential_metadata_org_env_idx
  on public.fiscal_credential_metadata (organization_id, environment);
create index if not exists fiscal_authorization_attempts_org_idx
  on public.fiscal_authorization_attempts (organization_id);
-- Ensure INVOICED exists on sales_document_status (idempotent)
do $$ begin
  alter type public.sales_document_status add value if not exists 'INVOICED';
exception when duplicate_object then null;
end $$;
-- Attempts should not be updatable by authenticated (append-only from client perspective)
revoke update, delete on public.fiscal_authorization_attempts from authenticated;
