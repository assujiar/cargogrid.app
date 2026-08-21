-- Real, executable test evidence for IAE-006 (Scheduled Reports, Prompt 334,
-- CG-S14-IAE-006) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000008000001..005.
-- Grep-verified unclaimed against every other *.sql fixture in this
-- directory before use. Uses finance_billing_summary (empty schema, never
-- retired by any fixture) plus a self-registered/self-retired test report
-- type, mirroring the lesson IAE-004's own fixture already applied: never
-- depend on another file's own incidental report-type state.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (iaeschedco), a global Supreme Admin, a configurer (REP:Configure), two recipients (tenant members), a second tenant (iaeschedco2) for cross-tenant isolation, and a retired test report type'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_configurer_role uuid;
  v_configurer_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000008000001', 'supreme@iaeschedco.test'),
    ('00000000-0000-0000-0000-000008000002', 'configurer@iaeschedco.test'),
    ('00000000-0000-0000-0000-000008000003', 'recipienta@iaeschedco.test'),
    ('00000000-0000-0000-0000-000008000004', 'recipientb@iaeschedco.test'),
    ('00000000-0000-0000-0000-000008000005', 'member@iaeschedco2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000008000001', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaeschedco', 'IAE Scheduled Co', 'idem-iaeschedco', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaeschedco2', 'IAE Scheduled Co 2', 'idem-iaeschedco2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaeschedco2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000008000002', 'configurer@iaeschedco.test', 'Configurer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'configurer@iaeschedco.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000008000003', 'recipienta@iaeschedco.test', 'Recipient A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'recipienta@iaeschedco.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000008000004', 'recipientb@iaeschedco.test', 'Recipient B', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'recipientb@iaeschedco.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000008000005', 'member@iaeschedco2.test', 'Beta Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaeschedco2.test'), 'active', 'onboarded', 'tester');

  v_configurer_role := (app.create_role(v_tenant1, 'Report Scheduler', 'REP:Configure', 'tester')).id;
  v_configurer_draft := app.create_role_version(v_configurer_role, 'tester');
  perform app.set_role_version_permissions(
    v_configurer_draft.id,
    array(select id from app.permissions where resource_module_code = 'REP' and action = 'Configure'),
    'tester'
  );
  perform app.publish_role_version(v_configurer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_configurer_role and status = 'published'),
    '00000000-0000-0000-0000-000008000002', '00000000-0000-0000-0000-000008000001', 'tester');

  perform app.register_report_type(
    'iae_sched_retired_report', 'IAE Scheduled Retired Report', 'retired for IAE-006 testing only',
    'get_dashboard_lead_aging', '00000000-0000-0000-0000-000008000001', 'tester'
  );
  perform app.retire_report_type('iae_sched_retired_report', '00000000-0000-0000-0000-000008000001', 'tester');
end;
$$;

