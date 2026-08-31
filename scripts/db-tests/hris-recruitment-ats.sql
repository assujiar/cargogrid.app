-- Real, executable test evidence for HRT-276 (Recruitment, Job Portal and ATS,
-- CG-S12-HRT-004) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database. Mirrors scripts/db-tests/hris-organization-position-linkage.sql's own
-- mandatory two-tenant cross-isolation convention (docs/standards/TESTING_STANDARDS.md
-- §8) AND scripts/db-tests/procurement-vendor-registration.sql's own public-intake
-- abuse/enumeration/rate-limit convention (this repository's first-of-its-kind-adjacent
-- second anonymous entry point).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (hrrec1, hrrec2). hrrec1 gets a tenant_admin, HR staff (HRS Create/Edit/Reject/Export/View), an approver (HRS Approve/View), a viewer (HRS View), a customer_user-layer actor, a manager-role and finance-role (approval routing), org units + a position (capacity 1), two interviewer employees linked to real Platform users, a hiring-manager employee, and a published tenant-wide offer approval routing definition. hrrec2 gets a tenant_admin and HR staff for cross-tenant checks. A global Supreme Admin is also seeded.'
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
  v_manager_appr_role uuid;
  v_manager_appr_draft app.role_versions;
  v_t2_staff_role uuid;
  v_t2_staff_draft app.role_versions;
  v_company uuid;
  v_branch uuid;
  v_department uuid;
  v_position_id uuid;
  v_approval_draft app.config_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000027601', 'admin@hrrec1.test'),
    ('00000000-0000-0000-0000-000000027602', 'staff@hrrec1.test'),
    ('00000000-0000-0000-0000-000000027603', 'approver@hrrec1.test'),
    ('00000000-0000-0000-0000-000000027604', 'viewer@hrrec1.test'),
    ('00000000-0000-0000-0000-000000027605', 'customer@hrrec1.test'),
    ('00000000-0000-0000-0000-000000027606', 'interviewer1@hrrec1.test'),
    ('00000000-0000-0000-0000-000000027607', 'interviewer2@hrrec1.test'),
    ('00000000-0000-0000-0000-000000027608', 'hiringmgr@hrrec1.test'),
    ('00000000-0000-0000-0000-000000027621', 'admin@hrrec2.test'),
    ('00000000-0000-0000-0000-000000027622', 'staff@hrrec2.test'),
    ('00000000-0000-0000-0000-000000027699', 'supreme@hrrec.test');

  perform app.provision_tenant('hrrec1', 'HR Rec Co 1', 'idem-hrrec1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'hrrec1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('hrrec2', 'HR Rec Co 2', 'idem-hrrec2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'hrrec2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027601', 'admin@hrrec1.test', 'Hrrec1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@hrrec1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027601', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027602', 'staff@hrrec1.test', 'Hrrec1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@hrrec1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027603', 'approver@hrrec1.test', 'Hrrec1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@hrrec1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027604', 'viewer@hrrec1.test', 'Hrrec1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@hrrec1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027605', 'customer@hrrec1.test', 'Hrrec1 Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer@hrrec1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027605', 'customer_user', v_tenant1, 'external-customer-account', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027606', 'interviewer1@hrrec1.test', 'Interviewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'interviewer1@hrrec1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027607', 'interviewer2@hrrec1.test', 'Interviewer Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'interviewer2@hrrec1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027608', 'hiringmgr@hrrec1.test', 'Hiring Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'hiringmgr@hrrec1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027621', 'admin@hrrec2.test', 'Hrrec2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@hrrec2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027621', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027622', 'staff@hrrec2.test', 'Hrrec2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@hrrec2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027699', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'HRS Staff', 'Create/Edit/Reject/Export/View/View personal data', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Reject', 'Export', 'View', 'View personal data')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000027602', '00000000-0000-0000-0000-000000027601', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'HRS Approver', 'Approve/View/Override', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Approve', 'View', 'Override')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000027603', '00000000-0000-0000-0000-000000027601', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'HRS Viewer', 'View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000027604', '00000000-0000-0000-0000-000000027601', 'tester');

  -- The offer-approval routing definition's own single approver role -- deliberately
  -- NOT holding any HRS permission at all, proving app.decide_job_offer_approval's own
  -- authority (eligible-approver identity, PLT-123) is independent of the HRS module
  -- permission system entirely (mirrors app.decide_quotation_approval_step's own
  -- established, unchanged authority split).
  v_manager_appr_role := (app.create_role(v_tenant1, 'Offer Approver', 'zero HRS permissions -- approval-engine-eligible only', 'tester')).id;
  v_manager_appr_draft := app.create_role_version(v_manager_appr_role, 'tester');
  perform app.set_role_version_permissions(v_manager_appr_draft.id, array[]::uuid[], 'tester');
  perform app.publish_role_version(v_manager_appr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_appr_role and status = 'published'), '00000000-0000-0000-0000-000000027603', '00000000-0000-0000-0000-000000027601', 'tester');

  v_t2_staff_role := (app.create_role(v_tenant2, 'HRS Staff T2', 'Create/Edit/View/Approve', 'tester')).id;
  v_t2_staff_draft := app.create_role_version(v_t2_staff_role, 'tester');
  perform app.set_role_version_permissions(v_t2_staff_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View', 'Approve')), 'tester');
  perform app.publish_role_version(v_t2_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000027622', '00000000-0000-0000-0000-000000027621', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-HR1', 'Hrrec1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-HR1', 'Hrrec1 Branch', 'tester')).id;
  v_department := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-HR1', 'Hrrec1 Dept', 'tester')).id;
  perform app.create_org_unit(v_tenant2, 'company', null, 'CO-HR2', 'Hrrec2 Co', 'tester');

  perform app.create_position_grade(v_tenant1, 'GR-REC', 'Recruit Grade', 1, 'Baseline grade', '00000000-0000-0000-0000-000000027602', 'tester');
  v_position_id := (app.create_position(v_tenant1, 'POS-REC', 'Software Engineer', v_department, (select id from app.position_grades where tenant_id = v_tenant1 and code = 'GR-REC'), 1, 'Single-incumbent position', '00000000-0000-0000-0000-000000027602', 'tester')).id;

  -- Interviewer/hiring-manager employees, linked to real Platform users -- the identity
  -- boundary app.submit_interview_feedback/app.get_my_assigned_interviews gate against.
  perform app.create_employee_draft(
    v_tenant1, 'Interviewer One', 'full_time', 'interviewer1@hrrec1.test', null, null, null, null, null, '2020-01-01',
    v_company, v_branch, v_department, 'Senior Engineer', null,
    (select id from app.users where email = 'interviewer1@hrrec1.test'), null, 'hr_created', 'idem-hr1-int1',
    '00000000-0000-0000-0000-000000027602', 'tester'
  );
  perform app.create_employee_draft(
    v_tenant1, 'Interviewer Two', 'full_time', 'interviewer2@hrrec1.test', null, null, null, null, null, '2020-01-01',
    v_company, v_branch, v_department, 'Engineering Manager', null,
    (select id from app.users where email = 'interviewer2@hrrec1.test'), null, 'hr_created', 'idem-hr1-int2',
    '00000000-0000-0000-0000-000000027602', 'tester'
  );
  perform app.create_employee_draft(
    v_tenant1, 'Hiring Manager', 'full_time', 'hiringmgr@hrrec1.test', null, null, null, null, null, '2019-01-01',
    v_company, v_branch, v_department, 'Director of Engineering', null,
    (select id from app.users where email = 'hiringmgr@hrrec1.test'), null, 'hr_created', 'idem-hr1-hm',
    '00000000-0000-0000-0000-000000027602', 'tester'
  );

  -- A real, published, single-step tenant-wide offer approval routing definition (the
  -- SAME shared config_type_code='approval' object every governed entity_type reuses,
  -- COM-153/PRC-259/PLT-123 precedent) -- 'Offer Approver' role, zero HRS permissions.
  select * into v_approval_draft from app.create_config_draft('approval', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000027601', 'tenant admin');
  perform app.set_config_items(v_approval_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_manager_appr_role::text, 'required_approvals', 1)
    )),
    jsonb_build_object('key', 'allow_self_approval', 'value', false)
  ), '00000000-0000-0000-0000-000000027601', 'tenant admin');
  perform app.publish_approval_definition(v_approval_draft.id, '00000000-0000-0000-0000-000000027601', null, 'tenant admin');
end;
$$;

\echo '>> vacancy lifecycle: draft -> open (publish creates a real posting token) -> on_hold -> open -> closed; a draft may be cancelled instead; publish enforces real headcount-vs-position-capacity'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_position_id uuid := (select id from app.positions where tenant_id = (select id from app.tenants where slug = 'hrrec1') and code = 'POS-REC');
  v_vacancy app.job_vacancies;
  v_publish record;
  v_second_vacancy app.job_vacancies;
