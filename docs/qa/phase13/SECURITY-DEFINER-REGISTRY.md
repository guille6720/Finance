# SECURITY DEFINER registry (Phase 13 deep audit)

Every `public` SECURITY DEFINER function must be `PASS` or `INTENTIONAL_AND_DOCUMENTED`.
Generic `REVIEW` is not allowed. `UNEXPLAINED SECURITY DEFINER` must be 0.

**Generated**: 2026-09-09T16:17:12.295Z
**Total**: 156 | **PASS**: 156 | **FAIL/UNEXPLAINED**: 0
**Source breakdown**: registry=4, auto_classified=91, execute_revoked=61, unclassified=0, hard_fail=0

## `accept_quote(p_document_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access`

## `accounting_write_audit(p_organization_id uuid, p_actor uuid, p_event_type text, p_entity_type text, p_entity_id text, p_action text, p_metadata jsonb)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `ack_analytics_alert(p_alert_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_any_feature(, analytics_assert_capability( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_any_feature(, analytics_assert_capability( — RAISES exception on unauthorized access`

## `activate_tax_rule_version(p_rule_version_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_service_role( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_service_role( — RAISES exception on unauthorized access`

## `analytics_account_is_cogs(p_account_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_alert_resolve_missing(p_org_id uuid, p_rule_code text, p_active_dedup_keys text[])`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_alert_rule_enabled(p_org_id uuid, p_rule_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_alert_threshold(p_org_id uuid, p_rule_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_alert_upsert_open(p_org_id uuid, p_rule_code text, p_domain analytics_alert_domain, p_dedup_key text, p_severity analytics_alert_severity, p_entity_type text, p_entity_id uuid, p_payload jsonb)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_ap_open_total(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_ar_open_total(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_assert_any_feature(p_org_id uuid, p_feature_codes text[])`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_assert_capability(p_org_id uuid, p_capability analytics_capability)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_assert_feature(p_org_id uuid, p_feature_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_assert_member(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_feature_enabled(p_org_id uuid, p_feature_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_has_capability(p_org_id uuid, p_capability analytics_capability)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_journal_economic_lines(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_management_balance_sheet(p_org_id uuid, p_as_of date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access`

## `analytics_management_pnl(p_org_id uuid, p_from date, p_to date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access`

## `analytics_member_role(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_org_timezone(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_period_bounds(p_org_id uuid, p_preset text, p_from date, p_to date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_product_margin_summary(p_organization_id uuid, p_from date, p_to date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature( — RAISES exception on unauthorized access`

## `analytics_sales_fiscal_gross(p_org_id uuid, p_from date, p_to date, p_env text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_sales_fiscal_net(p_org_id uuid, p_from date, p_to date, p_env text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_test_fixture_mixed_product_margin(p_organization_id uuid, p_issue_date date, p_stock_net numeric, p_service_net numeric, p_cogs numeric)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_treasury_type_balance(p_org_id uuid, p_account_type treasury_account_type)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `analytics_validate_saved_report_config(p_report_code text, p_filters jsonb, p_columns jsonb, p_sort jsonb)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `apply_module_pack(p_organization_id uuid, p_pack_id uuid, p_expected_configuration_hash text, p_confirm boolean)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): modules_assert_configure( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): modules_assert_configure( — RAISES exception on unauthorized access`

## `approve_purchase_order(p_order_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access`

## `begin_fiscal_authorization(p_fiscal_document_id uuid, p_intended_document_number bigint, p_certificate_fingerprint text, p_request_hash text, p_correlation_id text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `begin_pos_checkout(p_pos_sale_id uuid, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature(, pos_assert_feature_code( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature(, pos_assert_feature_code( — RAISES exception on unauthorized access`

## `bootstrap_organization_modules(p_organization_id uuid, p_enable_feature_codes text[])`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `calculate_tax_determination(p_tax_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access`

## `calculate_tax_period(p_tax_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role( — RAISES exception on unauthorized access`

## `can_mutate_org(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: registry
- Rationale: Thin wrapper over has_org_role(owner|admin|manager). Same SECURITY DEFINER constraints. Documented mutate surface for org-scoped tables.

## `cancel_pos_sale_draft(p_pos_sale_id uuid, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access`

## `cancel_sales_document(p_document_id uuid, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access`

## `close_accounting_period(p_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `close_pos_session(p_session_id uuid, p_closing_counted_cash numeric, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access`

## `close_tax_period(p_tax_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access`

