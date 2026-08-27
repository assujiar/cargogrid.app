-- ISS-2026-278 (Step 16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
-- -- no MFA/step-up/elevated-authorization gate exists on any import-commit RPC
-- (app.commit_import_job and every domain adapter's own app.commit_*_import_job), unlike
-- the 4 "platform-default high-risk target functions" HDN-378/ISS-2026-150 already
-- hardened with an IP-allowlist + MFA-step-up composition
-- (app.decide_ai_output_approval, app.activate_enterprise_idp_connection,
-- app.approve_mfa_exception, app.create_integration_connection). A bulk data-migration
-- commit is a privileged/financial-adjacent action (business rule §24's own RPD-023
-- citation names "export... financial, payroll" actions explicitly) yet required only the
-- same authorization bar as staging one ordinary CSV row.
--
-- Confirmed with the operator (AskUserQuestion) before implementing: IP-allowlist gating
-- ONLY, no mandatory MFA step-up, scoped to the 5 real commit_*_import_job functions
-- (app.create_import_export_job/app.stage_import_rows deliberately left untouched -- they
-- are staging operations, not the actual bulk-commit action this entry's own text is
-- concerned with). This entry's own text already flags the real risk of the fuller
-- HDN-378 parity option: forcing a mandatory MFA step-up on every bulk import commit,
-- including routine, non-financial ones (e.g. attendance_device_import), "risks
-- over-restricting a legitimate operational workflow" without a dedicated UX review this
-- checkpoint has no standing to perform. IP-allowlist gating is real defense-in-depth
-- (an optional p_client_ip parameter, skippable when the caller supplies no IP, and
-- bypassable via an already-existing, separately-governed app.ip_allowlist_bypass_grants
-- grant -- the identical composition and identical non-interactive-caller exemption
-- HDN-378's own 4 functions already established) without disrupting any routine import
-- workflow's own existing call shape.
--
-- Widens 5 functions, each with one new, trailing, DEFAULT-valued p_client_ip parameter,
-- inserted immediately after the function's own LAST authority check and before its first
-- business-state validation -- the identical "after authority is otherwise established,
-- before the mutating action" ordering discipline HDN-378 used for its own 4 functions.
-- CREATE OR REPLACE FUNCTION cannot be used for any of these (ISS-2026-260's own
-- self-caught finding: appending a parameter via CREATE OR REPLACE creates a second,
-- ambiguous overload rather than truly replacing the function) -- every one below is an
-- explicit DROP FUNCTION (old signature) + CREATE FUNCTION (new signature), followed by an
-- explicit re-grant to the exact same roles the original migration granted, verified
-- against each original migration's own grant statement before writing the new one.
--
-- app.commit_import_job (generic framework, 20260719170000) and
-- app.commit_vendor_rate_import_job (PRC-255, 20260730620000) are both service_role-only
-- (never granted to authenticated) -- confirmed by direct read of their own original grant
-- statements -- so the live client-facing risk this entry names is narrower for those two
-- specifically than for the 3 authenticated-reachable adapters below; widened anyway for
-- defense-in-depth consistency across the whole risk class, matching HDN-378's own
-- uniform treatment of its 4 target functions regardless of each one's own individual
-- exposure.

-- ===========================================================================
-- 1. app.commit_import_job (generic framework)
-- ===========================================================================

drop function app.commit_import_job(uuid, boolean, uuid, text);

create function app.commit_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
  v_pending_count integer;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_job.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_job.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_job.job_type <> 'import' then
    raise exception 'import_export_wrong_job_type: job % is not an import job', p_job_id using errcode = 'check_violation';
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

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.commit_import_job is
  'ISS-2026-278 (Step 16 historical-issue-backlog remediation): p_client_ip is an optional, trailing 5th parameter (default null) enforcing the tenant''s own IP allowlist restriction (scope ''admin'') via app.assert_ip_allowed when supplied, unless the acting identity holds a currently-active app.ip_allowlist_bypass_grants grant -- the identical composition and non-interactive-caller exemption HDN-378/ISS-2026-150 already established for its own 4 target functions, deliberately without a mandatory MFA step-up requirement (confirmed with the operator: forcing step-up on every bulk import commit, including routine ones, risks over-restricting a legitimate operational workflow without dedicated UX review).';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_import_job(uuid, boolean, uuid, text, text) to service_role;

-- ===========================================================================
-- 2. app.commit_employee_import_job (HRT-274)
-- ===========================================================================

drop function app.commit_employee_import_job(uuid, boolean, uuid, text);

create function app.commit_employee_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_company_id uuid;
  v_branch_id uuid;
  v_department_id uuid;
  v_number text;
  v_master app.master_records;
  v_employee app.employees;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_duplicate_flagged_count integer := 0;
  v_updated app.jobs;
  v_config_version_id uuid;
  v_constraint_name text;
  v_was_auto_numbered boolean;
  v_dup record;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'employee_import' then
    raise exception 'import_export_wrong_schema: job % is not an employee_import job', p_job_id using errcode = 'check_violation';
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

  select config_version_id into v_config_version_id from app.resolve_import_export_schema_columns(v_job.tenant_id, 'employee_import');

  -- Job-scoped advisory lock (mirrors app.commit_vendor_rate_import_job, PRC-255)
  -- -- resolved and taken before any staging row is read, serializing any
  -- concurrent/replayed commit call on this SAME job.
  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 274));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.employees where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;

    v_company_id := null;
    v_branch_id := null;
    v_department_id := null;
    if coalesce(v_payload ->> 'company_org_unit_code', '') <> '' then
      select id into v_company_id from app.org_units where tenant_id = v_job.tenant_id and code = (v_payload ->> 'company_org_unit_code') and unit_type = 'company';
    end if;
    if coalesce(v_payload ->> 'branch_org_unit_code', '') <> '' then
      select id into v_branch_id from app.org_units where tenant_id = v_job.tenant_id and code = (v_payload ->> 'branch_org_unit_code') and unit_type = 'branch';
    end if;
    if coalesce(v_payload ->> 'department_org_unit_code', '') <> '' then
      select id into v_department_id from app.org_units where tenant_id = v_job.tenant_id and code = (v_payload ->> 'department_org_unit_code') and unit_type = 'department';
    end if;

    v_was_auto_numbered := coalesce(nullif(v_payload ->> 'employee_number', ''), '') = '';
    v_number := coalesce(nullif(v_payload ->> 'employee_number', ''), app.next_employee_number(v_job.tenant_id));

    begin
      insert into app.master_records (master_type_code, tenant_id, code, name, aliases, attributes, created_by)
      values ('employee', v_job.tenant_id, v_number, v_payload ->> 'full_name', '[]'::jsonb, '{}'::jsonb, p_actor_label)
      returning * into v_master;
    exception
      when unique_violation then
        -- HDN-385 fix: app.master_records has no source_import_staging_row_id
        -- column and therefore no legitimate self-idempotent-replay case at
        -- this insert -- every collision here is a real one (duplicate
        -- explicit employee_number, in-batch or against a pre-existing
        -- employee). Raise loudly rather than silently dropping the row.
        raise exception 'employee_import_duplicate_employee_number: employee_number % (staging row %) already exists in tenant %', v_number, v_row.id, v_job.tenant_id
          using errcode = 'unique_violation';
    end;

    begin
      insert into app.employees (
        master_record_id, tenant_id, full_name, employment_type, intake_source,
        work_email, personal_email, personal_phone, company_org_unit_id, branch_org_unit_id, department_org_unit_id,
        position_title, source_import_staging_row_id, source_config_version_id, created_by
      )
      values (
        v_master.id, v_job.tenant_id, v_payload ->> 'full_name', coalesce(v_payload ->> 'employment_type', 'full_time'), 'bulk_import',
        nullif(v_payload ->> 'work_email', ''), nullif(v_payload ->> 'personal_email', ''), nullif(v_payload ->> 'personal_phone', ''),
        v_company_id, v_branch_id, v_department_id, nullif(v_payload ->> 'position_title', ''), v_row.id, v_config_version_id, p_actor_label
      )
      returning * into v_employee;
    exception
      when unique_violation then
        -- HDN-385 fix, mirroring app.commit_vendor_rate_import_job's proven
        -- pattern: only a violation of THIS adapter's own idempotency guard
        -- (employees_source_staging_row_unique) means "already committed,
        -- safe to skip" -- any other unique_violation is a real failure.
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'employees_source_staging_row_unique' then
          v_skipped_count := v_skipped_count + 1;
          continue;
        end if;
        raise;
    end;

    insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label, metadata)
    values (v_job.tenant_id, v_employee.master_record_id, 'none', 'draft', p_actor_auth_user_id, p_actor_label, jsonb_build_object('source', 'bulk_import', 'job_id', p_job_id));

    -- ISS-2026-269: an auto-generated employee_number never collides with a prior run's
    -- own auto-generated number, so master_records' own unique constraint is structurally
    -- blind to this case. Flag, for human review, any EXISTING employee in this tenant
    -- (any lifecycle_status) sharing this new row's work_email or full_name -- never a
    -- hard block, the import itself still succeeds.
    if v_was_auto_numbered then
      for v_dup in
        select master_record_id, work_email, full_name from app.employees
        where tenant_id = v_job.tenant_id
          and master_record_id <> v_employee.master_record_id
          and (
            (v_employee.work_email is not null and lower(work_email) = lower(v_employee.work_email))
            or full_name = v_employee.full_name
          )
      loop
        insert into app.employee_duplicate_candidates (
          tenant_id, source_master_record_id, candidate_master_record_id, similarity_basis, similarity_score, created_by
        )
        values (
          v_job.tenant_id, v_employee.master_record_id, v_dup.master_record_id,
          case
            when v_employee.work_email is not null and lower(v_dup.work_email) = lower(v_employee.work_email) and v_dup.full_name = v_employee.full_name then 'work_email+full_name'
            when v_employee.work_email is not null and lower(v_dup.work_email) = lower(v_employee.work_email) then 'work_email'
            else 'full_name'
          end,
          1.0, p_actor_label
        );
        v_duplicate_flagged_count := v_duplicate_flagged_count + 1;
      end loop;
    else
      -- ISS-2026-279: an EXPLICITLY-supplied employee_number that normalizes
      -- (lower + trim) to the same value as an existing employee's own
      -- number, without being byte-identical, sails straight past
      -- master_records_tenant_code_unique (a plain case-sensitive index) --
      -- flag it for human review, exactly mirroring the auto-numbered branch
      -- above, never a hard block.
      for v_dup in
        select e.master_record_id, m.code
        from app.employees e
        join app.master_records m on m.id = e.master_record_id
        where e.tenant_id = v_job.tenant_id
          and e.master_record_id <> v_employee.master_record_id
          and m.code <> v_number
          and lower(trim(m.code)) = lower(trim(v_number))
      loop
        insert into app.employee_duplicate_candidates (
          tenant_id, source_master_record_id, candidate_master_record_id, similarity_basis, similarity_score, created_by
        )
        values (
          v_job.tenant_id, v_employee.master_record_id, v_dup.master_record_id,
          'employee_number_normalized', 1.0, p_actor_label
        );
        v_duplicate_flagged_count := v_duplicate_flagged_count + 1;
      end loop;
    end if;

    v_created_count := v_created_count + 1;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_employee_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object('created_count', v_created_count, 'skipped_count', v_skipped_count, 'duplicate_flagged_count', v_duplicate_flagged_count)
  );

  return v_updated;
