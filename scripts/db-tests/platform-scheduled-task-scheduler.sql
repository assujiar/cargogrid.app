-- Real, executable evidence for the platform-wide scheduler
-- (20260902020000_create_platform_wide_security_snapshot_scheduler.sql), closing
-- ISS-2026-254's own final named gap: nothing forced app.capture_security_state_snapshot
-- to actually run before a restore. Run via `pnpm run db:test` against a real,
-- disposable Postgres database.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000000254001..004.
-- Grep-verified unclaimed against every other *.sql fixture in this directory before use.
--
-- Mirrors scripts/db-tests/task-scheduler.sql's own shape exactly, on the same four
-- questions that matter for an authority-recheck-every-run scheduler design: who may
-- configure it, does a real run produce real evidence, does an authority revocation
-- mid-schedule fail the run rather than silently skipping it, and does three
-- consecutive failures auto-disable the schedule. The one thing this file does NOT
-- need to test that task-scheduler.sql does: there is no per-tenant delegation switch
-- here at all -- a platform-wide task has no tenant to delegate to, so "Supreme Admin
-- or nobody" is the entire authority model.

\set ON_ERROR_STOP on

\echo '>> setup: two Supreme Admins and one plain user holding no Supreme Admin grant at all'
do $$
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000254001', 'supreme1@platsched.test'),
    ('00000000-0000-0000-0000-000000254002', 'supreme2@platsched.test'),
    ('00000000-0000-0000-0000-000000254003', 'plain@platsched.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000254001', 'supreme_admin', null, null, 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000254002', 'supreme_admin', null, null, 'tester');
  -- 254003 deliberately receives NO membership grant of any kind -- a real authenticated
  -- identity that is simply not a Supreme Admin, the exact shape ISS-2026-254's own
  -- required regression coverage names ("a non-Supreme-Admin caller is refused").
end;
$$;

\echo '>> the platform catalogue exists, is Supreme-Admin-scoped, and carries a real interval floor -- ISS-2026-254''s own security_state_snapshot task is in it'
do $$
declare
  v_def app.platform_scheduled_task_definitions;
begin
  select * into v_def from app.platform_scheduled_task_definitions where task_code = 'security_state_snapshot';
  if not found then
    raise exception 'assertion failed: security_state_snapshot is not in the platform catalogue';
  end if;
  if v_def.status <> 'active' then
    raise exception 'assertion failed: security_state_snapshot must be an active catalogue task';
  end if;
  if v_def.min_interval_minutes <= 0 or v_def.default_interval_minutes < v_def.min_interval_minutes then
    raise exception 'assertion failed: the catalogue task needs a positive interval floor and a default at or above it';
  end if;

  raise notice 'PASS: security_state_snapshot is a real, active, floored platform catalogue task';
end;
$$;

\echo '>> authority: a non-Supreme-Admin identity is refused BOTH configuring and reading the platform schedule; a Supreme Admin may do both'
do $$
declare
  v_plain uuid := '00000000-0000-0000-0000-000000254003';
  v_supreme uuid := '00000000-0000-0000-0000-000000254001';
  v_schedule app.platform_scheduled_tasks;
  v_rows integer;
begin
  begin
    perform app.configure_platform_scheduled_task('security_state_snapshot', true, 60, '{}'::jsonb, v_plain, 'plain');
    raise exception 'assertion failed: a non-Supreme-Admin identity must not be able to configure a platform-wide scheduled task';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.list_platform_scheduled_tasks(v_plain);
    raise exception 'assertion failed: a non-Supreme-Admin identity must not be able to read platform-wide schedules';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.run_security_state_snapshot_capture(v_plain, 'plain');
    raise exception 'assertion failed: a non-Supreme-Admin identity must not be able to trigger a security-state snapshot capture, scheduled entry point or not';
  exception when insufficient_privilege then null;
  end;

  select * into v_schedule from app.configure_platform_scheduled_task('security_state_snapshot', true, 60, '{}'::jsonb, v_supreme, 'supreme1');
  if v_schedule.authorized_by_auth_user_id <> v_supreme then
    raise exception 'assertion failed: the schedule must record the configuring Supreme Admin as the identity it runs as, got %', v_schedule.authorized_by_auth_user_id;
  end if;
  if not v_schedule.enabled or v_schedule.interval_minutes <> 60 then
    raise exception 'assertion failed: expected an enabled 60-minute schedule';
  end if;

  select count(*) into v_rows from app.list_platform_scheduled_tasks(v_supreme);
  if v_rows <> 1 then
    raise exception 'assertion failed: expected exactly 1 platform catalogue task listed, got %', v_rows;
  end if;

  raise notice 'PASS: a non-Supreme-Admin identity is refused configuring, reading, and directly triggering; a Supreme Admin may do all three';
end;
$$;

\echo '>> a real run: the dispatcher executes as the schedule''s own authorizing Supreme Admin, produces a REAL new row in public.security_state_snapshots (not merely a succeeded status), and next_run_at advances'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000000254001';
  v_schedule app.platform_scheduled_tasks;
  v_result record;
  v_run app.platform_scheduled_task_runs;
  v_snapshots_before integer;
  v_snapshots_after integer;
  v_before timestamptz;
begin
  select * into v_schedule from app.platform_scheduled_tasks where task_code = 'security_state_snapshot';
  v_before := v_schedule.next_run_at;

  select count(*) into v_snapshots_before from public.security_state_snapshots;

  update app.platform_scheduled_tasks set next_run_at = now() - interval '1 minute' where id = v_schedule.id;

  select * into v_result from app.run_due_platform_scheduled_tasks(now(), 50) where scheduled_task_id = v_schedule.id;
  if v_result.status is null then
    raise exception 'assertion failed: the due platform schedule should have been picked up by app.run_due_platform_scheduled_tasks';
  end if;
  if v_result.status <> 'succeeded' then
    raise exception 'assertion failed: expected the Supreme-Admin-authorized snapshot capture to succeed, got % (%)', v_result.status, v_result.detail;
  end if;

  -- The whole point of ISS-2026-254's fix: this must be REAL evidence, not a status
  -- string. A genuinely new row must exist in the table the manual runbook step reads.
  select count(*) into v_snapshots_after from public.security_state_snapshots;
  if v_snapshots_after <= v_snapshots_before then
    raise exception 'assertion failed: a succeeded scheduled run must leave a real new row in public.security_state_snapshots (before %, after %)', v_snapshots_before, v_snapshots_after;
  end if;
  if not exists (select 1 from public.security_state_snapshots where actor_label like 'scheduler:security_state_snapshot%' order by captured_at desc limit 1) then
    raise exception 'assertion failed: the scheduled snapshot must record an actor_label naming the scheduler, not a blank or manual-looking label';
  end if;

  select * into v_run from app.platform_scheduled_task_runs where scheduled_task_id = v_schedule.id order by started_at desc limit 1;
  if v_run.ran_as_auth_user_id <> v_supreme then
    raise exception 'assertion failed: the run must record the identity it actually ran as (expected %, got %)', v_supreme, v_run.ran_as_auth_user_id;
  end if;
  if v_run.status <> 'succeeded' or v_run.finished_at is null then
    raise exception 'assertion failed: the run row must be closed out with a real status and finish time';
  end if;

  select * into v_schedule from app.platform_scheduled_tasks where id = v_schedule.id;
  if v_schedule.next_run_at <= v_before then
    raise exception 'assertion failed: next_run_at must advance after a run (was %, now %)', v_before, v_schedule.next_run_at;
  end if;
  if v_schedule.last_run_status <> 'succeeded' or v_schedule.consecutive_authority_failures <> 0 then
    raise exception 'assertion failed: a successful run must record success and leave the failure counter at zero';
  end if;

  -- Not due yet: a second immediate pass must not re-run it, exactly like the tenant
  -- scheduler -- otherwise a poller running every minute would capture every minute too.
  if exists (select 1 from app.run_due_platform_scheduled_tasks(now(), 50) where scheduled_task_id = v_schedule.id) then
    raise exception 'assertion failed: a platform schedule that is not yet due must not run again';
  end if;

  raise notice 'PASS: the scheduled run captured a real new security_state_snapshots row, attributed to its authorizing Supreme Admin, and will not re-run before it is due';
end;
$$;

\echo '>> the governance case this design exists for: revoking the authorizing identity''s Supreme Admin grant mid-schedule makes the NEXT run fail as unauthorized (not silently skip, not succeed), and three consecutive failures auto-disable the schedule with the reason recorded'
do $$
declare
  v_supreme2 uuid := '00000000-0000-0000-0000-000000254002';
  v_membership_id uuid;
  v_schedule app.platform_scheduled_tasks;
  v_result record;
  v_i integer;
begin
  -- A second Supreme Admin authorizes a SECOND platform schedule (a different params
  -- set, so it coexists with the first rather than overwriting it -- app.
  -- platform_scheduled_tasks_unique is (task_code, params)).
  select * into v_schedule from app.configure_platform_scheduled_task(
    'security_state_snapshot', true, 60, jsonb_build_object('note', 'secondary'), v_supreme2, 'supreme2');
  if v_schedule.authorized_by_auth_user_id <> v_supreme2 then
    raise exception 'assertion failed: expected the second Supreme Admin to be recorded as the authorizing identity';
  end if;

  -- Their Supreme Admin authority is now taken away -- a real revocation, not a mock.
  select id into v_membership_id from app.principal_memberships
  where auth_user_id = v_supreme2 and layer = 'supreme_admin' and status = 'active';
  if v_membership_id is null then
    raise exception 'assertion failed: test setup broken -- expected an active supreme_admin membership for %', v_supreme2;
  end if;
  perform app.revoke_principal_membership(v_membership_id, 'ISS-2026-254 regression: simulate a departed Supreme Admin', 'tester');

  for v_i in 1..3 loop
    update app.platform_scheduled_tasks set next_run_at = now() - interval '1 minute' where id = v_schedule.id;
    select * into v_result from app.run_due_platform_scheduled_tasks(now(), 50) where scheduled_task_id = v_schedule.id;
    if v_result.status is null then
      raise exception 'assertion failed: pass % should have picked up the due platform schedule', v_i;
    end if;
    if v_result.status <> 'unauthorized' then
      raise exception 'assertion failed: pass % expected an unauthorized outcome after the authorizer''s grant was revoked, got % (%)', v_i, v_result.status, v_result.detail;
    end if;
  end loop;

  select * into v_schedule from app.platform_scheduled_tasks where id = v_schedule.id;
  if v_schedule.enabled then
    raise exception 'assertion failed: three consecutive authority failures must auto-disable the platform schedule';
  end if;
  if v_schedule.disabled_reason is null or v_schedule.disabled_reason not like 'auto-disabled%' then
    raise exception 'assertion failed: an auto-disabled platform schedule must say why, got %', coalesce(v_schedule.disabled_reason, '<null>');
  end if;
  if v_schedule.consecutive_authority_failures < 3 then
    raise exception 'assertion failed: expected the authority-failure counter to have reached 3, got %', v_schedule.consecutive_authority_failures;
  end if;

  -- Disabled means disabled: it is not picked up again.
  update app.platform_scheduled_tasks set next_run_at = now() - interval '1 minute' where id = v_schedule.id;
  if exists (select 1 from app.run_due_platform_scheduled_tasks(now(), 50) where scheduled_task_id = v_schedule.id) then
    raise exception 'assertion failed: an auto-disabled platform schedule must not keep running';
  end if;

  if (select count(*) from app.platform_scheduled_task_runs where scheduled_task_id = v_schedule.id and status = 'unauthorized') < 3 then
    raise exception 'assertion failed: each unauthorized attempt must leave its own run row';
  end if;

  -- The FIRST schedule (still authorized by supreme1, never touched) must be completely
  -- unaffected -- one authorizer losing their grant must not disable another's schedule.
  if not exists (
    select 1 from app.platform_scheduled_tasks
    where task_code = 'security_state_snapshot' and params = '{}'::jsonb and enabled
  ) then
    raise exception 'assertion failed: the first (unrelated) platform schedule must remain enabled -- one authorizer''s revocation must not cascade to another schedule';
  end if;

  raise notice 'PASS: a revoked Supreme Admin grant makes the very next scheduled run fail unauthorized, three in a row auto-disable the schedule with a stated reason, and an unrelated schedule is unaffected';
end;
$$;

\echo '>> re-authorizing is a real act by a real (still-Supreme-Admin) person: reconfiguring re-stamps the authorizing identity, clears the failure counter, and the schedule runs again'
do $$
declare
  v_supreme1 uuid := '00000000-0000-0000-0000-000000254001';
  v_supreme2 uuid := '00000000-0000-0000-0000-000000254002';
  v_schedule app.platform_scheduled_tasks;
  v_result record;
begin
  select * into v_schedule from app.platform_scheduled_tasks
  where task_code = 'security_state_snapshot' and params = jsonb_build_object('note', 'secondary');
  if v_schedule.enabled then
    raise exception 'assertion failed: this block expects the auto-disabled schedule from the previous one';
  end if;

  select * into v_schedule from app.configure_platform_scheduled_task(
    'security_state_snapshot', true, 60, jsonb_build_object('note', 'secondary'), v_supreme1, 'supreme1');

  if v_schedule.authorized_by_auth_user_id <> v_supreme1 then
    raise exception 'assertion failed: reconfiguring must re-stamp the authorizing identity (still %)', v_schedule.authorized_by_auth_user_id;
  end if;
  if v_schedule.authorized_by_auth_user_id = v_supreme2 then
    raise exception 'assertion failed: the previous (now-revoked) authorizer must not remain the identity the schedule runs as';
  end if;
  if not v_schedule.enabled or v_schedule.disabled_reason is not null or v_schedule.consecutive_authority_failures <> 0 then
    raise exception 'assertion failed: re-authorizing must re-enable the schedule and clear both the reason and the counter';
  end if;

  update app.platform_scheduled_tasks set next_run_at = now() - interval '1 minute' where id = v_schedule.id;
  select * into v_result from app.run_due_platform_scheduled_tasks(now(), 50) where scheduled_task_id = v_schedule.id;
  if v_result.status <> 'succeeded' then
    raise exception 'assertion failed: the re-authorized platform schedule should now succeed, got % (%)', v_result.status, v_result.detail;
  end if;

  raise notice 'PASS: reconfiguring transfers the platform schedule to a currently-authorized Supreme Admin, clears the disabled state, and the capture runs again';
end;
$$;

\echo '>> defence in depth at the grant layer: anon holds zero EXECUTE on every new function; authenticated cannot call the runner or the internal dispatcher; the public.* wrappers match their app.* counterparts exactly; the schedule/run tables are not directly writable by authenticated'
do $$
begin
  if has_function_privilege('anon', 'app.run_due_platform_scheduled_tasks(timestamptz, integer)', 'EXECUTE')
     or has_function_privilege('anon', 'app.configure_platform_scheduled_task(text, boolean, integer, jsonb, uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'app.list_platform_scheduled_tasks(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'app.run_security_state_snapshot_capture(uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'app._run_platform_scheduled_task_once(app.platform_scheduled_tasks, timestamptz)', 'EXECUTE')
     or has_function_privilege('anon', 'public.run_due_platform_scheduled_tasks(timestamptz, integer)', 'EXECUTE')
     or has_function_privilege('anon', 'public.configure_platform_scheduled_task(text, boolean, integer, jsonb, uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.list_platform_scheduled_tasks(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.run_security_state_snapshot_capture(uuid, text)', 'EXECUTE')
  then
    raise exception 'assertion failed: anon must hold zero EXECUTE on every platform-scheduler function';
  end if;

  if has_function_privilege('authenticated', 'public.run_due_platform_scheduled_tasks(timestamptz, integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'app.run_due_platform_scheduled_tasks(timestamptz, integer)', 'EXECUTE')
  then
    raise exception 'assertion failed: authenticated must NOT be able to invoke the platform scheduler runner, directly or through its public wrapper';
  end if;
  if has_function_privilege('authenticated', 'app._run_platform_scheduled_task_once(app.platform_scheduled_tasks, timestamptz)', 'EXECUTE') then
    raise exception 'assertion failed: authenticated must NOT be able to invoke the platform per-task dispatcher directly';
  end if;

  -- The platform catalogue is readable (it is a menu); the schedule and run tables are
  -- not, because they carry authorizing-identity columns and failure text -- identical
  -- reasoning to app.tenant_scheduled_tasks / app.scheduled_task_runs.
  if not has_table_privilege('authenticated', 'app.platform_scheduled_task_definitions', 'SELECT') then
    raise exception 'assertion failed: the platform catalogue should be readable by authenticated -- it is a menu, not sensitive data';
  end if;
  if has_table_privilege('authenticated', 'app.platform_scheduled_tasks', 'INSERT')
     or has_table_privilege('authenticated', 'app.platform_scheduled_tasks', 'UPDATE')
     or has_table_privilege('authenticated', 'app.platform_scheduled_task_runs', 'INSERT')
     or has_table_privilege('authenticated', 'app.platform_scheduled_task_runs', 'UPDATE')
  then
    raise exception 'assertion failed: authenticated must never write platform schedules or run history directly -- app.configure_platform_scheduled_task is the only path, and it is Supreme-Admin-gated';
  end if;

  raise notice 'PASS: anon holds nothing, authenticated cannot reach the runner or the dispatcher or write schedule/run rows directly, and the catalogue stays readable';
end;
$$;

\echo 'ALL platform-scheduled-task-scheduler assertions passed.'
