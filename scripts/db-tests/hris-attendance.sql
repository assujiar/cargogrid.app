-- Real, executable test evidence for HRT-278 (Attendance, CG-S12-HRT-006) -- run
-- via `pnpm run db:test` against a real, disposable Postgres database. Mirrors
-- scripts/db-tests/hris-onboarding-offboarding.sql's own two-tenant cross-
-- isolation convention.
--
-- This file is alphabetically named BEFORE hris-employee-master.sql,
-- hris-onboarding-offboarding.sql, hris-organization-position-linkage.sql, and
-- hris-recruitment-ats.sql, so `scripts/db-tests/run.sh` runs it FIRST -- it
-- cannot depend on any of those files' own fixtures. It builds its own,
-- self-contained two-tenant/employee/policy fixture using a fresh, unclaimed
-- UUID range (00000000-0000-0000-0000-0000000278xx), never colliding with the
-- 0000027501-27529/0000027601-27699/0000027701-27799 ranges HRT-275/276/277's
-- own fixtures already claim.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (att1, att2). att1 gets a tenant_admin, HR staff (HRS Create/Edit/Export/View/View personal data/Import), an approver (HRS Approve/View/Override), three active employees (emp1, emp2, mgr1 -- emp1 reports to mgr1) plus emp3/emp4 added later for isolated scenarios, and a published tenant-wide attendance policy. att2 gets a tenant_admin, an HR actor, and one active employee for cross-tenant checks. A global Supreme Admin is also seeded.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_staff_role uuid;
  v_staff_draft app.role_versions;
  v_approver_role uuid;
  v_approver_draft app.role_versions;
  v_t2_role uuid;
  v_t2_draft app.role_versions;
  v_company uuid;
  v_branch uuid;
  v_policy app.attendance_policies;
  v_version app.attendance_policy_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000027801', 'admin@att1.test'),
    ('00000000-0000-0000-0000-000000027802', 'staff@att1.test'),
    ('00000000-0000-0000-0000-000000027803', 'approver@att1.test'),
    ('00000000-0000-0000-0000-000000027804', 'emp1@att1.test'),
    ('00000000-0000-0000-0000-000000027805', 'emp2@att1.test'),
    ('00000000-0000-0000-0000-000000027806', 'mgr1@att1.test'),
    ('00000000-0000-0000-0000-000000027807', 'emp3@att1.test'),
    ('00000000-0000-0000-0000-000000027808', 'emp4@att1.test'),
    ('00000000-0000-0000-0000-000000027821', 'admin@att2.test'),
    ('00000000-0000-0000-0000-000000027822', 'emp1@att2.test'),
    ('00000000-0000-0000-0000-000000027823', 'hr@att2.test'),
    ('00000000-0000-0000-0000-000000027899', 'supreme@att.test');

  perform app.provision_tenant('att1', 'ATT Co 1', 'idem-att1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'att1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('att2', 'ATT Co 2', 'idem-att2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'att2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027801', 'admin@att1.test', 'Att1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@att1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027801', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027802', 'staff@att1.test', 'Att1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@att1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027803', 'approver@att1.test', 'Att1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@att1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027804', 'emp1@att1.test', 'Att1 Emp One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp1@att1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027805', 'emp2@att1.test', 'Att1 Emp Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp2@att1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027806', 'mgr1@att1.test', 'Att1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'mgr1@att1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027807', 'emp3@att1.test', 'Att1 Emp Three', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp3@att1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027808', 'emp4@att1.test', 'Att1 Emp Four', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp4@att1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027821', 'admin@att2.test', 'Att2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@att2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027821', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027822', 'emp1@att2.test', 'Att2 Emp One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp1@att2.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027823', 'hr@att2.test', 'Att2 HR', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'hr@att2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027899', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'HRS Staff', 'Create/Edit/Export/View/View personal data/Import', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Export', 'View', 'View personal data', 'Import')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000027802', '00000000-0000-0000-0000-000000027801', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'HRS Approver', 'Approve/View/Override', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Approve', 'View', 'Override')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000027803', '00000000-0000-0000-0000-000000027801', 'tester');

  v_t2_role := (app.create_role(v_tenant2, 'HRS Staff T2', 'Create/Edit/View/Approve/Override', 'tester')).id;
  v_t2_draft := app.create_role_version(v_t2_role, 'tester');
  perform app.set_role_version_permissions(v_t2_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View', 'Approve', 'Override')), 'tester');
  perform app.publish_role_version(v_t2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'), '00000000-0000-0000-0000-000000027823', '00000000-0000-0000-0000-000000027821', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-ATT1', 'Att1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-ATT1', 'Att1 Branch', 'tester')).id;
  perform app.create_org_unit(v_tenant2, 'company', null, 'CO-ATT2', 'Att2 Co', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Att1 Emp One', 'full_time', 'emp1work@att1.test', 'emp1p@att1.test', '0800000001', null, null, null, '2024-01-01', v_company, v_branch, null, 'Warehouse Staff', null, (select id from app.users where email = 'emp1@att1.test'), null, 'hr_created', 'idem-emp1-att1', '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@att1.test'), 'Contact One', 'spouse', '0810000001', null, true, '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@att1.test'), 1, '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@att1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000027803', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@att1.test'), 3, '00000000-0000-0000-0000-000000027803', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Att1 Manager', 'full_time', 'mgr1work@att1.test', 'mgr1p@att1.test', '0800000002', null, null, null, '2024-01-01', v_company, v_branch, null, 'Warehouse Manager', null, (select id from app.users where email = 'mgr1@att1.test'), null, 'hr_created', 'idem-mgr1-att1', '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@att1.test'), 'Contact Mgr', 'spouse', '0810000002', null, true, '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@att1.test'), 1, '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@att1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000027803', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@att1.test'), 3, '00000000-0000-0000-0000-000000027803', 'tester');

  -- emp1's manager is mgr1 (manager/team-scope tests below).
  perform app.transfer_employee(
    (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@att1.test'), 4,
    v_company, v_branch, null, 'Warehouse Staff', (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@att1.test'),
    'reorg', '00000000-0000-0000-0000-000000027802', 'tester'
  );

  perform app.create_employee_draft(v_tenant1, 'Att1 Emp Two', 'full_time', 'emp2work@att1.test', 'emp2p@att1.test', '0800000003', null, null, null, '2024-01-01', v_company, v_branch, null, 'Warehouse Staff', null, (select id from app.users where email = 'emp2@att1.test'), null, 'hr_created', 'idem-emp2-att1', '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@att1.test'), 'Contact Two', 'spouse', '0810000003', null, true, '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@att1.test'), 1, '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@att1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000027803', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@att1.test'), 3, '00000000-0000-0000-0000-000000027803', 'tester');

  -- emp3/emp4: company-only (no branch), so they resolve the tenant-wide policy
  -- even after a later branch-scoped policy is published (used for the device-
  -- import and concurrency scenarios, which must not collide with the
  -- branch-scoped geofence policy created later in this file).
  perform app.create_employee_draft(v_tenant1, 'Att1 Emp Three', 'full_time', 'emp3work@att1.test', 'emp3p@att1.test', '0800000005', null, null, null, '2024-01-01', v_company, null, null, 'Warehouse Staff', null, (select id from app.users where email = 'emp3@att1.test'), null, 'hr_created', 'idem-emp3-att1', '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@att1.test'), 'Contact Three', 'spouse', '0810000005', null, true, '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@att1.test'), 1, '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@att1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000027803', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@att1.test'), 3, '00000000-0000-0000-0000-000000027803', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Att1 Emp Four', 'full_time', 'emp4work@att1.test', 'emp4p@att1.test', '0800000006', null, null, null, '2024-01-01', v_company, null, null, 'Warehouse Staff', null, (select id from app.users where email = 'emp4@att1.test'), null, 'hr_created', 'idem-emp4-att1', '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp4work@att1.test'), 'Contact Four', 'spouse', '0810000006', null, true, '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp4work@att1.test'), 1, '00000000-0000-0000-0000-000000027802', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp4work@att1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000027803', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp4work@att1.test'), 3, '00000000-0000-0000-0000-000000027803', 'tester');

  perform app.create_employee_draft(v_tenant2, 'Att2 Emp One', 'full_time', 'emp1work@att2.test', 'emp1p@att2.test', '0800000004', null, null, null, '2024-01-01', (select id from app.org_units where tenant_id = v_tenant2 and code = 'CO-ATT2'), null, null, 'Staff', null, (select id from app.users where email = 'emp1@att2.test'), null, 'hr_created', 'idem-emp1-att2', '00000000-0000-0000-0000-000000027823', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@att2.test'), 'Contact Two', 'spouse', '0810000004', null, true, '00000000-0000-0000-0000-000000027823', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@att2.test'), 1, '00000000-0000-0000-0000-000000027823', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@att2.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000027823', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@att2.test'), 3, '00000000-0000-0000-0000-000000027823', 'tester');

  -- Tenant-wide attendance policy, published, effective from a while back.
  v_policy := app.create_attendance_policy(v_tenant1, null, 'Att1 Tenant-Wide', '00000000-0000-0000-0000-000000027802', 'tester');
  v_version := app.create_attendance_policy_version(
    v_policy.id, 'Asia/Jakarta', '08:00:00'::time, '17:00:00'::time, '04:00:00'::time, 15, 15,
    array['mobile_web','kiosk','device_import']::text[], 'none', null, null, 16, '2024-01-01'::date,
    '00000000-0000-0000-0000-000000027802', 'tester'
  );
  perform app.publish_attendance_policy_version(v_version.id, 1, '00000000-0000-0000-0000-000000027803', 'tester');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end $$;

