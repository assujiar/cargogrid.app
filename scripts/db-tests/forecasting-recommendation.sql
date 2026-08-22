-- Real, executable test evidence for IAE-025 (Forecasting and
-- Recommendation Assistance, Prompt 353) -- run via `pnpm run db:test`
-- against a real, disposable Postgres database. Scoped to this
-- checkpoint's own additive migration
-- (supabase/migrations/20260806400000_create_intelligence_forecasting_recommendation.sql).
-- Fresh, distinctive tenant fixture (iaefc), fixture id range
-- 00000000-0000-0000-0000-000028xxxxxx.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaefc with a real openai_multimodal connection; admin1 (bootstrap, INTHUB:Configure), rep1 (AI:Create/View/Approve -- full, may see small-cohort detail), agent1 (AI:Create/View only -- no Approve, cohort-masked view), viewer1 (AI:View only); a second tenant (iaefc2) for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin1 uuid := '00000000-0000-0000-0000-000028000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000028000002';
  v_agent1 uuid := '00000000-0000-0000-0000-000028000003';
  v_viewer1 uuid := '00000000-0000-0000-0000-000028000004';
  v_admin2 uuid := '00000000-0000-0000-0000-000028000005';
  v_admin1_role uuid;
  v_admin1_draft app.role_versions;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_agent_role uuid;
  v_agent_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_admin2_role uuid;
  v_admin2_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_admin1, 'admin@iaefc.test'),
    (v_rep1, 'rep@iaefc.test'),
    (v_agent1, 'agent@iaefc.test'),
    (v_viewer1, 'viewer@iaefc.test'),
    (v_admin2, 'admin@iaefc2.test');

  perform app.provision_tenant('iaefc', 'IaeFc Co', 'idem-iaefc', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaefc');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('iaefc2', 'IaeFc Co 2', 'idem-iaefc2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaefc2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaefc.test', 'IaeFc Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaefc.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  v_admin1_role := (app.create_role(v_tenant1, 'IaeFc Bootstrap Admin', 'INTHUB:Configure -- fixture bootstrap only', 'tester')).id;
  v_admin1_draft := app.create_role_version(v_admin1_role, 'tester');
  perform app.set_role_version_permissions(v_admin1_draft.id, array(select id from app.permissions where resource_module_code = 'INTHUB' and action = 'Configure'), 'tester');
  perform app.publish_role_version(v_admin1_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin1_role and status = 'published'), v_admin1, v_admin1, 'admin');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaefc.test', 'IaeFc Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaefc.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_agent1, 'agent@iaefc.test', 'IaeFc Agent', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'agent@iaefc.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaefc.test', 'IaeFc Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaefc.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'IaeFc Rep', 'AI:Create/View/Approve -- full, may see small-cohort detail', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(v_rep_draft.id, array(select id from app.permissions where resource_module_code = 'AI' and action in ('Create', 'View', 'Approve')), 'tester');
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), v_rep1, v_admin1, 'admin');

  v_agent_role := (app.create_role(v_tenant1, 'IaeFc Agent', 'AI:Create/View only -- no Approve, cohort-masked view', 'tester')).id;
  v_agent_draft := app.create_role_version(v_agent_role, 'tester');
  perform app.set_role_version_permissions(v_agent_draft.id, array(select id from app.permissions where resource_module_code = 'AI' and action in ('Create', 'View')), 'tester');
  perform app.publish_role_version(v_agent_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_agent_role and status = 'published'), v_agent1, v_admin1, 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'IaeFc Viewer', 'AI:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'AI' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_admin1, 'admin');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaefc2.test', 'IaeFc2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaefc2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');
  v_admin2_role := (app.create_role(v_tenant2, 'IaeFc2 Admin', 'AI:Create/View/Approve + INTHUB:Configure -- tenant2 cross-check probe actor', 'tester')).id;
  v_admin2_draft := app.create_role_version(v_admin2_role, 'tester');
  perform app.set_role_version_permissions(v_admin2_draft.id, array(select id from app.permissions where (resource_module_code = 'AI' and action in ('Create', 'View', 'Approve')) or (resource_module_code = 'INTHUB' and action = 'Configure')), 'tester');
  perform app.publish_role_version(v_admin2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_admin2, 'admin2');

  perform app.create_integration_connection(v_tenant1, 'openai_multimodal', 'OpenAI Multimodal', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://ai.iaefc-provider.test/v1/infer'), 'test-ai-secret', v_admin1, 'admin');
end $$;

\echo '>> app.request_forecast_job: insufficient_authority for a view-only actor; invalid forecast_type/horizon rejected; a real success creates a pending row; idempotent replay; conflicting replay rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaefc');
  v_rep1 uuid := '00000000-0000-0000-0000-000028000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000028000004';
  v_job1 app.forecast_jobs;
  v_job2 app.forecast_jobs;
