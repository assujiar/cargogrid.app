-- Procurement capability PRC-257 (RFQ, CG-S11-PRC-008). The seventh Phase 6
-- checkpoint, built directly on the already-VERIFIED PRC-256 (Sourcing).
-- Implements source-linked Procurement RFQs with governed vendor invitations,
-- comparable versioned response capture, clarification, deadline/extension
-- control, and a comparison-ready close. Reads (never re-derives eligibility
-- from scratch): app.sourcing_candidates where shortlisted = true is the
-- vendor invitation universe; app.sourcing_requests is the demand source
-- (20260730630000, PRC-256). Reuses app.evaluate_permission/app.rbac_decision
-- (PLT-113), app.capture_audit_event (PLT-112), app.has_prc_view_cost
-- (PRC-252), app.has_active_tenant_membership/app.actor_holds_customer_user_
-- layer (the hardened pattern-5 RLS predicate), and app.files/app.initiate_
-- file_upload/app.record_file_scan_result (PLT-128) for private, scanned
-- response evidence. No second vendor-shaped table, no second workflow/
-- numbering/file/notification engine is introduced.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Vendor eligibility is read, never re-derived.** Every invitation this
--    migration creates traces to an `app.sourcing_candidates` row (eligible
--    at minimum, per-vendor exclusion reasons already computed by PRC-256).
--    `app.issue_rfq` invites every `shortlisted = true` candidate for the
--    RFQ's own `sourcing_request_id`; `app.invite_additional_rfq_vendor`
--    (a governed exception, PRC:Override + mandatory reason) may add an
--    `eligible = true` candidate that was not part of the original shortlist,
--    but NEVER an ineligible one -- the exception flow's own "block
--    ineligible vendor" requirement is a hard `raise`, not a warning.
-- 2. **RFQ root/version/number.** `app.rfqs` is the canonical root.
--    `rfq_number` (app.next_rfq_number, the same bounded, disclosed
--    alternative to the full Configurable Numbering Engine PLT-125 that
--    COM-151's own app.next_quotation_number already established --
--    confirmed by direct inspection before choosing this pattern) is stable
--    across every version of one RFQ. A "changed requirements" revision
--    (business rule, Prompt 257 §24) is `app.revise_rfq`: while `issued`,
--    it marks the current row `superseded` and inserts a brand NEW row
--    (`version` + 1, `revised_from_id` set, `rfq_number` unchanged, status
--    reset to `draft`) -- never an in-place rewrite of an already-issued
--    RFQ's own requirements. The new version needs a fresh `app.issue_rfq`
--    call to re-invite vendors; existing invitations/responses on the
--    superseded version stay exactly as they were, for audit -- comparison
--    only ever considers the current (non-superseded) version.
-- 3. **requirements_snapshot excludes budget_amount at WRITE time, not READ
--    time.** PRC-256's own C-07 lesson (its build log §10.1 finding A):
--    `app.sourcing_requests.demand_snapshot` may carry `budget_amount`
--    verbatim. RFQ has no functional need for the internal budget figure --
--    vendor comparison uses each response's OWN `total_amount`, never the
--    internal benchmark -- so `app.draft_rfq_from_sourcing` strips the key
--    (`v_sourcing.demand_snapshot - 'budget_amount'`) before it is ever
--    stored on `app.rfqs.requirements_snapshot`. This is the stronger fix:
--    nothing to mask at read time because the value never lands in the
--    snapshot at all. `app.rfqs` therefore carries NO cost-sensitive column
--    of its own -- `app.rfqs_directory` is a PLAIN, unmasked view (kept only
--    for the "always read through a directory view" convention), and every
--    RFQ-root read RPC below returns `app.rfqs` directly, never a masked
--    projection.
-- 4. **app.rfq_responses IS cost-sensitive** (currency/total_amount/
--    validity_until/commercial_terms -- each vendor's own commercial offer).
--    Masked in `app.rfq_responses_directory` and in `app.list_rfq_responses`
--    behind `app.has_prc_view_cost`, the identical `has_prc_view_cost`
--    reused, never redefined, mirroring `budget_amount`'s own established
--    treatment. `lead_time_days`/`capture_mode`/`received_at`/
--    `comparison_eligible` are operational, not financial -- never masked.
-- 5. **No external vendor-facing response surface is built.** Prompt 257
--    §15 itself names this "optional... only when vendor identity scope is
--    verified" -- optional, and this checkpoint deliberately does not build
--    it, disclosed the same way PRC-255 disclosed deferring its own import
--    adapter UI and PRC-256 disclosed deferring capacity eligibility: no
--    capability is fabricated against infrastructure that does not exist.
--    Building a live anonymous public vendor-facing submission endpoint
--    would also be this repository's first NEW anonymous/public entry point
--    since Prompt 251's vendor-intake token (a `ADR-0021` §3.2 batch-cut
--    trigger on its own) for zero net capability this checkpoint's own
--    acceptance criteria requires -- Prompt 257's own business rule 3
--    ("Offline/email capture requires actor, source file/message, received
--    time and vendor confirmation where policy requires") describes exactly
--    the INTERNAL capture flow this migration builds instead:
--    `app.submit_rfq_response` requires an authenticated internal actor, an
--    optional evidence file (re-validated, never trusted -- design note 9),
--    a mandatory `received_at`, and an explicit `vendor_confirmed` flag.
--    Vendor invitation tokens (Prompt 257 §16) are deferred alongside the
--    external surface they exist to secure -- a token with no consuming
--    endpoint is a capability with no caller (taxonomy C-20), not a security
--    control.
-- 6. **Confidentiality (§16 "vendors cannot see competitor offers") is
--    structurally satisfied, not merely policy-enforced**, precisely because
--    no vendor-facing read path exists anywhere in this migration -- every
--    read RPC gates on tenant + PRC:View(+cost), the exact same internal
--    actor model every other PRC-25x capability already uses. There is no
--    code path by which a vendor identity reaches any RFQ row.
-- 7. **Late-capture authority is derived without a pre-authorization
--    disclosure (mirrors PRC-256's own C-05 fix directly, applied from the
--    start rather than discovered by a later review).** `app.submit_rfq_
--    response` checks PRC:Edit FIRST (a baseline every caller of this
--    function needs, disclosing nothing itself), only THEN locks and reads
--    the parent RFQ's own `response_deadline_at` to decide whether the
--    capture is late, and ONLY IF it is late does a SECOND, additional
--    PRC:Override check run (plus a mandatory `p_late_reason`) -- composing
--    two independently-gated checks, the same "compose two real, already-
--    gated calls" pattern `app.evaluate_sourcing_candidate_eligibility`
--    (PRC-256 design note 8) already established, never a single check
--    reordered around a data-dependent branch that could leak the deadline
--    itself to an unauthorized caller.
-- 8. **Lock order, stated once here per ground rule 2 (`docs/standards/
--    RECURRING_DEFECT_TAXONOMY.md` C-04): every function in this migration
--    that touches both a child row (invitation/clarification/response) and
--    its parent `app.rfqs` row locks the CHILD first, then the PARENT** --
--    the identical order `app.shortlist_sourcing_candidate`/`app.evaluate_
--    sourcing_candidate_eligibility` (PRC-256) already established for
--    exactly this reason (so the two capabilities' own functions, and every
--    function within this one, can never deadlock against each other).
--    `app.draft_rfq_from_sourcing` is the one exception -- it locks
--    `app.sourcing_requests` (a foreign parent from PRC-256, not touched
--    again afterward in the same function) before creating a brand new
--    `app.rfqs` row, so no ordering conflict with any RFQ-internal lock
--    exists.
-- 9. **File re-validation happens at the accepting RPC, never upstream**
--    (taxonomy C-10, mirrors `app.record_gps_device_installation`'s own
--    established technique exactly, confirmed by direct inspection before
--    writing this function). `app.submit_rfq_response` re-checks, for every
--    `p_file_ids` entry: the file exists, `tenant_id` matches the
--    invitation's own tenant, `record_type = 'rfq_invitation'` and
--    `record_id = p_rfq_invitation_id` (files are uploaded against the
--    already-existing invitation, never a not-yet-created response row --
--    the same "attach evidence to an existing entity" precedent the GPS
--    installation evidence capability already uses), and `malware_scan_
--    status = 'clean'` -- never trusting `app.initiate_file_upload`'s own
--    prior classification.
-- 10. **Idempotency-key replay compares every load-bearing INPUT field, not
--     a subset** (ground rule 4): `draft_rfq_from_sourcing` compares
--     sourcing_request_id/owner_user_id; `revise_rfq` compares revised_from_
--     id (=p_rfq_id)/reason/the three override params; `submit_rfq_response`
--     compares rfq_invitation_id/total_amount/currency/received_at. Every
--     nested `unique_violation` race-recovery handler is scoped by `get
--     stacked diagnostics constraint_name` (ground rule 5), never a bare
--     catch-all.
-- 11. **Bounded bulk invitations** (Prompt 257 §17): `app.issue_rfq` scans
--     at most 500 shortlisted candidates per call, disclosed via a real
--     `raise warning` on overflow -- the identical bound and disclosure
--     technique `app.evaluate_sourcing_candidate_eligibility` (PRC-256
--     design note 9) already established.
-- 12. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE
--     EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
--     its final grants, the standing per-migration convention since
--     `PLT-118`.
-- 13. **Self-caught, fixed before this migration was ever applied anywhere**
--     (Tier B taxonomy walk against this checkpoint's own diff, per
--     `docs/standards/RECURRING_DEFECT_TAXONOMY.md` -- not a follow-up
--     harden migration, the same "not yet applied, so fix directly"
--     precedent PRC-255/PRC-256 already established): (a) C-01 --
--     `app.submit_rfq_response`'s idempotency-replay comparison originally
--     checked only rfq_invitation_id/total_amount/currency/received_at;
--     widened to compare every caller-supplied field (validity_until/
--     lead_time_days/capture_mode/source_message_ref/vendor_confirmed/
--     commercial_terms too), both in the pre-check and the unique_violation
--     race-recovery handler. (b) C-01 -- `app.revise_rfq`'s own replay
--     comparison checked only revised_from_id; widened to compare the four
--     resolved override fields (cargo_weight_max/cargo_volume_max/
--     destination_lane/currency), computed once, early, and reused by both
--     the pre-check and the race-recovery handler. (c) C-04 --
--     `app.invite_additional_rfq_vendor` made its eligible/ineligible
--     decision on an UNLOCKED read of the `app.sourcing_candidates` row;
--     added `for update`, locked after `app.rfqs` (this function's own
--     existing lock), confirmed not to introduce a new deadlock class
--     against either PRC-256 function's own locking order (design note 8).
--     (d) C-20 -- `app.list_rfq_response_attachments` had a real db-test
--     assertion but no UI caller; wired into the detail page (fetched per
--     response, attachment count rendered next to the response row) rather
--     than left silently unreachable.

-- ===========================================================================
-- 1. app.rfq_number_counters + app.next_rfq_number (design note 2).
-- ===========================================================================

create table app.rfq_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

comment on table app.rfq_number_counters is
  'PRC-257: one atomic, tenant-scoped monotonic counter for app.next_rfq_number() -- the same bounded, disclosed alternative to the full Configurable Numbering Engine (PLT-125) that app.quotation_number_counters (COM-151) already established. Internal bookkeeping only -- no directly-readable row, mirrors app.quotation_number_counters'' own "none" RLS policy exactly.';

alter table app.rfq_number_counters enable row level security;

create policy rfq_number_counters_none on app.rfq_number_counters
  for select to authenticated
  using (false);

create function app.next_rfq_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.rfq_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.rfq_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'RFQ-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

comment on function app.next_rfq_number is 'PRC-257: atomic collision-safe allocation via a single INSERT ... ON CONFLICT ... DO UPDATE ... RETURNING, mirroring app.next_quotation_number (COM-151) exactly. Never recycled.';

-- ===========================================================================
-- 2. app.rfqs -- the RFQ root/version (design notes 2-3, 8).
-- ===========================================================================

create table app.rfqs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid references app.org_units (id),
  sourcing_request_id uuid not null references app.sourcing_requests (id),
  rfq_number text not null,
  version integer not null default 1,
  revised_from_id uuid references app.rfqs (id),
  requirements_snapshot jsonb not null default '{}'::jsonb,
  service_type text not null,
  mode text,
  origin_lane text not null,
  destination_lane text not null,
  cargo_weight_min numeric(14, 3),
  cargo_weight_max numeric(14, 3),
  cargo_volume_min numeric(14, 3),
  cargo_volume_max numeric(14, 3),
  currency text,
  status text not null default 'draft',
  issued_at timestamptz,
  response_deadline_at timestamptz,
  closed_at timestamptz,
  closed_reason text,
  owner_user_id uuid references auth.users (id),
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rfqs_status_check check (status in ('draft', 'issued', 'closed', 'cancelled', 'superseded')),
  constraint rfqs_version_check check (version > 0),
  constraint rfqs_service_type_check check (length(trim(service_type)) > 0),
  constraint rfqs_origin_lane_check check (length(trim(origin_lane)) > 0),
  constraint rfqs_destination_lane_check check (length(trim(destination_lane)) > 0),
  constraint rfqs_cargo_weight_min_nonneg_check check (cargo_weight_min is null or cargo_weight_min >= 0),
  constraint rfqs_cargo_weight_max_nonneg_check check (cargo_weight_max is null or cargo_weight_max >= 0),
  constraint rfqs_cargo_volume_min_nonneg_check check (cargo_volume_min is null or cargo_volume_min >= 0),
  constraint rfqs_cargo_volume_max_nonneg_check check (cargo_volume_max is null or cargo_volume_max >= 0),
  constraint rfqs_cargo_weight_range_check check (cargo_weight_max is null or cargo_weight_min is null or cargo_weight_max >= cargo_weight_min),
  constraint rfqs_cargo_volume_range_check check (cargo_volume_max is null or cargo_volume_min is null or cargo_volume_max >= cargo_volume_min),
  constraint rfqs_closed_reason_check check (status <> 'cancelled' or (closed_reason is not null and length(trim(closed_reason)) > 0)),
  constraint rfqs_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.rfqs is
  'PRC-257: canonical RFQ root/version. rfq_number is stable across every version of one RFQ (app.next_rfq_number, design note 2); a "changed requirements" revision marks the current row superseded and inserts a brand new row (app.revise_rfq). requirements_snapshot NEVER carries budget_amount (design note 3, stripped at write time) -- this table carries no cost-sensitive column of its own.';

create index rfqs_tenant_status_idx on app.rfqs (tenant_id, status);
create index rfqs_tenant_sourcing_idx on app.rfqs (tenant_id, sourcing_request_id);
create index rfqs_tenant_deadline_idx on app.rfqs (tenant_id, response_deadline_at) where status = 'issued';
create index rfqs_tenant_number_idx on app.rfqs (tenant_id, rfq_number);
create index rfqs_tenant_created_idx on app.rfqs (tenant_id, created_at desc);
create index rfqs_revised_from_idx on app.rfqs (revised_from_id) where revised_from_id is not null;

create function app.touch_rfq_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

comment on function app.touch_rfq_row is 'PRC-257: shared before-update touch trigger for app.rfqs/app.rfq_invitations/app.rfq_clarifications/app.rfq_responses -- record_version += 1, updated_at := now(), mirroring app.touch_sourcing_row (PRC-256) exactly. Every transition RPC''s own terminal UPDATE still carries the mandatory record_version-scoped WHERE and post-UPDATE stale_version re-check.';

create trigger rfqs_touch_row
  before update on app.rfqs
  for each row
  execute function app.touch_rfq_row();

-- ===========================================================================
-- 3. app.rfq_requirement_lines.
-- ===========================================================================

create table app.rfq_requirement_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  rfq_id uuid not null references app.rfqs (id),
  line_no integer not null,
  description text not null,
  quantity numeric(14, 3),
  uom text,
  notes text,
  created_at timestamptz not null default now(),
  constraint rfq_requirement_lines_line_no_check check (line_no > 0),
  constraint rfq_requirement_lines_description_check check (length(trim(description)) > 0),
  constraint rfq_requirement_lines_quantity_nonneg_check check (quantity is null or quantity >= 0),
  constraint rfq_requirement_lines_unique unique (rfq_id, line_no)
);

