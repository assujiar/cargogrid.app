-- HRT-ISS-065-CLOSURE -- dedicated follow-up task closing ISS-2026-065 (Employee
-- Master, HRT-274): "no effective-dated employee identity/lifecycle mechanism,
-- despite a binding, repeated Prompt 274 requirement" -- the SOLE remaining
-- blocker Prompt 297's own closure report (CG-S12-HRT-025,
-- docs/build-log/phase-07/HRIS_TICKETING_CLOSURE_REPORT.md §19/§20/§22) named for
-- PHASE_7_VERIFIED, independently re-confirmed OPEN by four separate verification
-- passes (the checkpoint author plus a six-lens synthesis pass). Explicit operator
-- authorization to build this as bounded new capability work (not a verification
-- checkpoint) is recorded in this task's own build log,
-- docs/build-log/phase-07/HRT-ISS-065-CLOSURE.md.
--
-- Binding source requirement (docs/ai-agent-build-prompt-package/12-phase-07-hris-
-- ticketing/274_EMPLOYEE_MASTER_PROMPT.md): §5 "one effective-dated workforce
-- truth"; §13 "effective dates ... and lifecycle history"; §17 index "... effective
-- period"; §18 audit records "... effective version"; §20 "Define effective-dated
-- employee identity, lifecycle, duplicate and correction invariants"; §22
-- "transfer company/branch/department/position, suspend or archive with preserved
-- history".
--
-- Structural template: app.employee_position_assignments (HRT-275,
-- 20260730840000_create_hris_organization_position_linkage.sql), the analogous,
-- already-VERIFIED effective-dated mechanism this checkpoint builds for the
-- EMPLOYEE's own record specifically (lifecycle_status, org/position/manager,
-- employment_type, hire_date/probation_end_date/employment_end_date) -- HRT-275's
-- own migration explicitly disclosed it does NOT close this gap (KNOWN_ISSUES.md
-- ISS-2026-065's own 2026-08-09 update paragraph).
--
-- ===========================================================================
-- Design decisions (this repository's own established documentation convention)
-- ===========================================================================
--
-- 1. **New table: app.employee_lifecycle_versions** (not
--    "...profile_versions" -- "lifecycle" matches this domain's own existing
--    vocabulary, app.employee_lifecycle_events, and distinguishes it from a
--    field-by-field profile-correction log, which app.employee_change_requests
--    already owns). A full point-in-time SNAPSHOT per version (every field the
--    spec names: lifecycle_status, company/branch/department_org_unit_id,
--    position_title, manager_employee_id, employment_type, hire_date,
--    probation_end_date, employment_end_date) -- not a delta -- mirroring
--    app.employee_position_assignments' own full-row-per-version shape exactly,
--    for the same reason: a delta model would require walking the whole chain to
--    answer "what was true on date X", defeating the point of an "as of" read.
--    effective_start_date/effective_end_date/a generated validity_range daterange,
--    change_reason, previous_version_id chain, decided_by/decided_at/
--    decided_reason, record_version, created_by/created_at -- every column the
--    task's own template names, present here in the same shape.
--
-- 2. **status enum: scheduled / active / superseded** (adapted from the task's
--    own suggested scheduled/active/superseded/cancelled -- 'cancelled' folded
--    into 'superseded', reasoned below). Deliberately did NOT reuse
--    app.employee_position_assignments' own pending_approval/active/rejected/
--    cancelled shape verbatim, because that shape encodes a PROPOSE-THEN-DECIDE
--    workflow this domain does not have (every one of the 7 RPCs below is a
--    direct, immediately-authoritative transition performed by an actor who
--    already holds sufficient authority -- there is no separate approval step to
--    model). Instead:
--      - 'scheduled' = written, but NOT YET applied to app.employees' own
--        current-state columns (a future p_effective_date). Durable until an
--        explicit later write changes it -- never flips merely because time
--        passed, avoiding the exact "status column that silently drifts stale
--        without a live scheduler" anti-pattern app.employee_position_
--        assignments' own header explicitly disclosed avoiding for its 'active'
--        status. Only app.activate_due_employee_lifecycle_transitions (an
--        explicit write) or a later superseding write ever changes it.
--      - 'active' = has been (immediately) or was (once due) applied to
--        app.employees -- covers past (closed via effective_end_date), current,
--        and even a chronologically-later-but-already-materialized row alike,
--        mirroring app.employee_position_assignments' own "status=active covers
--        past/current/future rows, validity_range @> current_date answers 'in
--        effect right now' at READ time, never the status column" philosophy
--        exactly -- a closed-but-still-'active' predecessor is correct, expected
--        history, never rewritten just because a successor later activated (see
--        decision 7).
--      - 'superseded' = voided by a LATER correction/reschedule before its own
--        content was ever authoritative going forward -- the one genuinely new
--        state this domain needs beyond the position-assignment precedent,
--        because a backdated correction can retroactively invalidate a row whose
--        entire remaining range is displaced (a truncation-to-empty-range is not
--        representable by any valid effective_start_date <= effective_end_date
--        pair -- decision 4). Applies uniformly whether the voided row had
--        already materialized (a genuine, once-true historical fact being
--        corrected away) or never got the chance to (a scheduled row cancelled
--        before its own date arrived) -- the task's own separate 'cancelled'
--        value is intentionally not a distinct state: both cases mean exactly
--        "no longer part of the authoritative timeline", the one fact every
--        consumer (the no-overlap constraint, the as-of read, the sweep) needs.
--    A `materialized_at timestamptz` column (independent of `status`) records
--    precisely when a version's fields were actually pushed onto app.employees --
--    defense-in-depth precision beyond the status label alone, and the exact
--    signal the sweep's own due-query keys off.
--
-- 3. **Supersede-before-insert, applied to every write (immediate, future, and
--    backdated alike)** -- HRT-279's own self-found "supersede then insert"
--    ordering defect is the direct precedent this decision deliberately avoids
--    repeating: app.record_employee_lifecycle_version (the one shared helper
--    every one of the 7 RPCs below calls) FIRST locks (`for update`) every
--    currently-live (status in scheduled/active) version row for this employee
--    whose range could be touched by the incoming p_effective_date, THEN
--    resolves each into exactly one of two outcomes, THEN inserts the new row:
--      (a) a stale row whose OWN effective_start_date >= the incoming
--          p_effective_date is entirely displaced -- flipped straight to
--          'superseded', its own effective_start_date/effective_end_date left
--          UNTOUCHED (a genuine, disclosed audit trail of "what this record used
--          to assert before the correction", never silently rewritten).
--      (b) a stale row that STRADDLES the incoming p_effective_date (its own
--          effective_start_date is earlier) is truncated -- effective_end_date
--          set to p_effective_date - 1 -- and otherwise left exactly as it was
--          (status unchanged); it remains a genuinely correct historical fact for
--          the sub-range it still covers, never rewritten just because a
--          successor now exists (matches app.employee_position_assignments' own
--          "closed-but-still-active" precedent, decision 2 above).
--    Only after every touched row is resolved does the new row get inserted --
--    the SAME ordering discipline app.decide_employee_position_assignment's own
--    predecessor-close-before-flip-to-active sequence already established for
--    this exact class of defect (an EXCLUDE constraint violation from a
--    still-overlapping predecessor), extended here to cover retroactive
--    correction, not merely ordinary chronological succession.
--
--    Concretely, for a genuinely backdated correction (p_effective_date <
--    current_date): every version row recorded between the correction point and
--    "now" necessarily has effective_start_date >= p_effective_date (nothing
--    real can have started before a date that is itself in the past relative to
--    today), so ALL of them fall into bucket (a) above and are superseded --
--    including any currently-'scheduled' future transition, which is
--    deliberately, conservatively voided rather than silently left pointing at a
--    now-rewritten past (disclosed limitation: HR must explicitly re-review and
--    re-schedule any future-dated transition after performing a backdated
--    correction for the same employee -- this repository does not attempt to
--    infer whether it is "still valid").
--
-- 4. **Authority for a backdated correction**: gated at least as strictly as this
--    domain's own most sensitive existing lifecycle action, per this task's own
--    instruction -- HRS:Override, matching app.terminate_employee/app.
--    suspend_employee's own bar. app.suspend_employee, app.terminate_employee,
--    and app.reactivate_employee are ALREADY gated at HRS:Override
--    unconditionally (every call, immediate or backdated) -- for those three,
--    backdating widens nothing further. app.create_employee_draft (HRS:Create),
--    app.update_employee_draft (HRS:Edit), app.transfer_employee (HRS:Edit), and
--    app.archive_employee_profile (HRS:Edit) each gain an EXPLICIT, additional
--    HRS:Override check, reached ONLY on the backdated branch -- never widening
--    what their normal (today, future) callers can already do (Tier B class
--    C-08, self-checked in the build log). Every backdated call additionally
--    requires a non-empty reason: reused from the RPC's own existing p_reason
--    parameter where one already exists and is already mandatory
--    (suspend/terminate) or already optional (transfer/archive, now made
--    conditionally mandatory only on the backdated branch); a NEW p_backdate_
--    reason parameter for the three RPCs with no reason parameter at all today
--    (create_employee_draft, update_employee_draft, reactivate_employee).
--
-- 5. **app.create_employee_draft / app.update_employee_draft: accept and record
--    p_effective_date, but ALWAYS materialize immediately** -- a deliberate,
--    narrower carve-out from the other 5 RPCs' true future-scheduling, reasoned
--    explicitly rather than left as an unexplained asymmetry. A draft's row
--    genuinely, unavoidably exists (and is immediately editable by HR) the moment
--    app.create_employee_draft returns -- there is no meaningful "the row does
--    not yet exist" state to defer, only "the row exists with lifecycle_status=
--    'draft'", which is already true by construction regardless of
--    p_effective_date. Worse, letting either RPC's version row sit 'scheduled'
--    (deferred to the sweep) would be actively unsafe: nothing stops HR from
--    submitting/approving/activating the SAME draft (via app.submit_employee_
--    for_approval / app.decide_employee_approval / app.activate_employee -- all
--    three genuinely OUT of this task's own bounded scope, per its own "stay
--    scoped to exactly this requirement" instruction, and left completely
--    unmodified) before the scheduled create/update version's own effective_date
--    arrives -- a later, unrelated sweep run would then blindly overwrite
--    whatever lifecycle_status/fields those unmodified RPCs had since committed.
--    Both RPCs therefore always write status='active'/materialized_at=now()
--    regardless of p_effective_date's relation to current_date; p_effective_date
--    is still stored on the version row's own effective_start_date (useful for
--    historical-truth/data-migration parity and for app.get_employee_lifecycle_
--    as_of correctly returning zero rows for a date before a genuinely
--    future-dated hire), and backdating either still requires the same HRS:
--    Override + mandatory-reason gate as the other 5. This is intentionally
--    scoped narrower than a literal reading of the task's "every RPC gets true
--    scheduling" framing -- disclosed here, not silently done, because widening
--    it later is additive (loosening a stricter default), never a breaking
--    change for any caller relying on today's always-immediate behavior.
--
-- 6. **app.get_employee_lifecycle_as_of(p_master_record_id, p_actor_auth_user_id,
--    p_as_of)** mirrors app.get_employee_current_assignment's own shape exactly:
--    reads app.employee_lifecycle_versions' own validity_range directly (never
--    app.employees' current-state columns, which only ever reflect "now"),
--    filtered to status in ('scheduled','active') (never 'superseded') and
--    validity_range @> p_as_of -- the EXCLUDE constraint below guarantees at most
--    one such row per employee per date, so this is always a clean 0-or-1-row
--    answer, genuinely correct for a past, present, or future p_as_of regardless
--    of whether app.activate_due_employee_lifecycle_transitions has ever run.
--    Distinct from the PRE-EXISTING app.get_employee_lifecycle_history (an
--    append-only event log a caller must linearly scan and manually interpret --
--    exactly the "cannot answer 'what was the status as of date X' without a
--    linear scan" gap ISS-2026-065's own CONFIRMED-STILL-OPEN entry named) --
--    that function is left completely unmodified; this is a genuinely new,
--    additional read, not a replacement. decided_reason is masked (returned null)
--    unless the caller is the linked employee themself or holds HRS:View
--    personal data, mirroring app.get_employee_profile's own v_unmasked pattern
--    exactly (decided_reason carries the same free-text HR-narrative shape
--    HRT-293 Finding A already classified `restricted` for every sibling reason
--    column on this domain -- scripts/data-classification/registry.ts's
--    HRS_REGISTRY gains one new entry below, never editing the existing
--    hrs:employees.lifecycle_reason_narrative entry).
--
-- 7. **app.activate_due_employee_lifecycle_transitions(p_tenant_id,
--    p_actor_auth_user_id, p_actor_label)** mirrors app.activate_due_employee_
--    position_assignments exactly: HRS:Override-gated, idempotent (a defensive
--    re-check of each candidate row's own status/effective_start_date under lock,
--    immediately after acquiring it, catches a row already resolved by a
--    concurrent call or an earlier iteration of the SAME sweep), and NOT wired to
--    any live scheduler -- no pg_cron or equivalent exists anywhere in this
--    repository (ISS-2026-015's own standing, disclosed, repository-wide gap;
--    the identical, already-accepted pattern ISS-2026-066 item 2 already
--    disclosed for app.activate_due_employee_position_assignments). Disclosed as
--    NOT_RUN in the build log rather than faking a cron trigger. Re-validates
--    manager-cycle-freedom (app.assert_no_employee_manager_cycle) immediately
--    before writing manager_employee_id at the actual commit point -- the SAME
--    defect class, and the SAME fix shape, app.sync_employee_current_assignment_
--    cache's own "CRITICAL review-round fix" comment (HRT-275) already
--    documents for the identical hazard (two independently-scheduled,
--    mutually-referencing manager changes must never BOTH activate into a live
--    cycle) -- adopted here proactively rather than waiting to re-discover it.
--    A row whose activation would violate that check, or whose org-unit
--    reference has since gone invalid/inactive (app.enforce_employee_org_unit_
--    shape, a trigger on app.employees itself, fires on the sweep's own UPDATE
--    exactly as it does on any other UPDATE), is skipped -- not silently, not by
--    aborting the whole batch -- disclosed via a dedicated failure-result audit
--    event, matching app.activate_due_employee_position_assignments' own
--    skipped_count/skipped_ids shape. C-21 (lock order): every write RPC below
--    locks app.employees FIRST, then (inside app.record_employee_lifecycle_
--    version) app.employee_lifecycle_versions rows SECOND; the sweep's own loop
--    locks in the SAME order (app.employees for the candidate's master_record_id
--    first, the specific version row second) -- stated explicitly here per the
--    taxonomy's own C-21 checklist item, not merely true by accident.
--    Deliberately does NOT re-validate full org-unit shape (existence/type/
--    active-status/ancestor-chain) for a scheduled TRANSFER at SCHEDULING time --
--    only at activation time, via the same trigger every other app.employees
--    UPDATE already goes through -- a disclosed, narrower-than-ideal choice
--    (early UX feedback at schedule-time would be better) accepted to keep this
--    checkpoint bounded; the activation-time check is authoritative and
--    correctly never lets an invalid org-unit combination reach app.employees.
--
-- 8. **Composition with HRT-295's identity coupling (already VERIFIED, task item
--    5) -- the single most safety-critical decision in this migration.**
--    app.suspend_employee/app.terminate_employee/app.reactivate_employee's own
--    IMMEDIATE-path statements (the `update app.employees ...` / `perform app.
--    transition_user_status(...)` pair) are left BYTE-IDENTICAL to their
--    HRT-295 (20260731230000) shape -- copied verbatim into this migration's own
--    "not future" branch, minimizing the risk of an accidental behavioral
--    regression to that already-VERIFIED security fix. app.transition_user_
--    status is called in that branch ONLY, exactly as before. For a
--    FUTURE-SCHEDULED transition, app.transition_user_status is NOT called at
--    scheduling time at all -- deferred entirely to app.activate_due_employee_
--    lifecycle_transitions, which calls it (suspended/revoked/active as
--    appropriate) at the SAME point it materializes the version's fields onto
--    app.employees, inside the SAME sweep-iteration transaction. Getting the
--    timing wrong either direction was explicitly named as the risk to guard
--    against: revoking Platform access at SCHEDULING time (before the effective
--    date genuinely arrives) would be a live availability bug -- an employee
--    scheduled for suspension two weeks from now would lose system access today;
--    never calling it at all until an unrelated later action happens would
--    regress HRT-295's own ISS-2026-104 fix for the future-dated path
--    specifically. Both paths are live-tested in this checkpoint's own db-test
--    regression file (immediate: role_assignments/app.users.status change inside
--    the SAME transaction as the HR-side flip, exactly as HRT-295 proved;
--    future: app.users.status/role_assignments UNCHANGED immediately after
--    scheduling, THEN correctly transitioned only after the sweep activates the
--    due row).
--
-- 9. **Downstream consumers of app.employees.lifecycle_status are unmodified,
--    confirmed by direct grep across the whole Phase 7 domain** (task item 6):
--    app.record_attendance_event (20260730900000:612), app.request_leave/app.
--    request_permit/app.request_business_trip (20260730930000:791), app.
--    request_overtime/app.log_timesheet_entry (20260730980000:919,1564), and
--    every payroll-eligibility read (20260731000000:1134,1603,1876) all
--    correctly continue to read app.employees' own CURRENT-state
--    lifecycle_status column directly -- a live, "right now" runtime check is
--    exactly what they need, and this migration is additive: it never changes
--    what that column reflects for an IMMEDIATE or BACKDATED transition (which
--    still update it synchronously, in the same transaction, precisely as
--    before -- decision 8's own "byte-identical immediate branch" discipline
--    guarantees this), and a genuinely FUTURE-scheduled transition correctly
--    leaves it untouched until due, which is the exact behavior every one of
--    these "right now" eligibility checks already needs (an employee scheduled
--    for suspension next month must remain eligible for attendance/leave/
--    overtime/payroll TODAY -- exactly what deferring the app.employees write
--    achieves). None required a code change; confirmed, not merely assumed.
--    app.sync_employee_leave_lifecycle_status (HRT-280, 20260730930000:1859) is
--    a SEPARATE, already-disclosed, already-accepted "not effective-dated"
--    reconciliation batch for leave-approval-driven lifecycle_status sync
--    specifically (its own comment explicitly cross-references ISS-2026-065) --
--    genuinely out of this task's own bounded scope (leave's own effective-dating
--    is Prompt 280's chartered domain, never HRT-274/this task's), left
--    completely untouched.
--
-- 10. **No speculative redesign**: payroll effective-dating, ticket capabilities,
--     employee_position_assignments (HRT-275's own domain, already effective-
--     dated and VERIFIED), and every RPC outside the literal 7 named by this
--     task (app.submit_employee_for_approval, app.decide_employee_approval, app.
--     activate_employee, app.link_employee_user, app.start_employee_leave, app.
--     end_employee_leave) are untouched, per this task's own "stay scoped to
--     exactly this requirement" instruction and this repository's own
--     established "no speculative redesign" discipline.
--
-- Tier B taxonomy self-check (docs/standards/RECURRING_DEFECT_TAXONOMY.md §4) --
-- full detail in docs/build-log/phase-07/HRT-ISS-065-CLOSURE.md:
--   C-04 (lock before decide): every write RPC already locks app.employees `for
--     update` before this migration's own logic runs (unchanged); app.record_
--     employee_lifecycle_version additionally locks every touched version row
--     `for update` before deciding supersede-vs-truncate (decision 3); the sweep
--     locks both app.employees and the specific version row before re-checking
--     and acting (decision 7).
--   C-08 (widening): re-verified per-RPC in decision 4 above -- only the
--     BACKDATED branch of 4 RPCs gains a NEW HRS:Override check (strictly
--     narrower, never wider, for those callers); the other 3 already required
--     HRS:Override unconditionally. Every existing (today, non-backdated) caller
--     of all 7 RPCs is provably unaffected -- new trailing parameters with
--     defaults, confirmed against every existing positional AND named-parameter
--     call site in this repository (scripts/db-tests/hris-employee-master.sql,
--     server/mutations/employee.ts) without editing any of them.
--   C-19 (supersede-before-insert ordering): decision 3 above is this exact
--     check, applied uniformly to every write, not merely the ordinary
--     chronological-succession case.
--   C-21 (lock order consistency with HRT-295): app.transition_user_status
--     itself takes no NEW locks this migration introduces (unmodified); the
--     employees-then-versions order (decision 7) is the only new cross-table
--     lock pair this migration adds, and it is consistent everywhere it is
--     taken.
--
-- Migration discipline: purely additive (new table, new functions, 7 existing
-- functions DROPped and re-CREATEd with a longer -- never reordered, never
-- removed -- parameter list, mirroring the established
-- 20260730810000_harden_procurement_approval_currency_normalization.sql
-- precedent for "add a new parameter to an already-applied function", since
-- CREATE OR REPLACE FUNCTION cannot change a function's own argument-type
-- signature). No applied migration is edited. No table is dropped or destructively
-- altered.

-- ===========================================================================
-- 1. app.employee_lifecycle_versions.
-- ===========================================================================

create table app.employee_lifecycle_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  master_record_id uuid not null references app.employees (master_record_id),
  lifecycle_status text not null,
  employment_type text not null,
  company_org_unit_id uuid references app.org_units (id),
  branch_org_unit_id uuid references app.org_units (id),
  department_org_unit_id uuid references app.org_units (id),
  position_title text,
  manager_employee_id uuid references app.employees (master_record_id),
  hire_date date,
  probation_end_date date,
  employment_end_date date,
  effective_start_date date not null,
  effective_end_date date,
  validity_range daterange generated always as (daterange(effective_start_date, effective_end_date, '[]')) stored,
  status text not null default 'active',
  change_reason text not null,
  decided_by text,
  decided_at timestamptz not null default now(),
  decided_reason text,
  previous_version_id uuid references app.employee_lifecycle_versions (id),
  materialized_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employee_lifecycle_versions_status_check check (status in ('scheduled', 'active', 'superseded')),
  constraint employee_lifecycle_versions_change_reason_check check (
    change_reason in ('hire', 'transfer', 'promotion', 'demotion', 'suspend', 'reactivate', 'terminate', 'archive', 'correction')
  ),
  constraint employee_lifecycle_versions_lifecycle_status_check check (
    lifecycle_status in ('draft', 'submitted', 'approved', 'active', 'on_leave', 'suspended', 'terminated', 'archived')
  ),
  constraint employee_lifecycle_versions_effective_range_check check (effective_end_date is null or effective_end_date >= effective_start_date),
  constraint employee_lifecycle_versions_manager_not_self_check check (manager_employee_id is distinct from master_record_id)
);

