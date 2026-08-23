-- HRIS capability HRT-283 (Prompt 283, CG-S12-HRT-011) -- KPI and
-- Performance. Eleventh Phase 7 capability, built directly on HRT-274
-- (Employee Master), HRT-275 (Organization and Position Linkage), and
-- HRT-278..282 (Attendance/Roster/Leave/Overtime/Timesheet/Payroll), reusing
-- the established manager-scope (self/direct-manager/HRS:View) pattern
-- those checkpoints already set rather than reinventing it. First of a
-- 3-prompt batch (283, 284, 285); Tier C review runs once, combined, after
-- all three are built (BUILD_EXECUTION_PROTOCOL.md section 3.4, batch cap
-- 3 following HRT-282's own 1 CRITICAL + 5 HIGH Tier C result).
--
-- ===========================================================================
-- DECISION 1 -- no rating-band/label subsystem; the outcome's own exact
-- final_score IS the explainable output (Prompt 283 section 24 "a score is
-- explainable from visible permitted inputs").
-- ===========================================================================
--
-- The prompt never names a qualitative rating-scale/banding requirement
-- (unlike, say, a 5-point "Exceeds/Meets/Below" label). Building one would
-- invent unspecified business configuration (how many bands, what labels,
-- what boundary tie-break rule) this checkpoint has no mandate to decide --
-- the same proportionate-effort call HRT-282 made declining a generic
-- formula evaluator. `app.performance_outcomes.score_breakdown` (an
-- explicit, non-free-text jsonb allowlist of goalAssignmentId/
-- kpiDefinitionId/weight/rawScore/weightedContribution per goal, NEVER
-- `to_jsonb(whole_row)` -- taxonomy C-07) plus the exact numeric
-- `final_score` already satisfy "explainable exact-decimal scoring" without
-- a label layer. Disclosed, not silently dropped.
--
-- ===========================================================================
-- DECISION 2 -- the manager assessment is the SOLE source of the computed
-- score; self and reviewer assessments are real, captured, visible inputs
-- but do not themselves feed the weighted-sum formula.
-- ===========================================================================
--
-- Prompt 283 names self/manager/reviewer stages but never specifies a
-- blending algorithm across them. Inventing one (e.g. 50/30/20 self/
-- manager/reviewer) would be unsupported business configuration. The
-- manager-assessment-is-authoritative model is the standard, defensible
-- shape (self informs, peers inform, the manager decides) and keeps the
-- formula in decision 1 exactly reproducible from ONE assessment's own
-- per-goal raw_score values, never an opaque cross-assessment average.
--
-- ===========================================================================
-- DECISION 3 -- direct-manager-only "effective team" scope, reused verbatim
-- from HRT-278/279/280/281 (mandatory reading item, "reuse the established
-- manager-scope pattern... do not reinvent").
-- ===========================================================================
--
-- Every list/visibility predicate below uses the identical
-- `e.manager_employee_id = v_self.master_record_id` single-level direct-
-- report shape `app.list_overtime_requests`/`app.list_leave_requests`/
-- `app.list_attendance_sessions` already established -- never a recursive
-- org-tree walk, never a second manager-hierarchy mechanism.
--
-- ===========================================================================
-- DECISION 4 -- calibration and appeal-decision use direct HRS:Approve/
-- HRS:Override gating with a structural self-decision block, NOT PLT-123.
-- ===========================================================================
--
-- HRT-282 decision 6 reserved PLT-123 maker-checker for the ONE genuinely
-- irreversible, batch-wide, fund-disbursing moment (payroll run
-- finalization). Nothing in this capability is batch-wide or irreversible
-- in that sense -- every outcome remains reversible through this
-- capability's OWN appeal/reopen workflow, which is itself governed. So:
-- calibration requires HRS:Override + a mandatory reason + a structural
-- self-calibration block (an actor may never calibrate their own outcome,
-- mirrors `decide_payroll_reimbursement_request`'s self-approval block);
-- appeal decision requires HRS:Approve + a mandatory reason + a structural
-- block against the appellant deciding their own appeal. "Governed...
-- reason + authority required" (section 24) is satisfied without a second
-- approval-routing mechanism.
--
-- ===========================================================================
-- DECISION 5 -- manager/reviewer assignment is resolved ONCE and frozen;
-- reassignment is a distinct, explicit, audited action that never mutates
-- or deletes an already-submitted assessment (mandatory reading item,
-- "manager reassignment does NOT silently transfer already-submitted
-- reviews").
-- ===========================================================================
--
-- `app.performance_reviewer_assignments` freezes `assigned_to_employee_id`
-- at the moment it is created (either explicitly via
-- `app.assign_performance_reviewer`, or auto-resolved from the employee's
-- CURRENT `app.employees.manager_employee_id` the first time a goal is
-- assigned, via `app._ensure_performance_manager_assignment`) -- it is
-- never re-derived live from the org chart on every read. If the real-
-- world manager later changes, the assignment does NOT silently follow;
-- only `app.reassign_performance_reviewer_assignment` (HRS:Override,
-- mandatory reason) can change it, and it does so by marking the OLD
-- assignment `status='reassigned'` (the old row and any submitted
-- assessment tied to it are NEVER mutated or deleted) and creating a BRAND
-- NEW assignment + a fresh `not_started` assessment for the new assignee.
--
-- ===========================================================================
-- DECISION 6 -- a genuine k-anonymity-style floor (k=5, fixed) on the one
-- grouped/aggregate report this checkpoint builds.
-- ===========================================================================
--
-- `app.report_performance_cycle_score_distribution` groups outcomes by
-- department and returns every group's real employee_count, but suppresses
-- (nulls) the disclosive statistic itself -- avg_final_score -- for any
-- group with fewer than 5 employees, marking `suppressed=true`. This is a
-- field-level mask on the sensitive aggregate, not merely a UI hint --
-- enforced inside the SECURITY DEFINER function itself, so no caller,
-- including a genuinely HRS:View-performance-holding HR actor, can observe
-- a small cohort's average score. A fixed k=5 (not tenant-configurable) is
-- a disclosed, bounded V1 scope decision.
--
-- ===========================================================================
-- DECISION 7 -- taxonomy C-24 audit-masking discipline applied from the
-- start (this phase's own 3-times-repeated defect: HRT-280, HRT-281,
-- HRT-282), never retrofitted.
-- ===========================================================================
--
-- Every `capture_audit_event` call below passes `p_reason => null`
-- unconditionally, and its `after_value` jsonb is built from an explicit,
-- reviewed allowlist that NEVER includes a raw_score/baseline_score/
-- calibrated_score/final_score/weight/target_value/actual_value or any
-- free-text field (score_rationale, overall_comment, adjustment_reason,
-- appeal_reason, decision_reason, na_reason, note) -- only ids, enum
-- status/decision strings, and counts. `app.query_audit_logs` is readable
-- by any plain tenant_admin (zero HRS role required) -- materially broader
-- than this capability's own HRS:View personal data / self / effective-team
-- visibility model, exactly the gap C-24 documents.
--
-- ===========================================================================
-- DECISION 8 -- no autonomous downstream action; zero write anywhere in
-- this migration to app.employees.lifecycle_status, any app.payroll_*
-- table, or any role/permission table (business rule, section 24 "outcomes
-- do not automatically alter pay, employment or access").
-- ===========================================================================
--
-- Grep-verified before commit (recorded in the build log): this migration
-- contains no `update app.employees set lifecycle_status`, no
-- `insert into app.payroll_` / `update app.payroll_`, and no
-- `insert into app.role_` / `app.permissions` write of any kind -- decision
-- 0 below reuses an already-legal permission action rather than seeding one.
--
-- ===========================================================================
-- DECISION 9 -- data-classification: reuse category 'pii', do not invent a
-- new 'performance' category ad hoc.
-- ===========================================================================
--
-- `scripts/data-classification/registry.ts`'s CATEGORIES const has no
-- 'performance' entry (unlike 'payroll', which HRT-274 explicitly reserved
-- ahead of time). Adding a new shared category is a cross-cutting taxonomy
-- change (CATEGORY_DEFAULT_LEVEL, CATEGORY_RETENTION_CLASS, and
-- DATA_CLASSIFICATION_STANDARDS.md all need updating) outside this single
-- capability's own mandate. Performance ratings/rationale/reasons are
-- registered under the existing 'pii' category (restricted-level personal
-- data about a specific employee), disclosed rather than silently reusing
-- 'payroll' or inventing a new bucket.
--
-- ===========================================================================
-- DECISION 10 -- deliberately NOT built, disclosed rather than silently
-- dropped (taxonomy C-23 discipline).
-- ===========================================================================
--
-- No staged-import (PLT-131/132) crosswalk for historical ratings/goals
-- (section 19's own migration-impact note, not named in section 20's
-- "detailed implementation tasks" bullets) -- a genuinely new, unrequested-
-- here build, matching HRT-275's identical "no staged-import crosswalk"
-- disclosure for position/grade/assignment rows. No predictive/AI scoring
-- of any kind (section 13's own explicit "Step 14" exclusion). No REST/
-- GraphQL adapter (repository-wide Phase 1-6 precedent). No template-KPI-
-- item removal RPC (add-only pre-publish; a mis-added item requires
-- archiving and recreating the template before publish) -- disclosed, not
-- built, low-severity.

-- ===========================================================================
-- DECISION 0 -- no new permission row; reuse the already-legal, already-
-- seeded `HRS:View personal data` action as this capability's own
-- protected "see individual performance content beyond self/manager/
-- reviewer" gate.
-- ===========================================================================
--
-- `app.permissions.action` is closed by a repository-wide, deliberately
-- fixed CHECK constraint (`permissions_action_check`,
-- `20260716103445_create_roles_permissions.sql`) that every capability
-- since HRT-274's own explicit disclosure (mirroring ADR-0020's identical
-- discipline) has reused rather than altered -- confirmed live: a first
-- attempt at a bespoke `('View performance', 'HRS', ...)` seed row was
-- rejected by that constraint during this checkpoint's own adversarial
-- `psql` testing. `View personal data` (already `protected=true`,
-- category `sensitive`, seeded at PLT-111 and already used by HRT-274 for
-- national_id/dob/personal_address masking) is the closest existing fit --
-- performance ratings/rationale are personal, sensitive, employee-specific
-- data in the same sense national ID and date of birth are. Reused
-- verbatim, never widened, matching HRT-282 decision 5's identical
-- "self/direct-manager/assigned-reviewer OR this PROTECTED permission
-- specifically -- never plain HRS:View" shape.

-- ===========================================================================
-- 1. app.performance_kpi_definitions / app.performance_kpi_definition_versions
--    -- the versioned KPI library (decision 1, section 13).
-- ===========================================================================

create table app.performance_kpi_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  name text not null,
  description text,
  unit_of_measure text not null default 'percent',
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint performance_kpi_definitions_code_check check (code ~ '^[a-z0-9_]{2,60}$'),
  constraint performance_kpi_definitions_name_check check (length(trim(name)) > 0),
  constraint performance_kpi_definitions_unit_check check (unit_of_measure in ('percent', 'count', 'currency', 'ratio', 'qualitative')),
  constraint performance_kpi_definitions_tenant_code_unique unique (tenant_id, code)
);

comment on table app.performance_kpi_definitions is
  'HRT-283: the KPI identity catalogue -- code/name/description/unit are fixed metadata once created (not editable after creation in this checkpoint, a disclosed V1 boundary); the versioned scoring configuration lives on app.performance_kpi_definition_versions below.';

create index performance_kpi_definitions_tenant_idx on app.performance_kpi_definitions (tenant_id);

create table app.performance_kpi_definition_versions (
  id uuid primary key default gen_random_uuid(),
  kpi_definition_id uuid not null references app.performance_kpi_definitions (id),
  tenant_id uuid not null references app.tenants (id),
  version_number integer not null,
  status text not null default 'active',
  scoring_method text not null,
  target_direction text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint performance_kpi_definition_versions_status_check check (status in ('active', 'archived')),
  constraint performance_kpi_definition_versions_method_check check (scoring_method in ('target_ratio', 'milestone_percent', 'qualitative_scale')),
  constraint performance_kpi_definition_versions_direction_shape_check check (
    (scoring_method = 'target_ratio' and target_direction in ('higher_is_better', 'lower_is_better'))
    or (scoring_method <> 'target_ratio' and target_direction is null)
  ),
  constraint performance_kpi_definition_versions_unique unique (kpi_definition_id, version_number)
);

comment on table app.performance_kpi_definition_versions is
  'HRT-283 (decision 1): exactly one active version per KPI at a time -- app.create_performance_kpi_definition_version archives the prior active version atomically. A goal assignment freezes the specific version it was assigned against (app.performance_goal_assignments.kpi_version_id), so archiving a version never disturbs an already-assigned goal''s own scoring rule -- versioned and exact (business rule, section 24).';

create index performance_kpi_definition_versions_kpi_status_idx on app.performance_kpi_definition_versions (kpi_definition_id, status);
create index performance_kpi_definition_versions_tenant_idx on app.performance_kpi_definition_versions (tenant_id);

create function app.touch_performance_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

comment on function app.touch_performance_row is
  'HRT-283: shared record_version-bump trigger for every versioned table below, mirroring app.touch_payroll_row (HRT-282) -- reused, never reimplemented per-table.';

create trigger performance_kpi_definition_versions_touch before update on app.performance_kpi_definition_versions
  for each row execute function app.touch_performance_row();

-- ===========================================================================
-- 2. app.performance_templates / app.performance_template_kpi_items -- the
--    reusable cycle template (weighted KPI slot configuration, section 13).
-- ===========================================================================

create table app.performance_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  name text not null,
  status text not null default 'draft',
  weight_total_required numeric(5, 2) not null default 100.00,
  requires_reviewer_stage boolean not null default false,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint performance_templates_code_check check (code ~ '^[a-z0-9_-]{2,60}$'),
  constraint performance_templates_name_check check (length(trim(name)) > 0),
  constraint performance_templates_status_check check (status in ('draft', 'published', 'archived')),
  constraint performance_templates_weight_check check (weight_total_required > 0 and weight_total_required <= 100),
  constraint performance_templates_tenant_code_unique unique (tenant_id, code)
);

comment on table app.performance_templates is
  'HRT-283: a reusable weighted-goal-slot configuration. Publish (app.publish_performance_template) validates every template_kpi_item''s own default_weight sums exactly to weight_total_required -- the "exact weight total" business rule (section 24) applied at the template''s own default configuration, independently re-validated per employee at goal-assignment completeness time too.';

create index performance_templates_tenant_status_idx on app.performance_templates (tenant_id, status);

create trigger performance_templates_touch before update on app.performance_templates
  for each row execute function app.touch_performance_row();

create table app.performance_template_kpi_items (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references app.performance_templates (id),
  tenant_id uuid not null references app.tenants (id),
  kpi_definition_id uuid not null references app.performance_kpi_definitions (id),
  default_weight numeric(5, 2) not null,
  is_required boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint performance_template_kpi_items_weight_check check (default_weight > 0 and default_weight <= 100),
  constraint performance_template_kpi_items_unique unique (template_id, kpi_definition_id)
);

comment on table app.performance_template_kpi_items is
  'HRT-283: add-only pre-publish (no remove RPC this checkpoint -- disclosed, decision 10); once a template is published it is immutable and a cycle referencing it copies weight_total_required at create time, never re-reads the template live.';

create index performance_template_kpi_items_template_idx on app.performance_template_kpi_items (template_id);

-- ===========================================================================
-- 3. app.performance_cycles -- the performance cycle instance (section 13,
--    21).
-- ===========================================================================

create table app.performance_cycles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  template_id uuid not null references app.performance_templates (id),
  code text not null,
  name text not null,
  cycle_type text not null default 'annual',
  period_start date not null,
  period_end date not null,
  goal_setting_due date,
  self_assessment_due date,
  manager_assessment_due date,
  calibration_due date,
  weight_total_required numeric(5, 2) not null,
  status text not null default 'draft',
  cancel_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint performance_cycles_code_check check (code ~ '^[a-z0-9_-]{2,60}$'),
  constraint performance_cycles_name_check check (length(trim(name)) > 0),
  constraint performance_cycles_type_check check (cycle_type in ('annual', 'semi_annual', 'quarterly', 'custom')),
  constraint performance_cycles_date_range_check check (period_end >= period_start),
  constraint performance_cycles_status_check check (
    status in ('draft', 'goal_setting_open', 'self_assessment_open', 'manager_assessment_open', 'calibration', 'acknowledgement', 'closed', 'cancelled')
  ),
  constraint performance_cycles_tenant_code_unique unique (tenant_id, code)
);

comment on table app.performance_cycles is
  'HRT-283 (section 21 main flow): draft -> goal_setting_open -> self_assessment_open -> manager_assessment_open -> calibration -> acknowledgement -> closed, or cancelled from any non-terminal state. weight_total_required is copied from the template at create time -- a later template edit never retroactively changes an in-flight cycle''s own requirement (versioned and exact).';

create index performance_cycles_tenant_status_idx on app.performance_cycles (tenant_id, status);
create index performance_cycles_tenant_dates_idx on app.performance_cycles (tenant_id, period_start desc);

create trigger performance_cycles_touch before update on app.performance_cycles
  for each row execute function app.touch_performance_row();

-- ===========================================================================
-- 4. app.performance_goal_assignments / app.performance_goal_progress_entries
--    -- weighted goal assignment and progress/evidence (section 13, 20).
-- ===========================================================================

create table app.performance_goal_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  cycle_id uuid not null references app.performance_cycles (id),
  employee_id uuid not null references app.employees (master_record_id),
  kpi_definition_id uuid not null references app.performance_kpi_definitions (id),
  kpi_version_id uuid not null references app.performance_kpi_definition_versions (id),
  weight numeric(5, 2) not null,
  target_value numeric(14, 4),
  target_unit text,
  status text not null default 'active',
  na_reason text,
  assigned_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint performance_goal_assignments_weight_check check (weight > 0 and weight <= 100),
  constraint performance_goal_assignments_target_check check (target_value is null or target_value >= 0),
  constraint performance_goal_assignments_status_check check (status in ('active', 'not_applicable')),
  constraint performance_goal_assignments_na_shape_check check (status <> 'not_applicable' or (na_reason is not null and length(trim(na_reason)) > 0)),
  constraint performance_goal_assignments_unique unique (cycle_id, employee_id, kpi_definition_id)
);

comment on table app.performance_goal_assignments is
  'HRT-283: one row per (cycle, employee, KPI). kpi_version_id freezes the specific scoring-rule version this goal was assigned against. Mid-cycle revision (weight/target edit, or marking not_applicable) is legal only before the employee''s own self assessment is submitted -- app.assign_performance_goal / app.mark_performance_goal_not_applicable both enforce this "goals_locked" gate identically (alternative flow, section 22).';

create index performance_goal_assignments_tenant_cycle_employee_idx on app.performance_goal_assignments (tenant_id, cycle_id, employee_id);

create trigger performance_goal_assignments_touch before update on app.performance_goal_assignments
  for each row execute function app.touch_performance_row();

create table app.performance_goal_progress_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  goal_assignment_id uuid not null references app.performance_goal_assignments (id),
  employee_id uuid not null references app.employees (master_record_id),
  actual_value numeric(14, 4),
  note text,
  evidence_file_id uuid references app.files (id),
  recorded_by_auth_user_id uuid,
  recorded_by text,
  recorded_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

comment on table app.performance_goal_progress_entries is
  'HRT-283: an append-only progress/evidence log against one goal assignment -- self, direct manager, or HRS:Edit may record an entry. Never mutated once written (a correction is a new entry, preserving history).';

create index performance_goal_progress_entries_goal_idx on app.performance_goal_progress_entries (goal_assignment_id, recorded_at desc);

-- ===========================================================================
-- 5. app.performance_reviewer_assignments -- manager AND multi-reviewer
--    (360) assignment, frozen and explicitly reassignable (decision 5).
-- ===========================================================================

create table app.performance_reviewer_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  cycle_id uuid not null references app.performance_cycles (id),
  employee_id uuid not null references app.employees (master_record_id),
  role text not null,
  assigned_to_employee_id uuid not null references app.employees (master_record_id),
  status text not null default 'active',
  reassigned_from_assignment_id uuid references app.performance_reviewer_assignments (id),
  reassign_reason text,
  assigned_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint performance_reviewer_assignments_role_check check (role in ('manager', 'reviewer')),
  constraint performance_reviewer_assignments_status_check check (status in ('active', 'reassigned')),
  constraint performance_reviewer_assignments_not_self_check check (assigned_to_employee_id <> employee_id)
);

comment on table app.performance_reviewer_assignments is
  'HRT-283 (decision 5): assigned_to_employee_id is resolved ONCE and frozen -- never re-derived live from app.employees.manager_employee_id after creation. app.reassign_performance_reviewer_assignment is the ONLY way to change it, and does so by creating a NEW row + marking this one reassigned, never mutating this row in place.';

create index performance_reviewer_assignments_tenant_cycle_employee_idx on app.performance_reviewer_assignments (tenant_id, cycle_id, employee_id);
create index performance_reviewer_assignments_assigned_to_idx on app.performance_reviewer_assignments (tenant_id, assigned_to_employee_id, status);

create unique index performance_reviewer_assignments_manager_active_unique on app.performance_reviewer_assignments (cycle_id, employee_id) where role = 'manager' and status = 'active';
create unique index performance_reviewer_assignments_reviewer_active_unique on app.performance_reviewer_assignments (cycle_id, employee_id, assigned_to_employee_id) where role = 'reviewer' and status = 'active';

create trigger performance_reviewer_assignments_touch before update on app.performance_reviewer_assignments
  for each row execute function app.touch_performance_row();

-- ===========================================================================
-- 6. app.performance_assessments / app.performance_assessment_kpi_scores --
--    self/manager/reviewer stages with explainable per-goal scoring
--    (decision 1, 2; section 13, 21).
-- ===========================================================================

create table app.performance_assessments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  cycle_id uuid not null references app.performance_cycles (id),
  employee_id uuid not null references app.employees (master_record_id),
  assessment_type text not null,
  reviewer_assignment_id uuid references app.performance_reviewer_assignments (id),
  assigned_to_employee_id uuid not null references app.employees (master_record_id),
  status text not null default 'not_started',
  overall_comment text,
  submitted_by text,
  submitted_at timestamptz,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint performance_assessments_type_check check (assessment_type in ('self', 'manager', 'reviewer')),
  constraint performance_assessments_status_check check (status in ('not_started', 'draft', 'submitted')),
  constraint performance_assessments_assignment_shape_check check (
    (assessment_type = 'self' and reviewer_assignment_id is null) or (assessment_type in ('manager', 'reviewer') and reviewer_assignment_id is not null)
  )
);

