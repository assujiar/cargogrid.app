-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-003 (Organization and Position
-- Linkage, Prompt 275) -- the SECOND Phase 7 capability. Links employees to
-- Platform-owned company/branch/department/team organization structures through
-- effective-dated position, grade and reporting assignments, per ADR-0023
-- (docs/adr/ADR-0023-phase7-hris-organization-team-and-employee-identity-
-- reconciliation.md, Part A) and HRT-274's own build log §10 recommendation.
--
-- Design decisions, disclosed rather than left implicit (matching HRT-274's own
-- discipline):
--
-- 1. **ADR-0023 Part A implemented exactly as decided.** `app.org_units.unit_type`
--    gains an additive fifth value, `team` (`DROP CONSTRAINT
--    org_units_unit_type_check` / `ADD CONSTRAINT ... CHECK (unit_type in
--    ('company','branch','department','business_unit','team'))`), plus one new
--    branch in `app.enforce_org_unit_parent_shape()` (`team`'s parent must be
--    `department` or `business_unit`, never `company`/`branch` directly; `team` is a
--    leaf type and may never itself be a parent -- a genuinely NEW guard, since no
--    prior type was ever a universally-forbidden parent). `app.create_org_unit`/
--    `app.move_org_unit`/`app.org_unit_ancestor_ids`/`app.org_unit_descendant_ids`
--    (all pre-existing, generic over `unit_type`) need no change at all -- only the
--    CHECK constraint and the parent-shape trigger widen, exactly as the ADR
--    specifies. This is NOT a re-litigation of that decision -- it is this migration's
--    own chartered implementation of an already-ratified design.
--
-- 2. **Position/grade are HR-governed, tenant-scoped catalogue data -- NOT a second
--    organization tree, and NOT routed through app.master_records.** Organization
--    write stays Platform-governed and unchanged (app.org_units'
--    create/move/rename/set_status RPCs remain service_role-only, exactly as PLT-109
--    left them -- this migration touches none of their grants). Position and grade
--    are HR module content: gated through app.evaluate_permission(..., 'HRS', ...)
--    like every other HRS-owned table, not a Platform-admin-only surface. They are
--    deliberately NOT routed through app.master_records (unlike vendor/driver/
--    employee) -- a position/grade is structural configuration describing a SLOT in
--    the org chart, not an operational actor identity needing merge/dedupe/lifecycle
--    across external sources. This mirrors app.org_units' own simpler,
--    directly-tenant-scoped shape (code+tenant unique, record_version, status
--    lifecycle) rather than vendor/driver/employee's master_records-extension shape --
--    the right precedent for catalogue/config data, not actor identity.
--
-- 3. **app.employees.position_id is an additive CURRENT-pointer column, never a
--    replacement for position_title.** Per HRT-274's own build log §10 recommendation
--    (and §3.2's own explicit promise): position_title remains untouched as a
--    display fallback for any employee never linked to a governed position (or
--    linked before this capability existed). position_id is nullable, references
--    app.positions(id), and is synced by app.decide_employee_position_assignment /
--    app.activate_due_employee_position_assignments -- never hand-edited by
--    app.update_employee_draft/app.transfer_employee (HRT-274's own free-text RPCs,
--    unchanged, still valid for a position-less employee).
--
-- 4. **A genuinely NEW table (app.employee_position_assignments), not a mutable
--    column on app.employees -- because effective-dated history cannot live in a
--    single mutable column** (section 13's own explicit reasoning). Every
--    transfer/promotion/hire/secondary-assignment is a NEW ROW, never an UPDATE of a
--    prior one's substantive fields -- the row itself IS the historical record.
--    app.employees.position_id/manager_employee_id/company_org_unit_id/
--    branch_org_unit_id/department_org_unit_id/position_title are a best-effort,
--    eagerly-synced CONVENIENCE CACHE of "whatever the latest PROCESSED assignment
--    says" -- the assignment table is the source of truth for point-in-time-correct
--    reads (app.get_employee_current_assignment, `p_as_of`-parameterized).
--
-- 5. **Two-step propose/decide workflow (HRS:Edit proposes, HRS:Approve decides) --
--    both permission actions already exist** (seeded at PLT-111,
--    20260716103445:61-63; unlike Prompt 274, this migration adds NO new
--    app.permissions row at all). This directly implements section 21's own main
--    flow ("previews downstream access/approval effects, obtains required approval
--    and activates the assignment on its effective date") as a real gate, not a
--    single always-immediate write. app.preview_employee_position_assignment_impact
--    is deliberately callable BEFORE a proposal even exists (a pure, read-only,
--    hypothetical-input computation) so the UI wizard can show impact before HR
--    commits to proposing anything, matching section 21's own ordering.
--
-- 6. **Impact preview computes REAL data only -- it does not fabricate
--    approval-queue/payroll/ticket impact that no live capability in this repository
--    yet produces.** Direct repository inspection this checkpoint confirms
--    approval-queue routing has no org-unit-scoped concept anywhere
--    (app.evaluate_permission is tenant+module+action only, no org-node scoping);
--    Payroll (Prompt 282) and Ticketing (Prompt 285+) tables do not exist yet. The
--    preview RPC computes what genuinely exists today (target position/grade/org
--    path, capacity remaining, would-be-cyclic manager chain, this employee's own
--    real direct-report count, real pending change-request/duplicate-candidate
--    counts) and returns an explicit `downstream_disclosure` text field naming the
--    not-yet-integrated systems, rather than inventing a placeholder number for any
--    of them -- "never fabricate" applied to a read projection, not only to writes.
--
-- 7. **Overlap and capacity are both real, DB-adjacent guards, not merely
--    documented intent.** Overlap (section 25 "overlap policy") reuses this
--    repository's own established `btree_gist` EXCLUDE-constraint pattern
--    (`app.vendor_rate_versions_no_ambiguous_overlap`, PRC-255,
--    20260730620000) -- a genuinely new primary assignment can never share an
--    overlapping `[effective_start_date, effective_end_date]` range with another
--    ACTIVE primary assignment for the same employee, enforced by Postgres itself,
--    not by application-layer discipline alone; `exclusion_violation`/
--    `deadlock_detected` are both translated into the same friendly
--    `assignment_overlap` error, mirroring PRC-255's own two-sqlstate handling
--    exactly (a GiST EXCLUDE insert under real contention can legitimately surface
--    either sqlstate for the identical business conflict). Capacity (section 25
--    "capacity", section 23 "position over-capacity") is validated at DECISION
--    (approval) time under a position-scoped advisory transaction lock -- matching
--    section 25's own literal "before activation" framing -- rather than at proposal
--    time, since a proposal does not yet commit any real headcount.
--
-- 8. **Manager-cycle prevention: formalizing HRT-274's own disclosed placeholder
--    decision, WITHOUT building a materialized reporting-line closure table.**
--    HRT-274's build log §10 explicitly left this decision to this checkpoint. This
--    checkpoint's own decision: KEEP app.assert_no_employee_manager_cycle's bounded
--    200-hop chain walk (unchanged, reused directly -- not reimplemented), rather
--    than building a materialized transitive-closure table. Reasoning: (a) real
--    organizational reporting depth is bounded by a small constant in every
--    plausible tenant (a 200-hop chain is already two orders of magnitude beyond any
--    realistic org depth); (b) a materialized closure table requires a
--    rebuild-on-every-manager-change trigger cascade with real storage/write-
--    amplification cost, for a check that already runs in O(depth) time with a
--    single indexed column walk; (c) this capability's own new
--    employee_position_assignments table gives manager-chain history for FREE via
--    its own effective-dated rows (app.get_employee_manager_chain reads the CURRENT
--    chain from app.employees.manager_employee_id, matching the existing
--    app.list_my_team_employees precedent, while historical manager-of-record at any
--    past date is answered by app.get_employee_current_assignment's own `p_as_of`
--    parameter) -- the materialized-closure alternative would duplicate information
--    this table already carries. The chain walk is reused (not reimplemented) at
--    BOTH app.propose_employee_position_assignment (early UX feedback) AND
--    app.decide_employee_position_assignment (the authoritative gate, re-checked
--    against fresh state) -- a cheap, defense-in-depth application of an unchanged
--    function, not a new mechanism.
--
-- 9. **No compensation/salary/pay-band field anywhere in this migration.**
--    Section 13's own scope is position/grade STRUCTURE (a title, a level, a
--    reporting slot) -- compensation amounts are Payroll's own chartered scope
--    (Prompt 282, HRS_REGISTRY's own "payroll" category, deliberately unused by
--    HRT-274 and unused here too). app.position_grades carries a `rank` (a bare
--    ordering integer, e.g. for sorting a grade ladder), never a pay figure.
--    scripts/data-classification/registry.ts's HRS_REGISTRY needs no new entry --
--    no column on any table this migration creates is PII or payroll-classified.
--
-- 10. **No staged-import (PLT-131/132) pipeline for positions/assignments.**
--    Unlike HRT-274's own employee_import adapter, this checkpoint does not build a
--    bulk-import path for position/grade/assignment rows -- disclosed, bounded scope
--    (section 19's "map existing department/position strings to canonical IDs
--    through staged, reviewed crosswalks" describes a FUTURE, not-yet-chartered
--    capability; building a first-of-its-kind crosswalk-import UI here would be
--    disproportionate, unrequested scope for this checkpoint). `source_config_
--    version_id` is reserved (nullable, unused by any RPC below) on
--    app.employee_position_assignments for that future capability, mirroring
--    app.employees' own identical "reserve the field, do not build the unbuilt
--    future capability" discipline.
--
-- 11. **No bulk/multi-employee reorganization wizard.** Section 13's own table
--    ("employee-assignment/version table") is singular-employee-centric; this
--    migration's RPCs operate one employee at a time. A batch "move an entire
--    department's employees to a new org unit in one transaction" tool is disclosed,
--    bounded future scope, not built here.
--
-- 12. **Authority routes exclusively through app.evaluate_permission(..., 'HRS',
--    ...)** for every write RPC below except the two self-service reads
--    (app.get_my_employee_position_assignment_history, identity-match-gated like
--    app.get_my_employee_profile) and the maintenance sweep
--    (app.activate_due_employee_position_assignments, service_role/HRS:Override
--    gated, mirrors the "async heavy work" performance guidance -- no live
--    cron/scheduler exists anywhere in this repository yet to invoke it
--    automatically, the same disclosed "mechanism proven, live wiring deferred"
--    posture PLT-107/HRT-274 already used for other not-yet-scheduled work).
--
-- 13. **Concurrency.** Every write RPC below: locks its target row(s)
--    (`SELECT ... FOR UPDATE`) before checking authority/version, folds a
--    non-member caller into the same not_found branch a genuinely missing row would
--    produce, checks authority BEFORE record_version, and repeats
--    `record_version = p_expected_version` in the terminal UPDATE's own WHERE
--    clause -- the fully-hardened shape this repository converged on (20260730480000
--    /20260730820000), adopted here from day one exactly as HRT-274 itself did.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement before
-- its final grants, the standing per-migration convention since PLT-118.

create extension if not exists btree_gist;

-- ===========================================================================
-- 1. ADR-0023 Part A -- widen app.org_units.unit_type to add 'team' (decision 1).
-- ===========================================================================

alter table app.org_units drop constraint org_units_unit_type_check;
alter table app.org_units add constraint org_units_unit_type_check
  check (unit_type in ('company', 'branch', 'department', 'business_unit', 'team'));

create or replace function app.enforce_org_unit_parent_shape()
returns trigger
language plpgsql
as $$
declare
  v_parent app.org_units;
begin
  if new.parent_id is null then
    if new.unit_type <> 'company' then
      raise exception 'invalid_org_unit_parent: % must have a parent (only company is a root type)', new.unit_type
        using errcode = 'check_violation';
    end if;
    return new;
  end if;

  select * into v_parent from app.org_units where id = new.parent_id;
  if not found then
    raise exception 'org_unit_parent_not_found: parent % does not exist', new.parent_id
      using errcode = 'no_data_found';
  end if;

  if v_parent.tenant_id <> new.tenant_id then
    raise exception 'cross_tenant_parent: parent % belongs to a different tenant', new.parent_id
      using errcode = 'check_violation';
  end if;

  -- HRT-275/ADR-0023 Part A addition: team is a leaf type -- no unit_type='team' row
  -- may ever itself be a parent, regardless of the child's own unit_type. Checked
  -- before the allowed-parent-type matrix below so the error is unambiguous.
  if v_parent.unit_type = 'team' then
    raise exception 'invalid_org_unit_parent: a team is a leaf type and may not itself be a parent (attempted to parent % under team %)', new.unit_type, new.parent_id
      using errcode = 'check_violation';
  end if;

  if not (
    (new.unit_type = 'branch' and v_parent.unit_type = 'company')
    or (new.unit_type = 'department' and v_parent.unit_type in ('company', 'branch', 'department'))
    or (new.unit_type = 'business_unit' and v_parent.unit_type = 'company')
    or (new.unit_type = 'team' and v_parent.unit_type in ('department', 'business_unit'))
  ) then
    raise exception 'invalid_org_unit_parent: a % may not be parented under a %', new.unit_type, v_parent.unit_type
      using errcode = 'check_violation';
  end if;

  -- Cycle guard: a node can never become its own ancestor. On UPDATE (move), the
  -- candidate parent's own path (or id) must not contain this node. Unchanged from
  -- PLT-109's own original logic.
  if tg_op = 'UPDATE' and (v_parent.path @> array[old.id] or v_parent.id = old.id) then
    raise exception 'org_unit_cycle: % cannot be moved under its own descendant %', old.id, new.parent_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

comment on function app.enforce_org_unit_parent_shape is
  'PLT-109, widened by HRT-275/ADR-0023 Part A: team''s parent must be department or business_unit (never company/branch directly); team is a leaf type and may never itself be a parent. Every pre-existing company/branch/department/business_unit rule is unchanged (regression-proven by scripts/db-tests/org-hierarchy.sql''s own pre-existing assertions, re-run unmodified against this widened function).';

-- ===========================================================================
-- 2. app.position_grades -- HR-governed, tenant-scoped grade ladder (decisions 2, 9).
--    Deliberately NOT routed through app.master_records (decision 2) -- structural
--    catalogue data, not an operational actor identity.
-- ===========================================================================

create table app.position_grades (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  name text not null,
  rank integer not null default 0,
  status text not null default 'active',
  description text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint position_grades_code_check check (length(trim(code)) > 0),
  constraint position_grades_name_check check (length(trim(name)) > 0),
  constraint position_grades_status_check check (status in ('active', 'inactive')),
  constraint position_grades_code_unique unique (tenant_id, code)
);

comment on table app.position_grades is
  'HRT-275: HR-governed grade ladder (a bare ordering integer, `rank` -- never a compensation figure, decision 9). Referenced by app.positions and, optionally per-assignment, app.employee_position_assignments. Never hard-deleted -- status=''inactive'' only, blocked while any active app.positions row still references it.';

create index position_grades_tenant_status_idx on app.position_grades (tenant_id, status);

create trigger position_grades_touch_row
  before update on app.position_grades
  for each row
  execute function app.touch_org_unit_row();

create function app.position_grade_audit_projection(p_grade app.position_grades)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_grade.id, 'code', p_grade.code, 'name', p_grade.name, 'rank', p_grade.rank,
    'status', p_grade.status, 'record_version', p_grade.record_version
  );
$$;

comment on function app.position_grade_audit_projection is
  'HRT-275: explicit non-sensitive projection for app.capture_audit_event calls against app.position_grades -- no column on this table is classified, but every audit call in this migration uses an explicit projection rather than to_jsonb(row), matching HRT-274''s own established discipline so a future column addition cannot silently become a leak vector.';

-- ===========================================================================
-- 3. app.positions -- HR-governed position catalogue, referencing a canonical
--    company/branch/department/business_unit/team org_units node (decision 2).
-- ===========================================================================

create table app.positions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  title text not null,
  org_unit_id uuid not null references app.org_units (id),
  grade_id uuid references app.position_grades (id),
  capacity integer not null default 1,
  status text not null default 'active',
  description text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint positions_code_check check (length(trim(code)) > 0),
  constraint positions_title_check check (length(trim(title)) > 0),
  constraint positions_capacity_check check (capacity > 0),
  constraint positions_status_check check (status in ('active', 'inactive')),
  constraint positions_code_unique unique (tenant_id, code)
);

