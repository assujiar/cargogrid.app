-- ISS-2026-317 (docs/runtime/KNOWN_ISSUES.md) -- payroll loan cutover has no import path, and
-- the entry's own stated reason for filing it rather than building it does not survive
-- checking.
--
-- THREE "BUSINESS DECISIONS" WERE NAMED AS THE REASON THIS WAS FILED RATHER THAN BUILT.
-- ALL THREE ARE ALREADY ANSWERED BY SHIPPED CODE, RE-DERIVED FROM THE LIVE SCHEMA RATHER THAN
-- ASSUMED:
--
--   1. "Whether the outstanding principal or the original principal is authoritative" --
--      app.payroll_loans has no rate column of any kind (verified against
--      information_schema.columns), so there is no interest computation for a rate to be
--      authoritative over. principal_amount has zero financial effect anywhere in the
--      deduction engine; only installment_amount (a fixed per-period amount) does. This
--      "decision" does not exist.
--
--   2. "Which instalments are considered paid" -- app.issue_payroll_loan (already shipped,
--      pre-dating this migration) already answers this: it takes p_is_opening_balance and
--      p_opening_remaining_installments, and inserts EXACTLY p_opening_remaining_installments
--      rows into app.payroll_loan_installments, numbered
--      (p_term_count - p_opening_remaining_installments + 1) .. p_term_count -- i.e. the
--      already-paid instalments never exist as rows at all, and the surviving rows are
--      numbered as the TAIL of the original schedule. This adapter reuses that numbering
--      unchanged; it does not invent a new one.
--
--   3. "Mid-term rate change" -- moot per (1): there is no rate to change.
--
-- So the real reason to file rather than build was never a business decision -- it was that
-- nobody had re-read app.issue_payroll_loan's own live signature. It already accepts opening
-- balances. What is missing is only the bulk import path onto it, which is ordinary PLT-131
-- adapter work following the pattern now established six times over (vendor_import,
-- customer_import, item_import, finance_opening_balance_import, and the inventory/leave pair
-- in 20260831260000).
--
-- WORSE THAN THE ENTRY SAYS IN ONE RESPECT, disclosed rather than left implicit: the cutover
-- parameters app.issue_payroll_loan already exposes are not reachable from the UI at all
-- (app/(tenant)/[tenantSlug]/hris/payroll/actions.ts hardcodes isOpeningBalance:false /
-- openingRemainingInstallments:null, and IssueLoanForm exposes no fields for them) and are
-- exercised by no test anywhere. That UI gap is a separate, smaller finding, filed below as
-- ISS-2026-321 rather than folded into this closure.
--
-- STEP 1: lineage column, mirroring ISS-2026-206/259's own "every import writes a durable,
-- queryable link back to its own staging row" discipline.

alter table app.payroll_loans add column source_import_staging_row_id uuid references app.import_staging_rows (id);

create unique index payroll_loans_source_import_row_unique on app.payroll_loans (source_import_staging_row_id)
  where source_import_staging_row_id is not null;

comment on column app.payroll_loans.source_import_staging_row_id is
  'ISS-2026-317: when this loan was created by app.commit_payroll_loan_cutover_import_job, the staging row it came from -- null for a loan issued through the ordinary app.issue_payroll_loan call. The partial unique index is the idempotency backstop: a re-committed job cannot create a second loan from the same staging row.';

-- ---------------------------------------------------------------------------------------
-- STEP 2: widen the primitive with one trailing, default-valued parameter. DROP + CREATE,
-- never CREATE OR REPLACE (ISS-2026-260) -- appending a parameter to an existing function
-- creates a second, ambiguous overload rather than truly replacing it. Body is the LIVE
-- pg_get_functiondef output with the new parameter and its INSERT column added, not
-- retyped from any earlier migration.
-- ---------------------------------------------------------------------------------------

drop function public.issue_payroll_loan(uuid, uuid, numeric, text, numeric, integer, boolean, integer, text, uuid, text);
drop function app.issue_payroll_loan(uuid, uuid, numeric, text, numeric, integer, boolean, integer, text, uuid, text);