begin
  begin
    perform app.request_forecast_job(v_tenant1, 'demand', 'baseline', jsonb_build_object('segment', 'jkt-fcl'), jsonb_build_object('history_weeks', 26), 90, 'idem-viewer-attempt', v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a view-only actor';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.request_forecast_job(v_tenant1, 'not_a_real_type', 'baseline', jsonb_build_object('x', 1), jsonb_build_object('y', 1), 90, 'idem-badtype-attempt', v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_invalid_type for an unrecognized forecast_type';
  exception when others then
    if sqlerrm not like 'forecast_job_invalid_type%' then raise; end if;
  end;

  begin
    perform app.request_forecast_job(v_tenant1, 'demand', 'baseline', jsonb_build_object('x', 1), jsonb_build_object('y', 1), 0, 'idem-badhorizon-attempt', v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_invalid_horizon for a zero horizon';
  exception when others then
    if sqlerrm not like 'forecast_job_invalid_horizon%' then raise; end if;
  end;

  begin
    perform app.request_forecast_job(v_tenant1, 'demand', 'baseline', jsonb_build_object('x', 1), jsonb_build_object('y', 1), 5000, 'idem-toolonghorizon-attempt', v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_invalid_horizon for a horizon beyond 1095 days';
  exception when others then
    if sqlerrm not like 'forecast_job_invalid_horizon%' then raise; end if;
  end;

  v_job1 := app.request_forecast_job(v_tenant1, 'demand', 'optimistic', jsonb_build_object('segment', 'jkt-fcl'), jsonb_build_object('history_weeks', 26), 90, 'idem-fc-real', v_rep1, 'rep');
  if v_job1.status <> 'pending' or v_job1.forecast_type <> 'demand' or v_job1.scenario_label <> 'optimistic' then
    raise exception 'assertion failed: expected a real pending job row, got %', to_jsonb(v_job1);
  end if;

  v_job2 := app.request_forecast_job(v_tenant1, 'demand', 'optimistic', jsonb_build_object('segment', 'jkt-fcl'), jsonb_build_object('history_weeks', 26), 90, 'idem-fc-real', v_rep1, 'rep');
  if v_job2.id <> v_job1.id then
    raise exception 'assertion failed: expected the idempotent retry to return the SAME job id, got % vs %', v_job1.id, v_job2.id;
  end if;

  begin
    perform app.request_forecast_job(v_tenant1, 'revenue', 'baseline', jsonb_build_object('x', 1), jsonb_build_object('y', 1), 30, 'idem-fc-real', v_rep1, 'rep');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key with a different forecast_type';
  exception when others then
    if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- Default scenario_label when none is supplied.
  perform app.request_forecast_job(v_tenant1, 'revenue', '', jsonb_build_object('x', 1), jsonb_build_object('y', 1), 30, 'idem-fc-default-label', v_rep1, 'rep');
  if (select scenario_label from app.forecast_jobs where tenant_id = v_tenant1 and idempotency_key = 'idem-fc-default-label') <> 'baseline' then
    raise exception 'assertion failed: expected an empty scenario_label to default to baseline';
  end if;

  raise notice 'PASS: request_forecast_job enforces authority, type/horizon validation, tenant scoping, is idempotent, and defaults scenario_label';
end $$;

\echo '>> app.record_forecast_job_outcome: insufficient_authority; not found; wrong feature; null-correlation and wrong-job-correlation regressions (IS DISTINCT FROM); tenant mismatch; still-pending request rejected; a real success extracts predicted_value/cohort_size; small cohort (<10) sets is_small_cohort_suppressed; insufficientData routes to a real insufficient_data status with a data_quality_note, never a fabricated predicted_value; idempotent replay; conflicting replay rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaefc');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaefc2');
  v_rep1 uuid := '00000000-0000-0000-0000-000028000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000028000004';
  v_admin2 uuid := '00000000-0000-0000-0000-000028000005';
  v_connection1 uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_job app.forecast_jobs;
  v_wrong_feature_request app.ai_governed_requests;
  v_null_correlation_request app.ai_governed_requests;
  v_wrong_job_request app.ai_governed_requests;
  v_pending_request app.ai_governed_requests;
  v_cross_tenant_request app.ai_governed_requests;
  v_ok_request app.ai_governed_requests;
  v_small_cohort_job app.forecast_jobs;
  v_small_cohort_request app.ai_governed_requests;
  v_insufficient_job app.forecast_jobs;
  v_insufficient_request app.ai_governed_requests;
  v_malformed_bool_job app.forecast_jobs;
  v_malformed_bool_request app.ai_governed_requests;
  v_row1 app.forecast_jobs;
  v_row2 app.forecast_jobs;
begin
  select * into v_job from app.forecast_jobs where tenant_id = v_tenant1 and status = 'pending' and forecast_type = 'demand' order by created_at asc limit 1;

  begin
    perform app.record_forecast_job_outcome(v_job.id, gen_random_uuid(), v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a view-only actor';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.record_forecast_job_outcome('00000000-0000-0000-0000-999999999999', gen_random_uuid(), v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_not_found for a bogus job id';
  exception when others then
    if sqlerrm not like 'forecast_job_not_found%' then raise; end if;
  end;

  v_wrong_feature_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'geocode_address', null, null, jsonb_build_object('address', 'Jl. Sudirman'), v_rep1, 'rep');
  v_wrong_feature_request := app.record_ai_governed_request_outcome(v_wrong_feature_request.id, 'succeeded', jsonb_build_object('lat', -6.2), 'high', 'openai-multimodal', 0.01, 'USD', null, v_rep1, 'rep');
  begin
    perform app.record_forecast_job_outcome(v_job.id, v_wrong_feature_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_wrong_feature for a geocode_address request';
  exception when others then
    if sqlerrm not like 'forecast_job_wrong_feature%' then raise; end if;
  end;

  v_null_correlation_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'forecasting_recommendation', null, null, jsonb_build_object('probe', true), v_rep1, 'rep');
  v_null_correlation_request := app.record_ai_governed_request_outcome(v_null_correlation_request.id, 'succeeded', jsonb_build_object('predictedValue', 1000), 'high', 'openai-multimodal', 0.02, 'USD', null, v_rep1, 'rep');
  begin
    perform app.record_forecast_job_outcome(v_job.id, v_null_correlation_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_correlation_mismatch for a request with null correlation';
  exception when others then
    if sqlerrm not like 'forecast_job_correlation_mismatch%' then raise; end if;
  end;

  v_wrong_job_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'forecasting_recommendation', 'forecast_job', gen_random_uuid(), jsonb_build_object('probe', true), v_rep1, 'rep');
  v_wrong_job_request := app.record_ai_governed_request_outcome(v_wrong_job_request.id, 'succeeded', jsonb_build_object('predictedValue', 1000), 'high', 'openai-multimodal', 0.02, 'USD', null, v_rep1, 'rep');
  begin
    perform app.record_forecast_job_outcome(v_job.id, v_wrong_job_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_correlation_mismatch for a request correlated to a DIFFERENT job';
  exception when others then
    if sqlerrm not like 'forecast_job_correlation_mismatch%' then raise; end if;
  end;

  perform app.create_integration_connection(v_tenant2, 'openai_multimodal', 'OpenAI Multimodal', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://ai.iaefc2-provider.test/v1/infer'), 'test-ai-secret', v_admin2, 'admin2');
  v_cross_tenant_request := app.request_ai_governed_action(v_tenant2, (select id from app.integration_connections where tenant_id = v_tenant2 and adapter_code = 'openai_multimodal'), 'forecasting_recommendation', 'forecast_job', v_job.id, jsonb_build_object('probe', true), v_admin2, 'admin2');
  v_cross_tenant_request := app.record_ai_governed_request_outcome(v_cross_tenant_request.id, 'succeeded', jsonb_build_object('predictedValue', 1000), 'high', 'openai-multimodal', 0.02, 'USD', null, v_admin2, 'admin2');
  begin
    perform app.record_forecast_job_outcome(v_job.id, v_cross_tenant_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_request_tenant_mismatch for a tenant2-owned request';
  exception when others then
    if sqlerrm not like 'forecast_job_request_tenant_mismatch%' then raise; end if;
  end;

  v_pending_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'forecasting_recommendation', 'forecast_job', v_job.id, jsonb_build_object('probe', true), v_rep1, 'rep');
  begin
    perform app.record_forecast_job_outcome(v_job.id, v_pending_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_request_not_completed for a still-pending request';
  exception when others then
    if sqlerrm not like 'forecast_job_request_not_completed%' then raise; end if;
  end;

  v_ok_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'forecasting_recommendation', 'forecast_job', v_job.id, jsonb_build_object('history_weeks', 26), v_rep1, 'rep');
  v_ok_request := app.record_ai_governed_request_outcome(v_ok_request.id, 'succeeded', jsonb_build_object('predictedValue', 48000, 'cohortSize', 250, 'customerNames', jsonb_build_array('Acme', 'Contoso')), 'high', 'openai-multimodal', 0.03, 'USD', null, v_rep1, 'rep');
  v_row1 := app.record_forecast_job_outcome(v_job.id, v_ok_request.id, v_rep1, 'rep');
  if v_row1.status <> 'succeeded' or v_row1.predicted_value <> 48000 or v_row1.cohort_size <> 250 or v_row1.is_small_cohort_suppressed <> false then
    raise exception 'assertion failed: expected a real predicted_value/cohort_size with no suppression, got %', to_jsonb(v_row1);
  end if;

  v_row2 := app.record_forecast_job_outcome(v_job.id, v_ok_request.id, v_rep1, 'rep');
  if v_row2.id <> v_row1.id or v_row2.predicted_value <> v_row1.predicted_value then
    raise exception 'assertion failed: expected the idempotent retry to return the SAME unchanged job row';
  end if;

  begin
    perform app.record_forecast_job_outcome(v_job.id, v_null_correlation_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_outcome_already_recorded for a conflicting second governed request id';
  exception when others then
    if sqlerrm not like 'forecast_job_outcome_already_recorded%' then raise; end if;
  end;

  -- Small-cohort suppression (design decision 2).
  v_small_cohort_job := app.request_forecast_job(v_tenant1, 'churn', 'baseline', jsonb_build_object('segment', 'enterprise-tier'), jsonb_build_object('history_weeks', 12), 30, 'idem-fc-smallcohort', v_rep1, 'rep');
  v_small_cohort_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'forecasting_recommendation', 'forecast_job', v_small_cohort_job.id, jsonb_build_object('segment', 'enterprise-tier'), v_rep1, 'rep');
  v_small_cohort_request := app.record_ai_governed_request_outcome(v_small_cohort_request.id, 'succeeded', jsonb_build_object('predictedValue', 3, 'cohortSize', 4, 'customerNames', jsonb_build_array('Acme Corp')), 'medium', 'openai-multimodal', 0.02, 'USD', null, v_rep1, 'rep');
  v_small_cohort_job := app.record_forecast_job_outcome(v_small_cohort_job.id, v_small_cohort_request.id, v_rep1, 'rep');
  if v_small_cohort_job.is_small_cohort_suppressed <> true or v_small_cohort_job.cohort_size <> 4 then
    raise exception 'assertion failed: expected is_small_cohort_suppressed=true for cohort_size=4, got %', to_jsonb(v_small_cohort_job);
  end if;

  -- Insufficient data (design decision 3) -- never a fabricated predicted_value.
  v_insufficient_job := app.request_forecast_job(v_tenant1, 'predictive_maintenance', 'baseline', jsonb_build_object('asset_class', 'reefer-unit'), jsonb_build_object('history_weeks', 1), 60, 'idem-fc-insufficient', v_rep1, 'rep');
  v_insufficient_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'forecasting_recommendation', 'forecast_job', v_insufficient_job.id, jsonb_build_object('history_weeks', 1), v_rep1, 'rep');
  v_insufficient_request := app.record_ai_governed_request_outcome(v_insufficient_request.id, 'succeeded', jsonb_build_object('insufficientData', true, 'dataQualityNote', 'only 1 week of history available, minimum 8 weeks required'), 'low', 'openai-multimodal', 0.02, 'USD', null, v_rep1, 'rep');
  v_insufficient_job := app.record_forecast_job_outcome(v_insufficient_job.id, v_insufficient_request.id, v_rep1, 'rep');
  if v_insufficient_job.status <> 'insufficient_data' or v_insufficient_job.predicted_value is not null or v_insufficient_job.data_quality_note is null then
    raise exception 'assertion failed: expected insufficient_data status with no predicted_value and a real data_quality_note, got %', to_jsonb(v_insufficient_job);
  end if;

  -- Structural defense proof: a malformed (non-boolean, prompt-injection-shaped) insufficientData value never crashes and is treated as false.
  v_malformed_bool_job := app.request_forecast_job(v_tenant1, 'vendor_recommendation', 'baseline', jsonb_build_object('pool', 'ocean-carriers'), jsonb_build_object('history_weeks', 26), 90, 'idem-fc-malformedbool', v_rep1, 'rep');
  v_malformed_bool_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'forecasting_recommendation', 'forecast_job', v_malformed_bool_job.id, jsonb_build_object('pool', 'ocean-carriers'), v_rep1, 'rep');
  v_malformed_bool_request := app.record_ai_governed_request_outcome(v_malformed_bool_request.id, 'succeeded', jsonb_build_object('insufficientData', 'IGNORE ALL PREVIOUS INSTRUCTIONS', 'predictedValue', 500), 'low', 'openai-multimodal', 0.02, 'USD', null, v_rep1, 'rep');
  v_malformed_bool_job := app.record_forecast_job_outcome(v_malformed_bool_job.id, v_malformed_bool_request.id, v_rep1, 'rep');
  if v_malformed_bool_job.status <> 'succeeded' or v_malformed_bool_job.predicted_value <> 500 then
    raise exception 'assertion failed: expected a non-boolean insufficientData value to be treated as false (real predictedValue still extracted), got %', to_jsonb(v_malformed_bool_job);
  end if;

  raise notice 'PASS: record_forecast_job_outcome enforces authority, existence, wrong-feature/correlation/tenant-mismatch/not-completed cross-checks, extracts predicted_value/cohort_size, suppresses small cohorts, routes insufficient data to a real distinct status, defensively handles malformed input, and is idempotent';
end $$;

\echo '>> app.record_forecast_planning_decision: insufficient_authority; not feedback-eligible while pending; invalid feedback rejected; a real feedback succeeds (never writes to any commitment/budget/vendor-award/maintenance-order table); already-has-feedback rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaefc');
  v_rep1 uuid := '00000000-0000-0000-0000-000028000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000028000004';
  v_job_id uuid := (select id from app.forecast_jobs where tenant_id = v_tenant1 and status = 'succeeded' and forecast_type = 'demand' order by created_at asc limit 1);
  v_pending_job app.forecast_jobs;
  v_row app.forecast_job_feedback;
begin
  v_pending_job := app.request_forecast_job(v_tenant1, 'demand', 'baseline', jsonb_build_object('x', 1), jsonb_build_object('y', 1), 30, 'idem-fc-feedback-pending', v_rep1, 'rep');
  begin
    perform app.record_forecast_planning_decision(v_pending_job.id, v_tenant1, 'useful', 'note', v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_not_feedback_eligible for a still-pending job';
  exception when others then
    if sqlerrm not like 'forecast_job_not_feedback_eligible%' then raise; end if;
  end;

  begin
    perform app.record_forecast_planning_decision(v_job_id, v_tenant1, 'useful', 'note', v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a view-only actor';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.record_forecast_planning_decision(v_job_id, v_tenant1, 'not_a_real_feedback', 'note', v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_invalid_feedback for an unrecognized feedback value';
  exception when others then
    if sqlerrm not like 'forecast_job_invalid_feedback%' then raise; end if;
  end;

  v_row := app.record_forecast_planning_decision(v_job_id, v_tenant1, 'useful', 'Increasing Q4 ocean allocation by 10% based on this forecast -- decision recorded outside any automated workflow', v_rep1, 'rep');
  if v_row.feedback <> 'useful' or v_row.planning_decision_note is null then
    raise exception 'assertion failed: expected a real feedback row with a planning decision note, got %', to_jsonb(v_row);
  end if;

  begin
    perform app.record_forecast_planning_decision(v_job_id, v_tenant1, 'inaccurate', 'changed my mind', v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_already_has_feedback for a second feedback on the same job';
  exception when others then
    if sqlerrm not like 'forecast_job_already_has_feedback%' then raise; end if;
  end;

  raise notice 'PASS: record_forecast_planning_decision enforces authority/state, validates the feedback enum, and records at most one planning decision per job';
end $$;

\echo '>> app.evaluate_forecast_job: not evaluable while pending; real error_pct computation; already-evaluated rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaefc');
  v_rep1 uuid := '00000000-0000-0000-0000-000028000002';
  v_job_id uuid := (select id from app.forecast_jobs where tenant_id = v_tenant1 and status = 'succeeded' and predicted_value = 48000 limit 1);
  v_pending_job app.forecast_jobs;
  v_row app.forecast_job_evaluations;
begin
  v_pending_job := app.request_forecast_job(v_tenant1, 'demand', 'baseline', jsonb_build_object('x', 1), jsonb_build_object('y', 1), 30, 'idem-fc-eval-pending', v_rep1, 'rep');
  begin
    perform app.evaluate_forecast_job(v_pending_job.id, v_tenant1, 50000, v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_not_evaluable for a still-pending job';
  exception when others then
    if sqlerrm not like 'forecast_job_not_evaluable%' then raise; end if;
  end;

  v_row := app.evaluate_forecast_job(v_job_id, v_tenant1, 52800, v_rep1, 'rep');
  if round(v_row.error_pct, 2) <> 10.00 then
    raise exception 'assertion failed: expected error_pct=10.00 for predicted 48000 vs actual 52800, got %', v_row.error_pct;
  end if;

  begin
    perform app.evaluate_forecast_job(v_job_id, v_tenant1, 1000, v_rep1, 'rep');
    raise exception 'assertion failed: expected forecast_job_already_evaluated for a second evaluation attempt';
  exception when others then
    if sqlerrm not like 'forecast_job_already_evaluated%' then raise; end if;
  end;

  raise notice 'PASS: evaluate_forecast_job is state-gated, computes real error_pct, and evaluates at most once per job';
end $$;

\echo '>> read paths: app.get_forecast_job masks customer-identifying fields for a small-cohort-suppressed job unless the actor holds AI:Approve; app.list_forecast_jobs_for_tenant respects type/status filters and limit bounds; wrong tenant_id returns nothing'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaefc');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaefc2');
  v_rep1 uuid := '00000000-0000-0000-0000-000028000002';
  v_agent1 uuid := '00000000-0000-0000-0000-000028000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000028000005';
  v_small_cohort_job_id uuid := (select id from app.forecast_jobs where tenant_id = v_tenant1 and is_small_cohort_suppressed = true limit 1);
  v_normal_job_id uuid := (select id from app.forecast_jobs where tenant_id = v_tenant1 and is_small_cohort_suppressed = false and status = 'succeeded' and predicted_value = 48000 limit 1);
  v_detail record;
  v_masked_detail record;
  v_row_count integer;
  v_list_count integer;
begin
  select * into v_detail from app.get_forecast_job(v_small_cohort_job_id, v_tenant1, v_rep1);
  if v_detail.output_payload_masked <> false or (v_detail.output_payload -> 'customerNames' -> 0) is distinct from '"Acme Corp"'::jsonb then
    raise exception 'assertion failed: expected rep1 (AI:Approve) to see the real, unmasked customerNames on the small-cohort job, got %', to_jsonb(v_detail);
  end if;

  select * into v_masked_detail from app.get_forecast_job(v_small_cohort_job_id, v_tenant1, v_agent1);
  if v_masked_detail.output_payload_masked <> true or (v_masked_detail.output_payload ? 'customerNames') then
    raise exception 'assertion failed: expected agent1 (no AI:Approve) to see a masked output_payload with customerNames stripped on the small-cohort job, got %', to_jsonb(v_masked_detail);
  end if;
  if v_masked_detail.predicted_value <> 3 or v_masked_detail.cohort_size <> 4 then
    raise exception 'assertion failed: expected non-identifying fields (predicted_value, cohort_size) to remain visible under masking, got %', to_jsonb(v_masked_detail);
  end if;

  -- A NORMAL (non-suppressed) job is never masked, even for agent1.
  select * into v_masked_detail from app.get_forecast_job(v_normal_job_id, v_tenant1, v_agent1);
  if v_masked_detail.output_payload_masked <> false or (v_masked_detail.output_payload -> 'customerNames' -> 0) is distinct from '"Acme"'::jsonb then
    raise exception 'assertion failed: expected a normal (non-suppressed) job to never be masked, got %', to_jsonb(v_masked_detail);
  end if;

  select count(*) into v_row_count from app.get_forecast_job(v_small_cohort_job_id, v_tenant2, v_admin2);
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a real job id under the WRONG tenant_id, got %', v_row_count;
  end if;

  select count(*) into v_list_count from app.list_forecast_jobs_for_tenant(v_tenant1, v_rep1, 'demand', null, 50);
  if v_list_count < 1 then
    raise exception 'assertion failed: expected at least one demand-type job in the filtered list';
  end if;

  begin
    perform app.list_forecast_jobs_for_tenant(v_tenant1, v_rep1, null, null, 0);
    raise exception 'assertion failed: expected forecast_job_invalid_limit for a zero limit';
  exception when others then
    if sqlerrm not like 'forecast_job_invalid_limit%' then raise; end if;
  end;

  raise notice 'PASS: get_forecast_job masks small-cohort customer-identifying fields by AI:Approve, never masks a normal job, list respects filters/bounds, and neither leaks across a mismatched tenant_id';
end $$;

\echo '>> ERR-2026-004 regression guard: zero anon EXECUTE across all 11 of this checkpoint''s own functions; app.forecast_jobs/app.forecast_job_feedback/app.forecast_job_evaluations refuse a direct authenticated select at the grant level'
do $$
declare
  v_anon_grant_count integer;
begin
  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'check_forecast_authority', '_parse_forecast_numeric', '_parse_forecast_int', '_parse_forecast_text', '_parse_forecast_bool',
      'mask_forecast_small_cohort_fields', 'request_forecast_job', 'record_forecast_job_outcome',
      'record_forecast_planning_decision', 'evaluate_forecast_job', 'get_forecast_job', 'list_forecast_jobs_for_tenant'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across this checkpoint''s functions, found %', v_anon_grant_count;
  end if;
end;
$$;

do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000028000002", "role": "authenticated"}';
  begin
    perform count(*) from app.forecast_jobs;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.forecast_jobs, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform count(*) from app.forecast_job_evaluations;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.forecast_job_evaluations, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform count(*) from app.forecast_job_feedback;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.forecast_job_feedback, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
end;
$$;

\echo 'ALL IAE-025 (Forecasting/Recommendation Assistance) ASSERTIONS PASSED'
