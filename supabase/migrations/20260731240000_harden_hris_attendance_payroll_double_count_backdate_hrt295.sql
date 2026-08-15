-- Phase 7 (HRIS and Ticketing) hardening -- Prompt 295 (CG-S12-HRT-023),
-- repair group "Attendance/Payroll time accuracy". Closes the two HRT-294
-- (Prompt 294) findings owned by this group, both scoped explicitly to
-- Prompt 295 in docs/runtime/KNOWN_ISSUES.md:
--
--   ISS-2026-105 (CRITICAL) -- app._resolve_payroll_time_inputs_for_period's
--   own covered-dates derivation excluded a work_date from the attendance-
--   session regular-minutes fallback ONLY when a Timesheet entry covered
--   it -- never when an APPROVED Overtime request covered it instead (no
--   timesheet entry). A work_date carrying both a real attendance session
--   and an approved overtime request was therefore counted TWICE: once via
--   its own full raw attendance span inside regular_minutes, once again via
--   overtime_weekday/weekend/holiday_minutes -- a live, real monetary
--   overstatement that reached a FINALIZED payroll run and its Finance
--   handoff with zero warning anywhere (live-reproduced: 125,000 IDR for
--   one employee, one pay period, from one overtime day).
--
--   ISS-2026-106 (High) -- app._ingest_attendance_event stamped work_date/
--   raw_clock_in_at/raw_clock_out_at from clock_timestamp() (the real
--   server "now") unconditionally, on EVERY channel -- including manual_hr
--   (HR backdated correction) and device_import (legacy batch import),
--   whose entire stated purpose is to represent a DIFFERENT, already-past
--   calendar day. The caller-supplied p_client_reported_at parameter was
--   captured only into the audit-only attendance_events.client_reported_at
--   column, never read back -- a manual/imported historical timestamp had
--   ZERO functional effect, and a single manual_hr/device_import caller
--   could not even record more than one attendance day per real calendar
--   day (duplicate_workday_session on the second call).
--
-- Fixed in this order (ISS-2026-106 first) because a correctly-backdated
-- attendance session, produced via the now-fixed app.record_manual_
-- attendance_event, is exactly the real, non-workaround-requiring fixture
-- ISS-2026-105's own regression proof needs (an attendance session and an
-- approved overtime request on the SAME work_date, with NO raw-UPDATE
-- fixture hack to force the date, unlike the pre-existing ISS-2026-074
-- fixture in scripts/db-tests/hris-payroll.sql, which predates this fix).
--
-- Both functions are extended via CREATE OR REPLACE FUNCTION, IDENTICAL
-- signatures, mirroring this repository's own established "never break an
-- existing caller/grant" discipline (used identically by the
-- 20260730920000 migration when it extended this SAME app._ingest_
-- attendance_event for HRT-279). No new GRANT statements are needed --
-- Postgres preserves existing privileges across CREATE OR REPLACE FUNCTION
-- when the signature does not change.

