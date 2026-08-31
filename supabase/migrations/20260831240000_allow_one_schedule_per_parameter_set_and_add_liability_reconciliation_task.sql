-- Closes `ISS-2026-134` item 4's schedulable half, and fixes a real defect in the scheduler
-- that adding that task is what surfaced.
--
-- THE DEFECT, WHICH IS MINE AND ALREADY SHIPPED
--
--   `20260831090000` gave `app.tenant_scheduled_tasks` the constraint
--   `unique (tenant_id, task_code)` -- one schedule per catalogue task per tenant. For the twelve
--   parameterless tasks that is exactly right. For every task that takes a parameter it is a
--   silent cap of one, and it was already wrong for tasks shipped days ago:
--
--     * `leave_accrual_batch` and `leave_carry_forward_batch` each take a `leave_type_id`. A
--       tenant with annual leave, sick leave and long-service leave could automate exactly ONE
--       of them, and configuring the second would silently overwrite the first rather than
--       failing -- the worst shape of all, because nothing tells anybody.
--     * `training_certificate_expiry_reminder` takes a `lookahead_days`, so a 30-day and a
--       7-day reminder cannot coexist.
--     * `vendor_compliance_waiver_expiry` and `vendor_compliance_status_refresh` take row caps.
--
--   Adding a currency-scoped liability reconciliation is what made this impossible to miss:
--   `ISS-2026-134` item 1's own documented workflow is one run PER CURRENCY, so a multi-currency
--   tenant needs several schedules of the same task by construction. The constraint would have
--   made the new task useless on exactly the tenants that need it, and would have kept quietly
--   eating leave-accrual schedules regardless.
--
-- THE FIX, AND WHY IT IS THIS ONE
--
--   `unique (tenant_id, task_code, params)`. A schedule is identified by what it actually does,
--   not merely by which task it is.
--
--   For the twelve parameterless tasks nothing changes at all: `params` is always `{}`, so the
--   key is still effectively `(tenant_id, task_code)` and reconfiguring still updates in place.
--   For a parameterised task, a different parameter set is now a different standing instruction,
--   which is what it always was in substance.
--
--   `configure_tenant_scheduled_task` keeps its exact signature and every one of its behaviours
--   -- authority, interval floor, required-parameter validation, identity re-stamping, failure
--   counter reset. Only the conflict target moves, in lockstep with the constraint, because an
--   `ON CONFLICT` target that no longer matches a unique index does not degrade gracefully: it
--   raises at runtime. The two have to move together or not at all.
--
--   What a reader should expect afterwards: passing the SAME params updates that schedule;
--   passing DIFFERENT params creates a second one. Disabling is still `p_enabled => false` on
--   the params you want stopped -- deliberately not a delete, so a stopped schedule stays
--   visible with its own reason rather than vanishing.

alter table app.tenant_scheduled_tasks drop constraint tenant_scheduled_tasks_unique;
alter table app.tenant_scheduled_tasks add constraint tenant_scheduled_tasks_unique unique (tenant_id, task_code, params);

comment on table app.tenant_scheduled_tasks is
  'One row per (tenant, task_code, params): this tenant''s own schedule for one catalogue task with one parameter set. The params half of that key was added by ISS-2026-134 -- the original (tenant, task_code) key silently capped every parameterised task at one schedule per tenant, so a tenant with three leave types could accrue only one and configuring the second overwrote the first with no warning. authorized_by_auth_user_id is the identity every run of this schedule ACTS AS -- deliberately a real person (the Supreme Admin or tenant admin who enabled it), never a synthetic system account, so every audit row a sweep writes names somebody accountable. Its authority is re-checked on every run, not cached: if it is revoked or narrowed the run fails and is recorded as unauthorized rather than escalating or silently skipping. Three consecutive authority failures auto-disable the row with disabled_reason set, so a departed employee''s stale schedule becomes a visible dead row instead of permanent noise.';

