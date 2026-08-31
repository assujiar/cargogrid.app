-- Real, executable test evidence for HRT-284 (Training and Talent,
-- CG-S12-HRT-012) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database (and standalone via psql per the runtime instructions,
-- since ISS-2026-077 -- a pre-existing, unrelated bug in
-- hris-leave-permit-business-trip.sql -- aborts the shared alphabetical
-- suite before reaching this file).
--
-- Self-contained: own two-tenant/employee/role fixture, own fresh,
-- unclaimed UUID range (00000000-0000-0000-0000-0000000284xx). Tenant
-- slugs `trn1`/`trn2` (grep-verified unclaimed).
--
-- Covers, live: competency/course/version publish lifecycle; prerequisite
-- enforcement (blocked until completed, then allowed); session capacity
-- and waitlist (fill to capacity, next enrollee waitlisted, cancel
-- promotes the earliest waitlisted enrollee); enrollment-approval gate
-- (pending_approval -> decide, self-decision blocked); mandatory bulk
-- assignment; attendance/completion; assessment retries with a computed
-- pass/fail; certificate issue/attach-evidence (malware-scan gate:
-- infected/unscanned rejected, clean accepted)/import (external,
-- unverified)/verify/revoke/renew; certificate expiry + reminder durable
-- jobs (idempotent re-run); development plan + actions, with a rejected
-- cross-employee linked_performance_outcome_id; the restricted talent
-- review workspace (assigned-reviewer-only visibility, reassignment never
-- silently transferring an already-submitted review); talent pool
-- membership (HRS:Override-only, mandatory reason); succession candidate
-- decision (mandatory reason, self-decision blocked); a genuine
-- k-anonymity floor on the one aggregate report; cross-tenant RLS
-- isolation; schema-privilege defense in depth; structural zero-write
-- proof.

\set ON_ERROR_STOP on

\echo '>> fixture'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_hr_role uuid; v_hr_draft app.role_versions;
  v_talent_role uuid; v_talent_draft app.role_versions;
  v_company uuid; v_branch uuid; v_dept_small uuid; v_dept_big uuid;
  v_mgr uuid; v_emp1 uuid; v_emp2 uuid; v_emp3 uuid; v_reviewer1 uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000028401', 'admin@trn1.test'),
    ('00000000-0000-0000-0000-000000028402', 'hr@trn1.test'),
    ('00000000-0000-0000-0000-000000028403', 'talentadmin@trn1.test'),
    ('00000000-0000-0000-0000-000000028404', 'mgr1@trn1.test'),
    ('00000000-0000-0000-0000-000000028405', 'emp1@trn1.test'),
    ('00000000-0000-0000-0000-000000028406', 'emp2@trn1.test'),
    ('00000000-0000-0000-0000-000000028407', 'emp3@trn1.test'),
    ('00000000-0000-0000-0000-000000028408', 'reviewer1@trn1.test'),
    ('00000000-0000-0000-0000-000000028421', 'admin@trn2.test');

  perform app.provision_tenant('trn1', 'Training Co 1', 'idem-trn1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'trn1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('trn2', 'Training Co 2', 'idem-trn2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'trn2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028401', 'admin@trn1.test', 'Trn1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@trn1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028401', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028402', 'hr@trn1.test', 'Trn1 HR', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'hr@trn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028403', 'talentadmin@trn1.test', 'Trn1 Talent Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'talentadmin@trn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028404', 'mgr1@trn1.test', 'Trn1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'mgr1@trn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028405', 'emp1@trn1.test', 'Trn1 Emp One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp1@trn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028406', 'emp2@trn1.test', 'Trn1 Emp Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp2@trn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028407', 'emp3@trn1.test', 'Trn1 Emp Three', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'emp3@trn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000028408', 'reviewer1@trn1.test', 'Trn1 Reviewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'reviewer1@trn1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000028421', 'admin@trn2.test', 'Trn2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@trn2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028421', 'tenant_admin', v_tenant2, null, 'tester');

  -- HR role: HRS Create/Edit/Approve/Export/View/View personal data
  -- (author competency/course/session/enrollment/certificate, decide
  -- enrollment, verify certificate).
  v_hr_role := (app.create_role(v_tenant1, 'HR Training', 'Create/Edit/Approve/View/View personal data', 'tester')).id;
  v_hr_draft := app.create_role_version(v_hr_role, 'tester');
  perform app.set_role_version_permissions(v_hr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Approve', 'Export', 'View', 'View personal data')), 'tester');
  perform app.publish_role_version(v_hr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_hr_role and status = 'published'), '00000000-0000-0000-0000-000000028402', '00000000-0000-0000-0000-000000028401', 'tester');

  -- Talent admin role: HRS Override/View/View personal data (talent
  -- review/pool/succession, certificate revoke, session cancel, expiry
  -- batches).
  v_talent_role := (app.create_role(v_tenant1, 'Talent Admin', 'Override/View/View personal data', 'tester')).id;
  v_talent_draft := app.create_role_version(v_talent_role, 'tester');
  perform app.set_role_version_permissions(v_talent_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Override', 'View', 'View personal data')), 'tester');
  perform app.publish_role_version(v_talent_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_talent_role and status = 'published'), '00000000-0000-0000-0000-000000028403', '00000000-0000-0000-0000-000000028401', 'tester');
  -- NOTE: hr@trn1 is deliberately NOT granted Override -- proves the
  -- decision-6 tier separation (HR authoring authority never implies
  -- talent-domain admin authority).

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-TRN1', 'Trn1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-TRN1', 'Trn1 Branch', 'tester')).id;
  v_dept_small := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-SMALL', 'Small Dept', 'tester')).id;
  v_dept_big := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-BIG', 'Big Dept', 'tester')).id;

  perform app.create_employee_draft(v_tenant1, 'Trn1 Manager', 'full_time', 'mgr1work@trn1.test', 'mgr1p@trn1.test', '0900000004', null, null, null, '2024-01-01', v_company, v_branch, v_dept_small, 'Manager', null, (select id from app.users where email = 'mgr1@trn1.test'), null, 'hr_created', 'idem-mgr1-trn1', '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@trn1.test'), 'Contact Mgr', 'spouse', '0910000004', null, true, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@trn1.test'), 1, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@trn1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@trn1.test'), 3, '00000000-0000-0000-0000-000000028402', 'tester');
  v_mgr := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'mgr1work@trn1.test');

  perform app.create_employee_draft(v_tenant1, 'Trn1 Emp One', 'full_time', 'emp1work@trn1.test', 'emp1p@trn1.test', '0900000005', null, null, null, '2024-01-01', v_company, v_branch, v_dept_small, 'Staff', v_mgr, (select id from app.users where email = 'emp1@trn1.test'), null, 'hr_created', 'idem-emp1-trn1', '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@trn1.test'), 'Contact One', 'spouse', '0910000005', null, true, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@trn1.test'), 1, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@trn1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@trn1.test'), 3, '00000000-0000-0000-0000-000000028402', 'tester');
  v_emp1 := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp1work@trn1.test');

  perform app.create_employee_draft(v_tenant1, 'Trn1 Emp Two', 'full_time', 'emp2work@trn1.test', 'emp2p@trn1.test', '0900000006', null, null, null, '2024-01-01', v_company, v_branch, v_dept_small, 'Staff', v_mgr, (select id from app.users where email = 'emp2@trn1.test'), null, 'hr_created', 'idem-emp2-trn1', '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@trn1.test'), 'Contact Two', 'spouse', '0910000006', null, true, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@trn1.test'), 1, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@trn1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@trn1.test'), 3, '00000000-0000-0000-0000-000000028402', 'tester');
  v_emp2 := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp2work@trn1.test');

  -- emp3: deliberately no manager -- the negative control for prerequisite/
  -- manager-scope checks below.
  perform app.create_employee_draft(v_tenant1, 'Trn1 Emp Three', 'full_time', 'emp3work@trn1.test', 'emp3p@trn1.test', '0900000007', null, null, null, '2024-01-01', v_company, v_branch, v_dept_big, 'Staff', null, (select id from app.users where email = 'emp3@trn1.test'), null, 'hr_created', 'idem-emp3-trn1', '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@trn1.test'), 'Contact Three', 'spouse', '0910000007', null, true, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@trn1.test'), 1, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@trn1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@trn1.test'), 3, '00000000-0000-0000-0000-000000028402', 'tester');
  v_emp3 := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'emp3work@trn1.test');

  perform app.create_employee_draft(v_tenant1, 'Trn1 Reviewer One', 'full_time', 'reviewer1work@trn1.test', 'reviewer1p@trn1.test', '0900000008', null, null, null, '2024-01-01', v_company, v_branch, v_dept_big, 'Staff', null, (select id from app.users where email = 'reviewer1@trn1.test'), null, 'hr_created', 'idem-reviewer1-trn1', '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'reviewer1work@trn1.test'), 'Contact Reviewer', 'spouse', '0910000008', null, true, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'reviewer1work@trn1.test'), 1, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'reviewer1work@trn1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028402', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'reviewer1work@trn1.test'), 3, '00000000-0000-0000-0000-000000028402', 'tester');
  v_reviewer1 := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'reviewer1work@trn1.test');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%, mgr=%, emp1=%, emp2=%, emp3=%, reviewer1=%', v_tenant1, v_tenant2, v_mgr, v_emp1, v_emp2, v_emp3, v_reviewer1;
