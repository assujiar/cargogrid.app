-- ISS-2026-070 (docs/runtime/KNOWN_ISSUES.md), item 1's REMAINING three PLT-127 wiring points.
--
-- The entry's own 2026-09-02 update closed the overdue-task half
-- (20260902043000_wire_onboarding_offboarding_overdue_task_sweep.sql) and then said plainly what
-- it had NOT closed:
--
--     "Task assignment, provisioning/revocation completion, and finalize-approval routing still
--      capture only an app.onboarding_case_events row and an app.audit_logs entry, with no
--      notification call of any kind; each is a distinct wiring point inside
--      app.assign_onboarding_task/app.request_onboarding_access_provisioning/etc, not a scheduled
--      sweep, and none was touched by this pass."
--
-- This migration closes exactly those three, and nothing else. It invents no new pattern: the
-- send primitive is app.queue_notification (PLT-127), the consumer contract is the one
-- app._queue_ticket_escalation_notification (HRT-291, 20260731160000) established and
-- app.run_onboarding_overdue_task_sweep already copied -- resolve a published template, resolve a
-- REAL recipient identity, call the real primitive inside a narrowly-scoped BEGIN/EXCEPTION so a
-- notification failure can never roll back or abort the governed business write it accompanies,
-- and ALWAYS record a discriminated app.onboarding_case_events row, never a silent drop.
--
-- ===========================================================================
-- Live schema re-verified before writing this file
-- ===========================================================================
--
--   * The four target functions' live bodies were read from the LAST migration that defines each
--     (app.assign_onboarding_task from 20260730880000; app.request_onboarding_access_provisioning
--     from 20260730890000; app.request_onboarding_access_revocation and
--     app.decide_onboarding_case_finalize_approval from 20260731190000;
--     app.submit_onboarding_case_for_finalize_approval from 20260831250000, which is where
--     ISS-2026-069's own per-domain approval routing replaced the hardcoded
--     config_type_code='approval' selector with app.resolve_approval_config_type_code) and are
--     reproduced below VERBATIM apart from the single notification statement each gains.
--     Each of the five was then diffed against pg_get_functiondef on the live hosted project
--     and found byte-identical -- not spot-checked, all five. Deriving these by a case-
--     SENSITIVE grep is the one way to get this wrong: 20260831250000 writes its CREATE OR
--     REPLACE in upper case, so a lower-case search silently returns the superseded
--     20260730880000 body and this migration would have reverted ISS-2026-069's fix. It did,
--     on the first attempt, and scripts/db-tests/config.sql caught it. No signature, no `security definer`, no `set search_path`, no guard,
--     no raise, no audit call and no return value changes.
--   * app.queue_notification (20260719130000) is unchanged: it refuses a recipient who is not an
--     active member of the tenant (`notification_recipient_unauthorized`) and refuses a context
--     value containing an angle bracket or a non-https URI
--     (app.render_notification_template's own guards). BOTH are ordinary, expected outcomes at
--     these call sites -- a revoked identity, an employee name carrying a stray '<' -- which is
--     precisely why every call here is wrapped rather than trusted.
--   * app.approval_request_steps (20260719090000) is unchanged: approver_type in
--     ('role','specific_user'), status in ('pending','active','approved','rejected','skipped').
--   * app.onboarding_case_events.event_type carries no CHECK constraint (confirmed against
--     20260730880000), so the discriminated '<type>_notified' / '<type>_notification_failed'
--     event codes below need no constraint widening.
--
-- ===========================================================================
-- What this migration deliberately does NOT close, said plainly
-- ===========================================================================
--
-- Item 2's remaining half -- "nothing in this repository polls app.background_jobs and executes
-- the checklist_version_publish fan-out job" -- is untouched and stays OPEN. That is
-- ISS-2026-015's repository-wide standing gap (no live job worker exists for ANY domain), not
-- something an onboarding migration can close for itself. Every notification this migration
-- queues is channel 'in_app', whose delivery IS the row's own existence and therefore needs no
-- worker -- the same PLT-127 boundary 20260902043000 already disclosed, unchanged: no live email
-- provider exists anywhere in this repository.

-- ===========================================================================
-- STEP 1: notification-type + published-template bootstrap for the four new types, mirroring
-- 20260902043000's own bootstrap exactly (which in turn mirrors 'ticket_escalated'). A direct
-- INSERT rather than app.register_notification_type/app.create_config_draft/app.
-- publish_config_version because migration-apply context has no live actor session and all three
-- of those RPCs are Supreme-Admin- or scope-authority-gated. channels=['in_app'] ONLY.
-- ===========================================================================

insert into app.notification_types (code, name, owner_primitive_code, registered_by) values
  ('onboarding_task_assigned', 'Onboarding/Offboarding Task Assigned', 'HRS', 'system'),
  ('onboarding_access_provisioning_completed', 'Onboarding Access Provisioning Completed', 'HRS', 'system'),
  ('onboarding_finalize_approval_requested', 'Onboarding Case Finalize Approval Requested', 'HRS', 'system'),
  ('onboarding_finalize_approval_decided', 'Onboarding Case Finalize Approval Decided', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by) values
  ('notification:onboarding_task_assigned', 'Onboarding/Offboarding Task Assigned Notification', 'HRS', 'system'),
  ('notification:onboarding_access_provisioning_completed', 'Onboarding Access Provisioning Completed Notification', 'HRS', 'system'),
  ('notification:onboarding_finalize_approval_requested', 'Onboarding Case Finalize Approval Requested Notification', 'HRS', 'system'),
  ('notification:onboarding_finalize_approval_decided', 'Onboarding Case Finalize Approval Decided Notification', 'HRS', 'system')
on conflict (code) do nothing;

do $bootstrap$
declare
  v_spec record;
  v_object_id uuid;
  v_version_id uuid;
begin
  for v_spec in
    select * from (values
      (
        'notification:onboarding_task_assigned',
        'Task assigned to you: {{task_title}}',
        'You have been assigned the onboarding/offboarding task "{{task_title}}" (due {{due_at}}). Open your CargoGrid onboarding workspace to work on it.'
      ),
      (
        'notification:onboarding_access_provisioning_completed',
        'Access {{request_type}} for {{employee_name}}',
        'The access task "{{task_title}}" you own has completed: platform access for {{employee_name}} was {{request_type}}. Open your CargoGrid onboarding workspace to review the recorded evidence.'
      ),
      (
        'notification:onboarding_finalize_approval_requested',
        'Approval needed: finalize a {{case_type}} case',
        'A {{case_type}} case is waiting on your decision to finalize. Open your CargoGrid approvals workspace to approve or reject it.'
      ),
      (
        'notification:onboarding_finalize_approval_decided',
        'Finalize {{decision}}: your {{case_type}} case',
        'The {{case_type}} case you submitted for finalize approval was {{decision}}. Open your CargoGrid onboarding workspace to see the outcome.'
      )
    ) as t(config_type_code, subject, body)
  loop
    select id into v_object_id from app.config_objects
    where config_type_code = v_spec.config_type_code and tenant_id is null and scope_level = 'global' and scope_id is null;

    if v_object_id is null then
      insert into app.config_objects (config_type_code, tenant_id, scope_level, scope_id, created_by)
      values (v_spec.config_type_code, null, 'global', null, 'system')
      returning id into v_object_id;
    end if;

    select id into v_version_id from app.config_versions where config_object_id = v_object_id and status = 'published';

    if v_version_id is null then
      insert into app.config_versions (config_object_id, version_number, status, effective_from, created_by, published_by, published_at)
      values (v_object_id, 1, 'published', now(), 'system', 'system', now())
      returning id into v_version_id;

      insert into app.config_items (config_version_id, key, value) values
        (v_version_id, 'channels', '["in_app"]'::jsonb),
        (v_version_id, 'default_locale', '"en"'::jsonb),
        (v_version_id, 'templates', jsonb_build_object('en', jsonb_build_object('subject', v_spec.subject, 'body', v_spec.body)));
    end if;

    raise notice '% notification template ready: config_object=%, published_version=%', v_spec.config_type_code, v_object_id, v_version_id;
  end loop;
end;
$bootstrap$;

-- ===========================================================================
-- STEP 2: the shared send helper. Every one of the three wiring points below calls exactly this,
-- rather than each re-implementing template resolution + exception isolation + event recording
-- three slightly different ways.
--
-- It NEVER raises. A missing published template, a recipient who lost tenant membership between
-- the business write and this call, an employee name carrying an angle bracket -- each is
-- recorded as a discriminated '<type>_notification_failed' event and reported through the return
-- value, never allowed to abort or roll back the governed business write that already succeeded.
-- The BEGIN/EXCEPTION deliberately wraps ONLY the app.queue_notification call, so the event
-- insert that records the outcome can never itself be rolled back by the failure it is recording.
-- ===========================================================================

create function app._queue_onboarding_case_notification(
  p_tenant_id uuid,
  p_case_id uuid,
  p_notification_type text,
  p_recipient_auth_user_id uuid,
  p_context jsonb,
  p_dedupe_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns boolean
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_config_version_id uuid;
  v_ok boolean := false;
  v_err text;
begin
  -- No real Platform identity to notify (an unassigned category-only owner, a case with no
  -- submitter recorded). Structurally expected, not a failure -- and deliberately NOT recorded as
  -- a failed notification, because nothing was ever addressable.
  if p_recipient_auth_user_id is null then
    return false;
  end if;

  select v.id into v_config_version_id
  from app.config_versions v
  join app.config_objects o on o.id = v.config_object_id
  where o.config_type_code = 'notification:' || p_notification_type and v.status = 'published'
  order by v.version_number desc
  limit 1;

  if v_config_version_id is null then
    insert into app.onboarding_case_events (case_id, tenant_id, event_type, actor_auth_user_id, actor_label, notes)
    values (p_case_id, p_tenant_id, p_notification_type || '_notification_failed', p_actor_auth_user_id, p_actor_label,
            'no published notification:' || p_notification_type || ' template is configured');
    return false;
  end if;

  begin
    perform app.queue_notification(
      v_config_version_id, p_tenant_id, p_notification_type, p_recipient_auth_user_id, 'in_app', 'en',
      coalesce(p_context, '{}'::jsonb), p_dedupe_key, p_actor_auth_user_id, p_actor_label
    );
    v_ok := true;
  exception
    when others then
      v_err := sqlerrm;
  end;

  if v_ok then
    insert into app.onboarding_case_events (case_id, tenant_id, event_type, actor_auth_user_id, actor_label, notes)
    values (p_case_id, p_tenant_id, p_notification_type || '_notified', p_actor_auth_user_id, p_actor_label,
            'Notification queued for recipient ' || p_recipient_auth_user_id::text);
  else
    insert into app.onboarding_case_events (case_id, tenant_id, event_type, actor_auth_user_id, actor_label, notes)
    values (p_case_id, p_tenant_id, p_notification_type || '_notification_failed', p_actor_auth_user_id, p_actor_label,
            'queue_notification raised for recipient ' || p_recipient_auth_user_id::text || ': ' || v_err);
  end if;

  return v_ok;
end;
$$;

comment on function app._queue_onboarding_case_notification(uuid, uuid, text, uuid, jsonb, text, uuid, text) is
  'ISS-2026-070 item 1: the shared PLT-127 send helper behind the task-assignment, provisioning/revocation-completion and finalize-approval-routing notifications. Resolves the published notification template for p_notification_type, calls app.queue_notification (the real engine primitive, never a re-implementation) inside a BEGIN/EXCEPTION scoped to that call alone, and ALWAYS records a discriminated app.onboarding_case_events row -- ''<type>_notified'' or ''<type>_notification_failed'' -- so a failed notification is visible in the case timeline rather than silently dropped. Never raises: the governed business write it accompanies has already succeeded and must not be rolled back by a notification problem. Returns true only when a notification was genuinely queued. A null recipient returns false without recording a failure -- there was no identity to address, which is a structural fact, not an error.';

-- ===========================================================================
-- STEP 3: the approver fan-out helper. Kept separate so the finalize-approval wiring points stay
-- one statement each, and so the "who is an approver" rule lives in exactly one place -- resolved
-- by the SAME role/specific_user semantics app.count_eligible_approvers_for_step (20260719090000)
-- already uses for its own eligibility count, never a second divergent definition.
-- ===========================================================================

create function app._notify_onboarding_finalize_approvers(
  p_tenant_id uuid,
  p_case_id uuid,
  p_request_id uuid,
  p_case_type text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns integer
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_target record;
  v_notified integer := 0;
begin
  -- status = 'active' ONLY, never 'pending'. app.request_approval (20260719090000) materializes a
  -- SEQUENTIAL request with step 1 'active' and every later step 'pending', and
  -- app.decide_approval_step flips the next one to 'active' as the chain advances -- so 'active'
  -- is exactly "whose turn it is now". Including 'pending' would tell a step-3 approver a decision
  -- was waiting on them while two earlier steps were still undecided. A parallel/threshold request
  -- materializes every step 'active' at once, and correctly notifies all of them immediately.
  for v_target in
    select distinct r.auth_user_id, r.step_id
    from (
      select s.specific_user_id as auth_user_id, s.id as step_id
      from app.approval_request_steps s
      where s.request_id = p_request_id
        and s.approver_type = 'specific_user'
        and s.status = 'active'
      union
      select ra.auth_user_id, s.id as step_id
      from app.approval_request_steps s
      join app.role_versions rv on rv.role_id = s.role_id and rv.status = 'published'
      join app.role_assignments ra on ra.role_version_id = rv.id and ra.tenant_id = p_tenant_id and ra.status = 'active'
      where s.request_id = p_request_id
        and s.approver_type = 'role'
        and s.status = 'active'
    ) r
    -- The actor is excluded deliberately: whoever just submitted the case, or just decided the
    -- previous step, does not need telling that the thing they did happened.
    where r.auth_user_id is not null and r.auth_user_id <> p_actor_auth_user_id
    order by r.auth_user_id, r.step_id
  loop
    if app._queue_onboarding_case_notification(
      p_tenant_id, p_case_id, 'onboarding_finalize_approval_requested', v_target.auth_user_id,
      jsonb_build_object('case_type', p_case_type),
      -- Per (step, recipient), not per request: a sequential chain advancing to a later step
      -- genuinely re-notifies somebody who also sat on an earlier step, instead of being
      -- swallowed as a duplicate of their previous turn.
      'onboarding-finalize-requested:' || v_target.step_id::text || ':' || v_target.auth_user_id::text,
      p_actor_auth_user_id, p_actor_label
    ) then
      v_notified := v_notified + 1;
    end if;
  end loop;

  return v_notified;
end;
$$;

comment on function app._notify_onboarding_finalize_approvers(uuid, uuid, uuid, text, uuid, text) is
  'ISS-2026-070 item 1 (finalize-approval routing): notifies every eligible approver of an onboarding/offboarding finalize-approval request''s not-yet-decided steps, resolving role-type steps through app.role_assignments joined to published app.role_versions and specific_user-type steps directly -- the identical rule app.count_eligible_approvers_for_step already uses, never a second definition of who an approver is. The deciding/submitting actor is excluded. Dedupe is per (step, recipient) so a sequential chain advancing to a later step re-notifies somebody who also sat on an earlier step. Never raises (every send goes through app._queue_onboarding_case_notification). Returns the count of genuinely new notifications queued.';

revoke execute on function app._queue_onboarding_case_notification(uuid, uuid, text, uuid, jsonb, text, uuid, text) from public, anon, authenticated;
grant execute on function app._queue_onboarding_case_notification(uuid, uuid, text, uuid, jsonb, text, uuid, text) to service_role;
revoke execute on function app._notify_onboarding_finalize_approvers(uuid, uuid, uuid, text, uuid, text) from public, anon, authenticated;
grant execute on function app._notify_onboarding_finalize_approvers(uuid, uuid, uuid, text, uuid, text) to service_role;

-- ===========================================================================
-- STEP 4: the four wiring points. Each function below is its CURRENT live definition reproduced
-- verbatim, plus exactly one notification statement. Nothing else in any of them changes.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- app.assign_onboarding_task -- wiring point 1 (task assignment)
-- ---------------------------------------------------------------------------

create or replace function app.assign_onboarding_task(
  p_case_id uuid, p_task_id uuid, p_expected_version integer, p_owner_auth_user_id uuid,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Edit');

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_owner_auth_user_id is not null and not app.has_active_tenant_membership(v_task.tenant_id, p_owner_auth_user_id) then
    raise exception 'owner_not_found: % is not an active member of tenant %', p_owner_auth_user_id, v_task.tenant_id using errcode = 'no_data_found';
  end if;

  update app.onboarding_case_tasks
  set owner_auth_user_id = p_owner_auth_user_id
  where id = p_task_id and record_version = p_expected_version
  returning * into v_task;
  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_onboarding_task',
    'app.onboarding_case_tasks', v_task.id, 'success', null, null, app.onboarding_case_task_audit_projection(v_task)
  );


  -- ISS-2026-070 item 1, wiring point 1 of 3 (TASK ASSIGNMENT). Before this
  -- migration an assignment produced an app.audit_logs row and nothing else --
  -- the person who just became accountable for the task was never told. Now the
  -- new owner is notified through PLT-127's own real engine, using the identical
  -- helper/dedupe/discriminated-event contract app.run_onboarding_overdue_task_
  -- sweep (20260902043000) already established for this same entry's overdue
  -- half. Self-assignment is deliberately NOT notified: the actor already knows,
  -- and notifying them would be pure noise, not a missing signal.
  if p_owner_auth_user_id is not null and p_owner_auth_user_id <> p_actor_auth_user_id then
    perform app._queue_onboarding_case_notification(
      v_task.tenant_id, p_case_id, 'onboarding_task_assigned', p_owner_auth_user_id,
      jsonb_build_object('task_title', v_task.title, 'due_at', coalesce(v_task.due_at::text, 'no due date set')),
      'onboarding-task-assigned:' || p_task_id::text || ':' || v_task.record_version::text,
      p_actor_auth_user_id, p_actor_label
    );
  end if;

  return v_task;
end;
$$;

-- ---------------------------------------------------------------------------
-- app.request_onboarding_access_provisioning -- wiring point 2a (provisioning completion)
-- ---------------------------------------------------------------------------

create or replace function app.request_onboarding_access_provisioning(
  p_case_id uuid, p_task_id uuid, p_expected_version integer,
  p_target_auth_user_id uuid, p_role_version_ids uuid[], p_org_unit_id uuid,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
  v_case app.onboarding_offboarding_cases;
  v_employee app.employees;
  v_user app.users;
  v_role_version_id uuid;
  v_request app.onboarding_task_provisioning_requests;
  v_job app.jobs;
  v_roles_granted integer := 0;
  v_roles_deferred integer := 0;
  v_completion_note text;
  v_grant_decision app.rbac_decision;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Edit');

  if v_task.task_type <> 'access_provisioning' then
    raise exception 'wrong_completion_path: task % is %, not access_provisioning', p_task_id, v_task.task_type using errcode = 'check_violation';
  end if;

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_task.status not in ('pending', 'in_progress', 'reopened') then
    raise exception 'invalid_transition: task % is %, cannot request provisioning', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if v_task.status = 'blocked' then
    raise exception 'task_blocked: task % has an incomplete dependency', p_task_id using errcode = 'check_violation';
  end if;

  -- Review-round fix (CRITICAL, privilege-escalation) -- see the migration
  -- header comment above for the full rationale.
  if coalesce(array_length(p_role_version_ids, 1), 0) > 0 then
    v_grant_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'HRS', 'Override');
    if not v_grant_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant % -- granting a real role via onboarding provisioning requires the same bar as access revocation', p_actor_auth_user_id, v_grant_decision.reason, v_task.tenant_id
        using errcode = 'insufficient_privilege';
    end if;

    foreach v_role_version_id in array p_role_version_ids loop
      perform app.assert_actor_holds_role_version_permissions(v_task.tenant_id, p_actor_auth_user_id, v_role_version_id);
    end loop;
  end if;

  select * into v_case from app.onboarding_offboarding_cases where id = p_case_id;
  if v_case.employee_master_record_id is null then
    raise exception 'case_has_no_employee: case % has no linked employee, cannot provision access', p_case_id using errcode = 'check_violation';
  end if;
  select * into v_employee from app.employees where master_record_id = v_case.employee_master_record_id;

  insert into app.onboarding_task_provisioning_requests (case_id, task_id, tenant_id, request_type, target_auth_user_id, requested_role_version_ids, org_unit_id, requested_by)
  values (p_case_id, p_task_id, v_task.tenant_id, 'grant_access', p_target_auth_user_id, coalesce(p_role_version_ids, '{}'::uuid[]), p_org_unit_id, p_actor_label)
  returning * into v_request;

  if p_target_auth_user_id is not null then
    -- Real, synchronous, governed grant -- section 16 "Platform identity
    -- authority", never a direct app.users/app.role_assignments write.
    v_user := app.invite_user(v_task.tenant_id, p_target_auth_user_id, coalesce(v_employee.work_email, v_employee.personal_email, v_employee.full_name || '@pending.invite'), v_employee.full_name, p_org_unit_id, p_actor_label, now() + interval '14 days');

    if v_employee.user_id is null then
      perform app.link_employee_user(v_employee.master_record_id, v_employee.record_version, v_user.id, p_actor_auth_user_id, p_actor_label);
    elsif v_employee.user_id <> v_user.id then
      raise exception 'employee_already_linked: employee % is already linked to a different user', v_employee.master_record_id using errcode = 'check_violation';
    end if;

    -- app.assign_role (PLT-111) requires the target app.users row to already
    -- be status='active' -- a freshly-invited user is 'invited' until they
    -- accept the invite themselves. This RPC never force-activates an
    -- unconfirmed account (that would be a real, undisclosed authentication
    -- bypass) -- roles are granted immediately only when the target identity
    -- is ALREADY active; a merely-invited identity legitimately defers (the
    -- realistic "brand new hire, invite just sent" case, section 22's own
    -- "preboarding without user access"). Review-round fix (MEDIUM,
    -- stranded-state): any OTHER non-active status (revoked/suspended -- a
    -- genuinely non-activatable identity) is rejected outright instead of
    -- silently completing with an unkeepable "re-run once active" promise.
    if v_user.status = 'active' then
      foreach v_role_version_id in array coalesce(p_role_version_ids, '{}'::uuid[]) loop
        perform app.assign_role(v_task.tenant_id, v_role_version_id, p_target_auth_user_id, p_actor_auth_user_id, p_actor_label);
        v_roles_granted := v_roles_granted + 1;
      end loop;
    elsif v_user.status = 'invited' then
      v_roles_deferred := coalesce(array_length(p_role_version_ids, 1), 0);
    else
      raise exception 'target_identity_not_activatable: user % has status %, access cannot be granted or meaningfully deferred -- resolve a different target identity, or reactivate the user first', v_user.id, v_user.status
        using errcode = 'check_violation';
    end if;

    update app.onboarding_task_provisioning_requests
    set status = 'completed', result_user_id = v_user.id, completed_at = now()
    where id = v_request.id;

    v_completion_note := 'Platform access granted: user ' || v_user.id::text || ' (status ' || v_user.status || '), ' || v_roles_granted || ' role(s) granted';
    if v_roles_deferred > 0 then
      v_completion_note := v_completion_note || ', ' || v_roles_deferred || ' role(s) deferred until the user accepts their invite (re-run once active)';
    end if;

    -- Async reconciliation/dispatch record (section 17) -- e.g. a downstream
    -- welcome-email/credentials-handoff adapter would claim this job. Reuses
    -- job_type='integration_sync' (decision 8's own sibling reasoning: adding a
    -- domain-specific job_type would widen app.generic_job_types()' shared,
    -- cross-domain single source of truth, out of this single-prompt batch's
    -- own mandate).
    v_job := app.enqueue_job(v_task.tenant_id, 'integration_sync', jsonb_build_object('onboarding_task_provisioning_request_id', v_request.id, 'case_id', p_case_id, 'task_id', p_task_id, 'user_id', v_user.id), 0, 'hrt277-provisioning:' || v_request.id::text, 3, p_actor_auth_user_id, p_actor_label);
    update app.onboarding_task_provisioning_requests set job_id = v_job.job_id where id = v_request.id;

    update app.onboarding_case_tasks
    set status = 'completed', completed_at = now(), completed_by = p_actor_label,
        evidence_note = coalesce(evidence_note, v_completion_note)
    where id = p_task_id and record_version = p_expected_version
    returning * into v_task;
  else
    -- section 22 "preboarding without user access" -- no auth identity
    -- resolved yet. The request is recorded (an acknowledged handoff, never an
    -- assumed success, section 14) and the task moves to in_progress, awaiting
    -- a follow-up call with a resolved p_target_auth_user_id.
    update app.onboarding_case_tasks
    set status = 'in_progress'
    where id = p_task_id and record_version = p_expected_version
    returning * into v_task;
  end if;

  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.recompute_onboarding_case_task_blocked_state(p_case_id);

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_onboarding_access_provisioning',
    'app.onboarding_case_tasks', v_task.id, 'success', null, null, app.onboarding_case_task_audit_projection(v_task) || jsonb_build_object('provisioning_request_id', v_request.id)
  );


  -- ISS-2026-070 item 1, wiring point 2 of 3 (PROVISIONING COMPLETION). Only the
  -- branch that genuinely COMPLETED -- p_target_auth_user_id resolved, the
  -- provisioning request moved to status='completed' -- notifies. The section-22
  -- preboarding branch (no auth identity resolved yet, task left in_progress
  -- awaiting a follow-up call) completes nothing and is correctly silent; a
  -- notification there would assert a handoff that has not happened.
  -- The recipient is the TASK OWNER, not the provisioned identity: the owner is
  -- the person accountable for this checklist item, while a freshly-invited
  -- target is frequently still status='invited' and not yet an active tenant
  -- member at all (app.queue_notification would refuse them outright).
  if p_target_auth_user_id is not null
     and v_task.owner_auth_user_id is not null
     and v_task.owner_auth_user_id <> p_actor_auth_user_id then
    perform app._queue_onboarding_case_notification(
      v_task.tenant_id, p_case_id, 'onboarding_access_provisioning_completed', v_task.owner_auth_user_id,
      jsonb_build_object(
        'task_title', v_task.title,
        'request_type', 'granted',
        'employee_name', coalesce(v_employee.full_name, 'the linked employee')
      ),
      'onboarding-provisioning-completed:' || v_request.id::text,
      p_actor_auth_user_id, p_actor_label
    );
  end if;

  return v_task;
end;
$$;

-- ---------------------------------------------------------------------------
-- app.request_onboarding_access_revocation -- wiring point 2b (revocation completion)
-- ---------------------------------------------------------------------------

create or replace function app.request_onboarding_access_revocation(p_case_id uuid, p_task_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
  v_case app.onboarding_offboarding_cases;
  v_employee app.employees;
  v_request app.onboarding_task_provisioning_requests;
  v_job app.jobs;
  v_note text;
  v_revoked_user app.users;
  v_role_assignment app.role_assignments;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Override');

  if v_task.task_type <> 'access_revocation' then
    raise exception 'wrong_completion_path: task % is %, not access_revocation', p_task_id, v_task.task_type using errcode = 'check_violation';
  end if;

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_task.status not in ('pending', 'in_progress', 'reopened') then
    raise exception 'invalid_transition: task % is %, cannot request revocation', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if v_task.status = 'blocked' then
    raise exception 'task_blocked: task % has an incomplete dependency', p_task_id using errcode = 'check_violation';
  end if;

  -- Review-round fix (HIGH, spec-compliance, business rule 5): a real reason
  -- is now required, mirroring waive/reopen/cancel/rehire's own established
  -- pattern exactly.
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request access revocation' using errcode = 'check_violation';
  end if;

  select * into v_case from app.onboarding_offboarding_cases where id = p_case_id;
  select * into v_employee from app.employees where master_record_id = v_case.employee_master_record_id;

  insert into app.onboarding_task_provisioning_requests (case_id, task_id, tenant_id, request_type, target_auth_user_id, requested_by)
  values (p_case_id, p_task_id, v_task.tenant_id, 'revoke_access', null, p_actor_label)
  returning * into v_request;

  if v_employee.user_id is not null then
    -- Real, governed revocation -- app.transition_user_status already cascades
    -- both the underlying PLT-107 identity linkage AND every active PLT-108
    -- principal membership (its own migration, 20260716102620:271-285).
    perform app.transition_user_status(v_employee.user_id, 'revoked', p_reason, p_actor_label);

    -- Review-round fix (CRITICAL, correctness-concurrency /
    -- revocation-cascade-incomplete): app.transition_user_status's own
    -- revoke branch (PLT-110) never touches app.role_assignments (PLT-111),
    -- and app.evaluate_permission (PLT-112) evaluates role_assignments
    -- directly, never re-checking app.users.status or tenant membership --
    -- live-reproduced pre-fix: a revoked identity with a still-'active'
    -- role_assignments row retained full permission-gated write authority
    -- (evaluate_permission still returned allowed=true, and the identity
    -- could still call app.start_onboarding_case successfully). This is a
    -- real gap in the SHARED PLT-110/112 primitives, used by every domain in
    -- the repository, not something this migration can fix at its root
    -- without a dedicated Platform/RBAC hardening prompt and ADR (AGENTS.md
    -- "Scope and refactoring") -- see docs/runtime/KNOWN_ISSUES.md for the
    -- filed, disclosed systemic gap. What IS fixed here, bounded to this
    -- capability's own real Platform-identity-authority write (the one this
    -- whole prompt is chartered around): every ACTIVE role_assignment this
    -- identity holds in this tenant is explicitly revoked as part of this
    -- same governed call, so THIS revocation path never again leaves
    -- effective authority behind.
    select * into v_revoked_user from app.users where id = v_employee.user_id;
    for v_role_assignment in
      select * from app.role_assignments
      where tenant_id = v_task.tenant_id and auth_user_id = v_revoked_user.auth_user_id and status = 'active'
    loop
      perform app.revoke_role_assignment(v_role_assignment.id, p_reason, p_actor_label);
    end loop;

    update app.onboarding_task_provisioning_requests set status = 'completed', result_user_id = v_employee.user_id, completed_at = now() where id = v_request.id;
    v_note := 'Platform access revoked for user ' || v_employee.user_id::text || ' -- reason: ' || p_reason;

    v_job := app.enqueue_job(v_task.tenant_id, 'integration_sync', jsonb_build_object('onboarding_task_provisioning_request_id', v_request.id, 'case_id', p_case_id, 'task_id', p_task_id, 'user_id', v_employee.user_id), 0, 'hrt277-revocation:' || v_request.id::text, 3, p_actor_auth_user_id, p_actor_label);
    update app.onboarding_task_provisioning_requests set job_id = v_job.job_id where id = v_request.id;
  else
    update app.onboarding_task_provisioning_requests set status = 'completed', completed_at = now() where id = v_request.id;
    v_note := 'No linked Platform user for this employee -- nothing to revoke. Reason: ' || p_reason;
  end if;

  update app.onboarding_case_tasks
  set status = 'completed', completed_at = now(), completed_by = p_actor_label, evidence_note = coalesce(evidence_note, v_note)
  where id = p_task_id and record_version = p_expected_version
  returning * into v_task;
  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.recompute_onboarding_case_task_blocked_state(p_case_id);

  -- HRT-293 Finding B fix (self-found, CRITICAL, C-24): p_reason is already
  -- durably stored above (v_note folded into app.onboarding_case_tasks.
  -- evidence_note, and as the reason argument to app.transition_user_status/
  -- app.revoke_role_assignment, each capturing their OWN evidence trail) --
  -- never also duplicated into app.audit_logs.reason via THIS call.
  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_onboarding_access_revocation',
    'app.onboarding_case_tasks', v_task.id, 'success', null, null, app.onboarding_case_task_audit_projection(v_task) || jsonb_build_object('provisioning_request_id', v_request.id)
  );


  -- ISS-2026-070 item 1, wiring point 2 of 3, revocation half. Same recipient
  -- reasoning as the provisioning half above, and here it is not merely
  -- preferable but forced: this function has just called
  -- app.transition_user_status(..., 'revoked', ...), which cascades away every
  -- active principal membership the target held -- so the revoked identity can
  -- no longer be a valid notification recipient by construction. The task owner
  -- is the real, still-authorized person who needs to know the revocation
  -- landed. Both branches notify (a linked user was revoked, or there was no
  -- linked user to revoke): both are genuine completions of the task, and the
  -- second is exactly the case an owner most needs told, since nothing visible
  -- happened to any identity.
  if v_task.owner_auth_user_id is not null and v_task.owner_auth_user_id <> p_actor_auth_user_id then
    perform app._queue_onboarding_case_notification(
      v_task.tenant_id, p_case_id, 'onboarding_access_provisioning_completed', v_task.owner_auth_user_id,
      jsonb_build_object(
        'task_title', v_task.title,
        'request_type', 'revoked',
        'employee_name', coalesce(v_employee.full_name, 'the linked employee')
      ),
      'onboarding-revocation-completed:' || v_request.id::text,
      p_actor_auth_user_id, p_actor_label
    );
  end if;

  return v_task;
end;
$$;

-- ---------------------------------------------------------------------------
-- app.submit_onboarding_case_for_finalize_approval -- wiring point 3a (approval routing)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.submit_onboarding_case_for_finalize_approval(p_case_id uuid, p_expected_version integer, p_exit_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.onboarding_offboarding_cases
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_case app.onboarding_offboarding_cases;
  v_employee app.employees;
  v_incomplete_mandatory integer;
  v_approval_config_version_id uuid;
  v_request app.approval_requests;
begin
  select * into v_case from app.onboarding_offboarding_cases where id = p_case_id for update;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_case.status <> 'active' then
    raise exception 'invalid_transition: case % is %, only an active case can be submitted for finalize approval', p_case_id, v_case.status
      using errcode = 'check_violation';
  end if;

  -- Mandatory checklist gate (acceptance criterion 2: "mandatory checklist and
  -- downstream acknowledgements gate finalization").
  select count(*) into v_incomplete_mandatory
  from app.onboarding_case_tasks
  where case_id = p_case_id and is_mandatory and status not in ('completed', 'waived');
  if v_incomplete_mandatory > 0 then
    raise exception 'mandatory_tasks_incomplete: case % has % incomplete mandatory task(s)', p_case_id, v_incomplete_mandatory
      using errcode = 'check_violation';
  end if;

  -- Precondition-check-only against the employee's own governed lifecycle FSM
  -- (decision 1) -- never chained/driven from this function.
  if v_case.employee_master_record_id is not null then
    select * into v_employee from app.employees where master_record_id = v_case.employee_master_record_id;
    if v_case.case_type = 'onboarding' and v_employee.lifecycle_status <> 'active' then
      raise exception 'employee_not_active_yet: employee % is %, must reach active via the standard employee lifecycle (submit/decide/activate, or app.rehire_employee) before this case can finalize', v_case.employee_master_record_id, v_employee.lifecycle_status
        using errcode = 'check_violation';
    end if;
    if v_case.case_type = 'offboarding' and v_employee.lifecycle_status not in ('terminated', 'archived') then
      raise exception 'employee_not_terminated_yet: employee % is %, must be terminated (app.terminate_employee) before this case can finalize', v_case.employee_master_record_id, v_employee.lifecycle_status
        using errcode = 'check_violation';
    end if;
  end if;

  -- exit_reason is captured HERE (not at case start -- self-found defect,
  -- fixed before commit: the original CHECK constraint required a non-null
  -- exit_reason at status='active' too, which made starting ANY offboarding
  -- case impossible, since the reason genuinely is not always known yet at
  -- start time). Caller-supplied here takes precedence; the case's own
  -- already-set exit_reason (if a caller already recorded one earlier via a
  -- direct UPDATE-less path) is preserved when this call passes null.
  if v_case.case_type = 'offboarding' then
    if coalesce(p_exit_reason, v_case.exit_reason) is null or length(trim(coalesce(p_exit_reason, v_case.exit_reason))) = 0 then
      raise exception 'exit_reason_required: an offboarding case requires a non-empty exit_reason before finalize submission' using errcode = 'check_violation';
    end if;
  end if;

  select cv.id into v_approval_config_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = app._resolve_approval_config_type_code(v_case.tenant_id, 'onboarding_case') and co.tenant_id = v_case.tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

  if v_approval_config_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % has no published approval routing definition', v_case.tenant_id
      using errcode = 'check_violation';
  end if;

  v_request := app.request_approval(
    v_approval_config_version_id, v_case.tenant_id, 'onboarding_offboarding_case', p_case_id,
    p_case_id::text || ':finalize:' || p_expected_version::text, p_actor_auth_user_id, p_actor_label
  );

  update app.onboarding_offboarding_cases
  set status = 'pending_finalize_approval', finalize_approval_request_id = v_request.id,
      exit_reason = coalesce(p_exit_reason, exit_reason)
  where id = p_case_id and record_version = p_expected_version
  returning * into v_case;
  if not found then
    raise exception 'stale_version: case % target row was concurrently modified (expected version %)', p_case_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_case_id, v_case.tenant_id, 'submit_finalize_approval', 'active', 'pending_finalize_approval', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_onboarding_case_for_finalize_approval',
    'app.onboarding_offboarding_cases', v_case.id, 'success', null, null, app.onboarding_case_audit_projection(v_case)
  );


  -- ISS-2026-070 item 1, wiring point 3 of 3 (FINALIZE-APPROVAL ROUTING), first
  -- half. app.request_approval above materialized real approval steps; until now
  -- nothing told the people those steps route to that a decision was waiting on
  -- them, so the case sat in pending_finalize_approval until somebody happened to
  -- open the page. Every eligible approver of the request's not-yet-decided steps
  -- is now notified, resolved through the SAME role/specific_user rule
  -- app.count_eligible_approvers_for_step (20260719090000) already uses -- never a
  -- second, divergent notion of who an approver is.
  perform app._notify_onboarding_finalize_approvers(
    v_case.tenant_id, p_case_id, v_request.id, v_case.case_type, p_actor_auth_user_id, p_actor_label
  );

  return v_case;
end;
$function$;

-- ---------------------------------------------------------------------------
-- app.decide_onboarding_case_finalize_approval -- wiring point 3b (decision + next-step routing)
-- ---------------------------------------------------------------------------

create or replace function app.decide_onboarding_case_finalize_approval(p_request_step_id uuid, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.onboarding_offboarding_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_case app.onboarding_offboarding_cases;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id using errcode = 'no_data_found';
  end if;

  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'onboarding_offboarding_case' or v_request.entity_id is null then
    raise exception 'not_an_onboarding_case_approval: approval request % is not an onboarding/offboarding case approval', v_request.id using errcode = 'check_violation';
  end if;

  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  -- Hardened terminal-UPDATE guard from the FIRST migration (mandatory reading
  -- item 5, closing HRT-276's own Tier C finding 7/8 class before it recurs):
  -- guarded on (finalize_approval_request_id = v_request.id AND status =
  -- 'pending_finalize_approval') -- if the case is no longer awaiting THIS
  -- specific decision (concurrently cancelled), the whole function raises and
  -- rolls back atomically, including the app.decide_approval_step mutation
  -- just above, rather than silently resurrecting a cancelled case.
  if v_updated_request.status = 'approved' then
    update app.onboarding_offboarding_cases
    set status = 'finalized', finalized_at = now(), finalized_by = p_actor_label
    where id = v_request.entity_id and finalize_approval_request_id = v_request.id and status = 'pending_finalize_approval'
    returning * into v_case;
    if not found then
      raise exception 'case_finalize_no_longer_applicable: case % is no longer awaiting decision on approval request % (concurrently cancelled)', v_request.entity_id, v_request.id
        using errcode = 'serialization_failure';
    end if;
    insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, actor_auth_user_id, actor_label)
    values (v_case.id, v_case.tenant_id, 'finalize', 'pending_finalize_approval', 'finalized', p_actor_auth_user_id, p_actor_label);
  elsif v_updated_request.status = 'rejected' then
    update app.onboarding_offboarding_cases
    set status = 'active', finalize_approval_request_id = null
    where id = v_request.entity_id and finalize_approval_request_id = v_request.id and status = 'pending_finalize_approval'
    returning * into v_case;
    if not found then
      raise exception 'case_finalize_no_longer_applicable: case % is no longer awaiting decision on approval request % (concurrently cancelled)', v_request.entity_id, v_request.id
        using errcode = 'serialization_failure';
    end if;
    insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, notes, actor_auth_user_id, actor_label)
    values (v_case.id, v_case.tenant_id, 'finalize_rejected', 'pending_finalize_approval', 'active', p_reason, p_actor_auth_user_id, p_actor_label);
  else
    select * into v_case from app.onboarding_offboarding_cases where id = v_request.entity_id;
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see this migration's own header.
  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_onboarding_case_finalize_approval',
    'app.onboarding_offboarding_cases', v_case.id, 'success', null, null, app.onboarding_case_audit_projection(v_case)
  );


  -- ISS-2026-070 item 1, wiring point 3 of 3, second half -- and this is the half
  -- that makes the word ROUTING literal rather than decorative:
  --   * a TERMINAL decision (approved/rejected) notifies whoever submitted the
  --     case for approval, closing the loop they opened;
  --   * a still-PENDING request means a sequential approval chain just advanced
  --     to its next step, so that step's approvers are notified exactly as the
  --     submit path notifies the first step's. Without this, every approval
  --     after the first in a multi-step chain was silent.
  -- The dedupe key is per (step, recipient), so advancing to a new step genuinely
  -- re-notifies a person who also sat on an earlier step, rather than being
  -- swallowed as a duplicate of their previous turn.
  if v_updated_request.status in ('approved', 'rejected') then
    if v_request.requested_by_auth_user_id is not null
       and v_request.requested_by_auth_user_id <> p_actor_auth_user_id then
      perform app._queue_onboarding_case_notification(
        v_case.tenant_id, v_case.id, 'onboarding_finalize_approval_decided', v_request.requested_by_auth_user_id,
        jsonb_build_object('case_type', v_case.case_type, 'decision', v_updated_request.status),
        'onboarding-finalize-decided:' || v_request.id::text || ':' || v_updated_request.status,
        p_actor_auth_user_id, p_actor_label
      );
    end if;
  elsif v_updated_request.status = 'pending' then
    perform app._notify_onboarding_finalize_approvers(
      v_case.tenant_id, v_case.id, v_request.id, v_case.case_type, p_actor_auth_user_id, p_actor_label
    );
  end if;

  return v_case;
end;
$$;


-- Grants are unchanged by a `create or replace` (the existing ACL on each function survives), so
-- none is re-issued here -- re-issuing one would be the only way this migration could silently
-- widen access, and it does not.
