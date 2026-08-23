-- HRIS capability HRT-284 (Prompt 284, CG-S12-HRT-012) -- Training and
-- Talent. Twelfth Phase 7 capability, built directly on HRT-274 (Employee
-- Master), HRT-275 (Organization and Position Linkage), HRT-283 (KPI and
-- Performance, whose app.performance_outcomes this checkpoint links a
-- development plan to), and PLT-128 (private/scanned file evidence),
-- PLT-131/132 (durable job framework) -- reused, never reinvented. Second
-- of a 3-prompt batch (283, 284, 285); Tier C review runs once, combined,
-- after all three are built (BUILD_EXECUTION_PROTOCOL.md section 3.4).
--
-- ===========================================================================
-- DECISION 0 -- no new permission row. Every write below gates on one of
-- the already-seeded HRS actions (Edit/Approve/Override/View personal
-- data) -- `app.permissions.action` is a fixed, repository-wide CHECK
-- constraint no capability alters (HRT-274/283's own confirmed-live
-- precedent).
-- ===========================================================================
--
-- ===========================================================================
-- DECISION 1 -- competency/skill is a single status-lifecycle catalogue
-- row (draft/published/archived), NOT a two-tier parent+version model.
-- ===========================================================================
--
-- Unlike a KPI definition (HRT-283) or a payroll component (HRT-282), a
-- competency here carries no scored/weighted/formula-bearing configuration
-- that a later edit could retroactively change underneath an already-
-- assigned record -- it is a reference taxonomy tag a course links to
-- (app.training_course_competencies). Course CURRICULUM content is what
-- genuinely needs frozen, exact versioning (an enrollment/certificate must
-- retain the applied version), so the two-tier model is spent there
-- instead (decision 2). A disclosed, bounded design choice, not an
-- oversight -- section 24's "competency... semantics are versioned" is
-- satisfied by app.training_courses/_course_versions, the concrete
-- carrier of assessment/certificate/prerequisite semantics a competency by
-- itself never varies.
--
-- ===========================================================================
-- DECISION 2 -- course/course-version is a two-tier versioned catalogue,
-- mirrors app.performance_kpi_definitions/_kpi_definition_versions
-- (HRT-283) and app.payroll_components/_component_versions (HRT-282)
-- exactly: exactly one PUBLISHED version per course at a time.
-- ===========================================================================
--
-- Every app.training_sessions row freezes the specific course_version_id
-- it was scheduled against; every app.training_enrollments row freezes the
-- same at enroll time. Archiving/superseding a version later never
-- disturbs an already-scheduled session or an already-completed
-- enrollment's own applied rules (passing_score, certificate_validity_
-- months) -- "active records retain applied versions" (section 24),
-- applied identically to how HRT-283 froze kpi_version_id on a goal
-- assignment.
--
-- ===========================================================================
-- DECISION 3 -- enrollment capacity, waitlist, and prerequisite
-- enforcement all happen INSIDE the enrollment RPC under a session-row
-- lock (taxonomy C-04) -- never a UI-side check, never trusted from the
-- caller.
-- ===========================================================================
--
-- app._enroll_employee_in_training_session_internal locks the target
-- app.training_sessions row FOR UPDATE first (the parent), THEN counts
-- currently-'enrolled' rows against capacity and decides enrolled vs.
-- waitlisted -- the classic "counted without a lock" race this repository
-- has hit repeatedly elsewhere (RECURRING_DEFECT_TAXONOMY.md C-04) is
-- structurally closed here from the start. Every other function that
-- touches both a session and its enrollments (cancel_training_session,
-- decide_training_enrollment, cancel_training_enrollment, bulk mandatory
-- assignment) locks the session (parent) BEFORE any enrollment (child) row
-- -- the one function that touches TWO sessions
-- (reschedule_training_enrollment) locks both, ordered by ascending id, to
-- avoid a cross-function deadlock against a concurrent reverse-direction
-- reschedule (taxonomy C-21 discipline, applied from the start).
--
-- ===========================================================================
-- DECISION 4 -- certificate/provider evidence reuses the established
-- PLT-128 private, malware-scanned app.files gate (taxonomy C-10) exactly
-- as app.record_gps_device_installation and every onboarding-task-evidence
-- RPC already do -- never a second file-scanning mechanism.
-- ===========================================================================
--
-- A certificate is created FIRST (app.issue_training_certificate /
-- app.import_historical_training_certificate, evidence_file_id left null),
-- then evidence is attached via a dedicated
-- app.attach_training_certificate_evidence RPC that re-validates tenant,
-- record_type/record_id scope, AND malware_scan_status='clean' at the
-- accepting RPC itself -- mirrors app.attach_payroll_component_version_
-- evidence's (HRT-282) identical two-step shape, which exists specifically
-- to avoid the chicken-and-egg problem of uploading a file scoped to a
-- record that does not exist yet.
--
-- ===========================================================================
-- DECISION 5 -- certificate expiry and reminder both reuse the
-- established PLT-131/132 app.jobs durable-job framework (enqueue -> self-
-- claim -> scan -> complete), the identical inline-batch shape
-- app.run_leave_accrual_batch/app.run_leave_carry_forward_batch (HRT-280)
-- and app.calculate_payroll_run (HRT-282) already established -- never a
-- second job mechanism. job_type is widened with two new HRIS-domain
-- values ('training_certificate_expiry', 'training_certificate_expiry_
-- reminder'), kept set-equal with the standing ATW-031 drift gate
-- (scripts/db-tests/background-job.sql) by construction (both the CHECK
-- constraint and app.generic_job_types() are widened together, in the
-- same migration, exactly as every prior HRIS-domain adopter did).
--
-- ===========================================================================
-- DECISION 6 -- talent review/pool/succession is the MOST restricted tier
-- in this checkpoint: every write gates on HRS:Override (never plain
-- HRS:Edit or HRS:View personal data), and read access is narrower still.
-- ===========================================================================
--
-- A talent review CYCLE and a talent review ASSIGNMENT are readable by an
-- HRS:Override holder OR the specific employee assigned as reviewer for
-- that case -- "restricted talent reviewers see assigned cases" (section
-- 26), taken literally: an ordinary HRS:View personal data holder with no
-- HRS:Override and no assignment sees NONE of this. A talent POOL and a
-- SUCCESSION CANDIDATE row carry no per-case reviewer concept (they are
-- committee-level HR decisions, not one-reviewer-per-subject cases) and
-- are therefore HRS:Override-only, full stop -- never self-visible, never
-- manager-of-employee-visible, unlike every other person-scoped table in
-- this migration (deliberately narrower than app.can_view_hris_training_
-- talent_row, and narrower than HRT-283's own performance visibility
-- model).
--
-- ===========================================================================
-- DECISION 7 -- talent-domain decisions (succession candidate confirm/
-- withdraw) require a mandatory reason and a structural self-decision
-- block, mirroring HRT-283 decision 4 -- never a second approval-routing
-- mechanism (PLT-123 maker-checker). Nothing in this capability is a
-- batch-wide, irreversible, fund-disbursing moment of the kind HRT-282
-- decision 6 reserved PLT-123 for.
-- ===========================================================================
--
-- ===========================================================================
-- DECISION 8 -- a genuine k-anonymity floor (k=5, matching Prompt 283's
-- own precedent number) on the one aggregate report this checkpoint
-- builds: talent pool distribution by department.
-- ===========================================================================
--
-- app.report_talent_pool_distribution_by_department suppresses (nulls)
-- member_count for any department with fewer than 5 active pool members,
-- marking suppressed=true, enforced INSIDE the SECURITY DEFINER function
-- itself -- not merely a UI hint, and not merely the average of a
-- sensitive value (HRT-283's own shape) but the raw headcount itself,
-- since in the talent-pool domain the disclosive fact is membership size,
-- not a numeric average.
--
-- ===========================================================================
-- DECISION 9 -- taxonomy C-24 audit-masking discipline applied from the
-- start (this phase's own repeatedly-recurring defect: HRT-280, HRT-281,
-- HRT-282), never retrofitted.
-- ===========================================================================
--
-- Every capture_audit_event call below passes p_reason => null
-- unconditionally, and its after_value jsonb is built from an explicit,
-- reviewed allowlist that NEVER includes potential_rating/readiness_note/
-- risk_of_loss/decision_reason/appeal-shaped free text, na/cancel/reject/
-- decision reasons, score/notes fields, or any raw p_*_reason/p_*_note
-- parameter -- only ids, enum status/decision strings, and counts.
-- app.query_audit_logs is readable by any plain tenant_admin (zero HRS
-- role required) -- materially broader than this capability's own
-- HRS:Override / assigned-reviewer-only visibility model for the talent
-- domain specifically, exactly the gap C-24 documents.
--
-- ===========================================================================
-- DECISION 10 -- no rating-band/predictive subsystem; potential_rating is
-- a small, closed, human-entered qualitative enum (low/moderate/high),
-- never a computed score. No predictive/AI-driven talent ranking of any
-- kind (Step 14 boundary, section 13's own explicit exclusion).
-- ===========================================================================
--
-- ===========================================================================
-- DECISION 11 -- deliberately NOT built, disclosed rather than silently
-- dropped (taxonomy C-23 discipline).
-- ===========================================================================
--
-- No employee-level competency PROFICIENCY-rating subsystem -- only a
-- course-to-competency catalogue link (app.training_course_competencies).
-- Section 13 never names a persisted "employee skill rating" record of its
-- own; it names competency/skill and training CATALOGUE plus development-
-- plan/talent-succession records, which this checkpoint does build. No
-- REST/GraphQL adapter (repository-wide Phase 1-6 precedent). No per-date
-- multi-day attendance granularity -- one summary attended/hours_attended
-- pair per enrollment (a disclosed V1 simplification, the identical
-- proportional-effort shape HRT-282 decision 9 already established for
-- "no per-vintage FIFO lot tracker"). No live email/push notification
-- DISPATCH for certificate expiry reminders: the durable job produces a
-- real, queryable app.training_certificate_expiry_reminders record (the
-- actual scan/detection/dedup mechanism section 20 requires), but does not
-- itself call app.queue_notification -- doing so would require this
-- checkpoint to also author and publish a Platform notification-type
-- config version, a cross-cutting Platform Core concern with zero
-- precedent anywhere in the repository (grep-confirmed: zero other
-- capability calls app.queue_notification either) -- disclosed exactly
-- like PRC-261's identical "no async reminder-dispatch queue wired" gap
-- for vendor-contract expiry.

-- ===========================================================================
-- 1. app.training_competencies -- the competency/skill catalogue
--    (decision 1).
-- ===========================================================================

create table app.training_competencies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  name text not null,
  description text,
  category text,
  status text not null default 'draft',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint training_competencies_code_check check (code ~ '^[a-z0-9_]{2,60}$'),
  constraint training_competencies_name_check check (length(trim(name)) > 0),
  constraint training_competencies_status_check check (status in ('draft', 'published', 'archived')),
  constraint training_competencies_tenant_code_unique unique (tenant_id, code)
);

comment on table app.training_competencies is
  'HRT-284 (decision 1): a simple status-lifecycle reference taxonomy row -- draft/published/archived, no separate version table (unlike course, which genuinely needs frozen curriculum versioning). Linked from a course via app.training_course_competencies.';

create index training_competencies_tenant_status_idx on app.training_competencies (tenant_id, status);

create function app.touch_training_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

comment on function app.touch_training_row is
  'HRT-284: shared record_version-bump trigger for every versioned table below, mirroring app.touch_performance_row (HRT-283) / app.touch_payroll_row (HRT-282) -- reused, never reimplemented per-table.';

create trigger training_competencies_touch before update on app.training_competencies
  for each row execute function app.touch_training_row();

-- ===========================================================================
-- 2. app.training_courses / app.training_course_versions -- the versioned
--    course catalogue (decision 2).
-- ===========================================================================

create table app.training_courses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  name text not null,
  category text,
  status text not null default 'active',
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint training_courses_code_check check (code ~ '^[a-z0-9_-]{2,60}$'),
  constraint training_courses_name_check check (length(trim(name)) > 0),
  constraint training_courses_status_check check (status in ('active', 'retired')),
  constraint training_courses_tenant_code_unique unique (tenant_id, code)
);

comment on table app.training_courses is
  'HRT-284: the course identity catalogue -- code/name/category are fixed metadata (not versioned; the curriculum content that genuinely varies lives on app.training_course_versions). status=retired stops the course line appearing for NEW scheduling; already-scheduled sessions/enrollments are untouched.';

create index training_courses_tenant_status_idx on app.training_courses (tenant_id, status);

create trigger training_courses_touch before update on app.training_courses
  for each row execute function app.touch_training_row();

create table app.training_course_versions (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references app.training_courses (id),
  tenant_id uuid not null references app.tenants (id),
  version_number integer not null,
  status text not null default 'draft',
  description text,
  delivery_mode text not null default 'in_person',
  duration_hours numeric(6, 2),
  is_mandatory boolean not null default false,
  requires_enrollment_approval boolean not null default false,
  requires_assessment boolean not null default false,
  passing_score numeric(5, 2),
  issues_certificate boolean not null default false,
  certificate_validity_months integer,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint training_course_versions_status_check check (status in ('draft', 'published', 'archived')),
  constraint training_course_versions_delivery_mode_check check (delivery_mode in ('in_person', 'virtual', 'e_learning', 'blended')),
  constraint training_course_versions_duration_check check (duration_hours is null or duration_hours > 0),
  constraint training_course_versions_passing_score_shape_check check (
    (requires_assessment and passing_score is not null and passing_score >= 0 and passing_score <= 100)
    or (not requires_assessment and passing_score is null)
  ),
  constraint training_course_versions_cert_validity_check check (certificate_validity_months is null or certificate_validity_months >= 1),
  constraint training_course_versions_unique unique (course_id, version_number)
);

comment on table app.training_course_versions is
  'HRT-284 (decision 2): exactly one published version per course at a time -- app.publish_training_course_version archives the prior published version atomically. A session freezes the specific version it was scheduled against (app.training_sessions.course_version_id), so archiving a version never disturbs an already-scheduled session -- versioned and exact (business rule, section 24).';

create index training_course_versions_course_status_idx on app.training_course_versions (course_id, status);
create index training_course_versions_tenant_idx on app.training_course_versions (tenant_id);

create trigger training_course_versions_touch before update on app.training_course_versions
  for each row execute function app.touch_training_row();

create table app.training_course_competencies (
  course_id uuid not null references app.training_courses (id),
  tenant_id uuid not null references app.tenants (id),
  competency_id uuid not null references app.training_competencies (id),
  created_by text,
  created_at timestamptz not null default now(),
  constraint training_course_competencies_pk primary key (course_id, competency_id)
);

comment on table app.training_course_competencies is
  'HRT-284: which competencies a course teaches -- a simple catalogue join, add-only (no remove RPC this checkpoint, matches HRT-283''s identical disclosed "add-only pre-publish" precedent for template KPI items).';

create index training_course_competencies_tenant_idx on app.training_course_competencies (tenant_id);

-- ===========================================================================
-- 3. app.training_providers -- internal/external training providers.
-- ===========================================================================

create table app.training_providers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  name text not null,
  provider_type text not null default 'internal',
  contact_name text,
  contact_email text,
  contact_phone text,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint training_providers_name_check check (length(trim(name)) > 0),
  constraint training_providers_type_check check (provider_type in ('internal', 'external')),
  constraint training_providers_status_check check (status in ('active', 'inactive'))
);

comment on table app.training_providers is
  'HRT-284: internal or external training provider directory. Broadly tenant-visible (catalogue metadata, no personal data) -- an employee browsing the catalogue can see who runs a session.';

create index training_providers_tenant_status_idx on app.training_providers (tenant_id, status);

create trigger training_providers_touch before update on app.training_providers
  for each row execute function app.touch_training_row();

-- ===========================================================================
-- 4. app.training_course_prerequisites (decision 3 -- enforced inside the
--    enrollment RPC, section 24).
-- ===========================================================================

create table app.training_course_prerequisites (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  course_id uuid not null references app.training_courses (id),
  prerequisite_course_id uuid not null references app.training_courses (id),
  created_by text,
  created_at timestamptz not null default now(),
  constraint training_course_prerequisites_not_self_check check (course_id <> prerequisite_course_id),
  constraint training_course_prerequisites_unique unique (course_id, prerequisite_course_id)
);

comment on table app.training_course_prerequisites is
  'HRT-284: course_id requires a COMPLETED enrollment (any version) of prerequisite_course_id before app._enroll_employee_in_training_session_internal will enroll an employee. Direct prerequisites only -- no transitive/multi-hop chain walk (a disclosed, bounded V1 scope, matching HRT-282 decision 8''s identical "no generic multi-hop evaluator" proportional-effort call).';

create index training_course_prerequisites_course_idx on app.training_course_prerequisites (course_id);
create index training_course_prerequisites_tenant_idx on app.training_course_prerequisites (tenant_id);

-- ===========================================================================
-- 5. app.training_sessions -- a scheduled instance of a course version.
-- ===========================================================================