comment on table app.performance_assessments is
  'HRT-283: one row per (cycle, employee, self|manager|reviewer[, assignment]). assigned_to_employee_id is denormalized from the assignment (self: the employee themself) for fast, join-free visibility filtering. Once submitted, its own app.performance_assessment_kpi_scores rows are locked (app.upsert_performance_assessment_kpi_score refuses further writes).';

create index performance_assessments_tenant_cycle_employee_idx on app.performance_assessments (tenant_id, cycle_id, employee_id);
create index performance_assessments_assigned_to_idx on app.performance_assessments (tenant_id, assigned_to_employee_id, status);

create unique index performance_assessments_self_unique on app.performance_assessments (cycle_id, employee_id) where assessment_type = 'self';
create unique index performance_assessments_assignment_unique on app.performance_assessments (reviewer_assignment_id) where reviewer_assignment_id is not null;

create trigger performance_assessments_touch before update on app.performance_assessments
  for each row execute function app.touch_performance_row();

create table app.performance_assessment_kpi_scores (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  assessment_id uuid not null references app.performance_assessments (id),
  goal_assignment_id uuid not null references app.performance_goal_assignments (id),
  actual_value numeric(14, 4),
  manual_score numeric(6, 3),
  raw_score numeric(6, 3) not null,
  score_rationale text not null,
  scored_by text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint performance_assessment_kpi_scores_raw_score_check check (raw_score >= 0 and raw_score <= 100),
  constraint performance_assessment_kpi_scores_manual_score_check check (manual_score is null or (manual_score >= 0 and manual_score <= 100)),
  constraint performance_assessment_kpi_scores_rationale_check check (length(trim(score_rationale)) > 0),
  constraint performance_assessment_kpi_scores_unique unique (assessment_id, goal_assignment_id)
);

comment on table app.performance_assessment_kpi_scores is
  'HRT-283 (decision 1): raw_score is ALWAYS computed deterministically by app.compute_kpi_raw_score from the goal''s own scoring_method/target_direction/target_value plus actual_value (target_ratio, milestone_percent) or the assessor''s own manual_score (qualitative_scale) -- reproducible from visible permitted inputs, the "explainable" requirement. score_rationale is mandatory free text explaining the score -- stored here (RLS-scoped exactly like the parent assessment), never copied unmasked into app.audit_logs (taxonomy C-24).';

create index performance_assessment_kpi_scores_assessment_idx on app.performance_assessment_kpi_scores (assessment_id);

create trigger performance_assessment_kpi_scores_touch before update on app.performance_assessment_kpi_scores
  for each row execute function app.touch_performance_row();

-- ===========================================================================
-- 7. app.performance_outcomes / app.performance_calibration_adjustments --
--    explainable computed score, governed calibration, acknowledgement
--    (decision 1, 4; section 13, 21, 24).
-- ===========================================================================

create table app.performance_outcomes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  cycle_id uuid not null references app.performance_cycles (id),
  employee_id uuid not null references app.employees (master_record_id),
  manager_assessment_id uuid references app.performance_assessments (id),
  baseline_score numeric(6, 3),
  calibrated_score numeric(6, 3),
  final_score numeric(6, 3),
  score_breakdown jsonb not null default '[]'::jsonb,
  status text not null default 'draft',
  published_by text,
  published_at timestamptz,
  acknowledged_by text,
  acknowledged_at timestamptz,
  acknowledgement_agreement text,
  acknowledgement_comment text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint performance_outcomes_status_check check (status in ('draft', 'published', 'acknowledged', 'appealed', 'reopened', 'closed')),
  constraint performance_outcomes_agreement_check check (acknowledgement_agreement is null or acknowledgement_agreement in ('agree', 'disagree')),
  constraint performance_outcomes_score_range_check check (
    (baseline_score is null or (baseline_score >= 0 and baseline_score <= 100))
    and (calibrated_score is null or (calibrated_score >= 0 and calibrated_score <= 100))
    and (final_score is null or (final_score >= 0 and final_score <= 100))
  ),
  constraint performance_outcomes_unique unique (cycle_id, employee_id)
);

comment on table app.performance_outcomes is
  'HRT-283: final_score = coalesce(calibrated_score, baseline_score), always exact and reproducible from score_breakdown''s own per-goal weight*raw_score/100 sum (decision 1). Never automatically written by any code path that also touches app.employees.lifecycle_status, app.payroll_*, or a role/permission table -- business rule, section 24 (decision 8, grep-verified).';

create index performance_outcomes_tenant_cycle_idx on app.performance_outcomes (tenant_id, cycle_id);
create index performance_outcomes_employee_idx on app.performance_outcomes (tenant_id, employee_id);

create trigger performance_outcomes_touch before update on app.performance_outcomes
  for each row execute function app.touch_performance_row();

create table app.performance_calibration_adjustments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  outcome_id uuid not null references app.performance_outcomes (id),
  previous_score numeric(6, 3) not null,
  adjusted_score numeric(6, 3) not null,
  adjustment_reason text not null,
  calibrated_by text,
  calibrated_by_auth_user_id uuid,
  calibrated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint performance_calibration_adjustments_score_check check (adjusted_score >= 0 and adjusted_score <= 100),
  constraint performance_calibration_adjustments_reason_check check (length(trim(adjustment_reason)) > 0)
);

comment on table app.performance_calibration_adjustments is
  'HRT-283 (decision 4): append-only governed history -- every calibration adjustment is a NEW row, never an update to a prior one. Readable only by HRS:View personal data holders (HR), never by the outcome''s own employee or manager directly -- the RESULT (final_score) is visible to them via app.performance_outcomes, the deliberation is not (a disclosed, bounded privacy decision).';

create index performance_calibration_adjustments_outcome_idx on app.performance_calibration_adjustments (outcome_id, calibrated_at desc);

-- ===========================================================================
-- 8. app.performance_appeals -- appeal/reopen workflow (section 13, 22, 24).
-- ===========================================================================

create table app.performance_appeals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  cycle_id uuid not null references app.performance_cycles (id),
  employee_id uuid not null references app.employees (master_record_id),
  outcome_id uuid not null references app.performance_outcomes (id),
  appeal_reason text not null,
  status text not null default 'submitted',
  submitted_by text,
  submitted_at timestamptz not null default now(),
  decided_by text,
  decided_at timestamptz,
  decision_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint performance_appeals_status_check check (status in ('submitted', 'under_review', 'upheld', 'overturned', 'withdrawn')),
  constraint performance_appeals_reason_check check (length(trim(appeal_reason)) > 0)
);

comment on table app.performance_appeals is
  'HRT-283: only the outcome''s own employee may file an appeal (app.submit_performance_appeal); only HRS:Approve, never the appellant themself, may decide it (app.decide_performance_appeal, structural self-decision block). Overturn reopens the outcome (status=reopened) for a fresh calibration + re-publish; uphold returns it to published.';

create index performance_appeals_tenant_cycle_idx on app.performance_appeals (tenant_id, cycle_id);
create unique index performance_appeals_open_unique on app.performance_appeals (outcome_id) where status in ('submitted', 'under_review');

create trigger performance_appeals_touch before update on app.performance_appeals
  for each row execute function app.touch_performance_row();