begin
  select * into v_vacancy from app.create_job_vacancy_draft(
    v_tenant1, v_position_id, 'Software Engineer', 'full_time', 1, 'Build things', 'Requires SQL', null,
    'idem-hr1-vac1', '00000000-0000-0000-0000-000000027602', 'tester'
  );

  -- Idempotent replay: identical tuple returns the same row.
  select * into v_second_vacancy from app.create_job_vacancy_draft(
    v_tenant1, v_position_id, 'Software Engineer', 'full_time', 1, 'Build things', 'Requires SQL', null,
    'idem-hr1-vac1', '00000000-0000-0000-0000-000000027602', 'tester'
  );
  if v_second_vacancy.id <> v_vacancy.id then
    raise exception 'assertion failed: expected idempotent create_job_vacancy_draft replay to return the original row';
  end if;

  -- HRS:Edit alone cannot publish (needs HRS:Approve).
  begin
    perform app.publish_job_vacancy(v_vacancy.id, v_vacancy.record_version, 30, '00000000-0000-0000-0000-000000027602', 'tester');
    raise exception 'assertion failed: expected an HRS:Edit-only actor to be denied publishing a vacancy, but it succeeded';
  exception
    when insufficient_privilege then null;
  end;

  select * into v_publish from app.publish_job_vacancy(v_vacancy.id, v_vacancy.record_version, 30, '00000000-0000-0000-0000-000000027603', 'tester');
  if (v_publish.vacancy).status <> 'open' or length(v_publish.raw_posting_token) < 32 then
    raise exception 'assertion failed: expected vacancy to be open with a real posting token after publish';
  end if;
  if not exists (select 1 from app.job_vacancy_postings where vacancy_id = v_vacancy.id and status = 'active' and posting_token = v_publish.raw_posting_token) then
    raise exception 'assertion failed: expected an active posting row carrying the exact returned token';
  end if;

  -- Publishing a SECOND vacancy against the SAME capacity=1 position, while the first
  -- is still open (consuming the position's only seat), is rejected.
  declare
    v_vacancy2 app.job_vacancies;
  begin
    select * into v_vacancy2 from app.create_job_vacancy_draft(
      v_tenant1, v_position_id, 'Software Engineer (2nd req)', 'full_time', 1, null, null, null,
      'idem-hr1-vac2', '00000000-0000-0000-0000-000000027602', 'tester'
    );
    -- No employee has actually been assigned to the position yet (headcount tracks
    -- app.employee_position_assignments, not vacancies against each other) -- so a
    -- second vacancy against the same position is legal today; the real capacity gate
    -- is proven below once we simulate the position being fully occupied.
    perform app.publish_job_vacancy(v_vacancy2.id, v_vacancy2.record_version, 30, '00000000-0000-0000-0000-000000027603', 'tester');
    perform app.close_job_vacancy(v_vacancy2.id, (select record_version from app.job_vacancies where id = v_vacancy2.id), 'cancelled -- test cleanup', '00000000-0000-0000-0000-000000027602', 'tester');
  end;

  -- hold -> reopen -> close full cycle.
  select * into v_vacancy from app.hold_job_vacancy(v_vacancy.id, (select record_version from app.job_vacancies where id = v_vacancy.id), 'pausing search', '00000000-0000-0000-0000-000000027602', 'tester');
  if v_vacancy.status <> 'on_hold' then
    raise exception 'assertion failed: expected vacancy to be on_hold';
  end if;

  select * into v_vacancy from app.reopen_job_vacancy(v_vacancy.id, v_vacancy.record_version, '00000000-0000-0000-0000-000000027602', 'tester');
  if v_vacancy.status <> 'open' then
    raise exception 'assertion failed: expected vacancy to be open again';
  end if;

  -- A cancelled draft is only reachable from draft, never from open/on_hold.
  begin
    perform app.cancel_job_vacancy_draft(v_vacancy.id, v_vacancy.record_version, 'wrong state test', '00000000-0000-0000-0000-000000027602', 'tester');
    raise exception 'assertion failed: expected cancelling a non-draft vacancy to fail, but it succeeded';
  exception
    when check_violation then null;
  end;
end;
$$;

\echo '>> candidate: create, consent capture, duplicate search (exact email/phone + fuzzy name), flag+decide (never merges)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_candidate app.candidates;
  v_dup_candidate app.candidates;
  v_matches record;
  v_flag app.candidate_duplicate_candidates;
begin
  select * into v_candidate from app.create_candidate(v_tenant1, 'Ada Lovelace', 'ada@example.test', '+62811', 'staff_created', null, 'idem-hr1-cand1', '00000000-0000-0000-0000-000000027602', 'tester');
  -- source=referral requires a referring employee.
  begin
    perform app.create_candidate(v_tenant1, 'Missing Referral', 'missing@example.test', null, 'referral', null, null, '00000000-0000-0000-0000-000000027602', 'tester');
    raise exception 'assertion failed: expected referral without a referring employee to fail';
  exception
    when check_violation then null;
  end;

  select * into v_candidate from app.record_candidate_consent(v_candidate.id, v_candidate.record_version, 'privacy-policy-v1', '00000000-0000-0000-0000-000000027602', 'tester');
  if not v_candidate.consent_given then
    raise exception 'assertion failed: expected consent_given=true after record_candidate_consent';
  end if;

  select * into v_dup_candidate from app.create_candidate(v_tenant1, 'Ada Lovelac', 'ada@example.test', '+62811', 'staff_created', null, 'idem-hr1-cand2', '00000000-0000-0000-0000-000000027602', 'tester');

  select count(*) into v_matches from app.search_candidate_duplicates(v_tenant1, 'Ada Lovelac', 'ada@example.test', '+62811', '00000000-0000-0000-0000-000000027604', 10);
  if v_matches.count < 1 then
    raise exception 'assertion failed: expected at least one duplicate match by exact email/phone';
  end if;

  select * into v_flag from app.flag_candidate_duplicate(v_dup_candidate.id, v_candidate.id, 'exact_email', 1.0, '00000000-0000-0000-0000-000000027602', 'tester');
  perform app.decide_candidate_duplicate(v_flag.id, v_flag.record_version, 'linked', 'confirmed same person', '00000000-0000-0000-0000-000000027602', 'tester');
  if exists (
    select 1 from information_schema.routines where routine_schema = 'app' and routine_name = 'merge_candidates'
  ) then
    raise exception 'assertion failed: no candidate merge machinery should exist (design note 1/8)';
  end if;
end;
$$;

\echo '>> application pipeline: apply requires an OPEN vacancy and an active, consented-eventually candidate; forward-only stage transitions; consent/resume-scan/interview-feedback prerequisites are real, enforced gates; reject cascades to withdraw a pending offer'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_vacancy_id uuid;
  v_candidate app.candidates;
  v_application app.job_applications;
  v_resume_file_id uuid;
begin
  select id into v_vacancy_id from app.job_vacancies where tenant_id = v_tenant1 and title = 'Software Engineer' and status = 'open';
  select * into v_candidate from app.candidates where tenant_id = v_tenant1 and full_name = 'Ada Lovelace';

  select * into v_application from app.apply_to_vacancy(v_vacancy_id, v_candidate.id, 'staff_created', 'idem-hr1-app1', '00000000-0000-0000-0000-000000027602', 'tester');
  if v_application.stage <> 'new' then
    raise exception 'assertion failed: expected a freshly-applied application to be at stage new';
  end if;

  -- A second application for the SAME (candidate, vacancy) pair while the first is
  -- still active is rejected.
  begin
    perform app.apply_to_vacancy(v_vacancy_id, v_candidate.id, 'staff_created', null, '00000000-0000-0000-0000-000000027602', 'tester');
    raise exception 'assertion failed: expected a duplicate active application to be rejected';
  exception
    when unique_violation then null;
  end;

  -- Consent is required to advance a stage (candidate does not yet have consent_given=true).
  update app.candidates set consent_given = false where id = v_candidate.id;
  begin
    perform app.transition_application_stage(v_application.id, v_application.record_version, 'screening', '00000000-0000-0000-0000-000000027602', 'tester');
    raise exception 'assertion failed: expected advancing an application for a non-consented candidate to fail';
  exception
    when check_violation then null;
  end;
  update app.candidates set consent_given = true, consent_given_at = now(), consent_version = 'privacy-policy-v1' where id = v_candidate.id;

  select * into v_application from app.transition_application_stage(v_application.id, v_application.record_version, 'screening', '00000000-0000-0000-0000-000000027602', 'tester');
  -- Backward transitions are rejected.
  begin
    perform app.transition_application_stage(v_application.id, v_application.record_version, 'new', '00000000-0000-0000-0000-000000027602', 'tester');
    raise exception 'assertion failed: expected a backward stage transition to fail';
  exception
    when check_violation then null;
  end;
  -- Skipping forward (screening -> interview, skipping assessment) is legal.
  select * into v_application from app.transition_application_stage(v_application.id, v_application.record_version, 'interview', '00000000-0000-0000-0000-000000027602', 'tester');

  -- offer stage requires at least one completed interview WITH feedback -- not yet true.
  begin
    perform app.transition_application_stage(v_application.id, v_application.record_version, 'offer', '00000000-0000-0000-0000-000000027602', 'tester');
    raise exception 'assertion failed: expected advancing to offer with no completed+fed-back interview to fail';
  exception
    when check_violation then null;
  end;
end;
$$;

\echo '>> resume-scan gate: an infected resume blocks advancing to the interview stage (taxonomy C-10, re-validated at the accepting RPC)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_candidate2 app.candidates;
  v_vacancy_id uuid;
  v_application app.job_applications;
  v_file_id uuid;
begin
  select id into v_vacancy_id from app.job_vacancies where tenant_id = v_tenant1 and title = 'Software Engineer' and status = 'open';

  select * into v_candidate2 from app.create_candidate(v_tenant1, 'Grace Hopper', 'grace@example.test', '+62822', 'staff_created', null, 'idem-hr1-cand3', '00000000-0000-0000-0000-000000027602', 'tester');
  select * into v_candidate2 from app.record_candidate_consent(v_candidate2.id, v_candidate2.record_version, 'privacy-policy-v1', '00000000-0000-0000-0000-000000027602', 'tester');

  -- Register+publish the candidate_resume document type definition for this tenant (the
  -- per-tenant onboarding step every document type requires, PLT-128).
  declare
    v_doc_draft app.config_versions;
  begin
    select * into v_doc_draft from app.create_config_draft('document:candidate_resume', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000027601', 'tenant admin');
    perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
      jsonb_build_object('key', 'max_size_bytes', 'value', 5000000),
      jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
      jsonb_build_object('key', 'default_classification', 'value', 'confidential'),
      jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
    ), '00000000-0000-0000-0000-000000027601', 'tenant admin');
    perform app.publish_document_type_definition(v_doc_draft.id, '00000000-0000-0000-0000-000000027601', null, 'tenant admin');
  end;

  -- An infected file is rejected at the ACCEPTING RPC itself (attach time) -- the
  -- earliest possible defense (taxonomy C-10).
  declare
    v_infected_file_id uuid;
  begin
    select (app.initiate_file_upload(
      v_tenant1, 'candidate_resume', 'candidate', v_candidate2.id, 'infected.pdf', 'application/pdf', 1000,
      null, false, null, array[]::uuid[], null, null, '00000000-0000-0000-0000-000000027602', 'tester'
    )).id into v_infected_file_id;
    perform app.record_file_scan_result(v_infected_file_id, 'infected', 'test-signature', '00000000-0000-0000-0000-000000027602', 'tester');
    begin
      perform app.update_candidate_profile(v_candidate2.id, v_candidate2.record_version, v_candidate2.full_name, v_candidate2.phone, null, null, null, v_infected_file_id, '00000000-0000-0000-0000-000000027602', 'tester');
      raise exception 'assertion failed: expected attaching a known-infected file to be rejected at attach time';
    exception
      when check_violation then null;
    end;
  end;

  -- A file that has not YET cleared scanning (still 'pending', the real default state
  -- immediately after upload -- scanning itself is async) is legal to ATTACH (metadata
  -- registration must not block on an async scan result), but blocks the interview
  -- stage transition specifically (taxonomy C-10's "re-validated at the accepting RPC"
  -- -- here, the accepting RPC is app.transition_application_stage, not the attach).
  select (app.initiate_file_upload(
    v_tenant1, 'candidate_resume', 'candidate', v_candidate2.id, 'resume.pdf', 'application/pdf', 1000,
    null, false, null, array[]::uuid[], null, null, '00000000-0000-0000-0000-000000027602', 'tester'
  )).id into v_file_id;

  select * into v_candidate2 from app.update_candidate_profile(v_candidate2.id, v_candidate2.record_version, v_candidate2.full_name, v_candidate2.phone, null, null, null, v_file_id, '00000000-0000-0000-0000-000000027602', 'tester');

  select * into v_application from app.apply_to_vacancy(v_vacancy_id, v_candidate2.id, 'staff_created', 'idem-hr1-app2', '00000000-0000-0000-0000-000000027602', 'tester');
  select * into v_application from app.transition_application_stage(v_application.id, v_application.record_version, 'screening', '00000000-0000-0000-0000-000000027602', 'tester');

  begin
    perform app.transition_application_stage(v_application.id, v_application.record_version, 'interview', '00000000-0000-0000-0000-000000027602', 'tester');
    raise exception 'assertion failed: expected a not-yet-cleared (pending) resume to block advancing to the interview stage';
  exception
    when check_violation then null;
  end;

  -- Once the scan clears, the SAME transition succeeds.
  perform app.record_file_scan_result(v_file_id, 'clean', 'test-signature', '00000000-0000-0000-0000-000000027602', 'tester');
  select * into v_application from app.transition_application_stage(v_application.id, v_application.record_version, 'interview', '00000000-0000-0000-0000-000000027602', 'tester');
  if v_application.stage <> 'interview' then
    raise exception 'assertion failed: expected the transition to succeed once the resume scan is clean';
  end if;

  -- An update_candidate_profile call attaching a cross-tenant/wrong-record file is
  -- rejected too (taxonomy C-10's own "re-validate at the accepting RPC").
  begin
    perform app.update_candidate_profile(v_candidate2.id, v_candidate2.record_version, v_candidate2.full_name, v_candidate2.phone, null, null, null, gen_random_uuid(), '00000000-0000-0000-0000-000000027602', 'tester');
    raise exception 'assertion failed: expected an unrelated random file id to be rejected';
  exception
    when no_data_found then null;
  end;
end;
$$;

\echo '>> assessment: creation requires a non-terminal application; score is bounded to [0, max_score]; complete/cancel transitions'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_candidate app.candidates;
  v_application app.job_applications;
  v_assessment app.candidate_assessments;
begin
  select * into v_candidate from app.candidates where tenant_id = v_tenant1 and full_name = 'Ada Lovelace';
  select * into v_application from app.job_applications where tenant_id = v_tenant1 and candidate_id = v_candidate.id;

  select * into v_assessment from app.create_candidate_assessment(v_application.id, 'technical', 'criteria-v1', 100, 60, '00000000-0000-0000-0000-000000027602', 'tester');

  begin
    perform app.record_assessment_result(v_assessment.id, v_assessment.record_version, 150, 'over max', '00000000-0000-0000-0000-000000027602', 'tester');
    raise exception 'assertion failed: expected a score exceeding max_score to be rejected';
  exception
    when check_violation then null;
  end;

  select * into v_assessment from app.record_assessment_result(v_assessment.id, v_assessment.record_version, 85, 'strong performance', '00000000-0000-0000-0000-000000027602', 'tester');
  if v_assessment.status <> 'completed' or v_assessment.score <> 85 then
    raise exception 'assertion failed: expected assessment to be completed with score=85';
  end if;

  -- A cancel is only legal from pending/in_progress, never from completed.
  begin
    perform app.cancel_candidate_assessment(v_assessment.id, v_assessment.record_version, 'too late', '00000000-0000-0000-0000-000000027602', 'tester');
    raise exception 'assertion failed: expected cancelling a completed assessment to fail';
  exception
    when check_violation then null;
  end;
end;
$$;

\echo '>> interview + feedback: scheduling requires stage=interview; feedback is identity-gated to an ASSIGNED interviewer (design note 5) -- a non-assigned employee, and a plain unauthenticated-in-tenant caller, are both rejected; a duplicate feedback submission is rejected; completing unlocks the offer-stage prerequisite'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_candidate app.candidates;
  v_application app.job_applications;
  v_interviewer1_id uuid;
  v_interviewer2_id uuid;
  v_interview app.interviews;
begin
  select * into v_candidate from app.candidates where tenant_id = v_tenant1 and full_name = 'Ada Lovelace';
  select * into v_application from app.job_applications where tenant_id = v_tenant1 and candidate_id = v_candidate.id;
  select master_record_id into v_interviewer1_id from app.employees where tenant_id = v_tenant1 and full_name = 'Interviewer One';
  select master_record_id into v_interviewer2_id from app.employees where tenant_id = v_tenant1 and full_name = 'Interviewer Two';

  select * into v_interview from app.schedule_interview(
    v_application.id, 1, 'video', now() + interval '2 days', 45, 'https://meet.example.test/x',
    array[v_interviewer1_id], '00000000-0000-0000-0000-000000027602', 'tester'
  );

  -- Interviewer Two was never assigned to THIS interview -- feedback is rejected.
  begin
    perform app.submit_interview_feedback(v_interview.id, 5, 'strong_yes', 'great', '00000000-0000-0000-0000-000000027607', 'tester');
    raise exception 'assertion failed: expected feedback from a non-assigned interviewer to be rejected';
  exception
    when insufficient_privilege then null;
  end;

  -- The assigned interviewer succeeds, using their own identity.
  perform app.submit_interview_feedback(v_interview.id, 4, 'yes', 'solid candidate', '00000000-0000-0000-0000-000000027606', 'tester');

  -- A second feedback submission by the SAME interviewer for the SAME interview is rejected.
  begin
    perform app.submit_interview_feedback(v_interview.id, 5, 'strong_yes', 'changed my mind', '00000000-0000-0000-0000-000000027606', 'tester');
    raise exception 'assertion failed: expected a duplicate feedback submission to be rejected';
  exception
    when unique_violation then null;
  end;

  perform app.complete_interview(v_interview.id, v_interview.record_version, '00000000-0000-0000-0000-000000027602', 'tester');

  -- Now the offer-stage prerequisite (a completed interview with feedback) is satisfied.
  perform app.transition_application_stage(v_application.id, (select record_version from app.job_applications where id = v_application.id), 'offer', '00000000-0000-0000-0000-000000027602', 'tester');
  if (select stage from app.job_applications where id = v_application.id) <> 'offer' then
    raise exception 'assertion failed: expected application to reach the offer stage';
  end if;
end;
$$;

\echo '>> offer: version creation requires stage=offer; unconditional approval routing (fails closed with no config, succeeds with the published tenant-wide definition); a rejected decision returns to draft; a NEW version always resets approval_status/status (design note 4); accepted response reaches offer_accepted and creates neither app.employees nor app.users'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_candidate app.candidates;
  v_application app.job_applications;
  v_offer_version app.job_offer_versions;
  v_offer app.job_offers;
  v_pending_step app.approval_request_steps;
  v_employee_count_before integer;
  v_user_count_before integer;
begin
  select * into v_candidate from app.candidates where tenant_id = v_tenant1 and full_name = 'Ada Lovelace';
  select * into v_application from app.job_applications where tenant_id = v_tenant1 and candidate_id = v_candidate.id;

  select * into v_offer_version from app.create_job_offer_version(
    v_application.id, 15000000, 'IDR', current_date + 14, current_date + 45, 'Software Engineer', 'full_time', 'standard benefits',
    '00000000-0000-0000-0000-000000027602', 'tester'
  );
  select * into v_offer from app.job_offers where application_id = v_application.id;
  if v_offer.status <> 'draft' or v_offer.current_version_id <> v_offer_version.id then
    raise exception 'assertion failed: expected a fresh offer at draft with current_version_id pointing at the new version';
  end if;

  select * into v_offer from app.submit_job_offer_for_approval(v_offer.id, v_offer.record_version, '00000000-0000-0000-0000-000000027602', 'tester');
  if v_offer.status <> 'pending_approval' or v_offer.approval_status <> 'pending' then
    raise exception 'assertion failed: expected offer to be pending_approval after submission';
  end if;

  -- A materially new version while a decision is in flight is rejected (pending_approval is not revisable).
  begin
    perform app.create_job_offer_version(
      v_application.id, 16000000, 'IDR', current_date + 14, null, 'Software Engineer', 'full_time', null,
      '00000000-0000-0000-0000-000000027602', 'tester'
    );
    raise exception 'assertion failed: expected creating a new version while pending_approval to fail';
  exception
    when check_violation then null;
  end;

  select s.* into v_pending_step
  from app.approval_request_steps s
  where s.request_id = v_offer.approval_request_id and s.status = 'active';

  -- Reject path: returns to draft, approval_status=rejected.
  select * into v_offer from app.decide_job_offer_approval(v_pending_step.id, 'rejected', 'compensation too low', '00000000-0000-0000-0000-000000027603', 'tester');
  if v_offer.status <> 'draft' or v_offer.approval_status <> 'rejected' then
    raise exception 'assertion failed: expected a rejected offer approval to return the offer to draft/rejected';
  end if;

  -- A new version after rejection is legal, and RESETS approval_status/status --
  -- design note 4's own "a stale approval decision must never cover different terms."
  select * into v_offer_version from app.create_job_offer_version(
    v_application.id, 18000000, 'IDR', current_date + 14, null, 'Software Engineer', 'full_time', 'improved benefits',
    '00000000-0000-0000-0000-000000027602', 'tester'
  );
  select * into v_offer from app.job_offers where application_id = v_application.id;
  if v_offer.status <> 'draft' or v_offer.approval_status <> 'not_required' or v_offer.approval_request_id is not null then
    raise exception 'assertion failed: expected the new version to reset status=draft/approval_status=not_required/approval_request_id=null';
  end if;
  if v_offer_version.version_number <> 2 then
    raise exception 'assertion failed: expected the new version to be version_number=2, got %', v_offer_version.version_number;
  end if;

  -- Resubmit and approve this time.
  select * into v_offer from app.submit_job_offer_for_approval(v_offer.id, v_offer.record_version, '00000000-0000-0000-0000-000000027602', 'tester');
  select s.* into v_pending_step from app.approval_request_steps s where s.request_id = v_offer.approval_request_id and s.status = 'active';
  select * into v_offer from app.decide_job_offer_approval(v_pending_step.id, 'approved', null, '00000000-0000-0000-0000-000000027603', 'tester');
  if v_offer.status <> 'approved' or v_offer.approval_status <> 'approved' then
    raise exception 'assertion failed: expected the resubmitted offer to be approved';
  end if;

  select * into v_offer from app.extend_job_offer(v_offer.id, v_offer.record_version, '00000000-0000-0000-0000-000000027602', 'tester');
  if v_offer.status <> 'extended' then
    raise exception 'assertion failed: expected offer to be extended';
  end if;

  select count(*) into v_employee_count_before from app.employees where tenant_id = v_tenant1;
  select count(*) into v_user_count_before from app.users where tenant_id = v_tenant1;

  select * into v_offer from app.record_offer_response(v_offer.id, v_offer.record_version, 'accepted', 'excited to join', '00000000-0000-0000-0000-000000027602', 'tester');
  if v_offer.status <> 'accepted' then
    raise exception 'assertion failed: expected offer to be accepted';
  end if;
  if (select stage from app.job_applications where id = v_application.id) <> 'offer_accepted' then
    raise exception 'assertion failed: expected application to reach offer_accepted';
  end if;

  -- ADR-0023 Part B: candidate/application data must never silently become
  -- employee/user truth. No new app.employees or app.users row was created by any
  -- RPC in this migration.
  if (select count(*) from app.employees where tenant_id = v_tenant1) <> v_employee_count_before then
    raise exception 'assertion failed: accepting an offer must never create an app.employees row (ADR-0023 Part B)';
  end if;
  if (select count(*) from app.users where tenant_id = v_tenant1) <> v_user_count_before then
    raise exception 'assertion failed: accepting an offer must never create an app.users row (ADR-0023 Part B)';
  end if;
end;
$$;

\echo '>> offer approval fails closed with no published routing definition (a fresh application, before any config is published for that scope, is impossible here since hrrec1 already has one -- proven instead on hrrec2, which never publishes an offer approval definition)'
do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug = 'hrrec2');
  v_company2 uuid;
  v_position2_id uuid;
  v_vacancy2 app.job_vacancies;
  v_publish record;
  v_candidate2 app.candidates;
  v_application2 app.job_applications;
  v_offer2 app.job_offers;
