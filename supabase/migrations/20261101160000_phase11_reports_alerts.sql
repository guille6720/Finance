-- Phase 11: report datasets, alerts evaluation, saved-report RPCs
-- Explicit evaluate only — no background auto-fire in this migration.

-- ---------------------------------------------------------------------------
-- Internal: upsert / resolve alert by dedup_key
-- ---------------------------------------------------------------------------

create or replace function public.analytics_alert_upsert_open(
  p_org_id uuid,
  p_rule_code text,
  p_domain public.analytics_alert_domain,
  p_dedup_key text,
  p_severity public.analytics_alert_severity,
  p_entity_type text,
  p_entity_id uuid,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := timezone('utc', now());
begin
  insert into public.analytics_alert_events (
    organization_id, rule_code, domain, entity_type, entity_id,
    dedup_key, severity, status, first_detected_at, last_detected_at, payload_snapshot
  ) values (
    p_org_id, p_rule_code, p_domain, p_entity_type, p_entity_id,
    p_dedup_key, p_severity, 'OPEN', v_now, v_now, coalesce(p_payload, '{}'::jsonb)
  )
  on conflict (organization_id, dedup_key) do update set
    last_detected_at = v_now,
    severity = excluded.severity,
    payload_snapshot = excluded.payload_snapshot,
    domain = excluded.domain,
    entity_type = excluded.entity_type,
    entity_id = excluded.entity_id,
    status = case
      when public.analytics_alert_events.status = 'RESOLVED'::public.analytics_alert_status
        then 'OPEN'::public.analytics_alert_status
      else public.analytics_alert_events.status
    end,
    resolved_at = case
      when public.analytics_alert_events.status = 'RESOLVED'::public.analytics_alert_status
        then null
      else public.analytics_alert_events.resolved_at
    end,
    updated_at = v_now;
end;
$$;
revoke all on function public.analytics_alert_upsert_open(
  uuid, text, public.analytics_alert_domain, text, public.analytics_alert_severity, text, uuid, jsonb
) from public, anon, authenticated;
create or replace function public.analytics_alert_resolve_missing(
  p_org_id uuid,
  p_rule_code text,
  p_active_dedup_keys text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.analytics_alert_events e
  set
    status = 'RESOLVED'::public.analytics_alert_status,
    resolved_at = timezone('utc', now()),
    updated_at = timezone('utc', now())
  where e.organization_id = p_org_id
    and e.rule_code = p_rule_code
    and e.status in (
      'OPEN'::public.analytics_alert_status,
      'ACKNOWLEDGED'::public.analytics_alert_status
    )
    and (
      p_active_dedup_keys is null
      or cardinality(p_active_dedup_keys) = 0
      or e.dedup_key <> all (p_active_dedup_keys)
    );
end;
$$;
revoke all on function public.analytics_alert_resolve_missing(uuid, text, text[])
  from public, anon, authenticated;
create or replace function public.analytics_alert_rule_enabled(
  p_org_id uuid,
  p_rule_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select s.enabled
      from public.analytics_alert_settings s
      where s.organization_id = p_org_id
        and s.rule_code = p_rule_code
    ),
    true
  );
$$;
revoke all on function public.analytics_alert_rule_enabled(uuid, text)
  from public, anon, authenticated;
create or replace function public.analytics_alert_threshold(
  p_org_id uuid,
  p_rule_code text
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select s.threshold_json
      from public.analytics_alert_settings s
      where s.organization_id = p_org_id
        and s.rule_code = p_rule_code
    ),
    '{}'::jsonb
  );
$$;
revoke all on function public.analytics_alert_threshold(uuid, text)
  from public, anon, authenticated;
-- ---------------------------------------------------------------------------
-- evaluate_analytics_alerts (explicit only)
-- ---------------------------------------------------------------------------