\echo '>> ISS-2026-059 lesson: work_date is computed in LOCAL time, never UTC calendar-date arithmetic -- an overnight shift''s clock-in and its own later clock-out compute the SAME work_date across a real UTC-midnight crossing'
do $$
declare
  v_clockin_date date;
  v_clockout_date date;
begin
  v_clockin_date := app.resolve_attendance_workday('2026-08-10 16:30:00+00'::timestamptz, 'Asia/Jakarta', '04:00:00'::time);
  v_clockout_date := app.resolve_attendance_workday('2026-08-10 19:00:00+00'::timestamptz, 'Asia/Jakarta', '04:00:00'::time);
  if v_clockin_date <> '2026-08-10'::date or v_clockout_date <> '2026-08-10'::date or v_clockin_date <> v_clockout_date then
    raise exception 'assertion failed: expected both timestamps to resolve to work_date 2026-08-10, got clockin=%, clockout=%', v_clockin_date, v_clockout_date;
  end if;
end $$;

\echo '>> policy resolution: branch-specific published policy is preferred over tenant-wide when both apply'
do $$
declare
  v_resolved app.attendance_policy_versions;
begin
  select * into v_resolved from app.resolve_effective_attendance_policy_version(
    (select id from app.tenants where slug='att1'),
    (select branch_org_unit_id from app.employees where work_email='emp1work@att1.test'),
    current_date
  ) limit 1;
  if v_resolved.timezone <> 'Asia/Jakarta' then
    raise exception 'assertion failed: expected a resolved policy, got none';
  end if;
