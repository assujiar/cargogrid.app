-- Tier C review of Prompt 295 (CG-S12-HRT-023, HRT-295) -- the standalone
-- Hardening checkpoint's own follow-up review. All four review lenses
-- (spec-compliance, security, correctness, integration) independently
-- live-re-derived the SAME residual gap in HRT-295's own ISS-2026-105 fix
-- (20260731240000) and this migration closes it. Never edits
-- 20260731240000 itself (an already-shipped migration in this same
-- checkpoint) -- CREATE OR REPLACE FUNCTION again, next free timestamp,
-- per this review's own additive-only mandate.
--
-- ===========================================================================
-- The residual gap, confirmed independently (own fixture, own arithmetic,
-- not accepted from any lens report or from 20260731240000's own claimed
-- before/after numbers).
-- ===========================================================================
--
-- ISS-2026-105's own original text (docs/runtime/KNOWN_ISSUES.md:522)
-- defines "correct" for its own live reproduction explicitly: the
-- overtime-covered day should be "counted ... at the shift's real
-- 540-minute REGULAR portion" -- i.e. an overtime-covered day's own
-- non-overtime worked minutes are still real, worked, compensable regular
-- time and must still be paid. 20260731240000's shipped fix instead
-- excludes such a day from the attendance-fallback ENTIRELY (0 minutes,
-- not 540) -- it correctly closes the double-count (the SAME minutes are
-- never counted twice) but replaces a real overstatement defect with a
-- real, larger-magnitude UNDERstatement defect on the identical
-- reproduction shape: a genuine attendance session plus a genuine,
-- HR-approved overtime request on the same work_date, no timesheet entry
-- -- not an edge case, the exact scenario this Critical finding's own
-- severity was judged against.
--
-- Independently re-derived here (before writing this fix, per this review's
-- own instruction to never fix from a report alone), on a FRESH fixture
-- distinct from both the original finding's own reproduction and
-- 20260731240000's own emp3/hris-payroll.sql regression block: tenant
-- pay1, a new employee (empindep), 2026-11-09, raw attendance span 735
-- minutes (08:00-20:15), a real HR-approved overtime request reconciling
-- to 180 minutes (the policy's own max_daily_minutes cap, reconciliation_
-- status=mismatch/reconciled_actual_minutes=195, eligible/approved capped
-- to 180 by the policy -- confirming this fix must key off the ACTUAL
-- approved_minutes value, never a hand-derived "raw span minus policy
-- baseline" shortcut), no timesheet entry. Pre-this-fix (20260731240000's
-- own shipped shape): app.payroll_input_snapshots.regular_minutes = 0 for
-- this employee/period -- the day's real 555 worked-and-unclaimed minutes
-- (735 raw - 180 approved overtime) paid nothing at all.
--
-- ===========================================================================
-- Fix: subtract, never blanket-exclude.
-- ===========================================================================
--
-- v_covered_dates (dates EXCLUDED entirely from the attendance-session
-- fallback) reverts to ONLY timesheet_entries-covered dates -- unchanged
-- from the function's ORIGINAL (pre-ISS-2026-105, 20260731000000) scope,
-- because a timesheet_entries row's own approved_minutes genuinely IS the
-- correct, complete regular-minutes figure for that work_date (a human
-- explicitly timesheeted the day) -- full exclusion is correct there, and
-- was never the defect.
--
-- A work_date covered by an APPROVED app.overtime_requests row but NO
-- timesheet entry is no longer excluded outright. Instead, step 2's own
-- attendance-fallback query now subtracts that SAME work_date's own
-- already-claimed approved_minutes from the session's raw span before
-- summing, floored at zero: greatest(0, raw_span - overtime_minutes). This
-- directly implements ISS-2026-105's own original "pay the real regular
-- portion" definition of correct, using the ACTUAL, real approved_minutes
-- value already computed and trusted elsewhere in this SAME function (the
-- v_ts_ow/v_ts_owe/v_ts_oh aggregation two queries above) -- never a
-- second, independent "standard workday minutes" config value.
--
-- This is deliberately NOT the "capping" alternative 20260731240000's own
-- header evaluated and rejected (min(raw_span, standard_workday_minutes)),
-- and neither of that header's own two rejected-capping reasons apply to
-- subtraction:
--   1. "Ambiguous source" (attendance_policy_versions.workday_start_time/
--      end_time vs overtime_policy_versions.standard_workday_minutes,
--      genuinely different values in this schema) does not apply --
--      subtraction reads NEITHER config value. It reads only the SAME
--      overtime_requests.approved_minutes column already trusted for the
--      overtime totals themselves, for the SAME work_date.
--   2. "Not double-count-safe for a full-day-holiday shift" does not apply
--      either -- if approved_minutes for a work_date meets or exceeds that
--      day's own raw attendance span (the exact full-day-holiday-overtime
--      case the rejected capping alternative could not handle safely),
--      greatest(0, raw_span - approved_minutes) correctly floors to ZERO,
--      never a "capped regular portion counted a second time on top of its
--      own full overtime_holiday_minutes" -- the day's minutes are either
--      fully consumed by the (already-counted) overtime figure, or a real,
--      genuinely-uncompensated remainder is paid once, never both.
--
-- At most one active/approved app.overtime_requests row can exist per
-- (tenant_id, employee_id, work_date) -- overtime_requests_employee_
-- workdate_active_unique (20260730980000) -- so the per-work_date minutes
-- map built below is unambiguous by construction, never an aggregation
-- choice.
--
-- Regression fixture (own, new -- see scripts/db-tests/hris-payroll.sql's
-- own updated ISS-2026-105 block): the EXISTING emp3 fixture's own
-- assertions are corrected in place to their genuinely correct values
-- (regular_minutes=1020 = 480 day B + 540 day A's real non-overtime
-- portion [690-150]; gross/net=850,000 IDR, never 400,000), and a NEW,
-- second employee (emp5) fixture is added proving the full-day-overtime
-- edge case 20260731240000's own header worried about (approved_minutes
-- >= raw_span) correctly floors to zero contribution, never a negative or
-- a second counted portion.
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
  v_overtime_minutes_by_date jsonb := '{}'::jsonb;
  v_att_regular integer := 0;
  v_att_ids uuid[] := array[]::uuid[];
