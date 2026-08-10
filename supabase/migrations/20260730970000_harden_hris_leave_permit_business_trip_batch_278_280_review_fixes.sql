-- Tier C batch review-round fix pass, CG-S12-HRT-008 (Prompt 280, Leave,
-- Permit and Business Trip), part of the combined 278-280 batch close.
-- AGENTS.md "never edit an applied migration; add a new migration" --
-- 20260730930000/20260730940000 are already applied and committed, so every
-- fix below is additive (CREATE FUNCTION for genuinely new helpers, CREATE OR
-- REPLACE FUNCTION for existing functions with an identical signature/return
-- shape, DROP POLICY + CREATE POLICY for RLS). One fix (app._transition_
-- employee_leave_status, app.start_employee_leave, app.end_employee_leave)
-- touches functions originally defined in 20260730830000 (HRT-274, Employee
-- Master, an earlier already-VERIFIED batch) -- also via CREATE OR REPLACE,
-- never edited in place, and their EXTERNAL behavior for every existing
-- direct caller is preserved byte-for-byte (same signature, same error
-- messages, same HRS:Edit gate); only a NEW internal engine function is
-- added and the two existing wrappers are refactored to call it, exactly the
-- "one shared engine, entry points differ only in authority bar" shape this
-- same migration's own app._create_leave_request already established.
--
-- Fixes five CONFIRMED, live-reproduced findings from the batch's Tier C
-- review, independently re-derived against a fresh disposable Postgres 16
-- database before this migration was written, per
-- BUILD_EXECUTION_PROTOCOL.md section 5.3:
--
-- 1. HIGH (spec-compliance): a leave-request evidence file was never
--    re-validated after initial creation -- app.update_leave_request_draft
--    wrote p_evidence_file_id straight into the row with zero check, and
--    app.submit_leave_request never referenced evidence_file_id at all, even
--    though this migration's own header (decision 8) explicitly claims
--    "app.submit_leave_request only re-validates tenant/record_type/
--    malware_scan_status". Live-reproduced: a cross-tenant, wrong-record-
--    type, never-scanned file was attached via update_leave_request_draft
--    and reached pending_approval via submit_leave_request with zero error
--    at any step. Fixed by extracting the SAME validation app._create_leave_
--    request already performs into a shared helper (app._validate_leave_
--    evidence_file) and calling it from BOTH update_leave_request_draft
--    (whenever evidence_file_id is set/changed) and submit_leave_request
--    (the actual boundary the build log claims re-validates) -- closing the
--    root cause (validation existed at exactly one of three write paths)
--    rather than only the one reported instance. While already inside
--    submit_leave_request for this fix, also closes the directly adjacent
--    gap the same missing check enabled: a requires_evidence leave type
--    could be drafted with evidence then have it stripped via update (or
--    never supplied on an HR-on-behalf create) and still reach
--    pending_approval, since only app._create_leave_request enforced
--    requires_evidence and only at initial creation.
--
-- 2. MEDIUM (spec-compliance): app.list_leave_requests denied a manager (no
--    HRS:View) even their own direct report's requests whenever an explicit
--    p_employee_id filter was supplied -- the manager-scope disjunct was
--    gated on `p_employee_id IS NULL`, so a real, correctly-related caller
--    got zero rows on the exact call shape (a filtered request) they would
--    most plausibly make. Live-reproduced: mgr1 saw 7 rows unfiltered but 0
--    rows filtered to their own direct report emp1. Fixed by making the
--    manager-of-target check apply regardless of whether p_employee_id is
--    null, matching app.list_attendance_sessions (HRT-278) and app.list_
--    schedule_assignments (HRT-279) exactly, and app.list_employee_leave_
--    balances (this same migration) which already got this right.
--
-- 3. HIGH (self-scoping-raw-table-overexposure, the SAME shape as HRT-278's
--    and HRT-279's own findings this batch's Tier C already fixed in
--    20260730950000/20260730960000): app.leave_requests and app.leave_
--    balance_ledger had a tenant-membership-only RLS SELECT policy -- a
--    tenant member with zero HRS permission and no linked employee row could
--    read the entire tenant's leave/permit/business-trip calendar and
--    balance ledger via a raw SELECT, live-reproduced (real dates, leave
--    types, statuses, and ledger postings for a specific employee's medical
--    leave and a business trip destination visible with zero authority).
--    Fixed by reusing app.can_view_hris_person_scoped_row (new in
--    20260730950000, this same batch's HRT-278 fix).
--
-- 4. CRITICAL (correctness-authority-bar-mismatch): app.decide_leave_request
--    and app.cancel_leave_request delegated employee lifecycle-status sync
--    (start_employee_leave/end_employee_leave) using the CALLING actor's own
--    authority, but those two functions hard-require HRS:Edit internally --
--    breaking BOTH the core approve path for a correctly-scoped least-
--    privilege approver (Approve/View/Override, no Edit -- this repository's
--    own established approver shape) AND the core self-cancel path for an
--    ordinary employee (zero HRS grants by design, decision 10) whenever the
--    leave being decided covers today. Live-reproduced both directions
--    end-to-end: an Approve/Override-only approver was rejected approving a
--    same-day leave with the WHOLE decision (including the approval step
--    itself) rolled back; a plain employee self-cancelling their own
--    already-started approved leave was rejected the same way, with no
--    cancellation recorded and no credit reversal posted. Root cause: app.
--    start_employee_leave/app.end_employee_leave (HRT-274) hard-require
--    HRS:Edit unconditionally, correct for their OWN direct HR-initiated
--    callers but wrong for a caller whose authority was already established
--    by a DIFFERENT, already-sufficient mechanism (PLT-123 approval-step
--    eligibility, or the self-service invariant). Fixed by extracting the
--    shared lock+transition+event+audit engine into a new internal function,
--    app._transition_employee_leave_status (no authority check of its own --
--    callers are responsible for having already established sufficient
--    authority, exactly this migration''s own app._create_leave_request
--    convention), refactoring app.start_employee_leave/app.end_employee_
--    leave into thin HRS:Edit-gated wrappers around it (zero behavior change
--    for their existing direct callers), and having app.decide_leave_request/
--    app.cancel_leave_request call the new internal engine directly instead
--    of the HRS:Edit-gated wrappers.
--
-- 5. HIGH (data-consistency-integration-boundary): approving a leave request
--    never re-ran attendance exception detection for the day(s) it covers --
--    an attendance exception recorded BEFORE a same-day/backdated leave
--    approval was never retroactively suppressed, leaving a stale, open
--    exception alongside an approved leave. Live-reproduced: a real 'late'
--    exception recorded from a real clock-in stayed status='open' after a
--    full_day leave covering the same day was subsequently approved -- the
--    FORWARD direction (leave approved before the clock-in) was already
--    correctly suppressed and tested (20260730940000); the reverse ordering
--    was not. Fixed by calling the existing app._recalculate_session_
--    exceptions (20260730940000, already leave-aware, service_role-only, no
--    redundant permission re-check -- avoiding the identical authority-bar-
--    mismatch class fixed in item 4 above) for every attendance_sessions row
--    that exists in the decided request''s own date range, on BOTH the
--    approve path (decide_leave_request) and the reverse direction the same
--    root cause implies -- a previously-approved, exception-suppressing
--    leave being cancelled (cancel_leave_request) should let a genuine
--    exception reappear on recalculation, not stay silently suppressed
--    forever.

-- ===========================================================================
-- Fix 3: self/manager/HRS:View RLS scoping (finding "self-scoping-raw-table-
-- overexposure", HIGH).
-- ===========================================================================

drop policy if exists leave_requests_select_scoped on app.leave_requests;
create policy leave_requests_select_scoped on app.leave_requests
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.can_view_hris_person_scoped_row(tenant_id, employee_id)
    )
  );

