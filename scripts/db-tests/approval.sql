-- Real, executable test evidence for PLT-123 (Approval Engine, CG-S6-PLT-020).
--
-- This file also builds and proves the one safe, isolated, synthetic example the
-- migration header discloses as deliberately NOT seeded as migration data: a 2-step
-- sequential manager-then-finance approval, plus a parallel and a threshold variant to
-- prove all three routing patterns are genuinely distinct algorithms, not the same code
-- under three names. No permanent example row exists anywhere outside this test file.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, a tenant_admin/regular org_user/Supreme Admin, two manager approvers and one finance approver (real role assignments, not principal-membership layers), plus one un-rostered identity for delegation/escalation tests'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_manager_role_id uuid;
  v_manager_draft app.role_versions;
  v_finance_role_id uuid;
  v_finance_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000001501', 'tenantadminap@example.test'),
    ('00000000-0000-0000-0000-000000001502', 'regularuserap@example.test'),
    ('00000000-0000-0000-0000-000000001503', 'supremeap@example.test'),
    ('00000000-0000-0000-0000-000000001504', 'manager1ap@example.test'),
    ('00000000-0000-0000-0000-000000001505', 'manager2ap@example.test'),
    ('00000000-0000-0000-0000-000000001506', 'financeap@example.test'),
    ('00000000-0000-0000-0000-000000001507', 'delegateap@example.test'),
    ('00000000-0000-0000-0000-000000001508', 'othertenantadminap@example.test');

  perform app.provision_tenant('acmeap', 'Acme Approval Co', 'idem-acmeap', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeap');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001501', 'tenantadminap@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminap@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001501', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001502', 'regularuserap@example.test', 'Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularuserap@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001502', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001504', 'manager1ap@example.test', 'Manager One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager1ap@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001504', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001505', 'manager2ap@example.test', 'Manager Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager2ap@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001505', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001506', 'financeap@example.test', 'Finance One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeap@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001506', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001507', 'delegateap@example.test', 'Delegate One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'delegateap@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001507', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001503', 'supreme_admin', null, null, 'tester');

  v_manager_role_id := (app.create_role(v_tenant_id, 'Manager Approver AP', 'test role', 'tester')).id;
  v_manager_draft := app.create_role_version(v_manager_role_id, 'tester');
  perform app.set_role_version_permissions(v_manager_draft.id, array[]::uuid[], 'tester');
  perform app.publish_role_version(v_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_id, (select id from app.role_versions where role_id = v_manager_role_id and status = 'published'), '00000000-0000-0000-0000-000000001504', '00000000-0000-0000-0000-000000001501', 'tester');
  perform app.assign_role(v_tenant_id, (select id from app.role_versions where role_id = v_manager_role_id and status = 'published'), '00000000-0000-0000-0000-000000001505', '00000000-0000-0000-0000-000000001501', 'tester');

  v_finance_role_id := (app.create_role(v_tenant_id, 'Finance Approver AP', 'test role', 'tester')).id;
  v_finance_draft := app.create_role_version(v_finance_role_id, 'tester');
  perform app.set_role_version_permissions(v_finance_draft.id, array[]::uuid[], 'tester');
  perform app.publish_role_version(v_finance_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_id, (select id from app.role_versions where role_id = v_finance_role_id and status = 'published'), '00000000-0000-0000-0000-000000001506', '00000000-0000-0000-0000-000000001501', 'tester');

  perform app.provision_tenant('gizmoap', 'Gizmo Approval Co', 'idem-gizmoap', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoap');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000001508', 'othertenantadminap@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantadminap@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001508', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.validate_approval_definition / app.publish_approval_definition: every structural failure mode is a distinct, named exception; a valid sequential definition publishes'
do $$
declare
  v_tenant_id uuid;
  v_manager_role_id uuid;
  v_finance_role_id uuid;
  v_draft app.config_versions;
  v_published app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeap');
  v_manager_role_id := (select id from app.roles where tenant_id = v_tenant_id and name = 'Manager Approver AP');
  v_finance_role_id := (select id from app.roles where tenant_id = v_tenant_id and name = 'Finance Approver AP');
  v_draft := app.create_config_draft('approval', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001501', 'tenant admin');

  -- approval_invalid_pattern
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object('key', 'pattern', 'value', 'random')), '00000000-0000-0000-0000-000000001501', 'tenant admin');
  begin
    perform app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001501', null, 'tenant admin');
    raise exception 'assertion failed: expected an invalid pattern to raise approval_invalid_pattern';
  exception
    when check_violation then
      if sqlerrm not like 'approval_invalid_pattern%' then
        raise exception 'assertion failed: expected approval_invalid_pattern, got %', sqlerrm;
      end if;
  end;

  -- approval_missing_steps
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object('key', 'pattern', 'value', 'sequential')), '00000000-0000-0000-0000-000000001501', 'tenant admin');
  begin
    perform app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001501', null, 'tenant admin');
    raise exception 'assertion failed: expected a missing steps item to raise approval_missing_steps';
  exception
    when check_violation then
      if sqlerrm not like 'approval_missing_steps%' then
        raise exception 'assertion failed: expected approval_missing_steps, got %', sqlerrm;
      end if;
  end;

  -- approval_invalid_step_order (duplicate step_order)
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_manager_role_id::text),
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_finance_role_id::text)
    ))
  ), '00000000-0000-0000-0000-000000001501', 'tenant admin');
  begin
    perform app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001501', null, 'tenant admin');
    raise exception 'assertion failed: expected a duplicated step_order to raise approval_invalid_step_order';
  exception
    when check_violation then
      if sqlerrm not like 'approval_invalid_step_order%' then
        raise exception 'assertion failed: expected approval_invalid_step_order, got %', sqlerrm;
      end if;
  end;

  -- approval_invalid_approver_type
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'department', 'role_id', v_manager_role_id::text)
    ))
  ), '00000000-0000-0000-0000-000000001501', 'tenant admin');
  begin
    perform app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001501', null, 'tenant admin');
    raise exception 'assertion failed: expected an unknown approver_type to raise approval_invalid_approver_type';
  exception
    when check_violation then
      if sqlerrm not like 'approval_invalid_approver_type%' then
        raise exception 'assertion failed: expected approval_invalid_approver_type, got %', sqlerrm;
      end if;
  end;

  -- approval_missing_approver_ref
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role')
    ))
  ), '00000000-0000-0000-0000-000000001501', 'tenant admin');
  begin
    perform app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001501', null, 'tenant admin');
    raise exception 'assertion failed: expected a role step with no role_id to raise approval_missing_approver_ref';
  exception
    when check_violation then
      if sqlerrm not like 'approval_missing_approver_ref%' then
        raise exception 'assertion failed: expected approval_missing_approver_ref, got %', sqlerrm;
      end if;
  end;

  -- approval_unknown_role
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', '00000000-0000-0000-0000-000000009999')
    ))
  ), '00000000-0000-0000-0000-000000001501', 'tenant admin');
  begin
    perform app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001501', null, 'tenant admin');
    raise exception 'assertion failed: expected a nonexistent role_id to raise approval_unknown_role';
  exception
    when check_violation then
      if sqlerrm not like 'approval_unknown_role%' then
        raise exception 'assertion failed: expected approval_unknown_role, got %', sqlerrm;
      end if;
  end;

  -- approval_unknown_user
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'specific_user', 'specific_user_id', '00000000-0000-0000-0000-000000009999')
    ))
  ), '00000000-0000-0000-0000-000000001501', 'tenant admin');
  begin
    perform app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001501', null, 'tenant admin');
    raise exception 'assertion failed: expected a nonexistent specific_user_id to raise approval_unknown_user';
  exception
    when check_violation then
      if sqlerrm not like 'approval_unknown_user%' then
        raise exception 'assertion failed: expected approval_unknown_user, got %', sqlerrm;
      end if;
  end;

  -- approval_invalid_required_approvals
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_manager_role_id::text, 'required_approvals', 0)
    ))
  ), '00000000-0000-0000-0000-000000001501', 'tenant admin');
  begin
    perform app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001501', null, 'tenant admin');
    raise exception 'assertion failed: expected required_approvals=0 to raise approval_invalid_required_approvals';
  exception
    when check_violation then
      if sqlerrm not like 'approval_invalid_required_approvals%' then
        raise exception 'assertion failed: expected approval_invalid_required_approvals, got %', sqlerrm;
      end if;
  end;

  -- approval_invalid_threshold
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'threshold'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_manager_role_id::text)
    )),
    jsonb_build_object('key', 'threshold_required_steps', 'value', 5)
  ), '00000000-0000-0000-0000-000000001501', 'tenant admin');
  begin
    perform app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001501', null, 'tenant admin');
    raise exception 'assertion failed: expected threshold_required_steps=5 with only 1 step to raise approval_invalid_threshold';
  exception
    when check_violation then
      if sqlerrm not like 'approval_invalid_threshold%' then
        raise exception 'assertion failed: expected approval_invalid_threshold, got %', sqlerrm;
      end if;
  end;

  -- Now the real, valid example: sequential manager -> finance.
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'allow_self_approval', 'value', false),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_manager_role_id::text, 'required_approvals', 1),
      jsonb_build_object('step_order', 2, 'approver_type', 'role', 'role_id', v_finance_role_id::text, 'required_approvals', 1)
    ))
  ), '00000000-0000-0000-0000-000000001501', 'tenant admin');

  begin
    perform app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001502', null, 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied publishing a tenant-scoped approval definition';
  exception
    when insufficient_privilege then
      null;
  end;

  v_published := app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001501', null, 'tenant admin');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the valid sequential definition to publish, got %', v_published.status;
  end if;