comment on table app.rfq_requirement_lines is
  'PRC-257: itemized requirement lines for one RFQ version. Auto-populated with one default line (description=service_type, quantity/uom derived from the inherited cargo profile) at app.draft_rfq_from_sourcing/app.revise_rfq creation time -- editing a line means revising the whole RFQ (app.revise_rfq), never an in-place per-line edit, a disclosed, bounded first iteration mirroring COM-151''s own disclosed "line editing is add/remove, not in-place edit" scope boundary.';

create index rfq_requirement_lines_rfq_idx on app.rfq_requirement_lines (rfq_id);

-- ===========================================================================
-- 4. app.rfq_invitations (design note 1).
-- ===========================================================================

create table app.rfq_invitations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  rfq_id uuid not null references app.rfqs (id),
  sourcing_candidate_id uuid not null references app.sourcing_candidates (id),
  vendor_master_id uuid not null references app.master_records (id),
  status text not null default 'invited',
  invited_at timestamptz not null default now(),
  invited_by text,
  decline_reason text,
  declined_at timestamptz,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rfq_invitations_status_check check (status in ('invited', 'declined', 'no_response', 'responded', 'withdrawn')),
  constraint rfq_invitations_decline_reason_check check (status <> 'declined' or (decline_reason is not null and length(trim(decline_reason)) > 0)),
  constraint rfq_invitations_unique_vendor unique (rfq_id, vendor_master_id)
);

