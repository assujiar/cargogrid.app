-- ISS-2026-300 reconciliation for project awdlicmwzdxquopwtcfd.
--
-- Metadata-only. Rewrites supabase_migrations.schema_migrations so every applied migration is
-- recorded under its repository filename version and name -- exactly what `supabase db push`
-- would have written had it been the tool that applied them. Touches no schema and no
-- application data.
--
-- WHY: the MCP apply_migration tool stamps its own wall-clock version instead of reading the
-- file's filename-embedded timestamp. ISS-2026-300 recorded this as affecting 9 rows. It is
-- actually 84: that many repository migrations are absent from the ledger under their own
-- version, and `supabase db push` would therefore try to re-run all of them -- non-idempotent
-- DDL (create function, alter table add column, drop function) against an already-migrated
-- schema.
--
-- VERIFIED BEFORE GENERATION:
--   * every row below maps to exactly one repository file (no ambiguity);
--   * no target version already exists in the ledger (no primary-key collision);
--   * the set of targets equals the set of repo versions missing from the ledger, exactly.
--
-- NINE ROWS ARE DELIBERATELY LEFT ALONE. The live project applied three migrations in parts
-- (finance authority chain p1-p6, its tier-C completeness p1-p3, and two settlement-reversal
-- follow-ups) which the repository later carries consolidated into single files. The first
-- part of each group is remapped to the consolidated file; the remaining part-rows stay as
-- orphans. `supabase db push` ignores ledger rows with no matching repo file, and deleting
-- them would be a larger and less reversible action than the problem warrants.
--
-- REVERSIBLE: the pre-change state of every row below is (version, name) as given in the
-- `where` clause.

begin;

update supabase_migrations.schema_migrations
   set version = '20260810000000', name = 'harden_tenant_isolation_actor_identity_gaps'
 where version = '20260825042102' and name = 'harden_tenant_isolation_actor_identity_gaps';

update supabase_migrations.schema_migrations
   set version = '20260810100000', name = 'harden_tenant_isolation_actor_identity_gaps_round2'
 where version = '20260825042130' and name = 'harden_tenant_isolation_actor_identity_gaps_round2';

update supabase_migrations.schema_migrations
   set version = '20260810200000', name = 'harden_dashboard_actor_identity_gaps'
 where version = '20260825070306' and name = 'harden_dashboard_actor_identity_gaps';

update supabase_migrations.schema_migrations
   set version = '20260810300000', name = 'harden_rbac_evaluator_tenant_membership_check'
 where version = '20260825070326' and name = 'harden_rbac_evaluator_tenant_membership_check';

update supabase_migrations.schema_migrations
   set version = '20260810400000', name = 'harden_crm_ops_actor_identity_gaps'
 where version = '20260825070445' and name = 'harden_crm_ops_actor_identity_gaps';

update supabase_migrations.schema_migrations
   set version = '20260810500000', name = 'harden_own_row_rls_membership_gap'
 where version = '20260825070458' and name = 'harden_own_row_rls_membership_gap';

update supabase_migrations.schema_migrations
   set version = '20260810600000', name = 'harden_loyalty_redemption_maker_checker'
 where version = '20260825070526' and name = 'harden_loyalty_redemption_maker_checker';

update supabase_migrations.schema_migrations
   set version = '20260810700000', name = 'harden_finance_authority_chain_security_definer'
 where version = '20260825074015' and name = 'harden_finance_authority_chain_security_definer_p1';

update supabase_migrations.schema_migrations
   set version = '20260810800000', name = 'harden_finance_journal_view_gate_and_self_approval'
 where version = '20260825075036' and name = 'harden_finance_journal_view_gate_and_self_approval';

update supabase_migrations.schema_migrations
   set version = '20260810900000', name = 'harden_finance_authority_chain_tierc_completeness'
 where version = '20260825075236' and name = 'harden_finance_authority_chain_tierc_completeness_p1';