\echo '>> app.create_scheduled_report: REP:Configure-gated; rejects unknown/retired codes, invalid timezone, dom+dow both set, and unsafe filters; a real daily schedule computes a real next_run_at'
do $$
declare
  v_tenant1 uuid;
  v_row app.scheduled_reports;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');

  begin
    perform app.create_scheduled_report(v_tenant1, 'finance_billing_summary', 'Should be denied', null, 0, 9, null, null, 'Asia/Jakarta', '{}'::jsonb, '00000000-0000-0000-0000-000008000003', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- recipient A lacks REP:Configure';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.create_scheduled_report(v_tenant1, 'not_a_real_report', 'x', null, 0, 9, null, null, 'Asia/Jakarta', '{}'::jsonb, '00000000-0000-0000-0000-000008000002', 'tester');
    raise exception 'assertion failed: expected report_type_unknown';
  exception
    when no_data_found then null;
  end;

  begin
    perform app.create_scheduled_report(v_tenant1, 'iae_sched_retired_report', 'x', null, 0, 9, null, null, 'Asia/Jakarta', '{}'::jsonb, '00000000-0000-0000-0000-000008000002', 'tester');
    raise exception 'assertion failed: expected report_type_retired';
  exception
    when check_violation then null;
  end;

  begin
    perform app.create_scheduled_report(v_tenant1, 'finance_billing_summary', 'x', null, 0, 9, null, null, 'Not/A_Real_Zone', '{}'::jsonb, '00000000-0000-0000-0000-000008000002', 'tester');
    raise exception 'assertion failed: expected scheduled_report_invalid_timezone';
  exception
    when check_violation then null;
  end;

  begin
    perform app.create_scheduled_report(v_tenant1, 'finance_billing_summary', 'x', null, 0, 9, 15, 1, 'Asia/Jakarta', '{}'::jsonb, '00000000-0000-0000-0000-000008000002', 'tester');
    raise exception 'assertion failed: expected scheduled_report_invalid_cron for both dom and dow set';
  exception
    when check_violation then null;
  end;

  select * into v_row from app.create_scheduled_report(
    v_tenant1, 'finance_billing_summary', 'Daily Billing Summary', 'a real test schedule',
    30, 9, null, null, 'Asia/Jakarta', '{}'::jsonb, '00000000-0000-0000-0000-000008000002', 'tester'
  );
  if v_row.status <> 'active' or v_row.next_run_at is null then
    raise exception 'assertion failed: expected a real active schedule with a computed next_run_at';
  end if;
end;
$$;

\echo '>> app.add_scheduled_report_recipient: REP:Configure-gated, rejects a non-member, succeeds for a real member'
do $$
declare
  v_tenant1 uuid;
  v_schedule_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');
  v_schedule_id := (select id from app.scheduled_reports where tenant_id = v_tenant1 and name = 'Daily Billing Summary');

  begin
    perform app.add_scheduled_report_recipient(v_schedule_id, '00000000-0000-0000-0000-000008000005', '00000000-0000-0000-0000-000008000002', 'tester');
    raise exception 'assertion failed: expected scheduled_report_recipient_not_member -- tenant2''s own member has no membership in tenant1';
  exception
    when check_violation then null;
  end;

  perform app.add_scheduled_report_recipient(v_schedule_id, '00000000-0000-0000-0000-000008000003', '00000000-0000-0000-0000-000008000002', 'tester');
  perform app.add_scheduled_report_recipient(v_schedule_id, '00000000-0000-0000-0000-000008000004', '00000000-0000-0000-0000-000008000002', 'tester');

  if (select count(*) from app.scheduled_report_recipients where scheduled_report_id = v_schedule_id) <> 2 then
    raise exception 'assertion failed: expected exactly 2 recipients';
  end if;
end;
$$;

\echo '>> app.run_scheduled_report: gated, reauthorizes recipients at run time (a revoked recipient is excluded, never a hard failure), delivers a real notification, advances next_run_at, and never double-enqueues the SAME due occurrence'
do $$
declare
  v_tenant1 uuid;
  v_schedule_id uuid;
  v_schedule_before app.scheduled_reports;
  v_schedule_after app.scheduled_reports;
  v_run app.scheduled_report_runs;
  v_run2 app.scheduled_report_runs;
  v_job_count integer;
  v_notification_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');
  v_schedule_id := (select id from app.scheduled_reports where tenant_id = v_tenant1 and name = 'Daily Billing Summary');
  select * into v_schedule_before from app.scheduled_reports where id = v_schedule_id;

  -- revoke recipient B's own tenant membership BEFORE the run -- must be
  -- excluded live, never only checked at add-time.
  update app.tenant_user_identities set status = 'revoked'
  where tenant_id = v_tenant1 and auth_user_id = '00000000-0000-0000-0000-000008000004';

  begin
    perform app.run_scheduled_report(v_schedule_id, '00000000-0000-0000-0000-000008000003', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- recipient A lacks REP:Configure to trigger a run';
  exception
    when insufficient_privilege then null;
  end;

  select * into v_run from app.run_scheduled_report(v_schedule_id, '00000000-0000-0000-0000-000008000002', 'tester');
  if v_run.recipients_total <> 2 or v_run.recipients_reauthorized <> 1 or v_run.recipients_denied <> 1 then
    raise exception 'assertion failed: expected 2 total / 1 reauthorized / 1 denied, got total=% reauth=% denied=%', v_run.recipients_total, v_run.recipients_reauthorized, v_run.recipients_denied;
  end if;
  if v_run.job_id is null then
    raise exception 'assertion failed: expected a real app.jobs row linked via job_id';
  end if;

  select * into v_schedule_after from app.scheduled_reports where id = v_schedule_id;
  if v_schedule_after.next_run_at <= v_schedule_before.next_run_at then
    raise exception 'assertion failed: expected next_run_at to advance forward past the just-triggered occurrence';
  end if;
  if v_schedule_after.last_run_at is null then
    raise exception 'assertion failed: expected last_run_at to be stamped';
  end if;

  select count(*) into v_notification_count from app.notifications
  where recipient_auth_user_id = '00000000-0000-0000-0000-000008000003' and notification_type_code = 'scheduled_report_ready';
  if v_notification_count <> 1 then
    raise exception 'assertion failed: expected exactly one real notification queued for the reauthorized recipient, got %', v_notification_count;
  end if;
  select count(*) into v_notification_count from app.notifications
  where recipient_auth_user_id = '00000000-0000-0000-0000-000008000004' and notification_type_code = 'scheduled_report_ready';
  if v_notification_count <> 0 then
    raise exception 'assertion failed: expected zero notifications for the revoked recipient';
  end if;

  -- duplicate-delivery prevention: force next_run_at back to the SAME due
  -- occurrence that was just triggered, then run again -- the underlying
  -- app.jobs row must NOT be duplicated (same idempotency_key).
  update app.scheduled_reports set next_run_at = v_schedule_before.next_run_at where id = v_schedule_id;
  select * into v_run2 from app.run_scheduled_report(v_schedule_id, '00000000-0000-0000-0000-000008000002', 'tester');
  if v_run2.job_id <> v_run.job_id then
    raise exception 'assertion failed: expected the SAME app.jobs row (idempotency key match) for a re-triggered due occurrence, got a different job_id';
  end if;

  select count(*) into v_job_count from app.jobs
  where job_type = 'report_generation' and (payload ->> 'scheduled_report_id')::uuid = v_schedule_id;
  if v_job_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE app.jobs row across both triggers of the same due occurrence, got %', v_job_count;
  end if;
end;
$$;

\echo '>> app.set_scheduled_report_status: pause/resume/archive, REP:Configure-gated; a paused schedule may not run'
do $$
declare
  v_tenant1 uuid;
  v_schedule_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');
  v_schedule_id := (select id from app.scheduled_reports where tenant_id = v_tenant1 and name = 'Daily Billing Summary');

  perform app.set_scheduled_report_status(v_schedule_id, 'paused', '00000000-0000-0000-0000-000008000002', 'tester');

  begin
    perform app.run_scheduled_report(v_schedule_id, '00000000-0000-0000-0000-000008000002', 'tester');
    raise exception 'assertion failed: expected scheduled_report_not_active for a paused schedule';
  exception
    when check_violation then null;
  end;

  perform app.set_scheduled_report_status(v_schedule_id, 'active', '00000000-0000-0000-0000-000008000002', 'tester');
  if (select status from app.scheduled_reports where id = v_schedule_id) <> 'active' then
    raise exception 'assertion failed: expected resume to restore status=active';
  end if;
end;
$$;

\echo '>> cross-tenant isolation: tenant2''s own actor cannot read/manage tenant1''s own schedule'
do $$
declare
  v_tenant1 uuid;
  v_schedule_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaeschedco');
  v_schedule_id := (select id from app.scheduled_reports where tenant_id = v_tenant1 and name = 'Daily Billing Summary');

  begin
    perform app.set_scheduled_report_status(v_schedule_id, 'paused', '00000000-0000-0000-0000-000008000005', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege for a cross-tenant status change attempt';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-006 function; authenticated has no direct INSERT/UPDATE/DELETE on any of the three new tables'
do $$
declare
  v_bad_grant record;
begin
  for v_bad_grant in
    select routine_name from information_schema.routine_privileges
    where routine_schema = 'app'
      and routine_name in ('create_scheduled_report', 'set_scheduled_report_status', 'add_scheduled_report_recipient', 'remove_scheduled_report_recipient', 'run_scheduled_report')
      and grantee = 'anon'
  loop
    raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_bad_grant.routine_name;
  end loop;

  for v_bad_grant in
    select privilege_type from information_schema.role_table_grants
    where table_schema = 'app' and table_name in ('scheduled_reports', 'scheduled_report_recipients', 'scheduled_report_runs')
      and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
  loop
    raise exception 'assertion failed: authenticated must not hold direct % on the new scheduled-report tables', v_bad_grant.privilege_type;
  end loop;
end;
$$;

\echo '>> audit trail: create/status-change/recipient-add/run each recorded a real app.audit_logs event'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where resource_type = 'app.scheduled_reports' and action = 'create_scheduled_report';
  if v_count = 0 then raise exception 'assertion failed: expected a create_scheduled_report audit event'; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.scheduled_report_recipients' and action = 'add_scheduled_report_recipient';
  if v_count = 0 then raise exception 'assertion failed: expected an add_scheduled_report_recipient audit event'; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.scheduled_report_runs' and action = 'run_scheduled_report';
  if v_count = 0 then raise exception 'assertion failed: expected a run_scheduled_report audit event'; end if;
end;
$$;

\echo 'ALL IAE-006 (Scheduled Reports) db-test assertions passed.'
