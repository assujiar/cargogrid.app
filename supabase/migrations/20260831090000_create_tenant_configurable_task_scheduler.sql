-- The automatic task scheduler. Closes the single largest cluster left in the backlog:
-- `ISS-2026-066`, `070`, `126`, `127`, `129`, `132` and the other entries whose common
-- sentence is some form of "on-demand/staff-triggered only; no automatic job wires this up".
-- Eleven findings, one missing capability.
--
-- THE PROBLEM THAT MADE THIS HARDER THAN "TURN ON pg_cron"
--
--   `pg_cron` 1.6.4 is available on the hosted project and not installed, but installing it was
--   never the blocker. Every sweep in this repository takes `p_actor_auth_user_id`, and most are
--   `app.evaluate_permission`-gated:
--
--     activate_due_employee_position_assignments      RBAC-gated
--     expire_loyalty_benefit_entitlements             RBAC-gated
--     expire_loyalty_point_lots                       RBAC-gated
--     run_incident_escalation_sweep                   RBAC-gated
--     run_leave_accrual_batch                         RBAC-gated
--     run_leave_carry_forward_batch                   RBAC-gated
--     run_loyalty_expiry_sweep                        RBAC-gated
--     run_ticket_escalation_evaluation_batch          actor recorded
--     run_ticket_sla_evaluation_batch                 actor recorded
--     run_training_certificate_expiry_batch           actor recorded
--     run_training_certificate_expiry_reminder_batch  actor recorded
--
--   A cron job has no identity. So "who is the scheduler acting as?" had to be answered before
--   any of this could run, and the obvious answer -- mint a second top-privilege platform
--   identity for the robot -- was put to the project owner and REJECTED, correctly.
--
-- THE OWNER'S ANSWER, WHICH IS THE DESIGN THIS MIGRATION IMPLEMENTS
--
--   "itu kan harusnya bisa diatur sama supreme admin dan bisa diberikan aksesnya sama supreme
--    admin ke admin tenant sehingga bisa disesuaikan sama tenant yg gunain cargogrid"
--
--   Supreme Admin owns the catalogue of what may be scheduled and decides, per task type,
--   whether a tenant's own admin may configure it. Each tenant then tunes its own schedule.
--
--   That also disposes of the identity question without inventing an identity. **A scheduled run
--   executes as the identity that authorized the schedule** -- the Supreme Admin or tenant admin
--   who enabled it, recorded on the row, re-checked on every single run. Nothing new is minted,
--   nothing runs as "the system", and every audit row a sweep writes names a real accountable
--   person, exactly as if they had clicked "run now" themselves.
--
--   The consequences of that choice are deliberate, not overlooked:
--
--     * If the authorizer's access is revoked or their permissions narrowed, the run FAILS. It
--       does not fall back to a higher authority and does not silently skip -- it is recorded as
--       a failure with the real reason. That is correct: a schedule is a standing instruction
--       from a person, and it should stop when that person's authority stops.
--     * A schedule that fails on authority 3 times in a row is auto-disabled with the reason
--       recorded, so a departed employee's stale schedule becomes a visible dead row rather than
--       a permanent noisy failure.
--     * Re-authorizing is a real act: someone with current authority reconfigures the row, which
--       re-stamps `authorized_by_auth_user_id` with THEIR identity.
--
-- WHAT THIS MIGRATION DOES NOT DO, SAID PLAINLY
--
--   It does not install `pg_cron` or schedule anything on the live project. It builds the
--   mechanism, the catalogue, the authority model and the dispatcher, and exposes one
--   service_role entry point (`app.run_due_scheduled_tasks`) that a cron job OR the existing
--   worker pattern in `scripts/jobs/` can call. Choosing the trigger -- pg_cron inside Postgres,
--   or an external scheduler hitting the worker -- is an infrastructure decision for the owner,
--   and turning it on is one line either way. Until it is turned on, nothing runs
--   automatically and the existing manual paths are unchanged.

-- ===========================================================================
-- 1. The catalogue -- Supreme Admin's, and the delegation switch lives here
-- ===========================================================================

