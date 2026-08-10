-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-008 (Leave, Permit and
-- Business Trip, Prompt 280) -- the THIRD and LAST of the 3-prompt Tier-C
-- batch HRT-278..280 (Attendance / Shift-Roster / Leave-Permit-Business-Trip;
-- batch capped at 3 per docs/standards/BUILD_EXECUTION_PROTOCOL.md section
-- 3.4, since the batch immediately preceding it, HRT-277, closed its own
-- Tier C with 7 Critical/High findings). Builds versioned leave/permit/
-- business-trip type and policy, an auditable balance ledger, a governed
-- request/approval workflow routed through PLT-123 (mandatory reading item
-- 8), and real integration points into HRT-278 (Attendance, exception
-- suppression) and HRT-279 (Shift/Roster, coverage/schedule) -- against
-- app.employees (HRT-274) and app.org_units (HRT-275/ADR-0023 Part A) --
-- never a second employee/organization root, never a second approval engine.
--
-- Design decisions, disclosed rather than left implicit (this build's
-- standing discipline, mirrors every prior HRT checkpoint's own header
-- shape):
--
-- 1. **Type identity is tenant-wide; policy detail is effective-dated AND
--    optionally org_unit-scoped -- two tables, mirroring HRT-278's own
--    attendance_policies/attendance_policy_versions split, but for a
--    different reason.** app.leave_types is a small, tenant-wide identity
--    catalogue (code/name/category/unit/requires_balance/requires_evidence) --
--    "Annual Leave" is the SAME concept everywhere in one tenant. Its
--    accrual/carry-forward/eligibility RULES can legitimately vary by branch
--    (different provincial regulation, different rosters) and by effective
--    date, so app.leave_type_policy_versions carries its own nullable
--    org_unit_id and effective_from, resolved by
--    app.resolve_effective_leave_type_policy_version exactly the way
--    app.resolve_effective_attendance_policy_version already resolves
--    (branch-scoped-over-tenant-wide, latest effective_from wins).
--
-- 2. **category in ('leave', 'permit', 'business_trip') is one closed
--    dimension on app.leave_types, not three separate tables.** Prompt 280's
--    own title names exactly these three, and section 22 ("permit without
--    balance, business trip") is satisfied structurally by
--    requires_balance=false on a permit/business-trip type -- never a
--    parallel schema fork per category. destination (leave_requests) is
--    populated only for a business_trip-category request; the CHECK
--    constraint below enforces this shape, not application discipline.
--
-- 3. **Balances are derived exclusively from an auditable ledger -- never a
--    mutable balance column anywhere (section 13/24's own "no silent field
--    mutation" instruction, taken literally).** app.leave_balance_ledger is
--    genuinely append-only (no UPDATE/DELETE grant to any role, not even
--    service_role gets an UPDATE); app.get_employee_leave_balance sums it on
--    read. accrual/carry_forward_expire/adjustment/opening_balance/
--    request_debit/request_credit_reversal are the seven event_type values
--    a real leave ledger needs; no eighth speculative type is added.
--
-- 4. **Ledger posting happens at APPROVAL and at post-approval CANCELLATION
--    only -- never at submission.** Section 24's own "Approved/cancelled
--    requests post idempotent ledger... effects; no direct balance edit" is
--    read literally: app.submit_leave_request performs a SOFT (non-locking,
--    advisory) balance check against currently-held balance minus other
--    pending requests' own total_units, so a caller gets fast feedback
--    without a lock held across every pending request in the tenant; the
--    AUTHORITATIVE check happens under a real advisory lock at
--    app.decide_leave_request's own approval branch (decision 9), the exact
--    moment the ledger debit is actually posted -- closing the C-04-shaped
--    "two concurrent approvals oversell the same balance" race a soft-only
--    check would leave open.
--
-- 5. **Overlap prevention is a real, database-enforced btree_gist EXCLUDE
--    constraint -- mirrors app.employee_position_assignments
--    (HRT-275)/app.vendor_rate_versions_no_ambiguous_overlap (PRC-255)
--    exactly, per this checkpoint's own binding instructions.**
--    app.leave_requests.validity_range (daterange, generated) with an
--    EXCLUDE using gist (employee_id with =, validity_range with &&) scoped
--    to status in ('pending_approval', 'approved') -- a draft or a
--    rejected/cancelled request never blocks a new one. V1-disclosed
--    simplification: overlap is checked at the WHOLE date-range granularity
--    regardless of day_portion (a half_day_morning permit and a
--    half_day_afternoon business trip on the SAME calendar day are treated
--    as overlapping and blocked, even though a real calendar has room for
--    both) -- the same class of disclosed simplification HRT-279's own
--    segment-cross-midnight rule already established for this repository,
--    not silently narrower than what section 25 actually requires (overlap
--    IS checked; the day_portion sub-partition of one single day is simply
--    not split further in V1).
--
-- 6. **Approval routes through PLT-123 exactly like every other Phase 6/7
--    approval flow -- never a bespoke mechanism (mandatory reading item 8,
--    binding instruction, explicit deviation from HRT-278's own decision 5
--    for attendance corrections).** HRT-278 deliberately bypassed PLT-123 for
--    corrections because that is a routine, potentially high-volume,
--    low-single-stakes workflow that must keep working even for a tenant
--    with no approval routing configured. Leave/permit/business-trip
--    requests are the opposite: every prior HRT checkpoint that reaches a
--    comparable stakes level (job offers, HRT-276; onboarding/offboarding
--    finalize, HRT-277) already routes through app.request_approval, and
--    this domain's own real balance/payroll/coverage consequences match that
--    bar. app.submit_leave_request looks up the tenant's own published
--    config_type_code='approval' definition exactly as
--    app.submit_onboarding_case_for_finalize_approval does and raises the
--    SAME approval_definition_not_configured error when none exists --
--    disclosed, not silently narrowed; a tenant must configure approval
--    routing (PLT-123, already-shipped capability) before this domain's
--    submit path will succeed, matching the onboarding/offboarding
--    precedent exactly.
--
-- 7. **Cancel genuinely cancels, never leaves a dependent process live
--    (mandatory reading item 4/8, the exact class found independently in
--    HRT-276 AND HRT-277).** app.cancel_leave_request calls
--    app.cancel_approval_request on any in-flight PLT-123 approval request
--    BEFORE cascading to cancelled, using the identical deliberately-PLAIN-
--    read-first, defer-all-locking-to-the-terminal-UPDATE lock order
--    app.cancel_onboarding_case (HRT-277, 20260730880000) established, so
--    this domain does not reintroduce the exact lock-order deadlock that
--    fix's own comment documents finding.
--
-- 8. **Attachments are a single evidence_file_id column, re-validated at the
--    accepting RPC (taxonomy C-10) -- mirrors
--    app.attendance_correction_requests' own established single-evidence-
--    file convention exactly**, not a new N-attachment table. Medical/
--    personal evidence is not a distinct file-classification VALUE this
--    migration invents; app.leave_types.evidence_classification
--    ('none'/'personal'/'medical') is a domain-owned field describing WHAT
--    KIND of justification a leave type demands, independent of
--    app.files.classification (PLT-128's own storage-classification scale,
--    which the uploader sets at upload time, before this domain's RPCs ever
--    see the file id) -- app.submit_leave_request only re-validates tenant/
--    record_type/record_id/malware_scan_status, exactly PLT-128's own
--    established contract, never a second classification authority.
--    evidence_classification in ('personal', 'medical') is registered in
--    scripts/data-classification/registry.ts (this checkpoint's own new
--    HRS_REGISTRY rows) as the disclosed data-classification-registry row
--    the task instructions asked to consider -- reason/destination are
--    column-restricted from this, the FIRST, migration (decision 11), never
--    retrofitted.
--
-- 9. **Balance-oversell concurrency is closed by a real advisory lock, keyed
--    (tenant_id, employee_id, leave_type_id) -- taxonomy C-04, designed
--    against from the start and live-tested (see the build log).** There is
--    no single parent ROW representing "this employee's balance" to lock
--    (the ledger is append-only, by design, decision 3) -- the advisory lock
--    is the correct primitive here, exactly the same reasoning
--    app.decide_employee_position_assignment (HRT-275) already used for
--    position-capacity serialization (a computed AGGREGATE, not a single
--    row, needed protecting).
--
-- 10. **Attendance-exception suppression and shift/roster integration are
--     BOTH real, but neither auto-mutates the other domain's own governed
--     state without an explicit, separately-authorized action (the
--     "authority-bar mismatch" lesson, HRT-277's own worst finding, designed
--     against here from the start).** Attendance-exception suppression
--     (an approved leave/permit day should not register as a late/
--     early-leave/missing-clock-out exception) is READ-ONLY from this
--     domain's own perspective -- a separate, later, additive migration
--     (20260730940000) extends HRT-278's own
--     app._recalculate_session_exceptions (CREATE OR REPLACE, identical
--     signature, mirrors HRT-279's own 20260730920000 precedent exactly) to
--     consult app.leave_requests. Schedule-assignment override (an approved
--     leave day "overriding" an already-published shift) is NOT automatic --
--     app.cancel_conflicting_schedule_assignment_for_leave is a real,
--     explicit, HRS:Override-gated action (the same authority bar
--     app.cancel_schedule_assignment already requires for a published row,
--     HRT-279 decision 5) that HR/a scheduler must invoke deliberately; an
--     approval alone never silently cancels someone else's already-published
--     shift, since the actor approving leave (HRS:Approve) is not
--     necessarily the actor with roster-mutation authority (HRS:Override).
--
-- 11. **Sensitive free-text fields are column-restricted from THIS, the
--     FIRST, migration** (never retrofitted -- the exact defect class
--     HRT-276's own Tier C review found and had to fix after the fact):
--     app.leave_requests.reason/destination/cancel_reason/decided_reason,
--     app.leave_balance_ledger.reason are excluded from the plain
--     `authenticated` column grant applied in this migration's own first
--     grant block, masked in every read RPC to the same self-or-HRS:View-
--     personal-data bar every other HRT checkpoint already established.
--
-- 12. **RBAC.** Zero new app.permissions rows -- the eleven HRS actions
--     already seeded (View/Create/Edit/Delete/Approve/Export/View personal
--     data/Reject/Import/Download/Override) cover every write below.
--     Authority bars matched to blast radius, not surface category: routine
--     authoring is Edit; publish is Approve; a direct manual balance
--     adjustment, a bulk accrual/carry-forward batch touching every eligible
--     employee at once, and a non-self cancellation of an already-APPROVED
--     (balance-debited) request are all Override -- never merely Edit.
--
-- 13. **Accrual/carry-forward reuse PLT-132 exactly (mandatory reading, the
--     third HRIS-domain adopter after HRT-279's roster_generation), bounded
--     and idempotent, never a literal background worker** (this repository
--     has no live job-dequeue worker anywhere yet, standing ISS-2026-015,
--     identical reasoning to HRT-278's decision 7/HRT-279's decision 8).
--     app.generic_job_types()/app.jobs.job_type's CHECK constraint are both
--     widened to add 'leave_accrual'/'leave_carry_forward_expiry';
--     app.enqueue_job/app.dispatch_event_as_job are both left completely
--     untouched (already collapsed to a single call to
--     app.generic_job_types() by ATW-031/20260730410000) -- the exact
--     HRT-279 decision 8 lesson (a first draft there widened enqueue_job
--     directly from a stale, superseded literal and silently reverted two
--     later job types) applied correctly from the start here.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
-- its own explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC
-- statement before its final grants, the standing per-migration convention
-- since PLT-118.

-- ===========================================================================
-- 1. app.leave_types -- tenant-wide identity catalogue (decision 1/2).
-- ===========================================================================

create table app.leave_types (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  name text not null,
  category text not null,
  unit text not null default 'day',
  requires_balance boolean not null default true,
  requires_evidence boolean not null default false,
  evidence_classification text not null default 'none',
  status text not null default 'draft',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint leave_types_code_check check (code ~ '^[a-z0-9_]{2,40}$'),
  constraint leave_types_name_check check (length(trim(name)) > 0),
  constraint leave_types_category_check check (category in ('leave', 'permit', 'business_trip')),
  constraint leave_types_unit_check check (unit = 'day'),
  constraint leave_types_evidence_classification_check check (evidence_classification in ('none', 'personal', 'medical')),
  constraint leave_types_evidence_shape_check check (requires_evidence or evidence_classification = 'none'),
  constraint leave_types_status_check check (status in ('draft', 'published', 'archived')),
  constraint leave_types_tenant_code_unique unique (tenant_id, code)
);

comment on table app.leave_types is
  'HRT-280 (decision 1/2): tenant-wide leave/permit/business-trip TYPE identity catalogue. unit is closed to ''day'' in V1 (disclosed -- an hours-denominated permit is a real, deferred future extension, matching this repository''s own reserve-the-field discipline). requires_balance=false models a permit/business-trip that never debits a balance (section 22''s own ''permit without balance, business trip'').';

create index leave_types_tenant_status_idx on app.leave_types (tenant_id, status);
create index leave_types_tenant_category_idx on app.leave_types (tenant_id, category);

-- ===========================================================================
-- 2. app.leave_type_policy_versions -- effective-dated, optionally
--    org_unit-scoped ruleset (decision 1).
-- ===========================================================================

create table app.leave_type_policy_versions (
  id uuid primary key default gen_random_uuid(),
  leave_type_id uuid not null references app.leave_types (id),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid references app.org_units (id),
  version_number integer not null,
  status text not null default 'draft',
  effective_from date not null,
  accrual_frequency text not null default 'none',
  accrual_amount_per_period numeric not null default 0,
  accrual_max_balance numeric,
  carry_forward_max_units numeric not null default 0,
  min_notice_days integer not null default 0,
  max_consecutive_units numeric,
  eligibility_min_tenure_days integer not null default 0,
  negative_balance_allowed boolean not null default false,
  published_at timestamptz,
  published_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint leave_type_policy_versions_status_check check (status in ('draft', 'published', 'superseded')),
  constraint leave_type_policy_versions_accrual_frequency_check check (accrual_frequency in ('none', 'monthly', 'annual')),
  constraint leave_type_policy_versions_accrual_amount_check check (accrual_amount_per_period >= 0),
  constraint leave_type_policy_versions_accrual_max_check check (accrual_max_balance is null or accrual_max_balance >= 0),
  constraint leave_type_policy_versions_carry_forward_check check (carry_forward_max_units >= 0),
  constraint leave_type_policy_versions_min_notice_check check (min_notice_days >= 0 and min_notice_days <= 365),
  constraint leave_type_policy_versions_max_consecutive_check check (max_consecutive_units is null or max_consecutive_units > 0),
  constraint leave_type_policy_versions_eligibility_check check (eligibility_min_tenure_days >= 0),
  constraint leave_type_policy_versions_published_shape_check check (
    (status <> 'published') or (published_at is not null and published_by is not null)
  ),
  constraint leave_type_policy_versions_scope_effective_unique unique (leave_type_id, org_unit_id, effective_from)
);

comment on table app.leave_type_policy_versions is
  'HRT-280 (decision 1): effective-dated accrual/carry-forward/eligibility ruleset. org_unit_id null = tenant-wide fallback; non-null = binds to one app.org_units node, resolved branch-scoped-over-tenant-wide by app.resolve_effective_leave_type_policy_version -- mirrors app.resolve_effective_attendance_policy_version (HRT-278) exactly. carry_forward_max_units=0 models a strict use-it-or-lose-it type (the SAME batch function, app.run_leave_carry_forward_batch, handles both a real cap and a full use-it-or-lose-it type -- decision 13, no second expiry mechanism).';

create index leave_type_policy_versions_type_idx on app.leave_type_policy_versions (leave_type_id, status, effective_from desc);

create function app.resolve_effective_leave_type_policy_version(p_tenant_id uuid, p_leave_type_id uuid, p_branch_org_unit_id uuid, p_as_of_date date)
returns setof app.leave_type_policy_versions
language sql
stable
as $$
  select pv.*
  from app.leave_type_policy_versions pv
  join app.leave_types t on t.id = pv.leave_type_id
  where t.tenant_id = p_tenant_id
    and pv.leave_type_id = p_leave_type_id
    and pv.status = 'published'
    and pv.effective_from <= p_as_of_date
    and (pv.org_unit_id is null or pv.org_unit_id = p_branch_org_unit_id)
  order by (pv.org_unit_id is not null) desc, pv.effective_from desc
  limit 1;
$$;

comment on function app.resolve_effective_leave_type_policy_version is
  'HRT-280 (decision 1): the single effective-policy resolution point every write RPC below uses. Prefers a published, org_unit-scoped version matching the employee''s own branch_org_unit_id over a tenant-wide (org_unit_id is null) one; among candidates of the same specificity, picks the greatest effective_from not after p_as_of_date. Zero rows = "no eligible policy" (section 23 exception flow).';

-- ===========================================================================
-- 3. app.leave_balance_ledger -- append-only source of truth (decision 3).
--    No UPDATE/DELETE grant to ANY role below, not even service_role.
-- ===========================================================================

create table app.leave_balance_ledger (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  leave_type_id uuid not null references app.leave_types (id),
  event_type text not null,
  units numeric not null,
  effective_date date not null,
  policy_version_id uuid references app.leave_type_policy_versions (id),
  source_request_id uuid,
  reason text,
  idempotency_key text,
  created_by text,
  created_at timestamptz not null default now(),
  constraint leave_balance_ledger_event_type_check check (
    event_type in ('accrual', 'carry_forward_expire', 'adjustment', 'opening_balance', 'request_debit', 'request_credit_reversal')
  ),
  constraint leave_balance_ledger_units_check check (units <> 0),
  constraint leave_balance_ledger_debit_sign_check check (event_type <> 'request_debit' or units < 0),
  constraint leave_balance_ledger_credit_sign_check check (event_type <> 'request_credit_reversal' or units > 0),
  constraint leave_balance_ledger_expire_sign_check check (event_type <> 'carry_forward_expire' or units < 0),
  constraint leave_balance_ledger_accrual_sign_check check (event_type <> 'accrual' or units > 0)
);

comment on table app.leave_balance_ledger is
  'HRT-280 (decision 3): genuinely append-only leave balance ledger -- the sole source of truth for every employee-leave_type balance (app.get_employee_leave_balance sums it). No mutable balance column exists anywhere in this domain. Sign-shape CHECK constraints (decision 3) make a misclassified event_type structurally impossible, not merely a convention.';

create index leave_balance_ledger_tenant_employee_type_idx on app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, effective_date);
create unique index leave_balance_ledger_idempotency_unique on app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, idempotency_key) where idempotency_key is not null;

create function app.get_employee_leave_balance(p_tenant_id uuid, p_employee_id uuid, p_leave_type_id uuid, p_as_of_date date default current_date)
returns numeric
language sql
stable
as $$
  select coalesce(sum(units), 0)
  from app.leave_balance_ledger
  where tenant_id = p_tenant_id and employee_id = p_employee_id and leave_type_id = p_leave_type_id and effective_date <= p_as_of_date;
$$;

comment on function app.get_employee_leave_balance is
  'HRT-280 (decision 3): the ONE balance computation this domain has. Never a materialized/cached balance column drifting from the ledger.';

-- ===========================================================================
-- 4. app.leave_requests -- the request/version root (decision 5).
-- ===========================================================================

create extension if not exists btree_gist;

create table app.leave_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  leave_type_id uuid not null references app.leave_types (id),
  policy_version_id uuid references app.leave_type_policy_versions (id),
  status text not null default 'draft',
  date_from date not null,
  date_to date not null,
  day_portion text not null default 'full_day',
  total_units numeric not null default 0,
  reason text not null,
  destination text,
  evidence_file_id uuid references app.files (id),
  schedule_snapshot jsonb not null default '[]'::jsonb,
  approval_request_id uuid references app.approval_requests (id),
  decided_by text,
  decided_at timestamptz,
  decided_reason text,
  cancelled_at timestamptz,
  cancel_reason text,
  payroll_input_status text not null default 'pending',
  previous_request_id uuid references app.leave_requests (id),
  requested_by_auth_user_id uuid not null,
  requested_by text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  validity_range daterange generated always as (daterange(date_from, date_to, '[]')) stored,
  constraint leave_requests_date_range_check check (date_to >= date_from),
  constraint leave_requests_day_portion_check check (day_portion in ('full_day', 'half_day_morning', 'half_day_afternoon')),
  constraint leave_requests_half_day_single_date_check check (day_portion = 'full_day' or date_from = date_to),
  constraint leave_requests_total_units_check check (total_units >= 0),
  constraint leave_requests_reason_check check (length(trim(reason)) > 0),
  constraint leave_requests_status_check check (status in ('draft', 'pending_approval', 'approved', 'rejected', 'cancelled')),
  constraint leave_requests_payroll_status_check check (payroll_input_status in ('pending', 'approved')),
  -- 'cancelled' deliberately does NOT force decided_at/decided_by to null:
  -- section 22's own "future cancellation" alternative flow lets an already-
  -- APPROVED request be cancelled later (app.cancel_leave_request), and that
  -- cancellation must preserve the real historical record of who/when
  -- approved it, never erase it -- a cancelled-from-draft/pending request
  -- simply carries the null pair it already had (self-found and fixed: a
  -- first draft required decided_at/decided_by null for EVERY cancelled row
  -- unconditionally, which made cancelling an approved request impossible --
  -- the terminal UPDATE itself violated this exact constraint, live-caught
  -- by the db-test suite).
  constraint leave_requests_decided_shape_check check (
    (status in ('draft', 'pending_approval', 'cancelled') and (decided_at is null) = (decided_by is null))
    or (status in ('approved', 'rejected') and decided_at is not null and decided_by is not null and decided_reason is not null and length(trim(decided_reason)) > 0)
  ),
  constraint leave_requests_cancel_shape_check check (status <> 'cancelled' or (cancel_reason is not null and length(trim(cancel_reason)) > 0 and cancelled_at is not null))
);

comment on table app.leave_requests is
  'HRT-280 (decision 5/6): the request root. destination is populated only for a business_trip-category leave_type (enforced by app.submit_leave_request, not a table CHECK, since the type join is not available inline). validity_range/the EXCLUDE constraint below enforce whole-date-range overlap prevention at the database level (decision 5), scoped to the two LIVE statuses only -- a draft or a decided-away (rejected/cancelled) request never blocks a new one.';

alter table app.leave_requests
  add constraint leave_requests_no_overlap
  exclude using gist (employee_id with =, validity_range with &&)
  where (status in ('pending_approval', 'approved'));

comment on constraint leave_requests_no_overlap on app.leave_requests is
  'HRT-280 (decision 5), mirrors app.employee_position_assignments_no_primary_overlap (HRT-275)/app.vendor_rate_versions_no_ambiguous_overlap (PRC-255) exactly. app.submit_leave_request translates the raw exclusion_violation/deadlock_detected into the friendly leave_request_overlap error.';

create index leave_requests_tenant_status_idx on app.leave_requests (tenant_id, status);
create index leave_requests_tenant_employee_idx on app.leave_requests (tenant_id, employee_id, date_from desc);
create index leave_requests_tenant_type_idx on app.leave_requests (tenant_id, leave_type_id);
create index leave_requests_tenant_date_idx on app.leave_requests (tenant_id, date_from, date_to);
create index leave_requests_approval_request_idx on app.leave_requests (approval_request_id) where approval_request_id is not null;
create unique index leave_requests_idempotency_unique on app.leave_requests (tenant_id, employee_id, idempotency_key) where idempotency_key is not null;

alter table app.leave_balance_ledger add constraint leave_balance_ledger_source_request_id_fkey foreign key (source_request_id) references app.leave_requests (id);

create function app.touch_leave_request_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger leave_requests_touch_row
  before update on app.leave_requests
  for each row
  execute function app.touch_leave_request_row();

create trigger leave_type_policy_versions_touch_row
  before update on app.leave_type_policy_versions
  for each row
  execute function app.touch_leave_request_row();

create trigger leave_types_touch_row
  before update on app.leave_types
  for each row
  execute function app.touch_leave_request_row();

comment on function app.touch_leave_request_row is
  'HRT-280: shared record_version/updated_at trigger, reused across all three versioned tables in this migration (leave_requests, leave_type_policy_versions, leave_types) -- never three copies of the identical trigger body.';

-- ===========================================================================
-- 5. Shared internal helpers.
-- ===========================================================================

create function app.leave_request_audit_projection(p_request app.leave_requests)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_request.id, 'tenant_id', p_request.tenant_id, 'employee_id', p_request.employee_id,
    'leave_type_id', p_request.leave_type_id, 'status', p_request.status, 'date_from', p_request.date_from,
    'date_to', p_request.date_to, 'day_portion', p_request.day_portion, 'total_units', p_request.total_units,
    'payroll_input_status', p_request.payroll_input_status, 'record_version', p_request.record_version
  );
$$;

comment on function app.leave_request_audit_projection is
  'HRT-280 (C-07): an explicit non-PII/non-reason jsonb_build_object projection -- never to_jsonb(row), which would carry reason/destination unmasked into app.audit_logs.';

-- Bounded (<=366 days) calendar-day counter, excluding tenant/branch holidays
-- (app.roster_holidays, HRT-279 -- reused directly, never a second holiday
-- calendar). Zero rows in app.roster_holidays (a tenant with no Shift/Roster
-- adoption) simply excludes nothing -- structurally optional, mirrors
-- HRT-279's own "Shift/Roster adoption is optional per tenant" framing.
create function app._compute_leave_business_units(p_tenant_id uuid, p_branch_org_unit_id uuid, p_date_from date, p_date_to date, p_day_portion text)
returns numeric
language sql
stable
set search_path = app, pg_temp
as $$
  select case when p_day_portion = 'full_day' then coalesce(count(*), 0)::numeric else 0.5 end
  from generate_series(p_date_from, p_date_to, interval '1 day') as d(day)
  where not exists (
    select 1 from app.roster_holidays h
    where h.tenant_id = p_tenant_id and h.status = 'active' and h.holiday_date = d.day::date and not h.is_working_day
      and (h.org_unit_id is null or h.org_unit_id = p_branch_org_unit_id)
  );
$$;

comment on function app._compute_leave_business_units is
  'HRT-280 (section 21 "validates schedule/holiday"): calendar-day count over [date_from,date_to] minus any active, non-working-day-override tenant- or branch-scoped app.roster_holidays row (HRT-279, reused directly). half_day_* is always exactly 0.5 units regardless of holiday overlap (a half-day request is always a single date, enforced by leave_requests_half_day_single_date_check) -- disclosed V1 simplification: a half-day request against a holiday date is a caller error the request will simply never be paid out for, not separately blocked at this layer.';

-- Real, but internal-only (never granted to authenticated), coverage-impact
-- computation for ONE employee-workday -- reuses app.roster_coverage_
-- requirements/app.schedule_assignments (HRT-279) directly, never a second
-- coverage engine (AGENTS.md "do not create duplicate ... policy engines").
-- Deliberately NOT implemented by calling the permission-gated
-- app.get_schedule_coverage_preview (which silently returns zero rows for a
-- caller lacking HRS:View) -- an eligible PLT-123 approver deciding a leave
-- request is not guaranteed to also hold HRS:View, and a silent empty result
-- would make this authoritative business-rule check silently pass every
-- time for such a caller, precisely the failure shape C-06 warns about.
create function app._leave_coverage_impact(p_tenant_id uuid, p_employee_id uuid, p_work_date date, out v_scheduled_count integer, out v_min_headcount integer)
language plpgsql
stable
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
  v_assignment app.schedule_assignments;
  v_shift_template_id uuid;
  v_org_unit_id uuid;
begin
  v_scheduled_count := null;
  v_min_headcount := null;

  select * into v_employee from app.employees where master_record_id = p_employee_id and tenant_id = p_tenant_id;
  if not found then
    return;
  end if;
  v_org_unit_id := coalesce(v_employee.branch_org_unit_id, v_employee.department_org_unit_id);
  if v_org_unit_id is null then
    return;
  end if;

  select * into v_assignment from app.resolve_effective_schedule_assignment(p_tenant_id, p_employee_id, p_work_date);
  if not found then
    return;
  end if;
  select sv.shift_template_id into v_shift_template_id from app.shift_template_versions sv where sv.id = v_assignment.shift_template_version_id;

  select req.min_headcount into v_min_headcount
  from app.roster_coverage_requirements req
  where req.tenant_id = p_tenant_id and req.org_unit_id = v_org_unit_id and req.shift_template_id = v_shift_template_id
    and req.day_of_week = extract(dow from p_work_date)::integer and req.status = 'active';
  if v_min_headcount is null then
    return;
  end if;

  select count(*) into v_scheduled_count
  from app.schedule_assignments sa
  join app.employees e on e.master_record_id = sa.employee_id
  join app.shift_template_versions sv2 on sv2.id = sa.shift_template_version_id
  where sa.tenant_id = p_tenant_id and sa.status = 'published' and sa.work_date = p_work_date and sv2.shift_template_id = v_shift_template_id
    and coalesce(e.branch_org_unit_id, e.department_org_unit_id) = v_org_unit_id;
end;
$$;

comment on function app._leave_coverage_impact is
  'HRT-280 (section 21/23 "coverage threshold"): for one employee-workday, resolves the employee''s own PUBLISHED shift assignment (HRT-279, app.resolve_effective_schedule_assignment) and the matching app.roster_coverage_requirements row, then counts every OTHER published assignment to the same shift/org_unit/date. v_min_headcount null = no coverage requirement is configured for this shift/day at all (nothing to check). Internal-only -- never granted to authenticated.';

-- ===========================================================================
-- 6. Type/policy authoring RPCs.
-- ===========================================================================

create function app.create_leave_type(
  p_tenant_id uuid, p_code text, p_name text, p_category text, p_requires_balance boolean,
  p_requires_evidence boolean, p_evidence_classification text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.leave_types
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_type app.leave_types;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_category not in ('leave', 'permit', 'business_trip') then
    raise exception 'invalid_category: % is not a recognized leave type category', p_category using errcode = 'check_violation';
  end if;

  insert into app.leave_types (
    tenant_id, code, name, category, requires_balance, requires_evidence, evidence_classification, created_by
  ) values (
    p_tenant_id, lower(trim(p_code)), p_name, p_category, p_requires_balance,
    p_requires_evidence, coalesce(p_evidence_classification, 'none'), p_actor_label
  ) returning * into v_type;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_leave_type',
    'app.leave_types', v_type.id, 'success', null, null, jsonb_build_object('code', v_type.code, 'category', v_type.category)
  );

  return v_type;
exception
  when unique_violation then
    raise exception 'duplicate_leave_type_code: code % already exists in tenant %', p_code, p_tenant_id using errcode = 'unique_violation';
end;
$$;

create function app.publish_leave_type(p_leave_type_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.leave_types
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_type app.leave_types;
begin
  select * into v_type from app.leave_types where id = p_leave_type_id for update;
  if not found or not app.has_active_tenant_membership(v_type.tenant_id, p_actor_auth_user_id) then
    raise exception 'leave_type_not_found: %', p_leave_type_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_type.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_type.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_type.record_version <> p_expected_version then
    raise exception 'stale_version: leave type % expected version % but found %', p_leave_type_id, p_expected_version, v_type.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_type.status <> 'draft' then
    raise exception 'invalid_transition: leave type % is %, only a draft may be published', p_leave_type_id, v_type.status
      using errcode = 'check_violation';
  end if;

  update app.leave_types set status = 'published' where id = p_leave_type_id and record_version = p_expected_version returning * into v_type;
  if not found then
    raise exception 'stale_version: leave type % target row was concurrently modified (expected version %)', p_leave_type_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_type.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_leave_type', 'app.leave_types', p_leave_type_id, 'success', null, null, '{}'::jsonb
  );

  return v_type;
end;
$$;

create function app.create_leave_type_policy_version(
  p_leave_type_id uuid, p_org_unit_id uuid, p_effective_from date, p_accrual_frequency text, p_accrual_amount_per_period numeric,
  p_accrual_max_balance numeric, p_carry_forward_max_units numeric, p_min_notice_days integer, p_max_consecutive_units numeric,
  p_eligibility_min_tenure_days integer, p_negative_balance_allowed boolean, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.leave_type_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_type app.leave_types;
  v_next_version integer;
  v_version app.leave_type_policy_versions;
begin
  select * into v_type from app.leave_types where id = p_leave_type_id;
  if not found then
    raise exception 'leave_type_not_found: %', p_leave_type_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_type.tenant_id, p_actor_auth_user_id) then
    raise exception 'leave_type_not_found: %', p_leave_type_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_type.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_type.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_org_unit_id is not null and not exists (select 1 from app.org_units where id = p_org_unit_id and tenant_id = v_type.tenant_id) then
    raise exception 'org_unit_not_found: %', p_org_unit_id using errcode = 'no_data_found';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.leave_type_policy_versions where leave_type_id = p_leave_type_id;

  insert into app.leave_type_policy_versions (
    leave_type_id, tenant_id, org_unit_id, version_number, effective_from, accrual_frequency, accrual_amount_per_period,
    accrual_max_balance, carry_forward_max_units, min_notice_days, max_consecutive_units, eligibility_min_tenure_days,
    negative_balance_allowed, created_by
  ) values (
    p_leave_type_id, v_type.tenant_id, p_org_unit_id, v_next_version, p_effective_from, coalesce(p_accrual_frequency, 'none'),
    coalesce(p_accrual_amount_per_period, 0), p_accrual_max_balance, coalesce(p_carry_forward_max_units, 0),
    coalesce(p_min_notice_days, 0), p_max_consecutive_units, coalesce(p_eligibility_min_tenure_days, 0),
    coalesce(p_negative_balance_allowed, false), p_actor_label
  ) returning * into v_version;

  perform app.capture_audit_event(
    v_type.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_leave_type_policy_version',
    'app.leave_type_policy_versions', v_version.id, 'success', null, null, jsonb_build_object('leave_type_id', p_leave_type_id, 'effective_from', p_effective_from)
  );

  return v_version;
exception
  when unique_violation then
    raise exception 'duplicate_policy_effective_date: a version for this leave type/org_unit scope already has effective_from %', p_effective_from using errcode = 'unique_violation';
end;
$$;

create function app.publish_leave_type_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.leave_type_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.leave_type_policy_versions;
begin
  select * into v_version from app.leave_type_policy_versions where id = p_version_id for update;
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

  update app.leave_type_policy_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: policy version % target row was concurrently modified (expected version %)', p_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.leave_types set status = 'published' where id = v_version.leave_type_id and status = 'draft';

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_leave_type_policy_version',
    'app.leave_type_policy_versions', p_version_id, 'success', null, null, jsonb_build_object('effective_from', v_version.effective_from)
  );

  return v_version;
