-- ISS-2026-254 (docs/runtime/KNOWN_ISSUES.md): closes the one gap the entry's own
-- 2026-08-25 partial resolution named as still open. That resolution
-- (20260826080000_harden_restore_security_state_reconciliation.sql) built
-- app.capture_security_state_snapshot() and app.detect_reverted_security_state(), but
-- both are VOLUNTARY -- nothing forces the snapshot step to actually happen before a
-- real restore, because a real restore runs entirely outside any RPC this schema
-- controls (raw psql/pg_restore, per docs/runbooks/database-restore.md). Its own
-- closing text named the fix this migration builds: "a scheduled periodic snapshot
-- independent of any specific restore."
--
-- THE DESIGN PROBLEM, STATED HONESTLY
--
--   The tenant task scheduler this repository already has
--   (20260831090000_create_tenant_configurable_task_scheduler.sql) is strictly
--   per-tenant: app.tenant_scheduled_tasks.tenant_id is NOT NULL references
--   app.tenants(id), because every task in its catalogue sweeps ONE tenant's own
--   data. app.capture_security_state_snapshot is deliberately the opposite shape --
--   platform-wide, across every tenant at once, because a restore is a whole-database
--   operation, not a per-tenant one. Registering it as a fake "tenant task" would mean
--   picking an arbitrary tenant to own a platform-wide action, which misrepresents who
--   is accountable for it. Widening app.tenant_scheduled_tasks.tenant_id to nullable
--   would let a NULL-tenant row silently coexist with real tenant rows in the same
--   table and the same dispatcher, which is a correctness hazard for zero benefit --
--   the two shapes never need to run in the same query or share a unique key.
--
--   The fix here is the other option this entry's own owner text left open: a small
--   sibling schema -- app.platform_scheduled_task_definitions,
--   app.platform_scheduled_tasks, app.platform_scheduled_task_runs -- that mirrors the
--   tenant scheduler's shape (same columns, same authority-recheck-every-run design,
--   same three-strikes auto-disable) with tenant_id simply absent rather than nullable,
--   and its own catalogue kept separate from app.scheduled_task_definitions rather than
--   sharing it: a shared catalogue would let a Supreme Admin accidentally register a
--   platform-wide task through app.configure_tenant_scheduled_task against some
--   arbitrary tenant_id, which the tenant dispatcher would then fail on forever with
--   scheduled_task_not_dispatchable -- a silent footgun a separate catalogue makes
--   structurally impossible rather than merely discouraged.
--
-- AUTHORITY, UNCHANGED FROM THE TENANT SCHEDULER'S OWN DESIGN
--
--   A scheduled run still executes as a real, accountable Supreme Admin identity --
--   never a synthetic system account -- re-checked on every single run via
--   app.is_supreme_admin(authorized_by_auth_user_id) inside
--   app.run_security_state_snapshot_capture, which app._run_platform_scheduled_task_once
--   dispatches to exactly as the tenant dispatcher dispatches to an RBAC-gated sweep
--   RPC. If that identity's Supreme Admin grant is revoked, the run fails
--   'unauthorized', not 'succeeded', and three consecutive unauthorized runs
--   auto-disable the schedule with the reason recorded -- identical discipline, not a
--   weakened platform-level lane.
--
-- WHAT THIS DOES AND DOES NOT CLOSE
--
--   It removes "a snapshot was never taken" as a real possibility: once a Supreme
--   Admin configures this schedule (hourly by default) and something drives
--   app.run_due_platform_scheduled_tasks periodically, a fresh snapshot always exists,
--   independent of whether any specific operator remembers the runbook step before any
--   specific restore. It does NOT install pg_cron or wire anything to run
--   automatically on the live project -- exactly the same disclosed boundary
--   20260831090000 drew for the tenant scheduler: this migration builds the
--   mechanism and exposes app.run_due_platform_scheduled_tasks as the entry point a
--   cron job or the scripts/jobs worker can call; turning that on is the operator's own
--   infrastructure step, covered by docs/runbooks/database-restore.md's own update in
--   this same change. And it does not, and cannot, literally intercept an external
--   pg_restore invocation -- Postgres has no hook into a process outside itself. What it
--   closes is the actual risk: "snapshot never taken" becomes structurally hard to
--   reach rather than a matter of operator memory.

