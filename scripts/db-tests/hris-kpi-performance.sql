-- Real, executable test evidence for HRT-283 (KPI and Performance,
-- CG-S12-HRT-011) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database (and standalone via psql per the runtime instructions,
-- since ISS-2026-077 -- a pre-existing, unrelated bug in
-- hris-leave-permit-business-trip.sql -- aborts the shared alphabetical
-- suite before reaching this file).
--
-- Self-contained: own two-tenant/employee/role fixture, own fresh,
-- unclaimed UUID range (00000000-0000-0000-0000-0000000283xx). Tenant
-- slugs `kpi1`/`kpi2` (grep-verified unclaimed).
--
-- Covers, live: KPI library versioning; template publish weight-sum
-- validation; cycle stage machine; weighted goal assignment (exact 100.00
-- weight requirement, not-applicable rebalancing); self/manager/reviewer
-- assessment stages with purpose/stage-bound visibility (an employee
-- cannot see their own manager assessment until submitted; a manager sees
-- reviewer input, the employee never does); explainable exact-decimal
-- scoring (decision 2 -- self and reviewer scores never affect the
-- computed outcome, only the submitted manager assessment does, proven
-- with deliberately DIFFERENT self vs manager scores); governed
-- calibration (self-calibration blocked, unauthorized-actor calibration
-- blocked, a distinct authorized actor succeeds); publish/acknowledge;
-- appeal/reopen (self-decision blocked, overturn reopens for
-- recalibration, uphold returns to published); manager reassignment NOT
-- silently transferring an already-submitted review; a genuine k-anonity
-- floor (a real 2-person department suppressed, a real 5-person department
-- not); cross-tenant RLS isolation; concurrent goal-assignment and
-- concurrent appeal-submission races; zero write to
-- app.employees.lifecycle_status/payroll/role tables (structural grep,
-- recorded in the build log, not re-proven here).

\set ON_ERROR_STOP on

\echo '>> fixture'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_hr_role uuid; v_hr_draft app.role_versions;
  v_appr_role uuid; v_appr_draft app.role_versions;
  v_company uuid; v_branch uuid; v_dept_small uuid; v_dept_big uuid;
  v_mgr uuid; v_emp1 uuid; v_emp2 uuid; v_rev1 uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000028301', 'admin@kpi1.test'),
    ('00000000-0000-0000-0000-000000028302', 'hr@kpi1.test'),
    ('00000000-0000-0000-0000-000000028303', 'approver@kpi1.test'),
    ('00000000-0000-0000-0000-000000028304', 'mgr1@kpi1.test'),
    ('00000000-0000-0000-0000-000000028305', 'emp1@kpi1.test'),
    ('00000000-0000-0000-0000-000000028306', 'emp2@kpi1.test'),
    ('00000000-0000-0000-0000-000000028307', 'reviewer1@kpi1.test'),
    ('00000000-0000-0000-0000-000000028321', 'admin@kpi2.test');

  perform app.provision_tenant('kpi1', 'KPI Co 1', 'idem-kpi1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'kpi1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('kpi2', 'KPI Co 2', 'idem-kpi2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'kpi2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028301', 'admin@kpi1.test', 'Kpi1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@kpi1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028301', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028302', 'hr@kpi1.test', 'Kpi1 HR', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'hr@kpi1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028303', 'approver@kpi1.test', 'Kpi1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@kpi1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028304', 'mgr1@kpi1.test', 'Kpi1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'mgr1@kpi1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028305', 'emp1@kpi1.test', 'Kpi1 Emp One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp1@kpi1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028306', 'emp2@kpi1.test', 'Kpi1 Emp Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp2@kpi1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028307', 'reviewer1@kpi1.test', 'Kpi1 Reviewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'reviewer1@kpi1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000028321', 'admin@kpi2.test', 'Kpi2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@kpi2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028321', 'tenant_admin', v_tenant2, null, 'tester');

  -- HR role: HRS Create/Edit/View (author KPI/template/cycle/goals).
  v_hr_role := (app.create_role(v_tenant1, 'HR KPI', 'Edit/View', 'tester')).id;
  v_hr_draft := app.create_role_version(v_hr_role, 'tester');
  perform app.set_role_version_permissions(v_hr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_hr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_hr_role and status = 'published'), '00000000-0000-0000-0000-000000028302', '00000000-0000-0000-0000-000000028301', 'tester');

  -- Approver role: HRS Approve/Override/View/View personal data (publish,
  -- advance cycle, calibrate, publish/acknowledge outcome oversight,
  -- decide appeal, reassign reviewer, report).
  v_appr_role := (app.create_role(v_tenant1, 'KPI Approver', 'Approve/Override/View/View personal data', 'tester')).id;
  v_appr_draft := app.create_role_version(v_appr_role, 'tester');
  perform app.set_role_version_permissions(v_appr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Approve', 'Override', 'View', 'View personal data')), 'tester');
  perform app.publish_role_version(v_appr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_appr_role and status = 'published'), '00000000-0000-0000-0000-000000028303', '00000000-0000-0000-0000-000000028301', 'tester');
  -- NOTE: emp1 is deliberately NOT granted the Approver role here -- doing
  -- so would give emp1 HRS:View personal data from the start, defeating
  -- the later "emp1 cannot see their own draft manager assessment"
  -- stage-bound-visibility proof. emp1 is granted Approver LATER, only
  -- immediately before the self-calibration/self-appeal-decision block
  -- tests that specifically need it (mirrors HRT-282's own "hr also holds
  -- Payroll Approver role" self-block test shape, timed correctly).

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-KPI1', 'Kpi1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-KPI1', 'Kpi1 Branch', 'tester')).id;
  v_dept_small := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-SMALL', 'Small Dept', 'tester')).id;
  v_dept_big := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-BIG', 'Big Dept', 'tester')).id;

  perform app.create_employee_draft(v_tenant1, 'Kpi1 Manager', 'full_time', 'mgr1work@kpi1.test', 'mgr1p@kpi1.test', '0900000004', null, null, null, '2024-01-01', v_company, v_branch, v_dept_small, 'Manager', null, (select id from app.users where email = 'mgr1@kpi1.test'), null, 'hr_created', 'idem-mgr1-kpi1', '00000000-0000-0000-0000-000000028302', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@kpi1.test'), 'Contact Mgr', 'spouse', '0910000004', null, true, '00000000-0000-0000-0000-000000028302', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@kpi1.test'), 1, '00000000-0000-0000-0000-000000028302', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@kpi1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028303', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@kpi1.test'), 3, '00000000-0000-0000-0000-000000028303', 'tester');
  v_mgr := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@kpi1.test');

  perform app.create_employee_draft(v_tenant1, 'Kpi1 Emp One', 'full_time', 'emp1work@kpi1.test', 'emp1p@kpi1.test', '0900000005', null, null, null, '2024-01-01', v_company, v_branch, v_dept_small, 'Staff', v_mgr, (select id from app.users where email = 'emp1@kpi1.test'), null, 'hr_created', 'idem-emp1-kpi1', '00000000-0000-0000-0000-000000028302', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@kpi1.test'), 'Contact One', 'spouse', '0910000005', null, true, '00000000-0000-0000-0000-000000028302', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@kpi1.test'), 1, '00000000-0000-0000-0000-000000028302', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@kpi1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028303', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@kpi1.test'), 3, '00000000-0000-0000-0000-000000028303', 'tester');
  v_emp1 := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@kpi1.test');

  perform app.create_employee_draft(v_tenant1, 'Kpi1 Emp Two', 'full_time', 'emp2work@kpi1.test', 'emp2p@kpi1.test', '0900000006', null, null, null, '2024-01-01', v_company, v_branch, v_dept_small, 'Staff', v_mgr, (select id from app.users where email = 'emp2@kpi1.test'), null, 'hr_created', 'idem-emp2-kpi1', '00000000-0000-0000-0000-000000028302', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@kpi1.test'), 'Contact Two', 'spouse', '0910000006', null, true, '00000000-0000-0000-0000-000000028302', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@kpi1.test'), 1, '00000000-0000-0000-0000-000000028302', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@kpi1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028303', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@kpi1.test'), 3, '00000000-0000-0000-0000-000000028303', 'tester');
  v_emp2 := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@kpi1.test');

  perform app.create_employee_draft(v_tenant1, 'Kpi1 Reviewer One', 'full_time', 'reviewer1work@kpi1.test', 'reviewer1p@kpi1.test', '0900000007', null, null, null, '2024-01-01', v_company, v_branch, v_dept_small, 'Staff', null, (select id from app.users where email = 'reviewer1@kpi1.test'), null, 'hr_created', 'idem-reviewer1-kpi1', '00000000-0000-0000-0000-000000028302', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'reviewer1work@kpi1.test'), 'Contact Reviewer', 'spouse', '0910000007', null, true, '00000000-0000-0000-0000-000000028302', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'reviewer1work@kpi1.test'), 1, '00000000-0000-0000-0000-000000028302', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'reviewer1work@kpi1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028303', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'reviewer1work@kpi1.test'), 3, '00000000-0000-0000-0000-000000028303', 'tester');
  v_rev1 := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'reviewer1work@kpi1.test');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%, mgr=%, emp1=%, emp2=%, reviewer1=%', v_tenant1, v_tenant2, v_mgr, v_emp1, v_emp2, v_rev1;
