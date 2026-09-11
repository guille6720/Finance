-- Phase 6 FINAL LIVE ADVISOR HARDENING (STAGING)
-- Covers 4 unindexed composite FKs reported by Performance Advisor.
--
-- Audit of CURRENT indexes (before this migration):
--
-- accounts_payable_items_org_doc_fk (organization_id, purchase_document_id)
--   HAD: unique(purchase_document_id), accounts_payable_items_doc_idx(purchase_document_id)
--   MISSING: left-prefix (organization_id, purchase_document_id)
--   NOTE: single-column doc_idx is redundant with UNIQUE(purchase_document_id)
--
-- purchase_documents_org_branch_fk (organization_id, branch_id)
--   HAD: org_status_date / org_supplier / org_due — none lead with (org, branch)
--   MISSING: (organization_id, branch_id)
--
-- purchase_documents_org_po_fk (organization_id, purchase_order_id)
--   HAD: purchase_documents_po_idx (purchase_order_id) WHERE NOT NULL
--   MISSING: left-prefix (organization_id, purchase_order_id)
--   REPLACE: drop single-column po_idx after creating composite (same access pattern
--            always scoped by organization_id in app queries; left-prefix covers FK)
--
-- purchase_orders_org_branch_fk (organization_id, branch_id)
--   HAD: org_status_date / org_supplier — none lead with (org, branch)
--   MISSING: (organization_id, branch_id)
--
-- Do NOT drop indexes solely for unused_index INFO (synthetic staging traffic).

-- 1) AP → purchase document composite FK
create index if not exists accounts_payable_items_org_doc_idx
  on public.accounts_payable_items (organization_id, purchase_document_id);
-- Redundant with UNIQUE(purchase_document_id); keep UNIQUE, drop duplicate btree
drop index if exists public.accounts_payable_items_doc_idx;
-- 2) Purchase documents → branch composite FK (nullable branch)
create index if not exists purchase_documents_org_branch_idx
  on public.purchase_documents (organization_id, branch_id)
  where branch_id is not null;
-- 3) Purchase documents → purchase order composite FK
--    Replaces purchase_documents_po_idx (purchase_order_id) — left-prefix covers FK
--    and org-scoped PO lookups.
create index if not exists purchase_documents_org_po_idx
  on public.purchase_documents (organization_id, purchase_order_id)
  where purchase_order_id is not null;
drop index if exists public.purchase_documents_po_idx;
-- 4) Purchase orders → branch composite FK (nullable branch)
create index if not exists purchase_orders_org_branch_idx
  on public.purchase_orders (organization_id, branch_id)
  where branch_id is not null;
comment on index public.accounts_payable_items_org_doc_idx is
  'Covers accounts_payable_items_org_doc_fk (organization_id, purchase_document_id)';
comment on index public.purchase_documents_org_branch_idx is
  'Covers purchase_documents_org_branch_fk (organization_id, branch_id)';
comment on index public.purchase_documents_org_po_idx is
  'Covers purchase_documents_org_po_fk; replaces purchase_documents_po_idx';
comment on index public.purchase_orders_org_branch_idx is
  'Covers purchase_orders_org_branch_fk (organization_id, branch_id)';