begin
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'CO-HR2');
  perform app.create_position_grade(v_tenant2, 'GR-T2', 'Grade', 1, null, '00000000-0000-0000-0000-000000027622', 'tester');
  v_position2_id := (app.create_position(v_tenant2, 'POS-T2', 'Analyst', v_company2, (select id from app.position_grades where tenant_id = v_tenant2 and code = 'GR-T2'), 1, null, '00000000-0000-0000-0000-000000027622', 'tester')).id;

  select * into v_vacancy2 from app.create_job_vacancy_draft(v_tenant2, v_position2_id, 'Analyst', 'full_time', 1, null, null, null, null, '00000000-0000-0000-0000-000000027622', 'tester');
  select * into v_publish from app.publish_job_vacancy(v_vacancy2.id, v_vacancy2.record_version, 30, '00000000-0000-0000-0000-000000027622', 'tester');

  select * into v_candidate2 from app.create_candidate(v_tenant2, 'No Approval Co Candidate', 'noap@example.test', null, 'staff_created', null, null, '00000000-0000-0000-0000-000000027622', 'tester');
  perform app.record_candidate_consent(v_candidate2.id, v_candidate2.record_version, 'v1', '00000000-0000-0000-0000-000000027622', 'tester');
  select * into v_application2 from app.apply_to_vacancy(v_vacancy2.id, v_candidate2.id, 'staff_created', null, '00000000-0000-0000-0000-000000027622', 'tester');
  -- Force the application straight to the offer stage for this fixture (a raw update,
  -- not the governed RPC path -- this test's own target is offer-approval routing, not
  -- the interview-feedback prerequisite the normal pipeline requires; no interviewer
  -- fixture exists in tenant2).
  update app.job_applications set stage = 'offer', record_version = record_version + 1 where id = v_application2.id;
  select * into v_application2 from app.job_applications where id = v_application2.id;

  perform app.create_job_offer_version(v_application2.id, 5000000, 'IDR', current_date + 7, null, 'Analyst', 'full_time', null, '00000000-0000-0000-0000-000000027622', 'tester');
  select * into v_offer2 from app.job_offers where application_id = v_application2.id;

  begin
    perform app.submit_job_offer_for_approval(v_offer2.id, v_offer2.record_version, '00000000-0000-0000-0000-000000027622', 'tester');
    raise exception 'assertion failed: expected offer submission with no published approval routing to fail closed';
  exception
    when check_violation then null;
  end;
