-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Part 3 of 4 -- HRIS, payroll, training/talent, and the cutover import-commit family
--
-- Continues the already-established, already-precedented repository fix pass for this
-- defect class (ISS-2026-043 / ISS-2026-048 / ISS-2026-054, and the eight 20260902*
-- harden_tenant_id_disclosure_* migrations immediately preceding these four). Root cause
-- unchanged: a SECURITY DEFINER function looks a record up by its own bare id (the caller
-- does not yet know which tenant owns it), THEN evaluates the actor's authority against
-- the looked-up row's own real tenant_id, and on denial raises
-- 'insufficient_authority: ... for tenant %' interpolating that real tenant_id -- handing
-- it to a caller who has not yet been shown to have ANY relationship to that tenant.
--
-- The fix, identical in shape to 20260902100000_harden_tenant_id_disclosure_finance.sql:
-- fold app.has_active_tenant_membership(<row>.tenant_id, p_actor_auth_user_id) into the
-- SAME not-found branch the row-miss case already raises, reusing that branch's identical
-- generic message and errcode = 'no_data_found'. A caller with zero membership in the
-- row's real tenant now gets byte-for-byte the error a nonexistent id already produced.
--
-- What is deliberately NOT changed: the authority check itself (evaluate_permission /
-- check_*_authority / can_access_record) is untouched, and a genuine member of that same
-- tenant who merely lacks the specific ROLE authority still reaches the original
-- insufficient_authority raise, with the same insufficient_privilege errcode and the same
-- message text, exactly as before. Preserving that distinction is the point of the fix:
-- only the zero-relationship caller's error shape changes. app.has_active_tenant_membership
-- is itself supreme-admin- and support-grant-aware (20260716111315_create_support_access),
-- so platform administrators and live support grants are unaffected.
--
-- Why this cannot deny a caller who was previously allowed: since
-- 20260810300000_harden_rbac_evaluator_tenant_membership_check, app.evaluate_permission
-- ITSELF refuses to return allowed=true without app.has_active_tenant_membership on the
-- same tenant, and the check_*_authority helpers wrap it. The gate added below is
-- therefore strictly implied by every authority check that already had to pass -- it only
-- moves WHEN the refusal is decided, never WHETHER it is.
--
-- 22 functions in this part. Every definition below is CREATE OR REPLACE against the
-- function's CURRENT live body -- the last migration that defines it, verified per
-- function, not an earlier superseded text. Signatures, volatility, security attribute and
-- search_path are copied verbatim and unchanged, so grants are unaffected.


-- app.cancel_payroll_loan
create or replace function app.cancel_payroll_loan(p_loan_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_loans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_loan app.payroll_loans;
begin
  select * into v_loan from app.payroll_loans where id = p_loan_id for update;
  if not found or not app.has_active_tenant_membership(v_loan.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_loan_not_found: %', p_loan_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Approve', v_loan.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_loan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_loan.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_loan.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_loan.status <> 'active' then
    raise exception 'invalid_transition: loan % is already %', p_loan_id, v_loan.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to cancel a loan' using errcode = 'check_violation';
  end if;

  update app.payroll_loans set status = 'cancelled', cancel_reason = p_reason where id = p_loan_id and record_version = p_expected_version
  returning * into v_loan;
  if not found then
    raise exception 'stale_version: concurrent update detected for loan %', p_loan_id using errcode = 'serialization_failure';
  end if;

  update app.payroll_loan_installments set status = 'waived' where loan_id = p_loan_id and status = 'scheduled';

  perform app.capture_audit_event(
    v_loan.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_payroll_loan',
    'app.payroll_loans', v_loan.id, 'success', null, null, null
  );

  return v_loan;
end;
$$;


-- app.cancel_payroll_run
create or replace function app.cancel_payroll_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
begin
  select * into v_run from app.payroll_runs where id = p_run_id for update;
  if not found or not app.has_active_tenant_membership(v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Edit', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_run.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_run.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_run.status not in ('draft', 'calculated', 'exception') then
    raise exception 'invalid_transition: run % is % -- a submitted/finalized run cannot be cancelled directly (reject via app.finalize_payroll_run, or correct via a linked run)', p_run_id, v_run.status
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to cancel a payroll run' using errcode = 'check_violation';
  end if;

  update app.payroll_runs set status = 'cancelled', cancel_reason = p_reason where id = p_run_id and record_version = p_expected_version
  returning * into v_run;
  if not found then
    raise exception 'stale_version: concurrent update detected for run %', p_run_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_payroll_run',
    'app.payroll_runs', v_run.id, 'success', null, null, null
  );

  return v_run;
end;
$$;


-- app.commit_attendance_device_import_job
create or replace function app.commit_attendance_device_import_job(
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
  v_employee app.employees;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_failed_count integer := 0;
  v_ignore app.attendance_events;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
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

  -- ISS-2026-278 (this migration): reuses the SAME HRS:Import pair the check immediately
  -- above already gates on. A strict no-op unless this tenant has itself opted (HRS,
  -- Import) into its own additional_high_risk_actions AND turned MFA on.
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


-- app.commit_customer_import_job
create or replace function app.commit_customer_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.jobs
language plpgsql
security definer
set search_path = 'app', 'public', 'pg_temp'
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_billing jsonb;
  v_account app.accounts;
  v_created_count integer := 0;
  v_linked_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
  v_constraint_name text;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'customer_import' then
    raise exception 'import_export_wrong_schema: job % is not a customer_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'COM', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-278 (unchanged by this migration): reuses the SAME COM:Import pair the check
  -- immediately above already gates on. A strict no-op unless this tenant has itself opted
  -- (COM, Import) into its own additional_high_risk_actions AND turned MFA on.
  perform app.assert_current_step_up_authorization(v_job.tenant_id, p_actor_auth_user_id, 'COM', 'Import');

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

  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 205));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.accounts where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;

    -- Billing address is assembled from flat columns: a spreadsheet cell cannot carry a
    -- jsonb object, and accepting raw JSON text from a file would be handing an importer
    -- direct control of a jsonb column's shape.
    v_billing := jsonb_strip_nulls(jsonb_build_object(
      'line1', nullif(v_payload ->> 'billing_line1', ''),
      'city', nullif(v_payload ->> 'billing_city', ''),
      'region', nullif(v_payload ->> 'billing_region', ''),
      'postalCode', nullif(v_payload ->> 'billing_postal_code', ''),
      'country', nullif(v_payload ->> 'billing_country', '')
    ));

    -- The canonical write path. No unique_violation handler here deliberately: the only
    -- collision this primitive can hit is the duplicate fingerprint, which it resolves
    -- internally to the existing account rather than raising. Anything that does escape is
    -- a genuine failure and must abort the whole commit.
    v_account := app.create_customer_account_direct(
      v_job.tenant_id,
      v_payload ->> 'legal_name',
      nullif(v_payload ->> 'trade_name', ''),
      nullif(v_payload ->> 'tax_id', ''),
      v_billing,
      null,
      p_actor_auth_user_id,
      p_actor_label
    );

    if v_account.source_import_staging_row_id = v_row.id then
      v_skipped_count := v_skipped_count + 1;
      continue;
    elsif v_account.source_import_staging_row_id is not null then
      -- Resolved by duplicate fingerprint to an account an EARLIER staged row created.
      -- See this migration's header: this is the designed behaviour of
      -- accounts_tenant_fingerprint_active_unique, not an anomaly, and it is counted and
      -- reported rather than silently dropped or miscounted as created.
      --
      -- ISS-2026-277 (this migration): before treating this match as a legitimate link,
      -- refuse it if the resolved account is under legal hold -- import content must not
      -- be silently associated with a held record, even via a "link", which is exactly the
      -- kind of write path app._is_under_legal_hold()'s own DELETE-scoped guards do not see.
      if app._is_under_legal_hold(v_job.tenant_id, 'operational', 'app.accounts', v_account.id) then
        raise exception 'import_blocked_legal_hold: account % is under legal hold, this import commit cannot target it', v_account.id
          using errcode = 'check_violation';
      end if;
      v_linked_count := v_linked_count + 1;
      continue;
    elsif v_account.created_at < v_job.created_at then
      -- Resolved to an account that predates this job entirely. Also a legitimate link,
      -- and deliberately NOT stamped: stamping it would rewrite the provenance of a record
      -- this import did not create.
      --
      -- ISS-2026-277 (this migration): the identical guard as the branch above -- a
      -- pre-existing, job-predating account under legal hold must not be silently linked
      -- either.
      if app._is_under_legal_hold(v_job.tenant_id, 'operational', 'app.accounts', v_account.id) then
        raise exception 'import_blocked_legal_hold: account % is under legal hold, this import commit cannot target it', v_account.id
          using errcode = 'check_violation';
      end if;
      v_linked_count := v_linked_count + 1;
      continue;
    end if;

    begin
      update app.accounts
      set source_import_staging_row_id = v_row.id
      where id = v_account.id
      returning * into v_account;
    exception
      when unique_violation then
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'accounts_source_import_row_unique' then
          v_skipped_count := v_skipped_count + 1;
          continue;
        end if;
        raise;
    end;

    v_created_count := v_created_count + 1;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_customer_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object(
      'status', v_updated.status,
      'accounts_created', v_created_count,
      'rows_linked_to_existing_account', v_linked_count,
      'rows_already_committed_skipped', v_skipped_count
    )
  );

  return v_updated;
