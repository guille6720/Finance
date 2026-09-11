-- Phase 10 hardening: cover composite rectification FK for Performance Advisor

create index if not exists tax_filing_supersedes_org_idx
  on public.tax_filing_records (organization_id, supersedes_filing_id);