create table app.training_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  course_version_id uuid not null references app.training_course_versions (id),
  provider_id uuid references app.training_providers (id),
  session_code text not null,
  location text,
  start_at timestamptz not null,
  end_at timestamptz not null,
  capacity integer not null,
  status text not null default 'scheduled',
  cancel_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint training_sessions_dates_check check (end_at > start_at),
  constraint training_sessions_capacity_check check (capacity > 0),
  constraint training_sessions_status_check check (status in ('scheduled', 'in_progress', 'completed', 'cancelled')),
  constraint training_sessions_cancel_reason_check check (status <> 'cancelled' or cancel_reason is not null),
  constraint training_sessions_tenant_code_unique unique (tenant_id, session_code)
);

comment on table app.training_sessions is
  'HRT-284: one scheduled offering of a specific, published app.training_course_versions row -- frozen at create time (decision 2). capacity is enforced under a row lock at enroll time (decision 3), never trusted from a client-computed remaining count.';

create index training_sessions_tenant_status_idx on app.training_sessions (tenant_id, status);
create index training_sessions_course_version_idx on app.training_sessions (course_version_id);
create index training_sessions_tenant_start_idx on app.training_sessions (tenant_id, start_at);

create trigger training_sessions_touch before update on app.training_sessions
  for each row execute function app.touch_training_row();

-- ===========================================================================
-- 6. app.training_enrollments -- enrollment, attendance, and completion
--    (decision 3; section 13, 20, 21, 22).
-- ===========================================================================

create table app.training_enrollments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  session_id uuid not null references app.training_sessions (id),
  employee_id uuid not null references app.employees (master_record_id),
  course_version_id uuid not null references app.training_course_versions (id),
  status text not null default 'pending_approval',
  enrollment_source text not null default 'self',
  enrolled_by text,
  decided_by text,
  decided_at timestamptz,
  decision_reason text,
  cancelled_reason text,
  cancelled_at timestamptz,
  rescheduled_from_enrollment_id uuid references app.training_enrollments (id),
  attended boolean,
  hours_attended numeric(6, 2),
  attendance_recorded_by text,
  attendance_recorded_at timestamptz,
  completion_notes text,
  completed_at timestamptz,
  completion_recorded_by text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint training_enrollments_status_check check (status in ('pending_approval', 'enrolled', 'waitlisted', 'cancelled', 'completed', 'failed', 'no_show')),
  constraint training_enrollments_source_check check (enrollment_source in ('self', 'manager_assigned', 'hr_assigned', 'mandatory_assigned')),
  constraint training_enrollments_cancel_shape_check check (status <> 'cancelled' or cancelled_reason is not null),
  constraint training_enrollments_hours_check check (hours_attended is null or hours_attended >= 0),
  constraint training_enrollments_idempotency_key_unique unique (tenant_id, idempotency_key)
);

comment on table app.training_enrollments is
  'HRT-284: one row per (session, employee) participation. course_version_id is frozen from the session at enroll time. Attendance (attended/hours_attended) and completion (status=completed/failed/no_show, completion_notes) are both recorded on this same row rather than a second table -- a disclosed V1 simplification (decision 11), one summary pair per enrollment, never per-date granularity.';

create index training_enrollments_tenant_session_idx on app.training_enrollments (tenant_id, session_id);
create index training_enrollments_tenant_employee_idx on app.training_enrollments (tenant_id, employee_id);
create unique index training_enrollments_active_unique on app.training_enrollments (session_id, employee_id) where status in ('pending_approval', 'enrolled', 'waitlisted');

create trigger training_enrollments_touch before update on app.training_enrollments
  for each row execute function app.touch_training_row();

-- ===========================================================================
-- 7. app.training_assessments -- scored attempts against an enrollment.
-- ===========================================================================

create table app.training_assessments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  enrollment_id uuid not null references app.training_enrollments (id),
  employee_id uuid not null references app.employees (master_record_id),
  course_version_id uuid not null references app.training_course_versions (id),
  attempt_number integer not null,
  score numeric(5, 2) not null,
  max_score numeric(5, 2) not null default 100,
  passed boolean not null,
  assessed_by text,
  assessed_at timestamptz not null default now(),
  notes text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  constraint training_assessments_score_check check (score >= 0),
  constraint training_assessments_max_score_check check (max_score > 0),
  constraint training_assessments_score_bound_check check (score <= max_score),
  constraint training_assessments_attempt_check check (attempt_number > 0),
  constraint training_assessments_unique unique (enrollment_id, attempt_number)
);

comment on table app.training_assessments is
  'HRT-284: an append-only assessment attempt log -- multiple retries per enrollment are legal (attempt_number auto-increments). passed is computed deterministically from score/max_score vs. the course version''s own passing_score at record time (app.compute_training_assessment_passed), never a UI toggle (business rule, section 24).';

create index training_assessments_enrollment_idx on app.training_assessments (enrollment_id, attempt_number desc);
create index training_assessments_tenant_employee_idx on app.training_assessments (tenant_id, employee_id);

-- ===========================================================================
-- 8. app.training_certificates / app.training_certificate_expiry_reminders
--    (decision 4, 5; section 13, 20).
-- ===========================================================================

create table app.training_certificates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  course_version_id uuid references app.training_course_versions (id),
  external_course_name text,
  enrollment_id uuid references app.training_enrollments (id),
  provider_id uuid references app.training_providers (id),
  certificate_number text,
  issued_at date not null,
  expiry_date date,
  status text not null default 'issued',
  source text not null default 'internal_completion',
  verification_status text not null default 'unverified',
  evidence_file_id uuid references app.files (id),
  renewed_from_certificate_id uuid references app.training_certificates (id),
  revoked_reason text,
  revoked_at timestamptz,
  revoked_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint training_certificates_status_check check (status in ('issued', 'expired', 'revoked')),
  constraint training_certificates_source_check check (source in ('internal_completion', 'external_import')),
  constraint training_certificates_verification_check check (verification_status in ('verified', 'unverified')),
  constraint training_certificates_course_shape_check check (course_version_id is not null or external_course_name is not null),
  constraint training_certificates_expiry_check check (expiry_date is null or expiry_date >= issued_at),
  constraint training_certificates_revoked_shape_check check (status <> 'revoked' or revoked_reason is not null),
  constraint training_certificates_tenant_number_unique unique (tenant_id, certificate_number)
);

comment on table app.training_certificates is
  'HRT-284 (decision 4): evidence_file_id is attached AFTER creation via app.attach_training_certificate_evidence (never uploaded before the record exists), re-validated for tenant/record-scope/clean-scan at that RPC. source=external_import (data migration impact, section 19) starts verification_status=unverified until app.verify_training_certificate reviews it -- never inferred as competency/talent classification from an unverified import.';

create index training_certificates_tenant_employee_idx on app.training_certificates (tenant_id, employee_id);
create index training_certificates_tenant_expiry_idx on app.training_certificates (tenant_id, expiry_date) where status in ('issued');

create trigger training_certificates_touch before update on app.training_certificates
  for each row execute function app.touch_training_row();

create table app.training_certificate_expiry_reminders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  certificate_id uuid not null references app.training_certificates (id),
  employee_id uuid not null references app.employees (master_record_id),
  period_label text not null,
  days_until_expiry integer not null,
  job_id uuid,
  reminded_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint training_certificate_expiry_reminders_unique unique (certificate_id, period_label)
);

comment on table app.training_certificate_expiry_reminders is
  'HRT-284 (decision 5): the real, queryable output of app.run_training_certificate_expiry_reminder_batch -- one row per (certificate, reminder period), idempotent by construction. Does NOT itself dispatch a notification (decision 11, disclosed).';

create index training_certificate_expiry_reminders_employee_idx on app.training_certificate_expiry_reminders (tenant_id, employee_id);

-- ===========================================================================
-- 9. app.training_development_plans / app.training_development_plan_actions
--    (section 13, 20).
-- ===========================================================================

create table app.training_development_plans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  title text not null,
  cycle_label text,
  status text not null default 'draft',
  linked_performance_outcome_id uuid references app.performance_outcomes (id),
  owner_note text,
  cancel_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint training_development_plans_title_check check (length(trim(title)) > 0),
  constraint training_development_plans_status_check check (status in ('draft', 'active', 'completed', 'cancelled')),
  constraint training_development_plans_cancel_shape_check check (status <> 'cancelled' or cancel_reason is not null)
);

comment on table app.training_development_plans is
  'HRT-284: a manager- or HR-authored development plan for one employee, optionally evidenced by a specific HRT-283 performance outcome (linked_performance_outcome_id) -- section 20''s "bind employee/position/KPI evidence". Never automatically created or advanced by any performance event -- always an explicit human action (business rule, section 24).';

create index training_development_plans_tenant_employee_idx on app.training_development_plans (tenant_id, employee_id);

create trigger training_development_plans_touch before update on app.training_development_plans
  for each row execute function app.touch_training_row();

create table app.training_development_plan_actions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  plan_id uuid not null references app.training_development_plans (id),
  action_type text not null default 'training',
  description text not null,
  linked_course_id uuid references app.training_courses (id),
  target_date date,
  status text not null default 'planned',
  completed_note text,
  completed_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint training_development_plan_actions_type_check check (action_type in ('training', 'coaching', 'stretch_assignment', 'certification', 'other')),
  constraint training_development_plan_actions_description_check check (length(trim(description)) > 0),
  constraint training_development_plan_actions_status_check check (status in ('planned', 'in_progress', 'completed', 'cancelled'))
);

comment on table app.training_development_plan_actions is
  'HRT-284: one concrete action item within a development plan, optionally pointing at a specific catalogue course.';

create index training_development_plan_actions_plan_idx on app.training_development_plan_actions (plan_id);

create trigger training_development_plan_actions_touch before update on app.training_development_plan_actions
  for each row execute function app.touch_training_row();

-- ===========================================================================
-- 10. app.talent_review_cycles / app.talent_review_assignments /
--     app.talent_reviews -- the restricted talent-review workspace
--     (decision 6, 7; section 13, 20, 26).
-- ===========================================================================

create table app.talent_review_cycles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  name text not null,
  period_label text not null,
  status text not null default 'draft',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint talent_review_cycles_name_check check (length(trim(name)) > 0),
  constraint talent_review_cycles_status_check check (status in ('draft', 'active', 'closed')),
  constraint talent_review_cycles_tenant_name_unique unique (tenant_id, name)
);

comment on table app.talent_review_cycles is
  'HRT-284 (decision 6): the administrative container for a round of talent reviews. Readable ONLY by an HRS:Override holder or an employee with an active reviewer assignment inside this specific cycle -- never plain tenant membership, never HRS:View personal data alone.';

create index talent_review_cycles_tenant_status_idx on app.talent_review_cycles (tenant_id, status);

create trigger talent_review_cycles_touch before update on app.talent_review_cycles
  for each row execute function app.touch_training_row();

create table app.talent_review_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  cycle_id uuid not null references app.talent_review_cycles (id),
  subject_employee_id uuid not null references app.employees (master_record_id),
  reviewer_employee_id uuid not null references app.employees (master_record_id),
  status text not null default 'active',
  reassigned_from_assignment_id uuid references app.talent_review_assignments (id),
  reassign_reason text,
  assigned_by text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint talent_review_assignments_status_check check (status in ('active', 'reassigned')),
  constraint talent_review_assignments_not_self_check check (reviewer_employee_id <> subject_employee_id)
);

comment on table app.talent_review_assignments is
  'HRT-284 (decision 6, mirrors HRT-283''s reviewer-assignment freeze exactly): reviewer_employee_id is resolved ONCE and frozen -- never re-derived live. app.reassign_talent_reviewer is the ONLY way to change it, and does so by creating a NEW row + marking this one reassigned, never mutating this row or its already-submitted review in place. One active reviewer per (cycle, subject) at a time -- a disclosed V1 simplification, never a multi-reviewer 360 for talent review.';

create index talent_review_assignments_tenant_cycle_idx on app.talent_review_assignments (tenant_id, cycle_id);
create index talent_review_assignments_reviewer_idx on app.talent_review_assignments (tenant_id, reviewer_employee_id, status);
create unique index talent_review_assignments_active_unique on app.talent_review_assignments (cycle_id, subject_employee_id) where status = 'active';

create trigger talent_review_assignments_touch before update on app.talent_review_assignments
  for each row execute function app.touch_training_row();

create table app.talent_reviews (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  cycle_id uuid not null references app.talent_review_cycles (id),
  subject_employee_id uuid not null references app.employees (master_record_id),
  assignment_id uuid not null references app.talent_review_assignments (id),
  potential_rating text,
  readiness_note text,
  risk_of_loss text,
  status text not null default 'draft',
  submitted_by text,
  submitted_at timestamptz,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint talent_reviews_potential_rating_check check (potential_rating is null or potential_rating in ('low', 'moderate', 'high')),
  constraint talent_reviews_risk_check check (risk_of_loss is null or risk_of_loss in ('low', 'medium', 'high')),
  constraint talent_reviews_status_check check (status in ('draft', 'submitted')),
  constraint talent_reviews_submit_shape_check check (status <> 'submitted' or potential_rating is not null),
  constraint talent_reviews_assignment_unique unique (assignment_id)
);

comment on table app.talent_reviews is
  'HRT-284 (decision 6, 10): the recorded decision evidence for one reviewer/subject case. potential_rating is a small, closed, human-entered enum -- never a computed score (decision 10). Content readable/writable ONLY by the assignment''s own reviewer_employee_id or an HRS:Override holder.';

create index talent_reviews_cycle_idx on app.talent_reviews (tenant_id, cycle_id);

create trigger talent_reviews_touch before update on app.talent_reviews
  for each row execute function app.touch_training_row();

-- ===========================================================================
-- 11. app.talent_pools / app.talent_pool_members (decision 6; section 13,
--     20).
-- ===========================================================================

create table app.talent_pools (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  name text not null,
  description text,
  pool_type text not null default 'high_potential',
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint talent_pools_name_check check (length(trim(name)) > 0),
  constraint talent_pools_type_check check (pool_type in ('successor', 'high_potential', 'critical_role')),
  constraint talent_pools_status_check check (status in ('active', 'archived')),
  constraint talent_pools_tenant_name_unique unique (tenant_id, name)
);

comment on table app.talent_pools is
  'HRT-284 (decision 6): an HR-governed talent pool. HRS:Override-only -- no per-case reviewer concept, no self/manager visibility of any kind, even narrower than app.talent_reviews.';

create index talent_pools_tenant_status_idx on app.talent_pools (tenant_id, status);

create trigger talent_pools_touch before update on app.talent_pools
  for each row execute function app.touch_training_row();

create table app.talent_pool_members (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  pool_id uuid not null references app.talent_pools (id),
  employee_id uuid not null references app.employees (master_record_id),
  status text not null default 'active',
  added_reason text not null,
  added_by text,
  added_at timestamptz not null default now(),
  removed_reason text,
  removed_by text,
  removed_at timestamptz,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint talent_pool_members_status_check check (status in ('active', 'removed')),
  constraint talent_pool_members_added_reason_check check (length(trim(added_reason)) > 0),
  constraint talent_pool_members_removed_shape_check check (status <> 'removed' or removed_reason is not null)
);

comment on table app.talent_pool_members is
  'HRT-284: membership requires a mandatory added_reason -- human evidence, never a bare toggle (business rule, section 24).';

create index talent_pool_members_pool_idx on app.talent_pool_members (pool_id, status);
create index talent_pool_members_tenant_employee_idx on app.talent_pool_members (tenant_id, employee_id);
create unique index talent_pool_members_active_unique on app.talent_pool_members (pool_id, employee_id) where status = 'active';

create trigger talent_pool_members_touch before update on app.talent_pool_members
  for each row execute function app.touch_training_row();

-- ===========================================================================
-- 12. app.talent_succession_candidates (decision 6, 7; section 13, 20).
-- ===========================================================================

create table app.talent_succession_candidates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  position_id uuid not null references app.positions (id),
  candidate_employee_id uuid not null references app.employees (master_record_id),
  readiness text not null,
  decision_reason text not null,
  status text not null default 'proposed',
  decided_by text,
  decided_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint talent_succession_candidates_readiness_check check (readiness in ('ready_now', 'ready_1_2_years', 'ready_3_plus_years', 'development_needed')),
  constraint talent_succession_candidates_reason_check check (length(trim(decision_reason)) > 0),
  constraint talent_succession_candidates_status_check check (status in ('proposed', 'confirmed', 'withdrawn'))
);

comment on table app.talent_succession_candidates is
  'HRT-284 (decision 7): every propose/decide call requires a mandatory human reason (decision_reason) -- "authorized human evidence, reason and review" (business rule, section 24). app.decide_succession_candidate structurally blocks a candidate deciding their own record.';

create index talent_succession_candidates_position_idx on app.talent_succession_candidates (tenant_id, position_id);
create index talent_succession_candidates_tenant_candidate_idx on app.talent_succession_candidates (tenant_id, candidate_employee_id);
create unique index talent_succession_candidates_active_unique on app.talent_succession_candidates (position_id, candidate_employee_id) where status <> 'withdrawn';

create trigger talent_succession_candidates_touch before update on app.talent_succession_candidates
  for each row execute function app.touch_training_row();

-- ===========================================================================
-- 13. Authority and visibility helpers (decision 3, 6).
-- ===========================================================================

create function app.check_training_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', p_action)).allowed;
$$;