create table app.scheduled_task_definitions (
  task_code text primary key,
  display_name text not null,
  description text not null,
  -- The delegation switch the owner asked for. false = only Supreme Admin may schedule this
  -- task for a tenant; true = that tenant's own active tenant_admin may configure it too.
  tenant_admin_configurable boolean not null default false,
  -- Guard rails a tenant cannot tune below: a sweep that scans a whole tenant should not be
  -- schedulable every minute by an enthusiastic admin.
  min_interval_minutes integer not null,
  default_interval_minutes integer not null,
  -- Task codes whose sweep needs a caller-supplied parameter (leave type, lookahead window).
  -- Named here so app.configure_tenant_scheduled_task can validate them at configuration time
  -- rather than failing at 03:00 on the first run.
  required_params text[] not null default '{}',
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scheduled_task_definitions_status_check check (status in ('active', 'retired')),
  constraint scheduled_task_definitions_interval_check check (min_interval_minutes > 0 and default_interval_minutes >= min_interval_minutes)
);

comment on table app.scheduled_task_definitions is
  'The catalogue of tasks that MAY be scheduled, owned by Supreme Admin. tenant_admin_configurable is the delegation switch: false means only Supreme Admin may schedule this task for a tenant, true means the tenant''s own active tenant_admin may configure it themselves. min_interval_minutes is a floor a tenant cannot tune below -- a tenant-wide sweep should not be schedulable every minute. A tenant can never schedule a task that is not in this table, so the platform, not the tenant, decides what automation exists at all.';

comment on column app.scheduled_task_definitions.tenant_admin_configurable is
  'The owner''s own design instruction, made concrete: "bisa diatur sama supreme admin dan bisa diberikan aksesnya sama supreme admin ke admin tenant". Supreme Admin flips this per task type; a tenant admin may configure only the task types it is true for.';

create table app.tenant_scheduled_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  task_code text not null references app.scheduled_task_definitions (task_code),
  enabled boolean not null default true,
  interval_minutes integer not null,
  params jsonb not null default '{}'::jsonb,
  -- The identity every run of this schedule acts as. Not a system account: a real, accountable
  -- person who took a real action to authorize this standing instruction.
  authorized_by_auth_user_id uuid not null references auth.users (id),
  authorized_at timestamptz not null default now(),
  next_run_at timestamptz not null default now(),
  last_run_at timestamptz,
  last_run_status text,
  last_run_detail text,
  consecutive_authority_failures integer not null default 0,
  disabled_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenant_scheduled_tasks_unique unique (tenant_id, task_code),
  constraint tenant_scheduled_tasks_interval_check check (interval_minutes > 0),
  constraint tenant_scheduled_tasks_last_status_check check (last_run_status is null or last_run_status in ('succeeded', 'failed', 'unauthorized')),
  constraint tenant_scheduled_tasks_disabled_reason_check check (enabled or disabled_reason is not null)
);

comment on table app.tenant_scheduled_tasks is
  'One row per (tenant, task_code): this tenant''s own schedule for one catalogue task. authorized_by_auth_user_id is the identity every run of this schedule ACTS AS -- deliberately a real person (the Supreme Admin or tenant admin who enabled it), never a synthetic system account, so every audit row a sweep writes names somebody accountable. Its authority is re-checked on every run, not cached: if it is revoked or narrowed the run fails and is recorded as unauthorized rather than escalating or silently skipping. Three consecutive authority failures auto-disable the row with disabled_reason set, so a departed employee''s stale schedule becomes a visible dead row instead of permanent noise.';

comment on column app.tenant_scheduled_tasks.authorized_by_auth_user_id is
  'Re-stamped on every configure call with the identity of whoever configured it. Re-authorizing a schedule after its owner leaves is therefore a real act by a real person with current authority, not a flag someone clears.';

create index tenant_scheduled_tasks_due_idx on app.tenant_scheduled_tasks (next_run_at) where enabled;
create index tenant_scheduled_tasks_tenant_idx on app.tenant_scheduled_tasks (tenant_id);