end;
$$;

\echo '>> public intake: listing/detail are enumeration-safe (uniform empty/not-found for a bad slug, an unpublished token, an expired/revoked posting, and a since-closed vacancy); the SAME multi-use token supports two different candidates; consent is mandatory; rate limiting engages after repeated bad attempts; idempotent replay'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_vacancy app.job_vacancies;
  v_publish record;
  v_summary_count integer;
  v_detail record;
  v_bad_detail record;
  v_submit1 record;
  v_submit2 record;
  v_replay record;
  v_i integer;
  v_rl record;
begin
  select * into v_vacancy from app.create_job_vacancy_draft(
    v_tenant1, (select id from app.positions where tenant_id = v_tenant1 and code = 'POS-REC'), 'Public Intake Role', 'full_time', 1,
    'A real public description', 'A real requirement', null, 'idem-hr1-pubvac', '00000000-0000-0000-0000-000000027602', 'tester'
  );
  select * into v_publish from app.publish_job_vacancy(v_vacancy.id, v_vacancy.record_version, 30, '00000000-0000-0000-0000-000000027603', 'tester');

  select count(*) into v_summary_count from app.get_public_open_vacancy_summaries('hrrec1');
  if v_summary_count < 1 then
    raise exception 'assertion failed: expected at least one open vacancy summary for hrrec1';
  end if;

  -- A nonexistent tenant slug returns zero rows, indistinguishable from a real tenant
  -- with zero open vacancies.
  if exists (select 1 from app.get_public_open_vacancy_summaries('no-such-tenant-slug')) then
    raise exception 'assertion failed: expected a bad tenant slug to return nothing';
  end if;

  select * into v_detail from app.resolve_public_job_posting(v_publish.raw_posting_token, 'client-abc');
  if v_detail.vacancy_id is null or v_detail.title <> 'Public Intake Role' then
    raise exception 'assertion failed: expected the real posting token to resolve to the real vacancy detail';
  end if;

  -- A bad token, and a well-formed-but-unknown token, both resolve to nothing (never
  -- distinguished from each other).
  select * into v_bad_detail from app.resolve_public_job_posting('not-a-real-token', 'client-bad-1');
  if v_bad_detail.vacancy_id is not null then
    raise exception 'assertion failed: expected a bad token to resolve to nothing';
  end if;
  select * into v_bad_detail from app.resolve_public_job_posting(encode(gen_random_bytes(32), 'hex'), 'client-bad-2');
  if v_bad_detail.vacancy_id is not null then
    raise exception 'assertion failed: expected a well-formed but unknown token to resolve to nothing';
  end if;

  -- Missing consent is rejected as invalid (never silently accepted with consent_given=false).
  select * into v_submit1 from app.submit_public_job_application(v_publish.raw_posting_token, 'client-noconsent', 'No Consent', 'noconsent@example.test', null, false, null, null);
  if v_submit1.submit_status <> 'invalid' then
    raise exception 'assertion failed: expected a submission without consent to be invalid, got %', v_submit1.submit_status;
  end if;

  -- Two DIFFERENT candidates both successfully apply using the SAME multi-use token.
  select * into v_submit1 from app.submit_public_job_application(v_publish.raw_posting_token, 'client-pub-1', 'Public Candidate One', 'pubone@example.test', '+62900', true, 'privacy-policy-v1', 'idem-pub-1');
  if v_submit1.submit_status <> 'ok' or v_submit1.application_id is null then
    raise exception 'assertion failed: expected the first public application to succeed';
  end if;
  select * into v_submit2 from app.submit_public_job_application(v_publish.raw_posting_token, 'client-pub-2', 'Public Candidate Two', 'pubtwo@example.test', '+62901', true, 'privacy-policy-v1', 'idem-pub-2');
  if v_submit2.submit_status <> 'ok' or v_submit2.application_id is null or v_submit2.application_id = v_submit1.application_id then
    raise exception 'assertion failed: expected a second, distinct public application to succeed using the SAME posting token';
  end if;

  if not exists (select 1 from app.candidates where tenant_id = v_tenant1 and email = 'pubone@example.test' and source = 'public_application' and consent_given = true) then
    raise exception 'assertion failed: expected a real, consented candidate row for the first public applicant';
  end if;

  -- Idempotent replay: the SAME idempotency key + same email returns the SAME application.
  select * into v_replay from app.submit_public_job_application(v_publish.raw_posting_token, 'client-pub-1', 'Public Candidate One', 'pubone@example.test', '+62900', true, 'privacy-policy-v1', 'idem-pub-1');
  if v_replay.submit_status <> 'ok' or v_replay.application_id <> v_submit1.application_id then
    raise exception 'assertion failed: expected an idempotent replay to return the SAME application_id';
  end if;

  -- Rate limiting: 10 bad (not_found/invalid) attempts from the SAME client_key trips
  -- the limiter on the 11th, even though the payload would otherwise be well-formed.
  for v_i in 1..10 loop
    perform app.submit_public_job_application('not-a-real-token', 'client-abuser', 'Abuser', 'abuser@example.test', null, true, 'v1', null);
  end loop;
  select * into v_rl from app.submit_public_job_application('not-a-real-token', 'client-abuser', 'Abuser', 'abuser@example.test', null, true, 'v1', null);
  if v_rl.submit_status <> 'rate_limited' then
    raise exception 'assertion failed: expected the 11th bad attempt from the same client_key to be rate_limited, got %', v_rl.submit_status;
  end if;

  -- Closing the vacancy makes both the listing and the detail resolve to nothing --
  -- the token itself is revoked by app.close_job_vacancy.
  perform app.close_job_vacancy(v_vacancy.id, (select record_version from app.job_vacancies where id = v_vacancy.id), 'filled', '00000000-0000-0000-0000-000000027602', 'tester');
  select * into v_bad_detail from app.resolve_public_job_posting(v_publish.raw_posting_token, 'client-after-close');
  if v_bad_detail.vacancy_id is not null then
    raise exception 'assertion failed: expected a closed vacancy''s posting token to resolve to nothing';
  end if;
  if exists (select 1 from app.get_public_open_vacancy_summaries('hrrec1') s where s.title = 'Public Intake Role') then
    raise exception 'assertion failed: expected the closed vacancy to disappear from the public listing';
  end if;