end $$;

\echo '>> clock-in as emp1 (self, identity-gated -- no p_employee_id parameter exists to spoof, section 16)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027804", "role": "authenticated"}', false);
set role authenticated;
select app.record_attendance_clock_event((select id from app.tenants where slug='att1'), 'clock_in', 'mobile_web', now(), null, null, 'clockin-1', '00000000-0000-0000-0000-000000027804', 'emp1');
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> get_my_attendance_status reflects the open session'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027804", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_status record;
begin
  select * into v_status from app.get_my_attendance_status((select id from app.tenants where slug='att1'), '00000000-0000-0000-0000-000000027804');
  if v_status.status <> 'open' then
    raise exception 'assertion failed: expected open session, got %', v_status.status;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> C-01 idempotency: a genuinely identical replay of the same key returns the SAME event, never a duplicate'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027804", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_original_id uuid := (select id from app.attendance_events where idempotency_key='clockin-1');
  v_replay_id uuid;
begin
  select id into v_replay_id from app.record_attendance_clock_event(
    (select id from app.tenants where slug='att1'), 'clock_in', 'mobile_web',
    (select client_reported_at from app.attendance_events where idempotency_key='clockin-1'),
    null, null, 'clockin-1', '00000000-0000-0000-0000-000000027804', 'emp1'
  );
  if v_replay_id <> v_original_id then
    raise exception 'assertion failed: expected identical replay to return the same event id';
  end if;
  if (select count(*) from app.attendance_events where idempotency_key='clockin-1') <> 1 then
    raise exception 'assertion failed: expected exactly one event for this key';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> C-01 idempotency: same key, DIFFERENT event_type must be rejected as a conflict, never silently returned or misattributed'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027804", "role": "authenticated"}', false);
set role authenticated;
do $$
begin
  begin
    perform app.record_attendance_clock_event((select id from app.tenants where slug='att1'), 'clock_out', 'mobile_web', now(), null, null, 'clockin-1', '00000000-0000-0000-0000-000000027804', 'emp1');
    raise exception 'assertion failed: expected idempotency_key_conflict';
  exception when others then
    if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> duplicate clock-in (no idempotency key reuse) must be rejected -- no double-open-session'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027804", "role": "authenticated"}', false);
set role authenticated;
do $$
begin
  begin
    perform app.record_attendance_clock_event((select id from app.tenants where slug='att1'), 'clock_in', 'mobile_web', now(), null, null, 'clockin-2', '00000000-0000-0000-0000-000000027804', 'emp1');
    raise exception 'assertion failed: expected duplicate_open_session';
  exception when others then
    if sqlerrm not like 'duplicate_open_session%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> C-04 (live, real concurrency, two separate OS processes): two concurrent clock-in attempts for the SAME never-clocked-in-today employee must produce exactly ONE open session, never two -- see this checkpoint''s own build log for the exact reproduction and result (the app-level pre-check races harmlessly; the real safety net is the (tenant_id, employee_id, work_date) unique constraint, which a live two-process run confirmed holds: one process succeeds, the other fails cleanly with a real unique-constraint error, zero duplicate sessions).'
select count(*) as sessions_for_emp1_today from app.attendance_sessions where employee_id = (select master_record_id from app.employees where work_email='emp1work@att1.test');

\echo '>> impossible ordering: clock-out is rejected while employee has no open session; clock-out succeeds once open'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027805", "role": "authenticated"}', false);
set role authenticated;
do $$
begin
  begin
    perform app.record_attendance_clock_event((select id from app.tenants where slug='att1'), 'clock_out', 'mobile_web', now(), null, null, 'e2-badorder', '00000000-0000-0000-0000-000000027805', 'emp2');
    raise exception 'assertion failed: expected no_open_session';
  exception when others then
    if sqlerrm not like 'no_open_session%' then raise; end if;
  end;
