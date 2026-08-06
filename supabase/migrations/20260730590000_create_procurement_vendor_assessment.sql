-- Procurement capability PRC-252 (Vendor Assessment, CG-S11-PRC-003). Versioned
-- initial/periodic/incident/financial/operational/safety vendor assessments with
-- explainable scoring, findings, corrective actions, maker-checker approval and
-- manual "start reassessment." Extends app.vendor_profiles (PRC-251,
-- 20260730580000_create_procurement_vendor_registration.sql, master_type_code='vendor'
-- via ADR-0020) -- every assessment references app.vendor_profiles.master_record_id.
-- Produces versioned SCORE/BAND evidence only; never mutates
-- app.vendor_profiles.lifecycle_status (vendor eligibility composition is PRC-256+/
-- PRC-262/263 scope, out of this capability's own range).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Template versioning mirrors app.item_control_policy_versions'
--    draft -> published -> archived shape exactly** (ATW-016,
--    20260730220000_create_advanced_tms_lot_batch_serial_expiry.sql):
--    app.publish_vendor_assessment_template's own p_supersedes_version_id parameter
--    archives the prior published version for the same
--    (tenant_id, vendor_category, assessment_type) scope and links the new one -- a
--    published template's own criteria are never edited in place (child-CRUD is
--    draft-only, enforced by app.assert_vendor_assessment_template_editable's own
--    `for update` lock, the same TOCTOU-closing pattern PRC-251's adversarial review
--    proved necessary for app.assert_vendor_profile_editable). Because
--    app.vendor_assessments.template_version_id always references the exact,
--    immutable, already-published template row an assessment was started against --
--    never "the current published version" re-resolved later -- this structurally
--    satisfies the RPD-040-style "applied version" invariant this repository enforces
--    everywhere rates/configs are consumed: a later template edit (a NEW draft, then a
--    NEW published version) can never retroactively change an in-flight or completed
--    assessment's own scoring rules, because that assessment's own criteria join is by
--    template_version_id, which never changes.
-- 2. **Weight-sum validation happens once, at publish, never at every criterion add**
--    (the prompt's own explicit instruction) -- app.publish_vendor_assessment_template
--    checks `abs(sum(active criteria weight) - weight_total_required) <= 0.01` and at
--    least one active criterion exists; a partial draft is never forced to sum
--    correctly mid-edit.
-- 3. **Explainable scoring is a real weighted sum, not a black box.**
--    app._compute_vendor_assessment_score (private, stable, no side effect) computes
--    `sum(criterion.weight * answer.score / 100)` over the assessment's own applied
--    template_version_id's active criteria, rounded to 2 decimals, then bands the
--    result against the template's own pass_threshold/conditional_threshold.
--    app.calculate_vendor_assessment_score (public, persists the result) and
--    app.submit_vendor_assessment_for_review (persists it as part of one atomic
--    transition) both call this same helper -- one arithmetic definition, not two
--    independently-maintained copies that could drift. app.get_vendor_assessment_score_
--    breakdown is the companion READ RPC a caller uses to show "criterion X
--    contributed Y points because weight Z * answer score W" per criterion (§4/§21/§33's
--    own "explainable" requirement).
-- 4. **Maker-checker is mandatory here** (unlike PRC-251, where §26 did not require
--    reviewer<>submitter separation and RBAC role separation was judged sufficient).
--    §21's own main flow names "submits to a separate reviewer" and §23 explicitly
--    names "self-approval" as a case to block.
--    app.decide_vendor_assessment_review rejects outright if
--    p_actor_auth_user_id = the assessment's own assessor_auth_user_id, using the exact
--    inline `self_approval_not_allowed` / `errcode = 'insufficient_privilege'` wording
--    app.approve_warehouse_billing_event (20260730300000_create_advanced_tms_
--    warehouse_billing_events.sql) established. The same guard is duplicated (defense
--    in depth, not merely satisfying the letter of the requirement) in
--    app.begin_vendor_assessment_review and in app.start_vendor_assessment / app.
--    submit_vendor_assessment_for_review's own optional reviewer pre-assignment
--    parameter (an assessor may not name themselves as the reviewer up front either).
-- 5. **Manual score adjustment (§24) is a dedicated RPC**
--    (app.adjust_vendor_assessment_score), gated on the seeded PRC:Override action,
--    mandatory non-empty reason, restricted to the submitted/under_review window (after
--    a score exists, before a decision is final) -- and writes BOTH the real prior
--    value and the new value into app.capture_audit_event's own before_value/
--    after_value jsonb parameters (genuinely recorded, not merely the new value), in
--    addition to the dedicated adjusted_score/adjustment_reason/adjusted_by/adjusted_at
--    column pair on the row itself for direct display without replaying the audit log.
--    "before" is `coalesce(adjusted_score, calculated_score)` -- a second override in
--    the same assessment correctly records the PRIOR adjustment as its own "before",
--    not the original machine-calculated score a first override may have already
--    superseded.
-- 6. **Reassessment is manual, never a scheduler.** On approval, expiry_date =
--    decided_at::date + the applied template's own validity_period_days.
--    app.get_vendor_assessment (and app.get_vendor_current_assessment_status, the
--    downstream-composable read RPC) surface a computed reassessment_due boolean
--    (expiry_date < current_date), never a stored, driftable copy.
--    app.start_vendor_assessment_reassessment is a real, callable RPC referencing the
--    prior assessment as its own predecessor_assessment_id -- no scheduler/cron job is
--    added (ISS-2026-015 already discloses no scheduler runtime exists anywhere in this
--    repository; this is a known, accepted, standing repository-wide gap, not this
--    capability's job to solve).
-- 7. **RBAC reuses exactly the 12 already-seeded PRC actions** (View/Create/Edit/
--    Delete/Approve/Reject/Export/Override/Download/Import/View cost/View personal
--    data -- 7 original PLT-111 rows plus PRC-251's own 5 additions). No new
--    app.permissions row is seeded by this migration. Mapping: `Create` = start a new
--    assessment/template draft/reassessment/corrective-action record; `Edit` = template
--    draft/criteria mutation, recording an answer, calculating/submitting, raising or
--    deciding a finding, updating a corrective action's status, archiving a template,
--    closing an assessment with zero open corrective actions; `Approve` = publishing a
--    template, beginning a review, approving a decision; `Reject` = rejecting a
--    decision; `Override` = manual score adjustment, closing an assessment WITH open
--    corrective actions (an explicit governed exception, per §23's own exception-flow
--    naming). §26's "compliance/finance/safety roles see purpose-bound sections" is
--    honored for the one dimension a seeded action actually fits: a criterion's own
--    `purpose_tag='financial'` answer value/notes are masked in
--    app.get_vendor_assessment_score_breakdown behind the newly-reused (not
--    newly-seeded) `PRC:View cost` action, mirroring app.has_view_cost's exact shape as
--    `app.has_prc_view_cost` (PRC-251 already established this "has_prc__" naming
--    convention with app.has_prc_view_personal_data, to avoid PLT-114's own
--    HRS-hardcoded `app.has_view_personal_data` name collision). No seeded action
--    distinctly fits `safety`/`compliance`/`operational` purpose tags beyond ordinary
--    `PRC:View`, so those sections are visible to any PRC:View holder -- a disclosed,
--    reasoned simplification given the fixed action set, not a silently-invented gap.
-- 8. **No vendor-portal identity exists to enforce "vendor users may supply evidence
--    but never approve themselves" against** -- PRC-267 (external vendor portal) is
--    explicitly out of this range's own scope
--    (docs/build-log/phase-06/00_PROCUREMENT_VENDOR_WBS.md §7), matching PRC-251's own
--    identical disclosed boundary. Nothing in this migration builds a fifth identity
--    layer for a vendor user.
-- 9. **Evidence reuses the existing Document/File Engine directly** (PLT-128,
--    app.initiate_file_upload, record_type='vendor_assessment',
--    record_id=the assessment's own id) -- this is the first Phase 6 capability that
--    actually wires a real evidence attachment (PRC-251 disclosed it did NOT need to;
--    this prompt's own §13/§18 explicitly name "evidence" as required schema content
--    and audit-trail content). app.vendor_assessment_answers.evidence_file_id and
--    app.vendor_assessment_corrective_actions.resolved_evidence_file_id are both
--    nullable `uuid references app.files (id)` -- no new file table is built.
-- 10. **tenant_id is duplicated directly on every new table**, matching PRC-251's own
--     already-established choice (required for the hardened RLS default-deny form to
--     reference tenant_id directly in each policy's qual, and for direct tenant-scoped
--     indexing).
-- 11. Per ERR-2026-004: this migration carries its own explicit
--     `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its
--     final grants, the standing per-migration convention since PLT-118.
-- 12. **Post-implementation adversarial-review fixes (this pass).** Three independent
--     reviewers examined this migration before it was applied; the following were
--     CONFIRMED and fixed in place (no separate migration file, since nothing had
--     been applied yet): (a) evidence-file linking (app.record_vendor_assessment_answer,
--     app.update_vendor_assessment_corrective_action_status) now re-validates the
--     file's tenant/record_type/record_id and malware_scan_status='clean', mirroring
--     app.record_gps_device_installation's own exact shape (previously a bare FK let
--     a caller launder a cross-tenant/wrong-record/unsafe file into an assessment's
--     evidence trail); (b) app.adjust_vendor_assessment_score now recomputes
--     score_band against the adjusted score (previously stayed frozen at the
--     machine-calculated band, letting an approved assessment show a self-
--     contradictory adjusted_score/score_band pairing); (c) app.decide_vendor_
--     assessment_review now enforces reviewer exclusivity once one is assigned
--     (previously a different Approve/Reject-holding actor could decide while the
--     row kept misattributing the decision to the original reviewer); (d)
--     app.create_vendor_assessment_corrective_action now locks and checks the
--     parent assessment is not closed (previously a new open corrective action
--     could attach to an already-closed assessment, both deterministically and via
--     a genuine race, defeating app.close_vendor_assessment's own governed-override
--     gate); (e) app.publish_vendor_assessment_template's superseded-template
--     archive now takes a `for update` lock plus a real version/status-guarded
--     UPDATE with a not-found re-check (previously a blind, unguarded UPDATE); (f)
--     weight_total_required is now pinned to exactly 100 at the column CHECK and at
--     both create/update RPCs, since app._compute_vendor_assessment_score's own
--     formula hardcodes a 100-point denominator (previously an arbitrary total
--     could crash the calculated_score range CHECK or make pass_threshold
--     unreachable); (g) app.create_vendor_assessment_template_draft's idempotency
--     replay now compares every semantically load-bearing field, not just
--     name/assessment_type. Judged NOT a defect and left as originally built: the
--     §26 safety/compliance masking gap (design note 7, above) -- closing it would
--     require widening app.permissions' own fixed, closed action enum
--     (permissions_action_check), which no migration in this repository has ever
--     done, for a masking need this migration's own existing PRC:View cost gate
--     cannot honestly cover. See docs/build-log/phase-06/PRC-252.md for the full
--     adversarial-review disposition, including findings judged accepted-not-fixed
--     with rationale.

-- ===========================================================================
-- 1. app.vendor_assessment_templates -- versioned draft/published/archived,
--    mirroring app.item_control_policy_versions exactly (design note 1).
-- ===========================================================================

create table app.vendor_assessment_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_category text,
  assessment_type text not null,
  name text not null,
  description text,
  validity_period_days integer not null,
  pass_threshold numeric(5, 2) not null,
  conditional_threshold numeric(5, 2) not null,
  weight_total_required numeric(6, 2) not null default 100.00,
  status text not null default 'draft',
  supersedes_version_id uuid references app.vendor_assessment_templates (id),
  effective_from timestamptz not null default now(),
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_assessment_templates_name_check check (length(trim(name)) > 0),
  constraint vendor_assessment_templates_assessment_type_check check (
    assessment_type in ('initial', 'periodic', 'incident', 'financial', 'operational', 'safety')
  ),
  constraint vendor_assessment_templates_status_check check (status in ('draft', 'published', 'archived')),
  constraint vendor_assessment_templates_validity_check check (validity_period_days > 0),
  constraint vendor_assessment_templates_pass_threshold_check check (pass_threshold >= 0 and pass_threshold <= 100),
  constraint vendor_assessment_templates_conditional_threshold_check check (conditional_threshold >= 0 and conditional_threshold <= 100),
  constraint vendor_assessment_templates_threshold_order_check check (conditional_threshold <= pass_threshold),
  -- Pinned to exactly 100: app._compute_vendor_assessment_score's own weighted-sum
  -- formula (`c.weight * a.score / 100.0`) hardcodes a 100-point denominator. A
  -- weight_total_required other than 100 either produces a calculated_score outside
  -- the 0-100 domain (crashing vendor_assessments_calculated_score_range_check) or
  -- makes pass_threshold mathematically unreachable -- both reproduced defects from
  -- adversarial review. Pinning at the column AND at both create/update RPCs is
  -- defense in depth, not merely a display default.
  constraint vendor_assessment_templates_weight_total_check check (weight_total_required = 100),
  constraint vendor_assessment_templates_not_self_supersede check (supersedes_version_id is null or supersedes_version_id <> id)
);

comment on table app.vendor_assessment_templates is
  'PRC-252: a versioned assessment template (draft -> published -> archived, mirrors app.item_control_policy_versions/ATW-016 exactly). Scoped by (tenant_id, vendor_category [nullable wildcard], assessment_type). app.vendor_assessments.template_version_id always references one immutable, already-published row here -- the applied-version snapshot invariant (design note 1).';

create unique index vendor_assessment_templates_published_unique on app.vendor_assessment_templates (tenant_id, coalesce(vendor_category, ''), assessment_type) where status = 'published';
create index vendor_assessment_templates_tenant_scope_idx on app.vendor_assessment_templates (tenant_id, vendor_category, assessment_type, status);
create unique index vendor_assessment_templates_idempotency_key_unique on app.vendor_assessment_templates (tenant_id, idempotency_key) where idempotency_key is not null;

-- ===========================================================================
-- 2. app.vendor_assessment_template_criteria -- child rows, draft-template-only
--    mutation (design note 1).
-- ===========================================================================

create table app.vendor_assessment_template_criteria (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  template_version_id uuid not null references app.vendor_assessment_templates (id),
  label text not null,
  purpose_tag text not null default 'operational',
  weight numeric(6, 2) not null,
  scoring_guidance text,
  display_order integer not null default 0,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_assessment_template_criteria_label_check check (length(trim(label)) > 0),
  constraint vendor_assessment_template_criteria_purpose_tag_check check (purpose_tag in ('financial', 'safety', 'operational', 'compliance')),
  constraint vendor_assessment_template_criteria_weight_check check (weight > 0),
  constraint vendor_assessment_template_criteria_status_check check (status in ('active', 'removed'))
);

comment on table app.vendor_assessment_template_criteria is
  'PRC-252: one scored criterion per template version. purpose_tag drives Sec.26''s purpose-bound section access (financial gated behind PRC:View cost, design note 7). weight is validated to sum to the parent template''s own weight_total_required ONLY at publish time (design note 2), never at every add.';

create index vendor_assessment_template_criteria_template_idx on app.vendor_assessment_template_criteria (template_version_id) where status = 'active';

create function app.touch_vendor_assessment_child_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger vendor_assessment_template_criteria_touch_row
  before update on app.vendor_assessment_template_criteria
  for each row
  execute function app.touch_vendor_assessment_child_row();

-- ===========================================================================
-- 3. app.vendor_assessments -- header. template_version_id is a snapshot FK
--    (design note 1's applied-version invariant).
-- ===========================================================================

create table app.vendor_assessments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_record_id uuid not null references app.vendor_profiles (master_record_id),
  template_version_id uuid not null references app.vendor_assessment_templates (id),
  assessment_type text not null,
  status text not null default 'draft',
  assessor_auth_user_id uuid not null,
  reviewer_auth_user_id uuid,
  calculated_score numeric(6, 2),
  score_band text,
  adjusted_score numeric(6, 2),
  adjustment_reason text,
  adjusted_by text,
  adjusted_by_auth_user_id uuid,
  adjusted_at timestamptz,
  submitted_at timestamptz,
  decided_at timestamptz,
  decision_reason text,
  expiry_date date,
  predecessor_assessment_id uuid references app.vendor_assessments (id),
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_assessments_assessment_type_check check (
    assessment_type in ('initial', 'periodic', 'incident', 'financial', 'operational', 'safety')
  ),
  constraint vendor_assessments_status_check check (
    status in ('draft', 'in_progress', 'submitted', 'under_review', 'approved', 'rejected', 'closed')
  ),
  constraint vendor_assessments_score_band_check check (score_band is null or score_band in ('pass', 'conditional', 'fail')),
  constraint vendor_assessments_calculated_score_range_check check (calculated_score is null or (calculated_score >= 0 and calculated_score <= 100)),
  constraint vendor_assessments_adjusted_score_range_check check (adjusted_score is null or (adjusted_score >= 0 and adjusted_score <= 100)),
  constraint vendor_assessments_decision_reason_check check (status <> 'rejected' or (decision_reason is not null and length(trim(decision_reason)) > 0)),
  constraint vendor_assessments_adjustment_shape_check check (
    (adjusted_score is null and adjustment_reason is null and adjusted_by is null and adjusted_by_auth_user_id is null and adjusted_at is null) or
    (adjusted_score is not null and adjustment_reason is not null and length(trim(adjustment_reason)) > 0 and adjusted_by is not null and adjusted_by_auth_user_id is not null and adjusted_at is not null)
  ),
  constraint vendor_assessments_not_self_predecessor check (predecessor_assessment_id is null or predecessor_assessment_id <> id)
);

comment on table app.vendor_assessments is
  'PRC-252: one assessment cycle for one vendor against one immutable applied template_version_id (design note 1 -- never re-resolved to "the current published version"). Lifecycle: draft -> in_progress -> submitted -> under_review -> approved|rejected -> closed. Never mutates app.vendor_profiles.lifecycle_status (out of this capability''s own scope, PRC-256+/262/263).';

create index vendor_assessments_tenant_status_idx on app.vendor_assessments (tenant_id, status);
create index vendor_assessments_vendor_type_status_idx on app.vendor_assessments (vendor_master_record_id, assessment_type, status);
create index vendor_assessments_assessor_idx on app.vendor_assessments (assessor_auth_user_id);
create index vendor_assessments_reviewer_idx on app.vendor_assessments (reviewer_auth_user_id);
-- At most one OPEN (not yet decided/closed) assessment per (vendor, assessment_type) --
-- the structural guard behind the "conflicting active assessment" exception-flow block
-- (prompt §23), not merely an application-level check.
create unique index vendor_assessments_one_open_per_type_idx on app.vendor_assessments (vendor_master_record_id, assessment_type) where status in ('draft', 'in_progress', 'submitted', 'under_review');
create unique index vendor_assessments_idempotency_key_unique on app.vendor_assessments (tenant_id, idempotency_key) where idempotency_key is not null;

-- ===========================================================================
-- 4. app.vendor_assessment_answers -- one row per criterion per assessment.
--    evidence_file_id reuses the Document/File Engine (PLT-128, design note 9).
-- ===========================================================================

create table app.vendor_assessment_answers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  assessment_id uuid not null references app.vendor_assessments (id),
  criterion_id uuid not null references app.vendor_assessment_template_criteria (id),
  value text,
  score numeric(5, 2) not null,
  evidence_file_id uuid references app.files (id),
  notes text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_assessment_answers_score_range_check check (score >= 0 and score <= 100),
  constraint vendor_assessment_answers_unique unique (assessment_id, criterion_id)
);

comment on table app.vendor_assessment_answers is
  'PRC-252: one row per (assessment, criterion), upserted by app.record_vendor_assessment_answer. score is 0-100, weighted by the criterion''s own weight in app._compute_vendor_assessment_score. evidence_file_id is nullable -- app.initiate_file_upload (record_type=''vendor_assessment'', record_id=assessment_id) is the real attachment path, never a second file table.';

create index vendor_assessment_answers_assessment_idx on app.vendor_assessment_answers (assessment_id);

create trigger vendor_assessment_answers_touch_row
  before update on app.vendor_assessment_answers
  for each row
  execute function app.touch_vendor_assessment_child_row();

-- ===========================================================================
-- 5. app.vendor_assessment_findings.
-- ===========================================================================

create table app.vendor_assessment_findings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  assessment_id uuid not null references app.vendor_assessments (id),
  severity text not null,
  description text not null,
  status text not null default 'open',
  resolution_reason text,
  resolved_by text,
  resolved_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_assessment_findings_severity_check check (severity in ('low', 'medium', 'high', 'critical')),
  constraint vendor_assessment_findings_description_check check (length(trim(description)) > 0),
  constraint vendor_assessment_findings_status_check check (status in ('open', 'resolved', 'waived')),
  constraint vendor_assessment_findings_resolution_shape_check check (
    (status = 'open' and resolved_at is null and resolved_by is null and resolution_reason is null) or
    (status <> 'open' and resolved_at is not null and resolved_by is not null and resolution_reason is not null and length(trim(resolution_reason)) > 0)
  )
);

comment on table app.vendor_assessment_findings is 'PRC-252: an issue raised during a specific assessment. resolved via app.decide_vendor_assessment_finding (resolved|waived, reason mandatory).';

create index vendor_assessment_findings_assessment_idx on app.vendor_assessment_findings (assessment_id);

create trigger vendor_assessment_findings_touch_row
  before update on app.vendor_assessment_findings
  for each row
  execute function app.touch_vendor_assessment_child_row();

-- ===========================================================================
-- 6. app.vendor_assessment_corrective_actions -- linked to a finding.
--    resolved_evidence_file_id reuses the Document/File Engine (design note 9).
-- ===========================================================================

create table app.vendor_assessment_corrective_actions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  finding_id uuid not null references app.vendor_assessment_findings (id),
  assessment_id uuid not null references app.vendor_assessments (id),
  description text not null,
  due_date date,
  status text not null default 'open',
  resolution_notes text,
  resolved_evidence_file_id uuid references app.files (id),
  resolved_by text,
  resolved_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_assessment_corrective_actions_description_check check (length(trim(description)) > 0),
  constraint vendor_assessment_corrective_actions_status_check check (status in ('open', 'completed', 'overdue', 'waived')),
  constraint vendor_assessment_corrective_actions_resolution_shape_check check (
    (status in ('open', 'overdue') and resolution_notes is null and resolved_at is null and resolved_by is null) or
    (status in ('completed', 'waived') and resolution_notes is not null and length(trim(resolution_notes)) > 0 and resolved_at is not null and resolved_by is not null)
  )
);

comment on table app.vendor_assessment_corrective_actions is
  'PRC-252: a remediation item tied to one finding. assessment_id is denormalized from finding.assessment_id (mirrors app.vendor_profiles'' own tenant_id duplication choice) for direct query/RLS/index use and for app.close_vendor_assessment''s own open-corrective-action count.';

create index vendor_assessment_corrective_actions_assessment_idx on app.vendor_assessment_corrective_actions (assessment_id);
create index vendor_assessment_corrective_actions_finding_idx on app.vendor_assessment_corrective_actions (finding_id);

create trigger vendor_assessment_corrective_actions_touch_row
  before update on app.vendor_assessment_corrective_actions
  for each row
  execute function app.touch_vendor_assessment_child_row();

-- ===========================================================================
-- 7. Field-masking helper (design note 7) -- mirrors app.has_view_cost /
--    app.has_prc_view_personal_data's exact shape.
--
--    Sec.26's own literal text names THREE distinct purpose-bound roles
--    ("compliance/finance/safety roles see purpose-bound sections"), matching the
--    criteria purpose_tag CHECK's own ('financial','safety','operational',
--    'compliance') set. Two independent adversarial reviewers confirmed that only
--    gating 'financial' (behind PRC:View cost) is a real, literal mismatch against
--    that text -- 'safety'/'compliance' are never masked. This migration does NOT
--    add new 'View safety data'/'View compliance data' actions to close that gap:
--    app.permissions.action is constrained by permissions_action_check
--    (20260716103445_create_roles_permissions.sql), a FIXED, closed enum -- every
--    later migration that seeds a new (module, action) row (this migration's own
--    View cost/View personal data/etc., COM's 'Assign' in
--    20260723090000_create_commercial_lead_management.sql) reuses an action STRING
--    already inside that enum; none has ever widened the enum itself, and doing so
--    here for two PRC-only labels would be an unprecedented, repository-wide-risk
--    change to shared RBAC infrastructure for one capability's own masking need.
--    No enum value already fits "safety" or "compliance" viewing without a
--    misleading semantic stretch (View selling price/View margin/View payroll are
--    COM/HRS-specific and would read as nonsense on a PRC role). Given that, 'safety'
--    and 'compliance' sections remain visible to any ordinary PRC:View holder -- a
--    disclosed, judged limitation of the fixed action vocabulary, not a silently
--    invented gap. 'operational' is never named purpose-bound in Sec.26's own text
--    either way, so it carries no gate regardless.
-- ===========================================================================

create function app.has_prc_view_cost(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'PRC', 'View cost')).allowed;
$$;

comment on function app.has_prc_view_cost is 'PRC-252: field-masking gate mirroring app.has_view_cost''s own shape -- true if the caller holds the real, seeded PRC:View cost permission for the given tenant. Named has_prc_view_cost, not has_view_cost, to avoid COM-148''s own same-named, COM-hardcoded function (the same collision-avoidance PRC-251''s app.has_prc_view_personal_data already established for PLT-114''s app.has_view_personal_data). Gates purpose_tag=''financial'' sections (design note 7); safety/compliance have no seeded action to gate behind (see design note 7''s own fuller explanation).';

-- ===========================================================================
-- 8. Private helpers -- shared authority+state preconditions and the single,
--    non-duplicated scoring computation (design note 3).
-- ===========================================================================

create function app.assert_vendor_assessment_template_editable(p_template_version_id uuid, p_actor_auth_user_id uuid, out v_template app.vendor_assessment_templates)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  -- `for update`: closes the same TOCTOU race class PRC-251's adversarial review
  -- found in app.assert_vendor_profile_editable -- serializes every criteria-CRUD
  -- call against app.publish_vendor_assessment_template's own terminal UPDATE on the
  -- same row.
  select * into v_template from app.vendor_assessment_templates where id = p_template_version_id for update;
  if not found then
    raise exception 'vendor_assessment_template_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_template.status <> 'draft' then
    raise exception 'vendor_assessment_template_not_draft: template version % is % -- criteria may only be edited while draft', p_template_version_id, v_template.status
      using errcode = 'check_violation';
  end if;
end;
$$;

comment on function app.assert_vendor_assessment_template_editable is 'PRC-252: shared authority+state precondition for every criteria-CRUD RPC -- PRC:Edit plus status=draft, under a `for update` row lock so it serializes against app.publish_vendor_assessment_template''s own terminal UPDATE.';

create function app.assert_vendor_assessment_editable(p_assessment_id uuid, p_actor_auth_user_id uuid, out v_assessment app.vendor_assessments)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  -- `for update`: same TOCTOU-closing discipline -- serializes answer-recording
  -- against app.submit_vendor_assessment_for_review's own terminal UPDATE on the
  -- same row (an answer must never be recorded into an assessment that just left
  -- draft/in_progress a moment earlier).
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id for update;
  if not found then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_actor_auth_user_id <> v_assessment.assessor_auth_user_id then
    raise exception 'not_assigned_assessor: identity % is not the assigned assessor for vendor assessment %', p_actor_auth_user_id, p_assessment_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assessment.status not in ('draft', 'in_progress') then
    raise exception 'vendor_assessment_not_editable: vendor assessment % is % -- answers may only be recorded while draft or in_progress', p_assessment_id, v_assessment.status
      using errcode = 'check_violation';
  end if;
end;
$$;

comment on function app.assert_vendor_assessment_editable is 'PRC-252: shared authority+state precondition for app.record_vendor_assessment_answer and app.submit_vendor_assessment_for_review -- PRC:Edit, actor must be the assigned assessor, status draft|in_progress, under a `for update` row lock.';

create function app._compute_vendor_assessment_score(
  p_template_version_id uuid,
  p_assessment_id uuid,
  out out_total numeric,
  out out_band text,
  out out_criterion_count integer,
  out out_answered_count integer
)
language plpgsql
stable
as $$
declare
  v_pass numeric;
  v_conditional numeric;
begin
  select pass_threshold, conditional_threshold into v_pass, v_conditional
  from app.vendor_assessment_templates where id = p_template_version_id;

  select count(c.id), count(a.id), coalesce(round(sum(c.weight * coalesce(a.score, 0) / 100.0), 2), 0)
    into out_criterion_count, out_answered_count, out_total
  from app.vendor_assessment_template_criteria c
  left join app.vendor_assessment_answers a on a.criterion_id = c.id and a.assessment_id = p_assessment_id
  where c.template_version_id = p_template_version_id and c.status = 'active';

  out_band := case
    when out_total >= v_pass then 'pass'
    when out_total >= v_conditional then 'conditional'
    else 'fail'
  end;
end;
$$;

comment on function app._compute_vendor_assessment_score is 'PRC-252: the SINGLE, non-duplicated explainable-scoring computation (design note 3) -- a deterministic weighted sum over the assessment''s own applied template_version_id''s active criteria. Called by both app.calculate_vendor_assessment_score and app.submit_vendor_assessment_for_review so the two never drift apart. Private (no grant), stable, no side effect.';

-- ===========================================================================
-- 9. Template lifecycle RPCs.
-- ===========================================================================

create function app.create_vendor_assessment_template_draft(
  p_tenant_id uuid,
  p_vendor_category text,
  p_assessment_type text,
  p_name text,
  p_description text,
  p_validity_period_days integer,
  p_pass_threshold numeric,
  p_conditional_threshold numeric,
  p_weight_total_required numeric,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assessment_templates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.vendor_assessment_templates;
  v_weight_total numeric;
  v_template app.vendor_assessment_templates;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name must not be empty' using errcode = 'check_violation';
  end if;
  if p_assessment_type not in ('initial', 'periodic', 'incident', 'financial', 'operational', 'safety') then
    raise exception 'invalid_assessment_type: % is not a recognized assessment type', p_assessment_type using errcode = 'check_violation';
  end if;
  if coalesce(p_validity_period_days, 0) <= 0 then
    raise exception 'invalid_validity_period: validity_period_days must be positive' using errcode = 'check_violation';
  end if;
  if p_pass_threshold is null or p_pass_threshold < 0 or p_pass_threshold > 100 then
    raise exception 'invalid_pass_threshold: pass_threshold must be between 0 and 100' using errcode = 'check_violation';
  end if;
  if p_conditional_threshold is null or p_conditional_threshold < 0 or p_conditional_threshold > 100 then
    raise exception 'invalid_conditional_threshold: conditional_threshold must be between 0 and 100' using errcode = 'check_violation';
  end if;
  if p_conditional_threshold > p_pass_threshold then
    raise exception 'invalid_threshold_order: conditional_threshold must not exceed pass_threshold' using errcode = 'check_violation';
  end if;
  -- Pinned to exactly 100 (table CHECK enforces this too, defense in depth) --
  -- app._compute_vendor_assessment_score's own formula hardcodes a 100-point
  -- denominator; any other total either crashes the calculated_score range CHECK or
  -- makes pass_threshold mathematically unreachable (adversarial review, reproduced).
  v_weight_total := coalesce(p_weight_total_required, 100.00);
  if v_weight_total <> 100 then
    raise exception 'invalid_weight_total: weight_total_required must equal 100 (the scoring formula''s own fixed denominator)' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_assessment_templates where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      -- Compares EVERY caller-supplied, semantically load-bearing field, not just
      -- name/assessment_type (adversarial review, reproduced: a retried call with
      -- corrected vendor_category/validity_period_days/thresholds silently returned
      -- the FIRST call's stale configuration with no warning).
      if v_existing.name is distinct from p_name or v_existing.assessment_type is distinct from p_assessment_type
        or v_existing.vendor_category is distinct from p_vendor_category
        or v_existing.validity_period_days is distinct from p_validity_period_days
        or v_existing.pass_threshold is distinct from p_pass_threshold
        or v_existing.conditional_threshold is distinct from p_conditional_threshold
        or v_existing.weight_total_required is distinct from v_weight_total
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different template (name %, type %)', p_idempotency_key, v_existing.name, v_existing.assessment_type
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_assessment_templates (
      tenant_id, vendor_category, assessment_type, name, description, validity_period_days,
      pass_threshold, conditional_threshold, weight_total_required, idempotency_key, created_by
    ) values (
      p_tenant_id, p_vendor_category, p_assessment_type, p_name, p_description, p_validity_period_days,
      p_pass_threshold, p_conditional_threshold, v_weight_total, p_idempotency_key, p_actor_label
    )
    returning * into v_template;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_assessment_templates where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.name is distinct from p_name or v_existing.assessment_type is distinct from p_assessment_type
        or v_existing.vendor_category is distinct from p_vendor_category
        or v_existing.validity_period_days is distinct from p_validity_period_days
        or v_existing.pass_threshold is distinct from p_pass_threshold
        or v_existing.conditional_threshold is distinct from p_conditional_threshold
        or v_existing.weight_total_required is distinct from v_weight_total
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different template (name %, type %)', p_idempotency_key, v_existing.name, v_existing.assessment_type
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_assessment_template_draft',
    'app.vendor_assessment_templates', v_template.id, 'success', null, null, to_jsonb(v_template)
  );

  return v_template;
end;
$$;

create function app.update_vendor_assessment_template_draft(
  p_template_version_id uuid,
  p_expected_version integer,
  p_vendor_category text,
  p_name text,
  p_description text,
  p_validity_period_days integer,
  p_pass_threshold numeric,
  p_conditional_threshold numeric,
  p_weight_total_required numeric,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assessment_templates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_template app.vendor_assessment_templates;
  v_weight_total numeric;
begin
  v_template := app.assert_vendor_assessment_template_editable(p_template_version_id, p_actor_auth_user_id);

  if v_template.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment template % expected version % but found %', p_template_version_id, p_expected_version, v_template.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name must not be empty' using errcode = 'check_violation';
  end if;
  if coalesce(p_validity_period_days, 0) <= 0 then
    raise exception 'invalid_validity_period: validity_period_days must be positive' using errcode = 'check_violation';
  end if;
  if p_pass_threshold is null or p_pass_threshold < 0 or p_pass_threshold > 100 then
    raise exception 'invalid_pass_threshold: pass_threshold must be between 0 and 100' using errcode = 'check_violation';
  end if;
  if p_conditional_threshold is null or p_conditional_threshold < 0 or p_conditional_threshold > 100 then
    raise exception 'invalid_conditional_threshold: conditional_threshold must be between 0 and 100' using errcode = 'check_violation';
  end if;
  if p_conditional_threshold > p_pass_threshold then
    raise exception 'invalid_threshold_order: conditional_threshold must not exceed pass_threshold' using errcode = 'check_violation';
  end if;
  v_weight_total := coalesce(p_weight_total_required, 100.00);
  if v_weight_total <> 100 then
    raise exception 'invalid_weight_total: weight_total_required must equal 100 (the scoring formula''s own fixed denominator)' using errcode = 'check_violation';
  end if;

  update app.vendor_assessment_templates
  set vendor_category = p_vendor_category, name = p_name, description = p_description, validity_period_days = p_validity_period_days,
      pass_threshold = p_pass_threshold, conditional_threshold = p_conditional_threshold, weight_total_required = v_weight_total,
      updated_at = now(), record_version = record_version + 1
  where id = p_template_version_id and record_version = p_expected_version
  returning * into v_template;
  if not found then
    raise exception 'stale_version: vendor assessment template % target row was concurrently modified (expected version %)', p_template_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_assessment_template_draft',
    'app.vendor_assessment_templates', v_template.id, 'success', null, null, to_jsonb(v_template)
  );

  return v_template;
end;
$$;

create function app.add_vendor_assessment_template_criterion(
  p_template_version_id uuid, p_label text, p_purpose_tag text, p_weight numeric, p_scoring_guidance text, p_display_order integer,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessment_template_criteria
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_template app.vendor_assessment_templates;
  v_criterion app.vendor_assessment_template_criteria;
begin
  v_template := app.assert_vendor_assessment_template_editable(p_template_version_id, p_actor_auth_user_id);

  if p_label is null or length(trim(p_label)) = 0 then
    raise exception 'invalid_criterion: label must not be empty' using errcode = 'check_violation';
  end if;
  if coalesce(p_purpose_tag, 'operational') not in ('financial', 'safety', 'operational', 'compliance') then
    raise exception 'invalid_purpose_tag: % is not a recognized purpose tag', p_purpose_tag using errcode = 'check_violation';
  end if;
  if p_weight is null or p_weight <= 0 then
    raise exception 'invalid_weight: weight must be positive' using errcode = 'check_violation';
  end if;

  insert into app.vendor_assessment_template_criteria (tenant_id, template_version_id, label, purpose_tag, weight, scoring_guidance, display_order, created_by)
  values (v_template.tenant_id, p_template_version_id, p_label, coalesce(p_purpose_tag, 'operational'), p_weight, p_scoring_guidance, coalesce(p_display_order, 0), p_actor_label)
  returning * into v_criterion;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_vendor_assessment_template_criterion',
    'app.vendor_assessment_template_criteria', v_criterion.id, 'success', null, null, to_jsonb(v_criterion)
  );

  return v_criterion;
end;
$$;

create function app.update_vendor_assessment_template_criterion(
  p_criterion_id uuid, p_expected_version integer, p_label text, p_purpose_tag text, p_weight numeric, p_scoring_guidance text, p_display_order integer,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessment_template_criteria
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_criterion app.vendor_assessment_template_criteria;
  v_template app.vendor_assessment_templates;
begin
  select * into v_criterion from app.vendor_assessment_template_criteria where id = p_criterion_id and status = 'active';
  if not found then
    raise exception 'criterion_not_found: %', p_criterion_id using errcode = 'no_data_found';
  end if;
  if v_criterion.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment template criterion % expected version % but found %', p_criterion_id, p_expected_version, v_criterion.record_version
      using errcode = 'serialization_failure';
  end if;

  v_template := app.assert_vendor_assessment_template_editable(v_criterion.template_version_id, p_actor_auth_user_id);

  if p_label is null or length(trim(p_label)) = 0 then
    raise exception 'invalid_criterion: label must not be empty' using errcode = 'check_violation';
  end if;
  if coalesce(p_purpose_tag, 'operational') not in ('financial', 'safety', 'operational', 'compliance') then
    raise exception 'invalid_purpose_tag: % is not a recognized purpose tag', p_purpose_tag using errcode = 'check_violation';
  end if;
  if p_weight is null or p_weight <= 0 then
    raise exception 'invalid_weight: weight must be positive' using errcode = 'check_violation';
  end if;

  update app.vendor_assessment_template_criteria
  set label = p_label, purpose_tag = coalesce(p_purpose_tag, 'operational'), weight = p_weight, scoring_guidance = p_scoring_guidance, display_order = coalesce(p_display_order, 0)
  where id = p_criterion_id and record_version = p_expected_version
  returning * into v_criterion;
  if not found then
    raise exception 'stale_version: vendor assessment template criterion % target row was concurrently modified (expected version %)', p_criterion_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_assessment_template_criterion',
    'app.vendor_assessment_template_criteria', v_criterion.id, 'success', null, null, to_jsonb(v_criterion)
  );

  return v_criterion;
end;
$$;

create function app.remove_vendor_assessment_template_criterion(p_criterion_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessment_template_criteria
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_criterion app.vendor_assessment_template_criteria;
  v_template app.vendor_assessment_templates;
begin
  select * into v_criterion from app.vendor_assessment_template_criteria where id = p_criterion_id and status = 'active';
  if not found then
    raise exception 'criterion_not_found: %', p_criterion_id using errcode = 'no_data_found';
  end if;
  if v_criterion.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment template criterion % expected version % but found %', p_criterion_id, p_expected_version, v_criterion.record_version
      using errcode = 'serialization_failure';
  end if;

  v_template := app.assert_vendor_assessment_template_editable(v_criterion.template_version_id, p_actor_auth_user_id);

  update app.vendor_assessment_template_criteria
  set status = 'removed'
  where id = p_criterion_id and record_version = p_expected_version
  returning * into v_criterion;
  if not found then
    raise exception 'stale_version: vendor assessment template criterion % target row was concurrently modified (expected version %)', p_criterion_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_vendor_assessment_template_criterion',
    'app.vendor_assessment_template_criteria', v_criterion.id, 'success', null, null, '{}'::jsonb
  );

  return v_criterion;
end;
$$;

create function app.publish_vendor_assessment_template(
  p_template_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessment_templates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.vendor_assessment_templates;
  v_superseded app.vendor_assessment_templates;
  v_weight_sum numeric;
  v_criterion_count integer;
begin
  select * into v_template from app.vendor_assessment_templates where id = p_template_version_id for update;
  if not found then
    raise exception 'vendor_assessment_template_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_template.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment template % expected version % but found %', p_template_version_id, p_expected_version, v_template.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_template.status <> 'draft' then
    raise exception 'invalid_transition: vendor assessment template % is % and cannot be published', p_template_version_id, v_template.status
      using errcode = 'check_violation';
  end if;

  select count(*), coalesce(sum(weight), 0) into v_criterion_count, v_weight_sum
  from app.vendor_assessment_template_criteria where template_version_id = p_template_version_id and status = 'active';
  if v_criterion_count = 0 then
    raise exception 'template_has_no_criteria: vendor assessment template % defines no active criteria' , p_template_version_id
      using errcode = 'check_violation';
  end if;
  if abs(v_weight_sum - v_template.weight_total_required) > 0.01 then
    raise exception 'weight_sum_mismatch: vendor assessment template % criteria weights sum to % but must sum to %', p_template_version_id, v_weight_sum, v_template.weight_total_required
      using errcode = 'check_violation';
  end if;

  if p_supersedes_version_id is not null then
    -- `for update`: closes a real, reproduced race (adversarial review) where a
    -- concurrent, independent app.archive_vendor_assessment_template call on the SAME
    -- superseded row could commit between this read and the terminal UPDATE below,
    -- which previously carried no record_version/status guard and no "not found"
    -- re-check at all -- silently re-archiving an already-independently-archived row
    -- with no audit trail of its own for that second archival.
    select * into v_superseded from app.vendor_assessment_templates where id = p_supersedes_version_id for update;
    if not found then
      raise exception 'superseded_template_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.tenant_id <> v_template.tenant_id or v_superseded.assessment_type <> v_template.assessment_type or coalesce(v_superseded.vendor_category, '') <> coalesce(v_template.vendor_category, '') then
      raise exception 'invalid_supersede: superseded template must share the same tenant/vendor_category/assessment_type' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded template % is % (must be published)', p_supersedes_version_id, v_superseded.status using errcode = 'check_violation';
    end if;
    update app.vendor_assessment_templates
    set status = 'archived', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_version_id and record_version = v_superseded.record_version and status = 'published';
    if not found then
      raise exception 'stale_version: superseded vendor assessment template % was concurrently modified (expected version %)', p_supersedes_version_id, v_superseded.record_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  begin
    update app.vendor_assessment_templates
    set status = 'published', supersedes_version_id = p_supersedes_version_id, updated_at = now(), record_version = record_version + 1
    where id = p_template_version_id and record_version = p_expected_version
    returning * into v_template;
  exception
    when unique_violation then
      raise exception 'active_template_exists: a published template already exists for tenant %, vendor_category %, assessment_type % -- supply p_supersedes_version_id to replace it', v_template.tenant_id, v_template.vendor_category, v_template.assessment_type
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: vendor assessment template % target row was concurrently modified (expected version %)', p_template_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_vendor_assessment_template',
    'app.vendor_assessment_templates', v_template.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id, 'weight_sum', v_weight_sum)
  );

  return v_template;
end;
$$;

comment on function app.publish_vendor_assessment_template is 'PRC-252: PRC:Approve-gated. Validates >=1 active criterion and that active criteria weights sum to weight_total_required within +/-0.01 (design note 2) BEFORE publishing; archives p_supersedes_version_id first so at most one published template ever exists per (tenant, vendor_category, assessment_type).';

create function app.archive_vendor_assessment_template(p_template_version_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessment_templates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.vendor_assessment_templates;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to archive a vendor assessment template' using errcode = 'check_violation';
  end if;

  select * into v_template from app.vendor_assessment_templates where id = p_template_version_id;
  if not found then
    raise exception 'vendor_assessment_template_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;
  if v_template.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment template % expected version % but found %', p_template_version_id, p_expected_version, v_template.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_template.status <> 'published' then
    raise exception 'invalid_transition: vendor assessment template % is % and cannot be archived', p_template_version_id, v_template.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assessment_templates
  set status = 'archived', updated_at = now(), record_version = record_version + 1
  where id = p_template_version_id and record_version = p_expected_version
  returning * into v_template;
  if not found then
    raise exception 'stale_version: vendor assessment template % target row was concurrently modified (expected version %)', p_template_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_template.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_vendor_assessment_template',
    'app.vendor_assessment_templates', v_template.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_template;
end;
$$;

-- ===========================================================================
-- 10. Assessment lifecycle RPCs.
-- ===========================================================================

create function app.start_vendor_assessment(
  p_vendor_master_record_id uuid, p_template_version_id uuid, p_reviewer_auth_user_id uuid, p_idempotency_key text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_template app.vendor_assessment_templates;
  v_existing app.vendor_assessments;
  v_constraint_name text;
  v_assessment app.vendor_assessments;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_vendor.lifecycle_status = 'blacklisted' then
    raise exception 'vendor_blacklisted: vendor % is blacklisted -- no new assessment cycle may be started', p_vendor_master_record_id
      using errcode = 'check_violation';
  end if;

  if p_reviewer_auth_user_id is not null and p_reviewer_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: assessor % may not pre-assign themselves as the reviewer', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_template from app.vendor_assessment_templates where id = p_template_version_id and tenant_id = v_vendor.tenant_id;
  if not found or v_template.status <> 'published' then
    raise exception 'template_not_published: vendor assessment template % is not a published template for tenant %', p_template_version_id, v_vendor.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_template.vendor_category is not null and v_template.vendor_category <> v_vendor.vendor_category then
    raise exception 'template_category_mismatch: template % applies to vendor_category % but vendor % is %', p_template_version_id, v_template.vendor_category, p_vendor_master_record_id, v_vendor.vendor_category
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_assessments where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.template_version_id is distinct from p_template_version_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assessment (vendor %, template %)', p_idempotency_key, v_existing.vendor_master_record_id, v_existing.template_version_id
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  -- One open assessment per (vendor, assessment_type) is a structural guard
  -- (vendor_assessments_one_open_per_type_idx) -- a pre-check here gives a clean
  -- error for the ordinary sequential case; the nested exception below recovers
  -- correctly for a genuine concurrent race, distinguishing WHICH unique index
  -- fired via GET STACKED DIAGNOSTICS rather than guessing.
  if exists (
    select 1 from app.vendor_assessments
    where vendor_master_record_id = p_vendor_master_record_id and assessment_type = v_template.assessment_type
      and status in ('draft', 'in_progress', 'submitted', 'under_review')
  ) then
    raise exception 'conflicting_active_assessment: vendor % already has an open % assessment', p_vendor_master_record_id, v_template.assessment_type
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.vendor_assessments (
      tenant_id, vendor_master_record_id, template_version_id, assessment_type, assessor_auth_user_id, reviewer_auth_user_id,
      idempotency_key, created_by
    ) values (
      v_vendor.tenant_id, p_vendor_master_record_id, p_template_version_id, v_template.assessment_type, p_actor_auth_user_id, p_reviewer_auth_user_id,
      p_idempotency_key, p_actor_label
    )
    returning * into v_assessment;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_assessments_idempotency_key_unique' and p_idempotency_key is not null then
        select * into v_existing from app.vendor_assessments where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
        if not found then
          raise;
        end if;
        if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.template_version_id is distinct from p_template_version_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor assessment (vendor %, template %)', p_idempotency_key, v_existing.vendor_master_record_id, v_existing.template_version_id
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      elsif v_constraint_name = 'vendor_assessments_one_open_per_type_idx' then
        raise exception 'conflicting_active_assessment: vendor % already has an open % assessment', p_vendor_master_record_id, v_template.assessment_type
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    v_vendor.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_vendor_assessment',
    'app.vendor_assessments', v_assessment.id, 'success', null, null, to_jsonb(v_assessment)
  );

  return v_assessment;
end;
$$;

comment on function app.start_vendor_assessment is 'PRC-252: blocks a stale (non-published) template, a category mismatch, a blacklisted vendor, and a conflicting already-open assessment for the same (vendor, assessment_type) -- prompt Sec.23''s exception-flow list. template_version_id is stored verbatim as the applied-version snapshot (design note 1).';

create function app.record_vendor_assessment_answer(
  p_assessment_id uuid, p_criterion_id uuid, p_value text, p_score numeric, p_evidence_file_id uuid, p_notes text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessment_answers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_assessment app.vendor_assessments;
  v_criterion app.vendor_assessment_template_criteria;
  v_answer app.vendor_assessment_answers;
  v_file app.files;
begin
  v_assessment := app.assert_vendor_assessment_editable(p_assessment_id, p_actor_auth_user_id);

  select * into v_criterion from app.vendor_assessment_template_criteria
    where id = p_criterion_id and template_version_id = v_assessment.template_version_id and status = 'active';
  if not found then
    raise exception 'criterion_not_in_template: criterion % does not belong to vendor assessment %''s own applied template version', p_criterion_id, p_assessment_id
      using errcode = 'check_violation';
  end if;

  if p_score is null or p_score < 0 or p_score > 100 then
    raise exception 'invalid_score: score must be between 0 and 100' using errcode = 'check_violation';
  end if;

  -- Evidence re-validation (adversarial review, reproduced): mirrors
  -- app.record_gps_device_installation's own exact shape
  -- (20260729350000_create_advanced_tms_device_installation_evidence.sql) -- a bare
  -- FK previously let a caller "launder" any file of any tenant/record_type/scan
  -- status into an assessment's own evidence trail. Re-fetch and reject on tenant
  -- mismatch, wrong record_type/record_id, or a non-clean malware scan ("unsafe
  -- evidence", Sec.23's own named block condition).
  if p_evidence_file_id is not null then
    select * into v_file from app.files where id = p_evidence_file_id;
    if not found then
      raise exception 'evidence_file_not_found: %', p_evidence_file_id using errcode = 'no_data_found';
    end if;
    if v_file.tenant_id <> v_assessment.tenant_id or v_file.record_type <> 'vendor_assessment' or v_file.record_id <> p_assessment_id then
      raise exception 'assessment_evidence_file_mismatch: file % does not belong to vendor assessment % in tenant %', p_evidence_file_id, p_assessment_id, v_assessment.tenant_id
        using errcode = 'check_violation';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'assessment_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be recorded', p_evidence_file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  insert into app.vendor_assessment_answers (tenant_id, assessment_id, criterion_id, value, score, evidence_file_id, notes, created_by)
  values (v_assessment.tenant_id, p_assessment_id, p_criterion_id, p_value, p_score, p_evidence_file_id, p_notes, p_actor_label)
  on conflict (assessment_id, criterion_id) do update
    set value = excluded.value, score = excluded.score, evidence_file_id = excluded.evidence_file_id, notes = excluded.notes
  returning * into v_answer;

  -- The parent assessment row is already exclusively locked (`for update`, inside
  -- app.assert_vendor_assessment_editable, same transaction) -- this side-effect
  -- draft->in_progress transition needs no separate record_version match, since no
  -- concurrent writer could have changed it between lock acquisition and here.
  if v_assessment.status = 'draft' then
    update app.vendor_assessments set status = 'in_progress', updated_at = now(), record_version = record_version + 1 where id = p_assessment_id;
  end if;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_vendor_assessment_answer',
    'app.vendor_assessment_answers', v_answer.id, 'success', null, null, to_jsonb(v_answer)
  );

  return v_answer;
end;
$$;

create function app.calculate_vendor_assessment_score(p_assessment_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
  v_score record;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id for update;
  if not found then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment % expected version % but found %', p_assessment_id, p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_assessment.status = 'closed' then
    raise exception 'vendor_assessment_closed: cannot recalculate a closed vendor assessment %', p_assessment_id using errcode = 'check_violation';
  end if;

  select * into v_score from app._compute_vendor_assessment_score(v_assessment.template_version_id, p_assessment_id);

  update app.vendor_assessments
  set calculated_score = v_score.out_total, score_band = v_score.out_band, record_version = record_version + 1, updated_at = now()
  where id = p_assessment_id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: vendor assessment % target row was concurrently modified (expected version %)', p_assessment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_vendor_assessment_score',
    'app.vendor_assessments', v_assessment.id, 'success', null, null,
    jsonb_build_object('calculated_score', v_score.out_total, 'score_band', v_score.out_band, 'answered_count', v_score.out_answered_count, 'criterion_count', v_score.out_criterion_count)
  );

  return v_assessment;
end;
$$;

comment on function app.calculate_vendor_assessment_score is 'PRC-252: callable any time before closed (e.g. "see running score" mid-questionnaire) -- persists calculated_score/score_band via app._compute_vendor_assessment_score, the same helper app.submit_vendor_assessment_for_review calls so the two never diverge (design note 3).';

create function app.submit_vendor_assessment_for_review(
  p_assessment_id uuid, p_expected_version integer, p_reviewer_auth_user_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_assessment app.vendor_assessments;
  v_score record;
begin
  v_assessment := app.assert_vendor_assessment_editable(p_assessment_id, p_actor_auth_user_id);

  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment % expected version % but found %', p_assessment_id, p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reviewer_auth_user_id is not null and p_reviewer_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: assessor % may not assign themselves as the reviewer', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_score from app._compute_vendor_assessment_score(v_assessment.template_version_id, p_assessment_id);
  if v_score.out_criterion_count = 0 then
    raise exception 'template_has_no_criteria: applied template version % defines no active criteria', v_assessment.template_version_id
      using errcode = 'check_violation';
  end if;
  if v_score.out_answered_count < v_score.out_criterion_count then
    raise exception 'missing_required_criteria: % of % required criteria answered for vendor assessment %', v_score.out_answered_count, v_score.out_criterion_count, p_assessment_id
      using errcode = 'check_violation';
  end if;

  update app.vendor_assessments
  set status = 'submitted', calculated_score = v_score.out_total, score_band = v_score.out_band, submitted_at = now(),
      reviewer_auth_user_id = coalesce(p_reviewer_auth_user_id, reviewer_auth_user_id), record_version = record_version + 1, updated_at = now()
  where id = p_assessment_id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: vendor assessment % target row was concurrently modified (expected version %)', p_assessment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_vendor_assessment_for_review',
    'app.vendor_assessments', v_assessment.id, 'success', null, null,
    jsonb_build_object('calculated_score', v_score.out_total, 'score_band', v_score.out_band)
  );

  return v_assessment;
end;
$$;

create function app.begin_vendor_assessment_review(p_assessment_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id for update;
  if not found then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;
  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment % expected version % but found %', p_assessment_id, p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Defense in depth (design note 4) -- the mandatory block point is
  -- app.decide_vendor_assessment_review, but refusing the assessor here too avoids
  -- a reviewer identity ever being set to the assessor in the first place.
  if p_actor_auth_user_id = v_assessment.assessor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % assessed vendor assessment % and may not also review it', p_actor_auth_user_id, p_assessment_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_assessment.reviewer_auth_user_id is not null and v_assessment.reviewer_auth_user_id <> p_actor_auth_user_id then
    raise exception 'review_already_assigned: vendor assessment % is already assigned to a different reviewer', p_assessment_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assessment.status <> 'submitted' then
    raise exception 'invalid_transition: vendor assessment % is % and cannot begin review', p_assessment_id, v_assessment.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assessments
  set status = 'under_review', reviewer_auth_user_id = p_actor_auth_user_id, record_version = record_version + 1, updated_at = now()
  where id = p_assessment_id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: vendor assessment % target row was concurrently modified (expected version %)', p_assessment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'begin_vendor_assessment_review',
    'app.vendor_assessments', v_assessment.id, 'success', null, null, '{}'::jsonb
  );

  return v_assessment;
end;
$$;

create function app.decide_vendor_assessment_review(
  p_assessment_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
  v_template app.vendor_assessment_templates;
  v_new_status text;
  v_expiry date;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'reject' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a vendor assessment' using errcode = 'check_violation';
  end if;

  select * into v_assessment from app.vendor_assessments where id = p_assessment_id for update;
  if not found then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;
  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment % expected version % but found %', p_assessment_id, p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;

  -- MANDATORY maker-checker block (design note 4, prompt Sec.23) -- checked before
  -- the authority evaluation so an assessor who also happens to hold PRC:Approve/
  -- Reject for their own tenant is refused on identity grounds, not merely on
  -- permission grounds.
  if p_actor_auth_user_id = v_assessment.assessor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % assessed vendor assessment % and may not also decide its review', p_actor_auth_user_id, p_assessment_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Reviewer exclusivity (adversarial review, reproduced): once a reviewer is
  -- assigned (app.begin_vendor_assessment_review, or a p_reviewer_auth_user_id
  -- pre-assignment at start/submit), only THAT reviewer may decide -- otherwise the
  -- terminal `coalesce(reviewer_auth_user_id, p_actor_auth_user_id)` below is a
  -- no-op once reviewer_auth_user_id is already non-null, so a DIFFERENT
  -- Approve/Reject-holding actor could decide while the row silently kept
  -- misattributing the decision to the originally-assigned reviewer. Mirrors
  -- app.begin_vendor_assessment_review's own review_already_assigned guard.
  if v_assessment.reviewer_auth_user_id is not null and v_assessment.reviewer_auth_user_id <> p_actor_auth_user_id then
    raise exception 'review_already_assigned: vendor assessment % is already assigned to a different reviewer', p_assessment_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', case p_decision when 'approve' then 'Approve' else 'Reject' end);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, initcap(p_decision), v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assessment.status not in ('submitted', 'under_review') then
    raise exception 'invalid_transition: vendor assessment % is % and cannot be decided', p_assessment_id, v_assessment.status
      using errcode = 'check_violation';
  end if;

  v_new_status := case p_decision when 'approve' then 'approved' else 'rejected' end;
  v_expiry := null;
  if p_decision = 'approve' then
    select * into v_template from app.vendor_assessment_templates where id = v_assessment.template_version_id;
    v_expiry := (now())::date + v_template.validity_period_days;
  end if;

  update app.vendor_assessments
  set status = v_new_status, decision_reason = p_reason, decided_at = now(), expiry_date = v_expiry,
      reviewer_auth_user_id = coalesce(reviewer_auth_user_id, p_actor_auth_user_id), record_version = record_version + 1, updated_at = now()
  where id = p_assessment_id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: vendor assessment % target row was concurrently modified (expected version %)', p_assessment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_assessment_review',
    'app.vendor_assessments', v_assessment.id, 'success', p_reason, null, jsonb_build_object('decision', p_decision, 'status', v_new_status, 'expiry_date', v_expiry)
  );

  return v_assessment;
end;
$$;

comment on function app.decide_vendor_assessment_review is 'PRC-252: MANDATORY maker-checker (design note 4) -- rejects self_approval_not_allowed if the actor is the assessment''s own assessor, mirroring app.approve_warehouse_billing_event''s exact wording/shape. On approve, expiry_date = decided_at::date + the applied template''s own validity_period_days.';

create function app.adjust_vendor_assessment_score(
  p_assessment_id uuid, p_expected_version integer, p_adjusted_score numeric, p_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
  v_before numeric;
  v_before_band text;
  v_new_band text;
  v_pass numeric;
  v_conditional numeric;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to manually adjust a vendor assessment score' using errcode = 'check_violation';
  end if;
  if p_adjusted_score is null or p_adjusted_score < 0 or p_adjusted_score > 100 then
    raise exception 'invalid_adjusted_score: adjusted_score must be between 0 and 100' using errcode = 'check_violation';
  end if;

  select * into v_assessment from app.vendor_assessments where id = p_assessment_id for update;
  if not found then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;
  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment % expected version % but found %', p_assessment_id, p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assessment.status not in ('submitted', 'under_review') then
    raise exception 'invalid_transition: vendor assessment % is % -- a score may only be manually adjusted while submitted or under_review', p_assessment_id, v_assessment.status
      using errcode = 'check_violation';
  end if;

  -- "before" is the prior EFFECTIVE score -- a second override in the same
  -- assessment correctly records the prior adjustment as its own before value
  -- (design note 5), not the original machine-calculated score a first override
  -- may have already superseded.
  v_before := coalesce(v_assessment.adjusted_score, v_assessment.calculated_score);
  v_before_band := v_assessment.score_band;

  -- score_band is RECOMPUTED against the adjusted score (adversarial review,
  -- reproduced: previously score_band stayed frozen at whatever the machine
  -- calculation last produced, so an approved assessment could persist
  -- adjusted_score=55/score_band='pass' -- a materially misleading pairing on the
  -- exact source-of-truth row app.get_vendor_current_assessment_status exposes to
  -- downstream eligibility composition, Sec.4/21/33's own "explainable" requirement).
  select pass_threshold, conditional_threshold into v_pass, v_conditional
  from app.vendor_assessment_templates where id = v_assessment.template_version_id;
  v_new_band := case
    when p_adjusted_score >= v_pass then 'pass'
    when p_adjusted_score >= v_conditional then 'conditional'
    else 'fail'
  end;

  update app.vendor_assessments
  set adjusted_score = p_adjusted_score, score_band = v_new_band, adjustment_reason = p_reason, adjusted_by = p_actor_label, adjusted_by_auth_user_id = p_actor_auth_user_id,
      adjusted_at = now(), record_version = record_version + 1, updated_at = now()
  where id = p_assessment_id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: vendor assessment % target row was concurrently modified (expected version %)', p_assessment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'adjust_vendor_assessment_score',
    'app.vendor_assessments', v_assessment.id, 'success', p_reason,
    jsonb_build_object('score', v_before, 'score_band', v_before_band), jsonb_build_object('score', p_adjusted_score, 'score_band', v_new_band)
  );

  return v_assessment;
end;
$$;

comment on function app.adjust_vendor_assessment_score is 'PRC-252: PRC:Override-gated, mandatory reason (prompt Sec.24). before_value/after_value are BOTH genuinely recorded in app.capture_audit_event, plus the dedicated adjusted_score/adjustment_reason/adjusted_by/adjusted_at column pair on the row itself for direct display (design note 5). score_band is recomputed against the adjusted score (never left stale at the machine-calculated band) so the persisted score/band pairing is never self-contradictory.';

create function app.close_vendor_assessment(p_assessment_id uuid, p_expected_version integer, p_override_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
  v_open_count integer;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id for update;
  if not found then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;
  if v_assessment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment % expected version % but found %', p_assessment_id, p_expected_version, v_assessment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_assessment.status not in ('approved', 'rejected') then
    raise exception 'invalid_transition: vendor assessment % is % and cannot be closed', p_assessment_id, v_assessment.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_open_count from app.vendor_assessment_corrective_actions where assessment_id = p_assessment_id and status in ('open', 'overdue');

  if v_open_count > 0 then
    if p_override_reason is null or length(trim(p_override_reason)) = 0 then
      raise exception 'open_corrective_actions_block_close: % open corrective action(s) remain on vendor assessment % -- supply an override reason to close anyway', v_open_count, p_assessment_id
        using errcode = 'check_violation';
    end if;
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Override');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  update app.vendor_assessments
  set status = 'closed', record_version = record_version + 1, updated_at = now()
  where id = p_assessment_id and record_version = p_expected_version
  returning * into v_assessment;
  if not found then
    raise exception 'stale_version: vendor assessment % target row was concurrently modified (expected version %)', p_assessment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_vendor_assessment',
    'app.vendor_assessments', v_assessment.id, 'success', p_override_reason, null, jsonb_build_object('open_corrective_action_count', v_open_count)
  );

  return v_assessment;
end;
$$;

comment on function app.close_vendor_assessment is 'PRC-252: requires status approved|rejected. If any corrective action is still open|overdue, PRC:Override plus a non-empty override reason is required (prompt Sec.23''s own exception flow); otherwise plain PRC:Edit suffices.';

create function app.start_vendor_assessment_reassessment(
  p_predecessor_assessment_id uuid, p_template_version_id uuid, p_reviewer_auth_user_id uuid, p_idempotency_key text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_predecessor app.vendor_assessments;
  v_template app.vendor_assessment_templates;
  v_vendor app.vendor_profiles;
  v_existing app.vendor_assessments;
  v_constraint_name text;
  v_assessment app.vendor_assessments;
begin
  select * into v_predecessor from app.vendor_assessments where id = p_predecessor_assessment_id;
  if not found then
    raise exception 'vendor_assessment_not_found: %', p_predecessor_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_predecessor.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_predecessor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- 'closed' is a legitimate predecessor too -- it is 'approved' plus a completed
  -- corrective-action reconciliation (app.close_vendor_assessment), never a
  -- regression away from approved; a rejected/draft/in-flight assessment is not.
  if v_predecessor.status not in ('approved', 'closed') then
    raise exception 'predecessor_not_approved: vendor assessment % is % -- only an approved or closed assessment may be reassessed', p_predecessor_assessment_id, v_predecessor.status
      using errcode = 'check_violation';
  end if;
  if p_reviewer_auth_user_id is not null and p_reviewer_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: assessor % may not pre-assign themselves as the reviewer', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_vendor from app.vendor_profiles where master_record_id = v_predecessor.vendor_master_record_id;
  if v_vendor.lifecycle_status = 'blacklisted' then
    raise exception 'vendor_blacklisted: vendor % is blacklisted -- no new assessment cycle may be started', v_predecessor.vendor_master_record_id
      using errcode = 'check_violation';
  end if;

  select * into v_template from app.vendor_assessment_templates where id = p_template_version_id and tenant_id = v_predecessor.tenant_id;
  if not found or v_template.status <> 'published' then
    raise exception 'template_not_published: vendor assessment template % is not a published template for tenant %', p_template_version_id, v_predecessor.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_template.assessment_type <> v_predecessor.assessment_type then
    raise exception 'reassessment_type_mismatch: template % is type % but predecessor assessment % is type %', p_template_version_id, v_template.assessment_type, p_predecessor_assessment_id, v_predecessor.assessment_type
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_assessments where tenant_id = v_predecessor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.predecessor_assessment_id is distinct from p_predecessor_assessment_id or v_existing.template_version_id is distinct from p_template_version_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different reassessment (predecessor %, template %)', p_idempotency_key, v_existing.predecessor_assessment_id, v_existing.template_version_id
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if exists (
    select 1 from app.vendor_assessments
    where vendor_master_record_id = v_predecessor.vendor_master_record_id and assessment_type = v_template.assessment_type
      and status in ('draft', 'in_progress', 'submitted', 'under_review')
  ) then
    raise exception 'conflicting_active_assessment: vendor % already has an open % assessment', v_predecessor.vendor_master_record_id, v_template.assessment_type
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.vendor_assessments (
      tenant_id, vendor_master_record_id, template_version_id, assessment_type, assessor_auth_user_id, reviewer_auth_user_id,
      predecessor_assessment_id, idempotency_key, created_by
    ) values (
      v_predecessor.tenant_id, v_predecessor.vendor_master_record_id, p_template_version_id, v_template.assessment_type, p_actor_auth_user_id, p_reviewer_auth_user_id,
      p_predecessor_assessment_id, p_idempotency_key, p_actor_label
    )
    returning * into v_assessment;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_assessments_idempotency_key_unique' and p_idempotency_key is not null then
        select * into v_existing from app.vendor_assessments where tenant_id = v_predecessor.tenant_id and idempotency_key = p_idempotency_key;
        if not found then
          raise;
        end if;
        if v_existing.predecessor_assessment_id is distinct from p_predecessor_assessment_id or v_existing.template_version_id is distinct from p_template_version_id then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different reassessment (predecessor %, template %)', p_idempotency_key, v_existing.predecessor_assessment_id, v_existing.template_version_id
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      elsif v_constraint_name = 'vendor_assessments_one_open_per_type_idx' then
        raise exception 'conflicting_active_assessment: vendor % already has an open % assessment', v_predecessor.vendor_master_record_id, v_template.assessment_type
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    v_predecessor.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_vendor_assessment_reassessment',
    'app.vendor_assessments', v_assessment.id, 'success', null, null, jsonb_build_object('predecessor_assessment_id', p_predecessor_assessment_id)
  );

  return v_assessment;
end;
$$;

comment on function app.start_vendor_assessment_reassessment is 'PRC-252: the manual "start reassessment" RPC (prompt''s own explicit "no scheduler" scope note, design note 6) -- references the prior assessment as predecessor_assessment_id. No cron/scheduler job is added (ISS-2026-015, standing repository-wide gap).';

-- ===========================================================================
-- 11. Findings and corrective actions.
-- ===========================================================================

create function app.raise_vendor_assessment_finding(p_assessment_id uuid, p_severity text, p_description text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessment_findings
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
  v_finding app.vendor_assessment_findings;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id;
  if not found then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_assessment.status not in ('draft', 'in_progress', 'submitted', 'under_review') then
    raise exception 'vendor_assessment_not_active: vendor assessment % is % -- a finding may only be raised against an active assessment', p_assessment_id, v_assessment.status
      using errcode = 'check_violation';
  end if;
  if coalesce(p_severity, '') not in ('low', 'medium', 'high', 'critical') then
    raise exception 'invalid_severity: % is not a recognized severity', p_severity using errcode = 'check_violation';
  end if;
  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'invalid_finding: description must not be empty' using errcode = 'check_violation';
  end if;

  insert into app.vendor_assessment_findings (tenant_id, assessment_id, severity, description, created_by)
  values (v_assessment.tenant_id, p_assessment_id, p_severity, p_description, p_actor_label)
  returning * into v_finding;

  perform app.capture_audit_event(
    v_assessment.tenant_id, p_actor_auth_user_id, p_actor_label, 'raise_vendor_assessment_finding',
    'app.vendor_assessment_findings', v_finding.id, 'success', null, null, to_jsonb(v_finding)
  );

  return v_finding;
end;
$$;

create function app.decide_vendor_assessment_finding(p_finding_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessment_findings
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_finding app.vendor_assessment_findings;
  v_assessment app.vendor_assessments;
begin
  if p_decision not in ('resolved', 'waived') then
    raise exception 'invalid_decision: % is not resolved or waived', p_decision using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a vendor assessment finding' using errcode = 'check_violation';
  end if;

  select * into v_finding from app.vendor_assessment_findings where id = p_finding_id;
  if not found then
    raise exception 'finding_not_found: %', p_finding_id using errcode = 'no_data_found';
  end if;
  if v_finding.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment finding % expected version % but found %', p_finding_id, p_expected_version, v_finding.record_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_assessment from app.vendor_assessments where id = v_finding.assessment_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_finding.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_finding.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_finding.status <> 'open' then
    raise exception 'invalid_transition: vendor assessment finding % is already %', p_finding_id, v_finding.status using errcode = 'check_violation';
  end if;

  update app.vendor_assessment_findings
  set status = p_decision, resolution_reason = p_reason, resolved_by = p_actor_label, resolved_at = now()
  where id = p_finding_id and record_version = p_expected_version
  returning * into v_finding;
  if not found then
    raise exception 'stale_version: vendor assessment finding % target row was concurrently modified (expected version %)', p_finding_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_finding.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_assessment_finding',
    'app.vendor_assessment_findings', v_finding.id, 'success', p_reason, null, jsonb_build_object('decision', p_decision)
  );

  return v_finding;
end;
$$;

create function app.create_vendor_assessment_corrective_action(p_finding_id uuid, p_description text, p_due_date date, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_assessment_corrective_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_finding app.vendor_assessment_findings;
  v_assessment app.vendor_assessments;
  v_action app.vendor_assessment_corrective_actions;
begin
  select * into v_finding from app.vendor_assessment_findings where id = p_finding_id;
  if not found then
    raise exception 'finding_not_found: %', p_finding_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_finding.tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_finding.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_finding.status <> 'open' then
    raise exception 'finding_not_open: vendor assessment finding % is % -- a corrective action may only be raised against an open finding', p_finding_id, v_finding.status
      using errcode = 'check_violation';
  end if;
  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'invalid_corrective_action: description must not be empty' using errcode = 'check_violation';
  end if;

  -- `for update` on the parent assessment: closes a real, reproduced defect
  -- (adversarial review, both deterministic and true-concurrent-race forms) where a
  -- brand-new OPEN corrective action could be attached to an assessment that was
  -- already closed (or was being closed concurrently), silently defeating
  -- app.close_vendor_assessment's own PRC:Override + mandatory-reason governance
  -- gate for open-corrective-actions-at-close-time. Locking the SAME assessment row
  -- app.close_vendor_assessment itself locks serializes the two RPCs against each
  -- other; both a plain sequential closed-assessment attempt and a genuine
  -- concurrent race now correctly reject.
  select * into v_assessment from app.vendor_assessments where id = v_finding.assessment_id for update;
  if not found then
    raise exception 'vendor_assessment_not_found: %', v_finding.assessment_id using errcode = 'no_data_found';
  end if;
  if v_assessment.status = 'closed' then
    raise exception 'vendor_assessment_closed: vendor assessment % is closed -- no new corrective action may be added', v_finding.assessment_id
      using errcode = 'check_violation';
  end if;

  insert into app.vendor_assessment_corrective_actions (tenant_id, finding_id, assessment_id, description, due_date, created_by)
  values (v_finding.tenant_id, p_finding_id, v_finding.assessment_id, p_description, p_due_date, p_actor_label)
  returning * into v_action;

  perform app.capture_audit_event(
    v_finding.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_assessment_corrective_action',
    'app.vendor_assessment_corrective_actions', v_action.id, 'success', null, null, to_jsonb(v_action)
  );

  return v_action;
end;
$$;

create function app.update_vendor_assessment_corrective_action_status(
  p_corrective_action_id uuid, p_expected_version integer, p_new_status text, p_resolution_notes text, p_resolved_evidence_file_id uuid,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_assessment_corrective_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_action app.vendor_assessment_corrective_actions;
  v_resolved_by text;
  v_resolved_at timestamptz;
  v_notes text;
  v_evidence uuid;
  v_file app.files;
begin
  if p_new_status not in ('open', 'completed', 'overdue', 'waived') then
    raise exception 'invalid_status: % is not a recognized corrective action status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_action from app.vendor_assessment_corrective_actions where id = p_corrective_action_id;
  if not found then
    raise exception 'corrective_action_not_found: %', p_corrective_action_id using errcode = 'no_data_found';
  end if;
  if v_action.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assessment corrective action % expected version % but found %', p_corrective_action_id, p_expected_version, v_action.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_action.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_action.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if (v_action.status = 'open' and p_new_status not in ('completed', 'overdue', 'waived')) or
     (v_action.status = 'overdue' and p_new_status not in ('completed', 'waived')) or
     (v_action.status in ('completed', 'waived')) then
    raise exception 'invalid_transition: vendor assessment corrective action % is % and cannot move to %', p_corrective_action_id, v_action.status, p_new_status
      using errcode = 'check_violation';
  end if;

  if p_new_status in ('completed', 'waived') then
    if p_resolution_notes is null or length(trim(p_resolution_notes)) = 0 then
      raise exception 'resolution_notes_required: non-empty resolution_notes are required to mark a corrective action % ', p_new_status using errcode = 'check_violation';
    end if;
    v_resolved_by := p_actor_label;
    v_resolved_at := now();
    v_notes := p_resolution_notes;
    v_evidence := p_resolved_evidence_file_id;

    -- Evidence re-validation (adversarial review, reproduced): same shape as
    -- app.record_vendor_assessment_answer's own fix above -- re-fetch and reject on
    -- tenant mismatch, wrong record_type/record_id, or a non-clean malware scan.
    -- record_id is the ASSESSMENT's own id (v_action.assessment_id), matching how the
    -- server action actually uploads corrective-action evidence (record_type=
    -- 'vendor_assessment', record_id=assessmentId, the same evidence trail an
    -- answer's own evidence_file_id is uploaded against).
    if v_evidence is not null then
      select * into v_file from app.files where id = v_evidence;
      if not found then
        raise exception 'evidence_file_not_found: %', v_evidence using errcode = 'no_data_found';
      end if;
      if v_file.tenant_id <> v_action.tenant_id or v_file.record_type <> 'vendor_assessment' or v_file.record_id <> v_action.assessment_id then
        raise exception 'assessment_evidence_file_mismatch: file % does not belong to vendor assessment % in tenant %', v_evidence, v_action.assessment_id, v_action.tenant_id
          using errcode = 'check_violation';
      end if;
      if v_file.malware_scan_status <> 'clean' then
        raise exception 'assessment_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be recorded', v_evidence, v_file.malware_scan_status
          using errcode = 'check_violation';
      end if;
    end if;
  else
    v_resolved_by := null;
    v_resolved_at := null;
    v_notes := null;
    v_evidence := null;
  end if;

  update app.vendor_assessment_corrective_actions
  set status = p_new_status, resolution_notes = v_notes, resolved_evidence_file_id = v_evidence, resolved_by = v_resolved_by, resolved_at = v_resolved_at
  where id = p_corrective_action_id and record_version = p_expected_version
  returning * into v_action;
  if not found then
    raise exception 'stale_version: vendor assessment corrective action % target row was concurrently modified (expected version %)', p_corrective_action_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_action.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_assessment_corrective_action_status',
    'app.vendor_assessment_corrective_actions', v_action.id, 'success', p_resolution_notes, null, jsonb_build_object('status', p_new_status)
  );

  return v_action;
end;
$$;

-- ===========================================================================
-- 12. Read RPCs.
-- ===========================================================================

create function app.get_vendor_assessment_template(p_template_version_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, vendor_category text, assessment_type text, name text, description text, validity_period_days integer,
  pass_threshold numeric, conditional_threshold numeric, weight_total_required numeric, status text, supersedes_version_id uuid,
  effective_from timestamptz, record_version integer, created_by text, created_at timestamptz, updated_at timestamptz, criterion_count integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.vendor_assessment_templates;
begin
  select * into v_template from app.vendor_assessment_templates t where t.id = p_template_version_id;
  if not found then
    raise exception 'vendor_assessment_template_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select v_template.id, v_template.tenant_id, v_template.vendor_category, v_template.assessment_type, v_template.name, v_template.description,
    v_template.validity_period_days, v_template.pass_threshold, v_template.conditional_threshold, v_template.weight_total_required, v_template.status,
    v_template.supersedes_version_id, v_template.effective_from, v_template.record_version, v_template.created_by, v_template.created_at, v_template.updated_at,
    (select count(*)::integer from app.vendor_assessment_template_criteria c where c.template_version_id = p_template_version_id and c.status = 'active');
end;
$$;

create function app.list_vendor_assessment_templates(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_vendor_category text default null, p_assessment_type text default null,
  p_limit integer default 50, p_after_id uuid default null
)
returns setof app.vendor_assessment_templates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_status_filter is not null and p_status_filter not in ('draft', 'published', 'archived') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select t.* from app.vendor_assessment_templates t
  where t.tenant_id = p_tenant_id
    and (p_status_filter is null or t.status = p_status_filter)
    and (p_vendor_category is null or t.vendor_category = p_vendor_category)
    and (p_assessment_type is null or t.assessment_type = p_assessment_type)
    and (p_after_id is null or t.id > p_after_id)
  order by t.id
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create function app.list_vendor_assessment_template_criteria(p_template_version_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_assessment_template_criteria
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_template app.vendor_assessment_templates;
begin
  select * into v_template from app.vendor_assessment_templates where id = p_template_version_id;
  if not found then
    raise exception 'vendor_assessment_template_not_found: %', p_template_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_template.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_template.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_assessment_template_criteria where template_version_id = p_template_version_id and status = 'active' order by display_order, label;
end;
$$;

create function app.get_vendor_assessment(p_assessment_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, vendor_master_record_id uuid, template_version_id uuid, assessment_type text, status text,
  assessor_auth_user_id uuid, reviewer_auth_user_id uuid, calculated_score numeric, score_band text, adjusted_score numeric,
  adjustment_reason text, adjusted_by text, adjusted_at timestamptz, submitted_at timestamptz, decided_at timestamptz,
  decision_reason text, expiry_date date, reassessment_due boolean, predecessor_assessment_id uuid, record_version integer,
  created_by text, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
begin
  select * into v_assessment from app.vendor_assessments a where a.id = p_assessment_id;
  if not found then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select v_assessment.id, v_assessment.tenant_id, v_assessment.vendor_master_record_id, v_assessment.template_version_id, v_assessment.assessment_type, v_assessment.status,
    v_assessment.assessor_auth_user_id, v_assessment.reviewer_auth_user_id, v_assessment.calculated_score, v_assessment.score_band, v_assessment.adjusted_score,
    v_assessment.adjustment_reason, v_assessment.adjusted_by, v_assessment.adjusted_at, v_assessment.submitted_at, v_assessment.decided_at,
    v_assessment.decision_reason, v_assessment.expiry_date, (v_assessment.expiry_date is not null and v_assessment.expiry_date < current_date), v_assessment.predecessor_assessment_id,
    v_assessment.record_version, v_assessment.created_by, v_assessment.created_at, v_assessment.updated_at;
end;
$$;

create function app.list_vendor_assessments(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_vendor_master_record_id uuid default null,
  p_assigned_to_me boolean default false, p_limit integer default 50, p_after_id uuid default null
)
returns setof app.vendor_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_status_filter is not null and p_status_filter not in ('draft', 'in_progress', 'submitted', 'under_review', 'approved', 'rejected', 'closed') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select a.* from app.vendor_assessments a
  where a.tenant_id = p_tenant_id
    and (p_status_filter is null or a.status = p_status_filter)
    and (p_vendor_master_record_id is null or a.vendor_master_record_id = p_vendor_master_record_id)
    and (not p_assigned_to_me or a.assessor_auth_user_id = p_actor_auth_user_id or a.reviewer_auth_user_id = p_actor_auth_user_id)
    and (p_after_id is null or a.id > p_after_id)
  order by a.id
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create function app.get_vendor_assessment_score_breakdown(p_assessment_id uuid, p_actor_auth_user_id uuid)
returns table (
  criterion_id uuid, label text, purpose_tag text, weight numeric, answer_score numeric, contribution numeric,
  value text, notes text, evidence_file_id uuid, answered boolean
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
  v_view_cost boolean;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id;
  if not found then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_view_cost := app.has_prc_view_cost(v_assessment.tenant_id, p_actor_auth_user_id);

  -- purpose-bound masking (Sec.26, design note 7): weight/answer_score/contribution
  -- stay visible to any PRC:View holder regardless of purpose_tag -- the numeric
  -- score IS the explainable-scoring requirement (Sec.4/21/33, itself mandatory) and
  -- is an abstracted figure, not raw evidence content. value/notes/evidence_file_id
  -- are ALL masked together for 'financial' (adversarial review: evidence_file_id
  -- was previously left unmasked even when value/notes were masked, letting a
  -- non-cost-viewer chase down the underlying file reference). 'safety'/'compliance'
  -- are not masked -- no seeded PRC action fits either distinctly (design note 7's
  -- own fuller explanation of why this migration does not widen the fixed
  -- permissions_action_check enum to invent one).
  return query
  select c.id, c.label, c.purpose_tag, c.weight, a.score,
    round(c.weight * coalesce(a.score, 0) / 100.0, 2),
    case when c.purpose_tag = 'financial' and not v_view_cost then null else a.value end,
    case when c.purpose_tag = 'financial' and not v_view_cost then null else a.notes end,
    case when c.purpose_tag = 'financial' and not v_view_cost then null else a.evidence_file_id end,
    (a.id is not null)
  from app.vendor_assessment_template_criteria c
  left join app.vendor_assessment_answers a on a.criterion_id = c.id and a.assessment_id = p_assessment_id
  where c.template_version_id = v_assessment.template_version_id and c.status = 'active'
  order by c.display_order, c.label;
end;
$$;

comment on function app.get_vendor_assessment_score_breakdown is 'PRC-252: the explainable-scoring READ RPC (design note 3) -- one row per active criterion in the assessment''s own applied template version, with weight/answer_score/contribution ("criterion X contributed Y points because weight Z * score W"). value/notes/evidence_file_id are ALL masked (null) together for financial purpose_tag unless the caller holds PRC:View cost (design note 7). safety/compliance are not masked -- no seeded PRC action fits either distinctly; see design note 7 for why this migration does not widen the fixed action enum to add one.';

create function app.list_vendor_assessment_findings(p_assessment_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_assessment_findings
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id;
  if not found then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_assessment_findings where assessment_id = p_assessment_id order by created_at desc;
end;
$$;

create function app.list_vendor_assessment_corrective_actions(p_assessment_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_assessment_corrective_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_assessment app.vendor_assessments;
begin
  select * into v_assessment from app.vendor_assessments where id = p_assessment_id;
  if not found then
    raise exception 'vendor_assessment_not_found: %', p_assessment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_assessment.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_assessment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_assessment_corrective_actions where assessment_id = p_assessment_id order by created_at desc;
end;
$$;

create function app.get_vendor_current_assessment_status(p_vendor_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (
  assessment_type text, assessment_id uuid, status text, calculated_score numeric, adjusted_score numeric, score_band text,
  decided_at timestamptz, expiry_date date, reassessment_due boolean
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select distinct on (a.assessment_type)
    a.assessment_type, a.id, a.status, a.calculated_score, a.adjusted_score, a.score_band, a.decided_at, a.expiry_date,
    (a.expiry_date is not null and a.expiry_date < current_date)
  from app.vendor_assessments a
  where a.vendor_master_record_id = p_vendor_master_record_id and a.status in ('approved', 'rejected')
  order by a.assessment_type, (a.status = 'approved') desc, a.created_at desc;
end;
$$;

comment on function app.get_vendor_current_assessment_status is 'PRC-252: the downstream-composable read RPC (prompt''s own "Downstream" scope note) -- one row per assessment_type, preferring the most recent APPROVED assessment when one exists, else the most recent decided (rejected) one. Prompts 253/256+ compose eligibility against this; this migration itself never mutates app.vendor_profiles.lifecycle_status.';

-- ===========================================================================
-- 13. RLS -- default-deny form, identical shape to PRC-251.
-- ===========================================================================

alter table app.vendor_assessment_templates enable row level security;
alter table app.vendor_assessment_template_criteria enable row level security;
alter table app.vendor_assessments enable row level security;
alter table app.vendor_assessment_answers enable row level security;
alter table app.vendor_assessment_findings enable row level security;
alter table app.vendor_assessment_corrective_actions enable row level security;

create policy vendor_assessment_templates_select_scoped on app.vendor_assessment_templates
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_assessment_template_criteria_select_scoped on app.vendor_assessment_template_criteria
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_assessments_select_scoped on app.vendor_assessments
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_assessment_answers_select_scoped on app.vendor_assessment_answers
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_assessment_findings_select_scoped on app.vendor_assessment_findings
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_assessment_corrective_actions_select_scoped on app.vendor_assessment_corrective_actions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 14. Grants.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.vendor_assessment_templates to authenticated, service_role;
grant insert, update, delete on app.vendor_assessment_templates to service_role;
grant select on app.vendor_assessment_template_criteria to authenticated, service_role;
grant insert, update, delete on app.vendor_assessment_template_criteria to service_role;
grant select on app.vendor_assessments to authenticated, service_role;
grant insert, update, delete on app.vendor_assessments to service_role;
grant select on app.vendor_assessment_answers to authenticated, service_role;
grant insert, update, delete on app.vendor_assessment_answers to service_role;
grant select on app.vendor_assessment_findings to authenticated, service_role;
grant insert, update, delete on app.vendor_assessment_findings to service_role;
grant select on app.vendor_assessment_corrective_actions to authenticated, service_role;
grant insert, update, delete on app.vendor_assessment_corrective_actions to service_role;

grant execute on function app.has_prc_view_cost(uuid, uuid) to authenticated, service_role;

grant execute on function app.create_vendor_assessment_template_draft(uuid, text, text, text, text, integer, numeric, numeric, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_assessment_template_draft(uuid, integer, text, text, text, integer, numeric, numeric, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.add_vendor_assessment_template_criterion(uuid, text, text, numeric, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_assessment_template_criterion(uuid, integer, text, text, numeric, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.remove_vendor_assessment_template_criterion(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.publish_vendor_assessment_template(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.archive_vendor_assessment_template(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.start_vendor_assessment(uuid, uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_vendor_assessment_answer(uuid, uuid, text, numeric, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.calculate_vendor_assessment_score(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.submit_vendor_assessment_for_review(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.begin_vendor_assessment_review(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_assessment_review(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.adjust_vendor_assessment_score(uuid, integer, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.close_vendor_assessment(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.start_vendor_assessment_reassessment(uuid, uuid, uuid, text, uuid, text) to authenticated, service_role;

grant execute on function app.raise_vendor_assessment_finding(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_assessment_finding(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_vendor_assessment_corrective_action(uuid, text, date, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_assessment_corrective_action_status(uuid, integer, text, text, uuid, uuid, text) to authenticated, service_role;

grant execute on function app.get_vendor_assessment_template(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_assessment_templates(uuid, uuid, text, text, text, integer, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_assessment_template_criteria(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_vendor_assessment(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_assessments(uuid, uuid, text, uuid, boolean, integer, uuid) to authenticated, service_role;
grant execute on function app.get_vendor_assessment_score_breakdown(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_assessment_findings(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_assessment_corrective_actions(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_vendor_current_assessment_status(uuid, uuid) to authenticated, service_role;