end;
$$;


-- app.commit_employee_import_job
create or replace function app.commit_employee_import_job(
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
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
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

  -- ISS-2026-278 (this migration): reuses the SAME HRS:Import pair the check immediately
  -- above already gates on. A strict no-op unless this tenant has itself opted (HRS,
  -- Import) into its own additional_high_risk_actions AND turned MFA on.
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


-- app.commit_finance_opening_balance_import_job
create or replace function app.commit_finance_opening_balance_import_job(
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
  v_type text;
  v_party_id uuid;
  v_ar app.finance_ar_open_items;
  v_ap app.finance_ap_open_items;
  v_ar_count integer := 0;
  v_ap_count integer := 0;
  v_batch_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'finance_opening_balance_import' then
    raise exception 'import_export_wrong_schema: job % is not a finance_opening_balance_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'FIN', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks FIN:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-278 (this migration): reuses the SAME FIN:Import pair the check immediately
  -- above already gates on. A strict no-op unless this tenant has itself opted (FIN,
  -- Import) into its own additional_high_risk_actions AND turned MFA on. Note this is
  -- FIN:Import, never the platform-default FIN:Approve tuple -- app.is_high_risk_action's
  -- own fixed set is untouched.
  perform app.assert_current_step_up_authorization(v_job.tenant_id, p_actor_auth_user_id, 'FIN', 'Import');

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

  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 205));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    v_payload := v_row.raw_payload;
    v_type := lower(trim(v_payload ->> 'open_item_type'));

    if v_type = 'ar' then
      if exists (
        select 1 from app.finance_ar_open_items
        where tenant_id = v_job.tenant_id and source_document_type = 'opening_balance' and source_document_id = v_row.id
      ) then
        v_skipped_count := v_skipped_count + 1;
        continue;
      end if;

      -- Re-resolved at write time, not carried from validation: an account can be merged
      -- or deactivated in between, and posting a balance to a merged account would be a
      -- silent misstatement.
      if coalesce(trim(v_payload ->> 'party_tax_id'), '') <> '' then
        select a.id into v_party_id from app.accounts a
        where a.tenant_id = v_job.tenant_id and a.status = 'active'
          and a.normalized_tax_id = app.normalize_prospect_identifier(v_payload ->> 'party_tax_id');
      else
        select a.id into v_party_id from app.accounts a
        where a.tenant_id = v_job.tenant_id and a.status = 'active'
          and a.normalized_legal_name = app.normalize_prospect_identifier(v_payload ->> 'party_legal_name');
      end if;
      if v_party_id is null then
        raise exception 'import_opening_balance_party_not_found: staged row % no longer resolves to exactly one active customer account in tenant %', v_row.row_number, v_job.tenant_id
          using errcode = 'check_violation';
      end if;

      -- The staged row id IS the source document id. See this migration's header: the
      -- existing finance_ar_open_items_source_unique already makes that the idempotency
      -- key, and a second provenance column would be a competing source of truth.
      -- company_id is null: app.jobs is tenant-scoped and carries no company column, and
      -- inventing one would attribute a balance to an org unit the file never named.
      -- app.finance_ar_open_items.company_id is nullable, and
      -- app.resolve_finance_period_for_date resolves tenant-level periods with a null
      -- company -- the same null this row's own validation already checked against.
      v_ar := app.post_finance_ar_open_item(
        v_job.tenant_id, null, v_party_id, 'opening_balance', v_row.id,
        v_payload ->> 'currency', (v_payload ->> 'original_amount')::numeric,
        (v_payload ->> 'document_date')::date, (v_payload ->> 'due_date')::date,
        p_actor_auth_user_id, p_actor_label
      );
      v_ar_count := v_ar_count + 1;

      -- Both halves in the SAME transaction. A subledger row without its GL batch is the
      -- exact state ISS-2026-273 exists to end, so it must not be reachable even by a
      -- commit that fails halfway: if this raises, the open item above rolls back with it.
      perform app.post_finance_opening_balance_batch('ar', v_ar.id, p_actor_auth_user_id, p_actor_label);
      v_batch_count := v_batch_count + 1;
    else
      if exists (
        select 1 from app.finance_ap_open_items
        where tenant_id = v_job.tenant_id and source_document_type = 'opening_balance' and source_document_id = v_row.id
      ) then
        v_skipped_count := v_skipped_count + 1;
        continue;
      end if;

      select m.id into v_party_id from app.master_records m
      where m.tenant_id = v_job.tenant_id and m.master_type_code = 'vendor' and m.code = (v_payload ->> 'party_vendor_code');
      if v_party_id is null then
        raise exception 'import_opening_balance_party_not_found: staged row % names vendor code %, which no longer resolves in tenant %', v_row.row_number, v_payload ->> 'party_vendor_code', v_job.tenant_id
          using errcode = 'check_violation';
      end if;

      v_ap := app.post_finance_ap_open_item(
        v_job.tenant_id, null, v_party_id, 'opening_balance', v_row.id,
        v_payload ->> 'currency', (v_payload ->> 'original_amount')::numeric,
        (v_payload ->> 'document_date')::date, (v_payload ->> 'due_date')::date,
        p_actor_auth_user_id, p_actor_label
      );
      v_ap_count := v_ap_count + 1;

      perform app.post_finance_opening_balance_batch('ap', v_ap.id, p_actor_auth_user_id, p_actor_label);
      v_batch_count := v_batch_count + 1;
    end if;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_finance_opening_balance_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object(
      'status', v_updated.status,
      'ar_open_items_created', v_ar_count,
      'ap_open_items_created', v_ap_count,
      'subledger_batches_posted', v_batch_count,
      'rows_already_committed_skipped', v_skipped_count
    )
  );

  return v_updated;
