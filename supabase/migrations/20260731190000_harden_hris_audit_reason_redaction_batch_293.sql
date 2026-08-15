-- HRT-293 (Sensitive Personal and Payroll Data Controls, CG-S12-HRT-021) --
-- repository-wide sweep of Finding B (CRITICAL, C-24) across every Phase 7
-- HR capability OTHER than Employee Master (fixed separately,
-- 20260731180000, in the same migration as the closely-related Finding A).
-- Additive only -- zero lines of any prior migration (<= 20260731180000)
-- touched. Every function below was read at its CURRENT live body (via
-- `pg_get_functiondef` against a fully-migrated database) before being
-- amended, exactly as 20260731180000's own header describes.
--
-- Finding B, restated (see 20260731180000's own header for the full
-- root-cause explanation): app.capture_audit_event's `p_reason` parameter
-- is a plain TEXT column, never passed through app.redact_audit_payload()
-- (which only ever redacts the jsonb before_value/after_value payloads).
-- app.query_audit_logs/app.export_audit_logs (PLT-116) are readable by ANY
-- plain tenant_admin (app.is_support_grant_authority: Supreme Admin OR
-- tenant_admin, zero domain permission required). Every function below
-- passed a caller-supplied free-text reason -- classified `pii`/confidential
-- or worse in HRS_REGISTRY (scripts/data-classification/registry.ts),
-- explicitly disclosed there as "can incidentally disclose sensitive
-- personal or medical circumstances" for the leave/attendance/schedule
-- family -- directly into that same broadly-readable audit_logs.reason
-- column. RECURRING_DEFECT_TAXONOMY.md's own note that HRT-280 "closed this
-- shape for leave" was true only for the jsonb after_value snapshot
-- (app.leave_request_audit_projection), never this separate scalar
-- `p_reason` vector -- corrected here.
--
-- Fix, uniformly: every capture_audit_event call below now passes `null`
-- for the reason argument. The same reason value is, in every case, ALSO
-- already durably written -- in the same transaction, one or two statements
-- above -- to this capability's own domain table (app.leave_requests.
-- decided_reason/cancel_reason, app.leave_balance_ledger.reason, app.
-- candidates.block_reason, app.job_applications.rejection_reason/
-- withdrawal_reason, app.candidate_assessments.notes, app.candidate_
-- duplicate_candidates.decided_reason, app.interviews.cancel_reason, app.
-- onboarding_case_events.notes, app.onboarding_case_tasks (via its own
-- audit projection), app.attendance_correction_requests.decided_reason,
-- app.schedule_assignments.cancel_reason, app.schedule_swap_requests.
-- decided_reason) -- every one of which is, per HRS_REGISTRY, already
-- column-restricted from the plain `authenticated` grant (service_role
-- only) and masked at its own owning read RPC to self-or-HRS:View-personal-
-- data. Duplicating the identical free-text value into app.audit_logs
-- (readable by any tenant_admin) served no purpose the domain table did not
-- already serve, and only widened who could read it. Mirrors this same
-- batch's own canonical C-24 shape (app.ticket_escalation_audit_projection,
-- 20260731160000, HRT-291): a sensitive free-text value lives in exactly
-- ONE properly-access-controlled place, never duplicated into a less-
-- controlled one.
--
-- A repository-wide grep of every function's CURRENT live body (via
-- pg_get_functiondef against a fully-migrated database -- the same
-- verification discipline this checkpoint's other migration used, since the
-- audit's own line-number citations against original migration text proved
-- unreliable at least once, see 20260731180000's own header on app._
-- transition_employee_leave_status) surfaced 8 further Phase 7 HR sites of
-- the identical Finding B shape, not individually named in the audit's own
-- list but squarely the same capability/same defect class: app.decide_
-- employee_position_assignment (HRT-275, 2 call sites: reject and approve
-- branches), app.cancel_employee_position_assignment (HRT-275), app.waive_
-- attendance_exception (HRT-278 -- HRS_REGISTRY already classifies this
-- exact waive_reason column identically to app.attendance_correction_
-- requests.reason, the sibling function the audit DID name), app.waive_
-- onboarding_task and app.request_onboarding_access_revocation (HRT-277,
-- siblings of app.reopen_onboarding_task/app.cancel_onboarding_case, which
-- the audit did name), app.cancel_conflicting_schedule_assignment_for_leave
-- (HRT-279/HRT-280 boundary -- delegates to app.cancel_schedule_assignment,
-- itself already fixed above, but independently ALSO logs its own second,
-- redundant audit entry with the same raw reason), and app.record_offer_
-- response/app.load_opening_leave_balance (HRT-276/HRT-280, a candidate's
-- own offer-response note and a leave-balance load's source reference,
-- both landing in the same registered/protected columns the audit's own
-- named siblings write to). Fixed here for the identical reason as every
-- other site in this file -- see this migration's own header above.

-- A second, narrower, distinct C-24 vector closed in the same pass:
-- app.record_assessment_result already correctly passed `null` for its own
-- reason argument, but its `after_value` jsonb carried a raw
-- `jsonb_build_object('score', p_score, ...)` -- the key name `score` does
-- not match app.redact_audit_payload's fixed sensitive-key-name pattern
-- (secret|password|token|key|authorization|cookie|ssn|npwp|bank|
-- account_number|salary|payroll), so a candidate's real assessment score
-- was readable by any tenant_admin via the audit log even though the same
-- HRT-276 Tier C review round (20260730870000) already correctly excluded
-- `score`/`notes` from app.candidate_assessments' own raw-table grant to
-- `authenticated` -- an audit-log-specific bypass of a fix that had
-- otherwise closed every other path. Fixed by dropping the `score` key from
-- the jsonb payload entirely (the structural `status` field alone is
-- retained, exactly mirroring app.cancel_candidate_assessment's own
-- adjacent after_value shape one function below).
--
-- Tier B taxonomy self-check for this file: C-24 (this file's entire
-- purpose, both the p_reason vector and the record_assessment_result score
-- vector); C-08 -- re-verified none of these changes narrow any legitimate
-- caller's access to the reason text itself, since every domain's own
-- properly-access-controlled table/column (self-or-HRS:View-personal-data,
-- per HRS_REGISTRY) is completely unaffected -- only the SECOND, more
-- broadly-readable audit_logs.reason copy is removed.

-- ===========================================================================
-- Leave/Permit/Business Trip (HRT-280) -- 3 sites.
-- ===========================================================================

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

comment on function app.decide_leave_request is 'HRT-280 (decision 4/9): no domain permission gate of its own for the ordinary approve/reject path -- app.decide_approval_step already gates on tenant membership + eligible-approver identity + C-18 self-approval block (mirrors app.decide_onboarding_case_finalize_approval, HRT-277). The coverage-override branch is the one place this function DOES gate directly (HRS:Override), since overriding a coverage block is a real, separate authority decision from ordinary leave approval. A rejected request returns to draft (section 22 "revision/resubmission"), letting the employee address the rejection reason and resubmit. HRT-293 Finding B fix: the audit-log reason argument is now null -- decided_reason lives only in app.leave_requests, masked to self-or-HRS:View-personal-data.';