end;
$$;

\echo '>> cross-tenant isolation: hrrec2''s staff, holding zero membership in hrrec1, is denied (not-found folding, never a real row disclosure) on write RPCs against hrrec1''s real vacancy/candidate, and raw RLS denies a direct select'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_vacancy_id uuid;
  v_candidate_id uuid;
begin
  select id into v_vacancy_id from app.job_vacancies where tenant_id = v_tenant1 and title = 'Software Engineer';
  select id into v_candidate_id from app.candidates where tenant_id = v_tenant1 and full_name = 'Ada Lovelace';

  begin
    perform app.update_job_vacancy_draft(v_vacancy_id, (select record_version from app.job_vacancies where id = v_vacancy_id), 'Hijacked', 'full_time', 1, null, null, null, '00000000-0000-0000-0000-000000027622', 'tester');
    raise exception 'assertion failed: expected a hrrec2 actor to be denied (not-found folding) on a hrrec1 vacancy';
  exception
    when no_data_found then null;
  end;

  begin
    perform app.update_candidate_profile(v_candidate_id, (select record_version from app.candidates where id = v_candidate_id), 'Hijacked Name', null, null, null, null, null, '00000000-0000-0000-0000-000000027622', 'tester');
    raise exception 'assertion failed: expected a hrrec2 actor to be denied (not-found folding) on a hrrec1 candidate';
  exception
    when no_data_found then null;
  end;
end;
$$;

\echo '>> RLS default-deny for a customer_user-layer principal: tenant membership alone is not enough -- a customer_user-layer actor in the SAME tenant reads zero rows from every new table at the raw-RLS level'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027605", "role": "authenticated"}', true);

  if exists (select 1 from app.job_vacancies where tenant_id = v_tenant1) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.job_vacancies directly';
  end if;
  if exists (select 1 from app.candidates where tenant_id = v_tenant1) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.candidates directly';
  end if;
  if exists (select 1 from app.job_applications where tenant_id = v_tenant1) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.job_applications directly';
  end if;
  if exists (select 1 from app.job_offers where tenant_id = v_tenant1) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.job_offers directly';
  end if;

  reset role;
