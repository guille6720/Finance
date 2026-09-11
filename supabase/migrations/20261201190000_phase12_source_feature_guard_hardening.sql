-- Phase 12.10 — Source feature-guard hardening + new-org bootstrap
-- Restores Phase 4 sales RPC bodies with sales_assert_feature after role checks.

create or replace function public.sales_assert_feature(p_organization_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.organization_features ofe
    join public.feature_catalog fc on fc.id = ofe.feature_id
    where ofe.organization_id = p_organization_id
      and fc.code = 'sales'
      and ofe.status = 'enabled'::public.feature_status
  ) then
    raise exception 'feature sales is not enabled';
  end if;
end;
$$;
revoke all on function public.sales_assert_feature(uuid) from public, anon, authenticated;
create or replace function public.send_quote(p_document_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
  v_line_count int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select * into v_doc from public.sales_documents where id = p_document_id for update;
  if v_doc.id is null then raise exception 'document not found'; end if;
  if v_doc.document_type <> 'QUOTE' then raise exception 'not a quote'; end if;
  perform public.sales_assert_role(v_doc.organization_id, array['owner','admin','manager','operator']::public.member_role[]);
  perform public.sales_assert_feature(v_doc.organization_id);
  if v_doc.status <> 'DRAFT' then raise exception 'only draft quotes can be sent'; end if;
  select count(*) into v_line_count from public.sales_document_lines where sales_document_id = v_doc.id;
  if v_line_count < 1 then raise exception 'quote must have at least one line'; end if;
  perform public.validate_sales_customer(v_doc.organization_id, v_doc.counterparty_id);
  perform public.refresh_sales_document_totals(v_doc.id);
  perform set_config('sales.engine_write', '1', true);
  update public.sales_documents
  set status = 'SENT',
      counterparty_snapshot = public.build_counterparty_snapshot(v_doc.organization_id, v_doc.counterparty_id),
      is_commercially_frozen = true
  where id = v_doc.id returning * into v_doc;
  perform set_config('sales.engine_write', '0', true);
  perform public.sales_write_audit(
    v_doc.organization_id, v_uid, 'sales.quote.sent', v_doc.id, 'send',
    jsonb_build_object('internal_number', v_doc.internal_number, 'total', v_doc.total, 'currency_code', v_doc.currency_code)
  );
  return v_doc;
end;
$$;
create or replace function public.accept_quote(p_document_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select * into v_doc from public.sales_documents where id = p_document_id for update;
  if v_doc.id is null then raise exception 'document not found'; end if;
  if v_doc.document_type <> 'QUOTE' then raise exception 'not a quote'; end if;
  perform public.sales_assert_role(v_doc.organization_id, array['owner','admin','manager']::public.member_role[]);
  perform public.sales_assert_feature(v_doc.organization_id);
  if v_doc.status <> 'SENT' then raise exception 'only sent quotes can be accepted'; end if;
  if v_doc.valid_until is not null and v_doc.valid_until < (timezone('utc', now()))::date then
    raise exception 'quote is expired';
  end if;
  perform set_config('sales.engine_write', '1', true);
  update public.sales_documents
  set status = 'ACCEPTED', confirmed_by = v_uid, confirmed_at = timezone('utc', now())
  where id = v_doc.id returning * into v_doc;
  perform set_config('sales.engine_write', '0', true);
  perform public.sales_write_audit(
    v_doc.organization_id, v_uid, 'sales.quote.accepted', v_doc.id, 'accept',
    jsonb_build_object('internal_number', v_doc.internal_number)
  );
  return v_doc;
end;
$$;
create or replace function public.reject_quote(p_document_id uuid, p_reason text default null)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select * into v_doc from public.sales_documents where id = p_document_id for update;
  if v_doc.document_type <> 'QUOTE' then raise exception 'not a quote'; end if;
  perform public.sales_assert_role(v_doc.organization_id, array['owner','admin','manager']::public.member_role[]);
  perform public.sales_assert_feature(v_doc.organization_id);
  if v_doc.status not in ('SENT', 'ACCEPTED') then raise exception 'quote cannot be rejected from this status'; end if;
  perform set_config('sales.engine_write', '1', true);
  update public.sales_documents
  set status = 'REJECTED', cancelled_at = timezone('utc', now()), cancel_reason = nullif(trim(p_reason), '')
  where id = p_document_id returning * into v_doc;
  perform set_config('sales.engine_write', '0', true);
  perform public.sales_write_audit(v_doc.organization_id, v_uid, 'sales.quote.rejected', v_doc.id, 'reject', '{}'::jsonb);
  return v_doc;
end;
$$;
create or replace function public.cancel_sales_document(p_document_id uuid, p_reason text default null)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select * into v_doc from public.sales_documents where id = p_document_id for update;
  perform public.sales_assert_role(v_doc.organization_id, array['owner','admin','manager']::public.member_role[]);
  perform public.sales_assert_feature(v_doc.organization_id);
  if v_doc.document_type = 'QUOTE' and v_doc.status in ('CONVERTED', 'REJECTED', 'CANCELLED') then
    raise exception 'quote cannot be cancelled';
  end if;
  if v_doc.document_type = 'SALES_ORDER' and v_doc.status in ('READY_TO_INVOICE', 'INVOICED', 'CANCELLED') then
    raise exception 'order cannot be cancelled';
  end if;
  perform set_config('sales.engine_write', '1', true);
  update public.sales_documents
  set status = 'CANCELLED', cancelled_at = timezone('utc', now()), cancel_reason = nullif(trim(p_reason), '')
  where id = p_document_id returning * into v_doc;
  perform set_config('sales.engine_write', '0', true);
  perform public.sales_write_audit(
    v_doc.organization_id, v_uid,
    case when v_doc.document_type = 'QUOTE' then 'sales.quote.cancelled' else 'sales.order.cancelled' end,
    v_doc.id, 'cancel', '{}'::jsonb
  );
  return v_doc;
end;
$$;
create or replace function public.convert_quote_to_order(p_quote_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_quote public.sales_documents;
  v_order public.sales_documents;
  v_number text;
  r record;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select * into v_quote from public.sales_documents where id = p_quote_id for update;
  if v_quote.document_type <> 'QUOTE' then raise exception 'not a quote'; end if;
  perform public.sales_assert_role(v_quote.organization_id, array['owner','admin','manager']::public.member_role[]);
  perform public.sales_assert_feature(v_quote.organization_id);
  if v_quote.converted_to_order_id is not null then
    select * into v_order from public.sales_documents where id = v_quote.converted_to_order_id;
    return v_order;
  end if;
  if v_quote.status <> 'ACCEPTED' then raise exception 'only accepted quotes can be converted'; end if;
  perform public.validate_sales_customer(v_quote.organization_id, v_quote.counterparty_id);
  v_number := public.next_sales_internal_number(v_quote.organization_id, 'SALES_ORDER', v_quote.document_date);
  perform set_config('sales.engine_write', '1', true);
  insert into public.sales_documents (
    organization_id, branch_id, document_type, internal_number, counterparty_id, status,
    document_date, expected_delivery_date, currency_code, description, customer_reference,
    payment_terms_text, payment_due_days, notes, source_document_id,
    counterparty_snapshot, subtotal, discount_total, total,
    is_commercially_frozen, created_by
  ) values (
    v_quote.organization_id, v_quote.branch_id, 'SALES_ORDER', v_number, v_quote.counterparty_id, 'DRAFT',
    v_quote.document_date, v_quote.expected_delivery_date, v_quote.currency_code, v_quote.description,
    v_quote.customer_reference, v_quote.payment_terms_text, v_quote.payment_due_days, v_quote.notes,
    v_quote.id, v_quote.counterparty_snapshot, v_quote.subtotal, v_quote.discount_total, v_quote.total,
    true, v_uid
  ) returning * into v_order;
  for r in select * from public.sales_document_lines where sales_document_id = v_quote.id order by line_number loop
    insert into public.sales_document_lines (
      organization_id, sales_document_id, line_number, description, quantity, unit_code,
      unit_price, discount_input_mode, discount_percent, discount_amount,
      line_subtotal, line_total, notes
    ) values (
      r.organization_id, v_order.id, r.line_number, r.description, r.quantity, r.unit_code,
      r.unit_price, r.discount_input_mode, r.discount_percent, r.discount_amount,
      r.line_subtotal, r.line_total, r.notes
    );
  end loop;
  update public.sales_documents
  set status = 'CONVERTED', converted_to_order_id = v_order.id
  where id = v_quote.id;
  perform set_config('sales.engine_write', '0', true);
  perform public.sales_write_audit(
    v_quote.organization_id, v_uid, 'sales.quote.converted', v_quote.id, 'convert',
    jsonb_build_object('order_id', v_order.id, 'order_number', v_order.internal_number)
  );
  perform public.sales_write_audit(
    v_order.organization_id, v_uid, 'sales.order.created', v_order.id, 'create',
    jsonb_build_object('source_quote_id', v_quote.id, 'from_conversion', true)
  );
  return v_order;
end;
$$;
create or replace function public.confirm_sales_order(p_order_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
  v_lines int;
  v_snapshot jsonb;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select * into v_doc from public.sales_documents where id = p_order_id for update;
  if v_doc.document_type <> 'SALES_ORDER' then raise exception 'not a sales order'; end if;
  perform public.sales_assert_role(v_doc.organization_id, array['owner','admin','manager']::public.member_role[]);
  perform public.sales_assert_feature(v_doc.organization_id);
  if v_doc.status <> 'DRAFT' then raise exception 'only draft orders can be confirmed'; end if;
  perform public.validate_sales_customer(v_doc.organization_id, v_doc.counterparty_id);
  select count(*) into v_lines from public.sales_document_lines where sales_document_id = v_doc.id;
  if v_lines < 1 then raise exception 'order must have at least one line'; end if;
  perform public.refresh_sales_document_totals(v_doc.id);
  if v_doc.source_document_id is null then
    v_snapshot := public.build_counterparty_snapshot(v_doc.organization_id, v_doc.counterparty_id);
  else
    v_snapshot := v_doc.counterparty_snapshot;
  end if;
  perform set_config('sales.engine_write', '1', true);
  update public.sales_documents
  set status = 'CONFIRMED', confirmed_by = v_uid, confirmed_at = timezone('utc', now()),
      counterparty_snapshot = v_snapshot, is_commercially_frozen = true
  where id = v_doc.id returning * into v_doc;
  perform set_config('sales.engine_write', '0', true);
  perform public.sales_write_audit(
    v_doc.organization_id, v_uid, 'sales.order.confirmed', v_doc.id, 'confirm',
    jsonb_build_object('internal_number', v_doc.internal_number, 'total', v_doc.total)
  );
  return v_doc;
end;
$$;
create or replace function public.mark_order_ready_to_invoice(p_order_id uuid)
returns public.sales_documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.sales_documents;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select * into v_doc from public.sales_documents where id = p_order_id for update;
  if v_doc.document_type <> 'SALES_ORDER' then raise exception 'not a sales order'; end if;
  perform public.sales_assert_role(v_doc.organization_id, array['owner','admin','manager','accountant']::public.member_role[]);
  perform public.sales_assert_feature(v_doc.organization_id);
  if v_doc.status = 'READY_TO_INVOICE' then return v_doc; end if;
  if v_doc.status <> 'CONFIRMED' then raise exception 'only confirmed orders can be marked ready to invoice'; end if;
  perform set_config('sales.engine_write', '1', true);
  update public.sales_documents set status = 'READY_TO_INVOICE' where id = p_order_id returning * into v_doc;
  perform set_config('sales.engine_write', '0', true);
  perform public.sales_write_audit(
    v_doc.organization_id, v_uid, 'sales.order.ready_to_invoice', v_doc.id, 'ready',
    jsonb_build_object('internal_number', v_doc.internal_number)
  );
  return v_doc;
end;
$$;
grant execute on function public.send_quote(uuid) to authenticated;
grant execute on function public.accept_quote(uuid) to authenticated;
grant execute on function public.reject_quote(uuid, text) to authenticated;
grant execute on function public.cancel_sales_document(uuid, text) to authenticated;
grant execute on function public.convert_quote_to_order(uuid) to authenticated;
grant execute on function public.confirm_sales_order(uuid) to authenticated;
grant execute on function public.mark_order_ready_to_invoice(uuid) to authenticated;
create or replace function public.bootstrap_organization_modules(
  p_organization_id uuid,
  p_enable_feature_codes text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_code text;
  v_fid uuid;
  v_rel public.feature_release_controls%rowtype;
  v_codes text[];
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.has_org_role(
    p_organization_id,
    array['owner', 'admin']::public.member_role[]
  ) then
    raise exception 'MODULES_CONFIGURE_DENIED';
  end if;

  perform public.modules_lock_organization(p_organization_id);

  v_codes := array['dashboard', 'accounting'];
  foreach v_code in array coalesce(p_enable_feature_codes, '{}') loop
    if v_code is null or v_code = any (v_codes) then continue; end if;
    v_codes := array_append(v_codes, v_code);
  end loop;

  foreach v_code in array v_codes loop
    select id into v_fid from public.feature_catalog where code = v_code and active;
    if v_fid is null then continue; end if;
    select * into v_rel from public.feature_release_controls where feature_id = v_fid;

    if v_code = 'medical_legal'
       or coalesce(v_rel.release_status, 'COMING_SOON') in (
         'COMING_SOON'::public.feature_release_status,
         'RESTRICTED'::public.feature_release_status,
         'BLOCKED'::public.feature_release_status,
         'RETIRED'::public.feature_release_status
       )
    then
      continue;
    end if;

    insert into public.organization_feature_entitlements (
      organization_id, feature_id, status, source_type, metadata, granted_at, granted_by
    ) values (
      p_organization_id, v_fid, 'GRANTED', 'SYSTEM',
      jsonb_build_object('bootstrap', true), timezone('utc', now()), v_uid
    )
    on conflict (organization_id, feature_id) do update set
      status = 'GRANTED'::public.feature_entitlement_status,
      updated_at = timezone('utc', now());

    insert into public.organization_feature_preferences (
      organization_id, feature_id, desired_enabled, updated_by
    ) values (p_organization_id, v_fid, true, v_uid)
    on conflict (organization_id, feature_id) do update set
      desired_enabled = true,
      updated_by = excluded.updated_by,
      updated_at = timezone('utc', now());
  end loop;

  select id into v_fid from public.feature_catalog where code = 'medical_legal';
  if v_fid is not null then
    insert into public.organization_feature_entitlements (
      organization_id, feature_id, status, source_type, metadata
    ) values (
      p_organization_id, v_fid, 'RESTRICTED', 'SYSTEM', jsonb_build_object('bootstrap', true)
    ) on conflict do nothing;
    insert into public.organization_feature_preferences (
      organization_id, feature_id, desired_enabled, updated_by
    ) values (p_organization_id, v_fid, false, v_uid)
    on conflict do nothing;
  end if;

  return public.recompute_organization_features(p_organization_id, v_uid, 'bootstrap');
end;
$$;
revoke all on function public.bootstrap_organization_modules(uuid, text[]) from public, anon;
grant execute on function public.bootstrap_organization_modules(uuid, text[]) to authenticated;
comment on function public.bootstrap_organization_modules(uuid, text[]) is
  'SECURITY DEFINER intentional: new-org bootstrap. Explicit codes only; default_status is not authority.';
