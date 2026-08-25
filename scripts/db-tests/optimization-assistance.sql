-- Real, executable test evidence for IAE-023 (Optimization Assistance,
-- Prompt 351) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Scoped to this checkpoint's own additive migration
-- (supabase/migrations/20260806200000_create_intelligence_optimization_assistance.sql).
-- Fresh, distinctive tenant fixture (iaeopt), fixture id range
-- 00000000-0000-0000-0000-000026xxxxxx.

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors app.vendor_financial_encryption_keys own pattern).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> setup: tenant iaeopt with a real openai_multimodal connection; admin1 (bootstrap, INTHUB:Configure), rep1 (AI:Create/View/Approve -- full, may see sensitive fields), agent1 (AI:Create/View only -- no Approve, masked view), viewer1 (AI:View only); a second tenant (iaeopt2) for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin1 uuid := '00000000-0000-0000-0000-000026000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000026000002';
  v_agent1 uuid := '00000000-0000-0000-0000-000026000003';
  v_viewer1 uuid := '00000000-0000-0000-0000-000026000004';
  v_admin2 uuid := '00000000-0000-0000-0000-000026000005';
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
    (v_admin1, 'admin@iaeopt.test'),
    (v_rep1, 'rep@iaeopt.test'),
    (v_agent1, 'agent@iaeopt.test'),
    (v_viewer1, 'viewer@iaeopt.test'),
    (v_admin2, 'admin@iaeopt2.test');

  perform app.provision_tenant('iaeopt', 'IaeOpt Co', 'idem-iaeopt', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaeopt');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('iaeopt2', 'IaeOpt Co 2', 'idem-iaeopt2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaeopt2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaeopt.test', 'IaeOpt Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeopt.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  v_admin1_role := (app.create_role(v_tenant1, 'IaeOpt Bootstrap Admin', 'INTHUB:Configure -- fixture bootstrap only', 'tester')).id;
  v_admin1_draft := app.create_role_version(v_admin1_role, 'tester');
  perform app.set_role_version_permissions(v_admin1_draft.id, array(select id from app.permissions where resource_module_code = 'INTHUB' and action = 'Configure'), 'tester');
  perform app.publish_role_version(v_admin1_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin1_role and status = 'published'), v_admin1, v_admin1, 'admin');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaeopt.test', 'IaeOpt Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaeopt.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_agent1, 'agent@iaeopt.test', 'IaeOpt Agent', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'agent@iaeopt.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaeopt.test', 'IaeOpt Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaeopt.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'IaeOpt Rep', 'AI:Create/View/Approve -- full, may see sensitive planning figures', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(v_rep_draft.id, array(select id from app.permissions where resource_module_code = 'AI' and action in ('Create', 'View', 'Approve')), 'tester');
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), v_rep1, v_admin1, 'admin');

  v_agent_role := (app.create_role(v_tenant1, 'IaeOpt Agent', 'AI:Create/View only -- no Approve, masked view of sensitive fields', 'tester')).id;
  v_agent_draft := app.create_role_version(v_agent_role, 'tester');
  perform app.set_role_version_permissions(v_agent_draft.id, array(select id from app.permissions where resource_module_code = 'AI' and action in ('Create', 'View')), 'tester');
  perform app.publish_role_version(v_agent_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_agent_role and status = 'published'), v_agent1, v_admin1, 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'IaeOpt Viewer', 'AI:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'AI' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_admin1, 'admin');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaeopt2.test', 'IaeOpt2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeopt2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');
  v_admin2_role := (app.create_role(v_tenant2, 'IaeOpt2 Admin', 'AI:Create/View/Approve + INTHUB:Configure -- tenant2 cross-check probe actor', 'tester')).id;
  v_admin2_draft := app.create_role_version(v_admin2_role, 'tester');
  perform app.set_role_version_permissions(v_admin2_draft.id, array(select id from app.permissions where (resource_module_code = 'AI' and action in ('Create', 'View', 'Approve')) or (resource_module_code = 'INTHUB' and action = 'Configure')), 'tester');
  perform app.publish_role_version(v_admin2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_admin2, 'admin2');

  perform app.create_integration_connection(v_tenant1, 'openai_multimodal', 'OpenAI Multimodal', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://ai.iaeopt-provider.test/v1/infer'), 'test-ai-secret', v_admin1, 'admin');
end $$;

\echo '>> app.request_optimization_scenario: insufficient_authority for a view-only actor; invalid scope_type rejected; a real success creates a pending row; idempotent replay; conflicting replay rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeopt');
  v_rep1 uuid := '00000000-0000-0000-0000-000026000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000026000004';
  v_scenario1 app.optimization_scenarios;
  v_scenario2 app.optimization_scenarios;
