-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Part 2b of 5 of a representative repository-wide fix pass (HRIS, functions 21-41 of 41).
-- See 20260902100000_harden_tenant_id_disclosure_finance.sql for the full rationale
-- (same fix pattern, same repository-wide precedent, applied here to HRIS).
-- Every function below is CREATE OR REPLACE against its CURRENT, live body -- signatures
-- are unchanged throughout, so grants are unaffected.

CREATE OR REPLACE FUNCTION app.decide_performance_appeal(p_appeal_id uuid, p_expected_version integer, p_decision text, p_decision_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_appeals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_appeal app.performance_appeals;
  v_outcome app.performance_outcomes;
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_appeal from app.performance_appeals where id = p_appeal_id for update;
  if not found or not app.has_active_tenant_membership(v_appeal.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_appeal_not_found: %', p_appeal_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Approve', v_appeal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_appeal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  -- Structural self-decision block: the appellant may never decide their
  -- own appeal, even while separately holding HRS:Approve.
  v_self := app.get_self_employee(v_appeal.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_appeal.employee_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own appeal' using errcode = 'insufficient_privilege';
  end if;
  if v_appeal.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_appeal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_appeal.status not in ('submitted', 'under_review') then
    raise exception 'invalid_transition: appeal % is % not open', p_appeal_id, v_appeal.status using errcode = 'check_violation';
  end if;
  if p_decision not in ('uphold', 'overturn') then
    raise exception 'invalid_decision: % must be uphold or overturn', p_decision using errcode = 'check_violation';
  end if;
  if p_decision_reason is null or length(trim(p_decision_reason)) = 0 then
    raise exception 'reason_required: a decision reason is required' using errcode = 'check_violation';
  end if;

  update app.performance_appeals set status = case p_decision when 'uphold' then 'upheld' else 'overturned' end,
    decided_by = p_actor_label, decided_at = now(), decision_reason = p_decision_reason
  where id = p_appeal_id and record_version = p_expected_version
  returning * into v_appeal;
  if not found then
    raise exception 'stale_version: concurrent update detected for appeal %', p_appeal_id using errcode = 'serialization_failure';
  end if;

  -- Lock order note (taxonomy C-21): this function locks performance_appeals
  -- THEN performance_outcomes. app.submit_performance_appeal only ever locks
  -- performance_outcomes (no appeal row exists yet to lock at creation
  -- time), so no sibling function locks these same two tables in the
  -- reverse order -- no deadlock risk between the two.
  select * into v_outcome from app.performance_outcomes where id = v_appeal.outcome_id for update;
  update app.performance_outcomes set status = case when p_decision = 'overturn' then 'reopened' else 'published' end
  where id = v_outcome.id;

  perform app.capture_audit_event(
    v_appeal.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_performance_appeal',
    'app.performance_appeals', v_appeal.id, 'success', null, null, jsonb_build_object('outcome_id', v_appeal.outcome_id, 'decision', p_decision)
  );
  return v_appeal;
end;
$function$;

CREATE OR REPLACE FUNCTION app.decide_succession_candidate(p_candidate_id uuid, p_expected_version integer, p_decision text, p_decision_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.talent_succession_candidates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_row app.talent_succession_candidates;
  v_self app.employees;
begin
  select * into v_row from app.talent_succession_candidates where id = p_candidate_id for update;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'talent_succession_candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_self := app.get_self_employee(v_row.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_row.candidate_employee_id then
    raise exception 'self_decision_not_permitted: an actor may not decide their own succession candidacy' using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status <> 'proposed' then
    raise exception 'invalid_transition: candidate % is % not proposed', p_candidate_id, v_row.status using errcode = 'check_violation';
  end if;
  if p_decision not in ('confirm', 'withdraw') then
    raise exception 'invalid_decision: %', p_decision using errcode = 'check_violation';
  end if;
  if p_decision_reason is null or length(trim(p_decision_reason)) = 0 then
    raise exception 'reason_required: a reason is required to decide a succession candidate' using errcode = 'check_violation';
  end if;

  update app.talent_succession_candidates
  set status = case p_decision when 'confirm' then 'confirmed' else 'withdrawn' end, decision_reason = p_decision_reason, decided_by = p_actor_label, decided_at = now()
  where id = p_candidate_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: concurrent update detected for candidate %', p_candidate_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_succession_candidate',
    'app.talent_succession_candidates', v_row.id, 'success', null, null, jsonb_build_object('decision', p_decision, 'status', v_row.status)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.decide_training_enrollment(p_enrollment_id uuid, p_expected_version integer, p_decision text, p_decision_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_enrollment app.training_enrollments;
  v_session app.training_sessions;
  v_enrolled_count integer;
  v_self app.employees;
  v_status text;
begin
  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id;
  if not found then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.training_sessions where id = v_enrollment.session_id for update;
  if not app.has_active_tenant_membership(v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;

  if not app.check_training_authority('Approve', v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_self := app.get_self_employee(v_session.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_enrollment.employee_id then
    raise exception 'self_decision_not_permitted: an actor may not decide their own enrollment request' using errcode = 'insufficient_privilege';
  end if;
  if v_enrollment.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_enrollment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_enrollment.status <> 'pending_approval' then
    raise exception 'invalid_transition: enrollment % is % not pending_approval', p_enrollment_id, v_enrollment.status using errcode = 'check_violation';
  end if;
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: %', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'reject' and (p_decision_reason is null or length(trim(p_decision_reason)) = 0) then
    raise exception 'reason_required: a reason is required to reject an enrollment request' using errcode = 'check_violation';
  end if;

  if p_decision = 'reject' then
    update app.training_enrollments
    set status = 'cancelled', decided_by = p_actor_label, decided_at = now(), decision_reason = p_decision_reason, cancelled_reason = p_decision_reason, cancelled_at = now()
    where id = p_enrollment_id and record_version = p_expected_version
    returning * into v_enrollment;
  else
    select count(*) into v_enrolled_count from app.training_enrollments where session_id = v_session.id and status = 'enrolled';
    v_status := case when v_enrolled_count < v_session.capacity then 'enrolled' else 'waitlisted' end;
    update app.training_enrollments
    set status = v_status, decided_by = p_actor_label, decided_at = now(), decision_reason = p_decision_reason
    where id = p_enrollment_id and record_version = p_expected_version
    returning * into v_enrollment;
  end if;
  if not found then
    raise exception 'stale_version: concurrent update detected for enrollment %', p_enrollment_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_training_enrollment',
    'app.training_enrollments', v_enrollment.id, 'success', null, null, jsonb_build_object('decision', p_decision, 'status', v_enrollment.status)
  );

  return v_enrollment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.publish_performance_outcome(p_outcome_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_outcomes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_outcome app.performance_outcomes;
begin
  select * into v_outcome from app.performance_outcomes where id = p_outcome_id for update;
  if not found or not app.has_active_tenant_membership(v_outcome.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_outcome_not_found: %', p_outcome_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Approve', v_outcome.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_outcome.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_outcome.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_outcome.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_outcome.status not in ('draft', 'reopened') then
    raise exception 'invalid_transition: outcome % is % -- only draft/reopened outcomes may be published', p_outcome_id, v_outcome.status using errcode = 'check_violation';
  end if;
  if v_outcome.manager_assessment_id is null then
    raise exception 'manager_assessment_missing: outcome % has no submitted manager assessment yet', p_outcome_id using errcode = 'check_violation';
  end if;

  update app.performance_outcomes set status = 'published', published_by = p_actor_label, published_at = now()
  where id = p_outcome_id and record_version = p_expected_version
  returning * into v_outcome;
  if not found then
    raise exception 'stale_version: concurrent update detected for outcome %', p_outcome_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_outcome.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_performance_outcome',
    'app.performance_outcomes', v_outcome.id, 'success', null, null, jsonb_build_object('cycle_id', v_outcome.cycle_id)
  );
  return v_outcome;
end;
$function$;

CREATE OR REPLACE FUNCTION app.publish_performance_template(p_template_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_templates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_template app.performance_templates;
  v_weight_sum numeric;
  v_item_count integer;
begin
  select * into v_template from app.performance_templates where id = p_template_id for update;
  if not found or not app.has_active_tenant_membership(v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Approve', v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_template.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_template.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_template.status <> 'draft' then
    raise exception 'invalid_transition: template % is % not draft', p_template_id, v_template.status using errcode = 'check_violation';
  end if;

  select count(*), coalesce(sum(default_weight), 0) into v_item_count, v_weight_sum from app.performance_template_kpi_items where template_id = p_template_id;
  if v_item_count = 0 then
    raise exception 'template_has_no_items: template % has no KPI items', p_template_id using errcode = 'check_violation';
  end if;
  if v_weight_sum <> v_template.weight_total_required then
    raise exception 'template_weights_incomplete: default weights sum to % but % is required', v_weight_sum, v_template.weight_total_required
      using errcode = 'check_violation';
  end if;

  update app.performance_templates set status = 'published' where id = p_template_id and record_version = p_expected_version
  returning * into v_template;
  if not found then
    raise exception 'stale_version: concurrent update detected for template %', p_template_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_performance_template',
    'app.performance_templates', v_template.id, 'success', null, null, jsonb_build_object('code', v_template.code)
  );

  return v_template;
end;
$function$;

CREATE OR REPLACE FUNCTION app.publish_training_competency(p_competency_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_competencies
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_row app.training_competencies;
begin
  select * into v_row from app.training_competencies where id = p_competency_id for update;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_competency_not_found: %', p_competency_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Approve', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'invalid_transition: competency % is % not draft', p_competency_id, v_row.status using errcode = 'check_violation';
  end if;

  update app.training_competencies set status = 'published' where id = p_competency_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: concurrent update detected for competency %', p_competency_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_training_competency',
    'app.training_competencies', v_row.id, 'success', null, null, jsonb_build_object('code', v_row.code)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.publish_training_course_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_course_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.training_course_versions;
begin
  select * into v_version from app.training_course_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_course_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Approve', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: version % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  -- Exactly one published version per course (decision 2) -- archiving the
  -- prior published version here is idempotent under concurrency (setting
  -- status to 'archived' twice is harmless); the real race (two concurrent
  -- callers both computing the same v_next at create time) is caught by
  -- create_training_course_version's own exception handler, not here.
  update app.training_course_versions set status = 'archived' where course_id = v_version.course_id and status = 'published';

  update app.training_course_versions set status = 'published' where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: concurrent update detected for version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_training_course_version',
    'app.training_course_versions', v_version.id, 'success', null, null, jsonb_build_object('course_id', v_version.course_id, 'version_number', v_version.version_number)
  );

  return v_version;
end;
$function$;

CREATE OR REPLACE FUNCTION app.reassign_performance_reviewer_assignment(p_assignment_id uuid, p_new_assigned_to_employee_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_reviewer_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_old app.performance_reviewer_assignments;
  v_new app.performance_reviewer_assignments;
  v_new_employee app.employees;
begin
  select * into v_old from app.performance_reviewer_assignments where id = p_assignment_id for update;
  if not found or not app.has_active_tenant_membership(v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_reviewer_assignment_not_found: %', p_assignment_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Override', v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_old.status <> 'active' then
    raise exception 'invalid_transition: assignment % is already %', p_assignment_id, v_old.status using errcode = 'check_violation';
  end if;
  if p_new_assigned_to_employee_id = v_old.employee_id then
    raise exception 'invalid_assignee: an employee may not be assigned as their own %', v_old.role using errcode = 'check_violation';
  end if;
  select * into v_new_employee from app.employees where master_record_id = p_new_assigned_to_employee_id and tenant_id = v_old.tenant_id;
  if not found or v_new_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'employee_not_active: % is not an active employee for tenant %', p_new_assigned_to_employee_id, v_old.tenant_id using errcode = 'no_data_found';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to reassign a reviewer assignment' using errcode = 'check_violation';
  end if;

  update app.performance_reviewer_assignments set status = 'reassigned', reassign_reason = p_reason where id = p_assignment_id;

  begin
    insert into app.performance_reviewer_assignments (tenant_id, cycle_id, employee_id, role, assigned_to_employee_id, reassigned_from_assignment_id, assigned_by)
    values (v_old.tenant_id, v_old.cycle_id, v_old.employee_id, v_old.role, p_new_assigned_to_employee_id, v_old.id, p_actor_label)
    returning * into v_new;
  exception
    when unique_violation then
      raise exception 'reviewer_assignment_conflict: this reassignment target already holds an active assignment of this role for this employee'
        using errcode = 'check_violation';
  end;

  -- The whole point of this RPC (decision 5): the OLD assignment, and any
  -- already-submitted assessment tied to it, is NEVER mutated or deleted --
  -- it stays exactly as it was, permanently attributed to the prior
  -- assessor. A brand-new not_started assessment is created for the new
  -- assignee; if the old assessment was still draft/not_started, it is
  -- simply superseded (orphaned under the now-reassigned assignment),
  -- never silently carried over as if the new assessor had written it.
  insert into app.performance_assessments (tenant_id, cycle_id, employee_id, assessment_type, reviewer_assignment_id, assigned_to_employee_id)
  values (v_old.tenant_id, v_old.cycle_id, v_old.employee_id, v_old.role, v_new.id, p_new_assigned_to_employee_id);

  perform app.capture_audit_event(
    v_old.tenant_id, p_actor_auth_user_id, p_actor_label, 'reassign_performance_reviewer_assignment',
    'app.performance_reviewer_assignments', v_new.id, 'success', null, null,
    jsonb_build_object('cycle_id', v_old.cycle_id, 'employee_id', v_old.employee_id, 'old_assignment_id', p_assignment_id, 'role', v_old.role)
  );
  return v_new;
end;
$function$;

CREATE OR REPLACE FUNCTION app.reassign_talent_reviewer(p_assignment_id uuid, p_new_reviewer_employee_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.talent_review_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_old app.talent_review_assignments;
  v_new app.talent_review_assignments;
begin
  select * into v_old from app.talent_review_assignments where id = p_assignment_id for update;
  if not found or not app.has_active_tenant_membership(v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'talent_review_assignment_not_found: %', p_assignment_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_old.status <> 'active' then
    raise exception 'invalid_transition: assignment % is % not active', p_assignment_id, v_old.status using errcode = 'check_violation';
  end if;
  if p_new_reviewer_employee_id = v_old.subject_employee_id then
    raise exception 'invalid_assignee: a reviewer may not be assigned to their own case' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to reassign a talent reviewer' using errcode = 'check_violation';
  end if;

  update app.talent_review_assignments set status = 'reassigned', reassign_reason = p_reason where id = p_assignment_id;

  insert into app.talent_review_assignments (tenant_id, cycle_id, subject_employee_id, reviewer_employee_id, reassigned_from_assignment_id, assigned_by)
  values (v_old.tenant_id, v_old.cycle_id, v_old.subject_employee_id, p_new_reviewer_employee_id, p_assignment_id, p_actor_label)
  returning * into v_new;

  insert into app.talent_reviews (tenant_id, cycle_id, subject_employee_id, assignment_id)
  values (v_old.tenant_id, v_old.cycle_id, v_old.subject_employee_id, v_new.id);

  perform app.capture_audit_event(
    v_old.tenant_id, p_actor_auth_user_id, p_actor_label, 'reassign_talent_reviewer',
    'app.talent_review_assignments', v_new.id, 'success', null, null, jsonb_build_object('old_assignment_id', p_assignment_id, 'subject_employee_id', v_old.subject_employee_id)
  );

  return v_new;
end;
$function$;

CREATE OR REPLACE FUNCTION app.record_performance_goal_progress(p_goal_assignment_id uuid, p_actual_value numeric, p_note text, p_evidence_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_goal_progress_entries
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_goal app.performance_goal_assignments;
  v_employee app.employees;
  v_self app.employees;
  v_file app.files;
  v_entry app.performance_goal_progress_entries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_goal from app.performance_goal_assignments where id = p_goal_assignment_id;
  if not found or not app.has_active_tenant_membership(v_goal.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_goal_assignment_not_found: %', p_goal_assignment_id using errcode = 'no_data_found';
  end if;
  select * into v_employee from app.employees where master_record_id = v_goal.employee_id;
  v_self := app.get_self_employee(v_goal.tenant_id, p_actor_auth_user_id);
  if not (
    (v_self.master_record_id is not null and v_self.master_record_id = v_goal.employee_id)
    or (v_self.master_record_id is not null and v_self.master_record_id = v_employee.manager_employee_id)
    or app.check_performance_authority('Edit', v_goal.tenant_id, p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % may not record progress on this goal', p_actor_auth_user_id using errcode = 'insufficient_privilege';
  end if;
  if v_goal.status <> 'active' then
    raise exception 'invalid_transition: goal % is % not active', p_goal_assignment_id, v_goal.status using errcode = 'check_violation';
  end if;
  if p_evidence_file_id is not null then
    -- Taxonomy C-10: re-validate tenant/scope/scan status at THIS accepting
    -- RPC, never trust the caller''s own upload-time classification.
    select * into v_file from app.files where id = p_evidence_file_id and tenant_id = v_goal.tenant_id;
    if not found then
      raise exception 'evidence_file_not_found: % is not a known file for tenant %', p_evidence_file_id, v_goal.tenant_id using errcode = 'no_data_found';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'evidence_file_not_clean: % has not passed malware scanning', p_evidence_file_id using errcode = 'check_violation';
    end if;
  end if;

  insert into app.performance_goal_progress_entries (tenant_id, goal_assignment_id, employee_id, actual_value, note, evidence_file_id, recorded_by_auth_user_id, recorded_by)
  values (v_goal.tenant_id, p_goal_assignment_id, v_goal.employee_id, p_actual_value, p_note, p_evidence_file_id, p_actor_auth_user_id, p_actor_label)
  returning * into v_entry;

  perform app.capture_audit_event(
    v_goal.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_performance_goal_progress',
    'app.performance_goal_progress_entries', v_entry.id, 'success', null, null, jsonb_build_object('goal_assignment_id', p_goal_assignment_id)
  );
  return v_entry;
end;
$function$;

CREATE OR REPLACE FUNCTION app.record_training_assessment(p_enrollment_id uuid, p_score numeric, p_max_score numeric, p_notes text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_assessments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_enrollment app.training_enrollments;
  v_version app.training_course_versions;
  v_next integer;
  v_row app.training_assessments;
begin
  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id;
  if not found or not app.has_active_tenant_membership(v_enrollment.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_enrollment.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_enrollment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  select * into v_version from app.training_course_versions where id = v_enrollment.course_version_id;
  if not v_version.requires_assessment then
    raise exception 'training_assessment_not_applicable: course version % does not require assessment', v_enrollment.course_version_id using errcode = 'check_violation';
  end if;
  if p_score is null or p_score < 0 or p_max_score is null or p_max_score <= 0 or p_score > p_max_score then
    raise exception 'invalid_score: score must be between 0 and max_score' using errcode = 'check_violation';
  end if;

  select coalesce(max(attempt_number), 0) + 1 into v_next from app.training_assessments where enrollment_id = p_enrollment_id;

  begin
    insert into app.training_assessments (tenant_id, enrollment_id, employee_id, course_version_id, attempt_number, score, max_score, passed, assessed_by, notes)
    values (
      v_enrollment.tenant_id, p_enrollment_id, v_enrollment.employee_id, v_enrollment.course_version_id, v_next, p_score, p_max_score,
      app.compute_training_assessment_passed(p_score, p_max_score, v_version.passing_score), p_actor_label, p_notes
    )
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'training_assessment_attempt_conflict: an attempt was just recorded concurrently for enrollment % -- retry to get the current next attempt number', p_enrollment_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_enrollment.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_training_assessment',
    'app.training_assessments', v_row.id, 'success', null, null, jsonb_build_object('enrollment_id', p_enrollment_id, 'attempt_number', v_next, 'passed', v_row.passed)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.record_training_attendance(p_enrollment_id uuid, p_attended boolean, p_hours_attended numeric, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_enrollment app.training_enrollments;
begin
  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id for update;
  if not found or not app.has_active_tenant_membership(v_enrollment.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_enrollment.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_enrollment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_enrollment.status <> 'enrolled' then
    raise exception 'invalid_transition: enrollment % is % not enrolled', p_enrollment_id, v_enrollment.status using errcode = 'check_violation';
  end if;
  if p_hours_attended is not null and p_hours_attended < 0 then
    raise exception 'invalid_hours: hours_attended must not be negative' using errcode = 'check_violation';
  end if;

  update app.training_enrollments
  set attended = p_attended, hours_attended = p_hours_attended, attendance_recorded_by = p_actor_label, attendance_recorded_at = now()
  where id = p_enrollment_id
  returning * into v_enrollment;

  perform app.capture_audit_event(
    v_enrollment.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_training_attendance',
    'app.training_enrollments', v_enrollment.id, 'success', null, null, jsonb_build_object('attended', p_attended)
  );

  return v_enrollment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.record_training_completion(p_enrollment_id uuid, p_expected_version integer, p_completion_status text, p_notes text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_enrollment app.training_enrollments;
begin
  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id for update;
  if not found or not app.has_active_tenant_membership(v_enrollment.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_enrollment.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_enrollment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_enrollment.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_enrollment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_enrollment.status <> 'enrolled' then
    raise exception 'invalid_transition: enrollment % is % not enrolled', p_enrollment_id, v_enrollment.status using errcode = 'check_violation';
  end if;
  if p_completion_status not in ('completed', 'failed', 'no_show') then
    raise exception 'invalid_completion_status: %', p_completion_status using errcode = 'check_violation';
  end if;

  update app.training_enrollments
  set status = p_completion_status, completion_notes = p_notes, completed_at = now(), completion_recorded_by = p_actor_label
  where id = p_enrollment_id and record_version = p_expected_version
  returning * into v_enrollment;
  if not found then
    raise exception 'stale_version: concurrent update detected for enrollment %', p_enrollment_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_enrollment.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_training_completion',
    'app.training_enrollments', v_enrollment.id, 'success', null, null, jsonb_build_object('status', p_completion_status)
  );

  return v_enrollment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.remove_talent_pool_member(p_member_id uuid, p_expected_version integer, p_removed_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.talent_pool_members
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_row app.talent_pool_members;
begin
  select * into v_row from app.talent_pool_members where id = p_member_id for update;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'talent_pool_member_not_found: %', p_member_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status <> 'active' then
    raise exception 'invalid_transition: member % is % not active', p_member_id, v_row.status using errcode = 'check_violation';
  end if;
  if p_removed_reason is null or length(trim(p_removed_reason)) = 0 then
    raise exception 'reason_required: a reason is required to remove a talent pool member' using errcode = 'check_violation';
  end if;

  update app.talent_pool_members set status = 'removed', removed_reason = p_removed_reason, removed_by = p_actor_label, removed_at = now()
  where id = p_member_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: concurrent update detected for member %', p_member_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_talent_pool_member',
    'app.talent_pool_members', v_row.id, 'success', null, null, jsonb_build_object('pool_id', v_row.pool_id)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.remove_training_course_prerequisite(p_prerequisite_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_row app.training_course_prerequisites;
begin
  select * into v_row from app.training_course_prerequisites where id = p_prerequisite_id;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_course_prerequisite_not_found: %', p_prerequisite_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  delete from app.training_course_prerequisites where id = p_prerequisite_id;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_training_course_prerequisite',
    'app.training_course_prerequisites', p_prerequisite_id, 'success', null, null, jsonb_build_object('course_id', v_row.course_id, 'prerequisite_course_id', v_row.prerequisite_course_id)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION app.renew_training_certificate(p_old_certificate_id uuid, p_certificate_number text, p_issued_at date, p_expiry_date date, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_certificates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_old app.training_certificates;
  v_row app.training_certificates;
begin
  select * into v_old from app.training_certificates where id = p_old_certificate_id;
  if not found or not app.has_active_tenant_membership(v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_certificate_not_found: %', p_old_certificate_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.training_certificates (
    tenant_id, employee_id, course_version_id, external_course_name, provider_id, certificate_number, issued_at, expiry_date,
    source, verification_status, renewed_from_certificate_id, created_by
  ) values (
    v_old.tenant_id, v_old.employee_id, v_old.course_version_id, v_old.external_course_name, v_old.provider_id, p_certificate_number, p_issued_at, p_expiry_date,
    v_old.source, v_old.verification_status, p_old_certificate_id, p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    v_old.tenant_id, p_actor_auth_user_id, p_actor_label, 'renew_training_certificate',
    'app.training_certificates', v_row.id, 'success', null, null, jsonb_build_object('renewed_from_certificate_id', p_old_certificate_id)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.reschedule_training_enrollment(p_enrollment_id uuid, p_new_session_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_enrollment app.training_enrollments;
  v_old_session_id uuid;
  v_first_id uuid;
  v_second_id uuid;
  v_self app.employees;
  v_is_self boolean := false;
  v_new_enrollment app.training_enrollments;
begin
  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id;
  if not found or not app.has_active_tenant_membership(v_enrollment.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;
  v_old_session_id := v_enrollment.session_id;
  if v_old_session_id = p_new_session_id then
    raise exception 'invalid_reschedule: new session must differ from the current session' using errcode = 'check_violation';
  end if;

  v_first_id := least(v_old_session_id, p_new_session_id);
  v_second_id := greatest(v_old_session_id, p_new_session_id);
  perform 1 from app.training_sessions where id = v_first_id for update;
  perform 1 from app.training_sessions where id = v_second_id for update;

  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id for update;

  v_self := app.get_self_employee((select tenant_id from app.training_sessions where id = v_old_session_id), p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_enrollment.employee_id then
    v_is_self := true;
  end if;
  if not v_is_self and not app.check_training_authority('Edit', v_enrollment.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is neither the enrolled employee nor an HRS:Edit holder for tenant %', p_actor_auth_user_id, v_enrollment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_enrollment.status not in ('pending_approval', 'enrolled', 'waitlisted') then
    raise exception 'invalid_transition: enrollment % is % -- only an active enrollment may be rescheduled', p_enrollment_id, v_enrollment.status using errcode = 'check_violation';
  end if;

  update app.training_enrollments set status = 'cancelled', cancelled_reason = 'rescheduled', cancelled_at = now()
  where id = p_enrollment_id;

  v_new_enrollment := app._enroll_employee_in_training_session_internal(p_new_session_id, v_enrollment.employee_id, v_enrollment.enrollment_source, p_actor_label);
  update app.training_enrollments set rescheduled_from_enrollment_id = p_enrollment_id where id = v_new_enrollment.id
  returning * into v_new_enrollment;

  perform app.capture_audit_event(
    v_enrollment.tenant_id, p_actor_auth_user_id, p_actor_label, 'reschedule_training_enrollment',
    'app.training_enrollments', v_new_enrollment.id, 'success', null, null, jsonb_build_object('old_enrollment_id', p_enrollment_id, 'old_session_id', v_old_session_id, 'new_session_id', p_new_session_id)
  );

  return v_new_enrollment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.revoke_training_certificate(p_certificate_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_certificates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cert app.training_certificates;
begin
  select * into v_cert from app.training_certificates where id = p_certificate_id for update;
  if not found or not app.has_active_tenant_membership(v_cert.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_certificate_not_found: %', p_certificate_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_cert.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_cert.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cert.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_cert.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_cert.status = 'revoked' then
    raise exception 'invalid_transition: certificate % is already revoked', p_certificate_id using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to revoke a certificate' using errcode = 'check_violation';
  end if;

  update app.training_certificates set status = 'revoked', revoked_reason = p_reason, revoked_at = now(), revoked_by = p_actor_label
  where id = p_certificate_id and record_version = p_expected_version
  returning * into v_cert;
  if not found then
    raise exception 'stale_version: concurrent update detected for certificate %', p_certificate_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cert.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_training_certificate',
    'app.training_certificates', v_cert.id, 'success', null, null, jsonb_build_object('status', 'revoked')
  );

  return v_cert;
end;
$function$;

CREATE OR REPLACE FUNCTION app.transition_talent_review_cycle_status(p_cycle_id uuid, p_expected_version integer, p_target_status text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.talent_review_cycles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cycle app.talent_review_cycles;
  v_legal boolean;
begin
  select * into v_cycle from app.talent_review_cycles where id = p_cycle_id for update;
  if not found or not app.has_active_tenant_membership(v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'talent_review_cycle_not_found: %', p_cycle_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_cycle.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cycle.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_cycle.record_version
      using errcode = 'serialization_failure';
  end if;

  v_legal := case v_cycle.status when 'draft' then p_target_status = 'active' when 'active' then p_target_status = 'closed' else false end;
  if not v_legal then
    raise exception 'invalid_transition: cycle % cannot move from % to %', p_cycle_id, v_cycle.status, p_target_status using errcode = 'check_violation';
  end if;

  update app.talent_review_cycles set status = p_target_status where id = p_cycle_id and record_version = p_expected_version
  returning * into v_cycle;
  if not found then
    raise exception 'stale_version: concurrent update detected for cycle %', p_cycle_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_talent_review_cycle_status',
    'app.talent_review_cycles', v_cycle.id, 'success', null, null, jsonb_build_object('status', v_cycle.status)
  );

  return v_cycle;
end;
$function$;

CREATE OR REPLACE FUNCTION app.update_training_provider_status(p_provider_id uuid, p_expected_version integer, p_status text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_providers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_row app.training_providers;
begin
  select * into v_row from app.training_providers where id = p_provider_id for update;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_provider_not_found: %', p_provider_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_status not in ('active', 'inactive') then
    raise exception 'invalid_status: %', p_status using errcode = 'check_violation';
  end if;

  update app.training_providers set status = p_status where id = p_provider_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: concurrent update detected for provider %', p_provider_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_training_provider_status',
    'app.training_providers', v_row.id, 'success', null, null, jsonb_build_object('status', p_status)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.verify_training_certificate(p_certificate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_certificates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cert app.training_certificates;
begin
  select * into v_cert from app.training_certificates where id = p_certificate_id for update;
  if not found or not app.has_active_tenant_membership(v_cert.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_certificate_not_found: %', p_certificate_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Approve', v_cert.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_cert.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cert.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_cert.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_cert.verification_status <> 'unverified' then
    raise exception 'invalid_transition: certificate % is already %', p_certificate_id, v_cert.verification_status using errcode = 'check_violation';
  end if;

  update app.training_certificates set verification_status = 'verified' where id = p_certificate_id and record_version = p_expected_version
  returning * into v_cert;
  if not found then
    raise exception 'stale_version: concurrent update detected for certificate %', p_certificate_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cert.tenant_id, p_actor_auth_user_id, p_actor_label, 'verify_training_certificate',
    'app.training_certificates', v_cert.id, 'success', null, null, jsonb_build_object('verification_status', 'verified')
  );

  return v_cert;
end;
$function$;

