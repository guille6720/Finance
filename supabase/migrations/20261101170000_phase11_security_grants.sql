-- Phase 11: security grants documentation + intentional SECURITY DEFINER list
-- Re-revoke internal helpers; grant client RPCs to authenticated only.
-- STAGING ONLY.

-- ---------------------------------------------------------------------------
-- Document: intentional SECURITY DEFINER surface (client-callable)
-- ---------------------------------------------------------------------------
-- get_dashboard_summary(uuid, text, date, date, text)
-- get_financial_dashboard(uuid, text, date, date, text)
-- get_ar_aging(uuid, date)
-- get_ap_aging(uuid, date)
-- analytics_management_pnl(uuid, date, date)
-- analytics_management_balance_sheet(uuid, date)
-- get_report_dataset(uuid, text, jsonb, int, int)
-- evaluate_analytics_alerts(uuid)
-- ack_analytics_alert(uuid)
-- upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
-- list_saved_reports(uuid, text)
-- delete_saved_report(uuid)
-- upsert_analytics_inventory_threshold(uuid, uuid, numeric, uuid, numeric, boolean, uuid)
--
-- Internal (REVOKED from public/anon/authenticated):
-- analytics_assert_service_role, analytics_assert_member, analytics_assert_feature,
-- analytics_assert_any_feature, analytics_feature_enabled, analytics_org_timezone,
-- analytics_period_bounds, analytics_fiscal_economic_sign, analytics_is_economic_journal_status,
-- analytics_journal_economic_lines, analytics_account_is_cogs,
-- analytics_sales_fiscal_net, analytics_sales_fiscal_gross, analytics_signed_balance,
-- analytics_prev_period_bounds, analytics_metric_payload, analytics_ar_open_total,
-- analytics_ap_open_total, analytics_treasury_type_balance, analytics_aging_bucket,
-- analytics_alert_upsert_open, analytics_alert_resolve_missing,
-- analytics_alert_rule_enabled, analytics_alert_threshold

-- ---------------------------------------------------------------------------
-- Re-revoke internals
-- ---------------------------------------------------------------------------

revoke all on function public.analytics_assert_service_role() from public, anon, authenticated;
grant execute on function public.analytics_assert_service_role() to service_role;
revoke all on function public.analytics_assert_member(uuid) from public, anon, authenticated;
revoke all on function public.analytics_feature_enabled(uuid, text) from public, anon, authenticated;
revoke all on function public.analytics_assert_feature(uuid, text) from public, anon, authenticated;
revoke all on function public.analytics_assert_any_feature(uuid, text[]) from public, anon, authenticated;
revoke all on function public.analytics_org_timezone(uuid) from public, anon, authenticated;
revoke all on function public.analytics_period_bounds(uuid, text, date, date)
  from public, anon, authenticated;
revoke all on function public.analytics_fiscal_economic_sign(public.fiscal_operation_kind)
  from public, anon, authenticated;
revoke all on function public.analytics_is_economic_journal_status(public.journal_entry_status)
  from public, anon, authenticated;
revoke all on function public.analytics_journal_economic_lines(uuid) from public, anon, authenticated;
revoke all on function public.analytics_account_is_cogs(uuid) from public, anon, authenticated;
revoke all on function public.analytics_sales_fiscal_net(uuid, date, date, text)
  from public, anon, authenticated;
revoke all on function public.analytics_sales_fiscal_gross(uuid, date, date, text)
  from public, anon, authenticated;
revoke all on function public.analytics_signed_balance(numeric, numeric, public.normal_balance)
  from public, anon, authenticated;
revoke all on function public.analytics_prev_period_bounds(date, date)
  from public, anon, authenticated;
revoke all on function public.analytics_metric_payload(text, numeric, text, text, numeric, boolean)
  from public, anon, authenticated;
revoke all on function public.analytics_ar_open_total(uuid) from public, anon, authenticated;
revoke all on function public.analytics_ap_open_total(uuid) from public, anon, authenticated;
revoke all on function public.analytics_treasury_type_balance(uuid, public.treasury_account_type)
  from public, anon, authenticated;
revoke all on function public.analytics_aging_bucket(date, date) from public, anon, authenticated;
revoke all on function public.analytics_alert_upsert_open(
  uuid, text, public.analytics_alert_domain, text, public.analytics_alert_severity, text, uuid, jsonb
) from public, anon, authenticated;
revoke all on function public.analytics_alert_resolve_missing(uuid, text, text[])
  from public, anon, authenticated;