end;
$$;


-- app.commit_inventory_opening_balance_import_job
create or replace function app.commit_inventory_opening_balance_import_job(
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
  v_warehouse_id uuid;
  v_owner_id uuid;
  v_item_id uuid;
  v_location_id uuid;
  v_key text;
  v_posted_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'inventory_opening_balance_import' then
    raise exception 'import_export_wrong_schema: job % is not an inventory_opening_balance_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-278 (this migration): reuses the SAME OPS:Import pair the check immediately
  -- above already gates on. A strict no-op unless this tenant has itself opted (OPS,
  -- Import) into its own additional_high_risk_actions AND turned MFA on.
  perform app.assert_current_step_up_authorization(v_job.tenant_id, p_actor_auth_user_id, 'OPS', 'Import');

  -- ISS-2026-278's composition, unchanged: a bulk commit is a privileged action, and a
  -- non-interactive caller that supplies no IP is exempt rather than blocked.
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

  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 206));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    v_payload := v_row.raw_payload;

    -- Derived from the staging row, never taken from the file. A file-supplied key would let
    -- a repeated cell silently collapse two real opening balances into one.
    v_key := 'inventory-opening-balance-import:' || v_row.id::text;

    if exists (select 1 from app.inventory_movements where tenant_id = v_job.tenant_id and idempotency_key = v_key) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    -- Re-resolved at write time rather than carried from validation: an item can be
    -- deactivated or a warehouse closed in between, and posting stock against either would
    -- be a silent misstatement of what is actually on the shelf.
    select id into v_warehouse_id from app.warehouses
    where tenant_id = v_job.tenant_id and code = trim(v_payload ->> 'warehouse_code') and status = 'active';
    select a.id into v_owner_id from app.accounts a
    where a.tenant_id = v_job.tenant_id and a.status = 'active' and a.tax_id = trim(v_payload ->> 'owner_account_tax_id');
    select id into v_item_id from app.item_masters
    where tenant_id = v_job.tenant_id and owner_account_id = v_owner_id and code = trim(v_payload ->> 'item_code') and status = 'active';
    select id into v_location_id from app.warehouse_locations
    where warehouse_id = v_warehouse_id and code = trim(v_payload ->> 'location_code');

    if v_warehouse_id is null or v_owner_id is null or v_item_id is null or v_location_id is null then
      raise exception 'import_row_no_longer_resolvable: staging row % no longer resolves to an active warehouse/account/item/location', v_row.id
        using errcode = 'check_violation';
    end if;

    -- The primitive does the writing. Every guard, balance rule and audit event it already
    -- enforces applies to this row unchanged.
    perform app.post_inventory_movement(
      v_job.tenant_id,
      v_warehouse_id,
      'opening_balance',
      'opening_balance',
      v_row.id,
      v_key,
      'Opening balance import, job ' || p_job_id::text,
      jsonb_build_array(jsonb_build_object(
        'owner_account_id', v_owner_id,
        'item_master_id', v_item_id,
        'location_id', v_location_id,
        'uom_code', trim(v_payload ->> 'uom_code'),
        'signed_quantity', (trim(v_payload ->> 'quantity'))::numeric,
        'lot_number', nullif(trim(coalesce(v_payload ->> 'lot_number', '')), ''),
        'serial_number', nullif(trim(coalesce(v_payload ->> 'serial_number', '')), ''),
        'expiry_date', nullif(trim(coalesce(v_payload ->> 'expiry_date', '')), ''),
        'status', lower(coalesce(nullif(trim(v_payload ->> 'status'), ''), 'on_hand'))
      )),
      p_actor_auth_user_id,
      p_actor_label,
      null
    );
    v_posted_count := v_posted_count + 1;
  end loop;

  update app.jobs
  set status = 'completed',
      processed_rows = v_posted_count + v_skipped_count,
      completed_at = now(),
      payload = payload || jsonb_build_object('posted_count', v_posted_count, 'skipped_count', v_skipped_count)
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_inventory_opening_balance_import_job',
    'app.jobs', p_job_id, 'success', null, null,
    jsonb_build_object('posted_count', v_posted_count, 'skipped_count', v_skipped_count, 'allow_partial', coalesce(p_allow_partial, false))
  );

  return v_updated;
end;
$$;