-- Same signature, so `create or replace` genuinely replaces rather than overloading
-- (ISS-2026-260). Rebuilt from the CURRENTLY-APPLIED definition read back with
-- pg_get_functiondef, not from the migration that created it -- the trap
-- `20260831230000`'s own dispatcher near-miss just demonstrated. Exactly one line differs:
-- the ON CONFLICT target.
create or replace function app.configure_tenant_scheduled_task(
  p_tenant_id uuid, p_task_code text, p_enabled boolean, p_interval_minutes integer,
  p_params jsonb, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.tenant_scheduled_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_definition app.scheduled_task_definitions;
  v_schedule app.tenant_scheduled_tasks;
  v_params jsonb := coalesce(p_params, '{}'::jsonb);
  v_interval integer;
  v_missing text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_definition from app.scheduled_task_definitions where task_code = p_task_code;
  if not found or v_definition.status <> 'active' then
    raise exception 'scheduled_task_not_available: % is not an active catalogue task', p_task_code using errcode = 'no_data_found';
  end if;

  if not app._can_configure_tenant_scheduled_task(p_tenant_id, p_task_code, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not configure scheduled task % for tenant %', p_actor_auth_user_id, p_task_code, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_interval := coalesce(p_interval_minutes, v_definition.default_interval_minutes);
  if v_interval < v_definition.min_interval_minutes then
    raise exception 'scheduled_task_interval_too_short: % requires at least % minutes between runs, got %', p_task_code, v_definition.min_interval_minutes, v_interval
      using errcode = 'check_violation';
  end if;

  -- Validated here, at configuration time, rather than discovered at 03:00 on the first run.
  foreach v_missing in array v_definition.required_params loop
    if not (v_params ? v_missing) then
      raise exception 'scheduled_task_missing_param: % requires the % parameter', p_task_code, v_missing using errcode = 'check_violation';
    end if;
  end loop;

  insert into app.tenant_scheduled_tasks as t
    (tenant_id, task_code, enabled, interval_minutes, params, authorized_by_auth_user_id, authorized_at,
     next_run_at, consecutive_authority_failures, disabled_reason, created_by)
  values
    (p_tenant_id, p_task_code, p_enabled, v_interval, v_params, p_actor_auth_user_id, now(),
     now(), 0, case when p_enabled then null else 'disabled at configuration' end, p_actor_label)
  -- ISS-2026-134: params joins the conflict target, in lockstep with the unique constraint
  -- above. Same params updates the same schedule; different params is a different standing
  -- instruction, which for a leave type or a currency is what it always was in substance.
  on conflict (tenant_id, task_code, params) do update
  set enabled = excluded.enabled,
      interval_minutes = excluded.interval_minutes,
      params = excluded.params,
      -- Re-stamped on purpose: whoever reconfigures a schedule becomes the identity it runs as.
      -- That is what makes re-authorizing after somebody leaves a real act by a real person.
      authorized_by_auth_user_id = excluded.authorized_by_auth_user_id,
      authorized_at = now(),
      consecutive_authority_failures = 0,
      disabled_reason = case when excluded.enabled then null else 'disabled at configuration' end,
      next_run_at = case when excluded.enabled then now() else t.next_run_at end
      -- record_version is NOT bumped here: the tenant_scheduled_tasks_touch_row trigger
      -- already does it, and doing both would advance it by two per call.
  returning * into v_schedule;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'configure_tenant_scheduled_task',
    'app.tenant_scheduled_tasks', v_schedule.id, 'success', null, null,
    jsonb_build_object('task_code', p_task_code, 'enabled', v_schedule.enabled, 'interval_minutes', v_schedule.interval_minutes, 'params', v_schedule.params)
  );

  return v_schedule;
end;
$$;

comment on function app.configure_tenant_scheduled_task is
  'Creates or updates one tenant schedule, identified by (tenant, task_code, params) since ISS-2026-134. Passing the same parameter set updates that schedule; passing a different one creates a second, which is what a tenant with three leave types or two trading currencies actually needs -- before this, the second silently overwrote the first. Every other behaviour is unchanged: delegation authority, the interval floor, required-parameter validation at configuration time rather than at 03:00 on the first run, identity re-stamping on every call, and the failure counter reset. Stopping a schedule is p_enabled => false on its own parameter set, deliberately not a delete, so a stopped schedule stays visible with its reason.';

-- ===========================================================================
-- The task itself. ISS-2026-134 item 4.
--
-- `currency` is required rather than defaulted, and that is the point: this migration's
-- whole reason for existing is that reconciliation is per-currency by the entry's own
-- documented workflow. A default would have hidden the multi-schedule need behind a
-- single silent USD run.
--
-- Supreme-Admin-only (`tenant_admin_configurable = false`), unlike its loyalty siblings.
-- The other loyalty tasks tune a tenant's own commercial rhythm; this one produces the
-- financial-liability evidence artefact a certification decision rests on, which is
-- platform governance rather than tenant policy. A Supreme Admin can delegate it later
-- without a migration -- that switch is exactly what it is for.
--
-- min_interval_minutes = 1440: a reconciliation run is a point-in-time liability
-- statement. Running it hourly would produce a pile of near-identical runs to certify,
-- which makes the artefact harder to trust rather than fresher.
-- ===========================================================================

insert into app.scheduled_task_definitions
  (task_code, display_name, description, tenant_admin_configurable, min_interval_minutes, default_interval_minutes, required_params)
values
  ('loyalty_liability_reconciliation', 'Loyalty liability reconciliation',
   'Executes a liability reconciliation run for one currency. Schedule one per currency the tenant trades in.',
   false, 1440, 1440, '{currency}')
on conflict (task_code) do nothing;

-- Rebuilt from the currently-applied definition (nineteen branches after 20260831230000),
-- not from any earlier migration. One branch added.
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
    -- ISS-2026-134 item 4. The idempotency key carries the currency as well as the period:
    -- two currencies on the same day are two genuinely different runs, and a key that named
    -- only the day would collapse them into one and lose a currency's liability statement.
    when 'loyalty_liability_reconciliation' then
      perform app.execute_loyalty_liability_reconciliation_run(
        p_schedule.tenant_id, p_now, p_schedule.params ->> 'currency', v_actor, v_label,
        'scheduler:' || p_schedule.task_code || ':' || (p_schedule.params ->> 'currency') || ':' || v_period, 1);
    when 'employee_position_activation' then
      perform app.activate_due_employee_position_assignments(p_schedule.tenant_id, v_actor, v_label);
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
  'Internal (app._ prefix, service_role-only): the explicit per-task dispatch, now twenty enumerated calls. Deliberately a CASE rather than dynamic SQL assembled from the row -- task_code is catalogue-controlled today, but a scheduler that EXECUTEs a statement built from a table column is one bad migration away from an injection surface. Every call passes the schedule''s own authorized_by_auth_user_id as the actor, which is what makes a scheduled run attributable to a person. A catalogue row with no dispatch branch raises rather than silently doing nothing.';

revoke execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) from public, anon, authenticated;
grant execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) to service_role;
