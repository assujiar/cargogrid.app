-- CG-AUDIT-2026-09-02 UNTRACKED-F-tenant-index (batch 2 of 2, closes the item):
-- batch 1 (20260927000000_untracked_f_add_missing_tenant_id_indexes_batch1.sql)
-- closed the 8 tables the audit's own closing parenthetical to section F named
-- explicitly by name, disclosing the remaining 91 as a separate follow-up rather
-- than silently narrowing the finding. This migration closes that follow-up:
-- every one of the remaining 91 tenant-scoped tables that still lacked an index
-- leading on tenant_id, confirmed via the same live-schema query used to verify
-- batch 1 (pg_class/pg_attribute/pg_index against a fresh disposable database
-- with every migration applied, including batch 1 itself) -- the exact 91-table
-- list below is what that query returned, not a hand-compiled guess.
--
-- Same reasoning as batch 1, unchanged: this is a mechanical, purely additive
-- schema fix (plain single-column `(tenant_id)` indexes, matching
-- 20260907170000_fix_shipment_order_dispatch_double_scan_iss_f5.sql's own
-- established pattern), not a product/business decision. A composite index
-- tuned to any one table's own specific hot-query shape would be speculative
-- optimization ahead of a measured need (AGENTS.md's own performance rule); the
-- audit's own framing is a coverage gap ("lack ANY index leading on tenant_id"),
-- which a plain index closes directly. Confirmed for all 91 tables (grepping
-- every `create index ... on app.<table>` statement across all migrations)
-- that no existing index leads with tenant_id, so every new index here is
-- genuinely additive and non-overlapping with any prior index.
--
-- This closes the UNTRACKED-F-tenant-index backlog item in full: 8 (batch 1) +
-- 91 (this migration) = 99, the audit's own original count, confirmed still
-- exactly 99 as of batch 1's own re-verification and unchanged since (no other
-- migration between batch 1 and this one touched any of these 91 tables' own
-- indexes).

