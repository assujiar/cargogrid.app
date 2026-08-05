-- CG-S10-ATW-032 (post-Prompt-248 audit) — narrows `ISS-2026-010` to fail closed.
--
-- ===========================================================================
-- What this migration deliberately does NOT do
-- ===========================================================================
--
-- It does not decide which records the Customer Portal may read. That is Phase 8 (Step 13)
-- scope, that prompt exists to define it, and settling it here would be exactly the overreach
-- `ISS-2026-010` has warned against since it was opened.
--
-- It does the opposite and strictly smaller thing: it makes the DEFAULT deny, so Phase 8 opens
-- precisely what the portal needs instead of inheriting 98 policies that were already open.
-- Every statement below is a pure `AND`-narrowing using the same ratified helper
-- `20260730311000` applied to the four tables it had live evidence for.
--
-- ===========================================================================
-- Why it is needed, and where the issue's own premise was wrong
-- ===========================================================================
--
-- `ISS-2026-010` recorded that of the remaining tenant-scoped SELECT policies, "most have no
-- owner-scope branch at all and so already fail closed for a `customer_user` actor (no
-- `org_unit_id`)". That reasoning holds only where a policy ALSO requires an org-unit or
-- record-scope predicate. These 98 require nothing of the kind — `app.has_active_tenant_membership`
-- is the entire test.
--
-- And a `customer_user` satisfies it. Proven in a disposable database rather than argued:
-- `app.invite_user` writes an `app.tenant_user_identities` row, `has_active_tenant_membership`
-- reads exactly that table, and a freshly granted `customer_user` principal returns
-- `has_active_tenant_membership = true` alongside `actor_holds_customer_user_layer = true`.
-- So the moment Step 13 grants its first production portal principal, that principal could read
-- `finance_journals`, `credit_profiles`, `customer_contracts`, `role_assignments`, `users`,
-- vehicle telemetry and the rest of this list — through a raw Supabase client, with no portal
-- code involved at all.
--
-- ===========================================================================
-- How the narrowing is written, and why not the obvious way
-- ===========================================================================
--
-- The layer check is inserted BESIDE each membership call, not appended to the end of the
-- qual. Six of these tables (`approval_request_steps`, `finance_invoice_lines`,
-- `finance_vendor_bill_lines`, `finance_period_close_checklist_items`, `role_versions`,
-- `tenants`) carry no `tenant_id` column of their own and reach tenancy through a parent
-- inside an `EXISTS`. Appending `and not app.actor_holds_customer_user_layer(r.tenant_id)`
-- outside that `EXISTS` does not compile — `r` is out of scope there — and appending
-- `(tenant_id)` fails outright because the column does not exist. Rewriting in place makes one
-- mechanical rule correct for every shape: wherever the membership expression is legal, so is
-- the layer expression, because it is literally the same expression. (98 call sites
-- rewritten across 98 policies.)
--
-- ===========================================================================
-- Scope and safety
-- ===========================================================================
--
-- * **SELECT only, and that is sufficient.** `authenticated` holds SELECT on 233 `app` tables
--   and ZERO INSERT/UPDATE/DELETE (`information_schema.role_table_grants`) — the
--   `ERR-2026-004` defence-in-depth posture. A portal principal cannot write directly to any
--   of these regardless, so read scope is the whole exposure.
-- * **Nothing is removed from staff.** `app.actor_holds_customer_user_layer` is true only for
--   an active `app.principal_memberships` row with `layer = 'customer_user'`. No staff
--   principal holds one, so for every existing caller the added conjunct is constant true.
-- * **Policies with a legitimate customer path are deliberately excluded.** Any policy already
--   carrying an owner-scope branch, a warehouse-eligibility gate, `app.can_access_record`, or
--   an org-unit/branch predicate is untouched — those are either the designed
--   customer-visible paths (`app.files` routes its customer branch through
--   `can_access_record`) or already fail closed on their own. Only policies where tenant
--   membership is the ENTIRE test are narrowed.
-- * **Reversible**: `alter policy ... using` on existing policies. No table, column,
--   constraint, function or grant is touched, and no already-applied migration file is edited.
--
-- What Step 13 inherits is a fail-closed baseline plus an exact, machine-checkable list of what
-- it must deliberately re-open — instead of 98 policies that were open by accident.

alter policy account_conversions_select_scoped on app.account_conversions
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy accounts_select_scoped on app.accounts
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy approval_delegations_select_scoped on app.approval_delegations
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy approval_request_steps_select_scoped on app.approval_request_steps
  using ((EXISTS ( SELECT 1 FROM app.approval_requests r WHERE ((r.id = approval_request_steps.request_id) AND ((app.has_active_tenant_membership(r.tenant_id) AND NOT app.actor_holds_customer_user_layer(r.tenant_id)) OR app.is_supreme_admin())))));