comment on table app.positions is
  'HRT-275: HR-governed position catalogue. org_unit_id references any canonical app.org_units node (company/branch/department/business_unit/team, ADR-0023 Part A) -- never a second hierarchy. capacity bounds how many CONCURRENT primary (never secondary) assignments this position may carry, enforced at approval time by app.decide_employee_position_assignment under a position-scoped advisory lock. Never hard-deleted -- status=''inactive'' only, blocked while any currently-in-effect assignment references it.';

create index positions_tenant_status_idx on app.positions (tenant_id, status);
create index positions_tenant_org_unit_idx on app.positions (tenant_id, org_unit_id);
create index positions_tenant_grade_idx on app.positions (tenant_id, grade_id) where grade_id is not null;

create trigger positions_touch_row
  before update on app.positions
  for each row
  execute function app.touch_org_unit_row();

-- Shape validation: org_unit_id, when set/changed, must be a same-tenant, active
-- app.org_units row -- mirrors app.enforce_employee_org_unit_shape's own established
-- "fires only when the column itself is part of the INSERT/UPDATE" discipline (HRT-274),
-- so a position already assigned to a node is never retroactively invalidated by a
-- LATER, unrelated org-unit deactivation.
create function app.enforce_position_org_unit_shape()
returns trigger
language plpgsql
as $$
declare
  v_unit app.org_units;
begin
  select * into v_unit from app.org_units where id = new.org_unit_id;
  if not found or v_unit.tenant_id <> new.tenant_id then
    raise exception 'org_unit_not_found: org_unit_id % is not a valid unit for tenant %', new.org_unit_id, new.tenant_id using errcode = 'no_data_found';
  end if;
  if v_unit.status <> 'active' then
    raise exception 'org_unit_inactive: org_unit_id % is inactive and cannot be assigned to a position', new.org_unit_id using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger positions_enforce_org_unit_shape
  before insert or update of org_unit_id, tenant_id on app.positions
  for each row
  execute function app.enforce_position_org_unit_shape();

create function app.position_audit_projection(p_position app.positions)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_position.id, 'code', p_position.code, 'title', p_position.title,
    'org_unit_id', p_position.org_unit_id, 'grade_id', p_position.grade_id,
    'capacity', p_position.capacity, 'status', p_position.status, 'record_version', p_position.record_version
  );
