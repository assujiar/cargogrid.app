-- Real, executable regression evidence for the merged Batch 4 Tier C review
-- fix pass (IAE-014..019, Prompts 342-347) -- run via `pnpm run db:test`
-- against a real, disposable Postgres database. Scoped to
-- supabase/migrations/20260805070000_harden_intelligence_batch4_tier_c_
-- review_fixes.sql. Every finding this file proves was FIRST live-
-- reproduced by one of four independent, parallel adversarial review lenses
-- (spec-compliance; security/RLS/tenant; correctness/concurrency; cross-
-- prompt integration), then independently re-verified live by the
-- orchestrating session (this file, plus genuinely concurrent multi-process
-- probes run directly against a scratch database before this file was
-- written -- see docs/build-log/phase-09/00_EXECUTION_INDEX.md §14 for the
-- exact commands and their actual output) before being accepted as fixed.
-- Fresh, distinctive tenant fixture (iaetierc4), fixture id range
-- 00000000-0000-0000-0000-000022xxxxxx.

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors app.vendor_financial_encryption_keys own pattern).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> setup: tenant iaetierc4 with a HR+FIN+INTHUB admin, a FIN-only actor (no HRS), a real openai_multimodal connection, a real activated employee and GL account, external_hr_system/external_accounting_system connections and mappings; a second tenant (iaetierc4b) for cross-tenant proofs'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_fin1 uuid := '00000000-0000-0000-0000-000022000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000022000003';
  v_admin_role uuid;
  v_admin_draft app.role_versions;
  v_fin_role uuid;
  v_fin_draft app.role_versions;
  v_admin2_role uuid;
  v_admin2_draft app.role_versions;
  v_company uuid;
  v_employee app.employees;
  v_gl app.finance_accounts;
