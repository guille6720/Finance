-- Phase 2 hardening: relocate btree_gist out of public (STAGING)
-- Project: rpcpdrzbcclofvjpgldb
--
-- Exclusion constraints depending on btree_gist:
--   accounting_fiscal_years_no_overlap
--   accounting_periods_no_overlap
--
-- Strategy: ALTER EXTENSION … SET SCHEMA (relocatable=true).
-- Does NOT drop constraints or accounting data.
-- Idempotent if already in extensions.

create schema if not exists extensions;
do $$
declare
  current_schema text;
begin
  select n.nspname
    into current_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'btree_gist';

  if current_schema is null then
    execute 'create extension btree_gist with schema extensions';
  elsif current_schema = 'public' then
    execute 'alter extension btree_gist set schema extensions';
  end if;
  -- else already in extensions (or other non-public) — leave as-is
end $$;
-- Sanity: exclusion constraints must still exist after relocate
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'accounting_fiscal_years_no_overlap'
  ) then
    raise exception 'accounting_fiscal_years_no_overlap missing after btree_gist relocate';
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'accounting_periods_no_overlap'
  ) then
    raise exception 'accounting_periods_no_overlap missing after btree_gist relocate';
  end if;
end $$;