-- app.commit_item_import_job
create or replace function app.commit_item_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.jobs
language plpgsql
security definer
set search_path = 'app', 'public', 'pg_temp'
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_owner_tax text;
  v_owner_name text;
  v_owner_account_id uuid;
  v_item app.item_masters;
  v_created_count integer := 0;
  v_linked_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
  v_constraint_name text;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'item_import' then
    raise exception 'import_export_wrong_schema: job % is not an item_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-278 (unchanged by this migration): reuses the SAME OPS:Import pair the check
  -- immediately above already gates on. A strict no-op unless this tenant has itself opted
  -- (OPS, Import) into its own additional_high_risk_actions AND turned MFA on.
  perform app.assert_current_step_up_authorization(v_job.tenant_id, p_actor_auth_user_id, 'OPS', 'Import');

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

  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 205));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.item_masters where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;
    v_owner_tax := nullif(trim(coalesce(v_payload ->> 'owner_account_tax_id', '')), '');
    v_owner_name := nullif(trim(coalesce(v_payload ->> 'owner_account_legal_name', '')), '');
    v_owner_account_id := null;

    -- Re-resolved here, not carried from validation: an account could have been merged or
    -- deactivated between validate and commit, and the ambiguity check must hold at write
    -- time, not only at check time.
    if v_owner_tax is not null then
      select a.id into v_owner_account_id from app.accounts a
      where a.tenant_id = v_job.tenant_id and a.status = 'active'
        and a.normalized_tax_id = app.normalize_prospect_identifier(v_owner_tax);
      if not found then
        raise exception 'import_owner_account_not_found: staged row % names owner_account_tax_id %, which no longer resolves to exactly one active account in tenant %', v_row.row_number, v_owner_tax, v_job.tenant_id
          using errcode = 'check_violation';
      end if;
    else
      select a.id into v_owner_account_id from app.accounts a
      where a.tenant_id = v_job.tenant_id and a.status = 'active'
        and a.normalized_legal_name = app.normalize_prospect_identifier(v_owner_name);
      if not found then
        raise exception 'import_owner_account_not_found: staged row % names owner_account_legal_name %, which no longer resolves to exactly one active account in tenant %', v_row.row_number, v_owner_name, v_job.tenant_id
          using errcode = 'check_violation';
      end if;
    end if;

    -- The canonical write path -- app.create_item_master is itself idempotent on
    -- (tenant_id, owner_account_id, code) and returns the existing row, so no
    -- unique_violation handler belongs around this call.
    v_item := app.create_item_master(
      v_job.tenant_id,
      v_owner_account_id,
      v_payload ->> 'code',
      v_payload ->> 'name',
      nullif(v_payload ->> 'description', ''),
      v_payload ->> 'base_uom_code',
      coalesce((nullif(v_payload ->> 'lot_controlled', ''))::boolean, false),
      coalesce((nullif(v_payload ->> 'serial_controlled', ''))::boolean, false),
      coalesce((nullif(v_payload ->> 'expiry_controlled', ''))::boolean, false),
      p_actor_auth_user_id,
      p_actor_label
    );

    if v_item.source_import_staging_row_id = v_row.id then
      v_skipped_count := v_skipped_count + 1;
      continue;
    elsif v_item.source_import_staging_row_id is not null then
      -- ISS-2026-277 (this migration): before treating this match as a legitimate link,
      -- refuse it if the resolved item master is under legal hold -- see
      -- app.commit_customer_import_job's identical guard in this same migration for the
      -- full reasoning.
      if app._is_under_legal_hold(v_job.tenant_id, 'operational', 'app.item_masters', v_item.id) then
        raise exception 'import_blocked_legal_hold: item master % is under legal hold, this import commit cannot target it', v_item.id
          using errcode = 'check_violation';
      end if;
      v_linked_count := v_linked_count + 1;
      continue;
    elsif v_item.created_at < v_job.created_at then
      -- An item that predates this job. A legitimate link, deliberately not stamped.
      --
      -- ISS-2026-277 (this migration): the identical guard as the branch above.
      if app._is_under_legal_hold(v_job.tenant_id, 'operational', 'app.item_masters', v_item.id) then
        raise exception 'import_blocked_legal_hold: item master % is under legal hold, this import commit cannot target it', v_item.id
          using errcode = 'check_violation';
      end if;
      v_linked_count := v_linked_count + 1;
      continue;
    end if;

    begin
      update app.item_masters
      set source_import_staging_row_id = v_row.id
      where id = v_item.id
      returning * into v_item;
    exception
      when unique_violation then
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'item_masters_source_import_row_unique' then
          v_skipped_count := v_skipped_count + 1;
          continue;
        end if;
        raise;
    end;

    v_created_count := v_created_count + 1;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_item_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object(
      'status', v_updated.status,
      'item_masters_created', v_created_count,
      'rows_linked_to_existing_item', v_linked_count,
      'rows_already_committed_skipped', v_skipped_count
    )
  );

  return v_updated;
end;
$$;


-- app.commit_leave_opening_balance_import_job
create or replace function app.commit_leave_opening_balance_import_job(
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
  v_leave_type_id uuid;
  v_key text;
  v_loaded_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'leave_opening_balance_import' then
    raise exception 'import_export_wrong_schema: job % is not a leave_opening_balance_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'HRS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-278 (this migration): reuses the SAME HRS:Import pair the check immediately
  -- above already gates on. A strict no-op unless this tenant has itself opted (HRS,
  -- Import) into its own additional_high_risk_actions AND turned MFA on.
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

  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 207));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    v_payload := v_row.raw_payload;
    v_key := 'leave-opening-balance-import:' || v_row.id::text;

    if exists (select 1 from app.leave_balance_ledger where tenant_id = v_job.tenant_id and idempotency_key = v_key) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    select e.master_record_id into v_employee_id
    from app.employees e
    join app.master_records m on m.id = e.master_record_id
    where e.tenant_id = v_job.tenant_id and m.code = trim(v_payload ->> 'employee_number');
    select id into v_leave_type_id from app.leave_types
    where tenant_id = v_job.tenant_id and code = trim(v_payload ->> 'leave_type_code');

    if v_employee_id is null or v_leave_type_id is null then
      raise exception 'import_row_no_longer_resolvable: staging row % no longer resolves to an employee and leave type of this tenant', v_row.id
        using errcode = 'check_violation';
    end if;

    perform app.load_opening_leave_balance(
      v_job.tenant_id,
      v_employee_id,
      v_leave_type_id,
      (trim(v_payload ->> 'units'))::numeric,
      (trim(v_payload ->> 'as_of_date'))::date,
      nullif(trim(coalesce(v_payload ->> 'source_reference', '')), ''),
      v_key,
      p_actor_auth_user_id,
      p_actor_label
    );
    v_loaded_count := v_loaded_count + 1;
  end loop;

  update app.jobs
  set status = 'completed',
      processed_rows = v_loaded_count + v_skipped_count,
      completed_at = now(),
      payload = payload || jsonb_build_object('loaded_count', v_loaded_count, 'skipped_count', v_skipped_count)
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_leave_opening_balance_import_job',
    'app.jobs', p_job_id, 'success', null, null,
    jsonb_build_object('loaded_count', v_loaded_count, 'skipped_count', v_skipped_count, 'allow_partial', coalesce(p_allow_partial, false))
  );

  return v_updated;
end;
$$;


