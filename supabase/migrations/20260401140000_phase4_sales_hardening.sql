-- Phase 4 final hardening (STAGING)
-- 1) Remove anon/PUBLIC EXECUTE from sales SECURITY DEFINER RPCs
-- 2) Harden next_sales_internal_number authorization
-- 3) Minimal FK covering indexes (no duplicates)

-- ---------------------------------------------------------------------------
-- 1. ACL: revoke PUBLIC + anon; retain authenticated + service_role
-- ---------------------------------------------------------------------------

revoke execute on function public.send_quote(uuid) from public;
revoke execute on function public.send_quote(uuid) from anon;
grant execute on function public.send_quote(uuid) to authenticated;
grant execute on function public.send_quote(uuid) to service_role;
revoke execute on function public.accept_quote(uuid) from public;
revoke execute on function public.accept_quote(uuid) from anon;
grant execute on function public.accept_quote(uuid) to authenticated;
grant execute on function public.accept_quote(uuid) to service_role;
revoke execute on function public.reject_quote(uuid, text) from public;
revoke execute on function public.reject_quote(uuid, text) from anon;
grant execute on function public.reject_quote(uuid, text) to authenticated;
grant execute on function public.reject_quote(uuid, text) to service_role;
revoke execute on function public.cancel_sales_document(uuid, text) from public;
revoke execute on function public.cancel_sales_document(uuid, text) from anon;
grant execute on function public.cancel_sales_document(uuid, text) to authenticated;
grant execute on function public.cancel_sales_document(uuid, text) to service_role;
revoke execute on function public.convert_quote_to_order(uuid) from public;
revoke execute on function public.convert_quote_to_order(uuid) from anon;
grant execute on function public.convert_quote_to_order(uuid) to authenticated;
grant execute on function public.convert_quote_to_order(uuid) to service_role;
revoke execute on function public.confirm_sales_order(uuid) from public;
revoke execute on function public.confirm_sales_order(uuid) from anon;
grant execute on function public.confirm_sales_order(uuid) to authenticated;
grant execute on function public.confirm_sales_order(uuid) to service_role;
revoke execute on function public.mark_order_ready_to_invoice(uuid) from public;
revoke execute on function public.mark_order_ready_to_invoice(uuid) from anon;
grant execute on function public.mark_order_ready_to_invoice(uuid) to authenticated;
grant execute on function public.mark_order_ready_to_invoice(uuid) to service_role;
revoke execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) from public;
revoke execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) from anon;
grant execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) to authenticated;
grant execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) to service_role;
-- ---------------------------------------------------------------------------
-- 2. Harden next_sales_internal_number
--    Must not burn sequences for arbitrary orgs / read-only members.
--    Requires authenticated identity + sales write roles on the target org.
-- ---------------------------------------------------------------------------

create or replace function public.next_sales_internal_number(
  p_organization_id uuid,
  p_document_type public.sales_document_type,
  p_document_date date
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_year int := extract(year from p_document_date)::int;
  v_seq bigint;
  v_prefix text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- Tenant-scoped: caller must hold a sales write role on the target org
  if not public.has_org_role(
    p_organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  ) then
    raise exception 'insufficient role for sales numbering';
  end if;

  if p_document_date is null then
    raise exception 'document date required';
  end if;

  if p_document_type = 'QUOTE' then
    v_prefix := 'PRES';
  elsif p_document_type = 'SALES_ORDER' then
    v_prefix := 'PED';
  else
    raise exception 'unsupported sales document type';
  end if;

  insert into public.sales_document_sequences (organization_id, document_type, sequence_year, last_value)
  values (p_organization_id, p_document_type, v_year, 0)
  on conflict (organization_id, document_type, sequence_year) do nothing;

  select last_value into v_seq
  from public.sales_document_sequences
  where organization_id = p_organization_id
    and document_type = p_document_type
    and sequence_year = v_year
  for update;

  v_seq := v_seq + 1;

  update public.sales_document_sequences
  set last_value = v_seq, updated_at = timezone('utc', now())
  where organization_id = p_organization_id
    and document_type = p_document_type
    and sequence_year = v_year;

  return v_prefix || '-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');
end;
$$;
revoke execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) from public;
revoke execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) from anon;
grant execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) to authenticated;
grant execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) to service_role;
-- ---------------------------------------------------------------------------
-- 3. Minimal FK covering indexes
--    Inspected existing indexes; do not duplicate.
--    Composite (organization_id, …) covers organization_id single-column FK.
-- ---------------------------------------------------------------------------

-- Covers: sales_document_lines_org_doc_fk + sales_document_lines_organization_id_fkey
-- Existing sales_document_lines_document_idx is (sales_document_id) only — does not cover org leftmost.
create index if not exists sales_document_lines_org_doc_idx
  on public.sales_document_lines (organization_id, sales_document_id);
-- Covers: sales_documents_org_branch_fk
create index if not exists sales_documents_org_branch_idx
  on public.sales_documents (organization_id, branch_id);
-- Covers: sales_documents_org_counterparty_fk
-- Existing sales_documents_counterparty_idx is (counterparty_id) only — does not cover org leftmost.
create index if not exists sales_documents_org_counterparty_idx
  on public.sales_documents (organization_id, counterparty_id);
-- Covers: sales_documents_created_by_fkey
create index if not exists sales_documents_created_by_idx
  on public.sales_documents (created_by);
-- Covers: sales_documents_confirmed_by_fkey
create index if not exists sales_documents_confirmed_by_idx
  on public.sales_documents (confirmed_by);
