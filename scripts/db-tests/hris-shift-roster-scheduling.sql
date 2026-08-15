-- Real, executable test evidence for HRT-279 (Shift, Roster and Scheduling,
-- CG-S12-HRT-007) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Mirrors scripts/db-tests/hris-attendance.sql's own
-- two-tenant cross-isolation convention.
--
-- Sorts alphabetically AFTER hris-attendance.sql/hris-employee-master.sql/
-- hris-onboarding-offboarding.sql/hris-organization-position-linkage.sql/
-- hris-recruitment-ats.sql, so those migrations are already applied when
-- this runs -- but this file builds its OWN self-contained two-tenant/
-- employee/shift/roster fixture using a fresh, unclaimed UUID range
-- (00000000-0000-0000-0000-0000000279xx), never depending on any other
-- hris-*.sql file's own fixture rows (each hris-*.sql file is independently
-- runnable).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (shr1, shr2). shr1 gets a tenant_admin, HR scheduling staff (HRS Create/Edit/Export/View/View personal data), an approver (HRS Approve/View/Override), four active employees (emp1/emp2/emp3, mgr1 -- emp1 reports to mgr1) in one company/branch org unit. shr2 gets a tenant_admin, staff, and one active employee for cross-tenant checks. A global Supreme Admin is also seeded.'
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
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000027901', 'admin@shr1.test'),
    ('00000000-0000-0000-0000-000000027902', 'staff@shr1.test'),
    ('00000000-0000-0000-0000-000000027903', 'approver@shr1.test'),
    ('00000000-0000-0000-0000-000000027904', 'emp1@shr1.test'),
    ('00000000-0000-0000-0000-000000027905', 'emp2@shr1.test'),
    ('00000000-0000-0000-0000-000000027906', 'mgr1@shr1.test'),
    ('00000000-0000-0000-0000-000000027907', 'emp3@shr1.test'),
    ('00000000-0000-0000-0000-000000027921', 'admin@shr2.test'),
    ('00000000-0000-0000-0000-000000027922', 'emp1@shr2.test'),
    ('00000000-0000-0000-0000-000000027923', 'staff@shr2.test'),
    ('00000000-0000-0000-0000-000000027989', 'supreme@shr.test');

  perform app.provision_tenant('shr1', 'SHR Co 1', 'idem-shr1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'shr1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('shr2', 'SHR Co 2', 'idem-shr2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'shr2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027901', 'admin@shr1.test', 'Shr1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@shr1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027901', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027902', 'staff@shr1.test', 'Shr1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@shr1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027903', 'approver@shr1.test', 'Shr1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@shr1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027904', 'emp1@shr1.test', 'Shr1 Emp One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp1@shr1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027905', 'emp2@shr1.test', 'Shr1 Emp Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp2@shr1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027906', 'mgr1@shr1.test', 'Shr1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'mgr1@shr1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027907', 'emp3@shr1.test', 'Shr1 Emp Three', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp3@shr1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027921', 'admin@shr2.test', 'Shr2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@shr2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027921', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027922', 'emp1@shr2.test', 'Shr2 Emp One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp1@shr2.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027923', 'staff@shr2.test', 'Shr2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@shr2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027989', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'HRS Scheduler Staff', 'Create/Edit/Export/View/View personal data', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Export', 'View', 'View personal data')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000027902', '00000000-0000-0000-0000-000000027901', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'HRS Approver', 'Approve/View/Override', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Approve', 'View', 'Override')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000027903', '00000000-0000-0000-0000-000000027901', 'tester');

  v_t2_role := (app.create_role(v_tenant2, 'HRS Scheduler Staff', 'Create/Edit/View/Approve/Override', 'tester')).id;
  v_t2_draft := app.create_role_version(v_t2_role, 'tester');
  perform app.set_role_version_permissions(v_t2_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View', 'Approve', 'Override')), 'tester');
  perform app.publish_role_version(v_t2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'), '00000000-0000-0000-0000-000000027923', '00000000-0000-0000-0000-000000027921', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-SHR1', 'Shr1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-SHR1', 'Shr1 Branch', 'tester')).id;
  perform app.create_org_unit(v_tenant2, 'company', null, 'CO-SHR2', 'Shr2 Co', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Shr1 Emp One', 'full_time', 'emp1work@shr1.test', 'emp1p@shr1.test', '0800000001', null, null, null, '2024-01-01', v_company, v_branch, null, 'Warehouse Staff', null, (select id from app.users where email = 'emp1@shr1.test'), null, 'hr_created', 'idem-shr-emp1', '00000000-0000-0000-0000-000000027902', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test'), 'Contact One', 'spouse', '0810000001', null, true, '00000000-0000-0000-0000-000000027902', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test'), 1, '00000000-0000-0000-0000-000000027902', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000027903', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test'), 3, '00000000-0000-0000-0000-000000027903', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Shr1 Manager', 'full_time', 'mgr1work@shr1.test', 'mgr1p@shr1.test', '0800000002', null, null, null, '2024-01-01', v_company, v_branch, null, 'Warehouse Manager', null, (select id from app.users where email = 'mgr1@shr1.test'), null, 'hr_created', 'idem-shr-mgr1', '00000000-0000-0000-0000-000000027902', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@shr1.test'), 'Contact Mgr', 'spouse', '0810000002', null, true, '00000000-0000-0000-0000-000000027902', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@shr1.test'), 1, '00000000-0000-0000-0000-000000027902', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@shr1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000027903', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@shr1.test'), 3, '00000000-0000-0000-0000-000000027903', 'tester');

  perform app.create_employee_draft(
    v_tenant1, 'Shr1 Emp Two', 'full_time', 'emp2work@shr1.test', 'emp2p@shr1.test', '0800000003', null, null, null, '2024-01-01',
    v_company, v_branch, null, 'Warehouse Staff', (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@shr1.test'),
    (select id from app.users where email = 'emp2@shr1.test'), null, 'hr_created', 'idem-shr-emp2', '00000000-0000-0000-0000-000000027902', 'tester'
  );
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@shr1.test'), 'Contact Two', 'spouse', '0810000003', null, true, '00000000-0000-0000-0000-000000027902', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@shr1.test'), 1, '00000000-0000-0000-0000-000000027902', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@shr1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000027903', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@shr1.test'), 3, '00000000-0000-0000-0000-000000027903', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Shr1 Emp Three', 'full_time', 'emp3work@shr1.test', 'emp3p@shr1.test', '0800000004', null, null, null, '2024-01-01', v_company, v_branch, null, 'Warehouse Staff', null, (select id from app.users where email = 'emp3@shr1.test'), null, 'hr_created', 'idem-shr-emp3', '00000000-0000-0000-0000-000000027902', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@shr1.test'), 'Contact Three', 'spouse', '0810000004', null, true, '00000000-0000-0000-0000-000000027902', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@shr1.test'), 1, '00000000-0000-0000-0000-000000027902', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@shr1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000027903', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@shr1.test'), 3, '00000000-0000-0000-0000-000000027903', 'tester');

  perform app.create_employee_draft(v_tenant2, 'Shr2 Emp One', 'full_time', 'emp1work@shr2.test', 'emp1p@shr2.test', '0800000005', null, null, null, '2024-01-01', (select id from app.org_units where tenant_id = v_tenant2 and code = 'CO-SHR2'), null, null, 'Staff', null, (select id from app.users where email = 'emp1@shr2.test'), null, 'hr_created', 'idem-shr-emp1-t2', '00000000-0000-0000-0000-000000027923', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@shr2.test'), 'Contact Shr2', 'spouse', '0810000005', null, true, '00000000-0000-0000-0000-000000027923', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@shr2.test'), 1, '00000000-0000-0000-0000-000000027923', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@shr2.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000027923', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant2 and work_email = 'emp1work@shr2.test'), 3, '00000000-0000-0000-0000-000000027923', 'tester');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end $$;