create or replace function app.cancel_leave_request(p_request_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.leave_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request_plain app.leave_requests;
  v_request app.leave_requests;
  v_self app.employees;
  v_is_self boolean;
  v_decision app.rbac_decision;
  v_type app.leave_types;
  v_day date;
  v_session_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request_plain from app.leave_requests where id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_request_plain.tenant_id, p_actor_auth_user_id) then
    raise exception 'leave_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_request_plain.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_request_plain.employee_id;

  if not v_is_self then
    if v_request_plain.status = 'approved' then
      v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request_plain.tenant_id, 'HRS', 'Override');
    else
      v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request_plain.tenant_id, 'HRS', 'Edit');
    end if;
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks required HRS authority (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request_plain.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_request_plain.status not in ('draft', 'pending_approval', 'approved') then
    raise exception 'invalid_transition: leave request % is %, cannot be cancelled', p_request_id, v_request_plain.status using errcode = 'check_violation';
  end if;
  if v_request_plain.status = 'approved' and v_request_plain.date_to < current_date then
    raise exception 'invalid_transition: leave request % already ended on %, a completed past leave cannot be cancelled', p_request_id, v_request_plain.date_to
      using errcode = 'check_violation';
  end if;

  if v_request_plain.status = 'pending_approval' and v_request_plain.approval_request_id is not null then
    begin
      perform app.cancel_approval_request(v_request_plain.approval_request_id, p_actor_auth_user_id, p_actor_label, p_reason);
    exception
      when no_data_found or check_violation then
        null;
    end;
  end if;

  select * into v_type from app.leave_types where id = v_request_plain.leave_type_id;

  update app.leave_requests
  set status = 'cancelled', cancel_reason = p_reason, cancelled_at = now()
  where id = p_request_id and record_version = p_expected_version and status = v_request_plain.status
  returning * into v_request;
  if not found then
    raise exception 'stale_version: leave request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status = 'cancelled' and v_type.requires_balance then
    insert into app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, event_type, units, effective_date, policy_version_id, source_request_id, idempotency_key, created_by)
    select v_request.tenant_id, v_request.employee_id, v_request.leave_type_id, 'request_credit_reversal', v_request.total_units, current_date, v_request.policy_version_id, v_request.id, v_request.id::text || ':credit_reversal', p_actor_label
    where exists (select 1 from app.leave_balance_ledger where source_request_id = v_request.id and event_type = 'request_debit')
      and not exists (select 1 from app.leave_balance_ledger where source_request_id = v_request.id and event_type = 'request_credit_reversal');
  end if;

  -- Batch 278-280 Tier C fix (data-consistency-integration-boundary, HIGH):
  -- the reverse of decide_leave_request's own approve-time recalculation --
  -- a request that WAS approved (and so may have been suppressing
  -- late/early_leave/missing_clock_out exceptions for its own date range) is
  -- now cancelled, so any session in that range is recalculated and a
  -- genuine exception may legitimately reappear rather than staying
  -- silently, permanently suppressed.
  if v_request_plain.status = 'approved' then
    v_day := v_request_plain.date_from;
    while v_day <= v_request_plain.date_to loop
      select s.id into v_session_id from app.attendance_sessions s
      where s.tenant_id = v_request_plain.tenant_id and s.employee_id = v_request_plain.employee_id and s.work_date = v_day;
      if found then
        perform app._recalculate_session_exceptions(v_session_id);
      end if;
      v_day := v_day + 1;
    end loop;
  end if;

  if v_type.category = 'leave' and v_request_plain.date_from <= current_date and v_request_plain.date_to >= current_date then
    declare
      v_current_employee app.employees;
    begin
      select * into v_current_employee from app.employees where master_record_id = v_request.employee_id for update;
      if v_current_employee.lifecycle_status = 'on_leave' then
        -- Batch 278-280 Tier C fix (correctness-authority-bar-mismatch,
        -- CRITICAL, live-reproduced): calls the shared internal engine
        -- directly (app._transition_employee_leave_status), never the
        -- HRS:Edit-gated app.end_employee_leave wrapper -- an ordinary
        -- employee self-cancelling their own already-started leave holds
        -- zero HRS permission by design (decision 10) and must not be
        -- required to hold HRS:Edit merely to complete their own cancel.
        perform app._transition_employee_leave_status(v_request.employee_id, v_current_employee.record_version, 'active', null, p_actor_auth_user_id, p_actor_label);
      end if;
    end;
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see this migration's own header.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_leave_request',
    'app.leave_requests', v_request.id, 'success', null, null, app.leave_request_audit_projection(v_request)
  );

  return v_request;
end;
$$;

comment on function app.cancel_leave_request is 'HRT-280 (decision 7, mandatory reading item 4/8): genuinely cancels any in-flight PLT-123 approval request before cascading (the exact class independently found and fixed in HRT-276 AND HRT-277). Section 22''s own "future cancellation" -- an approved request whose date_from is still in the future, or already in progress today, may be self-cancelled; an already-completed past leave cannot be. HRT-293 Finding B fix: the audit-log reason argument is now null -- cancel_reason lives only in app.leave_requests, masked to self-or-HRS:View-personal-data.';

create or replace function app.adjust_leave_balance(p_tenant_id uuid, p_employee_id uuid, p_leave_type_id uuid, p_units numeric, p_effective_date date, p_reason text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.leave_balance_ledger
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.leave_balance_ledger;
  v_entry app.leave_balance_ledger;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.employees where master_record_id = p_employee_id and tenant_id = p_tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.leave_types where id = p_leave_type_id and tenant_id = p_tenant_id) then
    raise exception 'leave_type_not_found: %', p_leave_type_id using errcode = 'no_data_found';
  end if;
  if p_units = 0 then
    raise exception 'invalid_units: an adjustment must be non-zero' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required for a manual balance adjustment' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.leave_balance_ledger where tenant_id = p_tenant_id and employee_id = p_employee_id and leave_type_id = p_leave_type_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.event_type = 'adjustment' and v_existing.units = p_units and v_existing.effective_date = p_effective_date then
        return v_existing;
      else
        raise exception 'idempotency_key_conflict: key % was already used for a different adjustment', p_idempotency_key using errcode = 'unique_violation';
      end if;
    end if;
  end if;

  insert into app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, event_type, units, effective_date, reason, idempotency_key, created_by)
  values (p_tenant_id, p_employee_id, p_leave_type_id, 'adjustment', p_units, coalesce(p_effective_date, current_date), p_reason, p_idempotency_key, p_actor_label)
  returning * into v_entry;

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_reason is already durably
  -- stored above in app.leave_balance_ledger.reason (HRS_REGISTRY
  -- hrs:leave_balance_ledger.reason, column-restricted) -- never also
  -- duplicated into app.audit_logs.reason.
  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'adjust_leave_balance',
    'app.leave_balance_ledger', v_entry.id, 'success', null, null, jsonb_build_object('employee_id', p_employee_id, 'leave_type_id', p_leave_type_id, 'units', p_units)
  );

  return v_entry;
end;
$$;