update supabase_migrations.schema_migrations
   set version = '20260811000000', name = 'harden_financial_integrity_invoicing_and_idempotency'
 where version = '20260825042444' and name = 'harden_financial_integrity_invoicing_and_idempotency';

update supabase_migrations.schema_migrations
   set version = '20260811100000', name = 'harden_finance_period_lock_idempotency_race'
 where version = '20260825075606' and name = 'harden_finance_period_lock_idempotency_race';

update supabase_migrations.schema_migrations
   set version = '20260811200000', name = 'harden_financial_integrity_tierc_fixes'
 where version = '20260825075724' and name = 'harden_financial_integrity_tierc_fixes';

update supabase_migrations.schema_migrations
   set version = '20260812000000', name = 'harden_data_lineage_audit_findings'
 where version = '20260825042546' and name = 'harden_data_lineage_audit_findings';

update supabase_migrations.schema_migrations
   set version = '20260813000000', name = 'harden_api_compatibility_audit_findings'
 where version = '20260825042602' and name = 'harden_api_compatibility_audit_findings';

update supabase_migrations.schema_migrations
   set version = '20260813100000', name = 'harden_api_compatibility_audit_tierc_fixes'
 where version = '20260825042613' and name = 'harden_api_compatibility_audit_tierc_fixes';

update supabase_migrations.schema_migrations
   set version = '20260814000000', name = 'harden_storage_signed_url_audit_findings'
 where version = '20260825042708' and name = 'harden_storage_signed_url_audit_findings';

update supabase_migrations.schema_migrations
   set version = '20260814100000', name = 'harden_storage_signed_url_audit_tierc_fixes'
 where version = '20260825043150' and name = 'harden_storage_signed_url_audit_tierc_fixes';

update supabase_migrations.schema_migrations
   set version = '20260815000000', name = 'harden_ip_restriction_iss150_closure_wiring'
 where version = '20260825043237' and name = 'harden_ip_restriction_iss150_closure_wiring';

update supabase_migrations.schema_migrations
   set version = '20260815200000', name = 'harden_relocate_pg_trgm_btree_gist_out_of_public'
 where version = '20260825043302' and name = 'harden_relocate_pg_trgm_btree_gist_out_of_public';

update supabase_migrations.schema_migrations
   set version = '20260815300000', name = 'harden_token_hash_column_privilege_iss232_closure'
 where version = '20260825043312' and name = 'harden_token_hash_column_privilege_iss232_closure';

update supabase_migrations.schema_migrations
   set version = '20260815400000', name = 'harden_ip_restriction_tierc_fixes'
 where version = '20260825043347' and name = 'harden_ip_restriction_tierc_fixes';

update supabase_migrations.schema_migrations
   set version = '20260816000000', name = 'harden_observability_audit_findings'
 where version = '20260825043404' and name = 'harden_observability_audit_findings';

update supabase_migrations.schema_migrations
   set version = '20260817000000', name = 'harden_employee_import_duplicate_swallow'
 where version = '20260825043431' and name = 'harden_employee_import_duplicate_swallow';

update supabase_migrations.schema_migrations
   set version = '20260818000000', name = 'harden_integrated_verification_legal_hold_bridge'
 where version = '20260825043458' and name = 'harden_integrated_verification_legal_hold_bridge';

update supabase_migrations.schema_migrations
   set version = '20260818100000', name = 'harden_integrated_verification_tierc_fixes'
 where version = '20260825043517' and name = 'harden_integrated_verification_tierc_fixes';

update supabase_migrations.schema_migrations
   set version = '20260819000000', name = 'harden_release_blocker_triage_remediation'
 where version = '20260825043715' and name = 'harden_release_blocker_triage_remediation';

update supabase_migrations.schema_migrations
   set version = '20260826000000', name = 'create_public_api_data_wrappers'
 where version = '20260825044733' and name = 'create_public_api_data_wrappers';

update supabase_migrations.schema_migrations
   set version = '20260826010000', name = 'harden_public_api_data_wrappers_tierc_fixes'
 where version = '20260825050021' and name = 'harden_public_api_data_wrappers_tierc_fixes';