end;
$$;

\echo '>> sequential pattern: separation-of-duties self-approval denial, unauthorized decider, then a real 2-step manager->finance completion'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_request app.approval_requests;
  v_step1_id uuid;
  v_step2_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeap');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'approval' and o.scope_level = 'tenant' and v.status = 'published';

  -- Requested by manager1ap themselves, who is also step 1's eligible approver -- this
  -- is what makes the self-approval test a real proof, not an incidental denial.
  v_request := app.request_approval(v_published_version_id, v_tenant_id, 'purchase_order', '00000000-0000-0000-0000-000000009101', 'req-ap-1', '00000000-0000-0000-0000-000000001504', 'manager one');
  if v_request.status <> 'pending' or v_request.pattern <> 'sequential' then
    raise exception 'assertion failed: expected a fresh pending sequential request, got status=% pattern=%', v_request.status, v_request.pattern;
  end if;
  select id into v_step1_id from app.approval_request_steps where request_id = v_request.id and step_order = 1;
  select id into v_step2_id from app.approval_request_steps where request_id = v_request.id and step_order = 2;
  if (select status from app.approval_request_steps where id = v_step1_id) <> 'active' or (select status from app.approval_request_steps where id = v_step2_id) <> 'pending' then
    raise exception 'assertion failed: expected sequential materialization to open only step 1';
  end if;

  begin
    perform app.decide_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000001504', 'manager one');
    raise exception 'assertion failed: expected the requester (also an eligible step-1 approver) to be denied deciding their own request';
  exception
    when check_violation then
      if sqlerrm not like 'approval_self_approval_denied%' then
        raise exception 'assertion failed: expected approval_self_approval_denied, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.decide_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000001506', 'finance one');
    raise exception 'assertion failed: expected financeap (not a Manager Approver AP holder) to be denied deciding step 1';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.decide_approval_step(v_step2_id, 'approved', '00000000-0000-0000-0000-000000001506', 'finance one');
    raise exception 'assertion failed: expected deciding a still-pending (not yet active) step 2 to raise approval_step_not_active';
  exception
    when check_violation then
      if sqlerrm not like 'approval_step_not_active%' then
        raise exception 'assertion failed: expected approval_step_not_active, got %', sqlerrm;
      end if;
  end;

  perform app.decide_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000001505', 'manager two');
  if (select status from app.approval_request_steps where id = v_step1_id) <> 'approved' then
    raise exception 'assertion failed: expected step 1 to be approved by manager two';
  end if;
  if (select status from app.approval_request_steps where id = v_step2_id) <> 'active' then
    raise exception 'assertion failed: expected step 2 to open once step 1 approved (sequential advance)';
  end if;
  if (select status from app.approval_requests where id = v_request.id) <> 'pending' then
    raise exception 'assertion failed: expected the request to remain pending until step 2 also decides';
  end if;

  perform app.decide_approval_step(v_step2_id, 'approved', '00000000-0000-0000-0000-000000001506', 'finance one');
  if (select status from app.approval_requests where id = v_request.id) <> 'approved' then
    raise exception 'assertion failed: expected the request to be approved once both sequential steps approved';
  end if;
  if (select ended_at from app.approval_requests where id = v_request.id) is null then
    raise exception 'assertion failed: expected ended_at to be set on completion';
  end if;

  -- Idempotent replay: the same idempotency_key returns the existing (now-approved) request, not a new one.
  if (app.request_approval(v_published_version_id, v_tenant_id, 'purchase_order', '00000000-0000-0000-0000-000000009101', 'req-ap-1', '00000000-0000-0000-0000-000000001504', 'manager one')).id <> v_request.id then
    raise exception 'assertion failed: expected a repeated request_approval call with the same idempotency_key to return the existing request';
  end if;