comment on table app.rfq_invitations is
  'PRC-257: one row per (rfq, invited vendor). sourcing_candidate_id traces every invitation to the exact PRC-256 eligibility decision that authorized it (design note 1) -- never re-derived. app.issue_rfq bulk-creates these from shortlisted sourcing_candidates; app.invite_additional_rfq_vendor adds one eligible-but-not-originally-shortlisted candidate under a governed PRC:Override exception.';

create index rfq_invitations_rfq_idx on app.rfq_invitations (rfq_id);
create index rfq_invitations_tenant_idx on app.rfq_invitations (tenant_id);
create index rfq_invitations_vendor_idx on app.rfq_invitations (vendor_master_id);

create trigger rfq_invitations_touch_row
  before update on app.rfq_invitations
  for each row
  execute function app.touch_rfq_row();

-- Structural enforcement (defense in depth) -- mirrors
-- app.enforce_sourcing_candidate_vendor_identity (PRC-256) exactly.
create function app.enforce_rfq_invitation_vendor_identity()
returns trigger
language plpgsql
as $$
declare
  v_master app.master_records;
begin
  select * into v_master from app.master_records where id = new.vendor_master_id;
  if not found then
    raise exception 'vendor_master_record_not_found: no master record %', new.vendor_master_id using errcode = 'foreign_key_violation';
  end if;
  if v_master.master_type_code <> 'vendor' then
    raise exception 'invalid_vendor_identity: master record % is master_type_code %, expected vendor', new.vendor_master_id, v_master.master_type_code
      using errcode = 'check_violation';
  end if;
  if v_master.tenant_id is distinct from new.tenant_id then
    raise exception 'invalid_vendor_identity: master record % belongs to tenant %, not %', new.vendor_master_id, v_master.tenant_id, new.tenant_id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger rfq_invitations_enforce_vendor_identity
  before insert or update of vendor_master_id, tenant_id on app.rfq_invitations
  for each row
  execute function app.enforce_rfq_invitation_vendor_identity();

-- ===========================================================================
-- 5. app.rfq_clarifications.
-- ===========================================================================

create table app.rfq_clarifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  rfq_id uuid not null references app.rfqs (id),
  vendor_master_id uuid references app.master_records (id),
  question text not null,
  asked_by text,
  asked_at timestamptz not null default now(),
  answer text,
  answered_by text,
  answered_at timestamptz,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rfq_clarifications_question_check check (length(trim(question)) > 0)
);

comment on table app.rfq_clarifications is
  'PRC-257: one row per clarification Q&A, offline-captured by internal Procurement staff (design note 5 -- no external vendor-facing ask/answer surface exists). vendor_master_id null = broadcast to every invited vendor; set = vendor-scoped.';

create index rfq_clarifications_rfq_idx on app.rfq_clarifications (rfq_id);

create trigger rfq_clarifications_touch_row
  before update on app.rfq_clarifications
  for each row
  execute function app.touch_rfq_row();

-- ===========================================================================
-- 6. app.rfq_responses + app.rfq_response_attachments (design notes 4, 9-10).
-- ===========================================================================

create table app.rfq_responses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  rfq_id uuid not null references app.rfqs (id),
  rfq_invitation_id uuid not null references app.rfq_invitations (id),
  vendor_master_id uuid not null references app.master_records (id),
  version integer not null default 1,
  previous_version_id uuid references app.rfq_responses (id),
  status text not null default 'submitted',
  currency text not null,
  total_amount numeric(14, 2) not null,
  validity_until timestamptz,
  lead_time_days integer,
  commercial_terms jsonb not null default '{}'::jsonb,
  capture_mode text not null default 'offline',
  source_message_ref text,
  received_at timestamptz not null,
  vendor_confirmed boolean not null default false,
  late_capture boolean not null default false,
  late_reason text,
  comparison_eligible boolean not null default true,
  idempotency_key text not null,
  actor_auth_user_id uuid,
  actor_label text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rfq_responses_status_check check (status in ('submitted', 'withdrawn')),
  constraint rfq_responses_capture_mode_check check (capture_mode in ('offline', 'email')),
  constraint rfq_responses_currency_check check (length(trim(currency)) > 0),
  constraint rfq_responses_total_amount_nonneg_check check (total_amount >= 0),
  constraint rfq_responses_lead_time_nonneg_check check (lead_time_days is null or lead_time_days >= 0),
  constraint rfq_responses_version_check check (version > 0),
  constraint rfq_responses_late_reason_check check (not late_capture or (late_reason is not null and length(trim(late_reason)) > 0)),
  constraint rfq_responses_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.rfq_responses is
  'PRC-257: versioned vendor commercial response evidence (never automatically selects/commits a vendor -- business rule). Offline/email-captured by internal Procurement staff with actor/received_at/vendor_confirmed (design note 5). currency/total_amount/validity_until/commercial_terms are cost-sensitive (design note 4). late_capture=true requires PRC:Override + late_reason (design note 7) and is never comparison_eligible.';

create index rfq_responses_invitation_idx on app.rfq_responses (rfq_invitation_id);
create index rfq_responses_rfq_idx on app.rfq_responses (rfq_id);
create index rfq_responses_tenant_idx on app.rfq_responses (tenant_id);

create trigger rfq_responses_touch_row
  before update on app.rfq_responses
  for each row
  execute function app.touch_rfq_row();

create table app.rfq_response_attachments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  rfq_response_id uuid not null references app.rfq_responses (id),
  file_id uuid not null references app.files (id),
  created_at timestamptz not null default now(),
  constraint rfq_response_attachments_unique unique (rfq_response_id, file_id)
);

comment on table app.rfq_response_attachments is
  'PRC-257: private, scanned evidence files attached to one response version. Every file is re-validated (tenant/record scope/malware_scan_status=clean, design note 9) at app.submit_rfq_response itself, never trusted from a prior check.';

create index rfq_response_attachments_response_idx on app.rfq_response_attachments (rfq_response_id);

-- ===========================================================================
-- 7. app.rfq_events -- append-only lifecycle history (mirrors
--    app.sourcing_request_events exactly).
-- ===========================================================================

create table app.rfq_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  rfq_id uuid not null references app.rfqs (id),
  from_status text not null,
  to_status text not null,
  reason text,
  evidence_ref text,
  actor_auth_user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now()
);

comment on table app.rfq_events is
  'PRC-257: append-only RFQ-root lifecycle transition history, one row per real status transition, written by every RFQ-root transition RPC in the same transaction as the state change -- mirrors app.sourcing_request_events (PRC-256) exactly. Invitation/clarification/response-level actions are NOT rfq-root transitions and do not write here (mirrors app.shortlist_sourcing_candidate''s own "child-level action, no parent event row" precedent) -- app.capture_audit_event still records every one of those.';

create index rfq_events_rfq_idx on app.rfq_events (rfq_id, occurred_at);

-- ===========================================================================
-- 8. Directory views (design notes 3-4).
-- ===========================================================================

create view app.rfqs_directory
as
select r.*
from app.rfqs r
where (app.has_active_tenant_membership(r.tenant_id) and not app.actor_holds_customer_user_layer(r.tenant_id)) or app.is_supreme_admin();

comment on view app.rfqs_directory is 'PRC-257: PLAIN (unmasked) projection of app.rfqs -- no cost-sensitive field exists on this table (design note 3). Kept only for the "always read through a directory view" convention; every read RPC below reconstructs its own projection directly against the base table (design note in list_rfq_responses below), never selecting from a view whose own row filter resolves auth.uid() implicitly (PRC-256''s own C-06 lesson).';

create view app.rfq_requirement_lines_directory
as
select l.*
from app.rfq_requirement_lines l
join app.rfqs r on r.id = l.rfq_id
where (app.has_active_tenant_membership(l.tenant_id) and not app.actor_holds_customer_user_layer(l.tenant_id)) or app.is_supreme_admin();

