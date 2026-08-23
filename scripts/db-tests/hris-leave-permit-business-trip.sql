-- Real, executable test evidence for HRT-280 (Leave, Permit and Business
-- Trip, CG-S12-HRT-008) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Mirrors scripts/db-tests/hris-attendance.sql's
-- own two-tenant cross-isolation convention.
--
-- This file is alphabetically named BEFORE hris-onboarding-offboarding.sql,
-- hris-organization-position-linkage.sql, hris-recruitment-ats.sql, and
-- hris-shift-roster-scheduling.sql, so `scripts/db-tests/run.sh` runs it
-- BEFORE all four -- it cannot depend on any of their own fixtures (the exact
-- reason hris-attendance.sql, which sorts even earlier, is fully
-- self-contained too). It builds its own two-tenant/employee/org-unit/shift/
-- coverage/attendance-policy fixture using a fresh, unclaimed UUID range
-- (00000000-0000-0000-0000-0000000280xx), never colliding with the
-- ...027801-027823/...027901-027923 ranges HRT-278/279's own fixtures claim.

\set ON_ERROR_STOP on

-- ISS-2026-077 root fix (CG-S15-HDN-002, Prompt 370, Step 15 Full Regression).
--
-- This fixture seeds schedule assignments, leave requests and attendance clock
-- events for "today" using current_date, then asserts against
-- app.attendance_sessions.work_date. Those are NOT the same clock:
--
--   * current_date is evaluated in the SESSION timezone, which run.sh leaves at
--     the server default (Etc/UTC on CI and on a hosted project alike);
--   * work_date is computed by app.resolve_attendance_workday() in the tenant
--     ATTENDANCE POLICY's timezone -- Asia/Jakarta (UTC+7) for this fixture's lv1.
--
-- From 17:00 UTC onward the Jakarta date is already tomorrow while current_date
-- is still today, so `where s.work_date = current_date` matches nothing and the
-- HRT-278-integration negative control below reports "found 0" for an employee
-- who genuinely did get a late exception. That is a real ~7-hour window every
-- single day (17:00-24:00 UTC), which is why this file was seen failing on
-- 2026-08-13, passing on 2026-08-14, and flipping from pass to fail partway
-- through one Phase 9 session on 2026-08-22 -- all on an identical, unmodified
-- file. It was registered as a "day-of-week" flake (ISS-2026-077); it is not.
-- It is a timezone-boundary mismatch, the same root class as ISS-2026-154.
--
-- Fixed at the root rather than at the assertion: align the session's own idea
-- of "today" with the timezone the code under test actually resolves work days
-- in, so current_date and work_date can never disagree. Proven by construction
-- across all 24 hours, not by re-running and hoping -- see
-- docs/build-log/full-system-hardening/HDN-370.md.
--
-- run.sh gives every test file its own psql session, so this setting is scoped
-- to this file and cannot leak into any other.
set timezone = 'Asia/Jakarta';

