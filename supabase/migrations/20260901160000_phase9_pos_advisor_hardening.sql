-- Phase 9 advisor hardening — FK covering indexes

create index if not exists pos_terminals_default_customer_idx
  on public.pos_terminals (organization_id, default_customer_id)
  where default_customer_id is not null;
create index if not exists pos_terminals_org_fiscal_pos_idx
  on public.pos_terminals (organization_id, fiscal_point_of_sale_id)
  where fiscal_point_of_sale_id is not null;
create index if not exists pos_sessions_org_terminal_idx
  on public.pos_sessions (organization_id, terminal_id);
create index if not exists pos_sales_org_terminal_idx
  on public.pos_sales (organization_id, terminal_id);
create index if not exists pos_sales_org_session_idx
  on public.pos_sales (organization_id, session_id);
create index if not exists pos_sales_org_sales_doc_idx
  on public.pos_sales (organization_id, sales_document_id);
create index if not exists pos_tenders_org_sale_idx
  on public.pos_tenders (organization_id, pos_sale_id);
create index if not exists pos_tenders_org_account_idx
  on public.pos_tenders (organization_id, treasury_account_id);
create index if not exists pos_tta_org_terminal_idx
  on public.pos_terminal_tender_accounts (organization_id, terminal_id);
create index if not exists pos_tta_org_account_idx
  on public.pos_terminal_tender_accounts (organization_id, treasury_account_id);
