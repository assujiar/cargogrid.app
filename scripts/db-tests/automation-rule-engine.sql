-- Real, executable test evidence for IAE-007 (Automation Rule Engine,
-- Prompt 335, CG-S14-IAE-007) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000009000001..008.
-- Grep-verified unclaimed against every other *.sql fixture in this
-- directory before use.
--
-- Applies the Batch 1 Tier C review's own hard-won lesson from the start
-- (not discovered after the fact this time): live RLS-as-a-forged-session
-- testing (request.jwt.claims + set role authenticated, section 8 below,
-- the same technique scripts/db-tests/ticketing-internal.sql section 5
-- already established) proves the customer_user-layer exclusion at the raw
-- table level, not merely through an RPC's own internal check.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (iaeautoco) with a Supreme Admin, an INTHUB:Configure holder, a plain member, a tenant_admin (approval-definition authority), a designated approver, a customer_user portal principal, a notify-recipient member, and a second tenant (iaeautoco2) with one lone member for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_configurer_role uuid;
  v_configurer_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000009000001', 'supreme@iaeautoco.test'),
    ('00000000-0000-0000-0000-000009000002', 'configurer@iaeautoco.test'),
    ('00000000-0000-0000-0000-000009000003', 'member@iaeautoco.test'),
    ('00000000-0000-0000-0000-000009000004', 'tenantadmin@iaeautoco.test'),
    ('00000000-0000-0000-0000-000009000005', 'approver@iaeautoco.test'),
    ('00000000-0000-0000-0000-000009000006', 'portal@iaeautoco.test'),
    ('00000000-0000-0000-0000-000009000007', 'member@iaeautoco2.test'),
    ('00000000-0000-0000-0000-000009000008', 'recipient@iaeautoco.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000009000001', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaeautoco', 'IAE Automation Co', 'idem-iaeautoco', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaeautoco2', 'IAE Automation Co 2', 'idem-iaeautoco2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaeautoco2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000009000002', 'configurer@iaeautoco.test', 'Configurer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'configurer@iaeautoco.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000009000003', 'member@iaeautoco.test', 'Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaeautoco.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000009000004', 'tenantadmin@iaeautoco.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@iaeautoco.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000009000004', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000009000005', 'approver@iaeautoco.test', 'Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@iaeautoco.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000009000008', 'recipient@iaeautoco.test', 'Recipient', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'recipient@iaeautoco.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000009000006', 'portal@iaeautoco.test', 'Portal Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'portal@iaeautoco.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000009000006', 'customer_user', v_tenant1, 'iae-auto-portal-ref', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000009000007', 'member@iaeautoco2.test', 'Beta Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaeautoco2.test'), 'active', 'onboarded', 'tester');

  v_configurer_role := (app.create_role(v_tenant1, 'Automation Configurer', 'INTHUB:Configure', 'tester')).id;
  v_configurer_draft := app.create_role_version(v_configurer_role, 'tester');
  perform app.set_role_version_permissions(
    v_configurer_draft.id,
    array(select id from app.permissions where resource_module_code = 'INTHUB' and action = 'Configure'),
    'tester'
  );
  perform app.publish_role_version(v_configurer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_configurer_role and status = 'published'),
    '00000000-0000-0000-0000-000009000002', '00000000-0000-0000-0000-000009000001', 'tester');
end;
$$;