$$;

comment on function app.position_audit_projection is 'HRT-275: explicit non-sensitive projection for app.capture_audit_event calls against app.positions (decision 9: no classified column exists on this table).';

-- ===========================================================================
-- 4. app.employee_position_assignments -- the effective-dated, versioned
--    assignment/history table (decision 4). Source of truth; app.employees'
--    position_id/manager_employee_id/company/branch/department_org_unit_id are a
--    synced convenience cache, never the other way around.
-- ===========================================================================

create table app.employee_position_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  master_record_id uuid not null references app.employees (master_record_id),
  position_id uuid not null references app.positions (id),
  grade_id uuid references app.position_grades (id),
  manager_employee_id uuid references app.employees (master_record_id),
  assignment_type text not null default 'primary',
  allocation_pct numeric(5, 2) not null default 100.00,
  effective_start_date date not null,
  effective_end_date date,
  validity_range daterange generated always as (daterange(effective_start_date, effective_end_date, '[]')) stored,
  status text not null default 'pending_approval',
  change_reason text not null,
  reason_note text,
  previous_assignment_id uuid references app.employee_position_assignments (id),
  source_config_version_id uuid references app.config_versions (id),
  decided_by text,
  decided_at timestamptz,
  decided_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employee_position_assignments_assignment_type_check check (assignment_type in ('primary', 'secondary')),
  constraint employee_position_assignments_allocation_pct_check check (allocation_pct > 0 and allocation_pct <= 100),
  constraint employee_position_assignments_status_check check (status in ('pending_approval', 'active', 'rejected', 'cancelled')),
  constraint employee_position_assignments_change_reason_check check (
    change_reason in ('hire', 'transfer', 'promotion', 'demotion', 'lateral_move', 'reorganization', 'secondary_assignment', 'correction')
  ),
  constraint employee_position_assignments_secondary_reason_check check (
    assignment_type <> 'secondary' or change_reason = 'secondary_assignment'
  ),
  constraint employee_position_assignments_manager_not_self_check check (manager_employee_id is distinct from master_record_id),
  constraint employee_position_assignments_effective_range_check check (effective_end_date is null or effective_end_date >= effective_start_date),
  constraint employee_position_assignments_decided_shape_check check (
    (status = 'pending_approval' and decided_at is null and decided_by is null) or
    (status <> 'pending_approval' and decided_at is not null and decided_by is not null and decided_reason is not null and length(trim(decided_reason)) > 0)
  )
);

comment on table app.employee_position_assignments is
  'HRT-275 (section 13): effective-dated employee <-> position/grade/manager assignment history. Every real transition is a NEW row -- never a mutating UPDATE of a prior row''s substantive fields (only status/decided_*/effective_end_date on the SAME row ever change, via app.decide_employee_position_assignment/app.cancel_employee_position_assignment). status=''active'' covers past (closed via effective_end_date), current, and future-dated (scheduled) rows alike -- "is this assignment in effect right now" is answered by validity_range @> current_date at read time, never a separately-drifting stored flag (avoids needing a live scheduler to keep a status column fresh). Two real EXCLUDE constraints below enforce overlap/duplication at the database level, not by application discipline alone.';

create index employee_position_assignments_tenant_employee_idx on app.employee_position_assignments (tenant_id, master_record_id);
create index employee_position_assignments_tenant_position_idx on app.employee_position_assignments (tenant_id, position_id);
create index employee_position_assignments_tenant_manager_idx on app.employee_position_assignments (tenant_id, manager_employee_id) where manager_employee_id is not null;
create index employee_position_assignments_tenant_status_idx on app.employee_position_assignments (tenant_id, status);
create index employee_position_assignments_pending_idx on app.employee_position_assignments (tenant_id) where status = 'pending_approval';
create index employee_position_assignments_due_activation_idx on app.employee_position_assignments (tenant_id, effective_start_date) where status = 'active';

-- Overlap guard (decision 7): a genuinely new PRIMARY assignment can never share an
-- overlapping validity_range with another ACTIVE primary assignment for the same
-- employee -- the real, DB-enforced "one primary role at a time" business rule.
-- Scoped to status='active' only (a pending_approval proposal does not yet commit
-- any real headcount/timeline, so proposals may freely overlap each other pending
-- review).
alter table app.employee_position_assignments
  add constraint employee_position_assignments_no_primary_overlap
  exclude using gist (master_record_id with =, validity_range with &&)
  where (assignment_type = 'primary' and status = 'active');

comment on constraint employee_position_assignments_no_primary_overlap on app.employee_position_assignments is
  'HRT-275 (section 25 "overlap policy"), mirrors app.vendor_rate_versions_no_ambiguous_overlap (PRC-255) exactly. app.decide_employee_position_assignment translates the raw exclusion_violation/deadlock_detected into the friendly assignment_overlap error.';

-- Duplicate-secondary guard: the same employee may not hold two overlapping ACTIVE
-- secondary assignments to the SAME position (would be a meaningless duplicate),
-- while still allowing multiple DIFFERENT concurrent secondary assignments
-- (decision: secondary assignments do not consume a position's primary capacity and
-- may coexist across different positions).
alter table app.employee_position_assignments
  add constraint employee_position_assignments_no_duplicate_secondary
  exclude using gist (master_record_id with =, position_id with =, validity_range with &&)
  where (assignment_type = 'secondary' and status = 'active');

create trigger employee_position_assignments_touch_row
  before update on app.employee_position_assignments
  for each row
  execute function app.touch_org_unit_row();

create function app.employee_position_assignment_audit_projection(p_assignment app.employee_position_assignments)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_assignment.id, 'master_record_id', p_assignment.master_record_id, 'position_id', p_assignment.position_id,
    'grade_id', p_assignment.grade_id, 'manager_employee_id', p_assignment.manager_employee_id,
    'assignment_type', p_assignment.assignment_type, 'allocation_pct', p_assignment.allocation_pct,
    'effective_start_date', p_assignment.effective_start_date, 'effective_end_date', p_assignment.effective_end_date,
    'status', p_assignment.status, 'change_reason', p_assignment.change_reason,
    'previous_assignment_id', p_assignment.previous_assignment_id, 'record_version', p_assignment.record_version
  );
$$;

comment on function app.employee_position_assignment_audit_projection is 'HRT-275: explicit non-sensitive projection for app.capture_audit_event calls against app.employee_position_assignments (decision 9: no classified column exists on this table).';

-- ===========================================================================
-- 5. app.employees additive columns (decision 3) -- position_id, a CURRENT-pointer
--    cache. position_title (HRT-274) is UNCHANGED and remains the display fallback.
-- ===========================================================================

alter table app.employees add column position_id uuid references app.positions (id);
comment on column app.employees.position_id is
  'HRT-275 (HRT-274''s own §10 recommendation): the position of this employee''s CURRENT, latest-PROCESSED primary assignment -- a synced convenience cache, never hand-edited by app.update_employee_draft/app.transfer_employee. NULL for an employee with no governed position yet (position_title remains the display fallback, unchanged, never replaced retroactively). Synced exclusively by app.decide_employee_position_assignment (immediate case) and app.activate_due_employee_position_assignments (future-dated case, once its effective_start_date arrives).';

create index employees_tenant_position_idx on app.employees (tenant_id, position_id) where position_id is not null;

-- ===========================================================================
-- 6. Internal helpers (service_role only -- called from the RPCs below).
-- ===========================================================================

-- Resolves the company/branch/department ancestor ids for a given org_unit_id, by
-- direct scan of app.org_units' own materialized path array -- no recursive CTE
-- (section 17). Used to keep app.employees' company/branch/department_org_unit_id
-- cache columns consistent with a position's own org_unit_id when an assignment
-- activates.
create function app.resolve_org_unit_lineage(p_org_unit_id uuid)
returns table (company_org_unit_id uuid, branch_org_unit_id uuid, department_org_unit_id uuid)
language plpgsql
stable
as $$
declare
  v_unit app.org_units;
begin
  select * into v_unit from app.org_units where id = p_org_unit_id;
  if not found then
    raise exception 'org_unit_not_found: % is not a valid org unit', p_org_unit_id using errcode = 'no_data_found';
  end if;

  return query
  select
    case when v_unit.unit_type = 'company' then v_unit.id
         else (select ou.id from app.org_units ou where ou.id = any(v_unit.path) and ou.unit_type = 'company' limit 1) end,
    case when v_unit.unit_type = 'branch' then v_unit.id
         else (select ou.id from app.org_units ou where ou.id = any(v_unit.path) and ou.unit_type = 'branch' limit 1) end,
    case when v_unit.unit_type = 'department' then v_unit.id
         else (select ou.id from app.org_units ou where ou.id = any(v_unit.path) and ou.unit_type = 'department' limit 1) end;
end;
$$;

comment on function app.resolve_org_unit_lineage is
  'HRT-275: reads app.org_units.path directly (a short, per-row materialized ancestor array) -- never a recursive CTE. A business_unit/team-rooted position may legitimately resolve a null branch/department ancestor (business_unit''s own parent is company only, and department is never nested under business_unit) -- disclosed, correct behavior, not a defect.';

