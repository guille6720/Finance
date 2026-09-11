-- Phase 11: analytics alerts + inventory thresholds
-- Attention Center events are derived; never rewrite source economics.

do $$ begin
  create type public.analytics_alert_severity as enum ('INFO', 'WARNING', 'CRITICAL');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.analytics_alert_status as enum ('OPEN', 'ACKNOWLEDGED', 'RESOLVED');
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.analytics_alert_domain as enum (
    'FINANCE', 'SALES', 'PURCHASES', 'INVENTORY', 'POS', 'FISCAL', 'TAX', 'ACCOUNTING', 'TREASURY'
  );
exception when duplicate_object then null;
end $$;
-- ---------------------------------------------------------------------------
-- analytics_alert_settings
-- ---------------------------------------------------------------------------

create table if not exists public.analytics_alert_settings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  rule_code text not null check (char_length(trim(rule_code)) >= 2),
  enabled boolean not null default true,
  threshold_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint analytics_alert_settings_org_id_unique unique (organization_id, id),
  constraint analytics_alert_settings_org_rule_unique unique (organization_id, rule_code)
);
create index if not exists analytics_alert_settings_org_idx
  on public.analytics_alert_settings (organization_id, enabled);
drop trigger if exists analytics_alert_settings_set_updated_at on public.analytics_alert_settings;
create trigger analytics_alert_settings_set_updated_at
before update on public.analytics_alert_settings
for each row execute function public.set_updated_at();
comment on table public.analytics_alert_settings is
  'Org enable/threshold overrides for Attention Center rules. Validated JSON only.';
-- ---------------------------------------------------------------------------
-- analytics_alert_events
-- ---------------------------------------------------------------------------

create table if not exists public.analytics_alert_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  rule_code text not null check (char_length(trim(rule_code)) >= 2),
  domain public.analytics_alert_domain not null,
  entity_type text,
  entity_id uuid,
  dedup_key text not null check (char_length(trim(dedup_key)) >= 1),
  severity public.analytics_alert_severity not null default 'WARNING',
  status public.analytics_alert_status not null default 'OPEN',
  first_detected_at timestamptz not null default timezone('utc', now()),
  last_detected_at timestamptz not null default timezone('utc', now()),
  resolved_at timestamptz,
  acknowledged_at timestamptz,
  acknowledged_by uuid references auth.users (id) on delete set null,
  payload_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint analytics_alert_events_org_id_unique unique (organization_id, id),
  constraint analytics_alert_events_org_dedup_unique unique (organization_id, dedup_key)
);
create index if not exists analytics_alert_events_org_status_idx
  on public.analytics_alert_events (organization_id, status, severity);
create index if not exists analytics_alert_events_org_rule_idx
  on public.analytics_alert_events (organization_id, rule_code, status);
create index if not exists analytics_alert_events_acknowledged_by_idx
  on public.analytics_alert_events (acknowledged_by)
  where acknowledged_by is not null;
create index if not exists analytics_alert_events_entity_idx
  on public.analytics_alert_events (organization_id, entity_type, entity_id)
  where entity_id is not null;
drop trigger if exists analytics_alert_events_set_updated_at on public.analytics_alert_events;
create trigger analytics_alert_events_set_updated_at
before update on public.analytics_alert_events
for each row execute function public.set_updated_at();
comment on table public.analytics_alert_events is
  'Deduped Attention Center events. ACK ≠ fix; source clear → RESOLVED via evaluate RPC.';
-- ---------------------------------------------------------------------------
-- analytics_inventory_thresholds
-- ---------------------------------------------------------------------------

create table if not exists public.analytics_inventory_thresholds (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  product_id uuid not null,
  warehouse_id uuid,
  minimum_available_quantity numeric(18, 4) not null check (minimum_available_quantity >= 0),
  warning_quantity numeric(18, 4) check (warning_quantity is null or warning_quantity >= 0),
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint analytics_inventory_thresholds_org_id_unique unique (organization_id, id),
  constraint analytics_inventory_thresholds_product_fk
    foreign key (organization_id, product_id)
    references public.products (organization_id, id) on delete cascade,
  constraint analytics_inventory_thresholds_warehouse_fk
    foreign key (organization_id, warehouse_id)
    references public.warehouses (organization_id, id) on delete cascade,
  constraint analytics_inventory_thresholds_warn_lte_min check (
    warning_quantity is null or warning_quantity <= minimum_available_quantity
  )
);
-- Unique: one threshold per org+product+warehouse (null warehouse = org-wide)
create unique index if not exists analytics_inventory_thresholds_scope_uidx
  on public.analytics_inventory_thresholds (
    organization_id,
    product_id,
    (coalesce(warehouse_id, '00000000-0000-0000-0000-000000000000'::uuid))
  );
