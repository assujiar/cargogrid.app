-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Part 2a of 5 of a representative repository-wide fix pass (HRIS, functions 1-20 of 41).
-- See 20260902100000_harden_tenant_id_disclosure_finance.sql for the full rationale
-- (same fix pattern, same repository-wide precedent, applied here to HRIS).
-- Every function below is CREATE OR REPLACE against its CURRENT, live body -- signatures
-- are unchanged throughout, so grants are unaffected.

CREATE OR REPLACE FUNCTION app.add_performance_template_kpi_item(p_template_id uuid, p_kpi_definition_id uuid, p_default_weight numeric, p_is_required boolean, p_sort_order integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_template_kpi_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_template app.performance_templates;
  v_item app.performance_template_kpi_items;
begin
  select * into v_template from app.performance_templates where id = p_template_id for update;
  if not found or not app.has_active_tenant_membership(v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Edit', v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_template.status <> 'draft' then
    raise exception 'template_not_draft: template % is % -- KPI items may only be added while draft', p_template_id, v_template.status
      using errcode = 'check_violation';
  end if;
  if p_default_weight is null or p_default_weight <= 0 or p_default_weight > 100 then
    raise exception 'invalid_weight: default_weight must be greater than 0 and at most 100' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.performance_kpi_definitions k where k.id = p_kpi_definition_id and k.tenant_id = v_template.tenant_id) then
    raise exception 'performance_kpi_definition_not_found: %', p_kpi_definition_id using errcode = 'no_data_found';
  end if;

  begin
    insert into app.performance_template_kpi_items (template_id, tenant_id, kpi_definition_id, default_weight, is_required, sort_order)
    values (p_template_id, v_template.tenant_id, p_kpi_definition_id, p_default_weight, coalesce(p_is_required, true), coalesce(p_sort_order, 0))
    returning * into v_item;
  exception
    when unique_violation then
      raise exception 'performance_template_kpi_item_conflict: KPI % is already on template %', p_kpi_definition_id, p_template_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_performance_template_kpi_item',
    'app.performance_template_kpi_items', v_item.id, 'success', null, null, jsonb_build_object('template_id', p_template_id, 'kpi_definition_id', p_kpi_definition_id)
  );

  return v_item;
end;
$function$;

