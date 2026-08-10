-- HRIS capability HRT-277 (Onboarding and Offboarding, CG-S12-HRT-005, Prompt 277).
-- The FOURTH Phase 7 capability, built on HRT-274 (Employee Master, VERIFIED),
-- HRT-275 (Organization and Position Linkage, VERIFIED) and HRT-276 (Recruitment/
-- ATS, COMPLETED, this same batch). Per ADR-0023 Part B, this is EXACTLY where the
-- governed candidate -> employee -> Platform-user conversion the ADR reserved for
-- this prompt becomes real: an accepted job_offer (HRT-276's own
-- app.job_offers.status='accepted', which explicitly creates no app.employees or
-- app.users row -- HRT-276 build log Section 1/9) converts, exactly once,
-- idempotently, into a linked app.employees row, and this capability's own
-- provision-request/revoke-request tasks write through Platform identity/access
-- authority using the EXISTING governed mechanisms this migration reuses directly
-- and never re-implements:
--   * app.create_employee_draft (HRT-274) -- the candidate/direct-hire -> employee
--     conversion itself. Idempotency is derived deterministically from the source
--     job_offer id (never a client-supplied key for the offer path), so retrying
--     app.start_onboarding_case against the SAME accepted offer always resolves to
--     the SAME employee row, never a duplicate (acceptance criterion 1).
--   * app.invite_user / app.assign_role / app.link_employee_user (PLT-107/110/111)
--     -- the real Platform user-account creation and role-grant mechanism. This
--     migration NEVER inserts into app.users or app.role_assignments directly.
--     app.invite_user itself requires an ALREADY-LINKED auth.users identity (its
--     own migration header: "Invite-by-email-before-signup... is disclosed
--     NOT_RUN here") -- a standing, repository-wide gap (re-confirmed this
--     checkpoint: zero `auth.admin.*`/`inviteUserByEmail` call sites exist
--     anywhere in app/ or server/) this checkpoint does NOT attempt to close,
--     since doing so would be a first-of-its-kind auth-identity-creation
--     mechanism (batch protocol section 3.2 trigger 2), squarely out of this
--     single-prompt batch's own scope. Concretely: app.request_onboarding_access_
--     provisioning accepts an OPTIONAL p_target_auth_user_id -- when the caller
--     (HR/IT) already has a resolved auth identity for the new hire (the common
--     real-world case: IT completes the cold-start Supabase invite out-of-band,
--     exactly the "invite-by-email-before-signup" gap already disclosed
--     repository-wide, then hands the resulting auth_user_id back to HR), this
--     RPC performs the REAL, synchronous, governed grant through the three
--     primitives above. When no auth identity is resolved yet, the request is
--     recorded (app.onboarding_task_provisioning_requests, status='requested')
--     and the task stays in_progress -- section 22's own "preboarding without
--     user access" alternative flow, never a fabricated success.
--   * app.transition_user_status (PLT-110) -- offboarding's real access
--     revocation. Reused directly (already cascades principal-membership and
--     auth-identity revocation on its own).
--   * app.request_approval / app.decide_approval_step / app.cancel_approval_
--     request (PLT-123) -- case finalize approval routing, mirroring HRT-276's
--     own app.submit_job_offer_for_approval/app.decide_job_offer_approval wrapper
--     shape EXACTLY, including the hardened terminal-UPDATE guard HRT-276's own
--     Tier C review round (20260730870000, findings 7/8) had to retrofit after a
--     live-reproduced two-process race -- applied here from the FIRST migration,
--     not retrofitted, per this task's own explicit instruction. app.
--     cancel_onboarding_case cancels any still-pending finalize-approval request
--     BEFORE cascading the case to cancelled, using the identical deliberately-
--     PLAIN-read, defer-all-locking-to-the-terminal-UPDATE lock order HRT-276's
--     fixed app.reject_application/app.withdraw_application established, so this
--     domain does not reintroduce the exact lock-order deadlock that fix's own
--     comment documents finding in an early draft.
--   * app.enqueue_job (PLT-132), job_type='integration_sync' -- every
--     provisioning/revocation/handoff action that involves a downstream external
--     system (asset/training/payroll/Operations, and the notify-IT half of
--     access provisioning) enqueues a real, tested job-framework row for
--     reconciliation (section 17 "async ... adapters with backpressure and
--     reconciliation") rather than adding a bespoke job_type to app.jobs' own
--     shared, cross-domain CHECK constraint / app.generic_job_types() single
--     source of truth (20260730410000) -- a materially more invasive, shared-
--     primitive-widening change this single-prompt batch has no mandate to make
--     for one domain. app.onboarding_task_provisioning_requests is this
--     migration's own reconciliation ledger, carrying the enqueued job's id.
--
-- Design decisions disclosed up front (never left implicit):
--
-- 1. Case finalize is PRECONDITION-CHECK-ONLY against app.employees.lifecycle_
--    status, never a chained mutation of it. app.submit_onboarding_case_for_
--    finalize_approval requires lifecycle_status='active' for an onboarding
--    case, or in ('terminated','archived') for an offboarding case, BEFORE
--    routing to PLT-123 -- HR drives the employee's own governed lifecycle FSM
--    (submit/decide/activate, or terminate) via HRT-274's own existing RPCs,
--    with HRT-274's own existing authority gates, exactly once. An earlier
--    design considered having app.decide_onboarding_case_finalize_approval
--    itself call app.terminate_employee (HRS:Override) at approval time --
--    rejected during this migration's own drafting: the PLT-123 approver
--    eligible to decide the CASE'S finalize step is not guaranteed to hold
--    HRS:Override on the EMPLOYEE row, an authority-chaining fragility with no
--    clean failure mode (a legitimately-eligible case approver could find their
--    decision unexpectedly rejected by a SECOND, unrelated authority gate deep
--    inside the transaction). Precondition-check-only avoids this entirely and
--    never duplicates HRT-274's own already-verified transition authority.
-- 2. Rehire (section 22's own alternative flow) genuinely needs a new employee-
--    lifecycle transition HRT-274 never built: app.reactivate_employee only
--    restores from 'suspended' (verified by direct reading of
--    20260730830000:1389-1462), and no terminated/archived -> active path
--    exists anywhere. app.rehire_employee (terminated -> active only; archived
--    stays genuinely terminal, matching HRT-274's own explicit "terminal
--    administrative closure" design intent for that state) is added HERE, as a
--    new, additive function operating on the pre-existing app.employees table
--    -- the same kind of downstream extension HRT-275 itself already made
--    (adding app.employees.position_id and its own RPCs) when a later
--    capability's own chartered scope genuinely required it. HRT-274's own
--    20260730830000 file is not edited.
-- 3. Employment-type vocabulary mismatch between app.job_offer_versions.
--    employment_type ('full_time','part_time','contract','internship',
--    'temporary') and app.employees.employment_type ('full_time','part_time',
--    'contract','intern','probation','daily_worker') is real (independently
--    confirmed by direct reading of both CHECK constraints) -- mapped
--    explicitly in app.start_onboarding_case (internship->intern,
--    temporary->contract, the closest real fit), never silently truncated or
--    left to fail a CHECK constraint at INSERT time.
-- 4. Sensitive HR evidence and exit reason are field-restricted from THIS,
--    the FIRST, migration (never retrofitted) -- app.onboarding_offboarding_
--    cases.exit_reason and app.onboarding_case_tasks.evidence_note/waive_reason
--    are excluded from the plain `authenticated` column grant (the PLT-114/
--    app.candidates/app.employees pattern), full access via service_role, and
--    masked/unmasked in the read RPCs by app.has_view_personal_data (reused
--    directly, already hardcoded to module 'HRS' -- no new helper needed).
-- 5. Notification-engine (PLT-127) wiring for task-owner due/overdue notices is
--    DISCLOSED, not built, this checkpoint (see the KNOWN_ISSUES.md entry this
--    checkpoint files) -- independently confirmed that ZERO prior HRT capability
--    (274/275/276) has ever called app.queue_notification/app.register_
--    notification_type, so this would be a first-of-its-kind integration for
--    this whole HRIS domain, not a bounded addition; overdue/blocked state is
--    still real and computed (due_at < now() at read time, exactly HRT-275's
--    own disclosed "no live scheduler exists anywhere in this repository yet"
--    precedent, ISS-2026-015), just not proactively pushed.
-- 6. No REST/GraphQL adapter -- matches the repository-wide Phase 1-7 precedent
--    every prior HRT/PRC/COM checkpoint already disclosed identically; Server
--    Actions only.
-- 7. Checklist templates are versioned, tenant-scoped, bespoke tables (mirroring
--    HRT-275's own position/grade catalogue shape: directly tenant-scoped,
--    record_version, active lifecycle) rather than routed through PLT-121's
--    Configuration Engine -- a checklist is domain workflow structure with its
--    own task/dependency graph, not a flat key/value config payload.
-- 8. task_type is a closed, small set ('document','access_provisioning',
--    'access_revocation','handoff','generic'); asset/training/payroll/
--    Operations handoffs are modeled as task_type='handoff' with an explicit
--    handoff_category column ('asset','training','payroll','operations')
--    rather than four separate task types/RPCs -- all four are, from this
--    domain's own point of view, an identical shape: an external acknowledgement
--    with evidence, never assumed success (section 14's own literal framing).
--    access_provisioning/access_revocation get their OWN dedicated RPCs because,
--    unlike the other four, they are the actual Platform-identity-authority
--    writes this whole prompt is chartered around.

-- ===========================================================================
-- 1. Checklist templates -- versioned, tenant-scoped (decision 7).
-- ===========================================================================

create table app.onboarding_checklist_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  name text not null,
  case_type text not null,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint onboarding_checklist_templates_code_check check (length(trim(code)) > 0),
  constraint onboarding_checklist_templates_name_check check (length(trim(name)) > 0),
  constraint onboarding_checklist_templates_case_type_check check (case_type in ('onboarding', 'offboarding', 'transfer')),
  constraint onboarding_checklist_templates_status_check check (status in ('active', 'archived')),
  constraint onboarding_checklist_templates_tenant_code_unique unique (tenant_id, code)
);

comment on table app.onboarding_checklist_templates is
  'HRT-277: tenant-scoped checklist template header (decision 7, mirrors app.positions'' own shape). One template per (tenant, code); each template owns 1..N versions, at most one published at a time (see app.onboarding_checklist_template_versions_one_published_idx below).';

create index onboarding_checklist_templates_tenant_case_type_idx on app.onboarding_checklist_templates (tenant_id, case_type, status);

create trigger onboarding_checklist_templates_touch_row
  before update on app.onboarding_checklist_templates
  for each row
  execute function app.touch_org_unit_row();

create table app.onboarding_checklist_template_versions (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references app.onboarding_checklist_templates (id),
  tenant_id uuid not null references app.tenants (id),
  version_number integer not null,
  status text not null default 'draft',
  published_at timestamptz,
  published_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint onboarding_checklist_template_versions_status_check check (status in ('draft', 'published', 'superseded')),
  constraint onboarding_checklist_template_versions_version_unique unique (template_id, version_number)
);

comment on table app.onboarding_checklist_template_versions is
  'HRT-277: one immutable-once-published checklist shape per version. app.onboarding_offboarding_cases.checklist_template_version_id locks in the version applied at case start (RPD-040: "active cases retain their applied version", section 24) -- a later template edit never retroactively changes an already-started case.';

create unique index onboarding_checklist_template_versions_one_published_idx on app.onboarding_checklist_template_versions (template_id) where status = 'published';
create index onboarding_checklist_template_versions_tenant_idx on app.onboarding_checklist_template_versions (tenant_id, status);

create trigger onboarding_checklist_template_versions_touch_row
  before update on app.onboarding_checklist_template_versions
  for each row
  execute function app.touch_org_unit_row();

create table app.onboarding_checklist_template_tasks (
  id uuid primary key default gen_random_uuid(),
  template_version_id uuid not null references app.onboarding_checklist_template_versions (id),
  tenant_id uuid not null references app.tenants (id),
  task_key text not null,
  title text not null,
  description text,
  task_type text not null,
  handoff_category text,
  owner_type text not null,
  is_mandatory boolean not null default true,
  sla_days integer not null default 3,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint onboarding_checklist_template_tasks_task_key_check check (task_key ~ '^[a-z0-9_-]{2,64}$'),
  constraint onboarding_checklist_template_tasks_title_check check (length(trim(title)) > 0),
  constraint onboarding_checklist_template_tasks_task_type_check check (task_type in ('document', 'access_provisioning', 'access_revocation', 'handoff', 'generic')),
  -- Self-found defect, fixed before commit: a bare
  -- `(task_type = 'handoff' and handoff_category in (...)) or (task_type <>
  -- 'handoff' and handoff_category is null)` evaluates to NULL (not FALSE)
  -- for task_type='handoff' with handoff_category IS NULL -- Postgres CHECK
  -- constraints only reject an explicit FALSE, so that shape silently ADMITTED
  -- exactly the malformed row it was meant to reject (a handoff task with no
  -- category). Fixed with an explicit `is not null` on the positive branch.
  constraint onboarding_checklist_template_tasks_handoff_category_check check (
    (task_type = 'handoff' and handoff_category is not null and handoff_category in ('asset', 'training', 'payroll', 'operations'))
    or (task_type <> 'handoff' and handoff_category is null)
  ),
  constraint onboarding_checklist_template_tasks_owner_type_check check (owner_type in ('hr', 'manager', 'employee', 'it', 'finance', 'operations')),
  constraint onboarding_checklist_template_tasks_sla_days_check check (sla_days > 0),
  constraint onboarding_checklist_template_tasks_version_key_unique unique (template_version_id, task_key)
);

comment on table app.onboarding_checklist_template_tasks is
  'HRT-277: one task definition within a checklist template version (decision 8: asset/training/payroll/operations handoffs share task_type=''handoff'' plus handoff_category, since all four are identically-shaped external acknowledgements from this domain''s own point of view).';

create index onboarding_checklist_template_tasks_version_idx on app.onboarding_checklist_template_tasks (template_version_id, sort_order);

create table app.onboarding_checklist_template_task_dependencies (
  id uuid primary key default gen_random_uuid(),
  template_version_id uuid not null references app.onboarding_checklist_template_versions (id),
  tenant_id uuid not null references app.tenants (id),
  task_key text not null,
  depends_on_task_key text not null,
  constraint onboarding_checklist_template_task_dependencies_not_self_check check (task_key <> depends_on_task_key),
  constraint onboarding_checklist_template_task_dependencies_unique unique (template_version_id, task_key, depends_on_task_key)
);

comment on table app.onboarding_checklist_template_task_dependencies is
  'HRT-277: an explicit dependency edge (task_key depends on depends_on_task_key must complete/waive first) within one template version. Cycle-checked at app.add_onboarding_checklist_template_task_dependency time via a bounded walk, mirroring app.assert_no_employee_manager_cycle''s own established shape (HRT-274).';

create index onboarding_checklist_template_task_dependencies_version_idx on app.onboarding_checklist_template_task_dependencies (template_version_id);

-- ===========================================================================
-- 2. Cases -- the onboarding/offboarding/transfer workflow instance.
-- ===========================================================================

create table app.onboarding_offboarding_cases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  case_type text not null,
  source_type text not null,
  source_job_offer_id uuid references app.job_offers (id),
  source_job_application_id uuid references app.job_applications (id),
  source_candidate_id uuid references app.candidates (id),
  employee_master_record_id uuid references app.employees (master_record_id),
  checklist_template_version_id uuid references app.onboarding_checklist_template_versions (id),
  status text not null default 'draft',
  effective_date date,
  initiated_by text,
  initiated_at timestamptz not null default now(),
  finalize_approval_request_id uuid references app.approval_requests (id),
  finalized_at timestamptz,
  finalized_by text,
  cancel_reason text,
  cancelled_at timestamptz,
  exit_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint onboarding_offboarding_cases_case_type_check check (case_type in ('onboarding', 'offboarding', 'transfer')),
  constraint onboarding_offboarding_cases_source_type_check check (source_type in ('job_offer', 'direct_hire', 'existing_employee')),
  constraint onboarding_offboarding_cases_status_check check (status in ('draft', 'active', 'pending_finalize_approval', 'finalized', 'cancelled')),
  constraint onboarding_offboarding_cases_cancel_reason_check check (status <> 'cancelled' or (cancel_reason is not null and length(trim(cancel_reason)) > 0)),
  constraint onboarding_offboarding_cases_exit_reason_check check (case_type <> 'offboarding' or status not in ('pending_finalize_approval', 'finalized') or (exit_reason is not null and length(trim(exit_reason)) > 0)),
  constraint onboarding_offboarding_cases_source_offer_unique unique (source_job_offer_id)
);

comment on table app.onboarding_offboarding_cases is
  'HRT-277: the workflow case root. employee_master_record_id is set exactly once, at start, and is idempotent for source_type=''job_offer'' (source_job_offer_id is unique-when-set, so retrying app.start_onboarding_case against the same accepted offer can never create a second case OR a second employee -- acceptance criterion 1). checklist_template_version_id is locked in at start (RPD-040). exit_reason is column-restricted (decision 4).';

create index onboarding_offboarding_cases_tenant_status_idx on app.onboarding_offboarding_cases (tenant_id, status);
create index onboarding_offboarding_cases_tenant_employee_idx on app.onboarding_offboarding_cases (tenant_id, employee_master_record_id) where employee_master_record_id is not null;
create unique index onboarding_offboarding_cases_idempotency_key_unique on app.onboarding_offboarding_cases (tenant_id, idempotency_key) where idempotency_key is not null;

create trigger onboarding_offboarding_cases_touch_row
  before update on app.onboarding_offboarding_cases
  for each row
  execute function app.touch_org_unit_row();

create table app.onboarding_case_events (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references app.onboarding_offboarding_cases (id),
  tenant_id uuid not null references app.tenants (id),
  event_type text not null,
  from_status text,
  to_status text,
  actor_auth_user_id uuid,
  actor_label text,
  notes text,
  occurred_at timestamptz not null default now()
);

comment on table app.onboarding_case_events is 'HRT-277: append-only case lifecycle/audit trail (section 18) -- mirrors app.employee_lifecycle_events'' own shape.';

create index onboarding_case_events_case_idx on app.onboarding_case_events (case_id, occurred_at desc);

-- ===========================================================================
-- 3. Case tasks -- the instantiated checklist, one row per template task, per
--    case, copied at instantiation (template edits never retroactively change
--    an active case).
-- ===========================================================================

create table app.onboarding_case_tasks (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references app.onboarding_offboarding_cases (id),
  tenant_id uuid not null references app.tenants (id),
  template_task_key text not null,
  title text not null,
  description text,
  task_type text not null,
  handoff_category text,
  owner_type text not null,
  owner_auth_user_id uuid references auth.users (id),
  is_mandatory boolean not null default true,
  due_at timestamptz,
  sort_order integer not null default 0,
  status text not null default 'pending',
  completed_at timestamptz,
  completed_by text,
  waived_at timestamptz,
  waived_by text,
  waive_reason text,
  evidence_note text,
  evidence_file_id uuid references app.files (id),
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint onboarding_case_tasks_task_type_check check (task_type in ('document', 'access_provisioning', 'access_revocation', 'handoff', 'generic')),
  constraint onboarding_case_tasks_owner_type_check check (owner_type in ('hr', 'manager', 'employee', 'it', 'finance', 'operations')),
  constraint onboarding_case_tasks_status_check check (status in ('pending', 'blocked', 'in_progress', 'completed', 'waived', 'reopened')),
  constraint onboarding_case_tasks_waive_reason_check check (status <> 'waived' or (waive_reason is not null and length(trim(waive_reason)) > 0)),
  constraint onboarding_case_tasks_case_key_unique unique (case_id, template_task_key)
);

comment on table app.onboarding_case_tasks is
  'HRT-277: one instantiated checklist task per case. evidence_note/waive_reason are column-restricted (decision 4). due_at/status drive due/blocked-state UI (section 15) -- overdue is computed at read time (due_at < now() and status not in completed/waived), no live scheduler (decision 5).';

create index onboarding_case_tasks_case_idx on app.onboarding_case_tasks (case_id, sort_order);
create index onboarding_case_tasks_tenant_owner_idx on app.onboarding_case_tasks (tenant_id, owner_auth_user_id) where owner_auth_user_id is not null;
create index onboarding_case_tasks_tenant_due_idx on app.onboarding_case_tasks (tenant_id, due_at) where status not in ('completed', 'waived');

create trigger onboarding_case_tasks_touch_row
  before update on app.onboarding_case_tasks
  for each row
  execute function app.touch_org_unit_row();

create table app.onboarding_case_task_dependencies (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references app.onboarding_offboarding_cases (id),
  tenant_id uuid not null references app.tenants (id),
  task_id uuid not null references app.onboarding_case_tasks (id),
  depends_on_task_id uuid not null references app.onboarding_case_tasks (id),
  constraint onboarding_case_task_dependencies_not_self_check check (task_id <> depends_on_task_id),
  constraint onboarding_case_task_dependencies_unique unique (task_id, depends_on_task_id)
);

comment on table app.onboarding_case_task_dependencies is 'HRT-277: instantiated dependency edges, copied from the template at case start.';

create index onboarding_case_task_dependencies_case_idx on app.onboarding_case_task_dependencies (case_id);
create index onboarding_case_task_dependencies_task_idx on app.onboarding_case_task_dependencies (task_id);

-- ===========================================================================
-- 4. Provisioning/revocation request ledger (the Platform-identity-authority
--    write audit/reconciliation trail, section 17/18).
-- ===========================================================================

create table app.onboarding_task_provisioning_requests (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references app.onboarding_offboarding_cases (id),
  task_id uuid not null references app.onboarding_case_tasks (id),
  tenant_id uuid not null references app.tenants (id),
  request_type text not null,
  target_auth_user_id uuid,
  requested_role_version_ids uuid[] not null default '{}',
  org_unit_id uuid references app.org_units (id),
  result_user_id uuid references app.users (id),
  status text not null default 'requested',
  failure_reason text,
  job_id uuid,
  requested_by text,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint onboarding_task_provisioning_requests_request_type_check check (request_type in ('grant_access', 'revoke_access')),
  constraint onboarding_task_provisioning_requests_status_check check (status in ('requested', 'completed', 'failed'))
);

comment on table app.onboarding_task_provisioning_requests is
  'HRT-277: the real audit/reconciliation ledger for every Platform-identity-authority write this capability performs -- never a fabricated success. job_id (nullable) references app.jobs.job_id (PLT-132, no FK -- app.jobs has no unique constraint on job_id alone suitable for a cross-schema FK here; correctness is enforced by only ever writing a job_id this same transaction just obtained from app.enqueue_job).';

create index onboarding_task_provisioning_requests_task_idx on app.onboarding_task_provisioning_requests (task_id);
create index onboarding_task_provisioning_requests_case_idx on app.onboarding_task_provisioning_requests (case_id);

-- ===========================================================================
-- 5. Evidence document type registration (PLT-128) -- mirrors HRT-274's own
--    direct-INSERT pattern (app.register_document_type gates on Supreme Admin;
--    a migration-apply context has no live actor).
-- ===========================================================================

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('onboarding_evidence', 'Onboarding/Offboarding Evidence', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:onboarding_evidence', 'Onboarding/Offboarding Evidence', 'HRS', 'system')
on conflict (code) do nothing;

-- ===========================================================================
-- 6. Audit projection helpers (taxonomy C-07: never to_jsonb(row) for a table
--    carrying a classified column).
-- ===========================================================================

create function app.onboarding_case_audit_projection(p_case app.onboarding_offboarding_cases)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_case.id, 'tenant_id', p_case.tenant_id, 'case_type', p_case.case_type,
    'source_type', p_case.source_type, 'employee_master_record_id', p_case.employee_master_record_id,
    'checklist_template_version_id', p_case.checklist_template_version_id, 'status', p_case.status,
    'effective_date', p_case.effective_date, 'record_version', p_case.record_version
  );
$$;

create function app.onboarding_case_task_audit_projection(p_task app.onboarding_case_tasks)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_task.id, 'case_id', p_task.case_id, 'template_task_key', p_task.template_task_key,
    'task_type', p_task.task_type, 'handoff_category', p_task.handoff_category, 'status', p_task.status,
    'owner_type', p_task.owner_type, 'owner_auth_user_id', p_task.owner_auth_user_id,
    'is_mandatory', p_task.is_mandatory, 'record_version', p_task.record_version
  );
$$;

-- ===========================================================================
-- 7. Checklist template authoring (HRS:Create/Edit to author, HRS:Approve to
--    publish -- mirrors app.publish_employee_position... family's own split).
-- ===========================================================================

create function app.create_onboarding_checklist_template(
  p_tenant_id uuid, p_code text, p_name text, p_case_type text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_checklist_templates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.onboarding_checklist_templates;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_case_type not in ('onboarding', 'offboarding', 'transfer') then
    raise exception 'invalid_case_type: %', p_case_type using errcode = 'check_violation';
  end if;

  begin
    insert into app.onboarding_checklist_templates (tenant_id, code, name, case_type, created_by)
    values (p_tenant_id, p_code, p_name, p_case_type, p_actor_label)
    returning * into v_template;
  exception
    when unique_violation then
      raise exception 'template_code_conflict: template code % is already in use for this tenant', p_code
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_onboarding_checklist_template',
    'app.onboarding_checklist_templates', v_template.id, 'success', null, null, to_jsonb(v_template)
  );

  return v_template;
end;
$$;

create function app.create_onboarding_checklist_template_version(
  p_template_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_checklist_template_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.onboarding_checklist_templates;
  v_existing_draft app.onboarding_checklist_template_versions;
  v_next_number integer;
  v_version app.onboarding_checklist_template_versions;
begin
  select * into v_template from app.onboarding_checklist_templates where id = p_template_id;
  if not found or not app.has_active_tenant_membership(v_template.tenant_id, p_actor_auth_user_id) then
    raise exception 'template_not_found: %', p_template_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing_draft from app.onboarding_checklist_template_versions where template_id = p_template_id and status = 'draft';
  if found then
    return v_existing_draft;
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_number from app.onboarding_checklist_template_versions where template_id = p_template_id;

  insert into app.onboarding_checklist_template_versions (template_id, tenant_id, version_number, created_by)
  values (p_template_id, v_template.tenant_id, v_next_number, p_actor_label)
  returning * into v_version;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_onboarding_checklist_template_version',
    'app.onboarding_checklist_template_versions', v_version.id, 'success', null, null, to_jsonb(v_version)
  );

  return v_version;
end;
$$;

comment on function app.create_onboarding_checklist_template_version is 'HRT-277: idempotent-by-construction -- returns the existing draft version if one is already open, rather than creating a second concurrent draft.';

create function app.add_onboarding_checklist_template_task(
  p_template_version_id uuid, p_task_key text, p_title text, p_description text,
  p_task_type text, p_handoff_category text, p_owner_type text, p_is_mandatory boolean,
  p_sla_days integer, p_sort_order integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_checklist_template_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.onboarding_checklist_template_versions;
  v_task app.onboarding_checklist_template_tasks;
begin
  select * into v_version from app.onboarding_checklist_template_versions where id = p_template_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'template_version_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: template version % is %, tasks can only be added to a draft version', p_template_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.onboarding_checklist_template_tasks (
      template_version_id, tenant_id, task_key, title, description, task_type, handoff_category,
      owner_type, is_mandatory, sla_days, sort_order
    ) values (
      p_template_version_id, v_version.tenant_id, p_task_key, p_title, p_description, p_task_type, p_handoff_category,
      p_owner_type, coalesce(p_is_mandatory, true), coalesce(p_sla_days, 3), coalesce(p_sort_order, 0)
    )
    returning * into v_task;
  exception
    when unique_violation then
      raise exception 'task_key_conflict: task key % already exists in this template version', p_task_key
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_onboarding_checklist_template_task',
    'app.onboarding_checklist_template_tasks', v_task.id, 'success', null, null, to_jsonb(v_task)
  );

  return v_task;
end;
$$;

-- Bounded-walk cycle guard, mirroring app.assert_no_employee_manager_cycle's own
-- established shape (HRT-274) -- a template's own task count is realistically small
-- (tens, not thousands), so a 500-hop bound is generously above any plausible depth.
create function app.assert_no_onboarding_template_task_dependency_cycle(p_template_version_id uuid, p_task_key text, p_depends_on_task_key text)
returns void
language plpgsql
stable
as $$
declare
  v_visited text[] := array[p_task_key];
  v_current text := p_depends_on_task_key;
  v_hops integer := 0;
  v_next text;
begin
  loop
    if v_current = p_task_key then
      raise exception 'dependency_cycle: task % cannot depend on % -- would create a cycle', p_task_key, p_depends_on_task_key
        using errcode = 'check_violation';
    end if;
    v_hops := v_hops + 1;
    if v_hops > 500 then
      raise exception 'dependency_cycle: dependency chain exceeds 500 hops for task % (probable cycle)', p_task_key
        using errcode = 'check_violation';
    end if;
    select depends_on_task_key into v_next
    from app.onboarding_checklist_template_task_dependencies
    where template_version_id = p_template_version_id and task_key = v_current
    limit 1;
    if v_next is null then
      return;
    end if;
    v_current := v_next;
  end loop;
end;
$$;

create function app.add_onboarding_checklist_template_task_dependency(
  p_template_version_id uuid, p_task_key text, p_depends_on_task_key text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_checklist_template_task_dependencies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.onboarding_checklist_template_versions;
  v_dependency app.onboarding_checklist_template_task_dependencies;
begin
  select * into v_version from app.onboarding_checklist_template_versions where id = p_template_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'template_version_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: template version % is %, dependencies can only be added to a draft version', p_template_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  if not exists (select 1 from app.onboarding_checklist_template_tasks where template_version_id = p_template_version_id and task_key = p_task_key) then
    raise exception 'task_key_not_found: task % does not exist in this template version', p_task_key using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.onboarding_checklist_template_tasks where template_version_id = p_template_version_id and task_key = p_depends_on_task_key) then
    raise exception 'task_key_not_found: task % does not exist in this template version', p_depends_on_task_key using errcode = 'no_data_found';
  end if;

  perform app.assert_no_onboarding_template_task_dependency_cycle(p_template_version_id, p_task_key, p_depends_on_task_key);

  begin
    insert into app.onboarding_checklist_template_task_dependencies (template_version_id, tenant_id, task_key, depends_on_task_key)
    values (p_template_version_id, v_version.tenant_id, p_task_key, p_depends_on_task_key)
    returning * into v_dependency;
  exception
    when unique_violation then
      raise exception 'dependency_already_exists: % already depends on %', p_task_key, p_depends_on_task_key
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_onboarding_checklist_template_task_dependency',
    'app.onboarding_checklist_template_task_dependencies', v_dependency.id, 'success', null, null, to_jsonb(v_dependency)
  );

  return v_dependency;
end;
$$;

create function app.publish_onboarding_checklist_template_version(
  p_template_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_checklist_template_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.onboarding_checklist_template_versions;
  v_task_count integer;
begin
  select * into v_version from app.onboarding_checklist_template_versions where id = p_template_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'template_version_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: template version % expected version % but found %', p_template_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: template version % is %, only a draft can be published', p_template_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_task_count from app.onboarding_checklist_template_tasks where template_version_id = p_template_version_id;
  if v_task_count = 0 then
    raise exception 'template_has_no_tasks: template version % has no tasks to publish', p_template_version_id using errcode = 'check_violation';
  end if;

  update app.onboarding_checklist_template_versions set status = 'superseded'
  where template_id = v_version.template_id and status = 'published';

  update app.onboarding_checklist_template_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_template_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: template version % target row was concurrently modified (expected version %)', p_template_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_onboarding_checklist_template_version',
    'app.onboarding_checklist_template_versions', v_version.id, 'success', null, null, to_jsonb(v_version)
  );

  return v_version;
end;
$$;

comment on function app.publish_onboarding_checklist_template_version is 'HRT-277: publishing supersedes the template''s own prior published version FIRST (the partial unique index onboarding_checklist_template_versions_one_published_idx allows at most one published row per template at any instant) -- an already-started case is unaffected, since it locked in its own checklist_template_version_id at start.';

-- ===========================================================================
-- 8. Case start -- the ADR-0023 Part B conversion itself. Resolves source data
--    (job_offer/candidate, or direct-hire params, or an existing employee),
--    maps employment_type vocabulary (decision 3), resolves the checklist
--    template version to apply, instantiates tasks/dependencies.
-- ===========================================================================

create function app.map_offer_employment_type_to_employee(p_offer_employment_type text)
returns text
language sql
immutable
as $$
  select case p_offer_employment_type
    when 'full_time' then 'full_time'
    when 'part_time' then 'part_time'
    when 'contract' then 'contract'
    when 'internship' then 'intern'
    when 'temporary' then 'contract'
    else 'full_time'
  end;
$$;

comment on function app.map_offer_employment_type_to_employee is 'HRT-277 decision 3: app.job_offer_versions.employment_type (''full_time''/''part_time''/''contract''/''internship''/''temporary'') and app.employees.employment_type (''full_time''/''part_time''/''contract''/''intern''/''probation''/''daily_worker'') are genuinely different vocabularies -- internship maps to intern, temporary maps to contract (the closest real fit), never silently truncated.';

-- Taxonomy C-01 (full-tuple idempotency replay, not merely key match): compares
-- the request's own case-identifying fields against an existing idempotency-
-- key or source-offer match before treating it as a safe replay. Self-found
-- during this checkpoint's own Tier B taxonomy walk, fixed before commit --
-- the original app.start_onboarding_case short-circuited on a bare key/offer
-- match with no tuple comparison at all, silently misattributing a
-- same-key-different-request call to the first case ever created with that key.
create function app.assert_onboarding_case_start_idempotent_replay(
  p_existing app.onboarding_offboarding_cases, p_case_type text, p_source_type text,
  p_employee_master_record_id uuid, p_replay_key text
)
returns void
language plpgsql
as $$
begin
  if p_existing.case_type is distinct from p_case_type
     or p_existing.source_type is distinct from p_source_type
     or (p_source_type = 'existing_employee' and p_existing.employee_master_record_id is distinct from p_employee_master_record_id)
  then
    raise exception 'idempotency_key_conflict: idempotency key/source % was already used for a different case request', p_replay_key
      using errcode = 'unique_violation';
  end if;
end;
$$;

-- Read-only preview (section 14 "preview" API) -- no mutation, computes what
-- app.start_onboarding_case would do: whether the conversion is already-done
-- (idempotent replay), which checklist template version would apply, and how
-- many tasks it carries.
create function app.preview_onboarding_case_start(
  p_tenant_id uuid, p_case_type text, p_source_type text, p_source_job_offer_id uuid,
  p_employee_master_record_id uuid, p_actor_auth_user_id uuid
)
returns table (
  would_reuse_existing_employee boolean, resolved_employee_master_record_id uuid,
  resolved_template_version_id uuid, resolved_template_task_count integer,
  offer_status text, offer_application_id uuid, candidate_full_name text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.job_offers;
  v_application app.job_applications;
  v_candidate app.candidates;
  v_existing_employee_id uuid;
  v_template_version_id uuid;
  v_task_count integer;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_case_type not in ('onboarding', 'offboarding', 'transfer') then
    raise exception 'invalid_case_type: %', p_case_type using errcode = 'check_violation';
  end if;

  if p_source_type = 'job_offer' then
    if p_source_job_offer_id is null then
      raise exception 'source_job_offer_id_required: source_type job_offer requires source_job_offer_id' using errcode = 'check_violation';
    end if;
    select * into v_offer from app.job_offers where id = p_source_job_offer_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'offer_not_found: %', p_source_job_offer_id using errcode = 'no_data_found';
    end if;
    select * into v_application from app.job_applications where id = v_offer.application_id;
    select * into v_candidate from app.candidates where id = v_application.candidate_id;
    select employee_master_record_id into v_existing_employee_id from app.onboarding_offboarding_cases where source_job_offer_id = p_source_job_offer_id limit 1;
  end if;

  select tv.id into v_template_version_id
  from app.onboarding_checklist_template_versions tv
  join app.onboarding_checklist_templates t on t.id = tv.template_id
  where t.tenant_id = p_tenant_id and t.case_type = p_case_type and tv.status = 'published'
  order by tv.published_at desc
  limit 1;

  select count(*) into v_task_count from app.onboarding_checklist_template_tasks where template_version_id = v_template_version_id;

  return query select
    (v_existing_employee_id is not null),
    v_existing_employee_id,
    v_template_version_id,
    coalesce(v_task_count, 0),
    v_offer.status,
    v_offer.application_id,
    v_candidate.full_name;
end;
$$;

comment on function app.preview_onboarding_case_start is 'HRT-277 section 14 "preview" API -- read-only, no mutation. would_reuse_existing_employee=true tells the caller a case for this exact source_job_offer_id already started the conversion (acceptance criterion 1, no duplicate).';

create function app.start_onboarding_case(
  p_tenant_id uuid, p_case_type text, p_source_type text,
  p_source_job_offer_id uuid, p_employee_master_record_id uuid,
  p_checklist_template_version_id uuid, p_effective_date date,
  p_full_name text, p_employment_type text, p_work_email text, p_personal_email text,
  p_personal_phone text, p_national_id_number text, p_date_of_birth date, p_gender text,
  p_company_org_unit_id uuid, p_branch_org_unit_id uuid, p_department_org_unit_id uuid,
  p_position_title text, p_manager_employee_id uuid,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_offboarding_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.onboarding_offboarding_cases;
  v_offer app.job_offers;
  v_application app.job_applications;
  v_candidate app.candidates;
  v_offer_version app.job_offer_versions;
  v_employee app.employees;
  v_case app.onboarding_offboarding_cases;
  v_template_version app.onboarding_checklist_template_versions;
  v_template app.onboarding_checklist_templates;
  v_task app.onboarding_checklist_template_tasks;
  v_case_task_id uuid;
  v_key_to_case_task_id jsonb := '{}'::jsonb;
  v_dep record;
  v_source_candidate_id uuid;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_case_type not in ('onboarding', 'offboarding', 'transfer') then
    raise exception 'invalid_case_type: %', p_case_type using errcode = 'check_violation';
  end if;
  if p_source_type not in ('job_offer', 'direct_hire', 'existing_employee') then
    raise exception 'invalid_source_type: %', p_source_type using errcode = 'check_violation';
  end if;

  -- Idempotent replay by the case's own idempotency_key (a caller-supplied key,
  -- used for the direct_hire/existing_employee paths; the job_offer path ALSO
  -- gets a structural guarantee via onboarding_offboarding_cases_source_offer_
  -- unique, checked below). Full-tuple compared (taxonomy C-01), not merely
  -- key-matched -- a same-key/different-request call raises idempotency_key_
  -- conflict instead of silently returning the first case.
  if p_idempotency_key is not null then
    select * into v_existing from app.onboarding_offboarding_cases where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      perform app.assert_onboarding_case_start_idempotent_replay(v_existing, p_case_type, p_source_type, p_employee_master_record_id, p_idempotency_key);
      return v_existing;
    end if;
  end if;

  if p_source_type = 'job_offer' then
    if p_source_job_offer_id is null then
      raise exception 'source_job_offer_id_required: source_type job_offer requires source_job_offer_id' using errcode = 'check_violation';
    end if;

    -- Structural idempotency for the job_offer path: onboarding_offboarding_
    -- cases_source_offer_unique means a second start against the SAME offer
    -- always returns the FIRST case, never a duplicate (acceptance criterion 1)
    -- -- checked explicitly here (not only relying on the exception handler
    -- below) so a caller who omits p_idempotency_key still gets the safe reuse.
    -- Full-tuple compared (taxonomy C-01): a caller who reuses the SAME
    -- accepted offer but supplies a mismatched case_type (e.g. 'offboarding'
    -- against a source_type that only ever creates 'onboarding' cases) is
    -- rejected, never silently handed back the pre-existing, differently-typed
    -- case.
    select * into v_existing from app.onboarding_offboarding_cases where source_job_offer_id = p_source_job_offer_id;
    if found then
      perform app.assert_onboarding_case_start_idempotent_replay(v_existing, p_case_type, p_source_type, null, p_source_job_offer_id::text);
      return v_existing;
    end if;

    select * into v_offer from app.job_offers where id = p_source_job_offer_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'offer_not_found: %', p_source_job_offer_id using errcode = 'no_data_found';
    end if;
    if v_offer.status <> 'accepted' then
      raise exception 'offer_not_accepted: offer % is %, only an accepted offer can start an onboarding case', p_source_job_offer_id, v_offer.status
        using errcode = 'check_violation';
    end if;
    if p_case_type <> 'onboarding' then
      raise exception 'invalid_case_type_for_source: source_type job_offer requires case_type onboarding, got %', p_case_type using errcode = 'check_violation';
    end if;

    select * into v_application from app.job_applications where id = v_offer.application_id;
    select * into v_candidate from app.candidates where id = v_application.candidate_id;
    select * into v_offer_version from app.job_offer_versions where id = v_offer.current_version_id;
    v_source_candidate_id := v_candidate.id;

    v_employee := app.create_employee_draft(
      p_tenant_id,
      coalesce(nullif(trim(p_full_name), ''), v_candidate.full_name),
      coalesce(p_employment_type, app.map_offer_employment_type_to_employee(v_offer_version.employment_type)),
      p_work_email,
      coalesce(p_personal_email, v_candidate.email),
      coalesce(p_personal_phone, v_candidate.phone),
      coalesce(p_national_id_number, v_candidate.national_id_number),
      coalesce(p_date_of_birth, v_candidate.date_of_birth),
      p_gender,
      coalesce(p_effective_date, v_offer_version.effective_date),
      p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id,
      coalesce(nullif(trim(p_position_title), ''), v_offer_version.title),
      p_manager_employee_id,
      null,
      null,
      'hr_created',
      'hrt277-onboarding-conversion:' || p_source_job_offer_id::text,
      p_actor_auth_user_id, p_actor_label
    );
  elsif p_source_type = 'direct_hire' then
    if p_case_type <> 'onboarding' then
      raise exception 'invalid_case_type_for_source: source_type direct_hire requires case_type onboarding, got %', p_case_type using errcode = 'check_violation';
    end if;
    if p_full_name is null or length(trim(p_full_name)) = 0 then
      raise exception 'invalid_full_name: direct_hire requires full_name' using errcode = 'check_violation';
    end if;
    if p_employment_type is null then
      raise exception 'invalid_employment_type: direct_hire requires employment_type' using errcode = 'check_violation';
    end if;
    if p_idempotency_key is null then
      raise exception 'idempotency_key_required: direct_hire requires a caller-supplied idempotency_key' using errcode = 'check_violation';
    end if;

    v_employee := app.create_employee_draft(
      p_tenant_id, p_full_name, p_employment_type, p_work_email, p_personal_email, p_personal_phone,
      p_national_id_number, p_date_of_birth, p_gender, p_effective_date,
      p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id, p_position_title, p_manager_employee_id,
      null, null, 'hr_created', 'hrt277-direct-hire:' || p_idempotency_key,
      p_actor_auth_user_id, p_actor_label
    );
  else -- existing_employee (offboarding, transfer, or onboarding-rehire)
    if p_employee_master_record_id is null then
      raise exception 'employee_master_record_id_required: source_type existing_employee requires employee_master_record_id' using errcode = 'check_violation';
    end if;
    select * into v_employee from app.employees where master_record_id = p_employee_master_record_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'employee_not_found: %', p_employee_master_record_id using errcode = 'no_data_found';
    end if;
    if p_case_type = 'offboarding' and v_employee.lifecycle_status not in ('active', 'on_leave', 'suspended') then
      raise exception 'invalid_transition: employee % is %, cannot start an offboarding case', p_employee_master_record_id, v_employee.lifecycle_status
        using errcode = 'check_violation';
    end if;
    if p_case_type = 'transfer' and v_employee.lifecycle_status not in ('active', 'on_leave') then
      raise exception 'invalid_transition: employee % is %, cannot start a transfer case', p_employee_master_record_id, v_employee.lifecycle_status
        using errcode = 'check_violation';
    end if;
  end if;

  -- Resolve checklist template version: caller-supplied (validated: published,
  -- correct tenant/case_type), or the tenant's current published default for
  -- this case_type. Locked in on the case (RPD-040).
  if p_checklist_template_version_id is not null then
    select * into v_template_version from app.onboarding_checklist_template_versions where id = p_checklist_template_version_id;
    if not found or v_template_version.tenant_id <> p_tenant_id or v_template_version.status <> 'published' then
      raise exception 'template_version_not_available: % is not a published template version for this tenant', p_checklist_template_version_id
        using errcode = 'check_violation';
    end if;
    select * into v_template from app.onboarding_checklist_templates where id = v_template_version.template_id;
    if v_template.case_type <> p_case_type then
      raise exception 'template_case_type_mismatch: template version % is for case_type %, not %', p_checklist_template_version_id, v_template.case_type, p_case_type
        using errcode = 'check_violation';
    end if;
  else
    select tv.* into v_template_version
    from app.onboarding_checklist_template_versions tv
    join app.onboarding_checklist_templates t on t.id = tv.template_id
    where t.tenant_id = p_tenant_id and t.case_type = p_case_type and tv.status = 'published'
    order by tv.published_at desc
    limit 1;
    if not found then
      raise exception 'no_published_checklist_template: tenant % has no published % checklist template', p_tenant_id, p_case_type
        using errcode = 'check_violation';
    end if;
  end if;

  begin
    insert into app.onboarding_offboarding_cases (
      tenant_id, case_type, source_type, source_job_offer_id, source_job_application_id, source_candidate_id,
      employee_master_record_id, checklist_template_version_id, status, effective_date, initiated_by,
      idempotency_key, created_by
    ) values (
      p_tenant_id, p_case_type, p_source_type, p_source_job_offer_id, v_application.id, v_source_candidate_id,
      v_employee.master_record_id, v_template_version.id, 'active', coalesce(p_effective_date, v_offer_version.effective_date), p_actor_label,
      p_idempotency_key, p_actor_label
    )
    returning * into v_case;
  exception
    when unique_violation then
      -- Concurrent-race recovery (taxonomy C-01: full-tuple compared, not
      -- merely key/offer-matched, mirroring the pre-insert checks above).
      if p_source_job_offer_id is not null then
        select * into v_case from app.onboarding_offboarding_cases where source_job_offer_id = p_source_job_offer_id;
        if found then
          perform app.assert_onboarding_case_start_idempotent_replay(v_case, p_case_type, p_source_type, null, p_source_job_offer_id::text);
          return v_case;
        end if;
      end if;
      if p_idempotency_key is not null then
        select * into v_case from app.onboarding_offboarding_cases where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
        if found then
          perform app.assert_onboarding_case_start_idempotent_replay(v_case, p_case_type, p_source_type, p_employee_master_record_id, p_idempotency_key);
          return v_case;
        end if;
      end if;
      raise;
  end;

  -- Instantiate tasks (copied at instantiation -- a later template edit never
  -- retroactively changes this case, section 24's own versioning rule).
  for v_task in select * from app.onboarding_checklist_template_tasks where template_version_id = v_template_version.id order by sort_order loop
    insert into app.onboarding_case_tasks (
      case_id, tenant_id, template_task_key, title, description, task_type, handoff_category,
      owner_type, is_mandatory, due_at, sort_order
    ) values (
      v_case.id, p_tenant_id, v_task.task_key, v_task.title, v_task.description, v_task.task_type, v_task.handoff_category,
      v_task.owner_type, v_task.is_mandatory, now() + make_interval(days => v_task.sla_days), v_task.sort_order
    )
    returning id into v_case_task_id;
    v_key_to_case_task_id := v_key_to_case_task_id || jsonb_build_object(v_task.task_key, v_case_task_id::text);
  end loop;

  for v_dep in select * from app.onboarding_checklist_template_task_dependencies where template_version_id = v_template_version.id loop
    insert into app.onboarding_case_task_dependencies (case_id, tenant_id, task_id, depends_on_task_id)
    values (
      v_case.id, p_tenant_id,
      (v_key_to_case_task_id ->> v_dep.task_key)::uuid,
      (v_key_to_case_task_id ->> v_dep.depends_on_task_key)::uuid
    );
  end loop;

  -- A task with an incomplete dependency starts blocked (section 15 "due/
  -- blocked state"), computed once at instantiation from a real dependency
  -- edge, then re-evaluated at every completion (app.complete_onboarding_task/
  -- app.waive_onboarding_task both re-derive downstream blocked state).
  update app.onboarding_case_tasks t
  set status = 'blocked'
  where t.case_id = v_case.id and t.status = 'pending'
    and exists (select 1 from app.onboarding_case_task_dependencies d where d.task_id = t.id);

  insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_case.id, p_tenant_id, 'start', null, 'active', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'start_onboarding_case',
    'app.onboarding_offboarding_cases', v_case.id, 'success', null, null, app.onboarding_case_audit_projection(v_case)
  );

  return v_case;
end;
$$;

comment on function app.start_onboarding_case is 'HRT-277: the ADR-0023 Part B conversion. For source_type=job_offer, calls app.create_employee_draft (HRT-274) with a deterministic idempotency_key derived from source_job_offer_id -- retrying against the SAME accepted offer always resolves to the SAME employee (never a duplicate) via TWO independent guards: this function''s own pre-check against onboarding_offboarding_cases_source_offer_unique, and create_employee_draft''s own idempotency-key replay. Never inserts into app.master_records/app.employees/app.users directly -- always through the existing governed RPC.';

-- ===========================================================================
-- 9. Task lifecycle -- assign/complete/waive/reopen (section 14's own API
--    surface), plus the two specialized Platform-identity-authority RPCs.
-- ===========================================================================

-- Re-derives blocked/pending for every not-yet-completed task in a case, from
-- its own dependency edges. Called after any task reaches a terminal
-- (completed/waived) state and after reopen. Idempotent: safe to call
-- repeatedly, never regresses an already in_progress/completed/waived task.
create function app.recompute_onboarding_case_task_blocked_state(p_case_id uuid)
returns void
language plpgsql
as $$
begin
  update app.onboarding_case_tasks t
  set status = 'blocked'
  where t.case_id = p_case_id
    and t.status = 'pending'
    and exists (
      select 1 from app.onboarding_case_task_dependencies d
      join app.onboarding_case_tasks dep on dep.id = d.depends_on_task_id
      where d.task_id = t.id and dep.status not in ('completed', 'waived')
    );

  update app.onboarding_case_tasks t
  set status = 'pending'
  where t.case_id = p_case_id
    and t.status = 'blocked'
    and not exists (
      select 1 from app.onboarding_case_task_dependencies d
      join app.onboarding_case_tasks dep on dep.id = d.depends_on_task_id
      where d.task_id = t.id and dep.status not in ('completed', 'waived')
    );
end;
$$;

-- Shared resolve+authority+lock preamble every task RPC below repeats
-- identically -- folds a non-member/cross-tenant caller into the same
-- not-found a genuinely missing task would produce (taxonomy C-05). Single
-- composite OUT parameter (matching app.assert_employee_editable_for_child_
-- crud's own established, directly-assignable "v_x := app.func(...)" shape,
-- HRT-274) -- the task row itself already carries tenant_id, so callers never
-- need the case row separately. Lock order (documented per taxonomy C-21):
-- case row FIRST, task row SECOND -- every sibling function in this migration
-- that touches both goes through this one preamble, so no two functions in
-- this file can ever take these two locks in opposite order.
create function app.resolve_onboarding_case_task_for_write(
  p_case_id uuid, p_task_id uuid, p_actor_auth_user_id uuid, p_required_action text,
  out v_task app.onboarding_case_tasks
)
language plpgsql
as $$
declare
  v_case app.onboarding_offboarding_cases;
  v_decision app.rbac_decision;
begin
  select * into v_case from app.onboarding_offboarding_cases where id = p_case_id for update;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  select * into v_task from app.onboarding_case_tasks where id = p_task_id and case_id = p_case_id for update;
  if not found then
    raise exception 'task_not_found: % is not a task on case %', p_task_id, p_case_id using errcode = 'no_data_found';
  end if;

  if p_required_action is not null then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'HRS', p_required_action);
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks HRS:% (%) for tenant %', p_actor_auth_user_id, p_required_action, v_decision.reason, v_case.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_case.status not in ('active', 'pending_finalize_approval') then
    raise exception 'case_not_active: case % is %, tasks cannot be modified', p_case_id, v_case.status using errcode = 'check_violation';
  end if;
end;
$$;

create function app.assign_onboarding_task(
  p_case_id uuid, p_task_id uuid, p_expected_version integer, p_owner_auth_user_id uuid,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Edit');

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_owner_auth_user_id is not null and not app.has_active_tenant_membership(v_task.tenant_id, p_owner_auth_user_id) then
    raise exception 'owner_not_found: % is not an active member of tenant %', p_owner_auth_user_id, v_task.tenant_id using errcode = 'no_data_found';
  end if;

  update app.onboarding_case_tasks
  set owner_auth_user_id = p_owner_auth_user_id
  where id = p_task_id and record_version = p_expected_version
  returning * into v_task;
  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_onboarding_task',
    'app.onboarding_case_tasks', v_task.id, 'success', null, null, app.onboarding_case_task_audit_projection(v_task)
  );

  return v_task;
end;
$$;

comment on function app.assign_onboarding_task is 'HRT-277: calls the shared resolve+lock+authority preamble (app.resolve_onboarding_case_task_for_write, a single composite-OUT-parameter function, directly assignable via ":=" exactly like app.assert_employee_editable_for_child_crud, HRT-274) -- the same real row locks (case then task, matching every other task RPC in this migration, avoiding a C-21-class inconsistent lock order across sibling functions) are taken exactly once.';

-- Generic completion -- document/handoff/generic task types. Blocked by an
-- incomplete non-waived dependency (section 21's own "completes verified ...
-- handoffs"). Evidence (note and/or file) is accepted but not itself mandated
-- by this generic RPC -- a template author who wants a HARD evidence
-- requirement enforces it at waive-authority-review time (Override-gated
-- waive is always available as the escape hatch, section 24).
create function app.complete_onboarding_task(
  p_case_id uuid, p_task_id uuid, p_expected_version integer,
  p_evidence_note text, p_evidence_file_id uuid,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
  v_file app.files;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Edit');

  if v_task.task_type in ('access_provisioning', 'access_revocation') then
    raise exception 'wrong_completion_path: task % is % and must be completed via app.request_onboarding_access_provisioning/revocation', p_task_id, v_task.task_type
      using errcode = 'check_violation';
  end if;

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_task.status not in ('pending', 'in_progress', 'reopened') then
    raise exception 'invalid_transition: task % is %, cannot be completed', p_task_id, v_task.status using errcode = 'check_violation';
  end if;

  if v_task.status = 'blocked' then
    raise exception 'task_blocked: task % has an incomplete dependency', p_task_id using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from app.onboarding_case_task_dependencies d
    join app.onboarding_case_tasks dep on dep.id = d.depends_on_task_id
    where d.task_id = p_task_id and dep.status not in ('completed', 'waived')
  ) then
    raise exception 'task_blocked: task % has an incomplete dependency', p_task_id using errcode = 'check_violation';
  end if;

  -- Re-validate tenant, record scope, and scan status at THIS accepting RPC
  -- (taxonomy C-10) -- never trust a caller's prior upload success as still
  -- valid.
  if p_evidence_file_id is not null then
    select * into v_file from app.files where id = p_evidence_file_id;
    if not found or v_file.tenant_id <> v_task.tenant_id or v_file.record_type <> 'onboarding_case_task' or v_file.record_id <> p_task_id then
      raise exception 'evidence_file_not_found: file % is not a valid evidence file for task %', p_evidence_file_id, p_task_id using errcode = 'no_data_found';
    end if;
    if v_file.malware_scan_status = 'infected' then
      raise exception 'evidence_file_infected: file % failed malware scanning and cannot be attached', p_evidence_file_id using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'evidence_file_not_scanned: file % has not cleared malware scanning (status %)', p_evidence_file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  update app.onboarding_case_tasks
  set status = 'completed', completed_at = now(), completed_by = p_actor_label,
      evidence_note = coalesce(p_evidence_note, evidence_note), evidence_file_id = coalesce(p_evidence_file_id, evidence_file_id)
  where id = p_task_id and record_version = p_expected_version
  returning * into v_task;
  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.recompute_onboarding_case_task_blocked_state(p_case_id);

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'complete_onboarding_task',
    'app.onboarding_case_tasks', v_task.id, 'success', null, null, app.onboarding_case_task_audit_projection(v_task)
  );

  return v_task;
end;
$$;

create function app.waive_onboarding_task(
  p_case_id uuid, p_task_id uuid, p_expected_version integer, p_waive_reason text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Override');

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_task.status in ('completed', 'waived') then
    raise exception 'invalid_transition: task % is already %, cannot be waived', p_task_id, v_task.status using errcode = 'check_violation';
  end if;

  if p_waive_reason is null or length(trim(p_waive_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to waive a task' using errcode = 'check_violation';
  end if;

  update app.onboarding_case_tasks
  set status = 'waived', waived_at = now(), waived_by = p_actor_label, waive_reason = p_waive_reason
  where id = p_task_id and record_version = p_expected_version
  returning * into v_task;
  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.recompute_onboarding_case_task_blocked_state(p_case_id);

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'waive_onboarding_task',
    'app.onboarding_case_tasks', v_task.id, 'success', p_waive_reason, null, app.onboarding_case_task_audit_projection(v_task)
  );

  return v_task;
end;
$$;

comment on function app.waive_onboarding_task is 'HRT-277 section 24: waive requires a reason, HRS:Override authority (deliberately a HIGHER bar than the HRS:Edit that completes a task normally -- a mandatory task bypassed without ever being done is exactly the kind of exception the taxonomy''s own C-18 class (''maker-checker enforced on the happy path only'') warns about), and audit. Works on ANY task status short of a terminal one, including a currently-blocked task -- waiving is how HR resolves a dependency that can never legitimately complete.';

create function app.reopen_onboarding_task(
  p_case_id uuid, p_task_id uuid, p_expected_version integer, p_reason text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Edit');

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_task.status not in ('completed', 'waived') then
    raise exception 'invalid_transition: task % is %, only a completed or waived task can be reopened', p_task_id, v_task.status using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reopen a task' using errcode = 'check_violation';
  end if;

  update app.onboarding_case_tasks
  set status = 'reopened', completed_at = null, completed_by = null, waived_at = null, waived_by = null, waive_reason = null
  where id = p_task_id and record_version = p_expected_version
  returning * into v_task;
  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.onboarding_case_events (case_id, tenant_id, event_type, notes, actor_auth_user_id, actor_label)
  values (p_case_id, v_task.tenant_id, 'task_reopened', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_onboarding_task',
    'app.onboarding_case_tasks', v_task.id, 'success', p_reason, null, app.onboarding_case_task_audit_projection(v_task)
  );

  return v_task;
end;
$$;

comment on function app.reopen_onboarding_task is 'HRT-277 section 22/23: only reachable while the CASE itself is not finalized/cancelled (app.resolve_onboarding_case_task_for_write''s own case-status gate) -- a finalized case''s history is immutable, matching section 24''s "never loses required business history".';

-- ===========================================================================
-- 10. Platform-identity-authority writes -- the two RPCs this whole prompt is
--     chartered around (section 16). Every real grant/revoke goes through the
--     existing PLT-107/110/111 mechanisms, never a direct write to app.users/
--     app.role_assignments (mandatory reading item 6).
-- ===========================================================================

create function app.request_onboarding_access_provisioning(
  p_case_id uuid, p_task_id uuid, p_expected_version integer,
  p_target_auth_user_id uuid, p_role_version_ids uuid[], p_org_unit_id uuid,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
  v_case app.onboarding_offboarding_cases;
  v_employee app.employees;
  v_user app.users;
  v_role_version_id uuid;
  v_request app.onboarding_task_provisioning_requests;
  v_job app.jobs;
  v_roles_granted integer := 0;
  v_roles_deferred integer := 0;
  v_completion_note text;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Edit');

  if v_task.task_type <> 'access_provisioning' then
    raise exception 'wrong_completion_path: task % is %, not access_provisioning', p_task_id, v_task.task_type using errcode = 'check_violation';
  end if;

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_task.status not in ('pending', 'in_progress', 'reopened') then
    raise exception 'invalid_transition: task % is %, cannot request provisioning', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if v_task.status = 'blocked' then
    raise exception 'task_blocked: task % has an incomplete dependency', p_task_id using errcode = 'check_violation';
  end if;

  select * into v_case from app.onboarding_offboarding_cases where id = p_case_id;
  if v_case.employee_master_record_id is null then
    raise exception 'case_has_no_employee: case % has no linked employee, cannot provision access', p_case_id using errcode = 'check_violation';
  end if;
  select * into v_employee from app.employees where master_record_id = v_case.employee_master_record_id;

  insert into app.onboarding_task_provisioning_requests (case_id, task_id, tenant_id, request_type, target_auth_user_id, requested_role_version_ids, org_unit_id, requested_by)
  values (p_case_id, p_task_id, v_task.tenant_id, 'grant_access', p_target_auth_user_id, coalesce(p_role_version_ids, '{}'::uuid[]), p_org_unit_id, p_actor_label)
  returning * into v_request;

  if p_target_auth_user_id is not null then
    -- Real, synchronous, governed grant -- section 16 "Platform identity
    -- authority", never a direct app.users/app.role_assignments write.
    v_user := app.invite_user(v_task.tenant_id, p_target_auth_user_id, coalesce(v_employee.work_email, v_employee.personal_email, v_employee.full_name || '@pending.invite'), v_employee.full_name, p_org_unit_id, p_actor_label, now() + interval '14 days');

    if v_employee.user_id is null then
      perform app.link_employee_user(v_employee.master_record_id, v_employee.record_version, v_user.id, p_actor_auth_user_id, p_actor_label);
    elsif v_employee.user_id <> v_user.id then
      raise exception 'employee_already_linked: employee % is already linked to a different user', v_employee.master_record_id using errcode = 'check_violation';
    end if;

    -- app.assign_role (PLT-111) requires the target app.users row to already
    -- be status='active' -- a freshly-invited user is 'invited' until they
    -- accept the invite themselves. This RPC never force-activates an
    -- unconfirmed account (that would be a real, undisclosed authentication
    -- bypass) -- roles are granted immediately only when the target identity
    -- is ALREADY active (the realistic "existing tenant member converting to
    -- an employee" case); otherwise they are deferred and disclosed in the
    -- task's own evidence_note, never silently dropped.
    if v_user.status = 'active' then
      foreach v_role_version_id in array coalesce(p_role_version_ids, '{}'::uuid[]) loop
        perform app.assign_role(v_task.tenant_id, v_role_version_id, p_target_auth_user_id, p_actor_auth_user_id, p_actor_label);
        v_roles_granted := v_roles_granted + 1;
      end loop;
    else
      v_roles_deferred := coalesce(array_length(p_role_version_ids, 1), 0);
    end if;

    update app.onboarding_task_provisioning_requests
    set status = 'completed', result_user_id = v_user.id, completed_at = now()
    where id = v_request.id;

    v_completion_note := 'Platform access granted: user ' || v_user.id::text || ' (status ' || v_user.status || '), ' || v_roles_granted || ' role(s) granted';
    if v_roles_deferred > 0 then
      v_completion_note := v_completion_note || ', ' || v_roles_deferred || ' role(s) deferred until the user accepts their invite (re-run once active)';
    end if;

    -- Async reconciliation/dispatch record (section 17) -- e.g. a downstream
    -- welcome-email/credentials-handoff adapter would claim this job. Reuses
    -- job_type='integration_sync' (decision 8's own sibling reasoning: adding a
    -- domain-specific job_type would widen app.generic_job_types()' shared,
    -- cross-domain single source of truth, out of this single-prompt batch's
    -- own mandate).
    v_job := app.enqueue_job(v_task.tenant_id, 'integration_sync', jsonb_build_object('onboarding_task_provisioning_request_id', v_request.id, 'case_id', p_case_id, 'task_id', p_task_id, 'user_id', v_user.id), 0, 'hrt277-provisioning:' || v_request.id::text, 3, p_actor_auth_user_id, p_actor_label);
    update app.onboarding_task_provisioning_requests set job_id = v_job.job_id where id = v_request.id;

    update app.onboarding_case_tasks
    set status = 'completed', completed_at = now(), completed_by = p_actor_label,
        evidence_note = coalesce(evidence_note, v_completion_note)
    where id = p_task_id and record_version = p_expected_version
    returning * into v_task;
  else
    -- section 22 "preboarding without user access" -- no auth identity
    -- resolved yet. The request is recorded (an acknowledged handoff, never an
    -- assumed success, section 14) and the task moves to in_progress, awaiting
    -- a follow-up call with a resolved p_target_auth_user_id.
    update app.onboarding_case_tasks
    set status = 'in_progress'
    where id = p_task_id and record_version = p_expected_version
    returning * into v_task;
  end if;

  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.recompute_onboarding_case_task_blocked_state(p_case_id);

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_onboarding_access_provisioning',
    'app.onboarding_case_tasks', v_task.id, 'success', null, null, app.onboarding_case_task_audit_projection(v_task) || jsonb_build_object('provisioning_request_id', v_request.id)
  );

  return v_task;
end;
$$;

comment on function app.request_onboarding_access_provisioning is 'HRT-277 section 16: the real Platform-identity-authority grant. When p_target_auth_user_id is supplied (the caller already resolved a Platform auth identity for the new hire -- typically via the standing, repository-wide, disclosed out-of-band cold-start invite gap this checkpoint does not attempt to close), performs a REAL synchronous grant via app.invite_user/app.link_employee_user/app.assign_role (never a direct app.users/app.role_assignments write) and completes the task. Otherwise records the request and leaves the task in_progress -- section 22''s own "preboarding without user access" alternative flow, never a fabricated success.';

create function app.request_onboarding_access_revocation(
  p_case_id uuid, p_task_id uuid, p_expected_version integer,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_case_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_task app.onboarding_case_tasks;
  v_case app.onboarding_offboarding_cases;
  v_employee app.employees;
  v_request app.onboarding_task_provisioning_requests;
  v_job app.jobs;
  v_note text;
begin
  v_task := app.resolve_onboarding_case_task_for_write(p_case_id, p_task_id, p_actor_auth_user_id, 'Override');

  if v_task.task_type <> 'access_revocation' then
    raise exception 'wrong_completion_path: task % is %, not access_revocation', p_task_id, v_task.task_type using errcode = 'check_violation';
  end if;

  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_task.status not in ('pending', 'in_progress', 'reopened') then
    raise exception 'invalid_transition: task % is %, cannot request revocation', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if v_task.status = 'blocked' then
    raise exception 'task_blocked: task % has an incomplete dependency', p_task_id using errcode = 'check_violation';
  end if;

  select * into v_case from app.onboarding_offboarding_cases where id = p_case_id;
  select * into v_employee from app.employees where master_record_id = v_case.employee_master_record_id;

  insert into app.onboarding_task_provisioning_requests (case_id, task_id, tenant_id, request_type, target_auth_user_id, requested_by)
  values (p_case_id, p_task_id, v_task.tenant_id, 'revoke_access', null, p_actor_label)
  returning * into v_request;

  if v_employee.user_id is not null then
    -- Real, governed revocation -- app.transition_user_status already cascades
    -- both the underlying PLT-107 identity linkage AND every active PLT-108
    -- principal membership (its own migration, 20260716102620:271-285), so no
    -- separate role-revocation loop is needed here.
    perform app.transition_user_status(v_employee.user_id, 'revoked', 'employee offboarded via case ' || p_case_id::text, p_actor_label);

    update app.onboarding_task_provisioning_requests set status = 'completed', result_user_id = v_employee.user_id, completed_at = now() where id = v_request.id;
    v_note := 'Platform access revoked for user ' || v_employee.user_id::text;

    v_job := app.enqueue_job(v_task.tenant_id, 'integration_sync', jsonb_build_object('onboarding_task_provisioning_request_id', v_request.id, 'case_id', p_case_id, 'task_id', p_task_id, 'user_id', v_employee.user_id), 0, 'hrt277-revocation:' || v_request.id::text, 3, p_actor_auth_user_id, p_actor_label);
    update app.onboarding_task_provisioning_requests set job_id = v_job.job_id where id = v_request.id;
  else
    update app.onboarding_task_provisioning_requests set status = 'completed', completed_at = now() where id = v_request.id;
    v_note := 'No linked Platform user for this employee -- nothing to revoke.';
  end if;

  update app.onboarding_case_tasks
  set status = 'completed', completed_at = now(), completed_by = p_actor_label, evidence_note = coalesce(evidence_note, v_note)
  where id = p_task_id and record_version = p_expected_version
  returning * into v_task;
  if not found then
    raise exception 'stale_version: task % target row was concurrently modified (expected version %)', p_task_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.recompute_onboarding_case_task_blocked_state(p_case_id);

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_onboarding_access_revocation',
    'app.onboarding_case_tasks', v_task.id, 'success', null, null, app.onboarding_case_task_audit_projection(v_task) || jsonb_build_object('provisioning_request_id', v_request.id)
  );

  return v_task;
end;
$$;

comment on function app.request_onboarding_access_revocation is 'HRT-277 section 16/24: the real Platform-identity-authority revoke. Reuses app.transition_user_status (PLT-110) directly -- never a direct app.users/app.role_assignments write. HRS:Override-gated (the same bar as app.terminate_employee) since this is an immediate-security-relevant action (section 22''s own "immediate security offboarding" alternative flow).';

-- ===========================================================================
-- 11. Case finalize -- PLT-123 approval routing (mandatory reading item 5/9),
--     with the hardened terminal-UPDATE guard and the cancel-path closure
--     applied from THIS, the FIRST, migration -- HRT-276's own Tier C review
--     round (20260730870000, findings 7/8) had to retrofit both after a real,
--     live-reproduced two-process race; this checkpoint does not repeat
--     either class of bug.
-- ===========================================================================

create function app.submit_onboarding_case_for_finalize_approval(
  p_case_id uuid, p_expected_version integer, p_exit_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_offboarding_cases
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_case app.onboarding_offboarding_cases;
  v_employee app.employees;
  v_incomplete_mandatory integer;
  v_approval_config_version_id uuid;
  v_request app.approval_requests;
begin
  select * into v_case from app.onboarding_offboarding_cases where id = p_case_id for update;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_case.record_version <> p_expected_version then
    raise exception 'stale_version: case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_case.status <> 'active' then
    raise exception 'invalid_transition: case % is %, only an active case can be submitted for finalize approval', p_case_id, v_case.status
      using errcode = 'check_violation';
  end if;

  -- Mandatory checklist gate (acceptance criterion 2: "mandatory checklist and
  -- downstream acknowledgements gate finalization").
  select count(*) into v_incomplete_mandatory
  from app.onboarding_case_tasks
  where case_id = p_case_id and is_mandatory and status not in ('completed', 'waived');
  if v_incomplete_mandatory > 0 then
    raise exception 'mandatory_tasks_incomplete: case % has % incomplete mandatory task(s)', p_case_id, v_incomplete_mandatory
      using errcode = 'check_violation';
  end if;

  -- Precondition-check-only against the employee's own governed lifecycle FSM
  -- (decision 1) -- never chained/driven from this function.
  if v_case.employee_master_record_id is not null then
    select * into v_employee from app.employees where master_record_id = v_case.employee_master_record_id;
    if v_case.case_type = 'onboarding' and v_employee.lifecycle_status <> 'active' then
      raise exception 'employee_not_active_yet: employee % is %, must reach active via the standard employee lifecycle (submit/decide/activate, or app.rehire_employee) before this case can finalize', v_case.employee_master_record_id, v_employee.lifecycle_status
        using errcode = 'check_violation';
    end if;
    if v_case.case_type = 'offboarding' and v_employee.lifecycle_status not in ('terminated', 'archived') then
      raise exception 'employee_not_terminated_yet: employee % is %, must be terminated (app.terminate_employee) before this case can finalize', v_case.employee_master_record_id, v_employee.lifecycle_status
        using errcode = 'check_violation';
    end if;
  end if;

  -- exit_reason is captured HERE (not at case start -- self-found defect,
  -- fixed before commit: the original CHECK constraint required a non-null
  -- exit_reason at status='active' too, which made starting ANY offboarding
  -- case impossible, since the reason genuinely is not always known yet at
  -- start time). Caller-supplied here takes precedence; the case's own
  -- already-set exit_reason (if a caller already recorded one earlier via a
  -- direct UPDATE-less path) is preserved when this call passes null.
  if v_case.case_type = 'offboarding' then
    if coalesce(p_exit_reason, v_case.exit_reason) is null or length(trim(coalesce(p_exit_reason, v_case.exit_reason))) = 0 then
      raise exception 'exit_reason_required: an offboarding case requires a non-empty exit_reason before finalize submission' using errcode = 'check_violation';
    end if;
  end if;

  select cv.id into v_approval_config_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = 'approval' and co.tenant_id = v_case.tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

  if v_approval_config_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % has no published approval routing definition', v_case.tenant_id
      using errcode = 'check_violation';
  end if;

  v_request := app.request_approval(
    v_approval_config_version_id, v_case.tenant_id, 'onboarding_offboarding_case', p_case_id,
    p_case_id::text || ':finalize:' || p_expected_version::text, p_actor_auth_user_id, p_actor_label
  );

  update app.onboarding_offboarding_cases
  set status = 'pending_finalize_approval', finalize_approval_request_id = v_request.id,
      exit_reason = coalesce(p_exit_reason, exit_reason)
  where id = p_case_id and record_version = p_expected_version
  returning * into v_case;
  if not found then
    raise exception 'stale_version: case % target row was concurrently modified (expected version %)', p_case_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_case_id, v_case.tenant_id, 'submit_finalize_approval', 'active', 'pending_finalize_approval', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_onboarding_case_for_finalize_approval',
    'app.onboarding_offboarding_cases', v_case.id, 'success', null, null, app.onboarding_case_audit_projection(v_case)
  );

  return v_case;
end;
$$;

create function app.decide_onboarding_case_finalize_approval(
  p_request_step_id uuid, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_offboarding_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_case app.onboarding_offboarding_cases;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id using errcode = 'no_data_found';
  end if;

  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'onboarding_offboarding_case' or v_request.entity_id is null then
    raise exception 'not_an_onboarding_case_approval: approval request % is not an onboarding/offboarding case approval', v_request.id using errcode = 'check_violation';
  end if;

  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  -- Hardened terminal-UPDATE guard from the FIRST migration (mandatory reading
  -- item 5, closing HRT-276's own Tier C finding 7/8 class before it recurs):
  -- guarded on (finalize_approval_request_id = v_request.id AND status =
  -- 'pending_finalize_approval') -- if the case is no longer awaiting THIS
  -- specific decision (concurrently cancelled), the whole function raises and
  -- rolls back atomically, including the app.decide_approval_step mutation
  -- just above, rather than silently resurrecting a cancelled case.
  if v_updated_request.status = 'approved' then
    update app.onboarding_offboarding_cases
    set status = 'finalized', finalized_at = now(), finalized_by = p_actor_label
    where id = v_request.entity_id and finalize_approval_request_id = v_request.id and status = 'pending_finalize_approval'
    returning * into v_case;
    if not found then
      raise exception 'case_finalize_no_longer_applicable: case % is no longer awaiting decision on approval request % (concurrently cancelled)', v_request.entity_id, v_request.id
        using errcode = 'serialization_failure';
    end if;
    insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, actor_auth_user_id, actor_label)
    values (v_case.id, v_case.tenant_id, 'finalize', 'pending_finalize_approval', 'finalized', p_actor_auth_user_id, p_actor_label);
  elsif v_updated_request.status = 'rejected' then
    update app.onboarding_offboarding_cases
    set status = 'active', finalize_approval_request_id = null
    where id = v_request.entity_id and finalize_approval_request_id = v_request.id and status = 'pending_finalize_approval'
    returning * into v_case;
    if not found then
      raise exception 'case_finalize_no_longer_applicable: case % is no longer awaiting decision on approval request % (concurrently cancelled)', v_request.entity_id, v_request.id
        using errcode = 'serialization_failure';
    end if;
    insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, notes, actor_auth_user_id, actor_label)
    values (v_case.id, v_case.tenant_id, 'finalize_rejected', 'pending_finalize_approval', 'active', p_reason, p_actor_auth_user_id, p_actor_label);
  else
    select * into v_case from app.onboarding_offboarding_cases where id = v_request.entity_id;
  end if;

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_onboarding_case_finalize_approval',
    'app.onboarding_offboarding_cases', v_case.id, 'success', p_reason, null, app.onboarding_case_audit_projection(v_case)
  );

  return v_case;
end;
$$;

comment on function app.decide_onboarding_case_finalize_approval is 'HRT-277: no domain permission gate of its own -- app.decide_approval_step already gates on tenant membership + eligible-approver identity (mirrors app.decide_job_offer_approval, HRT-276). A rejected finalize returns the case to active, letting HR address the rejection reason and resubmit.';

-- ===========================================================================
-- 12. Cancel -- cancels any in-flight PLT-123 approval request BEFORE
--     cascading to cancelled (mandatory reading item 5, closing HRT-276's own
--     Tier C finding 7/8 class from the first migration). Uses the identical
--     deliberately-PLAIN-read, defer-all-locking-to-the-terminal-UPDATE lock
--     order app.reject_application/app.withdraw_application (HRT-276,
--     20260730870000) established, so this domain does not reintroduce the
--     exact lock-order deadlock that fix's own comment documents finding.
-- ===========================================================================

create function app.cancel_onboarding_case(
  p_case_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_offboarding_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_case app.onboarding_offboarding_cases;
  v_case_plain app.onboarding_offboarding_cases;
begin
  -- Deliberately PLAIN (non-locking) read first, mirroring app.reject_
  -- application's own documented lock-order rationale exactly: app.decide_
  -- onboarding_case_finalize_approval's own call path locks app.approval_
  -- request_steps/app.approval_requests (inside app.decide_approval_step)
  -- BEFORE it ever touches app.onboarding_offboarding_cases (its own terminal
  -- update runs last). Taking a `for update` lock on the case here FIRST,
  -- before calling app.cancel_approval_request (which locks the SAME
  -- approval-engine tables), would lock case-then-approval_request_steps --
  -- the exact REVERSE order of that call path, a real lock-order cycle.
  select * into v_case_plain from app.onboarding_offboarding_cases where id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case_plain.tenant_id, p_actor_auth_user_id) then
    raise exception 'case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case_plain.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case_plain.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_case_plain.status not in ('draft', 'active', 'pending_finalize_approval') then
    raise exception 'invalid_transition: case % is %, cannot be cancelled', p_case_id, v_case_plain.status using errcode = 'check_violation';
  end if;

  if v_case_plain.status = 'pending_finalize_approval' and v_case_plain.finalize_approval_request_id is not null then
    begin
      perform app.cancel_approval_request(v_case_plain.finalize_approval_request_id, p_actor_auth_user_id, p_actor_label, p_reason);
    exception
      when no_data_found or check_violation then
        null;
    end;
  end if;

  update app.onboarding_offboarding_cases
  set status = 'cancelled', cancel_reason = p_reason, cancelled_at = now()
  where id = p_case_id and record_version = p_expected_version
  returning * into v_case;
  if not found then
    raise exception 'stale_version: case % target row was concurrently modified (expected version %)', p_case_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.onboarding_case_events (case_id, tenant_id, event_type, to_status, notes, actor_auth_user_id, actor_label)
  values (p_case_id, v_case.tenant_id, 'cancel', 'cancelled', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_case.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_onboarding_case',
    'app.onboarding_offboarding_cases', v_case.id, 'success', p_reason, null, app.onboarding_case_audit_projection(v_case)
  );

  return v_case;
end;
$$;

comment on function app.cancel_onboarding_case is 'HRT-277 section 23: cancelling never deletes the employee row it may have created/linked (section 24 "never loses required business history") -- a cancelled onboarding leaves the employee at whatever lifecycle_status it already reached; HR separately archives it via app.archive_employee_profile (HRT-274) if desired.';

-- ===========================================================================
-- 13. Rehire -- decision 2: extends HRT-274's own employee lifecycle FSM with
--     a transition it never built (terminated -> active only; archived stays
--     genuinely terminal, matching HRT-274's own explicit design intent).
--     Standalone, HRS:Override-gated (same bar as app.terminate_employee),
--     never chained into case finalize (the same authority-chaining-fragility
--     reasoning as decision 1).
-- ===========================================================================

create function app.rehire_employee(
  p_master_record_id uuid, p_expected_version integer, p_reason text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.employees
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to rehire an employee' using errcode = 'check_violation';
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

  if v_employee.lifecycle_status <> 'terminated' then
    raise exception 'invalid_transition: employee % is %, only a terminated employee can be rehired (archived is a genuinely terminal administrative closure)', p_master_record_id, v_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  update app.employees
  set lifecycle_status = 'active', terminate_reason = null, employment_end_date = null
  where master_record_id = p_master_record_id and record_version = p_expected_version
  returning * into v_employee;
  if not found then
    raise exception 'stale_version: employee % target row was concurrently modified (expected version %)', p_master_record_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.employee_lifecycle_events (tenant_id, master_record_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_employee.tenant_id, p_master_record_id, 'terminated', 'active', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'rehire_employee',
    'app.employees', p_master_record_id, 'success', p_reason, null, jsonb_build_object('rehired', true)
  );

  return v_employee;
end;
$$;

comment on function app.rehire_employee is 'HRT-277 decision 2 (section 22 "rehire linked to historical employee"): app.reactivate_employee (HRT-274) only restores from suspended -- no terminated/archived -> active path exists anywhere in HRT-274''s own migration (independently verified by direct reading). This function is the additive extension a downstream capability makes to a shared table it does not exclusively own, mirroring HRT-275''s own precedent of adding app.employees.position_id and its own RPCs. Never routes through app.create_employee_draft again -- the canonical employee identity and its full history (position/organization/compensation lineage, if any) are preserved unchanged, satisfying acceptance criterion "no-history-loss".';

-- ===========================================================================
-- 14. Reads -- server-filtered/searched/paginated (section 17: no SELECT *, no
--     client-loaded full dataset). Sensitive fields (exit_reason, evidence_
--     note, waive_reason -- decision 4) are masked by app.has_view_personal_
--     data, reused directly, unless the caller is reading their own assigned
--     task (task-owner isolation, section 26).
-- ===========================================================================

create function app.list_onboarding_checklist_templates(p_tenant_id uuid, p_actor_auth_user_id uuid, p_case_type_filter text default null)
returns table (
  id uuid, code text, name text, case_type text, status text,
  published_version_id uuid, published_version_number integer, record_version integer
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

  return query
  select t.id, t.code, t.name, t.case_type, t.status, tv.id, tv.version_number, t.record_version
  from app.onboarding_checklist_templates t
  left join app.onboarding_checklist_template_versions tv on tv.template_id = t.id and tv.status = 'published'
  where t.tenant_id = p_tenant_id and (p_case_type_filter is null or t.case_type = p_case_type_filter)
  order by t.code;
end;
$$;

create function app.get_onboarding_checklist_template_version(p_template_version_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, template_id uuid, version_number integer, status text, record_version integer,
  task_id uuid, task_key text, title text, description text, task_type text, handoff_category text,
  owner_type text, is_mandatory boolean, sla_days integer, sort_order integer, depends_on_task_keys text[]
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.onboarding_checklist_template_versions;
begin
  -- Table-aliased (v.id, never bare id) -- this function's own RETURNS TABLE
  -- carries an "id" output column (recurring bug class, C-05-adjacent; see
  -- app.get_onboarding_case's own identical fix above).
  select v.* into v_version from app.onboarding_checklist_template_versions v where v.id = p_template_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'template_version_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- LEFT JOIN (not the original inner join) -- a brand-new draft with zero
  -- tasks yet must still return exactly one row so the caller can see the
  -- version's own id/status/record_version (needed for publish's
  -- p_expected_version) even before the first task is added. Self-found
  -- defect, fixed before commit: the original inner-join shape returned ZERO
  -- rows for that real, reachable state (right after app.create_onboarding_
  -- checklist_template_version), silently hiding the version from its own
  -- read RPC.
  return query
  select
    v_version.id, v_version.template_id, v_version.version_number, v_version.status, v_version.record_version,
    tt.id, tt.task_key, tt.title, tt.description, tt.task_type, tt.handoff_category, tt.owner_type,
    tt.is_mandatory, tt.sla_days, tt.sort_order,
    coalesce((select array_agg(d.depends_on_task_key order by d.depends_on_task_key) from app.onboarding_checklist_template_task_dependencies d where d.template_version_id = p_template_version_id and d.task_key = tt.task_key), '{}'::text[])
  from app.onboarding_checklist_template_versions v
  left join app.onboarding_checklist_template_tasks tt on tt.template_version_id = v.id
  where v.id = p_template_version_id
  order by tt.sort_order nulls last;
end;
$$;

create function app.list_onboarding_cases(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_case_type_filter text default null,
  p_status_filter text default null, p_search text default null, p_limit integer default 50, p_after_id uuid default null
)
returns table (
  id uuid, case_type text, source_type text, employee_master_record_id uuid, employee_full_name text,
  status text, effective_date date, initiated_at timestamptz, record_version integer
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

  return query
  select c.id, c.case_type, c.source_type, c.employee_master_record_id, e.full_name, c.status, c.effective_date, c.initiated_at, c.record_version
  from app.onboarding_offboarding_cases c
  left join app.employees e on e.master_record_id = c.employee_master_record_id
  where c.tenant_id = p_tenant_id
    and (p_case_type_filter is null or c.case_type = p_case_type_filter)
    and (p_status_filter is null or c.status = p_status_filter)
    and (p_search is null or e.full_name ilike '%' || p_search || '%')
    and (p_after_id is null or c.id > p_after_id)
  order by c.id
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create function app.get_onboarding_case(p_case_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, case_type text, source_type text, source_job_offer_id uuid,
  employee_master_record_id uuid, employee_full_name text, checklist_template_version_id uuid,
  status text, effective_date date, initiated_by text, initiated_at timestamptz,
  finalize_approval_request_id uuid, finalized_at timestamptz, cancel_reason text,
  exit_reason text, exit_reason_masked boolean, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_case app.onboarding_offboarding_cases;
  v_employee app.employees;
  v_can_view_personal boolean;
begin
  -- Table-aliased (c.id, never bare id) -- this function's own RETURNS TABLE
  -- carries an "id" output column, genuinely ambiguous against a bare
  -- reference (the recurring bug class HRT-274/276's own build logs both
  -- found and fixed multiple times; caught live by this checkpoint's own
  -- adversarial testing before commit, not shipped as a repeat).
  select c.* into v_case from app.onboarding_offboarding_cases c where c.id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_employee from app.employees where master_record_id = v_case.employee_master_record_id;
  v_can_view_personal := app.has_view_personal_data(v_case.tenant_id, p_actor_auth_user_id);

  return query select
    v_case.id, v_case.tenant_id, v_case.case_type, v_case.source_type, v_case.source_job_offer_id,
    v_case.employee_master_record_id, v_employee.full_name, v_case.checklist_template_version_id,
    v_case.status, v_case.effective_date, v_case.initiated_by, v_case.initiated_at,
    v_case.finalize_approval_request_id, v_case.finalized_at, v_case.cancel_reason,
    case when v_can_view_personal then v_case.exit_reason else null end,
    (v_case.exit_reason is not null and not v_can_view_personal),
    v_case.record_version;
end;
$$;

create function app.list_onboarding_case_tasks(p_case_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, template_task_key text, title text, description text, task_type text, handoff_category text,
  owner_type text, owner_auth_user_id uuid, is_mandatory boolean, due_at timestamptz, is_overdue boolean,
  sort_order integer, status text, completed_at timestamptz, waived_at timestamptz,
  waive_reason text, evidence_note text, evidence_file_id uuid, sensitive_masked boolean,
  depends_on_task_ids uuid[], record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_case app.onboarding_offboarding_cases;
  v_can_view_personal boolean;
begin
  -- Table-aliased (this function's own RETURNS TABLE carries an "id" output
  -- column -- the recurring bug class).
  select c.* into v_case from app.onboarding_offboarding_cases c where c.id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_can_view_personal := app.has_view_personal_data(v_case.tenant_id, p_actor_auth_user_id);

  return query
  select
    t.id, t.template_task_key, t.title, t.description, t.task_type, t.handoff_category,
    t.owner_type, t.owner_auth_user_id, t.is_mandatory, t.due_at,
    (t.due_at is not null and t.due_at < now() and t.status not in ('completed', 'waived')),
    t.sort_order, t.status, t.completed_at, t.waived_at,
    case when v_can_view_personal or t.owner_auth_user_id = p_actor_auth_user_id then t.waive_reason else null end,
    case when v_can_view_personal or t.owner_auth_user_id = p_actor_auth_user_id then t.evidence_note else null end,
    t.evidence_file_id,
    ((t.waive_reason is not null or t.evidence_note is not null) and not v_can_view_personal and t.owner_auth_user_id is distinct from p_actor_auth_user_id),
    coalesce((select array_agg(d.depends_on_task_id) from app.onboarding_case_task_dependencies d where d.task_id = t.id), '{}'::uuid[]),
    t.record_version
  from app.onboarding_case_tasks t
  where t.case_id = p_case_id
  order by t.sort_order;
end;
$$;

comment on function app.list_onboarding_case_tasks is 'HRT-277 section 26/decision 4: evidence_note/waive_reason are visible to HRS:View-personal-data holders OR the task''s own assigned owner (task-owner isolation) -- masked (with sensitive_masked=true, never a silent empty string) for everyone else. is_overdue is computed here at read time (decision 5: no live scheduler exists anywhere in this repository yet).';

create function app.get_onboarding_case_approval_timeline(p_case_id uuid, p_actor_auth_user_id uuid)
returns table (
  step_id uuid, step_order integer, approver_type text, step_status text,
  decision_id uuid, actor_auth_user_id uuid, actor_label text, decision text, reason text, decided_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_case app.onboarding_offboarding_cases;
begin
  -- Table-aliased (this function's own RETURNS TABLE carries a "step_id"
  -- output column, not "id" itself -- aliased anyway for consistency with
  -- every sibling read RPC in this migration, defense in depth against a
  -- future column rename silently reintroducing the ambiguity).
  select c.* into v_case from app.onboarding_offboarding_cases c where c.id = p_case_id;
  if not found or not app.has_active_tenant_membership(v_case.tenant_id, p_actor_auth_user_id) then
    raise exception 'case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_case.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_case.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_case.finalize_approval_request_id is null then
    return;
  end if;

  return query select * from app.get_approval_request_history(v_case.finalize_approval_request_id, p_actor_auth_user_id);
end;
$$;

comment on function app.get_onboarding_case_approval_timeline is 'HRT-277 section 15 "approval timeline". Returns zero rows (never raises) when the case has never been submitted for finalize approval yet -- a real, distinguishable empty state, not an error.';

-- Task-owner self-service (section 26) -- identity-match, not permission-
-- gated, mirrors app.list_my_team_employees/app.get_my_assigned_interviews'
-- own established shape (HRT-274/276). Never requires HRS:View.
create function app.list_my_onboarding_tasks(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, case_id uuid, template_task_key text, title text, task_type text, handoff_category text,
  due_at timestamptz, is_overdue boolean, status text, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Explicit app.has_active_tenant_membership call (in addition to the
  -- identity-match check above) so the repository's own automated call-graph
  -- scanner (scripts/db-tests/rbac-enforcement.sql, ATW-032) recognizes a real
  -- authority check on this SECURITY DEFINER-granted-to-authenticated path --
  -- mirrors app.get_my_assigned_interviews' own identical fix (HRT-276).
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select t.id, t.case_id, t.template_task_key, t.title, t.task_type, t.handoff_category,
         t.due_at, (t.due_at is not null and t.due_at < now() and t.status not in ('completed', 'waived')),
         t.status, t.record_version
  from app.onboarding_case_tasks t
  where t.tenant_id = p_tenant_id and t.owner_auth_user_id = p_actor_auth_user_id
    and t.status not in ('completed', 'waived')
  order by t.due_at nulls last;
end;
$$;

create function app.export_onboarding_cases(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 500)
returns table (case_type text, source_type text, employee_full_name text, status text, effective_date date, initiated_at timestamptz)
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

  return query
  select c.case_type, c.source_type, e.full_name, c.status, c.effective_date, c.initiated_at
  from app.onboarding_offboarding_cases c
  left join app.employees e on e.master_record_id = c.employee_master_record_id
  where c.tenant_id = p_tenant_id and (p_status_filter is null or c.status = p_status_filter)
  order by c.initiated_at desc
  limit least(coalesce(p_limit, 500), 5000);
end;
$$;

comment on function app.export_onboarding_cases is 'HRT-277 section 14 "read/report" API -- deliberately carries no exit_reason/evidence_note/waive_reason column (a scoped export projection, section 17, matching app.export_positions'' own precedent: the columns simply are not selected, not masked-in-place).';

-- ===========================================================================
-- 15. RLS -- hardened default-deny (HRT-274/275/276's own established form),
--     proven live against anon/customer_user-layer/cross-tenant in the
--     db-test suite.
-- ===========================================================================

alter table app.onboarding_checklist_templates enable row level security;
alter table app.onboarding_checklist_template_versions enable row level security;
alter table app.onboarding_checklist_template_tasks enable row level security;
alter table app.onboarding_checklist_template_task_dependencies enable row level security;
alter table app.onboarding_offboarding_cases enable row level security;
alter table app.onboarding_case_events enable row level security;
alter table app.onboarding_case_tasks enable row level security;
alter table app.onboarding_case_task_dependencies enable row level security;
alter table app.onboarding_task_provisioning_requests enable row level security;

create policy onboarding_checklist_templates_select_scoped on app.onboarding_checklist_templates
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy onboarding_checklist_template_versions_select_scoped on app.onboarding_checklist_template_versions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy onboarding_checklist_template_tasks_select_scoped on app.onboarding_checklist_template_tasks
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy onboarding_checklist_template_task_dependencies_select_scoped on app.onboarding_checklist_template_task_dependencies
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy onboarding_offboarding_cases_select_scoped on app.onboarding_offboarding_cases
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy onboarding_case_events_select_scoped on app.onboarding_case_events
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy onboarding_case_tasks_select_scoped on app.onboarding_case_tasks
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy onboarding_case_task_dependencies_select_scoped on app.onboarding_case_task_dependencies
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy onboarding_task_provisioning_requests_select_scoped on app.onboarding_task_provisioning_requests
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 16. Grants. Column-restricted from THIS, the first, migration (decision 4/
--     mandatory reading item 5) -- exit_reason/evidence_note/waive_reason
--     excluded from the plain authenticated column grant; full access via
--     service_role. Every SECURITY DEFINER write RPC gates through
--     evaluate_permission or an explicit identity-match check (taxonomy C-12);
--     none is a bare grant with no authority check.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.onboarding_checklist_templates to authenticated, service_role;
grant insert, update on app.onboarding_checklist_templates to service_role;
grant select on app.onboarding_checklist_template_versions to authenticated, service_role;
grant insert, update on app.onboarding_checklist_template_versions to service_role;
grant select on app.onboarding_checklist_template_tasks to authenticated, service_role;
grant insert, delete on app.onboarding_checklist_template_tasks to service_role;
grant select on app.onboarding_checklist_template_task_dependencies to authenticated, service_role;
grant insert, delete on app.onboarding_checklist_template_task_dependencies to service_role;

grant select (
  id, tenant_id, case_type, source_type, source_job_offer_id, source_job_application_id,
  source_candidate_id, employee_master_record_id, checklist_template_version_id, status,
  effective_date, initiated_by, initiated_at, finalize_approval_request_id, finalized_at,
  finalized_by, cancel_reason, cancelled_at, idempotency_key, record_version, created_by,
  created_at, updated_at
) on app.onboarding_offboarding_cases to authenticated;
grant select on app.onboarding_offboarding_cases to service_role;
grant insert, update on app.onboarding_offboarding_cases to service_role;

grant select on app.onboarding_case_events to authenticated, service_role;
grant insert on app.onboarding_case_events to service_role;

grant select (
  id, case_id, tenant_id, template_task_key, title, description, task_type, handoff_category,
  owner_type, owner_auth_user_id, is_mandatory, due_at, sort_order, status, completed_at,
  completed_by, waived_at, waived_by, evidence_file_id, record_version, created_at, updated_at
) on app.onboarding_case_tasks to authenticated;
grant select on app.onboarding_case_tasks to service_role;
grant insert, update on app.onboarding_case_tasks to service_role;

grant select on app.onboarding_case_task_dependencies to authenticated, service_role;
grant insert on app.onboarding_case_task_dependencies to service_role;

grant select on app.onboarding_task_provisioning_requests to authenticated, service_role;
grant insert, update on app.onboarding_task_provisioning_requests to service_role;

-- Template authoring/publishing (HRS:Create/Edit/Approve gated internally).
grant execute on function app.create_onboarding_checklist_template(uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_onboarding_checklist_template_version(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.add_onboarding_checklist_template_task(uuid, text, text, text, text, text, text, boolean, integer, integer, uuid, text) to authenticated, service_role;
grant execute on function app.add_onboarding_checklist_template_task_dependency(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.publish_onboarding_checklist_template_version(uuid, integer, uuid, text) to authenticated, service_role;

-- Case lifecycle (HRS:Create/Edit/Approve/Override gated internally).
grant execute on function app.preview_onboarding_case_start(uuid, text, text, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.start_onboarding_case(uuid, text, text, uuid, uuid, uuid, date, text, text, text, text, text, text, date, text, uuid, uuid, uuid, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.assign_onboarding_task(uuid, uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.complete_onboarding_task(uuid, uuid, integer, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.waive_onboarding_task(uuid, uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.reopen_onboarding_task(uuid, uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.request_onboarding_access_provisioning(uuid, uuid, integer, uuid, uuid[], uuid, uuid, text) to authenticated, service_role;
grant execute on function app.request_onboarding_access_revocation(uuid, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.submit_onboarding_case_for_finalize_approval(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_onboarding_case_finalize_approval(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_onboarding_case(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.rehire_employee(uuid, integer, text, uuid, text) to authenticated, service_role;

-- Reads.
grant execute on function app.list_onboarding_checklist_templates(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_onboarding_checklist_template_version(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_onboarding_cases(uuid, uuid, text, text, text, integer, uuid) to authenticated, service_role;
grant execute on function app.get_onboarding_case(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_onboarding_case_tasks(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_onboarding_case_approval_timeline(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_my_onboarding_tasks(uuid, uuid) to authenticated, service_role;
grant execute on function app.export_onboarding_cases(uuid, uuid, text, integer) to authenticated, service_role;

-- Internal-only helpers (never granted to authenticated -- ISS-2026-033's own
-- "SECURITY DEFINER + no authority check" class does not apply here since
-- none of these is even reachable by authenticated at all).
grant execute on function app.onboarding_case_audit_projection(app.onboarding_offboarding_cases) to service_role;
grant execute on function app.onboarding_case_task_audit_projection(app.onboarding_case_tasks) to service_role;
grant execute on function app.assert_no_onboarding_template_task_dependency_cycle(uuid, text, text) to service_role;
grant execute on function app.map_offer_employment_type_to_employee(text) to service_role;
grant execute on function app.assert_onboarding_case_start_idempotent_replay(app.onboarding_offboarding_cases, text, text, uuid, text) to service_role;
grant execute on function app.recompute_onboarding_case_task_blocked_state(uuid) to service_role;
grant execute on function app.resolve_onboarding_case_task_for_write(uuid, uuid, uuid, text) to service_role;