-- ===========================================================================
-- 9. Authority and visibility helpers (decision 3, 5).
-- ===========================================================================

create function app.check_performance_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', p_action)).allowed;
$$;

comment on function app.check_performance_authority is
  'HRT-283: HRS:Edit gates authoring (KPI/template/cycle/goal draft actions); HRS:Approve gates publish/decide actions (template publish, cycle stage advance, outcome publish, appeal decide); HRS:Override gates calibration, cycle cancel, and reviewer reassignment; HRS:View personal data gates the one aggregate report and every non-self/non-manager/non-reviewer read. SECURITY DEFINER from the start (HRT-281/282''s own established lesson: a bare SECURITY INVOKER wrapper fails inside an RLS policy expression).';

create function app._is_direct_manager_of_employee(p_target_employee_id uuid, p_candidate_manager_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1 from app.employees e where e.master_record_id = p_target_employee_id and e.manager_employee_id = p_candidate_manager_employee_id
  );
$$;

comment on function app._is_direct_manager_of_employee is
  'HRT-283 (decision 3): the identical single-level direct-report predicate app.list_overtime_requests/app.list_leave_requests/app.list_attendance_sessions already established -- reused, never a recursive org-tree walk.';

create function app.can_view_hris_performance_row(p_tenant_id uuid, p_employee_id uuid, p_auth_user_id uuid default auth.uid())
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
  if (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'HRS', 'View personal data')).allowed then
    return true;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_auth_user_id);
  if v_self.master_record_id is null then
    return false;
  end if;
  if v_self.master_record_id = p_employee_id then
    return true;
  end if;
  if app._is_direct_manager_of_employee(p_employee_id, v_self.master_record_id) then
    return true;
  end if;
  return exists (
    select 1 from app.performance_reviewer_assignments ra
    where ra.tenant_id = p_tenant_id and ra.employee_id = p_employee_id and ra.assigned_to_employee_id = v_self.master_record_id and ra.status = 'active'
  );
end;
$$;

comment on function app.can_view_hris_performance_row is
  'HRT-283: self OR direct manager OR an assigned (active) manager/reviewer OR HRS:View personal data -- used for RLS on goal_assignments/goal_progress_entries. Never plain HRS:View, mirrors HRT-282 decision 5''s divergence.';

create function app.can_view_performance_assessment_row(
  p_tenant_id uuid, p_employee_id uuid, p_assessment_type text, p_assigned_to_employee_id uuid, p_status text, p_auth_user_id uuid default auth.uid()
)
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
  if (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'HRS', 'View personal data')).allowed then
    return true;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_auth_user_id);
  if v_self.master_record_id is null then
    return false;
  end if;
  -- The assessor always sees their own submission (draft or submitted).
  if v_self.master_record_id = p_assigned_to_employee_id then
    return true;
  end if;
  if p_assessment_type = 'self' then
    -- Self assessment: the employee sees their own; their direct manager
    -- sees it too (to inform their own assessment), regardless of stage.
    return v_self.master_record_id = p_employee_id or app._is_direct_manager_of_employee(p_employee_id, v_self.master_record_id);
  elsif p_assessment_type = 'manager' then
    -- Manager assessment: purpose- and stage-bound (section 16/26) -- the
    -- employee sees it ONLY once submitted, never mid-draft.
    return p_status = 'submitted' and v_self.master_record_id = p_employee_id;
  elsif p_assessment_type = 'reviewer' then
    -- Reviewer (360) input: visible to the employee''s own direct manager
    -- once submitted (informs their final assessment), never directly to
    -- the employee themself -- a disclosed, bounded confidentiality choice.
    return p_status = 'submitted' and app._is_direct_manager_of_employee(p_employee_id, v_self.master_record_id);
  end if;
  return false;
end;
$$;

comment on function app.can_view_performance_assessment_row is
  'HRT-283 (section 16/26 "purpose- and cycle-stage-bound"): the one assessment-type-aware visibility predicate, used for RLS on performance_assessments and (via a join to the parent) performance_assessment_kpi_scores.';

create function app.can_view_performance_outcome_row(p_tenant_id uuid, p_employee_id uuid, p_auth_user_id uuid default auth.uid())
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
  if (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'HRS', 'View personal data')).allowed then
    return true;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_auth_user_id);
  if v_self.master_record_id is null then
    return false;
  end if;
  return v_self.master_record_id = p_employee_id or app._is_direct_manager_of_employee(p_employee_id, v_self.master_record_id);
end;
$$;

comment on function app.can_view_performance_outcome_row is
  'HRT-283: self OR direct manager OR HRS:View personal data -- deliberately NOT extended to assigned reviewers (an outcome/final score is not 360-reviewer-visible in this design). Used for RLS on performance_outcomes, and (via joins) performance_calibration_adjustments (HR-only, no self/manager branch) and performance_appeals.';

create function app.compute_kpi_raw_score(p_scoring_method text, p_target_direction text, p_target_value numeric, p_actual_value numeric, p_manual_score numeric)
returns numeric
language plpgsql
immutable
as $$
declare
  v_score numeric;
begin
  if p_scoring_method = 'qualitative_scale' then
    if p_manual_score is null then
      raise exception 'manual_score_required: qualitative_scale KPIs require an assessor-entered score' using errcode = 'check_violation';
    end if;
    return round(p_manual_score, 3);
  elsif p_scoring_method = 'milestone_percent' then
    if p_actual_value is null then
      raise exception 'actual_value_required: milestone_percent KPIs require an actual (0-100) completion value' using errcode = 'check_violation';
    end if;
    return round(least(greatest(p_actual_value, 0), 100), 3);
  elsif p_scoring_method = 'target_ratio' then
    if p_actual_value is null or p_target_value is null or p_target_value = 0 then
      raise exception 'target_ratio_inputs_required: target_ratio KPIs require both a positive target_value and an actual_value' using errcode = 'check_violation';
    end if;
    if p_target_direction = 'higher_is_better' then
      v_score := (p_actual_value / p_target_value) * 100;
    elsif p_target_direction = 'lower_is_better' then
      v_score := (p_target_value / greatest(p_actual_value, 0.0001)) * 100;
    else
      raise exception 'invalid_target_direction: %', p_target_direction using errcode = 'check_violation';
    end if;
    return round(least(greatest(v_score, 0), 100), 3);
  else
    raise exception 'invalid_scoring_method: %', p_scoring_method using errcode = 'check_violation';
  end if;
end;
$$;

comment on function app.compute_kpi_raw_score is
  'HRT-283 (decision 1): the ONE deterministic scoring formula -- reproducible from visible permitted inputs (the goal''s own method/direction/target_value plus this assessment''s own actual_value or manual_score), the "explainable" requirement. Bounded to 3 fixed methods, no generic formula evaluator (mirrors HRT-282 decision 8''s identical, disclosed reasoning).';

-- ===========================================================================
-- 10. KPI library lifecycle (decision 1).
-- ===========================================================================

create function app.create_performance_kpi_definition(p_tenant_id uuid, p_code text, p_name text, p_description text, p_unit_of_measure text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_kpi_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_kpi app.performance_kpi_definitions;
begin
  if not app.check_performance_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_unit_of_measure not in ('percent', 'count', 'currency', 'ratio', 'qualitative') then
    raise exception 'invalid_unit_of_measure: %', p_unit_of_measure using errcode = 'check_violation';
  end if;

  select * into v_kpi from app.performance_kpi_definitions where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_kpi;
  end if;

  begin
    insert into app.performance_kpi_definitions (tenant_id, code, name, description, unit_of_measure, created_by)
    values (p_tenant_id, p_code, p_name, p_description, p_unit_of_measure, p_actor_label)
    returning * into v_kpi;
  exception
    when unique_violation then
      raise exception 'performance_kpi_definition_code_conflict: a KPI with code % was just created concurrently for tenant %', p_code, p_tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_performance_kpi_definition',
    'app.performance_kpi_definitions', v_kpi.id, 'success', null, null, jsonb_build_object('code', p_code)
  );

  return v_kpi;
end;
$$;

comment on function app.create_performance_kpi_definition is
  'HRT-283: idempotent on (tenant_id, code); a genuinely concurrent duplicate create raises a clean, classifiable performance_kpi_definition_code_conflict rather than a raw 23505 (taxonomy C-01/C-02, applied from the start).';

create function app.create_performance_kpi_definition_version(p_kpi_definition_id uuid, p_scoring_method text, p_target_direction text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_kpi_definition_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_kpi app.performance_kpi_definitions;
  v_next integer;
  v_version app.performance_kpi_definition_versions;
begin
  select * into v_kpi from app.performance_kpi_definitions where id = p_kpi_definition_id;
  if not found then
    raise exception 'performance_kpi_definition_not_found: %', p_kpi_definition_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Edit', v_kpi.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_kpi.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_scoring_method not in ('target_ratio', 'milestone_percent', 'qualitative_scale') then
    raise exception 'invalid_scoring_method: %', p_scoring_method using errcode = 'check_violation';
  end if;
  if p_scoring_method = 'target_ratio' and p_target_direction not in ('higher_is_better', 'lower_is_better') then
    raise exception 'invalid_target_direction: target_ratio requires higher_is_better or lower_is_better' using errcode = 'check_violation';
  end if;
  if p_scoring_method <> 'target_ratio' and p_target_direction is not null then
    raise exception 'target_direction_not_applicable: % does not use target_direction', p_scoring_method using errcode = 'check_violation';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next from app.performance_kpi_definition_versions where kpi_definition_id = p_kpi_definition_id;

  -- Exactly one active version per KPI (decision 1) -- archiving the prior
  -- active version here is idempotent under concurrency (setting status to
  -- 'archived' twice is harmless); the real race (two concurrent callers
  -- both computing the same v_next) is caught by the exception handler
  -- below, not by this UPDATE.
  update app.performance_kpi_definition_versions set status = 'archived' where kpi_definition_id = p_kpi_definition_id and status = 'active';

  begin
    insert into app.performance_kpi_definition_versions (kpi_definition_id, tenant_id, version_number, status, scoring_method, target_direction, created_by)
    values (p_kpi_definition_id, v_kpi.tenant_id, v_next, 'active', p_scoring_method, p_target_direction, p_actor_label)
    returning * into v_version;
  exception
    when unique_violation then
      raise exception 'performance_kpi_definition_version_conflict: a version was just created concurrently for KPI % -- retry to get the current next version number', p_kpi_definition_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_kpi.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_performance_kpi_definition_version',
    'app.performance_kpi_definition_versions', v_version.id, 'success', null, null, jsonb_build_object('kpi_definition_id', p_kpi_definition_id, 'version_number', v_next)
  );

  return v_version;
end;
$$;

create function app.archive_performance_kpi_definition_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_kpi_definition_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.performance_kpi_definition_versions;
begin
  select * into v_version from app.performance_kpi_definition_versions where id = p_version_id for update;
  if not found then
    raise exception 'performance_kpi_definition_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'active' then
    raise exception 'invalid_transition: version % is % not active', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  update app.performance_kpi_definition_versions set status = 'archived' where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: concurrent update detected for version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_performance_kpi_definition_version',
    'app.performance_kpi_definition_versions', v_version.id, 'success', null, null, jsonb_build_object('kpi_definition_id', v_version.kpi_definition_id)
  );

  return v_version;
end;
$$;

-- ===========================================================================
-- 11. Template lifecycle.
-- ===========================================================================

create function app.create_performance_template(p_tenant_id uuid, p_code text, p_name text, p_weight_total_required numeric, p_requires_reviewer_stage boolean, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_templates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_template app.performance_templates;
begin
  if not app.check_performance_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_template from app.performance_templates where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_template;
  end if;

  begin
    insert into app.performance_templates (tenant_id, code, name, weight_total_required, requires_reviewer_stage, created_by)
    values (p_tenant_id, p_code, p_name, coalesce(p_weight_total_required, 100.00), coalesce(p_requires_reviewer_stage, false), p_actor_label)
    returning * into v_template;
  exception
    when unique_violation then
      raise exception 'performance_template_code_conflict: a template with code % was just created concurrently for tenant %', p_code, p_tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_performance_template',
    'app.performance_templates', v_template.id, 'success', null, null, jsonb_build_object('code', p_code)
  );

  return v_template;
end;
$$;

create function app.add_performance_template_kpi_item(p_template_id uuid, p_kpi_definition_id uuid, p_default_weight numeric, p_is_required boolean, p_sort_order integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_template_kpi_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_template app.performance_templates;
  v_item app.performance_template_kpi_items;
begin
  select * into v_template from app.performance_templates where id = p_template_id for update;
  if not found then
    raise exception 'performance_template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Edit', v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_template.status <> 'draft' then
    raise exception 'template_not_draft: template % is % -- KPI items may only be added while draft', p_template_id, v_template.status
      using errcode = 'check_violation';
  end if;
  if p_default_weight is null or p_default_weight <= 0 or p_default_weight > 100 then
    raise exception 'invalid_weight: default_weight must be greater than 0 and at most 100' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.performance_kpi_definitions k where k.id = p_kpi_definition_id and k.tenant_id = v_template.tenant_id) then
    raise exception 'performance_kpi_definition_not_found: %', p_kpi_definition_id using errcode = 'no_data_found';
  end if;

  begin
    insert into app.performance_template_kpi_items (template_id, tenant_id, kpi_definition_id, default_weight, is_required, sort_order)
    values (p_template_id, v_template.tenant_id, p_kpi_definition_id, p_default_weight, coalesce(p_is_required, true), coalesce(p_sort_order, 0))
    returning * into v_item;
  exception
    when unique_violation then
      raise exception 'performance_template_kpi_item_conflict: KPI % is already on template %', p_kpi_definition_id, p_template_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_performance_template_kpi_item',
    'app.performance_template_kpi_items', v_item.id, 'success', null, null, jsonb_build_object('template_id', p_template_id, 'kpi_definition_id', p_kpi_definition_id)
  );

  return v_item;
end;
$$;

create function app.publish_performance_template(p_template_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_templates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_template app.performance_templates;
  v_weight_sum numeric;
  v_item_count integer;
begin
  select * into v_template from app.performance_templates where id = p_template_id for update;
  if not found then
    raise exception 'performance_template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Approve', v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_template.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_template.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_template.status <> 'draft' then
    raise exception 'invalid_transition: template % is % not draft', p_template_id, v_template.status using errcode = 'check_violation';
  end if;

  select count(*), coalesce(sum(default_weight), 0) into v_item_count, v_weight_sum from app.performance_template_kpi_items where template_id = p_template_id;
  if v_item_count = 0 then
    raise exception 'template_has_no_items: template % has no KPI items', p_template_id using errcode = 'check_violation';
  end if;
  if v_weight_sum <> v_template.weight_total_required then
    raise exception 'template_weights_incomplete: default weights sum to % but % is required', v_weight_sum, v_template.weight_total_required
      using errcode = 'check_violation';
  end if;

  update app.performance_templates set status = 'published' where id = p_template_id and record_version = p_expected_version
  returning * into v_template;
  if not found then
    raise exception 'stale_version: concurrent update detected for template %', p_template_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_performance_template',
    'app.performance_templates', v_template.id, 'success', null, null, jsonb_build_object('code', v_template.code)
  );

  return v_template;