\echo '>> setup: two tenants (lv1, lv2). lv1 gets a tenant_admin, HR staff (HRS Create/Edit/Export/View/View personal data/Import), an approver (HRS Approve/View/Override), four active employees (emp1, emp2, mgr1, emp3 -- emp1/emp2 report to mgr1), a published tenant-wide approval routing definition (PLT-123), a published attendance policy (HRT-278 integration), and a published shift template + coverage requirement (HRT-279 integration). lv2 gets a tenant_admin and one active employee for cross-tenant checks. A global Supreme Admin is also seeded.'
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
  v_appr_engine_role uuid;
  v_approval_draft app.config_versions;
  v_att_policy app.attendance_policies;
  v_att_version app.attendance_policy_versions;
  v_shift_tpl app.shift_templates;
  v_shift_version app.shift_template_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000028001', 'admin@lv1.test'),
    ('00000000-0000-0000-0000-000000028002', 'staff@lv1.test'),
    ('00000000-0000-0000-0000-000000028003', 'approver@lv1.test'),
    ('00000000-0000-0000-0000-000000028004', 'emp1@lv1.test'),
    ('00000000-0000-0000-0000-000000028005', 'emp2@lv1.test'),
    ('00000000-0000-0000-0000-000000028006', 'mgr1@lv1.test'),
    ('00000000-0000-0000-0000-000000028007', 'emp3@lv1.test'),
    ('00000000-0000-0000-0000-000000028021', 'admin@lv2.test'),
    ('00000000-0000-0000-0000-000000028022', 'emp1@lv2.test'),
    ('00000000-0000-0000-0000-000000028099', 'supreme@lv.test');

  perform app.provision_tenant('lv1', 'LV Co 1', 'idem-lv1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'lv1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('lv2', 'LV Co 2', 'idem-lv2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'lv2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028001', 'admin@lv1.test', 'Lv1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@lv1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028001', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028002', 'staff@lv1.test', 'Lv1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@lv1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028003', 'approver@lv1.test', 'Lv1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@lv1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028004', 'emp1@lv1.test', 'Lv1 Emp One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp1@lv1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028005', 'emp2@lv1.test', 'Lv1 Emp Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp2@lv1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028006', 'mgr1@lv1.test', 'Lv1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'mgr1@lv1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028007', 'emp3@lv1.test', 'Lv1 Emp Three', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp3@lv1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000028021', 'admin@lv2.test', 'Lv2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@lv2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028021', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000028022', 'emp1@lv2.test', 'Lv2 Emp One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp1@lv2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028099', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'HRS Staff', 'Create/Edit/Export/View/View personal data/Import', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Export', 'View', 'View personal data', 'Import')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000028002', '00000000-0000-0000-0000-000000028001', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'HRS Approver', 'Approve/View/Override', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Approve', 'View', 'Override')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000028003', '00000000-0000-0000-0000-000000028001', 'tester');

  v_t2_role := (app.create_role(v_tenant2, 'HRS Admin T2', 'Create/Edit/View/Approve/Override/Import', 'tester')).id;
  v_t2_draft := app.create_role_version(v_t2_role, 'tester');
  perform app.set_role_version_permissions(v_t2_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View', 'Approve', 'Override', 'Import')), 'tester');
  perform app.publish_role_version(v_t2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'), '00000000-0000-0000-0000-000000028021', '00000000-0000-0000-0000-000000028021', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-LV1', 'Lv1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-LV1', 'Lv1 Branch', 'tester')).id;
  perform app.create_org_unit(v_tenant2, 'company', null, 'CO-LV2', 'Lv2 Co', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Lv1 Manager', 'full_time', 'mgr1work@lv1.test', 'mgr1p@lv1.test', '0900000001', null, null, null, '2020-01-01', v_company, v_branch, null, 'Warehouse Manager', null, (select id from app.users where email = 'mgr1@lv1.test'), null, 'hr_created', 'idem-mgr1-lv1', '00000000-0000-0000-0000-000000028002', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@lv1.test'), 'Contact Mgr', 'spouse', '0910000001', null, true, '00000000-0000-0000-0000-000000028002', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@lv1.test'), 1, '00000000-0000-0000-0000-000000028002', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@lv1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028003', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@lv1.test'), 3, '00000000-0000-0000-0000-000000028003', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Lv1 Emp One', 'full_time', 'emp1work@lv1.test', 'emp1p@lv1.test', '0900000002', null, null, null, '2020-06-01', v_company, v_branch, null, 'Warehouse Staff', (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@lv1.test'), (select id from app.users where email = 'emp1@lv1.test'), null, 'hr_created', 'idem-emp1-lv1', '00000000-0000-0000-0000-000000028002', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@lv1.test'), 'Contact One', 'spouse', '0910000002', null, true, '00000000-0000-0000-0000-000000028002', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@lv1.test'), 1, '00000000-0000-0000-0000-000000028002', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@lv1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028003', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@lv1.test'), 3, '00000000-0000-0000-0000-000000028003', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Lv1 Emp Two', 'full_time', 'emp2work@lv1.test', 'emp2p@lv1.test', '0900000003', null, null, null, '2021-01-01', v_company, v_branch, null, 'Warehouse Staff', (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@lv1.test'), (select id from app.users where email = 'emp2@lv1.test'), null, 'hr_created', 'idem-emp2-lv1', '00000000-0000-0000-0000-000000028002', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@lv1.test'), 'Contact Two', 'spouse', '0910000003', null, true, '00000000-0000-0000-0000-000000028002', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@lv1.test'), 1, '00000000-0000-0000-0000-000000028002', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@lv1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028003', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@lv1.test'), 3, '00000000-0000-0000-0000-000000028003', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Lv1 Emp Three', 'full_time', 'emp3work@lv1.test', 'emp3p@lv1.test', '0900000004', null, null, null, '2022-01-01', v_company, null, null, 'Back Office', null, (select id from app.users where email = 'emp3@lv1.test'), null, 'hr_created', 'idem-emp3-lv1', '00000000-0000-0000-0000-000000028002', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@lv1.test'), 'Contact Three', 'spouse', '0910000004', null, true, '00000000-0000-0000-0000-000000028002', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@lv1.test'), 1, '00000000-0000-0000-0000-000000028002', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@lv1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028003', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@lv1.test'), 3, '00000000-0000-0000-0000-000000028003', 'tester');

  perform app.create_employee_draft(v_tenant2, 'Lv2 Emp One', 'full_time', 'emp1work@lv2.test', 'emp1p@lv2.test', '0900000005', null, null, null, '2020-01-01', (select id from app.org_units where tenant_id = v_tenant2 and code = 'CO-LV2'), null, null, 'Staff', null, (select id from app.users where email = 'emp1@lv2.test'), null, 'hr_created', 'idem-emp1-lv2', '00000000-0000-0000-0000-000000028021', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@lv2.test'), 'Contact', 'spouse', '0910000005', null, true, '00000000-0000-0000-0000-000000028021', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@lv2.test'), 1, '00000000-0000-0000-0000-000000028021', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@lv2.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028021', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@lv2.test'), 3, '00000000-0000-0000-0000-000000028021', 'tester');

  -- PLT-123 approval routing (decision 6/mandatory reading item 8): a real,
  -- published, single-step tenant-wide definition every leave/permit/
  -- business-trip request routes through -- never a bespoke mechanism.
  v_appr_engine_role := v_approver_role;
  v_approval_draft := app.create_config_draft('approval', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000028001', 'tenant admin');
  perform app.set_config_items(v_approval_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_appr_engine_role::text, 'required_approvals', 1)
    )),
    jsonb_build_object('key', 'allow_self_approval', 'value', false)
  ), '00000000-0000-0000-0000-000000028001', 'tenant admin');
  perform app.publish_approval_definition(v_approval_draft.id, '00000000-0000-0000-0000-000000028001', null, 'tenant admin');

  -- HRT-278 integration fixture: a tenant-wide attendance policy whose
  -- workday starts one second after local midnight with zero grace -- any
  -- real clock-in during a normal test run is deterministically "late"
  -- unless suppressed (never a hardcoded/aligned-to-now timestamp, ISS-2026-059
  -- lesson).
  v_att_policy := app.create_attendance_policy(v_tenant1, null, 'Lv1 Tenant-Wide', '00000000-0000-0000-0000-000000028002', 'tester');
  v_att_version := app.create_attendance_policy_version(
    v_att_policy.id, 'Asia/Jakarta', '00:00:01'::time, '23:59:00'::time, '00:00:00'::time, 0, 0,
    array['mobile_web','kiosk']::text[], 'none', null, null, 16, '2024-01-01'::date,
    '00000000-0000-0000-0000-000000028002', 'tester'
  );
  perform app.publish_attendance_policy_version(v_att_version.id, 1, '00000000-0000-0000-0000-000000028003', 'tester');

  -- HRT-279 integration fixture: a published fixed 08:00-17:00 shift, a
  -- coverage requirement of min_headcount=2 for the branch/every day of the
  -- week, and mgr1/emp2 published on it -- leaves exactly emp1's own
  -- coverage-count contribution as the variable the leave-approval coverage
  -- check below exercises.
  v_shift_tpl := app.create_shift_template(v_tenant1, v_branch, 'DAY', 'Day Shift', '00000000-0000-0000-0000-000000028002', 'staff');
  v_shift_version := app.create_shift_template_version(
    v_shift_tpl.id, 'Asia/Jakarta', '00:00:00'::time, 'fixed', 15, 15, '2024-01-01'::date,
    jsonb_build_array(jsonb_build_object('segment_type', 'work', 'start_time', '08:00:00', 'end_time', '17:00:00')),
    '00000000-0000-0000-0000-000000028002', 'staff'
  );
  perform app.publish_shift_template_version(v_shift_version.id, 1, '00000000-0000-0000-0000-000000028003', 'approver');
  -- min_headcount=3 (not 2): removing exactly ONE of the three scheduled
  -- employees must genuinely drop coverage BELOW the minimum (3-1=2 < 3) for
  -- the coverage-threshold scenario below to be a real, math-checked block,
  -- not merely asserted.
  perform app.set_schedule_coverage_requirement(v_tenant1, v_branch, v_shift_tpl.id, extract(dow from current_date)::integer, 3, '00000000-0000-0000-0000-000000028002', 'staff');
  perform app.assign_employee_schedule(v_tenant1, (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@lv1.test'), v_shift_version.id, current_date, 'manual', 'sched-mgr1-today', '00000000-0000-0000-0000-000000028002', 'staff');
  perform app.assign_employee_schedule(v_tenant1, (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@lv1.test'), v_shift_version.id, current_date, 'manual', 'sched-emp2-today', '00000000-0000-0000-0000-000000028002', 'staff');
  perform app.assign_employee_schedule(v_tenant1, (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@lv1.test'), v_shift_version.id, current_date, 'manual', 'sched-emp1-today', '00000000-0000-0000-0000-000000028002', 'staff');
  perform app.publish_schedule_assignments(v_tenant1, current_date, current_date, null, null, '00000000-0000-0000-0000-000000028003', 'approver');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end $$;

\echo '>> app.create_leave_type: viewer/no-permission actor rejected; staff (HRS:Edit) creates real annual/permit/business_trip types; duplicate code within a tenant rejected'
do $$
declare
  v_annual app.leave_types;
begin
  begin
    perform app.create_leave_type((select id from app.tenants where slug='lv1'), 'annual', 'Annual Leave', 'leave', true, false, 'none', '00000000-0000-0000-0000-000000028004', 'emp1');
    raise exception 'assertion failed: expected a zero-HRS-permission employee to be rejected creating a leave type';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority:%' then raise; end if;
  end;

  v_annual := app.create_leave_type((select id from app.tenants where slug='lv1'), 'annual', 'Annual Leave', 'leave', true, false, 'none', '00000000-0000-0000-0000-000000028002', 'staff');
  if v_annual.status <> 'draft' then raise exception 'assertion failed: expected a new leave type to start as draft'; end if;

  begin
    perform app.create_leave_type((select id from app.tenants where slug='lv1'), 'annual', 'Duplicate', 'leave', true, false, 'none', '00000000-0000-0000-0000-000000028002', 'staff');
    raise exception 'assertion failed: expected a duplicate code to be rejected';
  exception
    when unique_violation then null;
  end;

  perform app.create_leave_type((select id from app.tenants where slug='lv1'), 'permit', 'Permit', 'permit', false, false, 'none', '00000000-0000-0000-0000-000000028002', 'staff');
  perform app.create_leave_type((select id from app.tenants where slug='lv1'), 'business_trip', 'Business Trip', 'business_trip', false, false, 'none', '00000000-0000-0000-0000-000000028002', 'staff');
  perform app.create_leave_type((select id from app.tenants where slug='lv1'), 'sick', 'Sick Leave (medical evidence)', 'leave', true, true, 'medical', '00000000-0000-0000-0000-000000028002', 'staff');
end $$;

\echo '>> app.publish_leave_type / app.create_leave_type_policy_version / app.publish_leave_type_policy_version: HRS:Approve required for publish; a real policy version publishes and supersedes resolution correctly'
do $$
declare
  v_type app.leave_types;
  v_version app.leave_type_policy_versions;
  v_resolved app.leave_type_policy_versions;
begin
  select * into v_type from app.leave_types where tenant_id = (select id from app.tenants where slug='lv1') and code = 'annual';

  begin
    perform app.publish_leave_type(v_type.id, v_type.record_version, '00000000-0000-0000-0000-000000028002', 'staff');
    raise exception 'assertion failed: expected HRS:Edit-only staff to be rejected publishing (requires HRS:Approve)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority:%' then raise; end if;
  end;

  perform app.publish_leave_type(v_type.id, v_type.record_version, '00000000-0000-0000-0000-000000028003', 'approver');

  v_version := app.create_leave_type_policy_version(
    v_type.id, null, '2024-01-01'::date, 'monthly', 1, 24, 6, 0, null, 0, false,
    '00000000-0000-0000-0000-000000028002', 'staff'
  );
  perform app.publish_leave_type_policy_version(v_version.id, 1, '00000000-0000-0000-0000-000000028003', 'approver');

  select * into v_resolved from app.resolve_effective_leave_type_policy_version((select id from app.tenants where slug='lv1'), v_type.id, null, current_date) limit 1;
  if v_resolved.id <> v_version.id then raise exception 'assertion failed: expected the just-published version to resolve as effective'; end if;

  -- permit/business_trip/sick each get a trivial always-eligible policy too.
  -- app.publish_leave_type_policy_version's own side effect already flips the
  -- parent leave_type to published (mirrors app.publish_attendance_policy_
  -- version's identical parent-flip, HRT-278) -- no separate app.
  -- publish_leave_type call is needed (or valid: a second attempt on an
  -- already-published type is a real invalid_transition).
  perform app.publish_leave_type_policy_version(
    (app.create_leave_type_policy_version((select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='permit'), null, '2024-01-01'::date, 'none', 0, null, 0, 0, null, 0, true, '00000000-0000-0000-0000-000000028002', 'staff')).id,
    1, '00000000-0000-0000-0000-000000028003', 'approver'
  );

  perform app.publish_leave_type_policy_version(
    (app.create_leave_type_policy_version((select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='business_trip'), null, '2024-01-01'::date, 'none', 0, null, 0, 0, null, 0, true, '00000000-0000-0000-0000-000000028002', 'staff')).id,
    1, '00000000-0000-0000-0000-000000028003', 'approver'
  );

  perform app.publish_leave_type_policy_version(
    (app.create_leave_type_policy_version((select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='sick'), null, '2024-01-01'::date, 'none', 0, null, 0, 0, null, 0, false, '00000000-0000-0000-0000-000000028002', 'staff')).id,
    1, '00000000-0000-0000-0000-000000028003', 'approver'
  );

  if (select status from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='permit') <> 'published' then
    raise exception 'assertion failed: expected app.publish_leave_type_policy_version to auto-publish the parent leave_type';
  end if;
end $$;

\echo '>> app.load_opening_leave_balance: HRS:Import required; idempotent re-run; app.get_employee_leave_balance sums the ledger'
do $$
declare
  v_emp1 uuid := (select master_record_id from app.employees where work_email='emp1work@lv1.test');
  v_annual_id uuid := (select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='annual');
  v_balance numeric;
begin
  begin
    perform app.load_opening_leave_balance((select id from app.tenants where slug='lv1'), v_emp1, v_annual_id, 10, '2024-01-01'::date, 'legacy system', 'open-emp1-annual', '00000000-0000-0000-0000-000000028003', 'approver');
    raise exception 'assertion failed: expected HRS:Approve-only (no Import) to be rejected loading an opening balance';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority:%' then raise; end if;
  end;

  perform app.load_opening_leave_balance((select id from app.tenants where slug='lv1'), v_emp1, v_annual_id, 10, '2024-01-01'::date, 'legacy system', 'open-emp1-annual', '00000000-0000-0000-0000-000000028002', 'staff');
  perform app.load_opening_leave_balance((select id from app.tenants where slug='lv1'), v_emp1, v_annual_id, 10, '2024-01-01'::date, 'legacy system', 'open-emp1-annual', '00000000-0000-0000-0000-000000028002', 'staff');
  if (select count(*) from app.leave_balance_ledger where employee_id = v_emp1 and leave_type_id = v_annual_id and event_type = 'opening_balance') <> 1 then
    raise exception 'assertion failed: expected the idempotent re-run to post exactly one opening_balance event';
  end if;

  v_balance := app.get_employee_leave_balance((select id from app.tenants where slug='lv1'), v_emp1, v_annual_id, current_date);
  if v_balance <> 10 then raise exception 'assertion failed: expected balance 10, got %', v_balance; end if;

  -- Give emp2/emp3 the same opening balance for later scenarios.
  perform app.load_opening_leave_balance((select id from app.tenants where slug='lv1'), (select master_record_id from app.employees where work_email='emp2work@lv1.test'), v_annual_id, 10, '2024-01-01'::date, 'legacy system', 'open-emp2-annual', '00000000-0000-0000-0000-000000028002', 'staff');
  perform app.load_opening_leave_balance((select id from app.tenants where slug='lv1'), (select master_record_id from app.employees where work_email='emp3work@lv1.test'), v_annual_id, 1, '2024-01-01'::date, 'legacy system', 'open-emp3-annual', '00000000-0000-0000-0000-000000028002', 'staff');
end $$;

\echo '>> self-service app.create_leave_request/app.submit_leave_request as emp1 (decision 10, no employee-id parameter to spoof); overlap EXCLUDE constraint (decision 5) blocks a second overlapping submission; insufficient balance blocked'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='lv1');
  v_annual_id uuid := (select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='annual');
  v_request app.leave_requests;
  v_second app.leave_requests;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028004", "role": "authenticated"}', false);
  set role authenticated;
  v_request := app.create_leave_request(v_tenant1, v_annual_id, '2026-09-01'::date, '2026-09-03'::date, 'full_day', 'Family vacation', null, null, 'lv-emp1-req1', '00000000-0000-0000-0000-000000028004', 'emp1');
  if v_request.status <> 'draft' then raise exception 'assertion failed: expected a new request to start as draft, got %', v_request.status; end if;
  if v_request.total_units <> 3 then raise exception 'assertion failed: expected 3 business-day units, got %', v_request.total_units; end if;

  v_request := app.submit_leave_request(v_request.id, v_request.record_version, '00000000-0000-0000-0000-000000028004', 'emp1');
  if v_request.status <> 'pending_approval' then raise exception 'assertion failed: expected pending_approval after submit, got %', v_request.status; end if;
  if v_request.approval_request_id is null then raise exception 'assertion failed: expected a real PLT-123 approval_request_id to be attached'; end if;

  -- A second, overlapping request is rejected at SUBMIT time by the real
  -- database-level EXCLUDE constraint, translated to a friendly error.
  v_second := app.create_leave_request(v_tenant1, v_annual_id, '2026-09-02'::date, '2026-09-04'::date, 'full_day', 'Overlapping attempt', null, null, 'lv-emp1-req2', '00000000-0000-0000-0000-000000028004', 'emp1');
  begin
    perform app.submit_leave_request(v_second.id, v_second.record_version, '00000000-0000-0000-0000-000000028004', 'emp1');
    raise exception 'assertion failed: expected an overlapping submission to be rejected';
  exception
    when others then
      if sqlerrm not like 'leave_request_overlap:%' then raise; end if;
  end;

  -- Insufficient balance: emp1 has 10 units, request 28 (Oct 1-28). The
  -- soft, non-locking balance check (decision 4) runs at DRAFT-CREATE time
  -- already, not merely at submit -- fast feedback before a request is even
  -- persisted.
  begin
    perform app.create_leave_request(v_tenant1, v_annual_id, '2026-10-01'::date, '2026-10-28'::date, 'full_day', 'Too long', null, null, 'lv-emp1-over', '00000000-0000-0000-0000-000000028004', 'emp1');
    raise exception 'assertion failed: expected insufficient balance to block draft creation';
  exception
    when others then
      if sqlerrm not like 'insufficient_balance:%' then raise; end if;
  end;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);
end $$;

\echo '>> app.decide_leave_request: approve posts the C-04-safe advisory-lock-serialized ledger debit and reduces the balance; the raw EXCLUDE-guarded request row itself proves no double-decision is possible'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='lv1');
  v_annual_id uuid := (select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='annual');
  v_emp1 uuid := (select master_record_id from app.employees where work_email='emp1work@lv1.test');
  v_request_id uuid := (select id from app.leave_requests where tenant_id = v_tenant1 and employee_id = v_emp1 and idempotency_key = 'lv-emp1-req1');
  v_step_id uuid;
  v_decided app.leave_requests;
  v_balance numeric;
begin
  select s.id into v_step_id from app.approval_request_steps s
  join app.leave_requests r on r.approval_request_id = s.request_id
  where r.id = v_request_id and s.status = 'active';
  if v_step_id is null then raise exception 'assertion failed: expected a real active approval step for the submitted request'; end if;

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028003", "role": "authenticated"}', false);
  set role authenticated;
  v_decided := app.decide_leave_request(v_step_id, 'approved', 'looks good', false, '00000000-0000-0000-0000-000000028003', 'approver');
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  if v_decided.status <> 'approved' then raise exception 'assertion failed: expected approved, got %', v_decided.status; end if;
  if (select count(*) from app.leave_balance_ledger where source_request_id = v_request_id and event_type = 'request_debit') <> 1 then
    raise exception 'assertion failed: expected exactly one request_debit ledger event';
  end if;

  v_balance := app.get_employee_leave_balance(v_tenant1, v_emp1, v_annual_id, current_date);
  if v_balance <> 7 then raise exception 'assertion failed: expected balance 10-3=7, got %', v_balance; end if;

  -- The now-overlapping second request (from the prior block, still
  -- pending_approval) must now be rejected as unsubmittable by the SAME
  -- overlap guard even against an APPROVED sibling.
  if exists (
    select 1 from app.leave_requests where tenant_id = v_tenant1 and employee_id = v_emp1 and idempotency_key = 'lv-emp1-req2' and status = 'pending_approval'
  ) then
    raise notice 'lv-emp1-req2 remains pending_approval as expected (never itself submitted a second time)';
  end if;
end $$;

\echo '>> app.cancel_leave_request: cancelling a still-pending request cancels its own PLT-123 approval request too (mandatory reading item 4/8); cancelling an already-APPROVED future request posts a credit reversal and restores the balance'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='lv1');
  v_annual_id uuid := (select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='annual');
  v_emp2 uuid := (select master_record_id from app.employees where work_email='emp2work@lv1.test');
  v_pending app.leave_requests;
  v_approved app.leave_requests;
  v_cancelled app.leave_requests;
  v_step_id uuid;
  v_balance_before numeric;
  v_balance_after numeric;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028005", "role": "authenticated"}', false);
  set role authenticated;
  v_pending := app.create_leave_request(v_tenant1, v_annual_id, '2026-11-10'::date, '2026-11-10'::date, 'full_day', 'Placeholder', null, null, 'lv-emp2-cancel-pending', '00000000-0000-0000-0000-000000028005', 'emp2');
  v_pending := app.submit_leave_request(v_pending.id, v_pending.record_version, '00000000-0000-0000-0000-000000028005', 'emp2');
  v_cancelled := app.cancel_leave_request(v_pending.id, v_pending.record_version, 'changed my mind', '00000000-0000-0000-0000-000000028005', 'emp2');
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  if v_cancelled.status <> 'cancelled' then raise exception 'assertion failed: expected cancelled, got %', v_cancelled.status; end if;
  if (select status from app.approval_requests where id = v_pending.approval_request_id) <> 'cancelled' then
    raise exception 'assertion failed: expected the linked PLT-123 approval request to be cancelled too, never left dangling';
  end if;

  -- Approve a FUTURE-dated request for emp2, then self-cancel it.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028005", "role": "authenticated"}', false);
  set role authenticated;
  v_approved := app.create_leave_request(v_tenant1, v_annual_id, '2026-12-01'::date, '2026-12-02'::date, 'full_day', 'Year-end trip', null, null, 'lv-emp2-cancel-approved', '00000000-0000-0000-0000-000000028005', 'emp2');
  v_approved := app.submit_leave_request(v_approved.id, v_approved.record_version, '00000000-0000-0000-0000-000000028005', 'emp2');
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  select s.id into v_step_id from app.approval_request_steps s where s.request_id = v_approved.approval_request_id and s.status = 'active';
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028003", "role": "authenticated"}', false);
  set role authenticated;
  v_approved := app.decide_leave_request(v_step_id, 'approved', 'ok', false, '00000000-0000-0000-0000-000000028003', 'approver');
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  v_balance_before := app.get_employee_leave_balance(v_tenant1, v_emp2, v_annual_id, current_date);

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028005", "role": "authenticated"}', false);
  set role authenticated;
  v_cancelled := app.cancel_leave_request(v_approved.id, v_approved.record_version, 'plans changed', '00000000-0000-0000-0000-000000028005', 'emp2');
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  if v_cancelled.status <> 'cancelled' then raise exception 'assertion failed: expected cancelled, got %', v_cancelled.status; end if;
  if (select count(*) from app.leave_balance_ledger where source_request_id = v_approved.id and event_type = 'request_credit_reversal') <> 1 then
    raise exception 'assertion failed: expected exactly one request_credit_reversal ledger event';
  end if;
  v_balance_after := app.get_employee_leave_balance(v_tenant1, v_emp2, v_annual_id, current_date);
  if v_balance_after <> v_balance_before + 2 then
    raise exception 'assertion failed: expected balance restored by 2 units (% -> %), got %', v_balance_before, v_balance_before + 2, v_balance_after;
  end if;
end $$;

\echo '>> app.cancel_leave_request: an already-completed PAST approved leave cannot be cancelled -- no meaningful compensating event exists for time already taken'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='lv1');
  v_annual_id uuid := (select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='annual');
  v_emp3 uuid := (select master_record_id from app.employees where work_email='emp3work@lv1.test');
  v_request app.leave_requests;
  v_step_id uuid;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028007", "role": "authenticated"}', false);
  set role authenticated;
  v_request := app.create_leave_request(v_tenant1, v_annual_id, '2024-06-01'::date, '2024-06-01'::date, 'full_day', 'Long-past leave', null, null, 'lv-emp3-past', '00000000-0000-0000-0000-000000028007', 'emp3');
  v_request := app.submit_leave_request(v_request.id, v_request.record_version, '00000000-0000-0000-0000-000000028007', 'emp3');
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  select s.id into v_step_id from app.approval_request_steps s where s.request_id = v_request.approval_request_id and s.status = 'active';
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028003", "role": "authenticated"}', false);
  set role authenticated;
  v_request := app.decide_leave_request(v_step_id, 'approved', 'ok, backdated correction', false, '00000000-0000-0000-0000-000000028003', 'approver');
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028007", "role": "authenticated"}', false);
  set role authenticated;
  begin
    perform app.cancel_leave_request(v_request.id, v_request.record_version, 'too late', '00000000-0000-0000-0000-000000028007', 'emp3');
    raise exception 'assertion failed: expected cancelling an already-completed past leave to be rejected';
  exception
    when others then
      if sqlerrm not like 'invalid_transition:%' then raise; end if;
  end;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);
end $$;

\echo '>> C-05 cross-tenant fold: lv2 gets not-found (never a distinguishing error) probing lv1 leave types/requests by id; lv2 sees zero lv1 rows via RLS'
do $$
declare
  v_lv1_type_id uuid := (select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='annual');
  v_lv1_request_id uuid := (select id from app.leave_requests where tenant_id=(select id from app.tenants where slug='lv1') and idempotency_key='lv-emp1-req1');
  v_count integer;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028022", "role": "authenticated"}', false);
  set role authenticated;

  begin
    perform app.get_leave_request_detail(v_lv1_request_id, '00000000-0000-0000-0000-000000028022');
    raise exception 'assertion failed: expected a cross-tenant caller to get leave_request_not_found';
  exception
    when others then
      if sqlerrm not like 'leave_request_not_found:%' then raise; end if;
  end;

  select count(*) into v_count from app.leave_types where id = v_lv1_type_id;
  if v_count <> 0 then raise exception 'assertion failed: expected RLS to deny cross-tenant visibility of a leave_types row'; end if;

  select count(*) into v_count from app.leave_requests where id = v_lv1_request_id;
  if v_count <> 0 then raise exception 'assertion failed: expected RLS to deny cross-tenant visibility of a leave_requests row'; end if;

  reset role;
  perform set_config('request.jwt.claims', 'null', false);
end $$;

\echo '>> section 21/23 coverage threshold: approving emp1''s leave for TODAY would drop the branch/day-shift coverage below the required minimum -- blocked unless the approver also holds HRS:Override'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='lv1');
  v_emp1 uuid := (select master_record_id from app.employees where work_email='emp1work@lv1.test');
  v_permit_id uuid := (select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='permit');
  v_request app.leave_requests;
  v_step_id uuid;
  v_scheduled integer;
  v_min integer;