create view app.rfq_invitations_directory
as
select i.*
from app.rfq_invitations i
where (app.has_active_tenant_membership(i.tenant_id) and not app.actor_holds_customer_user_layer(i.tenant_id)) or app.is_supreme_admin();

create view app.rfq_clarifications_directory
as
select c.*
from app.rfq_clarifications c
where (app.has_active_tenant_membership(c.tenant_id) and not app.actor_holds_customer_user_layer(c.tenant_id)) or app.is_supreme_admin();

create view app.rfq_responses_directory
as
select
  r.id, r.tenant_id, r.rfq_id, r.rfq_invitation_id, r.vendor_master_id, r.version, r.previous_version_id, r.status,
  case when app.has_prc_view_cost(r.tenant_id) then r.currency else null end as currency,
  case when app.has_prc_view_cost(r.tenant_id) then r.total_amount else null end as total_amount,
  case when app.has_prc_view_cost(r.tenant_id) then r.validity_until else null end as validity_until,
  r.lead_time_days,
  case when app.has_prc_view_cost(r.tenant_id) then r.commercial_terms else '{}'::jsonb end as commercial_terms,
  not app.has_prc_view_cost(r.tenant_id) as cost_masked,
  r.capture_mode, r.source_message_ref, r.received_at, r.vendor_confirmed, r.late_capture, r.late_reason, r.comparison_eligible,
  r.idempotency_key, r.actor_auth_user_id, r.actor_label, r.record_version, r.created_at, r.updated_at
from app.rfq_responses r
where (app.has_active_tenant_membership(r.tenant_id) and not app.actor_holds_customer_user_layer(r.tenant_id)) or app.is_supreme_admin();

comment on view app.rfq_responses_directory is 'PRC-257: field-masked projection of app.rfq_responses -- currency/total_amount/validity_until/commercial_terms nulled (cost_masked=true) for a caller lacking PRC:View cost (design note 4), mirroring app.sourcing_requests_directory''s own budget_amount treatment exactly.';

-- ===========================================================================
-- 9. Creation RPCs (PRC:Create, design notes 2-3, 8, 10).
-- ===========================================================================

create function app.draft_rfq_from_sourcing(
  p_tenant_id uuid,
  p_sourcing_request_id uuid,
  p_owner_user_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfqs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_sourcing app.sourcing_requests;
  v_existing app.rfqs;
  v_snapshot jsonb;
  v_number text;
  v_constraint_name text;
  v_rfq app.rfqs;
  v_qty numeric;
  v_uom text;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;

  -- design note 8: locks a foreign PRC-256 parent row, never touched again in
  -- this function -- no ordering conflict with any RFQ-internal lock.
  select * into v_sourcing from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;
  if v_sourcing.tenant_id <> p_tenant_id then
    raise exception 'tenant_mismatch: sourcing request % does not belong to tenant %', p_sourcing_request_id, p_tenant_id
      using errcode = 'check_violation';
  end if;
  if v_sourcing.status <> 'shortlisted' then
    raise exception 'invalid_source_status: sourcing request % is % -- an RFQ may only be drafted from a shortlisted sourcing request', p_sourcing_request_id, v_sourcing.status
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.rfqs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.sourcing_request_id is distinct from p_sourcing_request_id or v_existing.owner_user_id is distinct from p_owner_user_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different RFQ', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  -- design note 3: budget_amount is stripped at WRITE time, never carried
  -- into the snapshot at all.
  v_snapshot := v_sourcing.demand_snapshot - 'budget_amount';
  v_number := app.next_rfq_number(p_tenant_id);

  begin
    insert into app.rfqs (
      tenant_id, org_unit_id, sourcing_request_id, rfq_number, version, requirements_snapshot,
      service_type, mode, origin_lane, destination_lane, cargo_weight_min, cargo_weight_max, cargo_volume_min, cargo_volume_max, currency,
      status, owner_user_id, idempotency_key, created_by
    ) values (
      p_tenant_id, v_sourcing.org_unit_id, p_sourcing_request_id, v_number, 1, v_snapshot,
      v_sourcing.service_type, v_sourcing.mode, v_sourcing.origin_lane, v_sourcing.destination_lane,
      v_sourcing.cargo_weight_min, v_sourcing.cargo_weight_max, v_sourcing.cargo_volume_min, v_sourcing.cargo_volume_max, v_sourcing.currency,
      'draft', p_owner_user_id, p_idempotency_key, p_actor_label
    )
    returning * into v_rfq;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'rfqs_tenant_idempotency_unique' then
        select * into v_existing from app.rfqs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.sourcing_request_id is distinct from p_sourcing_request_id or v_existing.owner_user_id is distinct from p_owner_user_id then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different RFQ', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise;
  end;

  v_qty := coalesce(v_rfq.cargo_weight_max, v_rfq.cargo_volume_max);
  v_uom := case when v_rfq.cargo_weight_max is not null then 'kg' when v_rfq.cargo_volume_max is not null then 'cbm' else null end;
  insert into app.rfq_requirement_lines (tenant_id, rfq_id, line_no, description, quantity, uom)
  values (p_tenant_id, v_rfq.id, 1, v_rfq.service_type, v_qty, v_uom);

  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_rfq.id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'draft_rfq_from_sourcing',
    'app.rfqs', v_rfq.id, 'success', null, null, to_jsonb(v_rfq)
  );

  return v_rfq;
end;
$$;

comment on function app.draft_rfq_from_sourcing is 'PRC-257: idempotent on (tenant_id, idempotency_key), replay compares sourcing_request_id/owner_user_id. Blocks a sourcing request that is not shortlisted. requirements_snapshot strips budget_amount at write time (design note 3). status=draft -- needs app.issue_rfq to invite vendors.';

create function app.revise_rfq(
  p_rfq_id uuid,
  p_cargo_weight_max numeric,
  p_cargo_volume_max numeric,
  p_destination_lane text,
  p_currency text,
  p_reason text,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfqs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_old app.rfqs;
  v_existing app.rfqs;
  v_new app.rfqs;
  v_new_weight_max numeric;
  v_new_volume_max numeric;
  v_new_dest text;
  v_new_currency text;
  v_constraint_name text;
  v_qty numeric;
  v_uom text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to revise an RFQ' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;

  select * into v_old from app.rfqs where id = p_rfq_id for update;
  if not found then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_old.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Resolved early (before the idempotency check) so the replay comparison
  -- below can verify the FULL target tuple, not just revised_from_id (ground
  -- rule 4 / taxonomy C-01) -- v_old's stored values are unchanged between
  -- the original call and any replay (a replay only ever finds this row
  -- already 'superseded' by the FIRST call using this exact key, and no
  -- other function mutates cargo_weight_max/cargo_volume_max/destination_
  -- lane/currency on an rfqs row).
  v_new_weight_max := coalesce(p_cargo_weight_max, v_old.cargo_weight_max);
  v_new_volume_max := coalesce(p_cargo_volume_max, v_old.cargo_volume_max);
  v_new_dest := coalesce(nullif(trim(p_destination_lane), ''), v_old.destination_lane);
  v_new_currency := coalesce(nullif(trim(p_currency), ''), v_old.currency);

  -- Idempotency replay is checked BEFORE the version/status gates below --
  -- deliberately. A replay of an already-succeeded revise arrives with the
  -- PRE-revise p_expected_version and finds the row already 'superseded' (the
  -- first call's own terminal state), so checking version/status first would
  -- turn a legitimate retry into a false stale_version/invalid_transition
  -- instead of the intended idempotent short-circuit.
  select * into v_existing from app.rfqs where tenant_id = v_old.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.revised_from_id is distinct from p_rfq_id
      or v_existing.cargo_weight_max is distinct from v_new_weight_max
      or v_existing.cargo_volume_max is distinct from v_new_volume_max
      or v_existing.destination_lane is distinct from v_new_dest
      or v_existing.currency is distinct from v_new_currency
    then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different RFQ revision', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if v_old.record_version <> p_expected_version then
    raise exception 'stale_version: rfq % expected version % but found %', p_rfq_id, p_expected_version, v_old.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_old.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % -- only an issued RFQ may be revised', p_rfq_id, v_old.status
      using errcode = 'check_violation';
  end if;

  update app.rfqs
  set status = 'superseded'
  where id = p_rfq_id and record_version = p_expected_version
  returning * into v_old;
  if not found then
    raise exception 'stale_version: rfq % target row was concurrently modified (expected version %)', p_rfq_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  begin
    insert into app.rfqs (
      tenant_id, org_unit_id, sourcing_request_id, rfq_number, version, revised_from_id, requirements_snapshot,
      service_type, mode, origin_lane, destination_lane, cargo_weight_min, cargo_weight_max, cargo_volume_min, cargo_volume_max, currency,
      status, owner_user_id, idempotency_key, created_by
    ) values (
      v_old.tenant_id, v_old.org_unit_id, v_old.sourcing_request_id, v_old.rfq_number, v_old.version + 1, v_old.id, v_old.requirements_snapshot,
      v_old.service_type, v_old.mode, v_old.origin_lane, v_new_dest, v_old.cargo_weight_min, v_new_weight_max, v_old.cargo_volume_min, v_new_volume_max, v_new_currency,
      'draft', v_old.owner_user_id, p_idempotency_key, p_actor_label
    )
    returning * into v_new;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'rfqs_tenant_idempotency_unique' then
        select * into v_existing from app.rfqs where tenant_id = v_old.tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.revised_from_id is distinct from p_rfq_id
            or v_existing.cargo_weight_max is distinct from v_new_weight_max
            or v_existing.cargo_volume_max is distinct from v_new_volume_max
            or v_existing.destination_lane is distinct from v_new_dest
            or v_existing.currency is distinct from v_new_currency
          then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different RFQ revision', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise;
  end;

  v_qty := coalesce(v_new.cargo_weight_max, v_new.cargo_volume_max);
  v_uom := case when v_new.cargo_weight_max is not null then 'kg' when v_new.cargo_volume_max is not null then 'cbm' else null end;
  insert into app.rfq_requirement_lines (tenant_id, rfq_id, line_no, description, quantity, uom)
  values (v_new.tenant_id, v_new.id, 1, v_new.service_type, v_qty, v_uom);

  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_old.tenant_id, v_old.id, 'issued', 'superseded', p_reason, p_actor_auth_user_id, p_actor_label);
  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_new.tenant_id, v_new.id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_new.tenant_id, p_actor_auth_user_id, p_actor_label, 'revise_rfq',
    'app.rfqs', v_new.id, 'success', p_reason, to_jsonb(v_old), to_jsonb(v_new)
  );

  return v_new;