drop policy if exists leave_balance_ledger_select_scoped on app.leave_balance_ledger;
create policy leave_balance_ledger_select_scoped on app.leave_balance_ledger
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.can_view_hris_person_scoped_row(tenant_id, employee_id)
    )
  );

-- ===========================================================================
-- Fix 1: shared evidence-file re-validation (spec-compliance, HIGH).
-- ===========================================================================

create function app._validate_leave_evidence_file(p_tenant_id uuid, p_evidence_file_id uuid)
returns void
language plpgsql
set search_path = app, pg_temp
as $$
declare
  v_file app.files;
begin
  if p_evidence_file_id is null then
    return;
  end if;
  select * into v_file from app.files where id = p_evidence_file_id;
  if not found or v_file.tenant_id <> p_tenant_id or v_file.record_type <> 'leave_request' then
    raise exception 'evidence_file_not_found: file % is not a valid evidence file', p_evidence_file_id using errcode = 'no_data_found';
  end if;
  if v_file.malware_scan_status = 'infected' then
    raise exception 'evidence_file_infected: file % failed malware scanning and cannot be attached', p_evidence_file_id using errcode = 'check_violation';
  end if;
  if v_file.malware_scan_status <> 'clean' then
    raise exception 'evidence_file_not_scanned: file % has not cleared malware scanning (status %)', p_evidence_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;