\echo '>> app.create_shift_template: viewer/no-permission actor rejected; staff (HRS:Edit) creates a real tenant-wide template; duplicate code within a tenant rejected'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tpl app.shift_templates;
begin
  v_tpl := app.create_shift_template((select id from app.tenants where slug='shr1'), null, 'MORNING', 'Morning Fixed', '00000000-0000-0000-0000-000000027902', 'staff');
  if v_tpl.status <> 'draft' then
    raise exception 'assertion failed: expected a new shift template to start draft';
  end if;

  begin
    perform app.create_shift_template((select id from app.tenants where slug='shr1'), null, 'MORNING', 'Duplicate Code', '00000000-0000-0000-0000-000000027902', 'staff');
    raise exception 'assertion failed: duplicate code within one tenant should be rejected';
  exception when unique_violation then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027904", "role": "authenticated"}', false);
set role authenticated;
do $$
begin
  begin
    perform app.create_shift_template((select id from app.tenants where slug='shr1'), null, 'NOPERM', 'No Permission', '00000000-0000-0000-0000-000000027904', 'emp1');
    raise exception 'assertion failed: a plain employee with no HRS:Edit should be rejected';
  exception when insufficient_privilege then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> app.create_shift_template_version: segment validation -- zero segments rejected, an overlapping segment rejected, a segment after a midnight-crossing segment rejected, invalid timezone rejected; a real fixed 08:00-17:00 shift succeeds and computes total_work_minutes correctly'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tpl_id uuid := (select id from app.shift_templates where tenant_id = (select id from app.tenants where slug='shr1') and code = 'MORNING');
begin
  begin
    perform app.create_shift_template_version(v_tpl_id, 'Asia/Jakarta', '00:00:00'::time, 'fixed', 15, 15, '2024-01-01'::date, '[]'::jsonb, '00000000-0000-0000-0000-000000027902', 'staff');
    raise exception 'assertion failed: zero segments should be rejected';
  exception when check_violation then
    null;
  end;

  begin
    perform app.create_shift_template_version(
      v_tpl_id, 'Asia/Jakarta', '00:00:00'::time, 'split', 15, 15, '2024-01-01'::date,
      jsonb_build_array(
        jsonb_build_object('segment_type', 'work', 'start_time', '08:00:00', 'end_time', '13:00:00'),
        jsonb_build_object('segment_type', 'work', 'start_time', '12:00:00', 'end_time', '17:00:00')
      ),
      '00000000-0000-0000-0000-000000027902', 'staff'
    );
    raise exception 'assertion failed: an overlapping segment (12:00 starts before 13:00 ends) should be rejected';
  exception when check_violation then
    null;
  end;

  begin
    perform app.create_shift_template_version(
      v_tpl_id, 'Asia/Jakarta', '04:00:00'::time, 'fixed', 15, 15, '2024-01-01'::date,
      jsonb_build_array(
        jsonb_build_object('segment_type', 'work', 'start_time', '22:00:00', 'end_time', '02:00:00'),
        jsonb_build_object('segment_type', 'break', 'start_time', '03:00:00', 'end_time', '03:30:00')
      ),
      '00000000-0000-0000-0000-000000027902', 'staff'
    );
    raise exception 'assertion failed: a segment after an already-midnight-crossing segment should be rejected';
  exception when check_violation then
    null;
  end;

  begin
    perform app.create_shift_template_version(v_tpl_id, 'Not/AZone', '00:00:00'::time, 'fixed', 15, 15, '2024-01-01'::date, jsonb_build_array(jsonb_build_object('segment_type', 'work', 'start_time', '08:00:00', 'end_time', '17:00:00')), '00000000-0000-0000-0000-000000027902', 'staff');
    raise exception 'assertion failed: an invalid IANA timezone should be rejected';
  exception when check_violation then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> a real fixed shift version (08:00-17:00, 60-min unpaid break) succeeds; total_work_minutes=480, total_break_minutes=60, crosses_midnight=false; publish requires HRS:Approve, not merely HRS:Edit; publish sets the parent template published too'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tpl_id uuid := (select id from app.shift_templates where tenant_id = (select id from app.tenants where slug='shr1') and code = 'MORNING');
  v_version app.shift_template_versions;
begin
  v_version := app.create_shift_template_version(
    v_tpl_id, 'Asia/Jakarta', '00:00:00'::time, 'fixed', 15, 15, '2024-01-01'::date,
    jsonb_build_array(
      jsonb_build_object('segment_type', 'work', 'start_time', '08:00:00', 'end_time', '12:00:00'),
      jsonb_build_object('segment_type', 'break', 'start_time', '12:00:00', 'end_time', '13:00:00'),
      jsonb_build_object('segment_type', 'work', 'start_time', '13:00:00', 'end_time', '17:00:00')
    ),
    '00000000-0000-0000-0000-000000027902', 'staff'
  );
  if v_version.total_work_minutes <> 480 or v_version.total_break_minutes <> 60 or v_version.crosses_midnight then
    raise exception 'assertion failed: expected 480 work minutes, 60 break minutes, no midnight crossing, got work=%, break=%, crosses=%', v_version.total_work_minutes, v_version.total_break_minutes, v_version.crosses_midnight;
  end if;

  begin
    perform app.publish_shift_template_version(v_version.id, 1, '00000000-0000-0000-0000-000000027902', 'staff');
    raise exception 'assertion failed: HRS:Edit alone should not be able to publish (requires HRS:Approve)';
  exception when insufficient_privilege then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027903", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_version_id uuid := (select id from app.shift_template_versions where shift_template_id = (select id from app.shift_templates where tenant_id = (select id from app.tenants where slug='shr1') and code = 'MORNING'));
  v_published app.shift_template_versions;
  v_tpl_status text;
begin
  v_published := app.publish_shift_template_version(v_version_id, 1, '00000000-0000-0000-0000-000000027903', 'approver');
  if v_published.status <> 'published' or v_published.published_by <> 'approver' then
    raise exception 'assertion failed: expected published status with published_by=approver';
  end if;
  select status into v_tpl_status from app.shift_templates where id = v_published.shift_template_id;
  if v_tpl_status <> 'published' then
    raise exception 'assertion failed: expected the parent shift template to also flip to published';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> a real cross-midnight shift (22:00-06:00) publishes cleanly for the roster-cycle/swap tests below'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tpl app.shift_templates;
  v_version app.shift_template_versions;
