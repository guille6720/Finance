-- Phase 11: service_role-only mixed margin staging fixture (STOCK + SERVICE → expect stock_net - cogs)

create or replace function public.analytics_test_fixture_mixed_product_margin(
  p_organization_id uuid,
  p_issue_date date,
  p_stock_net numeric,
  p_service_net numeric,
  p_cogs numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stock_prod uuid;
  v_svc_prod uuid;
  v_wh uuid;
  v_branch uuid;
  v_sales_doc uuid;
  v_stock_line uuid;
  v_svc_line uuid;
  v_dtype public.fiscal_document_types%rowtype;
  v_fd uuid;
  v_pos uuid;
  v_pos_n int;
  v_cp uuid;
  v_rule uuid;
  v_op uuid;
  v_iol uuid;
  v_stamp text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'analytics_test_fixture_mixed_product_margin is service_role only';
  end if;

  select id into v_branch
  from public.branches
  where organization_id = p_organization_id
  limit 1;

  insert into public.warehouses (
    organization_id, branch_id, code, name, active
  ) values (
    p_organization_id, v_branch, 'WHMGN' || upper(substr(v_stamp, 1, 4)), 'Margin fixture WH', true
  )
  returning id into v_wh;

  insert into public.products (
    organization_id, sku, name, product_type, base_unit_code, track_inventory, active
  ) values (
    p_organization_id, 'MGN-S-' || upper(v_stamp), 'Margin Stock Item',
    'STOCK_ITEM', 'UNIT', true, true
  )
  returning id into v_stock_prod;

  insert into public.products (
    organization_id, sku, name, product_type, base_unit_code, track_inventory, active
  ) values (
    p_organization_id, 'MGN-V-' || upper(v_stamp), 'Margin Service',
    'SERVICE', 'UNIT', false, true
  )
  returning id into v_svc_prod;

  select c.id into v_cp
  from public.counterparties c
  where c.organization_id = p_organization_id
    and c.tax_id_normalized = public.normalize_counterparty_tax_id('CUIT', '20111111112')
  limit 1;
  if v_cp is null then
    insert into public.counterparties (
      organization_id, legal_name, tax_id_type, tax_id, is_active
    ) values (
      p_organization_id, 'Margin Fixture CP', 'CUIT', '20111111112', true
    ) returning id into v_cp;
  end if;
  insert into public.counterparty_roles (organization_id, counterparty_id, role)
  values (p_organization_id, v_cp, 'CUSTOMER')
  on conflict do nothing;

  insert into public.sales_documents (
    organization_id, document_type, internal_number, counterparty_id, status,
    document_date, currency_code, subtotal, discount_total, total, branch_id
  ) values (
    p_organization_id, 'SALES_ORDER', 'SO-MGN-' || v_stamp, v_cp, 'CONFIRMED',
    p_issue_date, 'ARS', p_stock_net + p_service_net, 0, p_stock_net + p_service_net, v_branch
  )
  returning id into v_sales_doc;

  insert into public.sales_document_lines (
    organization_id, sales_document_id, line_number, product_id,
    description, quantity, unit_code, unit_price, line_subtotal, line_total
  ) values (
    p_organization_id, v_sales_doc, 1, v_stock_prod,
    'Stock line', 1, 'UNIT', p_stock_net, p_stock_net, p_stock_net
  )
  returning id into v_stock_line;

  insert into public.sales_document_lines (
    organization_id, sales_document_id, line_number, product_id,
    description, quantity, unit_code, unit_price, line_subtotal, line_total
  ) values (
    p_organization_id, v_sales_doc, 2, v_svc_prod,
    'Service line', 1, 'UNIT', p_service_net, p_service_net, p_service_net
  )
  returning id into v_svc_line;

  select * into v_dtype from public.fiscal_document_types where internal_code = 'INVOICE_A' limit 1;

  insert into public.fiscal_points_of_sale (
    organization_id, environment, arca_point_of_sale, description, is_active
  ) values (
    p_organization_id, 'HOMOLOGATION', 88, 'Margin fixture POS', true
  )
  on conflict (organization_id, environment, arca_point_of_sale) do update
    set description = excluded.description
  returning id into v_pos;
  if v_pos is null then
    select id into v_pos from public.fiscal_points_of_sale
    where organization_id = p_organization_id
      and environment = 'HOMOLOGATION'
      and arca_point_of_sale = 88;
  end if;
  select arca_point_of_sale into v_pos_n from public.fiscal_points_of_sale where id = v_pos;

  select id into v_rule
  from public.fiscal_rule_versions
  where organization_id = p_organization_id and status = 'ACTIVE'
  order by effective_from desc limit 1;
  if v_rule is null then
    insert into public.fiscal_rule_versions (
      organization_id, code, version, effective_from, source_reference, status, rules
    ) values (
      p_organization_id, 'MGN_FIX', 1, '2020-01-01', 'margin fixture', 'ACTIVE', '{}'::jsonb
    ) returning id into v_rule;
  end if;

  perform set_config('fiscal.engine_write', '1', true);

  -- Insert AUTHORIZED header first, then lines (engine_write allows line insert)
  insert into public.fiscal_documents (
    organization_id, document_type_id, document_class, arca_cbte_tipo,
    point_of_sale_id, arca_point_of_sale, document_number,
    status, fiscal_environment, issue_date, counterparty_id,
    currency_code, currency_rate,
    net_taxed_amount, net_exempt_amount, net_untaxed_amount,
    vat_amount, other_taxes_amount, total_amount,
    cae, authorized_at, fiscal_rule_version_id, idempotency_key
  ) values (
    p_organization_id, v_dtype.id, v_dtype.document_class, v_dtype.arca_cbte_tipo,
    v_pos, v_pos_n, (extract(epoch from clock_timestamp()) * 1000)::bigint,
    'AUTHORIZED', 'HOMOLOGATION', p_issue_date, v_cp,
    'PES', 1,
    p_stock_net + p_service_net, 0, 0,
    0, 0, p_stock_net + p_service_net,
    'MGNCAE' || substr(v_stamp, 1, 8),
    timezone('utc', now()), v_rule, 'mgn-fix-' || gen_random_uuid()::text
  )
  returning id into v_fd;

  insert into public.fiscal_document_lines (
    organization_id, fiscal_document_id, line_number,
    description, quantity, unit_price, net_amount, vat_amount, line_total,
    source_sales_line_id
  ) values
    (p_organization_id, v_fd, 1, 'Stock', 1, p_stock_net, p_stock_net, 0, p_stock_net, v_stock_line),
    (p_organization_id, v_fd, 2, 'Service', 1, p_service_net, p_service_net, 0, p_service_net, v_svc_line);

  insert into public.fiscal_tax_summaries (
    organization_id, fiscal_document_id, summary_kind, code, base_amount, rate, amount
  ) values (
    p_organization_id, v_fd, 'IVA', '5', p_stock_net + p_service_net, 0, 0
  );

  perform set_config('inventory.engine_write', '1', true);

  insert into public.inventory_operations (
    organization_id, internal_number, operation_type, status, accounting_status,
    operation_date, warehouse_id, description, idempotency_key, posted_at
  ) values (
    p_organization_id, 'ISS-MGN-' || v_stamp, 'ISSUE', 'POSTED', 'NOT_APPLICABLE',
    p_issue_date, v_wh, 'margin fixture issue', 'mgn-iss-' || gen_random_uuid()::text,
    timezone('utc', now())
  )
  returning id into v_op;

  insert into public.inventory_operation_lines (
    organization_id, inventory_operation_id, line_number, product_id, warehouse_id,
    direction, quantity, unit_code, unit_cost, value_delta, source_sales_line_id
  ) values (
    p_organization_id, v_op, 1, v_stock_prod, v_wh,
    'OUT', 1, 'UNIT', p_cogs, p_cogs, v_stock_line
  )
  returning id into v_iol;

  insert into public.inventory_ledger_entries (
    organization_id, inventory_operation_id, inventory_operation_line_id,
    product_id, warehouse_id, movement_date, operation_type, direction,
    quantity, unit_cost, value_delta
  ) values (
    p_organization_id, v_op, v_iol,
    v_stock_prod, v_wh, p_issue_date, 'ISSUE', 'OUT',
    1, p_cogs, p_cogs
  );

  return jsonb_build_object(
    'fiscal_document_id', v_fd,
    'stock_sales_line_id', v_stock_line,
    'service_sales_line_id', v_svc_line,
    'expected_margin', (p_stock_net - p_cogs)
  );
end;
$$;
revoke all on function public.analytics_test_fixture_mixed_product_margin(uuid, date, numeric, numeric, numeric)
  from public, anon, authenticated;
grant execute on function public.analytics_test_fixture_mixed_product_margin(uuid, date, numeric, numeric, numeric)
  to service_role;