-- ===========================================================================
-- Fix A (ISS-2026-106, High) -- app._ingest_attendance_event.
--
-- Root cause: v_now (clock_timestamp()) was used unconditionally for
-- v_work_date/raw_clock_in_at/raw_clock_out_at on every source_channel.
--
-- Fix: a new v_effective_at value is computed ONCE, branching on
-- p_source_channel -- the exact parameter every one of the four channels
-- (mobile_web, kiosk, manual_hr, device_import) already passes explicitly
-- and app._ingest_attendance_event already gates other behavior on
-- (channel allowlist bypass, geofence exemption, both pre-existing). For
-- manual_hr/device_import, the caller-supplied p_client_reported_at (a
-- non-null, required value at both real call sites -- app.record_manual_
-- attendance_event's own p_event_at_required guard and app.
-- validate_attendance_device_import_row's own event_at ISO-8601 check)
-- becomes the authoritative source for v_work_date/raw_clock_in_at/
-- raw_clock_out_at. For mobile_web/kiosk (the live self-service channels),
-- v_effective_at resolves to v_now exactly as before -- UNCHANGED, since
-- trusting a client-claimed time on a live capture channel would reopen
-- the anti-spoofing gap decision 10 of HRT-278's own build log deliberately
-- closed (a fabricated p_client_reported_at on those two channels is
-- already, correctly, inert -- this fix does not touch that property).
--
-- server_received_at (attendance_events, both INSERT statements) stays
-- v_now (clock_timestamp()) UNCONDITIONALLY on every channel -- it records
-- when the server actually processed the request, never a claimed event
-- time, exactly this function's own pre-existing, correct contract
-- ("server_received_at ... is always authoritative, never a client-supplied
-- timestamp" -- preserved verbatim in the comment below, now scoped
-- precisely to the field it always described).
--
-- The clock_out branch's own impossible_ordering guard is changed from
-- `v_now < v_session.raw_clock_in_at` to `v_effective_at <
-- v_session.raw_clock_in_at` -- comparing the SAME effective-time basis on
-- both sides (this clock-out call's own effective time against the
-- earlier clock-in's own stored raw_clock_in_at, which after this fix may
-- itself be a manual_hr/device_import effective time, not clock_timestamp())
-- -- required for the guard to keep meaning what its own error message
-- says, not a scope expansion: comparing a real wall-clock "now" against a
-- deliberately-backdated raw_clock_in_at would misfire (or fail to fire)
-- for the exact channels this fix targets.
--
-- Deliberately UNCHANGED (out of this finding's own scope, per KNOWN_
-- ISSUES.md's own citation of exactly three fields -- work_date/
-- raw_clock_in_at/raw_clock_out_at): the effective attendance policy is
-- still resolved against v_now ("today"), not v_effective_at -- a manual/
-- imported entry is evaluated under whichever attendance policy version is
-- effective AT ENTRY TIME, not whichever was effective on the claimed
-- historical date. Changing that is a separate, real design question (which
-- policy version should govern a backdated entry) this checkpoint's own
-- bounded mandate does not authorize; disclosed here rather than silently
-- folded in.
-- ===========================================================================

create or replace function app._ingest_attendance_event(
  p_employee app.employees,
  p_event_type text,
  p_source_channel text,
  p_client_reported_at timestamptz,
  p_location geography,
  p_idempotency_key text,
  p_raw_payload jsonb,
  p_source_staging_row_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  out v_event app.attendance_events
)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_existing app.attendance_events;
  v_policy app.attendance_policy_versions;
  v_work_date date;
  v_session app.attendance_sessions;
  v_now timestamptz := clock_timestamp();
  v_effective_at timestamptz;
  v_geofence_result text := 'not_evaluated';
  v_stored_location geography;
  v_location_source text := 'none';
  v_inside boolean;
  v_schedule_assignment_id uuid;
begin
  if p_employee.master_record_id is null then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;
  if p_employee.lifecycle_status <> 'active' then
    raise exception 'employee_not_active: employee % is %, only an active employee may record attendance', p_employee.master_record_id, p_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  -- HRT-295 (ISS-2026-106 resolution): manual_hr/device_import are NOT live
  -- self-service captures -- both already-required, caller-supplied
  -- p_client_reported_at now becomes the authoritative event time for
  -- those two channels specifically. mobile_web/kiosk are unaffected.
  v_effective_at := case
    when p_source_channel in ('manual_hr', 'device_import') and p_client_reported_at is not null
      then p_client_reported_at
    else v_now
  end;

  -- C-01: full-tuple idempotency replay -- compare the COMPLETE request, never
  -- the key alone.
  if p_idempotency_key is not null then
    select * into v_existing from app.attendance_events where tenant_id = p_employee.tenant_id and employee_id = p_employee.master_record_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.event_type = p_event_type and v_existing.source_channel = p_source_channel and v_existing.client_reported_at is not distinct from p_client_reported_at then
        v_event := v_existing;
        return;
      else
        raise exception 'idempotency_key_conflict: key % was already used for a different attendance event', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
    end if;
  end if;

  select * into v_policy from app.resolve_effective_attendance_policy_version(p_employee.tenant_id, p_employee.branch_org_unit_id, (v_now at time zone 'UTC')::date) limit 1;
  if not found then
    raise exception 'no_eligible_policy: no published attendance policy is effective for employee % as of %', p_employee.master_record_id, v_now
      using errcode = 'check_violation';
  end if;

  if p_source_channel <> 'manual_hr' and not (p_source_channel = any (v_policy.allowed_channels)) then
    raise exception 'channel_not_permitted: channel % is not permitted by the effective attendance policy', p_source_channel
      using errcode = 'check_violation';
  end if;

  -- Geofence evaluation (decision 4: structural minimization). Never applied to
  -- a manual_hr or device_import entry -- neither is a live self-service
  -- capture: manual_hr is HR keying in a past event with no physical presence
  -- to prove, authenticated by its own HRS:Edit authority instead (the same
  -- "manual_hr bypasses the channel allowlist" reasoning immediately above,
  -- applied to the location gate too); device_import reconciles an external
  -- device's own already-happened batch log (section 14/17's own "device/
  -- channel" framing), which this checkpoint's own schema carries as
  -- timestamp+badge data only, structurally never a coordinate (decision 6) --
  -- gated instead by HRS:Import authority at the commit RPC. Both entries'
  -- location_source/geofence_result stay 'none'/'not_evaluated', never a
  -- fabricated 'inside'.
  if p_source_channel not in ('manual_hr', 'device_import') and v_policy.location_enforcement_mode <> 'none' then
    if p_location is null then
      if v_policy.location_enforcement_mode = 'required' then
        raise exception 'location_required: the effective attendance policy requires a real, evaluated location' using errcode = 'check_violation';
      end if;
      -- advisory + missing: leave not_evaluated, store nothing.
    else
      v_inside := app.bounded_st_dwithin(p_location, v_policy.geofence_center, v_policy.geofence_radius_meters);
      v_geofence_result := case when v_inside then 'inside' else 'outside' end;
      v_stored_location := p_location;
      v_location_source := 'gps';
      if not v_inside and v_policy.location_enforcement_mode = 'required' then
        raise exception 'outside_geofence: location is outside the effective policy''s governed geofence -- never a fake success' using errcode = 'check_violation';
      end if;
    end if;
  end if;

  v_work_date := app.resolve_attendance_workday(v_effective_at, v_policy.timezone, v_policy.day_boundary_local_time);

  if p_event_type = 'clock_in' then
    if exists (select 1 from app.attendance_sessions where tenant_id = p_employee.tenant_id and employee_id = p_employee.master_record_id and status = 'open' for update) then
      raise exception 'duplicate_open_session: employee % already has an open attendance session -- clock out first', p_employee.master_record_id
        using errcode = 'check_violation';
    end if;
    if exists (select 1 from app.attendance_sessions where tenant_id = p_employee.tenant_id and employee_id = p_employee.master_record_id and work_date = v_work_date) then
      raise exception 'duplicate_workday_session: employee % already has an attendance session for %', p_employee.master_record_id, v_work_date
        using errcode = 'check_violation';
    end if;

    insert into app.attendance_events (
      tenant_id, employee_id, event_type, source_channel, client_reported_at, server_received_at,
      location, location_source, geofence_result, policy_version_id, raw_payload, source_import_staging_row_id, idempotency_key, created_by
    ) values (
      p_employee.tenant_id, p_employee.master_record_id, p_event_type, p_source_channel, p_client_reported_at, v_now,
      v_stored_location, v_location_source, v_geofence_result, v_policy.id, p_raw_payload, p_source_staging_row_id, p_idempotency_key, p_actor_label
    ) returning * into v_event;

    -- HRT-279 decision 1/2: resolve the PUBLISHED schedule assignment (if
    -- any) for this employee/work_date, once, at session-creation time.
    select id into v_schedule_assignment_id from app.resolve_effective_schedule_assignment(p_employee.tenant_id, p_employee.master_record_id, v_work_date) limit 1;

    insert into app.attendance_sessions (
      tenant_id, employee_id, work_date, timezone, policy_version_id, status, clock_in_event_id, raw_clock_in_at, schedule_assignment_id
    ) values (
      p_employee.tenant_id, p_employee.master_record_id, v_work_date, v_policy.timezone, v_policy.id, 'open', v_event.id, v_effective_at, v_schedule_assignment_id
    ) returning * into v_session;

    update app.attendance_events set session_id = v_session.id where id = v_event.id;
    v_event.session_id := v_session.id;

  elsif p_event_type = 'clock_out' then
    select * into v_session from app.attendance_sessions where tenant_id = p_employee.tenant_id and employee_id = p_employee.master_record_id and status = 'open' for update;
    if not found then
      raise exception 'no_open_session: employee % has no open attendance session to clock out of', p_employee.master_record_id
        using errcode = 'check_violation';
    end if;
    if v_effective_at < v_session.raw_clock_in_at then
      raise exception 'impossible_ordering: clock-out time precedes clock-in time for session %', v_session.id
        using errcode = 'check_violation';
    end if;

    insert into app.attendance_events (
      tenant_id, employee_id, event_type, source_channel, client_reported_at, server_received_at,
      location, location_source, geofence_result, policy_version_id, session_id, raw_payload, source_import_staging_row_id, idempotency_key, created_by
    ) values (
      p_employee.tenant_id, p_employee.master_record_id, p_event_type, p_source_channel, p_client_reported_at, v_now,
      v_stored_location, v_location_source, v_geofence_result, v_policy.id, v_session.id, p_raw_payload, p_source_staging_row_id, p_idempotency_key, p_actor_label
    ) returning * into v_event;

    update app.attendance_sessions
    set status = 'closed', clock_out_event_id = v_event.id, raw_clock_out_at = v_effective_at
    where id = v_session.id
    returning * into v_session;
  else
    raise exception 'invalid_event_type: % is not a recognized attendance event type', p_event_type using errcode = 'check_violation';
  end if;

  if v_geofence_result = 'outside' then
    insert into app.attendance_exceptions (tenant_id, employee_id, session_id, exception_type, severity, detail)
    values (p_employee.tenant_id, p_employee.master_record_id, v_session.id, 'out_of_geofence', 'medium', jsonb_build_object('event_id', v_event.id, 'event_type', p_event_type))
    on conflict (session_id, exception_type) where status in ('open', 'acknowledged')
    do update set detail = excluded.detail;
  end if;

  perform app._recalculate_session_exceptions(v_session.id);

  perform app.capture_audit_event(
    p_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'ingest_attendance_event',
    'app.attendance_events', v_event.id, 'success', null, null,
    jsonb_build_object('event_type', p_event_type, 'source_channel', p_source_channel, 'session_id', v_session.id, 'geofence_result', v_geofence_result, 'schedule_assignment_id', v_schedule_assignment_id)
  );
end;
$$;

comment on function app._ingest_attendance_event is
  'HRT-278 (decision 6/10), extended by HRT-279 (decision 2), extended by HRT-295 (ISS-2026-106 resolution): the ONE shared ingestion engine every clock/manual/device-import write path calls. server_received_at (clock_timestamp()) is ALWAYS authoritative, every channel, never a client-supplied timestamp. work_date/raw_clock_in_at/raw_clock_out_at now come from the caller-supplied, already-required p_client_reported_at on the manual_hr/device_import channels specifically (v_effective_at) -- clock_timestamp() remains authoritative for those three fields on the live self-service mobile_web/kiosk channels, unchanged, preserving the anti-spoofing property decision 10 of HRT-278''s own build log established. Raises, never silently coerces, when location_enforcement_mode=required and the location is missing/outside (section 15''s "no fake location success or hidden failure"). Resolves and carries schedule_assignment_id (HRT-279) on the clock_in branch only -- null when no published roster assignment exists for this employee/work_date, never blocking.';

-- ===========================================================================
-- Fix B (ISS-2026-105, CRITICAL) -- app._resolve_payroll_time_inputs_for_period.
--
-- Root cause: v_covered_dates (the set of work_dates to EXCLUDE from the
-- attendance-session regular-minutes fallback in step 2) was derived
-- EXCLUSIVELY from app.timesheet_entries reachable via this active
-- app.payroll_time_inputs row's own source_entry_ids -- even though the
-- SAME row's source_overtime_request_ids (used two queries above, for the
-- overtime totals themselves) can cover a work_date with NO timesheet
-- entry at all. That work_date was therefore left OUT of v_covered_dates,
-- so step 2's attendance-fallback query (unchanged, still summing the
-- FULL raw clock span of every approved session not in v_covered_dates)
-- counted it a second time -- once as overtime (already correct), once
-- again as regular (the double-count).
--
-- Fix: v_covered_dates is now the UNION of (a) work_dates reachable via
-- approved timesheet_entries (unchanged query) and (b) work_dates
-- reachable via approved app.overtime_requests, through this SAME active
-- payroll_time_inputs row's own source_overtime_request_ids -- mirroring,
-- field-for-field and predicate-for-predicate, how the pre-existing
-- timesheet-entries exclusion already works (same pti/tp join shape, same
-- tp.period_start<=p_period_end and tp.period_end>=p_period_start overlap
-- guard, same work_date-between-period-bounds guard, status='approved' in
-- place of te.status='approved'). A work_date now contributes through
-- EXACTLY one of the three real sources (timesheet, overtime, or the
-- attendance fallback) -- never a fallback span on top of an already-
-- governed timesheet OR overtime figure -- making this migration''s own
-- parent header claim ("a work_date contributes through exactly one
-- source, never both, by construction") genuinely true for overtime-only
-- work_dates too, not merely for timesheet-covered ones.
--
-- Capping evaluated, not implemented (Prompt 295 instruction: "evaluate...
-- implement if genuinely reachable without disproportionate scope
-- increase, otherwise state clearly..."): capping the attendance-fallback
-- session span at a "standard workday minutes" figure instead of (or in
-- addition to) this exclusion was considered. Rejected as NOT a sound
-- general substitute or supplement, for two concrete reasons found by
-- reading the real schema/functions, not asserted from principle alone:
--   1. Ambiguous source. Two INDEPENDENT, separately-configurable "standard
--      workday" figures already exist in this schema and can genuinely
--      differ -- app.attendance_policy_versions.workday_start_time/
--      workday_end_time (an Attendance-owned figure) versus app.
--      overtime_policy_versions.standard_workday_minutes (an Overtime-
--      owned figure, the ACTUAL baseline app._reconcile_overtime_request_
--      actual uses to compute an overtime request''s own reconciled/
--      eligible minutes). scripts/db-tests/hris-overtime-timesheet.sql''s
--      own existing fixture sets these to DIFFERENT values (540 vs 480
--      minutes) for the SAME tenant. Which one a payroll-side cap should
--      read is a genuine, undecided design fork, not a one-line addition.
--   2. Not double-count-safe even if the source ambiguity were resolved.
--      A blind cap (min(raw_span, standard_workday_minutes)) does not
--      subtract whatever portion of that SAME raw span an approved
--      overtime request already separately claims -- a work_date entirely
--      approved as overtime (e.g. a full holiday shift, eligible_
--      classification=''holiday'', a real, reachable case this schema
--      supports) would still have its capped "regular" portion counted a
--      SECOND time on top of its own full overtime_holiday_minutes -- a
--      smaller-magnitude but still-real instance of the exact defect this
--      fix closes. A capped fallback is therefore not safe to trust as a
--      no-double-count guarantee on its own, and combining it correctly
--      with per-work-date overtime-minute subtraction is a materially
--      larger, novel formula change touching the general (non-double-
--      counted) fallback path every other already-VERIFIED payroll
--      fixture also depends on -- disproportionate to this bounded repair.
-- The exclusion fix above is therefore the primary, MANDATORY, and
-- sufficient fix: it is unconditionally double-count-safe (a work_date is
-- either governed -- timesheet or overtime -- or it falls through to the
-- attendance fallback, never both), including the full-day-overtime edge
-- case capping alone would still mishandle. See docs/db-tests/
-- hris-payroll.sql''s own new ISS-2026-105 regression block for the live,
-- real-money-shaped proof.
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

  -- HRT-295 (ISS-2026-105 resolution): v_covered_dates is now the UNION of
  -- every work_date actually contributed above -- via APPROVED
  -- timesheet_entries (unchanged half, matches the ORIGINAL function's own
  -- scope) OR via an APPROVED overtime_requests row reachable through this
  -- SAME active payroll_time_inputs row's own source_overtime_request_ids
  -- (the fix -- previously omitted entirely, the root cause of the
  -- double-count). The attendance fallback below (step 2, its own query
  -- text UNCHANGED) therefore never fills a work_date already covered by
  -- EITHER governed source, closing the double-count at its root.
  select coalesce(array_agg(distinct wd), array[]::date[]) into v_covered_dates
  from (
    select te.work_date as wd
    from app.payroll_time_inputs pti
    join app.timesheet_periods tp on tp.id = pti.timesheet_period_id
    join app.timesheet_entries te on te.id = any (pti.source_entry_ids)
    where pti.tenant_id = p_tenant_id and pti.employee_id = p_employee_id and pti.status = 'active'
      and tp.period_start <= p_period_end and tp.period_end >= p_period_start
      and te.work_date between p_period_start and p_period_end
      and te.status = 'approved'
    union
    select ot.work_date as wd
    from app.payroll_time_inputs pti
    join app.timesheet_periods tp on tp.id = pti.timesheet_period_id
    join app.overtime_requests ot on ot.id = any (pti.source_overtime_request_ids)
    where pti.tenant_id = p_tenant_id and pti.employee_id = p_employee_id and pti.status = 'active'
      and tp.period_start <= p_period_end and tp.period_end >= p_period_start
      and ot.work_date between p_period_start and p_period_end
      and ot.status = 'approved'
  ) covered;

  -- Step 2: approved attendance sessions for any work_date in range NOT
  -- already covered by step 1 -- regular minutes ONLY, never overtime.
  -- (query text unchanged from the original function -- only the meaning
  -- of v_covered_dates, above, has widened.)
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
  'HRT-282 (decision 2, ISS-2026-074 resolution). Tier C fix (integration lens Finding 1, LIVE-CONFIRMED end to end): a work_date contributes through exactly one source, never both, computed per-work-date from the underlying timesheet_entries/overtime_requests rows and scoped to [p_period_start, p_period_end]. HRT-295 (ISS-2026-105 resolution, CRITICAL, LIVE-CONFIRMED real-money double-count): v_covered_dates now also excludes any work_date covered by an APPROVED overtime_requests row (previously only timesheet_entries-covered dates were excluded, so an overtime-only work_date with no timesheet entry was double-counted -- once as its own full raw attendance span, once as overtime). service_role only -- called exclusively from app._build_payroll_input_snapshot_for_employee.';
