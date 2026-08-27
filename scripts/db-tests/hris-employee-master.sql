-- Real, executable test evidence for HRT-274 (Employee Master, CG-S12-HRT-002) --
-- run via `pnpm run db:test` against a real, disposable Postgres database. Mirrors
-- scripts/db-tests/procurement-vendor-registration.sql's own mandatory two-tenant
-- cross-isolation convention (docs/standards/TESTING_STANDARDS.md §8).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (hrmemp1, hrmemp2). hrmemp1 gets a tenant_admin, HR staff (HRS Create/Edit/Import), an approver (HRS Approve/Reject/View), an override manager (HRS Override/Edit/View), a personal-data-viewer (HRS View + View personal data), a view-only actor, and a customer_user-layer actor, plus company/branch/department org units, a manager employee (linked to its own Platform user) and a report employee (linked to its own Platform user). hrmemp2 gets a tenant_admin and HR staff for cross-tenant checks. A global Supreme Admin is also seeded.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_staff_role uuid;
  v_staff_draft app.role_versions;
  v_approver_role uuid;
  v_approver_draft app.role_versions;
  v_manager_role uuid;
  v_manager_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_pdv_role uuid;
  v_pdv_draft app.role_versions;
  v_t2_staff_role uuid;
  v_t2_staff_draft app.role_versions;
  v_company uuid;
  v_branch uuid;
  v_department uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000027101', 'admin@hrmemp1.test'),
    ('00000000-0000-0000-0000-000000027102', 'staff@hrmemp1.test'),
    ('00000000-0000-0000-0000-000000027103', 'approver@hrmemp1.test'),
    ('00000000-0000-0000-0000-000000027104', 'manager@hrmemp1.test'),
    ('00000000-0000-0000-0000-000000027105', 'viewer@hrmemp1.test'),
    ('00000000-0000-0000-0000-000000027106', 'customer@hrmemp1.test'),
    ('00000000-0000-0000-0000-000000027107', 'pdv@hrmemp1.test'),
    ('00000000-0000-0000-0000-000000027108', 'mgrperson@hrmemp1.test'),
    ('00000000-0000-0000-0000-000000027109', 'reportperson@hrmemp1.test'),
    ('00000000-0000-0000-0000-000000027201', 'admin@hrmemp2.test'),
    ('00000000-0000-0000-0000-000000027202', 'staff@hrmemp2.test'),
    ('00000000-0000-0000-0000-000000027999', 'supreme@hrmemp.test');

  perform app.provision_tenant('hrmemp1', 'HR Emp Co 1', 'idem-hrmemp1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'hrmemp1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('hrmemp2', 'HR Emp Co 2', 'idem-hrmemp2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'hrmemp2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027101', 'admin@hrmemp1.test', 'Hrmemp1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@hrmemp1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027102', 'staff@hrmemp1.test', 'Hrmemp1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@hrmemp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027103', 'approver@hrmemp1.test', 'Hrmemp1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@hrmemp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027104', 'manager@hrmemp1.test', 'Hrmemp1 Override Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@hrmemp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027105', 'viewer@hrmemp1.test', 'Hrmemp1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@hrmemp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027106', 'customer@hrmemp1.test', 'Hrmemp1 Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer@hrmemp1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027106', 'customer_user', v_tenant1, 'external-customer-account', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027107', 'pdv@hrmemp1.test', 'Hrmemp1 Personal Data Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'pdv@hrmemp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027108', 'mgrperson@hrmemp1.test', 'Hrmemp1 Manager Person', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'mgrperson@hrmemp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027109', 'reportperson@hrmemp1.test', 'Hrmemp1 Report Person', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'reportperson@hrmemp1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027201', 'admin@hrmemp2.test', 'Hrmemp2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@hrmemp2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027201', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027202', 'staff@hrmemp2.test', 'Hrmemp2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@hrmemp2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027999', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'HRS Staff', 'Create/Edit/View/Import drafts', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View', 'Import')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000027102', '00000000-0000-0000-0000-000000027101', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'HRS Approver', 'Approve/Reject/View', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Approve', 'Reject', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000027103', '00000000-0000-0000-0000-000000027101', 'tester');

  v_manager_role := (app.create_role(v_tenant1, 'HRS Override Manager', 'Override/Edit/View', 'tester')).id;
  v_manager_draft := app.create_role_version(v_manager_role, 'tester');
  perform app.set_role_version_permissions(v_manager_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Override', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000027104', '00000000-0000-0000-0000-000000027101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'HRS Viewer', 'View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000027105', '00000000-0000-0000-0000-000000027101', 'tester');

  v_pdv_role := (app.create_role(v_tenant1, 'HRS Personal Data Viewer', 'View + View personal data', 'tester')).id;
  v_pdv_draft := app.create_role_version(v_pdv_role, 'tester');
  perform app.set_role_version_permissions(v_pdv_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('View', 'View personal data')), 'tester');
  perform app.publish_role_version(v_pdv_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_pdv_role and status = 'published'), '00000000-0000-0000-0000-000000027107', '00000000-0000-0000-0000-000000027101', 'tester');

  v_t2_staff_role := (app.create_role(v_tenant2, 'HRS Staff T2', 'Create/Edit/View', 'tester')).id;
  v_t2_staff_draft := app.create_role_version(v_t2_staff_role, 'tester');
  perform app.set_role_version_permissions(v_t2_staff_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_t2_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000027202', '00000000-0000-0000-0000-000000027201', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-HR1', 'Hrmemp1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-HR1', 'Hrmemp1 Branch', 'tester')).id;
  v_department := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-HR1', 'Hrmemp1 Dept', 'tester')).id;
end;
$$;

\echo '>> RBAC seed: the four new HRS permission rows exist exactly once'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.permissions where resource_module_code = 'HRS' and action in ('Reject', 'Import', 'Download', 'Override');
  if v_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 new HRS permission rows, found %', v_count;
  end if;
end;
$$;

\echo '>> master_type_code=''employee'' is registered, scope=tenant, owner_module_code=HRS'
do $$
declare
  v_type app.master_types;
begin
  select * into v_type from app.master_types where code = 'employee';
  if not found or v_type.scope <> 'tenant' or v_type.owner_module_code <> 'HRS' then
    raise exception 'assertion failed: expected master_type ''employee'' registered tenant-scoped under HRS, got %', v_type;
  end if;
end;
$$;

\echo '>> full lifecycle happy path: draft (missing fields blocks submit) -> add emergency contact + hire_date + org unit -> submit -> approve -> activate -> start leave -> end leave -> suspend -> reactivate -> terminate'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_approver uuid := '00000000-0000-0000-0000-000000027103';
  v_manager uuid := '00000000-0000-0000-0000-000000027104';
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HR1');
  v_employee app.employees;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'Budi Santoso', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-lifecycle-1', v_staff, 'staff');
  if v_employee.lifecycle_status <> 'draft' then
    raise exception 'assertion failed: expected a new employee to start draft, got %', v_employee.lifecycle_status;
  end if;

  begin
    perform app.submit_employee_for_approval(v_employee.master_record_id, v_employee.record_version, v_staff, 'staff');
    raise exception 'assertion failed: expected missing_required_field for a submit with no hire_date/org unit';
  exception
    when others then
      if sqlerrm not like 'missing_required_field%' then raise; end if;
  end;

  v_employee := app.update_employee_draft(v_employee.master_record_id, v_employee.record_version, 'Budi Santoso', 'full_time', 'budi@hrmemp1.test', null, null, null, null, null, '2026-01-15', null, v_company, null, null, 'Staff Analyst', null, v_staff, 'staff');

  begin
    perform app.submit_employee_for_approval(v_employee.master_record_id, v_employee.record_version, v_staff, 'staff');
    raise exception 'assertion failed: expected missing_required_contact for a submit with no emergency contact';
  exception
    when others then
      if sqlerrm not like 'missing_required_contact%' then raise; end if;
  end;

  perform app.add_employee_emergency_contact(v_employee.master_record_id, 'Ibu Santoso', 'Mother', '+62-811-1', null, true, v_staff, 'staff');

  v_employee := app.submit_employee_for_approval(v_employee.master_record_id, v_employee.record_version, v_staff, 'staff');
  if v_employee.lifecycle_status <> 'submitted' then
    raise exception 'assertion failed: expected submitted, got %', v_employee.lifecycle_status;
  end if;

  v_employee := app.decide_employee_approval(v_employee.master_record_id, v_employee.record_version, 'approve', null, v_approver, 'approver');
  if v_employee.lifecycle_status <> 'approved' then
    raise exception 'assertion failed: expected approved, got %', v_employee.lifecycle_status;
  end if;

  v_employee := app.activate_employee(v_employee.master_record_id, v_employee.record_version, v_approver, 'approver');
  if v_employee.lifecycle_status <> 'active' then
    raise exception 'assertion failed: expected active, got %', v_employee.lifecycle_status;
  end if;

  v_employee := app.start_employee_leave(v_employee.master_record_id, v_employee.record_version, 'annual leave', v_staff, 'staff');
  if v_employee.lifecycle_status <> 'on_leave' then
    raise exception 'assertion failed: expected on_leave, got %', v_employee.lifecycle_status;
  end if;

  v_employee := app.end_employee_leave(v_employee.master_record_id, v_employee.record_version, v_staff, 'staff');
  if v_employee.lifecycle_status <> 'active' then
    raise exception 'assertion failed: expected active after end_employee_leave, got %', v_employee.lifecycle_status;
  end if;

  v_employee := app.suspend_employee(v_employee.master_record_id, v_employee.record_version, 'under investigation', v_manager, 'manager');
  if v_employee.lifecycle_status <> 'suspended' then
    raise exception 'assertion failed: expected suspended, got %', v_employee.lifecycle_status;
  end if;

  v_employee := app.reactivate_employee(v_employee.master_record_id, v_employee.record_version, v_manager, 'manager');
  if v_employee.lifecycle_status <> 'active' then
    raise exception 'assertion failed: expected active after reactivate, got %', v_employee.lifecycle_status;
  end if;

  v_employee := app.terminate_employee(v_employee.master_record_id, v_employee.record_version, 'resignation', '2026-06-30', v_manager, 'manager');
  if v_employee.lifecycle_status <> 'terminated' or v_employee.employment_end_date::text <> '2026-06-30' then
    raise exception 'assertion failed: expected terminated with employment_end_date 2026-06-30, got %/%', v_employee.lifecycle_status, v_employee.employment_end_date;
  end if;

  -- Never a hard delete: the row and every child/history row survive termination.
  if not exists (select 1 from app.employee_emergency_contacts where master_record_id = v_employee.master_record_id and status = 'active') then
    raise exception 'assertion failed: expected the emergency contact to survive termination unchanged';
  end if;

  v_employee := app.archive_employee_profile(v_employee.master_record_id, v_employee.record_version, 'record retention closure', v_staff, 'staff');
  if v_employee.lifecycle_status <> 'archived' then
    raise exception 'assertion failed: expected archived (terminated -> archived is a real, valid closure path), got %', v_employee.lifecycle_status;
  end if;
end;
$$;

\echo '>> reject path: submitted -> draft with revision_reason, then resubmittable; archive from draft'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_approver uuid := '00000000-0000-0000-0000-000000027103';
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HR1');
  v_employee app.employees;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'Siti Rahayu', 'contract', null, null, null, null, null, null, '2026-02-01', v_company, null, null, null, null, null, null, 'hr_created', 'idem-reject-1', v_staff, 'staff');
  perform app.add_employee_emergency_contact(v_employee.master_record_id, 'Pak Rahayu', 'Father', '+62-811-2', null, true, v_staff, 'staff');
  v_employee := app.submit_employee_for_approval(v_employee.master_record_id, v_employee.record_version, v_staff, 'staff');

  begin
    perform app.decide_employee_approval(v_employee.master_record_id, v_employee.record_version, 'reject', null, v_approver, 'approver');
    raise exception 'assertion failed: expected reason_required for a reject with no reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_employee := app.decide_employee_approval(v_employee.master_record_id, v_employee.record_version, 'reject', 'incomplete documentation', v_approver, 'approver');
  if v_employee.lifecycle_status <> 'draft' or v_employee.revision_reason <> 'incomplete documentation' then
    raise exception 'assertion failed: expected draft with revision_reason set, got %/%', v_employee.lifecycle_status, v_employee.revision_reason;
  end if;

  v_employee := app.submit_employee_for_approval(v_employee.master_record_id, v_employee.record_version, v_staff, 'staff');
  if v_employee.lifecycle_status <> 'submitted' then
    raise exception 'assertion failed: expected a rejected-then-fixed draft to be resubmittable, got %', v_employee.lifecycle_status;
  end if;

  v_employee := app.decide_employee_approval(v_employee.master_record_id, v_employee.record_version, 'reject', 'second pass', v_approver, 'approver');
  v_employee := app.archive_employee_profile(v_employee.master_record_id, v_employee.record_version, null, v_staff, 'staff');
  if v_employee.lifecycle_status <> 'archived' then
    raise exception 'assertion failed: expected a never-activated draft to be archivable, got %', v_employee.lifecycle_status;
  end if;
end;
$$;

\echo '>> employee number: explicit override honored and tenant-unique; duplicate explicit number rejected with the friendly employee_number_conflict error (this checkpoint''s own review-round fix -- previously a raw, unclassified unique_violation with no domain prefix)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_employee1 app.employees;
begin
  v_employee1 := app.create_employee_draft(v_tenant1, 'Explicit Number Co', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, 'EMP-CUSTOM-001', 'hr_created', 'idem-empnum-1', v_staff, 'staff');
  if (select code from app.master_records where id = v_employee1.master_record_id) <> 'EMP-CUSTOM-001' then
    raise exception 'assertion failed: expected the explicit employee_number to be honored';
  end if;

  begin
    perform app.create_employee_draft(v_tenant1, 'Duplicate Number Co', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, 'EMP-CUSTOM-001', 'hr_created', 'idem-empnum-2', v_staff, 'staff');
    raise exception 'assertion failed: expected a duplicate explicit employee_number to be rejected';
  exception
    when unique_violation then
      if sqlerrm not like 'employee_number_conflict%' then
        raise exception 'assertion failed: expected the friendly employee_number_conflict message, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> cyclic reporting line rejected; a legal manager chain is accepted; transfer preserves full before/after history'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HR1');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'BR-HR1');
  v_department uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'DEPT-HR1');
  v_a app.employees;
  v_b app.employees;
  v_event_count integer;