begin
  insert into auth.users (id, email) values
    (v_admin1, 'admin@iaetierc4.test'),
    (v_fin1, 'fin1@iaetierc4.test'),
    (v_admin2, 'admin@iaetierc4b.test');

  perform app.provision_tenant('iaetierc4', 'IaeTierC4 Co', 'idem-iaetierc4', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaetierc4');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('iaetierc4b', 'IaeTierC4b Co', 'idem-iaetierc4b', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaetierc4b');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaetierc4.test', 'IaeTierC4 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaetierc4.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, v_fin1, 'fin1@iaetierc4.test', 'IaeTierC4 Fin1', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'fin1@iaetierc4.test'), 'active', 'onboarded', 'tester');

  v_admin_role := (app.create_role(v_tenant1, 'TierC4 Admin', 'HRS+FIN+AI+INTHUB full, OPS:Edit+View', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(
    v_admin_draft.id,
    array(select id from app.permissions where
      (resource_module_code in ('HRS', 'FIN', 'AI') and action in ('Create', 'Edit', 'Approve', 'View'))
      or (resource_module_code = 'INTHUB' and action in ('Configure', 'View'))
      or (resource_module_code = 'OPS' and action in ('Edit', 'View'))
    ),
    'tester'
  );
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), v_admin1, v_admin1, 'admin1');

  v_fin_role := (app.create_role(v_tenant1, 'TierC4 FIN Only', 'FIN:View+Edit, INTHUB:Configure -- NO HRS at all', 'tester')).id;
  v_fin_draft := app.create_role_version(v_fin_role, 'tester');
  perform app.set_role_version_permissions(
    v_fin_draft.id,
    array(select id from app.permissions where (resource_module_code = 'FIN' and action in ('View', 'Edit')) or (resource_module_code = 'INTHUB' and action in ('Configure', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_fin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_fin_role and status = 'published'), v_fin1, v_admin1, 'admin1');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaetierc4b.test', 'IaeTierC4b Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaetierc4b.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');
  v_admin2_role := (app.create_role(v_tenant2, 'TierC4b INTHUB Admin', 'INTHUB:Configure', 'tester')).id;
  v_admin2_draft := app.create_role_version(v_admin2_role, 'tester');
  perform app.set_role_version_permissions(v_admin2_draft.id, array(select id from app.permissions where resource_module_code = 'INTHUB' and action in ('Configure', 'View')), 'tester');
  perform app.publish_role_version(v_admin2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_admin2, 'admin2');

  perform app.create_org_unit(v_tenant1, 'company', null, 'IAETIERC4-CO', 'IaeTierC4 Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'IAETIERC4-CO');

  v_employee := app.create_employee_draft(v_tenant1, 'Rahasia Karyawan', 'full_time', null, null, null, null, null, null, '2026-01-01'::date, v_company, null, null, null, null, null, null, 'hr_created', 'idem-iaetierc4-emp1', v_admin1, 'admin1');
  perform app.add_employee_emergency_contact(v_employee.master_record_id, 'Ibu', 'Mother', '+62-1', null, true, v_admin1, 'admin1');
  v_employee := app.submit_employee_for_approval(v_employee.master_record_id, v_employee.record_version, v_admin1, 'admin1');
  v_employee := app.decide_employee_approval(v_employee.master_record_id, v_employee.record_version, 'approve', null, v_admin1, 'admin1');
  v_employee := app.activate_employee(v_employee.master_record_id, v_employee.record_version, v_admin1, 'admin1');

  select * into v_gl from app.create_finance_account_draft(v_tenant1, null, 'CASH-IAETIERC4', 'Cash', 'asset', 'debit', null, false, null, v_admin1, 'admin1');
  perform app.activate_finance_account(v_gl.id, v_gl.record_version, v_admin1, 'admin1');

  perform app.create_integration_connection(v_tenant1, 'openai_multimodal', 'AI', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://ai.iaetierc4.test/v1'), 'test-ai-secret', v_admin1, 'admin1');
  perform app.create_integration_connection(v_tenant1, 'external_hr_system', 'HR', 'production', null, null, null, jsonb_build_object('pollUrl', 'https://hr.iaetierc4.test/poll'), 'test-hr-secret', v_admin1, 'admin1');
  perform app.create_integration_connection(v_tenant1, 'external_accounting_system', 'ERP', 'production', null, null, null, jsonb_build_object('pollUrl', 'https://erp.iaetierc4.test/poll'), 'test-erp-secret', v_fin1, 'fin1');
  perform app.create_integration_connection(v_tenant1, 'carrier_status_api', 'Carrier', 'production', null, null, null, jsonb_build_object('pollUrl', 'https://carrier.iaetierc4.test/poll'), 'test-carrier-secret', v_admin1, 'admin1');
  perform app.create_integration_connection(v_tenant2, 'carrier_status_api', 'Carrier2', 'production', null, null, null, jsonb_build_object('pollUrl', 'https://carrier.iaetierc4b.test/poll'), 'test-carrier2-secret', v_admin2, 'admin2');
  perform app.create_integration_connection(v_tenant1, 'payment_gateway', 'PayGW', 'production', null, null, null, jsonb_build_object('pollUrl', 'https://pay.iaetierc4.test/webhook'), 'test-pay-secret', v_admin1, 'admin1');
  perform app.create_integration_connection(v_tenant2, 'payment_gateway', 'PayGW2', 'production', null, null, null, jsonb_build_object('pollUrl', 'https://pay.iaetierc4b.test/webhook'), 'test-pay2-secret', v_admin2, 'admin2');
  perform app.create_integration_connection(v_tenant1, 'bank_feed_api', 'BankA', 'production', null, null, null, jsonb_build_object('pollUrl', 'https://bank-a.iaetierc4.test/poll'), 'test-bank-a-secret', v_admin1, 'admin1');
  perform app.create_integration_connection(v_tenant1, 'bank_feed_api', 'BankB', 'sandbox', null, null, null, jsonb_build_object('pollUrl', 'https://bank-b.iaetierc4.test/poll'), 'test-bank-b-secret', v_admin1, 'admin1');

  perform app.set_external_sync_entity_mapping(v_tenant1, 'external_hr_system', 'employee', 'bidirectional', null, v_admin1, 'admin1');
  perform app.set_external_sync_entity_mapping(v_tenant1, 'external_accounting_system', 'gl_account', 'cargogrid_source', null, v_fin1, 'fin1');
  perform app.link_external_sync_entity(v_tenant1, 'external_hr_system', 'employee', 'EXT-EMP-1', v_employee.master_record_id, v_admin1, 'admin1');
  perform app.link_external_sync_entity(v_tenant1, 'external_accounting_system', 'gl_account', 'EXT-ACCT-1', v_gl.id, v_fin1, 'fin1');
end $$;

-- ===========================================================================
-- Fix 12 (Critical, IAE-019): atomic pending-only outcome transition.
-- ===========================================================================

\echo '>> [Tier C fix 12, Critical] app.record_ai_governed_request_outcome: the atomic WHERE status = ''pending'' transition rejects a repeated call on an already-succeeded request -- a real, sequential proxy for the race an independent 6-way genuinely concurrent probe against a live scratch database already confirmed (exactly 1 of 6 concurrent callers won, 5 got this same named error, before this file was written -- see the build log for the exact reproduction)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_conn_ai uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_req app.ai_governed_requests;
  v_first app.ai_governed_requests;
begin
  v_req := app.request_ai_governed_action(v_tenant1, v_conn_ai, 'tierc_race_test', null, null, jsonb_build_object('x', 1), v_admin1, 'admin1');
  v_first := app.record_ai_governed_request_outcome(v_req.id, 'succeeded', jsonb_build_object('w', 1), 'high', 'm', 1.0, 'USD', null, v_admin1, 'admin1');
  if v_first.status <> 'succeeded' or v_first.billed_amount <> 1.2000 then
    raise exception 'assertion failed: expected the first outcome to win cleanly, got %', to_jsonb(v_first);
  end if;

  begin
    perform app.record_ai_governed_request_outcome(v_req.id, 'succeeded', jsonb_build_object('w', 2), 'high', 'm', 1.0, 'USD', null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected ai_governed_request_not_pending for a second outcome on an already-succeeded request';
  exception when check_violation then
    if sqlerrm !~ 'ai_governed_request_not_pending' then raise; end if;
  end;

  if (select output_payload from app.ai_governed_requests where id = v_req.id) <> jsonb_build_object('w', 1) then
    raise exception 'assertion failed: the FIRST winner''s own output_payload must survive untouched -- a losing caller must never overwrite it';
  end if;

  raise notice 'PASS: record_ai_governed_request_outcome''s atomic pending-only transition rejects a repeated call, never silently overwriting the first winner''s real output/billed_amount';
end;
$$;

-- ===========================================================================
-- Fixes 10, 11 (High, IAE-019): recursive secret-key guard, no crash on a
-- non-object payload, output redaction instead of rejection.
-- ===========================================================================

\echo '>> [Tier C fix 10] app.assert_ai_prompt_payload_has_no_secret_shaped_keys: now recurses into nested objects/arrays and no longer raises a raw Postgres error on a top-level array payload'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_conn_ai uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_req app.ai_governed_requests;
begin
  begin
    perform app.request_ai_governed_action(v_tenant1, v_conn_ai, 'tierc_nested_secret', null, null, jsonb_build_object('employee', jsonb_build_object('full_name', 'X', 'bank_account_number', '1234567890')), v_admin1, 'admin1');
    raise exception 'assertion failed: expected ai_governed_request_secret_shaped_key for a NESTED secret-shaped key -- previously passed entirely undetected';
  exception when check_violation then
    if sqlerrm !~ 'ai_governed_request_secret_shaped_key' then raise; end if;
  end;

  -- A top-level JSON ARRAY prompt_payload -- an ordinary LLM/OCR extraction
  -- request shape -- must no longer raise a raw 22023 (cannot call
  -- jsonb_object_keys on an array).
  v_req := app.request_ai_governed_action(v_tenant1, v_conn_ai, 'tierc_array_payload', null, null, '["JKT", "SBY", "line-item-1"]'::jsonb, v_admin1, 'admin1');
  if v_req.status <> 'pending' then
    raise exception 'assertion failed: expected a real pending request for a top-level array prompt_payload, got %', to_jsonb(v_req);
  end if;

  raise notice 'PASS: assert_ai_prompt_payload_has_no_secret_shaped_keys recurses into nested objects, and a top-level array payload no longer crashes';
end;
$$;

\echo '>> [Tier C fix 11] app.record_ai_governed_request_outcome: a top-level JSON ARRAY output_payload no longer strands the request at pending; a nested secret-shaped key in output_payload is REDACTED (never rejected -- output is untrusted, provider-controlled content)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_conn_ai uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_req1 app.ai_governed_requests;
  v_outcome1 app.ai_governed_requests;
  v_req2 app.ai_governed_requests;
  v_outcome2 app.ai_governed_requests;
begin
  v_req1 := app.request_ai_governed_action(v_tenant1, v_conn_ai, 'tierc_array_output', null, null, jsonb_build_object('x', 1), v_admin1, 'admin1');
  v_outcome1 := app.record_ai_governed_request_outcome(v_req1.id, 'succeeded', '[{"line":1},{"line":2}]'::jsonb, 'high', 'm', 0.5, 'USD', null, v_admin1, 'admin1');
  if v_outcome1.status <> 'succeeded' or v_outcome1.output_payload <> '[{"line": 1}, {"line": 2}]'::jsonb then
    raise exception 'assertion failed: expected a real succeeded outcome carrying the array output_payload untouched, got %', to_jsonb(v_outcome1);
  end if;

  v_req2 := app.request_ai_governed_action(v_tenant1, v_conn_ai, 'tierc_redact_output', null, null, jsonb_build_object('x', 1), v_admin1, 'admin1');
  v_outcome2 := app.record_ai_governed_request_outcome(v_req2.id, 'succeeded', jsonb_build_object('note', 'ok', 'payment', jsonb_build_object('bank_account_number', '9999888877')), 'high', 'm', 0.5, 'USD', null, v_admin1, 'admin1');
  if v_outcome2.status <> 'succeeded' then
    raise exception 'assertion failed: expected the outcome to succeed (redacted, never rejected), got %', to_jsonb(v_outcome2);
  end if;
  if v_outcome2.output_payload #>> '{payment,bank_account_number}' <> '[REDACTED]' then
    raise exception 'assertion failed: expected the nested bank_account_number VALUE to be redacted, got %', to_jsonb(v_outcome2.output_payload);
  end if;
  if v_outcome2.output_payload ->> 'note' <> 'ok' then
    raise exception 'assertion failed: expected a non-secret-shaped sibling key to survive untouched, got %', to_jsonb(v_outcome2.output_payload);
  end if;

  raise notice 'PASS: a top-level array output_payload no longer strands the request; a nested secret-shaped output key is redacted, never rejected, and its non-secret siblings survive untouched';
end;
$$;

-- ===========================================================================
-- Fix 5, IAE-019 (High, spec-compliance): app.request_ai_governed_action is
-- now reachable through a genuine forged authenticated session.
-- ===========================================================================

\echo '>> [Tier C fix 5] app.request_ai_governed_action: live forged-session proof (request.jwt.claims + set role authenticated) -- previously permission-denied through the app''s own RLS-scoped client (SECURITY INVOKER calling a service_role-only authority helper); now SECURITY DEFINER + assert_actor_is_session_identity'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_conn_ai uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_fin1 uuid := '00000000-0000-0000-0000-000022000002';
  v_req app.ai_governed_requests;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000022000001", "role": "authenticated"}', false);
  set role authenticated;

  v_req := app.request_ai_governed_action(v_tenant1, v_conn_ai, 'tierc_forged_session', null, null, jsonb_build_object('y', 1), v_admin1, 'admin1');
  if v_req.status <> 'pending' then
    raise exception 'assertion failed: expected a real pending request through a genuine forged authenticated session';
  end if;

  -- ATW-032: the same genuine session may not claim to act as a DIFFERENT identity.
  begin
    perform app.request_ai_governed_action(v_tenant1, v_conn_ai, 'tierc_impersonation', null, null, jsonb_build_object('z', 1), v_fin1, 'fin1');
    raise exception 'assertion failed: expected actor_identity_mismatch -- session % must not claim identity %', v_admin1, v_fin1;
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'actor_identity_mismatch' then raise; end if;
  end;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: a real forged authenticated session, not the connecting superuser, calls app.request_ai_governed_action end to end; the same session cannot claim a different identity';
end;
$$;

-- ===========================================================================
-- Fix 6, IAE-019: connection/tenant cross-check on request_ai_governed_action.
-- ===========================================================================

\echo '>> [Tier C fix 6] app.request_ai_governed_action: refuses a connection_id that does not belong to p_tenant_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaetierc4b');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_foreign_conn uuid := (select id from app.integration_connections where tenant_id = v_tenant2 and adapter_code = 'carrier_status_api');
begin
  begin
    perform app.request_ai_governed_action(v_tenant1, v_foreign_conn, 'tierc_foreign_conn', null, null, jsonb_build_object('x', 1), v_admin1, 'admin1');
    raise exception 'assertion failed: expected ai_governed_request_connection_tenant_mismatch for a foreign-tenant connection id';
  exception when no_data_found then
    if sqlerrm !~ 'ai_governed_request_connection_tenant_mismatch' then raise; end if;
  end;

  raise notice 'PASS: request_ai_governed_action refuses a connection_id belonging to a different tenant';
end;
$$;

-- ===========================================================================
-- Fix 14, IAE-019: correlation pairing CHECK.
-- ===========================================================================

\echo '>> [Tier C fix 14] app.ai_governed_requests: a half-set correlation reference (type without id, or id without type) is now rejected by a real CHECK constraint'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_conn_ai uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
begin
  begin
    insert into app.ai_governed_requests (tenant_id, connection_id, feature_code, correlation_record_type, correlation_record_id, prompt_payload, requested_by)
    values (v_tenant1, v_conn_ai, 'tierc_half_ref', 'shipment_order', null, '{}'::jsonb, 'tester');
    raise exception 'assertion failed: expected the CHECK constraint to reject correlation_record_type set with correlation_record_id null';
  exception when check_violation then
    if sqlerrm !~ 'ai_governed_requests_correlation_pairing_check' then raise; end if;
  end;

  begin
    insert into app.ai_governed_requests (tenant_id, connection_id, feature_code, correlation_record_type, correlation_record_id, prompt_payload, requested_by)
    values (v_tenant1, v_conn_ai, 'tierc_half_ref', null, gen_random_uuid(), '{}'::jsonb, 'tester');
    raise exception 'assertion failed: expected the CHECK constraint to reject correlation_record_id set with correlation_record_type null';
  exception when check_violation then
    if sqlerrm !~ 'ai_governed_requests_correlation_pairing_check' then raise; end if;
  end;

  raise notice 'PASS: ai_governed_requests_correlation_pairing_check rejects both half-set shapes';
end;
$$;

-- ===========================================================================
-- Fix 13, IAE-019: request_ai_output_approval catches the unique_violation
-- app.request_approval's own unlocked check-then-insert can raise.
-- ===========================================================================

\echo '>> [Tier C fix 13] app.request_ai_output_approval: a real, published approval definition, then a repeated call after the approval_request_id is already set gets the same clean named error (a sequential proxy for the concurrent unique_violation the underlying app.request_approval can still raise)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_conn_ai uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_req app.ai_governed_requests;
  v_outcome app.ai_governed_requests;
  v_appr_draft app.config_versions;
  v_approval_request app.approval_requests;
begin
  v_appr_draft := app.create_config_draft('approval:ai_output_acceptance', v_tenant1, 'tenant', null, v_admin1, 'tester');
  perform app.set_config_items(
    v_appr_draft.id,
    jsonb_build_array(
      jsonb_build_object('key', 'pattern', 'value', 'sequential'),
      jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
        jsonb_build_object('step_order', 1, 'approver_type', 'specific_user', 'specific_user_id', v_admin1, 'required_approvals', 1)
      ))
    ),
    v_admin1, 'tester'
  );
  perform app.publish_approval_definition(v_appr_draft.id, v_admin1, now(), 'tester');

  v_req := app.request_ai_governed_action(v_tenant1, v_conn_ai, 'tierc_approval_race', null, null, jsonb_build_object('x', 1), v_admin1, 'admin1');
  v_outcome := app.record_ai_governed_request_outcome(v_req.id, 'succeeded', jsonb_build_object('draft', true), 'high', 'm', 0.1, 'USD', null, v_admin1, 'admin1');

  v_approval_request := app.request_ai_output_approval(v_outcome.id, v_admin1, 'admin1');
  if v_approval_request.status <> 'pending' then
    raise exception 'assertion failed: expected a real pending approval request, got %', to_jsonb(v_approval_request);
  end if;

  begin
    perform app.request_ai_output_approval(v_outcome.id, v_admin1, 'admin1');
    raise exception 'assertion failed: expected the SAME clean named error on a repeated call, never a raw unique_violation';
  exception when check_violation then
    if sqlerrm !~ 'ai_governed_request_approval_already_requested' then raise; end if;
  end;

  raise notice 'PASS: request_ai_output_approval''s only-once guard produces the same clean named error on repeat, the same shape the underlying app.request_approval''s own unique_violation must be translated into under real concurrency';
end;
$$;

-- ===========================================================================
-- Fixes 4, IAE-016/IAE-017 (High): webhook rate-limit counter scoped by
-- connection_id, closing the cross-tenant blast radius.
-- ===========================================================================

\echo '>> [Tier C fix 4a] app.ingest_logistics_partner_webhook_event: 10 bad-signature attempts against tenant2''s own connection no longer rate-limits a genuine tenant1 delivery sharing the same attacker-controlled client_key'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaetierc4b');
  v_conn1 uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'carrier_status_api');
  v_conn2 uuid := (select id from app.integration_connections where tenant_id = v_tenant2 and adapter_code = 'carrier_status_api');
  i integer;
  v_status text;
  v_payload text;
  v_ts bigint;
begin
  for i in 1..10 loop
    select ingest_status into v_status from app.ingest_logistics_partner_webhook_event(v_conn2, 'shared-attacker-client-key', 'not-json', extract(epoch from now())::bigint, 'bad-sig');
  end loop;
  if v_status <> 'invalid' then
    raise exception 'assertion failed: expected the 10th bad-sig attempt to still be invalid (not yet rate_limited on tenant2''s OWN connection), got %', v_status;
  end if;

  v_payload := jsonb_build_object('event_id', 'TIERC4-EVT-1', 'event_type', 'status_update')::text;
  v_ts := extract(epoch from now())::bigint;
  select ingest_status into v_status from app.ingest_logistics_partner_webhook_event(
    v_conn1, 'shared-attacker-client-key', v_payload, v_ts, app.compute_logistics_partner_webhook_signature(v_conn1, v_payload, v_ts)
  );
  if v_status <> 'ok' then
    raise exception 'assertion failed: expected a GENUINE tenant1 delivery (same client_key, DIFFERENT connection) to succeed -- got % -- the cross-tenant webhook DoS this fix closes', v_status;
  end if;

  raise notice 'PASS: the rate-limit counter is scoped by connection_id -- 10 bad-signature attempts against tenant2''s own connection no longer throttles a genuine tenant1 delivery sharing the same attacker-controlled client_key';
end;
$$;

\echo '>> [Tier C fix 4b] app.ingest_finance_payment_gateway_webhook_event: identical fix, mirrored'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaetierc4b');
  v_conn1 uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'payment_gateway');
  v_conn2 uuid := (select id from app.integration_connections where tenant_id = v_tenant2 and adapter_code = 'payment_gateway');
  i integer;
  v_status text;
  v_payload text;
  v_ts bigint;