begin
  v_tpl := app.create_shift_template((select id from app.tenants where slug='shr1'), null, 'NIGHT', 'Night Cross-Midnight', '00000000-0000-0000-0000-000000027902', 'staff');
  v_version := app.create_shift_template_version(
    v_tpl.id, 'Asia/Jakarta', '12:00:00'::time, 'fixed', 15, 15, '2024-01-01'::date,
    jsonb_build_array(jsonb_build_object('segment_type', 'work', 'start_time', '22:00:00', 'end_time', '06:00:00')),
    '00000000-0000-0000-0000-000000027902', 'staff'
  );
  if not v_version.crosses_midnight or v_version.total_work_minutes <> 480 then
    raise exception 'assertion failed: expected crosses_midnight=true, total_work_minutes=480 (22:00->06:00), got crosses=%, minutes=%', v_version.crosses_midnight, v_version.total_work_minutes;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027903", "role": "authenticated"}', false);
set role authenticated;
select app.publish_shift_template_version((select id from app.shift_template_versions where shift_template_id = (select id from app.shift_templates where tenant_id = (select id from app.tenants where slug='shr1') and code = 'NIGHT')), 1, '00000000-0000-0000-0000-000000027903', 'approver');
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> app.assign_employee_schedule: employee_not_found/employee_not_active/shift_template_version_not_available guarded; a real assignment succeeds at status=scheduled; C-01 full-tuple idempotency (identical replay returns the same row, a conflicting replay is rejected)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test');
  v_morning_version_id uuid := (select id from app.shift_template_versions where shift_template_id = (select id from app.shift_templates where tenant_id = v_tenant1 and code = 'MORNING') and status = 'published');
  v_assignment app.schedule_assignments;
  v_replay app.schedule_assignments;
begin
  begin
    perform app.assign_employee_schedule(v_tenant1, gen_random_uuid(), v_morning_version_id, '2026-08-17'::date, 'manual', null, '00000000-0000-0000-0000-000000027902', 'staff');
    raise exception 'assertion failed: an unknown employee_id should be rejected';
  exception when no_data_found then
    null;
  end;

  v_assignment := app.assign_employee_schedule(v_tenant1, v_emp1, v_morning_version_id, '2026-08-17'::date, 'manual', 'assign-emp1-0817', '00000000-0000-0000-0000-000000027902', 'staff');
  if v_assignment.status <> 'scheduled' then
    raise exception 'assertion failed: expected a new assignment to start scheduled, got %', v_assignment.status;
  end if;

  v_replay := app.assign_employee_schedule(v_tenant1, v_emp1, v_morning_version_id, '2026-08-17'::date, 'manual', 'assign-emp1-0817', '00000000-0000-0000-0000-000000027902', 'staff');
  if v_replay.id <> v_assignment.id then
    raise exception 'assertion failed: an identical replay must return the SAME row, never a duplicate';
  end if;
  if (select count(*) from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp1 and idempotency_key = 'assign-emp1-0817') <> 1 then
    raise exception 'assertion failed: expected exactly one row for this idempotency key';
  end if;

  begin
    perform app.assign_employee_schedule(v_tenant1, v_emp1, v_morning_version_id, '2026-08-18'::date, 'manual', 'assign-emp1-0817', '00000000-0000-0000-0000-000000027902', 'staff');
    raise exception 'assertion failed: same key, a DIFFERENT work_date must be rejected as a conflict, never silently applied';
  exception when unique_violation then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> app.assign_employee_schedule: superseding a still-DRAFT (scheduled) row is HRS:Edit; superseding an already-PUBLISHED row requires HRS:Override, not merely HRS:Edit (decision 5, blast-radius bar)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test');
  v_morning_version_id uuid := (select id from app.shift_template_versions where shift_template_id = (select id from app.shift_templates where tenant_id = v_tenant1 and code = 'MORNING') and status = 'published');
  v_prior uuid := (select id from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp1 and work_date = '2026-08-17'::date and status = 'scheduled');
  v_new app.schedule_assignments;
begin
  -- HRS:Edit alone (staff) may freely supersede a still-draft row.
  v_new := app.assign_employee_schedule(v_tenant1, v_emp1, v_morning_version_id, '2026-08-17'::date, 'manual', 'assign-emp1-0817-v2', '00000000-0000-0000-0000-000000027902', 'staff');
  if v_new.previous_assignment_id <> v_prior then
    raise exception 'assertion failed: expected the new row to link the superseded prior row';
  end if;
  if (select status from app.schedule_assignments where id = v_prior) <> 'superseded' then
    raise exception 'assertion failed: expected the prior row to be marked superseded';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> app.publish_schedule_assignments: HRS:Approve required; a real batch publish transitions scheduled->published, re-validates employee-active at publish time; RE-superseding the now-published row requires HRS:Override, HRS:Edit alone is rejected'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027903", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_results record;
  v_found boolean := false;
begin
  for v_results in select * from app.publish_schedule_assignments(v_tenant1, '2026-08-17'::date, '2026-08-17'::date, null, null, '00000000-0000-0000-0000-000000027903', 'approver') loop
    if v_results.published then
      v_found := true;
    end if;
  end loop;
  if not v_found then
    raise exception 'assertion failed: expected at least one assignment to be published';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test');
  v_morning_version_id uuid := (select id from app.shift_template_versions where shift_template_id = (select id from app.shift_templates where tenant_id = v_tenant1 and code = 'MORNING') and status = 'published');
begin
  if (select status from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp1 and work_date = '2026-08-17'::date and status = 'published') is null then
    raise exception 'assertion failed: expected the assignment to now be published';
  end if;

  begin
    perform app.assign_employee_schedule(v_tenant1, v_emp1, v_morning_version_id, '2026-08-17'::date, 'manual', 'assign-emp1-0817-v3', '00000000-0000-0000-0000-000000027902', 'staff');
    raise exception 'assertion failed: HRS:Edit alone must not be able to supersede an already-published assignment (requires HRS:Override)';
  exception when insufficient_privilege then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> app.cancel_schedule_assignment: cancelling a still-scheduled row is HRS:Edit; cancelling a published row requires HRS:Override; a non-empty reason is required'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test');
  v_published_id uuid := (select id from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp1 and work_date = '2026-08-17'::date and status = 'published');
begin
  begin
    perform app.cancel_schedule_assignment(v_published_id, 1, 'no longer needed', '00000000-0000-0000-0000-000000027902', 'staff');
    raise exception 'assertion failed: HRS:Edit alone must not be able to cancel a published assignment (requires HRS:Override)';
  exception when insufficient_privilege then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> roster cycles: app.create_roster_cycle/set_roster_cycle_slot/publish_roster_cycle -- an incomplete cycle (not every day-offset filled) cannot publish; a day-off (null shift) slot is a real, valid row; a complete 3-day cycle publishes'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_morning_id uuid := (select id from app.shift_templates where tenant_id = v_tenant1 and code = 'MORNING');
  v_cycle app.roster_cycles;