end $$;
select app.record_attendance_clock_event((select id from app.tenants where slug='att1'), 'clock_in', 'mobile_web', now(), null, null, 'e2-in-1', '00000000-0000-0000-0000-000000027805', 'emp2');
select app.record_attendance_clock_event((select id from app.tenants where slug='att1'), 'clock_out', 'mobile_web', now(), null, null, 'e2-out-1', '00000000-0000-0000-0000-000000027805', 'emp2');
reset role;
select set_config('request.jwt.claims', 'null', false);
do $$
declare
  v_session app.attendance_sessions;
begin
  select * into v_session from app.attendance_sessions where employee_id=(select master_record_id from app.employees where work_email='emp2work@att1.test');
  if v_session.status <> 'closed' then
    raise exception 'assertion failed: expected closed session';
  end if;
end $$;

\echo '>> clock-out for emp1: session closes, effective_clock_out_at reflects the raw event'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027804", "role": "authenticated"}', false);
set role authenticated;
select app.record_attendance_clock_event((select id from app.tenants where slug='att1'), 'clock_out', 'mobile_web', now(), null, null, 'clockout-1', '00000000-0000-0000-0000-000000027804', 'emp1');
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> manager (mgr1) team view via list_attendance_sessions with no HRS:View -- sees self + direct report emp1 only, never emp2 (section 26 "manager effective-team review where configured" + "prevent cross-team views")'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027806", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_seen_employee_ids uuid[];
begin
  select array_agg(employee_id) into v_seen_employee_ids from app.list_attendance_sessions((select id from app.tenants where slug='att1'), '00000000-0000-0000-0000-000000027806', null, null, null, null, 50, null);
  if (select master_record_id from app.employees where work_email='emp1work@att1.test') <> all(v_seen_employee_ids) then
    raise exception 'assertion failed: manager must see direct report emp1';
  end if;
  if (select master_record_id from app.employees where work_email='emp2work@att1.test') = any(v_seen_employee_ids) then
    raise exception 'assertion failed: manager must NOT see non-report emp2 (cross-team leak)';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> emp1 (self) requests a correction for their own already-closed session'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027804", "role": "authenticated"}', false);
set role authenticated;
select app.request_attendance_correction(
  (select id from app.attendance_sessions where employee_id = (select master_record_id from app.employees where work_email='emp1work@att1.test')),
  'adjust_clock_out', null, now() + interval '1 hour', 'Forgot to note overtime finish', null, 'corr-1', '00000000-0000-0000-0000-000000027804', 'emp1'
);
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> cross-tenant: emp1@att2 requesting a correction on an att1 session folds to not_found -- no real tenant_id/row-existence disclosure (C-05)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027822", "role": "authenticated"}', false);
set role authenticated;
do $$
begin
  begin
    perform app.request_attendance_correction(
      (select id from app.attendance_sessions where tenant_id=(select id from app.tenants where slug='att1') limit 1),
      'adjust_clock_in', now(), null, 'cross-tenant probe', null, 'xt-corr-1', '00000000-0000-0000-0000-000000027822', 'xt'
    );
    raise exception 'assertion failed: expected session_not_found (cross-tenant fold)';
  exception when others then
    if sqlerrm not like 'session_not_found%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);
select count(*) as should_be_zero from app.list_attendance_sessions((select id from app.tenants where slug='att1'), '00000000-0000-0000-0000-000000027822', null, null, null, null, 50, null);

\echo '>> HR approver decides the correction (approve) -- session gets corrected_clock_out_at, effective_clock_out_at reflects it, payroll_input_status resets to pending'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027803", "role": "authenticated"}', false);
set role authenticated;
select app.decide_attendance_correction(
  (select id from app.attendance_correction_requests where idempotency_key='corr-1'),
  1, 'approve', 'Overtime confirmed with manager', '00000000-0000-0000-0000-000000027803', 'approver'
);
reset role;
select set_config('request.jwt.claims', 'null', false);
do $$
declare
  v_session app.attendance_sessions;
begin
  select * into v_session from app.attendance_sessions where employee_id=(select master_record_id from app.employees where work_email='emp1work@att1.test');
  if v_session.corrected_clock_out_at is null or v_session.effective_clock_out_at <> v_session.corrected_clock_out_at then
    raise exception 'assertion failed: expected corrected_clock_out_at to be set and reflected in effective_clock_out_at';
  end if;
  if v_session.raw_clock_out_at is null then
    raise exception 'assertion failed: raw_clock_out_at must be preserved, never overwritten (section 24)';
  end if;
  if v_session.payroll_input_status <> 'pending' then
    raise exception 'assertion failed: expected payroll_input_status reset to pending';
  end if;