end;
$$;

comment on function app._validate_leave_evidence_file is
  'Batch 278-280 Tier C fix (spec-compliance, HIGH, live-reproduced): the exact same PLT-128 tenant/record_type/malware_scan_status re-validation app._create_leave_request already performs at creation time (20260730930000 lines 825-838), extracted so app.update_leave_request_draft and app.submit_leave_request can both apply it too -- previously only the creation path validated at all, so a cross-tenant/wrong-record-type/unscanned file attached via update_leave_request_draft reached pending_approval with zero check.';

-- Called from within already-SECURITY DEFINER callers only; no grant to
-- authenticated needed (mirrors every other "_"-prefixed internal helper in
-- this migration, e.g. app._compute_leave_business_units).
-- Every prior migration's own established convention (e.g. 20260730900000,
-- 20260730930000; see 20260730950000's identical fix in this same batch for
-- the full rationale): a brand-new function otherwise retains an implicit
-- PUBLIC EXECUTE grant the moment any explicit GRANT statement first
-- materializes its ACL -- this blanket revoke is the actual operative
-- mechanism, run once here to also cover app._transition_employee_leave_
-- status and its own wrapper CREATE OR REPLACEs further below.
revoke execute on all functions in schema app from public;

grant execute on function app._validate_leave_evidence_file(uuid, uuid) to service_role;

create or replace function app.update_leave_request_draft(
  p_request_id uuid, p_expected_version integer, p_date_from date, p_date_to date, p_day_portion text,
  p_reason text, p_destination text, p_evidence_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.leave_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.leave_requests;
  v_self app.employees;
  v_is_self boolean;
  v_decision app.rbac_decision;
  v_type app.leave_types;
  v_policy app.leave_type_policy_versions;
  v_units numeric;
  v_employee app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_request from app.leave_requests where id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'leave_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_request.employee_id;
  if not v_is_self then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: leave request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'draft' then
    raise exception 'invalid_transition: leave request % is %, only a draft may be edited', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = v_request.employee_id;
  select * into v_type from app.leave_types where id = v_request.leave_type_id and tenant_id = v_request.tenant_id and status = 'published';
  if not found then
    raise exception 'leave_type_not_available: % is not a published leave type in this tenant', v_request.leave_type_id using errcode = 'no_data_found';
  end if;
  select * into v_policy from app.resolve_effective_leave_type_policy_version(v_request.tenant_id, v_request.leave_type_id, v_employee.branch_org_unit_id, p_date_from) limit 1;
  if not found then
    raise exception 'no_eligible_policy: no published leave policy is effective for leave type % as of %', v_request.leave_type_id, p_date_from
      using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if v_type.category <> 'business_trip' and p_destination is not null then
    raise exception 'destination_not_applicable: destination may only be set for a business_trip leave type' using errcode = 'check_violation';
  end if;

  -- Batch 278-280 Tier C fix (spec-compliance, HIGH, live-reproduced): the
  -- SAME tenant/record_type/malware_scan_status re-validation app._create_
  -- leave_request already applies at creation -- previously this function
  -- wrote p_evidence_file_id straight into the row with zero check, the
  -- exact live-exploited gap (a cross-tenant, wrong-record-type,
  -- never-scanned file was accepted here and reached submit unchanged).
  perform app._validate_leave_evidence_file(v_request.tenant_id, p_evidence_file_id);

  v_units := app._compute_leave_business_units(v_request.tenant_id, v_employee.branch_org_unit_id, p_date_from, p_date_to, p_day_portion);

  update app.leave_requests
  set date_from = p_date_from, date_to = p_date_to, day_portion = p_day_portion, total_units = v_units,
      reason = p_reason, destination = p_destination, evidence_file_id = p_evidence_file_id, policy_version_id = v_policy.id
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: leave request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_leave_request_draft',
    'app.leave_requests', v_request.id, 'success', null, null, app.leave_request_audit_projection(v_request)
  );

  return v_request;