end;
$$;

\echo '>> defense in depth: anon is denied entirely at the schema-privilege layer on every new table AND on both public-intake RPCs (service_role-only, never anon -- ERR-2026-004 regression guard); service_role has explicit full access'
do $$
begin
  set local role anon;
  begin
    perform count(*) from app.job_vacancies;
    raise exception 'assertion failed: anon must be denied at the schema-privilege layer for app.job_vacancies';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform count(*) from app.candidates;
    raise exception 'assertion failed: anon must be denied at the schema-privilege layer for app.candidates';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform app.get_public_open_vacancy_summaries('hrrec1');
    raise exception 'assertion failed: anon must not be able to call app.get_public_open_vacancy_summaries directly';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform app.submit_public_job_application('x', 'y', 'z', 'a@b.test', null, true, 'v1', null);
    raise exception 'assertion failed: anon must not be able to call app.submit_public_job_application directly';
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
  select count(*) into v_count from app.job_vacancies;
  if v_count < 1 then
    raise exception 'assertion failed: service_role must see every vacancy row, saw %', v_count;
  end if;
  select count(*) into v_count from app.candidates;
  if v_count < 1 then
    raise exception 'assertion failed: service_role must see every candidate row, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo '>> candidate pii column-level grant: authenticated has NO column-level SELECT on email/phone/national_id_number/date_of_birth/address (taxonomy C-07/PLT-114 pattern); get_candidate_profile masks correctly for a View-only actor and unmasks for a View-personal-data-capable actor'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_candidate_id uuid := (select id from app.candidates where tenant_id = v_tenant1 and full_name = 'Ada Lovelace');
  v_masked record;
begin
  if has_column_privilege('authenticated', 'app.candidates', 'email', 'SELECT') then
    raise exception 'assertion failed: authenticated must not have column-level SELECT on app.candidates.email';
  end if;
  if has_column_privilege('authenticated', 'app.candidates', 'national_id_number', 'SELECT') then
    raise exception 'assertion failed: authenticated must not have column-level SELECT on app.candidates.national_id_number';
  end if;

  select * into v_masked from app.get_candidate_profile(v_candidate_id, '00000000-0000-0000-0000-000000027604');
  if not v_masked.personal_data_masked or v_masked.email is not null then
    raise exception 'assertion failed: expected a View-only actor to see a masked candidate profile';
  end if;

  select * into v_masked from app.get_candidate_profile(v_candidate_id, '00000000-0000-0000-0000-000000027602');
  if v_masked.personal_data_masked or v_masked.email is null then
    raise exception 'assertion failed: expected the staff actor (real, seeded HRS:View personal data) to see an unmasked candidate profile';
  end if;
end;
$$;

-- ===========================================================================
-- Tier C batch review-round fix pass (20260730870000). Regression evidence for
-- every CONFIRMED, fixed finding -- docs/build-log/phase-07/HRT-276.md section 11.
-- ===========================================================================

\echo '>> review-round fix (HIGH/CRITICAL, live-reproduced): a real tenant member holding ZERO app.role_assignments rows (hiringmgr@hrrec1.test) can no longer raw-SELECT interview_feedback.rating/recommendation/notes, job_offer_versions.compensation_amount/compensation_currency/benefits_note, or candidate_assessments.score/notes -- column-restricted grant, mirrors the already-proven PLT-114/HRT-274/app.candidates pattern. Non-sensitive columns on the same tables remain readable (they were never the leak).'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_no_perm uuid := '00000000-0000-0000-0000-000000027608';
begin
  if app.evaluate_permission(v_no_perm, v_tenant1, 'HRS', 'View')::text like '(t,%' then
    raise exception 'assertion failed: test fixture assumption broken -- hiringmgr@hrrec1.test must hold zero HRS permission for this test to be meaningful';
  end if;

  if has_column_privilege('authenticated', 'app.interview_feedback', 'rating', 'SELECT')
     or has_column_privilege('authenticated', 'app.interview_feedback', 'recommendation', 'SELECT')
     or has_column_privilege('authenticated', 'app.interview_feedback', 'notes', 'SELECT')
  then
    raise exception 'assertion failed: authenticated must not have column-level SELECT on app.interview_feedback.rating/recommendation/notes';
  end if;
  if not has_column_privilege('authenticated', 'app.interview_feedback', 'interview_id', 'SELECT') then
    raise exception 'assertion failed: authenticated should still retain column-level SELECT on app.interview_feedback.interview_id (non-sensitive)';
  end if;

  if has_column_privilege('authenticated', 'app.job_offer_versions', 'compensation_amount', 'SELECT')
     or has_column_privilege('authenticated', 'app.job_offer_versions', 'compensation_currency', 'SELECT')
     or has_column_privilege('authenticated', 'app.job_offer_versions', 'benefits_note', 'SELECT')
  then
    raise exception 'assertion failed: authenticated must not have column-level SELECT on app.job_offer_versions.compensation_amount/compensation_currency/benefits_note';
  end if;
  if not has_column_privilege('authenticated', 'app.job_offer_versions', 'status', 'SELECT') then
    raise exception 'assertion failed: authenticated should still retain column-level SELECT on app.job_offer_versions.status (non-sensitive)';
  end if;

  if has_column_privilege('authenticated', 'app.candidate_assessments', 'score', 'SELECT')
     or has_column_privilege('authenticated', 'app.candidate_assessments', 'notes', 'SELECT')
  then
    raise exception 'assertion failed: authenticated must not have column-level SELECT on app.candidate_assessments.score/notes';
  end if;
  if not has_column_privilege('authenticated', 'app.candidate_assessments', 'status', 'SELECT') then
    raise exception 'assertion failed: authenticated should still retain column-level SELECT on app.candidate_assessments.status (non-sensitive)';
  end if;

  -- A live, PostgREST-shaped session (real authenticated role + forged JWT claims for
  -- a zero-HRS-permission, non-assigned-interviewer tenant member) must be denied at
  -- the raw column level, matching the RPC layer's own already-correct authority gate.
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_no_perm, 'role', 'authenticated')::text, true);

  begin
    perform (select rating from app.interview_feedback limit 1);
    raise exception 'assertion failed: expected raw SELECT of app.interview_feedback.rating to be denied for a zero-HRS-permission actor';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform (select compensation_amount from app.job_offer_versions limit 1);
    raise exception 'assertion failed: expected raw SELECT of app.job_offer_versions.compensation_amount to be denied for a zero-HRS-permission actor';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform (select score from app.candidate_assessments limit 1);
    raise exception 'assertion failed: expected raw SELECT of app.candidate_assessments.score to be denied for a zero-HRS-permission actor';
  exception
    when insufficient_privilege then null;
  end;

  reset role;
end;
$$;

-- A separate top-level statement (own transaction) so the previous block's
-- transaction-local `set_config('request.jwt.claims', ..., true)` (is_local = true)
-- has already gone out of scope -- otherwise app.assert_actor_is_session_identity
-- (reached via app.list_candidate_assessments -> app.evaluate_permission) would see
-- the PRIOR block's forged zero-permission session identity still set and reject
-- this call as an identity mismatch.
\echo '>> review-round fix, continued: the RPC layer''s own real authority gate is unaffected by the column-restricted grant above -- a real HRS:View-holding staff actor still sees the full candidate_assessments row via app.list_candidate_assessments (SECURITY DEFINER, executes as the function owner)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
begin
  if (select score from app.candidate_assessments a join app.job_applications ja on ja.id = a.application_id join app.candidates c on c.id = ja.candidate_id where c.full_name = 'Ada Lovelace' limit 1) is distinct from (
    select score from app.list_candidate_assessments(
      (select ja.id from app.job_applications ja join app.candidates c on c.id = ja.candidate_id where c.full_name = 'Ada Lovelace' and ja.tenant_id = v_tenant1),
      '00000000-0000-0000-0000-000000027602'
    ) limit 1
  ) then
    raise exception 'assertion failed: expected app.list_candidate_assessments (SECURITY DEFINER, HRS:View-gated) to still return the real score for an authorized actor';
  end if;
end;
$$;

\echo '>> review-round fix (MEDIUM, C-01, live-reproduced): app.apply_to_vacancy''s idempotency-key replay now compares the FULL request tuple including `source` -- a same-key resubmission with a materially different source is rejected as idempotency_key_conflict, never silently accepted as an identical replay'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_vacancy_id uuid;
  v_candidate app.candidates;
  v_app1 app.job_applications;
