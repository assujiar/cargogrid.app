-- Real, executable test evidence for CG-AUDIT-2026-09-02 UNTRACKED-F-tenant-index
-- (batch 2, closing the item) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Directly queries pg_class/pg_attribute/pg_index
-- (the same mechanism used to personally re-verify the finding before writing
-- the migration) to prove every one of the remaining 91 named tables now has a
-- real index whose leading column is tenant_id, and that the schema-wide gap
-- this backlog item tracked is now genuinely zero.

\set ON_ERROR_STOP on

\echo '>> UNTRACKED-F-tenant-index batch 2: all 91 remaining tables now each have an index leading on tenant_id'
do $$
declare
  v_table text;
  v_has_leading_tenant_index boolean;
  v_tables text[] := array[
    'application_stage_history',
    'attendance_policy_versions',
    'candidate_duplicate_candidates',
    'contact_links',
    'costing_request_components',
    'costing_response_components',
    'costing_responses',
    'credit_profile_overrides',
    'customer_contract_price_components',
    'customer_portal_account_membership_history',
    'customer_portal_booking_request_history',
    'document_checklist_events',
    'employee_duplicate_candidates',
    'employee_emergency_contacts',
    'employee_lifecycle_events',
    'eta_prediction_evaluations',
    'file_scan_corrections',
    'finance_exchange_rates',
    'finance_period_lock_events',
    'finance_period_transitions',
    'finance_receipt_allocations',
    'finance_reconciliation_exceptions',
    'finance_settlement_allocations',
    'finance_tax_rule_versions',
    'forecast_job_evaluations',
    'forecast_job_feedback',
    'forecast_snapshots',
    'import_staging_rows',
    'interview_feedback',
    'interview_interviewers',
    'job_offer_versions',
    'job_order_overrides',
    'job_vacancy_lifecycle_events',
    'kb_ticket_article_links',
    'leave_type_policy_versions',
    'margin_calculations',
    'master_records',
    'onboarding_case_events',
    'onboarding_case_task_dependencies',
    'onboarding_checklist_template_task_dependencies',
    'onboarding_checklist_template_tasks',
    'onboarding_task_provisioning_requests',
    'opportunity_stage_history',
    'org_unit_history',
    'overtime_policy_versions',
    'payroll_finance_handoff_gl_lines',
    'payroll_finance_handoff_payment_instructions',
    'performance_assessment_kpi_scores',
    'performance_calibration_adjustments',
    'performance_goal_progress_entries',
    'performance_template_kpi_items',
    'principal_membership_history',
    'purchase_order_events',
    'quotation_lines',
    'rate_selections',
    'rfq_clarifications',
    'rfq_events',
    'rfq_requirement_lines',
    'rfq_response_attachments',
    'risk_signal_actions',
    'risk_signal_reviews',
    'role_lifecycle_history',
    'roster_cycle_slots',
    'scaling_recommendations',
    'scheduled_task_runs',
    'shift_segments',
    'shift_template_versions',
    'shipment_milestone_projections',
    'sla_calendar_versions',
    'sourcing_request_events',
    'ticket_escalation_levels',
    'ticket_escalation_suppressions',
    'ticket_sla_clock_events',
    'training_development_plan_actions',
    'user_lifecycle_history',
    'vehicle_source_health',
    'vehicle_source_switches',
    'vendor_addresses',
    'vendor_assessment_answers',
    'vendor_assessment_corrective_actions',
    'vendor_assessment_findings',
    'vendor_assessment_template_criteria',
    'vendor_bill_match_events',
    'vendor_capacity_blackouts',
    'vendor_contacts',
    'vendor_contract_events',
    'vendor_coverage',
    'vendor_duplicate_candidates',
    'vendor_kpi_scorecard_lines',
    'vendor_profile_lifecycle_events',
    'vendor_services'
  ];
begin
  if array_length(v_tables, 1) <> 91 then
    raise exception 'assertion failed: expected exactly 91 tables in this batch''s own fixture list, got %', array_length(v_tables, 1);
  end if;

  foreach v_table in array v_tables
  loop
    select exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid and a.attname = 'tenant_id' and a.attnum > 0 and not a.attisdropped
      join pg_index i on i.indrelid = c.oid and i.indkey[0] = a.attnum
      where n.nspname = 'app' and c.relname = v_table
    ) into v_has_leading_tenant_index;

    if not v_has_leading_tenant_index then
      raise exception 'assertion failed: expected app.% to now carry an index leading on tenant_id, found none', v_table;
    end if;
  end loop;
end;
$$;

\echo '>> UNTRACKED-F-tenant-index: the schema-wide gap this backlog item tracked (99 tables, 2026-09-02) is now genuinely zero -- every app.* table with a tenant_id column carries an index leading on it'
do $$
declare
  v_still_missing integer;
begin
  select count(*) into v_still_missing
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attname = 'tenant_id' and a.attnum > 0 and not a.attisdropped
  where n.nspname = 'app' and c.relkind = 'r'
    and not exists (
      select 1 from pg_index i where i.indrelid = c.oid and i.indkey[0] = a.attnum
    );

  if v_still_missing <> 0 then
    raise exception 'assertion failed: expected zero tenant-scoped tables still missing a leading tenant_id index after batch 1 + batch 2, got %', v_still_missing;
  end if;
end;
$$;

\echo 'ALL CG-AUDIT-2026-09-02 UNTRACKED-F-tenant-index (batch 2, item CLOSED) db-test assertions passed.'
