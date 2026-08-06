-- Real, executable test evidence for PRC-252 (Vendor Assessment, CG-S11-PRC-003) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (vasm1, vasm2). vasm1 gets a tenant_admin, a PRC staff/assessor (Create/Edit/View), a dual assessor-approver (Create/Edit/Approve/Reject/View, used only for the begin_review self-approval test), a reviewer (Approve/Reject/View), an override manager (Override/Create/Edit/View), a view-only actor, a cost-viewer (View/View cost), and a customer_user-layer actor. vasm2 gets a tenant_admin and a staff actor for cross-tenant checks. A global Supreme Admin is also seeded.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_staff_role uuid;
  v_staff_draft app.role_versions;
  v_dual_role uuid;
  v_dual_draft app.role_versions;
  v_reviewer_role uuid;
  v_reviewer_draft app.role_versions;
  v_manager_role uuid;
  v_manager_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_costviewer_role uuid;
  v_costviewer_draft app.role_versions;
  v_t2_staff_role uuid;
  v_t2_staff_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000026101', 'admin@vasm1.test'),
    ('00000000-0000-0000-0000-000000026102', 'staff@vasm1.test'),
    ('00000000-0000-0000-0000-000000026103', 'dual@vasm1.test'),
    ('00000000-0000-0000-0000-000000026104', 'reviewer@vasm1.test'),
    ('00000000-0000-0000-0000-000000026105', 'manager@vasm1.test'),
    ('00000000-0000-0000-0000-000000026106', 'viewer@vasm1.test'),
    ('00000000-0000-0000-0000-000000026107', 'costviewer@vasm1.test'),
    ('00000000-0000-0000-0000-000000026108', 'customer@vasm1.test'),
    ('00000000-0000-0000-0000-000000026201', 'admin@vasm2.test'),
    ('00000000-0000-0000-0000-000000026202', 'staff@vasm2.test'),
    ('00000000-0000-0000-0000-000000026999', 'supreme@vasm.test');

  perform app.provision_tenant('vasm1', 'Vendor Assessment Co 1', 'idem-vasm1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'vasm1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('vasm2', 'Vendor Assessment Co 2', 'idem-vasm2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'vasm2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000026101', 'admin@vasm1.test', 'Vasm1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vasm1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000026101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000026102', 'staff@vasm1.test', 'Vasm1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@vasm1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000026103', 'dual@vasm1.test', 'Vasm1 Dual', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'dual@vasm1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000026104', 'reviewer@vasm1.test', 'Vasm1 Reviewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'reviewer@vasm1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000026105', 'manager@vasm1.test', 'Vasm1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@vasm1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000026106', 'viewer@vasm1.test', 'Vasm1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@vasm1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000026107', 'costviewer@vasm1.test', 'Vasm1 Cost Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'costviewer@vasm1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000026108', 'customer@vasm1.test', 'Vasm1 Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer@vasm1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000026108', 'customer_user', v_tenant1, 'external-customer-account', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000026201', 'admin@vasm2.test', 'Vasm2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vasm2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000026201', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000026202', 'staff@vasm2.test', 'Vasm2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@vasm2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000026999', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'PRC Assessment Staff', 'Create/Edit/View', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000026102', '00000000-0000-0000-0000-000000026101', 'tester');

  v_dual_role := (app.create_role(v_tenant1, 'PRC Dual Assessor Approver', 'Create/Edit/Approve/Reject/View (self-approval test only)', 'tester')).id;
  v_dual_draft := app.create_role_version(v_dual_role, 'tester');
  perform app.set_role_version_permissions(v_dual_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'Approve', 'Reject', 'View')), 'tester');
  perform app.publish_role_version(v_dual_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_dual_role and status = 'published'), '00000000-0000-0000-0000-000000026103', '00000000-0000-0000-0000-000000026101', 'tester');

  v_reviewer_role := (app.create_role(v_tenant1, 'PRC Assessment Reviewer', 'Approve/Reject/View', 'tester')).id;
  v_reviewer_draft := app.create_role_version(v_reviewer_role, 'tester');
  perform app.set_role_version_permissions(v_reviewer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Approve', 'Reject', 'View')), 'tester');
  perform app.publish_role_version(v_reviewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_reviewer_role and status = 'published'), '00000000-0000-0000-0000-000000026104', '00000000-0000-0000-0000-000000026101', 'tester');

  v_manager_role := (app.create_role(v_tenant1, 'PRC Assessment Manager', 'Override/Create/Edit/View', 'tester')).id;
  v_manager_draft := app.create_role_version(v_manager_role, 'tester');
  perform app.set_role_version_permissions(v_manager_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Override', 'Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000026105', '00000000-0000-0000-0000-000000026101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'PRC Assessment Viewer', 'View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000026106', '00000000-0000-0000-0000-000000026101', 'tester');

  v_costviewer_role := (app.create_role(v_tenant1, 'PRC Assessment Cost Viewer', 'View/View cost', 'tester')).id;
  v_costviewer_draft := app.create_role_version(v_costviewer_role, 'tester');
  perform app.set_role_version_permissions(v_costviewer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('View', 'View cost')), 'tester');
  perform app.publish_role_version(v_costviewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_costviewer_role and status = 'published'), '00000000-0000-0000-0000-000000026107', '00000000-0000-0000-0000-000000026101', 'tester');

  v_t2_staff_role := (app.create_role(v_tenant2, 'PRC Assessment Staff T2', 'Create/Edit/View', 'tester')).id;
  v_t2_staff_draft := app.create_role_version(v_t2_staff_role, 'tester');
  perform app.set_role_version_permissions(v_t2_staff_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_t2_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000026202', '00000000-0000-0000-0000-000000026201', 'tester');
end $$;

\echo '>> setup: a vendor profile in each tenant, plus one vasm1 vendor eventually blacklisted'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'vasm2');
  v_admin1 uuid := '00000000-0000-0000-0000-000000026101';
  v_admin2 uuid := '00000000-0000-0000-0000-000000026201';
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000026104';
  v_manager uuid := '00000000-0000-0000-0000-000000026105';
  v_t2_staff uuid := '00000000-0000-0000-0000-000000026202';
  v_profile app.vendor_profiles;
  v_blacklist_profile app.vendor_profiles;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Contoso Logistik', 'Contoso', 'PT', 'REG-9001', 'trucking', 30, 'staff_created', 'idem-vasm-vendor-1', v_staff, 'staff');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Jane Vendor', 'Ops Manager', 'jane@contoso-vasm.test', '0811-900-001', true, v_staff, 'staff');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_staff, 'staff');
  perform app.add_vendor_service(v_profile.master_record_id, 'trucking', v_staff, 'staff');

  v_blacklist_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Bad Actor Logistics', null, 'PT', 'REG-9002', 'trucking', 30, 'staff_created', 'idem-vasm-vendor-blacklist', v_staff, 'staff');
  perform app.add_vendor_contact(v_blacklist_profile.master_record_id, 'Bob Bad', 'Ops', 'bob@badactor-vasm.test', '0811-900-002', true, v_staff, 'staff');
  perform app.add_vendor_address(v_blacklist_profile.master_record_id, 'legal', 'Jl. Thamrin 2', 'Jakarta', 'DKI Jakarta', '10230', 'Indonesia', v_staff, 'staff');
  perform app.add_vendor_service(v_blacklist_profile.master_record_id, 'trucking', v_staff, 'staff');
  v_blacklist_profile := app.submit_vendor_profile_for_review(v_blacklist_profile.master_record_id, v_blacklist_profile.record_version, v_staff, 'staff');
  v_blacklist_profile := app.decide_vendor_profile_review(v_blacklist_profile.master_record_id, v_blacklist_profile.record_version, 'approve', null, v_reviewer, 'reviewer');
  v_blacklist_profile := app.activate_vendor_profile(v_blacklist_profile.master_record_id, v_blacklist_profile.record_version, v_reviewer, 'reviewer');
  perform app.blacklist_vendor_profile(v_blacklist_profile.master_record_id, v_blacklist_profile.record_version, 'confirmed fraud', 'evidence-ref-9002', v_manager, 'manager');

  perform app.create_vendor_profile_draft(v_tenant2, 'PT Vasm2 Vendor', null, 'PT', 'REG-9101', 'trucking', 30, 'staff_created', 'idem-vasm2-vendor-1', v_t2_staff, 'staff');

  perform app.create_vendor_profile_draft(v_tenant1, 'PT Second Vendor', null, 'PT', 'REG-9003', 'trucking', 30, 'staff_created', 'idem-vasm-vendor-2', v_staff, 'staff');
end $$;

\echo '>> template lifecycle: draft -> add criteria -> weight-sum validation blocks publish until it sums correctly -> publish; a non-Approve actor cannot publish; an empty template cannot publish'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000026104';
  v_viewer uuid := '00000000-0000-0000-0000-000000026106';
  v_template app.vendor_assessment_templates;
  v_empty_template app.vendor_assessment_templates;
  v_crit_a app.vendor_assessment_template_criteria;
  v_crit_b app.vendor_assessment_template_criteria;
  v_crit_c app.vendor_assessment_template_criteria;