-- app.commit_payroll_loan_cutover_import_job
create or replace function app.commit_payroll_loan_cutover_import_job(
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
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_employee_id uuid;
  v_key text;
  v_loaded_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'payroll_loan_cutover_import' then
    raise exception 'import_export_wrong_schema: job % is not a payroll_loan_cutover_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_payroll_authority('Import', v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Import for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  -- app.issue_payroll_loan itself demands HRS:Approve of ITS caller for every ordinary,
  -- single-loan issuance -- a bulk cutover import is not exempt from that rule just because
  -- it arrives as a file. Checked here, before the loop, so a batch missing only this
  -- authority fails fast with one clear reason instead of failing loan-by-loan mid-commit.
  if not app.check_payroll_authority('Approve', v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-278 (this migration): reuses the SAME HRS:Import pair app.check_payroll_
  -- authority('Import', ...) immediately above already gates on -- deliberately NOT
  -- HRS:Approve (see this section's own header comment). A strict no-op unless this tenant
  -- has itself opted (HRS, Import) into its own additional_high_risk_actions AND turned MFA
  -- on.
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

  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 208));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    v_payload := v_row.raw_payload;
    v_key := 'payroll-loan-cutover-import:' || v_row.id::text;

    if exists (select 1 from app.payroll_loans where tenant_id = v_job.tenant_id and source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    select e.master_record_id into v_employee_id
    from app.employees e
    join app.master_records m on m.id = e.master_record_id
    where e.tenant_id = v_job.tenant_id and m.code = trim(v_payload ->> 'employee_number');

    if v_employee_id is null then
      raise exception 'import_row_no_longer_resolvable: staging row % no longer resolves to an active employee of this tenant', v_row.id
        using errcode = 'check_violation';
    end if;

    perform app.issue_payroll_loan(
      v_job.tenant_id,
      v_employee_id,
      (trim(v_payload ->> 'principal_amount'))::numeric,
      nullif(trim(coalesce(v_payload ->> 'currency', '')), ''),
      (trim(v_payload ->> 'installment_amount'))::numeric,
      (trim(v_payload ->> 'term_count'))::integer,
      true,
      (trim(v_payload ->> 'remaining_installments'))::integer,
      nullif(trim(coalesce(v_payload ->> 'notes', '')), ''),
      p_actor_auth_user_id,
      p_actor_label,
      v_row.id
    );
    v_loaded_count := v_loaded_count + 1;
  end loop;

  update app.jobs
  set status = 'completed',
      processed_rows = v_loaded_count + v_skipped_count,
      completed_at = now(),
      payload = payload || jsonb_build_object('loaded_count', v_loaded_count, 'skipped_count', v_skipped_count)
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_payroll_loan_cutover_import_job',
    'app.jobs', p_job_id, 'success', null, null,
    jsonb_build_object('loaded_count', v_loaded_count, 'skipped_count', v_skipped_count, 'allow_partial', coalesce(p_allow_partial, false))
  );

  return v_updated;
end;
$$;


-- app.commit_timesheet_import_job
create or replace function app.commit_timesheet_import_job(
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
  v_employee app.employees;
  v_job_order_id uuid;
  v_shipment_order_id uuid;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_failed_count integer := 0;
  v_ignore app.timesheet_entries;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
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

  -- ISS-2026-278 (this migration): reuses the SAME HRS:Import pair the check immediately
  -- above already gates on. A strict no-op unless this tenant has itself opted (HRS,
  -- Import) into its own additional_high_risk_actions AND turned MFA on.
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


-- app.commit_vendor_import_job
create or replace function app.commit_vendor_import_job(
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
  v_legal_name text;
  v_trade_name text;
  v_reg_number text;
  v_reg_number_normalized text;
  v_profile app.vendor_profiles;
  v_dupe record;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_flagged_count integer := 0;
  v_updated app.jobs;
  v_constraint_name text;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'vendor_import' then
    raise exception 'import_export_wrong_schema: job % is not a vendor_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- BOTH gates, mirroring app.commit_vendor_rate_import_job. PRC:Import alone must never
  -- be sufficient to create canonical vendor identities in bulk, and the underlying
  -- app.create_vendor_profile_draft still separately enforces its own PRC:Create gate on
  -- every single row -- the bulk path is strictly additive to the single-vendor path's
  -- own authority, never a way around it.
  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'PRC', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-278 (this migration): reuses the SAME PRC:Import pair the check immediately
  -- above already gates on. A strict no-op unless this tenant has itself opted (PRC,
  -- Import) into its own additional_high_risk_actions AND turned MFA on.
  perform app.assert_current_step_up_authorization(v_job.tenant_id, p_actor_auth_user_id, 'PRC', 'Import');

  -- ISS-2026-278 shape, adopted at birth rather than as a later remediation.
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

  -- Job-scoped advisory lock, resolved and taken before any staging row is read,
  -- serializing any concurrent or replayed commit call on this SAME job.
  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 205));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.vendor_profiles where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;
    v_legal_name := v_payload ->> 'legal_name';
    v_trade_name := nullif(v_payload ->> 'trade_name', '');
    v_reg_number := nullif(v_payload ->> 'business_registration_number', '');

    -- The canonical write path -- never a direct INSERT (Prompt 131 §24). Deliberately
    -- WITHOUT a unique_violation handler: see this migration's header. No unique_violation
    -- escaping this call is ever a safe replay, because create_vendor_profile_draft's own
    -- idempotency-key path RETURNS the existing row instead of raising. Anything that does
    -- reach here is a genuine master-record code collision or an idempotency key reused
    -- for a different legal_name -- both must abort the whole commit so the surrounding
    -- transaction rolls back and the job is never marked completed with a dropped row.
    v_profile := app.create_vendor_profile_draft(
      v_job.tenant_id,
      v_legal_name,
      v_trade_name,
      nullif(v_payload ->> 'legal_entity_type', ''),
      v_reg_number,
      nullif(v_payload ->> 'vendor_category', ''),
      nullif(v_payload ->> 'payment_term_days', '')::integer,
      'bulk_import',
      'vendor-import:' || v_row.id::text,
      p_actor_auth_user_id,
      p_actor_label
    );

    -- Provenance stamp. Explicit about every outcome -- never a `where ... is null`
    -- clause that would update zero rows and report success.
    if v_profile.source_import_staging_row_id = v_row.id then
      -- Already committed by this exact staged row (an idempotency-key replay that
      -- returned the row this same adapter previously created).
      v_skipped_count := v_skipped_count + 1;
      continue;
    elsif v_profile.source_import_staging_row_id is not null then
      raise exception 'import_vendor_profile_already_bound: staged row % resolved to vendor profile %, which is already bound to a different staged row (%) -- refusing to rebind', v_row.row_number, v_profile.master_record_id, v_profile.source_import_staging_row_id
        using errcode = 'check_violation';
    end if;

    begin
      update app.vendor_profiles
      set source_import_staging_row_id = v_row.id
      where master_record_id = v_profile.master_record_id
      returning * into v_profile;
    exception
      when unique_violation then
        -- The ONLY safe-replay case in this adapter: a concurrent call committed this
        -- exact staged row between the exists-check above and this UPDATE. Any other
        -- unique_violation is a real failure and must abort the whole commit.
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'vendor_profiles_source_import_row_unique' then
          v_skipped_count := v_skipped_count + 1;
          continue;
        end if;
        raise;
    end;

    v_created_count := v_created_count + 1;

    -- Duplicate sweep 1: trigram name/trade-name similarity, the detector PRC-251 already
    -- built and left with no bulk caller. Flagged, never blocking -- the row is created
    -- either way, and app.submit_vendor_profile_for_review's own existing gate then
    -- refuses to advance it until a human decides the pairing.
    for v_dupe in
      select d.master_record_id, d.similarity_score
      from app.search_vendor_duplicate_candidates(v_job.tenant_id, v_legal_name, v_trade_name, p_actor_auth_user_id, 5) d
      where d.master_record_id <> v_profile.master_record_id
    loop
      if not exists (
        select 1 from app.vendor_duplicate_candidates
        where source_master_record_id = v_profile.master_record_id and candidate_master_record_id = v_dupe.master_record_id
      ) then
        perform app.flag_vendor_duplicate_candidate(
          v_profile.master_record_id, v_dupe.master_record_id,
          'bulk_import: name/trade-name similarity against an existing vendor in this tenant',
          v_dupe.similarity_score::numeric, p_actor_auth_user_id, p_actor_label
        );
        v_flagged_count := v_flagged_count + 1;
      end if;
    end loop;

    -- Duplicate sweep 2: an identical business registration number (NPWP/NIB). Nothing in
    -- the schema constrains this column, and a trigram name score can miss it entirely
    -- ("PT Contoso Logistik" vs. "Contoso Trucking Indonesia" with one registration
    -- number between them). Compared with punctuation and case normalized away, since a
    -- spreadsheet's formatting of a registration number is not a business fact.
    if v_reg_number is not null then
      v_reg_number_normalized := upper(regexp_replace(v_reg_number, '[^0-9A-Za-z]', '', 'g'));
      if v_reg_number_normalized <> '' then
        for v_dupe in
          select vp.master_record_id
          from app.vendor_profiles vp
          where vp.tenant_id = v_job.tenant_id
            and vp.master_record_id <> v_profile.master_record_id
            and vp.business_registration_number is not null
            and upper(regexp_replace(vp.business_registration_number, '[^0-9A-Za-z]', '', 'g')) = v_reg_number_normalized
        loop
          if not exists (
            select 1 from app.vendor_duplicate_candidates
            where source_master_record_id = v_profile.master_record_id and candidate_master_record_id = v_dupe.master_record_id
          ) then
            perform app.flag_vendor_duplicate_candidate(
              v_profile.master_record_id, v_dupe.master_record_id,
              'bulk_import: identical business registration number after normalizing punctuation and case',
              1.0, p_actor_auth_user_id, p_actor_label
            );
            v_flagged_count := v_flagged_count + 1;
          end if;
        end loop;
      end if;
    end if;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_vendor_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object(
      'status', v_updated.status,
      'vendor_profiles_created', v_created_count,
      'rows_already_committed_skipped', v_skipped_count,
      'duplicate_candidates_flagged', v_flagged_count
    )
  );

  return v_updated;