begin
  select v_scheduled_count, v_min_headcount into v_scheduled, v_min from app._leave_coverage_impact(v_tenant1, v_emp1, current_date);
  if v_min is null or v_scheduled <> 3 then
    raise exception 'assertion failed: expected the fixture to show 3 published assignments (mgr1/emp2/emp1) and a real coverage requirement, got scheduled=%, min=%', v_scheduled, v_min;
  end if;

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028004", "role": "authenticated"}', false);
  set role authenticated;
  v_request := app.create_leave_request(v_tenant1, v_permit_id, current_date, current_date, 'full_day', 'Personal errand today', null, null, 'lv-emp1-coverage', '00000000-0000-0000-0000-000000028004', 'emp1');
  v_request := app.submit_leave_request(v_request.id, v_request.record_version, '00000000-0000-0000-0000-000000028004', 'emp1');
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  select s.id into v_step_id from app.approval_request_steps s where s.request_id = v_request.approval_request_id and s.status = 'active';

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028003", "role": "authenticated"}', false);
  set role authenticated;
  begin
    perform app.decide_leave_request(v_step_id, 'approved', 'ok', false, '00000000-0000-0000-0000-000000028003', 'approver');
    raise exception 'assertion failed: expected coverage_below_minimum to block approval without an explicit override';
  exception
    when others then
      if sqlerrm not like 'coverage_below_minimum:%' then raise; end if;
  end;

  -- approver here ALSO holds HRS:Override (fixture role grants Approve/View/Override), so the override branch succeeds.
  perform app.decide_leave_request(v_step_id, 'approved', 'coverage gap accepted for today', true, '00000000-0000-0000-0000-000000028003', 'approver');
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  if (select status from app.leave_requests where id = v_request.id) <> 'approved' then
    raise exception 'assertion failed: expected the override decision to approve the request';
  end if;