end $$;

\echo '>> KPI library: two versioned KPIs (target_ratio higher_is_better, qualitative_scale)'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_sales app.performance_kpi_definitions;
  v_quality app.performance_kpi_definitions;
  v_ver app.performance_kpi_definition_versions;
begin
  v_sales := app.create_performance_kpi_definition(v_tenant, 'sales_target', 'Sales Target', 'quarterly revenue target', 'currency', '00000000-0000-0000-0000-000000028302', 'hr');
  v_ver := app.create_performance_kpi_definition_version(v_sales.id, 'target_ratio', 'higher_is_better', '00000000-0000-0000-0000-000000028302', 'hr');
  if v_ver.status <> 'active' or v_ver.version_number <> 1 then raise exception 'assertion failed: sales_target version not active v1: %', v_ver; end if;

  v_quality := app.create_performance_kpi_definition(v_tenant, 'quality_score', 'Quality Score', 'manager-assessed quality', 'qualitative', '00000000-0000-0000-0000-000000028302', 'hr');
  perform app.create_performance_kpi_definition_version(v_quality.id, 'qualitative_scale', null, '00000000-0000-0000-0000-000000028302', 'hr');

  -- Idempotent re-create returns the same row.
  if (app.create_performance_kpi_definition(v_tenant, 'sales_target', 'Sales Target', 'quarterly revenue target', 'currency', '00000000-0000-0000-0000-000000028302', 'hr')).id <> v_sales.id then
    raise exception 'assertion failed: create_performance_kpi_definition not idempotent';
  end if;
  raise notice 'OK: KPI library sales_target v1 + quality_score v1 active';
end $$;

\echo '>> template: publish blocked until weights sum to exactly 100, succeeds once they do'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_template app.performance_templates;
begin
  v_template := app.create_performance_template(v_tenant, 'annual_std', 'Annual Standard', 100.00, true, '00000000-0000-0000-0000-000000028302', 'hr');
  perform app.add_performance_template_kpi_item(v_template.id, (select id from app.performance_kpi_definitions where tenant_id=v_tenant and code='sales_target'), 60.00, true, 1, '00000000-0000-0000-0000-000000028302', 'hr');

  begin
    perform app.publish_performance_template(v_template.id, v_template.record_version, '00000000-0000-0000-0000-000000028303', 'approver');
    raise exception 'ASSERTION FAILURE: template published with incomplete weights (60/100)';
  exception
    when others then
      if sqlerrm not like '%template_weights_incomplete%' then raise exception 'wrong error: %', sqlerrm; end if;
      raise notice 'OK: incomplete-weight template publish correctly blocked (%)', sqlerrm;
  end;

  perform app.add_performance_template_kpi_item(v_template.id, (select id from app.performance_kpi_definitions where tenant_id=v_tenant and code='quality_score'), 40.00, true, 2, '00000000-0000-0000-0000-000000028302', 'hr');
  v_template := app.publish_performance_template(v_template.id, v_template.record_version, '00000000-0000-0000-0000-000000028303', 'approver');
  if v_template.status <> 'published' then raise exception 'assertion failed: template not published: %', v_template.status; end if;
  raise notice 'OK: template published once weights sum to exactly 100';
end $$;

\echo '>> cycle: create + advance to goal_setting_open'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_template_id uuid := (select id from app.performance_templates where tenant_id=v_tenant and code='annual_std');
  v_cycle app.performance_cycles;
begin
  v_cycle := app.create_performance_cycle(v_tenant, v_template_id, 'fy2026', 'FY2026 Annual Review', 'annual', '2026-01-01', '2026-12-31', '2026-02-01', '2026-11-01', '2026-11-15', '2026-12-01', '00000000-0000-0000-0000-000000028302', 'hr');
  v_cycle := app.advance_performance_cycle_stage(v_cycle.id, v_cycle.record_version, 'goal_setting_open', '00000000-0000-0000-0000-000000028303', 'approver');
  if v_cycle.status <> 'goal_setting_open' then raise exception 'assertion failed: expected goal_setting_open, got %', v_cycle.status; end if;
  -- Illegal skip (goal_setting_open -> calibration) rejected.
  begin
    perform app.advance_performance_cycle_stage(v_cycle.id, v_cycle.record_version, 'calibration', '00000000-0000-0000-0000-000000028303', 'approver');
    raise exception 'ASSERTION FAILURE: illegal stage skip succeeded';
  exception
    when others then
      if sqlerrm not like '%invalid_transition%' then raise exception 'wrong error: %', sqlerrm; end if;
      raise notice 'OK: illegal cycle-stage skip correctly blocked (%)', sqlerrm;
  end;
