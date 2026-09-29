-- Public preview (Staging only): tester slots and synthetic demo data per tester organization.
--
-- Reconciles objects first created by hand in Staging (staging_tester_slots,
-- seed_staging_demo_counterparties, staging_reserve_tester_and_seed) and adds the full
-- demo seed. Everything stays inert until public.preview_demo_settings holds an enabled
-- row; migrations never insert that row, so Production is unaffected.
--
-- The demo seed is SECURITY INVOKER: it runs as the tester (owner) through RLS and the
-- existing posting engines (post_treasury_operation, post_purchase_document,
-- confirm_sales_order, ensure_tax_period). No row is written as POSTED directly and no
-- fiscal document, CAE or ARCA call is involved.

-- ---------------------------------------------------------------------------
-- Tester slots (one per user, max 5, concurrency-safe via advisory lock)
-- ---------------------------------------------------------------------------
create table if not exists public.staging_tester_slots (
  slot_no smallint primary key check (slot_no >= 1 and slot_no <= 5),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  organization_id uuid not null unique references public.organizations(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.staging_tester_slots enable row level security;
revoke all on table public.staging_tester_slots from public, anon, authenticated;
grant all on table public.staging_tester_slots to service_role;

-- ---------------------------------------------------------------------------
-- Preview switch (singleton). No row = disabled.
-- ---------------------------------------------------------------------------
create table if not exists public.preview_demo_settings (
  id boolean primary key default true check (id),
  enabled boolean not null default false,
  max_testers smallint not null default 5 check (max_testers >= 1 and max_testers <= 5),
  enabled_since timestamptz not null default now(),
  exempt_email_domains text[] not null default array['example.invalid']::text[],
  updated_at timestamptz not null default now()
);

alter table public.preview_demo_settings enable row level security;
revoke all on table public.preview_demo_settings from public, anon, authenticated;
grant all on table public.preview_demo_settings to service_role;

create or replace function public.preview_demo_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select s.enabled from public.preview_demo_settings s where s.id), false);
$$;

revoke all on function public.preview_demo_enabled() from public, anon;
grant execute on function public.preview_demo_enabled() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Slot reservation on organization creation. Raising rolls back the organization
-- insert, so a rejected attempt never consumes a slot. Users created before the
-- preview was enabled and internal domains (demo accounts) are exempt.
-- ---------------------------------------------------------------------------
create or replace function public.staging_reserve_tester_and_seed()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $function$
declare
  v_settings public.preview_demo_settings%rowtype;
  v_user_created_at timestamptz;
  v_email text;
  v_slot smallint;
begin
  select * into v_settings from public.preview_demo_settings s where s.id;
  if not found or not v_settings.enabled or new.created_by is null then
    return new;
  end if;

  select u.created_at, lower(u.email)
    into v_user_created_at, v_email
  from auth.users u
  where u.id = new.created_by;

  if v_user_created_at is null or v_user_created_at < v_settings.enabled_since then
    return new;
  end if;
  if split_part(coalesce(v_email, ''), '@', 2) = any (v_settings.exempt_email_domains) then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext('finance_staging_public_tester_slots_v1'));

  if exists (select 1 from public.staging_tester_slots s where s.user_id = new.created_by) then
    return new;
  end if;

  select gs::smallint
    into v_slot
  from generate_series(1, v_settings.max_testers) gs
  where not exists (select 1 from public.staging_tester_slots s where s.slot_no = gs)
  order by gs
  limit 1;

  if v_slot is null then
    raise exception using
      errcode = 'P0001',
      message = 'STAGING_TESTER_LIMIT_REACHED',
      detail = 'Public preview is limited to ' || v_settings.max_testers || ' tester accounts.';
  end if;

  insert into public.staging_tester_slots (slot_no, user_id, organization_id)
  values (v_slot, new.created_by, new.id);

  return new;
end;
$function$;

revoke all on function public.staging_reserve_tester_and_seed() from public, anon, authenticated;

create or replace trigger trg_staging_reserve_tester_and_seed
after insert on public.organizations
for each row execute function public.staging_reserve_tester_and_seed();