alter policy approval_requests_select_scoped on app.approval_requests
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy canonical_telemetry_events_select_scoped on app.canonical_telemetry_events
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy config_objects_select_scoped on app.config_objects
  using (((tenant_id IS NULL) OR (app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy contact_links_select_scoped on app.contact_links
  using ((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)));

alter policy credit_check_snapshots_select_scoped on app.credit_check_snapshots
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy credit_profile_overrides_select_scoped on app.credit_profile_overrides
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy credit_profiles_select_scoped on app.credit_profiles
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy custom_field_value_idempotency_keys_select_scoped on app.custom_field_value_idempotency_keys
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy custom_field_values_select_scoped on app.custom_field_values
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy customer_contract_price_components_select_scoped on app.customer_contract_price_components
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy customer_contracts_select_scoped on app.customer_contracts
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy device_vehicle_assignments_select_scoped on app.device_vehicle_assignments
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy direct_device_telemetry_reports_select_scoped on app.direct_device_telemetry_reports
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy document_requirement_definitions_select_scoped on app.document_requirement_definitions
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy driver_mobile_position_reports_select_scoped on app.driver_mobile_position_reports
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy driver_mobile_tracking_sessions_select_scoped on app.driver_mobile_tracking_sessions
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy driver_operational_profiles_select_scoped on app.driver_operational_profiles
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy exception_sla_policy_versions_select_scoped on app.exception_sla_policy_versions
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_accounts_select_scoped on app.finance_accounts
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_aging_bucket_configs_select_scoped on app.finance_aging_bucket_configs
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_ap_open_item_events_select_scoped on app.finance_ap_open_item_events
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_ap_open_items_select_scoped on app.finance_ap_open_items
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_ar_open_item_events_select_scoped on app.finance_ar_open_item_events
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_ar_open_items_select_scoped on app.finance_ar_open_items
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_bank_accounts_select_scoped on app.finance_bank_accounts
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_bank_statement_batches_select_scoped on app.finance_bank_statement_batches
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_bank_transactions_select_scoped on app.finance_bank_transactions
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_exchange_rate_import_batches_select_scoped on app.finance_exchange_rate_import_batches
  using (((tenant_id IS NULL) OR (app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_exchange_rates_select_scoped on app.finance_exchange_rates
  using (((tenant_id IS NULL) OR (app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_fiscal_calendars_select_scoped on app.finance_fiscal_calendars
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_fiscal_periods_select_scoped on app.finance_fiscal_periods
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_idempotency_claims_select_scoped on app.finance_idempotency_claims
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_invoice_lines_select_scoped on app.finance_invoice_lines
  using ((EXISTS ( SELECT 1 FROM app.finance_invoices i WHERE ((i.id = finance_invoice_lines.invoice_id) AND ((app.has_active_tenant_membership(i.tenant_id) AND NOT app.actor_holds_customer_user_layer(i.tenant_id)) OR app.is_supreme_admin())))));

alter policy finance_invoices_select_scoped on app.finance_invoices
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_journal_corrections_select_scoped on app.finance_journal_corrections
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_journal_lines_select_scoped on app.finance_journal_lines
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_journals_select_scoped on app.finance_journals
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_period_close_checklist_items_select_scoped on app.finance_period_close_checklist_items
  using ((EXISTS ( SELECT 1 FROM app.finance_fiscal_periods p WHERE ((p.id = finance_period_close_checklist_items.period_id) AND ((app.has_active_tenant_membership(p.tenant_id) AND NOT app.actor_holds_customer_user_layer(p.tenant_id)) OR app.is_supreme_admin())))));

alter policy finance_period_lock_events_select_scoped on app.finance_period_lock_events
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_period_locks_select_scoped on app.finance_period_locks
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_period_transitions_select_scoped on app.finance_period_transitions
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_receipt_allocation_batches_select_scoped on app.finance_receipt_allocation_batches
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_receipt_allocations_select_scoped on app.finance_receipt_allocations
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_receipts_select_scoped on app.finance_receipts
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_reconciliation_exceptions_select_scoped on app.finance_reconciliation_exceptions
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_reconciliation_runs_select_scoped on app.finance_reconciliation_runs
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_settlement_allocations_select_scoped on app.finance_settlement_allocations
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_settlements_select_scoped on app.finance_settlements
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_subledger_batches_select_scoped on app.finance_subledger_batches
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_subledger_lines_select_scoped on app.finance_subledger_lines
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_tax_codes_select_scoped on app.finance_tax_codes
  using (((tenant_id IS NULL) OR (app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_tax_rule_versions_select_scoped on app.finance_tax_rule_versions
  using (((tenant_id IS NULL) OR (app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy finance_vendor_bill_lines_select_scoped on app.finance_vendor_bill_lines
  using ((EXISTS ( SELECT 1 FROM app.finance_vendor_bills b WHERE ((b.id = finance_vendor_bill_lines.bill_id) AND ((app.has_active_tenant_membership(b.tenant_id) AND NOT app.actor_holds_customer_user_layer(b.tenant_id)) OR app.is_supreme_admin())))));

alter policy finance_vendor_bills_select_scoped on app.finance_vendor_bills
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy gps_device_installations_select_scoped on app.gps_device_installations
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy gps_devices_select_scoped on app.gps_devices
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy item_masters_select_scoped on app.item_masters
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy jobs_select_scoped on app.jobs
  using ((app.is_supreme_admin() OR ((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) AND ((requested_by_auth_user_id = auth.uid()) OR app.is_support_grant_authority(auth.uid(), tenant_id)))));

alter policy label_print_jobs_select_scoped on app.label_print_jobs
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy label_printers_select_scoped on app.label_printers
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy label_template_versions_select_scoped on app.label_template_versions
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy label_templates_select_scoped on app.label_templates
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy margin_rule_versions_select_scoped on app.margin_rule_versions
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy master_records_select_scoped on app.master_records
  using (((tenant_id IS NULL) OR (app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy milestone_template_versions_select_scoped on app.milestone_template_versions
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy numbering_allocations_select_scoped on app.numbering_allocations
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy org_units_select_own_tenant on app.org_units
  using ((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)));

alter policy pipeline_categories_select_scoped on app.pipeline_categories
  using ((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)));

alter policy principal_memberships_select_own_tenant on app.principal_memberships
  using ((((tenant_id IS NULL) AND (auth_user_id = auth.uid())) OR ((tenant_id IS NOT NULL) AND (app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)))));

alter policy provider_vehicle_mappings_select_scoped on app.provider_vehicle_mappings
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy quotation_approval_rules_select_scoped on app.quotation_approval_rules
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy report_runs_select_scoped on app.report_runs
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy role_assignments_select_own_tenant on app.role_assignments
  using ((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)));

alter policy role_versions_select_own_tenant on app.role_versions
  using ((EXISTS ( SELECT 1 FROM app.roles r WHERE ((r.id = role_versions.role_id) AND (app.has_active_tenant_membership(r.tenant_id) AND NOT app.actor_holds_customer_user_layer(r.tenant_id))))));

alter policy roles_select_own_tenant on app.roles
  using ((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)));

alter policy sim_cards_select_scoped on app.sim_cards
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy tenant_entitlement_overrides_select_own_tenant on app.tenant_entitlement_overrides
  using ((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)));

alter policy tenant_entitlements_select_own_tenant on app.tenant_entitlements
  using ((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)));

alter policy tenant_tracking_source_policies_select_scoped on app.tenant_tracking_source_policies
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy tenant_user_identities_select_own_tenant on app.tenant_user_identities
  using ((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)));

alter policy tenants_select_own_tenant on app.tenants
  using ((app.has_active_tenant_membership(id) AND NOT app.actor_holds_customer_user_layer(id)));

alter policy third_party_provider_connections_select_scoped on app.third_party_provider_connections
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy third_party_telemetry_reports_select_scoped on app.third_party_telemetry_reports
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy users_select_own_tenant on app.users
  using ((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)));

alter policy vehicle_capacity_reservations_select_scoped on app.vehicle_capacity_reservations
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy vehicle_current_positions_select_scoped on app.vehicle_current_positions
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy vehicle_operational_profiles_select_scoped on app.vehicle_operational_profiles
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy vehicle_source_health_select_scoped on app.vehicle_source_health
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy vehicle_source_switches_select_scoped on app.vehicle_source_switches
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy vehicle_tracking_source_priorities_select_scoped on app.vehicle_tracking_source_priorities
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy vendor_rate_versions_select_scoped on app.vendor_rate_versions
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy warehouse_billing_rate_components_select_scoped on app.warehouse_billing_rate_components
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));

alter policy win_loss_reasons_select_scoped on app.win_loss_reasons
  using ((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)));

alter policy workflow_instances_select_scoped on app.workflow_instances
  using (((app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()));
