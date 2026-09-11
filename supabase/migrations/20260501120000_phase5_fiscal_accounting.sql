-- Phase 5 — Fiscal accounting mappings + sales handoff columns

-- Ensure accounts have composite unique for FKs (before mapping table)
do $$ begin
  alter table public.accounts
    add constraint accounts_org_id_unique unique (organization_id, id);
exception
  when duplicate_object then null;
end $$;
create table public.fiscal_accounting_mappings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  sales_account_id uuid not null,
  vat_output_account_id uuid not null,
  receivables_account_id uuid not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id),
  constraint fiscal_accounting_mappings_sales_fk
    foreign key (organization_id, sales_account_id)
    references public.accounts (organization_id, id)
    on delete restrict,
  constraint fiscal_accounting_mappings_vat_fk
    foreign key (organization_id, vat_output_account_id)
    references public.accounts (organization_id, id)
    on delete restrict,
  constraint fiscal_accounting_mappings_recv_fk
    foreign key (organization_id, receivables_account_id)
    references public.accounts (organization_id, id)
    on delete restrict
);
create trigger fiscal_accounting_mappings_set_updated_at
before update on public.fiscal_accounting_mappings
for each row execute function public.set_updated_at();
-- Sales handoff pointer (set only by fiscal engine)
alter table public.sales_documents
  add column if not exists invoiced_fiscal_document_id uuid;
do $$ begin
  alter table public.sales_documents
    add constraint sales_documents_invoiced_fiscal_fk
    foreign key (invoiced_fiscal_document_id)
    references public.fiscal_documents (id)
    on delete restrict;
exception when duplicate_object then null;
end $$;
create index if not exists sales_documents_invoiced_fiscal_idx
  on public.sales_documents (invoiced_fiscal_document_id)
  where invoiced_fiscal_document_id is not null;
comment on table public.fiscal_accounting_mappings is
  'Per-org mapping for fiscal sale posting: sales revenue, IVA débito fiscal, receivables.';