begin
  v_template := app.create_vendor_assessment_template_draft(v_tenant1, 'trucking', 'initial', 'Initial Trucking Assessment v1', 'baseline qualification', 180, 80, 60, 100, 'idem-vasm-template-1', v_staff, 'staff');
  if v_template.status <> 'draft' then
    raise exception 'assertion failed: expected draft, got %', v_template.status;
  end if;

  -- adversarial-review fix: weight_total_required is pinned to exactly 100 -- the
  -- scoring formula (app._compute_vendor_assessment_score) hardcodes a 100-point
  -- denominator, so any other total either crashes the calculated_score range CHECK
  -- or makes pass_threshold mathematically unreachable. Both create and update reject
  -- it up front.
  begin
    perform app.create_vendor_assessment_template_draft(v_tenant1, 'trucking', 'periodic', 'Bad Weight Total Template', null, 90, 70, 50, 150, 'idem-vasm-badweight-template', v_staff, 'staff');
    raise exception 'assertion failed: expected invalid_weight_total for weight_total_required=150 on create';
  exception
    when others then
      if sqlerrm not like 'invalid_weight_total%' then raise; end if;
  end;
  begin
    perform app.update_vendor_assessment_template_draft(v_template.id, v_template.record_version, 'trucking', v_template.name, v_template.description, v_template.validity_period_days, v_template.pass_threshold, v_template.conditional_threshold, 60, v_staff, 'staff');
    raise exception 'assertion failed: expected invalid_weight_total for weight_total_required=60 on update';
  exception
    when others then
      if sqlerrm not like 'invalid_weight_total%' then raise; end if;
  end;

  -- viewer (View only) cannot add a criterion (requires PRC:Edit).
  begin
    perform app.add_vendor_assessment_template_criterion(v_template.id, 'On-time delivery rate', 'operational', 50, 'percentage of on-time deliveries last 12 months', 1, v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for viewer adding a criterion';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_crit_a := app.add_vendor_assessment_template_criterion(v_template.id, 'On-time delivery rate', 'operational', 50, 'percentage of on-time deliveries last 12 months', 1, v_staff, 'staff');

  -- empty template cannot publish.
  v_empty_template := app.create_vendor_assessment_template_draft(v_tenant1, 'trucking', 'periodic', 'Empty Template', null, 90, 70, 50, 100, 'idem-vasm-template-empty', v_staff, 'staff');
  begin
    perform app.publish_vendor_assessment_template(v_empty_template.id, v_empty_template.record_version, null, v_reviewer, 'reviewer');
    raise exception 'assertion failed: expected template_has_no_criteria';
  exception
    when others then
      if sqlerrm not like 'template_has_no_criteria%' then raise; end if;
  end;

  -- weight sum 50 <> 100 required -- publish blocked.
  begin
    perform app.publish_vendor_assessment_template(v_template.id, v_template.record_version, null, v_reviewer, 'reviewer');
    raise exception 'assertion failed: expected weight_sum_mismatch';
  exception
    when others then
      if sqlerrm not like 'weight_sum_mismatch%' then raise; end if;
  end;

  -- staff (PRC:Edit only, no Approve) cannot publish even once weights are complete.
  v_crit_b := app.add_vendor_assessment_template_criterion(v_template.id, 'Safety compliance', 'safety', 30, 'safety audit score', 2, v_staff, 'staff');
  v_crit_c := app.add_vendor_assessment_template_criterion(v_template.id, 'Financial stability disclosure', 'financial', 20, 'credit health summary', 3, v_staff, 'staff');
  begin
    perform app.publish_vendor_assessment_template(v_template.id, v_template.record_version, null, v_staff, 'staff');
    raise exception 'assertion failed: expected insufficient_authority for staff publishing';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_template := app.publish_vendor_assessment_template(v_template.id, v_template.record_version, null, v_reviewer, 'reviewer');
  if v_template.status <> 'published' then
    raise exception 'assertion failed: expected published, got %', v_template.status;
  end if;

  -- criteria are now immutable (draft-only mutation) -- adding a criterion to a published template fails.
  begin
    perform app.add_vendor_assessment_template_criterion(v_template.id, 'Late addition', 'operational', 5, null, 4, v_staff, 'staff');
    raise exception 'assertion failed: expected vendor_assessment_template_not_draft';
  exception
    when others then
      if sqlerrm not like 'vendor_assessment_template_not_draft%' then raise; end if;
  end;

  -- a second draft for the SAME (tenant, vendor_category, assessment_type) cannot publish without supersedes_version_id.
  declare
    v_dupe app.vendor_assessment_templates;
  begin
    v_dupe := app.create_vendor_assessment_template_draft(v_tenant1, 'trucking', 'initial', 'Duplicate Attempt', null, 90, 70, 50, 100, 'idem-vasm-template-dupe', v_staff, 'staff');
    perform app.add_vendor_assessment_template_criterion(v_dupe.id, 'Only criterion', 'operational', 100, null, 1, v_staff, 'staff');
    begin
      perform app.publish_vendor_assessment_template(v_dupe.id, v_dupe.record_version, null, v_reviewer, 'reviewer');
      raise exception 'assertion failed: expected active_template_exists';
    exception
      when others then
        if sqlerrm not like 'active_template_exists%' then raise; end if;
    end;
  end;
end $$;

\echo '>> full assessment happy path: start -> record answers -> explainable score calculation -> submit -> self-approval blocked -> begin_review -> decide approve -> expiry_date computed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000026104';
  v_manager uuid := '00000000-0000-0000-0000-000000026105';
  v_costviewer uuid := '00000000-0000-0000-0000-000000026107';
  v_viewer uuid := '00000000-0000-0000-0000-000000026106';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-1');
  v_template_id uuid := (select id from app.vendor_assessment_templates where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-template-1');
  v_crit_a uuid;
  v_crit_b uuid;
  v_crit_c uuid;
  v_assessment app.vendor_assessments;
  v_answer app.vendor_assessment_answers;
  v_breakdown record;
  v_masked_row record;
  v_unmasked_row record;
begin
  select id into v_crit_a from app.vendor_assessment_template_criteria where template_version_id = v_template_id and label = 'On-time delivery rate';
  select id into v_crit_b from app.vendor_assessment_template_criteria where template_version_id = v_template_id and label = 'Safety compliance';
  select id into v_crit_c from app.vendor_assessment_template_criteria where template_version_id = v_template_id and label = 'Financial stability disclosure';

  v_assessment := app.start_vendor_assessment(v_vendor_id, v_template_id, null, 'idem-vasm-assessment-1', v_staff, 'staff');
  if v_assessment.status <> 'draft' then
    raise exception 'assertion failed: expected draft, got %', v_assessment.status;
  end if;
  if v_assessment.assessment_type <> 'initial' then
    raise exception 'assertion failed: expected assessment_type initial (snapshotted from template), got %', v_assessment.assessment_type;
  end if;

  -- a reviewer (lacks PRC:Edit entirely) is rejected on authority grounds first.
  begin
    perform app.record_vendor_assessment_answer(v_assessment.id, v_crit_a, '95%', 90, null, null, v_reviewer, 'reviewer');
    raise exception 'assertion failed: expected insufficient_authority for a reviewer (no PRC:Edit) answering';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- a DIFFERENT actor who DOES hold PRC:Edit but is not the assigned assessor is
  -- rejected on identity grounds (not_assigned_assessor), distinct from the
  -- authority check above.
  begin
    perform app.record_vendor_assessment_answer(v_assessment.id, v_crit_a, '95%', 90, null, null, v_manager, 'manager');
    raise exception 'assertion failed: expected not_assigned_assessor for a PRC:Edit-holding non-assessor answering';
  exception
    when others then
      if sqlerrm not like 'not_assigned_assessor%' then raise; end if;
  end;

  v_answer := app.record_vendor_assessment_answer(v_assessment.id, v_crit_a, '95% on-time', 90, null, 'strong performance', v_staff, 'staff');

  -- first answer auto-transitions draft -> in_progress.
  select * into v_assessment from app.vendor_assessments where id = v_assessment.id;
  if v_assessment.status <> 'in_progress' then
    raise exception 'assertion failed: expected in_progress after first answer, got %', v_assessment.status;
  end if;

  perform app.record_vendor_assessment_answer(v_assessment.id, v_crit_b, 'clean safety audit', 100, null, null, v_staff, 'staff');
  perform app.record_vendor_assessment_answer(v_assessment.id, v_crit_c, 'stable, minor DSO concern', 50, null, 'confidential credit note', v_staff, 'staff');

  -- explainable score: 50*90/100 + 30*100/100 + 20*50/100 = 45 + 30 + 10 = 85 (pass, >= 80).
  v_assessment := app.calculate_vendor_assessment_score(v_assessment.id, v_assessment.record_version, v_staff, 'staff');
  if v_assessment.calculated_score <> 85.00 then
    raise exception 'assertion failed: expected calculated_score 85.00, got %', v_assessment.calculated_score;
  end if;
  if v_assessment.score_band <> 'pass' then
    raise exception 'assertion failed: expected score_band pass, got %', v_assessment.score_band;
  end if;

  -- score breakdown is explainable: each row shows weight * answer_score / 100 = contribution.
  for v_breakdown in select * from app.get_vendor_assessment_score_breakdown(v_assessment.id, v_staff) order by label loop
    if v_breakdown.label = 'On-time delivery rate' and v_breakdown.contribution <> 45.00 then
      raise exception 'assertion failed: expected On-time delivery rate contribution 45.00, got %', v_breakdown.contribution;
    end if;
    if v_breakdown.label = 'Safety compliance' and v_breakdown.contribution <> 30.00 then
      raise exception 'assertion failed: expected Safety compliance contribution 30.00, got %', v_breakdown.contribution;
    end if;
    if v_breakdown.label = 'Financial stability disclosure' and v_breakdown.contribution <> 10.00 then
      raise exception 'assertion failed: expected Financial stability disclosure contribution 10.00, got %', v_breakdown.contribution;
    end if;
  end loop;

  -- purpose-bound section masking: a plain viewer (PRC:View, no View cost) sees the financial criterion's contribution/weight but NOT its value/notes; a cost-viewer sees everything.
  select * into v_masked_row from app.get_vendor_assessment_score_breakdown(v_assessment.id, v_viewer) where label = 'Financial stability disclosure';
  if v_masked_row.value is not null or v_masked_row.notes is not null then
    raise exception 'assertion failed: expected financial value/notes masked for a caller without PRC:View cost';
  end if;
  if v_masked_row.contribution <> 10.00 then
    raise exception 'assertion failed: expected financial contribution still visible (10.00) even when value/notes are masked, got %', v_masked_row.contribution;
  end if;
  select * into v_unmasked_row from app.get_vendor_assessment_score_breakdown(v_assessment.id, v_costviewer) where label = 'Financial stability disclosure';
  if v_unmasked_row.value is null or v_unmasked_row.notes is null then
    raise exception 'assertion failed: expected financial value/notes visible for a caller WITH PRC:View cost';
  end if;

  -- (a dedicated missing_required_criteria case is covered by a separate assessment further below)
  v_assessment := app.submit_vendor_assessment_for_review(v_assessment.id, v_assessment.record_version, null, v_staff, 'staff');
  if v_assessment.status <> 'submitted' then
    raise exception 'assertion failed: expected submitted, got %', v_assessment.status;
  end if;

  -- MANDATORY maker-checker: the assessor may not decide their own review.
  begin
    perform app.decide_vendor_assessment_review(v_assessment.id, v_assessment.record_version, 'approve', null, v_staff, 'staff');
    raise exception 'assertion failed: expected self_approval_not_allowed for the assessor deciding their own review';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;

  v_assessment := app.begin_vendor_assessment_review(v_assessment.id, v_assessment.record_version, v_reviewer, 'reviewer');
  if v_assessment.status <> 'under_review' or v_assessment.reviewer_auth_user_id <> v_reviewer then
    raise exception 'assertion failed: expected under_review with reviewer set, got % / %', v_assessment.status, v_assessment.reviewer_auth_user_id;
  end if;

  v_assessment := app.decide_vendor_assessment_review(v_assessment.id, v_assessment.record_version, 'approve', null, v_reviewer, 'reviewer');
  if v_assessment.status <> 'approved' then
    raise exception 'assertion failed: expected approved, got %', v_assessment.status;
  end if;
  if v_assessment.expiry_date <> (v_assessment.decided_at::date + 180) then
    raise exception 'assertion failed: expected expiry_date = decided_at + 180 days, got % vs decided_at %', v_assessment.expiry_date, v_assessment.decided_at;
  end if;

  -- get_vendor_assessment surfaces reassessment_due = false for a far-future expiry.
  if (select reassessment_due from app.get_vendor_assessment(v_assessment.id, v_staff)) <> false then
    raise exception 'assertion failed: expected reassessment_due=false for a freshly-approved assessment';
  end if;
end $$;

\echo '>> begin_vendor_assessment_review self-approval defense-in-depth: an actor holding BOTH Edit and Approve who is also the assessor is blocked at begin_review, not only at decide'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_dual uuid := '00000000-0000-0000-0000-000000026103';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-1');
  v_template_id uuid := (select id from app.vendor_assessment_templates where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-template-1');
  v_crit record;
  v_assessment app.vendor_assessments;
begin
  v_assessment := app.start_vendor_assessment(v_vendor_id, v_template_id, null, 'idem-vasm-assessment-dual', v_dual, 'dual');
  for v_crit in select id, weight from app.vendor_assessment_template_criteria where template_version_id = v_template_id and status = 'active' loop
    perform app.record_vendor_assessment_answer(v_assessment.id, v_crit.id, 'ok', 80, null, null, v_dual, 'dual');
  end loop;
  select * into v_assessment from app.vendor_assessments where id = v_assessment.id;
  v_assessment := app.submit_vendor_assessment_for_review(v_assessment.id, v_assessment.record_version, null, v_dual, 'dual');

  begin
    perform app.begin_vendor_assessment_review(v_assessment.id, v_assessment.record_version, v_dual, 'dual');
    raise exception 'assertion failed: expected self_approval_not_allowed at begin_review for the assessor';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;

  -- pre-assigning yourself as reviewer at start/submit time is blocked too.
  begin
    perform app.start_vendor_assessment(v_vendor_id, v_template_id, v_dual, 'idem-vasm-assessment-self-reviewer', v_dual, 'dual');
    raise exception 'assertion failed: expected self_approval_not_allowed for pre-assigning self as reviewer';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;

  -- cleanup: a real, separate reviewer decides the dual assessment so it no longer
  -- occupies the one-open-assessment-per-(vendor,type) slot for later test blocks.
  perform app.decide_vendor_assessment_review(v_assessment.id, v_assessment.record_version, 'approve', null, '00000000-0000-0000-0000-000000026104', 'reviewer');
end $$;

\echo '>> reviewer exclusivity at decide_vendor_assessment_review (adversarial-review fix): once app.begin_vendor_assessment_review assigns a reviewer, a DIFFERENT Approve/Reject-holding actor may not decide -- the row must never silently misattribute the decision away from the actually-assigned reviewer'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000026104';
  v_dual uuid := '00000000-0000-0000-0000-000000026103';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-1');
  v_template_id uuid := (select id from app.vendor_assessment_templates where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-template-1');
  v_assessment app.vendor_assessments;
  v_crit record;
begin
  v_assessment := app.start_vendor_assessment(v_vendor_id, v_template_id, null, 'idem-vasm-reviewer-exclusivity', v_staff, 'staff');
  for v_crit in select id from app.vendor_assessment_template_criteria where template_version_id = v_template_id and status = 'active' loop
    perform app.record_vendor_assessment_answer(v_assessment.id, v_crit.id, 'ok', 85, null, null, v_staff, 'staff');
  end loop;
  select * into v_assessment from app.vendor_assessments where id = v_assessment.id;
  v_assessment := app.submit_vendor_assessment_for_review(v_assessment.id, v_assessment.record_version, null, v_staff, 'staff');
  v_assessment := app.begin_vendor_assessment_review(v_assessment.id, v_assessment.record_version, v_reviewer, 'reviewer');

  -- v_dual holds Approve/Reject too (and is not the assessor here), but is NOT the
  -- assigned reviewer -- must be rejected, not silently allowed to decide.
  begin
    perform app.decide_vendor_assessment_review(v_assessment.id, v_assessment.record_version, 'approve', null, v_dual, 'dual');
    raise exception 'assertion failed: expected review_already_assigned for a different actor deciding an already-assigned review';
  exception
    when others then
      if sqlerrm not like 'review_already_assigned%' then raise; end if;
  end;

  -- the ACTUALLY-assigned reviewer can still decide normally, and the row correctly
  -- attributes the decision to them.
  v_assessment := app.decide_vendor_assessment_review(v_assessment.id, v_assessment.record_version, 'approve', null, v_reviewer, 'reviewer');
  if v_assessment.status <> 'approved' or v_assessment.reviewer_auth_user_id <> v_reviewer then
    raise exception 'assertion failed: expected approved with reviewer_auth_user_id correctly attributed to the assigned reviewer, got % / %', v_assessment.status, v_assessment.reviewer_auth_user_id;
  end if;
end $$;

\echo '>> template-version snapshot immutability: superseding the published template with a NEW version (different weights) never changes an in-flight/completed assessment''s own scoring, since it always scores against its own applied template_version_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000026104';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-1');
  v_old_template_id uuid := (select id from app.vendor_assessment_templates where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-template-1');
  v_target_assessment_id uuid := (select id from app.vendor_assessments where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-assessment-1');
  v_new_template app.vendor_assessment_templates;
  v_score_before numeric;
  v_score_after numeric;
begin
  select calculated_score into v_score_before from app.vendor_assessments where id = v_target_assessment_id;

  -- publish a NEW version with DIFFERENT weights over the same criteria set, superseding the old one.
  v_new_template := app.create_vendor_assessment_template_draft(v_tenant1, 'trucking', 'initial', 'Initial Trucking Assessment v2', 're-weighted', 180, 80, 60, 100, 'idem-vasm-template-1b', v_staff, 'staff');
  perform app.add_vendor_assessment_template_criterion(v_new_template.id, 'On-time delivery rate', 'operational', 20, null, 1, v_staff, 'staff');
  perform app.add_vendor_assessment_template_criterion(v_new_template.id, 'Safety compliance', 'safety', 20, null, 2, v_staff, 'staff');
  perform app.add_vendor_assessment_template_criterion(v_new_template.id, 'Financial stability disclosure', 'financial', 60, null, 3, v_staff, 'staff');
  v_new_template := app.publish_vendor_assessment_template(v_new_template.id, v_new_template.record_version, v_old_template_id, v_reviewer, 'reviewer');
  if v_new_template.status <> 'published' then
    raise exception 'assertion failed: expected new template published, got %', v_new_template.status;
  end if;

  -- old template is now archived...
  if (select status from app.vendor_assessment_templates where id = v_old_template_id) <> 'archived' then
    raise exception 'assertion failed: expected old template archived after supersede';
  end if;

  -- ...but the already-approved assessment's own template_version_id never changed, and recalculating it STILL yields the original 85.00 (weights 50/30/20), not the new template's 20/20/60 weighting (which would compute 20*90/100+20*100/100+60*50/100 = 18+20+30 = 68).
  if (select template_version_id from app.vendor_assessments where id = v_target_assessment_id) <> v_old_template_id then
    raise exception 'assertion failed: expected the completed assessment''s template_version_id to remain the OLD template id';
  end if;

  perform app.calculate_vendor_assessment_score(
    v_target_assessment_id,
    (select record_version from app.vendor_assessments where id = v_target_assessment_id),
    v_staff, 'staff'
  );
  select calculated_score into v_score_after from app.vendor_assessments where id = v_target_assessment_id;
  if v_score_after <> v_score_before or v_score_after <> 85.00 then
    raise exception 'assertion failed: expected recalculated score to remain 85.00 (snapshot immutability), got % (was %)', v_score_after, v_score_before;
  end if;

  -- a NEW assessment started against the NEW template version scores against the NEW weights (68, band conditional since 60<=68<80).
  declare
    v_new_assessment app.vendor_assessments;
    v_crit record;
  begin
    v_new_assessment := app.start_vendor_assessment(v_vendor_id, v_new_template.id, null, 'idem-vasm-assessment-newtemplate', v_staff, 'staff');
    for v_crit in select id, label from app.vendor_assessment_template_criteria where template_version_id = v_new_template.id and status = 'active' loop
      if v_crit.label = 'On-time delivery rate' then
        perform app.record_vendor_assessment_answer(v_new_assessment.id, v_crit.id, '90', 90, null, null, v_staff, 'staff');
      elsif v_crit.label = 'Safety compliance' then
        perform app.record_vendor_assessment_answer(v_new_assessment.id, v_crit.id, '100', 100, null, null, v_staff, 'staff');
      else
        perform app.record_vendor_assessment_answer(v_new_assessment.id, v_crit.id, '50', 50, null, null, v_staff, 'staff');
      end if;
    end loop;
    select * into v_new_assessment from app.vendor_assessments where id = v_new_assessment.id;
    v_new_assessment := app.calculate_vendor_assessment_score(v_new_assessment.id, v_new_assessment.record_version, v_staff, 'staff');
    if v_new_assessment.calculated_score <> 68.00 or v_new_assessment.score_band <> 'conditional' then
      raise exception 'assertion failed: expected the new-template assessment to score 68.00/conditional, got % / %', v_new_assessment.calculated_score, v_new_assessment.score_band;
    end if;

    -- cleanup: decide this assessment so it no longer occupies vendor-1's own
    -- one-open-assessment-per-(vendor,type) slot for later test blocks in this file.
    v_new_assessment := app.submit_vendor_assessment_for_review(v_new_assessment.id, v_new_assessment.record_version, null, v_staff, 'staff');
    perform app.decide_vendor_assessment_review(v_new_assessment.id, v_new_assessment.record_version, 'approve', null, '00000000-0000-0000-0000-000000026104', 'reviewer');
  end;

  -- adversarial-review fix (guard regression, sequential proof -- the genuine
  -- concurrent-session race between this UPDATE and an independent
  -- app.archive_vendor_assessment_template call on the SAME superseded row was
  -- reproduced and fixed by adding a `for update` lock plus a real
  -- record_version/status-guarded UPDATE with a not-found re-check; verifying the
  -- race itself requires two live sessions, outside this sequential script, but this
  -- proves the guard's ordinary-path behavior): v_old_template_id is already
  -- 'archived' (superseded above) -- attempting to supersede it AGAIN via a fresh
  -- draft's publish must reject on the pre-existing status guard, not silently
  -- re-archive it a second time with no audit trail of its own.
  declare
    v_third_template app.vendor_assessment_templates;
  begin
    -- SAME tenant/vendor_category/assessment_type as v_old_template_id, so this
    -- exercises the STATUS guard specifically, not the earlier type-mismatch check.
    v_third_template := app.create_vendor_assessment_template_draft(v_tenant1, 'trucking', 'initial', 'Bogus Re-Supersede Attempt', null, 90, 70, 50, 100, 'idem-vasm-resupersede-attempt', v_staff, 'staff');
    perform app.add_vendor_assessment_template_criterion(v_third_template.id, 'Only criterion', 'operational', 100, null, 1, v_staff, 'staff');
    begin
      perform app.publish_vendor_assessment_template(v_third_template.id, v_third_template.record_version, v_old_template_id, v_reviewer, 'reviewer');
      raise exception 'assertion failed: expected invalid_supersede for re-superseding an already-archived template';
    exception
      when others then
        if sqlerrm not like 'invalid_supersede%' then raise; end if;
    end;
  end;
end $$;

\echo '>> manual score adjustment: PRC:Override-gated, mandatory reason, before/after evidence genuinely recorded in the audit trail; a second override records the PRIOR adjustment as its own before value'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000026104';
  v_manager uuid := '00000000-0000-0000-0000-000000026105';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-1');
  v_template_id uuid := (select id from app.vendor_assessment_templates where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-template-1b');
  v_assessment app.vendor_assessments;
  v_crit record;
  v_before jsonb;
  v_after jsonb;
begin
  v_assessment := app.start_vendor_assessment(v_vendor_id, v_template_id, null, 'idem-vasm-assessment-adjust', v_staff, 'staff');
  for v_crit in select id from app.vendor_assessment_template_criteria where template_version_id = v_template_id and status = 'active' loop
    perform app.record_vendor_assessment_answer(v_assessment.id, v_crit.id, 'ok', 80, null, null, v_staff, 'staff');
  end loop;
  select * into v_assessment from app.vendor_assessments where id = v_assessment.id;
  v_assessment := app.submit_vendor_assessment_for_review(v_assessment.id, v_assessment.record_version, null, v_staff, 'staff');
  if v_assessment.calculated_score <> 80.00 then
    raise exception 'assertion failed: expected calculated_score 80.00, got %', v_assessment.calculated_score;
  end if;

  -- staff (no Override) cannot adjust.
  begin
    perform app.adjust_vendor_assessment_score(v_assessment.id, v_assessment.record_version, 70, 'recalibration', v_staff, 'staff');
    raise exception 'assertion failed: expected insufficient_authority for staff adjusting the score';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- reason is mandatory.
  begin
    perform app.adjust_vendor_assessment_score(v_assessment.id, v_assessment.record_version, 70, null, v_manager, 'manager');
    raise exception 'assertion failed: expected reason_required';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_assessment := app.adjust_vendor_assessment_score(v_assessment.id, v_assessment.record_version, 70, 'evidence of undisclosed subcontracting found post-submission', v_manager, 'manager');
  if v_assessment.adjusted_score <> 70.00 or v_assessment.adjustment_reason is null or v_assessment.adjusted_by <> 'manager' or v_assessment.adjusted_at is null then
    raise exception 'assertion failed: expected adjusted_score/reason/by/at all set after override';
  end if;
  -- adversarial-review fix: score_band is RECOMPUTED against the adjusted score, not
  -- left frozen at the machine-calculated band. Template idem-vasm-template-1b has
  -- pass_threshold=80/conditional_threshold=60 -- 70 is 'conditional', not 'pass'.
  if v_assessment.score_band <> 'conditional' then
    raise exception 'assertion failed: expected score_band recomputed to conditional for adjusted_score=70 (pass=80/conditional=60), got %', v_assessment.score_band;
  end if;

  -- matched by the real after_value.score content, not "most recent occurred_at" --
  -- both overrides run inside the same enclosing transaction, so Postgres' `now()`
  -- (and therefore occurred_at) is IDENTICAL for both audit rows; an occurred_at-only
  -- ordering would be a genuine tie, not a reliable "latest" signal.
  select before_value, after_value into v_before, v_after
  from app.audit_logs
  where tenant_id = v_tenant1 and action = 'adjust_vendor_assessment_score' and resource_id = v_assessment.id and (after_value ->> 'score')::numeric = 70.00;
  if v_before is null or v_after is null then
    raise exception 'assertion failed: expected BOTH before_value and after_value genuinely recorded in the audit trail';
  end if;
  if (v_before ->> 'score')::numeric <> 80.00 or (v_after ->> 'score')::numeric <> 70.00 then
    raise exception 'assertion failed: expected before=80.00/after=70.00 in the audit trail, got %/%', v_before, v_after;
  end if;

  -- a SECOND override records the PRIOR adjustment (70) as its own before value, not the original calculated_score (80).
  v_assessment := app.adjust_vendor_assessment_score(v_assessment.id, v_assessment.record_version, 55, 'further evidence downgraded the assessment', v_manager, 'manager');
  select before_value, after_value into v_before, v_after
  from app.audit_logs
  where tenant_id = v_tenant1 and action = 'adjust_vendor_assessment_score' and resource_id = v_assessment.id and (after_value ->> 'score')::numeric = 55.00;
  if (v_before ->> 'score')::numeric <> 70.00 or (v_after ->> 'score')::numeric <> 55.00 then
    raise exception 'assertion failed: expected before=70.00 (the PRIOR adjustment)/after=55.00 on the second override, got %/%', v_before, v_after;
  end if;
  if (v_before ->> 'score_band') <> 'conditional' or (v_after ->> 'score_band') <> 'fail' then
    raise exception 'assertion failed: expected before_value.score_band=conditional/after_value.score_band=fail in the audit trail, got %/%', v_before, v_after;
  end if;
  -- 55 < conditional_threshold(60) -- 'fail', and the row itself (not just the audit
  -- trail) reflects it: an approved assessment can never persist a score/band pairing
  -- that contradicts itself.
  if v_assessment.score_band <> 'fail' then
    raise exception 'assertion failed: expected score_band recomputed to fail for adjusted_score=55 (conditional=60), got %', v_assessment.score_band;
  end if;

  -- cleanup: decide this assessment so it no longer occupies vendor-1's own
  -- one-open-assessment-per-(vendor,type) slot for later test blocks.
  perform app.decide_vendor_assessment_review(v_assessment.id, v_assessment.record_version, 'approve', null, v_reviewer, 'reviewer');
end $$;

\echo '>> reject path: reject requires a reason; expiry_date stays null; a rejected assessment cannot start a reassessment (predecessor_not_approved)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000026104';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-1');
  v_template_id uuid := (select id from app.vendor_assessment_templates where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-template-1b');
  v_assessment app.vendor_assessments;
  v_crit record;
begin
  v_assessment := app.start_vendor_assessment(v_vendor_id, v_template_id, null, 'idem-vasm-assessment-reject', v_staff, 'staff');
  for v_crit in select id from app.vendor_assessment_template_criteria where template_version_id = v_template_id and status = 'active' loop
    perform app.record_vendor_assessment_answer(v_assessment.id, v_crit.id, 'weak', 10, null, null, v_staff, 'staff');
  end loop;
  select * into v_assessment from app.vendor_assessments where id = v_assessment.id;
  v_assessment := app.submit_vendor_assessment_for_review(v_assessment.id, v_assessment.record_version, null, v_staff, 'staff');
  if v_assessment.score_band <> 'fail' then
    raise exception 'assertion failed: expected score_band fail for a low score, got %', v_assessment.score_band;
  end if;

  begin
    perform app.decide_vendor_assessment_review(v_assessment.id, v_assessment.record_version, 'reject', null, v_reviewer, 'reviewer');
    raise exception 'assertion failed: expected reason_required for reject';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_assessment := app.decide_vendor_assessment_review(v_assessment.id, v_assessment.record_version, 'reject', 'score below acceptable threshold', v_reviewer, 'reviewer');
  if v_assessment.status <> 'rejected' or v_assessment.expiry_date is not null or v_assessment.decision_reason is null then
    raise exception 'assertion failed: expected rejected status, null expiry_date, non-null decision_reason';
  end if;

  begin
    perform app.start_vendor_assessment_reassessment(v_assessment.id, v_template_id, null, 'idem-vasm-reassess-of-rejected', v_staff, 'staff');
    raise exception 'assertion failed: expected predecessor_not_approved';
  exception
    when others then
      if sqlerrm not like 'predecessor_not_approved%' then raise; end if;
  end;
end $$;

\echo '>> findings and corrective actions: raise -> resolve/waive; close_vendor_assessment blocks on open corrective actions unless a PRC:Override reason is supplied; evidence attachment reuses the Document/File Engine (record_type=vendor_assessment)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000026104';
  v_manager uuid := '00000000-0000-0000-0000-000000026105';
  v_admin uuid := '00000000-0000-0000-0000-000000026101';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-1');
  v_template_id uuid := (select id from app.vendor_assessment_templates where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-template-1b');
  v_assessment app.vendor_assessments;
  v_crit record;
  v_finding app.vendor_assessment_findings;
  v_finding2 app.vendor_assessment_findings;
  v_action app.vendor_assessment_corrective_actions;
  v_action2 app.vendor_assessment_corrective_actions;
  v_file app.files;
  v_doctype_draft app.config_versions;
begin
  perform app.register_document_type('vendor_assessment_evidence', 'Vendor Assessment Evidence', 'DOC', '00000000-0000-0000-0000-000000026999', 'supreme');
  v_doctype_draft := app.create_config_draft('document:vendor_assessment_evidence', v_tenant1, 'tenant', null, v_admin, 'admin');
  perform app.set_config_items(v_doctype_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_admin, 'admin');
  perform app.publish_document_type_definition(v_doctype_draft.id, v_admin, now(), 'admin');

  v_assessment := app.start_vendor_assessment(v_vendor_id, v_template_id, null, 'idem-vasm-assessment-findings', v_staff, 'staff');
  for v_crit in select id from app.vendor_assessment_template_criteria where template_version_id = v_template_id and status = 'active' loop
    perform app.record_vendor_assessment_answer(v_assessment.id, v_crit.id, 'ok', 85, null, null, v_staff, 'staff');
  end loop;
  select * into v_assessment from app.vendor_assessments where id = v_assessment.id;
  v_assessment := app.submit_vendor_assessment_for_review(v_assessment.id, v_assessment.record_version, null, v_staff, 'staff');
  v_assessment := app.begin_vendor_assessment_review(v_assessment.id, v_assessment.record_version, v_reviewer, 'reviewer');

  v_finding := app.raise_vendor_assessment_finding(v_assessment.id, 'high', 'expired safety certificate on file', v_staff, 'staff');
  if v_finding.status <> 'open' then
    raise exception 'assertion failed: expected finding status open, got %', v_finding.status;
  end if;

  v_action := app.create_vendor_assessment_corrective_action(v_finding.id, 'obtain a renewed safety certificate', current_date + 14, v_staff, 'staff');
  if v_action.status <> 'open' or v_action.assessment_id <> v_assessment.id then
    raise exception 'assertion failed: expected a new open corrective action linked to the assessment';
  end if;

  -- a second finding, waived, with its own corrective action completed with evidence.
  v_finding2 := app.raise_vendor_assessment_finding(v_assessment.id, 'low', 'minor documentation formatting issue', v_staff, 'staff');
  v_finding2 := app.decide_vendor_assessment_finding(v_finding2.id, v_finding2.record_version, 'waived', 'cosmetic only, no material risk', v_staff, 'staff');
  if v_finding2.status <> 'waived' then
    raise exception 'assertion failed: expected finding2 waived, got %', v_finding2.status;
  end if;

  v_action2 := app.create_vendor_assessment_corrective_action(v_finding.id, 'secondary confirming action', null, v_staff, 'staff');
  v_file := app.initiate_file_upload(
    v_tenant1, 'vendor_assessment_evidence', 'vendor_assessment', v_assessment.id,
    'renewed-safety-cert.pdf', 'application/pdf', 102400, 'internal', false, null, null, null,
    'idem-vasm-evidence-1', v_staff, 'staff'
  );

  -- unsafe evidence: a freshly-uploaded file defaults to malware_scan_status='pending' -- both
  -- app.record_vendor_assessment_answer and app.update_vendor_assessment_corrective_action_status
  -- reject it until it is resolved 'clean' (adversarial-review fix; the answer-side
  -- equivalent is covered in its own dedicated block further below, since this
  -- assessment is already under_review here and record_vendor_assessment_answer
  -- requires draft|in_progress).
  begin
    perform app.update_vendor_assessment_corrective_action_status(v_action2.id, v_action2.record_version, 'completed', 'attempted with an unscanned file', v_file.id, v_staff, 'staff');
    raise exception 'assertion failed: expected assessment_unsafe_evidence for a still-pending-scan file';
  exception
    when others then
      if sqlerrm not like 'assessment_unsafe_evidence%' then raise; end if;
  end;

  -- cross-tenant evidence laundering is rejected: a file that genuinely belongs to
  -- vasm2 (different tenant, unrelated record_type) can never be attached as vasm1
  -- evidence, even once scanned clean (adversarial-review fix -- previously a bare
  -- FK let ANY file of ANY tenant/record_type/scan-status be linked).
  declare
    v_tenant2 uuid := (select id from app.tenants where slug = 'vasm2');
    v_t2_staff uuid := '00000000-0000-0000-0000-000000026202';
    v_t2_doctype_draft app.config_versions;
    v_foreign_file app.files;
  begin
    perform app.register_document_type('vendor_assessment_evidence', 'Vendor Assessment Evidence', 'DOC', '00000000-0000-0000-0000-000000026999', 'supreme');
    v_t2_doctype_draft := app.create_config_draft('document:vendor_assessment_evidence', v_tenant2, 'tenant', null, '00000000-0000-0000-0000-000000026201', 'admin2');
    perform app.set_config_items(v_t2_doctype_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
      jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
      jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
      jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
      jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
    ), '00000000-0000-0000-0000-000000026201', 'admin2');
    perform app.publish_document_type_definition(v_t2_doctype_draft.id, '00000000-0000-0000-0000-000000026201', now(), 'admin2');
    v_foreign_file := app.initiate_file_upload(
      v_tenant2, 'vendor_assessment_evidence', 'vendor_assessment', gen_random_uuid(),
      'unrelated-vasm2-file.pdf', 'application/pdf', 1024, 'internal', false, null, null, null,
      'idem-vasm2-foreign-evidence', v_t2_staff, 'staff2'
    );
    perform app.record_file_scan_result(v_foreign_file.id, 'clean', 'test-scanner-ref', v_t2_staff, 'staff2');
    begin
      perform app.update_vendor_assessment_corrective_action_status(v_action2.id, v_action2.record_version, 'completed', 'attempted with a foreign-tenant file', v_foreign_file.id, v_staff, 'staff');
      raise exception 'assertion failed: expected assessment_evidence_file_mismatch for a cross-tenant/wrong-record file';
    exception
      when others then
        if sqlerrm not like 'assessment_evidence_file_mismatch%' then raise; end if;
    end;
  end;

  -- same-tenant but wrong record_type/record_id is also rejected, not just cross-tenant.
  declare
    v_wrong_record_file app.files;
  begin
    v_wrong_record_file := app.initiate_file_upload(
      v_tenant1, 'vendor_assessment_evidence', 'vendor_profile', v_vendor_id,
      'wrong-record-type.pdf', 'application/pdf', 1024, 'internal', false, null, null, null,
      'idem-vasm-wrongrecord-evidence', v_staff, 'staff'
    );
    perform app.record_file_scan_result(v_wrong_record_file.id, 'clean', 'test-scanner-ref', v_staff, 'staff');
    begin
      perform app.update_vendor_assessment_corrective_action_status(v_action2.id, v_action2.record_version, 'completed', 'attempted with a wrong record_type file', v_wrong_record_file.id, v_staff, 'staff');
      raise exception 'assertion failed: expected assessment_evidence_file_mismatch for a wrong record_type/record_id file';
    exception
      when others then
        if sqlerrm not like 'assessment_evidence_file_mismatch%' then raise; end if;
    end;
  end;

  -- once genuinely scanned clean and correctly scoped, the SAME file is accepted.
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', v_staff, 'staff');
  v_action2 := app.update_vendor_assessment_corrective_action_status(v_action2.id, v_action2.record_version, 'completed', 'renewed certificate uploaded and verified', v_file.id, v_staff, 'staff');
  if v_action2.status <> 'completed' or v_action2.resolved_evidence_file_id <> v_file.id or v_action2.resolution_notes is null then
    raise exception 'assertion failed: expected corrective action 2 completed with evidence attached';
  end if;

  -- resolution_notes are required to mark completed.
  begin
    perform app.update_vendor_assessment_corrective_action_status(v_action.id, v_action.record_version, 'completed', null, null, v_staff, 'staff');
    raise exception 'assertion failed: expected resolution_notes_required';
  exception
    when others then
      if sqlerrm not like 'resolution_notes_required%' then raise; end if;
  end;

  v_assessment := app.decide_vendor_assessment_review(v_assessment.id, v_assessment.record_version, 'approve', null, v_reviewer, 'reviewer');

  -- one corrective action (v_action) is still open -- close is blocked without an override reason, even for the Override-holding manager.
  begin
    perform app.close_vendor_assessment(v_assessment.id, v_assessment.record_version, null, v_manager, 'manager');
    raise exception 'assertion failed: expected open_corrective_actions_block_close';
  exception
    when others then
      if sqlerrm not like 'open_corrective_actions_block_close%' then raise; end if;
  end;

  -- staff (no Override) cannot close with an override reason either.
  begin
    perform app.close_vendor_assessment(v_assessment.id, v_assessment.record_version, 'closing anyway', v_staff, 'staff');
    raise exception 'assertion failed: expected insufficient_authority for staff closing with an open corrective action';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_assessment := app.close_vendor_assessment(v_assessment.id, v_assessment.record_version, 'vendor operationally cleared pending certificate renewal, tracked outside this cycle', v_manager, 'manager');
  if v_assessment.status <> 'closed' then
    raise exception 'assertion failed: expected closed, got %', v_assessment.status;
  end if;

  -- a finding may no longer be raised against a closed assessment.
  begin
    perform app.raise_vendor_assessment_finding(v_assessment.id, 'low', 'too late', v_staff, 'staff');
    raise exception 'assertion failed: expected vendor_assessment_not_active';
  exception
    when others then
      if sqlerrm not like 'vendor_assessment_not_active%' then raise; end if;
  end;

  -- adversarial-review fix: a brand-new corrective action can no longer be attached
  -- to an already-closed assessment either -- v_finding is STILL 'open' (only the
  -- assessment itself was closed, via the governed override, while v_action stayed
  -- open) so this exercises the real fix, not a finding-status short-circuit.
  if (select status from app.vendor_assessment_findings where id = v_finding.id) <> 'open' then
    raise exception 'assertion failed: test precondition violated -- expected v_finding to still be open';
  end if;
  begin
    perform app.create_vendor_assessment_corrective_action(v_finding.id, 'too late, assessment already closed', null, v_staff, 'staff');
    raise exception 'assertion failed: expected vendor_assessment_closed for a corrective action raised after the parent assessment closed';
  exception
    when others then
      if sqlerrm not like 'vendor_assessment_closed%' then raise; end if;
  end;
end $$;

\echo '>> record_vendor_assessment_answer evidence validation: unsafe (still-scanning) evidence rejected; cross-tenant/wrong-record evidence rejected; a genuinely clean, correctly-scoped file is accepted'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'vasm2');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000026104';
  v_t2_staff uuid := '00000000-0000-0000-0000-000000026202';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-2');
  v_template app.vendor_assessment_templates;
  v_crit app.vendor_assessment_template_criteria;
  v_assessment app.vendor_assessments;
  v_pending_file app.files;
  v_foreign_file app.files;
  v_wrong_record_file app.files;
begin
  -- a fresh, otherwise-unused assessment_type ('financial') keeps this block fully
  -- self-contained -- no collision with the one-open-assessment-per-(vendor,type)
  -- slot any other test block relies on.
  v_template := app.create_vendor_assessment_template_draft(v_tenant1, null, 'financial', 'Answer Evidence Validation Template', null, 90, 70, 50, 100, 'idem-vasm-evidence-answer-template', v_staff, 'staff');
  v_crit := app.add_vendor_assessment_template_criterion(v_template.id, 'Only criterion', 'financial', 100, null, 1, v_staff, 'staff');
  v_template := app.publish_vendor_assessment_template(v_template.id, v_template.record_version, null, v_reviewer, 'reviewer');

  v_assessment := app.start_vendor_assessment(v_vendor_id, v_template.id, null, 'idem-vasm-evidence-answer-assessment', v_staff, 'staff');

  -- the document type/config used by the earlier findings-and-corrective-actions
  -- block is already registered/published for tenant1 by this point in the file.
  v_pending_file := app.initiate_file_upload(
    v_tenant1, 'vendor_assessment_evidence', 'vendor_assessment', v_assessment.id,
    'pending-scan.pdf', 'application/pdf', 1024, 'internal', false, null, null, null,
    'idem-vasm-answer-evidence-pending', v_staff, 'staff'
  );
  begin
    perform app.record_vendor_assessment_answer(v_assessment.id, v_crit.id, 'ok', 90, v_pending_file.id, null, v_staff, 'staff');
    raise exception 'assertion failed: expected assessment_unsafe_evidence for a still-pending-scan file';
  exception
    when others then
      if sqlerrm not like 'assessment_unsafe_evidence%' then raise; end if;
  end;

  perform app.record_file_scan_result(v_pending_file.id, 'infected', 'test-scanner-ref', v_staff, 'staff');
  begin
    perform app.record_vendor_assessment_answer(v_assessment.id, v_crit.id, 'ok', 90, v_pending_file.id, null, v_staff, 'staff');
    raise exception 'assertion failed: expected assessment_unsafe_evidence for a file scanned infected';
  exception
    when others then
      if sqlerrm not like 'assessment_unsafe_evidence%' then raise; end if;
  end;

  v_foreign_file := app.initiate_file_upload(
    v_tenant2, 'vendor_assessment_evidence', 'vendor_assessment', gen_random_uuid(),
    'vasm2-own-file.pdf', 'application/pdf', 1024, 'internal', false, null, null, null,
    'idem-vasm-answer-foreign-evidence', v_t2_staff, 'staff2'
  );
  perform app.record_file_scan_result(v_foreign_file.id, 'clean', 'test-scanner-ref', v_t2_staff, 'staff2');
  begin
    perform app.record_vendor_assessment_answer(v_assessment.id, v_crit.id, 'ok', 90, v_foreign_file.id, null, v_staff, 'staff');
    raise exception 'assertion failed: expected assessment_evidence_file_mismatch for a cross-tenant file';
  exception
    when others then
      if sqlerrm not like 'assessment_evidence_file_mismatch%' then raise; end if;
  end;

  v_wrong_record_file := app.initiate_file_upload(
    v_tenant1, 'vendor_assessment_evidence', 'vendor_profile', v_vendor_id,
    'wrong-record-type.pdf', 'application/pdf', 1024, 'internal', false, null, null, null,
    'idem-vasm-answer-wrongrecord-evidence', v_staff, 'staff'
  );
  perform app.record_file_scan_result(v_wrong_record_file.id, 'clean', 'test-scanner-ref', v_staff, 'staff');
  begin
    perform app.record_vendor_assessment_answer(v_assessment.id, v_crit.id, 'ok', 90, v_wrong_record_file.id, null, v_staff, 'staff');
    raise exception 'assertion failed: expected assessment_evidence_file_mismatch for a wrong record_type/record_id file';
  exception
    when others then
      if sqlerrm not like 'assessment_evidence_file_mismatch%' then raise; end if;
  end;

  -- a genuinely clean, correctly-scoped file (same tenant, record_type='vendor_assessment', record_id=this assessment) is accepted.
  declare
    v_clean_file app.files;
    v_answer app.vendor_assessment_answers;
  begin
    v_clean_file := app.initiate_file_upload(
      v_tenant1, 'vendor_assessment_evidence', 'vendor_assessment', v_assessment.id,
      'clean-evidence.pdf', 'application/pdf', 1024, 'internal', false, null, null, null,
      'idem-vasm-answer-clean-evidence', v_staff, 'staff'
    );
    perform app.record_file_scan_result(v_clean_file.id, 'clean', 'test-scanner-ref', v_staff, 'staff');
    v_answer := app.record_vendor_assessment_answer(v_assessment.id, v_crit.id, 'ok', 90, v_clean_file.id, null, v_staff, 'staff');
    if v_answer.evidence_file_id <> v_clean_file.id then
      raise exception 'assertion failed: expected the genuinely clean, correctly-scoped evidence file to be accepted';
    end if;
  end;

  -- cleanup: decide this assessment so it does not leave a stray open slot behind.
  select * into v_assessment from app.vendor_assessments where id = v_assessment.id;
  v_assessment := app.submit_vendor_assessment_for_review(v_assessment.id, v_assessment.record_version, null, v_staff, 'staff');
  perform app.decide_vendor_assessment_review(v_assessment.id, v_assessment.record_version, 'approve', null, v_reviewer, 'reviewer');
end $$;

\echo '>> close_vendor_assessment with zero open corrective actions succeeds under plain PRC:Edit (no Override needed)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000026104';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-1');
  v_template_id uuid := (select id from app.vendor_assessment_templates where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-template-1b');
  v_assessment app.vendor_assessments;
  v_crit record;
begin
  v_assessment := app.start_vendor_assessment(v_vendor_id, v_template_id, null, 'idem-vasm-assessment-noca', v_staff, 'staff');
  for v_crit in select id from app.vendor_assessment_template_criteria where template_version_id = v_template_id and status = 'active' loop
    perform app.record_vendor_assessment_answer(v_assessment.id, v_crit.id, 'ok', 85, null, null, v_staff, 'staff');
  end loop;
  select * into v_assessment from app.vendor_assessments where id = v_assessment.id;
  v_assessment := app.submit_vendor_assessment_for_review(v_assessment.id, v_assessment.record_version, null, v_staff, 'staff');
  v_assessment := app.decide_vendor_assessment_review(v_assessment.id, v_assessment.record_version, 'approve', null, v_reviewer, 'reviewer');
  v_assessment := app.close_vendor_assessment(v_assessment.id, v_assessment.record_version, null, v_staff, 'staff');
  if v_assessment.status <> 'closed' then
    raise exception 'assertion failed: expected closed under plain PRC:Edit, got %', v_assessment.status;
  end if;
end $$;

\echo '>> reassessment: manual start_vendor_assessment_reassessment references the prior approved assessment as predecessor; conflicting_active_assessment blocks a second concurrent open assessment of the same type; a blacklisted vendor cannot start any assessment'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_predecessor_id uuid := (select id from app.vendor_assessments where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-assessment-noca');
  v_vendor_id uuid := (select vendor_master_record_id from app.vendor_assessments where id = v_predecessor_id);
  v_template_id uuid := (select template_version_id from app.vendor_assessments where id = v_predecessor_id);
  v_blacklisted_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-blacklist');
  v_reviewer uuid := '00000000-0000-0000-0000-000000026104';
  v_reassessment app.vendor_assessments;
  v_crit record;
begin
  v_reassessment := app.start_vendor_assessment_reassessment(v_predecessor_id, v_template_id, null, 'idem-vasm-reassess-1', v_staff, 'staff');
  if v_reassessment.predecessor_assessment_id <> v_predecessor_id or v_reassessment.status <> 'draft' then
    raise exception 'assertion failed: expected a new draft assessment referencing the predecessor';
  end if;

  -- a second attempt to start (initial) a fresh assessment of the same type while the reassessment is still open is blocked.
  begin
    perform app.start_vendor_assessment(v_vendor_id, v_template_id, null, 'idem-vasm-conflict-attempt', v_staff, 'staff');
    raise exception 'assertion failed: expected conflicting_active_assessment';
  exception
    when others then
      if sqlerrm not like 'conflicting_active_assessment%' then raise; end if;
  end;

  -- a blacklisted vendor can never start a new assessment cycle.
  begin
    perform app.start_vendor_assessment(v_blacklisted_vendor_id, v_template_id, null, 'idem-vasm-blacklisted-attempt', v_staff, 'staff');
    raise exception 'assertion failed: expected vendor_blacklisted';
  exception
    when others then
      if sqlerrm not like 'vendor_blacklisted%' then raise; end if;
  end;

  -- cleanup: decide this reassessment so it no longer occupies vendor-1's own
  -- one-open-assessment-per-(vendor,type) slot for later test blocks.
  for v_crit in select id from app.vendor_assessment_template_criteria where template_version_id = v_template_id and status = 'active' loop
    perform app.record_vendor_assessment_answer(v_reassessment.id, v_crit.id, 'ok', 90, null, null, v_staff, 'staff');
  end loop;
  select * into v_reassessment from app.vendor_assessments where id = v_reassessment.id;
  v_reassessment := app.submit_vendor_assessment_for_review(v_reassessment.id, v_reassessment.record_version, null, v_staff, 'staff');
  perform app.decide_vendor_assessment_review(v_reassessment.id, v_reassessment.record_version, 'approve', null, v_reviewer, 'reviewer');
end $$;

\echo '>> downstream read: get_vendor_current_assessment_status returns one row per assessment_type, preferring the most recent approved assessment'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-1');
  v_row record;
  v_found boolean := false;
begin
  for v_row in select * from app.get_vendor_current_assessment_status(v_vendor_id, v_staff) loop
    if v_row.assessment_type = 'initial' then
      v_found := true;
      if v_row.status <> 'approved' then
        raise exception 'assertion failed: expected the current initial-type status to be approved, got %', v_row.status;
      end if;
    end if;
  end loop;
  if not v_found then
    raise exception 'assertion failed: expected at least one initial-type row from get_vendor_current_assessment_status';
  end if;
end $$;

\echo '>> idempotency-key replay AND reused-for-a-different-target rejection: create_vendor_assessment_template_draft and start_vendor_assessment'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-1');
  v_second_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-2');
  v_template_id uuid := (select id from app.vendor_assessment_templates where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-template-1b');
  v_t1 app.vendor_assessment_templates;
  v_t2 app.vendor_assessment_templates;
  v_a1 app.vendor_assessments;
  v_a2 app.vendor_assessments;
begin
  v_t1 := app.create_vendor_assessment_template_draft(v_tenant1, 'operational', 'safety', 'Safety Replay Template', null, 60, 70, 50, 100, 'idem-vasm-replay-template', v_staff, 'staff');
  v_t2 := app.create_vendor_assessment_template_draft(v_tenant1, 'operational', 'safety', 'Safety Replay Template', null, 60, 70, 50, 100, 'idem-vasm-replay-template', v_staff, 'staff');
  if v_t1.id <> v_t2.id then
    raise exception 'assertion failed: expected an idempotency-key replay to return the SAME row';
  end if;

  begin
    perform app.create_vendor_assessment_template_draft(v_tenant1, 'operational', 'safety', 'A Completely Different Template', null, 60, 70, 50, 100, 'idem-vasm-replay-template', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key against a different name';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- adversarial-review fix: the replay comparison now covers EVERY semantically
  -- load-bearing field, not just name/assessment_type -- a reused key with the SAME
  -- name/type but a materially different validity_period_days/pass_threshold/
  -- conditional_threshold must also be rejected, not silently return the FIRST
  -- call's stale configuration.
  begin
    perform app.create_vendor_assessment_template_draft(v_tenant1, 'operational', 'safety', 'Safety Replay Template', null, 30, 70, 50, 100, 'idem-vasm-replay-template', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key against a different validity_period_days';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
  begin
    perform app.create_vendor_assessment_template_draft(v_tenant1, 'operational', 'safety', 'Safety Replay Template', null, 60, 95, 50, 100, 'idem-vasm-replay-template', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key against a different pass_threshold';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
  -- an EXACT replay (all fields identical) still returns the same row cleanly.
  v_t2 := app.create_vendor_assessment_template_draft(v_tenant1, 'operational', 'safety', 'Safety Replay Template', null, 60, 70, 50, 100, 'idem-vasm-replay-template', v_staff, 'staff');
  if v_t1.id <> v_t2.id then
    raise exception 'assertion failed: expected an exact-match replay to still return the SAME row after the widened comparison';
  end if;

  -- vendor-2 (fresh, no open assessment yet) is used as the replay target so this
  -- block does not depend on vendor-1's own open-assessment slot state elsewhere in
  -- this file.
  v_a1 := app.start_vendor_assessment(v_second_vendor_id, v_template_id, null, 'idem-vasm-replay-assessment', v_staff, 'staff');
  v_a2 := app.start_vendor_assessment(v_second_vendor_id, v_template_id, null, 'idem-vasm-replay-assessment', v_staff, 'staff');
  if v_a1.id <> v_a2.id then
    raise exception 'assertion failed: expected an idempotency-key replay on start_vendor_assessment to return the SAME row';
  end if;

  -- same idempotency_key, same template, but a DIFFERENT target vendor -- the
  -- idempotency target-mismatch check fires before the open-assessment check, so
  -- this correctly raises idempotency_key_conflict regardless of vendor-1's own
  -- current open-assessment state.
  begin
    perform app.start_vendor_assessment(v_vendor_id, v_template_id, null, 'idem-vasm-replay-assessment', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key against a different vendor';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
end $$;

\echo '>> record_version stale-version rejection: a mismatched expected_version is rejected on update_vendor_assessment_template_draft, publish_vendor_assessment_template, and submit_vendor_assessment_for_review'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000026104';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-1');
  v_template app.vendor_assessment_templates;
  v_assessment app.vendor_assessments;
  v_crit record;
begin
  v_template := app.create_vendor_assessment_template_draft(v_tenant1, 'trucking', 'incident', 'Stale Version Template', null, 30, 90, 60, 100, 'idem-vasm-stale-template', v_staff, 'staff');
  perform app.add_vendor_assessment_template_criterion(v_template.id, 'Only criterion', 'operational', 100, null, 1, v_staff, 'staff');

  begin
    perform app.update_vendor_assessment_template_draft(v_template.id, v_template.record_version + 99, 'trucking', 'Renamed', null, 30, 90, 60, 100, v_staff, 'staff');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  begin
    perform app.publish_vendor_assessment_template(v_template.id, v_template.record_version + 99, null, v_reviewer, 'reviewer');
    raise exception 'assertion failed: expected stale_version on publish';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_template := app.publish_vendor_assessment_template(v_template.id, v_template.record_version, null, v_reviewer, 'reviewer');
  v_assessment := app.start_vendor_assessment(v_vendor_id, v_template.id, null, 'idem-vasm-stale-assessment', v_staff, 'staff');
  for v_crit in select id from app.vendor_assessment_template_criteria where template_version_id = v_template.id and status = 'active' loop
    perform app.record_vendor_assessment_answer(v_assessment.id, v_crit.id, 'ok', 90, null, null, v_staff, 'staff');
  end loop;
  select * into v_assessment from app.vendor_assessments where id = v_assessment.id;

  begin
    perform app.submit_vendor_assessment_for_review(v_assessment.id, v_assessment.record_version + 99, null, v_staff, 'staff');
    raise exception 'assertion failed: expected stale_version on submit';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
end $$;

\echo '>> missing_required_criteria: submit is blocked while any active criterion of the applied template has no recorded answer'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_staff uuid := '00000000-0000-0000-0000-000000026102';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-1');
  v_template_id uuid := (select id from app.vendor_assessment_templates where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-template-1b');
  v_first_crit uuid;
  v_assessment app.vendor_assessments;
begin
  select id into v_first_crit from app.vendor_assessment_template_criteria where template_version_id = v_template_id and status = 'active' order by display_order limit 1;
  v_assessment := app.start_vendor_assessment(v_vendor_id, v_template_id, null, 'idem-vasm-incomplete-assessment', v_staff, 'staff');
  perform app.record_vendor_assessment_answer(v_assessment.id, v_first_crit, 'partial', 80, null, null, v_staff, 'staff');
  select * into v_assessment from app.vendor_assessments where id = v_assessment.id;

  begin
    perform app.submit_vendor_assessment_for_review(v_assessment.id, v_assessment.record_version, null, v_staff, 'staff');
    raise exception 'assertion failed: expected missing_required_criteria';
  exception
    when others then
      if sqlerrm not like 'missing_required_criteria%' then raise; end if;
  end;
end $$;

\echo '>> cross-tenant isolation: a vasm2 actor cannot read or start an assessment against a vasm1 vendor/template (insufficient_authority via evaluate_permission, never leaked as a different error); a reused REAL vasm1 idempotency key does not silently short-circuit under the attacker''s own identity; raw RLS denies direct row selection'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vasm1');
  v_t2_staff uuid := '00000000-0000-0000-0000-000000026202';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-vendor-1');
  v_template_id uuid := (select id from app.vendor_assessment_templates where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-template-1');
  v_target_assessment_id uuid := (select id from app.vendor_assessments where tenant_id = v_tenant1 and idempotency_key = 'idem-vasm-assessment-1');
begin
  begin
    perform app.get_vendor_assessment(v_target_assessment_id, v_t2_staff);
    raise exception 'assertion failed: expected insufficient_authority for a vasm2 actor reading a vasm1 assessment';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.start_vendor_assessment(v_vendor_id, v_template_id, null, 'idem-vasm-assessment-1', v_t2_staff, 'attacker');
    raise exception 'assertion failed: expected the vasm1 vendor lookup to reject on vasm2 authority, never silently reusing the real key';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000026202", "role": "authenticated"}', true);

  if exists (select 1 from app.vendor_assessments where id = v_target_assessment_id) then
    raise exception 'assertion failed: raw RLS leak -- vasm2 staff directly selected a vasm1 vendor assessment row';
  end if;

  reset role;
end $$;

\echo '>> RLS default-deny for a customer_user-layer principal: tenant membership alone is not enough -- a customer_user-layer actor in the SAME tenant reads zero rows at the raw-RLS level'
do $$
declare
  v_target_assessment_id uuid := (select a.id from app.vendor_assessments a join app.tenants t on t.id = a.tenant_id where t.slug = 'vasm1' and a.idempotency_key = 'idem-vasm-assessment-1');
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000026108", "role": "authenticated"}', true);

  if exists (select 1 from app.vendor_assessments where id = v_target_assessment_id) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.vendor_assessments directly, even inside its own tenant';
  end if;
  if exists (select 1 from app.vendor_assessment_answers where assessment_id = v_target_assessment_id) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.vendor_assessment_answers directly';
  end if;
  if exists (select 1 from app.vendor_assessment_templates where tenant_id = (select id from app.tenants where slug = 'vasm1')) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.vendor_assessment_templates directly';
  end if;

  reset role;
end $$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new PRC-252 function; app._compute_vendor_assessment_score is a private helper with no authenticated/service_role grant at all'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in (
      'create_vendor_assessment_template_draft', 'update_vendor_assessment_template_draft', 'add_vendor_assessment_template_criterion',
      'update_vendor_assessment_template_criterion', 'remove_vendor_assessment_template_criterion', 'publish_vendor_assessment_template',
      'archive_vendor_assessment_template', 'start_vendor_assessment', 'record_vendor_assessment_answer', 'calculate_vendor_assessment_score',
      'submit_vendor_assessment_for_review', 'begin_vendor_assessment_review', 'decide_vendor_assessment_review', 'adjust_vendor_assessment_score',
      'close_vendor_assessment', 'start_vendor_assessment_reassessment', 'raise_vendor_assessment_finding', 'decide_vendor_assessment_finding',
      'create_vendor_assessment_corrective_action', 'update_vendor_assessment_corrective_action_status'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on PRC-252 mutating functions, found %', v_count;
  end if;

  -- grantee='postgres' is Postgres' own implicit owner privilege row (present for
  -- every function regardless of any GRANT statement -- the same shape PRC-251's
  -- own already-VERIFIED app.assert_vendor_profile_editable carries) -- the real
  -- assertion is that no CLIENT-reachable role (authenticated/service_role/anon)
  -- was ever explicitly granted EXECUTE on this private helper.
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and routine_name = '_compute_vendor_assessment_score' and grantee in ('authenticated', 'service_role', 'anon');
  if v_count <> 0 then
    raise exception 'assertion failed: expected app._compute_vendor_assessment_score to carry no authenticated/service_role/anon grant (private helper), found %', v_count;
  end if;
end $$;