-- ===========================================================================
-- Recruitment/ATS (HRT-276) -- 8 sites (7 raw-reason + record_assessment_
-- result's own separate score vector).
-- ===========================================================================

create or replace function app.set_candidate_status(p_id uuid, p_expected_version integer, p_new_status text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_candidate app.candidates;
begin
  select * into v_candidate from app.candidates where id = p_id;
  if not found or not app.has_active_tenant_membership(v_candidate.tenant_id, p_actor_auth_user_id) then
    raise exception 'candidate_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_candidate.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_candidate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_candidate.record_version <> p_expected_version then
    raise exception 'stale_version: candidate % expected version % but found %', p_id, p_expected_version, v_candidate.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_new_status not in ('active', 'blocked', 'archived') then
    raise exception 'invalid_status: % is not a valid candidate status', p_new_status using errcode = 'check_violation';
  end if;
  if p_new_status in ('blocked', 'archived') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to % a candidate', p_new_status using errcode = 'check_violation';
  end if;
  if v_candidate.status = p_new_status then
    raise exception 'invalid_transition: candidate % is already %', p_id, p_new_status using errcode = 'check_violation';
  end if;

  update app.candidates
  set status = p_new_status, block_reason = case when p_new_status = 'blocked' then p_reason else null end
  where id = p_id and record_version = p_expected_version
  returning * into v_candidate;
  if not found then
    raise exception 'stale_version: candidate % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_reason is already durably
  -- stored above (block_reason) on app.candidates when relevant -- never
  -- also duplicated into app.audit_logs.reason. app.candidate_audit_
  -- projection's own jsonb after_value snapshot was already correctly
  -- non-pii (HRT-276).
  perform app.capture_audit_event(
    v_candidate.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_candidate_status',
    'app.candidates', v_candidate.id, 'success', null, null, app.candidate_audit_projection(v_candidate)
  );

  return v_candidate;
end;
$$;

create or replace function app.reject_application(p_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_applications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
  v_from_stage text;
  v_offer app.job_offers;
begin
  select * into v_application from app.job_applications where id = p_id;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'Reject');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Reject (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_application.record_version <> p_expected_version then
    raise exception 'stale_version: application % expected version % but found %', p_id, p_expected_version, v_application.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reject an application' using errcode = 'check_violation';
  end if;
  if v_application.stage in ('rejected', 'withdrawn', 'offer_accepted') then
    raise exception 'invalid_transition: application % is % and cannot be rejected', p_id, v_application.stage using errcode = 'check_violation';
  end if;
  v_from_stage := v_application.stage;

  update app.job_applications set stage = 'rejected', stage_since = now(), rejection_reason = p_reason
  where id = p_id and record_version = p_expected_version
  returning * into v_application;
  if not found then
    raise exception 'stale_version: application % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Review-round fix (CRITICAL, live-reproduced two-process race -- 20260730870000):
  -- cancel any still-pending PLT-123 approval request BEFORE flipping the offer to
  -- withdrawn -- mirrors the already-established app.cancel_purchase_order/app.
  -- cancel_vendor_contract precedent for "cancel a pending approval when its subject
  -- is terminated". Deliberately a PLAIN (non-locking) read of v_offer here, not
  -- `for update`: app.decide_job_offer_approval's own call path locks app.
  -- approval_request_steps/app.approval_requests (inside app.decide_approval_step)
  -- BEFORE it ever touches app.job_offers (its own terminal update runs after).
  -- Taking a `for update` lock on app.job_offers here, before calling app.
  -- cancel_approval_request (which locks the SAME approval-engine tables), would
  -- lock job_offers-then-approval_request_steps -- the exact REVERSE order of that
  -- call path, a real lock-order cycle -- live-reproduced as `deadlock detected`
  -- (SQLSTATE 40P01) during this fix's own regression testing. Locking nothing here
  -- and letting app.cancel_approval_request take its own locks (steps, then
  -- request) first, with app.job_offers only ever locked by the ordinary UPDATE
  -- below (last, exactly matching app.decide_job_offer_approval's own order), closes
  -- the deadlock while keeping the race-safety guarantee: a concurrent decide that
  -- has already resolved the request (or a concurrent caller that already cancelled
  -- it) between this read and the cancel call is tolerated -- the guarded update in
  -- app.decide_job_offer_approval is what actually determines the final state.
  select * into v_offer from app.job_offers where application_id = p_id;
  if found and v_offer.status = 'pending_approval' and v_offer.approval_request_id is not null then
    begin
      perform app.cancel_approval_request(v_offer.approval_request_id, p_actor_auth_user_id, p_actor_label, p_reason);
    exception
      when no_data_found or check_violation then
        null;
    end;
  end if;

  update app.job_offers set status = 'withdrawn' where application_id = p_id and status not in ('withdrawn', 'accepted', 'declined');

  insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, reason, actor_auth_user_id, actor_label)
  values (v_application.tenant_id, p_id, v_from_stage, 'rejected', p_reason, p_actor_auth_user_id, p_actor_label);

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_reason is already durably
  -- stored above (rejection_reason on app.job_applications,
  -- app.application_stage_history.reason) -- never also duplicated into
  -- app.audit_logs.reason.
  perform app.capture_audit_event(
    v_application.tenant_id, p_actor_auth_user_id, p_actor_label, 'reject_application',
    'app.job_applications', v_application.id, 'success', null, null, app.job_application_audit_projection(v_application)
  );

  return v_application;
end;
$$;

create or replace function app.withdraw_application(p_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_applications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
  v_from_stage text;
  v_offer app.job_offers;
begin
  select * into v_application from app.job_applications where id = p_id;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_application.record_version <> p_expected_version then
    raise exception 'stale_version: application % expected version % but found %', p_id, p_expected_version, v_application.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to withdraw an application' using errcode = 'check_violation';
  end if;
  if v_application.stage in ('rejected', 'withdrawn', 'offer_accepted') then
    raise exception 'invalid_transition: application % is % and cannot be withdrawn', p_id, v_application.stage using errcode = 'check_violation';
  end if;
  v_from_stage := v_application.stage;

  update app.job_applications set stage = 'withdrawn', stage_since = now(), withdrawal_reason = p_reason
  where id = p_id and record_version = p_expected_version
  returning * into v_application;
  if not found then
    raise exception 'stale_version: application % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Review-round fix (CRITICAL, same root cause AND same live-reproduced deadlock
  -- lock-order fix as app.reject_application above -- 20260730870000): cancel a
  -- still-pending PLT-123 approval request before cascading the offer to withdrawn,
  -- via a deliberately PLAIN (non-locking) read -- see app.reject_application's own
  -- inline comment for the full lock-order rationale.
  select * into v_offer from app.job_offers where application_id = p_id;
  if found and v_offer.status = 'pending_approval' and v_offer.approval_request_id is not null then
    begin
      perform app.cancel_approval_request(v_offer.approval_request_id, p_actor_auth_user_id, p_actor_label, p_reason);
    exception
      when no_data_found or check_violation then
        null;
    end;
  end if;

  update app.job_offers set status = 'withdrawn' where application_id = p_id and status not in ('withdrawn', 'accepted', 'declined');

  insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, reason, actor_auth_user_id, actor_label)
  values (v_application.tenant_id, p_id, v_from_stage, 'withdrawn', p_reason, p_actor_auth_user_id, p_actor_label);

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see app.reject_application above.
  perform app.capture_audit_event(
    v_application.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_application',
    'app.job_applications', v_application.id, 'success', null, null, app.job_application_audit_projection(v_application)
  );

  return v_application;
end;
$$;

create or replace function app.cancel_candidate_assessment(p_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.candidate_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.candidate_assessments;
begin
  select * into v_row from app.candidate_assessments where id = p_id;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'assessment_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: assessment % expected version % but found %', p_id, p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel an assessment' using errcode = 'check_violation';
  end if;
  if v_row.status not in ('pending', 'in_progress') then
    raise exception 'invalid_transition: assessment % is % and cannot be cancelled', p_id, v_row.status using errcode = 'check_violation';
  end if;

  update app.candidate_assessments set status = 'cancelled', notes = p_reason
  where id = p_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: assessment % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_reason is already durably
  -- stored above (app.candidate_assessments.notes, column-restricted since
  -- HRT-276's own Tier C review, 20260730870000) -- never also duplicated
  -- into app.audit_logs.reason.
  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_candidate_assessment',
    'app.candidate_assessments', v_row.id, 'success', null, null, jsonb_build_object('status', v_row.status)
  );

  return v_row;
end;
$$;

create or replace function app.decide_candidate_duplicate(p_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.candidate_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rbac app.rbac_decision;
  v_row app.candidate_duplicate_candidates;
begin
  select * into v_row from app.candidate_duplicate_candidates where id = p_id;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'duplicate_candidate_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_rbac := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'HRS', 'Edit');
  if not v_rbac.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_rbac.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: duplicate candidate row % expected version % but found %', p_id, p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_decision not in ('linked', 'dismissed') then
    raise exception 'invalid_decision: % is not linked or dismissed', p_decision using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a duplicate candidate pairing' using errcode = 'check_violation';
  end if;
  if v_row.decision <> 'pending' then
    raise exception 'invalid_transition: duplicate candidate row % is already %', p_id, v_row.decision using errcode = 'check_violation';
  end if;

  update app.candidate_duplicate_candidates
  set decision = p_decision, decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason, record_version = record_version + 1
  where id = p_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: duplicate candidate row % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see this migration's own header.
  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_candidate_duplicate',
    'app.candidate_duplicate_candidates', v_row.id, 'success', null, null, jsonb_build_object('decision', p_decision)
  );

  return v_row;
end;
$$;

create or replace function app.cancel_interview(p_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.interviews
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_interview app.interviews;
begin
  select * into v_interview from app.interviews where id = p_id;
  if not found or not app.has_active_tenant_membership(v_interview.tenant_id, p_actor_auth_user_id) then
    raise exception 'interview_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_interview.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_interview.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_interview.record_version <> p_expected_version then
    raise exception 'stale_version: interview % expected version % but found %', p_id, p_expected_version, v_interview.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel an interview' using errcode = 'check_violation';
  end if;
  if v_interview.status <> 'scheduled' then
    raise exception 'invalid_transition: interview % is % and cannot be cancelled', p_id, v_interview.status using errcode = 'check_violation';
  end if;

  update app.interviews set status = 'cancelled', cancel_reason = p_reason
  where id = p_id and record_version = p_expected_version
  returning * into v_interview;
  if not found then
    raise exception 'stale_version: interview % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see this migration's own header.
  perform app.capture_audit_event(
    v_interview.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_interview',
    'app.interviews', v_interview.id, 'success', null, null, jsonb_build_object('status', v_interview.status)
  );

  return v_interview;
end;
$$;

create or replace function app.record_assessment_result(p_id uuid, p_expected_version integer, p_score numeric, p_notes text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.candidate_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.candidate_assessments;
begin
  select * into v_row from app.candidate_assessments where id = p_id;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'assessment_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: assessment % expected version % but found %', p_id, p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status not in ('pending', 'in_progress') then
    raise exception 'invalid_transition: assessment % is % and cannot record a result', p_id, v_row.status using errcode = 'check_violation';
  end if;
  if p_score is null or p_score < 0 or p_score > v_row.max_score then
    raise exception 'invalid_score: score must be between 0 and % (max_score)', v_row.max_score using errcode = 'check_violation';
  end if;

  update app.candidate_assessments
  set score = p_score, notes = p_notes, status = 'completed', completed_at = now()
  where id = p_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: assessment % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24): the raw candidate score is a
  -- classified pii value (per this checkpoint's own registry addition,
  -- hrs:candidate_assessments.score_notes) already correctly withheld from
  -- app.candidate_assessments' own raw-table grant to authenticated
  -- (HRT-276 Tier C review, 20260730870000) -- but app.redact_audit_
  -- payload's fixed key-name pattern does not match the key name `score`,
  -- so the prior jsonb_build_object('score', p_score, ...) leaked it
  -- through the audit-log path alone. Dropped entirely; only the
  -- structural `status` field (already visible to any HRS:Edit holder
  -- through the ordinary read path) is retained, mirroring app.cancel_
  -- candidate_assessment's own adjacent after_value shape.
  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_assessment_result',
    'app.candidate_assessments', v_row.id, 'success', null, null, jsonb_build_object('status', v_row.status)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- Onboarding/Offboarding (HRT-277) -- 4 sites.
-- ===========================================================================

create or replace function app.cancel_onboarding_case(p_case_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.onboarding_offboarding_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_case app.onboarding_offboarding_cases;
  v_case_plain app.onboarding_offboarding_cases;
  v_provisioning_request app.onboarding_task_provisioning_requests;
  v_revoke_role_version_id uuid;
  v_role_assignment app.role_assignments;
  v_revoked_count integer := 0;
begin
  -- Deliberately PLAIN (non-locking) read first, mirroring app.reject_
  -- application's own documented lock-order rationale exactly: app.decide_
  -- onboarding_case_finalize_approval's own call path locks app.approval_
  -- request_steps/app.approval_requests (inside app.decide_approval_step)
  -- BEFORE it ever touches app.onboarding_offboarding_cases (its own terminal
  -- update runs last). Taking a `for update` lock on the case here FIRST,
  -- before calling app.cancel_approval_request (which locks the SAME
  -- approval-engine tables), would lock case-then-approval_request_steps --
  -- the exact REVERSE order of that call path, a real lock-order cycle.
  select * into v_case_plain from app.onboarding_offboarding_cases where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case_plain.tenant_id, p_actor_auth_user_id) then
    raise exception 'case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case_plain.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case_plain.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_case_plain.status not in ('draft', 'active', 'pending_finalize_approval') then
    raise exception 'invalid_transition: case % is %, cannot be cancelled', p_case_id, v_case_plain.status using errcode = 'check_violation';
  end if;

  if v_case_plain.status = 'pending_finalize_approval' and v_case_plain.finalize_approval_request_id is not null then
    begin
      perform app.cancel_approval_request(v_case_plain.finalize_approval_request_id, p_actor_auth_user_id, p_actor_label, p_reason);
    exception
      when no_data_found or check_violation then
        null;
    end;
  end if;

  update app.onboarding_offboarding_cases
  set status = 'cancelled', cancel_reason = p_reason, cancelled_at = now()
  where id = p_case_id and record_version = p_expected_version
  returning * into v_case;
  if not found then
    raise exception 'stale_version: case % target row was concurrently modified (expected version %)', p_case_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Review-round fix (CRITICAL, C-04 / dependent-in-flight-process-not-
  -- cancelled): revoke exactly the role grants THIS case's own completed
  -- access-provisioning requests produced -- see the migration header comment
  -- above for the full race-safety argument.
  for v_provisioning_request in
    select r.* from app.onboarding_task_provisioning_requests r
    where r.case_id = p_case_id and r.request_type = 'grant_access' and r.status = 'completed'
      and r.result_user_id is not null and coalesce(array_length(r.requested_role_version_ids, 1), 0) > 0
  loop
    foreach v_revoke_role_version_id in array v_provisioning_request.requested_role_version_ids loop
      for v_role_assignment in
        select * from app.role_assignments
        where tenant_id = v_case.tenant_id and role_version_id = v_revoke_role_version_id
          and auth_user_id = (select auth_user_id from app.users where id = v_provisioning_request.result_user_id)
          and status = 'active'
      loop
        perform app.revoke_role_assignment(v_role_assignment.id, 'onboarding/offboarding case ' || p_case_id::text || ' cancelled: ' || coalesce(p_reason, 'no reason supplied'), p_actor_label);
        v_revoked_count := v_revoked_count + 1;
      end loop;
    end loop;
  end loop;

  insert into app.onboarding_case_events (case_id, tenant_id, event_type, to_status, notes, actor_auth_user_id, actor_label)
  values (p_case_id, v_case.tenant_id, 'cancel', 'cancelled', p_reason, p_actor_auth_user_id, p_actor_label);

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_reason is already durably
  -- stored above (cancel_reason on app.onboarding_offboarding_cases,
  -- app.onboarding_case_events.notes) -- never also duplicated into
  -- app.audit_logs.reason.
  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_onboarding_case',
    'app.onboarding_offboarding_cases', v_case.id, 'success', null,
    null, app.onboarding_case_audit_projection(v_case) || jsonb_build_object('access_grants_revoked', v_revoked_count)
  );

  return v_case;
end;
$$;

comment on function app.cancel_onboarding_case is 'HRT-277 section 23, hardened by the Tier C review-round fix pass (20260730890000): cancelling never deletes the employee row it may have created/linked (section 24 "never loses required business history") -- a cancelled onboarding leaves the employee at whatever lifecycle_status it already reached; HR separately archives it via app.archive_employee_profile (HRT-274) if desired. Cancelling NOW also revokes any Platform role_assignments this case''s own completed access-provisioning requests already granted (never the underlying identity link itself) -- closes a live-reproduced gap where a cancelled case left a real, live Platform access grant behind. HRT-293 Finding B fix: the audit-log reason argument is now null.';

create or replace function app.reopen_onboarding_task(p_case_id uuid, p_task_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Edit');

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_task.status not in ('completed', 'waived') then
    raise exception 'invalid_transition: task % is %, only a completed or waived task can be reopened', p_task_id, v_task.status using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reopen a task' using errcode = 'check_violation';
  end if;

  update app.onboarding_case_tasks
  set status = 'reopened', completed_at = null, completed_by = null, waived_at = null, waived_by = null, waive_reason = null
  where id = p_task_id and record_version = p_expected_version
  returning * into v_task;
  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.onboarding_case_events (case_id, tenant_id, event_type, notes, actor_auth_user_id, actor_label)
  values (p_case_id, v_task.tenant_id, 'task_reopened', p_reason, p_actor_auth_user_id, p_actor_label);

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see this migration's own header.
  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_onboarding_task',
    'app.onboarding_case_tasks', v_task.id, 'success', null, null, app.onboarding_case_task_audit_projection(v_task)
  );

  return v_task;
end;
$$;

create or replace function app.decide_onboarding_case_finalize_approval(p_request_step_id uuid, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.onboarding_offboarding_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_case app.onboarding_offboarding_cases;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id using errcode = 'no_data_found';
  end if;

  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'onboarding_offboarding_case' or v_request.entity_id is null then
    raise exception 'not_an_onboarding_case_approval: approval request % is not an onboarding/offboarding case approval', v_request.id using errcode = 'check_violation';
  end if;

  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  -- Hardened terminal-UPDATE guard from the FIRST migration (mandatory reading
  -- item 5, closing HRT-276's own Tier C finding 7/8 class before it recurs):
  -- guarded on (finalize_approval_request_id = v_request.id AND status =
  -- 'pending_finalize_approval') -- if the case is no longer awaiting THIS
  -- specific decision (concurrently cancelled), the whole function raises and
  -- rolls back atomically, including the app.decide_approval_step mutation
  -- just above, rather than silently resurrecting a cancelled case.
  if v_updated_request.status = 'approved' then
    update app.onboarding_offboarding_cases
    set status = 'finalized', finalized_at = now(), finalized_by = p_actor_label
    where id = v_request.entity_id and finalize_approval_request_id = v_request.id and status = 'pending_finalize_approval'
    returning * into v_case;
    if not found then
      raise exception 'case_finalize_no_longer_applicable: case % is no longer awaiting decision on approval request % (concurrently cancelled)', v_request.entity_id, v_request.id
        using errcode = 'serialization_failure';
    end if;
    insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, actor_auth_user_id, actor_label)
    values (v_case.id, v_case.tenant_id, 'finalize', 'pending_finalize_approval', 'finalized', p_actor_auth_user_id, p_actor_label);
  elsif v_updated_request.status = 'rejected' then
    update app.onboarding_offboarding_cases
    set status = 'active', finalize_approval_request_id = null
    where id = v_request.entity_id and finalize_approval_request_id = v_request.id and status = 'pending_finalize_approval'
    returning * into v_case;
    if not found then
      raise exception 'case_finalize_no_longer_applicable: case % is no longer awaiting decision on approval request % (concurrently cancelled)', v_request.entity_id, v_request.id
        using errcode = 'serialization_failure';
    end if;
    insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, notes, actor_auth_user_id, actor_label)
    values (v_case.id, v_case.tenant_id, 'finalize_rejected', 'pending_finalize_approval', 'active', p_reason, p_actor_auth_user_id, p_actor_label);
  else
    select * into v_case from app.onboarding_offboarding_cases where id = v_request.entity_id;
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see this migration's own header.
  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_onboarding_case_finalize_approval',
    'app.onboarding_offboarding_cases', v_case.id, 'success', null, null, app.onboarding_case_audit_projection(v_case)
  );

  return v_case;
end;
$$;

create or replace function app.rehire_employee(p_master_record_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to rehire an employee' using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status <> 'terminated' then
    raise exception 'invalid_transition: employee % is %, only a terminated employee can be rehired (archived is a genuinely terminal administrative closure)', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.employees
  set lifecycle_status = 'active', terminate_reason = null, employment_end_date = null
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, 'terminated', 'active', p_reason, p_actor_auth_user_id, p_actor_label);

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_reason is already durably
  -- stored above in app.employee_lifecycle_events.reason (column-restricted
  -- by 20260731180000) -- never also duplicated into app.audit_logs.reason.
  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'rehire_employee',
    'app.employees', p_master_record_id, 'success', null, null, jsonb_build_object('rehired', true)
  );

  return v_employee;
end;
$$;

-- ===========================================================================
-- Attendance (HRT-278) -- 2 sites.
-- ===========================================================================

create or replace function app.decide_attendance_correction(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.attendance_correction_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.attendance_correction_requests;
  v_session app.attendance_sessions;
  v_self app.employees;
  v_new_status text;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decided_reason is null or length(trim(p_decided_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a correction request' using errcode = 'check_violation';
  end if;

  select cr.* into v_request from app.attendance_correction_requests cr where cr.id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'correction_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Self-approval is never permitted, even for an actor who happens to hold
  -- HRS:Approve (taxonomy C-18's "self-approval blocked on all transitions").
  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_request.employee_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own attendance correction request' using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: correction request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending_approval' then
    raise exception 'invalid_transition: correction request % is %, cannot be decided', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  select * into v_session from app.attendance_sessions where id = v_request.session_id for update;

  v_new_status := case p_decision when 'approve' then 'approved' else 'rejected' end;

  update app.attendance_correction_requests
  set status = v_new_status, decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: correction request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  if p_decision = 'approve' then
    if v_request.request_type in ('add_missing_clock_in', 'adjust_clock_in') then
      update app.attendance_sessions
      set corrected_clock_in_at = v_request.proposed_clock_in_at,
          raw_clock_in_at = coalesce(raw_clock_in_at, v_request.proposed_clock_in_at),
          status = case when status = 'open' or clock_out_event_id is not null then status else status end,
          payroll_input_status = 'pending', payroll_approved_by = null, payroll_approved_at = null
      where id = v_session.id;
    else
      update app.attendance_sessions
      set corrected_clock_out_at = v_request.proposed_clock_out_at,
          raw_clock_out_at = coalesce(raw_clock_out_at, v_request.proposed_clock_out_at),
          status = 'closed',
          clock_out_event_id = coalesce(clock_out_event_id, clock_in_event_id),
          payroll_input_status = 'pending', payroll_approved_by = null, payroll_approved_at = null
      where id = v_session.id;
    end if;

    if v_request.linked_exception_id is not null then
      update app.attendance_exceptions
      set status = 'resolved', resolved_at = now(), resolved_by = p_actor_label, resolution_note = 'resolved by approved correction ' || p_request_id::text
      where id = v_request.linked_exception_id and status in ('open', 'acknowledged');
    end if;

    perform app._recalculate_session_exceptions(v_session.id);
  else
    -- decision 9: rejecting never leaves the linked exception silently
    -- implying resolution is in flight.
    if v_request.linked_exception_id is not null then
      update app.attendance_exceptions set status = 'open'
      where id = v_request.linked_exception_id and status = 'open';
    end if;
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_decided_reason is already
  -- durably stored above in app.attendance_correction_requests.
  -- decided_reason (HRS_REGISTRY hrs:attendance_correction_requests.reason,
  -- column-restricted) -- never also duplicated into app.audit_logs.reason.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_attendance_correction',
    'app.attendance_correction_requests', p_request_id, 'success', null, null, jsonb_build_object('decision', p_decision)
  );

  return v_request;
end;
$$;

create or replace function app.cancel_attendance_correction(p_request_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.attendance_correction_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.attendance_correction_requests;
  v_self app.employees;
  v_is_self boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.attendance_correction_requests where id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'correction_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_request.employee_id and v_request.requested_by_auth_user_id = p_actor_auth_user_id;

  if not v_is_self then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a correction request' using errcode = 'check_violation';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: correction request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending_approval' then
    raise exception 'invalid_transition: correction request % is %, only a pending request may be cancelled', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  update app.attendance_correction_requests
  set status = 'cancelled'
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: correction request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.linked_exception_id is not null then
    update app.attendance_exceptions set status = 'open'
    where id = v_request.linked_exception_id and status = 'open';
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see app.decide_attendance_
  -- correction above.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_attendance_correction',
    'app.attendance_correction_requests', p_request_id, 'success', null, null, '{}'::jsonb
  );

  return v_request;
end;
$$;

-- ===========================================================================
-- Shift/Roster (HRT-279) -- 3 sites.
-- ===========================================================================

create or replace function app.cancel_schedule_assignment(p_assignment_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.schedule_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assignment app.schedule_assignments;
  v_has_edit boolean;
  v_has_override boolean;
begin
  -- decision 7: this function's own primary target lock order is
  -- assignment-first -- the ONLY row it locks via SELECT ... FOR UPDATE. Any
  -- dependent swap-request cancellation below is a single conditional UPDATE,
  -- never a separate pre-lock, so this function never holds a swap-request
  -- lock before its own assignment lock (matches app.decide_schedule_swap_
  -- request's own identical assignment-before-swap-request order).
  select * into v_assignment from app.schedule_assignments where id = p_assignment_id for update;
  if not found or not app.has_active_tenant_membership(v_assignment.tenant_id, p_actor_auth_user_id) then
    raise exception 'schedule_assignment_not_found: %', p_assignment_id using errcode = 'no_data_found';
  end if;

  -- C-05: HRS:Edit and HRS:Override are a genuinely disjoint EITHER/OR pair
  -- here (Edit suffices for a still-draft row, Override is required -- and
  -- sufficient on its own -- for an already-published one; an Override
  -- holder is NOT required to also hold Edit). A coarse "holds at least one
  -- of the two" floor runs FIRST and unconditionally, so a caller with
  -- NEITHER permission -- the real, meaningful zero-authority threat this
  -- class targets -- gets one generic rejection that discloses nothing about
  -- v_assignment.status. Only a caller who clears that floor (a genuine,
  -- already-privileged HRS actor) reaches the specific check for whichever
  -- one this row's own status actually requires.
  v_has_edit := (app.evaluate_permission(p_actor_auth_user_id, v_assignment.tenant_id, 'HRS', 'Edit')).allowed;
  v_has_override := (app.evaluate_permission(p_actor_auth_user_id, v_assignment.tenant_id, 'HRS', 'Override')).allowed;
  if not v_has_edit and not v_has_override then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit/HRS:Override for tenant %', p_actor_auth_user_id, v_assignment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assignment.status = 'published' then
    if not v_has_override then
      raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant % (cancelling a published assignment)', p_actor_auth_user_id, v_assignment.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  else
    if not v_has_edit then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_assignment.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a schedule assignment' using errcode = 'check_violation';
  end if;

  if v_assignment.record_version <> p_expected_version then
    raise exception 'stale_version: schedule assignment % expected version % but found %', p_assignment_id, p_expected_version, v_assignment.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_assignment.status not in ('scheduled', 'published') then
    raise exception 'invalid_transition: schedule assignment % is %, cannot be cancelled', p_assignment_id, v_assignment.status
      using errcode = 'check_violation';
  end if;

  update app.schedule_assignments
  set status = 'cancelled', cancel_reason = p_reason
  where id = p_assignment_id and record_version = p_expected_version
  returning * into v_assignment;
  if not found then
    raise exception 'stale_version: schedule assignment % target row was concurrently modified (expected version %)', p_assignment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- decision 6: never leave a dependent in-flight process live.
  update app.schedule_swap_requests
  set status = 'cancelled'
  where (assignment_id = p_assignment_id or target_assignment_id = p_assignment_id) and status = 'pending_approval';

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_reason is already durably
  -- stored above in app.schedule_assignments.cancel_reason (HRS_REGISTRY
  -- hrs:schedule_assignments.cancel_reason, column-restricted, never
  -- projected by any read RPC) -- never also duplicated into
  -- app.audit_logs.reason.
  perform app.capture_audit_event(
    v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_schedule_assignment',
    'app.schedule_assignments', p_assignment_id, 'success', null, null, '{}'::jsonb
  );

  return v_assignment;
end;
$$;

create or replace function app.decide_schedule_swap_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.schedule_swap_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_peek app.schedule_swap_requests;
  v_request app.schedule_swap_requests;
  v_self app.employees;
  v_lo uuid;
  v_hi uuid;
  v_lock_lo app.schedule_assignments;
  v_lock_hi app.schedule_assignments;
  v_assignment app.schedule_assignments;
  v_target_assignment app.schedule_assignments;
  v_new_status text;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decided_reason is null or length(trim(p_decided_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a swap request' using errcode = 'check_violation';
  end if;

  -- decision 7: PLAIN unlocked read first, only to discover which two
  -- assignment ids to lock (mirrors HRT-276 section 12.4's own
  -- "plain-read-before-lock" precedent) -- never a lock taken on the swap
  -- request row before the assignment rows, matching app.cancel_schedule_
  -- assignment's own assignment-before-swap-request order exactly.
  select * into v_peek from app.schedule_swap_requests where id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_peek.tenant_id, p_actor_auth_user_id) then
    raise exception 'schedule_swap_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_peek.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_peek.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Self-approval is never permitted for EITHER participant (C-18), even for
  -- an actor who happens to also hold HRS:Approve.
  v_self := app.get_self_employee(v_peek.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id in (v_peek.requesting_employee_id, v_peek.target_employee_id) then
    raise exception 'self_approval_not_permitted: an actor may not decide a swap request they are a party to' using errcode = 'insufficient_privilege';
  end if;

  -- Global ascending-uuid lock order on the two assignment rows -- deadlock-
  -- safe against another concurrent decide call on an overlapping pair.
  v_lo := least(v_peek.assignment_id, v_peek.target_assignment_id);
  v_hi := greatest(v_peek.assignment_id, v_peek.target_assignment_id);
  select * into v_lock_lo from app.schedule_assignments where id = v_lo for update;
  select * into v_lock_hi from app.schedule_assignments where id = v_hi for update;

  if v_lock_lo.id = v_peek.assignment_id then
    v_assignment := v_lock_lo; v_target_assignment := v_lock_hi;
  else
    v_assignment := v_lock_hi; v_target_assignment := v_lock_lo;
  end if;

  -- NOW lock and re-validate the swap request row itself, under the SAME
  -- (assignment-then-swap-request) global order every other function in this
  -- migration uses.
  select * into v_request from app.schedule_swap_requests where id = p_request_id for update;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: swap request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending_approval' then
    raise exception 'invalid_transition: swap request % is %, cannot be decided', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_new_status := case p_decision when 'approve' then 'approved' else 'rejected' end;

  update app.schedule_swap_requests
  set status = v_new_status, decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: swap request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  if p_decision = 'approve' then
    if v_assignment.status <> 'published' or v_target_assignment.status <> 'published' then
      raise exception 'invalid_transition: both assignments must still be published to complete a swap (revalidated at decision time)' using errcode = 'check_violation';
    end if;
    if not exists (select 1 from app.employees where master_record_id = v_request.requesting_employee_id and lifecycle_status = 'active')
       or not exists (select 1 from app.employees where master_record_id = v_request.target_employee_id and lifecycle_status = 'active') then
      raise exception 'employee_not_active: both employees must be active to complete a swap' using errcode = 'check_violation';
    end if;

    -- Two sequential UPDATEs are safe here: the partial unique index
    -- guarantees at most one active/published row per (employee, work_date),
    -- so each target tuple below is provably free the instant the OTHER
    -- row's own tuple has moved off it (or was never colliding).
    update app.schedule_assignments set employee_id = v_target_assignment.employee_id where id = v_assignment.id;
    update app.schedule_assignments set employee_id = v_assignment.employee_id where id = v_target_assignment.id;
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24): p_decided_reason is already
  -- durably stored above in app.schedule_swap_requests.decided_reason
  -- (HRS_REGISTRY hrs:schedule_swap_requests.reason, column-restricted) --
  -- never also duplicated into app.audit_logs.reason.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_schedule_swap_request',
    'app.schedule_swap_requests', p_request_id, 'success', null, null, jsonb_build_object('decision', p_decision)
  );

  return v_request;
end;
$$;

create or replace function app.cancel_schedule_swap_request(p_request_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.schedule_swap_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.schedule_swap_requests;
  v_self app.employees;
  v_is_self boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.schedule_swap_requests where id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'schedule_swap_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_request.requesting_employee_id and v_request.requested_by_auth_user_id = p_actor_auth_user_id;

  if not v_is_self then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a swap request' using errcode = 'check_violation';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: swap request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status <> 'pending_approval' then
    raise exception 'invalid_transition: swap request % is %, only a pending request may be cancelled', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  update app.schedule_swap_requests
  set status = 'cancelled'
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: swap request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- HRT-293 Finding B fix (CRITICAL, C-24) -- see app.decide_schedule_swap_
  -- request above.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_schedule_swap_request',
    'app.schedule_swap_requests', p_request_id, 'success', null, null, '{}'::jsonb
  );

  return v_request;
end;
$$;

-- ===========================================================================
-- Self-found sites (this migration's own header, above): 8 further
-- functions across HRT-275 (Organization/Position Linkage), HRT-276
-- (Recruitment/ATS), HRT-277 (Onboarding/Offboarding), HRT-278 (Attendance),
-- and the HRT-279/HRT-280 boundary -- same Finding B defect class, not
-- individually named by the audit's own list.
-- ===========================================================================

create or replace function app.decide_employee_position_assignment(p_assignment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.employee_position_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assignment app.employee_position_assignments;
  v_employee app.employees;
  v_position app.positions;
  v_predecessor app.employee_position_assignments;
  v_predecessor_found boolean;
  v_headcount integer;
  v_lock_key bigint;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide an assignment proposal' using errcode = 'check_violation';
  end if;

  select * into v_assignment from app.employee_position_assignments where id = p_assignment_id for update;
  if not found or not app.has_active_tenant_membership(v_assignment.tenant_id, p_actor_auth_user_id) then
    raise exception 'assignment_not_found: %', p_assignment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assignment.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assignment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assignment.record_version <> p_expected_version then
    raise exception 'stale_version: assignment % expected version % but found %', p_assignment_id, p_expected_version, v_assignment.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_assignment.status <> 'pending_approval' then
    raise exception 'assignment_not_pending: assignment % is % and cannot be decided', p_assignment_id, v_assignment.status
      using errcode = 'check_violation';
  end if;

  if p_decision = 'reject' then
    update app.employee_position_assignments
    set status = 'rejected', decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason
    where id = p_assignment_id and record_version = p_expected_version
    returning * into v_assignment;
    if not found then
      raise exception 'stale_version: assignment % target row was concurrently modified (expected version %)', p_assignment_id, p_expected_version
        using errcode = 'serialization_failure';
    end if;

    -- HRT-293 Finding B fix (self-found, CRITICAL, C-24): p_reason is
    -- already durably stored above in app.employee_position_assignments.
    -- decided_reason -- never also duplicated into app.audit_logs.reason.
    perform app.capture_audit_event(
      v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_employee_position_assignment',
      'app.employee_position_assignments', v_assignment.id, 'success', null, null, app.employee_position_assignment_audit_projection(v_assignment)
    );
    return v_assignment;
  end if;

  -- Approve path (decisions 7, 8: capacity + cycle re-checked authoritatively here).
  select * into v_employee from app.employees where master_record_id = v_assignment.master_record_id for update;
  select * into v_position from app.positions where id = v_assignment.position_id;

  if v_position.status <> 'active' then
    raise exception 'position_inactive: position % is inactive and cannot be activated', v_assignment.position_id using errcode = 'check_violation';
  end if;

  if v_assignment.manager_employee_id is not null and app.would_create_employee_manager_cycle(v_assignment.master_record_id, v_assignment.manager_employee_id) then
    raise exception 'cyclic_reporting_line: approving assignment % would create a cyclic reporting line', p_assignment_id
      using errcode = 'check_violation';
  end if;

  if v_assignment.assignment_type = 'primary' then
    -- Position-scoped advisory lock (mirrors app.commit_vendor_rate_import_job's own
    -- job-scoped-advisory-lock precedent) -- serializes concurrent approvals against
    -- the SAME position's capacity so two racing approvals cannot both pass the
    -- count check before either commits.
    v_lock_key := hashtextextended('employee_position_assignments:position:' || v_assignment.position_id::text, 0);
    perform pg_advisory_xact_lock(v_lock_key);

    -- Predecessor lookup happens BEFORE the capacity check (not after, as a naive
    -- reading of "close predecessor, then check capacity" would do) so that a
    -- same-position correction/promotion -- which closes the employee's own existing
    -- occupancy of THIS SAME position and immediately replaces it -- does not
    -- double-count that soon-to-be-closed predecessor against the position's own
    -- capacity. A predecessor at a DIFFERENT position is never excluded (a genuine
    -- transfer away from one position and into another must be capacity-checked at
    -- the destination without any special-casing).
    select * into v_predecessor
    from app.employee_position_assignments
    where master_record_id = v_assignment.master_record_id and assignment_type = 'primary' and status = 'active' and effective_end_date is null
    for update;
    v_predecessor_found := found;

    v_headcount := app.count_position_active_primary_headcount(
      v_assignment.position_id, v_assignment.validity_range,
      case when v_predecessor_found and v_predecessor.position_id = v_assignment.position_id then v_predecessor.id else null end
    );
    if v_headcount >= v_position.capacity then
      raise exception 'position_over_capacity: position % has % of % capacity slot(s) already committed for this date range', v_assignment.position_id, v_headcount, v_position.capacity
        using errcode = 'check_violation';
    end if;

    -- Close the currently open-ended primary predecessor (if any) BEFORE flipping
    -- this row to active, so the EXCLUDE constraint below sees a non-overlapping
    -- state -- exactly PRC-255's own established ordering.
    if v_predecessor_found then
      if v_assignment.effective_start_date <= v_predecessor.effective_start_date then
        raise exception 'invalid_effective_range: new assignment must start after the current assignment''s own start date (%)', v_predecessor.effective_start_date
          using errcode = 'check_violation';
      end if;
      update app.employee_position_assignments
      set effective_end_date = v_assignment.effective_start_date - 1
      where id = v_predecessor.id;
    end if;
  end if;

  begin
    update app.employee_position_assignments
    set status = 'active', decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason,
        previous_assignment_id = coalesce(previous_assignment_id, v_predecessor.id)
    where id = p_assignment_id and record_version = p_expected_version
    returning * into v_assignment;
  exception
    when exclusion_violation then
      raise exception 'assignment_overlap: an active % assignment already exists for this employee/position with an overlapping effective range', v_assignment.assignment_type
        using errcode = 'check_violation';
    when deadlock_detected then
      raise exception 'assignment_overlap: a concurrent decision on an overlapping assignment could not be serialized -- retry'
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: assignment % target row was concurrently modified (expected version %)', p_assignment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
  values (
    v_employee.tenant_id, v_employee.master_record_id, v_employee.lifecycle_status, v_employee.lifecycle_status, p_reason,
    jsonb_build_object('event', 'position_assignment', 'assignment_id', v_assignment.id, 'position_id', v_assignment.position_id, 'assignment_type', v_assignment.assignment_type, 'change_reason', v_assignment.change_reason, 'effective_start_date', v_assignment.effective_start_date),
    p_actor_auth_user_id, p_actor_label
  );

  -- Immediate sync only if already, or newly, in effect -- a future-dated approved
  -- assignment is left for app.activate_due_employee_position_assignments once its
  -- date arrives (decision 4).
  if v_assignment.effective_start_date <= current_date then
    perform app.sync_employee_current_assignment_cache(v_assignment);
  end if;

  -- HRT-293 Finding B fix (self-found, CRITICAL, C-24) -- see the reject
  -- branch above.
  perform app.capture_audit_event(
    v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_employee_position_assignment',
    'app.employee_position_assignments', v_assignment.id, 'success', null, null, app.employee_position_assignment_audit_projection(v_assignment)
  );

  return v_assignment;
end;
$$;

create or replace function app.cancel_employee_position_assignment(p_assignment_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.employee_position_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assignment app.employee_position_assignments;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel an assignment' using errcode = 'check_violation';
  end if;

  select * into v_assignment from app.employee_position_assignments where id = p_assignment_id for update;
  if not found or not app.has_active_tenant_membership(v_assignment.tenant_id, p_actor_auth_user_id) then
    raise exception 'assignment_not_found: %', p_assignment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assignment.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assignment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assignment.record_version <> p_expected_version then
    raise exception 'stale_version: assignment % expected version % but found %', p_assignment_id, p_expected_version, v_assignment.record_version
      using errcode = 'serialization_failure';
  end if;

  -- Section 23 "keep the current effective assignment intact": only a proposal still
  -- awaiting decision, or an approved-but-not-yet-effective (future-dated) assignment,
  -- may be cancelled. One already in effect today may never be cancelled retroactively
  -- -- only superseded by a new, properly-approved transfer.
  if v_assignment.status = 'active' and v_assignment.effective_start_date <= current_date then
    raise exception 'assignment_not_cancellable: assignment % is already in effect and cannot be cancelled -- propose a new transfer instead', p_assignment_id
      using errcode = 'check_violation';
  end if;
  if v_assignment.status not in ('pending_approval', 'active') then
    raise exception 'assignment_not_cancellable: assignment % is % and cannot be cancelled', p_assignment_id, v_assignment.status
      using errcode = 'check_violation';
  end if;

  update app.employee_position_assignments
  set status = 'cancelled', decided_by = coalesce(decided_by, p_actor_label), decided_at = coalesce(decided_at, now()), decided_reason = p_reason
  where id = p_assignment_id and record_version = p_expected_version
  returning * into v_assignment;
  if not found then
    raise exception 'stale_version: assignment % target row was concurrently modified (expected version %)', p_assignment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- HRT-293 Finding B fix (self-found, CRITICAL, C-24) -- see app.decide_
  -- employee_position_assignment above.
  perform app.capture_audit_event(
    v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_employee_position_assignment',
    'app.employee_position_assignments', v_assignment.id, 'success', null, null, app.employee_position_assignment_audit_projection(v_assignment)
  );

  return v_assignment;
end;
$$;

create or replace function app.waive_attendance_exception(p_exception_id uuid, p_expected_version integer, p_waive_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.attendance_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_exception app.attendance_exceptions;
begin
  select * into v_exception from app.attendance_exceptions where id = p_exception_id for update;
  if not found or not app.has_active_tenant_membership(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;

  -- decision 11: waive is the same blast radius as terminate/cancel elsewhere
  -- in this repository -- HRS:Override, not merely HRS:Edit.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- C-18 self-approval: an HRS:Override holder may not waive an exception on
  -- their OWN attendance, mirroring app.decide_attendance_correction's
  -- identical self-approval block exactly (self-found in this checkpoint's
  -- own Tier B taxonomy walk).
  declare
    v_self app.employees;
  begin
    v_self := app.get_self_employee(v_exception.tenant_id, p_actor_auth_user_id);
    if v_self.master_record_id is not null and v_self.master_record_id = v_exception.employee_id then
      raise exception 'self_approval_not_permitted: an actor may not waive their own attendance exception' using errcode = 'insufficient_privilege';
    end if;
  end;

  if p_waive_reason is null or length(trim(p_waive_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to waive an exception' using errcode = 'check_violation';
  end if;

  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_exception.status not in ('open', 'acknowledged') then
    raise exception 'invalid_transition: exception % is %, cannot be waived', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  update app.attendance_exceptions
  set status = 'waived', resolved_at = now(), resolved_by = p_actor_label, waive_reason = p_waive_reason
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;
  if not found then
    raise exception 'stale_version: exception % target row was concurrently modified (expected version %)', p_exception_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- HRT-293 Finding B fix (self-found, CRITICAL, C-24): p_waive_reason is
  -- already durably stored above in app.attendance_exceptions.waive_reason
  -- (HRS_REGISTRY hrs:attendance_exceptions.waive_reason, column-restricted
  -- -- masked identically to app.attendance_correction_requests.reason,
  -- whose own decide/cancel functions this same batch already fixed) --
  -- never also duplicated into app.audit_logs.reason.
  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'waive_attendance_exception',
    'app.attendance_exceptions', p_exception_id, 'success', null, null, '{}'::jsonb
  );

  return v_exception;
end;
$$;

create or replace function app.waive_onboarding_task(p_case_id uuid, p_task_id uuid, p_expected_version integer, p_waive_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Override');

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_task.status in ('completed', 'waived') then
    raise exception 'invalid_transition: task % is already %, cannot be waived', p_task_id, v_task.status using errcode = 'check_violation';
  end if;

  if p_waive_reason is null or length(trim(p_waive_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to waive a task' using errcode = 'check_violation';
  end if;

  update app.onboarding_case_tasks
  set status = 'waived', waived_at = now(), waived_by = p_actor_label, waive_reason = p_waive_reason
  where id = p_task_id and record_version = p_expected_version
  returning * into v_task;
  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.recompute_onboarding_case_task_blocked_state(p_case_id);

  -- HRT-293 Finding B fix (self-found, CRITICAL, C-24): p_waive_reason is
  -- already durably stored above in app.onboarding_case_tasks.waive_reason
  -- -- never also duplicated into app.audit_logs.reason.
  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'waive_onboarding_task',
    'app.onboarding_case_tasks', v_task.id, 'success', null, null, app.onboarding_case_task_audit_projection(v_task)
  );

  return v_task;
end;
$$;

create or replace function app.request_onboarding_access_revocation(p_case_id uuid, p_task_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
  v_case app.onboarding_offboarding_cases;
  v_employee app.employees;
  v_request app.onboarding_task_provisioning_requests;
  v_job app.jobs;
  v_note text;
  v_revoked_user app.users;
  v_role_assignment app.role_assignments;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Override');

  if v_task.task_type <> 'access_revocation' then
    raise exception 'wrong_completion_path: task % is %, not access_revocation', p_task_id, v_task.task_type using errcode = 'check_violation';
  end if;

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_task.status not in ('pending', 'in_progress', 'reopened') then
    raise exception 'invalid_transition: task % is %, cannot request revocation', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if v_task.status = 'blocked' then
    raise exception 'task_blocked: task % has an incomplete dependency', p_task_id using errcode = 'check_violation';
  end if;

  -- Review-round fix (HIGH, spec-compliance, business rule 5): a real reason
  -- is now required, mirroring waive/reopen/cancel/rehire's own established
  -- pattern exactly.
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request access revocation' using errcode = 'check_violation';
  end if;

  select * into v_case from app.onboarding_offboarding_cases where id = p_case_id;
  select * into v_employee from app.employees where master_record_id = v_case.employee_master_record_id;

  insert into app.onboarding_task_provisioning_requests (case_id, task_id, tenant_id, request_type, target_auth_user_id, requested_by)
  values (p_case_id, p_task_id, v_task.tenant_id, 'revoke_access', null, p_actor_label)
  returning * into v_request;

  if v_employee.user_id is not null then
    -- Real, governed revocation -- app.transition_user_status already cascades
    -- both the underlying PLT-107 identity linkage AND every active PLT-108
    -- principal membership (its own migration, 20260716102620:271-285).
    perform app.transition_user_status(v_employee.user_id, 'revoked', p_reason, p_actor_label);

    -- Review-round fix (CRITICAL, correctness-concurrency /
    -- revocation-cascade-incomplete): app.transition_user_status's own
    -- revoke branch (PLT-110) never touches app.role_assignments (PLT-111),
    -- and app.evaluate_permission (PLT-112) evaluates role_assignments
    -- directly, never re-checking app.users.status or tenant membership --
    -- live-reproduced pre-fix: a revoked identity with a still-'active'
    -- role_assignments row retained full permission-gated write authority
    -- (evaluate_permission still returned allowed=true, and the identity
    -- could still call app.start_onboarding_case successfully). This is a
    -- real gap in the SHARED PLT-110/112 primitives, used by every domain in
    -- the repository, not something this migration can fix at its root
    -- without a dedicated Platform/RBAC hardening prompt and ADR (AGENTS.md
    -- "Scope and refactoring") -- see docs/runtime/KNOWN_ISSUES.md for the
    -- filed, disclosed systemic gap. What IS fixed here, bounded to this
    -- capability's own real Platform-identity-authority write (the one this
    -- whole prompt is chartered around): every ACTIVE role_assignment this
    -- identity holds in this tenant is explicitly revoked as part of this
    -- same governed call, so THIS revocation path never again leaves
    -- effective authority behind.
    select * into v_revoked_user from app.users where id = v_employee.user_id;
    for v_role_assignment in
      select * from app.role_assignments
      where tenant_id = v_task.tenant_id and auth_user_id = v_revoked_user.auth_user_id and status = 'active'
    loop
      perform app.revoke_role_assignment(v_role_assignment.id, p_reason, p_actor_label);
    end loop;

    update app.onboarding_task_provisioning_requests set status = 'completed', result_user_id = v_employee.user_id, completed_at = now() where id = v_request.id;
    v_note := 'Platform access revoked for user ' || v_employee.user_id::text || ' -- reason: ' || p_reason;

    v_job := app.enqueue_job(v_task.tenant_id, 'integration_sync', jsonb_build_object('onboarding_task_provisioning_request_id', v_request.id, 'case_id', p_case_id, 'task_id', p_task_id, 'user_id', v_employee.user_id), 0, 'hrt277-revocation:' || v_request.id::text, 3, p_actor_auth_user_id, p_actor_label);
    update app.onboarding_task_provisioning_requests set job_id = v_job.job_id where id = v_request.id;
  else
    update app.onboarding_task_provisioning_requests set status = 'completed', completed_at = now() where id = v_request.id;
    v_note := 'No linked Platform user for this employee -- nothing to revoke. Reason: ' || p_reason;
  end if;

  update app.onboarding_case_tasks
  set status = 'completed', completed_at = now(), completed_by = p_actor_label, evidence_note = coalesce(evidence_note, v_note)
  where id = p_task_id and record_version = p_expected_version
  returning * into v_task;
  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.recompute_onboarding_case_task_blocked_state(p_case_id);

  -- HRT-293 Finding B fix (self-found, CRITICAL, C-24): p_reason is already
  -- durably stored above (v_note folded into app.onboarding_case_tasks.
  -- evidence_note, and as the reason argument to app.transition_user_status/
  -- app.revoke_role_assignment, each capturing their OWN evidence trail) --
  -- never also duplicated into app.audit_logs.reason via THIS call.
  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_onboarding_access_revocation',
    'app.onboarding_case_tasks', v_task.id, 'success', null, null, app.onboarding_case_task_audit_projection(v_task) || jsonb_build_object('provisioning_request_id', v_request.id)
  );

  return v_task;
end;
$$;

create or replace function app.cancel_conflicting_schedule_assignment_for_leave(p_leave_request_id uuid, p_work_date date, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.schedule_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.leave_requests;
  v_assignment app.schedule_assignments;
begin
  select * into v_request from app.leave_requests where id = p_leave_request_id;
  if not found then
    raise exception 'leave_request_not_found: %', p_leave_request_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'leave_request_not_found: %', p_leave_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.status <> 'approved' then
    raise exception 'invalid_transition: leave request % is %, only an approved request may override a scheduled shift', p_leave_request_id, v_request.status
      using errcode = 'check_violation';
  end if;
  if p_work_date < v_request.date_from or p_work_date > v_request.date_to then
    raise exception 'work_date_out_of_range: % is not within leave request %''s own date range', p_work_date, p_leave_request_id using errcode = 'check_violation';
  end if;

  select * into v_assignment from app.resolve_effective_schedule_assignment(v_request.tenant_id, v_request.employee_id, p_work_date);
  if not found then
    raise exception 'no_conflicting_schedule: employee % has no published schedule assignment on %', v_request.employee_id, p_work_date using errcode = 'no_data_found';
  end if;

  -- Reuses app.cancel_schedule_assignment (HRT-279) directly -- never a
  -- second cancellation mechanism for the same table (AGENTS.md "do not
  -- create duplicate ... policy engines"). That function itself re-checks
  -- HRS:Override for a published row, so this is not a privilege escalation
  -- path -- it is a real, deliberate delegation to the domain that actually
  -- owns app.schedule_assignments.
  v_assignment := app.cancel_schedule_assignment(v_assignment.id, p_expected_version, coalesce(p_reason, 'leave_request:' || p_leave_request_id::text), p_actor_auth_user_id, p_actor_label);

  -- HRT-293 Finding B fix (self-found, CRITICAL, C-24): app.cancel_schedule_
  -- assignment (called above, this same batch's own fix) already durably
  -- stores p_reason in app.schedule_assignments.cancel_reason and no longer
  -- duplicates it into app.audit_logs.reason itself -- but THIS wrapper was
  -- independently logging a SECOND, redundant audit entry with the same raw
  -- reason under its own action name. Closed the same way.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_conflicting_schedule_assignment_for_leave',
    'app.schedule_assignments', v_assignment.id, 'success', null, null, jsonb_build_object('leave_request_id', p_leave_request_id, 'work_date', p_work_date)
  );

  return v_assignment;
end;
$$;

create or replace function app.record_offer_response(p_offer_id uuid, p_expected_version integer, p_response text, p_response_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.job_offers;
  v_application app.job_applications;
begin
  select * into v_offer from app.job_offers where id = p_offer_id;
  if not found or not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: offer % expected version % but found %', p_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_response not in ('accepted', 'declined') then
    raise exception 'invalid_response: % is not accepted or declined', p_response using errcode = 'check_violation';
  end if;
  if v_offer.status <> 'extended' then
    raise exception 'invalid_transition: offer % is % and has no candidate response to record', p_offer_id, v_offer.status
      using errcode = 'check_violation';
  end if;

  select * into v_application from app.job_applications where id = v_offer.application_id for update;

  update app.job_offers set status = case p_response when 'accepted' then 'accepted' else 'declined' end
  where id = p_offer_id and record_version = p_expected_version
  returning * into v_offer;
  if not found then
    raise exception 'stale_version: offer % target row was concurrently modified (expected version %)', p_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  if p_response = 'accepted' then
    update app.job_applications set stage = 'offer_accepted', stage_since = now()
    where id = v_application.id and record_version = v_application.record_version;
    insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, reason, actor_auth_user_id, actor_label)
    values (v_application.tenant_id, v_application.id, v_application.stage, 'offer_accepted', p_response_note, p_actor_auth_user_id, p_actor_label);
  else
    update app.job_applications set stage = 'rejected', stage_since = now(), rejection_reason = coalesce(p_response_note, 'offer_declined')
    where id = v_application.id and record_version = v_application.record_version;
    insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, reason, actor_auth_user_id, actor_label)
    values (v_application.tenant_id, v_application.id, v_application.stage, 'rejected', coalesce(p_response_note, 'offer_declined'), p_actor_auth_user_id, p_actor_label);
  end if;

  -- HRT-293 Finding B fix (self-found, CRITICAL, C-24): p_response_note (a
  -- candidate's own free-text reason for accepting/declining, which can
  -- disclose personal circumstances) is already durably stored above
  -- (app.application_stage_history.reason, and app.job_applications.
  -- rejection_reason on decline) -- never also duplicated into
  -- app.audit_logs.reason.
  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_offer_response',
    'app.job_offers', v_offer.id, 'success', null, null, jsonb_build_object('status', v_offer.status)
  );

  return v_offer;
end;
$$;

create or replace function app.load_opening_leave_balance(p_tenant_id uuid, p_employee_id uuid, p_leave_type_id uuid, p_units numeric, p_as_of_date date, p_source_reference text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.leave_balance_ledger
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.leave_balance_ledger;
  v_entry app.leave_balance_ledger;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.employees where master_record_id = p_employee_id and tenant_id = p_tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.leave_types where id = p_leave_type_id and tenant_id = p_tenant_id) then
    raise exception 'leave_type_not_found: %', p_leave_type_id using errcode = 'no_data_found';
  end if;
  if p_units is null or p_units <= 0 then
    raise exception 'invalid_units: an opening balance load must be a positive amount' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: an opening balance load requires an idempotency key (section 19 reconciliation)' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.leave_balance_ledger where tenant_id = p_tenant_id and employee_id = p_employee_id and leave_type_id = p_leave_type_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.event_type = 'opening_balance' and v_existing.units = p_units and v_existing.effective_date = p_as_of_date then
      return v_existing;
    else
      raise exception 'idempotency_key_conflict: key % was already used for a different opening balance load', p_idempotency_key using errcode = 'unique_violation';
    end if;
  end if;

  insert into app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, event_type, units, effective_date, reason, idempotency_key, created_by)
  values (p_tenant_id, p_employee_id, p_leave_type_id, 'opening_balance', p_units, coalesce(p_as_of_date, current_date), coalesce(p_source_reference, 'opening balance load'), p_idempotency_key, p_actor_label)
  returning * into v_entry;

  -- HRT-293 Finding B fix (self-found, CRITICAL, C-24): p_source_reference is
  -- already durably stored above in app.leave_balance_ledger.reason
  -- (HRS_REGISTRY hrs:leave_balance_ledger.reason, column-restricted) --
  -- never also duplicated into app.audit_logs.reason. This value is
  -- typically a structural import/migration reference rather than
  -- human-authored narrative, but the column itself is classified
  -- regardless of a given caller's actual content, so this migration closes
  -- it identically to app.adjust_leave_balance above for consistency and
  -- defense in depth against a future caller passing real free text here.
  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'load_opening_leave_balance',
    'app.leave_balance_ledger', v_entry.id, 'success', null, null, jsonb_build_object('employee_id', p_employee_id, 'leave_type_id', p_leave_type_id, 'units', p_units)
  );

  return v_entry;
end;
$$;