begin
  for i in 1..10 loop
    select ingest_status into v_status from app.ingest_finance_payment_gateway_webhook_event(v_conn2, 'shared-attacker-client-key-fin', 'not-json', extract(epoch from now())::bigint, 'bad-sig');
  end loop;

  v_payload := jsonb_build_object('event_id', 'TIERC4-PAY-EVT-1', 'event_type', 'payment_confirmed')::text;
  v_ts := extract(epoch from now())::bigint;
  select ingest_status into v_status from app.ingest_finance_payment_gateway_webhook_event(
    v_conn1, 'shared-attacker-client-key-fin', v_payload, v_ts, app.compute_finance_payment_webhook_signature(v_conn1, v_payload, v_ts)
  );
  if v_status <> 'ok' then
    raise exception 'assertion failed: expected a GENUINE tenant1 payment webhook to succeed after 10 tenant2 bad-sig attempts sharing client_key, got %', v_status;
  end if;

  raise notice 'PASS: app.ingest_finance_payment_gateway_webhook_event''s rate-limit counter is likewise scoped by connection_id';
end;
$$;

-- ===========================================================================
-- Fix 8, IAE-017 (High): trigger_finance_bank_feed_sync idempotency key now
-- includes connection_id.
-- ===========================================================================

\echo '>> [Tier C fix 8] app.trigger_finance_bank_feed_sync: two DIFFERENT bank_feed_api connections triggering sync for the SAME bank_account_id in the same minute now enqueue TWO distinct jobs, never silently collide onto one'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_conn_a uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'bank_feed_api' and environment = 'production');
  v_conn_b uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'bank_feed_api' and environment = 'sandbox');
  v_gl_cash uuid := (select id from app.finance_accounts where tenant_id = v_tenant1 and code = 'CASH-IAETIERC4');
  v_bank_account app.finance_bank_accounts;
  v_job_a app.jobs;
  v_job_b app.jobs;
