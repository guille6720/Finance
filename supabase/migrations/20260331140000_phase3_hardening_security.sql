-- Phase 3 final hardening — security + performance (STAGING)
-- Project: rpcpdrzbcclofvjpgldb

-- ---------------------------------------------------------------------------
-- 1. Remove obsolete two-argument reversal overload (accidental Phase 3 artifact)
-- Canonical signature: reverse_journal_entry(uuid, date, text)
-- ---------------------------------------------------------------------------

drop function if exists public.reverse_journal_entry(uuid, text);
-- ---------------------------------------------------------------------------
-- 2. Minimum privilege — revoke anon table access on private accounting tables
-- ---------------------------------------------------------------------------

revoke all on table public.journal_entries from anon;
revoke all on table public.journal_entry_lines from anon;
revoke all on table public.accounts from anon;
revoke all on table public.accounting_periods from anon;
revoke all on table public.accounting_fiscal_years from anon;
revoke all on table public.accounting_sequences from anon;
-- Preserve authenticated access (Supabase default + Phase 2 RLS)
grant select, insert, update, delete on table public.journal_entries to authenticated;
grant select, insert, update, delete on table public.journal_entry_lines to authenticated;
grant select, insert, update, delete on table public.accounts to authenticated;
grant select, insert, update, delete on table public.accounting_periods to authenticated;
grant select, insert, update, delete on table public.accounting_fiscal_years to authenticated;
grant select on table public.accounting_sequences to authenticated;
-- ---------------------------------------------------------------------------
-- 3. Covering indexes for unindexed foreign keys (Performance Advisor)
-- ---------------------------------------------------------------------------

create index if not exists counterparties_created_by_idx
  on public.counterparties (created_by);
create index if not exists counterparty_addresses_organization_id_idx
  on public.counterparty_addresses (organization_id);
create index if not exists counterparty_contacts_organization_id_idx
  on public.counterparty_contacts (organization_id);
create index if not exists counterparty_fiscal_profiles_fiscal_condition_id_idx
  on public.counterparty_fiscal_profiles (fiscal_condition_id);
create index if not exists counterparty_fiscal_profiles_organization_id_idx
  on public.counterparty_fiscal_profiles (organization_id);
create index if not exists counterparty_roles_created_by_idx
  on public.counterparty_roles (created_by);