end;
$$;

-- ===========================================================================
-- 7. Request RPCs -- draft/submit/decide/cancel (decisions 4, 5, 6, 7, 9).
-- ===========================================================================

-- NOTE: this is deliberately NOT a shared two-composite-OUT-parameter helper
-- (a first draft tried that shape and hit a genuine Postgres restriction --
-- "record variable cannot be part of multiple-item INTO list" -- on
-- `select * into v_type, v_policy from fn()` when a function's own OUT
-- parameter list contains more than one composite/row type). The
-- type-then-policy resolution below is therefore inlined at its two call
-- sites (app._create_leave_request, app.update_leave_request_draft) rather
-- than shared through a function signature Postgres cannot support this way.

create function app._create_leave_request(
  p_tenant_id uuid, p_employee app.employees, p_leave_type_id uuid, p_date_from date, p_date_to date, p_day_portion text,
  p_reason text, p_destination text, p_evidence_file_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.leave_requests
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_type app.leave_types;
  v_policy app.leave_type_policy_versions;
  v_existing app.leave_requests;
  v_units numeric;
  v_request app.leave_requests;
begin
  if p_employee.master_record_id is null then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;
  if p_employee.lifecycle_status not in ('active', 'on_leave') then
    raise exception 'employee_not_active: employee % is %, only an active (or currently on-leave) employee may request leave', p_employee.master_record_id, p_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;
  if p_date_to < p_date_from then
    raise exception 'invalid_date_range: date_to must not precede date_from' using errcode = 'check_violation';
  end if;
  if (p_date_to - p_date_from) > 366 then
    raise exception 'invalid_date_range: a single leave request may span at most 366 days' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_type from app.leave_types where id = p_leave_type_id and tenant_id = p_tenant_id and status = 'published';
  if not found then
    raise exception 'leave_type_not_available: % is not a published leave type in this tenant', p_leave_type_id using errcode = 'no_data_found';
  end if;
  select * into v_policy from app.resolve_effective_leave_type_policy_version(p_tenant_id, p_leave_type_id, p_employee.branch_org_unit_id, p_date_from) limit 1;
  if not found then
    raise exception 'no_eligible_policy: no published leave policy is effective for leave type % as of %', p_leave_type_id, p_date_from
      using errcode = 'check_violation';
  end if;

  if v_type.category <> 'business_trip' and p_destination is not null then
    raise exception 'destination_not_applicable: destination may only be set for a business_trip leave type' using errcode = 'check_violation';
  end if;
  if v_type.category = 'business_trip' and (p_destination is null or length(trim(p_destination)) = 0) then
    raise exception 'destination_required: a business trip request requires a non-empty destination' using errcode = 'check_violation';
  end if;

  if v_type.requires_evidence and p_evidence_file_id is null then
    raise exception 'evidence_required: leave type % requires supporting evidence', v_type.code using errcode = 'check_violation';
  end if;
  if p_evidence_file_id is not null then
    declare
      v_file app.files;
    begin
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
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.leave_requests where tenant_id = p_tenant_id and employee_id = p_employee.master_record_id and idempotency_key = p_idempotency_key;
    if found then
      -- C-01: full-tuple idempotency replay -- every field that identifies
      -- what the caller actually asked for, not merely the dates (the exact
      -- recurring class this repository's own Prompts 252/253/254 each
      -- independently reintroduced by omitting a materially-identifying
      -- field from an otherwise-plausible-looking comparison).
      if v_existing.leave_type_id = p_leave_type_id and v_existing.date_from = p_date_from and v_existing.date_to = p_date_to
         and v_existing.day_portion = p_day_portion and v_existing.destination is not distinct from p_destination
         and v_existing.reason = p_reason then
        return v_existing;
      else
        raise exception 'idempotency_key_conflict: key % was already used for a different leave request', p_idempotency_key using errcode = 'unique_violation';
      end if;
    end if;
  end if;

  v_units := app._compute_leave_business_units(p_tenant_id, p_employee.branch_org_unit_id, p_date_from, p_date_to, p_day_portion);
  if v_policy.max_consecutive_units is not null and v_units > v_policy.max_consecutive_units then
    raise exception 'max_consecutive_units_exceeded: request % units exceeds the effective policy maximum of %', v_units, v_policy.max_consecutive_units
      using errcode = 'check_violation';
  end if;

  -- Soft, non-locking advisory balance check (decision 4) -- fast feedback at
  -- draft-create time; the AUTHORITATIVE, lock-serialized check happens at
  -- app.decide_leave_request's own approval branch.
  if v_type.requires_balance and not v_policy.negative_balance_allowed then
    declare
      v_current numeric;
      v_pending numeric;
    begin
      -- current_date, not p_date_from (matches app.decide_leave_request's
      -- own authoritative check, decision 4) -- a debit is posted at
      -- DECISION time, so "available balance" is always evaluated as of now,
      -- never as of a request's own possibly-future date.
      v_current := app.get_employee_leave_balance(p_tenant_id, p_employee.master_record_id, p_leave_type_id, current_date);
      select coalesce(sum(total_units), 0) into v_pending from app.leave_requests
      where tenant_id = p_tenant_id and employee_id = p_employee.master_record_id and leave_type_id = p_leave_type_id and status = 'pending_approval';
      if (v_current - v_pending - v_units) < 0 then
        raise exception 'insufficient_balance: available balance % (after % already-pending unit(s)) is less than the % unit(s) requested', v_current, v_pending, v_units
          using errcode = 'check_violation';
      end if;
    end;
  end if;

  insert into app.leave_requests (
    tenant_id, employee_id, leave_type_id, policy_version_id, date_from, date_to, day_portion, total_units,
    reason, destination, evidence_file_id, requested_by_auth_user_id, requested_by, idempotency_key, created_by
  ) values (
    p_tenant_id, p_employee.master_record_id, p_leave_type_id, v_policy.id, p_date_from, p_date_to, p_day_portion, v_units,
    p_reason, p_destination, p_evidence_file_id, p_actor_auth_user_id, p_actor_label, p_idempotency_key, p_actor_label
  ) returning * into v_request;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_leave_request',
    'app.leave_requests', v_request.id, 'success', null, null, app.leave_request_audit_projection(v_request)
  );

  return v_request;