begin
  v_cycle := app.create_roster_cycle(v_tenant1, null, 'Morning-Morning-Off', 3, '00000000-0000-0000-0000-000000027902', 'staff');
  perform app.set_roster_cycle_slot(v_cycle.id, 0, v_morning_id, '00000000-0000-0000-0000-000000027902', 'staff');
  perform app.set_roster_cycle_slot(v_cycle.id, 1, v_morning_id, '00000000-0000-0000-0000-000000027902', 'staff');
  -- Day offset 2 deliberately left unset -- publish must reject. Switch to
  -- the approver's own session (caller-is-actor is enforced) for this one
  -- call, then switch back.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027903", "role": "authenticated"}', true);
  set local role authenticated;
  begin
    perform app.publish_roster_cycle(v_cycle.id, 1, '00000000-0000-0000-0000-000000027903', 'approver');
    raise exception 'assertion failed: expected incomplete_roster_cycle';
  exception when check_violation then
    null;
  end;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', true);
  set local role authenticated;

  perform app.set_roster_cycle_slot(v_cycle.id, 2, null, '00000000-0000-0000-0000-000000027902', 'staff');
  if (select count(*) from app.roster_cycle_slots where roster_cycle_id = v_cycle.id) <> 3 then
    raise exception 'assertion failed: expected 3 slot rows including the explicit day-off null-shift row';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027903", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_cycle_id uuid := (select id from app.roster_cycles where tenant_id = v_tenant1 and name = 'Morning-Morning-Off');
  v_published app.roster_cycles;
begin
  v_published := app.publish_roster_cycle(v_cycle_id, 1, '00000000-0000-0000-0000-000000027903', 'approver');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the now-complete cycle to publish';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> app.generate_roster_schedule_assignments: bounded (<=92 days) batch generation from the published cycle, real PLT-132 app.jobs tracking row (enqueue -> self-claim -> complete, decision 8); skips a day already covered by a PUBLISHED assignment (emp1''s own 2026-08-17); a >92-day range is rejected'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test');
  v_emp3 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@shr1.test');
  v_cycle_id uuid := (select id from app.roster_cycles where tenant_id = v_tenant1 and name = 'Morning-Morning-Off');
  v_result record;
  v_job app.jobs;
begin
  begin
    perform app.generate_roster_schedule_assignments(v_tenant1, v_cycle_id, array[v_emp1, v_emp3], '2026-08-17'::date, '2026-12-01'::date, '00000000-0000-0000-0000-000000027902', 'staff');
    raise exception 'assertion failed: a range over 92 days should be rejected';
  exception when check_violation then
    null;
  end;

  select * into v_result from app.generate_roster_schedule_assignments(v_tenant1, v_cycle_id, array[v_emp1, v_emp3], '2026-08-17'::date, '2026-08-19'::date, '00000000-0000-0000-0000-000000027902', 'staff');
  -- day_offset 0 (2026-08-17) = MORNING for both employees, but emp1 already
  -- has a PUBLISHED assignment there -> skipped for emp1, created for emp3.
  -- day_offset 1 (2026-08-18) = MORNING for both -> created for both.
  -- day_offset 2 (2026-08-19) = day off for both -> nothing to create.
  if v_result.created_count <> 3 or v_result.skipped_count <> 1 then
    raise exception 'assertion failed: expected created_count=3, skipped_count=1, got created=%, skipped=%', v_result.created_count, v_result.skipped_count;
  end if;

  select * into v_job from app.jobs where job_id = v_result.job_id;
  if v_job.status <> 'completed' or v_job.job_type <> 'roster_generation' then
    raise exception 'assertion failed: expected a real, completed app.jobs row of type roster_generation, got status=%, type=%', v_job.status, v_job.job_type;
  end if;

  if (select count(*) from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp3 and work_date in ('2026-08-17', '2026-08-18') and source = 'bulk_generated') <> 2 then
    raise exception 'assertion failed: expected 2 real bulk_generated assignments for emp3';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> PLT-132 (HRT-295, CG-S12-HRT-023): a genuine per-employee-day assignment failure is durably recorded and the batch job still reaches completed -- the OTHER employee in the SAME run still gets scheduled correctly. Run as postgres (no SET ROLE) -- a temporary CHECK constraint is DDL, which the authenticated role used elsewhere in this file has no privilege to issue.'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test');
  v_emp1_company uuid;
  v_emp1_branch uuid;
  v_emp_bad uuid;
  v_cycle_id uuid := (select id from app.roster_cycles where tenant_id = v_tenant1 and name = 'Morning-Morning-Off');
  v_result record;
  v_job app.jobs;
  v_audit_count integer;
  v_audit app.audit_logs;