create or replace function public.evaluate_analytics_alerts(p_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_as_of date;
  v_keys text[] := '{}';
  v_key text;
  v_opened int := 0;
  v_thr jsonb;
  v_days int;
  v_now timestamptz := timezone('utc', now());
  r record;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_any_feature(p_organization_id, array['dashboard','reports']);

  if not public.has_org_role(
    p_organization_id,
    array['owner','admin','accountant','manager']::public.member_role[]
  ) then
    raise exception 'insufficient role to evaluate alerts';
  end if;

  v_as_of := (timezone(public.analytics_org_timezone(p_organization_id), timezone('utc', now())))::date;

  -- AR_OVERDUE
  if public.analytics_alert_rule_enabled(p_organization_id, 'AR_OVERDUE') then
    v_keys := '{}';
    for r in
      select ari.id, ari.open_amount, ari.due_date, ari.customer_id
      from public.accounts_receivable_items ari
      where ari.organization_id = p_organization_id
        and ari.status in ('OPEN','PARTIALLY_COLLECTED')
        and ari.open_amount > 0
        and ari.due_date is not null
        and ari.due_date < v_as_of
    loop
      v_key := 'AR_OVERDUE:' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'AR_OVERDUE', 'FINANCE', v_key, 'WARNING',
        'accounts_receivable_items', r.id,
        jsonb_build_object('open_amount', r.open_amount, 'due_date', r.due_date, 'as_of', v_as_of)
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'AR_OVERDUE', v_keys);
  end if;

  -- AP_OVERDUE
  if public.analytics_alert_rule_enabled(p_organization_id, 'AP_OVERDUE') then
    v_keys := '{}';
    for r in
      select api.id, api.open_amount, api.due_date
      from public.accounts_payable_items api
      where api.organization_id = p_organization_id
        and api.status in ('OPEN','PARTIALLY_PAID')
        and api.open_amount > 0
        and api.due_date is not null
        and api.due_date < v_as_of
    loop
      v_key := 'AP_OVERDUE:' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'AP_OVERDUE', 'FINANCE', v_key, 'WARNING',
        'accounts_payable_items', r.id,
        jsonb_build_object('open_amount', r.open_amount, 'due_date', r.due_date, 'as_of', v_as_of)
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'AP_OVERDUE', v_keys);
  end if;

  -- TAX_SOURCE_CHANGED
  if public.analytics_alert_rule_enabled(p_organization_id, 'TAX_SOURCE_CHANGED')
     and public.analytics_feature_enabled(p_organization_id, 'taxes')
  then
    v_keys := '{}';
    for r in
      select tp.id
      from public.tax_periods tp
      where tp.organization_id = p_organization_id
        and tp.source_changed
        and tp.status in ('OPEN','IN_REVIEW','REVIEWED','REOPENED')
    loop
      v_key := 'TAX_SOURCE_CHANGED:' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'TAX_SOURCE_CHANGED', 'TAX', v_key, 'WARNING',
        'tax_periods', r.id,
        jsonb_build_object('message', 'Fuente tributaria modificada — requiere revisión')
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'TAX_SOURCE_CHANGED', v_keys);
  end if;

  -- FISCAL_RECON_REQUIRED
  if public.analytics_alert_rule_enabled(p_organization_id, 'FISCAL_RECON_REQUIRED')
     and public.analytics_feature_enabled(p_organization_id, 'fiscal_invoicing')
  then
    v_keys := '{}';
    for r in
      select fd.id
      from public.fiscal_documents fd
      where fd.organization_id = p_organization_id
        and fd.status = 'RECONCILIATION_REQUIRED'::public.fiscal_document_status
    loop
      v_key := 'FISCAL_RECON_REQUIRED:' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'FISCAL_RECON_REQUIRED', 'FISCAL', v_key, 'CRITICAL',
        'fiscal_documents', r.id,
        jsonb_build_object('message', 'Documento fiscal requiere conciliación')
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'FISCAL_RECON_REQUIRED', v_keys);
  end if;

  -- POS_RECON_REQUIRED
  if public.analytics_alert_rule_enabled(p_organization_id, 'POS_RECON_REQUIRED')
     and public.analytics_feature_enabled(p_organization_id, 'pos')
  then
    v_keys := '{}';
    for r in
      select ps.id
      from public.pos_sales ps
      where ps.organization_id = p_organization_id
        and ps.status = 'RECONCILIATION_REQUIRED'::public.pos_sale_status
    loop
      v_key := 'POS_RECON_REQUIRED:' || r.id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'POS_RECON_REQUIRED', 'POS', v_key, 'CRITICAL',
        'pos_sales', r.id,
        jsonb_build_object('message', 'Venta POS requiere conciliación')
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'POS_RECON_REQUIRED', v_keys);
  end if;

  -- STOCK_BELOW_THRESHOLD
  if public.analytics_alert_rule_enabled(p_organization_id, 'STOCK_BELOW_THRESHOLD')
     and public.analytics_feature_enabled(p_organization_id, 'inventory')
  then
    v_keys := '{}';
    for r in
      select
        t.id as threshold_id,
        t.product_id,
        t.warehouse_id,
        t.minimum_available_quantity,
        coalesce(sum(ss.on_hand_quantity - ss.reserved_quantity), 0)::numeric(18, 4) as available_qty
      from public.analytics_inventory_thresholds t
      left join public.inventory_stock_state ss
        on ss.organization_id = t.organization_id
       and ss.product_id = t.product_id
       and (t.warehouse_id is null or ss.warehouse_id = t.warehouse_id)
      where t.organization_id = p_organization_id
        and t.active
      group by t.id, t.product_id, t.warehouse_id, t.minimum_available_quantity
      having coalesce(sum(ss.on_hand_quantity - ss.reserved_quantity), 0) < t.minimum_available_quantity
    loop
      v_key := 'STOCK_BELOW_THRESHOLD:' || r.threshold_id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'STOCK_BELOW_THRESHOLD', 'INVENTORY', v_key, 'WARNING',
        'analytics_inventory_thresholds', r.threshold_id,
        jsonb_build_object(
          'product_id', r.product_id,
          'warehouse_id', r.warehouse_id,
          'available', r.available_qty,
          'minimum', r.minimum_available_quantity
        )
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'STOCK_BELOW_THRESHOLD', v_keys);
  end if;

  -- CLEARING_AGING (only if threshold set)
  v_thr := public.analytics_alert_threshold(p_organization_id, 'CLEARING_AGING');
  if public.analytics_alert_rule_enabled(p_organization_id, 'CLEARING_AGING')
     and (v_thr ? 'max_age_days')
  then
    v_days := greatest(1, coalesce((v_thr->>'max_age_days')::int, 7));
    v_keys := '{}';
    -- Heuristic: CLEARING balance > 0 and oldest POSTED inflow leg older than threshold
    for r in
      select ta.id as account_id,
             public.treasury_account_balance(ta.id) as bal,
             min(o.operation_date) as oldest_date
      from public.treasury_accounts ta
      join public.treasury_operation_legs l
        on l.treasury_account_id = ta.id
       and l.organization_id = ta.organization_id
      join public.treasury_operations o
        on o.id = l.treasury_operation_id
       and o.organization_id = l.organization_id
      where ta.organization_id = p_organization_id
        and ta.account_type = 'CLEARING'::public.treasury_account_type
        and ta.is_active
        and o.status = 'POSTED'::public.treasury_operation_status
        and l.direction = 'INFLOW'::public.treasury_leg_direction
      group by ta.id
      having public.treasury_account_balance(ta.id) > 0
         and min(o.operation_date) <= (v_as_of - v_days)
    loop
      v_key := 'CLEARING_AGING:' || r.account_id::text;
      v_keys := array_append(v_keys, v_key);
      perform public.analytics_alert_upsert_open(
        p_organization_id, 'CLEARING_AGING', 'TREASURY', v_key, 'INFO',
        'treasury_accounts', r.account_id,
        jsonb_build_object(
          'balance', r.bal,
          'oldest_inflow_date', r.oldest_date,
          'max_age_days', v_days
        )
      );
      v_opened := v_opened + 1;
    end loop;
    perform public.analytics_alert_resolve_missing(p_organization_id, 'CLEARING_AGING', v_keys);
  end if;

  return jsonb_build_object(
    'organization_id', p_organization_id,
    'evaluated_at', v_now,
    'as_of', v_as_of,
    'touched_rules', v_opened,
    'evaluated_by', v_uid
  );