revoke all on function public.analytics_alert_rule_enabled(uuid, text)
  from public, anon, authenticated;
revoke all on function public.analytics_alert_threshold(uuid, text)
  from public, anon, authenticated;
-- ---------------------------------------------------------------------------
-- Client RPCs — authenticated only
-- ---------------------------------------------------------------------------

revoke all on function public.get_dashboard_summary(uuid, text, date, date, text) from public, anon;
grant execute on function public.get_dashboard_summary(uuid, text, date, date, text) to authenticated;
revoke all on function public.get_financial_dashboard(uuid, text, date, date, text) from public, anon;
grant execute on function public.get_financial_dashboard(uuid, text, date, date, text) to authenticated;
revoke all on function public.get_ar_aging(uuid, date) from public, anon;
grant execute on function public.get_ar_aging(uuid, date) to authenticated;
revoke all on function public.get_ap_aging(uuid, date) from public, anon;
grant execute on function public.get_ap_aging(uuid, date) to authenticated;
revoke all on function public.analytics_management_pnl(uuid, date, date) from public, anon;
grant execute on function public.analytics_management_pnl(uuid, date, date) to authenticated;
revoke all on function public.analytics_management_balance_sheet(uuid, date) from public, anon;
grant execute on function public.analytics_management_balance_sheet(uuid, date) to authenticated;
revoke all on function public.get_report_dataset(uuid, text, jsonb, int, int) from public, anon;
grant execute on function public.get_report_dataset(uuid, text, jsonb, int, int) to authenticated;
revoke all on function public.evaluate_analytics_alerts(uuid) from public, anon;
grant execute on function public.evaluate_analytics_alerts(uuid) to authenticated;
revoke all on function public.ack_analytics_alert(uuid) from public, anon;
grant execute on function public.ack_analytics_alert(uuid) to authenticated;
revoke all on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
  from public, anon;
grant execute on function public.upsert_saved_report(uuid, text, text, jsonb, jsonb, jsonb, text, uuid)
  to authenticated;
revoke all on function public.list_saved_reports(uuid, text) from public, anon;
grant execute on function public.list_saved_reports(uuid, text) to authenticated;
revoke all on function public.delete_saved_report(uuid) from public, anon;
grant execute on function public.delete_saved_report(uuid) to authenticated;
revoke all on function public.upsert_analytics_inventory_threshold(
  uuid, uuid, numeric, uuid, numeric, boolean, uuid
) from public, anon;
grant execute on function public.upsert_analytics_inventory_threshold(
  uuid, uuid, numeric, uuid, numeric, boolean, uuid
) to authenticated;
-- ---------------------------------------------------------------------------
-- Table grants (defense in depth)
-- ---------------------------------------------------------------------------

revoke all on table public.analytics_metric_definitions from public, anon;
grant select on table public.analytics_metric_definitions to authenticated;
grant all on table public.analytics_metric_definitions to service_role;
revoke all on table public.saved_reports from public, anon;
grant select, insert, update, delete on table public.saved_reports to authenticated;
grant all on table public.saved_reports to service_role;
revoke all on table public.analytics_alert_settings from public, anon;
grant select, insert, update, delete on table public.analytics_alert_settings to authenticated;
grant all on table public.analytics_alert_settings to service_role;
revoke all on table public.analytics_alert_events from public, anon;
grant select on table public.analytics_alert_events to authenticated;
grant all on table public.analytics_alert_events to service_role;
revoke all on table public.analytics_inventory_thresholds from public, anon;
grant select, insert, update, delete on table public.analytics_inventory_thresholds to authenticated;
grant all on table public.analytics_inventory_thresholds to service_role;
-- ---------------------------------------------------------------------------
-- Extra FK covering indexes (advisor)
-- ---------------------------------------------------------------------------

create index if not exists saved_reports_organization_id_idx
  on public.saved_reports (organization_id);
create index if not exists analytics_alert_settings_organization_id_idx
  on public.analytics_alert_settings (organization_id);
create index if not exists analytics_alert_events_organization_id_idx
  on public.analytics_alert_events (organization_id);
create index if not exists analytics_inventory_thresholds_organization_id_idx
  on public.analytics_inventory_thresholds (organization_id);