comment on table app.employee_lifecycle_versions is
  'ISS-2026-065 closure: effective-dated employee lifecycle/identity history, one full point-in-time snapshot per version, mirroring app.employee_position_assignments'' own shape (HRT-275) for the EMPLOYEE''s own record specifically -- lifecycle_status, org/position/manager, employment_type, hire_date/probation_end_date/employment_end_date. status=''scheduled'' (not yet applied to app.employees), ''active'' (applied at some point -- current or historical, decision 2), or ''superseded'' (voided by a later correction/reschedule). "In effect as of date X" is answered by validity_range @> X at READ time (app.get_employee_lifecycle_as_of), never by the status column alone -- see this migration''s own header, decisions 2/3.';

create index employee_lifecycle_versions_tenant_employee_idx on app.employee_lifecycle_versions (tenant_id, master_record_id);
create index employee_lifecycle_versions_tenant_status_idx on app.employee_lifecycle_versions (tenant_id, status);
create index employee_lifecycle_versions_due_activation_idx on app.employee_lifecycle_versions (tenant_id, effective_start_date) where status = 'scheduled';
create index employee_lifecycle_versions_previous_idx on app.employee_lifecycle_versions (previous_version_id) where previous_version_id is not null;

-- No two LIVE (scheduled/active) versions of the same employee may claim
-- overlapping time -- the database-enforced backstop behind decision 3's own
-- supersede-before-insert discipline, mirroring employee_position_assignments_
-- no_primary_overlap (HRT-275) exactly.
alter table app.employee_lifecycle_versions
  add constraint employee_lifecycle_versions_no_overlap
  exclude using gist (master_record_id with =, validity_range with &&)
  where (status in ('scheduled', 'active'));