create index if not exists analytics_inventory_thresholds_org_idx
  on public.analytics_inventory_thresholds (organization_id, active);
create index if not exists analytics_inventory_thresholds_product_idx
  on public.analytics_inventory_thresholds (organization_id, product_id);
create index if not exists analytics_inventory_thresholds_warehouse_idx
  on public.analytics_inventory_thresholds (organization_id, warehouse_id)
  where warehouse_id is not null;
drop trigger if exists analytics_inventory_thresholds_set_updated_at
  on public.analytics_inventory_thresholds;
create trigger analytics_inventory_thresholds_set_updated_at
before update on public.analytics_inventory_thresholds
for each row execute function public.set_updated_at();
comment on table public.analytics_inventory_thresholds is
  'Low-stock warning thresholds only — does not change stock engine rules.';
-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.analytics_alert_settings enable row level security;
alter table public.analytics_alert_events enable row level security;
alter table public.analytics_inventory_thresholds enable row level security;
drop policy if exists analytics_alert_settings_select on public.analytics_alert_settings;
create policy analytics_alert_settings_select on public.analytics_alert_settings
  for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists analytics_alert_settings_write on public.analytics_alert_settings;
create policy analytics_alert_settings_insert on public.analytics_alert_settings
  for insert to authenticated
  with check (
    public.has_org_role(organization_id, array['owner','admin','accountant','manager']::public.member_role[])
  );
create policy analytics_alert_settings_update on public.analytics_alert_settings
  for update to authenticated
  using (
    public.has_org_role(organization_id, array['owner','admin','accountant','manager']::public.member_role[])
  )
  with check (
    public.has_org_role(organization_id, array['owner','admin','accountant','manager']::public.member_role[])
  );
create policy analytics_alert_settings_delete on public.analytics_alert_settings
  for delete to authenticated
  using (
    public.has_org_role(organization_id, array['owner','admin','accountant','manager']::public.member_role[])
  );
drop policy if exists analytics_alert_events_select on public.analytics_alert_events;
create policy analytics_alert_events_select on public.analytics_alert_events
  for select to authenticated using (public.is_org_member(organization_id));
-- Mutations via SECURITY DEFINER RPCs only (no direct client write)
revoke insert, update, delete on table public.analytics_alert_events from authenticated;
drop policy if exists analytics_inventory_thresholds_select on public.analytics_inventory_thresholds;
create policy analytics_inventory_thresholds_select on public.analytics_inventory_thresholds
  for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists analytics_inventory_thresholds_write on public.analytics_inventory_thresholds;
create policy analytics_inventory_thresholds_insert on public.analytics_inventory_thresholds
  for insert to authenticated
  with check (
    public.has_org_role(organization_id, array['owner','admin','manager','accountant']::public.member_role[])
  );
create policy analytics_inventory_thresholds_update on public.analytics_inventory_thresholds
  for update to authenticated
  using (
    public.has_org_role(organization_id, array['owner','admin','manager','accountant']::public.member_role[])
  )
  with check (
    public.has_org_role(organization_id, array['owner','admin','manager','accountant']::public.member_role[])
  );
create policy analytics_inventory_thresholds_delete on public.analytics_inventory_thresholds
  for delete to authenticated
  using (
    public.has_org_role(organization_id, array['owner','admin','manager','accountant']::public.member_role[])
  );
revoke all on table public.analytics_alert_settings from public, anon;
revoke all on table public.analytics_alert_events from public, anon;
revoke all on table public.analytics_inventory_thresholds from public, anon;
grant select, insert, update, delete on table public.analytics_alert_settings to authenticated;
grant select on table public.analytics_alert_events to authenticated;
grant select, insert, update, delete on table public.analytics_inventory_thresholds to authenticated;
grant all on table public.analytics_alert_settings to service_role;
grant all on table public.analytics_alert_events to service_role;
grant all on table public.analytics_inventory_thresholds to service_role;
