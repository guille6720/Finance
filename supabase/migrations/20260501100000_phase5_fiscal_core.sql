-- Phase 5 — Fiscal core (STAGING / HOMOLOGATION)
-- No production ARCA. CAEA disabled by default.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.fiscal_environment as enum ('HOMOLOGATION', 'PRODUCTION');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.fiscal_document_status as enum (
    'DRAFT', 'READY_TO_AUTHORIZE', 'AUTHORIZING', 'AUTHORIZED',
    'REJECTED', 'RECONCILIATION_REQUIRED'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.fiscal_accounting_status as enum (
    'NOT_APPLICABLE', 'PENDING', 'POSTED', 'ERROR', 'REQUIRES_REVIEW'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.fiscal_authorization_outcome as enum (
    'APPROVED', 'REJECTED', 'TRANSPORT_ERROR', 'AUTH_ERROR',
    'BUSINESS_VALIDATION_ERROR', 'UNCERTAIN',
    'RECONCILED_AUTHORIZED', 'RECONCILED_NOT_FOUND'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.fiscal_issuance_method as enum (
    'WSFE_CAE', 'WSFE_CAEA', 'OTHER'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.fiscal_credential_status as enum (
    'ACTIVE', 'EXPIRING', 'EXPIRED', 'REVOKED'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.fiscal_vat_treatment as enum (
    'TAXED', 'EXEMPT', 'NOT_TAXED'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.fiscal_document_class as enum (
    'A', 'B', 'C', 'M', 'E', 'OTHER'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.fiscal_operation_kind as enum (
    'INVOICE', 'CREDIT_NOTE', 'DEBIT_NOTE', 'OTHER'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.fiscal_rule_status as enum (
    'DRAFT', 'REVIEWED', 'ACTIVE', 'RETIRED'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.fiscal_relationship_type as enum (
    'CREDIT_NOTE', 'DEBIT_NOTE'
  );
exception when duplicate_object then null;
end $$;
-- Sales handoff: INVOICED
do $$ begin
  alter type public.sales_document_status add value if not exists 'INVOICED';
exception when duplicate_object then null;
end $$;
-- Feature catalog
insert into public.feature_catalog (code, name, description, category, default_status, sort_order)
values (
  'fiscal_invoicing',
  'Facturación fiscal',
  'Emisión electrónica ARCA (CAE). Depende conceptualmente de ventas y contabilidad.',
  'contabilidad',
  'disabled',
  105
)
on conflict (code) do nothing;
-- ---------------------------------------------------------------------------
-- fiscal_rule_versions
-- ---------------------------------------------------------------------------

create table public.fiscal_rule_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations (id) on delete cascade,
  code text not null,
  version int not null check (version > 0),
  effective_from date not null,
  effective_to date,
  source_reference text not null,
  source_document text,
  status public.fiscal_rule_status not null default 'DRAFT',
  rules jsonb not null default '{}'::jsonb,
  reviewed_by uuid references auth.users (id),
  reviewed_at timestamptz,
  activated_by uuid references auth.users (id),
  activated_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint fiscal_rule_versions_dates check (
    effective_to is null or effective_to >= effective_from
  ),
  unique (organization_id, code, version)
);
create unique index fiscal_rule_versions_global_code_version_uidx
  on public.fiscal_rule_versions (code, version)
  where organization_id is null;
create trigger fiscal_rule_versions_set_updated_at
before update on public.fiscal_rule_versions
for each row execute function public.set_updated_at();
-- ACTIVE rules immutable
create or replace function public.prevent_active_fiscal_rule_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status = 'ACTIVE' then
      raise exception 'active fiscal rule versions cannot be deleted';
    end if;
    return old;
  end if;
  if old.status = 'ACTIVE' then
    if new.status is distinct from old.status
      or new.rules is distinct from old.rules
      or new.effective_from is distinct from old.effective_from
      or new.effective_to is distinct from old.effective_to
      or new.source_reference is distinct from old.source_reference
      or new.code is distinct from old.code
      or new.version is distinct from old.version
    then
      if current_setting('fiscal.engine_write', true) is distinct from '1' then
        raise exception 'active fiscal rule versions are immutable; create a new version';
      end if;
    end if;
  end if;
  return new;
end;
$$;
create trigger fiscal_rule_versions_immutable_active
before update or delete on public.fiscal_rule_versions
for each row execute function public.prevent_active_fiscal_rule_mutation();
-- ---------------------------------------------------------------------------
-- fiscal_document_types
-- ---------------------------------------------------------------------------

create table public.fiscal_document_types (
  id uuid primary key default gen_random_uuid(),
  internal_code text not null unique,
  arca_cbte_tipo int not null,
  name text not null,
  document_class public.fiscal_document_class not null,
  operation_kind public.fiscal_operation_kind not null,
  enabled_phase5 boolean not null default false,
  effective_from date not null default '2000-01-01',
  effective_to date,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);
create index fiscal_document_types_arca_idx on public.fiscal_document_types (arca_cbte_tipo);
-- ---------------------------------------------------------------------------
-- fiscal_parameter_catalogs
-- ---------------------------------------------------------------------------

create table public.fiscal_parameter_catalogs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations (id) on delete cascade,
  environment public.fiscal_environment not null,
  catalog_kind text not null,
  code text not null,
  label text not null,
  valid_from date,
  valid_to date,
  raw jsonb not null default '{}'::jsonb,
  fetched_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, environment, catalog_kind, code)
);
create index fiscal_parameter_catalogs_kind_idx
  on public.fiscal_parameter_catalogs (environment, catalog_kind);
-- ---------------------------------------------------------------------------
-- fiscal_points_of_sale
-- ---------------------------------------------------------------------------

create table public.fiscal_points_of_sale (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  environment public.fiscal_environment not null default 'HOMOLOGATION',
  arca_point_of_sale int not null check (arca_point_of_sale > 0),
  description text,
  issuance_method public.fiscal_issuance_method not null default 'WSFE_CAE',
  is_active boolean not null default true,
  effective_from date,
  effective_to date,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, environment, arca_point_of_sale),
  constraint fiscal_pos_org_id_unique unique (organization_id, id),
  constraint fiscal_pos_org_branch_fk
    foreign key (organization_id, branch_id)
    references public.branches (organization_id, id)
    on delete restrict
);
create trigger fiscal_points_of_sale_set_updated_at
before update on public.fiscal_points_of_sale
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- fiscal_credential_metadata (NO secrets)
-- ---------------------------------------------------------------------------

create table public.fiscal_credential_metadata (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  environment public.fiscal_environment not null,
  certificate_alias text not null,
  certificate_fingerprint text not null,
  valid_from timestamptz,
  valid_to timestamptz,
  status public.fiscal_credential_status not null default 'ACTIVE',
  secret_provider text not null default 'env_file',
  secret_ref text not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, environment, certificate_fingerprint)
);
create trigger fiscal_credential_metadata_set_updated_at
before update on public.fiscal_credential_metadata
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- fiscal_service_profiles
-- ---------------------------------------------------------------------------

create table public.fiscal_service_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  environment public.fiscal_environment not null default 'HOMOLOGATION',
  wsaa_service_name text not null default 'wsfe',
  enabled_methods jsonb not null default '{"cae": true, "caea": false}'::jsonb,
  timeouts_ms jsonb not null default '{"connect": 10000, "request": 60000}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, environment)
);
create trigger fiscal_service_profiles_set_updated_at
before update on public.fiscal_service_profiles
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- fiscal_documents
-- ---------------------------------------------------------------------------

create table public.fiscal_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  branch_id uuid,
  sales_document_id uuid,
  fiscal_environment public.fiscal_environment not null default 'HOMOLOGATION',
  service_provider text not null default 'ARCA_WSFE',
  document_type_id uuid not null references public.fiscal_document_types (id),
  document_class public.fiscal_document_class not null,
  arca_cbte_tipo int not null,
  point_of_sale_id uuid not null,
  arca_point_of_sale int not null,
  document_number bigint,
  issue_date date not null,
  counterparty_id uuid not null,
  issuer_snapshot jsonb not null default '{}'::jsonb,
  receiver_snapshot jsonb not null default '{}'::jsonb,
  currency_code text not null default 'PES' check (currency_code ~ '^[A-Z]{3}$'),
  currency_rate numeric(19, 6) not null default 1 check (currency_rate > 0),
  concept_type int not null default 1 check (concept_type between 1 and 3),
  net_taxed_amount numeric(19, 4) not null default 0 check (net_taxed_amount >= 0),
  net_exempt_amount numeric(19, 4) not null default 0 check (net_exempt_amount >= 0),
  net_untaxed_amount numeric(19, 4) not null default 0 check (net_untaxed_amount >= 0),
  vat_amount numeric(19, 4) not null default 0 check (vat_amount >= 0),
  other_taxes_amount numeric(19, 4) not null default 0 check (other_taxes_amount >= 0),
  total_amount numeric(19, 4) not null default 0 check (total_amount >= 0),
  status public.fiscal_document_status not null default 'DRAFT',
  accounting_status public.fiscal_accounting_status not null default 'NOT_APPLICABLE',
  journal_entry_id uuid,
  cae text,
  cae_expiration_date date,
  arca_result jsonb not null default '{}'::jsonb,
  arca_observations jsonb not null default '[]'::jsonb,
  authorized_at timestamptz,
  related_fiscal_document_id uuid,
  relationship_type public.fiscal_relationship_type,
  fiscal_rule_version_id uuid not null references public.fiscal_rule_versions (id),
  credential_fingerprint text,
  idempotency_key text not null,
  qr_payload text,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint fiscal_documents_org_id_unique unique (organization_id, id),
  constraint fiscal_documents_idempotency_unique unique (organization_id, idempotency_key),
  constraint fiscal_documents_org_counterparty_fk
    foreign key (organization_id, counterparty_id)
    references public.counterparties (organization_id, id)
    on delete restrict,
  constraint fiscal_documents_org_branch_fk
    foreign key (organization_id, branch_id)
    references public.branches (organization_id, id)
    on delete restrict,
  constraint fiscal_documents_org_pos_fk
    foreign key (organization_id, point_of_sale_id)
    references public.fiscal_points_of_sale (organization_id, id)
    on delete restrict,
  constraint fiscal_documents_sales_fk
    foreign key (sales_document_id)
    references public.sales_documents (id)
    on delete restrict,
  constraint fiscal_documents_related_fk
    foreign key (related_fiscal_document_id)
    references public.fiscal_documents (id)
    on delete restrict,
  constraint fiscal_documents_journal_fk
    foreign key (journal_entry_id)
    references public.journal_entries (id)
    on delete restrict,
  constraint fiscal_documents_ars_rate_check check (
    currency_code not in ('PES', 'ARS') or currency_rate = 1
  )
);
create unique index fiscal_documents_primary_invoice_per_order_uidx
  on public.fiscal_documents (organization_id, sales_document_id)
  where sales_document_id is not null and relationship_type is null;
create unique index fiscal_documents_voucher_uidx
  on public.fiscal_documents (
    organization_id, fiscal_environment, arca_point_of_sale, arca_cbte_tipo, document_number
  )
  where document_number is not null;
create index fiscal_documents_org_status_date_idx
  on public.fiscal_documents (organization_id, status, issue_date desc);
create index fiscal_documents_sales_idx
  on public.fiscal_documents (sales_document_id)
  where sales_document_id is not null;
create trigger fiscal_documents_set_updated_at
before update on public.fiscal_documents
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- fiscal_document_lines
-- ---------------------------------------------------------------------------

create table public.fiscal_document_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  fiscal_document_id uuid not null,
  line_number int not null check (line_number > 0),
  source_sales_line_id uuid,
  description text not null check (length(trim(description)) >= 1),
  quantity numeric(18, 4) not null check (quantity > 0),
  unit_price numeric(19, 4) not null check (unit_price >= 0),
  discount_amount numeric(19, 4) not null default 0 check (discount_amount >= 0),
  vat_treatment public.fiscal_vat_treatment not null default 'TAXED',
  vat_rate_code text,
  vat_rate numeric(7, 4) check (vat_rate is null or (vat_rate >= 0 and vat_rate <= 100)),
  net_amount numeric(19, 4) not null default 0 check (net_amount >= 0),
  vat_amount numeric(19, 4) not null default 0 check (vat_amount >= 0),
  exempt_amount numeric(19, 4) not null default 0 check (exempt_amount >= 0),
  untaxed_amount numeric(19, 4) not null default 0 check (untaxed_amount >= 0),
  line_total numeric(19, 4) not null default 0 check (line_total >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (fiscal_document_id, line_number),
  constraint fiscal_document_lines_org_doc_fk
    foreign key (organization_id, fiscal_document_id)
    references public.fiscal_documents (organization_id, id)
    on delete cascade
);
create index fiscal_document_lines_org_doc_idx
  on public.fiscal_document_lines (organization_id, fiscal_document_id);
create trigger fiscal_document_lines_set_updated_at
before update on public.fiscal_document_lines
for each row execute function public.set_updated_at();
-- ---------------------------------------------------------------------------
-- fiscal_tax_summaries
-- ---------------------------------------------------------------------------

create table public.fiscal_tax_summaries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  fiscal_document_id uuid not null,
  summary_kind text not null check (summary_kind in ('IVA', 'TRIBUTO')),
  code text not null,
  base_amount numeric(19, 4) not null default 0,
  rate numeric(7, 4),
  amount numeric(19, 4) not null default 0,
  unique (fiscal_document_id, summary_kind, code),
  constraint fiscal_tax_summaries_org_doc_fk
    foreign key (organization_id, fiscal_document_id)
    references public.fiscal_documents (organization_id, id)
    on delete cascade
);
-- ---------------------------------------------------------------------------
-- fiscal_authorization_attempts (append-oriented; no raw SOAP by default)
-- ---------------------------------------------------------------------------

create table public.fiscal_authorization_attempts (
  id uuid primary key default gen_random_uuid(),
  fiscal_document_id uuid not null,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  attempt_number int not null check (attempt_number > 0),
  environment public.fiscal_environment not null,
  service text not null default 'wsfe',
  requested_pos int not null,
  requested_cbte_tipo int not null,
  requested_document_number bigint,
  certificate_fingerprint text,
  request_hash text,
  started_at timestamptz not null default timezone('utc', now()),
  completed_at timestamptz,
  outcome public.fiscal_authorization_outcome,
  arca_error_codes jsonb not null default '[]'::jsonb,
  arca_observation_codes jsonb not null default '[]'::jsonb,
  transport_error_class text,
  correlation_id text not null,
  cae text,
  cae_expiration_date date,
  unique (fiscal_document_id, attempt_number),
  constraint fiscal_auth_attempts_org_doc_fk
    foreign key (organization_id, fiscal_document_id)
    references public.fiscal_documents (organization_id, id)
    on delete cascade
);
create index fiscal_authorization_attempts_doc_idx
  on public.fiscal_authorization_attempts (fiscal_document_id, attempt_number);
-- ---------------------------------------------------------------------------
-- Authorized immutability
-- ---------------------------------------------------------------------------

create or replace function public.prevent_authorized_fiscal_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status = 'AUTHORIZED' then
      raise exception 'authorized fiscal documents cannot be deleted';
    end if;
    return old;
  end if;

  if old.status = 'AUTHORIZED'
    and current_setting('fiscal.engine_write', true) is distinct from '1' then
    if new.issuer_snapshot is distinct from old.issuer_snapshot
      or new.receiver_snapshot is distinct from old.receiver_snapshot
      or new.document_type_id is distinct from old.document_type_id
      or new.arca_cbte_tipo is distinct from old.arca_cbte_tipo
      or new.arca_point_of_sale is distinct from old.arca_point_of_sale
      or new.document_number is distinct from old.document_number
      or new.issue_date is distinct from old.issue_date
      or new.currency_code is distinct from old.currency_code
      or new.currency_rate is distinct from old.currency_rate
      or new.net_taxed_amount is distinct from old.net_taxed_amount
      or new.net_exempt_amount is distinct from old.net_exempt_amount
      or new.net_untaxed_amount is distinct from old.net_untaxed_amount
      or new.vat_amount is distinct from old.vat_amount
      or new.other_taxes_amount is distinct from old.other_taxes_amount
      or new.total_amount is distinct from old.total_amount
      or new.cae is distinct from old.cae
      or new.cae_expiration_date is distinct from old.cae_expiration_date
      or new.sales_document_id is distinct from old.sales_document_id
      or new.related_fiscal_document_id is distinct from old.related_fiscal_document_id
      or new.qr_payload is distinct from old.qr_payload
      or new.status is distinct from old.status
    then
      raise exception 'authorized fiscal documents are commercially/fiscally immutable';
    end if;
  end if;
  return new;
end;
$$;
create trigger fiscal_documents_prevent_authorized_mutation
before update or delete on public.fiscal_documents
for each row execute function public.prevent_authorized_fiscal_mutation();
create or replace function public.prevent_authorized_fiscal_line_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_status public.fiscal_document_status;
begin
  select status into v_status
  from public.fiscal_documents
  where id = coalesce(new.fiscal_document_id, old.fiscal_document_id);

  if v_status = 'AUTHORIZED'
    and current_setting('fiscal.engine_write', true) is distinct from '1' then
    raise exception 'lines on authorized fiscal documents cannot be modified';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger fiscal_document_lines_prevent_authorized_mutation
before insert or update or delete on public.fiscal_document_lines
for each row execute function public.prevent_authorized_fiscal_line_mutation();
create or replace function public.prevent_authorized_fiscal_summary_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_status public.fiscal_document_status;
begin
  select status into v_status
  from public.fiscal_documents
  where id = coalesce(new.fiscal_document_id, old.fiscal_document_id);

  if v_status = 'AUTHORIZED'
    and current_setting('fiscal.engine_write', true) is distinct from '1' then
    raise exception 'tax summaries on authorized fiscal documents cannot be modified';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger fiscal_tax_summaries_prevent_authorized_mutation
before insert or update or delete on public.fiscal_tax_summaries
for each row execute function public.prevent_authorized_fiscal_summary_mutation();
