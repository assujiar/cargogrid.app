-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-007 (Shift, Roster and
-- Scheduling, Prompt 279) -- the SECOND of the 3-prompt Tier-C batch
-- HRT-278..280 (Attendance / Shift-Roster / Leave-Permit-Business-Trip; batch
-- capped at 3 per docs/standards/BUILD_EXECUTION_PROTOCOL.md section 3.4).
-- Builds versioned shift definitions, rotating roster cycles, per-employee
-- schedule assignment/publish, coverage requirements, and a governed swap
-- workflow against app.employees (HRT-274) and app.org_units (HRT-275/
-- ADR-0023 Part A) -- never a second employee/organization root. Integrates
-- with app.attendance_sessions (HRT-278) via a SEPARATE, later additive
-- migration (20260730920000) rather than touching this checkpoint's own
-- tables in the same statement as the binding -- keeps this migration's own
-- rollback boundary clean.
--
-- Design decisions, disclosed rather than left implicit (mirrors every prior
-- HRT checkpoint's own header shape):
--
-- 1. **Shift definitions are versioned exactly like app.attendance_policies/
--    app.attendance_policy_versions (HRT-278 decision 3).** app.shift_templates
--    is the scope pointer (tenant-wide when org_unit_id is null, or scoped to
--    one branch/org_unit node); app.shift_template_versions is the actual
--    effective-dated ruleset (timezone, day boundary, shift_type, optional
--    grace overrides). A real child table, app.shift_segments, carries the
--    work/break segment list (section 20's own "define shift segment...
--    invariants") -- never a flat jsonb blob for a structure this repository's
--    own Governed Engine pattern already has real CHECK-constrained precedent
--    for (rate_version/job_offer_version/checklist_template_version/
--    attendance_policy_version all use this exact parent/version/publish
--    shape).
--
-- 2. **Segment ordering/cross-midnight rule (section 20/24's own "grace/
--    cross-midnight rules... explicit, not inferred").** At most the LAST
--    segment in sequence order may cross midnight (end_time < start_time);
--    every earlier segment must have end_time > start_time and the next
--    segment's start_time must be >= the previous segment's end_time (no
--    overlap, strictly chronological). This models fixed, split (multiple
--    work+break segments), and cross-midnight shifts correctly with a single,
--    provable rule -- disclosed as a deliberate V1 simplification rather than
--    a full interval-algebra engine (no requirement anywhere in the source
--    prompt names a shift with more than one midnight crossing).
--
-- 3. **Rotating roster is a real, separate two-table construct**
--    (app.roster_cycles/app.roster_cycle_slots), not folded into
--    shift_template_versions -- a rotating PATTERN (which shift applies on
--    which day-offset of an N-day cycle) is a materially different shape from
--    a single shift's own segment list, and the source prompt's own
--    alternative flow (section 22) names "rotating roster" as its own case.
--    A cycle must publish (every day_offset 0..cycle_length_days-1 filled,
--    including explicit "day off" nulls) before app.generate_roster_schedule_
--    assignments may consume it -- mirrors every other Governed Engine's own
--    "cannot use a draft" rule.
--
-- 4. **app.schedule_assignments is BOTH the live assignment record AND the
--    published snapshot (section 13's own "schedule assignment... and
--    published snapshot records")** -- no second, duplicating snapshot table.
--    status='scheduled' is an editable HR draft; status='published' is the
--    section 24 "retains exact shift/calendar/config versions... immutable by
--    normal role" governed truth attendance/leave/overtime bind to (via
--    app.resolve_effective_schedule_assignment, published rows only); a
--    revision to an ALREADY-PUBLISHED slot is a NEW row (app.
--    assign_employee_schedule always inserts a new row and supersedes any
--    prior active one, never a destructive UPDATE of a published row's own
--    substantive fields) -- matches app.employee_position_assignments'
--    (HRT-275) identical "every real transition is a new row" discipline.
--    V1-bounded to one active-or-published assignment per (employee,
--    work_date) -- disclosed simplification, mirrors app.attendance_sessions'
--    own identical single-row-per-workday bound (HRT-278).
--
-- 5. **Authority bar matches blast radius, not surface category (HRT-277's
--    own worst finding, designed against from the start).** Creating/
--    superseding a still-DRAFT ('scheduled') assignment is HRS:Edit;
--    superseding or cancelling an already-PUBLISHED assignment -- the
--    "immutable by normal role" governed truth other capabilities already
--    bind to -- requires HRS:Override, the same bar app.terminate_employee/
--    app.waive_attendance_exception use. Publishing a batch of draft
--    assignments (the moment they become that governed truth) is HRS:Approve,
--    matching app.publish_attendance_policy_version's identical bar.
--
-- 6. **Cancel genuinely cancels, never leaves a dependent process live**
--    (HRT-276 section 12.4 / HRT-277 section 12.7 / HRT-278 decision 9's own
--    repeatedly-found "dependent in-flight process not cancelled" class,
--    designed against here from the first migration). Cancelling a schedule
--    assignment that is the subject of a still-pending swap request cancels
--    that swap request too, via a direct, unlocked, conditional UPDATE (never
--    a separate pre-lock) -- see decision 7's own lock-order note for why.
--
-- 7. **Lock order (taxonomy C-21), stated explicitly.** The two functions in
--    this migration that ever touch both an app.schedule_assignments row and
--    an app.schedule_swap_requests row always lock the ASSIGNMENT row(s)
--    first, the SWAP REQUEST row second -- never the reverse.
--    app.cancel_schedule_assignment locks its own target assignment first
--    (its primary target), then reaches the dependent swap request via a
--    single conditional UPDATE (no separate pre-lock, so it never independently
--    holds a swap-request lock before an assignment lock). app.decide_
--    schedule_swap_request does a PLAIN unlocked read of the swap request
--    first only to discover which two assignment ids to lock (mirrors HRT-276
--    section 12.4's own "plain-read-before-lock" precedent exactly) --locks
--    both assignment rows in GLOBAL ascending-uuid order (least/greatest,
--    deadlock-safe against itself under concurrent overlapping swaps) -- THEN
--    locks and re-validates the swap request row itself. Both functions
--    therefore share the identical assignment-before-swap-request order; no
--    lock-order cycle between them is possible.
--
-- 8. **Batch schedule generation reuses PLT-132's real background-job
--    framework, the first genuine HRIS-domain adopter of its own generic
--    job_type list (PLT-132's own header: "no business logic for any of
--    these eight new types is implemented here").** app.jobs.job_type is
--    widened by one more code, 'roster_generation', on BOTH of its two real
--    sources of truth (ATW-031/ISS-2026-012,
--    20260730410000_harden_job_type_single_source_of_truth.sql): the
--    app.jobs table's own literal CHECK constraint (drop/add, deliberately
--    NOT function-backed, per ATW-031's own reasoning) and
--    app.generic_job_types() (the single function both app.enqueue_job and
--    app.dispatch_event_as_job already call internally -- neither of THOSE
--    two functions is touched by this migration at all, since ATW-031
--    already collapsed their own independent literals into that one call).
--    Reusing the framework, never building a second one, and never
--    reintroducing the exact duplicated-list drift ATW-031 closed. Since this
--    repository has NO
--    live worker anywhere yet that dequeues app.jobs (standing, repeatedly
--    disclosed ISS-2026-015, most recently re-disclosed at HRT-278 decision
--    7), app.generate_roster_schedule_assignments self-claims the SPECIFIC
--    job row it just created (by job_id, under its own row lock -- never the
--    generic queue-wide app.claim_next_job, which selects "next pending job
--    of these types" tenant-wide and would be nondeterministic against a
--    caller that must process exactly the row it just created), does the
--    real bounded (<=92 days) generation work synchronously in the same
--    call, then calls the SAME app.complete_job() any future live poller
--    would call -- a genuine, non-bypassing use of the real lifecycle
--    primitives, not a second tracking mechanism.
--
-- 9. **Attendance integration is additive and structurally optional, in its
--    own separate migration (20260730920000) -- never blocking.** A tenant
--    that has not adopted Shift/Roster at all keeps attendance working
--    exactly as HRT-278 shipped it (schedule_assignment_id stays null,
--    zero behavior change). Deeper binding of exception-detection formulas
--    (late/early_leave) to a SPECIFIC shift's own segment times, rather than
--    the attendance policy's own generic workday window, is deliberately
--    NOT built here -- the exact "reserve the field, do not build the future
--    capability" discipline this codebase already used twice (HRT-274
--    decision 3, HRT-278 decision 1) -- reserved for whichever future
--    checkpoint (most plausibly Prompt 281, Overtime and Timesheet, which
--    already owns time-computation rules this domain does not) actually
--    needs it, never spent unused here.
--
-- 10. **RBAC.** Zero new app.permissions rows -- the eleven HRS actions
--     HRT-274 already seeded (View/Create/Edit/Delete/Approve/Export/View
--     personal data/Reject/Import/Download/Override) cover every write this
--     checkpoint performs, mirroring HRT-278 decision 11's identical choice.
--
-- 11. **Sensitive free-text fields are column-restricted from THIS, the
--     FIRST, migration** (never retrofitted -- the exact defect class HRT-276's
--     own Tier C review found and had to fix after the fact): app.
--     schedule_assignments.cancel_reason, app.schedule_swap_requests.reason/
--     decided_reason are excluded from the plain `authenticated` column grant
--     applied in this migration's own first grant block -- mirroring
--     app.attendance_correction_requests' identical column set and, like
--     that table's own established precedent, simply never projected by any
--     read RPC below (structural masking by omission from the RETURNS TABLE
--     shape, the same convention HRT-278's own list_attendance_correction_
--     requests already established, rather than a runtime is-self branch).
--
-- 12. **Coverage preview doubles as the "Operations... workforce availability
--     projection" surface (section 26)**, returning aggregate headcount
--     counts only, never employee-level identity -- no new cross-domain
--     Operations permission is invented, since no established, canonical
--     Operations-side permission for consuming HR schedules exists yet
--     (mirrors HRT-278's own "forward contract, not a live integration"
--     framing for Payroll). A dedicated Operations-side consumption
--     integration is that module's own future scope, disclosed rather than
--     forced.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its
-- own explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC
-- statement before its final grants, the standing per-migration convention
-- since PLT-118.

-- ===========================================================================
-- 1. app.shift_templates -- scope pointer (decision 1).
-- ===========================================================================

create table app.shift_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid references app.org_units (id),
  code text not null,
  name text not null,
  status text not null default 'draft',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shift_templates_code_check check (length(trim(code)) > 0),
  constraint shift_templates_name_check check (length(trim(name)) > 0),
  constraint shift_templates_status_check check (status in ('draft', 'published', 'archived'))
);

comment on table app.shift_templates is
  'HRT-279 (decision 1): tenant- or org_unit-scoped shift definition scope pointer, mirrors app.attendance_policies (HRT-278) exactly.';

create unique index shift_templates_tenant_code_unique on app.shift_templates (tenant_id, code);
create index shift_templates_tenant_status_idx on app.shift_templates (tenant_id, status);
create index shift_templates_tenant_org_unit_idx on app.shift_templates (tenant_id, org_unit_id) where org_unit_id is not null;

-- ===========================================================================
-- 2. app.shift_template_versions -- effective-dated ruleset.
-- ===========================================================================

create table app.shift_template_versions (
  id uuid primary key default gen_random_uuid(),
  shift_template_id uuid not null references app.shift_templates (id),
  tenant_id uuid not null references app.tenants (id),
  version_number integer not null,
  status text not null default 'draft',
  effective_from date not null,
  timezone text not null,
  day_boundary_local_time time not null default '00:00:00',
  shift_type text not null default 'fixed',
  grace_late_minutes integer,
  grace_early_minutes integer,
  crosses_midnight boolean not null default false,
  total_work_minutes integer not null,
  total_break_minutes integer not null default 0,
  published_at timestamptz,
  published_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shift_template_versions_status_check check (status in ('draft', 'published', 'superseded')),
  constraint shift_template_versions_shift_type_check check (shift_type in ('fixed', 'flexible', 'split')),
  constraint shift_template_versions_grace_late_check check (grace_late_minutes is null or (grace_late_minutes >= 0 and grace_late_minutes <= 240)),
  constraint shift_template_versions_grace_early_check check (grace_early_minutes is null or (grace_early_minutes >= 0 and grace_early_minutes <= 240)),
  constraint shift_template_versions_total_work_check check (total_work_minutes > 0),
  constraint shift_template_versions_total_break_check check (total_break_minutes >= 0),
  constraint shift_template_versions_published_shape_check check (
    (status <> 'published') or (published_at is not null and published_by is not null)
  ),
  constraint shift_template_versions_template_effective_unique unique (shift_template_id, effective_from)
);

comment on function app.validate_iana_timezone is
  'PLT-134/HRT-278: shared IANA timezone validator, reused unchanged by app.create_shift_template_version below -- never a second implementation.';

comment on table app.shift_template_versions is
  'HRT-279 (decisions 1-2): effective-dated shift ruleset. grace_late_minutes/grace_early_minutes are OPTIONAL per-shift overrides (null = inherit the attendance policy''s own grace, HRT-278) -- never a duplicate, independently-drifting copy of the same concept. total_work_minutes/total_break_minutes/crosses_midnight are computed once at create time from the segment list app.create_shift_template_version validates in the same call, never separately recomputed by a read RPC.';

create index shift_template_versions_template_idx on app.shift_template_versions (shift_template_id, status, effective_from desc);

-- ===========================================================================
-- 3. app.shift_segments -- work/break segment list (decision 2).
-- ===========================================================================

create table app.shift_segments (
  id uuid primary key default gen_random_uuid(),
  shift_template_version_id uuid not null references app.shift_template_versions (id),
  tenant_id uuid not null references app.tenants (id),
  sequence_number integer not null,
  segment_type text not null,
  start_time time not null,
  end_time time not null,
  crosses_midnight boolean not null,
  duration_minutes integer not null,
  constraint shift_segments_sequence_check check (sequence_number >= 0),
  constraint shift_segments_type_check check (segment_type in ('work', 'break')),
  constraint shift_segments_duration_check check (duration_minutes > 0),
  constraint shift_segments_version_sequence_unique unique (shift_template_version_id, sequence_number)
);

comment on table app.shift_segments is
  'HRT-279 (decision 2): one governed work/break segment. Written exclusively by app.create_shift_template_version in the SAME transaction as its own parent version row -- never independently added/edited after the fact (a shift revision creates a whole new version, matching this migration''s own "every real transition is a new row" discipline).';

create index shift_segments_version_idx on app.shift_segments (shift_template_version_id, sequence_number);

-- ===========================================================================
-- 4. app.roster_holidays -- calendar/holiday reference (section 13).
-- ===========================================================================

create table app.roster_holidays (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid references app.org_units (id),
  holiday_date date not null,
  name text not null,
  is_working_day boolean not null default false,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint roster_holidays_name_check check (length(trim(name)) > 0),
  constraint roster_holidays_status_check check (status in ('active', 'removed'))
);

comment on table app.roster_holidays is
  'HRT-279 (section 13): tenant- or org_unit-scoped holiday calendar reference. is_working_day=true marks a deliberate override (a normally-observed holiday that this tenant/branch treats as a working day) -- informational to schedule/coverage preview, never a hard scheduling block (a tenant may legitimately schedule holiday-pay work).';

create unique index roster_holidays_tenant_wide_unique on app.roster_holidays (tenant_id, holiday_date) where org_unit_id is null and status = 'active';
create unique index roster_holidays_org_unit_unique on app.roster_holidays (tenant_id, org_unit_id, holiday_date) where org_unit_id is not null and status = 'active';
create index roster_holidays_tenant_date_idx on app.roster_holidays (tenant_id, holiday_date) where status = 'active';

-- ===========================================================================
-- 5. app.roster_cycles / app.roster_cycle_slots -- rotating pattern
--    (decision 3).
-- ===========================================================================

create table app.roster_cycles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid references app.org_units (id),
  name text not null,
  cycle_length_days integer not null,
  status text not null default 'draft',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint roster_cycles_name_check check (length(trim(name)) > 0),
  constraint roster_cycles_status_check check (status in ('draft', 'published', 'archived')),
  constraint roster_cycles_length_check check (cycle_length_days > 0 and cycle_length_days <= 60)
);

comment on table app.roster_cycles is
  'HRT-279 (decision 3): a rotating roster pattern header (section 22''s "rotating roster"). Must be published (every day_offset 0..cycle_length_days-1 filled in app.roster_cycle_slots) before app.generate_roster_schedule_assignments may consume it.';

create index roster_cycles_tenant_status_idx on app.roster_cycles (tenant_id, status);

create table app.roster_cycle_slots (
  id uuid primary key default gen_random_uuid(),
  roster_cycle_id uuid not null references app.roster_cycles (id),
  tenant_id uuid not null references app.tenants (id),
  day_offset integer not null,
  shift_template_id uuid references app.shift_templates (id),
  created_by text,
  created_at timestamptz not null default now(),
  constraint roster_cycle_slots_day_offset_check check (day_offset >= 0),
  constraint roster_cycle_slots_cycle_offset_unique unique (roster_cycle_id, day_offset)
);

comment on table app.roster_cycle_slots is
  'HRT-279: one day-offset -> shift_template mapping within a rotating cycle. shift_template_id null means "day off" for that offset -- an explicit, real row, never an implicit gap (app.publish_roster_cycle requires every offset 0..cycle_length_days-1 to have a row before it will publish).';

create index roster_cycle_slots_cycle_idx on app.roster_cycle_slots (roster_cycle_id, day_offset);

-- ===========================================================================
-- 6. app.schedule_assignments -- the core per-employee-per-workday
--    assignment/published snapshot (decision 4).
-- ===========================================================================

create table app.schedule_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  shift_template_version_id uuid not null references app.shift_template_versions (id),
  work_date date not null,
  status text not null default 'scheduled',
  source text not null default 'manual',
  roster_cycle_id uuid references app.roster_cycles (id),
  previous_assignment_id uuid references app.schedule_assignments (id),
  cancel_reason text,
  published_at timestamptz,
  published_by text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schedule_assignments_status_check check (status in ('scheduled', 'published', 'cancelled', 'superseded')),
  constraint schedule_assignments_source_check check (source in ('manual', 'bulk_generated', 'swap')),
  constraint schedule_assignments_cancel_shape_check check (status <> 'cancelled' or (cancel_reason is not null and length(trim(cancel_reason)) > 0)),
  constraint schedule_assignments_published_shape_check check ((status <> 'published') or (published_at is not null and published_by is not null))
);

comment on table app.schedule_assignments is
  'HRT-279 (decision 4): one row per employee-per-workday assignment. Doubles as the published snapshot section 13 names -- status=''published'' rows are the immutable-by-normal-role governed truth app.resolve_effective_schedule_assignment (and, via a separate additive migration, app.attendance_sessions) binds to. Every real transition is a NEW row (previous_assignment_id links lineage) -- never a destructive UPDATE of a published row''s own shift/date. V1-bounded to one active-or-published assignment per (employee, work_date), mirrors app.attendance_sessions'' own identical bound (HRT-278), disclosed simplification.';

create unique index schedule_assignments_employee_workdate_active_unique on app.schedule_assignments (tenant_id, employee_id, work_date) where status in ('scheduled', 'published');
create index schedule_assignments_tenant_workdate_idx on app.schedule_assignments (tenant_id, work_date desc);
create index schedule_assignments_tenant_employee_workdate_idx on app.schedule_assignments (tenant_id, employee_id, work_date desc);
create index schedule_assignments_tenant_status_idx on app.schedule_assignments (tenant_id, status);
create index schedule_assignments_version_idx on app.schedule_assignments (shift_template_version_id);
create index schedule_assignments_cycle_idx on app.schedule_assignments (roster_cycle_id) where roster_cycle_id is not null;
create unique index schedule_assignments_idempotency_unique on app.schedule_assignments (tenant_id, employee_id, idempotency_key) where idempotency_key is not null;

-- ===========================================================================
-- 7. app.roster_coverage_requirements -- coverage requirement (section 13).
-- ===========================================================================

create table app.roster_coverage_requirements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid not null references app.org_units (id),
  shift_template_id uuid not null references app.shift_templates (id),
  day_of_week integer not null,
  min_headcount integer not null,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint roster_coverage_requirements_dow_check check (day_of_week >= 0 and day_of_week <= 6),
  constraint roster_coverage_requirements_headcount_check check (min_headcount >= 0),
  constraint roster_coverage_requirements_status_check check (status in ('active', 'inactive')),
  constraint roster_coverage_requirements_scope_unique unique (tenant_id, org_unit_id, shift_template_id, day_of_week)
);

