-- Real, executable evidence for the tenant-configurable task scheduler
-- (20260831090000_create_tenant_configurable_task_scheduler.sql) -- run via
-- `pnpm run db:test` against a real, disposable Postgres database.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000000439001..004.
-- Grep-verified unclaimed against every other *.sql fixture in this directory before use.
--
-- What this file is really testing is an AUTHORITY MODEL, not a cron loop. The design decision
-- the whole capability rests on is that a scheduled sweep runs as the real person who authorized
-- the schedule, and that their authority is re-checked on every run rather than cached at
-- configuration time. So the assertions below spend most of their effort on: who may configure
-- what, what happens when the authorizing identity's rights go away, and whether a stale
-- schedule becomes visibly dead rather than quietly wrong.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (sched1) with a Supreme Admin, a tenant_admin, and a plain member holding no admin authority at all'
do $$
declare
  v_tenant1 uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000439001', 'supreme@sched1.test'),
    ('00000000-0000-0000-0000-000000439002', 'admin@sched1.test'),
    ('00000000-0000-0000-0000-000000439003', 'member@sched1.test'),
    ('00000000-0000-0000-0000-000000439004', 'admin2@sched1.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000439001', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('sched1', 'Scheduler Co 1', 'idem-sched1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'sched1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000439002', 'admin@sched1.test', 'Sched1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@sched1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000439002', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000439004', 'admin2@sched1.test', 'Sched1 Admin Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@sched1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000439004', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000439003', 'member@sched1.test', 'Sched1 Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@sched1.test'), 'active', 'onboarded', 'tester');
end;
$$;

\echo '>> the catalogue is real and Supreme-Admin-owned: twenty-three active tasks, each with an interval floor, and the delegation switch genuinely splits them'
do $$
declare
  v_total integer;
  v_delegable integer;
  v_platform_only integer;
begin
  select count(*) into v_total from app.scheduled_task_definitions where status = 'active';
  -- 11 seeded by 20260831090000, 5 added by 20260831100000 (the ISS-2026-249 authority denial
  -- sweep and ISS-2026-313's four), 3 added by 20260831230000 (loyalty earning/tier/points
  -- posting), 1 added by 20260831240000 (loyalty liability reconciliation), 1 added by
  -- 20260902043000 (ISS-2026-070's onboarding/offboarding overdue-task sweep), 1 added by
  -- 20260902221000 (ISS-2026-129 item 2's own loyalty benefit-issuance sweep), and 1 added by
  -- 20260903150000 (ISS-2026-134 item 4's loyalty engagement-metrics snapshot).
  if v_total <> 23 then
    raise exception 'assertion failed: expected 23 active catalogue tasks, got %', v_total;
  end if;

  select count(*) into v_delegable from app.scheduled_task_definitions where status = 'active' and tenant_admin_configurable;
  select count(*) into v_platform_only from app.scheduled_task_definitions where status = 'active' and not tenant_admin_configurable;
  if v_delegable = 0 or v_platform_only = 0 then
    raise exception 'assertion failed: the delegation switch must genuinely split the catalogue (delegable=%, platform-only=%)', v_delegable, v_platform_only;
  end if;

  -- The floor is not decorative: every task must carry one, or a tenant admin could schedule a
  -- tenant-wide sweep every minute.
  if exists (select 1 from app.scheduled_task_definitions where min_interval_minutes <= 0 or default_interval_minutes < min_interval_minutes) then
    raise exception 'assertion failed: every catalogue task needs a positive interval floor and a default at or above it';
  end if;

  raise notice 'PASS: catalogue has % active tasks -- % delegable to tenant admins, % Supreme-Admin-only', v_total, v_delegable, v_platform_only;
end;
$$;

\echo '>> authority: a plain tenant member may configure nothing; a tenant_admin may configure a DELEGATED task but not a Supreme-Admin-only one; a Supreme Admin may configure both'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sched1');
  v_supreme uuid := '00000000-0000-0000-0000-000000439001';
  v_admin uuid := '00000000-0000-0000-0000-000000439002';
  v_member uuid := '00000000-0000-0000-0000-000000439003';
  v_schedule app.tenant_scheduled_tasks;
begin
  -- A plain member: no path at all, for either kind of task.
  begin
    perform app.configure_tenant_scheduled_task(v_tenant1, 'employee_position_activation', true, 1440, '{}'::jsonb, v_member, 'member');
    raise exception 'assertion failed: a plain tenant member must not be able to configure a scheduled task';
  exception when insufficient_privilege then null;
  end;

  -- A tenant_admin on a task Supreme Admin has NOT delegated: denied. This is the half of the
  -- owner's design that keeps platform machinery out of tenant hands by default.
  begin
    perform app.configure_tenant_scheduled_task(v_tenant1, 'incident_escalation_sweep', true, 15, '{}'::jsonb, v_admin, 'admin');
    raise exception 'assertion failed: a tenant_admin must not configure a task Supreme Admin has not delegated';
  exception when insufficient_privilege then null;
  end;

  -- The same tenant_admin on a DELEGATED task: allowed, and it runs as them.
  select * into v_schedule from app.configure_tenant_scheduled_task(v_tenant1, 'employee_position_activation', true, 1440, '{}'::jsonb, v_admin, 'admin');
  if v_schedule.authorized_by_auth_user_id <> v_admin then
    raise exception 'assertion failed: the schedule must record the configuring identity as the one it runs as, got %', v_schedule.authorized_by_auth_user_id;
  end if;
  if not v_schedule.enabled or v_schedule.interval_minutes <> 1440 then
    raise exception 'assertion failed: expected an enabled 1440-minute schedule';
  end if;

  -- Supreme Admin may configure the platform-only one for the same tenant.
  select * into v_schedule from app.configure_tenant_scheduled_task(v_tenant1, 'incident_escalation_sweep', true, 15, '{}'::jsonb, v_supreme, 'supreme');
  if v_schedule.authorized_by_auth_user_id <> v_supreme then
    raise exception 'assertion failed: expected the Supreme Admin to be recorded as the authorizing identity';
  end if;

  raise notice 'PASS: member denied everywhere; tenant_admin allowed only on delegated tasks; Supreme Admin allowed on both';
end;
$$;

\echo '>> the delegation switch is real and live: flipping it Supreme-Admin-only takes a tenant_admin''s configuration right away, and flipping it back restores it -- and only a Supreme Admin may flip it'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sched1');
  v_supreme uuid := '00000000-0000-0000-0000-000000439001';
  v_admin uuid := '00000000-0000-0000-0000-000000439002';
begin
  begin
    perform app.set_scheduled_task_delegation('incident_escalation_sweep', true, v_admin, 'admin');
    raise exception 'assertion failed: a tenant_admin must not be able to grant themselves configuration rights';
  exception when insufficient_privilege then null;
  end;

  if not app._can_configure_tenant_scheduled_task(v_tenant1, 'employee_position_activation', v_admin) then
    raise exception 'assertion failed: the tenant_admin should currently be able to configure this delegated task';
  end if;

  perform app.set_scheduled_task_delegation('employee_position_activation', false, v_supreme, 'supreme');
  if app._can_configure_tenant_scheduled_task(v_tenant1, 'employee_position_activation', v_admin) then
    raise exception 'assertion failed: revoking delegation must immediately remove the tenant_admin''s configuration right';
  end if;
  if not app._can_configure_tenant_scheduled_task(v_tenant1, 'employee_position_activation', v_supreme) then
    raise exception 'assertion failed: Supreme Admin must keep the right regardless of the delegation switch';
  end if;

  perform app.set_scheduled_task_delegation('employee_position_activation', true, v_supreme, 'supreme');
  if not app._can_configure_tenant_scheduled_task(v_tenant1, 'employee_position_activation', v_admin) then
    raise exception 'assertion failed: restoring delegation must restore the tenant_admin''s configuration right';
  end if;

  -- Fails closed on a task that does not exist, rather than defaulting to permissive.
  if app._can_configure_tenant_scheduled_task(v_tenant1, 'no_such_task_code', v_admin) then
    raise exception 'assertion failed: an unknown task_code must not be configurable by a tenant_admin';
  end if;

  raise notice 'PASS: the delegation switch is live in both directions, Supreme-Admin-only to flip, and fails closed for an unknown task';
end;
$$;

\echo '>> misconfiguration is caught at configuration time, by the person making it -- not at 03:00 on the first run: the interval floor and every required parameter are validated up front'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sched1');
  v_supreme uuid := '00000000-0000-0000-0000-000000439001';
  v_schedule app.tenant_scheduled_tasks;
begin
  begin
    perform app.configure_tenant_scheduled_task(v_tenant1, 'employee_position_activation', true, 1, '{}'::jsonb, v_supreme, 'supreme');
    raise exception 'assertion failed: expected scheduled_task_interval_too_short below the catalogue floor';
  exception when check_violation then
    if sqlerrm not like 'scheduled_task_interval_too_short%' then raise; end if;
  end;

  -- leave_accrual_batch cannot run without a leave type; the RPC says so now rather than
  -- casting a null uuid at run time.
  begin
    perform app.configure_tenant_scheduled_task(v_tenant1, 'leave_accrual_batch', true, 1440, '{}'::jsonb, v_supreme, 'supreme');
    raise exception 'assertion failed: expected scheduled_task_missing_param for a leave batch with no leave_type_id';
  exception when check_violation then
    if sqlerrm not like 'scheduled_task_missing_param%' then raise; end if;
  end;

  select * into v_schedule from app.configure_tenant_scheduled_task(
    v_tenant1, 'leave_accrual_batch', true, 1440,
    jsonb_build_object('leave_type_id', gen_random_uuid()::text), v_supreme, 'supreme');
  if v_schedule.params ->> 'leave_type_id' is null then
    raise exception 'assertion failed: the supplied parameter must be stored on the schedule';
  end if;

  begin
    perform app.configure_tenant_scheduled_task(v_tenant1, 'no_such_task_code', true, 1440, '{}'::jsonb, v_supreme, 'supreme');
    raise exception 'assertion failed: expected scheduled_task_not_available for a task outside the catalogue';
  exception when no_data_found then
    if sqlerrm not like 'scheduled_task_not_available%' then raise; end if;
  end;

  raise notice 'PASS: interval floor, required parameters and catalogue membership are all enforced at configuration time';
end;
$$;

\echo '>> the read surface shows every AVAILABLE task, not only the switched-on ones, and tells the caller per row whether THEY may change it -- so a UI can disable controls instead of letting a save fail'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sched1');
  v_admin uuid := '00000000-0000-0000-0000-000000439002';
  v_member uuid := '00000000-0000-0000-0000-000000439003';
  v_rows integer;
  v_configurable integer;
  v_not_configurable integer;
begin
  select count(*) into v_rows from app.list_tenant_scheduled_tasks(v_tenant1, v_admin);
  if v_rows <> 23 then
    raise exception 'assertion failed: expected all 23 active catalogue tasks listed, configured or not, got %', v_rows;
  end if;

  select count(*) filter (where configurable_by_actor), count(*) filter (where not configurable_by_actor)
  into v_configurable, v_not_configurable
  from app.list_tenant_scheduled_tasks(v_tenant1, v_admin);
  if v_configurable = 0 or v_not_configurable = 0 then
    raise exception 'assertion failed: the tenant_admin must see a genuine mix of rows they can and cannot change (%/%)', v_configurable, v_not_configurable;
  end if;

  -- An unconfigured task must read as off rather than as null, so the UI never renders a
  -- half-known state.
  if exists (select 1 from app.list_tenant_scheduled_tasks(v_tenant1, v_admin) where enabled is null) then
    raise exception 'assertion failed: an unconfigured task must list as disabled, never as null';
  end if;

  -- A plain member cannot read the schedule at all.
  begin
    perform app.list_tenant_scheduled_tasks(v_tenant1, v_member);
    raise exception 'assertion failed: a plain tenant member must not be able to read the tenant''s schedules';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: the read lists all 11 available tasks with a per-row configurable_by_actor flag (% changeable, % not for this admin), and is closed to a plain member', v_configurable, v_not_configurable;
end;
$$;

\echo '>> a real run: the sweep executes as the schedule''s own authorizing identity, a run row records WHO it ran as, and next_run_at advances by the configured interval'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sched1');
  v_supreme uuid := '00000000-0000-0000-0000-000000439001';
  v_schedule app.tenant_scheduled_tasks;
  v_result record;
  v_run app.scheduled_task_runs;
  v_before timestamptz;
begin
  -- Authorized by the Supreme Admin, whose authority passes every sweep's own RBAC gate.
  select * into v_schedule from app.configure_tenant_scheduled_task(
    v_tenant1, 'employee_position_activation', true, 1440, '{}'::jsonb, v_supreme, 'supreme');
  v_before := v_schedule.next_run_at;

  select * into v_result from app.run_due_scheduled_tasks(now(), 50)
  where scheduled_task_id = v_schedule.id;

  if v_result.status is null then
    raise exception 'assertion failed: the due schedule should have been picked up by app.run_due_scheduled_tasks';
  end if;
  if v_result.status <> 'succeeded' then
    raise exception 'assertion failed: expected the Supreme-Admin-authorized sweep to succeed, got % (%)', v_result.status, v_result.detail;
  end if;

  select * into v_run from app.scheduled_task_runs where scheduled_task_id = v_schedule.id order by started_at desc limit 1;
  if v_run.ran_as_auth_user_id <> v_supreme then
    raise exception 'assertion failed: the run must record the identity it actually ran as (expected %, got %)', v_supreme, v_run.ran_as_auth_user_id;
  end if;
  if v_run.status <> 'succeeded' or v_run.finished_at is null then
    raise exception 'assertion failed: the run row must be closed out with a real status and finish time';
  end if;

  select * into v_schedule from app.tenant_scheduled_tasks where id = v_schedule.id;
  if v_schedule.next_run_at <= v_before then
    raise exception 'assertion failed: next_run_at must advance after a run (was %, now %)', v_before, v_schedule.next_run_at;
  end if;
  if v_schedule.last_run_status <> 'succeeded' or v_schedule.consecutive_authority_failures <> 0 then
    raise exception 'assertion failed: a successful run must record success and leave the failure counter at zero';
  end if;

  -- Not due yet: a second immediate pass must not re-run it. This is what stops a scheduler
  -- polling every minute from running a daily sweep sixty times an hour.
  if exists (select 1 from app.run_due_scheduled_tasks(now(), 50) where scheduled_task_id = v_schedule.id) then
    raise exception 'assertion failed: a schedule that is not yet due must not run again';
  end if;

  raise notice 'PASS: the sweep ran as its authorizing identity, the run is attributable, and the schedule will not re-run until it is due';
end;
$$;

\echo '>> the governance case this whole design exists for: when the authorizing identity loses its authority the run FAILS rather than escalating or silently skipping, and three consecutive authority failures auto-disable the schedule with the reason recorded'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sched1');
  v_admin2 uuid := '00000000-0000-0000-0000-000000439004';
  v_schedule app.tenant_scheduled_tasks;
  v_result record;
  v_i integer;
begin
  -- A tenant_admin authorizes a schedule for a sweep whose own RBAC gate they do NOT satisfy
  -- (tenant_admin is a principal layer, not an HRS role grant). The configuration is legitimate
  -- -- they are allowed to schedule a delegated task -- but the sweep itself will refuse them,
  -- which is exactly the shape of "the authorizer's rights are not, or are no longer, enough".
  select * into v_schedule from app.configure_tenant_scheduled_task(
    v_tenant1, 'loyalty_expiry_sweep', true, 60, '{}'::jsonb, v_admin2, 'admin2');
  if v_schedule.authorized_by_auth_user_id <> v_admin2 then
    raise exception 'assertion failed: expected the second admin to be the authorizing identity';
  end if;

  for v_i in 1..3 loop
    update app.tenant_scheduled_tasks set next_run_at = now() - interval '1 minute' where id = v_schedule.id;
    select * into v_result from app.run_due_scheduled_tasks(now(), 50) where scheduled_task_id = v_schedule.id;
    if v_result.status is null then
      raise exception 'assertion failed: pass % should have picked up the due schedule', v_i;
    end if;
    if v_result.status <> 'unauthorized' then
      raise exception 'assertion failed: pass % expected an unauthorized outcome, got % (%)', v_i, v_result.status, v_result.detail;
    end if;
  end loop;

  select * into v_schedule from app.tenant_scheduled_tasks where id = v_schedule.id;
  if v_schedule.enabled then
    raise exception 'assertion failed: three consecutive authority failures must auto-disable the schedule';
  end if;
  if v_schedule.disabled_reason is null or v_schedule.disabled_reason not like 'auto-disabled%' then
    raise exception 'assertion failed: an auto-disabled schedule must say why, got %', coalesce(v_schedule.disabled_reason, '<null>');
  end if;
  if v_schedule.consecutive_authority_failures < 3 then
    raise exception 'assertion failed: expected the authority-failure counter to have reached 3, got %', v_schedule.consecutive_authority_failures;
  end if;

  -- Disabled means disabled: it is not picked up again.
  update app.tenant_scheduled_tasks set next_run_at = now() - interval '1 minute' where id = v_schedule.id;
  if exists (select 1 from app.run_due_scheduled_tasks(now(), 50) where scheduled_task_id = v_schedule.id) then
    raise exception 'assertion failed: an auto-disabled schedule must not keep running';
  end if;

  -- Every failed attempt is on the record, not just the last one.
  if (select count(*) from app.scheduled_task_runs where scheduled_task_id = v_schedule.id and status = 'unauthorized') < 3 then
    raise exception 'assertion failed: each unauthorized attempt must leave its own run row';
  end if;

  raise notice 'PASS: an authority failure is recorded as its own distinct outcome, three in a row auto-disable the schedule with a stated reason, and a disabled schedule stays stopped';
end;
$$;

\echo '>> re-authorizing is a real act by a real person: reconfiguring re-stamps the authorizing identity, clears the failure counter, and brings the schedule back'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sched1');
  v_supreme uuid := '00000000-0000-0000-0000-000000439001';
  v_admin2 uuid := '00000000-0000-0000-0000-000000439004';
  v_schedule app.tenant_scheduled_tasks;
  v_result record;
begin
  select * into v_schedule from app.tenant_scheduled_tasks where tenant_id = v_tenant1 and task_code = 'loyalty_expiry_sweep';
  if v_schedule.enabled then
    raise exception 'assertion failed: this block expects the auto-disabled schedule from the previous one';
  end if;

  -- Somebody with current authority takes it over. Their identity replaces the old one.
  select * into v_schedule from app.configure_tenant_scheduled_task(
    v_tenant1, 'loyalty_expiry_sweep', true, 60, '{}'::jsonb, v_supreme, 'supreme');

  if v_schedule.authorized_by_auth_user_id <> v_supreme then
    raise exception 'assertion failed: reconfiguring must re-stamp the authorizing identity (still %)', v_schedule.authorized_by_auth_user_id;
  end if;
  if v_schedule.authorized_by_auth_user_id = v_admin2 then
    raise exception 'assertion failed: the previous authorizer must not remain the identity the schedule runs as';
  end if;
  if not v_schedule.enabled or v_schedule.disabled_reason is not null or v_schedule.consecutive_authority_failures <> 0 then
    raise exception 'assertion failed: re-authorizing must re-enable the schedule and clear both the reason and the counter';
  end if;

  update app.tenant_scheduled_tasks set next_run_at = now() - interval '1 minute' where id = v_schedule.id;
  select * into v_result from app.run_due_scheduled_tasks(now(), 50) where scheduled_task_id = v_schedule.id;
  if v_result.status <> 'succeeded' then
    raise exception 'assertion failed: the re-authorized schedule should now succeed, got % (%)', v_result.status, v_result.detail;
  end if;

  raise notice 'PASS: reconfiguring transfers the schedule to the new authorizer, clears the disabled state, and the sweep runs again';
end;
$$;

\echo '>> defence in depth at the grant layer: anon holds zero EXECUTE on every new function; authenticated cannot call the runner or read the two identity-bearing tables directly; the public.* wrappers match their app.* counterparts exactly'
do $$
begin
  if has_function_privilege('anon', 'app.run_due_scheduled_tasks(timestamptz, integer)', 'EXECUTE')
     or has_function_privilege('anon', 'app.configure_tenant_scheduled_task(uuid, text, boolean, integer, jsonb, uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'app.set_scheduled_task_delegation(text, boolean, uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'app.list_tenant_scheduled_tasks(uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.configure_tenant_scheduled_task(uuid, text, boolean, integer, jsonb, uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.list_tenant_scheduled_tasks(uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.set_scheduled_task_delegation(text, boolean, uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.run_due_scheduled_tasks(timestamptz, integer)', 'EXECUTE')
  then
    raise exception 'assertion failed: anon must hold zero EXECUTE on every scheduler function (ERR-2026-004 regression guard)';
  end if;

  -- The runner acts as other identities by construction, so it is service_role-only. An
  -- authenticated caller reaching it would be an authority-laundering path.
  if has_function_privilege('authenticated', 'public.run_due_scheduled_tasks(timestamptz, integer)', 'EXECUTE') then
    raise exception 'assertion failed: authenticated must NOT be able to invoke the scheduler runner through its public wrapper either';
  end if;
  if has_function_privilege('authenticated', 'app.run_due_scheduled_tasks(timestamptz, integer)', 'EXECUTE') then
    raise exception 'assertion failed: authenticated must NOT be able to invoke the scheduler runner directly';
  end if;
  if has_function_privilege('authenticated', 'app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz)', 'EXECUTE') then
    raise exception 'assertion failed: authenticated must NOT be able to invoke the per-task dispatcher directly';
  end if;

  -- The catalogue is readable (it is a menu, not tenant data); the schedule and run tables are
  -- not, because they carry authorizing-identity columns and failure text.
  if not has_table_privilege('authenticated', 'app.scheduled_task_definitions', 'SELECT') then
    raise exception 'assertion failed: the catalogue should be readable by authenticated -- it is a menu, not tenant data';
  end if;
  if has_table_privilege('authenticated', 'app.tenant_scheduled_tasks', 'INSERT')
     or has_table_privilege('authenticated', 'app.tenant_scheduled_tasks', 'UPDATE')
     or has_table_privilege('authenticated', 'app.scheduled_task_runs', 'INSERT')
     or has_table_privilege('authenticated', 'app.scheduled_task_runs', 'UPDATE')
  then
    raise exception 'assertion failed: authenticated must never write schedules or run history directly';
  end if;

  raise notice 'PASS: anon holds nothing, authenticated cannot reach the runner or write schedule/run rows, and the catalogue stays readable';
end;
$$;


\echo '>> ISS-2026-134: a parameterised task can carry MORE THAN ONE schedule per tenant -- before this, configuring a second leave type silently OVERWROTE the first, which is the worst shape of all because nothing told anybody'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sched1');
  v_supreme uuid := '00000000-0000-0000-0000-000000439001';
  v_usd app.tenant_scheduled_tasks;
  v_idr app.tenant_scheduled_tasks;
  v_usd_again app.tenant_scheduled_tasks;
  v_count integer;
  v_parameterless_count integer;
begin
  -- Two currencies, one task. ISS-2026-134 item 1's own documented workflow is one
  -- reconciliation run PER CURRENCY, so a multi-currency tenant needs both by construction.
  v_usd := app.configure_tenant_scheduled_task(v_tenant1, 'loyalty_liability_reconciliation', true, 1440, '{"currency": "USD"}'::jsonb, v_supreme, 'supreme');
  v_idr := app.configure_tenant_scheduled_task(v_tenant1, 'loyalty_liability_reconciliation', true, 1440, '{"currency": "IDR"}'::jsonb, v_supreme, 'supreme');

  if v_usd.id = v_idr.id then
    raise exception 'assertion failed: two different currencies must be two different schedules, got the same row -- the second silently overwrote the first';
  end if;

  select count(*) into v_count from app.tenant_scheduled_tasks
  where tenant_id = v_tenant1 and task_code = 'loyalty_liability_reconciliation';
  if v_count <> 2 then
    raise exception 'assertion failed: expected 2 reconciliation schedules (USD and IDR), got %', v_count;
  end if;

  -- And the same parameter set still UPDATES in place rather than piling up duplicates --
  -- otherwise changing an interval would leave the old schedule running forever.
  v_usd_again := app.configure_tenant_scheduled_task(v_tenant1, 'loyalty_liability_reconciliation', true, 2880, '{"currency": "USD"}'::jsonb, v_supreme, 'supreme');
  if v_usd_again.id <> v_usd.id then
    raise exception 'assertion failed: the same parameter set must update the SAME schedule, got a new row';
  end if;
  if v_usd_again.interval_minutes <> 2880 then
    raise exception 'assertion failed: reconfiguring must actually change the interval, got %', v_usd_again.interval_minutes;
  end if;
  select count(*) into v_count from app.tenant_scheduled_tasks
  where tenant_id = v_tenant1 and task_code = 'loyalty_liability_reconciliation';
  if v_count <> 2 then
    raise exception 'assertion failed: reconfiguring an existing parameter set must not create a third row, got %', v_count;
  end if;

  -- A parameterless task is unaffected: params is always {} so the key is still effectively
  -- (tenant, task_code), and reconfiguring one must never fork into two.
  perform app.configure_tenant_scheduled_task(v_tenant1, 'loyalty_expiry_sweep', true, 1440, '{}'::jsonb, v_supreme, 'supreme');
  perform app.configure_tenant_scheduled_task(v_tenant1, 'loyalty_expiry_sweep', true, 2880, '{}'::jsonb, v_supreme, 'supreme');
  select count(*) into v_parameterless_count from app.tenant_scheduled_tasks
  where tenant_id = v_tenant1 and task_code = 'loyalty_expiry_sweep';
  if v_parameterless_count <> 1 then
    raise exception 'assertion failed: a parameterless task must still hold exactly one schedule per tenant, got %', v_parameterless_count;
  end if;

  -- The required parameter is still enforced -- the multi-schedule key must not become a way
  -- to smuggle in an unconfigured run that would fail at 03:00 instead.
  begin
    perform app.configure_tenant_scheduled_task(v_tenant1, 'loyalty_liability_reconciliation', true, 1440, '{}'::jsonb, v_supreme, 'supreme');
    raise exception 'assertion failed: expected scheduled_task_missing_param without a currency';
  exception
    when others then
      if sqlerrm not like 'scheduled_task_missing_param%' then raise; end if;
  end;

  raise notice 'PASS: one schedule per (tenant, task, params) -- USD and IDR coexist, the same params updates in place, and a parameterless task is unchanged';
end $$;

\echo '>> ISS-2026-134: the reconciliation task is Supreme-Admin-only and carries a real dispatch branch whose idempotency key names the currency -- two currencies on one day must be two runs, not one that silently loses the other'
do $$
declare
  v_delegable boolean;
  v_src text;
begin
  select tenant_admin_configurable into v_delegable from app.scheduled_task_definitions
  where task_code = 'loyalty_liability_reconciliation';
  if v_delegable is null then
    raise exception 'assertion failed: loyalty_liability_reconciliation is not in the catalogue';
  end if;
  if v_delegable then
    raise exception 'assertion failed: liability reconciliation produces the evidence a certification decision rests on -- it starts Supreme-Admin-only, not tenant-delegable';
  end if;

  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app' and p.proname = '_run_scheduled_task_once';
  if v_src not like '%loyalty_liability_reconciliation%' then
    raise exception 'assertion failed: the reconciliation task has no dispatch branch';
  end if;
  -- An idempotency key naming only the period would collapse USD and IDR on the same day
  -- into a single run, and one currency's liability statement would simply never exist.
  if v_src not like '%params ->> ''currency''%v_period%' then
    raise exception 'assertion failed: the reconciliation dispatch key must name the currency as well as the period';
  end if;

  raise notice 'PASS: reconciliation is catalogued Supreme-Admin-only, dispatches for real, and keys per currency and period';
end $$;

\echo '>> every catalogue task has a real dispatch branch -- a row added without one fails loudly rather than silently doing nothing on a schedule somebody trusts'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sched1');
  v_supreme uuid := '00000000-0000-0000-0000-000000439001';
  v_code text;
  v_params jsonb;
  v_schedule app.tenant_scheduled_tasks;
  v_result record;
  v_checked integer := 0;
begin
  for v_code in select task_code from app.scheduled_task_definitions where status = 'active' order by task_code loop
    v_params := '{}'::jsonb;
    if v_code like 'leave_%' then
      v_params := jsonb_build_object('leave_type_id', gen_random_uuid()::text);
    elsif v_code = 'training_certificate_expiry_reminder' then
      v_params := jsonb_build_object('lookahead_days', 30);
    elsif v_code = 'authority_denial_anomaly_sweep' then
      v_params := jsonb_build_object('window_minutes', 60, 'threshold', 10);
    elsif v_code = 'vendor_compliance_waiver_expiry' then
      v_params := jsonb_build_object('max_rows', 100);
    elsif v_code = 'vendor_compliance_status_refresh' then
      v_params := jsonb_build_object('max_vendors', 100);
    elsif v_code = 'loyalty_liability_reconciliation' then
      v_params := jsonb_build_object('currency', 'USD');
    elsif v_code = 'loyalty_engagement_metrics_snapshot' then
      -- ISS-2026-134 item 4: window_days is a REQUIRED catalogue param, so a schedule cannot be
      -- configured without one -- which is the point (a defaulted window makes two snapshots
      -- indistinguishable). Supplying it here is what lets this loop reach the dispatch branch.
      v_params := jsonb_build_object('window_days', 30);
    end if;

    select * into v_schedule from app.configure_tenant_scheduled_task(
      v_tenant1, v_code, true, (select default_interval_minutes from app.scheduled_task_definitions where task_code = v_code),
      v_params, v_supreme, 'supreme');
    update app.tenant_scheduled_tasks set next_run_at = now() - interval '1 minute' where id = v_schedule.id;

    select * into v_result from app.run_due_scheduled_tasks(now(), 100) where scheduled_task_id = v_schedule.id;
    if v_result.status is null then
      raise exception 'assertion failed: task % was due but never picked up', v_code;
    end if;
    -- A sweep may legitimately fail on this empty fixture tenant's own data (a made-up leave
    -- type has no policy, for instance). What must never happen is the dispatcher not knowing
    -- the code at all, which is a silent no-op on a schedule somebody is relying on.
    if v_result.detail is not null and v_result.detail like 'scheduled_task_not_dispatchable%' then
      raise exception 'assertion failed: catalogue task % has no dispatch branch', v_code;
    end if;
    v_checked := v_checked + 1;
  end loop;

  if v_checked <> 23 then
    raise exception 'assertion failed: expected to exercise all 23 catalogue tasks, exercised %', v_checked;
  end if;

  raise notice 'PASS: all 23 catalogue tasks reach a real dispatch branch -- none is a silent no-op';
end;
$$;

\echo '>> ISS-2026-249: the authority-denial burst detector. A single refusal produces NOTHING -- that is the false-positive flood the finding said made this producer unfixable. A burst above the threshold produces exactly ONE incident per identity, and severity rises when the refusals span several modules'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sched1');
  v_supreme uuid := '00000000-0000-0000-0000-000000439001';
  v_member uuid := '00000000-0000-0000-0000-000000439003';
  v_admin2 uuid := '00000000-0000-0000-0000-000000439004';
  v_raised integer;
  v_incidents_before integer;
  v_incidents_after integer;
  v_i integer;
  v_incident app.incidents;
begin
  select count(*) into v_incidents_before from app.incidents where tenant_id = v_tenant1 and signal_type = 'authority_denial_burst';

  -- One refusal. This is the authorization layer working, and it must alert on nothing.
  perform app.record_authority_denial(v_tenant1, v_member, 'rbac', 'FIN', 'Approve', 'insufficient_authority: identity lacks FIN:Approve');
  v_raised := app.run_authority_denial_anomaly_sweep(v_tenant1, now(), 60, 10, v_supreme, 'supreme');
  if v_raised <> 0 then
    raise exception 'assertion failed: a single refusal must raise nothing, raised %', v_raised;
  end if;

  -- A burst from ONE identity across ONE module: alerts, at the lower severity.
  for v_i in 1..12 loop
    perform app.record_authority_denial(v_tenant1, v_member, 'rbac', 'FIN', 'Approve', 'insufficient_authority: identity lacks FIN:Approve');
  end loop;
  v_raised := app.run_authority_denial_anomaly_sweep(v_tenant1, now(), 60, 10, v_supreme, 'supreme');
  if v_raised <> 1 then
    raise exception 'assertion failed: expected exactly one incident for one bursting identity, got %', v_raised;
  end if;

  select * into v_incident from app.incidents
  where tenant_id = v_tenant1 and signal_type = 'authority_denial_burst' and dedupe_discriminator = v_member::text
  order by opened_at desc limit 1;
  if v_incident.id is null then
    raise exception 'assertion failed: the incident must be deduplicated on the bursting identity, not on the tenant';
  end if;
  if v_incident.severity <> 'medium' then
    raise exception 'assertion failed: a burst inside a single module should be medium (a role that needs granting), got %', v_incident.severity;
  end if;

  -- A SECOND identity bursting at the same time must get its own incident, not be swallowed by
  -- the first one's dedupe window -- and spanning several modules reads as probing, so it is high.
  for v_i in 1..12 loop
    perform app.record_authority_denial(v_tenant1, v_admin2, 'rbac', 'MOD' || (v_i % 4)::text, 'Edit', 'insufficient_authority');
  end loop;
  v_raised := app.run_authority_denial_anomaly_sweep(v_tenant1, now(), 60, 10, v_supreme, 'supreme');
  if v_raised <> 2 then
    raise exception 'assertion failed: two bursting identities must produce two incidents, got %', v_raised;
  end if;

  select * into v_incident from app.incidents
  where tenant_id = v_tenant1 and signal_type = 'authority_denial_burst' and dedupe_discriminator = v_admin2::text
  order by opened_at desc limit 1;
  if v_incident.severity <> 'high' then
    raise exception 'assertion failed: refusals spanning more than two modules should escalate to high, got %', v_incident.severity;
  end if;

  select count(*) into v_incidents_after from app.incidents where tenant_id = v_tenant1 and signal_type = 'authority_denial_burst';
  if v_incidents_after - v_incidents_before <> 2 then
    raise exception 'assertion failed: repeated sweeps must not open a new incident per pass -- expected 2 distinct incidents, got %', v_incidents_after - v_incidents_before;
  end if;

  -- Outside the window, nothing is in scope any more.
  v_raised := app.run_authority_denial_anomaly_sweep(v_tenant1, now() - interval '2 days', 60, 10, v_supreme, 'supreme');
  if v_raised <> 0 then
    raise exception 'assertion failed: a window containing no denials must raise nothing, raised %', v_raised;
  end if;

  raise notice 'PASS: ISS-2026-249 -- one refusal alerts on nothing, a burst alerts once per identity, breadth escalates severity, and repeated sweeps do not reopen an incident';
end;
$$;

\echo '>> ISS-2026-249: a step-up refusal is recorded through the SAME path, because app.evaluate_permission returns mfa_step_up_required as a reason rather than raising -- and the recorder refuses an unknown tenant so a bug cannot fill the table with orphans'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sched1');
  v_member uuid := '00000000-0000-0000-0000-000000439003';
  v_denial app.authority_denials;
begin
  select * into v_denial from app.record_authority_denial(
    v_tenant1, v_member, 'step_up', 'FIN', 'Approve', 'insufficient_authority: … (mfa_step_up_required) …');
  if v_denial.denial_kind <> 'step_up' then
    raise exception 'assertion failed: a step-up refusal must be recorded as its own kind, got %', v_denial.denial_kind;
  end if;

  begin
    perform app.record_authority_denial(gen_random_uuid(), v_member, 'rbac', null, null, null);
    raise exception 'assertion failed: expected tenant_not_found for a denial against a nonexistent tenant';
  exception when no_data_found then
    if sqlerrm not like 'tenant_not_found%' then raise; end if;
  end;

  raise notice 'PASS: step-up refusals flow through the same recorder, and an unknown tenant is refused';
end;
$$;

\echo '>> defence in depth on the denial ledger: it is service_role-only to write, readable only through RLS by a tenant admin, and anon holds nothing'
do $$
begin
  if has_table_privilege('authenticated', 'app.authority_denials', 'INSERT')
     or has_table_privilege('authenticated', 'app.authority_denials', 'UPDATE')
     or has_table_privilege('authenticated', 'app.authority_denials', 'DELETE')
  then
    raise exception 'assertion failed: authenticated must never write or delete authority-denial evidence';
  end if;
  if has_function_privilege('anon', 'app.record_authority_denial(uuid, uuid, text, text, text, text, text, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'app.record_authority_denial(uuid, uuid, text, text, text, text, text, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.record_authority_denial(uuid, uuid, text, text, text, text, text, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'app.run_authority_denial_anomaly_sweep(uuid, timestamp with time zone, integer, integer, uuid, text)', 'EXECUTE')
  then
    raise exception 'assertion failed: the denial recorder is service_role-only and anon must hold nothing on either function';
  end if;
  if (select count(*) from pg_policies where schemaname = 'app' and tablename = 'authority_denials') <> 1 then
    raise exception 'assertion failed: expected exactly one RLS policy on app.authority_denials';
  end if;

  raise notice 'PASS: the denial ledger is service_role-write, RLS-read, and closed to anon';
end;
$$;

\echo 'ALL task-scheduler assertions passed.'