end;
$$;
revoke all on function public.evaluate_analytics_alerts(uuid) from public, anon;
grant execute on function public.evaluate_analytics_alerts(uuid) to authenticated;
comment on function public.evaluate_analytics_alerts(uuid) is
  'SECURITY DEFINER intentional: explicit alert rebuild/dedup; upserts by dedup_key; resolves when condition gone.';
-- ---------------------------------------------------------------------------
-- ack_analytics_alert
-- ---------------------------------------------------------------------------

create or replace function public.ack_analytics_alert(p_alert_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_row public.analytics_alert_events%rowtype;
begin
  select * into v_row from public.analytics_alert_events where id = p_alert_id;
  if not found then
    raise exception 'alert not found';
  end if;

  v_uid := public.analytics_assert_member(v_row.organization_id);
  perform public.analytics_assert_any_feature(v_row.organization_id, array['dashboard','reports']);

  if v_row.status = 'RESOLVED'::public.analytics_alert_status then
    raise exception 'cannot acknowledge a resolved alert';
  end if;

  update public.analytics_alert_events
  set
    status = 'ACKNOWLEDGED'::public.analytics_alert_status,
    acknowledged_at = timezone('utc', now()),
    acknowledged_by = v_uid,
    updated_at = timezone('utc', now())
  where id = p_alert_id;

  return jsonb_build_object('id', p_alert_id, 'status', 'ACKNOWLEDGED', 'acknowledged_by', v_uid);
end;
$$;
revoke all on function public.ack_analytics_alert(uuid) from public, anon;
grant execute on function public.ack_analytics_alert(uuid) to authenticated;
-- ---------------------------------------------------------------------------
-- Saved reports RPCs
-- ---------------------------------------------------------------------------

create or replace function public.upsert_saved_report(
  p_organization_id uuid,
  p_report_code text,
  p_name text,
  p_filters_json jsonb default '{}'::jsonb,
  p_columns_json jsonb default '[]'::jsonb,
  p_sort_json jsonb default '[]'::jsonb,
  p_visibility text default 'PRIVATE',
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_id uuid;
  v_vis public.saved_report_visibility;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, 'reports');

  v_vis := upper(coalesce(p_visibility, 'PRIVATE'))::public.saved_report_visibility;

  if p_id is not null then
    update public.saved_reports
    set
      report_code = upper(trim(p_report_code)),
      name = trim(p_name),
      filters_json = coalesce(p_filters_json, '{}'::jsonb),
      columns_json = coalesce(p_columns_json, '[]'::jsonb),
      sort_json = coalesce(p_sort_json, '[]'::jsonb),
      visibility = v_vis,
      updated_at = timezone('utc', now())
    where id = p_id
      and organization_id = p_organization_id
      and owner_user_id = v_uid
    returning id into v_id;
    if v_id is null then
      raise exception 'saved report not found or not owned';
    end if;
  else
    insert into public.saved_reports (
      organization_id, owner_user_id, report_code, name,
      filters_json, columns_json, sort_json, visibility
    ) values (
      p_organization_id, v_uid, upper(trim(p_report_code)), trim(p_name),
      coalesce(p_filters_json, '{}'::jsonb),
      coalesce(p_columns_json, '[]'::jsonb),
      coalesce(p_sort_json, '[]'::jsonb),
      v_vis
    )
    returning id into v_id;
  end if;

  return jsonb_build_object('id', v_id);
end;
$$;
revoke all on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
  from public, anon;
grant execute on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
  to authenticated;
create or replace function public.list_saved_reports(
  p_organization_id uuid,
  p_report_code text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_rows jsonb;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, 'reports');

  select coalesce(jsonb_agg(to_jsonb(s) order by s.updated_at desc), '[]'::jsonb)
  into v_rows
  from public.saved_reports s
  where s.organization_id = p_organization_id
    and s.active
    and (p_report_code is null or s.report_code = upper(trim(p_report_code)))
    and (
      s.visibility = 'ORGANIZATION'::public.saved_report_visibility
      or s.owner_user_id = v_uid
    );

  return jsonb_build_object('rows', v_rows);
end;
$$;
revoke all on function public.list_saved_reports(uuid, text) from public, anon;
grant execute on function public.list_saved_reports(uuid, text) to authenticated;
create or replace function public.delete_saved_report(p_saved_report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_row public.saved_reports%rowtype;
begin
  select * into v_row from public.saved_reports where id = p_saved_report_id;
  if not found then raise exception 'saved report not found'; end if;
  v_uid := public.analytics_assert_member(v_row.organization_id);
  if v_row.owner_user_id is distinct from v_uid then
    raise exception 'only owner can delete saved report';
  end if;

  update public.saved_reports
  set active = false, updated_at = timezone('utc', now())
  where id = p_saved_report_id;

  return jsonb_build_object('id', p_saved_report_id, 'active', false);
end;
$$;
revoke all on function public.delete_saved_report(uuid) from public, anon;
grant execute on function public.delete_saved_report(uuid) to authenticated;
create or replace function public.upsert_analytics_inventory_threshold(
  p_organization_id uuid,
  p_product_id uuid,
  p_minimum_available_quantity numeric,
  p_warehouse_id uuid default null,
  p_warning_quantity numeric default null,
  p_active boolean default true,
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_id uuid;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, 'inventory');

  if not public.has_org_role(
    p_organization_id,
    array['owner','admin','manager','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role for inventory thresholds';
  end if;

  if p_id is not null then
    update public.analytics_inventory_thresholds
    set
      product_id = p_product_id,
      warehouse_id = p_warehouse_id,
      minimum_available_quantity = p_minimum_available_quantity,
      warning_quantity = p_warning_quantity,
      active = coalesce(p_active, true),
      updated_at = timezone('utc', now())
    where id = p_id and organization_id = p_organization_id
    returning id into v_id;
    if v_id is null then raise exception 'threshold not found'; end if;
    return jsonb_build_object('id', v_id);
  end if;

  select t.id into v_id
  from public.analytics_inventory_thresholds t
  where t.organization_id = p_organization_id
    and t.product_id = p_product_id
    and t.warehouse_id is not distinct from p_warehouse_id
  limit 1;

  if v_id is not null then
    update public.analytics_inventory_thresholds
    set
      minimum_available_quantity = p_minimum_available_quantity,
      warning_quantity = p_warning_quantity,
      active = coalesce(p_active, true),
      updated_at = timezone('utc', now())
    where id = v_id;
  else
    insert into public.analytics_inventory_thresholds (
      organization_id, product_id, warehouse_id,
      minimum_available_quantity, warning_quantity, active
    ) values (
      p_organization_id, p_product_id, p_warehouse_id,
      p_minimum_available_quantity, p_warning_quantity, coalesce(p_active, true)
    )
    returning id into v_id;
  end if;

  return jsonb_build_object('id', v_id);
end;
$$;
revoke all on function public.upsert_analytics_inventory_threshold(
  uuid, uuid, numeric, uuid, numeric, boolean, uuid
) from public, anon;
grant execute on function public.upsert_analytics_inventory_threshold(
  uuid, uuid, numeric, uuid, numeric, boolean, uuid
) to authenticated;
-- ---------------------------------------------------------------------------
-- get_report_dataset
-- ---------------------------------------------------------------------------

create or replace function public.get_report_dataset(
  p_organization_id uuid,
  p_report_code text,
  p_filters jsonb default '{}'::jsonb,
  p_limit int default 100,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_code text := upper(trim(p_report_code));
  v_limit int := greatest(1, least(coalesce(p_limit, 100), 500));
  v_offset int := greatest(0, coalesce(p_offset, 0));
  v_from date;
  v_to date;
  v_as_of date;
  v_now timestamptz := timezone('utc', now());
  v_rows jsonb := '[]'::jsonb;
  v_totals jsonb := '{}'::jsonb;
  v_env text;
  v_pnl jsonb;
  v_bs jsonb;
  v_aging jsonb;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, 'reports');

  v_from := nullif(p_filters->>'from', '')::date;
  v_to := nullif(p_filters->>'to', '')::date;
  v_as_of := coalesce(nullif(p_filters->>'as_of', '')::date, v_to, v_from,
    (timezone(public.analytics_org_timezone(p_organization_id), timezone('utc', now())))::date);
  v_env := nullif(p_filters->>'fiscal_environment', '');

  if v_from is null or v_to is null then
    select pb.period_start, pb.period_end into v_from, v_to
    from public.analytics_period_bounds(
      p_organization_id,
      coalesce(nullif(p_filters->>'period_preset', ''), 'THIS_MONTH'),
      v_from, v_to
    ) pb;
  end if;

  case v_code
    when 'AR_AGING' then
      v_aging := public.get_ar_aging(p_organization_id, v_as_of);
      v_rows := coalesce(v_aging->'rows', '[]'::jsonb);
      v_totals := coalesce(v_aging->'totals', '{}'::jsonb);

    when 'AP_AGING' then
      v_aging := public.get_ap_aging(p_organization_id, v_as_of);
      v_rows := coalesce(v_aging->'rows', '[]'::jsonb);
      v_totals := coalesce(v_aging->'totals', '{}'::jsonb);

    when 'SALES_SUMMARY' then
      perform public.analytics_assert_feature(p_organization_id, 'fiscal_invoicing');
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), '[]'::jsonb),
             jsonb_build_object(
               'gross', coalesce(sum(x.gross), 0),
               'net', coalesce(sum(x.net), 0),
               'count', count(*)::int
             )
      into v_rows, v_totals
      from (
        select
          fd.id,
          fd.issue_date,
          fd.document_number,
          fd.status::text,
          fd.fiscal_environment::text,
          fdt.operation_kind::text,
          (fd.total_amount * public.analytics_fiscal_economic_sign(fdt.operation_kind))::numeric(19, 4) as gross,
          (
            (fd.net_taxed_amount + fd.net_exempt_amount + fd.net_untaxed_amount)
            * public.analytics_fiscal_economic_sign(fdt.operation_kind)
          )::numeric(19, 4) as net
        from public.fiscal_documents fd
        join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
        where fd.organization_id = p_organization_id
          and fd.status = 'AUTHORIZED'::public.fiscal_document_status
          and fd.issue_date >= v_from and fd.issue_date <= v_to
          and (v_env is null or fd.fiscal_environment::text = v_env)
        order by fd.issue_date desc, fd.document_number desc nulls last
        limit v_limit offset v_offset
      ) x;

    when 'CASH_BANK_POSITION' then
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), '[]'::jsonb),
             jsonb_build_object(
               'cash', public.analytics_treasury_type_balance(p_organization_id, 'CASH'),
               'bank', public.analytics_treasury_type_balance(p_organization_id, 'BANK'),
               'clearing', public.analytics_treasury_type_balance(p_organization_id, 'CLEARING')
             )
      into v_rows, v_totals
      from (
        select
          ta.id,
          ta.code,
          ta.name,
          ta.account_type::text,
          public.treasury_account_balance(ta.id)::numeric(19, 4) as balance
        from public.treasury_accounts ta
        where ta.organization_id = p_organization_id
          and ta.is_active
        order by ta.account_type, ta.code
        limit v_limit offset v_offset
      ) x;

    when 'TRIAL_BALANCE_MGMT' then
      perform public.analytics_assert_feature(p_organization_id, 'accounting');
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), '[]'::jsonb),
             jsonb_build_object(
               'debit_total', coalesce(sum(x.debit), 0),
               'credit_total', coalesce(sum(x.credit), 0)
             )
      into v_rows, v_totals
      from (
        select
          a.code,
          a.name,
          a.account_type::text,
          coalesce(sum(l.debit), 0)::numeric(19, 4) as debit,
          coalesce(sum(l.credit), 0)::numeric(19, 4) as credit,
          public.analytics_signed_balance(
            coalesce(sum(l.debit), 0),
            coalesce(sum(l.credit), 0),
            a.normal_balance
          ) as balance
        from public.accounts a
        left join public.analytics_journal_economic_lines(p_organization_id) l
          on l.account_id = a.id
         and l.entry_date >= v_from
         and l.entry_date <= v_to
        where a.organization_id = p_organization_id
          and a.is_active
          and a.account_type is distinct from 'MEMORANDUM'::public.account_type
        group by a.id, a.code, a.name, a.account_type, a.normal_balance
        having coalesce(sum(l.debit), 0) <> 0 or coalesce(sum(l.credit), 0) <> 0
        order by a.code
        limit v_limit offset v_offset
      ) x;

    when 'MANAGEMENT_PNL' then
      v_pnl := public.analytics_management_pnl(p_organization_id, v_from, v_to);
      v_rows := jsonb_build_array(v_pnl);
      v_totals := jsonb_build_object(
        'management_result', v_pnl->'management_result',
        'gross_result', v_pnl->'gross_result'
      );

    when 'MANAGEMENT_BALANCE_SHEET' then
      v_bs := public.analytics_management_balance_sheet(p_organization_id, v_as_of);
      v_rows := jsonb_build_array(v_bs);
      v_totals := jsonb_build_object(
        'assets', v_bs->'assets',
        'liabilities', v_bs->'liabilities',
        'equity', v_bs->'equity',
        'resultado_del_periodo', v_bs->'resultado_del_periodo',
        'difference', v_bs->'difference',
        'status', v_bs->'status'
      );

    when 'TAX_SUMMARY' then
      perform public.analytics_assert_feature(p_organization_id, 'taxes');
      if not public.has_org_role(
        p_organization_id, array['owner','admin','accountant']::public.member_role[]
      ) then
        raise exception 'insufficient role for tax report';
      end if;
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), '[]'::jsonb)
      into v_rows
      from (
        select
          tp.id as tax_period_id,
          tp.tax_code::text,
          tp.period_year,
          tp.period_month,
          tp.status::text,
          tp.source_changed,
          td.id as determination_id,
          td.totals_snapshot,
          (td.totals_snapshot->>'saldo_estimado') as saldo_estimado
        from public.tax_periods tp
        left join public.tax_determinations td
          on td.tax_period_id = tp.id and td.is_current
        where tp.organization_id = p_organization_id
        order by tp.period_year desc, tp.period_month desc nulls last
        limit v_limit offset v_offset
      ) x;
      v_totals := jsonb_build_object('disclaimer', 'Saldo estimado — no es DDJJ oficial');

    when 'INVENTORY_VALUATION' then
      perform public.analytics_assert_feature(p_organization_id, 'inventory');
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), '[]'::jsonb),
             jsonb_build_object('inventory_value', coalesce(sum(x.inventory_value), 0))
      into v_rows, v_totals
      from (
        select
          ics.product_id,
          p.sku,
          p.name,
          ics.quantity_on_hand_total,
          ics.average_unit_cost,
          ics.inventory_value
        from public.inventory_cost_state ics
        join public.products p
          on p.id = ics.product_id and p.organization_id = ics.organization_id
        where ics.organization_id = p_organization_id
        order by ics.inventory_value desc
        limit v_limit offset v_offset
      ) x;

    when 'POS_SUMMARY' then
      perform public.analytics_assert_feature(p_organization_id, 'pos');
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), '[]'::jsonb),
             jsonb_build_object('completed_count', count(*)::int)
      into v_rows, v_totals
      from (
        select
          ps.id,
          ps.status::text,
          ps.completed_at,
          ps.sales_document_id,
          ps.fiscal_document_id
        from public.pos_sales ps
        where ps.organization_id = p_organization_id
          and ps.status = 'COMPLETED'::public.pos_sale_status
          and (
            (ps.completed_at is not null
              and (timezone(public.analytics_org_timezone(p_organization_id), ps.completed_at))::date
                    between v_from and v_to)
            or (ps.completed_at is null
              and ps.created_at::date between v_from and v_to)
          )
        order by ps.completed_at desc nulls last
        limit v_limit offset v_offset
      ) x;

    when 'TREASURY_MOVEMENTS' then
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), '[]'::jsonb),
             jsonb_build_object(
               'amount_sum', coalesce(sum(x.amount), 0),
               'count', count(*)::int
             )
      into v_rows, v_totals
      from (
        select
          o.id,
          o.internal_number,
          o.operation_type::text,
          o.status::text,
          o.operation_date,
          o.amount,
          o.description
        from public.treasury_operations o
        where o.organization_id = p_organization_id
          and o.status = 'POSTED'::public.treasury_operation_status
          and o.operation_date >= v_from and o.operation_date <= v_to
        order by o.operation_date desc, o.internal_number desc
        limit v_limit offset v_offset
      ) x;

    when 'PURCHASES_SUMMARY' then
      perform public.analytics_assert_feature(p_organization_id, 'purchases');
      select coalesce(jsonb_agg(row_to_json(x)::jsonb), '[]'::jsonb),
             jsonb_build_object(
               'total', coalesce(sum(x.signed_total), 0),
               'count', count(*)::int
             )
      into v_rows, v_totals
      from (
        select
          pd.id,
          pd.document_type::text,
          pd.document_number,
          pd.issue_date,
          pd.accounting_date,
          pd.status::text,
          pd.total_amount,
          case
            when pd.document_type = 'SUPPLIER_CREDIT_NOTE'::public.purchase_document_type
              then -pd.total_amount
            else pd.total_amount
          end::numeric(19, 4) as signed_total
        from public.purchase_documents pd
        where pd.organization_id = p_organization_id
          and pd.status = 'POSTED'::public.purchase_document_status
          and pd.accounting_date >= v_from and pd.accounting_date <= v_to
        order by pd.accounting_date desc
        limit v_limit offset v_offset
      ) x;

    else
      raise exception 'unsupported report_code: %', p_report_code;
  end case;

  return jsonb_build_object(
    'rows', coalesce(v_rows, '[]'::jsonb),
    'totals', coalesce(v_totals, '{}'::jsonb),
    'meta', jsonb_build_object(
      'calculation_version', 1,
      'data_as_of', v_now,
      'generated_at', v_now,
      'report_code', v_code,
      'period_start', v_from,
      'period_end', v_to,
      'limit', v_limit,
      'offset', v_offset,
      'generated_by', v_uid
    )
  );
end;
$$;
revoke all on function public.get_report_dataset(uuid, text, jsonb, int, int) from public, anon;
grant execute on function public.get_report_dataset(uuid, text, jsonb, int, int) to authenticated;
comment on function public.get_report_dataset(uuid, text, jsonb, int, int) is
  'SECURITY DEFINER intentional: allowlisted report_code datasets only; requires reports feature.';
