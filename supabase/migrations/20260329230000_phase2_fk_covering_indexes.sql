-- Phase 2 hardening: covering indexes for unindexed FKs (STAGING)
-- Project: rpcpdrzbcclofvjpgldb
--
-- Only add indexes where the FK column is not already the *leading*
-- column of an existing index.

-- accounting_fiscal_years.closed_by
create index if not exists accounting_fiscal_years_closed_by_idx
  on public.accounting_fiscal_years (closed_by);
-- accounting_periods.reopened_by
create index if not exists accounting_periods_reopened_by_idx
  on public.accounting_periods (reopened_by);
-- accounting_sequences.fiscal_year_id
-- PK is (organization_id, fiscal_year_id) — fiscal_year_id is not leading
create index if not exists accounting_sequences_fiscal_year_id_idx
  on public.accounting_sequences (fiscal_year_id);
-- accounts.parent_id
-- existing accounts_org_parent_idx is (organization_id, parent_id) — parent_id not leading
create index if not exists accounts_parent_id_idx
  on public.accounts (parent_id);
-- journal_entries.created_by
create index if not exists journal_entries_created_by_idx
  on public.journal_entries (created_by);
-- journal_entries.fiscal_year_id
-- unique (organization_id, fiscal_year_id, entry_number) does not lead with fiscal_year_id
create index if not exists journal_entries_fiscal_year_id_idx
  on public.journal_entries (fiscal_year_id);
-- journal_entries.posted_by
create index if not exists journal_entries_posted_by_idx
  on public.journal_entries (posted_by);
-- journal_entries.reversed_by_entry_id
-- (reversal_of_entry_id already indexed; this is the inverse link)
create index if not exists journal_entries_reversed_by_entry_id_idx
  on public.journal_entries (reversed_by_entry_id);