\echo '>> bootstrap: a fresh notification type + global config (mirrors 20260802050000''s own direct-RPC bootstrap), and a minimal 2-state published workflow definition + a started instance (mirrors scripts/db-tests/workflow.sql''s own proven minimal shape)'
do $$
declare
  v_tenant1 uuid;
  v_notif_draft app.config_versions;
  v_wf_draft app.config_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');

  perform app.register_notification_type('automation_test_notify', 'Automation Test Notify', 'INTHUB', '00000000-0000-0000-0000-000009000001', 'tester');
  v_notif_draft := app.create_config_draft('notification:automation_test_notify', null, 'global', null, '00000000-0000-0000-0000-000009000001', 'tester');
  perform app.set_config_items(
    v_notif_draft.id,
    jsonb_build_array(
      jsonb_build_object('key', 'channels', 'value', '["in_app"]'::jsonb),
      jsonb_build_object('key', 'default_locale', 'value', '"en"'::jsonb),
      jsonb_build_object('key', 'templates', 'value', jsonb_build_object('en', jsonb_build_object('subject', 'Automation fired', 'body', 'rule triggered')))
    ),
    '00000000-0000-0000-0000-000009000001', 'tester'
  );
  perform app.publish_config_version(v_notif_draft.id, '00000000-0000-0000-0000-000009000001', now(), 'tester');

  v_wf_draft := app.create_config_draft('workflow', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000009000004', 'tester');
  perform app.set_config_items(
    v_wf_draft.id,
    jsonb_build_array(
      jsonb_build_object('key', 'states', 'value', jsonb_build_array('a', 'b')),
      jsonb_build_object('key', 'initial_state', 'value', 'a'),
      jsonb_build_object('key', 'terminal_states', 'value', jsonb_build_array('b')),
      jsonb_build_object('key', 'transitions', 'value', jsonb_build_array(jsonb_build_object('from', 'a', 'to', 'b')))
    ),
    '00000000-0000-0000-0000-000009000004', 'tester'
  );
  perform app.publish_workflow_definition(v_wf_draft.id, '00000000-0000-0000-0000-000009000004', now(), 'tester');

  perform app.start_workflow_instance(v_wf_draft.id, v_tenant1, 'generic', null, 'idem-iaeautoco-wf-instance', '00000000-0000-0000-0000-000009000003', 'tester');
end;
$$;

\echo '>> app.create_automation_rule: INTHUB:Configure-gated, opens a real empty version-1 draft'
do $$
declare
  v_tenant1 uuid;
  v_rule app.automation_rules;
  v_draft_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');

  begin
    perform app.create_automation_rule(v_tenant1, 'Should be denied', null, '00000000-0000-0000-0000-000009000003', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- member lacks INTHUB:Configure';
  exception
    when insufficient_privilege then null;
  end;

  v_rule := app.create_automation_rule(v_tenant1, 'High Priority Ticket Alert', 'notify + workflow + job on high priority', '00000000-0000-0000-0000-000009000002', 'tester');
  if v_rule.status <> 'active' or v_rule.current_version_id is not null then
    raise exception 'assertion failed: expected a real, unpublished (current_version_id null) rule';
  end if;

  select count(*) into v_draft_count from app.automation_rule_versions where automation_rule_id = v_rule.id and status = 'draft';
  if v_draft_count <> 1 then
    raise exception 'assertion failed: expected exactly one open draft version, got %', v_draft_count;
  end if;
end;
$$;

\echo '>> app.set_automation_rule_definition + app.dry_run_automation_rule: draft-only write, pure side-effect-free simulation'
do $$
declare
  v_tenant1 uuid;
  v_rule_id uuid;
  v_result jsonb;
  v_notif_count_before integer;
  v_job_count_before integer;
  v_notif_count_after integer;
  v_job_count_after integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');
  v_rule_id := (select id from app.automation_rules where tenant_id = v_tenant1 and name = 'High Priority Ticket Alert');

  perform app.set_automation_rule_definition(
    v_rule_id, 'ticket.created',
    jsonb_build_array(jsonb_build_object('field', 'priority', 'operator', 'eq', 'value', 'high')),
    jsonb_build_array(
      jsonb_build_object('action_type', 'notify', 'notification_type_code', 'automation_test_notify', 'channel', 'in_app', 'recipient_field', 'recipient_auth_user_id'),
      jsonb_build_object('action_type', 'transition_workflow', 'instance_id_field', 'instance_id', 'to_state', 'b', 'reason', 'automation'),
      jsonb_build_object('action_type', 'enqueue_job', 'job_type', 'automation_action_execution', 'payload', jsonb_build_object('sub_action', 'noop_probe'))
    ),
    '00000000-0000-0000-0000-000009000002', 'tester'
  );

  select count(*) into v_notif_count_before from app.notifications;
  select count(*) into v_job_count_before from app.jobs;

  v_result := app.dry_run_automation_rule(v_rule_id, jsonb_build_object('priority', 'high'), '00000000-0000-0000-0000-000009000002', 'tester');
  if (v_result ->> 'matched')::boolean <> true then
    raise exception 'assertion failed: expected a matching sample event to report matched=true';
  end if;
  if jsonb_array_length(v_result -> 'would_fire_actions') <> 3 then
    raise exception 'assertion failed: expected 3 would-fire actions, got %', jsonb_array_length(v_result -> 'would_fire_actions');
  end if;

  v_result := app.dry_run_automation_rule(v_rule_id, jsonb_build_object('priority', 'low'), '00000000-0000-0000-0000-000009000002', 'tester');
  if (v_result ->> 'matched')::boolean <> false then
    raise exception 'assertion failed: expected a non-matching sample event to report matched=false';
  end if;

  select count(*) into v_notif_count_after from app.notifications;
  select count(*) into v_job_count_after from app.jobs;
  if v_notif_count_after <> v_notif_count_before or v_job_count_after <> v_job_count_before then
    raise exception 'assertion failed: a dry run must never produce a real notification or job -- pure simulation only (design decision 9)';
  end if;
end;
$$;

\echo '>> app.request_automation_rule_publish_approval: fails cleanly with a named error until the tenant configures its own approval:automation_rule_publish definition, then succeeds and binds to the exact draft version'
do $$
declare
  v_tenant1 uuid;
  v_rule_id uuid;
  v_appr_draft app.config_versions;
  v_request app.approval_requests;
  v_draft_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');
  v_rule_id := (select id from app.automation_rules where tenant_id = v_tenant1 and name = 'High Priority Ticket Alert');

  begin
    perform app.request_automation_rule_publish_approval(v_rule_id, '00000000-0000-0000-0000-000009000002', 'tester');
    raise exception 'assertion failed: expected automation_rule_publish_approval_not_configured -- tenant has not configured the approval definition yet';
  exception
    when check_violation then
      if sqlerrm !~ 'automation_rule_publish_approval_not_configured' then raise; end if;
  end;

  v_appr_draft := app.create_config_draft('approval:automation_rule_publish', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000009000004', 'tester');
  perform app.set_config_items(
    v_appr_draft.id,
    jsonb_build_array(
      jsonb_build_object('key', 'pattern', 'value', 'sequential'),
      jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
        jsonb_build_object('step_order', 1, 'approver_type', 'specific_user', 'specific_user_id', '00000000-0000-0000-0000-000009000005', 'required_approvals', 1)
      ))
    ),
    '00000000-0000-0000-0000-000009000004', 'tester'
  );
  perform app.publish_approval_definition(v_appr_draft.id, '00000000-0000-0000-0000-000009000004', now(), 'tester');

  v_draft_id := (select id from app.automation_rule_versions where automation_rule_id = v_rule_id and status = 'draft');
  v_request := app.request_automation_rule_publish_approval(v_rule_id, '00000000-0000-0000-0000-000009000002', 'tester');
  if v_request.entity_type <> 'automation_rule_version' or v_request.entity_id <> v_draft_id or v_request.status <> 'pending' then
    raise exception 'assertion failed: expected a real, pending approval request bound to the exact draft version';
  end if;
end;
$$;

\echo '>> app.publish_automation_rule_version: rejects an unapproved/mismatched request by name, succeeds once approved and bound to the exact draft, opens a fresh draft'
do $$
declare
  v_tenant1 uuid;
  v_rule_id uuid;
  v_other_rule app.automation_rules;
  v_other_request app.approval_requests;
  v_request app.approval_requests;
  v_step_id uuid;
  v_rule_after app.automation_rules;
  v_new_draft_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');
  v_rule_id := (select id from app.automation_rules where tenant_id = v_tenant1 and name = 'High Priority Ticket Alert');
  select r.* into v_request from app.approval_requests r where r.tenant_id = v_tenant1 and r.entity_type = 'automation_rule_version' order by r.started_at desc limit 1;

  begin
    perform app.publish_automation_rule_version(v_rule_id, v_request.id, '00000000-0000-0000-0000-000009000002', 'tester');
    raise exception 'assertion failed: expected automation_rule_publish_not_approved -- the request is still pending';
  exception
    when check_violation then
      if sqlerrm !~ 'automation_rule_publish_not_approved' then raise; end if;
  end;

  -- Mismatch guard: a real, approved request for a DIFFERENT rule/entity must
  -- never satisfy this rule's own publish.
  v_other_rule := app.create_automation_rule(v_tenant1, 'Unrelated Rule', null, '00000000-0000-0000-0000-000009000002', 'tester');
  perform app.set_automation_rule_definition(
    v_other_rule.id, 'unrelated.event', '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('action_type', 'enqueue_job', 'job_type', 'automation_action_execution', 'payload', '{}'::jsonb)),
    '00000000-0000-0000-0000-000009000002', 'tester'
  );
  v_other_request := app.request_automation_rule_publish_approval(v_other_rule.id, '00000000-0000-0000-0000-000009000002', 'tester');
  v_step_id := (select id from app.approval_request_steps where request_id = v_other_request.id);
  perform app.decide_automation_rule_publish_approval(v_step_id, 'approved', '00000000-0000-0000-0000-000009000005', 'tester');

  begin
    perform app.publish_automation_rule_version(v_rule_id, v_other_request.id, '00000000-0000-0000-0000-000009000002', 'tester');
    raise exception 'assertion failed: expected automation_rule_publish_approval_mismatch -- the approved request is for a DIFFERENT rule''s draft';
  exception
    when check_violation then
      if sqlerrm !~ 'automation_rule_publish_approval_mismatch' then raise; end if;
  end;

  -- The real, matching approval: decide it, then publish.
  v_step_id := (select id from app.approval_request_steps where request_id = v_request.id);
  perform app.decide_automation_rule_publish_approval(v_step_id, 'approved', '00000000-0000-0000-0000-000009000005', 'tester');

  v_rule_after := app.publish_automation_rule_version(v_rule_id, v_request.id, '00000000-0000-0000-0000-000009000002', 'tester');
  if v_rule_after.current_version_id is null then
    raise exception 'assertion failed: expected current_version_id to be set after a real approved publish';
  end if;

  select count(*) into v_new_draft_count from app.automation_rule_versions where automation_rule_id = v_rule_id and status = 'draft';
  if v_new_draft_count <> 1 then
    raise exception 'assertion failed: expected exactly one fresh open draft after publish, got %', v_new_draft_count;
  end if;
end;
$$;

\echo '>> app.decide_automation_rule_publish_approval: refuses a step that does not belong to an automation_rule_version request (never a generic decide-any-step bypass)'
do $$
declare
  v_config_version_id uuid;
  v_foreign_request_id uuid;
  v_foreign_step_id uuid;
begin
  select cv.id into v_config_version_id
  from app.config_objects co
  join app.config_versions cv on cv.config_object_id = co.id and cv.status = 'published'
  where co.config_type_code = 'approval:automation_rule_publish' and co.scope_level = 'tenant';

  -- Direct fixture insert (bypassing app.request_approval, which always
  -- binds entity_type='automation_rule_version' itself) simulates a step
  -- from a totally unrelated approval domain -- proves the wrapper's own
  -- scoping guard, not merely that the happy path sets the right value.
  insert into app.approval_requests (tenant_id, config_version_id, entity_type, entity_id, pattern, status, idempotency_key, requested_by)
  values ((select id from app.tenants where slug = 'iaeautoco'), v_config_version_id, 'some_other_domain', null, 'sequential', 'pending', 'idem-foreign-request', 'tester')
  returning id into v_foreign_request_id;
  insert into app.approval_request_steps (request_id, step_order, approver_type, specific_user_id, required_approvals, status)
  values (v_foreign_request_id, 1, 'specific_user', '00000000-0000-0000-0000-000009000005', 1, 'active')
  returning id into v_foreign_step_id;

  begin
    perform app.decide_automation_rule_publish_approval(v_foreign_step_id, 'approved', '00000000-0000-0000-0000-000009000005', 'tester');
    raise exception 'assertion failed: expected automation_rule_publish_approval_wrong_domain -- this step belongs to a non-automation_rule_version request';
  exception
    when check_violation then
      if sqlerrm !~ 'automation_rule_publish_approval_wrong_domain' then raise; end if;
  end;
end;
$$;

\echo '>> C-05 discipline: a tenant-2 actor with zero relationship to tenant-1''s own rule gets the SAME automation_rule_not_found a missing id would produce, never a tenant-id-disclosing insufficient_authority'
do $$
declare
  v_tenant1 uuid;
  v_rule_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');
  v_rule_id := (select id from app.automation_rules where tenant_id = v_tenant1 and name = 'High Priority Ticket Alert');

  begin
    perform app.set_automation_rule_status(v_rule_id, 'paused', '00000000-0000-0000-0000-000009000007', 'tester');
    raise exception 'assertion failed: expected no_data_found -- a tenant-2 actor with zero relationship to tenant-1 must see the same not_found a missing id would produce';
  exception
    when no_data_found then null;
  end;

  begin
    perform app.dry_run_automation_rule(v_rule_id, '{}'::jsonb, '00000000-0000-0000-0000-000009000007', 'tester');
    raise exception 'assertion failed: expected no_data_found for dry_run_automation_rule too';
  exception
    when no_data_found then null;
  end;
end;
$$;

\echo '>> app.evaluate_event_for_automation_rules: a real matching event fires all 3 actions (real notification, real workflow transition, real job), records one completed execution row, and is idempotent on the SAME source event'
do $$
declare
  v_tenant1 uuid;
  v_rule_id uuid;
  v_instance_id uuid;
  v_event_payload jsonb;
  v_source_event app.event_logs;
  v_source_event_id uuid;
  v_exec1 app.automation_rule_executions;
  v_exec2 app.automation_rule_executions;
  v_notif_count integer;
  v_job_count integer;
  v_instance_state text;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');
  v_rule_id := (select id from app.automation_rules where tenant_id = v_tenant1 and name = 'High Priority Ticket Alert');
  v_instance_id := (select id from app.workflow_instances where tenant_id = v_tenant1 and idempotency_key = 'idem-iaeautoco-wf-instance');

  v_event_payload := jsonb_build_object(
    'priority', 'high',
    'recipient_auth_user_id', '00000000-0000-0000-0000-000009000008',
    'instance_id', v_instance_id
  );

  -- A real app.event_logs row (PLT-132's own outbox table) -- source_event_id
  -- is a genuine FK, never a bare synthetic UUID, so the real-event path is
  -- proven against a real upstream row, not a fabricated one.
  v_source_event := app.append_event_log(v_tenant1, 'ticket.created', 'app.tickets', null, v_event_payload, '00000000-0000-0000-0000-000009000003', 'tester');
  v_source_event_id := v_source_event.id;

  select * into v_exec1 from app.evaluate_event_for_automation_rules(
    v_tenant1, 'ticket.created', v_event_payload, v_source_event_id, '00000000-0000-0000-0000-000009000003', 'system'
  ) limit 1;

  if v_exec1.status <> 'completed' then
    raise exception 'assertion failed: expected status=completed, got % (actions_taken=%)', v_exec1.status, v_exec1.actions_taken;
  end if;
  if jsonb_array_length(v_exec1.actions_taken) <> 3 then
    raise exception 'assertion failed: expected 3 actions_taken entries, got %', jsonb_array_length(v_exec1.actions_taken);
  end if;

  select count(*) into v_notif_count from app.notifications
  where recipient_auth_user_id = '00000000-0000-0000-0000-000009000008' and notification_type_code = 'automation_test_notify';
  if v_notif_count <> 1 then
    raise exception 'assertion failed: expected exactly one real notification, got %', v_notif_count;
  end if;

  select count(*) into v_job_count from app.jobs where job_type = 'automation_action_execution' and tenant_id = v_tenant1;
  if v_job_count <> 1 then
    raise exception 'assertion failed: expected exactly one real app.jobs row, got %', v_job_count;
  end if;

  select current_state into v_instance_state from app.workflow_instances where id = v_instance_id;
  if v_instance_state <> 'b' then
    raise exception 'assertion failed: expected the real workflow instance to have transitioned to state b, got %', v_instance_state;
  end if;

  -- Idempotent replay: the SAME source event re-delivered must reuse the SAME execution row, never double-fire.
  select * into v_exec2 from app.evaluate_event_for_automation_rules(
    v_tenant1, 'ticket.created', v_event_payload, v_source_event_id, '00000000-0000-0000-0000-000009000003', 'system'
  ) limit 1;
  if v_exec2.id <> v_exec1.id then
    raise exception 'assertion failed: expected the SAME execution row on a replayed source event, got a different id';
  end if;

  select count(*) into v_notif_count from app.notifications
  where recipient_auth_user_id = '00000000-0000-0000-0000-000009000008' and notification_type_code = 'automation_test_notify';
  if v_notif_count <> 1 then
    raise exception 'assertion failed: expected STILL exactly one notification after a replayed source event (no duplicate), got %', v_notif_count;
  end if;

  raise notice 'PASS: real event -> 3 real actions (notification/workflow transition/job) fired exactly once, idempotent on replay';
end;
$$;

\echo '>> loop/storm suppression: a second, freshly-sourced event within the cooldown window is suppressed (real, queryable execution row, never a silent no-op); a rule already at its own storm cap is likewise suppressed'
do $$
declare
  v_tenant1 uuid;
  v_rule_id uuid;
  v_instance_id uuid;
  v_event_payload jsonb;
  v_exec app.automation_rule_executions;
  v_notif_count_before integer;
  v_notif_count_after integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');
  v_rule_id := (select id from app.automation_rules where tenant_id = v_tenant1 and name = 'High Priority Ticket Alert');
  v_instance_id := (select id from app.workflow_instances where tenant_id = v_tenant1 and idempotency_key = 'idem-iaeautoco-wf-instance');
  v_event_payload := jsonb_build_object('priority', 'high', 'recipient_auth_user_id', '00000000-0000-0000-0000-000009000008', 'instance_id', v_instance_id);

  select count(*) into v_notif_count_before from app.notifications
  where recipient_auth_user_id = '00000000-0000-0000-0000-000009000008' and notification_type_code = 'automation_test_notify';

  select * into v_exec from app.evaluate_event_for_automation_rules(
    v_tenant1, 'ticket.created', v_event_payload, null, '00000000-0000-0000-0000-000009000003', 'system'
  ) limit 1;
  if v_exec.status <> 'suppressed' or v_exec.suppressed_reason <> 'cooldown' then
    raise exception 'assertion failed: expected status=suppressed/cooldown for a fresh event within the cooldown window, got status=% reason=%', v_exec.status, v_exec.suppressed_reason;
  end if;

  select count(*) into v_notif_count_after from app.notifications
  where recipient_auth_user_id = '00000000-0000-0000-0000-000009000008' and notification_type_code = 'automation_test_notify';
  if v_notif_count_after <> v_notif_count_before then
    raise exception 'assertion failed: a cooldown-suppressed evaluation must never produce a real notification';
  end if;

  -- Storm-window cap: direct fixture update simulates "already at the cap"
  -- pre-existing state (this migration exposes no tenant-facing RPC to
  -- adjust cooldown_seconds/max_fires_per_window -- a disclosed, bounded
  -- scope choice, see this rule's own build log). Also clear last_fired_at
  -- so the cooldown branch above does not mask this assertion.
  update app.automation_rules
  set last_fired_at = now() - interval '1 hour', window_started_at = now(), fire_count_in_window = max_fires_per_window
  where id = v_rule_id;

  select * into v_exec from app.evaluate_event_for_automation_rules(
    v_tenant1, 'ticket.created', v_event_payload, null, '00000000-0000-0000-0000-000009000003', 'system'
  ) limit 1;
  if v_exec.status <> 'suppressed' or v_exec.suppressed_reason <> 'storm_window_exceeded' then
    raise exception 'assertion failed: expected status=suppressed/storm_window_exceeded once the rule is at its own fire cap, got status=% reason=%', v_exec.status, v_exec.suppressed_reason;
  end if;

  raise notice 'PASS: cooldown and storm-window suppression are both real, row-locked, and always leave a queryable execution row -- never a silent no-op';
end;
$$;

\echo '>> app.set_automation_rule_status: pausing a rule structurally excludes it from evaluation (zero execution rows, not even suppressed) -- Alternative flow: a rule misfires, admin pauses it'
do $$
declare
  v_tenant1 uuid;
  v_rule_id uuid;
  v_instance_id uuid;
  v_event_payload jsonb;
  v_exec_count_before integer;
  v_exec_count_after integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');
  v_rule_id := (select id from app.automation_rules where tenant_id = v_tenant1 and name = 'High Priority Ticket Alert');
  v_instance_id := (select id from app.workflow_instances where tenant_id = v_tenant1 and idempotency_key = 'idem-iaeautoco-wf-instance');
  v_event_payload := jsonb_build_object('priority', 'high', 'recipient_auth_user_id', '00000000-0000-0000-0000-000009000008', 'instance_id', v_instance_id);

  perform app.set_automation_rule_status(v_rule_id, 'paused', '00000000-0000-0000-0000-000009000002', 'tester');
  if (select status from app.automation_rules where id = v_rule_id) <> 'paused' then
    raise exception 'assertion failed: expected status=paused';
  end if;

  select count(*) into v_exec_count_before from app.automation_rule_executions where automation_rule_id = v_rule_id;
  perform app.evaluate_event_for_automation_rules(v_tenant1, 'ticket.created', v_event_payload, null, '00000000-0000-0000-0000-000009000003', 'system');
  select count(*) into v_exec_count_after from app.automation_rule_executions where automation_rule_id = v_rule_id;
  if v_exec_count_after <> v_exec_count_before then
    raise exception 'assertion failed: a paused rule must be structurally excluded from the trigger match itself -- expected zero new execution rows, got %', v_exec_count_after - v_exec_count_before;
  end if;

  perform app.set_automation_rule_status(v_rule_id, 'active', '00000000-0000-0000-0000-000009000002', 'tester');
end;
$$;

-- ===========================================================================
-- Batch 2 Tier C fix pass regressions (20260803030000_harden_intelligence_
-- batch2_tier_c_review_fixes.sql) -- one block per confirmed, fixed finding.
-- ===========================================================================

\echo '>> Tier C fix (finding 1, Critical): transition_workflow now scopes its workflow-instance lookup to the firing rule''s own tenant -- a rule in tenant1 whose event payload names tenant2''s own REAL workflow instance id must fail cleanly (automation_action_workflow_instance_not_found) and must NEVER transition tenant2''s instance, even though the acting identity holds real active membership in BOTH tenants (an ordinary, supported dual-tenant scenario)'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_dual_actor uuid := '00000000-0000-0000-0000-000009000007';
  v_wf_draft app.config_versions;
  v_instance_id uuid;
  v_state_before text;
  v_state_after text;
  v_rule app.automation_rules;
  v_request app.approval_requests;
  v_step_id uuid;
  v_exec app.automation_rule_executions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');
  v_tenant2 := (select id from app.tenants where slug = 'iaeautoco2');

  -- v_dual_actor (tenant2's own lone member) also becomes an active,
  -- ordinary tenant1 member -- an unremarkable, fully-supported multi-tenant
  -- membership scenario this repository's own (tenant_id, auth_user_id)
  -- per-tenant model already allows for any identity (contractor/platform
  -- staff/etc).
  perform app.invite_user(v_tenant1, v_dual_actor, 'member@iaeautoco2.test', 'Beta Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaeautoco2.test' and tenant_id = v_tenant1), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_dual_actor, 'tenant_admin', v_tenant2, null, 'tester');

  -- tenant2's own real, independent workflow + started instance.
  v_wf_draft := app.create_config_draft('workflow', v_tenant2, 'tenant', null, v_dual_actor, 'tester');
  perform app.set_config_items(
    v_wf_draft.id,
    jsonb_build_array(
      jsonb_build_object('key', 'states', 'value', jsonb_build_array('a', 'b')),
      jsonb_build_object('key', 'initial_state', 'value', 'a'),
      jsonb_build_object('key', 'terminal_states', 'value', jsonb_build_array('b')),
      jsonb_build_object('key', 'transitions', 'value', jsonb_build_array(jsonb_build_object('from', 'a', 'to', 'b')))
    ),
    v_dual_actor, 'tester'
  );
  perform app.publish_workflow_definition(v_wf_draft.id, v_dual_actor, now(), 'tester');
  perform app.start_workflow_instance(v_wf_draft.id, v_tenant2, 'generic', null, 'idem-iaeautoco2-wf-instance', v_dual_actor, 'tester');
  v_instance_id := (select id from app.workflow_instances where tenant_id = v_tenant2 and idempotency_key = 'idem-iaeautoco2-wf-instance');
  select current_state into v_state_before from app.workflow_instances where id = v_instance_id;

  -- tenant1's own rule, published, targeting the event payload's own
  -- instance_id field -- exactly the shape a real deployment would use.
  v_rule := app.create_automation_rule(v_tenant1, 'Cross Tenant WF Guard Rule', null, '00000000-0000-0000-0000-000009000002', 'tester');
  perform app.set_automation_rule_definition(
    v_rule.id, 'cross.tenant.wf.guard', '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('action_type', 'transition_workflow', 'instance_id_field', 'instance_id', 'to_state', 'b')),
    '00000000-0000-0000-0000-000009000002', 'tester'
  );
  v_request := app.request_automation_rule_publish_approval(v_rule.id, '00000000-0000-0000-0000-000009000002', 'tester');
  v_step_id := (select id from app.approval_request_steps where request_id = v_request.id);
  perform app.decide_automation_rule_publish_approval(v_step_id, 'approved', '00000000-0000-0000-0000-000009000005', 'tester');
  perform app.publish_automation_rule_version(v_rule.id, v_request.id, '00000000-0000-0000-0000-000009000002', 'tester');

  -- Fire tenant1's rule with an event payload naming tenant2's own real
  -- instance id, as the dual-tenant actor (who WOULD pass app.transition_
  -- workflow_instance's own downstream authority check against tenant2, the
  -- exact condition this finding''s live reproduction depended on).
  select * into v_exec from app.evaluate_event_for_automation_rules(
    v_tenant1, 'cross.tenant.wf.guard', jsonb_build_object('instance_id', v_instance_id), null, v_dual_actor, 'system'
  ) limit 1;

  if v_exec.status <> 'failed' then
    raise exception 'assertion failed: expected status=failed (automation_action_workflow_instance_not_found for a cross-tenant instance id), got status=% actions_taken=%', v_exec.status, v_exec.actions_taken;
  end if;
  if v_exec.actions_taken::text !~ 'automation_action_workflow_instance_not_found' then
    raise exception 'assertion failed: expected the transition_workflow action''s own error to be automation_action_workflow_instance_not_found, got %', v_exec.actions_taken;
  end if;

  select current_state into v_state_after from app.workflow_instances where id = v_instance_id;
  if v_state_after <> v_state_before then
    raise exception 'assertion failed: tenant2''s own workflow instance must NEVER be transitioned by tenant1''s own automation rule -- expected state to remain %, got %', v_state_before, v_state_after;
  end if;

  raise notice 'PASS: transition_workflow correctly refuses a cross-tenant workflow instance id (folded into automation_action_workflow_instance_not_found) and never mutates the foreign tenant''s own instance';
end;
$$;

\echo '>> Tier C fix (finding 2, Critical): publish now rejects a draft whose content was edited AFTER its approval request was opened -- the swapped, never-reviewed content must never publish under a stale approval'
do $$
declare
  v_tenant1 uuid;
  v_rule app.automation_rules;
  v_request app.approval_requests;
  v_step_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');

  v_rule := app.create_automation_rule(v_tenant1, 'Content Swap Guard Rule', null, '00000000-0000-0000-0000-000009000002', 'tester');
  perform app.set_automation_rule_definition(
    v_rule.id, 'content.swap.guard', '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('action_type', 'enqueue_job', 'job_type', 'automation_action_execution', 'payload', jsonb_build_object('sub_action', 'reviewed_original'))),
    '00000000-0000-0000-0000-000009000002', 'tester'
  );
  v_request := app.request_automation_rule_publish_approval(v_rule.id, '00000000-0000-0000-0000-000009000002', 'tester');
  v_step_id := (select id from app.approval_request_steps where request_id = v_request.id);
  perform app.decide_automation_rule_publish_approval(v_step_id, 'approved', '00000000-0000-0000-0000-000009000005', 'tester');

  -- Edit the SAME already-approved draft's content -- never reviewed by the
  -- approver above.
  perform app.set_automation_rule_definition(
    v_rule.id, 'content.swap.guard', '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('action_type', 'enqueue_job', 'job_type', 'automation_action_execution', 'payload', jsonb_build_object('sub_action', 'swapped_never_reviewed'))),
    '00000000-0000-0000-0000-000009000002', 'tester'
  );

  begin
    perform app.publish_automation_rule_version(v_rule.id, v_request.id, '00000000-0000-0000-0000-000009000002', 'tester');
    raise exception 'assertion failed: expected automation_rule_publish_content_changed -- the draft was edited after this exact request was approved';
  exception
    when check_violation then
      if sqlerrm !~ 'automation_rule_publish_content_changed' then raise; end if;
  end;

  if exists (select 1 from app.automation_rule_versions where automation_rule_id = v_rule.id and status = 'published') then
    raise exception 'assertion failed: the swapped content must never have actually published';
  end if;

  raise notice 'PASS: publish refuses a draft edited after its own approval was granted (content-hash mismatch), never ships unreviewed content under a stale approval';
end;
$$;

\echo '>> Tier C fix (finding 3, High): app.decide_automation_rule_publish_approval now folds a cross-tenant caller into the SAME automation_rule_publish_approval_step_not_found a missing id would produce, never a tenant-id-disclosing insufficient_authority delegated from app.decide_approval_step'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_outsider uuid := '00000000-0000-0000-0000-000009000009';
  v_rule app.automation_rules;
  v_request app.approval_requests;
  v_step_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');
  v_tenant2 := (select id from app.tenants where slug = 'iaeautoco2');

  -- A genuinely tenant2-ONLY identity (never given any membership in
  -- tenant1, unlike the finding-1 test's own dual-tenant actor above) --
  -- proves the fold applies to a caller with ZERO relationship to tenant1,
  -- not merely an actor who happens to also lack eligible-approver status.
  insert into auth.users (id, email) values (v_outsider, 'outsider@iaeautoco2.test');
  perform app.invite_user(v_tenant2, v_outsider, 'outsider@iaeautoco2.test', 'Outsider', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@iaeautoco2.test' and tenant_id = v_tenant2), 'active', 'onboarded', 'tester');

  v_rule := app.create_automation_rule(v_tenant1, 'Cross Tenant Decide Guard Rule', null, '00000000-0000-0000-0000-000009000002', 'tester');
  perform app.set_automation_rule_definition(
    v_rule.id, 'decide.guard.event', '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('action_type', 'enqueue_job', 'job_type', 'automation_action_execution', 'payload', '{}'::jsonb)),
    '00000000-0000-0000-0000-000009000002', 'tester'
  );
  v_request := app.request_automation_rule_publish_approval(v_rule.id, '00000000-0000-0000-0000-000009000002', 'tester');
  v_step_id := (select id from app.approval_request_steps where request_id = v_request.id);

  begin
    -- tenant2's own outsider member, zero relationship to tenant1, deciding
    -- a REAL tenant1 step.
    perform app.decide_automation_rule_publish_approval(v_step_id, 'approved', v_outsider, 'tester');
    raise exception 'assertion failed: expected no_data_found -- a tenant-2 actor with zero relationship to tenant-1''s own request must see the same not_found a missing id would produce, never a tenant-id-disclosing insufficient_authority';
  exception
    when no_data_found then null;
  end;

  if (select status from app.approval_requests where id = v_request.id) <> 'pending' then
    raise exception 'assertion failed: the cross-tenant decide attempt must never have actually decided the step';
  end if;

  raise notice 'PASS: decide_automation_rule_publish_approval folds a cross-tenant caller into automation_rule_publish_approval_step_not_found, never discloses the real tenant_id via insufficient_authority';
end;
$$;

\echo '>> Tier C fix (finding 5, High): two DIFFERENT enqueue_job actions in the SAME rule version no longer collide on the SAME idempotency key -- both must actually enqueue as two real, distinct app.jobs rows, never silently collapse to one'
do $$
declare
  v_tenant1 uuid;
  v_rule app.automation_rules;
  v_request app.approval_requests;
  v_step_id uuid;
  v_exec app.automation_rule_executions;
  v_job_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');

  v_rule := app.create_automation_rule(v_tenant1, 'Multi Enqueue Guard Rule', null, '00000000-0000-0000-0000-000009000002', 'tester');
  perform app.set_automation_rule_definition(
    v_rule.id, 'multi.enqueue.guard', '[]'::jsonb,
    jsonb_build_array(
      jsonb_build_object('action_type', 'enqueue_job', 'job_type', 'automation_action_execution', 'payload', jsonb_build_object('sub_action', 'first_job')),
      jsonb_build_object('action_type', 'enqueue_job', 'job_type', 'automation_action_execution', 'payload', jsonb_build_object('sub_action', 'second_job'))
    ),
    '00000000-0000-0000-0000-000009000002', 'tester'
  );
  v_request := app.request_automation_rule_publish_approval(v_rule.id, '00000000-0000-0000-0000-000009000002', 'tester');
  v_step_id := (select id from app.approval_request_steps where request_id = v_request.id);
  perform app.decide_automation_rule_publish_approval(v_step_id, 'approved', '00000000-0000-0000-0000-000009000005', 'tester');
  perform app.publish_automation_rule_version(v_rule.id, v_request.id, '00000000-0000-0000-0000-000009000002', 'tester');

  select * into v_exec from app.evaluate_event_for_automation_rules(
    v_tenant1, 'multi.enqueue.guard', '{}'::jsonb, null, '00000000-0000-0000-0000-000009000002', 'system'
  ) limit 1;
  if v_exec.status <> 'completed' then
    raise exception 'assertion failed: expected status=completed, got % (actions_taken=%)', v_exec.status, v_exec.actions_taken;
  end if;

  select count(*) into v_job_count from app.jobs
  where tenant_id = v_tenant1 and job_type = 'automation_action_execution' and payload ->> 'sub_action' in ('first_job', 'second_job');
  if v_job_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 real, distinct app.jobs rows (one per enqueue_job action), got %', v_job_count;
  end if;

  raise notice 'PASS: two enqueue_job actions in the same rule version now enqueue two real, distinct jobs -- no more silent dedupe collision on an identical, action-position-blind idempotency key';
end;
$$;

\echo '>> Tier C fix (finding 6, Low): app.dry_run_automation_rule now reports valid=false with a real validation_error when the draft carries an action_type outside the publish-time allowlist, instead of silently reporting it as something that "would fire"'
do $$
declare
  v_tenant1 uuid;
  v_rule app.automation_rules;
  v_result jsonb;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');

  v_rule := app.create_automation_rule(v_tenant1, 'Invalid Dry Run Guard Rule', null, '00000000-0000-0000-0000-000009000002', 'tester');
  perform app.set_automation_rule_definition(
    v_rule.id, 'invalid.dryrun.guard', '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('action_type', 'delete_customer_ledger_entry', 'target_table', 'app.ledger_entries')),
    '00000000-0000-0000-0000-000009000002', 'tester'
  );

  v_result := app.dry_run_automation_rule(v_rule.id, '{}'::jsonb, '00000000-0000-0000-0000-000009000002', 'tester');
  if (v_result ->> 'valid')::boolean <> false then
    raise exception 'assertion failed: expected valid=false for a draft carrying a governance-rejected action_type, got %', v_result;
  end if;
  if coalesce(v_result ->> 'validation_error', '') !~ 'automation_rule_invalid_action_type' then
    raise exception 'assertion failed: expected a real validation_error naming automation_rule_invalid_action_type, got %', v_result ->> 'validation_error';
  end if;
  -- Still a pure, informative simulation, not a hard block -- would_fire_actions is still reported.
  if jsonb_array_length(v_result -> 'would_fire_actions') <> 1 then
    raise exception 'assertion failed: dry run must still report the simulated would-fire actions alongside the new validity signal, got %', v_result;
  end if;

  raise notice 'PASS: dry_run_automation_rule now honestly reports valid=false for a governance-rejected draft, never silently implying it could really publish and fire';
end;
$$;

\echo '>> Tier C fix (finding 4, High): REAL three-process concurrency proof -- a genuinely concurrent redelivery of the SAME source event to the SAME rule, forced to interleave around the row lock via scripts/db-tests/automation-rule-engine-concurrency-helper.sh, must gracefully dedupe (both processes report the SAME final status, neither crashes with an unhandled unique_violation), and exactly ONE real execution row and ONE real job row must exist for the shared idempotency key'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeautoco');
  v_actor uuid := '00000000-0000-0000-0000-000009000002';
  v_rule app.automation_rules;
  v_request app.approval_requests;
  v_step_id uuid;
  v_event app.event_logs;
begin
  v_rule := app.create_automation_rule(v_tenant1, 'Race Guard Rule', null, v_actor, 'tester');
  perform app.set_automation_rule_definition(
    v_rule.id, 'race.guard.event', '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('action_type', 'enqueue_job', 'job_type', 'automation_action_execution', 'payload', '{}'::jsonb)),
    v_actor, 'tester'
  );
  v_request := app.request_automation_rule_publish_approval(v_rule.id, v_actor, 'tester');
  v_step_id := (select id from app.approval_request_steps where request_id = v_request.id);
  perform app.decide_automation_rule_publish_approval(v_step_id, 'approved', '00000000-0000-0000-0000-000009000005', 'tester');
  perform app.publish_automation_rule_version(v_rule.id, v_request.id, v_actor, 'tester');

  v_event := app.append_event_log(v_tenant1, 'race.guard.event', 'app.tickets', null, '{}'::jsonb, v_actor, 'tester');

  create temporary table if not exists tmp_race_guard_ids (rule_id uuid, tenant_id uuid, actor_id uuid, event_id uuid);
  delete from tmp_race_guard_ids;
  insert into tmp_race_guard_ids values (v_rule.id, v_tenant1, v_actor, v_event.id);
end;
$$;

select rule_id as race_rule_id, tenant_id as race_tenant_id, actor_id as race_actor_id, event_id as race_event_id
from tmp_race_guard_ids \gset

select current_database() as pg_test_db \gset
select pg_backend_pid()::text as race_bpid \gset

\set race_sql_l 'BEGIN; SELECT id FROM app.automation_rules WHERE id = ''' :race_rule_id ''' FOR UPDATE; SELECT pg_sleep(3); COMMIT;'
\set race_sql_a 'SELECT status FROM app.evaluate_event_for_automation_rules(''' :race_tenant_id ''', ''race.guard.event'', ''{}''::jsonb, ''' :race_event_id ''', ''' :race_actor_id ''', ''race-proc-a'');'
\set race_sql_b 'SELECT status FROM app.evaluate_event_for_automation_rules(''' :race_tenant_id ''', ''race.guard.event'', ''{}''::jsonb, ''' :race_event_id ''', ''' :race_actor_id ''', ''race-proc-b'');'

\set race_out_l '/tmp/cargogrid-automation-rule-race-l-' :race_bpid '.out'
\set race_out_a '/tmp/cargogrid-automation-rule-race-a-' :race_bpid '.out'
\set race_out_b '/tmp/cargogrid-automation-rule-race-b-' :race_bpid '.out'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_L :race_sql_l
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_L :race_out_l
\setenv RACE_OUT_A :race_out_a
\setenv RACE_OUT_B :race_out_b

\! bash scripts/db-tests/automation-rule-engine-concurrency-helper.sh

-- psql does not interpolate :variables inside a do $$ ... $$ body (the same
-- limitation scripts/db-tests/advanced-tms-wms-picking.sql's own L6-keyrace
-- block already documented, ISS-2026-023/CG-S10-ATW-027) -- smuggle the
-- captured content in via a session-level GUC instead, read back with
-- current_setting().
--
-- RGL-BLK-005 fix: this used to smuggle the two PID-suffixed PATHS and read
-- them with pg_read_file() inside the do block -- but pg_read_file() reads the
-- *server's* filesystem, while the helper above writes its race-output files
-- on the *client's*. Identical locally (same host), genuinely different in CI
-- (Postgres in its own Docker service container). \set's backtick form runs
-- client-side, so it is captured here, before the do block.
\set out_a `cat "$RACE_OUT_A"`
\set out_b `cat "$RACE_OUT_B"`
select set_config('cargogrid.race_out_a', :'out_a', false),
       set_config('cargogrid.race_out_b', :'out_b', false);

do $$
declare
  v_rule_id uuid;
  v_event_id uuid;
  v_exec_count integer;
  v_job_count integer;
  v_out_a text;
  v_out_b text;
begin
  select rule_id, event_id into v_rule_id, v_event_id from tmp_race_guard_ids;

  select count(*) into v_exec_count from app.automation_rule_executions where automation_rule_id = v_rule_id and source_event_id = v_event_id;
  if v_exec_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE real execution row for the shared idempotency key after the genuine concurrent race, got % -- see the RACE_OUT_L/A/B process output captured above', v_exec_count;
  end if;

  select count(*) into v_job_count from app.jobs
  where job_type = 'automation_action_execution'
    and idempotency_key = 'automation-' || v_rule_id || '-' || v_event_id || '-enqueue_job-1';
  if v_job_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE real app.jobs row for this race''s own idempotency key after the genuine concurrent race (never double-enqueued), got %', v_job_count;
  end if;

  -- Neither racing process may have crashed with an unhandled
  -- unique_violation (the exact regression this finding closed) -- both must
  -- have returned a clean status (completed), captured in their own output
  -- file by the helper script above.
  v_out_a := current_setting('cargogrid.race_out_a');
  v_out_b := current_setting('cargogrid.race_out_b');
  if v_out_a ~ 'ERROR' or v_out_b ~ 'ERROR' then
    raise exception 'assertion failed: expected BOTH racing processes to complete cleanly with no ERROR -- process A output=[%] process B output=[%]', v_out_a, v_out_b;
  end if;
  if trim(both E' \n\r\t' from v_out_a) <> 'completed' or trim(both E' \n\r\t' from v_out_b) <> 'completed' then
    raise exception 'assertion failed: expected BOTH racing processes to report status=completed -- got A=[%] B=[%]', v_out_a, v_out_b;
  end if;

  raise notice 'PASS: genuine three-process concurrent redelivery of the same source event dedupes gracefully (both processes report completed, zero unhandled unique_violation), exactly one execution row and one job row exist';
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-007 function; authenticated has no direct INSERT/UPDATE/DELETE on any of the three new tables'
do $$
declare
  v_bad_grant record;
begin
  for v_bad_grant in
    select routine_name from information_schema.routine_privileges
    where routine_schema = 'app'
      and routine_name in (
        'create_automation_rule', 'set_automation_rule_definition', 'dry_run_automation_rule',
        'request_automation_rule_publish_approval', 'decide_automation_rule_publish_approval', 'publish_automation_rule_version',
        'set_automation_rule_status', 'evaluate_event_for_automation_rules'
      )
      and grantee = 'anon'
  loop
    raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_bad_grant.routine_name;
  end loop;

  for v_bad_grant in
    select privilege_type from information_schema.role_table_grants
    where table_schema = 'app' and table_name in ('automation_rules', 'automation_rule_versions', 'automation_rule_executions')
      and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
  loop
    raise exception 'assertion failed: authenticated must not hold direct % on the new automation-rule tables', v_bad_grant.privilege_type;
  end loop;

  for v_bad_grant in
    select routine_name from information_schema.routine_privileges
    where routine_schema = 'app' and routine_name = 'evaluate_event_for_automation_rules' and grantee = 'authenticated'
  loop
    raise exception 'assertion failed: authenticated must not hold EXECUTE on app.evaluate_event_for_automation_rules -- a trusted service_role-only system entrypoint (design decision 5)';
  end loop;
end;
$$;

\echo '>> live forged-session RLS probe (request.jwt.claims + set role authenticated, the same technique scripts/db-tests/ticketing-internal.sql section 5 already established): a customer_user-layer portal principal sees ZERO rows of any of the three new tables via raw RLS, despite real active tenant membership; an ordinary member sees the real rows'
do $$
declare
  v_tenant1 uuid;
  v_rule_id uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeautoco');
  v_rule_id := (select id from app.automation_rules where tenant_id = v_tenant1 and name = 'High Priority Ticket Alert');

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000009000006", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.automation_rules where tenant_id = v_tenant1;
  if v_count <> 0 then raise exception 'FAIL (RLS): customer_user-layer portal principal sees % automation_rules row(s) via raw RLS, expected 0', v_count; end if;
  select count(*) into v_count from app.automation_rule_versions where automation_rule_id = v_rule_id;
  if v_count <> 0 then raise exception 'FAIL (RLS): customer_user-layer portal principal sees % automation_rule_versions row(s) via raw RLS, expected 0', v_count; end if;
  select count(*) into v_count from app.automation_rule_executions where automation_rule_id = v_rule_id;
  if v_count <> 0 then raise exception 'FAIL (RLS): customer_user-layer portal principal sees % automation_rule_executions row(s) via raw RLS, expected 0', v_count; end if;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000009000003", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.automation_rules where tenant_id = v_tenant1;
  if v_count = 0 then raise exception 'FAIL (RLS): an ordinary tenant member should see the tenant''s own automation_rules row(s) via raw RLS, got 0'; end if;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: live forged-session RLS probe -- a customer_user-layer principal sees zero rows across all 3 new tables despite real active tenant membership; an ordinary member sees the real rows';
end;
$$;

\echo '>> audit trail: create/set-definition/publish/status-change each recorded a real app.audit_logs event'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where resource_type = 'app.automation_rules' and action = 'create_automation_rule';
  if v_count = 0 then raise exception 'assertion failed: expected a create_automation_rule audit event'; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.automation_rule_versions' and action = 'set_automation_rule_definition';
  if v_count = 0 then raise exception 'assertion failed: expected a set_automation_rule_definition audit event'; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.automation_rule_versions' and action = 'publish_automation_rule_version';
  if v_count = 0 then raise exception 'assertion failed: expected a publish_automation_rule_version audit event'; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.automation_rules' and action = 'set_automation_rule_status';
  if v_count = 0 then raise exception 'assertion failed: expected a set_automation_rule_status audit event'; end if;
end;
$$;

\echo 'ALL IAE-007 (Automation Rule Engine) db-test assertions passed.'