begin
  select company_org_unit_id, branch_org_unit_id into v_emp1_company, v_emp1_branch from app.employees where master_record_id = v_emp1;

  -- A fresh, minimal, active employee -- the target of a temporary,
  -- narrowly-scoped CHECK constraint below.
  v_emp_bad := (app.create_employee_draft(
    v_tenant1, 'PLT132 Bad Employee', 'full_time', 'plt132badwork@shr1.test', 'plt132badp@shr1.test', '0800009999',
    null, null, null, '2024-01-01', v_emp1_company, v_emp1_branch, null, 'PLT-132 Test', null, null, null,
    'hr_created', 'idem-plt132-bad-shr1', '00000000-0000-0000-0000-000000027902', 'staff'
  )).master_record_id;
  perform app.add_employee_emergency_contact(v_emp_bad, 'Contact Bad', 'spouse', '0810009999', null, true, '00000000-0000-0000-0000-000000027902', 'staff');
  perform app.submit_employee_for_approval(v_emp_bad, 1, '00000000-0000-0000-0000-000000027902', 'staff');
  perform app.decide_employee_approval(v_emp_bad, 2, 'approve', null, '00000000-0000-0000-0000-000000027903', 'approver');
  perform app.activate_employee(v_emp_bad, 3, '00000000-0000-0000-0000-000000027903', 'approver');

  -- A temporary, narrowly-scoped CHECK constraint keyed to ONE real,
  -- already-committed employee's own id -- a genuine Postgres check_violation
  -- raised by real SQL execution against that employee's real
  -- app.schedule_assignments row, structurally indistinguishable from any of
  -- this schema's own dozens of pre-existing CHECK constraints (never an
  -- artificial statement-timeout). This deliberately uses a DIFFERENT real
  -- errcode (the default P0001/raise_exception, not check_violation) so this
  -- proof exercises the NEW `when others` branch specifically, never the
  -- pre-existing, unchanged four-code allowlist (insufficient_privilege/
  -- check_violation/no_data_found/unique_violation) that already silently
  -- skips a check_violation -- see this migration's own header. Dropped
  -- again at the end of this section for hygiene (scripts/db-tests/run.sh
  -- runs every *.sql file against the SAME disposable database in
  -- sequence).
  execute format(
    'create or replace function app._hrt295_plt132_sentinel_guard() returns trigger language plpgsql as $g$ begin if new.employee_id = %L then raise exception ''hrt295_plt132_sentinel_block: simulated real downstream rejection for employee %%'', new.employee_id; end if; return new; end; $g$;',
    v_emp_bad
  );
  execute 'create trigger hrt295_plt132_sentinel_guard before insert on app.schedule_assignments for each row execute function app._hrt295_plt132_sentinel_guard()';

  select * into v_result from app.generate_roster_schedule_assignments(v_tenant1, v_cycle_id, array[v_emp1, v_emp_bad], '2026-09-01'::date, '2026-09-02'::date, '00000000-0000-0000-0000-000000027902', 'staff');

  -- Before the HRT-295 fix, this uncaught exception (outside the pre-existing
  -- four-code allowlist) would have rolled back the ENTIRE transaction,
  -- including app.enqueue_job's own earlier INSERT -- HRT-294's own live
  -- reproduction found the job row simply gone afterward (neither pending
  -- nor dead_letter). Assert a REAL, terminal, non-lost row instead.
  select * into v_job from app.jobs where job_id = v_result.job_id;
  if v_job.job_id is null then
    raise exception 'CRITICAL (PLT-132 regression): the roster batch job row was lost entirely after a genuine per-employee-day failure -- exactly HRT-294''s own live-reproduced defect';
  end if;
  if v_job.status <> 'completed' then
    raise exception 'FAIL: expected the roster job to reach completed even with one genuinely failing employee, got %', v_job.status;
  end if;

  -- The healthy sibling employee (emp1) in the SAME run must still have been
  -- scheduled correctly for this brand-new date range (day_offset 0 =
  -- MORNING) -- one bad employee-day must never take the rest of the batch
  -- down with it.
  if (select count(*) from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp1 and work_date = '2026-09-01' and source = 'bulk_generated') <> 1 then
    raise exception 'FAIL: the healthy sibling employee (emp1) in the same roster run did not get a real bulk_generated assignment';
  end if;

  -- The failing employee must have zero rows left behind for EITHER day the
  -- trigger blocked (atomic per-item rollback) -- both 2026-09-01 and
  -- 2026-09-02 resolve to a MORNING shift for this cycle (offsets 0 and 1),
  -- so v_emp_bad genuinely fails BOTH days in this same run.
  if exists (select 1 from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp_bad and work_date in ('2026-09-01', '2026-09-02')) then
    raise exception 'FAIL: the genuinely failing employee must have zero schedule_assignments rows left behind for either blocked day (atomic per-item rollback)';
  end if;

  -- Real, durable, FINDABLE evidence of the specific failures -- queryable
  -- straight out of app.audit_logs, never merely a silent skipped_count
  -- increment. Exactly TWO rows -- one per genuinely failing day.
  select count(*) into v_audit_count from app.audit_logs
    where action = 'generate_roster_schedule_assignments_item_failed' and resource_type = 'app.employees' and resource_id = v_emp_bad and result = 'failure';
  if v_audit_count <> 2 then
    raise exception 'FAIL: expected exactly two durable, findable failure audit rows (one per blocked day) for the genuinely failing employee, got %', v_audit_count;
  end if;

  select * into v_audit from app.audit_logs where action = 'generate_roster_schedule_assignments_item_failed' and resource_id = v_emp_bad and (after_value ->> 'work_date') = '2026-09-01';
  if v_audit.reason is null or v_audit.reason not like '%hrt295_plt132_sentinel_block%' then
    raise exception 'FAIL: expected the durable failure record to carry the REAL error detail (the sentinel trigger message), got %', v_audit.reason;
  end if;
  if (v_audit.after_value ->> 'job_id')::uuid <> v_job.job_id then
    raise exception 'FAIL: the durable failure record must correlate back to the same job_id';
  end if;

  execute 'drop trigger hrt295_plt132_sentinel_guard on app.schedule_assignments';
  execute 'drop function app._hrt295_plt132_sentinel_guard()';

  raise notice 'PASS (PLT-132/HRT-295, roster): a genuine per-employee-day assignment failure outside the pre-existing four-code allowlist no longer loses the batch job row -- it reaches completed, the failing employee''s own state is cleanly rolled back, the healthy sibling employee (emp1) in the same run still gets scheduled correctly, and the failure itself is durably recorded and findable in app.audit_logs with real error detail';
end $$;

\echo '>> app.set_roster_holiday / app.list_roster_holidays: a real holiday is created; a same-date re-set replaces (never duplicates) the active row'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
begin
  perform app.set_roster_holiday(v_tenant1, null, '2026-12-25'::date, 'Christmas', false, '00000000-0000-0000-0000-000000027902', 'staff');
  perform app.set_roster_holiday(v_tenant1, null, '2026-12-25'::date, 'Christmas Day (corrected)', false, '00000000-0000-0000-0000-000000027902', 'staff');
  if (select count(*) from app.roster_holidays where tenant_id = v_tenant1 and holiday_date = '2026-12-25'::date and status = 'active') <> 1 then
    raise exception 'assertion failed: expected exactly one ACTIVE holiday row for this date after a corrective re-set';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> coverage requirement + preview: a real min_headcount=2 requirement on MORNING/Monday is created; the preview correctly reports below_minimum (1 scheduled) then met (2 scheduled) after a second real assignment is published'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'BR-SHR1');
  v_morning_id uuid := (select id from app.shift_templates where tenant_id = v_tenant1 and code = 'MORNING');
  v_day_of_week integer := extract(dow from '2026-08-18'::date)::integer;
begin
  perform app.set_schedule_coverage_requirement(v_tenant1, v_branch, v_morning_id, v_day_of_week, 2, '00000000-0000-0000-0000-000000027902', 'staff');
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

