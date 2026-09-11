-- Phase 6 — Purchase RPCs (numbering, approve OC, review, post, reverse)

create or replace function public.purchase_assert_feature(p_org_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare v_ok boolean;
begin
  select exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = 'purchases'
      and ofeat.status = 'enabled'
  ) into v_ok;
  if not coalesce(v_ok, false) then
    raise exception 'purchases feature is not enabled for this organization';
  end if;
end;
$$;
create or replace function public.purchase_assert_role(
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
    raise exception 'insufficient role for purchase operation';
  end if;
end;
$$;
create or replace function public.assert_active_supplier(
  p_org_id uuid,
  p_supplier_id uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare v_active boolean; v_role boolean;
begin
  select c.is_active into v_active
  from public.counterparties c
  where c.organization_id = p_org_id and c.id = p_supplier_id;
  if not found then raise exception 'supplier not found'; end if;
  if not coalesce(v_active, false) then raise exception 'supplier is inactive'; end if;

  select exists (
    select 1 from public.counterparty_roles r
    where r.organization_id = p_org_id
      and r.counterparty_id = p_supplier_id
      and r.role = 'SUPPLIER'
  ) into v_role;
  if not coalesce(v_role, false) then
    raise exception 'counterparty does not have SUPPLIER role';
  end if;
end;
$$;
create or replace function public.next_purchase_order_number(p_org_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year int := extract(year from timezone('utc', now()))::int;
  v_next bigint;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  perform public.purchase_assert_feature(p_org_id);
  perform public.purchase_assert_role(
    p_org_id, array['owner','admin','manager','operator']::public.member_role[]
  );

  insert into public.purchase_order_sequences (organization_id, sequence_year, last_value)
  values (p_org_id, v_year, 1)
  on conflict (organization_id, sequence_year)
  do update set
    last_value = public.purchase_order_sequences.last_value + 1,
    updated_at = timezone('utc', now())
  returning last_value into v_next;

  return 'OC-' || v_year::text || '-' || lpad(v_next::text, 6, '0');
end;
$$;
create or replace function public.build_supplier_snapshot(
  p_org_id uuid,
  p_supplier_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare v_snap jsonb;
begin
  select jsonb_build_object(
    'counterparty_id', c.id,
    'legal_name', c.legal_name,
    'trade_name', c.trade_name,
    'tax_id_type', c.tax_id_type,
    'tax_id', c.tax_id,
    'tax_id_normalized', c.tax_id_normalized,
    'fiscal_condition_code', fc.code,
    'fiscal_address', cfp.fiscal_address
  )
  into v_snap
  from public.counterparties c
  left join public.counterparty_fiscal_profiles cfp
    on cfp.organization_id = c.organization_id and cfp.counterparty_id = c.id
  left join public.fiscal_conditions fc on fc.id = cfp.fiscal_condition_id
  where c.organization_id = p_org_id and c.id = p_supplier_id;

  if v_snap is null then raise exception 'supplier not found for snapshot'; end if;
  return v_snap;
end;
$$;
create or replace function public.approve_purchase_order(p_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_po public.purchase_orders%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select * into v_po from public.purchase_orders where id = p_order_id for update;
  if not found then raise exception 'purchase order not found'; end if;

  perform public.purchase_assert_feature(v_po.organization_id);
  perform public.purchase_assert_role(
    v_po.organization_id, array['owner','admin','manager']::public.member_role[]
  );
  perform public.assert_active_supplier(v_po.organization_id, v_po.supplier_id);

  if v_po.status is distinct from 'DRAFT' then
    raise exception 'only DRAFT purchase orders can be approved';
  end if;
  if not exists (
    select 1 from public.purchase_order_lines where purchase_order_id = p_order_id
  ) then
    raise exception 'purchase order has no lines';
  end if;

  update public.purchase_orders
  set status = 'APPROVED',
      approved_by = v_uid,
      approved_at = timezone('utc', now()),
      supplier_snapshot = public.build_supplier_snapshot(v_po.organization_id, v_po.supplier_id),
      updated_at = timezone('utc', now())
  where id = p_order_id;

  return p_order_id;
end;
$$;
create or replace function public.complete_purchase_order(p_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_po public.purchase_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  select * into v_po from public.purchase_orders where id = p_order_id for update;
  if not found then raise exception 'purchase order not found'; end if;
  perform public.purchase_assert_feature(v_po.organization_id);
  perform public.purchase_assert_role(
    v_po.organization_id, array['owner','admin','manager']::public.member_role[]
  );
  if v_po.status is distinct from 'APPROVED' then
    raise exception 'only APPROVED purchase orders can be completed';
  end if;
  -- COMPLETED = commercial/documentary completion — NOT inventory receiving
  update public.purchase_orders
  set status = 'COMPLETED',
      completed_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where id = p_order_id;
  return p_order_id;
end;
$$;
create or replace function public.mark_purchase_reviewed(p_document_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_doc public.purchase_documents%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  select * into v_doc from public.purchase_documents where id = p_document_id for update;
  if not found then raise exception 'purchase document not found'; end if;
  perform public.purchase_assert_feature(v_doc.organization_id);
  perform public.purchase_assert_role(
    v_doc.organization_id,
    array['owner','admin','manager','accountant']::public.member_role[]
  );
  if v_doc.status not in ('DRAFT', 'REJECTED') then
    raise exception 'cannot review from status %', v_doc.status;
  end if;
  if v_doc.currency_code is distinct from 'ARS' then
    raise exception 'Phase 6 MVP allows ARS only';
  end if;
  if abs(
    (v_doc.net_taxed_amount + v_doc.net_exempt_amount + v_doc.net_untaxed_amount
      + v_doc.vat_amount + v_doc.other_taxes_amount) - v_doc.total_amount
  ) > 0.01 then
    raise exception 'purchase totals do not reconcile';
  end if;
  if not exists (
    select 1 from public.purchase_document_lines where purchase_document_id = p_document_id
  ) then
    raise exception 'purchase document has no lines';
  end if;

  update public.purchase_documents
  set status = 'REVIEWED',
      reviewed_by = auth.uid(),
      reviewed_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where id = p_document_id;
  return p_document_id;
end;
$$;
create or replace function public.post_purchase_document(p_document_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.purchase_documents%rowtype;
  v_map public.purchase_accounting_mappings%rowtype;
  v_period_id uuid;
  v_entry_id uuid;
  v_existing uuid;
  v_direction public.accounts_payable_direction;
  v_expense_account uuid;
  v_line record;
  v_line_no int := 0;
  v_expense_total numeric(19,4);
  v_ap_total numeric(19,4);
  v_lines_expense numeric(19,4);
  v_snap jsonb;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select * into v_doc from public.purchase_documents where id = p_document_id for update;
  if not found then raise exception 'purchase document not found'; end if;

  perform public.purchase_assert_feature(v_doc.organization_id);
  perform public.purchase_assert_role(
    v_doc.organization_id,
    array['owner','admin','accountant']::public.member_role[]
  );

  -- Idempotent: already posted
  if v_doc.status = 'POSTED' and v_doc.journal_entry_id is not null then
    return p_document_id;
  end if;

  if v_doc.status is distinct from 'REVIEWED' then
    raise exception 'document must be REVIEWED before posting';
  end if;

  if v_doc.currency_code is distinct from 'ARS' then
    raise exception 'unsupported currency for Phase 6: %', v_doc.currency_code;
  end if;

  perform public.assert_active_supplier(v_doc.organization_id, v_doc.supplier_id);

  if abs(
    (v_doc.net_taxed_amount + v_doc.net_exempt_amount + v_doc.net_untaxed_amount
      + v_doc.vat_amount + v_doc.other_taxes_amount) - v_doc.total_amount
  ) > 0.01 then
    raise exception 'purchase totals do not reconcile';
  end if;

  select * into v_map
  from public.purchase_accounting_mappings
  where organization_id = v_doc.organization_id;
  if not found then
    raise exception 'Falta configurar el mapeo contable de compras';
  end if;

  if v_doc.other_taxes_amount > 0 and v_map.other_taxes_account_id is null then
    raise exception 'Falta configurar la cuenta contable para otros impuestos.';
  end if;

  -- Closed period → require review, no partial journal, never rewrite issue_date
  -- Persist status and return (do not RAISE — that would roll back the status write).
  select period_id into v_period_id
  from public.resolve_open_period(v_doc.organization_id, v_doc.accounting_date);
  if v_period_id is null then
    perform set_config('purchase.engine_write', '1', true);
    update public.purchase_documents
    set accounting_status = 'ACCOUNTING_REQUIRES_REVIEW',
        updated_at = timezone('utc', now())
    where id = p_document_id;
    return p_document_id;
  end if;

  -- Existing journal for this source? (idempotent retry)
  select id into v_existing
  from public.journal_entries
  where organization_id = v_doc.organization_id
    and source_type = 'PURCHASE'
    and source_id = p_document_id
    and status = 'POSTED'
  limit 1;
  if v_existing is not null then
    perform set_config('purchase.engine_write', '1', true);
    update public.purchase_documents
    set status = 'POSTED',
        journal_entry_id = v_existing,
        accounting_status = 'POSTED',
        supplier_snapshot = case
          when supplier_snapshot = '{}'::jsonb
            then public.build_supplier_snapshot(v_doc.organization_id, v_doc.supplier_id)
          else supplier_snapshot
        end,
        posted_by = coalesce(posted_by, v_uid),
        posted_at = coalesce(posted_at, timezone('utc', now())),
        updated_at = timezone('utc', now())
    where id = p_document_id;

    insert into public.accounts_payable_items (
      organization_id, supplier_id, purchase_document_id, direction,
      original_amount, open_amount, currency_code, due_date, status
    ) values (
      v_doc.organization_id, v_doc.supplier_id, p_document_id,
      case
        when v_doc.document_type = 'SUPPLIER_CREDIT_NOTE'
          then 'AP_DECREASE'::public.accounts_payable_direction
        else 'AP_INCREASE'::public.accounts_payable_direction
      end,
      v_doc.total_amount, v_doc.total_amount, 'ARS', v_doc.due_date, 'OPEN'
    )
    on conflict (purchase_document_id) do nothing;

    return p_document_id;
  end if;

  v_snap := public.build_supplier_snapshot(v_doc.organization_id, v_doc.supplier_id);
  v_direction := case
    when v_doc.document_type = 'SUPPLIER_CREDIT_NOTE' then 'AP_DECREASE'::public.accounts_payable_direction
    else 'AP_INCREASE'::public.accounts_payable_direction
  end;

  v_expense_total := v_doc.net_taxed_amount + v_doc.net_exempt_amount + v_doc.net_untaxed_amount;
  v_ap_total := v_doc.total_amount;

  select coalesce(sum(net_amount + exempt_amount + untaxed_amount), 0)
    into v_lines_expense
  from public.purchase_document_lines
  where purchase_document_id = p_document_id;

  if abs(v_lines_expense - v_expense_total) > 0.01 then
    raise exception 'line net totals do not match document expense totals';
  end if;

  insert into public.journal_entries (
    organization_id, entry_date, description, status, source_type, source_id, created_by
  ) values (
    v_doc.organization_id,
    v_doc.accounting_date,
    'Compra ' || v_doc.document_type::text || ' ' || coalesce(v_doc.point_of_sale::text || '-', '') || coalesce(v_doc.document_number::text, ''),
    'DRAFT',
    'PURCHASE',
    p_document_id,
    v_uid
  )
  returning id into v_entry_id;

  -- Build lines depending on direction
  if v_direction = 'AP_INCREASE' then
    -- Debit expenses (from lines or default)
    for v_line in
      select * from public.purchase_document_lines
      where purchase_document_id = p_document_id
      order by line_number
    loop
      v_line_no := v_line_no + 1;
      v_expense_account := coalesce(v_line.account_id, v_map.default_expense_account_id);
      if v_expense_account is null then
        raise exception 'Falta cuenta de gasto en línea % o mapeo default_expense_account', v_line.line_number;
      end if;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id, cost_center_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_expense_account, v_line.description,
        v_line.net_amount + v_line.exempt_amount + v_line.untaxed_amount, 0,
        v_doc.supplier_id, v_line.cost_center_id
      );
    end loop;

    if v_doc.vat_amount > 0 then
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_map.vat_input_account_id,
        'IVA informado (captura comprobante)',
        v_doc.vat_amount, 0, v_doc.supplier_id
      );
    end if;

    if v_doc.other_taxes_amount > 0 then
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_map.other_taxes_account_id,
        'Otros impuestos del comprobante',
        v_doc.other_taxes_amount, 0, v_doc.supplier_id
      );
    end if;

    v_line_no := v_line_no + 1;
    insert into public.journal_entry_lines (
      organization_id, journal_entry_id, line_number, account_id, description,
      debit, credit, counterparty_id
    ) values (
      v_doc.organization_id, v_entry_id, v_line_no, v_map.accounts_payable_account_id,
      'Proveedores',
      0, v_ap_total, v_doc.supplier_id
    );
  else
    -- AP_DECREASE (credit note): debit AP, credit expense/VAT/other
    v_line_no := 1;
    insert into public.journal_entry_lines (
      organization_id, journal_entry_id, line_number, account_id, description,
      debit, credit, counterparty_id
    ) values (
      v_doc.organization_id, v_entry_id, v_line_no, v_map.accounts_payable_account_id,
      'Proveedores (NC)',
      v_ap_total, 0, v_doc.supplier_id
    );

    for v_line in
      select * from public.purchase_document_lines
      where purchase_document_id = p_document_id
      order by line_number
    loop
      v_line_no := v_line_no + 1;
      v_expense_account := coalesce(v_line.account_id, v_map.default_expense_account_id);
      if v_expense_account is null then
        raise exception 'Falta cuenta de gasto en línea % o mapeo default_expense_account', v_line.line_number;
      end if;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id, cost_center_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_expense_account, v_line.description,
        0, v_line.net_amount + v_line.exempt_amount + v_line.untaxed_amount,
        v_doc.supplier_id, v_line.cost_center_id
      );
    end loop;

    if v_doc.vat_amount > 0 then
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_map.vat_input_account_id,
        'IVA informado (NC)',
        0, v_doc.vat_amount, v_doc.supplier_id
      );
    end if;

    if v_doc.other_taxes_amount > 0 then
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_map.other_taxes_account_id,
        'Otros impuestos (NC)',
        0, v_doc.other_taxes_amount, v_doc.supplier_id
      );
    end if;
  end if;

  -- Post via Phase 2 engine; clean up DRAFT on failure (no partial journal)
  begin
    perform public.post_journal_entry(v_entry_id);
  exception when others then
    delete from public.journal_entries where id = v_entry_id and status = 'DRAFT';
    raise;
  end;

  perform set_config('purchase.engine_write', '1', true);

  update public.purchase_documents
  set status = 'POSTED',
      accounting_status = 'POSTED',
      journal_entry_id = v_entry_id,
      supplier_snapshot = v_snap,
      supplier_tax_id_normalized = v_snap->>'tax_id_normalized',
      posted_by = v_uid,
      posted_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where id = p_document_id;

  -- AP item (idempotent via unique purchase_document_id)
  insert into public.accounts_payable_items (
    organization_id, supplier_id, purchase_document_id, direction,
    original_amount, open_amount, currency_code, due_date, status
  ) values (
    v_doc.organization_id, v_doc.supplier_id, p_document_id, v_direction,
    v_ap_total, v_ap_total, 'ARS', v_doc.due_date, 'OPEN'
  )
  on conflict (purchase_document_id) do nothing;

  return p_document_id;
end;
$$;
create or replace function public.reverse_purchase_document(
  p_document_id uuid,
  p_reversal_date date default current_date,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_doc public.purchase_documents%rowtype;
  v_rev public.journal_entries%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  select * into v_doc from public.purchase_documents where id = p_document_id for update;
  if not found then raise exception 'purchase document not found'; end if;
  perform public.purchase_assert_feature(v_doc.organization_id);
  perform public.purchase_assert_role(
    v_doc.organization_id,
    array['owner','admin','accountant']::public.member_role[]
  );

  if v_doc.status = 'REVERSED' then
    return p_document_id; -- idempotent
  end if;
  if v_doc.status is distinct from 'POSTED' or v_doc.journal_entry_id is null then
    raise exception 'only POSTED purchases with journal can be reversed';
  end if;

  select * into v_rev from public.reverse_journal_entry(
    v_doc.journal_entry_id, p_reversal_date, coalesce(p_reason, 'Reversión compra')
  );

  perform set_config('purchase.engine_write', '1', true);

  update public.purchase_documents
  set status = 'REVERSED',
      reverse_journal_entry_id = v_rev.id,
      accounting_status = 'POSTED',
      updated_at = timezone('utc', now())
  where id = p_document_id;

  update public.accounts_payable_items
  set status = 'VOID',
      open_amount = 0,
      updated_at = timezone('utc', now())
  where purchase_document_id = p_document_id;

  return p_document_id;
end;
$$;
create or replace function public.supplier_ap_net_open(p_org_id uuid, p_supplier_id uuid)
returns numeric
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(sum(
    case
      when direction = 'AP_INCREASE' then open_amount
      when direction = 'AP_DECREASE' then -open_amount
      else 0
    end
  ), 0)
  from public.accounts_payable_items
  where organization_id = p_org_id
    and supplier_id = p_supplier_id
    and status = 'OPEN';
$$;
revoke all on function public.purchase_assert_feature(uuid) from public, anon;
revoke all on function public.purchase_assert_role(uuid, public.member_role[]) from public, anon;
revoke all on function public.assert_active_supplier(uuid, uuid) from public, anon;
revoke all on function public.next_purchase_order_number(uuid) from public, anon;
revoke all on function public.build_supplier_snapshot(uuid, uuid) from public, anon;
revoke all on function public.approve_purchase_order(uuid) from public, anon;
revoke all on function public.complete_purchase_order(uuid) from public, anon;
revoke all on function public.mark_purchase_reviewed(uuid) from public, anon;
revoke all on function public.post_purchase_document(uuid) from public, anon;
revoke all on function public.reverse_purchase_document(uuid, date, text) from public, anon;
revoke all on function public.supplier_ap_net_open(uuid, uuid) from public, anon;
grant execute on function public.next_purchase_order_number(uuid) to authenticated;
grant execute on function public.build_supplier_snapshot(uuid, uuid) to authenticated;
grant execute on function public.approve_purchase_order(uuid) to authenticated;
grant execute on function public.complete_purchase_order(uuid) to authenticated;
grant execute on function public.mark_purchase_reviewed(uuid) to authenticated;
grant execute on function public.post_purchase_document(uuid) to authenticated;
grant execute on function public.reverse_purchase_document(uuid, date, text) to authenticated;
grant execute on function public.supplier_ap_net_open(uuid, uuid) to authenticated;
grant execute on function public.assert_active_supplier(uuid, uuid) to authenticated;