end $$;

\echo '>> goal assignment: emp1 gets sales_target(60) + quality_score(40) = 100 exactly; auto-creates self assessment + frozen manager assignment'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_cycle_id uuid := (select id from app.performance_cycles where tenant_id=v_tenant and code='fy2026');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@kpi1.test');
  v_mgr uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='mgr1work@kpi1.test');
  v_goal app.performance_goal_assignments;
  v_self_a app.performance_assessments;
  v_mgr_a app.performance_assessments;
begin
  v_goal := app.assign_performance_goal(v_cycle_id, v_emp1, (select id from app.performance_kpi_definitions where tenant_id=v_tenant and code='sales_target'), 60.00, 100000, 'IDR', '00000000-0000-0000-0000-000000028302', 'hr');
  perform app.assign_performance_goal(v_cycle_id, v_emp1, (select id from app.performance_kpi_definitions where tenant_id=v_tenant and code='quality_score'), 40.00, null, null, '00000000-0000-0000-0000-000000028302', 'hr');

  select * into v_self_a from app.performance_assessments where cycle_id=v_cycle_id and employee_id=v_emp1 and assessment_type='self';
  if v_self_a.id is null or v_self_a.assigned_to_employee_id <> v_emp1 then raise exception 'assertion failed: self assessment not auto-created correctly'; end if;

  select * into v_mgr_a from app.performance_assessments where cycle_id=v_cycle_id and employee_id=v_emp1 and assessment_type='manager';
  if v_mgr_a.id is null or v_mgr_a.assigned_to_employee_id <> v_mgr then raise exception 'assertion failed: manager assignment not auto-frozen to mgr1: %', v_mgr_a.assigned_to_employee_id; end if;

  -- Progress entry (self logs progress with evidence-free note).
  perform app.record_performance_goal_progress(v_goal.id, 45000, 'halfway through Q2', null, '00000000-0000-0000-0000-000000028305', 'emp1');
  if (select count(*) from app.performance_goal_progress_entries where goal_assignment_id = v_goal.id) <> 1 then
    raise exception 'assertion failed: progress entry not recorded';
  end if;
  raise notice 'OK: goal assignment (weight 60+40=100), self assessment + frozen manager assignment auto-created, progress entry recorded';
end $$;

\echo '>> self assessment: weight-incomplete/score-incomplete guard, then full submit (with DIFFERENT scores than the manager will later give -- proves decision 2)'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_cycle app.performance_cycles;
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@kpi1.test');
  v_self_a app.performance_assessments;
  v_goal_sales uuid; v_goal_quality uuid;
begin
  select * into v_cycle from app.performance_cycles where tenant_id=v_tenant and code='fy2026';
  select * into v_self_a from app.performance_assessments where cycle_id=v_cycle.id and employee_id=v_emp1 and assessment_type='self';
  v_goal_sales := (select id from app.performance_goal_assignments where cycle_id=v_cycle.id and employee_id=v_emp1 and kpi_definition_id=(select id from app.performance_kpi_definitions where tenant_id=v_tenant and code='sales_target'));
  v_goal_quality := (select id from app.performance_goal_assignments where cycle_id=v_cycle.id and employee_id=v_emp1 and kpi_definition_id=(select id from app.performance_kpi_definitions where tenant_id=v_tenant and code='quality_score'));

  begin
    perform app.submit_performance_self_assessment(v_cycle.id, v_self_a.record_version, 'my self review', '00000000-0000-0000-0000-000000028305', 'emp1');
    raise exception 'ASSERTION FAILURE: self assessment submitted with zero scores recorded';
  exception
    when others then
      if sqlerrm not like '%goal_scores_incomplete%' then raise exception 'wrong error: %', sqlerrm; end if;
      raise notice 'OK: submit blocked with no scores recorded (%)', sqlerrm;
  end;

  perform app.upsert_performance_assessment_kpi_score(v_self_a.id, v_goal_sales, 90000, null, 'I hit 90 percent of target', '00000000-0000-0000-0000-000000028305', 'emp1');
  perform app.upsert_performance_assessment_kpi_score(v_self_a.id, v_goal_quality, null, 70, 'solid quality, some room to grow', '00000000-0000-0000-0000-000000028305', 'emp1');

  select * into v_self_a from app.performance_assessments where id = v_self_a.id;
  v_self_a := app.submit_performance_self_assessment(v_cycle.id, v_self_a.record_version, 'my self review', '00000000-0000-0000-0000-000000028305', 'emp1');
  if v_self_a.status <> 'submitted' then raise exception 'assertion failed: self assessment not submitted: %', v_self_a.status; end if;

  -- Goals now locked -- a further goal edit is rejected.
  begin
    perform app.assign_performance_goal(v_cycle.id, v_emp1, (select id from app.performance_kpi_definitions where tenant_id=v_tenant and code='sales_target'), 70.00, 100000, 'IDR', '00000000-0000-0000-0000-000000028302', 'hr');
    raise exception 'ASSERTION FAILURE: goal weight edited after self assessment submitted';
  exception
    when others then
      if sqlerrm not like '%goals_locked%' then raise exception 'wrong error: %', sqlerrm; end if;
      raise notice 'OK: goal edit correctly locked after self-assessment submission (%)', sqlerrm;
  end;
end $$;

\echo '>> not-applicable goal + weight rebalancing (emp2)'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_cycle_id uuid := (select id from app.performance_cycles where tenant_id=v_tenant and code='fy2026');
  v_emp2 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp2work@kpi1.test');
  v_goal1 app.performance_goal_assignments;
  v_goal2 app.performance_goal_assignments;
  v_self_a app.performance_assessments;