end;
$$;

\echo '>> sequential pattern: a rejection anywhere fails the whole request immediately and skips every remaining step'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_request app.approval_requests;
  v_step1_id uuid;
  v_step2_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeap');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'approval' and o.scope_level = 'tenant' and v.status = 'published';

  v_request := app.request_approval(v_published_version_id, v_tenant_id, 'purchase_order', '00000000-0000-0000-0000-000000009102', 'req-ap-2', '00000000-0000-0000-0000-000000001502', 'regular user');
  select id into v_step1_id from app.approval_request_steps where request_id = v_request.id and step_order = 1;
  select id into v_step2_id from app.approval_request_steps where request_id = v_request.id and step_order = 2;

  perform app.decide_approval_step(v_step1_id, 'rejected', '00000000-0000-0000-0000-000000001504', 'manager one', 'budget exceeded');
  if (select status from app.approval_requests where id = v_request.id) <> 'rejected' then
    raise exception 'assertion failed: expected a step rejection to immediately reject the whole request';
  end if;
  if (select status from app.approval_request_steps where id = v_step2_id) <> 'skipped' then
    raise exception 'assertion failed: expected the never-opened step 2 to be marked skipped after fail-fast rejection';
  end if;

  begin
    perform app.decide_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000001505', 'manager two');
    raise exception 'assertion failed: expected deciding a step on an already-rejected request to raise approval_request_not_pending';
  exception
    when check_violation then
      if sqlerrm not like 'approval_request_not_pending%' then
        raise exception 'assertion failed: expected approval_request_not_pending, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> parallel pattern: every step must independently reach its own required_approvals; duplicate decision by the same approver is rejected while a step is still active'
