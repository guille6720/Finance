-- Phase 6 — Accounts payable + accounting mappings + immutability

create table public.accounts_payable_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  supplier_id uuid not null,
  purchase_document_id uuid not null,
  direction public.accounts_payable_direction not null,
  original_amount numeric(19, 4) not null check (original_amount >= 0),
  open_amount numeric(19, 4) not null check (open_amount >= 0),
  currency_code text not null default 'ARS' check (currency_code = 'ARS'),
  due_date date,
  status public.accounts_payable_status not null default 'OPEN',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (purchase_document_id),
  constraint accounts_payable_items_org_id_unique unique (organization_id, id),
  constraint accounts_payable_items_org_supplier_fk
    foreign key (organization_id, supplier_id)
    references public.counterparties (organization_id, id)
    on delete restrict,
  constraint accounts_payable_items_org_doc_fk
    foreign key (organization_id, purchase_document_id)
    references public.purchase_documents (organization_id, id)
    on delete restrict,
  constraint accounts_payable_open_lte_original check (open_amount <= original_amount)
);
create index accounts_payable_items_org_status_due_idx
  on public.accounts_payable_items (organization_id, status, due_date);
create index accounts_payable_items_org_supplier_idx
  on public.accounts_payable_items (organization_id, supplier_id);
create trigger accounts_payable_items_set_updated_at
before update on public.accounts_payable_items
for each row execute function public.set_updated_at();
-- Browser must not rewrite AP balances
create or replace function public.prevent_ap_client_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if current_setting('purchase.engine_write', true) is distinct from '1' then
      raise exception 'accounts payable items cannot be deleted directly';
    end if;
    return old;
  end if;
  if current_setting('purchase.engine_write', true) is distinct from '1' then
    if new.open_amount is distinct from old.open_amount
      or new.original_amount is distinct from old.original_amount
      or new.direction is distinct from old.direction
      or new.status is distinct from old.status
      or new.purchase_document_id is distinct from old.purchase_document_id
      or new.supplier_id is distinct from old.supplier_id
    then
      raise exception 'accounts payable monetary/status fields are engine-only';
    end if;
  end if;
  return new;
end;
$$;
create trigger accounts_payable_items_engine_only
before update or delete on public.accounts_payable_items
for each row execute function public.prevent_ap_client_mutation();
-- Purchase accounting mappings
create table public.purchase_accounting_mappings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  accounts_payable_account_id uuid not null,
  vat_input_account_id uuid not null,
  default_expense_account_id uuid,
  other_taxes_account_id uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id),
  constraint purchase_acct_map_ap_fk
    foreign key (organization_id, accounts_payable_account_id)
    references public.accounts (organization_id, id) on delete restrict,
  constraint purchase_acct_map_vat_fk
    foreign key (organization_id, vat_input_account_id)
    references public.accounts (organization_id, id) on delete restrict,
  constraint purchase_acct_map_expense_fk
    foreign key (organization_id, default_expense_account_id)
    references public.accounts (organization_id, id) on delete restrict,
  constraint purchase_acct_map_other_fk
    foreign key (organization_id, other_taxes_account_id)
    references public.accounts (organization_id, id) on delete restrict
);
create index purchase_acct_map_ap_idx
  on public.purchase_accounting_mappings (organization_id, accounts_payable_account_id);
create index purchase_acct_map_vat_idx
  on public.purchase_accounting_mappings (organization_id, vat_input_account_id);
create index purchase_acct_map_expense_idx
  on public.purchase_accounting_mappings (organization_id, default_expense_account_id)
  where default_expense_account_id is not null;
create index purchase_acct_map_other_idx
  on public.purchase_accounting_mappings (organization_id, other_taxes_account_id)
  where other_taxes_account_id is not null;
create trigger purchase_accounting_mappings_set_updated_at
before update on public.purchase_accounting_mappings
for each row execute function public.set_updated_at();
-- Attachments metadata
create table public.purchase_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  purchase_document_id uuid not null,
  kind public.purchase_attachment_kind not null default 'SUPPLIER_PDF',
  storage_bucket text not null default 'purchase-evidence',
  storage_path text not null,
  original_filename text not null,
  mime_type text not null,
  size_bytes bigint not null check (size_bytes >= 0),
  sha256_hash text,
  uploaded_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  constraint purchase_attachments_org_doc_fk
    foreign key (organization_id, purchase_document_id)
    references public.purchase_documents (organization_id, id)
    on delete cascade,
  unique (organization_id, storage_path)
);
create index purchase_attachments_org_doc_idx
  on public.purchase_attachments (organization_id, purchase_document_id);
create index purchase_attachments_uploaded_by_idx
  on public.purchase_attachments (uploaded_by)
  where uploaded_by is not null;
comment on column public.purchase_attachments.sha256_hash is
  'Evidence integrity only — NOT a legal digital signature.';
-- Posted document immutability
create or replace function public.prevent_posted_purchase_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status in ('POSTED', 'REVERSED') then
      raise exception 'posted/reversed purchase documents cannot be deleted';
    end if;
    return old;
  end if;

  if old.status in ('POSTED', 'REVERSED')
    and current_setting('purchase.engine_write', true) is distinct from '1' then
    if new.supplier_id is distinct from old.supplier_id
      or new.document_type is distinct from old.document_type
      or new.point_of_sale is distinct from old.point_of_sale
      or new.document_number is distinct from old.document_number
      or new.issue_date is distinct from old.issue_date
      or new.total_amount is distinct from old.total_amount
      or new.vat_amount is distinct from old.vat_amount
      or new.net_taxed_amount is distinct from old.net_taxed_amount
      or new.supplier_snapshot is distinct from old.supplier_snapshot
      or new.currency_code is distinct from old.currency_code
      or new.status is distinct from old.status
      or new.related_purchase_document_id is distinct from old.related_purchase_document_id
    then
      raise exception 'posted purchase documents are commercially immutable';
    end if;
  end if;
  return new;
end;
$$;
create trigger purchase_documents_prevent_posted_mutation
before update or delete on public.purchase_documents
for each row execute function public.prevent_posted_purchase_mutation();
create or replace function public.prevent_posted_purchase_line_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_status public.purchase_document_status;
begin
  select status into v_status
  from public.purchase_documents
  where id = coalesce(new.purchase_document_id, old.purchase_document_id);

  if v_status in ('POSTED', 'REVERSED')
    and current_setting('purchase.engine_write', true) is distinct from '1' then
    raise exception 'lines on posted purchase documents cannot be modified';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger purchase_document_lines_prevent_posted_mutation
before insert or update or delete on public.purchase_document_lines
for each row execute function public.prevent_posted_purchase_line_mutation();