-- ===========================================================================
-- 1. The platform-wide catalogue -- Supreme Admin's, deliberately separate from
-- app.scheduled_task_definitions (see header: a shared catalogue would let a
-- platform-wide task be mis-registered as a tenant task).
-- ===========================================================================

create table app.platform_scheduled_task_definitions (
  task_code text primary key,
  display_name text not null,
  description text not null,
  min_interval_minutes integer not null,
  default_interval_minutes integer not null,
  required_params text[] not null default '{}',
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_scheduled_task_definitions_status_check check (status in ('active', 'retired')),
  constraint platform_scheduled_task_definitions_interval_check check (min_interval_minutes > 0 and default_interval_minutes >= min_interval_minutes)
);

comment on table app.platform_scheduled_task_definitions is
  'ISS-2026-254: the catalogue of PLATFORM-WIDE (not per-tenant) tasks that may be scheduled, owned by Supreme Admin. Deliberately a separate table from app.scheduled_task_definitions -- that catalogue''s rows are dispatched by app._run_scheduled_task_once against a per-tenant app.tenant_scheduled_tasks row, and a platform-wide action has no tenant to run against. Every row here is dispatched instead by app._run_platform_scheduled_task_once against app.platform_scheduled_tasks.';

create table app.platform_scheduled_tasks (
  id uuid primary key default gen_random_uuid(),
  task_code text not null references app.platform_scheduled_task_definitions (task_code),
  enabled boolean not null default true,
  interval_minutes integer not null,
  params jsonb not null default '{}'::jsonb,
  -- Same design as app.tenant_scheduled_tasks.authorized_by_auth_user_id: the identity
  -- every run of this schedule ACTS AS. Not a system account -- a real, accountable
  -- Supreme Admin who took a real action to authorize this standing instruction.
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
  constraint platform_scheduled_tasks_unique unique (task_code, params),
  constraint platform_scheduled_tasks_interval_check check (interval_minutes > 0),
  constraint platform_scheduled_tasks_last_status_check check (last_run_status is null or last_run_status in ('succeeded', 'failed', 'unauthorized')),
  constraint platform_scheduled_tasks_disabled_reason_check check (enabled or disabled_reason is not null)
);

comment on table app.platform_scheduled_tasks is
  'ISS-2026-254: one row per (task_code, params) -- a platform-wide schedule, with no tenant_id because the task it schedules is not scoped to one tenant. authorized_by_auth_user_id is the identity every run ACTS AS, re-checked on every run via app.is_supreme_admin (never cached), exactly like app.tenant_scheduled_tasks.authorized_by_auth_user_id. Three consecutive unauthorized runs auto-disable the row with disabled_reason set, identical discipline to the tenant scheduler -- this platform-level lane is not weakened.';

comment on column app.platform_scheduled_tasks.authorized_by_auth_user_id is
  'Re-stamped on every configure call with the identity of whoever configured it (must hold an active Supreme Admin grant at configuration time and on every subsequent run). Re-authorizing after that person''s access is revoked is therefore a real act by a different, currently-authorized Supreme Admin, not a flag someone clears.';

create index platform_scheduled_tasks_due_idx on app.platform_scheduled_tasks (next_run_at) where enabled;

create table app.platform_scheduled_task_runs (
  id uuid primary key default gen_random_uuid(),
  scheduled_task_id uuid not null references app.platform_scheduled_tasks (id),
  task_code text not null,
  ran_as_auth_user_id uuid not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null,
  detail text,
  constraint platform_scheduled_task_runs_status_check check (status in ('succeeded', 'failed', 'unauthorized'))
);

comment on table app.platform_scheduled_task_runs is
  'ISS-2026-254: append-only run history for the platform-wide scheduler, the same shape and purpose as app.scheduled_task_runs. ran_as_auth_user_id records the identity the run actually executed as -- a scheduled platform-wide action is attributable to a real Supreme Admin, never to "the system".';