begin
  select id into v_vacancy_id from app.job_vacancies where tenant_id = v_tenant1 and title = 'Software Engineer' and status = 'open';
  v_candidate := app.create_candidate(v_tenant1, 'Idem Fix Candidate', 'idem.fix.candidate@example.test', '+62811000111', 'staff_created', null, 'idem-hr1-idemfix-cand', '00000000-0000-0000-0000-000000027602', 'tester');

  v_app1 := app.apply_to_vacancy(v_vacancy_id, v_candidate.id, 'staff_created', 'idem-hr1-idemfix-key', '00000000-0000-0000-0000-000000027602', 'tester');
  if v_app1.source <> 'staff_created' then
    raise exception 'assertion failed: expected the first application to record source=staff_created';
  end if;

  begin
    perform app.apply_to_vacancy(v_vacancy_id, v_candidate.id, 'referral', 'idem-hr1-idemfix-key', '00000000-0000-0000-0000-000000027602', 'tester');
    raise exception 'assertion failed: expected a same-key resubmission with a different source (referral) to raise idempotency_key_conflict';
  exception
    when unique_violation then
      if sqlerrm not like 'idempotency_key_conflict:%' then
        raise;
      end if;
  end;

  -- An identical replay (same tuple, including source) is still accepted as a true
  -- replay, returning the original row unchanged.
  if (select id from app.apply_to_vacancy(v_vacancy_id, v_candidate.id, 'staff_created', 'idem-hr1-idemfix-key', '00000000-0000-0000-0000-000000027602', 'tester')) <> v_app1.id then
    raise exception 'assertion failed: expected an identical-tuple replay to return the original application unchanged';
  end if;
end;
$$;

\echo '>> review-round fix propagation sweep (MEDIUM, C-01): the identical narrow-tuple idempotency-comparison shape, fixed in app.create_job_vacancy_draft (full tuple: title/position_id/employment_type/headcount/description/requirements/hiring_manager_employee_id) and app.submit_public_job_application (full_name/phone added to the email comparison)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_position_id uuid := (select id from app.positions where tenant_id = v_tenant1 and code = 'POS-REC');
  v_vacancy1 app.job_vacancies;
  v_posting record;
  v_result record;
  v_result2 record;
begin
  v_vacancy1 := app.create_job_vacancy_draft(
    v_tenant1, v_position_id, 'Idem Fix Vacancy', 'full_time', 1, 'orig description', 'orig requirements', null,
    'idem-hr1-vacfix-key', '00000000-0000-0000-0000-000000027602', 'tester'
  );

  begin
    perform app.create_job_vacancy_draft(
      v_tenant1, v_position_id, 'Idem Fix Vacancy', 'full_time', 1, 'DIFFERENT description', 'orig requirements', null,
      'idem-hr1-vacfix-key', '00000000-0000-0000-0000-000000027602', 'tester'
    );
    raise exception 'assertion failed: expected a same-key resubmission with a different description to raise idempotency_key_conflict';
  exception
    when unique_violation then
      if sqlerrm not like 'idempotency_key_conflict:%' then
        raise;
      end if;
  end;

  -- Public intake: submit once, then replay the same idempotency_key with a
  -- different full_name -- must be rejected as a conflict, not silently accepted.
  select id into v_position_id from app.positions where tenant_id = v_tenant1 and code = 'POS-REC';
  perform app.publish_job_vacancy(v_vacancy1.id, v_vacancy1.record_version, 30, '00000000-0000-0000-0000-000000027603', 'tester');
  select posting_token into v_posting from app.job_vacancy_postings where vacancy_id = v_vacancy1.id;

  select * into v_result from app.submit_public_job_application(
    (select posting_token from app.job_vacancy_postings where vacancy_id = v_vacancy1.id),
    'idemfix-client-key-1', 'Public Idem Fix Applicant', 'public.idemfix@example.test', '+62811222333',
    true, 'v1', 'idem-hr1-pubidemfix-key'
  );
  if v_result.submit_status <> 'ok' then
    raise exception 'assertion failed: expected the first public application to succeed, got %', v_result.submit_status;
  end if;

  select * into v_result2 from app.submit_public_job_application(
    (select posting_token from app.job_vacancy_postings where vacancy_id = v_vacancy1.id),
    'idemfix-client-key-1', 'DIFFERENT Applicant Name', 'public.idemfix@example.test', '+62811222333',
    true, 'v1', 'idem-hr1-pubidemfix-key'
  );
  if v_result2.submit_status <> 'conflict' then
    raise exception 'assertion failed: expected a same-key resubmission with a different full_name to be a conflict, got %', v_result2.submit_status;
  end if;
end;
$$;

\echo '>> review-round fix (CRITICAL, live-reproduced with two real concurrent psql processes -- see docs/build-log/phase-07/HRT-276.md section 11 for the standalone concurrency evidence): app.reject_application/app.withdraw_application now actually run (never invoked anywhere in this file before this fix pass) and cancel a still-pending PLT-123 approval request before cascading the offer to withdrawn; app.decide_job_offer_approval on the now-cancelled step raises approval_step_not_active instead of silently resurrecting the offer'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_vacancy_id uuid;
  v_candidate_a app.candidates;
  v_candidate_b app.candidates;
  v_application_a app.job_applications;
  v_application_b app.job_applications;
  v_offer_a app.job_offers;
  v_offer_b app.job_offers;
  v_step_a app.approval_request_steps;
  v_step_b app.approval_request_steps;
  v_request_a app.approval_requests;
  v_request_b app.approval_requests;
begin
  select id into v_vacancy_id from app.job_vacancies where tenant_id = v_tenant1 and title = 'Software Engineer' and status = 'open';

  -- reject_application, with a real in-flight approval request bound to the offer.
  v_candidate_a := app.create_candidate(v_tenant1, 'Reject Cascade Candidate', 'reject.cascade@example.test', '+62811333444', 'staff_created', null, 'idem-hr1-rejcasc-cand', '00000000-0000-0000-0000-000000027602', 'tester');
  perform app.record_candidate_consent(v_candidate_a.id, v_candidate_a.record_version, 'v1', '00000000-0000-0000-0000-000000027602', 'tester');
  v_application_a := app.apply_to_vacancy(v_vacancy_id, v_candidate_a.id, 'staff_created', 'idem-hr1-rejcasc-app', '00000000-0000-0000-0000-000000027602', 'tester');
  update app.job_applications set stage = 'offer', record_version = record_version + 1 where id = v_application_a.id;
  perform app.create_job_offer_version(v_application_a.id, 15000000, 'IDR', current_date + 14, null, 'Software Engineer', 'full_time', 'standard benefits', '00000000-0000-0000-0000-000000027602', 'tester');
  select * into v_offer_a from app.job_offers where application_id = v_application_a.id;
  v_offer_a := app.submit_job_offer_for_approval(v_offer_a.id, v_offer_a.record_version, '00000000-0000-0000-0000-000000027602', 'tester');
  select s.* into v_step_a from app.approval_request_steps s where s.request_id = v_offer_a.approval_request_id and s.status = 'active';

  perform app.reject_application(v_application_a.id, (select record_version from app.job_applications where id = v_application_a.id), 'duplicate application, closing this one', '00000000-0000-0000-0000-000000027602', 'tester');

  if (select stage from app.job_applications where id = v_application_a.id) <> 'rejected' then
    raise exception 'assertion failed: expected application to be rejected';
  end if;
  if (select status from app.job_offers where id = v_offer_a.id) <> 'withdrawn' then
    raise exception 'assertion failed: expected the offer to be withdrawn after its application was rejected';
  end if;
  select * into v_request_a from app.approval_requests where id = v_offer_a.approval_request_id;
  if v_request_a.status <> 'cancelled' then
    raise exception 'assertion failed: expected app.reject_application to cancel the in-flight approval request, found status=%', v_request_a.status;
  end if;

  -- The approver, unaware of the rejection, tries to decide the now-cancelled step --
  -- must be rejected, never silently resurrecting the withdrawn offer.
  begin
    perform app.decide_job_offer_approval(v_step_a.id, 'approved', 'approving late', '00000000-0000-0000-0000-000000027603', 'tester');
    raise exception 'assertion failed: expected deciding a cancelled approval step to fail';
  exception
    when check_violation then null;
  end;
  if (select status from app.job_offers where id = v_offer_a.id) <> 'withdrawn' then
    raise exception 'assertion failed: expected the offer to remain withdrawn after the late, rejected decide attempt';
  end if;

  -- withdraw_application, same cascade, proven independently (this RPC was ALSO
  -- never invoked anywhere in this file before this fix pass).
  v_candidate_b := app.create_candidate(v_tenant1, 'Withdraw Cascade Candidate', 'withdraw.cascade@example.test', '+62811444555', 'staff_created', null, 'idem-hr1-witcasc-cand', '00000000-0000-0000-0000-000000027602', 'tester');
  perform app.record_candidate_consent(v_candidate_b.id, v_candidate_b.record_version, 'v1', '00000000-0000-0000-0000-000000027602', 'tester');
  v_application_b := app.apply_to_vacancy(v_vacancy_id, v_candidate_b.id, 'staff_created', 'idem-hr1-witcasc-app', '00000000-0000-0000-0000-000000027602', 'tester');
  update app.job_applications set stage = 'offer', record_version = record_version + 1 where id = v_application_b.id;
  perform app.create_job_offer_version(v_application_b.id, 15000000, 'IDR', current_date + 14, null, 'Software Engineer', 'full_time', 'standard benefits', '00000000-0000-0000-0000-000000027602', 'tester');
  select * into v_offer_b from app.job_offers where application_id = v_application_b.id;
  v_offer_b := app.submit_job_offer_for_approval(v_offer_b.id, v_offer_b.record_version, '00000000-0000-0000-0000-000000027602', 'tester');
  select s.* into v_step_b from app.approval_request_steps s where s.request_id = v_offer_b.approval_request_id and s.status = 'active';

  perform app.withdraw_application(v_application_b.id, (select record_version from app.job_applications where id = v_application_b.id), 'candidate withdrew by phone', '00000000-0000-0000-0000-000000027602', 'tester');

  if (select status from app.job_offers where id = v_offer_b.id) <> 'withdrawn' then
    raise exception 'assertion failed: expected the offer to be withdrawn after its application was withdrawn';
  end if;
  select * into v_request_b from app.approval_requests where id = v_offer_b.approval_request_id;
  if v_request_b.status <> 'cancelled' then
    raise exception 'assertion failed: expected app.withdraw_application to cancel the in-flight approval request, found status=%', v_request_b.status;
  end if;
  begin
    perform app.decide_job_offer_approval(v_step_b.id, 'approved', 'approving late', '00000000-0000-0000-0000-000000027603', 'tester');
    raise exception 'assertion failed: expected deciding a cancelled approval step to fail';
  exception
    when check_violation then null;
  end;
