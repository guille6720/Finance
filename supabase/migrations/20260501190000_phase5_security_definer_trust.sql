-- Phase 5 — SECURITY DEFINER trust boundary
-- Trusted ARCA adapter operations: service_role ONLY (no authenticated EXECUTE).
-- See docs/architecture/PHASE5-SECURITY-DEFINER.md

create or replace function public.fiscal_assert_service_role()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'trusted fiscal adapter operation requires service_role';
  end if;
end;
$$;
revoke all on function public.fiscal_assert_service_role() from public, anon, authenticated;
grant execute on function public.fiscal_assert_service_role() to service_role;
-- Recreate trusted functions with service_role gate (not auth.uid()/has_org_role)
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
  perform public.fiscal_assert_service_role();

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
  perform public.fiscal_assert_service_role();

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
  perform public.fiscal_assert_service_role();

  select * into v_doc from public.fiscal_documents where id = p_fiscal_document_id for update;
  if not found then raise exception 'fiscal document not found'; end if;
  if v_doc.status is distinct from 'AUTHORIZED' then
    raise exception 'QR only after AUTHORIZED';
  end if;
  perform set_config('fiscal.engine_write', '1', true);
  update public.fiscal_documents
  set qr_payload = p_qr_payload, updated_at = timezone('utc', now())
  where id = p_fiscal_document_id;
  return p_fiscal_document_id;
end;
$$;
revoke all on function public.begin_fiscal_authorization(uuid, bigint, text, text, text)
  from public, anon, authenticated;
revoke all on function public.complete_fiscal_authorization(
  uuid, public.fiscal_authorization_outcome, text, date, jsonb, jsonb, text, jsonb
) from public, anon, authenticated;
revoke all on function public.set_fiscal_qr_payload(uuid, text)
  from public, anon, authenticated;
grant execute on function public.begin_fiscal_authorization(uuid, bigint, text, text, text)
  to service_role;
grant execute on function public.complete_fiscal_authorization(
  uuid, public.fiscal_authorization_outcome, text, date, jsonb, jsonb, text, jsonb
) to service_role;
grant execute on function public.set_fiscal_qr_payload(uuid, text)
  to service_role;
-- Reaffirm USER-CALLABLE grants (INTENTIONAL_AND_DOCUMENTED)
revoke all on function public.prepare_fiscal_invoice_from_sales_order(uuid, uuid, text, date, int)
  from public, anon;
revoke all on function public.prepare_fiscal_note(uuid, text, public.fiscal_relationship_type, date, text)
  from public, anon;
revoke all on function public.mark_fiscal_ready_to_authorize(uuid)
  from public, anon;
revoke all on function public.resolve_fiscal_rule_version(uuid, date)
  from public, anon;
grant execute on function public.prepare_fiscal_invoice_from_sales_order(uuid, uuid, text, date, int)
  to authenticated, service_role;
grant execute on function public.prepare_fiscal_note(uuid, text, public.fiscal_relationship_type, date, text)
  to authenticated, service_role;
grant execute on function public.mark_fiscal_ready_to_authorize(uuid)
  to authenticated, service_role;
grant execute on function public.resolve_fiscal_rule_version(uuid, date)
  to authenticated, service_role;
comment on function public.begin_fiscal_authorization(uuid, bigint, text, text, text) is
  'TRUSTED SERVER ONLY (service_role) — ARCA adapter after UltimoAutorizado.';
comment on function public.complete_fiscal_authorization(uuid, public.fiscal_authorization_outcome, text, date, jsonb, jsonb, text, jsonb) is
  'TRUSTED SERVER ONLY (service_role) — CAE forgery protection; browser cannot RPC APPROVED.';
comment on function public.set_fiscal_qr_payload(uuid, text) is
  'TRUSTED SERVER ONLY (service_role) — QR forgery protection.';
comment on function public.prepare_fiscal_invoice_from_sales_order(uuid, uuid, text, date, int) is
  'INTENTIONAL_AND_DOCUMENTED — USER-CALLABLE SECURITY DEFINER; DRAFT only.';
comment on function public.prepare_fiscal_note(uuid, text, public.fiscal_relationship_type, date, text) is
  'INTENTIONAL_AND_DOCUMENTED — USER-CALLABLE SECURITY DEFINER; DRAFT note only.';
comment on function public.mark_fiscal_ready_to_authorize(uuid) is
  'INTENTIONAL_AND_DOCUMENTED — USER-CALLABLE SECURITY DEFINER; never sets CAE.';