-- Publish only ONE of the two bulk-generated 2026-08-18 assignments (emp1's)
-- first, so the coverage preview genuinely observes an intermediate
-- below_minimum state (1 published) before the second publish below flips it
-- to met (2 published) -- both bulk_generated rows started status=scheduled
-- and app.get_schedule_coverage_preview counts PUBLISHED rows only.
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027903", "role": "authenticated"}', false);
set role authenticated;
select app.publish_schedule_assignments(
  (select id from app.tenants where slug='shr1'), '2026-08-18'::date, '2026-08-18'::date, null,
  (select master_record_id from app.employees where tenant_id = (select id from app.tenants where slug='shr1') and work_email = 'emp1work@shr1.test'),
  '00000000-0000-0000-0000-000000027903', 'approver'
);
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_row record;
  v_below boolean := false;
begin
  for v_row in select * from app.get_schedule_coverage_preview(v_tenant1, '00000000-0000-0000-0000-000000027902', null, '2026-08-18'::date, '2026-08-18'::date) loop
    if v_row.coverage_status = 'below_minimum' and v_row.scheduled_count = 1 and v_row.min_headcount = 2 then
      v_below := true;
    end if;
  end loop;
  if not v_below then
    raise exception 'assertion failed: expected a real below_minimum row (1 scheduled bulk_generated employee against min_headcount=2) for 2026-08-18';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027903", "role": "authenticated"}', false);
set role authenticated;
select app.publish_schedule_assignments((select id from app.tenants where slug='shr1'), '2026-08-18'::date, '2026-08-18'::date, null, null, '00000000-0000-0000-0000-000000027903', 'approver');
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_row record;
  v_met boolean := false;
begin
  for v_row in select * from app.get_schedule_coverage_preview(v_tenant1, '00000000-0000-0000-0000-000000027902', null, '2026-08-18'::date, '2026-08-18'::date) loop
    if v_row.coverage_status = 'met' and v_row.scheduled_count = 2 then
      v_met := true;
    end if;
  end loop;
  if not v_met then
    raise exception 'assertion failed: expected coverage to flip to met (2 scheduled) once both employees'' assignments are published';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> swap fixtures: three fresh, manually-assigned-and-published emp1/emp2 pairs on dates entirely outside the bulk-generated 08-17..08-19 range (never colliding with emp3''s own bulk-generated rows against the partial unique index, which covers scheduled+published together)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test');
  v_emp2 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@shr1.test');
  v_morning_version_id uuid := (select id from app.shift_template_versions where shift_template_id = (select id from app.shift_templates where tenant_id = v_tenant1 and code = 'MORNING') and status = 'published');
  v_dates date[] := array['2026-09-10', '2026-09-11', '2026-09-12', '2026-09-13', '2026-09-14', '2026-09-15']::date[];
  v_d date;
  v_i integer := 1;
begin
  foreach v_d in array v_dates loop
    perform app.assign_employee_schedule(v_tenant1, case when v_i % 2 = 1 then v_emp1 else v_emp2 end, v_morning_version_id, v_d, 'manual', 'swap-fixture-' || v_d::text, '00000000-0000-0000-0000-000000027902', 'staff');
    v_i := v_i + 1;
  end loop;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027903", "role": "authenticated"}', false);
set role authenticated;
select app.publish_schedule_assignments((select id from app.tenants where slug='shr1'), '2026-09-10'::date, '2026-09-15'::date, null, null, '00000000-0000-0000-0000-000000027903', 'approver');
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> swap request: app.request_schedule_swap (self-only or HRS:Edit), app.decide_schedule_swap_request (HRS:Approve, self-approval blocked for EITHER party, C-18), app.cancel_schedule_swap_request. A real approve genuinely swaps employee_id between the two published assignments.'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027904", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test');
  v_emp2 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@shr1.test');
  v_emp1_assignment_id uuid;
  v_emp2_assignment_id uuid;
  v_request app.schedule_swap_requests;
begin
  -- Batch 278-280 Tier C fix propagation: resolved under a momentarily
  -- elevated LOCAL role (reverted before any RPC call below), because the
  -- batch's own RLS hardening (20260730960000) now correctly scopes a raw
  -- app.schedule_assignments SELECT to self/manager/HRS:View -- emp1
  -- (self-service, no HRS:View, not emp2's manager) legitimately cannot see
  -- emp2's own row via a raw SELECT any more, exactly the fix this same
  -- batch's review round required. This is test-arrangement only
  -- (constructing the RPC call's own arguments from already-known fixture
  -- rows, never the actor identity the RPC calls below authenticate as,
  -- which remains governed entirely by request.jwt.claims + the explicit
  -- p_actor_auth_user_id argument), never the behavior under test.
  set local role postgres;
  v_emp1_assignment_id := (select id from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp1 and work_date = '2026-09-10'::date and status = 'published');
  v_emp2_assignment_id := (select id from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp2 and work_date = '2026-09-11'::date and status = 'published');
  set local role authenticated;
  begin
    -- p_assignment_id belongs to emp2, not the caller (emp1) -- a
    -- well-formed target pair (emp1/v_emp1_assignment_id) so the function
    -- reaches its identity check rather than an earlier target-mismatch
    -- check.
    perform app.request_schedule_swap(v_emp2_assignment_id, v_emp1, v_emp1_assignment_id, 'not my own shift', null, '00000000-0000-0000-0000-000000027904', 'emp1');
    raise exception 'assertion failed: emp1 must not be able to propose a swap using an assignment that is not their own (identity-match required for self-service)';
  exception when insufficient_privilege then
    null;
  end;

  v_request := app.request_schedule_swap(v_emp1_assignment_id, v_emp2, v_emp2_assignment_id, 'family event', 'swap-emp1-emp2', '00000000-0000-0000-0000-000000027904', 'emp1');
  if v_request.status <> 'pending_approval' then
    raise exception 'assertion failed: expected a new swap request to start pending_approval';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> C-18: neither the requester NOR the target may decide their own swap, even if they somehow also held HRS:Approve'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027904", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_request_id uuid := (select id from app.schedule_swap_requests where idempotency_key = 'swap-emp1-emp2');
begin
  begin
    perform app.decide_schedule_swap_request(v_request_id, 1, 'approve', 'self-approving', '00000000-0000-0000-0000-000000027904', 'emp1');
    raise exception 'assertion failed: emp1 (requester) must not be able to decide their own swap request';
  exception when insufficient_privilege then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> a real HRS:Approve decision genuinely swaps employee_id between the two assignments'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027903", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test');
  v_emp2 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@shr1.test');
  v_request_id uuid := (select id from app.schedule_swap_requests where idempotency_key = 'swap-emp1-emp2');
  v_emp1_assignment_id uuid := (select id from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp1 and work_date = '2026-09-10'::date and status = 'published');
  v_emp2_assignment_id uuid := (select id from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp2 and work_date = '2026-09-11'::date and status = 'published');
  v_decided app.schedule_swap_requests;
begin
  v_decided := app.decide_schedule_swap_request(v_request_id, 1, 'approve', 'approved, coverage unaffected', '00000000-0000-0000-0000-000000027903', 'approver');
  if v_decided.status <> 'approved' then
    raise exception 'assertion failed: expected approved status';
  end if;
  if (select employee_id from app.schedule_assignments where id = v_emp1_assignment_id) <> v_emp2 then
    raise exception 'assertion failed: expected the 2026-09-10 assignment to now belong to emp2';
  end if;
  if (select employee_id from app.schedule_assignments where id = v_emp2_assignment_id) <> v_emp1 then
    raise exception 'assertion failed: expected the 2026-09-11 assignment to now belong to emp1';
  end if;

  begin
    perform app.decide_schedule_swap_request(v_request_id, 1, 'approve', 'double-decide', '00000000-0000-0000-0000-000000027903', 'approver');
    raise exception 'assertion failed: an already-decided swap request must not be decidable again';
  exception when check_violation then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> HRT-293 Finding B regression: app.decide_schedule_swap_request/app.cancel_schedule_assignment/app.cancel_schedule_swap_request no longer duplicate their raw decided_reason/cancel_reason ("approved, coverage unaffected" / "shift no longer needed" / "no longer needed", all used above) into THEIR OWN app.audit_logs.reason rows. Scoped by action name (not a bare reason-string match): several OTHER, unrelated capabilities in this repository coincidentally reuse the identical generic fixture string "no longer needed" for their own real, correctly-non-sensitive audit reasons (e.g. app.release_inventory_reservation, app.set_warehouse_status) -- a bare string match without the action filter is a false-positive trap, not a real defect, self-found while first exercising this exact assertion live.'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_fixed_actions text[] := array['decide_schedule_swap_request', 'cancel_schedule_assignment', 'cancel_schedule_swap_request'];