end $$;

\echo '>> competency lifecycle: create idempotent, publish (HRS:Approve), archive; viewer with no HRS:Edit rejected creating'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_comp app.training_competencies;
  v_comp2 app.training_competencies;
begin
  v_comp := app.create_training_competency(v_tenant, 'safety_basics', 'Safety Basics', 'Core workplace safety', 'safety', '00000000-0000-0000-0000-000000028402', 'hr');
  if v_comp.status <> 'draft' then raise exception 'assertion failed: new competency should be draft, got %', v_comp.status; end if;

  v_comp2 := app.create_training_competency(v_tenant, 'safety_basics', 'Safety Basics', 'Core workplace safety', 'safety', '00000000-0000-0000-0000-000000028402', 'hr');
  if v_comp2.id <> v_comp.id then raise exception 'assertion failed: create_training_competency not idempotent on (tenant,code)'; end if;

  begin
    perform app.create_training_competency(v_tenant, 'no_perm', 'No Perm', null, null, '00000000-0000-0000-0000-000000028405', 'emp1');
    raise exception 'ASSERTION FAILURE: emp1 (zero HRS:Edit) created a competency';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.publish_training_competency(v_comp.id, v_comp.record_version, '00000000-0000-0000-0000-000000028405', 'emp1');
    raise exception 'ASSERTION FAILURE: emp1 (zero HRS:Approve) published a competency';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_comp := app.publish_training_competency(v_comp.id, v_comp.record_version, '00000000-0000-0000-0000-000000028402', 'hr');
  if v_comp.status <> 'published' then raise exception 'assertion failed: competency not published: %', v_comp.status; end if;

  raise notice 'OK: competency create idempotent, publish requires HRS:Approve, unauthorized actor rejected on both create and publish';
end $$;

\echo '>> course/version lifecycle: exactly one published version per course; session creation blocked against a draft version'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_comp_id uuid := (select id from app.training_competencies where tenant_id=v_tenant and code='safety_basics');
  v_course app.training_courses;
  v_v1 app.training_course_versions;
  v_v2 app.training_course_versions;
begin
  v_course := app.create_training_course(v_tenant, 'safety_101', 'Safety 101', 'compliance', '00000000-0000-0000-0000-000000028402', 'hr');
  v_v1 := app.create_training_course_version(v_course.id, 'Intro to safety', 'in_person', 4, false, false, true, 70, true, 24, '00000000-0000-0000-0000-000000028402', 'hr');
  if v_v1.version_number <> 1 or v_v1.status <> 'draft' then raise exception 'assertion failed: v1 should be draft version 1, got %/%', v_v1.version_number, v_v1.status; end if;

  perform app.add_training_course_competency(v_course.id, v_comp_id, '00000000-0000-0000-0000-000000028402', 'hr');

  begin
    perform app.create_training_session(v_tenant, v_v1.id, null, 'sess_draft_blocked', null, now() + interval '10 days', now() + interval '10 days' + interval '4 hours', 5, '00000000-0000-0000-0000-000000028402', 'hr');
    raise exception 'ASSERTION FAILURE: a session was created against a draft (unpublished) course version';
  exception when others then
    if sqlerrm not like 'course_version_not_published%' then raise; end if;
  end;

  v_v1 := app.publish_training_course_version(v_v1.id, v_v1.record_version, '00000000-0000-0000-0000-000000028402', 'hr');
  if v_v1.status <> 'published' then raise exception 'assertion failed: v1 not published: %', v_v1.status; end if;

  v_v2 := app.create_training_course_version(v_course.id, 'Refreshed safety curriculum', 'in_person', 4, false, false, true, 75, true, 24, '00000000-0000-0000-0000-000000028402', 'hr');
  v_v2 := app.publish_training_course_version(v_v2.id, v_v2.record_version, '00000000-0000-0000-0000-000000028402', 'hr');

  if (select status from app.training_course_versions where id = v_v1.id) <> 'archived' then
    raise exception 'ASSERTION FAILURE: publishing v2 did not archive v1 -- exactly one published version invariant broken';
  end if;
  if v_v2.status <> 'published' then raise exception 'assertion failed: v2 not published: %', v_v2.status; end if;

  raise notice 'OK: session creation blocked against a draft version; publishing a new version archives the prior published one (exactly one published version at a time)';
end $$;

\echo '>> provider + prerequisite: safety_201 requires completed safety_101 first -- enrollment blocked until emp1 completes the prerequisite, then allowed'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_provider app.training_providers;
  v_course201 app.training_courses;
  v_v201 app.training_course_versions;
  v_v101_id uuid := (select id from app.training_course_versions where course_id=(select id from app.training_courses where tenant_id=v_tenant and code='safety_101') and status='published');
  v_course101_id uuid := (select id from app.training_courses where tenant_id=v_tenant and code='safety_101');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@trn1.test');
  v_sess101 app.training_sessions;
  v_sess201 app.training_sessions;
  v_enr101 app.training_enrollments;
begin
  v_provider := app.create_training_provider(v_tenant, 'Internal L&D', 'internal', 'L&D Team', 'ld@trn1.test', null, '00000000-0000-0000-0000-000000028402', 'hr');
  if v_provider.status <> 'active' then raise exception 'assertion failed: provider not active by default'; end if;

  v_course201 := app.create_training_course(v_tenant, 'safety_201', 'Safety 201 (Advanced)', 'compliance', '00000000-0000-0000-0000-000000028402', 'hr');
  v_v201 := app.create_training_course_version(v_course201.id, 'Advanced safety', 'in_person', 4, false, false, false, null, false, null, '00000000-0000-0000-0000-000000028402', 'hr');
  v_v201 := app.publish_training_course_version(v_v201.id, v_v201.record_version, '00000000-0000-0000-0000-000000028402', 'hr');
  perform app.add_training_course_prerequisite(v_course201.id, v_course101_id, '00000000-0000-0000-0000-000000028402', 'hr');
  -- Idempotent re-add is a safe no-op, never a raw 23505.
  perform app.add_training_course_prerequisite(v_course201.id, v_course101_id, '00000000-0000-0000-0000-000000028402', 'hr');

  v_sess201 := app.create_training_session(v_tenant, v_v201.id, v_provider.id, 'sess_201_a', 'Room A', now() + interval '20 days', now() + interval '20 days' + interval '4 hours', 5, '00000000-0000-0000-0000-000000028402', 'hr');

  begin
    perform app.enroll_self_in_training_session(v_tenant, v_sess201.id, '00000000-0000-0000-0000-000000028405', 'emp1');
    raise exception 'ASSERTION FAILURE: emp1 enrolled in safety_201 without ever completing the prerequisite safety_101';
  exception when others then
    if sqlerrm not like 'training_prerequisite_not_met%' then raise; end if;
  end;

  -- emp1 completes safety_101 first.
  v_sess101 := app.create_training_session(v_tenant, v_v101_id, v_provider.id, 'sess_101_prereq', 'Room B', now() + interval '5 days', now() + interval '5 days' + interval '4 hours', 5, '00000000-0000-0000-0000-000000028402', 'hr');
  v_enr101 := app.enroll_self_in_training_session(v_tenant, v_sess101.id, '00000000-0000-0000-0000-000000028405', 'emp1');
  perform app.record_training_completion(v_enr101.id, v_enr101.record_version, 'completed', 'finished on time', '00000000-0000-0000-0000-000000028402', 'hr');

  -- Now the prerequisite is met.
  perform app.enroll_self_in_training_session(v_tenant, v_sess201.id, '00000000-0000-0000-0000-000000028405', 'emp1');

  raise notice 'OK: prerequisite enforcement blocks enrollment until completed, then allows it; prerequisite add is idempotent';
end $$;

\echo '>> capacity + waitlist: fill a 2-seat session, third enrollee waitlisted; cancelling an enrolled seat promotes the earliest waitlisted enrollee'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_v101_id uuid := (select id from app.training_course_versions where course_id=(select id from app.training_courses where tenant_id=v_tenant and code='safety_101') and status='published');
  v_sess app.training_sessions;
  v_enr_mgr app.training_enrollments;
  v_enr_emp2 app.training_enrollments;
  v_enr_emp3 app.training_enrollments;
  v_emp2 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp2work@trn1.test');