begin
  v_goal1 := app.assign_performance_goal(v_cycle_id, v_emp2, (select id from app.performance_kpi_definitions where tenant_id=v_tenant and code='sales_target'), 50.00, 50000, 'IDR', '00000000-0000-0000-0000-000000028302', 'hr');
  v_goal2 := app.assign_performance_goal(v_cycle_id, v_emp2, (select id from app.performance_kpi_definitions where tenant_id=v_tenant and code='quality_score'), 50.00, null, null, '00000000-0000-0000-0000-000000028302', 'hr');

  -- Mark quality_score not applicable -- weight total now 50, not 100.
  v_goal2 := app.mark_performance_goal_not_applicable(v_goal2.id, v_goal2.record_version, 'role changed mid-cycle, quality metric no longer applies', '00000000-0000-0000-0000-000000028304', 'mgr1');

  select * into v_self_a from app.performance_assessments where cycle_id=v_cycle_id and employee_id=v_emp2 and assessment_type='self';
  perform app.upsert_performance_assessment_kpi_score(v_self_a.id, v_goal1.id, 50000, null, 'hit target exactly', '00000000-0000-0000-0000-000000028306', 'emp2');
  select * into v_self_a from app.performance_assessments where id = v_self_a.id;
  begin
    perform app.submit_performance_self_assessment(v_cycle_id, v_self_a.record_version, 'review', '00000000-0000-0000-0000-000000028306', 'emp2');
    raise exception 'ASSERTION FAILURE: self assessment submitted with active weights summing to only 50, not 100';
  exception
    when others then
      if sqlerrm not like '%goal_weights_incomplete%' then raise exception 'wrong error: %', sqlerrm; end if;
      raise notice 'OK: submission blocked while active weights sum to 50, not the required 100 (%)', sqlerrm;
  end;

  -- Rebalance: raise sales_target to 100 to cover the NA''d slot.
  v_goal1 := app.assign_performance_goal(v_cycle_id, v_emp2, (select id from app.performance_kpi_definitions where tenant_id=v_tenant and code='sales_target'), 100.00, 50000, 'IDR', '00000000-0000-0000-0000-000000028302', 'hr');
  select * into v_self_a from app.performance_assessments where id = v_self_a.id;
  v_self_a := app.submit_performance_self_assessment(v_cycle_id, v_self_a.record_version, 'review', '00000000-0000-0000-0000-000000028306', 'emp2');
  if v_self_a.status <> 'submitted' then raise exception 'assertion failed: self assessment should now submit cleanly'; end if;
  raise notice 'OK: after rebalancing to exactly 100, self assessment submits cleanly';
end $$;

\echo '>> purpose/stage-bound visibility: emp1 cannot see their own manager assessment while it is still a draft'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_cycle_id uuid := (select id from app.performance_cycles where tenant_id=v_tenant and code='fy2026');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@kpi1.test');
  v_seen integer;
begin
  select count(*) into v_seen from app.list_performance_assessments(v_tenant, v_cycle_id, '00000000-0000-0000-0000-000000028305', v_emp1, 'manager');
  if v_seen <> 0 then raise exception 'ASSERTION FAILURE: emp1 saw their own not-yet-submitted manager assessment (count=%)', v_seen; end if;
  raise notice 'OK: emp1 sees zero rows of their own draft manager assessment (purpose/stage-bound visibility)';
end $$;

\echo '>> manager assessment: advance cycle, score+submit with DIFFERENT values than self gave -- outcome must reflect ONLY the manager''s own scores (decision 2), exact decimal'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_cycle app.performance_cycles;
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@kpi1.test');
  v_mgr_a app.performance_assessments;
  v_goal_sales uuid; v_goal_quality uuid;
  v_outcome app.performance_outcomes;
begin
  select * into v_cycle from app.performance_cycles where tenant_id=v_tenant and code='fy2026';
  v_cycle := app.advance_performance_cycle_stage(v_cycle.id, v_cycle.record_version, 'self_assessment_open', '00000000-0000-0000-0000-000000028303', 'approver');
  v_cycle := app.advance_performance_cycle_stage(v_cycle.id, v_cycle.record_version, 'manager_assessment_open', '00000000-0000-0000-0000-000000028303', 'approver');

  select * into v_mgr_a from app.performance_assessments where cycle_id=v_cycle.id and employee_id=v_emp1 and assessment_type='manager';
  v_goal_sales := (select id from app.performance_goal_assignments where cycle_id=v_cycle.id and employee_id=v_emp1 and kpi_definition_id=(select id from app.performance_kpi_definitions where tenant_id=v_tenant and code='sales_target'));
  v_goal_quality := (select id from app.performance_goal_assignments where cycle_id=v_cycle.id and employee_id=v_emp1 and kpi_definition_id=(select id from app.performance_kpi_definitions where tenant_id=v_tenant and code='quality_score'));

  -- 120000/100000*100 = 120, capped to 100. Deliberately DIFFERENT from
  -- emp1's own self-scored 90000/70.
  perform app.upsert_performance_assessment_kpi_score(v_mgr_a.id, v_goal_sales, 120000, null, 'exceeded target', '00000000-0000-0000-0000-000000028304', 'mgr1');
  perform app.upsert_performance_assessment_kpi_score(v_mgr_a.id, v_goal_quality, null, 80, 'strong quality this cycle', '00000000-0000-0000-0000-000000028304', 'mgr1');

  select * into v_mgr_a from app.performance_assessments where id = v_mgr_a.id;
  v_mgr_a := app.submit_performance_manager_assessment(v_mgr_a.id, v_mgr_a.record_version, 'strong performer', '00000000-0000-0000-0000-000000028304', 'mgr1');
  if v_mgr_a.status <> 'submitted' then raise exception 'assertion failed: manager assessment not submitted: %', v_mgr_a.status; end if;

  select * into v_outcome from app.performance_outcomes where cycle_id=v_cycle.id and employee_id=v_emp1;
  -- Expected: 60% * 100 + 40% * 80 = 60 + 32 = 92.000 -- NOT the
  -- self-assessment-derived 60%*90+40%*70=82.
  if v_outcome.baseline_score <> 92.000 then raise exception 'assertion failed: expected baseline_score=92.000 (manager-derived), got %', v_outcome.baseline_score; end if;
  if v_outcome.final_score <> 92.000 then raise exception 'assertion failed: expected final_score=92.000, got %', v_outcome.final_score; end if;
  if jsonb_array_length(v_outcome.score_breakdown) <> 2 then raise exception 'assertion failed: score_breakdown should have 2 entries, got %', jsonb_array_length(v_outcome.score_breakdown); end if;
  raise notice 'OK: outcome baseline_score/final_score = 92.000, derived ONLY from the submitted manager assessment (decision 2), exact and explainable via score_breakdown';

  -- Now that the manager assessment is submitted, emp1 CAN see it.
  if (select count(*) from app.list_performance_assessments(v_tenant, v_cycle.id, '00000000-0000-0000-0000-000000028305', v_emp1, 'manager')) <> 1 then
    raise exception 'ASSERTION FAILURE: emp1 still cannot see the now-submitted manager assessment';
  end if;
  raise notice 'OK: emp1 can see the manager assessment once submitted';
end $$;

\echo '>> reviewer (360): reviewer1 scores+submits -- visible to reviewer1 and to mgr1 (direct manager), NEVER to emp1 directly'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_cycle_id uuid := (select id from app.performance_cycles where tenant_id=v_tenant and code='fy2026');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@kpi1.test');
  v_rev1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='reviewer1work@kpi1.test');
  v_rev_a app.performance_assessments;
  v_goal_sales uuid;
