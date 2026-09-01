-- ISS-2026-278 (docs/runtime/KNOWN_ISSUES.md), resumed: at the 2026-08-27 pass
-- (`20260826190000_harden_import_commit_ip_allowlist_gating.sql`) this entry was closed
-- IP-allowlist-only, explicitly declining step-up MFA with the stated reason "forcing
-- mandatory MFA step-up on every bulk import commit, including routine, non-financial ones
-- (e.g. attendance_device_import), risks over-restricting a legitimate operational workflow
-- without dedicated UX review."
--
-- That objection no longer holds, and this migration does not re-litigate it -- it composes
-- an already-shipped, already-proven mechanism that did not exist on 2026-08-27.
--
-- ===========================================================================
-- Why the original objection is moot: IAE-027 is a strict, tenant-owned opt-in
-- ===========================================================================
--
-- `app.assert_current_step_up_authorization` (IAE-027,
-- `20260807100000_create_intelligence_enterprise_mfa_session_controls.sql`) is a no-op
-- unless `app.is_high_risk_action(tenant, module, action)` returns true for the EXACT
-- tuple passed. `app.is_high_risk_action` returns true only for (a) a fixed, unrelated
-- platform-default set (`AI:Approve`, `IAM:Configure`, `SEC:Configure`, `SEC:Approve`,
-- `FIN:Approve`, `HRS:Approve`, `INTHUB:Configure` -- none of which is any import-commit
-- tuple used below), or (b) a tuple the TENANT ITSELF has added to its own
-- `app.mfa_tenant_policies.additional_high_risk_actions` (`app.set_mfa_tenant_policy`,
-- itself gated on `SEC:Configure`). This migration adds no platform-default tuple and does
-- not touch `app.is_high_risk_action`. A tenant that never configures its own policy --
-- every tenant in every existing fixture, and every tenant on the live project today --
-- sees IDENTICAL behavior after this migration as before it. Only a tenant that
-- deliberately opts a specific (module, `Import`) pair into its own policy AND turns MFA on
-- gets elevated authorization on that specific import-commit action. Live-verified against
-- a fresh migrated database in this checkpoint's own db-tests run (see the new fixture
-- appended to `scripts/db-tests/import-export.sql`) -- not asserted from the mechanism's own
-- header alone.
--
-- This exact composition -- one `perform app.assert_current_step_up_authorization(tenant,
-- actor, module, action)` call immediately after the existing authority check, no widening
-- of `is_high_risk_action` -- was used twice more THIS SAME DAY for an identical reasoning
-- shape: `20260901080000_create_customer_portal_legal_identity_change_requests.sql` and
-- `20260901090000_create_customer_portal_contact_change_requests.sql`, both gating their own
-- `decide_*` RPC on `app.assert_current_step_up_authorization(tenant, actor, 'COM',
-- 'Approve')` immediately after their own `COM:Approve` check. This migration mirrors that
-- established placement precedent, not a new pattern.
--
-- ===========================================================================
-- Scope: re-verified live, NOT the 5 the 2026-08-27 pass named -- the live list has grown
-- to 12
-- ===========================================================================
--
-- Live-queried (`pg_proc`, via `pg_get_function_identity_arguments` and a
-- `proname ~ '^commit_.*import_job$'` sweep against a freshly migrated database) before
-- writing this file, deliberately NOT assumed from the 2026-08-27 entry's own text: EVERY
-- `app.commit_*_import_job`-shaped function already carries a trailing `p_client_ip`
-- parameter today, and that set has grown from 5 to **12** since 2026-08-27. The original 5
-- (`app.commit_import_job`, `app.commit_employee_import_job`,
-- `app.commit_attendance_device_import_job`, `app.commit_timesheet_import_job`,
-- `app.commit_vendor_rate_import_job`) are joined by 7 domain adapters that shipped since,
-- each carrying the identical `p_client_ip` composition AT BIRTH (several of their own
-- comments say so explicitly, e.g. `app.commit_vendor_import_job`: "ISS-2026-278 shape,
-- adopted at birth rather than as a later remediation"): `app.commit_vendor_import_job`,
-- `app.commit_customer_import_job`, `app.commit_item_import_job`,
-- `app.commit_finance_opening_balance_import_job`,
-- `app.commit_inventory_opening_balance_import_job`,
-- `app.commit_leave_opening_balance_import_job`, `app.commit_payroll_loan_cutover_import_
-- job`. The task framing that started this migration named "5" and explicitly said not to
-- assume that count still held -- it does not, and this migration covers the real, current
-- list of 12, not the stale count. `app.create_import_export_job` and `app.stage_import_
-- rows` remain untouched, per this entry's own disclosed staging/commit boundary.
--
-- ===========================================================================
-- Placement and the (module, action) tuple used per function -- reusing existing
-- vocabulary, inventing nothing
-- ===========================================================================
--
-- 10 of the 11 domain adapters already gate their own commit on
-- `app.evaluate_permission(actor, tenant, <module>, 'Import')`:
-- `app.commit_employee_import_job`/`app.commit_attendance_device_import_job`/
-- `app.commit_timesheet_import_job`/`app.commit_leave_opening_balance_import_job` on
-- `HRS:Import`; `app.commit_vendor_rate_import_job`/`app.commit_vendor_import_job` on
-- `PRC:Import`; `app.commit_customer_import_job` on `COM:Import`;
-- `app.commit_item_import_job`/`app.commit_inventory_opening_balance_import_job` on
-- `OPS:Import`; `app.commit_finance_opening_balance_import_job` on `FIN:Import`. This
-- migration adds `perform app.assert_current_step_up_authorization(tenant, actor, <the SAME
-- module>, 'Import')` immediately after that existing check (before the existing
-- IP-allowlist check, mirroring `20260815000000`'s own authority -> step-up -> IP ordering
-- exactly) -- the same pair the function already gates on, never a new one.
--
-- `app.commit_payroll_loan_cutover_import_job` is the one adapter that gates through a
-- different helper, `app.check_payroll_authority`, called TWICE: once with `'Import'`
-- (mapping to `HRS:Import`, per its own error text) and once with `'Approve'` (mapping to
-- `HRS:Approve`, because `app.issue_payroll_loan` itself separately demands that authority
-- of every single-loan issuance and a bulk cutover is not exempt). `HRS:Approve` is one of
-- `app.is_high_risk_action`'s 7 fixed PLATFORM-DEFAULT tuples -- composing step-up on THAT
-- pair would not be a tenant opt-in at all, it would immediately start requiring step-up for
-- every tenant with `tenant_wide_required = true` regardless of any `additional_high_risk_
-- actions` list, breaking this entire migration's own "strict no-op by default" premise for
-- this one function. This migration therefore composes on `HRS:Import` here too --
-- consistent with the vocabulary every other adapter in this migration uses ("commit a bulk
-- import" is the action this entry is about; the additional `Approve` re-check is that one
-- adapter's own compounding domain rule, not the action being step-up-gated), and never on
-- `HRS:Approve`. `app.is_high_risk_action` itself is untouched by this migration either way.
--
-- `app.commit_import_job` (the generic framework path) is the one function with no fixed
-- module at all: unlike every domain adapter, a single job may target ANY registered import
-- schema, and this function carries no `evaluate_permission` call of its own -- only the
-- ordinary `app.check_import_export_job_authority` tenant-membership check. There is
-- therefore no single existing (module, action) pair on THIS function to reuse verbatim.
-- Rather than invent one, this migration resolves the SAME `Import`-action vocabulary every
-- adapter above already uses, keyed off the job's own already-persisted, foreign-key-
-- enforced domain classification: `app.import_export_schemas.owner_primitive_code`
-- (verified live: every one of the currently-registered schema codes used by a real adapter
-- has an `owner_primitive_code` of `COM`, `FIN`, `HRS`, `OPS`, or `PRC`, each of which
-- already carries a real `Import` permission row; a test-only schema registered with an
-- arbitrary code, as `scripts/db-tests/import-export.sql` itself does, resolves to a module
-- string `app.is_high_risk_action` simply finds no tenant policy for -- itself a correct
-- no-op, never an error). `app.jobs.import_export_schema_code` is FK-constrained against
-- `app.import_export_schemas.code` and, in practice, always populated for a job that
-- reached creation via `app.create_import_export_job` (that function calls `app.resolve_
-- import_export_schema_columns`, which raises before insertion if the schema code does not
-- resolve) -- so this lookup resolves for every real job reaching commit. The `if v_schema_
-- owner_module is not null` guard below is defense-in-depth only, never a silent skip of a
-- real case: if it somehow could not resolve, this migration does not newly deny (no
-- regression versus before this migration), it simply cannot apply a tuple it has no
-- legitimate value for.
--
-- ===========================================================================
-- The recurrence class this migration avoids (`ISS-2026-260`'s own self-caught finding,
-- and the class `20260830100000`/`20260831290000` had to correct after it)
-- ===========================================================================
--
-- Every one of the 12 `CREATE OR REPLACE FUNCTION` statements below restates `language
-- plpgsql` and, live-verified per function via `pg_proc.prosecdef`/`proconfig` before
-- writing this file (never assumed from an on-disk migration file that may be stale):
--   - `app.commit_import_job`: SECURITY INVOKER (no `SECURITY DEFINER` clause), NO
--     `search_path` override -- its original, unchanged shape since
--     `20260719170000_create_import_export_job_framework.sql`, preserved exactly, not a
--     bug to "fix" here.
--   - `app.commit_employee_import_job`, `app.commit_timesheet_import_job`: SECURITY
--     DEFINER, `set search_path = app, pg_temp`.
--   - Every other one of the 10 remaining domain adapters (`app.commit_attendance_device_
--     import_job`, `app.commit_vendor_rate_import_job`, `app.commit_vendor_import_job`,
--     `app.commit_customer_import_job`, `app.commit_item_import_job`, `app.commit_finance_
--     opening_balance_import_job`, `app.commit_inventory_opening_balance_import_job`,
--     `app.commit_leave_opening_balance_import_job`, `app.commit_payroll_loan_cutover_
--     import_job`): SECURITY DEFINER, `set search_path = app, public, pg_temp` (the extra
--     `public` schema each already needed before this migration).
-- Omitting any of these on a bare `CREATE OR REPLACE` silently resets it to the session
-- default -- exactly the mistake `20260831290000_restore_security_definer_on_drifted_
-- finance_wrappers.sql` had to issue a corrective migration for after a prior `CREATE OR
-- REPLACE` on a different set of functions dropped `SECURITY DEFINER` unintentionally.
--
-- Every parameter, the parameter list's own order, every return type, the IP-allowlist
-- branch, every existing business rule, and every existing grant is otherwise unchanged.
-- No already-applied migration is edited -- this is a same-signature `CREATE OR REPLACE` on
-- 12 live functions, diffed line-for-line against their live `pg_get_functiondef` output
-- before writing this file.

-- ===========================================================================
-- 1. app.commit_import_job (generic framework) -- resolves (module, 'Import') dynamically
-- from the job's own import_export_schemas.owner_primitive_code.
-- ===========================================================================

create or replace function app.commit_import_job(
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
  v_schema_owner_module text;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-278 (this migration): see this migration's own header for why the module is
  -- resolved dynamically here rather than hardcoded, and why this is a strict no-op for any
  -- tenant that has not itself opted the resolved (module, 'Import') pair into its own
  -- additional_high_risk_actions.
  select owner_primitive_code into v_schema_owner_module
  from app.import_export_schemas where code = v_job.import_export_schema_code;

  if v_schema_owner_module is not null then
    perform app.assert_current_step_up_authorization(v_job.tenant_id, p_actor_auth_user_id, v_schema_owner_module, 'Import');
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
  'ISS-2026-278 (Step 16 historical-issue-backlog remediation, resumed): p_client_ip (2026-08-27) enforces the tenant''s own IP allowlist restriction when supplied. This migration additionally composes app.assert_current_step_up_authorization, resolving (module, ''Import'') dynamically from app.import_export_schemas.owner_primitive_code for the job''s own schema -- a strict no-op unless the tenant has additively opted that exact pair into its own app.mfa_tenant_policies.additional_high_risk_actions AND turned MFA on. Never a change to app.is_high_risk_action''s own platform-default tuple list.';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_import_job(uuid, boolean, uuid, text, text) to service_role;

-- ===========================================================================
-- 2. app.commit_employee_import_job (HRT-274) -- HRS:Import, the SAME pair its own
-- evaluate_permission check already gates on.
-- ===========================================================================

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

comment on function app.commit_employee_import_job is
  'HRT-274 (decision 11), corrected at HDN-385 (Step 15, Data Migration Rehearsal), ISS-2026-269, ISS-2026-279, and ISS-2026-278 (Step 16 historical-issue-backlog remediation, resumed): idempotent per staging row and job-scoped-advisory-lock serialized, mirroring app.commit_vendor_rate_import_job (PRC-255) exactly. A genuine explicit employee_number collision (master_records_tenant_code_unique) raises a clear, named error and aborts the whole commit. A fresh, auto-numbered row sharing an existing employee''s own work_email or full_name (ISS-2026-269), OR an explicitly-numbered row whose employee_number normalizes to an existing employee''s own number without being byte-identical (ISS-2026-279), is flagged into app.employee_duplicate_candidates for human review (never a hard block -- the import still succeeds either way). p_client_ip is an optional, trailing 5th parameter (default null) enforcing the tenant''s own IP allowlist restriction when supplied, unless the acting identity holds an active bypass grant (ISS-2026-278). Additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''HRS'', ''Import'') immediately after the existing HRS:Import check -- a strict no-op unless the tenant has itself opted (HRS, Import) into its own additional_high_risk_actions AND turned MFA on (ISS-2026-278, resumed). Every created row is a real draft employee -- submit/approve/activate remain separate, deliberate HR actions afterward, never auto-activated by import.';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_employee_import_job(uuid, boolean, uuid, text, text) to authenticated, service_role;

-- ===========================================================================
-- 3. app.commit_attendance_device_import_job (HRT-278) -- HRS:Import, the SAME pair its
-- own evaluate_permission check already gates on.
-- ===========================================================================

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

comment on function app.commit_attendance_device_import_job is
  'HRT-278, widened at ISS-2026-278 (Step 16 historical-issue-backlog remediation, resumed): idempotent per staging row (source_import_staging_row_id unique-when-set on app.attendance_events, defended by a pre-check AND a per-row exception handler), job-scoped-advisory-lock serialized. Calls the SAME app._ingest_attendance_event engine the live self-service clock path calls -- never a second, independently-hardened write path. A per-row domain-validation failure at commit time (e.g. the employee was deactivated after this row was validated) marks that ONE row invalid and continues, never aborts the whole batch. p_client_ip is an optional, trailing 5th parameter (default null) enforcing the tenant''s own IP allowlist restriction when supplied, unless the acting identity holds an active bypass grant. Additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''HRS'', ''Import'') immediately after the existing HRS:Import check -- a strict no-op unless the tenant has itself opted (HRS, Import) into its own additional_high_risk_actions AND turned MFA on (ISS-2026-278, resumed).';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_attendance_device_import_job(uuid, boolean, uuid, text, text) to authenticated, service_role;

-- ===========================================================================
-- 4. app.commit_timesheet_import_job -- HRS:Import, the SAME pair its own
-- evaluate_permission check already gates on.
-- ===========================================================================

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

comment on function app.commit_timesheet_import_job is
  'Widened at ISS-2026-278 (Step 16 historical-issue-backlog remediation, resumed): idempotent per staging row (source_import_staging_row_id unique-when-set on app.timesheet_entries), job-scoped-advisory-lock serialized, mirrors app.commit_attendance_device_import_job (HRT-278). A per-row domain-validation failure at commit time marks that ONE row invalid and continues, never aborts the whole batch. p_client_ip is an optional, trailing 5th parameter (default null) enforcing the tenant''s own IP allowlist restriction when supplied, unless the acting identity holds an active bypass grant. Additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''HRS'', ''Import'') immediately after the existing HRS:Import check -- a strict no-op unless the tenant has itself opted (HRS, Import) into its own additional_high_risk_actions AND turned MFA on (ISS-2026-278, resumed).';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_timesheet_import_job(uuid, boolean, uuid, text, text) to authenticated, service_role;

-- ===========================================================================
-- 5. app.commit_vendor_rate_import_job (PRC-255) -- PRC:Import, the SAME pair its own
-- evaluate_permission check already gates on.
-- ===========================================================================

create or replace function app.commit_vendor_rate_import_job(
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

  -- ISS-2026-278 (this migration): reuses the SAME PRC:Import pair the check immediately
  -- above already gates on. A strict no-op unless this tenant has itself opted (PRC,
  -- Import) into its own additional_high_risk_actions AND turned MFA on.
  perform app.assert_current_step_up_authorization(v_job.tenant_id, p_actor_auth_user_id, 'PRC', 'Import');

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
  'PRC-255, widened at ISS-2026-278 (Step 16 historical-issue-backlog remediation, resumed): requires BOTH create_rate_version authority (Supreme Admin or tenant_admin) AND PRC:Import -- neither alone is sufficient. Only a violation of this adapter''s own idempotency guard (vendor_rate_versions_source_import_row_unique) is treated as a safe replay; any other unique_violation (e.g. a genuine vendor_code collision) aborts the whole commit rather than silently dropping the row. p_client_ip is an optional, trailing 5th parameter (default null) enforcing the tenant''s own IP allowlist restriction when supplied, unless the acting identity holds an active bypass grant. Additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''PRC'', ''Import'') immediately after the existing PRC:Import check -- a strict no-op unless the tenant has itself opted (PRC, Import) into its own additional_high_risk_actions AND turned MFA on (ISS-2026-278, resumed).';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_vendor_rate_import_job(uuid, boolean, uuid, text, text) to service_role;

-- ===========================================================================
-- 6. app.commit_vendor_import_job (PRC-251) -- PRC:Import, the SAME pair its own
-- evaluate_permission check already gates on.
-- ===========================================================================

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
  if not found then
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

comment on function app.commit_vendor_import_job is
  'ISS-2026-057: the PLT-131 domain-write adapter for the vendor_import schema, closing PRC-251''s named-but-never-built "Bulk-import staged vendors" alternative flow. Requires BOTH app.is_support_grant_authority AND PRC:Import; app.create_vendor_profile_draft then separately enforces its own unchanged PRC:Create gate per row -- the bulk path is strictly additive to the single-vendor path''s own authority, never a way around it. Writes only through that canonical function, never a direct INSERT. intake_source is forced to bulk_import by the adapter (a file cannot claim its own provenance) and every created vendor is a draft -- submit/review/approve/activate remain deliberate human actions. After each row commits, two duplicate sweeps run against it (trigram name/trade-name similarity, and an exact punctuation-and-case-normalized business_registration_number match) and flag app.vendor_duplicate_candidates rows: never a hard block, but app.submit_vendor_profile_for_review''s own existing gate then refuses to advance the vendor until a human resolves the pairing. Idempotent per staged row (vendor_profiles_source_import_row_unique, defended by a pre-check, an explicit already-bound check, a nested unique_violation handler scoped to that one constraint name, and a job-scoped advisory lock); no unique_violation from create_vendor_profile_draft is ever treated as a safe replay, because its own idempotency-key path returns the existing row rather than raising. p_client_ip is an optional trailing 5th parameter enforcing the tenant''s own IP allowlist when supplied, unless the acting identity holds an active bypass grant (ISS-2026-278). Additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''PRC'', ''Import'') immediately after the existing PRC:Import check -- a strict no-op unless the tenant has itself opted (PRC, Import) into its own additional_high_risk_actions AND turned MFA on (ISS-2026-278, resumed).';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_vendor_import_job(uuid, boolean, uuid, text, text) to service_role;

-- ===========================================================================
-- 7. app.commit_customer_import_job -- COM:Import, the SAME pair its own
-- evaluate_permission check already gates on.
-- ===========================================================================

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
set search_path = app, public, pg_temp
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
  if not found then
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

  -- ISS-2026-278 (this migration): reuses the SAME COM:Import pair the check immediately
  -- above already gates on. A strict no-op unless this tenant has itself opted (COM,
  -- Import) into its own additional_high_risk_actions AND turned MFA on.
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
      v_linked_count := v_linked_count + 1;
      continue;
    elsif v_account.created_at < v_job.created_at then
      -- Resolved to an account that predates this job entirely. Also a legitimate link,
      -- and deliberately NOT stamped: stamping it would rewrite the provenance of a record
      -- this import did not create.
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

comment on function app.commit_customer_import_job is
  'The PLT-131 domain-write adapter for the customer_import schema. Requires BOTH app.is_support_grant_authority AND COM:Import; app.create_customer_account_direct resolves duplicate fingerprints to an existing account rather than raising, so a repeated or overlapping legal_name/tax_id links to the canonical account instead of creating a second one. p_client_ip is an optional trailing 5th parameter enforcing the tenant''s own IP allowlist when supplied, unless the acting identity holds an active bypass grant (ISS-2026-278). Additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''COM'', ''Import'') immediately after the existing COM:Import check -- a strict no-op unless the tenant has itself opted (COM, Import) into its own additional_high_risk_actions AND turned MFA on (ISS-2026-278, resumed).';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_customer_import_job(uuid, boolean, uuid, text, text) to service_role;

-- ===========================================================================
-- 8. app.commit_item_import_job -- OPS:Import, the SAME pair its own
-- evaluate_permission check already gates on.
-- ===========================================================================

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
set search_path = app, public, pg_temp
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
  if not found then
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

  -- ISS-2026-278 (this migration): reuses the SAME OPS:Import pair the check immediately
  -- above already gates on. A strict no-op unless this tenant has itself opted (OPS,
  -- Import) into its own additional_high_risk_actions AND turned MFA on.
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
      v_linked_count := v_linked_count + 1;
      continue;
    elsif v_item.created_at < v_job.created_at then
      -- An item that predates this job. A legitimate link, deliberately not stamped.
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

comment on function app.commit_item_import_job is
  'The PLT-131 domain-write adapter for the item_import schema. Requires BOTH app.is_support_grant_authority AND OPS:Import; app.create_item_master is idempotent on (tenant_id, owner_account_id, code) and returns the existing row rather than raising. p_client_ip is an optional trailing 5th parameter enforcing the tenant''s own IP allowlist when supplied, unless the acting identity holds an active bypass grant (ISS-2026-278). Additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''OPS'', ''Import'') immediately after the existing OPS:Import check -- a strict no-op unless the tenant has itself opted (OPS, Import) into its own additional_high_risk_actions AND turned MFA on (ISS-2026-278, resumed).';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_item_import_job(uuid, boolean, uuid, text, text) to service_role;

-- ===========================================================================
-- 9. app.commit_finance_opening_balance_import_job -- FIN:Import, the SAME pair its own
-- evaluate_permission check already gates on.
-- ===========================================================================

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
  if not found then
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

comment on function app.commit_finance_opening_balance_import_job is
  'The PLT-131 domain-write adapter for the finance_opening_balance_import schema (ISS-2026-273). Requires BOTH app.is_support_grant_authority AND FIN:Import. Each row posts through the canonical app.post_finance_ar_open_item/app.post_finance_ap_open_item primitives AND app.post_finance_opening_balance_batch in the SAME transaction -- never a subledger row without its GL batch. p_client_ip is an optional trailing 5th parameter enforcing the tenant''s own IP allowlist when supplied, unless the acting identity holds an active bypass grant (ISS-2026-278). Additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''FIN'', ''Import'') immediately after the existing FIN:Import check -- a strict no-op unless the tenant has itself opted (FIN, Import) into its own additional_high_risk_actions AND turned MFA on (ISS-2026-278, resumed); never the platform-default FIN:Approve tuple.';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_finance_opening_balance_import_job(uuid, boolean, uuid, text, text) to service_role;

-- ===========================================================================
-- 10. app.commit_inventory_opening_balance_import_job -- OPS:Import, the SAME pair its own
-- evaluate_permission check already gates on.
-- ===========================================================================

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
  if not found then
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

comment on function app.commit_inventory_opening_balance_import_job is
  'The PLT-131 domain-write adapter for the inventory_opening_balance_import schema. Requires BOTH app.is_support_grant_authority AND OPS:Import. Every row posts through the canonical app.post_inventory_movement primitive with movement_type/reason=opening_balance, idempotent on a derived idempotency_key never taken from the file. p_client_ip is an optional trailing 5th parameter enforcing the tenant''s own IP allowlist when supplied, unless the acting identity holds an active bypass grant (ISS-2026-278). Additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''OPS'', ''Import'') immediately after the existing OPS:Import check -- a strict no-op unless the tenant has itself opted (OPS, Import) into its own additional_high_risk_actions AND turned MFA on (ISS-2026-278, resumed).';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_inventory_opening_balance_import_job(uuid, boolean, uuid, text, text) to service_role;

-- ===========================================================================
-- 11. app.commit_leave_opening_balance_import_job -- HRS:Import, the SAME pair its own
-- evaluate_permission check already gates on.
-- ===========================================================================

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
  if not found then
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

comment on function app.commit_leave_opening_balance_import_job is
  'The PLT-131 domain-write adapter for the leave_opening_balance_import schema. Requires BOTH app.is_support_grant_authority AND HRS:Import. Every row posts through the canonical app.load_opening_leave_balance primitive, idempotent on a derived idempotency_key never taken from the file. p_client_ip is an optional trailing 5th parameter enforcing the tenant''s own IP allowlist when supplied, unless the acting identity holds an active bypass grant (ISS-2026-278). Additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''HRS'', ''Import'') immediately after the existing HRS:Import check -- a strict no-op unless the tenant has itself opted (HRS, Import) into its own additional_high_risk_actions AND turned MFA on (ISS-2026-278, resumed).';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_leave_opening_balance_import_job(uuid, boolean, uuid, text, text) to service_role;

-- ===========================================================================
-- 12. app.commit_payroll_loan_cutover_import_job -- HRS:Import (the SAME pair
-- app.check_payroll_authority('Import', ...) already gates on immediately above),
-- deliberately NEVER HRS:Approve. See this migration's own header for why: HRS:Approve is
-- one of app.is_high_risk_action's 7 fixed platform-default tuples, so composing step-up on
-- it would not be a tenant opt-in at all -- it would immediately require step-up for every
-- tenant with tenant_wide_required = true, breaking this migration's own no-op-by-default
-- premise for this one function.
-- ===========================================================================

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
  if not found then
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

comment on function app.commit_payroll_loan_cutover_import_job is
  'The PLT-131 domain-write adapter for the payroll_loan_cutover_import schema. Requires app.is_support_grant_authority AND BOTH HRS:Import and HRS:Approve (app.issue_payroll_loan itself separately demands HRS:Approve of every single-loan issuance, and a bulk cutover is not exempt). Every row posts through the canonical app.issue_payroll_loan primitive with p_source_import_staging_row_id set, idempotent on that column. p_client_ip is an optional trailing 5th parameter enforcing the tenant''s own IP allowlist when supplied, unless the acting identity holds an active bypass grant (ISS-2026-278). Additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''HRS'', ''Import'') immediately after the existing authority checks -- reusing HRS:Import, deliberately never the platform-default HRS:Approve tuple (see this function''s own migration section header) -- a strict no-op unless this tenant has itself opted (HRS, Import) into its own additional_high_risk_actions AND turned MFA on (ISS-2026-278, resumed).';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_payroll_loan_cutover_import_job(uuid, boolean, uuid, text, text) to service_role;