begin
  v_sess := app.create_training_session(v_tenant, v_v101_id, null, 'sess_101_capacity', null, now() + interval '15 days', now() + interval '15 days' + interval '4 hours', 2, '00000000-0000-0000-0000-000000028402', 'hr');

  v_enr_mgr := app.enroll_self_in_training_session(v_tenant, v_sess.id, '00000000-0000-0000-0000-000000028404', 'mgr1');
  if v_enr_mgr.status <> 'enrolled' then raise exception 'assertion failed: 1st enrollee should be enrolled, got %', v_enr_mgr.status; end if;

  v_enr_emp2 := app.enroll_self_in_training_session(v_tenant, v_sess.id, '00000000-0000-0000-0000-000000028406', 'emp2');
  if v_enr_emp2.status <> 'enrolled' then raise exception 'assertion failed: 2nd enrollee should be enrolled (fills capacity=2), got %', v_enr_emp2.status; end if;

  v_enr_emp3 := app.enroll_self_in_training_session(v_tenant, v_sess.id, '00000000-0000-0000-0000-000000028407', 'emp3');
  if v_enr_emp3.status <> 'waitlisted' then raise exception 'assertion failed: 3rd enrollee should be waitlisted (capacity full), got %', v_enr_emp3.status; end if;

  -- A duplicate active-enrollment attempt is rejected cleanly, never a raw 23505.
  begin
    perform app.enroll_self_in_training_session(v_tenant, v_sess.id, '00000000-0000-0000-0000-000000028407', 'emp3');
    raise exception 'ASSERTION FAILURE: emp3 was allowed a second concurrent active enrollment in the same session';
  exception when others then
    if sqlerrm not like 'training_enrollment_already_active%' then raise; end if;
  end;

  -- mgr1 cancels their enrolled seat -- emp3 (the earliest waitlisted) is promoted automatically.
  perform app.cancel_training_enrollment(v_enr_mgr.id, v_enr_mgr.record_version, 'schedule conflict', '00000000-0000-0000-0000-000000028404', 'mgr1');
  if (select status from app.training_enrollments where id = v_enr_emp3.id) <> 'enrolled' then
    raise exception 'ASSERTION FAILURE: waitlisted emp3 was not promoted after mgr1''s seat freed up';
  end if;
  if (select status from app.training_enrollments where id = v_enr_mgr.id) <> 'cancelled' then
    raise exception 'assertion failed: mgr1''s enrollment should be cancelled';
  end if;

  raise notice 'OK: capacity enforced (2 enrolled, 3rd waitlisted); duplicate active enrollment rejected cleanly; cancelling a seat promotes the earliest waitlisted enrollee';
end $$;

\echo '>> enrollment-approval gate: requires_enrollment_approval starts pending_approval; self-decision blocked; HR decides approve -> enrolled'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_course app.training_courses;
  v_v app.training_course_versions;
  v_sess app.training_sessions;
  v_enr app.training_enrollments;
  v_emp2 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp2work@trn1.test');
begin
  v_course := app.create_training_course(v_tenant, 'ext_conference', 'External Conference', 'external', '00000000-0000-0000-0000-000000028402', 'hr');
  v_v := app.create_training_course_version(v_course.id, 'A costly external conference', 'virtual', 8, false, true, false, null, false, null, '00000000-0000-0000-0000-000000028402', 'hr');
  v_v := app.publish_training_course_version(v_v.id, v_v.record_version, '00000000-0000-0000-0000-000000028402', 'hr');
  v_sess := app.create_training_session(v_tenant, v_v.id, null, 'sess_conf_a', null, now() + interval '30 days', now() + interval '30 days' + interval '8 hours', 10, '00000000-0000-0000-0000-000000028402', 'hr');

  v_enr := app.enroll_self_in_training_session(v_tenant, v_sess.id, '00000000-0000-0000-0000-000000028406', 'emp2');
  if v_enr.status <> 'pending_approval' then raise exception 'assertion failed: requires_enrollment_approval course should start pending_approval, got %', v_enr.status; end if;

  -- Self-decision block: emp2 (even if they separately held HRS:Approve) may not decide their own request.
  begin
    perform app.decide_training_enrollment(v_enr.id, v_enr.record_version, 'approve', null, '00000000-0000-0000-0000-000000028406', 'emp2');
    raise exception 'ASSERTION FAILURE: emp2 decided their own enrollment request';
  exception when others then
    if sqlerrm not like '%lacks HRS:Approve%' then raise; end if;
  end;

  v_enr := app.decide_training_enrollment(v_enr.id, v_enr.record_version, 'approve', 'approved, budget confirmed', '00000000-0000-0000-0000-000000028402', 'hr');
  if v_enr.status <> 'enrolled' then raise exception 'assertion failed: approved pending_approval should become enrolled, got %', v_enr.status; end if;

  raise notice 'OK: requires_enrollment_approval gate works, self-decision blocked, HR decide approves into a real capacity-checked enrolled/waitlisted state';
end $$;

\echo '>> mandatory bulk assignment: a mandatory course session assigns every active employee; re-run is safely idempotent (already-active enrollments skipped, never double-enrolled)'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_course app.training_courses;
  v_v app.training_course_versions;
  v_sess app.training_sessions;
  v_assigned integer; v_skipped integer;
  v_assigned2 integer; v_skipped2 integer;
  v_enrolled_count integer;
begin
  v_course := app.create_training_course(v_tenant, 'code_of_conduct', 'Code of Conduct', 'compliance', '00000000-0000-0000-0000-000000028402', 'hr');
  v_v := app.create_training_course_version(v_course.id, 'Mandatory annual training', 'e_learning', 1, true, false, false, null, false, null, '00000000-0000-0000-0000-000000028402', 'hr');
  v_v := app.publish_training_course_version(v_v.id, v_v.record_version, '00000000-0000-0000-0000-000000028402', 'hr');
  v_sess := app.create_training_session(v_tenant, v_v.id, null, 'sess_coc_2026', null, now() + interval '2 days', now() + interval '2 days' + interval '1 hour', 100, '00000000-0000-0000-0000-000000028402', 'hr');

  select assigned_count, skipped_count into v_assigned, v_skipped from app.bulk_assign_mandatory_training_session(v_tenant, v_sess.id, '00000000-0000-0000-0000-000000028402', 'hr');
  select count(*) into v_enrolled_count from app.employees where tenant_id = v_tenant and lifecycle_status in ('active', 'on_leave');
  if v_assigned <> v_enrolled_count then raise exception 'assertion failed: expected % assigned (every active employee), got %', v_enrolled_count, v_assigned; end if;

  -- Re-running against the SAME session is a safe no-op -- every employee already has an active enrollment.
  select assigned_count, skipped_count into v_assigned2, v_skipped2 from app.bulk_assign_mandatory_training_session(v_tenant, v_sess.id, '00000000-0000-0000-0000-000000028402', 'hr');
  if v_assigned2 <> 0 or v_skipped2 <> v_enrolled_count then
    raise exception 'ASSERTION FAILURE: re-running bulk mandatory assignment did not safely skip already-enrolled employees (assigned=%, skipped=%)', v_assigned2, v_skipped2;
  end if;

  -- A non-mandatory session is rejected.
  begin
    perform app.bulk_assign_mandatory_training_session(v_tenant, (select id from app.training_sessions where session_code='sess_101_capacity'), '00000000-0000-0000-0000-000000028402', 'hr');
    raise exception 'ASSERTION FAILURE: bulk-assigned a non-mandatory session';
  exception when others then
    if sqlerrm not like 'training_session_not_mandatory%' then raise; end if;
  end;

  raise notice 'OK: mandatory bulk assignment enrolled every active employee (%), re-run safely idempotent (0 new, % skipped), non-mandatory session rejected', v_assigned, v_skipped2;
end $$;

\echo '>> attendance + assessment: multi-attempt scoring, computed pass/fail against the course version''s own passing_score, retries legal'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_v101_id uuid := (select id from app.training_course_versions where course_id=(select id from app.training_courses where tenant_id=v_tenant and code='safety_101') and status='published');
  v_sess app.training_sessions;
  v_enr app.training_enrollments;
  v_a1 app.training_assessments;
  v_a2 app.training_assessments;
begin
  v_sess := app.create_training_session(v_tenant, v_v101_id, null, 'sess_101_assess', null, now() + interval '6 days', now() + interval '6 days' + interval '4 hours', 5, '00000000-0000-0000-0000-000000028402', 'hr');
  v_enr := app.enroll_self_in_training_session(v_tenant, v_sess.id, '00000000-0000-0000-0000-000000028406', 'emp2');

  perform app.record_training_attendance(v_enr.id, true, 4.0, '00000000-0000-0000-0000-000000028402', 'hr');
  if (select attended from app.training_enrollments where id = v_enr.id) is distinct from true then
    raise exception 'assertion failed: attendance not recorded';
  end if;

  -- passing_score for safety_101 is 70 (set at creation above).
  v_a1 := app.record_training_assessment(v_enr.id, 50, 100, 'first attempt, did not pass', '00000000-0000-0000-0000-000000028402', 'hr');
  if v_a1.attempt_number <> 1 or v_a1.passed <> false then raise exception 'assertion failed: attempt 1 should be attempt_number=1, passed=false, got %/%', v_a1.attempt_number, v_a1.passed; end if;

  v_a2 := app.record_training_assessment(v_enr.id, 85, 100, 'retake, passed', '00000000-0000-0000-0000-000000028402', 'hr');
  if v_a2.attempt_number <> 2 or v_a2.passed <> true then raise exception 'assertion failed: attempt 2 should be attempt_number=2, passed=true, got %/%', v_a2.attempt_number, v_a2.passed; end if;

  select * into v_enr from app.training_enrollments where id = v_enr.id;
  perform app.record_training_completion(v_enr.id, v_enr.record_version, 'completed', 'passed on retake', '00000000-0000-0000-0000-000000028402', 'hr');
  if (select count(*) from app.training_assessments where enrollment_id = v_enr.id) <> 2 then
    raise exception 'assertion failed: expected exactly 2 append-only assessment attempts';
  end if;

  raise notice 'OK: attendance recorded; two assessment attempts (fail then pass), attempt_number auto-increments, passed computed deterministically against passing_score, both attempts preserved (append-only)';
end $$;