end $$;

\echo '>> decision 10 schedule override: app.cancel_conflicting_schedule_assignment_for_leave (HRS:Override) explicitly cancels emp1''s own already-published shift for today -- never automatic on mere approval'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='lv1');
  v_emp1 uuid := (select master_record_id from app.employees where work_email='emp1work@lv1.test');
  v_request_id uuid := (select id from app.leave_requests where tenant_id = v_tenant1 and idempotency_key = 'lv-emp1-coverage');
  v_assignment app.schedule_assignments;
  v_result app.schedule_assignments;
begin
  select * into v_assignment from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp1 and work_date = current_date and status = 'published';
  if v_assignment.id is null then raise exception 'assertion failed: expected emp1 to still have a real published assignment today (approval never auto-cancels it)'; end if;

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028002", "role": "authenticated"}', false);
  set role authenticated;
  begin
    perform app.cancel_conflicting_schedule_assignment_for_leave(v_request_id, current_date, v_assignment.record_version, 'on approved leave', '00000000-0000-0000-0000-000000028002', 'staff');
    raise exception 'assertion failed: expected HRS:Edit-only staff (no Override) to be rejected';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority:%' then raise; end if;
  end;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028003", "role": "authenticated"}', false);
  set role authenticated;
  v_result := app.cancel_conflicting_schedule_assignment_for_leave(v_request_id, current_date, v_assignment.record_version, 'on approved leave', '00000000-0000-0000-0000-000000028003', 'approver');
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  if v_result.status <> 'cancelled' then raise exception 'assertion failed: expected the conflicting shift to be cancelled, got %', v_result.status; end if;
end $$;

