-- HDN-385 (Data Migration Rehearsal): app.commit_employee_import_job (HRT-274,
-- 20260730830000_create_hris_employee_master.sql) silently swallowed a genuine
-- employee_number collision instead of surfacing it, violating business rule
-- (Prompt 385 §24) "duplicate handling is deterministic and reviewable".
--
-- Live-reproduced at HDN-385's own investigation: staging 2 rows in the same
-- job with the identical explicit employee_number produced a job reported as
-- status=completed with no error, no per-row flag, and only one of the two
-- rows actually written -- the dropped row was indistinguishable from a
-- correctly-committed one anywhere in app.jobs/app.import_staging_rows.
--
-- Root cause: the `master_records` insert's own unique_violation handler
-- caught ANY unique_violation unconditionally and silently skipped, treating
-- it as if it were the same self-idempotent replay case app.employees' own
-- handler protects against via `employees_source_staging_row_unique`. But
-- app.master_records carries no source_import_staging_row_id column at all --
-- there is no legitimate self-idempotent case at this insert. Every
-- master_records_tenant_code_unique violation here means a REAL collision:
-- either two rows in the same batch share an explicit employee_number, or
-- the number already belongs to a pre-existing employee outside this job.
-- This is the exact same defect class app.commit_vendor_rate_import_job
-- (PRC-255, 20260730620000_extend_commercial_vendor_rate_for_procurement.sql
-- lines 1500-1525) already found and fixed -- discriminate by constraint
-- name, only skip a violation of this adapter's own idempotency guard, raise
-- everything else as a real, job-aborting failure.
--
-- Fix: master_records insert no longer has any silent-skip branch (no
-- constraint on that table is ever a legitimate self-replay signal for this
-- function) -- any unique_violation there now raises a clear, named error
-- and aborts the whole commit (the surrounding transaction rolls back, so
-- the job is never marked completed with a silently dropped row). The
-- app.employees insert's own handler is narrowed to only skip a violation of
-- its own `employees_source_staging_row_unique` guard, mirroring PRC-255's
-- proven pattern exactly; anything else there also now raises.
--
-- This does NOT fix the harder, related gap HDN-385 also found: an
-- auto-generated (no explicit employee_number supplied) row has no duplicate
-- check at all against an existing employee sharing the same identity (e.g.
-- work_email) on a fresh re-import -- a genuine business-key duplicate
-- detection design decision, registered separately (ISS-2026-269), not a
-- mechanical fix of an already-proven pattern like this one.

create or replace function app.commit_employee_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
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
  v_updated app.jobs;
  v_config_version_id uuid;
  v_constraint_name text;
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

    v_created_count := v_created_count + 1;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_employee_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object('created_count', v_created_count, 'skipped_count', v_skipped_count)
  );

  return v_updated;
end;
$$;

comment on function app.commit_employee_import_job is 'HRT-274 (decision 11), corrected at HDN-385 (Step 15, Data Migration Rehearsal): idempotent per staging row (source_import_staging_row_id is unique-when-set on app.employees, defended by a pre-check AND a nested unique_violation handler scoped to employees_source_staging_row_unique specifically) and job-scoped-advisory-lock serialized, mirroring app.commit_vendor_rate_import_job (PRC-255) exactly. A genuine employee_number collision (master_records_tenant_code_unique) now raises a clear, named error and aborts the whole commit -- it is never a silent skip, since app.master_records has no self-idempotent-replay case to distinguish it from. Every created row is a real draft employee -- submit/approve/activate remain separate, deliberate HR actions afterward, never auto-activated by import.';