end;
$$;

comment on function app.commit_employee_import_job is 'HRT-274 (decision 11), corrected at HDN-385 (Step 15, Data Migration Rehearsal), ISS-2026-269, ISS-2026-279, and ISS-2026-278 (Step 16 historical-issue-backlog remediation): idempotent per staging row and job-scoped-advisory-lock serialized, mirroring app.commit_vendor_rate_import_job (PRC-255) exactly. A genuine explicit employee_number collision (master_records_tenant_code_unique) raises a clear, named error and aborts the whole commit. A fresh, auto-numbered row sharing an existing employee''s own work_email or full_name (ISS-2026-269), OR an explicitly-numbered row whose employee_number normalizes to an existing employee''s own number without being byte-identical (ISS-2026-279), is flagged into app.employee_duplicate_candidates for human review (never a hard block -- the import still succeeds either way). p_client_ip is an optional, trailing 5th parameter (default null) enforcing the tenant''s own IP allowlist restriction when supplied, unless the acting identity holds an active bypass grant (ISS-2026-278). Every created row is a real draft employee -- submit/approve/activate remain separate, deliberate HR actions afterward, never auto-activated by import.';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_employee_import_job(uuid, boolean, uuid, text, text) to authenticated, service_role;

-- ===========================================================================
-- 3. app.commit_attendance_device_import_job (HRT-278)
-- ===========================================================================

