-- =============================================================================
-- Phase 9: POS finalize + treasury permission boundary + staging fiscal fixture
-- =============================================================================
--
-- INTENTIONAL CLIENT RPCs (callable by role = authenticated):
--
--   public.finalize_pos_sale(p_pos_sale_id uuid, p_idempotency_key text)
--     → Called by POS cashier / manager after fiscal authorization.
--       Idempotent: safe to retry after crash (FINALIZING recovery path).
--       Roles: owner, admin, manager, operator.
--
-- SERVICE_ROLE-ONLY (NOT exported to authenticated users):
--
--   public.pos_test_fixture_mark_fiscal_authorized(
--       p_fiscal_document_id uuid,
--       p_cae text,
--       p_cae_expiration date
--   )
--     → Staging / CI fixture only. Marks a fiscal document AUTHORIZED without
--       going through ARCA, exactly mirroring complete_fiscal_authorization
--       success path. NEVER grant to authenticated or anon.
--
-- NOTE: post_treasury_operation is NOT broadened for generic operator use.
-- The POS finalize gate (treasury.pos_finalize = '1') is COLLECTION-only and
-- requires validated tender linkage to a FINALIZING sale. ADJUSTMENT / PAYMENT /
-- TRANSFER / OPENING_BALANCE require the usual owner/admin/accountant roles.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. Patch public.post_treasury_operation
--    Source: Phase 7 (20260701140000_phase7_post_treasury.sql) reprinted
--    verbatim. ONLY CHANGE: PAYMENT/COLLECTION/TRANSFER/OPENING_BALANCE role
--    gate now includes POS-finalize contextual authorization for COLLECTION
--    when treasury.pos_finalize = '1'. All other logic is identical.
-- ---------------------------------------------------------------------------

