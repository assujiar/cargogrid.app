-- HRIS capability HRT-276 (Recruitment, Job Portal and ATS, CG-S12-HRT-004)
-- Builds tenant-scoped recruitment from approved vacancy through candidate assessment,
-- interview and offer, plus a genuinely public (anonymous, token-based, enumeration-safe,
-- rate-limited) job-application intake surface bound to open vacancies only. Candidate
-- identity is explicitly NOT app.employees/app.users (ADR-0023 Part B) -- this migration
-- creates neither; the governed onboarding conversion is Prompt 277's own job.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Candidates are NOT routed through app.master_records.** Unlike vendor/driver/
--    employee (each a canonical operational actor other modules reference widely), a
--    candidate is not yet an operational actor anywhere else in this repository -- and
--    per ADR-0023 Part B a candidate must never silently become employee/user truth.
--    Registering a `master_type_code='candidate'` row now would pre-empt Prompt 277's own
--    conversion design (does conversion "merge" the candidate into a new employee master
--    record, or reference it structurally?) with a decision this checkpoint has no
--    mandate to make. Mirrors HRT-275's own identical reasoning for position/grade
--    ("not an operational actor identity needing merge/dedupe/lifecycle across external
--    sources" -- decision 3.2 there). `app.candidates` is a bespoke, directly
--    tenant-scoped table instead, structurally identical in shape convention to
--    `app.vendor_profiles`/`app.employees` (code-free here -- candidates have no natural
--    business code) minus the master_records extension.
--
-- 2. **The public intake surface mirrors PRC-251's proven vendor-intake shape, not a new
--    design.** A per-open-vacancy hashed, expiring, MULTI-USE posting token (distinct
--    from PRC-251's SINGLE-USE invitation token -- many candidates apply to one vacancy)
--    replaces the raw vacancy id everywhere the public route touches it, so no internal
--    UUID is ever exposed as a guessable enumeration surface; `app.resolve_public_job_
--    posting`/`app.list_public_open_vacancies` collapse every failure mode (bad token,
--    expired, revoked, vacancy no longer open, unknown tenant slug) into the SAME
--    uniform not-found/empty response, exactly like `app.resolve_vendor_self_
--    registration_target`. `app.submit_public_job_application` mirrors `app.submit_
--    vendor_profile_self_registration`'s anonymous shape: `p_client_key`-scoped
--    15-minute sliding-window rate limiting, an append-only attempts log
--    (`app.job_application_intake_attempts`, mirrors `app.vendor_intake_attempts`), never
--    raises once the rate-limit check passes, `service_role`-only (never granted to
--    `anon`), fronted by a server-rendered Next.js route using the service-role client --
--    the identical "no new `anon` Postgres grant" posture ERR-2026-004 established.
--
-- 3. **Resume/candidate document upload is deliberately NOT built as a new anonymous
--    entry point in this checkpoint.** This migration already opens this repository's
--    SECOND-EVER anonymous surface (BUILD_EXECUTION_PROTOCOL.md section 3.2's own
--    "first-of-its-kind security mechanism" trigger). Compounding that with a second,
--    genuinely new anonymous-file-upload authority path (PLT-128's `app.initiate_file_
--    upload`/`app.check_file_action_authority` both assume a real actor session) in the
--    SAME migration doubles first-of-its-kind risk for no requirement that actually
--    forces it -- section 16/17 name "candidate documents" and "async resume scan", not
--    "the public form must itself accept a file". Decision: the `candidate_resume`
--    document type is registered here (so a tenant CAN configure and use it), and
--    candidate document/resume attachment reuses the EXISTING, already-hardened,
--    already-`authenticated`-granted `app.initiate_file_upload`/`app.record_file_scan_
--    result`/`app.authorize_file_access` RPCs directly (`record_type='candidate'`) --
--    zero new SQL required for a staff member to attach a document today, exactly
--    HRT-274's own disclosed employee-document posture (`ISS-2026-064` item 2). `app.
--    update_candidate_profile` accepts a `p_resume_file_id` that, when supplied, is
--    re-validated for tenant/record-type/record-id/malware-scan-status match at the
--    ACCEPTING RPC (taxonomy C-10), never trusted from the caller.
--
-- 4. **Offer approval reuses PLT-123 end to end, with no bespoke threshold-policy
--    table.** Unlike PRC-259 (six entity types, independently thresholded), this
--    checkpoint governs exactly one entity type (`'job_offer'`) and every offer requires
--    approval unconditionally -- mirroring COM-153's shape (`app.request_approval`
--    called inside the domain's own submit RPC, one domain sync wrapper over `app.
--    decide_approval_step`, `entity_type` discriminates the request) but WITHOUT COM-
--    153's own bespoke `quotation_approval_rules` threshold table, since there is no
--    threshold dimension to evaluate here -- building one for a single always-required
--    entity type would be unused machinery. Reuses the SAME tenant-wide, already-
--    established `config_type_code='approval'`/`scope_level='tenant'` config object
--    every other domain shares; a tenant with no published routing definition fails
--    CLOSED (`approval_definition_not_configured`), never silently skips approval.
--    Submitting a MATERIALLY NEW offer version after a prior version was already
--    approved/rejected always resets `approval_status`/`status` back to `draft`/`not_
--    required` -- a stale approval decision must never be read as covering different
--    terms (a live, disclosed defect class this migration was written to avoid from day
--    one, not retrofitted after a review finding).
--
-- 5. **Interviewer field/record restriction is real, not RBAC-only (section 16).**
--    `app.submit_interview_feedback` is gated by IDENTITY MATCH against `app.interview_
--    interviewers` (the caller's own linked employee must be an assigned interviewer for
--    THIS interview) -- never by a generic HRS:Edit permission, mirroring `app.request_
--    employee_change`'s own identity-match-only gate (HRT-274). `app.get_my_assigned_
--    interviews` is the matching self-scoped read, letting an interviewer with ZERO HRS
--    permissions see only the candidates/applications they are actually assigned to
--    interview -- never the full pipeline.
--
-- 6. **Application stage transitions are a bounded, forward-only rank order
--    (new -> screening -> assessment -> interview -> offer), not a fully configurable
--    workflow graph.** `app.transition_application_stage` allows any forward jump
--    (skipping is legal -- not every vacancy runs every stage) but never a backward
--    move, and never targets `rejected`/`withdrawn`/`offer_accepted` (each has its own
--    dedicated RPC with its own required-reason/prerequisite validation, mirroring PRC-
--    251's `decide_vendor_profile_review` vs `archive_vendor_profile`/`suspend_vendor_
--    profile` separation). A disclosed, bounded interpretation of section 20's "stage/
--    offer versions" -- a fully general configurable pipeline-stage engine is a larger,
--    unrequested feature.
--
-- 7. **Assessment "versioned criteria" (section 24) is a free-text `criteria_version`
--    column, not a separate templated criteria-authoring/governance table** -- the same
--    bounded, disclosed interpretation HRT-274 §3.3 already used for employee-number
--    "configurable format" (no template engine exists anywhere in this repository to
--    reuse; building one is disproportionate scope for this checkpoint).
--
-- 8. **Duplicate candidate detection never auto-merges** (mirrors PRC-251/HRT-274 exactly)
--    -- `app.decide_candidate_duplicate` records a human decision (linked/dismissed),
--    never invoking any merge machinery (none exists for candidates, by design 1 above).
--
-- 9. **`app.candidates` carries classified PII columns** (national_id_number,
--    date_of_birth, address, phone, email -- the entire point of contact with a real
--    person before they are anything else in this system) -- masked by `app.has_view_
--    personal_data` (PLT-114, reused unchanged, already hardcoded to the 'HRS' module)
--    at the RPC read layer, AND column-restricted at the grant layer from day one
--    (PLT-114's own already-proven `grant select (<explicit non-pii column list>)`
--    pattern, applied here from the start rather than retrofitted after a review finding
--    the way HRT-274's own first pass needed). `full_name` is deliberately NOT masked
--    (needed for basic listing/search/duplicate detection, matching `app.employees.full_
--    name`'s own established treatment).
--
-- Per ERR-2026-004: this migration carries its own explicit
-- REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement before its final
-- grants, the standing per-migration convention since PLT-118.

-- ===========================================================================
-- 1. Candidate document type registration (design note 3) -- direct-INSERT
--    convention (mirrors 'employee_document', HRT-274 section 12): app.register_
--    document_type gates on Supreme Admin and a migration-apply context has no live
--    actor. Each tenant separately publishes its own document:candidate_resume policy
--    (allowed MIME types, max size, retention, classification) via the Configuration
--    Engine before any real upload succeeds -- the same per-tenant onboarding step every
--    document type in this repository requires.
-- ===========================================================================

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values ('candidate_resume', 'Candidate Resume/CV', 'HRS', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('document:candidate_resume', 'Candidate Resume/CV', 'HRS', 'system')
on conflict (code) do nothing;

-- ===========================================================================
-- 2. Vacancy tables.
-- ===========================================================================

create table app.job_vacancies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  position_id uuid not null references app.positions (id),
  title text not null,
  employment_type text not null,
  headcount integer not null default 1,
  status text not null default 'draft',
  status_reason text,
  description text,
  requirements text,
  hiring_manager_employee_id uuid references app.employees (master_record_id),
  owner_auth_user_id uuid references auth.users (id),
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_vacancies_title_check check (length(trim(title)) > 0),
  constraint job_vacancies_employment_type_check check (employment_type in ('full_time', 'part_time', 'contract', 'internship', 'temporary')),
  constraint job_vacancies_headcount_check check (headcount > 0),
  constraint job_vacancies_status_check check (status in ('draft', 'open', 'on_hold', 'closed', 'cancelled')),
  constraint job_vacancies_status_reason_shape_check check (
    status not in ('on_hold', 'closed', 'cancelled') or (status_reason is not null and length(trim(status_reason)) > 0)
  )
);

comment on table app.job_vacancies is
  'HRT-276: tenant-scoped recruitment vacancy, always bound to a real app.positions row (position_id is immutable after creation -- never changed by any RPC in this migration). headcount is validated against the position''s own real remaining capacity at publish time (app.count_position_active_primary_headcount, HRT-275), never a bare unchecked integer.';

create index job_vacancies_tenant_status_idx on app.job_vacancies (tenant_id, status);
create index job_vacancies_tenant_position_idx on app.job_vacancies (tenant_id, position_id);
create unique index job_vacancies_idempotency_key_unique on app.job_vacancies (tenant_id, idempotency_key) where idempotency_key is not null;

create trigger job_vacancies_touch_row
  before update on app.job_vacancies
  for each row
  execute function app.touch_org_unit_row();

create table app.job_vacancy_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vacancy_id uuid not null references app.job_vacancies (id),
  from_status text not null,
  to_status text not null,
  reason text,
  actor_auth_user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now()
);

comment on table app.job_vacancy_lifecycle_events is
  'HRT-276: append-only vacancy lifecycle timeline, distinct from app.audit_logs -- the domain-shaped history the vacancy detail UI reads directly, mirroring app.vendor_profile_lifecycle_events (PRC-251).';

create index job_vacancy_lifecycle_events_vacancy_idx on app.job_vacancy_lifecycle_events (vacancy_id, occurred_at);

create table app.job_vacancy_postings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vacancy_id uuid not null references app.job_vacancies (id),
  posting_token text not null,
  status text not null default 'active',
  expires_at timestamptz not null,
  published_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_reason text,
  record_version integer not null default 1,
  constraint job_vacancy_postings_status_check check (status in ('active', 'expired', 'revoked')),
  constraint job_vacancy_postings_token_unique unique (posting_token)
);

comment on table app.job_vacancy_postings is
  'HRT-276: one MULTI-USE, expiring public posting identifier per publish event -- unlike PRC-251''s single-use invite token (app.vendor_intake_tokens, hash-only, shown once), a job posting must be freely re-discoverable by every browsing candidate via app.get_public_open_vacancy_summaries, so posting_token is stored and returned DIRECTLY, never hashed -- hashing a value that must itself be redisplayed on every listing call would make it uncomparable (the whole point of a one-way hash). The property this token provides is UNGUESSABILITY (32 random bytes, hex-encoded -- 64 hex characters of entropy, structurally unenumerable), not secrecy from its own intended public audience. At most one active posting per vacancy at a time (partial unique index below).';

create unique index job_vacancy_postings_one_active_idx on app.job_vacancy_postings (vacancy_id) where status = 'active';
create index job_vacancy_postings_tenant_idx on app.job_vacancy_postings (tenant_id);

-- Append-only anti-enumeration evidence for the two anonymous entry points, mirroring
-- app.vendor_intake_attempts (PRC-251) exactly.
create table app.job_application_intake_attempts (
  id uuid primary key default gen_random_uuid(),
  client_key text not null,
  kind text not null,
  result text not null,
  occurred_at timestamptz not null default now(),
  constraint job_application_intake_attempts_kind_check check (kind in ('view_posting', 'submit_application')),
  constraint job_application_intake_attempts_result_check check (result in ('success', 'not_found', 'invalid', 'rate_limited', 'conflict'))
);

comment on table app.job_application_intake_attempts is
  'HRT-276: append-only anti-enumeration/anti-abuse evidence for app.resolve_public_job_posting and app.submit_public_job_application, mirroring app.vendor_intake_attempts (PRC-251). client_key is a hash of the caller''s own IP/session, computed by the calling Server Action.';

create index job_application_intake_attempts_client_key_idx on app.job_application_intake_attempts (client_key, occurred_at desc);

-- ===========================================================================
-- 3. Candidate tables (design note 1, 9).
-- ===========================================================================

create table app.candidates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  full_name text not null,
  email text not null,
  phone text,
  national_id_number text,
  date_of_birth date,
  address text,
  resume_file_id uuid references app.files (id),
  source text not null,
  referral_employee_id uuid references app.employees (master_record_id),
  consent_given boolean not null default false,
  consent_given_at timestamptz,
  consent_version text,
  status text not null default 'active',
  block_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint candidates_full_name_check check (length(trim(full_name)) > 0),
  constraint candidates_email_check check (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  constraint candidates_source_check check (source in ('public_application', 'staff_created', 'referral', 'agency', 'talent_pool', 'import')),
  constraint candidates_status_check check (status in ('active', 'blocked', 'archived')),
  constraint candidates_block_reason_check check (status <> 'blocked' or (block_reason is not null and length(trim(block_reason)) > 0)),
  constraint candidates_consent_shape_check check (
    (consent_given = false) or (consent_given_at is not null and consent_version is not null and length(trim(consent_version)) > 0)
  )
);

comment on table app.candidates is
  'HRT-276: tenant-scoped candidate identity -- deliberately NOT app.master_records/app.employees/app.users (design note 1, ADR-0023 Part B). national_id_number/date_of_birth/address/phone/email are classified pii, masked by app.has_view_personal_data and column-restricted at the grant layer (design note 9). Never hard-deleted -- status=''archived'' only.';

create index candidates_tenant_status_idx on app.candidates (tenant_id, status);
create index candidates_tenant_email_idx on app.candidates (tenant_id, lower(email));
create index candidates_tenant_phone_idx on app.candidates (tenant_id, phone) where phone is not null;
create index candidates_full_name_trgm_idx on app.candidates using gin (full_name gin_trgm_ops);
create unique index candidates_idempotency_key_unique on app.candidates (tenant_id, idempotency_key) where idempotency_key is not null;

create trigger candidates_touch_row
  before update on app.candidates
  for each row
  execute function app.touch_org_unit_row();

create table app.candidate_duplicate_candidates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  source_candidate_id uuid not null references app.candidates (id),
  candidate_id uuid not null references app.candidates (id),
  similarity_basis text not null,
  similarity_score numeric,
  decision text not null default 'pending',
  decided_by text,
  decided_at timestamptz,
  decided_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  constraint candidate_duplicate_candidates_not_self_check check (source_candidate_id <> candidate_id),
  constraint candidate_duplicate_candidates_similarity_basis_check check (length(trim(similarity_basis)) > 0),
  constraint candidate_duplicate_candidates_decision_check check (decision in ('pending', 'linked', 'dismissed')),
  constraint candidate_duplicate_candidates_decided_shape_check check (
    (decision = 'pending' and decided_at is null and decided_by is null and decided_reason is null) or
    (decision <> 'pending' and decided_at is not null and decided_by is not null and decided_reason is not null and length(trim(decided_reason)) > 0)
  )
);

comment on table app.candidate_duplicate_candidates is
  'HRT-276: source candidate -> candidate identity pairing flagged for human review (design note 8). decision=''linked'' documents a reviewer''s finding, never triggers an automatic merge -- no merge machinery exists for candidates at all (design note 1).';

create index candidate_duplicate_candidates_source_idx on app.candidate_duplicate_candidates (source_candidate_id);
create index candidate_duplicate_candidates_source_pending_idx on app.candidate_duplicate_candidates (source_candidate_id) where decision = 'pending';

-- ===========================================================================
-- 4. Application tables.
-- ===========================================================================

create table app.job_applications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vacancy_id uuid not null references app.job_vacancies (id),
  candidate_id uuid not null references app.candidates (id),
  stage text not null default 'new',
  source text not null,
  applied_at timestamptz not null default now(),
  stage_since timestamptz not null default now(),
  rejection_reason text,
  withdrawal_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_applications_stage_check check (stage in ('new', 'screening', 'assessment', 'interview', 'offer', 'offer_accepted', 'rejected', 'withdrawn')),
  constraint job_applications_source_check check (source in ('public_application', 'staff_created', 'referral', 'agency', 'talent_pool', 'import')),
  constraint job_applications_rejection_reason_check check (stage <> 'rejected' or (rejection_reason is not null and length(trim(rejection_reason)) > 0)),
  constraint job_applications_withdrawal_reason_check check (stage <> 'withdrawn' or (withdrawal_reason is not null and length(trim(withdrawal_reason)) > 0))
);

comment on table app.job_applications is
  'HRT-276: one candidate''s application against one vacancy. stage is a bounded, forward-only rank order (design note 6). At most one non-terminal application per (candidate, vacancy) -- the partial unique index below -- a candidate whose prior application was rejected/withdrawn may re-apply.';

create unique index job_applications_one_active_idx on app.job_applications (candidate_id, vacancy_id) where stage not in ('rejected', 'withdrawn');
create index job_applications_tenant_vacancy_stage_idx on app.job_applications (tenant_id, vacancy_id, stage);
create index job_applications_tenant_candidate_idx on app.job_applications (tenant_id, candidate_id);
create unique index job_applications_idempotency_key_unique on app.job_applications (tenant_id, idempotency_key) where idempotency_key is not null;

create trigger job_applications_touch_row
  before update on app.job_applications
  for each row
  execute function app.touch_org_unit_row();

create table app.application_stage_history (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  application_id uuid not null references app.job_applications (id),
  from_stage text not null,
  to_stage text not null,
  reason text,
  actor_auth_user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now()
);

comment on table app.application_stage_history is
  'HRT-276: append-only stage-transition timeline, one row per real transition, written by every stage-changing RPC in the same transaction. The domain-shaped pipeline timeline the application detail UI reads directly, never re-derived from app.audit_logs.';

create index application_stage_history_application_idx on app.application_stage_history (application_id, occurred_at);

-- ===========================================================================
-- 5. Assessment table.
-- ===========================================================================

create table app.candidate_assessments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  application_id uuid not null references app.job_applications (id),
  assessment_type text not null,
  criteria_version text not null,
  max_score numeric not null,
  pass_threshold numeric,
  score numeric,
  status text not null default 'pending',
  assessor_auth_user_id uuid references auth.users (id),
  notes text,
  completed_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint candidate_assessments_type_check check (assessment_type in ('screening', 'technical', 'behavioral', 'case_study', 'other')),
  constraint candidate_assessments_criteria_version_check check (length(trim(criteria_version)) > 0),
  constraint candidate_assessments_max_score_check check (max_score > 0),
  constraint candidate_assessments_pass_threshold_check check (pass_threshold is null or (pass_threshold >= 0 and pass_threshold <= max_score)),
  constraint candidate_assessments_score_check check (score is null or (score >= 0 and score <= max_score)),
  constraint candidate_assessments_status_check check (status in ('pending', 'in_progress', 'completed', 'cancelled')),
  constraint candidate_assessments_completed_shape_check check (status <> 'completed' or (score is not null and completed_at is not null))
);

comment on table app.candidate_assessments is
  'HRT-276: one scored assessment round for one application. criteria_version is a bounded free-text interpretation of "versioned criteria" (design note 7) -- no separate criteria-template governance table exists. score is bounded to [0, max_score] structurally (taxonomy C-15), never an unchecked numeric.';

create index candidate_assessments_application_idx on app.candidate_assessments (application_id);
create index candidate_assessments_tenant_status_idx on app.candidate_assessments (tenant_id, status);

create trigger candidate_assessments_touch_row
  before update on app.candidate_assessments
  for each row
  execute function app.touch_org_unit_row();

-- ===========================================================================
-- 6. Interview tables.
-- ===========================================================================

create table app.interviews (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  application_id uuid not null references app.job_applications (id),
  round integer not null default 1,
  mode text not null,
  scheduled_at timestamptz not null,
  duration_minutes integer not null,
  location_or_link text,
  status text not null default 'scheduled',
  cancel_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint interviews_round_check check (round > 0),
  constraint interviews_mode_check check (mode in ('in_person', 'phone', 'video')),
  constraint interviews_duration_check check (duration_minutes > 0),
  constraint interviews_status_check check (status in ('scheduled', 'completed', 'cancelled', 'no_show')),
  constraint interviews_cancel_reason_check check (status <> 'cancelled' or (cancel_reason is not null and length(trim(cancel_reason)) > 0))
);

comment on table app.interviews is 'HRT-276: one interview round for one application. Panel membership is app.interview_interviewers (below); scorecards are app.interview_feedback, one row per assigned interviewer.';

create index interviews_application_idx on app.interviews (application_id);
create index interviews_tenant_scheduled_idx on app.interviews (tenant_id, scheduled_at);

create trigger interviews_touch_row
  before update on app.interviews
  for each row
  execute function app.touch_org_unit_row();

create table app.interview_interviewers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  interview_id uuid not null references app.interviews (id),
  employee_id uuid not null references app.employees (master_record_id),
  is_lead boolean not null default false,
  created_at timestamptz not null default now(),
  constraint interview_interviewers_unique unique (interview_id, employee_id)
);

comment on table app.interview_interviewers is 'HRT-276: the assigned interview panel -- the identity boundary app.submit_interview_feedback gates against (design note 5), not a generic HRS:Edit permission.';

create index interview_interviewers_interview_idx on app.interview_interviewers (interview_id);
create index interview_interviewers_employee_idx on app.interview_interviewers (employee_id);

create table app.interview_feedback (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  interview_id uuid not null references app.interviews (id),
  interviewer_employee_id uuid not null references app.employees (master_record_id),
  rating integer not null,
  recommendation text not null,
  notes text,
  submitted_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint interview_feedback_rating_check check (rating between 1 and 5),
  constraint interview_feedback_recommendation_check check (recommendation in ('strong_yes', 'yes', 'no', 'strong_no')),
  constraint interview_feedback_unique unique (interview_id, interviewer_employee_id)
);

comment on table app.interview_feedback is 'HRT-276: one scorecard per assigned interviewer per interview -- app.submit_interview_feedback is the only write path, identity-gated to the interviewer themself (design note 5).';

create index interview_feedback_interview_idx on app.interview_feedback (interview_id);

-- ===========================================================================
-- 7. Offer tables (design note 4).
-- ===========================================================================

create table app.job_offers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  application_id uuid not null references app.job_applications (id),
  status text not null default 'draft',
  approval_status text not null default 'not_required',
  approval_request_id uuid references app.approval_requests (id),
  current_version_id uuid,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_offers_application_unique unique (application_id),
  constraint job_offers_status_check check (status in ('draft', 'pending_approval', 'approved', 'extended', 'accepted', 'declined', 'withdrawn')),
  constraint job_offers_approval_status_check check (approval_status in ('not_required', 'pending', 'approved', 'rejected'))
);

comment on table app.job_offers is
  'HRT-276: one offer record per application (unique). Terms live on app.job_offer_versions (one row per version, immutable once created) -- current_version_id points at the latest. Approval is real, unconditional PLT-123 routing (design note 4) -- no threshold bypass.';

create index job_offers_tenant_status_idx on app.job_offers (tenant_id, status);

create trigger job_offers_touch_row
  before update on app.job_offers
  for each row
  execute function app.touch_org_unit_row();

create table app.job_offer_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  offer_id uuid not null references app.job_offers (id),
  version_number integer not null,
  compensation_amount numeric not null,
  compensation_currency text not null,
  effective_date date not null,
  expiry_date date,
  title text not null,
  employment_type text not null,
  benefits_note text,
  status text not null default 'draft',
  created_by text,
  created_at timestamptz not null default now(),
  constraint job_offer_versions_version_unique unique (offer_id, version_number),
  constraint job_offer_versions_amount_check check (compensation_amount >= 0),
  constraint job_offer_versions_currency_check check (length(trim(compensation_currency)) > 0),
  constraint job_offer_versions_title_check check (length(trim(title)) > 0),
  constraint job_offer_versions_employment_type_check check (employment_type in ('full_time', 'part_time', 'contract', 'internship', 'temporary')),
  constraint job_offer_versions_expiry_check check (expiry_date is null or expiry_date >= effective_date),
  constraint job_offer_versions_status_check check (status in ('draft', 'submitted', 'superseded'))
);

comment on table app.job_offer_versions is
  'HRT-276: one immutable offer-terms snapshot per version -- never mutated once created (design note 4), only ever superseded by a new row. compensation_amount is non-negative-constrained (taxonomy C-15).';

create index job_offer_versions_offer_idx on app.job_offer_versions (offer_id, version_number);

alter table app.job_offers add constraint job_offers_current_version_fk foreign key (current_version_id) references app.job_offer_versions (id);

-- ===========================================================================
-- 8. Helper functions.
-- ===========================================================================

-- Maps an actor's session auth_user_id -> their own linked employee master_record_id
-- (app.employees.user_id references app.users.id, NOT auth.users.id directly -- mirrors
-- app.get_my_employee_profile's own established two-hop resolution, HRT-274). Returns
-- null (never raises) when the actor has no linked employee profile in this tenant.
create function app.resolve_actor_employee_id(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select e.master_record_id
  from app.employees e
  join app.users u on u.id = e.user_id
  where u.auth_user_id = p_actor_auth_user_id and u.tenant_id = p_tenant_id and e.tenant_id = p_tenant_id
  limit 1;
$$;

comment on function app.resolve_actor_employee_id is 'HRT-276: the identity-match primitive app.submit_interview_feedback/app.get_my_assigned_interviews (design note 5) and hiring-manager display resolve against.';

-- Explicit non-pii jsonb projections for app.capture_audit_event (taxonomy C-07) --
-- never to_jsonb(row) for any table carrying a classified column.
create function app.candidate_audit_projection(p_candidate app.candidates)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_candidate.id, 'source', p_candidate.source, 'status', p_candidate.status,
    'consent_given', p_candidate.consent_given, 'record_version', p_candidate.record_version
  );
$$;

create function app.job_vacancy_audit_projection(p_vacancy app.job_vacancies)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_vacancy.id, 'position_id', p_vacancy.position_id, 'status', p_vacancy.status,
    'headcount', p_vacancy.headcount, 'record_version', p_vacancy.record_version
  );
$$;

create function app.job_application_audit_projection(p_application app.job_applications)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_application.id, 'vacancy_id', p_application.vacancy_id, 'candidate_id', p_application.candidate_id,
    'stage', p_application.stage, 'record_version', p_application.record_version
  );
$$;

create function app.job_offer_version_audit_projection(p_version app.job_offer_versions)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_version.id, 'offer_id', p_version.offer_id, 'version_number', p_version.version_number,
    'status', p_version.status, 'compensation_currency', p_version.compensation_currency
  );
$$;

-- Offer visibility: HRS:View, OR an actor currently eligible to decide the offer's
-- pending approval step, OR an actor who already recorded a decision on it (so an
-- approver can still review the evidence/history after deciding).
create function app.can_view_job_offer(p_offer app.job_offers, p_actor_auth_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_view_decision app.rbac_decision;
begin
  v_view_decision := app.evaluate_permission(p_actor_auth_user_id, p_offer.tenant_id, 'HRS', 'View');
  if v_view_decision.allowed then
    return true;
  end if;

  if p_offer.approval_request_id is null then
    return false;
  end if;

  if exists (
    select 1 from app.approval_request_steps s
    where s.request_id = p_offer.approval_request_id and s.status = 'active'
      and app.is_eligible_approval_approver(s, p_offer.tenant_id, p_actor_auth_user_id)
  ) then
    return true;
  end if;

  return exists (
    select 1 from app.approval_decisions d
    join app.approval_request_steps s on s.id = d.request_step_id
    where s.request_id = p_offer.approval_request_id and d.actor_auth_user_id = p_actor_auth_user_id
  );
end;
$$;

-- ===========================================================================
-- 9. Vacancy RPCs.
-- ===========================================================================

create function app.create_job_vacancy_draft(
  p_tenant_id uuid,
  p_position_id uuid,
  p_title text,
  p_employment_type text,
  p_headcount integer,
  p_description text,
  p_requirements text,
  p_hiring_manager_employee_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_vacancies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.job_vacancies;
  v_position app.positions;
  v_vacancy app.job_vacancies;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'invalid_title: title must not be empty' using errcode = 'check_violation';
  end if;
  if coalesce(p_headcount, 0) <= 0 then
    raise exception 'invalid_headcount: headcount must be positive' using errcode = 'check_violation';
  end if;

  select * into v_position from app.positions where id = p_position_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'position_not_found: %', p_position_id using errcode = 'no_data_found';
  end if;
  if v_position.status <> 'active' then
    raise exception 'position_inactive: position % is inactive and cannot receive a new vacancy', p_position_id using errcode = 'check_violation';
  end if;

  if p_hiring_manager_employee_id is not null and not exists (
    select 1 from app.employees where master_record_id = p_hiring_manager_employee_id and tenant_id = p_tenant_id
  ) then
    raise exception 'employee_not_found: hiring manager %', p_hiring_manager_employee_id using errcode = 'no_data_found';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.job_vacancies where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.title is distinct from p_title or v_existing.position_id is distinct from p_position_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vacancy', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.job_vacancies (
      tenant_id, position_id, title, employment_type, headcount, description, requirements,
      hiring_manager_employee_id, owner_auth_user_id, idempotency_key, created_by
    ) values (
      p_tenant_id, p_position_id, p_title, p_employment_type, p_headcount, p_description, p_requirements,
      p_hiring_manager_employee_id, p_actor_auth_user_id, p_idempotency_key, p_actor_label
    )
    returning * into v_vacancy;
  exception
    when unique_violation then
      select * into v_existing from app.job_vacancies where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.title is distinct from p_title or v_existing.position_id is distinct from p_position_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vacancy', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  insert into app.job_vacancy_lifecycle_events (tenant_id, vacancy_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_vacancy.id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_job_vacancy_draft',
    'app.job_vacancies', v_vacancy.id, 'success', null, null, app.job_vacancy_audit_projection(v_vacancy)
  );

  return v_vacancy;
end;
$$;

create function app.update_job_vacancy_draft(
  p_id uuid,
  p_expected_version integer,
  p_title text,
  p_employment_type text,
  p_headcount integer,
  p_description text,
  p_requirements text,
  p_hiring_manager_employee_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_vacancies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vacancy app.job_vacancies;
begin
  select * into v_vacancy from app.job_vacancies where id = p_id;
  if not found or not app.has_active_tenant_membership(v_vacancy.tenant_id, p_actor_auth_user_id) then
    raise exception 'vacancy_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vacancy.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vacancy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_vacancy.record_version <> p_expected_version then
    raise exception 'stale_version: vacancy % expected version % but found %', p_id, p_expected_version, v_vacancy.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_vacancy.status <> 'draft' then
    raise exception 'invalid_transition: vacancy % is % and only a draft may be edited this way', p_id, v_vacancy.status
      using errcode = 'check_violation';
  end if;
  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'invalid_title: title must not be empty' using errcode = 'check_violation';
  end if;
  if coalesce(p_headcount, 0) <= 0 then
    raise exception 'invalid_headcount: headcount must be positive' using errcode = 'check_violation';
  end if;
  if p_hiring_manager_employee_id is not null and not exists (
    select 1 from app.employees where master_record_id = p_hiring_manager_employee_id and tenant_id = v_vacancy.tenant_id
  ) then
    raise exception 'employee_not_found: hiring manager %', p_hiring_manager_employee_id using errcode = 'no_data_found';
  end if;

  update app.job_vacancies
  set title = p_title, employment_type = p_employment_type, headcount = p_headcount,
      description = p_description, requirements = p_requirements, hiring_manager_employee_id = p_hiring_manager_employee_id
  where id = p_id and record_version = p_expected_version
  returning * into v_vacancy;
  if not found then
    raise exception 'stale_version: vacancy % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_vacancy.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_job_vacancy_draft',
    'app.job_vacancies', v_vacancy.id, 'success', null, null, app.job_vacancy_audit_projection(v_vacancy)
  );

  return v_vacancy;
end;
$$;

-- draft -> open (HRS:Approve -- publishing commits real headcount against the
-- position AND opens the public intake surface, both consequential enough to require
-- the same authority level PRC-251 used for vendor activation). Creates the vacancy's
-- own public posting token, returned exactly once (never stored raw).
create function app.publish_job_vacancy(
  p_id uuid,
  p_expected_version integer,
  p_validity_days integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (vacancy app.job_vacancies, raw_posting_token text, posting_expires_at timestamptz)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vacancy app.job_vacancies;
  v_position app.positions;
  v_current_headcount integer;
  v_remaining integer;
  v_raw_token text;
  v_expires_at timestamptz;
begin
  select * into v_vacancy from app.job_vacancies where id = p_id;
  if not found or not app.has_active_tenant_membership(v_vacancy.tenant_id, p_actor_auth_user_id) then
    raise exception 'vacancy_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vacancy.tenant_id, 'HRS', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vacancy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_vacancy.record_version <> p_expected_version then
    raise exception 'stale_version: vacancy % expected version % but found %', p_id, p_expected_version, v_vacancy.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_vacancy.status <> 'draft' then
    raise exception 'invalid_transition: vacancy % is % and cannot be published', p_id, v_vacancy.status
      using errcode = 'check_violation';
  end if;
  if coalesce(p_validity_days, 0) <= 0 then
    raise exception 'invalid_validity: validity_days must be positive' using errcode = 'check_violation';
  end if;

  select * into v_position from app.positions where id = v_vacancy.position_id for update;
  if v_position.status <> 'active' then
    raise exception 'position_inactive: position % is inactive and cannot be published against', v_vacancy.position_id using errcode = 'check_violation';
  end if;
  v_current_headcount := app.count_position_active_primary_headcount(v_position.id, daterange(current_date, current_date, '[]'));
  v_remaining := v_position.capacity - v_current_headcount;
  if v_vacancy.headcount > v_remaining then
    raise exception 'vacancy_headcount_exceeds_position_capacity: vacancy % requests % but position % has only % seat(s) remaining (capacity %, current headcount %)',
      p_id, v_vacancy.headcount, v_position.id, v_remaining, v_position.capacity, v_current_headcount
      using errcode = 'check_violation';
  end if;

  update app.job_vacancies
  set status = 'open', status_reason = null
  where id = p_id and record_version = p_expected_version
  returning * into v_vacancy;
  if not found then
    raise exception 'stale_version: vacancy % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.job_vacancy_lifecycle_events (tenant_id, vacancy_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_vacancy.tenant_id, p_id, 'draft', 'open', p_actor_auth_user_id, p_actor_label);

  v_raw_token := encode(gen_random_bytes(32), 'hex');
  v_expires_at := now() + (p_validity_days || ' days')::interval;

  insert into app.job_vacancy_postings (tenant_id, vacancy_id, posting_token, expires_at)
  values (v_vacancy.tenant_id, p_id, v_raw_token, v_expires_at);

  perform app.capture_audit_event(
    v_vacancy.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_job_vacancy',
    'app.job_vacancies', v_vacancy.id, 'success', null, null, app.job_vacancy_audit_projection(v_vacancy)
  );

  return query select v_vacancy, v_raw_token, v_expires_at;
end;
$$;

comment on function app.publish_job_vacancy is 'HRT-276: raw_posting_token is also returned here for staff convenience (e.g. sharing the link directly), but it is NOT a one-time-only secret -- design note 2/app.job_vacancy_postings'' own comment: this token is meant to be freely re-discoverable via app.get_public_open_vacancy_summaries, unlike PRC-251''s single-use invite token.';

create function app.hold_job_vacancy(p_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_vacancies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vacancy app.job_vacancies;
begin
  select * into v_vacancy from app.job_vacancies where id = p_id;
  if not found or not app.has_active_tenant_membership(v_vacancy.tenant_id, p_actor_auth_user_id) then
    raise exception 'vacancy_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vacancy.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vacancy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_vacancy.record_version <> p_expected_version then
    raise exception 'stale_version: vacancy % expected version % but found %', p_id, p_expected_version, v_vacancy.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to place a vacancy on hold' using errcode = 'check_violation';
  end if;
  if v_vacancy.status <> 'open' then
    raise exception 'invalid_transition: vacancy % is % and cannot be placed on hold', p_id, v_vacancy.status
      using errcode = 'check_violation';
  end if;

  update app.job_vacancies set status = 'on_hold', status_reason = p_reason
  where id = p_id and record_version = p_expected_version
  returning * into v_vacancy;
  if not found then
    raise exception 'stale_version: vacancy % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.job_vacancy_lifecycle_events (tenant_id, vacancy_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_vacancy.tenant_id, p_id, 'open', 'on_hold', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_vacancy.tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_job_vacancy',
    'app.job_vacancies', v_vacancy.id, 'success', p_reason, null, app.job_vacancy_audit_projection(v_vacancy)
  );

  return v_vacancy;
end;
$$;

create function app.reopen_job_vacancy(p_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_vacancies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vacancy app.job_vacancies;
  v_active_posting_exists boolean;
begin
  select * into v_vacancy from app.job_vacancies where id = p_id;
  if not found or not app.has_active_tenant_membership(v_vacancy.tenant_id, p_actor_auth_user_id) then
    raise exception 'vacancy_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vacancy.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vacancy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_vacancy.record_version <> p_expected_version then
    raise exception 'stale_version: vacancy % expected version % but found %', p_id, p_expected_version, v_vacancy.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_vacancy.status <> 'on_hold' then
    raise exception 'invalid_transition: vacancy % is % and cannot be reopened', p_id, v_vacancy.status
      using errcode = 'check_violation';
  end if;

  select exists (
    select 1 from app.job_vacancy_postings where vacancy_id = p_id and status = 'active' and expires_at > now()
  ) into v_active_posting_exists;
  if not v_active_posting_exists then
    raise exception 'posting_expired: vacancy % has no unexpired public posting -- publish a new one instead of reopening', p_id
      using errcode = 'check_violation';
  end if;

  update app.job_vacancies set status = 'open', status_reason = null
  where id = p_id and record_version = p_expected_version
  returning * into v_vacancy;
  if not found then
    raise exception 'stale_version: vacancy % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.job_vacancy_lifecycle_events (tenant_id, vacancy_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_vacancy.tenant_id, p_id, 'on_hold', 'open', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_vacancy.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_job_vacancy',
    'app.job_vacancies', v_vacancy.id, 'success', null, null, app.job_vacancy_audit_projection(v_vacancy)
  );

  return v_vacancy;
end;
$$;

create function app.close_job_vacancy(p_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_vacancies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vacancy app.job_vacancies;
  v_from_status text;
begin
  select * into v_vacancy from app.job_vacancies where id = p_id;
  if not found or not app.has_active_tenant_membership(v_vacancy.tenant_id, p_actor_auth_user_id) then
    raise exception 'vacancy_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vacancy.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vacancy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_vacancy.record_version <> p_expected_version then
    raise exception 'stale_version: vacancy % expected version % but found %', p_id, p_expected_version, v_vacancy.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to close a vacancy' using errcode = 'check_violation';
  end if;
  if v_vacancy.status not in ('open', 'on_hold') then
    raise exception 'invalid_transition: vacancy % is % and cannot be closed', p_id, v_vacancy.status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_vacancy.status;

  update app.job_vacancies set status = 'closed', status_reason = p_reason
  where id = p_id and record_version = p_expected_version
  returning * into v_vacancy;
  if not found then
    raise exception 'stale_version: vacancy % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.job_vacancy_postings set status = 'revoked', revoked_at = now(), revoked_reason = p_reason, record_version = record_version + 1
  where vacancy_id = p_id and status = 'active';

  insert into app.job_vacancy_lifecycle_events (tenant_id, vacancy_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_vacancy.tenant_id, p_id, v_from_status, 'closed', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_vacancy.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_job_vacancy',
    'app.job_vacancies', v_vacancy.id, 'success', p_reason, null, app.job_vacancy_audit_projection(v_vacancy)
  );

  return v_vacancy;
end;
$$;

create function app.cancel_job_vacancy_draft(p_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_vacancies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vacancy app.job_vacancies;
begin
  select * into v_vacancy from app.job_vacancies where id = p_id;
  if not found or not app.has_active_tenant_membership(v_vacancy.tenant_id, p_actor_auth_user_id) then
    raise exception 'vacancy_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vacancy.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vacancy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_vacancy.record_version <> p_expected_version then
    raise exception 'stale_version: vacancy % expected version % but found %', p_id, p_expected_version, v_vacancy.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a vacancy draft' using errcode = 'check_violation';
  end if;
  if v_vacancy.status <> 'draft' then
    raise exception 'invalid_transition: vacancy % is % and cannot be cancelled (only a never-published draft may be)', p_id, v_vacancy.status
      using errcode = 'check_violation';
  end if;

  update app.job_vacancies set status = 'cancelled', status_reason = p_reason
  where id = p_id and record_version = p_expected_version
  returning * into v_vacancy;
  if not found then
    raise exception 'stale_version: vacancy % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.job_vacancy_lifecycle_events (tenant_id, vacancy_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_vacancy.tenant_id, p_id, 'draft', 'cancelled', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_vacancy.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_job_vacancy_draft',
    'app.job_vacancies', v_vacancy.id, 'success', p_reason, null, app.job_vacancy_audit_projection(v_vacancy)
  );

  return v_vacancy;
end;
$$;

-- ===========================================================================
-- 10. Candidate RPCs.
-- ===========================================================================

create function app.assert_candidate_draft_idempotent_replay(p_existing app.candidates, p_full_name text, p_email text, p_phone text, p_source text)
returns void
language plpgsql
as $$
begin
  if p_existing.full_name is distinct from p_full_name
     or lower(p_existing.email) is distinct from lower(p_email)
     or p_existing.phone is distinct from p_phone
     or p_existing.source is distinct from p_source
  then
    raise exception 'idempotency_key_conflict: idempotency key was already used for a different candidate' using errcode = 'unique_violation';
  end if;
end;
$$;

create function app.create_candidate(
  p_tenant_id uuid,
  p_full_name text,
  p_email text,
  p_phone text,
  p_source text,
  p_referral_employee_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.candidates;
  v_candidate app.candidates;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_full_name is null or length(trim(p_full_name)) = 0 then
    raise exception 'invalid_full_name: full_name must not be empty' using errcode = 'check_violation';
  end if;
  if p_email is null or p_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid_email: % is not a valid email address', p_email using errcode = 'check_violation';
  end if;
  if p_source not in ('staff_created', 'referral', 'agency', 'talent_pool', 'import') then
    raise exception 'invalid_source: % is not valid for staff-initiated candidate creation', p_source using errcode = 'check_violation';
  end if;
  if p_source = 'referral' and p_referral_employee_id is null then
    raise exception 'referral_employee_required: source=referral requires a referring employee' using errcode = 'check_violation';
  end if;
  if p_referral_employee_id is not null and not exists (select 1 from app.employees where master_record_id = p_referral_employee_id and tenant_id = p_tenant_id) then
    raise exception 'employee_not_found: referral employee %', p_referral_employee_id using errcode = 'no_data_found';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.candidates where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      perform app.assert_candidate_draft_idempotent_replay(v_existing, p_full_name, p_email, p_phone, p_source);
      return v_existing;
    end if;
  end if;

  begin
    insert into app.candidates (tenant_id, full_name, email, phone, source, referral_employee_id, idempotency_key, created_by)
    values (p_tenant_id, p_full_name, lower(p_email), p_phone, p_source, p_referral_employee_id, p_idempotency_key, p_actor_label)
    returning * into v_candidate;
  exception
    when unique_violation then
      select * into v_existing from app.candidates where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      perform app.assert_candidate_draft_idempotent_replay(v_existing, p_full_name, p_email, p_phone, p_source);
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_candidate',
    'app.candidates', v_candidate.id, 'success', null, null, app.candidate_audit_projection(v_candidate)
  );

  return v_candidate;
end;
$$;

create function app.update_candidate_profile(
  p_id uuid,
  p_expected_version integer,
  p_full_name text,
  p_phone text,
  p_national_id_number text,
  p_date_of_birth date,
  p_address text,
  p_resume_file_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_candidate app.candidates;
  v_file app.files;
begin
  select * into v_candidate from app.candidates where id = p_id;
  if not found or not app.has_active_tenant_membership(v_candidate.tenant_id, p_actor_auth_user_id) then
    raise exception 'candidate_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_candidate.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_candidate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_candidate.record_version <> p_expected_version then
    raise exception 'stale_version: candidate % expected version % but found %', p_id, p_expected_version, v_candidate.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_candidate.status = 'archived' then
    raise exception 'candidate_archived: candidate % is archived and cannot be edited', p_id using errcode = 'check_violation';
  end if;
  if p_full_name is null or length(trim(p_full_name)) = 0 then
    raise exception 'invalid_full_name: full_name must not be empty' using errcode = 'check_violation';
  end if;

  -- Taxonomy C-10: a file id is re-validated for tenant/record scope and scan status at
  -- the ACCEPTING RPC, never trusted from the caller (design note 3).
  if p_resume_file_id is not null then
    select * into v_file from app.files where id = p_resume_file_id;
    if not found or v_file.tenant_id <> v_candidate.tenant_id or v_file.record_type <> 'candidate' or v_file.record_id <> p_id then
      raise exception 'resume_file_not_found: file % is not a candidate document for candidate %', p_resume_file_id, p_id using errcode = 'no_data_found';
    end if;
    if v_file.malware_scan_status = 'infected' then
      raise exception 'resume_file_infected: file % failed malware scanning and cannot be attached', p_resume_file_id using errcode = 'check_violation';
    end if;
  end if;

  update app.candidates
  set full_name = p_full_name, phone = p_phone, national_id_number = p_national_id_number,
      date_of_birth = p_date_of_birth, address = p_address, resume_file_id = p_resume_file_id
  where id = p_id and record_version = p_expected_version
  returning * into v_candidate;
  if not found then
    raise exception 'stale_version: candidate % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_candidate.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_candidate_profile',
    'app.candidates', v_candidate.id, 'success', null, null, app.candidate_audit_projection(v_candidate)
  );

  return v_candidate;
end;
$$;

create function app.record_candidate_consent(
  p_id uuid,
  p_expected_version integer,
  p_consent_version text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_candidate app.candidates;
begin
  select * into v_candidate from app.candidates where id = p_id;
  if not found or not app.has_active_tenant_membership(v_candidate.tenant_id, p_actor_auth_user_id) then
    raise exception 'candidate_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_candidate.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_candidate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_candidate.record_version <> p_expected_version then
    raise exception 'stale_version: candidate % expected version % but found %', p_id, p_expected_version, v_candidate.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_consent_version is null or length(trim(p_consent_version)) = 0 then
    raise exception 'consent_version_required: a non-empty consent_version is required' using errcode = 'check_violation';
  end if;

  update app.candidates set consent_given = true, consent_given_at = now(), consent_version = p_consent_version
  where id = p_id and record_version = p_expected_version
  returning * into v_candidate;
  if not found then
    raise exception 'stale_version: candidate % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_candidate.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_candidate_consent',
    'app.candidates', v_candidate.id, 'success', null, null, app.candidate_audit_projection(v_candidate)
  );

  return v_candidate;
end;
$$;

create function app.set_candidate_status(
  p_id uuid,
  p_expected_version integer,
  p_new_status text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_candidate app.candidates;
begin
  select * into v_candidate from app.candidates where id = p_id;
  if not found or not app.has_active_tenant_membership(v_candidate.tenant_id, p_actor_auth_user_id) then
    raise exception 'candidate_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_candidate.tenant_id, 'HRS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_candidate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_candidate.record_version <> p_expected_version then
    raise exception 'stale_version: candidate % expected version % but found %', p_id, p_expected_version, v_candidate.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_new_status not in ('active', 'blocked', 'archived') then
    raise exception 'invalid_status: % is not a valid candidate status', p_new_status using errcode = 'check_violation';
  end if;
  if p_new_status in ('blocked', 'archived') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to % a candidate', p_new_status using errcode = 'check_violation';
  end if;
  if v_candidate.status = p_new_status then
    raise exception 'invalid_transition: candidate % is already %', p_id, p_new_status using errcode = 'check_violation';
  end if;

  update app.candidates
  set status = p_new_status, block_reason = case when p_new_status = 'blocked' then p_reason else null end
  where id = p_id and record_version = p_expected_version
  returning * into v_candidate;
  if not found then
    raise exception 'stale_version: candidate % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_candidate.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_candidate_status',
    'app.candidates', v_candidate.id, 'success', p_reason, null, app.candidate_audit_projection(v_candidate)
  );

  return v_candidate;
end;
$$;

create function app.flag_candidate_duplicate(p_source_candidate_id uuid, p_candidate_id uuid, p_similarity_basis text, p_similarity_score numeric, p_actor_auth_user_id uuid, p_actor_label text)
returns app.candidate_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_source app.candidates;
  v_candidate app.candidates;
  v_row app.candidate_duplicate_candidates;
begin
  select * into v_source from app.candidates where id = p_source_candidate_id;
  if not found or not app.has_active_tenant_membership(v_source.tenant_id, p_actor_auth_user_id) then
    raise exception 'candidate_not_found: %', p_source_candidate_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_candidate from app.candidates where id = p_candidate_id and tenant_id = v_source.tenant_id;
  if not found then
    raise exception 'candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;
  if p_source_candidate_id = p_candidate_id then
    raise exception 'invalid_duplicate_pair: a candidate cannot be flagged as its own duplicate' using errcode = 'check_violation';
  end if;
  if p_similarity_basis is null or length(trim(p_similarity_basis)) = 0 then
    raise exception 'similarity_basis_required: a non-empty similarity_basis is required' using errcode = 'check_violation';
  end if;

  insert into app.candidate_duplicate_candidates (tenant_id, source_candidate_id, candidate_id, similarity_basis, similarity_score, created_by)
  values (v_source.tenant_id, p_source_candidate_id, p_candidate_id, p_similarity_basis, p_similarity_score, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    v_source.tenant_id, p_actor_auth_user_id, p_actor_label, 'flag_candidate_duplicate',
    'app.candidate_duplicate_candidates', v_row.id, 'success', null, null, jsonb_build_object('source_candidate_id', p_source_candidate_id, 'candidate_id', p_candidate_id)
  );

  return v_row;
end;
$$;

create function app.decide_candidate_duplicate(p_id uuid, p_expected_version integer, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.candidate_duplicate_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rbac app.rbac_decision;
  v_row app.candidate_duplicate_candidates;
begin
  select * into v_row from app.candidate_duplicate_candidates where id = p_id;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'duplicate_candidate_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_rbac := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'HRS', 'Edit');
  if not v_rbac.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_rbac.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: duplicate candidate row % expected version % but found %', p_id, p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_decision not in ('linked', 'dismissed') then
    raise exception 'invalid_decision: % is not linked or dismissed', p_decision using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decide a duplicate candidate pairing' using errcode = 'check_violation';
  end if;
  if v_row.decision <> 'pending' then
    raise exception 'invalid_transition: duplicate candidate row % is already %', p_id, v_row.decision using errcode = 'check_violation';
  end if;

  update app.candidate_duplicate_candidates
  set decision = p_decision, decided_by = p_actor_label, decided_at = now(), decided_reason = p_reason, record_version = record_version + 1
  where id = p_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: duplicate candidate row % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_candidate_duplicate',
    'app.candidate_duplicate_candidates', v_row.id, 'success', p_reason, null, jsonb_build_object('decision', p_decision)
  );

  return v_row;
end;
$$;

comment on function app.decide_candidate_duplicate is 'HRT-276: records a human decision only -- never invokes a merge (design note 8/1). No candidate merge machinery exists in this repository.';

-- ===========================================================================
-- 11. Application RPCs.
-- ===========================================================================

create function app.apply_to_vacancy(
  p_vacancy_id uuid,
  p_candidate_id uuid,
  p_source text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_applications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vacancy app.job_vacancies;
  v_candidate app.candidates;
  v_existing app.job_applications;
  v_application app.job_applications;
begin
  -- Locked (taxonomy C-04): the decision to insert a new application is gated on
  -- v_vacancy.status='open', with no version re-check on the INSERT itself (unlike an
  -- UPDATE's own repeated-predicate pattern) -- lock the vacancy row for the duration
  -- of this decision so a concurrent close cannot race a new application into it.
  select * into v_vacancy from app.job_vacancies where id = p_vacancy_id for update;
  if not found or not app.has_active_tenant_membership(v_vacancy.tenant_id, p_actor_auth_user_id) then
    raise exception 'vacancy_not_found: %', p_vacancy_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vacancy.tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vacancy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_vacancy.status <> 'open' then
    raise exception 'vacancy_not_open: vacancy % is % and is not accepting applications', p_vacancy_id, v_vacancy.status using errcode = 'check_violation';
  end if;

  select * into v_candidate from app.candidates where id = p_candidate_id and tenant_id = v_vacancy.tenant_id;
  if not found then
    raise exception 'candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;
  if v_candidate.status <> 'active' then
    raise exception 'candidate_not_active: candidate % is % and cannot be applied to a vacancy', p_candidate_id, v_candidate.status using errcode = 'check_violation';
  end if;
  if p_source not in ('staff_created', 'referral', 'agency', 'talent_pool', 'import') then
    raise exception 'invalid_source: % is not valid for staff-initiated application creation', p_source using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.job_applications where tenant_id = v_vacancy.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vacancy_id is distinct from p_vacancy_id or v_existing.candidate_id is distinct from p_candidate_id then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different application', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.job_applications (tenant_id, vacancy_id, candidate_id, source, idempotency_key, created_by)
    values (v_vacancy.tenant_id, p_vacancy_id, p_candidate_id, p_source, p_idempotency_key, p_actor_label)
    returning * into v_application;
  exception
    when unique_violation then
      -- Two distinct unique constraints can raise here: the idempotency-key index
      -- (a genuine key-reuse-for-different-target replay) or the one-active-application
      -- partial index (a real duplicate application attempt, independent of any key).
      -- Disambiguate by re-deriving from live state rather than assuming which fired.
      if p_idempotency_key is not null then
        select * into v_existing from app.job_applications where tenant_id = v_vacancy.tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.vacancy_id is distinct from p_vacancy_id or v_existing.candidate_id is distinct from p_candidate_id then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different application', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      select * into v_existing from app.job_applications where vacancy_id = p_vacancy_id and candidate_id = p_candidate_id and stage not in ('rejected', 'withdrawn');
      if found then
        raise exception 'application_already_exists: candidate % already has an active application against vacancy %', p_candidate_id, p_vacancy_id
          using errcode = 'unique_violation';
      end if;
      raise;
  end;

  insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, actor_auth_user_id, actor_label)
  values (v_vacancy.tenant_id, v_application.id, 'none', 'new', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_vacancy.tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_to_vacancy',
    'app.job_applications', v_application.id, 'success', null, null, app.job_application_audit_projection(v_application)
  );

  return v_application;
end;
$$;

-- Bounded, forward-only rank order (design note 6). Never targets
-- rejected/withdrawn/offer_accepted -- each has its own dedicated RPC.
create function app.transition_application_stage(
  p_id uuid,
  p_expected_version integer,
  p_to_stage text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_applications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
  v_candidate app.candidates;
  v_resume app.files;
  v_from_rank integer;
  v_to_rank integer;
  v_from_stage text;
  v_completed_interview_count integer;
begin
  select * into v_application from app.job_applications where id = p_id;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_application.record_version <> p_expected_version then
    raise exception 'stale_version: application % expected version % but found %', p_id, p_expected_version, v_application.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_to_stage not in ('new', 'screening', 'assessment', 'interview', 'offer') then
    raise exception 'invalid_transition: % is not a valid forward-transition target', p_to_stage using errcode = 'check_violation';
  end if;

  v_from_rank := (case v_application.stage when 'new' then 1 when 'screening' then 2 when 'assessment' then 3 when 'interview' then 4 when 'offer' then 5 else 0 end);
  v_to_rank := (case p_to_stage when 'new' then 1 when 'screening' then 2 when 'assessment' then 3 when 'interview' then 4 when 'offer' then 5 end);
  if v_from_rank = 0 or v_to_rank <= v_from_rank then
    raise exception 'invalid_transition: application % is % and cannot move to % (forward-only)', p_id, v_application.stage, p_to_stage
      using errcode = 'check_violation';
  end if;
  v_from_stage := v_application.stage;

  select * into v_candidate from app.candidates where id = v_application.candidate_id for update;
  if not v_candidate.consent_given then
    raise exception 'consent_required: candidate % has not given consent -- the application cannot advance', v_candidate.id using errcode = 'check_violation';
  end if;

  if p_to_stage = 'interview' and v_candidate.resume_file_id is not null then
    select * into v_resume from app.files where id = v_candidate.resume_file_id;
    if found and v_resume.malware_scan_status <> 'clean' then
      raise exception 'resume_not_scanned: candidate %''s resume has not cleared malware scanning (status %)', v_candidate.id, v_resume.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  if p_to_stage = 'offer' then
    select count(*) into v_completed_interview_count
    from app.interviews i
    join app.interview_feedback f on f.interview_id = i.id
    where i.application_id = p_id and i.status = 'completed';
    if v_completed_interview_count = 0 then
      raise exception 'interview_feedback_required: application % has no completed interview with recorded feedback', p_id using errcode = 'check_violation';
    end if;
  end if;

  update app.job_applications set stage = p_to_stage, stage_since = now()
  where id = p_id and record_version = p_expected_version
  returning * into v_application;
  if not found then
    raise exception 'stale_version: application % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, actor_auth_user_id, actor_label)
  values (v_application.tenant_id, p_id, v_from_stage, p_to_stage, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_application.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_application_stage',
    'app.job_applications', v_application.id, 'success', null, null, app.job_application_audit_projection(v_application)
  );

  return v_application;
end;
$$;

create function app.reject_application(p_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_applications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
  v_from_stage text;
begin
  select * into v_application from app.job_applications where id = p_id;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'Reject');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Reject (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_application.record_version <> p_expected_version then
    raise exception 'stale_version: application % expected version % but found %', p_id, p_expected_version, v_application.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reject an application' using errcode = 'check_violation';
  end if;
  if v_application.stage in ('rejected', 'withdrawn', 'offer_accepted') then
    raise exception 'invalid_transition: application % is % and cannot be rejected', p_id, v_application.stage using errcode = 'check_violation';
  end if;
  v_from_stage := v_application.stage;

  update app.job_applications set stage = 'rejected', stage_since = now(), rejection_reason = p_reason
  where id = p_id and record_version = p_expected_version
  returning * into v_application;
  if not found then
    raise exception 'stale_version: application % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.job_offers set status = 'withdrawn' where application_id = p_id and status not in ('withdrawn', 'accepted', 'declined');

  insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, reason, actor_auth_user_id, actor_label)
  values (v_application.tenant_id, p_id, v_from_stage, 'rejected', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_application.tenant_id, p_actor_auth_user_id, p_actor_label, 'reject_application',
    'app.job_applications', v_application.id, 'success', p_reason, null, app.job_application_audit_projection(v_application)
  );

  return v_application;
end;
$$;

create function app.withdraw_application(p_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_applications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
  v_from_stage text;
begin
  select * into v_application from app.job_applications where id = p_id;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_application.record_version <> p_expected_version then
    raise exception 'stale_version: application % expected version % but found %', p_id, p_expected_version, v_application.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to withdraw an application' using errcode = 'check_violation';
  end if;
  if v_application.stage in ('rejected', 'withdrawn', 'offer_accepted') then
    raise exception 'invalid_transition: application % is % and cannot be withdrawn', p_id, v_application.stage using errcode = 'check_violation';
  end if;
  v_from_stage := v_application.stage;

  update app.job_applications set stage = 'withdrawn', stage_since = now(), withdrawal_reason = p_reason
  where id = p_id and record_version = p_expected_version
  returning * into v_application;
  if not found then
    raise exception 'stale_version: application % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.job_offers set status = 'withdrawn' where application_id = p_id and status not in ('withdrawn', 'accepted', 'declined');

  insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, reason, actor_auth_user_id, actor_label)
  values (v_application.tenant_id, p_id, v_from_stage, 'withdrawn', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_application.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_application',
    'app.job_applications', v_application.id, 'success', p_reason, null, app.job_application_audit_projection(v_application)
  );

  return v_application;
end;
$$;

-- ===========================================================================
-- 12. Assessment RPCs.
-- ===========================================================================

create function app.create_candidate_assessment(
  p_application_id uuid,
  p_assessment_type text,
  p_criteria_version text,
  p_max_score numeric,
  p_pass_threshold numeric,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.candidate_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
  v_row app.candidate_assessments;
begin
  -- Locked (taxonomy C-04): the decision to insert a new assessment is gated on
  -- v_application.stage, with no version re-check at INSERT time.
  select * into v_application from app.job_applications where id = p_application_id for update;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_application_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_application.stage in ('rejected', 'withdrawn') then
    raise exception 'invalid_application_stage: application % is % and cannot receive a new assessment', p_application_id, v_application.stage
      using errcode = 'check_violation';
  end if;
  if p_criteria_version is null or length(trim(p_criteria_version)) = 0 then
    raise exception 'criteria_version_required: a non-empty criteria_version is required' using errcode = 'check_violation';
  end if;
  if coalesce(p_max_score, 0) <= 0 then
    raise exception 'invalid_max_score: max_score must be positive' using errcode = 'check_violation';
  end if;
  if p_pass_threshold is not null and (p_pass_threshold < 0 or p_pass_threshold > p_max_score) then
    raise exception 'invalid_pass_threshold: pass_threshold must be between 0 and max_score' using errcode = 'check_violation';
  end if;

  insert into app.candidate_assessments (tenant_id, application_id, assessment_type, criteria_version, max_score, pass_threshold, assessor_auth_user_id, created_by)
  values (v_application.tenant_id, p_application_id, p_assessment_type, p_criteria_version, p_max_score, p_pass_threshold, p_actor_auth_user_id, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    v_application.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_candidate_assessment',
    'app.candidate_assessments', v_row.id, 'success', null, null, jsonb_build_object('application_id', p_application_id, 'assessment_type', p_assessment_type)
  );

  return v_row;
end;
$$;

create function app.record_assessment_result(p_id uuid, p_expected_version integer, p_score numeric, p_notes text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.candidate_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.candidate_assessments;
begin
  select * into v_row from app.candidate_assessments where id = p_id;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'assessment_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: assessment % expected version % but found %', p_id, p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status not in ('pending', 'in_progress') then
    raise exception 'invalid_transition: assessment % is % and cannot record a result', p_id, v_row.status using errcode = 'check_violation';
  end if;
  if p_score is null or p_score < 0 or p_score > v_row.max_score then
    raise exception 'invalid_score: score must be between 0 and % (max_score)', v_row.max_score using errcode = 'check_violation';
  end if;

  update app.candidate_assessments
  set score = p_score, notes = p_notes, status = 'completed', completed_at = now()
  where id = p_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: assessment % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_assessment_result',
    'app.candidate_assessments', v_row.id, 'success', null, null, jsonb_build_object('score', p_score, 'status', v_row.status)
  );

  return v_row;
end;
$$;

create function app.cancel_candidate_assessment(p_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.candidate_assessments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.candidate_assessments;
begin
  select * into v_row from app.candidate_assessments where id = p_id;
  if not found or not app.has_active_tenant_membership(v_row.tenant_id, p_actor_auth_user_id) then
    raise exception 'assessment_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: assessment % expected version % but found %', p_id, p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel an assessment' using errcode = 'check_violation';
  end if;
  if v_row.status not in ('pending', 'in_progress') then
    raise exception 'invalid_transition: assessment % is % and cannot be cancelled', p_id, v_row.status using errcode = 'check_violation';
  end if;

  update app.candidate_assessments set status = 'cancelled', notes = p_reason
  where id = p_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: assessment % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_candidate_assessment',
    'app.candidate_assessments', v_row.id, 'success', p_reason, null, jsonb_build_object('status', v_row.status)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- 13. Interview RPCs.
-- ===========================================================================

create function app.schedule_interview(
  p_application_id uuid,
  p_round integer,
  p_mode text,
  p_scheduled_at timestamptz,
  p_duration_minutes integer,
  p_location_or_link text,
  p_interviewer_employee_ids uuid[],
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.interviews
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
  v_interview app.interviews;
  v_employee_id uuid;
begin
  -- Locked (taxonomy C-04): the decision to schedule a new interview is gated on
  -- v_application.stage='interview', with no version re-check at INSERT time.
  select * into v_application from app.job_applications where id = p_application_id for update;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_application_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_application.stage <> 'interview' then
    raise exception 'invalid_application_stage: application % is % -- move it to the interview stage first', p_application_id, v_application.stage
      using errcode = 'check_violation';
  end if;
  if p_interviewer_employee_ids is null or array_length(p_interviewer_employee_ids, 1) is null then
    raise exception 'interviewers_required: at least one interviewer must be assigned' using errcode = 'check_violation';
  end if;

  insert into app.interviews (tenant_id, application_id, round, mode, scheduled_at, duration_minutes, location_or_link, created_by)
  values (v_application.tenant_id, p_application_id, coalesce(p_round, 1), p_mode, p_scheduled_at, p_duration_minutes, p_location_or_link, p_actor_label)
  returning * into v_interview;

  foreach v_employee_id in array p_interviewer_employee_ids loop
    if not exists (select 1 from app.employees where master_record_id = v_employee_id and tenant_id = v_application.tenant_id) then
      raise exception 'employee_not_found: interviewer %', v_employee_id using errcode = 'no_data_found';
    end if;
    insert into app.interview_interviewers (tenant_id, interview_id, employee_id, is_lead)
    values (v_application.tenant_id, v_interview.id, v_employee_id, v_employee_id = p_interviewer_employee_ids[1]);
  end loop;

  perform app.capture_audit_event(
    v_application.tenant_id, p_actor_auth_user_id, p_actor_label, 'schedule_interview',
    'app.interviews', v_interview.id, 'success', null, null, jsonb_build_object('application_id', p_application_id, 'round', v_interview.round)
  );

  return v_interview;
end;
$$;

create function app.reschedule_interview(
  p_id uuid,
  p_expected_version integer,
  p_scheduled_at timestamptz,
  p_duration_minutes integer,
  p_location_or_link text,
  p_mode text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.interviews
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_interview app.interviews;
begin
  select * into v_interview from app.interviews where id = p_id;
  if not found or not app.has_active_tenant_membership(v_interview.tenant_id, p_actor_auth_user_id) then
    raise exception 'interview_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_interview.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_interview.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_interview.record_version <> p_expected_version then
    raise exception 'stale_version: interview % expected version % but found %', p_id, p_expected_version, v_interview.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_interview.status <> 'scheduled' then
    raise exception 'invalid_transition: interview % is % and cannot be rescheduled', p_id, v_interview.status using errcode = 'check_violation';
  end if;

  update app.interviews set scheduled_at = p_scheduled_at, duration_minutes = p_duration_minutes, location_or_link = p_location_or_link, mode = p_mode
  where id = p_id and record_version = p_expected_version
  returning * into v_interview;
  if not found then
    raise exception 'stale_version: interview % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_interview.tenant_id, p_actor_auth_user_id, p_actor_label, 'reschedule_interview',
    'app.interviews', v_interview.id, 'success', null, null, jsonb_build_object('scheduled_at', v_interview.scheduled_at)
  );

  return v_interview;
end;
$$;

create function app.cancel_interview(p_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.interviews
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_interview app.interviews;
begin
  select * into v_interview from app.interviews where id = p_id;
  if not found or not app.has_active_tenant_membership(v_interview.tenant_id, p_actor_auth_user_id) then
    raise exception 'interview_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_interview.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_interview.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_interview.record_version <> p_expected_version then
    raise exception 'stale_version: interview % expected version % but found %', p_id, p_expected_version, v_interview.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel an interview' using errcode = 'check_violation';
  end if;
  if v_interview.status <> 'scheduled' then
    raise exception 'invalid_transition: interview % is % and cannot be cancelled', p_id, v_interview.status using errcode = 'check_violation';
  end if;

  update app.interviews set status = 'cancelled', cancel_reason = p_reason
  where id = p_id and record_version = p_expected_version
  returning * into v_interview;
  if not found then
    raise exception 'stale_version: interview % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_interview.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_interview',
    'app.interviews', v_interview.id, 'success', p_reason, null, jsonb_build_object('status', v_interview.status)
  );

  return v_interview;
end;
$$;

create function app.complete_interview(p_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.interviews
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_interview app.interviews;
begin
  select * into v_interview from app.interviews where id = p_id;
  if not found or not app.has_active_tenant_membership(v_interview.tenant_id, p_actor_auth_user_id) then
    raise exception 'interview_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_interview.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_interview.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_interview.record_version <> p_expected_version then
    raise exception 'stale_version: interview % expected version % but found %', p_id, p_expected_version, v_interview.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_interview.status <> 'scheduled' then
    raise exception 'invalid_transition: interview % is % and cannot be completed', p_id, v_interview.status using errcode = 'check_violation';
  end if;

  update app.interviews set status = 'completed'
  where id = p_id and record_version = p_expected_version
  returning * into v_interview;
  if not found then
    raise exception 'stale_version: interview % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_interview.tenant_id, p_actor_auth_user_id, p_actor_label, 'complete_interview',
    'app.interviews', v_interview.id, 'success', null, null, jsonb_build_object('status', v_interview.status)
  );

  return v_interview;
end;
$$;

-- Identity-gated (design note 5) -- the caller's own linked employee must be an
-- assigned interviewer for THIS interview. Deliberately does NOT route through
-- app.evaluate_permission at all -- a plain interviewer with zero HRS permissions must
-- still be able to submit their own scorecard.
create function app.submit_interview_feedback(
  p_interview_id uuid,
  p_rating integer,
  p_recommendation text,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.interview_feedback
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_interview app.interviews;
  v_employee_id uuid;
  v_row app.interview_feedback;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Folds a non-member caller into the SAME interview_not_found a genuinely missing
  -- row would produce (never discloses that a real interview exists in a tenant the
  -- caller has no membership in) -- also closes rbac-enforcement.sql's own
  -- ISS-2026-033 call-graph gate (a real, explicit tenant-membership check, not merely
  -- a defense-in-depth restatement).
  select * into v_interview from app.interviews where id = p_interview_id;
  if not found or not app.has_active_tenant_membership(v_interview.tenant_id, p_actor_auth_user_id) then
    raise exception 'interview_not_found: %', p_interview_id using errcode = 'no_data_found';
  end if;

  v_employee_id := app.resolve_actor_employee_id(v_interview.tenant_id, p_actor_auth_user_id);
  if v_employee_id is null or not exists (
    select 1 from app.interview_interviewers where interview_id = p_interview_id and employee_id = v_employee_id
  ) then
    raise exception 'not_assigned_interviewer: identity % is not an assigned interviewer for interview %', p_actor_auth_user_id, p_interview_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_interview.status not in ('scheduled', 'completed') then
    raise exception 'invalid_interview_status: interview % is % and cannot receive feedback', p_interview_id, v_interview.status using errcode = 'check_violation';
  end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'invalid_rating: rating must be between 1 and 5' using errcode = 'check_violation';
  end if;
  if p_recommendation not in ('strong_yes', 'yes', 'no', 'strong_no') then
    raise exception 'invalid_recommendation: % is not a valid recommendation', p_recommendation using errcode = 'check_violation';
  end if;

  begin
    insert into app.interview_feedback (tenant_id, interview_id, interviewer_employee_id, rating, recommendation, notes)
    values (v_interview.tenant_id, p_interview_id, v_employee_id, p_rating, p_recommendation, p_notes)
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'feedback_already_submitted: identity % has already submitted feedback for interview %', p_actor_auth_user_id, p_interview_id
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_interview.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_interview_feedback',
    'app.interview_feedback', v_row.id, 'success', null, null, jsonb_build_object('interview_id', p_interview_id, 'recommendation', p_recommendation)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- 14. Offer RPCs (design note 4).
-- ===========================================================================

create function app.create_job_offer_version(
  p_application_id uuid,
  p_compensation_amount numeric,
  p_compensation_currency text,
  p_effective_date date,
  p_expiry_date date,
  p_title text,
  p_employment_type text,
  p_benefits_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_offer_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
  v_offer app.job_offers;
  v_next_version integer;
  v_row app.job_offer_versions;
begin
  -- Locked (taxonomy C-04): the decision to create a new offer version is gated on
  -- v_application.stage='offer', with no version re-check at INSERT time.
  select * into v_application from app.job_applications where id = p_application_id for update;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_application_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_application.stage <> 'offer' then
    raise exception 'invalid_application_stage: application % is % -- move it to the offer stage first', p_application_id, v_application.stage
      using errcode = 'check_violation';
  end if;
  if coalesce(p_compensation_amount, -1) < 0 then
    raise exception 'invalid_compensation_amount: compensation_amount must not be negative' using errcode = 'check_violation';
  end if;
  if p_compensation_currency is null or length(trim(p_compensation_currency)) = 0 then
    raise exception 'invalid_currency: compensation_currency must not be empty' using errcode = 'check_violation';
  end if;
  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'invalid_title: title must not be empty' using errcode = 'check_violation';
  end if;
  if p_expiry_date is not null and p_expiry_date < p_effective_date then
    raise exception 'invalid_expiry_date: expiry_date must not precede effective_date' using errcode = 'check_violation';
  end if;

  select * into v_offer from app.job_offers where application_id = p_application_id for update;
  if not found then
    insert into app.job_offers (tenant_id, application_id, created_by)
    values (v_application.tenant_id, p_application_id, p_actor_label)
    returning * into v_offer;
  end if;

  -- Only draft/approved/declined offers may receive a new version -- pending_approval
  -- (a decision is actively in flight; use app.decide_job_offer_approval or wait) and
  -- extended/accepted/withdrawn (already in the candidate's hands or closed) are not
  -- revisable through this RPC.
  if v_offer.status not in ('draft', 'approved', 'declined') then
    raise exception 'invalid_transition: offer % is % and cannot receive a new version', v_offer.id, v_offer.status using errcode = 'check_violation';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.job_offer_versions where offer_id = v_offer.id;

  insert into app.job_offer_versions (tenant_id, offer_id, version_number, compensation_amount, compensation_currency, effective_date, expiry_date, title, employment_type, benefits_note, created_by)
  values (v_application.tenant_id, v_offer.id, v_next_version, p_compensation_amount, p_compensation_currency, p_effective_date, p_expiry_date, p_title, p_employment_type, p_benefits_note, p_actor_label)
  returning * into v_row;

  -- A materially new version always resets approval/status -- a stale approval
  -- decision must never be read as covering different terms (design note 4).
  update app.job_offer_versions set status = 'superseded' where offer_id = v_offer.id and id <> v_row.id and status = 'draft';
  update app.job_offers
  set current_version_id = v_row.id, status = 'draft', approval_status = 'not_required', approval_request_id = null
  where id = v_offer.id;

  perform app.capture_audit_event(
    v_application.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_job_offer_version',
    'app.job_offer_versions', v_row.id, 'success', null, null, app.job_offer_version_audit_projection(v_row)
  );

  return v_row;
end;
$$;

comment on function app.create_job_offer_version is 'HRT-276: creates the job_offers row on first call, or a new version on any subsequent call. A new version always resets approval_status/status to not_required/draft (design note 4) -- an approval decision on version N never silently covers version N+1''s different terms.';

create function app.submit_job_offer_for_approval(p_offer_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_offers
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.job_offers;
  v_approval_config_version_id uuid;
  v_request app.approval_requests;
begin
  select * into v_offer from app.job_offers where id = p_offer_id;
  if not found or not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: offer % expected version % but found %', p_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_offer.status <> 'draft' or v_offer.current_version_id is null then
    raise exception 'invalid_transition: offer % is % and cannot be submitted for approval (needs at least one version)', p_offer_id, v_offer.status
      using errcode = 'check_violation';
  end if;

  select cv.id into v_approval_config_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = 'approval' and co.tenant_id = v_offer.tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

  if v_approval_config_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % has no published offer approval routing definition', v_offer.tenant_id
      using errcode = 'check_violation';
  end if;

  select * into v_request from app.request_approval(
    v_approval_config_version_id, v_offer.tenant_id, 'job_offer', p_offer_id,
    p_offer_id::text || ':' || v_offer.current_version_id::text, p_actor_auth_user_id, p_actor_label
  );

  update app.job_offers
  set status = 'pending_approval', approval_status = 'pending', approval_request_id = v_request.id
  where id = p_offer_id and record_version = p_expected_version
  returning * into v_offer;
  if not found then
    raise exception 'stale_version: offer % target row was concurrently modified (expected version %)', p_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.job_offer_versions set status = 'submitted' where id = v_offer.current_version_id;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_job_offer_for_approval',
    'app.job_offers', v_offer.id, 'success', null, null, jsonb_build_object('status', v_offer.status, 'approval_request_id', v_offer.approval_request_id)
  );

  return v_offer;
end;
$$;

comment on function app.submit_job_offer_for_approval is 'HRT-276: EVERY offer requires approval, unconditionally (design note 4) -- no threshold bypass exists. Fails closed (approval_definition_not_configured) if the tenant has no published approval routing, exactly like app.submit_quotation (COM-153).';

-- The one domain-specific sync wrapper over the Approval Engine (mirrors
-- app.decide_quotation_approval_step, COM-153) -- the engine itself cannot write back
-- to app.job_offers, being entity-agnostic.
create function app.decide_job_offer_approval(p_request_step_id uuid, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_offer app.job_offers;
begin
  -- app.decide_approval_step (PLT-123) itself never calls assert_actor_is_session_identity
  -- -- every domain sync wrapper over it adds this explicitly (mirrors app.decide_
  -- quotation_approval_step, COM-153, byte-for-byte).
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id using errcode = 'no_data_found';
  end if;

  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'job_offer' or v_request.entity_id is null then
    raise exception 'not_a_job_offer_approval: approval request % is not a job offer approval', v_request.id using errcode = 'check_violation';
  end if;

  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  if v_updated_request.status = 'approved' then
    update app.job_offers set status = 'approved', approval_status = 'approved'
    where id = v_request.entity_id
    returning * into v_offer;
  elsif v_updated_request.status = 'rejected' then
    update app.job_offers set status = 'draft', approval_status = 'rejected'
    where id = v_request.entity_id
    returning * into v_offer;
  else
    select * into v_offer from app.job_offers where id = v_request.entity_id;
  end if;

  return v_offer;
end;
$$;

comment on function app.decide_job_offer_approval is 'HRT-276: no domain permission gate of its own -- app.decide_approval_step already gates on tenant membership + eligible-approver identity (mirrors app.decide_quotation_approval_step exactly). A rejected offer returns to draft, letting the recruiter revise via app.create_job_offer_version and resubmit.';

create function app.extend_job_offer(p_offer_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.job_offers;
begin
  select * into v_offer from app.job_offers where id = p_offer_id;
  if not found or not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: offer % expected version % but found %', p_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_offer.status <> 'approved' or v_offer.approval_status not in ('approved') then
    raise exception 'invalid_transition: offer % is % (approval_status %) and cannot be extended', p_offer_id, v_offer.status, v_offer.approval_status
      using errcode = 'check_violation';
  end if;

  update app.job_offers set status = 'extended'
  where id = p_offer_id and record_version = p_expected_version
  returning * into v_offer;
  if not found then
    raise exception 'stale_version: offer % target row was concurrently modified (expected version %)', p_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'extend_job_offer',
    'app.job_offers', v_offer.id, 'success', null, null, jsonb_build_object('status', v_offer.status)
  );

  return v_offer;
end;
$$;

create function app.record_offer_response(p_offer_id uuid, p_expected_version integer, p_response text, p_response_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_offer app.job_offers;
  v_application app.job_applications;
begin
  select * into v_offer from app.job_offers where id = p_offer_id;
  if not found or not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: offer % expected version % but found %', p_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_response not in ('accepted', 'declined') then
    raise exception 'invalid_response: % is not accepted or declined', p_response using errcode = 'check_violation';
  end if;
  if v_offer.status <> 'extended' then
    raise exception 'invalid_transition: offer % is % and has no candidate response to record', p_offer_id, v_offer.status
      using errcode = 'check_violation';
  end if;

  select * into v_application from app.job_applications where id = v_offer.application_id for update;

  update app.job_offers set status = case p_response when 'accepted' then 'accepted' else 'declined' end
  where id = p_offer_id and record_version = p_expected_version
  returning * into v_offer;
  if not found then
    raise exception 'stale_version: offer % target row was concurrently modified (expected version %)', p_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  if p_response = 'accepted' then
    update app.job_applications set stage = 'offer_accepted', stage_since = now()
    where id = v_application.id and record_version = v_application.record_version;
    insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, reason, actor_auth_user_id, actor_label)
    values (v_application.tenant_id, v_application.id, v_application.stage, 'offer_accepted', p_response_note, p_actor_auth_user_id, p_actor_label);
  else
    update app.job_applications set stage = 'rejected', stage_since = now(), rejection_reason = coalesce(p_response_note, 'offer_declined')
    where id = v_application.id and record_version = v_application.record_version;
    insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, reason, actor_auth_user_id, actor_label)
    values (v_application.tenant_id, v_application.id, v_application.stage, 'rejected', coalesce(p_response_note, 'offer_declined'), p_actor_auth_user_id, p_actor_label);
  end if;

  perform app.capture_audit_event(
    v_offer.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_offer_response',
    'app.job_offers', v_offer.id, 'success', p_response_note, null, jsonb_build_object('status', v_offer.status)
  );

  return v_offer;
end;
$$;

comment on function app.record_offer_response is 'HRT-276: records the candidate''s response (recorded by staff -- a candidate has no session, ADR-0023 Part B). accepted -> application.stage=offer_accepted, the terminal success state awaiting Prompt 277''s own governed onboarding conversion; this function creates neither an app.employees nor an app.users row.';

-- ===========================================================================
-- 15. Public intake RPCs (design note 2) -- no actor, no session. Neither calls
--     app.evaluate_permission: there is no session identity to evaluate.
-- ===========================================================================

-- The real, callable listing RPC -- returns only genuinely public fields for OPEN
-- vacancies of an ACTIVE tenant, keyed by posting token (never the internal vacancy id,
-- per design note 2). Uniformly empty for a bad slug, an inactive tenant, or a tenant
-- with zero open vacancies -- these three cases are indistinguishable to the caller.
create function app.get_public_open_vacancy_summaries(p_tenant_slug text)
returns table (posting_token text, title text, employment_type text, org_unit_name text, headcount integer, published_at timestamptz)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  select id into v_tenant_id from app.tenants where slug = p_tenant_slug and canonical_status = 'active';
  if v_tenant_id is null then
    return;
  end if;

  return query
  select p.posting_token, v.title, v.employment_type, ou.name, v.headcount, p.published_at
  from app.job_vacancy_postings p
  join app.job_vacancies v on v.id = p.vacancy_id
  join app.positions pos on pos.id = v.position_id
  join app.org_units ou on ou.id = pos.org_unit_id
  where v.tenant_id = v_tenant_id and v.status = 'open' and p.status = 'active' and p.expires_at > now()
  order by p.published_at desc;
end;
$$;

comment on function app.get_public_open_vacancy_summaries is
  'HRT-276: a genuine public careers-page listing -- every column here (title/employment_type/org_unit_name/headcount) is information a real careers site already displays. See app.resolve_public_job_posting for the fuller per-posting detail (description/requirements) and app.submit_public_job_application for the actual submission path.';

-- Resolves a posting token (from the candidate''s own URL, either clicked from the
-- listing above or shared directly) to public vacancy detail. Every failure mode (bad
-- token, expired, revoked, vacancy no longer open) returns the SAME empty result --
-- never distinguished, mirroring app.resolve_vendor_self_registration_target''s uniform
-- not-found collapse -- so this cannot be used to enumerate a DRAFT/CLOSED vacancy''s
-- existence or a different tenant''s data.
create function app.resolve_public_job_posting(p_posting_token text, p_client_key text)
returns table (vacancy_id uuid, title text, employment_type text, description text, requirements text, org_unit_name text, headcount integer)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_recent_bad_count integer;
  v_posting app.job_vacancy_postings;
  v_vacancy app.job_vacancies;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'intake_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent_bad_count
  from app.job_application_intake_attempts
  where client_key = p_client_key and kind = 'view_posting' and result = 'not_found' and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 20 then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'view_posting', 'rate_limited');
    return;
  end if;

  if p_posting_token is null or length(p_posting_token) = 0 then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'view_posting', 'invalid');
    return;
  end if;

  select * into v_posting from app.job_vacancy_postings where posting_token = p_posting_token;
  if not found or v_posting.status <> 'active' or v_posting.expires_at <= now() then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'view_posting', 'not_found');
    return;
  end if;

  select * into v_vacancy from app.job_vacancies where id = v_posting.vacancy_id;
  if not found or v_vacancy.status <> 'open' then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'view_posting', 'not_found');
    return;
  end if;

  if not exists (select 1 from app.tenants where id = v_vacancy.tenant_id and canonical_status = 'active') then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'view_posting', 'not_found');
    return;
  end if;

  insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'view_posting', 'success');

  return query
  select v_vacancy.id, v_vacancy.title, v_vacancy.employment_type, v_vacancy.description, v_vacancy.requirements, ou.name, v_vacancy.headcount
  from app.positions pos
  join app.org_units ou on ou.id = pos.org_unit_id
  where pos.id = v_vacancy.position_id;
end;
$$;

comment on function app.resolve_public_job_posting is 'HRT-276: genuinely anonymous -- reads only its own posting/vacancy/position/org_unit rows (all already-public-by-definition once a vacancy is open), never any candidate or other-tenant data (mirrors app.resolve_vendor_self_registration_target, PRC-251).';

-- Genuinely anonymous submission. Never raises after the rate-limit check passes
-- (design note 2), so the attempts-log insert always survives to commit. Consent is
-- mandatory -- a submission without explicit, positive consent is rejected as invalid,
-- never silently accepted with consent_given=false.
create function app.submit_public_job_application(
  p_posting_token text,
  p_client_key text,
  p_full_name text,
  p_email text,
  p_phone text,
  p_consent_given boolean,
  p_consent_version text,
  p_idempotency_key text
)
returns table (submit_status text, application_id uuid)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_recent_bad_count integer;
  v_posting app.job_vacancy_postings;
  v_vacancy app.job_vacancies;
  v_existing_application app.job_applications;
  v_candidate app.candidates;
  v_application app.job_applications;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'intake_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent_bad_count
  from app.job_application_intake_attempts
  where client_key = p_client_key and kind = 'submit_application' and result in ('not_found', 'invalid') and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 10 then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'rate_limited');
    return query select 'rate_limited'::text, null::uuid;
    return;
  end if;

  if p_posting_token is null or length(p_posting_token) = 0
     or p_full_name is null or length(trim(p_full_name)) = 0
     or p_email is null or p_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
     or coalesce(p_consent_given, false) = false
     or p_consent_version is null or length(trim(p_consent_version)) = 0
  then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'invalid');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  select * into v_posting from app.job_vacancy_postings where posting_token = p_posting_token for update;
  if not found or v_posting.status <> 'active' or v_posting.expires_at <= now() then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'not_found');
    return query select 'not_found'::text, null::uuid;
    return;
  end if;

  select * into v_vacancy from app.job_vacancies where id = v_posting.vacancy_id for update;
  if not found or v_vacancy.status <> 'open' then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'not_found');
    return query select 'not_found'::text, null::uuid;
    return;
  end if;

  if not exists (select 1 from app.tenants where id = v_vacancy.tenant_id and canonical_status = 'active') then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'not_found');
    return query select 'not_found'::text, null::uuid;
    return;
  end if;

  -- Idempotent replay, keyed by the caller-supplied idempotency key (a public token is
  -- multi-use, unlike PRC-251's single-use invite -- replay cannot be keyed by the
  -- token itself here).
  if p_idempotency_key is not null then
    select * into v_existing_application from app.job_applications where tenant_id = v_vacancy.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      select * into v_candidate from app.candidates where id = v_existing_application.candidate_id;
      if found and lower(v_candidate.email) = lower(p_email) then
        insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'success');
        return query select 'ok'::text, v_existing_application.id;
        return;
      end if;
      insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'conflict');
      return query select 'conflict'::text, null::uuid;
      return;
    end if;
  end if;

  select * into v_candidate from app.candidates where tenant_id = v_vacancy.tenant_id and lower(email) = lower(p_email);
  if not found then
    insert into app.candidates (tenant_id, full_name, email, phone, source, consent_given, consent_given_at, consent_version, created_by)
    values (v_vacancy.tenant_id, p_full_name, lower(p_email), p_phone, 'public_application', true, now(), p_consent_version, 'public_job_application')
    returning * into v_candidate;
  elsif not v_candidate.consent_given then
    update app.candidates set consent_given = true, consent_given_at = now(), consent_version = p_consent_version
    where id = v_candidate.id
    returning * into v_candidate;
  end if;

  if v_candidate.status <> 'active' then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'conflict');
    return query select 'conflict'::text, null::uuid;
    return;
  end if;

  begin
    insert into app.job_applications (tenant_id, vacancy_id, candidate_id, source, idempotency_key, created_by)
    values (v_vacancy.tenant_id, v_vacancy.id, v_candidate.id, 'public_application', p_idempotency_key, 'public_job_application')
    returning * into v_application;
  exception
    when unique_violation then
      select * into v_existing_application from app.job_applications where vacancy_id = v_vacancy.id and candidate_id = v_candidate.id and stage not in ('rejected', 'withdrawn');
      if found then
        insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'success');
        return query select 'ok'::text, v_existing_application.id;
        return;
      end if;
      insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'conflict');
      return query select 'conflict'::text, null::uuid;
      return;
  end;

  insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, actor_label)
  values (v_vacancy.tenant_id, v_application.id, 'none', 'new', 'public_job_application');

  insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'success');

  perform app.capture_audit_event(
    v_vacancy.tenant_id, null, 'public_job_application', 'submit_public_job_application',
    'app.job_applications', v_application.id, 'success', null, null, jsonb_build_object('source', 'public_application')
  );

  return query select 'ok'::text, v_application.id;
end;
$$;

comment on function app.submit_public_job_application is 'HRT-276: genuinely anonymous -- no actor parameter, no evaluate_permission call. The raw posting token bound to an OPEN vacancy is the entire authorization surface. Reads/writes only its own candidate/application rows -- never any other tenant/candidate data (section 16). Never raises after the rate-limit check passes.';

-- ===========================================================================
-- 16. Read RPCs.
-- ===========================================================================

create function app.list_job_vacancies(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status_filter text default null,
  p_search text default null,
  p_limit integer default 50,
  p_after_id uuid default null
)
returns setof app.job_vacancies
language plpgsql
stable
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
  select v.* from app.job_vacancies v
  where v.tenant_id = p_tenant_id
    and (p_status_filter is null or v.status = p_status_filter)
    and (p_search is null or v.title ilike '%' || p_search || '%')
    and (p_after_id is null or v.id > p_after_id)
  order by v.id
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create function app.get_job_vacancy(p_id uuid, p_actor_auth_user_id uuid)
returns table (vacancy app.job_vacancies, active_posting_expires_at timestamptz, current_open_headcount integer)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vacancy app.job_vacancies;
begin
  select * into v_vacancy from app.job_vacancies where id = p_id;
  if not found or not app.has_active_tenant_membership(v_vacancy.tenant_id, p_actor_auth_user_id) then
    raise exception 'vacancy_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vacancy.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vacancy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select v_vacancy, p.expires_at,
    (select count(*)::integer from app.job_applications a where a.vacancy_id = p_id and a.stage not in ('rejected', 'withdrawn'))
  from (select 1) one
  left join app.job_vacancy_postings p on p.vacancy_id = p_id and p.status = 'active'
  limit 1;
end;
$$;

create function app.export_job_vacancies(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 500)
returns table (id uuid, title text, employment_type text, headcount integer, status text)
language plpgsql
stable
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
  select v.id, v.title, v.employment_type, v.headcount, v.status
  from app.job_vacancies v
  where v.tenant_id = p_tenant_id and (p_status_filter is null or v.status = p_status_filter)
  order by v.created_at desc
  limit least(coalesce(p_limit, 500), 5000);
end;
$$;

create function app.get_candidate_profile(p_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, full_name text, email text, phone text, national_id_number text, date_of_birth date, address text,
  resume_file_id uuid, source text, status text, consent_given boolean, consent_given_at timestamptz, consent_version text,
  personal_data_masked boolean, record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_candidate app.candidates;
  v_can_view_pii boolean;
begin
  -- Table-aliased and explicitly qualified (c.id): a bare `id` here is genuinely
  -- ambiguous against this function's own RETURNS TABLE column of the identical name
  -- (the exact class HRT-274's own build log found and fixed three times).
  select c.* into v_candidate from app.candidates c where c.id = p_id;
  if not found or not app.has_active_tenant_membership(v_candidate.tenant_id, p_actor_auth_user_id) then
    raise exception 'candidate_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_candidate.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_candidate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_can_view_pii := app.has_view_personal_data(v_candidate.tenant_id, p_actor_auth_user_id);

  return query
  select
    v_candidate.id, v_candidate.tenant_id, v_candidate.full_name,
    case when v_can_view_pii then v_candidate.email else null end,
    case when v_can_view_pii then v_candidate.phone else null end,
    case when v_can_view_pii then v_candidate.national_id_number else null end,
    case when v_can_view_pii then v_candidate.date_of_birth else null end,
    case when v_can_view_pii then v_candidate.address else null end,
    v_candidate.resume_file_id, v_candidate.source, v_candidate.status,
    v_candidate.consent_given, v_candidate.consent_given_at, v_candidate.consent_version,
    not v_can_view_pii, v_candidate.record_version, v_candidate.created_at, v_candidate.updated_at;
end;
$$;

comment on function app.get_candidate_profile is 'HRT-276: personal_data_masked is computed server-side (never a client-side guess), gated by app.has_view_personal_data (design note 9).';

create function app.list_candidates(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status_filter text default null,
  p_search text default null,
  p_limit integer default 50,
  p_after_id uuid default null
)
returns table (id uuid, full_name text, source text, status text, consent_given boolean, created_at timestamptz)
language plpgsql
stable
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
  select c.id, c.full_name, c.source, c.status, c.consent_given, c.created_at
  from app.candidates c
  where c.tenant_id = p_tenant_id
    and (p_status_filter is null or c.status = p_status_filter)
    and (p_search is null or c.full_name ilike '%' || p_search || '%')
    and (p_after_id is null or c.id > p_after_id)
  order by c.id
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_candidates is 'HRT-276: no pii column in this listing projection at all -- masking is not needed here because the sensitive columns are simply never selected, mirroring app.list_employees'' own established precedent.';

create function app.export_candidates(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status_filter text default null, p_limit integer default 500)
returns table (id uuid, full_name text, source text, status text)
language plpgsql
stable
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
  select c.id, c.full_name, c.source, c.status
  from app.candidates c
  where c.tenant_id = p_tenant_id and (p_status_filter is null or c.status = p_status_filter)
  order by c.created_at desc
  limit least(coalesce(p_limit, 500), 5000);
end;
$$;

comment on function app.export_candidates is 'HRT-276: a deliberately narrow, non-pii projection -- no email/phone/national_id_number/date_of_birth/address column is ever included, regardless of the caller''s HRS:View personal data standing, mirroring app.export_employees (HRT-274).';

create function app.search_candidate_duplicates(p_tenant_id uuid, p_full_name text, p_email text, p_phone text, p_actor_auth_user_id uuid, p_limit integer default 10)
returns table (id uuid, full_name text, similarity_basis text, similarity_score numeric)
language plpgsql
stable
security definer
set search_path = app, public, pg_temp
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
  select * from (
    select c.id, c.full_name, 'exact_email'::text as similarity_basis, 1.0::numeric as similarity_score
    from app.candidates c
    where c.tenant_id = p_tenant_id and p_email is not null and lower(c.email) = lower(p_email)
    union all
    select c.id, c.full_name, 'exact_phone'::text, 1.0::numeric
    from app.candidates c
    where c.tenant_id = p_tenant_id and p_phone is not null and c.phone = p_phone
    union all
    select c.id, c.full_name, 'fuzzy_name'::text, similarity(c.full_name, coalesce(p_full_name, ''))::numeric
    from app.candidates c
    where c.tenant_id = p_tenant_id and p_full_name is not null and similarity(c.full_name, p_full_name) > 0.4
  ) matches
  order by similarity_score desc
  limit least(coalesce(p_limit, 10), 50);
end;
$$;

create function app.list_application_stage_history(p_application_id uuid, p_actor_auth_user_id uuid)
returns setof app.application_stage_history
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
begin
  select * into v_application from app.job_applications where id = p_application_id;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_application_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.application_stage_history where application_id = p_application_id order by occurred_at;
end;
$$;

create function app.list_applications_for_vacancy(p_vacancy_id uuid, p_actor_auth_user_id uuid, p_stage_filter text default null)
returns table (id uuid, candidate_id uuid, candidate_full_name text, stage text, source text, applied_at timestamptz, stage_since timestamptz)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vacancy app.job_vacancies;
begin
  select * into v_vacancy from app.job_vacancies where id = p_vacancy_id;
  if not found or not app.has_active_tenant_membership(v_vacancy.tenant_id, p_actor_auth_user_id) then
    raise exception 'vacancy_not_found: %', p_vacancy_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vacancy.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vacancy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select a.id, a.candidate_id, c.full_name, a.stage, a.source, a.applied_at, a.stage_since
  from app.job_applications a
  join app.candidates c on c.id = a.candidate_id
  where a.vacancy_id = p_vacancy_id and (p_stage_filter is null or a.stage = p_stage_filter)
  order by a.applied_at desc;
end;
$$;

comment on function app.list_applications_for_vacancy is 'HRT-276: the recruitment pipeline table projection (section 15) -- candidate_full_name only, no pii column, matching app.list_candidates'' own established precedent.';

create function app.get_application_detail(p_id uuid, p_actor_auth_user_id uuid)
returns table (application app.job_applications, candidate_id uuid, candidate_full_name text, vacancy_title text)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
begin
  select * into v_application from app.job_applications where id = p_id;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select v_application, c.id, c.full_name, v.title
  from app.candidates c, app.job_vacancies v
  where c.id = v_application.candidate_id and v.id = v_application.vacancy_id;
end;
$$;

create function app.export_applications(p_tenant_id uuid, p_actor_auth_user_id uuid, p_vacancy_id uuid default null, p_limit integer default 500)
returns table (id uuid, vacancy_title text, candidate_full_name text, stage text, source text, applied_at timestamptz)
language plpgsql
stable
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
  select a.id, v.title, c.full_name, a.stage, a.source, a.applied_at
  from app.job_applications a
  join app.job_vacancies v on v.id = a.vacancy_id
  join app.candidates c on c.id = a.candidate_id
  where a.tenant_id = p_tenant_id and (p_vacancy_id is null or a.vacancy_id = p_vacancy_id)
  order by a.applied_at desc
  limit least(coalesce(p_limit, 500), 5000);
end;
$$;

create function app.list_candidate_assessments(p_application_id uuid, p_actor_auth_user_id uuid)
returns setof app.candidate_assessments
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
begin
  select * into v_application from app.job_applications where id = p_application_id;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_application_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.candidate_assessments where application_id = p_application_id order by created_at;
end;
$$;

create function app.list_application_interviews(p_application_id uuid, p_actor_auth_user_id uuid)
returns table (interview app.interviews, interviewer_employee_ids uuid[], feedback_count integer)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
begin
  select * into v_application from app.job_applications where id = p_application_id;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_application_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select i, (select array_agg(ii.employee_id) from app.interview_interviewers ii where ii.interview_id = i.id),
    (select count(*)::integer from app.interview_feedback f where f.interview_id = i.id)
  from app.interviews i
  where i.application_id = p_application_id
  order by i.round;
end;
$$;

-- Self-scoped, identity-gated (design note 5) -- never requires HRS:View. Returns an
-- empty result (never raises) when the caller has no linked employee profile.
create function app.get_my_assigned_interviews(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (interview_id uuid, application_id uuid, candidate_full_name text, vacancy_title text, scheduled_at timestamptz, status text, my_feedback_submitted boolean)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Explicit tenant-membership guard (defense in depth, HRT-275 "cheap defense in
  -- depth" precedent) -- app.resolve_actor_employee_id already implies membership
  -- transitively (app.users.tenant_id must match), but an explicit gate here is both
  -- clearer and keeps this function inside rbac-enforcement.sql's own authority-check
  -- call-graph closure (ISS-2026-033), matching app.get_my_employee_profile's own
  -- established shape exactly.
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_employee_id := app.resolve_actor_employee_id(p_tenant_id, p_actor_auth_user_id);
  if v_employee_id is null then
    return;
  end if;

  return query
  select i.id, a.id, c.full_name, v.title, i.scheduled_at, i.status,
    exists (select 1 from app.interview_feedback f where f.interview_id = i.id and f.interviewer_employee_id = v_employee_id)
  from app.interview_interviewers ii
  join app.interviews i on i.id = ii.interview_id
  join app.job_applications a on a.id = i.application_id
  join app.candidates c on c.id = a.candidate_id
  join app.job_vacancies v on v.id = a.vacancy_id
  where ii.employee_id = v_employee_id and i.tenant_id = p_tenant_id
  order by i.scheduled_at desc;
end;
$$;

create function app.get_offer_timeline(p_offer_id uuid, p_actor_auth_user_id uuid)
returns table (offer app.job_offers, versions app.job_offer_versions[])
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_offer app.job_offers;
begin
  select * into v_offer from app.job_offers where id = p_offer_id;
  if not found or not app.has_active_tenant_membership(v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'offer_not_found: %', p_offer_id using errcode = 'no_data_found';
  end if;

  if not app.can_view_job_offer(v_offer, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not view offer %', p_actor_auth_user_id, p_offer_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select v_offer, array_agg(ov order by ov.version_number)
  from app.job_offer_versions ov
  where ov.offer_id = p_offer_id;
end;
$$;

comment on function app.get_offer_timeline is 'HRT-276: HRS:View, OR a currently-eligible approver for the offer''s pending step, OR an actor who already decided a step on it (design note 4/app.can_view_job_offer) -- "approvers see offer evidence" (section 26) implemented as a real, narrower grant, not folded into HRS:View.';


-- ===========================================================================
-- 17. RLS.
-- ===========================================================================

alter table app.job_vacancies enable row level security;
alter table app.job_vacancy_lifecycle_events enable row level security;
alter table app.job_vacancy_postings enable row level security;
alter table app.candidates enable row level security;
alter table app.candidate_duplicate_candidates enable row level security;
alter table app.job_applications enable row level security;
alter table app.application_stage_history enable row level security;
alter table app.candidate_assessments enable row level security;
alter table app.interviews enable row level security;
alter table app.interview_interviewers enable row level security;
alter table app.interview_feedback enable row level security;
alter table app.job_offers enable row level security;
alter table app.job_offer_versions enable row level security;

create policy job_vacancies_select_scoped on app.job_vacancies
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy job_vacancy_lifecycle_events_select_scoped on app.job_vacancy_lifecycle_events
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy job_vacancy_postings_select_scoped on app.job_vacancy_postings
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy candidates_select_scoped on app.candidates
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy candidate_duplicate_candidates_select_scoped on app.candidate_duplicate_candidates
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy job_applications_select_scoped on app.job_applications
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy application_stage_history_select_scoped on app.application_stage_history
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy candidate_assessments_select_scoped on app.candidate_assessments
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy interviews_select_scoped on app.interviews
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy interview_interviewers_select_scoped on app.interview_interviewers
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy interview_feedback_select_scoped on app.interview_feedback
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy job_offers_select_scoped on app.job_offers
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy job_offer_versions_select_scoped on app.job_offer_versions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- app.job_application_intake_attempts carries no tenant_id column and no
-- authenticated/anon grant at all -- mirrors app.vendor_intake_attempts (PRC-251)
-- exactly (no RLS policy needed since no role beyond service_role can read it).

-- ===========================================================================
-- 18. Grants.
-- ===========================================================================

revoke execute on all functions in schema app from public;

-- app.candidates carries classified pii columns (email/phone/national_id_number/
-- date_of_birth/address -- design note 9). Column-restricted from day one, mirroring
-- PLT-114/app.employees' own already-proven pattern.
grant select (
  id, tenant_id, full_name, resume_file_id, source, referral_employee_id,
  consent_given, consent_given_at, consent_version, status, block_reason,
  idempotency_key, record_version, created_by, created_at, updated_at
) on app.candidates to authenticated;
grant select on app.candidates to service_role;
grant insert, update, delete on app.candidates to service_role;

grant select on app.job_vacancies to authenticated, service_role;
grant insert, update, delete on app.job_vacancies to service_role;
grant select on app.job_vacancy_lifecycle_events to authenticated, service_role;
grant insert on app.job_vacancy_lifecycle_events to service_role;
grant select on app.job_vacancy_postings to authenticated, service_role;
grant insert, update on app.job_vacancy_postings to service_role;
grant select on app.candidate_duplicate_candidates to authenticated, service_role;
grant insert, update on app.candidate_duplicate_candidates to service_role;
grant select on app.job_applications to authenticated, service_role;
grant insert, update, delete on app.job_applications to service_role;
grant select on app.application_stage_history to authenticated, service_role;
grant insert on app.application_stage_history to service_role;
grant select on app.candidate_assessments to authenticated, service_role;
grant insert, update on app.candidate_assessments to service_role;
grant select on app.interviews to authenticated, service_role;
grant insert, update on app.interviews to service_role;
grant select on app.interview_interviewers to authenticated, service_role;
grant insert on app.interview_interviewers to service_role;
grant select on app.interview_feedback to authenticated, service_role;
grant insert on app.interview_feedback to service_role;
grant select on app.job_offers to authenticated, service_role;
grant insert, update on app.job_offers to service_role;
grant select on app.job_offer_versions to authenticated, service_role;
grant insert, update on app.job_offer_versions to service_role;

grant select, insert on app.job_application_intake_attempts to service_role;

grant execute on function app.resolve_actor_employee_id(uuid, uuid) to service_role;
grant execute on function app.candidate_audit_projection(app.candidates) to service_role;
grant execute on function app.job_vacancy_audit_projection(app.job_vacancies) to service_role;
grant execute on function app.job_application_audit_projection(app.job_applications) to service_role;
grant execute on function app.job_offer_version_audit_projection(app.job_offer_versions) to service_role;
grant execute on function app.can_view_job_offer(app.job_offers, uuid) to service_role;
grant execute on function app.assert_candidate_draft_idempotent_replay(app.candidates, text, text, text, text) to service_role;

grant execute on function app.create_job_vacancy_draft(uuid, uuid, text, text, integer, text, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_job_vacancy_draft(uuid, integer, text, text, integer, text, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.publish_job_vacancy(uuid, integer, integer, uuid, text) to authenticated, service_role;
grant execute on function app.hold_job_vacancy(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.reopen_job_vacancy(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.close_job_vacancy(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_job_vacancy_draft(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.create_candidate(uuid, text, text, text, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_candidate_profile(uuid, integer, text, text, text, date, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.record_candidate_consent(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.set_candidate_status(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.flag_candidate_duplicate(uuid, uuid, text, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.decide_candidate_duplicate(uuid, integer, text, text, uuid, text) to authenticated, service_role;

grant execute on function app.apply_to_vacancy(uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.transition_application_stage(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.reject_application(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.withdraw_application(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.create_candidate_assessment(uuid, text, text, numeric, numeric, uuid, text) to authenticated, service_role;
grant execute on function app.record_assessment_result(uuid, integer, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_candidate_assessment(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.schedule_interview(uuid, integer, text, timestamptz, integer, text, uuid[], uuid, text) to authenticated, service_role;
grant execute on function app.reschedule_interview(uuid, integer, timestamptz, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_interview(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.complete_interview(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.submit_interview_feedback(uuid, integer, text, text, uuid, text) to authenticated, service_role;

grant execute on function app.create_job_offer_version(uuid, numeric, text, date, date, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_job_offer_for_approval(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decide_job_offer_approval(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.extend_job_offer(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.record_offer_response(uuid, integer, text, text, uuid, text) to authenticated, service_role;

grant execute on function app.get_public_open_vacancy_summaries(text) to service_role;
grant execute on function app.resolve_public_job_posting(text, text) to service_role;
grant execute on function app.submit_public_job_application(text, text, text, text, text, boolean, text, text) to service_role;

grant execute on function app.list_job_vacancies(uuid, uuid, text, text, integer, uuid) to authenticated, service_role;
grant execute on function app.get_job_vacancy(uuid, uuid) to authenticated, service_role;
grant execute on function app.export_job_vacancies(uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.get_candidate_profile(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_candidates(uuid, uuid, text, text, integer, uuid) to authenticated, service_role;
grant execute on function app.export_candidates(uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.search_candidate_duplicates(uuid, text, text, text, uuid, integer) to authenticated, service_role;
grant execute on function app.list_application_stage_history(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_applications_for_vacancy(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_application_detail(uuid, uuid) to authenticated, service_role;
grant execute on function app.export_applications(uuid, uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.list_candidate_assessments(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_application_interviews(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_my_assigned_interviews(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_offer_timeline(uuid, uuid) to authenticated, service_role;