CREATE OR REPLACE FUNCTION app.add_talent_pool_member(p_pool_id uuid, p_employee_id uuid, p_added_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.talent_pool_members
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_pool app.talent_pools;
  v_row app.talent_pool_members;
begin
  select * into v_pool from app.talent_pools where id = p_pool_id;
  if not found or not app.has_active_tenant_membership(v_pool.tenant_id, p_actor_auth_user_id) then
    raise exception 'talent_pool_not_found: %', p_pool_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_pool.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_pool.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_pool.status <> 'active' then
    raise exception 'talent_pool_not_active: pool % is % not active', p_pool_id, v_pool.status using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.employees e where e.master_record_id = p_employee_id and e.tenant_id = v_pool.tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;
  if p_added_reason is null or length(trim(p_added_reason)) = 0 then
    raise exception 'reason_required: a reason is required to add a talent pool member' using errcode = 'check_violation';
  end if;

  begin
    insert into app.talent_pool_members (tenant_id, pool_id, employee_id, added_reason, added_by)
    values (v_pool.tenant_id, p_pool_id, p_employee_id, p_added_reason, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'talent_pool_member_conflict: employee % is already an active member of pool %', p_employee_id, p_pool_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_pool.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_talent_pool_member',
    'app.talent_pool_members', v_row.id, 'success', null, null, jsonb_build_object('pool_id', p_pool_id, 'employee_id', p_employee_id)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.add_training_course_competency(p_course_id uuid, p_competency_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_course_competencies
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_course app.training_courses;
  v_row app.training_course_competencies;
begin
  select * into v_course from app.training_courses where id = p_course_id;
  if not found or not app.has_active_tenant_membership(v_course.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_course_not_found: %', p_course_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_course.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_course.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from app.training_competencies c where c.id = p_competency_id and c.tenant_id = v_course.tenant_id) then
    raise exception 'training_competency_not_found: %', p_competency_id using errcode = 'no_data_found';
  end if;

  begin
    insert into app.training_course_competencies (course_id, tenant_id, competency_id, created_by)
    values (p_course_id, v_course.tenant_id, p_competency_id, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.training_course_competencies where course_id = p_course_id and competency_id = p_competency_id;
      return v_row;
  end;

  perform app.capture_audit_event(
    v_course.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_training_course_competency',
    'app.training_course_competencies', p_course_id, 'success', null, null, jsonb_build_object('course_id', p_course_id, 'competency_id', p_competency_id)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.add_training_course_prerequisite(p_course_id uuid, p_prerequisite_course_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_course_prerequisites
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_course app.training_courses;
  v_row app.training_course_prerequisites;
begin
  select * into v_course from app.training_courses where id = p_course_id;
  if not found or not app.has_active_tenant_membership(v_course.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_course_not_found: %', p_course_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_course.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_course.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_course_id = p_prerequisite_course_id then
    raise exception 'invalid_prerequisite: a course cannot require itself' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.training_courses c where c.id = p_prerequisite_course_id and c.tenant_id = v_course.tenant_id) then
    raise exception 'training_course_not_found: %', p_prerequisite_course_id using errcode = 'no_data_found';
  end if;

  begin
    insert into app.training_course_prerequisites (tenant_id, course_id, prerequisite_course_id, created_by)
    values (v_course.tenant_id, p_course_id, p_prerequisite_course_id, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.training_course_prerequisites where course_id = p_course_id and prerequisite_course_id = p_prerequisite_course_id;
      return v_row;
  end;

  perform app.capture_audit_event(
    v_course.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_training_course_prerequisite',
    'app.training_course_prerequisites', v_row.id, 'success', null, null, jsonb_build_object('course_id', p_course_id, 'prerequisite_course_id', p_prerequisite_course_id)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.advance_performance_cycle_stage(p_cycle_id uuid, p_expected_version integer, p_target_status text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_cycles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cycle app.performance_cycles;
  v_legal boolean;
begin
  select * into v_cycle from app.performance_cycles where id = p_cycle_id for update;
  if not found or not app.has_active_tenant_membership(v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_cycle_not_found: %', p_cycle_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Approve', v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_cycle.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cycle.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_cycle.record_version
      using errcode = 'serialization_failure';
  end if;

  v_legal := case v_cycle.status
    when 'draft' then p_target_status = 'goal_setting_open'
    when 'goal_setting_open' then p_target_status = 'self_assessment_open'
    when 'self_assessment_open' then p_target_status = 'manager_assessment_open'
    when 'manager_assessment_open' then p_target_status = 'calibration'
    when 'calibration' then p_target_status = 'acknowledgement'
    when 'acknowledgement' then p_target_status = 'closed'
    else false
  end;
  if not v_legal then
    raise exception 'invalid_transition: cycle % cannot move from % to %', p_cycle_id, v_cycle.status, p_target_status using errcode = 'check_violation';
  end if;

  update app.performance_cycles set status = p_target_status where id = p_cycle_id and record_version = p_expected_version
  returning * into v_cycle;
  if not found then
    raise exception 'stale_version: concurrent update detected for cycle %', p_cycle_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'advance_performance_cycle_stage',
    'app.performance_cycles', v_cycle.id, 'success', null, null, jsonb_build_object('status', v_cycle.status)
  );

  return v_cycle;
end;
$function$;

CREATE OR REPLACE FUNCTION app.archive_performance_kpi_definition_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_kpi_definition_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.performance_kpi_definition_versions;
begin
  select * into v_version from app.performance_kpi_definition_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_kpi_definition_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'active' then
    raise exception 'invalid_transition: version % is % not active', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  update app.performance_kpi_definition_versions set status = 'archived' where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: concurrent update detected for version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_performance_kpi_definition_version',
    'app.performance_kpi_definition_versions', v_version.id, 'success', null, null, jsonb_build_object('kpi_definition_id', v_version.kpi_definition_id)
  );

  return v_version;
end;
$function$;

CREATE OR REPLACE FUNCTION app.archive_performance_template(p_template_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_templates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_template app.performance_templates;
begin
  select * into v_template from app.performance_templates where id = p_template_id for update;
  if not found or not app.has_active_tenant_membership(v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Edit', v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_template.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_template.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_template.status = 'archived' then
    raise exception 'invalid_transition: template % is already archived', p_template_id using errcode = 'check_violation';
  end if;

  update app.performance_templates set status = 'archived' where id = p_template_id and record_version = p_expected_version
  returning * into v_template;
  if not found then
    raise exception 'stale_version: concurrent update detected for template %', p_template_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_performance_template',
    'app.performance_templates', v_template.id, 'success', null, null, null
  );

  return v_template;
end;
$function$;

CREATE OR REPLACE FUNCTION app.archive_talent_pool(p_pool_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.talent_pools
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_row app.talent_pools;
begin
  select * into v_row from app.talent_pools where id = p_pool_id for update;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'talent_pool_not_found: %', p_pool_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status = 'archived' then
    raise exception 'invalid_transition: pool % is already archived', p_pool_id using errcode = 'check_violation';
  end if;

  update app.talent_pools set status = 'archived' where id = p_pool_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: concurrent update detected for pool %', p_pool_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_talent_pool',
    'app.talent_pools', v_row.id, 'success', null, null, jsonb_build_object('name', v_row.name)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.archive_training_competency(p_competency_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not app.check_training_authority('Edit', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status = 'archived' then
    raise exception 'invalid_transition: competency % is already archived', p_competency_id using errcode = 'check_violation';
  end if;

  update app.training_competencies set status = 'archived' where id = p_competency_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: concurrent update detected for competency %', p_competency_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_training_competency',
    'app.training_competencies', v_row.id, 'success', null, null, jsonb_build_object('code', v_row.code)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.archive_training_course_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not app.check_training_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status = 'archived' then
    raise exception 'invalid_transition: version % is already archived', p_version_id using errcode = 'check_violation';
  end if;

  update app.training_course_versions set status = 'archived' where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: concurrent update detected for version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_training_course_version',
    'app.training_course_versions', v_version.id, 'success', null, null, jsonb_build_object('course_id', v_version.course_id)
  );

  return v_version;
end;
$function$;

CREATE OR REPLACE FUNCTION app.assign_performance_goal(p_cycle_id uuid, p_employee_id uuid, p_kpi_definition_id uuid, p_weight numeric, p_target_value numeric, p_target_unit text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_goal_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cycle app.performance_cycles;
  v_employee app.employees;
  v_self app.employees;
  v_version app.performance_kpi_definition_versions;
  v_existing app.performance_goal_assignments;
  v_self_assessment app.performance_assessments;
  v_goal app.performance_goal_assignments;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_cycle from app.performance_cycles where id = p_cycle_id for update;
  if not found or not app.has_active_tenant_membership(v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_cycle_not_found: %', p_cycle_id using errcode = 'no_data_found';
  end if;
  select * into v_employee from app.employees where master_record_id = p_employee_id and tenant_id = v_cycle.tenant_id;
  if not found or v_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'employee_not_active: % is not an active employee for tenant %', p_employee_id, v_cycle.tenant_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_cycle.tenant_id, p_actor_auth_user_id);
  if not (
    app.check_performance_authority('Edit', v_cycle.tenant_id, p_actor_auth_user_id)
    or (v_self.master_record_id is not null and v_self.master_record_id = v_employee.manager_employee_id)
  ) then
    raise exception 'insufficient_authority: identity % may not assign goals to employee %', p_actor_auth_user_id, p_employee_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cycle.status not in ('goal_setting_open', 'self_assessment_open') then
    raise exception 'invalid_cycle_stage: cycle % is % -- goal assignment is not open', p_cycle_id, v_cycle.status using errcode = 'check_violation';
  end if;
  if p_weight is null or p_weight <= 0 or p_weight > 100 then
    raise exception 'invalid_weight: weight must be greater than 0 and at most 100' using errcode = 'check_violation';
  end if;

  select * into v_version from app.performance_kpi_definition_versions
    where kpi_definition_id = p_kpi_definition_id and tenant_id = v_cycle.tenant_id and status = 'active'
    order by version_number desc limit 1;
  if not found then
    raise exception 'kpi_version_not_found: no active KPI definition version exists for KPI % in tenant %', p_kpi_definition_id, v_cycle.tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_version.scoring_method = 'target_ratio' and p_target_value is null then
    raise exception 'target_value_required: this KPI''s target_ratio scoring method requires a target value' using errcode = 'check_violation';
  end if;

  perform app._ensure_performance_self_assessment(p_cycle_id, p_employee_id);
  perform app._ensure_performance_manager_assignment(p_cycle_id, p_employee_id, p_actor_label);

  -- Lock guard (section 22 "mid-cycle goal revision" is legal only BEFORE
  -- the employee''s own self assessment is submitted -- once submitted,
  -- goals are frozen for scoring integrity).
  select * into v_self_assessment from app.performance_assessments where cycle_id = p_cycle_id and employee_id = p_employee_id and assessment_type = 'self';
  if v_self_assessment.status = 'submitted' then
    raise exception 'goals_locked: employee %''s self assessment for cycle % is already submitted -- goals are frozen', p_employee_id, p_cycle_id
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.performance_goal_assignments where cycle_id = p_cycle_id and employee_id = p_employee_id and kpi_definition_id = p_kpi_definition_id for update;
  if found then
    update app.performance_goal_assignments set
      kpi_version_id = v_version.id, weight = p_weight, target_value = p_target_value, target_unit = p_target_unit,
      status = 'active', na_reason = null
    where id = v_existing.id
    returning * into v_goal;
  else
    begin
      insert into app.performance_goal_assignments (tenant_id, cycle_id, employee_id, kpi_definition_id, kpi_version_id, weight, target_value, target_unit, assigned_by, created_by)
      values (v_cycle.tenant_id, p_cycle_id, p_employee_id, p_kpi_definition_id, v_version.id, p_weight, p_target_value, p_target_unit, p_actor_label, p_actor_label)
      returning * into v_goal;
    exception
      when unique_violation then
        raise exception 'goal_assignment_conflict: this KPI was just assigned concurrently for this employee and cycle -- retry to update it'
          using errcode = 'check_violation';
    end;
  end if;

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_performance_goal',
    'app.performance_goal_assignments', v_goal.id, 'success', null, null,
    jsonb_build_object('cycle_id', p_cycle_id, 'employee_id', p_employee_id, 'kpi_definition_id', p_kpi_definition_id)
  );

  return v_goal;
end;
$function$;

CREATE OR REPLACE FUNCTION app.assign_performance_reviewer(p_cycle_id uuid, p_employee_id uuid, p_role text, p_assigned_to_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_reviewer_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cycle app.performance_cycles;
  v_target app.employees;
  v_assessor app.employees;
  v_assignment app.performance_reviewer_assignments;
begin
  select * into v_cycle from app.performance_cycles where id = p_cycle_id;
  if not found or not app.has_active_tenant_membership(v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_cycle_not_found: %', p_cycle_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Edit', v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_cycle.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_role not in ('manager', 'reviewer') then
    raise exception 'invalid_role: % must be manager or reviewer', p_role using errcode = 'check_violation';
  end if;
  if p_assigned_to_employee_id = p_employee_id then
    raise exception 'invalid_assignee: an employee may not be assigned as their own %', p_role using errcode = 'check_violation';
  end if;
  select * into v_target from app.employees where master_record_id = p_employee_id and tenant_id = v_cycle.tenant_id;
  if not found or v_target.lifecycle_status in ('terminated', 'archived') then
    raise exception 'employee_not_active: % is not an active employee for tenant %', p_employee_id, v_cycle.tenant_id using errcode = 'no_data_found';
  end if;
  select * into v_assessor from app.employees where master_record_id = p_assigned_to_employee_id and tenant_id = v_cycle.tenant_id;
  if not found or v_assessor.lifecycle_status in ('terminated', 'archived') then
    raise exception 'employee_not_active: % is not an active employee for tenant %', p_assigned_to_employee_id, v_cycle.tenant_id using errcode = 'no_data_found';
  end if;

  if p_role = 'manager' and exists (
    select 1 from app.performance_reviewer_assignments where cycle_id = p_cycle_id and employee_id = p_employee_id and role = 'manager' and status = 'active'
  ) then
    raise exception 'manager_assignment_exists: employee % already has an active manager assignment for cycle % -- use app.reassign_performance_reviewer_assignment', p_employee_id, p_cycle_id
      using errcode = 'check_violation';
  end if;

  perform app._ensure_performance_self_assessment(p_cycle_id, p_employee_id);

  begin
    insert into app.performance_reviewer_assignments (tenant_id, cycle_id, employee_id, role, assigned_to_employee_id, assigned_by)
    values (v_cycle.tenant_id, p_cycle_id, p_employee_id, p_role, p_assigned_to_employee_id, p_actor_label)
    returning * into v_assignment;
  exception
    when unique_violation then
      raise exception 'reviewer_assignment_conflict: this assignment already exists or was just created concurrently' using errcode = 'check_violation';
  end;

  insert into app.performance_assessments (tenant_id, cycle_id, employee_id, assessment_type, reviewer_assignment_id, assigned_to_employee_id)
  values (v_cycle.tenant_id, p_cycle_id, p_employee_id, p_role, v_assignment.id, p_assigned_to_employee_id);

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_performance_reviewer',
    'app.performance_reviewer_assignments', v_assignment.id, 'success', null, null,
    jsonb_build_object('cycle_id', p_cycle_id, 'employee_id', p_employee_id, 'role', p_role)
  );
  return v_assignment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.assign_talent_reviewer(p_cycle_id uuid, p_subject_employee_id uuid, p_reviewer_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.talent_review_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cycle app.talent_review_cycles;
  v_row app.talent_review_assignments;
begin
  select * into v_cycle from app.talent_review_cycles where id = p_cycle_id;
  if not found or not app.has_active_tenant_membership(v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'talent_review_cycle_not_found: %', p_cycle_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_cycle.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cycle.status = 'closed' then
    raise exception 'talent_review_cycle_closed: cycle % is closed', p_cycle_id using errcode = 'check_violation';
  end if;
  if p_reviewer_employee_id = p_subject_employee_id then
    raise exception 'invalid_assignee: a reviewer may not be assigned to their own case' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.employees e where e.master_record_id = p_subject_employee_id and e.tenant_id = v_cycle.tenant_id) then
    raise exception 'employee_not_found: %', p_subject_employee_id using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.employees e where e.master_record_id = p_reviewer_employee_id and e.tenant_id = v_cycle.tenant_id) then
    raise exception 'employee_not_found: %', p_reviewer_employee_id using errcode = 'no_data_found';
  end if;

  begin
    insert into app.talent_review_assignments (tenant_id, cycle_id, subject_employee_id, reviewer_employee_id, assigned_by)
    values (v_cycle.tenant_id, p_cycle_id, p_subject_employee_id, p_reviewer_employee_id, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'talent_review_assignment_conflict: subject % already has an active reviewer assignment in cycle %', p_subject_employee_id, p_cycle_id
        using errcode = 'check_violation';
  end;

  insert into app.talent_reviews (tenant_id, cycle_id, subject_employee_id, assignment_id)
  values (v_cycle.tenant_id, p_cycle_id, p_subject_employee_id, v_row.id);

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_talent_reviewer',
    'app.talent_review_assignments', v_row.id, 'success', null, null, jsonb_build_object('cycle_id', p_cycle_id, 'subject_employee_id', p_subject_employee_id)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.attach_training_certificate_evidence(p_certificate_id uuid, p_expected_version integer, p_evidence_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_certificates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cert app.training_certificates;
  v_file app.files;
begin
  select * into v_cert from app.training_certificates where id = p_certificate_id for update;
  if not found or not app.has_active_tenant_membership(v_cert.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_certificate_not_found: %', p_certificate_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_cert.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_cert.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cert.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_cert.record_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_file from app.files where id = p_evidence_file_id;
  if not found or v_file.tenant_id <> v_cert.tenant_id or v_file.record_type <> 'training_certificate' or v_file.record_id <> p_certificate_id then
    raise exception 'evidence_file_not_found: file % is not a valid evidence file for certificate %', p_evidence_file_id, p_certificate_id using errcode = 'no_data_found';
  end if;
  if v_file.malware_scan_status = 'infected' then
    raise exception 'evidence_file_infected: file % failed malware scanning and cannot be attached', p_evidence_file_id using errcode = 'check_violation';
  end if;
  if v_file.malware_scan_status <> 'clean' then
    raise exception 'evidence_file_not_scanned: file % has not cleared malware scanning (status %)', p_evidence_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;

  update app.training_certificates set evidence_file_id = p_evidence_file_id where id = p_certificate_id and record_version = p_expected_version
  returning * into v_cert;
  if not found then
    raise exception 'stale_version: concurrent update detected for certificate %', p_certificate_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cert.tenant_id, p_actor_auth_user_id, p_actor_label, 'attach_training_certificate_evidence',
    'app.training_certificates', v_cert.id, 'success', null, null, jsonb_build_object('evidence_file_id', p_evidence_file_id)
  );

  return v_cert;
end;
$function$;

CREATE OR REPLACE FUNCTION app.calibrate_performance_outcome_score(p_outcome_id uuid, p_expected_version integer, p_adjusted_score numeric, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_outcomes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_outcome app.performance_outcomes;
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_outcome from app.performance_outcomes where id = p_outcome_id for update;
  if not found or not app.has_active_tenant_membership(v_outcome.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_outcome_not_found: %', p_outcome_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Override', v_outcome.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_outcome.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  -- Structural self-calibration block (decision 4) -- an actor may never
  -- calibrate their own outcome, even while separately holding HRS:Override.
  v_self := app.get_self_employee(v_outcome.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_outcome.employee_id then
    raise exception 'self_calibration_not_permitted: an actor may not calibrate their own outcome' using errcode = 'insufficient_privilege';
  end if;
  if v_outcome.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_outcome.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_outcome.status not in ('draft', 'published', 'reopened') then
    raise exception 'invalid_transition: outcome % is % -- calibration is not permitted in this status', p_outcome_id, v_outcome.status using errcode = 'check_violation';
  end if;
  if p_adjusted_score is null or p_adjusted_score < 0 or p_adjusted_score > 100 then
    raise exception 'invalid_adjusted_score: adjusted score must be between 0 and 100' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to calibrate an outcome score' using errcode = 'check_violation';
  end if;

  insert into app.performance_calibration_adjustments (tenant_id, outcome_id, previous_score, adjusted_score, adjustment_reason, calibrated_by, calibrated_by_auth_user_id)
  values (v_outcome.tenant_id, p_outcome_id, coalesce(v_outcome.calibrated_score, v_outcome.baseline_score), round(p_adjusted_score, 3), p_reason, p_actor_label, p_actor_auth_user_id);

  update app.performance_outcomes set calibrated_score = round(p_adjusted_score, 3), final_score = round(p_adjusted_score, 3)
  where id = p_outcome_id and record_version = p_expected_version
  returning * into v_outcome;
  if not found then
    raise exception 'stale_version: concurrent update detected for outcome %', p_outcome_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_outcome.tenant_id, p_actor_auth_user_id, p_actor_label, 'calibrate_performance_outcome_score',
    'app.performance_outcomes', v_outcome.id, 'success', null, null, jsonb_build_object('outcome_id', p_outcome_id)
  );

  return v_outcome;
end;
$function$;

CREATE OR REPLACE FUNCTION app.cancel_performance_cycle(p_cycle_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_cycles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_cycle app.performance_cycles;
begin
  select * into v_cycle from app.performance_cycles where id = p_cycle_id for update;
  if not found or not app.has_active_tenant_membership(v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_cycle_not_found: %', p_cycle_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Override', v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_cycle.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cycle.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_cycle.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_cycle.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cycle % is already %', p_cycle_id, v_cycle.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to cancel a performance cycle' using errcode = 'check_violation';
  end if;

  update app.performance_cycles set status = 'cancelled', cancel_reason = p_reason where id = p_cycle_id and record_version = p_expected_version
  returning * into v_cycle;
  if not found then
    raise exception 'stale_version: concurrent update detected for cycle %', p_cycle_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_performance_cycle',
    'app.performance_cycles', v_cycle.id, 'success', null, null, jsonb_build_object('status', v_cycle.status)
  );

  return v_cycle;
end;
$function$;

CREATE OR REPLACE FUNCTION app.cancel_training_enrollment(p_enrollment_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_enrollment app.training_enrollments;
  v_session app.training_sessions;
  v_self app.employees;
  v_next_waitlisted app.training_enrollments;
  v_is_self boolean := false;
begin
  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id;
  if not found then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.training_sessions where id = v_enrollment.session_id for update;
  if not app.has_active_tenant_membership(v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_session.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_enrollment.employee_id then
    v_is_self := true;
  end if;
  if not v_is_self and not app.check_training_authority('Edit', v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is neither the enrolled employee nor an HRS:Edit holder for tenant %', p_actor_auth_user_id, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_enrollment.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_enrollment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_enrollment.status not in ('pending_approval', 'enrolled', 'waitlisted') then
    raise exception 'invalid_transition: enrollment % is % -- only an active enrollment may be cancelled', p_enrollment_id, v_enrollment.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to cancel an enrollment' using errcode = 'check_violation';
  end if;

  update app.training_enrollments set status = 'cancelled', cancelled_reason = p_reason, cancelled_at = now()
  where id = p_enrollment_id and record_version = p_expected_version
  returning * into v_enrollment;
  if not found then
    raise exception 'stale_version: concurrent update detected for enrollment %', p_enrollment_id using errcode = 'serialization_failure';
  end if;

  -- A capacity slot freed up -- promote the earliest waitlisted enrollee,
  -- still under the SAME session lock this function already holds.
  if v_enrollment.status = 'cancelled' then
    select * into v_next_waitlisted from app.training_enrollments
    where session_id = v_session.id and status = 'waitlisted'
    order by created_at asc
    limit 1
    for update;
    if found then
      update app.training_enrollments set status = 'enrolled' where id = v_next_waitlisted.id;
      perform app.capture_audit_event(
        v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'promote_training_enrollment_from_waitlist',
        'app.training_enrollments', v_next_waitlisted.id, 'success', null, null, jsonb_build_object('session_id', v_session.id)
      );
    end if;
  end if;

  perform app.capture_audit_event(
    v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_training_enrollment',
    'app.training_enrollments', v_enrollment.id, 'success', null, null, jsonb_build_object('session_id', v_session.id)
  );

  return v_enrollment;
end;
$function$;

CREATE OR REPLACE FUNCTION app.cancel_training_session(p_session_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_session app.training_sessions;
  v_enrollment record;
  v_cancelled_count integer := 0;
begin
  select * into v_session from app.training_sessions where id = p_session_id for update;
  if not found or not app.has_active_tenant_membership(v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_session_not_found: %', p_session_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_session.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_session.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_session.status = 'cancelled' then
    raise exception 'invalid_transition: session % is already cancelled', p_session_id using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to cancel a training session' using errcode = 'check_violation';
  end if;

  for v_enrollment in
    select * from app.training_enrollments where session_id = p_session_id and status in ('pending_approval', 'enrolled', 'waitlisted') order by id for update
  loop
    update app.training_enrollments
    set status = 'cancelled', cancelled_reason = 'session_cancelled: ' || p_reason, cancelled_at = now()
    where id = v_enrollment.id;
    v_cancelled_count := v_cancelled_count + 1;
  end loop;

  update app.training_sessions set status = 'cancelled', cancel_reason = p_reason where id = p_session_id and record_version = p_expected_version
  returning * into v_session;
  if not found then
    raise exception 'stale_version: concurrent update detected for session %', p_session_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_training_session',
    'app.training_sessions', v_session.id, 'success', null, null, jsonb_build_object('cancelled_enrollment_count', v_cancelled_count)
  );

  return v_session;
end;
$function$;

CREATE OR REPLACE FUNCTION app.create_performance_kpi_definition_version(p_kpi_definition_id uuid, p_scoring_method text, p_target_direction text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.performance_kpi_definition_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_kpi app.performance_kpi_definitions;
  v_next integer;
  v_version app.performance_kpi_definition_versions;
begin
  select * into v_kpi from app.performance_kpi_definitions where id = p_kpi_definition_id;
  if not found or not app.has_active_tenant_membership(v_kpi.tenant_id, p_actor_auth_user_id) then
    raise exception 'performance_kpi_definition_not_found: %', p_kpi_definition_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Edit', v_kpi.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_kpi.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_scoring_method not in ('target_ratio', 'milestone_percent', 'qualitative_scale') then
    raise exception 'invalid_scoring_method: %', p_scoring_method using errcode = 'check_violation';
  end if;
  if p_scoring_method = 'target_ratio' and p_target_direction not in ('higher_is_better', 'lower_is_better') then
    raise exception 'invalid_target_direction: target_ratio requires higher_is_better or lower_is_better' using errcode = 'check_violation';
  end if;
  if p_scoring_method <> 'target_ratio' and p_target_direction is not null then
    raise exception 'target_direction_not_applicable: % does not use target_direction', p_scoring_method using errcode = 'check_violation';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next from app.performance_kpi_definition_versions where kpi_definition_id = p_kpi_definition_id;

  -- Exactly one active version per KPI (decision 1) -- archiving the prior
  -- active version here is idempotent under concurrency (setting status to
  -- 'archived' twice is harmless); the real race (two concurrent callers
  -- both computing the same v_next) is caught by the exception handler
  -- below, not by this UPDATE.
  update app.performance_kpi_definition_versions set status = 'archived' where kpi_definition_id = p_kpi_definition_id and status = 'active';

  begin
    insert into app.performance_kpi_definition_versions (kpi_definition_id, tenant_id, version_number, status, scoring_method, target_direction, created_by)
    values (p_kpi_definition_id, v_kpi.tenant_id, v_next, 'active', p_scoring_method, p_target_direction, p_actor_label)
    returning * into v_version;
  exception
    when unique_violation then
      raise exception 'performance_kpi_definition_version_conflict: a version was just created concurrently for KPI % -- retry to get the current next version number', p_kpi_definition_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_kpi.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_performance_kpi_definition_version',
    'app.performance_kpi_definition_versions', v_version.id, 'success', null, null, jsonb_build_object('kpi_definition_id', p_kpi_definition_id, 'version_number', v_next)
  );

  return v_version;
end;
$function$;

CREATE OR REPLACE FUNCTION app.create_training_course_version(p_course_id uuid, p_description text, p_delivery_mode text, p_duration_hours numeric, p_is_mandatory boolean, p_requires_enrollment_approval boolean, p_requires_assessment boolean, p_passing_score numeric, p_issues_certificate boolean, p_certificate_validity_months integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.training_course_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_course app.training_courses;
  v_next integer;
  v_version app.training_course_versions;
begin
  select * into v_course from app.training_courses where id = p_course_id;
  if not found or not app.has_active_tenant_membership(v_course.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_course_not_found: %', p_course_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_course.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_course.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_delivery_mode not in ('in_person', 'virtual', 'e_learning', 'blended') then
    raise exception 'invalid_delivery_mode: %', p_delivery_mode using errcode = 'check_violation';
  end if;
  if coalesce(p_requires_assessment, false) and p_passing_score is null then
    raise exception 'passing_score_required: requires_assessment courses need a passing_score' using errcode = 'check_violation';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next from app.training_course_versions where course_id = p_course_id;

  begin
    insert into app.training_course_versions (
      course_id, tenant_id, version_number, description, delivery_mode, duration_hours, is_mandatory,
      requires_enrollment_approval, requires_assessment, passing_score, issues_certificate, certificate_validity_months, created_by
    ) values (
      p_course_id, v_course.tenant_id, v_next, p_description, p_delivery_mode, p_duration_hours, coalesce(p_is_mandatory, false),
      coalesce(p_requires_enrollment_approval, false), coalesce(p_requires_assessment, false), p_passing_score,
      coalesce(p_issues_certificate, false), p_certificate_validity_months, p_actor_label
    )
    returning * into v_version;
  exception
    when unique_violation then
      raise exception 'training_course_version_conflict: a version was just created concurrently for course % -- retry to get the current next version number', p_course_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_course.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_training_course_version',
    'app.training_course_versions', v_version.id, 'success', null, null, jsonb_build_object('course_id', p_course_id, 'version_number', v_next)
  );

  return v_version;
end;
$function$;