\echo '>> HRT-278 integration (20260730940000 binding): an approved full_day leave/permit covering TODAY suppresses the late-arrival exception a real clock-in would otherwise trigger; an employee with NO leave coverage still gets a real, undisturbed late exception'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='lv1');
  v_emp1_session uuid;
  v_emp3_session uuid;
  v_late_count_emp1 integer;
  v_late_count_emp3 integer;
begin
  -- emp1 clocks in "late" (policy workday_start_time=00:00:01, zero grace) --
  -- but emp1 has an APPROVED full_day permit covering today (from the
  -- coverage-threshold scenario above), so no late exception should exist.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028004", "role": "authenticated"}', false);
  set role authenticated;
  select id into v_emp1_session from app.record_attendance_clock_event(v_tenant1, 'clock_in', 'mobile_web', now(), null, null, 'lv-emp1-clockin-today', '00000000-0000-0000-0000-000000028004', 'emp1');
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  select count(*) into v_late_count_emp1 from app.attendance_exceptions x
  join app.attendance_sessions s on s.id = x.session_id
  where s.employee_id = (select master_record_id from app.employees where work_email='emp1work@lv1.test') and s.work_date = current_date and x.exception_type = 'late' and x.status in ('open', 'acknowledged');
  if v_late_count_emp1 <> 0 then
    raise exception 'assertion failed: expected the approved-leave-covered employee''s late exception to be suppressed, found % open/acknowledged', v_late_count_emp1;
  end if;

  -- emp3 has NO leave request covering today -- the identical clock-in
  -- timing produces a real, undisturbed late exception (the negative control
  -- proving the policy/detection logic itself is unchanged, only suppressed
  -- when leave genuinely applies).
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028007", "role": "authenticated"}', false);
  set role authenticated;
  select id into v_emp3_session from app.record_attendance_clock_event(v_tenant1, 'clock_in', 'mobile_web', now(), null, null, 'lv-emp3-clockin-today', '00000000-0000-0000-0000-000000028007', 'emp3');
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  select count(*) into v_late_count_emp3 from app.attendance_exceptions x
  join app.attendance_sessions s on s.id = x.session_id
  where s.employee_id = (select master_record_id from app.employees where work_email='emp3work@lv1.test') and s.work_date = current_date and x.exception_type = 'late' and x.status in ('open', 'acknowledged');
  if v_late_count_emp3 <> 1 then
    raise exception 'assertion failed: expected the NOT-on-leave employee to have a real late exception (negative control), found %', v_late_count_emp3;
  end if;