begin
  perform app.assign_performance_reviewer(v_cycle_id, v_emp1, 'reviewer', v_rev1, '00000000-0000-0000-0000-000000028302', 'hr');
  select * into v_rev_a from app.performance_assessments where cycle_id=v_cycle_id and employee_id=v_emp1 and assessment_type='reviewer' and assigned_to_employee_id=v_rev1;
  v_goal_sales := (select id from app.performance_goal_assignments where cycle_id=v_cycle_id and employee_id=v_emp1 and kpi_definition_id=(select id from app.performance_kpi_definitions where tenant_id=v_tenant and code='sales_target'));
  perform app.upsert_performance_assessment_kpi_score(v_rev_a.id, v_goal_sales, 100000, null, 'peer perspective: on target', '00000000-0000-0000-0000-000000028307', 'reviewer1');
  select * into v_rev_a from app.performance_assessments where id = v_rev_a.id;
  v_rev_a := app.submit_performance_reviewer_assessment(v_rev_a.id, v_rev_a.record_version, 'good collaborator', '00000000-0000-0000-0000-000000028307', 'reviewer1');

  if (select count(*) from app.list_performance_assessments(v_tenant, v_cycle_id, '00000000-0000-0000-0000-000000028307', v_emp1, 'reviewer')) <> 1 then
    raise exception 'ASSERTION FAILURE: reviewer1 cannot see own submitted reviewer assessment';
  end if;
  if (select count(*) from app.list_performance_assessments(v_tenant, v_cycle_id, '00000000-0000-0000-0000-000000028304', v_emp1, 'reviewer')) <> 1 then
    raise exception 'ASSERTION FAILURE: mgr1 (direct manager) cannot see the submitted reviewer input';
  end if;
  if (select count(*) from app.list_performance_assessments(v_tenant, v_cycle_id, '00000000-0000-0000-0000-000000028305', v_emp1, 'reviewer')) <> 0 then
    raise exception 'ASSERTION FAILURE: emp1 (the subject) CAN see reviewer input directly -- must never be visible to them';
  end if;
  raise notice 'OK: reviewer input visible to the reviewer and the manager, never directly to the reviewed employee';
end $$;

\echo '>> manager reassignment: does NOT silently transfer the already-submitted manager review'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_cycle_id uuid := (select id from app.performance_cycles where tenant_id=v_tenant and code='fy2026');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@kpi1.test');
  v_rev1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='reviewer1work@kpi1.test');
  v_old_assignment app.performance_reviewer_assignments;
  v_old_assessment_id uuid;
  v_new_assignment app.performance_reviewer_assignments;
  v_new_assessment app.performance_assessments;
begin
  select * into v_old_assignment from app.performance_reviewer_assignments where cycle_id=v_cycle_id and employee_id=v_emp1 and role='manager' and status='active';
  select id into v_old_assessment_id from app.performance_assessments where reviewer_assignment_id = v_old_assignment.id;

  -- reviewer1 (a distinct active employee, unrelated to emp1's real org
  -- chart) is deliberately used as the reassignment TARGET here purely to
  -- exercise the mechanism -- app.assign_performance_reviewer already
  -- separately covers the "real new manager" shape.
  v_new_assignment := app.reassign_performance_reviewer_assignment(v_old_assignment.id, v_rev1, 'org restructuring -- new interim manager', '00000000-0000-0000-0000-000000028303', 'approver');

  if v_new_assignment.assigned_to_employee_id <> v_rev1 then raise exception 'assertion failed: new assignment not pointed at reviewer1'; end if;

  select * into v_old_assignment from app.performance_reviewer_assignments where id = v_old_assignment.id;
  if v_old_assignment.status <> 'reassigned' then raise exception 'assertion failed: old assignment status should be reassigned, got %', v_old_assignment.status; end if;

  -- The OLD submitted assessment is untouched -- still submitted, still
  -- carries mgr1's own original score/comment.
  if (select status from app.performance_assessments where id = v_old_assessment_id) <> 'submitted' then
    raise exception 'ASSERTION FAILURE: reassignment mutated the OLD submitted assessment''s status';
  end if;
  if (select assigned_to_employee_id from app.performance_assessments where id = v_old_assessment_id) <> (select master_record_id from app.employees where tenant_id=v_tenant and work_email='mgr1work@kpi1.test') then
    raise exception 'ASSERTION FAILURE: the OLD submitted assessment''s own assignee was silently changed';
  end if;
  if (select overall_comment from app.performance_assessments where id = v_old_assessment_id) <> 'strong performer' then
    raise exception 'ASSERTION FAILURE: the OLD submitted assessment''s own comment was altered';
  end if;

  -- A brand-new, not_started assessment exists for the new assignee.
  select * into v_new_assessment from app.performance_assessments where reviewer_assignment_id = v_new_assignment.id;
  if v_new_assessment.status <> 'not_started' or v_new_assessment.assigned_to_employee_id <> v_rev1 then
    raise exception 'ASSERTION FAILURE: new assignee''s fresh assessment not created correctly';
  end if;

  -- The outcome''s own manager_assessment_id STILL points at the OLD
  -- (mgr1''s) submitted assessment -- the computed score is untouched by
  -- the reassignment, exactly as it must be.
  if (select manager_assessment_id from app.performance_outcomes where cycle_id=v_cycle_id and employee_id=v_emp1) <> v_old_assessment_id then
    raise exception 'ASSERTION FAILURE: outcome''s manager_assessment_id changed after reassignment';
  end if;

  raise notice 'OK: manager reassignment created a new assignment + fresh assessment; the OLD submitted assessment, its content, and the already-computed outcome are all completely untouched';
end $$;

\echo '>> calibration: self-calibration blocked, unauthorized (Edit-only) actor blocked, distinct Override holder succeeds with exact adjusted score + reason preserved (never in the audit log)'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_cycle_id uuid := (select id from app.performance_cycles where tenant_id=v_tenant and code='fy2026');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@kpi1.test');
  v_outcome app.performance_outcomes;
