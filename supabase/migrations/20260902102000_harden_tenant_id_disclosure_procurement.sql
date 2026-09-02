-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Part 3 of 5 of a representative repository-wide fix pass (Procurement).
-- See 20260902100000_harden_tenant_id_disclosure_finance.sql for the full rationale
-- (same fix pattern, same repository-wide precedent, applied here to Procurement).
-- Every function below is CREATE OR REPLACE against its CURRENT, live body -- signatures
-- are unchanged throughout, so grants are unaffected.

CREATE OR REPLACE FUNCTION app.accept_vendor_bill_match_within_tolerance(p_match_case_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_bill_match_cases
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.vendor_bill_match_cases;
begin
  select * into v_case from app.vendor_bill_match_cases where id = p_match_case_id for update;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: match case % expected version % but found %', p_match_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_case.is_current then
    raise exception 'invalid_transition: match case % is not the current version', p_match_case_id using errcode = 'check_violation';
  end if;
  -- C-15: re-verify at the actual point of commitment -- overall_status must genuinely
  -- be 'pending' (computed within-tolerance by app._reroll_vendor_bill_match_case) right
  -- now, never trusted from an earlier read the caller might be acting on.
  if v_case.overall_status <> 'pending' then
    raise exception 'invalid_transition: match case % is % -- only a case within tolerance and awaiting explicit accept may be accepted', p_match_case_id, v_case.overall_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_bill_match_cases
  set overall_status = 'matched', readiness_status = 'ready_for_finance', readiness_note = 'accepted within tolerance by ' || coalesce(p_actor_label, p_actor_auth_user_id::text), evaluated_by = p_actor_label, evaluated_at = now()
  where id = p_match_case_id and record_version = p_expected_version
  returning * into v_case;
  if not found then
    raise exception 'stale_version: match case % target row was concurrently modified (expected version %)', p_match_case_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app._record_vendor_bill_match_event(v_case.tenant_id, v_case.id, 'accepted_within_tolerance', '{}'::jsonb, p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'accept_vendor_bill_match_within_tolerance', 'app.vendor_bill_match_cases', v_case.id, 'success', null, null, to_jsonb(v_case));

  return v_case;
end;
$function$;

CREATE OR REPLACE FUNCTION app.activate_vendor_bill_match_tolerance_policy(p_policy_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_bill_match_tolerance_policies
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_policy app.vendor_bill_match_tolerance_policies;
  v_prior app.vendor_bill_match_tolerance_policies;
begin
  select * into v_policy from app.vendor_bill_match_tolerance_policies where id = p_policy_id for update;
  if not found or not app.has_active_tenant_membership(v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_tolerance_policy_not_found: %', p_policy_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Approve', v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve for tenant %', p_actor_auth_user_id, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_policy.record_version <> p_expected_version then
    raise exception 'stale_version: tolerance policy % expected version % but found %', p_policy_id, p_expected_version, v_policy.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_policy.status <> 'draft' then
    raise exception 'invalid_transition: tolerance policy % is % and cannot be activated', p_policy_id, v_policy.status
      using errcode = 'check_violation';
  end if;

  -- C-04: lock any currently-active row of this tenant before superseding it, same
  -- table lock order as this function's own only self-referential mutation (no other
  -- table is locked here, so no C-21 ordering question arises).
  select * into v_prior from app.vendor_bill_match_tolerance_policies where tenant_id = v_policy.tenant_id and status = 'active' for update;
  if found then
    update app.vendor_bill_match_tolerance_policies set status = 'archived' where id = v_prior.id and record_version = v_prior.record_version;
    if not found then
      raise exception 'stale_version: active tolerance policy % was concurrently modified', v_prior.id using errcode = 'serialization_failure';
    end if;
  end if;

  update app.vendor_bill_match_tolerance_policies set status = 'active', approved_by = p_actor_label, approved_at = now()
  where id = p_policy_id and record_version = p_expected_version
  returning * into v_policy;
  if not found then
    raise exception 'stale_version: tolerance policy % target row was concurrently modified (expected version %)', p_policy_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_vendor_bill_match_tolerance_policy', 'app.vendor_bill_match_tolerance_policies', v_policy.id, 'success', null, null, to_jsonb(v_policy));
  return v_policy;
end;
$function$;

CREATE OR REPLACE FUNCTION app.answer_rfq_clarification(p_clarification_id uuid, p_answer text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.rfq_clarifications
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_row app.rfq_clarifications;
begin
  if p_answer is null or length(trim(p_answer)) = 0 then
    raise exception 'answer_required: a non-empty answer is required' using errcode = 'check_violation';
  end if;

  select * into v_row from app.rfq_clarifications where id = p_clarification_id for update;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_clarification_not_found: %', p_clarification_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: rfq clarification % expected version % but found %', p_clarification_id, p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.answer is not null then
    raise exception 'clarification_already_answered: clarification % already carries an answer', p_clarification_id using errcode = 'check_violation';
  end if;

  update app.rfq_clarifications
  set answer = p_answer, answered_by = p_actor_label, answered_at = now()
  where id = p_clarification_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: rfq clarification % target row was concurrently modified (expected version %)', p_clarification_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'answer_rfq_clarification',
    'app.rfq_clarifications', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.cancel_rfq(p_rfq_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.rfqs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_rfq app.rfqs;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel an RFQ' using errcode = 'check_violation';
  end if;

  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found or not app.has_active_tenant_membership(v_rfq.tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rfq.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rfq.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rfq.record_version <> p_expected_version then
    raise exception 'stale_version: rfq % expected version % but found %', p_rfq_id, p_expected_version, v_rfq.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rfq.status not in ('draft', 'issued') then
    raise exception 'invalid_transition: rfq % is % and cannot be cancelled', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_rfq.status;

  update app.rfqs
  set status = 'cancelled', closed_at = now(), closed_reason = p_reason
  where id = p_rfq_id and record_version = p_expected_version
  returning * into v_rfq;
  if not found then
    raise exception 'stale_version: rfq % target row was concurrently modified (expected version %)', p_rfq_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_rfq.tenant_id, p_rfq_id, v_from_status, 'cancelled', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_rfq.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_rfq',
    'app.rfqs', v_rfq.id, 'success', p_reason, null, jsonb_build_object('status', v_rfq.status)
  );

  return v_rfq;
end;
$function$;

CREATE OR REPLACE FUNCTION app.cancel_vendor_bill_match_case(p_match_case_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_bill_match_cases
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.vendor_bill_match_cases;
begin
  select * into v_case from app.vendor_bill_match_cases where id = p_match_case_id for update;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Override', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Override for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a match case' using errcode = 'check_violation';
  end if;
  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: match case % expected version % but found %', p_match_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_case.overall_status in ('cancelled', 'matched') then
    raise exception 'invalid_transition: match case % is % and cannot be cancelled', p_match_case_id, v_case.overall_status using errcode = 'check_violation';
  end if;

  update app.vendor_bill_match_cases
  set overall_status = 'cancelled', readiness_status = 'blocked', cancel_reason = p_reason
  where id = p_match_case_id and record_version = p_expected_version
  returning * into v_case;
  if not found then
    raise exception 'stale_version: match case % target row was concurrently modified (expected version %)', p_match_case_id, p_expected_version using errcode = 'serialization_failure';
  end if;

  perform app._record_vendor_bill_match_event(v_case.tenant_id, v_case.id, 'case_cancelled', jsonb_build_object('reason', p_reason), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_vendor_bill_match_case', 'app.vendor_bill_match_cases', v_case.id, 'success', p_reason, null, to_jsonb(v_case));

  return v_case;
end;
$function$;

CREATE OR REPLACE FUNCTION app.decide_vendor_bill_match_exception_approval(p_approval_id uuid, p_expected_version integer, p_decision text, p_decision_note text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_bill_match_exception_approvals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_peek app.vendor_bill_match_exception_approvals;
  v_case app.vendor_bill_match_cases;
  v_approval app.vendor_bill_match_exception_approvals;
  v_bill app.finance_vendor_bills;
begin
  -- Lock order: unlocked peek to resolve the owning case, THEN lock the case, THEN
  -- lock/re-validate this approval row (migration header).
  select * into v_peek from app.vendor_bill_match_exception_approvals where id = p_approval_id;
  if not found then
    raise exception 'vendor_bill_match_exception_approval_not_found: %', p_approval_id using errcode = 'no_data_found';
  end if;

  select * into v_case from app.vendor_bill_match_cases where id = v_peek.match_case_id for update;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_case_not_found: %', v_peek.match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Approve', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_approval from app.vendor_bill_match_exception_approvals where id = p_approval_id for update;

  -- Taxonomy C-18: self-approval blocked.
  if v_approval.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % requested exception approval % and may not also decide it', p_actor_auth_user_id, p_approval_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_approval.record_version <> p_expected_version then
    raise exception 'stale_version: exception approval % expected version % but found %', p_approval_id, p_expected_version, v_approval.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_approval.status <> 'pending' then
    raise exception 'invalid_transition: exception approval % is % and cannot be decided again', p_approval_id, v_approval.status using errcode = 'check_violation';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not one of approved/rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision_note is null or length(trim(p_decision_note)) = 0 then
    raise exception 'reason_required: a non-empty decision note is required' using errcode = 'check_violation';
  end if;
  -- C-15: re-verify the case is still genuinely in exception right now, and the bill
  -- itself is still not void, at the actual point of commitment.
  if v_case.overall_status <> 'exception' then
    raise exception 'invalid_transition: match case % is no longer in exception (now %) -- this request is stale', v_case.id, v_case.overall_status
      using errcode = 'check_violation';
  end if;
  select * into v_bill from app.finance_vendor_bills where id = v_case.bill_id;
  if not found or v_bill.status = 'void' then
    raise exception 'finance_vendor_bill_void: bill % is void -- this exception approval can no longer be decided', v_case.bill_id using errcode = 'check_violation';
  end if;

  update app.vendor_bill_match_exception_approvals
  set status = p_decision, decision_note = p_decision_note, decided_by_auth_user_id = p_actor_auth_user_id, decided_at = now()
  where id = p_approval_id and record_version = p_expected_version
  returning * into v_approval;
  if not found then
    raise exception 'stale_version: exception approval % target row was concurrently modified (expected version %)', p_approval_id, p_expected_version using errcode = 'serialization_failure';
  end if;

  update app.vendor_bill_match_cases
  set overall_status = case when p_decision = 'approved' then 'matched' else 'blocked' end,
      readiness_status = case when p_decision = 'approved' then 'ready_for_finance' else 'blocked' end,
      readiness_note = case when p_decision = 'approved' then 'exception approved: ' || p_decision_note else 'exception rejected: ' || p_decision_note end
  where id = v_case.id;

  perform app._record_vendor_bill_match_event(v_case.tenant_id, v_case.id, 'exception_approval_decided', jsonb_build_object('approvalId', p_approval_id, 'decision', p_decision), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_bill_match_exception_approval', 'app.vendor_bill_match_exception_approvals', v_approval.id, 'success', p_decision_note, null, jsonb_build_object('decision', p_decision));

  return v_approval;
end;
$function$;

CREATE OR REPLACE FUNCTION app.decline_rfq_invitation(p_rfq_invitation_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.rfq_invitations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_invitation app.rfq_invitations;
  v_rfq_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decline an invitation' using errcode = 'check_violation';
  end if;

  select * into v_invitation from app.rfq_invitations where id = p_rfq_invitation_id for update;
  if not found or not app.has_active_tenant_membership(v_invitation.tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_invitation_not_found: %', p_rfq_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: rfq invitation % expected version % but found %', p_rfq_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;

  -- design note 8: child (invitation) already locked above, parent (rfq)
  -- locked here, second.
  select status into v_rfq_status from app.rfqs where id = v_invitation.rfq_id for update;
  if v_rfq_status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % -- an invitation may only be declined while issued', v_invitation.rfq_id, v_rfq_status
      using errcode = 'check_violation';
  end if;
  if v_invitation.status <> 'invited' then
    raise exception 'invalid_transition: rfq invitation % is % and cannot be declined', p_rfq_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.rfq_invitations
  set status = 'declined', decline_reason = p_reason, declined_at = now()
  where id = p_rfq_invitation_id and record_version = p_expected_version
  returning * into v_invitation;
  if not found then
    raise exception 'stale_version: rfq invitation % target row was concurrently modified (expected version %)', p_rfq_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'decline_rfq_invitation',
    'app.rfq_invitations', v_invitation.id, 'success', p_reason, null, jsonb_build_object('status', v_invitation.status)
  );

  return v_invitation;
end;
$function$;

CREATE OR REPLACE FUNCTION app.extend_rfq_deadline(p_rfq_id uuid, p_new_deadline_at timestamp with time zone, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.rfqs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_rfq app.rfqs;
begin
  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found or not app.has_active_tenant_membership(v_rfq.tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rfq.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rfq.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rfq.record_version <> p_expected_version then
    raise exception 'stale_version: rfq % expected version % but found %', p_rfq_id, p_expected_version, v_rfq.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rfq.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % -- the deadline may only be extended while issued', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;
  if p_new_deadline_at is null or p_new_deadline_at < v_rfq.response_deadline_at then
    raise exception 'deadline_narrowing_not_allowed: new deadline % is earlier than the current deadline % -- an extension only widens', p_new_deadline_at, v_rfq.response_deadline_at
      using errcode = 'check_violation';
  end if;

  update app.rfqs
  set response_deadline_at = p_new_deadline_at
  where id = p_rfq_id and record_version = p_expected_version
  returning * into v_rfq;
  if not found then
    raise exception 'stale_version: rfq % target row was concurrently modified (expected version %)', p_rfq_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, evidence_ref, actor_auth_user_id, actor_label)
  values (v_rfq.tenant_id, p_rfq_id, 'issued', 'issued', 'new_response_deadline_at=' || p_new_deadline_at::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_rfq.tenant_id, p_actor_auth_user_id, p_actor_label, 'extend_rfq_deadline',
    'app.rfqs', v_rfq.id, 'success', null, null, jsonb_build_object('response_deadline_at', v_rfq.response_deadline_at)
  );

  return v_rfq;
end;
$function$;

CREATE OR REPLACE FUNCTION app.invite_additional_rfq_vendor(p_rfq_id uuid, p_sourcing_candidate_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.rfq_invitations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_rfq app.rfqs;
  v_candidate app.sourcing_candidates;
  v_invitation app.rfq_invitations;
  v_constraint_name text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to invite an additional vendor' using errcode = 'check_violation';
  end if;

  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found or not app.has_active_tenant_membership(v_rfq.tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rfq.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rfq.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rfq.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % -- additional vendors may only be invited while issued', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;

  -- Locked (taxonomy C-04): the eligible/not-eligible decision below is made
  -- on this row -- an unlocked read could race a concurrent PRC-256
  -- re-evaluation (app.evaluate_sourcing_candidate_eligibility) that flips
  -- eligible=false between this read and the insert. app.rfqs is locked
  -- first (above), this sourcing_candidates row second -- the two lock sets
  -- never overlap with either PRC-256 function's own locking order
  -- (candidate row(s) then sourcing_requests row; app.rfqs is never locked
  -- by any PRC-256 function), so no new deadlock class is introduced.
  select * into v_candidate from app.sourcing_candidates where id = p_sourcing_candidate_id for update;
  if not found then
    raise exception 'sourcing_candidate_not_found: %', p_sourcing_candidate_id using errcode = 'no_data_found';
  end if;
  if v_candidate.sourcing_request_id <> v_rfq.sourcing_request_id then
    raise exception 'candidate_source_mismatch: candidate % does not belong to rfq %''s own sourcing request', p_sourcing_candidate_id, p_rfq_id
      using errcode = 'check_violation';
  end if;
  if v_candidate.tenant_id <> v_rfq.tenant_id then
    raise exception 'tenant_mismatch: candidate % does not belong to tenant %', p_sourcing_candidate_id, v_rfq.tenant_id
      using errcode = 'check_violation';
  end if;
  if not v_candidate.eligible then
    raise exception 'ineligible_vendor: candidate % is not eligible and cannot be invited', p_sourcing_candidate_id
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.rfq_invitations (tenant_id, rfq_id, sourcing_candidate_id, vendor_master_id, invited_by)
    values (v_rfq.tenant_id, p_rfq_id, v_candidate.id, v_candidate.vendor_master_id, p_actor_label)
    returning * into v_invitation;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'rfq_invitations_unique_vendor' then
        raise exception 'vendor_already_invited: vendor % is already invited to rfq %', v_candidate.vendor_master_id, p_rfq_id
          using errcode = 'unique_violation';
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_rfq.tenant_id, p_actor_auth_user_id, p_actor_label, 'invite_additional_rfq_vendor',
    'app.rfq_invitations', v_invitation.id, 'success', p_reason, null, to_jsonb(v_invitation)
  );

  return v_invitation;
end;
$function$;

CREATE OR REPLACE FUNCTION app.issue_rfq(p_rfq_id uuid, p_response_deadline_at timestamp with time zone, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.rfqs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_rfq app.rfqs;
  v_candidate record;
  v_count integer := 0;
begin
  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found or not app.has_active_tenant_membership(v_rfq.tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rfq.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rfq.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rfq.record_version <> p_expected_version then
    raise exception 'stale_version: rfq % expected version % but found %', p_rfq_id, p_expected_version, v_rfq.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rfq.status <> 'draft' then
    raise exception 'invalid_transition: rfq % is % and cannot be issued', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;
  if p_response_deadline_at is null or p_response_deadline_at <= now() then
    raise exception 'invalid_deadline: response deadline must be a future timestamp' using errcode = 'check_violation';
  end if;

  -- design note 11: bounded bulk invitation scan, disclosed via a real warning.
  for v_candidate in
    select id, vendor_master_id
    from app.sourcing_candidates
    where sourcing_request_id = v_rfq.sourcing_request_id and shortlisted = true
    order by id
    limit 501
  loop
    v_count := v_count + 1;
    if v_count > 500 then
      raise warning 'rfq_invitation_scan_bounded: rfq % has more than 500 shortlisted candidates -- only the first 500 (ordered by id) were invited this call; re-run app.invite_additional_rfq_vendor for the remainder', p_rfq_id;
      exit;
    end if;
    insert into app.rfq_invitations (tenant_id, rfq_id, sourcing_candidate_id, vendor_master_id, invited_by)
    values (v_rfq.tenant_id, p_rfq_id, v_candidate.id, v_candidate.vendor_master_id, p_actor_label)
    on conflict (rfq_id, vendor_master_id) do nothing;
  end loop;

  if v_count = 0 then
    raise exception 'no_shortlisted_vendors: sourcing request % has no shortlisted candidates to invite', v_rfq.sourcing_request_id
      using errcode = 'check_violation';
  end if;

  update app.rfqs
  set status = 'issued', issued_at = now(), response_deadline_at = p_response_deadline_at
  where id = p_rfq_id and record_version = p_expected_version
  returning * into v_rfq;
  if not found then
    raise exception 'stale_version: rfq % target row was concurrently modified (expected version %)', p_rfq_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_rfq.tenant_id, p_rfq_id, 'draft', 'issued', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_rfq.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_rfq',
    'app.rfqs', v_rfq.id, 'success', null, null, jsonb_build_object('status', v_rfq.status, 'invited_count', least(v_count, 500))
  );

  return v_rfq;
end;
$function$;

CREATE OR REPLACE FUNCTION app.map_vendor_bill_match_line(p_match_line_id uuid, p_expected_case_version integer, p_po_line_id uuid, p_rate_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_bill_match_lines
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_peek app.vendor_bill_match_lines;
  v_case app.vendor_bill_match_cases;
  v_line app.vendor_bill_match_lines;
  v_po_line app.purchase_order_lines;
  v_rate app.vendor_rate_versions;
  v_computed record;
begin
  -- Lock order (migration header): unlocked peek to resolve the owning case, THEN lock
  -- the parent case, THEN lock/re-validate this child row.
  select * into v_peek from app.vendor_bill_match_lines where id = p_match_line_id;
  if not found then
    raise exception 'vendor_bill_match_line_not_found: %', p_match_line_id using errcode = 'no_data_found';
  end if;

  select * into v_case from app.vendor_bill_match_cases where id = v_peek.match_case_id for update;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_case_not_found: %', v_peek.match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_case.record_version <> p_expected_case_version then
    raise exception 'stale_version: match case % expected version % but found %', v_case.id, p_expected_case_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;
  if not v_case.is_current or v_case.overall_status not in ('pending', 'exception') then
    raise exception 'invalid_transition: match case % is % and its lines can no longer be mapped', v_case.id, v_case.overall_status
      using errcode = 'check_violation';
  end if;

  select * into v_line from app.vendor_bill_match_lines where id = p_match_line_id for update;

  if p_po_line_id is not null then
    select * into v_po_line from app.purchase_order_lines where id = p_po_line_id and tenant_id = v_case.tenant_id;
    if not found or v_po_line.purchase_order_id <> v_case.purchase_order_id then
      raise exception 'po_line_scope_mismatch: purchase order line % does not belong to this case''s own purchase order', p_po_line_id using errcode = 'check_violation';
    end if;
    v_line.po_line_id := p_po_line_id;
    v_line.po_line_quantity_variance_pct := app._vendor_bill_match_pct_variance(v_line.vendor_stated_quantity, v_po_line.quantity);
    v_line.po_line_uom_mismatch := v_po_line.uom is not null and v_line.vendor_stated_uom is not null and lower(trim(v_po_line.uom)) <> lower(trim(v_line.vendor_stated_uom));
  end if;

  if p_rate_version_id is not null then
    select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id and tenant_id = v_case.tenant_id;
    if not found or v_rate.vendor_master_id is distinct from v_case.vendor_master_id then
      raise exception 'rate_version_scope_mismatch: rate version % does not belong to this case''s own vendor', p_rate_version_id using errcode = 'check_violation';
    end if;
    v_line.rate_version_id := p_rate_version_id;
    if v_line.evidence_quantity is not null and v_rate.currency = v_case.currency then
      begin
        select computed_amount, currency into v_computed from app.calculate_vendor_rate(p_rate_version_id, null, null, v_line.evidence_quantity, p_actor_auth_user_id);
        v_line.contracted_rate_amount := v_computed.computed_amount;
        v_line.contracted_rate_currency := v_computed.currency;
      exception
        when others then
          -- Best-effort only (migration header): a tier-resolution failure (e.g. no
          -- tier covers this quantity) never blocks the rest of the mapping.
          v_line.contracted_rate_amount := null;
          v_line.contracted_rate_currency := null;
      end;
    end if;
  end if;

  update app.vendor_bill_match_lines
  set po_line_id = v_line.po_line_id, po_line_quantity_variance_pct = v_line.po_line_quantity_variance_pct, po_line_uom_mismatch = v_line.po_line_uom_mismatch,
      rate_version_id = v_line.rate_version_id, contracted_rate_amount = v_line.contracted_rate_amount, contracted_rate_currency = v_line.contracted_rate_currency
  where id = p_match_line_id
  returning * into v_line;

  perform app._reroll_vendor_bill_match_case(v_case.id);

  perform app._record_vendor_bill_match_event(v_case.tenant_id, v_case.id, 'line_mapped', jsonb_build_object('matchLineId', p_match_line_id, 'poLineId', p_po_line_id, 'rateVersionId', p_rate_version_id), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'map_vendor_bill_match_line', 'app.vendor_bill_match_lines', v_line.id, 'success', null, null, '{}'::jsonb);

  return v_line;
end;
$function$;

CREATE OR REPLACE FUNCTION app.raise_vendor_bill_match_dispute(p_match_case_id uuid, p_match_line_id uuid, p_reason text, p_disputed_amount numeric, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_bill_match_disputes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.vendor_bill_match_cases;
  v_dispute app.vendor_bill_match_disputes;
begin
  select * into v_case from app.vendor_bill_match_cases where id = p_match_case_id for update;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to raise a vendor bill match dispute' using errcode = 'check_violation';
  end if;
  if not v_case.is_current or v_case.overall_status in ('cancelled', 'disputed') then
    raise exception 'invalid_transition: match case % is % and cannot be disputed', p_match_case_id, v_case.overall_status using errcode = 'check_violation';
  end if;
  if p_match_line_id is not null and not exists (select 1 from app.vendor_bill_match_lines where id = p_match_line_id and match_case_id = p_match_case_id) then
    raise exception 'vendor_bill_match_line_not_found: % does not belong to match case %', p_match_line_id, p_match_case_id using errcode = 'no_data_found';
  end if;

  update app.vendor_bill_match_cases set overall_status = 'disputed', readiness_status = 'not_ready', readiness_note = 'dispute raised: ' || p_reason where id = p_match_case_id;

  begin
    insert into app.vendor_bill_match_disputes (tenant_id, match_case_id, match_line_id, reason, disputed_amount, raised_by_auth_user_id, raised_by, created_by)
    values (v_case.tenant_id, p_match_case_id, p_match_line_id, p_reason, p_disputed_amount, p_actor_auth_user_id, p_actor_label, p_actor_label)
    returning * into v_dispute;
  exception
    when unique_violation then
      raise exception 'dispute_already_open: match case % (line %) already has an open dispute', p_match_case_id, p_match_line_id using errcode = 'unique_violation';
  end;

  perform app._record_vendor_bill_match_event(v_case.tenant_id, p_match_case_id, 'dispute_raised', jsonb_build_object('disputeId', v_dispute.id, 'matchLineId', p_match_line_id), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'raise_vendor_bill_match_dispute', 'app.vendor_bill_match_disputes', v_dispute.id, 'success', p_reason, null, jsonb_build_object('matchCaseId', p_match_case_id));

  return v_dispute;
end;
$function$;

CREATE OR REPLACE FUNCTION app.record_rfq_clarification(p_rfq_id uuid, p_vendor_master_id uuid, p_question text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.rfq_clarifications
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_rfq app.rfqs;
  v_row app.rfq_clarifications;
begin
  if p_question is null or length(trim(p_question)) = 0 then
    raise exception 'question_required: a non-empty question is required' using errcode = 'check_violation';
  end if;

  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found or not app.has_active_tenant_membership(v_rfq.tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rfq.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rfq.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rfq.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % -- clarifications may only be recorded while issued', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;
  if p_vendor_master_id is not null and not exists (select 1 from app.rfq_invitations where rfq_id = p_rfq_id and vendor_master_id = p_vendor_master_id) then
    raise exception 'vendor_not_invited: vendor % is not invited to rfq %', p_vendor_master_id, p_rfq_id using errcode = 'check_violation';
  end if;

  insert into app.rfq_clarifications (tenant_id, rfq_id, vendor_master_id, question, asked_by)
  values (v_rfq.tenant_id, p_rfq_id, p_vendor_master_id, p_question, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    v_rfq.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_rfq_clarification',
    'app.rfq_clarifications', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.record_vendor_bill_match_dispute_response(p_dispute_id uuid, p_expected_version integer, p_vendor_response text, p_vendor_response_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_bill_match_disputes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_dispute app.vendor_bill_match_disputes;
  v_file app.files;
begin
  select * into v_dispute from app.vendor_bill_match_disputes where id = p_dispute_id for update;
  if not found or not app.has_active_tenant_membership(v_dispute.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_dispute_not_found: %', p_dispute_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_dispute.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_dispute.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_dispute.record_version <> p_expected_version then
    raise exception 'stale_version: dispute % expected version % but found %', p_dispute_id, p_expected_version, v_dispute.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_dispute.status <> 'open' then
    raise exception 'invalid_transition: dispute % is % and can no longer take a response', p_dispute_id, v_dispute.status using errcode = 'check_violation';
  end if;
  if p_vendor_response is null or length(trim(p_vendor_response)) = 0 then
    raise exception 'reason_required: a non-empty response is required' using errcode = 'check_violation';
  end if;

  if p_vendor_response_file_id is not null then
    select * into v_file from app.files where id = p_vendor_response_file_id;
    if not found then
      raise exception 'evidence_file_not_found: %', p_vendor_response_file_id using errcode = 'no_data_found';
    end if;
    if v_file.tenant_id <> v_dispute.tenant_id or v_file.record_type <> 'vendor_bill_match_dispute' or v_file.record_id <> p_dispute_id then
      raise exception 'dispute_evidence_file_mismatch: file % does not belong to dispute % in tenant %', p_vendor_response_file_id, p_dispute_id, v_dispute.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'dispute_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be recorded', p_vendor_response_file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  update app.vendor_bill_match_disputes
  set vendor_response = p_vendor_response, vendor_response_at = now(), vendor_response_file_id = coalesce(p_vendor_response_file_id, vendor_response_file_id)
  where id = p_dispute_id and record_version = p_expected_version
  returning * into v_dispute;
  if not found then
    raise exception 'stale_version: dispute % target row was concurrently modified (expected version %)', p_dispute_id, p_expected_version using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(v_dispute.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_vendor_bill_match_dispute_response', 'app.vendor_bill_match_disputes', v_dispute.id, 'success', null, null, '{}'::jsonb);
  return v_dispute;
end;
$function$;

CREATE OR REPLACE FUNCTION app.request_vendor_bill_match_exception_approval(p_match_case_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_bill_match_exception_approvals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_case app.vendor_bill_match_cases;
  v_approval app.vendor_bill_match_exception_approvals;
begin
  select * into v_case from app.vendor_bill_match_cases where id = p_match_case_id for update;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_case_not_found: %', p_match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: match case % expected version % but found %', p_match_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request an exception approval' using errcode = 'check_violation';
  end if;
  if v_case.overall_status <> 'exception' then
    raise exception 'invalid_transition: match case % is % -- exception approval may only be requested for a case in exception', p_match_case_id, v_case.overall_status
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.vendor_bill_match_exception_approvals (tenant_id, match_case_id, reason, variance_amount, variance_pct, includes_duplicate_flag, requested_by_auth_user_id, requested_by, created_by)
    values (v_case.tenant_id, p_match_case_id, p_reason, v_case.total_variance_amount, v_case.total_variance_pct, v_case.is_duplicate_flagged, p_actor_auth_user_id, p_actor_label, p_actor_label)
    returning * into v_approval;
  exception
    when unique_violation then
      raise exception 'exception_approval_already_pending: match case % already has a pending exception approval request', p_match_case_id using errcode = 'unique_violation';
  end;

  perform app._record_vendor_bill_match_event(v_case.tenant_id, p_match_case_id, 'exception_approval_requested', jsonb_build_object('approvalId', v_approval.id), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_vendor_bill_match_exception_approval', 'app.vendor_bill_match_exception_approvals', v_approval.id, 'success', p_reason, null, jsonb_build_object('matchCaseId', p_match_case_id));

  return v_approval;
end;
$function$;

CREATE OR REPLACE FUNCTION app.resolve_vendor_bill_match_dispute(p_dispute_id uuid, p_expected_version integer, p_decision text, p_resolution_note text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_bill_match_disputes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_peek app.vendor_bill_match_disputes;
  v_case app.vendor_bill_match_cases;
  v_dispute app.vendor_bill_match_disputes;
begin
  -- Lock order: unlocked peek to resolve the owning case, THEN lock the case, THEN
  -- lock/re-validate this dispute row (migration header).
  select * into v_peek from app.vendor_bill_match_disputes where id = p_dispute_id;
  if not found then
    raise exception 'vendor_bill_match_dispute_not_found: %', p_dispute_id using errcode = 'no_data_found';
  end if;

  select * into v_case from app.vendor_bill_match_cases where id = v_peek.match_case_id for update;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_case_not_found: %', v_peek.match_case_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Approve', v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve for tenant %', p_actor_auth_user_id, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_dispute from app.vendor_bill_match_disputes where id = p_dispute_id for update;

  -- Taxonomy C-18: self-approval blocked -- the raiser may never also resolve their own
  -- dispute.
  if v_dispute.raised_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % raised dispute % and may not also resolve it', p_actor_auth_user_id, p_dispute_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_dispute.record_version <> p_expected_version then
    raise exception 'stale_version: dispute % expected version % but found %', p_dispute_id, p_expected_version, v_dispute.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_dispute.status <> 'open' then
    raise exception 'invalid_transition: dispute % is % and cannot be resolved again', p_dispute_id, v_dispute.status using errcode = 'check_violation';
  end if;
  if p_decision not in ('upheld', 'rejected', 'withdrawn') then
    raise exception 'invalid_decision: % is not one of upheld/rejected/withdrawn', p_decision using errcode = 'check_violation';
  end if;
  if p_resolution_note is null or length(trim(p_resolution_note)) = 0 then
    raise exception 'reason_required: a non-empty resolution note is required' using errcode = 'check_violation';
  end if;

  update app.vendor_bill_match_disputes
  set status = p_decision, resolution_note = p_resolution_note, resolved_by_auth_user_id = p_actor_auth_user_id, resolved_at = now()
  where id = p_dispute_id and record_version = p_expected_version
  returning * into v_dispute;
  if not found then
    raise exception 'stale_version: dispute % target row was concurrently modified (expected version %)', p_dispute_id, p_expected_version using errcode = 'serialization_failure';
  end if;

  -- Any resolution returns the case to pending -- a fresh accept/exception-approval
  -- decision is always required afterward, never silently re-cleared.
  update app.vendor_bill_match_cases
  set overall_status = 'pending', readiness_status = 'not_ready', readiness_note = 'dispute ' || p_decision || ' -- awaiting a fresh accept or exception-approval decision'
  where id = v_case.id;

  perform app._record_vendor_bill_match_event(v_case.tenant_id, v_case.id, 'dispute_resolved', jsonb_build_object('disputeId', p_dispute_id, 'decision', p_decision), p_actor_auth_user_id, p_actor_label);
  perform app.capture_audit_event(v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_vendor_bill_match_dispute', 'app.vendor_bill_match_disputes', v_dispute.id, 'success', p_resolution_note, null, jsonb_build_object('decision', p_decision));

  return v_dispute;
end;
$function$;

CREATE OR REPLACE FUNCTION app.revise_rfq(p_rfq_id uuid, p_cargo_weight_max numeric, p_cargo_volume_max numeric, p_destination_lane text, p_currency text, p_reason text, p_idempotency_key text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.rfqs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_old app.rfqs;
  v_existing app.rfqs;
  v_new app.rfqs;
  v_new_weight_max numeric;
  v_new_volume_max numeric;
  v_new_dest text;
  v_new_currency text;
  v_constraint_name text;
  v_qty numeric;
  v_uom text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to revise an RFQ' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;

  select * into v_old from app.rfqs where id = p_rfq_id for update;
  if not found or not app.has_active_tenant_membership(v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_old.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Resolved early (before the idempotency check) so the replay comparison
  -- below can verify the FULL target tuple, not just revised_from_id (ground
  -- rule 4 / taxonomy C-01) -- v_old's stored values are unchanged between
  -- the original call and any replay (a replay only ever finds this row
  -- already 'superseded' by the FIRST call using this exact key, and no
  -- other function mutates cargo_weight_max/cargo_volume_max/destination_
  -- lane/currency on an rfqs row).
  v_new_weight_max := coalesce(p_cargo_weight_max, v_old.cargo_weight_max);
  v_new_volume_max := coalesce(p_cargo_volume_max, v_old.cargo_volume_max);
  v_new_dest := coalesce(nullif(trim(p_destination_lane), ''), v_old.destination_lane);
  v_new_currency := coalesce(nullif(trim(p_currency), ''), v_old.currency);

  -- Idempotency replay is checked BEFORE the version/status gates below --
  -- deliberately. A replay of an already-succeeded revise arrives with the
  -- PRE-revise p_expected_version and finds the row already 'superseded' (the
  -- first call's own terminal state), so checking version/status first would
  -- turn a legitimate retry into a false stale_version/invalid_transition
  -- instead of the intended idempotent short-circuit.
  select * into v_existing from app.rfqs where tenant_id = v_old.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.revised_from_id is distinct from p_rfq_id
      or v_existing.cargo_weight_max is distinct from v_new_weight_max
      or v_existing.cargo_volume_max is distinct from v_new_volume_max
      or v_existing.destination_lane is distinct from v_new_dest
      or v_existing.currency is distinct from v_new_currency
    then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different RFQ revision', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if v_old.record_version <> p_expected_version then
    raise exception 'stale_version: rfq % expected version % but found %', p_rfq_id, p_expected_version, v_old.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_old.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % -- only an issued RFQ may be revised', p_rfq_id, v_old.status
      using errcode = 'check_violation';
  end if;

  update app.rfqs
  set status = 'superseded'
  where id = p_rfq_id and record_version = p_expected_version
  returning * into v_old;
  if not found then
    raise exception 'stale_version: rfq % target row was concurrently modified (expected version %)', p_rfq_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  begin
    insert into app.rfqs (
      tenant_id, org_unit_id, sourcing_request_id, rfq_number, version, revised_from_id, requirements_snapshot,
      service_type, mode, origin_lane, destination_lane, cargo_weight_min, cargo_weight_max, cargo_volume_min, cargo_volume_max, currency,
      status, owner_user_id, idempotency_key, created_by
    ) values (
      v_old.tenant_id, v_old.org_unit_id, v_old.sourcing_request_id, v_old.rfq_number, v_old.version + 1, v_old.id, v_old.requirements_snapshot,
      v_old.service_type, v_old.mode, v_old.origin_lane, v_new_dest, v_old.cargo_weight_min, v_new_weight_max, v_old.cargo_volume_min, v_new_volume_max, v_new_currency,
      'draft', v_old.owner_user_id, p_idempotency_key, p_actor_label
    )
    returning * into v_new;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'rfqs_tenant_idempotency_unique' then
        select * into v_existing from app.rfqs where tenant_id = v_old.tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.revised_from_id is distinct from p_rfq_id
            or v_existing.cargo_weight_max is distinct from v_new_weight_max
            or v_existing.cargo_volume_max is distinct from v_new_volume_max
            or v_existing.destination_lane is distinct from v_new_dest
            or v_existing.currency is distinct from v_new_currency
          then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different RFQ revision', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise;
  end;

  v_qty := coalesce(v_new.cargo_weight_max, v_new.cargo_volume_max);
  v_uom := case when v_new.cargo_weight_max is not null then 'kg' when v_new.cargo_volume_max is not null then 'cbm' else null end;
  insert into app.rfq_requirement_lines (tenant_id, rfq_id, line_no, description, quantity, uom)
  values (v_new.tenant_id, v_new.id, 1, v_new.service_type, v_qty, v_uom);

  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_old.tenant_id, v_old.id, 'issued', 'superseded', p_reason, p_actor_auth_user_id, p_actor_label);
  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_new.tenant_id, v_new.id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_new.tenant_id, p_actor_auth_user_id, p_actor_label, 'revise_rfq',
    'app.rfqs', v_new.id, 'success', p_reason, to_jsonb(v_old), to_jsonb(v_new)
  );

  return v_new;
end;
$function$;

CREATE OR REPLACE FUNCTION app.submit_rfq_response(p_rfq_invitation_id uuid, p_currency text, p_total_amount numeric, p_validity_until timestamp with time zone, p_lead_time_days integer, p_commercial_terms jsonb, p_capture_mode text, p_source_message_ref text, p_received_at timestamp with time zone, p_vendor_confirmed boolean, p_file_ids uuid[], p_late_reason text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.rfq_responses
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_late_decision app.rbac_decision;
  v_invitation app.rfq_invitations;
  v_rfq app.rfqs;
  v_late boolean;
  v_existing app.rfq_responses;
  v_response app.rfq_responses;
  v_file app.files;
  v_file_id uuid;
  v_prev_version integer;
  v_prev_id uuid;
  v_constraint_name text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;
  if p_currency is null or length(trim(p_currency)) = 0 then
    raise exception 'invalid_currency: currency must not be empty' using errcode = 'check_violation';
  end if;
  if p_total_amount is null or p_total_amount < 0 then
    raise exception 'invalid_total_amount: total_amount must be a non-negative number' using errcode = 'check_violation';
  end if;
  if p_received_at is null then
    raise exception 'received_at_required: received_at must not be empty' using errcode = 'check_violation';
  end if;
  if p_capture_mode is null or p_capture_mode not in ('offline', 'email') then
    raise exception 'invalid_capture_mode: % is not one of offline/email', p_capture_mode using errcode = 'check_violation';
  end if;

  select * into v_invitation from app.rfq_invitations where id = p_rfq_invitation_id for update;
  if not found or not app.has_active_tenant_membership(v_invitation.tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_invitation_not_found: %', p_rfq_invitation_id using errcode = 'no_data_found';
  end if;

  -- design note 7: baseline PRC:Edit check runs BEFORE the parent rfq (and
  -- its own deadline) is ever read -- discloses nothing about the rfq itself.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.status not in ('invited', 'responded') then
    raise exception 'invalid_transition: rfq invitation % is % and cannot accept a response', p_rfq_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  -- design note 8: child (invitation) already locked above, parent (rfq)
  -- locked here, second.
  select * into v_rfq from app.rfqs where id = v_invitation.rfq_id for update;
  if v_rfq.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % and is not accepting responses', v_rfq.id, v_rfq.status
      using errcode = 'check_violation';
  end if;

  v_late := p_received_at > v_rfq.response_deadline_at;
  if v_late then
    v_late_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Override');
    if not v_late_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant % -- a response received after the deadline requires an authorized late capture', p_actor_auth_user_id, v_late_decision.reason, v_invitation.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    if p_late_reason is null or length(trim(p_late_reason)) = 0 then
      raise exception 'late_reason_required: a reason is required to capture a response received after the deadline' using errcode = 'check_violation';
    end if;
  end if;

  -- Ground rule 4 / taxonomy C-01: compares every load-bearing caller-
  -- supplied field, not a subset -- including the ones a narrower comparison
  -- would let a reused key silently drift on (lead time, validity, capture
  -- mode, source reference, vendor confirmation, commercial terms).
  select * into v_existing from app.rfq_responses where tenant_id = v_invitation.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.rfq_invitation_id is distinct from p_rfq_invitation_id or v_existing.total_amount is distinct from p_total_amount
      or v_existing.currency is distinct from p_currency or v_existing.received_at is distinct from p_received_at
      or v_existing.validity_until is distinct from p_validity_until or v_existing.lead_time_days is distinct from p_lead_time_days
      or v_existing.capture_mode is distinct from p_capture_mode or v_existing.source_message_ref is distinct from p_source_message_ref
      or v_existing.vendor_confirmed is distinct from coalesce(p_vendor_confirmed, false)
      or v_existing.commercial_terms is distinct from coalesce(p_commercial_terms, '{}'::jsonb)
    then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different RFQ response', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  -- design note 9: every file is re-validated HERE, never trusted from a
  -- prior check -- tenant, record scope (uploaded against the already-
  -- existing invitation), and scan status.
  if p_file_ids is not null then
    foreach v_file_id in array p_file_ids loop
      select * into v_file from app.files where id = v_file_id;
      if not found then
        raise exception 'rfq_response_file_not_found: %', v_file_id using errcode = 'no_data_found';
      end if;
      if v_file.tenant_id <> v_invitation.tenant_id or v_file.record_type <> 'rfq_invitation' or v_file.record_id <> p_rfq_invitation_id then
        raise exception 'rfq_response_file_mismatch: file % does not belong to invitation % in tenant %', v_file_id, p_rfq_invitation_id, v_invitation.tenant_id
          using errcode = 'check_violation';
      end if;
      if v_file.malware_scan_status <> 'clean' then
        raise exception 'rfq_response_unsafe_file: file % has scan status % -- only clean files may be attached', v_file_id, v_file.malware_scan_status
          using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  select coalesce(max(version), 0), (array_agg(id order by version desc))[1]
  into v_prev_version, v_prev_id
  from app.rfq_responses where rfq_invitation_id = p_rfq_invitation_id;

  begin
    insert into app.rfq_responses (
      tenant_id, rfq_id, rfq_invitation_id, vendor_master_id, version, previous_version_id,
      currency, total_amount, validity_until, lead_time_days, commercial_terms, capture_mode, source_message_ref,
      received_at, vendor_confirmed, late_capture, late_reason, comparison_eligible, idempotency_key, actor_auth_user_id, actor_label
    ) values (
      v_invitation.tenant_id, v_invitation.rfq_id, p_rfq_invitation_id, v_invitation.vendor_master_id, coalesce(v_prev_version, 0) + 1, v_prev_id,
      p_currency, p_total_amount, p_validity_until, p_lead_time_days, coalesce(p_commercial_terms, '{}'::jsonb), p_capture_mode, p_source_message_ref,
      p_received_at, coalesce(p_vendor_confirmed, false), v_late, p_late_reason, not v_late, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    )
    returning * into v_response;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'rfq_responses_tenant_idempotency_unique' then
        select * into v_existing from app.rfq_responses where tenant_id = v_invitation.tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.rfq_invitation_id is distinct from p_rfq_invitation_id or v_existing.total_amount is distinct from p_total_amount
            or v_existing.currency is distinct from p_currency or v_existing.received_at is distinct from p_received_at
            or v_existing.validity_until is distinct from p_validity_until or v_existing.lead_time_days is distinct from p_lead_time_days
            or v_existing.capture_mode is distinct from p_capture_mode or v_existing.source_message_ref is distinct from p_source_message_ref
            or v_existing.vendor_confirmed is distinct from coalesce(p_vendor_confirmed, false)
            or v_existing.commercial_terms is distinct from coalesce(p_commercial_terms, '{}'::jsonb)
          then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different RFQ response', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise;
  end;

  if p_file_ids is not null and cardinality(p_file_ids) > 0 then
    insert into app.rfq_response_attachments (tenant_id, rfq_response_id, file_id)
    select v_invitation.tenant_id, v_response.id, f
    from unnest(p_file_ids) as f
    on conflict do nothing;
  end if;

  update app.rfq_invitations set status = 'responded' where id = p_rfq_invitation_id;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_rfq_response',
    'app.rfq_responses', v_response.id, 'success', p_late_reason, null, jsonb_build_object('version', v_response.version, 'late_capture', v_response.late_capture)
  );

  return v_response;
end;
$function$;

CREATE OR REPLACE FUNCTION app.update_vendor_bill_match_tolerance_policy_draft(p_policy_id uuid, p_expected_version integer, p_name text, p_quantity_tolerance_pct numeric, p_rate_tolerance_pct numeric, p_tax_tolerance_pct numeric, p_line_amount_tolerance_abs numeric, p_auto_clear_enabled boolean, p_duplicate_window_days integer, p_notes text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.vendor_bill_match_tolerance_policies
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_policy app.vendor_bill_match_tolerance_policies;
begin
  select * into v_policy from app.vendor_bill_match_tolerance_policies where id = p_policy_id for update;
  if not found or not app.has_active_tenant_membership(v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_bill_match_tolerance_policy_not_found: %', p_policy_id using errcode = 'no_data_found';
  end if;

  if not app.check_vendor_bill_match_authority('Edit', v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit for tenant %', p_actor_auth_user_id, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_policy.record_version <> p_expected_version then
    raise exception 'stale_version: tolerance policy % expected version % but found %', p_policy_id, p_expected_version, v_policy.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_policy.status <> 'draft' then
    raise exception 'invalid_transition: tolerance policy % is % and cannot be edited', p_policy_id, v_policy.status
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'reason_required: a non-empty policy name is required' using errcode = 'check_violation';
  end if;

  update app.vendor_bill_match_tolerance_policies
  set name = p_name, quantity_tolerance_pct = coalesce(p_quantity_tolerance_pct, 0), rate_tolerance_pct = coalesce(p_rate_tolerance_pct, 0),
      tax_tolerance_pct = coalesce(p_tax_tolerance_pct, 0), line_amount_tolerance_abs = coalesce(p_line_amount_tolerance_abs, 0),
      auto_clear_enabled = coalesce(p_auto_clear_enabled, false), duplicate_window_days = coalesce(p_duplicate_window_days, 30), notes = p_notes
  where id = p_policy_id and record_version = p_expected_version
  returning * into v_policy;
  if not found then
    raise exception 'stale_version: tolerance policy % target row was concurrently modified (expected version %)', p_policy_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_bill_match_tolerance_policy_draft', 'app.vendor_bill_match_tolerance_policies', v_policy.id, 'success', null, null, '{}'::jsonb);
  return v_policy;
end;
$function$;

CREATE OR REPLACE FUNCTION app.withdraw_rfq_response(p_rfq_response_id uuid, p_reason text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.rfq_responses
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_response app.rfq_responses;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to withdraw a response' using errcode = 'check_violation';
  end if;

  select * into v_response from app.rfq_responses where id = p_rfq_response_id for update;
  if not found or not app.has_active_tenant_membership(v_response.tenant_id, p_actor_auth_user_id) then
    raise exception 'rfq_response_not_found: %', p_rfq_response_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_response.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_response.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_response.record_version <> p_expected_version then
    raise exception 'stale_version: rfq response % expected version % but found %', p_rfq_response_id, p_expected_version, v_response.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_response.status <> 'submitted' then
    raise exception 'invalid_transition: rfq response % is % and cannot be withdrawn', p_rfq_response_id, v_response.status
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.rfq_responses where rfq_invitation_id = v_response.rfq_invitation_id and version > v_response.version) then
    raise exception 'not_latest_response_version: a newer response version exists for this invitation -- withdraw the latest version' using errcode = 'check_violation';
  end if;

  update app.rfq_responses
  set status = 'withdrawn'
  where id = p_rfq_response_id and record_version = p_expected_version
  returning * into v_response;
  if not found then
    raise exception 'stale_version: rfq response % target row was concurrently modified (expected version %)', p_rfq_response_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.rfq_invitations set status = 'invited' where id = v_response.rfq_invitation_id and status = 'responded';

  perform app.capture_audit_event(
    v_response.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_rfq_response',
    'app.rfq_responses', v_response.id, 'success', p_reason, null, jsonb_build_object('status', v_response.status)
  );

  return v_response;
end;
$function$;

