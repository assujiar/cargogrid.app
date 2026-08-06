-- Procurement capability PRC-253 (Compliance and Document Expiry, CG-S11-PRC-004).
-- Versioned compliance requirements, private evidence documents (extending PLT-128's
-- Document/File Engine, never forking it), verification, renewal, time-bounded
-- waivers, and a real, bounded, callable recalculation RPC that writes a per-vendor
-- eligibility-hold projection a future sourcing/PO/assignment capability (256+) can
-- compose against. Extends app.vendor_profiles (PRC-251, master_type_code='vendor'
-- via ADR-0020) -- every requirement/document/waiver/status row ultimately traces to
-- app.vendor_profiles.master_record_id. Never mutates
-- app.vendor_profiles.lifecycle_status (same boundary PRC-252 already respected).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Requirement versioning mirrors app.vendor_assessment_templates' exact
--    draft -> published -> archived shape** (PRC-252, itself mirroring
--    app.item_control_policy_versions/ATW-016), with ONE structural addition this
--    capability specifically needs: a stable `requirement_family_id` that survives
--    republish. PRC-252's own template_version_id is BOTH the applied-version
--    snapshot an assessment references AND the identity a caller resolves "the
--    current template for this scope" by -- because an assessment's own scoring
--    result never needs to survive a template republish (a new assessment cycle
--    just starts against the new version). A vendor's COMPLIANCE STANDING is
--    different: it must survive a requirement republish (tightening a reminder
--    schedule, or correcting a typo in the requirement name, must not silently
--    reset every vendor's own hold/status back to a blank slate on the next
--    recalculation). `requirement_family_id` is minted fresh on first creation and
--    is deliberately carried forward onto the new draft's own row only at PUBLISH
--    time (`app.publish_vendor_compliance_requirement`, when `p_supersedes_version_id`
--    is supplied) -- never earlier, so an in-progress draft has no borrowed identity
--    until it is actually confirmed as a continuation of an existing family. A
--    partial unique index (`requirement_family_id where status='published'`) then
--    structurally guarantees at most one live published version per family, the
--    same invariant `vendor_assessment_templates_published_unique` gives PRC-252 by
--    scope tuple alone (this capability additionally keeps that scope-tuple
--    uniqueness too, defensively -- design note 2).
-- 2. **`app.vendor_compliance_documents.requirement_version_id` is the RPD-040-style
--    immutable APPLIED-version snapshot** (identical discipline to PRC-252's own
--    `template_version_id`): a document submitted against requirement version N
--    stays linked to N forever, even after the requirement is republished to
--    version N+1 -- its own verification_status/expiry_date never retroactively
--    change because of a republish. What DOES change is which requirement the
--    FAMILY's aggregate `app.vendor_compliance_status` row is evaluated against on
--    the next recalculation: `app._recalculate_vendor_compliance_status_family`
--    resolves the vendor's own most-recently-submitted active document ANYWHERE in
--    the family's lineage (any requirement_version_id sharing the family), then
--    re-evaluates that SAME, unmodified evidence against whichever version is
--    CURRENTLY published. This is the literal, deliberate reading of "a vendor's
--    compliance status must survive a requirement republish" the task brief itself
--    asks to be thought through -- the document is a fact of history, the status is
--    a live governance projection over that history.
-- 3. **A defensive, non-required scope-tuple uniqueness constraint is ALSO kept**
--    (`vendor_compliance_requirements_published_scope_unique`, mirroring PRC-252's
--    own `vendor_assessment_templates_published_unique` byte-for-byte) --
--    (tenant_id, vendor_category, service_type, document_type_code) can have at
--    most one published requirement at a time. Two independent families could in
--    principle target the identical practical scope+document type, which would make
--    "which requirement applies" genuinely ambiguous for a vendor and for
--    `app.get_vendor_compliance_eligibility`'s downstream composition -- this
--    closes that off structurally rather than leaving it to application discipline.
-- 4. **Renewal creates a linked new version, never overwrites** (Sec.24's own
--    explicit business rule) -- `app.renew_vendor_compliance_document` mirrors
--    `app.create_file_version`'s exact shape at the compliance-document level:
--    flips the prior row's `is_latest_version` to false FIRST, then inserts the new
--    row sharing `version_group_id`/incrementing `version_number` -- the prior
--    evidence row, and the underlying `app.files` row it references, are NEVER
--    deleted, satisfying Sec.24's "expiry never silently deletes evidence." A
--    partial unique index (`requirement_version_id, vendor_master_record_id where
--    is_latest_version`) keeps exactly one ACTIVE submission per (vendor,
--    requirement-version) slot, so a second independent `submit` against an
--    already-occupied slot is rejected `active_submission_exists` -- renewal is the
--    only path to superseding it, matching PLT-128's own "versioning never
--    overwrites" precedent literally, one layer up.
-- 5. **Evidence-file re-validation on EVERY file_id parameter** (Sec.16/24's own
--    "unavailable to another user until RPD-032 scan policy permits it", and this
--    session's own standing discipline after PRC-252's adversarial review found and
--    fixed exactly this gap): `app.submit_vendor_compliance_document` and
--    `app.renew_vendor_compliance_document` both re-fetch `app.files` and reject on
--    tenant mismatch, wrong record scope, or a non-`clean` malware scan --
--    `record_type='vendor_compliance'`, `record_id=`the vendor's own
--    `master_record_id` (the file was uploaded "for this vendor's compliance
--    purpose", this task's own Sec.16/24 wording for a pre-existing-upload link).
--    Legal hold is REUSED directly against the underlying `app.files` row via
--    `app.set_file_legal_hold` -- no second, parallel legal-hold column is added to
--    `app.vendor_compliance_documents` (this task's own explicit instruction).
-- 6. **One generic PRC-owned document_type_code, not one per compliance document
--    title** -- mirrors PRC-252's own `vendor_assessment_evidence` precedent
--    exactly. `app.document_types` is confirmed a GLOBAL registry (`code text
--    primary key`, no `tenant_id` column, PLT-128's own migration read in full) --
--    it names a *kind* of file, not a specific compliance document's own title
--    ("business license" vs "insurance certificate" are both just PDFs/images to the
--    file engine). `app.vendor_compliance_requirements.document_type_code` still
--    carries a real FK to `app.document_types(code)` per this task's own explicit
--    schema request, but every requirement seeded by this capability's own db-test
--    fixture (and, in a real tenant, by whichever admin configures compliance)
--    reuses a single registered code, `vendor_compliance_document` -- registered the
--    identical way PRC-252 registered its own type: `app.register_document_type`
--    (Supreme-Admin-gated, side-effecting, idempotent) called from db-test/runtime
--    setup, never seeded inside this schema migration itself (a schema-definition
--    migration is not the place for an operational registry INSERT).
-- 7. **`app.vendor_compliance_status` is written ONLY by
--    `app.recalculate_vendor_compliance_status`'s own compute logic** -- concretely,
--    a single private helper (`app._recalculate_vendor_compliance_status_family`,
--    no grant to anyone but its owner) performs the ONLY `insert ... on conflict do
--    update` this table ever receives, anywhere in this migration. The public,
--    `PRC:Edit`-gated `app.recalculate_vendor_compliance_status(vendor_master_record_id,
--    ...)` RPC is the one documented entry point a caller (UI "Recalculate" button,
--    or a future scheduler job) invokes; `app.submit_vendor_compliance_document`/
--    `app.renew_vendor_compliance_document`/`app.decide_vendor_compliance_document`/
--    `app.decide_vendor_compliance_waiver`/`app.revoke_vendor_compliance_waiver` each
--    ALSO call the same private per-family helper directly, as the LAST step of
--    their own already-authorized transaction (part of closing the race the task
--    brief names: "a compliance-status recalculation racing a new document
--    upload" -- the recalculation for that specific family happens INSIDE the same
--    transaction as the upload/decision that changed it). This is the identical
--    "one non-duplicated computation, several authorized entry points" shape
--    PRC-252's own `app._compute_vendor_assessment_score` established (design note
--    3 there) -- disclosed here as the same pattern, one layer up (write, not read).
--    Inline-recalc-at-end-of-transaction alone only protects a mutating RPC's OWN
--    transaction from its own staleness, though -- it does nothing to protect a
--    fully INDEPENDENT `app.recalculate_vendor_compliance_status` call (a UI
--    "Recalculate" button, or a future scheduler entry point) from racing a
--    concurrently-committing document/waiver decision for the same family. Fix-pass
--    addition (HIGH-severity concurrency finding, adversarial review, reproduced
--    live with three concurrent psql sessions): `app._recalculate_vendor_compliance_
--    status_family` itself now takes a per-(vendor, family) `pg_advisory_xact_lock`
--    before any read, fully serializing every concurrent recompute of the same
--    family regardless of which of the several entry points reached it -- see that
--    function's own header for the mechanism.
-- 8. **A real, bounded, callable RECALCULATION rpc, mirroring
--    `app.purge_tracking_telemetry_history`'s own precedent** (ISS-2026-015's own
--    "enforceable and tested, not yet automatically enforced... wiring it is a
--    one-line job enqueue for whichever checkpoint builds the scheduler," quoted in
--    this task's own brief): `app.recalculate_tenant_vendor_compliance_status`
--    sweeps every vendor in a tenant up to a `p_max_vendors` budget (default 200,
--    ceiling 2000) and reports `more_remaining` exactly like `purge_tracking_
--    telemetry_history`'s own `more_remaining` shape, so a caller loops instead of
--    the database stalling on an unbounded tenant. `PRC:Override`-gated (a bulk
--    administrative sweep, not ordinary per-vendor editing) -- it calls the SAME
--    private per-vendor-all-families helper the public per-vendor RPC uses
--    (`app._recalculate_vendor_compliance_status_all_families`), bypassing that
--    RPC's own separate `PRC:Edit` gate rather than re-evaluating it per vendor,
--    since the outer `PRC:Override` check already covers authority for the whole
--    sweep and an actor holding `Override` is not guaranteed by this repository's
--    RBAC model to also hold `Edit`. **No scheduler is added** -- ISS-2026-015 is a
--    standing, accepted, repository-wide gap, not this capability's job to close;
--    both RPCs above are real, tested, and callable today, dormant until a human or
--    a future job invokes them, exactly like `purge_tracking_telemetry_history`.
-- 9. **`app.expire_vendor_compliance_waivers` is a bookkeeping sweep, not a
--    correctness dependency.** `app._recalculate_vendor_compliance_status_family`'s
--    own "does an active waiver cover this family" check evaluates
--    `status = 'approved' and valid_from <= current_date and valid_until >=
--    current_date` directly against the real calendar date -- it does NOT depend on
--    the lazy `expired` status label ever having been swept, so eligibility-hold
--    correctness never silently regresses if nobody has run the sweep recently. The
--    sweep exists only so the `status` COLUMN itself (surfaced to staff in the
--    waiver list/detail screens) reads `expired` rather than a misleadingly-still-
--    `approved` label past its own `valid_until` -- cosmetic/reporting accuracy, not
--    an eligibility-hold input. `PRC:Override`-gated, bounded (`p_max_rows`, default
--    500, ceiling 5000), mirrors `purge_tracking_telemetry_history`'s own bounded
--    shape a second time.
-- 10. **Legal hold interaction is proven by REUSE, not by a new code path**
--     (this task's own explicit instruction: "REUSE this exact function for legal
--     hold, do not build a second one"). A compliance document's own evidence file
--     can be placed under legal hold exactly the way any other file can
--     (`app.set_file_legal_hold`, support/Supreme authority only, unchanged from
--     PLT-128) -- `app.request_file_deletion` already refuses outright while
--     `legal_hold=true`, and this migration adds nothing that could bypass that.
-- 11. **RBAC reuses exactly the 12 already-seeded PRC actions**
--     (View/Create/Edit/Delete/Approve/Reject/Export/Override/Download/Import/View
--     cost/View personal data -- confirmed, per PRC-251/252's own precedent, by
--     reading `permissions_action_check`'s seeded rows directly rather than
--     assuming). No new `app.permissions` row is seeded by this migration. Mapping:
--     `Create` = draft a new requirement, submit a first-time document, request a
--     waiver; `Edit` = draft edit, archive a requirement, renew a document,
--     recalculate one vendor's own status; `Approve`/`Reject` = publish a
--     requirement, verify/reject-or-request-revision of a document (case-mapped by
--     decision, mirroring `app.decide_vendor_assessment_review`), decide a waiver
--     (approve/reject); `Override` = revoke an approved waiver, the bounded
--     waiver-expiry sweep, the bounded tenant-wide status recalculation sweep (all
--     three are administrative/bulk actions, not ordinary per-record editing);
--     `View` = every read RPC; `Download` = `app.access_vendor_compliance_document_
--     evidence` (fix-pass addition -- the genuine fit this action originally lacked
--     until the document/version viewer's own evidence-access call was built; see
--     that function's own header). `View cost`/`View personal data`/`Delete`/
--     `Export`/`Import` still have no distinct fit in this capability's own schema
--     (no financial figure, no PII field beyond actor UUIDs already handled
--     platform-wide, no destructive delete, no export/import surface built this
--     checkpoint) -- left unused here, a disclosed simplification, not a silently
--     invented gap.
-- 12. **Mandatory self-approval block on waiver decisions ONLY** (this task's own
--     explicit instruction: "MUST differ from requested_by -- self-approval
--     blocked, mirror Prompt 252's exact self_approval_not_allowed inline
--     pattern"), reproduced byte-for-byte from `app.decide_vendor_assessment_
--     review`'s own wording/errcode shape in `app.decide_vendor_compliance_waiver`,
--     PLUS a defensive, redundant table-level CHECK
--     (`vendor_compliance_waivers_no_self_approval_check`) so the invariant holds
--     even against a hypothetical future direct-table write path. Document
--     verification (`app.decide_vendor_compliance_document`) carries NO such block
--     -- this task's own spec names self-approval exclusively for waiver decisions
--     (Sec.21's "approved time-bounded waiver"), matching PRC-252's own precedent of
--     scoping maker-checker only where the source text explicitly names it (PRC-252
--     design note 4: assessment review decisions were maker-checker-gated because
--     Sec.21/23 named it; finding/corrective-action decisions were not, for the
--     identical textual-scoping reason applied here to document verification).
-- 13. **TOCTOU row locks on every read-then-conditionally-mutate path racing two
--     different RPCs** (this task's own named risk list, and PRC-252's own
--     adversarial review finding three confirmed races from missing locks):
--     `app.assert_vendor_compliance_requirement_editable` takes a `for update` lock
--     (serializing draft-CRUD against `app.publish_vendor_compliance_requirement`'s
--     own terminal UPDATE, identical to `app.assert_vendor_assessment_template_
--     editable`); `app.publish_vendor_compliance_requirement`'s own superseded-
--     requirement archive UPDATE takes a `for update` lock plus a real
--     `record_version`+status-guarded UPDATE with a `stale_version` not-found
--     re-check (identical to PRC-252's own adversarial-review fix #5, applied
--     proactively here rather than re-discovering it); every document/waiver
--     decision RPC (`decide_vendor_compliance_document`, `decide_vendor_compliance_
--     waiver`, `revoke_vendor_compliance_waiver`, `renew_vendor_compliance_
--     document`) takes a `for update` lock on its own target row before any status
--     transition. "A requirement being published while a document verification is
--     in flight" is closed STRUCTURALLY, not by a lock: `app.vendor_compliance_
--     documents.requirement_version_id` is an immutable snapshot FK (design note 2)
--     -- a published requirement row's own `requires_expiry`/`blocking_effect`/
--     `document_type_code` never change after publish (only its own `status` later
--     flips to `archived`, which cannot retroactively alter a document already
--     linked to it), so a verification reading that row mid-flight cannot observe a
--     torn write -- the identical "applied version never changes" argument PRC-252's
--     own design note 1 already established. "A waiver being decided while the
--     document it covers is being re-verified" and "a compliance-status
--     recalculation racing a new document upload" -- and, the adversarial-review
--     finding that widened this scope, a bystander `app.recalculate_vendor_
--     compliance_status` call racing either of those -- are closed by a real
--     per-(vendor, family) `pg_advisory_xact_lock` inside `app._recalculate_vendor_
--     compliance_status_family` itself (design note 7's own header carries the full
--     mechanism), the same technique/rationale as `app.reconcile_shipment_tracking_
--     health`'s own sibling advisory-lock fix (CG-S10-ATW-024). Reproduced live with
--     three concurrent psql sessions during the adversarial-review fix pass (session
--     B holds the status row via `for update`, session C decides a document and
--     blocks on the advisory lock, session A calls the public recalc RPC and blocks
--     behind C; releasing B lets C commit first with the fresh `verified` read, then
--     A -- now unblocked -- re-reads the ALREADY-COMMITTED fresh state instead of its
--     own stale pre-lock snapshot, so the final persisted row is `verified`, never
--     the reverse-commit-order overwrite the un-locked code produced before this fix).
-- 14. **Idempotency-key replay compares EVERY semantically load-bearing field**, not
--     just one or two (PRC-252's own adversarial-review finding #7, applied
--     proactively here): every idempotency-keyed create RPC in this migration
--     (`create_vendor_compliance_requirement_draft`, `submit_vendor_compliance_
--     document`, `request_vendor_compliance_waiver`) compares the found row's real
--     identity-defining columns against the new call's own values with `is distinct
--     from`, both at the pre-check AND inside the nested `unique_violation`
--     race-recovery handler.
-- 15. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants,
--     the standing per-migration convention since `PLT-118`.

-- ===========================================================================
-- 1. app.vendor_compliance_requirements -- versioned draft/published/archived
--    (design notes 1-3).
-- ===========================================================================

create table app.vendor_compliance_requirements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  requirement_family_id uuid not null default gen_random_uuid(),
  vendor_category text,
  service_type text,
  document_type_code text not null references app.document_types (code),
  name text not null,
  description text,
  blocking_effect text not null default 'blocking',
  requires_expiry boolean not null default true,
  reminder_offsets integer[] not null default array[30, 14, 7],
  status text not null default 'draft',
  supersedes_version_id uuid references app.vendor_compliance_requirements (id),
  effective_from timestamptz not null default now(),
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_compliance_requirements_name_check check (length(trim(name)) > 0),
  constraint vendor_compliance_requirements_blocking_effect_check check (blocking_effect in ('blocking', 'warning')),
  constraint vendor_compliance_requirements_status_check check (status in ('draft', 'published', 'archived')),
  constraint vendor_compliance_requirements_not_self_supersede check (supersedes_version_id is null or supersedes_version_id <> id)
);

comment on table app.vendor_compliance_requirements is
  'PRC-253: a versioned compliance requirement (draft -> published -> archived, mirrors app.vendor_assessment_templates/PRC-252 exactly). requirement_family_id (design note 1) is the identity that survives republish -- app.vendor_compliance_status keys on it, never on a single version id. reminder_offsets positivity is validated at the RPC layer only (a table CHECK cannot contain a subquery/unnest in Postgres) -- disclosed, not an oversight.';

create unique index vendor_compliance_requirements_published_family_unique on app.vendor_compliance_requirements (requirement_family_id) where status = 'published';
create unique index vendor_compliance_requirements_published_scope_unique on app.vendor_compliance_requirements (tenant_id, coalesce(vendor_category, ''), coalesce(service_type, ''), document_type_code) where status = 'published';
create index vendor_compliance_requirements_tenant_scope_idx on app.vendor_compliance_requirements (tenant_id, vendor_category, service_type, status);
create index vendor_compliance_requirements_family_idx on app.vendor_compliance_requirements (requirement_family_id);
create unique index vendor_compliance_requirements_idempotency_key_unique on app.vendor_compliance_requirements (tenant_id, idempotency_key) where idempotency_key is not null;

-- ===========================================================================
-- 2. app.vendor_compliance_documents -- one row per submitted evidence version
--    (design notes 2, 4, 5).
-- ===========================================================================

create table app.vendor_compliance_documents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_record_id uuid not null references app.vendor_profiles (master_record_id),
  requirement_version_id uuid not null references app.vendor_compliance_requirements (id),
  file_id uuid not null references app.files (id),
  version_group_id uuid not null default gen_random_uuid(),
  version_number integer not null default 1,
  is_latest_version boolean not null default true,
  issue_date date,
  expiry_date date,
  verification_status text not null default 'pending',
  verified_by text,
  verified_by_auth_user_id uuid,
  verified_at timestamptz,
  rejection_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_compliance_documents_verification_status_check check (verification_status in ('pending', 'verified', 'rejected', 'revision_requested')),
  constraint vendor_compliance_documents_version_number_check check (version_number > 0),
  constraint vendor_compliance_documents_expiry_order_check check (issue_date is null or expiry_date is null or expiry_date >= issue_date),
  constraint vendor_compliance_documents_decision_shape_check check (
    (verification_status = 'pending' and verified_by is null and verified_by_auth_user_id is null and verified_at is null) or
    (verification_status <> 'pending' and verified_by is not null and verified_by_auth_user_id is not null and verified_at is not null)
  ),
  constraint vendor_compliance_documents_rejection_reason_check check (
    (verification_status in ('rejected', 'revision_requested') and rejection_reason is not null and length(trim(rejection_reason)) > 0) or
    (verification_status not in ('rejected', 'revision_requested'))
  )
);

comment on table app.vendor_compliance_documents is
  'PRC-253: one row per submitted evidence version. requirement_version_id is the RPD-040-style immutable applied-version snapshot (design note 2) -- never re-resolved on requirement republish. file_id references app.files (PLT-128) directly, re-validated (tenant/record-scope/malware_scan_status=clean) by every RPC that accepts one as a parameter, never trusted as a bare FK (design note 5). version_group_id/version_number/is_latest_version mirror app.files'' own versioning shape one layer up -- app.renew_vendor_compliance_document never overwrites (design note 4).';

create unique index vendor_compliance_documents_one_latest_version_idx on app.vendor_compliance_documents (version_group_id) where is_latest_version;
create unique index vendor_compliance_documents_one_active_slot_idx on app.vendor_compliance_documents (requirement_version_id, vendor_master_record_id) where is_latest_version;
create index vendor_compliance_documents_vendor_requirement_idx on app.vendor_compliance_documents (vendor_master_record_id, requirement_version_id);
create index vendor_compliance_documents_expiry_idx on app.vendor_compliance_documents (expiry_date) where is_latest_version and verification_status = 'verified';
create unique index vendor_compliance_documents_idempotency_key_unique on app.vendor_compliance_documents (tenant_id, idempotency_key) where idempotency_key is not null;

-- ===========================================================================
-- 3. app.vendor_compliance_waivers -- time-bounded, approved, self-approval-
--    blocked (design note 12).
-- ===========================================================================

create table app.vendor_compliance_waivers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  requirement_version_id uuid not null references app.vendor_compliance_requirements (id),
  vendor_master_record_id uuid not null references app.vendor_profiles (master_record_id),
  reason text not null,
  valid_from date not null,
  valid_until date not null,
  requested_by text,
  requested_by_auth_user_id uuid not null,
  approved_by text,
  approved_by_auth_user_id uuid,
  decision_reason text,
  status text not null default 'pending',
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_compliance_waivers_reason_check check (length(trim(reason)) > 0),
  constraint vendor_compliance_waivers_status_check check (status in ('pending', 'approved', 'rejected', 'expired', 'revoked')),
  constraint vendor_compliance_waivers_valid_range_check check (valid_until >= valid_from),
  constraint vendor_compliance_waivers_approval_shape_check check (
    (status = 'approved' and approved_by is not null and approved_by_auth_user_id is not null) or (status <> 'approved')
  ),
  -- Defense in depth alongside the RPC-level block (design note 12) -- holds even
  -- against a hypothetical future direct-table write path.
  constraint vendor_compliance_waivers_no_self_approval_check check (approved_by_auth_user_id is null or approved_by_auth_user_id <> requested_by_auth_user_id)
);

comment on table app.vendor_compliance_waivers is
  'PRC-253: a time-bounded (valid_from/valid_until), approved, self-approval-blocked exception to a compliance requirement (Sec.21/24). app._recalculate_vendor_compliance_status_family treats a waiver as ACTIVE by direct calendar-date check (status=approved and valid_from<=current_date<=valid_until), never by the lazily-swept expired label alone (design note 9).';

create index vendor_compliance_waivers_vendor_requirement_idx on app.vendor_compliance_waivers (vendor_master_record_id, requirement_version_id);
create index vendor_compliance_waivers_tenant_status_idx on app.vendor_compliance_waivers (tenant_id, status);
create unique index vendor_compliance_waivers_idempotency_key_unique on app.vendor_compliance_waivers (tenant_id, idempotency_key) where idempotency_key is not null;

-- ===========================================================================
-- 4. app.vendor_compliance_status -- the single written-once-per-recalculation
--    eligibility projection, keyed by FAMILY (design notes 1, 2, 7).
-- ===========================================================================

create table app.vendor_compliance_status (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_record_id uuid not null references app.vendor_profiles (master_record_id),
  requirement_family_id uuid not null,
  current_requirement_version_id uuid references app.vendor_compliance_requirements (id),
  current_document_id uuid references app.vendor_compliance_documents (id),
  status text not null default 'not_submitted',
  eligibility_hold boolean not null default false,
  computed_at timestamptz not null default now(),
  computed_by text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_compliance_status_status_check check (status in ('not_submitted', 'pending_verification', 'verified', 'expiring_soon', 'expired', 'waived', 'rejected')),
  constraint vendor_compliance_status_unique unique (vendor_master_record_id, requirement_family_id)
);

comment on table app.vendor_compliance_status is
  'PRC-253: one row per (vendor, requirement FAMILY) -- survives a requirement republish (design note 1), unlike app.vendor_compliance_documents'' own per-version snapshot link. Written ONLY by app._recalculate_vendor_compliance_status_family (design note 7), reached via app.recalculate_vendor_compliance_status / app.recalculate_tenant_vendor_compliance_status or inline from the last step of every document/waiver-mutating RPC. eligibility_hold is true only when blocking_effect=''blocking'' AND status in (expired,rejected,not_submitted) AND no active waiver covers it -- never for expiring_soon/pending_verification/verified/waived.';

create index vendor_compliance_status_tenant_hold_idx on app.vendor_compliance_status (tenant_id, eligibility_hold);
create index vendor_compliance_status_tenant_status_idx on app.vendor_compliance_status (tenant_id, status);

-- ===========================================================================
-- 5. Private helpers (design notes 1, 7, 13). No grant to authenticated/
--    service_role -- callable only from within another SECURITY DEFINER function
--    owned by the same role, the identical shape app._compute_vendor_assessment_
--    score/app.assert_vendor_assessment_template_editable already established.
-- ===========================================================================

create function app._vendor_compliance_requirement_applies(p_vendor app.vendor_profiles, p_requirement app.vendor_compliance_requirements)
returns boolean
language sql
stable
as $$
  select
    p_vendor.tenant_id = p_requirement.tenant_id
    and (p_requirement.vendor_category is null or p_requirement.vendor_category = p_vendor.vendor_category)
    and (
      p_requirement.service_type is null
      or exists (
        select 1 from app.vendor_services vs
        where vs.master_record_id = p_vendor.master_record_id and vs.service_type = p_requirement.service_type and vs.status = 'active'
      )
    );
$$;

comment on function app._vendor_compliance_requirement_applies is 'PRC-253: does a published requirement apply to a given vendor -- vendor_category is a nullable wildcard matched against app.vendor_profiles.vendor_category directly; service_type is a nullable wildcard matched against the vendor''s own ACTIVE app.vendor_services rows (a vendor may offer several services, so this is an existence check, not a single-column match).';

create function app.assert_vendor_compliance_requirement_editable(p_requirement_version_id uuid, p_actor_auth_user_id uuid, out v_requirement app.vendor_compliance_requirements)
language plpgsql
as $$
declare
  v_decision app.rbac_decision;
begin
  -- `for update` (design note 13): serializes draft-CRUD against
  -- app.publish_vendor_compliance_requirement's own terminal UPDATE on the same row.
  select * into v_requirement from app.vendor_compliance_requirements where id = p_requirement_version_id for update;
  if not found then
    raise exception 'vendor_compliance_requirement_not_found: %', p_requirement_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_requirement.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_requirement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_requirement.status <> 'draft' then
    raise exception 'vendor_compliance_requirement_not_draft: requirement version % is % -- it may only be edited while draft', p_requirement_version_id, v_requirement.status
      using errcode = 'check_violation';
  end if;
end;
$$;

comment on function app.assert_vendor_compliance_requirement_editable is 'PRC-253: shared authority+state precondition for requirement draft mutation -- PRC:Edit plus status=draft, under a `for update` row lock (design note 13).';

-- The SINGLE writer of app.vendor_compliance_status (design note 7). No permission
-- check -- callable only from within an already-authorized caller's own transaction.
-- Atomic `insert ... on conflict do update` -- no separate lock/read-then-write race
-- window on the status row itself.
--
-- Fix-pass addition (HIGH-severity concurrency finding, adversarial review): the
-- `insert ... on conflict do update` at the end of this function is atomic against
-- itself, but the several independent SELECTs feeding it (current published
-- requirement, latest active document, active-waiver check) are NOT locked against a
-- second, fully independent invocation of this same helper for the same (vendor,
-- family) -- e.g. one reached inline from app.decide_vendor_compliance_document's own
-- transaction racing a bystander app.recalculate_vendor_compliance_status call. Two
-- concurrent invocations can commit in the reverse of their own read order: whichever
-- commits LAST wins the upsert regardless of which read a fresher snapshot, silently
-- persisting a stale status/eligibility_hold with no error (record_version still
-- increments). Reproduced live with three concurrent psql sessions. Closed the
-- identical way `app.reconcile_shipment_tracking_health`'s own sibling race was
-- closed (CG-S10-ATW-024) -- a per-(vendor, family) session-transaction advisory
-- lock taken BEFORE any read, fully serializing every concurrent recompute of the
-- same family so the second invocation's own reads only begin once the first has
-- committed (or rolled back).
create function app._recalculate_vendor_compliance_status_family(p_vendor_master_record_id uuid, p_requirement_family_id uuid, p_actor_label text)
returns app.vendor_compliance_status
language plpgsql
as $$
declare
  v_current_requirement app.vendor_compliance_requirements;
  v_document app.vendor_compliance_documents;
  v_has_active_waiver boolean;
  v_status text;
  v_hold boolean;
  v_row app.vendor_compliance_status;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_vendor_master_record_id::text || ':' || p_requirement_family_id::text, 0));

  select * into v_current_requirement
  from app.vendor_compliance_requirements
  where requirement_family_id = p_requirement_family_id and status = 'published';

  if v_current_requirement.id is null then
    -- No currently published requirement for this family (fully archived, never
    -- republished) -- nothing left to hold the vendor to. Remove any stale status
    -- row rather than leave a phantom hold in place.
    delete from app.vendor_compliance_status where vendor_master_record_id = p_vendor_master_record_id and requirement_family_id = p_requirement_family_id;
    return null;
  end if;

  -- The vendor's own most-recently-submitted ACTIVE evidence anywhere in the
  -- family's lineage (design note 2) -- a document's own snapshot link to the
  -- version it was submitted against never changes on republish, but the family's
  -- current status legitimately re-evaluates that same, unmodified evidence
  -- against whichever requirement version is published now.
  select d.* into v_document
  from app.vendor_compliance_documents d
  join app.vendor_compliance_requirements r on r.id = d.requirement_version_id
  where d.vendor_master_record_id = p_vendor_master_record_id and r.requirement_family_id = p_requirement_family_id and d.is_latest_version
  order by d.created_at desc
  limit 1;

  select exists (
    select 1
    from app.vendor_compliance_waivers w
    join app.vendor_compliance_requirements r on r.id = w.requirement_version_id
    where w.vendor_master_record_id = p_vendor_master_record_id and r.requirement_family_id = p_requirement_family_id
      and w.status = 'approved' and w.valid_from <= current_date and w.valid_until >= current_date
  ) into v_has_active_waiver;

  if v_has_active_waiver then
    v_status := 'waived';
  elsif v_document.id is null then
    v_status := 'not_submitted';
  elsif v_document.verification_status = 'pending' then
    v_status := 'pending_verification';
  elsif v_document.verification_status in ('rejected', 'revision_requested') then
    v_status := 'rejected';
  elsif v_document.verification_status = 'verified' then
    if not v_current_requirement.requires_expiry or v_document.expiry_date is null then
      v_status := 'verified';
    elsif v_document.expiry_date < current_date then
      v_status := 'expired';
    elsif v_document.expiry_date <= current_date + make_interval(days => coalesce((select max(o) from unnest(v_current_requirement.reminder_offsets) o), 0)) then
      v_status := 'expiring_soon';
    else
      v_status := 'verified';
    end if;
  else
    v_status := 'not_submitted';
  end if;

  v_hold := v_current_requirement.blocking_effect = 'blocking' and v_status in ('expired', 'rejected', 'not_submitted') and not v_has_active_waiver;

  insert into app.vendor_compliance_status (
    tenant_id, vendor_master_record_id, requirement_family_id, current_requirement_version_id, current_document_id,
    status, eligibility_hold, computed_at, computed_by
  ) values (
    v_current_requirement.tenant_id, p_vendor_master_record_id, p_requirement_family_id, v_current_requirement.id, v_document.id,
    v_status, v_hold, now(), p_actor_label
  )
  on conflict (vendor_master_record_id, requirement_family_id) do update
  set current_requirement_version_id = excluded.current_requirement_version_id,
      current_document_id = excluded.current_document_id,
      status = excluded.status,
      eligibility_hold = excluded.eligibility_hold,
      computed_at = excluded.computed_at,
      computed_by = excluded.computed_by,
      record_version = app.vendor_compliance_status.record_version + 1,
      updated_at = now()
  returning * into v_row;

  return v_row;
end;
$$;

comment on function app._recalculate_vendor_compliance_status_family is 'PRC-253: the single, non-duplicated write path for app.vendor_compliance_status (design note 7) -- one family, atomic upsert. Called by the last step of every document/waiver-mutating RPC (closing the "recalculation racing a new upload" race, design note 13) and looped by app._recalculate_vendor_compliance_status_all_families.';

create function app._recalculate_vendor_compliance_status_all_families(p_vendor_master_record_id uuid, p_actor_label text)
returns setof app.vendor_compliance_status
language plpgsql
as $$
declare
  v_vendor app.vendor_profiles;
  v_family record;
  v_row app.vendor_compliance_status;
begin
  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_record_id;
  if not found then
    return;
  end if;

  -- Every family that EITHER currently applies to this vendor by scope OR already
  -- has a status row (so a requirement that no longer applies -- e.g. the vendor's
  -- own category changed -- still gets its stale hold cleared, not left dangling).
  for v_family in
    select distinct r.requirement_family_id
    from app.vendor_compliance_requirements r
    where r.tenant_id = v_vendor.tenant_id and r.status = 'published' and app._vendor_compliance_requirement_applies(v_vendor, r)
    union
    select s.requirement_family_id from app.vendor_compliance_status s where s.vendor_master_record_id = p_vendor_master_record_id
  loop
    v_row := app._recalculate_vendor_compliance_status_family(p_vendor_master_record_id, v_family.requirement_family_id, p_actor_label);
    if v_row.id is not null then
      return next v_row;
    end if;
  end loop;

  return;
end;
$$;

comment on function app._recalculate_vendor_compliance_status_all_families is 'PRC-253: loops every applicable-or-previously-tracked family for one vendor, calling app._recalculate_vendor_compliance_status_family for each. Used by both app.recalculate_vendor_compliance_status (per-vendor, PRC:Edit-gated) and app.recalculate_tenant_vendor_compliance_status (bounded sweep, PRC:Override-gated) so the two public entry points never duplicate the resolution logic (design note 8).';

-- ===========================================================================
-- 6. Requirement lifecycle RPCs.
-- ===========================================================================

create function app.create_vendor_compliance_requirement_draft(
  p_tenant_id uuid,
  p_vendor_category text,
  p_service_type text,
  p_document_type_code text,
  p_name text,
  p_description text,
  p_blocking_effect text,
  p_requires_expiry boolean,
  p_reminder_offsets integer[],
  p_effective_from timestamptz,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_compliance_requirements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.vendor_compliance_requirements;
  v_offset integer;
  v_requirement app.vendor_compliance_requirements;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name must not be empty' using errcode = 'check_violation';
  end if;
  if coalesce(p_blocking_effect, 'blocking') not in ('blocking', 'warning') then
    raise exception 'invalid_blocking_effect: % is not blocking or warning', p_blocking_effect using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.document_types where code = p_document_type_code) then
    raise exception 'document_type_not_registered: % is not a registered document type', p_document_type_code using errcode = 'check_violation';
  end if;
  if p_reminder_offsets is not null then
    foreach v_offset in array p_reminder_offsets loop
      if v_offset <= 0 then
        raise exception 'invalid_reminder_offset: reminder offsets must be positive, got %', v_offset using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_compliance_requirements where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      -- Fix-pass addition (MEDIUM-severity finding, adversarial review): reminder_offsets
      -- (drives the expiring_soon threshold) and effective_from were missing from this
      -- comparison. reminder_offsets has a deterministic default (array[30,14,7]),
      -- compared the identical coalesce-then-compare way blocking_effect/requires_expiry
      -- already are. effective_from's own default is `now()` -- non-deterministic across
      -- two separate calls -- so it is only compared when the REPLAY call explicitly
      -- supplies a value: two replays that both omit it (both intending "use the
      -- default") are never treated as a spurious mismatch, but a replay that explicitly
      -- names a different effective_from than what was actually stored is still rejected.
      if v_existing.name is distinct from p_name or v_existing.vendor_category is distinct from p_vendor_category
        or v_existing.service_type is distinct from p_service_type or v_existing.document_type_code is distinct from p_document_type_code
        or v_existing.blocking_effect is distinct from coalesce(p_blocking_effect, 'blocking') or v_existing.requires_expiry is distinct from coalesce(p_requires_expiry, true)
        or v_existing.reminder_offsets is distinct from coalesce(p_reminder_offsets, array[30, 14, 7])
        or (p_effective_from is not null and v_existing.effective_from is distinct from p_effective_from)
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different compliance requirement (name %)', p_idempotency_key, v_existing.name
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_compliance_requirements (
      tenant_id, vendor_category, service_type, document_type_code, name, description,
      blocking_effect, requires_expiry, reminder_offsets, effective_from, idempotency_key, created_by
    ) values (
      p_tenant_id, p_vendor_category, p_service_type, p_document_type_code, p_name, p_description,
      coalesce(p_blocking_effect, 'blocking'), coalesce(p_requires_expiry, true), coalesce(p_reminder_offsets, array[30, 14, 7]), coalesce(p_effective_from, now()), p_idempotency_key, p_actor_label
    )
    returning * into v_requirement;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_compliance_requirements where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      -- Fix-pass addition (MEDIUM-severity finding, adversarial review): reminder_offsets
      -- (drives the expiring_soon threshold) and effective_from were missing from this
      -- comparison. reminder_offsets has a deterministic default (array[30,14,7]),
      -- compared the identical coalesce-then-compare way blocking_effect/requires_expiry
      -- already are. effective_from's own default is `now()` -- non-deterministic across
      -- two separate calls -- so it is only compared when the REPLAY call explicitly
      -- supplies a value: two replays that both omit it (both intending "use the
      -- default") are never treated as a spurious mismatch, but a replay that explicitly
      -- names a different effective_from than what was actually stored is still rejected.
      if v_existing.name is distinct from p_name or v_existing.vendor_category is distinct from p_vendor_category
        or v_existing.service_type is distinct from p_service_type or v_existing.document_type_code is distinct from p_document_type_code
        or v_existing.blocking_effect is distinct from coalesce(p_blocking_effect, 'blocking') or v_existing.requires_expiry is distinct from coalesce(p_requires_expiry, true)
        or v_existing.reminder_offsets is distinct from coalesce(p_reminder_offsets, array[30, 14, 7])
        or (p_effective_from is not null and v_existing.effective_from is distinct from p_effective_from)
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different compliance requirement (name %)', p_idempotency_key, v_existing.name
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_compliance_requirement_draft',
    'app.vendor_compliance_requirements', v_requirement.id, 'success', null, null, to_jsonb(v_requirement)
  );

  return v_requirement;
end;
$$;

create function app.update_vendor_compliance_requirement_draft(
  p_requirement_version_id uuid,
  p_expected_version integer,
  p_vendor_category text,
  p_service_type text,
  p_document_type_code text,
  p_name text,
  p_description text,
  p_blocking_effect text,
  p_requires_expiry boolean,
  p_reminder_offsets integer[],
  p_effective_from timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_compliance_requirements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_requirement app.vendor_compliance_requirements;
  v_offset integer;
begin
  v_requirement := app.assert_vendor_compliance_requirement_editable(p_requirement_version_id, p_actor_auth_user_id);

  if v_requirement.record_version <> p_expected_version then
    raise exception 'stale_version: vendor compliance requirement % expected version % but found %', p_requirement_version_id, p_expected_version, v_requirement.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name must not be empty' using errcode = 'check_violation';
  end if;
  if coalesce(p_blocking_effect, 'blocking') not in ('blocking', 'warning') then
    raise exception 'invalid_blocking_effect: % is not blocking or warning', p_blocking_effect using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.document_types where code = p_document_type_code) then
    raise exception 'document_type_not_registered: % is not a registered document type', p_document_type_code using errcode = 'check_violation';
  end if;
  if p_reminder_offsets is not null then
    foreach v_offset in array p_reminder_offsets loop
      if v_offset <= 0 then
        raise exception 'invalid_reminder_offset: reminder offsets must be positive, got %', v_offset using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  update app.vendor_compliance_requirements
  set vendor_category = p_vendor_category, service_type = p_service_type, document_type_code = p_document_type_code,
      name = p_name, description = p_description, blocking_effect = coalesce(p_blocking_effect, 'blocking'),
      requires_expiry = coalesce(p_requires_expiry, true), reminder_offsets = coalesce(p_reminder_offsets, array[30, 14, 7]),
      effective_from = coalesce(p_effective_from, effective_from), updated_at = now(), record_version = record_version + 1
  where id = p_requirement_version_id and record_version = p_expected_version
  returning * into v_requirement;
  if not found then
    raise exception 'stale_version: vendor compliance requirement % target row was concurrently modified (expected version %)', p_requirement_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_requirement.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_compliance_requirement_draft',
    'app.vendor_compliance_requirements', v_requirement.id, 'success', null, null, to_jsonb(v_requirement)
  );

  return v_requirement;
end;
$$;

create function app.publish_vendor_compliance_requirement(
  p_requirement_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_compliance_requirements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_requirement app.vendor_compliance_requirements;
  v_superseded app.vendor_compliance_requirements;
  v_family_id uuid;
begin
  select * into v_requirement from app.vendor_compliance_requirements where id = p_requirement_version_id for update;
  if not found then
    raise exception 'vendor_compliance_requirement_not_found: %', p_requirement_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_requirement.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_requirement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_requirement.record_version <> p_expected_version then
    raise exception 'stale_version: vendor compliance requirement % expected version % but found %', p_requirement_version_id, p_expected_version, v_requirement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_requirement.status <> 'draft' then
    raise exception 'invalid_transition: vendor compliance requirement % is % and cannot be published', p_requirement_version_id, v_requirement.status
      using errcode = 'check_violation';
  end if;

  v_family_id := v_requirement.requirement_family_id;

  if p_supersedes_version_id is not null then
    -- `for update` (design note 13, mirrors PRC-252's own adversarial-review fix):
    -- closes the same TOCTOU class where a concurrent, independent archive call on
    -- the SAME superseded row could commit between this read and the terminal
    -- UPDATE below.
    select * into v_superseded from app.vendor_compliance_requirements where id = p_supersedes_version_id for update;
    if not found then
      raise exception 'superseded_requirement_not_found: %', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.tenant_id <> v_requirement.tenant_id
      or coalesce(v_superseded.vendor_category, '') <> coalesce(v_requirement.vendor_category, '')
      or coalesce(v_superseded.service_type, '') <> coalesce(v_requirement.service_type, '')
      or v_superseded.document_type_code <> v_requirement.document_type_code
    then
      raise exception 'invalid_supersede: superseded requirement must share the same tenant/vendor_category/service_type/document_type_code' using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded requirement % is % (must be published)', p_supersedes_version_id, v_superseded.status using errcode = 'check_violation';
    end if;

    v_family_id := v_superseded.requirement_family_id;

    update app.vendor_compliance_requirements
    set status = 'archived', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_version_id and record_version = v_superseded.record_version and status = 'published';
    if not found then
      raise exception 'stale_version: superseded vendor compliance requirement % was concurrently modified (expected version %)', p_supersedes_version_id, v_superseded.record_version
        using errcode = 'serialization_failure';
    end if;
  end if;

  begin
    update app.vendor_compliance_requirements
    set status = 'published', supersedes_version_id = p_supersedes_version_id, requirement_family_id = v_family_id, updated_at = now(), record_version = record_version + 1
    where id = p_requirement_version_id and record_version = p_expected_version
    returning * into v_requirement;
  exception
    when unique_violation then
      raise exception 'active_requirement_exists: a published compliance requirement already exists for tenant %, scope %/%/% -- supply p_supersedes_version_id to replace it', v_requirement.tenant_id, v_requirement.vendor_category, v_requirement.service_type, v_requirement.document_type_code
        using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: vendor compliance requirement % target row was concurrently modified (expected version %)', p_requirement_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_requirement.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_vendor_compliance_requirement',
    'app.vendor_compliance_requirements', v_requirement.id, 'success', null, null, jsonb_build_object('supersedes_version_id', p_supersedes_version_id, 'requirement_family_id', v_family_id)
  );

  return v_requirement;
end;
$$;

comment on function app.publish_vendor_compliance_requirement is 'PRC-253: PRC:Approve-gated. When p_supersedes_version_id is supplied, archives the prior published version FIRST (record_version+status-guarded, design note 13) and carries its requirement_family_id forward onto the new row (design note 1) -- the moment a draft becomes a genuine continuation of an existing family, not before.';

create function app.archive_vendor_compliance_requirement(p_requirement_version_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_compliance_requirements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_requirement app.vendor_compliance_requirements;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to archive a vendor compliance requirement' using errcode = 'check_violation';
  end if;

  select * into v_requirement from app.vendor_compliance_requirements where id = p_requirement_version_id;
  if not found then
    raise exception 'vendor_compliance_requirement_not_found: %', p_requirement_version_id using errcode = 'no_data_found';
  end if;
  if v_requirement.record_version <> p_expected_version then
    raise exception 'stale_version: vendor compliance requirement % expected version % but found %', p_requirement_version_id, p_expected_version, v_requirement.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_requirement.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_requirement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_requirement.status <> 'published' then
    raise exception 'invalid_transition: vendor compliance requirement % is % and cannot be archived', p_requirement_version_id, v_requirement.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_compliance_requirements
  set status = 'archived', updated_at = now(), record_version = record_version + 1
  where id = p_requirement_version_id and record_version = p_expected_version
  returning * into v_requirement;
  if not found then
    raise exception 'stale_version: vendor compliance requirement % target row was concurrently modified (expected version %)', p_requirement_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_requirement.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_vendor_compliance_requirement',
    'app.vendor_compliance_requirements', v_requirement.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_requirement;
end;
$$;

comment on function app.archive_vendor_compliance_requirement is 'PRC-253: archives a published requirement with no replacement (mandatory reason). Deliberately does NOT sweep every affected vendor''s own app.vendor_compliance_status row -- a stale hold clears on the next real recalculation (app.recalculate_tenant_vendor_compliance_status is the operator tool for exactly this), matching design note 8''s own "not yet automatically enforced" precedent.';

-- ===========================================================================
-- 7. Document lifecycle RPCs (design notes 4, 5).
-- ===========================================================================

create function app.submit_vendor_compliance_document(
  p_vendor_master_record_id uuid,
  p_requirement_version_id uuid,
  p_file_id uuid,
  p_issue_date date,
  p_expiry_date date,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_compliance_documents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_requirement app.vendor_compliance_requirements;
  v_file app.files;
  v_existing app.vendor_compliance_documents;
  v_constraint_name text;
  v_document app.vendor_compliance_documents;
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

  select * into v_requirement from app.vendor_compliance_requirements where id = p_requirement_version_id and tenant_id = v_vendor.tenant_id;
  if not found or v_requirement.status <> 'published' then
    raise exception 'requirement_not_published: vendor compliance requirement % is not a published requirement for tenant %', p_requirement_version_id, v_vendor.tenant_id
      using errcode = 'check_violation';
  end if;
  if not app._vendor_compliance_requirement_applies(v_vendor, v_requirement) then
    raise exception 'requirement_not_applicable: requirement % does not apply to vendor % (category/service scope mismatch)', p_requirement_version_id, p_vendor_master_record_id
      using errcode = 'check_violation';
  end if;

  if p_expiry_date is not null and p_issue_date is not null and p_expiry_date < p_issue_date then
    raise exception 'inconsistent_issue_expiry_date: expiry_date % is before issue_date %', p_expiry_date, p_issue_date using errcode = 'check_violation';
  end if;
  if v_requirement.requires_expiry and p_expiry_date is null then
    raise exception 'expiry_date_required: requirement % requires an expiry date', p_requirement_version_id using errcode = 'check_violation';
  end if;
  if not v_requirement.requires_expiry and p_expiry_date is not null then
    raise exception 'expiry_date_not_applicable: requirement % does not track expiry -- omit expiry_date', p_requirement_version_id using errcode = 'check_violation';
  end if;

  -- Evidence re-validation (design note 5, mandatory pattern): re-fetch and reject
  -- on tenant mismatch, wrong record scope, or a non-clean malware scan. record_type
  -- ='vendor_compliance', record_id=the vendor's own master_record_id -- the file
  -- was uploaded "for this vendor's compliance purpose" (this task's own Sec.16/24
  -- wording for a pre-existing-upload link).
  select * into v_file from app.files where id = p_file_id;
  if not found then
    raise exception 'evidence_file_not_found: %', p_file_id using errcode = 'no_data_found';
  end if;
  if v_file.tenant_id <> v_vendor.tenant_id or v_file.record_type <> 'vendor_compliance' or v_file.record_id <> p_vendor_master_record_id then
    raise exception 'compliance_evidence_file_mismatch: file % was not uploaded for vendor %''s own compliance purpose in tenant %', p_file_id, p_vendor_master_record_id, v_vendor.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_file.malware_scan_status <> 'clean' then
    raise exception 'compliance_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be submitted', p_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_compliance_documents where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      -- Fix-pass addition (HIGH-severity finding, adversarial review): issue_date/
      -- expiry_date were missing from this comparison -- expiry_date is the single
      -- most consequential field in this entire capability (the sole input that
      -- flips verified/expiring_soon/expired, which in turn drives eligibility_hold),
      -- so a replay silently carrying a corrected date must be rejected, not
      -- silently ignored, exactly like every other identity-defining column here.
      if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.requirement_version_id is distinct from p_requirement_version_id
        or v_existing.file_id is distinct from p_file_id or v_existing.issue_date is distinct from p_issue_date or v_existing.expiry_date is distinct from p_expiry_date
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different compliance document submission', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_compliance_documents (
      tenant_id, vendor_master_record_id, requirement_version_id, file_id, issue_date, expiry_date, idempotency_key, created_by
    ) values (
      v_vendor.tenant_id, p_vendor_master_record_id, p_requirement_version_id, p_file_id, p_issue_date, p_expiry_date, p_idempotency_key, p_actor_label
    )
    returning * into v_document;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_compliance_documents_idempotency_key_unique' and p_idempotency_key is not null then
        select * into v_existing from app.vendor_compliance_documents where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
        if not found then
          raise;
        end if;
        if v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id or v_existing.requirement_version_id is distinct from p_requirement_version_id
          or v_existing.file_id is distinct from p_file_id or v_existing.issue_date is distinct from p_issue_date or v_existing.expiry_date is distinct from p_expiry_date
        then
          raise exception 'idempotency_key_conflict: idempotency key % was already used for a different compliance document submission', p_idempotency_key
            using errcode = 'unique_violation';
        end if;
        return v_existing;
      elsif v_constraint_name = 'vendor_compliance_documents_one_active_slot_idx' then
        raise exception 'active_submission_exists: vendor % already has an active submission for requirement % -- use renew instead', p_vendor_master_record_id, p_requirement_version_id
          using errcode = 'check_violation';
      else
        raise;
      end if;
  end;

  perform app._recalculate_vendor_compliance_status_family(p_vendor_master_record_id, v_requirement.requirement_family_id, p_actor_label);

  perform app.capture_audit_event(
    v_vendor.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_vendor_compliance_document',
    'app.vendor_compliance_documents', v_document.id, 'success', null, null, to_jsonb(v_document)
  );

  return v_document;
end;
$$;

create function app.renew_vendor_compliance_document(
  p_previous_document_id uuid,
  p_file_id uuid,
  p_issue_date date,
  p_expiry_date date,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_compliance_documents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_prev app.vendor_compliance_documents;
  v_requirement app.vendor_compliance_requirements;
  v_file app.files;
  v_new app.vendor_compliance_documents;
begin
  select * into v_prev from app.vendor_compliance_documents where id = p_previous_document_id for update;
  if not found then
    raise exception 'vendor_compliance_document_not_found: %', p_previous_document_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_prev.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_prev.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not v_prev.is_latest_version then
    raise exception 'vendor_compliance_document_not_latest: document % is not the latest version of its lineage, renewal must start from the latest', p_previous_document_id
      using errcode = 'check_violation';
  end if;

  select * into v_requirement from app.vendor_compliance_requirements where id = v_prev.requirement_version_id;

  if p_expiry_date is not null and p_issue_date is not null and p_expiry_date < p_issue_date then
    raise exception 'inconsistent_issue_expiry_date: expiry_date % is before issue_date %', p_expiry_date, p_issue_date using errcode = 'check_violation';
  end if;
  if v_requirement.requires_expiry and p_expiry_date is null then
    raise exception 'expiry_date_required: requirement % requires an expiry date', v_prev.requirement_version_id using errcode = 'check_violation';
  end if;
  if not v_requirement.requires_expiry and p_expiry_date is not null then
    raise exception 'expiry_date_not_applicable: requirement % does not track expiry -- omit expiry_date', v_prev.requirement_version_id using errcode = 'check_violation';
  end if;

  select * into v_file from app.files where id = p_file_id;
  if not found then
    raise exception 'evidence_file_not_found: %', p_file_id using errcode = 'no_data_found';
  end if;
  if v_file.tenant_id <> v_prev.tenant_id or v_file.record_type <> 'vendor_compliance' or v_file.record_id <> v_prev.vendor_master_record_id then
    raise exception 'compliance_evidence_file_mismatch: file % was not uploaded for vendor %''s own compliance purpose in tenant %', p_file_id, v_prev.vendor_master_record_id, v_prev.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_file.malware_scan_status <> 'clean' then
    raise exception 'compliance_unsafe_evidence: evidence file % has scan status % -- only clean evidence may be submitted', p_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_compliance_documents
  set is_latest_version = false
  where id = v_prev.id;

  insert into app.vendor_compliance_documents (
    tenant_id, vendor_master_record_id, requirement_version_id, file_id, version_group_id, version_number, is_latest_version,
    issue_date, expiry_date, created_by
  ) values (
    v_prev.tenant_id, v_prev.vendor_master_record_id, v_prev.requirement_version_id, p_file_id, v_prev.version_group_id, v_prev.version_number + 1, true,
    p_issue_date, p_expiry_date, p_actor_label
  )
  returning * into v_new;

  perform app._recalculate_vendor_compliance_status_family(v_prev.vendor_master_record_id, v_requirement.requirement_family_id, p_actor_label);

  perform app.capture_audit_event(
    v_prev.tenant_id, p_actor_auth_user_id, p_actor_label, 'renew_vendor_compliance_document',
    'app.vendor_compliance_documents', v_new.id, 'success', null, to_jsonb(v_prev), to_jsonb(v_new)
  );

  return v_new;
end;
$$;

comment on function app.renew_vendor_compliance_document is 'PRC-253: mirrors app.create_file_version''s exact shape one layer up (design note 4) -- flips the prior row''s is_latest_version to false FIRST, then inserts a new row sharing version_group_id, never deleting the prior evidence. Evidence file re-validated identically to app.submit_vendor_compliance_document (design note 5).';

create function app.decide_vendor_compliance_document(
  p_document_id uuid, p_expected_version integer, p_decision text, p_rejection_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_compliance_documents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_document app.vendor_compliance_documents;
  v_requirement app.vendor_compliance_requirements;
  v_gate text;
begin
  if p_decision not in ('verified', 'rejected', 'revision_requested') then
    raise exception 'invalid_decision: % is not verified, rejected, or revision_requested', p_decision using errcode = 'check_violation';
  end if;
  if p_decision in ('rejected', 'revision_requested') and (p_rejection_reason is null or length(trim(p_rejection_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject or request revision of a compliance document' using errcode = 'check_violation';
  end if;

  select * into v_document from app.vendor_compliance_documents where id = p_document_id for update;
  if not found then
    raise exception 'vendor_compliance_document_not_found: %', p_document_id using errcode = 'no_data_found';
  end if;
  if v_document.record_version <> p_expected_version then
    raise exception 'stale_version: vendor compliance document % expected version % but found %', p_document_id, p_expected_version, v_document.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_document.verification_status <> 'pending' then
    raise exception 'invalid_transition: vendor compliance document % is already %', p_document_id, v_document.verification_status using errcode = 'check_violation';
  end if;

  v_gate := case p_decision when 'verified' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_document.tenant_id, 'PRC', v_gate);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_gate, v_decision.reason, v_document.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_requirement from app.vendor_compliance_requirements where id = v_document.requirement_version_id;
  if p_decision = 'verified' and v_requirement.requires_expiry and v_document.expiry_date is null then
    raise exception 'expiry_required_for_verification: document % has no expiry_date but requirement % requires one', p_document_id, v_requirement.id
      using errcode = 'check_violation';
  end if;

  update app.vendor_compliance_documents
  set verification_status = p_decision, rejection_reason = case when p_decision = 'verified' then null else p_rejection_reason end,
      verified_by = p_actor_label, verified_by_auth_user_id = p_actor_auth_user_id, verified_at = now(),
      record_version = record_version + 1, updated_at = now()
  where id = p_document_id and record_version = p_expected_version
  returning * into v_document;
  if not found then
    raise exception 'stale_version: vendor compliance document % target row was concurrently modified (expected version %)', p_document_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app._recalculate_vendor_compliance_status_family(v_document.vendor_master_record_id, v_requirement.requirement_family_id, p_actor_label);

  perform app.capture_audit_event(
    v_document.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_compliance_document',
    'app.vendor_compliance_documents', v_document.id, 'success', p_rejection_reason, null, jsonb_build_object('decision', p_decision)
  );

  return v_document;
end;
$$;

comment on function app.decide_vendor_compliance_document is 'PRC-253: verified requires PRC:Approve, rejected/revision_requested requires PRC:Reject (case-mapped, mirrors app.decide_vendor_assessment_review). No self-approval block (design note 12 -- this task''s own spec names self-approval exclusively for waiver decisions). Verifying against a requires_expiry requirement with no expiry_date on the document is rejected outright.';

-- Fix-pass addition (HIGH-severity finding, adversarial review): PLT-128's own
-- app.authorize_file_access -- "the single gate a real signed-URL-issuing server
-- action calls" -- was never referenced anywhere in this capability, so a reviewer
-- had no gated, audited path to actually view/download the evidence they were being
-- asked to verify/reject (Sec.15's "document/version viewer", Sec.16/18's "download
-- audited", Sec.21's "authorized reviewers verify them"). This wrapper composes:
-- (a) this capability's OWN PRC:Download authority check (the genuine fit design
-- note 11 originally, and incorrectly, disclosed as unused), (b) PLT-128's own single
-- access gate (malware-scan + record/sensitivity access, RPD-032), never a second,
-- parallel scan/authority check, and (c) this capability's own audit trail via
-- app.capture_audit_event, alongside PLT-128's own independent app.file_access_logs
-- row app.authorize_file_access itself always inserts. A denied access still returns
-- a row (result=denied, reason set) with every file-identifying field nulled out --
-- never raises -- so a caller shows a generic "access denied: <reason>" without
-- leaking filename/size/mime to a requester who was refused. storage_path is
-- deliberately never selected or returned here (PLT-128''s own "no raw file path
-- exposure" property, preserved, not regressed). Callable from app.authorize_file_
-- access (owned by the same role as every other function in this migration, no
-- SECURITY DEFINER of its own, service_role-EXECUTE-only at PLT-128''s own grant) only
-- because THIS function is itself SECURITY DEFINER -- the identical "already-
-- authorized SECURITY DEFINER caller" mechanism design note 13''s private helpers
-- already rely on, one layer up and crossing into PLT-128''s own schema surface.
create function app.access_vendor_compliance_document_evidence(
  p_document_id uuid, p_access_type text, p_actor_auth_user_id uuid, p_actor_label text, p_correlation_id uuid default null
)
returns table (
  file_id uuid, original_filename text, mime_type text, size_bytes bigint, malware_scan_status text,
  classification text, legal_hold boolean, uploaded_at timestamptz, access_result text, access_reason text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_document app.vendor_compliance_documents;
  v_file app.files;
  v_log app.file_access_logs;
begin
  if p_access_type not in ('signed_url_issued', 'download', 'metadata_view') then
    raise exception 'invalid_access_type: % is not one of signed_url_issued/download/metadata_view', p_access_type using errcode = 'check_violation';
  end if;

  select * into v_document from app.vendor_compliance_documents where id = p_document_id;
  if not found then
    raise exception 'vendor_compliance_document_not_found: %', p_document_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_document.tenant_id, 'PRC', 'Download');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Download (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_document.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_log := app.authorize_file_access(v_document.file_id, p_access_type, p_actor_auth_user_id, p_correlation_id);

  perform app.capture_audit_event(
    v_document.tenant_id, p_actor_auth_user_id, p_actor_label, 'access_vendor_compliance_document_evidence',
    -- app.audit_logs.result is the platform-wide success/failure enum (app.capture_audit_event's
    -- own constraint, distinct from PLT-128's own app.file_access_logs.result granted/denied
    -- enum used above for v_log) -- never conflate the two.
    'app.vendor_compliance_documents', v_document.id, case when v_log.result = 'granted' then 'success' else 'failure' end,
    v_log.reason, null, jsonb_build_object('access_type', p_access_type, 'result', v_log.result)
  );

  if v_log.result <> 'granted' then
    return query select v_document.file_id, null::text, null::text, null::bigint, null::text, null::text, null::boolean, null::timestamptz, v_log.result, v_log.reason;
    return;
  end if;

  select * into v_file from app.files where id = v_document.file_id;

  return query
  select v_file.id, v_file.original_filename, v_file.mime_type, v_file.size_bytes, v_file.malware_scan_status,
    v_file.classification, v_file.legal_hold, v_file.created_at, v_log.result, v_log.reason;
end;
$$;

comment on function app.access_vendor_compliance_document_evidence is 'PRC-253 fix-pass addition: the document/version viewer''s own gated evidence-access call (Sec.15/16/18/21) -- PRC:Download plus PLT-128''s own app.authorize_file_access (malware-scan + record/sensitivity gate, RPD-032), both audited (this capability''s own app.capture_audit_event AND app.authorize_file_access''s own app.file_access_logs row). Never returns storage_path. A denied result nulls out every file-identifying field rather than raising, so a UI can show "access denied: <reason>" without a second round trip.';

-- ===========================================================================
-- 8. Waiver RPCs (design notes 9, 12).
-- ===========================================================================

create function app.request_vendor_compliance_waiver(
  p_requirement_version_id uuid, p_vendor_master_record_id uuid, p_reason text, p_valid_from date, p_valid_until date,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_compliance_waivers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_requirement app.vendor_compliance_requirements;
  v_existing app.vendor_compliance_waivers;
  v_waiver app.vendor_compliance_waivers;
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

  select * into v_requirement from app.vendor_compliance_requirements where id = p_requirement_version_id and tenant_id = v_vendor.tenant_id;
  if not found then
    raise exception 'vendor_compliance_requirement_not_found: %', p_requirement_version_id using errcode = 'no_data_found';
  end if;
  if not app._vendor_compliance_requirement_applies(v_vendor, v_requirement) then
    raise exception 'requirement_not_applicable: requirement % does not apply to vendor % (category/service scope mismatch)', p_requirement_version_id, p_vendor_master_record_id
      using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request a compliance waiver' using errcode = 'check_violation';
  end if;
  if p_valid_from is null or p_valid_until is null or p_valid_until < p_valid_from then
    raise exception 'invalid_validity_window: valid_until must be on or after valid_from' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_compliance_waivers where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.requirement_version_id is distinct from p_requirement_version_id or v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id
        or v_existing.valid_from is distinct from p_valid_from or v_existing.valid_until is distinct from p_valid_until
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different waiver request', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_compliance_waivers (
      tenant_id, requirement_version_id, vendor_master_record_id, reason, valid_from, valid_until,
      requested_by, requested_by_auth_user_id, idempotency_key, created_by
    ) values (
      v_vendor.tenant_id, p_requirement_version_id, p_vendor_master_record_id, p_reason, p_valid_from, p_valid_until,
      p_actor_label, p_actor_auth_user_id, p_idempotency_key, p_actor_label
    )
    returning * into v_waiver;
  exception
    when unique_violation then
      select * into v_existing from app.vendor_compliance_waivers where tenant_id = v_vendor.tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.requirement_version_id is distinct from p_requirement_version_id or v_existing.vendor_master_record_id is distinct from p_vendor_master_record_id
        or v_existing.valid_from is distinct from p_valid_from or v_existing.valid_until is distinct from p_valid_until
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different waiver request', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    v_vendor.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_vendor_compliance_waiver',
    'app.vendor_compliance_waivers', v_waiver.id, 'success', null, null, to_jsonb(v_waiver)
  );

  return v_waiver;
end;
$$;

create function app.decide_vendor_compliance_waiver(
  p_waiver_id uuid, p_expected_version integer, p_decision text, p_decision_reason text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_compliance_waivers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_waiver app.vendor_compliance_waivers;
  v_requirement app.vendor_compliance_requirements;
  v_gate text;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not approved or rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'rejected' and (p_decision_reason is null or length(trim(p_decision_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a compliance waiver' using errcode = 'check_violation';
  end if;

  select * into v_waiver from app.vendor_compliance_waivers where id = p_waiver_id for update;
  if not found then
    raise exception 'vendor_compliance_waiver_not_found: %', p_waiver_id using errcode = 'no_data_found';
  end if;
  if v_waiver.record_version <> p_expected_version then
    raise exception 'stale_version: vendor compliance waiver % expected version % but found %', p_waiver_id, p_expected_version, v_waiver.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_waiver.status <> 'pending' then
    raise exception 'invalid_transition: vendor compliance waiver % is already %', p_waiver_id, v_waiver.status using errcode = 'check_violation';
  end if;

  -- MANDATORY self-approval block (design note 12, Sec.21's own "approved
  -- time-bounded waiver", mirrors app.decide_vendor_assessment_review's exact
  -- inline pattern) -- checked before the authority evaluation, on identity
  -- grounds, not merely permission grounds.
  if p_actor_auth_user_id = v_waiver.requested_by_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % requested vendor compliance waiver % and may not also decide it', p_actor_auth_user_id, p_waiver_id
      using errcode = 'insufficient_privilege';
  end if;

  v_gate := case p_decision when 'approved' then 'Approve' else 'Reject' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_waiver.tenant_id, 'PRC', v_gate);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_gate, v_decision.reason, v_waiver.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.vendor_compliance_waivers
  set status = p_decision, approved_by = p_actor_label, approved_by_auth_user_id = p_actor_auth_user_id, decision_reason = p_decision_reason,
      record_version = record_version + 1, updated_at = now()
  where id = p_waiver_id and record_version = p_expected_version
  returning * into v_waiver;
  if not found then
    raise exception 'stale_version: vendor compliance waiver % target row was concurrently modified (expected version %)', p_waiver_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_requirement from app.vendor_compliance_requirements where id = v_waiver.requirement_version_id;
  perform app._recalculate_vendor_compliance_status_family(v_waiver.vendor_master_record_id, v_requirement.requirement_family_id, p_actor_label);

  perform app.capture_audit_event(
    v_waiver.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_compliance_waiver',
    'app.vendor_compliance_waivers', v_waiver.id, 'success', p_decision_reason, null, jsonb_build_object('decision', p_decision)
  );

  return v_waiver;
end;
$$;

comment on function app.decide_vendor_compliance_waiver is 'PRC-253: MANDATORY maker-checker (design note 12) -- rejects self_approval_not_allowed if the actor is the waiver''s own requester, mirroring app.decide_vendor_assessment_review''s exact wording/shape. Approved requires PRC:Approve, rejected requires PRC:Reject.';

create function app.revoke_vendor_compliance_waiver(p_waiver_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_compliance_waivers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_waiver app.vendor_compliance_waivers;
  v_requirement app.vendor_compliance_requirements;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to revoke a compliance waiver' using errcode = 'check_violation';
  end if;

  select * into v_waiver from app.vendor_compliance_waivers where id = p_waiver_id for update;
  if not found then
    raise exception 'vendor_compliance_waiver_not_found: %', p_waiver_id using errcode = 'no_data_found';
  end if;
  if v_waiver.record_version <> p_expected_version then
    raise exception 'stale_version: vendor compliance waiver % expected version % but found %', p_waiver_id, p_expected_version, v_waiver.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_waiver.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_waiver.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_waiver.status <> 'approved' then
    raise exception 'invalid_transition: vendor compliance waiver % is % and cannot be revoked', p_waiver_id, v_waiver.status using errcode = 'check_violation';
  end if;

  update app.vendor_compliance_waivers
  set status = 'revoked', decision_reason = p_reason, record_version = record_version + 1, updated_at = now()
  where id = p_waiver_id and record_version = p_expected_version
  returning * into v_waiver;
  if not found then
    raise exception 'stale_version: vendor compliance waiver % target row was concurrently modified (expected version %)', p_waiver_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_requirement from app.vendor_compliance_requirements where id = v_waiver.requirement_version_id;
  perform app._recalculate_vendor_compliance_status_family(v_waiver.vendor_master_record_id, v_requirement.requirement_family_id, p_actor_label);

  perform app.capture_audit_event(
    v_waiver.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_vendor_compliance_waiver',
    'app.vendor_compliance_waivers', v_waiver.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_waiver;
end;
$$;

create function app.expire_vendor_compliance_waivers(p_tenant_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_max_rows integer default 500)
returns table (expired_count integer, more_remaining boolean)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_budget integer;
  v_count integer;
  v_total integer;
begin
  if p_tenant_id is null then
    raise exception 'tenant_required: a tenant id is required to sweep waiver expiry' using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_budget := least(greatest(coalesce(p_max_rows, 500), 1), 5000);

  select count(*) into v_total from app.vendor_compliance_waivers where tenant_id = p_tenant_id and status = 'approved' and valid_until < current_date;

  with doomed as (
    select id from app.vendor_compliance_waivers
    where tenant_id = p_tenant_id and status = 'approved' and valid_until < current_date
    order by valid_until
    limit v_budget
    for update
  )
  update app.vendor_compliance_waivers w
  set status = 'expired', updated_at = now(), record_version = record_version + 1
  from doomed d
  where w.id = d.id;
  get diagnostics v_count = row_count;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'expire_vendor_compliance_waivers',
    'app.vendor_compliance_waivers', null, 'success', null, null, jsonb_build_object('expired_count', v_count)
  );

  return query select v_count, (v_total > v_budget);
end;
$$;

comment on function app.expire_vendor_compliance_waivers is 'PRC-253: bounded (design note 9), PRC:Override-gated cosmetic/reporting sweep -- flips status to expired past valid_until. Eligibility-hold correctness never depends on this having run (app._recalculate_vendor_compliance_status_family checks the real calendar date directly), so a stale-but-unswept row never silently keeps a vendor eligible past its own waiver window.';

-- ===========================================================================
-- 9. Status recalculation RPCs (design notes 7, 8).
-- ===========================================================================

create function app.recalculate_vendor_compliance_status(p_vendor_master_record_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns setof app.vendor_compliance_status
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

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vendor.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vendor.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app._recalculate_vendor_compliance_status_all_families(p_vendor_master_record_id, p_actor_label);
end;
$$;

comment on function app.recalculate_vendor_compliance_status is 'PRC-253: the one public, documented, PRC:Edit-gated per-vendor recalculation entry point (design note 7) -- recomputes every applicable-or-previously-tracked requirement family for this vendor. Real, callable, bounded to one vendor''s own family set; not auto-scheduled (ISS-2026-015, design note 8).';

create function app.recalculate_tenant_vendor_compliance_status(p_tenant_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_max_vendors integer default 200)
returns table (vendors_recalculated integer, more_remaining boolean)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_budget integer;
  v_vendor record;
  v_count integer := 0;
  v_total integer;
begin
  if p_tenant_id is null then
    raise exception 'tenant_required: a tenant id is required to recalculate tenant compliance status' using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_budget := least(greatest(coalesce(p_max_vendors, 200), 1), 2000);

  select count(*) into v_total from app.vendor_profiles where tenant_id = p_tenant_id;

  for v_vendor in select master_record_id from app.vendor_profiles where tenant_id = p_tenant_id order by master_record_id limit v_budget
  loop
    perform app._recalculate_vendor_compliance_status_all_families(v_vendor.master_record_id, p_actor_label);
    v_count := v_count + 1;
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'recalculate_tenant_vendor_compliance_status',
    'app.vendor_compliance_status', null, 'success', null, null, jsonb_build_object('vendors_recalculated', v_count)
  );

  return query select v_count, (v_total > v_budget);
end;
$$;

comment on function app.recalculate_tenant_vendor_compliance_status is 'PRC-253: the bounded, PRC:Override-gated tenant-wide sweep (design note 8), mirroring app.purge_tracking_telemetry_history''s own real/bounded/not-yet-scheduled shape. Calls the private per-vendor helper directly (bypassing the public per-vendor RPC''s own separate PRC:Edit gate) since the outer PRC:Override check already covers authority for the whole sweep. No scheduler is added -- ISS-2026-015 is a standing, accepted, repository-wide gap.';

-- Supporting index for the version-lineage read below (list_vendor_compliance_document_versions) -- the table's own unique index only covers the single is_latest_version row per group.
create index vendor_compliance_documents_version_group_lookup_idx on app.vendor_compliance_documents (version_group_id, version_number);

-- ===========================================================================
-- 10. Read RPCs.
-- ===========================================================================

create function app.get_vendor_compliance_requirement(p_requirement_version_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_compliance_requirements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_requirement app.vendor_compliance_requirements;
begin
  select * into v_requirement from app.vendor_compliance_requirements where id = p_requirement_version_id;
  if not found then
    raise exception 'vendor_compliance_requirement_not_found: %', p_requirement_version_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_requirement.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_requirement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_compliance_requirements where id = p_requirement_version_id;
end;
$$;

create function app.list_vendor_compliance_requirements(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_vendor_category text default null,
  p_service_type text default null, p_requirement_family_id uuid default null, p_limit integer default 50, p_after_id uuid default null
)
returns setof app.vendor_compliance_requirements
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
  select r.* from app.vendor_compliance_requirements r
  where r.tenant_id = p_tenant_id
    and (p_status_filter is null or r.status = p_status_filter)
    and (p_vendor_category is null or r.vendor_category = p_vendor_category)
    and (p_service_type is null or r.service_type = p_service_type)
    and (p_requirement_family_id is null or r.requirement_family_id = p_requirement_family_id)
    and (p_after_id is null or r.id > p_after_id)
  order by r.id
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create function app.get_vendor_compliance_document(p_document_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_compliance_documents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_document app.vendor_compliance_documents;
begin
  select * into v_document from app.vendor_compliance_documents where id = p_document_id;
  if not found then
    raise exception 'vendor_compliance_document_not_found: %', p_document_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_document.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_document.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_compliance_documents where id = p_document_id;
end;
$$;

create function app.list_vendor_compliance_documents(
  p_vendor_master_record_id uuid, p_actor_auth_user_id uuid, p_requirement_version_id uuid default null,
  p_latest_only boolean default true, p_limit integer default 100, p_after_id uuid default null
)
returns setof app.vendor_compliance_documents
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
  select d.* from app.vendor_compliance_documents d
  where d.vendor_master_record_id = p_vendor_master_record_id
    and (p_requirement_version_id is null or d.requirement_version_id = p_requirement_version_id)
    and (not p_latest_only or d.is_latest_version)
    and (p_after_id is null or d.id > p_after_id)
  order by d.id
  limit least(coalesce(p_limit, 100), 500);
end;
$$;

create function app.list_vendor_compliance_document_versions(p_version_group_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_compliance_documents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_any app.vendor_compliance_documents;
begin
  select * into v_any from app.vendor_compliance_documents where version_group_id = p_version_group_id limit 1;
  if not found then
    raise exception 'vendor_compliance_document_not_found: no document with version_group_id %', p_version_group_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_any.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_any.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_compliance_documents where version_group_id = p_version_group_id order by version_number;
end;
$$;

comment on function app.list_vendor_compliance_document_versions is 'PRC-253: the document/version viewer''s own data source (Sec.15) -- full lineage for one compliance evidence slot, oldest to newest, proving renewal never deletes prior evidence (design note 4).';

create function app.get_vendor_compliance_waiver(p_waiver_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_compliance_waivers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_waiver app.vendor_compliance_waivers;
begin
  select * into v_waiver from app.vendor_compliance_waivers where id = p_waiver_id;
  if not found then
    raise exception 'vendor_compliance_waiver_not_found: %', p_waiver_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_waiver.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_waiver.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_compliance_waivers where id = p_waiver_id;
end;
$$;

create function app.list_vendor_compliance_waivers(
  p_vendor_master_record_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 50, p_after_id uuid default null
)
returns setof app.vendor_compliance_waivers
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
  if p_status_filter is not null and p_status_filter not in ('pending', 'approved', 'rejected', 'expired', 'revoked') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select w.* from app.vendor_compliance_waivers w
  where w.vendor_master_record_id = p_vendor_master_record_id
    and (p_status_filter is null or w.status = p_status_filter)
    and (p_after_id is null or w.id > p_after_id)
  order by w.id
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

-- The downstream-composable read RPC (task brief's own "Downstream" scope note --
-- Prompts 256+ (sourcing/PO/assignment) don't exist yet in this repository, so this
-- migration builds only the READ side a future capability will compose against). One
-- row per requirement family currently tracked for this vendor.
create function app.get_vendor_compliance_eligibility(p_vendor_master_record_id uuid, p_actor_auth_user_id uuid)
returns table (
  requirement_family_id uuid, requirement_version_id uuid, requirement_name text, blocking_effect text,
  document_type_code text, status text, eligibility_hold boolean, current_document_id uuid, expiry_date date,
  reminder_offsets integer[], days_until_expiry integer, reminder_tier_days integer, computed_at timestamptz
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
  select s.requirement_family_id, s.current_requirement_version_id, r.name, r.blocking_effect, r.document_type_code,
    s.status, s.eligibility_hold, s.current_document_id, d.expiry_date, r.reminder_offsets,
    (d.expiry_date - current_date) as days_until_expiry,
    (select min(o) from unnest(r.reminder_offsets) o where o >= (d.expiry_date - current_date)) as reminder_tier_days,
    s.computed_at
  from app.vendor_compliance_status s
  left join app.vendor_compliance_requirements r on r.id = s.current_requirement_version_id
  left join app.vendor_compliance_documents d on d.id = s.current_document_id
  where s.vendor_master_record_id = p_vendor_master_record_id
  order by r.name nulls last;
end;
$$;

comment on function app.get_vendor_compliance_eligibility is 'PRC-253: the downstream-composable read RPC (task brief''s own "Downstream" scope note) -- one row per requirement family currently tracked for this vendor, reflecting app.vendor_compliance_status''s own last-computed projection (never live-recomputed on read -- call app.recalculate_vendor_compliance_status first for a fresh view). A future sourcing/PO/assignment capability (256+) composes eligibility by checking whether any row has eligibility_hold=true -- this migration itself never builds that composition or mutates app.vendor_profiles.lifecycle_status. Fix-pass addition (MEDIUM-severity finding, adversarial review): reminder_offsets/days_until_expiry/reminder_tier_days surface WHICH reminder tier a document has already crossed (the smallest already-triggered offset -- e.g. {30,14,7} at 10 days remaining reads reminder_tier_days=14, not just an undifferentiated expiring_soon) -- app.vendor_compliance_status''s own status column deliberately stays a single expiring_soon value (this task''s own named enum), these are read-time-computed, never stored.';

-- Tenant-wide compliance matrix / expiring-soon-and-holds queue -- one flexible,
-- cursor-paginated, server-filtered read RPC serves both UI surfaces (Sec.15's own
-- "compliance matrix" and "expiry calendar/queue").
create function app.list_tenant_vendor_compliance_matrix(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_hold_only boolean default false,
  p_vendor_master_record_id uuid default null, p_limit integer default 100, p_after_id uuid default null
)
returns table (
  status_id uuid, vendor_master_record_id uuid, vendor_legal_name text, requirement_family_id uuid, requirement_version_id uuid,
  requirement_name text, blocking_effect text, document_type_code text, status text, eligibility_hold boolean,
  current_document_id uuid, expiry_date date, reminder_offsets integer[], days_until_expiry integer, reminder_tier_days integer,
  computed_at timestamptz
)
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
  if p_status_filter is not null and p_status_filter not in ('not_submitted', 'pending_verification', 'verified', 'expiring_soon', 'expired', 'waived', 'rejected') then
    raise exception 'invalid_status_filter: %', p_status_filter using errcode = 'check_violation';
  end if;

  return query
  select s.id, s.vendor_master_record_id, v.legal_name, s.requirement_family_id, s.current_requirement_version_id,
    r.name, r.blocking_effect, r.document_type_code, s.status, s.eligibility_hold, s.current_document_id, d.expiry_date, r.reminder_offsets,
    (d.expiry_date - current_date) as days_until_expiry,
    (select min(o) from unnest(r.reminder_offsets) o where o >= (d.expiry_date - current_date)) as reminder_tier_days,
    s.computed_at
  from app.vendor_compliance_status s
  join app.vendor_profiles v on v.master_record_id = s.vendor_master_record_id
  left join app.vendor_compliance_requirements r on r.id = s.current_requirement_version_id
  left join app.vendor_compliance_documents d on d.id = s.current_document_id
  where s.tenant_id = p_tenant_id
    and (p_status_filter is null or s.status = p_status_filter)
    and (not p_hold_only or s.eligibility_hold)
    and (p_vendor_master_record_id is null or s.vendor_master_record_id = p_vendor_master_record_id)
    and (p_after_id is null or s.id > p_after_id)
  order by s.id
  limit least(coalesce(p_limit, 100), 500);
end;
$$;

comment on function app.list_tenant_vendor_compliance_matrix is 'PRC-253: the compliance-matrix (Sec.15) and expiry/reminders-queue (p_status_filter in (expiring_soon,expired), or p_hold_only=true) shared read RPC -- cursor-paginated, server-filtered, joined for display (vendor legal name, requirement name/blocking effect) so the UI never loads a full unfiltered dataset (Sec.17). reminder_tier_days (fix-pass addition, MEDIUM-severity finding) is the smallest reminder_offsets entry already crossed by days_until_expiry, letting the reminders queue distinguish a 30-day-tier row from a 7-day-tier row instead of collapsing every expiring_soon row into one undifferentiated bucket.';

-- ===========================================================================
-- 11. RLS -- default-deny form, identical shape to PRC-251/252.
-- ===========================================================================

alter table app.vendor_compliance_requirements enable row level security;
alter table app.vendor_compliance_documents enable row level security;
alter table app.vendor_compliance_waivers enable row level security;
alter table app.vendor_compliance_status enable row level security;

create policy vendor_compliance_requirements_select_scoped on app.vendor_compliance_requirements
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_compliance_documents_select_scoped on app.vendor_compliance_documents
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_compliance_waivers_select_scoped on app.vendor_compliance_waivers
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_compliance_status_select_scoped on app.vendor_compliance_status
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 12. Grants (design note 15, ERR-2026-004).
-- ===========================================================================

grant select on app.vendor_compliance_requirements to authenticated, service_role;
grant select on app.vendor_compliance_documents to authenticated, service_role;
grant select on app.vendor_compliance_waivers to authenticated, service_role;
grant select on app.vendor_compliance_status to authenticated, service_role;

revoke execute on all functions in schema app from public;

grant execute on function app.create_vendor_compliance_requirement_draft(uuid, text, text, text, text, text, text, boolean, integer[], timestamptz, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_compliance_requirement_draft(uuid, integer, text, text, text, text, text, text, boolean, integer[], timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.publish_vendor_compliance_requirement(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.archive_vendor_compliance_requirement(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.submit_vendor_compliance_document(uuid, uuid, uuid, date, date, text, uuid, text) to authenticated, service_role;
grant execute on function app.renew_vendor_compliance_document(uuid, uuid, date, date, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_compliance_document(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.access_vendor_compliance_document_evidence(uuid, text, uuid, text, uuid) to authenticated, service_role;

grant execute on function app.request_vendor_compliance_waiver(uuid, uuid, text, date, date, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_compliance_waiver(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.revoke_vendor_compliance_waiver(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.expire_vendor_compliance_waivers(uuid, uuid, text, integer) to authenticated, service_role;

grant execute on function app.recalculate_vendor_compliance_status(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.recalculate_tenant_vendor_compliance_status(uuid, uuid, text, integer) to authenticated, service_role;

grant execute on function app.get_vendor_compliance_requirement(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_compliance_requirements(uuid, uuid, text, text, text, uuid, integer, uuid) to authenticated, service_role;
grant execute on function app.get_vendor_compliance_document(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_compliance_documents(uuid, uuid, uuid, boolean, integer, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_compliance_document_versions(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_vendor_compliance_waiver(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_compliance_waivers(uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.get_vendor_compliance_eligibility(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_tenant_vendor_compliance_matrix(uuid, uuid, text, boolean, uuid, integer, uuid) to authenticated, service_role;