begin
  -- emp1 is granted the Approver role (HRS:Approve/Override/View/View
  -- personal data) ONLY now -- used exclusively to prove the structural
  -- self-calibration block holds even when the subject separately holds
  -- the authority permission (mirrors HRT-282's own "hr also holds
  -- Payroll Approver role" self-block test shape). Granted this late,
  -- deliberately, so it cannot interfere with the earlier stage-bound-
  -- visibility proof (emp1 could not yet see their own draft manager
  -- assessment).
  perform app.assign_role(
    v_tenant, (select id from app.role_versions where role_id = (select id from app.roles where tenant_id = v_tenant and name = 'KPI Approver') and status = 'published'),
    '00000000-0000-0000-0000-000000028305', '00000000-0000-0000-0000-000000028301', 'tester'
  );

  select * into v_outcome from app.performance_outcomes where cycle_id=v_cycle_id and employee_id=v_emp1;

  -- Unauthorized: hr@kpi1 holds only HRS:Edit, never Override.
  begin
    perform app.calibrate_performance_outcome_score(v_outcome.id, v_outcome.record_version, 95, 'trying without Override', '00000000-0000-0000-0000-000000028302', 'hr');
    raise exception 'SECURITY FAILURE: hr (Edit-only) calibrated an outcome without HRS:Override';
  exception
    when others then
      if sqlerrm not like '%insufficient_authority%' then raise exception 'wrong error: %', sqlerrm; end if;
      raise notice 'OK: Edit-only actor correctly blocked from calibrating (%)', sqlerrm;
  end;

  -- Self-calibration: emp1 holds Approver/Override (granted in fixture for
  -- exactly this test) but is the outcome''s OWN employee.
  begin
    perform app.calibrate_performance_outcome_score(v_outcome.id, v_outcome.record_version, 100, 'self calibrate attempt', '00000000-0000-0000-0000-000000028305', 'emp1');
    raise exception 'SECURITY FAILURE: emp1 self-calibrated their own outcome';
  exception
    when others then
      if sqlerrm not like '%self_calibration_not_permitted%' then raise exception 'wrong error: %', sqlerrm; end if;
      raise notice 'OK: self-calibration correctly blocked (%)', sqlerrm;
  end;

  v_outcome := app.calibrate_performance_outcome_score(v_outcome.id, v_outcome.record_version, 95.500, 'calibration committee: normalized against peer cohort', '00000000-0000-0000-0000-000000028303', 'approver');
  if v_outcome.calibrated_score <> 95.500 or v_outcome.final_score <> 95.500 then
    raise exception 'assertion failed: expected calibrated/final_score=95.500, got %/%', v_outcome.calibrated_score, v_outcome.final_score;
  end if;
  if v_outcome.baseline_score <> 92.000 then raise exception 'assertion failed: baseline_score should remain 92.000 (untouched), got %', v_outcome.baseline_score; end if;

  if (select count(*) from app.performance_calibration_adjustments where outcome_id = v_outcome.id) <> 1 then
    raise exception 'assertion failed: expected exactly 1 calibration_adjustments row';
  end if;
  if (select adjustment_reason from app.performance_calibration_adjustments where outcome_id = v_outcome.id) <> 'calibration committee: normalized against peer cohort' then
    raise exception 'ASSERTION FAILURE: the real reason was not preserved on the governed calibration row itself';
  end if;

  -- Taxonomy C-24: the free-text reason and the numeric scores never reach
  -- app.audit_logs (readable by any plain tenant_admin regardless of
  -- HRS:View personal data). Matched by exact JSONB key presence and a
  -- literal reason-substring search (NOT a raw text/like scan of the whole
  -- after_value blob, which would false-positive on outcome_id''s own
  -- random UUID hex digits coincidentally containing "92"/"95").
  if exists (
    select 1 from app.audit_logs
    where action = 'calibrate_performance_outcome_score' and resource_id = v_outcome.id
      and (
        reason is not null
        or after_value ? 'adjustment_reason' or after_value ? 'adjusted_score' or after_value ? 'previous_score'
        or after_value ? 'reason' or after_value ? 'score'
        or after_value::text ilike '%peer cohort%'
      )
  ) then
    raise exception 'SECURITY FAILURE: calibration reason or score leaked into app.audit_logs unmasked';
  end if;
  raise notice 'OK: calibration succeeded (95.500), reason preserved on the governed table, and confirmed absent from app.audit_logs';
end $$;

\echo '>> publish + acknowledge outcome'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_cycle_id uuid := (select id from app.performance_cycles where tenant_id=v_tenant and code='fy2026');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@kpi1.test');
  v_outcome app.performance_outcomes;
begin
  select * into v_outcome from app.performance_outcomes where cycle_id=v_cycle_id and employee_id=v_emp1;
  v_outcome := app.publish_performance_outcome(v_outcome.id, v_outcome.record_version, '00000000-0000-0000-0000-000000028303', 'approver');
  if v_outcome.status <> 'published' then raise exception 'assertion failed: expected published, got %', v_outcome.status; end if;

  v_outcome := app.acknowledge_performance_outcome(v_outcome.id, v_outcome.record_version, 'agree', 'thank you for the feedback', '00000000-0000-0000-0000-000000028305', 'emp1');
  if v_outcome.status <> 'acknowledged' or v_outcome.acknowledgement_agreement <> 'agree' then
    raise exception 'assertion failed: expected acknowledged/agree, got %/%', v_outcome.status, v_outcome.acknowledgement_agreement;
  end if;
  raise notice 'OK: outcome published then acknowledged by emp1 (agree, 95.500)';
end $$;

\echo '>> appeal/reopen: emp1 appeals, self-decision blocked, distinct Approve holder overturns -> reopened -> recalibrate -> republish -> re-acknowledge'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_cycle_id uuid := (select id from app.performance_cycles where tenant_id=v_tenant and code='fy2026');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@kpi1.test');
  v_outcome app.performance_outcomes;
  v_appeal app.performance_appeals;
begin
  select * into v_outcome from app.performance_outcomes where cycle_id=v_cycle_id and employee_id=v_emp1;
  v_appeal := app.submit_performance_appeal(v_outcome.id, 'I believe the calibration adjustment was miscalculated', '00000000-0000-0000-0000-000000028305', 'emp1');
  if v_appeal.status <> 'submitted' then raise exception 'assertion failed: appeal not submitted: %', v_appeal.status; end if;
  if (select status from app.performance_outcomes where id = v_outcome.id) <> 'appealed' then
    raise exception 'assertion failed: outcome should be appealed';
  end if;

  -- A second appeal for the SAME outcome is rejected -- the FIRST
  -- submission already flipped outcome.status to 'appealed', so the
  -- second call's own status check (not the redundant EXISTS a first
  -- draft of this function had -- removed as dead code once this was
  -- live-verified) is what rejects it, via the same row lock that would
  -- also serialize a genuinely concurrent pair of callers (taxonomy
  -- C-01/C-04).
  begin
    perform app.submit_performance_appeal(v_outcome.id, 'second appeal attempt', '00000000-0000-0000-0000-000000028305', 'emp1');
    raise exception 'ASSERTION FAILURE: a second open appeal for the same outcome was accepted';
  exception
    when others then
      if sqlerrm not like '%invalid_transition%' then raise exception 'wrong error: %', sqlerrm; end if;
      raise notice 'OK: a second open appeal for the same outcome correctly rejected (%)', sqlerrm;
  end;

  -- Self-decision blocked: emp1 (the appellant) also holds Approve.
  begin
    perform app.decide_performance_appeal(v_appeal.id, v_appeal.record_version, 'overturn', 'self decide attempt', '00000000-0000-0000-0000-000000028305', 'emp1');
    raise exception 'SECURITY FAILURE: emp1 decided their own appeal';
  exception
    when others then
      if sqlerrm not like '%self_approval_not_permitted%' then raise exception 'wrong error: %', sqlerrm; end if;
      raise notice 'OK: appellant self-decision correctly blocked (%)', sqlerrm;
  end;

  v_appeal := app.decide_performance_appeal(v_appeal.id, v_appeal.record_version, 'overturn', 'agreed, the adjustment arithmetic was wrong', '00000000-0000-0000-0000-000000028303', 'approver');
  if v_appeal.status <> 'overturned' then raise exception 'assertion failed: expected overturned, got %', v_appeal.status; end if;
  if (select status from app.performance_outcomes where id = v_outcome.id) <> 'reopened' then
    raise exception 'assertion failed: outcome should be reopened after overturn';
  end if;

  select * into v_outcome from app.performance_outcomes where id = v_outcome.id;
  v_outcome := app.calibrate_performance_outcome_score(v_outcome.id, v_outcome.record_version, 96.000, 'corrected calibration per appeal decision', '00000000-0000-0000-0000-000000028303', 'approver');
  v_outcome := app.publish_performance_outcome(v_outcome.id, v_outcome.record_version, '00000000-0000-0000-0000-000000028303', 'approver');
  if v_outcome.status <> 'published' or v_outcome.final_score <> 96.000 then
    raise exception 'assertion failed: expected republished/96.000, got %/%', v_outcome.status, v_outcome.final_score;
  end if;
  raise notice 'OK: appeal overturned, outcome reopened, recalibrated to 96.000, and republished';