create index platform_scheduled_task_runs_task_idx on app.platform_scheduled_task_runs (scheduled_task_id, started_at desc);

create trigger platform_scheduled_tasks_touch_row
  before update on app.platform_scheduled_tasks
  for each row execute function app.touch_org_unit_row();

-- ===========================================================================
-- 2. The catalogue's initial (and, for now, only) content: the security-state
-- snapshot this entire migration exists to make periodic.
-- ===========================================================================

insert into app.platform_scheduled_task_definitions
  (task_code, display_name, description, min_interval_minutes, default_interval_minutes, required_params)
values
  ('security_state_snapshot', 'Security state snapshot (ISS-2026-254)',
   'Captures the current IDs of every active legal hold, revoked API key, disabled webhook endpoint, and suspended/revoked user or membership into public.security_state_snapshots via app.capture_security_state_snapshot, so a fresh snapshot always exists ahead of any restore rather than depending on an operator remembering to run it manually.',
   15, 60, '{}');

-- ===========================================================================
-- 3. The accountable entry point: authority-gated, then delegates to the ALREADY
-- EXISTING capture RPC. Reimplements none of its logic -- it exists only to add the
-- Supreme-Admin authority check that capture_security_state_snapshot itself never
-- had (it was built as a service_role-only manual-operator primitive, with no actor
-- argument at all), so a scheduled run has the same "re-check authority every run,
-- fail as unauthorized rather than silently, three-strikes auto-disable" discipline
-- every other entry in this scheduler family has.
-- ===========================================================================

create function app.run_security_state_snapshot_capture(p_actor_auth_user_id uuid, p_actor_label text)
returns public.security_state_snapshots
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_snapshot public.security_state_snapshots;
  v_label text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not capture a platform-wide security state snapshot -- Supreme Admin only', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  v_label := coalesce(nullif(trim(p_actor_label), ''), 'supreme_admin:' || p_actor_auth_user_id::text);

  v_snapshot := app.capture_security_state_snapshot(v_label);

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'run_security_state_snapshot_capture',
    'public.security_state_snapshots', v_snapshot.id, 'success', null, null,
    jsonb_build_object('snapshot_id', v_snapshot.id, 'captured_at', v_snapshot.captured_at)
  );

  return v_snapshot;
end;
$$;

comment on function app.run_security_state_snapshot_capture is
  'ISS-2026-254: the authority-gated, accountable entry point a Supreme Admin (or the platform scheduler acting as one) calls to capture a security-state snapshot. Adds nothing to app.capture_security_state_snapshot''s own logic -- it is a pure Supreme-Admin authority gate in front of it, re-checked on every call via app.is_supreme_admin, so a scheduled run has the same authority-recheck-every-run discipline as every other task in this scheduler family. Raises insufficient_privilege (not a silent no-op) when the calling identity does not currently hold an active Supreme Admin grant.';