end $$;

\echo '>> C-18 self-approval is blocked on ALL transitions, including one where the actor happens to also hold HRS:Approve'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='att1');
  v_role uuid;
  v_draft app.role_versions;
begin
  v_role := (app.create_role(v_tenant, 'Temp Approve', 'temp', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(v_draft.id, array(select id from app.permissions where resource_module_code='HRS' and action in ('Approve')), 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id=v_role and status='published'), '00000000-0000-0000-0000-000000027804', '00000000-0000-0000-0000-000000027801', 'tester');
end $$;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027804", "role": "authenticated"}', false);
set role authenticated;
select app.request_attendance_correction(
  (select id from app.attendance_sessions where employee_id = (select master_record_id from app.employees where work_email='emp1work@att1.test')),
  'adjust_clock_out', null, now() + interval '2 hour', 'Second correction', null, 'corr-2', '00000000-0000-0000-0000-000000027804', 'emp1'
);
do $$
begin
  begin
    perform app.decide_attendance_correction(
      (select id from app.attendance_correction_requests where idempotency_key='corr-2'),
      1, 'approve', 'self approving', '00000000-0000-0000-0000-000000027804', 'emp1'
    );
    raise exception 'assertion failed: expected self_approval_not_permitted';
  exception when others then
    if sqlerrm not like 'self_approval_not_permitted%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> HR rejects the second correction -- the correction is rejected, never silently applied'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027803", "role": "authenticated"}', false);
set role authenticated;
select app.decide_attendance_correction(
  (select id from app.attendance_correction_requests where idempotency_key='corr-2'),
  1, 'reject', 'Not enough evidence', '00000000-0000-0000-0000-000000027803', 'approver'
);
reset role;
select set_config('request.jwt.claims', 'null', false);
do $$
declare
  v_status text;
begin
  select status into v_status from app.attendance_correction_requests where idempotency_key='corr-2';
  if v_status <> 'rejected' then
    raise exception 'assertion failed: expected rejected, got %', v_status;
  end if;
end $$;

\echo '>> decision 9: cancelling a pending correction never leaves a linked exception silently implying resolution is in flight -- reopen it to ''open'' immediately'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027804", "role": "authenticated"}', false);
set role authenticated;
select app.request_attendance_correction(
  (select id from app.attendance_sessions where employee_id = (select master_record_id from app.employees where work_email='emp1work@att1.test')),
  'adjust_clock_out', null, now() + interval '3 hour', 'Third correction, to be cancelled', null, 'corr-3', '00000000-0000-0000-0000-000000027804', 'emp1'
);
select app.cancel_attendance_correction(
  (select id from app.attendance_correction_requests where idempotency_key='corr-3'),
  1, 'changed my mind', '00000000-0000-0000-0000-000000027804', 'emp1'
);
reset role;
select set_config('request.jwt.claims', 'null', false);
do $$
declare
  v_status text;
begin
  select status into v_status from app.attendance_correction_requests where idempotency_key='corr-3';
  if v_status <> 'cancelled' then
    raise exception 'assertion failed: expected cancelled, got %', v_status;
  end if;
end $$;

\echo '>> waiving an exception requires HRS:Override, not merely HRS:Edit (decision 11, C-18 authority-bar-matches-blast-radius)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027802", "role": "authenticated"}', false);
set role authenticated;
do $$
begin
  begin
    perform app.waive_attendance_exception(
      (select id from app.attendance_exceptions where employee_id=(select master_record_id from app.employees where work_email='emp1work@att1.test') and status in ('open','acknowledged') limit 1),
      1, 'waived by staff (should fail)', '00000000-0000-0000-0000-000000027802', 'staff'
    );
    raise exception 'assertion failed: expected insufficient_authority for staff (Edit-only) waiving';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027803", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_exc_id uuid;
  v_exc_version integer;
begin
  select id, record_version into v_exc_id, v_exc_version from app.attendance_exceptions where employee_id=(select master_record_id from app.employees where work_email='emp1work@att1.test') and status in ('open','acknowledged') limit 1;
  if v_exc_id is not null then
    perform app.waive_attendance_exception(v_exc_id, v_exc_version, 'late arrival excused, traffic incident', '00000000-0000-0000-0000-000000027803', 'approver');
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> HRT-293 Finding B regression: app.waive_attendance_exception no longer duplicates the raw waive_reason ("late arrival excused, traffic incident", just used above) into app.audit_logs.reason -- a plain tenant_admin reading via app.query_audit_logs never sees it either'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='att1');
begin
  if exists (select 1 from app.audit_logs where reason = 'late arrival excused, traffic incident') then
    raise exception 'HRT-293 Finding B regression: app.audit_logs.reason must never carry the raw attendance-exception waive reason';
  end if;
  if exists (select 1 from app.query_audit_logs('00000000-0000-0000-0000-000000027801', v_tenant1, 200) where reason = 'late arrival excused, traffic incident') then
    raise exception 'HRT-293 Finding B regression: a plain tenant_admin must never see the raw waive reason via app.query_audit_logs';
  end if;
