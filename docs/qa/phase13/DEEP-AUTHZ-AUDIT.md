# Deep SECURITY / RPC authz audit

DEFINER_DEEP_AUTHZ_PASS=442/442
FAIL=0
UNEXPLAINED_APP_RPC=0
AUTO_CLASSIFIED=159

**Generated**: 2026-09-09T16:17:14.110Z

## public (application)

### `public.accept_quote(p_document_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access

### `public.ack_analytics_alert(p_alert_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_any_feature(, analytics_assert_capability( — RAISES exception on unauthorized access

### `public.activate_tax_rule_version(p_rule_version_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_service_role( — RAISES exception on unauthorized access

### `public.analytics_management_balance_sheet(p_org_id uuid, p_as_of date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access

### `public.analytics_management_pnl(p_org_id uuid, p_from date, p_to date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access

### `public.analytics_product_margin_summary(p_organization_id uuid, p_from date, p_to date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature( — RAISES exception on unauthorized access

### `public.apply_module_pack(p_organization_id uuid, p_pack_id uuid, p_expected_configuration_hash text, p_confirm boolean)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): modules_assert_configure( — RAISES exception on unauthorized access

### `public.approve_purchase_order(p_order_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access

### `public.assert_active_supplier(p_org_id uuid, p_supplier_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.begin_pos_checkout(p_pos_sale_id uuid, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature(, pos_assert_feature_code( — RAISES exception on unauthorized access

### `public.build_counterparty_snapshot(p_organization_id uuid, p_counterparty_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.build_supplier_snapshot(p_org_id uuid, p_supplier_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.calculate_tax_determination(p_tax_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access

### `public.calculate_tax_period(p_tax_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role( — RAISES exception on unauthorized access

### `public.can_mutate_org(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: registry

### `public.cancel_pos_sale_draft(p_pos_sale_id uuid, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access

### `public.cancel_sales_document(p_document_id uuid, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access

### `public.close_accounting_period(p_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.close_pos_session(p_session_id uuid, p_closing_counted_cash numeric, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access

### `public.close_tax_period(p_tax_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access

### `public.complete_purchase_order(p_order_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access

### `public.confirm_sales_order(p_order_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access

### `public.convert_quote_to_order(p_quote_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access

### `public.counterparties_normalize_tax_id()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.create_inventory_reservation(p_organization_id uuid, p_product_id uuid, p_warehouse_id uuid, p_sales_document_id uuid, p_sales_document_line_id uuid, p_quantity numeric, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_is_org_member: delegates tenant isolation to is_org_member(); org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access

### `public.create_tax_obligation(p_tax_period_id uuid, p_obligation_type tax_obligation_type, p_amount numeric, p_due_date date, p_narrative text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access

### `public.deactivate_product(p_product_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.delete_saved_report(p_saved_report_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member( — RAISES exception on unauthorized access

### `public.ensure_ar_from_fiscal_document(p_fiscal_document_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_is_org_member: delegates tenant isolation to is_org_member(); org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.ensure_inventory_chart_accounts(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.ensure_monthly_periods(p_fiscal_year_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.ensure_pos_walk_in_and_settings(p_org_id uuid, p_legal_name text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access

### `public.ensure_tax_period(p_organization_id uuid, p_tax_code tax_code, p_jurisdiction_code text, p_period_year integer, p_period_month integer, p_workspace_environment tax_workspace_environment)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access

### `public.ensure_treasury_clearing_coa(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.evaluate_analytics_alerts(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_any_feature(, analytics_assert_capability( — RAISES exception on unauthorized access

### `public.feature_dependencies_assert_dag()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.finalize_pos_sale(p_pos_sale_id uuid, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature(, treasury_assert_feature( — RAISES exception on unauthorized access

### `public.find_counterparty_soft_duplicates(p_organization_id uuid, p_legal_name text, p_email text, p_phone text, p_exclude_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.fiscal_assert_feature(p_org_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.fiscal_assert_role(p_org_id uuid, p_roles member_role[])`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.get_ap_aging(p_organization_id uuid, p_as_of date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_any_feature(, analytics_assert_capability( — RAISES exception on unauthorized access

