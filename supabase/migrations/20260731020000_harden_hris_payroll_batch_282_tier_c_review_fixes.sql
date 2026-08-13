-- HRIS capability HRT-282 (Prompt 282, CG-S12-HRT-010) -- Tier C batch
-- adversarial review fix pass (BUILD_EXECUTION_PROTOCOL.md section 5).
-- HRT-282 is its own single-prompt batch. 4 parallel review lenses (spec-
-- compliance; security/RLS/tenant isolation; correctness/concurrency;
-- cross-prompt integration) each independently re-verified live against a
-- disposable Postgres 16 database. Every fix below closes a finding that was
-- independently RE-DERIVED live by the orchestrating session before being
-- accepted -- never fixed from a lens citation alone (section 5.3). Full
-- disposition table, propagation-sweep record, and fresh gate numbers are in
-- docs/build-log/phase-07/HRT-282.md's own Tier C batch-review section.
--
-- Per AGENTS.md "never edit an applied migration; add a new migration" --
-- 20260731000000_create_hris_payroll_foundation.sql and
-- 20260731010000_bind_hris_payroll_to_finance_handoff.sql are both left
-- untouched. Every behavioral fix below is a `create or replace function`
-- against a function those two migrations defined, or new additive DDL --
-- the exact, established shape 20260730990000 (HRT-281's own Tier C fix)
-- and every prior HRT/ATW hardening migration already used.
--
-- ===========================================================================
-- Fix 1 (CRITICAL -- security lens Finding A, integration lens Finding 2,
-- LIVE-CONFIRMED). Unmasked compensation amounts and free-text decision/
-- cancel/resolution reasons leaked into app.audit_logs, readable by ANY
-- tenant_admin (app.query_audit_logs gates on app.is_support_grant_authority
-- = Supreme Admin OR the tenant's own active tenant_admin -- a materially
-- BROADER bar than the HRS:View payroll gate every other payroll read
-- surface requires), defeating decision 5's entire compensation-visibility
-- model. Live-reproduced exactly as both lenses described: a bare
-- tenant_admin holding ZERO HRS role, correctly denied on every raw table
-- and read RPC, read a real reimbursement amount+employee_id, a real loan
-- principal_amount+employee_id, and real free-text decision/finalize/cancel
-- reason text straight out of app.query_audit_logs.
--
-- app.redact_audit_payload() (20260716113048) is NOT touched -- its
-- key-name regex is a repository-wide, cross-domain shared primitive; widening
-- it for this one domain's field names is out of this batch's scope and risks
-- an unreviewed behavior change to every OTHER capability's audit trail.
-- Instead, exactly HRT-281's OWN established Tier C fix pattern
-- (20260730990000) is reused: stop ROUTING sensitive reason text into
-- capture_audit_event's unredacted `p_reason` parameter, and stop building an
-- `after_value` jsonb that carries a raw money figure. Every one of the
-- functions below is otherwise byte-for-byte unchanged from
-- 20260731000000/20260731010000 -- only the audit-capture call itself is
-- narrowed.
-- ===========================================================================

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
  if not found then
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

comment on function app.reopen_payroll_period_inputs is
  'HRT-282: HRS:Override-gated, blocked while any run for this period has advanced past draft -- prevents reopening inputs out from under a run that has already calculated/is under review/pending approval/finalized. Tier C fix: p_reason no longer routed into the audit trail unredacted (was readable by any tenant_admin regardless of HRS:View payroll).';

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
  if not found then
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

comment on function app.end_payroll_component_assignment is
  'HRT-282. Tier C fix: p_end_reason no longer routed into the audit trail unredacted.';

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
  if not found then
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

comment on function app.decide_payroll_reimbursement_request is
  'HRT-282 (taxonomy C-18): self-approval structurally blocked before any decision-branch logic. Tier C fix: p_decided_reason no longer routed into the audit trail unredacted (LIVE-CONFIRMED able to carry medical/personal-data-shaped free text, readable by any tenant_admin regardless of HRS:View payroll).';

create or replace function app.cancel_payroll_reimbursement_request(p_request_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_reimbursement_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.payroll_reimbursement_requests;
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_request from app.payroll_reimbursement_requests where id = p_request_id for update;
  if not found then
    raise exception 'payroll_reimbursement_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;
  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  if not (v_self.master_record_id = v_request.employee_id or app.check_payroll_authority('Edit', v_request.tenant_id, p_actor_auth_user_id)) then
    raise exception 'insufficient_authority: identity % may not cancel this reimbursement request', p_actor_auth_user_id using errcode = 'insufficient_privilege';
  end if;
  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status not in ('draft', 'pending_approval') then
    raise exception 'invalid_transition: request % is % -- only draft/pending_approval may be cancelled', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to cancel a reimbursement request' using errcode = 'check_violation';
  end if;

  update app.payroll_reimbursement_requests set status = 'cancelled', cancel_reason = p_reason where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: concurrent update detected for request %', p_request_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_payroll_reimbursement_request',
    'app.payroll_reimbursement_requests', v_request.id, 'success', null, null, null
  );

  return v_request;
end;
$$;

comment on function app.cancel_payroll_reimbursement_request is
  'HRT-282. Tier C fix: p_reason no longer routed into the audit trail unredacted.';

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
  if not found then
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

comment on function app.cancel_payroll_loan is
  'HRT-282. Tier C fix: p_reason no longer routed into the audit trail unredacted.';

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
  if not found then
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

comment on function app.resolve_payroll_exception is
  'HRT-282. Tier C fix: p_resolution_note no longer routed into the audit trail unredacted (a resolution note may describe a specific salary/calculation issue).';

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
  if not found then
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

comment on function app.waive_payroll_exception is
  'HRT-282. Tier C fix: p_resolution_note no longer routed into the audit trail unredacted.';

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
  if not found then
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

comment on function app.cancel_payroll_run is
  'HRT-282. Tier C fix: p_reason no longer routed into the audit trail unredacted. IS wired to a live UI caller (hris/payroll/actions.ts:cancelPayrollRunAction, payroll-admin-panel.tsx) -- the original build log''s own C-20 disclosure list incorrectly named this function as having no UI caller; corrected in the Tier C batch review record.';

create or replace function app.finalize_payroll_run(p_request_step_id uuid, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_approval_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_run app.payroll_runs;
  v_period app.payroll_periods;
  v_result app.payroll_run_employee_results;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id using errcode = 'no_data_found';
  end if;
  select * into v_approval_request from app.approval_requests where id = v_step.request_id;
  if v_approval_request.entity_type <> 'payroll_run' or v_approval_request.entity_id is null then
    raise exception 'not_a_payroll_run_approval: approval request % is not a payroll run finalization approval', v_approval_request.id
      using errcode = 'check_violation';
  end if;

  select * into v_run from app.payroll_runs where id = v_approval_request.entity_id for update;

  -- The REAL authority gate -- PLT-123's own eligible-approver-identity
  -- check AND its own allow_self_approval=false-by-default self-decision
  -- block (decision 6, RPD-023's disclosed compensating control). Called
  -- BEFORE any payroll-domain-specific logic runs (taxonomy C-05).
  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_approval_request.id;

  if v_updated_request.status = 'approved' then
    -- Re-select FOR UPDATE -- taxonomy C-04, the run row must be locked
    -- across the whole decide-then-act window, not merely read once above
    -- before app.decide_approval_step (which itself may have taken time
    -- under contention).
    select * into v_run from app.payroll_runs where id = v_approval_request.entity_id for update;
    if v_run.status <> 'pending_approval' then
      raise exception 'invalid_transition: run % is % -- expected pending_approval', v_run.id, v_run.status using errcode = 'check_violation';
    end if;

    update app.payroll_runs set status = 'finalized', finalized_by = p_actor_label, finalized_at = now() where id = v_run.id
    returning * into v_run;

    if v_run.run_type = 'regular' then
      select * into v_period from app.payroll_periods where id = v_run.payroll_period_id for update;
      update app.payroll_periods set status = 'finalized', finalized_at = now() where id = v_period.id;
    end if;

    for v_result in select * from app.payroll_run_employee_results where payroll_run_id = v_run.id loop
      perform app._generate_payroll_payslip(v_run, v_result, p_actor_label);
    end loop;

    -- Tier C fix 1: p_reason (an entire payroll run's finalize decision
    -- rationale) no longer routed into the audit trail unredacted.
    perform app.capture_audit_event(
      v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'finalize_payroll_run',
      'app.payroll_runs', v_run.id, 'success', null, null, jsonb_build_object('status', v_run.status)
    );
  else
    update app.payroll_runs set status = 'calculated', decided_reason = p_reason where id = v_approval_request.entity_id
    returning * into v_run;

    perform app.capture_audit_event(
      v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'finalize_payroll_run_rejected',
      'app.payroll_runs', v_run.id, 'success', null, null, jsonb_build_object('status', v_run.status)
    );
  end if;

  return v_run;
end;
$$;

comment on function app.finalize_payroll_run is
  'HRT-282 (decision 6, mandatory reading item 4): the CHECKER step, mirrors app.decide_leave_request (HRT-280) exactly -- calls app.decide_approval_step FIRST, before any payroll-domain-specific effect, and re-locks the run row FOR UPDATE after that gate clears (taxonomy C-04, defends against a concurrent second finalize attempt racing the SAME approved step). On approve: finalizes the run, locks the period (only for run_type=regular), and generates every employee''s private payslip. On reject: kicks the run back to calculated for correction/resubmission, never a dead end. Tier C fix: p_reason no longer routed into the audit trail unredacted on either branch (was readable by any tenant_admin regardless of HRS:View payroll).';

create or replace function app.prepare_finance_payroll_disbursement_handoff_from_payroll_run(p_tenant_id uuid, p_run_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_finance_handoff_batches
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
  v_existing app.payroll_finance_handoff_batches;
  v_batch app.payroll_finance_handoff_batches;
  v_gross numeric(14, 2);
  v_deductions numeric(14, 2);
  v_tax numeric(14, 2);
  v_benefit numeric(14, 2);
  v_reimb numeric(14, 2);
  v_loan numeric(14, 2);
  v_net numeric(14, 2);
  v_count integer;
begin
  -- Payroll's OWN authority (HRS:Approve) generates the handoff -- this is
  -- still Payroll acting on its own finalized data, never a Finance action.
  if not app.check_payroll_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_run from app.payroll_runs where id = p_run_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if v_run.status <> 'finalized' then
    raise exception 'payroll_run_not_finalized: run % is % -- only a finalized run may generate a Finance handoff', p_run_id, v_run.status
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.payroll_finance_handoff_batches where payroll_run_id = p_run_id;
  if found then
    return v_existing;
  end if;

  select
    coalesce(sum(gross_earnings), 0), coalesce(sum(total_deductions), 0), coalesce(sum(total_tax), 0),
    coalesce(sum(total_benefit_employer_cost), 0), coalesce(sum(total_reimbursement), 0), coalesce(sum(total_loan_repayment), 0),
    coalesce(sum(net_pay), 0), count(*)
  into v_gross, v_deductions, v_tax, v_benefit, v_reimb, v_loan, v_net, v_count
  from app.payroll_run_employee_results where payroll_run_id = p_run_id;

  insert into app.payroll_finance_handoff_batches (
    tenant_id, payroll_run_id, payroll_period_id, currency, gross_earnings_total, total_deductions_total, total_tax_total,
    total_benefit_employer_cost_total, total_reimbursement_total, total_loan_repayment_total, net_pay_total, employee_count, generated_by
  ) values (
    p_tenant_id, p_run_id, v_run.payroll_period_id, v_run.currency, v_gross, v_deductions, v_tax, v_benefit, v_reimb, v_loan, v_net, v_count, p_actor_label
  )
  returning * into v_batch;

  insert into app.payroll_finance_handoff_gl_lines (handoff_batch_id, tenant_id, line_type, gl_mapping_category, amount, currency)
  select v_batch.id, p_tenant_id, l.line_type, coalesce(c.gl_mapping_category, 'loan_or_reimbursement'), sum(l.amount), l.currency
  from app.payroll_calculation_lines l
  left join app.payroll_components c on c.id = l.component_id
  where l.payroll_run_id = p_run_id
  group by l.line_type, coalesce(c.gl_mapping_category, 'loan_or_reimbursement'), l.currency;

  insert into app.payroll_finance_handoff_payment_instructions (handoff_batch_id, tenant_id, employee_id, net_pay_amount, currency, bank_reference_masked)
  select v_batch.id, p_tenant_id, r.employee_id, r.net_pay, r.currency, null
  from app.payroll_run_employee_results r
  where r.payroll_run_id = p_run_id;

  -- Tier C fix (propagation sweep): net_pay_total is a whole-run aggregate,
  -- not a single employee's compensation, but it is still a real financial
  -- figure correlatable via payroll_run_id -- dropped from the audit
  -- after_value for the same reason as every other money-bearing site above.
  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_payroll_disbursement_handoff_from_payroll_run',
    'app.payroll_finance_handoff_batches', v_batch.id, 'success', null, null,
    jsonb_build_object('payroll_run_id', p_run_id, 'employee_count', v_count)
  );

  return v_batch;
end;
$$;

comment on function app.prepare_finance_payroll_disbursement_handoff_from_payroll_run is
  'HRT-282 (decision 1): mirrors app.prepare_finance_vendor_bill_from_actual_cost (FIN-200) exactly -- idempotent on payroll_run_id (a replay returns the existing batch unchanged, never a second batch for the same run); sums this run''s ALREADY-COMPUTED, immutable app.payroll_run_employee_results/app.payroll_calculation_lines -- never re-derives or re-calculates a figure. Zero write to any app.finance_* table -- grep-verified. Tier C fix: net_pay_total dropped from the audit after_value (propagation sweep of Tier C fix 1).';

-- ===========================================================================
-- Fix 2 (MEDIUM -- security lens Finding B, LIVE-CONFIRMED). The 3
-- Finance-handoff tables' own `_select_scoped` RLS policies called
-- app.evaluate_permission(...) DIRECTLY inside `USING (...)`.
-- app.evaluate_permission is EXECUTE-granted to service_role ONLY
-- (20260716104519); an RLS policy predicate always evaluates as the
-- QUERYING role, never the policy-defining migration's owner, so this threw
-- `permission denied for function evaluate_permission` for every
-- `authenticated` caller attempting a raw SELECT on these 3 tables --
-- LIVE-REPRODUCED for a genuinely FIN:Edit-holding actor (the table's own
-- intended reader), a zero-permission member, a cross-tenant tenant_admin,
-- and an HRS:View payroll holder alike. Fails CLOSED (a hard error, zero
-- rows disclosed) -- not a confidentiality leak, but a genuine functional
-- break of "gated identically to every other payroll table PLUS FIN:View"
-- (20260731010000's own header claim). Not reachable through the app's own
-- UI today (server/queries/payroll.ts always calls the SECURITY DEFINER RPCs,
-- unaffected since they run as the function owner), but reachable by any
-- direct PostgREST GET against these 3 tables, which their own
-- `grant select ... to authenticated` specifically enables.
--
-- Fix: the exact established pattern app.check_payroll_authority already
-- uses -- a SECURITY DEFINER wrapper, granted to authenticated, directly
-- usable from an RLS policy expression.
-- ===========================================================================

create function app.check_payroll_finance_handoff_view_authority(p_tenant_id uuid, p_actor_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', 'View')).allowed;
$$;

comment on function app.check_payroll_finance_handoff_view_authority is
  'HRT-282 Tier C fix (security lens Finding B, LIVE-CONFIRMED): SECURITY DEFINER from the start, mirroring app.check_payroll_authority''s own established shape and its exact HRT-281 self-found-defect-3 lesson -- a bare SECURITY INVOKER wrapper around app.evaluate_permission fails for any RLS policy expression, since a policy predicate always evaluates as the querying `authenticated` role, never this function''s owner. Directly usable from RLS, never a second helper.';

drop policy payroll_finance_handoff_batches_select_scoped on app.payroll_finance_handoff_batches;
create policy payroll_finance_handoff_batches_select_scoped on app.payroll_finance_handoff_batches
  for select to authenticated
  using (
    app.is_supreme_admin()
    or app.check_payroll_authority('View payroll', tenant_id, auth.uid())
    or app.check_payroll_finance_handoff_view_authority(tenant_id, auth.uid())
  );

drop policy payroll_finance_handoff_gl_lines_select_scoped on app.payroll_finance_handoff_gl_lines;
create policy payroll_finance_handoff_gl_lines_select_scoped on app.payroll_finance_handoff_gl_lines
  for select to authenticated
  using (
    app.is_supreme_admin()
    or app.check_payroll_authority('View payroll', tenant_id, auth.uid())
    or app.check_payroll_finance_handoff_view_authority(tenant_id, auth.uid())
  );

drop policy payroll_finance_handoff_payment_instructions_select_scoped on app.payroll_finance_handoff_payment_instructions;
create policy payroll_finance_handoff_payment_instructions_select_scoped on app.payroll_finance_handoff_payment_instructions
  for select to authenticated
  using (
    app.is_supreme_admin()
    or app.can_view_hris_payroll_row(tenant_id, employee_id, auth.uid())
    or app.check_payroll_finance_handoff_view_authority(tenant_id, auth.uid())
  );

comment on policy payroll_finance_handoff_batches_select_scoped on app.payroll_finance_handoff_batches is
  'HRT-282 migration 2, Tier C-fixed: readable by either side of the handoff boundary -- Payroll (HRS:View payroll) or Finance (FIN:View, via the SECURITY DEFINER app.check_payroll_finance_handoff_view_authority) -- never by plain tenant membership. The original policy called app.evaluate_permission directly, which is service_role-only -- fixed to route through a SECURITY DEFINER wrapper (LIVE-CONFIRMED broken before this fix, for every authenticated caller including a genuinely FIN:Edit-holding one).';

-- ===========================================================================
-- Fix 3 (HIGH -- correctness lens Finding 1, LIVE-CONFIRMED via two genuinely
-- concurrent OS `psql` processes, for both the (tenant, code) natural key on
-- app.payroll_periods/app.payroll_components AND the (component_id,
-- version_number) natural key on app.payroll_component_versions).
-- create_payroll_period/create_payroll_component/create_payroll_component_
-- version all used a check-then-insert pattern with NO exception handler,
-- unlike their sibling app.create_payroll_run (which already correctly
-- catches unique_violation). A raw, undiscriminated 23505 leaked to the
-- losing concurrent caller, unclassifiable by
-- PAYROLL_KNOWN_MUTATION_ERROR_CODES (resolves to "unknown").
-- ===========================================================================

create or replace function app.create_payroll_period(
  p_tenant_id uuid, p_org_unit_id uuid, p_code text, p_period_type text,
  p_period_start date, p_period_end date, p_pay_date date,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_periods
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.payroll_periods;
begin
  if not app.check_payroll_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_period from app.payroll_periods where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_period;
  end if;

  begin
    insert into app.payroll_periods (tenant_id, org_unit_id, code, period_type, period_start, period_end, pay_date, created_by)
    values (p_tenant_id, p_org_unit_id, p_code, coalesce(p_period_type, 'monthly'), p_period_start, p_period_end, p_pay_date, p_actor_label)
    returning * into v_period;
  exception
    -- Tier C fix (correctness lens Finding 1, LIVE-CONFIRMED with two
    -- genuinely concurrent psql processes): both callers can pass the
    -- "not found" check above before either commits; without this handler
    -- the loser previously received a raw, undiscriminated 23505.
    when unique_violation then
      raise exception 'payroll_period_code_conflict: a payroll period with code % was just created concurrently for tenant % -- retry the read', p_code, p_tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_payroll_period',
    'app.payroll_periods', v_period.id, 'success', null, null, jsonb_build_object('code', p_code)
  );

  return v_period;
end;
$$;

comment on function app.create_payroll_period is
  'HRT-282: idempotent on (tenant_id, code) -- a replay with the same code returns the existing row unchanged, matching this repository''s own established idempotent-create shape. Tier C fix: a genuinely concurrent duplicate create now raises a clean, classifiable payroll_period_code_conflict instead of leaking a raw 23505.';

create or replace function app.create_payroll_component(
  p_tenant_id uuid, p_code text, p_name text, p_component_type text, p_gl_mapping_category text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_components
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_component app.payroll_components;
begin
  if not app.check_payroll_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_component_type not in ('earning', 'deduction', 'benefit_employer_cost', 'tax') then
    raise exception 'invalid_component_type: % is not a supported component type', p_component_type using errcode = 'check_violation';
  end if;

  select * into v_component from app.payroll_components where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_component;
  end if;

  begin
    insert into app.payroll_components (tenant_id, code, name, component_type, is_statutory, gl_mapping_category, created_by)
    values (p_tenant_id, p_code, p_name, p_component_type, false, p_gl_mapping_category, p_actor_label)
    returning * into v_component;
  exception
    when unique_violation then
      raise exception 'payroll_component_code_conflict: a payroll component with code % was just created concurrently for tenant % -- retry the read', p_code, p_tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_payroll_component',
    'app.payroll_components', v_component.id, 'success', null, null, jsonb_build_object('code', p_code, 'component_type', p_component_type)
  );

  return v_component;
end;
$$;

comment on function app.create_payroll_component is
  'HRT-282 (decision 3): tenant-scoped only -- a caller can never create a tenant_id-null platform-wide statutory label through this entrypoint (is_statutory is hardcoded false here); those are seeded, Supreme-Admin-owned rows only. Idempotent on (tenant_id, code). Tier C fix: a genuinely concurrent duplicate create now raises a clean, classifiable payroll_component_code_conflict instead of leaking a raw 23505.';

create or replace function app.create_payroll_component_version(
  p_component_id uuid, p_calculation_method text, p_fixed_amount numeric, p_percentage_rate numeric,
  p_percentage_of_component_id uuid, p_currency text, p_effective_from date,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_component_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_component app.payroll_components;
  v_version app.payroll_component_versions;
  v_next_version integer;
begin
  select * into v_component from app.payroll_components where id = p_component_id;
  if not found then
    raise exception 'payroll_component_not_found: %', p_component_id using errcode = 'no_data_found';
  end if;
  if not app._check_payroll_component_authority('Edit', v_component.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not author a version of component %', p_actor_auth_user_id, p_component_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_calculation_method not in ('fixed_amount', 'hourly_rate', 'percentage_of_component', 'manual_per_run') then
    raise exception 'invalid_calculation_method: %', p_calculation_method using errcode = 'check_violation';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.payroll_component_versions where component_id = p_component_id;

  begin
    insert into app.payroll_component_versions (
      component_id, tenant_id, version_number, calculation_method, fixed_amount, percentage_rate,
      percentage_of_component_id, currency, effective_from, is_example_fixture, created_by
    ) values (
      p_component_id, v_component.tenant_id, v_next_version, p_calculation_method, p_fixed_amount, p_percentage_rate,
      p_percentage_of_component_id, coalesce(p_currency, 'IDR'), p_effective_from, false, p_actor_label
    )
    returning * into v_version;
  exception
    -- Tier C fix (correctness lens Finding 1, LIVE-CONFIRMED with two
    -- genuinely concurrent psql processes computing the SAME v_next_version
    -- before either commits).
    when unique_violation then
      raise exception 'payroll_component_version_conflict: a version for component % was just created concurrently -- retry to get the current next version number', p_component_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_component.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_payroll_component_version',
    'app.payroll_component_versions', v_version.id, 'success', null, null, jsonb_build_object('component_id', p_component_id, 'version_number', v_next_version)
  );

  return v_version;
end;
$$;

comment on function app.create_payroll_component_version is
  'HRT-282 (decisions 3, 8): every user-created draft has is_example_fixture=false unconditionally -- only this migration''s own seed INSERT ever sets it true. calculation_method is bounded to the three supported methods (decision 8) -- no free-text formula evaluator exists anywhere in this capability. Tier C fix: a genuinely concurrent duplicate version-number create now raises a clean, classifiable payroll_component_version_conflict instead of leaking a raw 23505.';

-- ===========================================================================
-- Fix 4 (MEDIUM-HIGH -- correctness lens Finding 2, LIVE-CONFIRMED).
-- app.freeze_payroll_period_inputs had NO guard against re-freezing a period
-- that already has a run past draft, unlike its sibling
-- app.reopen_payroll_period_inputs (which already correctly counts advanced
-- runs and cleanly rejects with payroll_period_has_advanced_run). The
-- migration's own comments (both on freeze and reopen) asserted reopen is
-- "the only path back to input_frozen after calculation has started" --
-- LIVE-DISPROVEN: re-freezing a period with a `calculated` (or
-- `pending_approval`) run was blocked only by an incidental raw 23503 FK
-- violation on payroll_run_employee_results.input_snapshot_id, once the
-- DELETE FROM payroll_input_snapshots inside freeze hit a snapshot a run had
-- already referenced. Fixed by adding the EXACT SAME guard reopen already
-- has, before the DELETE ever runs.
-- ===========================================================================

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
  if not found then
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

comment on function app.freeze_payroll_period_inputs is
  'HRT-282: bounded, synchronous per-period input freeze (section 17''s own "no unbounded scan" -- bounded to this ONE period''s own active/on_leave employees, org_unit-scoped when the period itself is). Re-callable while still open/input_frozen (a genuine re-freeze after a reopen, decision 2) -- DELETEs and re-INSERTs snapshot rows for this period only, never once a run has advanced past calculated for it. Tier C fix (correctness lens Finding 2, LIVE-CONFIRMED): now explicitly, cleanly guarded against re-freezing while any run for this period has advanced past draft, mirroring app.reopen_payroll_period_inputs'' own identical guard -- was previously only incidentally blocked by a raw FK-violation, unclassifiable by PAYROLL_KNOWN_MUTATION_ERROR_CODES.';

-- ===========================================================================
-- Fix 5 (MEDIUM -- correctness lens Finding 5, LIVE-CONFIRMED).
-- app.create_payroll_run never validated that a correction/adjustment run's
-- own p_period_id matches the p_adjusts_run_id target's own
-- payroll_period_id -- LIVE-CONFIRMED: created a `correction` run against a
-- brand-new, unrelated, never-frozen period while adjusts_run_id pointed at
-- a DIFFERENT period's finalized run, with zero error. Also folds in the
-- integration lens's idempotency-replay finding: the replay comparison
-- omitted `currency`, matching the established "full-tuple idempotency
-- replay" class this repository's own C-01 taxonomy entry requires.
-- ===========================================================================

create or replace function app.create_payroll_run(p_tenant_id uuid, p_period_id uuid, p_run_type text, p_adjusts_run_id uuid, p_currency text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.payroll_periods;
  v_adjusted app.payroll_runs;
  v_existing app.payroll_runs;
  v_run app.payroll_runs;
begin
  if not app.check_payroll_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  select * into v_period from app.payroll_periods where id = p_period_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'payroll_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;
  if p_run_type not in ('regular', 'off_cycle', 'correction', 'adjustment') then
    raise exception 'invalid_run_type: %', p_run_type using errcode = 'check_violation';
  end if;
  if p_run_type = 'regular' and v_period.status = 'open' then
    raise exception 'payroll_period_inputs_not_frozen: period % has not had its inputs frozen yet', p_period_id using errcode = 'check_violation';
  end if;
  if p_run_type in ('correction', 'adjustment') then
    if p_adjusts_run_id is null then
      raise exception 'adjusts_run_id_required: % runs must reference the run they correct', p_run_type using errcode = 'check_violation';
    end if;
    select * into v_adjusted from app.payroll_runs where id = p_adjusts_run_id and tenant_id = p_tenant_id;
    if not found or v_adjusted.status <> 'finalized' then
      raise exception 'payroll_run_adjust_target_not_finalized: % is not a finalized run for tenant %', p_adjusts_run_id, p_tenant_id using errcode = 'check_violation';
    end if;
    -- Tier C fix (correctness lens Finding 5, LIVE-CONFIRMED): a correction/
    -- adjustment run's own period must be the SAME period as the run it
    -- corrects -- otherwise a correction's financial effect misattributes to
    -- the wrong period in period-scoped reporting/reconciliation (e.g.
    -- app.payroll_finance_handoff_batches, which keys off payroll_period_id
    -- directly).
    if v_adjusted.payroll_period_id <> p_period_id then
      raise exception 'payroll_run_adjust_period_mismatch: run % corrects a run belonging to period %, not the requested period %', p_adjusts_run_id, v_adjusted.payroll_period_id, p_period_id
        using errcode = 'check_violation';
    end if;
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.payroll_runs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      -- Tier C fix (integration lens, full-tuple idempotency replay class):
      -- currency was previously omitted from this comparison.
      if v_existing.payroll_period_id = p_period_id and v_existing.run_type = p_run_type and v_existing.adjusts_run_id is not distinct from p_adjusts_run_id
         and v_existing.currency = coalesce(p_currency, 'IDR') then
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: key % was already used for a different payroll run', p_idempotency_key using errcode = 'check_violation';
    end if;
  end if;

  begin
    insert into app.payroll_runs (tenant_id, payroll_period_id, run_type, adjusts_run_id, currency, idempotency_key, created_by)
    values (p_tenant_id, p_period_id, p_run_type, p_adjusts_run_id, coalesce(p_currency, 'IDR'), p_idempotency_key, p_actor_label)
    returning * into v_run;
  exception
    when unique_violation then
      raise exception 'payroll_run_already_active: an active regular run already exists for period %', p_period_id using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_payroll_run',
    'app.payroll_runs', v_run.id, 'success', null, null, jsonb_build_object('period_id', p_period_id, 'run_type', p_run_type)
  );

  return v_run;
end;
$$;

comment on function app.create_payroll_run is
  'HRT-282. Tier C fix: a correction/adjustment run''s own period must match the finalized run it corrects (payroll_run_adjust_period_mismatch, LIVE-CONFIRMED gap); idempotency replay comparison now includes currency.';

-- ===========================================================================
-- Fix 6 (HIGH -- integration lens Finding 1, LIVE-CONFIRMED end to end).
-- app._resolve_payroll_time_inputs_for_period only counted an ACTIVE
-- app.payroll_time_inputs row's regular/overtime minutes when its OWN
-- app.timesheet_periods window fell ENTIRELY inside the requested payroll
-- period range. A weekly timesheet period straddling a monthly payroll
-- period's boundary (a routine, ordinary configuration) caused the ENTIRE
-- row's minutes to silently vanish -- LIVE-REPRODUCED: a real, HR-approved
-- 480-minute timesheet entry for a work_date genuinely inside the payroll
-- period produced regular_minutes=0 in the frozen snapshot, zero
-- error/exception/audit trace, because its OWN timesheet period (Jul 27 -
-- Aug 2) started one day before the Aug 1 payroll-period start.
--
-- Fixed at root cause: contribution is now computed per WORK_DATE from the
-- underlying app.timesheet_entries/app.overtime_requests rows the payroll
-- time input's own source_entry_ids/source_overtime_request_ids reference,
-- restricted to work_dates inside [p_period_start, p_period_end] -- not from
-- the timesheet period's own pre-aggregated whole-period total. A work_date
-- still contributes through exactly one source, never both (v_covered_dates
-- is now exactly the work-date-level set actually contributed, so the
-- attendance fallback in step 2 -- unchanged -- still only ever fills a
-- work_date NOT already covered here). The full-containment case (the
-- original, already-passing scenario) is unaffected -- this is a strict
-- generalization from "entire period contained" to "any overlap,
-- work-date-scoped", never a narrowing.
-- ===========================================================================

create or replace function app._resolve_payroll_time_inputs_for_period(
  p_tenant_id uuid, p_employee_id uuid, p_period_start date, p_period_end date
)
returns table (
  regular_minutes integer, overtime_weekday_minutes integer, overtime_weekend_minutes integer, overtime_holiday_minutes integer,
  source_payroll_time_input_ids uuid[], source_attendance_session_ids uuid[]
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_ts_regular integer := 0;
  v_ts_ow integer := 0;
  v_ts_owe integer := 0;
  v_ts_oh integer := 0;
  v_covered_dates date[] := array[]::date[];
  v_pti_ids uuid[] := array[]::uuid[];
  v_att_regular integer := 0;
  v_att_ids uuid[] := array[]::uuid[];
begin
  -- Step 1: every ACTIVE app.payroll_time_inputs row whose own timesheet
  -- period OVERLAPS the payroll period at all (Tier C fix: was previously
  -- gated on full containment, which silently dropped an entire boundary-
  -- straddling week's worth of real, approved time) contributes ONLY the
  -- per-work-date regular minutes for the timesheet_entries it actually
  -- backs whose own work_date falls inside [p_period_start, p_period_end]
  -- -- never the whole timesheet-period total, which could include
  -- out-of-range work_dates on the other side of the boundary.
  select
    coalesce(sum(te.approved_minutes), 0), coalesce(array_agg(distinct pti.id), array[]::uuid[])
  into v_ts_regular, v_pti_ids
  from app.payroll_time_inputs pti
  join app.timesheet_periods tp on tp.id = pti.timesheet_period_id
  join app.timesheet_entries te on te.id = any (pti.source_entry_ids)
  where pti.tenant_id = p_tenant_id and pti.employee_id = p_employee_id and pti.status = 'active'
    and tp.period_start <= p_period_end and tp.period_end >= p_period_start
    and te.work_date between p_period_start and p_period_end
    and te.status = 'approved';

  -- Same overlap/work-date scoping for overtime -- the payroll period only
  -- ever receives the overtime minutes for work_dates genuinely inside it.
  select
    coalesce(sum(ot.approved_minutes) filter (where ot.eligible_classification = 'weekday'), 0),
    coalesce(sum(ot.approved_minutes) filter (where ot.eligible_classification = 'weekend'), 0),
    coalesce(sum(ot.approved_minutes) filter (where ot.eligible_classification = 'holiday'), 0)
  into v_ts_ow, v_ts_owe, v_ts_oh
  from app.payroll_time_inputs pti
  join app.timesheet_periods tp on tp.id = pti.timesheet_period_id
  join app.overtime_requests ot on ot.id = any (pti.source_overtime_request_ids)
  where pti.tenant_id = p_tenant_id and pti.employee_id = p_employee_id and pti.status = 'active'
    and tp.period_start <= p_period_end and tp.period_end >= p_period_start
    and ot.work_date between p_period_start and p_period_end
    and ot.status = 'approved';

  -- v_covered_dates is exactly the work_dates actually contributed above via
  -- timesheet_entries (matches the ORIGINAL function's own scope -- it only
  -- ever populated this from source_entry_ids/timesheet_entries, never from
  -- overtime_requests), so the attendance fallback below still only ever
  -- fills a work_date this step did NOT already cover.
  select coalesce(array_agg(distinct te.work_date), array[]::date[]) into v_covered_dates
  from app.payroll_time_inputs pti
  join app.timesheet_periods tp on tp.id = pti.timesheet_period_id
  join app.timesheet_entries te on te.id = any (pti.source_entry_ids)
  where pti.tenant_id = p_tenant_id and pti.employee_id = p_employee_id and pti.status = 'active'
    and tp.period_start <= p_period_end and tp.period_end >= p_period_start
    and te.work_date between p_period_start and p_period_end
    and te.status = 'approved';

  -- Step 2: approved attendance sessions for any work_date in range NOT
  -- already covered by step 1 -- regular minutes ONLY, never overtime.
  -- (unchanged from the original function.)
  select
    coalesce(sum(greatest(0, round(extract(epoch from (s.effective_clock_out_at - s.effective_clock_in_at)) / 60)))::integer, 0),
    coalesce(array_agg(s.id), array[]::uuid[])
  into v_att_regular, v_att_ids
  from app.attendance_sessions s
  where s.tenant_id = p_tenant_id and s.employee_id = p_employee_id
    and s.work_date between p_period_start and p_period_end
    and s.payroll_input_status = 'approved'
    and s.effective_clock_in_at is not null and s.effective_clock_out_at is not null
    and not (s.work_date = any (v_covered_dates));

  regular_minutes := v_ts_regular + v_att_regular;
  overtime_weekday_minutes := v_ts_ow;
  overtime_weekend_minutes := v_ts_owe;
  overtime_holiday_minutes := v_ts_oh;
  source_payroll_time_input_ids := v_pti_ids;
  source_attendance_session_ids := v_att_ids;
  return next;
end;
$$;

comment on function app._resolve_payroll_time_inputs_for_period is
  'HRT-282 (decision 2, ISS-2026-074 resolution). Tier C fix (integration lens Finding 1, LIVE-CONFIRMED end to end -- a real approved 480-minute boundary-week entry produced regular_minutes=0 before this fix, =480 after): a work_date now contributes through exactly one source, never both, computed per-work-date from the underlying timesheet_entries/overtime_requests rows and scoped to [p_period_start, p_period_end] -- never gated on the owning timesheet_periods row being ENTIRELY inside the payroll period, which silently dropped any boundary-straddling week. service_role only -- called exclusively from app._build_payroll_input_snapshot_for_employee.';

-- ===========================================================================
-- Fix 7 (LOW/MEDIUM -- integration lens Finding 3, LIVE-CONFIRMED by direct
-- code read against the committed function). The reimbursement create
-- idempotency-replay comparison omitted `currency` and `evidence_file_id`
-- from the full-tuple check (the exact C-01 "partial-tuple idempotency"
-- class HRT-281's own Tier C fix closed for unpaid_break_minutes one
-- checkpoint earlier on this same branch). Folded together with the amount
-- masking from Fix 1 since both touch the same function body.
-- ===========================================================================

create or replace function app._create_payroll_reimbursement_request(
  p_tenant_id uuid, p_employee_id uuid, p_category text, p_amount numeric, p_currency text, p_expense_date date,
  p_description text, p_evidence_file_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_reimbursement_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
  v_existing app.payroll_reimbursement_requests;
  v_request app.payroll_reimbursement_requests;
  v_file app.files;
begin
  select * into v_employee from app.employees where master_record_id = p_employee_id and tenant_id = p_tenant_id;
  if not found or v_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'employee_not_active: % is not an active employee for tenant %', p_employee_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount: amount must be positive' using errcode = 'check_violation';
  end if;
  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'description_required: a non-empty description is required' using errcode = 'check_violation';
  end if;
  if p_evidence_file_id is not null then
    -- Taxonomy C-10: re-validate tenant/record scope/scan status at THIS
    -- accepting RPC, never trust the caller's own upload-time classification.
    select * into v_file from app.files where id = p_evidence_file_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'evidence_file_not_found: % is not a known file for tenant %', p_evidence_file_id, p_tenant_id using errcode = 'no_data_found';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'evidence_file_not_clean: % has not passed malware scanning', p_evidence_file_id using errcode = 'check_violation';
    end if;
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.payroll_reimbursement_requests
      where tenant_id = p_tenant_id and employee_id = p_employee_id and idempotency_key = p_idempotency_key;
    if found then
      -- Tier C fix (integration lens Finding 3, full-tuple idempotency
      -- replay class): currency and evidence_file_id were previously
      -- omitted -- a same-key retry with a genuinely different currency or
      -- evidence attachment was silently swallowed.
      if v_existing.category = p_category and v_existing.amount = p_amount and v_existing.expense_date = p_expense_date and v_existing.description = p_description
         and v_existing.currency = coalesce(p_currency, 'IDR') and v_existing.evidence_file_id is not distinct from p_evidence_file_id then
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: key % was already used for a different reimbursement request', p_idempotency_key using errcode = 'check_violation';
    end if;
  end if;

  insert into app.payroll_reimbursement_requests (
    tenant_id, employee_id, category, amount, currency, expense_date, description, evidence_file_id,
    requested_by_auth_user_id, requested_by, idempotency_key, created_by
  ) values (
    p_tenant_id, p_employee_id, p_category, p_amount, coalesce(p_currency, 'IDR'), p_expense_date, p_description, p_evidence_file_id,
    p_actor_auth_user_id, p_actor_label, p_idempotency_key, p_actor_label
  )
  returning * into v_request;

  -- Tier C fix 1 (propagation sweep): `amount` dropped from the audit
  -- after_value -- LIVE-CONFIRMED readable by any tenant_admin via
  -- app.query_audit_logs regardless of HRS:View payroll.
  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_payroll_reimbursement_request',
    'app.payroll_reimbursement_requests', v_request.id, 'success', null, null, jsonb_build_object('employee_id', p_employee_id, 'category', p_category)
  );

  return v_request;
end;
$$;

comment on function app._create_payroll_reimbursement_request is
  'HRT-282. Tier C fix: idempotency replay comparison now includes currency/evidence_file_id (full-tuple class); amount dropped from the audit after_value (LIVE-CONFIRMED readable by any tenant_admin regardless of HRS:View payroll).';

create or replace function app.issue_payroll_loan(
  p_tenant_id uuid, p_employee_id uuid, p_principal_amount numeric, p_currency text, p_installment_amount numeric,
  p_term_count integer, p_is_opening_balance boolean, p_opening_remaining_installments integer, p_notes text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_loans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
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
    is_opening_balance, notes, issued_by, created_by
  ) values (
    p_tenant_id, p_employee_id, p_principal_amount, coalesce(p_currency, 'IDR'), p_installment_amount, p_term_count, v_remaining,
    coalesce(p_is_opening_balance, false), p_notes, p_actor_label, p_actor_label
  )
  returning * into v_loan;

  for i in (p_term_count - v_remaining + 1) .. p_term_count loop
    insert into app.payroll_loan_installments (loan_id, tenant_id, installment_number, amount)
    values (v_loan.id, p_tenant_id, i, p_installment_amount);
  end loop;

  -- Tier C fix 1 (propagation sweep): `principal_amount` dropped from the
  -- audit after_value -- LIVE-CONFIRMED readable by any tenant_admin via
  -- app.query_audit_logs regardless of HRS:View payroll.
  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_payroll_loan',
    'app.payroll_loans', v_loan.id, 'success', null, null, jsonb_build_object('employee_id', p_employee_id, 'term_count', p_term_count)
  );

  return v_loan;
end;
$$;

comment on function app.issue_payroll_loan is
  'HRT-282 (decision 13): p_is_opening_balance=true is the disclosed, bounded cutover path -- only the REMAINING installments (p_opening_remaining_installments) are scheduled, numbered from (term_count - remaining + 1) so a run''s own "next scheduled installment" resolution stays a simple ascending scan regardless of whether the loan started fresh or mid-repayment. Tier C fix: principal_amount dropped from the audit after_value (LIVE-CONFIRMED readable by any tenant_admin regardless of HRS:View payroll).';

-- ===========================================================================
-- Fix 8 (HIGH -- correctness lens Findings 3/4, disclosed + partially fixed).
-- app.calculate_payroll_run's own comment (and this checkpoint's build log)
-- claimed "a real chunk-boundary heartbeat + a record_job_failure-compatible
-- dead-letter path, all reusing PLT-131/132 unchanged." LIVE-CONFIRMED false
-- on the durability claim: the entire job lifecycle
-- (enqueue_job/heartbeat_job/complete_job) runs inside ONE PL/pgSQL function
-- invocation, i.e. one transaction from the caller's perspective (a plain
-- FUNCTION, not a PROCEDURE, so it cannot commit incrementally) --
-- app.claim_next_job/app.record_job_failure, the framework's actual
-- multi-worker-safe claim/backoff/DLQ mechanisms, are never called anywhere
-- in this checkpoint (grep-confirmed). A crash mid-calculation is safe from
-- corruption (full rollback -- no partial/dirty payroll data is ever
-- observable) but is NOT a genuine checkpoint/resume -- the caller must
-- re-invoke the whole batch from scratch. This deeper architectural gap
-- (true multi-transaction, crash-resumable chunked execution) requires a
-- design decision this batch has no mandate to make on its own, and is
-- DISCLOSED, not fixed, in docs/runtime/KNOWN_ISSUES.md (ISS-2026-081).
--
-- The NARROWER, genuinely fixable part of the same finding -- the mid-loop
-- `status = 'cancelling'` check being unreachable dead code, since nothing
-- anywhere ever sets a payroll_calculation job to 'cancelling' (the only
-- function that ever does, app.cancel_import_export_job, is import/export-
-- scoped, gated on a different authority, grep-confirmed 0 occurrences of
-- "cancel" in this checkpoint's own scripts/db-tests/hris-payroll.sql) -- IS
-- fixed here: a new, correctly HRS:Edit-scoped RPC makes that check
-- genuinely reachable. Postgres READ COMMITTED semantics mean a fresh SELECT
-- inside the SAME already-in-flight calculate_payroll_run invocation DOES
-- observe an externally-committed status='cancelling' update at its next
-- chunk-boundary check -- this is a real, live mechanism once something can
-- actually set the flag, not merely decorative.
-- ===========================================================================

create function app.request_payroll_run_calculation_cancellation(p_run_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
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
  if not found then
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

comment on function app.request_payroll_run_calculation_cancellation is
  'HRT-282 Tier C fix (correctness lens Finding 4): the correctly HRS:Edit-scoped caller that makes app.calculate_payroll_run''s own mid-loop cancellation check (status=''cancelling'') genuinely reachable -- previously dead code, since the only function anywhere that ever set a job to ''cancelling'' (app.cancel_import_export_job) is import/export-scoped under a different authority. Intended for the case where a separate session observes a run stuck in status=calculating (a long-running batch) and wants to stop it before it completes; the ALREADY-EXISTING, already-live-tested chunk-boundary check inside app.calculate_payroll_run is unchanged. Real, tested SQL-layer wrapper exists in server/mutations/payroll.ts; no UI form yet -- disclosed as ISS-2026-082, matching this checkpoint''s own established "wrapper with no UI caller" disclosure shape (archive_payroll_component_version and 4 siblings).';

comment on function app.calculate_payroll_run is
  'HRT-282 (sections 17/28): reuses PLT-131/132''s app.jobs framework directly -- app.enqueue_job/app.heartbeat_job/app.complete_job/app.acknowledge_job_cancellation, never a second queue. Chunked at 25 employees per heartbeat/cancellation-check boundary (a genuine checkpoint within this one invocation, not decorative -- see app.request_payroll_run_calculation_cancellation, the Tier C fix that makes it genuinely reachable). A single employee''s calculation failure is caught, recorded as a payroll_exceptions row, and does NOT abort the rest of the batch -- the run lands in status=exception for review rather than either silently dropping that employee or failing the whole run. Never callable once a run has reached pending_approval/finalized/cancelled (business rule: finalized history never silently recalculates). Tier C correction (correctness lens Finding 3, LIVE-CONFIRMED): this checkpoint''s ORIGINAL comment/build-log language overclaimed genuine multi-transaction crash-resumability -- the whole job lifecycle (enqueue/heartbeat/complete) runs inside this ONE function invocation/transaction; app.claim_next_job/app.record_job_failure are never called. A crash mid-calculation rolls back atomically (zero corruption, zero partial/dirty data ever observable) but is NOT resumable from a checkpoint -- the caller must re-invoke the whole batch. Disclosed, not fixed, as ISS-2026-081 (a genuine multi-transaction, crash-resumable redesign is an architectural decision outside this batch''s mandate).';

-- ===========================================================================
-- Grants. Per ERR-2026-004: explicit REVOKE before this migration's own
-- final grants. Every `create or replace function` above targets a function
-- that already carries its correct authenticated/service_role grant from
-- 20260731000000/20260731010000 -- CREATE OR REPLACE never resets an
-- existing grant, so only this migration's 2 genuinely NEW functions need an
-- explicit grant below.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.check_payroll_finance_handoff_view_authority(uuid, uuid) to authenticated, service_role;
grant execute on function app.request_payroll_run_calculation_cancellation(uuid, uuid, text) to authenticated, service_role;
