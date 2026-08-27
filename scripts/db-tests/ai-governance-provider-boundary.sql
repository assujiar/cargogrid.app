-- Real, executable test evidence for IAE-019 (AI Governance Provider
-- Boundary, Prompt 347) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Scoped to this checkpoint's own additive
-- migration (supabase/migrations/
-- 20260805060000_create_intelligence_ai_governance_provider_boundary.sql).
-- Fresh, distinctive tenant fixture (iaeaigov), fixture id range
-- 00000000-0000-0000-0000-000021xxxxxx.

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors app.vendor_financial_encryption_keys own pattern).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

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

\echo '>> ISS-2026-249 (Track B Batch 1): a genuinely-recorded failure (not a race loser) now raises a real observability alert -- previously this producer never alerted at all'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaigov');
  v_rep1 uuid := '00000000-0000-0000-0000-000021000002';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_failing_request app.ai_governed_requests;
  v_outcome app.ai_governed_requests;
begin
  v_failing_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'quotation_draft', null, null, jsonb_build_object('origin', 'JKT'), v_rep1, 'rep');
  v_outcome := app.record_ai_governed_request_outcome(v_failing_request.id, 'failed', null, null, null, null, null, 'provider timeout', v_rep1, 'rep');
  if v_outcome.status <> 'failed' then
    raise exception 'assertion failed: expected status=failed, got %', v_outcome.status;
  end if;

  if not exists (
    select 1 from app.incidents
    where tenant_id = v_tenant1 and source_type = 'ai' and signal_type = 'error' and severity = 'medium'
      and title like 'AI governed action failed:%'
  ) then
    raise exception 'assertion failed: expected a real app.incidents row (source_type=ai, signal_type=error, medium) after this genuine failure -- ISS-2026-249 regression';
  end if;
end;
$$;

\echo '>> app.record_ai_governed_request_outcome (IAE-037 Tier C fix): also rejects a NaN or Infinity provider_unit_cost_amount, which the original ">= 0" check alone silently admitted (NaN < 0 is false in Postgres numeric ordering) -- a real defense-in-depth gap since a poisoned NaN cost would corrupt a tenant-wide billing SUM'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaigov');
  v_rep1 uuid := '00000000-0000-0000-0000-000021000002';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_request app.ai_governed_requests;