comment on constraint employee_lifecycle_versions_no_overlap on app.employee_lifecycle_versions is
  'ISS-2026-065 closure, mirrors employee_position_assignments_no_primary_overlap (HRT-275). app.record_employee_lifecycle_version always supersedes/truncates every touched row BEFORE this INSERT runs (decision 3) -- this constraint should never actually fire in normal operation; it exists as a genuine database-level backstop, not merely application discipline.';

create trigger employee_lifecycle_versions_touch_row
  before update on app.employee_lifecycle_versions
  for each row
  execute function app.touch_employee_child_row();

-- Non-PII audit-log projection (mirrors app.employee_position_assignment_audit_
-- projection / app.employee_audit_projection exactly) -- deliberately omits
-- decided_reason (classified restricted, HRS_REGISTRY, see this migration's own
-- registry.ts addition below) from every app.capture_audit_event call.
create function app.employee_lifecycle_version_audit_projection(p_version app.employee_lifecycle_versions)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_version.id, 'master_record_id', p_version.master_record_id, 'lifecycle_status', p_version.lifecycle_status,
    'employment_type', p_version.employment_type, 'company_org_unit_id', p_version.company_org_unit_id,
    'branch_org_unit_id', p_version.branch_org_unit_id, 'department_org_unit_id', p_version.department_org_unit_id,
    'position_title', p_version.position_title, 'manager_employee_id', p_version.manager_employee_id,
    'hire_date', p_version.hire_date, 'probation_end_date', p_version.probation_end_date, 'employment_end_date', p_version.employment_end_date,
    'effective_start_date', p_version.effective_start_date, 'effective_end_date', p_version.effective_end_date,
    'status', p_version.status, 'change_reason', p_version.change_reason, 'previous_version_id', p_version.previous_version_id,
    'record_version', p_version.record_version
  );
$$;

comment on function app.employee_lifecycle_version_audit_projection is
  'ISS-2026-065 closure: the ONLY shape passed to app.capture_audit_event for an app.employee_lifecycle_versions row -- deliberately omits decided_reason (classified restricted, a named third party/disciplinary-narrative-shaped free-text column, HRS_REGISTRY), mirroring app.employee_audit_projection''s own established discipline (HRT-274) and this migration''s own decision 6.';

-- ===========================================================================
-- 2. app.record_employee_lifecycle_version -- the shared supersede-then-insert
--    writer every one of the 7 RPCs below calls (decision 3). service_role only,
--    never callable directly by `authenticated`.
-- ===========================================================================

create function app.record_employee_lifecycle_version(
  p_tenant_id uuid,
  p_master_record_id uuid,
  p_lifecycle_status text,
  p_employment_type text,
  p_company_org_unit_id uuid,
  p_branch_org_unit_id uuid,
  p_department_org_unit_id uuid,
  p_position_title text,
  p_manager_employee_id uuid,
  p_hire_date date,
  p_probation_end_date date,
  p_employment_end_date date,
  p_effective_date date,
  p_change_reason text,
  p_decided_reason text,
  p_materialize boolean,
  p_actor_label text
)
returns app.employee_lifecycle_versions
language plpgsql
as $$
declare
  v_stale app.employee_lifecycle_versions;
  v_previous_id uuid;
  v_new app.employee_lifecycle_versions;