create or replace function public.post_treasury_operation(p_operation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_op        public.treasury_operations%rowtype;
  v_period_id uuid;
  v_entry_id  uuid;
  v_existing  uuid;
  v_leg       record;
  v_leg_count int;
  v_inflow    numeric(19,4);
  v_outflow   numeric(19,4);
  v_src_acct  uuid;
  v_dst_acct  uuid;
  v_src_coa   uuid;
  v_dst_coa   uuid;
  v_ap_coa    uuid;
  v_ar_coa    uuid;
  v_eq_coa    uuid;
  v_adj_coa   uuid;
  v_alloc     record;
  v_alloc_sum numeric(19,4);
  v_open      numeric(19,4);
  v_source    public.journal_source_type;
  v_desc      text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select * into v_op
  from public.treasury_operations
  where id = p_operation_id
  for update;
  if not found then raise exception 'treasury operation not found'; end if;

  -- Tenant feature gate from the protected row
  perform public.treasury_assert_feature(v_op.organization_id, array['cash','banks']);

  if v_op.status = 'POSTED' and v_op.journal_entry_id is not null then
    return p_operation_id;
  end if;
  if v_op.status is distinct from 'DRAFT' then
    raise exception 'only DRAFT operations can be posted';
  end if;
  if v_op.currency_code is distinct from 'ARS' then
    raise exception 'unsupported currency for Phase 7: %', v_op.currency_code;
  end if;

  -- -------------------------------------------------------------------------
  -- Permissions by operation type
  -- -------------------------------------------------------------------------
  if v_op.operation_type = 'ADJUSTMENT' then
    if not public.has_org_role(
      v_op.organization_id, array['owner','accountant']::public.member_role[]
    ) then
      raise exception 'only owner/accountant may post adjustments';
    end if;
    if v_op.reason is null or char_length(trim(v_op.reason)) < 3 then
      raise exception 'adjustment reason is required';
    end if;

  elsif v_op.operation_type in ('PAYMENT', 'COLLECTION', 'TRANSFER', 'OPENING_BALANCE') then
    -- -----------------------------------------------------------------------
    -- Phase 9 POS finalize gate — COLLECTION only, context-validated.
    -- treasury.pos_finalize = '1' is set exclusively by finalize_pos_sale.
    -- The two OR-branches below cover the live path and the idempotent-retry
    -- path (tender already linked and op re-posted while sale is FINALIZING
    -- or just-COMPLETED).
    -- ADJUSTMENT / PAYMENT / TRANSFER / OPENING_BALANCE are NOT affected.
    -- -----------------------------------------------------------------------
    if current_setting('treasury.pos_finalize', true) = '1'
       and v_op.operation_type = 'COLLECTION' then
      if not exists (
        select 1
        from public.pos_tenders t
        join public.pos_sales   s on s.id = t.pos_sale_id
        where t.treasury_operation_id = p_operation_id
          and s.status = 'FINALIZING'
          and t.status = 'DRAFT'
      ) and not exists (
        -- idempotent retry: tender already linked to this posted op while
        -- sale is FINALIZING or just reached COMPLETED
        select 1
        from public.pos_tenders t
        join public.pos_sales   s on s.id = t.pos_sale_id
        where t.treasury_operation_id = p_operation_id
          and s.status in ('FINALIZING', 'COMPLETED')
          and t.status in ('DRAFT', 'POSTED')
      ) then
        raise exception 'POS finalize treasury context invalid';
      end if;
    elsif not public.has_org_role(
      v_op.organization_id,
      array['owner','admin','accountant']::public.member_role[]
    ) then
      raise exception 'insufficient role to post treasury operation';
    end if;
  end if;

  -- Idempotent journal reuse
  select id into v_existing
  from public.journal_entries
  where organization_id = v_op.organization_id
    and source_id        = p_operation_id
    and status           = 'POSTED'
    and source_type in ('PAYMENT','COLLECTION','BANK','SYSTEM')
  limit 1;
  if v_existing is not null then
    perform set_config('treasury.engine_write', '1', true);
    update public.treasury_operations
    set status            = 'POSTED',
        journal_entry_id  = v_existing,
        accounting_status = 'POSTED',
        posted_by         = coalesce(posted_by, v_uid),
        posted_at         = coalesce(posted_at, timezone('utc', now()))
    where id = p_operation_id;
    return p_operation_id;
  end if;

  select period_id into v_period_id
  from public.resolve_open_period(v_op.organization_id, v_op.operation_date);
  if v_period_id is null then
    perform set_config('treasury.engine_write', '1', true);
    update public.treasury_operations
    set accounting_status = 'ACCOUNTING_REQUIRES_REVIEW',
        updated_at        = timezone('utc', now())
    where id = p_operation_id;
    return p_operation_id;
  end if;

  select count(*)::int,
         coalesce(sum(case when direction = 'INFLOW'  then amount else 0 end), 0),
         coalesce(sum(case when direction = 'OUTFLOW' then amount else 0 end), 0)
  into v_leg_count, v_inflow, v_outflow
  from public.treasury_operation_legs
  where treasury_operation_id = p_operation_id;

  -- Validate legs by type
  if v_op.operation_type = 'PAYMENT' then
    if v_leg_count <> 1 or v_outflow <> v_op.amount or v_inflow <> 0 then
      raise exception 'PAYMENT requires exactly one OUTFLOW equal to amount';
    end if;
  elsif v_op.operation_type = 'COLLECTION' then
    if v_leg_count <> 1 or v_inflow <> v_op.amount or v_outflow <> 0 then
      raise exception 'COLLECTION requires exactly one INFLOW equal to amount';
    end if;
  elsif v_op.operation_type = 'TRANSFER' then
    if v_leg_count <> 2 or v_inflow <> v_op.amount or v_outflow <> v_op.amount then
      raise exception 'TRANSFER requires equal INFLOW and OUTFLOW';
    end if;
    select treasury_account_id into v_src_acct
    from public.treasury_operation_legs
    where treasury_operation_id = p_operation_id and direction = 'OUTFLOW';
    select treasury_account_id into v_dst_acct
    from public.treasury_operation_legs
    where treasury_operation_id = p_operation_id and direction = 'INFLOW';
    if v_src_acct is not distinct from v_dst_acct then
      raise exception 'TRANSFER source and destination must differ';
    end if;
  elsif v_op.operation_type = 'OPENING_BALANCE' then
    if v_leg_count <> 1 or (v_inflow + v_outflow) <> v_op.amount then
      raise exception 'OPENING_BALANCE requires exactly one leg equal to amount';
    end if;
    if exists (
      select 1
      from public.treasury_operation_legs l
      join public.treasury_operations     o on o.id = l.treasury_operation_id
      where l.treasury_account_id = (
        select treasury_account_id
        from public.treasury_operation_legs
        where treasury_operation_id = p_operation_id
        limit 1
      )
        and o.operation_type = 'OPENING_BALANCE'
        and o.status         = 'POSTED'
        and o.id             <> p_operation_id
    ) then
      raise exception 'treasury account already has a POSTED opening balance';
    end if;
  elsif v_op.operation_type = 'ADJUSTMENT' then
    if v_leg_count <> 1 or (v_inflow + v_outflow) <> v_op.amount then
      raise exception 'ADJUSTMENT requires exactly one leg equal to amount';
    end if;
  end if;

  -- All legs must be active ARS accounts
  for v_leg in
    select l.*, ta.accounting_account_id, ta.is_active,
           ta.currency_code as tac
    from public.treasury_operation_legs l
    join public.treasury_accounts        ta on ta.id = l.treasury_account_id
    where l.treasury_operation_id = p_operation_id
  loop
    if not v_leg.is_active then
      raise exception 'treasury account inactive';
    end if;
    if v_leg.tac is distinct from 'ARS' then
      raise exception 'treasury account currency must be ARS';
    end if;
  end loop;

  -- PAYMENT: validate allocations and lock AP items
  if v_op.operation_type = 'PAYMENT' then
    select coalesce(sum(allocated_amount), 0) into v_alloc_sum
    from public.payment_allocations
    where treasury_operation_id = p_operation_id;
    if v_alloc_sum <> v_op.amount then
      raise exception 'payment allocations must equal payment amount';
    end if;

    perform 1
    from public.accounts_payable_items ap
    where ap.id in (
      select accounts_payable_item_id
      from public.payment_allocations
      where treasury_operation_id = p_operation_id
    )
    order by ap.id
    for update;

    for v_alloc in
      select pa.*,
             ap.open_amount as ap_open,
             ap.direction   as ap_dir,
             ap.supplier_id as ap_supplier
      from public.payment_allocations pa
      join public.accounts_payable_items ap
        on ap.id = pa.accounts_payable_item_id
      where pa.treasury_operation_id = p_operation_id
      order by pa.accounts_payable_item_id
    loop
      if v_alloc.ap_dir is distinct from 'AP_INCREASE' then
        raise exception 'payments may only allocate to AP_INCREASE items';
      end if;
      if v_alloc.ap_supplier is distinct from v_op.counterparty_id then
        raise exception 'AP allocation supplier mismatch';
      end if;
      if v_alloc.allocated_amount > v_alloc.ap_open then
        raise exception 'allocation exceeds AP open amount (concurrency)';
      end if;
    end loop;
  end if;

  -- COLLECTION: validate allocations and lock AR items
  if v_op.operation_type = 'COLLECTION' then
    select coalesce(sum(allocated_amount), 0) into v_alloc_sum
    from public.collection_allocations
    where treasury_operation_id = p_operation_id;
    if v_alloc_sum <> v_op.amount then
      raise exception 'collection allocations must equal collection amount';
    end if;

    perform 1
    from public.accounts_receivable_items ar
    where ar.id in (
      select accounts_receivable_item_id
      from public.collection_allocations
      where treasury_operation_id = p_operation_id
    )
    order by ar.id
    for update;

    for v_alloc in
      select ca.*,
             ar.open_amount as ar_open,
             ar.direction   as ar_dir,
             ar.customer_id as ar_customer
      from public.collection_allocations ca
      join public.accounts_receivable_items ar
        on ar.id = ca.accounts_receivable_item_id
      where ca.treasury_operation_id = p_operation_id
      order by ca.accounts_receivable_item_id
    loop
      if v_alloc.ar_dir is distinct from 'AR_INCREASE' then
        raise exception 'collections may only allocate to AR_INCREASE items';
      end if;
      if v_alloc.ar_customer is distinct from v_op.counterparty_id then
        raise exception 'AR allocation customer mismatch';
      end if;
      if v_alloc.allocated_amount > v_alloc.ar_open then
        raise exception 'allocation exceeds AR open amount (concurrency)';
      end if;
    end loop;
  end if;

  -- Build journal
  v_source := case v_op.operation_type
    when 'PAYMENT'         then 'PAYMENT'   ::public.journal_source_type
    when 'COLLECTION'      then 'COLLECTION'::public.journal_source_type
    when 'TRANSFER'        then 'BANK'      ::public.journal_source_type
    when 'OPENING_BALANCE' then 'SYSTEM'    ::public.journal_source_type
    when 'ADJUSTMENT'      then 'SYSTEM'    ::public.journal_source_type
  end;
  v_desc := left(
    v_op.operation_type::text || ' ' || v_op.internal_number || ' ' || v_op.description,
    500
  );

  insert into public.journal_entries (
    organization_id, entry_date, description,
    status, source_type, source_id, created_by
  ) values (
    v_op.organization_id, v_op.operation_date, v_desc,
    'DRAFT', v_source, p_operation_id, v_uid
  ) returning id into v_entry_id;

  begin
    if v_op.operation_type = 'PAYMENT' then
      v_ap_coa := public.resolve_ap_account(v_op.organization_id);
      select ta.accounting_account_id into v_src_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = 'OUTFLOW';
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number,
        account_id, description, debit, credit, counterparty_id
      ) values
        (v_op.organization_id, v_entry_id, 1,
         v_ap_coa, 'Pago proveedores',  v_op.amount, 0,            v_op.counterparty_id),
        (v_op.organization_id, v_entry_id, 2,
         v_src_coa, 'Egreso tesorería', 0,            v_op.amount, v_op.counterparty_id);

    elsif v_op.operation_type = 'COLLECTION' then
      v_ar_coa := public.resolve_ar_account(v_op.organization_id);
      select ta.accounting_account_id into v_dst_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = 'INFLOW';
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number,
        account_id, description, debit, credit, counterparty_id
      ) values
        (v_op.organization_id, v_entry_id, 1,
         v_dst_coa, 'Ingreso tesorería', v_op.amount, 0,            v_op.counterparty_id),
        (v_op.organization_id, v_entry_id, 2,
         v_ar_coa,  'Cobro clientes',    0,            v_op.amount, v_op.counterparty_id);

    elsif v_op.operation_type = 'TRANSFER' then
      select ta.accounting_account_id into v_src_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = 'OUTFLOW';
      select ta.accounting_account_id into v_dst_coa
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id and l.direction = 'INFLOW';
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number,
        account_id, description, debit, credit
      ) values
        (v_op.organization_id, v_entry_id, 1, v_dst_coa, 'Transferencia destino', v_op.amount, 0),
        (v_op.organization_id, v_entry_id, 2, v_src_coa, 'Transferencia origen',  0, v_op.amount);

    elsif v_op.operation_type = 'OPENING_BALANCE' then
      v_eq_coa := public.resolve_opening_equity_account(v_op.organization_id);
      select ta.accounting_account_id, l.direction into v_src_coa, v_desc
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id;
      if v_desc = 'INFLOW' then
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_src_coa, 'Saldo inicial tesorería',   v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_eq_coa,  'Contrapartida saldo inicial', 0, v_op.amount);
      else
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_eq_coa,  'Contrapartida saldo inicial', v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_src_coa, 'Saldo inicial tesorería',   0, v_op.amount);
      end if;

    elsif v_op.operation_type = 'ADJUSTMENT' then
      v_adj_coa := public.resolve_adjustment_offset_account(v_op.organization_id);
      select ta.accounting_account_id, l.direction into v_src_coa, v_desc
      from public.treasury_operation_legs l
      join public.treasury_accounts ta on ta.id = l.treasury_account_id
      where l.treasury_operation_id = p_operation_id;
      if v_desc = 'INFLOW' then
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_src_coa,  'Ajuste tesorería',             v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_adj_coa,  coalesce(v_op.reason,'Ajuste'), 0, v_op.amount);
      else
        insert into public.journal_entry_lines (
          organization_id, journal_entry_id, line_number, account_id, description, debit, credit
        ) values
          (v_op.organization_id, v_entry_id, 1, v_adj_coa,  coalesce(v_op.reason,'Ajuste'), v_op.amount, 0),
          (v_op.organization_id, v_entry_id, 2, v_src_coa,  'Ajuste tesorería',             0, v_op.amount);
      end if;
    end if;

    perform public.post_journal_entry(v_entry_id);
  exception when others then
    delete from public.journal_entries where id = v_entry_id and status = 'DRAFT';
    raise;
  end;

  perform set_config('treasury.engine_write', '1', true);

  -- Apply AP allocations
  if v_op.operation_type = 'PAYMENT' then
    for v_alloc in
      select *
      from public.payment_allocations
      where treasury_operation_id = p_operation_id
      order by accounts_payable_item_id
    loop
      update public.accounts_payable_items
      set open_amount = open_amount - v_alloc.allocated_amount,
          status      = case
            when open_amount - v_alloc.allocated_amount = 0
              then 'PAID'::public.accounts_payable_status
            else 'PARTIALLY_PAID'::public.accounts_payable_status
          end,
          updated_at  = timezone('utc', now())
      where id = v_alloc.accounts_payable_item_id
        and open_amount >= v_alloc.allocated_amount;
      if not found then
        raise exception 'AP concurrent update failed';
      end if;
    end loop;
  end if;

  -- Apply AR allocations
  if v_op.operation_type = 'COLLECTION' then
    for v_alloc in
      select *
      from public.collection_allocations
      where treasury_operation_id = p_operation_id
      order by accounts_receivable_item_id
    loop
      update public.accounts_receivable_items
      set open_amount = open_amount - v_alloc.allocated_amount,
          status      = case
            when open_amount - v_alloc.allocated_amount = 0
              then 'COLLECTED'::public.accounts_receivable_status
            else 'PARTIALLY_COLLECTED'::public.accounts_receivable_status
          end,
          updated_at  = timezone('utc', now())
      where id = v_alloc.accounts_receivable_item_id
        and open_amount >= v_alloc.allocated_amount;
      if not found then
        raise exception 'AR concurrent update failed';
      end if;
    end loop;
  end if;

  update public.treasury_operations
  set status            = 'POSTED',
      accounting_status = 'POSTED',
      journal_entry_id  = v_entry_id,
      posted_by         = v_uid,
      posted_at         = timezone('utc', now()),
      updated_at        = timezone('utc', now())
  where id = p_operation_id;

  return p_operation_id;