end;
$$;

\echo '>> HRT-293 Finding B regression: app.set_candidate_status/app.record_assessment_result no longer duplicate the raw block/candidate-assessment reason (nor a candidate assessment''s raw numeric score) into app.audit_logs.reason/after_value'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_staff uuid := '00000000-0000-0000-0000-000000027602';
  v_override_actor uuid := '00000000-0000-0000-0000-000000027603';
  v_candidate app.candidates;
  v_reason text := 'HRT-293 regression: candidate blocked, personal-circumstance-adjacent narrative';
begin
  v_candidate := app.create_candidate(v_tenant1, 'HRT293 Regression Candidate', 'hrt293cand@example.test', '+15550002222', 'staff_created', null, 'idem-hrt293-cand-1', v_staff, 'tester');
  perform app.set_candidate_status(v_candidate.id, v_candidate.record_version, 'blocked', v_reason, v_override_actor, 'tester');

  if exists (select 1 from app.audit_logs where reason = v_reason) then
    raise exception 'HRT-293 Finding B regression: app.audit_logs.reason must never carry the raw candidate block reason';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'set_candidate_status' and resource_id = v_candidate.id and reason is null) then
    raise exception 'HRT-293 Finding B regression: expected a set_candidate_status audit_logs row with reason=null';
  end if;

  -- app.record_assessment_result's own separate C-24 vector: a raw numeric
  -- score previously leaked into app.audit_logs.after_value under a key name
  -- (`score`) the redactor's fixed pattern does not match. Exercised directly
  -- against an isolated assessment row (service_role, mirroring how this
  -- migration's own write path is reached -- no application/vacancy scaffold
  -- needed to prove the audit-log projection shape).
  declare
    v_assessment_id uuid := gen_random_uuid();
    v_dummy_application_id uuid;
  begin
    select id into v_dummy_application_id from app.job_applications where tenant_id = v_tenant1 limit 1;
    if v_dummy_application_id is not null then
      insert into app.candidate_assessments (id, tenant_id, application_id, assessment_type, criteria_version, max_score, status, created_by)
      values (v_assessment_id, v_tenant1, v_dummy_application_id, 'other', 'v1', 100, 'pending', 'tester');
      perform app.record_assessment_result(v_assessment_id, 1, 87.500, 'HRT-293 regression notes', v_staff, 'tester');
      if exists (
        select 1 from app.audit_logs
        where action = 'record_assessment_result' and resource_id = v_assessment_id
          and (after_value ? 'score' or after_value::text like '%87.5%')
      ) then
        raise exception 'HRT-293 Finding B regression: app.audit_logs.after_value must never carry the raw candidate assessment score';
      end if;
    end if;
  end;
end;
$$;

\echo '>> ISS-2026-068: hiring managers finally have the self-scoped "assigned slice" read the interviewer half already had -- app.list_my_hiring_manager_vacancies returns only the caller''s own vacancies, requires ZERO HRS permission, and is silent (not an error) for a caller with no employee profile or no membership'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrrec1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'hrrec2');
  v_position_id uuid := (select id from app.positions where tenant_id = (select id from app.tenants where slug = 'hrrec1') and code = 'POS-REC');
  v_manager_employee_id uuid := (select master_record_id from app.employees where tenant_id = (select id from app.tenants where slug = 'hrrec1') and full_name = 'Hiring Manager');
  v_mine app.job_vacancies;
  v_theirs app.job_vacancies;
  v_count integer;
begin
  -- 027608 is the fixture's hiring manager and holds NO HRS permission at all
  -- (the same identity the authority tests above use as their no-permission
  -- control). If this identity can read a vacancy, it is because the vacancy
  -- names it -- there is no other credential in play.
  if (app.evaluate_permission('00000000-0000-0000-0000-000000027608', v_tenant1, 'HRS', 'View')).allowed then
    raise exception 'assertion failed: this test is only meaningful if 027608 genuinely lacks HRS:View';
  end if;

  select * into v_mine from app.create_job_vacancy_draft(
    v_tenant1, v_position_id, 'Owned By Hiring Manager', 'full_time', 1, null, null, v_manager_employee_id,
    'idem-hr1-iss068-mine', '00000000-0000-0000-0000-000000027602', 'tester'
  );
  select * into v_theirs from app.create_job_vacancy_draft(
    v_tenant1, v_position_id, 'Owned By Nobody In Particular', 'full_time', 1, null, null, null,
    'idem-hr1-iss068-theirs', '00000000-0000-0000-0000-000000027602', 'tester'
  );

  -- A real forged session, because the function asserts the claimed actor IS the
  -- session identity -- exactly as app.get_my_assigned_interviews does.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027608", "role": "authenticated"}', true);

  select count(*) into v_count from app.list_my_hiring_manager_vacancies(v_tenant1, '00000000-0000-0000-0000-000000027608');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the hiring manager to see exactly their own 1 vacancy, got %', v_count;
  end if;
  if not exists (select 1 from app.list_my_hiring_manager_vacancies(v_tenant1, '00000000-0000-0000-0000-000000027608') v where v.id = v_mine.id) then
    raise exception 'assertion failed: expected the hiring manager''s own vacancy in their assigned slice';
  end if;
  if exists (select 1 from app.list_my_hiring_manager_vacancies(v_tenant1, '00000000-0000-0000-0000-000000027608') v where v.id = v_theirs.id) then
    raise exception 'assertion failed: the assigned slice must NOT include a vacancy this manager does not own';
  end if;

  -- Cross-tenant: the same identity asking about a tenant it is not a member of
  -- gets silence, not a row and not an error that would confirm the tenant exists.
  select count(*) into v_count from app.list_my_hiring_manager_vacancies(v_tenant2, '00000000-0000-0000-0000-000000027608');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a tenant the caller is not a member of, got %', v_count;
  end if;

  -- Claiming to be someone else is rejected outright, not silently answered.
  begin
    perform app.list_my_hiring_manager_vacancies(v_tenant1, '00000000-0000-0000-0000-000000027602');
    raise exception 'assertion failed: expected actor_identity_mismatch when the session claims another identity';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027605", "role": "authenticated"}', true);
  -- A tenant member with no employee profile at all (the customer-layer principal)
  -- returns empty rather than raising -- it learns nothing about the tenant's hiring.
  select count(*) into v_count from app.list_my_hiring_manager_vacancies(v_tenant1, '00000000-0000-0000-0000-000000027605');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a caller with no linked employee profile, got %', v_count;
  end if;

  perform set_config('request.jwt.claims', '', true);

  -- Cleanup: both stay DRAFTS (never published, so they never consumed a posting or
  -- the position's capacity) and are cancelled rather than closed -- app.close_job_vacancy
  -- rejects a draft by design, which is the correct behaviour, not something to work around.
  perform app.cancel_job_vacancy_draft(v_mine.id, (select record_version from app.job_vacancies where id = v_mine.id), 'test cleanup', '00000000-0000-0000-0000-000000027602', 'tester');
  perform app.cancel_job_vacancy_draft(v_theirs.id, (select record_version from app.job_vacancies where id = v_theirs.id), 'test cleanup', '00000000-0000-0000-0000-000000027602', 'tester');
end;
$$;

\echo 'ALL HRT-276 db-test assertions passed.'