begin
  -- Lock, then resolve, every currently-live version row this write could touch --
  -- BEFORE the INSERT below (decision 3, taxonomy C-04/C-19).
  for v_stale in
    select * from app.employee_lifecycle_versions
    where master_record_id = p_master_record_id
      and status in ('scheduled', 'active')
      and (effective_end_date is null or effective_end_date >= p_effective_date)
    order by effective_start_date
    for update
  loop
    if v_stale.effective_start_date >= p_effective_date then
      -- Bucket (a): entirely displaced -- void it, dates left untouched for audit.
      update app.employee_lifecycle_versions set status = 'superseded' where id = v_stale.id;
    else
      -- Bucket (b): straddles the new effective date -- truncate its own trailing
      -- edge; it remains a genuinely correct historical fact for the range it
      -- still covers, status unchanged.
      update app.employee_lifecycle_versions set effective_end_date = p_effective_date - 1 where id = v_stale.id;
      v_previous_id := v_stale.id;
    end if;
  end loop;

  insert into app.employee_lifecycle_versions (
    tenant_id, master_record_id, lifecycle_status, employment_type,
    company_org_unit_id, branch_org_unit_id, department_org_unit_id, position_title, manager_employee_id,
    hire_date, probation_end_date, employment_end_date, effective_start_date, status, change_reason,
    decided_by, decided_reason, previous_version_id, materialized_at, created_by
  ) values (
    p_tenant_id, p_master_record_id, p_lifecycle_status, p_employment_type,
    p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id, p_position_title, p_manager_employee_id,
    p_hire_date, p_probation_end_date, p_employment_end_date, p_effective_date,
    case when p_materialize then 'active' else 'scheduled' end, p_change_reason,
    p_actor_label, p_decided_reason, v_previous_id, case when p_materialize then now() else null end, p_actor_label
  )
  returning * into v_new;

  return v_new;
end;
$$;

comment on function app.record_employee_lifecycle_version is
  'ISS-2026-065 closure: the single supersede-then-insert writer for app.employee_lifecycle_versions, called from every one of the 7 lifecycle-transition RPCs. See this migration''s own header, decision 3, for the full bucket-(a)/(b) reasoning. service_role only -- never a public entry point.';

-- ===========================================================================
-- 3. The 7 lifecycle-transition RPCs -- each DROPped and re-CREATEd with a new,
--    strictly-additive trailing parameter list (decision 4/5; CREATE OR REPLACE
--    cannot change a function's own argument-type signature, so a plain
--    body-only replace is not available here -- mirrors the established
--    20260730810000 precedent for this exact situation).
-- ===========================================================================

drop function if exists app.create_employee_draft(uuid, text, text, text, text, text, text, date, text, date, uuid, uuid, uuid, text, uuid, uuid, text, text, text, uuid, text);

