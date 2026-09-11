-- Phase 11: analytics metric registry (GLOBAL catalog)
-- STAGING ONLY — additive. Do not rewrite Phase 1–10 migrations.
-- Money / units: never FLOAT. Metric formulas live in reviewed server code keyed by code + calculation_version.

do $$ begin
  create type public.analytics_metric_unit_type as enum (
    'CURRENCY', 'COUNT', 'PERCENT', 'QUANTITY', 'DAYS'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.analytics_metric_domain as enum (
    'EXECUTIVE',
    'FINANCIAL',
    'SALES',
    'PURCHASES',
    'TREASURY',
    'AR',
    'AP',
    'INVENTORY',
    'POS',
    'TAX',
    'ACCOUNTING'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.analytics_metric_comparison as enum (
    'PREV_PERIOD', 'PREV_YEAR', 'NONE'
  );
exception when duplicate_object then null;
end $$;
create table if not exists public.analytics_metric_definitions (
  code text primary key
    check (char_length(code) between 2 and 64 and code = upper(code)),
  name_business text not null check (char_length(trim(name_business)) >= 1),
  name_accountant text not null check (char_length(trim(name_accountant)) >= 1),
  description text not null default '',
  domain public.analytics_metric_domain not null,
  unit_type public.analytics_metric_unit_type not null,
  calculation_version int not null default 1 check (calculation_version >= 1),
  default_comparison public.analytics_metric_comparison not null default 'PREV_PERIOD',
  required_feature text,
  required_permission text,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);
create index if not exists analytics_metric_definitions_domain_idx
  on public.analytics_metric_definitions (domain, active);
create index if not exists analytics_metric_definitions_feature_idx
  on public.analytics_metric_definitions (required_feature)
  where required_feature is not null;
drop trigger if exists analytics_metric_definitions_set_updated_at
  on public.analytics_metric_definitions;
create trigger analytics_metric_definitions_set_updated_at
before update on public.analytics_metric_definitions
for each row execute function public.set_updated_at();
comment on table public.analytics_metric_definitions is
  'GLOBAL controlled metric registry. System-seeded only; no user SQL / no organization_id.';
-- Seed MVP metrics (calculation_version = 1)
insert into public.analytics_metric_definitions (
  code, name_business, name_accountant, description, domain, unit_type,
  calculation_version, default_comparison, required_feature, required_permission, active
) values
  (
    'SALES_FISCAL_GROSS_AUTHORIZED',
    'Ventas facturadas brutas autorizadas',
    'Fiscal AUTHORIZED total_amount × economic sign',
    'Sum fiscal_documents.total_amount with INVOICE/DN +1, CN -1; status=AUTHORIZED; issue_date in period.',
    'SALES', 'CURRENCY', 1, 'PREV_PERIOD', 'fiscal_invoicing', null, true
  ),
  (
    'SALES_FISCAL_NET_AUTHORIZED',
    'Ventas facturadas netas autorizadas',
    'Fiscal AUTHORIZED net bases × economic sign',
    'Sum (net_taxed+net_exempt+net_untaxed) × economic sign; status=AUTHORIZED; issue_date in period.',
    'SALES', 'CURRENCY', 1, 'PREV_PERIOD', 'fiscal_invoicing', null, true
  ),
  (
    'SALES_COMMERCIAL_CONFIRMED',
    'Ventas comerciales confirmadas',
    'Commercial confirmed/invoiced pipeline (secondary)',
    'Sales documents in confirmed/invoiced pipeline — not default Ventas KPI.',
    'SALES', 'CURRENCY', 1, 'PREV_PERIOD', 'sales', null, true
  ),
  (
    'MANAGEMENT_GROSS_RESULT',
    'Resultado bruto gerencial',
    'Revenue − COGS (management P&L)',
    'From analytics_management_pnl: revenue − cogs. Subject to mapping review.',
    'ACCOUNTING', 'CURRENCY', 1, 'PREV_PERIOD', 'accounting', null, true
  ),
  (
    'GROSS_MARGIN',
    'Margen bruto',
    'Fiscal net sales − inventory COGS',
    'Authorized fiscal net basis for stocked goods minus Phase 8 COGS only.',
    'SALES', 'CURRENCY', 1, 'PREV_PERIOD', 'inventory', null, true
  ),
  (
    'GROSS_MARGIN_PCT',
    'Margen bruto %',
    'Gross margin / sales base',
    'Server percent; zero denominator → Sin base comparable.',
    'SALES', 'PERCENT', 1, 'PREV_PERIOD', 'inventory', null, true
  ),
  (
    'COGS_INVENTORY',
    'Costo de mercadería vendida',
    'Inventory issue COGS in period',
    'Phase 8 inventory COGS linked to completed/authorized sales basis.',
    'INVENTORY', 'CURRENCY', 1, 'PREV_PERIOD', 'inventory', null, true
  ),
  (
    'CASH_INTERNAL',
    'Saldo de caja interno',
    'Sum treasury_account_balance(CASH)',
    'Internal cash from POSTED treasury legs only — not bank-confirmed.',
    'TREASURY', 'CURRENCY', 1, 'NONE', 'cash', null, true
  ),
  (
    'BANK_INTERNAL',
    'Saldo bancario interno',
    'Sum treasury_account_balance(BANK)',
    'Internal bank books balance — never labeled bank-confirmed.',
    'TREASURY', 'CURRENCY', 1, 'NONE', 'banks', null, true
  ),
  (
    'CLEARING_PENDING',
    'Tarjetas/QR pendientes de acreditación',
    'Sum treasury_account_balance(CLEARING)',
    'Processor clearing receivable; separate from cash/bank.',
    'TREASURY', 'CURRENCY', 1, 'NONE', 'pos', null, true
  ),
  (
    'AR_OPEN',
    'Cuentas por cobrar abiertas',
    'AR open_amount OPEN+PARTIALLY_COLLECTED',
    'Signed by AR direction; open_amount > 0.',
    'AR', 'CURRENCY', 1, 'NONE', 'sales', null, true
  ),
  (
    'AP_OPEN',
    'Cuentas por pagar abiertas',
    'AP open_amount OPEN+PARTIALLY_PAID',
    'Signed by AP direction; open_amount > 0.',
    'AP', 'CURRENCY', 1, 'NONE', 'purchases', null, true
  ),
  (
    'INVENTORY_VALUE',
    'Inventario valorizado',
    'Sum inventory_cost_state.inventory_value',
    'Engine projection valuation at org+product.',
    'INVENTORY', 'CURRENCY', 1, 'NONE', 'inventory', null, true
  ),
  (
    'TAX_IVA_SALDO_ESTIMADO',
    'IVA — saldo estimado',
    'tax_determinations.totals_snapshot.saldo_estimado',
    'Read-only Phase 10 estimate. Label: Saldo estimado según Contabilium — never definitive DDJJ.',
    'TAX', 'CURRENCY', 1, 'NONE', 'taxes', null, true
  ),
  (
    'TAX_OBLIGATIONS_NEAR',
    'Obligaciones próximas',
    'Open tax obligations near due',
    'Count/list near-due tax_obligations (config days).',
    'TAX', 'COUNT', 1, 'NONE', 'taxes', null, true
  ),
  (
    'COLLECTIONS_POSTED',
    'Cobros reales',
    'Posted COLLECTION treasury ops in period',
    'Sum amount of treasury_operations type COLLECTION status POSTED by operation_date.',
    'TREASURY', 'CURRENCY', 1, 'PREV_PERIOD', 'cash', null, true
  ),
  (
    'PAYMENTS_POSTED',
    'Pagos reales',
    'Posted PAYMENT treasury ops in period',
    'Sum amount of treasury_operations type PAYMENT status POSTED by operation_date.',
    'TREASURY', 'CURRENCY', 1, 'PREV_PERIOD', 'cash', null, true
  ),
  (
    'ACCT_REVENUE',
    'Ingresos contables',
    'GL REVENUE credit−debit POSTED+REVERSED',
    'Economic journal scope status IN (POSTED, REVERSED).',
    'ACCOUNTING', 'CURRENCY', 1, 'PREV_PERIOD', 'accounting', null, true
  ),
  (
    'ACCT_RESULT_EST',
    'Resultado estimado (gerencial)',
    'Management P&L net',
    'analytics_management_pnl.management_result — gerencial interno.',
    'ACCOUNTING', 'CURRENCY', 1, 'PREV_PERIOD', 'accounting', null, true
  ),
  (
    'POS_COMPLETED_COUNT',
    'Ventas POS completadas',
    'pos_sales status=COMPLETED count',
    'Completed POS sales in period (completed_at / sale date).',
    'POS', 'COUNT', 1, 'PREV_PERIOD', 'pos', null, true
  ),
  (
    'PURCHASES_POSTED',
    'Compras contabilizadas',
    'purchase_documents status=POSTED total signed',
    'POSTED purchases in period by accounting_date; CN/DN as separate docs.',
    'PURCHASES', 'CURRENCY', 1, 'PREV_PERIOD', 'purchases', null, true
  )
on conflict (code) do update set
  name_business = excluded.name_business,
  name_accountant = excluded.name_accountant,
  description = excluded.description,
  domain = excluded.domain,
  unit_type = excluded.unit_type,
  calculation_version = excluded.calculation_version,
  default_comparison = excluded.default_comparison,
  required_feature = excluded.required_feature,
  required_permission = excluded.required_permission,
  active = excluded.active,
  updated_at = timezone('utc', now());
alter table public.analytics_metric_definitions enable row level security;
drop policy if exists analytics_metric_definitions_select on public.analytics_metric_definitions;
create policy analytics_metric_definitions_select
  on public.analytics_metric_definitions
  for select to authenticated
  using (true);
-- No insert/update/delete for authenticated (service_role bypasses RLS)
revoke all on table public.analytics_metric_definitions from public, anon;
grant select on table public.analytics_metric_definitions to authenticated;
grant all on table public.analytics_metric_definitions to service_role;