create table app.scheduled_task_runs (
  id uuid primary key default gen_random_uuid(),
  scheduled_task_id uuid not null references app.tenant_scheduled_tasks (id),
  tenant_id uuid not null references app.tenants (id),
  task_code text not null,
  ran_as_auth_user_id uuid not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null,
  detail text,
  constraint scheduled_task_runs_status_check check (status in ('succeeded', 'failed', 'unauthorized'))
);

comment on table app.scheduled_task_runs is
  'Append-only run history. ran_as_auth_user_id records the identity the run actually executed as, which is the whole point of the design: a scheduled sweep is attributable to a person, not to "the system".';

create index scheduled_task_runs_task_idx on app.scheduled_task_runs (scheduled_task_id, started_at desc);

-- No touch trigger on app.scheduled_task_definitions: app.touch_org_unit_row bumps
-- record_version, and the catalogue deliberately has no such column -- it is a small
-- Supreme-Admin-managed menu, not an optimistically-concurrent record. updated_at is set
-- explicitly by the one RPC that writes it.
create trigger tenant_scheduled_tasks_touch_row
  before update on app.tenant_scheduled_tasks
  for each row execute function app.touch_org_unit_row();

-- ===========================================================================
-- 2. The catalogue's initial contents -- the eleven sweeps the backlog names
-- ===========================================================================
--
-- tenant_admin_configurable is set per task on one question: is this the tenant's own business
-- rhythm, or the platform's? Loyalty expiry, leave accrual, certificate reminders and position
-- activation are the tenant's own HR/commercial policy, so their own admin tunes them. Incident
-- and ticket-SLA escalation sweeps are platform service-level machinery, so they start
-- Supreme-Admin-only; a Supreme Admin can flip any of these later without a migration, which is
-- exactly what the switch is for.

insert into app.scheduled_task_definitions
  (task_code, display_name, description, tenant_admin_configurable, min_interval_minutes, default_interval_minutes, required_params)
values
  ('loyalty_expiry_sweep', 'Loyalty expiry sweep',
   'Expires due loyalty point lots and benefit entitlements for the tenant.', true, 60, 1440, '{}'),
  ('loyalty_point_lot_expiry', 'Loyalty point lot expiry',
   'Expires only the point lots whose expiry date has passed.', true, 60, 1440, '{}'),
  ('loyalty_benefit_entitlement_expiry', 'Loyalty benefit entitlement expiry',
   'Expires only the benefit entitlements whose validity has ended.', true, 60, 1440, '{}'),
  ('employee_position_activation', 'Future-dated position activation',
   'Activates employee position assignments whose effective date has arrived.', true, 60, 1440, '{}'),
  ('leave_accrual_batch', 'Leave accrual',
   'Accrues leave balances for one leave type across the tenant.', true, 1440, 1440, '{leave_type_id}'),
  ('leave_carry_forward_batch', 'Leave carry-forward',
   'Carries eligible unused leave forward for one leave type.', true, 1440, 10080, '{leave_type_id}'),
  ('training_certificate_expiry', 'Training certificate expiry',
   'Marks training certificates that have passed their expiry date.', true, 1440, 1440, '{}'),
  ('training_certificate_expiry_reminder', 'Training certificate expiry reminder',
   'Raises reminders for certificates expiring within a lookahead window.', true, 1440, 1440, '{lookahead_days}'),
  ('incident_escalation_sweep', 'Incident escalation sweep',
   'Escalates monitoring incidents whose escalation window has elapsed.', false, 5, 15, '{}'),
  ('ticket_sla_evaluation', 'Ticket SLA evaluation',
   'Evaluates ticket SLA targets and records breaches.', false, 5, 15, '{}'),
  ('ticket_escalation_evaluation', 'Ticket escalation evaluation',
   'Applies ticket escalation rules whose conditions are met.', false, 5, 15, '{}');

-- ===========================================================================
-- 3. Authority
-- ===========================================================================

