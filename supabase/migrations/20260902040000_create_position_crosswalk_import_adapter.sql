-- ISS-2026-066 item 3 (docs/runtime/KNOWN_ISSUES.md): "No staged-import (PLT-131/132)
-- crosswalk for position/grade/assignment rows." HRT-275's own migration disclosed this as a
-- deliberate scope trim, not a defect -- this is the narrow, additive PLT-131 domain-write
-- adapter that closes it, mirroring app.commit_payroll_loan_cutover_import_job (the freshest
-- adapter in the repository, 20260901010000, further widened by 20260901110000's step-up/IP
-- composition) exactly, never a reimplementation of app.propose_employee_position_assignment's
-- own rules.
--
-- ===========================================================================
-- Live schema re-verified before writing this file, per this checkpoint's own instruction --
-- nothing below is assumed from an on-disk migration that may be stale
-- ===========================================================================
--
-- `pg_get_functiondef`/`information_schema.columns` against the live hosted project confirmed:
--   * app.propose_employee_position_assignment is still the original 13-argument HRT-275 shape
--     (no p_client_ip) -- this adapter calls it unchanged, never widened.
--   * app.decide_employee_position_assignment WAS widened after HRT-275 shipped (a 7th trailing
--     p_client_ip default null, added by 20260831270000) -- moot here, because this adapter
--     deliberately never calls it (see the design decision below).
--   * app.employee_position_assignments carries no source_import_staging_row_id column yet --
--     added below, mirroring app.payroll_loans' identical ISS-2026-317 lineage column exactly.
--   * app._run_scheduled_task_once currently dispatches 20 task_code branches (the ISS-2026-066
--     scheduler item is unrelated to this file -- app.activate_due_employee_position_assignments
--     was already registered as the employee_position_activation catalogue task at
--     20260831090000_create_tenant_configurable_task_scheduler.sql, and the entry's own 2026-08-31
--     update already marked that ONE item RESOLVED. Nothing about the scheduler is touched here.
--
-- ===========================================================================
-- The one real design decision: PROPOSE only, never DECIDE
-- ===========================================================================
--
-- app.commit_payroll_loan_cutover_import_job calls app.issue_payroll_loan directly to fully
-- effective loans, because a payroll cutover IS the authoritative opening balance -- there is no
-- separate "review" step for it anywhere else in this schema. A position/grade crosswalk row is
-- different: HRT-275's own section 21 main flow is a deliberate two-step propose-then-decide
-- workflow (a pending_approval proposal, reviewed and approved/rejected as a SEPARATE, later
-- HRS:Approve act), and the entry's own filing text calls this "a staged, REVIEWED crosswalk" --
-- the review is the point, not an inconvenience to route around. So this adapter calls ONLY
-- app.propose_employee_position_assignment per row, exactly mirroring app.commit_employee_
-- import_job's own established discipline ("Every created row is a real draft employee --
-- submit/approve/activate remain separate, deliberate HR actions afterward, never auto-activated
-- by import"). Every bulk-created proposal here lands in the SAME pending_approval queue a single
-- HR-entered proposal would, reviewed through the SAME existing /hris/employees/[masterRecordId]/
-- positions wizard -- no new approval UI is needed or built. This also means the commit RPC only
-- needs to require HRS:Import + HRS:Edit (what propose itself demands), never HRS:Approve or an
-- administrative (is_support_grant_authority) gate -- a materially lower blast radius than a
-- bulk-effective write, correctly reflected in a lighter authority bar.
--
-- ===========================================================================
-- STEP 1: lineage column, mirroring app.payroll_loans.source_import_staging_row_id
-- (ISS-2026-317) exactly -- the idempotency backstop for a re-committed job.
-- ===========================================================================

alter table app.employee_position_assignments add column source_import_staging_row_id uuid references app.import_staging_rows (id);

create unique index employee_position_assignments_source_import_row_unique on app.employee_position_assignments (source_import_staging_row_id)
  where source_import_staging_row_id is not null;

comment on column app.employee_position_assignments.source_import_staging_row_id is
  'ISS-2026-066 item 3: when this PROPOSAL was created by app.commit_position_crosswalk_import_job, the staging row it came from -- null for a proposal entered through the ordinary single-employee UI wizard. Stamped via a direct UPDATE immediately after app.propose_employee_position_assignment returns (that primitive''s own signature is never widened -- it has 60+ live callers and no need to know about import provenance). The partial unique index is the idempotency backstop: a re-committed job cannot create a second proposal from the same staging row.';

-- ===========================================================================
-- STEP 2: register the import schema kind.
-- ===========================================================================

insert into app.import_export_schemas (code, name, owner_primitive_code, registered_by)
values ('position_crosswalk_import', 'Position/Grade Crosswalk Import', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('import_export:position_crosswalk_import', 'Position/Grade Crosswalk Import Column Mapping', 'HRS', 'system')
on conflict (code) do nothing;

-- ===========================================================================
-- STEP 3: app.validate_position_crosswalk_import_row -- invoker, mirroring app.validate_
-- payroll_loan_cutover_import_row exactly: re-derives only what can be answered earlier and
-- cheaper than the commit step, leaves every authoritative rule inside app.propose_employee_
-- position_assignment.
-- ===========================================================================

create function app.validate_position_crosswalk_import_row(
  p_staging_row_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.import_staging_rows
language plpgsql
as $$
declare
  v_row app.import_staging_rows;
  v_job app.jobs;
  v_payload jsonb;
  v_field text;
  v_value text;
  v_errors text[] := array[]::text[];
  v_text_fields text[] := array['employee_number', 'position_code', 'grade_code', 'manager_employee_number', 'assignment_type', 'change_reason', 'reason_note'];
  v_employee_id uuid;
  v_manager_id uuid;
  v_position_id uuid;
  v_assignment_type text;
  v_change_reason text;
  v_start_date date;
  v_end_date date;
  v_allocation numeric;
begin
  v_row := app.validate_staging_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
  if v_row.validation_status <> 'valid' then
    return v_row;
  end if;

  select * into v_job from app.jobs where job_id = v_row.job_id;
  v_payload := v_row.raw_payload;

  foreach v_field in array v_text_fields loop
    v_value := v_payload ->> v_field;
    if v_value is not null and v_value ~ '^[-+=@\t\r]' then
      v_errors := v_errors || (v_field || ': value begins with a disallowed formula/spreadsheet-injection prefix (=, +, -, @, tab, or carriage return)');
    end if;
  end loop;

  select e.master_record_id, e.lifecycle_status into v_employee_id, v_value
  from app.employees e
  join app.master_records m on m.id = e.master_record_id
  where e.tenant_id = v_job.tenant_id and m.code = trim(coalesce(v_payload ->> 'employee_number', ''));
  if v_employee_id is null then
    v_errors := v_errors || ('employee_number: ' || coalesce(v_payload ->> 'employee_number', '(missing)') || ' does not resolve to an employee of this tenant');
  elsif v_value in ('terminated', 'archived') then
    v_errors := v_errors || ('employee_number: ' || (v_payload ->> 'employee_number') || ' is ' || v_value || ' and cannot receive a new position assignment');
  end if;

  select id into v_position_id from app.positions where tenant_id = v_job.tenant_id and code = trim(coalesce(v_payload ->> 'position_code', '')) and status = 'active';
  if v_position_id is null then
    v_errors := v_errors || ('position_code: ' || coalesce(v_payload ->> 'position_code', '(missing)') || ' does not resolve to an active position of this tenant');
  end if;

  if coalesce(v_payload ->> 'grade_code', '') <> '' and not exists (
    select 1 from app.position_grades where tenant_id = v_job.tenant_id and code = trim(v_payload ->> 'grade_code') and status = 'active'
  ) then
    v_errors := v_errors || ('grade_code: ' || (v_payload ->> 'grade_code') || ' does not resolve to an active grade of this tenant');
  end if;

  if coalesce(v_payload ->> 'manager_employee_number', '') <> '' then
    select e.master_record_id into v_manager_id
    from app.employees e
    join app.master_records m on m.id = e.master_record_id
    where e.tenant_id = v_job.tenant_id and m.code = trim(v_payload ->> 'manager_employee_number');
    if v_manager_id is null then
      v_errors := v_errors || ('manager_employee_number: ' || (v_payload ->> 'manager_employee_number') || ' does not resolve to an employee of this tenant');
    elsif v_manager_id = v_employee_id then
      v_errors := v_errors || ('manager_employee_number: an employee may not be their own manager');
    end if;
  end if;

  v_assignment_type := coalesce(nullif(trim(v_payload ->> 'assignment_type'), ''), 'primary');
  if v_assignment_type not in ('primary', 'secondary') then
    v_errors := v_errors || ('assignment_type: ' || v_assignment_type || ' must be primary or secondary');
  end if;

  v_change_reason := coalesce(nullif(trim(v_payload ->> 'change_reason'), ''), 'correction');
  if v_change_reason not in ('hire', 'transfer', 'promotion', 'demotion', 'lateral_move', 'reorganization', 'secondary_assignment', 'correction') then
    v_errors := v_errors || ('change_reason: ' || v_change_reason || ' is not a recognized change reason');
  elsif v_assignment_type = 'secondary' and v_change_reason <> 'secondary_assignment' then
    v_errors := v_errors || ('change_reason: a secondary assignment_type requires an explicit change_reason of secondary_assignment');
  end if;

  if coalesce(v_payload ->> 'effective_start_date', '') <> '' then
    begin
      v_start_date := (trim(v_payload ->> 'effective_start_date'))::date;
    exception when others then
      v_errors := v_errors || ('effective_start_date: ' || (v_payload ->> 'effective_start_date') || ' is not a valid date');
    end;
  end if;

  if coalesce(v_payload ->> 'effective_end_date', '') <> '' then
    begin
      v_end_date := (trim(v_payload ->> 'effective_end_date'))::date;
      if v_start_date is not null and v_end_date < v_start_date then
        v_errors := v_errors || ('effective_end_date: ' || v_end_date || ' is before effective_start_date ' || v_start_date);
      end if;
    exception when others then
      v_errors := v_errors || ('effective_end_date: ' || (v_payload ->> 'effective_end_date') || ' is not a valid date');
    end;
  end if;

  if coalesce(v_payload ->> 'allocation_pct', '') <> '' then
    begin
      v_allocation := (trim(v_payload ->> 'allocation_pct'))::numeric;
      if v_allocation <= 0 or v_allocation > 100 then
        v_errors := v_errors || ('allocation_pct: ' || v_allocation || ' must be greater than 0 and no more than 100');
      end if;
    exception when others then
      v_errors := v_errors || ('allocation_pct: ' || (v_payload ->> 'allocation_pct') || ' is not a valid number');
    end;
  end if;

  if array_length(v_errors, 1) is not null then
    update app.import_staging_rows set validation_status = 'invalid', error = array_to_string(v_errors, '; ')
    where id = p_staging_row_id returning * into v_row;
    update app.jobs set valid_row_count = greatest(valid_row_count - 1, 0), invalid_row_count = invalid_row_count + 1
    where job_id = v_row.job_id;
  end if;

  return v_row;
end;
$$;

comment on function app.validate_position_crosswalk_import_row is
  'ISS-2026-066 item 3: row-level validation for position_crosswalk_import. Re-derives only what can be answered earlier and cheaper than the commit step -- employee_number resolving to a non-terminated/archived employee of this tenant, position_code resolving to an active position, an optional grade_code resolving to an active grade, an optional manager_employee_number resolving to a different employee, assignment_type/change_reason within the CHECK-constrained vocabulary (including the secondary/secondary_assignment pairing rule), and well-formed dates/allocation_pct -- and leaves the authoritative proposal rule (capacity, cycle detection, version match) inside app.propose_employee_position_assignment.';

-- ===========================================================================
-- STEP 4: app.commit_position_crosswalk_import_job -- security definer, mirroring app.commit_
-- payroll_loan_cutover_import_job''s CURRENT (post-20260901110000) shape: IP-allowlist gating
-- and step-up MFA composition adopted at birth, never as a later remediation. Requires HRS:Import
-- AND HRS:Edit (what app.propose_employee_position_assignment itself separately demands of every
-- single-proposal caller) -- deliberately NOT HRS:Approve and NOT an administrative gate, since
-- this adapter only ever creates pending_approval proposals (see this file''s own header for why).
-- ===========================================================================

create function app.commit_position_crosswalk_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.jobs
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_employee_id uuid;
  v_employee_version integer;
  v_employee_status text;
  v_position_id uuid;
  v_grade_id uuid;
  v_manager_id uuid;
  v_assignment_type text;
  v_change_reason text;
  v_start_date date;
  v_end_date date;
  v_allocation numeric;
  v_reason_note text;
  v_proposed app.employee_position_assignments;
  v_config_version_id uuid;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'position_crosswalk_import' then
    raise exception 'import_export_wrong_schema: job % is not a position_crosswalk_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'HRS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- app.propose_employee_position_assignment itself demands HRS:Edit of ITS caller for every
  -- ordinary, single-proposal call -- a bulk crosswalk import is not exempt from that rule just
  -- because it arrives as a file. Checked here, before the loop, so a batch missing only this
  -- authority fails fast with one clear reason instead of failing row-by-row mid-commit.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-278 shape, adopted at birth: reuses the SAME HRS:Import pair already checked above,
  -- never HRS:Edit -- a strict no-op unless this tenant has itself opted (HRS, Import) into its
  -- own additional_high_risk_actions AND turned MFA on.
  perform app.assert_current_step_up_authorization(v_job.tenant_id, p_actor_auth_user_id, 'HRS', 'Import');

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_job.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_job.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_job.status <> 'in_progress' then
    raise exception 'import_export_job_not_committable: job % is %, only an in_progress job may be committed', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_pending_count from app.import_staging_rows where job_id = p_job_id and validation_status = 'pending';
  if v_pending_count > 0 then
    raise exception 'import_export_job_not_fully_validated: job % still has % row(s) pending validation', p_job_id, v_pending_count
      using errcode = 'check_violation';
  end if;

  if v_job.invalid_row_count > 0 and not coalesce(p_allow_partial, false) then
    raise exception 'import_export_job_has_invalid_rows: job % has % invalid row(s); pass p_allow_partial to accept a partial commit', p_job_id, v_job.invalid_row_count
      using errcode = 'check_violation';
  end if;

  select config_version_id into v_config_version_id from app.resolve_import_export_schema_columns(v_job.tenant_id, 'position_crosswalk_import');

  -- Job-scoped advisory lock, mirrors every other commit_*_import_job adapter (HRT-275''s own
  -- checkpoint number as the salt, matching app.commit_employee_import_job''s use of 274 for
  -- HRT-274).
  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 275));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    v_payload := v_row.raw_payload;

    if exists (select 1 from app.employee_position_assignments where tenant_id = v_job.tenant_id and source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    select e.master_record_id, e.record_version, e.lifecycle_status into v_employee_id, v_employee_version, v_employee_status
    from app.employees e
    join app.master_records m on m.id = e.master_record_id
    where e.tenant_id = v_job.tenant_id and m.code = trim(v_payload ->> 'employee_number');

    if v_employee_id is null or v_employee_status in ('terminated', 'archived') then
      raise exception 'import_row_no_longer_resolvable: staging row % no longer resolves to a non-terminated/archived employee of this tenant', v_row.id
        using errcode = 'check_violation';
    end if;

    select id into v_position_id from app.positions where tenant_id = v_job.tenant_id and code = trim(v_payload ->> 'position_code') and status = 'active';
    if v_position_id is null then
      raise exception 'import_row_no_longer_resolvable: staging row % no longer resolves to an active position of this tenant', v_row.id
        using errcode = 'check_violation';
    end if;

    v_grade_id := null;
    if coalesce(v_payload ->> 'grade_code', '') <> '' then
      select id into v_grade_id from app.position_grades where tenant_id = v_job.tenant_id and code = trim(v_payload ->> 'grade_code') and status = 'active';
      if v_grade_id is null then
        raise exception 'import_row_no_longer_resolvable: staging row % no longer resolves to an active grade of this tenant', v_row.id
          using errcode = 'check_violation';
      end if;
    end if;

    v_manager_id := null;
    if coalesce(v_payload ->> 'manager_employee_number', '') <> '' then
      select e.master_record_id into v_manager_id
      from app.employees e
      join app.master_records m on m.id = e.master_record_id
      where e.tenant_id = v_job.tenant_id and m.code = trim(v_payload ->> 'manager_employee_number');
      if v_manager_id is null then
        raise exception 'import_row_no_longer_resolvable: staging row % no longer resolves a manager_employee_number to an employee of this tenant', v_row.id
          using errcode = 'check_violation';
      end if;
    end if;

    v_assignment_type := coalesce(nullif(trim(v_payload ->> 'assignment_type'), ''), 'primary');
    v_change_reason := coalesce(nullif(trim(v_payload ->> 'change_reason'), ''), 'correction');
    v_start_date := coalesce(nullif(trim(v_payload ->> 'effective_start_date'), '')::date, current_date);
    v_end_date := nullif(trim(v_payload ->> 'effective_end_date'), '')::date;
    v_allocation := coalesce(nullif(trim(v_payload ->> 'allocation_pct'), '')::numeric, 100.00);
    v_reason_note := coalesce(nullif(trim(v_payload ->> 'reason_note'), ''), 'Bulk position/grade crosswalk import (staging row ' || v_row.id::text || ')');

    v_proposed := app.propose_employee_position_assignment(
      v_employee_id, v_employee_version, v_position_id, v_grade_id, v_manager_id,
      v_assignment_type, v_allocation, v_start_date, v_end_date,
      v_change_reason, v_reason_note, p_actor_auth_user_id, p_actor_label
    );

    update app.employee_position_assignments
    set source_import_staging_row_id = v_row.id, source_config_version_id = coalesce(source_config_version_id, v_config_version_id)
    where id = v_proposed.id;

    v_created_count := v_created_count + 1;
  end loop;

  update app.jobs
  set status = 'completed',
      processed_rows = v_created_count + v_skipped_count,
      completed_at = now(),
      payload = payload || jsonb_build_object('created_count', v_created_count, 'skipped_count', v_skipped_count)
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_position_crosswalk_import_job',
    'app.jobs', p_job_id, 'success', null, null,
    jsonb_build_object('created_count', v_created_count, 'skipped_count', v_skipped_count, 'allow_partial', coalesce(p_allow_partial, false))
  );

  return v_updated;
end;
$$;

comment on function app.commit_position_crosswalk_import_job is
  'ISS-2026-066 item 3: the PLT-131 domain-write adapter for the position_crosswalk_import schema. Every row calls ONLY app.propose_employee_position_assignment (never app.decide_employee_position_assignment) -- creating a real pending_approval proposal, never an auto-approved live change, so the SAME human review this checkpoint''s own single-employee wizard requires still applies to every bulk-created row (this file''s own header explains why). Requires HRS:Import AND HRS:Edit (the same authority app.propose_employee_position_assignment already demands of its caller for one proposal at a time). Idempotent per staging row (employee_position_assignments_source_import_row_unique, defended by a pre-check), job-scoped-advisory-lock serialized. p_client_ip is an optional, trailing 5th parameter (default null) enforcing the tenant''s own IP allowlist restriction when supplied, unless the acting identity holds an active bypass grant, and the commit is additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''HRS'', ''Import'') -- both composed at birth, mirroring app.commit_payroll_loan_cutover_import_job''s CURRENT, post-ISS-2026-278 shape rather than requiring a later remediation pass.';

-- ===========================================================================
-- STEP 5: grants + public.* wrappers, matching app.commit_payroll_loan_cutover_import_job''s
-- established grant set exactly -- service_role only, never anon/authenticated (RGL-394 Option 2).
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.validate_position_crosswalk_import_row(uuid, uuid, text) to service_role;
grant execute on function app.commit_position_crosswalk_import_job(uuid, boolean, uuid, text, text) to service_role;

create function public.validate_position_crosswalk_import_row(p_staging_row_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.import_staging_rows
language sql
set search_path = app, public, pg_temp
as $wrap$
  select * from app.validate_position_crosswalk_import_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.validate_position_crosswalk_import_row(uuid, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin invoker-rights pass-through, never a reimplementation -- invoker rather than definer because the app.* function it wraps is, and the wrapper-parity gate requires the two sides to agree.';

revoke execute on function public.validate_position_crosswalk_import_row(uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.validate_position_crosswalk_import_row(uuid, uuid, text) to service_role;

create function public.commit_position_crosswalk_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
returns app.jobs
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.commit_position_crosswalk_import_job(p_job_id, p_allow_partial, p_actor_auth_user_id, p_actor_label, p_client_ip);
$wrap$;

comment on function public.commit_position_crosswalk_import_job is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through, never a reimplementation.';

revoke execute on function public.commit_position_crosswalk_import_job(uuid, boolean, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.commit_position_crosswalk_import_job(uuid, boolean, uuid, text, text) to service_role;