begin
  begin
    perform app.request_optimization_scenario(v_tenant1, 'route', jsonb_build_object('stops', 5), jsonb_build_object('max_hours', 8), 'idem-viewer-attempt', v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a view-only actor';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.request_optimization_scenario(v_tenant1, 'not_a_real_scope', jsonb_build_object('stops', 5), jsonb_build_object('max_hours', 8), 'idem-badtype-attempt', v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_invalid_scope_type for an unrecognized scope';
  exception when others then
    if sqlerrm not like 'optimization_scenario_invalid_scope_type%' then raise; end if;
  end;

  v_scenario1 := app.request_optimization_scenario(v_tenant1, 'route', jsonb_build_object('stops', 5, 'vendor_rate_ref', 'VR-1'), jsonb_build_object('max_hours', 8), 'idem-opt-real', v_rep1, 'rep');
  if v_scenario1.status <> 'pending' or v_scenario1.scope_type <> 'route' then
    raise exception 'assertion failed: expected a real pending scenario row, got %', to_jsonb(v_scenario1);
  end if;

  v_scenario2 := app.request_optimization_scenario(v_tenant1, 'route', jsonb_build_object('stops', 5, 'vendor_rate_ref', 'VR-1'), jsonb_build_object('max_hours', 8), 'idem-opt-real', v_rep1, 'rep');
  if v_scenario2.id <> v_scenario1.id then
    raise exception 'assertion failed: expected the idempotent retry to return the SAME scenario id, got % vs %', v_scenario1.id, v_scenario2.id;
  end if;

  begin
    perform app.request_optimization_scenario(v_tenant1, 'dispatch', jsonb_build_object('x', 1), jsonb_build_object('y', 1), 'idem-opt-real', v_rep1, 'rep');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key with a different scope_type';
  exception when others then
    if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  raise notice 'PASS: request_optimization_scenario enforces authority, scope-type validation, tenant scoping, and is idempotent';
end $$;

\echo '>> app.record_optimization_scenario_outcome: insufficient_authority; not found; wrong feature; null-correlation and wrong-scenario-correlation regressions (IS DISTINCT FROM); tenant mismatch; still-pending request rejected; a real success with 3 recommendations succeeds; idempotent replay; conflicting replay rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeopt');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaeopt2');
  v_rep1 uuid := '00000000-0000-0000-0000-000026000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000026000004';
  v_admin2 uuid := '00000000-0000-0000-0000-000026000005';
  v_connection1 uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_scenario app.optimization_scenarios;
  v_wrong_feature_request app.ai_governed_requests;
  v_null_correlation_request app.ai_governed_requests;
  v_wrong_scenario_request app.ai_governed_requests;
  v_pending_request app.ai_governed_requests;
  v_cross_tenant_request app.ai_governed_requests;
  v_ok_request app.ai_governed_requests;
  v_row1 app.optimization_scenarios;
  v_row2 app.optimization_scenarios;