create function app._can_configure_tenant_scheduled_task(p_tenant_id uuid, p_task_code text, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.is_supreme_admin(p_actor_auth_user_id)
      or (
        coalesce((select d.tenant_admin_configurable from app.scheduled_task_definitions d where d.task_code = p_task_code), false)
        and app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id)
      );
$$;

comment on function app._can_configure_tenant_scheduled_task is
  'The delegation rule, in one place. Supreme Admin may configure any catalogue task for any tenant. A tenant''s own active tenant_admin may configure a task only where Supreme Admin has marked it tenant_admin_configurable. app.is_support_grant_authority is reused rather than reimplemented -- it is already exactly "Supreme Admin, or this tenant''s own active tenant_admin", and a second copy of that rule would drift from it. coalesce(..., false) fails closed for an unknown task_code.';

-- app._ prefixed and service_role-only, deliberately. It is an internal predicate, not a public
-- surface: every caller that needs it (app.configure_tenant_scheduled_task,
-- app.list_tenant_scheduled_tasks) is SECURITY DEFINER and reaches it as the function owner. The
-- underscore also exempts it from the public.* wrapper-parity gate, which is correct -- a helper
-- with no independent meaning should not become a REST endpoint.
revoke execute on function app._can_configure_tenant_scheduled_task(uuid, text, uuid) from public;
grant execute on function app._can_configure_tenant_scheduled_task(uuid, text, uuid) to service_role;

-- ===========================================================================
-- 4. Supreme Admin: flip the delegation switch, retire a task
-- ===========================================================================

create function app.set_scheduled_task_delegation(
  p_task_code text, p_tenant_admin_configurable boolean, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.scheduled_task_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_definition app.scheduled_task_definitions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only a Supreme Admin may change which scheduled tasks a tenant admin can configure'
      using errcode = 'insufficient_privilege';
  end if;

  update app.scheduled_task_definitions
  set tenant_admin_configurable = p_tenant_admin_configurable,
      updated_at = now()
  where task_code = p_task_code
  returning * into v_definition;
  if not found then
    raise exception 'scheduled_task_not_found: % is not a catalogue task', p_task_code using errcode = 'no_data_found';
  end if;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'set_scheduled_task_delegation',
    'app.scheduled_task_definitions', null, 'success', null, null,
    jsonb_build_object('task_code', p_task_code, 'tenant_admin_configurable', p_tenant_admin_configurable)
  );

  return v_definition;
end;
$$;

comment on function app.set_scheduled_task_delegation is
  'Supreme-Admin-only. Flips whether a tenant''s own admin may configure this task type, so the platform can widen or narrow delegation per task without a migration.';

