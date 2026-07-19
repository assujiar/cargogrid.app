-- Real, executable test evidence for PLT-122 (Workflow Engine, CG-S6-PLT-019).
--
-- This file also builds and proves the one safe, isolated, synthetic example workflow
-- this capability's migration header discloses as deliberately NOT seeded as migration
-- data: a `draft -> submitted -> approved|rejected` request workflow. No permanent
-- example row exists anywhere outside this test file.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants each with a tenant_admin and a regular org_user, a global Supreme Admin, plus one role in acmewf for scope tests'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000001401', 'tenantadminwf@example.test'),
    ('00000000-0000-0000-0000-000000001402', 'regularuserwf@example.test'),
    ('00000000-0000-0000-0000-000000001403', 'supremewf@example.test'),
    ('00000000-0000-0000-0000-000000001404', 'othertenantadminwf@example.test');

  perform app.provision_tenant('acmewf', 'Acme Workflow Co', 'idem-acmewf', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmewf');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001401', 'tenantadminwf@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminwf@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001401', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001402', 'regularuserwf@example.test', 'Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularuserwf@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001402', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001403', 'supreme_admin', null, null, 'tester');

  perform app.create_role(v_tenant_id, 'Guard Test Role WF', 'test role', 'tester');

  perform app.provision_tenant('gizmowf', 'Gizmo Workflow Co', 'idem-gizmowf', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmowf');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000001404', 'othertenantadminwf@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantadminwf@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001404', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.workflow_hooks: always_true/noop are seeded; app.register_workflow_hook is idempotent and Supreme-Admin-only'
do $$
declare
  v_count integer;
  v_registered1 app.workflow_hooks;
  v_registered2 app.workflow_hooks;
begin
  select count(*) into v_count from app.workflow_hooks where code in ('always_true', 'noop');
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly the 2 seeded hooks, saw %', v_count;
  end if;

  begin
    perform app.register_workflow_hook('never_true', 'guard', 'Never True', 'a registered-but-unimplemented guard for fail-closed testing', '00000000-0000-0000-0000-000000001401', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied registering a workflow hook';
  exception
    when insufficient_privilege then
      null;
  end;

  v_registered1 := app.register_workflow_hook('never_true', 'guard', 'Never True', 'a registered-but-unimplemented guard for fail-closed testing', '00000000-0000-0000-0000-000000001403', 'supreme admin');
  v_registered2 := app.register_workflow_hook('never_true', 'guard', 'Never True', 'a registered-but-unimplemented guard for fail-closed testing', '00000000-0000-0000-0000-000000001403', 'supreme admin');
  if v_registered1.code <> v_registered2.code then
    raise exception 'assertion failed: expected a repeated registration to be idempotent';
  end if;
end;
$$;

\echo '>> app.evaluate_workflow_guard: direct-call coverage -- null guard and always_true both pass; an unregistered code raises workflow_unknown_guard'
do $$
begin
  if not app.evaluate_workflow_guard(null) then
    raise exception 'assertion failed: expected a null guard code to unconditionally pass';
  end if;
  if not app.evaluate_workflow_guard('always_true') then
    raise exception 'assertion failed: expected the always_true guard to pass';
  end if;

  begin
    perform app.evaluate_workflow_guard('totally_unregistered_guard_code');
    raise exception 'assertion failed: expected an unregistered guard code to raise workflow_unknown_guard';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.validate_workflow_definition / app.publish_workflow_definition: every structural failure mode is a distinct, named exception; a valid definition publishes'
do $$
declare
  v_tenant_id uuid;
  v_draft app.config_versions;
  v_published app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewf');
  v_draft := app.create_config_draft('workflow', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001401', 'tenant admin');

  -- workflow_missing_states: no 'states' item at all.
  perform app.set_config_items(v_draft.id, '[{"key": "initial_state", "value": "draft"}]'::jsonb, '00000000-0000-0000-0000-000000001401', 'tenant admin');
  begin
    perform app.publish_workflow_definition(v_draft.id, '00000000-0000-0000-0000-000000001401', null, 'tenant admin');
    raise exception 'assertion failed: expected a missing states item to raise workflow_missing_states';
  exception
    when check_violation then
      if sqlerrm not like 'workflow_missing_states%' then
        raise exception 'assertion failed: expected workflow_missing_states, got %', sqlerrm;
      end if;
  end;

  -- workflow_invalid_initial_state: initial_state not among states.
  perform app.set_config_items(v_draft.id, '[{"key": "states", "value": ["a", "b"]}, {"key": "initial_state", "value": "c"}]'::jsonb, '00000000-0000-0000-0000-000000001401', 'tenant admin');
  begin
    perform app.publish_workflow_definition(v_draft.id, '00000000-0000-0000-0000-000000001401', null, 'tenant admin');
    raise exception 'assertion failed: expected an out-of-set initial_state to raise workflow_invalid_initial_state';
  exception
    when check_violation then
      if sqlerrm not like 'workflow_invalid_initial_state%' then
        raise exception 'assertion failed: expected workflow_invalid_initial_state, got %', sqlerrm;
      end if;
  end;

  -- workflow_invalid_terminal_state: a terminal state not among states.
  perform app.set_config_items(
    v_draft.id,
    '[{"key": "states", "value": ["a", "b"]}, {"key": "initial_state", "value": "a"}, {"key": "terminal_states", "value": ["z"]}, {"key": "transitions", "value": [{"from": "a", "to": "b"}]}]'::jsonb,
    '00000000-0000-0000-0000-000000001401', 'tenant admin'
  );
  begin
    perform app.publish_workflow_definition(v_draft.id, '00000000-0000-0000-0000-000000001401', null, 'tenant admin');
    raise exception 'assertion failed: expected an out-of-set terminal state to raise workflow_invalid_terminal_state';
  exception
    when check_violation then
      if sqlerrm not like 'workflow_invalid_terminal_state%' then
        raise exception 'assertion failed: expected workflow_invalid_terminal_state, got %', sqlerrm;
      end if;
  end;

  -- workflow_invalid_transition_from / _to: transitions referencing undeclared states.
  perform app.set_config_items(
    v_draft.id,
    '[{"key": "states", "value": ["a", "b"]}, {"key": "initial_state", "value": "a"}, {"key": "terminal_states", "value": ["b"]}, {"key": "transitions", "value": [{"from": "x", "to": "b"}]}]'::jsonb,
    '00000000-0000-0000-0000-000000001401', 'tenant admin'
  );
  begin
    perform app.publish_workflow_definition(v_draft.id, '00000000-0000-0000-0000-000000001401', null, 'tenant admin');
    raise exception 'assertion failed: expected an undeclared from-state to raise workflow_invalid_transition_from';
  exception
    when check_violation then
      if sqlerrm not like 'workflow_invalid_transition_from%' then
        raise exception 'assertion failed: expected workflow_invalid_transition_from, got %', sqlerrm;
      end if;
  end;

  perform app.set_config_items(
    v_draft.id,
    '[{"key": "states", "value": ["a", "b"]}, {"key": "initial_state", "value": "a"}, {"key": "terminal_states", "value": ["b"]}, {"key": "transitions", "value": [{"from": "a", "to": "y"}]}]'::jsonb,
    '00000000-0000-0000-0000-000000001401', 'tenant admin'
  );
  begin
    perform app.publish_workflow_definition(v_draft.id, '00000000-0000-0000-0000-000000001401', null, 'tenant admin');
    raise exception 'assertion failed: expected an undeclared to-state to raise workflow_invalid_transition_to';
  exception
    when check_violation then
      if sqlerrm not like 'workflow_invalid_transition_to%' then
        raise exception 'assertion failed: expected workflow_invalid_transition_to, got %', sqlerrm;
      end if;
  end;

  -- workflow_unknown_guard / workflow_unknown_effect: hook codes that were never registered at all.
  perform app.set_config_items(
    v_draft.id,
    '[{"key": "states", "value": ["a", "b"]}, {"key": "initial_state", "value": "a"}, {"key": "terminal_states", "value": ["b"]}, {"key": "transitions", "value": [{"from": "a", "to": "b", "guard": "nonexistent_guard"}]}]'::jsonb,
    '00000000-0000-0000-0000-000000001401', 'tenant admin'
  );
  begin
    perform app.publish_workflow_definition(v_draft.id, '00000000-0000-0000-0000-000000001401', null, 'tenant admin');
    raise exception 'assertion failed: expected an unregistered guard reference to raise workflow_unknown_guard';
  exception
    when check_violation then
      if sqlerrm not like 'workflow_unknown_guard%' then
        raise exception 'assertion failed: expected workflow_unknown_guard, got %', sqlerrm;
      end if;
  end;

  perform app.set_config_items(
    v_draft.id,
    '[{"key": "states", "value": ["a", "b"]}, {"key": "initial_state", "value": "a"}, {"key": "terminal_states", "value": ["b"]}, {"key": "transitions", "value": [{"from": "a", "to": "b", "effect": "nonexistent_effect"}]}]'::jsonb,
    '00000000-0000-0000-0000-000000001401', 'tenant admin'
  );
  begin
    perform app.publish_workflow_definition(v_draft.id, '00000000-0000-0000-0000-000000001401', null, 'tenant admin');
    raise exception 'assertion failed: expected an unregistered effect reference to raise workflow_unknown_effect';
  exception
    when check_violation then
      if sqlerrm not like 'workflow_unknown_effect%' then
        raise exception 'assertion failed: expected workflow_unknown_effect, got %', sqlerrm;
      end if;
  end;

  -- workflow_unreachable_state: a declared state with no incoming path from initial_state.
  perform app.set_config_items(
    v_draft.id,
    '[{"key": "states", "value": ["a", "b", "orphan"]}, {"key": "initial_state", "value": "a"}, {"key": "terminal_states", "value": ["b"]}, {"key": "transitions", "value": [{"from": "a", "to": "b"}]}]'::jsonb,
    '00000000-0000-0000-0000-000000001401', 'tenant admin'
  );
  begin
    perform app.publish_workflow_definition(v_draft.id, '00000000-0000-0000-0000-000000001401', null, 'tenant admin');
    raise exception 'assertion failed: expected an unreachable declared state to raise workflow_unreachable_state';
  exception
    when check_violation then
      if sqlerrm not like 'workflow_unreachable_state%' then
        raise exception 'assertion failed: expected workflow_unreachable_state, got %', sqlerrm;
      end if;
  end;

  -- workflow_dead_end_state: a reachable, non-terminal state with zero outgoing transitions.
  perform app.set_config_items(
    v_draft.id,
    '[{"key": "states", "value": ["a", "b"]}, {"key": "initial_state", "value": "a"}, {"key": "terminal_states", "value": []}, {"key": "transitions", "value": [{"from": "a", "to": "b"}]}]'::jsonb,
    '00000000-0000-0000-0000-000000001401', 'tenant admin'
  );
  begin
    perform app.publish_workflow_definition(v_draft.id, '00000000-0000-0000-0000-000000001401', null, 'tenant admin');
    raise exception 'assertion failed: expected a non-terminal state with no outgoing transition to raise workflow_dead_end_state';
  exception
    when check_violation then
      if sqlerrm not like 'workflow_dead_end_state%' then
        raise exception 'assertion failed: expected workflow_dead_end_state, got %', sqlerrm;
      end if;
  end;

  -- Now the real, valid example: draft -> submitted -> approved|rejected.
  perform app.set_config_items(
    v_draft.id,
    ('[' ||
      '{"key": "states", "value": ["draft", "submitted", "approved", "rejected"]}, ' ||
      '{"key": "initial_state", "value": "draft"}, ' ||
      '{"key": "terminal_states", "value": ["approved", "rejected"]}, ' ||
      '{"key": "transitions", "value": [' ||
        '{"from": "draft", "to": "submitted"}, ' ||
        '{"from": "submitted", "to": "approved", "guard": "always_true", "effect": "noop"}, ' ||
        '{"from": "submitted", "to": "rejected"}' ||
      ']}' ||
    ']')::jsonb,
    '00000000-0000-0000-0000-000000001401', 'tenant admin'
  );

  begin
    perform app.publish_workflow_definition(v_draft.id, '00000000-0000-0000-0000-000000001402', null, 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied publishing a tenant-scoped workflow definition';
  exception
    when insufficient_privilege then
      null;
  end;

  v_published := app.publish_workflow_definition(v_draft.id, '00000000-0000-0000-0000-000000001401', null, 'tenant admin');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the valid draft -> submitted -> approved|rejected definition to publish, got %', v_published.status;
  end if;
end;
$$;

\echo '>> app.start_workflow_instance: requires a published definition, is authority-gated and idempotent on (tenant_id, idempotency_key)'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_published_version_id uuid;
  v_draft_version_id uuid;
  v_instance1 app.workflow_instances;
  v_instance2 app.workflow_instances;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewf');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmowf');

  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'workflow' and o.scope_level = 'tenant' and v.status = 'published';

  -- Draft a second, never-published version of the same object to exercise the not-published gate.
  v_draft_version_id := (app.create_config_draft('workflow', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001401', 'tenant admin')).id;

  begin
    perform app.start_workflow_instance(v_draft_version_id, v_tenant_id, 'quotation', '00000000-0000-0000-0000-000000009001', 'inst-wf-bad', '00000000-0000-0000-0000-000000001401', 'tenant admin');
    raise exception 'assertion failed: expected starting an instance from a non-published version to raise workflow_definition_not_published';
  exception
    when check_violation then
      if sqlerrm not like 'workflow_definition_not_published%' then
        raise exception 'assertion failed: expected workflow_definition_not_published, got %', sqlerrm;
      end if;
  end;
  perform app.discard_config_draft(v_draft_version_id, '00000000-0000-0000-0000-000000001401', 'cleanup', 'tenant admin');

  begin
    perform app.start_workflow_instance(v_published_version_id, v_tenant_id, 'quotation', '00000000-0000-0000-0000-000000009001', 'inst-wf-1', '00000000-0000-0000-0000-000000001404', 'other tenant admin');
    raise exception 'assertion failed: expected an identity with no membership in acmewf to be denied starting an instance there';
  exception
    when insufficient_privilege then
      null;
  end;

  v_instance1 := app.start_workflow_instance(v_published_version_id, v_tenant_id, 'quotation', '00000000-0000-0000-0000-000000009001', 'inst-wf-1', '00000000-0000-0000-0000-000000001402', 'regular user');
  if v_instance1.current_state <> 'draft' or v_instance1.status <> 'active' then
    raise exception 'assertion failed: expected a fresh instance at current_state=draft status=active, got current_state=% status=%', v_instance1.current_state, v_instance1.status;
  end if;

  v_instance2 := app.start_workflow_instance(v_published_version_id, v_tenant_id, 'quotation', '00000000-0000-0000-0000-000000009001', 'inst-wf-1', '00000000-0000-0000-0000-000000001402', 'regular user');
  if v_instance2.id <> v_instance1.id then
    raise exception 'assertion failed: expected a repeated start with the same idempotency_key to return the existing instance, not create a second one';
  end if;

  if (select count(*) from app.workflow_transition_history where instance_id = v_instance1.id and event_type = 'start') <> 1 then
    raise exception 'assertion failed: expected exactly one start history row (the idempotent replay must not insert a duplicate)';
  end if;
end;
$$;

\echo '>> app.transition_workflow_instance: optimistic concurrency, declared-transition enforcement, guard evaluation, and terminal-state completion'
do $$
declare
  v_tenant_id uuid;
  v_instance app.workflow_instances;
  v_after_submit app.workflow_instances;
  v_after_approve app.workflow_instances;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewf');
  select * into v_instance from app.workflow_instances where tenant_id = v_tenant_id and idempotency_key = 'inst-wf-1';

  begin
    perform app.transition_workflow_instance(v_instance.id, 'submitted', 'approved', '00000000-0000-0000-0000-000000001402', 'regular user');
    raise exception 'assertion failed: expected a mismatched expected_current_state to raise stale_workflow_state';
  exception
    when check_violation then
      if sqlerrm not like 'stale_workflow_state%' then
        raise exception 'assertion failed: expected stale_workflow_state, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.transition_workflow_instance(v_instance.id, 'draft', 'rejected', '00000000-0000-0000-0000-000000001402', 'regular user');
    raise exception 'assertion failed: expected an undeclared draft -> rejected transition to raise invalid_workflow_transition';
  exception
    when check_violation then
      if sqlerrm not like 'invalid_workflow_transition%' then
        raise exception 'assertion failed: expected invalid_workflow_transition, got %', sqlerrm;
      end if;
  end;

  v_after_submit := app.transition_workflow_instance(v_instance.id, 'draft', 'submitted', '00000000-0000-0000-0000-000000001402', 'regular user', 'submitting for approval');
  if v_after_submit.current_state <> 'submitted' or v_after_submit.status <> 'active' then
    raise exception 'assertion failed: expected current_state=submitted status=active after a non-terminal transition, got current_state=% status=%', v_after_submit.current_state, v_after_submit.status;
  end if;

  v_after_approve := app.transition_workflow_instance(v_instance.id, 'submitted', 'approved', '00000000-0000-0000-0000-000000001402', 'regular user', 'approved');
  if v_after_approve.current_state <> 'approved' or v_after_approve.status <> 'completed' or v_after_approve.ended_at is null then
    raise exception 'assertion failed: expected current_state=approved status=completed ended_at set after reaching a terminal state, got current_state=% status=% ended_at=%', v_after_approve.current_state, v_after_approve.status, v_after_approve.ended_at;
  end if;

  begin
    perform app.transition_workflow_instance(v_instance.id, 'approved', 'draft', '00000000-0000-0000-0000-000000001402', 'regular user');
    raise exception 'assertion failed: expected a transition attempt on a completed instance to raise workflow_instance_not_active';
  exception
    when check_violation then
      if sqlerrm not like 'workflow_instance_not_active%' then
        raise exception 'assertion failed: expected workflow_instance_not_active, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> app.evaluate_workflow_guard fail-closed path exercised through a real transition: a registered-but-unimplemented guard blocks the transition with guard_not_implemented, never silently passes'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_draft app.config_versions;
  v_published app.config_versions;
  v_instance app.workflow_instances;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewf');
  v_role_id := (select id from app.roles where tenant_id = v_tenant_id and name = 'Guard Test Role WF');

  v_draft := app.create_config_draft('workflow', v_tenant_id, 'role', v_role_id, '00000000-0000-0000-0000-000000001401', 'tenant admin');
  perform app.set_config_items(
    v_draft.id,
    ('[' ||
      '{"key": "states", "value": ["start", "done"]}, ' ||
      '{"key": "initial_state", "value": "start"}, ' ||
      '{"key": "terminal_states", "value": ["done"]}, ' ||
      '{"key": "transitions", "value": [{"from": "start", "to": "done", "guard": "never_true"}]}' ||
    ']')::jsonb,
    '00000000-0000-0000-0000-000000001401', 'tenant admin'
  );
  v_published := app.publish_workflow_definition(v_draft.id, '00000000-0000-0000-0000-000000001401', null, 'tenant admin');

  v_instance := app.start_workflow_instance(v_published.id, v_tenant_id, 'generic', null, 'inst-wf-guard-1', '00000000-0000-0000-0000-000000001402', 'regular user');

  begin
    perform app.transition_workflow_instance(v_instance.id, 'start', 'done', '00000000-0000-0000-0000-000000001402', 'regular user');
    raise exception 'assertion failed: expected the registered-but-unimplemented never_true guard to fail closed with guard_not_implemented, not silently pass';
  exception
    when feature_not_supported then
      if sqlerrm not like 'guard_not_implemented%' then
        raise exception 'assertion failed: expected guard_not_implemented, got %', sqlerrm;
      end if;
  end;

  if (select current_state from app.workflow_instances where id = v_instance.id) <> 'start' then
    raise exception 'assertion failed: expected the instance to remain at start (the rejected transition must not have applied)';
  end if;
end;
$$;

\echo '>> app.cancel_workflow_instance: active -> cancelled; rejects cancelling an already-terminal instance'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_instance app.workflow_instances;
  v_cancelled app.workflow_instances;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewf');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'workflow' and o.scope_level = 'tenant' and v.status = 'published';

  v_instance := app.start_workflow_instance(v_published_version_id, v_tenant_id, 'quotation', '00000000-0000-0000-0000-000000009002', 'inst-wf-2', '00000000-0000-0000-0000-000000001402', 'regular user');
  v_cancelled := app.cancel_workflow_instance(v_instance.id, '00000000-0000-0000-0000-000000001401', 'tenant admin', 'duplicate request');
  if v_cancelled.status <> 'cancelled' or v_cancelled.ended_at is null or v_cancelled.ended_reason <> 'duplicate request' then
    raise exception 'assertion failed: expected status=cancelled with ended_at/ended_reason set, got status=% ended_at=% ended_reason=%', v_cancelled.status, v_cancelled.ended_at, v_cancelled.ended_reason;
  end if;

  begin
    perform app.cancel_workflow_instance(v_instance.id, '00000000-0000-0000-0000-000000001401', 'tenant admin', 'again');
    raise exception 'assertion failed: expected cancelling an already-cancelled instance to raise workflow_instance_not_active';
  exception
    when check_violation then
      if sqlerrm not like 'workflow_instance_not_active%' then
        raise exception 'assertion failed: expected workflow_instance_not_active, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> app.get_workflow_instance_history: authority-gated, ordered oldest-first, and reflects every real event on the instance'
do $$
declare
  v_tenant_id uuid;
  v_instance_id uuid;
  v_rows app.workflow_transition_history[];
  v_row app.workflow_transition_history;
  v_i integer := 0;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewf');
  select id into v_instance_id from app.workflow_instances where tenant_id = v_tenant_id and idempotency_key = 'inst-wf-1';

  begin
    perform app.get_workflow_instance_history(v_instance_id, '00000000-0000-0000-0000-000000001404');
    raise exception 'assertion failed: expected an identity with no membership in acmewf to be denied reading instance history';
  exception
    when insufficient_privilege then
      null;
  end;

  select array_agg(h order by h.occurred_at) into v_rows from app.get_workflow_instance_history(v_instance_id, '00000000-0000-0000-0000-000000001402') h;
  if array_length(v_rows, 1) <> 3 then
    raise exception 'assertion failed: expected exactly 3 history rows (start, draft->submitted, submitted->approved), saw %', array_length(v_rows, 1);
  end if;
  if v_rows[1].event_type <> 'start' or v_rows[2].to_state <> 'submitted' or v_rows[3].to_state <> 'approved' then
    raise exception 'assertion failed: expected history rows in start / ->submitted / ->approved order';
  end if;
end;
$$;

\echo '>> every workflow mutation self-captures a canonical app.audit_logs entry (no bespoke *_history table for hooks/definitions -- app.workflow_transition_history exists only for instance runtime events)'
do $$
declare
  v_tenant_id uuid;
  v_actions text[] := array['start_workflow_instance', 'transition_workflow_instance', 'cancel_workflow_instance'];
  v_action text;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewf');

  foreach v_action in array v_actions loop
    select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_id and action = v_action;
    if v_count = 0 then
      raise exception 'assertion failed: expected at least one app.audit_logs entry for action=%, saw none', v_action;
    end if;
  end loop;

  select count(*) into v_count from app.audit_logs where action = 'register_workflow_hook' and tenant_id is null;
  if v_count = 0 then
    raise exception 'assertion failed: expected a platform-wide (null tenant_id) audit entry for register_workflow_hook';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has direct RLS-scoped SELECT on workflow_instances but none on workflow_transition_history; anon holds no EXECUTE on service_role-only mutations (ERR-2026-004 regression guard)'
do $$
declare
  v_has_privilege boolean;
begin
  select has_table_privilege('authenticated', 'app.workflow_instances', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold direct SELECT on app.workflow_instances (normal tenant business data, RLS-scoped)';
  end if;

  select has_table_privilege('authenticated', 'app.workflow_transition_history', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold no direct SELECT on app.workflow_transition_history (app.get_workflow_instance_history is the sole read path)';
  end if;

  select has_table_privilege('anon', 'app.workflow_instances', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no privilege on app.workflow_instances at all';
  end if;

  select has_table_privilege('authenticated', 'app.workflow_hooks', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold SELECT on app.workflow_hooks (platform-owned reference data)';
  end if;

  select has_function_privilege('authenticated', 'app.get_workflow_instance_history(uuid, uuid)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on app.get_workflow_instance_history';
  end if;

  select has_function_privilege('anon', 'app.get_workflow_instance_history(uuid, uuid)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on app.get_workflow_instance_history';
  end if;

  select has_function_privilege('anon', 'app.start_workflow_instance(uuid, uuid, text, uuid, text, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.start_workflow_instance (ERR-2026-004 regression guard)';
  end if;

  select has_function_privilege('anon', 'app.transition_workflow_instance(uuid, text, text, uuid, text, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.transition_workflow_instance (ERR-2026-004 regression guard)';
  end if;
end;
$$;
