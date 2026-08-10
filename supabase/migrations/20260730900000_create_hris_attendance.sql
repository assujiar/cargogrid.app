-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-006 (Attendance, Prompt 278)
-- -- the FIRST of the 3-prompt Tier-C batch HRT-278..280 (Attendance / Shift-Roster
-- / Leave-Permit-Business-Trip; batch capped at 3 per
-- docs/standards/BUILD_EXECUTION_PROTOCOL.md section 3.4, since the immediately
-- preceding batch (HRT-277) closed its own Tier C with 7 Critical/High findings).
-- Builds online-first attendance capture (clock-in/out), server-authoritative
-- policy-bound exception detection, and governed correction against
-- app.employees (HRT-274) and app.org_units (HRT-275/ADR-0023 Part A) -- never a
-- second employee/organization root.
--
-- Design decisions, disclosed rather than left implicit (this build's standing
-- discipline, mirrors every prior HRT checkpoint's own header shape):
--
-- 1. **Break/rest-period events are explicitly OUT of this checkpoint's scope.**
--    Prompt 278's own main flow (section 21) describes exactly two employee
--    actions -- clock in, clock out -- never a break/rest event. event_type is
--    therefore a closed set of exactly ('clock_in', 'clock_out'). Break-deduction
--    rules are a natural, additive extension for a future checkpoint (most
--    plausibly Prompt 281, Overtime and Timesheet, which already owns
--    time-computation rules this domain does not), never retrofitted here
--    speculatively -- the same "reserve the field, do not build the future
--    capability" discipline HRT-274's own decision 3 established for
--    position_title/position_id.
--
-- 2. **Shift/Roster (Prompt 279) does not exist yet and is not anticipated by
--    schema here.** "Effective shift" (section 21) is satisfied by
--    app.attendance_policy_versions' own workday_start_time/workday_end_time
--    (a single tenant- or branch-wide daily window), not a per-employee roster
--    assignment -- the real per-employee shift-roster table is Prompt 279's own
--    chartered scope. app.attendance_sessions carries no shift_id column at all
--    (not even a placeholder) because a foreign key to a table that does not yet
--    exist cannot be added correctly in advance -- Prompt 279 is expected to add
--    a new, additive, nullable shift_id column and its own resolution function
--    when it ships, mirroring HRT-275's own precedent of adding
--    app.employees.position_id additively once Position/Grade existed. Disclosed,
--    not silently narrowed.
--
-- 3. **Policy is versioned, tenant- or branch-scoped, and resolved by effective
--    date -- a bespoke table, not PLT-121's Configuration Engine.** Mirrors
--    HRT-277's own decision 7 (checklist templates) reasoning exactly: workday/
--    timezone/grace/geofence rules are a small, strongly-typed, validated
--    structure (a raw geography point + radius, a time-of-day pair, bounded
--    integers) that benefits from real CHECK constraints and a governed
--    geography column -- not a flat jsonb key/value payload. app.attendance_
--    policies is the scope pointer (tenant-wide when org_unit_id is null, or
--    scoped to one branch/org-unit node otherwise); app.attendance_policy_
--    versions is the actual effective-dated ruleset, following the exact
--    parent/version/publish shape every prior Governed Engine in this repository
--    already uses (rate_version, job_offer_version, checklist_template_version).
--
-- 4. **Location/device data is minimized structurally, not merely
--    documented (section 16).** app.attendance_events.location is populated
--    ONLY when the resolved policy's own location_enforcement_mode is
--    'advisory' or 'required' -- when a policy is 'none' (the common case for a
--    back-office role with no geofence requirement), any location coordinate a
--    client happens to send is discarded before it ever reaches a stored column,
--    never merely left unused. geofence_result ('inside'/'outside'/
--    'not_evaluated') is a coarse derived classification, safe to expose to any
--    HRS:View holder; the raw geography point itself is masked to the same
--    self-or-HRS:View-personal-data bar every other HRT checkpoint already
--    established for personal fields (app.employees' own v_is_self pattern,
--    reused, never reimplemented). Geofence evaluation itself applies ONLY to
--    the two live, self-service channels (mobile_web/kiosk) -- a manual_hr entry
--    (HR keying a past event with nothing to prove physically, gated on its own
--    HRS:Edit authority instead) and a device_import row (an external device's
--    own already-happened batch log, this checkpoint's own staging schema
--    carries no coordinate field at all) are both structurally exempt, a real,
--    self-found gap this checkpoint's own adversarial testing caught (see the
--    build log): an early draft applied the geofence gate uniformly and a
--    required-geofence policy made every manual HR correction and every device
--    import row unconditionally fail.
--
-- 5. **Corrections are a direct, permission-gated propose/decide workflow --
--    NOT routed through PLT-123's Approval Engine.** Considered and rejected:
--    HRT-276/277 both route their (comparatively rare, high-stakes) approvals
--    through app.request_approval, which REQUIRES a tenant to have already
--    published a config_type_code='approval' routing definition or every call
--    fails outright (approval_definition_not_configured). Attendance
--    corrections are a routine, potentially high-volume, low-single-stakes HR
--    workflow (an employee forgot to clock out yesterday) that must keep working
--    even for a tenant that has not yet configured PLT-123 approval routing for
--    an unrelated domain -- exactly HRT-275's own already-established
--    app.employee_position_assignments shape (propose under HRS:Edit, decide
--    under HRS:Approve, on the SAME row, record_version-guarded), reused here
--    directly rather than reinvented or forced through the heavier engine.
--
-- 6. **Device import reuses the real PLT-131/132 staged-import pipeline exactly
--    -- the sixth-plus adopter after PRC-255/HRT-274 (vendor_rate_import/
--    employee_import).** app.register_import_export_schema/app.create_import_
--    export_job/app.stage_import_rows are called UNCHANGED; only the domain-
--    specific validate/commit pair (app.validate_attendance_device_import_row,
--    app.commit_attendance_device_import_job) is new, and BOTH the live
--    self-service clock path and the device-import commit path route through
--    the SAME internal ingestion engine (app._ingest_attendance_event) so
--    server-side validation of employee/policy/timestamp/ordering is identical
--    on both paths -- never two independently-hardened write paths (the exact
--    shape this repository's own review rounds have repeatedly found drifting).
--
-- 7. **Exception recalculation is a bounded, synchronous RPC, not a literal
--    background-worker job.** Section 17 names "async ... exception
--    recalculation" as a performance requirement. This repository has NO live
--    job worker anywhere yet that dequeues app.jobs (standing, repeatedly
--    disclosed gap, ISS-2026-015) -- enqueuing a job nothing will ever claim
--    would not actually be async, only a permanently-pending row, exactly the
--    shape HRT-277's own onboarding-provisioning jobs already are (real work
--    done synchronously in the same call; the job row is a tracking artifact,
--    never dequeued). Rather than repeat that same disclosed shape, app.
--    recalculate_attendance_exceptions_for_range runs synchronously and is
--    explicitly bounded (a hard 92-day range cap, section 17's own "no
--    unbounded... scan" instruction), matching AGENTS.md's own "add async/
--    partition/read-model machinery only after measured need." If real tenant
--    volume later proves this insufficient, app.enqueue_job/app.claim_next_job
--    (PLT-132) is the already-proven primitive to route through then -- not
--    invented here as an unreachable, undequeued placeholder.
--
-- 8. **Sensitive free-text fields are column-restricted from THIS, the FIRST,
--    migration** (never retrofitted -- the exact defect class HRT-276's own
--    Tier C review found and had to fix after the fact): app.attendance_events.
--    location/raw_payload, app.attendance_correction_requests.reason/
--    decided_reason, app.attendance_exceptions.waive_reason/resolution_note are
--    excluded from the plain `authenticated` column grant applied in this
--    migration's own first grant block, masked in every read RPC to the same
--    self-or-HRS:View-personal-data bar as app.employees' own personal fields.
--
-- 9. **Cancel genuinely cancels, never leaves a dependent process live.** A
--    correction request cancelled or rejected while it was the sole reason a
--    linked exception was 'pending_correction' returns that exception to
--    'open', never leaves it silently stranded in a state implying resolution
--    is already in flight when it is not (HRT-276 section 12.4/HRT-277 section
--    12.7's own repeatedly-found "dependent in-flight process not cancelled"
--    class, designed against here from the start, not retrofitted).
--
-- 10. **Anti-spoofing is structural, not a parameter check.** app.record_
--     attendance_clock_event carries NO p_employee_id parameter at all -- the
--     acting employee is resolved exclusively from the caller's own validated
--     auth_user_id -> app.users -> app.employees linkage (app.get_self_
--     employee), so there is no field for a self-service caller to spoof in the
--     first place (section 16's "prevent spoofed IDs"). Only the separate,
--     HRS:Edit-permission-gated app.record_manual_attendance_event accepts an
--     explicit target employee, exactly the "employees act only for self unless
--     explicit HR authority" split section 16 requires.
--
-- 11. **RBAC.** Zero new app.permissions rows -- the eleven HRS actions HRT-274
--     already seeded (View/Create/Edit/Delete/Approve/Export/View personal
--     data/Reject/Import/Download/Override) cover every write this checkpoint
--     performs. waive_attendance_exception and manual out-of-policy correction
--     approval both require HRS:Override (the same bar app.terminate_employee
--     and HRT-277's own waive/cancel actions use), never merely HRS:Edit --
--     the authority-bar-mismatch class HRT-277's Tier C review found as its
--     single worst finding (section 12.1) was designed against from the start
--     by matching blast radius, not surface category, for every write below.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement
-- before its final grants, the standing per-migration convention since PLT-118.

-- ===========================================================================
-- 1. app.attendance_policies -- scope pointer (tenant-wide when org_unit_id is
--    null, or scoped to one org_unit node otherwise -- decision 3).
-- ===========================================================================

create table app.attendance_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid references app.org_units (id),
  name text not null,
  status text not null default 'draft',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_policies_name_check check (length(trim(name)) > 0),
  constraint attendance_policies_status_check check (status in ('draft', 'published', 'archived'))
);

comment on table app.attendance_policies is
  'HRT-278 (decision 3): tenant- or org_unit-scoped attendance policy scope pointer. org_unit_id null = tenant-wide fallback; non-null = binds to one app.org_units node (any unit_type, most realistically branch). Never a second organization hierarchy.';

create unique index attendance_policies_tenant_org_unit_unique on app.attendance_policies (tenant_id, org_unit_id) where org_unit_id is not null;
create unique index attendance_policies_tenant_wide_unique on app.attendance_policies (tenant_id) where org_unit_id is null;
create index attendance_policies_tenant_status_idx on app.attendance_policies (tenant_id, status);

-- ===========================================================================
-- 2. app.attendance_policy_versions -- the actual effective-dated ruleset.
-- ===========================================================================

create table app.attendance_policy_versions (
  id uuid primary key default gen_random_uuid(),
  policy_id uuid not null references app.attendance_policies (id),
  tenant_id uuid not null references app.tenants (id),
  version_number integer not null,
  status text not null default 'draft',
  effective_from date not null,
  timezone text not null,
  workday_start_time time not null,
  workday_end_time time not null,
  day_boundary_local_time time not null default '00:00:00',
  grace_late_minutes integer not null default 0,
  grace_early_minutes integer not null default 0,
  allowed_channels text[] not null default array['mobile_web', 'kiosk']::text[],
  location_enforcement_mode text not null default 'none',
  geofence_center geography (point, 4326),
  geofence_radius_meters numeric,
  max_session_hours numeric not null default 16,
  published_at timestamptz,
  published_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_policy_versions_status_check check (status in ('draft', 'published', 'superseded')),
  constraint attendance_policy_versions_grace_late_check check (grace_late_minutes >= 0 and grace_late_minutes <= 240),
  constraint attendance_policy_versions_grace_early_check check (grace_early_minutes >= 0 and grace_early_minutes <= 240),
  constraint attendance_policy_versions_max_session_check check (max_session_hours > 0 and max_session_hours <= 48),
  constraint attendance_policy_versions_location_mode_check check (location_enforcement_mode in ('none', 'advisory', 'required')),
  constraint attendance_policy_versions_geofence_shape_check check (
    location_enforcement_mode = 'none' or (geofence_center is not null and geofence_radius_meters is not null and geofence_radius_meters > 0)
  ),
  constraint attendance_policy_versions_geofence_valid_check check (geofence_center is null or app.validate_geography_point(geofence_center)),
  constraint attendance_policy_versions_channels_check check (
    allowed_channels <@ array['mobile_web', 'kiosk', 'device_import']::text[] and array_length(allowed_channels, 1) > 0
  ),
  constraint attendance_policy_versions_published_shape_check check (
    (status <> 'published') or (published_at is not null and published_by is not null)
  ),
  constraint attendance_policy_versions_policy_effective_unique unique (policy_id, effective_from)
);

comment on table app.attendance_policy_versions is
  'HRT-278: effective-dated attendance ruleset (decision 3). geofence_center/geofence_radius_meters are required exactly when location_enforcement_mode <> ''none'' (structural CHECK, decision 4). Resolution (app.resolve_effective_attendance_policy_version) picks the branch-scoped published version over a tenant-wide one when both apply, then the greatest effective_from <= the target work_date.';

create index attendance_policy_versions_policy_idx on app.attendance_policy_versions (policy_id, status, effective_from desc);
create index attendance_policy_versions_geofence_gix on app.attendance_policy_versions using gist (geofence_center) where geofence_center is not null;

-- ===========================================================================
-- 3. Timezone/workday helpers (decision, ISS-2026-059's own UTC-midnight
--    lesson: compute entirely in LOCAL time, never in UTC calendar-date terms).
-- ===========================================================================

create function app.validate_iana_timezone(p_timezone text)
returns boolean
language sql
stable
as $$
  select exists (select 1 from pg_timezone_names where name = p_timezone);
$$;

comment on function app.validate_iana_timezone is
  'HRT-278: true if p_timezone is a real, currently-known IANA zone name (pg_timezone_names). Rejects a bare fixed UTC offset string masquerading as a zone.';

-- work_date is computed ENTIRELY in the policy''s own local time -- convert the
-- server timestamptz to a local naive timestamp first (time zone- and
-- DST-aware, since app.validate_iana_timezone requires a real IANA name, never
-- a fixed offset), THEN subtract the day-boundary offset, THEN take the date.
-- An overnight shift''s clock-in (e.g. 23:30 local) and its own later clock-out
-- (e.g. 02:00 local the following calendar day) compute to the SAME work_date
-- whenever day_boundary_local_time falls between them (e.g. 04:00) -- proven in
-- scripts/db-tests/hris-attendance.sql across a real UTC-midnight crossing,
-- direct lesson from ISS-2026-059 (PRC-264''s own UTC-arithmetic day-boundary bug).
create function app.resolve_attendance_workday(p_ts timestamptz, p_timezone text, p_day_boundary time)
returns date
language sql
immutable
as $$
  select (((p_ts at time zone p_timezone) - (coalesce(p_day_boundary, '00:00:00'::time) - '00:00:00'::time)))::date;
$$;

comment on function app.resolve_attendance_workday is
  'HRT-278: the governed local-time work_date bucketing function (decision, ISS-2026-059 lesson) -- every attendance session''s own work_date is computed by this function alone, never inline UTC date arithmetic.';

-- ===========================================================================
-- 4. app.attendance_events -- raw, append-only, server-authoritative log.
--    Never mutated after insert (a correction creates a NEW row, decision 5's
--    own "raw events preserved" rule) -- no record_version/updated_at.
-- ===========================================================================

create table app.attendance_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  event_type text not null,
  source_channel text not null,
  device_label text,
  client_reported_at timestamptz,
  server_received_at timestamptz not null default clock_timestamp(),
  location geography (point, 4326),
  location_source text not null default 'none',
  geofence_result text not null default 'not_evaluated',
  policy_version_id uuid references app.attendance_policy_versions (id),
  session_id uuid,
  is_correction boolean not null default false,
  correction_request_id uuid,
  raw_payload jsonb,
  source_import_staging_row_id uuid references app.import_staging_rows (id),
  idempotency_key text,
  created_by text,
  created_at timestamptz not null default now(),
  constraint attendance_events_event_type_check check (event_type in ('clock_in', 'clock_out')),
  constraint attendance_events_source_channel_check check (source_channel in ('mobile_web', 'kiosk', 'manual_hr', 'device_import')),
  constraint attendance_events_location_source_check check (location_source in ('none', 'gps', 'manual')),
  constraint attendance_events_geofence_result_check check (geofence_result in ('not_evaluated', 'inside', 'outside')),
  constraint attendance_events_location_shape_check check ((location is null) = (location_source = 'none')),
  constraint attendance_events_location_valid_check check (location is null or app.validate_geography_point(location))
);

comment on table app.attendance_events is
  'HRT-278: raw, append-only, server-authoritative attendance log (decision 5/section 24 "raw events preserved"). server_received_at (clock_timestamp(), the real wall-clock moment this row was written -- NOT now(), which is frozen at transaction start and would collapse ordering within one statement) is authoritative; client_reported_at is informational only, never trusted for ordering/exception decisions. location is populated ONLY when the resolved policy''s location_enforcement_mode required evaluating it (decision 4 -- structural minimization, not merely documented).';

create index attendance_events_tenant_employee_idx on app.attendance_events (tenant_id, employee_id, server_received_at desc);
create index attendance_events_session_idx on app.attendance_events (session_id) where session_id is not null;
create unique index attendance_events_idempotency_key_unique on app.attendance_events (tenant_id, employee_id, idempotency_key) where idempotency_key is not null;
create unique index attendance_events_staging_row_unique on app.attendance_events (source_import_staging_row_id) where source_import_staging_row_id is not null;

-- ===========================================================================
-- 5. app.attendance_sessions -- one derived row per (employee, work_date),
--    V1-bounded to a single clock-in/clock-out pair per workday (disclosed
--    simplification -- split-shift/multi-session days are out of scope, see
--    the checkpoint build log).
-- ===========================================================================

create table app.attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  work_date date not null,
  timezone text not null,
  policy_version_id uuid not null references app.attendance_policy_versions (id),
  status text not null default 'open',
  clock_in_event_id uuid references app.attendance_events (id),
  clock_out_event_id uuid references app.attendance_events (id),
  raw_clock_in_at timestamptz,
  raw_clock_out_at timestamptz,
  corrected_clock_in_at timestamptz,
  corrected_clock_out_at timestamptz,
  effective_clock_in_at timestamptz generated always as (coalesce(corrected_clock_in_at, raw_clock_in_at)) stored,
  effective_clock_out_at timestamptz generated always as (coalesce(corrected_clock_out_at, raw_clock_out_at)) stored,
  payroll_input_status text not null default 'pending',
  payroll_approved_by text,
  payroll_approved_at timestamptz,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_sessions_status_check check (status in ('open', 'closed')),
  constraint attendance_sessions_payroll_status_check check (payroll_input_status in ('pending', 'approved')),
  constraint attendance_sessions_clock_in_shape_check check ((status = 'open') = (clock_out_event_id is null)),
  constraint attendance_sessions_tenant_employee_workdate_unique unique (tenant_id, employee_id, work_date)
);