## `complete_fiscal_authorization(p_attempt_id uuid, p_outcome fiscal_authorization_outcome, p_cae text, p_cae_expiration date, p_arca_error_codes jsonb, p_arca_observation_codes jsonb, p_transport_error_class text, p_arca_result jsonb)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `complete_purchase_order(p_order_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access`

## `confirm_sales_order(p_order_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access`

## `convert_quote_to_order(p_quote_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access`

## `create_inventory_reservation(p_organization_id uuid, p_product_id uuid, p_warehouse_id uuid, p_sales_document_id uuid, p_sales_document_line_id uuid, p_quantity numeric, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_is_org_member: delegates tenant isolation to is_org_member(); org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_is_org_member: delegates tenant isolation to is_org_member()`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access`

## `create_tax_obligation(p_tax_period_id uuid, p_obligation_type tax_obligation_type, p_amount numeric, p_due_date date, p_narrative text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access`

## `deactivate_product(p_product_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `delete_saved_report(p_saved_report_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member( — RAISES exception on unauthorized access`

## `ensure_ar_from_fiscal_document(p_fiscal_document_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_is_org_member: delegates tenant isolation to is_org_member(); org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_is_org_member: delegates tenant isolation to is_org_member()`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `ensure_inventory_chart_accounts(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `ensure_inventory_cost_row(p_org uuid, p_product uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `ensure_inventory_stock_row(p_org uuid, p_wh uuid, p_product uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `ensure_monthly_periods(p_fiscal_year_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `ensure_pos_walk_in_and_settings(p_org_id uuid, p_legal_name text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access`

## `ensure_tax_period(p_organization_id uuid, p_tax_code tax_code, p_jurisdiction_code text, p_period_year integer, p_period_month integer, p_workspace_environment tax_workspace_environment)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access`

## `ensure_treasury_clearing_coa(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `evaluate_analytics_alerts(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_any_feature(, analytics_assert_capability( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_any_feature(, analytics_assert_capability( — RAISES exception on unauthorized access`

## `finalize_pos_sale(p_pos_sale_id uuid, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature(, treasury_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature(, treasury_assert_feature( — RAISES exception on unauthorized access`

## `get_ap_aging(p_organization_id uuid, p_as_of date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_any_feature(, analytics_assert_capability( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_any_feature(, analytics_assert_capability( — RAISES exception on unauthorized access`

## `get_ar_aging(p_organization_id uuid, p_as_of date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_any_feature(, analytics_assert_capability( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_any_feature(, analytics_assert_capability( — RAISES exception on unauthorized access`