update supabase_migrations.schema_migrations
   set version = '20260826020000', name = 'harden_vendor_kpi_rate_validity_window_calc'
 where version = '20260825062542' and name = 'harden_vendor_kpi_rate_validity_window_calc';

update supabase_migrations.schema_migrations
   set version = '20260826030000', name = 'harden_finance_settlement_reversal_gl_journal_and_reachability'
 where version = '20260825094848' and name = 'harden_finance_settlement_reversal_gl_journal_and_reachability';

update supabase_migrations.schema_migrations
   set version = '20260826040000', name = 'harden_rbac_evaluator_platform_user_status_check'
 where version = '20260825122556' and name = 'harden_rbac_evaluator_platform_user_status_check';

update supabase_migrations.schema_migrations
   set version = '20260826050000', name = 'harden_integration_secrets_encryption_at_rest'
 where version = '20260825124834' and name = 'harden_integration_secrets_encryption_at_rest';

update supabase_migrations.schema_migrations
   set version = '20260826060000', name = 'harden_database_restore_audit_trail'
 where version = '20260825130529' and name = 'harden_database_restore_audit_trail';

update supabase_migrations.schema_migrations
   set version = '20260826070000', name = 'harden_employee_import_duplicate_detection'
 where version = '20260825131629' and name = 'harden_employee_import_duplicate_detection';

update supabase_migrations.schema_migrations
   set version = '20260826080000', name = 'harden_restore_security_state_reconciliation'
 where version = '20260825134216' and name = 'harden_restore_security_state_reconciliation';

update supabase_migrations.schema_migrations
   set version = '20260826081000', name = 'harden_record_database_restore_event_wrapper_grant_leak'
 where version = '20260825132238' and name = 'harden_record_database_restore_event_wrapper_grant_leak';

update supabase_migrations.schema_migrations
   set version = '20260826090000', name = 'harden_security_state_snapshots_table_privilege_leak'
 where version = '20260825134329' and name = 'harden_security_state_snapshots_table_privilege_leak';

update supabase_migrations.schema_migrations
   set version = '20260826100000', name = 'harden_user_status_transition_invalid_event_type'
 where version = '20260825135736' and name = 'harden_user_status_transition_invalid_event_type';

update supabase_migrations.schema_migrations
   set version = '20260826110000', name = 'harden_evaluate_permission_session_revocation_enforcement'
 where version = '20260826001823' and name = 'harden_evaluate_permission_session_revocation_enforcement';

update supabase_migrations.schema_migrations
   set version = '20260826120000', name = 'harden_restore_materialized_view_refresh_completeness'
 where version = '20260826002939' and name = 'harden_restore_materialized_view_refresh_completeness';

update supabase_migrations.schema_migrations
   set version = '20260826130000', name = 'create_reference_data_import_registration'
 where version = '20260826010519' and name = 'create_reference_data_import_registration';

update supabase_migrations.schema_migrations
   set version = '20260826140000', name = 'create_migration_rehearsal_tracking'
 where version = '20260826011753' and name = 'create_migration_rehearsal_tracking';

update supabase_migrations.schema_migrations
   set version = '20260826150000', name = 'create_employee_import_rollback'
 where version = '20260827013003' and name = 'create_employee_import_rollback';

update supabase_migrations.schema_migrations
   set version = '20260826160000', name = 'create_finance_journal_historical_import'
 where version = '20260827032922' and name = 'create_finance_journal_historical_import';

update supabase_migrations.schema_migrations
   set version = '20260826170000', name = 'harden_employee_import_number_normalization_detection'
 where version = '20260827034055' and name = 'harden_employee_import_number_normalization_detection';

update supabase_migrations.schema_migrations
   set version = '20260826180000', name = 'create_dr_restore_scenario_taxonomy'
 where version = '20260827065222' and name = 'create_dr_restore_scenario_taxonomy';

update supabase_migrations.schema_migrations
   set version = '20260826190000', name = 'harden_import_commit_ip_allowlist_gating'
 where version = '20260827101725' and name = 'harden_import_commit_ip_allowlist_gating';