end;
$$;


-- app.decide_leave_request
create or replace function app.decide_leave_request(p_request_step_id uuid, p_decision text, p_reason text, p_override_coverage boolean, p_actor_auth_user_id uuid, p_actor_label text)
returns app.leave_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_approval_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_request app.leave_requests;
  v_type app.leave_types;
  v_lock_key bigint;
  v_current numeric;
  v_day date;
  v_leave_scheduled_count integer;
  v_leave_min_headcount integer;
  v_override_decision app.rbac_decision;
  v_session_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id using errcode = 'no_data_found';
  end if;
  select * into v_approval_request from app.approval_requests where id = v_step.request_id;
  if v_approval_request.entity_type <> 'leave_request' or v_approval_request.entity_id is null then
    raise exception 'not_a_leave_request_approval: approval request % is not a leave/permit/business-trip request approval', v_approval_request.id using errcode = 'check_violation';
  end if;

  select * into v_request from app.leave_requests where id = v_approval_request.entity_id;
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id using errcode = 'no_data_found';
  end if;
  select * into v_type from app.leave_types where id = v_request.leave_type_id;

  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_approval_request.id;

  if v_updated_request.status = 'approved' then
    v_day := v_request.date_from;
    while v_day <= v_request.date_to loop
      select v_scheduled_count, v_min_headcount into v_leave_scheduled_count, v_leave_min_headcount from app._leave_coverage_impact(v_request.tenant_id, v_request.employee_id, v_day);
      if v_leave_min_headcount is not null and (v_leave_scheduled_count - 1) < v_leave_min_headcount then
        if not coalesce(p_override_coverage, false) then
          raise exception 'coverage_below_minimum: approving this leave would drop % coverage below the required minimum of % on %', v_request.employee_id, v_leave_min_headcount, v_day
            using errcode = 'check_violation';
        end if;
        v_override_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Override');
        if not v_override_decision.allowed then
          raise exception 'insufficient_authority: overriding a coverage-below-minimum block requires HRS:Override (%) for tenant %', v_override_decision.reason, v_request.tenant_id
            using errcode = 'insufficient_privilege';
        end if;
      end if;
      v_day := v_day + 1;
    end loop;

    if v_type.requires_balance then
      v_lock_key := hashtextextended('leave_balance:' || v_request.employee_id::text || ':' || v_request.leave_type_id::text, 0);
      perform pg_advisory_xact_lock(v_lock_key);
      v_current := app.get_employee_leave_balance(v_request.tenant_id, v_request.employee_id, v_request.leave_type_id, current_date);
      if v_current - v_request.total_units < 0 then
        declare
          v_policy app.leave_type_policy_versions;
        begin
          select * into v_policy from app.leave_type_policy_versions where id = v_request.policy_version_id;
          if not coalesce(v_policy.negative_balance_allowed, false) then
            raise exception 'insufficient_balance: available balance % is less than the % unit(s) requested', v_current, v_request.total_units
              using errcode = 'check_violation';
          end if;
        end;
      end if;
      insert into app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, event_type, units, effective_date, policy_version_id, source_request_id, idempotency_key, created_by)
      values (v_request.tenant_id, v_request.employee_id, v_request.leave_type_id, 'request_debit', -v_request.total_units, current_date, v_request.policy_version_id, v_request.id, v_request.id::text || ':debit', p_actor_label);
    end if;

    update app.leave_requests
    set status = 'approved', decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason
    where id = v_approval_request.entity_id and approval_request_id = v_approval_request.id and status = 'pending_approval'
    returning * into v_request;
    if not found then
      raise exception 'leave_request_no_longer_applicable: request % is no longer awaiting decision on approval request % (concurrently cancelled)', v_approval_request.entity_id, v_approval_request.id
        using errcode = 'serialization_failure';
    end if;

    -- Batch 278-280 Tier C fix (data-consistency-integration-boundary, HIGH,
    -- live-reproduced): re-run attendance exception detection for every
    -- session that already exists in this now-approved request''s own date
    -- range -- closes the reverse-ordering gap (a clock-in/exception
    -- recorded BEFORE this approval) the forward direction (20260730940000)
    -- already handled. Bounded to the request''s own already-<=366-day range.
    v_day := v_request.date_from;
    while v_day <= v_request.date_to loop
      select s.id into v_session_id from app.attendance_sessions s
      where s.tenant_id = v_request.tenant_id and s.employee_id = v_request.employee_id and s.work_date = v_day;
      if found then
        perform app._recalculate_session_exceptions(v_session_id);
      end if;
      v_day := v_day + 1;
    end loop;

    if v_type.category = 'leave' and v_request.date_from <= current_date and v_request.date_to >= current_date then
      declare
        v_current_employee app.employees;
      begin
        select * into v_current_employee from app.employees where master_record_id = v_request.employee_id for update;
        if v_current_employee.lifecycle_status = 'active' then
          -- Batch 278-280 Tier C fix (correctness-authority-bar-mismatch,
          -- CRITICAL, live-reproduced): calls the shared internal engine
          -- directly (app._transition_employee_leave_status), never the
          -- HRS:Edit-gated app.start_employee_leave wrapper -- this
          -- function''s own authority to decide THIS step was already
          -- established above by app.decide_approval_step (PLT-123 eligible-
          -- approver identity), which does not imply and must not require
          -- HRS:Edit too.
          perform app._transition_employee_leave_status(v_request.employee_id, v_current_employee.record_version, 'on_leave', 'leave_request:' || v_request.id::text, p_actor_auth_user_id, p_actor_label);
        end if;
      end;
    end if;
  elsif v_updated_request.status = 'rejected' then
    update app.leave_requests
    set status = 'rejected', decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason
    where id = v_approval_request.entity_id and approval_request_id = v_approval_request.id and status = 'pending_approval'
    returning * into v_request;
    if not found then
      raise exception 'leave_request_no_longer_applicable: request % is no longer awaiting decision on approval request % (concurrently cancelled)', v_approval_request.entity_id, v_approval_request.id
        using errcode = 'serialization_failure';
    end if;
  else
    select * into v_request from app.leave_requests where id = v_approval_request.entity_id;
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_reason is already durably
  -- stored above in app.leave_requests.decided_reason (column-restricted,
  -- HRS_REGISTRY hrs:leave_requests.reason) -- never also duplicated into
  -- app.audit_logs.reason. app.leave_request_audit_projection's own
  -- jsonb after_value snapshot was already correctly non-pii (HRT-280) --
  -- only this separate scalar p_reason vector needed closing.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_leave_request',
    'app.leave_requests', v_request.id, 'success', null, null, app.leave_request_audit_projection(v_request)
  );

  return v_request;