begin
  v_a := app.create_employee_draft(v_tenant1, 'Chain Employee A', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-cycle-a', v_staff, 'staff');
  v_b := app.create_employee_draft(v_tenant1, 'Chain Employee B', 'full_time', null, null, null, null, null, null, null, null, null, null, null, v_a.master_record_id, null, null, 'hr_created', 'idem-cycle-b', v_staff, 'staff');

  -- B already reports to A. Setting A's manager to B would create a 2-cycle.
  begin
    perform app.update_employee_draft(v_a.master_record_id, v_a.record_version, v_a.full_name, v_a.employment_type, null, null, null, null, null, null, null, null, null, null, null, null, v_b.master_record_id, v_staff, 'staff');
    raise exception 'assertion failed: expected cyclic_reporting_line for A -> B -> A';
  exception
    when others then
      if sqlerrm not like 'cyclic_reporting_line%' then raise; end if;
  end;

  begin
    perform app.update_employee_draft(v_a.master_record_id, v_a.record_version, v_a.full_name, v_a.employment_type, null, null, null, null, null, null, null, null, null, null, null, null, v_a.master_record_id, v_staff, 'staff');
    raise exception 'assertion failed: expected cyclic_reporting_line (self-manager) to be rejected';
  exception
    when others then
      if sqlerrm not like 'cyclic_reporting_line%' then raise; end if;
  end;

  -- Transfer: real org-unit/position/manager change, before/after preserved in history.
  v_a := app.transfer_employee(v_a.master_record_id, v_a.record_version, v_company, v_branch, v_department, 'Senior Analyst', null, 'org restructuring', v_staff, 'staff');
  if v_a.department_org_unit_id <> v_department or v_a.position_title <> 'Senior Analyst' then
    raise exception 'assertion failed: expected the transfer to apply department/position, got %/%', v_a.department_org_unit_id, v_a.position_title;
  end if;

  select count(*) into v_event_count from app.employee_lifecycle_events where master_record_id = v_a.master_record_id and metadata ->> 'event' = 'transfer';
  if v_event_count <> 1 then
    raise exception 'assertion failed: expected exactly one transfer event recorded, found %', v_event_count;
  end if;
  if not exists (
    select 1 from app.employee_lifecycle_events
    where master_record_id = v_a.master_record_id and metadata ->> 'event' = 'transfer'
      and (metadata -> 'after' ->> 'department_org_unit_id')::uuid = v_department
      and metadata -> 'before' ->> 'department_org_unit_id' is null
  ) then
    raise exception 'assertion failed: expected the transfer event to carry real before(null)/after(department) values';
  end if;

  -- Org-unit shape validation: wrong unit_type and cross-branch ancestor mismatch.
  begin
    perform app.transfer_employee(v_a.master_record_id, v_a.record_version, v_department, null, null, null, null, null, v_staff, 'staff');
    raise exception 'assertion failed: expected invalid_org_unit_type (a department passed where company is expected)';
  exception
    when others then
      if sqlerrm not like 'invalid_org_unit_type%' then raise; end if;
  end;
end;
$$;

\echo '>> own-profile: app.get_my_employee_profile resolves by identity match and returns unmasked own data; app.link_employee_user links an unlinked profile; app.request_employee_change is identity-match-gated and app.decide_employee_change_request applies an approved correction'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_mgr_auth uuid := '00000000-0000-0000-0000-000000027108';
  v_report_auth uuid := '00000000-0000-0000-0000-000000027109';
  v_mgr_user_id uuid := (select id from app.users where email = 'mgrperson@hrmemp1.test');
  v_report_user_id uuid := (select id from app.users where email = 'reportperson@hrmemp1.test');
  v_manager_emp app.employees;
  v_report_emp app.employees;
  v_own_profile record;
  v_request app.employee_change_requests;
  v_final app.employees;
begin
  v_manager_emp := app.create_employee_draft(v_tenant1, 'Manager Person', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-mgrperson', v_staff, 'staff');
  v_report_emp := app.create_employee_draft(v_tenant1, 'Report Person', 'full_time', null, 'old@personal.test', null, null, null, null, null, null, null, null, null, v_manager_emp.master_record_id, null, null, 'hr_created', 'idem-reportperson', v_staff, 'staff');

  -- Before linking: get_my_employee_profile returns zero rows (never raises).
  if exists (select 1 from app.get_my_employee_profile(v_tenant1, v_report_auth)) then
    raise exception 'assertion failed: expected zero rows before linking';
  end if;

  v_manager_emp := app.link_employee_user(v_manager_emp.master_record_id, v_manager_emp.record_version, v_mgr_user_id, v_staff, 'staff');
  v_report_emp := app.link_employee_user(v_report_emp.master_record_id, v_report_emp.record_version, v_report_user_id, v_staff, 'staff');

  -- Symmetric uniqueness: the SAME user cannot be linked to a second employee.
  begin
    perform app.link_employee_user(v_manager_emp.master_record_id, v_manager_emp.record_version, v_report_user_id, v_staff, 'staff');
    raise exception 'assertion failed: expected user_already_linked for a user already linked to a different employee';
  exception
    when others then
      if sqlerrm not like 'user_already_linked%' then raise; end if;
  end;

  select * into v_own_profile from app.get_my_employee_profile(v_tenant1, v_report_auth);
  if v_own_profile.full_name <> 'Report Person' or v_own_profile.personal_email <> 'old@personal.test' then
    raise exception 'assertion failed: expected the report''s own unmasked profile, got %', v_own_profile;
  end if;

  -- Identity-match gate: the manager may not request a change against the report's profile.
  begin
    perform app.request_employee_change(v_report_emp.master_record_id, 'personal_email', 'nope@x.test', null, v_mgr_auth);
    raise exception 'assertion failed: expected not_own_profile for a manager requesting a change on someone else''s profile';
  exception
    when others then
      if sqlerrm not like 'not_own_profile%' then raise; end if;
  end;

  v_request := app.request_employee_change(v_report_emp.master_record_id, 'personal_email', 'new@personal.test', 'moved providers', v_report_auth);
  if v_request.current_value_snapshot <> 'old@personal.test' or v_request.status <> 'pending' then
    raise exception 'assertion failed: expected a pending request snapshotting the old value, got %', v_request;
  end if;

  -- A caller-supplied field outside the fixed allow-list is rejected (never a dynamic, unbounded column).
  begin
    perform app.request_employee_change(v_report_emp.master_record_id, 'national_id_number', '1234', null, v_report_auth);
    raise exception 'assertion failed: expected invalid_field_key for a non-allow-listed field';
  exception
    when others then
      if sqlerrm not like 'invalid_field_key%' then raise; end if;
  end;

  perform app.decide_employee_change_request(v_request.id, v_request.record_version, 'approved', 'verified', v_staff, 'staff');

  select * into v_final from app.employees where master_record_id = v_report_emp.master_record_id;
  if v_final.personal_email <> 'new@personal.test' then
    raise exception 'assertion failed: expected the approved correction to be applied, got %', v_final.personal_email;
  end if;
end;
$$;

\echo '>> manager-scoped team view: app.list_my_team_employees is self-resolved (the caller''s OWN employee row determines their team) and carries zero PII columns'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_mgr_auth uuid := '00000000-0000-0000-0000-000000027108';
  v_staff_auth uuid := '00000000-0000-0000-0000-000000027102';
  v_team_row record;
  v_team_count integer;
begin
  select count(*) into v_team_count from app.list_my_team_employees(v_tenant1, v_mgr_auth);
  if v_team_count <> 1 then
    raise exception 'assertion failed: expected exactly one direct report, found %', v_team_count;
  end if;

  select * into v_team_row from app.list_my_team_employees(v_tenant1, v_mgr_auth) limit 1;
  if v_team_row.full_name <> 'Report Person' then
    raise exception 'assertion failed: expected Report Person on the manager''s team view, got %', v_team_row.full_name;
  end if;

  -- HR staff (not this employee's manager, no linked employee row at all) sees an empty team.
  if exists (select 1 from app.list_my_team_employees(v_tenant1, v_staff_auth)) then
    raise exception 'assertion failed: expected zero team rows for an actor with no linked employee profile';
  end if;
end;
$$;

\echo '>> field masking: app.get_employee_profile masks sensitive personal fields without HRS:View personal data; unmasked with it; always unmasked for the employee''s own linked profile (a View-only-HOLDING actor with zero HRS:View personal data still sees their OWN masked fields once linked)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_viewer uuid := '00000000-0000-0000-0000-000000027105';
  v_pdv uuid := '00000000-0000-0000-0000-000000027107';
  v_self_auth uuid := '00000000-0000-0000-0000-000000027110';
  v_employee app.employees;
  v_masked record;
  v_unmasked record;
  v_self record;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'Mask Test Person', 'full_time', null, 'maskme@personal.test', null, '3201-MASK', null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-mask-1', v_staff, 'staff');

  select * into v_masked from app.get_employee_profile(v_employee.master_record_id, v_viewer);
  if not v_masked.personal_data_masked or v_masked.personal_email is not null or v_masked.national_id_number is not null then
    raise exception 'assertion failed: expected a View-only caller to see masked personal fields, got %', v_masked;
  end if;

  select * into v_unmasked from app.get_employee_profile(v_employee.master_record_id, v_pdv);
  if v_unmasked.personal_data_masked or v_unmasked.personal_email <> 'maskme@personal.test' or v_unmasked.national_id_number <> '3201-MASK' then
    raise exception 'assertion failed: expected a View-personal-data caller to see unmasked personal fields, got %', v_unmasked;
  end if;

  -- Own-profile self-read via app.get_employee_profile (the shared HR/self-service
  -- detail RPC) is unmasked even for an actor holding NO HRS permission at all,
  -- once linked -- v_is_self, never HRS:View personal data, is what unmasks it.
  insert into auth.users (id, email) values (v_self_auth, 'maskself@hrmemp1.test');
  perform app.invite_user(v_tenant1, v_self_auth, 'maskself@hrmemp1.test', 'Mask Self Person', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'maskself@hrmemp1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_self_auth, 'org_user', v_tenant1, null, 'tester');
  perform app.link_employee_user(v_employee.master_record_id, v_employee.record_version, (select id from app.users where email = 'maskself@hrmemp1.test'), v_staff, 'staff');

  select * into v_self from app.get_employee_profile(v_employee.master_record_id, v_self_auth);
  if v_self.personal_data_masked or v_self.personal_email <> 'maskme@personal.test' then
    raise exception 'assertion failed: expected the employee''s own linked self-read to be unmasked with zero HRS permission, got %', v_self;
  end if;
end;
$$;

\echo '>> emergency contact masking mirrors app.vendor_contacts (PRC-251): name/relationship visible unmasked, phone/email masked without HRS:View personal data'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_viewer uuid := '00000000-0000-0000-0000-000000027105';
  v_pdv uuid := '00000000-0000-0000-0000-000000027107';
  v_employee app.employees;
  v_masked record;
  v_unmasked record;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'Contact Mask Person', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-contactmask-1', v_staff, 'staff');
  perform app.add_employee_emergency_contact(v_employee.master_record_id, 'Emergency Contact', 'Sibling', '+62-811-9', 'contact@personal.test', true, v_staff, 'staff');

  select * into v_masked from app.list_employee_emergency_contacts(v_employee.master_record_id, v_viewer) limit 1;
  if v_masked.name <> 'Emergency Contact' or v_masked.phone is not null or v_masked.email is not null then
    raise exception 'assertion failed: expected name visible, phone/email masked for a View-only caller, got %', v_masked;
  end if;

  select * into v_unmasked from app.list_employee_emergency_contacts(v_employee.master_record_id, v_pdv) limit 1;
  if v_unmasked.phone <> '+62-811-9' or v_unmasked.email <> 'contact@personal.test' then
    raise exception 'assertion failed: expected phone/email visible for a View-personal-data caller, got %', v_unmasked;
  end if;
end;
$$;

\echo '>> duplicate detection (never auto-merged): trigram name search and exact national_id_number/email match; flag + pending blocks submission; dismiss/link unblocks'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_existing app.employees;
  v_candidate app.employees;
  v_search_count integer;
  v_flagged app.employee_duplicate_candidates;
begin
  v_existing := app.create_employee_draft(v_tenant1, 'Ahmad Fauzi Wijaya', 'full_time', null, null, null, '3201-DUPE-1', null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-dupe-existing', v_staff, 'staff');

  select count(*) into v_search_count from app.search_employee_duplicate_candidates(v_tenant1, 'Ahmad Fauzi Wijaya', null, null, null, v_staff, 10) where match_basis = 'full_name trigram similarity';
  if v_search_count = 0 then
    raise exception 'assertion failed: expected a trigram name match to surface the existing employee';
  end if;

  select count(*) into v_search_count from app.search_employee_duplicate_candidates(v_tenant1, null, '3201-DUPE-1', null, null, v_staff, 10) where match_basis = 'national_id_number exact match';
  if v_search_count <> 1 then
    raise exception 'assertion failed: expected exactly one exact national_id_number match, found %', v_search_count;
  end if;

  v_candidate := app.create_employee_draft(v_tenant1, 'Ahmad Fauzi Wijaya', 'contract', null, null, null, null, null, null, '2026-03-01', (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HR1'), null, null, null, null, null, null, 'hr_created', 'idem-dupe-candidate', v_staff, 'staff');
  perform app.add_employee_emergency_contact(v_candidate.master_record_id, 'Contact', null, '+62-811-3', null, true, v_staff, 'staff');

  v_flagged := app.flag_employee_duplicate_candidate(v_candidate.master_record_id, v_existing.master_record_id, 'manual HR review match', 1.0, v_staff, 'staff');

  begin
    perform app.submit_employee_for_approval(v_candidate.master_record_id, v_candidate.record_version, v_staff, 'staff');
    raise exception 'assertion failed: expected unresolved_duplicate_candidates to block submission';
  exception
    when others then
      if sqlerrm not like 'unresolved_duplicate_candidates%' then raise; end if;
  end;

  perform app.decide_employee_duplicate_candidate(v_flagged.id, v_flagged.record_version, 'dismissed', 'different person, coincidental name match', v_staff, 'staff');

  -- Submission now succeeds -- and 'linked' never invokes any merge; both master_records rows are untouched.
  perform app.submit_employee_for_approval(v_candidate.master_record_id, v_candidate.record_version, v_staff, 'staff');
  if not exists (select 1 from app.master_records where id = v_existing.master_record_id and canonical_status = 'active') then
    raise exception 'assertion failed: expected the existing employee''s master_records row to remain untouched (canonical_status=active)';
  end if;
end;
$$;

\echo '>> concurrency: record_version stale-version rejection (pre-check), and the terminal UPDATE''s own repeated version predicate as a second guard'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_employee app.employees;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'Stale Version Person', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-stale-1', v_staff, 'staff');

  begin
    perform app.update_employee_draft(v_employee.master_record_id, v_employee.record_version + 99, v_employee.full_name, v_employee.employment_type, null, null, null, null, null, null, null, null, null, null, null, null, null, v_staff, 'staff');
    raise exception 'assertion failed: expected stale_version for a deliberately wrong expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
end;
$$;

\echo '>> idempotency-key replay AND idempotency-key-reused-for-a-different-target on create_employee_draft'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_first app.employees;
  v_replay app.employees;
begin
  v_first := app.create_employee_draft(v_tenant1, 'Idem Person', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-createreplay-1', v_staff, 'staff');
  v_replay := app.create_employee_draft(v_tenant1, 'Idem Person', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-createreplay-1', v_staff, 'staff');
  if v_replay.master_record_id <> v_first.master_record_id then
    raise exception 'assertion failed: expected a repeated idempotency_key to return the SAME row, not create a duplicate';
  end if;

  begin
    perform app.create_employee_draft(v_tenant1, 'Different Person', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-createreplay-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for the same key against a different full_name';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
end;
$$;

\echo '>> cross-tenant isolation: hrmemp2''s staff, holding zero membership in hrmemp1, is rejected on every RPC against hrmemp1''s real employee, and raw RLS denies a direct select'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_t2_staff uuid := '00000000-0000-0000-0000-000000027202';
  v_target_master_record_id uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and idempotency_key = 'idem-lifecycle-1');
begin
  begin
    perform app.get_employee_profile(v_target_master_record_id, v_t2_staff);
    raise exception 'assertion failed: expected employee_not_found for a hrmemp2 actor reading a hrmemp1 employee profile';
  exception
    when others then
      if sqlerrm not like 'employee_not_found%' then raise; end if;
  end;

  begin
    perform app.suspend_employee(v_target_master_record_id, 1, 'attack', v_t2_staff, 'attacker');
    raise exception 'assertion failed: expected employee_not_found (never insufficient_authority, which would disclose the real tenant_id) for a cross-tenant suspend attempt';
  exception
    when others then
      if sqlerrm not like 'employee_not_found%' then raise; end if;
  end;

  begin
    perform app.create_employee_draft(v_tenant1, 'Cross Tenant Attempt', 'full_time', null, null, null, null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-lifecycle-1', v_t2_staff, 'attacker');
    raise exception 'assertion failed: expected insufficient_authority for a hrmemp2 actor creating a draft under hrmemp1 (a real, already-consumed hrmemp1 idempotency key must never short-circuit into hrmemp1''s real data for an unauthorized caller)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027202", "role": "authenticated"}', true);

  if exists (select 1 from app.employees where master_record_id = v_target_master_record_id) then
    raise exception 'assertion failed: raw RLS leak -- hrmemp2 staff directly selected a hrmemp1 employee row';
  end if;
  if exists (select 1 from app.employee_emergency_contacts where master_record_id = v_target_master_record_id) then
    raise exception 'assertion failed: raw RLS leak -- hrmemp2 staff directly selected a hrmemp1 emergency contact row';
  end if;

  reset role;
end;
$$;

\echo '>> authority-before-disclosure: a real hrmemp1 member who both lacks the required authority AND supplies a stale expected_version gets insufficient_authority, never stale_version (which would disclose the real record_version)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_viewer uuid := '00000000-0000-0000-0000-000000027105';
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_employee app.employees;
  v_wrong_version integer;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'Auth Order Person', 'full_time', null, null, null, null, null, null, '2026-04-01', (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HR1'), null, null, null, null, null, null, 'hr_created', 'idem-authorder-1', v_staff, 'staff');
  perform app.add_employee_emergency_contact(v_employee.master_record_id, 'Contact', null, '+62-811-4', null, true, v_staff, 'staff');
  v_employee := app.submit_employee_for_approval(v_employee.master_record_id, v_employee.record_version, v_staff, 'staff');
  v_wrong_version := v_employee.record_version + 99;

  begin
    perform app.suspend_employee(v_employee.master_record_id, v_wrong_version, 'quality issue', v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority (never stale_version) for a View-only actor supplying a stale version to suspend';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end;
$$;

\echo '>> RLS default-deny for a customer_user-layer principal: tenant membership alone is not enough -- a customer_user-layer actor in the SAME tenant reads zero employee rows at the raw-RLS level'
do $$
declare
  v_target_master_record_id uuid := (select e.master_record_id from app.employees e join app.tenants t on t.id = e.tenant_id where t.slug = 'hrmemp1' and e.idempotency_key = 'idem-lifecycle-1');
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027106", "role": "authenticated"}', true);

  if exists (select 1 from app.employees where master_record_id = v_target_master_record_id) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.employees directly, even inside its own tenant';
  end if;
  if exists (select 1 from app.employee_change_requests where master_record_id = v_target_master_record_id) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.employee_change_requests directly';
  end if;

  reset role;
end;
$$;

\echo '>> staged import (PLT-131/132 fifth-plus real domain-write adapter): a tenant publishes import_export:employee_import columns, stages rows (one valid, one invalid via org-unit-code, one formula-injection attempt), commit creates real draft employees, and a repeat commit is idempotent (no duplicate rows)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_admin uuid := '00000000-0000-0000-0000-000000027101';
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_draft app.config_versions;
  v_doc_draft app.config_versions;
  v_source_file app.files;
  v_job app.jobs;
  v_row1 app.import_staging_rows;
  v_row2 app.import_staging_rows;
  v_row3 app.import_staging_rows;
  v_committed app.jobs;
  v_created_count integer;
  v_recommitted app.jobs;
begin
  -- The 'employee_document' document type is registered directly by the migration
  -- itself (decision 4) -- but, mirroring every other document type in this
  -- repository (scripts/db-tests/import-export.sql's own identical setup), each
  -- tenant must still separately publish its own document:employee_document
  -- column definition before app.initiate_file_upload will accept anything.
  v_doc_draft := app.create_config_draft('document:employee_document', v_tenant1, 'tenant', null, v_admin, 'tenant admin');
  perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('text/csv')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('confidential'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_admin, 'tenant admin');
  perform app.publish_document_type_definition(v_doc_draft.id, v_admin, now(), 'tenant admin');

  -- Publish the tenant's own column definition (per-tenant onboarding step, mirrors
  -- vendor_rate_import's own identical requirement).
  v_draft := app.create_config_draft('import_export:employee_import', v_tenant1, 'tenant', null, v_admin, 'tenant admin');
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
      jsonb_build_object('key', 'employee_number', 'label', 'Employee Number', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'full_name', 'label', 'Full Name', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'employment_type', 'label', 'Employment Type', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'work_email', 'label', 'Work Email', 'required', false, 'data_type', 'email'),
      jsonb_build_object('key', 'personal_email', 'label', 'Personal Email', 'required', false, 'data_type', 'email'),
      jsonb_build_object('key', 'personal_phone', 'label', 'Personal Phone', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'company_org_unit_code', 'label', 'Company Code', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'branch_org_unit_code', 'label', 'Branch Code', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'department_org_unit_code', 'label', 'Department Code', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'position_title', 'label', 'Position Title', 'required', false, 'data_type', 'text')
    ))
  ), v_admin, 'tenant admin');
  perform app.publish_import_export_schema(v_draft.id, v_admin, now(), 'tenant admin');

  -- A clean, scanned source file (PLT-128 reused directly).
  v_source_file := app.initiate_file_upload(v_tenant1, 'employee_document', 'import_job', gen_random_uuid(), 'employees.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-empimport-source-1', v_staff, 'staff');
  perform app.record_file_scan_result(v_source_file.id, 'clean', null, v_staff, 'staff');

  v_job := app.create_import_export_job(v_tenant1, 'import', 'employee_import', v_source_file.id, '{}'::jsonb, 'idem-empimport-job-1', v_staff, 'staff');

  -- app.stage_import_rows returns an integer (the count staged this call), never the
  -- staged rows themselves -- each staged row is read back from app.import_staging_
  -- rows by (job_id, row_number), row_number continuing sequentially across separate
  -- calls (the framework's own documented, already-tested behavior).
  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', 'EMP-IMPORT-001', 'full_name', 'Imported Employee One', 'employment_type', 'full_time',
    'work_email', 'one@hrmemp1.test', 'company_org_unit_code', 'CO-HR1', 'department_org_unit_code', 'DEPT-HR1'
  )), v_staff, 'staff');
  select * into v_row1 from app.import_staging_rows where job_id = v_job.job_id and row_number = 1;

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'full_name', 'Bad Department Employee', 'employment_type', 'full_time', 'department_org_unit_code', 'NOT-A-REAL-CODE'
  )), v_staff, 'staff');
  select * into v_row2 from app.import_staging_rows where job_id = v_job.job_id and row_number = 2;

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'full_name', '=cmd|/c calc', 'employment_type', 'full_time'
  )), v_staff, 'staff');
  select * into v_row3 from app.import_staging_rows where job_id = v_job.job_id and row_number = 3;

  perform app.validate_employee_import_row(v_row1.id, v_staff, 'staff');
  perform app.validate_employee_import_row(v_row2.id, v_staff, 'staff');
  perform app.validate_employee_import_row(v_row3.id, v_staff, 'staff');

  if (select validation_status from app.import_staging_rows where id = v_row1.id) <> 'valid' then
    raise exception 'assertion failed: expected row 1 (real department code) to validate as valid';
  end if;
  if (select validation_status from app.import_staging_rows where id = v_row2.id) <> 'invalid' or (select error from app.import_staging_rows where id = v_row2.id) !~ 'department_org_unit_code' then
    raise exception 'assertion failed: expected row 2 to be invalid with a department_org_unit_code error, got %', (select error from app.import_staging_rows where id = v_row2.id);
  end if;
  if (select validation_status from app.import_staging_rows where id = v_row3.id) <> 'invalid' or (select error from app.import_staging_rows where id = v_row3.id) !~ 'formula/spreadsheet-injection' then
    raise exception 'assertion failed: expected row 3 (formula-injection attempt) to be rejected as invalid, got %', (select error from app.import_staging_rows where id = v_row3.id);
  end if;

  begin
    perform app.commit_employee_import_job(v_job.job_id, false, v_staff, 'staff');
    raise exception 'assertion failed: expected import_export_job_has_invalid_rows without p_allow_partial';
  exception
    when others then
      if sqlerrm not like 'import_export_job_has_invalid_rows%' then raise; end if;
  end;

  v_committed := app.commit_employee_import_job(v_job.job_id, true, v_staff, 'staff');
  if v_committed.status <> 'completed' then
    raise exception 'assertion failed: expected the job to complete on a partial commit, got %', v_committed.status;
  end if;

  select count(*) into v_created_count from app.employees where source_import_staging_row_id = v_row1.id;
  if v_created_count <> 1 then
    raise exception 'assertion failed: expected exactly one real draft employee created from the valid staged row, found %', v_created_count;
  end if;
  if not exists (select 1 from app.employees where source_import_staging_row_id = v_row1.id and lifecycle_status = 'draft' and department_org_unit_id = (select id from app.org_units where tenant_id = v_tenant1 and code = 'DEPT-HR1')) then
    raise exception 'assertion failed: expected the imported employee to resolve department_org_unit_code to the real org unit id and remain in draft (never auto-activated)';
  end if;

  -- Idempotent replay of commit: job is no longer in_progress, so a second commit call
  -- itself is refused -- but confirm no second employee row was ever created for the
  -- same staging row regardless.
  begin
    v_recommitted := app.commit_employee_import_job(v_job.job_id, true, v_staff, 'staff');
    raise exception 'assertion failed: expected import_export_job_not_committable for a job already completed';
  exception
    when others then
      if sqlerrm not like 'import_export_job_not_committable%' then raise; end if;
  end;

  select count(*) into v_created_count from app.employees where source_import_staging_row_id = v_row1.id;
  if v_created_count <> 1 then
    raise exception 'assertion failed: expected still exactly one employee row for staging row 1 after the refused re-commit attempt, found %', v_created_count;
  end if;