comment on table app.roster_coverage_requirements is
  'HRT-279 (section 13): minimum scheduled headcount for one (org_unit, shift_template, day_of_week 0=Sunday..6=Saturday) tuple. A tenant wanting every-day coverage creates 7 rows -- disclosed V1 simplification (no "any day" wildcard row).';

create index roster_coverage_requirements_tenant_idx on app.roster_coverage_requirements (tenant_id, org_unit_id, status);

-- ===========================================================================
-- 8. app.schedule_swap_requests -- governed swap workflow (section 22/24).
-- ===========================================================================

create table app.schedule_swap_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  requesting_employee_id uuid not null references app.employees (master_record_id),
  requested_by_auth_user_id uuid not null,
  assignment_id uuid not null references app.schedule_assignments (id),
  target_employee_id uuid not null references app.employees (master_record_id),
  target_assignment_id uuid not null references app.schedule_assignments (id),
  reason text not null,
  status text not null default 'pending_approval',
  decided_by text,
  decided_at timestamptz,
  decided_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schedule_swap_requests_reason_check check (length(trim(reason)) > 0),
  constraint schedule_swap_requests_status_check check (status in ('pending_approval', 'approved', 'rejected', 'cancelled')),
  constraint schedule_swap_requests_not_self_check check (requesting_employee_id <> target_employee_id),
  constraint schedule_swap_requests_not_same_assignment_check check (assignment_id <> target_assignment_id),
  constraint schedule_swap_requests_decided_shape_check check (
    (status = 'pending_approval' and decided_at is null and decided_by is null) or
    (status = 'cancelled' and decided_at is null and decided_by is null) or
    (status in ('approved', 'rejected') and decided_at is not null and decided_by is not null and decided_reason is not null and length(trim(decided_reason)) > 0)
  )
);