create index application_stage_history_tenant_idx on app.application_stage_history (tenant_id);
create index attendance_policy_versions_tenant_idx on app.attendance_policy_versions (tenant_id);
create index candidate_duplicate_candidates_tenant_idx on app.candidate_duplicate_candidates (tenant_id);
create index contact_links_tenant_idx on app.contact_links (tenant_id);
create index costing_request_components_tenant_idx on app.costing_request_components (tenant_id);
create index costing_response_components_tenant_idx on app.costing_response_components (tenant_id);
create index costing_responses_tenant_idx on app.costing_responses (tenant_id);
create index credit_profile_overrides_tenant_idx on app.credit_profile_overrides (tenant_id);
create index customer_contract_price_components_tenant_idx on app.customer_contract_price_components (tenant_id);
create index customer_portal_account_membership_history_tenant_idx on app.customer_portal_account_membership_history (tenant_id);
create index customer_portal_booking_request_history_tenant_idx on app.customer_portal_booking_request_history (tenant_id);
create index document_checklist_events_tenant_idx on app.document_checklist_events (tenant_id);
create index employee_duplicate_candidates_tenant_idx on app.employee_duplicate_candidates (tenant_id);
create index employee_emergency_contacts_tenant_idx on app.employee_emergency_contacts (tenant_id);
create index employee_lifecycle_events_tenant_idx on app.employee_lifecycle_events (tenant_id);
create index eta_prediction_evaluations_tenant_idx on app.eta_prediction_evaluations (tenant_id);
create index file_scan_corrections_tenant_idx on app.file_scan_corrections (tenant_id);
create index finance_exchange_rates_tenant_idx on app.finance_exchange_rates (tenant_id);
create index finance_period_lock_events_tenant_idx on app.finance_period_lock_events (tenant_id);
create index finance_period_transitions_tenant_idx on app.finance_period_transitions (tenant_id);
create index finance_receipt_allocations_tenant_idx on app.finance_receipt_allocations (tenant_id);
create index finance_reconciliation_exceptions_tenant_idx on app.finance_reconciliation_exceptions (tenant_id);
create index finance_settlement_allocations_tenant_idx on app.finance_settlement_allocations (tenant_id);
create index finance_tax_rule_versions_tenant_idx on app.finance_tax_rule_versions (tenant_id);
create index forecast_job_evaluations_tenant_idx on app.forecast_job_evaluations (tenant_id);
create index forecast_job_feedback_tenant_idx on app.forecast_job_feedback (tenant_id);
create index forecast_snapshots_tenant_idx on app.forecast_snapshots (tenant_id);
create index import_staging_rows_tenant_idx on app.import_staging_rows (tenant_id);
create index interview_feedback_tenant_idx on app.interview_feedback (tenant_id);
create index interview_interviewers_tenant_idx on app.interview_interviewers (tenant_id);
create index job_offer_versions_tenant_idx on app.job_offer_versions (tenant_id);
create index job_order_overrides_tenant_idx on app.job_order_overrides (tenant_id);
create index job_vacancy_lifecycle_events_tenant_idx on app.job_vacancy_lifecycle_events (tenant_id);
create index kb_ticket_article_links_tenant_idx on app.kb_ticket_article_links (tenant_id);
create index leave_type_policy_versions_tenant_idx on app.leave_type_policy_versions (tenant_id);
create index margin_calculations_tenant_idx on app.margin_calculations (tenant_id);
create index master_records_tenant_idx on app.master_records (tenant_id);
create index onboarding_case_events_tenant_idx on app.onboarding_case_events (tenant_id);
create index onboarding_case_task_dependencies_tenant_idx on app.onboarding_case_task_dependencies (tenant_id);
create index onboarding_checklist_template_task_dependencies_tenant_idx on app.onboarding_checklist_template_task_dependencies (tenant_id);
create index onboarding_checklist_template_tasks_tenant_idx on app.onboarding_checklist_template_tasks (tenant_id);
create index onboarding_task_provisioning_requests_tenant_idx on app.onboarding_task_provisioning_requests (tenant_id);
create index opportunity_stage_history_tenant_idx on app.opportunity_stage_history (tenant_id);
create index org_unit_history_tenant_idx on app.org_unit_history (tenant_id);
create index overtime_policy_versions_tenant_idx on app.overtime_policy_versions (tenant_id);
create index payroll_finance_handoff_gl_lines_tenant_idx on app.payroll_finance_handoff_gl_lines (tenant_id);
create index payroll_finance_handoff_payment_instructions_tenant_idx on app.payroll_finance_handoff_payment_instructions (tenant_id);
create index performance_assessment_kpi_scores_tenant_idx on app.performance_assessment_kpi_scores (tenant_id);
create index performance_calibration_adjustments_tenant_idx on app.performance_calibration_adjustments (tenant_id);
create index performance_goal_progress_entries_tenant_idx on app.performance_goal_progress_entries (tenant_id);
create index performance_template_kpi_items_tenant_idx on app.performance_template_kpi_items (tenant_id);
create index principal_membership_history_tenant_idx on app.principal_membership_history (tenant_id);
create index purchase_order_events_tenant_idx on app.purchase_order_events (tenant_id);
create index quotation_lines_tenant_idx on app.quotation_lines (tenant_id);
create index rate_selections_tenant_idx on app.rate_selections (tenant_id);
create index rfq_clarifications_tenant_idx on app.rfq_clarifications (tenant_id);
create index rfq_events_tenant_idx on app.rfq_events (tenant_id);
create index rfq_requirement_lines_tenant_idx on app.rfq_requirement_lines (tenant_id);
create index rfq_response_attachments_tenant_idx on app.rfq_response_attachments (tenant_id);
create index risk_signal_actions_tenant_idx on app.risk_signal_actions (tenant_id);
create index risk_signal_reviews_tenant_idx on app.risk_signal_reviews (tenant_id);
create index role_lifecycle_history_tenant_idx on app.role_lifecycle_history (tenant_id);
create index roster_cycle_slots_tenant_idx on app.roster_cycle_slots (tenant_id);
create index scaling_recommendations_tenant_idx on app.scaling_recommendations (tenant_id);
create index scheduled_task_runs_tenant_idx on app.scheduled_task_runs (tenant_id);
create index shift_segments_tenant_idx on app.shift_segments (tenant_id);
create index shift_template_versions_tenant_idx on app.shift_template_versions (tenant_id);
create index shipment_milestone_projections_tenant_idx on app.shipment_milestone_projections (tenant_id);
create index sla_calendar_versions_tenant_idx on app.sla_calendar_versions (tenant_id);
create index sourcing_request_events_tenant_idx on app.sourcing_request_events (tenant_id);
create index ticket_escalation_levels_tenant_idx on app.ticket_escalation_levels (tenant_id);
create index ticket_escalation_suppressions_tenant_idx on app.ticket_escalation_suppressions (tenant_id);
create index ticket_sla_clock_events_tenant_idx on app.ticket_sla_clock_events (tenant_id);
create index training_development_plan_actions_tenant_idx on app.training_development_plan_actions (tenant_id);
create index user_lifecycle_history_tenant_idx on app.user_lifecycle_history (tenant_id);
create index vehicle_source_health_tenant_idx on app.vehicle_source_health (tenant_id);
create index vehicle_source_switches_tenant_idx on app.vehicle_source_switches (tenant_id);
create index vendor_addresses_tenant_idx on app.vendor_addresses (tenant_id);
create index vendor_assessment_answers_tenant_idx on app.vendor_assessment_answers (tenant_id);
create index vendor_assessment_corrective_actions_tenant_idx on app.vendor_assessment_corrective_actions (tenant_id);
create index vendor_assessment_findings_tenant_idx on app.vendor_assessment_findings (tenant_id);
create index vendor_assessment_template_criteria_tenant_idx on app.vendor_assessment_template_criteria (tenant_id);
create index vendor_bill_match_events_tenant_idx on app.vendor_bill_match_events (tenant_id);
create index vendor_capacity_blackouts_tenant_idx on app.vendor_capacity_blackouts (tenant_id);
create index vendor_contacts_tenant_idx on app.vendor_contacts (tenant_id);
create index vendor_contract_events_tenant_idx on app.vendor_contract_events (tenant_id);
create index vendor_coverage_tenant_idx on app.vendor_coverage (tenant_id);
create index vendor_duplicate_candidates_tenant_idx on app.vendor_duplicate_candidates (tenant_id);
create index vendor_kpi_scorecard_lines_tenant_idx on app.vendor_kpi_scorecard_lines (tenant_id);
create index vendor_profile_lifecycle_events_tenant_idx on app.vendor_profile_lifecycle_events (tenant_id);
create index vendor_services_tenant_idx on app.vendor_services (tenant_id);
