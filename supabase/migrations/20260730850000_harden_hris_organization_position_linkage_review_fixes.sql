-- Prompt 275 (CG-S12-HRT-003, Organization and Position Linkage) -- adversarial
-- review-round fix pass. `supabase/migrations/20260730840000_create_hris_
-- organization_position_linkage.sql` fixed its OWN functions in place (that
-- checkpoint was not yet `VERIFIED` when this review ran). The one CONFIRMED finding
-- that reaches into an already-`VERIFIED`, closed checkpoint --
-- `20260730830000_create_hris_employee_master.sql` (HRT-274) -- is fixed here,
-- additively, per this repository's own standing convention (a `VERIFIED` migration
-- is never edited in place; a later checkpoint that must change its behavior does so
-- via `CREATE OR REPLACE FUNCTION` in a new, later-sorting migration).
--
-- ===========================================================================
-- Finding (HIGH): governed `app.employees.position_id` and HRT-274's still-live
-- free-text `app.transfer_employee`/`app.update_employee_draft` can silently
-- desynchronize `position_title`/`manager_employee_id` from the governed truth.
-- ===========================================================================
--
-- `app.transfer_employee` writes `company_org_unit_id`/`branch_org_unit_id`/
-- `department_org_unit_id`/`position_title`/`manager_employee_id` but never touches
-- `position_id`; `app.update_employee_draft` (gated only on `lifecycle_status='draft'`)
-- writes the same `position_title`/`manager_employee_id` pair and likewise never
-- touches `position_id`. Both remained fully callable against an employee who already
-- has a governed `position_id` set by `app.decide_employee_position_assignment`/
-- `app.sync_employee_current_assignment_cache` (HRT-275,
-- `20260730840000_create_hris_organization_position_linkage.sql`) --
-- `app.propose_employee_position_assignment` only blocks `lifecycle_status in
-- ('terminated','archived')`, so a draft/active/on_leave/suspended employee can
-- legally hold BOTH a governed assignment and be edited via the ungoverned free-text
-- path at any time. HRT-275's own decision 3 asserted the free-text paths "remain
-- valid, unchanged, free-text-only paths for a position-less employee" -- but nothing
-- enforced that premise; it was aspirational, not real.
--
-- Fix (recommendation option (a) from the review): both functions now raise a new,
-- named `governed_position_exists` error (`errcode = 'check_violation'`, matching
-- this repository's own error-naming/errcode convention) when the target employee
-- already carries a non-null `position_id`, directing the caller to the governed
-- assignment workflow (`app.propose_employee_position_assignment`) instead of
-- allowing a silent, contradictory overwrite. This blocks the WHOLE call (not merely
-- the two conflicting columns) when a governed position exists -- a deliberate,
-- disclosed trade-off: a draft employee who already holds a governed position must
-- use the governed workflow for position/manager changes and cannot use
-- `app.update_employee_draft` at all while a governed position is attached (a real,
-- but narrow and easily worked around, restriction -- `app.update_employee_draft`'s
-- own remaining fields, name/email/phone/dates, still have no governed-truth
-- conflict, but this fix does not attempt a column-by-column partial guard, since
-- that would require restructuring the single UPDATE statement and risk silently
-- dropping caller-supplied data for the two governed columns instead of rejecting the
-- call outright -- rejecting outright is the safer, more legible failure mode).
-- Every other line of both functions (authority order, record_version handling,
-- lifecycle-status gating, cycle guard, before/after lifecycle-event capture, audit
-- capture) is preserved verbatim from `20260730830000`.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement before
-- its final grants, the standing per-migration convention since PLT-118 (defensive --
-- CREATE OR REPLACE FUNCTION on an already-existing, unchanged-signature function
-- preserves its existing ACL, so this is not structurally required here, but is kept
-- for consistency with every other migration in this repository).

create or replace function app.update_employee_draft(
  p_master_record_id uuid,
  p_expected_version integer,
  p_full_name text,
  p_employment_type text,
  p_work_email text,
  p_personal_email text,
  p_personal_phone text,
  p_national_id_number text,
  p_date_of_birth date,
  p_gender text,
  p_hire_date date,
  p_probation_end_date date,
  p_company_org_unit_id uuid,
  p_branch_org_unit_id uuid,
  p_department_org_unit_id uuid,
  p_position_title text,
  p_manager_employee_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status <> 'draft' then
    raise exception 'employee_not_draft: employee % is % -- only a draft profile may be edited this way', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  -- HRT-275 review-round fix (HIGH): a governed position_id already exists for this
  -- employee -- position_title/manager_employee_id must be changed through
  -- app.propose_employee_position_assignment (the governed workflow), never silently
  -- overwritten here. See this migration's own header for full reasoning.
  if v_employee.position_id is not null then
    raise exception 'governed_position_exists: employee % already has a governed position (%) -- edit position/manager via app.propose_employee_position_assignment, not this free-text profile edit', p_master_record_id, v_employee.position_id
      using errcode = 'check_violation';
  end if;

  if p_full_name is null or length(trim(p_full_name)) = 0 then
    raise exception 'invalid_full_name: full_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_employment_type not in ('full_time', 'part_time', 'contract', 'intern', 'probation', 'daily_worker') then
    raise exception 'invalid_employment_type: %', p_employment_type using errcode = 'check_violation';
  end if;

  if p_manager_employee_id is not null then
    if not exists (select 1 from app.employees where master_record_id = p_manager_employee_id and tenant_id = v_employee.tenant_id) then
      raise exception 'employee_not_found: manager % is not a valid employee for tenant %', p_manager_employee_id, v_employee.tenant_id using errcode = 'no_data_found';
    end if;
    perform app.assert_no_employee_manager_cycle(p_master_record_id, p_manager_employee_id);
  end if;

  update app.employees
  set full_name = p_full_name, employment_type = p_employment_type, work_email = p_work_email,
      personal_email = p_personal_email, personal_phone = p_personal_phone, national_id_number = p_national_id_number,
      date_of_birth = p_date_of_birth, gender = p_gender, hire_date = p_hire_date, probation_end_date = p_probation_end_date,
      company_org_unit_id = p_company_org_unit_id, branch_org_unit_id = p_branch_org_unit_id, department_org_unit_id = p_department_org_unit_id,
      position_title = p_position_title, manager_employee_id = p_manager_employee_id
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.master_records set name = p_full_name where id = p_master_record_id;

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_employee_draft',
    'app.employees', p_master_record_id, 'success', null, null, app.employee_audit_projection(v_employee)
  );

  return v_employee;
end;
$$;

comment on function app.update_employee_draft is
  'HRT-274, review-round-fixed by HRT-275 (20260730850000): draft-only free-text profile edit. Now raises governed_position_exists when the employee already carries a governed position_id (HRT-275''s own decision 3 premise, now actually enforced) -- see that fix''s own inline comment above.';

create or replace function app.transfer_employee(
  p_master_record_id uuid,
  p_expected_version integer,
  p_company_org_unit_id uuid,
  p_branch_org_unit_id uuid,
  p_department_org_unit_id uuid,
  p_position_title text,
  p_manager_employee_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_before jsonb;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'invalid_transition: employee % is % and cannot be transferred', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  -- HRT-275 review-round fix (HIGH): a governed position_id already exists for this
  -- employee -- position_title/manager_employee_id must be changed through
  -- app.propose_employee_position_assignment (the governed workflow), never silently
  -- overwritten here. See 20260730850000's own header for full reasoning.
  if v_employee.position_id is not null then
    raise exception 'governed_position_exists: employee % already has a governed position (%) -- transfer via app.propose_employee_position_assignment, not this free-text transfer', p_master_record_id, v_employee.position_id
      using errcode = 'check_violation';
  end if;

  if p_manager_employee_id is not null then
    if not exists (select 1 from app.employees where master_record_id = p_manager_employee_id and tenant_id = v_employee.tenant_id) then
      raise exception 'employee_not_found: manager % is not a valid employee for tenant %', p_manager_employee_id, v_employee.tenant_id using errcode = 'no_data_found';
    end if;
    perform app.assert_no_employee_manager_cycle(p_master_record_id, p_manager_employee_id);
  end if;

  v_before := jsonb_build_object(
    'company_org_unit_id', v_employee.company_org_unit_id, 'branch_org_unit_id', v_employee.branch_org_unit_id,
    'department_org_unit_id', v_employee.department_org_unit_id, 'position_title', v_employee.position_title,
    'manager_employee_id', v_employee.manager_employee_id
  );

  update app.employees
  set company_org_unit_id = p_company_org_unit_id, branch_org_unit_id = p_branch_org_unit_id,
      department_org_unit_id = p_department_org_unit_id, position_title = p_position_title,
      manager_employee_id = p_manager_employee_id
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
  values (
    v_employee.tenant_id, p_master_record_id, v_employee.lifecycle_status, v_employee.lifecycle_status, p_reason,
    jsonb_build_object(
      'event', 'transfer', 'before', v_before,
      'after', jsonb_build_object(
        'company_org_unit_id', p_company_org_unit_id, 'branch_org_unit_id', p_branch_org_unit_id,
        'department_org_unit_id', p_department_org_unit_id, 'position_title', p_position_title,
        'manager_employee_id', p_manager_employee_id
      )
    ),
    p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'transfer_employee',
    'app.employees', p_master_record_id, 'success', p_reason, v_before, app.employee_audit_projection(v_employee)
  );

  return v_employee;
end;
$$;

comment on function app.transfer_employee is
  'HRT-274, review-round-fixed by HRT-275 (20260730850000): moves company/branch/department/position/manager while preserving full before/after history in app.employee_lifecycle_events.metadata -- lifecycle_status itself is unchanged by a transfer. Now raises governed_position_exists when the employee already carries a governed position_id (HRT-275''s own decision 3 premise, now actually enforced) -- see that fix''s own inline comment above. Callable from any non-terminal, position-less status.';

revoke execute on all functions in schema app from public;

grant execute on function app.update_employee_draft(uuid, integer, text, text, text, text, text, text, date, text, date, date, uuid, uuid, uuid, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.transfer_employee(uuid, integer, uuid, uuid, uuid, text, uuid, text, uuid, text) to authenticated, service_role;