-- Non-raising wrapper around app.assert_no_employee_manager_cycle (HRT-274, reused
-- unchanged, decision 8) for use in a read-only preview context.
--
-- HRT-275 review-round fix (LOW, adversarial review): the original body caught
-- `when others` -- a blanket catch that would silently relabel ANY internal error
-- (lock_timeout, statement_timeout, out-of-shared-memory, or any other genuinely
-- unrelated error raised by the chain-walk SELECT inside
-- app.assert_no_employee_manager_cycle) as "this candidate manager assignment would
-- create a cycle", which both app.propose_employee_position_assignment and
-- app.decide_employee_position_assignment then surface to the caller as
-- `cyclic_reporting_line` -- masking the true cause. Narrowed to the exact condition
-- app.assert_no_employee_manager_cycle actually raises (`errcode = 'check_violation'`,
-- every one of its three `raise exception` sites) so an unrelated error now propagates
-- with its own real SQLSTATE/message instead of being relabeled.
create function app.would_create_employee_manager_cycle(p_employee_id uuid, p_candidate_manager_id uuid)
returns boolean
language plpgsql
stable
as $$
begin
  perform app.assert_no_employee_manager_cycle(p_employee_id, p_candidate_manager_id);
  return false;
exception
  when check_violation then
    return true;
end;
$$;

-- Counts ACTIVE primary assignments to a position whose validity_range overlaps a
-- given candidate range -- the real headcount-over-time check behind "capacity"
-- (section 25). Never counts secondary assignments (decision: secondary does not
-- consume primary capacity).
create function app.count_position_active_primary_headcount(p_position_id uuid, p_candidate_range daterange, p_exclude_assignment_id uuid default null)
returns integer
language sql
stable
as $$
  select count(*)::integer
  from app.employee_position_assignments
  where position_id = p_position_id
    and assignment_type = 'primary'
    and status = 'active'
    and validity_range && p_candidate_range
    and (p_exclude_assignment_id is null or id <> p_exclude_assignment_id);
$$;

comment on function app.count_position_active_primary_headcount is
  'HRT-275: p_exclude_assignment_id lets a caller exclude one specific currently-active row from the count -- used by app.decide_employee_position_assignment so a same-position correction/promotion (which closes then replaces the employee''s own existing occupancy of this SAME position) does not double-count that soon-to-be-closed predecessor against the position''s own capacity.';

-- Syncs app.employees' convenience-cache columns from one now-effective assignment
-- row. Called from both app.decide_employee_position_assignment (immediate case) and
-- app.activate_due_employee_position_assignments (future-dated case). PRIMARY
-- assignments only -- a secondary assignment never overwrites the employee's own
-- primary-position cache.
create function app.sync_employee_current_assignment_cache(p_assignment app.employee_position_assignments)
returns void
language plpgsql
as $$
declare
  v_position app.positions;
  v_lineage record;