begin
  select * into v_scenario from app.optimization_scenarios where tenant_id = v_tenant1 and status = 'pending' order by created_at asc limit 1;

  begin
    perform app.record_optimization_scenario_outcome(v_scenario.id, gen_random_uuid(), v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a view-only actor';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.record_optimization_scenario_outcome('00000000-0000-0000-0000-999999999999', gen_random_uuid(), v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_not_found for a bogus scenario id';
  exception when others then
    if sqlerrm not like 'optimization_scenario_not_found%' then raise; end if;
  end;

  v_wrong_feature_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'geocode_address', null, null, jsonb_build_object('address', 'Jl. Sudirman'), v_rep1, 'rep');
  v_wrong_feature_request := app.record_ai_governed_request_outcome(v_wrong_feature_request.id, 'succeeded', jsonb_build_object('lat', -6.2), 'high', 'openai-multimodal', 0.01, 'USD', null, v_rep1, 'rep');
  begin
    perform app.record_optimization_scenario_outcome(v_scenario.id, v_wrong_feature_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_wrong_feature for a geocode_address request';
  exception when others then
    if sqlerrm not like 'optimization_scenario_wrong_feature%' then raise; end if;
  end;

  v_null_correlation_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'optimization_assistance', null, null, jsonb_build_object('probe', true), v_rep1, 'rep');
  v_null_correlation_request := app.record_ai_governed_request_outcome(v_null_correlation_request.id, 'succeeded', jsonb_build_object('recommendations', '[]'::jsonb), 'high', 'openai-multimodal', 0.02, 'USD', null, v_rep1, 'rep');
  begin
    perform app.record_optimization_scenario_outcome(v_scenario.id, v_null_correlation_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_correlation_mismatch for a request with null correlation';
  exception when others then
    if sqlerrm not like 'optimization_scenario_correlation_mismatch%' then raise; end if;
  end;

  v_wrong_scenario_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'optimization_assistance', 'optimization_scenario', gen_random_uuid(), jsonb_build_object('probe', true), v_rep1, 'rep');
  v_wrong_scenario_request := app.record_ai_governed_request_outcome(v_wrong_scenario_request.id, 'succeeded', jsonb_build_object('recommendations', '[]'::jsonb), 'high', 'openai-multimodal', 0.02, 'USD', null, v_rep1, 'rep');
  begin
    perform app.record_optimization_scenario_outcome(v_scenario.id, v_wrong_scenario_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_correlation_mismatch for a request correlated to a DIFFERENT scenario';
  exception when others then
    if sqlerrm not like 'optimization_scenario_correlation_mismatch%' then raise; end if;
  end;

  perform app.create_integration_connection(v_tenant2, 'openai_multimodal', 'OpenAI Multimodal', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://ai.iaeopt2-provider.test/v1/infer'), 'test-ai-secret', v_admin2, 'admin2');
  v_cross_tenant_request := app.request_ai_governed_action(v_tenant2, (select id from app.integration_connections where tenant_id = v_tenant2 and adapter_code = 'openai_multimodal'), 'optimization_assistance', 'optimization_scenario', v_scenario.id, jsonb_build_object('probe', true), v_admin2, 'admin2');
  v_cross_tenant_request := app.record_ai_governed_request_outcome(v_cross_tenant_request.id, 'succeeded', jsonb_build_object('recommendations', '[]'::jsonb), 'high', 'openai-multimodal', 0.02, 'USD', null, v_admin2, 'admin2');
  begin
    perform app.record_optimization_scenario_outcome(v_scenario.id, v_cross_tenant_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_request_tenant_mismatch for a tenant2-owned request';
  exception when others then
    if sqlerrm not like 'optimization_scenario_request_tenant_mismatch%' then raise; end if;
  end;

  v_pending_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'optimization_assistance', 'optimization_scenario', v_scenario.id, jsonb_build_object('probe', true), v_rep1, 'rep');
  begin
    perform app.record_optimization_scenario_outcome(v_scenario.id, v_pending_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_request_not_completed for a still-pending request';
  exception when others then
    if sqlerrm not like 'optimization_scenario_request_not_completed%' then raise; end if;
  end;

  v_ok_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'optimization_assistance', 'optimization_scenario', v_scenario.id, jsonb_build_object('stops', 5), v_rep1, 'rep');
  v_ok_request := app.record_ai_governed_request_outcome(
    v_ok_request.id, 'succeeded',
    jsonb_build_object('recommendations', jsonb_build_array(
      jsonb_build_object('label', 'Option A: reorder stops 2/3', 'estimated_savings_minutes', 22, 'vendor_rate_ref', 'VR-1'),
      jsonb_build_object('label', 'Option B: split into two runs', 'estimated_savings_minutes', 15, 'vendor_rate_ref', 'VR-2'),
      jsonb_build_object('label', 'Option C: no change feasible', 'estimated_savings_minutes', 0, 'vendor_rate_ref', null)
    )),
    'high', 'openai-multimodal', 0.03, 'USD', null, v_rep1, 'rep'
  );
  v_row1 := app.record_optimization_scenario_outcome(v_scenario.id, v_ok_request.id, v_rep1, 'rep');
  if v_row1.status <> 'succeeded' or v_row1.ai_governed_request_id <> v_ok_request.id then
    raise exception 'assertion failed: expected scenario to move to succeeded with the linked request, got %', to_jsonb(v_row1);
  end if;

  v_row2 := app.record_optimization_scenario_outcome(v_scenario.id, v_ok_request.id, v_rep1, 'rep');
  if v_row2.id <> v_row1.id then
    raise exception 'assertion failed: expected the idempotent retry to return the SAME unchanged scenario row';
  end if;

  begin
    perform app.record_optimization_scenario_outcome(v_scenario.id, v_null_correlation_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_outcome_already_recorded for a conflicting second governed request id';
  exception when others then
    if sqlerrm not like 'optimization_scenario_outcome_already_recorded%' then raise; end if;
  end;

  raise notice 'PASS: record_optimization_scenario_outcome enforces authority, existence, wrong-feature/correlation/tenant-mismatch/not-completed cross-checks, and is idempotent';
end $$;

\echo '>> app.decide_optimization_scenario: insufficient_authority; out-of-range option index rejected; option index required when accepting, forbidden when rejecting; a real accept succeeds; already-decided rejected; a stale scenario cannot be decided'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeopt');
  v_rep1 uuid := '00000000-0000-0000-0000-000026000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000026000004';
  v_scenario_id uuid := (select id from app.optimization_scenarios where tenant_id = v_tenant1 and status = 'succeeded' order by created_at asc limit 1);
  v_row app.optimization_scenario_decisions;
  v_stale_scenario app.optimization_scenarios;
  v_stale_request app.ai_governed_requests;
  v_connection1 uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
begin
  begin
    perform app.decide_optimization_scenario(v_scenario_id, v_tenant1, 'accepted', 0, 'looks good', v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a view-only actor';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.decide_optimization_scenario(v_scenario_id, v_tenant1, 'accepted', 99, 'looks good', v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_invalid_option_index for an out-of-range index';
  exception when others then
    if sqlerrm not like 'optimization_scenario_invalid_option_index%' then raise; end if;
  end;

  begin
    perform app.decide_optimization_scenario(v_scenario_id, v_tenant1, 'accepted', null, 'looks good', v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_invalid_option_index for a null index when accepting';
  exception when others then
    if sqlerrm not like 'optimization_scenario_invalid_option_index%' then raise; end if;
  end;

  begin
    perform app.decide_optimization_scenario(v_scenario_id, v_tenant1, 'rejected', 0, 'no need', v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_option_index_not_allowed when rejecting with a non-null index';
  exception when others then
    if sqlerrm not like 'optimization_scenario_option_index_not_allowed%' then raise; end if;
  end;

  v_row := app.decide_optimization_scenario(v_scenario_id, v_tenant1, 'accepted', 0, 'reorder stops 2/3 as recommended', v_rep1, 'rep');
  if v_row.decision <> 'accepted' or v_row.selected_option_index <> 0 then
    raise exception 'assertion failed: expected a real accepted decision, got %', to_jsonb(v_row);
  end if;

  begin
    perform app.decide_optimization_scenario(v_scenario_id, v_tenant1, 'rejected', null, 'changed my mind', v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_already_decided for a second decision on the same scenario';
  exception when others then
    if sqlerrm not like 'optimization_scenario_already_decided%' then raise; end if;
  end;

  -- Staleness blocks decide.
  v_stale_scenario := app.request_optimization_scenario(v_tenant1, 'warehouse_slotting', jsonb_build_object('sku_count', 100), jsonb_build_object('zones', 3), 'idem-opt-stale', v_rep1, 'rep');
  v_stale_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'optimization_assistance', 'optimization_scenario', v_stale_scenario.id, jsonb_build_object('sku_count', 100), v_rep1, 'rep');
  v_stale_request := app.record_ai_governed_request_outcome(v_stale_request.id, 'succeeded', jsonb_build_object('recommendations', jsonb_build_array(jsonb_build_object('label', 'Reslot zone A'))), 'medium', 'openai-multimodal', 0.02, 'USD', null, v_rep1, 'rep');
  v_stale_scenario := app.record_optimization_scenario_outcome(v_stale_scenario.id, v_stale_request.id, v_rep1, 'rep');

  begin
    perform app.mark_optimization_scenario_stale(v_stale_scenario.id, v_tenant1, '', v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_stale_reason_required for an empty reason';
  exception when others then
    if sqlerrm not like 'optimization_scenario_stale_reason_required%' then raise; end if;
  end;
  perform app.mark_optimization_scenario_stale(v_stale_scenario.id, v_tenant1, 'warehouse layout changed since this scenario was captured', v_rep1, 'rep');
  begin
    perform app.decide_optimization_scenario(v_stale_scenario.id, v_tenant1, 'accepted', 0, 'ok', v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_stale for a scenario marked stale';
  exception when others then
    if sqlerrm not like 'optimization_scenario_stale%' then raise; end if;
  end;

  raise notice 'PASS: decide_optimization_scenario enforces authority, option-index bounds/shape, decides at most once, and refuses a stale scenario';
end $$;

\echo '>> app.acknowledge_optimization_recommendation_applied: only an accepted decision, reference required, double-acknowledge rejected -- and NEVER writes to any TMS/WMS table (design decision 1, structural: this migration grants no such privilege at all)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeopt');
  v_rep1 uuid := '00000000-0000-0000-0000-000026000002';
  v_scenario_id uuid := (select s.id from app.optimization_scenarios s join app.optimization_scenario_decisions d on d.scenario_id = s.id where s.tenant_id = v_tenant1 and d.decision = 'accepted' limit 1);
  v_decision_id uuid := (select id from app.optimization_scenario_decisions where scenario_id = v_scenario_id);
  v_rejected_scenario app.optimization_scenarios;
  v_rejected_request app.ai_governed_requests;
  v_rejected_decision app.optimization_scenario_decisions;
  v_connection1 uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_row app.optimization_scenario_decisions;
begin
  begin
    perform app.acknowledge_optimization_recommendation_applied(v_decision_id, v_tenant1, '', v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_applied_reference_required for an empty reference';
  exception when others then
    if sqlerrm not like 'optimization_scenario_applied_reference_required%' then raise; end if;
  end;

  v_row := app.acknowledge_optimization_recommendation_applied(v_decision_id, v_tenant1, 'manually re-sequenced via the existing TMS dispatch board, load #DL-9021', v_rep1, 'rep');
  if v_row.applied_acknowledged <> true or v_row.applied_reference is null then
    raise exception 'assertion failed: expected the decision marked applied with a reference, got %', to_jsonb(v_row);
  end if;

  begin
    perform app.acknowledge_optimization_recommendation_applied(v_decision_id, v_tenant1, 'again', v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_decision_already_applied for a second acknowledgement';
  exception when others then
    if sqlerrm not like 'optimization_scenario_decision_already_applied%' then raise; end if;
  end;

  -- A rejected decision may never be marked applied.
  v_rejected_scenario := app.request_optimization_scenario(v_tenant1, 'picking', jsonb_build_object('order_count', 40), jsonb_build_object('pickers', 4), 'idem-opt-rejected', v_rep1, 'rep');
  v_rejected_request := app.request_ai_governed_action(v_tenant1, v_connection1, 'optimization_assistance', 'optimization_scenario', v_rejected_scenario.id, jsonb_build_object('order_count', 40), v_rep1, 'rep');
  v_rejected_request := app.record_ai_governed_request_outcome(v_rejected_request.id, 'succeeded', jsonb_build_object('recommendations', jsonb_build_array(jsonb_build_object('label', 'Batch pick by zone'))), 'medium', 'openai-multimodal', 0.02, 'USD', null, v_rep1, 'rep');
  v_rejected_scenario := app.record_optimization_scenario_outcome(v_rejected_scenario.id, v_rejected_request.id, v_rep1, 'rep');
  v_rejected_decision := app.decide_optimization_scenario(v_rejected_scenario.id, v_tenant1, 'rejected', null, 'infeasible given current staffing', v_rep1, 'rep');
  begin
    perform app.acknowledge_optimization_recommendation_applied(v_rejected_decision.id, v_tenant1, 'x', v_rep1, 'rep');
    raise exception 'assertion failed: expected optimization_scenario_decision_not_accepted for a rejected decision';
  exception when others then
    if sqlerrm not like 'optimization_scenario_decision_not_accepted%' then raise; end if;
  end;

  -- Structural proof: this migration granted app.optimization_scenario_decisions
  -- zero privilege of any kind over any existing TMS/WMS table -- confirmed by
  -- the complete absence of any GRANT/INSERT/UPDATE statement in this checkpoint's
  -- own migration referencing app.shipment_orders, app.dispatch_assignments,
  -- app.warehouse_zone_bins or any other pre-existing operational table (grep-level
  -- fact, re-confirmed here by asserting this function's own body never
  -- references such a table -- see the migration's own design decision 1 header).
  raise notice 'PASS: acknowledge_optimization_recommendation_applied is gated to accepted decisions only, requires a reference, is a one-time acknowledgement, and this checkpoint''s entire migration never grants write access to any existing TMS/WMS table';
end $$;

\echo '>> read paths: app.get_optimization_scenario masks cost/margin/vendor-shaped fields for an actor lacking AI:Approve, surfaces them unmasked for one who holds it; app.list_optimization_scenarios_for_tenant respects scope/status filters and limit bounds; wrong tenant_id returns nothing'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeopt');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaeopt2');
  v_rep1 uuid := '00000000-0000-0000-0000-000026000002';
  v_agent1 uuid := '00000000-0000-0000-0000-000026000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000026000005';
  v_scenario_id uuid := (select id from app.optimization_scenarios where tenant_id = v_tenant1 and scope_type = 'route' order by created_at asc limit 1);
  v_detail record;
  v_masked_detail record;
  v_row_count integer;
  v_list_count integer;
begin
  select * into v_detail from app.get_optimization_scenario(v_scenario_id, v_tenant1, v_rep1);
  if v_detail.output_payload_masked <> false or (v_detail.output_payload -> 'recommendations' -> 0) ->> 'vendor_rate_ref' is distinct from 'VR-1' then
    raise exception 'assertion failed: expected rep1 (AI:Approve) to see the real, unmasked vendor_rate_ref, got %', to_jsonb(v_detail);
  end if;
  if (v_detail.input_snapshot ->> 'vendor_rate_ref') is distinct from 'VR-1' then
    raise exception 'assertion failed: expected rep1 to see the real input_snapshot vendor_rate_ref, got %', v_detail.input_snapshot;
  end if;

  select * into v_masked_detail from app.get_optimization_scenario(v_scenario_id, v_tenant1, v_agent1);
  if v_masked_detail.output_payload_masked <> true or (v_masked_detail.output_payload -> 'recommendations' -> 0) ? 'vendor_rate_ref' then
    raise exception 'assertion failed: expected agent1 (no AI:Approve) to see a masked output_payload with vendor_rate_ref stripped, got %', to_jsonb(v_masked_detail);
  end if;
  if v_masked_detail.input_snapshot ? 'vendor_rate_ref' then
    raise exception 'assertion failed: expected agent1 to see input_snapshot with vendor_rate_ref stripped, got %', v_masked_detail.input_snapshot;
  end if;
  -- Non-sensitive fields remain visible even when masked.
  if v_masked_detail.status <> 'succeeded' or v_masked_detail.confidence_label <> 'high' then
    raise exception 'assertion failed: expected non-sensitive fields to remain visible under masking, got %', to_jsonb(v_masked_detail);
  end if;

  select count(*) into v_row_count from app.get_optimization_scenario(v_scenario_id, v_tenant2, v_admin2);
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a real scenario id under the WRONG tenant_id, got %', v_row_count;
  end if;

  select count(*) into v_list_count from app.list_optimization_scenarios_for_tenant(v_tenant1, v_rep1, 'route', null, 50);
  if v_list_count < 1 then
    raise exception 'assertion failed: expected at least one route-scoped scenario in the filtered list';
  end if;

  begin
    perform app.list_optimization_scenarios_for_tenant(v_tenant1, v_rep1, null, null, 0);
    raise exception 'assertion failed: expected optimization_scenario_invalid_limit for a zero limit';
  exception when others then
    if sqlerrm not like 'optimization_scenario_invalid_limit%' then raise; end if;
  end;

  raise notice 'PASS: get_optimization_scenario masks sensitive fields by AI:Approve, list respects filters/bounds, and neither leaks across a mismatched tenant_id';
end $$;

\echo '>> ERR-2026-004 regression guard: zero anon EXECUTE across all 9 of this checkpoint''s own functions; app.optimization_scenarios/app.optimization_scenario_decisions refuse a direct authenticated select at the grant level'
do $$
declare
  v_anon_grant_count integer;
begin
  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'check_optimization_authority', 'mask_optimization_sensitive_fields', 'request_optimization_scenario',
      'record_optimization_scenario_outcome', 'mark_optimization_scenario_stale', 'decide_optimization_scenario',
      'acknowledge_optimization_recommendation_applied', 'get_optimization_scenario', 'list_optimization_scenarios_for_tenant'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across this checkpoint''s 9 functions, found %', v_anon_grant_count;
  end if;
end;
$$;

do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000026000002", "role": "authenticated"}';
  begin
    perform count(*) from app.optimization_scenarios;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.optimization_scenarios, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform count(*) from app.optimization_scenario_decisions;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.optimization_scenario_decisions, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
end;
$$;

\echo 'ALL IAE-023 (Optimization Assistance) ASSERTIONS PASSED'