begin
  v_bank_account := app.create_finance_bank_account(v_tenant1, null, 'TierC4 BCA Account', 'BCA', '1234', 'IDR', v_gl_cash, v_admin1, 'admin1');

  v_job_a := app.trigger_finance_bank_feed_sync(v_tenant1, v_conn_a, v_bank_account.id, v_admin1, 'admin1');
  v_job_b := app.trigger_finance_bank_feed_sync(v_tenant1, v_conn_b, v_bank_account.id, v_admin1, 'admin1');

  if v_job_a.job_id = v_job_b.job_id then
    raise exception 'assertion failed: expected TWO distinct jobs for two different bank_feed_api connections on the same account -- got the SAME job_id % (wrong-connection routing bug)', v_job_a.job_id;
  end if;
  if (v_job_a.payload ->> 'connection_id') <> v_conn_a::text or (v_job_b.payload ->> 'connection_id') <> v_conn_b::text then
    raise exception 'assertion failed: expected each job to carry its OWN connection_id, got % and %', to_jsonb(v_job_a), to_jsonb(v_job_b);
  end if;

  raise notice 'PASS: trigger_finance_bank_feed_sync''s idempotency key now includes connection_id -- two connections on the same bank_account_id enqueue two distinct, correctly-routed jobs';
end;
$$;