revoke execute on function app.set_scheduled_task_delegation(text, boolean, uuid, text) from public;
grant execute on function app.set_scheduled_task_delegation(text, boolean, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 5. Configure a tenant's schedule
-- ===========================================================================

create function app.configure_tenant_scheduled_task(
  p_tenant_id uuid,
  p_task_code text,
  p_enabled boolean,
  p_interval_minutes integer,
  p_params jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
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
  on conflict (tenant_id, task_code) do update
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
  'Creates or updates one tenant''s schedule for one catalogue task. Authority is app._can_configure_tenant_scheduled_task: Supreme Admin always, the tenant''s own active tenant_admin only where Supreme Admin marked the task tenant_admin_configurable. The interval floor and the task''s required parameters are validated HERE, at configuration time, so a misconfiguration surfaces to the person making it rather than as a 03:00 failure. authorized_by_auth_user_id is re-stamped with the configuring identity on every call -- the schedule runs as whoever last authorized it, and the failure counter resets, so reconfiguring is how a schedule gets re-authorized after its previous owner leaves.';

revoke execute on function app.configure_tenant_scheduled_task(uuid, text, boolean, integer, jsonb, uuid, text) from public;
grant execute on function app.configure_tenant_scheduled_task(uuid, text, boolean, integer, jsonb, uuid, text) to authenticated, service_role;

create function app.list_tenant_scheduled_tasks(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, task_code text, display_name text, description text, tenant_admin_configurable boolean,
  configurable_by_actor boolean, enabled boolean, interval_minutes integer, min_interval_minutes integer,
  default_interval_minutes integer, required_params text[], params jsonb,
  authorized_by_auth_user_id uuid, authorized_at timestamptz, next_run_at timestamptz,
  last_run_at timestamptz, last_run_status text, last_run_detail text,
  consecutive_authority_failures integer, disabled_reason text, record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % may not read scheduled tasks for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Every ACTIVE catalogue task, whether this tenant has configured it or not, so the
  -- configuration screen shows what is available rather than only what is already on.
  return query
  select s.id, d.task_code, d.display_name, d.description, d.tenant_admin_configurable,
         app._can_configure_tenant_scheduled_task(p_tenant_id, d.task_code, p_actor_auth_user_id),
         coalesce(s.enabled, false), s.interval_minutes, d.min_interval_minutes,
         d.default_interval_minutes, d.required_params, coalesce(s.params, '{}'::jsonb),
         s.authorized_by_auth_user_id, s.authorized_at, s.next_run_at,
         s.last_run_at, s.last_run_status, s.last_run_detail,
         coalesce(s.consecutive_authority_failures, 0), s.disabled_reason, s.record_version
  from app.scheduled_task_definitions d
  left join app.tenant_scheduled_tasks s on s.task_code = d.task_code and s.tenant_id = p_tenant_id
  where d.status = 'active'
  order by d.display_name;
end;
$$;

comment on function app.list_tenant_scheduled_tasks is
  'The configuration screen''s read. Returns every ACTIVE catalogue task, configured or not, so an admin sees what automation is available rather than only what is already switched on, and carries configurable_by_actor per row so the UI can disable the controls this particular admin may not use instead of letting them fail on save.';

revoke execute on function app.list_tenant_scheduled_tasks(uuid, uuid) from public;
grant execute on function app.list_tenant_scheduled_tasks(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 6. The dispatcher
-- ===========================================================================
--
-- An explicit CASE per task_code, never dynamic SQL built from the row. task_code is
-- foreign-keyed to the catalogue and the catalogue is Supreme-Admin-managed, so it is not
-- attacker-controlled today -- but a scheduler that builds and EXECUTEs a statement from a
-- table column is one bad migration away from being an injection surface, and enumerating
-- eleven calls costs nothing by comparison.

create function app._run_scheduled_task_once(p_schedule app.tenant_scheduled_tasks, p_now timestamptz)
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
    else
      raise exception 'scheduled_task_not_dispatchable: % has a catalogue row but no dispatch branch', p_schedule.task_code
        using errcode = 'check_violation';
  end case;
end;
$$;

comment on function app._run_scheduled_task_once is
  'Internal (app._ prefix, service_role-only): the explicit per-task dispatch. Deliberately a CASE over eleven enumerated calls rather than dynamic SQL assembled from the row -- task_code is catalogue-controlled today, but a scheduler that EXECUTEs a statement built from a table column is one bad migration away from an injection surface. Every call passes the schedule''s own authorized_by_auth_user_id as the actor, which is what makes a scheduled run attributable to a person. A catalogue row with no dispatch branch raises rather than silently doing nothing.';

revoke execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) from public;
grant execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) to service_role;

create function app.run_due_scheduled_tasks(p_now timestamptz default now(), p_limit integer default 50)
returns table (scheduled_task_id uuid, tenant_id uuid, task_code text, status text, detail text)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_schedule app.tenant_scheduled_tasks;
  v_status text;
  v_detail text;
  v_run_id uuid;
begin
  for v_schedule in
    select * from app.tenant_scheduled_tasks t
    where t.enabled and t.next_run_at <= p_now
    order by t.next_run_at
    limit greatest(coalesce(p_limit, 50), 1)
    -- Skip-locked so two schedulers racing never run the same sweep twice; a row another
    -- worker holds is simply left for the next pass rather than waited on.
    for update skip locked
  loop
    v_status := 'succeeded';
    v_detail := null;
    insert into app.scheduled_task_runs (scheduled_task_id, tenant_id, task_code, ran_as_auth_user_id, status)
    values (v_schedule.id, v_schedule.tenant_id, v_schedule.task_code, v_schedule.authorized_by_auth_user_id, 'failed')
    returning id into v_run_id;

    begin
      perform app._run_scheduled_task_once(v_schedule, p_now);
    exception
      -- The authority case is separated from every other failure on purpose. A sweep that
      -- errors because of its own data is a bug to investigate; a sweep that errors because
      -- the person who authorized it no longer has the right to run it is a governance event,
      -- and it is the one that auto-disables the schedule.
      when insufficient_privilege then
        v_status := 'unauthorized';
        v_detail := sqlerrm;
      when others then
        v_status := 'failed';
        v_detail := sqlerrm;
    end;

    update app.scheduled_task_runs
    set finished_at = now(), status = v_status, detail = v_detail
    where id = v_run_id;

    update app.tenant_scheduled_tasks t
    set last_run_at = p_now,
        last_run_status = v_status,
        last_run_detail = v_detail,
        next_run_at = p_now + make_interval(mins => t.interval_minutes),
        consecutive_authority_failures = case when v_status = 'unauthorized' then t.consecutive_authority_failures + 1 else 0 end,
        enabled = case when v_status = 'unauthorized' and t.consecutive_authority_failures + 1 >= 3 then false else t.enabled end,
        disabled_reason = case
          when v_status = 'unauthorized' and t.consecutive_authority_failures + 1 >= 3
          then 'auto-disabled: the authorizing identity has lacked the required authority for 3 consecutive runs -- reconfigure this schedule to re-authorize it'
          else t.disabled_reason
        end
    where t.id = v_schedule.id;

    scheduled_task_id := v_schedule.id;
    tenant_id := v_schedule.tenant_id;
    task_code := v_schedule.task_code;
    status := v_status;
    detail := v_detail;
    return next;
  end loop;
end;
$$;

comment on function app.run_due_scheduled_tasks is
  'The scheduler entry point, service_role-only: runs every enabled schedule whose next_run_at has passed, each as its own authorizing identity. Rows are claimed FOR UPDATE SKIP LOCKED so two workers racing never double-run a sweep. One failing task never stops the pass -- each run is wrapped and recorded individually. An insufficient_privilege failure is treated as a distinct outcome from any other error, because it means the authorizing person''s rights changed rather than that the sweep is broken; three consecutive ones auto-disable the schedule with the reason recorded, which turns a departed employee''s stale schedule into a visible dead row instead of permanent nightly noise. Nothing calls this automatically yet: installing pg_cron, or pointing the existing scripts/jobs worker pattern at it, is a deliberate infrastructure step for the operator.';

revoke execute on function app.run_due_scheduled_tasks(timestamptz, integer) from public;
grant execute on function app.run_due_scheduled_tasks(timestamptz, integer) to service_role;

-- ===========================================================================
-- 7. Grants and RLS
-- ===========================================================================

grant select on app.scheduled_task_definitions to authenticated, service_role;
grant insert, update on app.scheduled_task_definitions to service_role;
grant select, insert, update on app.tenant_scheduled_tasks to service_role;
grant select, insert, update on app.scheduled_task_runs to service_role;

-- No `authenticated` grant on app.tenant_scheduled_tasks or app.scheduled_task_runs: both carry
-- authorized_by/ran_as identity columns and failure text, and the only intended read path is
-- app.list_tenant_scheduled_tasks, which is authority-gated. RLS is enabled anyway as defence in
-- depth, so a future grant added by mistake still cannot cross a tenant boundary.
alter table app.tenant_scheduled_tasks enable row level security;
alter table app.scheduled_task_runs enable row level security;

-- `(select auth.uid())`, never a bare `auth.uid()`: inside a policy clause the bare call is
-- re-evaluated per row, while the scalar subquery is hoisted into an InitPlan and evaluated once.
-- scripts/security/check-rls-initplan.ts enforces this repository-wide and caught the first draft
-- of these two policies.
create policy tenant_scheduled_tasks_select_scoped on app.tenant_scheduled_tasks
  for select to authenticated
  using (app.is_support_grant_authority((select auth.uid()), tenant_id));

create policy scheduled_task_runs_select_scoped on app.scheduled_task_runs
  for select to authenticated
  using (app.is_support_grant_authority((select auth.uid()), tenant_id));

-- ===========================================================================
-- 8. public.* wrappers (RGL-394 Option 2) -- app is not exposed to PostgREST
-- ===========================================================================

create function public.configure_tenant_scheduled_task(
  p_tenant_id uuid, p_task_code text, p_enabled boolean, p_interval_minutes integer,
  p_params jsonb, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.tenant_scheduled_tasks
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.configure_tenant_scheduled_task(p_tenant_id, p_task_code, p_enabled, p_interval_minutes, p_params, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.configure_tenant_scheduled_task(uuid, text, boolean, integer, jsonb, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.configure_tenant_scheduled_task, never a reimplementation.';

revoke execute on function public.configure_tenant_scheduled_task(uuid, text, boolean, integer, jsonb, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.configure_tenant_scheduled_task(uuid, text, boolean, integer, jsonb, uuid, text) to authenticated, service_role;

create function public.list_tenant_scheduled_tasks(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, task_code text, display_name text, description text, tenant_admin_configurable boolean,
  configurable_by_actor boolean, enabled boolean, interval_minutes integer, min_interval_minutes integer,
  default_interval_minutes integer, required_params text[], params jsonb,
  authorized_by_auth_user_id uuid, authorized_at timestamptz, next_run_at timestamptz,
  last_run_at timestamptz, last_run_status text, last_run_detail text,
  consecutive_authority_failures integer, disabled_reason text, record_version integer
)
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_tenant_scheduled_tasks(p_tenant_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_tenant_scheduled_tasks(uuid, uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_tenant_scheduled_tasks, never a reimplementation.';

revoke execute on function public.list_tenant_scheduled_tasks(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_tenant_scheduled_tasks(uuid, uuid) to authenticated, service_role;

create function public.set_scheduled_task_delegation(p_task_code text, p_tenant_admin_configurable boolean, p_actor_auth_user_id uuid, p_actor_label text)
returns app.scheduled_task_definitions
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.set_scheduled_task_delegation(p_task_code, p_tenant_admin_configurable, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.set_scheduled_task_delegation(text, boolean, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.set_scheduled_task_delegation, never a reimplementation.';

revoke execute on function public.set_scheduled_task_delegation(text, boolean, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.set_scheduled_task_delegation(text, boolean, uuid, text) to authenticated, service_role;

-- The runner gets a wrapper too, with a grant set matching its app.* counterpart EXACTLY:
-- service_role and nothing else. It needs one because a worker calling through PostgREST can
-- only reach the public schema, and the parity gate requires one for every externally-callable
-- app.* function -- but "externally callable" here still means service_role only, never anon and
-- never authenticated. The revoke names anon explicitly rather than relying on `from public`,
-- because Supabase's ALTER DEFAULT PRIVILEGES grants anon EXECUTE outright at CREATE time and an
-- explicit grant survives a PUBLIC revoke -- the ISS-2026-309 mechanism.
create function public.run_due_scheduled_tasks(p_now timestamptz default now(), p_limit integer default 50)
returns table (scheduled_task_id uuid, tenant_id uuid, task_code text, status text, detail text)
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.run_due_scheduled_tasks(p_now, p_limit);
$wrap$;

comment on function public.run_due_scheduled_tasks(timestamptz, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.run_due_scheduled_tasks, never a reimplementation. service_role-only, matching the app.* grant set exactly -- this is the scheduler''s own entry point and must never be reachable by anon or by an authenticated session.';

revoke execute on function public.run_due_scheduled_tasks(timestamptz, integer) from anon, authenticated, service_role, public;
grant execute on function public.run_due_scheduled_tasks(timestamptz, integer) to service_role;