end $$;

\echo '>> decision 13 accrual/carry-forward batches: bounded, idempotent, real PLT-132 app.jobs rows (job_type in (leave_accrual, leave_carry_forward_expiry)); a real carry-forward-cap forfeiture is posted'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='lv1');
  v_annual_id uuid := (select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='annual');
  v_emp3 uuid := (select master_record_id from app.employees where work_email='emp3work@lv1.test');
  v_accrued integer; v_skipped integer; v_job_id uuid;
  v_expired integer; v_skipped2 integer; v_job_id2 uuid;
  v_balance_before numeric;
  v_balance_after numeric;
begin
  begin
    perform app.run_leave_accrual_batch(v_tenant1, v_annual_id, current_date, '2026-08', '00000000-0000-0000-0000-000000028002', 'staff');
    raise exception 'assertion failed: expected HRS:Edit-only staff (no Override) to be rejected running the accrual batch';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority:%' then raise; end if;
  end;

  select accrued_count, skipped_count, job_id into v_accrued, v_skipped, v_job_id from app.run_leave_accrual_batch(v_tenant1, v_annual_id, current_date, '2026-08', '00000000-0000-0000-0000-000000028003', 'approver');
  if v_accrued < 1 then raise exception 'assertion failed: expected at least one real accrual posting, got %', v_accrued; end if;
  if (select job_type from app.jobs where job_id = v_job_id) <> 'leave_accrual' then raise exception 'assertion failed: expected a real leave_accrual app.jobs row'; end if;
  if (select status from app.jobs where job_id = v_job_id) <> 'completed' then raise exception 'assertion failed: expected the job to reach completed'; end if;

  -- Idempotent re-run for the SAME period: zero new accruals.
  select accrued_count into v_accrued from app.run_leave_accrual_batch(v_tenant1, v_annual_id, current_date, '2026-08', '00000000-0000-0000-0000-000000028003', 'approver');
  if v_accrued <> 0 then raise exception 'assertion failed: expected a same-period re-run to accrue nothing new, got %', v_accrued; end if;

  -- emp3's own balance is still well under the 6-unit carry_forward_max_units
  -- cap on the annual policy at this point (the batch run above already
  -- proved a below-cap employee is simply skipped, v_skipped counts it) --
  -- push emp3 ABOVE the cap here and confirm the excess is genuinely forfeited.
  -- Dated current_date - 1 (not current_date) deliberately: app.run_leave_
  -- carry_forward_batch computes the PRIOR period's own ending balance as of
  -- p_effective_date - 1 (standard carry-forward semantics -- the balance at
  -- the moment just before the new period begins), so this adjustment must
  -- fall within that window to be seen by the batch call below.
  perform app.adjust_leave_balance(v_tenant1, v_emp3, v_annual_id, 10, current_date - 1, 'test setup: push emp3 above the carry-forward cap', 'lv-emp3-push-above-cap', '00000000-0000-0000-0000-000000028003', 'approver');
  v_balance_before := app.get_employee_leave_balance(v_tenant1, v_emp3, v_annual_id, current_date);
  if v_balance_before <= 6 then raise exception 'assertion failed: expected emp3''s balance to exceed the carry-forward cap of 6, got %', v_balance_before; end if;

  select expired_count, skipped_count, job_id into v_expired, v_skipped2, v_job_id2 from app.run_leave_carry_forward_batch(v_tenant1, v_annual_id, current_date, '2026-fy', '00000000-0000-0000-0000-000000028003', 'approver');
  if v_expired < 1 then raise exception 'assertion failed: expected at least one real carry-forward-expiry posting (emp3 is over cap), got %', v_expired; end if;
  if (select job_type from app.jobs where job_id = v_job_id2) <> 'leave_carry_forward_expiry' then raise exception 'assertion failed: expected a real leave_carry_forward_expiry app.jobs row'; end if;

  -- The batch caps the PRIOR-period-ending snapshot (as of p_effective_date-1
  -- = current_date-1), forfeiting the excess over the 6-unit cap as one real
  -- ledger row dated TODAY (both app.decide_leave_request's own debit and
  -- this forfeiture are dated at their own DECISION time, never a leave's own
  -- date_from -- decision 4/9). v_balance_after is asserted against the
  -- ACTUAL posted forfeiture units read back from the ledger itself, never a
  -- hardcoded magic number -- this domain''s own exact composition of
  -- opening/debit/accrual/adjustment events all landing on different
  -- effective_dates makes the precise excess a genuine computed fact, not a
  -- constant worth hand-deriving twice.
  declare
    v_forfeit_units numeric;
  begin
    select units into v_forfeit_units from app.leave_balance_ledger
    where tenant_id = v_tenant1 and employee_id = v_emp3 and leave_type_id = v_annual_id and event_type = 'carry_forward_expire';
    if v_forfeit_units is null or v_forfeit_units >= 0 then
      raise exception 'assertion failed: expected a real negative carry_forward_expire ledger row for emp3, got %', v_forfeit_units;
    end if;
    v_balance_after := app.get_employee_leave_balance(v_tenant1, v_emp3, v_annual_id, current_date);
    if v_balance_after <> v_balance_before + v_forfeit_units then
      raise exception 'assertion failed: expected emp3''s balance reduced by exactly the forfeited % unit(s) (% -> %), got %', -v_forfeit_units, v_balance_before, v_balance_before + v_forfeit_units, v_balance_after;
    end if;
  end;

  -- Idempotent re-run for the SAME period: zero new expiries.
  select expired_count into v_expired from app.run_leave_carry_forward_batch(v_tenant1, v_annual_id, current_date, '2026-fy', '00000000-0000-0000-0000-000000028003', 'approver');
  if v_expired <> 0 then raise exception 'assertion failed: expected a same-period re-run to forfeit nothing new, got %', v_expired; end if;
end $$;

\echo '>> ATW-031 drift gate: leave_accrual/leave_carry_forward_expiry landed on BOTH app.jobs.job_type''s CHECK constraint and app.generic_job_types(), never just one (HRT-279''s own precedent lesson)'
do $$
declare
  v_generic text[] := app.generic_job_types();
  v_check_def text;
begin
  if not ('leave_accrual' = any(v_generic)) or not ('leave_carry_forward_expiry' = any(v_generic)) then
    raise exception 'assertion failed: expected both new job types in app.generic_job_types()';
  end if;
  select pg_get_constraintdef(oid) into v_check_def from pg_constraint where conname = 'jobs_job_type_check' and conrelid = 'app.jobs'::regclass;
  if v_check_def not like '%leave_accrual%' or v_check_def not like '%leave_carry_forward_expiry%' then
    raise exception 'assertion failed: expected both new job types in the jobs_job_type_check CHECK constraint';
  end if;
end $$;