begin
  if p_assignment.assignment_type <> 'primary' then
    return;
  end if;

  -- HRT-275 review-round fix (CRITICAL, adversarial review): this is the ONLY code
  -- path that ever writes app.employees.manager_employee_id (see the function comment
  -- below) -- but a future-dated app.decide_employee_position_assignment approval
  -- deliberately does NOT call this function immediately (its own "if
  -- effective_start_date <= current_date" guard), leaving app.employees'
  -- manager_employee_id cache stale relative to the just-approved assignment. Both
  -- app.propose_employee_position_assignment and app.decide_employee_position_assignment
  -- re-check cycle-freedom via app.would_create_employee_manager_cycle, but that check
  -- walks this SAME stale cache column -- so two independently-valid, future-dated,
  -- mutually-referencing propose+decide pairs can each pass their own re-check against
  -- a still-null/stale cache, and app.activate_due_employee_position_assignments' own
  -- maintenance sweep (the only other caller of this function) previously called this
  -- function with no cycle validation of its own at all -- live-reproduced as a
  -- persistent, undetected two-employee manager cycle once both due rows synced.
  -- Fix: re-validate cycle-freedom authoritatively at the one point that actually
  -- commits a change to the live app.employees.manager_employee_id graph -- here,
  -- immediately before the UPDATE -- regardless of whether the caller is the
  -- immediate decide-time sync or the future-dated maintenance sweep. Raises (does not
  -- silently swallow) on a detected cycle; app.activate_due_employee_position_assignments
  -- below catches it per-row so one cyclic row can never abort the rest of the sweep.
  if p_assignment.manager_employee_id is not null then
    perform app.assert_no_employee_manager_cycle(p_assignment.master_record_id, p_assignment.manager_employee_id);
  end if;

  select * into v_position from app.positions where id = p_assignment.position_id;
  select * into v_lineage from app.resolve_org_unit_lineage(v_position.org_unit_id);

  update app.employees
  set position_id = p_assignment.position_id,
      position_title = v_position.title,
      manager_employee_id = p_assignment.manager_employee_id,
      company_org_unit_id = v_lineage.company_org_unit_id,
      branch_org_unit_id = v_lineage.branch_org_unit_id,
      department_org_unit_id = v_lineage.department_org_unit_id
  where master_record_id = p_assignment.master_record_id;
end;
$$;

comment on function app.sync_employee_current_assignment_cache is
  'HRT-275 (decision 3, decision 4): the ONLY code path that ever writes app.employees.position_id -- overwrites position_title too (from the position''s own current title), matching real HRIS behavior that org placement follows a governed position once one is assigned. Never invoked for a secondary assignment. Review-round fix: re-validates manager-cycle-freedom (app.assert_no_employee_manager_cycle) immediately before writing manager_employee_id -- the authoritative gate, since this is the only point that actually commits a change to the live reporting-line graph (see the fix comment inline above).';

-- ===========================================================================
-- 7. Position grade CRUD (HRS:Create/Edit/View, decision 2).
-- ===========================================================================

create function app.create_position_grade(
  p_tenant_id uuid, p_code text, p_name text, p_rank integer, p_description text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.position_grades
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.position_grades;
  v_grade app.position_grades;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_code is null or length(trim(p_code)) = 0 or p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_position_grade: code and name must not be empty' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.position_grades where tenant_id = p_tenant_id and code = p_code;
  if found then
    if v_existing.name = p_name and v_existing.rank is not distinct from coalesce(p_rank, 0) and v_existing.description is not distinct from p_description then
      return v_existing;
    end if;
    raise exception 'position_grade_code_conflict: code % already exists for tenant % with different data', p_code, p_tenant_id
      using errcode = 'unique_violation';
  end if;

  insert into app.position_grades (tenant_id, code, name, rank, description, created_by)
  values (p_tenant_id, p_code, p_name, coalesce(p_rank, 0), p_description, p_actor_label)
  returning * into v_grade;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_position_grade',
    'app.position_grades', v_grade.id, 'success', null, null, app.position_grade_audit_projection(v_grade)
  );

  return v_grade;
end;
$$;

create function app.update_position_grade(
  p_id uuid, p_expected_version integer, p_name text, p_rank integer, p_description text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.position_grades
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_grade app.position_grades;
begin
  select * into v_grade from app.position_grades where id = p_id for update;
  if not found or not app.has_active_tenant_membership(v_grade.tenant_id, p_actor_auth_user_id) then
    raise exception 'position_grade_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_grade.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_grade.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_grade.record_version <> p_expected_version then
    raise exception 'stale_version: position grade % expected version % but found %', p_id, p_expected_version, v_grade.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_position_grade: name must not be empty' using errcode = 'check_violation';
  end if;

  update app.position_grades
  set name = p_name, rank = coalesce(p_rank, 0), description = p_description
  where id = p_id and record_version = p_expected_version
  returning * into v_grade;
  if not found then
    raise exception 'stale_version: position grade % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_grade.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_position_grade',
    'app.position_grades', v_grade.id, 'success', null, null, app.position_grade_audit_projection(v_grade)
  );

  return v_grade;
end;
$$;

create function app.set_position_grade_status(
  p_id uuid, p_expected_version integer, p_new_status text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.position_grades
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_grade app.position_grades;
  v_active_positions integer;
begin
  select * into v_grade from app.position_grades where id = p_id for update;
  if not found or not app.has_active_tenant_membership(v_grade.tenant_id, p_actor_auth_user_id) then
    raise exception 'position_grade_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_grade.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_grade.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_grade.record_version <> p_expected_version then
    raise exception 'stale_version: position grade % expected version % but found %', p_id, p_expected_version, v_grade.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_new_status not in ('active', 'inactive') then
    raise exception 'invalid_status: %', p_new_status using errcode = 'check_violation';
  end if;

  if p_new_status = 'inactive' and v_grade.status = 'active' then
    select count(*) into v_active_positions from app.positions where grade_id = p_id and status = 'active';
    if v_active_positions > 0 then
      raise exception 'position_grade_in_use: grade % cannot be deactivated while % active position(s) reference it', p_id, v_active_positions
        using errcode = 'check_violation';
    end if;
  end if;

  update app.position_grades set status = p_new_status
  where id = p_id and record_version = p_expected_version
  returning * into v_grade;
  if not found then
    raise exception 'stale_version: position grade % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_grade.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_position_grade_status',
    'app.position_grades', v_grade.id, 'success', null, null, app.position_grade_audit_projection(v_grade)
  );

  return v_grade;
end;
$$;

create function app.list_position_grades(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null)
returns setof app.position_grades
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status_filter is not null and p_status_filter not in ('active', 'inactive') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select * from app.position_grades
  where tenant_id = p_tenant_id and (p_status_filter is null or status = p_status_filter)
  order by rank, code;
end;
$$;

-- ===========================================================================
-- 8. Position CRUD (HRS:Create/Edit/View/Export, decision 2).
-- ===========================================================================

create function app.create_position(
  p_tenant_id uuid, p_code text, p_title text, p_org_unit_id uuid, p_grade_id uuid, p_capacity integer, p_description text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.positions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.positions;
  v_position app.positions;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_code is null or length(trim(p_code)) = 0 or p_title is null or length(trim(p_title)) = 0 then
    raise exception 'invalid_position: code and title must not be empty' using errcode = 'check_violation';
  end if;

  if p_grade_id is not null and not exists (select 1 from app.position_grades where id = p_grade_id and tenant_id = p_tenant_id) then
    raise exception 'position_grade_not_found: % is not a valid grade for tenant %', p_grade_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.positions where tenant_id = p_tenant_id and code = p_code;
  if found then
    if v_existing.title = p_title and v_existing.org_unit_id = p_org_unit_id and v_existing.grade_id is not distinct from p_grade_id
       and v_existing.capacity = coalesce(p_capacity, 1) and v_existing.description is not distinct from p_description then
      return v_existing;
    end if;
    raise exception 'position_code_conflict: code % already exists for tenant % with different data', p_code, p_tenant_id
      using errcode = 'unique_violation';
  end if;

  insert into app.positions (tenant_id, code, title, org_unit_id, grade_id, capacity, description, created_by)
  values (p_tenant_id, p_code, p_title, p_org_unit_id, p_grade_id, coalesce(p_capacity, 1), p_description, p_actor_label)
  returning * into v_position;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_position',
    'app.positions', v_position.id, 'success', null, null, app.position_audit_projection(v_position)
  );

  return v_position;
end;
$$;

create function app.update_position(
  p_id uuid, p_expected_version integer, p_title text, p_org_unit_id uuid, p_grade_id uuid, p_capacity integer, p_description text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.positions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_position app.positions;
begin
  select * into v_position from app.positions where id = p_id for update;
  if not found or not app.has_active_tenant_membership(v_position.tenant_id, p_actor_auth_user_id) then
    raise exception 'position_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_position.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_position.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_position.record_version <> p_expected_version then
    raise exception 'stale_version: position % expected version % but found %', p_id, p_expected_version, v_position.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'invalid_position: title must not be empty' using errcode = 'check_violation';
  end if;

  if p_grade_id is not null and not exists (select 1 from app.position_grades where id = p_grade_id and tenant_id = v_position.tenant_id) then
    raise exception 'position_grade_not_found: % is not a valid grade for tenant %', p_grade_id, v_position.tenant_id using errcode = 'no_data_found';
  end if;

  update app.positions
  set title = p_title, org_unit_id = p_org_unit_id, grade_id = p_grade_id, capacity = coalesce(p_capacity, 1), description = p_description
  where id = p_id and record_version = p_expected_version
  returning * into v_position;
  if not found then
    raise exception 'stale_version: position % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_position.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_position',
    'app.positions', v_position.id, 'success', null, null, app.position_audit_projection(v_position)
  );

  return v_position;
end;
$$;

create function app.set_position_status(
  p_id uuid, p_expected_version integer, p_new_status text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.positions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_position app.positions;
  v_active_assignments integer;
begin
  select * into v_position from app.positions where id = p_id for update;
  if not found or not app.has_active_tenant_membership(v_position.tenant_id, p_actor_auth_user_id) then
    raise exception 'position_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_position.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_position.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_position.record_version <> p_expected_version then
    raise exception 'stale_version: position % expected version % but found %', p_id, p_expected_version, v_position.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_new_status not in ('active', 'inactive') then
    raise exception 'invalid_status: %', p_new_status using errcode = 'check_violation';
  end if;

  if p_new_status = 'inactive' and v_position.status = 'active' then
    select count(*) into v_active_assignments
    from app.employee_position_assignments
    where position_id = p_id and status = 'active' and validity_range @> current_date;
    if v_active_assignments > 0 then
      raise exception 'position_in_use: position % cannot be deactivated while % currently-effective assignment(s) reference it', p_id, v_active_assignments
        using errcode = 'check_violation';
    end if;
  end if;

  update app.positions set status = p_new_status
  where id = p_id and record_version = p_expected_version
  returning * into v_position;
  if not found then
    raise exception 'stale_version: position % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_position.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_position_status',
    'app.positions', v_position.id, 'success', null, null, app.position_audit_projection(v_position)
  );

  return v_position;
end;
$$;

create function app.list_positions(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_org_unit_id uuid default null, p_status_filter text default null,
  p_search text default null, p_limit integer default 50, p_after_code text default null
)
returns table (
  id uuid, code text, title text, org_unit_id uuid, grade_id uuid, capacity integer, status text,
  current_headcount integer, record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status_filter is not null and p_status_filter not in ('active', 'inactive') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select p.id, p.code, p.title, p.org_unit_id, p.grade_id, p.capacity, p.status,
         app.count_position_active_primary_headcount(p.id, daterange(current_date, current_date, '[]'))::integer,
         p.record_version, p.created_at, p.updated_at
  from app.positions p
  where p.tenant_id = p_tenant_id
    and (p_org_unit_id is null or p.org_unit_id = p_org_unit_id)
    and (p_status_filter is null or p.status = p_status_filter)
    and (p_search is null or p.code ilike '%' || p_search || '%' or p.title ilike '%' || p_search || '%')
    and (p_after_code is null or p.code > p_after_code)
  order by p.code
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_positions is 'HRT-275: cursor-paginated (code-keyset), server-filtered/searched catalogue projection -- selective columns, no SELECT *. current_headcount is computed per row via the same indexed overlap check the capacity guard itself uses.';

create function app.get_position(p_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, code text, title text, org_unit_id uuid, grade_id uuid, capacity integer, status text,
  description text, current_headcount integer, capacity_remaining integer, record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_position app.positions;
  v_headcount integer;
begin
  select * into v_position from app.positions p where p.id = p_id;
  if not found or not app.has_active_tenant_membership(v_position.tenant_id, p_actor_auth_user_id) then
    raise exception 'position_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_position.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_position.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_headcount := app.count_position_active_primary_headcount(p_id, daterange(current_date, current_date, '[]'));

  return query
  select v_position.id, v_position.tenant_id, v_position.code, v_position.title, v_position.org_unit_id, v_position.grade_id,
         v_position.capacity, v_position.status, v_position.description, v_headcount, greatest(v_position.capacity - v_headcount, 0),
         v_position.record_version, v_position.created_at, v_position.updated_at;
end;
$$;

create function app.export_positions(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 500)
returns table (code text, title text, org_unit_id uuid, grade_code text, capacity integer, status text)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Export');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Export (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status_filter is not null and p_status_filter not in ('active', 'inactive') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select p.code, p.title, p.org_unit_id, g.code, p.capacity, p.status
  from app.positions p
  left join app.position_grades g on g.id = p.grade_id
  where p.tenant_id = p_tenant_id and (p_status_filter is null or p.status = p_status_filter)
  order by p.code
  limit least(coalesce(p_limit, 500), 5000);
end;
$$;

comment on function app.export_positions is 'HRT-275 (section 14 "scoped export"): a deliberately narrow projection -- no salary/compensation column exists to omit (decision 9), but the projection is still explicit and selective, never SELECT *.';

-- ===========================================================================
-- 9. Employee <-> position/grade/manager assignment workflow (decisions 4, 5, 7, 8).
-- ===========================================================================

create function app.propose_employee_position_assignment(
  p_master_record_id uuid, p_expected_version integer, p_position_id uuid, p_grade_id uuid, p_manager_employee_id uuid,
  p_assignment_type text, p_allocation_pct numeric, p_effective_start_date date, p_effective_end_date date,
  p_change_reason text, p_reason_note text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.employee_position_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_position app.positions;
  v_assignment app.employee_position_assignments;
  v_resolved_grade_id uuid;
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
    raise exception 'employee_closed: employee % is % -- a position may not be proposed', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  if p_assignment_type not in ('primary', 'secondary') then
    raise exception 'invalid_assignment_type: %', p_assignment_type using errcode = 'check_violation';
  end if;
  if p_change_reason not in ('hire', 'transfer', 'promotion', 'demotion', 'lateral_move', 'reorganization', 'secondary_assignment', 'correction') then
    raise exception 'invalid_change_reason: %', p_change_reason using errcode = 'check_violation';
  end if;
  if p_assignment_type = 'secondary' and p_change_reason <> 'secondary_assignment' then
    raise exception 'invalid_change_reason: a secondary assignment must use change_reason=secondary_assignment' using errcode = 'check_violation';
  end if;
  if p_effective_start_date is null then
    raise exception 'invalid_effective_range: effective_start_date is required' using errcode = 'check_violation';
  end if;
  if p_effective_end_date is not null and p_effective_end_date < p_effective_start_date then
    raise exception 'invalid_effective_range: effective_end_date % is before effective_start_date %', p_effective_end_date, p_effective_start_date
      using errcode = 'check_violation';
  end if;

  select * into v_position from app.positions where id = p_position_id and tenant_id = v_employee.tenant_id;
  if not found then
    raise exception 'position_not_found: % is not a valid position for tenant %', p_position_id, v_employee.tenant_id using errcode = 'no_data_found';
  end if;
  if v_position.status <> 'active' then
    raise exception 'position_inactive: position % is inactive', p_position_id using errcode = 'check_violation';
  end if;

  v_resolved_grade_id := coalesce(p_grade_id, v_position.grade_id);
  if v_resolved_grade_id is not null then
    if not exists (select 1 from app.position_grades where id = v_resolved_grade_id and tenant_id = v_employee.tenant_id and status = 'active') then
      raise exception 'position_grade_not_found: % is not a valid active grade for tenant %', v_resolved_grade_id, v_employee.tenant_id using errcode = 'no_data_found';
    end if;
  end if;

  if p_manager_employee_id is not null then
    if not exists (select 1 from app.employees where master_record_id = p_manager_employee_id and tenant_id = v_employee.tenant_id) then
      raise exception 'employee_not_found: manager % is not a valid employee for tenant %', p_manager_employee_id, v_employee.tenant_id using errcode = 'no_data_found';
    end if;
    -- Early UX feedback (decision 8) -- re-checked authoritatively at decide-time too.
    if app.would_create_employee_manager_cycle(p_master_record_id, p_manager_employee_id) then
      raise exception 'cyclic_reporting_line: setting % as manager of % would create a cyclic reporting line', p_manager_employee_id, p_master_record_id
        using errcode = 'check_violation';
    end if;
  end if;

  insert into app.employee_position_assignments (
    tenant_id, master_record_id, position_id, grade_id, manager_employee_id, assignment_type, allocation_pct,
    effective_start_date, effective_end_date, change_reason, reason_note, created_by
  )
  values (
    v_employee.tenant_id, p_master_record_id, p_position_id, v_resolved_grade_id, p_manager_employee_id, p_assignment_type,
    coalesce(p_allocation_pct, 100.00), p_effective_start_date, p_effective_end_date, p_change_reason, p_reason_note, p_actor_label
  )
  returning * into v_assignment;

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'propose_employee_position_assignment',
    'app.employee_position_assignments', v_assignment.id, 'success', null, null, app.employee_position_assignment_audit_projection(v_assignment)
  );

  return v_assignment;
end;
$$;

comment on function app.propose_employee_position_assignment is
  'HRT-275 (section 21 main flow, step 1): creates a status=''pending_approval'' proposal -- never immediately effective. Serves hire/transfer/promotion/demotion/lateral_move/reorganization/secondary_assignment/correction uniformly, distinguished by change_reason/assignment_type. p_expected_version guards the EMPLOYEE row (not yet any assignment row, since none exists until this call creates it).';

create function app.decide_employee_position_assignment(
  p_assignment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.employee_position_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assignment app.employee_position_assignments;
  v_employee app.employees;
  v_position app.positions;
  v_predecessor app.employee_position_assignments;
  v_predecessor_found boolean;
  v_headcount integer;
  v_lock_key bigint;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide an assignment proposal' using errcode = 'check_violation';
  end if;

  select * into v_assignment from app.employee_position_assignments where id = p_assignment_id for update;
  if not found or not app.has_active_tenant_membership(v_assignment.tenant_id, p_actor_auth_user_id) then
    raise exception 'assignment_not_found: %', p_assignment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assignment.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assignment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assignment.record_version <> p_expected_version then
    raise exception 'stale_version: assignment % expected version % but found %', p_assignment_id, p_expected_version, v_assignment.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_assignment.status <> 'pending_approval' then
    raise exception 'assignment_not_pending: assignment % is % and cannot be decided', p_assignment_id, v_assignment.status
      using errcode = 'check_violation';
  end if;

  if p_decision = 'reject' then
    update app.employee_position_assignments
    set status = 'rejected', decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason
    where id = p_assignment_id and record_version = p_expected_version
    returning * into v_assignment;
    if not found then
      raise exception 'stale_version: assignment % target row was concurrently modified (expected version %)', p_assignment_id, p_expected_version
        using errcode = 'serialization_failure';
    end if;

    perform app.capture_audit_event(
      v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_employee_position_assignment',
      'app.employee_position_assignments', v_assignment.id, 'success', p_reason, null, app.employee_position_assignment_audit_projection(v_assignment)
    );
    return v_assignment;
  end if;

  -- Approve path (decisions 7, 8: capacity + cycle re-checked authoritatively here).
  select * into v_employee from app.employees where master_record_id = v_assignment.master_record_id for update;
  select * into v_position from app.positions where id = v_assignment.position_id;

  if v_position.status <> 'active' then
    raise exception 'position_inactive: position % is inactive and cannot be activated', v_assignment.position_id using errcode = 'check_violation';
  end if;

  if v_assignment.manager_employee_id is not null and app.would_create_employee_manager_cycle(v_assignment.master_record_id, v_assignment.manager_employee_id) then
    raise exception 'cyclic_reporting_line: approving assignment % would create a cyclic reporting line', p_assignment_id
      using errcode = 'check_violation';
  end if;

  if v_assignment.assignment_type = 'primary' then
    -- Position-scoped advisory lock (mirrors app.commit_vendor_rate_import_job's own
    -- job-scoped-advisory-lock precedent) -- serializes concurrent approvals against
    -- the SAME position's capacity so two racing approvals cannot both pass the
    -- count check before either commits.
    v_lock_key := hashtextextended('employee_position_assignments:position:' || v_assignment.position_id::text, 0);
    perform pg_advisory_xact_lock(v_lock_key);

    -- Predecessor lookup happens BEFORE the capacity check (not after, as a naive
    -- reading of "close predecessor, then check capacity" would do) so that a
    -- same-position correction/promotion -- which closes the employee's own existing
    -- occupancy of THIS SAME position and immediately replaces it -- does not
    -- double-count that soon-to-be-closed predecessor against the position's own
    -- capacity. A predecessor at a DIFFERENT position is never excluded (a genuine
    -- transfer away from one position and into another must be capacity-checked at
    -- the destination without any special-casing).
    select * into v_predecessor
    from app.employee_position_assignments
    where master_record_id = v_assignment.master_record_id and assignment_type = 'primary' and status = 'active' and effective_end_date is null
    for update;
    v_predecessor_found := found;

    v_headcount := app.count_position_active_primary_headcount(
      v_assignment.position_id, v_assignment.validity_range,
      case when v_predecessor_found and v_predecessor.position_id = v_assignment.position_id then v_predecessor.id else null end
    );
    if v_headcount >= v_position.capacity then
      raise exception 'position_over_capacity: position % has % of % capacity slot(s) already committed for this date range', v_assignment.position_id, v_headcount, v_position.capacity
        using errcode = 'check_violation';
    end if;

    -- Close the currently open-ended primary predecessor (if any) BEFORE flipping
    -- this row to active, so the EXCLUDE constraint below sees a non-overlapping
    -- state -- exactly PRC-255's own established ordering.
    if v_predecessor_found then
      if v_assignment.effective_start_date <= v_predecessor.effective_start_date then
        raise exception 'invalid_effective_range: new assignment must start after the current assignment''s own start date (%)', v_predecessor.effective_start_date
          using errcode = 'check_violation';
      end if;
      update app.employee_position_assignments
      set effective_end_date = v_assignment.effective_start_date - 1
      where id = v_predecessor.id;
    end if;
  end if;

  begin
    update app.employee_position_assignments
    set status = 'active', decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason,
        previous_assignment_id = coalesce(previous_assignment_id, v_predecessor.id)
    where id = p_assignment_id and record_version = p_expected_version
    returning * into v_assignment;
  exception
    when exclusion_violation then
      raise exception 'assignment_overlap: an active % assignment already exists for this employee/position with an overlapping effective range', v_assignment.assignment_type
        using errcode = 'check_violation';
    when deadlock_detected then
      raise exception 'assignment_overlap: a concurrent decision on an overlapping assignment could not be serialized -- retry'
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: assignment % target row was concurrently modified (expected version %)', p_assignment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, metadata, actor_auth_user_id, actor_label)
  values (
    v_employee.tenant_id, v_employee.master_record_id, v_employee.lifecycle_status, v_employee.lifecycle_status, p_reason,
    jsonb_build_object('event', 'position_assignment', 'assignment_id', v_assignment.id, 'position_id', v_assignment.position_id, 'assignment_type', v_assignment.assignment_type, 'change_reason', v_assignment.change_reason, 'effective_start_date', v_assignment.effective_start_date),
    p_actor_auth_user_id, p_actor_label
  );

  -- Immediate sync only if already, or newly, in effect -- a future-dated approved
  -- assignment is left for app.activate_due_employee_position_assignments once its
  -- date arrives (decision 4).
  if v_assignment.effective_start_date <= current_date then
    perform app.sync_employee_current_assignment_cache(v_assignment);
  end if;

  perform app.capture_audit_event(
    v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_employee_position_assignment',
    'app.employee_position_assignments', v_assignment.id, 'success', p_reason, null, app.employee_position_assignment_audit_projection(v_assignment)
  );

  return v_assignment;
end;
$$;

comment on function app.decide_employee_position_assignment is
  'HRT-275 (section 21 main flow, step 2; HRS:Approve). Approve: re-validates position status, manager-cycle, and capacity (position-scoped advisory-locked, decision 7) authoritatively, closes the prior open-ended primary predecessor, flips this row to active, and syncs app.employees'' cache columns if already effective. Reject: a terminal, disclosed decision with a mandatory reason, the prior active assignment (if any) is left completely untouched (section 23 "keep the current effective assignment intact").';

create function app.cancel_employee_position_assignment(
  p_assignment_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.employee_position_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assignment app.employee_position_assignments;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel an assignment' using errcode = 'check_violation';
  end if;

  select * into v_assignment from app.employee_position_assignments where id = p_assignment_id for update;
  if not found or not app.has_active_tenant_membership(v_assignment.tenant_id, p_actor_auth_user_id) then
    raise exception 'assignment_not_found: %', p_assignment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assignment.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assignment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assignment.record_version <> p_expected_version then
    raise exception 'stale_version: assignment % expected version % but found %', p_assignment_id, p_expected_version, v_assignment.record_version
      using errcode = 'serialization_failure';
  end if;

  -- Section 23 "keep the current effective assignment intact": only a proposal still
  -- awaiting decision, or an approved-but-not-yet-effective (future-dated) assignment,
  -- may be cancelled. One already in effect today may never be cancelled retroactively
  -- -- only superseded by a new, properly-approved transfer.
  if v_assignment.status = 'active' and v_assignment.effective_start_date <= current_date then
    raise exception 'assignment_not_cancellable: assignment % is already in effect and cannot be cancelled -- propose a new transfer instead', p_assignment_id
      using errcode = 'check_violation';
  end if;
  if v_assignment.status not in ('pending_approval', 'active') then
    raise exception 'assignment_not_cancellable: assignment % is % and cannot be cancelled', p_assignment_id, v_assignment.status
      using errcode = 'check_violation';
  end if;

  update app.employee_position_assignments
  set status = 'cancelled', decided_by = coalesce(decided_by, p_actor_label), decided_at = coalesce(decided_at, now()), decided_reason = p_reason
  where id = p_assignment_id and record_version = p_expected_version
  returning * into v_assignment;
  if not found then
    raise exception 'stale_version: assignment % target row was concurrently modified (expected version %)', p_assignment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_employee_position_assignment',
    'app.employee_position_assignments', v_assignment.id, 'success', p_reason, null, app.employee_position_assignment_audit_projection(v_assignment)
  );

  return v_assignment;
end;
$$;

-- Maintenance sweep (decision 12) -- service_role/HRS:Override gated. No live
-- cron/scheduler exists anywhere in this repository yet to invoke this
-- automatically (the same disclosed "mechanism proven, live wiring deferred"
-- posture as PLT-107's correlation-id generation and HRT-274's staged-import
-- Server Action trigger surface) -- callable on demand today, and the natural
-- attachment point for a future scheduled-job capability.
create function app.activate_due_employee_position_assignments(p_tenant_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns integer
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.employee_position_assignments;
  v_count integer := 0;
  v_skipped integer := 0;
  v_skipped_ids uuid[] := '{}';
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_row in
    select a.* from app.employee_position_assignments a
    join app.employees e on e.master_record_id = a.master_record_id
    where a.tenant_id = p_tenant_id
      and a.assignment_type = 'primary'
      and a.status = 'active'
      and a.effective_start_date <= current_date
      and e.position_id is distinct from a.position_id
    order by a.effective_start_date
  loop
    -- HRT-275 review-round fix (CRITICAL, adversarial review): app.sync_employee_
    -- current_assignment_cache now raises (check_violation) when the row it is about
    -- to sync would create a manager cycle against the graph's current live state
    -- (only reachable here when a second, independently-approved future-dated
    -- assignment on the OTHER side of the same pair already activated earlier in this
    -- same sweep). Caught per-row so one cyclic row can never abort the rest of the
    -- sweep, nor silently proceed as if it had synced -- it is skipped and disclosed
    -- via the audit event below.
    begin
      perform app.sync_employee_current_assignment_cache(v_row);
      v_count := v_count + 1;
    exception
      when check_violation then
        v_skipped := v_skipped + 1;
        v_skipped_ids := array_append(v_skipped_ids, v_row.id);
    end;
  end loop;

  if v_count > 0 then
    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_due_employee_position_assignments',
      'app.employee_position_assignments', p_tenant_id, 'success', null, null, jsonb_build_object('activated_count', v_count)
    );
  end if;

  if v_skipped > 0 then
    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'activate_due_employee_position_assignments',
      'app.employee_position_assignments', p_tenant_id, 'failure',
      'cyclic_reporting_line detected during maintenance sweep -- assignment(s) left unsynced; app.employees.manager_employee_id remains at its prior, cycle-free value for the affected employee(s) until the conflicting assignment is resolved and the sweep is retried',
      null, jsonb_build_object('skipped_count', v_skipped, 'skipped_assignment_ids', to_jsonb(v_skipped_ids))
    );
  end if;

  return v_count;
end;
$$;

comment on function app.activate_due_employee_position_assignments is
  'HRT-275 (decision 4, decision 12): sweeps approved primary assignments whose effective_start_date has arrived but whose employees.position_id cache does not yet match, and syncs them. Idempotent -- a repeated call re-syncs nothing once every due row matches its own cache. Review-round fix: a row whose sync would create a manager cycle is skipped (not synced) and disclosed via a dedicated failure-result audit event, rather than corrupting the reporting-line graph or aborting the whole sweep -- returns only the count of rows genuinely activated.';

-- ===========================================================================
-- 10. Impact preview (decision 6, section 24 binding rule).
-- ===========================================================================

create function app.preview_employee_position_assignment_impact(
  p_master_record_id uuid, p_position_id uuid, p_manager_employee_id uuid, p_effective_start_date date, p_actor_auth_user_id uuid, p_actor_label text
)
returns table (
  current_position_id uuid, current_position_title text, current_manager_employee_id uuid,
  proposed_position_title text, proposed_grade_id uuid, proposed_company_org_unit_id uuid, proposed_branch_org_unit_id uuid, proposed_department_org_unit_id uuid,
  position_capacity integer, position_current_headcount integer, position_capacity_remaining integer,
  would_create_manager_cycle boolean, target_org_unit_active boolean,
  direct_report_count integer, pending_change_request_count integer, pending_duplicate_candidate_count integer,
  downstream_disclosure text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_position app.positions;
  v_unit app.org_units;
  v_lineage record;
  v_headcount integer;
  v_would_cycle boolean;
  v_direct_reports integer;
  v_pending_change_requests integer;
  v_pending_duplicates integer;
  v_downstream_disclosure text;
begin
  select * into v_employee from app.employees e where e.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_position from app.positions where id = p_position_id and tenant_id = v_employee.tenant_id;
  if not found then
    raise exception 'position_not_found: % is not a valid position for tenant %', p_position_id, v_employee.tenant_id using errcode = 'no_data_found';
  end if;

  select * into v_unit from app.org_units where id = v_position.org_unit_id;
  select * into v_lineage from app.resolve_org_unit_lineage(v_position.org_unit_id);
  v_headcount := app.count_position_active_primary_headcount(p_position_id, daterange(coalesce(p_effective_start_date, current_date), coalesce(p_effective_start_date, current_date), '[]'));
  v_would_cycle := (p_manager_employee_id is not null and app.would_create_employee_manager_cycle(p_master_record_id, p_manager_employee_id));
  v_direct_reports := (select count(*)::integer from app.employees where manager_employee_id = p_master_record_id);
  v_pending_change_requests := (select count(*)::integer from app.employee_change_requests where master_record_id = p_master_record_id and status = 'pending');
  v_pending_duplicates := (select count(*)::integer from app.employee_duplicate_candidates where source_master_record_id = p_master_record_id and decision = 'pending');
  v_downstream_disclosure := 'Approval-queue org-scope, Payroll input recalculation, and Ticketing queue routing are not yet integrated capabilities in this repository (Payroll: Prompt 282; Ticketing: Prompt 285+) -- their impact is not computed here rather than fabricated.';

  -- HRT-275 review-round fix (MEDIUM, adversarial review): section 18 names "impact
  -- preview" among what audit must record, and section 33's acceptance criteria
  -- requires "previewed and auditable" -- the original body computed every signal but
  -- never called app.capture_audit_event at all, leaving no forensic record of what
  -- was actually disclosed to a decision-maker before a reorganization/transfer.
  -- Captured as its own explicit, non-sensitive projection (no raw row/to_jsonb),
  -- result='success', after_value carries every computed signal -- so a later audit
  -- can reconstruct exactly what this call showed and when.
  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'preview_employee_position_assignment_impact',
    'app.employee_position_assignments', p_master_record_id, 'success', null, null,
    jsonb_build_object(
      'master_record_id', p_master_record_id, 'position_id', p_position_id, 'grade_id', v_position.grade_id,
      'manager_employee_id', p_manager_employee_id, 'effective_start_date', p_effective_start_date,
      'position_capacity', v_position.capacity, 'position_current_headcount', v_headcount,
      'position_capacity_remaining', greatest(v_position.capacity - v_headcount, 0),
      'would_create_manager_cycle', v_would_cycle, 'target_org_unit_active', (v_unit.status = 'active'),
      'direct_report_count', v_direct_reports, 'pending_change_request_count', v_pending_change_requests,
      'pending_duplicate_candidate_count', v_pending_duplicates
    )
  );

  return query
  select
    v_employee.position_id, v_employee.position_title, v_employee.manager_employee_id,
    v_position.title, v_position.grade_id, v_lineage.company_org_unit_id, v_lineage.branch_org_unit_id, v_lineage.department_org_unit_id,
    v_position.capacity, v_headcount, greatest(v_position.capacity - v_headcount, 0),
    v_would_cycle, (v_unit.status = 'active'),
    v_direct_reports, v_pending_change_requests, v_pending_duplicates,
    v_downstream_disclosure;
end;
$$;

comment on function app.preview_employee_position_assignment_impact is
  'HRT-275 (decision 6, section 24 "reorganization requires impact preview for approval queues, roles, payroll, time and open tickets"). Computes every REAL, currently-existing impact signal (target position/grade/org path, capacity remaining, manager-cycle check, this employee''s own real direct-report count, real pending change-request/duplicate-candidate counts) and returns an explicit downstream_disclosure for the capabilities that do not exist yet in this repository, rather than fabricating a number for them. Callable standalone, before any proposal exists (section 21''s own preview-before-propose ordering). Review-round fix: now takes p_actor_label and self-captures a canonical app.audit_logs entry (an explicit projection, never a raw row) on every call, closing section 18/33''s "previewed and auditable" requirement.';

-- ===========================================================================
-- 11. Read RPCs (HRS:View unless noted).
-- ===========================================================================

create function app.get_employee_position_assignment_history(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.employee_position_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  select * into v_employee from app.employees e where e.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.employee_position_assignments
  where master_record_id = p_master_record_id
  order by effective_start_date desc, created_at desc;
end;
$$;

create function app.get_my_employee_position_assignment_history(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.employee_position_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_caller_user_id uuid;
  v_master_record_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  select u.id into v_caller_user_id from app.users u where u.auth_user_id = p_actor_auth_user_id and u.tenant_id = p_tenant_id;
  if v_caller_user_id is null then
    return;
  end if;

  select e.master_record_id into v_master_record_id from app.employees e where e.tenant_id = p_tenant_id and e.user_id = v_caller_user_id;
  if v_master_record_id is null then
    return;
  end if;

  return query
  select * from app.employee_position_assignments
  where master_record_id = v_master_record_id
  order by effective_start_date desc, created_at desc;
end;
$$;

comment on function app.get_my_employee_position_assignment_history is 'HRT-275: self-only, identity-match-gated like app.get_my_employee_profile (HRT-274) -- never requires HRS:View. Returns zero rows (never raises) when the caller has no linked employee profile.';

create function app.get_employee_current_assignment(p_master_record_id uuid, p_actor_auth_user_id uuid, p_as_of date default current_date)
returns setof app.employee_position_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  select * into v_employee from app.employees e where e.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.employee_position_assignments
  where master_record_id = p_master_record_id and status = 'active' and validity_range @> p_as_of
  order by assignment_type;
end;
$$;

comment on function app.get_employee_current_assignment is
  'HRT-275: the genuinely point-in-time-correct read (section 20 "test ... historical queries") -- reads directly from app.employee_position_assignments'' own validity_range, never from app.employees'' convenience cache, so it is correct even for a p_as_of date whose assignment has not yet been synced by app.activate_due_employee_position_assignments.';

create function app.get_employee_manager_chain(p_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (depth integer, master_record_id uuid, employee_number text, full_name text, position_title text)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
  v_current uuid;
  v_depth integer := 0;
  v_hops integer := 0;
  v_row record;
begin
  select * into v_employee from app.employees e where e.master_record_id = p_master_record_id;
  if not found or not app.has_active_tenant_membership(v_employee.tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: %', p_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_employee.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_employee.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Bounded chain walk (decision 8, reused from app.assert_no_employee_manager_cycle's
  -- own 200-hop bound) -- current manager-of-record only, from app.employees'
  -- own synced cache column, never a recursive CTE.
  v_current := v_employee.manager_employee_id;
  while v_current is not null and v_hops < 200 loop
    v_hops := v_hops + 1;
    v_depth := v_depth + 1;
    select e.master_record_id, m.code, e.full_name, e.position_title into v_row from app.employees e join app.master_records m on m.id = e.master_record_id where e.master_record_id = v_current;
    if not found then
      exit;
    end if;
    return query select v_depth, v_row.master_record_id, v_row.code, v_row.full_name, v_row.position_title;
    -- Table-aliased and explicitly qualified: this function's own RETURNS TABLE
    -- includes master_record_id, so a bare reference to either name here is
    -- genuinely ambiguous against that OUT column -- the identical class of bug
    -- HRT-274's own app.get_employee_profile/app.get_my_employee_profile/
    -- app.list_my_team_employees hit and fixed, live-reproduced again here.
    select e.manager_employee_id into v_current from app.employees e where e.master_record_id = v_current;
  end loop;
end;
$$;

comment on function app.get_employee_manager_chain is 'HRT-275 (section 14 "hierarchy read"): the employee''s own reporting chain, root-most manager last, bounded to 200 hops (decision 8, unchanged from app.assert_no_employee_manager_cycle''s own bound).';

create function app.get_org_position_tree(p_tenant_id uuid, p_actor_auth_user_id uuid, p_root_org_unit_id uuid default null)
returns table (
  org_unit_id uuid, org_unit_code text, org_unit_name text, unit_type text, depth integer,
  position_id uuid, position_code text, position_title text, capacity integer, current_headcount integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_scope_ids uuid[];
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_root_org_unit_id is not null then
    if not exists (select 1 from app.org_units where id = p_root_org_unit_id and tenant_id = p_tenant_id) then
      raise exception 'org_unit_not_found: % is not a valid org unit for tenant %', p_root_org_unit_id, p_tenant_id using errcode = 'no_data_found';
    end if;
    -- Reuses the pre-existing, path-indexed descendant helper (section 17: no
    -- recursive CTE) -- never reimplemented.
    v_scope_ids := array(select p_root_org_unit_id union select * from app.org_unit_descendant_ids(p_root_org_unit_id));
  end if;

  return query
  select ou.id, ou.code, ou.name, ou.unit_type, ou.depth,
         p.id, p.code, p.title, p.capacity,
         coalesce((select app.count_position_active_primary_headcount(p.id, daterange(current_date, current_date, '[]'))), 0)
  from app.org_units ou
  left join app.positions p on p.org_unit_id = ou.id and p.tenant_id = p_tenant_id
  where ou.tenant_id = p_tenant_id
    and (p_root_org_unit_id is null or ou.id = any(v_scope_ids))
  order by ou.path, ou.code, p.code;
end;
$$;

comment on function app.get_org_position_tree is
  'HRT-275 (section 15 "organization-linked position tree", section 17 "prevent recursive N+1 hierarchy loads"): one joined query over app.org_units (scoped via the pre-existing path-indexed app.org_unit_descendant_ids helper, never a recursive CTE) and app.positions -- an org unit with no position at all still appears (LEFT JOIN), with null position_id, so the tree UI can render every node.';

-- ===========================================================================
-- 12. RLS -- default-deny form (pattern (3), identical to HRT-274's own policies).
-- ===========================================================================

alter table app.position_grades enable row level security;
alter table app.positions enable row level security;
alter table app.employee_position_assignments enable row level security;

create policy position_grades_select_scoped on app.position_grades
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy positions_select_scoped on app.positions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy employee_position_assignments_select_scoped on app.employee_position_assignments
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 13. Grants. No column-restricted grant is needed on any of these three tables
--    (decision 9: no PII/payroll column exists on any of them) -- plain `select` to
--    authenticated, mirroring app.org_units' own established precedent for
--    non-sensitive tenant-scoped structural data, RLS-row-scoped as above.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.position_grades to authenticated, service_role;
grant insert, update, delete on app.position_grades to service_role;

grant select on app.positions to authenticated, service_role;
grant insert, update, delete on app.positions to service_role;

grant select on app.employee_position_assignments to authenticated, service_role;
grant insert, update, delete on app.employee_position_assignments to service_role;

grant execute on function app.resolve_org_unit_lineage(uuid) to service_role;
grant execute on function app.would_create_employee_manager_cycle(uuid, uuid) to service_role;
grant execute on function app.count_position_active_primary_headcount(uuid, daterange, uuid) to service_role;
grant execute on function app.sync_employee_current_assignment_cache(app.employee_position_assignments) to service_role;
grant execute on function app.position_grade_audit_projection(app.position_grades) to service_role;
grant execute on function app.position_audit_projection(app.positions) to service_role;
grant execute on function app.employee_position_assignment_audit_projection(app.employee_position_assignments) to service_role;

grant execute on function app.create_position_grade(uuid, text, text, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_position_grade(uuid, integer, text, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.set_position_grade_status(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_position_grades(uuid, uuid, text) to authenticated, service_role;

grant execute on function app.create_position(uuid, text, text, uuid, uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_position(uuid, integer, text, uuid, uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.set_position_status(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_positions(uuid, uuid, uuid, text, text, integer, text) to authenticated, service_role;
grant execute on function app.get_position(uuid, uuid) to authenticated, service_role;
grant execute on function app.export_positions(uuid, uuid, text, integer) to authenticated, service_role;

grant execute on function app.propose_employee_position_assignment(uuid, integer, uuid, uuid, uuid, text, numeric, date, date, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_employee_position_assignment(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_employee_position_assignment(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.activate_due_employee_position_assignments(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.preview_employee_position_assignment_impact(uuid, uuid, uuid, date, uuid, text) to authenticated, service_role;

grant execute on function app.get_employee_position_assignment_history(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_my_employee_position_assignment_history(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_employee_current_assignment(uuid, uuid, date) to authenticated, service_role;
grant execute on function app.get_employee_manager_chain(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_org_position_tree(uuid, uuid, uuid) to authenticated, service_role;
