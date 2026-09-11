-- Phase 9: POS core enums + tables
-- Orchestration only — commercial truth remains sales_documents / lines.

do $$ begin
  create type public.pos_session_status as enum ('OPEN', 'CLOSED');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.pos_sale_status as enum (
    'DRAFT',
    'READY_TO_CHECKOUT',
    'STOCK_RESERVED',
    'WAITING_FISCAL',
    'FISCAL_AUTHORIZED',
    'FINALIZING',
    'COMPLETED',
    'CANCELLED',
    'RECONCILIATION_REQUIRED'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.pos_tender_method as enum (
    'CASH', 'BANK_TRANSFER', 'CARD', 'QR'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.pos_tender_status as enum (
    'DRAFT', 'POSTED', 'REVERSED'
  );
exception when duplicate_object then null;
end $$;
-- ---------------------------------------------------------------------------
-- pos_settings (1:1 org)
-- ---------------------------------------------------------------------------

create table if not exists public.pos_settings (
  organization_id uuid primary key references public.organizations (id) on delete cascade,
  default_walk_in_customer_id uuid not null,
  default_document_type_internal_code text,
  default_condicion_iva_receptor_id int,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint pos_settings_walk_in_fk
    foreign key (organization_id, default_walk_in_customer_id)
    references public.counterparties (organization_id, id)
    on delete restrict
);
create index if not exists pos_settings_walk_in_idx
  on public.pos_settings (default_walk_in_customer_id);
create trigger pos_settings_set_updated_at
before update on public.pos_settings
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- pos_terminals
-- ---------------------------------------------------------------------------

create table if not exists public.pos_terminals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid not null,
  code text not null,
  name text not null,
  warehouse_id uuid not null,
  default_customer_id uuid,
  fiscal_point_of_sale_id uuid,
  active boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint pos_terminals_org_id_unique unique (organization_id, id),
  constraint pos_terminals_code_unique unique (organization_id, code),
  constraint pos_terminals_code_check check (length(btrim(code)) >= 1 and length(btrim(code)) <= 32),
  constraint pos_terminals_name_check check (length(btrim(name)) >= 1),
  constraint pos_terminals_org_branch_fk
    foreign key (organization_id, branch_id)
    references public.branches (organization_id, id) on delete restrict,
  constraint pos_terminals_org_wh_fk
    foreign key (organization_id, warehouse_id)
    references public.warehouses (organization_id, id) on delete restrict,
  constraint pos_terminals_org_customer_fk
    foreign key (organization_id, default_customer_id)
    references public.counterparties (organization_id, id) on delete restrict,
  constraint pos_terminals_fiscal_pos_fk
    foreign key (fiscal_point_of_sale_id)
    references public.fiscal_points_of_sale (id) on delete restrict
);
create index if not exists pos_terminals_org_branch_idx
  on public.pos_terminals (organization_id, branch_id);
create index if not exists pos_terminals_warehouse_idx
  on public.pos_terminals (organization_id, warehouse_id);
create index if not exists pos_terminals_fiscal_pos_idx
  on public.pos_terminals (fiscal_point_of_sale_id)
  where fiscal_point_of_sale_id is not null;
create index if not exists pos_terminals_created_by_idx
  on public.pos_terminals (created_by) where created_by is not null;
create trigger pos_terminals_set_updated_at
before update on public.pos_terminals
for each row execute function public.set_updated_at();
comment on column public.pos_terminals.code is
  'Internal retail terminal code (e.g. POS-01). NOT an ARCA punto de venta.';
-- ---------------------------------------------------------------------------
-- pos_sessions
-- ---------------------------------------------------------------------------

create table if not exists public.pos_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  terminal_id uuid not null,
  cashier_id uuid not null references auth.users (id),
  status public.pos_session_status not null default 'OPEN',
  opened_at timestamptz not null default timezone('utc', now()),
  closed_at timestamptz,
  opening_expected_cash numeric(19, 4) not null default 0,
  opening_counted_cash numeric(19, 4),
  closing_expected_cash numeric(19, 4),
  closing_counted_cash numeric(19, 4),
  closing_difference numeric(19, 4),
  idempotency_key text not null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint pos_sessions_org_id_unique unique (organization_id, id),
  constraint pos_sessions_idempotency_unique unique (organization_id, idempotency_key),
  constraint pos_sessions_org_terminal_fk
    foreign key (organization_id, terminal_id)
    references public.pos_terminals (organization_id, id) on delete restrict,
  constraint pos_sessions_closed_check check (
    (status = 'OPEN' and closed_at is null)
    or (status = 'CLOSED' and closed_at is not null)
  )
);
create unique index if not exists pos_sessions_one_open_per_terminal
  on public.pos_sessions (terminal_id)
  where status = 'OPEN';
create index if not exists pos_sessions_org_cashier_idx
  on public.pos_sessions (organization_id, cashier_id, opened_at desc);
create index if not exists pos_sessions_terminal_idx
  on public.pos_sessions (terminal_id, status);
-- ---------------------------------------------------------------------------
-- pos_sales
-- ---------------------------------------------------------------------------