end;
$$;

comment on function app.revise_rfq is 'PRC-257: only from status=issued, mandatory reason. Marks the current version superseded and inserts a brand new draft version (version+1, revised_from_id, same rfq_number) -- existing invitations/responses stay on the superseded version, unaltered, for audit. Idempotent on (tenant_id, idempotency_key), replay compares revised_from_id.';

-- ===========================================================================
-- 10. RFQ-root lifecycle transition RPCs (design notes 1, 8, 11).
-- ===========================================================================

create function app.issue_rfq(
  p_rfq_id uuid,
  p_response_deadline_at timestamptz,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfqs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rfq app.rfqs;
  v_candidate record;
  v_count integer := 0;
begin
  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rfq.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rfq.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rfq.record_version <> p_expected_version then
    raise exception 'stale_version: rfq % expected version % but found %', p_rfq_id, p_expected_version, v_rfq.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rfq.status <> 'draft' then
    raise exception 'invalid_transition: rfq % is % and cannot be issued', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;
  if p_response_deadline_at is null or p_response_deadline_at <= now() then
    raise exception 'invalid_deadline: response deadline must be a future timestamp' using errcode = 'check_violation';
  end if;

  -- design note 11: bounded bulk invitation scan, disclosed via a real warning.
  for v_candidate in
    select id, vendor_master_id
    from app.sourcing_candidates
    where sourcing_request_id = v_rfq.sourcing_request_id and shortlisted = true
    order by id
    limit 501
  loop
    v_count := v_count + 1;
    if v_count > 500 then
      raise warning 'rfq_invitation_scan_bounded: rfq % has more than 500 shortlisted candidates -- only the first 500 (ordered by id) were invited this call; re-run app.invite_additional_rfq_vendor for the remainder', p_rfq_id;
      exit;
    end if;
    insert into app.rfq_invitations (tenant_id, rfq_id, sourcing_candidate_id, vendor_master_id, invited_by)
    values (v_rfq.tenant_id, p_rfq_id, v_candidate.id, v_candidate.vendor_master_id, p_actor_label)
    on conflict (rfq_id, vendor_master_id) do nothing;
  end loop;

  if v_count = 0 then
    raise exception 'no_shortlisted_vendors: sourcing request % has no shortlisted candidates to invite', v_rfq.sourcing_request_id
      using errcode = 'check_violation';
  end if;

  update app.rfqs
  set status = 'issued', issued_at = now(), response_deadline_at = p_response_deadline_at
  where id = p_rfq_id and record_version = p_expected_version
  returning * into v_rfq;
  if not found then
    raise exception 'stale_version: rfq % target row was concurrently modified (expected version %)', p_rfq_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_rfq.tenant_id, p_rfq_id, 'draft', 'issued', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_rfq.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_rfq',
    'app.rfqs', v_rfq.id, 'success', null, null, jsonb_build_object('status', v_rfq.status, 'invited_count', least(v_count, 500))
  );

  return v_rfq;
end;
$$;

comment on function app.issue_rfq is 'PRC-257: draft -> issued. Bulk-invites every shortlisted app.sourcing_candidates row for this RFQ''s own sourcing_request_id (design note 1), bounded to 500 (design note 11). Requires a future p_response_deadline_at and at least one shortlisted candidate.';

create function app.invite_additional_rfq_vendor(
  p_rfq_id uuid,
  p_sourcing_candidate_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfq_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rfq app.rfqs;
  v_candidate app.sourcing_candidates;
  v_invitation app.rfq_invitations;
  v_constraint_name text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to invite an additional vendor' using errcode = 'check_violation';
  end if;

  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rfq.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rfq.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rfq.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % -- additional vendors may only be invited while issued', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;

  -- Locked (taxonomy C-04): the eligible/not-eligible decision below is made
  -- on this row -- an unlocked read could race a concurrent PRC-256
  -- re-evaluation (app.evaluate_sourcing_candidate_eligibility) that flips
  -- eligible=false between this read and the insert. app.rfqs is locked
  -- first (above), this sourcing_candidates row second -- the two lock sets
  -- never overlap with either PRC-256 function's own locking order
  -- (candidate row(s) then sourcing_requests row; app.rfqs is never locked
  -- by any PRC-256 function), so no new deadlock class is introduced.
  select * into v_candidate from app.sourcing_candidates where id = p_sourcing_candidate_id for update;
  if not found then
    raise exception 'sourcing_candidate_not_found: %', p_sourcing_candidate_id using errcode = 'no_data_found';
  end if;
  if v_candidate.sourcing_request_id <> v_rfq.sourcing_request_id then
    raise exception 'candidate_source_mismatch: candidate % does not belong to rfq %''s own sourcing request', p_sourcing_candidate_id, p_rfq_id
      using errcode = 'check_violation';
  end if;
  if v_candidate.tenant_id <> v_rfq.tenant_id then
    raise exception 'tenant_mismatch: candidate % does not belong to tenant %', p_sourcing_candidate_id, v_rfq.tenant_id
      using errcode = 'check_violation';
  end if;
  if not v_candidate.eligible then
    raise exception 'ineligible_vendor: candidate % is not eligible and cannot be invited', p_sourcing_candidate_id
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.rfq_invitations (tenant_id, rfq_id, sourcing_candidate_id, vendor_master_id, invited_by)
    values (v_rfq.tenant_id, p_rfq_id, v_candidate.id, v_candidate.vendor_master_id, p_actor_label)
    returning * into v_invitation;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'rfq_invitations_unique_vendor' then
        raise exception 'vendor_already_invited: vendor % is already invited to rfq %', v_candidate.vendor_master_id, p_rfq_id
          using errcode = 'unique_violation';
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_rfq.tenant_id, p_actor_auth_user_id, p_actor_label, 'invite_additional_rfq_vendor',
    'app.rfq_invitations', v_invitation.id, 'success', p_reason, null, to_jsonb(v_invitation)
  );

  return v_invitation;
end;
$$;

comment on function app.invite_additional_rfq_vendor is 'PRC-257: PRC:Override, mandatory reason -- a governed exception. Only an ELIGIBLE app.sourcing_candidates row (never ineligible, exception flow) belonging to the same sourcing_request may be added, only while the RFQ is issued.';