end;
$$;

\echo '>> HDN-385 (Data Migration Rehearsal) fix regression: a genuine explicit employee_number collision (two rows in the same batch) now aborts the whole commit with a loud, named error instead of silently swallowing the duplicate and reporting status=completed as if nothing were wrong'
do $$
declare
  v_tenant1 uuid;
  v_staff uuid;
  v_job app.jobs;
  v_source_file app.files;
  v_row1 app.import_staging_rows;
  v_row2 app.import_staging_rows;
  v_created_before integer;
  v_created_after integer;
  v_raised boolean := false;
begin
  select id into v_tenant1 from app.tenants where slug = 'hrmemp1';
  select auth_user_id into v_staff from app.users where email = 'staff@hrmemp1.test';

  v_source_file := app.initiate_file_upload(v_tenant1, 'employee_document', 'import_job', gen_random_uuid(), 'employees-dup.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-empimport-dup-source-1', v_staff, 'staff');
  perform app.record_file_scan_result(v_source_file.id, 'clean', null, v_staff, 'staff');

  v_job := app.create_import_export_job(v_tenant1, 'import', 'employee_import', v_source_file.id, '{}'::jsonb, 'idem-empimport-dup-job-1', v_staff, 'staff');

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', 'EMP-DUP-001', 'full_name', 'Duplicate Row One', 'employment_type', 'full_time'
  )), v_staff, 'staff');
  select * into v_row1 from app.import_staging_rows where job_id = v_job.job_id and row_number = 1;

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', 'EMP-DUP-001', 'full_name', 'Duplicate Row Two', 'employment_type', 'full_time'
  )), v_staff, 'staff');
  select * into v_row2 from app.import_staging_rows where job_id = v_job.job_id and row_number = 2;

  perform app.validate_employee_import_row(v_row1.id, v_staff, 'staff');
  perform app.validate_employee_import_row(v_row2.id, v_staff, 'staff');

  select count(*) into v_created_before from app.employees where tenant_id = v_tenant1 and full_name in ('Duplicate Row One', 'Duplicate Row Two');
  if v_created_before <> 0 then
    raise exception 'assertion failed: expected zero pre-existing rows for this test''s own fixture names, found %', v_created_before;
  end if;

  begin
    perform app.commit_employee_import_job(v_job.job_id, true, v_staff, 'staff');
    raise exception 'assertion failed: expected employee_import_duplicate_employee_number to abort the commit, but it reported success';
  exception
    when others then
      if sqlerrm like 'employee_import_duplicate_employee_number%' then
        v_raised := true;
      else
        raise;
      end if;
  end;
  if not v_raised then
    raise exception 'assertion failed: expected the duplicate-employee_number exception branch to have been taken';
  end if;

  -- The whole commit is one transaction (job-scoped advisory lock, HDN-385's
  -- own fix comment) -- the entire attempt must roll back cleanly, not leave
  -- the first row silently committed while the second was rejected.
  select count(*) into v_created_after from app.employees where tenant_id = v_tenant1 and full_name in ('Duplicate Row One', 'Duplicate Row Two');
  if v_created_after <> 0 then
    raise exception 'assertion failed: expected zero employees committed after an aborted duplicate-collision commit (all-or-nothing), found %', v_created_after;
  end if;

  -- The job itself must not be silently marked completed by the failed attempt.
  if (select status from app.jobs where job_id = v_job.job_id) = 'completed' then
    raise exception 'assertion failed: expected the job to remain in_progress after an aborted commit, not completed';
  end if;