create function app.issue_payroll_loan(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_principal_amount numeric,
  p_currency text,
  p_installment_amount numeric,
  p_term_count integer,
  p_is_opening_balance boolean,
  p_opening_remaining_installments integer,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_source_import_staging_row_id uuid default null
)
returns app.payroll_loans
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_employee app.employees;
  v_loan app.payroll_loans;
  v_remaining integer;
  i integer;
begin
  if not app.check_payroll_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  select * into v_employee from app.employees where master_record_id = p_employee_id and tenant_id = p_tenant_id;
  if not found or v_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'employee_not_active: % is not an active employee for tenant %', p_employee_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if p_principal_amount is null or p_principal_amount <= 0 or p_installment_amount is null or p_installment_amount <= 0 or p_term_count is null or p_term_count <= 0 then
    raise exception 'invalid_loan_terms: principal, installment amount and term count must all be positive' using errcode = 'check_violation';
  end if;

  v_remaining := case when coalesce(p_is_opening_balance, false) then coalesce(p_opening_remaining_installments, p_term_count) else p_term_count end;
  if v_remaining < 0 or v_remaining > p_term_count then
    raise exception 'invalid_opening_remaining_installments: % must be between 0 and term_count %', v_remaining, p_term_count using errcode = 'check_violation';
  end if;

  insert into app.payroll_loans (
    tenant_id, employee_id, principal_amount, currency, installment_amount, term_count, remaining_installments,
    is_opening_balance, notes, issued_by, created_by, source_import_staging_row_id
  ) values (
    p_tenant_id, p_employee_id, p_principal_amount, coalesce(p_currency, 'IDR'), p_installment_amount, p_term_count, v_remaining,
    coalesce(p_is_opening_balance, false), p_notes, p_actor_label, p_actor_label, p_source_import_staging_row_id
  )
  returning * into v_loan;

  for i in (p_term_count - v_remaining + 1) .. p_term_count loop
    insert into app.payroll_loan_installments (loan_id, tenant_id, installment_number, amount)
    values (v_loan.id, p_tenant_id, i, p_installment_amount);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_payroll_loan',
    'app.payroll_loans', v_loan.id, 'success', null, null, jsonb_build_object('employee_id', p_employee_id, 'term_count', p_term_count)
  );

  return v_loan;
end;
$function$;

comment on function app.issue_payroll_loan(uuid, uuid, numeric, text, numeric, integer, boolean, integer, text, uuid, text, uuid) is
  'ISS-2026-317: widened with a trailing, optional p_source_import_staging_row_id, populated only when this loan is created by app.commit_payroll_loan_cutover_import_job. Every existing 11-argument call site keeps working: the parameter defaults to null and every other behaviour is byte-identical to the pre-widening body.';

revoke execute on function app.issue_payroll_loan(uuid, uuid, numeric, text, numeric, integer, boolean, integer, text, uuid, text, uuid) from anon, authenticated, service_role, public;
grant execute on function app.issue_payroll_loan(uuid, uuid, numeric, text, numeric, integer, boolean, integer, text, uuid, text, uuid) to authenticated;
grant execute on function app.issue_payroll_loan(uuid, uuid, numeric, text, numeric, integer, boolean, integer, text, uuid, text, uuid) to service_role;

create function public.issue_payroll_loan(
  p_tenant_id uuid, p_employee_id uuid, p_principal_amount numeric, p_currency text, p_installment_amount numeric,
  p_term_count integer, p_is_opening_balance boolean, p_opening_remaining_installments integer, p_notes text,
  p_actor_auth_user_id uuid, p_actor_label text, p_source_import_staging_row_id uuid default null
)
returns app.payroll_loans
language sql
security definer
set search_path to 'app', 'public', 'pg_temp'
as $wrap$
  select app.issue_payroll_loan(p_tenant_id, p_employee_id, p_principal_amount, p_currency, p_installment_amount,
    p_term_count, p_is_opening_balance, p_opening_remaining_installments, p_notes, p_actor_auth_user_id, p_actor_label,
    p_source_import_staging_row_id);