comment on function app.check_training_authority is
  'HRT-284: HRS:Edit gates authoring (competency/course/provider/prerequisite/session create, self/HR enrollment, attendance/completion/assessment recording, certificate issue/import/attach, development plan authoring); HRS:Approve gates publish/verify/decide actions (course version publish, certificate verify, enrollment decide); HRS:Override gates every talent-domain write, session/certificate cancellation-class actions, and the certificate expiry/reminder batches. SECURITY DEFINER from the start (HRT-281/282/283''s own established lesson: a bare SECURITY INVOKER wrapper fails inside an RLS policy expression).';

create function app.can_view_hris_training_talent_row(p_tenant_id uuid, p_employee_id uuid, p_auth_user_id uuid default auth.uid())
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

comment on function app.can_view_hris_training_talent_row is
  'HRT-284: self OR direct manager OR HRS:View personal data -- used for RLS on enrollment/assessment/certificate/reminder/development-plan tables ("results... are purpose- and field-restricted", section 16). Reuses app._is_direct_manager_of_employee (HRT-283, single-level direct-report predicate) rather than a second manager-hierarchy mechanism. Deliberately NOT used for the talent-domain tables below -- decision 6''s narrower model.';

create function app.can_view_talent_review_row(p_tenant_id uuid, p_reviewer_employee_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  if p_tenant_id is null then
    return false;
  end if;
  if not app.has_active_tenant_membership(p_tenant_id, p_auth_user_id) then
    return false;
  end if;
  if (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'HRS', 'Override')).allowed then
    return true;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_auth_user_id);
  return v_self.master_record_id is not null and v_self.master_record_id = p_reviewer_employee_id;
end;
$$;

comment on function app.can_view_talent_review_row is
  'HRT-284 (decision 6): HRS:Override OR being the specific assigned reviewer -- "restricted talent reviewers see assigned cases" taken literally. Never self (the SUBJECT of a review does not see it), never direct manager, never plain HRS:View personal data. Used for RLS on talent_review_assignments/talent_reviews, and (via an EXISTS join) talent_review_cycles.';

