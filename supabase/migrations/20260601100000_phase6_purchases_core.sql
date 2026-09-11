-- Phase 6 — Purchases core (STAGING)
-- Approved adjustments: COMPLETED (not RECEIVED), ARS MVP, AP direction model

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.purchase_order_status as enum (
    'DRAFT', 'APPROVED', 'COMPLETED', 'CANCELLED'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.purchase_document_type as enum (
    'SUPPLIER_INVOICE', 'SUPPLIER_CREDIT_NOTE', 'SUPPLIER_DEBIT_NOTE'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.purchase_document_status as enum (
    'DRAFT', 'REVIEWED', 'POSTED', 'REVERSED', 'REJECTED'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.purchase_accounting_status as enum (
    'NOT_APPLICABLE', 'PENDING', 'POSTED', 'ERROR', 'ACCOUNTING_REQUIRES_REVIEW'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.accounts_payable_status as enum (
    'OPEN', 'PARTIALLY_PAID', 'PAID', 'VOID'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.accounts_payable_direction as enum (
    'AP_INCREASE', 'AP_DECREASE'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.purchase_vat_treatment as enum (
    'TAXED', 'EXEMPT', 'NOT_TAXED'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.purchase_relationship_type as enum (
    'CREDIT_NOTE', 'DEBIT_NOTE'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.purchase_attachment_kind as enum (
    'SUPPLIER_PDF', 'SCAN', 'SUPPORTING_RECEIPT', 'OTHER'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.purchase_line_unit_code as enum (
    'UNIT', 'HOUR', 'KG', 'M', 'OTHER'
  );
exception when duplicate_object then null;
end $$;
-- ---------------------------------------------------------------------------
-- Sequences
-- ---------------------------------------------------------------------------

create table public.purchase_order_sequences (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  sequence_year int not null check (sequence_year >= 2000 and sequence_year <= 2100),
  last_value bigint not null default 0 check (last_value >= 0),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (organization_id, sequence_year)
);
-- ---------------------------------------------------------------------------
-- purchase_orders
-- ---------------------------------------------------------------------------

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  supplier_id uuid not null,
  internal_number text not null,
  status public.purchase_order_status not null default 'DRAFT',
  order_date date not null default (timezone('utc', now()))::date,
  expected_delivery_date date,
  currency_code text not null default 'ARS' check (currency_code ~ '^[A-Z]{3}$'),
  supplier_snapshot jsonb not null default '{}'::jsonb,
  subtotal numeric(19, 4) not null default 0 check (subtotal >= 0),
  discount_total numeric(19, 4) not null default 0 check (discount_total >= 0),
  total numeric(19, 4) not null default 0 check (total >= 0),
  notes text,
  internal_notes text,
  created_by uuid references auth.users (id),
  approved_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  approved_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  constraint purchase_orders_org_id_unique unique (organization_id, id),
  constraint purchase_orders_internal_number_unique unique (organization_id, internal_number),
  constraint purchase_orders_org_supplier_fk
    foreign key (organization_id, supplier_id)
    references public.counterparties (organization_id, id)
    on delete restrict,
  constraint purchase_orders_org_branch_fk
    foreign key (organization_id, branch_id)
    references public.branches (organization_id, id)
    on delete restrict,
  constraint purchase_orders_ars_mvp check (currency_code = 'ARS')
);
create index purchase_orders_org_status_date_idx
  on public.purchase_orders (organization_id, status, order_date desc);
create index purchase_orders_org_supplier_idx
  on public.purchase_orders (organization_id, supplier_id);
create index purchase_orders_created_by_idx
  on public.purchase_orders (created_by) where created_by is not null;
create trigger purchase_orders_set_updated_at
before update on public.purchase_orders
for each row execute function public.set_updated_at();
create table public.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  purchase_order_id uuid not null,
  line_number int not null check (line_number > 0),
  description text not null check (length(trim(description)) >= 1),
  quantity numeric(18, 4) not null check (quantity > 0),
  unit_code public.purchase_line_unit_code not null default 'UNIT',
  unit_price numeric(19, 4) not null check (unit_price >= 0),
  discount_amount numeric(19, 4) not null default 0 check (discount_amount >= 0),
  line_total numeric(19, 4) not null default 0 check (line_total >= 0),
  future_product_id uuid,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (purchase_order_id, line_number),
  constraint purchase_order_lines_org_po_fk
    foreign key (organization_id, purchase_order_id)
    references public.purchase_orders (organization_id, id)
    on delete cascade
);
create index purchase_order_lines_org_po_idx
  on public.purchase_order_lines (organization_id, purchase_order_id);
create trigger purchase_order_lines_set_updated_at
before update on public.purchase_order_lines
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- purchase_documents
-- ---------------------------------------------------------------------------

create table public.purchase_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  supplier_id uuid not null,
  purchase_order_id uuid,
  document_type public.purchase_document_type not null,
  document_class text,
  arca_cbte_tipo int,
  point_of_sale int check (point_of_sale is null or point_of_sale > 0),
  document_number bigint check (document_number is null or document_number > 0),
  issue_date date not null,
  accounting_date date not null,
  due_date date,
  payment_due_days int check (payment_due_days is null or payment_due_days >= 0),
  currency_code text not null default 'ARS' check (currency_code ~ '^[A-Z]{3}$'),
  currency_rate numeric(19, 6) not null default 1 check (currency_rate > 0),
  supplier_snapshot jsonb not null default '{}'::jsonb,
  supplier_tax_id_normalized text,
  net_taxed_amount numeric(19, 4) not null default 0 check (net_taxed_amount >= 0),
  net_exempt_amount numeric(19, 4) not null default 0 check (net_exempt_amount >= 0),
  net_untaxed_amount numeric(19, 4) not null default 0 check (net_untaxed_amount >= 0),
  vat_amount numeric(19, 4) not null default 0 check (vat_amount >= 0),
  other_taxes_amount numeric(19, 4) not null default 0 check (other_taxes_amount >= 0),
  total_amount numeric(19, 4) not null default 0 check (total_amount >= 0),
  status public.purchase_document_status not null default 'DRAFT',
  accounting_status public.purchase_accounting_status not null default 'NOT_APPLICABLE',
  journal_entry_id uuid,
  reverse_journal_entry_id uuid,
  related_purchase_document_id uuid,
  relationship_type public.purchase_relationship_type,
  external_cae text,
  external_cae_expiration date,
  external_reference text,
  idempotency_key text not null,
  notes text,
  internal_notes text,
  created_by uuid references auth.users (id),
  reviewed_by uuid references auth.users (id),
  posted_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  reviewed_at timestamptz,
  posted_at timestamptz,
  constraint purchase_documents_org_id_unique unique (organization_id, id),
  constraint purchase_documents_idempotency_unique unique (organization_id, idempotency_key),
  constraint purchase_documents_org_supplier_fk
    foreign key (organization_id, supplier_id)
    references public.counterparties (organization_id, id)
    on delete restrict,
  constraint purchase_documents_org_branch_fk
    foreign key (organization_id, branch_id)
    references public.branches (organization_id, id)
    on delete restrict,
  constraint purchase_documents_org_po_fk
    foreign key (organization_id, purchase_order_id)
    references public.purchase_orders (organization_id, id)
    on delete restrict,
  constraint purchase_documents_related_fk
    foreign key (related_purchase_document_id)
    references public.purchase_documents (id)
    on delete restrict,
  constraint purchase_documents_journal_fk
    foreign key (journal_entry_id)
    references public.journal_entries (id)
    on delete restrict,
  constraint purchase_documents_reverse_journal_fk
    foreign key (reverse_journal_entry_id)
    references public.journal_entries (id)
    on delete restrict,
  constraint purchase_documents_ars_mvp check (
    currency_code = 'ARS' and currency_rate = 1
  )
);
-- Normalized duplicate identity (POS/number as integers — no zero-padding ambiguity)
create unique index purchase_documents_supplier_voucher_uidx
  on public.purchase_documents (
    organization_id, supplier_id, document_type, point_of_sale, document_number
  )
  where point_of_sale is not null
    and document_number is not null
    and status is distinct from 'REJECTED';
create index purchase_documents_org_status_date_idx
  on public.purchase_documents (organization_id, status, issue_date desc);
create index purchase_documents_org_supplier_idx
  on public.purchase_documents (organization_id, supplier_id, issue_date desc);
create index purchase_documents_org_due_idx
  on public.purchase_documents (organization_id, due_date)
  where due_date is not null;
create index purchase_documents_po_idx
  on public.purchase_documents (purchase_order_id)
  where purchase_order_id is not null;
create index purchase_documents_journal_idx
  on public.purchase_documents (journal_entry_id)
  where journal_entry_id is not null;
create index purchase_documents_related_idx
  on public.purchase_documents (related_purchase_document_id)
  where related_purchase_document_id is not null;
create index purchase_documents_created_by_idx
  on public.purchase_documents (created_by)
  where created_by is not null;
create trigger purchase_documents_set_updated_at
before update on public.purchase_documents
for each row execute function public.set_updated_at();
create table public.purchase_document_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  purchase_document_id uuid not null,
  line_number int not null check (line_number > 0),
  description text not null check (length(trim(description)) >= 1),
  quantity numeric(18, 4) not null check (quantity > 0),
  unit_code public.purchase_line_unit_code not null default 'UNIT',
  unit_price numeric(19, 4) not null check (unit_price >= 0),
  discount_amount numeric(19, 4) not null default 0 check (discount_amount >= 0),
  vat_treatment public.purchase_vat_treatment not null default 'TAXED',
  vat_rate_code text,
  vat_rate numeric(7, 4) check (vat_rate is null or (vat_rate >= 0 and vat_rate <= 100)),
  net_amount numeric(19, 4) not null default 0 check (net_amount >= 0),
  vat_amount numeric(19, 4) not null default 0 check (vat_amount >= 0),
  exempt_amount numeric(19, 4) not null default 0 check (exempt_amount >= 0),
  untaxed_amount numeric(19, 4) not null default 0 check (untaxed_amount >= 0),
  line_total numeric(19, 4) not null default 0 check (line_total >= 0),
  account_id uuid,
  cost_center_id uuid,
  future_product_id uuid,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (purchase_document_id, line_number),
  constraint purchase_document_lines_org_doc_fk
    foreign key (organization_id, purchase_document_id)
    references public.purchase_documents (organization_id, id)
    on delete cascade,
  constraint purchase_document_lines_org_account_fk
    foreign key (organization_id, account_id)
    references public.accounts (organization_id, id)
    on delete restrict
);
create index purchase_document_lines_org_doc_idx
  on public.purchase_document_lines (organization_id, purchase_document_id);
create index purchase_document_lines_account_idx
  on public.purchase_document_lines (organization_id, account_id)
  where account_id is not null;
create trigger purchase_document_lines_set_updated_at
before update on public.purchase_document_lines
for each row execute function public.set_updated_at();
create table public.purchase_document_tax_summaries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  purchase_document_id uuid not null,
  summary_kind text not null check (summary_kind in ('IVA', 'OTHER')),
  code text not null,
  base_amount numeric(19, 4) not null default 0,
  rate numeric(7, 4),
  amount numeric(19, 4) not null default 0,
  unique (purchase_document_id, summary_kind, code),
  constraint purchase_tax_summaries_org_doc_fk
    foreign key (organization_id, purchase_document_id)
    references public.purchase_documents (organization_id, id)
    on delete cascade
);
create index purchase_tax_summaries_org_doc_idx
  on public.purchase_document_tax_summaries (organization_id, purchase_document_id);
comment on column public.purchase_documents.vat_amount is
  'IVA INFORMADO on supplier document capture — NOT automatic IVA crédito fiscal eligibility.';