begin
  if exists (select 1 from app.audit_logs where reason in ('approved, coverage unaffected', 'shift no longer needed', 'no longer needed') and action = any (v_fixed_actions)) then
    raise exception 'HRT-293 Finding B regression: app.audit_logs.reason must never carry a raw schedule-assignment/swap-request reason for decide_schedule_swap_request/cancel_schedule_assignment/cancel_schedule_swap_request';
  end if;
  if exists (select 1 from app.query_audit_logs('00000000-0000-0000-0000-000000027901', v_tenant1, 500) where reason in ('approved, coverage unaffected', 'shift no longer needed', 'no longer needed') and action = any (v_fixed_actions)) then
    raise exception 'HRT-293 Finding B regression: a plain tenant_admin must never see a raw schedule-assignment/swap-request reason via app.query_audit_logs for these actions';
  end if;
end $$;

\echo '>> decision 6: cancelling a schedule assignment that a PENDING swap request depends on cancels the swap request too, never leaves it silently stranded'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027904", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test');
  v_emp2 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@shr1.test');
  v_dep_assignment_id uuid;
  v_dep_target_id uuid;
  v_dep_request app.schedule_swap_requests;
begin
  -- Batch 278-280 Tier C fix propagation: v_dep_target_id (emp2's own row)
  -- resolved under a momentarily elevated LOCAL role (reverted before the
  -- RPC call below), for the exact same reason as the earlier swap-request
  -- block above -- emp1 cannot see emp2's raw schedule_assignments row
  -- post-fix; test-arrangement only.
  set local role postgres;
  v_dep_assignment_id := (select id from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp1 and work_date = '2026-09-12'::date and status = 'published');
  v_dep_target_id := (select id from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp2 and work_date = '2026-09-13'::date and status = 'published');
  set local role authenticated;
  v_dep_request := app.request_schedule_swap(v_dep_assignment_id, v_emp2, v_dep_target_id, 'testing cancel cascade', 'swap-cancel-cascade', '00000000-0000-0000-0000-000000027904', 'emp1');

  -- Cancelling an already-PUBLISHED assignment is HRS:Override (decision 5's
  -- blast-radius bar) -- the approver, not plain HRS:Edit staff.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027903", "role": "authenticated"}', true);
  set local role authenticated;
  perform app.cancel_schedule_assignment(v_dep_assignment_id, 1, 'shift no longer needed', '00000000-0000-0000-0000-000000027903', 'approver');

  if (select status from app.schedule_swap_requests where id = v_dep_request.id) <> 'cancelled' then
    raise exception 'assertion failed: expected the dependent pending swap request to be auto-cancelled, never left stranded pending_approval';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> app.cancel_schedule_swap_request: self-cancel by the requester while pending'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027904", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@shr1.test');
  v_emp2 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@shr1.test');
  v_a uuid;
  v_b uuid;
  v_req app.schedule_swap_requests;
  v_cancelled app.schedule_swap_requests;
begin
  -- Batch 278-280 Tier C fix propagation: v_b (emp2's own row) resolved
  -- under a momentarily elevated LOCAL role (reverted before the RPC call
  -- below) -- same reason as the earlier swap-request blocks above.
  set local role postgres;
  v_a := (select id from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp1 and work_date = '2026-09-14'::date and status = 'published');
  v_b := (select id from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_emp2 and work_date = '2026-09-15'::date and status = 'published');
  set local role authenticated;
  v_req := app.request_schedule_swap(v_a, v_emp2, v_b, 'changed my mind test', 'swap-self-cancel', '00000000-0000-0000-0000-000000027904', 'emp1');
  v_cancelled := app.cancel_schedule_swap_request(v_req.id, 1, 'no longer needed', '00000000-0000-0000-0000-000000027904', 'emp1');
  if v_cancelled.status <> 'cancelled' then
    raise exception 'assertion failed: expected self-cancel to succeed';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> list_schedule_assignments (section 26): HRS:View holders see the tenant-wide list; a plain employee with no HRS:View sees only self + direct reports, never a stranger''s row'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027906", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_emp2 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@shr1.test');
  v_emp3 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@shr1.test');
  v_saw_report boolean := false;
  v_saw_stranger boolean := false;
  v_row record;
begin
  -- mgr1 (no HRS:View) manages emp2 -- should see emp2's own rows if any
  -- exist, and must never see emp3's rows (not a direct report, not self).
  for v_row in select * from app.list_schedule_assignments(v_tenant1, '00000000-0000-0000-0000-000000027906', null, null, null, null, 50, null) loop
    if v_row.employee_id = v_emp2 then v_saw_report := true; end if;
    if v_row.employee_id = v_emp3 then v_saw_stranger := true; end if;
  end loop;
  if v_saw_stranger then
    raise exception 'assertion failed: a manager with no HRS:View must never see a non-report''s schedule assignment';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> C-05: cross-tenant fold to not-found -- shr2''s own HRS:Edit staff gets shift_template_not_found (never a real tenant_id disclosure) probing shr1''s own shift template id'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027923", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_shr1_tpl_id uuid := (select id from app.shift_templates where tenant_id = (select id from app.tenants where slug='shr1') and code = 'MORNING');
begin
  begin
    perform app.create_shift_template_version(v_shr1_tpl_id, 'Asia/Jakarta', '00:00:00'::time, 'fixed', 15, 15, '2024-01-01'::date, jsonb_build_array(jsonb_build_object('segment_type', 'work', 'start_time', '08:00:00', 'end_time', '17:00:00')), '00000000-0000-0000-0000-000000027923', 'staff2');
    raise exception 'assertion failed: expected shift_template_not_found for a cross-tenant probe';
  exception when no_data_found then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> cross-tenant isolation sweep: shr2''s own admin sees zero shr1 rows across every new table via the RLS-scoped read RPCs'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027921", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_cnt integer;
begin
  select count(*) into v_cnt from app.list_shift_templates(v_tenant1, '00000000-0000-0000-0000-000000027921');
  if v_cnt <> 0 then raise exception 'assertion failed: expected zero shr1 shift templates visible to a shr2 actor'; end if;
  select count(*) into v_cnt from app.list_roster_cycles(v_tenant1, '00000000-0000-0000-0000-000000027921');
  if v_cnt <> 0 then raise exception 'assertion failed: expected zero shr1 roster cycles visible to a shr2 actor'; end if;
  select count(*) into v_cnt from app.list_schedule_assignments(v_tenant1, '00000000-0000-0000-0000-000000027921', null, null, null, null, 50, null);
  if v_cnt <> 0 then raise exception 'assertion failed: expected zero shr1 schedule assignments visible to a shr2 actor'; end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> HRT-279 <-> HRT-278 integration (own additive migration 20260730920000): a self-service clock-in resolves and carries the PUBLISHED schedule_assignment_id when one exists for that employee/work_date; stays null when none exists (structurally optional, zero behavior change otherwise)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'BR-SHR1');
  v_policy app.attendance_policies;
  v_version app.attendance_policy_versions;