end;
$$;

create function app.archive_performance_template(p_template_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_templates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_template app.performance_templates;
begin
  select * into v_template from app.performance_templates where id = p_template_id for update;
  if not found then
    raise exception 'performance_template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Edit', v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_template.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_template.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_template.status = 'archived' then
    raise exception 'invalid_transition: template % is already archived', p_template_id using errcode = 'check_violation';
  end if;

  update app.performance_templates set status = 'archived' where id = p_template_id and record_version = p_expected_version
  returning * into v_template;
  if not found then
    raise exception 'stale_version: concurrent update detected for template %', p_template_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_performance_template',
    'app.performance_templates', v_template.id, 'success', null, null, null
  );

  return v_template;
end;
$$;

-- ===========================================================================
-- 12. Cycle lifecycle (section 21).
-- ===========================================================================

create function app.create_performance_cycle(
  p_tenant_id uuid, p_template_id uuid, p_code text, p_name text, p_cycle_type text,
  p_period_start date, p_period_end date, p_goal_setting_due date, p_self_assessment_due date,
  p_manager_assessment_due date, p_calibration_due date, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.performance_cycles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_template app.performance_templates;
  v_cycle app.performance_cycles;
begin
  if not app.check_performance_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  select * into v_template from app.performance_templates where id = p_template_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'performance_template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;
  if v_template.status <> 'published' then
    raise exception 'template_not_published: template % is % not published', p_template_id, v_template.status using errcode = 'check_violation';
  end if;
  if p_period_end < p_period_start then
    raise exception 'invalid_period_range: period_end must not be before period_start' using errcode = 'check_violation';
  end if;

  select * into v_cycle from app.performance_cycles where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_cycle;
  end if;

  begin
    insert into app.performance_cycles (
      tenant_id, template_id, code, name, cycle_type, period_start, period_end,
      goal_setting_due, self_assessment_due, manager_assessment_due, calibration_due, weight_total_required, created_by
    ) values (
      p_tenant_id, p_template_id, p_code, p_name, coalesce(p_cycle_type, 'annual'), p_period_start, p_period_end,
      p_goal_setting_due, p_self_assessment_due, p_manager_assessment_due, p_calibration_due, v_template.weight_total_required, p_actor_label
    )
    returning * into v_cycle;
  exception
    when unique_violation then
      raise exception 'performance_cycle_code_conflict: a performance cycle with code % was just created concurrently for tenant %', p_code, p_tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_performance_cycle',
    'app.performance_cycles', v_cycle.id, 'success', null, null, jsonb_build_object('code', p_code)
  );

  return v_cycle;
end;
$$;

comment on function app.create_performance_cycle is
  'HRT-283: idempotent on (tenant_id, code); weight_total_required is copied from the (required-published) template at create time, never re-read live afterward.';

create function app.advance_performance_cycle_stage(p_cycle_id uuid, p_expected_version integer, p_target_status text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_cycles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cycle app.performance_cycles;
  v_legal boolean;
begin
  select * into v_cycle from app.performance_cycles where id = p_cycle_id for update;
  if not found then
    raise exception 'performance_cycle_not_found: %', p_cycle_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Approve', v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_cycle.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cycle.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_cycle.record_version
      using errcode = 'serialization_failure';
  end if;

  v_legal := case v_cycle.status
    when 'draft' then p_target_status = 'goal_setting_open'
    when 'goal_setting_open' then p_target_status = 'self_assessment_open'
    when 'self_assessment_open' then p_target_status = 'manager_assessment_open'
    when 'manager_assessment_open' then p_target_status = 'calibration'
    when 'calibration' then p_target_status = 'acknowledgement'
    when 'acknowledgement' then p_target_status = 'closed'
    else false
  end;
  if not v_legal then
    raise exception 'invalid_transition: cycle % cannot move from % to %', p_cycle_id, v_cycle.status, p_target_status using errcode = 'check_violation';
  end if;

  update app.performance_cycles set status = p_target_status where id = p_cycle_id and record_version = p_expected_version
  returning * into v_cycle;
  if not found then
    raise exception 'stale_version: concurrent update detected for cycle %', p_cycle_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'advance_performance_cycle_stage',
    'app.performance_cycles', v_cycle.id, 'success', null, null, jsonb_build_object('status', v_cycle.status)
  );

  return v_cycle;
end;
$$;

comment on function app.advance_performance_cycle_stage is
  'HRT-283: the single ordered state-machine advance covering draft->goal_setting_open->self_assessment_open->manager_assessment_open->calibration->acknowledgement->closed -- one step at a time, no skipping.';

create function app.cancel_performance_cycle(p_cycle_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_cycles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cycle app.performance_cycles;
begin
  select * into v_cycle from app.performance_cycles where id = p_cycle_id for update;
  if not found then
    raise exception 'performance_cycle_not_found: %', p_cycle_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Override', v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_cycle.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cycle.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_cycle.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_cycle.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cycle % is already %', p_cycle_id, v_cycle.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to cancel a performance cycle' using errcode = 'check_violation';
  end if;

  update app.performance_cycles set status = 'cancelled', cancel_reason = p_reason where id = p_cycle_id and record_version = p_expected_version
  returning * into v_cycle;
  if not found then
    raise exception 'stale_version: concurrent update detected for cycle %', p_cycle_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_performance_cycle',
    'app.performance_cycles', v_cycle.id, 'success', null, null, jsonb_build_object('status', v_cycle.status)
  );

  return v_cycle;
end;
$$;

-- ===========================================================================
-- 13. Enrollment helpers -- self assessment + manager assignment, both
--     resolved/created idempotently under real concurrency (decision 5;
--     taxonomy C-01/C-02 -- a real exception handler, never just a
--     pre-check).
-- ===========================================================================