update supabase_migrations.schema_migrations
   set version = '20260827000000', name = 'wire_observability_alert_producers'
 where version = '20260827131115' and name = 'wire_observability_alert_producers';

update supabase_migrations.schema_migrations
   set version = '20260827010000', name = 'harden_cross_tenant_error_disclosure_representative'
 where version = '20260827131209' and name = 'harden_cross_tenant_error_disclosure_representative';

update supabase_migrations.schema_migrations
   set version = '20260827030000', name = 'harden_analytics_refresh_runs_grant'
 where version = '20260827131227' and name = 'harden_analytics_refresh_runs_grant';

update supabase_migrations.schema_migrations
   set version = '20260827110000', name = 'harden_request_approval_unique_violation_handler'
 where version = '20260827144848' and name = 'harden_request_approval_unique_violation_handler';

update supabase_migrations.schema_migrations
   set version = '20260827130000', name = 'harden_tenant_disclosure_representative_extension_batch2'
 where version = '20260827145007' and name = 'harden_tenant_disclosure_representative_extension_batch2';

update supabase_migrations.schema_migrations
   set version = '20260827140000', name = 'harden_customer_portal_invoice_account_id_projection_iss2026124'
 where version = '20260828015303' and name = 'harden_customer_portal_invoice_account_id_projection_iss2026124';

update supabase_migrations.schema_migrations
   set version = '20260828000000', name = 'create_loyalty_point_program_expiry_config'
 where version = '20260828015346' and name = 'create_loyalty_point_program_expiry_config';

update supabase_migrations.schema_migrations
   set version = '20260828030000', name = 'harden_customer_portal_membership_anti_enumeration'
 where version = '20260828015420' and name = 'harden_customer_portal_membership_anti_enumeration';

update supabase_migrations.schema_migrations
   set version = '20260828040000', name = 'harden_advanced_tms_customer_inventory_access_actor_identity'
 where version = '20260828015535' and name = 'harden_advanced_tms_customer_inventory_access_actor_identity';

update supabase_migrations.schema_migrations
   set version = '20260828050000', name = 'harden_customer_portal_loyalty_fraud_review_case_self_approval'
 where version = '20260828015610' and name = 'harden_customer_portal_loyalty_fraud_review_case_self_approval';

update supabase_migrations.schema_migrations
   set version = '20260828060000', name = 'harden_customer_portal_loyalty_tier_movements_supreme_admin_override'
 where version = '20260828015620' and name = 'harden_customer_portal_loyalty_tier_movements_supreme_admin_override';

update supabase_migrations.schema_migrations
   set version = '20260828070000', name = 'harden_customer_portal_loyalty_liability_reward_internal_cost_missing_exception'
 where version = '20260828015701' and name = 'harden_customer_portal_loyalty_liability_reward_internal_cost_missing_exception';

update supabase_migrations.schema_migrations
   set version = '20260828090000', name = 'harden_ai_governed_action_region_capability_consult'
 where version = '20260828032642' and name = 'harden_ai_governed_action_region_capability_consult';

update supabase_migrations.schema_migrations
   set version = '20260828100000', name = 'harden_enterprise_idp_domain_lookup_rate_limit'
 where version = '20260828032657' and name = 'harden_enterprise_idp_domain_lookup_rate_limit';

update supabase_migrations.schema_migrations
   set version = '20260828110000', name = 'harden_support_session_gates_active_grant'
 where version = '20260828041219' and name = 'harden_support_session_gates_active_grant';

update supabase_migrations.schema_migrations
   set version = '20260828111000', name = 'harden_support_session_open_audit_trail'
 where version = '20260828041247' and name = 'harden_support_session_open_audit_trail';

update supabase_migrations.schema_migrations
   set version = '20260828121000', name = 'harden_shared_record_scope_primitives_actor_identity'
 where version = '20260828041335' and name = 'harden_shared_record_scope_primitives_actor_identity';