create function app._training_prerequisites_met(p_tenant_id uuid, p_employee_id uuid, p_course_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select not exists (
    select 1
    from app.training_course_prerequisites p
    where p.tenant_id = p_tenant_id and p.course_id = p_course_id
      and not exists (
        select 1
        from app.training_enrollments e
        join app.training_course_versions cv on cv.id = e.course_version_id
        where e.tenant_id = p_tenant_id and e.employee_id = p_employee_id and e.status = 'completed'
          and cv.course_id = p.prerequisite_course_id
      )
  );
$$;

comment on function app._training_prerequisites_met is
  'HRT-284 (decision 3): true iff every DIRECT prerequisite of p_course_id has at least one COMPLETED enrollment (any version) for p_employee_id. Internal-only (service_role), called from app._enroll_employee_in_training_session_internal.';

-- ===========================================================================
-- 14. Competency lifecycle (decision 1).
-- ===========================================================================

create function app.create_training_competency(p_tenant_id uuid, p_code text, p_name text, p_description text, p_category text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_competencies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.training_competencies;
begin
  if not app.check_training_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app.training_competencies where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_row;
  end if;

  begin
    insert into app.training_competencies (tenant_id, code, name, description, category, created_by)
    values (p_tenant_id, p_code, p_name, p_description, p_category, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'training_competency_code_conflict: a competency with code % was just created concurrently for tenant %', p_code, p_tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_training_competency',
    'app.training_competencies', v_row.id, 'success', null, null, jsonb_build_object('code', p_code)
  );

  return v_row;
end;
$$;

comment on function app.create_training_competency is
  'HRT-284: idempotent on (tenant_id, code); a genuinely concurrent duplicate create raises a clean, classifiable training_competency_code_conflict rather than a raw 23505 (taxonomy C-01/C-02, applied from the start).';

create function app.publish_training_competency(p_competency_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_competencies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.training_competencies;
begin
  select * into v_row from app.training_competencies where id = p_competency_id for update;
  if not found then
    raise exception 'training_competency_not_found: %', p_competency_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Approve', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'invalid_transition: competency % is % not draft', p_competency_id, v_row.status using errcode = 'check_violation';
  end if;

  update app.training_competencies set status = 'published' where id = p_competency_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: concurrent update detected for competency %', p_competency_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_training_competency',
    'app.training_competencies', v_row.id, 'success', null, null, jsonb_build_object('code', v_row.code)
  );

  return v_row;
end;
$$;

create function app.archive_training_competency(p_competency_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_competencies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.training_competencies;
begin
  select * into v_row from app.training_competencies where id = p_competency_id for update;
  if not found then
    raise exception 'training_competency_not_found: %', p_competency_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status = 'archived' then
    raise exception 'invalid_transition: competency % is already archived', p_competency_id using errcode = 'check_violation';
  end if;

  update app.training_competencies set status = 'archived' where id = p_competency_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: concurrent update detected for competency %', p_competency_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_training_competency',
    'app.training_competencies', v_row.id, 'success', null, null, jsonb_build_object('code', v_row.code)
  );

  return v_row;
end;
$$;

create function app.list_training_competencies(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.training_competencies
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.training_competencies where tenant_id = p_tenant_id order by code;
end;
$$;

-- ===========================================================================
-- 15. Course / course-version lifecycle (decision 2).
-- ===========================================================================

create function app.create_training_course(p_tenant_id uuid, p_code text, p_name text, p_category text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_courses
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.training_courses;
begin
  if not app.check_training_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app.training_courses where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_row;
  end if;

  begin
    insert into app.training_courses (tenant_id, code, name, category, created_by)
    values (p_tenant_id, p_code, p_name, p_category, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'training_course_code_conflict: a course with code % was just created concurrently for tenant %', p_code, p_tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_training_course',
    'app.training_courses', v_row.id, 'success', null, null, jsonb_build_object('code', p_code)
  );

  return v_row;
end;
$$;

create function app.create_training_course_version(
  p_course_id uuid, p_description text, p_delivery_mode text, p_duration_hours numeric, p_is_mandatory boolean,
  p_requires_enrollment_approval boolean, p_requires_assessment boolean, p_passing_score numeric,
  p_issues_certificate boolean, p_certificate_validity_months integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.training_course_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_course app.training_courses;
  v_next integer;
  v_version app.training_course_versions;
begin
  select * into v_course from app.training_courses where id = p_course_id;
  if not found then
    raise exception 'training_course_not_found: %', p_course_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_course.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_course.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_delivery_mode not in ('in_person', 'virtual', 'e_learning', 'blended') then
    raise exception 'invalid_delivery_mode: %', p_delivery_mode using errcode = 'check_violation';
  end if;
  if coalesce(p_requires_assessment, false) and p_passing_score is null then
    raise exception 'passing_score_required: requires_assessment courses need a passing_score' using errcode = 'check_violation';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next from app.training_course_versions where course_id = p_course_id;

  begin
    insert into app.training_course_versions (
      course_id, tenant_id, version_number, description, delivery_mode, duration_hours, is_mandatory,
      requires_enrollment_approval, requires_assessment, passing_score, issues_certificate, certificate_validity_months, created_by
    ) values (
      p_course_id, v_course.tenant_id, v_next, p_description, p_delivery_mode, p_duration_hours, coalesce(p_is_mandatory, false),
      coalesce(p_requires_enrollment_approval, false), coalesce(p_requires_assessment, false), p_passing_score,
      coalesce(p_issues_certificate, false), p_certificate_validity_months, p_actor_label
    )
    returning * into v_version;
  exception
    when unique_violation then
      raise exception 'training_course_version_conflict: a version was just created concurrently for course % -- retry to get the current next version number', p_course_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_course.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_training_course_version',
    'app.training_course_versions', v_version.id, 'success', null, null, jsonb_build_object('course_id', p_course_id, 'version_number', v_next)
  );

  return v_version;
end;
$$;

create function app.publish_training_course_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_course_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.training_course_versions;
begin
  select * into v_version from app.training_course_versions where id = p_version_id for update;
  if not found then
    raise exception 'training_course_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Approve', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: version % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  -- Exactly one published version per course (decision 2) -- archiving the
  -- prior published version here is idempotent under concurrency (setting
  -- status to 'archived' twice is harmless); the real race (two concurrent
  -- callers both computing the same v_next at create time) is caught by
  -- create_training_course_version's own exception handler, not here.
  update app.training_course_versions set status = 'archived' where course_id = v_version.course_id and status = 'published';

  update app.training_course_versions set status = 'published' where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: concurrent update detected for version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_training_course_version',
    'app.training_course_versions', v_version.id, 'success', null, null, jsonb_build_object('course_id', v_version.course_id, 'version_number', v_version.version_number)
  );

  return v_version;
end;
$$;

create function app.archive_training_course_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_course_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.training_course_versions;
begin
  select * into v_version from app.training_course_versions where id = p_version_id for update;
  if not found then
    raise exception 'training_course_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status = 'archived' then
    raise exception 'invalid_transition: version % is already archived', p_version_id using errcode = 'check_violation';
  end if;

  update app.training_course_versions set status = 'archived' where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: concurrent update detected for version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_training_course_version',
    'app.training_course_versions', v_version.id, 'success', null, null, jsonb_build_object('course_id', v_version.course_id)
  );

  return v_version;
end;
$$;

create function app.add_training_course_competency(p_course_id uuid, p_competency_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_course_competencies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_course app.training_courses;
  v_row app.training_course_competencies;
begin
  select * into v_course from app.training_courses where id = p_course_id;
  if not found then
    raise exception 'training_course_not_found: %', p_course_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_course.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_course.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from app.training_competencies c where c.id = p_competency_id and c.tenant_id = v_course.tenant_id) then
    raise exception 'training_competency_not_found: %', p_competency_id using errcode = 'no_data_found';
  end if;

  begin
    insert into app.training_course_competencies (course_id, tenant_id, competency_id, created_by)
    values (p_course_id, v_course.tenant_id, p_competency_id, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.training_course_competencies where course_id = p_course_id and competency_id = p_competency_id;
      return v_row;
  end;

  perform app.capture_audit_event(
    v_course.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_training_course_competency',
    'app.training_course_competencies', p_course_id, 'success', null, null, jsonb_build_object('course_id', p_course_id, 'competency_id', p_competency_id)
  );

  return v_row;
end;
$$;

create function app.list_training_courses(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.training_courses
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.training_courses where tenant_id = p_tenant_id order by code;
end;
$$;

create function app.list_training_course_versions(p_course_id uuid, p_actor_auth_user_id uuid)
returns setof app.training_course_versions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_course app.training_courses;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_course from app.training_courses where id = p_course_id;
  if not found then
    raise exception 'training_course_not_found: %', p_course_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_course.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_course.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.training_course_versions where course_id = p_course_id order by version_number desc;
end;
$$;

create function app.list_training_course_competencies(p_course_id uuid, p_actor_auth_user_id uuid)
returns table (course_id uuid, competency_id uuid, competency_code text, competency_name text)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_course app.training_courses;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_course from app.training_courses where id = p_course_id;
  if not found then
    raise exception 'training_course_not_found: %', p_course_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_course.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_course.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select tc.course_id, tc.competency_id, c.code, c.name
  from app.training_course_competencies tc
  join app.training_competencies c on c.id = tc.competency_id
  where tc.course_id = p_course_id
  order by c.code;
end;
$$;

-- ===========================================================================
-- 16. Provider lifecycle.
-- ===========================================================================

create function app.create_training_provider(p_tenant_id uuid, p_name text, p_provider_type text, p_contact_name text, p_contact_email text, p_contact_phone text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_providers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.training_providers;
begin
  if not app.check_training_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_provider_type not in ('internal', 'external') then
    raise exception 'invalid_provider_type: %', p_provider_type using errcode = 'check_violation';
  end if;

  insert into app.training_providers (tenant_id, name, provider_type, contact_name, contact_email, contact_phone, created_by)
  values (p_tenant_id, p_name, p_provider_type, p_contact_name, p_contact_email, p_contact_phone, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_training_provider',
    'app.training_providers', v_row.id, 'success', null, null, jsonb_build_object('name', p_name, 'provider_type', p_provider_type)
  );

  return v_row;
end;
$$;

create function app.update_training_provider_status(p_provider_id uuid, p_expected_version integer, p_status text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_providers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.training_providers;
begin
  select * into v_row from app.training_providers where id = p_provider_id for update;
  if not found then
    raise exception 'training_provider_not_found: %', p_provider_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_status not in ('active', 'inactive') then
    raise exception 'invalid_status: %', p_status using errcode = 'check_violation';
  end if;

  update app.training_providers set status = p_status where id = p_provider_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: concurrent update detected for provider %', p_provider_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_training_provider_status',
    'app.training_providers', v_row.id, 'success', null, null, jsonb_build_object('status', p_status)
  );

  return v_row;
end;
$$;

create function app.list_training_providers(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.training_providers
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.training_providers where tenant_id = p_tenant_id order by name;
end;
$$;

-- ===========================================================================
-- 17. Prerequisite management.
-- ===========================================================================

create function app.add_training_course_prerequisite(p_course_id uuid, p_prerequisite_course_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_course_prerequisites
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_course app.training_courses;
  v_row app.training_course_prerequisites;
begin
  select * into v_course from app.training_courses where id = p_course_id;
  if not found then
    raise exception 'training_course_not_found: %', p_course_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_course.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_course.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_course_id = p_prerequisite_course_id then
    raise exception 'invalid_prerequisite: a course cannot require itself' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.training_courses c where c.id = p_prerequisite_course_id and c.tenant_id = v_course.tenant_id) then
    raise exception 'training_course_not_found: %', p_prerequisite_course_id using errcode = 'no_data_found';
  end if;

  begin
    insert into app.training_course_prerequisites (tenant_id, course_id, prerequisite_course_id, created_by)
    values (v_course.tenant_id, p_course_id, p_prerequisite_course_id, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.training_course_prerequisites where course_id = p_course_id and prerequisite_course_id = p_prerequisite_course_id;
      return v_row;
  end;

  perform app.capture_audit_event(
    v_course.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_training_course_prerequisite',
    'app.training_course_prerequisites', v_row.id, 'success', null, null, jsonb_build_object('course_id', p_course_id, 'prerequisite_course_id', p_prerequisite_course_id)
  );

  return v_row;
end;
$$;

create function app.remove_training_course_prerequisite(p_prerequisite_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.training_course_prerequisites;
begin
  select * into v_row from app.training_course_prerequisites where id = p_prerequisite_id;
  if not found then
    raise exception 'training_course_prerequisite_not_found: %', p_prerequisite_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  delete from app.training_course_prerequisites where id = p_prerequisite_id;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_training_course_prerequisite',
    'app.training_course_prerequisites', p_prerequisite_id, 'success', null, null, jsonb_build_object('course_id', v_row.course_id, 'prerequisite_course_id', v_row.prerequisite_course_id)
  );
end;
$$;

create function app.list_training_course_prerequisites(p_course_id uuid, p_actor_auth_user_id uuid)
returns setof app.training_course_prerequisites
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_course app.training_courses;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_course from app.training_courses where id = p_course_id;
  if not found then
    raise exception 'training_course_not_found: %', p_course_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_course.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_course.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.training_course_prerequisites where course_id = p_course_id;
end;
$$;

-- ===========================================================================
-- 18. Session lifecycle.
-- ===========================================================================

create function app.create_training_session(
  p_tenant_id uuid, p_course_version_id uuid, p_provider_id uuid, p_session_code text, p_location text,
  p_start_at timestamptz, p_end_at timestamptz, p_capacity integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.training_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.training_course_versions;
  v_row app.training_sessions;
begin
  if not app.check_training_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  select * into v_version from app.training_course_versions where id = p_course_version_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'training_course_version_not_found: %', p_course_version_id using errcode = 'no_data_found';
  end if;
  if v_version.status <> 'published' then
    raise exception 'course_version_not_published: version % is % not published', p_course_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if p_end_at <= p_start_at then
    raise exception 'invalid_session_dates: end_at must be after start_at' using errcode = 'check_violation';
  end if;
  if coalesce(p_capacity, 0) <= 0 then
    raise exception 'invalid_capacity: capacity must be positive' using errcode = 'check_violation';
  end if;
  if p_provider_id is not null and not exists (select 1 from app.training_providers pr where pr.id = p_provider_id and pr.tenant_id = p_tenant_id) then
    raise exception 'training_provider_not_found: %', p_provider_id using errcode = 'no_data_found';
  end if;

  select * into v_row from app.training_sessions where tenant_id = p_tenant_id and session_code = p_session_code;
  if found then
    return v_row;
  end if;

  begin
    insert into app.training_sessions (tenant_id, course_version_id, provider_id, session_code, location, start_at, end_at, capacity, created_by)
    values (p_tenant_id, p_course_version_id, p_provider_id, p_session_code, p_location, p_start_at, p_end_at, p_capacity, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'training_session_code_conflict: a session with code % was just created concurrently for tenant %', p_session_code, p_tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_training_session',
    'app.training_sessions', v_row.id, 'success', null, null, jsonb_build_object('session_code', p_session_code, 'course_version_id', p_course_version_id)
  );

  return v_row;
end;
$$;

-- Cancels a session AND every still-active enrollment against it. Lock
-- order (decision 3, taxonomy C-21): session (parent) FIRST, then every
-- active enrollment (child) -- the SAME order app._enroll_employee_in_
-- training_session_internal/app.decide_training_enrollment/app.cancel_
-- training_enrollment all use, so no two functions in this migration ever
-- lock these two tables in conflicting order.
create function app.cancel_training_session(p_session_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_session app.training_sessions;
  v_enrollment record;
  v_cancelled_count integer := 0;
begin
  select * into v_session from app.training_sessions where id = p_session_id for update;
  if not found then
    raise exception 'training_session_not_found: %', p_session_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_session.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_session.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_session.status = 'cancelled' then
    raise exception 'invalid_transition: session % is already cancelled', p_session_id using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to cancel a training session' using errcode = 'check_violation';
  end if;

  for v_enrollment in
    select * from app.training_enrollments where session_id = p_session_id and status in ('pending_approval', 'enrolled', 'waitlisted') order by id for update
  loop
    update app.training_enrollments
    set status = 'cancelled', cancelled_reason = 'session_cancelled: ' || p_reason, cancelled_at = now()
    where id = v_enrollment.id;
    v_cancelled_count := v_cancelled_count + 1;
  end loop;

  update app.training_sessions set status = 'cancelled', cancel_reason = p_reason where id = p_session_id and record_version = p_expected_version
  returning * into v_session;
  if not found then
    raise exception 'stale_version: concurrent update detected for session %', p_session_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_training_session',
    'app.training_sessions', v_session.id, 'success', null, null, jsonb_build_object('cancelled_enrollment_count', v_cancelled_count)
  );

  return v_session;
end;
$$;

create function app.list_training_sessions(p_tenant_id uuid, p_actor_auth_user_id uuid, p_course_id uuid default null, p_status text default null)
returns table (
  id uuid, course_version_id uuid, course_id uuid, course_code text, course_name text, provider_id uuid, provider_name text,
  session_code text, location text, start_at timestamptz, end_at timestamptz, capacity integer, enrolled_count integer, status text, record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select s.id, s.course_version_id, cv.course_id, c.code, c.name, s.provider_id, pr.name,
    s.session_code, s.location, s.start_at, s.end_at, s.capacity,
    (select count(*)::integer from app.training_enrollments e where e.session_id = s.id and e.status = 'enrolled'),
    s.status, s.record_version
  from app.training_sessions s
  join app.training_course_versions cv on cv.id = s.course_version_id
  join app.training_courses c on c.id = cv.course_id
  left join app.training_providers pr on pr.id = s.provider_id
  where s.tenant_id = p_tenant_id and (p_course_id is null or c.id = p_course_id) and (p_status is null or s.status = p_status)
  order by s.start_at desc;
end;
$$;

create function app.get_training_session(p_session_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, course_version_id uuid, course_id uuid, course_code text, course_name text, provider_id uuid, provider_name text,
  session_code text, location text, start_at timestamptz, end_at timestamptz, capacity integer, enrolled_count integer, waitlisted_count integer, status text, record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_session app.training_sessions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_session from app.training_sessions where id = p_session_id;
  if not found then
    raise exception 'training_session_not_found: %', p_session_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select s.id, s.course_version_id, cv.course_id, c.code, c.name, s.provider_id, pr.name,
    s.session_code, s.location, s.start_at, s.end_at, s.capacity,
    (select count(*)::integer from app.training_enrollments e where e.session_id = s.id and e.status = 'enrolled'),
    (select count(*)::integer from app.training_enrollments e where e.session_id = s.id and e.status = 'waitlisted'),
    s.status, s.record_version
  from app.training_sessions s
  join app.training_course_versions cv on cv.id = s.course_version_id
  join app.training_courses c on c.id = cv.course_id
  left join app.training_providers pr on pr.id = s.provider_id
  where s.id = p_session_id;
end;
$$;

-- ===========================================================================
-- 19. Enrollment, attendance, and completion (decision 3; section 13, 20,
--     21, 22).
-- ===========================================================================

-- The one real enrollment engine, service_role-only. Locks the session row
-- FOR UPDATE FIRST (parent), then decides prerequisite/capacity/approval
-- under that lock -- the classic "counted without a lock" race this
-- repository has hit repeatedly elsewhere is structurally closed here from
-- the start (decision 3, taxonomy C-04).
create function app._enroll_employee_in_training_session_internal(p_session_id uuid, p_employee_id uuid, p_source text, p_actor_label text)
returns app.training_enrollments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_session app.training_sessions;
  v_version app.training_course_versions;
  v_enrolled_count integer;
  v_status text;
  v_row app.training_enrollments;
begin
  select * into v_session from app.training_sessions where id = p_session_id for update;
  if not found then
    raise exception 'training_session_not_found: %', p_session_id using errcode = 'no_data_found';
  end if;
  if v_session.status <> 'scheduled' then
    raise exception 'training_session_not_scheduled: session % is % not scheduled', p_session_id, v_session.status using errcode = 'check_violation';
  end if;
  if v_session.start_at <= now() then
    raise exception 'training_session_already_started: session % has already started', p_session_id using errcode = 'check_violation';
  end if;

  select * into v_version from app.training_course_versions where id = v_session.course_version_id;

  if not exists (select 1 from app.employees e where e.master_record_id = p_employee_id and e.tenant_id = v_session.tenant_id and e.lifecycle_status in ('active', 'on_leave')) then
    raise exception 'employee_not_active: employee % is not an active employee of tenant %', p_employee_id, v_session.tenant_id using errcode = 'check_violation';
  end if;
  if not app._training_prerequisites_met(v_session.tenant_id, p_employee_id, v_version.course_id) then
    raise exception 'training_prerequisite_not_met: employee % has not completed every prerequisite of course %', p_employee_id, v_version.course_id using errcode = 'check_violation';
  end if;

  select count(*) into v_enrolled_count from app.training_enrollments where session_id = p_session_id and status = 'enrolled';

  if v_version.requires_enrollment_approval then
    v_status := 'pending_approval';
  elsif v_enrolled_count < v_session.capacity then
    v_status := 'enrolled';
  else
    v_status := 'waitlisted';
  end if;

  begin
    insert into app.training_enrollments (tenant_id, session_id, employee_id, course_version_id, status, enrollment_source, enrolled_by)
    values (v_session.tenant_id, p_session_id, p_employee_id, v_session.course_version_id, v_status, p_source, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'training_enrollment_already_active: employee % already has an active enrollment for session %', p_employee_id, p_session_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_session.tenant_id, null, p_actor_label, 'enroll_in_training_session',
    'app.training_enrollments', v_row.id, 'success', null, null, jsonb_build_object('session_id', p_session_id, 'employee_id', p_employee_id, 'status', v_status, 'source', p_source)
  );

  return v_row;
end;
$$;

comment on function app._enroll_employee_in_training_session_internal is
  'HRT-284 (decision 3): the ONE enrollment write path -- app.enroll_self_in_training_session, app.enroll_employee_in_training_session, and app.bulk_assign_mandatory_training_session all delegate here after their own authority check, never duplicating the capacity/prerequisite logic.';

create function app.enroll_self_in_training_session(p_tenant_id uuid, p_session_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_enrollments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  -- Explicit, matching every sibling self-service RPC's established shape
  -- (HRT-282's own self-found ATW-032 fix): app.get_self_employee's own
  -- join alone is not credited as an authority check by the standing
  -- mechanical rbac-enforcement.sql sweep, live-caught before commit.
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    raise exception 'employee_not_found: identity % has no linked employee record in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  return app._enroll_employee_in_training_session_internal(p_session_id, v_self.master_record_id, 'self', p_actor_label);
end;
$$;

create function app.enroll_employee_in_training_session(p_tenant_id uuid, p_session_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_enrollments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_source text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if app.check_training_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    v_source := 'hr_assigned';
  else
    v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
    if v_self.master_record_id is null or not app._is_direct_manager_of_employee(p_employee_id, v_self.master_record_id) then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit and is not the direct manager of employee % in tenant %', p_actor_auth_user_id, p_employee_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    v_source := 'manager_assigned';
  end if;
  return app._enroll_employee_in_training_session_internal(p_session_id, p_employee_id, v_source, p_actor_label);
end;
$$;

comment on function app.enroll_employee_in_training_session is
  'HRT-284: HR (HRS:Edit) may assign ANY employee; a direct manager with no HRS:Edit may assign only their own direct report (mirrors the established manager-scope reuse, decision 3 of HRT-283/HRT-278-281). Never a client-supplied "which authority applies" flag.';

create function app.bulk_assign_mandatory_training_session(p_tenant_id uuid, p_session_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns table (assigned_count integer, skipped_count integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_session app.training_sessions;
  v_version app.training_course_versions;
  v_employee record;
  v_assigned integer := 0;
  v_skipped integer := 0;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_training_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  select * into v_session from app.training_sessions where id = p_session_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'training_session_not_found: %', p_session_id using errcode = 'no_data_found';
  end if;
  select * into v_version from app.training_course_versions where id = v_session.course_version_id;
  if not v_version.is_mandatory then
    raise exception 'training_session_not_mandatory: session %''s own course version is not marked mandatory', p_session_id using errcode = 'check_violation';
  end if;

  -- Bounded to currently active/on_leave employees, mirrors app.run_leave_
  -- accrual_batch's own identical scope (never an unbounded scan without a
  -- real predicate, section 17). Each employee''s own enrollment attempt is
  -- independently caught -- one employee''s prerequisite failure or
  -- already-active enrollment never aborts the whole batch (mirrors the
  -- leave accrual batch''s own per-employee exception-isolation shape).
  for v_employee in select * from app.employees where tenant_id = p_tenant_id and lifecycle_status in ('active', 'on_leave') loop
    begin
      perform app._enroll_employee_in_training_session_internal(p_session_id, v_employee.master_record_id, 'mandatory_assigned', p_actor_label);
      v_assigned := v_assigned + 1;
    exception
      when others then
        v_skipped := v_skipped + 1;
    end;
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'bulk_assign_mandatory_training_session',
    'app.training_sessions', p_session_id, 'success', null, null, jsonb_build_object('assigned_count', v_assigned, 'skipped_count', v_skipped)
  );

  assigned_count := v_assigned; skipped_count := v_skipped;
  return next;
end;
$$;

comment on function app.bulk_assign_mandatory_training_session is
  'HRT-284 (alternative flow, section 22 "mandatory compliance training"): a real, tested bulk-assignment batch, mirrors app.run_leave_accrual_batch''s own per-employee loop-with-isolated-exception shape (HRT-280) rather than a bare disclosure. Idempotent in effect: an employee already actively enrolled in this session is safely skipped (counted, never a hard failure), so re-running the same session is always safe.';

-- Approve/reject a pending_approval enrollment. Lock order: session
-- (parent) THEN the enrollment row (child) -- identical order to every
-- other function in this migration that touches both (decision 3,
-- taxonomy C-21). Structural self-decision block: the decider''s own
-- employee_id may never equal the enrollment''s own employee_id, even if
-- they separately hold HRS:Approve.
create function app.decide_training_enrollment(p_enrollment_id uuid, p_expected_version integer, p_decision text, p_decision_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_enrollments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_enrollment app.training_enrollments;
  v_session app.training_sessions;
  v_enrolled_count integer;
  v_self app.employees;
  v_status text;
begin
  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id;
  if not found then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.training_sessions where id = v_enrollment.session_id for update;

  if not app.check_training_authority('Approve', v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_self := app.get_self_employee(v_session.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_enrollment.employee_id then
    raise exception 'self_decision_not_permitted: an actor may not decide their own enrollment request' using errcode = 'insufficient_privilege';
  end if;
  if v_enrollment.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_enrollment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_enrollment.status <> 'pending_approval' then
    raise exception 'invalid_transition: enrollment % is % not pending_approval', p_enrollment_id, v_enrollment.status using errcode = 'check_violation';
  end if;
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: %', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'reject' and (p_decision_reason is null or length(trim(p_decision_reason)) = 0) then
    raise exception 'reason_required: a reason is required to reject an enrollment request' using errcode = 'check_violation';
  end if;

  if p_decision = 'reject' then
    update app.training_enrollments
    set status = 'cancelled', decided_by = p_actor_label, decided_at = now(), decision_reason = p_decision_reason, cancelled_reason = p_decision_reason, cancelled_at = now()
    where id = p_enrollment_id and record_version = p_expected_version
    returning * into v_enrollment;
  else
    select count(*) into v_enrolled_count from app.training_enrollments where session_id = v_session.id and status = 'enrolled';
    v_status := case when v_enrolled_count < v_session.capacity then 'enrolled' else 'waitlisted' end;
    update app.training_enrollments
    set status = v_status, decided_by = p_actor_label, decided_at = now(), decision_reason = p_decision_reason
    where id = p_enrollment_id and record_version = p_expected_version
    returning * into v_enrollment;
  end if;
  if not found then
    raise exception 'stale_version: concurrent update detected for enrollment %', p_enrollment_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_training_enrollment',
    'app.training_enrollments', v_enrollment.id, 'success', null, null, jsonb_build_object('decision', p_decision, 'status', v_enrollment.status)
  );

  return v_enrollment;
end;
$$;

-- Cancel + waitlist promotion. Lock order: session (parent) THEN
-- enrollment rows (children) -- identical order throughout (decision 3,
-- taxonomy C-21).
create function app.cancel_training_enrollment(p_enrollment_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_enrollments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_enrollment app.training_enrollments;
  v_session app.training_sessions;
  v_self app.employees;
  v_next_waitlisted app.training_enrollments;
  v_is_self boolean := false;
begin
  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id;
  if not found then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.training_sessions where id = v_enrollment.session_id for update;

  v_self := app.get_self_employee(v_session.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_enrollment.employee_id then
    v_is_self := true;
  end if;
  if not v_is_self and not app.check_training_authority('Edit', v_session.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is neither the enrolled employee nor an HRS:Edit holder for tenant %', p_actor_auth_user_id, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_enrollment.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_enrollment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_enrollment.status not in ('pending_approval', 'enrolled', 'waitlisted') then
    raise exception 'invalid_transition: enrollment % is % -- only an active enrollment may be cancelled', p_enrollment_id, v_enrollment.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to cancel an enrollment' using errcode = 'check_violation';
  end if;

  update app.training_enrollments set status = 'cancelled', cancelled_reason = p_reason, cancelled_at = now()
  where id = p_enrollment_id and record_version = p_expected_version
  returning * into v_enrollment;
  if not found then
    raise exception 'stale_version: concurrent update detected for enrollment %', p_enrollment_id using errcode = 'serialization_failure';
  end if;

  -- A capacity slot freed up -- promote the earliest waitlisted enrollee,
  -- still under the SAME session lock this function already holds.
  if v_enrollment.status = 'cancelled' then
    select * into v_next_waitlisted from app.training_enrollments
    where session_id = v_session.id and status = 'waitlisted'
    order by created_at asc
    limit 1
    for update;
    if found then
      update app.training_enrollments set status = 'enrolled' where id = v_next_waitlisted.id;
      perform app.capture_audit_event(
        v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'promote_training_enrollment_from_waitlist',
        'app.training_enrollments', v_next_waitlisted.id, 'success', null, null, jsonb_build_object('session_id', v_session.id)
      );
    end if;
  end if;

  perform app.capture_audit_event(
    v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_training_enrollment',
    'app.training_enrollments', v_enrollment.id, 'success', null, null, jsonb_build_object('session_id', v_session.id)
  );

  return v_enrollment;
end;
$$;

-- Reschedules an enrollment to a DIFFERENT session of the same or a
-- different course. Touches TWO sessions -- locked in ascending-id order
-- (never the caller-supplied old-then-new order) to avoid a deadlock
-- against a concurrent reverse-direction reschedule crossing the same two
-- sessions (taxonomy C-21, decision 3).
create function app.reschedule_training_enrollment(p_enrollment_id uuid, p_new_session_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_enrollments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_enrollment app.training_enrollments;
  v_old_session_id uuid;
  v_first_id uuid;
  v_second_id uuid;
  v_self app.employees;
  v_is_self boolean := false;
  v_new_enrollment app.training_enrollments;
begin
  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id;
  if not found then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;
  v_old_session_id := v_enrollment.session_id;
  if v_old_session_id = p_new_session_id then
    raise exception 'invalid_reschedule: new session must differ from the current session' using errcode = 'check_violation';
  end if;

  v_first_id := least(v_old_session_id, p_new_session_id);
  v_second_id := greatest(v_old_session_id, p_new_session_id);
  perform 1 from app.training_sessions where id = v_first_id for update;
  perform 1 from app.training_sessions where id = v_second_id for update;

  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id for update;

  v_self := app.get_self_employee((select tenant_id from app.training_sessions where id = v_old_session_id), p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_enrollment.employee_id then
    v_is_self := true;
  end if;
  if not v_is_self and not app.check_training_authority('Edit', v_enrollment.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is neither the enrolled employee nor an HRS:Edit holder for tenant %', p_actor_auth_user_id, v_enrollment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_enrollment.status not in ('pending_approval', 'enrolled', 'waitlisted') then
    raise exception 'invalid_transition: enrollment % is % -- only an active enrollment may be rescheduled', p_enrollment_id, v_enrollment.status using errcode = 'check_violation';
  end if;

  update app.training_enrollments set status = 'cancelled', cancelled_reason = 'rescheduled', cancelled_at = now()
  where id = p_enrollment_id;

  v_new_enrollment := app._enroll_employee_in_training_session_internal(p_new_session_id, v_enrollment.employee_id, v_enrollment.enrollment_source, p_actor_label);
  update app.training_enrollments set rescheduled_from_enrollment_id = p_enrollment_id where id = v_new_enrollment.id
  returning * into v_new_enrollment;

  perform app.capture_audit_event(
    v_enrollment.tenant_id, p_actor_auth_user_id, p_actor_label, 'reschedule_training_enrollment',
    'app.training_enrollments', v_new_enrollment.id, 'success', null, null, jsonb_build_object('old_enrollment_id', p_enrollment_id, 'old_session_id', v_old_session_id, 'new_session_id', p_new_session_id)
  );

  return v_new_enrollment;
end;
$$;

create function app.record_training_attendance(p_enrollment_id uuid, p_attended boolean, p_hours_attended numeric, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_enrollments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_enrollment app.training_enrollments;
begin
  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id for update;
  if not found then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_enrollment.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_enrollment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_enrollment.status <> 'enrolled' then
    raise exception 'invalid_transition: enrollment % is % not enrolled', p_enrollment_id, v_enrollment.status using errcode = 'check_violation';
  end if;
  if p_hours_attended is not null and p_hours_attended < 0 then
    raise exception 'invalid_hours: hours_attended must not be negative' using errcode = 'check_violation';
  end if;

  update app.training_enrollments
  set attended = p_attended, hours_attended = p_hours_attended, attendance_recorded_by = p_actor_label, attendance_recorded_at = now()
  where id = p_enrollment_id
  returning * into v_enrollment;

  perform app.capture_audit_event(
    v_enrollment.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_training_attendance',
    'app.training_enrollments', v_enrollment.id, 'success', null, null, jsonb_build_object('attended', p_attended)
  );

  return v_enrollment;
end;
$$;

create function app.record_training_completion(p_enrollment_id uuid, p_expected_version integer, p_completion_status text, p_notes text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_enrollments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_enrollment app.training_enrollments;
begin
  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id for update;
  if not found then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_enrollment.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_enrollment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_enrollment.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_enrollment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_enrollment.status <> 'enrolled' then
    raise exception 'invalid_transition: enrollment % is % not enrolled', p_enrollment_id, v_enrollment.status using errcode = 'check_violation';
  end if;
  if p_completion_status not in ('completed', 'failed', 'no_show') then
    raise exception 'invalid_completion_status: %', p_completion_status using errcode = 'check_violation';
  end if;

  update app.training_enrollments
  set status = p_completion_status, completion_notes = p_notes, completed_at = now(), completion_recorded_by = p_actor_label
  where id = p_enrollment_id and record_version = p_expected_version
  returning * into v_enrollment;
  if not found then
    raise exception 'stale_version: concurrent update detected for enrollment %', p_enrollment_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_enrollment.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_training_completion',
    'app.training_enrollments', v_enrollment.id, 'success', null, null, jsonb_build_object('status', p_completion_status)
  );

  return v_enrollment;
end;
$$;

create function app.list_training_enrollments(p_tenant_id uuid, p_actor_auth_user_id uuid, p_session_id uuid default null, p_employee_id uuid default null, p_status text default null)
returns table (
  id uuid, session_id uuid, session_code text, employee_id uuid, employee_full_name text, course_version_id uuid, course_code text, course_name text,
  status text, enrollment_source text, attended boolean, hours_attended numeric, record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select e.id, e.session_id, s.session_code, e.employee_id, emp.full_name, e.course_version_id, c.code, c.name,
    e.status, e.enrollment_source, e.attended, e.hours_attended, e.record_version
  from app.training_enrollments e
  join app.training_sessions s on s.id = e.session_id
  join app.training_course_versions cv on cv.id = e.course_version_id
  join app.training_courses c on c.id = cv.course_id
  join app.employees emp on emp.master_record_id = e.employee_id
  where e.tenant_id = p_tenant_id
    and app.can_view_hris_training_talent_row(p_tenant_id, e.employee_id, p_actor_auth_user_id)
    and (p_session_id is null or e.session_id = p_session_id)
    and (p_employee_id is null or e.employee_id = p_employee_id)
    and (p_status is null or e.status = p_status)
  order by e.created_at desc;
end;
$$;

create function app.list_my_training_enrollments(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text default null)
returns table (
  id uuid, session_id uuid, session_code text, course_version_id uuid, course_code text, course_name text, start_at timestamptz,
  status text, enrollment_source text, attended boolean, completion_notes text, record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;
  return query
  select e.id, e.session_id, s.session_code, e.course_version_id, c.code, c.name, s.start_at,
    e.status, e.enrollment_source, e.attended, e.completion_notes, e.record_version
  from app.training_enrollments e
  join app.training_sessions s on s.id = e.session_id
  join app.training_course_versions cv on cv.id = e.course_version_id
  join app.training_courses c on c.id = cv.course_id
  where e.tenant_id = p_tenant_id and e.employee_id = v_self.master_record_id and (p_status is null or e.status = p_status)
  order by s.start_at desc;
end;
$$;

-- ===========================================================================
-- 20. Assessment.
-- ===========================================================================

create function app.compute_training_assessment_passed(p_score numeric, p_max_score numeric, p_passing_score numeric)
returns boolean
language sql
immutable
as $$
  select case when p_passing_score is null then null else (p_score / p_max_score) * 100 >= p_passing_score end;
$$;

comment on function app.compute_training_assessment_passed is
  'HRT-284: deterministic, reproducible from visible inputs -- the course version''s own passing_score compared against this attempt''s score/max_score ratio. Returns null (unscored/no pass bar) only when the course version itself has no passing_score, which app.record_training_assessment rejects with training_assessment_requires_passing_score before ever calling this.';

create function app.record_training_assessment(p_enrollment_id uuid, p_score numeric, p_max_score numeric, p_notes text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_enrollment app.training_enrollments;
  v_version app.training_course_versions;
  v_next integer;
  v_row app.training_assessments;
begin
  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id;
  if not found then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_enrollment.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_enrollment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  select * into v_version from app.training_course_versions where id = v_enrollment.course_version_id;
  if not v_version.requires_assessment then
    raise exception 'training_assessment_not_applicable: course version % does not require assessment', v_enrollment.course_version_id using errcode = 'check_violation';
  end if;
  if p_score is null or p_score < 0 or p_max_score is null or p_max_score <= 0 or p_score > p_max_score then
    raise exception 'invalid_score: score must be between 0 and max_score' using errcode = 'check_violation';
  end if;

  select coalesce(max(attempt_number), 0) + 1 into v_next from app.training_assessments where enrollment_id = p_enrollment_id;

  begin
    insert into app.training_assessments (tenant_id, enrollment_id, employee_id, course_version_id, attempt_number, score, max_score, passed, assessed_by, notes)
    values (
      v_enrollment.tenant_id, p_enrollment_id, v_enrollment.employee_id, v_enrollment.course_version_id, v_next, p_score, p_max_score,
      app.compute_training_assessment_passed(p_score, p_max_score, v_version.passing_score), p_actor_label, p_notes
    )
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'training_assessment_attempt_conflict: an attempt was just recorded concurrently for enrollment % -- retry to get the current next attempt number', p_enrollment_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_enrollment.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_training_assessment',
    'app.training_assessments', v_row.id, 'success', null, null, jsonb_build_object('enrollment_id', p_enrollment_id, 'attempt_number', v_next, 'passed', v_row.passed)
  );

  return v_row;
end;
$$;

comment on function app.record_training_assessment is
  'HRT-284: append-only per attempt (attempt_number auto-increments, retries are legal -- test data requirement, section 27). score/notes are never copied into app.audit_logs (taxonomy C-24) -- only ids, attempt_number, and the boolean passed outcome.';

create function app.list_training_assessments(p_enrollment_id uuid, p_actor_auth_user_id uuid)
returns setof app.training_assessments
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_enrollment app.training_enrollments;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_enrollment from app.training_enrollments where id = p_enrollment_id;
  if not found then
    raise exception 'training_enrollment_not_found: %', p_enrollment_id using errcode = 'no_data_found';
  end if;
  if not app.can_view_hris_training_talent_row(v_enrollment.tenant_id, v_enrollment.employee_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not view assessments for employee %', p_actor_auth_user_id, v_enrollment.employee_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.training_assessments where enrollment_id = p_enrollment_id order by attempt_number desc;
end;
$$;

-- ===========================================================================
-- 21. Certificate (decision 4; section 13, 19, 20, 22).
-- ===========================================================================

create function app.issue_training_certificate(
  p_tenant_id uuid, p_employee_id uuid, p_course_version_id uuid, p_enrollment_id uuid, p_certificate_number text,
  p_issued_at date, p_expiry_date date, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.training_certificates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.training_course_versions;
  v_row app.training_certificates;
begin
  if not app.check_training_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from app.employees e where e.master_record_id = p_employee_id and e.tenant_id = p_tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;
  select * into v_version from app.training_course_versions where id = p_course_version_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'training_course_version_not_found: %', p_course_version_id using errcode = 'no_data_found';
  end if;
  if p_enrollment_id is not null and not exists (
    select 1 from app.training_enrollments e where e.id = p_enrollment_id and e.employee_id = p_employee_id and e.course_version_id = p_course_version_id
  ) then
    raise exception 'training_enrollment_not_found: enrollment % does not match employee %/course version %', p_enrollment_id, p_employee_id, p_course_version_id
      using errcode = 'no_data_found';
  end if;

  insert into app.training_certificates (
    tenant_id, employee_id, course_version_id, enrollment_id, certificate_number, issued_at, expiry_date, source, verification_status, created_by
  ) values (
    p_tenant_id, p_employee_id, p_course_version_id, p_enrollment_id, p_certificate_number, p_issued_at, p_expiry_date, 'internal_completion', 'verified', p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_training_certificate',
    'app.training_certificates', v_row.id, 'success', null, null, jsonb_build_object('employee_id', p_employee_id, 'course_version_id', p_course_version_id)
  );

  return v_row;
end;
$$;

create function app.import_historical_training_certificate(
  p_tenant_id uuid, p_employee_id uuid, p_external_course_name text, p_provider_id uuid, p_certificate_number text,
  p_issued_at date, p_expiry_date date, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.training_certificates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.training_certificates;
begin
  if not app.check_training_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from app.employees e where e.master_record_id = p_employee_id and e.tenant_id = p_tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;
  if p_external_course_name is null or length(trim(p_external_course_name)) = 0 then
    raise exception 'invalid_external_course_name: an external course name is required for an imported certificate' using errcode = 'check_violation';
  end if;

  insert into app.training_certificates (
    tenant_id, employee_id, external_course_name, provider_id, certificate_number, issued_at, expiry_date, source, verification_status, created_by
  ) values (
    p_tenant_id, p_employee_id, p_external_course_name, p_provider_id, p_certificate_number, p_issued_at, p_expiry_date, 'external_import', 'unverified', p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'import_historical_training_certificate',
    'app.training_certificates', v_row.id, 'success', null, null, jsonb_build_object('employee_id', p_employee_id, 'source', 'external_import')
  );

  return v_row;
end;
$$;

comment on function app.import_historical_training_certificate is
  'HRT-284 (section 19, data migration impact): historical evidence is source-labeled (source=external_import) and starts verification_status=unverified -- never inferred as competency/talent classification from an unverified import (business rule, section 19).';

-- Re-validates the file for tenant, record scope, and clean scan status AT
-- THIS accepting RPC -- taxonomy C-10, mirrors app.record_gps_device_
-- installation / every onboarding-task-evidence RPC's identical shape,
-- never trusted from the caller''s own upload-time classification.
create function app.attach_training_certificate_evidence(p_certificate_id uuid, p_expected_version integer, p_evidence_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_certificates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cert app.training_certificates;
  v_file app.files;
begin
  select * into v_cert from app.training_certificates where id = p_certificate_id for update;
  if not found then
    raise exception 'training_certificate_not_found: %', p_certificate_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_cert.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_cert.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cert.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_cert.record_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_file from app.files where id = p_evidence_file_id;
  if not found or v_file.tenant_id <> v_cert.tenant_id or v_file.record_type <> 'training_certificate' or v_file.record_id <> p_certificate_id then
    raise exception 'evidence_file_not_found: file % is not a valid evidence file for certificate %', p_evidence_file_id, p_certificate_id using errcode = 'no_data_found';
  end if;
  if v_file.malware_scan_status = 'infected' then
    raise exception 'evidence_file_infected: file % failed malware scanning and cannot be attached', p_evidence_file_id using errcode = 'check_violation';
  end if;
  if v_file.malware_scan_status <> 'clean' then
    raise exception 'evidence_file_not_scanned: file % has not cleared malware scanning (status %)', p_evidence_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;

  update app.training_certificates set evidence_file_id = p_evidence_file_id where id = p_certificate_id and record_version = p_expected_version
  returning * into v_cert;
  if not found then
    raise exception 'stale_version: concurrent update detected for certificate %', p_certificate_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cert.tenant_id, p_actor_auth_user_id, p_actor_label, 'attach_training_certificate_evidence',
    'app.training_certificates', v_cert.id, 'success', null, null, jsonb_build_object('evidence_file_id', p_evidence_file_id)
  );

  return v_cert;
end;
$$;

create function app.verify_training_certificate(p_certificate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_certificates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cert app.training_certificates;
begin
  select * into v_cert from app.training_certificates where id = p_certificate_id for update;
  if not found then
    raise exception 'training_certificate_not_found: %', p_certificate_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Approve', v_cert.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_cert.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cert.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_cert.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_cert.verification_status <> 'unverified' then
    raise exception 'invalid_transition: certificate % is already %', p_certificate_id, v_cert.verification_status using errcode = 'check_violation';
  end if;

  update app.training_certificates set verification_status = 'verified' where id = p_certificate_id and record_version = p_expected_version
  returning * into v_cert;
  if not found then
    raise exception 'stale_version: concurrent update detected for certificate %', p_certificate_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cert.tenant_id, p_actor_auth_user_id, p_actor_label, 'verify_training_certificate',
    'app.training_certificates', v_cert.id, 'success', null, null, jsonb_build_object('verification_status', 'verified')
  );

  return v_cert;
end;
$$;

create function app.revoke_training_certificate(p_certificate_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_certificates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cert app.training_certificates;
begin
  select * into v_cert from app.training_certificates where id = p_certificate_id for update;
  if not found then
    raise exception 'training_certificate_not_found: %', p_certificate_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_cert.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_cert.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cert.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_cert.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_cert.status = 'revoked' then
    raise exception 'invalid_transition: certificate % is already revoked', p_certificate_id using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to revoke a certificate' using errcode = 'check_violation';
  end if;

  update app.training_certificates set status = 'revoked', revoked_reason = p_reason, revoked_at = now(), revoked_by = p_actor_label
  where id = p_certificate_id and record_version = p_expected_version
  returning * into v_cert;
  if not found then
    raise exception 'stale_version: concurrent update detected for certificate %', p_certificate_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cert.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_training_certificate',
    'app.training_certificates', v_cert.id, 'success', null, null, jsonb_build_object('status', 'revoked')
  );

  return v_cert;
end;
$$;

create function app.renew_training_certificate(
  p_old_certificate_id uuid, p_certificate_number text, p_issued_at date, p_expiry_date date, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.training_certificates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_old app.training_certificates;
  v_row app.training_certificates;
begin
  select * into v_old from app.training_certificates where id = p_old_certificate_id;
  if not found then
    raise exception 'training_certificate_not_found: %', p_old_certificate_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.training_certificates (
    tenant_id, employee_id, course_version_id, external_course_name, provider_id, certificate_number, issued_at, expiry_date,
    source, verification_status, renewed_from_certificate_id, created_by
  ) values (
    v_old.tenant_id, v_old.employee_id, v_old.course_version_id, v_old.external_course_name, v_old.provider_id, p_certificate_number, p_issued_at, p_expiry_date,
    v_old.source, v_old.verification_status, p_old_certificate_id, p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    v_old.tenant_id, p_actor_auth_user_id, p_actor_label, 'renew_training_certificate',
    'app.training_certificates', v_row.id, 'success', null, null, jsonb_build_object('renewed_from_certificate_id', p_old_certificate_id)
  );

  return v_row;
end;
$$;

comment on function app.renew_training_certificate is
  'HRT-284 (alternative flow, section 22 "certificate renewal"): a NEW certificate row referencing the old one via renewed_from_certificate_id -- the old row is never mutated (still ages into status=expired naturally via app.run_training_certificate_expiry_batch, exactly like every other lineage-preserving pattern this repository uses -- HRT-282 decision 11''s "finalized run history never recalculates in place").';

create function app.list_training_certificates(p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid default null)
returns table (
  id uuid, employee_id uuid, employee_full_name text, course_version_id uuid, course_code text, course_name text, external_course_name text,
  certificate_number text, issued_at date, expiry_date date, status text, source text, verification_status text, evidence_file_id uuid,
  renewed_from_certificate_id uuid, record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select t.id, t.employee_id, e.full_name, t.course_version_id, c.code, c.name, t.external_course_name,
    t.certificate_number, t.issued_at, t.expiry_date, t.status, t.source, t.verification_status, t.evidence_file_id,
    t.renewed_from_certificate_id, t.record_version
  from app.training_certificates t
  join app.employees e on e.master_record_id = t.employee_id
  left join app.training_course_versions cv on cv.id = t.course_version_id
  left join app.training_courses c on c.id = cv.course_id
  where t.tenant_id = p_tenant_id
    and app.can_view_hris_training_talent_row(p_tenant_id, t.employee_id, p_actor_auth_user_id)
    and (p_employee_id is null or t.employee_id = p_employee_id)
  order by t.issued_at desc;
end;
$$;

create function app.list_my_training_certificates(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, course_version_id uuid, course_code text, course_name text, external_course_name text, certificate_number text,
  issued_at date, expiry_date date, status text, source text, verification_status text, evidence_file_id uuid, record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;
  return query
  select t.id, t.course_version_id, c.code, c.name, t.external_course_name, t.certificate_number,
    t.issued_at, t.expiry_date, t.status, t.source, t.verification_status, t.evidence_file_id, t.record_version
  from app.training_certificates t
  left join app.training_course_versions cv on cv.id = t.course_version_id
  left join app.training_courses c on c.id = cv.course_id
  where t.tenant_id = p_tenant_id and t.employee_id = v_self.master_record_id
  order by t.issued_at desc;
end;
$$;

create function app.get_training_certificate(p_certificate_id uuid, p_actor_auth_user_id uuid)
returns app.training_certificates
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_cert app.training_certificates;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_cert from app.training_certificates where id = p_certificate_id;
  if not found then
    raise exception 'training_certificate_not_found: %', p_certificate_id using errcode = 'no_data_found';
  end if;
  if not app.can_view_hris_training_talent_row(v_cert.tenant_id, v_cert.employee_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not view certificate %', p_actor_auth_user_id, p_certificate_id
      using errcode = 'insufficient_privilege';
  end if;
  return v_cert;
end;
$$;

-- ===========================================================================
-- 22. Certificate expiry / reminder durable jobs (decision 5). Widens
--     app.jobs.job_type''s CHECK constraint and app.generic_job_types()
--     TOGETHER, in this same migration, exactly as every prior HRIS-domain
--     adopter did -- kept set-equal by the standing ATW-031 drift gate
--     (scripts/db-tests/background-job.sql, unchanged, self-checking).
-- ===========================================================================

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'HRT-284 (decision 5): widened to add ''training_certificate_expiry''/''training_certificate_expiry_reminder'' -- the fifth HRIS-domain adopter of PLT-132''s own generic job_type list, after HRT-282''s ''payroll_calculation''. Kept set-equal with app.generic_job_types() by scripts/db-tests/background-job.sql''s own standing ATW-031 drift-gate assertion.';

create or replace function app.generic_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder'
  ]::text[];
$$;

comment on function app.generic_job_types is
  'ATW-031 (ISS-2026-012), widened by HRT-284 to add ''training_certificate_expiry''/''training_certificate_expiry_reminder''. The single authority for which job_type values the GENERIC queue mechanics accept -- app.enqueue_job and app.dispatch_event_as_job both already call this function directly, unchanged by this migration.';

-- Transitions any 'issued' certificate past its own expiry_date to
-- status=expired. A plain, idempotent UPDATE (running it twice for the
-- same as_of_date is a safe no-op -- the second run's WHERE clause matches
-- zero rows) -- no exception handler needed, unlike an INSERT-based ledger
-- (mirrors app.run_leave_carry_forward_batch's shape, decision 5).
create function app.run_training_certificate_expiry_batch(p_tenant_id uuid, p_as_of_date date, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns table (expired_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_worker_id text;
  v_expired integer := 0;
begin
  if not app.check_training_authority('Override', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_as_of_date is null or p_period_label is null or length(trim(p_period_label)) = 0 then
    raise exception 'invalid_period: p_as_of_date and a non-empty p_period_label are required' using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'training_certificate_expiry', jsonb_build_object('as_of_date', p_as_of_date, 'period_label', p_period_label),
    0, 'training_certificate_expiry:' || p_period_label, 1, p_actor_auth_user_id, p_actor_label
  );

  -- Only claim/process/complete a genuinely FRESH pending job -- a replay
  -- of an already-processed period is a real, safe no-op (mirrors HRT-280's
  -- own self-found, live-caught lesson on app.run_leave_accrual_batch).
  if v_job.status = 'pending' then
    v_worker_id := 'inline-training-cert-expiry:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    update app.training_certificates
    set status = 'expired'
    where tenant_id = p_tenant_id and status = 'issued' and expiry_date is not null and expiry_date < p_as_of_date;
    get diagnostics v_expired = row_count;

    perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_training_certificate_expiry_batch',
      'app.jobs', v_job.job_id, 'success', null, null, jsonb_build_object('period_label', p_period_label, 'expired_count', v_expired)
    );
  end if;

  expired_count := v_expired; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.run_training_certificate_expiry_batch is
  'HRT-284 (decision 5): a real app.jobs row tracked through the actual PLT-132 lifecycle (enqueue -> self-claim -> complete), mirrors app.run_leave_carry_forward_batch (HRT-280) exactly. Idempotent per period_label.';

-- Scans for certificates expiring within a lookahead window and records a
-- real, queryable reminder row -- idempotent per (certificate_id,
-- period_label) via the table's own unique constraint + exception handler
-- (decision 5, disclosed limitation: no live notification dispatch,
-- decision 11).
create function app.run_training_certificate_expiry_reminder_batch(p_tenant_id uuid, p_as_of_date date, p_lookahead_days integer, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns table (reminded_count integer, skipped_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_worker_id text;
  v_cert record;
  v_reminded integer := 0;
  v_skipped integer := 0;
begin
  if not app.check_training_authority('Override', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_as_of_date is null or p_period_label is null or length(trim(p_period_label)) = 0 then
    raise exception 'invalid_period: p_as_of_date and a non-empty p_period_label are required' using errcode = 'check_violation';
  end if;
  if coalesce(p_lookahead_days, 0) <= 0 then
    raise exception 'invalid_lookahead: p_lookahead_days must be positive' using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'training_certificate_expiry_reminder', jsonb_build_object('as_of_date', p_as_of_date, 'lookahead_days', p_lookahead_days, 'period_label', p_period_label),
    0, 'training_certificate_expiry_reminder:' || p_period_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-training-cert-reminder:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    for v_cert in
      select * from app.training_certificates
      where tenant_id = p_tenant_id and status = 'issued' and expiry_date is not null
        and expiry_date >= p_as_of_date and expiry_date <= p_as_of_date + p_lookahead_days
    loop
      begin
        insert into app.training_certificate_expiry_reminders (tenant_id, certificate_id, employee_id, period_label, days_until_expiry, job_id)
        values (p_tenant_id, v_cert.id, v_cert.employee_id, p_period_label, (v_cert.expiry_date - p_as_of_date), v_job.job_id);
        v_reminded := v_reminded + 1;
      exception
        when unique_violation then
          -- Already reminded for this (certificate, period) -- the table's
          -- own unique constraint is the real re-run safety net.
          v_skipped := v_skipped + 1;
      end;
    end loop;

    perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_training_certificate_expiry_reminder_batch',
      'app.jobs', v_job.job_id, 'success', null, null, jsonb_build_object('period_label', p_period_label, 'reminded_count', v_reminded, 'skipped_count', v_skipped)
    );
  end if;

  reminded_count := v_reminded; skipped_count := v_skipped; job_id := v_job.job_id;
  return next;
end;
$$;

create function app.list_training_certificate_expiry_reminders(p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid default null)
returns setof app.training_certificate_expiry_reminders
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select r.* from app.training_certificate_expiry_reminders r
  where r.tenant_id = p_tenant_id
    and app.can_view_hris_training_talent_row(p_tenant_id, r.employee_id, p_actor_auth_user_id)
    and (p_employee_id is null or r.employee_id = p_employee_id)
  order by r.reminded_at desc;
end;
$$;

-- ===========================================================================
-- 23. Development plan (section 13, 20). Reuses the direct-manager-only
--     "effective team" scope, decision 3 of HRT-283, reused verbatim.
-- ===========================================================================

create function app.create_training_development_plan(p_tenant_id uuid, p_employee_id uuid, p_title text, p_cycle_label text, p_linked_performance_outcome_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_development_plans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
  v_row app.training_development_plans;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not exists (select 1 from app.employees e where e.master_record_id = p_employee_id and e.tenant_id = p_tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
    if v_self.master_record_id is null or not app._is_direct_manager_of_employee(p_employee_id, v_self.master_record_id) then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit and is not the direct manager of employee % in tenant %', p_actor_auth_user_id, p_employee_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  if p_linked_performance_outcome_id is not null and not exists (
    select 1 from app.performance_outcomes o where o.id = p_linked_performance_outcome_id and o.tenant_id = p_tenant_id and o.employee_id = p_employee_id
  ) then
    raise exception 'performance_outcome_not_found: outcome % does not belong to employee %', p_linked_performance_outcome_id, p_employee_id using errcode = 'no_data_found';
  end if;

  insert into app.training_development_plans (tenant_id, employee_id, title, cycle_label, linked_performance_outcome_id, created_by)
  values (p_tenant_id, p_employee_id, p_title, p_cycle_label, p_linked_performance_outcome_id, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_training_development_plan',
    'app.training_development_plans', v_row.id, 'success', null, null, jsonb_build_object('employee_id', p_employee_id)
  );

  return v_row;
end;
$$;

comment on function app.create_training_development_plan is
  'HRT-284 (section 20 "bind employee/position/KPI evidence"): linked_performance_outcome_id, when supplied, must genuinely belong to the SAME employee -- re-validated server-side, never trusted from the caller. HRS:Edit OR the employee''s own direct manager may author a plan (reuses HRT-283 decision 3''s established manager-scope shape verbatim).';

create function app.transition_training_development_plan_status(p_plan_id uuid, p_expected_version integer, p_target_status text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_development_plans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_plan app.training_development_plans;
  v_self app.employees;
  v_legal boolean;
begin
  select * into v_plan from app.training_development_plans where id = p_plan_id for update;
  if not found then
    raise exception 'training_development_plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_plan.tenant_id, p_actor_auth_user_id) then
    v_self := app.get_self_employee(v_plan.tenant_id, p_actor_auth_user_id);
    if v_self.master_record_id is null or not app._is_direct_manager_of_employee(v_plan.employee_id, v_self.master_record_id) then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit and is not the direct manager of employee % in tenant %', p_actor_auth_user_id, v_plan.employee_id, v_plan.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  if v_plan.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_plan.record_version
      using errcode = 'serialization_failure';
  end if;

  v_legal := case v_plan.status
    when 'draft' then p_target_status in ('active', 'cancelled')
    when 'active' then p_target_status in ('completed', 'cancelled')
    else false
  end;
  if not v_legal then
    raise exception 'invalid_transition: plan % cannot move from % to %', p_plan_id, v_plan.status, p_target_status using errcode = 'check_violation';
  end if;
  if p_target_status = 'cancelled' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a reason is required to cancel a development plan' using errcode = 'check_violation';
  end if;

  update app.training_development_plans set status = p_target_status, cancel_reason = case when p_target_status = 'cancelled' then p_reason else cancel_reason end
  where id = p_plan_id and record_version = p_expected_version
  returning * into v_plan;
  if not found then
    raise exception 'stale_version: concurrent update detected for plan %', p_plan_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_training_development_plan_status',
    'app.training_development_plans', v_plan.id, 'success', null, null, jsonb_build_object('status', v_plan.status)
  );

  return v_plan;
end;
$$;

create function app.add_training_development_plan_action(p_plan_id uuid, p_action_type text, p_description text, p_linked_course_id uuid, p_target_date date, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_development_plan_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_plan app.training_development_plans;
  v_self app.employees;
  v_row app.training_development_plan_actions;
begin
  select * into v_plan from app.training_development_plans where id = p_plan_id;
  if not found then
    raise exception 'training_development_plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_plan.tenant_id, p_actor_auth_user_id) then
    v_self := app.get_self_employee(v_plan.tenant_id, p_actor_auth_user_id);
    if v_self.master_record_id is null or not app._is_direct_manager_of_employee(v_plan.employee_id, v_self.master_record_id) then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit and is not the direct manager of employee % in tenant %', p_actor_auth_user_id, v_plan.employee_id, v_plan.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  if v_plan.status not in ('draft', 'active') then
    raise exception 'invalid_plan_status: plan % is % -- actions may only be added while draft or active', p_plan_id, v_plan.status using errcode = 'check_violation';
  end if;
  if p_action_type not in ('training', 'coaching', 'stretch_assignment', 'certification', 'other') then
    raise exception 'invalid_action_type: %', p_action_type using errcode = 'check_violation';
  end if;
  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'description_required: a description is required for a development plan action' using errcode = 'check_violation';
  end if;
  if p_linked_course_id is not null and not exists (select 1 from app.training_courses c where c.id = p_linked_course_id and c.tenant_id = v_plan.tenant_id) then
    raise exception 'training_course_not_found: %', p_linked_course_id using errcode = 'no_data_found';
  end if;

  insert into app.training_development_plan_actions (tenant_id, plan_id, action_type, description, linked_course_id, target_date, created_by)
  values (v_plan.tenant_id, p_plan_id, p_action_type, p_description, p_linked_course_id, p_target_date, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_training_development_plan_action',
    'app.training_development_plan_actions', v_row.id, 'success', null, null, jsonb_build_object('plan_id', p_plan_id, 'action_type', p_action_type)
  );

  return v_row;
end;
$$;

create function app.update_training_development_plan_action_status(p_action_id uuid, p_expected_version integer, p_status text, p_completed_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_development_plan_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_action app.training_development_plan_actions;
  v_plan app.training_development_plans;
  v_self app.employees;
begin
  select * into v_action from app.training_development_plan_actions where id = p_action_id for update;
  if not found then
    raise exception 'training_development_plan_action_not_found: %', p_action_id using errcode = 'no_data_found';
  end if;
  select * into v_plan from app.training_development_plans where id = v_action.plan_id;
  if not app.check_training_authority('Edit', v_action.tenant_id, p_actor_auth_user_id) then
    v_self := app.get_self_employee(v_action.tenant_id, p_actor_auth_user_id);
    if v_self.master_record_id is null or (v_self.master_record_id <> v_plan.employee_id and not app._is_direct_manager_of_employee(v_plan.employee_id, v_self.master_record_id)) then
      raise exception 'insufficient_authority: identity % lacks HRS:Edit and is neither employee % nor their direct manager', p_actor_auth_user_id, v_plan.employee_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  if v_action.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_action.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_status not in ('planned', 'in_progress', 'completed', 'cancelled') then
    raise exception 'invalid_status: %', p_status using errcode = 'check_violation';
  end if;

  update app.training_development_plan_actions
  set status = p_status, completed_note = coalesce(p_completed_note, completed_note), completed_at = case when p_status = 'completed' then now() else completed_at end
  where id = p_action_id and record_version = p_expected_version
  returning * into v_action;
  if not found then
    raise exception 'stale_version: concurrent update detected for action %', p_action_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_action.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_training_development_plan_action_status',
    'app.training_development_plan_actions', v_action.id, 'success', null, null, jsonb_build_object('status', p_status)
  );

  return v_action;
end;
$$;

comment on function app.update_training_development_plan_action_status is
  'HRT-284: HRS:Edit, the plan''s own employee (self-service progress updates), or the employee''s direct manager may update an action''s status -- a genuinely three-way authority check, unlike every other write in this migration.';

create function app.list_training_development_plans(p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid default null)
returns table (id uuid, employee_id uuid, employee_full_name text, title text, cycle_label text, status text, linked_performance_outcome_id uuid, record_version integer)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select p.id, p.employee_id, e.full_name, p.title, p.cycle_label, p.status, p.linked_performance_outcome_id, p.record_version
  from app.training_development_plans p
  join app.employees e on e.master_record_id = p.employee_id
  where p.tenant_id = p_tenant_id
    and app.can_view_hris_training_talent_row(p_tenant_id, p.employee_id, p_actor_auth_user_id)
    and (p_employee_id is null or p.employee_id = p_employee_id)
  order by p.created_at desc;
end;
$$;

create function app.list_my_training_development_plans(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.training_development_plans
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;
  return query select * from app.training_development_plans where tenant_id = p_tenant_id and employee_id = v_self.master_record_id order by created_at desc;
end;
$$;

create function app.list_training_development_plan_actions(p_plan_id uuid, p_actor_auth_user_id uuid)
returns setof app.training_development_plan_actions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_plan app.training_development_plans;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_plan from app.training_development_plans where id = p_plan_id;
  if not found then
    raise exception 'training_development_plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;
  if not app.can_view_hris_training_talent_row(v_plan.tenant_id, v_plan.employee_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not view plan %', p_actor_auth_user_id, p_plan_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.training_development_plan_actions where plan_id = p_plan_id order by created_at;
end;
$$;

-- ===========================================================================
-- 24. Talent review cycle / assignment / review (decision 6, 7, 9;
--     section 13, 20, 26).
-- ===========================================================================

create function app.create_talent_review_cycle(p_tenant_id uuid, p_name text, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.talent_review_cycles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.talent_review_cycles;
begin
  if not app.check_training_authority('Override', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app.talent_review_cycles where tenant_id = p_tenant_id and name = p_name;
  if found then
    return v_row;
  end if;

  begin
    insert into app.talent_review_cycles (tenant_id, name, period_label, created_by)
    values (p_tenant_id, p_name, p_period_label, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'talent_review_cycle_name_conflict: a cycle named % was just created concurrently for tenant %', p_name, p_tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_talent_review_cycle',
    'app.talent_review_cycles', v_row.id, 'success', null, null, jsonb_build_object('name', p_name)
  );

  return v_row;
end;
$$;

create function app.transition_talent_review_cycle_status(p_cycle_id uuid, p_expected_version integer, p_target_status text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.talent_review_cycles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cycle app.talent_review_cycles;
  v_legal boolean;
begin
  select * into v_cycle from app.talent_review_cycles where id = p_cycle_id for update;
  if not found then
    raise exception 'talent_review_cycle_not_found: %', p_cycle_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_cycle.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cycle.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_cycle.record_version
      using errcode = 'serialization_failure';
  end if;

  v_legal := case v_cycle.status when 'draft' then p_target_status = 'active' when 'active' then p_target_status = 'closed' else false end;
  if not v_legal then
    raise exception 'invalid_transition: cycle % cannot move from % to %', p_cycle_id, v_cycle.status, p_target_status using errcode = 'check_violation';
  end if;

  update app.talent_review_cycles set status = p_target_status where id = p_cycle_id and record_version = p_expected_version
  returning * into v_cycle;
  if not found then
    raise exception 'stale_version: concurrent update detected for cycle %', p_cycle_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_talent_review_cycle_status',
    'app.talent_review_cycles', v_cycle.id, 'success', null, null, jsonb_build_object('status', v_cycle.status)
  );

  return v_cycle;
end;
$$;

create function app.list_talent_review_cycles(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.talent_review_cycles
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  -- Intentionally NOT gated on HRS:Override here -- RLS (decision 6) is
  -- the real restriction: a caller with neither HRS:Override nor an
  -- active assignment in a given cycle simply gets zero rows for that
  -- cycle, exactly like every other RLS-scoped list RPC in this
  -- migration. An HRS:Override check here would be redundant with RLS,
  -- never a widening -- assigned reviewers with zero HRS:Override must
  -- still see their own cycle's row.
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.talent_review_cycles where tenant_id = p_tenant_id order by created_at desc;
end;
$$;

comment on function app.list_talent_review_cycles is
  'HRT-284 (decision 6): relies entirely on talent_review_cycles_select_scoped RLS for the real restriction -- an HRS:Override holder sees every cycle, an assigned reviewer sees only cycles carrying their own active assignment, everyone else sees zero rows.';

-- Creates the assignment AND a fresh draft app.talent_reviews row in one
-- call (a simple 1:1 shape, unlike HRT-283's separate _ensure_* helper,
-- since talent review has no auto-triggered "first goal assignment"
-- moment to hang the creation off of -- HR always creates it explicitly).
create function app.assign_talent_reviewer(p_cycle_id uuid, p_subject_employee_id uuid, p_reviewer_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.talent_review_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_cycle app.talent_review_cycles;
  v_row app.talent_review_assignments;
begin
  select * into v_cycle from app.talent_review_cycles where id = p_cycle_id;
  if not found then
    raise exception 'talent_review_cycle_not_found: %', p_cycle_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_cycle.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_cycle.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_cycle.status = 'closed' then
    raise exception 'talent_review_cycle_closed: cycle % is closed', p_cycle_id using errcode = 'check_violation';
  end if;
  if p_reviewer_employee_id = p_subject_employee_id then
    raise exception 'invalid_assignee: a reviewer may not be assigned to their own case' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.employees e where e.master_record_id = p_subject_employee_id and e.tenant_id = v_cycle.tenant_id) then
    raise exception 'employee_not_found: %', p_subject_employee_id using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.employees e where e.master_record_id = p_reviewer_employee_id and e.tenant_id = v_cycle.tenant_id) then
    raise exception 'employee_not_found: %', p_reviewer_employee_id using errcode = 'no_data_found';
  end if;

  begin
    insert into app.talent_review_assignments (tenant_id, cycle_id, subject_employee_id, reviewer_employee_id, assigned_by)
    values (v_cycle.tenant_id, p_cycle_id, p_subject_employee_id, p_reviewer_employee_id, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'talent_review_assignment_conflict: subject % already has an active reviewer assignment in cycle %', p_subject_employee_id, p_cycle_id
        using errcode = 'check_violation';
  end;

  insert into app.talent_reviews (tenant_id, cycle_id, subject_employee_id, assignment_id)
  values (v_cycle.tenant_id, p_cycle_id, p_subject_employee_id, v_row.id);

  perform app.capture_audit_event(
    v_cycle.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_talent_reviewer',
    'app.talent_review_assignments', v_row.id, 'success', null, null, jsonb_build_object('cycle_id', p_cycle_id, 'subject_employee_id', p_subject_employee_id)
  );

  return v_row;
end;
$$;

-- Mirrors app.reassign_performance_reviewer_assignment (HRT-283) exactly:
-- the OLD assignment and any already-submitted review tied to it are
-- NEVER mutated or deleted, only marked reassigned; a BRAND NEW assignment
-- + fresh draft review is created for the new reviewer.
create function app.reassign_talent_reviewer(p_assignment_id uuid, p_new_reviewer_employee_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.talent_review_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_old app.talent_review_assignments;
  v_new app.talent_review_assignments;
begin
  select * into v_old from app.talent_review_assignments where id = p_assignment_id for update;
  if not found then
    raise exception 'talent_review_assignment_not_found: %', p_assignment_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_old.status <> 'active' then
    raise exception 'invalid_transition: assignment % is % not active', p_assignment_id, v_old.status using errcode = 'check_violation';
  end if;
  if p_new_reviewer_employee_id = v_old.subject_employee_id then
    raise exception 'invalid_assignee: a reviewer may not be assigned to their own case' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to reassign a talent reviewer' using errcode = 'check_violation';
  end if;

  update app.talent_review_assignments set status = 'reassigned', reassign_reason = p_reason where id = p_assignment_id;

  insert into app.talent_review_assignments (tenant_id, cycle_id, subject_employee_id, reviewer_employee_id, reassigned_from_assignment_id, assigned_by)
  values (v_old.tenant_id, v_old.cycle_id, v_old.subject_employee_id, p_new_reviewer_employee_id, p_assignment_id, p_actor_label)
  returning * into v_new;

  insert into app.talent_reviews (tenant_id, cycle_id, subject_employee_id, assignment_id)
  values (v_old.tenant_id, v_old.cycle_id, v_old.subject_employee_id, v_new.id);

  perform app.capture_audit_event(
    v_old.tenant_id, p_actor_auth_user_id, p_actor_label, 'reassign_talent_reviewer',
    'app.talent_review_assignments', v_new.id, 'success', null, null, jsonb_build_object('old_assignment_id', p_assignment_id, 'subject_employee_id', v_old.subject_employee_id)
  );

  return v_new;
end;
$$;

create function app.submit_talent_review(p_review_id uuid, p_expected_version integer, p_potential_rating text, p_readiness_note text, p_risk_of_loss text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.talent_reviews
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_review app.talent_reviews;
  v_assignment app.talent_review_assignments;
  v_self app.employees;
begin
  select * into v_review from app.talent_reviews where id = p_review_id for update;
  if not found then
    raise exception 'talent_review_not_found: %', p_review_id using errcode = 'no_data_found';
  end if;
  select * into v_assignment from app.talent_review_assignments where id = v_review.assignment_id;

  v_self := app.get_self_employee(v_review.tenant_id, p_actor_auth_user_id);
  if not app.check_training_authority('Override', v_review.tenant_id, p_actor_auth_user_id)
    and (v_self.master_record_id is null or v_self.master_record_id <> v_assignment.reviewer_employee_id) then
    raise exception 'insufficient_authority: identity % is neither the assigned reviewer nor an HRS:Override holder', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_review.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_review.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_review.status <> 'draft' then
    raise exception 'invalid_transition: review % is % not draft', p_review_id, v_review.status using errcode = 'check_violation';
  end if;
  if p_potential_rating not in ('low', 'moderate', 'high') then
    raise exception 'invalid_potential_rating: %', p_potential_rating using errcode = 'check_violation';
  end if;
  if p_risk_of_loss is not null and p_risk_of_loss not in ('low', 'medium', 'high') then
    raise exception 'invalid_risk_of_loss: %', p_risk_of_loss using errcode = 'check_violation';
  end if;

  update app.talent_reviews
  set potential_rating = p_potential_rating, readiness_note = p_readiness_note, risk_of_loss = p_risk_of_loss,
      status = 'submitted', submitted_by = p_actor_label, submitted_at = now()
  where id = p_review_id and record_version = p_expected_version
  returning * into v_review;
  if not found then
    raise exception 'stale_version: concurrent update detected for review %', p_review_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_review.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_talent_review',
    'app.talent_reviews', v_review.id, 'success', null, null, jsonb_build_object('cycle_id', v_review.cycle_id, 'subject_employee_id', v_review.subject_employee_id)
  );

  return v_review;
end;
$$;

comment on function app.submit_talent_review is
  'HRT-284 (decision 6, taxonomy C-24): potential_rating/readiness_note/risk_of_loss are NEVER copied into app.audit_logs -- only ids and the cycle/subject reference. Gated on being the assignment''s own reviewer_employee_id OR HRS:Override (an admin override capability, never a bypass of the assignment concept itself).';

create function app.list_talent_review_assignments(p_tenant_id uuid, p_actor_auth_user_id uuid, p_cycle_id uuid default null)
returns table (
  id uuid, cycle_id uuid, subject_employee_id uuid, subject_full_name text, reviewer_employee_id uuid, reviewer_full_name text, status text, record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_is_admin boolean;
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_is_admin := app.check_training_authority('Override', p_tenant_id, p_actor_auth_user_id);
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);

  return query
  select a.id, a.cycle_id, a.subject_employee_id, se.full_name, a.reviewer_employee_id, re.full_name, a.status, a.record_version
  from app.talent_review_assignments a
  join app.employees se on se.master_record_id = a.subject_employee_id
  join app.employees re on re.master_record_id = a.reviewer_employee_id
  where a.tenant_id = p_tenant_id
    and (p_cycle_id is null or a.cycle_id = p_cycle_id)
    and (v_is_admin or (v_self.master_record_id is not null and v_self.master_record_id = a.reviewer_employee_id))
  order by a.created_at desc;
end;
$$;

create function app.list_my_talent_review_assignments(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, cycle_id uuid, cycle_name text, subject_employee_id uuid, subject_full_name text, status text, review_id uuid, review_status text)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;
  return query
  select a.id, a.cycle_id, c.name, a.subject_employee_id, se.full_name, a.status, r.id, r.status
  from app.talent_review_assignments a
  join app.talent_review_cycles c on c.id = a.cycle_id
  join app.employees se on se.master_record_id = a.subject_employee_id
  left join app.talent_reviews r on r.assignment_id = a.id
  where a.tenant_id = p_tenant_id and a.reviewer_employee_id = v_self.master_record_id and a.status = 'active'
  order by a.created_at desc;
end;
$$;

create function app.get_talent_review(p_review_id uuid, p_actor_auth_user_id uuid)
returns app.talent_reviews
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_review app.talent_reviews;
  v_assignment app.talent_review_assignments;
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_review from app.talent_reviews where id = p_review_id;
  if not found then
    raise exception 'talent_review_not_found: %', p_review_id using errcode = 'no_data_found';
  end if;
  select * into v_assignment from app.talent_review_assignments where id = v_review.assignment_id;
  v_self := app.get_self_employee(v_review.tenant_id, p_actor_auth_user_id);
  if not app.check_training_authority('Override', v_review.tenant_id, p_actor_auth_user_id)
    and (v_self.master_record_id is null or v_self.master_record_id <> v_assignment.reviewer_employee_id) then
    raise exception 'insufficient_authority: identity % may not view review %', p_actor_auth_user_id, p_review_id
      using errcode = 'insufficient_privilege';
  end if;
  return v_review;
end;
$$;

-- ===========================================================================
-- 25. Talent pool (decision 6; section 13, 20).
-- ===========================================================================

create function app.create_talent_pool(p_tenant_id uuid, p_name text, p_description text, p_pool_type text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.talent_pools
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.talent_pools;
begin
  if not app.check_training_authority('Override', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_pool_type not in ('successor', 'high_potential', 'critical_role') then
    raise exception 'invalid_pool_type: %', p_pool_type using errcode = 'check_violation';
  end if;

  select * into v_row from app.talent_pools where tenant_id = p_tenant_id and name = p_name;
  if found then
    return v_row;
  end if;

  begin
    insert into app.talent_pools (tenant_id, name, description, pool_type, created_by)
    values (p_tenant_id, p_name, p_description, p_pool_type, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'talent_pool_name_conflict: a pool named % was just created concurrently for tenant %', p_name, p_tenant_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_talent_pool',
    'app.talent_pools', v_row.id, 'success', null, null, jsonb_build_object('name', p_name, 'pool_type', p_pool_type)
  );

  return v_row;
end;
$$;

create function app.archive_talent_pool(p_pool_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.talent_pools
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.talent_pools;
begin
  select * into v_row from app.talent_pools where id = p_pool_id for update;
  if not found then
    raise exception 'talent_pool_not_found: %', p_pool_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status = 'archived' then
    raise exception 'invalid_transition: pool % is already archived', p_pool_id using errcode = 'check_violation';
  end if;

  update app.talent_pools set status = 'archived' where id = p_pool_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: concurrent update detected for pool %', p_pool_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_talent_pool',
    'app.talent_pools', v_row.id, 'success', null, null, jsonb_build_object('name', v_row.name)
  );

  return v_row;
end;
$$;

create function app.add_talent_pool_member(p_pool_id uuid, p_employee_id uuid, p_added_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.talent_pool_members
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_pool app.talent_pools;
  v_row app.talent_pool_members;
begin
  select * into v_pool from app.talent_pools where id = p_pool_id;
  if not found then
    raise exception 'talent_pool_not_found: %', p_pool_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_pool.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_pool.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_pool.status <> 'active' then
    raise exception 'talent_pool_not_active: pool % is % not active', p_pool_id, v_pool.status using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.employees e where e.master_record_id = p_employee_id and e.tenant_id = v_pool.tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;
  if p_added_reason is null or length(trim(p_added_reason)) = 0 then
    raise exception 'reason_required: a reason is required to add a talent pool member' using errcode = 'check_violation';
  end if;

  begin
    insert into app.talent_pool_members (tenant_id, pool_id, employee_id, added_reason, added_by)
    values (v_pool.tenant_id, p_pool_id, p_employee_id, p_added_reason, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'talent_pool_member_conflict: employee % is already an active member of pool %', p_employee_id, p_pool_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_pool.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_talent_pool_member',
    'app.talent_pool_members', v_row.id, 'success', null, null, jsonb_build_object('pool_id', p_pool_id, 'employee_id', p_employee_id)
  );

  return v_row;
end;
$$;

create function app.remove_talent_pool_member(p_member_id uuid, p_expected_version integer, p_removed_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.talent_pool_members
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.talent_pool_members;
begin
  select * into v_row from app.talent_pool_members where id = p_member_id for update;
  if not found then
    raise exception 'talent_pool_member_not_found: %', p_member_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status <> 'active' then
    raise exception 'invalid_transition: member % is % not active', p_member_id, v_row.status using errcode = 'check_violation';
  end if;
  if p_removed_reason is null or length(trim(p_removed_reason)) = 0 then
    raise exception 'reason_required: a reason is required to remove a talent pool member' using errcode = 'check_violation';
  end if;

  update app.talent_pool_members set status = 'removed', removed_reason = p_removed_reason, removed_by = p_actor_label, removed_at = now()
  where id = p_member_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: concurrent update detected for member %', p_member_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_talent_pool_member',
    'app.talent_pool_members', v_row.id, 'success', null, null, jsonb_build_object('pool_id', v_row.pool_id)
  );

  return v_row;
end;
$$;

create function app.list_talent_pools(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.talent_pools
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_training_authority('Override', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.talent_pools where tenant_id = p_tenant_id order by name;
end;
$$;

create function app.list_talent_pool_members(p_pool_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, pool_id uuid, employee_id uuid, employee_full_name text, status text, added_reason text, added_at timestamptz, record_version integer)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_pool app.talent_pools;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_pool from app.talent_pools where id = p_pool_id;
  if not found then
    raise exception 'talent_pool_not_found: %', p_pool_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_pool.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_pool.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select m.id, m.pool_id, m.employee_id, e.full_name, m.status, m.added_reason, m.added_at, m.record_version
  from app.talent_pool_members m
  join app.employees e on e.master_record_id = m.employee_id
  where m.pool_id = p_pool_id
  order by m.added_at desc;
end;
$$;

-- ===========================================================================
-- 26. Succession candidate (decision 6, 7; section 13, 20).
-- ===========================================================================

create function app.propose_succession_candidate(p_tenant_id uuid, p_position_id uuid, p_candidate_employee_id uuid, p_readiness text, p_decision_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.talent_succession_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.talent_succession_candidates;
begin
  if not app.check_training_authority('Override', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from app.positions p where p.id = p_position_id and p.tenant_id = p_tenant_id) then
    raise exception 'position_not_found: %', p_position_id using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.employees e where e.master_record_id = p_candidate_employee_id and e.tenant_id = p_tenant_id) then
    raise exception 'employee_not_found: %', p_candidate_employee_id using errcode = 'no_data_found';
  end if;
  if p_readiness not in ('ready_now', 'ready_1_2_years', 'ready_3_plus_years', 'development_needed') then
    raise exception 'invalid_readiness: %', p_readiness using errcode = 'check_violation';
  end if;
  if p_decision_reason is null or length(trim(p_decision_reason)) = 0 then
    raise exception 'reason_required: a reason is required to propose a succession candidate' using errcode = 'check_violation';
  end if;

  begin
    insert into app.talent_succession_candidates (tenant_id, position_id, candidate_employee_id, readiness, decision_reason, created_by)
    values (p_tenant_id, p_position_id, p_candidate_employee_id, p_readiness, p_decision_reason, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'talent_succession_candidate_conflict: employee % already has an active succession candidacy for position %', p_candidate_employee_id, p_position_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'propose_succession_candidate',
    'app.talent_succession_candidates', v_row.id, 'success', null, null, jsonb_build_object('position_id', p_position_id, 'candidate_employee_id', p_candidate_employee_id, 'readiness', p_readiness)
  );

  return v_row;
end;
$$;

-- Structural self-decision block (decision 7): a candidate may never
-- confirm/withdraw their own succession candidacy, even if they separately
-- hold HRS:Override.
create function app.decide_succession_candidate(p_candidate_id uuid, p_expected_version integer, p_decision text, p_decision_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.talent_succession_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.talent_succession_candidates;
  v_self app.employees;
begin
  select * into v_row from app.talent_succession_candidates where id = p_candidate_id for update;
  if not found then
    raise exception 'talent_succession_candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Override', v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_self := app.get_self_employee(v_row.tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_row.candidate_employee_id then
    raise exception 'self_decision_not_permitted: an actor may not decide their own succession candidacy' using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status <> 'proposed' then
    raise exception 'invalid_transition: candidate % is % not proposed', p_candidate_id, v_row.status using errcode = 'check_violation';
  end if;
  if p_decision not in ('confirm', 'withdraw') then
    raise exception 'invalid_decision: %', p_decision using errcode = 'check_violation';
  end if;
  if p_decision_reason is null or length(trim(p_decision_reason)) = 0 then
    raise exception 'reason_required: a reason is required to decide a succession candidate' using errcode = 'check_violation';
  end if;

  update app.talent_succession_candidates
  set status = case p_decision when 'confirm' then 'confirmed' else 'withdrawn' end, decision_reason = p_decision_reason, decided_by = p_actor_label, decided_at = now()
  where id = p_candidate_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: concurrent update detected for candidate %', p_candidate_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_succession_candidate',
    'app.talent_succession_candidates', v_row.id, 'success', null, null, jsonb_build_object('decision', p_decision, 'status', v_row.status)
  );

  return v_row;
end;
$$;

create function app.list_succession_candidates(p_tenant_id uuid, p_actor_auth_user_id uuid, p_position_id uuid default null)
returns table (
  id uuid, position_id uuid, position_title text, candidate_employee_id uuid, candidate_full_name text, readiness text, status text, record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_training_authority('Override', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query
  select s.id, s.position_id, pos.title, s.candidate_employee_id, e.full_name, s.readiness, s.status, s.record_version
  from app.talent_succession_candidates s
  join app.positions pos on pos.id = s.position_id
  join app.employees e on e.master_record_id = s.candidate_employee_id
  where s.tenant_id = p_tenant_id and (p_position_id is null or s.position_id = p_position_id)
  order by s.created_at desc;
end;
$$;

-- ===========================================================================
-- 27. Privacy-safe aggregate reporting -- genuine k-anonymity floor
--     (decision 8).
-- ===========================================================================

create function app.report_talent_pool_distribution_by_department(p_tenant_id uuid, p_pool_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns table (department_org_unit_id uuid, department_name text, member_count integer, suppressed boolean)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  c_k_floor constant integer := 5;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_training_authority('Override', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'report_talent_pool_distribution_by_department',
    'app.talent_pools', p_pool_id, 'success', null, null, jsonb_build_object('pool_id', p_pool_id)
  );

  return query
  with per_dept as (
    select e.department_org_unit_id as dept_id, ou.name as dept_name, count(*)::integer as cnt
    from app.talent_pool_members m
    join app.employees e on e.master_record_id = m.employee_id
    left join app.org_units ou on ou.id = e.department_org_unit_id
    where m.tenant_id = p_tenant_id and m.pool_id = p_pool_id and m.status = 'active'
    group by e.department_org_unit_id, ou.name
  )
  select pd.dept_id, pd.dept_name,
    case when pd.cnt >= c_k_floor then pd.cnt else null end,
    pd.cnt < c_k_floor
  from per_dept pd
  order by pd.dept_name nulls last;
end;
$$;

comment on function app.report_talent_pool_distribution_by_department is
  'HRT-284 (decision 8, section 16 "small-cohort reporting is protected the same way Prompt 283 required"): a genuine k-anonymity-style floor (k=5, fixed) enforced INSIDE this SECURITY DEFINER function -- member_count is nulled and suppressed=true for any department with fewer than 5 active pool members. Not merely a UI hint: no caller, including a genuine HRS:Override holder, can retrieve a small cohort''s exact headcount through this RPC.';

-- ===========================================================================
-- 28. Row Level Security.
-- ===========================================================================

alter table app.training_competencies enable row level security;
alter table app.training_courses enable row level security;
alter table app.training_course_versions enable row level security;
alter table app.training_course_competencies enable row level security;
alter table app.training_providers enable row level security;
alter table app.training_course_prerequisites enable row level security;
alter table app.training_sessions enable row level security;
alter table app.training_enrollments enable row level security;
alter table app.training_assessments enable row level security;
alter table app.training_certificates enable row level security;
alter table app.training_certificate_expiry_reminders enable row level security;
alter table app.training_development_plans enable row level security;
alter table app.training_development_plan_actions enable row level security;
alter table app.talent_review_cycles enable row level security;
alter table app.talent_review_assignments enable row level security;
alter table app.talent_reviews enable row level security;
alter table app.talent_pools enable row level security;
alter table app.talent_pool_members enable row level security;
alter table app.talent_succession_candidates enable row level security;

-- Catalogue: broadly tenant-member-readable metadata ("training may be
-- broadly visible", section 16) -- mirrors HRT-283's identical
-- performance_kpi_definitions/_templates precedent, hardened default-deny
-- form against a customer_user-layer principal (ISS-2026-010 lineage).
create policy training_competencies_select_scoped on app.training_competencies
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy training_courses_select_scoped on app.training_courses
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy training_course_versions_select_scoped on app.training_course_versions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy training_course_competencies_select_scoped on app.training_course_competencies
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy training_providers_select_scoped on app.training_providers
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy training_course_prerequisites_select_scoped on app.training_course_prerequisites
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy training_sessions_select_scoped on app.training_sessions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- Person-scoped: self / direct manager / HRS:View personal data (decision
-- 6) -- "results... are purpose- and field-restricted" (section 16).
create policy training_enrollments_select_scoped on app.training_enrollments
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_training_talent_row(tenant_id, employee_id, (select auth.uid())));

create policy training_assessments_select_scoped on app.training_assessments
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_training_talent_row(tenant_id, employee_id, (select auth.uid())));

create policy training_certificates_select_scoped on app.training_certificates
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_training_talent_row(tenant_id, employee_id, (select auth.uid())));

create policy training_certificate_expiry_reminders_select_scoped on app.training_certificate_expiry_reminders
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_training_talent_row(tenant_id, employee_id, (select auth.uid())));

create policy training_development_plans_select_scoped on app.training_development_plans
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_training_talent_row(tenant_id, employee_id, (select auth.uid())));

create policy training_development_plan_actions_select_scoped on app.training_development_plan_actions
  for select to authenticated
  using (
    app.is_supreme_admin()
    or exists (
      select 1 from app.training_development_plans p
      where p.id = plan_id and app.can_view_hris_training_talent_row(p.tenant_id, p.employee_id, (select auth.uid()))
    )
  );

-- Talent: HRS:Override OR the specific assigned reviewer for that case
-- (decision 6) -- deliberately NOT self, NOT direct manager, narrower than
-- every other person-scoped table above.
create policy talent_review_cycles_select_scoped on app.talent_review_cycles
  for select to authenticated
  using (
    app.is_supreme_admin()
    or app.check_training_authority('Override', tenant_id, (select auth.uid()))
    or exists (
      select 1 from app.talent_review_assignments a
      where a.cycle_id = talent_review_cycles.id and a.status = 'active'
        and a.reviewer_employee_id = (app.get_self_employee(tenant_id, (select auth.uid()))).master_record_id
    )
  );

create policy talent_review_assignments_select_scoped on app.talent_review_assignments
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_talent_review_row(tenant_id, reviewer_employee_id, (select auth.uid())));

create policy talent_reviews_select_scoped on app.talent_reviews
  for select to authenticated
  using (
    app.is_supreme_admin()
    or exists (
      select 1 from app.talent_review_assignments a
      where a.id = assignment_id and app.can_view_talent_review_row(a.tenant_id, a.reviewer_employee_id, (select auth.uid()))
    )
  );

create policy talent_pools_select_scoped on app.talent_pools
  for select to authenticated
  using (app.is_supreme_admin() or app.check_training_authority('Override', tenant_id, (select auth.uid())));

create policy talent_pool_members_select_scoped on app.talent_pool_members
  for select to authenticated
  using (app.is_supreme_admin() or app.check_training_authority('Override', tenant_id, (select auth.uid())));

create policy talent_succession_candidates_select_scoped on app.talent_succession_candidates
  for select to authenticated
  using (app.is_supreme_admin() or app.check_training_authority('Override', tenant_id, (select auth.uid())));

-- ===========================================================================
-- 29. Grants. Per ERR-2026-004 / the standing convention established at
--     PLT-118 (20260717095000): explicit REVOKE before any role-specific
--     GRANT below, defense-in-depth belt-and-suspenders alongside the
--     schema-wide `alter default privileges` set up in that migration.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.training_competencies to authenticated, service_role;
grant select on app.training_courses to authenticated, service_role;
grant select on app.training_course_versions to authenticated, service_role;
grant select on app.training_course_competencies to authenticated, service_role;
grant select on app.training_providers to authenticated, service_role;
grant select on app.training_course_prerequisites to authenticated, service_role;
grant select on app.training_sessions to authenticated, service_role;
grant select on app.training_enrollments to authenticated, service_role;
grant select on app.training_assessments to authenticated, service_role;
grant select on app.training_certificates to authenticated, service_role;
grant select on app.training_certificate_expiry_reminders to authenticated, service_role;
grant select on app.training_development_plans to authenticated, service_role;
grant select on app.training_development_plan_actions to authenticated, service_role;
grant select on app.talent_review_cycles to authenticated, service_role;
grant select on app.talent_review_assignments to authenticated, service_role;
grant select on app.talent_reviews to authenticated, service_role;
grant select on app.talent_pools to authenticated, service_role;
grant select on app.talent_pool_members to authenticated, service_role;
grant select on app.talent_succession_candidates to authenticated, service_role;

grant insert, update, delete on app.training_competencies to service_role;
grant insert, update, delete on app.training_courses to service_role;
grant insert, update, delete on app.training_course_versions to service_role;
grant insert, update, delete on app.training_course_competencies to service_role;
grant insert, update, delete on app.training_providers to service_role;
grant insert, update, delete on app.training_course_prerequisites to service_role;
grant insert, update, delete on app.training_sessions to service_role;
grant insert, update, delete on app.training_enrollments to service_role;
grant insert, update, delete on app.training_assessments to service_role;
grant insert, update, delete on app.training_certificates to service_role;
grant insert, update, delete on app.training_certificate_expiry_reminders to service_role;
grant insert, update, delete on app.training_development_plans to service_role;
grant insert, update, delete on app.training_development_plan_actions to service_role;
grant insert, update, delete on app.talent_review_cycles to service_role;
grant insert, update, delete on app.talent_review_assignments to service_role;
grant insert, update, delete on app.talent_reviews to service_role;
grant insert, update, delete on app.talent_pools to service_role;
grant insert, update, delete on app.talent_pool_members to service_role;
grant insert, update, delete on app.talent_succession_candidates to service_role;

grant execute on function app.touch_training_row() to service_role;
grant execute on function app.check_training_authority(text, uuid, uuid) to authenticated, service_role;
grant execute on function app.can_view_hris_training_talent_row(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.can_view_talent_review_row(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app._training_prerequisites_met(uuid, uuid, uuid) to service_role;

grant execute on function app.create_training_competency(uuid, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.publish_training_competency(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.archive_training_competency(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.list_training_competencies(uuid, uuid) to authenticated, service_role;

grant execute on function app.create_training_course(uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_training_course_version(uuid, text, text, numeric, boolean, boolean, boolean, numeric, boolean, integer, uuid, text) to authenticated, service_role;
grant execute on function app.publish_training_course_version(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.archive_training_course_version(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.add_training_course_competency(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.list_training_courses(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_training_course_versions(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_training_course_competencies(uuid, uuid) to authenticated, service_role;

grant execute on function app.create_training_provider(uuid, text, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_training_provider_status(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_training_providers(uuid, uuid) to authenticated, service_role;

grant execute on function app.add_training_course_prerequisite(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.remove_training_course_prerequisite(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.list_training_course_prerequisites(uuid, uuid) to authenticated, service_role;

grant execute on function app.create_training_session(uuid, uuid, uuid, text, text, timestamptz, timestamptz, integer, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_training_session(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_training_sessions(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_training_session(uuid, uuid) to authenticated, service_role;

grant execute on function app._enroll_employee_in_training_session_internal(uuid, uuid, text, text) to service_role;
grant execute on function app.enroll_self_in_training_session(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.enroll_employee_in_training_session(uuid, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.bulk_assign_mandatory_training_session(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.decide_training_enrollment(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_training_enrollment(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.reschedule_training_enrollment(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.record_training_attendance(uuid, boolean, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.record_training_completion(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_training_enrollments(uuid, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.list_my_training_enrollments(uuid, uuid, text) to authenticated, service_role;

grant execute on function app.compute_training_assessment_passed(numeric, numeric, numeric) to service_role;
grant execute on function app.record_training_assessment(uuid, numeric, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_training_assessments(uuid, uuid) to authenticated, service_role;

grant execute on function app.issue_training_certificate(uuid, uuid, uuid, uuid, text, date, date, uuid, text) to authenticated, service_role;
grant execute on function app.import_historical_training_certificate(uuid, uuid, text, uuid, text, date, date, uuid, text) to authenticated, service_role;
grant execute on function app.attach_training_certificate_evidence(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.verify_training_certificate(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.revoke_training_certificate(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.renew_training_certificate(uuid, text, date, date, uuid, text) to authenticated, service_role;
grant execute on function app.list_training_certificates(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_my_training_certificates(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_training_certificate(uuid, uuid) to authenticated, service_role;

grant execute on function app.run_training_certificate_expiry_batch(uuid, date, text, uuid, text) to authenticated, service_role;
grant execute on function app.run_training_certificate_expiry_reminder_batch(uuid, date, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_training_certificate_expiry_reminders(uuid, uuid, uuid) to authenticated, service_role;

grant execute on function app.create_training_development_plan(uuid, uuid, text, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.transition_training_development_plan_status(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.add_training_development_plan_action(uuid, text, text, uuid, date, uuid, text) to authenticated, service_role;
grant execute on function app.update_training_development_plan_action_status(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_training_development_plans(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_my_training_development_plans(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_training_development_plan_actions(uuid, uuid) to authenticated, service_role;

grant execute on function app.create_talent_review_cycle(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.transition_talent_review_cycle_status(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_talent_review_cycles(uuid, uuid) to authenticated, service_role;
grant execute on function app.assign_talent_reviewer(uuid, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.reassign_talent_reviewer(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_talent_review(uuid, integer, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_talent_review_assignments(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_my_talent_review_assignments(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_talent_review(uuid, uuid) to authenticated, service_role;

grant execute on function app.create_talent_pool(uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.archive_talent_pool(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.add_talent_pool_member(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.remove_talent_pool_member(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_talent_pools(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_talent_pool_members(uuid, uuid) to authenticated, service_role;

grant execute on function app.propose_succession_candidate(uuid, uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_succession_candidate(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_succession_candidates(uuid, uuid, uuid) to authenticated, service_role;

grant execute on function app.report_talent_pool_distribution_by_department(uuid, uuid, uuid, text) to authenticated, service_role;
