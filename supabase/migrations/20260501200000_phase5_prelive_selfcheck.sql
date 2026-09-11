-- Phase 5 — pre-live selfcheck RPC (service_role) for FK indexes + RLS + grants

create or replace function public.phase5_prelive_selfcheck()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_missing_indexes text[] := array[]::text[];
  v_for_all_policies text[] := array[]::text[];
  v_auth_trusted text[] := array[]::text[];
  v_idx text;
  v_needed text[] := array[
    'fiscal_rule_versions_reviewed_by_idx',
    'fiscal_rule_versions_activated_by_idx',
    'fiscal_points_of_sale_org_branch_idx',
    'fiscal_documents_org_counterparty_idx',
    'fiscal_documents_org_branch_idx',
    'fiscal_documents_org_pos_idx',
    'fiscal_tax_summaries_org_doc_idx',
    'fiscal_authorization_attempts_org_doc_idx',
    'fiscal_accounting_mappings_sales_account_idx',
    'fiscal_accounting_mappings_vat_account_idx',
    'fiscal_accounting_mappings_recv_account_idx'
  ];
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'service_role required';
  end if;

  foreach v_idx in array v_needed loop
    if not exists (
      select 1 from pg_indexes
      where schemaname = 'public' and indexname = v_idx
    ) then
      v_missing_indexes := array_append(v_missing_indexes, v_idx);
    end if;
  end loop;

  select coalesce(array_agg(policyname order by policyname), array[]::text[])
  into v_for_all_policies
  from pg_policies
  where schemaname = 'public'
    and tablename like 'fiscal_%'
    and cmd = 'ALL';

  select coalesce(array_agg(p.proname::text order by p.proname), array[]::text[])
  into v_auth_trusted
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'begin_fiscal_authorization',
      'complete_fiscal_authorization',
      'set_fiscal_qr_payload'
    )
    and has_function_privilege('authenticated', p.oid, 'EXECUTE');

  return jsonb_build_object(
    'missing_fk_indexes', to_jsonb(v_missing_indexes),
    'fiscal_for_all_policies', to_jsonb(v_for_all_policies),
    'authenticated_can_execute_trusted', to_jsonb(v_auth_trusted),
    'ok', (
      coalesce(array_length(v_missing_indexes, 1), 0) = 0
      and coalesce(array_length(v_for_all_policies, 1), 0) = 0
      and coalesce(array_length(v_auth_trusted, 1), 0) = 0
    )
  );
end;
$$;
revoke all on function public.phase5_prelive_selfcheck() from public, anon, authenticated;
grant execute on function public.phase5_prelive_selfcheck() to service_role;