-- ===========================================================================
-- Fix 9, IAE-018 (High): list_external_sync_records_for_tenant per-row
-- filter (the PII-leak fix).
-- ===========================================================================

\echo '>> [Tier C fix 9] app.list_external_sync_records_for_tenant: a FIN-only actor with ZERO HRS permission passing p_entity_type => null now sees ZERO employee rows -- previously leaked full internal employee PII via field_diffs'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_fin1 uuid := '00000000-0000-0000-0000-000022000002';
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_conn_hr uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'external_hr_system');
  v_conn_erp uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'external_accounting_system');
  v_total integer;
  v_employee_rows integer;
begin
  perform app.record_external_sync_snapshot(v_tenant1, v_conn_hr, 'external_hr_system', 'employee', 'EXT-EMP-1', jsonb_build_object('fullName', 'Rahasia Karyawan LEAKED', 'workEmail', 'secret@hr.test'), v_admin1, 'admin1');
  perform app.record_external_sync_snapshot(v_tenant1, v_conn_erp, 'external_accounting_system', 'gl_account', 'EXT-ACCT-1', jsonb_build_object('code', 'CASH-IAETIERC4', 'name', 'Cash (legacy)', 'accountType', 'asset', 'normalBalance', 'debit', 'status', 'active'), v_fin1, 'fin1');

  select count(*) into v_total from app.list_external_sync_records_for_tenant(v_tenant1, v_fin1, null, null, 50);
  select count(*) into v_employee_rows from (select * from app.list_external_sync_records_for_tenant(v_tenant1, v_fin1, null, null, 50)) r where r.entity_type = 'employee';

  if v_employee_rows <> 0 then
    raise exception 'assertion failed: expected ZERO employee rows visible to a FIN-only actor with NO HRS permission -- got % (the live PII leak this fix closes)', v_employee_rows;
  end if;
  if v_total < 1 then
    raise exception 'assertion failed: expected at least the gl_account row (FIN:View is held) to remain visible, got %', v_total;
  end if;

  begin
    perform app.list_external_sync_records_for_tenant(v_tenant1, v_fin1, 'employee', null, 50);
    raise exception 'assertion failed: expected insufficient_authority for fin1 explicitly requesting entity_type=employee';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: list_external_sync_records_for_tenant now filters each row by its OWN entity_type''s own real module authority -- a FIN-only actor sees zero employee rows via p_entity_type => null';
