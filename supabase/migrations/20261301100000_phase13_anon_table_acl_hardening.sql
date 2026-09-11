-- Phase 13.1 — Anon table ACL hardening (least privilege)
-- STAGING ONLY application via linked push after review.
-- Revokes residual anon privileges on public tables.
-- Does NOT weaken authenticated tenant access; RLS remains authoritative.

do $$
declare
  r record;
begin
  for r in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
  loop
    execute format('revoke all on table public.%I from anon', r.relname);
  end loop;
end $$;
-- Also revoke anon DEFAULT privileges if any (best-effort; may no-op)
alter default privileges in schema public revoke all on tables from anon;
comment on schema public is
  'Phase13: anon has no table privileges on public relations; API access via authenticated + RLS or SECURITY DEFINER RPCs.';