create function app.extend_rfq_deadline(
  p_rfq_id uuid,
  p_new_deadline_at timestamptz,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfqs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rfq app.rfqs;
begin
  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rfq.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rfq.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rfq.record_version <> p_expected_version then
    raise exception 'stale_version: rfq % expected version % but found %', p_rfq_id, p_expected_version, v_rfq.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rfq.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % -- the deadline may only be extended while issued', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;
  if p_new_deadline_at is null or p_new_deadline_at < v_rfq.response_deadline_at then
    raise exception 'deadline_narrowing_not_allowed: new deadline % is earlier than the current deadline % -- an extension only widens', p_new_deadline_at, v_rfq.response_deadline_at
      using errcode = 'check_violation';
  end if;

  update app.rfqs
  set response_deadline_at = p_new_deadline_at
  where id = p_rfq_id and record_version = p_expected_version
  returning * into v_rfq;
  if not found then
    raise exception 'stale_version: rfq % target row was concurrently modified (expected version %)', p_rfq_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, evidence_ref, actor_auth_user_id, actor_label)
  values (v_rfq.tenant_id, p_rfq_id, 'issued', 'issued', 'new_response_deadline_at=' || p_new_deadline_at::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_rfq.tenant_id, p_actor_auth_user_id, p_actor_label, 'extend_rfq_deadline',
    'app.rfqs', v_rfq.id, 'success', null, null, jsonb_build_object('response_deadline_at', v_rfq.response_deadline_at)
  );

  return v_rfq;
end;
$$;

create function app.close_rfq_for_comparison(
  p_rfq_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfqs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rfq app.rfqs;
begin
  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rfq.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rfq.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rfq.record_version <> p_expected_version then
    raise exception 'stale_version: rfq % expected version % but found %', p_rfq_id, p_expected_version, v_rfq.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rfq.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % and cannot be closed for comparison', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;

  update app.rfq_invitations set status = 'no_response' where rfq_id = p_rfq_id and status = 'invited';

  update app.rfqs
  set status = 'closed', closed_at = now()
  where id = p_rfq_id and record_version = p_expected_version
  returning * into v_rfq;
  if not found then
    raise exception 'stale_version: rfq % target row was concurrently modified (expected version %)', p_rfq_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_rfq.tenant_id, p_rfq_id, 'issued', 'closed', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_rfq.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_rfq_for_comparison',
    'app.rfqs', v_rfq.id, 'success', null, null, jsonb_build_object('status', v_rfq.status)
  );

  return v_rfq;
end;
$$;

comment on function app.close_rfq_for_comparison is 'PRC-257: issued -> closed. Every still-invited (no response ever submitted) invitation is marked no_response. Comparison reads app.list_rfq_responses for this RFQ once closed -- comparison_eligible already distinguishes on-time vs late-captured responses.';

