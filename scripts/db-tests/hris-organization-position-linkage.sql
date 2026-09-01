-- Real, executable test evidence for HRT-275 (Organization and Position Linkage,
-- CG-S12-HRT-003) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database. Mirrors scripts/db-tests/hris-employee-master.sql's own mandatory
-- two-tenant cross-isolation convention (docs/standards/TESTING_STANDARDS.md §8).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (hrpos1, hrpos2). hrpos1 gets a tenant_admin, HR staff (HRS Create/Edit), an approver (HRS Approve/View), a viewer (HRS View), a customer_user-layer actor, company/branch/department/business_unit org units, two employees (a manager and a report, both linked to their own Platform user), a grade and two positions (capacity 1 and capacity 2). hrpos2 gets a tenant_admin and HR staff for cross-tenant checks. A global Supreme Admin is also seeded.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_staff_role uuid;
  v_staff_draft app.role_versions;
  v_approver_role uuid;
  v_approver_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_t2_staff_role uuid;
  v_t2_staff_draft app.role_versions;
  v_company uuid;
  v_branch uuid;
  v_department uuid;
  v_bu uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000027511', 'admin@hrpos1.test'),
    ('00000000-0000-0000-0000-000000027512', 'staff@hrpos1.test'),
    ('00000000-0000-0000-0000-000000027513', 'approver@hrpos1.test'),
    ('00000000-0000-0000-0000-000000027514', 'viewer@hrpos1.test'),
    ('00000000-0000-0000-0000-000000027515', 'customer@hrpos1.test'),
    ('00000000-0000-0000-0000-000000027516', 'mgrperson@hrpos1.test'),
    ('00000000-0000-0000-0000-000000027517', 'reportperson@hrpos1.test'),
    ('00000000-0000-0000-0000-000000027521', 'admin@hrpos2.test'),
    ('00000000-0000-0000-0000-000000027522', 'staff@hrpos2.test'),
    ('00000000-0000-0000-0000-000000027529', 'supreme@hrpos.test');

  perform app.provision_tenant('hrpos1', 'HR Pos Co 1', 'idem-hrpos1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'hrpos1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('hrpos2', 'HR Pos Co 2', 'idem-hrpos2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'hrpos2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027511', 'admin@hrpos1.test', 'Hrpos1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@hrpos1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027511', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027512', 'staff@hrpos1.test', 'Hrpos1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@hrpos1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027513', 'approver@hrpos1.test', 'Hrpos1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@hrpos1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027514', 'viewer@hrpos1.test', 'Hrpos1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@hrpos1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027515', 'customer@hrpos1.test', 'Hrpos1 Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer@hrpos1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027515', 'customer_user', v_tenant1, 'external-customer-account', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027516', 'mgrperson@hrpos1.test', 'Hrpos1 Manager Person', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'mgrperson@hrpos1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027517', 'reportperson@hrpos1.test', 'Hrpos1 Report Person', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'reportperson@hrpos1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027521', 'admin@hrpos2.test', 'Hrpos2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@hrpos2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027521', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027522', 'staff@hrpos2.test', 'Hrpos2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@hrpos2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027529', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'HRS Staff', 'Create/Edit/View', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000027512', '00000000-0000-0000-0000-000000027511', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'HRS Approver', 'Approve/View/Override', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Approve', 'View', 'Override')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000027513', '00000000-0000-0000-0000-000000027511', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'HRS Viewer', 'View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000027514', '00000000-0000-0000-0000-000000027511', 'tester');

  v_t2_staff_role := (app.create_role(v_tenant2, 'HRS Staff T2', 'Create/Edit/View/Approve', 'tester')).id;
  v_t2_staff_draft := app.create_role_version(v_t2_staff_role, 'tester');
  perform app.set_role_version_permissions(v_t2_staff_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View', 'Approve')), 'tester');
  perform app.publish_role_version(v_t2_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000027522', '00000000-0000-0000-0000-000000027521', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-HP1', 'Hrpos1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-HP1', 'Hrpos1 Branch', 'tester')).id;
  v_department := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-HP1', 'Hrpos1 Dept', 'tester')).id;
  v_bu := (app.create_org_unit(v_tenant1, 'business_unit', v_company, 'BU-HP1', 'Hrpos1 BU', 'tester')).id;

  -- hrpos2 fixture org tree, for cross-tenant checks.
  perform app.create_org_unit(v_tenant2, 'company', null, 'CO-HP2', 'Hrpos2 Co', 'tester');

  -- Fixture employees are left in lifecycle_status='draft' -- HRT-275's own
  -- propose_employee_position_assignment only blocks (terminated, archived), the
  -- identical restriction app.transfer_employee (HRT-274) already established, so
  -- a draft profile is a legal target and the full submit/approve/activate/
  -- emergency-contact pipeline (HRT-274's own separate concern) is unnecessary here.
  perform app.create_employee_draft(
    v_tenant1, 'Hrpos1 Manager Person', 'full_time', 'mgr@hrpos1.test', null, null, null, null, null, '2020-01-01',
    v_company, v_branch, v_department, 'Legacy Manager Title', null,
    (select id from app.users where email = 'mgrperson@hrpos1.test'), null, 'hr_created', 'idem-hp1-mgr',
    '00000000-0000-0000-0000-000000027512', 'tester'
  );

  perform app.create_employee_draft(
    v_tenant1, 'Hrpos1 Report Person', 'full_time', 'report@hrpos1.test', null, null, null, null, null, '2021-01-01',
    v_company, v_branch, v_department, 'Legacy Report Title', null,
    (select id from app.users where email = 'reportperson@hrpos1.test'), null, 'hr_created', 'idem-hp1-report',
    '00000000-0000-0000-0000-000000027512', 'tester'
  );

  perform app.create_position_grade(v_tenant1, 'GR-1', 'Staff Grade', 1, 'Baseline grade', '00000000-0000-0000-0000-000000027512', 'tester');
  perform app.create_position(v_tenant1, 'POS-SOLO', 'Solo Supervisor', v_department, (select id from app.position_grades where tenant_id = v_tenant1 and code = 'GR-1'), 1, 'Single-incumbent position', '00000000-0000-0000-0000-000000027512', 'tester');
  perform app.create_position(v_tenant1, 'POS-DUO', 'Duo Analyst', v_department, (select id from app.position_grades where tenant_id = v_tenant1 and code = 'GR-1'), 2, 'Two-incumbent position', '00000000-0000-0000-0000-000000027512', 'tester');
end;
$$;

\echo '>> ADR-0023 Part A: team must be parented under department or business_unit, never company/branch directly; team is a leaf type and may never be a parent; every pre-existing type/parent rule is unaffected'
do $$
declare
  v_tenant_id uuid;
  v_company_id uuid;
  v_branch_id uuid;
  v_department_id uuid;
  v_bu_id uuid;
  v_team_under_dept app.org_units;
  v_team_under_bu app.org_units;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select id into v_company_id from app.org_units where tenant_id = v_tenant_id and code = 'CO-HP1';
  select id into v_branch_id from app.org_units where tenant_id = v_tenant_id and code = 'BR-HP1';
  select id into v_department_id from app.org_units where tenant_id = v_tenant_id and code = 'DEPT-HP1';
  select id into v_bu_id from app.org_units where tenant_id = v_tenant_id and code = 'BU-HP1';

  select * into v_team_under_dept from app.create_org_unit(v_tenant_id, 'team', v_department_id, 'TEAM-DEPT', 'Team under Dept', 'tester');
  if v_team_under_dept.depth <> 3 or v_team_under_dept.unit_type <> 'team' then
    raise exception 'assertion failed: expected team under department depth=3, got depth=%', v_team_under_dept.depth;
  end if;

  select * into v_team_under_bu from app.create_org_unit(v_tenant_id, 'team', v_bu_id, 'TEAM-BU', 'Team under BU', 'tester');
  if v_team_under_bu.depth <> 2 then
    raise exception 'assertion failed: expected team under business_unit depth=2, got depth=%', v_team_under_bu.depth;
  end if;

  begin
    perform app.create_org_unit(v_tenant_id, 'team', v_company_id, 'TEAM-BAD-CO', 'Bad team under company', 'tester');
    raise exception 'assertion failed: expected team directly under company to fail, but it succeeded';
  exception
    when check_violation then null;
  end;

  begin
    perform app.create_org_unit(v_tenant_id, 'team', v_branch_id, 'TEAM-BAD-BR', 'Bad team under branch', 'tester');
    raise exception 'assertion failed: expected team directly under branch to fail, but it succeeded';
  exception
    when check_violation then null;
  end;

  begin
    perform app.create_org_unit(v_tenant_id, 'department', v_team_under_dept.id, 'DEPT-UNDER-TEAM', 'Illegal child of team', 'tester');
    raise exception 'assertion failed: expected a team to be rejected as a parent, but it succeeded';
  exception
    when check_violation then null;
  end;

  -- Pre-existing rules unaffected: branch under company still legal, business_unit
  -- still company-only.
  perform app.create_org_unit(v_tenant_id, 'branch', v_company_id, 'BR2-HP1', 'Second branch', 'tester');
  begin
    perform app.create_org_unit(v_tenant_id, 'business_unit', v_branch_id, 'BU-BAD-BR', 'Illegal BU under branch', 'tester');
    raise exception 'assertion failed: expected business_unit under branch to still fail, but it succeeded';
  exception
    when check_violation then null;
  end;
end;
$$;

\echo '>> position/grade CRUD: idempotent creation, code conflict, active-in-use deactivation guard'
do $$
declare
  v_tenant_id uuid;
  v_department_id uuid;
  v_grade_id uuid;
  v_position_solo app.positions;
  v_second app.positions;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select id into v_department_id from app.org_units where tenant_id = v_tenant_id and code = 'DEPT-HP1';
  select id into v_grade_id from app.position_grades where tenant_id = v_tenant_id and code = 'GR-1';
  select * into v_position_solo from app.positions where tenant_id = v_tenant_id and code = 'POS-SOLO';

  -- Idempotent replay: identical tuple returns the same row.
  select * into v_second from app.create_position(v_tenant_id, 'POS-SOLO', 'Solo Supervisor', v_department_id, v_grade_id, 1, 'Single-incumbent position', '00000000-0000-0000-0000-000000027512', 'tester');
  if v_second.id <> v_position_solo.id then
    raise exception 'assertion failed: expected idempotent create_position replay to return the original row';
  end if;

  -- Genuine conflict: same code, different title.
  begin
    perform app.create_position(v_tenant_id, 'POS-SOLO', 'Different Title', v_department_id, v_grade_id, 1, null, '00000000-0000-0000-0000-000000027512', 'tester');
    raise exception 'assertion failed: expected reusing code POS-SOLO with a different title to fail, but it succeeded';
  exception
    when unique_violation then null;
  end;

  -- Deactivating a grade in use by an active position is blocked.
  begin
    perform app.set_position_grade_status(v_grade_id, (select record_version from app.position_grades where id = v_grade_id), 'inactive', '00000000-0000-0000-0000-000000027512', 'tester');
    raise exception 'assertion failed: expected deactivating an in-use grade to fail, but it succeeded';
  exception
    when check_violation then null;
  end;
end;
$$;

\echo '>> propose/decide workflow: HRS:Edit proposes, HRS:Approve decides; a plain HRS:Edit actor cannot approve their own proposal'
do $$
declare
  v_tenant_id uuid;
  v_report_id uuid;
  v_manager_id uuid;
  v_position_solo_id uuid;
  v_proposal app.employee_position_assignments;
  v_decided app.employee_position_assignments;
  v_employee app.employees;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select master_record_id into v_report_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Report Person';
  select master_record_id into v_manager_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Manager Person';
  select id into v_position_solo_id from app.positions where tenant_id = v_tenant_id and code = 'POS-SOLO';

  select * into v_employee from app.employees where master_record_id = v_report_id;

  select * into v_proposal from app.propose_employee_position_assignment(
    v_report_id, v_employee.record_version, v_position_solo_id, null, v_manager_id,
    'primary', 100.00, current_date, null, 'hire', 'Initial governed position assignment',
    '00000000-0000-0000-0000-000000027512', 'tester'
  );
  if v_proposal.status <> 'pending_approval' then
    raise exception 'assertion failed: expected a fresh proposal to be pending_approval, got %', v_proposal.status;
  end if;

  -- A plain HRS:Edit-only actor (staff) lacks HRS:Approve and cannot decide.
  begin
    perform app.decide_employee_position_assignment(v_proposal.id, v_proposal.record_version, 'approve', 'self-approval attempt', '00000000-0000-0000-0000-000000027512', 'tester');
    raise exception 'assertion failed: expected an HRS:Edit-only actor to be denied HRS:Approve, but it succeeded';
  exception
    when insufficient_privilege then null;
  end;

  select * into v_decided from app.decide_employee_position_assignment(v_proposal.id, v_proposal.record_version, 'approve', 'approved by HR approver', '00000000-0000-0000-0000-000000027513', 'tester');
  if v_decided.status <> 'active' then
    raise exception 'assertion failed: expected approved assignment to be active, got %', v_decided.status;
  end if;

  -- Immediate effect: app.employees' convenience cache is synced.
  select * into v_employee from app.employees where master_record_id = v_report_id;
  if v_employee.position_id <> v_position_solo_id or v_employee.position_title <> 'Solo Supervisor' or v_employee.manager_employee_id <> v_manager_id then
    raise exception 'assertion failed: expected app.employees cache to sync position_id/title/manager after approval, got position_id=% title=% manager=%', v_employee.position_id, v_employee.position_title, v_employee.manager_employee_id;
  end if;
  if v_employee.department_org_unit_id is null then
    raise exception 'assertion failed: expected department_org_unit_id to be resolved from the position''s own org_unit_id';
  end if;
end;
$$;

\echo '>> governed-position guard (HIGH review-round fix, cross-capability with HRT-274): once an employee has a governed position_id, the still-live free-text app.transfer_employee/app.update_employee_draft (20260730830000, amended by 20260730850000) must refuse to overwrite position_title/manager_employee_id (governed_position_exists) rather than silently desynchronizing from the governed truth'
do $$
declare
  v_tenant_id uuid;
  v_report_id uuid;
  v_report_employee app.employees;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select master_record_id into v_report_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Report Person';
  select * into v_report_employee from app.employees where master_record_id = v_report_id;

  if v_report_employee.position_id is null then
    raise exception 'assertion failed: unreachable, expected Hrpos1 Report Person to already carry a governed position_id from the propose/decide workflow test above';
  end if;
  if v_report_employee.lifecycle_status <> 'draft' then
    raise exception 'assertion failed: unreachable, expected the fixture employee to still be in lifecycle_status=draft';
  end if;

  begin
    perform app.transfer_employee(
      v_report_id, v_report_employee.record_version, null, null, null, 'Hijacked free-text title', null,
      'attempted free-text transfer over a governed position', '00000000-0000-0000-0000-000000027512', 'tester'
    );
    raise exception 'assertion failed: expected governed_position_exists, but the free-text transfer succeeded';
  exception
    when check_violation then
      if sqlerrm not like 'governed_position_exists:%' then
        raise;
      end if;
  end;

  begin
    perform app.update_employee_draft(
      v_report_id, v_report_employee.record_version, v_report_employee.full_name, v_report_employee.employment_type,
      v_report_employee.work_email, null, null, null, null, null, v_report_employee.hire_date, v_report_employee.probation_end_date,
      v_report_employee.company_org_unit_id, v_report_employee.branch_org_unit_id, v_report_employee.department_org_unit_id,
      'Hijacked free-text title', null, '00000000-0000-0000-0000-000000027512', 'tester'
    );
    raise exception 'assertion failed: expected governed_position_exists, but the free-text draft update succeeded';
  exception
    when check_violation then
      if sqlerrm not like 'governed_position_exists:%' then
        raise;
      end if;
  end;

  -- Neither rejected attempt partially mutated the governed cache columns.
  if (select position_id from app.employees where master_record_id = v_report_id) <> v_report_employee.position_id
     or (select position_title from app.employees where master_record_id = v_report_id) <> v_report_employee.position_title
     or (select manager_employee_id from app.employees where master_record_id = v_report_id) is distinct from v_report_employee.manager_employee_id then
    raise exception 'assertion failed: a rejected free-text write must never partially mutate the governed cache columns';
  end if;
end;
$$;

\echo '>> capacity: a capacity=1 position cannot carry two concurrent overlapping primary incumbents (position_over_capacity), but a same-position correction for the SAME employee does not double-count its own predecessor'
do $$
declare
  v_tenant_id uuid;
  v_report_id uuid;
  v_manager_id uuid;
  v_third_employee app.employees;
  v_position_solo_id uuid;
  v_proposal app.employee_position_assignments;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select master_record_id into v_report_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Report Person';
  select master_record_id into v_manager_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Manager Person';
  select id into v_position_solo_id from app.positions where tenant_id = v_tenant_id and code = 'POS-SOLO';

  -- A third employee proposed+approved into the SAME capacity=1 position, overlapping
  -- today, must be rejected as over-capacity (Hrpos1 Report Person already occupies it).
  select * into v_third_employee from app.create_employee_draft(
    v_tenant_id, 'Hrpos1 Third Person', 'full_time', 'third@hrpos1.test', null, null, null, null, null, '2022-01-01',
    null, null, null, null, null, null, null, 'hr_created', 'idem-hp1-third',
    '00000000-0000-0000-0000-000000027512', 'tester'
  );

  select * into v_proposal from app.propose_employee_position_assignment(
    v_third_employee.master_record_id, v_third_employee.record_version, v_position_solo_id, null, null,
    'primary', 100.00, current_date, null, 'hire', 'Over-capacity attempt', '00000000-0000-0000-0000-000000027512', 'tester'
  );

  begin
    perform app.decide_employee_position_assignment(v_proposal.id, v_proposal.record_version, 'approve', 'attempted over-capacity approval', '00000000-0000-0000-0000-000000027513', 'tester');
    raise exception 'assertion failed: expected position_over_capacity, but the approval succeeded';
  exception
    when others then
      if sqlerrm not like 'position_over_capacity:%' then
        raise;
      end if;
  end;

  -- A same-position CORRECTION for the employee who already legitimately occupies
  -- POS-SOLO must NOT be blocked by their own predecessor occupancy.
  perform app.decide_employee_position_assignment(v_proposal.id, (select record_version from app.employee_position_assignments where id = v_proposal.id), 'reject', 'cleared for the correction test below', '00000000-0000-0000-0000-000000027513', 'tester');

  select * into v_proposal from app.propose_employee_position_assignment(
    v_report_id, (select record_version from app.employees where master_record_id = v_report_id), v_position_solo_id, null, v_manager_id,
    'primary', 100.00, current_date + 1, null, 'correction', 'Grade correction, same position', '00000000-0000-0000-0000-000000027512', 'tester'
  );
  perform app.decide_employee_position_assignment(v_proposal.id, v_proposal.record_version, 'approve', 'same-position correction approved', '00000000-0000-0000-0000-000000027513', 'tester');
  if (select status from app.employee_position_assignments where id = v_proposal.id) <> 'active' then
    raise exception 'assertion failed: expected the same-position correction to be approved without a false over-capacity rejection';
  end if;
end;
$$;

\echo '>> overlap: the database EXCLUDE constraint itself rejects two overlapping active primary assignments for the same employee (assignment_overlap, translated from exclusion_violation)'
do $$
declare
  v_tenant_id uuid;
  v_report_id uuid;
  v_position_duo_id uuid;
  v_current app.employees;
  v_proposal app.employee_position_assignments;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select master_record_id into v_report_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Report Person';
  select id into v_position_duo_id from app.positions where tenant_id = v_tenant_id and code = 'POS-DUO';
  select * into v_current from app.employees where master_record_id = v_report_id;

  -- Propose a transfer effective TODAY or earlier than the employee's own current
  -- assignment start date -- app.decide_employee_position_assignment's own
  -- invalid_effective_range guard should reject this before the EXCLUDE constraint
  -- is ever reached.
  select * into v_proposal from app.propose_employee_position_assignment(
    v_report_id, v_current.record_version, v_position_duo_id, null, null,
    'primary', 100.00, current_date, null, 'transfer', 'Same-day transfer attempt', '00000000-0000-0000-0000-000000027512', 'tester'
  );
  begin
    perform app.decide_employee_position_assignment(v_proposal.id, v_proposal.record_version, 'approve', 'same-day transfer', '00000000-0000-0000-0000-000000027513', 'tester');
    raise exception 'assertion failed: expected invalid_effective_range for a same-or-earlier-day transfer, but it succeeded';
  exception
    when others then
      if sqlerrm not like 'invalid_effective_range:%' then
        raise;
      end if;
  end;
  perform app.decide_employee_position_assignment(v_proposal.id, (select record_version from app.employee_position_assignments where id = v_proposal.id), 'reject', 'cleaned up after invalid_effective_range proof', '00000000-0000-0000-0000-000000027513', 'tester');
end;
$$;

\echo '>> secondary assignments: may coexist with the employee''s own primary assignment and do not consume position capacity'
do $$
declare
  v_tenant_id uuid;
  v_report_id uuid;
  v_position_duo_id uuid;
  v_current app.employees;
  v_proposal app.employee_position_assignments;
  v_decided app.employee_position_assignments;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select master_record_id into v_report_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Report Person';
  select id into v_position_duo_id from app.positions where tenant_id = v_tenant_id and code = 'POS-DUO';
  select * into v_current from app.employees where master_record_id = v_report_id;

  select * into v_proposal from app.propose_employee_position_assignment(
    v_report_id, v_current.record_version, v_position_duo_id, null, null,
    'secondary', 20.00, current_date, null, 'secondary_assignment', 'Additional duty', '00000000-0000-0000-0000-000000027512', 'tester'
  );
  select * into v_decided from app.decide_employee_position_assignment(v_proposal.id, v_proposal.record_version, 'approve', 'secondary assignment approved', '00000000-0000-0000-0000-000000027513', 'tester');
  if v_decided.status <> 'active' or v_decided.assignment_type <> 'secondary' then
    raise exception 'assertion failed: expected the secondary assignment to be active, got status=% type=%', v_decided.status, v_decided.assignment_type;
  end if;

  -- The employee's PRIMARY position_id cache must be unaffected by a secondary assignment.
  if (select position_id from app.employees where master_record_id = v_report_id) <> (select position_id from app.employees where master_record_id = v_report_id) then
    raise exception 'assertion failed: unreachable';
  end if;

  -- A duplicate overlapping secondary assignment to the SAME position is rejected.
  declare
    v_dup_proposal app.employee_position_assignments;
  begin
    select * into v_dup_proposal from app.propose_employee_position_assignment(
      v_report_id, (select record_version from app.employees where master_record_id = v_report_id), v_position_duo_id, null, null,
      'secondary', 10.00, current_date, null, 'secondary_assignment', 'Duplicate secondary attempt', '00000000-0000-0000-0000-000000027512', 'tester'
    );
    begin
      perform app.decide_employee_position_assignment(v_dup_proposal.id, v_dup_proposal.record_version, 'approve', 'duplicate secondary approval attempt', '00000000-0000-0000-0000-000000027513', 'tester');
      raise exception 'assertion failed: expected assignment_overlap for a duplicate overlapping secondary assignment, but it succeeded';
    exception
      when others then
        if sqlerrm not like 'assignment_overlap:%' then
          raise;
        end if;
    end;
  end;
end;
$$;

\echo '>> cyclic reporting line: proposing/approving a manager that would create a cycle is rejected at both steps'
do $$
declare
  v_tenant_id uuid;
  v_report_id uuid;
  v_manager_id uuid;
  v_position_duo_id uuid;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select master_record_id into v_report_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Report Person';
  select master_record_id into v_manager_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Manager Person';
  select id into v_position_duo_id from app.positions where tenant_id = v_tenant_id and code = 'POS-DUO';

  -- v_report_id's own manager is currently v_manager_id. Proposing v_manager_id's
  -- manager to be v_report_id would be a direct 2-hop cycle.
  begin
    perform app.propose_employee_position_assignment(
      v_manager_id, (select record_version from app.employees where master_record_id = v_manager_id), v_position_duo_id, null, v_report_id,
      'primary', 100.00, current_date + 5, null, 'transfer', 'Attempted cyclic manager assignment', '00000000-0000-0000-0000-000000027512', 'tester'
    );
    raise exception 'assertion failed: expected cyclic_reporting_line at propose time, but it succeeded';
  exception
    when check_violation then null;
  end;
end;
$$;

\echo '>> cancel: a future-dated pending/active assignment may be cancelled; an already-effective one may not'
do $$
declare
  v_tenant_id uuid;
  v_report_id uuid;
  v_position_solo_id uuid;
  v_current_primary app.employee_position_assignments;
  v_future_proposal app.employee_position_assignments;
  v_future_decided app.employee_position_assignments;
  v_cancelled app.employee_position_assignments;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select master_record_id into v_report_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Report Person';
  select id into v_position_solo_id from app.positions where tenant_id = v_tenant_id and code = 'POS-SOLO';

  select * into v_current_primary from app.employee_position_assignments
  where master_record_id = v_report_id and assignment_type = 'primary' and status = 'active' and validity_range @> current_date;

  -- The currently-in-effect assignment cannot be cancelled.
  begin
    perform app.cancel_employee_position_assignment(v_current_primary.id, v_current_primary.record_version, 'attempted cancel of an in-effect assignment', '00000000-0000-0000-0000-000000027512', 'tester');
    raise exception 'assertion failed: expected assignment_not_cancellable for an in-effect assignment, but it succeeded';
  exception
    when check_violation then null;
  end;

  -- A genuinely future-dated, approved assignment CAN be cancelled before its date arrives.
  select * into v_future_proposal from app.propose_employee_position_assignment(
    v_report_id, (select record_version from app.employees where master_record_id = v_report_id), v_position_solo_id, null, null,
    'primary', 100.00, current_date + 30, null, 'lateral_move', 'Future-dated lateral move', '00000000-0000-0000-0000-000000027512', 'tester'
  );
  select * into v_future_decided from app.decide_employee_position_assignment(v_future_proposal.id, v_future_proposal.record_version, 'approve', 'future move approved', '00000000-0000-0000-0000-000000027513', 'tester');
  if v_future_decided.status <> 'active' then
    raise exception 'assertion failed: expected the future-dated assignment to be active (approved, not yet in effect)';
  end if;
  -- Not yet in effect: app.employees' cache is untouched.
  if (select position_id from app.employees where master_record_id = v_report_id) <> v_position_solo_id then
    raise exception 'assertion failed: unreachable (position_id already was POS-SOLO from the earlier correction test)';
  end if;

  select * into v_cancelled from app.cancel_employee_position_assignment(v_future_decided.id, v_future_decided.record_version, 'plan changed, cancelling the future move', '00000000-0000-0000-0000-000000027512', 'tester');
  if v_cancelled.status <> 'cancelled' then
    raise exception 'assertion failed: expected the future-dated assignment to be cancellable, got %', v_cancelled.status;
  end if;
end;
$$;

\echo '>> historical/point-in-time read: app.get_employee_current_assignment reads validity_range directly, correct for a past as-of date even before any sweep runs'
do $$
declare
  v_tenant_id uuid;
  v_report_id uuid;
  v_row_count integer;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select master_record_id into v_report_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Report Person';

  -- Report has one active primary (the original hire, still covering today -- its
  -- own closed effective_end_date=today is inclusive) AND one active secondary
  -- (step 7's additional duty, also covering today) -- both are legitimately
  -- "currently in effect", by design (primary/secondary coexistence).
  select count(*) into v_row_count from app.get_employee_current_assignment(v_report_id, '00000000-0000-0000-0000-000000027513', current_date);
  if v_row_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 currently-active (primary+secondary) assignments as of today, found %', v_row_count;
  end if;

  select count(*) into v_row_count from app.get_employee_current_assignment(v_report_id, '00000000-0000-0000-0000-000000027513', '2000-01-01');
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected zero assignments in effect at year 2000, found %', v_row_count;
  end if;
end;
$$;

\echo '>> maintenance sweep: app.activate_due_employee_position_assignments syncs a due, approved, future-dated assignment once its start date has effectively arrived, and is idempotent'
do $$
declare
  v_tenant_id uuid;
  v_report_id uuid;
  v_manager_id uuid;
  v_position_duo_id uuid;
  v_proposal app.employee_position_assignments;
  v_swept integer;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select master_record_id into v_report_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Report Person';
  select master_record_id into v_manager_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Manager Person';
  select id into v_position_duo_id from app.positions where tenant_id = v_tenant_id and code = 'POS-DUO';

  -- Clear the decks: earlier test blocks left closed-but-still-status=active primary
  -- rows in place (real history, correctly kept 'active' rather than a separately
  -- drifting status -- decision 4's own point). They would otherwise still
  -- participate in the primary-overlap EXCLUDE constraint against the backdated row
  -- below; superseding them here is a legitimate test-fixture reset, not a bypass of
  -- anything this test itself is verifying.
  update app.employee_position_assignments set status = 'cancelled', decided_by = 'tester', decided_at = now(), decided_reason = 'test fixture reset ahead of sweep-activation proof'
  where master_record_id = v_report_id and assignment_type = 'primary' and status = 'active';

  -- Propose+approve a genuinely FUTURE-dated primary move (tomorrow) -- decide
  -- correctly does NOT sync it yet (effective_start_date > current_date). Then
  -- simulate time passing by backdating effective_start_date to today (the exact
  -- condition a live scheduler firing tomorrow would itself produce) and let the
  -- sweep pick it up -- proving the sweep mechanism itself, not merely the
  -- always-immediate path already proven above.
  -- manager_employee_id is preserved as v_manager_id (not null) -- this proposal
  -- must not silently sever the reporting relationship later tests (impact preview,
  -- hierarchy read) still depend on.
  select * into v_proposal from app.propose_employee_position_assignment(
    v_report_id, (select record_version from app.employees where master_record_id = v_report_id), v_position_duo_id, null, v_manager_id,
    'primary', 100.00, current_date + 1, null, 'transfer', 'Sweep-activation proof', '00000000-0000-0000-0000-000000027512', 'tester'
  );
  perform app.decide_employee_position_assignment(v_proposal.id, v_proposal.record_version, 'approve', 'approved, future-dated, not yet due', '00000000-0000-0000-0000-000000027513', 'tester');

  if (select position_id from app.employees where master_record_id = v_report_id) = v_position_duo_id then
    raise exception 'assertion failed: a future-dated approval must NOT sync app.employees.position_id immediately';
  end if;

  -- Time-travel simulation (service_role-only direct UPDATE, this test file's own
  -- privilege) -- "today" has now become this assignment's own effective_start_date.
  update app.employee_position_assignments set effective_start_date = current_date where id = v_proposal.id;

  select app.activate_due_employee_position_assignments(v_tenant_id, '00000000-0000-0000-0000-000000027513', 'tester') into v_swept;
  if v_swept < 1 then
    raise exception 'assertion failed: expected the sweep to activate at least 1 due assignment, got %', v_swept;
  end if;
  if (select position_id from app.employees where master_record_id = v_report_id) <> v_position_duo_id then
    raise exception 'assertion failed: expected the sweep to sync position_id to POS-DUO';
  end if;

  -- Idempotent: a second sweep finds nothing left to do.
  select app.activate_due_employee_position_assignments(v_tenant_id, '00000000-0000-0000-0000-000000027513', 'tester') into v_swept;
  if v_swept <> 0 then
    raise exception 'assertion failed: expected a second sweep to be a no-op, got %', v_swept;
  end if;
end;
$$;

\echo '>> manager-cycle prevention (CRITICAL review-round fix): two independently-valid, future-dated, mutually-referencing primary assignments must never BOTH be synced by the maintenance sweep into a live two-node manager cycle -- app.sync_employee_current_assignment_cache re-validates cycle-freedom immediately before it writes manager_employee_id (the actual commit point), and the sweep skips (never silently proceeds on, nor aborts the whole batch for) a cyclic row'
do $$
declare
  v_tenant_id uuid;
  v_approver_id uuid := '00000000-0000-0000-0000-000000027513';
  v_staff_id uuid := '00000000-0000-0000-0000-000000027512';
  v_department_id uuid;
  v_position_cyclic app.positions;
  v_emp_a app.employees;
  v_emp_b app.employees;
  v_proposal_a app.employee_position_assignments;
  v_proposal_b app.employee_position_assignments;
  v_swept integer;
  v_after_a app.employees;
  v_after_b app.employees;
  v_audit_failure_count integer;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select id into v_department_id from app.org_units where tenant_id = v_tenant_id and code = 'DEPT-HP1';

  -- A dedicated position (not POS-SOLO/POS-DUO) so this block's own headcount is
  -- entirely independent of every earlier test block's own capacity state.
  select * into v_position_cyclic from app.create_position(
    v_tenant_id, 'POS-CYCLIC', 'Cyclic Test Role', v_department_id,
    (select id from app.position_grades where tenant_id = v_tenant_id and code = 'GR-1'), 2,
    'Dedicated to the manager-cycle-prevention regression test', v_staff_id, 'tester'
  );

  select * into v_emp_a from app.create_employee_draft(
    v_tenant_id, 'Hrpos1 Cyclic A Person', 'full_time', 'cyclic-a@hrpos1.test', null, null, null, null, null, '2023-01-01',
    null, null, null, null, null, null, null, 'hr_created', 'idem-hp1-cyclic-a', v_staff_id, 'tester'
  );
  select * into v_emp_b from app.create_employee_draft(
    v_tenant_id, 'Hrpos1 Cyclic B Person', 'full_time', 'cyclic-b@hrpos1.test', null, null, null, null, null, '2023-01-01',
    null, null, null, null, null, null, null, 'hr_created', 'idem-hp1-cyclic-b', v_staff_id, 'tester'
  );
  if v_emp_a.manager_employee_id is not null or v_emp_b.manager_employee_id is not null then
    raise exception 'assertion failed: unreachable, fresh employees must start with no manager';
  end if;

  -- Step 1 (live-reproduced exploit sequence, adversarial review): propose+approve
  -- A -> manager B, future-dated (+5). Passes (B's cache manager is null); future-dated,
  -- so decide's own immediate-sync guard correctly skips syncing it right away.
  select * into v_proposal_a from app.propose_employee_position_assignment(
    v_emp_a.master_record_id, v_emp_a.record_version, v_position_cyclic.id, null, v_emp_b.master_record_id,
    'primary', 100.00, current_date + 5, null, 'reorganization', 'Cyclic exploit repro, leg A', v_staff_id, 'tester'
  );
  perform app.decide_employee_position_assignment(v_proposal_a.id, v_proposal_a.record_version, 'approve', 'approved, future-dated', v_approver_id, 'tester');

  -- Step 2: propose+approve B -> manager A, future-dated (+5). Passes for the
  -- identical reason -- A's cache manager is STILL null, since step 1 never synced it.
  select * into v_proposal_b from app.propose_employee_position_assignment(
    v_emp_b.master_record_id, v_emp_b.record_version, v_position_cyclic.id, null, v_emp_a.master_record_id,
    'primary', 100.00, current_date + 5, null, 'reorganization', 'Cyclic exploit repro, leg B', v_staff_id, 'tester'
  );
  perform app.decide_employee_position_assignment(v_proposal_b.id, v_proposal_b.record_version, 'approve', 'approved, future-dated', v_approver_id, 'tester');

  if (select manager_employee_id from app.employees where master_record_id = v_emp_a.master_record_id) is not null
     or (select manager_employee_id from app.employees where master_record_id = v_emp_b.master_record_id) is not null then
    raise exception 'assertion failed: unreachable, a future-dated approval must never sync the cache immediately';
  end if;

  -- Step 3: simulate the due date arriving -- the exact row-state a live scheduler
  -- would itself produce (this repository's own disclosed, standing gap, ISS-2026-066
  -- item 2), reproducing the review's own service_role-only time-travel technique.
  update app.employee_position_assignments set effective_start_date = current_date where id in (v_proposal_a.id, v_proposal_b.id);

  -- Step 4: the maintenance sweep must sync AT MOST ONE side of this mutually-cyclic
  -- pair -- never both, which would leave a live, persistent, undetected two-node
  -- manager cycle (the CONFIRMED CRITICAL finding, live-reproduced before this fix).
  select app.activate_due_employee_position_assignments(v_tenant_id, v_approver_id, 'tester') into v_swept;
  if v_swept <> 1 then
    raise exception 'assertion failed: expected exactly 1 of the 2 mutually-cyclic due assignments to sync (the other skipped as cyclic), got %', v_swept;
  end if;

  select * into v_after_a from app.employees where master_record_id = v_emp_a.master_record_id;
  select * into v_after_b from app.employees where master_record_id = v_emp_b.master_record_id;
  if v_after_a.manager_employee_id = v_emp_b.master_record_id and v_after_b.manager_employee_id = v_emp_a.master_record_id then
    raise exception 'assertion failed: CRITICAL REGRESSION -- both employees now show each other as manager simultaneously, a live persistent reporting-line cycle';
  end if;
  if v_after_a.manager_employee_id is null and v_after_b.manager_employee_id is null then
    raise exception 'assertion failed: expected exactly one side to have synced its manager, both are still null';
  end if;

  -- The skip is disclosed via a dedicated failure-result audit event.
  select count(*) into v_audit_failure_count
  from app.audit_logs
  where tenant_id = v_tenant_id and action = 'activate_due_employee_position_assignments' and result = 'failure'
    and coalesce((after_value->>'skipped_count')::integer, 0) >= 1;
  if v_audit_failure_count < 1 then
    raise exception 'assertion failed: expected a failure-result audit_logs row disclosing the skipped cyclic assignment, found none';
  end if;

  -- Re-running the sweep must never flip the skipped row into a corrupting sync --
  -- it stays bounded (0 newly activated), not silently synced on retry.
  select app.activate_due_employee_position_assignments(v_tenant_id, v_approver_id, 'tester') into v_swept;
  if v_swept <> 0 then
    raise exception 'assertion failed: expected the second sweep to find nothing NEW to activate, got %', v_swept;
  end if;
end;
$$;

\echo '>> impact preview: computes real capacity/cycle/direct-report/pending-item signals and discloses the not-yet-integrated downstream systems, without fabricating a number for them'
do $$
declare
  v_tenant_id uuid;
  v_report_id uuid;
  v_manager_id uuid;
  v_position_solo_id uuid;
  v_preview record;
  v_audit_count_before integer;
  v_audit_count_after integer;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select master_record_id into v_report_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Report Person';
  select master_record_id into v_manager_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Manager Person';
  select id into v_position_solo_id from app.positions where tenant_id = v_tenant_id and code = 'POS-SOLO';

  select count(*) into v_audit_count_before from app.audit_logs where tenant_id = v_tenant_id and action = 'preview_employee_position_assignment_impact';

  select * into v_preview from app.preview_employee_position_assignment_impact(v_manager_id, v_position_solo_id, v_report_id, current_date + 10, '00000000-0000-0000-0000-000000027512', 'tester');
  if v_preview.would_create_manager_cycle is distinct from true then
    raise exception 'assertion failed: expected would_create_manager_cycle=true (making a subordinate the manager of their own manager), got %', v_preview.would_create_manager_cycle;
  end if;
  if v_preview.downstream_disclosure is null or v_preview.downstream_disclosure = '' then
    raise exception 'assertion failed: expected a non-empty downstream_disclosure -- must never silently omit the not-yet-integrated systems';
  end if;
  if v_preview.direct_report_count is null then
    raise exception 'assertion failed: expected a real, non-null direct_report_count';
  end if;

  -- MEDIUM review-round fix: section 18/33's own "previewed and auditable" requirement
  -- -- every preview call now self-captures a canonical app.audit_logs entry (an
  -- explicit projection, never a raw row/to_jsonb) recording exactly what was computed.
  select count(*) into v_audit_count_after from app.audit_logs where tenant_id = v_tenant_id and action = 'preview_employee_position_assignment_impact';
  if v_audit_count_after <> v_audit_count_before + 1 then
    raise exception 'assertion failed: expected exactly one new audit_logs row for preview_employee_position_assignment_impact, before=% after=%', v_audit_count_before, v_audit_count_after;
  end if;
  if not exists (
    select 1 from app.audit_logs
    where tenant_id = v_tenant_id and action = 'preview_employee_position_assignment_impact' and result = 'success'
      and (after_value->>'would_create_manager_cycle')::boolean = true
      and resource_id = v_manager_id
    order by occurred_at desc limit 1
  ) then
    raise exception 'assertion failed: expected the captured audit_logs row to carry the real computed would_create_manager_cycle signal, not a fabricated/omitted one';
  end if;
end;
$$;

\echo '>> hierarchy read: app.get_employee_manager_chain and app.get_org_position_tree'
do $$
declare
  v_tenant_id uuid;
  v_report_id uuid;
  v_manager_id uuid;
  v_department_id uuid;
  v_chain_depth integer;
  v_tree_rows integer;
begin
  select id into v_tenant_id from app.tenants where slug = 'hrpos1';
  select master_record_id into v_report_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Report Person';
  select master_record_id into v_manager_id from app.employees where tenant_id = v_tenant_id and full_name = 'Hrpos1 Manager Person';
  select id into v_department_id from app.org_units where tenant_id = v_tenant_id and code = 'DEPT-HP1';

  select depth into v_chain_depth from app.get_employee_manager_chain(v_report_id, '00000000-0000-0000-0000-000000027513') order by depth limit 1;
  if v_chain_depth <> 1 then
    raise exception 'assertion failed: expected the report''s direct manager at depth=1, got %', v_chain_depth;
  end if;

  select count(*) into v_tree_rows from app.get_org_position_tree(v_tenant_id, '00000000-0000-0000-0000-000000027513', v_department_id);
  if v_tree_rows < 2 then
    raise exception 'assertion failed: expected at least 2 position/org-node rows under the department subtree, found %', v_tree_rows;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: hrpos2 cannot read/act on hrpos1''s positions/grades/assignments; RPC-level not_found folding and raw RLS denial both hold'
do $$
declare
  v_tenant1 uuid;
  v_position_solo_id uuid;
  v_grade_id uuid;
  v_report_id uuid;
begin
  select id into v_tenant1 from app.tenants where slug = 'hrpos1';
  select id into v_position_solo_id from app.positions where tenant_id = v_tenant1 and code = 'POS-SOLO';
  select id into v_grade_id from app.position_grades where tenant_id = v_tenant1 and code = 'GR-1';
  select master_record_id into v_report_id from app.employees where tenant_id = v_tenant1 and full_name = 'Hrpos1 Report Person';

  begin
    perform app.update_position(v_position_solo_id, (select record_version from app.positions where id = v_position_solo_id), 'Hijacked Title', null, null, 1, null, '00000000-0000-0000-0000-000000027522', 'tester');
    raise exception 'assertion failed: expected a hrpos2 actor to be denied (not-found folding) on a hrpos1 position, but it succeeded';
  exception
    when no_data_found then null;
  end;

  begin
    perform app.propose_employee_position_assignment(
      v_report_id, (select record_version from app.employees where master_record_id = v_report_id), v_position_solo_id, null, null,
      'primary', 100.00, current_date + 60, null, 'transfer', 'cross-tenant attempt', '00000000-0000-0000-0000-000000027522', 'tester'
    );
    raise exception 'assertion failed: expected a hrpos2 actor to be denied (not-found folding) on a hrpos1 employee, but it succeeded';
  exception
    when no_data_found then null;
  end;
end;
$$;

\echo '>> RLS default-deny for a customer_user-layer principal: tenant membership alone is not enough -- a customer_user-layer actor in the SAME tenant reads zero rows from any of the three new tables at the raw-RLS level'
do $$
declare
  v_position_solo_id uuid := (select id from app.positions where tenant_id = (select id from app.tenants where slug = 'hrpos1') and code = 'POS-SOLO');
  v_grade_id uuid := (select id from app.position_grades where tenant_id = (select id from app.tenants where slug = 'hrpos1') and code = 'GR-1');
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027515", "role": "authenticated"}', true);

  if exists (select 1 from app.positions where id = v_position_solo_id) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.positions directly, even inside its own tenant';
  end if;
  if exists (select 1 from app.position_grades where id = v_grade_id) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.position_grades directly';
  end if;
  if exists (select 1 from app.employee_position_assignments where tenant_id = (select id from app.tenants where slug = 'hrpos1')) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.employee_position_assignments directly';
  end if;

  reset role;
end;
$$;

\echo '>> defense in depth: anon is denied entirely at the schema-privilege layer on every new table; service_role has explicit full access'
do $$
begin
  set local role anon;
  begin
    perform count(*) from app.positions;
    raise exception 'assertion failed: anon must be denied at the schema-privilege layer for app.positions';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform count(*) from app.position_grades;
    raise exception 'assertion failed: anon must be denied at the schema-privilege layer for app.position_grades';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform count(*) from app.employee_position_assignments;
    raise exception 'assertion failed: anon must be denied at the schema-privilege layer for app.employee_position_assignments';
  exception
    when insufficient_privilege then null;
  end;
  reset role;
end;
$$;

do $$
declare
  v_count integer;
begin
  set local role service_role;
  select count(*) into v_count from app.positions;
  if v_count < 2 then
    raise exception 'assertion failed: service_role must see every position row, saw %', v_count;
  end if;
  select count(*) into v_count from app.employee_position_assignments;
  if v_count < 1 then
    raise exception 'assertion failed: service_role must see every assignment row, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo '>> structural regression guard: app.org_units/app.employees/app.master_records core shapes are untouched by this migration (only additive columns/constraints)'
do $$
declare
  v_org_unit_type_count integer;
  v_employees_position_id_exists boolean;
begin
  select count(distinct unit_type) into v_org_unit_type_count from app.org_units;
  if v_org_unit_type_count < 4 then
    raise exception 'assertion failed: expected at least 4 distinct unit_type values still present (regression), found %', v_org_unit_type_count;
  end if;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'employees' and column_name = 'position_id'
  ) into v_employees_position_id_exists;
  if not v_employees_position_id_exists then
    raise exception 'assertion failed: expected app.employees.position_id to exist as an additive column';
  end if;

  if not exists (select 1 from information_schema.columns where table_schema = 'app' and table_name = 'employees' and column_name = 'position_title') then
    raise exception 'assertion failed: app.employees.position_title (HRT-274''s own display fallback) must never be dropped';
  end if;
end;
$$;

\echo '>> HRT-293 self-found regression (same shape as Finding A): app.employee_position_assignments.reason_note/decided_reason are no longer readable by any active tenant member via a raw column-level SELECT, and app.decide_employee_position_assignment/app.cancel_employee_position_assignment no longer duplicate the raw reason into app.audit_logs.reason (Finding B)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrpos1');
  v_department_id uuid := (select id from app.org_units where tenant_id = v_tenant1 and unit_type = 'department');
  v_position_solo_id uuid := (select id from app.positions where tenant_id = v_tenant1 and code = 'POS-SOLO');
  v_grade_id uuid := (select id from app.position_grades where tenant_id = v_tenant1 and code = 'GR-1');
  v_manager_id uuid;
  v_manager_version integer;
  v_staff uuid := '00000000-0000-0000-0000-000000027512';
  v_approver uuid := '00000000-0000-0000-0000-000000027513';
  v_proposal app.employee_position_assignments;
  v_reason text := 'HRT-293 regression: personal circumstance narrative, never for the audit log';
begin
  -- Column-level defense in depth, verified directly (no fixture needed): the two
  -- free-text reason columns must have no column-level SELECT grant to `authenticated`
  -- at all, while a structural sibling column (change_reason, a fixed enum) does.
  if has_column_privilege('authenticated', 'app.employee_position_assignments', 'reason_note', 'select') then
    raise exception 'HRT-293 regression: app.employee_position_assignments.reason_note must not be selectable by authenticated';
  end if;
  if has_column_privilege('authenticated', 'app.employee_position_assignments', 'decided_reason', 'select') then
    raise exception 'HRT-293 regression: app.employee_position_assignments.decided_reason must not be selectable by authenticated';
  end if;
  if not has_column_privilege('authenticated', 'app.employee_position_assignments', 'change_reason', 'select') then
    raise exception 'HRT-293 regression: app.employee_position_assignments.change_reason should remain selectable (structural enum, not free text)';
  end if;

  -- Reject path (deliberately -- never touches the capacity/predecessor logic
  -- POS-SOLO's own existing incumbent would otherwise trip): proves the same
  -- `decided_reason` free text never reaches app.audit_logs.
  select master_record_id, record_version into v_manager_id, v_manager_version
  from app.employees where tenant_id = v_tenant1 and full_name = 'Hrpos1 Manager Person';

  v_proposal := app.propose_employee_position_assignment(
    v_manager_id, v_manager_version, v_position_solo_id, v_grade_id, null,
    'primary', 100.00, current_date + 90, null, 'transfer', v_reason, v_staff, 'tester'
  );
  perform app.decide_employee_position_assignment(v_proposal.id, v_proposal.record_version, 'reject', v_reason, v_approver, 'tester');

  if exists (select 1 from app.audit_logs where reason = v_reason) then
    raise exception 'HRT-293 Finding B regression: app.audit_logs.reason must never carry the raw employee-position-assignment decision reason';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'decide_employee_position_assignment' and resource_id = v_proposal.id and reason is null) then
    raise exception 'HRT-293 Finding B regression: expected a decide_employee_position_assignment audit_logs row with reason=null';
  end if;
end;
$$;

\echo '>> ISS-2026-066 item 3 regression: staged import (PLT-131/132) crosswalk for position/grade -- validates employee/position/grade/manager code resolution, rejects formula-injection and the secondary/secondary_assignment pairing mismatch, creates a real pending_approval proposal only (never auto-decided), is idempotent per staging row, and genuinely requires HRS:Import (not merely HRS:Edit)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrpos1');
  v_admin uuid := '00000000-0000-0000-0000-000000027511';
  v_staff uuid := '00000000-0000-0000-0000-000000027512';
  v_viewer uuid := '00000000-0000-0000-0000-000000027514';
  v_import_role uuid;
  v_import_draft app.role_versions;
  v_doc_draft app.config_versions;
  v_schema_draft app.config_versions;
  v_source_file app.files;
  v_job app.jobs;
  v_row_valid app.import_staging_rows;
  v_row_bad_position app.import_staging_rows;
  v_row_injection app.import_staging_rows;
  v_row_secondary_mismatch app.import_staging_rows;
  v_committed app.jobs;
  v_report_number text;
  v_manager_number text;
  v_created_count integer;
  v_recommitted app.jobs;
  v_denial_job app.jobs;
  v_denial_row app.import_staging_rows;
  v_denial_source_file app.files;
begin
  -- staff (027512) already holds HRS:Create/Edit/View from the top-of-file fixture --
  -- widened here with a SECOND role granting HRS:Import (roles are additive; a real
  -- actor may hold more than one simultaneously), so this block proves the SAME staff
  -- identity, never a new synthetic one, driving a real crosswalk import end to end.
  v_import_role := (app.create_role(v_tenant1, 'HRS Import Grant', 'Import only', 'tester')).id;
  v_import_draft := app.create_role_version(v_import_role, 'tester');
  perform app.set_role_version_permissions(v_import_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action = 'Import'), 'tester');
  perform app.publish_role_version(v_import_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_import_role and status = 'published'), v_staff, v_admin, 'tester');

  -- Per-tenant onboarding steps this adapter requires, mirroring hris-employee-
  -- master.sql's own identical staged-import setup exactly (tenant hrpos1 has never
  -- published either config type before this block).
  v_doc_draft := app.create_config_draft('document:employee_document', v_tenant1, 'tenant', null, v_admin, 'tester');
  perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('text/csv')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('confidential'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_admin, 'tester');
  perform app.publish_document_type_definition(v_doc_draft.id, v_admin, now(), 'tester');

  v_schema_draft := app.create_config_draft('import_export:position_crosswalk_import', v_tenant1, 'tenant', null, v_admin, 'tester');
  perform app.set_config_items(v_schema_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
      jsonb_build_object('key', 'employee_number', 'label', 'Employee Number', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'position_code', 'label', 'Position Code', 'required', true, 'data_type', 'text'),
      jsonb_build_object('key', 'grade_code', 'label', 'Grade Code', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'manager_employee_number', 'label', 'Manager Employee Number', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'assignment_type', 'label', 'Assignment Type', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'allocation_pct', 'label', 'Allocation %', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'effective_start_date', 'label', 'Effective Start Date', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'effective_end_date', 'label', 'Effective End Date', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'change_reason', 'label', 'Change Reason', 'required', false, 'data_type', 'text'),
      jsonb_build_object('key', 'reason_note', 'label', 'Reason Note', 'required', false, 'data_type', 'text')
    ))
  ), v_admin, 'tester');
  perform app.publish_import_export_schema(v_schema_draft.id, v_admin, now(), 'tester');

  select m.code into v_report_number from app.employees e join app.master_records m on m.id = e.master_record_id where e.tenant_id = v_tenant1 and e.full_name = 'Hrpos1 Report Person';
  select m.code into v_manager_number from app.employees e join app.master_records m on m.id = e.master_record_id where e.tenant_id = v_tenant1 and e.full_name = 'Hrpos1 Manager Person';

  v_source_file := app.initiate_file_upload(v_tenant1, 'employee_document', 'import_job', gen_random_uuid(), 'position-crosswalk.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-poscross-source-1', v_staff, 'staff');
  perform app.record_file_scan_result(v_source_file.id, 'clean', null, v_staff, 'staff');

  v_job := app.create_import_export_job(v_tenant1, 'import', 'position_crosswalk_import', v_source_file.id, '{}'::jsonb, 'idem-poscross-job-1', v_staff, 'staff');

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', v_report_number, 'position_code', 'POS-DUO', 'grade_code', 'GR-1',
    'manager_employee_number', v_manager_number, 'change_reason', 'reorganization',
    'reason_note', 'Crosswalk migration of legacy free-text title'
  )), v_staff, 'staff');
  select * into v_row_valid from app.import_staging_rows where job_id = v_job.job_id and row_number = 1;

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', v_report_number, 'position_code', 'NOT-A-REAL-POSITION'
  )), v_staff, 'staff');
  select * into v_row_bad_position from app.import_staging_rows where job_id = v_job.job_id and row_number = 2;

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', v_report_number, 'position_code', 'POS-DUO', 'reason_note', '=cmd|/c calc'
  )), v_staff, 'staff');
  select * into v_row_injection from app.import_staging_rows where job_id = v_job.job_id and row_number = 3;

  perform app.stage_import_rows(v_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', v_report_number, 'position_code', 'POS-DUO', 'assignment_type', 'secondary', 'change_reason', 'transfer'
  )), v_staff, 'staff');
  select * into v_row_secondary_mismatch from app.import_staging_rows where job_id = v_job.job_id and row_number = 4;

  perform app.validate_position_crosswalk_import_row(v_row_valid.id, v_staff, 'staff');
  perform app.validate_position_crosswalk_import_row(v_row_bad_position.id, v_staff, 'staff');
  perform app.validate_position_crosswalk_import_row(v_row_injection.id, v_staff, 'staff');
  perform app.validate_position_crosswalk_import_row(v_row_secondary_mismatch.id, v_staff, 'staff');

  if (select validation_status from app.import_staging_rows where id = v_row_valid.id) <> 'valid' then
    raise exception 'assertion failed: expected the well-formed crosswalk row to validate as valid, got %', (select error from app.import_staging_rows where id = v_row_valid.id);
  end if;
  if (select validation_status from app.import_staging_rows where id = v_row_bad_position.id) <> 'invalid' or (select error from app.import_staging_rows where id = v_row_bad_position.id) !~ 'position_code' then
    raise exception 'assertion failed: expected row 2 (unknown position_code) to be invalid with a position_code error, got %', (select error from app.import_staging_rows where id = v_row_bad_position.id);
  end if;
  if (select validation_status from app.import_staging_rows where id = v_row_injection.id) <> 'invalid' or (select error from app.import_staging_rows where id = v_row_injection.id) !~ 'formula/spreadsheet-injection' then
    raise exception 'assertion failed: expected row 3 (formula-injection attempt in reason_note) to be rejected as invalid, got %', (select error from app.import_staging_rows where id = v_row_injection.id);
  end if;
  if (select validation_status from app.import_staging_rows where id = v_row_secondary_mismatch.id) <> 'invalid' or (select error from app.import_staging_rows where id = v_row_secondary_mismatch.id) !~ 'secondary_assignment' then
    raise exception 'assertion failed: expected row 4 (secondary assignment_type with a non-secondary_assignment change_reason) to be rejected as invalid, got %', (select error from app.import_staging_rows where id = v_row_secondary_mismatch.id);
  end if;

  begin
    perform app.commit_position_crosswalk_import_job(v_job.job_id, false, v_staff, 'staff');
    raise exception 'assertion failed: expected import_export_job_has_invalid_rows without p_allow_partial';
  exception
    when others then
      if sqlerrm not like 'import_export_job_has_invalid_rows%' then raise; end if;
  end;

  v_committed := app.commit_position_crosswalk_import_job(v_job.job_id, true, v_staff, 'staff');
  if v_committed.status <> 'completed' then
    raise exception 'assertion failed: expected the job to complete on a partial commit, got %', v_committed.status;
  end if;

  select count(*) into v_created_count from app.employee_position_assignments where source_import_staging_row_id = v_row_valid.id;
  if v_created_count <> 1 then
    raise exception 'assertion failed: expected exactly one real proposal created from the valid staged row, found %', v_created_count;
  end if;

  if not exists (
    select 1 from app.employee_position_assignments a
    where a.source_import_staging_row_id = v_row_valid.id
      and a.status = 'pending_approval'
      and a.position_id = (select id from app.positions where tenant_id = v_tenant1 and code = 'POS-DUO')
      and a.grade_id = (select id from app.position_grades where tenant_id = v_tenant1 and code = 'GR-1')
      and a.manager_employee_id = (select e2.master_record_id from app.employees e2 join app.master_records m2 on m2.id = e2.master_record_id where e2.tenant_id = v_tenant1 and m2.code = v_manager_number)
      and a.change_reason = 'reorganization'
  ) then
    raise exception 'assertion failed: expected the imported row to resolve employee/position/grade/manager codes correctly and land as a real pending_approval proposal, never auto-approved';
  end if;

  -- Idempotent replay: the job is no longer in_progress, so a second commit call is
  -- itself refused -- but confirm no second proposal was ever created for the same
  -- staging row regardless.
  begin
    v_recommitted := app.commit_position_crosswalk_import_job(v_job.job_id, true, v_staff, 'staff');
    raise exception 'assertion failed: expected import_export_job_not_committable for a job already completed';
  exception
    when others then
      if sqlerrm not like 'import_export_job_not_committable%' then raise; end if;
  end;

  select count(*) into v_created_count from app.employee_position_assignments where source_import_staging_row_id = v_row_valid.id;
  if v_created_count <> 1 then
    raise exception 'assertion failed: expected still exactly one proposal after the refused recommit, found %', v_created_count;
  end if;

  -- Authority: the tenant's HRS viewer (View only -- no Import, no Edit) genuinely
  -- cannot commit a crosswalk job, proving HRS:Import is a real, enforced gate rather
  -- than merely disclosed in this migration's own comments.
  v_denial_source_file := app.initiate_file_upload(v_tenant1, 'employee_document', 'import_job', gen_random_uuid(), 'position-crosswalk-denial.csv', 'text/csv', 2048, null, false, null, '{}', null, 'idem-poscross-source-2', v_staff, 'staff');
  perform app.record_file_scan_result(v_denial_source_file.id, 'clean', null, v_staff, 'staff');
  v_denial_job := app.create_import_export_job(v_tenant1, 'import', 'position_crosswalk_import', v_denial_source_file.id, '{}'::jsonb, 'idem-poscross-job-denial-1', v_staff, 'staff');
  perform app.stage_import_rows(v_denial_job.job_id, jsonb_build_array(jsonb_build_object(
    'employee_number', v_report_number, 'position_code', 'POS-DUO'
  )), v_staff, 'staff');
  select * into v_denial_row from app.import_staging_rows where job_id = v_denial_job.job_id and row_number = 1;
  perform app.validate_position_crosswalk_import_row(v_denial_row.id, v_staff, 'staff');

  begin
    perform app.commit_position_crosswalk_import_job(v_denial_job.job_id, false, v_viewer, 'viewer');
    raise exception 'assertion failed: expected the HRS-View-only viewer identity to be denied HRS:Import';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%HRS:Import%' then raise; end if;
  end;

  -- The SAME job, committed by the staff identity that genuinely holds HRS:Import
  -- (and HRS:Edit), still succeeds -- the denial above was a real authority gate, not
  -- a structural failure of the job itself.
  v_committed := app.commit_position_crosswalk_import_job(v_denial_job.job_id, false, v_staff, 'staff');
  if v_committed.status <> 'completed' then
    raise exception 'assertion failed: expected the denial-proof job to complete once committed by an identity holding HRS:Import, got %', v_committed.status;
  end if;
end;
$$;

\echo 'ALL HRT-275 db-test assertions passed.'