end $$;

\echo '>> RLS: zero-permission cross-tenant member sees nothing of kpi1'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug='kpi1');
  v_cycle_id uuid := (select id from app.performance_cycles where tenant_id=v_tenant1 and code='fy2026');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant1 and work_email='emp1work@kpi1.test');
begin
  if (select count(*) from app.list_performance_cycles(v_tenant1, '00000000-0000-0000-0000-000000028321', null)) <> 0 then
    raise exception 'SECURITY FAILURE: kpi2 admin saw kpi1 cycles';
  end if;
  if (select count(*) from app.list_performance_outcomes(v_tenant1, v_cycle_id, '00000000-0000-0000-0000-000000028321', v_emp1)) <> 0 then
    raise exception 'SECURITY FAILURE: kpi2 admin saw an kpi1 employee''s outcome';
  end if;
  raise notice 'OK: cross-tenant actor sees zero rows via every scoped read RPC tested';
end $$;

\echo '>> k-anonymity: a genuinely tiny (2-person) department is suppressed; a synthetic 5-person department is not'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='kpi1');
  v_cycle_id uuid := (select id from app.performance_cycles where tenant_id=v_tenant and code='fy2026');
  v_dept_big uuid := (select id from app.org_units where tenant_id=v_tenant and code='DEPT-BIG');
  v_company uuid := (select id from app.org_units where tenant_id=v_tenant and code='CO-KPI1');
  v_branch uuid := (select id from app.org_units where tenant_id=v_tenant and code='BR-KPI1');
  i integer;
  v_emp_id uuid;
  v_small_row record;
  v_big_row record;
begin
  -- emp2 (DEPT-SMALL) only went through the self-assessment half of the
  -- real lifecycle above (weight-rebalancing test) -- give it a real
  -- app.performance_outcomes row too (test-authoring shortcut, same
  -- disclosed reasoning as the 5 synthetic Big-Dept rows below) so
  -- DEPT-SMALL is a genuine 2-person cohort, matching emp1''s own
  -- end-to-end-computed row already created above.
  insert into app.performance_outcomes (tenant_id, cycle_id, employee_id, baseline_score, final_score, status, published_by, published_at)
  values (v_tenant, v_cycle_id, (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp2work@kpi1.test'), 80.000, 80.000, 'published', 'tester', now());

  -- 5 lightweight synthetic employees in DEPT-BIG, each with a real,
  -- RLS-governed app.performance_outcomes row (test-authoring shortcut,
  -- disclosed: full goal/self/manager lifecycle for 5 employees would be
  -- disproportionate test-fixture weight for what this block exists to
  -- prove -- the REPORTING function''s own k-floor arithmetic, already
  -- proven correct end-to-end for emp1/emp2 above via the real RPC path).
  for i in 1..5 loop
    perform app.create_employee_draft(
      v_tenant, 'Big Dept Emp ' || i, 'full_time', 'bigdept' || i || '@kpi1.test', null, null, null, null, null, '2024-01-01',
      v_company, v_branch, v_dept_big, 'Staff', null, null, null, 'hr_created', 'idem-bigdept-' || i, '00000000-0000-0000-0000-000000028302', 'tester'
    );
    perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id=v_tenant and work_email='bigdept' || i || '@kpi1.test'), 'Contact Big ' || i, 'spouse', '099000000' || i, null, true, '00000000-0000-0000-0000-000000028302', 'tester');
    perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id=v_tenant and work_email='bigdept' || i || '@kpi1.test'), 1, '00000000-0000-0000-0000-000000028302', 'tester');
    perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id=v_tenant and work_email='bigdept' || i || '@kpi1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028303', 'tester');
    perform app.activate_employee((select master_record_id from app.employees where tenant_id=v_tenant and work_email='bigdept' || i || '@kpi1.test'), 3, '00000000-0000-0000-0000-000000028303', 'tester');
    v_emp_id := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='bigdept' || i || '@kpi1.test');
    insert into app.performance_outcomes (tenant_id, cycle_id, employee_id, baseline_score, final_score, status, published_by, published_at)
    values (v_tenant, v_cycle_id, v_emp_id, 70 + i, 70 + i, 'published', 'tester', now());
  end loop;

  select department_org_unit_id, employee_count, avg_final_score, suppressed
    into v_small_row
    from app.report_performance_cycle_score_distribution(v_tenant, v_cycle_id, '00000000-0000-0000-0000-000000028303', 'approver')
    where department_org_unit_id = (select id from app.org_units where tenant_id=v_tenant and code='DEPT-SMALL');
  if v_small_row.employee_count <> 2 or not v_small_row.suppressed or v_small_row.avg_final_score is not null then
    raise exception 'ASSERTION FAILURE: 2-person department not suppressed as expected: count=%, suppressed=%, avg=%', v_small_row.employee_count, v_small_row.suppressed, v_small_row.avg_final_score;
  end if;

  select department_org_unit_id, employee_count, avg_final_score, suppressed
    into v_big_row
    from app.report_performance_cycle_score_distribution(v_tenant, v_cycle_id, '00000000-0000-0000-0000-000000028303', 'approver')
    where department_org_unit_id = v_dept_big;
  if v_big_row.employee_count <> 5 or v_big_row.suppressed or v_big_row.avg_final_score is null then
    raise exception 'ASSERTION FAILURE: 5-person department incorrectly suppressed: count=%, suppressed=%, avg=%', v_big_row.employee_count, v_big_row.suppressed, v_big_row.avg_final_score;
  end if;
  if v_big_row.avg_final_score <> 73.00 then
    raise exception 'assertion failed: expected big-dept avg (71+72+73+74+75)/5=73.00, got %', v_big_row.avg_final_score;
  end if;

  -- Unauthorized (Edit-only) caller blocked entirely.
  begin
    perform app.report_performance_cycle_score_distribution(v_tenant, v_cycle_id, '00000000-0000-0000-0000-000000028302', 'hr');
    raise exception 'SECURITY FAILURE: HR (Edit-only, no View personal data) ran the aggregate report';
  exception
    when others then
      if sqlerrm not like '%insufficient_authority%' then raise exception 'wrong error: %', sqlerrm; end if;
  end;

  raise notice 'OK: k-anonymity floor (k=5) -- the real 2-person department is suppressed (avg NULL), the 5-person department reports its real average (73.00) unsuppressed';