create function app.create_employee_draft(
  p_tenant_id uuid,
  p_full_name text,
  p_employment_type text,
  p_work_email text,
  p_personal_email text,
  p_personal_phone text,
  p_national_id_number text,
  p_date_of_birth date,
  p_gender text,
  p_hire_date date,
  p_company_org_unit_id uuid,
  p_branch_org_unit_id uuid,
  p_department_org_unit_id uuid,
  p_position_title text,
  p_manager_employee_id uuid,
  p_user_id uuid,
  p_employee_number text,
  p_intake_source text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_effective_date date default current_date,
  p_backdate_reason text default null
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.employees;
  v_existing_number text;
  v_number text;
  v_master app.master_records;
  v_employee app.employees;
  v_effective_date date;
  v_is_backdate boolean;
  v_version app.employee_lifecycle_versions;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_full_name is null or length(trim(p_full_name)) = 0 then
    raise exception 'invalid_full_name: full_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_employment_type not in ('full_time', 'part_time', 'contract', 'intern', 'probation', 'daily_worker') then
    raise exception 'invalid_employment_type: %', p_employment_type using errcode = 'check_violation';
  end if;
  if p_intake_source not in ('hr_created', 'bulk_import') then
    raise exception 'invalid_intake_source: % is not valid for direct draft creation', p_intake_source using errcode = 'check_violation';
  end if;

  -- ISS-2026-065 closure (decision 4/5): p_effective_date is recorded on the
  -- initial version row for historical-truth/"as of" purposes, but this RPC
  -- always materializes immediately (decision 5) -- only the backdate gate
  -- applies here, never true deferred scheduling.
  v_effective_date := coalesce(p_effective_date, current_date);
  v_is_backdate := v_effective_date < current_date;
  if v_is_backdate then
    if p_backdate_reason is null or length(trim(p_backdate_reason)) = 0 then
      raise exception 'backdate_reason_required: a non-empty reason is required to backdate this employee lifecycle change to %', v_effective_date using errcode = 'check_violation';
    end if;
    if not (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override')).allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Override (required to backdate an employee lifecycle change) for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- No cycle check is needed here: a brand-new draft has no id yet, so no existing
  -- row's manager chain can possibly already reach it -- a cycle is structurally
  -- impossible at creation time. app.assert_no_employee_manager_cycle is called from
  -- app.update_employee_draft and app.transfer_employee instead, the only two paths
  -- that can point manager_employee_id at an ALREADY-EXISTING row's chain.

  if p_manager_employee_id is not null and not exists (select 1 from app.employees where master_record_id = p_manager_employee_id and tenant_id = p_tenant_id) then
    raise exception 'employee_not_found: manager % is not a valid employee for tenant %', p_manager_employee_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if p_user_id is not null and not exists (select 1 from app.users where id = p_user_id and tenant_id = p_tenant_id) then
    raise exception 'user_not_found: % is not a valid user for tenant %', p_user_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if p_idempotency_key is not null then
    select e.* into v_existing
    from app.employees e
    where e.tenant_id = p_tenant_id and e.idempotency_key = p_idempotency_key;
    if found then
      select code into v_existing_number from app.master_records where id = v_existing.master_record_id;
      perform app.assert_employee_draft_idempotent_replay(
        v_existing, v_existing_number, p_full_name, p_employment_type, p_work_email, p_personal_email,
        p_personal_phone, p_national_id_number, p_date_of_birth, p_gender, p_hire_date,
        p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id, p_position_title,
        p_manager_employee_id, p_user_id, p_intake_source, p_employee_number, p_idempotency_key
      );
      return v_existing;
    end if;
  end if;

  v_number := coalesce(nullif(trim(p_employee_number), ''), app.next_employee_number(p_tenant_id));

  begin
    insert into app.master_records (master_type_code, tenant_id, code, name, aliases, attributes, created_by)
    values ('employee', p_tenant_id, v_number, p_full_name, '[]'::jsonb, '{}'::jsonb, p_actor_label)
    returning * into v_master;
  exception
    when unique_violation then
      raise exception 'employee_number_conflict: employee number % is already in use for this tenant', v_number
        using errcode = 'unique_violation';
  end;

  begin
    insert into app.employees (
      master_record_id, tenant_id, user_id, full_name, employment_type, intake_source,
      work_email, personal_email, personal_phone, national_id_number, date_of_birth, gender,
      hire_date, company_org_unit_id, branch_org_unit_id, department_org_unit_id,
      position_title, manager_employee_id, idempotency_key, created_by
    )
    values (
      v_master.id, p_tenant_id, p_user_id, p_full_name, p_employment_type, p_intake_source,
      p_work_email, p_personal_email, p_personal_phone, p_national_id_number, p_date_of_birth, p_gender,
      p_hire_date, p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id,
      p_position_title, p_manager_employee_id, p_idempotency_key, p_actor_label
    )
    returning * into v_employee;
  exception
    when unique_violation then
      select e.* into v_existing
      from app.employees e
      where e.tenant_id = p_tenant_id and e.idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      select code into v_existing_number from app.master_records where id = v_existing.master_record_id;
      perform app.assert_employee_draft_idempotent_replay(
        v_existing, v_existing_number, p_full_name, p_employment_type, p_work_email, p_personal_email,
        p_personal_phone, p_national_id_number, p_date_of_birth, p_gender, p_hire_date,
        p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id, p_position_title,
        p_manager_employee_id, p_user_id, p_intake_source, p_employee_number, p_idempotency_key
      );
      return v_existing;
  end;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_employee.master_record_id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  v_version := app.record_employee_lifecycle_version(
    p_tenant_id, v_employee.master_record_id, 'draft', p_employment_type,
    p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id, p_position_title, p_manager_employee_id,
    p_hire_date, null, null, v_effective_date, 'hire', p_backdate_reason, true, p_actor_label
  );

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_employee_draft',
    'app.employees', v_employee.master_record_id, 'success', null, null, app.employee_audit_projection(v_employee)
  );

  return v_employee;
end;
$$;

comment on function app.create_employee_draft is 'HRT-274: creates the canonical master_records row (master_type_code=''employee'') and its employees extension together, in one transaction. Gates exclusively on HRS:Create. ISS-2026-065 closure: accepts p_effective_date/p_backdate_reason (default current_date/null, fully backward-compatible) and writes the employee''s initial app.employee_lifecycle_versions row -- always materialized immediately (this migration''s own header, decision 5); backdating additionally requires HRS:Override + a non-empty reason.';

drop function if exists app.update_employee_draft(uuid, integer, text, text, text, text, text, text, date, text, date, date, uuid, uuid, uuid, text, uuid, uuid, text);

create function app.update_employee_draft(
  p_master_record_id uuid,
  p_expected_version integer,
  p_full_name text,
  p_employment_type text,
  p_work_email text,
  p_personal_email text,
  p_personal_phone text,
  p_national_id_number text,
  p_date_of_birth date,
  p_gender text,
  p_hire_date date,
  p_probation_end_date date,
  p_company_org_unit_id uuid,
  p_branch_org_unit_id uuid,
  p_department_org_unit_id uuid,
  p_position_title text,
  p_manager_employee_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_effective_date date default current_date,
  p_backdate_reason text default null
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_effective_date date;
  v_is_backdate boolean;
  v_version app.employee_lifecycle_versions;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status <> 'draft' then
    raise exception 'employee_not_draft: employee % is % -- only a draft profile may be edited this way', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  -- HRT-275 review-round fix (HIGH): a governed position_id already exists for this
  -- employee -- position_title/manager_employee_id must be changed through
  -- app.propose_employee_position_assignment (the governed workflow), never silently
  -- overwritten here.
  if v_employee.position_id is not null then
    raise exception 'governed_position_exists: employee % already has a governed position (%) -- edit position/manager via app.propose_employee_position_assignment, not this free-text profile edit', p_master_record_id, v_employee.position_id
      using errcode = 'check_violation';
  end if;

  -- ISS-2026-065 closure (decision 4/5): same carve-out as app.create_employee_draft
  -- -- always materializes immediately; only the backdate gate applies.
  v_effective_date := coalesce(p_effective_date, current_date);
  v_is_backdate := v_effective_date < current_date;
  if v_is_backdate then
    if p_backdate_reason is null or length(trim(p_backdate_reason)) = 0 then
      raise exception 'backdate_reason_required: a non-empty reason is required to backdate this employee lifecycle change to %', v_effective_date using errcode = 'check_violation';
    end if;
    if not (app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Override')).allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Override (required to backdate an employee lifecycle change) for tenant %', p_actor_auth_user_id, v_employee.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if p_full_name is null or length(trim(p_full_name)) = 0 then
    raise exception 'invalid_full_name: full_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_employment_type not in ('full_time', 'part_time', 'contract', 'intern', 'probation', 'daily_worker') then
    raise exception 'invalid_employment_type: %', p_employment_type using errcode = 'check_violation';
  end if;

  if p_manager_employee_id is not null then
    if not exists (select 1 from app.employees where master_record_id = p_manager_employee_id and tenant_id = v_employee.tenant_id) then
      raise exception 'employee_not_found: manager % is not a valid employee for tenant %', p_manager_employee_id, v_employee.tenant_id using errcode = 'no_data_found';
    end if;
    perform app.assert_no_employee_manager_cycle(p_master_record_id, p_manager_employee_id);
  end if;

  update app.employees
  set full_name = p_full_name, employment_type = p_employment_type, work_email = p_work_email,
      personal_email = p_personal_email, personal_phone = p_personal_phone, national_id_number = p_national_id_number,
      date_of_birth = p_date_of_birth, gender = p_gender, hire_date = p_hire_date, probation_end_date = p_probation_end_date,
      company_org_unit_id = p_company_org_unit_id, branch_org_unit_id = p_branch_org_unit_id, department_org_unit_id = p_department_org_unit_id,
      position_title = p_position_title, manager_employee_id = p_manager_employee_id
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.master_records set name = p_full_name where id = p_master_record_id;

  v_version := app.record_employee_lifecycle_version(
    v_employee.tenant_id, p_master_record_id, v_employee.lifecycle_status, v_employee.employment_type,
    v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
    v_employee.position_title, v_employee.manager_employee_id, v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
    v_effective_date, 'correction', p_backdate_reason, true, p_actor_label
  );

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_employee_draft',
    'app.employees', p_master_record_id, 'success', null, null, app.employee_audit_projection(v_employee)
  );

  return v_employee;
end;
$$;

comment on function app.update_employee_draft is
  'HRT-274, review-round-fixed by HRT-275 (20260730850000): draft-only free-text profile edit. Raises governed_position_exists when the employee already carries a governed position_id. ISS-2026-065 closure: accepts p_effective_date/p_backdate_reason (default current_date/null); always materializes immediately (decision 5); backdating requires HRS:Override + a non-empty reason.';

drop function if exists app.suspend_employee(uuid, integer, text, uuid, text);

create function app.suspend_employee(
  p_master_record_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text,
  p_effective_date date default current_date
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_from_status text;
  v_effective_date date;
  v_is_future boolean;
  v_version app.employee_lifecycle_versions;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to suspend an employee' using errcode = 'check_violation';
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

  if v_employee.lifecycle_status not in ('active', 'on_leave') then
    raise exception 'invalid_transition: employee % is % and cannot be suspended', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_employee.lifecycle_status;

  -- ISS-2026-065 closure: already HRS:Override-gated unconditionally above, so
  -- backdating widens nothing further (decision 4) -- p_reason already doubles as
  -- the mandatory backdate-correction reason (already required, unconditionally,
  -- above).
  v_effective_date := coalesce(p_effective_date, current_date);
  v_is_future := v_effective_date > current_date;

  if v_is_future then
    -- Scheduled: app.employees' own current-state columns are untouched until
    -- app.activate_due_employee_lifecycle_transitions applies it.
    -- app.transition_user_status is deliberately NOT called yet -- see this
    -- migration's own header, decision 8.
    v_version := app.record_employee_lifecycle_version(
      v_employee.tenant_id, p_master_record_id, 'suspended', v_employee.employment_type,
      v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
      v_employee.position_title, v_employee.manager_employee_id, v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
      v_effective_date, 'suspend', p_reason, false, p_actor_label
    );

    insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
    values (v_employee.tenant_id, p_master_record_id, v_from_status, 'suspended', p_reason, jsonb_build_object('scheduled', true, 'effective_start_date', v_effective_date, 'version_id', v_version.id), p_actor_auth_user_id, p_actor_label);

    perform app.capture_audit_event(
      v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'suspend_employee',
      'app.employees', p_master_record_id, 'success', null, null, jsonb_build_object('scheduled', true, 'effective_start_date', v_effective_date)
    );

    return v_employee;
  end if;

  -- Immediate/backdated path -- byte-identical to the HRT-295 (20260731230000)
  -- shape (this migration's own header, decision 8).
  update app.employees
  set lifecycle_status = 'suspended', suspend_reason = p_reason
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, v_from_status, 'suspended', p_reason, p_actor_auth_user_id, p_actor_label);

  v_version := app.record_employee_lifecycle_version(
    v_employee.tenant_id, p_master_record_id, 'suspended', v_employee.employment_type,
    v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
    v_employee.position_title, v_employee.manager_employee_id, v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
    v_effective_date, 'suspend', p_reason, true, p_actor_label
  );

  if v_employee.user_id is not null then
    perform app.transition_user_status(v_employee.user_id, 'suspended', p_reason, p_actor_label);
  end if;

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'suspend_employee',
    'app.employees', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

comment on function app.suspend_employee is
  'HRT-274, coupled to Platform identity by HRT-295 (ISS-2026-104). ISS-2026-065 closure: accepts p_effective_date (default current_date). A future p_effective_date schedules the transition (app.employees and app.transition_user_status are both left untouched until app.activate_due_employee_lifecycle_transitions activates it -- this migration''s own header, decision 8); a past p_effective_date backdates it (already gated at HRS:Override + mandatory reason, unconditionally, so nothing widens).';

drop function if exists app.reactivate_employee(uuid, integer, uuid, text);

create function app.reactivate_employee(
  p_master_record_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text,
  p_effective_date date default current_date, p_backdate_reason text default null
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_restore_status text;
  v_platform_status text;
  v_effective_date date;
  v_is_future boolean;
  v_is_backdate boolean;
  v_version app.employee_lifecycle_versions;
begin
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

  if v_employee.lifecycle_status <> 'suspended' then
    raise exception 'invalid_transition: employee % is % and cannot be reactivated', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  -- ISS-2026-065 closure: already HRS:Override-gated unconditionally above, so
  -- backdating widens nothing further -- only the mandatory-reason-when-
  -- backdating check applies (reactivate has no existing reason parameter).
  v_effective_date := coalesce(p_effective_date, current_date);
  v_is_future := v_effective_date > current_date;
  v_is_backdate := v_effective_date < current_date;
  if v_is_backdate and (p_backdate_reason is null or length(trim(p_backdate_reason)) = 0) then
    raise exception 'backdate_reason_required: a non-empty reason is required to backdate this employee lifecycle change to %', v_effective_date using errcode = 'check_violation';
  end if;

  -- Restore the status the employee was suspended FROM (active or on_leave) --
  -- unmodified from this function's own pre-existing review-round fix.
  select from_status into v_restore_status
  from app.employee_lifecycle_events
  where master_record_id = p_master_record_id and to_status = 'suspended'
  order by occurred_at desc
  limit 1;
  if v_restore_status is null or v_restore_status not in ('active', 'on_leave') then
    v_restore_status := 'active';
  end if;

  if v_is_future then
    v_version := app.record_employee_lifecycle_version(
      v_employee.tenant_id, p_master_record_id, v_restore_status, v_employee.employment_type,
      v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
      v_employee.position_title, v_employee.manager_employee_id, v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
      v_effective_date, 'reactivate', p_backdate_reason, false, p_actor_label
    );

    insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
    values (v_employee.tenant_id, p_master_record_id, 'suspended', v_restore_status, p_backdate_reason, jsonb_build_object('scheduled', true, 'effective_start_date', v_effective_date, 'version_id', v_version.id), p_actor_auth_user_id, p_actor_label);

    perform app.capture_audit_event(
      v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'reactivate_employee',
      'app.employees', p_master_record_id, 'success', null, null, jsonb_build_object('scheduled', true, 'effective_start_date', v_effective_date)
    );

    return v_employee;
  end if;

  -- Immediate/backdated path -- byte-identical to the HRT-295 (20260731230000)
  -- shape (this migration's own header, decision 8).
  update app.employees
  set lifecycle_status = v_restore_status, suspend_reason = null
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, 'suspended', v_restore_status, p_actor_auth_user_id, p_actor_label);

  v_version := app.record_employee_lifecycle_version(
    v_employee.tenant_id, p_master_record_id, v_restore_status, v_employee.employment_type,
    v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
    v_employee.position_title, v_employee.manager_employee_id, v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
    v_effective_date, 'reactivate', p_backdate_reason, true, p_actor_label
  );

  if v_employee.user_id is not null then
    select status into v_platform_status from app.users where id = v_employee.user_id;
    if v_platform_status = 'suspended' then
      perform app.transition_user_status(v_employee.user_id, 'active', 'employee reactivated: end of suspension', p_actor_label);
    end if;
  end if;

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'reactivate_employee',
    'app.employees', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

comment on function app.reactivate_employee is
  'HRT-274, coupled to Platform identity by HRT-295. ISS-2026-065 closure: accepts p_effective_date/p_backdate_reason. A future p_effective_date schedules the un-suspension (app.transition_user_status deferred to the sweep -- decision 8); a past p_effective_date backdates it (already HRS:Override-gated; a non-empty p_backdate_reason becomes mandatory).';

drop function if exists app.terminate_employee(uuid, integer, text, date, uuid, text);

create function app.terminate_employee(
  p_master_record_id uuid, p_expected_version integer, p_reason text, p_employment_end_date date, p_actor_auth_user_id uuid, p_actor_label text,
  p_effective_date date default current_date
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_from_status text;
  v_effective_date date;
  v_is_future boolean;
  v_version app.employee_lifecycle_versions;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to terminate an employee' using errcode = 'check_violation';
  end if;
  if p_employment_end_date is null then
    raise exception 'employment_end_date_required: an effective employment_end_date is required to terminate an employee' using errcode = 'check_violation';
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

  if v_employee.lifecycle_status not in ('active', 'on_leave', 'suspended') then
    raise exception 'invalid_transition: employee % is % and cannot be terminated', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_employee.lifecycle_status;

  -- ISS-2026-065 closure: already HRS:Override-gated + mandatory-reason
  -- unconditionally above, so backdating widens nothing further (decision 4).
  v_effective_date := coalesce(p_effective_date, current_date);
  v_is_future := v_effective_date > current_date;

  if v_is_future then
    v_version := app.record_employee_lifecycle_version(
      v_employee.tenant_id, p_master_record_id, 'terminated', v_employee.employment_type,
      v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
      v_employee.position_title, v_employee.manager_employee_id, v_employee.hire_date, v_employee.probation_end_date, p_employment_end_date,
      v_effective_date, 'terminate', p_reason, false, p_actor_label
    );

    insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
    values (
      v_employee.tenant_id, p_master_record_id, v_from_status, 'terminated', p_reason,
      jsonb_build_object('employment_end_date', p_employment_end_date, 'scheduled', true, 'effective_start_date', v_effective_date, 'version_id', v_version.id),
      p_actor_auth_user_id, p_actor_label
    );

    perform app.capture_audit_event(
      v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'terminate_employee',
      'app.employees', p_master_record_id, 'success', null, null, jsonb_build_object('employment_end_date', p_employment_end_date, 'scheduled', true, 'effective_start_date', v_effective_date)
    );

    return v_employee;
  end if;

  -- Immediate/backdated path -- byte-identical to the HRT-295 (20260731230000)
  -- shape (this migration's own header, decision 8).
  update app.employees
  set lifecycle_status = 'terminated', terminate_reason = p_reason, employment_end_date = p_employment_end_date,
      suspend_reason = null, leave_reason = null
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, v_from_status, 'terminated', p_reason, jsonb_build_object('employment_end_date', p_employment_end_date), p_actor_auth_user_id, p_actor_label);

  v_version := app.record_employee_lifecycle_version(
    v_employee.tenant_id, p_master_record_id, 'terminated', v_employee.employment_type,
    v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
    v_employee.position_title, v_employee.manager_employee_id, v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
    v_effective_date, 'terminate', p_reason, true, p_actor_label
  );

  if v_employee.user_id is not null then
    perform app.transition_user_status(v_employee.user_id, 'revoked', p_reason, p_actor_label);
  end if;

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'terminate_employee',
    'app.employees', p_master_record_id, 'success', null, null, jsonb_build_object('employment_end_date', p_employment_end_date)
  );

  return v_employee;
end;
$$;

comment on function app.terminate_employee is
  'HRT-274 (section 24: "never erases required payroll, attendance, Operations or audit history"): terminal, but the row and every child/history row is preserved unchanged -- no delete anywhere. HRT-295 / ISS-2026-104 fix: user_id remains linked, but Platform authentication/authority IS revoked in the same transaction via app.transition_user_status for an immediate/backdated transition. ISS-2026-065 closure: accepts p_effective_date. A future p_effective_date schedules the termination -- app.employees and app.transition_user_status are both left untouched until app.activate_due_employee_lifecycle_transitions activates it (this migration''s own header, decision 8).';

drop function if exists app.archive_employee_profile(uuid, integer, text, uuid, text);

create function app.archive_employee_profile(
  p_master_record_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text,
  p_effective_date date default current_date
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_from_status text;
  v_effective_date date;
  v_is_future boolean;
  v_is_backdate boolean;
  v_version app.employee_lifecycle_versions;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status not in ('draft', 'submitted', 'approved', 'terminated') then
    raise exception 'invalid_transition: employee % is % and cannot be archived', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_employee.lifecycle_status;

  -- ISS-2026-065 closure (decision 4): archive is normally HRS:Edit only --
  -- backdating requires an EXPLICIT, additional HRS:Override check plus a
  -- non-empty reason (p_reason is normally optional; now conditionally mandatory).
  v_effective_date := coalesce(p_effective_date, current_date);
  v_is_future := v_effective_date > current_date;
  v_is_backdate := v_effective_date < current_date;
  if v_is_backdate then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'backdate_reason_required: a non-empty reason is required to backdate this employee lifecycle change to %', v_effective_date using errcode = 'check_violation';
    end if;
    if not (app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Override')).allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Override (required to backdate an employee lifecycle change) for tenant %', p_actor_auth_user_id, v_employee.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_is_future then
    v_version := app.record_employee_lifecycle_version(
      v_employee.tenant_id, p_master_record_id, 'archived', v_employee.employment_type,
      v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
      v_employee.position_title, v_employee.manager_employee_id, v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
      v_effective_date, 'archive', p_reason, false, p_actor_label
    );

    insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
    values (v_employee.tenant_id, p_master_record_id, v_from_status, 'archived', p_reason, jsonb_build_object('scheduled', true, 'effective_start_date', v_effective_date, 'version_id', v_version.id), p_actor_auth_user_id, p_actor_label);

    perform app.capture_audit_event(
      v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_employee_profile',
      'app.employees', p_master_record_id, 'success', null, null, jsonb_build_object('scheduled', true, 'effective_start_date', v_effective_date)
    );

    return v_employee;
  end if;

  update app.employees
  set lifecycle_status = 'archived', archive_reason = p_reason
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, v_from_status, 'archived', p_reason, p_actor_auth_user_id, p_actor_label);

  v_version := app.record_employee_lifecycle_version(
    v_employee.tenant_id, p_master_record_id, 'archived', v_employee.employment_type,
    v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
    v_employee.position_title, v_employee.manager_employee_id, v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
    v_effective_date, 'archive', p_reason, true, p_actor_label
  );

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_employee_profile',
    'app.employees', p_master_record_id, 'success', null, null, '{}'::jsonb
  );

  return v_employee;
end;
$$;

comment on function app.archive_employee_profile is
  'HRT-274 (decision 6): reachable from a never-activated profile (draft/submitted/approved) OR from terminated. ISS-2026-065 closure: accepts p_effective_date (default current_date). A future date schedules the archival (app.employees untouched until the sweep activates it); a past date backdates it -- newly gated at HRS:Override + a now-mandatory p_reason (this migration''s own header, decision 4).';

drop function if exists app.transfer_employee(uuid, integer, uuid, uuid, uuid, text, uuid, text, uuid, text);

create function app.transfer_employee(
  p_master_record_id uuid, p_expected_version integer, p_company_org_unit_id uuid, p_branch_org_unit_id uuid, p_department_org_unit_id uuid,
  p_position_title text, p_manager_employee_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text,
  p_effective_date date default current_date
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_before jsonb;
  v_effective_date date;
  v_is_future boolean;
  v_is_backdate boolean;
  v_version app.employee_lifecycle_versions;
begin
  select * into v_employee from app.employees where master_record_id = p_master_record_id for update;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_employee.record_version <> p_expected_version then
    raise exception 'stale_version: employee % expected version % but found %', p_master_record_id, p_expected_version, v_employee.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'invalid_transition: employee % is % and cannot be transferred', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  -- HRT-275 review-round fix (HIGH): a governed position_id already exists for this
  -- employee -- position_title/manager_employee_id must be changed through
  -- app.propose_employee_position_assignment (the governed workflow), never silently
  -- overwritten here.
  if v_employee.position_id is not null then
    raise exception 'governed_position_exists: employee % already has a governed position (%) -- transfer via app.propose_employee_position_assignment, not this free-text transfer', p_master_record_id, v_employee.position_id
      using errcode = 'check_violation';
  end if;

  -- ISS-2026-065 closure (decision 4): transfer is normally HRS:Edit only --
  -- backdating requires an EXPLICIT, additional HRS:Override check plus a
  -- non-empty reason (p_reason is normally optional; now conditionally mandatory).
  v_effective_date := coalesce(p_effective_date, current_date);
  v_is_future := v_effective_date > current_date;
  v_is_backdate := v_effective_date < current_date;
  if v_is_backdate then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'backdate_reason_required: a non-empty reason is required to backdate this employee lifecycle change to %', v_effective_date using errcode = 'check_violation';
    end if;
    if not (app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Override')).allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Override (required to backdate an employee lifecycle change) for tenant %', p_actor_auth_user_id, v_employee.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if p_manager_employee_id is not null then
    if not exists (select 1 from app.employees where master_record_id = p_manager_employee_id and tenant_id = v_employee.tenant_id) then
      raise exception 'employee_not_found: manager % is not a valid employee for tenant %', p_manager_employee_id, v_employee.tenant_id using errcode = 'no_data_found';
    end if;
    perform app.assert_no_employee_manager_cycle(p_master_record_id, p_manager_employee_id);
  end if;

  v_before := jsonb_build_object(
    'company_org_unit_id', v_employee.company_org_unit_id, 'branch_org_unit_id', v_employee.branch_org_unit_id,
    'department_org_unit_id', v_employee.department_org_unit_id, 'position_title', v_employee.position_title,
    'manager_employee_id', v_employee.manager_employee_id
  );

  if v_is_future then
    -- Scheduled: org-unit shape for the NEW (not-yet-applied) org units is
    -- authoritatively re-validated only at activation time, via the same trigger
    -- every other app.employees UPDATE goes through -- this migration's own
    -- header, decision 7, discloses this explicitly.
    v_version := app.record_employee_lifecycle_version(
      v_employee.tenant_id, p_master_record_id, v_employee.lifecycle_status, v_employee.employment_type,
      p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id, p_position_title, p_manager_employee_id,
      v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
      v_effective_date, 'transfer', p_reason, false, p_actor_label
    );

    insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
    values (
      v_employee.tenant_id, p_master_record_id, v_employee.lifecycle_status, v_employee.lifecycle_status, p_reason,
      jsonb_build_object(
        'event', 'transfer', 'before', v_before,
        'after', jsonb_build_object(
          'company_org_unit_id', p_company_org_unit_id, 'branch_org_unit_id', p_branch_org_unit_id,
          'department_org_unit_id', p_department_org_unit_id, 'position_title', p_position_title,
          'manager_employee_id', p_manager_employee_id
        ),
        'scheduled', true, 'effective_start_date', v_effective_date, 'version_id', v_version.id
      ),
      p_actor_auth_user_id, p_actor_label
    );

    perform app.capture_audit_event(
      v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'transfer_employee',
      'app.employees', p_master_record_id, 'success', null, v_before, jsonb_build_object('scheduled', true, 'effective_start_date', v_effective_date)
    );

    return v_employee;
  end if;

  update app.employees
  set company_org_unit_id = p_company_org_unit_id, branch_org_unit_id = p_branch_org_unit_id,
      department_org_unit_id = p_department_org_unit_id, position_title = p_position_title,
      manager_employee_id = p_manager_employee_id
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
  values (
    v_employee.tenant_id, p_master_record_id, v_employee.lifecycle_status, v_employee.lifecycle_status, p_reason,
    jsonb_build_object(
      'event', 'transfer', 'before', v_before,
      'after', jsonb_build_object(
        'company_org_unit_id', p_company_org_unit_id, 'branch_org_unit_id', p_branch_org_unit_id,
        'department_org_unit_id', p_department_org_unit_id, 'position_title', p_position_title,
        'manager_employee_id', p_manager_employee_id
      )
    ),
    p_actor_auth_user_id, p_actor_label
  );

  v_version := app.record_employee_lifecycle_version(
    v_employee.tenant_id, p_master_record_id, v_employee.lifecycle_status, v_employee.employment_type,
    v_employee.company_org_unit_id, v_employee.branch_org_unit_id, v_employee.department_org_unit_id,
    v_employee.position_title, v_employee.manager_employee_id, v_employee.hire_date, v_employee.probation_end_date, v_employee.employment_end_date,
    v_effective_date, 'transfer', p_reason, true, p_actor_label
  );

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'transfer_employee',
    'app.employees', p_master_record_id, 'success', null, v_before, app.employee_audit_projection(v_employee)
  );

  return v_employee;
end;
$$;

comment on function app.transfer_employee is
  'HRT-274 (section 22): moves company/branch/department/position/manager while preserving full before/after history in app.employee_lifecycle_events.metadata -- lifecycle_status itself is unchanged by a transfer. Callable from any non-terminal status without a governed position_id. ISS-2026-065 closure: accepts p_effective_date (default current_date). A future date schedules the transfer (this migration''s own header, decision 7, discloses that org-unit shape is re-validated only at activation for the scheduled path); a past date backdates it -- newly gated at HRS:Override + a now-mandatory p_reason.';

-- ===========================================================================
-- 4. app.get_employee_lifecycle_as_of -- the genuine "as of" read (decision 6).
-- ===========================================================================

create function app.get_employee_lifecycle_as_of(p_master_record_id uuid, p_actor_auth_user_id uuid, p_as_of date default current_date)
returns table (
  id uuid, master_record_id uuid, lifecycle_status text, employment_type text,
  company_org_unit_id uuid, branch_org_unit_id uuid, department_org_unit_id uuid,
  position_title text, manager_employee_id uuid, hire_date date, probation_end_date date, employment_end_date date,
  effective_start_date date, effective_end_date date, status text, change_reason text,
  decided_by text, decided_at timestamptz, decided_reason text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_caller_user_id uuid;
  v_is_self boolean;
  v_unmasked boolean;
begin
  select * into v_employee from app.employees e where e.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  select u.id into v_caller_user_id from app.users u where u.auth_user_id = p_actor_auth_user_id and u.tenant_id = v_employee.tenant_id;
  v_is_self := v_caller_user_id is not null and v_employee.user_id is not distinct from v_caller_user_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed and not v_is_self then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_unmasked := v_is_self or app.has_view_personal_data(v_employee.tenant_id, p_actor_auth_user_id);

  return query
  select
    v.id, v.master_record_id, v.lifecycle_status, v.employment_type,
    v.company_org_unit_id, v.branch_org_unit_id, v.department_org_unit_id,
    v.position_title, v.manager_employee_id, v.hire_date, v.probation_end_date, v.employment_end_date,
    v.effective_start_date, v.effective_end_date, v.status, v.change_reason,
    v.decided_by, v.decided_at, case when v_unmasked then v.decided_reason else null end, v.record_version
  from app.employee_lifecycle_versions v
  where v.master_record_id = p_master_record_id and v.status in ('scheduled', 'active') and v.validity_range @> p_as_of;
end;
$$;

comment on function app.get_employee_lifecycle_as_of is
  'ISS-2026-065 closure: reconstructs what an employee''s lifecycle state genuinely was/will be on any given date, reading app.employee_lifecycle_versions'' own validity_range directly (never app.employees'' current-state columns, decision 6). Mirrors app.get_employee_current_assignment (HRT-275) exactly -- always correct regardless of whether app.activate_due_employee_lifecycle_transitions has run. decided_reason masked to null unless self or HRS:View personal data, mirroring app.get_employee_profile. Distinct from the pre-existing app.get_employee_lifecycle_history (an append-only event log requiring a manual linear scan) -- left unmodified.';

-- ===========================================================================
-- 5. app.activate_due_employee_lifecycle_transitions -- the maintenance sweep
--    (decision 7). HRS:Override-gated, idempotent, no live scheduler wired to
--    it (NOT_RUN, disclosed in the build log).
-- ===========================================================================

create function app.activate_due_employee_lifecycle_transitions(p_tenant_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns integer
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_candidate record;
  v_employee app.employees;
  v_version app.employee_lifecycle_versions;
  v_apply_failed boolean;
  v_count integer := 0;
  v_skipped integer := 0;
  v_skipped_ids uuid[] := '{}';
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_candidate in
    select id, master_record_id from app.employee_lifecycle_versions
    where tenant_id = p_tenant_id and status = 'scheduled' and effective_start_date <= current_date
    order by effective_start_date
  loop
    -- C-21 lock order: app.employees FIRST, then the specific version row --
    -- the SAME order every write RPC above uses (it locks app.employees before
    -- ever calling app.record_employee_lifecycle_version, the only other place
    -- that locks version rows). See this migration's own header, decision 7.
    select * into v_employee from app.employees where master_record_id = v_candidate.master_record_id for update;
    select * into v_version from app.employee_lifecycle_versions where id = v_candidate.id for update;

    -- Idempotent / defensive re-check under lock -- a concurrent sweep call, or an
    -- earlier iteration of THIS SAME sweep touching this employee via a
    -- since-superseding row, may have already resolved this one.
    if v_version.status <> 'scheduled' or v_version.effective_start_date > current_date then
      continue;
    end if;

    v_apply_failed := false;
    begin
      -- Re-validates cycle-freedom immediately before writing manager_employee_id
      -- -- the same defect class, and the same fix shape, app.sync_employee_
      -- current_assignment_cache's own "CRITICAL review-round fix" (HRT-275)
      -- already established.
      if v_version.manager_employee_id is not null then
        perform app.assert_no_employee_manager_cycle(v_version.master_record_id, v_version.manager_employee_id);
      end if;

      update app.employees
      set lifecycle_status = v_version.lifecycle_status, employment_type = v_version.employment_type,
          company_org_unit_id = v_version.company_org_unit_id, branch_org_unit_id = v_version.branch_org_unit_id,
          department_org_unit_id = v_version.department_org_unit_id, position_title = v_version.position_title,
          manager_employee_id = v_version.manager_employee_id, hire_date = v_version.hire_date,
          probation_end_date = v_version.probation_end_date, employment_end_date = v_version.employment_end_date,
          suspend_reason = case
            when v_version.change_reason = 'suspend' then v_version.decided_reason
            when v_version.change_reason in ('reactivate', 'terminate') then null
            else suspend_reason
          end,
          terminate_reason = case when v_version.change_reason = 'terminate' then v_version.decided_reason else terminate_reason end,
          archive_reason = case when v_version.change_reason = 'archive' then v_version.decided_reason else archive_reason end,
          leave_reason = case when v_version.change_reason = 'terminate' then null else leave_reason end
      where master_record_id = v_version.master_record_id;
    exception
      when check_violation or no_data_found then
        v_apply_failed := true;
        v_skipped := v_skipped + 1;
        v_skipped_ids := array_append(v_skipped_ids, v_version.id);
    end;

    if v_apply_failed then
      continue;
    end if;

    update app.employee_lifecycle_versions set status = 'active', materialized_at = now() where id = v_version.id;

    -- HRT-295 identity-coupling composition (this migration's own header,
    -- decision 8): the deferred Platform-identity transition fires NOW, at
    -- activation, never earlier.
    if v_version.change_reason = 'suspend' and v_employee.user_id is not null then
      perform app.transition_user_status(v_employee.user_id, 'suspended', v_version.decided_reason, p_actor_label);
    elsif v_version.change_reason = 'terminate' and v_employee.user_id is not null then
      perform app.transition_user_status(v_employee.user_id, 'revoked', v_version.decided_reason, p_actor_label);
    elsif v_version.change_reason = 'reactivate' and v_employee.user_id is not null then
      if (select status from app.users where id = v_employee.user_id) = 'suspended' then
        perform app.transition_user_status(v_employee.user_id, 'active', 'employee reactivated: scheduled end of suspension', p_actor_label);
      end if;
    end if;

    insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
    values (
      v_version.tenant_id, v_version.master_record_id, v_employee.lifecycle_status, v_version.lifecycle_status, v_version.decided_reason,
      jsonb_build_object('event', 'scheduled_activation', 'version_id', v_version.id, 'change_reason', v_version.change_reason),
      p_actor_auth_user_id, p_actor_label
    );

    v_count := v_count + 1;
  end loop;

  if v_count > 0 then
    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_due_employee_lifecycle_transitions',
      'app.employees', p_tenant_id, 'success', null, null, jsonb_build_object('activated_count', v_count)
    );
  end if;

  if v_skipped > 0 then
    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_due_employee_lifecycle_transitions',
      'app.employees', p_tenant_id, 'failure',
      'cyclic_reporting_line or invalid org unit detected during maintenance sweep -- transition(s) left unactivated; app.employees remains at its prior value for the affected employee(s) until the conflict is resolved and the sweep is retried',
      null, jsonb_build_object('skipped_count', v_skipped, 'skipped_version_ids', to_jsonb(v_skipped_ids))
    );
  end if;

  return v_count;
end;
$$;

comment on function app.activate_due_employee_lifecycle_transitions is
  'ISS-2026-065 closure (decision 7): sweeps app.employee_lifecycle_versions rows whose effective_start_date has arrived but which are still status=''scheduled'', and activates them -- mirrors app.activate_due_employee_position_assignments (HRT-275) exactly, including its own "skip a cyclic row, disclose via a failure audit event, never abort the whole sweep" discipline. HRS:Override-gated, idempotent, NOT wired to any live scheduler (no pg_cron or equivalent exists anywhere in this repository -- ISS-2026-015''s own standing, disclosed gap) -- disclosed as NOT_RUN in docs/build-log/phase-07/HRT-ISS-065-CLOSURE.md, callable on demand today. Returns the count of rows genuinely activated.';

-- ===========================================================================
-- 6. RLS + grants.
-- ===========================================================================

-- ERR-2026-004 / the standing per-migration convention since PLT-118: PostgreSQL
-- grants EXECUTE to PUBLIC on every function by default at creation time. This
-- migration both DROPs+CREATEs 7 existing functions (a new function object each
-- time -- CREATE OR REPLACE cannot be used for a signature change) and CREATEs 4
-- genuinely new ones (app.record_employee_lifecycle_version, app.employee_
-- lifecycle_version_audit_projection, app.get_employee_lifecycle_as_of, app.
-- activate_due_employee_lifecycle_transitions) -- every one of those 11 function
-- objects would otherwise silently carry the implicit PUBLIC grant, regardless of
-- this schema's own ALTER DEFAULT PRIVILEGES statement (20260717095000), exactly
-- mirroring the established, verified-live precedent
-- (20260730810000_harden_procurement_approval_currency_normalization.sql's own
-- header: "a freshly CREATEd function (post DROP) again carries the default
-- PUBLIC execute grant this schema's own ALTER DEFAULT PRIVILEGES revoke only
-- covered for functions that existed when IT ran"). Verified live in this
-- checkpoint's own smoke-test iteration, not assumed: without this statement,
-- `has_function_privilege('anon', 'app.create_employee_draft(...)', 'EXECUTE')`
-- returned true.
revoke execute on all functions in schema app from public;

alter table app.employee_lifecycle_versions enable row level security;

create policy employee_lifecycle_versions_select_scoped on app.employee_lifecycle_versions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- decided_reason is classified restricted (HRS_REGISTRY, this migration's own
-- registry.ts addition) -- column-restricted from `authenticated` at the grant
-- layer from creation, mirroring app.employees'' own established pattern (never
-- needing a later "raw table reason column grant sweep" fix, decision 6/1).
-- Every other column here is the SAME non-sensitive shape app.employee_audit_
-- projection/app.employee_position_assignment_audit_projection already treat as
-- safe (lifecycle_status, org/position/manager ids, dates, status metadata).
grant select (
  id, tenant_id, master_record_id, lifecycle_status, employment_type,
  company_org_unit_id, branch_org_unit_id, department_org_unit_id, position_title, manager_employee_id,
  hire_date, probation_end_date, employment_end_date, effective_start_date, effective_end_date,
  status, change_reason, decided_by, decided_at, previous_version_id, materialized_at,
  record_version, created_by, created_at, updated_at
) on app.employee_lifecycle_versions to authenticated;
grant select on app.employee_lifecycle_versions to service_role;
grant insert, update on app.employee_lifecycle_versions to service_role;

grant execute on function app.employee_lifecycle_version_audit_projection(app.employee_lifecycle_versions) to service_role;
grant execute on function app.record_employee_lifecycle_version(uuid, uuid, text, text, uuid, uuid, uuid, text, uuid, date, date, date, date, text, text, boolean, text) to service_role;

grant execute on function app.create_employee_draft(uuid, text, text, text, text, text, text, date, text, date, uuid, uuid, uuid, text, uuid, uuid, text, text, text, uuid, text, date, text) to authenticated, service_role;
grant execute on function app.update_employee_draft(uuid, integer, text, text, text, text, text, text, date, text, date, date, uuid, uuid, uuid, text, uuid, uuid, text, date, text) to authenticated, service_role;
grant execute on function app.suspend_employee(uuid, integer, text, uuid, text, date) to authenticated, service_role;
grant execute on function app.reactivate_employee(uuid, integer, uuid, text, date, text) to authenticated, service_role;
grant execute on function app.terminate_employee(uuid, integer, text, date, uuid, text, date) to authenticated, service_role;
grant execute on function app.archive_employee_profile(uuid, integer, text, uuid, text, date) to authenticated, service_role;
grant execute on function app.transfer_employee(uuid, integer, uuid, uuid, uuid, text, uuid, text, uuid, text, date) to authenticated, service_role;

grant execute on function app.get_employee_lifecycle_as_of(uuid, uuid, date) to authenticated, service_role;
grant execute on function app.activate_due_employee_lifecycle_transitions(uuid, uuid, text) to authenticated, service_role;