-- Kept for parity with Staging; the trigger no longer calls it (the demo seed below
-- creates the same counterparties by external_code).
create or replace function public.seed_staging_demo_counterparties(p_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  v_actor uuid;
  v_row record;
  v_counterparty_id uuid;
begin
  perform pg_advisory_xact_lock(hashtext('seed_staging_demo_counterparties:' || p_organization_id::text));

  select o.created_by into v_actor from public.organizations o where o.id = p_organization_id;
  if v_actor is null then
    raise exception 'Organization not found: %', p_organization_id;
  end if;

  for v_row in
    select * from (values
      ('DEMO-CUST-001','Almacén Horizonte','CUSTOMER'::public.counterparty_role,'ventas@horizonte.demo','11 5555-1001'),
      ('DEMO-CUST-002','Estudio Río Plata','CUSTOMER'::public.counterparty_role,'administracion@rioplata.demo','11 5555-1002'),
      ('DEMO-CUST-003','Comercial Andina','CUSTOMER'::public.counterparty_role,'compras@andina.demo','11 5555-1003'),
      ('DEMO-CUST-004','Servicios del Sur','CUSTOMER'::public.counterparty_role,'contacto@delsur.demo','11 5555-1004'),
      ('DEMO-CUST-005','Mercado Central Demo','CUSTOMER'::public.counterparty_role,'cuentas@mercadocentral.demo','11 5555-1005'),
      ('DEMO-SUP-001','Distribuidora Norte','SUPPLIER'::public.counterparty_role,'pedidos@norte.demo','11 5555-2001'),
      ('DEMO-SUP-002','Insumos Delta','SUPPLIER'::public.counterparty_role,'ventas@delta.demo','11 5555-2002'),
      ('DEMO-SUP-003','Logística Federal','SUPPLIER'::public.counterparty_role,'operaciones@federal.demo','11 5555-2003'),
      ('DEMO-SUP-004','Tecnología Pampeana','SUPPLIER'::public.counterparty_role,'cuentas@pampeana.demo','11 5555-2004'),
      ('DEMO-SUP-005','Papelera del Plata','SUPPLIER'::public.counterparty_role,'comercial@papelera.demo','11 5555-2005')
    ) as x(external_code, legal_name, role, email, phone)
  loop
    select c.id into v_counterparty_id
    from public.counterparties c
    where c.organization_id = p_organization_id and c.external_code = v_row.external_code
    limit 1;

    if v_counterparty_id is null then
      insert into public.counterparties (
        organization_id, entity_type, legal_name, trade_name, tax_id_type, external_code,
        email, phone, notes, is_active, created_by
      ) values (
        p_organization_id, 'LEGAL_ENTITY'::public.counterparty_entity_type, v_row.legal_name,
        v_row.legal_name, 'NONE'::public.tax_id_type, v_row.external_code, v_row.email, v_row.phone,
        'Dato de demostración generado automáticamente en Staging.', true, v_actor
      )
      returning id into v_counterparty_id;
    end if;

    insert into public.counterparty_roles (counterparty_id, organization_id, role, created_by)
    values (v_counterparty_id, p_organization_id, v_row.role, v_actor)
    on conflict (counterparty_id, role) do nothing;
  end loop;
end;
$function$;

revoke all on function public.seed_staging_demo_counterparties(uuid) from public, anon, authenticated;
grant execute on function public.seed_staging_demo_counterparties(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Eligibility: preview enabled, caller is owner, the organization holds a tester slot
-- and is not a platform demo organization.
-- ---------------------------------------------------------------------------
create or replace function public.preview_demo_org_eligible(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.preview_demo_enabled()
    and exists (
      select 1 from public.staging_tester_slots s where s.organization_id = p_organization_id
    )
    and not exists (
      select 1 from public.organization_settings os
      where os.organization_id = p_organization_id and os.key = 'demo.is_demo'
    )
    and public.has_org_role(p_organization_id, array['owner']::public.member_role[]);
$$;

revoke all on function public.preview_demo_org_eligible(uuid) from public, anon;
grant execute on function public.preview_demo_org_eligible(uuid) to authenticated, service_role;

create or replace function public.preview_demo_seed_status(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_opening boolean;
  v_complete boolean;
begin
  if not public.preview_demo_org_eligible(p_organization_id) then
    return jsonb_build_object('eligible', false, 'complete', false);
  end if;

  v_opening := exists (
    select 1
    from public.treasury_operations o
    join public.treasury_operation_legs l on l.treasury_operation_id = o.id
    join public.treasury_accounts ta on ta.id = l.treasury_account_id
    where o.organization_id = p_organization_id
      and o.operation_type = 'OPENING_BALANCE'
      and o.status = 'POSTED'
      and ta.account_type = 'CASH'
  );

  v_complete := v_opening
    and (
      select count(*) from public.treasury_operations o
      where o.organization_id = p_organization_id
        and o.idempotency_key in (
          'staging-demo-collection-001', 'staging-demo-payment-001', 'staging-demo-transfer-001'
        )
        and o.status = 'POSTED'
    ) = 3
    and (
      select count(*) from public.purchase_documents d
      where d.organization_id = p_organization_id
        and d.idempotency_key in ('staging-demo-purchase-001', 'staging-demo-purchase-002')
        and d.status = 'POSTED'
    ) = 2
    and (
      select count(*) from public.sales_documents d
      where d.organization_id = p_organization_id
        and d.document_type = 'SALES_ORDER'
        and d.customer_reference in ('staging-demo-sale-001', 'staging-demo-sale-002', 'staging-demo-sale-003')
        and d.status in ('CONFIRMED', 'READY_TO_INVOICE', 'INVOICED')
    ) = 3;

  return jsonb_build_object('eligible', true, 'complete', v_complete);
end;
$function$;

revoke all on function public.preview_demo_seed_status(uuid) from public, anon;
grant execute on function public.preview_demo_seed_status(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Demo seed. Idempotent: every record is keyed (external_code, sku, idempotency_key,
-- customer_reference) and existing rows are reused or only advanced through the
-- engines. One transaction: a failure leaves nothing half-written.
-- ---------------------------------------------------------------------------
create or replace function public.seed_preview_demo_data(p_organization_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_org uuid := p_organization_id;
  v_branch uuid;
  v_cash_ta uuid;
  v_bank_ta uuid;
  v_row record;
  v_id uuid;
  v_status text;
  v_num text;
  v_ap_item uuid;
  v_offset uuid;
  v_map_id uuid;
  v_map_offset uuid;
  v_parent uuid;
  v_level int;
  v_customers uuid[] := array[]::uuid[];
  v_suppliers uuid[] := array[]::uuid[];
  v_purchases uuid[] := array[]::uuid[];
  v_month int;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;
  if not public.preview_demo_org_eligible(v_org) then
    raise exception using errcode = 'P0001', message = 'PREVIEW_DEMO_NOT_ALLOWED';
  end if;

  perform pg_advisory_xact_lock(hashtext('seed_preview_demo_data:' || v_org::text));

  select b.id into v_branch
  from public.branches b
  where b.organization_id = v_org
  order by b.is_main desc, b.created_at
  limit 1;

  select ta.id into v_cash_ta
  from public.treasury_accounts ta
  where ta.organization_id = v_org and ta.account_type = 'CASH' and ta.is_active and ta.currency_code = 'ARS'
  order by (ta.code = 'CAJA') desc, ta.code
  limit 1;

  select ta.id into v_bank_ta
  from public.treasury_accounts ta
  where ta.organization_id = v_org and ta.account_type = 'BANK' and ta.is_active and ta.currency_code = 'ARS'
  order by (ta.code = 'BANCO') desc, ta.code
  limit 1;

  if v_cash_ta is null or v_bank_ta is null then
    raise exception using errcode = 'P0001', message = 'PREVIEW_DEMO_MISSING_TREASURY_ACCOUNTS';
  end if;

  -- Counterparties: synthetic names, no tax id (tax_id_type NONE).
  for v_row in
    select * from (values
      ('DEMO-CUST-001','Almacén Horizonte','CUSTOMER','ventas@horizonte.demo','11 5555-1001'),
      ('DEMO-CUST-002','Estudio Río Plata','CUSTOMER','administracion@rioplata.demo','11 5555-1002'),
      ('DEMO-CUST-003','Comercial Andina','CUSTOMER','compras@andina.demo','11 5555-1003'),
      ('DEMO-CUST-004','Servicios del Sur','CUSTOMER','contacto@delsur.demo','11 5555-1004'),
      ('DEMO-CUST-005','Mercado Central Demo','CUSTOMER','cuentas@mercadocentral.demo','11 5555-1005'),
      ('DEMO-SUP-001','Distribuidora Norte','SUPPLIER','pedidos@norte.demo','11 5555-2001'),
      ('DEMO-SUP-002','Insumos Delta','SUPPLIER','ventas@delta.demo','11 5555-2002'),
      ('DEMO-SUP-003','Logística Federal','SUPPLIER','operaciones@federal.demo','11 5555-2003'),
      ('DEMO-SUP-004','Tecnología Pampeana','SUPPLIER','cuentas@pampeana.demo','11 5555-2004'),
      ('DEMO-SUP-005','Papelera del Plata','SUPPLIER','comercial@papelera.demo','11 5555-2005')
    ) as x(external_code, legal_name, role, email, phone)
  loop
    select c.id into v_id
    from public.counterparties c
    where c.organization_id = v_org and c.external_code = v_row.external_code
    order by c.created_at
    limit 1;

    if v_id is null then
      insert into public.counterparties (
        organization_id, entity_type, legal_name, trade_name, tax_id_type, external_code,
        email, phone, notes, is_active, created_by
      ) values (
        v_org, 'LEGAL_ENTITY', v_row.legal_name, v_row.legal_name, 'NONE', v_row.external_code,
        v_row.email, v_row.phone, 'Dato de demostración (sintético).', true, v_uid
      )
      returning id into v_id;
    end if;

    insert into public.counterparty_roles (counterparty_id, organization_id, role, created_by)
    values (v_id, v_org, v_row.role::public.counterparty_role, v_uid)
    on conflict (counterparty_id, role) do nothing;

    if v_row.role = 'CUSTOMER' then
      v_customers := v_customers || v_id;
    else
      v_suppliers := v_suppliers || v_id;
    end if;
  end loop;

  -- Products: 3 stock items, 2 services.
  for v_row in
    select * from (values
      ('DEMO-PRD-001','Resma de papel A4 (demo)','STOCK_ITEM','UNIT',true,9500::numeric,6200::numeric),
      ('DEMO-PRD-002','Tóner para impresora (demo)','STOCK_ITEM','UNIT',true,48000::numeric,31000::numeric),
      ('DEMO-PRD-003','Silla de oficina (demo)','STOCK_ITEM','UNIT',true,120000::numeric,78000::numeric),
      ('DEMO-SRV-001','Mantenimiento mensual (demo)','SERVICE','UNIT',false,60000::numeric,null::numeric),
      ('DEMO-SRV-002','Hora de consultoría (demo)','SERVICE','HOUR',false,19000::numeric,null::numeric)
    ) as x(sku, name, product_type, unit, track, sale, purchase)
  loop
    if not exists (
      select 1 from public.products p where p.organization_id = v_org and p.sku = v_row.sku
    ) then
      insert into public.products (
        organization_id, sku, name, product_type, base_unit_code, track_inventory, active,
        default_sale_price, default_purchase_price, created_by
      ) values (
        v_org, v_row.sku, v_row.name, v_row.product_type::public.product_type,
        v_row.unit::public.inventory_unit_code, v_row.track, true, v_row.sale, v_row.purchase, v_uid
      );
    end if;
  end loop;

  -- Purchases: DRAFT -> REVIEWED -> POSTED through the purchase engine.
  for v_row in
    select * from (values
      ('staging-demo-purchase-001', 1, date '2026-08-05', 60000::numeric, 12600::numeric, 'Insumos de oficina (demo)'),
      ('staging-demo-purchase-002', 2, date '2026-09-08', 80000::numeric, 16800::numeric, 'Servicio de logística (demo)')
    ) as x(idem, supplier_idx, doc_date, net, vat, description)
  loop
    select d.id, d.status::text into v_id, v_status
    from public.purchase_documents d
    where d.organization_id = v_org and d.idempotency_key = v_row.idem;

    if v_id is null then
      insert into public.purchase_documents (
        organization_id, branch_id, supplier_id, document_type, issue_date, accounting_date,
        due_date, currency_code, currency_rate, net_taxed_amount, vat_amount, total_amount,
        status, external_reference, idempotency_key, notes, created_by
      ) values (
        v_org, v_branch, v_suppliers[v_row.supplier_idx], 'SUPPLIER_INVOICE', v_row.doc_date,
        v_row.doc_date, v_row.doc_date + 30, 'ARS', 1, v_row.net, v_row.vat, v_row.net + v_row.vat,
        'DRAFT', upper(v_row.idem), v_row.idem, 'Comprobante de prueba (datos sintéticos).', v_uid
      )
      returning id into v_id;
      v_status := 'DRAFT';
    end if;

    if v_status in ('DRAFT', 'REJECTED') then
      if not exists (
        select 1 from public.purchase_document_lines l where l.purchase_document_id = v_id
      ) then
        insert into public.purchase_document_lines (
          organization_id, purchase_document_id, line_number, description, quantity, unit_code,
          unit_price, vat_treatment, net_amount, vat_amount, line_total
        ) values (
          v_org, v_id, 1, v_row.description, 1, 'UNIT', v_row.net, 'TAXED', v_row.net, v_row.vat,
          v_row.net + v_row.vat
        );
      end if;
      perform public.mark_purchase_reviewed(v_id);
      v_status := 'REVIEWED';
    end if;

    if v_status = 'REVIEWED' then
      perform public.post_purchase_document(v_id);
      select d.status::text into v_status from public.purchase_documents d where d.id = v_id;
    end if;

    if v_status not in ('POSTED', 'REVERSED') then
      raise exception using errcode = 'P0001', message = 'PREVIEW_DEMO_PURCHASE_NOT_POSTED';
    end if;
    v_purchases := v_purchases || v_id;
  end loop;

  -- Offset account for treasury adjustments (only filled when the mapping has none).
  select m.id, m.adjustment_offset_account_id into v_map_id, v_map_offset
  from public.treasury_accounting_mappings m
  where m.organization_id = v_org;

  if v_map_offset is null then
    select a.id into v_offset
    from public.accounts a
    where a.organization_id = v_org and a.code = '4.1.90' and a.is_postable and a.account_type = 'REVENUE';

    if v_offset is null then
      select a.parent_id, a.level into v_parent, v_level
      from public.accounts a
      where a.organization_id = v_org and a.system_role = 'sales'
      limit 1;

      insert into public.accounts (
        organization_id, parent_id, code, name, account_type, normal_balance, level, is_postable
      ) values (
        v_org, v_parent, '4.1.90', 'Otros ingresos y ajustes de caja', 'REVENUE', 'CREDIT',
        coalesce(v_level, 2), true
      )
      returning id into v_offset;
    end if;

    if v_map_id is null then
      insert into public.treasury_accounting_mappings (organization_id, adjustment_offset_account_id)
      values (v_org, v_offset);
    else
      update public.treasury_accounting_mappings
      set adjustment_offset_account_id = v_offset, updated_at = timezone('utc', now())
      where id = v_map_id and adjustment_offset_account_id is null;
    end if;
  end if;

  -- Treasury: opening +150.000, customer collection +85.000, supplier payment -42.000,
  -- cash -> bank 30.000. Cash ends at 163.000, bank at 30.000.
  -- A collection can only be allocated to receivables born from authorized fiscal
  -- invoices, so the demo collection is a cash ADJUSTMENT with an explicit reason.
  for v_row in
    select * from (values
      ('staging-demo-opening-cash', 'OPENING_BALANCE', date '2026-07-01', 150000::numeric,
        'Saldo inicial de caja (demo)', null::text),
      ('staging-demo-collection-001', 'ADJUSTMENT', date '2026-08-12', 85000::numeric,
        'Cobro a cliente sin factura (demo)',
        'Cobro de cliente registrado como ingreso de caja: dato de prueba sin factura fiscal.'),
      ('staging-demo-payment-001', 'PAYMENT', date '2026-09-05', 42000::numeric,
        'Pago parcial a proveedor (demo)', null::text),
      ('staging-demo-transfer-001', 'TRANSFER', date '2026-09-15', 30000::numeric,
        'Depósito de caja en banco (demo)', null::text)
    ) as x(idem, op_type, op_date, amount, description, reason)
  loop
    select o.id, o.status::text into v_id, v_status
    from public.treasury_operations o
    where o.organization_id = v_org and o.idempotency_key = v_row.idem;

    continue when v_id is not null and v_status <> 'DRAFT';

    if v_id is null then
      -- Respect an opening balance the tester already posted on the cash box.
      continue when v_row.op_type = 'OPENING_BALANCE' and exists (
        select 1
        from public.treasury_operation_legs l
        join public.treasury_operations o on o.id = l.treasury_operation_id
        where l.treasury_account_id = v_cash_ta
          and o.operation_type = 'OPENING_BALANCE'
          and o.status = 'POSTED'
      );

      v_num := public.next_treasury_operation_number(v_org, v_row.op_type::public.treasury_operation_type);
      insert into public.treasury_operations (
        organization_id, branch_id, internal_number, operation_type, status, operation_date,
        counterparty_id, amount, currency_code, reference, description, reason, idempotency_key,
        created_by
      ) values (
        v_org, v_branch, v_num, v_row.op_type::public.treasury_operation_type, 'DRAFT', v_row.op_date,
        case v_row.op_type
          when 'ADJUSTMENT' then v_customers[1]
          when 'PAYMENT' then v_suppliers[1]
        end,
        v_row.amount, 'ARS', upper(v_row.idem), v_row.description, v_row.reason, v_row.idem, v_uid
      )
      returning id into v_id;
    end if;

    if not exists (
      select 1 from public.treasury_operation_legs l where l.treasury_operation_id = v_id
    ) then
      if v_row.op_type = 'TRANSFER' then
        insert into public.treasury_operation_legs (
          organization_id, treasury_operation_id, treasury_account_id, direction, amount, line_number
        ) values
          (v_org, v_id, v_cash_ta, 'OUTFLOW', v_row.amount, 1),
          (v_org, v_id, v_bank_ta, 'INFLOW', v_row.amount, 2);
      else
        insert into public.treasury_operation_legs (
          organization_id, treasury_operation_id, treasury_account_id, direction, amount, line_number
        ) values (
          v_org, v_id, v_cash_ta,
          case when v_row.op_type = 'PAYMENT' then 'OUTFLOW' else 'INFLOW' end::public.treasury_leg_direction,
          v_row.amount, 1
        );
      end if;
    end if;

    if v_row.op_type = 'PAYMENT' and not exists (
      select 1 from public.payment_allocations pa where pa.treasury_operation_id = v_id
    ) then
      select ap.id into v_ap_item
      from public.accounts_payable_items ap
      where ap.organization_id = v_org and ap.purchase_document_id = v_purchases[1];
      if v_ap_item is null then
        raise exception using errcode = 'P0001', message = 'PREVIEW_DEMO_MISSING_PAYABLE';
      end if;
      insert into public.payment_allocations (
        organization_id, treasury_operation_id, accounts_payable_item_id, allocated_amount
      ) values (v_org, v_id, v_ap_item, v_row.amount);
    end if;

    perform public.post_treasury_operation(v_id);

    select o.status::text into v_status from public.treasury_operations o where o.id = v_id;
    if v_status <> 'POSTED' then
      raise exception using errcode = 'P0001', message = 'PREVIEW_DEMO_TREASURY_NOT_POSTED';
    end if;
  end loop;

  -- Sales orders through the sales engine (commercial only: no fiscal invoice).
  for v_row in
    select * from (values
      ('staging-demo-sale-001', 1, date '2026-07-15', 'Mantenimiento mensual (demo)', 'UNIT',
        2::numeric, 60000::numeric, 'CONFIRMED'),
      ('staging-demo-sale-002', 2, date '2026-08-20', 'Consultoría contable (demo)', 'HOUR',
        5::numeric, 19000::numeric, 'READY_TO_INVOICE'),
      ('staging-demo-sale-003', 3, date '2026-09-10', 'Equipamiento de oficina (demo)', 'UNIT',
        1::numeric, 145000::numeric, 'READY_TO_INVOICE')
    ) as x(ref, customer_idx, doc_date, description, unit, quantity, unit_price, target)
  loop
    select d.id, d.status::text into v_id, v_status
    from public.sales_documents d
    where d.organization_id = v_org and d.document_type = 'SALES_ORDER' and d.customer_reference = v_row.ref;

    if v_id is null then
      v_num := public.next_sales_internal_number(v_org, 'SALES_ORDER', v_row.doc_date);
      insert into public.sales_documents (
        organization_id, branch_id, document_type, internal_number, counterparty_id, status,
        document_date, currency_code, customer_reference, notes, created_by
      ) values (
        v_org, v_branch, 'SALES_ORDER', v_num, v_customers[v_row.customer_idx], 'DRAFT',
        v_row.doc_date, 'ARS', v_row.ref, 'Pedido de prueba (datos sintéticos, sin factura fiscal).', v_uid
      )
      returning id into v_id;
      v_status := 'DRAFT';
    end if;

    if v_status = 'DRAFT' then
      if not exists (
        select 1 from public.sales_document_lines l where l.sales_document_id = v_id
      ) then
        insert into public.sales_document_lines (
          organization_id, sales_document_id, line_number, description, quantity, unit_code, unit_price
        ) values (
          v_org, v_id, 1, v_row.description, v_row.quantity,
          v_row.unit::public.sales_line_unit_code, v_row.unit_price
        );
      end if;
      perform public.confirm_sales_order(v_id);
      v_status := 'CONFIRMED';
    end if;

    if v_status = 'CONFIRMED' and v_row.target = 'READY_TO_INVOICE' then
      perform public.mark_order_ready_to_invoice(v_id);
    end if;
  end loop;

  -- IVA periods (review workspace only; nothing is filed) when the taxes module is on.
  if exists (
    select 1
    from public.organization_features f
    join public.feature_catalog fc on fc.id = f.feature_id
    where f.organization_id = v_org and fc.code = 'taxes' and f.status = 'enabled'
  ) then
    for v_month in 7..9 loop
      perform public.ensure_tax_period(v_org, 'IVA', null, 2026, v_month, 'HOMOLOGATION');
    end loop;
  end if;

  return jsonb_build_object(
    'customers', (
      select count(*) from public.counterparty_roles r
      where r.organization_id = v_org and r.role = 'CUSTOMER'
    ),
    'suppliers', (
      select count(*) from public.counterparty_roles r
      where r.organization_id = v_org and r.role = 'SUPPLIER'
    ),
    'products', (
      select count(*) from public.products p
      where p.organization_id = v_org and p.sku in ('DEMO-PRD-001','DEMO-PRD-002','DEMO-PRD-003','DEMO-SRV-001','DEMO-SRV-002')
    ),
    'treasury_posted', (
      select count(*) from public.treasury_operations o
      where o.organization_id = v_org and o.idempotency_key like 'staging-demo-%' and o.status = 'POSTED'
    ),
    'purchases_posted', (
      select count(*) from public.purchase_documents d
      where d.organization_id = v_org and d.idempotency_key like 'staging-demo-purchase-%' and d.status = 'POSTED'
    ),
    'sales_orders', (
      select count(*) from public.sales_documents d
      where d.organization_id = v_org and d.customer_reference like 'staging-demo-sale-%'
        and d.status in ('CONFIRMED', 'READY_TO_INVOICE', 'INVOICED')
    ),
    'tax_periods', (
      select count(*) from public.tax_periods t
      where t.organization_id = v_org and t.workspace_environment = 'HOMOLOGATION'
    ),
    'cash_balance', (
      select coalesce(sum(case when l.direction = 'INFLOW' then l.amount else -l.amount end), 0)
      from public.treasury_operation_legs l
      join public.treasury_operations o on o.id = l.treasury_operation_id
      where l.treasury_account_id = v_cash_ta and o.status = 'POSTED'
    ),
    'bank_balance', (
      select coalesce(sum(case when l.direction = 'INFLOW' then l.amount else -l.amount end), 0)
      from public.treasury_operation_legs l
      join public.treasury_operations o on o.id = l.treasury_operation_id
      where l.treasury_account_id = v_bank_ta and o.status = 'POSTED'
    )
  );
end;
$function$;

revoke all on function public.seed_preview_demo_data(uuid) from public, anon;
grant execute on function public.seed_preview_demo_data(uuid) to authenticated;