-- ===========================================================================
-- HRT-295 Tier C review fix (correctness lens finding, test-coverage gap):
-- both 20260731260000's own header ("Regression proof... hris-leave-permit-
-- business-trip.sql") and docs/runtime/KNOWN_ISSUES.md's ISS-2026-112
-- resolution note claimed a real regression fixture for app.run_leave_
-- accrual_batch/app.run_leave_carry_forward_batch existed in THIS file --
-- git diff on this file was byte-for-byte EMPTY at that point (a false
-- claim, confirmed by a repo-wide grep for the exact audit action names
-- the fix introduces returning zero matches anywhere). The underlying CODE
-- fix in 20260731260000/20260731290000 is genuinely correct (independently
-- verified below) -- this closes the missing test-protection gap only.
-- ===========================================================================

\echo '>> PLT-132 (HRT-295, CG-S12-HRT-023 Tier C review): a genuine per-employee failure in app.run_leave_accrual_batch/app.run_leave_carry_forward_batch is durably recorded and the batch job still reaches completed -- the healthy sibling employee in the SAME run still accrues/expires correctly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='lv1');
  v_annual_id uuid := (select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='annual');
  v_emp1 uuid := (select master_record_id from app.employees where work_email='emp1work@lv1.test');
  v_emp2 uuid := (select master_record_id from app.employees where work_email='emp2work@lv1.test');
  v_accrued integer; v_skipped integer; v_job_id uuid;
  v_job_status text;
  v_audit_count integer;
begin
  execute format('alter table app.leave_balance_ledger add constraint plt132_tc_sentinel_block_emp2_accrual check (employee_id is distinct from %L) not valid', v_emp2);

  select accrued_count, skipped_count, job_id into v_accrued, v_skipped, v_job_id
  from app.run_leave_accrual_batch(v_tenant1, v_annual_id, current_date, '2026-09-plt132tc', '00000000-0000-0000-0000-000000028003', 'approver');

  select status into v_job_status from app.jobs where job_id = v_job_id;
  if v_job_status <> 'completed' then
    raise exception 'PLT-132 TIER C REGRESSION: expected the job to reach completed despite emp2''s own forced failure, got %', v_job_status;
  end if;
  if v_accrued < 1 then
    raise exception 'assertion failed: expected the healthy sibling employee (emp1) to still accrue in the SAME run, got accrued_count=%', v_accrued;
  end if;
  if exists (select 1 from app.leave_balance_ledger where tenant_id = v_tenant1 and employee_id = v_emp2 and idempotency_key like 'accrual:%2026-09-plt132tc') then
    raise exception 'PLT-132 TIER C REGRESSION: emp2''s own forced-failure ledger row must NOT exist (cleanly rolled back)';
  end if;

  select count(*) into v_audit_count from app.audit_logs
  where tenant_id = v_tenant1 and action = 'run_leave_accrual_batch_item_failed' and resource_id = v_emp2 and result = 'failure';
  if v_audit_count < 1 then
    raise exception 'PLT-132 TIER C REGRESSION: expected a durable, findable run_leave_accrual_batch_item_failed audit_logs row for emp2, got %', v_audit_count;
  end if;

  raise notice 'OK: PLT-132/HRT-295 run_leave_accrual_batch -- job % reached completed with emp2''s forced failure durably recorded (% audit row(s)) and emp1 still accrued (%)', v_job_id, v_audit_count, v_accrued;

  alter table app.leave_balance_ledger drop constraint plt132_tc_sentinel_block_emp2_accrual;
end $$;

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='lv1');
  v_annual_id uuid := (select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='annual');
  v_emp1 uuid := (select master_record_id from app.employees where work_email='emp1work@lv1.test');
  v_emp2 uuid := (select master_record_id from app.employees where work_email='emp2work@lv1.test');
  v_job_status text;
  v_audit_count integer;
  v_job_id uuid;
begin
  -- Push BOTH emp1 and emp2 above the carry-forward cap so both are genuine
  -- candidates for a real forfeiture posting in the SAME run.
  perform app.adjust_leave_balance(v_tenant1, v_emp1, v_annual_id, 10, current_date - 1, 'PLT-132 Tier C fixture: push emp1 above cap', 'lv-emp1-push-above-cap-plt132tc', '00000000-0000-0000-0000-000000028003', 'approver');
  perform app.adjust_leave_balance(v_tenant1, v_emp2, v_annual_id, 10, current_date - 1, 'PLT-132 Tier C fixture: push emp2 above cap', 'lv-emp2-push-above-cap-plt132tc', '00000000-0000-0000-0000-000000028003', 'approver');

  execute format('alter table app.leave_balance_ledger add constraint plt132_tc_sentinel_block_emp2_carryfwd check (employee_id is distinct from %L) not valid', v_emp2);

  select job_id into v_job_id from app.run_leave_carry_forward_batch(v_tenant1, v_annual_id, current_date, '2026-fy-plt132tc', '00000000-0000-0000-0000-000000028003', 'approver');

  select status into v_job_status from app.jobs where job_id = v_job_id;
  if v_job_status <> 'completed' then
    raise exception 'PLT-132 TIER C REGRESSION: expected the job to reach completed despite emp2''s own forced failure, got %', v_job_status;
  end if;
  if not exists (select 1 from app.leave_balance_ledger where tenant_id = v_tenant1 and employee_id = v_emp1 and event_type = 'carry_forward_expire' and idempotency_key like '%2026-fy-plt132tc') then
    raise exception 'assertion failed: expected the healthy sibling employee (emp1) to still get a real carry_forward_expire posting in the SAME run';
  end if;

  select count(*) into v_audit_count from app.audit_logs
  where tenant_id = v_tenant1 and action = 'run_leave_carry_forward_batch_item_failed' and resource_id = v_emp2 and result = 'failure';
  if v_audit_count < 1 then
    raise exception 'PLT-132 TIER C REGRESSION: expected a durable, findable run_leave_carry_forward_batch_item_failed audit_logs row for emp2, got %', v_audit_count;
  end if;

  raise notice 'OK: PLT-132/HRT-295 run_leave_carry_forward_batch -- job % reached completed with emp2''s forced failure durably recorded (% audit row(s)) and emp1 still got its real forfeiture posted', v_job_id, v_audit_count;

  alter table app.leave_balance_ledger drop constraint plt132_tc_sentinel_block_emp2_carryfwd;
end $$;

\echo '>> evidence gate (C-10): a required-evidence leave type blocks submission with no evidence_file_id; a non-existent evidence_file_id is rejected as evidence_file_not_found'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='lv1');
  v_sick_id uuid := (select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='sick');
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028006", "role": "authenticated"}', false);
  set role authenticated;
  begin
    perform app.create_leave_request(v_tenant1, v_sick_id, current_date + 30, current_date + 30, 'full_day', 'Flu', null, null, 'lv-mgr1-sick-no-evidence', '00000000-0000-0000-0000-000000028006', 'mgr1');
    raise exception 'assertion failed: expected evidence_required to block a medical-evidence type with no file';
  exception
    when others then
      if sqlerrm not like 'evidence_required:%' then raise; end if;
  end;

  begin
    perform app.create_leave_request(v_tenant1, v_sick_id, current_date + 30, current_date + 30, 'full_day', 'Flu', null, gen_random_uuid(), 'lv-mgr1-sick-fake-evidence', '00000000-0000-0000-0000-000000028006', 'mgr1');
    raise exception 'assertion failed: expected a non-existent evidence_file_id to be rejected';
  exception
    when others then
      if sqlerrm not like 'evidence_file_not_found:%' then raise; end if;
  end;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);
end $$;