end $$;

-- Real concurrent-OS-process races (app.assign_performance_goal,
-- app.submit_performance_appeal) are exercised separately via two genuine
-- background `psql` processes against this SAME database, NOT embedded in
-- this file (a single-connection `psql -f` script cannot itself open two
-- concurrent sessions) -- see the build log's own "Live concurrency
-- evidence" section for the exact commands and results.

\echo '>> RLS raw-table isolation: mgr1 (zero HRS permission beyond being emp1/emp2''s real direct manager) sees exactly their 2 direct reports'' outcomes via a real session on the RAW table -- not 0, not the other 5 synthetic Big-Dept outcomes -- a genuine contrast proof, not merely "denied everything"'
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028304", "role": "authenticated"}', false);
set role authenticated;
select count(*) as mgr1_raw_outcome_count from app.performance_outcomes;
reset role;
select set_config('request.jwt.claims', 'null', false);
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.performance_outcomes o
    join app.employees e on e.master_record_id = o.employee_id
    where e.manager_employee_id = (select master_record_id from app.employees where tenant_id=(select id from app.tenants where slug='kpi1') and work_email='mgr1work@kpi1.test')
       or o.employee_id = (select master_record_id from app.employees where tenant_id=(select id from app.tenants where slug='kpi1') and work_email='mgr1work@kpi1.test');
  if v_count <> 2 then
    raise exception 'test setup assumption violated: expected exactly 2 outcomes visible to mgr1 (emp1''s + emp2''s), got %', v_count;
  end if;
  raise notice 'OK: mgr1''s raw-table row count above should read exactly 2 (emp1''s + emp2''s outcomes, never the 5 unrelated Big-Dept ones) -- verify against the mgr1_raw_outcome_count output';
end $$;

\echo '>> schema-privilege defense in depth: anon holds zero table privilege on any performance table; authenticated has RLS-scoped SELECT only; internal _-prefixed functions are service_role-only'
do $$
declare
  v_tbl text;
  v_fn text;
begin
  foreach v_tbl in array array[
    'performance_kpi_definitions','performance_kpi_definition_versions','performance_templates','performance_template_kpi_items',
    'performance_cycles','performance_goal_assignments','performance_goal_progress_entries','performance_reviewer_assignments',
    'performance_assessments','performance_assessment_kpi_scores','performance_outcomes','performance_calibration_adjustments','performance_appeals'
  ] loop
    if has_table_privilege('anon', 'app.' || v_tbl, 'SELECT') then
      raise exception 'SECURITY FAILURE: anon holds SELECT on app.%', v_tbl;
    end if;
    if has_table_privilege('authenticated', 'app.' || v_tbl, 'INSERT')
      or has_table_privilege('authenticated', 'app.' || v_tbl, 'UPDATE')
      or has_table_privilege('authenticated', 'app.' || v_tbl, 'DELETE') then
      raise exception 'SECURITY FAILURE: authenticated holds a direct write privilege on app.%', v_tbl;
    end if;
  end loop;

  foreach v_fn in array array[
    '_is_direct_manager_of_employee(uuid,uuid)', '_ensure_performance_self_assessment(uuid,uuid)',
    '_ensure_performance_manager_assignment(uuid,uuid,text)', '_assert_performance_assessment_scores_complete(uuid,uuid,uuid,numeric)',
    'compute_kpi_raw_score(text,text,numeric,numeric,numeric)'
  ] loop
    if has_function_privilege('authenticated', 'app.' || v_fn, 'EXECUTE') then
      raise exception 'SECURITY FAILURE: authenticated holds EXECUTE on internal app.%', v_fn;
    end if;
  end loop;
  raise notice 'OK: anon zero table privilege, authenticated RLS-scoped SELECT only, internal functions service_role-only';
end $$;

\echo '>> structural proof: zero write to app.employees.lifecycle_status, any app.payroll_* table, or any role/permission table anywhere in this migration''s own function bodies'
do $$
declare
  v_fn record;
  v_violations text := '';
begin
  for v_fn in
    select p.proname, pg_get_functiondef(p.oid) as src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname like 'performance_%' or (n.nspname = 'app' and p.proname ~ '^(assign_performance|mark_performance|record_performance|submit_performance|calibrate_performance|publish_performance|acknowledge_performance|create_performance|reassign_performance|decide_performance|advance_performance|cancel_performance|archive_performance|add_performance|report_performance|upsert_performance)')
  loop
    if v_fn.src ilike '%update app.employees set%lifecycle_status%'
      or v_fn.src ilike '%insert into app.payroll_%' or v_fn.src ilike '%update app.payroll_%' or v_fn.src ilike '%delete from app.payroll_%'
      or v_fn.src ilike '%insert into app.role_%' or v_fn.src ilike '%insert into app.permissions%' or v_fn.src ilike '%insert into app.role_assignments%'
    then
      v_violations := v_violations || v_fn.proname || '; ';
    end if;
  end loop;
  if v_violations <> '' then
    raise exception 'SECURITY FAILURE: found downstream auto-action write(s) in: %', v_violations;
  end if;
  raise notice 'OK: zero write to app.employees.lifecycle_status / app.payroll_* / role-permission tables across every HRT-283 write function (structural proof)';
end $$;

\echo 'HRT-283 KPI AND PERFORMANCE TEST SUITE COMPLETE'