begin
  v_policy := app.create_attendance_policy(v_tenant1, null, 'Shr1 Tenant-Wide', '00000000-0000-0000-0000-000000027902', 'tester');
  v_version := app.create_attendance_policy_version(
    v_policy.id, 'Asia/Jakarta', '00:00:00'::time, '23:59:00'::time, '00:00:00'::time, 15, 15,
    array['mobile_web', 'kiosk']::text[], 'none', null, null, 20, '2024-01-01'::date,
    '00000000-0000-0000-0000-000000027902', 'tester'
  );
  perform app.publish_attendance_policy_version(v_version.id, 1, '00000000-0000-0000-0000-000000027903', 'tester');
end $$;

\echo '>> mgr1 gets a real PUBLISHED schedule_assignment for TODAY''s own real, live-resolved work_date (app._ingest_attendance_event''s own work_date bucketing, never a hardcoded fixture date -- attendance''s work_date is always resolved from clock_timestamp(), never from a client-supplied or test-fixed timestamp, per HRT-278''s own anti-spoofing design) -- their own clock-in today should carry it'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_mgr1 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@shr1.test');
  v_morning_version_id uuid := (select id from app.shift_template_versions where shift_template_id = (select id from app.shift_templates where tenant_id = v_tenant1 and code = 'MORNING') and status = 'published');
  v_today_work_date date := app.resolve_attendance_workday(clock_timestamp(), 'Asia/Jakarta', '00:00:00'::time);
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027902", "role": "authenticated"}', true);
  set local role authenticated;
  perform app.assign_employee_schedule(v_tenant1, v_mgr1, v_morning_version_id, v_today_work_date, 'manual', 'integration-mgr1-today', '00000000-0000-0000-0000-000000027902', 'staff');

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027903", "role": "authenticated"}', true);
  set local role authenticated;
  perform app.publish_schedule_assignments(v_tenant1, v_today_work_date, v_today_work_date, null, v_mgr1, '00000000-0000-0000-0000-000000027903', 'approver');
end $$;

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027906", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='shr1');
  v_mgr1 uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@shr1.test');
  v_today_work_date date := app.resolve_attendance_workday(clock_timestamp(), 'Asia/Jakarta', '00:00:00'::time);
  v_expected_assignment_id uuid := (select id from app.schedule_assignments where tenant_id = v_tenant1 and employee_id = v_mgr1 and work_date = v_today_work_date and status = 'published');
  v_event app.attendance_events;
  v_session_assignment_id uuid;
begin
  if v_expected_assignment_id is null then
    raise exception 'assertion failed: fixture setup failed -- expected a real published assignment for mgr1/%', v_today_work_date;
  end if;
  v_event := app.record_attendance_clock_event(v_tenant1, 'clock_in', 'mobile_web', now(), null, null, 'integration-clockin-mgr1', '00000000-0000-0000-0000-000000027906', 'mgr1');
  select schedule_assignment_id into v_session_assignment_id from app.attendance_sessions where id = v_event.session_id;
  if v_session_assignment_id is distinct from v_expected_assignment_id then
    raise exception 'assertion failed: expected the new attendance session to carry schedule_assignment_id=%, got %', v_expected_assignment_id, v_session_assignment_id;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> emp3 has NO roster assignment covering today -- their clock-in must leave schedule_assignment_id null, never error, never a fabricated link (decision 9, structurally optional)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027907", "role": "authenticated"}', false);
set role authenticated;
do $$
declare
  v_event app.attendance_events;
  v_session_assignment_id uuid;
begin
  v_event := app.record_attendance_clock_event((select id from app.tenants where slug='shr1'), 'clock_in', 'mobile_web', now(), null, null, 'integration-clockin-emp3', '00000000-0000-0000-0000-000000027907', 'emp3');
  if v_event.id is null then
    raise exception 'assertion failed: expected a real attendance event to be created regardless of roster adoption';
  end if;
  select schedule_assignment_id into v_session_assignment_id from app.attendance_sessions where id = v_event.session_id;
  if v_session_assignment_id is not null then
    raise exception 'assertion failed: expected schedule_assignment_id to stay null when no roster assignment exists for this employee/work_date';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> schema-privilege defense in depth: anon holds no direct table/EXECUTE access; authenticated has column-restricted grants on cancel_reason/reason/decided_reason (never projected by any read RPC); service_role has full access'
set role anon;
do $$
begin
  begin
    perform count(*) from app.schedule_assignments;
    raise exception 'assertion failed: anon must not read schedule_assignments';
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
  select has_column_privilege('authenticated', 'app.schedule_assignments', 'cancel_reason', 'select') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not read schedule_assignments.cancel_reason'; end if;
  select has_column_privilege('authenticated', 'app.schedule_swap_requests', 'reason', 'select') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not read schedule_swap_requests.reason'; end if;
  select has_column_privilege('authenticated', 'app.schedule_swap_requests', 'decided_reason', 'select') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not read schedule_swap_requests.decided_reason'; end if;
  -- Non-sensitive columns remain readable (never over-restricted).
  select has_column_privilege('authenticated', 'app.schedule_assignments', 'work_date', 'select') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: authenticated should read schedule_assignments.work_date'; end if;
end $$;

do $$
declare
  v_has_priv boolean;
begin
  select has_function_privilege('authenticated', 'app.enqueue_job(uuid,text,jsonb,integer,text,integer,uuid,text)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: authenticated should still be able to call app.enqueue_job (unchanged by this migration)'; end if;
  select has_function_privilege('authenticated', 'app.generic_job_types()', 'EXECUTE') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: authenticated should still be able to call app.generic_job_types (unchanged ACL, CREATE OR REPLACE preserves it)'; end if;
end $$;

\echo '>> RLS default-deny: a forged cross-tenant staff session cannot see shr1''s own rows via the raw table (RLS still gates even with a column-restricted grant)'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027923", "role": "authenticated"}', false);
set role authenticated;
select count(*) as should_be_zero from app.schedule_assignments where tenant_id = (select id from app.tenants where slug='shr1');
reset role;
select set_config('request.jwt.claims', 'null', false);

\echo '>> ATW-031 (ISS-2026-012) drift gate, HRT-279''s own scoped re-check: the app.jobs job_type CHECK constraint and app.all_job_types() both carry roster_generation (the SAME extraction technique scripts/db-tests/background-job.sql''s own standing whole-list drift gate uses, scoped here to confirm THIS checkpoint''s own addition landed on both sources of truth, not just one)'
do $$
declare
  v_check_types text[];
  v_all_types text[] := app.all_job_types();
begin
  select array_agg(m[1] order by m[1]) into v_check_types
  from regexp_matches(
    (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'app.jobs'::regclass and conname like '%job_type%'),
    '''([a-z_]+)''::text', 'g'
  ) as m;

  if not ('roster_generation' = any (v_check_types)) then
    raise exception 'assertion failed: expected roster_generation present in the app.jobs job_type CHECK constraint, got %', v_check_types;
  end if;
  if not ('roster_generation' = any (v_all_types)) then
    raise exception 'assertion failed: expected roster_generation present in app.all_job_types(), got %', v_all_types;
  end if;
end $$;

\echo 'ALL HRT-279 db-test assertions passed.'