end;
$$;

\echo '>> ISS-2026-269 (Step 16 historical-issue-backlog remediation) fix regression: a fresh, auto-numbered re-import of an un-keyed row sharing an existing employee''s own work_email/full_name is flagged into app.employee_duplicate_candidates for human review -- the exact HDN-385 live reproduction (a genuine duplicate person record, silently created, zero flag) -- the import itself still succeeds (never a hard block)'
do $$
declare
  v_tenant1 uuid;
  v_staff uuid;
  v_job1 app.jobs;
  v_job2 app.jobs;
  v_source_file1 app.files;
  v_source_file2 app.files;
  v_row1 app.import_staging_rows;
  v_row2 app.import_staging_rows;
  v_first_employee_count integer;
  v_second_employee_count integer;
  v_first_id uuid;
  v_second_id uuid;
  v_candidate app.employee_duplicate_candidates;
begin
  select id into v_tenant1 from app.tenants where slug = 'hrmemp1';
  select auth_user_id into v_staff from app.users where email = 'staff@hrmemp1.test';

  -- First import: a single, un-keyed (no employee_number) row.
  v_source_file1 := app.initiate_file_upload(v_tenant1, 'employee_document', 'import_job', gen_random_uuid(), 'employees-unkeyed-1.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-empimport-unkeyed-source-1', v_staff, 'staff');
  perform app.record_file_scan_result(v_source_file1.id, 'clean', null, v_staff, 'staff');
  v_job1 := app.create_import_export_job(v_tenant1, 'import', 'employee_import', v_source_file1.id, '{}'::jsonb, 'idem-empimport-unkeyed-job-1', v_staff, 'staff');
  perform app.stage_import_rows(v_job1.job_id, jsonb_build_array(jsonb_build_object(
    'full_name', 'Repeat Import Person', 'work_email', 'repeat.import@hrmemp1.test', 'employment_type', 'full_time'
  )), v_staff, 'staff');
  select * into v_row1 from app.import_staging_rows where job_id = v_job1.job_id and row_number = 1;
  perform app.validate_employee_import_row(v_row1.id, v_staff, 'staff');
  perform app.commit_employee_import_job(v_job1.job_id, false, v_staff, 'staff');

  select count(*) into v_first_employee_count from app.employees
    where tenant_id = v_tenant1 and full_name = 'Repeat Import Person';
  select master_record_id into v_first_id from app.employees
    where tenant_id = v_tenant1 and full_name = 'Repeat Import Person' limit 1;
  if v_first_employee_count <> 1 then
    raise exception 'assertion failed: expected exactly one employee created by the first import, got %', v_first_employee_count;
  end if;

  -- Second import: the SAME source row, re-imported as a genuinely new, un-keyed staging
  -- row in a fresh job -- exactly HDN-385''s own "a fresh re-import of the same source
  -- file" reproduction. app.next_employee_number() mints a DIFFERENT number, so
  -- master_records'' own unique constraint never fires; this is the precise gap
  -- ISS-2026-269 exists to close.
  v_source_file2 := app.initiate_file_upload(v_tenant1, 'employee_document', 'import_job', gen_random_uuid(), 'employees-unkeyed-2.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-empimport-unkeyed-source-2', v_staff, 'staff');
  perform app.record_file_scan_result(v_source_file2.id, 'clean', null, v_staff, 'staff');
  v_job2 := app.create_import_export_job(v_tenant1, 'import', 'employee_import', v_source_file2.id, '{}'::jsonb, 'idem-empimport-unkeyed-job-2', v_staff, 'staff');
  perform app.stage_import_rows(v_job2.job_id, jsonb_build_array(jsonb_build_object(
    'full_name', 'Repeat Import Person', 'work_email', 'repeat.import@hrmemp1.test', 'employment_type', 'full_time'
  )), v_staff, 'staff');
  select * into v_row2 from app.import_staging_rows where job_id = v_job2.job_id and row_number = 1;
  perform app.validate_employee_import_row(v_row2.id, v_staff, 'staff');

  -- The import itself still succeeds -- never a hard block.
  perform app.commit_employee_import_job(v_job2.job_id, false, v_staff, 'staff');

  select count(*) into v_second_employee_count from app.employees where tenant_id = v_tenant1 and full_name = 'Repeat Import Person';
  if v_second_employee_count <> 2 then
    raise exception 'assertion failed: expected the second, genuinely-duplicate employee record to still be created (never a hard block on import), found % rows total', v_second_employee_count;
  end if;
  select master_record_id into v_second_id from app.employees where tenant_id = v_tenant1 and full_name = 'Repeat Import Person' and master_record_id <> v_first_id;

  -- ...but now flagged, where before this fix there was zero flag at all.
  select * into v_candidate from app.employee_duplicate_candidates
    where tenant_id = v_tenant1 and source_master_record_id = v_second_id and candidate_master_record_id = v_first_id;
  if not found then
    raise exception 'assertion failed: expected a pending app.employee_duplicate_candidates row linking the re-imported duplicate back to the original employee -- ISS-2026-269''s own "zero duplicate detection" gap has reappeared';
  end if;
  if v_candidate.decision <> 'pending' or v_candidate.similarity_basis <> 'work_email+full_name' then
    raise exception 'assertion failed: expected decision=pending/similarity_basis=work_email+full_name (both fields matched), got decision=%, similarity_basis=%', v_candidate.decision, v_candidate.similarity_basis;
  end if;

  -- A THIRD import, un-keyed, with a genuinely different person (different work_email
  -- AND full_name) must NOT be flagged -- proving this is a real match, not "every
  -- auto-numbered row gets flagged unconditionally."
  declare
    v_job3 app.jobs;
    v_source_file3 app.files;
    v_row3 app.import_staging_rows;
    v_third_id uuid;
  begin
    v_source_file3 := app.initiate_file_upload(v_tenant1, 'employee_document', 'import_job', gen_random_uuid(), 'employees-unkeyed-3.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-empimport-unkeyed-source-3', v_staff, 'staff');
    perform app.record_file_scan_result(v_source_file3.id, 'clean', null, v_staff, 'staff');
    v_job3 := app.create_import_export_job(v_tenant1, 'import', 'employee_import', v_source_file3.id, '{}'::jsonb, 'idem-empimport-unkeyed-job-3', v_staff, 'staff');
    perform app.stage_import_rows(v_job3.job_id, jsonb_build_array(jsonb_build_object(
      'full_name', 'Genuinely Distinct Person', 'work_email', 'distinct.person@hrmemp1.test', 'employment_type', 'full_time'
    )), v_staff, 'staff');
    select * into v_row3 from app.import_staging_rows where job_id = v_job3.job_id and row_number = 1;
    perform app.validate_employee_import_row(v_row3.id, v_staff, 'staff');
    perform app.commit_employee_import_job(v_job3.job_id, false, v_staff, 'staff');
    select master_record_id into v_third_id from app.employees where tenant_id = v_tenant1 and full_name = 'Genuinely Distinct Person';

    if exists (select 1 from app.employee_duplicate_candidates where tenant_id = v_tenant1 and source_master_record_id = v_third_id) then
      raise exception 'assertion failed: expected a genuinely distinct new employee (no shared work_email/full_name with anyone) to NOT be flagged as a duplicate candidate';
    end if;
  end;

  raise notice 'ISS-2026-269 duplicate-import-detection proof: a re-imported, auto-numbered duplicate person is flagged into app.employee_duplicate_candidates for human review (import still succeeds, never a hard block); a genuinely distinct new employee is not flagged';
end;
$$;

\echo '>> ISS-2026-279 (Step 16 historical-issue-backlog remediation) fix regression: an EXPLICITLY-supplied employee_number that normalizes (lower + trim) to the same value as an existing employee''s own number, without being byte-identical, is flagged into app.employee_duplicate_candidates for human review -- the exact HDN-385 Tier C live reproduction (EMP-CASE-001 / emp-case-001 / trailing-space variant all committed as 3 distinct employees, zero flag) -- the import itself still succeeds (never a hard block), and an unrelated employee_number is never flagged'
do $$
declare
  v_tenant1 uuid;
  v_staff uuid;
  v_job1 app.jobs;
  v_job2 app.jobs;
  v_job3 app.jobs;
  v_job4 app.jobs;
  v_source_file1 app.files;
  v_source_file2 app.files;
  v_source_file3 app.files;
  v_source_file4 app.files;
  v_row1 app.import_staging_rows;
  v_row2 app.import_staging_rows;
  v_row3 app.import_staging_rows;
  v_row4 app.import_staging_rows;
  v_first_id uuid;
  v_second_id uuid;
  v_third_id uuid;
  v_fourth_id uuid;
  v_candidate app.employee_duplicate_candidates;
  v_employee_count integer;
begin
  select id into v_tenant1 from app.tenants where slug = 'hrmemp1';
  select auth_user_id into v_staff from app.users where email = 'staff@hrmemp1.test';

  -- First import: the canonical explicit number.
  v_source_file1 := app.initiate_file_upload(v_tenant1, 'employee_document', 'import_job', gen_random_uuid(), 'employees-normcase-1.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-empimport-normcase-source-1', v_staff, 'staff');
  perform app.record_file_scan_result(v_source_file1.id, 'clean', null, v_staff, 'staff');
  v_job1 := app.create_import_export_job(v_tenant1, 'import', 'employee_import', v_source_file1.id, '{}'::jsonb, 'idem-empimport-normcase-job-1', v_staff, 'staff');
  perform app.stage_import_rows(v_job1.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', 'EMP-CASE-001', 'full_name', 'Case Variant Person One', 'employment_type', 'full_time'
  )), v_staff, 'staff');
  select * into v_row1 from app.import_staging_rows where job_id = v_job1.job_id and row_number = 1;
  perform app.validate_employee_import_row(v_row1.id, v_staff, 'staff');
  perform app.commit_employee_import_job(v_job1.job_id, false, v_staff, 'staff');
  select master_record_id into v_first_id from app.employees where tenant_id = v_tenant1 and full_name = 'Case Variant Person One';

  -- Second import, a SEPARATE job (the unique index is per-row, but confirming it never
  -- fires cross-job either): lowercase variant, a genuinely different person (no shared
  -- work_email/full_name), isolating this proof to employee_number normalization alone.
  v_source_file2 := app.initiate_file_upload(v_tenant1, 'employee_document', 'import_job', gen_random_uuid(), 'employees-normcase-2.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-empimport-normcase-source-2', v_staff, 'staff');
  perform app.record_file_scan_result(v_source_file2.id, 'clean', null, v_staff, 'staff');
  v_job2 := app.create_import_export_job(v_tenant1, 'import', 'employee_import', v_source_file2.id, '{}'::jsonb, 'idem-empimport-normcase-job-2', v_staff, 'staff');
  perform app.stage_import_rows(v_job2.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', 'emp-case-001', 'full_name', 'Case Variant Person Two', 'employment_type', 'full_time'
  )), v_staff, 'staff');
  select * into v_row2 from app.import_staging_rows where job_id = v_job2.job_id and row_number = 1;
  perform app.validate_employee_import_row(v_row2.id, v_staff, 'staff');
  perform app.commit_employee_import_job(v_job2.job_id, false, v_staff, 'staff');
  select master_record_id into v_second_id from app.employees where tenant_id = v_tenant1 and full_name = 'Case Variant Person Two';

  select count(*) into v_employee_count from app.employees where tenant_id = v_tenant1 and full_name in ('Case Variant Person One', 'Case Variant Person Two');
  if v_employee_count <> 2 then
    raise exception 'assertion failed: expected both case-variant rows to still be created (never a hard block on import), found %', v_employee_count;
  end if;

  select * into v_candidate from app.employee_duplicate_candidates
    where tenant_id = v_tenant1 and source_master_record_id = v_second_id and candidate_master_record_id = v_first_id;
  if not found then
    raise exception 'assertion failed: expected a pending app.employee_duplicate_candidates row linking emp-case-001 back to EMP-CASE-001 -- ISS-2026-279''s own case-sensitivity gap has reappeared';
  end if;
  if v_candidate.decision <> 'pending' or v_candidate.similarity_basis <> 'employee_number_normalized' then
    raise exception 'assertion failed: expected decision=pending/similarity_basis=employee_number_normalized, got decision=%, similarity_basis=%', v_candidate.decision, v_candidate.similarity_basis;
  end if;

  -- Third import: trailing-space variant, the exact 3rd form the entry's own live
  -- reproduction named -- must ALSO be flagged (against both prior rows).
  v_source_file3 := app.initiate_file_upload(v_tenant1, 'employee_document', 'import_job', gen_random_uuid(), 'employees-normcase-3.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-empimport-normcase-source-3', v_staff, 'staff');
  perform app.record_file_scan_result(v_source_file3.id, 'clean', null, v_staff, 'staff');
  v_job3 := app.create_import_export_job(v_tenant1, 'import', 'employee_import', v_source_file3.id, '{}'::jsonb, 'idem-empimport-normcase-job-3', v_staff, 'staff');
  perform app.stage_import_rows(v_job3.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', 'EMP-CASE-001 ', 'full_name', 'Case Variant Person Three', 'employment_type', 'full_time'
  )), v_staff, 'staff');
  select * into v_row3 from app.import_staging_rows where job_id = v_job3.job_id and row_number = 1;
  perform app.validate_employee_import_row(v_row3.id, v_staff, 'staff');
  perform app.commit_employee_import_job(v_job3.job_id, false, v_staff, 'staff');
  select master_record_id into v_third_id from app.employees where tenant_id = v_tenant1 and full_name = 'Case Variant Person Three';

  if (select count(*) from app.employee_duplicate_candidates where tenant_id = v_tenant1 and source_master_record_id = v_third_id) <> 2 then
    raise exception 'assertion failed: expected the trailing-space variant to be flagged against BOTH prior case-variant employees, got % candidate row(s)', (select count(*) from app.employee_duplicate_candidates where tenant_id = v_tenant1 and source_master_record_id = v_third_id);
  end if;

  -- A FOURTH import, with a genuinely unrelated explicit employee_number, must NOT be
  -- flagged -- proving this is a real normalized match, not "every explicitly-numbered
  -- row gets flagged unconditionally."
  v_source_file4 := app.initiate_file_upload(v_tenant1, 'employee_document', 'import_job', gen_random_uuid(), 'employees-normcase-4.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-empimport-normcase-source-4', v_staff, 'staff');
  perform app.record_file_scan_result(v_source_file4.id, 'clean', null, v_staff, 'staff');
  v_job4 := app.create_import_export_job(v_tenant1, 'import', 'employee_import', v_source_file4.id, '{}'::jsonb, 'idem-empimport-normcase-job-4', v_staff, 'staff');
  perform app.stage_import_rows(v_job4.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', 'EMP-CASE-999', 'full_name', 'Case Variant Person Four', 'employment_type', 'full_time'
  )), v_staff, 'staff');
  select * into v_row4 from app.import_staging_rows where job_id = v_job4.job_id and row_number = 1;
  perform app.validate_employee_import_row(v_row4.id, v_staff, 'staff');
  perform app.commit_employee_import_job(v_job4.job_id, false, v_staff, 'staff');
  select master_record_id into v_fourth_id from app.employees where tenant_id = v_tenant1 and full_name = 'Case Variant Person Four';

  if exists (select 1 from app.employee_duplicate_candidates where tenant_id = v_tenant1 and source_master_record_id = v_fourth_id) then
    raise exception 'assertion failed: expected a genuinely unrelated explicit employee_number (no normalized collision with anyone) to NOT be flagged as a duplicate candidate';
  end if;

  raise notice 'ISS-2026-279 employee-number-normalization-detection proof: EMP-CASE-001/emp-case-001/''EMP-CASE-001 '' all commit successfully (never a hard block) and are flagged pairwise into app.employee_duplicate_candidates for human review; a genuinely unrelated explicit number is not flagged';