drop function app.commit_attendance_device_import_job(uuid, boolean, uuid, text);

create function app.commit_attendance_device_import_job(
  p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null
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
  v_employee app.employees;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_failed_count integer := 0;
  v_ignore app.attendance_events;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'attendance_device_import' then
    raise exception 'import_export_wrong_schema: job % is not an attendance_device_import job', p_job_id using errcode = 'check_violation';
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

  -- Job-scoped advisory lock (mirrors app.commit_employee_import_job, HRT-274,
  -- and app.commit_vendor_rate_import_job, PRC-255, with this checkpoint's own
  -- distinct salt) -- serializes any concurrent/replayed commit call on this
  -- SAME job.
  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 278));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.attendance_events where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;

    select e.* into v_employee from app.employees e join app.master_records m on m.id = e.master_record_id
    where e.tenant_id = v_job.tenant_id and m.code = (v_payload ->> 'employee_number');

    begin
      v_ignore := app._ingest_attendance_event(
        v_employee, v_payload ->> 'event_type', 'device_import', (v_payload ->> 'event_at')::timestamptz, null,
        null, v_payload, v_row.id, p_actor_auth_user_id, p_actor_label
      );
      if coalesce(v_payload ->> 'device_label', '') <> '' then
        update app.attendance_events set device_label = v_payload ->> 'device_label' where id = v_ignore.id;
      end if;
      v_created_count := v_created_count + 1;
    exception
      when no_data_found or check_violation or unique_violation then
        update app.import_staging_rows set validation_status = 'invalid', error = sqlerrm where id = v_row.id;
        v_failed_count := v_failed_count + 1;
    end;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now(),
      valid_row_count = v_created_count, invalid_row_count = coalesce(invalid_row_count, 0) + v_failed_count
  where job_id = p_job_id
  returning * into v_job;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_attendance_device_import_job',
    'app.jobs', p_job_id, 'success', null, null,
    jsonb_build_object('created_count', v_created_count, 'skipped_count', v_skipped_count, 'failed_count', v_failed_count)
  );

  return v_job;
