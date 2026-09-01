-- ISS-2026-070 (docs/runtime/KNOWN_ISSUES.md): "no live job worker/overdue scheduler" and
-- "PLT-127 Notification Engine is not wired". Same fix shape as ISS-2026-066's own scheduler
-- item: the tenant-configurable scheduler (supabase/migrations/20260831090000) already exists --
-- this migration registers a real "overdue onboarding/offboarding task" sweep on it, and wires
-- that sweep to PLT-127's own real send primitive (app.queue_notification), mirroring
-- app._queue_ticket_escalation_notification (HRT-291, 20260731160000) -- the repository's own
-- FIRST real PLT-127 domain consumer, copied deliberately rather than re-invented: resolve a
-- published notification template, resolve a real recipient, call app.queue_notification inside a
-- per-row BEGIN/EXCEPTION so one bad row can never abort the whole sweep, and always record a
-- discriminated app.onboarding_case_events row (never a silent drop).
--
-- ===========================================================================
-- Live schema re-verified before writing this file
-- ===========================================================================
--
--   * app._run_scheduled_task_once currently dispatches 20 task_code branches (confirmed live via
--     pg_get_functiondef) -- this migration widens it to 21, every existing branch byte-identical.
--   * app.onboarding_case_tasks/app.onboarding_offboarding_cases are unchanged since
--     20260730880000 (confirmed live via information_schema.columns) -- due_at/status/owner_
--     auth_user_id/case status='active' are exactly the columns this sweep already reads at read
--     time (app.list_onboarding_case_tasks' own is_overdue projection, decision 5's own disclosed
--     "no live scheduler" boundary this migration closes).
--   * app.queue_notification/app.check_notification_trigger_authority are unchanged since
--     20260719130000 -- this migration calls them exactly as HRT-291 already does, never
--     reimplementing either.
--
-- ===========================================================================
-- What this migration closes, and what it deliberately does not
-- ===========================================================================
--
-- Closes: "no live job worker/overdue scheduler" (a real, schedulable sweep now exists, callable
-- on demand today and attachable to a timer the moment pg_cron/an external trigger is turned on --
-- ISS-2026-066's own entry already disclosed that turning the scheduler on is a separate,
-- deliberate infrastructure decision for the operator, unaffected by this migration) and "PLT-127
-- Notification Engine is not wired" for exactly the overdue-task case this sweep covers (a real
-- notification is queued through the real engine, not logged/no-op).
--
-- Deliberately NOT closed here, and said plainly: task ASSIGNMENT / provisioning-revocation-
-- completion / finalize-approval-routing notifications (the entry's OTHER named PLT-127 gaps) are
-- untouched -- each is a distinct wiring point in app.assign_onboarding_task/app.request_
-- onboarding_access_provisioning/etc, not a scheduled sweep, and is out of this migration's own
-- bounded scope. app.preview_onboarding_case_start/app.export_onboarding_cases still have no UI
-- caller (item 3), no dedicated case_type='transfer' db-test scenario exists (item 4), and no
-- beforeunload guard/E2E spec exists (item 5) -- all remain OPEN, disclosed in the entry's own
-- closing text below, not silently dropped.

-- ===========================================================================
-- STEP 1: notification type bootstrap, mirroring app._queue_ticket_escalation_notification's own
-- 'ticket_escalated' direct-INSERT bootstrap (20260731160000) exactly -- migration-apply context
-- has no live actor session, so app.register_notification_type/app.create_config_draft/app.
-- publish_config_version (all Supreme-Admin- or scope-authority-gated) cannot be called here.
-- channels=['in_app'] ONLY (no live email provider exists anywhere in this repository, PLT-127's
-- own disclosed boundary, unchanged by this migration).
-- ===========================================================================

insert into app.notification_types (code, name, owner_primitive_code, registered_by)
values ('onboarding_task_overdue', 'Onboarding/Offboarding Task Overdue', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('notification:onboarding_task_overdue', 'Onboarding/Offboarding Task Overdue Notification', 'HRS', 'system')
on conflict (code) do nothing;

do $$
declare
  v_object_id uuid;
  v_version_id uuid;
begin
  select id into v_object_id from app.config_objects
  where config_type_code = 'notification:onboarding_task_overdue' and tenant_id is null and scope_level = 'global' and scope_id is null;

  if v_object_id is null then
    insert into app.config_objects (config_type_code, tenant_id, scope_level, scope_id, created_by)
    values ('notification:onboarding_task_overdue', null, 'global', null, 'system')
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
      (v_version_id, 'templates', '{"en": {"subject": "Overdue task: {{task_title}}", "body": "Your onboarding/offboarding task \"{{task_title}}\" was due {{due_at}} and is still open. Open your CargoGrid onboarding workspace to complete or waive it."}}'::jsonb);
  end if;

  raise notice 'onboarding_task_overdue notification template ready: config_object=%, published_version=%', v_object_id, v_version_id;
end;
$$;

-- ===========================================================================
-- STEP 2: the sweep itself. RBAC-gated on HRS:Override (mirrors app.activate_due_employee_
-- position_assignments' own gate -- a maintenance sweep scanning a whole tenant's onboarding/
-- offboarding cases, not a single-record action). Idempotent per (task, period) via
-- app.queue_notification's own (tenant, type, recipient, channel, dedupe_key) uniqueness -- a
-- repeated run inside the same period_label re-notifies nobody twice.
-- ===========================================================================

create function app.run_onboarding_overdue_task_sweep(
  p_tenant_id uuid,
  p_now timestamptz,
  p_period_label text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns integer
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_config_version_id uuid;
  v_task record;
  v_dedupe_key text;
  v_notified integer := 0;
  v_failed integer := 0;
  v_no_owner integer := 0;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_period_label is null or length(trim(p_period_label)) = 0 then
    raise exception 'invalid_period: a non-empty p_period_label is required' using errcode = 'check_violation';
  end if;

  select v.id into v_config_version_id
  from app.config_versions v
  join app.config_objects o on o.id = v.config_object_id
  where o.config_type_code = 'notification:onboarding_task_overdue' and v.status = 'published'
  order by v.version_number desc
  limit 1;

  if v_config_version_id is null then
    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_onboarding_overdue_task_sweep',
      'app.onboarding_case_tasks', p_tenant_id, 'failure',
      'no published notification:onboarding_task_overdue template is configured', null, null
    );
    return 0;
  end if;

  for v_task in
    select t.id, t.case_id, t.title, t.owner_auth_user_id, t.due_at
    from app.onboarding_case_tasks t
    join app.onboarding_offboarding_cases c on c.id = t.case_id
    where c.tenant_id = p_tenant_id
      and c.status = 'active'
      and t.due_at is not null
      and t.due_at < p_now
      and t.status not in ('completed', 'waived')
    order by t.due_at
  loop
    -- A task with no owner_auth_user_id (owner_type is a category, e.g. 'hr', with nobody
    -- specifically assigned yet) has no real Platform identity to notify -- structurally
    -- expected, not a failure, so it is skipped and counted rather than raising.
    if v_task.owner_auth_user_id is null then
      v_no_owner := v_no_owner + 1;
      continue;
    end if;

    v_dedupe_key := 'onboarding-task-overdue:' || v_task.id::text || ':' || p_period_label;

    begin
      perform app.queue_notification(
        v_config_version_id, p_tenant_id, 'onboarding_task_overdue', v_task.owner_auth_user_id, 'in_app', 'en',
        jsonb_build_object('task_title', v_task.title, 'due_at', v_task.due_at),
        v_dedupe_key, p_actor_auth_user_id, p_actor_label
      );
      insert into app.onboarding_case_events (case_id, tenant_id, event_type, actor_auth_user_id, actor_label, notes)
      values (v_task.case_id, p_tenant_id, 'task_overdue_notified', p_actor_auth_user_id, p_actor_label, 'Overdue notification queued for task ' || v_task.id::text);
      v_notified := v_notified + 1;
    exception
      -- Deliberately, narrowly isolated (mirrors app._queue_ticket_escalation_notification,
      -- HRT-291): a notification-queuing failure on ONE task (e.g. an unsafe context value,
      -- or a recipient who lost tenant membership between the scan and the call) must never
      -- abort the rest of the sweep -- recorded, never silently dropped.
      when others then
        v_failed := v_failed + 1;
        insert into app.onboarding_case_events (case_id, tenant_id, event_type, actor_auth_user_id, actor_label, notes)
        values (v_task.case_id, p_tenant_id, 'task_overdue_notification_failed', p_actor_auth_user_id, p_actor_label, 'queue_notification raised: ' || sqlerrm);
    end;
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_onboarding_overdue_task_sweep',
    'app.onboarding_case_tasks', p_tenant_id, 'success', null, null,
    jsonb_build_object('notified_count', v_notified, 'failed_count', v_failed, 'no_owner_count', v_no_owner, 'period_label', p_period_label)
  );

  return v_notified;
end;
$$;

comment on function app.run_onboarding_overdue_task_sweep is
  'ISS-2026-070: scans every active onboarding/offboarding case in the tenant for a task whose due_at has passed and whose status is not completed/waived (the identical "overdue" predicate app.list_onboarding_case_tasks/app.list_my_onboarding_tasks already compute at read time -- decision 5''s own disclosed no-live-scheduler boundary) and queues a real PLT-127 in_app notification to each task''s own owner_auth_user_id via app.queue_notification -- the SAME primitive/pattern app._queue_ticket_escalation_notification (HRT-291) already established as this repository''s first real domain consumer. A task with no owner_auth_user_id set is skipped and counted (no identity to notify, not a failure). Idempotent per (task, period_label) via app.queue_notification''s own dedupe_key uniqueness. Gated on HRS:Override, mirroring app.activate_due_employee_position_assignments'' own maintenance-sweep gate. Returns the count of genuinely NEW notifications queued this call.';

-- ===========================================================================
-- STEP 3: grants + public.* wrapper (RGL-394 Option 2), matching every sibling sweep''s grant set
-- exactly -- callable directly by an authenticated HRS:Override holder (not only the scheduler).
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.run_onboarding_overdue_task_sweep(uuid, timestamptz, text, uuid, text) to authenticated, service_role;

create function public.run_onboarding_overdue_task_sweep(
  p_tenant_id uuid, p_now timestamptz, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text
)
returns integer
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.run_onboarding_overdue_task_sweep(p_tenant_id, p_now, p_period_label, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.run_onboarding_overdue_task_sweep(uuid, timestamptz, text, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.run_onboarding_overdue_task_sweep, never a reimplementation.';

revoke execute on function public.run_onboarding_overdue_task_sweep(uuid, timestamptz, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.run_onboarding_overdue_task_sweep(uuid, timestamptz, text, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- STEP 4: register the catalogue task and widen the dispatcher -- same registration pattern
-- 20260831230000_add_loyalty_earning_tier_and_points_posting_sweeps.sql already established.
-- tenant_admin_configurable=true: how often a tenant wants overdue-task reminders is its own HR
-- business rhythm, exactly like training-certificate-expiry reminders, not platform service-level
-- machinery.
-- ===========================================================================

insert into app.scheduled_task_definitions
  (task_code, display_name, description, tenant_admin_configurable, min_interval_minutes, default_interval_minutes, required_params)
values
  ('onboarding_offboarding_overdue_task_sweep', 'Onboarding/offboarding overdue task reminders',
   'Notifies each overdue onboarding/offboarding task''s own owner through the notification engine.', true, 60, 240, '{}')
on conflict (task_code) do nothing;

-- Same signature, so `create or replace` genuinely replaces rather than overloading
-- (ISS-2026-260). One new branch; every existing branch (live-confirmed, 20 of them) is
-- byte-identical.
create or replace function app._run_scheduled_task_once(p_schedule app.tenant_scheduled_tasks, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_actor uuid := p_schedule.authorized_by_auth_user_id;
  v_label text := 'scheduler:' || p_schedule.task_code;
  v_period text := to_char(p_now, 'YYYY-MM-DD');
begin
  case p_schedule.task_code
    when 'loyalty_expiry_sweep' then
      perform app.run_loyalty_expiry_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'loyalty_point_lot_expiry' then
      perform app.expire_loyalty_point_lots(p_schedule.tenant_id, v_actor, v_label, p_now);
    when 'loyalty_benefit_entitlement_expiry' then
      perform app.expire_loyalty_benefit_entitlements(p_schedule.tenant_id, v_actor, v_label, p_now);
    when 'loyalty_earning_evaluation_sweep' then
      perform app.run_loyalty_earning_evaluation_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'loyalty_tier_recalculation_sweep' then
      perform app.run_loyalty_tier_recalculation_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'loyalty_points_posting_sweep' then
      perform app.run_loyalty_points_posting_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'loyalty_liability_reconciliation' then
      perform app.execute_loyalty_liability_reconciliation_run(
        p_schedule.tenant_id, p_now, p_schedule.params ->> 'currency', v_actor, v_label,
        'scheduler:' || p_schedule.task_code || ':' || (p_schedule.params ->> 'currency') || ':' || v_period, 1);
    when 'employee_position_activation' then
      perform app.activate_due_employee_position_assignments(p_schedule.tenant_id, v_actor, v_label);
    -- ISS-2026-070
    when 'onboarding_offboarding_overdue_task_sweep' then
      perform app.run_onboarding_overdue_task_sweep(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    when 'leave_accrual_batch' then
      perform app.run_leave_accrual_batch(
        p_schedule.tenant_id, (p_schedule.params ->> 'leave_type_id')::uuid, p_now::date, v_period, v_actor, v_label);
    when 'leave_carry_forward_batch' then
      perform app.run_leave_carry_forward_batch(
        p_schedule.tenant_id, (p_schedule.params ->> 'leave_type_id')::uuid, p_now::date, v_period, v_actor, v_label);
    when 'training_certificate_expiry' then
      perform app.run_training_certificate_expiry_batch(p_schedule.tenant_id, p_now::date, v_period, v_actor, v_label);
    when 'training_certificate_expiry_reminder' then
      perform app.run_training_certificate_expiry_reminder_batch(
        p_schedule.tenant_id, p_now::date, (p_schedule.params ->> 'lookahead_days')::integer, v_period, v_actor, v_label);
    when 'incident_escalation_sweep' then
      perform app.run_incident_escalation_sweep(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    when 'ticket_sla_evaluation' then
      perform app.run_ticket_sla_evaluation_batch(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    when 'ticket_escalation_evaluation' then
      perform app.run_ticket_escalation_evaluation_batch(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    -- ISS-2026-249
    when 'authority_denial_anomaly_sweep' then
      perform app.run_authority_denial_anomaly_sweep(
        p_schedule.tenant_id, p_now,
        (p_schedule.params ->> 'window_minutes')::integer,
        (p_schedule.params ->> 'threshold')::integer,
        v_actor, v_label);
    -- ISS-2026-313
    when 'employee_lifecycle_activation' then
      perform app.activate_due_employee_lifecycle_transitions(p_schedule.tenant_id, v_actor, v_label);
    when 'kb_article_version_expiry' then
      perform app.expire_kb_article_versions_batch(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    when 'vendor_compliance_waiver_expiry' then
      perform app.expire_vendor_compliance_waivers(
        p_schedule.tenant_id, v_actor, v_label, (p_schedule.params ->> 'max_rows')::integer);
    when 'vendor_compliance_status_refresh' then
      perform app.recalculate_tenant_vendor_compliance_status(
        p_schedule.tenant_id, v_actor, v_label, (p_schedule.params ->> 'max_vendors')::integer);
    else
      raise exception 'scheduled_task_not_dispatchable: % has a catalogue row but no dispatch branch', p_schedule.task_code
        using errcode = 'check_violation';
  end case;
end;
$$;

comment on function app._run_scheduled_task_once is
  'Internal (app._ prefix, service_role-only): the explicit per-task dispatch, now twenty-one enumerated calls after ISS-2026-070 added the onboarding/offboarding overdue-task sweep. Deliberately a CASE rather than dynamic SQL assembled from the row -- task_code is catalogue-controlled today, but a scheduler that EXECUTEs a statement built from a table column is one bad migration away from an injection surface. Every call passes the schedule''s own authorized_by_auth_user_id as the actor, which is what makes a scheduled run attributable to a person. A catalogue row with no dispatch branch raises rather than silently doing nothing.';

revoke execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) from public, anon, authenticated;
grant execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) to service_role;