comment on table app.attendance_sessions is
  'HRT-278: one derived row per (employee, work_date) -- V1-bounded to a single clock-in/clock-out pair per workday (disclosed simplification, see docs/build-log/phase-07/HRT-278.md). effective_clock_in_at/effective_clock_out_at (generated, decision 5) resolve to the governed correction when one has been approved, the raw clock event otherwise -- section 24''s "corrections create linked versions, never overwrite source evidence silently" is satisfied structurally: raw_clock_in_at/raw_clock_out_at are never overwritten by a correction, only corrected_clock_in_at/corrected_clock_out_at are set.';

create unique index attendance_sessions_open_per_employee_unique on app.attendance_sessions (tenant_id, employee_id) where status = 'open';
create index attendance_sessions_tenant_workdate_idx on app.attendance_sessions (tenant_id, work_date desc);
create index attendance_sessions_tenant_employee_workdate_idx on app.attendance_sessions (tenant_id, employee_id, work_date desc);
create index attendance_sessions_tenant_payroll_idx on app.attendance_sessions (tenant_id, payroll_input_status);

alter table app.attendance_events add constraint attendance_events_session_id_fkey foreign key (session_id) references app.attendance_sessions (id);

-- ===========================================================================
-- 6. app.attendance_exceptions -- system-detected (and re-detectable)
--    exceptions against a session.
-- ===========================================================================