revoke execute on function app.run_security_state_snapshot_capture(uuid, text) from public;
grant execute on function app.run_security_state_snapshot_capture(uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 4. Configure the platform-wide schedule -- Supreme-Admin-only, no delegation
-- switch exists here because there is no tenant to delegate to.
-- ===========================================================================

create function app.configure_platform_scheduled_task(
  p_task_code text,
  p_enabled boolean,
  p_interval_minutes integer,
  p_params jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.platform_scheduled_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_definition app.platform_scheduled_task_definitions;
  v_schedule app.platform_scheduled_tasks;
  v_params jsonb := coalesce(p_params, '{}'::jsonb);
  v_interval integer;
  v_missing text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not configure a platform-wide scheduled task -- Supreme Admin only', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_definition from app.platform_scheduled_task_definitions where task_code = p_task_code;
  if not found or v_definition.status <> 'active' then
    raise exception 'platform_scheduled_task_not_available: % is not an active platform catalogue task', p_task_code using errcode = 'no_data_found';
  end if;

  v_interval := coalesce(p_interval_minutes, v_definition.default_interval_minutes);
  if v_interval < v_definition.min_interval_minutes then
    raise exception 'platform_scheduled_task_interval_too_short: % requires at least % minutes between runs, got %', p_task_code, v_definition.min_interval_minutes, v_interval
      using errcode = 'check_violation';
  end if;

  -- Validated here, at configuration time, mirroring app.configure_tenant_scheduled_task
  -- exactly -- a misconfiguration surfaces to the person making it, not at 03:00.
  foreach v_missing in array v_definition.required_params loop
    if not (v_params ? v_missing) then
      raise exception 'platform_scheduled_task_missing_param: % requires the % parameter', p_task_code, v_missing using errcode = 'check_violation';
    end if;
  end loop;

  insert into app.platform_scheduled_tasks as t
    (task_code, enabled, interval_minutes, params, authorized_by_auth_user_id, authorized_at,
     next_run_at, consecutive_authority_failures, disabled_reason, created_by)
  values
    (p_task_code, p_enabled, v_interval, v_params, p_actor_auth_user_id, now(),
     now(), 0, case when p_enabled then null else 'disabled at configuration' end, p_actor_label)
  on conflict (task_code, params) do update
  set enabled = excluded.enabled,
      interval_minutes = excluded.interval_minutes,
      params = excluded.params,
      -- Re-stamped on purpose: whoever reconfigures a schedule becomes the identity it
      -- runs as, exactly as app.configure_tenant_scheduled_task already does.
      authorized_by_auth_user_id = excluded.authorized_by_auth_user_id,
      authorized_at = now(),
      consecutive_authority_failures = 0,
      disabled_reason = case when excluded.enabled then null else 'disabled at configuration' end,
      next_run_at = case when excluded.enabled then now() else t.next_run_at end
      -- record_version is NOT bumped here: platform_scheduled_tasks_touch_row already
      -- does it, and doing both would advance it by two per call (same reasoning as
      -- app.configure_tenant_scheduled_task).
  returning * into v_schedule;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'configure_platform_scheduled_task',
    'app.platform_scheduled_tasks', v_schedule.id, 'success', null, null,
    jsonb_build_object('task_code', p_task_code, 'enabled', v_schedule.enabled, 'interval_minutes', v_schedule.interval_minutes, 'params', v_schedule.params)
  );

  return v_schedule;
end;
$$;

comment on function app.configure_platform_scheduled_task is
  'ISS-2026-254: creates or updates a platform-wide schedule for one catalogue task. Supreme-Admin-only -- there is no delegation switch, unlike app.configure_tenant_scheduled_task, because a platform-wide action has no tenant admin to delegate to. Otherwise mirrors that function''s behaviour exactly: interval floor and required parameters validated at configuration time, identity re-stamped and failure counter reset on every call.';

revoke execute on function app.configure_platform_scheduled_task(text, boolean, integer, jsonb, uuid, text) from public;
grant execute on function app.configure_platform_scheduled_task(text, boolean, integer, jsonb, uuid, text) to authenticated, service_role;

create function app.list_platform_scheduled_tasks(p_actor_auth_user_id uuid)
returns table (
  id uuid, task_code text, display_name text, description text,
  enabled boolean, interval_minutes integer, min_interval_minutes integer,
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

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not read platform-wide scheduled tasks -- Supreme Admin only', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select s.id, d.task_code, d.display_name, d.description,
         coalesce(s.enabled, false), s.interval_minutes, d.min_interval_minutes,
         d.default_interval_minutes, d.required_params, coalesce(s.params, '{}'::jsonb),
         s.authorized_by_auth_user_id, s.authorized_at, s.next_run_at,
         s.last_run_at, s.last_run_status, s.last_run_detail,
         coalesce(s.consecutive_authority_failures, 0), s.disabled_reason, s.record_version
  from app.platform_scheduled_task_definitions d
  left join app.platform_scheduled_tasks s on s.task_code = d.task_code
  where d.status = 'active'
  order by d.display_name;
end;
$$;

comment on function app.list_platform_scheduled_tasks is
  'ISS-2026-254: the configuration screen''s read for platform-wide schedules, Supreme-Admin-only. Mirrors app.list_tenant_scheduled_tasks in shape (every active catalogue task, configured or not) minus the per-tenant configurable_by_actor flag, which has no meaning here -- only Supreme Admin may ever configure a platform-wide task.';

revoke execute on function app.list_platform_scheduled_tasks(uuid) from public;
grant execute on function app.list_platform_scheduled_tasks(uuid) to authenticated, service_role;

-- ===========================================================================
-- 5. The platform-wide dispatcher, mirroring app._run_scheduled_task_once /
-- app.run_due_scheduled_tasks exactly, just without a tenant column anywhere.
-- ===========================================================================

create function app._run_platform_scheduled_task_once(p_schedule app.platform_scheduled_tasks, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_actor uuid := p_schedule.authorized_by_auth_user_id;
  v_label text := 'scheduler:' || p_schedule.task_code;
begin
  case p_schedule.task_code
    when 'security_state_snapshot' then
      perform app.run_security_state_snapshot_capture(v_actor, v_label);
    else
      raise exception 'platform_scheduled_task_not_dispatchable: % has a catalogue row but no dispatch branch', p_schedule.task_code
        using errcode = 'check_violation';
  end case;
end;
$$;

comment on function app._run_platform_scheduled_task_once is
  'Internal (app._ prefix, service_role-only): the explicit per-task dispatch for platform-wide schedules, the sibling of app._run_scheduled_task_once. Deliberately a CASE, not dynamic SQL, for the identical reason. Passes the schedule''s own authorized_by_auth_user_id as the actor to app.run_security_state_snapshot_capture, which re-checks that identity''s Supreme Admin authority on every call.';

revoke execute on function app._run_platform_scheduled_task_once(app.platform_scheduled_tasks, timestamptz) from public, anon, authenticated;
grant execute on function app._run_platform_scheduled_task_once(app.platform_scheduled_tasks, timestamptz) to service_role;

create function app.run_due_platform_scheduled_tasks(p_now timestamptz default now(), p_limit integer default 50)
returns table (scheduled_task_id uuid, task_code text, status text, detail text)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_schedule app.platform_scheduled_tasks;
  v_status text;
  v_detail text;
  v_run_id uuid;
begin
  for v_schedule in
    select * from app.platform_scheduled_tasks t
    where t.enabled and t.next_run_at <= p_now
    order by t.next_run_at
    limit greatest(coalesce(p_limit, 50), 1)
    for update skip locked
  loop
    v_status := 'succeeded';
    v_detail := null;
    insert into app.platform_scheduled_task_runs (scheduled_task_id, task_code, ran_as_auth_user_id, status)
    values (v_schedule.id, v_schedule.task_code, v_schedule.authorized_by_auth_user_id, 'failed')
    returning id into v_run_id;

    begin
      perform app._run_platform_scheduled_task_once(v_schedule, p_now);
    exception
      when insufficient_privilege then
        v_status := 'unauthorized';
        v_detail := sqlerrm;
      when others then
        v_status := 'failed';
        v_detail := sqlerrm;
    end;

    update app.platform_scheduled_task_runs
    set finished_at = now(), status = v_status, detail = v_detail
    where id = v_run_id;

    update app.platform_scheduled_tasks t
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
    task_code := v_schedule.task_code;
    status := v_status;
    detail := v_detail;
    return next;
  end loop;
end;
$$;

comment on function app.run_due_platform_scheduled_tasks is
  'ISS-2026-254: the platform-wide scheduler entry point, service_role-only, the sibling of app.run_due_scheduled_tasks. Runs every enabled platform schedule whose next_run_at has passed, as its own authorizing Supreme Admin identity, re-checked live on every run. Three consecutive unauthorized outcomes auto-disable the schedule with the reason recorded, identical discipline to the tenant scheduler. Nothing calls this automatically yet -- installing pg_cron, or pointing the existing scripts/jobs worker pattern at it (alongside app.run_due_scheduled_tasks), is the operator''s own deliberate infrastructure step, now documented as the mandatory mechanism behind docs/runbooks/database-restore.md''s pre-restore snapshot step.';

revoke execute on function app.run_due_platform_scheduled_tasks(timestamptz, integer) from public, anon, authenticated;
grant execute on function app.run_due_platform_scheduled_tasks(timestamptz, integer) to service_role;

-- ===========================================================================
-- 6. Grants and RLS
-- ===========================================================================

grant select on app.platform_scheduled_task_definitions to authenticated, service_role;
grant insert, update on app.platform_scheduled_task_definitions to service_role;
grant select, insert, update on app.platform_scheduled_tasks to service_role;
grant select, insert, update on app.platform_scheduled_task_runs to service_role;

-- No `authenticated` grant on app.platform_scheduled_tasks or
-- app.platform_scheduled_task_runs: both carry authorizing-identity columns and
-- failure text, and the only intended read path is app.list_platform_scheduled_tasks,
-- which is Supreme-Admin-gated. RLS is enabled anyway as defence in depth, exactly the
-- same reasoning 20260831090000 already applied to their tenant-scoped siblings.
alter table app.platform_scheduled_tasks enable row level security;
alter table app.platform_scheduled_task_runs enable row level security;

-- `(select auth.uid())`, never a bare `auth.uid()`: see 20260831090000's own comment --
-- scripts/security/check-rls-initplan.ts enforces this repository-wide.
create policy platform_scheduled_tasks_select_scoped on app.platform_scheduled_tasks
  for select to authenticated
  using (app.is_supreme_admin((select auth.uid())));

create policy platform_scheduled_task_runs_select_scoped on app.platform_scheduled_task_runs
  for select to authenticated
  using (app.is_supreme_admin((select auth.uid())));

-- ===========================================================================
-- 7. public.* wrappers (RGL-394 Option 2) -- app is not exposed to PostgREST
-- ===========================================================================

create function public.run_security_state_snapshot_capture(p_actor_auth_user_id uuid, p_actor_label text)
returns public.security_state_snapshots
language sql
volatile
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.run_security_state_snapshot_capture(p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.run_security_state_snapshot_capture(uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.run_security_state_snapshot_capture, never a reimplementation.';

revoke execute on function public.run_security_state_snapshot_capture(uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.run_security_state_snapshot_capture(uuid, text) to authenticated, service_role;

create function public.configure_platform_scheduled_task(
  p_task_code text, p_enabled boolean, p_interval_minutes integer,
  p_params jsonb, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.platform_scheduled_tasks
language sql
volatile
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.configure_platform_scheduled_task(p_task_code, p_enabled, p_interval_minutes, p_params, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.configure_platform_scheduled_task(text, boolean, integer, jsonb, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.configure_platform_scheduled_task, never a reimplementation.';

revoke execute on function public.configure_platform_scheduled_task(text, boolean, integer, jsonb, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.configure_platform_scheduled_task(text, boolean, integer, jsonb, uuid, text) to authenticated, service_role;

create function public.list_platform_scheduled_tasks(p_actor_auth_user_id uuid)
returns table (
  id uuid, task_code text, display_name text, description text,
  enabled boolean, interval_minutes integer, min_interval_minutes integer,
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
  select * from app.list_platform_scheduled_tasks(p_actor_auth_user_id);
$wrap$;

comment on function public.list_platform_scheduled_tasks(uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_platform_scheduled_tasks, never a reimplementation.';

revoke execute on function public.list_platform_scheduled_tasks(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_platform_scheduled_tasks(uuid) to authenticated, service_role;

-- service_role-only, matching its app.* counterpart exactly -- this is the scheduler's
-- own entry point and must never be reachable by anon or by an authenticated session,
-- identical reasoning to public.run_due_scheduled_tasks.
create function public.run_due_platform_scheduled_tasks(p_now timestamptz default now(), p_limit integer default 50)
returns table (scheduled_task_id uuid, task_code text, status text, detail text)
language sql
volatile
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.run_due_platform_scheduled_tasks(p_now, p_limit);
$wrap$;

comment on function public.run_due_platform_scheduled_tasks(timestamptz, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.run_due_platform_scheduled_tasks, never a reimplementation. service_role-only, matching the app.* grant set exactly.';

revoke execute on function public.run_due_platform_scheduled_tasks(timestamptz, integer) from anon, authenticated, service_role, public;
grant execute on function public.run_due_platform_scheduled_tasks(timestamptz, integer) to service_role;