create function app._ensure_performance_self_assessment(p_cycle_id uuid, p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant uuid;
begin
  select tenant_id into v_tenant from app.performance_cycles where id = p_cycle_id;
  begin
    insert into app.performance_assessments (tenant_id, cycle_id, employee_id, assessment_type, reviewer_assignment_id, assigned_to_employee_id)
    values (v_tenant, p_cycle_id, p_employee_id, 'self', null, p_employee_id);
  exception
    when unique_violation then
      -- A concurrent caller (another goal assignment for the same
      -- employee, or the reviewer-assignment path) already created this
      -- row -- benign.
      null;
  end;
end;
$$;

create function app._ensure_performance_manager_assignment(p_cycle_id uuid, p_employee_id uuid, p_actor_label text)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant uuid;
  v_manager_id uuid;
  v_assignment app.performance_reviewer_assignments;
begin
  select tenant_id into v_tenant from app.performance_cycles where id = p_cycle_id;
  select manager_employee_id into v_manager_id from app.employees where master_record_id = p_employee_id;
  if v_manager_id is null then
    -- No current manager to freeze -- disclosed limitation (build log):
    -- an employee with no manager gets no auto-created manager assignment;
    -- HR may still assign one explicitly via app.assign_performance_reviewer.
    return;
  end if;
  begin
    insert into app.performance_reviewer_assignments (tenant_id, cycle_id, employee_id, role, assigned_to_employee_id, assigned_by)
    values (v_tenant, p_cycle_id, p_employee_id, 'manager', v_manager_id, p_actor_label)
    returning * into v_assignment;
  exception
    when unique_violation then
      -- A concurrent caller already created this cycle's manager assignment.
      return;
  end;
  insert into app.performance_assessments (tenant_id, cycle_id, employee_id, assessment_type, reviewer_assignment_id, assigned_to_employee_id)
  values (v_tenant, p_cycle_id, p_employee_id, 'manager', v_assignment.id, v_manager_id);
end;
$$;

comment on function app._ensure_performance_manager_assignment is
  'HRT-283 (decision 5): resolves app.employees.manager_employee_id ONCE, at the moment it is first called (typically the employee''s first goal assignment) -- the frozen manager assignment for this cycle. Never re-resolved on a later call once an active assignment already exists.';

-- ===========================================================================
-- 14. Goal assignment (section 13, 20, 22 mid-cycle revision, 24 exact
--     weight).
-- ===========================================================================

create function app.assign_performance_goal(
  p_cycle_id uuid, p_employee_id uuid, p_kpi_definition_id uuid, p_weight numeric, p_target_value numeric, p_target_unit text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.performance_goal_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cycle app.performance_cycles;
  v_employee app.employees;
  v_self app.employees;
  v_version app.performance_kpi_definition_versions;
  v_existing app.performance_goal_assignments;
  v_self_assessment app.performance_assessments;
  v_goal app.performance_goal_assignments;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_cycle from app.performance_cycles where id = p_cycle_id for update;
  if not found then
    raise exception 'performance_cycle_not_found: %', p_cycle_id using errcode = 'no_data_found';
  end if;
  select * into v_employee from app.employees where master_record_id = p_employee_id and tenant_id = v_cycle.tenant_id;
  if not found or v_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'employee_not_active: % is not an active employee for tenant %', p_employee_id, v_cycle.tenant_id using errcode = 'no_data_found';
  end if;

  v_self := app.get_self_employee(v_cycle.tenant_id, p_actor_auth_user_id);
  if not (
    app.check_performance_authority('Edit', v_cycle.tenant_id, p_actor_auth_user_id)
    or (v_self.master_record_id is not null and v_self.master_record_id = v_employee.manager_employee_id)
  ) then
    raise exception 'insufficient_authority: identity % may not assign goals to employee %', p_actor_auth_user_id, p_employee_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cycle.status not in ('goal_setting_open', 'self_assessment_open') then
    raise exception 'invalid_cycle_stage: cycle % is % -- goal assignment is not open', p_cycle_id, v_cycle.status using errcode = 'check_violation';
  end if;
  if p_weight is null or p_weight <= 0 or p_weight > 100 then
    raise exception 'invalid_weight: weight must be greater than 0 and at most 100' using errcode = 'check_violation';
  end if;

  select * into v_version from app.performance_kpi_definition_versions
    where kpi_definition_id = p_kpi_definition_id and tenant_id = v_cycle.tenant_id and status = 'active'
    order by version_number desc limit 1;
  if not found then
    raise exception 'kpi_version_not_found: no active KPI definition version exists for KPI % in tenant %', p_kpi_definition_id, v_cycle.tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_version.scoring_method = 'target_ratio' and p_target_value is null then
    raise exception 'target_value_required: this KPI''s target_ratio scoring method requires a target value' using errcode = 'check_violation';
  end if;

  perform app._ensure_performance_self_assessment(p_cycle_id, p_employee_id);
  perform app._ensure_performance_manager_assignment(p_cycle_id, p_employee_id, p_actor_label);

  -- Lock guard (section 22 "mid-cycle goal revision" is legal only BEFORE
  -- the employee''s own self assessment is submitted -- once submitted,
  -- goals are frozen for scoring integrity).
  select * into v_self_assessment from app.performance_assessments where cycle_id = p_cycle_id and employee_id = p_employee_id and assessment_type = 'self';
  if v_self_assessment.status = 'submitted' then
    raise exception 'goals_locked: employee %''s self assessment for cycle % is already submitted -- goals are frozen', p_employee_id, p_cycle_id
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.performance_goal_assignments where cycle_id = p_cycle_id and employee_id = p_employee_id and kpi_definition_id = p_kpi_definition_id for update;
  if found then
    update app.performance_goal_assignments set
      kpi_version_id = v_version.id, weight = p_weight, target_value = p_target_value, target_unit = p_target_unit,
      status = 'active', na_reason = null
    where id = v_existing.id
    returning * into v_goal;
  else
    begin
      insert into app.performance_goal_assignments (tenant_id, cycle_id, employee_id, kpi_definition_id, kpi_version_id, weight, target_value, target_unit, assigned_by, created_by)
      values (v_cycle.tenant_id, p_cycle_id, p_employee_id, p_kpi_definition_id, v_version.id, p_weight, p_target_value, p_target_unit, p_actor_label, p_actor_label)
      returning * into v_goal;
    exception
      when unique_violation then
        raise exception 'goal_assignment_conflict: this KPI was just assigned concurrently for this employee and cycle -- retry to update it'
          using errcode = 'check_violation';
    end;
  end if;

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_performance_goal',
    'app.performance_goal_assignments', v_goal.id, 'success', null, null,
    jsonb_build_object('cycle_id', p_cycle_id, 'employee_id', p_employee_id, 'kpi_definition_id', p_kpi_definition_id)
  );

  return v_goal;
end;
$$;

comment on function app.assign_performance_goal is
  'HRT-283: an upsert on (cycle_id, employee_id, kpi_definition_id) -- HRS:Edit OR the employee''s own direct manager. Auto-ensures the self assessment and (if the employee has a current manager) the frozen manager assignment exist. weight/target_value/target_unit are NEVER put into the audit trail (only ids and status) -- taxonomy C-24.';

create function app.mark_performance_goal_not_applicable(p_goal_assignment_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_goal_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_goal app.performance_goal_assignments;
  v_employee app.employees;
  v_self app.employees;
  v_self_assessment app.performance_assessments;
begin
  select * into v_goal from app.performance_goal_assignments where id = p_goal_assignment_id for update;
  if not found then
    raise exception 'performance_goal_assignment_not_found: %', p_goal_assignment_id using errcode = 'no_data_found';
  end if;
  select * into v_employee from app.employees where master_record_id = v_goal.employee_id;
  v_self := app.get_self_employee(v_goal.tenant_id, p_actor_auth_user_id);
  if not (
    app.check_performance_authority('Edit', v_goal.tenant_id, p_actor_auth_user_id)
    or (v_self.master_record_id is not null and v_self.master_record_id = v_employee.manager_employee_id)
  ) then
    raise exception 'insufficient_authority: identity % may not mark this goal not applicable', p_actor_auth_user_id using errcode = 'insufficient_privilege';
  end if;
  if v_goal.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_goal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_goal.status <> 'active' then
    raise exception 'invalid_transition: goal % is % not active', p_goal_assignment_id, v_goal.status using errcode = 'check_violation';
  end if;
  select * into v_self_assessment from app.performance_assessments where cycle_id = v_goal.cycle_id and employee_id = v_goal.employee_id and assessment_type = 'self';
  if v_self_assessment.status = 'submitted' then
    raise exception 'goals_locked: employee %''s self assessment for cycle % is already submitted -- goals are frozen', v_goal.employee_id, v_goal.cycle_id
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to mark a goal not applicable' using errcode = 'check_violation';
  end if;

  update app.performance_goal_assignments set status = 'not_applicable', na_reason = p_reason
  where id = p_goal_assignment_id and record_version = p_expected_version
  returning * into v_goal;
  if not found then
    raise exception 'stale_version: concurrent update detected for goal %', p_goal_assignment_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_goal.tenant_id, p_actor_auth_user_id, p_actor_label, 'mark_performance_goal_not_applicable',
    'app.performance_goal_assignments', v_goal.id, 'success', null, null, jsonb_build_object('cycle_id', v_goal.cycle_id, 'employee_id', v_goal.employee_id)
  );
  return v_goal;
end;
$$;

create function app.record_performance_goal_progress(p_goal_assignment_id uuid, p_actual_value numeric, p_note text, p_evidence_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_goal_progress_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_goal app.performance_goal_assignments;
  v_employee app.employees;
  v_self app.employees;
  v_file app.files;
  v_entry app.performance_goal_progress_entries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_goal from app.performance_goal_assignments where id = p_goal_assignment_id;
  if not found then
    raise exception 'performance_goal_assignment_not_found: %', p_goal_assignment_id using errcode = 'no_data_found';
  end if;
  select * into v_employee from app.employees where master_record_id = v_goal.employee_id;
  v_self := app.get_self_employee(v_goal.tenant_id, p_actor_auth_user_id);
  if not (
    (v_self.master_record_id is not null and v_self.master_record_id = v_goal.employee_id)
    or (v_self.master_record_id is not null and v_self.master_record_id = v_employee.manager_employee_id)
    or app.check_performance_authority('Edit', v_goal.tenant_id, p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % may not record progress on this goal', p_actor_auth_user_id using errcode = 'insufficient_privilege';
  end if;
  if v_goal.status <> 'active' then
    raise exception 'invalid_transition: goal % is % not active', p_goal_assignment_id, v_goal.status using errcode = 'check_violation';
  end if;
  if p_evidence_file_id is not null then
    -- Taxonomy C-10: re-validate tenant/scope/scan status at THIS accepting
    -- RPC, never trust the caller''s own upload-time classification.
    select * into v_file from app.files where id = p_evidence_file_id and tenant_id = v_goal.tenant_id;
    if not found then
      raise exception 'evidence_file_not_found: % is not a known file for tenant %', p_evidence_file_id, v_goal.tenant_id using errcode = 'no_data_found';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'evidence_file_not_clean: % has not passed malware scanning', p_evidence_file_id using errcode = 'check_violation';
    end if;
  end if;

  insert into app.performance_goal_progress_entries (tenant_id, goal_assignment_id, employee_id, actual_value, note, evidence_file_id, recorded_by_auth_user_id, recorded_by)
  values (v_goal.tenant_id, p_goal_assignment_id, v_goal.employee_id, p_actual_value, p_note, p_evidence_file_id, p_actor_auth_user_id, p_actor_label)
  returning * into v_entry;

  perform app.capture_audit_event(
    v_goal.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_performance_goal_progress',
    'app.performance_goal_progress_entries', v_entry.id, 'success', null, null, jsonb_build_object('goal_assignment_id', p_goal_assignment_id)
  );
  return v_entry;
end;
$$;

-- ===========================================================================
-- 15. Reviewer (manager + 360) assignment and explicit, audited reassignment
--     (decision 5, mandatory reading item).
-- ===========================================================================

create function app.assign_performance_reviewer(p_cycle_id uuid, p_employee_id uuid, p_role text, p_assigned_to_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_reviewer_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cycle app.performance_cycles;
  v_target app.employees;
  v_assessor app.employees;
  v_assignment app.performance_reviewer_assignments;
begin
  select * into v_cycle from app.performance_cycles where id = p_cycle_id;
  if not found then
    raise exception 'performance_cycle_not_found: %', p_cycle_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Edit', v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_cycle.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_role not in ('manager', 'reviewer') then
    raise exception 'invalid_role: % must be manager or reviewer', p_role using errcode = 'check_violation';
  end if;
  if p_assigned_to_employee_id = p_employee_id then
    raise exception 'invalid_assignee: an employee may not be assigned as their own %', p_role using errcode = 'check_violation';
  end if;
  select * into v_target from app.employees where master_record_id = p_employee_id and tenant_id = v_cycle.tenant_id;
  if not found or v_target.lifecycle_status in ('terminated', 'archived') then
    raise exception 'employee_not_active: % is not an active employee for tenant %', p_employee_id, v_cycle.tenant_id using errcode = 'no_data_found';
  end if;
  select * into v_assessor from app.employees where master_record_id = p_assigned_to_employee_id and tenant_id = v_cycle.tenant_id;
  if not found or v_assessor.lifecycle_status in ('terminated', 'archived') then
    raise exception 'employee_not_active: % is not an active employee for tenant %', p_assigned_to_employee_id, v_cycle.tenant_id using errcode = 'no_data_found';
  end if;

  if p_role = 'manager' and exists (
    select 1 from app.performance_reviewer_assignments where cycle_id = p_cycle_id and employee_id = p_employee_id and role = 'manager' and status = 'active'
  ) then
    raise exception 'manager_assignment_exists: employee % already has an active manager assignment for cycle % -- use app.reassign_performance_reviewer_assignment', p_employee_id, p_cycle_id
      using errcode = 'check_violation';
  end if;

  perform app._ensure_performance_self_assessment(p_cycle_id, p_employee_id);

  begin
    insert into app.performance_reviewer_assignments (tenant_id, cycle_id, employee_id, role, assigned_to_employee_id, assigned_by)
    values (v_cycle.tenant_id, p_cycle_id, p_employee_id, p_role, p_assigned_to_employee_id, p_actor_label)
    returning * into v_assignment;
  exception
    when unique_violation then
      raise exception 'reviewer_assignment_conflict: this assignment already exists or was just created concurrently' using errcode = 'check_violation';
  end;

  insert into app.performance_assessments (tenant_id, cycle_id, employee_id, assessment_type, reviewer_assignment_id, assigned_to_employee_id)
  values (v_cycle.tenant_id, p_cycle_id, p_employee_id, p_role, v_assignment.id, p_assigned_to_employee_id);

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_performance_reviewer',
    'app.performance_reviewer_assignments', v_assignment.id, 'success', null, null,
    jsonb_build_object('cycle_id', p_cycle_id, 'employee_id', p_employee_id, 'role', p_role)
  );
  return v_assignment;
end;
$$;

create function app.reassign_performance_reviewer_assignment(p_assignment_id uuid, p_new_assigned_to_employee_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_reviewer_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_old app.performance_reviewer_assignments;
  v_new app.performance_reviewer_assignments;
  v_new_employee app.employees;
begin
  select * into v_old from app.performance_reviewer_assignments where id = p_assignment_id for update;
  if not found then
    raise exception 'performance_reviewer_assignment_not_found: %', p_assignment_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Override', v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_old.status <> 'active' then
    raise exception 'invalid_transition: assignment % is already %', p_assignment_id, v_old.status using errcode = 'check_violation';
  end if;
  if p_new_assigned_to_employee_id = v_old.employee_id then
    raise exception 'invalid_assignee: an employee may not be assigned as their own %', v_old.role using errcode = 'check_violation';
  end if;
  select * into v_new_employee from app.employees where master_record_id = p_new_assigned_to_employee_id and tenant_id = v_old.tenant_id;
  if not found or v_new_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'employee_not_active: % is not an active employee for tenant %', p_new_assigned_to_employee_id, v_old.tenant_id using errcode = 'no_data_found';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to reassign a reviewer assignment' using errcode = 'check_violation';
  end if;

  update app.performance_reviewer_assignments set status = 'reassigned', reassign_reason = p_reason where id = p_assignment_id;

  begin
    insert into app.performance_reviewer_assignments (tenant_id, cycle_id, employee_id, role, assigned_to_employee_id, reassigned_from_assignment_id, assigned_by)
    values (v_old.tenant_id, v_old.cycle_id, v_old.employee_id, v_old.role, p_new_assigned_to_employee_id, v_old.id, p_actor_label)
    returning * into v_new;
  exception
    when unique_violation then
      raise exception 'reviewer_assignment_conflict: this reassignment target already holds an active assignment of this role for this employee'
        using errcode = 'check_violation';
  end;

  -- The whole point of this RPC (decision 5): the OLD assignment, and any
  -- already-submitted assessment tied to it, is NEVER mutated or deleted --
  -- it stays exactly as it was, permanently attributed to the prior
  -- assessor. A brand-new not_started assessment is created for the new
  -- assignee; if the old assessment was still draft/not_started, it is
  -- simply superseded (orphaned under the now-reassigned assignment),
  -- never silently carried over as if the new assessor had written it.
  insert into app.performance_assessments (tenant_id, cycle_id, employee_id, assessment_type, reviewer_assignment_id, assigned_to_employee_id)
  values (v_old.tenant_id, v_old.cycle_id, v_old.employee_id, v_old.role, v_new.id, p_new_assigned_to_employee_id);

  perform app.capture_audit_event(
    v_old.tenant_id, p_actor_auth_user_id, p_actor_label, 'reassign_performance_reviewer_assignment',
    'app.performance_reviewer_assignments', v_new.id, 'success', null, null,
    jsonb_build_object('cycle_id', v_old.cycle_id, 'employee_id', v_old.employee_id, 'old_assignment_id', p_assignment_id, 'role', v_old.role)
  );
  return v_new;
end;
$$;

comment on function app.reassign_performance_reviewer_assignment is
  'HRT-283 (decision 5, mandatory reading item -- "manager reassignment does NOT silently transfer already-submitted reviews; reassignment is explicit and audited"): HRS:Override, mandatory reason. Live-tested: a submitted manager assessment under the OLD assignment remains byte-for-byte unchanged and readable under its own original assignment after a reassignment.';

-- ===========================================================================
-- 16. Assessment scoring and submission (decision 1, 2; section 13, 21).
-- ===========================================================================

create function app.upsert_performance_assessment_kpi_score(
  p_assessment_id uuid, p_goal_assignment_id uuid, p_actual_value numeric, p_manual_score numeric,
  p_score_rationale text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.performance_assessment_kpi_scores
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_assessment app.performance_assessments;
  v_goal app.performance_goal_assignments;
  v_version app.performance_kpi_definition_versions;
  v_self app.employees;
  v_raw_score numeric;
  v_row app.performance_assessment_kpi_scores;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_assessment from app.performance_assessments where id = p_assessment_id for update;
  if not found then
    raise exception 'performance_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;
  if v_assessment.status = 'submitted' then
    raise exception 'invalid_transition: assessment % is already submitted -- scores are locked', p_assessment_id using errcode = 'check_violation';
  end if;

  v_self := app.get_self_employee(v_assessment.tenant_id, p_actor_auth_user_id);
  if not (
    (v_self.master_record_id is not null and v_self.master_record_id = v_assessment.assigned_to_employee_id)
    or app.check_performance_authority('Override', v_assessment.tenant_id, p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % may not record scores on assessment %', p_actor_auth_user_id, p_assessment_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_goal from app.performance_goal_assignments where id = p_goal_assignment_id and tenant_id = v_assessment.tenant_id and employee_id = v_assessment.employee_id;
  if not found then
    raise exception 'performance_goal_assignment_not_found: %', p_goal_assignment_id using errcode = 'no_data_found';
  end if;
  if v_goal.status <> 'active' then
    raise exception 'goal_not_scoreable: goal % is % not active', p_goal_assignment_id, v_goal.status using errcode = 'check_violation';
  end if;
  if p_score_rationale is null or length(trim(p_score_rationale)) = 0 then
    raise exception 'rationale_required: a score rationale is required' using errcode = 'check_violation';
  end if;

  select * into v_version from app.performance_kpi_definition_versions where id = v_goal.kpi_version_id;
  v_raw_score := app.compute_kpi_raw_score(v_version.scoring_method, v_version.target_direction, v_goal.target_value, p_actual_value, p_manual_score);

  insert into app.performance_assessment_kpi_scores (tenant_id, assessment_id, goal_assignment_id, actual_value, manual_score, raw_score, score_rationale, scored_by)
  values (v_assessment.tenant_id, p_assessment_id, p_goal_assignment_id, p_actual_value, p_manual_score, v_raw_score, p_score_rationale, p_actor_label)
  on conflict (assessment_id, goal_assignment_id) do update set
    actual_value = excluded.actual_value, manual_score = excluded.manual_score, raw_score = excluded.raw_score,
    score_rationale = excluded.score_rationale, scored_by = excluded.scored_by
  returning * into v_row;

  if v_assessment.status = 'not_started' then
    update app.performance_assessments set status = 'draft' where id = p_assessment_id;
  end if;

  -- Taxonomy C-24: raw_score/actual_value/manual_score/score_rationale are
  -- exactly the "rating"/free-text shape this must never carry unmasked --
  -- after_value here names only ids, never a value.
  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'upsert_performance_assessment_kpi_score',
    'app.performance_assessment_kpi_scores', v_row.id, 'success', null, null, jsonb_build_object('assessment_id', p_assessment_id, 'goal_assignment_id', p_goal_assignment_id)
  );

  return v_row;
end;
$$;

create function app._assert_performance_assessment_scores_complete(p_cycle_id uuid, p_employee_id uuid, p_assessment_id uuid, p_weight_total_required numeric)
returns void
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_weight_sum numeric;
  v_missing integer;
begin
  select coalesce(sum(weight), 0) into v_weight_sum from app.performance_goal_assignments where cycle_id = p_cycle_id and employee_id = p_employee_id and status = 'active';
  if v_weight_sum <> p_weight_total_required then
    raise exception 'goal_weights_incomplete: active goal weights sum to % but % is required', v_weight_sum, p_weight_total_required using errcode = 'check_violation';
  end if;
  select count(*) into v_missing from app.performance_goal_assignments g
    where g.cycle_id = p_cycle_id and g.employee_id = p_employee_id and g.status = 'active'
      and not exists (select 1 from app.performance_assessment_kpi_scores s where s.assessment_id = p_assessment_id and s.goal_assignment_id = g.id);
  if v_missing > 0 then
    raise exception 'goal_scores_incomplete: % active goal(s) have not been scored yet', v_missing using errcode = 'check_violation';
  end if;
end;
$$;

comment on function app._assert_performance_assessment_scores_complete is
  'HRT-283 (business rule/validation rule, section 24/25 "exact weight total"): shared by every submit_performance_*_assessment function -- one authoritative implementation, never duplicated per stage.';

create function app.submit_performance_self_assessment(p_cycle_id uuid, p_expected_version integer, p_overall_comment text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cycle app.performance_cycles;
  v_self app.employees;
  v_assessment app.performance_assessments;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_cycle from app.performance_cycles where id = p_cycle_id;
  if not found then
    raise exception 'performance_cycle_not_found: %', p_cycle_id using errcode = 'no_data_found';
  end if;
  v_self := app.get_self_employee(v_cycle.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    raise exception 'employee_not_found: no employee record linked to this identity' using errcode = 'no_data_found';
  end if;

  select * into v_assessment from app.performance_assessments where cycle_id = p_cycle_id and employee_id = v_self.master_record_id and assessment_type = 'self' for update;
  if not found then
    raise exception 'performance_assessment_not_found: no self assessment exists yet for this cycle -- goals must be assigned first' using errcode = 'no_data_found';
  end if;
  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_assessment.status = 'submitted' then
    raise exception 'invalid_transition: self assessment already submitted' using errcode = 'check_violation';
  end if;
  if v_cycle.status not in ('goal_setting_open', 'self_assessment_open') then
    raise exception 'invalid_cycle_stage: cycle % is % -- self assessment is not open', p_cycle_id, v_cycle.status using errcode = 'check_violation';
  end if;

  perform app._assert_performance_assessment_scores_complete(p_cycle_id, v_self.master_record_id, v_assessment.id, v_cycle.weight_total_required);

  update app.performance_assessments set status = 'submitted', overall_comment = p_overall_comment, submitted_by = p_actor_label, submitted_at = now()
  where id = v_assessment.id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: concurrent update detected for assessment %', v_assessment.id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_performance_self_assessment',
    'app.performance_assessments', v_assessment.id, 'success', null, null, jsonb_build_object('cycle_id', p_cycle_id)
  );

  return v_assessment;
end;
$$;

create function app.submit_performance_manager_assessment(p_assessment_id uuid, p_expected_version integer, p_overall_comment text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_assessment app.performance_assessments;
  v_cycle app.performance_cycles;
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_assessment from app.performance_assessments where id = p_assessment_id for update;
  if not found then
    raise exception 'performance_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;
  if v_assessment.assessment_type <> 'manager' then
    raise exception 'not_a_manager_assessment: % is a % assessment', p_assessment_id, v_assessment.assessment_type using errcode = 'check_violation';
  end if;
  select * into v_cycle from app.performance_cycles where id = v_assessment.cycle_id;
  v_self := app.get_self_employee(v_assessment.tenant_id, p_actor_auth_user_id);
  if not (
    (v_self.master_record_id is not null and v_self.master_record_id = v_assessment.assigned_to_employee_id)
    or app.check_performance_authority('Override', v_assessment.tenant_id, p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % may not submit this manager assessment', p_actor_auth_user_id using errcode = 'insufficient_privilege';
  end if;
  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_assessment.status = 'submitted' then
    raise exception 'invalid_transition: manager assessment already submitted' using errcode = 'check_violation';
  end if;
  if v_cycle.status <> 'manager_assessment_open' then
    raise exception 'invalid_cycle_stage: cycle % is % -- manager assessment is not open', v_cycle.id, v_cycle.status using errcode = 'check_violation';
  end if;

  perform app._assert_performance_assessment_scores_complete(v_assessment.cycle_id, v_assessment.employee_id, p_assessment_id, v_cycle.weight_total_required);

  update app.performance_assessments set status = 'submitted', overall_comment = p_overall_comment, submitted_by = p_actor_label, submitted_at = now()
  where id = p_assessment_id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: concurrent update detected for assessment %', p_assessment_id using errcode = 'serialization_failure';
  end if;

  perform app._compute_performance_outcome_baseline(v_assessment);

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_performance_manager_assessment',
    'app.performance_assessments', v_assessment.id, 'success', null, null,
    jsonb_build_object('cycle_id', v_assessment.cycle_id, 'employee_id', v_assessment.employee_id)
  );

  return v_assessment;
end;
$$;

create function app.submit_performance_reviewer_assessment(p_assessment_id uuid, p_expected_version integer, p_overall_comment text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_assessment app.performance_assessments;
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_assessment from app.performance_assessments where id = p_assessment_id for update;
  if not found then
    raise exception 'performance_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;
  if v_assessment.assessment_type <> 'reviewer' then
    raise exception 'not_a_reviewer_assessment: % is a % assessment', p_assessment_id, v_assessment.assessment_type using errcode = 'check_violation';
  end if;
  v_self := app.get_self_employee(v_assessment.tenant_id, p_actor_auth_user_id);
  if not (
    (v_self.master_record_id is not null and v_self.master_record_id = v_assessment.assigned_to_employee_id)
    or app.check_performance_authority('Override', v_assessment.tenant_id, p_actor_auth_user_id)
  ) then
    raise exception 'insufficient_authority: identity % may not submit this reviewer assessment', p_actor_auth_user_id using errcode = 'insufficient_privilege';
  end if;
  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_assessment.status = 'submitted' then
    raise exception 'invalid_transition: reviewer assessment already submitted' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.performance_assessment_kpi_scores s where s.assessment_id = p_assessment_id) then
    raise exception 'goal_scores_incomplete: no goals have been scored yet' using errcode = 'check_violation';
  end if;

  update app.performance_assessments set status = 'submitted', overall_comment = p_overall_comment, submitted_by = p_actor_label, submitted_at = now()
  where id = p_assessment_id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: concurrent update detected for assessment %', p_assessment_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_performance_reviewer_assessment',
    'app.performance_assessments', v_assessment.id, 'success', null, null,
    jsonb_build_object('cycle_id', v_assessment.cycle_id, 'employee_id', v_assessment.employee_id)
  );

  return v_assessment;
end;
$$;

comment on function app.submit_performance_reviewer_assessment is
  'HRT-283 (decision 2): reviewer (360) input is captured and visible (per app.can_view_performance_assessment_row''s own reviewer branch) but does NOT itself feed app._compute_performance_outcome_baseline -- only a submitted MANAGER assessment does. Disclosed, not an oversight.';

-- ===========================================================================
-- 17. Explainable score computation, calibration, publish, acknowledgement
--     (decision 1, 4).
-- ===========================================================================

create function app._compute_performance_outcome_baseline(p_assessment app.performance_assessments)
returns app.performance_outcomes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_breakdown jsonb;
  v_baseline numeric;
  v_outcome app.performance_outcomes;
  v_existing app.performance_outcomes;
begin
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'goalAssignmentId', g.id, 'kpiDefinitionId', g.kpi_definition_id, 'weight', g.weight,
      'rawScore', s.raw_score, 'weightedContribution', round(g.weight * s.raw_score / 100.0, 3)
    ) order by g.id), '[]'::jsonb),
    coalesce(sum(round(g.weight * s.raw_score / 100.0, 3)), 0)
  into v_breakdown, v_baseline
  from app.performance_goal_assignments g
  join app.performance_assessment_kpi_scores s on s.goal_assignment_id = g.id and s.assessment_id = p_assessment.id
  where g.cycle_id = p_assessment.cycle_id and g.employee_id = p_assessment.employee_id and g.status = 'active';

  select * into v_existing from app.performance_outcomes where cycle_id = p_assessment.cycle_id and employee_id = p_assessment.employee_id for update;
  if found then
    if v_existing.status not in ('draft', 'reopened') then
      -- A published/acknowledged/appealed/closed outcome is never silently
      -- overwritten by a later manager-assessment resubmission -- that
      -- flow does not exist here; only an appeal->overturn reopens it.
      raise exception 'outcome_not_writable: outcome for employee % in cycle % is % -- recomputation requires an appeal/reopen first', p_assessment.employee_id, p_assessment.cycle_id, v_existing.status
        using errcode = 'check_violation';
    end if;
    update app.performance_outcomes set
      manager_assessment_id = p_assessment.id, baseline_score = round(v_baseline, 3), score_breakdown = v_breakdown,
      final_score = coalesce(v_existing.calibrated_score, round(v_baseline, 3))
    where id = v_existing.id
    returning * into v_outcome;
  else
    insert into app.performance_outcomes (tenant_id, cycle_id, employee_id, manager_assessment_id, baseline_score, final_score, score_breakdown)
    values (p_assessment.tenant_id, p_assessment.cycle_id, p_assessment.employee_id, p_assessment.id, round(v_baseline, 3), round(v_baseline, 3), v_breakdown)
    returning * into v_outcome;
  end if;
  return v_outcome;
end;
$$;

comment on function app._compute_performance_outcome_baseline is
  'HRT-283 (decision 1, 2): the ONE weighted-sum formula, called only from app.submit_performance_manager_assessment. score_breakdown is an explicit jsonb_build_object allowlist (goalAssignmentId/kpiDefinitionId/weight/rawScore/weightedContribution) -- NEVER to_jsonb(whole_row) (taxonomy C-07). Internal only, service_role granted.';

create function app.calibrate_performance_outcome_score(p_outcome_id uuid, p_expected_version integer, p_adjusted_score numeric, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_outcomes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_outcome app.performance_outcomes;
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_outcome from app.performance_outcomes where id = p_outcome_id for update;
  if not found then
    raise exception 'performance_outcome_not_found: %', p_outcome_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Override', v_outcome.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_outcome.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  -- Structural self-calibration block (decision 4) -- an actor may never
  -- calibrate their own outcome, even while separately holding HRS:Override.
  v_self := app.get_self_employee(v_outcome.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_outcome.employee_id then
    raise exception 'self_calibration_not_permitted: an actor may not calibrate their own outcome' using errcode = 'insufficient_privilege';
  end if;
  if v_outcome.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_outcome.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_outcome.status not in ('draft', 'published', 'reopened') then
    raise exception 'invalid_transition: outcome % is % -- calibration is not permitted in this status', p_outcome_id, v_outcome.status using errcode = 'check_violation';
  end if;
  if p_adjusted_score is null or p_adjusted_score < 0 or p_adjusted_score > 100 then
    raise exception 'invalid_adjusted_score: adjusted score must be between 0 and 100' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to calibrate an outcome score' using errcode = 'check_violation';
  end if;

  insert into app.performance_calibration_adjustments (tenant_id, outcome_id, previous_score, adjusted_score, adjustment_reason, calibrated_by, calibrated_by_auth_user_id)
  values (v_outcome.tenant_id, p_outcome_id, coalesce(v_outcome.calibrated_score, v_outcome.baseline_score), round(p_adjusted_score, 3), p_reason, p_actor_label, p_actor_auth_user_id);

  update app.performance_outcomes set calibrated_score = round(p_adjusted_score, 3), final_score = round(p_adjusted_score, 3)
  where id = p_outcome_id and record_version = p_expected_version
  returning * into v_outcome;
  if not found then
    raise exception 'stale_version: concurrent update detected for outcome %', p_outcome_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_outcome.tenant_id, p_actor_auth_user_id, p_actor_label, 'calibrate_performance_outcome_score',
    'app.performance_outcomes', v_outcome.id, 'success', null, null, jsonb_build_object('outcome_id', p_outcome_id)
  );

  return v_outcome;
end;
$$;

create function app.publish_performance_outcome(p_outcome_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_outcomes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_outcome app.performance_outcomes;
begin
  select * into v_outcome from app.performance_outcomes where id = p_outcome_id for update;
  if not found then
    raise exception 'performance_outcome_not_found: %', p_outcome_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Approve', v_outcome.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_outcome.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_outcome.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_outcome.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_outcome.status not in ('draft', 'reopened') then
    raise exception 'invalid_transition: outcome % is % -- only draft/reopened outcomes may be published', p_outcome_id, v_outcome.status using errcode = 'check_violation';
  end if;
  if v_outcome.manager_assessment_id is null then
    raise exception 'manager_assessment_missing: outcome % has no submitted manager assessment yet', p_outcome_id using errcode = 'check_violation';
  end if;

  update app.performance_outcomes set status = 'published', published_by = p_actor_label, published_at = now()
  where id = p_outcome_id and record_version = p_expected_version
  returning * into v_outcome;
  if not found then
    raise exception 'stale_version: concurrent update detected for outcome %', p_outcome_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_outcome.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_performance_outcome',
    'app.performance_outcomes', v_outcome.id, 'success', null, null, jsonb_build_object('cycle_id', v_outcome.cycle_id)
  );
  return v_outcome;
end;
$$;

create function app.acknowledge_performance_outcome(p_outcome_id uuid, p_expected_version integer, p_agreement text, p_comment text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_outcomes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_outcome app.performance_outcomes;
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_outcome from app.performance_outcomes where id = p_outcome_id for update;
  if not found then
    raise exception 'performance_outcome_not_found: %', p_outcome_id using errcode = 'no_data_found';
  end if;
  v_self := app.get_self_employee(v_outcome.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null or v_self.master_record_id <> v_outcome.employee_id then
    raise exception 'insufficient_authority: only the outcome''s own employee may acknowledge it' using errcode = 'insufficient_privilege';
  end if;
  if v_outcome.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_outcome.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_outcome.status <> 'published' then
    raise exception 'invalid_transition: outcome % is % -- only a published outcome may be acknowledged', p_outcome_id, v_outcome.status using errcode = 'check_violation';
  end if;
  if p_agreement not in ('agree', 'disagree') then
    raise exception 'invalid_agreement: % must be agree or disagree', p_agreement using errcode = 'check_violation';
  end if;

  update app.performance_outcomes set status = 'acknowledged', acknowledged_by = p_actor_label, acknowledged_at = now(),
    acknowledgement_agreement = p_agreement, acknowledgement_comment = p_comment
  where id = p_outcome_id and record_version = p_expected_version
  returning * into v_outcome;
  if not found then
    raise exception 'stale_version: concurrent update detected for outcome %', p_outcome_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_outcome.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_performance_outcome',
    'app.performance_outcomes', v_outcome.id, 'success', null, null, jsonb_build_object('agreement', p_agreement)
  );
  return v_outcome;
end;
$$;

-- ===========================================================================
-- 18. Appeal/reopen workflow (section 13, 22, 24).
-- ===========================================================================

create function app.submit_performance_appeal(p_outcome_id uuid, p_appeal_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_appeals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_outcome app.performance_outcomes;
  v_self app.employees;
  v_appeal app.performance_appeals;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  -- Locking the outcome row FIRST serializes any concurrent appeal
  -- submission against the SAME outcome (taxonomy C-01/C-04): a second,
  -- genuinely concurrent caller blocks on this SAME row lock until the
  -- first commits (status -> 'appealed'), then re-reads that status and is
  -- rejected by the status check below -- an explicit "already open" EXISTS
  -- pre-check would be dead code given this status invariant (submitting
  -- an appeal always flips status away from published/acknowledged, so no
  -- sequential OR concurrent second call can ever reach it with status
  -- still published/acknowledged AND an open appeal already present) --
  -- live-verified, not merely reasoned about, during this checkpoint's own
  -- adversarial testing. The partial unique index on (outcome_id) where
  -- status in ('submitted','under_review') remains as pure structural
  -- defense in depth, never expected to fire.
  select * into v_outcome from app.performance_outcomes where id = p_outcome_id for update;
  if not found then
    raise exception 'performance_outcome_not_found: %', p_outcome_id using errcode = 'no_data_found';
  end if;
  v_self := app.get_self_employee(v_outcome.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null or v_self.master_record_id <> v_outcome.employee_id then
    raise exception 'insufficient_authority: only the outcome''s own employee may appeal it' using errcode = 'insufficient_privilege';
  end if;
  if v_outcome.status not in ('published', 'acknowledged') then
    raise exception 'invalid_transition: outcome % is % -- an appeal may only be filed against a published or acknowledged outcome', p_outcome_id, v_outcome.status
      using errcode = 'check_violation';
  end if;
  if p_appeal_reason is null or length(trim(p_appeal_reason)) = 0 then
    raise exception 'reason_required: an appeal reason is required' using errcode = 'check_violation';
  end if;

  insert into app.performance_appeals (tenant_id, cycle_id, employee_id, outcome_id, appeal_reason, submitted_by)
  values (v_outcome.tenant_id, v_outcome.cycle_id, v_outcome.employee_id, p_outcome_id, p_appeal_reason, p_actor_label)
  returning * into v_appeal;

  update app.performance_outcomes set status = 'appealed' where id = p_outcome_id;

  perform app.capture_audit_event(
    v_outcome.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_performance_appeal',
    'app.performance_appeals', v_appeal.id, 'success', null, null, jsonb_build_object('outcome_id', p_outcome_id)
  );
  return v_appeal;
end;
$$;

create function app.decide_performance_appeal(p_appeal_id uuid, p_expected_version integer, p_decision text, p_decision_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.performance_appeals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_appeal app.performance_appeals;
  v_outcome app.performance_outcomes;
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_appeal from app.performance_appeals where id = p_appeal_id for update;
  if not found then
    raise exception 'performance_appeal_not_found: %', p_appeal_id using errcode = 'no_data_found';
  end if;
  if not app.check_performance_authority('Approve', v_appeal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_appeal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  -- Structural self-decision block: the appellant may never decide their
  -- own appeal, even while separately holding HRS:Approve.
  v_self := app.get_self_employee(v_appeal.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_appeal.employee_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own appeal' using errcode = 'insufficient_privilege';
  end if;
  if v_appeal.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_appeal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_appeal.status not in ('submitted', 'under_review') then
    raise exception 'invalid_transition: appeal % is % not open', p_appeal_id, v_appeal.status using errcode = 'check_violation';
  end if;
  if p_decision not in ('uphold', 'overturn') then
    raise exception 'invalid_decision: % must be uphold or overturn', p_decision using errcode = 'check_violation';
  end if;
  if p_decision_reason is null or length(trim(p_decision_reason)) = 0 then
    raise exception 'reason_required: a decision reason is required' using errcode = 'check_violation';
  end if;

  update app.performance_appeals set status = case p_decision when 'uphold' then 'upheld' else 'overturned' end,
    decided_by = p_actor_label, decided_at = now(), decision_reason = p_decision_reason
  where id = p_appeal_id and record_version = p_expected_version
  returning * into v_appeal;
  if not found then
    raise exception 'stale_version: concurrent update detected for appeal %', p_appeal_id using errcode = 'serialization_failure';
  end if;

  -- Lock order note (taxonomy C-21): this function locks performance_appeals
  -- THEN performance_outcomes. app.submit_performance_appeal only ever locks
  -- performance_outcomes (no appeal row exists yet to lock at creation
  -- time), so no sibling function locks these same two tables in the
  -- reverse order -- no deadlock risk between the two.
  select * into v_outcome from app.performance_outcomes where id = v_appeal.outcome_id for update;
  update app.performance_outcomes set status = case when p_decision = 'overturn' then 'reopened' else 'published' end
  where id = v_outcome.id;

  perform app.capture_audit_event(
    v_appeal.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_performance_appeal',
    'app.performance_appeals', v_appeal.id, 'success', null, null, jsonb_build_object('outcome_id', v_appeal.outcome_id, 'decision', p_decision)
  );
  return v_appeal;
end;
$$;

-- ===========================================================================
-- 19. Privacy-safe aggregate reporting -- genuine k-anonymity floor
--     (decision 6).
-- ===========================================================================

create function app.report_performance_cycle_score_distribution(p_tenant_id uuid, p_cycle_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns table (department_org_unit_id uuid, department_name text, employee_count integer, avg_final_score numeric, suppressed boolean)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  c_k_floor constant integer := 5;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_performance_authority('View personal data', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:View personal data for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'report_performance_cycle_score_distribution',
    'app.performance_cycles', p_cycle_id, 'success', null, null, jsonb_build_object('cycle_id', p_cycle_id)
  );

  return query
  with per_dept as (
    select e.department_org_unit_id as dept_id, ou.name as dept_name, count(*)::integer as cnt, avg(o.final_score) as avg_score
    from app.performance_outcomes o
    join app.employees e on e.master_record_id = o.employee_id
    left join app.org_units ou on ou.id = e.department_org_unit_id
    where o.tenant_id = p_tenant_id and o.cycle_id = p_cycle_id and o.status in ('published', 'acknowledged', 'closed')
    group by e.department_org_unit_id, ou.name
  )
  select pd.dept_id, pd.dept_name, pd.cnt,
    case when pd.cnt >= c_k_floor then round(pd.avg_score, 2) else null end,
    pd.cnt < c_k_floor
  from per_dept pd
  order by pd.dept_name nulls last;
end;
$$;

comment on function app.report_performance_cycle_score_distribution is
  'HRT-283 (decision 6, section 16 "aggregate reports resist small-cohort re-identification"): a genuine k-anonymity-style floor (k=5, fixed) enforced INSIDE this SECURITY DEFINER function -- avg_final_score is nulled and suppressed=true for any department with fewer than 5 employees with a published/acknowledged/closed outcome in this cycle. Not merely a UI hint: no caller, including a genuine HRS:View personal data holder, can retrieve a small cohort''s average through this RPC.';

-- ===========================================================================
-- 20. Read RPCs -- library/template/cycle (tenant-member reads).
-- ===========================================================================

create function app.list_performance_kpi_definitions(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, code text, name text, description text, unit_of_measure text)
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
  select k.id, k.code, k.name, k.description, k.unit_of_measure
  from app.performance_kpi_definitions k
  where k.tenant_id = p_tenant_id
  order by k.code;
end;
$$;

create function app.list_performance_kpi_definition_versions(p_kpi_definition_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, version_number integer, status text, scoring_method text, target_direction text, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select k.tenant_id into v_tenant from app.performance_kpi_definitions k where k.id = p_kpi_definition_id;
  if v_tenant is null or not app.has_active_tenant_membership(v_tenant, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select v.id, v.version_number, v.status, v.scoring_method, v.target_direction, v.record_version
  from app.performance_kpi_definition_versions v
  where v.kpi_definition_id = p_kpi_definition_id
  order by v.version_number desc;
end;
$$;

create function app.list_performance_templates(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, code text, name text, status text, weight_total_required numeric, requires_reviewer_stage boolean, record_version integer)
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
  select t.id, t.code, t.name, t.status, t.weight_total_required, t.requires_reviewer_stage, t.record_version
  from app.performance_templates t
  where t.tenant_id = p_tenant_id
  order by t.code;
end;
$$;

create function app.list_performance_template_kpi_items(p_template_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, kpi_definition_id uuid, kpi_code text, kpi_name text, default_weight numeric, is_required boolean, sort_order integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select t.tenant_id into v_tenant from app.performance_templates t where t.id = p_template_id;
  if v_tenant is null or not app.has_active_tenant_membership(v_tenant, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select i.id, i.kpi_definition_id, k.code, k.name, i.default_weight, i.is_required, i.sort_order
  from app.performance_template_kpi_items i
  join app.performance_kpi_definitions k on k.id = i.kpi_definition_id
  where i.template_id = p_template_id
  order by i.sort_order, k.code;
end;
$$;

create function app.list_performance_cycles(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text)
returns table (id uuid, template_id uuid, code text, name text, cycle_type text, period_start date, period_end date, status text, weight_total_required numeric, record_version integer)
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
  select c.id, c.template_id, c.code, c.name, c.cycle_type, c.period_start, c.period_end, c.status, c.weight_total_required, c.record_version
  from app.performance_cycles c
  where c.tenant_id = p_tenant_id and (p_status is null or c.status = p_status)
  order by c.period_start desc;
end;
$$;

create function app.get_performance_cycle(p_cycle_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, tenant_id uuid, template_id uuid, code text, name text, cycle_type text, period_start date, period_end date, status text, weight_total_required numeric, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.performance_cycles;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_row from app.performance_cycles where id = p_cycle_id;
  if v_row.id is null or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query select v_row.id, v_row.tenant_id, v_row.template_id, v_row.code, v_row.name, v_row.cycle_type, v_row.period_start, v_row.period_end, v_row.status, v_row.weight_total_required, v_row.record_version;
end;
$$;

-- ===========================================================================
-- 21. Read RPCs -- goal assignment / progress (scoped: self / direct
--     manager / assigned reviewer / HRS:View personal data, decision 3).
-- ===========================================================================

create function app.list_performance_goal_assignments(p_tenant_id uuid, p_cycle_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid default null)
returns table (
  id uuid, employee_id uuid, employee_number text, employee_full_name text, kpi_definition_id uuid, kpi_code text, kpi_name text,
  kpi_version_id uuid, weight numeric, target_value numeric, target_unit text, status text, na_reason text, record_version integer
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
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View personal data')).allowed;

  if p_employee_id is not null then
    if not app.can_view_hris_performance_row(p_tenant_id, p_employee_id, p_actor_auth_user_id) then
      return;
    end if;
  elsif not v_has_view and v_self.master_record_id is null then
    return;
  end if;

  return query
  select g.id, g.employee_id, m.code, e.full_name, g.kpi_definition_id, k.code, k.name, g.kpi_version_id, g.weight, g.target_value, g.target_unit, g.status, g.na_reason, g.record_version
  from app.performance_goal_assignments g
  join app.employees e on e.master_record_id = g.employee_id
  join app.master_records m on m.id = e.master_record_id
  join app.performance_kpi_definitions k on k.id = g.kpi_definition_id
  where g.tenant_id = p_tenant_id and g.cycle_id = p_cycle_id
    and (
      (p_employee_id is not null and g.employee_id = p_employee_id)
      or (p_employee_id is null and v_has_view)
      or (p_employee_id is null and not v_has_view and (
        g.employee_id = v_self.master_record_id
        or e.manager_employee_id = v_self.master_record_id
        or exists (
          select 1 from app.performance_reviewer_assignments ra
          where ra.cycle_id = p_cycle_id and ra.employee_id = g.employee_id and ra.assigned_to_employee_id = v_self.master_record_id and ra.status = 'active'
        )
      ))
    )
  order by k.code;
end;
$$;

create function app.list_my_performance_goal_assignments(p_tenant_id uuid, p_actor_auth_user_id uuid, p_cycle_id uuid default null)
returns table (
  id uuid, cycle_id uuid, kpi_definition_id uuid, kpi_code text, kpi_name text, kpi_version_id uuid,
  weight numeric, target_value numeric, target_unit text, status text, na_reason text, record_version integer
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
  select g.id, g.cycle_id, g.kpi_definition_id, k.code, k.name, g.kpi_version_id, g.weight, g.target_value, g.target_unit, g.status, g.na_reason, g.record_version
  from app.performance_goal_assignments g
  join app.performance_kpi_definitions k on k.id = g.kpi_definition_id
  where g.tenant_id = p_tenant_id and g.employee_id = v_self.master_record_id and (p_cycle_id is null or g.cycle_id = p_cycle_id)
  order by k.code;
end;
$$;

create function app.list_performance_goal_progress_entries(p_goal_assignment_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, actual_value numeric, note text, evidence_file_id uuid, recorded_by text, recorded_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_goal app.performance_goal_assignments;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_goal from app.performance_goal_assignments where id = p_goal_assignment_id;
  if v_goal.id is null or not app.can_view_hris_performance_row(v_goal.tenant_id, v_goal.employee_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select p.id, p.actual_value, p.note, p.evidence_file_id, p.recorded_by, p.recorded_at
  from app.performance_goal_progress_entries p
  where p.goal_assignment_id = p_goal_assignment_id
  order by p.recorded_at desc;
end;
$$;

-- ===========================================================================
-- 22. Read RPCs -- reviewer assignment, assessment, scores (decision 5,
--     section 16/26 stage-bound visibility).
-- ===========================================================================

create function app.list_performance_reviewer_assignments(p_tenant_id uuid, p_cycle_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid default null)
returns table (
  id uuid, employee_id uuid, employee_full_name text, role text, assigned_to_employee_id uuid, assigned_to_full_name text, status text, record_version integer
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
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View personal data')).allowed;

  return query
  select ra.id, ra.employee_id, e.full_name, ra.role, ra.assigned_to_employee_id, a.full_name, ra.status, ra.record_version
  from app.performance_reviewer_assignments ra
  join app.employees e on e.master_record_id = ra.employee_id
  join app.employees a on a.master_record_id = ra.assigned_to_employee_id
  where ra.tenant_id = p_tenant_id and ra.cycle_id = p_cycle_id
    and (p_employee_id is null or ra.employee_id = p_employee_id)
    and (
      v_has_view
      or (v_self.master_record_id is not null and (ra.employee_id = v_self.master_record_id or ra.assigned_to_employee_id = v_self.master_record_id))
    )
  order by ra.role, e.full_name;
end;
$$;

create function app.list_performance_assessments(p_tenant_id uuid, p_cycle_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid default null, p_assessment_type text default null)
returns table (
  id uuid, employee_id uuid, employee_full_name text, assessment_type text, assigned_to_employee_id uuid, assigned_to_full_name text,
  status text, overall_comment text, submitted_at timestamptz, record_version integer
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

  return query
  select a.id, a.employee_id, e.full_name, a.assessment_type, a.assigned_to_employee_id, r.full_name,
    a.status, a.overall_comment, a.submitted_at, a.record_version
  from app.performance_assessments a
  join app.employees e on e.master_record_id = a.employee_id
  join app.employees r on r.master_record_id = a.assigned_to_employee_id
  where a.tenant_id = p_tenant_id and a.cycle_id = p_cycle_id
    and (p_employee_id is null or a.employee_id = p_employee_id)
    and (p_assessment_type is null or a.assessment_type = p_assessment_type)
    and app.can_view_performance_assessment_row(p_tenant_id, a.employee_id, a.assessment_type, a.assigned_to_employee_id, a.status, p_actor_auth_user_id)
  order by a.assessment_type, e.full_name;
end;
$$;

create function app.list_my_performance_assessments(p_tenant_id uuid, p_actor_auth_user_id uuid, p_assessment_type text default null)
returns table (
  id uuid, cycle_id uuid, cycle_code text, employee_id uuid, employee_full_name text, assessment_type text,
  status text, overall_comment text, submitted_at timestamptz, record_version integer
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
  select a.id, a.cycle_id, c.code, a.employee_id, e.full_name, a.assessment_type, a.status, a.overall_comment, a.submitted_at, a.record_version
  from app.performance_assessments a
  join app.performance_cycles c on c.id = a.cycle_id
  join app.employees e on e.master_record_id = a.employee_id
  where a.tenant_id = p_tenant_id and a.assigned_to_employee_id = v_self.master_record_id
    and (p_assessment_type is null or a.assessment_type = p_assessment_type)
  order by c.period_start desc, a.assessment_type;
end;
$$;

comment on function app.list_my_performance_assessments is
  'HRT-283: assigned_to_employee_id = self covers ALL THREE assessment types uniformly -- self (assigned_to = own employee_id), manager, and reviewer. Serves both the self-service page (assessment_type=self) and the team-review page (assessment_type in manager,reviewer).';

create function app.list_performance_assessment_kpi_scores(p_assessment_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, goal_assignment_id uuid, kpi_code text, kpi_name text, actual_value numeric, manual_score numeric, raw_score numeric, score_rationale text, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_assessment app.performance_assessments;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_assessment from app.performance_assessments where id = p_assessment_id;
  if v_assessment.id is null then
    return;
  end if;
  if not app.can_view_performance_assessment_row(v_assessment.tenant_id, v_assessment.employee_id, v_assessment.assessment_type, v_assessment.assigned_to_employee_id, v_assessment.status, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select s.id, s.goal_assignment_id, k.code, k.name, s.actual_value, s.manual_score, s.raw_score, s.score_rationale, s.record_version
  from app.performance_assessment_kpi_scores s
  join app.performance_goal_assignments g on g.id = s.goal_assignment_id
  join app.performance_kpi_definitions k on k.id = g.kpi_definition_id
  where s.assessment_id = p_assessment_id
  order by k.code;
end;
$$;

-- ===========================================================================
-- 23. Read RPCs -- outcome, calibration history, appeal (decision 4).
-- ===========================================================================

create function app.list_performance_outcomes(p_tenant_id uuid, p_cycle_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid default null)
returns table (
  id uuid, employee_id uuid, employee_full_name text, baseline_score numeric, calibrated_score numeric, final_score numeric,
  status text, published_at timestamptz, acknowledgement_agreement text, record_version integer
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
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View personal data')).allowed;

  return query
  select o.id, o.employee_id, e.full_name, o.baseline_score, o.calibrated_score, o.final_score, o.status, o.published_at, o.acknowledgement_agreement, o.record_version
  from app.performance_outcomes o
  join app.employees e on e.master_record_id = o.employee_id
  where o.tenant_id = p_tenant_id and o.cycle_id = p_cycle_id
    and (p_employee_id is null or o.employee_id = p_employee_id)
    and (
      v_has_view
      or (v_self.master_record_id is not null and (o.employee_id = v_self.master_record_id or e.manager_employee_id = v_self.master_record_id))
    )
  order by e.full_name;
end;
$$;

create function app.list_my_performance_outcomes(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, cycle_id uuid, cycle_code text, baseline_score numeric, calibrated_score numeric, final_score numeric, score_breakdown jsonb,
  status text, published_at timestamptz, acknowledgement_agreement text, acknowledgement_comment text, record_version integer
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
  select o.id, o.cycle_id, c.code, o.baseline_score, o.calibrated_score, o.final_score, o.score_breakdown, o.status, o.published_at, o.acknowledgement_agreement, o.acknowledgement_comment, o.record_version
  from app.performance_outcomes o
  join app.performance_cycles c on c.id = o.cycle_id
  where o.tenant_id = p_tenant_id and o.employee_id = v_self.master_record_id and o.status in ('published', 'acknowledged', 'appealed', 'reopened', 'closed')
  order by c.period_start desc;
end;
$$;

create function app.get_performance_outcome(p_outcome_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, cycle_id uuid, employee_id uuid, baseline_score numeric, calibrated_score numeric, final_score numeric,
  score_breakdown jsonb, status text, published_at timestamptz, acknowledgement_agreement text, acknowledgement_comment text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.performance_outcomes;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_row from app.performance_outcomes where id = p_outcome_id;
  if v_row.id is null or not app.can_view_performance_outcome_row(v_row.tenant_id, v_row.employee_id, p_actor_auth_user_id) then
    return;
  end if;
  return query select v_row.id, v_row.tenant_id, v_row.cycle_id, v_row.employee_id, v_row.baseline_score, v_row.calibrated_score, v_row.final_score,
    v_row.score_breakdown, v_row.status, v_row.published_at, v_row.acknowledgement_agreement, v_row.acknowledgement_comment, v_row.record_version;
end;
$$;

create function app.list_performance_calibration_adjustments(p_outcome_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, previous_score numeric, adjusted_score numeric, adjustment_reason text, calibrated_by text, calibrated_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_outcome app.performance_outcomes;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_outcome from app.performance_outcomes where id = p_outcome_id;
  if v_outcome.id is null then
    return;
  end if;
  -- HR-only (decision 4) -- never self/manager, even though they may see
  -- the outcome's own final_score via app.can_view_performance_outcome_row.
  if not app.check_performance_authority('View personal data', v_outcome.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select a.id, a.previous_score, a.adjusted_score, a.adjustment_reason, a.calibrated_by, a.calibrated_at
  from app.performance_calibration_adjustments a
  where a.outcome_id = p_outcome_id
  order by a.calibrated_at desc;
end;
$$;

create function app.list_performance_appeals(p_tenant_id uuid, p_cycle_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid default null)
returns table (id uuid, employee_id uuid, employee_full_name text, outcome_id uuid, appeal_reason text, status text, decision_reason text, record_version integer)
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
  v_has_view := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View personal data')).allowed;

  return query
  select ap.id, ap.employee_id, e.full_name, ap.outcome_id, ap.appeal_reason, ap.status, ap.decision_reason, ap.record_version
  from app.performance_appeals ap
  join app.employees e on e.master_record_id = ap.employee_id
  where ap.tenant_id = p_tenant_id and ap.cycle_id = p_cycle_id
    and (p_employee_id is null or ap.employee_id = p_employee_id)
    and (v_has_view or (v_self.master_record_id is not null and ap.employee_id = v_self.master_record_id))
  order by ap.submitted_at desc;
end;
$$;

create function app.list_my_performance_appeals(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, cycle_id uuid, outcome_id uuid, appeal_reason text, status text, decision_reason text, record_version integer)
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
  select ap.id, ap.cycle_id, ap.outcome_id, ap.appeal_reason, ap.status, ap.decision_reason, ap.record_version
  from app.performance_appeals ap
  where ap.tenant_id = p_tenant_id and ap.employee_id = v_self.master_record_id
  order by ap.submitted_at desc;
end;
$$;

-- ===========================================================================
-- 24. Row Level Security.
-- ===========================================================================

alter table app.performance_kpi_definitions enable row level security;
alter table app.performance_kpi_definition_versions enable row level security;
alter table app.performance_templates enable row level security;
alter table app.performance_template_kpi_items enable row level security;
alter table app.performance_cycles enable row level security;
alter table app.performance_goal_assignments enable row level security;
alter table app.performance_goal_progress_entries enable row level security;
alter table app.performance_reviewer_assignments enable row level security;
alter table app.performance_assessments enable row level security;
alter table app.performance_assessment_kpi_scores enable row level security;
alter table app.performance_outcomes enable row level security;
alter table app.performance_calibration_adjustments enable row level security;
alter table app.performance_appeals enable row level security;

-- Library/template/cycle: broadly tenant-member-readable metadata (mirrors
-- HRT-275's own app.positions/app.position_grades precedent -- no
-- individual sensitive data lives on these tables), hardened default-deny
-- form against a customer_user-layer principal (ISS-2026-010 lineage).
create policy performance_kpi_definitions_select_scoped on app.performance_kpi_definitions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy performance_kpi_definition_versions_select_scoped on app.performance_kpi_definition_versions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy performance_templates_select_scoped on app.performance_templates
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy performance_template_kpi_items_select_scoped on app.performance_template_kpi_items
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy performance_cycles_select_scoped on app.performance_cycles
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- Person-scoped: self / direct manager / assigned reviewer / HRS:View
-- performance (decision 3, 5) -- never plain HRS:View.
create policy performance_goal_assignments_select_scoped on app.performance_goal_assignments
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_performance_row(tenant_id, employee_id, (select auth.uid())));

create policy performance_goal_progress_entries_select_scoped on app.performance_goal_progress_entries
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_performance_row(tenant_id, employee_id, (select auth.uid())));

create policy performance_reviewer_assignments_select_scoped on app.performance_reviewer_assignments
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (app.evaluate_permission((select auth.uid()), tenant_id, 'HRS', 'View personal data')).allowed
    or (app.get_self_employee(tenant_id, (select auth.uid()))).master_record_id = employee_id
    or (app.get_self_employee(tenant_id, (select auth.uid()))).master_record_id = assigned_to_employee_id
  );

-- Assessment-type-aware, purpose- and stage-bound (decision 4, section
-- 16/26) -- the one policy that cannot reuse a flat self-or-manager
-- predicate.
create policy performance_assessments_select_scoped on app.performance_assessments
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_performance_assessment_row(tenant_id, employee_id, assessment_type, assigned_to_employee_id, status, (select auth.uid())));

create policy performance_assessment_kpi_scores_select_scoped on app.performance_assessment_kpi_scores
  for select to authenticated
  using (
    app.is_supreme_admin()
    or exists (
      select 1 from app.performance_assessments a
      where a.id = assessment_id
        and app.can_view_performance_assessment_row(a.tenant_id, a.employee_id, a.assessment_type, a.assigned_to_employee_id, a.status, (select auth.uid()))
    )
  );

-- Outcome / calibration / appeal: self / direct manager / HRS:View
-- performance (decision 4) -- calibration history additionally excludes
-- self/manager (HR-only, never exposed via RLS to the outcome's own
-- employee or their manager, even though the outcome ITSELF is).
create policy performance_outcomes_select_scoped on app.performance_outcomes
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_performance_outcome_row(tenant_id, employee_id, (select auth.uid())));

create policy performance_calibration_adjustments_select_scoped on app.performance_calibration_adjustments
  for select to authenticated
  using (app.is_supreme_admin() or (app.evaluate_permission((select auth.uid()), tenant_id, 'HRS', 'View personal data')).allowed);

create policy performance_appeals_select_scoped on app.performance_appeals
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_performance_outcome_row(tenant_id, employee_id, (select auth.uid())));

-- ===========================================================================
-- 25. Grants. Per ERR-2026-004 / the standing convention established at
--     PLT-118 (20260717095000): explicit REVOKE before any role-specific
--     GRANT below, defense-in-depth belt-and-suspenders alongside the
--     schema-wide `alter default privileges` set up in that migration.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.performance_kpi_definitions to authenticated, service_role;
grant select on app.performance_kpi_definition_versions to authenticated, service_role;
grant select on app.performance_templates to authenticated, service_role;
grant select on app.performance_template_kpi_items to authenticated, service_role;
grant select on app.performance_cycles to authenticated, service_role;
grant select on app.performance_goal_assignments to authenticated, service_role;
grant select on app.performance_goal_progress_entries to authenticated, service_role;
grant select on app.performance_reviewer_assignments to authenticated, service_role;
grant select on app.performance_assessments to authenticated, service_role;
grant select on app.performance_assessment_kpi_scores to authenticated, service_role;
grant select on app.performance_outcomes to authenticated, service_role;
grant select on app.performance_calibration_adjustments to authenticated, service_role;
grant select on app.performance_appeals to authenticated, service_role;

grant insert, update, delete on app.performance_kpi_definitions to service_role;
grant insert, update, delete on app.performance_kpi_definition_versions to service_role;
grant insert, update, delete on app.performance_templates to service_role;
grant insert, update, delete on app.performance_template_kpi_items to service_role;
grant insert, update, delete on app.performance_cycles to service_role;
grant insert, update, delete on app.performance_goal_assignments to service_role;
grant insert, update, delete on app.performance_goal_progress_entries to service_role;
grant insert, update, delete on app.performance_reviewer_assignments to service_role;
grant insert, update, delete on app.performance_assessments to service_role;
grant insert, update, delete on app.performance_assessment_kpi_scores to service_role;
grant insert, update, delete on app.performance_outcomes to service_role;
grant insert, update, delete on app.performance_calibration_adjustments to service_role;
grant insert, update, delete on app.performance_appeals to service_role;

grant execute on function app.touch_performance_row() to service_role;
grant execute on function app.check_performance_authority(text, uuid, uuid) to authenticated, service_role;
grant execute on function app._is_direct_manager_of_employee(uuid, uuid) to service_role;
grant execute on function app.can_view_hris_performance_row(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.can_view_performance_assessment_row(uuid, uuid, text, uuid, text, uuid) to authenticated, service_role;
grant execute on function app.can_view_performance_outcome_row(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.compute_kpi_raw_score(text, text, numeric, numeric, numeric) to service_role;

grant execute on function app.create_performance_kpi_definition(uuid, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_performance_kpi_definition_version(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.archive_performance_kpi_definition_version(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.list_performance_kpi_definitions(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_performance_kpi_definition_versions(uuid, uuid) to authenticated, service_role;

grant execute on function app.create_performance_template(uuid, text, text, numeric, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.add_performance_template_kpi_item(uuid, uuid, numeric, boolean, integer, uuid, text) to authenticated, service_role;
grant execute on function app.publish_performance_template(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.archive_performance_template(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.list_performance_templates(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_performance_template_kpi_items(uuid, uuid) to authenticated, service_role;

grant execute on function app.create_performance_cycle(uuid, uuid, text, text, text, date, date, date, date, date, date, uuid, text) to authenticated, service_role;
grant execute on function app.advance_performance_cycle_stage(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_performance_cycle(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_performance_cycles(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_performance_cycle(uuid, uuid) to authenticated, service_role;

grant execute on function app._ensure_performance_self_assessment(uuid, uuid) to service_role;
grant execute on function app._ensure_performance_manager_assignment(uuid, uuid, text) to service_role;
grant execute on function app.assign_performance_goal(uuid, uuid, uuid, numeric, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.mark_performance_goal_not_applicable(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_performance_goal_progress(uuid, numeric, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.list_performance_goal_assignments(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_my_performance_goal_assignments(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_performance_goal_progress_entries(uuid, uuid) to authenticated, service_role;

grant execute on function app.assign_performance_reviewer(uuid, uuid, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.reassign_performance_reviewer_assignment(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_performance_reviewer_assignments(uuid, uuid, uuid, uuid) to authenticated, service_role;

grant execute on function app.upsert_performance_assessment_kpi_score(uuid, uuid, numeric, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app._assert_performance_assessment_scores_complete(uuid, uuid, uuid, numeric) to service_role;
grant execute on function app.submit_performance_self_assessment(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_performance_manager_assessment(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_performance_reviewer_assessment(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_performance_assessments(uuid, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.list_my_performance_assessments(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.list_performance_assessment_kpi_scores(uuid, uuid) to authenticated, service_role;

grant execute on function app._compute_performance_outcome_baseline(app.performance_assessments) to service_role;
grant execute on function app.calibrate_performance_outcome_score(uuid, integer, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.publish_performance_outcome(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.acknowledge_performance_outcome(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_performance_outcomes(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_my_performance_outcomes(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_performance_outcome(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_performance_calibration_adjustments(uuid, uuid) to authenticated, service_role;

grant execute on function app.submit_performance_appeal(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_performance_appeal(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_performance_appeals(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_my_performance_appeals(uuid, uuid) to authenticated, service_role;

grant execute on function app.report_performance_cycle_score_distribution(uuid, uuid, uuid, text) to authenticated, service_role;

