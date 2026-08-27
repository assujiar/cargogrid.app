-- Real, executable test evidence for HRT-281 (Overtime and Timesheet,
-- CG-S12-HRT-009) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Mirrors scripts/db-tests/hris-attendance.sql's own
-- two-tenant cross-isolation convention.
--
-- Self-contained: own two-tenant/employee/policy fixture, own fresh,
-- unclaimed UUID range (00000000-0000-0000-0000-0000000281xx), never
-- colliding with any sibling HRIS test file's own claimed range (grep-
-- verified against every existing scripts/db-tests/*.sql file before
-- authoring this one).
--
-- Disclosed scope boundary (not silently narrowed): a fully realistic
-- Operations app.job_orders/app.shipment_orders row requires a 4+ level
-- Commercial pipeline fixture (opportunity -> prospect -> quotation ->
-- job_order_handoff -> job_order), well outside this checkpoint's own
-- chartered HRIS scope to construct. This file proves the NEGATIVE path
-- (a non-existent job/shipment reference id is rejected, the real security
-- property "authorized independently" protects) with a random UUID; the
-- POSITIVE "a real reference is accepted and its number/status projected"
-- path is verified by direct code review of app._validate_overtime_
-- timesheet_operations_reference (a simple two-predicate existence+tenant
-- check) rather than by a live fixture, per the build log's own disclosure.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (ot1, ot2). ot1 gets a tenant_admin, HR staff (HRS Create/Edit/View/Export/Import), an approver (HRS Approve/View/Override/View payroll), three active employees (emp1, emp2, mgr1 -- emp1 reports to mgr1, emp2 has no manager relation), a published attendance policy, and a published overtime policy. ot2 gets a tenant_admin, an HR actor with full authority, and one active employee for cross-tenant checks. A global Supreme Admin is also seeded.'
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
  v_att_policy app.attendance_policies;
  v_att_version app.attendance_policy_versions;
  v_ot_policy app.overtime_policies;
  v_ot_version app.overtime_policy_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000028101', 'admin@ot1.test'),
    ('00000000-0000-0000-0000-000000028102', 'staff@ot1.test'),
    ('00000000-0000-0000-0000-000000028103', 'approver@ot1.test'),
    ('00000000-0000-0000-0000-000000028104', 'emp1@ot1.test'),
    ('00000000-0000-0000-0000-000000028105', 'emp2@ot1.test'),
    ('00000000-0000-0000-0000-000000028106', 'mgr1@ot1.test'),
    ('00000000-0000-0000-0000-000000028121', 'admin@ot2.test'),
    ('00000000-0000-0000-0000-000000028122', 'emp1@ot2.test'),
    ('00000000-0000-0000-0000-000000028123', 'hr@ot2.test'),
    ('00000000-0000-0000-0000-000000028199', 'supreme@ot.test');

  perform app.provision_tenant('ot1', 'OT Co 1', 'idem-ot1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'ot1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('ot2', 'OT Co 2', 'idem-ot2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'ot2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028101', 'admin@ot1.test', 'Ot1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@ot1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028102', 'staff@ot1.test', 'Ot1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@ot1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028103', 'approver@ot1.test', 'Ot1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@ot1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028104', 'emp1@ot1.test', 'Ot1 Emp One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp1@ot1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028105', 'emp2@ot1.test', 'Ot1 Emp Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp2@ot1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028106', 'mgr1@ot1.test', 'Ot1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'mgr1@ot1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000028121', 'admin@ot2.test', 'Ot2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@ot2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028121', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000028122', 'emp1@ot2.test', 'Ot2 Emp One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp1@ot2.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000028123', 'hr@ot2.test', 'Ot2 HR', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'hr@ot2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028199', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'HRS Staff', 'Create/Edit/View/Export/Import', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View', 'Export', 'Import')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000028102', '00000000-0000-0000-0000-000000028101', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'HRS Approver', 'Approve/View/Override/View payroll', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Approve', 'View', 'Override', 'View payroll')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000028103', '00000000-0000-0000-0000-000000028101', 'tester');

  v_t2_role := (app.create_role(v_tenant2, 'HRS Staff T2', 'Create/Edit/View/Approve/Override/View payroll', 'tester')).id;
  v_t2_draft := app.create_role_version(v_t2_role, 'tester');
  perform app.set_role_version_permissions(v_t2_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View', 'Approve', 'Override', 'View payroll')), 'tester');
  perform app.publish_role_version(v_t2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'), '00000000-0000-0000-0000-000000028123', '00000000-0000-0000-0000-000000028121', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-OT1', 'Ot1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-OT1', 'Ot1 Branch', 'tester')).id;
  perform app.create_org_unit(v_tenant2, 'company', null, 'CO-OT2', 'Ot2 Co', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Ot1 Manager', 'full_time', 'mgr1work@ot1.test', 'mgr1p@ot1.test', '0800000002', null, null, null, '2024-01-01', v_company, v_branch, null, 'Warehouse Manager', null, (select id from app.users where email = 'mgr1@ot1.test'), null, 'hr_created', 'idem-mgr1-ot1', '00000000-0000-0000-0000-000000028102', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@ot1.test'), 'Contact Mgr', 'spouse', '0810000002', null, true, '00000000-0000-0000-0000-000000028102', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@ot1.test'), 1, '00000000-0000-0000-0000-000000028102', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@ot1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028103', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@ot1.test'), 3, '00000000-0000-0000-0000-000000028103', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Ot1 Emp One', 'full_time', 'emp1work@ot1.test', 'emp1p@ot1.test', '0800000001', null, null, null, '2024-01-01', v_company, v_branch, null, 'Warehouse Staff', null, (select id from app.users where email = 'emp1@ot1.test'), null, 'hr_created', 'idem-emp1-ot1', '00000000-0000-0000-0000-000000028102', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@ot1.test'), 'Contact One', 'spouse', '0810000001', null, true, '00000000-0000-0000-0000-000000028102', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@ot1.test'), 1, '00000000-0000-0000-0000-000000028102', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@ot1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028103', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@ot1.test'), 3, '00000000-0000-0000-0000-000000028103', 'tester');
  -- emp1's manager is mgr1 (manager/team-scope tests below).
  perform app.transfer_employee(
    (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@ot1.test'), 4,
    v_company, v_branch, null, 'Warehouse Staff', (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@ot1.test'),
    'reorg', '00000000-0000-0000-0000-000000028102', 'tester'
  );

  perform app.create_employee_draft(v_tenant1, 'Ot1 Emp Two', 'full_time', 'emp2work@ot1.test', 'emp2p@ot1.test', '0800000003', null, null, null, '2024-01-01', v_company, v_branch, null, 'Warehouse Staff', null, (select id from app.users where email = 'emp2@ot1.test'), null, 'hr_created', 'idem-emp2-ot1', '00000000-0000-0000-0000-000000028102', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@ot1.test'), 'Contact Two', 'spouse', '0810000003', null, true, '00000000-0000-0000-0000-000000028102', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@ot1.test'), 1, '00000000-0000-0000-0000-000000028102', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@ot1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028103', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@ot1.test'), 3, '00000000-0000-0000-0000-000000028103', 'tester');

  perform app.create_employee_draft(v_tenant2, 'Ot2 Emp One', 'full_time', 'emp1work@ot2.test', 'emp1p@ot2.test', '0800000004', null, null, null, '2024-01-01', (select id from app.org_units where tenant_id = v_tenant2 and code = 'CO-OT2'), null, null, 'Staff', null, (select id from app.users where email = 'emp1@ot2.test'), null, 'hr_created', 'idem-emp1-ot2', '00000000-0000-0000-0000-000000028123', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@ot2.test'), 'Contact Two', 'spouse', '0810000004', null, true, '00000000-0000-0000-0000-000000028123', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@ot2.test'), 1, '00000000-0000-0000-0000-000000028123', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@ot2.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028123', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@ot2.test'), 3, '00000000-0000-0000-0000-000000028123', 'tester');

  -- Attendance policy (HRT-278), tenant-wide, published -- needed for
  -- actual-time reconciliation evidence.
  v_att_policy := app.create_attendance_policy(v_tenant1, null, 'Ot1 Attendance', '00000000-0000-0000-0000-000000028102', 'tester');
  v_att_version := app.create_attendance_policy_version(
    v_att_policy.id, 'Asia/Jakarta', '08:00:00'::time, '17:00:00'::time, '04:00:00'::time, 15, 15,
    array['mobile_web', 'kiosk']::text[], 'none', null, null, 16, '2024-01-01'::date,
    '00000000-0000-0000-0000-000000028102', 'tester'
  );
  perform app.publish_attendance_policy_version(v_att_version.id, 1, '00000000-0000-0000-0000-000000028103', 'tester');

  -- Overtime policy, tenant-wide, published: 15-minute nearest rounding,
  -- 30-minute minimum threshold, 180-minute daily cap, 600-minute weekly
  -- cap, 480-minute standard workday baseline.
  v_ot_policy := app.create_overtime_policy(v_tenant1, null, 'Ot1 Overtime', '00000000-0000-0000-0000-000000028102', 'tester');
  v_ot_version := app.create_overtime_policy_version(v_ot_policy.id, 15, 'nearest', 30, 180, 600, 480, 0, true, '2024-01-01'::date, '00000000-0000-0000-0000-000000028102', 'tester');
  perform app.publish_overtime_policy_version(v_ot_version.id, 1, '00000000-0000-0000-0000-000000028103', 'tester');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end $$;

\echo '>> policy resolution: published tenant-wide overtime policy resolves for emp1'
do $$
declare
  v_resolved app.overtime_policy_versions;
begin
  select * into v_resolved from app.resolve_effective_overtime_policy_version(
    (select id from app.tenants where slug = 'ot1'),
    (select branch_org_unit_id from app.employees where work_email = 'emp1work@ot1.test'),
    current_date
  ) limit 1;
  if v_resolved.rounding_increment_minutes <> 15 then
    raise exception 'assertion failed: expected a resolved policy with rounding_increment_minutes=15, got none/different';
  end if;
end $$;

\echo '>> round_minutes: nearest/up/down all compute correctly against a 15-minute increment'
do $$
begin
  if app.round_minutes(37, 15, 'nearest') <> 30 then raise exception 'assertion failed: nearest(37,15) expected 30, got %', app.round_minutes(37, 15, 'nearest'); end if;
  if app.round_minutes(38, 15, 'nearest') <> 45 then raise exception 'assertion failed: nearest(38,15) expected 45, got %', app.round_minutes(38, 15, 'nearest'); end if;
  if app.round_minutes(31, 15, 'up') <> 45 then raise exception 'assertion failed: up(31,15) expected 45, got %', app.round_minutes(31, 15, 'up'); end if;
  if app.round_minutes(44, 15, 'down') <> 30 then raise exception 'assertion failed: down(44,15) expected 30, got %', app.round_minutes(44, 15, 'down'); end if;
end $$;

\echo '>> clock in/out emp1 (real evidence, then adjust the underlying row to a realistic 10-hour span -- app.record_attendance_clock_event always uses clock_timestamp(), never the caller-reported time, by design)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
select app.record_attendance_clock_event((select id from app.tenants where slug = 'ot1'), 'clock_in', 'mobile_web', now(), null, null, 'ci-emp1', '00000000-0000-0000-0000-000000028104', 'emp1');
select app.record_attendance_clock_event((select id from app.tenants where slug = 'ot1'), 'clock_out', 'mobile_web', now(), null, null, 'co-emp1', '00000000-0000-0000-0000-000000028104', 'emp1');
reset role;
select set_config('request.jwt.claims', 'null', false);

-- Pin the session to the most recent weekday, keeping the same 10-hour span. work_date is
-- stamped from the server clock by app.record_attendance_clock_event (never the caller-reported
-- time, by design), so on a Saturday or Sunday run the server correctly classifies the overtime
-- below as `weekend` and this file's `eligible_classification = 'weekday'` assertion fails. That
-- is a defect in the test, not in the code: the classification logic is right, the fixture just
-- has to land on a weekday to assert the weekday branch. Verified failing on Sunday 2026-08-23.
update app.attendance_sessions s
set work_date = wd.d,
    raw_clock_in_at = (wd.d + time '08:00')::timestamptz,
    raw_clock_out_at = (wd.d + time '18:00')::timestamptz
from (
  select current_date - (case extract(isodow from current_date)::int
                           when 6 then 1   -- Saturday -> Friday
                           when 7 then 2   -- Sunday   -> Friday
                           else 0 end) as d
) wd
where s.tenant_id = (select id from app.tenants where slug = 'ot1') and s.employee_id = (select master_record_id from app.employees where work_email = 'emp1work@ot1.test');

\echo '>> emp1 (self, no p_employee_id parameter exists to spoof) creates and submits a planned overtime request for the SAME work_date -- reconciliation matches the real 10h-minus-8h-baseline = 120 minutes'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_work_date date := (select work_date from app.attendance_sessions where tenant_id = (select id from app.tenants where slug = 'ot1') and employee_id = (select master_record_id from app.employees where work_email = 'emp1work@ot1.test'));
  v_req app.overtime_requests;
begin
  v_req := app.create_overtime_request(
    v_tenant, 'planned', (v_work_date::text || ' 17:00:00')::timestamptz, (v_work_date::text || ' 19:00:00')::timestamptz,
    0, 'project deadline', null, null, null, 'ot-req-1', '00000000-0000-0000-0000-000000028104', 'emp1'
  );
  if v_req.status <> 'draft' or v_req.requested_minutes <> 120 then
    raise exception 'assertion failed: expected draft/120 requested minutes, got %/%', v_req.status, v_req.requested_minutes;
  end if;

  v_req := app.submit_overtime_request(v_req.id, v_req.record_version, '00000000-0000-0000-0000-000000028104', 'emp1');
  if v_req.status <> 'pending_approval' or v_req.reconciliation_status <> 'matched' or v_req.reconciled_actual_minutes <> 120 then
    raise exception 'assertion failed: expected pending_approval/matched/120, got %/%/%', v_req.status, v_req.reconciliation_status, v_req.reconciled_actual_minutes;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> C-01 idempotency: an identical replay of the same key returns the SAME request; a same-key-different-window replay is rejected'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_work_date date := (select work_date from app.attendance_sessions where tenant_id = (select id from app.tenants where slug = 'ot1') and employee_id = (select master_record_id from app.employees where work_email = 'emp1work@ot1.test'));
  v_original_id uuid := (select id from app.overtime_requests where idempotency_key = 'ot-req-1');
  v_replay app.overtime_requests;
begin
  v_replay := app.create_overtime_request(
    v_tenant, 'planned', (v_work_date::text || ' 17:00:00')::timestamptz, (v_work_date::text || ' 19:00:00')::timestamptz,
    0, 'project deadline', null, null, null, 'ot-req-1', '00000000-0000-0000-0000-000000028104', 'emp1'
  );
  if v_replay.id <> v_original_id then
    raise exception 'assertion failed: identical replay should return the SAME row, got a different id';
  end if;

  begin
    perform app.create_overtime_request(
      v_tenant, 'planned', (v_work_date::text || ' 20:00:00')::timestamptz, (v_work_date::text || ' 21:00:00')::timestamptz,
      0, 'different window', null, null, null, 'ot-req-1', '00000000-0000-0000-0000-000000028104', 'emp1'
    );
    raise exception 'assertion failed: expected idempotency_key_conflict for a same-key-different-window replay';
  exception when others then
    if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> C-18 self-approval blocked: emp1 (also lacking HRS:Approve) cannot decide their own request'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_req_id uuid := (select id from app.overtime_requests where idempotency_key = 'ot-req-1');
  v_version integer := (select record_version from app.overtime_requests where id = (select id from app.overtime_requests where idempotency_key = 'ot-req-1'));
begin
  begin
    perform app.decide_overtime_request(v_req_id, v_version, 'approve', 'self approve attempt', null, '00000000-0000-0000-0000-000000028104', 'emp1');
    raise exception 'assertion failed: expected insufficient_authority (emp1 lacks HRS:Approve)';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> approver (HRS:Approve/View/Override/View payroll) decides -- server computes eligible=120 (rounded, under both caps), classification=weekday, approved defaults to eligible'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_req_id uuid := (select id from app.overtime_requests where idempotency_key = 'ot-req-1');
  v_version integer;
  v_req app.overtime_requests;
begin
  select record_version into v_version from app.overtime_requests where id = v_req_id;
  v_req := app.decide_overtime_request(v_req_id, v_version, 'approve', 'looks legitimate', null, '00000000-0000-0000-0000-000000028103', 'approver');
  if v_req.status <> 'approved' or v_req.eligible_minutes <> 120 or v_req.eligible_classification <> 'weekday' or v_req.approved_minutes <> 120 then
    raise exception 'assertion failed: expected approved/120/weekday/120, got %/%/%/%', v_req.status, v_req.eligible_minutes, v_req.eligible_classification, v_req.approved_minutes;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> daily cap enforcement: a fresh 4-hour (240 minute) overtime request against a 180-minute daily cap is capped at exactly 180, not 240'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028105", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_req app.overtime_requests;
begin
  v_req := app.create_overtime_request(
    v_tenant, 'planned', '2027-03-01 17:00:00+00'::timestamptz, '2027-03-01 21:00:00+00'::timestamptz,
    0, 'big push', null, null, null, 'ot-req-cap', '00000000-0000-0000-0000-000000028105', 'emp2'
  );
  v_req := app.submit_overtime_request(v_req.id, v_req.record_version, '00000000-0000-0000-0000-000000028105', 'emp2');
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_req_id uuid := (select id from app.overtime_requests where idempotency_key = 'ot-req-cap');
  v_version integer;
  v_req app.overtime_requests;
begin
  select record_version into v_version from app.overtime_requests where id = v_req_id;
  -- No matching attendance evidence exists for this employee/date -- approve
  -- anyway under HRS:Override (decision 16's own exception-flow path).
  v_req := app.decide_overtime_request(v_req_id, v_version, 'approve', 'override -- no clock device on this route', null, '00000000-0000-0000-0000-000000028103', 'approver');
  if v_req.reconciliation_status <> 'no_attendance' then
    raise exception 'assertion failed: expected no_attendance reconciliation, got %', v_req.reconciliation_status;
  end if;
  if v_req.eligible_minutes <> 180 then
    raise exception 'assertion failed: expected daily cap of 180 minutes, got %', v_req.eligible_minutes;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> attendance-evidence hard gate (decision 16): a NON-override approver cannot approve a no-attendance/mismatch request'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028105", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_req app.overtime_requests;
begin
  v_req := app.create_overtime_request(
    v_tenant, 'emergency_after_the_fact', '2027-03-02 17:00:00+00'::timestamptz, '2027-03-02 18:00:00+00'::timestamptz,
    0, 'no clock device', null, null, null, 'ot-req-noatt', '00000000-0000-0000-0000-000000028105', 'emp2'
  );
  perform app.submit_overtime_request(v_req.id, v_req.record_version, '00000000-0000-0000-0000-000000028105', 'emp2');
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028102", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_req_id uuid := (select id from app.overtime_requests where idempotency_key = 'ot-req-noatt');
begin
  -- staff@ot1 holds HRS Create/Edit/View/Export/Import -- NOT Approve, so
  -- this must fail on authority before ever reaching the override check.
  begin
    perform app.decide_overtime_request(v_req_id, 2, 'approve', 'attempt', null, '00000000-0000-0000-0000-000000028102', 'staff');
    raise exception 'assertion failed: expected insufficient_authority for a non-Approve actor';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> revision/resubmission (spec section 22, decision 19, self-found Tier B gap): once an overtime_requests/timesheet_entries row is rejected it is a terminal leaf -- submit_overtime_request/submit_timesheet_entry both require status=draft, no path back from rejected -- so the real resubmission path is create-new for the SAME work_date, live-verified here, not merely asserted in a comment'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028105", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_req1 app.overtime_requests;
  v_req2 app.overtime_requests;
begin
  v_req1 := app.create_overtime_request(
    v_tenant, 'planned', '2027-03-03 17:00:00+00'::timestamptz, '2027-03-03 19:00:00+00'::timestamptz,
    0, 'first attempt', null, null, null, 'ot-req-resubmit-1', '00000000-0000-0000-0000-000000028105', 'emp2'
  );
  v_req1 := app.submit_overtime_request(v_req1.id, v_req1.record_version, '00000000-0000-0000-0000-000000028105', 'emp2');
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_req_id uuid := (select id from app.overtime_requests where idempotency_key = 'ot-req-resubmit-1');
  v_version integer;
begin
  select record_version into v_version from app.overtime_requests where id = v_req_id;
  perform app.decide_overtime_request(v_req_id, v_version, 'reject', 'not enough workload to justify', null, '00000000-0000-0000-0000-000000028103', 'approver');
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028105", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_req1_status text := (select status from app.overtime_requests where idempotency_key = 'ot-req-resubmit-1');
  v_req2 app.overtime_requests;
begin
  if v_req1_status <> 'rejected' then
    raise exception 'assertion failed: expected the first overtime request to be rejected, got %', v_req1_status;
  end if;
  -- The active-slot unique index excludes 'rejected' from its scope, so a
  -- brand-new request for the SAME work_date is the real resubmission path.
  v_req2 := app.create_overtime_request(
    v_tenant, 'planned', '2027-03-03 17:00:00+00'::timestamptz, '2027-03-03 21:00:00+00'::timestamptz,
    0, 'revised, longer justification', null, null, null, 'ot-req-resubmit-2', '00000000-0000-0000-0000-000000028105', 'emp2'
  );
  if v_req2.status <> 'draft' or v_req2.work_date <> (select work_date from app.overtime_requests where idempotency_key = 'ot-req-resubmit-1') then
    raise exception 'assertion failed: expected a fresh draft request on the SAME work_date as the rejected one, got status=% work_date=%', v_req2.status, v_req2.work_date;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_entry1 app.timesheet_entries;
begin
  v_entry1 := app.create_timesheet_entry(v_tenant, '2027-03-06'::date, 240, 0, null, null, null, 'first attempt', 'ts-entry-resubmit-1', '00000000-0000-0000-0000-000000028104', 'emp1');
  v_entry1 := app.submit_timesheet_entry(v_entry1.id, v_entry1.record_version, '00000000-0000-0000-0000-000000028104', 'emp1');
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_entry_id uuid := (select id from app.timesheet_entries where idempotency_key = 'ts-entry-resubmit-1');
  v_version integer;
begin
  select record_version into v_version from app.timesheet_entries where id = v_entry_id;
  perform app.decide_timesheet_entry(v_entry_id, v_version, 'reject', 'hours look wrong, please recheck', null, '00000000-0000-0000-0000-000000028103', 'approver');
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_entry1_status text := (select status from app.timesheet_entries where idempotency_key = 'ts-entry-resubmit-1');
  v_entry2 app.timesheet_entries;
begin
  if v_entry1_status <> 'rejected' then
    raise exception 'assertion failed: expected the first timesheet entry to be rejected, got %', v_entry1_status;
  end if;
  v_entry2 := app.create_timesheet_entry(v_tenant, '2027-03-06'::date, 300, 0, null, null, null, 'revised, corrected hours', 'ts-entry-resubmit-2', '00000000-0000-0000-0000-000000028104', 'emp1');
  if v_entry2.status <> 'draft' or v_entry2.work_date <> '2027-03-06'::date then
    raise exception 'assertion failed: expected a fresh draft entry on the SAME work_date as the rejected one, got status=% work_date=%', v_entry2.status, v_entry2.work_date;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> multi-job timesheet allocation: emp1 logs TWO entries for the SAME work_date across different (absent, this fixture has no real Operations reference) allocations -- proves no uniqueness constraint blocks a second same-day entry'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_work_date date := (select work_date from app.attendance_sessions where tenant_id = (select id from app.tenants where slug = 'ot1') and employee_id = (select master_record_id from app.employees where work_email = 'emp1work@ot1.test'));
  v_entry1 app.timesheet_entries;
  v_entry2 app.timesheet_entries;
begin
  v_entry1 := app.create_timesheet_entry(v_tenant, v_work_date, 300, 15, null, null, null, 'morning job A', 'ts-entry-1', '00000000-0000-0000-0000-000000028104', 'emp1');
  v_entry2 := app.create_timesheet_entry(v_tenant, v_work_date, 180, 15, null, null, null, 'afternoon job B', 'ts-entry-2', '00000000-0000-0000-0000-000000028104', 'emp1');
  if v_entry1.work_date <> v_entry2.work_date then
    raise exception 'assertion failed: expected both entries on the same work_date';
  end if;
  v_entry1 := app.submit_timesheet_entry(v_entry1.id, v_entry1.record_version, '00000000-0000-0000-0000-000000028104', 'emp1');
  v_entry2 := app.submit_timesheet_entry(v_entry2.id, v_entry2.record_version, '00000000-0000-0000-0000-000000028104', 'emp1');
  if v_entry1.status <> 'pending_approval' or v_entry2.status <> 'pending_approval' then
    raise exception 'assertion failed: expected both entries submitted';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> Operations reference authorized independently (decision 8): a non-existent job_order_id is rejected'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
begin
  begin
    perform app.create_timesheet_entry(v_tenant, current_date, 60, 0, gen_random_uuid(), null, null, 'bad job ref', 'ts-badjob', '00000000-0000-0000-0000-000000028104', 'emp1');
    raise exception 'assertion failed: expected job_order_not_found for a fabricated job_order_id';
  exception when others then
    if sqlerrm not like 'job_order_not_found%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> approver decides both timesheet entries; a manager (mgr1, no HRS:View/Approve) can SEE emp1''s entries via the manager-scope list but staff@ot1 (no relation) list-with-explicit-filter is denied'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_entry1_id uuid := (select id from app.timesheet_entries where idempotency_key = 'ts-entry-1');
  v_entry2_id uuid := (select id from app.timesheet_entries where idempotency_key = 'ts-entry-2');
  v_entry app.timesheet_entries;
  v_version integer;
begin
  select record_version into v_version from app.timesheet_entries where id = v_entry1_id;
  v_entry := app.decide_timesheet_entry(v_entry1_id, v_version, 'approve', 'ok', null, '00000000-0000-0000-0000-000000028103', 'approver');
  if v_entry.eligible_minutes <> 285 or v_entry.approved_minutes <> 285 then
    raise exception 'assertion failed: expected eligible=285 (300-15 break), got %', v_entry.eligible_minutes;
  end if;

  select record_version into v_version from app.timesheet_entries where id = v_entry2_id;
  v_entry := app.decide_timesheet_entry(v_entry2_id, v_version, 'approve', 'ok', null, '00000000-0000-0000-0000-000000028103', 'approver');
  if v_entry.eligible_minutes <> 165 or v_entry.approved_minutes <> 165 then
    raise exception 'assertion failed: expected eligible=165 (180-15 break), got %', v_entry.eligible_minutes;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> manager scoping (mandatory reading: reuse the roster''s own manager-scope resolution): mgr1 (no HRS:View) sees emp1''s entries via list_timesheet_entries; emp2 (unrelated) is denied when filtered explicitly'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028106", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_emp1_id uuid := (select master_record_id from app.employees where work_email = 'emp1work@ot1.test');
  v_count integer;
begin
  select count(*) into v_count from app.list_timesheet_entries(v_tenant, '00000000-0000-0000-0000-000000028106', v_emp1_id, null, null, null, 50, null);
  if v_count < 2 then
    raise exception 'assertion failed: expected mgr1 to see at least 2 of emp1''s entries via manager scope, got %', v_count;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028105", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_emp1_id uuid := (select master_record_id from app.employees where work_email = 'emp1work@ot1.test');
  v_count integer;
begin
  -- emp2 has no HRS:View and is not emp1's manager -- explicit filter to
  -- emp1's own id must return zero rows.
  select count(*) into v_count from app.list_timesheet_entries(v_tenant, '00000000-0000-0000-0000-000000028105', v_emp1_id, null, null, null, 50, null);
  if v_count <> 0 then
    raise exception 'assertion failed: expected 0 rows for an unrelated, unprivileged caller filtering to emp1, got %', v_count;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> period lock/reopen workflow: HR creates a period, emp1 submits their own summary, approver approves it, HR locks the period -- then a NEW submission for a date in-range is blocked until the period is reopened'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028102", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_work_date date := (select work_date from app.attendance_sessions where tenant_id = (select id from app.tenants where slug = 'ot1') and employee_id = (select master_record_id from app.employees where work_email = 'emp1work@ot1.test'));
  v_period app.timesheet_periods;
begin
  v_period := app.create_timesheet_period(v_tenant, null, 'PERIOD-2027-01', v_work_date - 10, v_work_date + 10, '00000000-0000-0000-0000-000000028102', 'staff');
  if v_period.status <> 'open' then
    raise exception 'assertion failed: expected a freshly created period to be open';
  end if;

  -- Overlap rejected.
  begin
    perform app.create_timesheet_period(v_tenant, null, 'PERIOD-OVERLAP', v_work_date - 1, v_work_date + 1, '00000000-0000-0000-0000-000000028102', 'staff');
    raise exception 'assertion failed: expected timesheet_period_overlap';
  exception when others then
    if sqlerrm not like 'timesheet_period_overlap%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_period_id uuid := (select id from app.timesheet_periods where code = 'PERIOD-2027-01');
  v_emp1_id uuid := (select master_record_id from app.employees where work_email = 'emp1work@ot1.test');
  v_summary app.timesheet_period_summaries;
begin
  v_summary := app.submit_timesheet_period_summary(v_period_id, v_emp1_id, '00000000-0000-0000-0000-000000028104', 'emp1');
  if v_summary.status <> 'submitted' or v_summary.total_regular_minutes <> 450 or v_summary.total_overtime_weekday_minutes <> 120 then
    raise exception 'assertion failed: expected submitted/regular=450/ot_weekday=120, got %/%/%', v_summary.status, v_summary.total_regular_minutes, v_summary.total_overtime_weekday_minutes;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> C-18 self-approval blocked on the period summary too'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_summary_id uuid := (select id from app.timesheet_period_summaries where timesheet_period_id = (select id from app.timesheet_periods where code = 'PERIOD-2027-01'));
  v_version integer;
begin
  select record_version into v_version from app.timesheet_period_summaries where id = v_summary_id;
  perform app.approve_timesheet_period_summary(v_summary_id, v_version, 'approved', '00000000-0000-0000-0000-000000028103', 'approver');
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

do $$
declare
  v_summary_id uuid := (select id from app.timesheet_period_summaries where timesheet_period_id = (select id from app.timesheet_periods where code = 'PERIOD-2027-01'));
begin
  if (select status from app.timesheet_period_summaries where id = v_summary_id) <> 'approved' then
    raise exception 'assertion failed: expected the period summary to be approved';
  end if;
end $$;

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_period_id uuid := (select id from app.timesheet_periods where code = 'PERIOD-2027-01');
  v_version integer;
  v_period app.timesheet_periods;
begin
  select record_version into v_version from app.timesheet_periods where id = v_period_id;
  v_period := app.lock_timesheet_period(v_period_id, v_version, '00000000-0000-0000-0000-000000028103', 'approver');
  if v_period.status <> 'locked' then
    raise exception 'assertion failed: expected the period to be locked';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> a locked period blocks a NEW submission for a date in its range'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_work_date date := (select work_date from app.attendance_sessions where tenant_id = (select id from app.tenants where slug = 'ot1') and employee_id = (select master_record_id from app.employees where work_email = 'emp1work@ot1.test'));
  v_entry app.timesheet_entries;
begin
  v_entry := app.create_timesheet_entry(v_tenant, v_work_date, 60, 0, null, null, null, 'late add', 'ts-locked-1', '00000000-0000-0000-0000-000000028104', 'emp1');
  begin
    perform app.submit_timesheet_entry(v_entry.id, v_entry.record_version, '00000000-0000-0000-0000-000000028104', 'emp1');
    raise exception 'assertion failed: expected timesheet_period_locked';
  exception when others then
    if sqlerrm not like 'timesheet_period_locked%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> governed reopen (decision 10): HRS:Edit cannot reopen a locked period; HRS:Override can, with a mandatory reason'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028102", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_period_id uuid := (select id from app.timesheet_periods where code = 'PERIOD-2027-01');
  v_version integer;
begin
  select record_version into v_version from app.timesheet_periods where id = v_period_id;
  begin
    perform app.reopen_timesheet_period(v_period_id, v_version, 'need to fix', '00000000-0000-0000-0000-000000028102', 'staff');
    raise exception 'assertion failed: expected insufficient_authority for a plain HRS:Edit actor';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_period_id uuid := (select id from app.timesheet_periods where code = 'PERIOD-2027-01');
  v_version integer;
  v_period app.timesheet_periods;
begin
  select record_version into v_version from app.timesheet_periods where id = v_period_id;
  v_period := app.reopen_timesheet_period(v_period_id, v_version, 'late correction needed', '00000000-0000-0000-0000-000000028103', 'approver');
  if v_period.status <> 'open' or v_period.reopen_count <> 1 then
    raise exception 'assertion failed: expected open/reopen_count=1, got %/%', v_period.status, v_period.reopen_count;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> the late entry can now be submitted and decided since the period is open again'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_entry_id uuid := (select id from app.timesheet_entries where idempotency_key = 'ts-locked-1');
  -- Explicit column list, never `select *` -- notes/decided_reason/
  -- cancel_reason are column-restricted from `authenticated` (mirrors
  -- HRT-278's own established db-test fixture fix for the identical class).
  v_version integer := (select record_version from app.timesheet_entries where id = v_entry_id);
  v_entry app.timesheet_entries;
begin
  v_entry := app.submit_timesheet_entry(v_entry_id, v_version, '00000000-0000-0000-0000-000000028104', 'emp1');
  if v_entry.status <> 'pending_approval' then
    raise exception 'assertion failed: expected pending_approval once the period is reopened';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_entry_id uuid := (select id from app.timesheet_entries where idempotency_key = 'ts-locked-1');
  v_version integer;
begin
  select record_version into v_version from app.timesheet_entries where id = v_entry_id;
  perform app.decide_timesheet_entry(v_entry_id, v_version, 'approve', 'ok, late add accepted', null, '00000000-0000-0000-0000-000000028103', 'approver');
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> decision 10''s own "never a silent overwrite": reopening the PERIOD does NOT silently revert the already-approved summary -- app.reopen_timesheet_period_summary is its own, separately governed action'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_period_id uuid := (select id from app.timesheet_periods where code = 'PERIOD-2027-01');
  v_emp1_id uuid := (select master_record_id from app.employees where work_email = 'emp1work@ot1.test');
begin
  if (select status from app.timesheet_period_summaries where timesheet_period_id = v_period_id) <> 'approved' then
    raise exception 'assertion failed: expected the summary to STILL be approved after the period-only reopen';
  end if;
  begin
    perform app.submit_timesheet_period_summary(v_period_id, v_emp1_id, '00000000-0000-0000-0000-000000028104', 'emp1');
    raise exception 'assertion failed: expected invalid_transition -- an approved summary is not directly re-submittable without its own explicit reopen';
  exception when others then
    if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> re-approve the (now stale) summary and re-lock the period -- via the summary''s own explicit reopen'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_summary_id uuid := (select id from app.timesheet_period_summaries where timesheet_period_id = (select id from app.timesheet_periods where code = 'PERIOD-2027-01'));
begin
  perform app.reopen_timesheet_period_summary(v_summary_id, (select record_version from app.timesheet_period_summaries where id = v_summary_id), 'late add needs to be folded in', '00000000-0000-0000-0000-000000028103', 'approver');
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_period_id uuid := (select id from app.timesheet_periods where code = 'PERIOD-2027-01');
  v_emp1_id uuid := (select master_record_id from app.employees where work_email = 'emp1work@ot1.test');
begin
  perform app.submit_timesheet_period_summary(v_period_id, v_emp1_id, '00000000-0000-0000-0000-000000028104', 'emp1');
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_summary_id uuid := (select id from app.timesheet_period_summaries where timesheet_period_id = (select id from app.timesheet_periods where code = 'PERIOD-2027-01'));
  v_version integer;
  v_summary app.timesheet_period_summaries;
  v_period_id uuid := (select id from app.timesheet_periods where code = 'PERIOD-2027-01');
  v_period_version integer;
  v_period app.timesheet_periods;
begin
  select record_version into v_version from app.timesheet_period_summaries where id = v_summary_id;
  v_summary := app.approve_timesheet_period_summary(v_summary_id, v_version, 're-approved with the late add', '00000000-0000-0000-0000-000000028103', 'approver');
  if v_summary.total_regular_minutes <> 510 then
    raise exception 'assertion failed: expected the recomputed total_regular_minutes to include the late add (450+60=510), got %', v_summary.total_regular_minutes;
  end if;

  select record_version into v_period_version from app.timesheet_periods where id = v_period_id;
  v_period := app.lock_timesheet_period(v_period_id, v_period_version, '00000000-0000-0000-0000-000000028103', 'approver');
  if v_period.status <> 'locked' then
    raise exception 'assertion failed: expected the period to be locked again';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> the ONE versioned idempotent payroll-input handoff record (decision 11): generate, then re-generate with no change -- returns the SAME version; reopening the summary and re-approving with a genuine change produces a NEW version, the prior one superseded'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_period_id uuid := (select id from app.timesheet_periods where code = 'PERIOD-2027-01');
  v_emp1_id uuid := (select master_record_id from app.employees where work_email = 'emp1work@ot1.test');
  v_pti1 app.payroll_time_inputs;
  v_pti2 app.payroll_time_inputs;
begin
  v_pti1 := app.generate_payroll_time_input(v_period_id, v_emp1_id, '00000000-0000-0000-0000-000000028103', 'approver');
  if v_pti1.version_number <> 1 or v_pti1.status <> 'active' or v_pti1.regular_minutes <> 510 or v_pti1.overtime_weekday_minutes <> 120 then
    raise exception 'assertion failed: expected version=1/active/regular=510/ot_weekday=120, got %/%/%/%', v_pti1.version_number, v_pti1.status, v_pti1.regular_minutes, v_pti1.overtime_weekday_minutes;
  end if;

  v_pti2 := app.generate_payroll_time_input(v_period_id, v_emp1_id, '00000000-0000-0000-0000-000000028103', 'approver');
  if v_pti2.id <> v_pti1.id or v_pti2.version_number <> 1 then
    raise exception 'assertion failed: expected a no-op idempotent replay (SAME id/version), got id=%/version=%', v_pti2.id, v_pti2.version_number;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> pay-field leakage check: app.payroll_time_inputs carries zero rate/amount/currency columns (structural, decision 12)'
do $$
declare
  v_money_columns integer;
begin
  -- Word-boundary-anchored (\y...\y, Postgres's own regex word-boundary
  -- syntax) -- a naive substring match falsely flagged generated_by
  -- (contains "rate" inside "geneRATEd"), self-found before this became a
  -- silently-wrong negative-control assertion.
  select count(*) into v_money_columns
  from information_schema.columns
  where table_schema = 'app' and table_name = 'payroll_time_inputs'
    and (column_name ~* '\yrate\y|\yamount\y|\ycurrency\y|\yprice\y|\ycost\y|\ywage\y|\ysalary\y');
  if v_money_columns <> 0 then
    raise exception 'assertion failed: expected zero rate/amount/currency-shaped columns on app.payroll_time_inputs, found %', v_money_columns;
  end if;
end $$;

\echo '>> reopening the approved summary resets contributing rows'' payroll_input_status back to pending; a cancel is blocked while payroll_input_status=approved'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_req_id uuid := (select id from app.overtime_requests where idempotency_key = 'ot-req-1');
begin
  if (select payroll_input_status from app.overtime_requests where id = v_req_id) <> 'approved' then
    raise exception 'assertion failed: expected the overtime request to be folded into the generated payroll input (payroll_input_status=approved)';
  end if;
  begin
    perform app.cancel_overtime_request(v_req_id, (select record_version from app.overtime_requests where id = v_req_id), 'trying to cancel', '00000000-0000-0000-0000-000000028103', 'approver');
    raise exception 'assertion failed: expected payroll_input_already_generated';
  exception when others then
    if sqlerrm not like 'payroll_input_already_generated%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028102", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_summary_id uuid := (select id from app.timesheet_period_summaries where timesheet_period_id = (select id from app.timesheet_periods where code = 'PERIOD-2027-01'));
  v_period_id uuid := (select id from app.timesheet_periods where code = 'PERIOD-2027-01');
begin
  -- staff@ot1 lacks HRS:Override -- period reopen must fail first.
  begin
    perform app.reopen_timesheet_period(v_period_id, (select record_version from app.timesheet_periods where id = v_period_id), 'correction', '00000000-0000-0000-0000-000000028102', 'staff');
    raise exception 'assertion failed: expected insufficient_authority';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_period_id uuid := (select id from app.timesheet_periods where code = 'PERIOD-2027-01');
  v_summary_id uuid := (select id from app.timesheet_period_summaries where timesheet_period_id = (select id from app.timesheet_periods where code = 'PERIOD-2027-01'));
  v_req_id uuid := (select id from app.overtime_requests where idempotency_key = 'ot-req-1');
begin
  perform app.reopen_timesheet_period(v_period_id, (select record_version from app.timesheet_periods where id = v_period_id), 'correction', '00000000-0000-0000-0000-000000028103', 'approver');
  perform app.reopen_timesheet_period_summary(v_summary_id, (select record_version from app.timesheet_period_summaries where id = v_summary_id), 'reviewing the overtime figure', '00000000-0000-0000-0000-000000028103', 'approver');

  if (select payroll_input_status from app.overtime_requests where id = v_req_id) <> 'pending' then
    raise exception 'assertion failed: expected the overtime request''s payroll_input_status to reset to pending on reopen';
  end if;
  if (select status from app.timesheet_period_summaries where id = v_summary_id) <> 'pending' then
    raise exception 'assertion failed: expected the summary to return to pending';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> re-approve and re-generate: a genuinely UNCHANGED recompute still returns the SAME active version (content-based idempotency holds across a reopen/no-op cycle)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028104", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_period_id uuid := (select id from app.timesheet_periods where code = 'PERIOD-2027-01');
  v_emp1_id uuid := (select master_record_id from app.employees where work_email = 'emp1work@ot1.test');
begin
  perform app.submit_timesheet_period_summary(v_period_id, v_emp1_id, '00000000-0000-0000-0000-000000028104', 'emp1');
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_summary_id uuid := (select id from app.timesheet_period_summaries where timesheet_period_id = (select id from app.timesheet_periods where code = 'PERIOD-2027-01'));
  v_period_id uuid := (select id from app.timesheet_periods where code = 'PERIOD-2027-01');
  v_emp1_id uuid := (select master_record_id from app.employees where work_email = 'emp1work@ot1.test');
  v_pti app.payroll_time_inputs;
begin
  perform app.approve_timesheet_period_summary(v_summary_id, (select record_version from app.timesheet_period_summaries where id = v_summary_id), 'unchanged, re-approved', '00000000-0000-0000-0000-000000028103', 'approver');
  perform app.lock_timesheet_period(v_period_id, (select record_version from app.timesheet_periods where id = v_period_id), '00000000-0000-0000-0000-000000028103', 'approver');
  v_pti := app.generate_payroll_time_input(v_period_id, v_emp1_id, '00000000-0000-0000-0000-000000028103', 'approver');
  if v_pti.version_number <> 1 then
    raise exception 'assertion failed: expected the SAME version 1 (nothing genuinely changed), got version %', v_pti.version_number;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> timesheet import (section 22 "authorized import"): the sixth-plus real PLT-131/132 staged-import adapter -- publish import_export schema config, stage rows, validate (structural + formula-injection + employee/job/shipment resolution), commit. app.create_config_draft/app.publish_document_type_definition/app.publish_import_export_schema are service_role-only (PLT-121) -- this whole config-authoring block runs at the default (superuser) connection role, mirroring scripts/db-tests/hris-attendance.sql''s own identical device-import fixture shape exactly (no set role authenticated here).'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_doc_draft app.config_versions;
  v_draft app.config_versions;
  v_source_file app.files;
  v_job app.jobs;
  v_row1 app.import_staging_rows;
  v_row2 app.import_staging_rows;
  v_row3 app.import_staging_rows;
begin
  v_doc_draft := app.create_config_draft('document:timesheet_import_source', v_tenant, 'tenant', null, '00000000-0000-0000-0000-000000028101', 'admin');
  perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('text/csv')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('confidential'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), '00000000-0000-0000-0000-000000028101', 'admin');
  perform app.publish_document_type_definition(v_doc_draft.id, '00000000-0000-0000-0000-000000028101', now(), 'admin');

  v_draft := app.create_config_draft('import_export:timesheet_import', v_tenant, 'tenant', null, '00000000-0000-0000-0000-000000028101', 'admin');
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
      jsonb_build_object('key', 'employee_number', 'label', 'Employee Number', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'work_date', 'label', 'Work Date', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'entry_minutes', 'label', 'Entry Minutes', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'job_number', 'label', 'Job Number', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'shipment_number', 'label', 'Shipment Number', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'notes', 'label', 'Notes', 'required', false, 'data_type', 'text')
    ))
  ), '00000000-0000-0000-0000-000000028101', 'admin');
  perform app.publish_import_export_schema(v_draft.id, '00000000-0000-0000-0000-000000028101', now(), 'admin');

  v_source_file := app.initiate_file_upload(v_tenant, 'timesheet_import_source', 'import_job', gen_random_uuid(), 'timesheet-export.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-tsimport-src-1', '00000000-0000-0000-0000-000000028102', 'staff');
  perform app.record_file_scan_result(v_source_file.id, 'clean', null, '00000000-0000-0000-0000-000000028102', 'staff');

  v_job := app.create_import_export_job(v_tenant, 'import', 'timesheet_import', v_source_file.id, '{}'::jsonb, 'idem-tsimport-job-1', '00000000-0000-0000-0000-000000028102', 'staff');

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', (select code from app.master_records where id = (select master_record_id from app.employees where work_email = 'emp2work@ot1.test')),
    'work_date', '2027-04-01', 'entry_minutes', '240', 'notes', 'valid row'
  )), '00000000-0000-0000-0000-000000028102', 'staff');
  select * into v_row1 from app.import_staging_rows where job_id = v_job.job_id and row_number = 1;

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', 'NOT-A-REAL-EMPLOYEE', 'work_date', '2027-04-01', 'entry_minutes', '120'
  )), '00000000-0000-0000-0000-000000028102', 'staff');
  select * into v_row2 from app.import_staging_rows where job_id = v_job.job_id and row_number = 2;

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', '=cmd|/c calc', 'work_date', '2027-04-01', 'entry_minutes', '120'
  )), '00000000-0000-0000-0000-000000028102', 'staff');
  select * into v_row3 from app.import_staging_rows where job_id = v_job.job_id and row_number = 3;

  perform app.validate_timesheet_import_row(v_row1.id, '00000000-0000-0000-0000-000000028102', 'staff');
  perform app.validate_timesheet_import_row(v_row2.id, '00000000-0000-0000-0000-000000028102', 'staff');
  perform app.validate_timesheet_import_row(v_row3.id, '00000000-0000-0000-0000-000000028102', 'staff');

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
    perform app.commit_timesheet_import_job(v_job.job_id, false, '00000000-0000-0000-0000-000000028102', 'staff');
    raise exception 'assertion failed: expected import_export_job_has_invalid_rows without p_allow_partial';
  exception when others then
    if sqlerrm not like 'import_export_job_has_invalid_rows%' then raise; end if;
  end;

  perform app.commit_timesheet_import_job(v_job.job_id, true, '00000000-0000-0000-0000-000000028102', 'staff');
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

do $$
declare
  v_entry app.timesheet_entries;
begin
  select * into v_entry from app.timesheet_entries where source = 'import';
  if v_entry.id is null then
    raise exception 'assertion failed: expected a real timesheet_entry created from the import commit';
  end if;
  if v_entry.entry_minutes <> 240 or v_entry.status <> 'draft' then
    raise exception 'assertion failed: unexpected imported entry shape (entry_minutes=%/status=%)', v_entry.entry_minutes, v_entry.status;
  end if;
end $$;

\echo '>> re-committing the SAME import job is idempotent per staging row (never a duplicate timesheet_entry) -- mirrors scripts/db-tests/hris-attendance.sql''s own identical re-commit fixture shape (superuser connection role, direct app.jobs status reset for test purposes, then the real RPC)'
do $$
declare
  v_job_id uuid := (select job_id from app.jobs where import_export_schema_code = 'timesheet_import' order by created_at desc limit 1);
begin
  update app.jobs set status = 'in_progress' where job_id = v_job_id;
  perform app.commit_timesheet_import_job(v_job_id, true, '00000000-0000-0000-0000-000000028102', 'staff');
end $$;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.timesheet_entries where source = 'import';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 imported entry after a re-commit, got %', v_count;
  end if;
end $$;

\echo '>> cross-tenant isolation: ot2''s zero-relation actor probing an ot1 id gets a uniform not-found, never a distinguishing error'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028123", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_ot1_req_id uuid := (select id from app.overtime_requests where idempotency_key = 'ot-req-1');
begin
  begin
    perform app.decide_overtime_request(v_ot1_req_id, 1, 'approve', 'cross-tenant probe', null, '00000000-0000-0000-0000-000000028123', 'ot2hr');
    raise exception 'assertion failed: expected overtime_request_not_found for a cross-tenant probe';
  exception when others then
    if sqlerrm not like 'overtime_request_not_found%' then raise; end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> RLS default-deny: a zero-permission ot2 member''s raw SELECT sees zero ot1 rows on every person-scoped table'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028122", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.overtime_requests where tenant_id = (select id from app.tenants where slug = 'ot1');
  if v_count <> 0 then raise exception 'assertion failed: expected 0 cross-tenant overtime_requests rows via raw SELECT, got %', v_count; end if;

  select count(*) into v_count from app.timesheet_entries where tenant_id = (select id from app.tenants where slug = 'ot1');
  if v_count <> 0 then raise exception 'assertion failed: expected 0 cross-tenant timesheet_entries rows via raw SELECT, got %', v_count; end if;

  select count(*) into v_count from app.timesheet_period_summaries where tenant_id = (select id from app.tenants where slug = 'ot1');
  if v_count <> 0 then raise exception 'assertion failed: expected 0 cross-tenant timesheet_period_summaries rows via raw SELECT, got %', v_count; end if;

  select count(*) into v_count from app.payroll_time_inputs where tenant_id = (select id from app.tenants where slug = 'ot1');
  if v_count <> 0 then raise exception 'assertion failed: expected 0 cross-tenant payroll_time_inputs rows via raw SELECT, got %', v_count; end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> RLS self-scoping-raw-table-overexposure guard: a SAME-tenant zero-HRS-permission member (no linked employee row) sees ZERO rows on every person-scoped table via a raw SELECT -- the exact HIGH finding class this phase''s batch 278-280 Tier C found three times, designed against here from the FIRST migration by reusing app.can_view_hris_person_scoped_row'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028101", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_count integer;
begin
  -- admin@ot1 holds tenant_admin membership but this role grants no HRS
  -- permission and has no linked app.employees row -- exactly the probe
  -- shape the prior batch's own finding was live-reproduced with.
  select count(*) into v_count from app.overtime_requests where tenant_id = (select id from app.tenants where slug = 'ot1');
  if v_count <> 0 then raise exception 'assertion failed: expected 0 overtime_requests rows for a zero-HRS-permission tenant member, got %', v_count; end if;

  select count(*) into v_count from app.timesheet_entries where tenant_id = (select id from app.tenants where slug = 'ot1');
  if v_count <> 0 then raise exception 'assertion failed: expected 0 timesheet_entries rows for a zero-HRS-permission tenant member, got %', v_count; end if;

  select count(*) into v_count from app.timesheet_period_summaries where tenant_id = (select id from app.tenants where slug = 'ot1');
  if v_count <> 0 then raise exception 'assertion failed: expected 0 timesheet_period_summaries rows for a zero-HRS-permission tenant member, got %', v_count; end if;

  select count(*) into v_count from app.payroll_time_inputs where tenant_id = (select id from app.tenants where slug = 'ot1');
  if v_count <> 0 then raise exception 'assertion failed: expected 0 payroll_time_inputs rows for a zero-HRS-permission tenant member (decision 12''s own stricter gate), got %', v_count; end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> HRS:View-payroll-holding actor DOES see payroll_time_inputs via a raw SELECT (the shared helper''s positive path, not merely the negative)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028103", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.payroll_time_inputs where tenant_id = (select id from app.tenants where slug = 'ot1');
  if v_count = 0 then
    raise exception 'assertion failed: expected the HRS:View-payroll-holding approver to see at least 1 payroll_time_inputs row via raw SELECT';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> schema-privilege defense in depth: anon holds no direct table/function access; authenticated has RLS-scoped SELECT but sensitive free-text columns are column-restricted both directions; internal engine functions are service_role-only'
do $$
declare
  v_has_priv boolean;
begin
  select has_table_privilege('anon', 'app.overtime_requests', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not have direct table privilege on app.overtime_requests'; end if;

  select has_column_privilege('authenticated', 'app.overtime_requests', 'reason', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT have column privilege on overtime_requests.reason (column-restricted)'; end if;
  select has_column_privilege('authenticated', 'app.overtime_requests', 'work_date', 'SELECT') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: authenticated SHOULD have column privilege on overtime_requests.work_date (not restricted)'; end if;

  select has_column_privilege('authenticated', 'app.timesheet_entries', 'notes', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT have column privilege on timesheet_entries.notes (column-restricted)'; end if;

  select has_column_privilege('service_role', 'app.overtime_requests', 'reason', 'SELECT') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: service_role SHOULD retain full column access to overtime_requests.reason'; end if;

  select has_function_privilege('authenticated', 'app.validate_timesheet_import_row(uuid,uuid,text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT have execute on app.validate_timesheet_import_row (service_role-only)'; end if;
  select has_function_privilege('authenticated', 'app._generate_payroll_time_input(uuid,uuid,uuid,text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT have execute on the internal app._generate_payroll_time_input engine'; end if;
  select has_function_privilege('authenticated', 'app._create_overtime_request(app.employees,text,timestamptz,timestamptz,integer,text,uuid,uuid,uuid,text,uuid,text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT have execute on the internal app._create_overtime_request engine'; end if;

  select has_column_privilege('authenticated', 'app.payroll_time_inputs', 'regular_minutes', 'SELECT') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: authenticated SHOULD have column privilege on payroll_time_inputs.regular_minutes (no money on this table, structurally)'; end if;
end $$;

\echo '>> record_version genuinely advances on every real UPDATE (touch-row trigger, self-found gap this checkpoint closed from the start)'
do $$
declare
  v_version integer;
begin
  select record_version into v_version from app.overtime_requests where idempotency_key = 'ot-req-1';
  if v_version <= 1 then
    raise exception 'assertion failed: expected record_version to have advanced past 1 after submit+decide, got %', v_version;
  end if;
end $$;

\echo '>> ISS-2026-278 (Step 16 historical-issue-backlog remediation) regression: app.commit_timesheet_import_job now composes app.assert_ip_allowed + app.has_active_ip_allowlist_bypass when a caller supplies p_client_ip -- denies an out-of-range IP under enforced mode, allows an in-range one, and allows a null/omitted p_client_ip regardless of enforcement (every pre-existing call site in this file relies on exactly this)'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'ot1');
  v_supreme uuid := '00000000-0000-0000-0000-000000028199';
  v_employee_number text := (select code from app.master_records where id = (select master_record_id from app.employees where work_email = 'emp2work@ot1.test'));
  v_source_file1 app.files;
  v_source_file2 app.files;
  v_source_file3 app.files;
  v_job1 app.jobs;
  v_job2 app.jobs;
  v_job3 app.jobs;
  v_row1 app.import_staging_rows;
  v_row2 app.import_staging_rows;
  v_row3 app.import_staging_rows;
  v_committed app.jobs;
  v_raised boolean;
begin
  perform app.add_ip_allowlist_entry(v_tenant, '203.0.113.0/24', 'ot1 office range', 'admin', v_supreme, 'supreme');
  perform app.set_ip_allowlist_enforcement_mode(v_tenant, 'enforced', v_supreme, 'supreme');

  -- (a) out-of-range p_client_ip -- denied, ip_not_allowed.
  v_source_file1 := app.initiate_file_upload(v_tenant, 'timesheet_import_source', 'import_job', gen_random_uuid(), 'timesheet-ipcheck-a.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-tsimport-ipcheck-src-a', '00000000-0000-0000-0000-000000028102', 'staff');
  perform app.record_file_scan_result(v_source_file1.id, 'clean', null, '00000000-0000-0000-0000-000000028102', 'staff');
  v_job1 := app.create_import_export_job(v_tenant, 'import', 'timesheet_import', v_source_file1.id, '{}'::jsonb, 'idem-tsimport-ipcheck-job-a', '00000000-0000-0000-0000-000000028102', 'staff');
  perform app.stage_import_rows(v_job1.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', v_employee_number, 'work_date', '2027-05-01', 'entry_minutes', '120', 'notes', 'ip check a'
  )), '00000000-0000-0000-0000-000000028102', 'staff');
  select * into v_row1 from app.import_staging_rows where job_id = v_job1.job_id and row_number = 1;
  perform app.validate_timesheet_import_row(v_row1.id, '00000000-0000-0000-0000-000000028102', 'staff');
  v_raised := false;
  begin
    perform app.commit_timesheet_import_job(v_job1.job_id, false, '00000000-0000-0000-0000-000000028102', 'staff', '198.51.100.7');
    raise exception 'assertion failed: expected ip_not_allowed for an out-of-range p_client_ip under enforced mode, the call unexpectedly succeeded';
  exception
    when insufficient_privilege then
      if sqlerrm !~ 'ip_not_allowed' then raise; end if;
      v_raised := true;
  end;
  if not v_raised then
    raise exception 'assertion failed: expected ip_not_allowed, got none';
  end if;

  -- (b) in-range p_client_ip -- succeeds.
  v_source_file2 := app.initiate_file_upload(v_tenant, 'timesheet_import_source', 'import_job', gen_random_uuid(), 'timesheet-ipcheck-b.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-tsimport-ipcheck-src-b', '00000000-0000-0000-0000-000000028102', 'staff');
  perform app.record_file_scan_result(v_source_file2.id, 'clean', null, '00000000-0000-0000-0000-000000028102', 'staff');
  v_job2 := app.create_import_export_job(v_tenant, 'import', 'timesheet_import', v_source_file2.id, '{}'::jsonb, 'idem-tsimport-ipcheck-job-b', '00000000-0000-0000-0000-000000028102', 'staff');
  perform app.stage_import_rows(v_job2.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', v_employee_number, 'work_date', '2027-05-02', 'entry_minutes', '120', 'notes', 'ip check b'
  )), '00000000-0000-0000-0000-000000028102', 'staff');
  select * into v_row2 from app.import_staging_rows where job_id = v_job2.job_id and row_number = 1;
  perform app.validate_timesheet_import_row(v_row2.id, '00000000-0000-0000-0000-000000028102', 'staff');
  v_committed := app.commit_timesheet_import_job(v_job2.job_id, false, '00000000-0000-0000-0000-000000028102', 'staff', '203.0.113.42');
  if v_committed.status <> 'completed' then
    raise exception 'assertion failed: expected a real completed commit for an in-range p_client_ip, got %', v_committed;
  end if;

  -- (c) p_client_ip omitted -- succeeds regardless of the enforced policy.
  v_source_file3 := app.initiate_file_upload(v_tenant, 'timesheet_import_source', 'import_job', gen_random_uuid(), 'timesheet-ipcheck-c.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-tsimport-ipcheck-src-c', '00000000-0000-0000-0000-000000028102', 'staff');
  perform app.record_file_scan_result(v_source_file3.id, 'clean', null, '00000000-0000-0000-0000-000000028102', 'staff');
  v_job3 := app.create_import_export_job(v_tenant, 'import', 'timesheet_import', v_source_file3.id, '{}'::jsonb, 'idem-tsimport-ipcheck-job-c', '00000000-0000-0000-0000-000000028102', 'staff');
  perform app.stage_import_rows(v_job3.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', v_employee_number, 'work_date', '2027-05-03', 'entry_minutes', '120', 'notes', 'ip check c'
  )), '00000000-0000-0000-0000-000000028102', 'staff');
  select * into v_row3 from app.import_staging_rows where job_id = v_job3.job_id and row_number = 1;
  perform app.validate_timesheet_import_row(v_row3.id, '00000000-0000-0000-0000-000000028102', 'staff');
  v_committed := app.commit_timesheet_import_job(v_job3.job_id, false, '00000000-0000-0000-0000-000000028102', 'staff');
  if v_committed.status <> 'completed' then
    raise exception 'assertion failed: expected a real completed commit when p_client_ip is omitted, regardless of enforcement, got %', v_committed;
  end if;

  raise notice 'PASS: app.commit_timesheet_import_job (ISS-2026-278) denies an out-of-range p_client_ip under enforced mode, allows an in-range one, and allows an omitted p_client_ip regardless of enforcement';
end;
$$;

\echo '>> HRT-281 OVERTIME AND TIMESHEET TEST SUITE COMPLETE'