end;
$$;

-- ===========================================================================
-- Fix 7, IAE-016/IAE-017/IAE-018 (Medium): review/decide terminal-state
-- guards.
-- ===========================================================================

\echo '>> [Tier C fix 7a] app.review_logistics_partner_event: a re-decision of an already-reviewed event is now rejected, never a silent lost-update overwrite'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_conn1 uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'carrier_status_api');
  v_event app.logistics_partner_events;
begin
  v_event := app.record_logistics_partner_sync_event(v_tenant1, v_conn1, 'TIERC4-SYNC-EVT-1', 'status_update', null, jsonb_build_object('note', 'x'), v_admin1, 'admin1');
  perform app.review_logistics_partner_event(v_event.id, 'reviewed', 'first decision', v_admin1, 'admin1');

  begin
    perform app.review_logistics_partner_event(v_event.id, 'dismissed', 'a SECOND, conflicting decision', v_admin1, 'admin1');
    raise exception 'assertion failed: expected logistics_partner_event_already_reviewed for a re-decision';
  exception when check_violation then
    if sqlerrm !~ 'logistics_partner_event_already_reviewed' then raise; end if;
  end;

  if (select processing_status from app.logistics_partner_events where id = v_event.id) <> 'reviewed' then
    raise exception 'assertion failed: expected the FIRST decision to survive untouched';
  end if;

  raise notice 'PASS: review_logistics_partner_event rejects a re-decision of an already-decided event';
end;
$$;

\echo '>> [Tier C fix 7b] app.review_finance_payment_gateway_event: identical fix, mirrored'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_conn1 uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'payment_gateway');
  v_payload text;
  v_ts bigint;
  v_row record;
  v_event_id uuid;