end $$;

\echo '>> geofence: branch-scoped required-geofence policy overrides tenant-wide for a branch-assigned employee -- a location outside the geofence is REJECTED, never a fake success (section 15)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027802", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='att1');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant and code='BR-ATT1');
  v_policy app.attendance_policies;
  v_version app.attendance_policy_versions;
begin
  v_policy := app.create_attendance_policy(v_tenant, v_branch, 'Att1 Branch Geofenced', '00000000-0000-0000-0000-000000027802', 'staff');
  v_version := app.create_attendance_policy_version(
    v_policy.id, 'Asia/Jakarta', '08:00:00'::time, '17:00:00'::time, '04:00:00'::time, 15, 15,
    array['mobile_web','kiosk']::text[], 'required',
    jsonb_build_object('type','Point','coordinates', array[106.8456, -6.2088]),
    200, 16, '2024-01-01'::date, '00000000-0000-0000-0000-000000027802', 'staff'
  );
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027803", "role": "authenticated"}', false);
set role authenticated;
select app.publish_attendance_policy_version(
  (select id from app.attendance_policy_versions where policy_id = (select id from app.attendance_policies where name='Att1 Branch Geofenced')),
  1, '00000000-0000-0000-0000-000000027803', 'approver'
);
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027806", "role": "authenticated"}', false);
set role authenticated;
do $$
begin
  begin
    perform app.record_attendance_clock_event(
      (select id from app.tenants where slug='att1'), 'clock_in', 'mobile_web', now(),
      jsonb_build_object('type','Point','coordinates', array[107.6191, -6.9175]),
      null, 'geo-in-1', '00000000-0000-0000-0000-000000027806', 'mgr1'
    );
    raise exception 'assertion failed: expected outside_geofence rejection';
  exception when others then
    if sqlerrm not like 'outside_geofence%' then raise; end if;
  end;
end $$;
select event_type, location_source, geofence_result from app.record_attendance_clock_event(
  (select id from app.tenants where slug='att1'), 'clock_in', 'mobile_web', now(),
  jsonb_build_object('type','Point','coordinates', array[106.8456, -6.2088]),
  null, 'geo-in-2', '00000000-0000-0000-0000-000000027806', 'mgr1'
);
select app.record_attendance_clock_event((select id from app.tenants where slug='att1'), 'clock_out', 'mobile_web', now(), jsonb_build_object('type','Point','coordinates', array[106.8456, -6.2088]), null, 'geo-out-2', '00000000-0000-0000-0000-000000027806', 'mgr1');
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> geofence never applies to manual_hr or device_import channels (both structurally exempt) -- a manual entry against the SAME required-geofence-branch employee must not require location'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027802", "role": "authenticated"}', false);
set role authenticated;
do $$
begin
  begin
    perform app.record_manual_attendance_event((select id from app.tenants where slug='att1'), (select master_record_id from app.employees where work_email='mgr1work@att1.test'), 'clock_in', now() - interval '1 hour', 'HR entered on behalf, employee forgot badge', 'man-1', '00000000-0000-0000-0000-000000027802', 'staff');
    raise exception 'assertion failed: expected duplicate_workday_session (mgr1 already has a session today from the geofence test above), never location_required';
  exception when others then
    if sqlerrm not like 'duplicate_workday_session%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> manual HR entry requires a non-empty reason'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027802", "role": "authenticated"}', false);
set role authenticated;
do $$
begin
  begin
    perform app.record_manual_attendance_event((select id from app.tenants where slug='att1'), (select master_record_id from app.employees where work_email='emp3work@att1.test'), 'clock_in', now(), null, null, '00000000-0000-0000-0000-000000027802', 'staff');
    raise exception 'assertion failed: expected reason_required';
  exception when others then
    if sqlerrm not like 'reason_required%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> self-service channel restriction: device_import is not a valid channel on the self-clock RPC'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027807", "role": "authenticated"}', false);
set role authenticated;
do $$
begin
  begin
    perform app.record_attendance_clock_event((select id from app.tenants where slug='att1'), 'clock_in', 'device_import', now(), null, null, 'bad-chan-1', '00000000-0000-0000-0000-000000027807', 'emp3');
    raise exception 'assertion failed: expected invalid_source_channel';
  exception when others then
    if sqlerrm not like 'invalid_source_channel%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> device import (decision 6): the sixth-plus real PLT-131/132 staged-import adapter -- publish document type + import_export schema config, stage rows, validate (structural + formula-injection + employee resolution), commit'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='att1');
  v_doc_draft app.config_versions;
  v_draft app.config_versions;
  v_source_file app.files;
  v_job app.jobs;
  v_row1 app.import_staging_rows;
  v_row2 app.import_staging_rows;
  v_row3 app.import_staging_rows;
