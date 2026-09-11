-- Phase 11: attention summary + product margin lineage helper

create or replace function public.get_attention_summary(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_now timestamptz := timezone('utc', now());
  v_open int := 0;
  v_ack int := 0;
  v_critical int := 0;
  v_items jsonb := '[]'::jsonb;
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, 'dashboard');

  if not public.has_org_role(
    p_organization_id,
    array['owner', 'admin', 'manager', 'accountant', 'operator']::public.member_role[]
  ) then
    raise exception 'insufficient role for attention summary';
  end if;

  select
    count(*) filter (where status = 'OPEN'),
    count(*) filter (where status = 'ACKNOWLEDGED'),
    count(*) filter (where status in ('OPEN', 'ACKNOWLEDGED') and severity = 'CRITICAL')
  into v_open, v_ack, v_critical
  from public.analytics_alert_events
  where organization_id = p_organization_id
    and status in ('OPEN', 'ACKNOWLEDGED');

  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.sort_sev, x.last_detected_at desc), '[]'::jsonb)
  into v_items
  from (
    select
      e.id,
      e.rule_code,
      e.domain,
      e.severity,
      e.status,
      e.entity_type,
      e.entity_id,
      e.payload_snapshot,
      e.first_detected_at,
      e.last_detected_at,
      case e.severity
        when 'CRITICAL' then 0
        when 'WARNING' then 1
        else 2
      end as sort_sev
    from public.analytics_alert_events e
    where e.organization_id = p_organization_id
      and e.status in ('OPEN', 'ACKNOWLEDGED')
    order by sort_sev, e.last_detected_at desc
    limit 50
  ) x;

  return jsonb_build_object(
    'open_count', coalesce(v_open, 0),
    'acknowledged_count', coalesce(v_ack, 0),
    'critical_count', coalesce(v_critical, 0),
    'items', coalesce(v_items, '[]'::jsonb),
    'calculation_version', 1,
    'data_as_of', v_now,
    'generated_at', v_now,
    'generated_by', v_uid,
    'note', 'Call evaluate_analytics_alerts explicitly to refresh; dashboard GET does not write alerts.'
  );
end;
$$;
revoke all on function public.get_attention_summary(uuid) from public, anon;
grant execute on function public.get_attention_summary(uuid) to authenticated;
comment on function public.get_attention_summary(uuid) is
  'SECURITY DEFINER intentional: read-only Attention Center summary; no alert writes.';
-- Product gross margin only when sales-line → inventory ISSUE lineage is proven.
-- Returns status MARGIN_LINEAGE_REQUIRES_REVIEW when incomplete.
create or replace function public.analytics_product_margin_summary(
  p_organization_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_now timestamptz := timezone('utc', now());
  v_revenue numeric(19, 4) := 0;
  v_cogs numeric(19, 4) := 0;
  v_linked_lines int := 0;
  v_unlinked_lines int := 0;
  v_status text := 'OK';
begin
  v_uid := public.analytics_assert_member(p_organization_id);
  perform public.analytics_assert_feature(p_organization_id, 'fiscal_invoicing');
  perform public.analytics_assert_feature(p_organization_id, 'inventory');

  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'invalid period';
  end if;

  -- Signed net revenue from AUTHORIZED fiscal lines that have source_sales_line_id
  select
    coalesce(sum(
      coalesce(fdl.net_amount, 0) * public.analytics_fiscal_economic_sign(fdt.operation_kind)
    ), 0)::numeric(19, 4),
    count(*) filter (where fdl.source_sales_line_id is not null),
    count(*) filter (where fdl.source_sales_line_id is null)
  into v_revenue, v_linked_lines, v_unlinked_lines
  from public.fiscal_document_lines fdl
  join public.fiscal_documents fd
    on fd.id = fdl.fiscal_document_id
   and fd.organization_id = fdl.organization_id
  join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
  where fdl.organization_id = p_organization_id
    and fd.status = 'AUTHORIZED'::public.fiscal_document_status
    and fd.issue_date >= p_from
    and fd.issue_date <= p_to;

  -- COGS from inventory ISSUE ledger linked through operation lines → sales_document_line
  select coalesce(sum(abs(ile.total_cost)), 0)::numeric(19, 4)
  into v_cogs
  from public.inventory_ledger_entries ile
  join public.inventory_operation_lines iol
    on iol.id = ile.inventory_operation_line_id
   and iol.organization_id = ile.organization_id
  join public.inventory_operations io
    on io.id = iol.inventory_operation_id
   and io.organization_id = iol.organization_id
  where ile.organization_id = p_organization_id
    and io.status = 'POSTED'::public.inventory_operation_status
    and io.operation_type = 'ISSUE'::public.inventory_operation_type
    and iol.sales_document_line_id is not null
    and exists (
      select 1
      from public.fiscal_document_lines fdl2
      join public.fiscal_documents fd2
        on fd2.id = fdl2.fiscal_document_id
       and fd2.organization_id = fdl2.organization_id
      where fdl2.organization_id = p_organization_id
        and fdl2.source_sales_line_id = iol.sales_document_line_id
        and fd2.status = 'AUTHORIZED'::public.fiscal_document_status
        and fd2.issue_date >= p_from
        and fd2.issue_date <= p_to
    );

  if v_unlinked_lines > 0 or v_linked_lines = 0 then
    v_status := 'MARGIN_LINEAGE_REQUIRES_REVIEW';
  end if;

  return jsonb_build_object(
    'status', v_status,
    'signed_net_revenue_linked_lines', v_revenue,
    'inventory_cogs_linked', v_cogs,
    'product_gross_margin', case
      when v_status = 'OK' then (v_revenue - v_cogs)::numeric(19, 4)
      else null
    end,
    'linked_fiscal_lines', v_linked_lines,
    'unlinked_fiscal_lines', v_unlinked_lines,
    'note', 'SERVICE/NON_STOCK never receive inventory COGS. Never use default_purchase_price. Never gross-total − COGS.',
    'calculation_version', 1,
    'period_start', p_from,
    'period_end', p_to,
    'data_as_of', v_now,
    'generated_at', v_now,
    'generated_by', v_uid
  );
end;
$$;
revoke all on function public.analytics_product_margin_summary(uuid, date, date)
  from public, anon;
grant execute on function public.analytics_product_margin_summary(uuid, date, date)
  to authenticated;
comment on function public.analytics_product_margin_summary(uuid, date, date) is
  'SECURITY DEFINER intentional: product margin only with proven sales-line lineage; else MARGIN_LINEAGE_REQUIRES_REVIEW.';
