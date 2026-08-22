-- Real, executable test evidence for IAE-019 (AI Governance Provider
-- Boundary, Prompt 347) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Scoped to this checkpoint's own additive
-- migration (supabase/migrations/
-- 20260805060000_create_intelligence_ai_governance_provider_boundary.sql).
-- Fresh, distinctive tenant fixture (iaeaigov), fixture id range
-- 00000000-0000-0000-0000-000021xxxxxx.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaeaigov with a real openai_multimodal integration connection; a rep (AI:Create+View, INTHUB:Configure), an approver (AI:Approve+View), a viewer (AI:View only); a second tenant (iaeaigov2) for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin1 uuid := '00000000-0000-0000-0000-000021000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000021000002';
  v_approver1 uuid := '00000000-0000-0000-0000-000021000003';
  v_viewer1 uuid := '00000000-0000-0000-0000-000021000004';
  v_admin2 uuid := '00000000-0000-0000-0000-000021000005';
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_approver_role uuid;
  v_approver_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_admin1, 'admin@iaeaigov.test'),
    (v_rep1, 'rep@iaeaigov.test'),
    (v_approver1, 'approver@iaeaigov.test'),
    (v_viewer1, 'viewer@iaeaigov.test'),
    (v_admin2, 'admin@iaeaigov2.test');

  perform app.provision_tenant('iaeaigov', 'IaeAiGov Co', 'idem-iaeaigov', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaeaigov');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('iaeaigov2', 'IaeAiGov Co 2', 'idem-iaeaigov2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaeaigov2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaeaigov.test', 'IaeAiGov Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeaigov.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaeaigov.test', 'IaeAiGov Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaeaigov.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_approver1, 'approver@iaeaigov.test', 'IaeAiGov Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@iaeaigov.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaeaigov.test', 'IaeAiGov Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaeaigov.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'AiGov Rep', 'AI:Create+View, INTHUB:Configure+View', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'AI' and action in ('Create', 'View')) or (resource_module_code = 'INTHUB' and action in ('Configure', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), v_rep1, v_admin1, 'admin');

  v_approver_role := (app.create_role(v_tenant1, 'AiGov Approver', 'AI:Approve+View, no Create', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'AI' and action in ('Approve', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), v_approver1, v_admin1, 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'AiGov Viewer', 'AI:View only, no Create/Approve', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'AI' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_admin1, 'admin');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaeaigov2.test', 'IaeAiGov2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeaigov2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  perform app.create_integration_connection(v_tenant1, 'openai_multimodal', 'OpenAI Multimodal', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://ai.iaeaigov-provider.test/v1/infer'), 'test-ai-secret', v_rep1, 'rep');
end $$;

\echo '>> module/adapter registration: AI entitlement module and its 3 permissions exist; openai_multimodal adapter is registered under owner_primitive_code AI'
do $$
begin
  if not exists (select 1 from app.entitlement_modules where code = 'AI' and owning_phase = 9) then
    raise exception 'assertion failed: expected the AI entitlement module to be registered with owning_phase = 9';
  end if;
  if (select count(*) from app.permissions where resource_module_code = 'AI' and action in ('Create', 'View', 'Approve')) <> 3 then
    raise exception 'assertion failed: expected exactly 3 AI permissions (Create/View/Approve)';
  end if;
  if not exists (select 1 from app.integration_adapters where code = 'openai_multimodal' and owner_primitive_code = 'AI') then
    raise exception 'assertion failed: expected the openai_multimodal adapter registered under owner_primitive_code AI';
  end if;

  raise notice 'PASS: AI entitlement module, its 3 permissions, and the openai_multimodal adapter are all real, registered rows';
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds EXECUTE on ZERO new IAE-019 functions -- AI output must never have any anonymous, unauthenticated surface'
do $$
declare
  v_fn text;
  v_new_functions text[] := array[
    'check_ai_governance_authority', 'assert_ai_prompt_payload_has_no_secret_shaped_keys',
    'get_ai_governed_dispatch_info', 'get_ai_governed_credential', 'request_ai_governed_action',
    'record_ai_governed_request_outcome', 'list_ai_governed_requests_for_tenant',
    'request_ai_output_approval', 'decide_ai_output_approval'
  ];
begin
  foreach v_fn in array v_new_functions loop
    if exists (
      select 1 from information_schema.role_routine_grants
      where routine_schema = 'app' and routine_name = v_fn and grantee = 'anon'
    ) then
      raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_fn;
    end if;
  end loop;

  raise notice 'PASS: anon holds zero EXECUTE on any new IAE-019 function';
end;
$$;

\echo '>> app.get_ai_governed_dispatch_info: AI:Create-gated, resolves the tenant''s own real openai_multimodal connection; a View-only actor is denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaigov');
  v_rep1 uuid := '00000000-0000-0000-0000-000021000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000021000004';
  v_row record;
begin
  select * into v_row from app.get_ai_governed_dispatch_info(v_tenant1, v_rep1);
  if v_row.connection_status <> 'active' or (v_row.connection_config->>'apiUrl') <> 'https://ai.iaeaigov-provider.test/v1/infer' then
    raise exception 'assertion failed: expected the real active openai_multimodal connection, got %', to_jsonb(v_row);
  end if;

  begin
    perform app.get_ai_governed_dispatch_info(v_tenant1, v_viewer1);
    raise exception 'assertion failed: expected insufficient_authority for a View-only actor (dispatch info requires AI:Create)';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: get_ai_governed_dispatch_info is AI:Create-gated and resolves the real connection';
end;
$$;

\echo '>> app.request_ai_governed_action: AI:Create-gated, requires a non-empty feature_code, rejects a secret-shaped prompt key, otherwise records a real pending row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaigov');
  v_rep1 uuid := '00000000-0000-0000-0000-000021000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000021000004';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_request app.ai_governed_requests;
begin
  begin
    perform app.request_ai_governed_action(v_tenant1, v_connection_id, 'quotation_draft', null, null, jsonb_build_object('origin', 'JKT'), v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a View-only actor';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.request_ai_governed_action(v_tenant1, v_connection_id, '   ', null, null, jsonb_build_object('origin', 'JKT'), v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_governed_request_feature_code_required for a blank feature_code';
  exception when check_violation then
    if sqlerrm !~ 'ai_governed_request_feature_code_required' then raise; end if;
  end;

  begin
    perform app.request_ai_governed_action(v_tenant1, v_connection_id, 'quotation_draft', null, null, jsonb_build_object('bank_account_number', '1234567890'), v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_governed_request_secret_shaped_key for a bank_account_number-shaped prompt key';
  exception when check_violation then
    if sqlerrm !~ 'ai_governed_request_secret_shaped_key' then raise; end if;
  end;

  v_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'quotation_draft', null, null, jsonb_build_object('origin', 'JKT', 'destination', 'SBY'), v_rep1, 'rep');
  if v_request.status <> 'pending' or v_request.feature_code <> 'quotation_draft' then
    raise exception 'assertion failed: expected a real pending request, got %', to_jsonb(v_request);
  end if;

  raise notice 'PASS: request_ai_governed_action is AI:Create-gated, requires a real feature_code, rejects a secret-shaped prompt key, and records a real pending row otherwise';
end;
$$;

\echo '>> app.record_ai_governed_request_outcome: rejects a non-pending request (idempotency), rejects a negative cost, REDACTS (never rejects) a secret-shaped output key -- output is untrusted provider content, per the merged Batch 4 Tier C review fix -- otherwise computes billed_amount at the real +20% markup (RPD-028) and completes'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaigov');
  v_rep1 uuid := '00000000-0000-0000-0000-000021000002';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_request app.ai_governed_requests;
  v_redact_request app.ai_governed_requests;
  v_outcome app.ai_governed_requests;
begin
  v_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'quotation_draft', null, null, jsonb_build_object('origin', 'JKT'), v_rep1, 'rep');

  begin
    perform app.record_ai_governed_request_outcome(v_request.id, 'succeeded', jsonb_build_object('draftLines', '[]'::jsonb), 'high', 'openai-multimodal', -1, 'USD', null, v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_governed_request_invalid_cost_amount for a negative cost';
  exception when check_violation then
    if sqlerrm !~ 'ai_governed_request_invalid_cost_amount' then raise; end if;
  end;

  -- Tier C fix: output_payload is provider-controlled, untrusted content --
  -- a secret-shaped key there is now REDACTED, never rejected (rejecting it
  -- would permanently strand the governance write itself on an ordinary,
  -- legitimate AI response). A SEPARATE request is used here since this
  -- call now genuinely succeeds and transitions its own request.
  v_redact_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'quotation_draft', null, null, jsonb_build_object('origin', 'JKT'), v_rep1, 'rep');
  v_outcome := app.record_ai_governed_request_outcome(v_redact_request.id, 'succeeded', jsonb_build_object('api_key', 'leaked', 'note', 'ok'), null, 'openai-multimodal', 0.05, 'USD', null, v_rep1, 'rep');
  if v_outcome.status <> 'succeeded' or v_outcome.output_payload ->> 'api_key' <> '[REDACTED]' or v_outcome.output_payload ->> 'note' <> 'ok' then
    raise exception 'assertion failed: expected a real succeeded outcome with the secret-shaped key REDACTED and its non-secret sibling untouched, got %', to_jsonb(v_outcome);
  end if;

  v_outcome := app.record_ai_governed_request_outcome(v_request.id, 'succeeded', jsonb_build_object('draftLines', jsonb_build_array('Freight')), 'high', 'openai-multimodal', 0.05, 'USD', null, v_rep1, 'rep');
  if v_outcome.status <> 'succeeded' or v_outcome.billed_amount <> 0.06 or v_outcome.completed_at is null then
    raise exception 'assertion failed: expected status=succeeded, billed_amount=0.06 (0.05 * 1.20), a real completed_at, got %', to_jsonb(v_outcome);
  end if;

  begin
    perform app.record_ai_governed_request_outcome(v_request.id, 'failed', null, null, null, null, null, 'late failure', v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_governed_request_not_pending -- this request already transitioned to succeeded';
  exception when check_violation then
    if sqlerrm !~ 'ai_governed_request_not_pending' then raise; end if;
  end;

  raise notice 'PASS: record_ai_governed_request_outcome enforces the pending-only transition, rejects a negative cost, redacts (never rejects) a secret-shaped output key, and computes billed_amount at the real RPD-028 markup';
end;
$$;

\echo '>> app.list_ai_governed_requests_for_tenant: AI:View-gated, sees this tenant''s own real requests, supports a feature_code filter; a cross-tenant admin is denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaigov');
  v_rep1 uuid := '00000000-0000-0000-0000-000021000002';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_admin2 uuid := '00000000-0000-0000-0000-000021000005';
  v_count integer;
begin
  perform app.request_ai_governed_action(v_tenant1, v_connection_id, 'eta_prediction', null, null, jsonb_build_object('shipmentRef', 'SHP-1'), v_rep1, 'rep');

  select count(*) into v_count from app.list_ai_governed_requests_for_tenant(v_tenant1, v_rep1);
  if v_count < 2 then
    raise exception 'assertion failed: expected at least 2 real requests for this tenant, got %', v_count;
  end if;

  select count(*) into v_count from app.list_ai_governed_requests_for_tenant(v_tenant1, v_rep1, 'eta_prediction');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 eta_prediction request, got %', v_count;
  end if;

  begin
    perform app.list_ai_governed_requests_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant admin';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: list_ai_governed_requests_for_tenant is AI:View-gated, supports a feature_code filter, and denies a cross-tenant admin';
end;
$$;

\echo '>> app.request_ai_output_approval: refuses a non-succeeded request, then fails cleanly with a named error until the tenant configures its own approval:ai_output_acceptance definition, then succeeds and is only-once'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaigov');
  v_admin1 uuid := '00000000-0000-0000-0000-000021000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000021000002';
  v_approver1 uuid := '00000000-0000-0000-0000-000021000003';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_pending_request app.ai_governed_requests;
  v_succeeded_request app.ai_governed_requests;
  v_appr_draft app.config_versions;
  v_approval_request app.approval_requests;
begin
  v_pending_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'quotation_draft', null, null, jsonb_build_object('origin', 'JKT'), v_rep1, 'rep');

  begin
    perform app.request_ai_output_approval(v_pending_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_governed_request_not_succeeded -- this request is still pending';
  exception when check_violation then
    if sqlerrm !~ 'ai_governed_request_not_succeeded' then raise; end if;
  end;

  v_succeeded_request := app.record_ai_governed_request_outcome(v_pending_request.id, 'succeeded', jsonb_build_object('draftLines', jsonb_build_array('Freight')), 'high', 'openai-multimodal', 0.05, 'USD', null, v_rep1, 'rep');

  begin
    perform app.request_ai_output_approval(v_succeeded_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_output_acceptance_approval_not_configured -- tenant has not configured the approval definition yet';
  exception when check_violation then
    if sqlerrm !~ 'ai_output_acceptance_approval_not_configured' then raise; end if;
  end;

  v_appr_draft := app.create_config_draft('approval:ai_output_acceptance', v_tenant1, 'tenant', null, v_admin1, 'tester');
  perform app.set_config_items(
    v_appr_draft.id,
    jsonb_build_array(
      jsonb_build_object('key', 'pattern', 'value', 'sequential'),
      jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
        jsonb_build_object('step_order', 1, 'approver_type', 'specific_user', 'specific_user_id', v_approver1, 'required_approvals', 1)
      ))
    ),
    v_admin1, 'tester'
  );
  perform app.publish_approval_definition(v_appr_draft.id, v_admin1, now(), 'tester');

  v_approval_request := app.request_ai_output_approval(v_succeeded_request.id, v_rep1, 'rep');
  if v_approval_request.entity_type <> 'ai_governed_output' or v_approval_request.entity_id <> v_succeeded_request.id or v_approval_request.status <> 'pending' then
    raise exception 'assertion failed: expected a real, pending approval request bound to the exact succeeded request, got %', to_jsonb(v_approval_request);
  end if;
  if (select approval_request_id from app.ai_governed_requests where id = v_succeeded_request.id) <> v_approval_request.id then
    raise exception 'assertion failed: expected ai_governed_requests.approval_request_id to be set to the new approval request';
  end if;

  begin
    perform app.request_ai_output_approval(v_succeeded_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_governed_request_approval_already_requested -- this request already has an approval request';
  exception when check_violation then
    if sqlerrm !~ 'ai_governed_request_approval_already_requested' then raise; end if;
  end;

  raise notice 'PASS: request_ai_output_approval refuses a non-succeeded request, fails cleanly until the tenant configures its own approval definition, then succeeds exactly once';
end;
$$;

\echo '>> app.decide_ai_output_approval: folds a step from a foreign (non-ai_governed_output) request into the SAME not-found-shaped error; denies an actor without AI:Approve; succeeds for the real approver and resolves the approval request'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaigov');
  v_rep1 uuid := '00000000-0000-0000-0000-000021000002';
  v_approver1 uuid := '00000000-0000-0000-0000-000021000003';
  v_config_version_id uuid;
  v_foreign_request_id uuid;
  v_foreign_step_id uuid;
  v_request app.ai_governed_requests;
  v_step_id uuid;
  v_step app.approval_request_steps;
begin
  select cv.id into v_config_version_id
  from app.config_objects co
  join app.config_versions cv on cv.config_object_id = co.id and cv.status = 'published'
  where co.config_type_code = 'approval:ai_output_acceptance' and co.tenant_id = v_tenant1;

  -- A foreign approval_requests row of a DIFFERENT entity_type must never be
  -- decidable through this AI-scoped proxy -- mirrors app.decide_automation_
  -- rule_publish_approval's own foreign-request guard db-test (IAE-007).
  insert into app.approval_requests (tenant_id, config_version_id, entity_type, entity_id, pattern, status, idempotency_key, requested_by)
  values (v_tenant1, v_config_version_id, 'some_other_domain', null, 'sequential', 'pending', 'idem-iaeaigov-foreign-request', 'tester')
  returning id into v_foreign_request_id;
  insert into app.approval_request_steps (request_id, step_order, approver_type, specific_user_id, required_approvals, status)
  values (v_foreign_request_id, 1, 'specific_user', v_approver1, 1, 'active')
  returning id into v_foreign_step_id;

  begin
    perform app.decide_ai_output_approval(v_foreign_step_id, 'approved', v_approver1, 'approver');
    raise exception 'assertion failed: expected ai_output_approval_wrong_domain for a step belonging to a non-ai_governed_output request';
  exception when check_violation then
    if sqlerrm !~ 'ai_output_approval_wrong_domain' then raise; end if;
  end;

  select r.* into v_request from app.ai_governed_requests r where r.tenant_id = v_tenant1 and r.approval_request_id is not null order by r.created_at desc limit 1;
  select id into v_step_id from app.approval_request_steps where request_id = v_request.approval_request_id;

  begin
    perform app.decide_ai_output_approval(v_step_id, 'approved', v_rep1, 'rep');
    raise exception 'assertion failed: expected insufficient_authority -- rep holds AI:Create+View but not AI:Approve';
  exception when insufficient_privilege then null;
  end;

  v_step := app.decide_ai_output_approval(v_step_id, 'approved', v_approver1, 'approver', 'looks correct');
  if v_step.status <> 'approved' then
    raise exception 'assertion failed: expected the real step to transition to approved, got %', to_jsonb(v_step);
  end if;
  if (select status from app.approval_requests where id = v_request.approval_request_id) <> 'approved' then
    raise exception 'assertion failed: expected the single-step sequential approval_requests row to resolve to approved';
  end if;

  raise notice 'PASS: decide_ai_output_approval folds a foreign-request step into ai_output_approval_wrong_domain, denies an actor without AI:Approve, and a real AI:Approve actor resolves the approval';
end;
$$;

\echo '>> cross-tenant isolation: a tenant-2 actor cannot dispatch, record, or list against tenant-1''s own AI governance data'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaigov');
  v_admin2 uuid := '00000000-0000-0000-0000-000021000005';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
begin
  begin
    perform app.request_ai_governed_action(v_tenant1, v_connection_id, 'quotation_draft', null, null, jsonb_build_object('origin', 'JKT'), v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority -- admin2 has no membership in tenant1';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.list_ai_governed_requests_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority -- admin2 has no membership in tenant1';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: a cross-tenant actor is denied AI:Create and AI:View authority for a tenant it does not belong to';
end;
$$;

\echo '>> ai-governance-provider-boundary.sql: ALL PASSED'