$wrap$;

comment on function public.issue_payroll_loan(uuid, uuid, numeric, text, numeric, integer, boolean, integer, text, uuid, text, uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.issue_payroll_loan with an identical grant set, never a reimplementation.';

revoke execute on function public.issue_payroll_loan(uuid, uuid, numeric, text, numeric, integer, boolean, integer, text, uuid, text, uuid) from anon, authenticated, service_role, public;
grant execute on function public.issue_payroll_loan(uuid, uuid, numeric, text, numeric, integer, boolean, integer, text, uuid, text, uuid) to authenticated;
grant execute on function public.issue_payroll_loan(uuid, uuid, numeric, text, numeric, integer, boolean, integer, text, uuid, text, uuid) to service_role;

-- ---------------------------------------------------------------------------------------
-- STEP 3: register the import schema kind.
-- ---------------------------------------------------------------------------------------

insert into app.import_export_schemas (code, name, owner_primitive_code, registered_by)
values ('payroll_loan_cutover_import', 'Payroll Loan Cutover Import', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('import_export:payroll_loan_cutover_import', 'Payroll Loan Cutover Import Column Mapping', 'HRS', 'system')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------------------
-- STEP 4: app.validate_payroll_loan_cutover_import_row -- invoker (not definer), mirroring
-- app.validate_leave_opening_balance_import_row and app.validate_inventory_opening_balance_
-- import_row (20260831260000): re-derives only what can be answered earlier and cheaper than
-- the commit step, and leaves every authoritative rule inside app.issue_payroll_loan.
-- ---------------------------------------------------------------------------------------

create function app.validate_payroll_loan_cutover_import_row(
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
  v_text_fields text[] := array['employee_number', 'currency', 'notes'];
  v_employee_id uuid;
  v_principal numeric;
  v_installment numeric;
  v_term_count integer;
  v_remaining integer;
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

  select e.master_record_id into v_employee_id
  from app.employees e
  join app.master_records m on m.id = e.master_record_id
  where e.tenant_id = v_job.tenant_id and m.code = trim(v_payload ->> 'employee_number');
  if v_employee_id is null then
    v_errors := v_errors || ('employee_number: ' || coalesce(v_payload ->> 'employee_number', '(missing)') || ' does not resolve to an employee of this tenant');
  elsif exists (select 1 from app.employees where master_record_id = v_employee_id and lifecycle_status in ('terminated', 'archived')) then
    v_errors := v_errors || ('employee_number: ' || (v_payload ->> 'employee_number') || ' is not an active employee');
  end if;

  begin
    v_principal := (nullif(trim(coalesce(v_payload ->> 'principal_amount', '')), ''))::numeric;
  exception when others then v_principal := null; end;
  if v_principal is null or v_principal <= 0 then
    v_errors := v_errors || ('principal_amount: ' || coalesce(v_payload ->> 'principal_amount', '(missing)') || ' must be a positive number');
  end if;

  begin
    v_installment := (nullif(trim(coalesce(v_payload ->> 'installment_amount', '')), ''))::numeric;
  exception when others then v_installment := null; end;
  if v_installment is null or v_installment <= 0 then
    v_errors := v_errors || ('installment_amount: ' || coalesce(v_payload ->> 'installment_amount', '(missing)') || ' must be a positive number');
  end if;

  begin
    v_term_count := (nullif(trim(coalesce(v_payload ->> 'term_count', '')), ''))::integer;
  exception when others then v_term_count := null; end;
  if v_term_count is null or v_term_count <= 0 or v_term_count > 360 then
    v_errors := v_errors || ('term_count: ' || coalesce(v_payload ->> 'term_count', '(missing)') || ' must be a whole number of installments between 1 and 360');
  end if;

  begin
    v_remaining := (nullif(trim(coalesce(v_payload ->> 'remaining_installments', '')), ''))::integer;
  exception when others then v_remaining := null; end;
  if v_remaining is null or v_remaining < 0 then
    v_errors := v_errors || ('remaining_installments: ' || coalesce(v_payload ->> 'remaining_installments', '(missing)') || ' must be zero or a positive whole number -- zero means the loan is fully repaid as of cutover');
  elsif v_term_count is not null and v_remaining > v_term_count then
    v_errors := v_errors || ('remaining_installments: ' || v_remaining || ' cannot exceed term_count ' || v_term_count);
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

comment on function app.validate_payroll_loan_cutover_import_row is
  'ISS-2026-317: row-level validation for payroll_loan_cutover_import. Re-derives only what can be answered earlier and cheaper than the commit step -- employee number resolving to an active employee of this tenant, positive principal/installment amounts, a term count between 1 and 360, and a remaining-installments count between 0 and term_count -- and leaves the authoritative loan-issuance rule inside app.issue_payroll_loan.';

-- ---------------------------------------------------------------------------------------
-- STEP 5: app.commit_payroll_loan_cutover_import_job -- security definer, mirroring
-- app.commit_leave_opening_balance_import_job's shape exactly, including the administrative
-- gate on top of the module permission: bulk-importing loans rewrites every named employee's
-- own repayment schedule in one call, which is the same reasoning ISS-2026-303 applied to bulk
-- leave-balance loads.
-- ---------------------------------------------------------------------------------------

create function app.commit_payroll_loan_cutover_import_job(
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
  'ISS-2026-317: commits a payroll_loan_cutover_import job by calling app.issue_payroll_loan once per valid row with p_is_opening_balance=true -- it writes no loan or installment row itself, so that primitive''s HRS:Approve gate, positive-terms rule, opening-balance instalment-numbering and audit event all apply to an imported loan unchanged. Gated on HRS:Import AND HRS:Approve (the same authority app.issue_payroll_loan already demands of its caller for one loan at a time -- a bulk cutover is not exempt) plus administrative (tenant_admin/Supreme Admin) authority, mirroring app.commit_leave_opening_balance_import_job''s administrative gate -- a bulk cutover rewrites every named employee''s own repayment schedule in one call. Keys are derived from the staging row id via the source_import_staging_row_id column, never taken from the file; already-loaded rows are skipped and counted so a partially-committed job resumes.';

-- ---------------------------------------------------------------------------------------
-- STEP 6: grants + public.* wrappers.
-- ---------------------------------------------------------------------------------------

revoke execute on all functions in schema app from public;

grant execute on function app.validate_payroll_loan_cutover_import_row(uuid, uuid, text) to service_role;
grant execute on function app.commit_payroll_loan_cutover_import_job(uuid, boolean, uuid, text, text) to service_role;

create function public.validate_payroll_loan_cutover_import_row(p_staging_row_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.import_staging_rows
language sql
set search_path = app, public, pg_temp
as $wrap$
  select * from app.validate_payroll_loan_cutover_import_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.validate_payroll_loan_cutover_import_row(uuid, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin invoker-rights pass-through, never a reimplementation -- invoker rather than definer because the app.* function it wraps is, and the wrapper-parity gate requires the two sides to agree.';

revoke execute on function public.validate_payroll_loan_cutover_import_row(uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.validate_payroll_loan_cutover_import_row(uuid, uuid, text) to service_role;

create function public.commit_payroll_loan_cutover_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
returns app.jobs
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.commit_payroll_loan_cutover_import_job(p_job_id, p_allow_partial, p_actor_auth_user_id, p_actor_label, p_client_ip);
$wrap$;

comment on function public.commit_payroll_loan_cutover_import_job is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through, never a reimplementation.';

revoke execute on function public.commit_payroll_loan_cutover_import_job(uuid, boolean, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.commit_payroll_loan_cutover_import_job(uuid, boolean, uuid, text, text) to service_role;