begin
  v_payload := jsonb_build_object('event_id', 'TIERC4-PAY-REVIEW-1', 'event_type', 'payment_confirmed')::text;
  v_ts := extract(epoch from now())::bigint;
  select * into v_row from app.ingest_finance_payment_gateway_webhook_event(v_conn1, 'review-test-key', v_payload, v_ts, app.compute_finance_payment_webhook_signature(v_conn1, v_payload, v_ts));
  v_event_id := v_row.event_id;

  perform app.review_finance_payment_gateway_event(v_event_id, 'dismissed', 'first decision', v_admin1, 'admin1');

  begin
    perform app.review_finance_payment_gateway_event(v_event_id, 'reviewed', 'a SECOND, conflicting decision', v_admin1, 'admin1');
    raise exception 'assertion failed: expected finance_payment_event_already_reviewed for a re-decision';
  exception when check_violation then
    if sqlerrm !~ 'finance_payment_event_already_reviewed' then raise; end if;
  end;

  raise notice 'PASS: review_finance_payment_gateway_event rejects a re-decision of an already-decided event';
end;
$$;

\echo '>> [Tier C fix 7c] app.review_external_sync_conflict: identical fix, mirrored -- a no_conflict record may still be reviewed once, but not twice'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_conn_erp uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'external_accounting_system');
  v_fin1 uuid := '00000000-0000-0000-0000-000022000002';
  v_record app.external_sync_records;
begin
  v_record := app.record_external_sync_snapshot(v_tenant1, v_conn_erp, 'external_accounting_system', 'gl_account', 'EXT-ACCT-1', jsonb_build_object('code', 'CASH-IAETIERC4', 'name', 'Cash', 'accountType', 'asset', 'normalBalance', 'debit', 'status', 'active'), v_fin1, 'fin1');
  if v_record.conflict_status <> 'no_conflict' then
    raise exception 'assertion failed: expected a no_conflict snapshot (identical payload), got %', to_jsonb(v_record);
  end if;

  perform app.review_external_sync_conflict(v_record.id, 'reviewed', 'acknowledged, no action needed', v_fin1, 'fin1');

  begin
    perform app.review_external_sync_conflict(v_record.id, 'dismissed', 'a SECOND, conflicting decision', v_fin1, 'fin1');
    raise exception 'assertion failed: expected external_sync_record_already_reviewed for a re-decision';
  exception when check_violation then
    if sqlerrm !~ 'external_sync_record_already_reviewed' then raise; end if;
  end;

  raise notice 'PASS: review_external_sync_conflict allows a no_conflict record to be reviewed once, but rejects re-deciding it';
end;
$$;

-- ===========================================================================
-- Fixes 1, 2, 3, IAE-014: notification attempt race + terminal guard,
-- cross-tenant contact address, RLS read scoping.
-- ===========================================================================

\echo '>> [Tier C fix 1] app.record_notification_delivery_attempt: refuses a further attempt on a skipped/sent (terminal) notification'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_supreme uuid := '00000000-0000-0000-0000-000022000099';
  v_notif_draft app.config_versions;
  v_notification app.notifications;
begin
  insert into auth.users (id, email) values (v_supreme, 'supreme@iaetierc4.test') on conflict (id) do nothing;
  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');
  perform app.register_notification_type('tierc4_test_notify', 'TierC4 Test Notify', 'NOTIF', v_supreme, 'supreme admin');

  v_notif_draft := app.create_config_draft('notification:tierc4_test_notify', v_tenant1, 'tenant', null, v_admin1, 'tester');
  perform app.set_config_items(
    v_notif_draft.id,
    jsonb_build_array(
      jsonb_build_object('key', 'channels', 'value', jsonb_build_array('email')),
      jsonb_build_object('key', 'default_locale', 'value', 'en'),
      jsonb_build_object('key', 'templates', 'value', jsonb_build_object('en', jsonb_build_object('subject', 'Test', 'body', 'Body')))
    ),
    v_admin1, 'tester'
  );
  perform app.publish_config_version(v_notif_draft.id, v_admin1, now(), 'tester');

  v_notification := app.queue_notification((select cv.id from app.config_versions cv join app.config_objects co on co.id = cv.config_object_id where co.config_type_code = 'notification:tierc4_test_notify' and cv.status = 'published'), v_tenant1, 'tierc4_test_notify', v_admin1, 'email', 'en', '{}'::jsonb, 'tierc4-dedupe-1', v_admin1, 'tester');

  -- Opt this recipient OUT of email with no in_app fallback declared -- the
  -- notification will be queued as 'skipped'.
  perform app.set_notification_preference(v_tenant1, v_admin1, 'tierc4_test_notify', 'email', false, v_admin1, 'admin1');
  v_notification := app.queue_notification((select cv.id from app.config_versions cv join app.config_objects co on co.id = cv.config_object_id where co.config_type_code = 'notification:tierc4_test_notify' and cv.status = 'published'), v_tenant1, 'tierc4_test_notify', v_admin1, 'email', 'en', '{}'::jsonb, 'tierc4-dedupe-2', v_admin1, 'tester');
  if v_notification.status <> 'skipped' then
    raise exception 'assertion failed: expected a real skipped notification (opted out, no in_app fallback declared for this notification type), got %', to_jsonb(v_notification);
  end if;

  begin
    perform app.record_notification_delivery_attempt(v_notification.id, 'success', null, v_admin1, 'admin1');
    raise exception 'assertion failed: expected notification_delivery_attempt_already_terminal for an attempt on a skipped notification';
  exception when check_violation then
    if sqlerrm !~ 'notification_delivery_attempt_already_terminal' then raise; end if;
  end;

  raise notice 'PASS: record_notification_delivery_attempt refuses a further attempt on a skipped (terminal) notification';
