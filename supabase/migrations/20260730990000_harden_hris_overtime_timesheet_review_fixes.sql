-- Tier C batch review-round fix pass, CG-S12-HRT-009 (Prompt 281, Overtime
-- and Timesheet). AGENTS.md "never edit an applied migration; add a new
-- migration" -- 20260730980000 is already applied and committed, so every
-- fix below is additive (CREATE OR REPLACE FUNCTION for an existing
-- function with an identical signature/return shape, CREATE FUNCTION for
-- the one genuinely new helper, ALTER TABLE ... DROP/ADD CONSTRAINT for two
-- CHECK-constraint widenings), exactly as 20260730950000/960000/970000
-- already established for the sibling 278-280 batch's own Tier C fix pass.
--
-- Fixes six CONFIRMED, independently live-reproduced findings from this
-- batch's Tier C review (spec-compliance lens, security/RLS lens,
-- correctness/concurrency lens, cross-prompt integration lens), each
-- re-derived against a fresh disposable Postgres 16 database with real
-- forged-JWT sessions before this migration was written, per
-- docs/standards/BUILD_EXECUTION_PROTOCOL.md section 5.3 -- never accepted
-- from a lens's own citation alone:
--
-- 1. CRITICAL (spec-compliance + correctness, duplicate finding from both
--    lenses): app._create_overtime_request/app._create_timesheet_entry
--    never queried app.leave_requests at all -- an employee with an
--    APPROVED leave request covering a date could still have an overtime
--    request or timesheet entry created (and later approved) for that same
--    date, live-reproduced end to end with zero error, contradicting spec
--    section 23/25's explicit "block schedule/leave overlap" requirement.
--    Fixed by adding a read-only app.leave_requests (HRT-280) overlap check
--    to both internal engines -- reused directly, exactly like this
--    migration's own established read-only reuse of app.attendance_
--    sessions/app.roster_holidays/app.schedule_assignments, never a second
--    leave calendar.
--
-- 2. HIGH (correctness, recurring ambiguous-bare-column class this
--    repository's own taxonomy repeatedly tracks -- already hit and fixed
--    at HRT-274 (3x), HRT-275, HRT-276, HRT-278, and this migration's own
--    header comment at line 3019-3022 explicitly claims to guard against
--    it): all four cursor-paginated list RPCs (app.list_my_overtime_
--    requests, app.list_overtime_requests, app.list_my_timesheet_entries,
--    app.list_timesheet_entries) declare a RETURNS TABLE output column
--    named `id`, which becomes an implicit PL/pgSQL variable in scope for
--    the whole function body; each function's own `p_after_id` cursor
--    lookup ran `select * into v_after from app.<table> where id =
--    p_after_id` -- a bare, unqualified `id` reference that collides with
--    that output variable, live-reproduced raising a hard `column
--    reference "id" is ambiguous` on the FIRST real call with a non-null
--    cursor (i.e. the first time pagination is actually used past a
--    tenant's initial default page). Fixed by aliasing the source table in
--    each offending lookup, mirroring the alias-qualified style every
--    OTHER query in this same migration already uses.
--
-- 3. HIGH (correctness, C-01 idempotency): app._create_overtime_request/
--    app._create_timesheet_entry's own full-tuple idempotency-replay
--    comparison (the exact discipline both functions' own inline comments
--    claim: "compare the COMPLETE request, never the key alone") omitted
--    `unpaid_break_minutes` from the compared tuple -- live-reproduced: a
--    retry with the SAME idempotency key but a materially different
--    `unpaid_break_minutes` silently returned the FIRST attempt's row
--    unchanged, with no `idempotency_key_conflict` and no signal the
--    caller's correction never took effect. Fixed by adding `unpaid_break_
--    minutes` to both functions' own replay-tuple comparison.
--
-- 4. HIGH (correctness, contradicts this migration's own decision 10 "a
--    locked period changes ONLY through a governed reopen, never a silent
--    overwrite"): app.submit_overtime_request/app.decide_overtime_request/
--    app.submit_timesheet_entry/app.decide_timesheet_entry all correctly
--    call app.is_timesheet_period_locked before mutating, but app.cancel_
--    overtime_request/app.cancel_timesheet_entry never did -- only guarding
--    against `payroll_input_status = 'approved'`, a distinct and narrower
--    condition. Live-reproduced with a real control check (a fresh submit
--    into the SAME locked period correctly failed with `timesheet_period_
--    locked`) immediately followed by the exploit (the self-requester, with
--    ZERO HRS permission, successfully cancelled their own already-APPROVED,
--    payroll-pending overtime request inside that SAME locked period, no
--    error, no reopen workflow involved). Fixed by adding the identical
--    lock-gate check to both cancel functions, in the same relative
--    position (after the payroll-input-status guard, before the terminal
--    UPDATE), mirroring submit/decide's own established shape exactly.
--
-- 5. HIGH (security/C-07, live regression of a class the immediately
--    preceding capability, HRT-280, explicitly fixed one migration earlier
--    for the identical reason -- app.leave_request_audit_projection,
--    20260730930000:462, "an explicit non-PII/non-reason jsonb_build_
--    object projection -- never to_jsonb(row), which would carry reason/
--    destination unmasked into app.audit_logs"): app.submit_timesheet_
--    period_summary/app.approve_timesheet_period_summary captured `to_
--    jsonb(v_summary)` directly into `app.audit_logs.after_value`, carrying
--    `decided_reason`/`last_reopen_reason` unmasked (neither key name
--    matches app.redact_audit_payload's fixed sensitive-key-name pattern);
--    eight further call sites (app.decide_overtime_request, app.cancel_
--    overtime_request, app.decide_timesheet_entry, app.cancel_timesheet_
--    entry, app.approve_timesheet_period_summary, app.reject_timesheet_
--    period_summary, app.reopen_timesheet_period, app.reopen_timesheet_
--    period_summary) routed the entity's own decided/cancel/reopen reason
--    text straight into `capture_audit_event`'s unredacted `p_reason` ->
--    `app.audit_logs.reason` column, which is never passed through app.
--    redact_audit_payload at all (that function only ever processes the
--    jsonb before/after columns). Both paths are read via app.query_audit_
--    logs/app.export_audit_logs (PLT-116), gated only by Supreme Admin OR
--    ANY active tenant_admin -- not `HRS:View`, not `HRS:View personal
--    data`, not self, not the direct manager. Live-reproduced end to end: a
--    zero-HRS-permission tenant_admin was correctly denied the SAME data on
--    every legitimate read path (raw SELECT, app.get_overtime_request_
--    detail, app.get_timesheet_period_summary all returned zero rows), yet
--    the exact same actor read real decided_reason/cancel_reason/last_
--    reopen_reason free text for genuine HR decisions straight out of the
--    audit trail. Fixed by (a) adding a masked, explicit-column app.
--    timesheet_period_summary_audit_projection helper mirroring app.leave_
--    request_audit_projection's own established shape exactly, replacing
--    both to_jsonb(v_summary) call sites, and (b) no longer routing any of
--    the eight sites' own decided/cancel/reopen reason text into capture_
--    audit_event's p_reason argument (passed as null instead -- the
--    action/resource/result/actor/timestamp evidence is still fully
--    captured; only the free-text business-sensitive reason value, which
--    remains fully readable through each entity's own governed, permission-
--    scoped read RPC, is withheld from the broadly-accessible audit-log
--    surface).
--
-- 6. HIGH (cross-prompt integration): app.reopen_timesheet_period_summary
--    reverts an approved summary to `pending` and resets its contributing
--    app.timesheet_entries/app.overtime_requests rows' `payroll_input_
--    status` back to `pending`, but never touched the already-generated
--    app.payroll_time_inputs row for that (period, employee) -- live-
--    reproduced: immediately after a governed reopen (before any re-
--    generate), app.get_payroll_time_input/app.list_payroll_time_inputs --
--    the actual read RPCs Prompt 282 (Payroll) is expected to consume --
--    both still returned that row as `status='active'` with the STALE,
--    pre-correction totals, with zero signal the underlying summary had
--    been reopened and was no longer approved. This directly threatens the
--    "ONE versioned, idempotent payroll-input handoff" contract this
--    migration's own header claims to guarantee. Fixed by (a) widening
--    app.payroll_time_inputs.status's own CHECK constraint to add a third
--    value, 'stale' (distinct from 'superseded', which specifically means
--    "a newer, already-generated version exists and is linked via
--    superseded_by_id"), (b) app.reopen_timesheet_period_summary now flips
--    any existing 'active' payroll_time_inputs row for that (period,
--    employee) to 'stale' at reopen time -- the exact "supersede/invalidate
--    at the moment truth changes" discipline this same migration already
--    applies correctly inside app._generate_payroll_time_input itself, and
--    (c) app._generate_payroll_time_input's own active-row lookup now
--    considers both 'active' and 'stale' as "the prior version to compare
--    against," restoring a content-unchanged 'stale' row directly back to
--    'active' (no redundant new version) rather than ever returning a
--    'stale'-labelled row as if it were the freshly-generated result.
--
-- Two further CONFIRMED findings are fixed as cheap, in-scope, low-risk
-- additions in this same migration (not separately numbered above since
-- neither is Critical/High):
--
-- * LOW (spec-compliance/C-15): app.timesheet_period_summaries.entry_count/
--   overtime_request_count carried no non-negativity CHECK, unlike every
--   sibling numeric column on this table (the existing minutes_nonneg_check
--   covers only the four minutes columns). Currently unreachable via any
--   write path (app._compute_timesheet_period_summary always sets both from
--   `count(*)`, which cannot be negative) -- a genuine defense-in-depth gap,
--   not a live bug, closed here for completeness.
--
-- Every other CONFIRMED-but-not-fixed-here finding, and every disposition
-- (already-fixed / rejected-with-reason / disclosed), is recorded in
-- docs/build-log/phase-07/HRT-281.md section 12 and, where Critical/High and
-- disclosed rather than fixed, in docs/runtime/KNOWN_ISSUES.md, per section
-- 5.6 -- no Critical/High finding is left open uncontained.

-- ===========================================================================
-- Fix 1 (part A): app.timesheet_period_summary_audit_projection -- the new
-- masked projection helper Fix 5 needs, mirroring app.leave_request_audit_
-- projection (HRT-280, 20260730930000:462) exactly: an explicit, non-reason
-- jsonb_build_object projection, never to_jsonb(row).
-- ===========================================================================

create function app.timesheet_period_summary_audit_projection(p_summary app.timesheet_period_summaries)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_summary.id, 'tenant_id', p_summary.tenant_id, 'employee_id', p_summary.employee_id,
    'timesheet_period_id', p_summary.timesheet_period_id, 'status', p_summary.status,
    'total_regular_minutes', p_summary.total_regular_minutes, 'total_overtime_weekday_minutes', p_summary.total_overtime_weekday_minutes,
    'total_overtime_weekend_minutes', p_summary.total_overtime_weekend_minutes, 'total_overtime_holiday_minutes', p_summary.total_overtime_holiday_minutes,
    'entry_count', p_summary.entry_count, 'overtime_request_count', p_summary.overtime_request_count,
    'record_version', p_summary.record_version
  );
$$;

comment on function app.timesheet_period_summary_audit_projection is
  'HRT-281 Tier C fix (C-07): an explicit non-PII/non-reason jsonb_build_object projection -- never to_jsonb(row), which would carry decided_reason/last_reopen_reason unmasked into app.audit_logs, mirroring app.leave_request_audit_projection (HRT-280) exactly.';

grant execute on function app.timesheet_period_summary_audit_projection(app.timesheet_period_summaries) to authenticated, service_role;

-- ===========================================================================
-- Fix 1 (part B) + Fix 3: app._create_overtime_request -- leave-overlap
-- block (Finding 1, CRITICAL) and full-tuple idempotency including
-- unpaid_break_minutes (Finding 3, HIGH). Identical signature/return type
-- to the original, so CREATE OR REPLACE keeps every existing grant intact.
-- ===========================================================================

create or replace function app._create_overtime_request(
  p_employee app.employees,
  p_request_type text,
  p_requested_start_at timestamptz,
  p_requested_end_at timestamptz,
  p_unpaid_break_minutes integer,
  p_reason text,
  p_schedule_assignment_id uuid,
  p_job_order_id uuid,
  p_shipment_order_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.overtime_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.overtime_requests;
  v_work_date date;
  v_policy app.overtime_policy_versions;
  v_request app.overtime_requests;
begin
  if p_employee.master_record_id is null then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;
  if p_employee.lifecycle_status not in ('active', 'on_leave') then
    raise exception 'employee_not_active: employee % is %, only an active employee may request overtime', p_employee.master_record_id, p_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  if p_request_type not in ('planned', 'emergency_after_the_fact') then
    raise exception 'invalid_request_type: % is not planned or emergency_after_the_fact', p_request_type using errcode = 'check_violation';
  end if;
  if p_requested_start_at is null or p_requested_end_at is null or p_requested_end_at <= p_requested_start_at then
    raise exception 'invalid_time_range: requested_end_at must be after requested_start_at' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request overtime' using errcode = 'check_violation';
  end if;
  if coalesce(p_unpaid_break_minutes, 0) < 0 then
    raise exception 'invalid_break_minutes: unpaid_break_minutes must not be negative' using errcode = 'check_violation';
  end if;

  -- C-01: full-tuple idempotency replay -- compare the COMPLETE request,
  -- never the key alone. Tier C fix (Finding 3, HIGH): unpaid_break_minutes
  -- is now part of the compared tuple -- it was omitted originally, so a
  -- same-key retry with a genuinely different break correction silently
  -- returned the FIRST attempt's row unchanged instead of either applying
  -- the correction or raising idempotency_key_conflict.
  if p_idempotency_key is not null then
    select * into v_existing from app.overtime_requests where tenant_id = p_employee.tenant_id and employee_id = p_employee.master_record_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.request_type = p_request_type and v_existing.requested_start_at = p_requested_start_at and v_existing.requested_end_at = p_requested_end_at
         and v_existing.unpaid_break_minutes = coalesce(p_unpaid_break_minutes, 0) then
        return v_existing;
      else
        -- C-02 (self-found, live-reproduced by this checkpoint's own db-test
        -- run): deliberately NOT errcode='unique_violation' -- this
        -- function's own trailing `exception when unique_violation` handler
        -- (guarding the terminal INSERT's real active-slot race) would
        -- otherwise swallow this deliberate guard and re-report it as a
        -- misleading overtime_request_conflict, exactly the recurring class
        -- docs/standards/RECURRING_DEFECT_TAXONOMY.md C-02 describes.
        raise exception 'idempotency_key_conflict: key % was already used for a different overtime request', p_idempotency_key
          using errcode = 'check_violation';
      end if;
    end if;
  end if;

  select app.resolve_attendance_workday(p_requested_start_at, coalesce(pv.timezone, 'UTC'), coalesce(pv.day_boundary_local_time, '00:00:00'::time))
  into v_work_date
  from app.resolve_effective_attendance_policy_version(p_employee.tenant_id, p_employee.branch_org_unit_id, (p_requested_start_at at time zone 'UTC')::date) pv
  limit 1;
  if v_work_date is null then
    v_work_date := (p_requested_start_at at time zone 'UTC')::date;
  end if;

  select * into v_policy from app.resolve_effective_overtime_policy_version(p_employee.tenant_id, p_employee.branch_org_unit_id, v_work_date) limit 1;
  if not found then
    raise exception 'no_eligible_policy: no published overtime policy is effective for employee % as of %', p_employee.master_record_id, v_work_date
      using errcode = 'check_violation';
  end if;

  -- Tier C fix (Finding 1, CRITICAL, spec section 23/25 "block schedule/
  -- leave overlap"): reuses app.leave_requests (HRT-280) directly,
  -- read-only -- never a second leave calendar. Scoped to the two LIVE
  -- statuses (pending_approval/approved), mirroring app.leave_requests_no_
  -- overlap's own EXCLUDE-constraint scope exactly. Unconditional (no
  -- HRS:Override bypass) -- matches this same function's other create-time
  -- hard blocks (no_eligible_policy, schedule_assignment_not_found), none
  -- of which is overridable at create time either; only the DECIDE-time
  -- attendance-evidence check has an HRS:Override exception.
  if exists (
    select 1 from app.leave_requests lr
    where lr.tenant_id = p_employee.tenant_id
      and lr.employee_id = p_employee.master_record_id
      and lr.status in ('pending_approval', 'approved')
      and lr.validity_range @> v_work_date
  ) then
    raise exception 'leave_overlap_conflict: employee % has a pending or approved leave request covering %', p_employee.master_record_id, v_work_date
      using errcode = 'check_violation';
  end if;

  if p_schedule_assignment_id is not null and not exists (
    select 1 from app.schedule_assignments sa where sa.id = p_schedule_assignment_id and sa.tenant_id = p_employee.tenant_id and sa.employee_id = p_employee.master_record_id
  ) then
    raise exception 'schedule_assignment_not_found: % is not a valid schedule assignment for employee %', p_schedule_assignment_id, p_employee.master_record_id
      using errcode = 'no_data_found';
  end if;
  perform app._validate_overtime_timesheet_operations_reference(p_employee.tenant_id, p_job_order_id, p_shipment_order_id);

  insert into app.overtime_requests (
    tenant_id, employee_id, work_date, request_type, requested_start_at, requested_end_at, unpaid_break_minutes, reason,
    schedule_assignment_id, job_order_id, shipment_order_id, requested_by_auth_user_id, requested_by, policy_version_id, idempotency_key, created_by
  ) values (
    p_employee.tenant_id, p_employee.master_record_id, v_work_date, p_request_type, p_requested_start_at, p_requested_end_at, coalesce(p_unpaid_break_minutes, 0), p_reason,
    p_schedule_assignment_id, p_job_order_id, p_shipment_order_id, p_actor_auth_user_id, p_actor_label, v_policy.id, p_idempotency_key, p_actor_label
  )
  returning * into v_request;

  perform app.capture_audit_event(
    p_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_overtime_request',
    'app.overtime_requests', v_request.id, 'success', null, null, jsonb_build_object('work_date', v_work_date, 'request_type', p_request_type)
  );

  return v_request;
exception
  -- C-09 (RECURRING_DEFECT_TAXONOMY.md): this table carries TWO unique
  -- indexes the terminal INSERT can violate (the active-slot uniqueness
  -- AND overtime_requests_idempotency_unique, the latter reachable when two
  -- literally-concurrent calls share an idempotency key and both pass the
  -- unlocked pre-check above before either commits). Discriminate on the
  -- real constraint name rather than assuming a unique_violation here can
  -- only ever mean the active-slot conflict.
  when unique_violation then
    declare
      v_constraint_name text;
    begin
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'overtime_requests_idempotency_unique' then
        raise exception 'idempotency_key_conflict: key % was already used for a different overtime request (concurrent duplicate submit)', p_idempotency_key
          using errcode = 'check_violation';
      else
        raise exception 'overtime_request_conflict: employee % already has an active overtime request for %', p_employee.master_record_id, v_work_date
          using errcode = 'check_violation';
      end if;
    end;
end;
$$;

-- ===========================================================================
-- Fix 1 (part C) + Fix 3: app._create_timesheet_entry -- identical leave-
-- overlap block and idempotency-tuple fix, same shape as _create_overtime_
-- request above.
-- ===========================================================================

create or replace function app._create_timesheet_entry(
  p_employee app.employees,
  p_work_date date,
  p_entry_minutes integer,
  p_unpaid_break_minutes integer,
  p_job_order_id uuid,
  p_shipment_order_id uuid,
  p_schedule_assignment_id uuid,
  p_notes text,
  p_source text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.timesheet_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.timesheet_entries;
  v_policy app.overtime_policy_versions;
  v_entry app.timesheet_entries;
begin
  if p_employee.master_record_id is null then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;
  if p_employee.lifecycle_status not in ('active', 'on_leave') then
    raise exception 'employee_not_active: employee % is %, only an active employee may log a timesheet entry', p_employee.master_record_id, p_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  if p_work_date is null then
    raise exception 'work_date_required: a work_date is required for a timesheet entry' using errcode = 'check_violation';
  end if;
  if p_entry_minutes is null or p_entry_minutes <= 0 or p_entry_minutes > 1440 then
    raise exception 'invalid_entry_minutes: entry_minutes must be a positive number of minutes, at most 1440' using errcode = 'check_violation';
  end if;
  if coalesce(p_unpaid_break_minutes, 0) < 0 then
    raise exception 'invalid_break_minutes: unpaid_break_minutes must not be negative' using errcode = 'check_violation';
  end if;
  if p_source not in ('manual', 'import', 'attendance_derived') then
    raise exception 'invalid_source: % is not manual/import/attendance_derived', p_source using errcode = 'check_violation';
  end if;

  -- C-01: full-tuple idempotency replay. Tier C fix (Finding 3, HIGH):
  -- unpaid_break_minutes now part of the compared tuple (same fix as
  -- _create_overtime_request above, applied here for the identical reason).
  if p_idempotency_key is not null then
    select * into v_existing from app.timesheet_entries where tenant_id = p_employee.tenant_id and employee_id = p_employee.master_record_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.work_date = p_work_date and v_existing.entry_minutes = p_entry_minutes
         and v_existing.job_order_id is not distinct from p_job_order_id and v_existing.shipment_order_id is not distinct from p_shipment_order_id
         and v_existing.unpaid_break_minutes = coalesce(p_unpaid_break_minutes, 0) then
        return v_existing;
      else
        -- Deliberately NOT errcode='unique_violation' -- this function has
        -- no wrapping unique_violation handler today, but this keeps the
        -- SAME lesson applied uniformly as app._create_overtime_request's
        -- own self-found C-02 fix, rather than leaving a second, dormant
        -- copy of the identical hazard for a future edit to reintroduce.
        raise exception 'idempotency_key_conflict: key % was already used for a different timesheet entry', p_idempotency_key
          using errcode = 'check_violation';
      end if;
    end if;
  end if;

  select * into v_policy from app.resolve_effective_overtime_policy_version(p_employee.tenant_id, p_employee.branch_org_unit_id, p_work_date) limit 1;
  if v_policy.id is null then
    raise exception 'no_eligible_policy: no published overtime/timesheet policy is effective for employee % as of %', p_employee.master_record_id, p_work_date
      using errcode = 'check_violation';
  end if;

  -- Tier C fix (Finding 1, CRITICAL): identical leave-overlap block as
  -- _create_overtime_request above -- applies uniformly regardless of
  -- source (manual/import/attendance_derived), matching this function's own
  -- existing uniform policy/operations-reference checks, which likewise
  -- apply regardless of source.
  if exists (
    select 1 from app.leave_requests lr
    where lr.tenant_id = p_employee.tenant_id
      and lr.employee_id = p_employee.master_record_id
      and lr.status in ('pending_approval', 'approved')
      and lr.validity_range @> p_work_date
  ) then
    raise exception 'leave_overlap_conflict: employee % has a pending or approved leave request covering %', p_employee.master_record_id, p_work_date
      using errcode = 'check_violation';
  end if;

  if p_schedule_assignment_id is not null and not exists (
    select 1 from app.schedule_assignments sa where sa.id = p_schedule_assignment_id and sa.tenant_id = p_employee.tenant_id and sa.employee_id = p_employee.master_record_id
  ) then
    raise exception 'schedule_assignment_not_found: % is not a valid schedule assignment for employee %', p_schedule_assignment_id, p_employee.master_record_id
      using errcode = 'no_data_found';
  end if;
  perform app._validate_overtime_timesheet_operations_reference(p_employee.tenant_id, p_job_order_id, p_shipment_order_id);

  insert into app.timesheet_entries (
    tenant_id, employee_id, work_date, entry_minutes, unpaid_break_minutes, job_order_id, shipment_order_id, schedule_assignment_id,
    notes, source, requested_by_auth_user_id, requested_by, policy_version_id, idempotency_key, created_by
  ) values (
    p_employee.tenant_id, p_employee.master_record_id, p_work_date, p_entry_minutes, coalesce(p_unpaid_break_minutes, 0), p_job_order_id, p_shipment_order_id, p_schedule_assignment_id,
    p_notes, p_source, p_actor_auth_user_id, p_actor_label, v_policy.id, p_idempotency_key, p_actor_label
  )
  returning * into v_entry;

  perform app.capture_audit_event(
    p_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_timesheet_entry',
    'app.timesheet_entries', v_entry.id, 'success', null, null, jsonb_build_object('work_date', p_work_date, 'entry_minutes', p_entry_minutes)
  );

  return v_entry;
exception
  -- C-09 (RECURRING_DEFECT_TAXONOMY.md), self-found gap: this INSERT's own
  -- column list never sets source_import_staging_row_id (the caller sets it
  -- via a separate UPDATE after this function returns -- see
  -- app.commit_timesheet_import_job), so the partial
  -- timesheet_entries_staging_row_unique index can never fire from here;
  -- the idempotency-unique index is the only one this INSERT can violate. A
  -- literally-concurrent duplicate submit sharing an idempotency key (both
  -- callers passing the unlocked pre-check above before either commits)
  -- previously surfaced as a raw, undiagnosed unique_violation with no
  -- handler at all -- now a clean, retriable idempotency_key_conflict,
  -- matching app._create_overtime_request's own identical fix.
  when unique_violation then
    raise exception 'idempotency_key_conflict: key % was already used for a different timesheet entry (concurrent duplicate submit)', p_idempotency_key
      using errcode = 'check_violation';
end;
$$;

-- ===========================================================================
-- Fix 4 (part A) + Fix 5 (part A): app.cancel_overtime_request -- adds the
-- missing period-lock gate (Finding 4, HIGH) and stops routing the raw
-- cancel_reason into capture_audit_event's unredacted p_reason column
-- (Finding 5, HIGH).
-- ===========================================================================

create or replace function app.cancel_overtime_request(
  p_request_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.overtime_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.overtime_requests;
  v_self app.employees;
  v_is_self boolean;
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.overtime_requests where id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'overtime_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_request.employee_id;

  -- Authority bar matched to blast radius (decision 17), mirrors app.
  -- cancel_leave_request's own Edit-or-Override tiering by row status
  -- (HRT-280 decision 12).
  if not v_is_self then
    if v_request.status = 'approved' then
      v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Override');
    else
      v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Edit');
    end if;
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks required HRS authority (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel an overtime request' using errcode = 'check_violation';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: overtime request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status not in ('draft', 'pending_approval', 'approved') then
    raise exception 'invalid_transition: overtime request % is %, cannot be cancelled', p_request_id, v_request.status using errcode = 'check_violation';
  end if;
  -- Decision 10/acceptance criteria: a request already folded into an
  -- active payroll input changes ONLY through the governed period-summary
  -- reopen workflow, never a silent cancel.
  if v_request.payroll_input_status = 'approved' then
    raise exception 'payroll_input_already_generated: overtime request % already contributed to a generated payroll input -- reopen the timesheet period summary first', p_request_id
      using errcode = 'check_violation';
  end if;

  -- Tier C batch review fix (Finding 4, HIGH): a locked period must reject
  -- a cancel too, not only submit/decide -- app.submit_overtime_request and
  -- app.decide_overtime_request both already call app.is_timesheet_period_
  -- locked before mutating; this function never did, live-reproduced
  -- letting a self-requester with ZERO HRS permission cancel their own
  -- already-approved, payroll-pending request inside a locked period.
  select * into v_employee from app.employees where master_record_id = v_request.employee_id;
  if app.is_timesheet_period_locked(v_request.tenant_id, v_employee.branch_org_unit_id, v_request.work_date) then
    raise exception 'timesheet_period_locked: the period covering % is locked -- ask HR to reopen it first', v_request.work_date
      using errcode = 'check_violation';
  end if;

  update app.overtime_requests
  set status = 'cancelled', cancel_reason = p_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: overtime request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Tier C batch review fix (Finding 5, HIGH, C-07): p_reason is the
  -- entity's own cancel_reason free text -- no longer routed into capture_
  -- audit_event's unredacted p_reason/app.audit_logs.reason column (any
  -- tenant_admin can read that column via app.query_audit_logs regardless
  -- of HRS:View/View personal data). The real cancel_reason value remains
  -- fully available through this row's own governed, permission-scoped
  -- read RPC (app.get_overtime_request_detail).
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_overtime_request',
    'app.overtime_requests', p_request_id, 'success', null, null, '{}'::jsonb
  );

  return v_request;
end;
$$;

-- ===========================================================================
-- Fix 4 (part B) + Fix 5 (part B): app.cancel_timesheet_entry -- identical
-- shape as app.cancel_overtime_request above.
-- ===========================================================================

create or replace function app.cancel_timesheet_entry(
  p_entry_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.timesheet_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_entry app.timesheet_entries;
  v_self app.employees;
  v_is_self boolean;
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_entry from app.timesheet_entries where id = p_entry_id for update;
  if not found or not app.has_active_tenant_membership(v_entry.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_entry_not_found: %', p_entry_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_entry.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_entry.employee_id;

  if not v_is_self then
    if v_entry.status = 'approved' then
      v_decision := app.evaluate_permission(p_actor_auth_user_id, v_entry.tenant_id, 'HRS', 'Override');
    else
      v_decision := app.evaluate_permission(p_actor_auth_user_id, v_entry.tenant_id, 'HRS', 'Edit');
    end if;
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks required HRS authority (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_entry.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a timesheet entry' using errcode = 'check_violation';
  end if;

  if v_entry.record_version <> p_expected_version then
    raise exception 'stale_version: timesheet entry % expected version % but found %', p_entry_id, p_expected_version, v_entry.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_entry.status not in ('draft', 'pending_approval', 'approved') then
    raise exception 'invalid_transition: timesheet entry % is %, cannot be cancelled', p_entry_id, v_entry.status using errcode = 'check_violation';
  end if;
  if v_entry.payroll_input_status = 'approved' then
    raise exception 'payroll_input_already_generated: timesheet entry % already contributed to a generated payroll input -- reopen the timesheet period summary first', p_entry_id
      using errcode = 'check_violation';
  end if;

  -- Tier C batch review fix (Finding 4, HIGH): identical period-lock gate
  -- as app.cancel_overtime_request above.
  select * into v_employee from app.employees where master_record_id = v_entry.employee_id;
  if app.is_timesheet_period_locked(v_entry.tenant_id, v_employee.branch_org_unit_id, v_entry.work_date) then
    raise exception 'timesheet_period_locked: the period covering % is locked -- ask HR to reopen it first', v_entry.work_date
      using errcode = 'check_violation';
  end if;

  update app.timesheet_entries
  set status = 'cancelled', cancel_reason = p_reason
  where id = p_entry_id and record_version = p_expected_version
  returning * into v_entry;
  if not found then
    raise exception 'stale_version: timesheet entry % target row was concurrently modified (expected version %)', p_entry_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Tier C batch review fix (Finding 5, HIGH, C-07): same reasoning as
  -- app.cancel_overtime_request above -- p_reason no longer routed into the
  -- unredacted audit_logs.reason column.
  perform app.capture_audit_event(
    v_entry.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_timesheet_entry',
    'app.timesheet_entries', p_entry_id, 'success', null, null, '{}'::jsonb
  );

  return v_entry;
end;
$$;

-- ===========================================================================
-- Fix 2 (part A): the four ambiguous-`id` cursor-pagination RPCs (Finding
-- 2, HIGH). Each fix aliases the source table in the p_after_id lookup
-- query -- a fully-qualified `x.id` reference cannot collide with the
-- RETURNS TABLE output column also named `id`, unlike the original bare
-- `id`. No other line changes.
-- ===========================================================================

create or replace function app.list_my_overtime_requests(p_tenant_id uuid, p_actor_auth_user_id uuid, p_limit integer, p_after_id uuid)
returns table (
  id uuid, work_date date, request_type text, requested_start_at timestamptz, requested_end_at timestamptz, requested_minutes integer,
  unpaid_break_minutes integer, status text, reconciliation_status text, eligible_minutes integer, eligible_classification text,
  approved_minutes integer, payroll_input_status text, reason text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_after app.overtime_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;

  if p_after_id is not null then
    select ot.* into v_after from app.overtime_requests ot where ot.id = p_after_id;
  end if;

  return query
  select o.id, o.work_date, o.request_type, o.requested_start_at, o.requested_end_at, o.requested_minutes, o.unpaid_break_minutes,
         o.status, o.reconciliation_status, o.eligible_minutes, o.eligible_classification, o.approved_minutes, o.payroll_input_status,
         o.reason, o.record_version
  from app.overtime_requests o
  where o.tenant_id = p_tenant_id and o.employee_id = v_self.master_record_id
    and (v_after.id is null or (o.work_date, o.id) < (v_after.work_date, v_after.id))
  order by o.work_date desc, o.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create or replace function app.list_overtime_requests(p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid, p_status text, p_limit integer, p_after_id uuid)
returns table (
  id uuid, employee_id uuid, employee_number text, employee_full_name text, work_date date, request_type text, status text,
  requested_minutes integer, reconciliation_status text, eligible_minutes integer, eligible_classification text, approved_minutes integer,
  payroll_input_status text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_has_view boolean;
  v_after app.overtime_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View')).allowed;

  -- Decision (mandatory reading item, "managers approve effective team,
  -- reuse the roster's own manager-scope resolution") -- the identical
  -- self-or-direct-manager-or-HRS:View predicate app.list_attendance_
  -- sessions/app.list_schedule_assignments/app.list_leave_requests each
  -- independently compute, never a second manager-hierarchy mechanism.
  if p_employee_id is not null then
    if not (
      v_has_view
      or (v_self.master_record_id is not null and v_self.master_record_id = p_employee_id)
      or exists (select 1 from app.employees e where e.master_record_id = p_employee_id and e.manager_employee_id = v_self.master_record_id)
    ) then
      return;
    end if;
  elsif not v_has_view and v_self.master_record_id is null then
    return;
  end if;

  if p_after_id is not null then
    select ot.* into v_after from app.overtime_requests ot where ot.id = p_after_id;
  end if;

  return query
  select o.id, o.employee_id, m.code, e.full_name, o.work_date, o.request_type, o.status, o.requested_minutes, o.reconciliation_status,
         o.eligible_minutes, o.eligible_classification, o.approved_minutes, o.payroll_input_status, o.record_version
  from app.overtime_requests o
  join app.employees e on e.master_record_id = o.employee_id
  join app.master_records m on m.id = e.master_record_id
  where o.tenant_id = p_tenant_id
    and (p_status is null or o.status = p_status)
    and (
      (p_employee_id is not null and o.employee_id = p_employee_id)
      or (p_employee_id is null and v_has_view)
      or (p_employee_id is null and not v_has_view and (o.employee_id = v_self.master_record_id or e.manager_employee_id = v_self.master_record_id))
    )
    and (v_after.id is null or (o.work_date, o.id) < (v_after.work_date, v_after.id))
  order by o.work_date desc, o.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create or replace function app.list_my_timesheet_entries(p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date, p_limit integer, p_after_id uuid)
returns table (
  id uuid, work_date date, entry_minutes integer, unpaid_break_minutes integer, job_order_id uuid, job_number text,
  shipment_order_id uuid, shipment_number text, status text, reconciliation_status text, eligible_minutes integer,
  approved_minutes integer, payroll_input_status text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_after app.timesheet_entries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;

  if p_after_id is not null then
    select te2.* into v_after from app.timesheet_entries te2 where te2.id = p_after_id;
  end if;

  return query
  select te.id, te.work_date, te.entry_minutes, te.unpaid_break_minutes, te.job_order_id, jo.job_number, te.shipment_order_id, so.shipment_number,
         te.status, te.reconciliation_status, te.eligible_minutes, te.approved_minutes, te.payroll_input_status, te.record_version
  from app.timesheet_entries te
  left join app.job_orders jo on jo.id = te.job_order_id
  left join app.shipment_orders so on so.id = te.shipment_order_id
  where te.tenant_id = p_tenant_id and te.employee_id = v_self.master_record_id
    and (p_from_date is null or te.work_date >= p_from_date)
    and (p_to_date is null or te.work_date <= p_to_date)
    and (v_after.id is null or (te.work_date, te.id) < (v_after.work_date, v_after.id))
  order by te.work_date desc, te.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create or replace function app.list_timesheet_entries(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid, p_status text, p_from_date date, p_to_date date, p_limit integer, p_after_id uuid
)
returns table (
  id uuid, employee_id uuid, employee_number text, employee_full_name text, work_date date, entry_minutes integer,
  job_order_id uuid, job_number text, shipment_order_id uuid, shipment_number text, status text, reconciliation_status text,
  eligible_minutes integer, approved_minutes integer, payroll_input_status text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_has_view boolean;
  v_after app.timesheet_entries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View')).allowed;

  if p_employee_id is not null then
    if not (
      v_has_view
      or (v_self.master_record_id is not null and v_self.master_record_id = p_employee_id)
      or exists (select 1 from app.employees e where e.master_record_id = p_employee_id and e.manager_employee_id = v_self.master_record_id)
    ) then
      return;
    end if;
  elsif not v_has_view and v_self.master_record_id is null then
    return;
  end if;

  if p_after_id is not null then
    select te2.* into v_after from app.timesheet_entries te2 where te2.id = p_after_id;
  end if;

  return query
  select te.id, te.employee_id, m.code, e.full_name, te.work_date, te.entry_minutes, te.job_order_id, jo.job_number, te.shipment_order_id, so.shipment_number,
         te.status, te.reconciliation_status, te.eligible_minutes, te.approved_minutes, te.payroll_input_status, te.record_version
  from app.timesheet_entries te
  join app.employees e on e.master_record_id = te.employee_id
  join app.master_records m on m.id = e.master_record_id
  left join app.job_orders jo on jo.id = te.job_order_id
  left join app.shipment_orders so on so.id = te.shipment_order_id
  where te.tenant_id = p_tenant_id
    and (p_status is null or te.status = p_status)
    and (p_from_date is null or te.work_date >= p_from_date)
    and (p_to_date is null or te.work_date <= p_to_date)
    and (
      (p_employee_id is not null and te.employee_id = p_employee_id)
      or (p_employee_id is null and v_has_view)
      or (p_employee_id is null and not v_has_view and (te.employee_id = v_self.master_record_id or e.manager_employee_id = v_self.master_record_id))
    )
    and (v_after.id is null or (te.work_date, te.id) < (v_after.work_date, v_after.id))
  order by te.work_date desc, te.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

-- ===========================================================================
-- Fix 5 (part C): app.decide_overtime_request / app.decide_timesheet_entry
-- -- decided_reason no longer routed into capture_audit_event's unredacted
-- p_reason column. No other change from the originally-committed function.
-- ===========================================================================

create or replace function app.decide_overtime_request(
  p_request_id uuid,
  p_expected_version integer,
  p_decision text,
  p_decided_reason text,
  p_approved_minutes_override integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.overtime_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rbac app.rbac_decision;
  v_override_rbac app.rbac_decision;
  v_request app.overtime_requests;
  v_self app.employees;
  v_employee app.employees;
  v_policy app.overtime_policy_versions;
  v_pre_round integer;
  v_eligible integer;
  v_classification text;
  v_approved integer;
  v_week_key text;
  v_week_sum integer;
  v_remaining integer;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decided_reason is null or length(trim(p_decided_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide an overtime request' using errcode = 'check_violation';
  end if;

  select * into v_request from app.overtime_requests where id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'overtime_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_rbac := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Approve');
  if not v_rbac.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_rbac.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- C-18: self-approval never permitted, even for an actor who also holds
  -- HRS:Approve.
  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_request.employee_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own overtime request' using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: overtime request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'pending_approval' then
    raise exception 'invalid_transition: overtime request % is %, cannot be decided', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = v_request.employee_id;
  if app.is_timesheet_period_locked(v_request.tenant_id, v_employee.branch_org_unit_id, v_request.work_date) then
    raise exception 'timesheet_period_locked: the period covering % is locked -- ask HR to reopen it first', v_request.work_date
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approve' then
    -- Decision 3/16: refresh reconciliation with the freshest evidence
    -- available at decide time, then hard-block on missing/mismatched
    -- attendance evidence unless the decider also holds HRS:Override
    -- (exception flow, section 23).
    v_request := app._reconcile_overtime_request_actual(p_request_id);

    if v_request.reconciliation_status in ('no_attendance', 'mismatch') then
      v_override_rbac := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Override');
      if not v_override_rbac.allowed then
        raise exception 'attendance_evidence_required: reconciliation status is % -- approving without matching attendance evidence requires HRS:Override (%)', v_request.reconciliation_status, v_override_rbac.reason
          using errcode = 'insufficient_privilege';
      end if;
    end if;

    -- v_policy.id is checked directly, never the bare FOUND special
    -- variable (the reconcile call immediately above already overwrote it) --
    -- the exact class HRT-279's own self-found defect #3 established.
    select * into v_policy from app.overtime_policy_versions where id = v_request.policy_version_id;
    if v_policy.id is null then
      select * into v_policy from app.resolve_effective_overtime_policy_version(v_request.tenant_id, v_employee.branch_org_unit_id, v_request.work_date) limit 1;
      if v_policy.id is null then
        raise exception 'no_eligible_policy: no published overtime policy is effective for employee % as of %', v_request.employee_id, v_request.work_date
          using errcode = 'check_violation';
      end if;
    end if;

    v_pre_round := greatest(0, coalesce(v_request.reconciled_actual_minutes, v_request.requested_minutes) - v_request.unpaid_break_minutes);

    if v_pre_round < v_policy.min_overtime_minutes then
      v_eligible := 0;
    else
      v_eligible := app.round_minutes(v_pre_round, v_policy.rounding_increment_minutes, v_policy.rounding_mode);

      if v_policy.daily_overtime_cap_minutes is not null then
        v_eligible := least(v_eligible, v_policy.daily_overtime_cap_minutes);
      end if;

      if v_policy.weekly_overtime_cap_minutes is not null then
        -- Decision 9: advisory-lock-serialized weekly-cap enforcement -- the
        -- structural safety net closing the real concurrent-approval race
        -- this task's own workflow instructions name explicitly. Keyed on
        -- (tenant, employee, ISO year-week), mirrors app.decide_leave_
        -- request's own pg_advisory_xact_lock shape (HRT-280 decision 4/9).
        v_week_key := v_request.tenant_id::text || ':' || v_request.employee_id::text || ':' || to_char(v_request.work_date, 'IYYY-IW');
        perform pg_advisory_xact_lock(hashtextextended(v_week_key, 281));

        select coalesce(sum(o.eligible_minutes), 0) into v_week_sum
        from app.overtime_requests o
        where o.tenant_id = v_request.tenant_id and o.employee_id = v_request.employee_id and o.status = 'approved'
          and o.id <> v_request.id
          and to_char(o.work_date, 'IYYY-IW') = to_char(v_request.work_date, 'IYYY-IW');

        v_remaining := greatest(0, v_policy.weekly_overtime_cap_minutes - v_week_sum);
        v_eligible := least(v_eligible, v_remaining);
      end if;
    end if;

    v_classification := app.classify_overtime_work_date(v_request.tenant_id, v_employee.branch_org_unit_id, v_request.work_date);

    v_approved := coalesce(p_approved_minutes_override, v_eligible);
    if v_approved < 0 or v_approved > v_eligible then
      raise exception 'invalid_approved_minutes: approved_minutes % must be between 0 and the eligible figure of %', v_approved, v_eligible
        using errcode = 'check_violation';
    end if;

    -- v_request.record_version is used here, never the caller's own
    -- p_expected_version -- the approve branch's own reconcile call above
    -- already advanced it (same self-found class as app.submit_overtime_
    -- request). The reject branch never touches the row before this point,
    -- so v_request.record_version there still equals p_expected_version
    -- exactly -- one uniform guard shape, safe in both branches, since the
    -- row lock held since the top SELECT ... FOR UPDATE rules out any
    -- external race in between.
    update app.overtime_requests
    set status = 'approved', decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason,
        eligible_minutes = v_eligible, eligible_classification = v_classification, approved_minutes = v_approved, payroll_input_status = 'pending'
    where id = p_request_id and record_version = v_request.record_version
    returning * into v_request;
  else
    update app.overtime_requests
    set status = 'rejected', decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason
    where id = p_request_id and record_version = v_request.record_version
    returning * into v_request;
  end if;
  if not found then
    raise exception 'stale_version: overtime request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Tier C batch review fix (Finding 5, HIGH, C-07): decided_reason no
  -- longer routed into capture_audit_event's unredacted p_reason column --
  -- still fully readable through app.get_overtime_request_detail's own
  -- governed, permission-scoped read path.
  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_overtime_request',
    'app.overtime_requests', p_request_id, 'success', null, null, jsonb_build_object('decision', p_decision, 'eligible_minutes', v_request.eligible_minutes, 'approved_minutes', v_request.approved_minutes)
  );

  return v_request;
end;
$$;

create or replace function app.decide_timesheet_entry(
  p_entry_id uuid,
  p_expected_version integer,
  p_decision text,
  p_decided_reason text,
  p_approved_minutes_override integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.timesheet_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rbac app.rbac_decision;
  v_entry app.timesheet_entries;
  v_self app.employees;
  v_employee app.employees;
  v_policy app.overtime_policy_versions;
  v_pre_round integer;
  v_eligible integer;
  v_approved integer;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decided_reason is null or length(trim(p_decided_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a timesheet entry' using errcode = 'check_violation';
  end if;

  select * into v_entry from app.timesheet_entries where id = p_entry_id for update;
  if not found or not app.has_active_tenant_membership(v_entry.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_entry_not_found: %', p_entry_id using errcode = 'no_data_found';
  end if;

  v_rbac := app.evaluate_permission(p_actor_auth_user_id, v_entry.tenant_id, 'HRS', 'Approve');
  if not v_rbac.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_rbac.reason, v_entry.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_self := app.get_self_employee(v_entry.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_entry.employee_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own timesheet entry' using errcode = 'insufficient_privilege';
  end if;

  if v_entry.record_version <> p_expected_version then
    raise exception 'stale_version: timesheet entry % expected version % but found %', p_entry_id, p_expected_version, v_entry.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_entry.status <> 'pending_approval' then
    raise exception 'invalid_transition: timesheet entry % is %, cannot be decided', p_entry_id, v_entry.status
      using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = v_entry.employee_id;
  if app.is_timesheet_period_locked(v_entry.tenant_id, v_employee.branch_org_unit_id, v_entry.work_date) then
    raise exception 'timesheet_period_locked: the period covering % is locked -- ask HR to reopen it first', v_entry.work_date
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approve' then
    select * into v_policy from app.overtime_policy_versions where id = v_entry.policy_version_id;
    if v_policy.id is null then
      select * into v_policy from app.resolve_effective_overtime_policy_version(v_entry.tenant_id, v_employee.branch_org_unit_id, v_entry.work_date) limit 1;
      if v_policy.id is null then
        raise exception 'no_eligible_policy: no published overtime/timesheet policy is effective for employee % as of %', v_entry.employee_id, v_entry.work_date
          using errcode = 'check_violation';
      end if;
    end if;

    v_pre_round := greatest(0, v_entry.entry_minutes - v_entry.unpaid_break_minutes);
    v_eligible := app.round_minutes(v_pre_round, v_policy.rounding_increment_minutes, v_policy.rounding_mode);

    v_approved := coalesce(p_approved_minutes_override, v_eligible);
    if v_approved < 0 or v_approved > v_eligible then
      raise exception 'invalid_approved_minutes: approved_minutes % must be between 0 and the eligible figure of %', v_approved, v_eligible
        using errcode = 'check_violation';
    end if;

    update app.timesheet_entries
    set status = 'approved', decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason,
        eligible_minutes = v_eligible, approved_minutes = v_approved, payroll_input_status = 'pending'
    where id = p_entry_id and record_version = p_expected_version
    returning * into v_entry;
  else
    update app.timesheet_entries
    set status = 'rejected', decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason
    where id = p_entry_id and record_version = p_expected_version
    returning * into v_entry;
  end if;
  if not found then
    raise exception 'stale_version: timesheet entry % target row was concurrently modified (expected version %)', p_entry_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Tier C batch review fix (Finding 5, HIGH, C-07): same reasoning as
  -- app.decide_overtime_request above.
  perform app.capture_audit_event(
    v_entry.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_timesheet_entry',
    'app.timesheet_entries', p_entry_id, 'success', null, null, jsonb_build_object('decision', p_decision, 'eligible_minutes', v_entry.eligible_minutes, 'approved_minutes', v_entry.approved_minutes)
  );

  return v_entry;
end;
$$;

-- ===========================================================================
-- Fix 5 (part D): app.submit_timesheet_period_summary / app.approve_
-- timesheet_period_summary -- to_jsonb(v_summary) replaced with the new
-- masked app.timesheet_period_summary_audit_projection; approve also stops
-- routing its own p_reason into the unredacted audit_logs.reason column.
-- ===========================================================================

create or replace function app.submit_timesheet_period_summary(
  p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.timesheet_period_summaries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.timesheet_periods;
  v_self app.employees;
  v_is_self boolean;
  v_decision app.rbac_decision;
  v_summary app.timesheet_period_summaries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_period from app.timesheet_periods where id = p_period_id;
  if v_period.id is null or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;
  if v_period.status <> 'open' then
    raise exception 'timesheet_period_locked: period % is locked, cannot accept a new submission', p_period_id using errcode = 'check_violation';
  end if;

  v_self := app.get_self_employee(v_period.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = p_employee_id;
  if not v_is_self then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_period.tenant_id, 'HRS', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_period.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  v_summary := app._compute_timesheet_period_summary(p_period_id, p_employee_id);
  if v_summary.status not in ('pending', 'rejected') then
    raise exception 'invalid_transition: timesheet period summary for employee % is %, cannot be re-submitted', p_employee_id, v_summary.status
      using errcode = 'check_violation';
  end if;

  update app.timesheet_period_summaries
  set status = 'submitted', submitted_by = p_actor_label, submitted_at = now()
  where id = v_summary.id
  returning * into v_summary;

  -- Tier C batch review fix (Finding 5, HIGH, C-07): to_jsonb(v_summary)
  -- replaced with the masked projection -- mirrors app.leave_request_audit_
  -- projection's own established fix for the identical class one migration
  -- earlier (HRT-280).
  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_timesheet_period_summary',
    'app.timesheet_period_summaries', v_summary.id, 'success', null, null, app.timesheet_period_summary_audit_projection(v_summary)
  );

  return v_summary;
end;
$$;

create or replace function app.approve_timesheet_period_summary(
  p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.timesheet_period_summaries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_summary app.timesheet_period_summaries;
  v_period app.timesheet_periods;
  v_decision app.rbac_decision;
  v_self app.employees;
begin
  select * into v_summary from app.timesheet_period_summaries where id = p_summary_id for update;
  if v_summary.id is null or not app.has_active_tenant_membership(v_summary.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_period_summary_not_found: %', p_summary_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_summary.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_summary.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_self := app.get_self_employee(v_summary.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_summary.employee_id then
    raise exception 'self_approval_not_permitted: an actor may not approve their own timesheet period summary' using errcode = 'insufficient_privilege';
  end if;

  if v_summary.record_version <> p_expected_version then
    raise exception 'stale_version: timesheet period summary % expected version % but found %', p_summary_id, p_expected_version, v_summary.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_summary.status <> 'submitted' then
    raise exception 'invalid_transition: timesheet period summary % is %, only a submitted summary may be approved', p_summary_id, v_summary.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.timesheet_periods where id = v_summary.timesheet_period_id;
  if v_period.status <> 'open' then
    raise exception 'timesheet_period_locked: period % is locked, reopen it before deciding a summary', v_period.id using errcode = 'check_violation';
  end if;

  -- Recompute fresh, immediately before locking the figures in -- never
  -- approve a stale total (this table''s own comment). The recompute is a
  -- real UPDATE on THIS SAME row (upsert), so it advances record_version
  -- via app.touch_overtime_timesheet_row -- re-read the CURRENT version for
  -- the terminal guard below, never the caller's own, now-stale,
  -- p_expected_version (identical self-found class as app.submit_overtime_
  -- request/app.submit_timesheet_entry; the row lock held since the top
  -- SELECT ... FOR UPDATE makes this safe).
  v_summary := app._compute_timesheet_period_summary(v_summary.timesheet_period_id, v_summary.employee_id);

  update app.timesheet_period_summaries
  set status = 'approved', decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason
  where id = p_summary_id and record_version = v_summary.record_version
  returning * into v_summary;
  if not found then
    raise exception 'stale_version: timesheet period summary % target row was concurrently modified (expected version %)', p_summary_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Tier C batch review fix (Finding 5, HIGH, C-07): to_jsonb(v_summary)
  -- replaced with the masked projection, and p_reason no longer routed into
  -- the unredacted audit_logs.reason column -- still fully readable via
  -- app.get_timesheet_period_summary's own governed read path.
  perform app.capture_audit_event(
    v_summary.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_timesheet_period_summary',
    'app.timesheet_period_summaries', p_summary_id, 'success', null, null, app.timesheet_period_summary_audit_projection(v_summary)
  );

  return v_summary;
end;
$$;

-- ===========================================================================
-- Fix 5 (part E): app.reject_timesheet_period_summary / app.reopen_
-- timesheet_period -- p_reason no longer routed into the unredacted audit_
-- logs.reason column. No other change.
-- ===========================================================================

create or replace function app.reject_timesheet_period_summary(
  p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.timesheet_period_summaries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_summary app.timesheet_period_summaries;
  v_decision app.rbac_decision;
  v_self app.employees;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reject a timesheet period summary' using errcode = 'check_violation';
  end if;

  select * into v_summary from app.timesheet_period_summaries where id = p_summary_id for update;
  if v_summary.id is null or not app.has_active_tenant_membership(v_summary.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_period_summary_not_found: %', p_summary_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_summary.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_summary.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- C-18 (RECURRING_DEFECT_TAXONOMY.md), self-found consistency gap: the
  -- sibling approve_timesheet_period_summary blocks self-decision; this
  -- reject counterpart did not. Low practical risk standing alone (a self-
  -- reject only sets the actor's own record back, granting nothing), but
  -- every OTHER decide-style function in this migration
  -- (decide_overtime_request, decide_timesheet_entry) blocks self on the
  -- WHOLE decide operation, not just its approve half -- matched here for
  -- the same uniform enforcement.
  v_self := app.get_self_employee(v_summary.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_summary.employee_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own timesheet period summary' using errcode = 'insufficient_privilege';
  end if;

  if v_summary.record_version <> p_expected_version then
    raise exception 'stale_version: timesheet period summary % expected version % but found %', p_summary_id, p_expected_version, v_summary.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_summary.status <> 'submitted' then
    raise exception 'invalid_transition: timesheet period summary % is %, only a submitted summary may be rejected', p_summary_id, v_summary.status
      using errcode = 'check_violation';
  end if;

  update app.timesheet_period_summaries
  set status = 'rejected', decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason
  where id = p_summary_id and record_version = p_expected_version
  returning * into v_summary;
  if not found then
    raise exception 'stale_version: timesheet period summary % target row was concurrently modified (expected version %)', p_summary_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Tier C batch review fix (Finding 5, HIGH, C-07): p_reason no longer
  -- routed into the unredacted audit_logs.reason column.
  perform app.capture_audit_event(
    v_summary.tenant_id, p_actor_auth_user_id, p_actor_label, 'reject_timesheet_period_summary',
    'app.timesheet_period_summaries', p_summary_id, 'success', null, null, '{}'::jsonb
  );

  return v_summary;
end;
$$;

create or replace function app.reopen_timesheet_period(
  p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.timesheet_periods
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_period app.timesheet_periods;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reopen a timesheet period' using errcode = 'check_violation';
  end if;

  select * into v_period from app.timesheet_periods where id = p_period_id for update;
  if v_period.id is null or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  -- Decision 10/17: reopen is HRS:Override, a strictly bigger blast radius
  -- than the HRS:Approve that locked it.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_period.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: timesheet period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_period.status <> 'locked' then
    raise exception 'invalid_transition: timesheet period % is not locked', p_period_id using errcode = 'check_violation';
  end if;

  update app.timesheet_periods
  set status = 'open', locked_by = null, locked_at = null, reopen_count = reopen_count + 1,
      last_reopened_by = p_actor_label, last_reopened_at = now(), last_reopen_reason = p_reason
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  if not found then
    raise exception 'stale_version: timesheet period % target row was concurrently modified (expected version %)', p_period_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Tier C batch review fix (Finding 5, HIGH, C-07): p_reason no longer
  -- routed into the unredacted audit_logs.reason column -- still fully
  -- readable via app.list_timesheet_periods/this row's own last_reopen_
  -- reason column (never column-restricted from authenticated, unlike the
  -- person-scoped tables' reason columns, since timesheet_periods is
  -- tenant-membership-scoped metadata, not per-employee HR content).
  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_timesheet_period',
    'app.timesheet_periods', p_period_id, 'success', null, null, '{}'::jsonb
  );

  return v_period;
end;
$$;

-- ===========================================================================
-- Fix 5 (part F) + Fix 6 (part A): app.reopen_timesheet_period_summary --
-- p_reason no longer routed into the unredacted audit_logs.reason column
-- (Finding 5), and now also invalidates the existing active app.payroll_
-- time_inputs row for this (period, employee) by flipping it to 'stale'
-- (Finding 6).
-- ===========================================================================

create or replace function app.reopen_timesheet_period_summary(
  p_summary_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.timesheet_period_summaries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_summary app.timesheet_period_summaries;
  v_period app.timesheet_periods;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reopen a timesheet period summary' using errcode = 'check_violation';
  end if;

  select * into v_summary from app.timesheet_period_summaries where id = p_summary_id for update;
  if v_summary.id is null or not app.has_active_tenant_membership(v_summary.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_period_summary_not_found: %', p_summary_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_summary.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_summary.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_period from app.timesheet_periods where id = v_summary.timesheet_period_id;
  if v_period.status <> 'open' then
    raise exception 'timesheet_period_locked: period % is locked -- reopen the period first', v_period.id using errcode = 'check_violation';
  end if;

  if v_summary.record_version <> p_expected_version then
    raise exception 'stale_version: timesheet period summary % expected version % but found %', p_summary_id, p_expected_version, v_summary.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_summary.status <> 'approved' then
    raise exception 'invalid_transition: timesheet period summary % is %, only an approved summary may be reopened', p_summary_id, v_summary.status
      using errcode = 'check_violation';
  end if;

  update app.timesheet_period_summaries
  set status = 'pending', reopen_count = reopen_count + 1, last_reopened_by = p_actor_label, last_reopened_at = now(), last_reopen_reason = p_reason
  where id = p_summary_id and record_version = p_expected_version
  returning * into v_summary;
  if not found then
    raise exception 'stale_version: timesheet period summary % target row was concurrently modified (expected version %)', p_summary_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Governed correction (decision 10): the contributing entries/requests are
  -- reset to pending payroll-input status so a subsequent re-approval and
  -- re-generation of the payroll input is possible.
  update app.timesheet_entries
  set payroll_input_status = 'pending'
  where tenant_id = v_summary.tenant_id and employee_id = v_summary.employee_id and payroll_input_status = 'approved'
    and work_date between v_period.period_start and v_period.period_end;
  update app.overtime_requests
  set payroll_input_status = 'pending'
  where tenant_id = v_summary.tenant_id and employee_id = v_summary.employee_id and payroll_input_status = 'approved'
    and work_date between v_period.period_start and v_period.period_end;

  -- Tier C batch review fix (Finding 6, HIGH): the ALREADY-generated app.
  -- payroll_time_inputs row for this (period, employee), if any, is now
  -- flipped to 'stale' at reopen time -- previously it stayed 'active' with
  -- its pre-correction totals, live-reproduced returning as
  -- status='active' from app.get_payroll_time_input/app.list_payroll_
  -- time_inputs with zero signal the underlying summary was reopened.
  -- 'stale' is distinct from 'superseded' (which specifically means "a
  -- newer, already-generated version exists and supersedes this one via
  -- superseded_by_id") -- app._generate_payroll_time_input below treats a
  -- 'stale' row as the prior version to compare against/replace, exactly
  -- like it already treats an 'active' one.
  update app.payroll_time_inputs
  set status = 'stale'
  where timesheet_period_id = v_summary.timesheet_period_id and employee_id = v_summary.employee_id and status = 'active';

  -- Tier C batch review fix (Finding 5, HIGH, C-07): p_reason no longer
  -- routed into the unredacted audit_logs.reason column.
  perform app.capture_audit_event(
    v_summary.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_timesheet_period_summary',
    'app.timesheet_period_summaries', p_summary_id, 'success', null, null, '{}'::jsonb
  );

  return v_summary;
end;
$$;

-- ===========================================================================
-- Fix 6 (part B): app._generate_payroll_time_input -- the active-row lookup
-- now considers 'active' AND 'stale' as "the prior version," and a
-- content-unchanged 'stale' row is restored directly to 'active' rather
-- than ever being returned to a caller while still labelled 'stale'.
-- ===========================================================================

create or replace function app._generate_payroll_time_input(p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_time_inputs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.timesheet_periods;
  v_summary app.timesheet_period_summaries;
  v_active app.payroll_time_inputs;
  v_next_version integer;
  v_new app.payroll_time_inputs;
  v_entry_ids uuid[];
  v_ot_ids uuid[];
  v_lock_key text;
begin
  select * into v_period from app.timesheet_periods where id = p_period_id;
  if v_period.id is null then
    raise exception 'timesheet_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  -- Advisory-lock-serialized per (period, employee) -- two concurrent
  -- generate calls for the SAME employee's SAME period can never both race
  -- past the partial-unique-active-row check below.
  v_lock_key := p_period_id::text || ':' || p_employee_id::text;
  perform pg_advisory_xact_lock(hashtextextended(v_lock_key, 281));

  select * into v_summary from app.timesheet_period_summaries where timesheet_period_id = p_period_id and employee_id = p_employee_id for update;
  if v_summary.id is null then
    raise exception 'timesheet_period_summary_not_found: no summary for employee % in period %', p_employee_id, p_period_id using errcode = 'no_data_found';
  end if;
  if v_summary.status <> 'approved' then
    raise exception 'invalid_transition: timesheet period summary for employee % is %, must be approved before a payroll input may be generated', p_employee_id, v_summary.status
      using errcode = 'check_violation';
  end if;

  -- Decision 11: recompute fresh -- content-based idempotency depends on
  -- always reading the TRUE current state, never a stale approve-time
  -- snapshot (an employee summary could theoretically have gone stale from
  -- a late-arriving approved entry before the whole period was locked).
  v_summary := app._compute_timesheet_period_summary(p_period_id, p_employee_id);

  select array_agg(te.id) into v_entry_ids from app.timesheet_entries te
  where te.tenant_id = v_period.tenant_id and te.employee_id = p_employee_id and te.status = 'approved' and te.work_date between v_period.period_start and v_period.period_end;
  select array_agg(ot.id) into v_ot_ids from app.overtime_requests ot
  where ot.tenant_id = v_period.tenant_id and ot.employee_id = p_employee_id and ot.status = 'approved' and ot.work_date between v_period.period_start and v_period.period_end;

  -- Tier C batch review fix (Finding 6, HIGH): a 'stale' row (flipped by
  -- app.reopen_timesheet_period_summary above) is now ALSO the "prior
  -- version to compare against/replace," exactly like an 'active' row
  -- already was -- picks the most recent by version_number since at most
  -- one of 'active'/'stale' can exist for this (period, employee) at a
  -- time (the partial unique index only constrains 'active', but the
  -- reopen path above guarantees the row it flips was the sole 'active'
  -- one, and no OTHER path ever creates a second 'stale' row without first
  -- superseding it here).
  select * into v_active from app.payroll_time_inputs
  where timesheet_period_id = p_period_id and employee_id = p_employee_id and status in ('active', 'stale')
  order by version_number desc
  limit 1;

  if v_active.id is not null
     and v_active.regular_minutes = v_summary.total_regular_minutes
     and v_active.overtime_weekday_minutes = v_summary.total_overtime_weekday_minutes
     and v_active.overtime_weekend_minutes = v_summary.total_overtime_weekend_minutes
     and v_active.overtime_holiday_minutes = v_summary.total_overtime_holiday_minutes
  then
    -- Decision 11: true content-based idempotency -- an identical recompute
    -- returns the SAME active version, never a redundant new one, and
    -- immune by construction to the C-01 "replay matched the key but never
    -- verified the target" class, since there is no caller-supplied replay
    -- key here to mis-compare against. Tier C fix (Finding 6): if the prior
    -- version was flipped to 'stale' by a reopen but the recomputed totals
    -- are genuinely unchanged (e.g. the reopen turned out not to need a
    -- real correction), restore it directly to 'active' -- never return a
    -- row still labelled 'stale' as if it were the fresh, authoritative
    -- result.
    if v_active.status = 'stale' then
      update app.payroll_time_inputs set status = 'active' where id = v_active.id returning * into v_active;
    end if;
    return v_active;
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.payroll_time_inputs where timesheet_period_id = p_period_id and employee_id = p_employee_id;

  -- Supersede BEFORE insert -- HRT-279's own self-found defect #2 lesson
  -- (insert-before-supersede momentarily violated its own partial unique
  -- index), applied here from the start rather than discovered again. This
  -- also covers a v_active row currently 'stale' -- either way it ends up
  -- definitively 'superseded', with superseded_by_id pointing at the
  -- genuinely new version below.
  if v_active.id is not null then
    update app.payroll_time_inputs set status = 'superseded' where id = v_active.id;
  end if;

  insert into app.payroll_time_inputs (
    tenant_id, employee_id, timesheet_period_id, period_summary_id, version_number, regular_minutes,
    overtime_weekday_minutes, overtime_weekend_minutes, overtime_holiday_minutes, source_entry_ids, source_overtime_request_ids,
    idempotency_key, generated_by
  ) values (
    v_period.tenant_id, p_employee_id, p_period_id, v_summary.id, v_next_version, v_summary.total_regular_minutes,
    v_summary.total_overtime_weekday_minutes, v_summary.total_overtime_weekend_minutes, v_summary.total_overtime_holiday_minutes,
    coalesce(v_entry_ids, array[]::uuid[]), coalesce(v_ot_ids, array[]::uuid[]),
    p_period_id::text || ':' || p_employee_id::text || ':' || v_next_version::text, p_actor_label
  )
  returning * into v_new;

  if v_active.id is not null then
    update app.payroll_time_inputs set superseded_by_id = v_new.id where id = v_active.id;
  end if;

  update app.timesheet_entries set payroll_input_status = 'approved' where id = any (coalesce(v_entry_ids, array[]::uuid[]));
  update app.overtime_requests set payroll_input_status = 'approved' where id = any (coalesce(v_ot_ids, array[]::uuid[]));

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'generate_payroll_time_input',
    'app.payroll_time_inputs', v_new.id, 'success', null, null,
    jsonb_build_object('timesheet_period_id', p_period_id, 'employee_id', p_employee_id, 'version_number', v_next_version)
  );

  return v_new;
end;
$$;

-- ===========================================================================
-- Fix 6 (part C): widen app.payroll_time_inputs.status's own CHECK
-- constraint to add 'stale'.
-- ===========================================================================

alter table app.payroll_time_inputs drop constraint payroll_time_inputs_status_check;
alter table app.payroll_time_inputs add constraint payroll_time_inputs_status_check check (status in ('active', 'superseded', 'stale'));

comment on table app.payroll_time_inputs is
  'HRT-281 (decisions 1, 11, 12), Tier C fix (Finding 6): the versioned, idempotent payroll-input handoff Prompt 282 (Payroll) is expected to consume -- time/classification ONLY, zero rate/amount/currency column (decision 12). Genuinely append-only: a correction produces a NEW row, the prior one flipped to ''superseded'' (insert-after-supersede ordering, HRT-279 defect #2 lesson), never an UPDATE of the original figures. A governed period-summary reopen (app.reopen_timesheet_period_summary) additionally flips the CURRENTLY active row to ''stale'' immediately, before any new version exists, so a Payroll consumer reading status=''active'' never sees pre-correction totals during the window between a reopen and the next regenerate.';

-- ===========================================================================
-- Low-severity, cheap, in-scope fix: non-negativity CHECK on app.timesheet_
-- period_summaries.entry_count/overtime_request_count -- every other
-- numeric column on this table already carries one; these two were the
-- exception (defense-in-depth only, unreachable via any current write path
-- since app._compute_timesheet_period_summary always sets both from
-- count(*), which cannot be negative).
-- ===========================================================================

alter table app.timesheet_period_summaries
  add constraint timesheet_period_summaries_counts_nonneg_check check (entry_count >= 0 and overtime_request_count >= 0);
