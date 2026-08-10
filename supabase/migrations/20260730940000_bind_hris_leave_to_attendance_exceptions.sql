-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-008 (Leave, Permit and
-- Business Trip, Prompt 280) -- binding migration, the exact additive shape
-- HRT-279's own 20260730920000 established: a SEPARATE, LATER migration that
-- extends a PRE-EXISTING function via CREATE OR REPLACE FUNCTION (identical
-- signature, every unrelated line unchanged) rather than editing an
-- already-applied migration directly (AGENTS.md "never edit an applied
-- migration; add a new migration").
--
-- Closes decision 10 of 20260730930000: attendance-exception suppression for
-- an approved leave/permit/business-trip day (task binding instruction: "a
-- day on approved leave should not register as an attendance exception").
-- app._recalculate_session_exceptions (HRT-278) is extended to consult
-- app.leave_requests (this checkpoint's own new table, HRT-280) --
-- structurally optional and read-only from Attendance's own perspective: a
-- tenant with zero Leave/Permit adoption (zero rows in app.leave_requests)
-- sees ZERO behavior change, exactly HRT-279's own "structurally optional"
-- framing for its identical attendance-binding migration.
--
-- day_portion semantics (mirrors 20260730930000's own leave_requests.
-- day_portion CHECK exactly, disclosed V1 simplification): 'full_day'
-- suppresses ALL THREE exception types (late/early_leave/missing_clock_out)
-- for that session -- the whole day is excused, whatever clock activity
-- still happened is incidental; 'half_day_morning' suppresses 'late' only
-- (the employee was excused for the morning, so a late arrival is expected,
-- not exceptional); 'half_day_afternoon' suppresses 'early_leave' only. Any
-- PRE-EXISTING open/acknowledged exception of a suppressed type is actively
-- resolved (resolved_by='system'), never merely skipped going forward --
-- symmetric with the function's own established "resolves an exception whose
-- condition no longer holds" behavior for every other branch.
--
-- The lookup is `limit 1` deliberately, not defensively: 20260730930000's own
-- leave_requests_no_overlap EXCLUDE constraint makes more than one
-- pending_approval-or-approved request covering the SAME employee-date a
-- structural impossibility (decision 5) -- there is never more than one
-- 'approved' row to find for one (employee_id, work_date).

create or replace function app._recalculate_session_exceptions(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_session app.attendance_sessions;
  v_policy app.attendance_policy_versions;
  v_workday_start timestamptz;
  v_workday_end timestamptz;
  v_late_minutes numeric;
  v_early_minutes numeric;
  v_session_hours numeric;
  v_leave_portion text;
begin
  select * into v_session from app.attendance_sessions where id = p_session_id;
  if not found then
    return;
  end if;
  select * into v_policy from app.attendance_policy_versions where id = v_session.policy_version_id;

  -- HRT-280 binding: an approved leave/permit/business-trip request covering
  -- this session's own work_date, if any. null = no leave coverage, every
  -- branch below behaves exactly as HRT-278 originally shipped it.
  select r.day_portion into v_leave_portion
  from app.leave_requests r
  where r.tenant_id = v_session.tenant_id and r.employee_id = v_session.employee_id
    and r.status = 'approved' and r.date_from <= v_session.work_date and r.date_to >= v_session.work_date
  limit 1;

  -- An overnight-shift workday_end_time (< workday_start_time, e.g. start 22:00
  -- end 06:00) belongs to the FOLLOWING local calendar day.
  v_workday_start := (v_session.work_date::text || ' ' || v_policy.workday_start_time::text)::timestamp at time zone v_policy.timezone;
  v_workday_end := ((v_session.work_date + case when v_policy.workday_end_time < v_policy.workday_start_time then 1 else 0 end)::text || ' ' || v_policy.workday_end_time::text)::timestamp at time zone v_policy.timezone;

  -- late (HRT-280: suppressed by a full_day or half_day_morning approved
  -- leave covering this work_date)
  if v_leave_portion in ('full_day', 'half_day_morning') then
    update app.attendance_exceptions set status = 'resolved', resolved_at = now(), resolved_by = 'system'
    where session_id = p_session_id and exception_type = 'late' and status in ('open', 'acknowledged');
  elsif v_session.effective_clock_in_at is not null then
    v_late_minutes := extract(epoch from (v_session.effective_clock_in_at - (v_workday_start + (v_policy.grace_late_minutes || ' minutes')::interval))) / 60.0;
    if v_late_minutes > 0 then
      insert into app.attendance_exceptions (tenant_id, employee_id, session_id, exception_type, severity, detail)
      values (v_session.tenant_id, v_session.employee_id, p_session_id, 'late', case when v_late_minutes > 60 then 'high' else 'medium' end, jsonb_build_object('minutes_late', round(v_late_minutes)))
      on conflict (session_id, exception_type) where status in ('open', 'acknowledged')
      do update set detail = excluded.detail, severity = excluded.severity;
    else
      update app.attendance_exceptions set status = 'resolved', resolved_at = now(), resolved_by = 'system'
      where session_id = p_session_id and exception_type = 'late' and status in ('open', 'acknowledged');
    end if;
  end if;

  -- early_leave (HRT-280: suppressed by a full_day or half_day_afternoon
  -- approved leave covering this work_date)
  if v_leave_portion in ('full_day', 'half_day_afternoon') then
    update app.attendance_exceptions set status = 'resolved', resolved_at = now(), resolved_by = 'system'
    where session_id = p_session_id and exception_type = 'early_leave' and status in ('open', 'acknowledged');
  elsif v_session.effective_clock_out_at is not null then
    v_early_minutes := extract(epoch from ((v_workday_end - (v_policy.grace_early_minutes || ' minutes')::interval) - v_session.effective_clock_out_at)) / 60.0;
    if v_early_minutes > 0 then
      insert into app.attendance_exceptions (tenant_id, employee_id, session_id, exception_type, severity, detail)
      values (v_session.tenant_id, v_session.employee_id, p_session_id, 'early_leave', case when v_early_minutes > 60 then 'high' else 'medium' end, jsonb_build_object('minutes_early', round(v_early_minutes)))
      on conflict (session_id, exception_type) where status in ('open', 'acknowledged')
      do update set detail = excluded.detail, severity = excluded.severity;
    else
      update app.attendance_exceptions set status = 'resolved', resolved_at = now(), resolved_by = 'system'
      where session_id = p_session_id and exception_type = 'early_leave' and status in ('open', 'acknowledged');
    end if;
  end if;

  -- missing_clock_out (HRT-280: suppressed by a full_day approved leave --
  -- an employee excused for the entire day who never clocked in has no open
  -- session to begin with; this branch matters for the case where they
  -- clocked in before the leave was approved, or a correction later applies)
  if v_leave_portion = 'full_day' then
    update app.attendance_exceptions set status = 'resolved', resolved_at = now(), resolved_by = 'system'
    where session_id = p_session_id and exception_type = 'missing_clock_out' and status in ('open', 'acknowledged');
  elsif v_session.status = 'open' and v_session.effective_clock_in_at is not null
     and now() > v_session.effective_clock_in_at + (v_policy.max_session_hours || ' hours')::interval then
    v_session_hours := extract(epoch from (now() - v_session.effective_clock_in_at)) / 3600.0;
    insert into app.attendance_exceptions (tenant_id, employee_id, session_id, exception_type, severity, detail)
    values (v_session.tenant_id, v_session.employee_id, p_session_id, 'missing_clock_out', 'high', jsonb_build_object('open_hours', round(v_session_hours, 1)))
    on conflict (session_id, exception_type) where status in ('open', 'acknowledged')
    do update set detail = excluded.detail;
  elsif v_session.status = 'closed' then
    update app.attendance_exceptions set status = 'resolved', resolved_at = now(), resolved_by = 'system'
    where session_id = p_session_id and exception_type = 'missing_clock_out' and status in ('open', 'acknowledged');
  end if;
end;
$$;

comment on function app._recalculate_session_exceptions is
  'HRT-278: internal exception-detection engine, re-run after every clock event and every correction decision (decision, section 20''s own "define ... exception ... invariants"). Upserts per (session_id, exception_type), never duplicates; resolves an exception whose condition no longer holds, so exceptions always reflect CURRENT effective time. out_of_geofence/impossible_ordering are raised directly at ingest time (app._ingest_attendance_event), not recomputed here, since both depend on the ORIGINAL raw event, not the current effective time. Extended by HRT-280 (20260730940000, decision 10): late/early_leave/missing_clock_out are suppressed (and any pre-existing open/acknowledged row of that type actively resolved) when an approved app.leave_requests row covers this session''s own work_date -- structurally optional, zero behavior change for a tenant with no Leave/Permit adoption.';

-- app._recalculate_session_exceptions is service_role-only (unchanged from
-- HRT-278 -- CREATE OR REPLACE preserves the existing ACL, never
-- re-granted here, taxonomy C-11 "never restore a grant block as though it
-- were removed").
