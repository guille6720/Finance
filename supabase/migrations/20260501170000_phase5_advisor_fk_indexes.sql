-- Phase 5 — Advisor FK covering indexes (documentation + NEW indexes only)
--
-- Source audit: migrations 20260501100000 … 20260501160000
-- Findings: docs/qa/PHASE5-ADVISOR-AUDIT-FINDINGS.md
-- Script: scripts/phase5-advisor-audit.mjs
--
-- Scope: public.fiscal_* tables only.
-- Does NOT change RLS / FOR ALL policies (listed in findings; apply separately).
-- Idempotent: create index if not exists — no duplicates of indexes from
-- 20260501100000 / 20260501150000.
--
-- Already covered (do NOT recreate):
--   fiscal_documents_created_by_idx, fiscal_documents_journal_entry_id_idx,
--   fiscal_documents_related_idx, fiscal_documents_rule_version_idx,
--   fiscal_documents_document_type_idx, fiscal_documents_sales_idx,
--   fiscal_documents_org_status_date_idx, fiscal_documents_org_id_unique,
--   fiscal_document_lines_org_doc_idx, fiscal_authorization_attempts_doc_idx,
--   fiscal_authorization_attempts_org_idx, fiscal_points_of_sale unique/org indexes,
--   fiscal_credential_metadata_org_env_idx, fiscal_accounting_mappings UNIQUE(organization_id)

-- ---------------------------------------------------------------------------
-- Missing FK covering indexes
-- ---------------------------------------------------------------------------

-- fiscal_rule_versions_reviewed_by_fkey
create index if not exists fiscal_rule_versions_reviewed_by_idx
  on public.fiscal_rule_versions (reviewed_by)
  where reviewed_by is not null;
-- fiscal_rule_versions_activated_by_fkey
create index if not exists fiscal_rule_versions_activated_by_idx
  on public.fiscal_rule_versions (activated_by)
  where activated_by is not null;
-- fiscal_pos_org_branch_fk
create index if not exists fiscal_points_of_sale_org_branch_idx
  on public.fiscal_points_of_sale (organization_id, branch_id);
-- fiscal_documents_org_counterparty_fk
create index if not exists fiscal_documents_org_counterparty_idx
  on public.fiscal_documents (organization_id, counterparty_id);
-- fiscal_documents_org_branch_fk
create index if not exists fiscal_documents_org_branch_idx
  on public.fiscal_documents (organization_id, branch_id);
-- fiscal_documents_org_pos_fk
create index if not exists fiscal_documents_org_pos_idx
  on public.fiscal_documents (organization_id, point_of_sale_id);
-- fiscal_tax_summaries_organization_id_fkey + fiscal_tax_summaries_org_doc_fk
-- (unique on fiscal_document_id,… does not lead with organization_id)
create index if not exists fiscal_tax_summaries_org_doc_idx
  on public.fiscal_tax_summaries (organization_id, fiscal_document_id);
-- fiscal_auth_attempts_org_doc_fk
-- (org_idx + doc_idx exist separately; composite FK needs joint leading columns)
create index if not exists fiscal_authorization_attempts_org_doc_idx
  on public.fiscal_authorization_attempts (organization_id, fiscal_document_id);
-- fiscal_accounting_mappings_sales_fk
create index if not exists fiscal_accounting_mappings_sales_account_idx
  on public.fiscal_accounting_mappings (organization_id, sales_account_id);
-- fiscal_accounting_mappings_vat_fk
create index if not exists fiscal_accounting_mappings_vat_account_idx
  on public.fiscal_accounting_mappings (organization_id, vat_output_account_id);
-- fiscal_accounting_mappings_recv_fk
create index if not exists fiscal_accounting_mappings_recv_account_idx
  on public.fiscal_accounting_mappings (organization_id, receivables_account_id);