### `public.get_ar_aging(p_organization_id uuid, p_as_of date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_any_feature(, analytics_assert_capability( — RAISES exception on unauthorized access

### `public.get_attention_summary(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access; analytics_has_capability: calls analytics_has_capability() — gates on org-level analytics capability

### `public.get_dashboard_summary(p_organization_id uuid, p_period_preset text, p_from date, p_to date, p_compare_mode text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access; analytics_has_capability: calls analytics_has_capability() — gates on org-level analytics capability

### `public.get_financial_dashboard(p_organization_id uuid, p_period_preset text, p_from date, p_to date, p_compare_mode text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access

### `public.get_module_configuration_state(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): modules_assert_read( — RAISES exception on unauthorized access

### `public.get_report_dataset(p_organization_id uuid, p_report_code text, p_filters jsonb, p_limit integer, p_offset integer)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability(, analytics_assert_any_feature( — RAISES exception on unauthorized access

### `public.has_org_role(p_org_id uuid, p_roles member_role[])`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: registry

### `public.ignore_bank_statement_line(p_statement_line_id uuid, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.inventory_assert_feature(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access

### `public.inventory_round_avg(p_value numeric, p_qty numeric)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.inventory_round_value(p_qty numeric, p_unit_cost numeric)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.is_org_member(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: registry

### `public.list_saved_reports(p_organization_id uuid, p_report_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature( — RAISES exception on unauthorized access

### `public.mark_fiscal_ready_to_authorize(p_fiscal_document_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): fiscal_assert_feature(, fiscal_assert_role( — RAISES exception on unauthorized access

### `public.mark_order_ready_to_invoice(p_order_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access

### `public.mark_purchase_reviewed(p_document_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access

### `public.match_bank_statement_line(p_statement_line_id uuid, p_treasury_operation_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): treasury_assert_feature( — RAISES exception on unauthorized access

### `public.next_inventory_operation_number(p_org_id uuid, p_operation_type inventory_operation_type)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_is_org_member: delegates tenant isolation to is_org_member(); domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access

### `public.next_purchase_order_number(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access

### `public.next_sales_internal_number(p_organization_id uuid, p_document_type sales_document_type, p_document_date date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.next_treasury_operation_number(p_org_id uuid, p_operation_type treasury_operation_type)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): treasury_assert_feature( — RAISES exception on unauthorized access

### `public.normalize_counterparty_tax_id(p_type tax_id_type, p_value text)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.open_pos_session(p_terminal_id uuid, p_opening_counted_cash numeric, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access

### `public.organization_features_engine_write_guard()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.pos_expected_account_type(p_method pos_tender_method)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.pos_settings_validate_before_write()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.pos_terminal_validate_before_write()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.pos_tta_validate_before_write()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.post_inventory_operation(p_operation_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access

### `public.post_journal_entry(p_entry_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_is_org_member: delegates tenant isolation to is_org_member(); org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.post_open_item_compensation(p_domain open_item_domain, p_increase_item_id uuid, p_decrease_item_id uuid, p_amount numeric, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.post_purchase_document(p_document_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access

### `public.post_treasury_operation(p_operation_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): treasury_assert_feature( — RAISES exception on unauthorized access

### `public.prepare_fiscal_invoice_from_sales_order(p_sales_document_id uuid, p_point_of_sale_id uuid, p_document_type_internal_code text, p_issue_date date, p_condicion_iva_receptor_id integer)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): fiscal_assert_feature(, fiscal_assert_role( — RAISES exception on unauthorized access

### `public.prepare_fiscal_note(p_parent_fiscal_document_id uuid, p_document_type_internal_code text, p_relationship fiscal_relationship_type, p_issue_date date, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): fiscal_assert_feature(, fiscal_assert_role( — RAISES exception on unauthorized access