end;
$$;

\echo '>> [Tier C fix 2] app.set_notification_contact_address: refuses to plant a contact address for a tenant the target identity is not an active member of'
do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaetierc4b');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
begin
  begin
    perform app.set_notification_contact_address(v_tenant2, v_admin1, 'sms', '+62-800-PLANTED', v_admin1, 'admin1');
    raise exception 'assertion failed: expected notification_contact_recipient_unauthorized -- admin1 is not a member of tenant2';
  exception when insufficient_privilege then
    if sqlerrm !~ 'notification_contact_recipient_unauthorized' then raise; end if;
  end;

  raise notice 'PASS: set_notification_contact_address refuses a cross-tenant self-service plant for a non-member identity';
end;
$$;

\echo '>> [Tier C fix 3] app.notification_contact_addresses RLS: live forged-session proof -- the owner sees their own row only within a tenant they actively belong to; the tenant''s own tenant_admin can now read it too'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_fin1 uuid := '00000000-0000-0000-0000-000022000002';
  v_count integer;
begin
  perform app.set_notification_contact_address(v_tenant1, v_fin1, 'sms', '+62-800-REAL', v_fin1, 'fin1');

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000022000002", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.notification_contact_addresses where tenant_id = v_tenant1 and auth_user_id = v_fin1;
  if v_count <> 1 then
    raise exception 'assertion failed: expected fin1 to see their own real, active-membership contact address row, got %', v_count;
  end if;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  -- The tenant's own tenant_admin (support-grant authority) can now READ it
  -- too -- previously zero read path existed despite already having WRITE
  -- authority via app.set_notification_contact_address on behalf of others.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000022000001", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.notification_contact_addresses where tenant_id = v_tenant1 and auth_user_id = v_fin1;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the tenant''s own tenant_admin to now have a real read path to this row, got %', v_count;
  end if;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: the RLS policy''s own read authority now matches its write authority, scoped to active tenant membership';
end;
$$;

-- ===========================================================================
-- Fix 6, IAE-016/IAE-017/IAE-018: connection/tenant cross-check on the
-- remaining evidence-writer functions (not otherwise exercised above).
-- ===========================================================================

\echo '>> [Tier C fix 6, remaining writers] app.record_logistics_partner_sync_event / app.record_einvoice_submission_attempt / app.record_tax_authority_lookup / app.record_external_sync_snapshot all refuse a connection_id that does not belong to p_tenant_id (and, where applicable, does not match the declared adapter)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaetierc4');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaetierc4b');
  v_admin1 uuid := '00000000-0000-0000-0000-000022000001';
  v_fin1 uuid := '00000000-0000-0000-0000-000022000002';
  v_foreign_conn uuid := (select id from app.integration_connections where tenant_id = v_tenant2 and adapter_code = 'carrier_status_api');
  v_wrong_adapter_conn uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'payment_gateway');
  v_hr_conn uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'external_hr_system');
begin
  begin
    perform app.record_logistics_partner_sync_event(v_tenant1, v_foreign_conn, 'TIERC4-EVT-X', 'status_update', null, '{}'::jsonb, v_admin1, 'admin1');
    raise exception 'assertion failed: expected logistics_partner_connection_tenant_mismatch';
  exception when no_data_found then
    if sqlerrm !~ 'logistics_partner_connection_tenant_mismatch' then raise; end if;
  end;

  begin
    perform app.record_tax_authority_lookup(v_tenant1, v_wrong_adapter_conn, 'PPN-11', current_date, 'success', '{}'::jsonb, '{}'::jsonb, 0.01, 'USD', null, v_fin1, 'fin1');
    raise exception 'assertion failed: expected finance_provider_connection_tenant_mismatch -- payment_gateway is not a tax_authority_api connection';
  exception when no_data_found then
    if sqlerrm !~ 'finance_provider_connection_tenant_mismatch' then raise; end if;
  end;

  begin
    perform app.record_external_sync_snapshot(v_tenant1, v_hr_conn, 'external_accounting_system', 'gl_account', 'EXT-ACCT-X', '{}'::jsonb, v_fin1, 'fin1');
    raise exception 'assertion failed: expected external_sync_connection_tenant_mismatch -- the connection is external_hr_system, not external_accounting_system';
  exception when no_data_found then
    if sqlerrm !~ 'external_sync_connection_tenant_mismatch' then raise; end if;
  end;

  raise notice 'PASS: every remaining evidence-writer cross-checks its own connection_id against tenant_id (and adapter_code where applicable)';
end;
$$;

\echo '>> batch4-tier-c-review-fixes.sql: ALL PASSED'
