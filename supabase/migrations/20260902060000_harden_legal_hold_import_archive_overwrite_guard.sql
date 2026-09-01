-- ISS-2026-277 (docs/runtime/KNOWN_ISSUES.md): app._is_under_legal_hold()'s existing
-- enforcement is scoped to deletion only -- no structural protection exists against a
-- migration/import job OVERWRITING or ARCHIVING a legally-held record instead of deleting it.
--
-- ===========================================================================
-- What app._is_under_legal_hold() actually does today, read live (pg_get_functiondef)
-- before writing this file, not assumed from the entry's own text
-- ===========================================================================
--
-- `app._is_under_legal_hold(p_tenant_id, p_record_class, p_source_table, p_source_record_id)`
-- is a generic, cross-table primitive: it returns true for (a) a hold with
-- `scope_record_table`/`scope_record_id` matching this EXACT (table, record) pair, (b) a
-- tenant-wide hold on this `record_class` with no specific scope, or (c) the native
-- `legal_hold` boolean bridged in for `app.files`/`app.audit_logs`/`app.tenants`
-- specifically. Branch (a) is table-agnostic by construction -- `app.request_legal_hold()`
-- accepts any schema-qualified `p_scope_record_table`, so a hold can already be placed on a
-- specific `app.employees`, `app.vendor_profiles`, `app.accounts` or `app.item_masters` row
-- today, with no schema change required. The entry's own re-verification (2026-08-28, Track
-- B Batch 7) counted 5 live enforcement points, ALL still UPDATE/DELETE-scoped: the
-- `files_protect_legal_hold_from_deletion` trigger, `app.request_file_deletion()`,
-- `app.request_retention_archive()`, plus two more added since. None of them protect a
-- write path that OVERWRITES or ARCHIVES a record's own live content outside of physical or
-- soft deletion.
--
-- ===========================================================================
-- Scope: which write paths this migration actually closes, and why not others
-- ===========================================================================
--
-- Every one of the 12 `app.commit_*_import_job`-shaped RPCs `ISS-2026-278`'s own
-- `20260901110000_harden_import_commit_step_up_mfa_gating.sql` already enumerates was read
-- live (pg_get_functiondef) before writing this file. Ten of them are pure create-or-fail or
-- create-or-append primitives: a genuine identity collision either raises a named error before
-- any row is written (`app.commit_employee_import_job` on `employee_number`,
-- `app.commit_vendor_rate_import_job`'s rate versions are historical/append-only) or the
-- underlying create-primitive's own idempotency key is derived from the staging row's own id
-- (`app.commit_vendor_import_job`'s `'vendor-import:' || row_id`,
-- `app.commit_attendance_device_import_job`, `app.commit_timesheet_import_job`, all four
-- opening-balance/cutover adapters), which can never resolve to a DIFFERENT, pre-existing
-- business record -- only to a row this exact import call itself just created or a prior
-- replay of this exact staged row. There is no reachable "found a pre-existing record and is
-- about to treat it as this import's own target" branch in any of those ten today, so a
-- legal-hold guard placed in them would have zero live caller to exercise, exactly the
-- "latent, not reachable" shape this entry's own prior dispositions correctly declined to
-- guard against speculatively.
--
-- The other two -- `app.commit_customer_import_job` and `app.commit_item_import_job` -- are
-- different in kind: `app.create_customer_account_direct` resolves duplicates by a
-- **business-identity** fingerprint (normalized legal_name + tax_id), and
-- `app.create_item_master` resolves by **business-identity** (tenant, owner_account_id, code)
-- -- both keys a genuinely unrelated, pre-existing record can share with an imported row's
-- content, independent of which staged row (if any) created it. Each adapter already has two
-- branches that treat such a match as a legitimate, pre-existing target: linked to a
-- DIFFERENT staged row's own earlier commit (`source_import_staging_row_id is not null`), or
-- predates this job entirely (`created_at < v_job.created_at`). Both branches are real,
-- live-reachable today (an ordinary re-import of an overlapping extract hits them
-- constantly, per each adapter's own existing test coverage in
-- scripts/db-tests/master-data-import.sql) -- and neither one currently asks whether the
-- record it is about to treat as this import's own target is under legal hold before
-- reporting the row a successful "link". This migration closes exactly that gap, in exactly
-- those two branches of exactly those two functions -- additively, before either branch's
-- own `continue`, never touching `ISS-2026-278`'s own already-landed step-up-MFA composition
-- (`app.assert_current_step_up_authorization`) or the IP-allowlist check above it in either
-- function.
--
-- `app.commit_vendor_import_job` was checked and deliberately excluded for the same
-- "no reachable target" reason as the other ten: its own idempotency key
-- (`'vendor-import:' || row_id`) is unique per staging row by construction, so
-- `app.create_vendor_profile_draft`'s idempotency-key lookup can only ever return a row THIS
-- SAME staged row previously created (a genuine replay) -- never a different, pre-existing
-- vendor. Its one "already bound to a different row" branch already RAISES
-- `import_vendor_profile_already_bound` today (a hard error, not a silent link), so there is
-- no silent-overwrite gap to close there either.
--
-- ===========================================================================
-- The archive half: two RPCs that genuinely overwrite an EXISTING row's own live content
-- ===========================================================================
--
-- Searched for every `archive_*`/`_archive_record`-shaped function live (pg_proc sweep)
-- before writing this file. Of that list, `app.archive_employee_profile` and
-- `app.archive_vendor_profile` are the two whose target table (`app.employees`,
-- `app.vendor_profiles`) is the SAME table one of the `ISS-2026-278`-hardened import-commit
-- adapters above also writes to -- the exact cross-domain overlap `HDN-385`'s own Data
-- Migration Rehearsal concern is about (a migration/import-adjacent process silently
-- clobbering a held record instead of deleting it). Both genuinely mutate an existing row in
-- place (`lifecycle_status`, `archive_reason`/`record_version`) with no DELETE anywhere in
-- their own call path -- exactly the "archived... instead of deleting it" shape this entry
-- names, and exactly why the existing DELETE-scoped trigger/RPC guards never see it. Neither
-- carried any legal-hold awareness before this migration. The other archive_* functions this
-- sweep found (loyalty rewards, KB articles, sales plans, performance/training definitions,
-- vendor sub-entities) sit outside the cross-referenced import-commit domain scope this entry
-- and its own HDN-385 finding are about, and are left to a dedicated future task exactly as
-- the entry's prior dispositions already scoped this kind of widening.
--
-- ===========================================================================
-- The error shape: mirrors app.request_file_deletion's own DELETE-path convention exactly
-- ===========================================================================
--
-- `<domain>_legal_hold_blocks_<verb>`, errcode = check_violation, the same shape
-- `document_legal_hold_blocks_deletion` / `audit_log_legal_hold_blocks_deletion` /
-- `file_access_log_legal_hold_blocks_deletion` already establish -- never a generic or
-- differently-shaped error. `p_record_class` is passed as `'operational'` throughout,
-- matching the same precedent every non-finance/non-audit call site of
-- `app._is_under_legal_hold()` already uses (`app.protect_files_legal_hold_from_deletion`,
-- `app.request_file_deletion`, the tenant-termination guard in
-- `20260818000000_harden_integrated_verification_legal_hold_bridge.sql`) -- existence-oracle-
-- safe, since the actor calling any of these four RPCs has already independently resolved
-- the target record through their own authorized tenant-scoped lookup; the hold check adds
-- no new information disclosure beyond what the existing authority/lookup already exposed.
--
-- No already-applied migration is edited. Every one of the 4 `CREATE OR REPLACE FUNCTION`
-- statements below is a same-signature, additive change, diffed line-for-line against each
-- function's own live `pg_get_functiondef` output before writing this file -- every existing
-- parameter, return type, `SECURITY DEFINER`/`search_path` clause, business rule and grant
-- is preserved exactly.

-- ===========================================================================
-- 1. app.archive_employee_profile -- guards BOTH the immediate and the scheduled/future
-- archive branch, checked once before either runs.
-- ===========================================================================

create or replace function app.archive_employee_profile(
  p_master_record_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_effective_date date default current_date
)
returns app.employees
language plpgsql
security definer
set search_path = 'app', 'pg_temp'
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_from_status text;
  v_effective_date date;
  v_is_future boolean;
  v_is_backdate boolean;
  v_version app.employee_lifecycle_versions;
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

  if v_employee.lifecycle_status not in ('draft', 'submitted', 'approved', 'terminated') then
    raise exception 'invalid_transition: employee % is % and cannot be archived', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_employee.lifecycle_status;

  -- ISS-2026-277 (this migration): archiving genuinely overwrites this row's own live
  -- content (lifecycle_status, archive_reason) with no DELETE anywhere in this function's own
  -- call path, so the existing DELETE-scoped legal-hold guards never see it. Checked once
  -- here, before either the immediate or the scheduled/future branch below does anything, so
  -- a SCHEDULED archive of a held employee is refused up front rather than only failing
  -- later, unguarded, when the scheduled transition actually executes.
  if app._is_under_legal_hold(v_employee.tenant_id, 'operational', 'app.employees', p_master_record_id) then
    raise exception 'employee_legal_hold_blocks_archive: employee % is under legal hold, it cannot be archived', p_master_record_id
      using errcode = 'check_violation';
  end if;

  -- ISS-2026-065 closure (decision 4): archive is normally HRS:Edit only --
  -- backdating requires an EXPLICIT, additional HRS:Override check plus a
  -- non-empty reason (p_reason is normally optional; now conditionally mandatory).
  v_effective_date := coalesce(p_effective_date, current_date);
  v_is_future := v_effective_date > current_date;
  v_is_backdate := v_effective_date < current_date;
  if v_is_backdate then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'backdate_reason_required: a non-empty reason is required to backdate this employee lifecycle change to %', v_effective_date using errcode = 'check_violation';
    end if;
    if not (app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Override')).allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Override (required to backdate an employee lifecycle change) for tenant %', p_actor_auth_user_id, v_employee.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_is_future then
    v_version := app.record_employee_lifecycle_version(
      v_employee.tenant_id, p_master_record_id, 'archived', v_employee.employment_type,
      v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
      v_employee.position_title, v_employee.manager_employee_id, v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
      v_effective_date, 'archive', p_reason, false, p_actor_label
    );

    insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
    values (v_employee.tenant_id, p_master_record_id, v_from_status, 'archived', p_reason, jsonb_build_object('scheduled', true, 'effective_start_date', v_effective_date, 'version_id', v_version.id), p_actor_auth_user_id, p_actor_label);

    perform app.capture_audit_event(
      v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_employee_profile',
      'app.employees', p_master_record_id, 'success', null, null, jsonb_build_object('scheduled', true, 'effective_start_date', v_effective_date)
    );

    return v_employee;
  end if;

  update app.employees
  set lifecycle_status = 'archived', archive_reason = p_reason
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, v_from_status, 'archived', p_reason, p_actor_auth_user_id, p_actor_label);

  v_version := app.record_employee_lifecycle_version(
    v_employee.tenant_id, p_master_record_id, 'archived', v_employee.employment_type,
    v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
    v_employee.position_title, v_employee.manager_employee_id, v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
    v_effective_date, 'archive', p_reason, true, p_actor_label
  );

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_employee_profile',
    'app.employees', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

comment on function app.archive_employee_profile is
  'ISS-2026-065 closure (decision 4), corrected at HDN-385, and ISS-2026-277 (this migration): archive is normally HRS:Edit only -- backdating additionally requires HRS:Override plus a non-empty reason. A scheduled (future-dated) archive records a lifecycle version and an event without mutating the live row yet; an immediate archive updates lifecycle_status/archive_reason directly. ISS-2026-277: additionally checks app._is_under_legal_hold(tenant, ''operational'', ''app.employees'', master_record_id) once, before either branch runs, raising employee_legal_hold_blocks_archive (check_violation) for a held employee -- a held employee cannot be archived, scheduled or immediate, mirroring the DELETE-path convention app.request_file_deletion already established.';

revoke execute on all functions in schema app from public;
grant execute on function app.archive_employee_profile(uuid, integer, text, uuid, text, date) to authenticated, service_role;

-- ===========================================================================
-- 2. app.archive_vendor_profile -- guards the one write branch this function has.
-- ===========================================================================

create or replace function app.archive_vendor_profile(
  p_master_record_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_profiles
language plpgsql
security definer
set search_path = 'app', 'pg_temp'
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.vendor_profiles;
begin
  select * into v_profile from app.vendor_profiles where master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_profile.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_profile_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_profile.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_profile.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_profile.record_version <> p_expected_version then
    raise exception 'stale_version: vendor profile % expected version % but found %', p_master_record_id, p_expected_version, v_profile.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_profile.lifecycle_status <> 'suspended' then
    raise exception 'invalid_transition: vendor profile % is % and cannot be archived (must be suspended first)', p_master_record_id, v_profile.lifecycle_status
      using errcode = 'check_violation';
  end if;

  -- ISS-2026-277 (this migration): see app.archive_employee_profile's identical guard in the
  -- same migration -- archiving genuinely overwrites this row's own live content
  -- (lifecycle_status, record_version) with no DELETE anywhere in this function's own call
  -- path.
  if app._is_under_legal_hold(v_profile.tenant_id, 'operational', 'app.vendor_profiles', p_master_record_id) then
    raise exception 'vendor_profile_legal_hold_blocks_archive: vendor profile % is under legal hold, it cannot be archived', p_master_record_id
      using errcode = 'check_violation';
  end if;

  update app.vendor_profiles
  set lifecycle_status = 'archived', record_version = record_version + 1, updated_at = now()
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_profile;
  if not found then
    raise exception 'stale_version: vendor profile % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_profile_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_profile.tenant_id, p_master_record_id, 'suspended', 'archived', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_profile.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_vendor_profile',
    'app.vendor_profiles', p_master_record_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_profile;
end;
$$;

comment on function app.archive_vendor_profile is
  'Prompt 269 (ISS-2026-054/ISS-2026-055), corrected at HDN-385, and ISS-2026-277 (this migration): only a suspended vendor profile may be archived. ISS-2026-277: additionally checks app._is_under_legal_hold(tenant, ''operational'', ''app.vendor_profiles'', master_record_id) before the archiving UPDATE, raising vendor_profile_legal_hold_blocks_archive (check_violation) for a held vendor profile, mirroring the DELETE-path convention app.request_file_deletion already established.';

revoke execute on all functions in schema app from public;
grant execute on function app.archive_vendor_profile(uuid, integer, text, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 3. app.commit_customer_import_job -- guards BOTH "resolved to a pre-existing account"
-- branches (linked to a different staged row; predates this job). ISS-2026-278's own
-- step-up-MFA/IP-allowlist composition above is untouched.
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

comment on function app.commit_customer_import_job is
  'The PLT-131 domain-write adapter for the customer_import schema. Requires BOTH app.is_support_grant_authority AND COM:Import; app.create_customer_account_direct resolves duplicate fingerprints to an existing account rather than raising, so a repeated or overlapping legal_name/tax_id links to the canonical account instead of creating a second one. p_client_ip is an optional trailing 5th parameter enforcing the tenant''s own IP allowlist when supplied, unless the acting identity holds an active bypass grant (ISS-2026-278). Additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''COM'', ''Import'') immediately after the existing COM:Import check -- a strict no-op unless the tenant has itself opted (COM, Import) into its own additional_high_risk_actions AND turned MFA on (ISS-2026-278, resumed). ISS-2026-277 (this migration): BOTH branches that resolve a staged row to a pre-existing account (linked to a different staged row; predates this job) now refuse with import_blocked_legal_hold (check_violation) if that account is under legal hold (app._is_under_legal_hold, scope app.accounts) -- an import can still CREATE a genuinely new account freely; it can no longer silently link its content to one that is held.';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_customer_import_job(uuid, boolean, uuid, text, text) to service_role;

-- ===========================================================================
-- 4. app.commit_item_import_job -- guards BOTH "resolved to a pre-existing item" branches,
-- the identical shape as app.commit_customer_import_job above.
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

comment on function app.commit_item_import_job is
  'The PLT-131 domain-write adapter for the item_import schema. Requires BOTH app.is_support_grant_authority AND OPS:Import; app.create_item_master is idempotent on (tenant_id, owner_account_id, code) and returns the existing row rather than raising. p_client_ip is an optional trailing 5th parameter enforcing the tenant''s own IP allowlist when supplied, unless the acting identity holds an active bypass grant (ISS-2026-278). Additionally gated on app.assert_current_step_up_authorization(tenant, actor, ''OPS'', ''Import'') immediately after the existing OPS:Import check -- a strict no-op unless the tenant has itself opted (OPS, Import) into its own additional_high_risk_actions AND turned MFA on (ISS-2026-278, resumed). ISS-2026-277 (this migration): BOTH branches that resolve a staged row to a pre-existing item master (linked to a different staged row; predates this job) now refuse with import_blocked_legal_hold (check_violation) if that item master is under legal hold (app._is_under_legal_hold, scope app.item_masters) -- an import can still CREATE a genuinely new item master freely; it can no longer silently link its content to one that is held.';

revoke execute on all functions in schema app from public;
grant execute on function app.commit_item_import_job(uuid, boolean, uuid, text, text) to service_role;