begin
  -- Step 1: every ACTIVE app.payroll_time_inputs row whose own timesheet
  -- period OVERLAPS the payroll period at all contributes ONLY the
  -- per-work-date regular minutes for the timesheet_entries it actually
  -- backs whose own work_date falls inside [p_period_start, p_period_end].
  -- Unchanged from 20260731000000/20260731240000.
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

  -- Same overlap/work-date scoping for overtime -- unchanged from
  -- 20260731000000/20260731240000.
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

  -- Tier C fix (this migration): v_covered_dates reverts to ONLY
  -- timesheet_entries-covered work_dates -- a timesheet_entries row's own
  -- approved_minutes genuinely IS the day's complete, correct regular
  -- figure, so full exclusion from the attendance fallback below remains
  -- correct and unchanged here.
  select coalesce(array_agg(distinct te.work_date), array[]::date[]) into v_covered_dates
  from app.payroll_time_inputs pti
  join app.timesheet_periods tp on tp.id = pti.timesheet_period_id
  join app.timesheet_entries te on te.id = any (pti.source_entry_ids)
  where pti.tenant_id = p_tenant_id and pti.employee_id = p_employee_id and pti.status = 'active'
    and tp.period_start <= p_period_end and tp.period_end >= p_period_start
    and te.work_date between p_period_start and p_period_end
    and te.status = 'approved';

  -- Tier C fix (this migration): work_dates covered by an APPROVED
  -- overtime_requests row but NOT already covered by a timesheet entry
  -- (the exact ISS-2026-105 double-count shape) are captured here WITH
  -- their own real approved_minutes, keyed by work_date -- never simply
  -- excluded. At most one approved/active overtime_requests row can exist
  -- per (employee, work_date) (overtime_requests_employee_workdate_active_
  -- unique, 20260730980000), so this map is unambiguous.
  select coalesce(jsonb_object_agg(ot.work_date, ot.approved_minutes), '{}'::jsonb) into v_overtime_minutes_by_date
  from app.payroll_time_inputs pti
  join app.timesheet_periods tp on tp.id = pti.timesheet_period_id
  join app.overtime_requests ot on ot.id = any (pti.source_overtime_request_ids)
  where pti.tenant_id = p_tenant_id and pti.employee_id = p_employee_id and pti.status = 'active'
    and tp.period_start <= p_period_end and tp.period_end >= p_period_start
    and ot.work_date between p_period_start and p_period_end
    and ot.status = 'approved'
    and not (ot.work_date = any (v_covered_dates));

  -- Step 2: approved attendance sessions for any work_date in range NOT
  -- covered by a timesheet entry. A work_date ALSO covered by an approved
  -- overtime request (v_overtime_minutes_by_date) now contributes its own
  -- raw span MINUS that day's already-claimed overtime minutes, floored at
  -- zero -- the day's real, non-overtime regular portion, never double-
  -- counted (the overtime slice is already counted once, above, via
  -- v_ts_ow/v_ts_owe/v_ts_oh) and never zeroed outright. An uncontested
  -- work_date (covered by neither timesheet nor overtime) is unaffected --
  -- coalesce(..., 0) against a map with no entry for that date is a no-op
  -- subtraction, contributing its full raw span exactly as the ORIGINAL,
  -- pre-ISS-2026-105 function always did.
  select
    coalesce(sum(
      greatest(0,
        greatest(0, round(extract(epoch from (s.effective_clock_out_at - s.effective_clock_in_at)) / 60))
        - coalesce((v_overtime_minutes_by_date ->> s.work_date::text)::integer, 0)
      )
    )::integer, 0),
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
  'HRT-282 (decision 2, ISS-2026-074 resolution): a work_date contributes through exactly one source, never both, computed per-work-date from the underlying timesheet_entries/overtime_requests rows and scoped to [p_period_start, p_period_end]. HRT-295 (ISS-2026-105 resolution, CRITICAL): a work_date covered by an approved overtime_requests row with no timesheet entry no longer double-counts its raw attendance span. Tier C review fix (20260731280000, same finding, residual gap all four review lenses independently confirmed): that overtime-covered day is no longer EXCLUDED outright (which zeroed a real, worked, non-overtime regular portion) -- its attendance-fallback contribution is now raw_span minus that day''s own real approved overtime minutes, floored at zero, matching ISS-2026-105''s own original "pay the real regular portion" definition of correct. service_role only -- called exclusively from app._build_payroll_input_snapshot_for_employee.';