end;
$$;

comment on function app.update_leave_request_draft is
  'HRT-280 (section 22 "revision/resubmission"): editing is bounded to status=draft ONLY -- a rejected request returns to draft (app.decide_leave_request''s own reject branch) precisely so it can be edited here and resubmitted, mirroring app.request_employee_change''s own governed-correction shape. Batch 278-280 Tier C fix (spec-compliance, HIGH): p_evidence_file_id is now re-validated (tenant/record_type/malware_scan_status) via app._validate_leave_evidence_file before being written.';

create or replace function app.submit_leave_request(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.leave_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.leave_requests;
  v_self app.employees;
  v_is_self boolean;
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_type app.leave_types;
  v_policy app.leave_type_policy_versions;
  v_approval_config_version_id uuid;
  v_approval_request app.approval_requests;
  v_snapshot jsonb := '[]'::jsonb;
  v_day date;
  v_assignment app.schedule_assignments;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_request from app.leave_requests where id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'leave_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_request.employee_id;
  if not v_is_self then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: leave request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'draft' then
    raise exception 'invalid_transition: leave request % is %, only a draft may be submitted', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = v_request.employee_id;
  select * into v_policy from app.leave_type_policy_versions where id = v_request.policy_version_id;
  select * into v_type from app.leave_types where id = v_request.leave_type_id;

  -- Batch 278-280 Tier C fix (spec-compliance, HIGH, live-reproduced): this
  -- migration's own header (decision 8) already claimed submit_leave_request
  -- "only re-validates tenant/record_type/malware_scan_status" -- it never
  -- actually did. Now the authoritative gate before pending_approval: a
  -- requires_evidence type must still carry evidence at submit time (closes
  -- the adjacent gap where evidence attached at draft time could be stripped
  -- via update_leave_request_draft, or never supplied by an HR-on-behalf
  -- create, and still reach approval), and any attached file is re-validated
  -- exactly as app._create_leave_request validates it at creation.
  if v_type.requires_evidence and v_request.evidence_file_id is null then
    raise exception 'evidence_required: leave type % requires supporting evidence', v_type.code using errcode = 'check_violation';
  end if;
  perform app._validate_leave_evidence_file(v_request.tenant_id, v_request.evidence_file_id);

  if v_policy.min_notice_days > 0 and v_request.date_from < (current_date + v_policy.min_notice_days) then
    raise exception 'min_notice_not_met: leave type requires at least % day(s) advance notice', v_policy.min_notice_days using errcode = 'check_violation';
  end if;
  if v_policy.eligibility_min_tenure_days > 0 and v_employee.hire_date is not null
     and (current_date - v_employee.hire_date) < v_policy.eligibility_min_tenure_days then
    raise exception 'eligibility_not_met: employee has not met the % day minimum tenure required by this leave policy', v_policy.eligibility_min_tenure_days
      using errcode = 'check_violation';
  end if;

  v_day := v_request.date_from;
  while v_day <= v_request.date_to loop
    select * into v_assignment from app.resolve_effective_schedule_assignment(v_request.tenant_id, v_request.employee_id, v_day);
    if found then
      v_snapshot := v_snapshot || jsonb_build_object('work_date', v_day, 'schedule_assignment_id', v_assignment.id, 'shift_template_version_id', v_assignment.shift_template_version_id);
    end if;
    v_day := v_day + 1;
  end loop;

  select cv.id into v_approval_config_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = 'approval' and co.tenant_id = v_request.tenant_id and co.scope_level = 'tenant' and cv.status = 'published';
  if v_approval_config_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % has no published approval routing definition', v_request.tenant_id
      using errcode = 'check_violation';
  end if;

  v_approval_request := app.request_approval(
    v_approval_config_version_id, v_request.tenant_id, 'leave_request', p_request_id,
    p_request_id::text || ':submit:' || p_expected_version::text, p_actor_auth_user_id, p_actor_label
  );

  begin
    update app.leave_requests
    set status = 'pending_approval', approval_request_id = v_approval_request.id, schedule_snapshot = v_snapshot
    where id = p_request_id and record_version = p_expected_version
    returning * into v_request;
  exception
    when exclusion_violation then
      raise exception 'leave_request_overlap: employee % already has a pending or approved leave/permit/business-trip request overlapping this date range', v_request.employee_id
        using errcode = 'check_violation';
    when deadlock_detected then
      raise exception 'leave_request_overlap: a concurrent decision on an overlapping request could not be serialized -- retry'
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: leave request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_leave_request',
    'app.leave_requests', v_request.id, 'success', null, null, app.leave_request_audit_projection(v_request)
  );

  return v_request;