create table if not exists public.pos_sales (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  terminal_id uuid not null,
  session_id uuid not null,
  sales_document_id uuid not null,
  fiscal_document_id uuid,
  status public.pos_sale_status not null default 'DRAFT',
  idempotency_key text not null,
  cash_received numeric(19, 4),
  change_given numeric(19, 4),
  checkout_started_at timestamptz,
  completed_at timestamptz,
  inventory_operation_id uuid,
  created_by uuid references auth.users (id),
  completed_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint pos_sales_org_id_unique unique (organization_id, id),
  constraint pos_sales_sales_doc_unique unique (sales_document_id),
  constraint pos_sales_idempotency_unique unique (organization_id, idempotency_key),
  constraint pos_sales_inventory_op_unique unique (inventory_operation_id),
  constraint pos_sales_org_terminal_fk
    foreign key (organization_id, terminal_id)
    references public.pos_terminals (organization_id, id) on delete restrict,
  constraint pos_sales_org_session_fk
    foreign key (organization_id, session_id)
    references public.pos_sessions (organization_id, id) on delete restrict,
  constraint pos_sales_sales_doc_fk
    foreign key (sales_document_id)
    references public.sales_documents (id) on delete restrict,
  constraint pos_sales_fiscal_doc_fk
    foreign key (fiscal_document_id)
    references public.fiscal_documents (id) on delete restrict,
  constraint pos_sales_inventory_op_fk
    foreign key (inventory_operation_id)
    references public.inventory_operations (id) on delete restrict,
  constraint pos_sales_change_check check (
    (cash_received is null and change_given is null)
    or (cash_received is not null and change_given is not null and cash_received >= 0 and change_given >= 0)
  )
);
create index if not exists pos_sales_session_status_idx
  on public.pos_sales (session_id, status);
create index if not exists pos_sales_org_status_idx
  on public.pos_sales (organization_id, status, created_at desc);
create index if not exists pos_sales_fiscal_idx
  on public.pos_sales (fiscal_document_id) where fiscal_document_id is not null;
create index if not exists pos_sales_terminal_idx
  on public.pos_sales (terminal_id, created_at desc);
create trigger pos_sales_set_updated_at
before update on public.pos_sales
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- pos_tenders
-- ---------------------------------------------------------------------------

create table if not exists public.pos_tenders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  pos_sale_id uuid not null,
  method public.pos_tender_method not null,
  treasury_account_id uuid not null,
  amount numeric(19, 4) not null check (amount > 0),
  cash_received numeric(19, 4),
  change_given numeric(19, 4),
  reference text,
  provider_label text,
  status public.pos_tender_status not null default 'DRAFT',
  treasury_operation_id uuid,
  idempotency_key text not null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint pos_tenders_org_id_unique unique (organization_id, id),
  constraint pos_tenders_idempotency_unique unique (organization_id, idempotency_key),
  constraint pos_tenders_treasury_op_unique unique (treasury_operation_id),
  constraint pos_tenders_org_sale_fk
    foreign key (organization_id, pos_sale_id)
    references public.pos_sales (organization_id, id) on delete cascade,
  constraint pos_tenders_org_account_fk
    foreign key (organization_id, treasury_account_id)
    references public.treasury_accounts (organization_id, id) on delete restrict,
  constraint pos_tenders_treasury_op_fk
    foreign key (treasury_operation_id)
    references public.treasury_operations (id) on delete restrict,
  constraint pos_tenders_cash_meta_check check (
    (
      method = 'CASH'
      and (
        cash_received is null
        or (
          cash_received >= amount
          and change_given is not null
          and change_given = cash_received - amount
        )
      )
    )
    or (
      method <> 'CASH'
      and cash_received is null
      and change_given is null
    )
  ),
  constraint pos_tenders_no_card_pan_check check (
    reference is null or length(reference) <= 128
  ),
  constraint pos_tenders_provider_check check (
    provider_label is null or length(provider_label) <= 64
  )
);
create index if not exists pos_tenders_sale_idx
  on public.pos_tenders (pos_sale_id);
create index if not exists pos_tenders_account_idx
  on public.pos_tenders (treasury_account_id);
-- ---------------------------------------------------------------------------
-- pos_terminal_tender_accounts
-- ---------------------------------------------------------------------------

create table if not exists public.pos_terminal_tender_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  terminal_id uuid not null,
  method public.pos_tender_method not null,
  treasury_account_id uuid not null,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint pos_tta_org_id_unique unique (organization_id, id),
  constraint pos_tta_org_terminal_fk
    foreign key (organization_id, terminal_id)
    references public.pos_terminals (organization_id, id) on delete cascade,
  constraint pos_tta_org_account_fk
    foreign key (organization_id, treasury_account_id)
    references public.treasury_accounts (organization_id, id) on delete restrict
);
create unique index if not exists pos_tta_terminal_method_active
  on public.pos_terminal_tender_accounts (terminal_id, method)
  where active;
-- One CASH drawer account → one terminal (deterministic session cash)
create unique index if not exists pos_tta_cash_account_one_terminal
  on public.pos_terminal_tender_accounts (treasury_account_id)
  where method = 'CASH' and active;
create index if not exists pos_tta_account_idx
  on public.pos_terminal_tender_accounts (treasury_account_id);
create trigger pos_tta_set_updated_at
before update on public.pos_terminal_tender_accounts
for each row execute function public.set_updated_at();