end;
$$;

comment on function app.commit_attendance_device_import_job is
  'HRT-278 (decision 6), widened at ISS-2026-278 (Step 16 historical-issue-backlog remediation): idempotent per staging row (source_import_staging_row_id unique-when-set on app.attendance_events, defended by a pre-check AND a per-row exception handler), job-scoped-advisory-lock serialized. Calls the SAME app._ingest_attendance_event engine the live self-service clock path calls -- never a second, independently-hardened write path. A per-row domain-validation failure at commit time (e.g. the employee was deactivated after this row was validated) marks that ONE row invalid and continues, never aborts the whole batch. p_client_ip is an optional, trailing 5th parameter (default null) enforcing the tenant''s own IP allowlist restriction when supplied, unless the acting identity holds an active bypass grant.';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_attendance_device_import_job(uuid, boolean, uuid, text, text) to authenticated, service_role;

-- ===========================================================================
-- 4. app.commit_timesheet_import_job
-- ===========================================================================

drop function app.commit_timesheet_import_job(uuid, boolean, uuid, text);

create function app.commit_timesheet_import_job(
  p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null
)
returns app.jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_employee app.employees;
  v_job_order_id uuid;
  v_shipment_order_id uuid;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_failed_count integer := 0;
  v_ignore app.timesheet_entries;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'timesheet_import' then
    raise exception 'import_export_wrong_schema: job % is not a timesheet_import job', p_job_id using errcode = 'check_violation';
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

  -- Job-scoped advisory lock, mirrors app.commit_attendance_device_import_
  -- job (HRT-278) with this checkpoint's own distinct salt.
  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 281));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.timesheet_entries where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;

    select e.* into v_employee from app.employees e join app.master_records m on m.id = e.master_record_id
    where e.tenant_id = v_job.tenant_id and m.code = (v_payload ->> 'employee_number');

    v_job_order_id := null;
    if coalesce(v_payload ->> 'job_number', '') <> '' then
      select jo.id into v_job_order_id from app.job_orders jo where jo.tenant_id = v_job.tenant_id and jo.job_number = (v_payload ->> 'job_number');
    end if;
    v_shipment_order_id := null;
    if coalesce(v_payload ->> 'shipment_number', '') <> '' then
      select so.id into v_shipment_order_id from app.shipment_orders so where so.tenant_id = v_job.tenant_id and so.shipment_number = (v_payload ->> 'shipment_number');
    end if;

    begin
      v_ignore := app._create_timesheet_entry(
        v_employee, (v_payload ->> 'work_date')::date, (v_payload ->> 'entry_minutes')::integer, 0,
        v_job_order_id, v_shipment_order_id, null, v_payload ->> 'notes', 'import', null, p_actor_auth_user_id, p_actor_label
      );
      update app.timesheet_entries set source_import_staging_row_id = v_row.id where id = v_ignore.id;
      v_created_count := v_created_count + 1;
    exception
      when no_data_found or check_violation or unique_violation then
        update app.import_staging_rows set validation_status = 'invalid', error = sqlerrm where id = v_row.id;
        v_failed_count := v_failed_count + 1;
    end;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now(),
      valid_row_count = v_created_count, invalid_row_count = coalesce(invalid_row_count, 0) + v_failed_count
  where job_id = p_job_id
  returning * into v_job;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_timesheet_import_job',
    'app.jobs', p_job_id, 'success', null, null,
    jsonb_build_object('created_count', v_created_count, 'skipped_count', v_skipped_count, 'failed_count', v_failed_count)
  );

  return v_job;