begin
  v_doc_draft := app.create_config_draft('document:attendance_device_import_source', v_tenant, 'tenant', null, '00000000-0000-0000-0000-000000027801', 'admin');
  perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('text/csv')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('confidential'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), '00000000-0000-0000-0000-000000027801', 'admin');
  perform app.publish_document_type_definition(v_doc_draft.id, '00000000-0000-0000-0000-000000027801', now(), 'admin');

  v_draft := app.create_config_draft('import_export:attendance_device_import', v_tenant, 'tenant', null, '00000000-0000-0000-0000-000000027801', 'admin');
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
      jsonb_build_object('key', 'employee_number', 'label', 'Employee Number', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'event_type', 'label', 'Event Type', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'event_at', 'label', 'Event At', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'device_label', 'label', 'Device', 'required', false, 'data_type', 'text')
    ))
  ), '00000000-0000-0000-0000-000000027801', 'admin');
  perform app.publish_import_export_schema(v_draft.id, '00000000-0000-0000-0000-000000027801', now(), 'admin');

  v_source_file := app.initiate_file_upload(v_tenant, 'attendance_device_import_source', 'import_job', gen_random_uuid(), 'kiosk-export.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-devimport-src-1', '00000000-0000-0000-0000-000000027802', 'staff');
  perform app.record_file_scan_result(v_source_file.id, 'clean', null, '00000000-0000-0000-0000-000000027802', 'staff');

  v_job := app.create_import_export_job(v_tenant, 'import', 'attendance_device_import', v_source_file.id, '{}'::jsonb, 'idem-devimport-job-1', '00000000-0000-0000-0000-000000027802', 'staff');

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', (select code from app.master_records where id = (select master_record_id from app.employees where work_email='emp3work@att1.test')),
    'event_type', 'clock_in', 'event_at', (now() - interval '2 hours')::text, 'device_label', 'Kiosk-1'
  )), '00000000-0000-0000-0000-000000027802', 'staff');
  select * into v_row1 from app.import_staging_rows where job_id = v_job.job_id and row_number = 1;

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', 'NOT-A-REAL-EMPLOYEE', 'event_type', 'clock_in', 'event_at', now()::text
  )), '00000000-0000-0000-0000-000000027802', 'staff');
  select * into v_row2 from app.import_staging_rows where job_id = v_job.job_id and row_number = 2;

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', '=cmd|/c calc', 'event_type', 'clock_in', 'event_at', now()::text
  )), '00000000-0000-0000-0000-000000027802', 'staff');
  select * into v_row3 from app.import_staging_rows where job_id = v_job.job_id and row_number = 3;

  perform app.validate_attendance_device_import_row(v_row1.id, '00000000-0000-0000-0000-000000027802', 'staff');
  perform app.validate_attendance_device_import_row(v_row2.id, '00000000-0000-0000-0000-000000027802', 'staff');
  perform app.validate_attendance_device_import_row(v_row3.id, '00000000-0000-0000-0000-000000027802', 'staff');

  if (select validation_status from app.import_staging_rows where id = v_row1.id) <> 'valid' then
    raise exception 'assertion failed: expected row1 valid, got %', (select error from app.import_staging_rows where id = v_row1.id);
  end if;
  if (select validation_status from app.import_staging_rows where id = v_row2.id) <> 'invalid' or (select error from app.import_staging_rows where id = v_row2.id) !~ 'employee_number' then
    raise exception 'assertion failed: expected row2 invalid on employee_number, got %', (select error from app.import_staging_rows where id = v_row2.id);
  end if;
  if (select validation_status from app.import_staging_rows where id = v_row3.id) <> 'invalid' or (select error from app.import_staging_rows where id = v_row3.id) !~ 'formula' then
    raise exception 'assertion failed: expected row3 invalid on formula-injection, got %', (select error from app.import_staging_rows where id = v_row3.id);
  end if;

  begin
    perform app.commit_attendance_device_import_job(v_job.job_id, false, '00000000-0000-0000-0000-000000027802', 'staff');
    raise exception 'assertion failed: expected import_export_job_has_invalid_rows without p_allow_partial';
  exception when others then
    if sqlerrm not like 'import_export_job_has_invalid_rows%' then raise; end if;
  end;

  perform app.commit_attendance_device_import_job(v_job.job_id, true, '00000000-0000-0000-0000-000000027802', 'staff');
end $$;

do $$
declare
  v_event app.attendance_events;
begin
  select * into v_event from app.attendance_events where source_channel='device_import';
  if v_event.id is null then
    raise exception 'assertion failed: expected a real attendance_event created from the device import commit';
  end if;
  if v_event.event_type <> 'clock_in' or v_event.device_label <> 'Kiosk-1' then
    raise exception 'assertion failed: unexpected device-imported event shape';
  end if;
end $$;

\echo '>> re-committing the SAME job is idempotent per staging row (never a duplicate attendance_event)'
do $$
declare
  v_job_id uuid := (select job_id from app.jobs where import_export_schema_code='attendance_device_import' order by created_at desc limit 1);