do $$
declare
  v_tenant_id uuid;
  v_manager_role_id uuid;
  v_finance_role_id uuid;
  v_draft app.config_versions;
  v_published app.config_versions;
  v_request app.approval_requests;
  v_step1_id uuid;
  v_step2_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeap');
  v_manager_role_id := (select id from app.roles where tenant_id = v_tenant_id and name = 'Manager Approver AP');
  v_finance_role_id := (select id from app.roles where tenant_id = v_tenant_id and name = 'Finance Approver AP');

  v_draft := app.create_config_draft('approval', v_tenant_id, 'role', v_manager_role_id, '00000000-0000-0000-0000-000000001501', 'tenant admin');
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'parallel'),
    jsonb_build_object('key', 'allow_self_approval', 'value', false),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_manager_role_id::text, 'required_approvals', 2),
      jsonb_build_object('step_order', 2, 'approver_type', 'role', 'role_id', v_finance_role_id::text, 'required_approvals', 1)
    ))
  ), '00000000-0000-0000-0000-000000001501', 'tenant admin');
  v_published := app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001501', null, 'tenant admin');

  v_request := app.request_approval(v_published.id, v_tenant_id, 'quotation', '00000000-0000-0000-0000-000000009103', 'req-ap-3', '00000000-0000-0000-0000-000000001502', 'regular user');
  if v_request.pattern <> 'parallel' then
    raise exception 'assertion failed: expected pattern=parallel on the materialized request';
  end if;
  select id into v_step1_id from app.approval_request_steps where request_id = v_request.id and step_order = 1;
  select id into v_step2_id from app.approval_request_steps where request_id = v_request.id and step_order = 2;
  if (select status from app.approval_request_steps where id = v_step2_id) <> 'active' then
    raise exception 'assertion failed: expected parallel materialization to open every step at once (step 2 active from the start)';
  end if;

  perform app.decide_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000001504', 'manager one');
  if (select status from app.approval_request_steps where id = v_step1_id) <> 'active' or (select approvals_count from app.approval_request_steps where id = v_step1_id) <> 1 then
    raise exception 'assertion failed: expected step 1 to stay active at approvals_count=1 (required_approvals=2)';
  end if;

  begin
    perform app.decide_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000001504', 'manager one');
    raise exception 'assertion failed: expected a second decision by the same approver on a still-active step to raise approval_decision_already_recorded';
  exception
    when unique_violation then
      if sqlerrm not like 'approval_decision_already_recorded%' then
        raise exception 'assertion failed: expected approval_decision_already_recorded, got %', sqlerrm;
      end if;
  end;

  perform app.decide_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000001505', 'manager two');
  if (select status from app.approval_request_steps where id = v_step1_id) <> 'approved' then
    raise exception 'assertion failed: expected step 1 to reach approved once approvals_count=required_approvals=2';
  end if;
  if (select status from app.approval_requests where id = v_request.id) <> 'pending' then
    raise exception 'assertion failed: expected the request to remain pending until every parallel step is approved';
  end if;

  perform app.decide_approval_step(v_step2_id, 'approved', '00000000-0000-0000-0000-000000001506', 'finance one');
  if (select status from app.approval_requests where id = v_request.id) <> 'approved' then
    raise exception 'assertion failed: expected the request to approve once every parallel step independently reached approved';
  end if;
