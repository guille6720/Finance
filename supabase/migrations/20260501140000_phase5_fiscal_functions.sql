-- Phase 5 — Fiscal RPCs (prepare / ready / complete / reconcile / notes / accounting)
-- ARCA SOAP stays in application layer. These RPCs coordinate DB state + locks.

create or replace function public.fiscal_assert_feature(p_org_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_ok boolean;
begin
  select exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = 'fiscal_invoicing'
      and ofeat.status = 'enabled'
  ) into v_ok;

  if not coalesce(v_ok, false) then
    raise exception 'fiscal_invoicing feature is not enabled for this organization';
  end if;
end;
$$;
create or replace function public.fiscal_assert_role(
  p_org_id uuid,
  p_roles public.member_role[]
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not public.has_org_role(p_org_id, p_roles) then
    raise exception 'insufficient role for fiscal operation';
  end if;
end;
$$;
create or replace function public.resolve_fiscal_rule_version(
  p_org_id uuid,
  p_issue_date date
)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select id into v_id
  from public.fiscal_rule_versions
  where status = 'ACTIVE'
    and effective_from <= p_issue_date
    and (effective_to is null or effective_to >= p_issue_date)
    and (organization_id = p_org_id or organization_id is null)
  order by
    case when organization_id = p_org_id then 0 else 1 end,
    effective_from desc,
    version desc
  limit 1;

  if v_id is null then
    raise exception 'no ACTIVE fiscal rule version for issue_date %', p_issue_date;
  end if;
  return v_id;
end;
$$;
-- Prepare primary invoice from READY_TO_INVOICE sales order (idempotent)
create or replace function public.prepare_fiscal_invoice_from_sales_order(
  p_sales_document_id uuid,
  p_point_of_sale_id uuid,
  p_document_type_internal_code text,
  p_issue_date date default current_date,
  p_condicion_iva_receptor_id int default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_sales public.sales_documents%rowtype;
  v_pos public.fiscal_points_of_sale%rowtype;
  v_dtype public.fiscal_document_types%rowtype;
  v_rule_id uuid;
  v_existing uuid;
  v_doc_id uuid;
  v_org public.organizations%rowtype;
  v_fp record;
  v_cp record;
  v_line record;
  v_line_no int := 0;
  v_net_taxed numeric(19,4) := 0;
  v_vat numeric(19,4) := 0;
  v_total numeric(19,4) := 0;
  v_line_net numeric(19,4);
  v_line_vat numeric(19,4);
  v_line_total numeric(19,4);
  v_idem text;
  v_receiver jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  select * into v_sales
  from public.sales_documents
  where id = p_sales_document_id
  for update;

  if not found then
    raise exception 'sales document not found';
  end if;

  perform public.fiscal_assert_feature(v_sales.organization_id);
  perform public.fiscal_assert_role(
    v_sales.organization_id,
    array['owner','admin','manager','operator','accountant']::public.member_role[]
  );

  if v_sales.document_type is distinct from 'SALES_ORDER' then
    raise exception 'only SALES_ORDER can be prepared for fiscal invoice';
  end if;
  if v_sales.status is distinct from 'READY_TO_INVOICE' then
    raise exception 'sales order must be READY_TO_INVOICE (got %)', v_sales.status;
  end if;

  v_idem := 'invoice:' || p_sales_document_id::text;

  select id into v_existing
  from public.fiscal_documents
  where organization_id = v_sales.organization_id
    and idempotency_key = v_idem;

  if v_existing is not null then
    return v_existing;
  end if;

  select * into v_pos
  from public.fiscal_points_of_sale
  where id = p_point_of_sale_id
    and organization_id = v_sales.organization_id
    and is_active
  for share;

  if not found then
    raise exception 'active fiscal point of sale not found';
  end if;
  if v_pos.environment = 'PRODUCTION' then
    raise exception 'PRODUCTION fiscal environment is blocked in Phase 5';
  end if;
  if v_pos.issuance_method is distinct from 'WSFE_CAE' then
    raise exception 'only WSFE_CAE issuance is enabled in Phase 5';
  end if;

  select * into v_dtype
  from public.fiscal_document_types
  where internal_code = p_document_type_internal_code
    and enabled_phase5
    and operation_kind = 'INVOICE';

  if not found then
    raise exception 'document type % not enabled for Phase 5 invoice', p_document_type_internal_code;
  end if;

  v_rule_id := public.resolve_fiscal_rule_version(v_sales.organization_id, p_issue_date);

  select * into v_org from public.organizations where id = v_sales.organization_id;
  if v_org.cuit is null then
    raise exception 'organization CUIT required for fiscal issuance';
  end if;

  select fc.code as condition_code, fp.fiscal_address, fp.gross_income_number, fp.activity_start_date
  into v_fp
  from public.fiscal_profiles fp
  left join public.fiscal_conditions fc on fc.id = fp.fiscal_condition_id
  where fp.organization_id = v_sales.organization_id
  limit 1;

  select c.id, c.tax_id, c.tax_id_type, c.legal_name, c.trade_name,
         fc.code as fiscal_condition_code, cfp.fiscal_address
  into v_cp
  from public.counterparties c
  left join public.counterparty_fiscal_profiles cfp
    on cfp.organization_id = c.organization_id and cfp.counterparty_id = c.id
  left join public.fiscal_conditions fc on fc.id = cfp.fiscal_condition_id
  where c.organization_id = v_sales.organization_id
    and c.id = v_sales.counterparty_id;

  if p_condicion_iva_receptor_id is null then
    raise exception 'CondicionIVAReceptorId is required';
  end if;

  -- Validate receptor condition exists in catalog (bootstrap or refreshed)
  if not exists (
    select 1 from public.fiscal_parameter_catalogs
    where catalog_kind = 'CONDICION_IVA_RECEPTOR'
      and environment = v_pos.environment
      and code = p_condicion_iva_receptor_id::text
      and (organization_id is null or organization_id = v_sales.organization_id)
  ) then
    raise exception 'CondicionIVAReceptorId % not found in fiscal_parameter_catalogs', p_condicion_iva_receptor_id;
  end if;

  v_receiver := jsonb_build_object(
    'counterparty_id', v_cp.id,
    'tax_id', v_cp.tax_id,
    'tax_id_type', v_cp.tax_id_type,
    'legal_name', v_cp.legal_name,
    'trade_name', v_cp.trade_name,
    'fiscal_condition_code', v_cp.fiscal_condition_code,
    'fiscal_address', v_cp.fiscal_address,
    'CondicionIVAReceptorId', p_condicion_iva_receptor_id
  );

  insert into public.fiscal_documents (
    organization_id,
    branch_id,
    sales_document_id,
    fiscal_environment,
    document_type_id,
    document_class,
    arca_cbte_tipo,
    point_of_sale_id,
    arca_point_of_sale,
    issue_date,
    counterparty_id,
    issuer_snapshot,
    receiver_snapshot,
    currency_code,
    currency_rate,
    concept_type,
    status,
    accounting_status,
    fiscal_rule_version_id,
    idempotency_key,
    created_by
  ) values (
    v_sales.organization_id,
    v_sales.branch_id,
    v_sales.id,
    v_pos.environment,
    v_dtype.id,
    v_dtype.document_class,
    v_dtype.arca_cbte_tipo,
    v_pos.id,
    v_pos.arca_point_of_sale,
    p_issue_date,
    v_sales.counterparty_id,
    jsonb_build_object(
      'cuit', v_org.cuit,
      'legal_name', v_org.legal_name,
      'commercial_name', v_org.commercial_name,
      'fiscal_condition_code', v_fp.condition_code,
      'fiscal_address', v_fp.fiscal_address,
      'gross_income_number', v_fp.gross_income_number,
      'activity_start_date', v_fp.activity_start_date
    ),
    v_receiver,
    'PES',
    1,
    1,
    'DRAFT',
    'NOT_APPLICABLE',
    v_rule_id,
    v_idem,
    v_uid
  )
  returning id into v_doc_id;

  for v_line in
    select *
    from public.sales_document_lines
    where sales_document_id = v_sales.id
    order by line_number
  loop
    v_line_no := v_line_no + 1;
    v_line_net := round((v_line.quantity * v_line.unit_price) - coalesce(v_line.discount_amount, 0), 4);
    -- Phase 5 default: 21% taxed until line-level VAT treatment is configured
    v_line_vat := round(v_line_net * 0.21, 4);
    v_line_total := v_line_net + v_line_vat;
    v_net_taxed := v_net_taxed + v_line_net;
    v_vat := v_vat + v_line_vat;
    v_total := v_total + v_line_total;

    insert into public.fiscal_document_lines (
      organization_id, fiscal_document_id, line_number, source_sales_line_id,
      description, quantity, unit_price, discount_amount,
      vat_treatment, vat_rate_code, vat_rate,
      net_amount, vat_amount, exempt_amount, untaxed_amount, line_total
    ) values (
      v_sales.organization_id, v_doc_id, v_line_no, v_line.id,
      v_line.description, v_line.quantity, v_line.unit_price, coalesce(v_line.discount_amount, 0),
      'TAXED', '5', 21,
      v_line_net, v_line_vat, 0, 0, v_line_total
    );
  end loop;

  if v_line_no = 0 then
    raise exception 'sales order has no lines';
  end if;

  insert into public.fiscal_tax_summaries (
    organization_id, fiscal_document_id, summary_kind, code, base_amount, rate, amount
  ) values (
    v_sales.organization_id, v_doc_id, 'IVA', '5', v_net_taxed, 21, v_vat
  );

  update public.fiscal_documents
  set net_taxed_amount = v_net_taxed,
      vat_amount = v_vat,
      total_amount = v_total,
      updated_at = timezone('utc', now())
  where id = v_doc_id;

  return v_doc_id;
end;
$$;
create or replace function public.mark_fiscal_ready_to_authorize(p_fiscal_document_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_doc public.fiscal_documents%rowtype;
begin
  select * into v_doc
  from public.fiscal_documents
  where id = p_fiscal_document_id
  for update;

  if not found then
    raise exception 'fiscal document not found';
  end if;

  perform public.fiscal_assert_feature(v_doc.organization_id);
  perform public.fiscal_assert_role(
    v_doc.organization_id,
    array['owner','admin','manager','operator','accountant']::public.member_role[]
  );

  if v_doc.status not in ('DRAFT', 'REJECTED') then
    raise exception 'cannot mark ready from status %', v_doc.status;
  end if;
  if v_doc.currency_code not in ('PES', 'ARS') then
    raise exception 'Phase 5 homologation MVP allows ARS/PES only';
  end if;
  if coalesce((v_doc.receiver_snapshot->>'CondicionIVAReceptorId')::int, 0) <= 0 then
    raise exception 'CondicionIVAReceptorId missing on receiver snapshot';
  end if;
  if v_doc.total_amount <= 0 then
    raise exception 'total_amount must be positive';
  end if;
  if abs(
    (v_doc.net_taxed_amount + v_doc.net_exempt_amount + v_doc.net_untaxed_amount
      + v_doc.vat_amount + v_doc.other_taxes_amount) - v_doc.total_amount
  ) > 0.01 then
    raise exception 'totals do not reconcile';
  end if;

  update public.fiscal_documents
  set status = 'READY_TO_AUTHORIZE',
      updated_at = timezone('utc', now())
  where id = p_fiscal_document_id;

  return p_fiscal_document_id;
end;
$$;
-- Begin authorization: lock + AUTHORIZING + attempt row. Number provided by app after UltimoAutorizado.
create or replace function public.begin_fiscal_authorization(
  p_fiscal_document_id uuid,
  p_intended_document_number bigint,
  p_certificate_fingerprint text,
  p_request_hash text,
  p_correlation_id text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_doc public.fiscal_documents%rowtype;
  v_attempt_id uuid;
  v_attempt_no int;
begin
  if p_intended_document_number is null or p_intended_document_number <= 0 then
    raise exception 'intended document number required';
  end if;

  select * into v_doc
  from public.fiscal_documents
  where id = p_fiscal_document_id
  for update;

  if not found then
    raise exception 'fiscal document not found';
  end if;

  perform public.fiscal_assert_feature(v_doc.organization_id);
  -- authorize roles: owner, admin, accountant (manager excluded by default)
  perform public.fiscal_assert_role(
    v_doc.organization_id,
    array['owner','admin','accountant']::public.member_role[]
  );

  if v_doc.fiscal_environment = 'PRODUCTION' then
    raise exception 'PRODUCTION ARCA blocked';
  end if;

  if v_doc.status = 'AUTHORIZED' then
    raise exception 'already authorized';
  end if;

  if v_doc.status = 'AUTHORIZING' then
    raise exception 'authorization already in progress; reconcile first';
  end if;

  if v_doc.status = 'RECONCILIATION_REQUIRED' then
    raise exception 'uncertain outcome: reconcile before new FECAE; do not allocate a new number';
  end if;

  if v_doc.status is distinct from 'READY_TO_AUTHORIZE' then
    raise exception 'document must be READY_TO_AUTHORIZE';
  end if;

  -- Advisory lock key: org + env + POS + cbte tipo
  perform pg_advisory_xact_lock(
    hashtext(
      v_doc.organization_id::text || ':' || v_doc.fiscal_environment::text
      || ':' || v_doc.arca_point_of_sale::text || ':' || v_doc.arca_cbte_tipo::text
    )
  );

  select coalesce(max(attempt_number), 0) + 1 into v_attempt_no
  from public.fiscal_authorization_attempts
  where fiscal_document_id = p_fiscal_document_id;

  insert into public.fiscal_authorization_attempts (
    fiscal_document_id, organization_id, attempt_number, environment, service,
    requested_pos, requested_cbte_tipo, requested_document_number,
    certificate_fingerprint, request_hash, correlation_id, outcome
  ) values (
    p_fiscal_document_id, v_doc.organization_id, v_attempt_no, v_doc.fiscal_environment, 'wsfe',
    v_doc.arca_point_of_sale, v_doc.arca_cbte_tipo, p_intended_document_number,
    p_certificate_fingerprint, p_request_hash, p_correlation_id, null
  )
  returning id into v_attempt_id;

  update public.fiscal_documents
  set status = 'AUTHORIZING',
      document_number = p_intended_document_number,
      credential_fingerprint = p_certificate_fingerprint,
      updated_at = timezone('utc', now())
  where id = p_fiscal_document_id;

  return v_attempt_id;
end;
$$;
create or replace function public.complete_fiscal_authorization(
  p_attempt_id uuid,
  p_outcome public.fiscal_authorization_outcome,
  p_cae text default null,
  p_cae_expiration date default null,
  p_arca_error_codes jsonb default '[]'::jsonb,
  p_arca_observation_codes jsonb default '[]'::jsonb,
  p_transport_error_class text default null,
  p_arca_result jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt public.fiscal_authorization_attempts%rowtype;
  v_doc public.fiscal_documents%rowtype;
begin
  select * into v_attempt
  from public.fiscal_authorization_attempts
  where id = p_attempt_id
  for update;

  if not found then
    raise exception 'attempt not found';
  end if;

  select * into v_doc
  from public.fiscal_documents
  where id = v_attempt.fiscal_document_id
  for update;

  perform public.fiscal_assert_role(
    v_doc.organization_id,
    array['owner','admin','accountant']::public.member_role[]
  );

  perform set_config('fiscal.engine_write', '1', true);

  update public.fiscal_authorization_attempts
  set completed_at = timezone('utc', now()),
      outcome = p_outcome,
      cae = p_cae,
      cae_expiration_date = p_cae_expiration,
      arca_error_codes = coalesce(p_arca_error_codes, '[]'::jsonb),
      arca_observation_codes = coalesce(p_arca_observation_codes, '[]'::jsonb),
      transport_error_class = p_transport_error_class
  where id = p_attempt_id;

  if p_outcome in ('APPROVED', 'RECONCILED_AUTHORIZED') then
    if p_cae is null or p_cae_expiration is null then
      raise exception 'CAE and expiration required for approved outcome';
    end if;

    update public.fiscal_documents
    set status = 'AUTHORIZED',
        cae = p_cae,
        cae_expiration_date = p_cae_expiration,
        arca_result = coalesce(p_arca_result, '{}'::jsonb),
        arca_observations = coalesce(p_arca_observation_codes, '[]'::jsonb),
        authorized_at = timezone('utc', now()),
        accounting_status = 'PENDING',
        updated_at = timezone('utc', now())
    where id = v_doc.id;

    if v_doc.sales_document_id is not null and v_doc.relationship_type is null then
      update public.sales_documents
      set status = 'INVOICED',
          invoiced_fiscal_document_id = v_doc.id,
          updated_at = timezone('utc', now())
      where id = v_doc.sales_document_id
        and organization_id = v_doc.organization_id
        and status = 'READY_TO_INVOICE';
    end if;

  elsif p_outcome = 'REJECTED' then
    update public.fiscal_documents
    set status = 'REJECTED',
        document_number = null,
        arca_result = coalesce(p_arca_result, '{}'::jsonb),
        arca_observations = coalesce(p_arca_observation_codes, '[]'::jsonb),
        updated_at = timezone('utc', now())
    where id = v_doc.id;

  elsif p_outcome in ('TRANSPORT_ERROR', 'UNCERTAIN', 'AUTH_ERROR') then
    -- Keep intended number; do not burn a new one
    update public.fiscal_documents
    set status = 'RECONCILIATION_REQUIRED',
        arca_result = coalesce(p_arca_result, '{}'::jsonb),
        updated_at = timezone('utc', now())
    where id = v_doc.id;

  elsif p_outcome = 'RECONCILED_NOT_FOUND' then
    update public.fiscal_documents
    set status = 'READY_TO_AUTHORIZE',
        document_number = null,
        updated_at = timezone('utc', now())
    where id = v_doc.id;

  elsif p_outcome = 'BUSINESS_VALIDATION_ERROR' then
    update public.fiscal_documents
    set status = 'REJECTED',
        document_number = null,
        arca_result = coalesce(p_arca_result, '{}'::jsonb),
        updated_at = timezone('utc', now())
    where id = v_doc.id;
  else
    raise exception 'unsupported outcome %', p_outcome;
  end if;

  return v_doc.id;
end;
$$;
create or replace function public.set_fiscal_qr_payload(
  p_fiscal_document_id uuid,
  p_qr_payload text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_doc public.fiscal_documents%rowtype;
begin
  select * into v_doc from public.fiscal_documents where id = p_fiscal_document_id for update;
  if not found then raise exception 'fiscal document not found'; end if;
  if v_doc.status is distinct from 'AUTHORIZED' then
    raise exception 'QR only after AUTHORIZED';
  end if;
  perform public.fiscal_assert_role(
    v_doc.organization_id,
    array['owner','admin','accountant']::public.member_role[]
  );
  perform set_config('fiscal.engine_write', '1', true);
  update public.fiscal_documents
  set qr_payload = p_qr_payload, updated_at = timezone('utc', now())
  where id = p_fiscal_document_id;
  return p_fiscal_document_id;
end;
$$;
-- Credit / debit note prepare from authorized parent
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
  v_line record;
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

  if p_relationship = 'CREDIT_NOTE' then
    v_roles := array['owner','admin','accountant']::public.member_role[];
  else
    v_roles := array['owner','admin','accountant']::public.member_role[];
  end if;
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
revoke all on function public.fiscal_assert_feature(uuid) from public, anon;
revoke all on function public.fiscal_assert_role(uuid, public.member_role[]) from public, anon;
revoke all on function public.resolve_fiscal_rule_version(uuid, date) from public, anon;
revoke all on function public.prepare_fiscal_invoice_from_sales_order(uuid, uuid, text, date, int) from public, anon;
revoke all on function public.mark_fiscal_ready_to_authorize(uuid) from public, anon;
revoke all on function public.begin_fiscal_authorization(uuid, bigint, text, text, text) from public, anon;
revoke all on function public.complete_fiscal_authorization(uuid, public.fiscal_authorization_outcome, text, date, jsonb, jsonb, text, jsonb) from public, anon;
revoke all on function public.set_fiscal_qr_payload(uuid, text) from public, anon;
revoke all on function public.prepare_fiscal_note(uuid, text, public.fiscal_relationship_type, date, text) from public, anon;
grant execute on function public.resolve_fiscal_rule_version(uuid, date) to authenticated;
grant execute on function public.prepare_fiscal_invoice_from_sales_order(uuid, uuid, text, date, int) to authenticated;
grant execute on function public.mark_fiscal_ready_to_authorize(uuid) to authenticated;
grant execute on function public.begin_fiscal_authorization(uuid, bigint, text, text, text) to authenticated;
grant execute on function public.complete_fiscal_authorization(uuid, public.fiscal_authorization_outcome, text, date, jsonb, jsonb, text, jsonb) to authenticated;
grant execute on function public.set_fiscal_qr_payload(uuid, text) to authenticated;
grant execute on function public.prepare_fiscal_note(uuid, text, public.fiscal_relationship_type, date, text) to authenticated;