begin
  v_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'quotation_draft', null, null, jsonb_build_object('origin', 'JKT'), v_rep1, 'rep');
  begin
    perform app.record_ai_governed_request_outcome(v_request.id, 'succeeded', jsonb_build_object('draftLines', '[]'::jsonb), 'high', 'openai-multimodal', 'NaN'::numeric, 'USD', null, v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_governed_request_invalid_cost_amount for a NaN cost';
  exception when check_violation then
    if sqlerrm !~ 'ai_governed_request_invalid_cost_amount' then raise; end if;
  end;

  begin
    perform app.record_ai_governed_request_outcome(v_request.id, 'succeeded', jsonb_build_object('draftLines', '[]'::jsonb), 'high', 'openai-multimodal', 'Infinity'::numeric, 'USD', null, v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_governed_request_invalid_cost_amount for an Infinity cost';
  exception when check_violation then
    if sqlerrm !~ 'ai_governed_request_invalid_cost_amount' then raise; end if;
  end;

  -- The request itself must still be genuinely pending -- neither rejected
  -- attempt above may have silently transitioned it.
  if (select status from app.ai_governed_requests where id = v_request.id) <> 'pending' then
    raise exception 'assertion failed: expected the request to remain pending after both rejected cost values';
  end if;

  raise notice 'PASS: record_ai_governed_request_outcome rejects NaN/Infinity provider_unit_cost_amount, never silently transitioning the request';
end;
$$;

\echo '>> app.redact_ai_output_payload_secret_shaped_values (IAE-037 Tier C fix): a deeply nested output_payload no longer crashes with a raw Postgres stack-depth error -- it raises a clean, named ai_output_payload_nesting_too_deep error instead, and the governed request is never silently stranded'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaigov');
  v_rep1 uuid := '00000000-0000-0000-0000-000021000002';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_request app.ai_governed_requests;
  v_deep jsonb := '"leaf"'::jsonb;
  i integer;
begin
  -- 40 levels of nesting -- ordinary, non-malicious AI-provider content can
  -- reach this depth; the un-fixed function crashed with a raw Postgres
  -- 'stack depth limit exceeded' around ~400 levels, live-reproduced by the
  -- adversarial hardening lens. This regression proves the bounded case
  -- (well within the real cap) still works and the over-cap case fails
  -- clean, not with a raw engine crash.
  for i in 1..40 loop
    v_deep := jsonb_build_object('nested', v_deep);
  end loop;

  v_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'quotation_draft', null, null, jsonb_build_object('origin', 'JKT'), v_rep1, 'rep');
  begin
    perform app.record_ai_governed_request_outcome(v_request.id, 'succeeded', v_deep, 'high', 'openai-multimodal', 0.05, 'USD', null, v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_output_payload_nesting_too_deep for a 40-level-deep output_payload (bounded cap is 32)';
  exception when check_violation then
    if sqlerrm !~ 'ai_output_payload_nesting_too_deep' then raise; end if;
  end;

  -- A shallow, ordinary payload (well under the cap) still succeeds normally.
  perform app.record_ai_governed_request_outcome(v_request.id, 'succeeded', jsonb_build_object('draftLines', jsonb_build_array('Freight')), 'high', 'openai-multimodal', 0.05, 'USD', null, v_rep1, 'rep');

  raise notice 'PASS: redact_ai_output_payload_secret_shaped_values bounds recursion to a clean, named error instead of a raw stack-depth crash, while ordinary shallow payloads are unaffected';
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

  perform app.verify_mfa_step_up_challenge((app.request_mfa_step_up_challenge(v_tenant1, 'AI', 'Approve', v_approver1, 'approver')).id, v_approver1, 'approver');
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

\echo '>> ISS-2026-150 closure: app.decide_ai_output_approval now composes app.assert_ip_allowed + app.has_active_ip_allowlist_bypass when a caller supplies p_client_ip -- a fresh, dedicated tenant (iaeaigovip), never touched by any earlier block in this file (which uses iaeaigov/iaeaigov2 for its own, unrelated create_integration_connection fixture calls), so this enforced-mode policy cannot collide with them'
do $$
declare
  v_tenant uuid;
  v_admin uuid := '00000000-0000-0000-0000-000021900000';
  v_rep uuid := '00000000-0000-0000-0000-000021900001';
  v_approver uuid := '00000000-0000-0000-0000-000021900002';
  v_admin_role uuid;
  v_admin_draft app.role_versions;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_approver_role uuid;
  v_approver_draft app.role_versions;
  v_connection_id uuid;
  v_appr_draft app.config_versions;
  v_request app.ai_governed_requests;
  v_succeeded app.ai_governed_requests;
  v_approval_request app.approval_requests;
  v_step_id uuid;
  v_step app.approval_request_steps;
begin
  insert into auth.users (id, email) values
    (v_admin, 'admin@iaeaigovip.test'),
    (v_rep, 'rep@iaeaigovip.test'),
    (v_approver, 'approver@iaeaigovip.test');

  perform app.provision_tenant('iaeaigovip', 'IaeAiGovIp Co', 'idem-iaeaigovip', 'tester');
  v_tenant := (select id from app.tenants where slug = 'iaeaigovip');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant, v_admin, 'admin@iaeaigovip.test', 'Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeaigovip.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin, 'tenant_admin', v_tenant, null, 'tester');

  perform app.invite_user(v_tenant, v_rep, 'rep@iaeaigovip.test', 'Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaeaigovip.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant, v_approver, 'approver@iaeaigovip.test', 'Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@iaeaigovip.test'), 'active', 'onboarded', 'tester');

  -- v_admin's own tenant_admin membership grants config-draft authority (app.check_
  -- config_object_authority / app.is_support_grant_authority) but carries no module
  -- permission of its own -- SEC:Configure needs its own explicit role, same as
  -- integration-hub.sql's own new regression block above establishes.
  v_admin_role := (app.create_role(v_tenant, 'IaeAiGovIp Admin', 'SEC:Configure', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'SEC' and action = 'Configure'), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), v_admin, v_admin, 'admin');

  v_rep_role := (app.create_role(v_tenant, 'IaeAiGovIp Rep', 'AI:Create+View, INTHUB:Configure+View', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'AI' and action in ('Create', 'View')) or (resource_module_code = 'INTHUB' and action in ('Configure', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), v_rep, v_admin, 'admin');

  v_approver_role := (app.create_role(v_tenant, 'IaeAiGovIp Approver', 'AI:Approve+View', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'AI' and action in ('Approve', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), v_approver, v_admin, 'admin');

  v_connection_id := (app.create_integration_connection(v_tenant, 'openai_multimodal', 'OpenAI Multimodal', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://ai.iaeaigovip-provider.test/v1/infer'), 'test-ai-secret', v_rep, 'rep')).id;

  v_appr_draft := app.create_config_draft('approval:ai_output_acceptance', v_tenant, 'tenant', null, v_admin, 'tester');
  perform app.set_config_items(
    v_appr_draft.id,
    jsonb_build_array(
      jsonb_build_object('key', 'pattern', 'value', 'sequential'),
      jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
        jsonb_build_object('step_order', 1, 'approver_type', 'specific_user', 'specific_user_id', v_approver, 'required_approvals', 1)
      ))
    ),
    v_admin, 'tester'
  );
  perform app.publish_approval_definition(v_appr_draft.id, v_admin, now(), 'tester');

  -- Real allowlist entry (203.0.113.0/24, scope admin) plus enforced mode -- mirrors
  -- ip-restriction-network-access.sql's own established setup pattern verbatim.
  perform app.add_ip_allowlist_entry(v_tenant, '203.0.113.0/24', 'iaeaigovip office range', 'admin', v_admin, 'admin');
  perform app.set_ip_allowlist_enforcement_mode(v_tenant, 'enforced', v_admin, 'admin');

  -- One verified step-up challenge stays "current" for the tenant policy's own
  -- step_up_max_age_minutes window (default 15) -- reused across all 3 decide calls
  -- below, exactly the real client behavior this checkpoint composes against.
  perform app.verify_mfa_step_up_challenge((app.request_mfa_step_up_challenge(v_tenant, 'AI', 'Approve', v_approver, 'approver')).id, v_approver, 'approver');

  -- (a) out-of-range p_client_ip -- denied, ip_not_allowed.
  v_request := app.request_ai_governed_action(v_tenant, v_connection_id, 'quotation_draft', null, null, jsonb_build_object('origin', 'JKT'), v_rep, 'rep');
  v_succeeded := app.record_ai_governed_request_outcome(v_request.id, 'succeeded', jsonb_build_object('draftLines', jsonb_build_array('Freight')), 'high', 'openai-multimodal', 0.05, 'USD', null, v_rep, 'rep');
  v_approval_request := app.request_ai_output_approval(v_succeeded.id, v_rep, 'rep');
  select id into v_step_id from app.approval_request_steps where request_id = v_approval_request.id;
  begin
    perform app.decide_ai_output_approval(v_step_id, 'approved', v_approver, 'approver', 'looks correct', '198.51.100.7');
    raise exception 'assertion failed: expected ip_not_allowed for an out-of-range p_client_ip under enforced mode, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlerrm !~ 'ip_not_allowed' then raise; end if;
  end;
  if (select status from app.approval_request_steps where id = v_step_id) <> 'active' then
    raise exception 'assertion failed: the rejected out-of-range-IP attempt must never leave the step transitioned';
  end if;

  -- (b) in-range p_client_ip -- succeeds.
  v_step := app.decide_ai_output_approval(v_step_id, 'approved', v_approver, 'approver', 'looks correct', '203.0.113.42');
  if v_step.status <> 'approved' then
    raise exception 'assertion failed: expected the step to transition to approved for an in-range p_client_ip, got %', to_jsonb(v_step);
  end if;

  -- (c) p_client_ip omitted/null -- succeeds regardless of the enforced policy, proving
  -- the non-interactive-caller exemption. A fresh request/outcome/approval cycle is
  -- needed since the one above already resolved.
  v_request := app.request_ai_governed_action(v_tenant, v_connection_id, 'quotation_draft', null, null, jsonb_build_object('origin', 'JKT'), v_rep, 'rep');
  v_succeeded := app.record_ai_governed_request_outcome(v_request.id, 'succeeded', jsonb_build_object('draftLines', jsonb_build_array('Freight')), 'high', 'openai-multimodal', 0.05, 'USD', null, v_rep, 'rep');
  v_approval_request := app.request_ai_output_approval(v_succeeded.id, v_rep, 'rep');
  select id into v_step_id from app.approval_request_steps where request_id = v_approval_request.id;
  v_step := app.decide_ai_output_approval(v_step_id, 'approved', v_approver, 'approver', 'looks correct');
  if v_step.status <> 'approved' then
    raise exception 'assertion failed: expected the step to transition to approved when p_client_ip is omitted, regardless of the enforced IP allowlist policy, got %', to_jsonb(v_step);
  end if;

  raise notice 'PASS: app.decide_ai_output_approval (ISS-2026-150 closure) denies an out-of-range p_client_ip under enforced mode, allows an in-range one, and allows a null p_client_ip regardless of enforcement';
end;
$$;

\echo '>> ai-governance-provider-boundary.sql: ALL PASSED'