end;
$$;

\echo '>> threshold pattern: the request approves the instant N of M steps individually reach approved, and every still-open step is then marked skipped'
do $$
declare
  v_tenant_id uuid;
  v_manager_role_id uuid;
  v_finance_role_id uuid;
  v_draft app.config_versions;
  v_published app.config_versions;
  v_request app.approval_requests;
  v_step1_id uuid;
  v_step2_id uuid;
  v_step3_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeap');
  v_manager_role_id := (select id from app.roles where tenant_id = v_tenant_id and name = 'Manager Approver AP');
  v_finance_role_id := (select id from app.roles where tenant_id = v_tenant_id and name = 'Finance Approver AP');

  v_draft := app.create_config_draft('approval', v_tenant_id, 'role', v_finance_role_id, '00000000-0000-0000-0000-000000001501', 'tenant admin');
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'threshold'),
    jsonb_build_object('key', 'threshold_required_steps', 'value', 2),
    jsonb_build_object('key', 'allow_self_approval', 'value', false),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_manager_role_id::text, 'required_approvals', 1),
      jsonb_build_object('step_order', 2, 'approver_type', 'role', 'role_id', v_finance_role_id::text, 'required_approvals', 1),
      jsonb_build_object('step_order', 3, 'approver_type', 'specific_user', 'specific_user_id', '00000000-0000-0000-0000-000000001507', 'required_approvals', 1)
    ))
  ), '00000000-0000-0000-0000-000000001501', 'tenant admin');
  v_published := app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001501', null, 'tenant admin');

  v_request := app.request_approval(v_published.id, v_tenant_id, 'vendor_rate', '00000000-0000-0000-0000-000000009104', 'req-ap-4', '00000000-0000-0000-0000-000000001502', 'regular user');
  select id into v_step1_id from app.approval_request_steps where request_id = v_request.id and step_order = 1;
  select id into v_step2_id from app.approval_request_steps where request_id = v_request.id and step_order = 2;
  select id into v_step3_id from app.approval_request_steps where request_id = v_request.id and step_order = 3;

  perform app.decide_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000001504', 'manager one');
  if (select status from app.approval_requests where id = v_request.id) <> 'pending' then
    raise exception 'assertion failed: expected the request to stay pending at 1 of 2 required steps approved';
  end if;

  perform app.decide_approval_step(v_step2_id, 'approved', '00000000-0000-0000-0000-000000001506', 'finance one');
  if (select status from app.approval_requests where id = v_request.id) <> 'approved' then
    raise exception 'assertion failed: expected the request to approve the instant threshold_required_steps=2 is reached';
  end if;
  if (select status from app.approval_request_steps where id = v_step3_id) <> 'skipped' then
    raise exception 'assertion failed: expected the still-open (never decided) 3rd step to be marked skipped once the threshold was met';
  end if;
end;
$$;