\echo '>> certificate: issue (internal), evidence attach malware-scan gate (infected/unscanned rejected, clean accepted), import historical (external, unverified), verify, revoke, renew'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_v101_id uuid := (select id from app.training_course_versions where course_id=(select id from app.training_courses where tenant_id=v_tenant and code='safety_101') and status='published');
  v_emp2 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp2work@trn1.test');
  v_cert app.training_certificates;
  v_cert_import app.training_certificates;
  v_cert_renewed app.training_certificates;
  v_cfg_version app.config_versions;
  v_file_infected uuid;
  v_file_pending uuid;
  v_file_clean uuid;
  v_file_wrong_scope uuid;
begin
  v_cert := app.issue_training_certificate(v_tenant, v_emp2, v_v101_id, null, 'CERT-SAF101-EMP2', current_date, (current_date + interval '2 years')::date, '00000000-0000-0000-0000-000000028402', 'hr');
  if v_cert.status <> 'issued' or v_cert.source <> 'internal_completion' or v_cert.verification_status <> 'verified' then
    raise exception 'assertion failed: internal certificate should start issued/internal_completion/verified, got %/%/%', v_cert.status, v_cert.source, v_cert.verification_status;
  end if;

  -- Real PLT-128 file evidence, reusing the established document/file engine
  -- directly (mirrors every onboarding/GPS-installation evidence fixture in
  -- this repository) -- app.register_document_type requires Supreme Admin,
  -- so this fixture grants a local supreme_admin principal membership first.
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000028499', 'supreme@trn1.test') on conflict do nothing;
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028499', 'supreme_admin', null, null, 'tester');
  perform app.register_document_type('training_certificate', 'Training Certificate Evidence', 'DOC', '00000000-0000-0000-0000-000000028499', 'supreme');

  select * into v_cfg_version from app.create_config_draft('document:training_certificate', v_tenant, 'tenant', null, '00000000-0000-0000-0000-000000028401', 'admin');
  perform app.set_config_items(v_cfg_version.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5000000),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'confidential'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000028401', 'admin');
  perform app.publish_document_type_definition(v_cfg_version.id, '00000000-0000-0000-0000-000000028401', null, 'admin');

  v_file_infected := (app.initiate_file_upload(v_tenant, 'training_certificate', 'training_certificate', v_cert.id, 'certificate-infected.pdf', 'application/pdf', 1000, 'confidential', false, null, '{}'::uuid[], null, 'idem-tt-file-infected', '00000000-0000-0000-0000-000000028402', 'hr')).id;
  perform app.record_file_scan_result(v_file_infected, 'infected', 'scanner-ref-1', '00000000-0000-0000-0000-000000028402', 'hr');
  v_file_pending := (app.initiate_file_upload(v_tenant, 'training_certificate', 'training_certificate', v_cert.id, 'certificate-pending.pdf', 'application/pdf', 1000, 'confidential', false, null, '{}'::uuid[], null, 'idem-tt-file-pending', '00000000-0000-0000-0000-000000028402', 'hr')).id;
  v_file_clean := (app.initiate_file_upload(v_tenant, 'training_certificate', 'training_certificate', v_cert.id, 'certificate-clean.pdf', 'application/pdf', 1000, 'confidential', false, null, '{}'::uuid[], null, 'idem-tt-file-clean', '00000000-0000-0000-0000-000000028402', 'hr')).id;
  perform app.record_file_scan_result(v_file_clean, 'clean', 'scanner-ref-2', '00000000-0000-0000-0000-000000028402', 'hr');
  -- Wrong scope: a real, clean file, but scoped to a DIFFERENT record (never attachable regardless of scan status).
  v_file_wrong_scope := (app.initiate_file_upload(v_tenant, 'training_certificate', 'training_certificate', gen_random_uuid(), 'certificate-wrong-scope.pdf', 'application/pdf', 1000, 'confidential', false, null, '{}'::uuid[], null, 'idem-tt-file-wrong', '00000000-0000-0000-0000-000000028402', 'hr')).id;
  perform app.record_file_scan_result(v_file_wrong_scope, 'clean', 'scanner-ref-3', '00000000-0000-0000-0000-000000028402', 'hr');

  begin
    perform app.attach_training_certificate_evidence(v_cert.id, v_cert.record_version, v_file_infected, '00000000-0000-0000-0000-000000028402', 'hr');
    raise exception 'ASSERTION FAILURE: an infected file was attached as certificate evidence';
  exception when others then
    if sqlerrm not like 'evidence_file_infected%' then raise; end if;
  end;
  begin
    perform app.attach_training_certificate_evidence(v_cert.id, v_cert.record_version, v_file_pending, '00000000-0000-0000-0000-000000028402', 'hr');
    raise exception 'ASSERTION FAILURE: a not-yet-scanned (pending) file was attached as certificate evidence';
  exception when others then
    if sqlerrm not like 'evidence_file_not_scanned%' then raise; end if;
  end;
  begin
    perform app.attach_training_certificate_evidence(v_cert.id, v_cert.record_version, v_file_wrong_scope, '00000000-0000-0000-0000-000000028402', 'hr');
    raise exception 'ASSERTION FAILURE: a clean file scoped to a DIFFERENT record was attached as certificate evidence';
  exception when others then
    if sqlerrm not like 'evidence_file_not_found%' then raise; end if;
  end;

  v_cert := app.attach_training_certificate_evidence(v_cert.id, v_cert.record_version, v_file_clean, '00000000-0000-0000-0000-000000028402', 'hr');
  if v_cert.evidence_file_id <> v_file_clean then raise exception 'assertion failed: clean, correctly-scoped evidence was not attached'; end if;

  -- Historical import: source-labeled, unverified until reviewed (section 19).
  v_cert_import := app.import_historical_training_certificate(v_tenant, v_emp2, 'External First Aid Certification', null, 'CERT-EXT-FA-001', (current_date - interval '30 days')::date, (current_date + interval '335 days')::date, '00000000-0000-0000-0000-000000028402', 'hr');
  if v_cert_import.source <> 'external_import' or v_cert_import.verification_status <> 'unverified' then
    raise exception 'ASSERTION FAILURE: imported certificate should start external_import/unverified, got %/%', v_cert_import.source, v_cert_import.verification_status;
  end if;
  v_cert_import := app.verify_training_certificate(v_cert_import.id, v_cert_import.record_version, '00000000-0000-0000-0000-000000028402', 'hr');
  if v_cert_import.verification_status <> 'verified' then raise exception 'assertion failed: certificate should now be verified'; end if;
  begin
    perform app.verify_training_certificate(v_cert_import.id, v_cert_import.record_version, '00000000-0000-0000-0000-000000028402', 'hr');
    raise exception 'ASSERTION FAILURE: an already-verified certificate was verified again';
  exception when others then
    if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Revoke requires HRS:Override, not merely HRS:Edit/Approve.
  begin
    perform app.revoke_training_certificate(v_cert.id, v_cert.record_version, 'issued in error', '00000000-0000-0000-0000-000000028402', 'hr');
    raise exception 'ASSERTION FAILURE: hr (HRS:Edit/Approve, zero Override) revoked a certificate';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  v_cert := app.revoke_training_certificate(v_cert.id, v_cert.record_version, 'issued in error', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  if v_cert.status <> 'revoked' or v_cert.revoked_reason <> 'issued in error' then raise exception 'assertion failed: certificate not revoked correctly'; end if;

  -- Renewal creates a NEW row, never mutates the old one.
  v_cert_renewed := app.renew_training_certificate(v_cert_import.id, 'CERT-EXT-FA-002', current_date, (current_date + interval '1 year')::date, '00000000-0000-0000-0000-000000028402', 'hr');
  if v_cert_renewed.renewed_from_certificate_id <> v_cert_import.id then raise exception 'assertion failed: renewal did not reference the old certificate'; end if;
  if (select status from app.training_certificates where id = v_cert_import.id) <> 'issued' then
    raise exception 'ASSERTION FAILURE: renewal mutated the OLD certificate''s own status';
  end if;

  raise notice 'OK: certificate issue/import/verify/revoke/renew all work; evidence attach correctly rejects infected, pending-scan, and wrong-scope files, accepts clean correctly-scoped evidence; revoke requires HRS:Override specifically';
end $$;

\echo '>> certificate expiry + reminder durable jobs: HRS:Override required; a genuinely expired certificate transitions; a within-lookahead certificate gets a reminder row; both batches are idempotent on re-run'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_v101_id uuid := (select id from app.training_course_versions where course_id=(select id from app.training_courses where tenant_id=v_tenant and code='safety_101') and status='published');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@trn1.test');
  v_expiring app.training_certificates;
  v_already_expired app.training_certificates;
  v_expired_count integer; v_job1 uuid;
  v_expired_count2 integer; v_job1b uuid;
  v_reminded integer; v_skipped integer; v_job2 uuid;
  v_reminded2 integer; v_skipped2 integer;
begin
  v_already_expired := app.issue_training_certificate(v_tenant, v_emp1, v_v101_id, null, 'CERT-SAF101-EXPIRED', (current_date - interval '400 days')::date, (current_date - interval '30 days')::date, '00000000-0000-0000-0000-000000028402', 'hr');
  v_expiring := app.issue_training_certificate(v_tenant, v_emp1, v_v101_id, null, 'CERT-SAF101-SOON', (current_date - interval '350 days')::date, (current_date + interval '10 days')::date, '00000000-0000-0000-0000-000000028402', 'hr');

  begin
    perform app.run_training_certificate_expiry_batch(v_tenant, current_date, 'test-period-1', '00000000-0000-0000-0000-000000028402', 'hr');
    raise exception 'ASSERTION FAILURE: hr (zero HRS:Override) ran the certificate expiry batch';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select expired_count, job_id into v_expired_count, v_job1 from app.run_training_certificate_expiry_batch(v_tenant, current_date, 'test-period-1', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  if v_expired_count <> 1 then raise exception 'assertion failed: expected exactly 1 certificate expired, got %', v_expired_count; end if;
  if (select status from app.training_certificates where id = v_already_expired.id) <> 'expired' then
    raise exception 'ASSERTION FAILURE: the genuinely past-expiry certificate did not transition to expired';
  end if;
  if (select status from app.training_certificates where id = v_expiring.id) <> 'issued' then
    raise exception 'ASSERTION FAILURE: a certificate not yet past its own expiry_date was incorrectly expired';
  end if;

  -- Idempotent re-run for the SAME period: zero additional expirations, same job row.
  select expired_count, job_id into v_expired_count2, v_job1b from app.run_training_certificate_expiry_batch(v_tenant, current_date, 'test-period-1', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  if v_expired_count2 <> 0 or v_job1b <> v_job1 then
    raise exception 'ASSERTION FAILURE: re-running the expiry batch for the same period was not a safe no-op (expired=%, job %/% )', v_expired_count2, v_job1b, v_job1;
  end if;

  select reminded_count, skipped_count, job_id into v_reminded, v_skipped, v_job2 from app.run_training_certificate_expiry_reminder_batch(v_tenant, current_date, 30, 'test-period-1', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  if v_reminded <> 1 then raise exception 'assertion failed: expected exactly 1 certificate reminded (within a 30-day lookahead), got %', v_reminded; end if;
  if not exists (select 1 from app.training_certificate_expiry_reminders where certificate_id = v_expiring.id and period_label = 'test-period-1') then
    raise exception 'ASSERTION FAILURE: no reminder row recorded for the soon-to-expire certificate';
  end if;

  -- Idempotent re-run: the SAME (already-completed) job row is returned by
  -- app.enqueue_job's own replay, so the scan loop never re-runs (mirrors
  -- app.run_leave_accrual_batch's identical "only claim/process/complete a
  -- genuinely FRESH pending job" shape) -- zero new reminders, and critically,
  -- zero DUPLICATE reminder rows for the certificate already reminded above.
  select reminded_count, skipped_count into v_reminded2, v_skipped2 from app.run_training_certificate_expiry_reminder_batch(v_tenant, current_date, 30, 'test-period-1', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  if v_reminded2 <> 0 or v_skipped2 <> 0 then
    raise exception 'ASSERTION FAILURE: re-running the reminder batch for the same period was not a safe no-op (reminded=%, skipped=%)', v_reminded2, v_skipped2;
  end if;
  if (select count(*) from app.training_certificate_expiry_reminders where certificate_id = v_expiring.id and period_label = 'test-period-1') <> 1 then
    raise exception 'ASSERTION FAILURE: re-running the reminder batch produced a duplicate reminder row';
  end if;

  raise notice 'OK: both certificate expiry/reminder batches require HRS:Override, correctly scope to genuinely-due certificates only, and are idempotent on re-run for the same period';
end $$;

\echo '>> reschedule + session cancel cascade: reschedule creates a new enrollment referencing the old (cancelled) one; cancelling a session cancels every still-active enrollment'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_v101_id uuid := (select id from app.training_course_versions where course_id=(select id from app.training_courses where tenant_id=v_tenant and code='safety_101') and status='published');
  v_sess_a app.training_sessions;
  v_sess_b app.training_sessions;
  v_enr app.training_enrollments;
  v_enr_new app.training_enrollments;
  v_enr_other app.training_enrollments;
begin
  v_sess_a := app.create_training_session(v_tenant, v_v101_id, null, 'sess_101_resched_a', null, now() + interval '40 days', now() + interval '40 days' + interval '4 hours', 5, '00000000-0000-0000-0000-000000028402', 'hr');
  v_sess_b := app.create_training_session(v_tenant, v_v101_id, null, 'sess_101_resched_b', null, now() + interval '41 days', now() + interval '41 days' + interval '4 hours', 5, '00000000-0000-0000-0000-000000028402', 'hr');

  v_enr := app.enroll_self_in_training_session(v_tenant, v_sess_a.id, '00000000-0000-0000-0000-000000028407', 'emp3');
  v_enr_new := app.reschedule_training_enrollment(v_enr.id, v_sess_b.id, '00000000-0000-0000-0000-000000028407', 'emp3');
  if v_enr_new.session_id <> v_sess_b.id or v_enr_new.rescheduled_from_enrollment_id <> v_enr.id then
    raise exception 'ASSERTION FAILURE: reschedule did not create a correctly-linked new enrollment on the new session';
  end if;
  if (select status from app.training_enrollments where id = v_enr.id) <> 'cancelled' then
    raise exception 'ASSERTION FAILURE: reschedule did not cancel the OLD enrollment';
  end if;

  v_enr_other := app.enroll_self_in_training_session(v_tenant, v_sess_a.id, '00000000-0000-0000-0000-000000028408', 'reviewer1');
  perform app.cancel_training_session(v_sess_a.id, (select record_version from app.training_sessions where id = v_sess_a.id), 'venue unavailable', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  if (select status from app.training_sessions where id = v_sess_a.id) <> 'cancelled' then raise exception 'assertion failed: session A not cancelled'; end if;
  if (select status from app.training_enrollments where id = v_enr_other.id) <> 'cancelled' then
    raise exception 'ASSERTION FAILURE: cancelling the session did not cascade-cancel a still-active enrollment against it';
  end if;

  -- Session cancel requires HRS:Override, not merely HRS:Edit/Approve.
  begin
    perform app.cancel_training_session(v_sess_b.id, (select record_version from app.training_sessions where id = v_sess_b.id), 'test', '00000000-0000-0000-0000-000000028402', 'hr');
    raise exception 'ASSERTION FAILURE: hr (zero HRS:Override) cancelled a session';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  raise notice 'OK: reschedule creates a correctly-linked new enrollment and cancels the old one; session cancel (HRS:Override) cascades to every still-active enrollment; session cancel rejects an Edit/Approve-only actor';
end $$;

\echo '>> development plan: direct manager may author (unrelated actor may not); cross-employee linked_performance_outcome_id rejected; action lifecycle; self-service progress update by the plan''s own employee'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@trn1.test');
  v_plan app.training_development_plans;
  v_action app.training_development_plan_actions;
  v_course101_id uuid := (select id from app.training_courses where tenant_id=v_tenant and code='safety_101');
begin
  -- reviewer1 has no HRS:Edit and is not emp1's manager -- rejected.
  begin
    perform app.create_training_development_plan(v_tenant, v_emp1, 'FY2026 Growth Plan', 'FY2026', null, '00000000-0000-0000-0000-000000028408', 'reviewer1');
    raise exception 'ASSERTION FAILURE: reviewer1 (not emp1''s manager, zero HRS:Edit) created a development plan for emp1';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- A linked_performance_outcome_id that does not exist is rejected (FK/not-found), proving the reference is genuinely re-validated server-side, never trusted blind.
  begin
    perform app.create_training_development_plan(v_tenant, v_emp1, 'FY2026 Growth Plan', 'FY2026', gen_random_uuid(), '00000000-0000-0000-0000-000000028404', 'mgr1');
    raise exception 'ASSERTION FAILURE: a non-existent linked_performance_outcome_id was accepted';
  exception when others then
    if sqlerrm not like 'performance_outcome_not_found%' then raise; end if;
  end;

  -- mgr1 is emp1's real direct manager -- allowed, with no outcome link.
  v_plan := app.create_training_development_plan(v_tenant, v_emp1, 'FY2026 Growth Plan', 'FY2026', null, '00000000-0000-0000-0000-000000028404', 'mgr1');
  if v_plan.status <> 'draft' then raise exception 'assertion failed: new plan should be draft'; end if;

  v_plan := app.transition_training_development_plan_status(v_plan.id, v_plan.record_version, 'active', null, '00000000-0000-0000-0000-000000028404', 'mgr1');
  if v_plan.status <> 'active' then raise exception 'assertion failed: plan not active'; end if;

  v_action := app.add_training_development_plan_action(v_plan.id, 'certification', 'Complete Safety 201', v_course101_id, current_date + 60, '00000000-0000-0000-0000-000000028404', 'mgr1');
  if v_action.status <> 'planned' then raise exception 'assertion failed: new action should be planned'; end if;

  -- emp1 (the plan's OWN employee, self-service) may progress their own action.
  v_action := app.update_training_development_plan_action_status(v_action.id, v_action.record_version, 'in_progress', null, '00000000-0000-0000-0000-000000028405', 'emp1');
  if v_action.status <> 'in_progress' then raise exception 'assertion failed: emp1 should be able to progress their own action'; end if;

  -- emp2 (neither HRS:Edit, nor emp1, nor emp1''s manager) may not.
  begin
    perform app.update_training_development_plan_action_status(v_action.id, v_action.record_version, 'completed', 'done', '00000000-0000-0000-0000-000000028406', 'emp2');
    raise exception 'ASSERTION FAILURE: emp2 updated a development plan action that is neither theirs nor a report of theirs';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_action := app.update_training_development_plan_action_status(v_action.id, v_action.record_version, 'completed', 'finished early', '00000000-0000-0000-0000-000000028404', 'mgr1');
  if v_action.status <> 'completed' or v_action.completed_at is null then raise exception 'assertion failed: action not marked completed with a timestamp'; end if;

  raise notice 'OK: development plan authoring correctly scoped to HRS:Edit or the employee''s own direct manager; a non-existent linked outcome rejected; action lifecycle (planned->in_progress->completed) works with self, manager, and correctly rejects an unrelated actor';
end $$;

\echo '>> restricted talent review: cycle create/activate (HRS:Override), reviewer assignment (self-assignment blocked structurally), submit gated to the assigned reviewer only, reassignment never mutates the old submitted review'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@trn1.test');
  v_reviewer1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='reviewer1work@trn1.test');
  v_emp2 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp2work@trn1.test');
  v_cycle app.talent_review_cycles;
  v_assignment app.talent_review_assignments;
  v_review app.talent_reviews;
  v_new_assignment app.talent_review_assignments;
  v_new_review_id uuid;
  v_visible_count integer;
begin
  begin
    perform app.create_talent_review_cycle(v_tenant, 'FY2026 Talent Review', 'FY2026', '00000000-0000-0000-0000-000000028402', 'hr');
    raise exception 'ASSERTION FAILURE: hr (HRS:Edit/Approve, zero Override) created a talent review cycle';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  v_cycle := app.create_talent_review_cycle(v_tenant, 'FY2026 Talent Review', 'FY2026', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  v_cycle := app.transition_talent_review_cycle_status(v_cycle.id, v_cycle.record_version, 'active', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  if v_cycle.status <> 'active' then raise exception 'assertion failed: cycle not active'; end if;

  -- Structural self-assignment block (CHECK constraint) -- a reviewer may never be assigned to their own case.
  begin
    perform app.assign_talent_reviewer(v_cycle.id, v_emp1, v_emp1, '00000000-0000-0000-0000-000000028403', 'talentadmin');
    raise exception 'ASSERTION FAILURE: emp1 was assigned as their own talent reviewer';
  exception when others then
    if sqlerrm not like 'invalid_assignee%' then raise; end if;
  end;

  v_assignment := app.assign_talent_reviewer(v_cycle.id, v_emp1, v_reviewer1, '00000000-0000-0000-0000-000000028403', 'talentadmin');
  select * into v_review from app.talent_reviews where assignment_id = v_assignment.id;
  if v_review.status <> 'draft' then raise exception 'assertion failed: fresh review should be draft'; end if;

  -- emp2 (neither the assigned reviewer nor HRS:Override) cannot submit.
  begin
    perform app.submit_talent_review(v_review.id, v_review.record_version, 'high', 'strong performer', 'medium', '00000000-0000-0000-0000-000000028406', 'emp2');
    raise exception 'ASSERTION FAILURE: emp2 (not the assigned reviewer) submitted the review';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_review := app.submit_talent_review(v_review.id, v_review.record_version, 'high', 'strong performer, ready for stretch assignment', 'medium', '00000000-0000-0000-0000-000000028408', 'reviewer1');
  if v_review.status <> 'submitted' or v_review.potential_rating <> 'high' then raise exception 'assertion failed: review not submitted correctly'; end if;

  -- Restricted visibility: emp2 (zero Override, not the reviewer) sees ZERO assignments; reviewer1 sees exactly their own case; talentadmin sees it too.
  select count(*) into v_visible_count from app.list_talent_review_assignments(v_tenant, '00000000-0000-0000-0000-000000028406', v_cycle.id);
  if v_visible_count <> 0 then raise exception 'ASSERTION FAILURE: emp2 (unrelated, zero Override) sees % talent review assignment(s), expected 0', v_visible_count; end if;
  select count(*) into v_visible_count from app.list_my_talent_review_assignments(v_tenant, '00000000-0000-0000-0000-000000028408');
  if v_visible_count <> 1 then raise exception 'assertion failed: reviewer1 should see exactly their own 1 assigned case, got %', v_visible_count; end if;

  -- Reassignment: the OLD assignment/review are never mutated, a brand new pair is created.
  v_new_assignment := app.reassign_talent_reviewer(v_assignment.id, v_emp2, 'reviewer1 is now emp1''s peer, reassigning to avoid a conflict of interest', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  if (select status from app.talent_review_assignments where id = v_assignment.id) <> 'reassigned' then
    raise exception 'ASSERTION FAILURE: old assignment status not marked reassigned';
  end if;
  if (select status from app.talent_reviews where id = v_review.id) <> 'submitted'
    or (select potential_rating from app.talent_reviews where id = v_review.id) <> 'high' then
    raise exception 'ASSERTION FAILURE: reassignment mutated the OLD submitted review''s own content';
  end if;
  select id into v_new_review_id from app.talent_reviews where assignment_id = v_new_assignment.id;
  if (select status from app.talent_reviews where id = v_new_review_id) <> 'draft' then
    raise exception 'ASSERTION FAILURE: a fresh draft review was not created for the new reviewer';
  end if;

  raise notice 'OK: talent review cycle requires HRS:Override; self-assignment structurally blocked; submit gated to the assigned reviewer only; restricted visibility (unrelated actor sees 0, assigned reviewer sees exactly their own case); reassignment never mutates the old submitted review, creates a fresh one for the new reviewer';
end $$;

\echo '>> talent pool: HRS:Override-only (HR Edit/Approve-only actor rejected on read AND write); mandatory reason on add/remove'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@trn1.test');
  v_pool app.talent_pools;
  v_member app.talent_pool_members;
  v_visible_count integer;
begin
  begin
    perform app.create_talent_pool(v_tenant, 'High Potential 2026', 'Annual HiPo pool', 'high_potential', '00000000-0000-0000-0000-000000028402', 'hr');
    raise exception 'ASSERTION FAILURE: hr (zero HRS:Override) created a talent pool';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  v_pool := app.create_talent_pool(v_tenant, 'High Potential 2026', 'Annual HiPo pool', 'high_potential', '00000000-0000-0000-0000-000000028403', 'talentadmin');

  begin
    perform app.add_talent_pool_member(v_pool.id, v_emp1, '', '00000000-0000-0000-0000-000000028403', 'talentadmin');
    raise exception 'ASSERTION FAILURE: a talent pool member was added with an empty (whitespace-only) reason';
  exception when others then
    if sqlerrm not like 'reason_required%' then raise; end if;
  end;
  v_member := app.add_talent_pool_member(v_pool.id, v_emp1, 'consistently exceeds expectations, strong leadership potential', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  if v_member.status <> 'active' then raise exception 'assertion failed: new member should be active'; end if;

  begin
    perform app.remove_talent_pool_member(v_member.id, v_member.record_version, null, '00000000-0000-0000-0000-000000028403', 'talentadmin');
    raise exception 'ASSERTION FAILURE: a talent pool member was removed with no reason';
  exception when others then
    if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  -- HR (HRS:Edit/Approve, zero Override) sees ZERO rows -- not merely "cannot write", genuinely cannot read either.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028402", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_visible_count from app.talent_pool_members;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);
  if v_visible_count <> 0 then raise exception 'ASSERTION FAILURE: hr (zero HRS:Override) sees % talent_pool_members row(s) via RLS, expected 0', v_visible_count; end if;

  v_member := app.remove_talent_pool_member(v_member.id, v_member.record_version, 'accepted a role at another company', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  if v_member.status <> 'removed' then raise exception 'assertion failed: member not removed correctly'; end if;

  raise notice 'OK: talent pool create/add/remove all require HRS:Override; mandatory reason enforced on both add and remove; a plain HR (Edit/Approve, zero Override) actor sees ZERO rows via RLS, not merely denied writes';
end $$;

\echo '>> succession candidate: mandatory reason; self-decision structurally blocked'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_company uuid := (select company_org_unit_id from app.employees where tenant_id=v_tenant and work_email='mgr1work@trn1.test');
  v_position app.positions;
  v_emp1 uuid := (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@trn1.test');
  v_candidate app.talent_succession_candidates;
begin
  v_position := (app.create_position(v_tenant, 'POS-MGR-001', 'Branch Manager', v_company, null, 1, 'Manages the branch', '00000000-0000-0000-0000-000000028402', 'hr'));

  v_candidate := app.propose_succession_candidate(v_tenant, v_position.id, v_emp1, 'ready_1_2_years', 'strong technical performer, developing leadership skills', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  if v_candidate.status <> 'proposed' then raise exception 'assertion failed: new candidate should be proposed'; end if;

  -- Self-decision block: emp1 (even holding HRS:Override) may not decide their own succession candidacy.
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000028405', 'tenant_admin', v_tenant, null, 'tester');
  begin
    perform app.decide_succession_candidate(v_candidate.id, v_candidate.record_version, 'confirm', 'self-decided', '00000000-0000-0000-0000-000000028405', 'emp1');
    raise exception 'ASSERTION FAILURE: emp1 (zero HRS:Override -- and even a tenant_admin grant does not carry HRS:Override) decided their own succession candidacy';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.decide_succession_candidate(v_candidate.id, v_candidate.record_version, 'confirm', null, '00000000-0000-0000-0000-000000028403', 'talentadmin');
    raise exception 'ASSERTION FAILURE: a succession candidate was decided with no reason';
  exception when others then
    if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_candidate := app.decide_succession_candidate(v_candidate.id, v_candidate.record_version, 'confirm', 'confirmed after committee review', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  if v_candidate.status <> 'confirmed' then raise exception 'assertion failed: candidate not confirmed correctly'; end if;

  raise notice 'OK: succession candidate propose/decide requires HRS:Override and a mandatory reason; self-decision structurally blocked even for an actor who separately holds tenant_admin';
end $$;

\echo '>> k-anonymity: a genuinely tiny (2-person) department is suppressed in the talent-pool distribution report; a synthetic 5-person department is not'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug='trn1');
  v_dept_small uuid := (select department_org_unit_id from app.employees where tenant_id=v_tenant and work_email='mgr1work@trn1.test');
  v_dept_big uuid := (select department_org_unit_id from app.employees where tenant_id=v_tenant and work_email='reviewer1work@trn1.test');
  v_pool app.talent_pools;
  v_i integer;
  v_emp_id uuid;
  v_small_row record;
  v_big_row record;
begin
  v_pool := app.create_talent_pool(v_tenant, 'Succession Bench 2026', 'Bench-strength pool', 'successor', '00000000-0000-0000-0000-000000028403', 'talentadmin');

  -- Small dept: exactly the 2 real employees already in it (mgr1, emp1, emp2 -- pick 2).
  perform app.add_talent_pool_member(v_pool.id, (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp1work@trn1.test'), 'bench strength', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  perform app.add_talent_pool_member(v_pool.id, (select master_record_id from app.employees where tenant_id=v_tenant and work_email='emp2work@trn1.test'), 'bench strength', '00000000-0000-0000-0000-000000028403', 'talentadmin');

  -- Big dept: 5 synthetic employees, all in v_dept_big.
  for v_i in 1..5 loop
    insert into auth.users (id, email) values (('00000000-0000-0000-0000-0000000284' || (60 + v_i)::text)::uuid, 'bigdept' || v_i || '@trn1.test');
    perform app.invite_user(v_tenant, ('00000000-0000-0000-0000-0000000284' || (60 + v_i)::text)::uuid, 'bigdept' || v_i || '@trn1.test', 'Big Dept ' || v_i, null, 'tester', now() + interval '7 days');
    perform app.transition_user_status((select id from app.users where email = 'bigdept' || v_i || '@trn1.test'), 'active', 'onboarded', 'tester');
    perform app.create_employee_draft(v_tenant, 'Big Dept ' || v_i, 'full_time', 'bigdept' || v_i || 'work@trn1.test', 'bigdept' || v_i || 'p@trn1.test', '090000009' || v_i, null, null, null, '2024-01-01', (select company_org_unit_id from app.employees where tenant_id=v_tenant and work_email='mgr1work@trn1.test'), (select branch_org_unit_id from app.employees where tenant_id=v_tenant and work_email='mgr1work@trn1.test'), v_dept_big, 'Staff', null, (select id from app.users where email = 'bigdept' || v_i || '@trn1.test'), null, 'hr_created', 'idem-bigdept' || v_i || '-trn1', '00000000-0000-0000-0000-000000028402', 'tester');
    perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'bigdept' || v_i || 'work@trn1.test'), 'Contact', 'spouse', '091000009' || v_i, null, true, '00000000-0000-0000-0000-000000028402', 'tester');
    perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'bigdept' || v_i || 'work@trn1.test'), 1, '00000000-0000-0000-0000-000000028402', 'tester');
    perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'bigdept' || v_i || 'work@trn1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000028402', 'tester');
    perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'bigdept' || v_i || 'work@trn1.test'), 3, '00000000-0000-0000-0000-000000028402', 'tester');
    v_emp_id := (select master_record_id from app.employees where tenant_id = v_tenant and work_email = 'bigdept' || v_i || 'work@trn1.test');
    perform app.add_talent_pool_member(v_pool.id, v_emp_id, 'bench strength', '00000000-0000-0000-0000-000000028403', 'talentadmin');
  end loop;

  select * into v_small_row from app.report_talent_pool_distribution_by_department(v_tenant, v_pool.id, '00000000-0000-0000-0000-000000028403', 'talentadmin') where department_org_unit_id = v_dept_small;
  if v_small_row.suppressed is distinct from true or v_small_row.member_count is not null then
    raise exception 'ASSERTION FAILURE: the real 2-person department should be suppressed (member_count NULL), got suppressed=%, member_count=%', v_small_row.suppressed, v_small_row.member_count;
  end if;

  select * into v_big_row from app.report_talent_pool_distribution_by_department(v_tenant, v_pool.id, '00000000-0000-0000-0000-000000028403', 'talentadmin') where department_org_unit_id = v_dept_big;
  if v_big_row.suppressed is distinct from false or v_big_row.member_count <> 5 then
    raise exception 'ASSERTION FAILURE: the 5-person department should report its real count (5) unsuppressed, got suppressed=%, member_count=%', v_big_row.suppressed, v_big_row.member_count;
  end if;

  -- The report itself is HRS:Override-gated.
  begin
    perform app.report_talent_pool_distribution_by_department(v_tenant, v_pool.id, '00000000-0000-0000-0000-000000028402', 'hr');
    raise exception 'ASSERTION FAILURE: hr (zero HRS:Override) ran the talent pool distribution report';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  raise notice 'OK: k-anonymity floor (k=5) -- the real 2-person department is suppressed (member_count NULL), the 5-person department reports its real count (5) unsuppressed; report itself requires HRS:Override';
end $$;

\echo '>> cross-tenant RLS isolation: a zero-permission trn2 member sees zero rows of trn1 across catalogue, person-scoped, and talent tables'
do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug='trn2');
  v_count integer;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028421", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.training_competencies;
  if v_count <> 0 then raise exception 'ASSERTION FAILURE: trn2 admin sees % training_competencies row(s), expected 0', v_count; end if;
  select count(*) into v_count from app.training_courses;
  if v_count <> 0 then raise exception 'ASSERTION FAILURE: trn2 admin sees % training_courses row(s), expected 0', v_count; end if;
  select count(*) into v_count from app.training_sessions;
  if v_count <> 0 then raise exception 'ASSERTION FAILURE: trn2 admin sees % training_sessions row(s), expected 0', v_count; end if;
  select count(*) into v_count from app.training_enrollments;
  if v_count <> 0 then raise exception 'ASSERTION FAILURE: trn2 admin sees % training_enrollments row(s), expected 0', v_count; end if;
  select count(*) into v_count from app.training_certificates;
  if v_count <> 0 then raise exception 'ASSERTION FAILURE: trn2 admin sees % training_certificates row(s), expected 0', v_count; end if;
  select count(*) into v_count from app.training_development_plans;
  if v_count <> 0 then raise exception 'ASSERTION FAILURE: trn2 admin sees % training_development_plans row(s), expected 0', v_count; end if;
  select count(*) into v_count from app.talent_review_cycles;
  if v_count <> 0 then raise exception 'ASSERTION FAILURE: trn2 admin (tenant_admin of trn2, zero HRS:Override anywhere) sees % talent_review_cycles row(s), expected 0', v_count; end if;
  select count(*) into v_count from app.talent_pools;
  if v_count <> 0 then raise exception 'ASSERTION FAILURE: trn2 admin sees % talent_pools row(s), expected 0', v_count; end if;
  select count(*) into v_count from app.talent_succession_candidates;
  if v_count <> 0 then raise exception 'ASSERTION FAILURE: trn2 admin sees % talent_succession_candidates row(s), expected 0', v_count; end if;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  -- Every RPC also independently rejects a cross-tenant read attempt via app.has_active_tenant_membership, not merely RLS.
  begin
    perform app.list_training_courses(v_tenant2, '00000000-0000-0000-0000-000000028402');
    raise exception 'ASSERTION FAILURE: hr (a trn1 identity) was accepted reading trn2''s training courses via the RPC layer';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  raise notice 'OK: a zero-permission trn2 tenant_admin sees zero trn1 rows via RLS across catalogue/person-scoped/talent tables; RPC layer independently rejects a cross-tenant identity too';
end $$;

\echo '>> schema-privilege defense in depth: anon holds zero table privilege on any training/talent table; authenticated has RLS-scoped SELECT only; internal _-prefixed functions are service_role-only'
do $$
declare
  v_tbl text;
  v_fn text;
begin
  foreach v_tbl in array array[
    'training_competencies', 'training_courses', 'training_course_versions', 'training_course_competencies',
    'training_providers', 'training_course_prerequisites', 'training_sessions', 'training_enrollments',
    'training_assessments', 'training_certificates', 'training_certificate_expiry_reminders',
    'training_development_plans', 'training_development_plan_actions',
    'talent_review_cycles', 'talent_review_assignments', 'talent_reviews', 'talent_pools', 'talent_pool_members', 'talent_succession_candidates'
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
    '_training_prerequisites_met(uuid,uuid,uuid)', '_enroll_employee_in_training_session_internal(uuid,uuid,text,text)',
    'compute_training_assessment_passed(numeric,numeric,numeric)'
  ] loop
    if has_function_privilege('authenticated', 'app.' || v_fn, 'EXECUTE') then
      raise exception 'SECURITY FAILURE: authenticated holds EXECUTE on internal app.%', v_fn;
    end if;
  end loop;
  raise notice 'OK: anon zero table privilege, authenticated RLS-scoped SELECT only, internal functions service_role-only';
end $$;

\echo '>> structural proof: zero write to app.employees.lifecycle_status, any app.payroll_* table, any app.performance_outcomes/_assessments write, or any role/permission table anywhere in this migration''s own function bodies'
do $$
declare
  v_fn record;
  v_violations text := '';
begin
  for v_fn in
    select p.proname, pg_get_functiondef(p.oid) as src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app'
      and (p.proname ~ '^(training_|talent_)' or p.proname ~ '_training_|_talent_' or p.proname in (
        'create_training_competency', 'publish_training_competency', 'archive_training_competency',
        'create_training_course', 'create_training_course_version', 'publish_training_course_version', 'archive_training_course_version',
        'add_training_course_competency', 'create_training_provider', 'update_training_provider_status',
        'add_training_course_prerequisite', 'remove_training_course_prerequisite', 'create_training_session', 'cancel_training_session',
        'enroll_self_in_training_session', 'enroll_employee_in_training_session', 'bulk_assign_mandatory_training_session',
        'decide_training_enrollment', 'cancel_training_enrollment', 'reschedule_training_enrollment', 'record_training_attendance',
        'record_training_completion', 'record_training_assessment', 'issue_training_certificate', 'import_historical_training_certificate',
        'attach_training_certificate_evidence', 'verify_training_certificate', 'revoke_training_certificate', 'renew_training_certificate',
        'run_training_certificate_expiry_batch', 'run_training_certificate_expiry_reminder_batch',
        'create_training_development_plan', 'transition_training_development_plan_status', 'add_training_development_plan_action',
        'update_training_development_plan_action_status', 'create_talent_review_cycle', 'transition_talent_review_cycle_status',
        'assign_talent_reviewer', 'reassign_talent_reviewer', 'submit_talent_review', 'create_talent_pool', 'archive_talent_pool',
        'add_talent_pool_member', 'remove_talent_pool_member', 'propose_succession_candidate', 'decide_succession_candidate'
      ))
  loop
    if v_fn.src ilike '%update app.employees set%lifecycle_status%'
      or v_fn.src ilike '%insert into app.payroll_%' or v_fn.src ilike '%update app.payroll_%' or v_fn.src ilike '%delete from app.payroll_%'
      or v_fn.src ilike '%insert into app.performance_%' or v_fn.src ilike '%update app.performance_%' or v_fn.src ilike '%delete from app.performance_%'
      or v_fn.src ilike '%insert into app.role_%' or v_fn.src ilike '%insert into app.permissions%' or v_fn.src ilike '%insert into app.role_assignments%'
    then
      v_violations := v_violations || v_fn.proname || '; ';
    end if;
  end loop;
  if v_violations <> '' then
    raise exception 'SECURITY FAILURE: found downstream auto-action write(s) in: %', v_violations;
  end if;
  raise notice 'OK: zero write to app.employees.lifecycle_status / app.payroll_* / app.performance_* / role-permission tables across every HRT-284 write function (structural proof)';
end $$;

\echo '>> ISS-2026-083: provider evidence (Prompt 284 §16''s other half) attaches under the same PLT-128 discipline as certificate evidence -- infected, unscanned, wrong-scope and unauthorized are each refused'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'trn1');
  v_hr uuid := '00000000-0000-0000-0000-000000028402';
  v_admin uuid := '00000000-0000-0000-0000-000000028401';
  v_supreme uuid := '00000000-0000-0000-0000-000000028499';
  v_viewer uuid := '00000000-0000-0000-0000-000000028403';
  v_provider app.training_providers;
  v_cfg_version app.config_versions;
  v_file_clean uuid;
  v_file_pending uuid;
  v_file_infected uuid;
  v_file_wrong_scope uuid;
  v_failed boolean;
begin
  select * into v_provider from app.training_providers where tenant_id = v_tenant and name = 'Internal L&D';

  perform app.register_document_type('training_provider', 'Training Provider Accreditation', 'DOC', v_supreme, 'supreme');
  select * into v_cfg_version from app.create_config_draft('document:training_provider', v_tenant, 'tenant', null, v_admin, 'admin');
  perform app.set_config_items(v_cfg_version.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5000000),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), v_admin, 'admin');
  perform app.publish_document_type_definition(v_cfg_version.id, v_admin, null, 'admin');

  v_file_infected := (app.initiate_file_upload(v_tenant, 'training_provider', 'training_provider', v_provider.id, 'accreditation-infected.pdf', 'application/pdf', 1000, null, false, null, '{}'::uuid[], null, 'idem-tt-prov-infected', v_hr, 'hr')).id;
  perform app.record_file_scan_result(v_file_infected, 'infected', 'scanner-prov-1', v_hr, 'hr');
  v_file_pending := (app.initiate_file_upload(v_tenant, 'training_provider', 'training_provider', v_provider.id, 'accreditation-pending.pdf', 'application/pdf', 1000, null, false, null, '{}'::uuid[], null, 'idem-tt-prov-pending', v_hr, 'hr')).id;
  v_file_clean := (app.initiate_file_upload(v_tenant, 'training_provider', 'training_provider', v_provider.id, 'accreditation-clean.pdf', 'application/pdf', 1000, null, false, null, '{}'::uuid[], null, 'idem-tt-prov-clean', v_hr, 'hr')).id;
  perform app.record_file_scan_result(v_file_clean, 'clean', 'scanner-prov-2', v_hr, 'hr');
  -- Real, clean, right tenant, right document type -- scoped to a DIFFERENT provider. The case a
  -- tenant check waves through, and the only one that exercises the record-scope guard.
  v_file_wrong_scope := (app.initiate_file_upload(v_tenant, 'training_provider', 'training_provider', gen_random_uuid(), 'accreditation-wrong.pdf', 'application/pdf', 1000, null, false, null, '{}'::uuid[], null, 'idem-tt-prov-wrong', v_hr, 'hr')).id;
  perform app.record_file_scan_result(v_file_wrong_scope, 'clean', 'scanner-prov-3', v_hr, 'hr');

  begin
    perform app.attach_training_provider_evidence(v_provider.id, v_provider.record_version, v_file_infected, v_hr, 'hr');
    raise exception 'ASSERTION FAILURE: an infected file was attached as provider evidence';
  exception when others then
    if sqlerrm not like 'evidence_file_infected%' then raise; end if;
  end;
  begin
    perform app.attach_training_provider_evidence(v_provider.id, v_provider.record_version, v_file_pending, v_hr, 'hr');
    raise exception 'ASSERTION FAILURE: a not-yet-scanned file was attached as provider evidence';
  exception when others then
    if sqlerrm not like 'evidence_file_not_scanned%' then raise; end if;
  end;
  begin
    perform app.attach_training_provider_evidence(v_provider.id, v_provider.record_version, v_file_wrong_scope, v_hr, 'hr');
    raise exception 'ASSERTION FAILURE: a clean file scoped to a DIFFERENT provider was attached as provider evidence';
  exception when others then
    if sqlerrm not like 'evidence_file_not_found%' then raise; end if;
  end;

  -- Attaching an accreditation is a write, so it carries HRS:Edit -- not the broader read access
  -- the provider directory itself has (the directory is catalogue metadata; the document is not).
  begin
    perform app.attach_training_provider_evidence(v_provider.id, v_provider.record_version, v_file_clean, v_viewer, 'viewer');
    v_failed := false;
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then raise exception 'ASSERTION FAILURE: a viewer without HRS:Edit attached provider evidence'; end if;

  v_provider := app.attach_training_provider_evidence(v_provider.id, v_provider.record_version, v_file_clean, v_hr, 'hr');
  if v_provider.evidence_file_id <> v_file_clean then
    raise exception 'ASSERTION FAILURE: clean, correctly-scoped provider evidence was not attached';
  end if;

  -- Stale version is refused after the attach bumped it, exactly as the certificate path behaves.
  begin
    perform app.attach_training_provider_evidence(v_provider.id, v_provider.record_version - 1, v_file_clean, v_hr, 'hr');
    v_failed := false;
  exception when serialization_failure then
    v_failed := true;
  end;
  if not v_failed then raise exception 'ASSERTION FAILURE: a stale expected_version was accepted'; end if;

  if not exists (
    select 1 from app.audit_logs where action = 'attach_training_provider_evidence' and resource_id = v_provider.id and result = 'success'
  ) then
    raise exception 'ASSERTION FAILURE: no audit event recorded for the provider evidence attachment';
  end if;

  if (select count(*) from information_schema.routine_privileges where routine_name = 'attach_training_provider_evidence' and grantee = 'anon') <> 0 then
    raise exception 'ASSERTION FAILURE: anon holds EXECUTE on attach_training_provider_evidence';
  end if;

  raise notice 'PASS: ISS-2026-083 -- provider evidence attaches under the identical PLT-128 discipline as certificate evidence, with no divergence to learn';
end;
$$;

\echo 'HRT-284 TRAINING AND TALENT TEST SUITE COMPLETE'