create table app.attendance_exceptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  session_id uuid not null references app.attendance_sessions (id),
  exception_type text not null,
  severity text not null default 'medium',
  status text not null default 'open',
  detected_at timestamptz not null default now(),
  detail jsonb not null default '{}'::jsonb,
  resolved_at timestamptz,
  resolved_by text,
  resolution_note text,
  waive_reason text,
  correction_request_id uuid,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_exceptions_type_check check (
    exception_type in ('late', 'early_leave', 'missing_clock_out', 'out_of_geofence', 'impossible_ordering')
  ),
  constraint attendance_exceptions_severity_check check (severity in ('low', 'medium', 'high')),
  constraint attendance_exceptions_status_check check (status in ('open', 'acknowledged', 'resolved', 'waived')),
  constraint attendance_exceptions_waive_reason_check check (status <> 'waived' or (waive_reason is not null and length(trim(waive_reason)) > 0)),
  constraint attendance_exceptions_resolved_shape_check check (
    (status in ('resolved', 'waived')) = (resolved_at is not null and resolved_by is not null)
  )
);

comment on table app.attendance_exceptions is
  'HRT-278: system-detected exceptions against one attendance_session. At most one OPEN-or-acknowledged row per (session_id, exception_type) -- app._recalculate_session_exceptions upserts detail on re-detection rather than duplicating. waive_reason/resolution_note are column-restricted (decision 8).';

create unique index attendance_exceptions_open_type_unique on app.attendance_exceptions (session_id, exception_type) where status in ('open', 'acknowledged');
create index attendance_exceptions_tenant_status_idx on app.attendance_exceptions (tenant_id, status);
create index attendance_exceptions_tenant_employee_idx on app.attendance_exceptions (tenant_id, employee_id, detected_at desc);
create index attendance_exceptions_session_idx on app.attendance_exceptions (session_id);

-- ===========================================================================
-- 7. app.attendance_correction_requests -- governed propose/decide workflow
--    (decision 5).
-- ===========================================================================

create table app.attendance_correction_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  session_id uuid not null references app.attendance_sessions (id),
  requested_by_auth_user_id uuid not null,
  requested_by text,
  request_type text not null,
  proposed_clock_in_at timestamptz,
  proposed_clock_out_at timestamptz,
  reason text not null,
  evidence_file_id uuid references app.files (id),
  status text not null default 'pending_approval',
  linked_exception_id uuid references app.attendance_exceptions (id),
  decided_by text,
  decided_at timestamptz,
  decided_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_correction_requests_reason_check check (length(trim(reason)) > 0),
  constraint attendance_correction_requests_request_type_check check (
    request_type in ('add_missing_clock_in', 'add_missing_clock_out', 'adjust_clock_in', 'adjust_clock_out')
  ),
  constraint attendance_correction_requests_status_check check (status in ('pending_approval', 'approved', 'rejected', 'cancelled')),
  constraint attendance_correction_requests_proposed_shape_check check (
    (request_type in ('add_missing_clock_in', 'adjust_clock_in') and proposed_clock_in_at is not null and proposed_clock_out_at is null)
    or (request_type in ('add_missing_clock_out', 'adjust_clock_out') and proposed_clock_out_at is not null and proposed_clock_in_at is null)
  ),
  constraint attendance_correction_requests_decided_shape_check check (
    (status = 'pending_approval' and decided_at is null and decided_by is null)
    or (status = 'cancelled' and decided_at is null and decided_by is null)
    or (status in ('approved', 'rejected') and decided_at is not null and decided_by is not null and decided_reason is not null and length(trim(decided_reason)) > 0)
  )
);