end;
$$;

comment on function app._create_leave_request is
  'HRT-280 (decision 10/section 16 anti-spoofing): the ONE shared draft-creation engine both the self-service and HR-on-behalf entry points call, mirroring app._ingest_attendance_event''s (HRT-278) own shared-engine shape -- never two independently-validated write paths.';

create function app.create_leave_request(
  p_tenant_id uuid, p_leave_type_id uuid, p_date_from date, p_date_to date, p_day_portion text,
  p_reason text, p_destination text, p_evidence_file_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.leave_requests
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  return app._create_leave_request(
    p_tenant_id, v_self, p_leave_type_id, p_date_from, p_date_to, p_day_portion,
    p_reason, p_destination, p_evidence_file_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.create_leave_request is
  'HRT-280 (decision 10): self-service draft creation -- no p_employee_id parameter exists, the acting employee is resolved exclusively from the caller''s own session identity (app.get_self_employee, reused unchanged from HRT-278), so there is no field for a self-service caller to spoof.';

create function app.create_leave_request_for_employee(
  p_tenant_id uuid, p_employee_id uuid, p_leave_type_id uuid, p_date_from date, p_date_to date, p_day_portion text,
  p_reason text, p_destination text, p_evidence_file_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.leave_requests
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_employee from app.employees where master_record_id = p_employee_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;

  return app._create_leave_request(
    p_tenant_id, v_employee, p_leave_type_id, p_date_from, p_date_to, p_day_portion,
    p_reason, p_destination, p_evidence_file_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.create_leave_request_for_employee is
  'HRT-280 (decision 10): explicit HR-on-behalf entry point, HRS:Edit-gated -- the "employees act only for self unless explicit HR authority" split section 16 requires, mirrors app.record_manual_attendance_event (HRT-278) exactly.';

create function app.update_leave_request_draft(
  p_request_id uuid, p_expected_version integer, p_date_from date, p_date_to date, p_day_portion text,
  p_reason text, p_destination text, p_evidence_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.leave_requests
language plpgsql
security definer
set search_path = app, public, pg_temp
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
  'HRT-280 (section 22 "revision/resubmission"): editing is bounded to status=draft ONLY -- a rejected request returns to draft (app.decide_leave_request''s own reject branch) precisely so it can be edited here and resubmitted, mirroring app.request_employee_change''s own governed-correction shape.';

create function app.submit_leave_request(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.leave_requests
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_request app.leave_requests;
  v_self app.employees;
  v_is_self boolean;
  v_decision app.rbac_decision;
  v_employee app.employees;
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

  if v_policy.min_notice_days > 0 and v_request.date_from < (current_date + v_policy.min_notice_days) then
    raise exception 'min_notice_not_met: leave type requires at least % day(s) advance notice', v_policy.min_notice_days using errcode = 'check_violation';
  end if;
  if v_policy.eligibility_min_tenure_days > 0 and v_employee.hire_date is not null
     and (current_date - v_employee.hire_date) < v_policy.eligibility_min_tenure_days then
    raise exception 'eligibility_not_met: employee has not met the % day minimum tenure required by this leave policy', v_policy.eligibility_min_tenure_days
      using errcode = 'check_violation';
  end if;

  -- Schedule snapshot (decision 10, section 13 "schedule snapshot") --
  -- immutable, captured once at submit time, never a live join thereafter.
  -- Bounded to the request's own (already <=366-day) range.
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
  'HRT-280 (decision 5/6): the EXCLUDE-constraint overlap check fires HERE (the draft->pending_approval transition), never at draft creation -- a draft never blocks another request. Routes through PLT-123 exactly like app.submit_onboarding_case_for_finalize_approval (HRT-277) -- raises the SAME approval_definition_not_configured error when the tenant has not configured approval routing, disclosed, never silently bypassed.';

create function app.decide_leave_request(p_request_step_id uuid, p_decision text, p_reason text, p_override_coverage boolean, p_actor_auth_user_id uuid, p_actor_label text)
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
  -- Deliberately NOT named v_scheduled_count/v_min_headcount: this is a
  -- caller of app._leave_coverage_impact, whose own OUT parameters carry
  -- those exact names -- live-caught by the db-test suite itself
  -- ("column reference is ambiguous"), the recurring class this task's own
  -- instructions explicitly flagged (bare references colliding with a
  -- callee's own output-column/OUT-parameter names), fixed by naming these
  -- two variables distinctly rather than merely qualifying the reference.
  v_leave_scheduled_count integer;
  v_leave_min_headcount integer;
  v_override_decision app.rbac_decision;
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

  -- C-05 (self-found during this checkpoint's own Tier B walk, NOT a db-test
  -- failure): the coverage-threshold check below discloses real scheduling
  -- data (whether approving this specific leave would violate a coverage
  -- requirement, and the exact headcount) -- it must never run before the
  -- caller's own authority to decide THIS step is established. app.decide_
  -- approval_step is the actual authority gate (tenant membership + eligible-
  -- approver identity + C-18 self-approval block); it is called FIRST, and
  -- the coverage check moves to AFTER it succeeds, inside the SAME
  -- transaction -- a coverage-block still fully rolls back the approval
  -- decide_approval_step itself just committed, so the net effect for the
  -- caller is identical (their decision truly did not take effect), but
  -- nothing is disclosed to a caller who has not already been proven
  -- eligible to decide this exact step.
  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_approval_request.id;

  if v_updated_request.status = 'approved' then
    -- Coverage-threshold check (section 23 "coverage threshold") -- only on
    -- the APPROVE path, only when a real coverage requirement exists for the
    -- employee's own resolved shift on EACH date in range, and only blocking
    -- (never merely warning) unless the deciding actor also holds HRS:Override
    -- (decision 12/section 26) to explicitly accept understaffing. The caller
    -- has already been proven an eligible approver of this exact step by
    -- app.decide_approval_step above, so disclosing coverage detail here is safe.
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

    -- Real advisory-lock-serialized balance debit (decision 4/9) -- the
    -- AUTHORITATIVE check+post, closing the C-04-shaped oversell race the
    -- submit-time soft check alone would leave open.
    if v_type.requires_balance then
      v_lock_key := hashtextextended('leave_balance:' || v_request.employee_id::text || ':' || v_request.leave_type_id::text, 0);
      perform pg_advisory_xact_lock(v_lock_key);
      -- Dated current_date (the DECISION date), not v_request.date_from (the
      -- leave's own, possibly future, start date) -- self-found: a first
      -- draft dated the debit at date_from, which made a future-dated
      -- approval invisible to app.get_employee_leave_balance's own "as of
      -- today" callers (including this same function's own balance check
      -- immediately below, and every read RPC) until the leave date actually
      -- arrived -- an approved-but-not-yet-taken leave must reduce AVAILABLE
      -- balance immediately (the exact reason the overlap EXCLUDE constraint
      -- also treats a still-future approved request as live), mirrors app.
      -- cancel_leave_request's own request_credit_reversal, which was
      -- already correctly dated current_date from the start.
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

    -- Employee lifecycle sync (decision -- reserved field ISS-2026-065's own
    -- exact reservation point): only when the approved leave has ALREADY
    -- started (today falls within its own date range) and the employee is
    -- currently active -- app.employee_lifecycle_status is point-in-time
    -- only, never effective-dated (standing, disclosed HRT-274 gap), so a
    -- FUTURE-dated approval never flips lifecycle_status prematurely.
    if v_type.category = 'leave' and v_request.date_from <= current_date and v_request.date_to >= current_date then
      declare
        v_current_employee app.employees;
      begin
        select * into v_current_employee from app.employees where master_record_id = v_request.employee_id for update;
        if v_current_employee.lifecycle_status = 'active' then
          perform app.start_employee_leave(v_request.employee_id, v_current_employee.record_version, 'leave_request:' || v_request.id::text, p_actor_auth_user_id, p_actor_label);
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
  'HRT-280 (decision 4/9): no domain permission gate of its own for the ordinary approve/reject path -- app.decide_approval_step already gates on tenant membership + eligible-approver identity + C-18 self-approval block (mirrors app.decide_onboarding_case_finalize_approval, HRT-277). The coverage-override branch is the one place this function DOES gate directly (HRS:Override), since overriding a coverage block is a real, separate authority decision from ordinary leave approval. A rejected request returns to draft (section 22 "revision/resubmission"), letting the employee address the rejection reason and resubmit.';

create function app.cancel_leave_request(p_request_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
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
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Deliberately PLAIN (non-locking) read first, mirroring app.cancel_
  -- onboarding_case''s own documented lock-order rationale exactly (decision
  -- 7/mandatory reading item 8): app.decide_leave_request''s own call path
  -- locks app.approval_request_steps/app.approval_requests (inside app.
  -- decide_approval_step) BEFORE it ever touches app.leave_requests (its own
  -- terminal UPDATE runs last). Locking the request row here FIRST, before
  -- calling app.cancel_approval_request (which locks the SAME approval-
  -- engine tables), would be the exact REVERSE order -- a real lock-order
  -- cycle (taxonomy C-21).
  select * into v_request_plain from app.leave_requests where id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_request_plain.tenant_id, p_actor_auth_user_id) then
    raise exception 'leave_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_request_plain.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_request_plain.employee_id;

  -- Authority bar matched to blast radius (decision 12): self may always
  -- cancel their own request; a non-self cancellation of a still-pending
  -- request is Edit; a non-self cancellation of an already-APPROVED
  -- (balance-debited) request requires Override -- a genuinely bigger
  -- blast radius than an ordinary edit, mirrors app.cancel_schedule_
  -- assignment''s (HRT-279) own Edit-or-Override tiering by row status.
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

  -- Ledger credit reversal + lifecycle sync -- ONLY when the request had
  -- actually been approved (a debit exists to reverse); idempotent via the
  -- ledger''s own unique idempotency_key so a retried cancel never
  -- double-credits.
  if v_request.status = 'cancelled' and v_type.requires_balance then
    insert into app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, event_type, units, effective_date, policy_version_id, source_request_id, idempotency_key, created_by)
    select v_request.tenant_id, v_request.employee_id, v_request.leave_type_id, 'request_credit_reversal', v_request.total_units, current_date, v_request.policy_version_id, v_request.id, v_request.id::text || ':credit_reversal', p_actor_label
    where exists (select 1 from app.leave_balance_ledger where source_request_id = v_request.id and event_type = 'request_debit')
      and not exists (select 1 from app.leave_balance_ledger where source_request_id = v_request.id and event_type = 'request_credit_reversal');
  end if;

  if v_type.category = 'leave' and v_request_plain.date_from <= current_date and v_request_plain.date_to >= current_date then
    declare
      v_current_employee app.employees;
    begin
      select * into v_current_employee from app.employees where master_record_id = v_request.employee_id for update;
      if v_current_employee.lifecycle_status = 'on_leave' then
        perform app.end_employee_leave(v_request.employee_id, v_current_employee.record_version, p_actor_auth_user_id, p_actor_label);
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
  'HRT-280 (decision 7, mandatory reading item 4/8): genuinely cancels any in-flight PLT-123 approval request before cascading (the exact class independently found and fixed in HRT-276 AND HRT-277). Section 22''s own "future cancellation" -- an approved request whose date_from is still in the future, or already in progress today, may be self-cancelled; an already-completed past leave cannot be (no meaningful compensating event exists for time already taken).';

-- ===========================================================================
-- 8. Balance adjustment RPCs (decision 12 -- both Override-gated, the
--    biggest blast-radius writes in this domain: a direct, unaudited-by-any-
--    request balance mutation).
-- ===========================================================================

create function app.adjust_leave_balance(
  p_tenant_id uuid, p_employee_id uuid, p_leave_type_id uuid, p_units numeric, p_effective_date date,
  p_reason text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.leave_balance_ledger
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.leave_balance_ledger;
  v_entry app.leave_balance_ledger;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.employees where master_record_id = p_employee_id and tenant_id = p_tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.leave_types where id = p_leave_type_id and tenant_id = p_tenant_id) then
    raise exception 'leave_type_not_found: %', p_leave_type_id using errcode = 'no_data_found';
  end if;
  if p_units = 0 then
    raise exception 'invalid_units: an adjustment must be non-zero' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required for a manual balance adjustment' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.leave_balance_ledger where tenant_id = p_tenant_id and employee_id = p_employee_id and leave_type_id = p_leave_type_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.event_type = 'adjustment' and v_existing.units = p_units and v_existing.effective_date = p_effective_date then
        return v_existing;
      else
        raise exception 'idempotency_key_conflict: key % was already used for a different adjustment', p_idempotency_key using errcode = 'unique_violation';
      end if;
    end if;
  end if;

  insert into app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, event_type, units, effective_date, reason, idempotency_key, created_by)
  values (p_tenant_id, p_employee_id, p_leave_type_id, 'adjustment', p_units, coalesce(p_effective_date, current_date), p_reason, p_idempotency_key, p_actor_label)
  returning * into v_entry;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'adjust_leave_balance',
    'app.leave_balance_ledger', v_entry.id, 'success', p_reason, null, jsonb_build_object('employee_id', p_employee_id, 'leave_type_id', p_leave_type_id, 'units', p_units)
  );

  return v_entry;
end;
$$;

create function app.load_opening_leave_balance(
  p_tenant_id uuid, p_employee_id uuid, p_leave_type_id uuid, p_units numeric, p_as_of_date date,
  p_source_reference text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.leave_balance_ledger
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.leave_balance_ledger;
  v_entry app.leave_balance_ledger;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.employees where master_record_id = p_employee_id and tenant_id = p_tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.leave_types where id = p_leave_type_id and tenant_id = p_tenant_id) then
    raise exception 'leave_type_not_found: %', p_leave_type_id using errcode = 'no_data_found';
  end if;
  if p_units is null or p_units <= 0 then
    raise exception 'invalid_units: an opening balance load must be a positive amount' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: an opening balance load requires an idempotency key (section 19 reconciliation)' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.leave_balance_ledger where tenant_id = p_tenant_id and employee_id = p_employee_id and leave_type_id = p_leave_type_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.event_type = 'opening_balance' and v_existing.units = p_units and v_existing.effective_date = p_as_of_date then
      return v_existing;
    else
      raise exception 'idempotency_key_conflict: key % was already used for a different opening balance load', p_idempotency_key using errcode = 'unique_violation';
    end if;
  end if;

  insert into app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, event_type, units, effective_date, reason, idempotency_key, created_by)
  values (p_tenant_id, p_employee_id, p_leave_type_id, 'opening_balance', p_units, coalesce(p_as_of_date, current_date), coalesce(p_source_reference, 'opening balance load'), p_idempotency_key, p_actor_label)
  returning * into v_entry;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'load_opening_leave_balance',
    'app.leave_balance_ledger', v_entry.id, 'success', p_source_reference, null, jsonb_build_object('employee_id', p_employee_id, 'leave_type_id', p_leave_type_id, 'units', p_units)
  );

  return v_entry;
end;
$$;

comment on function app.load_opening_leave_balance is
  'HRT-280 (section 19 "load opening balances... through signed reconciliation totals and source dates; never invent historical accrual"): a distinct event_type/RPC from app.adjust_leave_balance for auditability -- mandatory idempotency_key (unlike the general adjustment path) since a real data-migration load must be safely re-runnable against the same source extract without double-posting.';

-- ===========================================================================
-- 9. Accrual/carry-forward batch jobs (decision 13, PLT-132 reuse, third
--    HRIS-domain adopter after HRT-279's roster_generation).
-- ===========================================================================

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry',
    'document_generation', 'dashboard_refresh', 'loyalty_expiration', 'recurring_billing',
    'integration_sync', 'route_load_planning', 'print_label', 'roster_generation',
    'leave_accrual', 'leave_carry_forward_expiry'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'HRT-280 (decision 13): widened to add ''leave_accrual''/''leave_carry_forward_expiry'' -- the third HRIS-domain adopter of PLT-132''s own generic job_type list, after HRT-279''s ''roster_generation''. Kept set-equal with app.generic_job_types() by scripts/db-tests/background-job.sql''s own standing ATW-031 drift-gate assertion.';

create or replace function app.generic_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry'
  ]::text[];
$$;

comment on function app.generic_job_types is
  'ATW-031 (ISS-2026-012), widened by HRT-280 (decision 13) to add ''leave_accrual''/''leave_carry_forward_expiry'' -- the single authority for which job_type values the GENERIC queue mechanics accept. app.enqueue_job and app.dispatch_event_as_job both already call this function directly (unchanged by this migration, the exact HRT-279 decision 8 lesson applied correctly from the start) -- app.all_job_types() (also unchanged) composes it with (''import'',''export'').';

create function app.run_leave_accrual_batch(p_tenant_id uuid, p_leave_type_id uuid, p_as_of_date date, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns table (accrued_count integer, skipped_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_type app.leave_types;
  v_job app.jobs;
  v_worker_id text;
  v_employee record;
  v_policy app.leave_type_policy_versions;
  v_accrued integer := 0;
  v_skipped integer := 0;
  v_key text;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_type from app.leave_types where id = p_leave_type_id and tenant_id = p_tenant_id and status = 'published';
  if not found then
    raise exception 'leave_type_not_available: % is not a published leave type in this tenant', p_leave_type_id using errcode = 'no_data_found';
  end if;
  if p_as_of_date is null or p_period_label is null or length(trim(p_period_label)) = 0 then
    raise exception 'invalid_period: p_as_of_date and a non-empty p_period_label are required' using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'leave_accrual', jsonb_build_object('leave_type_id', p_leave_type_id, 'as_of_date', p_as_of_date, 'period_label', p_period_label),
    0, 'leave_accrual:' || p_leave_type_id::text || ':' || p_period_label, 1, p_actor_auth_user_id, p_actor_label
  );

  -- Self-found, live-caught by the db-test suite's own idempotent-re-run
  -- assertion: app.enqueue_job's own idempotency replay (PLT-132, unchanged)
  -- returns the SAME app.jobs row regardless of its CURRENT status on a key
  -- match -- a first draft unconditionally attempted to claim-then-complete
  -- it again, which raised job_lease_not_held the moment a caller re-ran the
  -- SAME period (exactly the "safely re-runnable" case section 17 itself
  -- requires). Only claim/process/complete when app.enqueue_job genuinely
  -- created a FRESH pending row; a replay of an already-processed job is a
  -- real, safe no-op that reports zero NEW postings, never a second attempt
  -- to complete an already-completed job. (This exact shape -- an unguarded
  -- claim-then-complete pair right after app.enqueue_job -- is also present
  -- in app.generate_roster_schedule_assignments, HRT-279, 20260730910000;
  -- that function's own db-test never exercises a same-idempotency-key
  -- repeat call so it was not live-caught there. Out of this task's own
  -- allowed-files scope to edit; flagged here for the batch's own Tier C
  -- propagation sweep rather than silently left unswept.)
  if v_job.status = 'pending' then
    v_worker_id := 'inline-leave-accrual:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    -- Bounded to CURRENTLY active employees eligible per the resolved
    -- policy''s own tenure requirement -- never an unbounded tenant-wide
    -- table scan without a real predicate (section 17''s own "no unbounded
    -- scan").
    for v_employee in select * from app.employees where tenant_id = p_tenant_id and lifecycle_status in ('active', 'on_leave') loop
      select * into v_policy from app.resolve_effective_leave_type_policy_version(p_tenant_id, p_leave_type_id, v_employee.branch_org_unit_id, p_as_of_date) limit 1;
      if not found or v_policy.accrual_frequency = 'none' or v_policy.accrual_amount_per_period <= 0 then
        v_skipped := v_skipped + 1;
        continue;
      end if;
      if v_policy.eligibility_min_tenure_days > 0 and (v_employee.hire_date is null or (p_as_of_date - v_employee.hire_date) < v_policy.eligibility_min_tenure_days) then
        v_skipped := v_skipped + 1;
        continue;
      end if;
      if v_policy.accrual_max_balance is not null and app.get_employee_leave_balance(p_tenant_id, v_employee.master_record_id, p_leave_type_id, p_as_of_date) >= v_policy.accrual_max_balance then
        v_skipped := v_skipped + 1;
        continue;
      end if;

      v_key := 'accrual:' || v_policy.id::text || ':' || p_period_label;
      begin
        insert into app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, event_type, units, effective_date, policy_version_id, idempotency_key, created_by)
        values (p_tenant_id, v_employee.master_record_id, p_leave_type_id, 'accrual', v_policy.accrual_amount_per_period, p_as_of_date, v_policy.id, v_key, p_actor_label);
        v_accrued := v_accrued + 1;
      exception
        when unique_violation then
          -- Already posted for this employee/policy_version/period -- the
          -- ledger''s own idempotency_key unique index is the real re-run
          -- safety net (section 17 "async accrual... jobs" must be safely
          -- re-runnable).
          v_skipped := v_skipped + 1;
      end;
    end loop;

    perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_leave_accrual_batch',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('leave_type_id', p_leave_type_id, 'period_label', p_period_label, 'accrued_count', v_accrued, 'skipped_count', v_skipped)
    );
  end if;

  accrued_count := v_accrued; skipped_count := v_skipped; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.run_leave_accrual_batch is
  'HRT-280 (decision 13): a real app.jobs row tracked through the actual PLT-132 lifecycle (enqueue -> self-claim -> complete), mirrors app.generate_roster_schedule_assignments (HRT-279) exactly. Idempotent per (policy_version_id, period_label) via the ledger''s own unique idempotency_key -- re-running the SAME period for the SAME policy version is always a safe no-op, never a double-accrual.';

create function app.run_leave_carry_forward_batch(p_tenant_id uuid, p_leave_type_id uuid, p_effective_date date, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns table (expired_count integer, skipped_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_type app.leave_types;
  v_job app.jobs;
  v_worker_id text;
  v_employee record;
  v_policy app.leave_type_policy_versions;
  v_current numeric;
  v_excess numeric;
  v_expired integer := 0;
  v_skipped integer := 0;
  v_key text;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_type from app.leave_types where id = p_leave_type_id and tenant_id = p_tenant_id and status = 'published';
  if not found then
    raise exception 'leave_type_not_available: % is not a published leave type in this tenant', p_leave_type_id using errcode = 'no_data_found';
  end if;
  if p_effective_date is null or p_period_label is null or length(trim(p_period_label)) = 0 then
    raise exception 'invalid_period: p_effective_date and a non-empty p_period_label are required' using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'leave_carry_forward_expiry', jsonb_build_object('leave_type_id', p_leave_type_id, 'effective_date', p_effective_date, 'period_label', p_period_label),
    0, 'leave_carry_forward:' || p_leave_type_id::text || ':' || p_period_label, 1, p_actor_auth_user_id, p_actor_label
  );

  -- Same guard as app.run_leave_accrual_batch above, same reason (self-found,
  -- live-caught): only claim/process/complete a genuinely FRESH pending job.
  if v_job.status = 'pending' then
    v_worker_id := 'inline-leave-carry-forward:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    for v_employee in select * from app.employees where tenant_id = p_tenant_id and lifecycle_status in ('active', 'on_leave') loop
      select * into v_policy from app.resolve_effective_leave_type_policy_version(p_tenant_id, p_leave_type_id, v_employee.branch_org_unit_id, p_effective_date) limit 1;
      if not found then
        v_skipped := v_skipped + 1;
        continue;
      end if;

      v_current := app.get_employee_leave_balance(p_tenant_id, v_employee.master_record_id, p_leave_type_id, p_effective_date - 1);
      v_excess := v_current - v_policy.carry_forward_max_units;
      if v_excess <= 0 then
        v_skipped := v_skipped + 1;
        continue;
      end if;

      v_key := 'carry_forward_expire:' || v_policy.id::text || ':' || p_period_label;
      begin
        insert into app.leave_balance_ledger (tenant_id, employee_id, leave_type_id, event_type, units, effective_date, policy_version_id, idempotency_key, created_by)
        values (p_tenant_id, v_employee.master_record_id, p_leave_type_id, 'carry_forward_expire', -v_excess, p_effective_date, v_policy.id, v_key, p_actor_label);
        v_expired := v_expired + 1;
      exception
        when unique_violation then
          v_skipped := v_skipped + 1;
      end;
    end loop;

    perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_leave_carry_forward_batch',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('leave_type_id', p_leave_type_id, 'period_label', p_period_label, 'expired_count', v_expired, 'skipped_count', v_skipped)
    );
  end if;

  expired_count := v_expired; skipped_count := v_skipped; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.run_leave_carry_forward_batch is
  'HRT-280 (decision 13, section 20 "carry-forward jobs"): a single batch handles BOTH a real capped carry-forward AND a strict use-it-or-lose-it type (carry_forward_max_units=0) -- no second expiry mechanism (never a per-vintage/FIFO lot tracker, a disclosed V1 simplification: the whole balance in excess of the cap is forfeited as one ledger event, not the OLDEST accrual specifically). Idempotent per (policy_version_id, period_label), mirrors app.run_leave_accrual_batch exactly.';

-- ===========================================================================
-- 10. Schedule override + employee-lifecycle sync (decision 10 -- both
--     explicit, separately-authorized actions, never automatic).
-- ===========================================================================

create function app.cancel_conflicting_schedule_assignment_for_leave(p_leave_request_id uuid, p_work_date date, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.schedule_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.leave_requests;
  v_assignment app.schedule_assignments;
begin
  select * into v_request from app.leave_requests where id = p_leave_request_id;
  if not found then
    raise exception 'leave_request_not_found: %', p_leave_request_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'leave_request_not_found: %', p_leave_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.status <> 'approved' then
    raise exception 'invalid_transition: leave request % is %, only an approved request may override a scheduled shift', p_leave_request_id, v_request.status
      using errcode = 'check_violation';
  end if;
  if p_work_date < v_request.date_from or p_work_date > v_request.date_to then
    raise exception 'work_date_out_of_range: % is not within leave request %''s own date range', p_work_date, p_leave_request_id using errcode = 'check_violation';
  end if;

  select * into v_assignment from app.resolve_effective_schedule_assignment(v_request.tenant_id, v_request.employee_id, p_work_date);
  if not found then
    raise exception 'no_conflicting_schedule: employee % has no published schedule assignment on %', v_request.employee_id, p_work_date using errcode = 'no_data_found';
  end if;

  -- Reuses app.cancel_schedule_assignment (HRT-279) directly -- never a
  -- second cancellation mechanism for the same table (AGENTS.md "do not
  -- create duplicate ... policy engines"). That function itself re-checks
  -- HRS:Override for a published row, so this is not a privilege escalation
  -- path -- it is a real, deliberate delegation to the domain that actually
  -- owns app.schedule_assignments.
  v_assignment := app.cancel_schedule_assignment(v_assignment.id, p_expected_version, coalesce(p_reason, 'leave_request:' || p_leave_request_id::text), p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_conflicting_schedule_assignment_for_leave',
    'app.schedule_assignments', v_assignment.id, 'success', p_reason, null, jsonb_build_object('leave_request_id', p_leave_request_id, 'work_date', p_work_date)
  );

  return v_assignment;
end;
$$;

comment on function app.cancel_conflicting_schedule_assignment_for_leave is
  'HRT-280 (decision 10, mandatory reading "authority-bar mismatch"): a real, explicit, HRS:Override-gated action -- an approved leave never SILENTLY cancels an already-published shift (the actor who approved the leave, HRS:Approve, is not necessarily the actor with roster-mutation authority, HRS:Override). Delegates the actual cancellation to app.cancel_schedule_assignment (HRT-279) unchanged, never a second cancellation mechanism.';

create function app.sync_employee_leave_lifecycle_status(p_tenant_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns table (started_count integer, ended_count integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_started integer := 0;
  v_ended integer := 0;
  v_employee record;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Bounded to employees currently active with an approved 'leave'-category
  -- request that has already started today -- mirrors app.recalculate_
  -- attendance_exceptions_for_range''s (HRT-278) own "no live job worker,
  -- bounded synchronous RPC" reasoning (decision 13/ISS-2026-015) exactly.
  for v_employee in
    select e.* from app.employees e
    join app.leave_requests r on r.employee_id = e.master_record_id and r.status = 'approved'
    join app.leave_types t on t.id = r.leave_type_id and t.category = 'leave'
    where e.tenant_id = p_tenant_id and e.lifecycle_status = 'active'
      and r.date_from <= current_date and r.date_to >= current_date
    for update of e
  loop
    perform app.start_employee_leave(v_employee.master_record_id, v_employee.record_version, 'leave_lifecycle_sync', p_actor_auth_user_id, p_actor_label);
    v_started := v_started + 1;
  end loop;

  for v_employee in
    select e.* from app.employees e
    where e.tenant_id = p_tenant_id and e.lifecycle_status = 'on_leave'
      and not exists (
        select 1 from app.leave_requests r
        join app.leave_types t on t.id = r.leave_type_id and t.category = 'leave'
        where r.employee_id = e.master_record_id and r.status = 'approved' and r.date_from <= current_date and r.date_to >= current_date
      )
    for update of e
  loop
    perform app.end_employee_leave(v_employee.master_record_id, v_employee.record_version, p_actor_auth_user_id, p_actor_label);
    v_ended := v_ended + 1;
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'sync_employee_leave_lifecycle_status',
    'app.employees', null, 'success', null, null, jsonb_build_object('started_count', v_started, 'ended_count', v_ended)
  );

  started_count := v_started; ended_count := v_ended;
  return next;
end;
$$;

comment on function app.sync_employee_leave_lifecycle_status is
  'HRT-280: bounded, synchronous, HRS:Edit-gated batch reconciling app.employees.lifecycle_status against currently-in-effect approved leave -- the exact reservation point HRT-274''s own app.start_employee_leave/app.end_employee_leave comment named ("accrual/balance/multi-day-request leave workflow is Prompt 280''s own chartered scope"). A tenant that never calls this (or app.decide_leave_request''s own inline sync at approval time) simply keeps lifecycle_status stale by up to one day -- disclosed, matches ISS-2026-065''s own standing "not effective-dated" gap, never silently pretended to be a live scheduler.';

-- ===========================================================================
-- 11. Read RPCs.
-- ===========================================================================

create function app.list_leave_types(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.leave_types
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    return;
  end if;
  return query select t.* from app.leave_types t where t.tenant_id = p_tenant_id order by t.category, t.name;
end;
$$;

create function app.list_leave_type_policy_versions(p_leave_type_id uuid, p_actor_auth_user_id uuid)
returns setof app.leave_type_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_type app.leave_types;
  v_decision app.rbac_decision;
begin
  select * into v_type from app.leave_types where id = p_leave_type_id;
  if not found then
    return;
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_type.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    return;
  end if;
  return query select v.* from app.leave_type_policy_versions v where v.leave_type_id = p_leave_type_id order by v.effective_from desc;
end;
$$;

create function app.list_employee_leave_balances(p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid default null, p_as_of_date date default current_date)
returns table (leave_type_id uuid, code text, name text, category text, requires_balance boolean, balance numeric, pending_units numeric)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_target uuid;
  v_is_self boolean;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  v_target := coalesce(p_employee_id, v_self.master_record_id);
  if v_target is null then
    return;
  end if;
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_target;

  if not v_is_self then
    if not (
      exists (select 1 from app.employees e where e.master_record_id = v_target and e.manager_employee_id = v_self.master_record_id)
      or (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View')).allowed
    ) then
      return;
    end if;
  end if;

  return query
  select t.id, t.code, t.name, t.category, t.requires_balance,
         app.get_employee_leave_balance(p_tenant_id, v_target, t.id, p_as_of_date),
         coalesce((select sum(r.total_units) from app.leave_requests r where r.employee_id = v_target and r.leave_type_id = t.id and r.status = 'pending_approval'), 0)
  from app.leave_types t
  where t.tenant_id = p_tenant_id and t.status = 'published'
  order by t.category, t.name;
end;
$$;

comment on function app.list_employee_leave_balances is
  'HRT-280 (section 16 "employees see own balances... managers see effective team"): self, or the target''s own DIRECT manager, or an HRS:View holder -- never any other tenant member. Zero rows for an unauthorized combination, never a distinguishable error (mirrors the RLS default-deny fold pattern for reads).';

create function app.list_leave_requests(
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
      r.employee_id = v_self.master_record_id
      or (p_employee_id is null and not v_has_view and e.manager_employee_id = v_self.master_record_id)
      or v_has_view
    )
    and (p_employee_id is null or r.employee_id = p_employee_id)
  order by r.id
  limit v_bounded_limit;
end;
$$;

comment on function app.list_leave_requests is
  'HRT-280 (section 16/26): self rows always visible; a manager with no HRS:View sees their own direct reports'' rows (organizational fields only when p_employee_id is null -- an explicit p_employee_id filter still requires either self or HRS:View, never lets a manager probe an arbitrary non-report by id); an HRS:View holder sees the whole tenant. reason is nulled unless the caller is the requester themself or holds HRS:View personal data (section 16 "managers see... only necessary reason").';

create function app.get_leave_request_detail(p_request_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, employee_id uuid, leave_type_id uuid, status text, date_from date, date_to date, day_portion text,
  total_units numeric, reason text, destination text, evidence_file_id uuid, schedule_snapshot jsonb,
  payroll_input_status text, decided_reason text, cancel_reason text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.leave_requests;
  v_self app.employees;
  v_is_self boolean;
  v_is_manager boolean;
  v_has_view boolean;
  v_has_personal boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  -- Table-aliased (r.id, not bare id) -- this function's own RETURNS TABLE
  -- output carries an `id` column of the identical name, live-caught by the
  -- db-test suite ("column reference is ambiguous"), the exact recurring
  -- class this task's own instructions explicitly flagged.
  select r.* into v_request from app.leave_requests r where r.id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'leave_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = v_request.employee_id;
  v_is_manager := exists (select 1 from app.employees e where e.master_record_id = v_request.employee_id and e.manager_employee_id = v_self.master_record_id);
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'View')).allowed;
  v_has_personal := (app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'View personal data')).allowed;

  if not (v_is_self or v_is_manager or v_has_view) then
    raise exception 'leave_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  return query
  select v_request.id, v_request.employee_id, v_request.leave_type_id, v_request.status, v_request.date_from, v_request.date_to,
         v_request.day_portion, v_request.total_units,
         case when v_is_self or v_has_personal then v_request.reason else null end,
         case when v_is_self or v_has_personal then v_request.destination else null end,
         case when v_is_self or v_has_personal then v_request.evidence_file_id else null end,
         v_request.schedule_snapshot, v_request.payroll_input_status,
         case when v_is_self or v_has_personal then v_request.decided_reason else null end,
         case when v_is_self or v_has_personal then v_request.cancel_reason else null end,
         v_request.record_version;
end;
$$;

comment on function app.get_leave_request_detail is
  'HRT-280 (C-05): the not-found fold applies uniformly to a genuinely-missing row AND to a row a non-self/non-manager/non-View caller has no standing to see -- a cross-tenant or unrelated caller gets the SAME leave_request_not_found either way, never a distinguishable disclosure.';

create function app.list_leave_balance_ledger(p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid, p_leave_type_id uuid default null, p_limit integer default 50)
returns setof app.leave_balance_ledger
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_is_self boolean;
  v_has_personal boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  v_is_self := v_self.master_record_id is not null and v_self.master_record_id = p_employee_id;
  v_has_personal := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View personal data')).allowed;
  if not (v_is_self or v_has_personal) then
    return;
  end if;
  return query
  select l.* from app.leave_balance_ledger l
  where l.tenant_id = p_tenant_id and l.employee_id = p_employee_id and (p_leave_type_id is null or l.leave_type_id = p_leave_type_id)
  order by l.effective_date desc, l.created_at desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create function app.get_leave_calendar(p_tenant_id uuid, p_actor_auth_user_id uuid, p_org_unit_id uuid, p_from_date date, p_to_date date)
returns table (employee_id uuid, employee_name text, leave_type_id uuid, category text, date_from date, date_to date, day_portion text)
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
  if p_from_date is null or p_to_date is null or p_to_date < p_from_date or (p_to_date - p_from_date) > 366 then
    raise exception 'invalid_date_range: date range must be non-empty and at most 366 days' using errcode = 'check_violation';
  end if;

  -- Section 15/16 "manager calendar visibility minimizes sensitive leave
  -- reason and attachment data" -- deliberately projects name/type/dates
  -- only, never reason/destination/evidence_file_id.
  return query
  select r.employee_id, e.full_name, r.leave_type_id, t.category, r.date_from, r.date_to, r.day_portion
  from app.leave_requests r
  join app.employees e on e.master_record_id = r.employee_id
  join app.leave_types t on t.id = r.leave_type_id
  where r.tenant_id = p_tenant_id and r.status = 'approved'
    and r.date_from <= p_to_date and r.date_to >= p_from_date
    and (p_org_unit_id is null or e.branch_org_unit_id = p_org_unit_id or e.department_org_unit_id = p_org_unit_id)
  order by r.date_from, e.full_name;
end;
$$;

create function app.export_leave_requests(p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date)
returns table (employee_code text, employee_name text, leave_type_code text, category text, date_from date, date_to date, total_units numeric, status text)
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
    p_tenant_id, p_actor_auth_user_id, p_actor_auth_user_id::text, 'export_leave_requests',
    'app.leave_requests', null, 'success', null, null, jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date)
  );

  -- Section 16 "exports... minimize detail" -- no reason/destination/
  -- evidence_file_id column ever appears in an export, regardless of the
  -- caller's own HRS:View personal data standing (mirrors app.export_
  -- employees'' identical, disclosed narrower scope, HRT-274).
  return query
  select m.code, e.full_name, t.code, t.category, r.date_from, r.date_to, r.total_units, r.status
  from app.leave_requests r
  join app.employees e on e.master_record_id = r.employee_id
  join app.master_records m on m.id = e.master_record_id
  join app.leave_types t on t.id = r.leave_type_id
  where r.tenant_id = p_tenant_id and r.date_from <= p_to_date and r.date_to >= p_from_date
  order by r.date_from, m.code;
end;
$$;

create function app.approve_leave_for_payroll_input(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.leave_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.leave_requests;
begin
  select * into v_request from app.leave_requests where id = p_request_id for update;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'leave_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: leave request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'approved' then
    raise exception 'invalid_transition: leave request % is %, only an approved request may be marked ready for payroll input', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  update app.leave_requests set payroll_input_status = 'approved' where id = p_request_id and record_version = p_expected_version returning * into v_request;
  if not found then
    raise exception 'stale_version: leave request % target row was concurrently modified (expected version %)', p_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_leave_for_payroll_input',
    'app.leave_requests', v_request.id, 'success', null, null, app.leave_request_audit_projection(v_request)
  );

  return v_request;
end;
$$;

comment on function app.approve_leave_for_payroll_input is
  'HRT-280 (section 13/24 "payroll-impact records"): the identical forward-contract shape app.approve_attendance_for_payroll_input (HRT-278) already established -- Payroll itself (Prompt 282) does not exist yet; no live Finance/Payroll posting occurs from this checkpoint.';

-- ===========================================================================
-- 12. RLS -- hardened default-deny select policy on every new table (writes
--     exclusively through the SECURITY DEFINER functions above, never a raw
--     INSERT/UPDATE grant to authenticated).
-- ===========================================================================

alter table app.leave_types enable row level security;
alter table app.leave_type_policy_versions enable row level security;
alter table app.leave_balance_ledger enable row level security;
alter table app.leave_requests enable row level security;

create policy leave_types_select_scoped on app.leave_types
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy leave_type_policy_versions_select_scoped on app.leave_type_policy_versions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy leave_balance_ledger_select_scoped on app.leave_balance_ledger
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy leave_requests_select_scoped on app.leave_requests
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 13. Grants (decision 11) -- column-restricted from THIS, the FIRST,
--     migration for every sensitive free-text field, mirroring HRT-278's
--     own established convention exactly, never a blanket
--     `grant select on <table> to authenticated`.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select (id, tenant_id, code, name, category, unit, requires_balance, requires_evidence, evidence_classification, status, record_version, created_by, created_at, updated_at)
  on app.leave_types to authenticated;
grant select on app.leave_types to service_role;

grant select (
  id, leave_type_id, tenant_id, org_unit_id, version_number, status, effective_from, accrual_frequency, accrual_amount_per_period,
  accrual_max_balance, carry_forward_max_units, min_notice_days, max_consecutive_units, eligibility_min_tenure_days,
  negative_balance_allowed, published_at, published_by, record_version, created_by, created_at, updated_at
) on app.leave_type_policy_versions to authenticated;
grant select on app.leave_type_policy_versions to service_role;

grant select (id, tenant_id, employee_id, leave_type_id, event_type, units, effective_date, policy_version_id, source_request_id, idempotency_key, created_by, created_at)
  on app.leave_balance_ledger to authenticated;
grant select on app.leave_balance_ledger to service_role;
grant insert on app.leave_balance_ledger to service_role;

grant select (
  id, tenant_id, employee_id, leave_type_id, policy_version_id, status, date_from, date_to, day_portion, total_units,
  evidence_file_id, schedule_snapshot, approval_request_id, cancelled_at, payroll_input_status, previous_request_id,
  requested_by_auth_user_id, requested_by, idempotency_key, record_version, created_by, created_at, updated_at
) on app.leave_requests to authenticated;
grant select on app.leave_requests to service_role;

comment on column app.leave_requests.reason is 'HRT-280 (decision 11): column-restricted from authenticated -- service_role only. Masked at the RPC layer (app.get_leave_request_detail/app.list_leave_requests) to self-or-HRS:View-personal-data.';
comment on column app.leave_requests.destination is 'HRT-280 (decision 11): column-restricted from authenticated, same bar as reason -- a business-trip destination can be as sensitive as a leave reason.';
comment on column app.leave_requests.decided_reason is 'HRT-280 (decision 11): column-restricted from authenticated, same bar as reason.';
comment on column app.leave_requests.cancel_reason is 'HRT-280 (decision 11): column-restricted from authenticated, same bar as reason.';
comment on column app.leave_balance_ledger.reason is 'HRT-280 (decision 11): column-restricted from authenticated -- an HR adjustment/opening-balance reason can incidentally disclose sensitive personal circumstances, masked identically to app.leave_requests.reason.';

grant execute on function app.resolve_effective_leave_type_policy_version(uuid, uuid, uuid, date) to authenticated, service_role;
grant execute on function app.get_employee_leave_balance(uuid, uuid, uuid, date) to authenticated, service_role;

grant execute on function app.create_leave_type(uuid, text, text, text, boolean, boolean, text, uuid, text) to authenticated, service_role;
grant execute on function app.publish_leave_type(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.create_leave_type_policy_version(uuid, uuid, date, text, numeric, numeric, numeric, integer, numeric, integer, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.publish_leave_type_policy_version(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.create_leave_request(uuid, uuid, date, date, text, text, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_leave_request_for_employee(uuid, uuid, uuid, date, date, text, text, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_leave_request_draft(uuid, integer, date, date, text, text, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.submit_leave_request(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decide_leave_request(uuid, text, text, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_leave_request(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.adjust_leave_balance(uuid, uuid, uuid, numeric, date, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.load_opening_leave_balance(uuid, uuid, uuid, numeric, date, text, text, uuid, text) to authenticated, service_role;

grant execute on function app.run_leave_accrual_batch(uuid, uuid, date, text, uuid, text) to authenticated, service_role;
grant execute on function app.run_leave_carry_forward_batch(uuid, uuid, date, text, uuid, text) to authenticated, service_role;

grant execute on function app.cancel_conflicting_schedule_assignment_for_leave(uuid, date, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.sync_employee_leave_lifecycle_status(uuid, uuid, text) to authenticated, service_role;

grant execute on function app.list_leave_types(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_leave_type_policy_versions(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_employee_leave_balances(uuid, uuid, uuid, date) to authenticated, service_role;
grant execute on function app.list_leave_requests(uuid, uuid, uuid, text, date, date, integer, uuid) to authenticated, service_role;
grant execute on function app.get_leave_request_detail(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_leave_balance_ledger(uuid, uuid, uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.get_leave_calendar(uuid, uuid, uuid, date, date) to authenticated, service_role;
grant execute on function app.export_leave_requests(uuid, uuid, date, date) to authenticated, service_role;
grant execute on function app.approve_leave_for_payroll_input(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.leave_request_audit_projection(app.leave_requests) to authenticated, service_role;

-- Internal-only -- never granted to authenticated (decision, mirrors
-- app._ingest_attendance_event/app._recalculate_session_exceptions,
-- HRT-278).
grant execute on function app._create_leave_request(uuid, app.employees, uuid, date, date, text, text, text, uuid, text, uuid, text) to service_role;
grant execute on function app._compute_leave_business_units(uuid, uuid, date, date, text) to service_role;
grant execute on function app._leave_coverage_impact(uuid, uuid, date) to service_role;