comment on table app.schedule_swap_requests is
  'HRT-279 (decision 6/7): direct propose (self-or-HRS:Edit)/decide (HRS:Approve) two-employee assignment swap, mirroring app.attendance_correction_requests (HRT-278) exactly. reason/decided_reason are column-restricted (decision 11).';

create index schedule_swap_requests_tenant_status_idx on app.schedule_swap_requests (tenant_id, status);
create index schedule_swap_requests_requester_idx on app.schedule_swap_requests (tenant_id, requesting_employee_id);
create index schedule_swap_requests_target_idx on app.schedule_swap_requests (tenant_id, target_employee_id);
create index schedule_swap_requests_assignment_idx on app.schedule_swap_requests (assignment_id) where status = 'pending_approval';
create index schedule_swap_requests_target_assignment_idx on app.schedule_swap_requests (target_assignment_id) where status = 'pending_approval';
create unique index schedule_swap_requests_idempotency_unique on app.schedule_swap_requests (tenant_id, requesting_employee_id, idempotency_key) where idempotency_key is not null;

-- ===========================================================================
-- 9. Shared internal helper.
-- ===========================================================================

create function app.resolve_effective_schedule_assignment(p_tenant_id uuid, p_employee_id uuid, p_work_date date)
returns setof app.schedule_assignments
language sql
stable
as $$
  select sa.*
  from app.schedule_assignments sa
  where sa.tenant_id = p_tenant_id and sa.employee_id = p_employee_id and sa.work_date = p_work_date and sa.status = 'published'
  limit 1;
$$;

comment on function app.resolve_effective_schedule_assignment is
  'HRT-279 (decision 4/9): the single resolution point any downstream capability (attendance, future leave/overtime/Operations) uses to find the PUBLISHED schedule snapshot for one employee-workday. Zero rows = "no roster assigned" -- never an error, since Shift/Roster adoption is optional per tenant.';

grant execute on function app.resolve_effective_schedule_assignment(uuid, uuid, date) to authenticated, service_role;

-- ===========================================================================
-- 10. Shift template authoring RPCs.
-- ===========================================================================

create function app.create_shift_template(
  p_tenant_id uuid, p_org_unit_id uuid, p_code text, p_name text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.shift_templates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.shift_templates;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'invalid_code: code must not be empty' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name must not be empty' using errcode = 'check_violation';
  end if;

  if p_org_unit_id is not null and not exists (select 1 from app.org_units where id = p_org_unit_id and tenant_id = p_tenant_id) then
    raise exception 'org_unit_not_found: no org unit % in tenant %', p_org_unit_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  insert into app.shift_templates (tenant_id, org_unit_id, code, name, created_by)
  values (p_tenant_id, p_org_unit_id, p_code, p_name, p_actor_label)
  returning * into v_template;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_shift_template',
    'app.shift_templates', v_template.id, 'success', null, null, to_jsonb(v_template)
  );

  return v_template;
end;
$$;