end;
$$;
revoke all on function public.post_treasury_operation(uuid) from public, anon;
grant execute on function public.post_treasury_operation(uuid) to authenticated;
-- ---------------------------------------------------------------------------
-- 2. finalize_pos_sale
--    Orchestrates the FISCAL_AUTHORIZED → COMPLETED lifecycle.
--    Crash-safe: re-entrant on FINALIZING status (recovery path).
--    One DB transaction; no autonomous sub-transactions; no ARCA calls.
-- ---------------------------------------------------------------------------

create or replace function public.finalize_pos_sale(
  p_pos_sale_id     uuid,
  p_idempotency_key text default null  -- reserved; sale lock is the idempotency handle
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid           uuid := auth.uid();
  v_sale          public.pos_sales%rowtype;
  v_session       public.pos_sessions%rowtype;
  v_sales_doc     public.sales_documents%rowtype;
  v_fiscal_doc    public.fiscal_documents%rowtype;
  v_terminal      public.pos_terminals%rowtype;
  v_tender        record;
  v_line          record;
  v_ar_id         uuid;
  v_op_id         uuid;
  v_inv_op_id     uuid;
  v_num           text;
  v_inv_num       text;
  v_inv_line_no   int;
  v_tenders_total numeric(19,4);
  v_fiscal_net    numeric(19,4);
  v_cash_received numeric(19,4);
  v_change_given  numeric(19,4);
begin
  -- 1. Require authenticated caller
  if v_uid is null then raise exception 'authentication required'; end if;

  -- 2. Lock pos_sale row (prevents concurrent finalization of the same sale)
  select * into v_sale
  from public.pos_sales
  where id = p_pos_sale_id
  for update;
  if not found then raise exception 'POS sale not found'; end if;

  -- 3. Idempotent: already COMPLETED
  if v_sale.status = 'COMPLETED' then
    return v_sale.id;
  end if;

  -- 4+5. Status gate: FINALIZING = crash recovery (continue same checks)
  if v_sale.status not in ('FISCAL_AUTHORIZED', 'FINALIZING') then
    raise exception 'POS sale must be FISCAL_AUTHORIZED or FINALIZING (got %)', v_sale.status;
  end if;

  -- 6. Feature + role gate
  perform public.pos_assert_feature(v_sale.organization_id);
  if not public.has_org_role(
    v_sale.organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  ) then
    raise exception 'insufficient role to finalize POS sale';
  end if;

  -- 7. Session must be OPEN
  select * into v_session
  from public.pos_sessions
  where id = v_sale.session_id
    and organization_id = v_sale.organization_id;
  if not found or v_session.status is distinct from 'OPEN' then
    raise exception 'POS session must be OPEN to finalize sale';
  end if;

  -- Load terminal (warehouse_id + branch_id used throughout)
  select * into v_terminal
  from public.pos_terminals
  where id              = v_sale.terminal_id
    and organization_id = v_sale.organization_id;
  if not found then raise exception 'POS terminal not found'; end if;

  -- 8. Sales document: must be commercially frozen and ARS
  select * into v_sales_doc
  from public.sales_documents
  where id              = v_sale.sales_document_id
    and organization_id = v_sale.organization_id;
  if not found then raise exception 'linked sales document not found'; end if;
  if not v_sales_doc.is_commercially_frozen then
    raise exception 'sales document must be commercially frozen before finalization';
  end if;
  if v_sales_doc.currency_code is distinct from 'ARS' then
    raise exception 'POS finalize requires ARS sales document (got %)', v_sales_doc.currency_code;
  end if;

  -- 9. Fiscal document: must be AUTHORIZED, same org, same sales_document_id
  if v_sale.fiscal_document_id is null then
    raise exception 'POS sale has no linked fiscal document';
  end if;
  select * into v_fiscal_doc
  from public.fiscal_documents
  where id              = v_sale.fiscal_document_id
    and organization_id = v_sale.organization_id;
  if not found then raise exception 'fiscal document not found'; end if;
  if v_fiscal_doc.status is distinct from 'AUTHORIZED' then
    raise exception 'fiscal document must be AUTHORIZED (got %)', v_fiscal_doc.status;
  end if;
  if v_fiscal_doc.sales_document_id is distinct from v_sale.sales_document_id then
    raise exception 'fiscal document sales_document_id does not match POS sale';
  end if;

  -- 10. Total validations (exact numeric match)
  --     a) sales.total == fiscal net (taxed + exempt + untaxed); no VAT here
  v_fiscal_net := v_fiscal_doc.net_taxed_amount
                + v_fiscal_doc.net_exempt_amount
                + v_fiscal_doc.net_untaxed_amount;
  if v_sales_doc.total <> v_fiscal_net then
    raise exception 'POS_TOTAL_MISMATCH: sales.total % <> fiscal net %',
      v_sales_doc.total, v_fiscal_net;
  end if;
  --     b) sum(DRAFT|POSTED tender amounts) == fiscal.total_amount (gross, incl. 21% VAT)
  select coalesce(sum(t.amount), 0) into v_tenders_total
  from public.pos_tenders t
  where t.pos_sale_id = p_pos_sale_id
    and t.status in ('DRAFT', 'POSTED');
  if v_tenders_total <> v_fiscal_doc.total_amount then
    raise exception 'POS_TOTAL_MISMATCH: tenders sum % <> fiscal.total_amount %',
      v_tenders_total, v_fiscal_doc.total_amount;
  end if;

  -- 11. Transition to FINALIZING (or re-arm engine_write for crash recovery)
  perform set_config('pos.engine_write', '1', true);
  perform set_config('treasury.pos_finalize', '1', true);
  if v_sale.status = 'FISCAL_AUTHORIZED' then
    update public.pos_sales
    set status     = 'FINALIZING',
        updated_at = timezone('utc', now())
    where id = p_pos_sale_id;
  end if;

  -- 12. Ensure AR item from fiscal document; lock for update
  --     Note: ensure_ar_from_fiscal_document allows operator only when
  --     treasury.pos_finalize=1 and sale is FINALIZING.
  v_ar_id := public.ensure_ar_from_fiscal_document(v_sale.fiscal_document_id);
  perform 1 from public.accounts_receivable_items where id = v_ar_id for update;

  -- 13. Process each DRAFT tender in stable id order
  for v_tender in
    select t.*
    from public.pos_tenders t
    where t.pos_sale_id = p_pos_sale_id
      and t.status = 'DRAFT'
    order by t.id
  loop
    v_op_id := v_tender.treasury_operation_id;

    -- If tender already links a POSTED treasury op, just ensure tender is POSTED and move on
    if v_op_id is not null then
      if exists (
        select 1 from public.treasury_operations
        where id = v_op_id and status = 'POSTED'
      ) then
        perform set_config('pos.engine_write', '1', true);
        update public.pos_tenders
        set status = 'POSTED'
        where id = v_tender.id and status = 'DRAFT';
        continue;
      end if;
      -- Op exists but not yet POSTED (very unlikely partial crash): fall through to post it
    else
      -- No treasury op yet → validate account, feature, then create
      perform public.pos_validate_tender_account(
        v_sale.organization_id,
        v_sale.terminal_id,
        v_tender.method,
        v_tender.treasury_account_id
      );
      -- Feature: CASH → cash feature; BANK_TRANSFER → banks; CARD/QR clearing → cash|banks
      perform public.treasury_assert_feature(v_sale.organization_id, array['cash','banks']);

      -- Check idempotency key before consuming a sequence number (crash-recovery path)
      select id into v_op_id
      from public.treasury_operations
      where organization_id = v_sale.organization_id
        and idempotency_key = 'pos-col:' || v_tender.id::text;

      if v_op_id is null then
        v_num := public.next_treasury_operation_number(v_sale.organization_id, 'COLLECTION');
        insert into public.treasury_operations (
          organization_id,
          branch_id,
          internal_number,
          operation_type,
          status,
          operation_date,
          counterparty_id,
          amount,
          currency_code,
          description,
          idempotency_key,
          created_by
        ) values (
          v_sale.organization_id,
          v_terminal.branch_id,
          v_num,
          'COLLECTION',
          'DRAFT',
          current_date,
          v_sales_doc.counterparty_id,
          v_tender.amount,
          'ARS',
          left('Cobro POS ' || v_sales_doc.internal_number
               || ' ' || v_tender.method::text, 500),
          'pos-col:' || v_tender.id::text,
          v_uid
        )
        returning id into v_op_id;
      end if;
    end if;

    -- Idempotent INFLOW leg (line 1)
    insert into public.treasury_operation_legs (
      organization_id,
      treasury_operation_id,
      treasury_account_id,
      direction,
      amount,
      line_number
    ) values (
      v_sale.organization_id,
      v_op_id,
      v_tender.treasury_account_id,
      'INFLOW',
      v_tender.amount,
      1
    )
    on conflict (treasury_operation_id, line_number) do nothing;

    -- Idempotent collection allocation to the AR item
    perform set_config('treasury.engine_write', '1', true);
    insert into public.collection_allocations (
      organization_id,
      treasury_operation_id,
      accounts_receivable_item_id,
      allocated_amount
    ) values (
      v_sale.organization_id,
      v_op_id,
      v_ar_id,
      v_tender.amount
    )
    on conflict (treasury_operation_id, accounts_receivable_item_id) do nothing;

    -- Arm POS finalize context:
    --   treasury.pos_finalize = '1'  → post_treasury_operation accepts COLLECTION
    --                                   without standard role gate (see role-check patch)
    --   treasury.engine_write = '1'  → AR mutation guard bypass
    --   pos.engine_write      = '1'  → pos_tenders / pos_sales guard bypass
    perform set_config('treasury.pos_finalize', '1', true);
    perform set_config('treasury.engine_write',  '1', true);
    perform set_config('pos.engine_write',        '1', true);

    -- Link tender.treasury_operation_id BEFORE posting so that the context
    -- validation in post_treasury_operation finds the DRAFT tender in the
    -- FINALIZING sale and approves the COLLECTION.
    if v_tender.treasury_operation_id is null then
      update public.pos_tenders
      set treasury_operation_id = v_op_id
      where id = v_tender.id;
    end if;

    -- Post the COLLECTION (builds journal, applies AR allocation; idempotent if already POSTED)
    perform public.post_treasury_operation(v_op_id);

    -- Mark tender POSTED
    perform set_config('pos.engine_write', '1', true);
    update public.pos_tenders
    set status = 'POSTED'
    where id = v_tender.id;

  end loop; -- end tender loop

  -- Optional cash rollup: populate pos_sales.cash_received / change_given from CASH tenders
  select
    coalesce(sum(coalesce(t.cash_received, t.amount)), 0),
    coalesce(sum(coalesce(t.change_given,  0)),         0)
  into v_cash_received, v_change_given
  from public.pos_tenders t
  where t.pos_sale_id = p_pos_sale_id
    and t.method      = 'CASH'
    and t.status      = 'POSTED';

  -- 14. Inventory: ISSUE for STOCK_ITEM lines with ACTIVE reservations
  --     Skipped entirely when inventory_operation_id is already set (crash recovery).
  if v_sale.inventory_operation_id is null then

    if exists (
      select 1
      from public.sales_document_lines sdl
      join public.products pr
        on pr.id              = sdl.product_id
       and pr.organization_id = sdl.organization_id
      join public.inventory_reservations ir
        on ir.sales_document_line_id = sdl.id
       and ir.status in ('ACTIVE', 'CONSUMED')
      where sdl.sales_document_id = v_sale.sales_document_id
        and pr.product_type        = 'STOCK_ITEM'
    ) then

      -- Idempotency: re-use existing op if crash happened between create and link
      select id into v_inv_op_id
      from public.inventory_operations
      where organization_id = v_sale.organization_id
        and idempotency_key = 'pos-issue:' || p_pos_sale_id::text;

      if v_inv_op_id is null then
        v_inv_num := public.next_inventory_operation_number(v_sale.organization_id, 'ISSUE');
        perform set_config('inventory.engine_write', '1', true);
        insert into public.inventory_operations (
          organization_id,
          internal_number,
          operation_type,
          status,
          operation_date,
          warehouse_id,
          source_sales_document_id,
          description,
          idempotency_key,
          created_by
        ) values (
          v_sale.organization_id,
          v_inv_num,
          'ISSUE',
          'DRAFT',
          current_date,
          v_terminal.warehouse_id,
          v_sale.sales_document_id,
          left('POS issue ' || v_inv_num || ' venta ' || v_sales_doc.internal_number, 500),
          'pos-issue:' || p_pos_sale_id::text,
          v_uid
        )
        returning id into v_inv_op_id;
      end if;

      perform set_config('inventory.engine_write', '1', true);

      -- Starting line_number (allows re-entry without duplicate line conflicts)
      v_inv_line_no := coalesce((
        select max(line_number)
        from public.inventory_operation_lines
        where inventory_operation_id = v_inv_op_id
      ), 0);

      -- Insert OUT lines for each ACTIVE reservation (CONSUMED = already issued, skip)
      for v_line in
        select
          sdl.id            as sdl_id,
          sdl.quantity,
          pr.id             as product_id,
          pr.base_unit_code,
          ir.id             as reservation_id,
          ir.warehouse_id
        from public.sales_document_lines sdl
        join public.products pr
          on pr.id              = sdl.product_id
         and pr.organization_id = sdl.organization_id
        join public.inventory_reservations ir
          on ir.sales_document_line_id = sdl.id
         and ir.status = 'ACTIVE'
        where sdl.sales_document_id = v_sale.sales_document_id
          and pr.product_type        = 'STOCK_ITEM'
        order by sdl.line_number, ir.id
      loop
        -- Skip if this reservation already has a line in this operation (idempotent)
        if exists (
          select 1 from public.inventory_operation_lines
          where inventory_operation_id = v_inv_op_id
            and reservation_id         = v_line.reservation_id
        ) then
          continue;
        end if;

        v_inv_line_no := v_inv_line_no + 1;

        insert into public.inventory_operation_lines (
          organization_id,
          inventory_operation_id,
          line_number,
          product_id,
          warehouse_id,
          direction,
          quantity,
          unit_code,
          reservation_id,
          source_sales_line_id
        ) values (
          v_sale.organization_id,
          v_inv_op_id,
          v_inv_line_no,
          v_line.product_id,
          v_line.warehouse_id,      -- reservation's warehouse (where stock is reserved)
          'OUT',
          v_line.quantity,
          v_line.base_unit_code,    -- product base unit (matches inventory ledger)
          v_line.reservation_id,
          v_line.sdl_id
        );
      end loop;

      -- Post the ISSUE operation (idempotent; updates stock state, cost state, ledger)
      perform public.post_inventory_operation(v_inv_op_id);

      -- Link inventory_operation_id to the POS sale
      perform set_config('pos.engine_write', '1', true);
      update public.pos_sales
      set inventory_operation_id = v_inv_op_id,
          updated_at              = timezone('utc', now())
      where id = p_pos_sale_id;

    end if; -- has stock items
  end if;   -- inventory_operation_id is null

  -- 15. Mark COMPLETED
  --     If all tenders were already POSTED and inventory done mid-way, we still
  --     reach here and flip to COMPLETED.
  perform set_config('pos.engine_write', '1', true);
  update public.pos_sales
  set status       = 'COMPLETED',
      completed_at = timezone('utc', now()),
      completed_by = v_uid,
      -- cash_received / change_given: both set or both null (constraint)
      cash_received = case when v_cash_received > 0 then v_cash_received else null end,
      change_given  = case when v_cash_received > 0 then v_change_given  else null end,
      updated_at    = timezone('utc', now())
  where id = p_pos_sale_id;

  -- 16. Return sale id
  return p_pos_sale_id;