create function app.cancel_rfq(
  p_rfq_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfqs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rfq app.rfqs;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel an RFQ' using errcode = 'check_violation';
  end if;

  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rfq.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rfq.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rfq.record_version <> p_expected_version then
    raise exception 'stale_version: rfq % expected version % but found %', p_rfq_id, p_expected_version, v_rfq.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rfq.status not in ('draft', 'issued') then
    raise exception 'invalid_transition: rfq % is % and cannot be cancelled', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_rfq.status;

  update app.rfqs
  set status = 'cancelled', closed_at = now(), closed_reason = p_reason
  where id = p_rfq_id and record_version = p_expected_version
  returning * into v_rfq;
  if not found then
    raise exception 'stale_version: rfq % target row was concurrently modified (expected version %)', p_rfq_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.rfq_events (tenant_id, rfq_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_rfq.tenant_id, p_rfq_id, v_from_status, 'cancelled', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_rfq.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_rfq',
    'app.rfqs', v_rfq.id, 'success', p_reason, null, jsonb_build_object('status', v_rfq.status)
  );

  return v_rfq;
end;
$$;

-- ===========================================================================
-- 11. Invitation-level RPCs (design note 8: child locked before parent).
-- ===========================================================================

create function app.decline_rfq_invitation(
  p_rfq_invitation_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfq_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_invitation app.rfq_invitations;
  v_rfq_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decline an invitation' using errcode = 'check_violation';
  end if;

  select * into v_invitation from app.rfq_invitations where id = p_rfq_invitation_id for update;
  if not found then
    raise exception 'rfq_invitation_not_found: %', p_rfq_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: rfq invitation % expected version % but found %', p_rfq_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;

  -- design note 8: child (invitation) already locked above, parent (rfq)
  -- locked here, second.
  select status into v_rfq_status from app.rfqs where id = v_invitation.rfq_id for update;
  if v_rfq_status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % -- an invitation may only be declined while issued', v_invitation.rfq_id, v_rfq_status
      using errcode = 'check_violation';
  end if;
  if v_invitation.status <> 'invited' then
    raise exception 'invalid_transition: rfq invitation % is % and cannot be declined', p_rfq_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.rfq_invitations
  set status = 'declined', decline_reason = p_reason, declined_at = now()
  where id = p_rfq_invitation_id and record_version = p_expected_version
  returning * into v_invitation;
  if not found then
    raise exception 'stale_version: rfq invitation % target row was concurrently modified (expected version %)', p_rfq_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'decline_rfq_invitation',
    'app.rfq_invitations', v_invitation.id, 'success', p_reason, null, jsonb_build_object('status', v_invitation.status)
  );

  return v_invitation;
end;
$$;

comment on function app.decline_rfq_invitation is 'PRC-257: internal staff-captured record of a vendor decline (offline/email, business rule 3). Only while invited and the parent RFQ is issued. Lock order: invitation, then rfq (design note 8).';

-- ===========================================================================
-- 12. Clarification RPCs.
-- ===========================================================================

create function app.record_rfq_clarification(
  p_rfq_id uuid,
  p_vendor_master_id uuid,
  p_question text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfq_clarifications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rfq app.rfqs;
  v_row app.rfq_clarifications;
begin
  if p_question is null or length(trim(p_question)) = 0 then
    raise exception 'question_required: a non-empty question is required' using errcode = 'check_violation';
  end if;

  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rfq.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rfq.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_rfq.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % -- clarifications may only be recorded while issued', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;
  if p_vendor_master_id is not null and not exists (select 1 from app.rfq_invitations where rfq_id = p_rfq_id and vendor_master_id = p_vendor_master_id) then
    raise exception 'vendor_not_invited: vendor % is not invited to rfq %', p_vendor_master_id, p_rfq_id using errcode = 'check_violation';
  end if;

  insert into app.rfq_clarifications (tenant_id, rfq_id, vendor_master_id, question, asked_by)
  values (v_rfq.tenant_id, p_rfq_id, p_vendor_master_id, p_question, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    v_rfq.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_rfq_clarification',
    'app.rfq_clarifications', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

create function app.answer_rfq_clarification(
  p_clarification_id uuid,
  p_answer text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfq_clarifications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.rfq_clarifications;
begin
  if p_answer is null or length(trim(p_answer)) = 0 then
    raise exception 'answer_required: a non-empty answer is required' using errcode = 'check_violation';
  end if;

  select * into v_row from app.rfq_clarifications where id = p_clarification_id for update;
  if not found then
    raise exception 'rfq_clarification_not_found: %', p_clarification_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: rfq clarification % expected version % but found %', p_clarification_id, p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.answer is not null then
    raise exception 'clarification_already_answered: clarification % already carries an answer', p_clarification_id using errcode = 'check_violation';
  end if;

  update app.rfq_clarifications
  set answer = p_answer, answered_by = p_actor_label, answered_at = now()
  where id = p_clarification_id and record_version = p_expected_version
  returning * into v_row;
  if not found then
    raise exception 'stale_version: rfq clarification % target row was concurrently modified (expected version %)', p_clarification_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'answer_rfq_clarification',
    'app.rfq_clarifications', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- 13. Response RPCs (design notes 4, 7, 9-10).
-- ===========================================================================

create function app.submit_rfq_response(
  p_rfq_invitation_id uuid,
  p_currency text,
  p_total_amount numeric,
  p_validity_until timestamptz,
  p_lead_time_days integer,
  p_commercial_terms jsonb,
  p_capture_mode text,
  p_source_message_ref text,
  p_received_at timestamptz,
  p_vendor_confirmed boolean,
  p_file_ids uuid[],
  p_late_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfq_responses
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_late_decision app.rbac_decision;
  v_invitation app.rfq_invitations;
  v_rfq app.rfqs;
  v_late boolean;
  v_existing app.rfq_responses;
  v_response app.rfq_responses;
  v_file app.files;
  v_file_id uuid;
  v_prev_version integer;
  v_prev_id uuid;
  v_constraint_name text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;
  if p_currency is null or length(trim(p_currency)) = 0 then
    raise exception 'invalid_currency: currency must not be empty' using errcode = 'check_violation';
  end if;
  if p_total_amount is null or p_total_amount < 0 then
    raise exception 'invalid_total_amount: total_amount must be a non-negative number' using errcode = 'check_violation';
  end if;
  if p_received_at is null then
    raise exception 'received_at_required: received_at must not be empty' using errcode = 'check_violation';
  end if;
  if p_capture_mode is null or p_capture_mode not in ('offline', 'email') then
    raise exception 'invalid_capture_mode: % is not one of offline/email', p_capture_mode using errcode = 'check_violation';
  end if;

  select * into v_invitation from app.rfq_invitations where id = p_rfq_invitation_id for update;
  if not found then
    raise exception 'rfq_invitation_not_found: %', p_rfq_invitation_id using errcode = 'no_data_found';
  end if;

  -- design note 7: baseline PRC:Edit check runs BEFORE the parent rfq (and
  -- its own deadline) is ever read -- discloses nothing about the rfq itself.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.status not in ('invited', 'responded') then
    raise exception 'invalid_transition: rfq invitation % is % and cannot accept a response', p_rfq_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  -- design note 8: child (invitation) already locked above, parent (rfq)
  -- locked here, second.
  select * into v_rfq from app.rfqs where id = v_invitation.rfq_id for update;
  if v_rfq.status <> 'issued' then
    raise exception 'invalid_transition: rfq % is % and is not accepting responses', v_rfq.id, v_rfq.status
      using errcode = 'check_violation';
  end if;

  v_late := p_received_at > v_rfq.response_deadline_at;
  if v_late then
    v_late_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Override');
    if not v_late_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant % -- a response received after the deadline requires an authorized late capture', p_actor_auth_user_id, v_late_decision.reason, v_invitation.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
    if p_late_reason is null or length(trim(p_late_reason)) = 0 then
      raise exception 'late_reason_required: a reason is required to capture a response received after the deadline' using errcode = 'check_violation';
    end if;
  end if;

  -- Ground rule 4 / taxonomy C-01: compares every load-bearing caller-
  -- supplied field, not a subset -- including the ones a narrower comparison
  -- would let a reused key silently drift on (lead time, validity, capture
  -- mode, source reference, vendor confirmation, commercial terms).
  select * into v_existing from app.rfq_responses where tenant_id = v_invitation.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.rfq_invitation_id is distinct from p_rfq_invitation_id or v_existing.total_amount is distinct from p_total_amount
      or v_existing.currency is distinct from p_currency or v_existing.received_at is distinct from p_received_at
      or v_existing.validity_until is distinct from p_validity_until or v_existing.lead_time_days is distinct from p_lead_time_days
      or v_existing.capture_mode is distinct from p_capture_mode or v_existing.source_message_ref is distinct from p_source_message_ref
      or v_existing.vendor_confirmed is distinct from coalesce(p_vendor_confirmed, false)
      or v_existing.commercial_terms is distinct from coalesce(p_commercial_terms, '{}'::jsonb)
    then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different RFQ response', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  -- design note 9: every file is re-validated HERE, never trusted from a
  -- prior check -- tenant, record scope (uploaded against the already-
  -- existing invitation), and scan status.
  if p_file_ids is not null then
    foreach v_file_id in array p_file_ids loop
      select * into v_file from app.files where id = v_file_id;
      if not found then
        raise exception 'rfq_response_file_not_found: %', v_file_id using errcode = 'no_data_found';
      end if;
      if v_file.tenant_id <> v_invitation.tenant_id or v_file.record_type <> 'rfq_invitation' or v_file.record_id <> p_rfq_invitation_id then
        raise exception 'rfq_response_file_mismatch: file % does not belong to invitation % in tenant %', v_file_id, p_rfq_invitation_id, v_invitation.tenant_id
          using errcode = 'check_violation';
      end if;
      if v_file.malware_scan_status <> 'clean' then
        raise exception 'rfq_response_unsafe_file: file % has scan status % -- only clean files may be attached', v_file_id, v_file.malware_scan_status
          using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  select coalesce(max(version), 0), (array_agg(id order by version desc))[1]
  into v_prev_version, v_prev_id
  from app.rfq_responses where rfq_invitation_id = p_rfq_invitation_id;

  begin
    insert into app.rfq_responses (
      tenant_id, rfq_id, rfq_invitation_id, vendor_master_id, version, previous_version_id,
      currency, total_amount, validity_until, lead_time_days, commercial_terms, capture_mode, source_message_ref,
      received_at, vendor_confirmed, late_capture, late_reason, comparison_eligible, idempotency_key, actor_auth_user_id, actor_label
    ) values (
      v_invitation.tenant_id, v_invitation.rfq_id, p_rfq_invitation_id, v_invitation.vendor_master_id, coalesce(v_prev_version, 0) + 1, v_prev_id,
      p_currency, p_total_amount, p_validity_until, p_lead_time_days, coalesce(p_commercial_terms, '{}'::jsonb), p_capture_mode, p_source_message_ref,
      p_received_at, coalesce(p_vendor_confirmed, false), v_late, p_late_reason, not v_late, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    )
    returning * into v_response;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'rfq_responses_tenant_idempotency_unique' then
        select * into v_existing from app.rfq_responses where tenant_id = v_invitation.tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.rfq_invitation_id is distinct from p_rfq_invitation_id or v_existing.total_amount is distinct from p_total_amount
            or v_existing.currency is distinct from p_currency or v_existing.received_at is distinct from p_received_at
            or v_existing.validity_until is distinct from p_validity_until or v_existing.lead_time_days is distinct from p_lead_time_days
            or v_existing.capture_mode is distinct from p_capture_mode or v_existing.source_message_ref is distinct from p_source_message_ref
            or v_existing.vendor_confirmed is distinct from coalesce(p_vendor_confirmed, false)
            or v_existing.commercial_terms is distinct from coalesce(p_commercial_terms, '{}'::jsonb)
          then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different RFQ response', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise;
  end;

  if p_file_ids is not null and cardinality(p_file_ids) > 0 then
    insert into app.rfq_response_attachments (tenant_id, rfq_response_id, file_id)
    select v_invitation.tenant_id, v_response.id, f
    from unnest(p_file_ids) as f
    on conflict do nothing;
  end if;

  update app.rfq_invitations set status = 'responded' where id = p_rfq_invitation_id;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_rfq_response',
    'app.rfq_responses', v_response.id, 'success', p_late_reason, null, jsonb_build_object('version', v_response.version, 'late_capture', v_response.late_capture)
  );

  return v_response;
end;
$$;

comment on function app.submit_rfq_response is 'PRC-257: internal offline/email capture only (design note 5) -- requires an authenticated actor, a mandatory received_at, and an explicit vendor_confirmed flag. On-time requires PRC:Edit; a response received after response_deadline_at additionally requires PRC:Override + a mandatory late_reason (design note 7), and is never comparison_eligible. Files are re-validated at this RPC (design note 9). Idempotent on (tenant_id, idempotency_key).';

create function app.withdraw_rfq_response(
  p_rfq_response_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.rfq_responses
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_response app.rfq_responses;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to withdraw a response' using errcode = 'check_violation';
  end if;

  select * into v_response from app.rfq_responses where id = p_rfq_response_id for update;
  if not found then
    raise exception 'rfq_response_not_found: %', p_rfq_response_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_response.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_response.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_response.record_version <> p_expected_version then
    raise exception 'stale_version: rfq response % expected version % but found %', p_rfq_response_id, p_expected_version, v_response.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_response.status <> 'submitted' then
    raise exception 'invalid_transition: rfq response % is % and cannot be withdrawn', p_rfq_response_id, v_response.status
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.rfq_responses where rfq_invitation_id = v_response.rfq_invitation_id and version > v_response.version) then
    raise exception 'not_latest_response_version: a newer response version exists for this invitation -- withdraw the latest version' using errcode = 'check_violation';
  end if;

  update app.rfq_responses
  set status = 'withdrawn'
  where id = p_rfq_response_id and record_version = p_expected_version
  returning * into v_response;
  if not found then
    raise exception 'stale_version: rfq response % target row was concurrently modified (expected version %)', p_rfq_response_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  update app.rfq_invitations set status = 'invited' where id = v_response.rfq_invitation_id and status = 'responded';

  perform app.capture_audit_event(
    v_response.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_rfq_response',
    'app.rfq_responses', v_response.id, 'success', p_reason, null, jsonb_build_object('status', v_response.status)
  );

  return v_response;
end;
$$;

-- ===========================================================================
-- 14. Read RPCs (PRC:View, design notes 3-4). Every one reconstructs its own
--     projection directly against the base table, never selecting from a
--     directory view whose own row filter resolves auth.uid() implicitly --
--     PRC-256's own C-06 lesson, applied here from the start.
-- ===========================================================================

create function app.get_rfq(p_rfq_id uuid, p_actor_auth_user_id uuid)
returns app.rfqs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
  v_row app.rfqs;
begin
  select tenant_id into v_tenant_id from app.rfqs where id = p_rfq_id;
  if v_tenant_id is null then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app.rfqs where id = p_rfq_id;
  return v_row;
end;
$$;

create function app.list_rfqs(p_tenant_id uuid, p_status text, p_actor_auth_user_id uuid, p_limit integer default 50)
returns setof app.rfqs
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
  if p_status is not null and p_status not in ('draft', 'issued', 'closed', 'cancelled', 'superseded') then
    raise exception 'invalid_status_filter: %', p_status using errcode = 'check_violation';
  end if;

  return query
  select * from app.rfqs
  where tenant_id = p_tenant_id
    and ((p_status is not null and status = p_status) or (p_status is null and status <> 'superseded'))
  order by created_at desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_rfqs is 'PRC-257: server-side clamped to <=200 rows. With no p_status filter, superseded (historical, non-current) versions are excluded by default -- pass p_status=''superseded'' explicitly to see them. Mirrors app.list_sourcing_requests'' own disclosed .limit(200) bound.';

create function app.list_rfq_requirement_lines(p_rfq_id uuid, p_actor_auth_user_id uuid)
returns setof app.rfq_requirement_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.rfqs where id = p_rfq_id;
  if v_tenant_id is null then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.rfq_requirement_lines where rfq_id = p_rfq_id order by line_no;
end;
$$;

create function app.list_rfq_invitations(p_rfq_id uuid, p_actor_auth_user_id uuid)
returns setof app.rfq_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.rfqs where id = p_rfq_id;
  if v_tenant_id is null then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.rfq_invitations where rfq_id = p_rfq_id order by invited_at;
end;
$$;

create function app.list_rfq_clarifications(p_rfq_id uuid, p_actor_auth_user_id uuid)
returns setof app.rfq_clarifications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.rfqs where id = p_rfq_id;
  if v_tenant_id is null then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.rfq_clarifications where rfq_id = p_rfq_id order by asked_at;
end;
$$;

create function app.list_rfq_responses(p_rfq_id uuid, p_actor_auth_user_id uuid)
returns setof app.rfq_responses_directory
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.rfqs where id = p_rfq_id;
  if v_tenant_id is null then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    r.id, r.tenant_id, r.rfq_id, r.rfq_invitation_id, r.vendor_master_id, r.version, r.previous_version_id, r.status,
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.currency else null end,
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.total_amount else null end,
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.validity_until else null end,
    r.lead_time_days,
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.commercial_terms else '{}'::jsonb end,
    not app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id),
    r.capture_mode, r.source_message_ref, r.received_at, r.vendor_confirmed, r.late_capture, r.late_reason, r.comparison_eligible,
    r.idempotency_key, r.actor_auth_user_id, r.actor_label, r.record_version, r.created_at, r.updated_at
  from app.rfq_responses r
  where r.rfq_id = p_rfq_id
  order by r.created_at;
end;
$$;

comment on function app.list_rfq_responses is 'PRC-257: comparison read. Masks currency/total_amount/validity_until/commercial_terms behind PRC:View cost, threading p_actor_auth_user_id explicitly into app.has_prc_view_cost -- never selecting from app.rfq_responses_directory itself (whose own row filter/mask default to auth.uid()), mirroring app.search_vendor_rates (PRC-255) / app.list_sourcing_requests (PRC-256) exactly.';

create function app.list_rfq_response_attachments(p_rfq_response_id uuid, p_actor_auth_user_id uuid)
returns setof app.rfq_response_attachments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.rfq_responses where id = p_rfq_response_id;
  if v_tenant_id is null then
    raise exception 'rfq_response_not_found: %', p_rfq_response_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.rfq_response_attachments where rfq_response_id = p_rfq_response_id order by created_at;
end;
$$;

create function app.get_rfq_history(p_rfq_id uuid, p_actor_auth_user_id uuid)
returns setof app.rfq_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.rfqs where id = p_rfq_id;
  if v_tenant_id is null then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.rfq_events where rfq_id = p_rfq_id order by occurred_at;
end;
$$;

-- ===========================================================================
-- 15. RLS -- hardened default-deny form, identical shape to every PRC-25x
--     table.
-- ===========================================================================

alter table app.rfqs enable row level security;
alter table app.rfq_requirement_lines enable row level security;
alter table app.rfq_invitations enable row level security;
alter table app.rfq_clarifications enable row level security;
alter table app.rfq_responses enable row level security;
alter table app.rfq_response_attachments enable row level security;
alter table app.rfq_events enable row level security;

create policy rfqs_select_scoped on app.rfqs
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy rfq_requirement_lines_select_scoped on app.rfq_requirement_lines
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy rfq_invitations_select_scoped on app.rfq_invitations
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy rfq_clarifications_select_scoped on app.rfq_clarifications
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy rfq_responses_select_scoped on app.rfq_responses
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy rfq_response_attachments_select_scoped on app.rfq_response_attachments
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy rfq_events_select_scoped on app.rfq_events
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 16. Grants (design note 12, ERR-2026-004).
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.rfqs to authenticated, service_role;
grant select on app.rfq_requirement_lines to authenticated, service_role;
grant select on app.rfq_invitations to authenticated, service_role;
grant select on app.rfq_clarifications to authenticated, service_role;

-- Column-restricted grant (mirrors app.sourcing_requests'' own proven
-- technique) -- currency/total_amount/validity_until/commercial_terms
-- withheld from `authenticated`, only reachable through app.rfq_responses_
-- directory's / app.list_rfq_responses' own has_prc_view_cost mask.
grant select (
  id, tenant_id, rfq_id, rfq_invitation_id, vendor_master_id, version, previous_version_id, status,
  lead_time_days, capture_mode, source_message_ref, received_at, vendor_confirmed, late_capture, late_reason, comparison_eligible,
  idempotency_key, actor_auth_user_id, actor_label, record_version, created_at, updated_at
) on app.rfq_responses to authenticated;
grant select on app.rfq_responses to service_role;

grant select on app.rfq_response_attachments to authenticated, service_role;
grant select on app.rfq_events to authenticated, service_role;

grant select on app.rfqs_directory to authenticated, service_role;
grant select on app.rfq_requirement_lines_directory to authenticated, service_role;
grant select on app.rfq_invitations_directory to authenticated, service_role;
grant select on app.rfq_clarifications_directory to authenticated, service_role;
grant select on app.rfq_responses_directory to authenticated, service_role;

grant execute on function app.next_rfq_number(uuid) to service_role;

grant execute on function app.draft_rfq_from_sourcing(uuid, uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.revise_rfq(uuid, numeric, numeric, text, text, text, text, integer, uuid, text) to authenticated, service_role;

grant execute on function app.issue_rfq(uuid, timestamptz, integer, uuid, text) to authenticated, service_role;
grant execute on function app.invite_additional_rfq_vendor(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.extend_rfq_deadline(uuid, timestamptz, integer, uuid, text) to authenticated, service_role;
grant execute on function app.close_rfq_for_comparison(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_rfq(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decline_rfq_invitation(uuid, text, integer, uuid, text) to authenticated, service_role;

grant execute on function app.record_rfq_clarification(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.answer_rfq_clarification(uuid, text, integer, uuid, text) to authenticated, service_role;

grant execute on function app.submit_rfq_response(uuid, text, numeric, timestamptz, integer, jsonb, text, text, timestamptz, boolean, uuid[], text, text, uuid, text) to authenticated, service_role;
grant execute on function app.withdraw_rfq_response(uuid, text, integer, uuid, text) to authenticated, service_role;

grant execute on function app.get_rfq(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_rfqs(uuid, text, uuid, integer) to authenticated, service_role;
grant execute on function app.list_rfq_requirement_lines(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_rfq_invitations(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_rfq_clarifications(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_rfq_responses(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_rfq_response_attachments(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_rfq_history(uuid, uuid) to authenticated, service_role;