end;
$$;

comment on function app.submit_leave_request is
  'HRT-280 (decision 5/6): the EXCLUDE-constraint overlap check fires HERE (the draft->pending_approval transition), never at draft creation -- a draft never blocks another request. Routes through PLT-123 exactly like app.submit_onboarding_case_for_finalize_approval (HRT-277) -- raises the SAME approval_definition_not_configured error when the tenant has not configured approval routing, disclosed, never silently bypassed. Batch 278-280 Tier C fix (spec-compliance, HIGH): now the ACTUAL authoritative re-validation boundary the original header already claimed it was -- requires_evidence is enforced and any attached evidence_file_id is re-validated (tenant/record_type/malware_scan_status) via app._validate_leave_evidence_file.';

-- ===========================================================================
-- Fix 2: app.list_leave_requests manager-of-target scoping under an explicit
-- p_employee_id filter (spec-compliance, MEDIUM).
-- ===========================================================================

create or replace function app.list_leave_requests(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid default null, p_status text default null,
  p_from_date date default null, p_to_date date default null, p_limit integer default 50, p_after_id uuid default null
)
returns table (
  id uuid, employee_id uuid, employee_name text, leave_type_id uuid, leave_type_code text, category text,
  status text, date_from date, date_to date, day_portion text, total_units numeric, payroll_input_status text, record_version integer,
  reason_visible boolean, reason text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_has_view boolean;
  v_has_personal boolean;
  v_bounded_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View')).allowed;
  v_has_personal := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View personal data')).allowed;
  v_bounded_limit := least(coalesce(p_limit, 50), 200);

  return query
  select r.id, r.employee_id, e.full_name, r.leave_type_id, t.code, t.category, r.status, r.date_from, r.date_to,
         r.day_portion, r.total_units, r.payroll_input_status, r.record_version,
         (r.employee_id = v_self.master_record_id or v_has_personal) as reason_visible,
         case when r.employee_id = v_self.master_record_id or v_has_personal then r.reason else null end
  from app.leave_requests r
  join app.employees e on e.master_record_id = r.employee_id
  join app.leave_types t on t.id = r.leave_type_id
  where r.tenant_id = p_tenant_id
    and (p_status is null or r.status = p_status)
    and (p_from_date is null or r.date_to >= p_from_date)
    and (p_to_date is null or r.date_from <= p_to_date)
    and (p_after_id is null or r.id > p_after_id)
    and (
      v_has_view
      or r.employee_id = v_self.master_record_id
      or e.manager_employee_id = v_self.master_record_id
    )
    and (p_employee_id is null or r.employee_id = p_employee_id)
  order by r.id
  limit v_bounded_limit;
end;
$$;

comment on function app.list_leave_requests is
  'HRT-280 (section 16/26): self rows always visible; a manager with no HRS:View sees their own direct reports'' rows; an HRS:View holder sees the whole tenant. reason is nulled unless the caller is the requester themself or holds HRS:View personal data (section 16 "managers see... only necessary reason"). Batch 278-280 Tier C fix (spec-compliance, MEDIUM, live-reproduced): the manager-of-target check previously only applied when p_employee_id was null, so a manager filtering to their own real direct report''s requests got zero rows -- fixed by applying the manager check unconditionally (matches app.list_attendance_sessions/HRT-278 and app.list_schedule_assignments/HRT-279, and this migration''s own app.list_employee_leave_balances, which already got this right), then narrowing by p_employee_id afterward exactly as before.';

-- ===========================================================================
-- Fix 4: authority-bar-mismatch on employee lifecycle sync (correctness,
-- CRITICAL). New shared internal engine (no authority check of its own --
-- callers must have already established sufficient authority), refactors
-- app.start_employee_leave/app.end_employee_leave (HRT-274,
-- 20260730830000) into thin wrappers around it with IDENTICAL external
-- behavior, then app.decide_leave_request/app.cancel_leave_request call the
-- engine directly instead of the HRS:Edit-gated wrappers.
-- ===========================================================================

create function app._transition_employee_leave_status(
  p_master_record_id uuid, p_expected_version integer, p_to_status text, p_reason text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
  v_from_status text;
begin
  if p_to_status not in ('on_leave', 'active') then
    raise exception 'invalid_leave_transition_target: % is not a supported leave lifecycle target', p_to_status using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  v_from_status := v_employee.lifecycle_status;
  if p_to_status = 'on_leave' then
    if v_from_status <> 'active' then
      raise exception 'invalid_transition: employee % is % and cannot start leave', p_master_record_id, v_from_status using errcode = 'check_violation';
    end if;
    update app.employees set lifecycle_status = 'on_leave', leave_reason = p_reason
    where master_record_id = p_master_record_id and record_version = p_expected_version
    returning * into v_employee;
  else
    if v_from_status <> 'on_leave' then
      raise exception 'invalid_transition: employee % is % and cannot end leave', p_master_record_id, v_from_status using errcode = 'check_violation';
    end if;
    update app.employees set lifecycle_status = 'active', leave_reason = null
    where master_record_id = p_master_record_id and record_version = p_expected_version
    returning * into v_employee;
  end if;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, v_from_status, p_to_status, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label,
    case when p_to_status = 'on_leave' then 'start_employee_leave' else 'end_employee_leave' end,
    'app.employees', p_master_record_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

comment on function app._transition_employee_leave_status is
  'Batch 278-280 Tier C fix (correctness-authority-bar-mismatch, CRITICAL, live-reproduced): the shared employee-leave-lifecycle lock+transition+event+audit engine, extracted from app.start_employee_leave/app.end_employee_leave (HRT-274) -- deliberately carries NO authority check of its own, mirroring app._create_leave_request''s own "shared engine, entry points differ only in authority bar" convention. app.start_employee_leave/app.end_employee_leave remain the HRS:Edit-gated direct-call entry points (unchanged external behavior); app.decide_leave_request/app.cancel_leave_request (HRT-280) call this engine directly, since their OWN authority (PLT-123 eligible-approver identity, or the self-service invariant) was already established before ever reaching this transition and must not be re-tested against an unrelated, sometimes-absent HRS:Edit grant.';

-- Re-run for the same reason as the earlier revoke in this migration (this
-- function did not exist yet when that one ran) -- a blanket, idempotent
-- statement, safe to repeat.
revoke execute on all functions in schema app from public;

grant execute on function app._transition_employee_leave_status(uuid, integer, text, text, uuid, text) to service_role;

create or replace function app.start_employee_leave(
  p_master_record_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.employees where master_record_id = p_master_record_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app._transition_employee_leave_status(p_master_record_id, p_expected_version, 'on_leave', p_reason, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.start_employee_leave is
  'HRT-274 (decision 6): a coarse, HR-set lifecycle state only -- accrual/balance/multi-day-request leave workflow is Prompt 280''s own chartered scope, not built here. Batch 278-280 Tier C fix (correctness-authority-bar-mismatch, CRITICAL): refactored into a thin HRS:Edit-gated wrapper around the new app._transition_employee_leave_status shared engine -- external behavior (signature, HRS:Edit requirement, every error message) is unchanged for this function''s own direct callers; only app.decide_leave_request (HRT-280) now bypasses this wrapper to call the shared engine directly, since it already established its own sufficient authority via PLT-123 before ever reaching this transition.';

create or replace function app.end_employee_leave(
  p_master_record_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.employees where master_record_id = p_master_record_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app._transition_employee_leave_status(p_master_record_id, p_expected_version, 'active', null, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.end_employee_leave is
  'HRT-274: ends an ''on_leave'' lifecycle state, returning the employee to ''active''. Batch 278-280 Tier C fix (correctness-authority-bar-mismatch, CRITICAL): refactored into a thin HRS:Edit-gated wrapper around the new app._transition_employee_leave_status shared engine -- external behavior is unchanged for this function''s own direct callers; only app.cancel_leave_request (HRT-280) now bypasses this wrapper to call the shared engine directly, since a self-cancelling employee (decision 10 -- zero HRS grants by design) or a non-self Override-holding canceller already established sufficient authority before ever reaching this transition.';

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

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_leave_request',
    'app.leave_requests', v_request.id, 'success', p_reason, null, app.leave_request_audit_projection(v_request)
  );

  return v_request;
end;
$$;

comment on function app.decide_leave_request is
  'HRT-280 (decision 4/9): no domain permission gate of its own for the ordinary approve/reject path -- app.decide_approval_step already gates on tenant membership + eligible-approver identity + C-18 self-approval block (mirrors app.decide_onboarding_case_finalize_approval, HRT-277). The coverage-override branch is the one place this function DOES gate directly (HRS:Override), since overriding a coverage block is a real, separate authority decision from ordinary leave approval. A rejected request returns to draft (section 22 "revision/resubmission"), letting the employee address the rejection reason and resubmit. Batch 278-280 Tier C fix (CRITICAL + HIGH, live-reproduced): the employee-lifecycle sync now calls the internal app._transition_employee_leave_status engine directly instead of the HRS:Edit-gated app.start_employee_leave (a correctly-scoped Approve/Override-only approver was previously rejected outright, rolling back the whole decision); the approve branch now also re-runs app._recalculate_session_exceptions for every existing session in the approved date range, so a same-day/backdated approval retroactively suppresses an already-recorded exception instead of leaving it stale.';

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

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_leave_request',
    'app.leave_requests', v_request.id, 'success', p_reason, null, app.leave_request_audit_projection(v_request)
  );

  return v_request;
end;
$$;

comment on function app.cancel_leave_request is
  'HRT-280 (decision 7, mandatory reading item 4/8): genuinely cancels any in-flight PLT-123 approval request before cascading (the exact class independently found and fixed in HRT-276 AND HRT-277). Section 22''s own "future cancellation" -- an approved request whose date_from is still in the future, or already in progress today, may be self-cancelled; an already-completed past leave cannot be (no meaningful compensating event exists for time already taken). Batch 278-280 Tier C fix (CRITICAL + HIGH, live-reproduced): the employee-lifecycle sync now calls the internal app._transition_employee_leave_status engine directly instead of the HRS:Edit-gated app.end_employee_leave (a self-cancelling employee with zero HRS grants was previously rejected outright); a previously-approved request being cancelled now also re-runs app._recalculate_session_exceptions for every existing session in its own date range, letting a genuinely open exception reappear instead of staying permanently suppressed.';