\echo '>> app.escalate_approval_step: an override authority reassigns an active step''s approver target; a regular org_user is denied; the old approver loses eligibility and the new one gains it'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_request app.approval_requests;
  v_step1_id uuid;
  v_escalated app.approval_request_steps;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeap');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'approval' and o.scope_level = 'tenant' and v.status = 'published';

  v_request := app.request_approval(v_published_version_id, v_tenant_id, 'purchase_order', '00000000-0000-0000-0000-000000009105', 'req-ap-5', '00000000-0000-0000-0000-000000001502', 'regular user');
  select id into v_step1_id from app.approval_request_steps where request_id = v_request.id and step_order = 1;

  begin
    perform app.escalate_approval_step(v_step1_id, 'specific_user', null, '00000000-0000-0000-0000-000000001507', '00000000-0000-0000-0000-000000001502', 'regular user', 'SLA breach');
    raise exception 'assertion failed: expected a regular org_user to lack override authority to escalate';
  exception
    when insufficient_privilege then
      null;
  end;

  v_escalated := app.escalate_approval_step(v_step1_id, 'specific_user', null, '00000000-0000-0000-0000-000000001507', '00000000-0000-0000-0000-000000001501', 'tenant admin', 'SLA breach');
  if v_escalated.approver_type <> 'specific_user' or v_escalated.specific_user_id <> '00000000-0000-0000-0000-000000001507' then
    raise exception 'assertion failed: expected the step to be reassigned to the escalation target';
  end if;

  begin
    perform app.decide_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000001504', 'manager one');
    raise exception 'assertion failed: expected the original role-based approver to lose eligibility after escalation';
  exception
    when insufficient_privilege then
      null;
  end;

  perform app.decide_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000001507', 'delegate one');
  if (select status from app.approval_request_steps where id = v_step1_id) <> 'approved' then
    raise exception 'assertion failed: expected the escalation target to successfully decide the reassigned step';
  end if;
  perform app.cancel_approval_request(v_request.id, '00000000-0000-0000-0000-000000001501', 'tenant admin', 'test cleanup, step 2 not needed');
end;
$$;

\echo '>> app.create_approval_delegation / app.revoke_approval_delegation: bounded (<=90 days), no self-delegation, delegator-or-tenant_admin authority; an active delegation grants decision eligibility, a revoked one denies it again'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_delegation app.approval_delegations;
  v_request app.approval_requests;
  v_step1_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeap');

  begin
    perform app.create_approval_delegation(v_tenant_id, '00000000-0000-0000-0000-000000001504', '00000000-0000-0000-0000-000000001504', 'all', null, now(), now() + interval '30 days', '00000000-0000-0000-0000-000000001504', 'manager one');
    raise exception 'assertion failed: expected a self-delegation to be rejected structurally';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.create_approval_delegation(v_tenant_id, '00000000-0000-0000-0000-000000001504', '00000000-0000-0000-0000-000000001507', 'all', null, now(), now() + interval '120 days', '00000000-0000-0000-0000-000000001504', 'manager one');
    raise exception 'assertion failed: expected a 120-day delegation to exceed the 90-day bound and be rejected structurally';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.create_approval_delegation(v_tenant_id, '00000000-0000-0000-0000-000000001504', '00000000-0000-0000-0000-000000001507', 'all', null, now(), now() + interval '30 days', '00000000-0000-0000-0000-000000001502', 'regular user');
    raise exception 'assertion failed: expected a non-delegator, non-admin actor to be denied creating a delegation on someone else''s behalf';
  exception
    when insufficient_privilege then
      null;
  end;

  v_delegation := app.create_approval_delegation(v_tenant_id, '00000000-0000-0000-0000-000000001504', '00000000-0000-0000-0000-000000001507', 'all', null, now(), now() + interval '30 days', '00000000-0000-0000-0000-000000001504', 'manager one');

  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'approval' and o.scope_level = 'tenant' and v.status = 'published';
  v_request := app.request_approval(v_published_version_id, v_tenant_id, 'purchase_order', '00000000-0000-0000-0000-000000009106', 'req-ap-6', '00000000-0000-0000-0000-000000001502', 'regular user');
  select id into v_step1_id from app.approval_request_steps where request_id = v_request.id and step_order = 1;

  perform app.decide_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000001507', 'delegate one, standing in for manager one');
  if (select status from app.approval_request_steps where id = v_step1_id) <> 'approved' then
    raise exception 'assertion failed: expected the delegate to successfully decide via an active, unexpired, unrevoked delegation';
  end if;

  perform app.revoke_approval_delegation(v_delegation.id, '00000000-0000-0000-0000-000000001504', 'manager one', 'no longer needed');
  begin
    perform app.revoke_approval_delegation(v_delegation.id, '00000000-0000-0000-0000-000000001504', 'manager one', 'again');
    raise exception 'assertion failed: expected revoking an already-revoked delegation to raise approval_delegation_already_revoked';
  exception
    when check_violation then
      if sqlerrm not like 'approval_delegation_already_revoked%' then
        raise exception 'assertion failed: expected approval_delegation_already_revoked, got %', sqlerrm;
      end if;
  end;

  declare
    v_second_request app.approval_requests;
    v_second_step1_id uuid;
  begin
    v_second_request := app.request_approval(v_published_version_id, v_tenant_id, 'purchase_order', '00000000-0000-0000-0000-000000009107', 'req-ap-7', '00000000-0000-0000-0000-000000001502', 'regular user');
    select id into v_second_step1_id from app.approval_request_steps where request_id = v_second_request.id and step_order = 1;
    begin
      perform app.decide_approval_step(v_second_step1_id, 'approved', '00000000-0000-0000-0000-000000001507', 'delegate one');
      raise exception 'assertion failed: expected the delegate to lose decision eligibility once the delegation is revoked (expired delegation fails safely, Prompt 123 §23)';
    exception
      when insufficient_privilege then
        null;
    end;
    perform app.cancel_approval_request(v_second_request.id, '00000000-0000-0000-0000-000000001501', 'tenant admin', 'test cleanup');
  end;
  perform app.cancel_approval_request(v_request.id, '00000000-0000-0000-0000-000000001501', 'tenant admin', 'test cleanup, step 2 not needed');