### `public.prepare_pos_fiscal_handoff(p_pos_sale_id uuid, p_document_type_internal_code text, p_condicion_iva_receptor_id integer)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature(, pos_assert_feature_code( — RAISES exception on unauthorized access

### `public.prevent_active_fiscal_rule_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_active_tax_rule_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_ap_client_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_ar_client_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_authorized_fiscal_line_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_authorized_fiscal_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_authorized_fiscal_summary_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_counterparty_delete_with_movements()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_frozen_sales_document_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_frozen_sales_line_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_inventory_ledger_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_inventory_projection_client_write()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_pos_sale_engine_forgery()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_pos_session_expected_forgery()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_pos_tender_engine_forgery()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_posted_allocation_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_posted_inventory_line_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_posted_inventory_op_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_posted_purchase_line_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_posted_purchase_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_posted_treasury_leg_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_posted_treasury_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_reservation_client_mutate()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_tax_determination_client_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_tax_filing_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_tax_payment_mutation()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.prevent_tax_period_status_forgery()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.preview_module_pack(p_organization_id uuid, p_pack_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): modules_assert_configure( — RAISES exception on unauthorized access

### `public.purchase_assert_feature(p_org_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.purchase_assert_role(p_org_id uuid, p_roles member_role[])`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.recalculate_sales_line_amounts()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.reconcile_vat_accounting(p_tax_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): org_gate_is_org_member: delegates tenant isolation to is_org_member()

### `public.record_tax_filing_external(p_tax_period_id uuid, p_filing_kind tax_filing_kind, p_external_form_code text, p_external_receipt_number text, p_filed_at timestamp with time zone, p_evidence_reference text, p_evidence_hash text, p_supersedes_filing_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access

### `public.record_tax_payment_external(p_tax_obligation_id uuid, p_payment_date date, p_amount numeric, p_external_reference text, p_payment_method_description text, p_evidence_reference text, p_evidence_hash text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access

### `public.refresh_sales_document_totals(p_document_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.register_tax_wp(p_organization_id uuid, p_wp_type tax_wp_type, p_tax_code tax_code, p_operation_date date, p_tax_period_date date, p_amount numeric, p_certificate_number text, p_jurisdiction_code text, p_counterparty_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access

### `public.reject_quote(p_document_id uuid, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access

### `public.release_inventory_reservation(p_reservation_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_is_org_member: delegates tenant isolation to is_org_member(); domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access

### `public.reopen_accounting_period(p_period_id uuid, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.reopen_tax_period(p_tax_period_id uuid, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access

### `public.reset_pos_checkout(p_pos_sale_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.resolve_adjustment_offset_account(p_org_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.resolve_ap_account(p_org_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.resolve_ar_account(p_org_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.resolve_fiscal_rule_version(p_org_id uuid, p_issue_date date)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.resolve_open_period(p_organization_id uuid, p_entry_date date)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.resolve_opening_equity_account(p_org_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.revalidate_tax_determination_sources(p_tax_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): org_gate_is_org_member: delegates tenant isolation to is_org_member()

### `public.reverse_inventory_operation(p_operation_id uuid, p_reversal_date date, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access

### `public.reverse_journal_entry(p_original_entry_id uuid, p_reversal_date date, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_is_org_member: delegates tenant isolation to is_org_member(); org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.reverse_purchase_document(p_document_id uuid, p_reversal_date date, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access

### `public.reverse_treasury_operation(p_operation_id uuid, p_reversal_date date, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): treasury_assert_feature( — RAISES exception on unauthorized access

### `public.review_tax_period(p_tax_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access

### `public.sales_assert_role(p_organization_id uuid, p_roles member_role[])`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.sales_document_lines_refresh_header()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.sales_write_audit(p_org_id uuid, p_uid uuid, p_event text, p_entity_id uuid, p_action text, p_metadata jsonb)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.seed_starter_chart_of_accounts(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.send_quote(p_document_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access

