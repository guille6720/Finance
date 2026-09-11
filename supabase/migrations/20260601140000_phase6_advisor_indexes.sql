-- Phase 6 — Advisor FK covering indexes

create index if not exists purchase_orders_approved_by_idx
  on public.purchase_orders (approved_by)
  where approved_by is not null;
create index if not exists purchase_documents_reviewed_by_idx
  on public.purchase_documents (reviewed_by)
  where reviewed_by is not null;
create index if not exists purchase_documents_posted_by_idx
  on public.purchase_documents (posted_by)
  where posted_by is not null;
create index if not exists purchase_documents_reverse_journal_idx
  on public.purchase_documents (reverse_journal_entry_id)
  where reverse_journal_entry_id is not null;
create index if not exists purchase_document_lines_cost_center_idx
  on public.purchase_document_lines (cost_center_id)
  where cost_center_id is not null;
create index if not exists accounts_payable_items_doc_idx
  on public.accounts_payable_items (purchase_document_id);
create index if not exists purchase_attachments_uploaded_by_idx
  on public.purchase_attachments (uploaded_by)
  where uploaded_by is not null;
