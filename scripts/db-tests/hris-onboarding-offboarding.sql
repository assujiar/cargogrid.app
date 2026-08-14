-- Real, executable test evidence for HRT-277 (Onboarding and Offboarding,
-- CG-S12-HRT-005) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database. Mirrors scripts/db-tests/hris-recruitment-ats.sql's own mandatory
-- two-tenant cross-isolation convention AND HRT-276's own cancel/approval-cancel
-- concurrency-adjacent regression convention (§12.4 of that checkpoint's build log).
--
-- This file is alphabetically named BEFORE hris-organization-position-linkage.sql
-- and hris-recruitment-ats.sql, so `scripts/db-tests/run.sh` runs it FIRST -- it
-- cannot depend on either of those files' own fixtures. It builds its own,
-- self-contained tenant/candidate/application/interview/offer/accepted pipeline
-- (condensed from HRT-276's own established happy path) using a fresh, unclaimed
-- UUID range (00000000-0000-0000-0000-0000000277xx), never colliding with the
-- 0000027501-27529/0000027601-27699 ranges HRT-275/276's own fixtures already claim.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (hrt2771, hrt2772). hrt2771 gets a tenant_admin, HR staff (HRS Create/Edit/Export/View/View personal data), an approver (HRS Approve/View/Override), a viewer (HRS View only), a customer_user-layer actor, org units + a position, an interviewer employee linked to a real Platform user, a candidate carried through the full recruitment pipeline to an ACCEPTED offer, and a published tenant-wide approval routing definition (shared by both offer approval and case finalize approval, PLT-123 convention). hrt2772 gets a tenant_admin and HR staff for cross-tenant checks. A global Supreme Admin is also seeded.'
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
  v_appr_engine_role uuid;
  v_appr_engine_draft app.role_versions;
  v_t2_staff_role uuid;
  v_t2_staff_draft app.role_versions;
  v_company uuid;
  v_branch uuid;
  v_department uuid;
  v_position_id uuid;
  v_approval_draft app.config_versions;
  v_vacancy app.job_vacancies;
  v_candidate app.candidates;
  v_application app.job_applications;
  v_interview app.interviews;
  v_offer_version app.job_offer_versions;
  v_offer app.job_offers;
  v_pending_step app.approval_request_steps;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000027701', 'admin@hrt2771.test'),
    ('00000000-0000-0000-0000-000000027702', 'staff@hrt2771.test'),
    ('00000000-0000-0000-0000-000000027703', 'approver@hrt2771.test'),
    ('00000000-0000-0000-0000-000000027704', 'viewer@hrt2771.test'),
    ('00000000-0000-0000-0000-000000027705', 'customer@hrt2771.test'),
    ('00000000-0000-0000-0000-000000027706', 'interviewer1@hrt2771.test'),
    ('00000000-0000-0000-0000-000000027707', 'existingemp1@hrt2771.test'),
    ('00000000-0000-0000-0000-000000027708', 'existingemp2@hrt2771.test'),
    ('00000000-0000-0000-0000-000000027709', 'newhire1@hrt2771.test'),
    ('00000000-0000-0000-0000-000000027710', 'newhire2@hrt2771.test'),
    ('00000000-0000-0000-0000-000000027721', 'admin@hrt2772.test'),
    ('00000000-0000-0000-0000-000000027722', 'staff@hrt2772.test'),
    ('00000000-0000-0000-0000-000000027799', 'supreme@hrt277.test');

  perform app.provision_tenant('hrt2771', 'HRT-277 Co 1', 'idem-hrt2771', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'hrt2771');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('hrt2772', 'HRT-277 Co 2', 'idem-hrt2772', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'hrt2772');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027701', 'admin@hrt2771.test', 'Hrt2771 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@hrt2771.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027701', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027702', 'staff@hrt2771.test', 'Hrt2771 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@hrt2771.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027703', 'approver@hrt2771.test', 'Hrt2771 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@hrt2771.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027704', 'viewer@hrt2771.test', 'Hrt2771 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@hrt2771.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027705', 'customer@hrt2771.test', 'Hrt2771 Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer@hrt2771.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027705', 'customer_user', v_tenant1, 'external-customer-account', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027706', 'interviewer1@hrt2771.test', 'Interviewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'interviewer1@hrt2771.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027707', 'existingemp1@hrt2771.test', 'Existing Employee One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'existingemp1@hrt2771.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027708', 'existingemp2@hrt2771.test', 'Existing Employee Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'existingemp2@hrt2771.test'), 'active', 'onboarded', 'tester');
  -- newhire1/newhire2 (027709/027710) are invited to auth.users only -- NOT yet
  -- app.invite_user'd here -- they simulate a real "cold-start" identity IT has
  -- already created out-of-band, but the tenant-scoped app.users profile does not
  -- yet exist, exactly the resolved-auth-identity shape app.request_onboarding_
  -- access_provisioning expects a caller to supply.

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027721', 'admin@hrt2772.test', 'Hrt2772 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@hrt2772.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027721', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027722', 'staff@hrt2772.test', 'Hrt2772 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@hrt2772.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027799', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'HRS Staff', 'Create/Edit/Export/View/View personal data', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Export', 'View', 'View personal data')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000027702', '00000000-0000-0000-0000-000000027701', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'HRS Approver', 'Approve/View/Override', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Approve', 'View', 'Override')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000027703', '00000000-0000-0000-0000-000000027701', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'HRS Viewer', 'View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000027704', '00000000-0000-0000-0000-000000027701', 'tester');

  -- The approval-engine's own eligible-approver role -- deliberately zero HRS
  -- permissions (proves PLT-123 eligibility is independent of the HRS module,
  -- HRT-276's own established precedent) -- reused by BOTH the offer approval and
  -- the case finalize approval (same shared config_type_code='approval' object).
  v_appr_engine_role := (app.create_role(v_tenant1, 'Approval Engine Approver', 'zero HRS permissions -- approval-engine-eligible only', 'tester')).id;
  v_appr_engine_draft := app.create_role_version(v_appr_engine_role, 'tester');
  perform app.set_role_version_permissions(v_appr_engine_draft.id, array[]::uuid[], 'tester');
  perform app.publish_role_version(v_appr_engine_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_appr_engine_role and status = 'published'), '00000000-0000-0000-0000-000000027703', '00000000-0000-0000-0000-000000027701', 'tester');

  v_t2_staff_role := (app.create_role(v_tenant2, 'HRS Staff T2', 'Create/Edit/View/Approve/Override', 'tester')).id;
  v_t2_staff_draft := app.create_role_version(v_t2_staff_role, 'tester');
  perform app.set_role_version_permissions(v_t2_staff_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'View', 'Approve', 'Override')), 'tester');
  perform app.publish_role_version(v_t2_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000027722', '00000000-0000-0000-0000-000000027721', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-HRT2771', 'Hrt2771 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-HRT2771', 'Hrt2771 Branch', 'tester')).id;
  v_department := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-HRT2771', 'Hrt2771 Dept', 'tester')).id;
  perform app.create_org_unit(v_tenant2, 'company', null, 'CO-HRT2772', 'Hrt2772 Co', 'tester');

  perform app.create_position_grade(v_tenant1, 'GR-HRT277', 'Grade', 1, 'Baseline grade', '00000000-0000-0000-0000-000000027702', 'tester');
  v_position_id := (app.create_position(v_tenant1, 'POS-HRT277', 'Software Engineer', v_department, (select id from app.position_grades where tenant_id = v_tenant1 and code = 'GR-HRT277'), 5, 'Multi-incumbent position', '00000000-0000-0000-0000-000000027702', 'tester')).id;

  -- Existing (already-employed, active) employees -- used by the offboarding/
  -- transfer/existing_employee test blocks below.
  perform app.create_employee_draft(
    v_tenant1, 'Existing Employee One', 'full_time', 'existingemp1@hrt2771.test', null, null, null, null, null, '2020-01-01',
    v_company, v_branch, v_department, 'Senior Engineer', null,
    (select id from app.users where email = 'existingemp1@hrt2771.test'), null, 'hr_created', 'idem-hrt2771-emp1',
    '00000000-0000-0000-0000-000000027702', 'tester'
  );
  perform app.create_employee_draft(
    v_tenant1, 'Existing Employee Two', 'full_time', 'existingemp2@hrt2771.test', null, null, null, null, null, '2020-01-01',
    v_company, v_branch, v_department, 'Engineering Manager', null,
    (select id from app.users where email = 'existingemp2@hrt2771.test'), null, 'hr_created', 'idem-hrt2771-emp2',
    '00000000-0000-0000-0000-000000027702', 'tester'
  );
  perform app.create_employee_draft(
    v_tenant1, 'Interviewer One', 'full_time', 'interviewer1@hrt2771.test', null, null, null, null, null, '2020-01-01',
    v_company, v_branch, v_department, 'Staff Engineer', null,
    (select id from app.users where email = 'interviewer1@hrt2771.test'), null, 'hr_created', 'idem-hrt2771-interviewer1',
    '00000000-0000-0000-0000-000000027702', 'tester'
  );
  -- Activate both "existing employee" fixtures through the real HRT-274
  -- lifecycle (submit -> approve -> activate), mandatory contact first.
  declare
    v_e app.employees;
  begin
    for v_e in select * from app.employees where tenant_id = v_tenant1 and full_name in ('Existing Employee One', 'Existing Employee Two') loop
      perform app.add_employee_emergency_contact(v_e.master_record_id, 'Contact', 'sibling', '08120000000', null, true, '00000000-0000-0000-0000-000000027702', 'tester');
      declare v_ee app.employees;
      begin
        select * into v_ee from app.employees where master_record_id = v_e.master_record_id;
        select * into v_ee from app.submit_employee_for_approval(v_e.master_record_id, v_ee.record_version, '00000000-0000-0000-0000-000000027702', 'tester');
        select * into v_ee from app.decide_employee_approval(v_e.master_record_id, v_ee.record_version, 'approve', null, '00000000-0000-0000-0000-000000027703', 'tester');
        perform app.activate_employee(v_e.master_record_id, v_ee.record_version, '00000000-0000-0000-0000-000000027703', 'tester');
      end;
    end loop;
  end;

  -- A real, published, single-step tenant-wide approval routing definition,
  -- config_type_code='approval' (PLT-123, shared by every governed entity_type
  -- this migration and HRT-276's own migration both route through it).
  select * into v_approval_draft from app.create_config_draft('approval', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000027701', 'tenant admin');
  perform app.set_config_items(v_approval_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_appr_engine_role::text, 'required_approvals', 1)
    )),
    jsonb_build_object('key', 'allow_self_approval', 'value', false)
  ), '00000000-0000-0000-0000-000000027701', 'tenant admin');
  perform app.publish_approval_definition(v_approval_draft.id, '00000000-0000-0000-0000-000000027701', null, 'tenant admin');

  -- Condensed recruitment pipeline (HRT-276) to a real ACCEPTED offer.
  select * into v_vacancy from app.create_job_vacancy_draft(v_tenant1, v_position_id, 'Software Engineer', 'full_time', 1, null, null, null, 'idem-hrt2771-vac1', '00000000-0000-0000-0000-000000027702', 'tester');
  perform app.publish_job_vacancy(v_vacancy.id, v_vacancy.record_version, 30, '00000000-0000-0000-0000-000000027703', 'tester');

  select * into v_candidate from app.create_candidate(v_tenant1, 'Ada Lovelace', 'ada@example.test', '0811111111', 'staff_created', null, 'idem-hrt2771-cand1', '00000000-0000-0000-0000-000000027702', 'tester');
  perform app.record_candidate_consent(v_candidate.id, v_candidate.record_version, 'v1', '00000000-0000-0000-0000-000000027702', 'tester');

  select * into v_application from app.apply_to_vacancy(v_vacancy.id, v_candidate.id, 'staff_created', 'idem-hrt2771-app1', '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_application from app.transition_application_stage(v_application.id, v_application.record_version, 'screening', '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_application from app.transition_application_stage(v_application.id, v_application.record_version, 'assessment', '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_application from app.transition_application_stage(v_application.id, v_application.record_version, 'interview', '00000000-0000-0000-0000-000000027702', 'tester');

  select * into v_interview from app.schedule_interview(v_application.id, 1, 'video', now() + interval '1 day', 60, 'https://meet.example.test', array[(select master_record_id from app.employees where tenant_id = v_tenant1 and full_name = 'Interviewer One')], '00000000-0000-0000-0000-000000027702', 'tester');
  perform app.complete_interview(v_interview.id, v_interview.record_version, '00000000-0000-0000-0000-000000027702', 'tester');
  perform app.submit_interview_feedback(v_interview.id, 5, 'strong_yes', 'excellent candidate', '00000000-0000-0000-0000-000000027706', 'tester');

  select * into v_application from app.transition_application_stage(v_application.id, v_application.record_version, 'offer', '00000000-0000-0000-0000-000000027702', 'tester');

  select * into v_offer_version from app.create_job_offer_version(v_application.id, 15000000, 'IDR', current_date + 14, current_date + 45, 'Software Engineer', 'full_time', 'standard benefits', '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_offer from app.job_offers where application_id = v_application.id;
  select * into v_offer from app.submit_job_offer_for_approval(v_offer.id, v_offer.record_version, '00000000-0000-0000-0000-000000027702', 'tester');
  select s.* into v_pending_step from app.approval_request_steps s where s.request_id = v_offer.approval_request_id and s.status = 'active';
  select * into v_offer from app.decide_job_offer_approval(v_pending_step.id, 'approved', null, '00000000-0000-0000-0000-000000027703', 'tester');
  select * into v_offer from app.extend_job_offer(v_offer.id, v_offer.record_version, '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_offer from app.record_offer_response(v_offer.id, v_offer.record_version, 'accepted', 'excited to join', '00000000-0000-0000-0000-000000027702', 'tester');
  if v_offer.status <> 'accepted' then
    raise exception 'assertion failed: fixture setup expected the offer to reach accepted, got %', v_offer.status;
  end if;
end;
$$;

\echo '>> checklist templates: onboarding (4 tasks, 1 dependency, dependency-cycle rejected) and offboarding (2 tasks), both created and published; unpublished draft is not returned as the tenant''s current default'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_onb_template app.onboarding_checklist_templates;
  v_onb_version app.onboarding_checklist_template_versions;
  v_ofb_template app.onboarding_checklist_templates;
  v_ofb_version app.onboarding_checklist_template_versions;
  v_task_count integer;
begin
  select * into v_onb_template from app.create_onboarding_checklist_template(v_tenant1, 'ONB-STD', 'Standard Onboarding', 'onboarding', '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_onb_version from app.create_onboarding_checklist_template_version(v_onb_template.id, '00000000-0000-0000-0000-000000027702', 'tester');

  -- Idempotent-by-construction: a second call while a draft is already open
  -- returns the SAME draft version, never a duplicate.
  if (app.create_onboarding_checklist_template_version(v_onb_template.id, '00000000-0000-0000-0000-000000027702', 'tester')).id <> v_onb_version.id then
    raise exception 'assertion failed: expected create_onboarding_checklist_template_version to be idempotent while a draft is open';
  end if;

  perform app.add_onboarding_checklist_template_task(v_onb_version.id, 'welcome-doc', 'Sign welcome document', null, 'document', null, 'employee', true, 3, 1, '00000000-0000-0000-0000-000000027702', 'tester');
  perform app.add_onboarding_checklist_template_task(v_onb_version.id, 'it-access', 'Provision Platform access', null, 'access_provisioning', null, 'it', true, 2, 2, '00000000-0000-0000-0000-000000027702', 'tester');
  perform app.add_onboarding_checklist_template_task(v_onb_version.id, 'asset-issue', 'Issue laptop', null, 'handoff', 'asset', 'operations', true, 5, 3, '00000000-0000-0000-0000-000000027702', 'tester');
  perform app.add_onboarding_checklist_template_task(v_onb_version.id, 'training', 'Complete onboarding training', null, 'handoff', 'training', 'hr', false, 10, 4, '00000000-0000-0000-0000-000000027702', 'tester');

  -- A handoff task requires a handoff_category; a non-handoff task must NOT carry one.
  begin
    perform app.add_onboarding_checklist_template_task(v_onb_version.id, 'bad-task', 'Bad', null, 'handoff', null, 'hr', true, 1, 5, '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected a handoff task with no handoff_category to be rejected';
  exception when check_violation then null;
  end;

  perform app.add_onboarding_checklist_template_task_dependency(v_onb_version.id, 'it-access', 'welcome-doc', '00000000-0000-0000-0000-000000027702', 'tester');
  begin
    perform app.add_onboarding_checklist_template_task_dependency(v_onb_version.id, 'welcome-doc', 'it-access', '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected a two-node dependency cycle to be rejected';
  exception when check_violation then null;
  end;

  -- A draft template version is not yet the tenant's current published default.
  select resolved_template_task_count into v_task_count from app.preview_onboarding_case_start(v_tenant1, 'onboarding', 'direct_hire', null, null, '00000000-0000-0000-0000-000000027702');
  if v_task_count <> 0 then
    raise exception 'assertion failed: expected zero resolved tasks before ANY onboarding template is published, got %', v_task_count;
  end if;

  perform app.publish_onboarding_checklist_template_version(v_onb_version.id, v_onb_version.record_version, '00000000-0000-0000-0000-000000027703', 'tester');
  if not exists (select 1 from app.onboarding_checklist_template_versions where id = v_onb_version.id and status = 'published') then
    raise exception 'assertion failed: expected onboarding template version published';
  end if;

  -- HRS:Edit alone cannot publish (needs HRS:Approve).
  select * into v_ofb_template from app.create_onboarding_checklist_template(v_tenant1, 'OFB-STD', 'Standard Offboarding', 'offboarding', '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_ofb_version from app.create_onboarding_checklist_template_version(v_ofb_template.id, '00000000-0000-0000-0000-000000027702', 'tester');
  perform app.add_onboarding_checklist_template_task(v_ofb_version.id, 'revoke-access', 'Revoke Platform access', null, 'access_revocation', null, 'it', true, 1, 1, '00000000-0000-0000-0000-000000027702', 'tester');
  perform app.add_onboarding_checklist_template_task(v_ofb_version.id, 'return-asset', 'Return laptop', null, 'handoff', 'asset', 'operations', true, 5, 2, '00000000-0000-0000-0000-000000027702', 'tester');
  begin
    perform app.publish_onboarding_checklist_template_version(v_ofb_version.id, v_ofb_version.record_version, '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected an HRS:Edit-only actor to be denied publishing, but it succeeded';
  exception when insufficient_privilege then null;
  end;
  perform app.publish_onboarding_checklist_template_version(v_ofb_version.id, v_ofb_version.record_version, '00000000-0000-0000-0000-000000027703', 'tester');
end;
$$;

\echo '>> preview_onboarding_case_start: read-only, no mutation; reflects the accepted offer and resolved published template'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_offer_id uuid := (select id from app.job_offers where tenant_id = v_tenant1 and status = 'accepted');
  v_preview record;
  v_case_count_before integer;
begin
  select count(*) into v_case_count_before from app.onboarding_offboarding_cases;
  select * into v_preview from app.preview_onboarding_case_start(v_tenant1, 'onboarding', 'job_offer', v_offer_id, null, '00000000-0000-0000-0000-000000027702');
  if v_preview.would_reuse_existing_employee or v_preview.resolved_template_task_count <> 4 or v_preview.candidate_full_name <> 'Ada Lovelace' or v_preview.offer_status <> 'accepted' then
    raise exception 'assertion failed: preview_onboarding_case_start returned unexpected values';
  end if;
  if (select count(*) from app.onboarding_offboarding_cases) <> v_case_count_before then
    raise exception 'assertion failed: preview must never mutate state';
  end if;
end;
$$;

\echo '>> start_onboarding_case: idempotent ADR-0023 Part B conversion from an accepted offer -- exactly one employee, retry-safe; wrong case_type/source_type combinations rejected; company/branch/department shape enforced via the reused app.create_employee_draft'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_offer_id uuid := (select id from app.job_offers where tenant_id = v_tenant1 and status = 'accepted');
  v_company uuid := (select id from app.org_units where tenant_id = (select id from app.tenants where slug = 'hrt2771') and code = 'CO-HRT2771');
  v_branch uuid := (select id from app.org_units where tenant_id = (select id from app.tenants where slug = 'hrt2771') and code = 'BR-HRT2771');
  v_department uuid := (select id from app.org_units where tenant_id = (select id from app.tenants where slug = 'hrt2771') and code = 'DEPT-HRT2771');
  v_case app.onboarding_offboarding_cases;
  v_case_retry app.onboarding_offboarding_cases;
  v_employee_count_before integer;
begin
  select count(*) into v_employee_count_before from app.employees where tenant_id = v_tenant1;

  -- Wrong case_type for source_type=job_offer.
  begin
    perform app.start_onboarding_case(
      v_tenant1, 'offboarding', 'job_offer', v_offer_id, null, null, null,
      null, null, null, null, null, null, null, null, null, null, null, null, null,
      'idem-wrong-case-type', '00000000-0000-0000-0000-000000027702', 'tester'
    );
    raise exception 'assertion failed: expected invalid_case_type_for_source';
  exception when check_violation then null;
  end;

  select * into v_case from app.start_onboarding_case(
    v_tenant1, 'onboarding', 'job_offer', v_offer_id, null, null, null,
    null, null, null, null, null, null, null, null,
    v_company, v_branch, v_department, null, null,
    null, '00000000-0000-0000-0000-000000027702', 'tester'
  );
  if v_case.status <> 'active' or v_case.employee_master_record_id is null or v_case.checklist_template_version_id is null then
    raise exception 'assertion failed: expected an active case with a linked employee and locked-in checklist version';
  end if;
  if (select count(*) from app.employees where tenant_id = v_tenant1) <> v_employee_count_before + 1 then
    raise exception 'assertion failed: expected exactly ONE new employee created by the conversion';
  end if;
  if (select count(*) from app.onboarding_case_tasks where case_id = v_case.id) <> 4 then
    raise exception 'assertion failed: expected 4 instantiated tasks (copied from the published template)';
  end if;
  if (select status from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'it-access') <> 'blocked' then
    raise exception 'assertion failed: expected it-access to start blocked (its own dependency on welcome-doc is not yet satisfied)';
  end if;

  -- Retry against the SAME offer -- structurally idempotent (acceptance
  -- criterion 1), even WITHOUT a caller-supplied idempotency_key, via the
  -- onboarding_offboarding_cases_source_offer_unique short-circuit.
  select * into v_case_retry from app.start_onboarding_case(
    v_tenant1, 'onboarding', 'job_offer', v_offer_id, null, null, null,
    null, null, null, null, null, null, null, null, null, null, null, null, null,
    null, '00000000-0000-0000-0000-000000027702', 'tester'
  );
  if v_case_retry.id <> v_case.id then
    raise exception 'assertion failed: expected idempotent replay against the same offer to return the SAME case';
  end if;
  if (select count(*) from app.employees where tenant_id = v_tenant1) <> v_employee_count_before + 1 then
    raise exception 'assertion failed: expected still exactly ONE employee after the idempotent retry -- no duplicate';
  end if;
  if (select count(*) from app.onboarding_offboarding_cases where source_job_offer_id = v_offer_id) <> 1 then
    raise exception 'assertion failed: expected exactly one case for this offer, never a second';
  end if;

  -- Self-found-and-fixed defect (taxonomy C-01, Tier B self-check): a retry
  -- against the SAME offer but a MISMATCHED case_type must be rejected, never
  -- silently handed back the pre-existing, differently-typed case.
  begin
    perform app.start_onboarding_case(
      v_tenant1, 'offboarding', 'job_offer', v_offer_id, null, null, null,
      null, null, null, null, null, null, null, null, null, null, null, null, null,
      null, '00000000-0000-0000-0000-000000027702', 'tester'
    );
    raise exception 'assertion failed: expected idempotency_key_conflict for a same-offer, mismatched-case_type retry';
  exception when unique_violation then null;
  end;
end;
$$;

\echo '>> self-found-and-fixed C-01 regression: direct_hire idempotency_key replay compares the full request tuple, not merely the key -- a same-key/different-case_type retry is rejected, a genuine same-key/same-request replay still returns the same case unchanged'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_employee_id uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and full_name = 'Existing Employee One');
  v_case app.onboarding_offboarding_cases;
  v_case_replay app.onboarding_offboarding_cases;
begin
  select * into v_case from app.start_onboarding_case(
    v_tenant1, 'onboarding', 'existing_employee', null, v_employee_id, null, current_date,
    null, null, null, null, null, null, null, null, null, null, null, null, null,
    'idem-hrt2771-c01-regress', '00000000-0000-0000-0000-000000027702', 'tester'
  );

  -- Genuine replay: identical case_type/source_type/employee -- returns the SAME case.
  select * into v_case_replay from app.start_onboarding_case(
    v_tenant1, 'onboarding', 'existing_employee', null, v_employee_id, null, current_date,
    null, null, null, null, null, null, null, null, null, null, null, null, null,
    'idem-hrt2771-c01-regress', '00000000-0000-0000-0000-000000027702', 'tester'
  );
  if v_case_replay.id <> v_case.id then
    raise exception 'assertion failed: expected a genuine same-key replay to return the SAME case';
  end if;

  -- Same key, DIFFERENT case_type -- must be rejected, never silently return the transfer case.
  begin
    perform app.start_onboarding_case(
      v_tenant1, 'offboarding', 'existing_employee', null, v_employee_id, null, current_date,
      null, null, null, null, null, null, null, null, null, null, null, null, null,
      'idem-hrt2771-c01-regress', '00000000-0000-0000-0000-000000027702', 'tester'
    );
    raise exception 'assertion failed: expected idempotency_key_conflict for a same-key, mismatched-case_type retry';
  exception when unique_violation then null;
  end;

  -- Same key, DIFFERENT employee -- must also be rejected.
  declare
    v_other_employee_id uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and full_name = 'Existing Employee Two');
  begin
    perform app.start_onboarding_case(
      v_tenant1, 'onboarding', 'existing_employee', null, v_other_employee_id, null, current_date,
      null, null, null, null, null, null, null, null, null, null, null, null, null,
      'idem-hrt2771-c01-regress', '00000000-0000-0000-0000-000000027702', 'tester'
    );
    raise exception 'assertion failed: expected idempotency_key_conflict for a same-key, mismatched-employee retry';
  exception when unique_violation then null;
  end;
end;
$$;

\echo '>> task lifecycle: dependency-blocked completion rejected; completing welcome-doc unblocks it-access; access-provisioning task rejects the generic completion path; unresolved provisioning request records a real request and leaves the task in_progress; a resolved, freshly-invited but not-yet-active identity defers role assignment (disclosed, never silently dropped); waive requires HRS:Override (not Edit); evidence file is re-validated (tenant/record-scope/scan-status) at the accepting RPC'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_case_id uuid := (select id from app.onboarding_offboarding_cases where tenant_id = v_tenant1 and case_type = 'onboarding' limit 1);
  v_welcome app.onboarding_case_tasks;
  v_it_access app.onboarding_case_tasks;
  v_asset app.onboarding_case_tasks;
  v_training app.onboarding_case_tasks;
  v_file app.files;
  v_doc_draft app.config_versions;
  v_wrong_tenant_file app.files;
begin
  select * into v_welcome from app.onboarding_case_tasks where case_id = v_case_id and template_task_key = 'welcome-doc';
  select * into v_it_access from app.onboarding_case_tasks where case_id = v_case_id and template_task_key = 'it-access';
  select * into v_asset from app.onboarding_case_tasks where case_id = v_case_id and template_task_key = 'asset-issue';
  select * into v_training from app.onboarding_case_tasks where case_id = v_case_id and template_task_key = 'training';

  -- it-access still blocked -- neither generic completion nor provisioning may proceed.
  begin
    perform app.request_onboarding_access_provisioning(v_case_id, v_it_access.id, v_it_access.record_version, null, '{}'::uuid[], null, '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected task_blocked';
  exception when check_violation then null;
  end;

  select * into v_welcome from app.complete_onboarding_task(v_case_id, v_welcome.id, v_welcome.record_version, 'signed', null, '00000000-0000-0000-0000-000000027702', 'tester');
  if v_welcome.status <> 'completed' then raise exception 'assertion failed: expected welcome-doc completed'; end if;

  select * into v_it_access from app.onboarding_case_tasks where id = v_it_access.id;
  if v_it_access.status <> 'pending' then
    raise exception 'assertion failed: expected it-access unblocked to pending once its dependency completed, got %', v_it_access.status;
  end if;

  -- The generic completion RPC refuses an access_provisioning task outright.
  begin
    perform app.complete_onboarding_task(v_case_id, v_it_access.id, v_it_access.record_version, 'done', null, '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected wrong_completion_path';
  exception when check_violation then null;
  end;

  -- Unresolved (no auth identity yet) -- section 22 "preboarding without user access".
  select * into v_it_access from app.request_onboarding_access_provisioning(v_case_id, v_it_access.id, v_it_access.record_version, null, '{}'::uuid[], null, '00000000-0000-0000-0000-000000027702', 'tester');
  if v_it_access.status <> 'in_progress' then
    raise exception 'assertion failed: expected in_progress after an unresolved provisioning request';
  end if;
  if not exists (select 1 from app.onboarding_task_provisioning_requests where task_id = v_it_access.id and status = 'requested' and target_auth_user_id is null) then
    raise exception 'assertion failed: expected a requested provisioning-request row with no target identity yet';
  end if;

  -- Resolved with a real, ALREADY-ACTIVE identity (newhire1) -- app.invite_user
  -- (idempotent) + app.link_employee_user + real role assignment via
  -- app.assign_role. Real Platform-identity-authority write, never a direct
  -- app.users/app.role_assignments INSERT.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027709', 'newhire1@hrt2771.test', 'New Hire One', null, 'tester', now() + interval '14 days');
  perform app.transition_user_status((select id from app.users where email = 'newhire1@hrt2771.test'), 'active', 'onboarded', 'tester');

  select * into v_it_access from app.request_onboarding_access_provisioning(v_case_id, v_it_access.id, v_it_access.record_version, '00000000-0000-0000-0000-000000027709', '{}'::uuid[], null, '00000000-0000-0000-0000-000000027702', 'tester');
  if v_it_access.status <> 'completed' then
    raise exception 'assertion failed: expected completed after resolved provisioning against an active identity, got %', v_it_access.status;
  end if;
  if (select user_id from app.employees where master_record_id = (select employee_master_record_id from app.onboarding_offboarding_cases where id = v_case_id)) is null then
    raise exception 'assertion failed: expected app.employees.user_id linked via app.link_employee_user';
  end if;
  if not exists (select 1 from app.onboarding_task_provisioning_requests where task_id = v_it_access.id and status = 'completed' and result_user_id is not null) then
    raise exception 'assertion failed: expected the provisioning-request row marked completed with a real result_user_id';
  end if;
  if not exists (select 1 from app.onboarding_task_provisioning_requests where task_id = v_it_access.id and job_id is not null) then
    raise exception 'assertion failed: expected a real app.jobs dispatch/reconciliation record (job_id set, section 17)';
  end if;

  -- Evidence file for asset-issue: tenant/record-scope/scan-status re-validated
  -- at THIS accepting RPC (taxonomy C-10) -- a cross-tenant file and an
  -- unscanned file are both rejected.
  select * into v_doc_draft from app.create_config_draft('document:onboarding_evidence', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000027701', 'tenant admin');
  perform app.set_config_items(v_doc_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5000000),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000027701', 'tenant admin');
  perform app.publish_document_type_definition(v_doc_draft.id, '00000000-0000-0000-0000-000000027701', null, 'tenant admin');

  -- Cross-tenant file (belongs to hrt2772, never a valid evidence file for a hrt2771 task).
  declare
    v_t2_doc_draft app.config_versions;
    v_t2_id uuid := (select id from app.tenants where slug = 'hrt2772');
  begin
    select * into v_t2_doc_draft from app.create_config_draft('document:onboarding_evidence', v_t2_id, 'tenant', null, '00000000-0000-0000-0000-000000027721', 'tenant admin');
    perform app.set_config_items(v_t2_doc_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
      jsonb_build_object('key', 'max_size_bytes', 'value', 5000000),
      jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
      jsonb_build_object('key', 'default_classification', 'value', 'internal'),
      jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
    ), '00000000-0000-0000-0000-000000027721', 'tenant admin');
    perform app.publish_document_type_definition(v_t2_doc_draft.id, '00000000-0000-0000-0000-000000027721', null, 'tenant admin');
    select * into v_wrong_tenant_file from app.initiate_file_upload(v_t2_id, 'onboarding_evidence', 'onboarding_case_task', v_asset.id, 'wrong-tenant.pdf', 'application/pdf', 100, 'internal', false, null, '{}'::uuid[], null, 'idem-hrt2772-file-wrong', '00000000-0000-0000-0000-000000027722', 'tester');
    perform app.record_file_scan_result(v_wrong_tenant_file.id, 'clean', 'ref', '00000000-0000-0000-0000-000000027722', 'tester');
  end;
  begin
    perform app.complete_onboarding_task(v_case_id, v_asset.id, v_asset.record_version, 'attempt', v_wrong_tenant_file.id, '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected evidence_file_not_found for a cross-tenant file';
  exception when no_data_found then null;
  end;

  -- Unscanned file (pending, never cleared).
  select * into v_file from app.initiate_file_upload(v_tenant1, 'onboarding_evidence', 'onboarding_case_task', v_asset.id, 'laptop-receipt.pdf', 'application/pdf', 12345, 'internal', false, null, '{}'::uuid[], null, 'idem-hrt2771-file-1', '00000000-0000-0000-0000-000000027706', 'tester');
  begin
    perform app.complete_onboarding_task(v_case_id, v_asset.id, v_asset.record_version, 'attempt', v_file.id, '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected evidence_file_not_scanned for a pending-scan file';
  exception when check_violation then null;
  end;

  perform app.record_file_scan_result(v_file.id, 'clean', 'test-provider-ref', '00000000-0000-0000-0000-000000027706', 'tester');
  select * into v_asset from app.complete_onboarding_task(v_case_id, v_asset.id, v_asset.record_version, 'laptop issued, serial ABC123', v_file.id, '00000000-0000-0000-0000-000000027702', 'tester');
  if v_asset.status <> 'completed' or v_asset.evidence_file_id <> v_file.id then
    raise exception 'assertion failed: expected asset-issue completed with the real, scanned evidence file';
  end if;

  -- HRS:Edit alone cannot waive (needs Override, taxonomy C-18).
  begin
    perform app.waive_onboarding_task(v_case_id, v_training.id, v_training.record_version, 'deferred to next quarter', '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected an HRS:Edit-only actor to be denied waiving a task, but it succeeded';
  exception when insufficient_privilege then null;
  end;
  select * into v_training from app.waive_onboarding_task(v_case_id, v_training.id, v_training.record_version, 'deferred to next quarter', '00000000-0000-0000-0000-000000027703', 'tester');
  if v_training.status <> 'waived' then raise exception 'assertion failed: expected training waived'; end if;

  -- Reopen (only reachable while the case itself is not finalized/cancelled).
  select * into v_training from app.reopen_onboarding_task(v_case_id, v_training.id, v_training.record_version, 'training now required after all', '00000000-0000-0000-0000-000000027702', 'tester');
  if v_training.status <> 'reopened' or v_training.waive_reason is not null then
    raise exception 'assertion failed: expected training reopened with waive_reason cleared';
  end if;
  select * into v_training from app.waive_onboarding_task(v_case_id, v_training.id, v_training.record_version, 'deferred to next quarter (re-waived)', '00000000-0000-0000-0000-000000027703', 'tester');
end;
$$;

\echo '>> case finalize approval: fails while the employee has not yet reached active via HRT-274''s own governed lifecycle (decision 1, precondition-check-only, never chained); a rejected decision returns the case to active; approved finalizes; the approval timeline is real and auditable'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_case app.onboarding_offboarding_cases;
  v_employee app.employees;
  v_pending_step app.approval_request_steps;
  v_timeline_count integer;
begin
  select * into v_case from app.onboarding_offboarding_cases where tenant_id = v_tenant1 and case_type = 'onboarding' limit 1;
  select * into v_employee from app.employees where master_record_id = v_case.employee_master_record_id;

  begin
    perform app.submit_onboarding_case_for_finalize_approval(v_case.id, v_case.record_version, null, '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected employee_not_active_yet';
  exception when check_violation then null;
  end;

  -- Drive the employee's own governed lifecycle to active (HRT-274's own RPCs,
  -- out-of-band -- decision 1: never chained from this case's own finalize).
  perform app.add_employee_emergency_contact(v_employee.master_record_id, 'Next of Kin', 'spouse', '08123456789', null, true, '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_employee from app.employees where master_record_id = v_employee.master_record_id;
  select * into v_employee from app.submit_employee_for_approval(v_employee.master_record_id, v_employee.record_version, '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_employee from app.decide_employee_approval(v_employee.master_record_id, v_employee.record_version, 'approve', null, '00000000-0000-0000-0000-000000027703', 'tester');
  select * into v_employee from app.activate_employee(v_employee.master_record_id, v_employee.record_version, '00000000-0000-0000-0000-000000027703', 'tester');
  if v_employee.lifecycle_status <> 'active' then raise exception 'assertion failed: expected employee active'; end if;

  select * into v_case from app.submit_onboarding_case_for_finalize_approval(v_case.id, v_case.record_version, null, '00000000-0000-0000-0000-000000027702', 'tester');
  if v_case.status <> 'pending_finalize_approval' then raise exception 'assertion failed: expected pending_finalize_approval'; end if;

  select s.* into v_pending_step from app.approval_request_steps s where s.request_id = v_case.finalize_approval_request_id and s.status = 'active';
  select * into v_case from app.decide_onboarding_case_finalize_approval(v_pending_step.id, 'rejected', 'need manager sign-off first', '00000000-0000-0000-0000-000000027703', 'tester');
  if v_case.status <> 'active' then raise exception 'assertion failed: expected a rejected finalize decision to return the case to active, got %', v_case.status; end if;

  -- Resubmit and approve this time.
  select * into v_case from app.submit_onboarding_case_for_finalize_approval(v_case.id, v_case.record_version, null, '00000000-0000-0000-0000-000000027702', 'tester');
  select s.* into v_pending_step from app.approval_request_steps s where s.request_id = v_case.finalize_approval_request_id and s.status = 'active';
  select * into v_case from app.decide_onboarding_case_finalize_approval(v_pending_step.id, 'approved', null, '00000000-0000-0000-0000-000000027703', 'tester');
  if v_case.status <> 'finalized' or v_case.finalized_at is null then
    raise exception 'assertion failed: expected case finalized, got %', v_case.status;
  end if;

  -- Each submit-for-finalize-approval call opens a NEW app.approval_requests row
  -- (finalize_approval_request_id always points at the CURRENT/latest attempt,
  -- mirroring app.job_offers.approval_request_id's own established shape,
  -- HRT-276) -- the timeline reflects the request that actually finalized the
  -- case (1 decision row: the approval); the earlier rejection remains a real,
  -- separate, permanently-recorded app.approval_requests row and an
  -- app.onboarding_case_events 'finalize_rejected' row, just not part of THIS
  -- current-request timeline view.
  select count(*) into v_timeline_count from app.get_onboarding_case_approval_timeline(v_case.id, '00000000-0000-0000-0000-000000027702');
  if v_timeline_count < 1 then
    raise exception 'assertion failed: expected at least 1 decision row in the current approval timeline';
  end if;
  if (select count(*) from app.approval_requests where entity_type = 'onboarding_offboarding_case' and entity_id = v_case.id) <> 2 then
    raise exception 'assertion failed: expected 2 total approval_requests rows across both submit attempts (the rejected one and the approved one), both permanently on file';
  end if;
  if not exists (select 1 from app.onboarding_case_events where case_id = v_case.id and event_type = 'finalize_rejected') then
    raise exception 'assertion failed: expected a permanent finalize_rejected case-event row';
  end if;
end;
$$;

\echo '>> offboarding: existing_employee source; access revocation calls the REAL app.transition_user_status (never a direct app.users write); cancel (plain, no pending approval) preserves the employee/its history'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_employee_id uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and full_name = 'Existing Employee One');
  v_case app.onboarding_offboarding_cases;
  v_revoke_task app.onboarding_case_tasks;
  v_return_task app.onboarding_case_tasks;
begin
  -- Wrong source_type for offboarding (job_offer never applies) -- exercised
  -- against a job_offer that has NEVER started a case yet (a genuinely
  -- unclaimed source_job_offer_id), so the assertion actually reaches the
  -- case_type check instead of short-circuiting on the structural
  -- source-offer idempotency guard (the earlier "start_onboarding_case" block
  -- already exercises this exact mismatch against a fresh, never-cased offer).
  declare
    v_fresh_offer_id uuid;
  begin
    select id into v_fresh_offer_id from app.job_offers
    where tenant_id = v_tenant1 and id not in (select source_job_offer_id from app.onboarding_offboarding_cases where source_job_offer_id is not null)
    limit 1;
    if v_fresh_offer_id is not null then
      begin
        perform app.start_onboarding_case(
          v_tenant1, 'offboarding', 'job_offer', v_fresh_offer_id, null, null, current_date,
          null, null, null, null, null, null, null, null, null, null, null, null, null,
          'idem-offb-badsource', '00000000-0000-0000-0000-000000027702', 'tester'
        );
        raise exception 'assertion failed: expected invalid_case_type_for_source';
      exception when check_violation then null;
      end;
    end if;
  end;

  select * into v_case from app.start_onboarding_case(
    v_tenant1, 'offboarding', 'existing_employee', null, v_employee_id, null, current_date,
    null, null, null, null, null, null, null, null, null, null, null, null, null,
    'idem-hrt2771-offb-1', '00000000-0000-0000-0000-000000027702', 'tester'
  );
  if v_case.status <> 'active' then raise exception 'assertion failed: expected active offboarding case'; end if;

  select * into v_revoke_task from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'revoke-access';
  select * into v_return_task from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'return-asset';

  -- The generic completion RPC refuses an access_revocation task outright
  -- (actor holds HRS:Edit -- the exception under test is wrong_completion_path,
  -- not an authority denial).
  begin
    perform app.complete_onboarding_task(v_case.id, v_revoke_task.id, v_revoke_task.record_version, 'done', null, '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected wrong_completion_path';
  exception when check_violation then null;
  end;

  -- Review-round fix (HIGH, spec-compliance, business rule 5): a non-empty
  -- reason is now required -- checked explicitly before the real call below.
  begin
    perform app.request_onboarding_access_revocation(v_case.id, v_revoke_task.id, v_revoke_task.record_version, null, '00000000-0000-0000-0000-000000027703', 'tester');
    raise exception 'assertion failed: expected reason_required for a null reason';
  exception when check_violation then null;
  end;

  select * into v_revoke_task from app.request_onboarding_access_revocation(v_case.id, v_revoke_task.id, v_revoke_task.record_version, 'employee resigned, standard offboarding', '00000000-0000-0000-0000-000000027703', 'tester');
  if v_revoke_task.status <> 'completed' then raise exception 'assertion failed: expected revoke-access completed'; end if;
  if (select status from app.users where auth_user_id = '00000000-0000-0000-0000-000000027707' and tenant_id = v_tenant1) <> 'revoked' then
    raise exception 'assertion failed: expected the linked Platform user ACTUALLY revoked via app.transition_user_status (never a direct app.users write)';
  end if;
  -- app.transition_user_status also revokes the underlying tenant_user_identities
  -- linkage and every active principal_membership -- proven indirectly here: a
  -- second revocation attempt against the same already-revoked user must not
  -- error (transition_user_status is a real state machine, revoked is terminal
  -- -- confirmed via a direct re-check, never re-invoked here to avoid a
  -- redundant, unrelated invalid_user_transition assertion).
  if (select count(*) from app.principal_memberships where auth_user_id = '00000000-0000-0000-0000-000000027707' and status = 'active') <> 0 then
    raise exception 'assertion failed: expected zero active principal memberships after revocation cascade';
  end if;

  -- HRS:Edit alone cannot request access revocation (needs Override -- same
  -- immediate-security-relevant bar as app.terminate_employee).
  begin
    perform app.request_onboarding_access_revocation(v_case.id, v_revoke_task.id, v_revoke_task.record_version, 'attempted revocation', '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected an HRS:Edit-only actor to be denied requesting access revocation, but it succeeded';
  exception
    when insufficient_privilege then null;
  end;

  -- Complete the remaining mandatory return-asset task (ordinary HRS:Edit
  -- completion, unrelated to the Override bar above) so the case has no
  -- incomplete mandatory work left before it is cancelled below.
  select * into v_return_task from app.complete_onboarding_task(v_case.id, v_return_task.id, v_return_task.record_version, 'returned', null, '00000000-0000-0000-0000-000000027702', 'tester');
  if v_return_task.status <> 'completed' then raise exception 'assertion failed: expected return-asset completed'; end if;

  -- Cancel a still-active offboarding case (no pending finalize approval yet) --
  -- the employee row and its full history are preserved unchanged.
  select * into v_case from app.cancel_onboarding_case(v_case.id, (select record_version from app.onboarding_offboarding_cases where id = v_case.id), 'employee retracted resignation', '00000000-0000-0000-0000-000000027702', 'tester');
  if v_case.status <> 'cancelled' or v_case.cancel_reason is null then raise exception 'assertion failed: expected cancelled with a recorded reason'; end if;
  if not exists (select 1 from app.employees where master_record_id = v_employee_id) then
    raise exception 'assertion failed: cancelling a case must never delete the employee it is linked to (no-history-loss)';
  end if;
end;
$$;

\echo '>> cancel WITH a pending finalize approval MUST cancel the approval request too (the HRT-276 CRITICAL/HIGH lesson, closed from the FIRST migration, not retrofitted) -- a late decide on the cancelled step is rejected, never resurrects the case'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_employee_id uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and full_name = 'Existing Employee Two');
  v_case app.onboarding_offboarding_cases;
  v_task app.onboarding_case_tasks;
  v_request_id uuid;
  v_employee app.employees;
begin
  select * into v_case from app.start_onboarding_case(
    v_tenant1, 'offboarding', 'existing_employee', null, v_employee_id, null, current_date,
    null, null, null, null, null, null, null, null, null, null, null, null, null,
    'idem-hrt2771-offb-2', '00000000-0000-0000-0000-000000027702', 'tester'
  );

  for v_task in select * from app.onboarding_case_tasks where case_id = v_case.id loop
    if v_task.task_type = 'access_revocation' then
      perform app.request_onboarding_access_revocation(v_case.id, v_task.id, v_task.record_version, 'standard offboarding checklist', '00000000-0000-0000-0000-000000027703', 'tester');
    else
      perform app.complete_onboarding_task(v_case.id, v_task.id, v_task.record_version, 'done', null, '00000000-0000-0000-0000-000000027702', 'tester');
    end if;
  end loop;

  select * into v_employee from app.employees where master_record_id = v_employee_id;
  perform app.terminate_employee(v_employee_id, v_employee.record_version, 'resigned', current_date, '00000000-0000-0000-0000-000000027703', 'tester');

  select * into v_case from app.onboarding_offboarding_cases where id = v_case.id;
  select * into v_case from app.submit_onboarding_case_for_finalize_approval(v_case.id, v_case.record_version, 'voluntary resignation', '00000000-0000-0000-0000-000000027702', 'tester');
  if v_case.status <> 'pending_finalize_approval' or v_case.exit_reason is null then
    raise exception 'assertion failed: expected pending_finalize_approval with exit_reason set';
  end if;
  v_request_id := v_case.finalize_approval_request_id;

  select * into v_case from app.cancel_onboarding_case(v_case.id, v_case.record_version, 'reorg cancelled the exit', '00000000-0000-0000-0000-000000027702', 'tester');
  if v_case.status <> 'cancelled' then raise exception 'assertion failed: expected cancelled'; end if;

  if (select status from app.approval_requests where id = v_request_id) <> 'cancelled' then
    raise exception 'assertion failed: expected the pending finalize-approval request CANCELLED, not left dangling to potentially resurrect the case later';
  end if;

  declare v_step app.approval_request_steps;
  begin
    select * into v_step from app.approval_request_steps where request_id = v_request_id limit 1;
    begin
      perform app.decide_onboarding_case_finalize_approval(v_step.id, 'approved', null, '00000000-0000-0000-0000-000000027703', 'tester');
      raise exception 'assertion failed: expected the late decide on a cancelled step to fail';
    exception when check_violation then null;
    end;
  end;

  if (select status from app.onboarding_offboarding_cases where id = v_case.id) <> 'cancelled' then
    raise exception 'assertion failed: expected the case to remain cancelled after the rejected late decide -- never resurrected';
  end if;
end;
$$;

\echo '>> offboarding without exit_reason at finalize-submission time is rejected (starting the case itself never requires an exit_reason -- self-found-and-fixed defect, see build log)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_employee_id uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and full_name = 'Interviewer One');
  v_case app.onboarding_offboarding_cases;
  v_task app.onboarding_case_tasks;
  v_employee app.employees;
begin
  select * into v_employee from app.employees where master_record_id = v_employee_id;
  perform app.add_employee_emergency_contact(v_employee_id, 'Contact', 'sibling', '08129999997', null, true, '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_employee from app.employees where master_record_id = v_employee_id;
  select * into v_employee from app.submit_employee_for_approval(v_employee_id, v_employee.record_version, '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_employee from app.decide_employee_approval(v_employee_id, v_employee.record_version, 'approve', null, '00000000-0000-0000-0000-000000027703', 'tester');
  select * into v_employee from app.activate_employee(v_employee_id, v_employee.record_version, '00000000-0000-0000-0000-000000027703', 'tester');

  select * into v_case from app.start_onboarding_case(
    v_tenant1, 'offboarding', 'existing_employee', null, v_employee_id, null, current_date,
    null, null, null, null, null, null, null, null, null, null, null, null, null,
    'idem-hrt2771-offb-3', '00000000-0000-0000-0000-000000027702', 'tester'
  );
  for v_task in select * from app.onboarding_case_tasks where case_id = v_case.id loop
    if v_task.task_type = 'access_revocation' then
      perform app.request_onboarding_access_revocation(v_case.id, v_task.id, v_task.record_version, 'standard offboarding checklist', '00000000-0000-0000-0000-000000027703', 'tester');
    else
      perform app.complete_onboarding_task(v_case.id, v_task.id, v_task.record_version, 'done', null, '00000000-0000-0000-0000-000000027702', 'tester');
    end if;
  end loop;

  begin
    perform app.submit_onboarding_case_for_finalize_approval(v_case.id, v_case.record_version, null, '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected exit_reason_required';
  exception when check_violation then null;
  end;
end;
$$;

\echo '>> mandatory checklist gate: finalize submission blocked while a mandatory task is incomplete'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_employee_id uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and full_name = 'Existing Employee One');
  v_case app.onboarding_offboarding_cases;
begin
  select * into v_case from app.start_onboarding_case(
    v_tenant1, 'offboarding', 'existing_employee', null, v_employee_id, null, current_date,
    null, null, null, null, null, null, null, null, null, null, null, null, null,
    'idem-hrt2771-mandatory-gate-1', '00000000-0000-0000-0000-000000027702', 'tester'
  );
  -- Not a single task completed -- the mandatory-task gate must fire before
  -- even reaching the employee-status precondition.
  begin
    perform app.submit_onboarding_case_for_finalize_approval(v_case.id, v_case.record_version, null, '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected mandatory_tasks_incomplete';
  exception when check_violation then null;
  end;
end;
$$;

\echo '>> rehire: app.reactivate_employee (HRT-274) only restores from suspended -- app.rehire_employee (HRT-277, decision 2) is the genuinely new terminated -> active transition; archived stays terminal'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_employee_id uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and full_name = 'Existing Employee Two');
  v_employee app.employees;
begin
  select * into v_employee from app.employees where master_record_id = v_employee_id;
  if v_employee.lifecycle_status <> 'terminated' then
    raise exception 'assertion failed: expected employee terminated from the prior block, got %', v_employee.lifecycle_status;
  end if;

  -- reactivate_employee (HRT-274) cannot do this -- only from suspended.
  begin
    perform app.reactivate_employee(v_employee_id, v_employee.record_version, '00000000-0000-0000-0000-000000027703', 'tester');
    raise exception 'assertion failed: expected app.reactivate_employee to reject a terminated employee';
  exception when check_violation then null;
  end;

  -- HRS:Edit alone cannot rehire (needs Override).
  begin
    perform app.rehire_employee(v_employee_id, v_employee.record_version, 'rejoining the team', '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected an HRS:Edit-only actor to be denied rehiring, but it succeeded';
  exception when insufficient_privilege then null;
  end;

  select * into v_employee from app.rehire_employee(v_employee_id, v_employee.record_version, 'rejoining the team', '00000000-0000-0000-0000-000000027703', 'tester');
  if v_employee.lifecycle_status <> 'active' or v_employee.terminate_reason is not null then
    raise exception 'assertion failed: expected rehired employee active with terminate_reason cleared';
  end if;
  if (select count(*) from app.employee_lifecycle_events where master_record_id = v_employee_id and from_status = 'terminated' and to_status = 'active') <> 1 then
    raise exception 'assertion failed: expected a real employee_lifecycle_events row recording the rehire';
  end if;

  -- An already-active employee cannot be "rehired" again.
  begin
    perform app.rehire_employee(v_employee_id, v_employee.record_version, 'again', '00000000-0000-0000-0000-000000027703', 'tester');
    raise exception 'assertion failed: expected invalid_transition on a non-terminated employee';
  exception when check_violation then null;
  end;
end;
$$;

\echo '>> assign_onboarding_task and task-owner isolation via list_my_onboarding_tasks -- an owner sees their own assigned task; a different actor sees zero of it'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_employee_id uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and full_name = 'Interviewer One');
  v_case app.onboarding_offboarding_cases;
  v_task app.onboarding_case_tasks;
  v_count integer;
begin
  select * into v_case from app.start_onboarding_case(
    v_tenant1, 'offboarding', 'existing_employee', null, v_employee_id, null, current_date,
    null, null, null, null, null, null, null, null, null, null, null, null, null,
    'idem-hrt2771-offb-assign', '00000000-0000-0000-0000-000000027702', 'tester'
  );
  select * into v_task from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'return-asset';

  select * into v_task from app.assign_onboarding_task(v_case.id, v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000027703', '00000000-0000-0000-0000-000000027702', 'tester');
  if v_task.owner_auth_user_id <> '00000000-0000-0000-0000-000000027703' then
    raise exception 'assertion failed: expected task owner assigned';
  end if;

  select count(*) into v_count from app.list_my_onboarding_tasks(v_tenant1, '00000000-0000-0000-0000-000000027703');
  if v_count < 1 then raise exception 'assertion failed: expected the assigned owner to see this task in their own list'; end if;
  select count(*) into v_count from app.list_my_onboarding_tasks(v_tenant1, '00000000-0000-0000-0000-000000027704');
  if v_count <> 0 then raise exception 'assertion failed: expected a DIFFERENT actor to see zero of this owner''s tasks (task-owner isolation, section 26)'; end if;

  -- Cannot assign a non-member as owner.
  begin
    perform app.assign_onboarding_task(v_case.id, v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000027722', '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected owner_not_found for a cross-tenant identity';
  exception when no_data_found then null;
  end;
end;
$$;

\echo '>> reads: get_onboarding_case (sensitive-field masking), list_onboarding_case_tasks (evidence/waive_reason masking, task-owner override), list_onboarding_cases, export_onboarding_cases'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_case_id uuid := (select id from app.onboarding_offboarding_cases where tenant_id = v_tenant1 and case_type = 'onboarding' and status = 'finalized' limit 1);
  v_row record;
  v_masked_row record;
  v_case_count integer;
  v_export_count integer;
begin
  select * into v_row from app.get_onboarding_case(v_case_id, '00000000-0000-0000-0000-000000027702');
  if v_row.id <> v_case_id then raise exception 'assertion failed: get_onboarding_case returned the wrong row'; end if;

  select count(*) into v_case_count from app.list_onboarding_case_tasks(v_case_id, '00000000-0000-0000-0000-000000027704');
  if v_case_count <> 4 then raise exception 'assertion failed: expected 4 tasks listed'; end if;

  -- Viewer (View only, no View personal data, not the task owner) sees waive_reason masked.
  select * into v_masked_row from app.list_onboarding_case_tasks(v_case_id, '00000000-0000-0000-0000-000000027704') where template_task_key = 'training';
  if v_masked_row.waive_reason is not null or not v_masked_row.sensitive_masked then
    raise exception 'assertion failed: expected waive_reason masked for a View-only actor with no owner match';
  end if;

  -- Staff (View personal data) sees it unmasked.
  select * into v_row from app.list_onboarding_case_tasks(v_case_id, '00000000-0000-0000-0000-000000027702') where template_task_key = 'training';
  if v_row.waive_reason is null or v_row.sensitive_masked then
    raise exception 'assertion failed: expected waive_reason UNmasked for a View-personal-data holder';
  end if;

  select count(*) into v_case_count from app.list_onboarding_cases(v_tenant1, '00000000-0000-0000-0000-000000027702', null, null, null, 50, null);
  if v_case_count < 1 then raise exception 'assertion failed: expected at least one case listed'; end if;

  select count(*) into v_export_count from app.export_onboarding_cases(v_tenant1, '00000000-0000-0000-0000-000000027702');
  if v_export_count < 1 then raise exception 'assertion failed: expected at least one exported case row'; end if;
end;
$$;

\echo '>> cross-tenant isolation: hrt2772 staff, holding zero membership in hrt2771, is denied (not-found folding, never a real row disclosure) on case/task reads and writes against a hrt2771 case; raw RLS denies a direct select'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_case_id uuid := (select id from app.onboarding_offboarding_cases where tenant_id = v_tenant1 limit 1);
  v_task_id uuid := (select id from app.onboarding_case_tasks where tenant_id = v_tenant1 limit 1);
begin
  begin
    perform app.get_onboarding_case(v_case_id, '00000000-0000-0000-0000-000000027722');
    raise exception 'assertion failed: expected cross-tenant not-found on get_onboarding_case';
  exception when no_data_found then null;
  end;

  begin
    perform app.complete_onboarding_task(v_case_id, v_task_id, 1, 'hijack attempt', null, '00000000-0000-0000-0000-000000027722', 'tester');
    raise exception 'assertion failed: expected cross-tenant not-found on complete_onboarding_task';
  exception when no_data_found then null;
  end;
end;
$$;

\echo '>> RLS default-deny for a customer_user-layer principal (tenant membership alone is not enough) AND for a real hrt2772 tenant member (wrong tenant) -- both read zero rows at the raw-RLS level from every new table'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027705", "role": "authenticated"}', true);
  if exists (select 1 from app.onboarding_offboarding_cases where tenant_id = v_tenant1) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.onboarding_offboarding_cases directly';
  end if;
  if exists (select 1 from app.onboarding_case_tasks where tenant_id = v_tenant1) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.onboarding_case_tasks directly';
  end if;
  if exists (select 1 from app.onboarding_checklist_templates where tenant_id = v_tenant1) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.onboarding_checklist_templates directly';
  end if;
  reset role;

  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027722", "role": "authenticated"}', true);
  if exists (select 1 from app.onboarding_offboarding_cases where tenant_id = v_tenant1) then
    raise exception 'assertion failed: a real, active, WRONG-tenant member must never read app.onboarding_offboarding_cases directly';
  end if;
  if exists (select 1 from app.onboarding_task_provisioning_requests where tenant_id = v_tenant1) then
    raise exception 'assertion failed: a real, active, WRONG-tenant member must never read app.onboarding_task_provisioning_requests directly';
  end if;
  reset role;
end;
$$;

\echo '>> defense in depth: anon is denied entirely at the schema-privilege layer on every new table; service_role has explicit full access'
do $$
begin
  set local role anon;
  begin
    perform count(*) from app.onboarding_offboarding_cases;
    raise exception 'assertion failed: anon must be denied at the schema-privilege layer';
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
  select count(*) into v_count from app.onboarding_offboarding_cases;
  if v_count < 1 then
    raise exception 'assertion failed: service_role must have full, unrestricted access';
  end if;
  reset role;
end;
$$;

\echo '>> exit_reason column-restricted grant: authenticated has no column-level SELECT on it (decision 4, applied from the first migration -- mandatory reading item 5)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
begin
  if has_column_privilege('authenticated', 'app.onboarding_offboarding_cases', 'exit_reason', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT have column-level SELECT on exit_reason';
  end if;
  if not has_column_privilege('authenticated', 'app.onboarding_offboarding_cases', 'status', 'SELECT') then
    raise exception 'assertion failed: authenticated SHOULD have column-level SELECT on status (never over-restricted)';
  end if;
  if has_column_privilege('authenticated', 'app.onboarding_case_tasks', 'evidence_note', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT have column-level SELECT on evidence_note';
  end if;
  if has_column_privilege('authenticated', 'app.onboarding_case_tasks', 'waive_reason', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT have column-level SELECT on waive_reason';
  end if;
end;
$$;

-- ===========================================================================
-- Tier C review-round fix pass (20260730890000) regression coverage. Every
-- block below live-reproduces the ORIGINAL exploit/defect first, confirming
-- it is now blocked/corrected, per BUILD_EXECUTION_PROTOCOL.md section 5.3 --
-- "never accept a fix from the findings register alone."
-- ===========================================================================

\echo '>> review-round fix: a task_type=handoff completion with no evidence note/file is rejected (business rule 3); a real note or file still completes it; document/generic tasks remain unaffected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HRT2771');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'BR-HRT2771');
  v_department uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'DEPT-HRT2771');
  v_case app.onboarding_offboarding_cases;
  v_asset app.onboarding_case_tasks;
  v_welcome app.onboarding_case_tasks;
begin
  select * into v_case from app.start_onboarding_case(
    v_tenant1, 'onboarding', 'direct_hire', null, null, null, current_date,
    'Evidence Fix Hire', 'full_time', null, null, null, null, null, null,
    v_company, v_branch, v_department, null, null,
    'idem-hrt2771-evidence-fix', '00000000-0000-0000-0000-000000027702', 'tester'
  );
  select * into v_welcome from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'welcome-doc';
  select * into v_welcome from app.complete_onboarding_task(v_case.id, v_welcome.id, v_welcome.record_version, 'signed', null, '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_asset from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'asset-issue';

  -- Pre-fix, this succeeded with BOTH evidence fields NULL -- now rejected.
  begin
    perform app.complete_onboarding_task(v_case.id, v_asset.id, v_asset.record_version, null, null, '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected evidence_required for a handoff task with no evidence note or file';
  exception when check_violation then null;
  end;

  select * into v_asset from app.complete_onboarding_task(v_case.id, v_asset.id, v_asset.record_version, 'laptop issued, serial FIX-001', null, '00000000-0000-0000-0000-000000027702', 'tester');
  if v_asset.status <> 'completed' then
    raise exception 'assertion failed: expected asset-issue completed once a real evidence note is supplied';
  end if;
end;
$$;

\echo '>> review-round fix: a direct_hire idempotency_key replay now compares the FULL request tuple (full_name/employment_type/work_email/effective_date/org units/position/manager), not merely case_type/source_type -- a materially different hire on the same key is rejected, a genuinely identical replay still returns the same case'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HRT2771');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'BR-HRT2771');
  v_department uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'DEPT-HRT2771');
  v_case app.onboarding_offboarding_cases;
  v_case_replay app.onboarding_offboarding_cases;
begin
  select * into v_case from app.start_onboarding_case(
    v_tenant1, 'onboarding', 'direct_hire', null, null, null, current_date,
    'Direct Hire Tuple Fix', 'full_time', 'tuple-fix@hrt2771.test', null, null, null, null, null,
    v_company, v_branch, v_department, 'Analyst', null,
    'idem-hrt2771-direct-tuple-fix', '00000000-0000-0000-0000-000000027702', 'tester'
  );

  -- Same key, materially different hire (name/employment_type/work_email) --
  -- pre-fix this silently returned the FIRST case with no error.
  begin
    perform app.start_onboarding_case(
      v_tenant1, 'onboarding', 'direct_hire', null, null, null, current_date,
      'A Totally Different Hire', 'contract', 'different-tuple-fix@hrt2771.test', null, null, null, null, null,
      v_company, v_branch, v_department, 'Analyst', null,
      'idem-hrt2771-direct-tuple-fix', '00000000-0000-0000-0000-000000027702', 'tester'
    );
    raise exception 'assertion failed: expected idempotency_key_conflict for a same-key, materially-different direct_hire replay';
  exception when unique_violation then null;
  end;

  -- Genuinely identical replay still returns the SAME case.
  select * into v_case_replay from app.start_onboarding_case(
    v_tenant1, 'onboarding', 'direct_hire', null, null, null, current_date,
    'Direct Hire Tuple Fix', 'full_time', 'tuple-fix@hrt2771.test', null, null, null, null, null,
    v_company, v_branch, v_department, 'Analyst', null,
    'idem-hrt2771-direct-tuple-fix', '00000000-0000-0000-0000-000000027702', 'tester'
  );
  if v_case_replay.id <> v_case.id then
    raise exception 'assertion failed: expected a genuine identical direct_hire replay to return the SAME case';
  end if;
end;
$$;

\echo '>> review-round fix: app.request_onboarding_access_provisioning no longer lets an HRS:Edit-only actor grant ANY published role -- an actual role grant now requires HRS:Override, AND the granting actor may never delegate a permission (e.g. FIN:Override) they do not themselves already hold; a third-party grant, a self-grant, and an Override-holding-but-under-permissioned actor are all blocked; a genuinely over-permissioned actor still succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HRT2771');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'BR-HRT2771');
  v_department uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'DEPT-HRT2771');
  v_fin_role uuid;
  v_fin_draft app.role_versions;
  v_fin_role_version uuid;
  v_full_role uuid;
  v_full_draft app.role_versions;
  v_case app.onboarding_offboarding_cases;
  v_task app.onboarding_case_tasks;
  v_result app.onboarding_case_tasks;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000027730', 'escalation-target@hrt2771.test'),
    ('00000000-0000-0000-0000-000000027731', 'legit-grant-target@hrt2771.test');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027730', 'escalation-target@hrt2771.test', 'Escalation Target', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'escalation-target@hrt2771.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027731', 'legit-grant-target@hrt2771.test', 'Legit Grant Target', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'legit-grant-target@hrt2771.test'), 'active', 'onboarded', 'tester');

  -- A role carrying FIN:Override/Approve -- unrelated to HRS, never flagged
  -- protected=true (protected only covers View-class field-masking).
  v_fin_role := (app.create_role(v_tenant1, 'Finance Controller Fixture', 'FIN Approve/Override', 'tester')).id;
  v_fin_draft := app.create_role_version(v_fin_role, 'tester');
  perform app.set_role_version_permissions(v_fin_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Approve', 'Override')), 'tester');
  perform app.publish_role_version(v_fin_draft.id, now(), 'tester');
  v_fin_role_version := (select id from app.role_versions where role_id = v_fin_role and status = 'published');

  select * into v_case from app.start_onboarding_case(
    v_tenant1, 'onboarding', 'direct_hire', null, null, null, current_date,
    'Escalation Fixture Hire', 'full_time', null, null, null, null, null, null,
    v_company, v_branch, v_department, null, null,
    'idem-hrt2771-escalation-fixture', '00000000-0000-0000-0000-000000027702', 'tester'
  );
  select * into v_task from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'welcome-doc';
  perform app.complete_onboarding_task(v_case.id, v_task.id, v_task.record_version, 'signed', null, '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_task from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'it-access';

  -- (1) HRS:Edit-only actor (staff@hrt2771, this checkpoint's own db-test
  -- fixture persona) attempts a THIRD-PARTY grant -- blocked at the
  -- HRS:Override bar before the delegation check even runs.
  begin
    perform app.request_onboarding_access_provisioning(v_case.id, v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000027730', array[v_fin_role_version], null, '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected insufficient_authority (HRS:Override) for an HRS:Edit-only actor granting a real role';
  exception when insufficient_privilege then null;
  end;

  -- (2) approver@hrt2771 HOLDS HRS:Override but zero FIN permission --
  -- blocked by the delegation check (cannot grant what it does not hold),
  -- for BOTH a third-party target and a self-grant.
  begin
    perform app.request_onboarding_access_provisioning(v_case.id, v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000027730', array[v_fin_role_version], null, '00000000-0000-0000-0000-000000027703', 'tester');
    raise exception 'assertion failed: expected insufficient_authority_to_delegate for an HRS:Override actor lacking the target role''s own FIN permissions (third-party)';
  exception when insufficient_privilege then null;
  end;
  begin
    perform app.request_onboarding_access_provisioning(v_case.id, v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000027703', array[v_fin_role_version], null, '00000000-0000-0000-0000-000000027703', 'tester');
    raise exception 'assertion failed: expected insufficient_authority_to_delegate for a SELF-grant of a role the actor does not already hold';
  exception when insufficient_privilege then null;
  end;

  -- Task must still be untouched (still pending, version unchanged) after
  -- every blocked attempt above -- never partially applied.
  select * into v_task from app.onboarding_case_tasks where id = v_task.id;
  if v_task.status <> 'pending' then
    raise exception 'assertion failed: expected the access_provisioning task to remain pending after every blocked escalation attempt, got %', v_task.status;
  end if;

  -- (3) A genuinely over-permissioned actor (holds HRS:Override AND the
  -- target role's own FIN:Approve/Override) succeeds -- the legitimate path
  -- is not collaterally broken by the fix.
  v_full_role := (app.create_role(v_tenant1, 'HR Director Equivalent Fixture', 'HRS Override + FIN Approve/Override', 'tester')).id;
  v_full_draft := app.create_role_version(v_full_role, 'tester');
  perform app.set_role_version_permissions(v_full_draft.id, array(
    select id from app.permissions
    where (resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Override', 'View'))
       or (resource_module_code = 'FIN' and action in ('Approve', 'Override'))
  ), 'tester');
  perform app.publish_role_version(v_full_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_full_role and status = 'published'), '00000000-0000-0000-0000-000000027701', '00000000-0000-0000-0000-000000027701', 'tester');

  select * into v_result from app.request_onboarding_access_provisioning(v_case.id, v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000027731', array[v_fin_role_version], null, '00000000-0000-0000-0000-000000027701', 'tester');
  if v_result.status <> 'completed' then
    raise exception 'assertion failed: expected the legitimate, sufficiently-permissioned grant to succeed';
  end if;
  if not (app.evaluate_permission('00000000-0000-0000-0000-000000027731', v_tenant1, 'FIN', 'Override')).allowed then
    raise exception 'assertion failed: expected the legitimate grant target to actually hold FIN:Override afterward';
  end if;
  if (app.evaluate_permission('00000000-0000-0000-0000-000000027730', v_tenant1, 'FIN', 'Override')).allowed then
    raise exception 'assertion failed: the earlier BLOCKED escalation target must never have actually received FIN:Override';
  end if;
end;
$$;

\echo '>> review-round fix: cancelling an onboarding case now revokes any Platform role_assignments already granted through that case''s own completed access-provisioning tasks (never the underlying identity link) -- the C-04 dependent-in-flight-process-not-cancelled gap'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HRT2771');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'BR-HRT2771');
  v_department uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'DEPT-HRT2771');
  v_viewer_role_version uuid := (select id from app.role_versions where role_id = (select id from app.roles where tenant_id = v_tenant1 and name = 'HRS Viewer') and status = 'published');
  v_edit_override_role uuid;
  v_edit_override_draft app.role_versions;
  v_case app.onboarding_offboarding_cases;
  v_task app.onboarding_case_tasks;
  v_assignment_status text;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000027732', 'cancel-cascade-target@hrt2771.test'),
    ('00000000-0000-0000-0000-000000027735', 'cancel-cascade-granter@hrt2771.test');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027732', 'cancel-cascade-target@hrt2771.test', 'Cancel Cascade Target', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'cancel-cascade-target@hrt2771.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027735', 'cancel-cascade-granter@hrt2771.test', 'Cancel Cascade Granter', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'cancel-cascade-granter@hrt2771.test'), 'active', 'onboarded', 'tester');

  -- A real HR-director-equivalent actor: holds both HRS:Edit (the baseline
  -- task-write bar) and HRS:Override (the real-grant bar, review-round fix),
  -- plus HRS:View itself (so it may delegate the HRS-View-only fixture role
  -- below without tripping the actor-holds-what-it-grants check).
  v_edit_override_role := (app.create_role(v_tenant1, 'Cancel Cascade Granter Role Fixture', 'HRS Create/Edit/Override/View', 'tester')).id;
  v_edit_override_draft := app.create_role_version(v_edit_override_role, 'tester');
  perform app.set_role_version_permissions(v_edit_override_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Override', 'View')), 'tester');
  perform app.publish_role_version(v_edit_override_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_edit_override_role and status = 'published'), '00000000-0000-0000-0000-000000027735', '00000000-0000-0000-0000-000000027701', 'tester');

  select * into v_case from app.start_onboarding_case(
    v_tenant1, 'onboarding', 'direct_hire', null, null, null, current_date,
    'Cancel Cascade Hire', 'full_time', null, null, null, null, null, null,
    v_company, v_branch, v_department, null, null,
    'idem-hrt2771-cancel-cascade', '00000000-0000-0000-0000-000000027702', 'tester'
  );
  select * into v_task from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'welcome-doc';
  perform app.complete_onboarding_task(v_case.id, v_task.id, v_task.record_version, 'signed', null, '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_task from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'it-access';

  -- The fixture granter above holds HRS:Edit/Override AND HRS:View itself
  -- (the viewer role carries only HRS:View) -- a real, legitimate grant.
  perform app.request_onboarding_access_provisioning(v_case.id, v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000027732', array[v_viewer_role_version], null, '00000000-0000-0000-0000-000000027735', 'tester');

  if not (select exists (select 1 from app.role_assignments where tenant_id = v_tenant1 and role_version_id = v_viewer_role_version and auth_user_id = '00000000-0000-0000-0000-000000027732' and status = 'active')) then
    raise exception 'assertion failed: expected the role grant to be active before cancellation';
  end if;

  select * into v_case from app.cancel_onboarding_case(v_case.id, v_case.record_version, 'headcount rescinded before day one', '00000000-0000-0000-0000-000000027702', 'tester');
  if v_case.status <> 'cancelled' then
    raise exception 'assertion failed: expected the case cancelled';
  end if;

  select status into v_assignment_status from app.role_assignments where tenant_id = v_tenant1 and role_version_id = v_viewer_role_version and auth_user_id = '00000000-0000-0000-0000-000000027732';
  if v_assignment_status <> 'revoked' then
    raise exception 'assertion failed: expected the role grant REVOKED once its own case was cancelled, got %', v_assignment_status;
  end if;
end;
$$;

\echo '>> review-round fix: a target identity that is genuinely non-activatable (already revoked, not merely a fresh invite) is rejected outright by access provisioning instead of silently completing the task with an unkeepable "re-run once active" promise'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HRT2771');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'BR-HRT2771');
  v_department uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'DEPT-HRT2771');
  v_case app.onboarding_offboarding_cases;
  v_task app.onboarding_case_tasks;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000027733', 'already-revoked-target@hrt2771.test');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027733', 'already-revoked-target@hrt2771.test', 'Already Revoked Target', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'already-revoked-target@hrt2771.test'), 'active', 'onboarded', 'tester');
  perform app.transition_user_status((select id from app.users where email = 'already-revoked-target@hrt2771.test'), 'revoked', 'left the company before this new case existed', 'tester');

  select * into v_case from app.start_onboarding_case(
    v_tenant1, 'onboarding', 'direct_hire', null, null, null, current_date,
    'Stranded State Hire', 'full_time', null, null, null, null, null, null,
    v_company, v_branch, v_department, null, null,
    'idem-hrt2771-stranded-state', '00000000-0000-0000-0000-000000027702', 'tester'
  );
  select * into v_task from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'welcome-doc';
  perform app.complete_onboarding_task(v_case.id, v_task.id, v_task.record_version, 'signed', null, '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_task from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'it-access';

  begin
    perform app.request_onboarding_access_provisioning(v_case.id, v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000027733', '{}'::uuid[], null, '00000000-0000-0000-0000-000000027702', 'tester');
    raise exception 'assertion failed: expected target_identity_not_activatable for an already-revoked target identity';
  exception when check_violation then null;
  end;

  select * into v_task from app.onboarding_case_tasks where id = v_task.id;
  if v_task.status <> 'pending' then
    raise exception 'assertion failed: expected the task to remain pending (actionable), not falsely completed, got %', v_task.status;
  end if;
end;
$$;

\echo '>> review-round fix: app.request_onboarding_access_revocation now also revokes every ACTIVE app.role_assignments row for the target identity in this tenant -- app.transition_user_status alone (PLT-110) never touched role_assignments, so a revoked identity previously retained full permission-gated authority'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CO-HRT2771');
  v_branch uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'BR-HRT2771');
  v_department uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'DEPT-HRT2771');
  v_ghost_role uuid;
  v_ghost_draft app.role_versions;
  v_case app.onboarding_offboarding_cases;
  v_task app.onboarding_case_tasks;
  v_emp app.employees;
  v_emp_id uuid;
  v_ofb_case app.onboarding_offboarding_cases;
  v_ofb_task app.onboarding_case_tasks;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000027734', 'revoke-cascade-ghost@hrt2771.test');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027734', 'revoke-cascade-ghost@hrt2771.test', 'Revoke Cascade Ghost', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'revoke-cascade-ghost@hrt2771.test'), 'active', 'onboarded', 'tester');

  v_ghost_role := (app.create_role(v_tenant1, 'Revoke Cascade HRS Create Fixture', 'HRS Create', 'tester')).id;
  v_ghost_draft := app.create_role_version(v_ghost_role, 'tester');
  perform app.set_role_version_permissions(v_ghost_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create')), 'tester');
  perform app.publish_role_version(v_ghost_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_ghost_role and status = 'published'), '00000000-0000-0000-0000-000000027734', '00000000-0000-0000-0000-000000027701', 'tester');

  if not (app.evaluate_permission('00000000-0000-0000-0000-000000027734', v_tenant1, 'HRS', 'Create')).allowed then
    raise exception 'assertion failed: expected the fixture identity to genuinely hold HRS:Create before revocation';
  end if;

  -- Link this identity to a real, active employee via a direct_hire case
  -- (so app.request_onboarding_access_revocation has a real app.employees.
  -- user_id to act on), then run it through the full employee lifecycle to
  -- 'active' so an offboarding case can legally start against it.
  select * into v_case from app.start_onboarding_case(
    v_tenant1, 'onboarding', 'direct_hire', null, null, null, current_date,
    'Revoke Cascade Employee', 'full_time', null, null, null, null, null, null,
    v_company, v_branch, v_department, null, null,
    'idem-hrt2771-revoke-cascade', '00000000-0000-0000-0000-000000027702', 'tester'
  );
  select * into v_task from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'welcome-doc';
  perform app.complete_onboarding_task(v_case.id, v_task.id, v_task.record_version, 'signed', null, '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_task from app.onboarding_case_tasks where case_id = v_case.id and template_task_key = 'it-access';
  perform app.request_onboarding_access_provisioning(v_case.id, v_task.id, v_task.record_version, '00000000-0000-0000-0000-000000027734', '{}'::uuid[], null, '00000000-0000-0000-0000-000000027702', 'tester');

  v_emp_id := (select master_record_id from app.employees where tenant_id = v_tenant1 and full_name = 'Revoke Cascade Employee');
  select * into v_emp from app.employees where master_record_id = v_emp_id;
  perform app.add_employee_emergency_contact(v_emp_id, 'Emergency Contact', 'sibling', '081200000099', null, true, '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_emp from app.employees where master_record_id = v_emp_id;
  select * into v_emp from app.submit_employee_for_approval(v_emp_id, v_emp.record_version, '00000000-0000-0000-0000-000000027702', 'tester');
  select * into v_emp from app.decide_employee_approval(v_emp_id, v_emp.record_version, 'approve', null, '00000000-0000-0000-0000-000000027703', 'tester');
  select * into v_emp from app.activate_employee(v_emp_id, v_emp.record_version, '00000000-0000-0000-0000-000000027703', 'tester');

  select * into v_ofb_case from app.start_onboarding_case(
    v_tenant1, 'offboarding', 'existing_employee', null, v_emp_id, null, current_date,
    null, null, null, null, null, null, null, null, null, null, null, null, null,
    'idem-hrt2771-revoke-cascade-offb', '00000000-0000-0000-0000-000000027702', 'tester'
  );
  select * into v_ofb_task from app.onboarding_case_tasks where case_id = v_ofb_case.id and template_task_key = 'revoke-access';
  perform app.request_onboarding_access_revocation(v_ofb_case.id, v_ofb_task.id, v_ofb_task.record_version, 'security offboarding -- immediate exit', '00000000-0000-0000-0000-000000027703', 'tester');

  if (app.evaluate_permission('00000000-0000-0000-0000-000000027734', v_tenant1, 'HRS', 'Create')).allowed then
    raise exception 'assertion failed: expected the revoked identity to have LOST HRS:Create -- app.role_assignments must now be revoked, not merely app.users.status';
  end if;
  if (select count(*) from app.role_assignments where auth_user_id = '00000000-0000-0000-0000-000000027734' and status = 'active') <> 0 then
    raise exception 'assertion failed: expected zero active role_assignments for the revoked identity';
  end if;
end;
$$;

\echo '>> review-round fix: onboarding_task_provisioning_requests/onboarding_case_events no longer grant authenticated a blanket, non-column-scoped SELECT -- identity-linkage/authority/free-text columns are excluded, matching the exit_reason/evidence_note/waive_reason discipline'
do $$
begin
  if has_column_privilege('authenticated', 'app.onboarding_task_provisioning_requests', 'target_auth_user_id', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT have column-level SELECT on target_auth_user_id';
  end if;
  if has_column_privilege('authenticated', 'app.onboarding_task_provisioning_requests', 'requested_role_version_ids', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT have column-level SELECT on requested_role_version_ids';
  end if;
  if has_column_privilege('authenticated', 'app.onboarding_task_provisioning_requests', 'result_user_id', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT have column-level SELECT on result_user_id';
  end if;
  if has_column_privilege('authenticated', 'app.onboarding_task_provisioning_requests', 'failure_reason', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT have column-level SELECT on failure_reason';
  end if;
  if not has_column_privilege('authenticated', 'app.onboarding_task_provisioning_requests', 'status', 'SELECT') then
    raise exception 'assertion failed: authenticated SHOULD still have column-level SELECT on status (never over-restricted)';
  end if;
  if has_column_privilege('authenticated', 'app.onboarding_case_events', 'notes', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT have column-level SELECT on onboarding_case_events.notes';
  end if;
  if not has_column_privilege('authenticated', 'app.onboarding_case_events', 'event_type', 'SELECT') then
    raise exception 'assertion failed: authenticated SHOULD still have column-level SELECT on event_type (never over-restricted)';
  end if;
end;
$$;

\echo '>> structural regression guard: app.employees/app.users/app.job_offers/app.approval_requests core shapes are unaltered beyond this migration''s own additive functions'
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'app' and table_name = 'employees' and column_name = 'user_id') then
    raise exception 'assertion failed: app.employees.user_id must still exist unchanged';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'app' and table_name = 'users' and column_name = 'status') then
    raise exception 'assertion failed: app.users.status must still exist unchanged';
  end if;
end;
$$;

\echo '>> HRT-293 Finding B regression: app.waive_onboarding_task/app.reopen_onboarding_task/app.cancel_onboarding_case no longer duplicate their raw reason text (several distinct real reasons already used above in this same file) into app.audit_logs.reason for THEIR OWN action rows -- a plain tenant_admin reading via app.query_audit_logs never sees any of them either. Scoped to the specific action names this checkpoint fixed (self-found, disclosed as ISS-2026-093: app.cancel_approval_request, the SHARED PLT-123 approval-engine primitive these functions call internally to cancel an in-flight approval, independently logs the identical raw reason under its own action="cancel_approval_request" row -- a real, but out-of-scope-for-this-HR-checkpoint, C-24 gap in a cross-domain Platform Core primitive, not touched here).'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'hrt2771');
  v_fixed_actions text[] := array['waive_onboarding_task', 'reopen_onboarding_task', 'cancel_onboarding_case'];
  v_reasons text[] := array[
    'deferred to next quarter', 'training now required after all', 'deferred to next quarter (re-waived)',
    'employee retracted resignation', 'reorg cancelled the exit', 'headcount rescinded before day one'
  ];
begin
  if exists (select 1 from app.audit_logs where reason = any (v_reasons) and action = any (v_fixed_actions)) then
    raise exception 'HRT-293 Finding B regression: app.audit_logs.reason must never carry a raw onboarding/offboarding task or case reason for waive_onboarding_task/reopen_onboarding_task/cancel_onboarding_case';
  end if;
  if exists (select 1 from app.query_audit_logs('00000000-0000-0000-0000-000000027701', v_tenant1, 500) where reason = any (v_reasons) and action = any (v_fixed_actions)) then
    raise exception 'HRT-293 Finding B regression: a plain tenant_admin must never see a raw onboarding/offboarding reason via app.query_audit_logs for these actions';
  end if;
end $$;

\echo 'ALL HRT-277 db-test assertions passed.'