end;
$$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): anon holds no direct table/EXECUTE access to any new employee object; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; app.validate_employee_import_row is service_role-only (ATW-032''s own live rbac-enforcement.sql gate independently proves the transitive-authority half of this); CRITICAL fix regression -- authenticated''s SELECT on app.employees/app.employee_emergency_contacts/app.employee_change_requests is column-scoped, never full-row (this checkpoint''s own review-round fix, PLT-114''s exact established pattern)'
do $$
declare
  v_has_privilege boolean;
begin
  select has_table_privilege('anon', 'app.employees', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no SELECT on app.employees';
  end if;

  select has_table_privilege('authenticated', 'app.employees', 'INSERT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold no direct INSERT on app.employees (writes go through SECURITY DEFINER RPCs only)';
  end if;

  select has_function_privilege('authenticated', 'app.validate_employee_import_row(uuid, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold no EXECUTE on the service_role-only app.validate_employee_import_row';
  end if;

  -- ISS-2026-065 closure: app.create_employee_draft's own signature grew two new
  -- trailing parameters (p_effective_date/p_backdate_reason, both defaulted) --
  -- referenced here by its current, full signature (the only one that exists;
  -- the migration DROPped the old 21-arg overload rather than layering a second
  -- one alongside it -- see that migration's own header).
  select has_function_privilege('anon', 'app.create_employee_draft(uuid, text, text, text, text, text, text, date, text, date, uuid, uuid, uuid, text, uuid, uuid, text, text, text, uuid, text, date, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on app.create_employee_draft';
  end if;

  -- CRITICAL fix regression: authenticated must hold NO column-level SELECT on any
  -- classified pii column, even though it holds table-level SELECT overall (RLS
  -- filters rows, never columns -- a table-level grant alone leaves every classified
  -- column readable by any tenant member holding zero HRS permission at all).
  if has_column_privilege('authenticated', 'app.employees', 'national_id_number', 'SELECT')
     or has_column_privilege('authenticated', 'app.employees', 'personal_email', 'SELECT')
     or has_column_privilege('authenticated', 'app.employees', 'personal_phone', 'SELECT')
     or has_column_privilege('authenticated', 'app.employees', 'date_of_birth', 'SELECT')
     or has_column_privilege('authenticated', 'app.employees', 'gender', 'SELECT')
     or has_column_privilege('authenticated', 'app.employees', 'personal_address_street', 'SELECT')
  then
    raise exception 'assertion failed: expected authenticated to hold no column SELECT on any classified pii column of app.employees';
  end if;
  if not has_column_privilege('authenticated', 'app.employees', 'full_name', 'SELECT') then
    raise exception 'assertion failed: expected authenticated to still hold column SELECT on the non-pii app.employees.full_name (the fix must not be a blanket revoke)';
  end if;
  if has_column_privilege('authenticated', 'app.employee_emergency_contacts', 'phone', 'SELECT')
     or has_column_privilege('authenticated', 'app.employee_emergency_contacts', 'email', 'SELECT')
  then
    raise exception 'assertion failed: expected authenticated to hold no column SELECT on app.employee_emergency_contacts.phone/email';
  end if;
  if has_column_privilege('authenticated', 'app.employee_change_requests', 'current_value_snapshot', 'SELECT')
     or has_column_privilege('authenticated', 'app.employee_change_requests', 'requested_value', 'SELECT')
  then
    raise exception 'assertion failed: expected authenticated to hold no column SELECT on app.employee_change_requests.current_value_snapshot/requested_value';
  end if;
end;
$$;

\echo '>> CRITICAL fix regression, live session-simulated: a real hrmemp1 tenant member holding ZERO HRS role (tenant_admin, assigned no role in this fixture) passes RLS (has_active_tenant_membership) but is denied at the column-privilege layer reading any classified pii column directly off app.employees/app.employee_emergency_contacts -- while still able to read the non-pii columns RLS alone was always meant to scope'
do $$
declare
  v_target_master_record_id uuid := (select e.master_record_id from app.employees e join app.tenants t on t.id = e.tenant_id where t.slug = 'hrmemp1' and e.idempotency_key = 'idem-lifecycle-1');
  v_contact_id uuid;
begin
  select id into v_contact_id from app.employee_emergency_contacts where master_record_id = v_target_master_record_id and status = 'active' limit 1;

  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027101", "role": "authenticated"}', true);

  begin
    perform (select national_id_number from app.employees where master_record_id = v_target_master_record_id);
    raise exception 'assertion failed: expected permission denied reading app.employees.national_id_number as a zero-HRS-permission tenant member';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform (select personal_email from app.employees where master_record_id = v_target_master_record_id);
    raise exception 'assertion failed: expected permission denied reading app.employees.personal_email as a zero-HRS-permission tenant member';
  exception
    when insufficient_privilege then null;
  end;

  if v_contact_id is not null then
    begin
      perform (select phone from app.employee_emergency_contacts where id = v_contact_id);
      raise exception 'assertion failed: expected permission denied reading app.employee_emergency_contacts.phone as a zero-HRS-permission tenant member';
    exception
      when insufficient_privilege then null;
    end;
  end if;

  if not exists (select 1 from app.employees where master_record_id = v_target_master_record_id and full_name is not null) then
    raise exception 'assertion failed: expected the non-pii app.employees.full_name column to remain directly readable for a real tenant member (RLS row-scoping, unaffected by the column fix)';
  end if;

  reset role;
end;
$$;

\echo '>> MEDIUM fix regression: app.update_employee_emergency_contact/app.remove_employee_emergency_contact check authority BEFORE record_version (this checkpoint''s own review-round fix) -- a Tenant B actor with zero relation to hrmemp1 gets employee_not_found, never stale_version (which would disclose the contact''s real record_version), and the contact is genuinely unchanged by both rejected attempts'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_t2_staff uuid := '00000000-0000-0000-0000-000000027202';
  v_employee app.employees;
  v_contact app.employee_emergency_contacts;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'Contact Order Person', 'full_time', null, null, null, null, null, null, '2026-04-01', (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HR1'), null, null, null, null, null, null, 'hr_created', 'idem-contactorder-1', v_staff, 'staff');
  v_contact := app.add_employee_emergency_contact(v_employee.master_record_id, 'Order Contact', null, '+62-811-5000', null, true, v_staff, 'staff');

  begin
    perform app.update_employee_emergency_contact(v_contact.id, 999, 'x', 'x', 'x', 'x@x.test', false, v_t2_staff, 'Cross-Tenant Actor');
    raise exception 'assertion failed: expected employee_not_found (never stale_version) for a Tenant B actor updating a Tenant A contact';
  exception
    when others then
      if sqlerrm not like 'employee_not_found%' then raise; end if;
  end;

  begin
    perform app.remove_employee_emergency_contact(v_contact.id, 999, v_t2_staff, 'Cross-Tenant Actor');
    raise exception 'assertion failed: expected employee_not_found (never stale_version) for a Tenant B actor removing a Tenant A contact';
  exception
    when others then
      if sqlerrm not like 'employee_not_found%' then raise; end if;
  end;

  if (select name from app.employee_emergency_contacts where id = v_contact.id) <> 'Order Contact'
     or (select status from app.employee_emergency_contacts where id = v_contact.id) <> 'active'
  then
    raise exception 'assertion failed: the contact must be genuinely unchanged after both rejected cross-tenant attempts';
  end if;
end;
$$;

\echo '>> HIGH fix regression: create_employee_draft''s idempotency-key replay compares the FULL input tuple, not merely full_name (this checkpoint''s own review-round fix) -- a same-key/same-full_name/different-other-field replay is rejected as idempotency_key_conflict, never silently returned with the first call''s stale data'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_first app.employees;
begin
  v_first := app.create_employee_draft(v_tenant1, 'Idem Tuple Person', 'full_time', 'first@work.example', 'first-personal@example.com', '+62-811-0001', null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-tuple-probe-1', v_staff, 'staff');

  begin
    perform app.create_employee_draft(v_tenant1, 'Idem Tuple Person', 'contract', 'second@work.example', 'second-personal@example.com', '+62-811-9999', null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-tuple-probe-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a same-key/same-full_name/different-employment_type-and-contact replay';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  if (select employment_type from app.employees where master_record_id = v_first.master_record_id) <> 'full_time'
     or (select work_email from app.employees where master_record_id = v_first.master_record_id) <> 'first@work.example'
  then
    raise exception 'assertion failed: the original row must be unaffected by the rejected conflicting replay';
  end if;

  -- A genuine same-key/same-full-tuple replay is still a safe, silent no-op (the
  -- pre-existing, correct behavior -- unaffected by this fix).
  if (app.create_employee_draft(v_tenant1, 'Idem Tuple Person', 'full_time', 'first@work.example', 'first-personal@example.com', '+62-811-0001', null, null, null, null, null, null, null, null, null, null, null, 'hr_created', 'idem-tuple-probe-1', v_staff, 'staff')).master_record_id <> v_first.master_record_id then
    raise exception 'assertion failed: expected a genuine same-tuple replay to return the SAME row, not create a new one';
  end if;
end;
$$;

\echo '>> CRITICAL fix regression: app.audit_logs never carries a classified pii value for any app.employees/app.employee_emergency_contacts/app.employee_change_requests lifecycle event (this checkpoint''s own review-round fix -- app.redact_audit_payload''s key-name-pattern redaction does not match these column names, so to_jsonb() of a raw row previously wrote national_id_number/personal_email/personal_phone/date_of_birth/gender/contact-phone/contact-email/current_value_snapshot/requested_value into app.audit_logs in plaintext)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_self_auth uuid := '00000000-0000-0000-0000-000000027111';
  v_employee app.employees;
  v_contact app.employee_emergency_contacts;
  v_request app.employee_change_requests;
  v_after jsonb;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'Audit Redaction Person', 'full_time', 'audit-work@example.test', 'audit-secret-personal@example.test', '+62-811-7777', 'ID-AUDIT-SECRET-1', '1991-02-03', 'female', null, null, null, null, null, null, null, null, 'hr_created', 'idem-auditredact-1', v_staff, 'staff');

  select after_value into v_after from app.audit_logs where action = 'create_employee_draft' and resource_id = v_employee.master_record_id order by occurred_at desc limit 1;
  if v_after is null or v_after ? 'national_id_number' or v_after ? 'personal_email' or v_after ? 'personal_phone' or v_after ? 'date_of_birth' or v_after ? 'gender' then
    raise exception 'assertion failed: create_employee_draft''s own audit after_value must never carry a classified pii key, got %', v_after;
  end if;

  v_employee := app.update_employee_draft(v_employee.master_record_id, v_employee.record_version, 'Audit Redaction Person', 'contract', 'audit-work@example.test', 'audit-secret-personal-2@example.test', '+62-811-7778', 'ID-AUDIT-SECRET-2', '1991-02-03', 'female', null, null, null, null, null, null, null, v_staff, 'staff');
  select after_value into v_after from app.audit_logs where action = 'update_employee_draft' and resource_id = v_employee.master_record_id order by occurred_at desc limit 1;
  if v_after is null or v_after ? 'national_id_number' or v_after ? 'personal_email' or v_after ? 'personal_phone' then
    raise exception 'assertion failed: update_employee_draft''s own audit after_value must never carry a classified pii key, got %', v_after;
  end if;

  v_contact := app.add_employee_emergency_contact(v_employee.master_record_id, 'Audit Contact', null, '+62-811-8888', 'audit-contact@example.test', true, v_staff, 'staff');
  select after_value into v_after from app.audit_logs where action = 'add_employee_emergency_contact' and resource_id = v_contact.id order by occurred_at desc limit 1;
  if v_after is null or v_after ? 'phone' or v_after ? 'email' then
    raise exception 'assertion failed: add_employee_emergency_contact''s own audit after_value must never carry phone/email, got %', v_after;
  end if;

  -- Link the employee to a fresh, never-before-linked Platform user so
  -- request_employee_change's own identity-match gate is satisfiable.
  insert into auth.users (id, email) values (v_self_auth, 'auditself@hrmemp1.test');
  perform app.invite_user(v_tenant1, v_self_auth, 'auditself@hrmemp1.test', 'Audit Self Person', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'auditself@hrmemp1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_self_auth, 'org_user', v_tenant1, null, 'tester');
  v_employee := app.link_employee_user(v_employee.master_record_id, v_employee.record_version, (select id from app.users where email = 'auditself@hrmemp1.test'), v_staff, 'staff');

  v_request := app.request_employee_change(v_employee.master_record_id, 'personal_email', 'audit-requested-secret@example.test', 'update please', v_self_auth);
  select after_value into v_after from app.audit_logs where action = 'request_employee_change' and resource_id = v_request.id order by occurred_at desc limit 1;
  if v_after is null or v_after ? 'current_value_snapshot' or v_after ? 'requested_value' then
    raise exception 'assertion failed: request_employee_change''s own audit after_value must never carry current_value_snapshot/requested_value, got %', v_after;
  end if;
  if (select requested_value from app.employee_change_requests where id = v_request.id) <> 'audit-requested-secret@example.test' then
    raise exception 'assertion failed: the real request row itself must still carry the real requested_value (only the audit copy is redacted)';
  end if;
end;
$$;

\echo '>> HIGH fix regression: an inactive company/branch/department org unit may not be assigned to an employee on create OR transfer (section 23''s "block ... inactive organization" rule, this checkpoint''s own review-round fix)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_inactive_company uuid;
  v_active_employee app.employees;
begin
  v_inactive_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-HR1-INACTIVE', 'Inactive Co', 'tester')).id;
  perform app.set_org_unit_status(v_inactive_company, 'inactive', 1, 'closing down', 'tester');

  begin
    perform app.create_employee_draft(v_tenant1, 'Inactive Org Person', 'full_time', null, null, null, null, null, null, null, v_inactive_company, null, null, null, null, null, null, 'hr_created', 'idem-inactiveorg-1', v_staff, 'staff');
    raise exception 'assertion failed: expected org_unit_inactive rejecting an inactive company_org_unit_id on create';
  exception
    when others then
      if sqlerrm not like 'org_unit_inactive%' then raise; end if;
  end;

  -- A legal active-company employee, then a transfer INTO the same inactive company
  -- must also be rejected.
  v_active_employee := app.create_employee_draft(v_tenant1, 'Transfer Target Person', 'full_time', null, null, null, null, null, null, null, (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HR1'), null, null, null, null, null, null, 'hr_created', 'idem-inactiveorg-2', v_staff, 'staff');
  begin
    perform app.transfer_employee(v_active_employee.master_record_id, v_active_employee.record_version, v_inactive_company, null, null, null, null, 'reorg', v_staff, 'staff');
    raise exception 'assertion failed: expected org_unit_inactive rejecting a transfer into an inactive company_org_unit_id';
  exception
    when others then
      if sqlerrm not like 'org_unit_inactive%' then raise; end if;
  end;

  if (select company_org_unit_id from app.employees where master_record_id = v_active_employee.master_record_id) is not distinct from v_inactive_company then
    raise exception 'assertion failed: the rejected transfer must not have moved the employee into the inactive company';
  end if;
end;
$$;

\echo '>> LOW fix regression: app.reactivate_employee restores the status the employee was suspended FROM (active or on_leave), not always ''active'' (this checkpoint''s own review-round fix) -- an employee suspended while on_leave reads as on_leave again after reactivation, not silently ''active'''
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_approver uuid := '00000000-0000-0000-0000-000000027103';
  v_manager uuid := '00000000-0000-0000-0000-000000027104';
  v_employee app.employees;
begin
  v_employee := app.create_employee_draft(v_tenant1, 'Reactivate Fidelity Person', 'full_time', null, null, null, null, null, null, '2026-04-01', (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HR1'), null, null, null, null, null, null, 'hr_created', 'idem-reactivatefid-1', v_staff, 'staff');
  perform app.add_employee_emergency_contact(v_employee.master_record_id, 'Fidelity Contact', null, '+62-811-6000', null, true, v_staff, 'staff');
  v_employee := app.submit_employee_for_approval(v_employee.master_record_id, v_employee.record_version, v_staff, 'staff');
  v_employee := app.decide_employee_approval(v_employee.master_record_id, v_employee.record_version, 'approve', null, v_approver, 'approver');
  v_employee := app.activate_employee(v_employee.master_record_id, v_employee.record_version, v_approver, 'approver');
  v_employee := app.start_employee_leave(v_employee.master_record_id, v_employee.record_version, 'family leave', v_staff, 'staff');
  if v_employee.lifecycle_status <> 'on_leave' then
    raise exception 'assertion failed: expected on_leave after start_employee_leave, got %', v_employee.lifecycle_status;
  end if;

  v_employee := app.suspend_employee(v_employee.master_record_id, v_employee.record_version, 'policy violation while on leave', v_manager, 'manager');
  if v_employee.lifecycle_status <> 'suspended' then
    raise exception 'assertion failed: expected suspended, got %', v_employee.lifecycle_status;
  end if;

  v_employee := app.reactivate_employee(v_employee.master_record_id, v_employee.record_version, v_manager, 'manager');
  if v_employee.lifecycle_status <> 'on_leave' then
    raise exception 'assertion failed: expected reactivate_employee to restore on_leave (the real pre-suspension status), got %', v_employee.lifecycle_status;
  end if;
end;
$$;

\echo '>> LOW coverage gap closed: an unscanned (not_yet_scanned) employee document is denied by app.authorize_file_access for a non-uploader tenant member, and an infected one is denied even for the uploader themself (section 27''s ''unscanned documents'' test-data requirement, generic PLT-128 mechanism, exercised here for record_type=''employee'')'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_viewer uuid := '00000000-0000-0000-0000-000000027105';
  v_pending_file app.files;
  v_infected_file app.files;
  v_log app.file_access_logs;
begin
  v_pending_file := app.initiate_file_upload(v_tenant1, 'employee_document', 'employee', gen_random_uuid(), 'unscanned.csv', 'text/csv', 1024, null, false, null, '{}', null, 'idem-empfile-pending-1', v_staff, 'staff');
  v_log := app.authorize_file_access(v_pending_file.id, 'download', v_viewer);
  if v_log.result <> 'denied' or v_log.reason <> 'document_not_yet_scanned' then
    raise exception 'assertion failed: expected an unscanned (not_yet_scanned) employee document to be denied for a non-uploader tenant member, got result=% reason=%', v_log.result, v_log.reason;
  end if;

  v_infected_file := app.initiate_file_upload(v_tenant1, 'employee_document', 'employee', gen_random_uuid(), 'infected.csv', 'text/csv', 1024, null, false, null, '{}', null, 'idem-empfile-infected-1', v_staff, 'staff');
  perform app.record_file_scan_result(v_infected_file.id, 'infected', 'eicar-test-signature', v_staff, 'staff');
  v_log := app.authorize_file_access(v_infected_file.id, 'download', v_staff);
  if v_log.result <> 'denied' or v_log.reason <> 'document_infected_quarantined' then
    raise exception 'assertion failed: expected an infected employee document to be denied even for the uploader themself, got result=% reason=%', v_log.result, v_log.reason;
  end if;
end;
$$;

\echo '>> never touched: app.master_records/app.master_types/app.org_units/app.users structural shape is unchanged by this migration'
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'app' and table_name = 'master_records' and column_name = 'master_type_code') then
    raise exception 'assertion failed: app.master_records.master_type_code missing -- structural regression';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'app' and table_name = 'org_units' and column_name = 'unit_type') then
    raise exception 'assertion failed: app.org_units.unit_type missing -- structural regression';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'app' and table_name = 'users' and column_name = 'auth_user_id') then
    raise exception 'assertion failed: app.users.auth_user_id missing -- structural regression';
  end if;
end;
$$;

\echo '>> HRT-293 Finding A (CRITICAL) regression: app.employees'' five HR-narrative reason columns (revision_reason/suspend_reason/terminate_reason/archive_reason/leave_reason) are masked to self-or-HRS:View-personal-data identically to every other classified personal field -- previously returned unconditionally by app.get_employee_profile and included in app.employees'' own column-restricted grant to authenticated; app.employee_lifecycle_events.reason is masked the same way in app.get_employee_lifecycle_history and no longer carries a blanket table-level grant to authenticated'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HR1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_approver uuid := '00000000-0000-0000-0000-000000027103';
  v_override_manager uuid := '00000000-0000-0000-0000-000000027104';
  v_viewer uuid := '00000000-0000-0000-0000-000000027105';
  v_pdv uuid := '00000000-0000-0000-0000-000000027107';
  v_draft app.employees;
  v_active app.employees;
  v_suspended app.employees;
  v_profile record;
  v_before_count integer;
  v_reason text := 'HRT-293 regression: confidential medical/disciplinary narrative';
begin
  v_draft := app.create_employee_draft(v_tenant1, 'HRT293 Regression Employee', 'full_time', 'hrt293regression@work.test', null, null, null, null, null, '2024-01-01', v_company, null, null, 'Engineer', null, null, null, 'hr_created', 'idem-hrt293-emp-reg-1', v_staff, 'staff');
  perform app.add_employee_emergency_contact(v_draft.master_record_id, 'Emergency Contact', 'spouse', '+15550009999', 'ec@example.test', true, v_staff, 'staff');
  select * into v_draft from app.employees where master_record_id = v_draft.master_record_id;
  perform app.submit_employee_for_approval(v_draft.master_record_id, v_draft.record_version, v_staff, 'staff');
  select * into v_draft from app.employees where master_record_id = v_draft.master_record_id;
  v_active := app.decide_employee_approval(v_draft.master_record_id, v_draft.record_version, 'approve', null, v_approver, 'approver');
  v_active := app.activate_employee(v_active.master_record_id, v_active.record_version, v_approver, 'approver');

  v_before_count := (select count(*) from app.audit_logs);
  v_suspended := app.suspend_employee(v_active.master_record_id, v_active.record_version, v_reason, v_override_manager, 'override_manager');

  -- (a) A personal-data-viewer sees the real suspend_reason.
  select * into v_profile from app.get_employee_profile(v_suspended.master_record_id, v_pdv);
  if v_profile.suspend_reason is distinct from v_reason then
    raise exception 'HRT-293 Finding A regression: pdv (HRS:View personal data) should see the real suspend_reason via get_employee_profile, got %', v_profile.suspend_reason;
  end if;

  -- (b) A plain HRS:View holder (no personal-data permission) gets it masked to null.
  select * into v_profile from app.get_employee_profile(v_suspended.master_record_id, v_viewer);
  if v_profile.suspend_reason is not null then
    raise exception 'HRT-293 Finding A regression: plain HRS:View viewer should NOT see suspend_reason via get_employee_profile, got %', v_profile.suspend_reason;
  end if;

  -- (c) The same masking holds on app.employee_lifecycle_events via app.get_employee_lifecycle_history.
  if exists (select 1 from app.get_employee_lifecycle_history(v_suspended.master_record_id, v_viewer) where to_status = 'suspended' and reason is not null) then
    raise exception 'HRT-293 Finding A regression: plain HRS:View viewer should see a null reason in app.get_employee_lifecycle_history for the suspend transition';
  end if;
  if not exists (select 1 from app.get_employee_lifecycle_history(v_suspended.master_record_id, v_pdv) where to_status = 'suspended' and reason = v_reason) then
    raise exception 'HRT-293 Finding A regression: pdv should see the real reason in app.get_employee_lifecycle_history for the suspend transition';
  end if;

  -- (d) A raw, forged-session SELECT of the sensitive columns via the `authenticated` role is denied outright -- a database guarantee, not merely RPC-layer masking.
  perform set_config('request.jwt.claims', json_build_object('sub', v_viewer::text, 'role', 'authenticated')::text, true);
  begin
    set local role authenticated;
    begin
      execute 'select suspend_reason from app.employees where master_record_id = $1' using v_suspended.master_record_id;
      raise exception 'HRT-293 Finding A regression: raw SELECT of app.employees.suspend_reason should be denied for the authenticated role (column-level grant)';
    exception
      when insufficient_privilege then null;
    end;
    begin
      execute 'select reason from app.employee_lifecycle_events where master_record_id = $1' using v_suspended.master_record_id;
      raise exception 'HRT-293 Finding A regression: raw SELECT of app.employee_lifecycle_events.reason should be denied for the authenticated role (column-level grant)';
    exception
      when insufficient_privilege then null;
    end;
    reset role;
  end;
  -- HDN-372 (Step 15, Prompt 372, Tenant Isolation Audit): `reset role` above restores
  -- the calling superuser role, but `request.jwt.claims` was set with `set_config(...,
  -- true)` -- LOCAL to this transaction, not tied to the role -- so it would otherwise
  -- keep resolving auth.uid() to v_viewer for the rest of this block. app.query_audit_logs
  -- below is called with a different, hardcoded actor (the tenant_admin); since
  -- HDN-372 wired app.assert_actor_is_session_identity into it, that call now correctly
  -- requires auth.uid() to either match the passed actor or be NULL (the ordinary,
  -- session-less shape every other call in this file already uses). Clearing it here
  -- restores that shape rather than leaving a stale forged-actor session bleeding into
  -- unrelated assertions below. Must be '{}', not null/''/omitted: a custom-placeholder
  -- GUC already SET in this transaction does not revert to unset on set_config(...,
  -- null, true) -- it becomes the empty string, and auth.uid()'s own ::json cast then
  -- RAISES on '' rather than returning null (the same quirk already root-caused and
  -- fixed with this exact '{}' idiom at scripts/db-tests/commercial-rate-cost-
  -- lookup.sql's own DO block, the established precedent this follows).
  perform set_config('request.jwt.claims', '{}', true);

  -- (e) HRT-293 Finding B: app.audit_logs never carries the raw suspend_reason, for this action or any prior action in this same test run, and a plain tenant_admin (zero HRS grant) reading via app.query_audit_logs never sees it either.
  if exists (select 1 from app.audit_logs where reason = v_reason) then
    raise exception 'HRT-293 Finding B regression: app.audit_logs.reason must never carry the raw suspend reason';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'suspend_employee' and resource_id = v_suspended.master_record_id and reason is null and occurred_at >= now() - interval '5 minutes') then
    raise exception 'HRT-293 Finding B regression: expected a suspend_employee audit_logs row with reason=null for this test''s own suspend call';
  end if;
  if exists (select 1 from app.query_audit_logs('00000000-0000-0000-0000-000000027101', v_tenant1, 200) where reason = v_reason) then
    raise exception 'HRT-293 Finding B regression: a plain tenant_admin (zero HRS grant) must never see the raw suspend reason via app.query_audit_logs';
  end if;
end;
$$;

\echo '>> HRT-295 (CG-S12-HRT-023) / ISS-2026-104 fix: app.suspend_employee/app.terminate_employee now couple to the REAL Platform-authority revoke in the SAME transaction -- zero Onboarding/Offboarding case ever created (the exact live-reproduced gap: a terminated or suspended employee previously kept full role-granted authority indefinitely unless HR separately, manually drove a wholly optional case to one specific task). Role_assignments are stripped (ISS-2026-072 centralized fix, both suspend AND revoke), app.users.status is coupled correctly, and app.reactivate_employee (this capability''s own existing un-suspend path) mirrors it on the way back -- WITHOUT auto-restoring the stripped role_assignments, matching this same migration''s rehire precedent'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HR1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_approver uuid := '00000000-0000-0000-0000-000000027103';
  v_override_manager uuid := '00000000-0000-0000-0000-000000027104';
  v_worker_auth uuid := '00000000-0000-0000-0000-000000027112';
  v_viewer_role_version_id uuid;
  v_worker_user app.users;
  v_draft app.employees;
  v_active app.employees;
  v_decision app.rbac_decision;
  v_active_role_count integer;
  v_profile_count integer;
begin
  insert into auth.users (id, email) values (v_worker_auth, 'termcoupling@hrmemp1.test');
  perform app.invite_user(v_tenant1, v_worker_auth, 'termcoupling@hrmemp1.test', 'Term Coupling Worker', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'termcoupling@hrmemp1.test'), 'active', 'onboarded', 'tester');
  select * into v_worker_user from app.users where email = 'termcoupling@hrmemp1.test';

  -- A real, unrelated role assignment -- proves system-wide, not merely
  -- ticketing-specific, authority retention (ISS-2026-104's own live
  -- reproduction used an unrelated PRC:Create grant for the identical point;
  -- this file's own tenant carries an HRS Viewer role, reused here).
  select id into v_viewer_role_version_id from app.role_versions
  where role_id = (select id from app.roles where tenant_id = v_tenant1 and name = 'HRS Viewer') and status = 'published';
  perform app.assign_role(v_tenant1, v_viewer_role_version_id, v_worker_auth, '00000000-0000-0000-0000-000000027101', 'tester');

  v_draft := app.create_employee_draft(
    v_tenant1, 'Term Coupling Worker', 'full_time', 'termcoupling@hrmemp1.test', null, null, null, null, null, '2024-01-01',
    v_company, null, null, 'Engineer', null, v_worker_user.id, null, 'hr_created', 'idem-termcoupling-1',
    v_staff, 'staff'
  );
  perform app.add_employee_emergency_contact(v_draft.master_record_id, 'Emergency Contact', 'spouse', '+15550009999', 'ec@example.test', true, v_staff, 'staff');
  select * into v_draft from app.employees where master_record_id = v_draft.master_record_id;
  perform app.submit_employee_for_approval(v_draft.master_record_id, v_draft.record_version, v_staff, 'staff');
  select * into v_draft from app.employees where master_record_id = v_draft.master_record_id;
  v_active := app.decide_employee_approval(v_draft.master_record_id, v_draft.record_version, 'approve', null, v_approver, 'approver');
  v_active := app.activate_employee(v_active.master_record_id, v_active.record_version, v_approver, 'approver');

  -- Baseline, before any lifecycle change: full authority.
  v_decision := app.evaluate_permission(v_worker_auth, v_tenant1, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'assertion failed: expected the worker to hold HRS:View before suspend, got allowed=%', v_decision.allowed;
  end if;
  select count(*) into v_profile_count from app.get_my_employee_profile(v_tenant1, v_worker_auth);
  if v_profile_count <> 1 then
    raise exception 'assertion failed: expected the worker to read their own employee profile before suspend, got % row(s)', v_profile_count;
  end if;

  -- --- suspend: permission-gated authority blocked; self-service reads (tenant
  -- membership only) deliberately UNCHANGED -- a temporary freeze, not an exit.
  v_active := app.suspend_employee(v_active.master_record_id, v_active.record_version, 'under investigation', v_override_manager, 'override_manager');
  if v_active.lifecycle_status <> 'suspended' then
    raise exception 'assertion failed: expected suspended, got %', v_active.lifecycle_status;
  end if;
  if (select status from app.users where id = v_worker_user.id) <> 'suspended' then
    raise exception 'assertion failed: expected the linked Platform user status=suspended after app.suspend_employee';
  end if;
  select count(*) into v_active_role_count from app.role_assignments where tenant_id = v_tenant1 and auth_user_id = v_worker_auth and status = 'active';
  if v_active_role_count <> 0 then
    raise exception 'assertion failed: expected zero active role_assignments after suspend, found %', v_active_role_count;
  end if;
  v_decision := app.evaluate_permission(v_worker_auth, v_tenant1, 'HRS', 'View');
  if v_decision.allowed then
    raise exception 'assertion failed: expected HRS:View denied for a suspended employee once role_assignments are revoked, got allowed=true';
  end if;
  if not app.has_active_tenant_membership(v_tenant1, v_worker_auth) then
    raise exception 'assertion failed: suspend deliberately does not revoke tenant_user_identities (unlike terminate) -- expected has_active_tenant_membership to remain true';
  end if;
  select count(*) into v_profile_count from app.get_my_employee_profile(v_tenant1, v_worker_auth);
  if v_profile_count <> 1 then
    raise exception 'assertion failed: suspend deliberately preserves self-service reads (a suspended employee can still see their own profile / open a ticket about the suspension) -- expected 1 row, got %', v_profile_count;
  end if;

  -- --- reactivate (this capability's own existing un-suspend path, checked per
  -- this task's own instruction): restores the Platform user to active, but does
  -- NOT auto-restore the stripped role_assignment.
  v_active := app.reactivate_employee(v_active.master_record_id, v_active.record_version, v_override_manager, 'override_manager');
  if v_active.lifecycle_status <> 'active' then
    raise exception 'assertion failed: expected active after reactivate, got %', v_active.lifecycle_status;
  end if;
  if (select status from app.users where id = v_worker_user.id) <> 'active' then
    raise exception 'assertion failed: expected the linked Platform user status=active after app.reactivate_employee';
  end if;
  v_decision := app.evaluate_permission(v_worker_auth, v_tenant1, 'HRS', 'View');
  if v_decision.allowed then
    raise exception 'assertion failed: expected HRS:View to remain denied after reactivation -- role_assignments are never auto-restored by a status flip';
  end if;

  -- A real, separate, explicit re-grant restores it.
  perform app.assign_role(v_tenant1, v_viewer_role_version_id, v_worker_auth, '00000000-0000-0000-0000-000000027101', 'tester');
  v_decision := app.evaluate_permission(v_worker_auth, v_tenant1, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'assertion failed: expected HRS:View restored after an explicit, separate app.assign_role re-grant';
  end if;

  -- --- terminate: zero Onboarding/Offboarding case ever created -- exactly
  -- ISS-2026-104's own live reproduction shape. Blocks BOTH permission-gated
  -- authority AND self-service reads (unlike suspend -- a genuine exit, not a
  -- temporary freeze).
  v_active := app.terminate_employee(v_active.master_record_id, v_active.record_version, 'resignation', current_date, v_override_manager, 'override_manager');
  if v_active.lifecycle_status <> 'terminated' then
    raise exception 'assertion failed: expected terminated, got %', v_active.lifecycle_status;
  end if;
  if (select status from app.users where id = v_worker_user.id) <> 'revoked' then
    raise exception 'assertion failed: expected the linked Platform user ACTUALLY revoked via app.transition_user_status, never a separate optional offboarding case';
  end if;
  select count(*) into v_active_role_count from app.role_assignments where tenant_id = v_tenant1 and auth_user_id = v_worker_auth and status = 'active';
  if v_active_role_count <> 0 then
    raise exception 'assertion failed: expected zero active role_assignments after termination, found %', v_active_role_count;
  end if;
  v_decision := app.evaluate_permission(v_worker_auth, v_tenant1, 'HRS', 'View');
  if v_decision.allowed then
    raise exception 'assertion failed: expected HRS:View denied for a terminated employee, got allowed=true (system-wide authority-retention gap, ISS-2026-104)';
  end if;
  if app.has_active_tenant_membership(v_tenant1, v_worker_auth) then
    raise exception 'assertion failed: expected has_active_tenant_membership=false for a terminated employee';
  end if;
  select count(*) into v_profile_count from app.get_my_employee_profile(v_tenant1, v_worker_auth);
  if v_profile_count <> 0 then
    raise exception 'assertion failed: expected a terminated employee''s own self-read (app.get_my_employee_profile) to return zero rows, got %', v_profile_count;
  end if;

  -- Real forged session (request.jwt.claims + set role authenticated, this
  -- file's own established technique) -- proves this is not merely an
  -- internal-call artifact: a genuine terminated-employee session reading
  -- HRS-gated self data now fails.
  perform set_config('request.jwt.claims', json_build_object('sub', v_worker_auth::text, 'role', 'authenticated')::text, true);
  begin
    set local role authenticated;
    select count(*) into v_profile_count from app.get_my_employee_profile(v_tenant1, v_worker_auth);
    if v_profile_count <> 0 then
      raise exception 'assertion failed: expected a terminated employee''s own forged-session self-read to return zero rows, got %', v_profile_count;
    end if;
    reset role;
  end;
  perform set_config('request.jwt.claims', 'null', true);

  -- app.terminate_employee against an ALREADY-revoked linked user (idempotency
  -- of the Platform coupling itself, not merely the HR-side state machine) --
  -- re-terminating is rejected on the employee's own lifecycle_status (terminated
  -- is not in the allowed from-set) before the Platform call is ever reached, so
  -- this also proves the earlier revoke never left the row in a state a second
  -- legitimate call could not cleanly reason about.
  begin
    perform app.terminate_employee(v_active.master_record_id, v_active.record_version, 'again', current_date, v_override_manager, 'override_manager');
    raise exception 'assertion failed: expected re-terminating an already-terminated employee to fail on invalid_transition';
  exception when check_violation then null;
  end;
end;
$$;

-- ===========================================================================
-- HRT-295 Tier C review fix (integration lens finding, test-coverage gap,
-- not a functional defect): 20260731230000's own header/comment states three
-- separate times that terminating/suspending a tenant's last active
-- tenant_admin is "now reachable from HRIS for the first time" via the
-- last_critical_admin guard (ISS-2026-072's own pre-existing check inside
-- app.transition_user_status) -- but no db-test anywhere in this repository
-- ever drove app.terminate_employee/app.suspend_employee against a tenant's
-- last active tenant_admin. The code itself is genuinely correct (confirmed
-- below) -- this closes the missing regression-coverage gap so a future
-- regression here would actually be caught by `pnpm run db:test`.
-- ===========================================================================

\echo '>> HRT-295 Tier C review: app.terminate_employee/app.suspend_employee against a tenant''s LAST active tenant_admin correctly raises last_critical_admin (ISS-2026-072''s own pre-existing guard, newly reachable from HRIS via 20260731230000) and rolls back the WHOLE transaction atomically -- never a half-applied HR-side state change with the Platform side left untouched'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrmemp1');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HR1');
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_approver uuid := '00000000-0000-0000-0000-000000027103';
  v_override_manager uuid := '00000000-0000-0000-0000-000000027104';
  v_new_admin_auth uuid := '00000000-0000-0000-0000-000000027120';
  v_new_admin_user app.users;
  v_draft app.employees;
  v_active app.employees;
  v_original_admin_membership uuid;
  v_pre_status text;
  v_pre_version integer;
  v_pre_lifecycle text;
begin
  -- A second employee, linked to a new Platform user, granted tenant_admin
  -- -- now TWO active tenant_admins for hrmemp1 (the fixture's own
  -- pre-existing 00000000-...027101, plus this new one).
  insert into auth.users (id, email) values (v_new_admin_auth, 'lastcriticaladmin@hrmemp1.test');
  perform app.invite_user(v_tenant1, v_new_admin_auth, 'lastcriticaladmin@hrmemp1.test', 'Last Critical Admin Worker', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'lastcriticaladmin@hrmemp1.test'), 'active', 'onboarded', 'tester');
  select * into v_new_admin_user from app.users where email = 'lastcriticaladmin@hrmemp1.test';
  perform app.grant_principal_membership(v_new_admin_auth, 'tenant_admin', v_tenant1, null, 'tester');

  v_draft := app.create_employee_draft(
    v_tenant1, 'Last Critical Admin Worker', 'full_time', 'lastcriticaladmin@hrmemp1.test', null, null, null, null, null, '2024-01-01',
    v_company, null, null, 'Head of Operations', null, v_new_admin_user.id, null, 'hr_created', 'idem-lastcriticaladmin-1',
    v_staff, 'staff'
  );
  perform app.add_employee_emergency_contact(v_draft.master_record_id, 'Emergency Contact', 'spouse', '+15550008888', 'ec2@example.test', true, v_staff, 'staff');
  select * into v_draft from app.employees where master_record_id = v_draft.master_record_id;
  perform app.submit_employee_for_approval(v_draft.master_record_id, v_draft.record_version, v_staff, 'staff');
  select * into v_draft from app.employees where master_record_id = v_draft.master_record_id;
  v_active := app.decide_employee_approval(v_draft.master_record_id, v_draft.record_version, 'approve', null, v_approver, 'approver');
  v_active := app.activate_employee(v_active.master_record_id, v_active.record_version, v_approver, 'approver');

  -- Revoke the fixture's own ORIGINAL tenant_admin (00000000-...027101) so
  -- this NEW employee's linked identity becomes the tenant's ONLY active
  -- tenant_admin -- the exact precondition last_critical_admin guards.
  select id into v_original_admin_membership from app.principal_memberships
  where auth_user_id = '00000000-0000-0000-0000-000000027101' and tenant_id = v_tenant1 and layer = 'tenant_admin' and status = 'active';
  perform app.revoke_principal_membership(v_original_admin_membership, 'HRT-295 Tier C fixture: isolate the last-critical-admin precondition', 'tester');

  if (select count(*) from app.principal_memberships where tenant_id = v_tenant1 and layer = 'tenant_admin' and status = 'active') <> 1 then
    raise exception 'assertion failed: expected exactly one active tenant_admin remaining for hrmemp1 (this new employee''s own identity)';
  end if;

  v_pre_lifecycle := v_active.lifecycle_status;
  v_pre_version := v_active.record_version;
  v_pre_status := (select status from app.users where id = v_new_admin_user.id);

  -- terminate_employee: rejected, and the WHOLE transaction rolls back --
  -- never a half-applied state (HR side flipped, Platform side untouched,
  -- or vice versa).
  begin
    perform app.terminate_employee(v_active.master_record_id, v_active.record_version, 'attempted termination of the last critical admin', current_date, v_override_manager, 'override_manager');
    raise exception 'assertion failed: expected app.terminate_employee against the tenant''s last active tenant_admin to raise last_critical_admin';
  exception
    when others then
      if sqlerrm not like 'last_critical_admin:%' then
        raise;
      end if;
  end;

  if (select lifecycle_status from app.employees where master_record_id = v_active.master_record_id) <> v_pre_lifecycle
     or (select record_version from app.employees where master_record_id = v_active.master_record_id) <> v_pre_version then
    raise exception 'HRT-295 Tier C REGRESSION: expected the employee''s own lifecycle_status/record_version genuinely UNCHANGED after a rejected last_critical_admin termination (atomic rollback), got a partial change';
  end if;
  if (select status from app.users where id = v_new_admin_user.id) <> v_pre_status then
    raise exception 'HRT-295 Tier C REGRESSION: expected the linked Platform user''s own status genuinely UNCHANGED after a rejected last_critical_admin termination (atomic rollback), got a partial change';
  end if;
  if (select count(*) from app.principal_memberships where tenant_id = v_tenant1 and layer = 'tenant_admin' and status = 'active') <> 1 then
    raise exception 'HRT-295 Tier C REGRESSION: expected the tenant_admin membership itself genuinely unaffected by the rejected call';
  end if;

  -- suspend_employee: identical guard, identical atomic rollback.
  begin
    perform app.suspend_employee(v_active.master_record_id, v_active.record_version, 'attempted suspension of the last critical admin', v_override_manager, 'override_manager');
    raise exception 'assertion failed: expected app.suspend_employee against the tenant''s last active tenant_admin to raise last_critical_admin';
  exception
    when others then
      if sqlerrm not like 'last_critical_admin:%' then
        raise;
      end if;
  end;
  if (select lifecycle_status from app.employees where master_record_id = v_active.master_record_id) <> v_pre_lifecycle then
    raise exception 'HRT-295 Tier C REGRESSION: expected the employee''s own lifecycle_status genuinely UNCHANGED after a rejected last_critical_admin suspension (atomic rollback)';
  end if;
  if (select status from app.users where id = v_new_admin_user.id) <> v_pre_status then
    raise exception 'HRT-295 Tier C REGRESSION: expected the linked Platform user''s own status genuinely UNCHANGED after a rejected last_critical_admin suspension (atomic rollback)';
  end if;

  -- Positive control: re-grant a second tenant_admin (the original,
  -- restoring hygiene for anything downstream that might rely on it too),
  -- and confirm termination now succeeds normally once this employee is no
  -- longer the LAST one.
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027101', 'tenant_admin', v_tenant1, null, 'tester');
  v_active := app.terminate_employee(v_active.master_record_id, v_active.record_version, 'resignation, no longer the last critical admin', current_date, v_override_manager, 'override_manager');
  if v_active.lifecycle_status <> 'terminated' then
    raise exception 'assertion failed: expected termination to succeed once a second active tenant_admin exists, got %', v_active.lifecycle_status;
  end if;
  if (select status from app.users where id = v_new_admin_user.id) <> 'revoked' then
    raise exception 'assertion failed: expected the linked Platform user to be genuinely revoked once termination succeeds';
  end if;

  raise notice 'PASS: last_critical_admin correctly blocks both app.terminate_employee and app.suspend_employee against a tenant''s last active tenant_admin, with a genuine atomic rollback both times, and a normal termination succeeds once a second admin exists';
end;
$$;

-- ISS-2026-271 (Step 16 historical-issue-backlog remediation): app.rollback_employee_
-- import_job -- a real, governed rollback for a completed import, closing both residues
-- the entry's own manual-drill reproduction found (a dangling app.audit_logs reference;
-- an untouched, but deliberately never-reused, employee-number counter), and proving the
-- entry's own unexercised downstream-reference risk is correctly handled by Postgres's
-- own default FK enforcement rather than silently orphaning or cascade-deleting anything.
\echo '>> ISS-2026-271 regression: app.rollback_employee_import_job -- HRS:Import-gated, refuses a non-completed job and an empty reason, deletes the job''s own employee/master_record/lifecycle-event/staging rows while leaving the job row itself (now status=rolled_back) and app.employee_number_counters untouched, records a real audit event, and refuses cleanly (never partially) when a created employee has a real downstream reference'
do $$
declare
  v_tenant1 uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000027102';
  v_viewer uuid := '00000000-0000-0000-0000-000000027105';
  v_source_file app.files;
  v_job app.jobs;
  v_row1 app.import_staging_rows;
  v_row2 app.import_staging_rows;
  v_committed app.jobs;
  v_rolled_back app.jobs;
  v_employee1_id uuid;
  v_employee2_id uuid;
  v_counter_before integer;
  v_counter_after integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'hrmemp1');

  v_source_file := app.initiate_file_upload(v_tenant1, 'employee_document', 'import_job', gen_random_uuid(), 'rollback-employees.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-empimport-rollback-source-1', v_staff, 'staff');
  perform app.record_file_scan_result(v_source_file.id, 'clean', null, v_staff, 'staff');

  v_job := app.create_import_export_job(v_tenant1, 'import', 'employee_import', v_source_file.id, '{}'::jsonb, 'idem-empimport-rollback-job-1', v_staff, 'staff');

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'full_name', 'Rollback Test Employee One', 'employment_type', 'full_time', 'work_email', 'rollback-one@hrmemp1.test'
  )), v_staff, 'staff');
  select * into v_row1 from app.import_staging_rows where job_id = v_job.job_id and row_number = 1;

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'full_name', 'Rollback Test Employee Two', 'employment_type', 'full_time', 'work_email', 'rollback-two@hrmemp1.test'
  )), v_staff, 'staff');
  select * into v_row2 from app.import_staging_rows where job_id = v_job.job_id and row_number = 2;

  perform app.validate_employee_import_row(v_row1.id, v_staff, 'staff');
  perform app.validate_employee_import_row(v_row2.id, v_staff, 'staff');

  -- Rejected before the job is even committed: only a completed job may be rolled back.
  begin
    perform app.rollback_employee_import_job(v_job.job_id, 'too early', v_staff, 'staff');
    raise exception 'assertion failed: expected rollback of an in_progress (not yet committed) job to be rejected';
  exception
    when others then
      if sqlerrm not like 'import_export_job_not_rollbackable%' then raise; end if;
  end;

  v_committed := app.commit_employee_import_job(v_job.job_id, false, v_staff, 'staff');
  if v_committed.status <> 'completed' then
    raise exception 'assertion failed: expected the rollback-fixture job to commit cleanly, got status=%', v_committed.status;
  end if;

  select master_record_id into v_employee1_id from app.employees where tenant_id = v_tenant1 and work_email = 'rollback-one@hrmemp1.test';
  select master_record_id into v_employee2_id from app.employees where tenant_id = v_tenant1 and work_email = 'rollback-two@hrmemp1.test';
  if v_employee1_id is null or v_employee2_id is null then
    raise exception 'assertion failed: expected both rollback-fixture employees to exist after commit';
  end if;

  select last_seq into v_counter_before from app.employee_number_counters where tenant_id = v_tenant1;

  -- A viewer (HRS:View only, no HRS:Import) is denied.
  begin
    perform app.rollback_employee_import_job(v_job.job_id, 'unauthorized attempt', v_viewer, 'viewer');
    raise exception 'assertion failed: expected a viewer (no HRS:Import) to be denied';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- A blank reason is rejected.
  begin
    perform app.rollback_employee_import_job(v_job.job_id, '   ', v_staff, 'staff');
    raise exception 'assertion failed: expected a blank rollback reason to be rejected';
  exception
    when others then
      if sqlerrm not like 'employee_import_rollback_reason_required%' then raise; end if;
  end;

  -- The real downstream-reference risk this entry itself flagged as unexercised: link
  -- employee 1 as a duplicate candidate of employee 2 (a genuine, minimal downstream
  -- reference into app.employees, the same default-RESTRICT FK shape every real
  -- downstream domain -- payroll, position assignment, attendance -- also uses). The
  -- rollback must refuse cleanly, and NEITHER employee may be partially deleted.
  insert into app.employee_duplicate_candidates (tenant_id, source_master_record_id, candidate_master_record_id, similarity_basis, created_by)
  values (v_tenant1, v_employee1_id, v_employee2_id, 'ISS-2026-271 regression fixture', 'tester');

  begin
    perform app.rollback_employee_import_job(v_job.job_id, 'blocked by downstream reference', v_staff, 'staff');
    raise exception 'assertion failed: expected rollback to be refused while a real downstream reference exists';
  exception
    when others then
      if sqlerrm not like 'employee_import_rollback_blocked_by_downstream_references%' then raise; end if;
  end;

  if not exists (select 1 from app.employees where master_record_id in (v_employee1_id, v_employee2_id)) then
    raise exception 'assertion failed: expected BOTH employees to survive a refused rollback (atomic, never a partial delete)';
  end if;
  if (select status from app.jobs where job_id = v_job.job_id) <> 'completed' then
    raise exception 'assertion failed: expected the job to remain status=completed after a refused rollback';
  end if;

  -- Clear the downstream reference, then the identical rollback call succeeds cleanly.
  delete from app.employee_duplicate_candidates where source_master_record_id = v_employee1_id and candidate_master_record_id = v_employee2_id;

  v_rolled_back := app.rollback_employee_import_job(v_job.job_id, 'ISS-2026-271 regression: real rollback', v_staff, 'staff');
  if v_rolled_back.status <> 'rolled_back' or v_rolled_back.error <> 'ISS-2026-271 regression: real rollback' then
    raise exception 'assertion failed: expected status=rolled_back with the given reason recorded on the job row, got status=%, error=%', v_rolled_back.status, v_rolled_back.error;
  end if;

  if exists (select 1 from app.employees where master_record_id in (v_employee1_id, v_employee2_id)) then
    raise exception 'assertion failed: expected both employees to be deleted after a successful rollback';
  end if;
  if exists (select 1 from app.master_records where id in (v_employee1_id, v_employee2_id)) then
    raise exception 'assertion failed: expected both master_records to be deleted after a successful rollback';
  end if;
  if exists (select 1 from app.employee_lifecycle_events where master_record_id in (v_employee1_id, v_employee2_id)) then
    raise exception 'assertion failed: expected all lifecycle events for both employees to be deleted after a successful rollback';
  end if;
  if exists (select 1 from app.import_staging_rows where job_id = v_job.job_id) then
    raise exception 'assertion failed: expected the job''s own staging rows to be deleted after a successful rollback';
  end if;

  -- ISS-2026-271's own first named residue, closed: the job row itself still exists
  -- (never deleted), so this and every other audit_logs row already referencing this
  -- job_id remains resolvable.
  if not exists (select 1 from app.jobs where job_id = v_job.job_id) then
    raise exception 'assertion failed: expected the job row itself to survive rollback (status=rolled_back, never deleted) -- this is what keeps existing audit_logs references resolvable';
  end if;
  if not exists (
    select 1 from app.audit_logs
    where action = 'rollback_employee_import_job' and resource_type = 'app.jobs' and resource_id = v_job.job_id
  ) then
    raise exception 'assertion failed: expected a real, persisted audit_logs event for the rollback itself';
  end if;

  -- ISS-2026-271's own second named residue: deliberately NOT "fixed" by reclaiming the
  -- counter -- app.employee_number_counters is untouched by design (that table''s own
  -- comment: "Never reused"). Proved directly, not merely asserted in a comment.
  select last_seq into v_counter_after from app.employee_number_counters where tenant_id = v_tenant1;
  if v_counter_after is distinct from v_counter_before then
    raise exception 'assertion failed: expected app.employee_number_counters to be completely untouched by rollback (deliberately never reclaimed), got % (was %)', v_counter_after, v_counter_before;
  end if;

  -- An already-rolled-back job cannot be rolled back again.
  begin
    perform app.rollback_employee_import_job(v_job.job_id, 'second attempt', v_staff, 'staff');
    raise exception 'assertion failed: expected rollback of an already-rolled_back job to be rejected';
  exception
    when others then
      if sqlerrm not like 'import_export_job_not_rollbackable%' then raise; end if;
  end;

  raise notice 'ISS-2026-271 proof: app.rollback_employee_import_job is HRS:Import-gated, refuses a non-completed job/blank reason/second rollback attempt, refuses atomically (never partially) when a real downstream reference exists, and on success deletes the job''s own employee/master_record/lifecycle-event/staging rows while leaving the job row (status=rolled_back) and app.employee_number_counters completely untouched, with a real audit event recording the rollback itself';
end;
$$;

\echo '>> ISS-2026-271 regression evidence complete'