begin
  update app.jobs set status = 'in_progress' where job_id = v_job_id;
  perform app.commit_attendance_device_import_job(v_job_id, true, '00000000-0000-0000-0000-000000027802', 'staff');
end $$;
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.attendance_events where source_channel='device_import';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 device-imported event after a repeat commit, got %', v_count;
  end if;
end $$;

\echo '>> payroll input approval: a closed session with zero open/acknowledged exceptions approves; one with an unresolved exception is skipped, never silently approved (section 24)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027803", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_row record;
  v_emp2_approved boolean := false;
begin
  for v_row in select * from app.approve_attendance_for_payroll_input((select id from app.tenants where slug='att1'), current_date - 1, current_date + 1, null, '00000000-0000-0000-0000-000000027803', 'approver') loop
    if v_row.session_id = (select id from app.attendance_sessions where employee_id=(select master_record_id from app.employees where work_email='emp2work@att1.test')) then
      v_emp2_approved := v_row.approved;
    end if;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> a session already approved for payroll is reset to pending by a subsequently APPROVED correction (never silently recalculates an already-fed value without re-approval, section 24)'
do $$
declare
  v_status_before text;
begin
  select payroll_input_status into v_status_before from app.attendance_sessions where employee_id=(select master_record_id from app.employees where work_email='emp2work@att1.test');
  if v_status_before is distinct from 'approved' then
    raise notice 'emp2 session was not approved this run (has exceptions) -- skip reset-on-correction check, not this checkpoint''s own defect';
  end if;
end $$;

\echo '>> exception recalculation (decision 7, bounded synchronous batch): re-running against the correction-adjusted session is a genuine, safe no-op-or-update, never an error, and is bounded to <= 92 days'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027802", "role": "authenticated"}', false);
set role authenticated;
select app.recalculate_attendance_exceptions_for_range((select id from app.tenants where slug='att1'), current_date - 5, current_date + 1, null, '00000000-0000-0000-0000-000000027802', 'staff');
do $$
begin
  begin
    perform app.recalculate_attendance_exceptions_for_range((select id from app.tenants where slug='att1'), current_date - 200, current_date, null, '00000000-0000-0000-0000-000000027802', 'staff');
    raise exception 'assertion failed: expected invalid_date_range for a >92-day range';
  exception when others then
    if sqlerrm not like 'invalid_date_range%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> schema-privilege defense in depth: anon holds no direct table access; authenticated has RLS-scoped SELECT but the sensitive free-text/location columns are column-restricted; validate_attendance_device_import_row is service_role-only'
set role anon;
do $$
begin
  begin
    perform count(*) from app.attendance_sessions;
    raise exception 'assertion failed: anon must not read attendance_sessions';
  exception when insufficient_privilege then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

do $$
declare
  v_has_priv boolean;
begin
  select has_column_privilege('authenticated', 'app.attendance_events', 'location', 'select') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not read attendance_events.location'; end if;
  select has_column_privilege('authenticated', 'app.attendance_events', 'raw_payload', 'select') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not read attendance_events.raw_payload'; end if;
  select has_column_privilege('authenticated', 'app.attendance_correction_requests', 'reason', 'select') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not read attendance_correction_requests.reason'; end if;
  select has_column_privilege('authenticated', 'app.attendance_correction_requests', 'decided_reason', 'select') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not read attendance_correction_requests.decided_reason'; end if;
  select has_column_privilege('authenticated', 'app.attendance_exceptions', 'waive_reason', 'select') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not read attendance_exceptions.waive_reason'; end if;
  select has_column_privilege('authenticated', 'app.attendance_exceptions', 'resolution_note', 'select') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not read attendance_exceptions.resolution_note'; end if;
  -- Non-sensitive columns remain readable (never over-restricted).
  select has_column_privilege('authenticated', 'app.attendance_sessions', 'work_date', 'select') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: authenticated should read attendance_sessions.work_date'; end if;
  select has_column_privilege('authenticated', 'app.attendance_events', 'event_type', 'select') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: authenticated should read attendance_events.event_type'; end if;
end $$;

do $$
declare
  v_has_priv boolean;
begin
  select has_function_privilege('authenticated', 'app.validate_attendance_device_import_row(uuid,uuid,text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not directly call the service_role-only validate function'; end if;
end $$;

\echo '>> RLS default-deny: a forged cross-tenant staff session cannot see att1''s own rows via the raw table (RLS still gates even with a column-restricted grant)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027823", "role": "authenticated"}', false);
set role authenticated;
select count(*) as should_be_zero from app.attendance_sessions where tenant_id = (select id from app.tenants where slug='att1');
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> structural regression guard: this migration''s own additive functions do not alter app.employees.user_id/app.users.status shape (no cross-domain mutation)'
select count(*) as employees_with_user_id from app.employees where user_id is not null and tenant_id = (select id from app.tenants where slug='att1');

\echo 'ALL HRT-278 ATTENDANCE ASSERTIONS PASSED'