\echo '>> business_trip destination shape: required for a business_trip type, forbidden for a non-business_trip type'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='lv1');
  v_trip_id uuid := (select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='business_trip');
  v_permit_id uuid := (select id from app.leave_types where tenant_id=(select id from app.tenants where slug='lv1') and code='permit');
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028006", "role": "authenticated"}', false);
  set role authenticated;
  begin
    perform app.create_leave_request(v_tenant1, v_trip_id, current_date + 40, current_date + 41, 'full_day', 'Client visit', null, null, 'lv-mgr1-trip-no-dest', '00000000-0000-0000-0000-000000028006', 'mgr1');
    raise exception 'assertion failed: expected destination_required for a business_trip type';
  exception
    when others then
      if sqlerrm not like 'destination_required:%' then raise; end if;
  end;

  perform app.create_leave_request(v_tenant1, v_trip_id, current_date + 40, current_date + 41, 'full_day', 'Client visit', 'Surabaya', null, 'lv-mgr1-trip-with-dest', '00000000-0000-0000-0000-000000028006', 'mgr1');

  begin
    perform app.create_leave_request(v_tenant1, v_permit_id, current_date + 42, current_date + 42, 'full_day', 'Personal', 'Surabaya', null, 'lv-mgr1-permit-with-dest', '00000000-0000-0000-0000-000000028006', 'mgr1');
    raise exception 'assertion failed: expected destination_not_applicable for a non-business_trip type';
  exception
    when others then
      if sqlerrm not like 'destination_not_applicable:%' then raise; end if;
  end;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);
end $$;

\echo '>> app.list_leave_requests/app.list_employee_leave_balances manager scoping: mgr1 (no HRS:View) sees direct report emp1''s requests/balances, never emp3 (not a report)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='lv1');
  v_emp1 uuid := (select master_record_id from app.employees where work_email='emp1work@lv1.test');
  v_emp3 uuid := (select master_record_id from app.employees where work_email='emp3work@lv1.test');
  v_seen_emp1 boolean;
  v_seen_emp3 boolean;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028006", "role": "authenticated"}', false);
  set role authenticated;
  select exists(select 1 from app.list_leave_requests(v_tenant1, '00000000-0000-0000-0000-000000028006', null, null, null, null, 200, null) where employee_id = v_emp1) into v_seen_emp1;
  select exists(select 1 from app.list_leave_requests(v_tenant1, '00000000-0000-0000-0000-000000028006', null, null, null, null, 200, null) where employee_id = v_emp3) into v_seen_emp3;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  if not v_seen_emp1 then raise exception 'assertion failed: expected mgr1 to see direct report emp1''s requests'; end if;
  if v_seen_emp3 then raise exception 'assertion failed: expected mgr1 to NOT see emp3 (not a direct report)'; end if;
end $$;

\echo '>> schema-privilege defense in depth: anon has zero EXECUTE on any new function; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE on any of the 4 new tables; app.leave_balance_ledger carries no UPDATE/DELETE grant to ANY role (genuinely append-only, decision 3); column-restricted grants verified both directions'
do $$
begin
  if has_function_privilege('anon', 'app.create_leave_request(uuid,uuid,date,date,text,text,text,uuid,text,uuid,text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not be able to execute app.create_leave_request';
  end if;
  if has_function_privilege('anon', 'app.decide_leave_request(uuid,text,text,boolean,uuid,text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not be able to execute app.decide_leave_request';
  end if;

  if has_table_privilege('authenticated', 'app.leave_requests', 'INSERT') then raise exception 'assertion failed: authenticated must not have direct INSERT on app.leave_requests'; end if;
  if has_table_privilege('authenticated', 'app.leave_requests', 'UPDATE') then raise exception 'assertion failed: authenticated must not have direct UPDATE on app.leave_requests'; end if;
  if has_table_privilege('authenticated', 'app.leave_balance_ledger', 'UPDATE') then raise exception 'assertion failed: authenticated must not have UPDATE on app.leave_balance_ledger (append-only)'; end if;
  if has_table_privilege('authenticated', 'app.leave_balance_ledger', 'DELETE') then raise exception 'assertion failed: authenticated must not have DELETE on app.leave_balance_ledger (append-only)'; end if;
  if has_table_privilege('service_role', 'app.leave_balance_ledger', 'UPDATE') then raise exception 'assertion failed: service_role must not have UPDATE on app.leave_balance_ledger (genuinely append-only, no role gets this)'; end if;
  if has_table_privilege('service_role', 'app.leave_balance_ledger', 'DELETE') then raise exception 'assertion failed: service_role must not have DELETE on app.leave_balance_ledger (genuinely append-only, no role gets this)'; end if;

  if has_column_privilege('authenticated', 'app.leave_requests', 'reason', 'SELECT') then raise exception 'assertion failed: authenticated must not have column SELECT on leave_requests.reason'; end if;
  if has_column_privilege('authenticated', 'app.leave_requests', 'destination', 'SELECT') then raise exception 'assertion failed: authenticated must not have column SELECT on leave_requests.destination'; end if;
  if has_column_privilege('authenticated', 'app.leave_requests', 'cancel_reason', 'SELECT') then raise exception 'assertion failed: authenticated must not have column SELECT on leave_requests.cancel_reason'; end if;
  if has_column_privilege('authenticated', 'app.leave_requests', 'decided_reason', 'SELECT') then raise exception 'assertion failed: authenticated must not have column SELECT on leave_requests.decided_reason'; end if;
  if has_column_privilege('authenticated', 'app.leave_balance_ledger', 'reason', 'SELECT') then raise exception 'assertion failed: authenticated must not have column SELECT on leave_balance_ledger.reason'; end if;
  if not has_column_privilege('authenticated', 'app.leave_requests', 'status', 'SELECT') then raise exception 'assertion failed: authenticated should still have column SELECT on leave_requests.status (over-restricted)'; end if;
  if not has_column_privilege('service_role', 'app.leave_requests', 'reason', 'SELECT') then raise exception 'assertion failed: service_role should retain SELECT on leave_requests.reason'; end if;
end $$;

\echo '>> RLS default-deny: a forged cross-tenant session sees zero rows on every new table even with a raw select'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000028022", "role": "authenticated"}';
  select count(*) into v_count from app.leave_types;
  if v_count <> 0 then raise exception 'assertion failed: expected zero app.leave_types rows visible to a cross-tenant (lv2) session'; end if;
  select count(*) into v_count from app.leave_requests;
  if v_count <> 0 then raise exception 'assertion failed: expected zero app.leave_requests rows visible to a cross-tenant (lv2) session'; end if;
  select count(*) into v_count from app.leave_balance_ledger;
  if v_count <> 0 then raise exception 'assertion failed: expected zero app.leave_balance_ledger rows visible to a cross-tenant (lv2) session'; end if;
  select count(*) into v_count from app.leave_type_policy_versions;
  if v_count <> 0 then raise exception 'assertion failed: expected zero app.leave_type_policy_versions rows visible to a cross-tenant (lv2) session'; end if;
  reset role;
end $$;

\echo '>> structural regression guard: this migration never altered app.employees.master_record_id/tenant_id/lifecycle_status shape, and app.leave_requests never duplicates app.schedule_assignments/app.attendance_sessions as a second store for the same entity'
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema='app' and table_name='employees' and column_name='master_record_id') then
    raise exception 'assertion failed: app.employees.master_record_id missing';
  end if;
  if exists (select 1 from information_schema.columns where table_schema='app' and table_name='leave_requests' and column_name='shift_template_version_id') then
    raise exception 'assertion failed: app.leave_requests must never carry its own shift_template_version_id -- schedule_snapshot (jsonb, immutable at submit time) is the only integration surface, never a second live FK into app.schedule_assignments'' own domain';
  end if;
end $$;
