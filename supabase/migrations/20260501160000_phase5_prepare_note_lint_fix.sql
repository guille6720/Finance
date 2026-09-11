-- Phase 5 — lint fix for prepare_fiscal_note unused variable

create or replace function public.prepare_fiscal_note(
  p_parent_fiscal_document_id uuid,
  p_document_type_internal_code text,
  p_relationship public.fiscal_relationship_type,
  p_issue_date date default current_date,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent public.fiscal_documents%rowtype;
  v_dtype public.fiscal_document_types%rowtype;
  v_rule_id uuid;
  v_doc_id uuid;
  v_idem text;
  v_existing uuid;
  v_roles public.member_role[];
begin
  select * into v_parent
  from public.fiscal_documents
  where id = p_parent_fiscal_document_id
  for share;

  if not found then raise exception 'parent fiscal document not found'; end if;
  if v_parent.status is distinct from 'AUTHORIZED' then
    raise exception 'parent must be AUTHORIZED';
  end if;

  perform public.fiscal_assert_feature(v_parent.organization_id);

  v_roles := array['owner','admin','accountant']::public.member_role[];
  perform public.fiscal_assert_role(v_parent.organization_id, v_roles);

  select * into v_dtype
  from public.fiscal_document_types
  where internal_code = p_document_type_internal_code
    and enabled_phase5
    and operation_kind = case
      when p_relationship = 'CREDIT_NOTE' then 'CREDIT_NOTE'::public.fiscal_operation_kind
      else 'DEBIT_NOTE'::public.fiscal_operation_kind
    end;

  if not found then
    raise exception 'note document type not enabled';
  end if;
  if v_dtype.document_class is distinct from v_parent.document_class then
    raise exception 'note class must match parent class';
  end if;

  v_idem := coalesce(p_idempotency_key, lower(p_relationship::text) || ':' || p_parent_fiscal_document_id::text || ':' || p_issue_date::text);
  select id into v_existing
  from public.fiscal_documents
  where organization_id = v_parent.organization_id and idempotency_key = v_idem;
  if v_existing is not null then return v_existing; end if;

  v_rule_id := public.resolve_fiscal_rule_version(v_parent.organization_id, p_issue_date);

  insert into public.fiscal_documents (
    organization_id, branch_id, sales_document_id, fiscal_environment,
    document_type_id, document_class, arca_cbte_tipo,
    point_of_sale_id, arca_point_of_sale, issue_date, counterparty_id,
    issuer_snapshot, receiver_snapshot, currency_code, currency_rate, concept_type,
    net_taxed_amount, net_exempt_amount, net_untaxed_amount, vat_amount,
    other_taxes_amount, total_amount, status, accounting_status,
    related_fiscal_document_id, relationship_type, fiscal_rule_version_id,
    idempotency_key, created_by
  ) values (
    v_parent.organization_id, v_parent.branch_id, null, v_parent.fiscal_environment,
    v_dtype.id, v_dtype.document_class, v_dtype.arca_cbte_tipo,
    v_parent.point_of_sale_id, v_parent.arca_point_of_sale, p_issue_date, v_parent.counterparty_id,
    v_parent.issuer_snapshot, v_parent.receiver_snapshot, v_parent.currency_code, v_parent.currency_rate, v_parent.concept_type,
    v_parent.net_taxed_amount, v_parent.net_exempt_amount, v_parent.net_untaxed_amount, v_parent.vat_amount,
    v_parent.other_taxes_amount, v_parent.total_amount, 'DRAFT', 'NOT_APPLICABLE',
    v_parent.id, p_relationship, v_rule_id,
    v_idem, auth.uid()
  )
  returning id into v_doc_id;

  insert into public.fiscal_document_lines (
    organization_id, fiscal_document_id, line_number, description, quantity, unit_price,
    discount_amount, vat_treatment, vat_rate_code, vat_rate,
    net_amount, vat_amount, exempt_amount, untaxed_amount, line_total
  )
  select
    organization_id, v_doc_id, line_number, description, quantity, unit_price,
    discount_amount, vat_treatment, vat_rate_code, vat_rate,
    net_amount, vat_amount, exempt_amount, untaxed_amount, line_total
  from public.fiscal_document_lines
  where fiscal_document_id = v_parent.id;

  insert into public.fiscal_tax_summaries (
    organization_id, fiscal_document_id, summary_kind, code, base_amount, rate, amount
  )
  select organization_id, v_doc_id, summary_kind, code, base_amount, rate, amount
  from public.fiscal_tax_summaries
  where fiscal_document_id = v_parent.id;

  return v_doc_id;
end;
$$;