comment on table app.attendance_correction_requests is
  'HRT-278 (decision 5): direct propose (HRS:Edit)/decide (HRS:Approve) correction workflow, mirroring app.employee_position_assignments (HRT-275) exactly -- never routed through PLT-123. reason/decided_reason are column-restricted (decision 8).';

create index attendance_correction_requests_tenant_status_idx on app.attendance_correction_requests (tenant_id, status);
create index attendance_correction_requests_session_idx on app.attendance_correction_requests (session_id);
create index attendance_correction_requests_requester_idx on app.attendance_correction_requests (tenant_id, requested_by_auth_user_id);
create unique index attendance_correction_requests_idempotency_unique on app.attendance_correction_requests (tenant_id, employee_id, idempotency_key) where idempotency_key is not null;

alter table app.attendance_exceptions add constraint attendance_exceptions_correction_request_id_fkey foreign key (correction_request_id) references app.attendance_correction_requests (id);
alter table app.attendance_events add constraint attendance_events_correction_request_id_fkey foreign key (correction_request_id) references app.attendance_correction_requests (id);

-- ===========================================================================
-- 8. Shared internal helpers.
-- ===========================================================================

-- Resolves the caller's own linked employee row (self-service identity
-- resolution, decision 10), or a row of all NULLs (master_record_id null) when
-- the caller has no linked employee profile in this tenant. SECURITY DEFINER so
-- it works regardless of authenticated's own direct grants on app.users
-- (mirrors app.has_view_personal_data's own established reasoning).
create function app.get_self_employee(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns app.employees
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select e.*
  from app.employees e
  join app.users u on u.id = e.user_id
  where e.tenant_id = p_tenant_id and u.auth_user_id = p_actor_auth_user_id and u.tenant_id = p_tenant_id;
$$;

comment on function app.get_self_employee is
  'HRT-278: resolves the calling identity''s own linked app.employees row within one tenant, or zero rows if unlinked. The sole self-identity resolution mechanism for every self-service RPC below (decision 10) -- never a client-supplied employee_id on a self-service path.';

-- Branch-scoped-over-tenant-wide, latest-effective-published-version
-- resolution (decision 3).
create function app.resolve_effective_attendance_policy_version(p_tenant_id uuid, p_branch_org_unit_id uuid, p_as_of_date date)
returns setof app.attendance_policy_versions
language sql
stable
as $$
  select pv.*
  from app.attendance_policy_versions pv
  join app.attendance_policies p on p.id = pv.policy_id
  where p.tenant_id = p_tenant_id
    and pv.status = 'published'
    and pv.effective_from <= p_as_of_date
    and (p.org_unit_id is null or p.org_unit_id = p_branch_org_unit_id)
  order by (p.org_unit_id is not null) desc, pv.effective_from desc
  limit 1;
$$;

comment on function app.resolve_effective_attendance_policy_version is
  'HRT-278 (decision 3): the single effective-policy resolution point every write RPC below uses. Prefers a published, org_unit-scoped policy matching the employee''s own branch_org_unit_id over a tenant-wide (org_unit_id is null) one; among candidates of the same specificity, picks the greatest effective_from not after p_as_of_date. Zero rows = "no eligible policy" (section 23 exception flow).';

-- Recomputes every exception type for one session, from its own CURRENT
-- effective_clock_in_at/effective_clock_out_at and its own resolved policy
-- version -- upserts (never duplicates) per (session_id, exception_type),
-- resolves an exception whose underlying condition no longer holds. Called
-- after every clock event AND after every correction decision, so exceptions
-- always reflect the CURRENT effective time, never a stale first-computed one.
create function app._recalculate_session_exceptions(p_session_id uuid)
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
begin
  select * into v_session from app.attendance_sessions where id = p_session_id;
  if not found then
    return;
  end if;
  select * into v_policy from app.attendance_policy_versions where id = v_session.policy_version_id;

  v_workday_start := (v_session.work_date::text || ' ' || v_policy.workday_start_time::text)::timestamp at time zone v_policy.timezone;
  -- An overnight-shift workday_end_time (< workday_start_time, e.g. start 22:00
  -- end 06:00) belongs to the FOLLOWING local calendar day.
  v_workday_end := ((v_session.work_date + case when v_policy.workday_end_time < v_policy.workday_start_time then 1 else 0 end)::text || ' ' || v_policy.workday_end_time::text)::timestamp at time zone v_policy.timezone;

  -- late
  if v_session.effective_clock_in_at is not null then
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

  -- early_leave
  if v_session.effective_clock_out_at is not null then
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

  -- missing_clock_out: still open past a generous multiple of max_session_hours
  if v_session.status = 'open' and v_session.effective_clock_in_at is not null
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
  'HRT-278: internal exception-detection engine, re-run after every clock event and every correction decision (decision, section 20''s own "define ... exception ... invariants"). Upserts per (session_id, exception_type), never duplicates; resolves an exception whose condition no longer holds, so exceptions always reflect CURRENT effective time. out_of_geofence/impossible_ordering are raised directly at ingest time (app._ingest_attendance_event), not recomputed here, since both depend on the ORIGINAL raw event, not the current effective time.';

-- The single shared ingestion engine (decision 6/10) -- self-service clock,
-- HR manual entry, and device-import commit all call this, never three
-- independently-validated write paths.
create function app._ingest_attendance_event(
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

    insert into app.attendance_sessions (
      tenant_id, employee_id, work_date, timezone, policy_version_id, status, clock_in_event_id, raw_clock_in_at
    ) values (
      p_employee.tenant_id, p_employee.master_record_id, v_work_date, v_policy.timezone, v_policy.id, 'open', v_event.id, v_now
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
    jsonb_build_object('event_type', p_event_type, 'source_channel', p_source_channel, 'session_id', v_session.id, 'geofence_result', v_geofence_result)
  );
end;
$$;

comment on function app._ingest_attendance_event is
  'HRT-278 (decision 6/10): the ONE shared ingestion engine every clock/manual/device-import write path calls -- server_received_at (clock_timestamp()) is always authoritative, never a client-supplied timestamp. Raises, never silently coerces, when location_enforcement_mode=required and the location is missing/outside (section 15''s "no fake location success or hidden failure").';

-- ===========================================================================
-- 9. Policy authoring RPCs.
-- ===========================================================================

create function app.create_attendance_policy(
  p_tenant_id uuid, p_org_unit_id uuid, p_name text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.attendance_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_policy app.attendance_policies;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name must not be empty' using errcode = 'check_violation';
  end if;

  if p_org_unit_id is not null and not exists (select 1 from app.org_units where id = p_org_unit_id and tenant_id = p_tenant_id) then
    raise exception 'org_unit_not_found: no org unit % in tenant %', p_org_unit_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  insert into app.attendance_policies (tenant_id, org_unit_id, name, created_by)
  values (p_tenant_id, p_org_unit_id, p_name, p_actor_label)
  returning * into v_policy;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_attendance_policy',
    'app.attendance_policies', v_policy.id, 'success', null, null, to_jsonb(v_policy)
  );

  return v_policy;
end;
$$;

create function app.create_attendance_policy_version(
  p_policy_id uuid,
  p_timezone text,
  p_workday_start_time time,
  p_workday_end_time time,
  p_day_boundary_local_time time,
  p_grace_late_minutes integer,
  p_grace_early_minutes integer,
  p_allowed_channels text[],
  p_location_enforcement_mode text,
  p_geofence_center_geojson jsonb,
  p_geofence_radius_meters numeric,
  p_max_session_hours numeric,
  p_effective_from date,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.attendance_policy_versions
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_policy app.attendance_policies;
  v_next_version integer;
  v_version app.attendance_policy_versions;
  v_geofence geography;
begin
  select * into v_policy from app.attendance_policies where id = p_policy_id;
  if not found or not app.has_active_tenant_membership(v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'policy_not_found: %', p_policy_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_policy.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_policy.status = 'archived' then
    raise exception 'invalid_transition: policy % is archived, cannot author a new version', p_policy_id using errcode = 'check_violation';
  end if;

  if not app.validate_iana_timezone(p_timezone) then
    raise exception 'invalid_timezone: % is not a recognized IANA timezone', p_timezone using errcode = 'check_violation';
  end if;

  if p_geofence_center_geojson is not null then
    v_geofence := app.geojson_point_to_geography(p_geofence_center_geojson);
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.attendance_policy_versions where policy_id = p_policy_id;

  insert into app.attendance_policy_versions (
    policy_id, tenant_id, version_number, effective_from, timezone, workday_start_time, workday_end_time,
    day_boundary_local_time, grace_late_minutes, grace_early_minutes, allowed_channels, location_enforcement_mode,
    geofence_center, geofence_radius_meters, max_session_hours, created_by
  ) values (
    p_policy_id, v_policy.tenant_id, v_next_version, p_effective_from, p_timezone, p_workday_start_time, p_workday_end_time,
    coalesce(p_day_boundary_local_time, '00:00:00'::time), coalesce(p_grace_late_minutes, 0), coalesce(p_grace_early_minutes, 0),
    coalesce(p_allowed_channels, array['mobile_web', 'kiosk']::text[]), coalesce(p_location_enforcement_mode, 'none'),
    v_geofence, p_geofence_radius_meters, coalesce(p_max_session_hours, 16), p_actor_label
  ) returning * into v_version;

  perform app.capture_audit_event(
    v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_attendance_policy_version',
    'app.attendance_policy_versions', v_version.id, 'success', null, null, jsonb_build_object('policy_id', p_policy_id, 'version_number', v_next_version)
  );

  return v_version;
end;
$$;

create function app.publish_attendance_policy_version(
  p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.attendance_policy_versions
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.attendance_policy_versions;
  v_policy app.attendance_policies;
begin
  select * into v_version from app.attendance_policy_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'policy_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: policy version % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: policy version % is %, only a draft may be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  update app.attendance_policy_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: policy version % target row was concurrently modified (expected version %)', p_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.attendance_policies set status = 'published' where id = v_version.policy_id and status = 'draft';

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_attendance_policy_version',
    'app.attendance_policy_versions', p_version_id, 'success', null, null, jsonb_build_object('effective_from', v_version.effective_from)
  );

  return v_version;
end;
$$;

-- ===========================================================================
-- 10. Clock / manual entry RPCs.
-- ===========================================================================

create function app.record_attendance_clock_event(
  p_tenant_id uuid,
  p_event_type text,
  p_source_channel text,
  p_client_reported_at timestamptz,
  p_location_geojson jsonb,
  p_device_label text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.attendance_events
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_self app.employees;
  v_location geography;
  v_result app.attendance_events;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;

  if p_source_channel not in ('mobile_web', 'kiosk') then
    raise exception 'invalid_source_channel: self-service clock events must use mobile_web or kiosk' using errcode = 'check_violation';
  end if;

  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if p_location_geojson is not null then
    v_location := app.geojson_point_to_geography(p_location_geojson);
  end if;

  v_result := app._ingest_attendance_event(
    v_self, p_event_type, p_source_channel, p_client_reported_at, v_location,
    p_idempotency_key, null, null, p_actor_auth_user_id, p_actor_label
  );

  if p_device_label is not null then
    update app.attendance_events set device_label = p_device_label where id = v_result.id;
    v_result.device_label := p_device_label;
  end if;

  return v_result;
end;
$$;

comment on function app.record_attendance_clock_event is
  'HRT-278 (decision 10): self-only -- NO p_employee_id parameter exists, the acting employee is resolved exclusively from the caller''s own session identity (app.get_self_employee). Structurally prevents a spoofed target id (section 16).';

create function app.record_manual_attendance_event(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_event_type text,
  p_event_at timestamptz,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.attendance_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_result app.attendance_events;
begin
  select * into v_employee from app.employees where master_record_id = p_employee_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required for a manual attendance entry' using errcode = 'check_violation';
  end if;
  if p_event_at is null then
    raise exception 'event_at_required: a manual attendance entry requires an explicit event timestamp' using errcode = 'check_violation';
  end if;

  v_result := app._ingest_attendance_event(
    v_employee, p_event_type, 'manual_hr', p_event_at, null,
    p_idempotency_key, jsonb_build_object('manual_reason', p_reason), null, p_actor_auth_user_id, p_actor_label
  );

  return v_result;
end;
$$;

comment on function app.record_manual_attendance_event is
  'HRT-278 (decision 10): HRS:Edit-gated, explicit target employee -- the "explicit HR authority" half of section 16''s access split. p_event_at (not now()) is the authoritative timestamp -- HR is entering a real past event, never re-timestamping to the entry moment.';

-- ===========================================================================
-- 11. Correction propose/decide/cancel RPCs (decision 5).
-- ===========================================================================

create function app.request_attendance_correction(
  p_session_id uuid,
  p_request_type text,
  p_proposed_clock_in_at timestamptz,
  p_proposed_clock_out_at timestamptz,
  p_reason text,
  p_evidence_file_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.attendance_correction_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_session app.attendance_sessions;
  v_self app.employees;
  v_is_self boolean;
  v_file app.files;
  v_existing app.attendance_correction_requests;
  v_request app.attendance_correction_requests;
  v_exception_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_session from app.attendance_sessions where id = p_session_id;
  if not found or not app.has_active_tenant_membership(v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'session_not_found: %', p_session_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_session.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_session.employee_id;

  if not v_is_self then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_session.tenant_id, 'HRS', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_session.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request a correction' using errcode = 'check_violation';
  end if;

  if p_evidence_file_id is not null then
    select * into v_file from app.files where id = p_evidence_file_id;
    if not found or v_file.tenant_id <> v_session.tenant_id or v_file.record_type <> 'attendance_correction' or v_file.record_id <> p_session_id then
      raise exception 'evidence_file_not_found: file % is not a valid evidence file for session %', p_evidence_file_id, p_session_id using errcode = 'no_data_found';
    end if;
    if v_file.malware_scan_status = 'infected' then
      raise exception 'evidence_file_infected: file % failed malware scanning and cannot be attached', p_evidence_file_id using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'evidence_file_not_scanned: file % has not cleared malware scanning (status %)', p_evidence_file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.attendance_correction_requests where tenant_id = v_session.tenant_id and employee_id = v_session.employee_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.session_id = p_session_id and v_existing.request_type = p_request_type
         and v_existing.proposed_clock_in_at is not distinct from p_proposed_clock_in_at
         and v_existing.proposed_clock_out_at is not distinct from p_proposed_clock_out_at then
        return v_existing;
      else
        raise exception 'idempotency_key_conflict: key % was already used for a different correction request', p_idempotency_key using errcode = 'unique_violation';
      end if;
    end if;
  end if;

  select id into v_exception_id from app.attendance_exceptions
  where session_id = p_session_id and exception_type = 'missing_clock_out' and status in ('open', 'acknowledged')
  limit 1;

  insert into app.attendance_correction_requests (
    tenant_id, employee_id, session_id, requested_by_auth_user_id, requested_by, request_type,
    proposed_clock_in_at, proposed_clock_out_at, reason, evidence_file_id, linked_exception_id, idempotency_key
  ) values (
    v_session.tenant_id, v_session.employee_id, p_session_id, p_actor_auth_user_id, p_actor_label, p_request_type,
    p_proposed_clock_in_at, p_proposed_clock_out_at, p_reason, p_evidence_file_id, v_exception_id, p_idempotency_key
  ) returning * into v_request;

  perform app.capture_audit_event(
    v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_attendance_correction',
    'app.attendance_correction_requests', v_request.id, 'success', null, null, jsonb_build_object('session_id', p_session_id, 'request_type', p_request_type)
  );

  return v_request;
end;
$$;

create function app.decide_attendance_correction(
  p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
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

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_attendance_correction',
    'app.attendance_correction_requests', p_request_id, 'success', p_decided_reason, null, jsonb_build_object('decision', p_decision)
  );

  return v_request;
end;
$$;

create function app.cancel_attendance_correction(
  p_request_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
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

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_attendance_correction',
    'app.attendance_correction_requests', p_request_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_request;
end;
$$;

-- ===========================================================================
-- 12. Exception acknowledge/waive RPCs.
-- ===========================================================================

create function app.acknowledge_attendance_exception(
  p_exception_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text
)
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

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_exception.status <> 'open' then
    raise exception 'invalid_transition: exception % is %, only an open exception may be acknowledged', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  update app.attendance_exceptions
  set status = 'acknowledged'
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;
  if not found then
    raise exception 'stale_version: exception % target row was concurrently modified (expected version %)', p_exception_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_attendance_exception',
    'app.attendance_exceptions', p_exception_id, 'success', null, null, '{}'::jsonb
  );

  return v_exception;
end;
$$;

create function app.waive_attendance_exception(
  p_exception_id uuid, p_expected_version integer, p_waive_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
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

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'waive_attendance_exception',
    'app.attendance_exceptions', p_exception_id, 'success', p_waive_reason, null, '{}'::jsonb
  );

  return v_exception;
end;
$$;

-- ===========================================================================
-- 13. Payroll-input approval RPC (section 24: "approved attendance may feed
--     payroll once with lineage; finalized payroll is not silently
--     recalculated" -- Payroll itself, Prompt 282, does not exist yet; this is
--     the forward contract it will consume, mirrored on the established
--     "prepare_finance_*_from_*" handoff shape, never a live posting here).
-- ===========================================================================

create function app.approve_attendance_for_payroll_input(
  p_tenant_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns table (session_id uuid, approved boolean, skip_reason text)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.attendance_sessions;
  v_open_exceptions integer;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_from_date is null or p_to_date is null or p_to_date < p_from_date or (p_to_date - p_from_date) > 92 then
    raise exception 'invalid_date_range: date range must be non-empty and at most 92 days' using errcode = 'check_violation';
  end if;

  for v_row in
    select s.* from app.attendance_sessions s
    where s.tenant_id = p_tenant_id and s.work_date between p_from_date and p_to_date
      and (p_employee_id is null or s.employee_id = p_employee_id)
      and s.payroll_input_status = 'pending'
    for update
  loop
    if v_row.status <> 'closed' then
      session_id := v_row.id; approved := false; skip_reason := 'session_not_closed';
      return next;
      continue;
    end if;

    select count(*) into v_open_exceptions from app.attendance_exceptions x where x.session_id = v_row.id and x.status in ('open', 'acknowledged');
    if v_open_exceptions > 0 then
      session_id := v_row.id; approved := false; skip_reason := 'unresolved_exceptions';
      return next;
      continue;
    end if;

    update app.attendance_sessions
    set payroll_input_status = 'approved', payroll_approved_by = p_actor_label, payroll_approved_at = now()
    where id = v_row.id;

    session_id := v_row.id; approved := true; skip_reason := null;
    return next;
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_attendance_for_payroll_input',
    'app.attendance_sessions', null, 'success', null, null, jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date, 'employee_id', p_employee_id)
  );

  return;
end;
$$;

comment on function app.approve_attendance_for_payroll_input is
  'HRT-278 (section 24): marks closed sessions with zero open/acknowledged exceptions as payroll_input_status=''approved'' -- the forward contract Prompt 282 (Payroll) is expected to consume, never a live Finance/Payroll posting from this checkpoint. A session with any unresolved exception is skipped, not silently approved. app.decide_attendance_correction resets payroll_input_status to ''pending'' on ANY approved correction against an already-approved session (never silently recalculates an already-fed value).';

-- ===========================================================================
-- 14. Bounded synchronous exception recalculation (decision 7).
-- ===========================================================================

create function app.recalculate_attendance_exceptions_for_range(
  p_tenant_id uuid, p_from_date date, p_to_date date, p_org_unit_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns integer
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.attendance_sessions;
  v_count integer := 0;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_from_date is null or p_to_date is null or p_to_date < p_from_date or (p_to_date - p_from_date) > 92 then
    raise exception 'invalid_date_range: date range must be non-empty and at most 92 days (decision 7 -- bounded synchronous recalculation)' using errcode = 'check_violation';
  end if;

  for v_row in
    select s.* from app.attendance_sessions s
    join app.employees e on e.master_record_id = s.employee_id
    where s.tenant_id = p_tenant_id and s.work_date between p_from_date and p_to_date
      and (p_org_unit_id is null or e.branch_org_unit_id = p_org_unit_id or e.department_org_unit_id = p_org_unit_id)
  loop
    perform app._recalculate_session_exceptions(v_row.id);
    v_count := v_count + 1;
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'recalculate_attendance_exceptions_for_range',
    'app.attendance_sessions', null, 'success', null, null, jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date, 'session_count', v_count)
  );

  return v_count;
end;
$$;

-- ===========================================================================
-- 15. Device import -- real PLT-131/132 staged-import adapter (decision 6).
-- ===========================================================================

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('attendance_device_import_source', 'Attendance Device Import Source', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:attendance_device_import_source', 'Attendance Device Import Source', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.import_export_schemas (code, name, owner_primitive_code, registered_by)
values ('attendance_device_import', 'Attendance Device Import', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('import_export:attendance_device_import', 'Attendance Device Import', 'HRS', 'system')
on conflict (code) do nothing;

create function app.validate_attendance_device_import_row(
  p_staging_row_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.import_staging_rows
language plpgsql
as $$
declare
  v_row app.import_staging_rows;
  v_payload jsonb;
  v_errors text[] := array[]::text[];
  v_text_fields text[] := array['employee_number', 'event_type', 'event_at', 'device_label'];
  v_field text;
  v_value text;
  v_event_type text;
  v_event_at text;
begin
  v_row := app.validate_staging_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
  if v_row.validation_status <> 'valid' then
    return v_row;
  end if;

  v_payload := v_row.raw_payload;

  foreach v_field in array v_text_fields loop
    v_value := v_payload ->> v_field;
    if v_value is not null and v_value ~ '^[-+=@\t\r]' then
      v_errors := v_errors || (v_field || ': value begins with a disallowed formula/spreadsheet-injection prefix (=, +, -, @, tab, or carriage return)');
    end if;
  end loop;

  v_event_type := v_payload ->> 'event_type';
  if v_event_type is null or v_event_type not in ('clock_in', 'clock_out') then
    v_errors := v_errors || ('event_type: ' || coalesce(v_event_type, '(missing)') || ' is not clock_in or clock_out');
  end if;

  v_event_at := v_payload ->> 'event_at';
  if v_event_at is null or not (v_event_at ~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}') then
    v_errors := v_errors || ('event_at: ' || coalesce(v_event_at, '(missing)') || ' is not a recognized ISO-8601 timestamp');
  end if;

  if coalesce(v_payload ->> 'employee_number', '') = '' then
    v_errors := v_errors || 'employee_number: required value is missing';
  elsif not exists (
    select 1 from app.employees e join app.master_records m on m.id = e.master_record_id
    where e.tenant_id = (select tenant_id from app.jobs where job_id = v_row.job_id) and m.code = (v_payload ->> 'employee_number')
  ) then
    v_errors := v_errors || ('employee_number: ' || (v_payload ->> 'employee_number') || ' does not resolve to a known employee in this tenant');
  end if;

  if array_length(v_errors, 1) is not null then
    update app.import_staging_rows
    set validation_status = 'invalid', error = array_to_string(v_errors, '; ')
    where id = p_staging_row_id
    returning * into v_row;

    update app.jobs
    set invalid_row_count = invalid_row_count + 1, valid_row_count = valid_row_count - 1
    where job_id = v_row.job_id;
  end if;

  return v_row;
end;
$$;

comment on function app.validate_attendance_device_import_row is
  'HRT-278 (decision 6): calls app.validate_staging_row UNCHANGED first (generic structural pass), then the same formula/spreadsheet-injection prefix set every prior staged-import adapter uses, plus employee_number/event_type/event_at domain checks.';

create function app.commit_attendance_device_import_job(
  p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.jobs
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_employee app.employees;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_failed_count integer := 0;
  v_ignore app.attendance_events;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'attendance_device_import' then
    raise exception 'import_export_wrong_schema: job % is not an attendance_device_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'HRS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
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

  -- Job-scoped advisory lock (mirrors app.commit_employee_import_job, HRT-274,
  -- and app.commit_vendor_rate_import_job, PRC-255, with this checkpoint's own
  -- distinct salt) -- serializes any concurrent/replayed commit call on this
  -- SAME job.
  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 278));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.attendance_events where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;

    select e.* into v_employee from app.employees e join app.master_records m on m.id = e.master_record_id
    where e.tenant_id = v_job.tenant_id and m.code = (v_payload ->> 'employee_number');

    begin
      v_ignore := app._ingest_attendance_event(
        v_employee, v_payload ->> 'event_type', 'device_import', (v_payload ->> 'event_at')::timestamptz, null,
        null, v_payload, v_row.id, p_actor_auth_user_id, p_actor_label
      );
      if coalesce(v_payload ->> 'device_label', '') <> '' then
        update app.attendance_events set device_label = v_payload ->> 'device_label' where id = v_ignore.id;
      end if;
      v_created_count := v_created_count + 1;
    exception
      when no_data_found or check_violation or unique_violation then
        update app.import_staging_rows set validation_status = 'invalid', error = sqlerrm where id = v_row.id;
        v_failed_count := v_failed_count + 1;
    end;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now(),
      valid_row_count = v_created_count, invalid_row_count = coalesce(invalid_row_count, 0) + v_failed_count
  where job_id = p_job_id
  returning * into v_job;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_attendance_device_import_job',
    'app.jobs', p_job_id, 'success', null, null,
    jsonb_build_object('created_count', v_created_count, 'skipped_count', v_skipped_count, 'failed_count', v_failed_count)
  );

  return v_job;
end;
$$;

comment on function app.commit_attendance_device_import_job is
  'HRT-278 (decision 6): idempotent per staging row (source_import_staging_row_id unique-when-set on app.attendance_events, defended by a pre-check AND a per-row exception handler), job-scoped-advisory-lock serialized. Calls the SAME app._ingest_attendance_event engine the live self-service clock path calls -- never a second, independently-hardened write path. A per-row domain-validation failure at commit time (e.g. the employee was deactivated after this row was validated) marks that ONE row invalid and continues, never aborts the whole batch.';

-- ===========================================================================
-- 16. Read RPCs.
-- ===========================================================================

create function app.get_my_attendance_status(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  session_id uuid, work_date date, status text, effective_clock_in_at timestamptz, effective_clock_out_at timestamptz,
  open_exception_count integer, payroll_input_status text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;

  return query
  select s.id, s.work_date, s.status, s.effective_clock_in_at, s.effective_clock_out_at,
         (select count(*)::integer from app.attendance_exceptions x where x.session_id = s.id and x.status in ('open', 'acknowledged')),
         s.payroll_input_status
  from app.attendance_sessions s
  where s.tenant_id = p_tenant_id and s.employee_id = v_self.master_record_id
  order by s.work_date desc
  limit 14;
end;
$$;

create function app.list_attendance_sessions(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_status text,
  p_limit integer, p_after_id uuid
)
returns table (
  id uuid, employee_id uuid, employee_number text, employee_full_name text, work_date date, status text,
  effective_clock_in_at timestamptz, effective_clock_out_at timestamptz, payroll_input_status text,
  open_exception_count integer, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_has_view boolean;
  v_after app.attendance_sessions;
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
    select * into v_after from app.attendance_sessions where id = p_after_id;
  end if;

  return query
  select s.id, s.employee_id, m.code, e.full_name, s.work_date, s.status, s.effective_clock_in_at, s.effective_clock_out_at,
         s.payroll_input_status,
         (select count(*)::integer from app.attendance_exceptions x where x.session_id = s.id and x.status in ('open', 'acknowledged')),
         s.record_version
  from app.attendance_sessions s
  join app.employees e on e.master_record_id = s.employee_id
  join app.master_records m on m.id = e.master_record_id
  where s.tenant_id = p_tenant_id
    and (p_from_date is null or s.work_date >= p_from_date)
    and (p_to_date is null or s.work_date <= p_to_date)
    and (p_status is null or s.status = p_status)
    and (
      (p_employee_id is not null and s.employee_id = p_employee_id)
      or (p_employee_id is null and v_has_view)
      or (p_employee_id is null and not v_has_view and (s.employee_id = v_self.master_record_id or e.manager_employee_id = v_self.master_record_id))
    )
    and (v_after.id is null or (s.work_date, s.id) < (v_after.work_date, v_after.id))
  order by s.work_date desc, s.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_attendance_sessions is
  'HRT-278 (section 26): HRS:View holders see the full tenant-scoped list; anyone else (no HRS:View) transparently gets a manager/self scope (their own session rows plus their own direct reports'' rows only) -- the concrete "manager effective-team review where configured" + "prevent cross-team views" mechanism, unified into one RPC rather than a separate team-only endpoint.';

create function app.get_attendance_session_detail(p_session_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, employee_id uuid, work_date date, status text, timezone text, effective_clock_in_at timestamptz, effective_clock_out_at timestamptz,
  raw_clock_in_at timestamptz, raw_clock_out_at timestamptz, payroll_input_status text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_session app.attendance_sessions;
  v_self app.employees;
  v_has_view boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_session from app.attendance_sessions where id = p_session_id;
  if not found or not app.has_active_tenant_membership(v_session.tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_self := app.get_self_employee(v_session.tenant_id, p_actor_auth_user_id);
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, v_session.tenant_id, 'HRS', 'View')).allowed;

  if not (
    v_has_view
    or (v_self.master_record_id is not null and v_self.master_record_id = v_session.employee_id)
    or exists (select 1 from app.employees e where e.master_record_id = v_session.employee_id and e.manager_employee_id = v_self.master_record_id)
  ) then
    return;
  end if;

  return query
  select s.id, s.employee_id, s.work_date, s.status, s.timezone, s.effective_clock_in_at, s.effective_clock_out_at,
         s.raw_clock_in_at, s.raw_clock_out_at, s.payroll_input_status, s.record_version
  from app.attendance_sessions s where s.id = p_session_id;
end;
$$;

create function app.list_attendance_exceptions(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text, p_limit integer, p_after_id uuid
)
returns table (
  id uuid, employee_id uuid, employee_number text, session_id uuid, work_date date, exception_type text, severity text,
  status text, detail jsonb, detected_at timestamptz, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_after app.attendance_exceptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    return;
  end if;

  if p_after_id is not null then
    select * into v_after from app.attendance_exceptions where id = p_after_id;
  end if;

  return query
  select x.id, x.employee_id, m.code, x.session_id, s.work_date, x.exception_type, x.severity, x.status, x.detail, x.detected_at, x.record_version
  from app.attendance_exceptions x
  join app.attendance_sessions s on s.id = x.session_id
  join app.employees e on e.master_record_id = x.employee_id
  join app.master_records m on m.id = e.master_record_id
  where x.tenant_id = p_tenant_id
    and (p_status is null or x.status = p_status)
    and (v_after.id is null or (x.detected_at, x.id) < (v_after.detected_at, v_after.id))
  order by x.detected_at desc, x.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create function app.list_my_attendance_correction_requests(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, session_id uuid, work_date date, request_type text, status text, created_at timestamptz, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  return query
  select cr.id, cr.session_id, s.work_date, cr.request_type, cr.status, cr.created_at, cr.record_version
  from app.attendance_correction_requests cr
  join app.attendance_sessions s on s.id = cr.session_id
  where cr.tenant_id = p_tenant_id and cr.requested_by_auth_user_id = p_actor_auth_user_id
  order by cr.created_at desc
  limit 100;
end;
$$;

create function app.list_attendance_correction_requests(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text, p_limit integer, p_after_id uuid)
returns table (
  id uuid, employee_id uuid, employee_number text, session_id uuid, work_date date, request_type text, status text,
  created_at timestamptz, record_version integer, has_evidence boolean
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_after app.attendance_correction_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    return;
  end if;

  if p_after_id is not null then
    select * into v_after from app.attendance_correction_requests where id = p_after_id;
  end if;

  return query
  select cr.id, cr.employee_id, m.code, cr.session_id, s.work_date, cr.request_type, cr.status, cr.created_at, cr.record_version,
         (cr.evidence_file_id is not null)
  from app.attendance_correction_requests cr
  join app.attendance_sessions s on s.id = cr.session_id
  join app.employees e on e.master_record_id = cr.employee_id
  join app.master_records m on m.id = e.master_record_id
  where cr.tenant_id = p_tenant_id
    and (p_status is null or cr.status = p_status)
    and (v_after.id is null or (cr.created_at, cr.id) < (v_after.created_at, v_after.id))
  order by cr.created_at desc, cr.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create function app.list_attendance_policies(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, org_unit_id uuid, name text, status text, published_version_id uuid, published_version_number integer, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    return;
  end if;

  return query
  select p.id, p.org_unit_id, p.name, p.status, pv.id, pv.version_number, p.record_version
  from app.attendance_policies p
  left join lateral (
    select v.id, v.version_number from app.attendance_policy_versions v
    where v.policy_id = p.id and v.status = 'published'
    order by v.effective_from desc limit 1
  ) pv on true
  where p.tenant_id = p_tenant_id
  order by p.name;
end;
$$;

create function app.get_attendance_policy_version(p_version_id uuid, p_actor_auth_user_id uuid)
returns app.attendance_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.attendance_policy_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_version from app.attendance_policy_versions where id = p_version_id;
  if not found then
    return null;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    return null;
  end if;

  return v_version;
end;
$$;

create function app.export_attendance_sessions(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date
)
returns table (
  employee_number text, employee_full_name text, work_date date, status text, effective_clock_in_at timestamptz,
  effective_clock_out_at timestamptz, payroll_input_status text, exception_types text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Export');
  if not v_decision.allowed then
    return;
  end if;

  if p_from_date is null or p_to_date is null or (p_to_date - p_from_date) > 366 then
    raise exception 'invalid_date_range: export date range must be non-empty and at most 366 days' using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_auth_user_id::text, 'export_attendance_sessions',
    'app.attendance_sessions', null, 'success', null, null, jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date)
  );

  return query
  select m.code, e.full_name, s.work_date, s.status, s.effective_clock_in_at, s.effective_clock_out_at, s.payroll_input_status,
         coalesce((select string_agg(x.exception_type, ',') from app.attendance_exceptions x where x.session_id = s.id and x.status in ('open', 'acknowledged')), '')
  from app.attendance_sessions s
  join app.employees e on e.master_record_id = s.employee_id
  join app.master_records m on m.id = e.master_record_id
  where s.tenant_id = p_tenant_id and s.work_date between p_from_date and p_to_date
  order by s.work_date, m.code;
end;
$$;

-- ===========================================================================
-- 17. RLS -- hardened default-deny select policy on every new table (writes
--     exclusively through the SECURITY DEFINER functions above, never a raw
--     INSERT/UPDATE grant to authenticated).
-- ===========================================================================

alter table app.attendance_policies enable row level security;
alter table app.attendance_policy_versions enable row level security;
alter table app.attendance_events enable row level security;
alter table app.attendance_sessions enable row level security;
alter table app.attendance_exceptions enable row level security;
alter table app.attendance_correction_requests enable row level security;

create policy attendance_policies_select_scoped on app.attendance_policies
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy attendance_policy_versions_select_scoped on app.attendance_policy_versions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy attendance_events_select_scoped on app.attendance_events
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy attendance_sessions_select_scoped on app.attendance_sessions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy attendance_exceptions_select_scoped on app.attendance_exceptions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy attendance_correction_requests_select_scoped on app.attendance_correction_requests
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 18. Grants -- column-restricted from the first migration (decision 8), never
--     a blanket `grant select on <table> to authenticated`.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select (id, tenant_id, org_unit_id, name, status, record_version, created_by, created_at, updated_at)
  on app.attendance_policies to authenticated;
grant select on app.attendance_policies to service_role;

grant select (
  id, policy_id, tenant_id, version_number, status, effective_from, timezone, workday_start_time, workday_end_time,
  day_boundary_local_time, grace_late_minutes, grace_early_minutes, allowed_channels, location_enforcement_mode,
  geofence_center, geofence_radius_meters, max_session_hours, published_at, published_by, record_version, created_by, created_at, updated_at
) on app.attendance_policy_versions to authenticated;
grant select on app.attendance_policy_versions to service_role;

grant select (
  id, tenant_id, employee_id, event_type, source_channel, device_label, client_reported_at, server_received_at,
  location_source, geofence_result, policy_version_id, session_id, is_correction, correction_request_id, idempotency_key, created_by, created_at
) on app.attendance_events to authenticated;
grant select on app.attendance_events to service_role;

grant select on app.attendance_sessions to authenticated;
grant select on app.attendance_sessions to service_role;

grant select (
  id, tenant_id, employee_id, session_id, exception_type, severity, status, detected_at, detail,
  resolved_at, resolved_by, correction_request_id, record_version, created_at, updated_at
) on app.attendance_exceptions to authenticated;
grant select on app.attendance_exceptions to service_role;

grant select (
  id, tenant_id, employee_id, session_id, requested_by_auth_user_id, requested_by, request_type,
  proposed_clock_in_at, proposed_clock_out_at, evidence_file_id, status, linked_exception_id, decided_by, decided_at,
  idempotency_key, record_version, created_at, updated_at
) on app.attendance_correction_requests to authenticated;
grant select on app.attendance_correction_requests to service_role;

grant execute on function app.validate_iana_timezone(text) to authenticated, service_role;
grant execute on function app.resolve_attendance_workday(timestamptz, text, time) to authenticated, service_role;
grant execute on function app.resolve_effective_attendance_policy_version(uuid, uuid, date) to authenticated, service_role;
grant execute on function app.get_self_employee(uuid, uuid) to authenticated, service_role;

grant execute on function app.create_attendance_policy(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_attendance_policy_version(uuid, text, time, time, time, integer, integer, text[], text, jsonb, numeric, numeric, date, uuid, text) to authenticated, service_role;
grant execute on function app.publish_attendance_policy_version(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.record_attendance_clock_event(uuid, text, text, timestamptz, jsonb, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_manual_attendance_event(uuid, uuid, text, timestamptz, text, text, uuid, text) to authenticated, service_role;

grant execute on function app.request_attendance_correction(uuid, text, timestamptz, timestamptz, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_attendance_correction(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_attendance_correction(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.acknowledge_attendance_exception(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.waive_attendance_exception(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.approve_attendance_for_payroll_input(uuid, date, date, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.recalculate_attendance_exceptions_for_range(uuid, date, date, uuid, uuid, text) to authenticated, service_role;

grant execute on function app.validate_attendance_device_import_row(uuid, uuid, text) to service_role;
grant execute on function app.commit_attendance_device_import_job(uuid, boolean, uuid, text) to authenticated, service_role;

grant execute on function app.get_my_attendance_status(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_attendance_sessions(uuid, uuid, date, date, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.get_attendance_session_detail(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_attendance_exceptions(uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.list_my_attendance_correction_requests(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_attendance_correction_requests(uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.list_attendance_policies(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_attendance_policy_version(uuid, uuid) to authenticated, service_role;
grant execute on function app.export_attendance_sessions(uuid, uuid, date, date) to authenticated, service_role;

-- Internal engine functions -- service_role only (called exclusively from
-- inside this migration's own already-authorized SECURITY DEFINER functions,
-- mirrors app.next_employee_number/app._recalculate_session_exceptions's own
-- established "internal, no direct authenticated grant" convention).
grant execute on function app._ingest_attendance_event(app.employees, text, text, timestamptz, geography, text, jsonb, uuid, uuid, text) to service_role;
grant execute on function app._recalculate_session_exceptions(uuid) to service_role;
