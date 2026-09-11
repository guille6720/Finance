-- Phase 9: remaining FK covering indexes (advisor)

create index if not exists pos_sales_created_by_idx
  on public.pos_sales (created_by) where created_by is not null;
create index if not exists pos_sales_completed_by_idx
  on public.pos_sales (completed_by) where completed_by is not null;
create index if not exists pos_sessions_cashier_idx
  on public.pos_sessions (cashier_id);
create index if not exists pos_settings_walk_in_covering_idx
  on public.pos_settings (organization_id, default_walk_in_customer_id);