end;
$$;

\echo '>> app.request_approval refuses to create a request against a step with zero currently-eligible approvers (Prompt 123 §23''s "no approver" exception case, checked proactively)'
do $$
declare
  v_tenant_id uuid;
  v_empty_role_id uuid;
  v_draft app.config_versions;
  v_published app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeap');
  v_empty_role_id := (app.create_role(v_tenant_id, 'Empty Approver AP', 'nobody holds this role', 'tester')).id;

  v_draft := app.create_config_draft('approval', v_tenant_id, 'role', v_empty_role_id, '00000000-0000-0000-0000-000000001501', 'tenant admin');
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_empty_role_id::text)
    ))
  ), '00000000-0000-0000-0000-000000001501', 'tenant admin');
  v_published := app.publish_approval_definition(v_draft.id, '00000000-0000-0000-0000-000000001501', null, 'tenant admin');

  if app.count_eligible_approvers_for_step(v_tenant_id, 'role', v_empty_role_id, null) <> 0 then
    raise exception 'assertion failed: expected zero eligible approvers for a role nobody holds';
  end if;

  begin
    perform app.request_approval(v_published.id, v_tenant_id, 'generic', null, 'req-ap-8', '00000000-0000-0000-0000-000000001502', 'regular user');
    raise exception 'assertion failed: expected a step with zero eligible approvers to raise approval_no_eligible_approver at request time';
  exception
    when check_violation then
      if sqlerrm not like 'approval_no_eligible_approver%' then
        raise exception 'assertion failed: expected approval_no_eligible_approver, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> app.cancel_approval_request: pending -> cancelled, every open step skipped; a cancelled request can no longer be decided'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_request app.approval_requests;
  v_step1_id uuid;
  v_cancelled app.approval_requests;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeap');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'approval' and o.scope_level = 'tenant' and v.status = 'published';

  v_request := app.request_approval(v_published_version_id, v_tenant_id, 'purchase_order', '00000000-0000-0000-0000-000000009108', 'req-ap-9', '00000000-0000-0000-0000-000000001502', 'regular user');
  select id into v_step1_id from app.approval_request_steps where request_id = v_request.id and step_order = 1;

  v_cancelled := app.cancel_approval_request(v_request.id, '00000000-0000-0000-0000-000000001502', 'regular user', 'no longer needed');
  if v_cancelled.status <> 'cancelled' or v_cancelled.ended_at is null then
    raise exception 'assertion failed: expected status=cancelled with ended_at set';
  end if;
  if (select status from app.approval_request_steps where id = v_step1_id) <> 'skipped' then
    raise exception 'assertion failed: expected the open step to be marked skipped on cancellation';
  end if;

  begin
    perform app.decide_approval_step(v_step1_id, 'approved', '00000000-0000-0000-0000-000000001504', 'manager one');
    raise exception 'assertion failed: expected deciding a step on a cancelled request to raise approval_request_not_pending';
  exception
    when check_violation then
      if sqlerrm not like 'approval_request_not_pending%' then
        raise exception 'assertion failed: expected approval_request_not_pending, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.cancel_approval_request(v_request.id, '00000000-0000-0000-0000-000000001502', 'regular user', 'again');
    raise exception 'assertion failed: expected cancelling an already-cancelled request to raise approval_request_not_pending';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.get_approval_request_history: authority-gated, ordered by step_order then decided_at, and reflects every real decision'