create function app.create_shift_template_version(
  p_shift_template_id uuid,
  p_timezone text,
  p_day_boundary_local_time time,
  p_shift_type text,
  p_grace_late_minutes integer,
  p_grace_early_minutes integer,
  p_effective_from date,
  p_segments jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shift_template_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.shift_templates;
  v_next_version integer;
  v_version app.shift_template_versions;
  v_segment jsonb;
  v_idx integer := 0;
  v_seg_type text;
  v_start time;
  v_end time;
  v_crosses boolean;
  v_duration integer;
  v_prev_end time;
  v_prev_crosses boolean := false;
  v_total_work integer := 0;
  v_total_break integer := 0;
  v_final_crosses boolean := false;
  v_work_seg_count integer := 0;
begin
  select * into v_template from app.shift_templates where id = p_shift_template_id;
  if not found or not app.has_active_tenant_membership(v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'shift_template_not_found: %', p_shift_template_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_template.status = 'archived' then
    raise exception 'invalid_transition: shift template % is archived, cannot author a new version', p_shift_template_id using errcode = 'check_violation';
  end if;

  if not app.validate_iana_timezone(p_timezone) then
    raise exception 'invalid_timezone: % is not a recognized IANA timezone', p_timezone using errcode = 'check_violation';
  end if;

  if p_segments is null or jsonb_typeof(p_segments) <> 'array' or jsonb_array_length(p_segments) = 0 then
    raise exception 'invalid_segments: at least one work/break segment is required' using errcode = 'check_violation';
  end if;

  -- decision 2: validate segment order/shape. sequence_number is assigned by
  -- array position, 0-based.
  for v_segment in select * from jsonb_array_elements(p_segments) loop
    v_seg_type := v_segment ->> 'segment_type';
    if v_seg_type is null or v_seg_type not in ('work', 'break') then
      raise exception 'invalid_segment_type: segment % has segment_type %, expected work or break', v_idx, coalesce(v_seg_type, '(missing)')
        using errcode = 'check_violation';
    end if;

    begin
      v_start := (v_segment ->> 'start_time')::time;
      v_end := (v_segment ->> 'end_time')::time;
    exception when others then
      raise exception 'invalid_segment_time: segment % has an unparsable start_time/end_time', v_idx using errcode = 'check_violation';
    end;

    if v_prev_crosses then
      raise exception 'invalid_segment_order: segment % follows a segment that already crosses midnight -- at most the LAST segment may cross midnight', v_idx
        using errcode = 'check_violation';
    end if;

    v_crosses := v_end < v_start;
    if v_end = v_start then
      raise exception 'invalid_segment_duration: segment % has a zero-length window (start_time = end_time)', v_idx using errcode = 'check_violation';
    end if;

    if v_idx > 0 and v_start < v_prev_end then
      raise exception 'invalid_segment_overlap: segment % starts (%) before the previous segment ends (%)', v_idx, v_start, v_prev_end
        using errcode = 'check_violation';
    end if;

    v_duration := case when v_crosses then (1440 - (extract(epoch from v_start) / 60)::integer + (extract(epoch from v_end) / 60)::integer)
                        else ((extract(epoch from v_end) / 60)::integer - (extract(epoch from v_start) / 60)::integer) end;

    if v_seg_type = 'work' then
      v_total_work := v_total_work + v_duration;
      v_work_seg_count := v_work_seg_count + 1;
    else
      v_total_break := v_total_break + v_duration;
    end if;

    v_final_crosses := v_crosses;
    v_prev_end := v_end;
    v_prev_crosses := v_crosses;
    v_idx := v_idx + 1;
  end loop;

  if v_work_seg_count = 0 then
    raise exception 'invalid_segments: at least one work segment is required' using errcode = 'check_violation';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.shift_template_versions where shift_template_id = p_shift_template_id;

  insert into app.shift_template_versions (
    shift_template_id, tenant_id, version_number, effective_from, timezone, day_boundary_local_time, shift_type,
    grace_late_minutes, grace_early_minutes, crosses_midnight, total_work_minutes, total_break_minutes, created_by
  ) values (
    p_shift_template_id, v_template.tenant_id, v_next_version, p_effective_from, p_timezone, coalesce(p_day_boundary_local_time, '00:00:00'::time),
    coalesce(p_shift_type, 'fixed'), p_grace_late_minutes, p_grace_early_minutes, v_final_crosses, v_total_work, v_total_break, p_actor_label
  ) returning * into v_version;

  v_idx := 0;
  for v_segment in select * from jsonb_array_elements(p_segments) loop
    v_start := (v_segment ->> 'start_time')::time;
    v_end := (v_segment ->> 'end_time')::time;
    v_crosses := v_end < v_start;
    v_duration := case when v_crosses then (1440 - (extract(epoch from v_start) / 60)::integer + (extract(epoch from v_end) / 60)::integer)
                        else ((extract(epoch from v_end) / 60)::integer - (extract(epoch from v_start) / 60)::integer) end;

    insert into app.shift_segments (shift_template_version_id, tenant_id, sequence_number, segment_type, start_time, end_time, crosses_midnight, duration_minutes)
    values (v_version.id, v_template.tenant_id, v_idx, v_segment ->> 'segment_type', v_start, v_end, v_crosses, v_duration);

    v_idx := v_idx + 1;
  end loop;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_shift_template_version',
    'app.shift_template_versions', v_version.id, 'success', null, null,
    jsonb_build_object('shift_template_id', p_shift_template_id, 'version_number', v_next_version, 'segment_count', v_idx)
  );

  return v_version;
end;
$$;

comment on function app.create_shift_template_version is
  'HRT-279 (decision 2): validates and inserts the full segment list in the SAME transaction as the parent version row. total_work_minutes/total_break_minutes/crosses_midnight are computed here once, never recomputed by a read path.';

create function app.publish_shift_template_version(
  p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.shift_template_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.shift_template_versions;
begin
  select * into v_version from app.shift_template_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'shift_template_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: shift template version % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: shift template version % is %, only a draft may be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  update app.shift_template_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: shift template version % target row was concurrently modified (expected version %)', p_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.shift_templates set status = 'published' where id = v_version.shift_template_id and status = 'draft';

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_shift_template_version',
    'app.shift_template_versions', p_version_id, 'success', null, null, jsonb_build_object('effective_from', v_version.effective_from)
  );

  return v_version;
end;
$$;

-- ===========================================================================
-- 11. Roster cycle RPCs (decision 3).
-- ===========================================================================

create function app.create_roster_cycle(
  p_tenant_id uuid, p_org_unit_id uuid, p_name text, p_cycle_length_days integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.roster_cycles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cycle app.roster_cycles;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name must not be empty' using errcode = 'check_violation';
  end if;
  if p_cycle_length_days is null or p_cycle_length_days <= 0 or p_cycle_length_days > 60 then
    raise exception 'invalid_cycle_length: cycle_length_days must be between 1 and 60' using errcode = 'check_violation';
  end if;
  if p_org_unit_id is not null and not exists (select 1 from app.org_units where id = p_org_unit_id and tenant_id = p_tenant_id) then
    raise exception 'org_unit_not_found: no org unit % in tenant %', p_org_unit_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  insert into app.roster_cycles (tenant_id, org_unit_id, name, cycle_length_days, created_by)
  values (p_tenant_id, p_org_unit_id, p_name, p_cycle_length_days, p_actor_label)
  returning * into v_cycle;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_roster_cycle',
    'app.roster_cycles', v_cycle.id, 'success', null, null, to_jsonb(v_cycle)
  );

  return v_cycle;
end;
$$;

create function app.set_roster_cycle_slot(
  p_roster_cycle_id uuid, p_day_offset integer, p_shift_template_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.roster_cycle_slots
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cycle app.roster_cycles;
  v_template app.shift_templates;
  v_slot app.roster_cycle_slots;
begin
  select * into v_cycle from app.roster_cycles where id = p_roster_cycle_id;
  if not found or not app.has_active_tenant_membership(v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'roster_cycle_not_found: %', p_roster_cycle_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cycle.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cycle.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cycle.status <> 'draft' then
    raise exception 'invalid_transition: roster cycle % is %, only a draft cycle''s slots may be edited', p_roster_cycle_id, v_cycle.status
      using errcode = 'check_violation';
  end if;

  if p_day_offset is null or p_day_offset < 0 or p_day_offset >= v_cycle.cycle_length_days then
    raise exception 'invalid_day_offset: % is outside the cycle''s own range [0, %)', p_day_offset, v_cycle.cycle_length_days
      using errcode = 'check_violation';
  end if;

  if p_shift_template_id is not null then
    select * into v_template from app.shift_templates where id = p_shift_template_id;
    if not found or v_template.tenant_id <> v_cycle.tenant_id or v_template.status <> 'published' then
      raise exception 'shift_template_not_available: % is not a published shift template in this tenant', p_shift_template_id using errcode = 'no_data_found';
    end if;
  end if;

  insert into app.roster_cycle_slots (roster_cycle_id, tenant_id, day_offset, shift_template_id, created_by)
  values (p_roster_cycle_id, v_cycle.tenant_id, p_day_offset, p_shift_template_id, p_actor_label)
  on conflict (roster_cycle_id, day_offset) do update set shift_template_id = excluded.shift_template_id, created_by = excluded.created_by
  returning * into v_slot;

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_roster_cycle_slot',
    'app.roster_cycle_slots', v_slot.id, 'success', null, null,
    jsonb_build_object('roster_cycle_id', p_roster_cycle_id, 'day_offset', p_day_offset, 'shift_template_id', p_shift_template_id)
  );

  return v_slot;
end;
$$;

create function app.publish_roster_cycle(
  p_roster_cycle_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.roster_cycles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cycle app.roster_cycles;
  v_slot_count integer;
begin
  select * into v_cycle from app.roster_cycles where id = p_roster_cycle_id for update;
  if not found or not app.has_active_tenant_membership(v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'roster_cycle_not_found: %', p_roster_cycle_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cycle.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cycle.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cycle.record_version <> p_expected_version then
    raise exception 'stale_version: roster cycle % expected version % but found %', p_roster_cycle_id, p_expected_version, v_cycle.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_cycle.status <> 'draft' then
    raise exception 'invalid_transition: roster cycle % is %, only a draft may be published', p_roster_cycle_id, v_cycle.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_slot_count from app.roster_cycle_slots where roster_cycle_id = p_roster_cycle_id;
  if v_slot_count <> v_cycle.cycle_length_days then
    raise exception 'incomplete_roster_cycle: cycle % has % of % day-offsets filled -- every offset must have a slot (day off is an explicit null shift) before publish', p_roster_cycle_id, v_slot_count, v_cycle.cycle_length_days
      using errcode = 'check_violation';
  end if;

  update app.roster_cycles set status = 'published' where id = p_roster_cycle_id and record_version = p_expected_version returning * into v_cycle;
  if not found then
    raise exception 'stale_version: roster cycle % target row was concurrently modified (expected version %)', p_roster_cycle_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_roster_cycle',
    'app.roster_cycles', p_roster_cycle_id, 'success', null, null, '{}'::jsonb
  );

  return v_cycle;
end;
$$;

-- ===========================================================================
-- 12. Holiday calendar RPCs.
-- ===========================================================================

create function app.set_roster_holiday(
  p_tenant_id uuid, p_org_unit_id uuid, p_holiday_date date, p_name text, p_is_working_day boolean, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.roster_holidays
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_holiday app.roster_holidays;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_holiday_date is null then
    raise exception 'invalid_holiday_date: holiday_date is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name must not be empty' using errcode = 'check_violation';
  end if;
  if p_org_unit_id is not null and not exists (select 1 from app.org_units where id = p_org_unit_id and tenant_id = p_tenant_id) then
    raise exception 'org_unit_not_found: no org unit % in tenant %', p_org_unit_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if p_org_unit_id is null then
    update app.roster_holidays set status = 'removed' where tenant_id = p_tenant_id and org_unit_id is null and holiday_date = p_holiday_date and status = 'active';
  else
    update app.roster_holidays set status = 'removed' where tenant_id = p_tenant_id and org_unit_id = p_org_unit_id and holiday_date = p_holiday_date and status = 'active';
  end if;

  insert into app.roster_holidays (tenant_id, org_unit_id, holiday_date, name, is_working_day, created_by)
  values (p_tenant_id, p_org_unit_id, p_holiday_date, p_name, coalesce(p_is_working_day, false), p_actor_label)
  returning * into v_holiday;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_roster_holiday',
    'app.roster_holidays', v_holiday.id, 'success', null, null, to_jsonb(v_holiday)
  );

  return v_holiday;
end;
$$;

comment on function app.set_roster_holiday is
  'HRT-279: idempotent upsert-by-replace -- any existing active holiday row for the same (tenant, org_unit, date) is marked removed and a fresh row inserted, never a destructive UPDATE of history.';

create function app.remove_roster_holiday(p_holiday_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.roster_holidays
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_holiday app.roster_holidays;
begin
  select * into v_holiday from app.roster_holidays where id = p_holiday_id for update;
  if not found or not app.has_active_tenant_membership(v_holiday.tenant_id, p_actor_auth_user_id) then
    raise exception 'roster_holiday_not_found: %', p_holiday_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_holiday.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_holiday.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_holiday.status <> 'active' then
    raise exception 'invalid_transition: roster holiday % is already %, cannot be removed again', p_holiday_id, v_holiday.status using errcode = 'check_violation';
  end if;

  update app.roster_holidays set status = 'removed' where id = p_holiday_id returning * into v_holiday;

  perform app.capture_audit_event(
    v_holiday.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_roster_holiday',
    'app.roster_holidays', p_holiday_id, 'success', null, null, '{}'::jsonb
  );

  return v_holiday;
end;
$$;

-- ===========================================================================
-- 13. Coverage requirement RPC.
-- ===========================================================================

create function app.set_schedule_coverage_requirement(
  p_tenant_id uuid, p_org_unit_id uuid, p_shift_template_id uuid, p_day_of_week integer, p_min_headcount integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.roster_coverage_requirements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.shift_templates;
  v_requirement app.roster_coverage_requirements;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.org_units where id = p_org_unit_id and tenant_id = p_tenant_id) then
    raise exception 'org_unit_not_found: no org unit % in tenant %', p_org_unit_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  select * into v_template from app.shift_templates where id = p_shift_template_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'shift_template_not_found: %', p_shift_template_id using errcode = 'no_data_found';
  end if;

  if p_day_of_week is null or p_day_of_week < 0 or p_day_of_week > 6 then
    raise exception 'invalid_day_of_week: % must be between 0 (Sunday) and 6 (Saturday)', p_day_of_week using errcode = 'check_violation';
  end if;
  if p_min_headcount is null or p_min_headcount < 0 then
    raise exception 'invalid_min_headcount: min_headcount must be non-negative' using errcode = 'check_violation';
  end if;

  insert into app.roster_coverage_requirements (tenant_id, org_unit_id, shift_template_id, day_of_week, min_headcount, created_by)
  values (p_tenant_id, p_org_unit_id, p_shift_template_id, p_day_of_week, p_min_headcount, p_actor_label)
  on conflict (tenant_id, org_unit_id, shift_template_id, day_of_week)
  do update set min_headcount = excluded.min_headcount, status = 'active', updated_at = now()
  returning * into v_requirement;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_schedule_coverage_requirement',
    'app.roster_coverage_requirements', v_requirement.id, 'success', null, null, to_jsonb(v_requirement)
  );

  return v_requirement;
end;
$$;

-- ===========================================================================
-- 14. Schedule assignment core RPCs (decisions 4/5).
-- ===========================================================================

create function app.assign_employee_schedule(
  p_tenant_id uuid, p_employee_id uuid, p_shift_template_version_id uuid, p_work_date date, p_source text, p_idempotency_key text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.schedule_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
  v_version app.shift_template_versions;
  v_existing app.schedule_assignments;
  v_existing_found boolean;
  v_new app.schedule_assignments;
  v_decision app.rbac_decision;
  v_has_edit boolean;
  v_has_override boolean;
begin
  select * into v_employee from app.employees where master_record_id = p_employee_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;
  if v_employee.tenant_id <> p_tenant_id then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;

  -- C-05: HRS:Edit and HRS:Override are a genuinely disjoint EITHER/OR pair
  -- (decision 5) -- Edit suffices for the no-existing-row/still-draft cases,
  -- Override is required -- and sufficient ON ITS OWN, an Override holder is
  -- NOT required to also hold Edit -- for superseding an already-published
  -- row. A coarse "holds at least one of the two" floor runs HERE,
  -- immediately after the tenant-membership fold and before ANY row-state
  -- disclosure (employee lifecycle_status, shift-version availability,
  -- whether an existing row is published, etc.) -- a caller with NEITHER
  -- permission, the real zero-authority threat this class targets, gets one
  -- generic rejection that discloses nothing about the target row.
  v_has_edit := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit')).allowed;
  v_has_override := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override')).allowed;
  if not v_has_edit and not v_has_override then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit/HRS:Override for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.lifecycle_status <> 'active' then
    raise exception 'employee_not_active: employee % is %, only an active employee may be scheduled', p_employee_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  select * into v_version from app.shift_template_versions where id = p_shift_template_version_id;
  if not found or v_version.tenant_id <> p_tenant_id or v_version.status <> 'published' then
    raise exception 'shift_template_version_not_available: % is not a published shift template version in this tenant', p_shift_template_version_id
      using errcode = 'no_data_found';
  end if;

  if p_work_date is null then
    raise exception 'invalid_work_date: work_date is required' using errcode = 'check_violation';
  end if;

  -- decision 4: any existing active-or-published row for this (employee,
  -- work_date) is locked and superseded, never destructively updated.
  -- v_existing_found is captured HERE, explicitly, into its own boolean --
  -- never relying on the bare FOUND special variable below, since the
  -- idempotency-replay lookup immediately after this also runs a SELECT and
  -- would silently overwrite FOUND with ITS OWN result before the decision-5
  -- authority branch ever reads it (a real bug this checkpoint's own
  -- adversarial db-testing caught live: a same-status, cross-purpose reuse of
  -- FOUND across two sequential SELECTs in the same function).
  select * into v_existing from app.schedule_assignments
  where tenant_id = p_tenant_id and employee_id = p_employee_id and work_date = p_work_date and status in ('scheduled', 'published')
  for update;
  v_existing_found := found;

  -- C-01: full-tuple idempotency replay.
  if p_idempotency_key is not null then
    declare
      v_replay app.schedule_assignments;
    begin
      select * into v_replay from app.schedule_assignments where tenant_id = p_tenant_id and employee_id = p_employee_id and idempotency_key = p_idempotency_key;
      if found then
        if v_replay.work_date = p_work_date and v_replay.shift_template_version_id = p_shift_template_version_id then
          return v_replay;
        else
          raise exception 'idempotency_key_conflict: key % was already used for a different schedule assignment', p_idempotency_key using errcode = 'unique_violation';
        end if;
      end if;
    end;
  end if;

  -- decision 5: superseding an already-PUBLISHED row is a strictly higher
  -- blast radius than superseding a still-draft one, and needs HRS:Override
  -- specifically -- the floor above only established the caller holds AT
  -- LEAST one of Edit/Override; this is the specific, per-case check for
  -- whichever one this row's own state actually requires.
  if v_existing_found and v_existing.status = 'published' then
    if not v_has_override then
      raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant % (superseding a published assignment)', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  else
    if not v_has_edit then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- The prior row (if any) MUST be marked superseded BEFORE the new row is
  -- inserted -- the partial unique index covers status in ('scheduled',
  -- 'published') together, so inserting the new 'scheduled' row first while
  -- the prior row still holds either of those two statuses for the SAME
  -- (tenant, employee, work_date) would violate that index immediately,
  -- before the old row could ever be superseded. Both rows are already
  -- locked (the prior row via the FOR UPDATE select above; the new row does
  -- not exist yet) so this ordering is race-free.
  if v_existing.id is not null then
    update app.schedule_assignments set status = 'superseded' where id = v_existing.id;
  end if;

  insert into app.schedule_assignments (tenant_id, employee_id, shift_template_version_id, work_date, source, previous_assignment_id, idempotency_key, created_by)
  values (p_tenant_id, p_employee_id, p_shift_template_version_id, p_work_date, coalesce(p_source, 'manual'), v_existing.id, p_idempotency_key, p_actor_label)
  returning * into v_new;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_employee_schedule',
    'app.schedule_assignments', v_new.id, 'success', null, null,
    jsonb_build_object('employee_id', p_employee_id, 'work_date', p_work_date, 'shift_template_version_id', p_shift_template_version_id, 'superseded_id', v_existing.id)
  );

  return v_new;
end;
$$;

comment on function app.assign_employee_schedule is
  'HRT-279 (decisions 4/5): always inserts a new row. If a prior scheduled-or-published row exists for the same (employee, work_date), it is superseded -- HRS:Edit suffices to supersede a still-draft (''scheduled'') row, HRS:Override is required to supersede an already-published one (the "immutable by normal role" governed truth).';

create function app.cancel_schedule_assignment(
  p_assignment_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
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

  perform app.capture_audit_event(
    v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_schedule_assignment',
    'app.schedule_assignments', p_assignment_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_assignment;
end;
$$;

create function app.publish_schedule_assignments(
  p_tenant_id uuid, p_from_date date, p_to_date date, p_org_unit_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns table (assignment_id uuid, published boolean, skip_reason text)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.schedule_assignments;
  v_employee app.employees;
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
    select sa.* from app.schedule_assignments sa
    join app.employees e on e.master_record_id = sa.employee_id
    where sa.tenant_id = p_tenant_id and sa.work_date between p_from_date and p_to_date and sa.status = 'scheduled'
      and (p_employee_id is null or sa.employee_id = p_employee_id)
      and (p_org_unit_id is null or e.branch_org_unit_id = p_org_unit_id or e.department_org_unit_id = p_org_unit_id)
    for update of sa
  loop
    select * into v_employee from app.employees where master_record_id = v_row.employee_id;
    if v_employee.lifecycle_status <> 'active' then
      assignment_id := v_row.id; published := false; skip_reason := 'employee_not_active';
      return next;
      continue;
    end if;

    if not exists (select 1 from app.shift_template_versions where id = v_row.shift_template_version_id and status = 'published') then
      assignment_id := v_row.id; published := false; skip_reason := 'shift_template_version_not_published';
      return next;
      continue;
    end if;

    update app.schedule_assignments
    set status = 'published', published_at = now(), published_by = p_actor_label
    where id = v_row.id;

    assignment_id := v_row.id; published := true; skip_reason := null;
    return next;
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_schedule_assignments',
    'app.schedule_assignments', null, 'success', null, null, jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date)
  );

  return;
end;
$$;

comment on function app.publish_schedule_assignments is
  'HRT-279 (section 25 "concurrency before publish"): batch-transitions ''scheduled'' rows to ''published'' -- the moment they become the immutable-by-normal-role governed truth app.resolve_effective_schedule_assignment binds to. Re-validates employee-active and shift-version-still-published at publish time, not merely at proposal time; a failed check skips that one row, never aborts the whole batch.';

-- ===========================================================================
-- 15. Batch generation: widen PLT-132's job_type list (decision 8), then the
--     generation RPC itself. Per ATW-031/ISS-2026-012 (`supabase/migrations/
--     20260730410000_harden_job_type_single_source_of_truth.sql`),
--     app.generic_job_types() is now the SINGLE authority app.enqueue_job and
--     app.dispatch_event_as_job both already call internally -- this
--     checkpoint widens ONLY that one function (plus the app.jobs table's
--     own literal CHECK, which ATW-031's own header explains is deliberately
--     NOT rewritten to call the function, so it is widened separately and a
--     standing db-test assertion in scripts/db-tests/background-job.sql
--     keeps the two set-equal). app.enqueue_job/app.dispatch_event_as_job
--     themselves are NOT touched -- ATW-031 already collapsed their own
--     independent literals into a single call to app.generic_job_types(), so
--     re-declaring either here would be the exact duplicated-list drift
--     ATW-031 closed, reintroduced. (A first draft of this migration
--     mistakenly widened app.enqueue_job directly from the ORIGINAL PLT-132
--     migration's own now-superseded literal, silently reverting the
--     'route_load_planning'/'print_label' types two later migrations had
--     already added -- caught live by this checkpoint's own full db:test run
--     against scripts/db-tests/advanced-tms-label-barcode-operations.sql's
--     own 'print_label' usage, and again by background-job.sql's own ATW-031
--     drift-gate assertion; fixed by adopting the real current single source
--     of truth instead, see build log.)
-- ===========================================================================

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry',
    'document_generation', 'dashboard_refresh', 'loyalty_expiration', 'recurring_billing',
    'integration_sync', 'route_load_planning', 'print_label', 'roster_generation'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'HRT-279 (decision 8): widened to add ''roster_generation'' -- the first HRIS domain adopter of PLT-132''s own generic job_type list. Kept set-equal with app.all_job_types() by scripts/db-tests/background-job.sql''s own standing ATW-031 drift-gate assertion.';

create or replace function app.generic_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation'
  ]::text[];
$$;

comment on function app.generic_job_types is
  'ATW-031 (ISS-2026-012), widened by HRT-279 (decision 8) to add ''roster_generation'' -- the single authority for which job_type values the GENERIC queue mechanics accept. app.enqueue_job and app.dispatch_event_as_job both already call this function directly (unchanged by this migration); app.all_job_types() (also unchanged) composes it with (''import'',''export'').';

create function app.generate_roster_schedule_assignments(
  p_tenant_id uuid, p_roster_cycle_id uuid, p_employee_ids uuid[], p_from_date date, p_to_date date, p_actor_auth_user_id uuid, p_actor_label text
)
returns table (created_count integer, superseded_count integer, skipped_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cycle app.roster_cycles;
  v_job app.jobs;
  v_worker_id text;
  v_employee_id uuid;
  v_offset integer;
  v_slot app.roster_cycle_slots;
  v_created integer := 0;
  v_superseded integer := 0;
  v_skipped integer := 0;
  v_existing_status text;
  v_day date;
  v_result app.schedule_assignments;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_cycle from app.roster_cycles where id = p_roster_cycle_id;
  if not found or v_cycle.tenant_id <> p_tenant_id or v_cycle.status <> 'published' then
    raise exception 'roster_cycle_not_available: % is not a published roster cycle in this tenant', p_roster_cycle_id using errcode = 'no_data_found';
  end if;

  if p_employee_ids is null or array_length(p_employee_ids, 1) is null then
    raise exception 'invalid_employee_ids: at least one employee_id is required' using errcode = 'check_violation';
  end if;

  if p_from_date is null or p_to_date is null or p_to_date < p_from_date or (p_to_date - p_from_date) > 92 then
    raise exception 'invalid_date_range: date range must be non-empty and at most 92 days (decision 8 -- bounded generation)' using errcode = 'check_violation';
  end if;

  -- decision 8: a real app.jobs row, tracked through the actual PLT-132
  -- lifecycle (enqueue -> self-claim -> complete), never a second tracking
  -- mechanism.
  v_job := app.enqueue_job(
    p_tenant_id, 'roster_generation',
    jsonb_build_object('roster_cycle_id', p_roster_cycle_id, 'from_date', p_from_date, 'to_date', p_to_date, 'employee_count', array_length(p_employee_ids, 1)),
    0, null, 1, p_actor_auth_user_id, p_actor_label
  );
  v_worker_id := 'inline-roster-generator:' || p_actor_auth_user_id::text;

  -- Table-aliased and qualified throughout -- this function's own RETURNS
  -- TABLE output column is itself named job_id, the exact recurring
  -- ambiguous-bare-column class this repository's own prior HRT checkpoints
  -- (274/275/276/277) each independently hit at least once.
  update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
  where j.job_id = v_job.job_id and j.status = 'pending';

  foreach v_employee_id in array p_employee_ids loop
    if not exists (select 1 from app.employees where master_record_id = v_employee_id and tenant_id = p_tenant_id and lifecycle_status = 'active') then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_day := p_from_date;
    while v_day <= p_to_date loop
      v_offset := ((v_day - p_from_date) % v_cycle.cycle_length_days);
      select * into v_slot from app.roster_cycle_slots where roster_cycle_id = p_roster_cycle_id and day_offset = v_offset;

      if v_slot.shift_template_id is not null then
        select status into v_existing_status from app.schedule_assignments
        where tenant_id = p_tenant_id and employee_id = v_employee_id and work_date = v_day and status in ('scheduled', 'published');

        if v_existing_status = 'published' then
          v_skipped := v_skipped + 1;
        else
          declare
            v_version_id uuid;
          begin
            select id into v_version_id from app.shift_template_versions
            where shift_template_id = v_slot.shift_template_id and status = 'published'
            order by effective_from desc limit 1;

            if v_version_id is null then
              v_skipped := v_skipped + 1;
            else
              begin
                v_result := app.assign_employee_schedule(p_tenant_id, v_employee_id, v_version_id, v_day, 'bulk_generated', null, p_actor_auth_user_id, p_actor_label);
                update app.schedule_assignments set roster_cycle_id = p_roster_cycle_id where id = v_result.id;
                if v_existing_status is not null then
                  v_superseded := v_superseded + 1;
                else
                  v_created := v_created + 1;
                end if;
              exception
                -- A per-day race (e.g. a concurrent HR action published or
                -- cancelled this exact day between this loop's own unlocked
                -- peek and app.assign_employee_schedule's own authoritative
                -- lock/check) skips ONLY this one day, never aborts the
                -- whole batch or loses the app.jobs tracking row already
                -- created above -- mirrors app.commit_attendance_device_
                -- import_job's (HRT-278) identical per-row skip-and-continue
                -- shape.
                when insufficient_privilege or check_violation or no_data_found or unique_violation then
                  v_skipped := v_skipped + 1;
              end;
            end if;
          end;
        end if;
      end if;

      v_existing_status := null;

      v_day := v_day + 1;
    end loop;
  end loop;

  perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'generate_roster_schedule_assignments',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('roster_cycle_id', p_roster_cycle_id, 'created_count', v_created, 'superseded_count', v_superseded, 'skipped_count', v_skipped)
  );

  created_count := v_created; superseded_count := v_superseded; skipped_count := v_skipped; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.generate_roster_schedule_assignments is
  'HRT-279 (decision 8): bounded (<=92 days) batch generation from a PUBLISHED roster cycle''s own day-offset pattern. Self-claims the SPECIFIC app.jobs row it just created (by job_id, under its own row lock) rather than the generic queue-wide app.claim_next_job -- calls the SAME app.enqueue_job/app.complete_job any future live poller would call, a real, non-bypassing use of the PLT-132 lifecycle. Skips (never overwrites) a day already covered by a PUBLISHED assignment, since superseding one requires HRS:Override -- this function runs at the HRS:Edit bar (bulk DRAFT generation).';

-- ===========================================================================
-- 16. Swap propose/decide/cancel RPCs (decisions 6/7).
-- ===========================================================================

create function app.request_schedule_swap(
  p_assignment_id uuid, p_target_employee_id uuid, p_target_assignment_id uuid, p_reason text, p_idempotency_key text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.schedule_swap_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assignment app.schedule_assignments;
  v_target_assignment app.schedule_assignments;
  v_self app.employees;
  v_is_self boolean;
  v_existing app.schedule_swap_requests;
  v_request app.schedule_swap_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- C-05: the not-found tenant fold runs first, then the identity/authority
  -- check, BEFORE any row-state (status/target-validity) is disclosed to the
  -- caller -- a fully authorized-and-scoped caller learns v_assignment.status
  -- etc. only after proving they are entitled to act on this row at all.
  select * into v_assignment from app.schedule_assignments where id = p_assignment_id;
  if not found or not app.has_active_tenant_membership(v_assignment.tenant_id, p_actor_auth_user_id) then
    raise exception 'schedule_assignment_not_found: %', p_assignment_id using errcode = 'no_data_found';
  end if;

  select * into v_target_assignment from app.schedule_assignments where id = p_target_assignment_id;
  if not found or v_target_assignment.tenant_id <> v_assignment.tenant_id or v_target_assignment.employee_id <> p_target_employee_id then
    raise exception 'schedule_assignment_not_found: %', p_target_assignment_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_assignment.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_assignment.employee_id;

  if not v_is_self then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assignment.tenant_id, 'HRS', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assignment.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- Only now, past the authority gate, are status/target-validity details
  -- (which reveal something about the row beyond bare existence) evaluated.
  if v_assignment.status <> 'published' then
    raise exception 'invalid_transition: schedule assignment % is %, only a published assignment may be swapped', p_assignment_id, v_assignment.status
      using errcode = 'check_violation';
  end if;
  if v_target_assignment.status <> 'published' then
    raise exception 'invalid_transition: schedule assignment % is %, only a published assignment may be swapped', p_target_assignment_id, v_target_assignment.status
      using errcode = 'check_violation';
  end if;
  if v_assignment.employee_id = p_target_employee_id then
    raise exception 'invalid_swap_target: an employee may not swap a shift with themself' using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request a swap' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.schedule_swap_requests where tenant_id = v_assignment.tenant_id and requesting_employee_id = v_assignment.employee_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.assignment_id = p_assignment_id and v_existing.target_employee_id = p_target_employee_id and v_existing.target_assignment_id = p_target_assignment_id then
        return v_existing;
      else
        raise exception 'idempotency_key_conflict: key % was already used for a different swap request', p_idempotency_key using errcode = 'unique_violation';
      end if;
    end if;
  end if;

  insert into app.schedule_swap_requests (
    tenant_id, requesting_employee_id, requested_by_auth_user_id, assignment_id, target_employee_id, target_assignment_id, reason, idempotency_key
  ) values (
    v_assignment.tenant_id, v_assignment.employee_id, p_actor_auth_user_id, p_assignment_id, p_target_employee_id, p_target_assignment_id, p_reason, p_idempotency_key
  ) returning * into v_request;

  perform app.capture_audit_event(
    v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_schedule_swap',
    'app.schedule_swap_requests', v_request.id, 'success', null, null,
    jsonb_build_object('assignment_id', p_assignment_id, 'target_assignment_id', p_target_assignment_id)
  );

  return v_request;
end;
$$;

create function app.decide_schedule_swap_request(
  p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
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

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_schedule_swap_request',
    'app.schedule_swap_requests', p_request_id, 'success', p_decided_reason, null, jsonb_build_object('decision', p_decision)
  );

  return v_request;
end;
$$;

create function app.cancel_schedule_swap_request(
  p_request_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
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

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_schedule_swap_request',
    'app.schedule_swap_requests', p_request_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_request;
end;
$$;

-- ===========================================================================
-- 17. Read RPCs.
-- ===========================================================================

create function app.get_my_schedule(p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date)
returns table (
  assignment_id uuid, work_date date, shift_template_id uuid, shift_template_name text, shift_type text,
  crosses_midnight boolean, status text
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
  select sa.id, sa.work_date, st.id, st.name, sv.shift_type, sv.crosses_midnight, sa.status
  from app.schedule_assignments sa
  join app.shift_template_versions sv on sv.id = sa.shift_template_version_id
  join app.shift_templates st on st.id = sv.shift_template_id
  where sa.tenant_id = p_tenant_id and sa.employee_id = v_self.master_record_id and sa.status = 'published'
    and (p_from_date is null or sa.work_date >= p_from_date) and (p_to_date is null or sa.work_date <= p_to_date)
  order by sa.work_date;
end;
$$;

create function app.list_schedule_assignments(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date, p_employee_id uuid, p_status text,
  p_limit integer, p_after_id uuid
)
returns table (
  id uuid, employee_id uuid, employee_number text, employee_full_name text, work_date date, shift_template_name text,
  status text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_has_view boolean;
  v_after app.schedule_assignments;
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
    select * into v_after from app.schedule_assignments sa0 where sa0.id = p_after_id;
  end if;

  return query
  select sa.id, sa.employee_id, m.code, e.full_name, sa.work_date, st.name, sa.status, sa.record_version
  from app.schedule_assignments sa
  join app.employees e on e.master_record_id = sa.employee_id
  join app.master_records m on m.id = e.master_record_id
  join app.shift_template_versions sv on sv.id = sa.shift_template_version_id
  join app.shift_templates st on st.id = sv.shift_template_id
  where sa.tenant_id = p_tenant_id
    and (p_from_date is null or sa.work_date >= p_from_date)
    and (p_to_date is null or sa.work_date <= p_to_date)
    and (p_status is null or sa.status = p_status)
    and (
      (p_employee_id is not null and sa.employee_id = p_employee_id)
      or (p_employee_id is null and v_has_view)
      or (p_employee_id is null and not v_has_view and (sa.employee_id = v_self.master_record_id or e.manager_employee_id = v_self.master_record_id))
    )
    and (v_after.id is null or (sa.work_date, sa.id) < (v_after.work_date, v_after.id))
  order by sa.work_date desc, sa.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_schedule_assignments is
  'HRT-279 (section 26): HRS:View holders see the full tenant-scoped list; anyone else transparently gets self + direct-reports scope only, mirroring app.list_attendance_sessions (HRT-278) exactly.';

create function app.get_schedule_assignment_detail(p_assignment_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, employee_id uuid, work_date date, shift_template_version_id uuid, shift_template_name text, status text,
  source text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_assignment app.schedule_assignments;
  v_self app.employees;
  v_has_view boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_assignment from app.schedule_assignments sa0 where sa0.id = p_assignment_id;
  if not found or not app.has_active_tenant_membership(v_assignment.tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_self := app.get_self_employee(v_assignment.tenant_id, p_actor_auth_user_id);
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, v_assignment.tenant_id, 'HRS', 'View')).allowed;

  if not (
    v_has_view
    or (v_self.master_record_id is not null and v_self.master_record_id = v_assignment.employee_id)
    or exists (select 1 from app.employees e where e.master_record_id = v_assignment.employee_id and e.manager_employee_id = v_self.master_record_id)
  ) then
    return;
  end if;

  return query
  select sa.id, sa.employee_id, sa.work_date, sa.shift_template_version_id, st.name, sa.status, sa.source, sa.record_version
  from app.schedule_assignments sa
  join app.shift_template_versions sv on sv.id = sa.shift_template_version_id
  join app.shift_templates st on st.id = sv.shift_template_id
  where sa.id = p_assignment_id;
end;
$$;

create function app.list_shift_templates(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, org_unit_id uuid, code text, name text, status text, published_version_id uuid, published_version_number integer, record_version integer)
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
  select st.id, st.org_unit_id, st.code, st.name, st.status, sv.id, sv.version_number, st.record_version
  from app.shift_templates st
  left join lateral (
    select v.id, v.version_number from app.shift_template_versions v
    where v.shift_template_id = st.id and v.status = 'published'
    order by v.effective_from desc limit 1
  ) sv on true
  where st.tenant_id = p_tenant_id
  order by st.name;
end;
$$;

create function app.get_shift_template_version_detail(p_version_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, shift_template_id uuid, version_number integer, status text, effective_from date, timezone text,
  day_boundary_local_time time, shift_type text, grace_late_minutes integer, grace_early_minutes integer,
  crosses_midnight boolean, total_work_minutes integer, total_break_minutes integer, record_version integer, segments jsonb
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.shift_template_versions;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_version from app.shift_template_versions stv0 where stv0.id = p_version_id;
  if not found then
    return;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    return;
  end if;

  return query
  select
    v_version.id, v_version.shift_template_id, v_version.version_number, v_version.status, v_version.effective_from, v_version.timezone,
    v_version.day_boundary_local_time, v_version.shift_type, v_version.grace_late_minutes, v_version.grace_early_minutes,
    v_version.crosses_midnight, v_version.total_work_minutes, v_version.total_break_minutes, v_version.record_version,
    (select coalesce(jsonb_agg(jsonb_build_object(
       'sequence_number', s.sequence_number, 'segment_type', s.segment_type, 'start_time', s.start_time,
       'end_time', s.end_time, 'crosses_midnight', s.crosses_midnight, 'duration_minutes', s.duration_minutes
     ) order by s.sequence_number), '[]'::jsonb)
     from app.shift_segments s where s.shift_template_version_id = v_version.id);
end;
$$;

create function app.list_roster_cycles(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, org_unit_id uuid, name text, cycle_length_days integer, status text, slot_count integer, record_version integer)
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
  select rc.id, rc.org_unit_id, rc.name, rc.cycle_length_days, rc.status,
         (select count(*)::integer from app.roster_cycle_slots s where s.roster_cycle_id = rc.id), rc.record_version
  from app.roster_cycles rc
  where rc.tenant_id = p_tenant_id
  order by rc.name;
end;
$$;

create function app.get_roster_cycle_detail(p_roster_cycle_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, org_unit_id uuid, name text, cycle_length_days integer, status text, record_version integer, slots jsonb
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cycle app.roster_cycles;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_cycle from app.roster_cycles rc0 where rc0.id = p_roster_cycle_id;
  if not found then
    return;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cycle.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    return;
  end if;

  return query
  select
    v_cycle.id, v_cycle.org_unit_id, v_cycle.name, v_cycle.cycle_length_days, v_cycle.status, v_cycle.record_version,
    (select coalesce(jsonb_agg(jsonb_build_object('day_offset', s.day_offset, 'shift_template_id', s.shift_template_id) order by s.day_offset), '[]'::jsonb)
     from app.roster_cycle_slots s where s.roster_cycle_id = v_cycle.id);
end;
$$;

create function app.list_roster_holidays(p_tenant_id uuid, p_actor_auth_user_id uuid, p_org_unit_id uuid)
returns table (id uuid, org_unit_id uuid, holiday_date date, name text, is_working_day boolean, record_version integer)
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
  select h.id, h.org_unit_id, h.holiday_date, h.name, h.is_working_day, h.record_version
  from app.roster_holidays h
  where h.tenant_id = p_tenant_id and h.status = 'active'
    and (p_org_unit_id is null or h.org_unit_id = p_org_unit_id or h.org_unit_id is null)
  order by h.holiday_date;
end;
$$;

create function app.list_schedule_coverage_requirements(p_tenant_id uuid, p_actor_auth_user_id uuid, p_org_unit_id uuid)
returns table (id uuid, org_unit_id uuid, shift_template_id uuid, shift_template_name text, day_of_week integer, min_headcount integer, record_version integer)
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
  select r.id, r.org_unit_id, r.shift_template_id, st.name, r.day_of_week, r.min_headcount, r.record_version
  from app.roster_coverage_requirements r
  join app.shift_templates st on st.id = r.shift_template_id
  where r.tenant_id = p_tenant_id and r.status = 'active'
    and (p_org_unit_id is null or r.org_unit_id = p_org_unit_id)
  order by r.day_of_week, st.name;
end;
$$;

create function app.get_schedule_coverage_preview(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_org_unit_id uuid, p_from_date date, p_to_date date
)
returns table (
  work_date date, shift_template_id uuid, shift_template_name text, scheduled_count integer, min_headcount integer, coverage_status text
)
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

  if p_from_date is null or p_to_date is null or p_to_date < p_from_date or (p_to_date - p_from_date) > 92 then
    raise exception 'invalid_date_range: date range must be non-empty and at most 92 days' using errcode = 'check_violation';
  end if;

  -- decision 12: aggregate headcount only, never employee-level identity --
  -- the "Operations... workforce availability projection" surface.
  return query
  with days as (select generate_series(p_from_date, p_to_date, interval '1 day')::date as d),
  scheduled as (
    select sa.work_date, st.id as shift_template_id, count(*)::integer as scheduled_count
    from app.schedule_assignments sa
    join app.employees e on e.master_record_id = sa.employee_id
    join app.shift_template_versions sv on sv.id = sa.shift_template_version_id
    join app.shift_templates st on st.id = sv.shift_template_id
    where sa.tenant_id = p_tenant_id and sa.status = 'published' and sa.work_date between p_from_date and p_to_date
      and (p_org_unit_id is null or e.branch_org_unit_id = p_org_unit_id or e.department_org_unit_id = p_org_unit_id)
    group by sa.work_date, st.id
  )
  select r.d, req.shift_template_id, st.name, coalesce(sch.scheduled_count, 0), req.min_headcount,
         case when coalesce(sch.scheduled_count, 0) >= req.min_headcount then 'met' else 'below_minimum' end
  from days r
  join app.roster_coverage_requirements req on req.tenant_id = p_tenant_id and req.status = 'active'
    and req.day_of_week = extract(dow from r.d)::integer
    and (p_org_unit_id is null or req.org_unit_id = p_org_unit_id)
  join app.shift_templates st on st.id = req.shift_template_id
  left join scheduled sch on sch.work_date = r.d and sch.shift_template_id = req.shift_template_id
  order by r.d, st.name;
end;
$$;

create function app.list_schedule_swap_requests(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text, p_limit integer, p_after_id uuid)
returns table (
  id uuid, requesting_employee_id uuid, requesting_employee_number text, target_employee_id uuid, target_employee_number text,
  assignment_id uuid, target_assignment_id uuid, status text, created_at timestamptz, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_after app.schedule_swap_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    return;
  end if;

  if p_after_id is not null then
    select * into v_after from app.schedule_swap_requests sr0 where sr0.id = p_after_id;
  end if;

  return query
  select sr.id, sr.requesting_employee_id, rm.code, sr.target_employee_id, tm.code, sr.assignment_id, sr.target_assignment_id,
         sr.status, sr.created_at, sr.record_version
  from app.schedule_swap_requests sr
  join app.employees re on re.master_record_id = sr.requesting_employee_id
  join app.master_records rm on rm.id = re.master_record_id
  join app.employees te on te.master_record_id = sr.target_employee_id
  join app.master_records tm on tm.id = te.master_record_id
  where sr.tenant_id = p_tenant_id
    and (p_status is null or sr.status = p_status)
    and (v_after.id is null or (sr.created_at, sr.id) < (v_after.created_at, v_after.id))
  order by sr.created_at desc, sr.id desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create function app.list_my_schedule_swap_requests(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, role text, assignment_id uuid, target_assignment_id uuid, status text, created_at timestamptz, record_version integer)
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
  select sr.id, case when sr.requesting_employee_id = v_self.master_record_id then 'requester' else 'target' end,
         sr.assignment_id, sr.target_assignment_id, sr.status, sr.created_at, sr.record_version
  from app.schedule_swap_requests sr
  where sr.tenant_id = p_tenant_id and (sr.requesting_employee_id = v_self.master_record_id or sr.target_employee_id = v_self.master_record_id)
  order by sr.created_at desc
  limit 100;
end;
$$;

create function app.export_schedule_assignments(p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date)
returns table (employee_number text, employee_full_name text, work_date date, shift_template_name text, status text)
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
    p_tenant_id, p_actor_auth_user_id, p_actor_auth_user_id::text, 'export_schedule_assignments',
    'app.schedule_assignments', null, 'success', null, null, jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date)
  );

  return query
  select m.code, e.full_name, sa.work_date, st.name, sa.status
  from app.schedule_assignments sa
  join app.employees e on e.master_record_id = sa.employee_id
  join app.master_records m on m.id = e.master_record_id
  join app.shift_template_versions sv on sv.id = sa.shift_template_version_id
  join app.shift_templates st on st.id = sv.shift_template_id
  where sa.tenant_id = p_tenant_id and sa.work_date between p_from_date and p_to_date
  order by sa.work_date, m.code;
end;
$$;

-- ===========================================================================
-- 18. RLS -- hardened default-deny select policy on every new table (writes
--     exclusively through the SECURITY DEFINER functions above).
-- ===========================================================================

alter table app.shift_templates enable row level security;
alter table app.shift_template_versions enable row level security;
alter table app.shift_segments enable row level security;
alter table app.roster_holidays enable row level security;
alter table app.roster_cycles enable row level security;
alter table app.roster_cycle_slots enable row level security;
alter table app.schedule_assignments enable row level security;
alter table app.roster_coverage_requirements enable row level security;
alter table app.schedule_swap_requests enable row level security;

create policy shift_templates_select_scoped on app.shift_templates
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy shift_template_versions_select_scoped on app.shift_template_versions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy shift_segments_select_scoped on app.shift_segments
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy roster_holidays_select_scoped on app.roster_holidays
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy roster_cycles_select_scoped on app.roster_cycles
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy roster_cycle_slots_select_scoped on app.roster_cycle_slots
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy schedule_assignments_select_scoped on app.schedule_assignments
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy roster_coverage_requirements_select_scoped on app.roster_coverage_requirements
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy schedule_swap_requests_select_scoped on app.schedule_swap_requests
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 19. Grants -- column-restricted from the first migration (decision 11),
--     never a blanket `grant select on <table> to authenticated`.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.shift_templates to authenticated;
grant select on app.shift_templates to service_role;

grant select on app.shift_template_versions to authenticated;
grant select on app.shift_template_versions to service_role;

grant select on app.shift_segments to authenticated;
grant select on app.shift_segments to service_role;

grant select on app.roster_holidays to authenticated;
grant select on app.roster_holidays to service_role;

grant select on app.roster_cycles to authenticated;
grant select on app.roster_cycles to service_role;

grant select on app.roster_cycle_slots to authenticated;
grant select on app.roster_cycle_slots to service_role;

grant select (
  id, tenant_id, employee_id, shift_template_version_id, work_date, status, source, roster_cycle_id, previous_assignment_id,
  published_at, published_by, idempotency_key, record_version, created_by, created_at, updated_at
) on app.schedule_assignments to authenticated;
grant select on app.schedule_assignments to service_role;

grant select on app.roster_coverage_requirements to authenticated;
grant select on app.roster_coverage_requirements to service_role;

grant select (
  id, tenant_id, requesting_employee_id, requested_by_auth_user_id, assignment_id, target_employee_id, target_assignment_id,
  status, decided_by, decided_at, idempotency_key, record_version, created_by, created_at, updated_at
) on app.schedule_swap_requests to authenticated;
grant select on app.schedule_swap_requests to service_role;

grant execute on function app.create_shift_template(uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_shift_template_version(uuid, text, time, text, integer, integer, date, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.publish_shift_template_version(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.create_roster_cycle(uuid, uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.set_roster_cycle_slot(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.publish_roster_cycle(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.set_roster_holiday(uuid, uuid, date, text, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.remove_roster_holiday(uuid, uuid, text) to authenticated, service_role;

grant execute on function app.set_schedule_coverage_requirement(uuid, uuid, uuid, integer, integer, uuid, text) to authenticated, service_role;

grant execute on function app.assign_employee_schedule(uuid, uuid, uuid, date, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_schedule_assignment(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.publish_schedule_assignments(uuid, date, date, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.generate_roster_schedule_assignments(uuid, uuid, uuid[], date, date, uuid, text) to authenticated, service_role;

grant execute on function app.request_schedule_swap(uuid, uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_schedule_swap_request(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_schedule_swap_request(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.get_my_schedule(uuid, uuid, date, date) to authenticated, service_role;
grant execute on function app.list_schedule_assignments(uuid, uuid, date, date, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.get_schedule_assignment_detail(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_shift_templates(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_shift_template_version_detail(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_roster_cycles(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_roster_cycle_detail(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_roster_holidays(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_schedule_coverage_requirements(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_schedule_coverage_preview(uuid, uuid, uuid, date, date) to authenticated, service_role;
grant execute on function app.list_schedule_swap_requests(uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.list_my_schedule_swap_requests(uuid, uuid) to authenticated, service_role;
grant execute on function app.export_schedule_assignments(uuid, uuid, date, date) to authenticated, service_role;

-- app.generic_job_types()/app.enqueue_job/app.dispatch_event_as_job are all
-- unchanged by this migration beyond the CREATE OR REPLACE above (which
-- preserves the existing ACL on app.generic_job_types() -- C-11's own
-- established "CREATE OR REPLACE preserves an existing ACL" rule, verified
-- against this exact function's own already-applied grant in
-- 20260730410000) -- no grant statement is needed or added here.