### `public.set_organization_feature_preference(p_organization_id uuid, p_feature_code text, p_desired_enabled boolean, p_confirm_dependencies boolean)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): modules_assert_configure( — RAISES exception on unauthorized access

### `public.set_pos_tenders(p_pos_sale_id uuid, p_tenders jsonb)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access

### `public.start_pos_sale(p_session_id uuid, p_idempotency_key text, p_customer_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access

### `public.supplier_ap_net_open(p_org_id uuid, p_supplier_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.sync_pos_fiscal_status(p_pos_sale_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access

### `public.tax_assert_feature(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): tax_assert_feature( — RAISES exception on unauthorized access

### `public.tax_assert_role(p_org_id uuid, p_roles member_role[])`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): tax_assert_role( — RAISES exception on unauthorized access

### `public.tax_assert_service_role()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.tax_canonical_fiscal_hash(p_doc fiscal_documents, p_summary fiscal_tax_summaries)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.tax_canonical_purchase_hash(p_doc purchase_documents, p_summary purchase_document_tax_summaries, p_class vat_purchase_classifications)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.tax_fiscal_vat_economic_sign(p_operation_kind fiscal_operation_kind)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.tax_obligation_outstanding(p_tax_obligation_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): org_gate_is_org_member: delegates tenant isolation to is_org_member()

### `public.tax_sha256(p_text text)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.tax_test_fixture_purchase_iva_components(p_organization_id uuid, p_supplier_id uuid, p_issue_date date, p_components jsonb)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): service_role_enforce_raise: RAISE EXCEPTION guards to service_role callers only

### `public.treasury_account_balance(p_account_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.treasury_assert_feature(p_org_id uuid, p_codes text[])`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.unmatch_bank_statement_line(p_statement_line_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability

### `public.upsert_analytics_inventory_threshold(p_organization_id uuid, p_product_id uuid, p_minimum_available_quantity numeric, p_warehouse_id uuid, p_warning_quantity numeric, p_active boolean, p_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature( — RAISES exception on unauthorized access

### `public.upsert_iibb_jurisdiction_allocation(p_tax_period_id uuid, p_jurisdiction_code text, p_distribution_method iibb_distribution_method, p_sales_allocation_strategy iibb_sales_allocation_strategy, p_gross_revenue_amount numeric, p_cm_form_code tax_cm_form_code, p_coefficient numeric, p_narrative text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access

### `public.upsert_organization_tax_registration(p_organization_id uuid, p_tax_code tax_code, p_jurisdiction_code text, p_registration_number text, p_effective_from date, p_regime_metadata jsonb)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access

### `public.upsert_saved_report(p_organization_id uuid, p_report_code text, p_name text, p_filters_json jsonb, p_columns_json jsonb, p_sort_json jsonb, p_visibility text, p_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature( — RAISES exception on unauthorized access

### `public.upsert_vat_purchase_classification(p_organization_id uuid, p_purchase_document_id uuid, p_purchase_tax_summary_id uuid, p_classification vat_credit_classification, p_computable_amount numeric, p_noncomputable_amount numeric, p_reason_code text, p_reason_notes text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access

### `public.validate_counterparty_child_tenancy()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.validate_sales_customer(p_organization_id uuid, p_counterparty_id uuid)`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.validate_sales_document_status_for_type()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.validate_sales_line_tenancy()`

- Verdict: **SECURITY_INVOKER_RLS_SCOPED**
- Gate: PASS
- SECURITY DEFINER: false
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified: security_invoker_rls_scoped: SECURITY INVOKER execution context — all table access subject to PostgreSQL RLS policies enforced by the database engine; no elevated privilege bypass

### `public.why_feature_unavailable(p_organization_id uuid, p_feature_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- SECURITY DEFINER: true
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): modules_assert_read( — RAISES exception on unauthorized access


Platform/vendor RPCs audited: 280 (PASS_PLATFORM_SCOPED ≠ application authorization).

## UNEXPLAINED_APP_RPC = 0 ✅