do $$
declare
  v_tenant_id uuid;
  v_request_id uuid;
  v_rows record;
  v_count integer := 0;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeap');
  select id into v_request_id from app.approval_requests where tenant_id = v_tenant_id and idempotency_key = 'req-ap-1';

  begin
    perform app.get_approval_request_history(v_request_id, '00000000-0000-0000-0000-000000001508');
    raise exception 'assertion failed: expected an identity with no membership in acmeap to be denied reading request history';
  exception
    when insufficient_privilege then
      null;
  end;

  for v_rows in select * from app.get_approval_request_history(v_request_id, '00000000-0000-0000-0000-000000001502') order by step_order loop
    v_count := v_count + 1;
    if v_count = 1 and (v_rows.decision <> 'approved' or v_rows.step_order <> 1) then
      raise exception 'assertion failed: expected the first history row to be step 1''s approved decision';
    end if;
  end loop;
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 decision rows (step 1 by manager two, step 2 by finance one) for req-ap-1, saw %', v_count;
  end if;
end;
$$;

\echo '>> app.list_pending_approval_steps_for_actor: the pending-approver inbox view model reflects only what this actor is currently eligible to decide'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_request app.approval_requests;
  v_pending_for_manager integer;
  v_pending_for_regular integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeap');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'approval' and o.scope_level = 'tenant' and v.status = 'published';

  perform app.request_approval(v_published_version_id, v_tenant_id, 'purchase_order', '00000000-0000-0000-0000-000000009109', 'req-ap-10', '00000000-0000-0000-0000-000000001502', 'regular user');

  select count(*) into v_pending_for_manager from app.list_pending_approval_steps_for_actor(v_tenant_id, '00000000-0000-0000-0000-000000001505');
  if v_pending_for_manager < 1 then
    raise exception 'assertion failed: expected manager two to see at least the fresh req-ap-10 step 1 in their pending inbox';
  end if;

  select count(*) into v_pending_for_regular from app.list_pending_approval_steps_for_actor(v_tenant_id, '00000000-0000-0000-0000-000000001502');
  if v_pending_for_regular <> 0 then
    raise exception 'assertion failed: expected the non-approver regular user to see zero steps in their pending inbox, saw %', v_pending_for_regular;
  end if;

  begin
    perform app.list_pending_approval_steps_for_actor(v_tenant_id, '00000000-0000-0000-0000-000000001508');
    raise exception 'assertion failed: expected an identity with no membership in acmeap to be denied listing the tenant''s pending inbox';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> every approval lifecycle mutation self-captures a canonical app.audit_logs entry (no bespoke *_history table for definitions -- app.approval_decisions exists only for step-level decision events)'
do $$
declare
  v_tenant_id uuid;
  v_actions text[] := array['request_approval', 'decide_approval_step', 'cancel_approval_request', 'escalate_approval_step', 'create_approval_delegation', 'revoke_approval_delegation'];
  v_action text;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeap');

  foreach v_action in array v_actions loop
    select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_id and action = v_action;
    if v_count = 0 then
      raise exception 'assertion failed: expected at least one app.audit_logs entry for action=%, saw none', v_action;
    end if;
  end loop;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has direct RLS-scoped SELECT on requests/steps/delegations but none on approval_decisions; anon holds no EXECUTE on service_role-only mutations (ERR-2026-004 regression guard)'
do $$
declare
  v_has_privilege boolean;
begin
  select has_table_privilege('authenticated', 'app.approval_requests', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold direct SELECT on app.approval_requests';
  end if;

  select has_table_privilege('authenticated', 'app.approval_request_steps', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold direct SELECT on app.approval_request_steps';
  end if;

  select has_table_privilege('authenticated', 'app.approval_delegations', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold direct SELECT on app.approval_delegations';
  end if;

  select has_table_privilege('authenticated', 'app.approval_decisions', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold no direct SELECT on app.approval_decisions (app.get_approval_request_history is the sole read path)';
  end if;

  select has_table_privilege('anon', 'app.approval_requests', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no privilege on app.approval_requests at all';
  end if;

  select has_function_privilege('authenticated', 'app.get_approval_request_history(uuid, uuid)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on app.get_approval_request_history';
  end if;

  select has_function_privilege('anon', 'app.get_approval_request_history(uuid, uuid)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on app.get_approval_request_history';
  end if;

  select has_function_privilege('anon', 'app.request_approval(uuid, uuid, text, uuid, text, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.request_approval (ERR-2026-004 regression guard)';
  end if;

  select has_function_privilege('anon', 'app.decide_approval_step(uuid, text, uuid, text, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.decide_approval_step (ERR-2026-004 regression guard)';
  end if;
end;
$$;