end;
$$;

comment on function app.commit_timesheet_import_job is
  'Widened at ISS-2026-278 (Step 16 historical-issue-backlog remediation): idempotent per staging row (source_import_staging_row_id unique-when-set on app.timesheet_entries), job-scoped-advisory-lock serialized, mirrors app.commit_attendance_device_import_job (HRT-278). A per-row domain-validation failure at commit time marks that ONE row invalid and continues, never aborts the whole batch. p_client_ip is an optional, trailing 5th parameter (default null) enforcing the tenant''s own IP allowlist restriction when supplied, unless the acting identity holds an active bypass grant.';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_timesheet_import_job(uuid, boolean, uuid, text, text) to authenticated, service_role;

-- ===========================================================================
-- 5. app.commit_vendor_rate_import_job (PRC-255)
-- ===========================================================================

drop function app.commit_vendor_rate_import_job(uuid, boolean, uuid, text);

create function app.commit_vendor_rate_import_job(
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
  v_vendor_master_id uuid;
  v_vendor_master app.master_records;
  v_new_rate app.vendor_rate_versions;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_tier_idx integer;
  v_tier_prefix text;
  v_tier_amount numeric;
  v_updated app.jobs;
  v_constraint_name text;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'vendor_rate_import' then
    raise exception 'import_export_wrong_schema: job % is not a vendor_rate_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- PRC-255 addition (design note 11): BOTH the unchanged create_rate_version
  -- authority AND the new PRC:Import action -- see this migration's own header for
  -- why PRC:Import alone must never be sufficient.
  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'PRC', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

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

  -- Job-scoped advisory lock (pattern 3) -- resolved and taken before any staging
  -- row is read, serializing any concurrent/replayed commit call on this SAME job.
  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 205));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.vendor_rate_versions where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;
    v_vendor_master_id := null;
    if coalesce(v_payload ->> 'vendor_master_code', '') <> '' then
      select * into v_vendor_master from app.master_records
      where tenant_id = v_job.tenant_id and master_type_code = 'vendor' and code = (v_payload ->> 'vendor_master_code');
      if not found then
        raise exception 'import_vendor_master_not_found: staging row % references vendor_master_code % which does not resolve to a registered vendor in tenant %', v_row.row_number, v_payload ->> 'vendor_master_code', v_job.tenant_id
          using errcode = 'check_violation';
      end if;
      v_vendor_master_id := v_vendor_master.id;
    end if;

    begin
      select * into v_new_rate from app.create_rate_version(
        v_job.tenant_id,
        v_payload ->> 'vendor_code',
        v_payload ->> 'vendor_name',
        v_payload ->> 'service_type',
        nullif(v_payload ->> 'mode', ''),
        v_payload ->> 'origin_lane',
        v_payload ->> 'destination_lane',
        nullif(v_payload ->> 'equipment_type', ''),
        null, null, null, null,
        v_payload ->> 'currency',
        (v_payload ->> 'base_amount')::numeric,
        nullif(v_payload ->> 'minimum_amount', '')::numeric,
        '[]'::jsonb,
        now(), null, null,
        p_actor_auth_user_id, p_actor_label,
        v_vendor_master_id,
        nullif(v_payload ->> 'lead_time_days', '')::integer,
        nullif(v_payload ->> 'capacity_terms', ''),
        v_row.id
      );
    exception
      when unique_violation then
        -- Race-recovery (pattern 4): a concurrent/replayed call already committed
        -- this exact staging row between the exists-check above and this INSERT.
        -- BUG FIX (post-review, CRITICAL): the ORIGINAL handler caught ANY
        -- unique_violation unconditionally, which also silently swallowed a
        -- GENUINE vendor_code collision -- app.create_rate_version ->
        -- app.create_master_record has its own unlocked check-then-insert on
        -- master_records_tenant_code_unique and re-raises a real collision as
        -- master_record_already_exists, ALSO sqlstate unique_violation. Treating
        -- that as "safe replay, skip" silently dropped the row: the job still
        -- reported status=completed/valid_row_count as if the rate version had
        -- been created, but no row was ever written, with no error and no
        -- recoverable retry path (a completed job can never be recommitted).
        -- Only a violation of THIS adapter's own idempotency guard
        -- (vendor_rate_versions_source_import_row_unique) means "already
        -- committed, safe to skip" -- any other unique_violation is a REAL
        -- failure and must abort the whole commit (the surrounding transaction
        -- rolls back, so the job is never marked completed with a silently
        -- dropped row).
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'vendor_rate_versions_source_import_row_unique' then
          v_skipped_count := v_skipped_count + 1;
          continue;
        end if;
        raise;
    end;

    v_created_count := v_created_count + 1;

    for v_tier_idx in 1..3 loop
      v_tier_prefix := 'tier' || v_tier_idx || '_';
      v_tier_amount := nullif(v_payload ->> (v_tier_prefix || 'amount'), '')::numeric;
      if v_tier_amount is not null then
        perform app._insert_vendor_rate_tier(
          v_new_rate,
          v_tier_idx,
          nullif(v_payload ->> (v_tier_prefix || 'weight_min'), '')::numeric,
          nullif(v_payload ->> (v_tier_prefix || 'weight_max'), '')::numeric,
          nullif(v_payload ->> (v_tier_prefix || 'volume_min'), '')::numeric,
          nullif(v_payload ->> (v_tier_prefix || 'volume_max'), '')::numeric,
          v_tier_amount,
          nullif(v_payload ->> (v_tier_prefix || 'minimum_charge'), '')::numeric,
          null,
          p_actor_label
        );
      end if;
    end loop;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_vendor_rate_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object('status', v_updated.status, 'rate_versions_created', v_created_count, 'rows_already_committed_skipped', v_skipped_count)
  );

  return v_updated;