## `get_attention_summary(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access; analytics_has_capability: calls analytics_has_capability() — gates on org-level analytics capability
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access`
  - `analytics_has_capability: calls analytics_has_capability() — gates on org-level analytics capability`

## `get_dashboard_summary(p_organization_id uuid, p_period_preset text, p_from date, p_to date, p_compare_mode text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access; analytics_has_capability: calls analytics_has_capability() — gates on org-level analytics capability
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access`
  - `analytics_has_capability: calls analytics_has_capability() — gates on org-level analytics capability`

## `get_financial_dashboard(p_organization_id uuid, p_period_preset text, p_from date, p_to date, p_compare_mode text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability( — RAISES exception on unauthorized access`

## `get_module_configuration_state(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): modules_assert_read( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): modules_assert_read( — RAISES exception on unauthorized access`

## `get_report_dataset(p_organization_id uuid, p_report_code text, p_filters jsonb, p_limit integer, p_offset integer)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability(, analytics_assert_any_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature(, analytics_assert_capability(, analytics_assert_any_feature( — RAISES exception on unauthorized access`

## `handle_new_user()`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: registry
- Rationale: Auth trigger on auth.users must insert profiles with elevated rights. Direct EXECUTE revoked from anon/authenticated/public in Phase 13 migration. search_path pinned to public.

## `has_org_role(p_org_id uuid, p_roles member_role[])`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: registry
- Rationale: RLS helper for role checks. Bound to auth.uid(), active membership, role = any(p_roles). search_path=public. No cross-tenant leakage vector beyond caller JWT.

## `ignore_bank_statement_line(p_statement_line_id uuid, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `inventory_assert_feature(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access`

## `is_org_member(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: registry
- Rationale: RLS helper bypasses RLS on organization_members to avoid recursion. Bound to auth.uid(), active membership only, search_path=public, EXECUTE granted to authenticated only.

## `list_saved_reports(p_organization_id uuid, p_report_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature( — RAISES exception on unauthorized access`

## `mark_fiscal_ready_to_authorize(p_fiscal_document_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): fiscal_assert_feature(, fiscal_assert_role( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): fiscal_assert_feature(, fiscal_assert_role( — RAISES exception on unauthorized access`

## `mark_order_ready_to_invoice(p_order_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access`

## `mark_purchase_reviewed(p_document_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access`

## `match_bank_statement_line(p_statement_line_id uuid, p_treasury_operation_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): treasury_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): treasury_assert_feature( — RAISES exception on unauthorized access`

## `modules_assert_configure(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `modules_assert_read(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `modules_assert_service_role()`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `modules_config_hash(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `modules_disable_block_reason(p_organization_id uuid, p_feature_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `modules_entitlement_is_granted(p_organization_id uuid, p_feature_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `modules_entitlement_is_restricted(p_organization_id uuid, p_feature_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `modules_evaluate_feature_state(p_organization_id uuid, p_feature_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `modules_lock_organization(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `modules_preference_desired(p_organization_id uuid, p_feature_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `modules_write_audit(p_organization_id uuid, p_actor uuid, p_event_type text, p_action text, p_metadata jsonb)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `next_inventory_operation_number(p_org_id uuid, p_operation_type inventory_operation_type)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_is_org_member: delegates tenant isolation to is_org_member(); domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_is_org_member: delegates tenant isolation to is_org_member()`
  - `domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access`

## `next_purchase_order_number(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access`

## `next_sales_internal_number(p_organization_id uuid, p_document_type sales_document_type, p_document_date date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `next_treasury_operation_number(p_org_id uuid, p_operation_type treasury_operation_type)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): treasury_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): treasury_assert_feature( — RAISES exception on unauthorized access`

## `open_pos_session(p_terminal_id uuid, p_opening_counted_cash numeric, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access`

## `phase12_assert_authenticated_function_acl()`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `phase12_assert_authenticated_table_acl()`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `phase5_prelive_selfcheck()`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `platform_bootstrap_organization_modules(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `platform_disable_organization_feature(p_organization_id uuid, p_feature_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `platform_enable_organization_feature(p_organization_id uuid, p_feature_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `platform_grant_feature_entitlement(p_organization_id uuid, p_feature_code text, p_source_type feature_entitlement_source, p_metadata jsonb)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `platform_revoke_feature_entitlement(p_organization_id uuid, p_feature_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `platform_set_feature_release(p_feature_code text, p_release_status feature_release_status, p_self_service_allowed boolean, p_notes text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `pos_assert_feature(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `pos_assert_feature_code(p_org_id uuid, p_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `pos_test_fixture_mark_fiscal_authorized(p_fiscal_document_id uuid, p_cae text, p_cae_expiration date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `pos_validate_tender_account(p_org_id uuid, p_terminal_id uuid, p_method pos_tender_method, p_treasury_account_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `pos_validate_walk_in_customer(p_org_id uuid, p_customer_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `post_inventory_operation(p_operation_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access`

## `post_journal_entry(p_entry_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_is_org_member: delegates tenant isolation to is_org_member(); org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_is_org_member: delegates tenant isolation to is_org_member()`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `post_open_item_compensation(p_domain open_item_domain, p_increase_item_id uuid, p_decrease_item_id uuid, p_amount numeric, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `post_purchase_document(p_document_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access`

## `post_fiscal_document_accounting(p_fiscal_document_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: manual_phase5_accounting_post_once
- Rationale: Exactly-once fiscal→GL post. auth.uid() required; fiscal_assert_feature + fiscal_assert_role(owner/admin/accountant); only AUTHORIZED docs; unique (org, fiscal_document, ARCA_AUTHORIZED) + SALE source unique index; posts via existing post_journal_entry; EXECUTE revoked from anon/public; granted to authenticated (+ service_role for trusted callers with user JWT context).
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): fiscal_assert_feature(, fiscal_assert_role(`
  - `idempotency: fiscal_accounting_post_keys PK + journal_entries_sale_source_uidx`

## `post_treasury_operation(p_operation_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): treasury_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): treasury_assert_feature( — RAISES exception on unauthorized access`

## `prepare_fiscal_invoice_from_sales_order(p_sales_document_id uuid, p_point_of_sale_id uuid, p_document_type_internal_code text, p_issue_date date, p_condicion_iva_receptor_id integer)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): fiscal_assert_feature(, fiscal_assert_role( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): fiscal_assert_feature(, fiscal_assert_role( — RAISES exception on unauthorized access`

## `prepare_fiscal_note(p_parent_fiscal_document_id uuid, p_document_type_internal_code text, p_relationship fiscal_relationship_type, p_issue_date date, p_idempotency_key text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): fiscal_assert_feature(, fiscal_assert_role( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): fiscal_assert_feature(, fiscal_assert_role( — RAISES exception on unauthorized access`

## `prepare_pos_fiscal_handoff(p_pos_sale_id uuid, p_document_type_internal_code text, p_condicion_iva_receptor_id integer)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature(, pos_assert_feature_code( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature(, pos_assert_feature_code( — RAISES exception on unauthorized access`

## `preview_module_pack(p_organization_id uuid, p_pack_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): modules_assert_configure( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): modules_assert_configure( — RAISES exception on unauthorized access`

## `purchase_line_inventory_debit_account(p_organization_id uuid, p_product_id uuid, p_fallback_expense uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `recompute_feature_for_all_organizations(p_feature_id uuid, p_actor uuid, p_source text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `recompute_organization_features(p_organization_id uuid, p_actor uuid, p_source text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `reconcile_vat_accounting(p_tax_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): org_gate_is_org_member: delegates tenant isolation to is_org_member()
- Evidence patterns:
  - `org_gate_is_org_member: delegates tenant isolation to is_org_member()`

## `record_tax_filing_external(p_tax_period_id uuid, p_filing_kind tax_filing_kind, p_external_form_code text, p_external_receipt_number text, p_filed_at timestamp with time zone, p_evidence_reference text, p_evidence_hash text, p_supersedes_filing_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access`

## `record_tax_payment_external(p_tax_obligation_id uuid, p_payment_date date, p_amount numeric, p_external_reference text, p_payment_method_description text, p_evidence_reference text, p_evidence_hash text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access`

## `register_tax_wp(p_organization_id uuid, p_wp_type tax_wp_type, p_tax_code tax_code, p_operation_date date, p_tax_period_date date, p_amount numeric, p_certificate_number text, p_jurisdiction_code text, p_counterparty_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access`

## `reject_quote(p_document_id uuid, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access`

## `release_inventory_reservation(p_reservation_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_is_org_member: delegates tenant isolation to is_org_member(); domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_is_org_member: delegates tenant isolation to is_org_member()`
  - `domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access`

## `reopen_accounting_period(p_period_id uuid, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `reopen_tax_period(p_tax_period_id uuid, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access`

## `reset_pos_checkout(p_pos_sale_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `revalidate_tax_determination_sources(p_tax_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): org_gate_is_org_member: delegates tenant isolation to is_org_member()
- Evidence patterns:
  - `org_gate_is_org_member: delegates tenant isolation to is_org_member()`

## `reverse_inventory_operation(p_operation_id uuid, p_reversal_date date, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): inventory_assert_feature( — RAISES exception on unauthorized access`

## `reverse_journal_entry(p_original_entry_id uuid, p_reversal_date date, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_is_org_member: delegates tenant isolation to is_org_member(); org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_is_org_member: delegates tenant isolation to is_org_member()`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `reverse_purchase_document(p_document_id uuid, p_reversal_date date, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): purchase_assert_feature(, purchase_assert_role( — RAISES exception on unauthorized access`

## `reverse_treasury_operation(p_operation_id uuid, p_reversal_date date, p_reason text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): treasury_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): treasury_assert_feature( — RAISES exception on unauthorized access`

## `review_tax_period(p_tax_period_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access`

## `sales_assert_feature(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `seed_starter_chart_of_accounts(p_organization_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `send_quote(p_document_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `domain_assert_helper: calls project-specific authz assert(s): sales_assert_role(, sales_assert_feature( — RAISES exception on unauthorized access`

## `set_fiscal_qr_payload(p_fiscal_document_id uuid, p_qr_payload text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `set_organization_feature_preference(p_organization_id uuid, p_feature_code text, p_desired_enabled boolean, p_confirm_dependencies boolean)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): modules_assert_configure( — RAISES exception on unauthorized access
- Evidence patterns:
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): modules_assert_configure( — RAISES exception on unauthorized access`

## `set_pos_tenders(p_pos_sale_id uuid, p_tenders jsonb)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access`

## `start_pos_sale(p_session_id uuid, p_idempotency_key text, p_customer_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access`

## `sync_pos_fiscal_status(p_pos_sale_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): pos_assert_feature( — RAISES exception on unauthorized access`

## `tax_assert_feature(p_org_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): tax_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_feature( — RAISES exception on unauthorized access`

## `tax_assert_role(p_org_id uuid, p_roles member_role[])`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): tax_assert_role( — RAISES exception on unauthorized access
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role( — RAISES exception on unauthorized access`

## `tax_obligation_outstanding(p_tax_obligation_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): org_gate_is_org_member: delegates tenant isolation to is_org_member()
- Evidence patterns:
  - `org_gate_is_org_member: delegates tenant isolation to is_org_member()`

## `tax_resolve_active_rule(p_tax_code tax_code, p_jurisdiction_code text, p_rule_key text, p_as_of date)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `tax_resolve_effective_date(p_tax_code tax_code, p_source_domain tax_source_domain, p_issue_date date, p_accounting_date date, p_rule_version tax_rule_versions)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `tax_test_fixture_authorized_fiscal(p_organization_id uuid, p_issue_date date, p_fiscal_environment fiscal_environment, p_vat_amount numeric, p_net_taxed numeric, p_counterparty_id uuid, p_point_of_sale_id uuid, p_document_type_internal_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: execute_revoked
- Rationale: execute_revoked_from_client_roles: EXECUTE revoked from anon and authenticated — callable only by service_role/postgres or other SECURITY DEFINER RPCs. svc_can_execute=true.

## `tax_test_fixture_purchase_iva_components(p_organization_id uuid, p_supplier_id uuid, p_issue_date date, p_components jsonb)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): service_role_enforce_raise: RAISE EXCEPTION guards execution to service_role callers only
- Evidence patterns:
  - `service_role_enforce_raise: RAISE EXCEPTION guards execution to service_role callers only`

## `unmatch_bank_statement_line(p_statement_line_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity; org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability
- Evidence patterns:
  - `auth_uid_bound: calls auth.uid() — binds operation to current JWT user identity`
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`

## `upsert_analytics_inventory_threshold(p_organization_id uuid, p_product_id uuid, p_minimum_available_quantity numeric, p_warehouse_id uuid, p_warning_quantity numeric, p_active boolean, p_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): org_gate_has_org_role: delegates role check to has_org_role(); entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `org_gate_has_org_role: delegates role check to has_org_role()`
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature( — RAISES exception on unauthorized access`

## `upsert_iibb_jurisdiction_allocation(p_tax_period_id uuid, p_jurisdiction_code text, p_distribution_method iibb_distribution_method, p_sales_allocation_strategy iibb_sales_allocation_strategy, p_gross_revenue_amount numeric, p_cm_form_code tax_cm_form_code, p_coefficient numeric, p_narrative text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access`

## `upsert_organization_tax_registration(p_organization_id uuid, p_tax_code tax_code, p_jurisdiction_code text, p_registration_number text, p_effective_from date, p_regime_metadata jsonb)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access`

## `upsert_saved_report(p_organization_id uuid, p_report_code text, p_name text, p_filters_json jsonb, p_columns_json jsonb, p_sort_json jsonb, p_visibility text, p_id uuid)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): analytics_assert_member(, analytics_assert_feature( — RAISES exception on unauthorized access`

## `upsert_vat_purchase_classification(p_organization_id uuid, p_purchase_document_id uuid, p_purchase_tax_summary_id uuid, p_classification vat_credit_classification, p_computable_amount numeric, p_noncomputable_amount numeric, p_reason_code text, p_reason_notes text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access
- Evidence patterns:
  - `domain_assert_helper: calls project-specific authz assert(s): tax_assert_role(, tax_assert_feature( — RAISES exception on unauthorized access`

## `why_feature_unavailable(p_organization_id uuid, p_feature_code text)`

- Verdict: **INTENTIONAL_AND_DOCUMENTED**
- Gate: PASS
- search_path pinned: true
- Source: auto_classified
- Rationale: Auto-classified (evidence-based): entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability; domain_assert_helper: calls project-specific authz assert(s): modules_assert_read( — RAISES exception on unauthorized access
- Evidence patterns:
  - `entitlement_assert: RAISE EXCEPTION before mutation on missing feature/entitlement/permission/capability`
  - `domain_assert_helper: calls project-specific authz assert(s): modules_assert_read( — RAISES exception on unauthorized access`


UNEXPLAINED SECURITY DEFINER = 0