end;
$$;


-- app.decide_payroll_reimbursement_request
create or replace function app.decide_payroll_reimbursement_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_reimbursement_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.payroll_reimbursement_requests;
begin
  select * into v_request from app.payroll_reimbursement_requests where id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_reimbursement_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Approve', v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  -- Taxonomy C-18: self-approval blocked structurally, not merely by
  -- convention -- the requester can never decide their own request even
  -- while separately holding HRS:Approve.
  if v_request.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own reimbursement request' using errcode = 'insufficient_privilege';
  end if;
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % must be approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decided_reason is null or length(trim(p_decided_reason)) = 0 then
    raise exception 'reason_required: a reason is required to decide a reimbursement request' using errcode = 'check_violation';
  end if;
  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'pending_approval' then
    raise exception 'invalid_transition: request % is % not pending_approval', p_request_id, v_request.status using errcode = 'check_violation';
  end if;

  update app.payroll_reimbursement_requests
  set status = case p_decision when 'approve' then 'approved' else 'rejected' end,
      decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: concurrent update detected for request %', p_request_id using errcode = 'serialization_failure';
  end if;

  -- Tier C fix 1: p_decided_reason -- LIVE-CONFIRMED to be able to carry
  -- medical/personal-data-shaped free text (integration lens's exact
  -- reproduction) -- no longer routed into the audit trail unredacted.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_payroll_reimbursement_request',
    'app.payroll_reimbursement_requests', v_request.id, 'success', null, null, jsonb_build_object('status', v_request.status)
  );

  return v_request;
end;
$$;