end;
$$;
revoke all on function public.finalize_pos_sale(uuid, text) from public, anon;
grant execute on function public.finalize_pos_sale(uuid, text) to authenticated;
comment on function public.finalize_pos_sale(uuid, text) is
  'Phase 9 — POS sale finalization (FISCAL_AUTHORIZED → COMPLETED). '
  'Idempotent; crash-safe via FINALIZING recovery path. '
  'Intentional client RPC: authenticated + roles owner/admin/manager/operator.';
-- ---------------------------------------------------------------------------
-- 3. pos_test_fixture_mark_fiscal_authorized
--    Staging / CI test fixture only. Marks a fiscal document AUTHORIZED and
--    the linked sales order INVOICED, bypassing the ARCA WSFE round-trip.
--    Mirrors the success path of complete_fiscal_authorization (APPROVED).
--    NEVER grant to authenticated or anon.
-- ---------------------------------------------------------------------------

create or replace function public.pos_test_fixture_mark_fiscal_authorized(
  p_fiscal_document_id uuid,
  p_cae                text default 'TESTCAE0001',
  p_cae_expiration     date default (current_date + 30)
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_doc public.fiscal_documents%rowtype;
begin
  -- Only the trusted server adapter (service_role JWT) may call this fixture.
  -- fiscal_assert_service_role checks auth.role() = 'service_role'.
  perform public.fiscal_assert_service_role();

  select * into v_doc
  from public.fiscal_documents
  where id = p_fiscal_document_id
  for update;
  if not found then raise exception 'fiscal document not found'; end if;

  -- Idempotent: already AUTHORIZED
  if v_doc.status = 'AUTHORIZED' then
    return p_fiscal_document_id;
  end if;

  if v_doc.status not in ('DRAFT', 'READY_TO_AUTHORIZE', 'AUTHORIZING') then
    raise exception
      'fixture requires DRAFT / READY_TO_AUTHORIZE / AUTHORIZING (got %)',
      v_doc.status;
  end if;

  perform set_config('fiscal.engine_write', '1', true);
  perform set_config('sales.engine_write', '1', true);

  update public.fiscal_documents
  set status              = 'AUTHORIZED',
      cae                 = p_cae,
      cae_expiration_date = p_cae_expiration,
      authorized_at       = timezone('utc', now()),
      accounting_status   = 'PENDING',
      arca_result         = '{}'::jsonb,
      arca_observations   = '[]'::jsonb,
      updated_at          = timezone('utc', now())
  where id = p_fiscal_document_id;

  if v_doc.sales_document_id is not null and v_doc.relationship_type is null then
    update public.sales_documents
    set status                      = 'INVOICED',
        invoiced_fiscal_document_id = v_doc.id,
        updated_at                  = timezone('utc', now())
    where id              = v_doc.sales_document_id
      and organization_id = v_doc.organization_id
      and status          = 'READY_TO_INVOICE';
  end if;

  return p_fiscal_document_id;
end;
$$;
-- NEVER expose to authenticated users — service_role (CI / staging adapter) only
revoke all on function public.pos_test_fixture_mark_fiscal_authorized(uuid, text, date)
  from public, anon, authenticated;
grant execute on function public.pos_test_fixture_mark_fiscal_authorized(uuid, text, date)
  to service_role;
comment on function public.pos_test_fixture_mark_fiscal_authorized(uuid, text, date) is
  'Phase 9 staging fixture ONLY — marks fiscal document AUTHORIZED without ARCA. '
  'service_role only. Do NOT use in production.';
-- ---------------------------------------------------------------------------
-- Patch ensure_ar_from_fiscal_document: allow operator during POS finalize only
-- (treasury.pos_finalize=1). Does NOT broaden generic AR creation for cashiers.
-- ---------------------------------------------------------------------------
create or replace function public.ensure_ar_from_fiscal_document(p_fiscal_document_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.fiscal_documents%rowtype;
  v_existing uuid;
  v_direction public.accounts_receivable_direction;
  v_id uuid;
  v_dtype_kind text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select * into v_doc from public.fiscal_documents where id = p_fiscal_document_id for update;
  if not found then raise exception 'fiscal document not found'; end if;

  if not public.is_org_member(v_doc.organization_id) then
    raise exception 'not a member of organization';
  end if;

  if current_setting('treasury.pos_finalize', true) = '1' then
    if not public.has_org_role(
      v_doc.organization_id,
      array['owner','admin','accountant','manager','operator']::public.member_role[]
    ) then
      raise exception 'insufficient role to create receivable (POS finalize)';
    end if;
    if not exists (
      select 1 from public.pos_sales s
      where s.fiscal_document_id = p_fiscal_document_id
        and s.status = 'FINALIZING'
    ) then
      raise exception 'POS finalize AR context invalid';
    end if;
  elsif not public.has_org_role(
    v_doc.organization_id,
    array['owner','admin','accountant','manager']::public.member_role[]
  ) then
    raise exception 'insufficient role to create receivable';
  end if;

  select id into v_existing
  from public.accounts_receivable_items
  where fiscal_document_id = p_fiscal_document_id;
  if v_existing is not null then
    return v_existing;
  end if;

  if v_doc.status is distinct from 'AUTHORIZED' then
    raise exception 'only AUTHORIZED fiscal documents may create AR items';
  end if;

  if v_doc.currency_code not in ('ARS', 'PES') then
    raise exception 'Phase 7 MVP AR requires ARS/PES fiscal documents';
  end if;

  if v_doc.total_amount <= 0 then
    raise exception 'fiscal document total must be positive';
  end if;

  if v_doc.relationship_type = 'CREDIT_NOTE' then
    v_direction := 'AR_DECREASE';
  elsif v_doc.relationship_type = 'DEBIT_NOTE' then
    v_direction := 'AR_INCREASE';
  else
    select fdt.operation_kind::text into v_dtype_kind
    from public.fiscal_document_types fdt
    where fdt.id = v_doc.document_type_id;
    if v_dtype_kind = 'CREDIT_NOTE' then
      v_direction := 'AR_DECREASE';
    else
      v_direction := 'AR_INCREASE';
    end if;
  end if;

  perform set_config('treasury.engine_write', '1', true);

  insert into public.accounts_receivable_items (
    organization_id, customer_id, source_type, source_id, fiscal_document_id,
    direction, original_amount, open_amount, currency_code, due_date, status
  ) values (
    v_doc.organization_id, v_doc.counterparty_id, 'FISCAL_DOCUMENT', v_doc.id, v_doc.id,
    v_direction, v_doc.total_amount, v_doc.total_amount, 'ARS', null, 'OPEN'
  )
  on conflict (fiscal_document_id) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.accounts_receivable_items where fiscal_document_id = p_fiscal_document_id;
  end if;

  return v_id;
end;
$$;
revoke all on function public.ensure_ar_from_fiscal_document(uuid) from public, anon;
grant execute on function public.ensure_ar_from_fiscal_document(uuid) to authenticated;