update supabase_migrations.schema_migrations
   set version = '20260828140000', name = 'harden_customer_ticket_links_entity_id_registry_redaction'
 where version = '20260828041404' and name = 'harden_customer_ticket_links_entity_id_registry_redaction';

update supabase_migrations.schema_migrations
   set version = '20260828150000', name = 'harden_job_order_snapshot_source_lineage'
 where version = '20260828051421' and name = 'harden_job_order_snapshot_source_lineage';

update supabase_migrations.schema_migrations
   set version = '20260828151000', name = 'harden_inventory_movement_reservation_source_lineage'
 where version = '20260828051441' and name = 'harden_inventory_movement_reservation_source_lineage';

update supabase_migrations.schema_migrations
   set version = '20260828160000', name = 'harden_self_approval_null_actor_fail_open'
 where version = '20260828051619' and name = 'harden_self_approval_null_actor_fail_open';

update supabase_migrations.schema_migrations
   set version = '20260828171000', name = 'harden_vendor_evidence_reviewer_record_scope'
 where version = '20260828051710' and name = 'harden_vendor_evidence_reviewer_record_scope';

update supabase_migrations.schema_migrations
   set version = '20260828173000', name = 'harden_files_malware_scan_raw_correction_audit'
 where version = '20260828051730' and name = 'harden_files_malware_scan_raw_correction_audit';

update supabase_migrations.schema_migrations
   set version = '20260828193000', name = 'harden_customer_portal_last_account_admin_status_guard'
 where version = '20260828075307' and name = 'harden_customer_portal_last_account_admin_status_guard';

update supabase_migrations.schema_migrations
   set version = '20260828200000', name = 'create_raw_mutation_tripwire'
 where version = '20260828075334' and name = 'create_raw_mutation_tripwire';

update supabase_migrations.schema_migrations
   set version = '20260830100000', name = 'create_vendor_import_adapter'
 where version = '20260831002539' and name = '20260830100000_create_vendor_import_adapter';

update supabase_migrations.schema_migrations
   set version = '20260830110000', name = 'harden_evaluate_permission_step_up_enforcement'
 where version = '20260831002631' and name = '20260830110000_harden_evaluate_permission_step_up_enforcement';

update supabase_migrations.schema_migrations
   set version = '20260830120000', name = 'create_customer_and_item_import_adapters'
 where version = '20260831002852' and name = '20260830120000_create_customer_and_item_import_adapters';

update supabase_migrations.schema_migrations
   set version = '20260830130000', name = 'create_finance_opening_balance_import_and_gl_posting'
 where version = '20260831003055' and name = '20260830130000_create_finance_opening_balance_import_and_gl_posting';

update supabase_migrations.schema_migrations
   set version = '20260830140000', name = 'create_incident_communication'
 where version = '20260831003441' and name = 'create_incident_communication';

update supabase_migrations.schema_migrations
   set version = '20260830150000', name = 'create_incident_escalation_sweep'
 where version = '20260831003611' and name = 'create_incident_escalation_sweep';

update supabase_migrations.schema_migrations
   set version = '20260830160000', name = 'harden_approval_engine_audit_reason_redaction'
 where version = '20260831003706' and name = 'harden_approval_engine_audit_reason_redaction';

update supabase_migrations.schema_migrations
   set version = '20260830170000', name = 'create_durable_ip_access_evaluation'
 where version = '20260831003741' and name = 'create_durable_ip_access_evaluation';

update supabase_migrations.schema_migrations
   set version = '20260830180000', name = 'add_observability_alert_dedupe_discriminator'
 where version = '20260831003827' and name = 'add_observability_alert_dedupe_discriminator';

update supabase_migrations.schema_migrations
   set version = '20260830190000', name = 'harden_enqueue_job_idempotency_payload_tuple'
 where version = '20260831003923' and name = 'harden_enqueue_job_idempotency_payload_tuple';

update supabase_migrations.schema_migrations
   set version = '20260830200000', name = 'correct_public_wrapper_grant_parity'
 where version = '20260831004209' and name = 'correct_public_wrapper_grant_parity';

commit;
