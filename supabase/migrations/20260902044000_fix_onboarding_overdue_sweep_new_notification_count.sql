-- Self-found regression, caught live by `pnpm run db:test` immediately after
-- 20260902043000_wire_onboarding_offboarding_overdue_task_sweep.sql applied. This function's
-- own comment claims it "Returns the count of genuinely NEW notifications queued this call" --
-- but the body never checked for newness before calling app.queue_notification, and that
-- primitive's own idempotency (PLT-127, "same tenant/type/recipient/channel/dedupe_key returns
-- the existing row rather than raising") means a REPEATED call for an already-notified task
-- returns successfully without erroring, so the loop counted it as notified again regardless.
-- The bug was invisible in isolation but real: `v_notified` was actually "count of tasks that did
-- not error", not "count of genuinely new notifications" -- live-caught only because this
-- checkpoint's own new db-tests regression asserted the SECOND (same-period, idempotent-replay)
-- call returns 0 new notifications, and it did not.
--
-- Fix: check whether a notification with this exact dedupe_key already exists BEFORE calling
-- app.queue_notification, and skip (silently, not a failure -- already handled) when it does.
-- Every other line is byte-identical to the live definition.

create or replace function app.run_onboarding_overdue_task_sweep(
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
  v_already_sent integer := 0;
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

    -- Fixed here (20260902044000): app.queue_notification is itself idempotent on
    -- (tenant, type, recipient, channel, dedupe_key) -- it returns the EXISTING row rather
    -- than raising on a repeat call, so counting every non-erroring call as "notified" would
    -- over-count a replay. Checked explicitly so v_notified genuinely means "new this call".
    if exists (
      select 1 from app.notifications
      where tenant_id = p_tenant_id and notification_type_code = 'onboarding_task_overdue'
        and recipient_auth_user_id = v_task.owner_auth_user_id and requested_channel = 'in_app'
        and dedupe_key = v_dedupe_key
    ) then
      v_already_sent := v_already_sent + 1;
      continue;
    end if;

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
    jsonb_build_object('notified_count', v_notified, 'already_sent_count', v_already_sent, 'failed_count', v_failed, 'no_owner_count', v_no_owner, 'period_label', p_period_label)
  );

  return v_notified;
end;
$$;

comment on function app.run_onboarding_overdue_task_sweep is
  'ISS-2026-070: scans every active onboarding/offboarding case in the tenant for a task whose due_at has passed and whose status is not completed/waived (the identical "overdue" predicate app.list_onboarding_case_tasks/app.list_my_onboarding_tasks already compute at read time -- decision 5''s own disclosed no-live-scheduler boundary) and queues a real PLT-127 in_app notification to each task''s own owner_auth_user_id via app.queue_notification -- the SAME primitive/pattern app._queue_ticket_escalation_notification (HRT-291) already established as this repository''s first real domain consumer. A task with no owner_auth_user_id set is skipped and counted (no identity to notify, not a failure). Idempotent per (task, period_label): a dedupe_key that already has a notification row is skipped BEFORE calling app.queue_notification (fixed at 20260902044000 -- that primitive''s own idempotent "return the existing row" behavior otherwise made every replay count as newly notified). Gated on HRS:Override, mirroring app.activate_due_employee_position_assignments'' own maintenance-sweep gate. Returns the count of genuinely NEW notifications queued this call.';