end;
$$;

comment on function app.commit_vendor_rate_import_job is
  'PRC-255, widened at ISS-2026-278 (Step 16 historical-issue-backlog remediation): requires BOTH create_rate_version authority (Supreme Admin or tenant_admin) AND PRC:Import -- neither alone is sufficient. Only a violation of this adapter''s own idempotency guard (vendor_rate_versions_source_import_row_unique) is treated as a safe replay; any other unique_violation (e.g. a genuine vendor_code collision) aborts the whole commit rather than silently dropping the row. p_client_ip is an optional, trailing 5th parameter (default null) enforcing the tenant''s own IP allowlist restriction when supplied, unless the acting identity holds an active bypass grant.';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_vendor_rate_import_job(uuid, boolean, uuid, text, text) to service_role;

-- ===========================================================================
-- 6. Matching Option 2 public.* wrappers (RGL-394) for all 5 functions above --
-- each an explicit DROP FUNCTION (old signature) + CREATE FUNCTION (new signature,
-- matching each app.* function's own security mode exactly), never CREATE OR REPLACE
-- across a changed argument list (ISS-2026-260's own self-caught finding).
-- ===========================================================================

drop function public.commit_import_job(uuid, boolean, uuid, text);

create function public.commit_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
returns app.jobs
language sql
volatile
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.commit_import_job(p_job_id, p_allow_partial, p_actor_auth_user_id, p_actor_label, p_client_ip);
$wrap$;

comment on function public.commit_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.commit_import_job with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.commit_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.commit_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;

drop function public.commit_employee_import_job(uuid, boolean, uuid, text);

create function public.commit_employee_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
returns app.jobs
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.commit_employee_import_job(p_job_id, p_allow_partial, p_actor_auth_user_id, p_actor_label, p_client_ip);
$wrap$;

comment on function public.commit_employee_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.commit_employee_import_job with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.commit_employee_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.commit_employee_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role, authenticated;

drop function public.commit_attendance_device_import_job(uuid, boolean, uuid, text);

create function public.commit_attendance_device_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
returns app.jobs
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.commit_attendance_device_import_job(p_job_id, p_allow_partial, p_actor_auth_user_id, p_actor_label, p_client_ip);
$wrap$;

comment on function public.commit_attendance_device_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.commit_attendance_device_import_job with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.commit_attendance_device_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.commit_attendance_device_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role, authenticated;

drop function public.commit_timesheet_import_job(uuid, boolean, uuid, text);

create function public.commit_timesheet_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
returns app.jobs
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.commit_timesheet_import_job(p_job_id, p_allow_partial, p_actor_auth_user_id, p_actor_label, p_client_ip);
$wrap$;

comment on function public.commit_timesheet_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.commit_timesheet_import_job with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.commit_timesheet_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.commit_timesheet_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role, authenticated;

drop function public.commit_vendor_rate_import_job(uuid, boolean, uuid, text);

create function public.commit_vendor_rate_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
returns app.jobs
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.commit_vendor_rate_import_job(p_job_id, p_allow_partial, p_actor_auth_user_id, p_actor_label, p_client_ip);
$wrap$;

comment on function public.commit_vendor_rate_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.commit_vendor_rate_import_job with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.commit_vendor_rate_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) from anon, authenticated, service_role, public;
grant execute on function public.commit_vendor_rate_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text) to service_role;
