-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-009 (Overtime and
-- Timesheet, Prompt 281). Builds requested/actual/eligible/approved overtime
-- and timesheet evidence against app.employees (HRT-274), app.schedule_
-- assignments (HRT-279), app.attendance_sessions (HRT-278) and Operations'
-- app.job_orders/app.shipment_orders (OPS-168/OPS-169) -- never a second
-- employee/schedule/attendance/job root. Consumed next by Prompt 282
-- (Payroll, not yet built) via app.payroll_time_inputs, the one versioned
-- payroll-input handoff this checkpoint emits.
--
-- Design decisions, disclosed rather than left implicit (this build's
-- standing discipline, mirrors every prior HRT checkpoint's own header
-- shape):
--
-- 1. **Requested/actual/eligible/approved are four distinct, never-collapsed
--    columns on the SAME row, not four separate tables.** app.overtime_
--    requests carries requested_minutes (a GENERATED column off the
--    caller's own requested_start_at/requested_end_at, immutable),
--    reconciled_actual_minutes (computed server-side against app.
--    attendance_sessions, decision 4), eligible_minutes (computed
--    server-side from the resolved policy's rounding/cap/threshold rules,
--    decision 6), and approved_minutes (the decider's own final figure,
--    CHECK-constrained <= eligible_minutes, never higher -- decision 7).
--    app.timesheet_entries carries the identical four-column shape for
--    regular time. Business rule (prompt section 24) is satisfied
--    structurally, not merely by convention: no single mutable "hours"
--    column exists anywhere that a later step could silently overwrite the
--    earlier one's own evidence.
--
-- 2. **One policy surface, two consumers.** app.overtime_policies/app.
--    overtime_policy_versions is versioned exactly like app.attendance_
--    policies/app.attendance_policy_versions (HRT-278 decision 3) and
--    app.shift_templates/app.shift_template_versions (HRT-279 decision 1).
--    Its rounding_increment_minutes/rounding_mode govern BOTH overtime
--    eligibility computation AND ordinary timesheet-entry eligibility
--    computation -- one config surface, never a second "timesheet policy"
--    table duplicating the same rounding rule. Named "overtime" (matching
--    the prompt's own vocabulary and this migration's own file name) but
--    its comment says so explicitly, so a future reader is not surprised.
--
-- 3. **Actual-time reconciliation reuses app.attendance_sessions directly,
--    read-only -- no column is ever added to Attendance's own tables, and
--    HRT-278's migration is never touched.** app._reconcile_overtime_
--    request_actual looks up the employee's own attendance_sessions row for
--    the SAME work_date (the real evidence app.record_attendance_clock_
--    event/app._ingest_attendance_event already captured) and computes
--    actual worked minutes from its effective_clock_in_at/effective_clock_
--    out_at -- the SAME governed, correction-aware columns Attendance's own
--    payroll-input approval already trusts. This is why NO second
--    "bind_hris_overtime_to_attendance" migration exists (unlike HRT-279/
--    HRT-280's own additive bindings into Attendance/Shift-Roster): every
--    integration point here is a foreign key plus a read, never a write
--    into another checkpoint's own committed schema -- the lowest-risk
--    integration shape available, disclosed as a deliberate choice, not an
--    oversight of the "if you need a binding migration" allowance.
--
-- 4. **The baseline "how many minutes were actually scheduled" figure
--    prefers app.schedule_assignments' own shift (via app.resolve_
--    effective_schedule_assignment, HRT-279's own single resolution point,
--    reused verbatim -- never a second lookup mechanism, per this task's
--    own mandatory-reading instruction), falling back to the policy's own
--    configured standard_workday_minutes when no roster assignment exists**
--    for a tenant that has not adopted Shift/Roster. Actual overtime minutes
--    = greatest(0, actual worked minutes - baseline minutes - unpaid break
--    minutes).
--
-- 5. **Overtime/timesheet approval is a DIRECT propose (self-or-HRS:Edit)/
--    decide (HRS:Approve) workflow, NOT routed through PLT-123.** Mirrors
--    HRT-278 decision 5's own reasoning exactly (attendance corrections)
--    and HRT-279's own schedule-assignment/swap shape: this is a routine,
--    potentially daily-volume HR workflow that must keep working for a
--    tenant that has never configured PLT-123 approval routing for an
--    unrelated domain. This is the disjoint choice from HRT-280 (Leave),
--    which correctly DOES route through PLT-123 because leave is
--    comparatively rare and balance-affecting -- both are real, live
--    precedents in this same phase; this checkpoint's own volume/stakes
--    profile matches the attendance/shift-roster bucket, not leave's.
--
-- 6. **Rounding, minimum-threshold, daily cap and weekly cap are ALL
--    computed server-side, inside app.decide_overtime_request/app.decide_
--    timesheet_entry, from the resolved policy version -- never accepted
--    as a client-supplied number (section 17 "no client-only calculation
--    authority").** app.round_minutes is the one rounding function every
--    caller uses (nearest/up/down against a configurable increment). The
--    weekly cap check is advisory-lock-serialized (decision 9) against a
--    genuine concurrent-approval race -- the exact class this task's own
--    workflow instructions name explicitly ("concurrency on ... cap
--    enforcement").
--
-- 7. **approved_minutes is CHECK-constrained <= eligible_minutes on both
--    app.overtime_requests and app.timesheet_entries.** A decider may
--    approve LESS than the server-computed eligible figure (a real,
--    disclosed partial-approval authority) but never fabricate MORE --
--    eligible_minutes is the true governed ceiling.
--
-- 8. **Operations job/shipment references are authorized independently,
--    minimally, and never leak Operations data this capability is not
--    scoped to reveal (section 26).** app._validate_overtime_timesheet_
--    operations_reference checks ONLY that a supplied app.job_orders/app.
--    shipment_orders id exists in the caller's OWN tenant -- no OPS
--    permission is invented, no financial/customer/quotation column is
--    ever selected by this migration's own functions, and every read RPC
--    below projects job_number/shipment_number only (never revenue_
--    snapshot, customer_snapshot, or any other Operations-owned field).
--    Mirrors HRT-279 decision 12's own "aggregate headcount only, no new
--    cross-domain permission invented" reasoning, applied here to a
--    reference id instead of a headcount.
--
-- 9. **Weekly-cap enforcement is pg_advisory_xact_lock-serialized, keyed on
--    (tenant_id, employee_id, iso_year_week) -- the identical structural
--    shape app.decide_leave_request (HRT-280 decision 4) already uses for
--    its own no-single-row-to-lock balance race.** Two concurrent decide
--    calls for the SAME employee's SAME ISO week can never both compute
--    "headroom available" against a stale read and jointly exceed the
--    weekly cap -- live-tested with two real, concurrent psql processes
--    (build log).
--
-- 10. **Locked/approved records change only through a governed reopen, NEVER
--     a silent overwrite (section 24, acceptance criteria).** app.
--     timesheet_periods has its own status gate (open/locked); app.
--     timesheet_period_summaries has its own per-employee status gate
--     (pending/submitted/approved/rejected); reopening either requires
--     HRS:Override and a non-empty reason, and is recorded (reopen_count/
--     last_reopened_by/at/reason). Reopening the PERIOD unlocks the date
--     range for new submissions but does NOT silently revert an already-
--     approved employee summary -- that is its own, separately governed
--     app.reopen_timesheet_period_summary action. app.payroll_time_inputs
--     is genuinely append-only/versioned (decision 11) -- a correction after
--     a payroll input was already generated produces a NEW version row,
--     the prior one flipped to 'superseded', never an UPDATE of the
--     original figures.
--
-- 11. **The payroll-input handoff is the one place this checkpoint is
--     deliberately MORE conservative than its own established idempotency-
--     key convention (C-01), not less: app.payroll_time_inputs has no
--     caller-supplied idempotency key at all.** app._generate_payroll_time_
--     input recomputes the period summary fresh, compares the resulting
--     totals against the CURRENT active version's own totals, and returns
--     the existing active row UNCHANGED when they match -- true content-
--     based idempotency, immune by construction to the exact "idempotency
--     replay matched the key but never verified the target" defect class
--     (taxonomy C-01) that recurred three times earlier in this build,
--     because there is no caller-supplied replay key here to mis-compare
--     against. A version is created ONLY when the recomputed totals
--     genuinely differ from the current active version.
--
-- 12. **Pay rate/value fields are withheld from anyone without payroll
--     permission -- realized here as: no rate/multiplier/currency/amount
--     column exists ANYWHERE in this migration's schema (business rule
--     "Payroll amount/rate calculation belongs to payroll; this capability
--     emits approved time/classification inputs").** app.payroll_time_
--     inputs carries only integer minute columns split by classification
--     (weekday/weekend/holiday) -- zero money. As the one deliberately more
--     conservative read-access decision this checkpoint makes, app.
--     payroll_time_inputs' own RLS/read RPCs are gated on the PROTECTED
--     'HRS:View payroll' permission (not the broader plain 'HRS:View') for
--     any non-self caller -- the literal, narrowest reading of "withheld
--     unless payroll permission," applied even though no money value is
--     actually present, since this artifact is Payroll's own structured
--     input and its classification split is exactly the shape a rate would
--     be multiplied against.
--
-- 13. **Break-time deduction is a real, configurable, per-record field
--     (unpaid_break_minutes on both app.overtime_requests and app.
--     timesheet_entries), closing the exact reservation HRT-278 decision 1
--     named this checkpoint as the plausible owner of** ("Break-deduction
--     rules are a natural, additive extension for a future checkpoint, most
--     plausibly Prompt 281"). This checkpoint does NOT add a break/rest
--     attendance EVENT type to app.attendance_events (that table's
--     event_type CHECK constraint is untouched, per decision 3 above) --
--     only the DEDUCTION RULE itself, entered directly on the overtime/
--     timesheet record, is in scope here. Disclosed, not silently narrowed.
--
-- 14. **Multi-job timesheet allocation is real: app.timesheet_entries carries
--     NO uniqueness constraint on (employee_id, work_date)** (unlike app.
--     overtime_requests, which IS bounded to one active request per workday
--     -- decision, mirrors app.attendance_sessions/app.schedule_
--     assignments' own identical V1 bound). One employee may log several
--     timesheet_entries for the SAME work_date across different job_order_
--     id/shipment_order_id references, satisfying section 22's own named
--     "multi-job allocation" alternative flow.
--
-- 15. **Timesheet-entry reconciliation against Attendance is informational,
--     not a hard approval block (disclosed V1 scope boundary, distinct from
--     overtime's own harder gate -- decision 16).** A day's attendance
--     evidence rarely lines up minute-for-minute against several manually
--     allocated job/shipment entries, and this repository has no field-
--     device clock-in requirement for every timesheet-eligible role.
--     app._reconcile_timesheet_day sets reconciliation_status/reconciled_
--     day_actual_minutes on every entry for that employee-workday as a
--     visible signal; app.decide_timesheet_entry never blocks on it.
--
-- 16. **Overtime approval DOES hard-block on missing/mismatched attendance
--     evidence unless the decider also holds HRS:Override** (exception flow,
--     section 23: "Block ... attendance mismatch"). This is the one place
--     overtime and timesheet decide functions genuinely diverge in
--     strictness, and the divergence is disclosed here rather than silently
--     inconsistent.
--
-- 17. **RBAC.** Zero new app.permissions rows -- the twelve HRS actions
--     already seeded (View/Create/Edit/Delete/Approve/Export/View payroll/
--     View personal data/Reject/Import/Download/Override) cover every write
--     this checkpoint performs. Blast-radius-matched, not surface-category-
--     matched (HRT-277's own worst finding, designed against from the
--     start): period/summary REOPEN and the coverage-mismatch overtime
--     override both require HRS:Override, never merely HRS:Edit/Approve;
--     ordinary decide is HRS:Approve; ordinary authoring/submission is
--     HRS:Edit or self.
--
-- 18. **Self-approval is blocked on every governed decision** (taxonomy
--     C-18): decide_overtime_request, decide_timesheet_entry, approve_
--     timesheet_period_summary AND reject_timesheet_period_summary all
--     block an actor deciding their own request/entry/summary even when
--     they also hold the gating permission -- designed in from the start
--     (and, for the reject counterpart, closed by this checkpoint's own
--     Tier B self-review before commit -- the approve/reject split for
--     period summaries had left the block on approve only), mirroring
--     HRT-278/279/280's own identical, by-now-established control.
--
-- 19. **"Revision/resubmission" (spec section 22) is create-new, never
--     in-place edit, once a request/entry has been decided.** A rejected
--     app.overtime_requests / app.timesheet_entries row is a terminal
--     leaf -- submit_overtime_request/submit_timesheet_entry/update_
--     timesheet_entry_draft all require status='draft', with no path back
--     from 'rejected'. This is deliberate, not an oversight: decision 1's
--     own "distinct, versioned, traceable, never collapsed into one
--     mutable value" principle applies to a DECIDED record just as much as
--     an approved one, so a rejected request's content and its decided_
--     reason/decided_by lineage are never silently rewritten in place.
--     The real resubmission path is: create a brand-new request/entry for
--     the same work_date (the active-slot unique index on app.overtime_
--     requests excludes 'rejected' from its scope, and app.timesheet_
--     entries carries no such uniqueness at all -- decision 14) -- live-
--     verified against this checkpoint's own fixture before commit. The
--     PERIOD-SUMMARY layer (a coarser, per-employee-per-period rollup, not
--     an individual request/entry) is the one place true in-place
--     resubmission exists (app.timesheet_period_summaries: 'rejected' ->
--     app.submit_timesheet_period_summary re-submits the SAME row), since
--     a summary is a recomputed projection over its constituent entries/
--     requests rather than an independent source-of-truth record.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
-- its own explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM
-- PUBLIC statement before its final grants, the standing per-migration
-- convention since PLT-118.

create extension if not exists btree_gist;

-- ===========================================================================
-- 1. app.overtime_policies -- scope pointer (tenant-wide when org_unit_id is
--    null, or scoped to one org_unit node otherwise -- decision 2).
-- ===========================================================================

create table app.overtime_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid references app.org_units (id),
  name text not null,
  status text not null default 'draft',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint overtime_policies_name_check check (length(trim(name)) > 0),
  constraint overtime_policies_status_check check (status in ('draft', 'published', 'archived'))
);

comment on table app.overtime_policies is
  'HRT-281 (decision 2): tenant- or org_unit-scoped overtime/timesheet policy scope pointer. org_unit_id null = tenant-wide fallback; non-null = binds to one app.org_units node. Governs BOTH overtime eligibility rounding/caps AND ordinary timesheet-entry rounding -- one config surface, never two.';

create unique index overtime_policies_tenant_org_unit_unique on app.overtime_policies (tenant_id, org_unit_id) where org_unit_id is not null;
create unique index overtime_policies_tenant_wide_unique on app.overtime_policies (tenant_id) where org_unit_id is null;
create index overtime_policies_tenant_status_idx on app.overtime_policies (tenant_id, status);

-- ===========================================================================
-- 2. app.overtime_policy_versions -- the actual effective-dated ruleset.
-- ===========================================================================

create table app.overtime_policy_versions (
  id uuid primary key default gen_random_uuid(),
  policy_id uuid not null references app.overtime_policies (id),
  tenant_id uuid not null references app.tenants (id),
  version_number integer not null,
  status text not null default 'draft',
  effective_from date not null,
  rounding_increment_minutes integer not null default 15,
  rounding_mode text not null default 'nearest',
  min_overtime_minutes integer not null default 30,
  daily_overtime_cap_minutes integer,
  weekly_overtime_cap_minutes integer,
  standard_workday_minutes integer not null default 480,
  default_break_deduction_minutes integer not null default 0,
  requires_pre_approval boolean not null default true,
  published_at timestamptz,
  published_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint overtime_policy_versions_status_check check (status in ('draft', 'published', 'superseded')),
  constraint overtime_policy_versions_rounding_increment_check check (rounding_increment_minutes > 0 and rounding_increment_minutes <= 60),
  constraint overtime_policy_versions_rounding_mode_check check (rounding_mode in ('nearest', 'up', 'down')),
  constraint overtime_policy_versions_min_overtime_check check (min_overtime_minutes >= 0),
  constraint overtime_policy_versions_daily_cap_check check (daily_overtime_cap_minutes is null or daily_overtime_cap_minutes > 0),
  constraint overtime_policy_versions_weekly_cap_check check (weekly_overtime_cap_minutes is null or weekly_overtime_cap_minutes > 0),
  constraint overtime_policy_versions_cap_order_check check (
    daily_overtime_cap_minutes is null or weekly_overtime_cap_minutes is null or weekly_overtime_cap_minutes >= daily_overtime_cap_minutes
  ),
  constraint overtime_policy_versions_standard_workday_check check (standard_workday_minutes > 0 and standard_workday_minutes <= 1440),
  constraint overtime_policy_versions_break_deduction_check check (default_break_deduction_minutes >= 0),
  constraint overtime_policy_versions_published_shape_check check (
    (status <> 'published') or (published_at is not null and published_by is not null)
  ),
  constraint overtime_policy_versions_policy_effective_unique unique (policy_id, effective_from)
);

comment on table app.overtime_policy_versions is
  'HRT-281 (decision 2/6): effective-dated overtime/timesheet ruleset. rounding_increment_minutes/rounding_mode/min_overtime_minutes/daily_overtime_cap_minutes/weekly_overtime_cap_minutes/standard_workday_minutes/default_break_deduction_minutes are ALL applied server-side only (app.round_minutes, app.decide_overtime_request, app.decide_timesheet_entry) -- never accepted as a client-supplied figure (section 17).';

create index overtime_policy_versions_policy_idx on app.overtime_policy_versions (policy_id, status, effective_from desc);

-- Branch-scoped-over-tenant-wide, latest-effective-published-version
-- resolution (decision 2), mirroring app.resolve_effective_attendance_
-- policy_version (HRT-278) exactly.
create function app.resolve_effective_overtime_policy_version(p_tenant_id uuid, p_branch_org_unit_id uuid, p_as_of_date date)
returns setof app.overtime_policy_versions
language sql
stable
as $$
  select pv.*
  from app.overtime_policy_versions pv
  join app.overtime_policies p on p.id = pv.policy_id
  where p.tenant_id = p_tenant_id
    and pv.status = 'published'
    and pv.effective_from <= p_as_of_date
    and (p.org_unit_id is null or p.org_unit_id = p_branch_org_unit_id)
  order by (p.org_unit_id is not null) desc, pv.effective_from desc
  limit 1;
$$;

comment on function app.resolve_effective_overtime_policy_version is
  'HRT-281: the single effective-policy resolution point every overtime/timesheet write RPC below uses. Zero rows = "no eligible policy" (section 23 exception flow).';

-- ===========================================================================
-- 3. Shared rounding/classification helpers (decision 6).
-- ===========================================================================

create function app.round_minutes(p_minutes numeric, p_increment integer, p_mode text)
returns integer
language sql
immutable
as $$
  select case
    when p_minutes is null then null
    when p_increment is null or p_increment <= 0 then round(p_minutes)::integer
    when p_mode = 'up' then (ceil(p_minutes / p_increment::numeric) * p_increment)::integer
    when p_mode = 'down' then (floor(p_minutes / p_increment::numeric) * p_increment)::integer
    else (round(p_minutes / p_increment::numeric) * p_increment)::integer
  end;
$$;

comment on function app.round_minutes is
  'HRT-281 (decision 6): the ONE rounding function every overtime/timesheet eligibility computation uses -- nearest/up/down against a configurable increment. Never reimplemented inline.';

-- Reuses app.roster_holidays (HRT-279) directly, read-only -- never a second
-- holiday calendar.
create function app.classify_overtime_work_date(p_tenant_id uuid, p_org_unit_id uuid, p_work_date date)
returns text
language sql
stable
as $$
  select case
    when exists (
      select 1 from app.roster_holidays h
      where h.tenant_id = p_tenant_id and h.holiday_date = p_work_date and h.status = 'active' and not h.is_working_day
        and (h.org_unit_id is null or h.org_unit_id = p_org_unit_id)
    ) then 'holiday'
    when extract(dow from p_work_date) in (0, 6) then 'weekend'
    else 'weekday'
  end;
$$;

comment on function app.classify_overtime_work_date is
  'HRT-281: reuses app.roster_holidays (HRT-279) directly -- never a second holiday calendar. is_working_day=true (an explicit tenant override) never classifies as holiday.';

-- Decision 8: minimal, existence-only, tenant-scoped validation -- never
-- selects a financial/customer/quotation column from either table.
create function app._validate_overtime_timesheet_operations_reference(p_tenant_id uuid, p_job_order_id uuid, p_shipment_order_id uuid)
returns void
language plpgsql
stable
as $$
begin
  if p_job_order_id is not null and not exists (select 1 from app.job_orders where id = p_job_order_id and tenant_id = p_tenant_id) then
    raise exception 'job_order_not_found: % is not a valid job order for this tenant', p_job_order_id using errcode = 'no_data_found';
  end if;
  if p_shipment_order_id is not null and not exists (select 1 from app.shipment_orders where id = p_shipment_order_id and tenant_id = p_tenant_id) then
    raise exception 'shipment_order_not_found: % is not a valid shipment order for this tenant', p_shipment_order_id using errcode = 'no_data_found';
  end if;
end;
$$;

-- ===========================================================================
-- 4. app.overtime_requests -- requested/actual/eligible/approved overtime
--    evidence (decision 1), one active request per employee-workday
--    (mirrors app.attendance_sessions/app.schedule_assignments' own V1
--    bound).
-- ===========================================================================

create table app.overtime_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  work_date date not null,
  request_type text not null default 'planned',
  requested_start_at timestamptz not null,
  requested_end_at timestamptz not null,
  requested_minutes integer generated always as (greatest(0, round(extract(epoch from (requested_end_at - requested_start_at)) / 60.0))::integer) stored,
  unpaid_break_minutes integer not null default 0,
  reason text not null,
  schedule_assignment_id uuid references app.schedule_assignments (id),
  job_order_id uuid references app.job_orders (id),
  shipment_order_id uuid references app.shipment_orders (id),
  status text not null default 'draft',
  requested_by_auth_user_id uuid not null,
  requested_by text,
  policy_version_id uuid references app.overtime_policy_versions (id),
  attendance_session_id uuid references app.attendance_sessions (id),
  reconciliation_status text not null default 'not_reconciled',
  reconciled_actual_minutes integer,
  eligible_minutes integer,
  eligible_classification text,
  approved_minutes integer,
  decided_by text,
  decided_at timestamptz,
  decided_reason text,
  cancel_reason text,
  payroll_input_status text not null default 'pending',
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint overtime_requests_request_type_check check (request_type in ('planned', 'emergency_after_the_fact')),
  constraint overtime_requests_reason_check check (length(trim(reason)) > 0),
  constraint overtime_requests_time_order_check check (requested_end_at > requested_start_at),
  constraint overtime_requests_break_check check (unpaid_break_minutes >= 0),
  constraint overtime_requests_status_check check (status in ('draft', 'pending_approval', 'approved', 'rejected', 'cancelled')),
  constraint overtime_requests_reconciliation_status_check check (reconciliation_status in ('not_reconciled', 'matched', 'mismatch', 'no_attendance')),
  constraint overtime_requests_classification_check check (eligible_classification is null or eligible_classification in ('weekday', 'weekend', 'holiday')),
  constraint overtime_requests_classification_shape_check check ((eligible_minutes is null) = (eligible_classification is null)),
  constraint overtime_requests_payroll_status_check check (payroll_input_status in ('pending', 'approved')),
  constraint overtime_requests_eligible_nonneg_check check (eligible_minutes is null or eligible_minutes >= 0),
  constraint overtime_requests_approved_nonneg_check check (approved_minutes is null or approved_minutes >= 0),
  constraint overtime_requests_approved_le_eligible_check check (approved_minutes is null or eligible_minutes is null or approved_minutes <= eligible_minutes),
  constraint overtime_requests_decided_shape_check check (
    (status in ('draft', 'pending_approval') and decided_at is null and decided_by is null)
    or (status = 'cancelled')
    or (status in ('approved', 'rejected') and decided_at is not null and decided_by is not null and decided_reason is not null and length(trim(decided_reason)) > 0)
  ),
  constraint overtime_requests_cancel_reason_check check (status <> 'cancelled' or (cancel_reason is not null and length(trim(cancel_reason)) > 0))
);

comment on table app.overtime_requests is
  'HRT-281 (decision 1): requested_minutes (generated, immutable) vs reconciled_actual_minutes (app._reconcile_overtime_request_actual, against app.attendance_sessions) vs eligible_minutes (app.decide_overtime_request, server-computed from the resolved policy) vs approved_minutes (the decider''s own final figure, CHECK <= eligible_minutes, decision 7) are four distinct, separately-lineaged columns, never collapsed.';

create unique index overtime_requests_employee_workdate_active_unique on app.overtime_requests (tenant_id, employee_id, work_date) where status in ('draft', 'pending_approval', 'approved');
create index overtime_requests_tenant_status_idx on app.overtime_requests (tenant_id, status);
create index overtime_requests_tenant_employee_workdate_idx on app.overtime_requests (tenant_id, employee_id, work_date desc);
create unique index overtime_requests_idempotency_unique on app.overtime_requests (tenant_id, employee_id, idempotency_key) where idempotency_key is not null;
create index overtime_requests_tenant_payroll_idx on app.overtime_requests (tenant_id, payroll_input_status);

-- ===========================================================================
-- 5. app.timesheet_periods -- period definition and lock gate (decision 10).
-- ===========================================================================

create table app.timesheet_periods (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid references app.org_units (id),
  code text not null,
  period_start date not null,
  period_end date not null,
  status text not null default 'open',
  locked_by text,
  locked_at timestamptz,
  reopen_count integer not null default 0,
  last_reopened_by text,
  last_reopened_at timestamptz,
  last_reopen_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint timesheet_periods_code_check check (length(trim(code)) > 0),
  constraint timesheet_periods_date_order_check check (period_end >= period_start),
  constraint timesheet_periods_status_check check (status in ('open', 'locked')),
  constraint timesheet_periods_locked_shape_check check ((status <> 'locked') or (locked_at is not null and locked_by is not null)),
  constraint timesheet_periods_reopen_shape_check check (reopen_count = 0 or (last_reopened_by is not null and last_reopened_at is not null and last_reopen_reason is not null)),
  constraint timesheet_periods_tenant_org_code_unique unique (tenant_id, org_unit_id, code)
);

comment on table app.timesheet_periods is
  'HRT-281 (decision 10): period definition + whole-period lock gate. Overlap across periods of the SAME scope (tenant-wide, or the SAME org_unit_id) is prevented by timesheet_periods_no_overlap below -- a branch-scoped period and a tenant-wide period MAY legitimately cover the same date range (branch-scoped wins resolution, mirrors app.resolve_effective_attendance_policy_version''s own precedence).';

alter table app.timesheet_periods add constraint timesheet_periods_no_overlap
  exclude using gist (
    tenant_id with =,
    coalesce(org_unit_id, '00000000-0000-0000-0000-000000000000'::uuid) with =,
    daterange(period_start, period_end, '[]') with &&
  );

create index timesheet_periods_tenant_range_idx on app.timesheet_periods (tenant_id, period_start desc);

-- Branch-scoped-over-tenant-wide period resolution, mirroring decision 2's
-- own policy-resolution shape.
create function app.resolve_effective_timesheet_period(p_tenant_id uuid, p_branch_org_unit_id uuid, p_work_date date)
returns setof app.timesheet_periods
language sql
stable
as $$
  select tp.*
  from app.timesheet_periods tp
  where tp.tenant_id = p_tenant_id
    and tp.period_start <= p_work_date and tp.period_end >= p_work_date
    and (tp.org_unit_id is null or tp.org_unit_id = p_branch_org_unit_id)
  order by (tp.org_unit_id is not null) desc
  limit 1;
$$;

create function app.is_timesheet_period_locked(p_tenant_id uuid, p_branch_org_unit_id uuid, p_work_date date)
returns boolean
language sql
stable
as $$
  select coalesce((select tp.status = 'locked' from app.resolve_effective_timesheet_period(p_tenant_id, p_branch_org_unit_id, p_work_date) tp limit 1), false);
$$;

comment on function app.is_timesheet_period_locked is
  'HRT-281 (decision 10): the one lock-gate check app.submit_overtime_request/app.decide_overtime_request/app.submit_timesheet_entry/app.decide_timesheet_entry all call before mutating a locked period''s own date range.';

-- ===========================================================================
-- 6. app.timesheet_entries -- requested/actual/eligible/approved regular
--    time evidence against an eligible schedule/job/shipment reference
--    (decisions 1, 8, 14).
-- ===========================================================================

create table app.timesheet_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  work_date date not null,
  entry_minutes integer not null,
  unpaid_break_minutes integer not null default 0,
  job_order_id uuid references app.job_orders (id),
  shipment_order_id uuid references app.shipment_orders (id),
  schedule_assignment_id uuid references app.schedule_assignments (id),
  notes text,
  status text not null default 'draft',
  source text not null default 'manual',
  requested_by_auth_user_id uuid not null,
  requested_by text,
  policy_version_id uuid references app.overtime_policy_versions (id),
  attendance_session_id uuid references app.attendance_sessions (id),
  reconciliation_status text not null default 'not_reconciled',
  reconciled_day_actual_minutes integer,
  eligible_minutes integer,
  approved_minutes integer,
  decided_by text,
  decided_at timestamptz,
  decided_reason text,
  cancel_reason text,
  payroll_input_status text not null default 'pending',
  source_import_staging_row_id uuid references app.import_staging_rows (id),
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint timesheet_entries_minutes_check check (entry_minutes > 0 and entry_minutes <= 1440),
  constraint timesheet_entries_break_check check (unpaid_break_minutes >= 0),
  constraint timesheet_entries_status_check check (status in ('draft', 'pending_approval', 'approved', 'rejected', 'cancelled')),
  constraint timesheet_entries_source_check check (source in ('manual', 'import', 'attendance_derived')),
  constraint timesheet_entries_reconciliation_status_check check (reconciliation_status in ('not_reconciled', 'matched', 'mismatch', 'no_attendance')),
  constraint timesheet_entries_payroll_status_check check (payroll_input_status in ('pending', 'approved')),
  constraint timesheet_entries_eligible_nonneg_check check (eligible_minutes is null or eligible_minutes >= 0),
  constraint timesheet_entries_approved_nonneg_check check (approved_minutes is null or approved_minutes >= 0),
  constraint timesheet_entries_approved_le_eligible_check check (approved_minutes is null or eligible_minutes is null or approved_minutes <= eligible_minutes),
  constraint timesheet_entries_decided_shape_check check (
    (status in ('draft', 'pending_approval') and decided_at is null and decided_by is null)
    or (status = 'cancelled')
    or (status in ('approved', 'rejected') and decided_at is not null and decided_by is not null and decided_reason is not null and length(trim(decided_reason)) > 0)
  ),
  constraint timesheet_entries_cancel_reason_check check (status <> 'cancelled' or (cancel_reason is not null and length(trim(cancel_reason)) > 0))
);

comment on table app.timesheet_entries is
  'HRT-281 (decisions 1, 14): regular-time evidence against an eligible schedule/job/shipment reference. NO uniqueness on (employee_id, work_date) -- multi-job allocation across several rows for the SAME workday is real and supported (decision 14).';

create index timesheet_entries_tenant_employee_workdate_idx on app.timesheet_entries (tenant_id, employee_id, work_date desc);
create index timesheet_entries_tenant_status_idx on app.timesheet_entries (tenant_id, status);
create unique index timesheet_entries_idempotency_unique on app.timesheet_entries (tenant_id, employee_id, idempotency_key) where idempotency_key is not null;
create unique index timesheet_entries_staging_row_unique on app.timesheet_entries (source_import_staging_row_id) where source_import_staging_row_id is not null;
create index timesheet_entries_tenant_payroll_idx on app.timesheet_entries (tenant_id, payroll_input_status);

-- ===========================================================================
-- 7. app.timesheet_period_summaries -- the per (period, employee) approval
--    unit (decision 10) -- what a manager/HR actually approves and locks.
-- ===========================================================================

create table app.timesheet_period_summaries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  timesheet_period_id uuid not null references app.timesheet_periods (id),
  status text not null default 'pending',
  total_regular_minutes integer not null default 0,
  total_overtime_weekday_minutes integer not null default 0,
  total_overtime_weekend_minutes integer not null default 0,
  total_overtime_holiday_minutes integer not null default 0,
  entry_count integer not null default 0,
  overtime_request_count integer not null default 0,
  computed_at timestamptz,
  submitted_by text,
  submitted_at timestamptz,
  decided_by text,
  decided_at timestamptz,
  decided_reason text,
  reopen_count integer not null default 0,
  last_reopened_by text,
  last_reopened_at timestamptz,
  last_reopen_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint timesheet_period_summaries_status_check check (status in ('pending', 'submitted', 'approved', 'rejected')),
  constraint timesheet_period_summaries_minutes_nonneg_check check (
    total_regular_minutes >= 0 and total_overtime_weekday_minutes >= 0 and total_overtime_weekend_minutes >= 0 and total_overtime_holiday_minutes >= 0
  ),
  constraint timesheet_period_summaries_reopen_shape_check check (reopen_count = 0 or (last_reopened_by is not null and last_reopened_at is not null and last_reopen_reason is not null)),
  constraint timesheet_period_summaries_period_employee_unique unique (timesheet_period_id, employee_id)
);

comment on table app.timesheet_period_summaries is
  'HRT-281 (decision 10): the per (period, employee) approval unit -- recomputed fresh (app._compute_timesheet_period_summary) from every app.timesheet_entries/app.overtime_requests row with status=''approved'' in the period''s own date range, on submit AND immediately before approve, so the approved totals are never stale.';

create index timesheet_period_summaries_tenant_status_idx on app.timesheet_period_summaries (tenant_id, status);
create index timesheet_period_summaries_employee_idx on app.timesheet_period_summaries (tenant_id, employee_id);

-- ===========================================================================
-- 8. app.payroll_time_inputs -- the ONE versioned, idempotent payroll-input
--    handoff record (decisions 1, 11, 12). No rate/amount/currency column
--    anywhere -- time and classification only.
-- ===========================================================================

create table app.payroll_time_inputs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  timesheet_period_id uuid not null references app.timesheet_periods (id),
  period_summary_id uuid not null references app.timesheet_period_summaries (id),
  version_number integer not null,
  status text not null default 'active',
  regular_minutes integer not null,
  overtime_weekday_minutes integer not null,
  overtime_weekend_minutes integer not null,
  overtime_holiday_minutes integer not null,
  source_entry_ids uuid[] not null default array[]::uuid[],
  source_overtime_request_ids uuid[] not null default array[]::uuid[],
  idempotency_key text not null,
  superseded_by_id uuid references app.payroll_time_inputs (id),
  generated_by text,
  created_at timestamptz not null default now(),
  constraint payroll_time_inputs_status_check check (status in ('active', 'superseded')),
  constraint payroll_time_inputs_minutes_nonneg_check check (
    regular_minutes >= 0 and overtime_weekday_minutes >= 0 and overtime_weekend_minutes >= 0 and overtime_holiday_minutes >= 0
  ),
  constraint payroll_time_inputs_version_check check (version_number > 0),
  constraint payroll_time_inputs_period_employee_version_unique unique (timesheet_period_id, employee_id, version_number)
);

comment on table app.payroll_time_inputs is
  'HRT-281 (decisions 1, 11, 12): the versioned, idempotent payroll-input handoff Prompt 282 (Payroll) is expected to consume -- time/classification ONLY, zero rate/amount/currency column (decision 12). Genuinely append-only: a correction produces a NEW row (app._generate_payroll_time_input marks the prior active row superseded BEFORE inserting the new one, the exact insert-after-supersede ordering lesson HRT-279''s own self-found defect #2 established), never an UPDATE of the original figures.';

create unique index payroll_time_inputs_active_unique on app.payroll_time_inputs (timesheet_period_id, employee_id) where status = 'active';
create index payroll_time_inputs_tenant_idx on app.payroll_time_inputs (tenant_id, timesheet_period_id);
create unique index payroll_time_inputs_idempotency_unique on app.payroll_time_inputs (tenant_id, employee_id, idempotency_key);

-- ===========================================================================
-- 8b. Touch-row triggers (record_version increment on every UPDATE) --
--     mirrors app.touch_leave_request_row (HRT-280), the established,
--     correct convention for every optimistic-concurrency-guarded table in
--     this phase. One shared function, reused across all six record_
--     version-bearing tables below (identical shape to app.touch_leave_
--     request_row's own reuse across three tables) -- self-found during
--     this checkpoint's own adversarial testing: a first draft omitted this
--     trigger entirely (matching an existing, unrelated gap in HRT-278/279's
--     own already-VERIFIED migrations, out of this checkpoint's allowed-
--     files scope to fix), which would have made every record_version
--     optimistic-lock check in this migration structurally inert -- two
--     sequential updates against the SAME p_expected_version would both
--     silently succeed, never detecting the intervening change. app.
--     payroll_time_inputs deliberately carries NO record_version/trigger --
--     it is genuinely immutable per version (decision 11), never updated
--     after insert except its own status/superseded_by_id supersede step.
-- ===========================================================================

create function app.touch_overtime_timesheet_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger overtime_policies_touch_row before update on app.overtime_policies for each row execute function app.touch_overtime_timesheet_row();
create trigger overtime_policy_versions_touch_row before update on app.overtime_policy_versions for each row execute function app.touch_overtime_timesheet_row();
create trigger overtime_requests_touch_row before update on app.overtime_requests for each row execute function app.touch_overtime_timesheet_row();
create trigger timesheet_periods_touch_row before update on app.timesheet_periods for each row execute function app.touch_overtime_timesheet_row();
create trigger timesheet_entries_touch_row before update on app.timesheet_entries for each row execute function app.touch_overtime_timesheet_row();
create trigger timesheet_period_summaries_touch_row before update on app.timesheet_period_summaries for each row execute function app.touch_overtime_timesheet_row();

-- ===========================================================================
-- 9. Overtime policy authoring RPCs.
-- ===========================================================================

create function app.create_overtime_policy(
  p_tenant_id uuid, p_org_unit_id uuid, p_name text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.overtime_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_policy app.overtime_policies;
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

  insert into app.overtime_policies (tenant_id, org_unit_id, name, created_by)
  values (p_tenant_id, p_org_unit_id, p_name, p_actor_label)
  returning * into v_policy;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_overtime_policy',
    'app.overtime_policies', v_policy.id, 'success', null, null, to_jsonb(v_policy)
  );

  return v_policy;
end;
$$;

create function app.create_overtime_policy_version(
  p_policy_id uuid,
  p_rounding_increment_minutes integer,
  p_rounding_mode text,
  p_min_overtime_minutes integer,
  p_daily_overtime_cap_minutes integer,
  p_weekly_overtime_cap_minutes integer,
  p_standard_workday_minutes integer,
  p_default_break_deduction_minutes integer,
  p_requires_pre_approval boolean,
  p_effective_from date,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.overtime_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_policy app.overtime_policies;
  v_next_version integer;
  v_version app.overtime_policy_versions;
begin
  select * into v_policy from app.overtime_policies where id = p_policy_id;
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

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.overtime_policy_versions where policy_id = p_policy_id;

  insert into app.overtime_policy_versions (
    policy_id, tenant_id, version_number, effective_from, rounding_increment_minutes, rounding_mode, min_overtime_minutes,
    daily_overtime_cap_minutes, weekly_overtime_cap_minutes, standard_workday_minutes, default_break_deduction_minutes,
    requires_pre_approval, created_by
  ) values (
    p_policy_id, v_policy.tenant_id, v_next_version, p_effective_from, coalesce(p_rounding_increment_minutes, 15), coalesce(p_rounding_mode, 'nearest'),
    coalesce(p_min_overtime_minutes, 30), p_daily_overtime_cap_minutes, p_weekly_overtime_cap_minutes, coalesce(p_standard_workday_minutes, 480),
    coalesce(p_default_break_deduction_minutes, 0), coalesce(p_requires_pre_approval, true), p_actor_label
  ) returning * into v_version;

  perform app.capture_audit_event(
    v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_overtime_policy_version',
    'app.overtime_policy_versions', v_version.id, 'success', null, null, jsonb_build_object('policy_id', p_policy_id, 'version_number', v_next_version)
  );

  return v_version;
end;
$$;

create function app.publish_overtime_policy_version(
  p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.overtime_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.overtime_policy_versions;
begin
  select * into v_version from app.overtime_policy_versions where id = p_version_id for update;
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

  update app.overtime_policy_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: policy version % target row was concurrently modified (expected version %)', p_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.overtime_policies set status = 'published' where id = v_version.policy_id and status = 'draft';

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_overtime_policy_version',
    'app.overtime_policy_versions', p_version_id, 'success', null, null, jsonb_build_object('effective_from', v_version.effective_from)
  );

  return v_version;
end;
$$;

-- ===========================================================================
-- 10. Overtime request: shared internal engine (no authority check of its
--     own -- callers below establish authority first, mirroring app._
--     transition_employee_leave_status''s (HRT-280 Tier C fix) own
--     documented "shared engine, gated wrappers" convention, applied here
--     from the start rather than found as a defect later) plus its two
--     gated entry points (decision 1/17).
-- ===========================================================================

create function app._create_overtime_request(
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
  -- never the key alone.
  if p_idempotency_key is not null then
    select * into v_existing from app.overtime_requests where tenant_id = p_employee.tenant_id and employee_id = p_employee.master_record_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.request_type = p_request_type and v_existing.requested_start_at = p_requested_start_at and v_existing.requested_end_at = p_requested_end_at then
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

comment on function app._create_overtime_request is
  'HRT-281 (decision 5/17): internal engine, no authority check of its own -- app.create_overtime_request (self) and app.create_overtime_request_for_employee (HRS:Edit) both establish authority BEFORE calling this. Work_date reuses app.resolve_attendance_workday (HRT-278) via the effective attendance policy when one exists, falling back to a plain UTC date otherwise -- never a second, inconsistent day-bucketing rule.';

create function app.create_overtime_request(
  p_tenant_id uuid,
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
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  return app._create_overtime_request(
    v_self, p_request_type, p_requested_start_at, p_requested_end_at, p_unpaid_break_minutes, p_reason,
    p_schedule_assignment_id, p_job_order_id, p_shipment_order_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.create_overtime_request is
  'HRT-281 (decision 5): self-only -- NO p_employee_id parameter exists, the acting employee is resolved exclusively from the caller''s own validated session identity (app.get_self_employee), mirroring app.record_attendance_clock_event''s own established anti-spoofing shape.';

create function app.create_overtime_request_for_employee(
  p_tenant_id uuid,
  p_employee_id uuid,
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
  v_decision app.rbac_decision;
  v_employee app.employees;
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

  return app._create_overtime_request(
    v_employee, p_request_type, p_requested_start_at, p_requested_end_at, p_unpaid_break_minutes, p_reason,
    p_schedule_assignment_id, p_job_order_id, p_shipment_order_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.create_overtime_request_for_employee is
  'HRT-281: HRS:Edit-gated, explicit target employee -- the "explicit HR authority" half of the self/HR split every prior HRT self-service capability establishes.';

create function app.submit_overtime_request(
  p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text
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
  if not v_is_self then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: overtime request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'draft' then
    raise exception 'invalid_transition: overtime request % is %, only a draft may be submitted', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = v_request.employee_id;
  if app.is_timesheet_period_locked(v_request.tenant_id, v_employee.branch_org_unit_id, v_request.work_date) then
    raise exception 'timesheet_period_locked: the period covering % is locked -- ask HR to reopen it first', v_request.work_date
      using errcode = 'check_violation';
  end if;

  -- Best-effort reconciliation at submit time -- informational only here
  -- (evidence often does not exist yet for a genuinely planned, pre-approval
  -- request); the AUTHORITATIVE reconciliation runs again inside app.decide_
  -- overtime_request (decision 3). The reconcile call itself is a real
  -- UPDATE on this SAME row, so it advances record_version via app.touch_
  -- overtime_timesheet_row -- the terminal UPDATE below re-reads the
  -- CURRENT version (never the caller's own, now-stale, p_expected_version)
  -- for its own guard, since the row lock held since the top SELECT ... FOR
  -- UPDATE already makes this safe (no external process could have raced
  -- in between): self-found during this checkpoint's own adversarial
  -- testing -- an early draft used p_expected_version here and every
  -- submit unconditionally raised a false stale_version.
  v_request := app._reconcile_overtime_request_actual(p_request_id);

  update app.overtime_requests
  set status = 'pending_approval'
  where id = p_request_id and record_version = v_request.record_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: overtime request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_overtime_request',
    'app.overtime_requests', p_request_id, 'success', null, null, '{}'::jsonb
  );

  return v_request;
end;
$$;

-- ===========================================================================
-- 11. Actual-time reconciliation against Attendance (decision 3).
-- ===========================================================================

create function app._reconcile_overtime_request_actual(p_request_id uuid)
returns app.overtime_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.overtime_requests;
  v_session app.attendance_sessions;
  v_policy app.overtime_policy_versions;
  v_baseline_minutes integer;
  v_actual_total_minutes numeric;
  v_actual_overtime_minutes integer;
  v_status text;
  v_tolerance integer;
begin
  select * into v_request from app.overtime_requests where id = p_request_id for update;
  if not found then
    raise exception 'overtime_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  select * into v_session from app.attendance_sessions where tenant_id = v_request.tenant_id and employee_id = v_request.employee_id and work_date = v_request.work_date;

  -- v_policy.id is checked directly (never the bare FOUND special variable,
  -- which the immediately preceding SELECT into v_session would already
  -- have overwritten) -- the exact class HRT-279's own self-found defect #3
  -- established as a live hazard.
  select * into v_policy from app.overtime_policy_versions where id = v_request.policy_version_id;

  if v_session.id is null or v_session.status is distinct from 'closed' then
    update app.overtime_requests
    set reconciliation_status = 'no_attendance', reconciled_actual_minutes = null, attendance_session_id = v_session.id
    where id = p_request_id
    returning * into v_request;
    return v_request;
  end if;

  -- Baseline preference: the employee's own published schedule assignment
  -- (HRT-279, decision 4) over the policy's own configured standard_
  -- workday_minutes fallback.
  select stv.total_work_minutes into v_baseline_minutes
  from app.resolve_effective_schedule_assignment(v_request.tenant_id, v_request.employee_id, v_request.work_date) sa
  join app.shift_template_versions stv on stv.id = sa.shift_template_version_id;
  if v_baseline_minutes is null then
    v_baseline_minutes := coalesce(v_policy.standard_workday_minutes, 480);
  end if;

  v_actual_total_minutes := extract(epoch from (v_session.effective_clock_out_at - v_session.effective_clock_in_at)) / 60.0;
  v_actual_overtime_minutes := greatest(0, round(v_actual_total_minutes - v_baseline_minutes))::integer;

  v_tolerance := greatest(coalesce(v_policy.rounding_increment_minutes, 15), 15);
  v_status := case when abs(v_actual_overtime_minutes - v_request.requested_minutes) <= v_tolerance then 'matched' else 'mismatch' end;

  update app.overtime_requests
  set reconciliation_status = v_status, reconciled_actual_minutes = v_actual_overtime_minutes, attendance_session_id = v_session.id
  where id = p_request_id
  returning * into v_request;

  return v_request;
end;
$$;

comment on function app._reconcile_overtime_request_actual is
  'HRT-281 (decision 3/4): internal engine, no authority check of its own -- callers (app.submit_overtime_request, app.decide_overtime_request, the public app.reconcile_overtime_request_actual wrapper) establish authority first. Reads app.attendance_sessions (HRT-278) and app.resolve_effective_schedule_assignment (HRT-279) directly, read-only -- writes nothing outside this table.';

create function app.reconcile_overtime_request_actual(p_request_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.overtime_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.overtime_requests;
  v_self app.employees;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.overtime_requests where id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'overtime_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  if not (v_self.master_record_id is not null and v_self.master_record_id = v_request.employee_id) then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  return app._reconcile_overtime_request_actual(p_request_id);
end;
$$;

-- ===========================================================================
-- 12. Overtime decide/cancel (decisions 6, 7, 9, 16, 18).
-- ===========================================================================

create function app.decide_overtime_request(
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

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_overtime_request',
    'app.overtime_requests', p_request_id, 'success', p_decided_reason, null, jsonb_build_object('decision', p_decision, 'eligible_minutes', v_request.eligible_minutes, 'approved_minutes', v_request.approved_minutes)
  );

  return v_request;
end;
$$;

create function app.cancel_overtime_request(
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

  update app.overtime_requests
  set status = 'cancelled', cancel_reason = p_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: overtime request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_overtime_request',
    'app.overtime_requests', p_request_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_request;
end;
$$;

-- ===========================================================================
-- 13. Timesheet entries: shared internal engine plus gated entry points
--     (decisions 1, 8, 14, 17), mirroring section 10 above exactly.
-- ===========================================================================

create function app._create_timesheet_entry(
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

  -- C-01: full-tuple idempotency replay.
  if p_idempotency_key is not null then
    select * into v_existing from app.timesheet_entries where tenant_id = p_employee.tenant_id and employee_id = p_employee.master_record_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.work_date = p_work_date and v_existing.entry_minutes = p_entry_minutes
         and v_existing.job_order_id is not distinct from p_job_order_id and v_existing.shipment_order_id is not distinct from p_shipment_order_id then
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

comment on function app._create_timesheet_entry is
  'HRT-281 (decision 14): internal engine, no authority check of its own. NO uniqueness on (employee_id, work_date) -- multi-job allocation is real; several entries may exist for the SAME workday across different job_order_id/shipment_order_id references.';

create function app.create_timesheet_entry(
  p_tenant_id uuid,
  p_work_date date,
  p_entry_minutes integer,
  p_unpaid_break_minutes integer,
  p_job_order_id uuid,
  p_shipment_order_id uuid,
  p_schedule_assignment_id uuid,
  p_notes text,
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
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  return app._create_timesheet_entry(
    v_self, p_work_date, p_entry_minutes, p_unpaid_break_minutes, p_job_order_id, p_shipment_order_id, p_schedule_assignment_id,
    p_notes, 'manual', p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.create_timesheet_entry is
  'HRT-281 (decision 14): self-only -- NO p_employee_id parameter exists, mirroring app.create_overtime_request''s own structural anti-spoofing shape.';

create function app.create_timesheet_entry_for_employee(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_work_date date,
  p_entry_minutes integer,
  p_unpaid_break_minutes integer,
  p_job_order_id uuid,
  p_shipment_order_id uuid,
  p_schedule_assignment_id uuid,
  p_notes text,
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
  v_decision app.rbac_decision;
  v_employee app.employees;
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

  return app._create_timesheet_entry(
    v_employee, p_work_date, p_entry_minutes, p_unpaid_break_minutes, p_job_order_id, p_shipment_order_id, p_schedule_assignment_id,
    p_notes, 'manual', p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );
end;
$$;

create function app.update_timesheet_entry_draft(
  p_entry_id uuid,
  p_expected_version integer,
  p_entry_minutes integer,
  p_unpaid_break_minutes integer,
  p_job_order_id uuid,
  p_shipment_order_id uuid,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
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
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_entry from app.timesheet_entries where id = p_entry_id for update;
  if not found or not app.has_active_tenant_membership(v_entry.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_entry_not_found: %', p_entry_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_entry.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_entry.employee_id;
  if not v_is_self then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_entry.tenant_id, 'HRS', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_entry.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_entry.record_version <> p_expected_version then
    raise exception 'stale_version: timesheet entry % expected version % but found %', p_entry_id, p_expected_version, v_entry.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_entry.status <> 'draft' then
    raise exception 'invalid_transition: timesheet entry % is %, only a draft may be edited', p_entry_id, v_entry.status
      using errcode = 'check_violation';
  end if;
  if p_entry_minutes is null or p_entry_minutes <= 0 or p_entry_minutes > 1440 then
    raise exception 'invalid_entry_minutes: entry_minutes must be a positive number of minutes, at most 1440' using errcode = 'check_violation';
  end if;
  if coalesce(p_unpaid_break_minutes, 0) < 0 then
    raise exception 'invalid_break_minutes: unpaid_break_minutes must not be negative' using errcode = 'check_violation';
  end if;

  perform app._validate_overtime_timesheet_operations_reference(v_entry.tenant_id, p_job_order_id, p_shipment_order_id);

  update app.timesheet_entries
  set entry_minutes = p_entry_minutes, unpaid_break_minutes = coalesce(p_unpaid_break_minutes, 0), job_order_id = p_job_order_id,
      shipment_order_id = p_shipment_order_id, notes = p_notes
  where id = p_entry_id and record_version = p_expected_version
  returning * into v_entry;
  if not found then
    raise exception 'stale_version: timesheet entry % target row was concurrently modified (expected version %)', p_entry_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_entry.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_timesheet_entry_draft',
    'app.timesheet_entries', p_entry_id, 'success', null, null, jsonb_build_object('entry_minutes', p_entry_minutes)
  );

  return v_entry;
end;
$$;

-- Decision 15: informational-only aggregate day reconciliation -- sets a
-- visible signal on every non-cancelled entry for the (employee, work_date),
-- never blocks approval on its own (app.decide_timesheet_entry, unlike
-- app.decide_overtime_request, never hard-gates on this status -- decision
-- 16's own disclosed divergence).
create function app._reconcile_timesheet_day(p_tenant_id uuid, p_employee_id uuid, p_work_date date)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_session app.attendance_sessions;
  v_employee app.employees;
  v_policy app.overtime_policy_versions;
  v_actual_minutes numeric;
  v_sum_entry_minutes integer;
  v_status text;
  v_tolerance integer;
begin
  select * into v_session from app.attendance_sessions where tenant_id = p_tenant_id and employee_id = p_employee_id and work_date = p_work_date;
  select * into v_employee from app.employees where master_record_id = p_employee_id;
  select * into v_policy from app.resolve_effective_overtime_policy_version(p_tenant_id, v_employee.branch_org_unit_id, p_work_date) limit 1;

  select coalesce(sum(greatest(0, entry_minutes - unpaid_break_minutes)), 0) into v_sum_entry_minutes
  from app.timesheet_entries
  where tenant_id = p_tenant_id and employee_id = p_employee_id and work_date = p_work_date and status in ('pending_approval', 'approved');

  -- Self-found (live db-test failure): the WHERE clause below is scoped to
  -- status IN ('pending_approval','approved') ONLY -- never 'draft'. An
  -- earlier draft touched every non-cancelled row (including untouched
  -- sibling drafts for the SAME work_date), which silently advanced their
  -- own record_version via app.touch_overtime_timesheet_row as a side
  -- effect of submitting a DIFFERENT entry -- a genuinely confusing
  -- surprise a concurrent legitimate edit on that untouched draft would
  -- have seen as a false stale_version. app.submit_timesheet_entry (the
  -- caller) now flips its OWN row to pending_approval BEFORE calling this,
  -- so the just-submitted row is correctly included here without needing
  -- 'draft' in this predicate at all.
  if v_session.id is null or v_session.status is distinct from 'closed' then
    update app.timesheet_entries
    set reconciliation_status = 'no_attendance', reconciled_day_actual_minutes = null, attendance_session_id = v_session.id
    where tenant_id = p_tenant_id and employee_id = p_employee_id and work_date = p_work_date and status in ('pending_approval', 'approved');
    return;
  end if;

  v_actual_minutes := round(extract(epoch from (v_session.effective_clock_out_at - v_session.effective_clock_in_at)) / 60.0);
  v_tolerance := greatest(coalesce(v_policy.rounding_increment_minutes, 15), 30);
  v_status := case when abs(v_actual_minutes - v_sum_entry_minutes) <= v_tolerance then 'matched' else 'mismatch' end;

  update app.timesheet_entries
  set reconciliation_status = v_status, reconciled_day_actual_minutes = v_actual_minutes::integer, attendance_session_id = v_session.id
  where tenant_id = p_tenant_id and employee_id = p_employee_id and work_date = p_work_date and status in ('pending_approval', 'approved');
end;
$$;

create function app.submit_timesheet_entry(
  p_entry_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text
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
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_entry.tenant_id, 'HRS', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_entry.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_entry.record_version <> p_expected_version then
    raise exception 'stale_version: timesheet entry % expected version % but found %', p_entry_id, p_expected_version, v_entry.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_entry.status <> 'draft' then
    raise exception 'invalid_transition: timesheet entry % is %, only a draft may be submitted', p_entry_id, v_entry.status
      using errcode = 'check_violation';
  end if;

  select * into v_employee from app.employees where master_record_id = v_entry.employee_id;
  if app.is_timesheet_period_locked(v_entry.tenant_id, v_employee.branch_org_unit_id, v_entry.work_date) then
    raise exception 'timesheet_period_locked: the period covering % is locked -- ask HR to reopen it first', v_entry.work_date
      using errcode = 'check_violation';
  end if;

  -- The status flip runs FIRST, guarded by the caller's own genuine
  -- p_expected_version (nothing has touched this row since the top SELECT
  -- ... FOR UPDATE). app._reconcile_timesheet_day runs AFTER, scoped to
  -- status IN ('pending_approval','approved') -- this row is already
  -- 'pending_approval' by the time it runs, so it is correctly included,
  -- and no untouched sibling DRAFT for the same work_date is ever silently
  -- touched (self-found: an earlier draft called reconcile BEFORE this
  -- flip, against a broader 'status <> cancelled' scope that included
  -- drafts, and a second sibling entry's own later submit call raised a
  -- false stale_version purely from this row's own submit having bumped
  -- it moments earlier -- live-caught by this checkpoint's own db-test
  -- multi-job-allocation scenario).
  update app.timesheet_entries
  set status = 'pending_approval'
  where id = p_entry_id and record_version = p_expected_version
  returning * into v_entry;
  if not found then
    raise exception 'stale_version: timesheet entry % target row was concurrently modified (expected version %)', p_entry_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app._reconcile_timesheet_day(v_entry.tenant_id, v_entry.employee_id, v_entry.work_date);
  select * into v_entry from app.timesheet_entries where id = p_entry_id;

  perform app.capture_audit_event(
    v_entry.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_timesheet_entry',
    'app.timesheet_entries', p_entry_id, 'success', null, null, '{}'::jsonb
  );

  return v_entry;
end;
$$;

create function app.decide_timesheet_entry(
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

  perform app.capture_audit_event(
    v_entry.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_timesheet_entry',
    'app.timesheet_entries', p_entry_id, 'success', p_decided_reason, null, jsonb_build_object('decision', p_decision, 'eligible_minutes', v_entry.eligible_minutes, 'approved_minutes', v_entry.approved_minutes)
  );

  return v_entry;
end;
$$;

create function app.cancel_timesheet_entry(
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

  update app.timesheet_entries
  set status = 'cancelled', cancel_reason = p_reason
  where id = p_entry_id and record_version = p_expected_version
  returning * into v_entry;
  if not found then
    raise exception 'stale_version: timesheet entry % target row was concurrently modified (expected version %)', p_entry_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_entry.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_timesheet_entry',
    'app.timesheet_entries', p_entry_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_entry;
end;
$$;

-- ===========================================================================
-- 14. Timesheet import -- real PLT-131/132 staged-import adapter, mirroring
--     HRT-278's own attendance device-import decision 6 exactly (section 22
--     "authorized import").
-- ===========================================================================

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('timesheet_import_source', 'Timesheet Import Source', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:timesheet_import_source', 'Timesheet Import Source', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.import_export_schemas (code, name, owner_primitive_code, registered_by)
values ('timesheet_import', 'Timesheet Import', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('import_export:timesheet_import', 'Timesheet Import', 'HRS', 'system')
on conflict (code) do nothing;

create function app.validate_timesheet_import_row(
  p_staging_row_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.import_staging_rows
language plpgsql
as $$
declare
  v_row app.import_staging_rows;
  v_payload jsonb;
  v_errors text[] := array[]::text[];
  v_text_fields text[] := array['employee_number', 'work_date', 'entry_minutes', 'job_number', 'shipment_number', 'notes'];
  v_field text;
  v_value text;
  v_tenant_id uuid;
begin
  v_row := app.validate_staging_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
  if v_row.validation_status <> 'valid' then
    return v_row;
  end if;

  v_payload := v_row.raw_payload;
  select tenant_id into v_tenant_id from app.jobs where job_id = v_row.job_id;

  foreach v_field in array v_text_fields loop
    v_value := v_payload ->> v_field;
    if v_value is not null and v_value ~ '^[-+=@\t\r]' then
      v_errors := v_errors || (v_field || ': value begins with a disallowed formula/spreadsheet-injection prefix (=, +, -, @, tab, or carriage return)');
    end if;
  end loop;

  if coalesce(v_payload ->> 'work_date', '') !~ '^\d{4}-\d{2}-\d{2}' then
    v_errors := v_errors || ('work_date: ' || coalesce(v_payload ->> 'work_date', '(missing)') || ' is not a valid ISO date');
  end if;

  if coalesce(v_payload ->> 'entry_minutes', '') !~ '^[0-9]+$' or (v_payload ->> 'entry_minutes')::numeric <= 0 then
    v_errors := v_errors || ('entry_minutes: ' || coalesce(v_payload ->> 'entry_minutes', '(missing)') || ' is not a positive whole number of minutes');
  end if;

  if coalesce(v_payload ->> 'employee_number', '') = '' then
    v_errors := v_errors || 'employee_number: required value is missing';
  elsif not exists (
    select 1 from app.employees e join app.master_records m on m.id = e.master_record_id
    where e.tenant_id = v_tenant_id and m.code = (v_payload ->> 'employee_number')
  ) then
    v_errors := v_errors || ('employee_number: ' || (v_payload ->> 'employee_number') || ' does not resolve to a known employee in this tenant');
  end if;

  if coalesce(v_payload ->> 'job_number', '') <> '' and not exists (
    select 1 from app.job_orders jo where jo.tenant_id = v_tenant_id and jo.job_number = (v_payload ->> 'job_number')
  ) then
    v_errors := v_errors || ('job_number: ' || (v_payload ->> 'job_number') || ' does not resolve to a known job order in this tenant');
  end if;

  if coalesce(v_payload ->> 'shipment_number', '') <> '' and not exists (
    select 1 from app.shipment_orders so where so.tenant_id = v_tenant_id and so.shipment_number = (v_payload ->> 'shipment_number')
  ) then
    v_errors := v_errors || ('shipment_number: ' || (v_payload ->> 'shipment_number') || ' does not resolve to a known shipment order in this tenant');
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

comment on function app.validate_timesheet_import_row is
  'HRT-281 (section 22 "authorized import"): calls app.validate_staging_row UNCHANGED first, then the same formula/spreadsheet-injection prefix set every prior staged-import adapter uses, plus employee_number/work_date/entry_minutes/job_number/shipment_number domain checks.';

create function app.commit_timesheet_import_job(
  p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_employee app.employees;
  v_job_order_id uuid;
  v_shipment_order_id uuid;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_failed_count integer := 0;
  v_ignore app.timesheet_entries;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'timesheet_import' then
    raise exception 'import_export_wrong_schema: job % is not a timesheet_import job', p_job_id using errcode = 'check_violation';
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

  -- Job-scoped advisory lock, mirrors app.commit_attendance_device_import_
  -- job (HRT-278) with this checkpoint's own distinct salt.
  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 281));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.timesheet_entries where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;

    select e.* into v_employee from app.employees e join app.master_records m on m.id = e.master_record_id
    where e.tenant_id = v_job.tenant_id and m.code = (v_payload ->> 'employee_number');

    v_job_order_id := null;
    if coalesce(v_payload ->> 'job_number', '') <> '' then
      select jo.id into v_job_order_id from app.job_orders jo where jo.tenant_id = v_job.tenant_id and jo.job_number = (v_payload ->> 'job_number');
    end if;
    v_shipment_order_id := null;
    if coalesce(v_payload ->> 'shipment_number', '') <> '' then
      select so.id into v_shipment_order_id from app.shipment_orders so where so.tenant_id = v_job.tenant_id and so.shipment_number = (v_payload ->> 'shipment_number');
    end if;

    begin
      v_ignore := app._create_timesheet_entry(
        v_employee, (v_payload ->> 'work_date')::date, (v_payload ->> 'entry_minutes')::integer, 0,
        v_job_order_id, v_shipment_order_id, null, v_payload ->> 'notes', 'import', null, p_actor_auth_user_id, p_actor_label
      );
      update app.timesheet_entries set source_import_staging_row_id = v_row.id where id = v_ignore.id;
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
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_timesheet_import_job',
    'app.jobs', p_job_id, 'success', null, null,
    jsonb_build_object('created_count', v_created_count, 'skipped_count', v_skipped_count, 'failed_count', v_failed_count)
  );

  return v_job;
end;
$$;

comment on function app.commit_timesheet_import_job is
  'HRT-281 (section 22): idempotent per staging row (source_import_staging_row_id unique-when-set, defended by a pre-check AND a per-row exception handler), job-scoped-advisory-lock serialized. Calls the SAME app._create_timesheet_entry engine the live manual-entry path calls, source=''import'' -- never a second, independently-hardened write path.';

-- ===========================================================================
-- 15. Period definition + per-employee summary approve/lock/reopen
--     (decision 10, acceptance criteria "lock/reopen ... pass").
-- ===========================================================================

create function app.create_timesheet_period(
  p_tenant_id uuid, p_org_unit_id uuid, p_code text, p_period_start date, p_period_end date, p_actor_auth_user_id uuid, p_actor_label text
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
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'invalid_code: code must not be empty' using errcode = 'check_violation';
  end if;
  if p_period_start is null or p_period_end is null or p_period_end < p_period_start then
    raise exception 'invalid_date_range: period_end must not be before period_start' using errcode = 'check_violation';
  end if;
  if p_org_unit_id is not null and not exists (select 1 from app.org_units where id = p_org_unit_id and tenant_id = p_tenant_id) then
    raise exception 'org_unit_not_found: no org unit % in tenant %', p_org_unit_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  begin
    insert into app.timesheet_periods (tenant_id, org_unit_id, code, period_start, period_end, created_by)
    values (p_tenant_id, p_org_unit_id, p_code, p_period_start, p_period_end, p_actor_label)
    returning * into v_period;
  exception
    when exclusion_violation then
      raise exception 'timesheet_period_overlap: a period of the same scope already covers part of % to %', p_period_start, p_period_end
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_timesheet_period',
    'app.timesheet_periods', v_period.id, 'success', null, null, to_jsonb(v_period)
  );

  return v_period;
end;
$$;

-- Recomputes a (period, employee) summary fresh from every APPROVED entry/
-- overtime request in the period''s own date range -- no authority check of
-- its own (internal engine, decision, mirrors app._transition_employee_
-- leave_status''s established convention). Upserts, never duplicates.
create function app._compute_timesheet_period_summary(p_period_id uuid, p_employee_id uuid)
returns app.timesheet_period_summaries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.timesheet_periods;
  v_regular integer;
  v_ot_weekday integer;
  v_ot_weekend integer;
  v_ot_holiday integer;
  v_entry_count integer;
  v_ot_count integer;
  v_summary app.timesheet_period_summaries;
begin
  select * into v_period from app.timesheet_periods where id = p_period_id;
  if v_period.id is null then
    raise exception 'timesheet_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  select coalesce(sum(approved_minutes), 0), count(*) into v_regular, v_entry_count
  from app.timesheet_entries
  where tenant_id = v_period.tenant_id and employee_id = p_employee_id and status = 'approved'
    and work_date between v_period.period_start and v_period.period_end;

  select
    coalesce(sum(approved_minutes) filter (where eligible_classification = 'weekday'), 0),
    coalesce(sum(approved_minutes) filter (where eligible_classification = 'weekend'), 0),
    coalesce(sum(approved_minutes) filter (where eligible_classification = 'holiday'), 0),
    count(*)
  into v_ot_weekday, v_ot_weekend, v_ot_holiday, v_ot_count
  from app.overtime_requests
  where tenant_id = v_period.tenant_id and employee_id = p_employee_id and status = 'approved'
    and work_date between v_period.period_start and v_period.period_end;

  insert into app.timesheet_period_summaries (
    tenant_id, employee_id, timesheet_period_id, total_regular_minutes, total_overtime_weekday_minutes,
    total_overtime_weekend_minutes, total_overtime_holiday_minutes, entry_count, overtime_request_count, computed_at
  ) values (
    v_period.tenant_id, p_employee_id, p_period_id, v_regular, v_ot_weekday, v_ot_weekend, v_ot_holiday, v_entry_count, v_ot_count, now()
  )
  on conflict (timesheet_period_id, employee_id) do update
  set total_regular_minutes = excluded.total_regular_minutes,
      total_overtime_weekday_minutes = excluded.total_overtime_weekday_minutes,
      total_overtime_weekend_minutes = excluded.total_overtime_weekend_minutes,
      total_overtime_holiday_minutes = excluded.total_overtime_holiday_minutes,
      entry_count = excluded.entry_count,
      overtime_request_count = excluded.overtime_request_count,
      computed_at = excluded.computed_at
  returning * into v_summary;

  return v_summary;
end;
$$;

create function app.submit_timesheet_period_summary(
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

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_timesheet_period_summary',
    'app.timesheet_period_summaries', v_summary.id, 'success', null, null, to_jsonb(v_summary)
  );

  return v_summary;
end;
$$;

create function app.approve_timesheet_period_summary(
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

  perform app.capture_audit_event(
    v_summary.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_timesheet_period_summary',
    'app.timesheet_period_summaries', p_summary_id, 'success', p_reason, null, to_jsonb(v_summary)
  );

  return v_summary;
end;
$$;

create function app.reject_timesheet_period_summary(
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
  -- reject counterpart did not. Low practical risk on its own (a self-
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

  perform app.capture_audit_event(
    v_summary.tenant_id, p_actor_auth_user_id, p_actor_label, 'reject_timesheet_period_summary',
    'app.timesheet_period_summaries', p_summary_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_summary;
end;
$$;

create function app.lock_timesheet_period(
  p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.timesheet_periods
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_period app.timesheet_periods;
  v_unapproved_count integer;
begin
  select * into v_period from app.timesheet_periods where id = p_period_id for update;
  if v_period.id is null or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_period.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: timesheet period % expected version % but found %', p_period_id, p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_period.status <> 'open' then
    raise exception 'invalid_transition: timesheet period % is already locked', p_period_id using errcode = 'check_violation';
  end if;

  select count(*) into v_unapproved_count from app.timesheet_period_summaries where timesheet_period_id = p_period_id and status <> 'approved';
  if v_unapproved_count > 0 then
    raise exception 'period_has_unapproved_summaries: % employee summary(ies) in period % are not yet approved', v_unapproved_count, p_period_id
      using errcode = 'check_violation';
  end if;

  update app.timesheet_periods
  set status = 'locked', locked_by = p_actor_label, locked_at = now()
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  if not found then
    raise exception 'stale_version: timesheet period % target row was concurrently modified (expected version %)', p_period_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'lock_timesheet_period',
    'app.timesheet_periods', p_period_id, 'success', null, null, '{}'::jsonb
  );

  return v_period;
end;
$$;

create function app.reopen_timesheet_period(
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

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_timesheet_period',
    'app.timesheet_periods', p_period_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_period;
end;
$$;

comment on function app.reopen_timesheet_period is
  'HRT-281 (decision 10): unlocks the date range for new submissions -- does NOT silently revert an already-approved app.timesheet_period_summaries row (that is app.reopen_timesheet_period_summary''s own, separately governed action, decision 10''s own "never a silent overwrite").';

create function app.reopen_timesheet_period_summary(
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
  -- re-generation of the payroll input is possible -- the ALREADY-generated
  -- app.payroll_time_inputs row itself is untouched here (it stays ''active''
  -- until a NEW version is genuinely generated -- decision 11).
  update app.timesheet_entries
  set payroll_input_status = 'pending'
  where tenant_id = v_summary.tenant_id and employee_id = v_summary.employee_id and payroll_input_status = 'approved'
    and work_date between v_period.period_start and v_period.period_end;
  update app.overtime_requests
  set payroll_input_status = 'pending'
  where tenant_id = v_summary.tenant_id and employee_id = v_summary.employee_id and payroll_input_status = 'approved'
    and work_date between v_period.period_start and v_period.period_end;

  perform app.capture_audit_event(
    v_summary.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_timesheet_period_summary',
    'app.timesheet_period_summaries', p_summary_id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_summary;
end;
$$;

-- ===========================================================================
-- 16. Payroll-input handoff (decisions 1, 11, 12) -- the ONE versioned
--     idempotent record Prompt 282 (Payroll) is expected to consume.
-- ===========================================================================

create function app._generate_payroll_time_input(p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
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

  select * into v_active from app.payroll_time_inputs where timesheet_period_id = p_period_id and employee_id = p_employee_id and status = 'active';

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
    -- key here to mis-compare against.
    return v_active;
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.payroll_time_inputs where timesheet_period_id = p_period_id and employee_id = p_employee_id;

  -- Supersede BEFORE insert -- HRT-279's own self-found defect #2 lesson
  -- (insert-before-supersede momentarily violated its own partial unique
  -- index), applied here from the start rather than discovered again.
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

comment on function app._generate_payroll_time_input is
  'HRT-281 (decisions 1, 11, 12): internal engine, no authority check of its own -- app.generate_payroll_time_input and app.generate_payroll_time_inputs_for_period both establish HRS:Approve authority BEFORE calling this. Zero rate/amount/currency column anywhere in its own output row (decision 12).';

create function app.generate_payroll_time_input(
  p_period_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_time_inputs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.timesheet_periods;
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  select * into v_period from app.timesheet_periods where id = p_period_id;
  if v_period.id is null or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_period.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_employee from app.employees where master_record_id = p_employee_id and tenant_id = v_period.tenant_id;
  if v_employee.master_record_id is null then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;

  return app._generate_payroll_time_input(p_period_id, p_employee_id, p_actor_auth_user_id, p_actor_label);
end;
$$;

create function app.generate_payroll_time_inputs_for_period(
  p_period_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns table (employee_id uuid, payroll_time_input_id uuid, generated boolean, skip_reason text)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.timesheet_periods;
  v_decision app.rbac_decision;
  v_row record;
  v_result app.payroll_time_inputs;
begin
  select * into v_period from app.timesheet_periods where id = p_period_id;
  if v_period.id is null or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'timesheet_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_period.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_row in select s.employee_id as emp_id from app.timesheet_period_summaries s where s.timesheet_period_id = p_period_id and s.status = 'approved'
  loop
    begin
      v_result := app._generate_payroll_time_input(p_period_id, v_row.emp_id, p_actor_auth_user_id, p_actor_label);
      employee_id := v_row.emp_id; payroll_time_input_id := v_result.id; generated := true; skip_reason := null;
      return next;
    exception
      when others then
        employee_id := v_row.emp_id; payroll_time_input_id := null; generated := false; skip_reason := sqlerrm;
        return next;
    end;
  end loop;

  return;
end;
$$;

comment on function app.generate_payroll_time_inputs_for_period is
  'HRT-281: bulk variant, one HRS:Approve authority check, then loops calling the SAME app._generate_payroll_time_input internal engine per approved summary -- a per-employee failure is captured in skip_reason and does not abort the batch.';

-- ===========================================================================
-- 17. Read RPCs. Every table alias is explicit throughout -- never a bare
--     column reference that could collide with a RETURNS TABLE output
--     column of the same name (the recurring ambiguous-id class this task's
--     own instructions, and this phase's own taxonomy, both flag).
-- ===========================================================================

create function app.list_my_overtime_requests(p_tenant_id uuid, p_actor_auth_user_id uuid, p_limit integer, p_after_id uuid)
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
    select * into v_after from app.overtime_requests where id = p_after_id;
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

create function app.list_overtime_requests(p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid, p_status text, p_limit integer, p_after_id uuid)
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
    select * into v_after from app.overtime_requests where id = p_after_id;
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

create function app.get_overtime_request_detail(p_request_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, employee_id uuid, employee_number text, employee_full_name text, work_date date, request_type text,
  requested_start_at timestamptz, requested_end_at timestamptz, requested_minutes integer, unpaid_break_minutes integer,
  reason text, schedule_assignment_id uuid, job_order_id uuid, job_number text, shipment_order_id uuid, shipment_number text,
  status text, reconciliation_status text, reconciled_actual_minutes integer, eligible_minutes integer, eligible_classification text,
  approved_minutes integer, decided_reason text, cancel_reason text, payroll_input_status text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row record;
  v_self app.employees;
  v_is_self boolean;
  v_has_view boolean;
  v_has_view_personal boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select o.*, m.code as m_code, e.full_name as e_full_name, e.manager_employee_id as mgr_id, jo.job_number as jo_number, so.shipment_number as so_number
  into v_row
  from app.overtime_requests o
  join app.employees e on e.master_record_id = o.employee_id
  join app.master_records m on m.id = e.master_record_id
  left join app.job_orders jo on jo.id = o.job_order_id
  left join app.shipment_orders so on so.id = o.shipment_order_id
  where o.id = p_request_id;

  if v_row.id is null or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_self := app.get_self_employee(v_row.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_row.employee_id;
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'HRS', 'View')).allowed;

  if not (v_is_self or v_has_view or (v_self.master_record_id is not null and v_self.master_record_id = v_row.mgr_id)) then
    return;
  end if;

  v_has_view_personal := v_is_self or (app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'HRS', 'View personal data')).allowed;

  return query select
    v_row.id, v_row.employee_id, v_row.m_code, v_row.e_full_name, v_row.work_date, v_row.request_type,
    v_row.requested_start_at, v_row.requested_end_at, v_row.requested_minutes, v_row.unpaid_break_minutes,
    case when v_has_view_personal then v_row.reason else null end,
    v_row.schedule_assignment_id, v_row.job_order_id, v_row.jo_number, v_row.shipment_order_id, v_row.so_number,
    v_row.status, v_row.reconciliation_status, v_row.reconciled_actual_minutes, v_row.eligible_minutes, v_row.eligible_classification,
    v_row.approved_minutes, case when v_has_view_personal then v_row.decided_reason else null end,
    case when v_has_view_personal then v_row.cancel_reason else null end, v_row.payroll_input_status, v_row.record_version;
end;
$$;

create function app.list_my_timesheet_entries(p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date, p_limit integer, p_after_id uuid)
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
    select * into v_after from app.timesheet_entries where id = p_after_id;
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

create function app.list_timesheet_entries(
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
    select * into v_after from app.timesheet_entries where id = p_after_id;
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

create function app.get_timesheet_entry_detail(p_entry_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, employee_id uuid, employee_number text, employee_full_name text, work_date date, entry_minutes integer, unpaid_break_minutes integer,
  job_order_id uuid, job_number text, shipment_order_id uuid, shipment_number text, notes text, status text, source text,
  reconciliation_status text, reconciled_day_actual_minutes integer, eligible_minutes integer, approved_minutes integer,
  decided_reason text, cancel_reason text, payroll_input_status text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row record;
  v_self app.employees;
  v_is_self boolean;
  v_has_view boolean;
  v_has_view_personal boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select te.*, m.code as m_code, e.full_name as e_full_name, e.manager_employee_id as mgr_id, jo.job_number as jo_number, so.shipment_number as so_number
  into v_row
  from app.timesheet_entries te
  join app.employees e on e.master_record_id = te.employee_id
  join app.master_records m on m.id = e.master_record_id
  left join app.job_orders jo on jo.id = te.job_order_id
  left join app.shipment_orders so on so.id = te.shipment_order_id
  where te.id = p_entry_id;

  if v_row.id is null or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_self := app.get_self_employee(v_row.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_row.employee_id;
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'HRS', 'View')).allowed;

  if not (v_is_self or v_has_view or (v_self.master_record_id is not null and v_self.master_record_id = v_row.mgr_id)) then
    return;
  end if;

  v_has_view_personal := v_is_self or (app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'HRS', 'View personal data')).allowed;

  return query select
    v_row.id, v_row.employee_id, v_row.m_code, v_row.e_full_name, v_row.work_date, v_row.entry_minutes, v_row.unpaid_break_minutes,
    v_row.job_order_id, v_row.jo_number, v_row.shipment_order_id, v_row.so_number,
    case when v_has_view_personal then v_row.notes else null end,
    v_row.status, v_row.source, v_row.reconciliation_status, v_row.reconciled_day_actual_minutes, v_row.eligible_minutes, v_row.approved_minutes,
    case when v_has_view_personal then v_row.decided_reason else null end,
    case when v_has_view_personal then v_row.cancel_reason else null end, v_row.payroll_input_status, v_row.record_version;
end;
$$;

-- Decision: visible to any active tenant member, not gated on HRS:View --
-- period code/date-range/lock-status is non-sensitive organizational
-- calendar metadata (no employee-level data, mirrors app.list_attendance_
-- policies' own identical "any tenant member may see policy shape" bar).
-- Self-found necessity: without this, a self-service employee could never
-- discover which timesheet_period_id to submit their own period summary
-- against, since app.submit_timesheet_period_summary itself requires an
-- explicit p_period_id -- the exact "capability with no reachable UI
-- caller" class (taxonomy C-20) this checkpoint designs against from the
-- start rather than discovering after ship.
create function app.list_timesheet_periods(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, org_unit_id uuid, code text, period_start date, period_end date, status text, record_version integer)
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
  select tp.id, tp.org_unit_id, tp.code, tp.period_start, tp.period_end, tp.status, tp.record_version
  from app.timesheet_periods tp
  where tp.tenant_id = p_tenant_id
  order by tp.period_start desc;
end;
$$;

create function app.list_timesheet_period_summaries(p_tenant_id uuid, p_actor_auth_user_id uuid, p_period_id uuid, p_status text)
returns table (
  id uuid, employee_id uuid, employee_number text, employee_full_name text, timesheet_period_id uuid, status text,
  total_regular_minutes integer, total_overtime_weekday_minutes integer, total_overtime_weekend_minutes integer,
  total_overtime_holiday_minutes integer, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_has_view boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View')).allowed;

  return query
  select s.id, s.employee_id, m.code, e.full_name, s.timesheet_period_id, s.status, s.total_regular_minutes,
         s.total_overtime_weekday_minutes, s.total_overtime_weekend_minutes, s.total_overtime_holiday_minutes, s.record_version
  from app.timesheet_period_summaries s
  join app.employees e on e.master_record_id = s.employee_id
  join app.master_records m on m.id = e.master_record_id
  where s.tenant_id = p_tenant_id
    and (p_period_id is null or s.timesheet_period_id = p_period_id)
    and (p_status is null or s.status = p_status)
    and (v_has_view or s.employee_id = v_self.master_record_id or e.manager_employee_id = v_self.master_record_id)
  order by s.timesheet_period_id desc, m.code;
end;
$$;

create function app.get_timesheet_period_summary(p_summary_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, employee_id uuid, employee_number text, employee_full_name text, timesheet_period_id uuid, status text,
  total_regular_minutes integer, total_overtime_weekday_minutes integer, total_overtime_weekend_minutes integer,
  total_overtime_holiday_minutes integer, entry_count integer, overtime_request_count integer, computed_at timestamptz,
  decided_reason text, reopen_count integer, last_reopen_reason text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row record;
  v_self app.employees;
  v_is_self boolean;
  v_has_view boolean;
  v_has_view_personal boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select s.*, m.code as m_code, e.full_name as e_full_name, e.manager_employee_id as mgr_id
  into v_row
  from app.timesheet_period_summaries s
  join app.employees e on e.master_record_id = s.employee_id
  join app.master_records m on m.id = e.master_record_id
  where s.id = p_summary_id;

  if v_row.id is null or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_self := app.get_self_employee(v_row.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_row.employee_id;
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'HRS', 'View')).allowed;

  if not (v_is_self or v_has_view or (v_self.master_record_id is not null and v_self.master_record_id = v_row.mgr_id)) then
    return;
  end if;

  v_has_view_personal := v_is_self or (app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'HRS', 'View personal data')).allowed;

  return query select
    v_row.id, v_row.employee_id, v_row.m_code, v_row.e_full_name, v_row.timesheet_period_id, v_row.status,
    v_row.total_regular_minutes, v_row.total_overtime_weekday_minutes, v_row.total_overtime_weekend_minutes, v_row.total_overtime_holiday_minutes,
    v_row.entry_count, v_row.overtime_request_count, v_row.computed_at,
    case when v_has_view_personal then v_row.decided_reason else null end,
    v_row.reopen_count, case when v_has_view_personal then v_row.last_reopen_reason else null end, v_row.record_version;
end;
$$;

create function app.list_overtime_policies(p_tenant_id uuid, p_actor_auth_user_id uuid)
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
  from app.overtime_policies p
  left join lateral (
    select v.id, v.version_number from app.overtime_policy_versions v
    where v.policy_id = p.id and v.status = 'published'
    order by v.effective_from desc limit 1
  ) pv on true
  where p.tenant_id = p_tenant_id
  order by p.name;
end;
$$;

create function app.get_overtime_policy_version(p_version_id uuid, p_actor_auth_user_id uuid)
returns app.overtime_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.overtime_policy_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_version from app.overtime_policy_versions where id = p_version_id;
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

-- Decision 12: gated on the PROTECTED 'HRS:View payroll' permission for any
-- non-self caller -- the narrowest reading of "pay ... fields withheld
-- unless payroll permission," even though this artifact carries zero money.
create function app.list_payroll_time_inputs(p_tenant_id uuid, p_actor_auth_user_id uuid, p_period_id uuid)
returns table (
  id uuid, employee_id uuid, employee_number text, timesheet_period_id uuid, version_number integer, status text,
  regular_minutes integer, overtime_weekday_minutes integer, overtime_weekend_minutes integer, overtime_holiday_minutes integer, created_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_has_view_payroll boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  v_has_view_payroll := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View payroll')).allowed;

  if not v_has_view_payroll and v_self.master_record_id is null then
    return;
  end if;

  return query
  select pti.id, pti.employee_id, m.code, pti.timesheet_period_id, pti.version_number, pti.status, pti.regular_minutes,
         pti.overtime_weekday_minutes, pti.overtime_weekend_minutes, pti.overtime_holiday_minutes, pti.created_at
  from app.payroll_time_inputs pti
  join app.employees e on e.master_record_id = pti.employee_id
  join app.master_records m on m.id = e.master_record_id
  where pti.tenant_id = p_tenant_id
    and (p_period_id is null or pti.timesheet_period_id = p_period_id)
    and (v_has_view_payroll or pti.employee_id = v_self.master_record_id)
  order by pti.created_at desc;
end;
$$;

create function app.get_payroll_time_input(p_payroll_time_input_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, employee_id uuid, employee_number text, timesheet_period_id uuid, version_number integer, status text,
  regular_minutes integer, overtime_weekday_minutes integer, overtime_weekend_minutes integer, overtime_holiday_minutes integer,
  source_entry_ids uuid[], source_overtime_request_ids uuid[], created_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row record;
  v_self app.employees;
  v_has_view_payroll boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select pti.*, m.code as m_code
  into v_row
  from app.payroll_time_inputs pti
  join app.employees e on e.master_record_id = pti.employee_id
  join app.master_records m on m.id = e.master_record_id
  where pti.id = p_payroll_time_input_id;

  if v_row.id is null or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_self := app.get_self_employee(v_row.tenant_id, p_actor_auth_user_id);
  v_has_view_payroll := (app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'HRS', 'View payroll')).allowed;

  if not (v_has_view_payroll or (v_self.master_record_id is not null and v_self.master_record_id = v_row.employee_id)) then
    return;
  end if;

  return query select
    v_row.id, v_row.employee_id, v_row.m_code, v_row.timesheet_period_id, v_row.version_number, v_row.status,
    v_row.regular_minutes, v_row.overtime_weekday_minutes, v_row.overtime_weekend_minutes, v_row.overtime_holiday_minutes,
    v_row.source_entry_ids, v_row.source_overtime_request_ids, v_row.created_at;
end;
$$;

create function app.export_timesheet_entries(p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date)
returns table (
  employee_number text, employee_full_name text, work_date date, job_number text, shipment_number text,
  entry_minutes integer, eligible_minutes integer, approved_minutes integer, status text
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
    p_tenant_id, p_actor_auth_user_id, p_actor_auth_user_id::text, 'export_timesheet_entries',
    'app.timesheet_entries', null, 'success', null, null, jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date)
  );

  return query
  select m.code, e.full_name, te.work_date, jo.job_number, so.shipment_number, te.entry_minutes, te.eligible_minutes, te.approved_minutes, te.status
  from app.timesheet_entries te
  join app.employees e on e.master_record_id = te.employee_id
  join app.master_records m on m.id = e.master_record_id
  left join app.job_orders jo on jo.id = te.job_order_id
  left join app.shipment_orders so on so.id = te.shipment_order_id
  where te.tenant_id = p_tenant_id and te.work_date between p_from_date and p_to_date
  order by te.work_date, m.code;
end;
$$;

-- ===========================================================================
-- 18. RLS -- hardened default-deny select policy on every new table (writes
--     exclusively through the SECURITY DEFINER functions above, never a raw
--     INSERT/UPDATE grant to authenticated). Person-scoped tables (overtime_
--     requests, timesheet_entries, timesheet_period_summaries) reuse app.
--     can_view_hris_person_scoped_row (established by the batch 278-280
--     Tier C fix, 20260730950000) FROM THE FIRST MIGRATION -- never the
--     tenant-membership-only shape that recurred as a HIGH finding three
--     times earlier in this same phase (mandatory reading item: "reuse ...
--     do not reinvent scoping").
-- ===========================================================================

alter table app.overtime_policies enable row level security;
alter table app.overtime_policy_versions enable row level security;
alter table app.overtime_requests enable row level security;
alter table app.timesheet_periods enable row level security;
alter table app.timesheet_entries enable row level security;
alter table app.timesheet_period_summaries enable row level security;
alter table app.payroll_time_inputs enable row level security;

create policy overtime_policies_select_scoped on app.overtime_policies
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy overtime_policy_versions_select_scoped on app.overtime_policy_versions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy timesheet_periods_select_scoped on app.timesheet_periods
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy overtime_requests_select_scoped on app.overtime_requests
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.can_view_hris_person_scoped_row(tenant_id, employee_id)
    )
  );

create policy timesheet_entries_select_scoped on app.timesheet_entries
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.can_view_hris_person_scoped_row(tenant_id, employee_id)
    )
  );

create policy timesheet_period_summaries_select_scoped on app.timesheet_period_summaries
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.can_view_hris_person_scoped_row(tenant_id, employee_id)
    )
  );

-- Decision 12: deliberately NOT app.can_view_hris_person_scoped_row (which
-- checks plain 'HRS:View') -- payroll_time_inputs is the one table this
-- checkpoint gates more conservatively than the reused helper, on self OR
-- the PROTECTED 'HRS:View payroll' permission specifically. A disclosed,
-- reasoned divergence from the shared shape, not a copy-paste omission.
--
-- Self-found during this checkpoint's own adversarial testing (not a db-
-- test failure -- a genuine live-reproduced RLS defect): app.evaluate_
-- permission is SECURITY INVOKER and granted EXECUTE to service_role ONLY
-- (20260716104519), never authenticated. Every other RLS policy in this
-- migration/repository calls only SECURITY DEFINER helpers (app.has_
-- active_tenant_membership, app.can_view_hris_person_scoped_row, etc.) --
-- inlining a bare app.evaluate_permission(...) call directly into a USING
-- clause, evaluated as the querying `authenticated` role (not elevated by
-- any SECURITY DEFINER context at that point), raised a raw `permission
-- denied for function evaluate_permission` for EVERY authenticated caller,
-- including a genuinely entitled HRS:View-payroll holder -- a real,
-- reproducible functional break, not merely a hypothetical. Fixed by
-- wrapping the predicate in its own SECURITY DEFINER helper, mirroring
-- app.can_view_hris_person_scoped_row's own established shape exactly.
create function app.can_view_hris_payroll_time_input_row(p_tenant_id uuid, p_employee_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  if p_tenant_id is null or p_employee_id is null then
    return false;
  end if;
  if not app.has_active_tenant_membership(p_tenant_id, p_auth_user_id) then
    return false;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = p_employee_id then
    return true;
  end if;
  return (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'HRS', 'View payroll')).allowed;
end;
$$;

comment on function app.can_view_hris_payroll_time_input_row is
  'HRT-281 (decision 12, self-found live RLS defect): self OR the PROTECTED HRS:View payroll permission specifically -- never plain HRS:View. SECURITY DEFINER so its own internal app.evaluate_permission call runs as this function''s owner, never the bare `authenticated` role a raw RLS policy expression would otherwise evaluate as.';

create policy payroll_time_inputs_select_scoped on app.payroll_time_inputs
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.can_view_hris_payroll_time_input_row(tenant_id, employee_id)
    )
  );

-- ===========================================================================
-- 19. Grants -- column-restricted from the first migration, never a blanket
--     `grant select on <table> to authenticated`.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select (id, tenant_id, org_unit_id, name, status, record_version, created_by, created_at, updated_at)
  on app.overtime_policies to authenticated;
grant select on app.overtime_policies to service_role;

grant select (
  id, policy_id, tenant_id, version_number, status, effective_from, rounding_increment_minutes, rounding_mode, min_overtime_minutes,
  daily_overtime_cap_minutes, weekly_overtime_cap_minutes, standard_workday_minutes, default_break_deduction_minutes,
  requires_pre_approval, published_at, published_by, record_version, created_by, created_at, updated_at
) on app.overtime_policy_versions to authenticated;
grant select on app.overtime_policy_versions to service_role;

grant select (
  id, tenant_id, employee_id, work_date, request_type, requested_start_at, requested_end_at, requested_minutes, unpaid_break_minutes,
  schedule_assignment_id, job_order_id, shipment_order_id, status, requested_by_auth_user_id, requested_by, policy_version_id,
  attendance_session_id, reconciliation_status, reconciled_actual_minutes, eligible_minutes, eligible_classification, approved_minutes,
  decided_by, decided_at, payroll_input_status, idempotency_key, record_version, created_by, created_at, updated_at
) on app.overtime_requests to authenticated;
grant select on app.overtime_requests to service_role;

grant select (id, tenant_id, org_unit_id, code, period_start, period_end, status, locked_by, locked_at, reopen_count, record_version, created_by, created_at, updated_at)
  on app.timesheet_periods to authenticated;
grant select on app.timesheet_periods to service_role;

grant select (
  id, tenant_id, employee_id, work_date, entry_minutes, unpaid_break_minutes, job_order_id, shipment_order_id, schedule_assignment_id,
  status, source, requested_by_auth_user_id, requested_by, policy_version_id, attendance_session_id, reconciliation_status,
  reconciled_day_actual_minutes, eligible_minutes, approved_minutes, decided_by, decided_at, payroll_input_status,
  source_import_staging_row_id, idempotency_key, record_version, created_by, created_at, updated_at
) on app.timesheet_entries to authenticated;
grant select on app.timesheet_entries to service_role;

grant select (
  id, tenant_id, employee_id, timesheet_period_id, status, total_regular_minutes, total_overtime_weekday_minutes,
  total_overtime_weekend_minutes, total_overtime_holiday_minutes, entry_count, overtime_request_count, computed_at,
  submitted_by, submitted_at, decided_by, decided_at, reopen_count, last_reopened_by, last_reopened_at, record_version, created_at, updated_at
) on app.timesheet_period_summaries to authenticated;
grant select on app.timesheet_period_summaries to service_role;

-- Decision 12: no money column exists on this table at all, but the grant
-- is still column-restricted (defense in depth, mirrors every other
-- sensitive table in this migration) -- every column here is time/
-- classification only.
grant select (
  id, tenant_id, employee_id, timesheet_period_id, period_summary_id, version_number, status, regular_minutes,
  overtime_weekday_minutes, overtime_weekend_minutes, overtime_holiday_minutes, source_entry_ids, source_overtime_request_ids, created_at
) on app.payroll_time_inputs to authenticated;
grant select on app.payroll_time_inputs to service_role;

grant execute on function app.can_view_hris_payroll_time_input_row(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.resolve_effective_overtime_policy_version(uuid, uuid, date) to authenticated, service_role;
grant execute on function app.round_minutes(numeric, integer, text) to authenticated, service_role;
grant execute on function app.classify_overtime_work_date(uuid, uuid, date) to authenticated, service_role;
grant execute on function app.resolve_effective_timesheet_period(uuid, uuid, date) to authenticated, service_role;
grant execute on function app.is_timesheet_period_locked(uuid, uuid, date) to authenticated, service_role;

grant execute on function app.create_overtime_policy(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_overtime_policy_version(uuid, integer, text, integer, integer, integer, integer, integer, boolean, date, uuid, text) to authenticated, service_role;
grant execute on function app.publish_overtime_policy_version(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.create_overtime_request(uuid, text, timestamptz, timestamptz, integer, text, uuid, uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_overtime_request_for_employee(uuid, uuid, text, timestamptz, timestamptz, integer, text, uuid, uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_overtime_request(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reconcile_overtime_request_actual(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.decide_overtime_request(uuid, integer, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_overtime_request(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.create_timesheet_entry(uuid, date, integer, integer, uuid, uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_timesheet_entry_for_employee(uuid, uuid, date, integer, integer, uuid, uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_timesheet_entry_draft(uuid, integer, integer, integer, uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_timesheet_entry(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decide_timesheet_entry(uuid, integer, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_timesheet_entry(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.validate_timesheet_import_row(uuid, uuid, text) to service_role;
grant execute on function app.commit_timesheet_import_job(uuid, boolean, uuid, text) to authenticated, service_role;

grant execute on function app.create_timesheet_period(uuid, uuid, text, date, date, uuid, text) to authenticated, service_role;
grant execute on function app.submit_timesheet_period_summary(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.approve_timesheet_period_summary(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.reject_timesheet_period_summary(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.lock_timesheet_period(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reopen_timesheet_period(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.reopen_timesheet_period_summary(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.generate_payroll_time_input(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.generate_payroll_time_inputs_for_period(uuid, uuid, text) to authenticated, service_role;

grant execute on function app.list_my_overtime_requests(uuid, uuid, integer, uuid) to authenticated, service_role;
grant execute on function app.list_overtime_requests(uuid, uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.get_overtime_request_detail(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_my_timesheet_entries(uuid, uuid, date, date, integer, uuid) to authenticated, service_role;
grant execute on function app.list_timesheet_entries(uuid, uuid, uuid, text, date, date, integer, uuid) to authenticated, service_role;
grant execute on function app.get_timesheet_entry_detail(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_timesheet_periods(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_timesheet_period_summaries(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_timesheet_period_summary(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_overtime_policies(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_overtime_policy_version(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_payroll_time_inputs(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_payroll_time_input(uuid, uuid) to authenticated, service_role;
grant execute on function app.export_timesheet_entries(uuid, uuid, date, date) to authenticated, service_role;

-- Internal engine functions -- service_role only (called exclusively from
-- inside this migration's own already-authorized SECURITY DEFINER
-- functions), mirrors app._ingest_attendance_event/app._recalculate_
-- session_exceptions' own established "internal, no direct authenticated
-- grant" convention.
grant execute on function app._validate_overtime_timesheet_operations_reference(uuid, uuid, uuid) to service_role;
grant execute on function app._create_overtime_request(app.employees, text, timestamptz, timestamptz, integer, text, uuid, uuid, uuid, text, uuid, text) to service_role;
grant execute on function app._reconcile_overtime_request_actual(uuid) to service_role;
grant execute on function app._create_timesheet_entry(app.employees, date, integer, integer, uuid, uuid, uuid, text, text, text, uuid, text) to service_role;
grant execute on function app._reconcile_timesheet_day(uuid, uuid, date) to service_role;
grant execute on function app._compute_timesheet_period_summary(uuid, uuid) to service_role;
grant execute on function app._generate_payroll_time_input(uuid, uuid, uuid, text) to service_role;