-- app.end_payroll_component_assignment
create or replace function app.end_payroll_component_assignment(p_assignment_id uuid, p_expected_version integer, p_effective_to date, p_end_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_employee_component_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_assignment app.payroll_employee_component_assignments;
begin
  select * into v_assignment from app.payroll_employee_component_assignments where id = p_assignment_id for update;
  if not found or not app.has_active_tenant_membership(v_assignment.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_assignment_not_found: %', p_assignment_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Edit', v_assignment.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_assignment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_assignment.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_assignment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_assignment.status <> 'active' then
    raise exception 'invalid_transition: assignment % is already %', p_assignment_id, v_assignment.status using errcode = 'check_violation';
  end if;
  if p_end_reason is null or length(trim(p_end_reason)) = 0 then
    raise exception 'reason_required: a reason is required to end an assignment' using errcode = 'check_violation';
  end if;

  update app.payroll_employee_component_assignments
  set status = 'ended', effective_to = coalesce(p_effective_to, current_date), end_reason = p_end_reason
  where id = p_assignment_id and record_version = p_expected_version
  returning * into v_assignment;
  if not found then
    raise exception 'stale_version: concurrent update detected for assignment %', p_assignment_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'end_payroll_component_assignment',
    'app.payroll_employee_component_assignments', v_assignment.id, 'success', null, null, null
  );

  return v_assignment;
end;
$$;


-- app.freeze_payroll_period_inputs
create or replace function app.freeze_payroll_period_inputs(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_periods
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.payroll_periods;
  v_employee record;
  v_count integer := 0;
  v_advanced_run_count integer;
begin
  select * into v_period from app.payroll_periods where id = p_period_id for update;
  if not found or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Edit', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_period.status not in ('open', 'input_frozen') then
    raise exception 'invalid_transition: period % is %, only open/input_frozen may (re)freeze inputs', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  -- Tier C fix (correctness lens Finding 2, LIVE-CONFIRMED): re-freezing
  -- while any run for this period has already advanced past draft must be
  -- cleanly rejected here, BEFORE the snapshot DELETE below -- not left to
  -- surface as an incidental raw FK-violation once a run's own
  -- input_snapshot_id reference collides with it. Mirrors
  -- app.reopen_payroll_period_inputs' own identical, pre-existing guard.
  select count(*) into v_advanced_run_count from app.payroll_runs
    where payroll_period_id = p_period_id and status not in ('draft', 'cancelled');
  if v_advanced_run_count > 0 then
    raise exception 'payroll_period_has_advanced_run: period % has a run already past draft -- cancel it first' , p_period_id
      using errcode = 'check_violation';
  end if;

  delete from app.payroll_input_snapshots where payroll_period_id = p_period_id;

  for v_employee in
    select * from app.employees where tenant_id = v_period.tenant_id and lifecycle_status in ('active', 'on_leave')
      and (v_period.org_unit_id is null or company_org_unit_id = v_period.org_unit_id or branch_org_unit_id = v_period.org_unit_id)
  loop
    perform app._build_payroll_input_snapshot_for_employee(
      v_period.tenant_id, p_period_id, v_employee.master_record_id, v_period.period_start, v_period.period_end, p_actor_label
    );
    v_count := v_count + 1;
  end loop;

  update app.payroll_periods
  set status = 'input_frozen', frozen_by = p_actor_label, frozen_at = now(), frozen_employee_count = v_count, reopen_reason = null
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  if not found then
    raise exception 'stale_version: concurrent update detected for period %', p_period_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'freeze_payroll_period_inputs',
    'app.payroll_periods', v_period.id, 'success', null, null, jsonb_build_object('employee_count', v_count)
  );

  return v_period;
end;
$$;


-- app.list_talent_pool_members
create or replace function app.list_talent_pool_members(p_pool_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, pool_id uuid, employee_id uuid, employee_full_name text, status text, added_reason text, added_at timestamptz, record_version integer)
language plpgsql
stable security definer
set search_path to 'app', 'pg_temp'
as $$
declare
  v_pool app.talent_pools;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_pool from app.talent_pools p where p.id = p_pool_id;
  if not found or not app.has_active_tenant_membership(v_pool.tenant_id, p_actor_auth_user_id) then
    raise exception 'talent_pool_not_found: %', p_pool_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_pool.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_pool.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select m.id, m.pool_id, m.employee_id, e.full_name, m.status, m.added_reason, m.added_at, m.record_version
  from app.talent_pool_members m
  join app.employees e on e.master_record_id = m.employee_id
  where m.pool_id = p_pool_id
  order by m.added_at desc;
end;
$$;


-- app.reopen_payroll_period_inputs
create or replace function app.reopen_payroll_period_inputs(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_periods
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.payroll_periods;
  v_advanced_run_count integer;
begin
  select * into v_period from app.payroll_periods where id = p_period_id for update;
  if not found or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Override', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to reopen frozen inputs' using errcode = 'check_violation';
  end if;
  if v_period.status <> 'input_frozen' then
    raise exception 'invalid_transition: period % is %, only input_frozen may reopen', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_advanced_run_count from app.payroll_runs
    where payroll_period_id = p_period_id and status not in ('draft', 'cancelled');
  if v_advanced_run_count > 0 then
    raise exception 'payroll_period_has_advanced_run: period % has a run already past draft -- cancel it first' , p_period_id
      using errcode = 'check_violation';
  end if;

  update app.payroll_periods set status = 'open', reopen_reason = p_reason where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  if not found then
    raise exception 'stale_version: concurrent update detected for period %', p_period_id using errcode = 'serialization_failure';
  end if;

  -- Tier C fix 1: p_reason is no longer routed into capture_audit_event's
  -- unredacted `reason` column (was readable by any tenant_admin via
  -- app.query_audit_logs regardless of HRS:View payroll/Override).
  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_payroll_period_inputs',
    'app.payroll_periods', v_period.id, 'success', null, null, null
  );

  return v_period;
end;
$$;


-- app.request_payroll_run_calculation_cancellation
create or replace function app.request_payroll_run_calculation_cancellation(p_run_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
  v_job app.jobs;
begin
  select * into v_run from app.payroll_runs where id = p_run_id;
  if not found or not app.has_active_tenant_membership(v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Edit', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_run.status <> 'calculating' then
    raise exception 'payroll_run_not_calculating: run % is % -- only an in-flight calculation (status=calculating) may be requested for cancellation', p_run_id, v_run.status
      using errcode = 'check_violation';
  end if;

  select * into v_job from app.jobs
    where tenant_id = v_run.tenant_id and job_type = 'payroll_calculation' and status = 'in_progress'
      and (payload ->> 'run_id')::uuid = p_run_id
    order by created_at desc limit 1
    for update;
  if not found then
    raise exception 'payroll_calculation_job_not_in_progress: no in-progress calculation job found for run %', p_run_id using errcode = 'no_data_found';
  end if;

  update app.jobs set status = 'cancelling', cancel_reason = 'requested by ' || p_actor_label where job_id = v_job.job_id
  returning * into v_job;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_payroll_run_calculation_cancellation',
    'app.jobs', v_job.job_id, 'success', null, null, jsonb_build_object('payroll_run_id', p_run_id)
  );

  return v_job;
end;
$$;


-- app.reschedule_training_enrollment
create or replace function app.reschedule_training_enrollment(p_enrollment_id uuid, p_new_session_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
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
  -- ISS-2026-146: this row is reached by FK from an already-guarded parent, so its own
  -- lookup had no not-found branch to fold the membership check into. A new guard, raising
  -- the identical generic message/errcode this function's own sibling not-found check one
  -- statement above already raises, so a zero-membership caller cannot tell the two apart.
  if not found or not app.has_active_tenant_membership(v_enrollment.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;

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


-- app.resolve_payroll_exception
create or replace function app.resolve_payroll_exception(p_exception_id uuid, p_resolution_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.payroll_exceptions;
begin
  select * into v_exception from app.payroll_exceptions where id = p_exception_id for update;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Edit', v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_exception.status <> 'open' then
    raise exception 'invalid_transition: exception % is already %', p_exception_id, v_exception.status using errcode = 'check_violation';
  end if;
  if p_resolution_note is null or length(trim(p_resolution_note)) = 0 then
    raise exception 'reason_required: a resolution note is required' using errcode = 'check_violation';
  end if;

  update app.payroll_exceptions set status = 'resolved', resolved_by = p_actor_label, resolved_at = now(), resolution_note = p_resolution_note
  where id = p_exception_id
  returning * into v_exception;

  update app.payroll_runs set exception_count = greatest(0, exception_count - 1) where id = v_exception.payroll_run_id;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_payroll_exception',
    'app.payroll_exceptions', v_exception.id, 'success', null, null, null
  );

  return v_exception;
end;
$$;


-- app.waive_payroll_exception
create or replace function app.waive_payroll_exception(p_exception_id uuid, p_resolution_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.payroll_exceptions;
begin
  select * into v_exception from app.payroll_exceptions where id = p_exception_id for update;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Override', v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_exception.status <> 'open' then
    raise exception 'invalid_transition: exception % is already %', p_exception_id, v_exception.status using errcode = 'check_violation';
  end if;
  if p_resolution_note is null or length(trim(p_resolution_note)) = 0 then
    raise exception 'reason_required: a resolution note is required to waive an exception' using errcode = 'check_violation';
  end if;

  update app.payroll_exceptions set status = 'waived', resolved_by = p_actor_label, resolved_at = now(), resolution_note = p_resolution_note
  where id = p_exception_id
  returning * into v_exception;

  update app.payroll_runs set exception_count = greatest(0, exception_count - 1) where id = v_exception.payroll_run_id;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'waive_payroll_exception',
    'app.payroll_exceptions', v_exception.id, 'success', null, null, null
  );

  return v_exception;
end;
$$;
