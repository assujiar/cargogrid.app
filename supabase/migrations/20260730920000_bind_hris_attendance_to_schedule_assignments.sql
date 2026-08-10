-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-007 (Shift, Roster and
-- Scheduling, Prompt 279) -- the reservation point HRT-278's own migration
-- header (supabase/migrations/20260730900000_create_hris_attendance.sql,
-- decision 2) explicitly disclosed: "Prompt 279 is expected to add a new,
-- additive, nullable shift_id column and its own resolution function when it
-- ships." Kept as its OWN, separate migration file from
-- 20260730910000_create_hris_shift_roster_scheduling.sql (this checkpoint's
-- own new tables) so the rollback boundary of "Shift/Roster's own schema" and
-- "the binding into a sibling, already-applied capability's table" stay
-- independently reversible.
--
-- Design decisions:
--
-- 1. **Purely additive, structurally optional, zero behavior change for a
--    tenant that has not adopted Shift/Roster.** app.attendance_sessions
--    gains one new nullable column, schedule_assignment_id, populated ONLY
--    when app.resolve_effective_schedule_assignment (HRT-279) finds a
--    PUBLISHED assignment for the employee/work_date being clocked -- zero
--    rows found (the common case for any tenant not using Shift/Roster, or
--    for any employee/day it has not scheduled) leaves the column null,
--    exactly HRT-278's own original, already-tested behavior.
--
-- 2. **app._ingest_attendance_event is extended via CREATE OR REPLACE
--    FUNCTION, identical signature, every other line byte-for-byte
--    unchanged** -- mirrors HRT-278's own established "extends via CREATE OR
--    REPLACE FUNCTION... identical signatures... never weakening an existing
--    test" discipline (used there for app.cancel_import_export_job etc.,
--    itself mirroring PLT-132's own identical technique on PLT-131
--    functions). Only the clock_in branch is touched -- the schedule lookup
--    happens once, at session-creation time, and is carried on the session
--    row for its own lifetime (the same "resolved once, not re-resolved on
--    every read" discipline app._ingest_attendance_event already applies to
--    policy_version_id).
--
-- 3. **No new validation, no new blocking behavior.** This migration does
--    NOT make attendance ingestion depend on, or fail because of, a missing
--    or unpublished schedule assignment -- deliberately, to avoid a behavior
--    change to a sibling capability's already-tested write path within the
--    same batch. Deeper binding of exception-detection formulas (late/
--    early_leave) to a specific shift's own segment times is explicitly
--    reserved for a future checkpoint (this migration's own parent file,
--    20260730910000, decision 9).

alter table app.attendance_sessions add column schedule_assignment_id uuid references app.schedule_assignments (id);

comment on column app.attendance_sessions.schedule_assignment_id is
  'HRT-279: the PUBLISHED app.schedule_assignments row (if any) app.resolve_effective_schedule_assignment resolved for this employee/work_date at clock-in time. Null when Shift/Roster has not been adopted or no roster covers this employee/day -- never required, never backfilled retroactively by a later publish.';

create index attendance_sessions_schedule_assignment_idx on app.attendance_sessions (schedule_assignment_id) where schedule_assignment_id is not null;

-- Identical body to 20260730900000_create_hris_attendance.sql's own
-- app._ingest_attendance_event, with exactly one addition: resolving and
-- carrying schedule_assignment_id on the clock_in branch's own session
-- insert. Every other line, including every exception message and errcode,
-- is preserved verbatim.
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

  v_work_date := app.resolve_attendance_workday(v_now, v_policy.timezone, v_policy.day_boundary_local_time);

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
      p_employee.tenant_id, p_employee.master_record_id, v_work_date, v_policy.timezone, v_policy.id, 'open', v_event.id, v_now, v_schedule_assignment_id
    ) returning * into v_session;

    update app.attendance_events set session_id = v_session.id where id = v_event.id;
    v_event.session_id := v_session.id;

  elsif p_event_type = 'clock_out' then
    select * into v_session from app.attendance_sessions where tenant_id = p_employee.tenant_id and employee_id = p_employee.master_record_id and status = 'open' for update;
    if not found then
      raise exception 'no_open_session: employee % has no open attendance session to clock out of', p_employee.master_record_id
        using errcode = 'check_violation';
    end if;
    if v_now < v_session.raw_clock_in_at then
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
    set status = 'closed', clock_out_event_id = v_event.id, raw_clock_out_at = v_now
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
  'HRT-278 (decision 6/10), extended by HRT-279 (decision 2): the ONE shared ingestion engine every clock/manual/device-import write path calls -- server_received_at (clock_timestamp()) is always authoritative, never a client-supplied timestamp. Raises, never silently coerces, when location_enforcement_mode=required and the location is missing/outside (section 15''s "no fake location success or hidden failure"). Resolves and carries schedule_assignment_id (HRT-279) on the clock_in branch only -- null when no published roster assignment exists for this employee/work_date, never blocking.';

-- Grant unchanged -- app._ingest_attendance_event remains service_role-only,
-- called exclusively from within this repository's own already-authorized
-- SECURITY DEFINER functions (HRT-278 decision 6's own "internal, no direct
-- authenticated grant" convention, unaffected by this migration).
