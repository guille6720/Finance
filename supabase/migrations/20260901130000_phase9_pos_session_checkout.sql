-- Phase 9: POS session + checkout RPCs (STAGING ONLY)
-- Depends on: phase9_pos_core, phase9_pos_helpers
-- All RPCs: SECURITY DEFINER, search_path='', grant authenticated / revoke public+anon
-- Engine GUC pos.engine_write='1' required for pos_sales status / pos_sessions expected fields.
-- Engine GUC sales.engine_write='1' required for sales_documents status transitions.

-- ===========================================================================
-- 1. open_pos_session
-- ===========================================================================

create or replace function public.open_pos_session(
  p_terminal_id         uuid,
  p_opening_counted_cash numeric,
  p_idempotency_key     text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_terminal   public.pos_terminals%rowtype;
  v_cash_acct  uuid;
  v_expected   numeric;
  v_session_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  -- Lock terminal to prevent concurrent opens
  select * into v_terminal
  from public.pos_terminals
  where id = p_terminal_id
  for update;

  if not found then raise exception 'terminal not found'; end if;
  if not v_terminal.active then raise exception 'terminal is not active'; end if;

  if not public.has_org_role(
    v_terminal.organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  ) then
    raise exception 'insufficient role to open POS session';
  end if;

  perform public.pos_assert_feature(v_terminal.organization_id);

  -- Idempotency
  select id into v_session_id
  from public.pos_sessions
  where organization_id = v_terminal.organization_id
    and idempotency_key = p_idempotency_key;
  if v_session_id is not null then return v_session_id; end if;

  -- Require an active CASH tender account mapping for this terminal
  select treasury_account_id into v_cash_acct
  from public.pos_terminal_tender_accounts
  where terminal_id = p_terminal_id
    and method = 'CASH'
    and active
  limit 1;

  if v_cash_acct is null then
    raise exception 'terminal has no active CASH tender account; configure pos_terminal_tender_accounts first';
  end if;

  -- Opening expected = current ledger balance of the CASH account (POSTED legs only)
  v_expected := public.treasury_account_balance(v_cash_acct);

  perform set_config('pos.engine_write', '1', true);

  insert into public.pos_sessions (
    organization_id, terminal_id, cashier_id, status,
    opening_expected_cash, opening_counted_cash, idempotency_key
  ) values (
    v_terminal.organization_id, p_terminal_id, v_uid, 'OPEN',
    v_expected, p_opening_counted_cash, p_idempotency_key
  )
  returning id into v_session_id;
  -- Unique index pos_sessions_one_open_per_terminal enforces one OPEN per terminal.

  return v_session_id;
end;
$$;
-- ===========================================================================
-- 2. close_pos_session
-- ===========================================================================

create or replace function public.close_pos_session(
  p_session_id          uuid,
  p_closing_counted_cash numeric,
  p_idempotency_key     text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid             uuid := auth.uid();
  v_session         public.pos_sessions%rowtype;
  v_opening_base    numeric;
  v_cash_posted     numeric;
  v_closing_expected numeric;
  v_difference      numeric;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_session
  from public.pos_sessions
  where id = p_session_id
  for update;

  if not found then raise exception 'session not found'; end if;

  if not public.has_org_role(
    v_session.organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  ) then
    raise exception 'insufficient role to close POS session';
  end if;

  perform public.pos_assert_feature(v_session.organization_id);

  -- Idempotent if already closed
  if v_session.status = 'CLOSED' then return v_session.id; end if;

  -- Block on dangerous in-flight states
  if exists (
    select 1 from public.pos_sales
    where session_id = p_session_id
      and status in (
        'STOCK_RESERVED','WAITING_FISCAL','FISCAL_AUTHORIZED',
        'FINALIZING','RECONCILIATION_REQUIRED'
      )
  ) then
    raise exception 'session has sales in pending states (STOCK_RESERVED/WAITING_FISCAL/...); '
                    'complete or reconcile them before closing';
  end if;

  -- Block on unresolved open sales
  if exists (
    select 1 from public.pos_sales
    where session_id = p_session_id
      and status in ('DRAFT','READY_TO_CHECKOUT')
  ) then
    raise exception 'session has open sales (DRAFT/READY_TO_CHECKOUT); '
                    'cancel them explicitly before closing';
  end if;

  -- Closing expected:
  --   base = opening_counted_cash (actual counted) or opening_expected_cash if not counted
  --   + sum of all POSTED CASH tender amounts for COMPLETED sales in this session
  v_opening_base := coalesce(v_session.opening_counted_cash, v_session.opening_expected_cash);

  select coalesce(sum(pt.amount), 0) into v_cash_posted
  from public.pos_tenders pt
  join public.pos_sales ps on ps.id = pt.pos_sale_id
  where ps.session_id = p_session_id
    and ps.status = 'COMPLETED'
    and pt.method = 'CASH'
    and pt.status = 'POSTED';

  v_closing_expected := v_opening_base + v_cash_posted;
  v_difference       := coalesce(p_closing_counted_cash, 0) - v_closing_expected;

  perform set_config('pos.engine_write', '1', true);

  update public.pos_sessions
  set status                = 'CLOSED',
      closed_at             = timezone('utc', now()),
      closing_counted_cash  = p_closing_counted_cash,
      closing_expected_cash = v_closing_expected,
      closing_difference    = v_difference
  where id = p_session_id;

  return p_session_id;
end;
$$;
-- ===========================================================================
-- 3. start_pos_sale
-- ===========================================================================

create or replace function public.start_pos_sale(
  p_session_id      uuid,
  p_idempotency_key text,
  p_customer_id     uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid            uuid := auth.uid();
  v_org_id         uuid;
  v_session        public.pos_sessions%rowtype;
  v_terminal       public.pos_terminals%rowtype;
  v_settings       public.pos_settings%rowtype;
  v_customer_id    uuid;
  v_internal_num   text;
  v_sales_doc_id   uuid;
  v_pos_sale_id    uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  -- Fast idempotency check before locking
  select organization_id into v_org_id
  from public.pos_sessions
  where id = p_session_id;

  if v_org_id is null then raise exception 'session not found'; end if;

  select id into v_pos_sale_id
  from public.pos_sales
  where organization_id = v_org_id
    and idempotency_key = p_idempotency_key;
  if v_pos_sale_id is not null then return v_pos_sale_id; end if;

  select * into v_session
  from public.pos_sessions
  where id = p_session_id
  for share;

  if v_session.status <> 'OPEN' then
    raise exception 'session is not OPEN (status: %)', v_session.status;
  end if;

  if not public.has_org_role(
    v_session.organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  ) then
    raise exception 'insufficient role to start POS sale';
  end if;

  perform public.pos_assert_feature(v_session.organization_id);

  select * into v_terminal
  from public.pos_terminals
  where id = v_session.terminal_id
    and organization_id = v_session.organization_id;
  if not found then raise exception 'terminal not found'; end if;

  select * into v_settings
  from public.pos_settings
  where organization_id = v_session.organization_id;

  -- Customer: explicit arg > terminal default > org walk-in default
  v_customer_id := coalesce(
    p_customer_id,
    v_terminal.default_customer_id,
    v_settings.default_walk_in_customer_id
  );

  if v_customer_id is null then
    raise exception 'no customer resolved; set pos_settings.default_walk_in_customer_id';
  end if;

  perform public.pos_validate_walk_in_customer(v_session.organization_id, v_customer_id);

  -- Allocate sales internal number
  v_internal_num := public.next_sales_internal_number(
    v_session.organization_id,
    'SALES_ORDER'::public.sales_document_type,
    current_date
  );

  perform set_config('sales.engine_write', '1', true);

  insert into public.sales_documents (
    organization_id, branch_id, document_type, internal_number,
    counterparty_id, status, document_date, currency_code, created_by
  ) values (
    v_session.organization_id, v_terminal.branch_id, 'SALES_ORDER', v_internal_num,
    v_customer_id, 'DRAFT', current_date, 'ARS', v_uid
  )
  returning id into v_sales_doc_id;

  perform set_config('sales.engine_write', '0', true);
  perform set_config('pos.engine_write', '1', true);

  insert into public.pos_sales (
    organization_id, terminal_id, session_id, sales_document_id,
    status, idempotency_key, created_by
  ) values (
    v_session.organization_id, v_session.terminal_id, p_session_id, v_sales_doc_id,
    'DRAFT', p_idempotency_key, v_uid
  )
  returning id into v_pos_sale_id;

  return v_pos_sale_id;
end;
$$;
-- ===========================================================================
-- 4. cancel_pos_sale_draft
-- ===========================================================================

create or replace function public.cancel_pos_sale_draft(
  p_pos_sale_id uuid,
  p_reason      text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_sale   public.pos_sales%rowtype;
  v_res_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id
  for update;

  if not found then raise exception 'POS sale not found'; end if;

  if not public.has_org_role(
    v_sale.organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  ) then
    raise exception 'insufficient role to cancel POS sale';
  end if;

  perform public.pos_assert_feature(v_sale.organization_id);

  -- Idempotent
  if v_sale.status = 'CANCELLED' then return v_sale.id; end if;

  -- Hard deny for fiscal / completed states
  if v_sale.status in (
    'WAITING_FISCAL','FISCAL_AUTHORIZED','FINALIZING',
    'COMPLETED','RECONCILIATION_REQUIRED'
  ) then
    raise exception 'cannot cancel POS sale in status %', v_sale.status;
  end if;

  if v_sale.status not in ('DRAFT','READY_TO_CHECKOUT','STOCK_RESERVED') then
    raise exception 'unexpected POS sale status: %', v_sale.status;
  end if;

  -- For STOCK_RESERVED: release active inventory reservations
  if v_sale.status = 'STOCK_RESERVED' then
    for v_res_id in
      select ir.id
      from public.inventory_reservations ir
      join public.sales_document_lines sdl
        on sdl.id = ir.sales_document_line_id
      where sdl.sales_document_id = v_sale.sales_document_id
        and ir.organization_id    = v_sale.organization_id
        and ir.status             = 'ACTIVE'
    loop
      perform public.release_inventory_reservation(v_res_id);
    end loop;
  end if;

  -- Cancel the underlying sales document directly.
  -- We bypass cancel_sales_document() because:
  --   (a) operators lack the manager+ role it requires, and
  --   (b) READY_TO_INVOICE orders are blocked by it for STOCK_RESERVED path.
  perform set_config('sales.engine_write', '1', true);
  update public.sales_documents
  set status       = 'CANCELLED',
      cancelled_at = timezone('utc', now()),
      cancel_reason = nullif(trim(coalesce(p_reason, '')), '')
  where id = v_sale.sales_document_id;
  perform set_config('sales.engine_write', '0', true);

  perform set_config('pos.engine_write', '1', true);
  update public.pos_sales
  set status = 'CANCELLED'
  where id = p_pos_sale_id;

  return p_pos_sale_id;
end;
$$;
-- ===========================================================================
-- 5. set_pos_tenders
-- ===========================================================================

create or replace function public.set_pos_tenders(
  p_pos_sale_id uuid,
  p_tenders     jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid           uuid := auth.uid();
  v_sale          public.pos_sales%rowtype;
  v_item          jsonb;
  v_method        public.pos_tender_method;
  v_amount        numeric;
  v_account_id    uuid;
  v_cash_received numeric;
  v_change_given  numeric;
  v_idem          text;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id
  for update;

  if not found then raise exception 'POS sale not found'; end if;

  if not public.has_org_role(
    v_sale.organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  ) then
    raise exception 'insufficient role to set tenders';
  end if;

  perform public.pos_assert_feature(v_sale.organization_id);

  if v_sale.status not in (
    'DRAFT','READY_TO_CHECKOUT','STOCK_RESERVED','WAITING_FISCAL','FISCAL_AUTHORIZED'
  ) then
    raise exception 'cannot set tenders in status %', v_sale.status;
  end if;

  -- Replace all DRAFT tenders (POSTED/REVERSED are untouched)
  delete from public.pos_tenders
  where pos_sale_id = p_pos_sale_id
    and status = 'DRAFT';

  for v_item in select * from jsonb_array_elements(p_tenders)
  loop
    v_method := (v_item->>'method')::public.pos_tender_method;
    v_amount := (v_item->>'amount')::numeric;

    if v_method is null then raise exception 'tender method is required'; end if;
    if v_amount is null or v_amount <= 0 then
      raise exception 'tender amount must be positive (got %)', v_amount;
    end if;

    -- Resolve treasury account: explicit param > terminal mapping
    v_account_id := (v_item->>'treasury_account_id')::uuid;

    if v_account_id is null then
      select treasury_account_id into v_account_id
      from public.pos_terminal_tender_accounts
      where terminal_id = v_sale.terminal_id
        and method      = v_method
        and active
      limit 1;

      if v_account_id is null then
        raise exception
          'no treasury account for method % on terminal; '
          'provide treasury_account_id or configure pos_terminal_tender_accounts',
          v_method;
      end if;
    end if;

    -- Full validation: type, org, active, mapping
    perform public.pos_validate_tender_account(
      v_sale.organization_id, v_sale.terminal_id, v_method, v_account_id
    );

    -- CASH change math
    v_cash_received := null;
    v_change_given  := null;

    if v_method = 'CASH' and (v_item->>'cash_received') is not null then
      v_cash_received := (v_item->>'cash_received')::numeric;
      if v_cash_received < v_amount then
        raise exception 'cash_received (%) must be >= amount (%)', v_cash_received, v_amount;
      end if;
      v_change_given := v_cash_received - v_amount;
    end if;

    -- Use provided idempotency_key or generate one
    v_idem := coalesce(
      nullif(trim(coalesce(v_item->>'idempotency_key', '')), ''),
      gen_random_uuid()::text
    );

    insert into public.pos_tenders (
      organization_id, pos_sale_id, method, treasury_account_id,
      amount, cash_received, change_given,
      reference, provider_label, status, idempotency_key
    ) values (
      v_sale.organization_id, p_pos_sale_id, v_method, v_account_id,
      v_amount, v_cash_received, v_change_given,
      nullif(trim(coalesce(v_item->>'reference', '')), ''),
      nullif(trim(coalesce(v_item->>'provider_label', '')), ''),
      'DRAFT', v_idem
    );
  end loop;
end;
$$;
-- ===========================================================================
-- 6. begin_pos_checkout
-- ===========================================================================

create or replace function public.begin_pos_checkout(
  p_pos_sale_id     uuid,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_sale       public.pos_sales%rowtype;
  v_terminal   public.pos_terminals%rowtype;
  v_doc        public.sales_documents%rowtype;
  v_snapshot   jsonb;
  v_line_count int;
  v_line       record;
  v_has_stock  boolean := false;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id
  for update;

  if not found then raise exception 'POS sale not found'; end if;

  if not public.has_org_role(
    v_sale.organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  ) then
    raise exception 'insufficient role for POS checkout';
  end if;

  perform public.pos_assert_feature(v_sale.organization_id);

  -- Idempotent: already past checkout initiation
  if v_sale.status in (
    'STOCK_RESERVED','WAITING_FISCAL','FISCAL_AUTHORIZED','FINALIZING','COMPLETED'
  ) then
    return v_sale.id;
  end if;

  if v_sale.status not in ('DRAFT','READY_TO_CHECKOUT') then
    raise exception 'begin_pos_checkout requires DRAFT or READY_TO_CHECKOUT (got %)', v_sale.status;
  end if;

  -- Lock and read the underlying sales document
  select * into v_doc
  from public.sales_documents
  where id = v_sale.sales_document_id
  for update;

  if v_doc.status not in ('DRAFT') then
    raise exception 'sales document is already frozen (status %); cannot re-checkout', v_doc.status;
  end if;

  -- Must have at least one line
  select count(*) into v_line_count
  from public.sales_document_lines
  where sales_document_id = v_sale.sales_document_id;

  if v_line_count < 1 then raise exception 'POS sale must have at least one line before checkout'; end if;

  -- Currency guard
  if v_doc.currency_code is distinct from 'ARS' then
    raise exception 'POS sales must be in ARS (got %)', v_doc.currency_code;
  end if;

  select * into v_terminal
  from public.pos_terminals
  where id = v_sale.terminal_id
    and organization_id = v_sale.organization_id;

  if not found then raise exception 'terminal not found'; end if;

  -- Refresh totals before freezing
  perform public.refresh_sales_document_totals(v_sale.sales_document_id);

  -- Build counterparty snapshot
  v_snapshot := public.build_counterparty_snapshot(v_sale.organization_id, v_doc.counterparty_id);

  -- Freeze the sales document: DRAFT → CONFIRMED → READY_TO_INVOICE
  -- Done inline to allow 'operator' role (confirm_sales_order requires manager+).
  perform set_config('sales.engine_write', '1', true);

  update public.sales_documents
  set status                 = 'CONFIRMED',
      confirmed_by           = v_uid,
      confirmed_at           = timezone('utc', now()),
      counterparty_snapshot  = v_snapshot,
      is_commercially_frozen = true
  where id = v_sale.sales_document_id
    and status = 'DRAFT';

  update public.sales_documents
  set status = 'READY_TO_INVOICE'
  where id = v_sale.sales_document_id
    and status = 'CONFIRMED';

  perform set_config('sales.engine_write', '0', true);

  -- Create inventory reservations for STOCK_ITEM lines only
  for v_line in
    select sdl.*
    from public.sales_document_lines sdl
    join public.products p
      on p.id = sdl.product_id
     and p.organization_id = sdl.organization_id
    where sdl.sales_document_id = v_sale.sales_document_id
      and p.product_type    = 'STOCK_ITEM'
      and p.track_inventory = true
      and p.active          = true
  loop
    -- Assert inventory feature once (on first STOCK_ITEM hit)
    if not v_has_stock then
      perform public.pos_assert_feature_code(v_sale.organization_id, 'inventory');
      v_has_stock := true;
    end if;

    perform public.create_inventory_reservation(
      v_sale.organization_id,
      v_line.product_id,
      v_terminal.warehouse_id,
      v_sale.sales_document_id,
      v_line.id,
      v_line.quantity,
      'pos-res:' || v_line.id::text   -- idempotency_key: stable per sale line
    );
  end loop;
  -- SERVICE / NON_STOCK lines: no reservation needed, skip.

  -- Transition POS sale to STOCK_RESERVED
  perform set_config('pos.engine_write', '1', true);

  update public.pos_sales
  set status              = 'STOCK_RESERVED',
      checkout_started_at = timezone('utc', now())
  where id = p_pos_sale_id;

  return p_pos_sale_id;
end;
$$;
-- ===========================================================================
-- 7. reset_pos_checkout
-- For STOCK_RESERVED only.  Releases reservations and cancels via the standard
-- cancel path.  Editable state (DRAFT lines) is NOT recoverable once the sales
-- order is commercially frozen — the correct flow is to cancel and open a new
-- sale.  See design doc D6.
-- ===========================================================================

create or replace function public.reset_pos_checkout(p_pos_sale_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_sale public.pos_sales%rowtype;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id;

  if not found then raise exception 'POS sale not found'; end if;

  if not public.has_org_role(
    v_sale.organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  ) then
    raise exception 'insufficient role to reset POS checkout';
  end if;

  if v_sale.status <> 'STOCK_RESERVED' then
    raise exception 'reset_pos_checkout only allowed in STOCK_RESERVED (got %)', v_sale.status;
  end if;

  -- Delegate: releases reservations + cancels sales doc + sets pos CANCELLED
  return public.cancel_pos_sale_draft(p_pos_sale_id, 'checkout reset by operator');
end;
$$;
-- ===========================================================================
-- 8. prepare_pos_fiscal_handoff
-- ===========================================================================

create or replace function public.prepare_pos_fiscal_handoff(
  p_pos_sale_id                  uuid,
  p_document_type_internal_code  text default null,
  p_condicion_iva_receptor_id    int  default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_sale      public.pos_sales%rowtype;
  v_terminal  public.pos_terminals%rowtype;
  v_settings  public.pos_settings%rowtype;
  v_doc_type  text;
  v_condicion int;
  v_fiscal_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id
  for update;

  if not found then raise exception 'POS sale not found'; end if;

  if not public.has_org_role(
    v_sale.organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  ) then
    raise exception 'insufficient role for POS fiscal handoff';
  end if;

  perform public.pos_assert_feature(v_sale.organization_id);
  perform public.pos_assert_feature_code(v_sale.organization_id, 'fiscal_invoicing');

  -- Idempotent: already in or past fiscal flow
  if v_sale.status in ('WAITING_FISCAL','FISCAL_AUTHORIZED','FINALIZING','COMPLETED') then
    return v_sale.fiscal_document_id;
  end if;

  if v_sale.status <> 'STOCK_RESERVED' then
    raise exception 'prepare_pos_fiscal_handoff requires STOCK_RESERVED (got %)', v_sale.status;
  end if;

  select * into v_terminal
  from public.pos_terminals
  where id = v_sale.terminal_id
    and organization_id = v_sale.organization_id;

  if not found then raise exception 'terminal not found'; end if;

  if v_terminal.fiscal_point_of_sale_id is null then
    raise exception 'terminal.fiscal_point_of_sale_id is not configured';
  end if;

  select * into v_settings
  from public.pos_settings
  where organization_id = v_sale.organization_id;

  -- Resolve document type: arg > setting > default
  v_doc_type := coalesce(
    nullif(trim(coalesce(p_document_type_internal_code, '')), ''),
    v_settings.default_document_type_internal_code,
    'INVOICE_C'
  );

  -- Resolve condición IVA receptor: arg > setting > 5 (Consumidor Final)
  v_condicion := coalesce(
    p_condicion_iva_receptor_id,
    v_settings.default_condicion_iva_receptor_id,
    5
  );

  -- Prepare fiscal invoice from the READY_TO_INVOICE sales order
  v_fiscal_id := public.prepare_fiscal_invoice_from_sales_order(
    v_sale.sales_document_id,
    v_terminal.fiscal_point_of_sale_id,
    v_doc_type,
    current_date,
    v_condicion
  );

  -- Mark READY_TO_AUTHORIZE so the application layer can call ARCA FECAE
  perform public.mark_fiscal_ready_to_authorize(v_fiscal_id);

  -- Link fiscal doc + transition POS sale
  perform set_config('pos.engine_write', '1', true);

  update public.pos_sales
  set status             = 'WAITING_FISCAL',
      fiscal_document_id = v_fiscal_id
  where id = p_pos_sale_id;

  return v_fiscal_id;
end;
$$;
-- ===========================================================================
-- 9. sync_pos_fiscal_status
-- Reads the linked fiscal_document status and advances pos_sale status accordingly.
-- The application must call this after complete_fiscal_authorization to advance
-- a WAITING_FISCAL sale to FISCAL_AUTHORIZED (or RECONCILIATION_REQUIRED).
-- ===========================================================================

create or replace function public.sync_pos_fiscal_status(p_pos_sale_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid            uuid := auth.uid();
  v_sale           public.pos_sales%rowtype;
  v_fiscal_status  text;
  v_new_status     public.pos_sale_status;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id
  for update;

  if not found then raise exception 'POS sale not found'; end if;

  if not public.has_org_role(
    v_sale.organization_id,
    array['owner','admin','manager','operator','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role to sync fiscal status';
  end if;

  perform public.pos_assert_feature(v_sale.organization_id);

  if v_sale.fiscal_document_id is null then
    raise exception 'no fiscal document linked to this POS sale';
  end if;

  -- Only meaningful while in fiscal flow
  if v_sale.status not in ('WAITING_FISCAL','FISCAL_AUTHORIZED','RECONCILIATION_REQUIRED') then
    return v_sale.status::text;
  end if;

  select status::text into v_fiscal_status
  from public.fiscal_documents
  where id = v_sale.fiscal_document_id;

  if v_fiscal_status is null then raise exception 'fiscal document not found'; end if;

  v_new_status := case v_fiscal_status
    when 'AUTHORIZED'              then 'FISCAL_AUTHORIZED'::public.pos_sale_status
    when 'RECONCILIATION_REQUIRED' then 'RECONCILIATION_REQUIRED'::public.pos_sale_status
    -- REJECTED: stay in WAITING_FISCAL so operator can fix and retry
    when 'REJECTED'                then 'WAITING_FISCAL'::public.pos_sale_status
    -- AUTHORIZING, READY_TO_AUTHORIZE, DRAFT: no change
    else v_sale.status
  end;

  if v_new_status is distinct from v_sale.status then
    perform set_config('pos.engine_write', '1', true);
    update public.pos_sales
    set status = v_new_status
    where id = p_pos_sale_id;
  end if;

  return v_new_status::text;
end;
$$;
-- ===========================================================================
-- 10. ensure_pos_walk_in_and_settings
-- Idempotent bootstrap: creates walk-in counterparty + CUSTOMER role +
-- pos_settings if any are missing for the org.
-- ===========================================================================

create or replace function public.ensure_pos_walk_in_and_settings(
  p_org_id    uuid,
  p_legal_name text default 'Consumidor Final'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := auth.uid();
  v_customer_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  if not public.has_org_role(
    p_org_id,
    array['owner','admin','accountant','manager']::public.member_role[]
  ) then
    raise exception 'insufficient role for POS settings setup';
  end if;

  perform public.pos_assert_feature(p_org_id);

  -- Find or create walk-in counterparty
  select id into v_customer_id
  from public.counterparties
  where organization_id = p_org_id
    and legal_name       = p_legal_name
    and is_active        = true
  order by created_at asc
  limit 1;

  if v_customer_id is null then
    insert into public.counterparties (
      organization_id, legal_name, is_active, created_by
    ) values (
      p_org_id, p_legal_name, true, v_uid
    )
    returning id into v_customer_id;
  end if;

  -- Ensure CUSTOMER role (idempotent)
  insert into public.counterparty_roles (organization_id, counterparty_id, role)
  values (p_org_id, v_customer_id, 'CUSTOMER')
  on conflict do nothing;

  -- Ensure pos_settings row.
  -- The pos_settings_validate_trg trigger fires BEFORE INSERT and calls
  -- pos_validate_walk_in_customer, so the CUSTOMER role must exist first (above).
  insert into public.pos_settings (organization_id, default_walk_in_customer_id)
  values (p_org_id, v_customer_id)
  on conflict (organization_id) do nothing;

  return v_customer_id;
end;
$$;
-- ===========================================================================
-- Grant / Revoke
-- Pattern: revoke from public + anon (belt-and-suspenders), grant authenticated.
-- Internal helpers remain revoked from all client roles.
-- ===========================================================================

-- open_pos_session
revoke all on function public.open_pos_session(uuid, numeric, text)
  from public, anon;
grant execute on function public.open_pos_session(uuid, numeric, text)
  to authenticated;
-- close_pos_session
revoke all on function public.close_pos_session(uuid, numeric, text)
  from public, anon;
grant execute on function public.close_pos_session(uuid, numeric, text)
  to authenticated;
-- start_pos_sale
revoke all on function public.start_pos_sale(uuid, text, uuid)
  from public, anon;
grant execute on function public.start_pos_sale(uuid, text, uuid)
  to authenticated;
-- cancel_pos_sale_draft
revoke all on function public.cancel_pos_sale_draft(uuid, text)
  from public, anon;
grant execute on function public.cancel_pos_sale_draft(uuid, text)
  to authenticated;
-- set_pos_tenders
revoke all on function public.set_pos_tenders(uuid, jsonb)
  from public, anon;
grant execute on function public.set_pos_tenders(uuid, jsonb)
  to authenticated;
-- begin_pos_checkout
revoke all on function public.begin_pos_checkout(uuid, text)
  from public, anon;
grant execute on function public.begin_pos_checkout(uuid, text)
  to authenticated;
-- reset_pos_checkout
revoke all on function public.reset_pos_checkout(uuid)
  from public, anon;
grant execute on function public.reset_pos_checkout(uuid)
  to authenticated;
-- prepare_pos_fiscal_handoff
revoke all on function public.prepare_pos_fiscal_handoff(uuid, text, int)
  from public, anon;
grant execute on function public.prepare_pos_fiscal_handoff(uuid, text, int)
  to authenticated;
-- sync_pos_fiscal_status
revoke all on function public.sync_pos_fiscal_status(uuid)
  from public, anon;
grant execute on function public.sync_pos_fiscal_status(uuid)
  to authenticated;
-- ensure_pos_walk_in_and_settings
revoke all on function public.ensure_pos_walk_in_and_settings(uuid, text)
  from public, anon;
grant execute on function public.ensure_pos_walk_in_and_settings(uuid, text)
  to authenticated;
