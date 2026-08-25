-- ISS-2026-269 (Step 15/16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
-- -- an auto-generated-employee-number import row (no employee_number supplied in the
-- source data, so app.next_employee_number() mints one) has ZERO duplicate detection
-- against an existing employee sharing the same identity. Live-reproduced at HDN-385: a
-- fresh re-import of an identical un-keyed row created a second, genuinely duplicate
-- employee (identical full_name/work_email), silently, with zero error/skip/flag.
-- This is distinct from, and unfixed by, HDN-385's own 20260817000000 fix -- that fix
-- only catches a collision on an EXPLICIT employee_number; an un-keyed row has no key to
-- collide on at all, so master_records' own unique constraint never fires.
--
-- Matching heuristic (the one real design decision this finding's own KNOWN_ISSUES.md
-- entry explicitly left open -- "work_email? full_name+date_of_birth? a fuzzy match?"):
-- exact, case-insensitive work_email match, OR exact full_name match, against any
-- EXISTING employee in the same tenant (any lifecycle_status -- a duplicate person is a
-- duplicate regardless of the pre-existing record's own current status). This is not an
-- arbitrary choice: it is the exact same definition of "duplicate" HDN-385's own live
-- reproduction used to demonstrate the defect ("identical full_name/work_email"), so the
-- fix closes precisely the case that was proven, without inventing a fuzzier heuristic
-- (Levenshtein distance, phonetic matching) this entry's own text explicitly flagged as
-- requiring further HR-domain design input beyond a bounded mechanical fix.
--
-- Deliberately a REVIEW flag, never a hard block: app.employee_duplicate_candidates
-- (HRT-274 decision 10) is this schema's own established "flagged for human review, a
-- reviewer's own decision, never an automatic merge" mechanism -- inserting a `pending`
-- row here composes with the exact same review workflow app.submit_employee_for_approval
-- already checks, rather than inventing a second, competing mechanism. The import itself
-- still succeeds (an HR team re-importing a source file with an already-processed row
-- must not be blocked outright -- that would be its own new defect, a false-positive
-- import failure) -- it succeeds WITH a real, reviewable flag recorded, closing the
-- "zero duplicate detection... silently... zero flag" gap this entry names verbatim.
--
-- Deliberately NOT routed through app.flag_employee_duplicate_candidate (the existing
-- manually-invoked RPC): that RPC re-checks HRS:Edit authority on the calling actor,
-- independent of the HRS:Import authority app.commit_employee_import_job already
-- verified once at the top of its own transaction. Composing it here would silently
-- require every importer to ALSO hold HRS:Edit, breaking a legitimate import for any
-- actor who holds Import but not Edit -- a real authority regression this fix must not
-- introduce. Inserting directly into app.employee_duplicate_candidates from within the
-- already-authority-checked commit function avoids it, mirroring how this same migration
-- file's own commit function already writes directly to app.employee_lifecycle_events
-- rather than calling a separate governed RPC for that side effect too.

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

comment on function app.commit_employee_import_job is 'HRT-274 (decision 11), corrected at HDN-385 (Step 15, Data Migration Rehearsal) and ISS-2026-269 (Step 16 historical-issue-backlog remediation): idempotent per staging row and job-scoped-advisory-lock serialized, mirroring app.commit_vendor_rate_import_job (PRC-255) exactly. A genuine explicit employee_number collision (master_records_tenant_code_unique) raises a clear, named error and aborts the whole commit. A fresh, auto-numbered row sharing an existing employee''s own work_email or full_name is flagged into app.employee_duplicate_candidates for human review (never a hard block -- the import still succeeds) -- closing the HDN-385-reproduced silent-duplicate-person gap this earlier fix disclosed but did not close. Every created row is a real draft employee -- submit/approve/activate remain separate, deliberate HR actions afterward, never auto-activated by import.';
