-- Procurement capability PRC-256 (Sourcing, CG-S11-PRC-007). The sixth Phase 6
-- checkpoint. Implements source-linked sourcing requests, vendor discovery,
-- candidate eligibility with explainable reasons, and human-owned shortlist
-- curation -- a source-versioned shortlist handoff surface a later, separate
-- Procurement RFQ capability (Prompt 257, NOT built here) can read from. Extends
-- app.vendor_profiles/app.vendor_services/app.vendor_coverage (PRC-251),
-- app.get_vendor_compliance_eligibility (PRC-253), and reads app.costing_requests
-- (COM-148) / app.shipment_orders (OPS-169) as read-only demand sources -- never
-- modifies any of them. Per ADR-0020, canonical vendor identity is
-- app.master_records where master_type_code='vendor', reached via
-- app.vendor_profiles.master_record_id -- this migration never invents a second
-- vendor-shaped table.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Demand inheritance is a point-in-time snapshot, never a live re-derivation**
--    (Prompt 256 §24 "no silent re-entry or conflicting copy"), mirroring
--    app.costing_requests.requirements_snapshot's own established convention.
--    `demand_snapshot` holds the FULL source row/object at creation time;
--    typed mirror columns (service_type/origin_lane/destination_lane/... ) are
--    extracted once, at creation, for indexed querying -- never re-synced if the
--    source later changes (costing_requests/shipment_orders are themselves
--    effectively immutable post-creation in this repository -- a costing_request
--    revision creates a NEW row via revised_from_id, and no shipment_orders RPC
--    rewrites its own service_type/origin/destination in place).
-- 2. **requirements_snapshot's real key shape** (confirmed by direct inspection of
--    `app.request_costing`/`app.get_opportunity_costing_readiness`,
--    20260724090000/20260723210000, and their own db-test fixture) is
--    `{service_type, cargo_description, origin, destination, target_ready_date}`
--    -- NO mode/weight/volume/currency/budget_amount key exists anywhere in a real
--    costing_request's own snapshot. `create_sourcing_request_from_costing`
--    therefore only ever populates service_type/origin_lane/destination_lane
--    (required, else `source_demand_incomplete`) and a best-effort
--    requested_pickup_at parsed from target_ready_date (any cast failure is
--    swallowed to null, never raised -- a malformed date string is not grounds to
--    block sourcing). mode/cargo_weight_*/cargo_volume_*/currency/budget_amount
--    stay null for every costing-sourced request today -- a disclosed, real
--    limitation of the upstream contract, not a bug in this migration. The
--    extraction code defensively also attempts mode/currency/budget_amount keys
--    (a no-op today, forward-compatible if COM-148's own snapshot shape ever
--    grows those keys).
-- 3. **app.shipment_orders' own real columns** (confirmed by direct inspection of
--    20260727100000_create_operations_shipment_order.sql) ARE reliably
--    service_type/mode/origin/destination (all NOT NULL) plus
--    basis_weight_kg/basis_volume_cbm/planned_pickup_at/planned_delivery_at
--    (nullable). `create_sourcing_request_from_operational_demand` maps
--    basis_weight_kg/basis_volume_cbm onto cargo_weight_max/cargo_volume_max
--    (never cargo_*_min) -- read as "sourcing needs a vendor able to handle UP TO
--    this much cargo," the natural sourcing-side reading of a single known
--    quantity, not a range boundary. currency/budget_amount have no shipment_orders
--    equivalent at all and stay null. demand_snapshot is the `to_jsonb` of the
--    source shipment_orders row MINUS `consignee_snapshot`/`notify_party_snapshot`
--    (design note 16a, a post-review fix -- those two fields carry real customer/
--    consignee identity governed by the source's own record-scoped RLS, which
--    Sourcing's tenant+PRC:View scope does not replicate; there is no separate
--    "requirements" sub-object on that table the way costing_requests has one).
-- 4. **Status machine is exactly the nine-transition set the task names, no
--    extra states.** costing_request/operational_demand-sourced requests are
--    created directly into 'open' (already-trustworthy canonical source data, no
--    separate submit step); only a 'proactive' request starts 'draft' and needs
--    `submit_sourcing_request` to reach 'open'. This mirrors PRC-251's own
--    "begin_review is optional, decide accepts submitted OR under_review" spirit
--    of not forcing a state transition step that adds no real governance value
--    for already-vetted source data.
-- 5. **RBAC mapping reuses the 12 already-seeded PRC actions exclusively** -- no
--    new `app.permissions` row is seeded by this migration. Create = the three
--    creation RPCs. Edit = submit_sourcing_request (mirrors
--    app.submit_vendor_profile_for_review/app.submit_vendor_assessment_for_review's
--    own "submit a draft" = Edit precedent, confirmed by direct inspection before
--    deciding), evaluate_sourcing_candidate_eligibility (a recompute is a write),
--    shortlist_sourcing_candidate for an ELIGIBLE candidate or any un-shortlist,
--    submit_sourcing_shortlist, close_sourcing_request_no_source,
--    cancel_sourcing_request (mirrors app.archive_vendor_profile/
--    app.archive_vendor_compliance_requirement's own "terminal-with-mandatory-
--    reason administrative closure = Edit" precedent -- PRC has no dedicated
--    Close/Reopen action). Override = override_sourcing_request_constraints,
--    shortlist_sourcing_candidate for an EXCLUDED candidate (a governed exception
--    -- "no algorithm autonomously selects a vendor" extends to "excluded
--    candidates need a human override to even be considered"), reopen_sourcing_
--    request (mirrors app.reactivate_vendor_profile/app.suspend_vendor_profile's
--    own "governed exception path, mandatory reason" precedent).
--    View = every read RPC.
-- 6. **shortlist_reason is unconditionally required (non-empty) whenever
--    shortlisted=true, at both the table CHECK and the RPC level** -- the spec's
--    own column definition ("CHECK: required non-empty when shortlisted=true")
--    applies regardless of candidate eligibility; what DIFFERS by eligibility is
--    the AUTHORITY required (PRC:Edit for an eligible candidate, PRC:Override for
--    an excluded one), never whether a reason is needed at all. Un-shortlisting
--    (p_shortlisted=false) needs PRC:Edit only, reason optional, and the CHECK is
--    vacuous in that direction (only fires when shortlisted=true).
-- 7. **Re-evaluating eligibility never silently reverts a human's prior shortlist
--    decision.** The UPSERT in app.evaluate_sourcing_candidate_eligibility updates
--    only eligible/exclusion_reasons/evaluation_snapshot on conflict --
--    shortlisted/shortlist_reason/shortlisted_by/shortlisted_at are NEVER touched
--    by a re-evaluation. A candidate that becomes ineligible while still
--    shortlisted is a real, surfaced signal (visible via eligible=false AND
--    shortlisted=true simultaneously in the directory read) -- not auto-cleared.
-- 8. **Eligibility dimensions actually evaluated: vendor_not_active (defensive
--    completeness only -- structurally unreachable since the vendor scan itself
--    filters lifecycle_status='active'), service_mismatch, coverage_mismatch,
--    compliance_ineligible.** `has_active_rate` is informational-only in
--    evaluation_snapshot, NEVER an exclusion reason (Prompt 256's own explicit
--    "RFQ exists precisely to solicit quotes from vendors without one yet").
--    **Capacity/availability (PRC-262, Vendor Capacity and Availability) does not
--    exist yet and is deliberately NOT evaluated** -- disclosed here exactly the
--    way PRC-255 disclosed deferring a tax dimension to FIN-195, not fabricated
--    against data that does not exist. **No vendor cargo-type/restricted-cargo
--    capability master exists anywhere in this repository** -- no such check is
--    built; a request-level cargo restriction flag is deliberately NOT modeled
--    either (the task's own "prefer not modeling it and disclosing the gap" over
--    a column that would silently claim to be enforced when it isn't).
--    Recomputing eligibility calls the already-PRC:View-gated
--    app.get_vendor_compliance_eligibility per candidate vendor -- the calling
--    actor must therefore hold BOTH PRC:Edit (this RPC's own gate) AND PRC:View
--    (the composed read's own gate), mirroring app.commit_vendor_rate_import_job's
--    own established "compose two independently-gated calls, both real" pattern
--    (PRC-255 design note 11) rather than a new bypass.
-- 9. **The vendor scan is bounded to 500 active vendors per call**, matching the
--    task's own explicit instruction. Hitting the bound is disclosed via a real
--    `raise warning` (visible in Postgres logs/psql output), not a silent
--    truncation -- the function's own fixed `returns setof app.sourcing_candidates`
--    contract has no row for a `more_remaining` flag the way
--    `purge_tracking_telemetry_history`'s own scalar-record return shape does, so a
--    logged warning is this checkpoint's own disclosed, lighter-weight equivalent.
-- 10. **The override RPC only structurally validates the two NUMERIC caps
--     (cargo_weight_max/cargo_volume_max) against "must be >= the currently stored
--     value, else constraint_narrowing_not_allowed" -- read literally: the check
--     only fires when a value is ALREADY stored (comparing against nothing is
--     vacuously satisfied, so a null-to-value transition on either numeric field
--     always succeeds; a value-to-smaller-value transition is blocked).**
--     `p_destination_lane` is free text -- there is no structural way to prove one
--     lane string is "wider" than another, so it is applied directly when
--     supplied (governed procedurally: PRC:Override, mandatory reason, an audit
--     event, never a structural comparison) -- disclosed here as a deliberate
--     scope boundary, not an oversight. `app.sourcing_request_events` gains one
--     column beyond the task's own abbreviated column list, `evidence_ref text`
--     (present on the very table this task told this migration to mirror "the
--     exact shape" of, `app.vendor_profile_lifecycle_events`, but omitted from the
--     task's own explicit list) -- used exactly once, to carry
--     `p_override_expires_at` on the override RPC's own event row, resolving the
--     task's own explicit "evidence_ref or reason column -- your choice, document
--     it" instruction in favor of evidence_ref (reason already carries the human
--     rationale; conflating a timestamp into that same free-text field would be
--     worse). The override event's own from_status/to_status are both 'open' (no
--     real state transition occurs -- a constraint widening, not a status change)
--     -- still written, matching every "Lifecycle transitions" RPC's own
--     obligation to append an event row.
-- 11. **Masking**: `budget_amount` is cost-sensitive (Prompt 256's own explicit
--     instruction, mirroring `vendor_rate_versions.base_amount`) -- masked in
--     `app.sourcing_requests_directory` behind the already-seeded, already-proven
--     `app.has_prc_view_cost` (PRC-252's function, reused, never redefined --
--     confirmed by direct inspection before writing this migration).
--     `app.sourcing_candidates` carries no cost-sensitive field at all (no
--     amount/currency column on that table) -- `app.sourcing_candidates_directory`
--     is therefore a PLAIN, unmasked, tenant-scoped view, kept only for the
--     "always read through a view, never the base table" naming convention this
--     repository holds itself to everywhere else, not because masking is needed
--     here. Both views' row filters use the hardened pattern-5 predicate
--     (`has_active_tenant_membership(...) and not actor_holds_customer_user_layer(...)`,
--     copied verbatim from `app.vendor_rate_versions_directory`'s own row filter in
--     20260730620000) from creation -- a customer_user-layer principal gets ZERO
--     rows from either view, not merely masked ones.
-- 12. **The touch trigger is a real `before update` trigger** (record_version += 1,
--     updated_at := now()), per the task's own explicit instruction -- one shared
--     function, `app.touch_sourcing_row`, reused across both
--     `app.sourcing_requests` and `app.sourcing_candidates` (the same "one shared
--     touch trigger for near-identical tables" precedent PRC-251 already
--     established for its own four child tables), mirroring
--     `app.touch_shipment_orders_row`'s own established main-entity-table
--     precedent (OPS-169) rather than PRC-251's own alternative "RPC manually sets
--     record_version+1" convention -- both patterns coexist in this repository
--     already; this checkpoint follows the one the task text explicitly names.
--     Every transition RPC below therefore omits `record_version = record_version
--     + 1`/`updated_at = now()` from its own UPDATE SET list (the trigger handles
--     both), but every terminal UPDATE still carries the mandatory
--     `record_version = p_expected_version`-scoped WHERE and post-UPDATE "if not
--     found" `stale_version` re-check (ground rule 2) -- the trigger changes WHO
--     increments the counter, never whether the optimistic-concurrency guard
--     itself is enforced.
-- 13. **Idempotency-key replay compares every load-bearing INPUT field, not a
--     subset** (ground rule 4): the two source-linked creation RPCs compare
--     source_costing_request_id/source_shipment_order_id, owner_user_id, and
--     sla_due_at (the only genuine caller-supplied inputs -- every typed mirror
--     column is DERIVED from the immutable source row, so comparing the source id
--     alone already covers them); the proactive creation RPC compares every one of
--     its thirteen caller-supplied fields (service_type, mode, origin_lane,
--     destination_lane, cargo_weight_min/max, cargo_volume_min/max,
--     requested_pickup_at/delivery_at, currency, budget_amount, owner_user_id,
--     sla_due_at) since none of them are derived. Every nested `unique_violation`
--     race-recovery handler is scoped by `get stacked diagnostics constraint_name`
--     (ground rule 5) -- never a bare catch-all.
-- 14. **No notification is added.** Prompt 256 §20/§28 (the "detailed
--     implementation tasks"/"tests to create" sections) name no notification
--     requirement for Sourcing itself, unlike some other Phase 6 prompts that
--     explicitly call one out -- re-read in full before this migration was
--     written; no `queue_notification`-shaped call is added here, matching the
--     task's own explicit "do not add one unless the spec text explicitly
--     requires it for Sourcing itself" instruction.
-- 15. Per ERR-2026-004: this migration carries its own explicit `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants,
--     the standing per-migration convention since PLT-118.
-- 16. **Post-implementation adversarial review fixes** (this migration was corrected
--     in place before being applied anywhere -- not a follow-up harden migration,
--     the same "not yet applied, so fix directly" precedent PRC-255's own §10.1
--     established). Full disposition: `docs/build-log/phase-06/PRC-256.md` §10.
--     (a) `demand_snapshot` carried the FULL to_jsonb of the source row with no
--     masking at all -- two distinct sensitive-data leaks, both closed. First,
--     `create_sourcing_request_from_operational_demand` no longer stores
--     `consignee_snapshot`/`notify_party_snapshot` (real customer/consignee
--     identity, confirmed by direct inspection of `app.shipment_orders`, whose OWN
--     RLS scopes them by `can_access_record`/org-unit, a per-record scope Sourcing
--     never inherits) -- excluded at WRITE time via the standard jsonb `-` operator,
--     since sourcing has no functional use for them (every field it needs is
--     already a typed mirror column). Second, `create_proactive_sourcing_request`'s
--     own `demand_snapshot` legitimately carries `budget_amount` for an authorized
--     viewer's audit trail, so that key is instead masked at READ time in the
--     directory view and both read RPCs, using the exact same
--     `app.has_prc_view_cost` case-when shape design note 11 already established
--     for the typed `budget_amount` column -- never removed from storage, since a
--     PRC:View cost holder must still be able to see it.
--     (b) `app.shortlist_sourcing_candidate` read the parent `sourcing_requests.status`
--     via a plain, UNLOCKED `select` -- both a concurrency gap (a concurrent
--     `submit_sourcing_shortlist`/`close_sourcing_request_no_source`/
--     `cancel_sourcing_request`, each of which DOES take `for update` on the same
--     row, could commit a status change underneath this read) and a pre-authorization
--     information leak (the parent's real status, including for a cross-tenant
--     caller with zero role assignment, was disclosed via `invalid_transition`
--     BEFORE `evaluate_permission` ever ran -- every sibling transition RPC in this
--     migration checks permission immediately after its own existence/lock check,
--     making this function the sole outlier). Fixed by reordering (permission is now
--     evaluated before the parent row is even read) AND locking the parent row
--     `for update` once eligibility is confirmed -- both using the exact `for
--     update` shape every sibling transition RPC already uses, never a new pattern.
--     (c) `app.evaluate_sourcing_candidate_eligibility` had the identical unlocked
--     parent-status read, checked once before its own up-to-500-vendor loop with no
--     re-check -- a concurrent `cancel_sourcing_request`/`close_sourcing_request_no_
--     source`/`submit_sourcing_shortlist` could commit mid-scan, leaving freshly
--     written `sourcing_candidates` rows for a request that is no longer open. Fixed
--     by adding a `for update` re-check of the parent's status AFTER the loop
--     completes (not before it, and not held for the loop's own duration) -- raising
--     `invalid_transition` there rolls back the whole call's candidate upserts in the
--     same transaction. Locking only at the very end, after every candidate row this
--     call itself touches is already locked, preserves the SAME lock order
--     `shortlist_sourcing_candidate` uses (candidate row(s) before the parent
--     request row) -- avoiding a new deadlock class a leading `for update` here
--     would otherwise create against a concurrent `shortlist_sourcing_candidate`
--     call on one of the same candidates.
--     (d) No non-negativity CHECK existed for `cargo_weight_min`/`cargo_weight_max`/
--     `cargo_volume_min`/`cargo_volume_max` (only the relative max>=min checks) --
--     a negative value could persist via either `create_proactive_sourcing_request`
--     or, more subtly, via `override_sourcing_request_constraints`'s own
--     null-to-value-always-widens rule. Four new table CHECK constraints close this
--     at the single authoritative point every insert/update path shares, mirroring
--     `budget_amount`'s own existing `>= 0` CHECK immediately above them.
--     (e) Two missing indexes named explicitly in Prompt 256 §17 ("service/mode/...
--     date") added: `(tenant_id, mode)` and `(tenant_id, created_at desc)` -- the
--     latter also matching `list_sourcing_requests`' own `order by created_at desc`.

-- ===========================================================================
-- 1. app.sourcing_requests (design notes 1-4, 11-13).
-- ===========================================================================

create table app.sourcing_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid references app.org_units (id),
  source_type text not null,
  source_costing_request_id uuid references app.costing_requests (id),
  source_shipment_order_id uuid references app.shipment_orders (id),
  demand_snapshot jsonb not null default '{}'::jsonb,
  service_type text not null,
  mode text,
  origin_lane text not null,
  destination_lane text not null,
  cargo_weight_min numeric(14, 3),
  cargo_weight_max numeric(14, 3),
  cargo_volume_min numeric(14, 3),
  cargo_volume_max numeric(14, 3),
  requested_pickup_at timestamptz,
  requested_delivery_at timestamptz,
  currency text,
  budget_amount numeric(14, 2),
  status text not null default 'draft',
  owner_user_id uuid references auth.users (id),
  sla_due_at timestamptz,
  closed_reason text,
  shortlist_locked_at timestamptz,
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sourcing_requests_source_type_check check (source_type in ('costing_request', 'operational_demand', 'proactive')),
  constraint sourcing_requests_status_check check (status in ('draft', 'open', 'shortlisted', 'closed_no_source', 'cancelled')),
  constraint sourcing_requests_service_type_check check (length(trim(service_type)) > 0),
  constraint sourcing_requests_origin_lane_check check (length(trim(origin_lane)) > 0),
  constraint sourcing_requests_destination_lane_check check (length(trim(destination_lane)) > 0),
  constraint sourcing_requests_source_shape_check check (
    (source_type = 'costing_request' and source_costing_request_id is not null and source_shipment_order_id is null)
    or (source_type = 'operational_demand' and source_shipment_order_id is not null and source_costing_request_id is null)
    or (source_type = 'proactive' and source_costing_request_id is null and source_shipment_order_id is null)
  ),
  constraint sourcing_requests_closed_reason_check check (
    (status in ('closed_no_source', 'cancelled') and closed_reason is not null and length(trim(closed_reason)) > 0)
    or (status not in ('closed_no_source', 'cancelled'))
  ),
  constraint sourcing_requests_cargo_weight_range_check check (cargo_weight_max is null or cargo_weight_min is null or cargo_weight_max >= cargo_weight_min),
  constraint sourcing_requests_cargo_volume_range_check check (cargo_volume_max is null or cargo_volume_min is null or cargo_volume_max >= cargo_volume_min),
  constraint sourcing_requests_cargo_weight_min_nonneg_check check (cargo_weight_min is null or cargo_weight_min >= 0),
  constraint sourcing_requests_cargo_weight_max_nonneg_check check (cargo_weight_max is null or cargo_weight_max >= 0),
  constraint sourcing_requests_cargo_volume_min_nonneg_check check (cargo_volume_min is null or cargo_volume_min >= 0),
  constraint sourcing_requests_cargo_volume_max_nonneg_check check (cargo_volume_max is null or cargo_volume_max >= 0),
  constraint sourcing_requests_budget_amount_check check (budget_amount is null or budget_amount >= 0),
  constraint sourcing_requests_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.sourcing_requests is
  'PRC-256: one row per sourcing effort, source-linked to a Commercial costing request (COM-148) or an Operations shipment order (OPS-169), or proactive (no source). demand_snapshot is the FULL point-in-time copy of whatever source fields were inherited (design note 1) -- authoritative, never live re-derived, mirroring app.costing_requests.requirements_snapshot''s own convention. Typed mirror columns (service_type/origin_lane/destination_lane are NOT NULL, everything else is a best-effort extraction -- design notes 2-3) exist for indexed querying only.';

create index sourcing_requests_tenant_status_idx on app.sourcing_requests (tenant_id, status);
create index sourcing_requests_tenant_owner_idx on app.sourcing_requests (tenant_id, owner_user_id);
create index sourcing_requests_tenant_sla_idx on app.sourcing_requests (tenant_id, sla_due_at) where status in ('draft', 'open');
create index sourcing_requests_tenant_service_idx on app.sourcing_requests (tenant_id, service_type);
create index sourcing_requests_tenant_mode_idx on app.sourcing_requests (tenant_id, mode);
create index sourcing_requests_tenant_lanes_idx on app.sourcing_requests (tenant_id, origin_lane, destination_lane);
create index sourcing_requests_tenant_created_idx on app.sourcing_requests (tenant_id, created_at desc);
create index sourcing_requests_source_costing_idx on app.sourcing_requests (source_costing_request_id) where source_costing_request_id is not null;
create index sourcing_requests_source_shipment_idx on app.sourcing_requests (source_shipment_order_id) where source_shipment_order_id is not null;

create function app.touch_sourcing_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

comment on function app.touch_sourcing_row is 'PRC-256 design note 12: shared before-update touch trigger for app.sourcing_requests and app.sourcing_candidates -- record_version += 1, updated_at := now(). Every transition RPC''s own terminal UPDATE relies on this rather than setting either column itself; the record_version-scoped WHERE clause and post-UPDATE stale_version re-check remain mandatory regardless (ground rule 2).';

create trigger sourcing_requests_touch_row
  before update on app.sourcing_requests
  for each row
  execute function app.touch_sourcing_row();

-- ===========================================================================
-- 2. app.sourcing_request_events -- append-only lifecycle history (design note 10).
-- ===========================================================================

create table app.sourcing_request_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  sourcing_request_id uuid not null references app.sourcing_requests (id),
  from_status text not null,
  to_status text not null,
  reason text,
  evidence_ref text,
  actor_auth_user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now()
);

comment on table app.sourcing_request_events is
  'PRC-256: append-only lifecycle transition history, one row per real transition (plus the constraint-override RPC''s own same-status event, design note 10), written by every transition RPC in the same transaction as the state change. evidence_ref (design note 10) mirrors app.vendor_profile_lifecycle_events'' own column of the same name (the precedent this table is told to mirror "the exact shape" of), used here to carry app.override_sourcing_request_constraints'' own p_override_expires_at.';

create index sourcing_request_events_request_idx on app.sourcing_request_events (sourcing_request_id, occurred_at);

-- ===========================================================================
-- 3. app.sourcing_candidates (design notes 6-9).
-- ===========================================================================

create table app.sourcing_candidates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  sourcing_request_id uuid not null references app.sourcing_requests (id),
  vendor_master_id uuid not null references app.master_records (id),
  eligible boolean not null,
  exclusion_reasons text[] not null default '{}'::text[],
  evaluation_snapshot jsonb not null default '{}'::jsonb,
  shortlisted boolean not null default false,
  shortlist_reason text,
  shortlisted_by text,
  shortlisted_at timestamptz,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sourcing_candidates_exclusion_reasons_check check (
    exclusion_reasons <@ array['vendor_not_active', 'service_mismatch', 'coverage_mismatch', 'compliance_ineligible']::text[]
  ),
  constraint sourcing_candidates_eligible_consistency_check check (
    (eligible and cardinality(exclusion_reasons) = 0) or (not eligible and cardinality(exclusion_reasons) > 0)
  ),
  constraint sourcing_candidates_shortlist_reason_check check (
    (shortlisted and shortlist_reason is not null and length(trim(shortlist_reason)) > 0) or not shortlisted
  ),
  constraint sourcing_candidates_unique_vendor unique (sourcing_request_id, vendor_master_id)
);

comment on table app.sourcing_candidates is
  'PRC-256: one row per (sourcing_request, candidate vendor), written/upserted only by app.evaluate_sourcing_candidate_eligibility (eligible/exclusion_reasons/evaluation_snapshot) and app.shortlist_sourcing_candidate (shortlisted/shortlist_reason/shortlisted_by/shortlisted_at) -- a re-evaluation NEVER clears a prior human shortlist decision (design note 7). exclusion_reasons is drawn from a fixed, documented four-value set (design note 8); has_active_rate lives only in evaluation_snapshot, informational, never an exclusion reason.';

create index sourcing_candidates_request_idx on app.sourcing_candidates (sourcing_request_id);
create index sourcing_candidates_tenant_idx on app.sourcing_candidates (tenant_id);
create index sourcing_candidates_vendor_idx on app.sourcing_candidates (vendor_master_id);

create trigger sourcing_candidates_touch_row
  before update on app.sourcing_candidates
  for each row
  execute function app.touch_sourcing_row();

-- Structural enforcement (defense in depth) -- mirrors
-- app.enforce_vendor_rate_version_vendor_identity (PRC-255) exactly.
create function app.enforce_sourcing_candidate_vendor_identity()
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

create trigger sourcing_candidates_enforce_vendor_identity
  before insert or update of vendor_master_id, tenant_id on app.sourcing_candidates
  for each row
  execute function app.enforce_sourcing_candidate_vendor_identity();

-- ===========================================================================
-- 4. Masked/plain directory views (design note 11).
-- ===========================================================================

create view app.sourcing_requests_directory
as
select
  r.id,
  r.tenant_id,
  r.org_unit_id,
  r.source_type,
  r.source_costing_request_id,
  r.source_shipment_order_id,
  -- ADVERSARIAL REVIEW FIX (design note 16a): a proactive request's own
  -- demand_snapshot carries budget_amount verbatim (jsonb_build_object at creation)
  -- -- masked here with the exact same has_prc_view_cost gate the typed column
  -- immediately below already uses, closing the bypass a caller could otherwise
  -- read the real amount through even with cost_masked=true on the typed column.
  case when app.has_prc_view_cost(r.tenant_id) then r.demand_snapshot else r.demand_snapshot - 'budget_amount' end as demand_snapshot,
  r.service_type,
  r.mode,
  r.origin_lane,
  r.destination_lane,
  r.cargo_weight_min,
  r.cargo_weight_max,
  r.cargo_volume_min,
  r.cargo_volume_max,
  r.requested_pickup_at,
  r.requested_delivery_at,
  r.currency,
  case when app.has_prc_view_cost(r.tenant_id) then r.budget_amount else null end as budget_amount,
  not app.has_prc_view_cost(r.tenant_id) as cost_masked,
  r.status,
  r.owner_user_id,
  r.sla_due_at,
  r.closed_reason,
  r.shortlist_locked_at,
  r.record_version,
  r.created_by,
  r.created_at,
  r.updated_at
from app.sourcing_requests r
where (app.has_active_tenant_membership(r.tenant_id) and not app.actor_holds_customer_user_layer(r.tenant_id)) or app.is_supreme_admin();

comment on view app.sourcing_requests_directory is 'PRC-256: field-masked projection of app.sourcing_requests -- budget_amount nulled (cost_masked=true) for a caller lacking PRC:View cost, exactly like app.vendor_rate_versions_directory''s base_amount. Row filter uses the hardened pattern-5 predicate from creation (a customer_user-layer principal gets zero rows).';

create view app.sourcing_candidates_directory
as
select c.*
from app.sourcing_candidates c
where (app.has_active_tenant_membership(c.tenant_id) and not app.actor_holds_customer_user_layer(c.tenant_id)) or app.is_supreme_admin();

comment on view app.sourcing_candidates_directory is 'PRC-256: PLAIN (unmasked) projection of app.sourcing_candidates -- no cost-sensitive field exists on this table (design note 11), so no CASE-WHEN masking is applied; the view exists only to keep the "always read through a _directory view, never the base table" convention every PRC-25x checkpoint holds itself to. Row filter uses the same hardened pattern-5 predicate as app.sourcing_requests_directory.';

-- ===========================================================================
-- 5. Creation RPCs (PRC:Create, design notes 1-4, 13).
-- ===========================================================================

create function app.create_sourcing_request_from_costing(
  p_tenant_id uuid,
  p_costing_request_id uuid,
  p_owner_user_id uuid,
  p_sla_due_at timestamptz,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_costing app.costing_requests;
  v_existing app.sourcing_requests;
  v_snapshot jsonb;
  v_service_type text;
  v_origin_lane text;
  v_destination_lane text;
  v_pickup_at timestamptz;
  v_constraint_name text;
  v_request app.sourcing_requests;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;

  select * into v_costing from app.costing_requests where id = p_costing_request_id;
  if not found then
    raise exception 'costing_request_not_found: %', p_costing_request_id using errcode = 'no_data_found';
  end if;
  if v_costing.tenant_id <> p_tenant_id then
    raise exception 'tenant_mismatch: costing request % does not belong to tenant %', p_costing_request_id, p_tenant_id
      using errcode = 'check_violation';
  end if;
  if v_costing.status in ('cancelled', 'superseded') then
    raise exception 'invalid_source_status: costing request % is % and cannot source a sourcing request', p_costing_request_id, v_costing.status
      using errcode = 'check_violation';
  end if;

  v_snapshot := v_costing.requirements_snapshot;
  v_service_type := nullif(v_snapshot ->> 'service_type', '');
  v_origin_lane := nullif(v_snapshot ->> 'origin', '');
  v_destination_lane := nullif(v_snapshot ->> 'destination', '');
  if v_service_type is null or v_origin_lane is null or v_destination_lane is null then
    raise exception 'source_demand_incomplete: costing request % requirements_snapshot has no usable service_type/origin/destination', p_costing_request_id
      using errcode = 'check_violation';
  end if;

  -- design note 2: target_ready_date is a plain string in the real snapshot shape
  -- (e.g. '2026-08-01') -- best-effort cast, never a hard failure on a malformed
  -- value (a bad date string is not grounds to block sourcing).
  begin
    v_pickup_at := nullif(v_snapshot ->> 'target_ready_date', '')::timestamptz;
  exception
    when others then
      v_pickup_at := null;
  end;

  select * into v_existing from app.sourcing_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.source_costing_request_id is distinct from p_costing_request_id
      or v_existing.owner_user_id is distinct from p_owner_user_id
      or v_existing.sla_due_at is distinct from p_sla_due_at
    then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different sourcing request', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  begin
    insert into app.sourcing_requests (
      tenant_id, org_unit_id, source_type, source_costing_request_id, demand_snapshot,
      service_type, mode, origin_lane, destination_lane, requested_pickup_at, currency, budget_amount,
      status, owner_user_id, sla_due_at, idempotency_key, created_by
    ) values (
      p_tenant_id, v_costing.org_unit_id, 'costing_request', p_costing_request_id, v_snapshot,
      v_service_type, nullif(v_snapshot ->> 'mode', ''), v_origin_lane, v_destination_lane, v_pickup_at,
      nullif(v_snapshot ->> 'currency', ''), nullif(v_snapshot ->> 'budget_amount', '')::numeric,
      'open', p_owner_user_id, p_sla_due_at, p_idempotency_key, p_actor_label
    )
    returning * into v_request;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'sourcing_requests_tenant_idempotency_unique' then
        select * into v_existing from app.sourcing_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.source_costing_request_id is distinct from p_costing_request_id
            or v_existing.owner_user_id is distinct from p_owner_user_id
            or v_existing.sla_due_at is distinct from p_sla_due_at
          then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different sourcing request', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise;
  end;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_request.id, 'none', 'open', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_sourcing_request_from_costing',
    'app.sourcing_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

comment on function app.create_sourcing_request_from_costing is 'PRC-256: idempotent on (tenant_id, idempotency_key), replay compares source_costing_request_id/owner_user_id/sla_due_at (design note 13). Blocks a cancelled/superseded source costing request. Extracts service_type/origin/destination from requirements_snapshot (required, else source_demand_incomplete -- design note 2); status=open directly (already-trustworthy source).';

create function app.create_sourcing_request_from_operational_demand(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_owner_user_id uuid,
  p_sla_due_at timestamptz,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_shipment app.shipment_orders;
  v_existing app.sourcing_requests;
  v_service_type text;
  v_origin_lane text;
  v_destination_lane text;
  v_constraint_name text;
  v_request app.sourcing_requests;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;
  if v_shipment.tenant_id <> p_tenant_id then
    raise exception 'tenant_mismatch: shipment order % does not belong to tenant %', p_shipment_order_id, p_tenant_id
      using errcode = 'check_violation';
  end if;
  if v_shipment.status = 'cancelled' then
    raise exception 'invalid_source_status: shipment order % is cancelled and cannot source a sourcing request', p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  -- design note 3: service_type/origin/destination are real NOT NULL columns on
  -- app.shipment_orders -- this check is defensive completeness, not expected to
  -- ever fire in practice.
  v_service_type := nullif(v_shipment.service_type, '');
  v_origin_lane := nullif(v_shipment.origin, '');
  v_destination_lane := nullif(v_shipment.destination, '');
  if v_service_type is null or v_origin_lane is null or v_destination_lane is null then
    raise exception 'source_demand_incomplete: shipment order % has no usable service_type/origin/destination', p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.sourcing_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.source_shipment_order_id is distinct from p_shipment_order_id
      or v_existing.owner_user_id is distinct from p_owner_user_id
      or v_existing.sla_due_at is distinct from p_sla_due_at
    then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different sourcing request', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  begin
    insert into app.sourcing_requests (
      tenant_id, org_unit_id, source_type, source_shipment_order_id, demand_snapshot,
      service_type, mode, origin_lane, destination_lane, cargo_weight_max, cargo_volume_max,
      requested_pickup_at, requested_delivery_at,
      status, owner_user_id, sla_due_at, idempotency_key, created_by
    ) values (
      -- ADVERSARIAL REVIEW FIX (design note 16a): consignee_snapshot/notify_party_
      -- snapshot are real customer/consignee identity data, governed on the source
      -- app.shipment_orders row by can_access_record/org-unit record scope --
      -- Sourcing's own RLS/RBAC is tenant+PRC:View only, no record scope, so storing
      -- them here would let any PRC:View holder read customer PII a direct query of
      -- the source row would have denied them. Excluded at write time; every field
      -- Sourcing actually needs is already a typed mirror column extracted below.
      p_tenant_id, v_shipment.org_unit_id, 'operational_demand', p_shipment_order_id,
      to_jsonb(v_shipment) - 'consignee_snapshot' - 'notify_party_snapshot',
      v_service_type, nullif(v_shipment.mode, ''), v_origin_lane, v_destination_lane, v_shipment.basis_weight_kg, v_shipment.basis_volume_cbm,
      v_shipment.planned_pickup_at, v_shipment.planned_delivery_at,
      'open', p_owner_user_id, p_sla_due_at, p_idempotency_key, p_actor_label
    )
    returning * into v_request;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'sourcing_requests_tenant_idempotency_unique' then
        select * into v_existing from app.sourcing_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.source_shipment_order_id is distinct from p_shipment_order_id
            or v_existing.owner_user_id is distinct from p_owner_user_id
            or v_existing.sla_due_at is distinct from p_sla_due_at
          then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different sourcing request', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise;
  end;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_request.id, 'none', 'open', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_sourcing_request_from_operational_demand',
    'app.sourcing_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

comment on function app.create_sourcing_request_from_operational_demand is 'PRC-256: idempotent on (tenant_id, idempotency_key), replay compares source_shipment_order_id/owner_user_id/sla_due_at. Blocks a cancelled source shipment order (draft/confirmed both remain valid demand sources -- design note 3/disclosed judgment call). basis_weight_kg/basis_volume_cbm map onto cargo_weight_max/cargo_volume_max only. status=open directly.';

create function app.create_proactive_sourcing_request(
  p_tenant_id uuid,
  p_service_type text,
  p_mode text,
  p_origin_lane text,
  p_destination_lane text,
  p_cargo_weight_min numeric,
  p_cargo_weight_max numeric,
  p_cargo_volume_min numeric,
  p_cargo_volume_max numeric,
  p_requested_pickup_at timestamptz,
  p_requested_delivery_at timestamptz,
  p_currency text,
  p_budget_amount numeric,
  p_owner_user_id uuid,
  p_sla_due_at timestamptz,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.sourcing_requests;
  v_snapshot jsonb;
  v_constraint_name text;
  v_request app.sourcing_requests;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;
  if p_service_type is null or length(trim(p_service_type)) = 0 then
    raise exception 'invalid_service_type: service_type must not be empty' using errcode = 'check_violation';
  end if;
  if p_origin_lane is null or length(trim(p_origin_lane)) = 0 then
    raise exception 'invalid_origin_lane: origin_lane must not be empty' using errcode = 'check_violation';
  end if;
  if p_destination_lane is null or length(trim(p_destination_lane)) = 0 then
    raise exception 'invalid_destination_lane: destination_lane must not be empty' using errcode = 'check_violation';
  end if;
  if p_budget_amount is not null and p_budget_amount < 0 then
    raise exception 'invalid_budget_amount: budget_amount must not be negative' using errcode = 'check_violation';
  end if;

  v_snapshot := jsonb_build_object(
    'service_type', p_service_type, 'mode', p_mode, 'origin_lane', p_origin_lane, 'destination_lane', p_destination_lane,
    'cargo_weight_min', p_cargo_weight_min, 'cargo_weight_max', p_cargo_weight_max,
    'cargo_volume_min', p_cargo_volume_min, 'cargo_volume_max', p_cargo_volume_max,
    'requested_pickup_at', p_requested_pickup_at, 'requested_delivery_at', p_requested_delivery_at,
    'currency', p_currency, 'budget_amount', p_budget_amount
  );

  select * into v_existing from app.sourcing_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.service_type is distinct from p_service_type or v_existing.mode is distinct from p_mode
      or v_existing.origin_lane is distinct from p_origin_lane or v_existing.destination_lane is distinct from p_destination_lane
      or v_existing.cargo_weight_min is distinct from p_cargo_weight_min or v_existing.cargo_weight_max is distinct from p_cargo_weight_max
      or v_existing.cargo_volume_min is distinct from p_cargo_volume_min or v_existing.cargo_volume_max is distinct from p_cargo_volume_max
      or v_existing.requested_pickup_at is distinct from p_requested_pickup_at or v_existing.requested_delivery_at is distinct from p_requested_delivery_at
      or v_existing.currency is distinct from p_currency or v_existing.budget_amount is distinct from p_budget_amount
      or v_existing.owner_user_id is distinct from p_owner_user_id or v_existing.sla_due_at is distinct from p_sla_due_at
    then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different sourcing request', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  begin
    insert into app.sourcing_requests (
      tenant_id, source_type, demand_snapshot,
      service_type, mode, origin_lane, destination_lane, cargo_weight_min, cargo_weight_max, cargo_volume_min, cargo_volume_max,
      requested_pickup_at, requested_delivery_at, currency, budget_amount,
      status, owner_user_id, sla_due_at, idempotency_key, created_by
    ) values (
      p_tenant_id, 'proactive', v_snapshot,
      p_service_type, nullif(p_mode, ''), p_origin_lane, p_destination_lane, p_cargo_weight_min, p_cargo_weight_max, p_cargo_volume_min, p_cargo_volume_max,
      p_requested_pickup_at, p_requested_delivery_at, nullif(p_currency, ''), p_budget_amount,
      'draft', p_owner_user_id, p_sla_due_at, p_idempotency_key, p_actor_label
    )
    returning * into v_request;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'sourcing_requests_tenant_idempotency_unique' then
        select * into v_existing from app.sourcing_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.service_type is distinct from p_service_type or v_existing.mode is distinct from p_mode
            or v_existing.origin_lane is distinct from p_origin_lane or v_existing.destination_lane is distinct from p_destination_lane
            or v_existing.cargo_weight_min is distinct from p_cargo_weight_min or v_existing.cargo_weight_max is distinct from p_cargo_weight_max
            or v_existing.cargo_volume_min is distinct from p_cargo_volume_min or v_existing.cargo_volume_max is distinct from p_cargo_volume_max
            or v_existing.requested_pickup_at is distinct from p_requested_pickup_at or v_existing.requested_delivery_at is distinct from p_requested_delivery_at
            or v_existing.currency is distinct from p_currency or v_existing.budget_amount is distinct from p_budget_amount
            or v_existing.owner_user_id is distinct from p_owner_user_id or v_existing.sla_due_at is distinct from p_sla_due_at
          then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different sourcing request', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise;
  end;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_request.id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_proactive_sourcing_request',
    'app.sourcing_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

comment on function app.create_proactive_sourcing_request is 'PRC-256: no source demand -- status=draft (needs app.submit_sourcing_request to reach open). Idempotency replay compares every one of its thirteen caller-supplied fields (design note 13, none are derived).';

-- ===========================================================================
-- 6. Lifecycle transition RPCs (design notes 4-6, 10, 12; ground rules 1-5).
-- ===========================================================================

create function app.submit_sourcing_request(
  p_sourcing_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
begin
  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing request % expected version % but found %', p_sourcing_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.source_type <> 'proactive' then
    raise exception 'invalid_transition: sourcing request % is source_type % -- only a proactive request may be submitted (costing/operational-sourced requests are created directly into open)', p_sourcing_request_id, v_request.source_type
      using errcode = 'check_violation';
  end if;
  if v_request.status <> 'draft' then
    raise exception 'invalid_transition: sourcing request % is % and cannot be submitted', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  update app.sourcing_requests
  set status = 'open'
  where id = p_sourcing_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: sourcing request % target row was concurrently modified (expected version %)', p_sourcing_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_request.tenant_id, p_sourcing_request_id, 'draft', 'open', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_sourcing_request',
    'app.sourcing_requests', v_request.id, 'success', null, null, jsonb_build_object('status', v_request.status)
  );

  return v_request;
end;
$$;

create function app.override_sourcing_request_constraints(
  p_sourcing_request_id uuid,
  p_cargo_weight_max numeric,
  p_cargo_volume_max numeric,
  p_destination_lane text,
  p_reason text,
  p_override_expires_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
  v_new_weight_max numeric;
  v_new_volume_max numeric;
  v_new_destination_lane text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to override sourcing request constraints' using errcode = 'check_violation';
  end if;

  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing request % expected version % but found %', p_sourcing_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'open' then
    raise exception 'invalid_transition: sourcing request % is % -- constraints may only be overridden while open', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- design note 10: widen-only, literal reading -- the check only fires when a
  -- value is ALREADY stored; a null-to-value transition always succeeds.
  if p_cargo_weight_max is not null and v_request.cargo_weight_max is not null and p_cargo_weight_max < v_request.cargo_weight_max then
    raise exception 'constraint_narrowing_not_allowed: cargo_weight_max override % is less than the current value % -- an override widens, it never narrows', p_cargo_weight_max, v_request.cargo_weight_max
      using errcode = 'check_violation';
  end if;
  if p_cargo_volume_max is not null and v_request.cargo_volume_max is not null and p_cargo_volume_max < v_request.cargo_volume_max then
    raise exception 'constraint_narrowing_not_allowed: cargo_volume_max override % is less than the current value % -- an override widens, it never narrows', p_cargo_volume_max, v_request.cargo_volume_max
      using errcode = 'check_violation';
  end if;

  v_new_weight_max := coalesce(p_cargo_weight_max, v_request.cargo_weight_max);
  v_new_volume_max := coalesce(p_cargo_volume_max, v_request.cargo_volume_max);
  v_new_destination_lane := coalesce(nullif(trim(p_destination_lane), ''), v_request.destination_lane);

  update app.sourcing_requests
  set cargo_weight_max = v_new_weight_max, cargo_volume_max = v_new_volume_max, destination_lane = v_new_destination_lane
  where id = p_sourcing_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: sourcing request % target row was concurrently modified (expected version %)', p_sourcing_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, reason, evidence_ref, actor_auth_user_id, actor_label)
  values (
    v_request.tenant_id, p_sourcing_request_id, 'open', 'open', p_reason,
    case when p_override_expires_at is not null then 'override_expires_at=' || p_override_expires_at::text else null end,
    p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_sourcing_request_constraints',
    'app.sourcing_requests', v_request.id, 'success', p_reason, null,
    jsonb_build_object('cargo_weight_max', v_request.cargo_weight_max, 'cargo_volume_max', v_request.cargo_volume_max, 'destination_lane', v_request.destination_lane, 'override_expires_at', p_override_expires_at)
  );

  return v_request;
end;
$$;

create function app.evaluate_sourcing_candidate_eligibility(
  p_sourcing_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns setof app.sourcing_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
  v_vendor record;
  v_vendor_count integer := 0;
  v_reasons text[];
  v_snapshot jsonb;
  v_service_match jsonb;
  v_coverage_match jsonb;
  v_compliance_rows jsonb;
  v_has_hold boolean;
  v_has_active_rate boolean;
  v_candidate app.sourcing_candidates;
  v_final_status text;
begin
  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id;
  if not found then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.status <> 'open' then
    raise exception 'invalid_transition: sourcing request % is % and candidate eligibility may only be evaluated while open', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  for v_vendor in
    select vp.master_record_id, mr.code, mr.name
    from app.vendor_profiles vp
    join app.master_records mr on mr.id = vp.master_record_id
    where vp.tenant_id = v_request.tenant_id and vp.lifecycle_status = 'active'
    order by vp.master_record_id
    limit 501
  loop
    v_vendor_count := v_vendor_count + 1;
    -- design note 9: bounded scan, disclosed via a real warning, never a silent
    -- truncation.
    if v_vendor_count > 500 then
      raise warning 'sourcing_candidate_scan_bounded: sourcing request % has more than 500 active vendors in tenant % -- only the first 500 (ordered by master_record_id) were evaluated this call; re-run to cover the remainder', p_sourcing_request_id, v_request.tenant_id;
      exit;
    end if;

    v_reasons := array[]::text[];

    -- vendor_not_active (design note 8): defensive completeness only -- the WHERE
    -- clause above already filters lifecycle_status='active', so this branch is
    -- structurally unreachable in a single-threaded evaluation. Kept as a named
    -- reason code for explainability if a future caller composes eligibility
    -- differently, or a race changes lifecycle_status mid-loop.
    if not exists (select 1 from app.vendor_profiles where master_record_id = v_vendor.master_record_id and lifecycle_status = 'active') then
      v_reasons := array_append(v_reasons, 'vendor_not_active');
    end if;

    select jsonb_agg(jsonb_build_object('id', vs.id, 'service_type', vs.service_type)) into v_service_match
    from app.vendor_services vs
    where vs.master_record_id = v_vendor.master_record_id and vs.status = 'active' and vs.service_type = v_request.service_type;
    if v_service_match is null then
      v_reasons := array_append(v_reasons, 'service_mismatch');
    end if;

    select jsonb_agg(jsonb_build_object('id', vc.id, 'origin_lane', vc.origin_lane, 'destination_lane', vc.destination_lane)) into v_coverage_match
    from app.vendor_coverage vc
    where vc.master_record_id = v_vendor.master_record_id and vc.status = 'active'
      and vc.origin_lane = v_request.origin_lane
      and (vc.destination_lane is null or vc.destination_lane = v_request.destination_lane);
    if v_coverage_match is null then
      v_reasons := array_append(v_reasons, 'coverage_mismatch');
    end if;

    select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb), bool_or(e.eligibility_hold)
    into v_compliance_rows, v_has_hold
    from app.get_vendor_compliance_eligibility(v_vendor.master_record_id, p_actor_auth_user_id) e;
    if coalesce(v_has_hold, false) then
      v_reasons := array_append(v_reasons, 'compliance_ineligible');
    end if;

    select exists (
      select 1 from app.vendor_rate_versions rv
      where rv.vendor_master_id = v_vendor.master_record_id and rv.tenant_id = v_request.tenant_id and rv.approval_status = 'approved'
        and rv.effective_from <= now() and (rv.effective_to is null or rv.effective_to > now())
    ) into v_has_active_rate;

    v_snapshot := jsonb_build_object(
      'vendor_code', v_vendor.code,
      'vendor_name', v_vendor.name,
      'service_match', coalesce(v_service_match, '[]'::jsonb),
      'coverage_match', coalesce(v_coverage_match, '[]'::jsonb),
      'compliance_rows', coalesce(v_compliance_rows, '[]'::jsonb),
      'has_active_rate', coalesce(v_has_active_rate, false),
      'evaluated_at', now()
    );

    insert into app.sourcing_candidates (tenant_id, sourcing_request_id, vendor_master_id, eligible, exclusion_reasons, evaluation_snapshot)
    values (v_request.tenant_id, p_sourcing_request_id, v_vendor.master_record_id, cardinality(v_reasons) = 0, v_reasons, v_snapshot)
    on conflict (sourcing_request_id, vendor_master_id) do update
    set eligible = excluded.eligible, exclusion_reasons = excluded.exclusion_reasons, evaluation_snapshot = excluded.evaluation_snapshot
    returning * into v_candidate;

    return next v_candidate;
  end loop;

  -- ADVERSARIAL REVIEW FIX (design note 16c): the leading status check above uses a
  -- plain, unlocked read (a fast-path early-exit, not the authoritative gate) -- a
  -- concurrent cancel_sourcing_request/close_sourcing_request_no_source/
  -- submit_sourcing_shortlist (each of which takes `for update` on this same row)
  -- could otherwise commit a status change mid-scan, leaving freshly written
  -- sourcing_candidates rows for a request that is no longer open. This final,
  -- locked re-check is the real gate: raising here rolls back every candidate
  -- upsert this call performed, in the same transaction. Locked only now, AFTER
  -- every candidate row this call itself touched is already locked by the loop's
  -- own upserts -- preserves the same lock order app.shortlist_sourcing_candidate
  -- uses (candidate row(s) before the parent request row), so the two functions
  -- cannot deadlock against each other.
  select status into v_final_status from app.sourcing_requests where id = p_sourcing_request_id for update;
  if v_final_status <> 'open' then
    raise exception 'invalid_transition: sourcing request % transitioned to % while candidate eligibility was being evaluated -- re-run once reopened', p_sourcing_request_id, v_final_status
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'evaluate_sourcing_candidate_eligibility',
    'app.sourcing_requests', p_sourcing_request_id, 'success', null, null, jsonb_build_object('vendor_count_evaluated', least(v_vendor_count, 500))
  );

  return;
end;
$$;

comment on function app.evaluate_sourcing_candidate_eligibility is 'PRC-256: PRC:Edit-gated (a recompute is a write). Composes app.get_vendor_compliance_eligibility per candidate, which itself requires PRC:View -- the calling actor needs BOTH (design note 8). UPSERT preserves shortlisted/shortlist_reason/shortlisted_by/shortlisted_at across re-evaluation (design note 7). Bounded to 500 active vendors per call (design note 9).';

create function app.shortlist_sourcing_candidate(
  p_candidate_id uuid,
  p_shortlisted boolean,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_candidates
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_candidate app.sourcing_candidates;
  v_request app.sourcing_requests;
  v_action text;
begin
  select * into v_candidate from app.sourcing_candidates where id = p_candidate_id for update;
  if not found then
    raise exception 'sourcing_candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;

  -- design note 6: reason is unconditionally required whenever shortlisted=true
  -- (mirrors the table CHECK), regardless of eligibility; only the AUTHORITY
  -- required differs by eligibility. v_action is derived from the already-locked
  -- candidate row's own eligible field -- no additional query needed.
  if p_shortlisted then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: shortlisting a candidate requires a non-empty reason' using errcode = 'check_violation';
    end if;
    v_action := case when v_candidate.eligible then 'Edit' else 'Override' end;
  else
    v_action := 'Edit';
  end if;

  -- ADVERSARIAL REVIEW FIX (design note 16b): permission is now evaluated BEFORE
  -- the parent sourcing_request is read at all -- the original ordering fetched
  -- v_request.status first (a plain, unlocked SELECT) and disclosed it via
  -- invalid_transition even to a caller who fails this very permission check,
  -- including a cross-tenant actor with zero role assignment in v_candidate's own
  -- tenant. Every sibling transition RPC in this migration already checks
  -- permission immediately after its own existence/lock check; this was the sole
  -- outlier.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_candidate.tenant_id, 'PRC', v_action);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:% (%) for tenant %', p_actor_auth_user_id, v_action, v_decision.reason, v_candidate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_candidate.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing candidate % expected version % but found %', p_candidate_id, p_expected_version, v_candidate.record_version
      using errcode = 'serialization_failure';
  end if;

  -- ADVERSARIAL REVIEW FIX (design note 16b): the parent row is now locked `for
  -- update` -- matching every sibling transition RPC's own "for update" shape --
  -- closing a real race where a concurrent submit_sourcing_shortlist/
  -- close_sourcing_request_no_source/cancel_sourcing_request (each of which locks
  -- this same row) could commit a status change between an unlocked read here and
  -- this function's own terminal UPDATE. Locked only now (after the candidate row
  -- is already locked, and only this one row) -- matching the lock order
  -- app.evaluate_sourcing_candidate_eligibility's own end-of-call recheck uses
  -- (candidate row(s) before the parent request row), so the two functions cannot
  -- deadlock against each other.
  select * into v_request from app.sourcing_requests where id = v_candidate.sourcing_request_id for update;
  if v_request.status <> 'open' then
    raise exception 'invalid_transition: sourcing request % is % -- candidates may only be shortlisted/un-shortlisted while open', v_request.id, v_request.status
      using errcode = 'check_violation';
  end if;

  update app.sourcing_candidates
  set shortlisted = p_shortlisted,
      shortlist_reason = case when p_shortlisted then p_reason else null end,
      shortlisted_by = case when p_shortlisted then p_actor_label else null end,
      shortlisted_at = case when p_shortlisted then now() else null end
  where id = p_candidate_id and record_version = p_expected_version
  returning * into v_candidate;
  if not found then
    raise exception 'stale_version: sourcing candidate % target row was concurrently modified (expected version %)', p_candidate_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_candidate.tenant_id, p_actor_auth_user_id, p_actor_label, 'shortlist_sourcing_candidate',
    'app.sourcing_candidates', v_candidate.id, 'success', p_reason, null,
    jsonb_build_object('shortlisted', v_candidate.shortlisted, 'eligible', v_candidate.eligible)
  );

  return v_candidate;
end;
$$;

comment on function app.shortlist_sourcing_candidate is 'PRC-256: shortlisting an eligible candidate needs PRC:Edit; shortlisting an EXCLUDED candidate needs PRC:Override AND a mandatory reason -- a governed exception, no algorithm autonomously promotes an excluded candidate. Un-shortlisting needs PRC:Edit only, reason optional. Only while the parent sourcing_request is open.';

create function app.submit_sourcing_shortlist(
  p_sourcing_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
  v_shortlisted_count integer;
begin
  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing request % expected version % but found %', p_sourcing_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'open' then
    raise exception 'invalid_transition: sourcing request % is % and cannot submit a shortlist', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_shortlisted_count from app.sourcing_candidates where sourcing_request_id = p_sourcing_request_id and shortlisted = true;
  if v_shortlisted_count = 0 then
    raise exception 'no_candidates_shortlisted: sourcing request % has zero shortlisted candidates', p_sourcing_request_id using errcode = 'check_violation';
  end if;

  update app.sourcing_requests
  set status = 'shortlisted', shortlist_locked_at = now()
  where id = p_sourcing_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: sourcing request % target row was concurrently modified (expected version %)', p_sourcing_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_request.tenant_id, p_sourcing_request_id, 'open', 'shortlisted', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_sourcing_shortlist',
    'app.sourcing_requests', v_request.id, 'success', null, null, jsonb_build_object('shortlisted_count', v_shortlisted_count)
  );

  return v_request;
end;
$$;

create function app.close_sourcing_request_no_source(
  p_sourcing_request_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to close a sourcing request with no source' using errcode = 'check_violation';
  end if;

  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing request % expected version % but found %', p_sourcing_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'open' then
    raise exception 'invalid_transition: sourcing request % is % and cannot be closed no-source', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  update app.sourcing_requests
  set status = 'closed_no_source', closed_reason = p_reason
  where id = p_sourcing_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: sourcing request % target row was concurrently modified (expected version %)', p_sourcing_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_request.tenant_id, p_sourcing_request_id, 'open', 'closed_no_source', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_sourcing_request_no_source',
    'app.sourcing_requests', v_request.id, 'success', p_reason, null, jsonb_build_object('status', v_request.status)
  );

  return v_request;
end;
$$;

create function app.cancel_sourcing_request(
  p_sourcing_request_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a sourcing request' using errcode = 'check_violation';
  end if;

  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing request % expected version % but found %', p_sourcing_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status not in ('draft', 'open') then
    raise exception 'invalid_transition: sourcing request % is % and cannot be cancelled', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_request.status;

  update app.sourcing_requests
  set status = 'cancelled', closed_reason = p_reason
  where id = p_sourcing_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: sourcing request % target row was concurrently modified (expected version %)', p_sourcing_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_request.tenant_id, p_sourcing_request_id, v_from_status, 'cancelled', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_sourcing_request',
    'app.sourcing_requests', v_request.id, 'success', p_reason, null, jsonb_build_object('status', v_request.status)
  );

  return v_request;
end;
$$;

create function app.reopen_sourcing_request(
  p_sourcing_request_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expected_version integer
)
returns app.sourcing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.sourcing_requests;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reopen a sourcing request' using errcode = 'check_violation';
  end if;

  select * into v_request from app.sourcing_requests where id = p_sourcing_request_id for update;
  if not found then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: sourcing request % expected version % but found %', p_sourcing_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status not in ('shortlisted', 'closed_no_source', 'cancelled') then
    raise exception 'invalid_transition: sourcing request % is % and cannot be reopened', p_sourcing_request_id, v_request.status
      using errcode = 'check_violation';
  end if;
  v_from_status := v_request.status;

  update app.sourcing_requests
  set status = 'open', shortlist_locked_at = null, closed_reason = null
  where id = p_sourcing_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: sourcing request % target row was concurrently modified (expected version %)', p_sourcing_request_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.sourcing_request_events (tenant_id, sourcing_request_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_request.tenant_id, p_sourcing_request_id, v_from_status, 'open', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_sourcing_request',
    'app.sourcing_requests', v_request.id, 'success', p_reason, null, jsonb_build_object('status', v_request.status)
  );

  return v_request;
end;
$$;

comment on function app.reopen_sourcing_request is 'PRC-256: PRC:Override-gated governed reopen from shortlisted/closed_no_source/cancelled back to open. Clears shortlist_locked_at and closed_reason; does NOT clear any candidate''s shortlisted flag (human-owned, preserved).';

-- ===========================================================================
-- 7. Read RPCs (PRC:View, design note 11).
-- ===========================================================================

-- BUG FIX (found live running this migration's own db-test suite): the FIRST draft
-- of every read RPC below did `select * from app.sourcing_requests_directory`/
-- `app.sourcing_candidates_directory` -- but that view's own row filter AND cost
-- mask both call `app.has_active_tenant_membership`/`app.actor_holds_customer_user_
-- layer`/`app.has_prc_view_cost` with their DEFAULT `auth.uid()` argument, not this
-- function's own EXPLICIT, already-validated `p_actor_auth_user_id`. In a real
-- browser session the two are the same value (evaluate_permission's own internal
-- assert_actor_is_session_identity guarantees it), but this SECURITY DEFINER
-- function is the one place `p_actor_auth_user_id` is the authoritative, explicit
-- identity -- silently falling back to session-implicit auth.uid() for the actual
-- data projection is the wrong dependency, live-reproduced by this checkpoint's own
-- db-test suite (every read returned an all-null row / zero rows outside a real
-- JWT session). Fixed by reconstructing the exact same projection directly against
-- the base table, passing p_actor_auth_user_id explicitly to app.has_prc_view_cost
-- -- the identical technique app.search_vendor_rates (PRC-255) already uses for
-- exactly this reason (that function's own declared return type is the masked
-- view's shape too, but its body never selects from the view itself).
create function app.get_sourcing_request(p_sourcing_request_id uuid, p_actor_auth_user_id uuid)
returns app.sourcing_requests_directory
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
  v_row app.sourcing_requests_directory;
begin
  select tenant_id into v_tenant_id from app.sourcing_requests where id = p_sourcing_request_id;
  if v_tenant_id is null then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select
    r.id, r.tenant_id, r.org_unit_id, r.source_type, r.source_costing_request_id, r.source_shipment_order_id,
    -- ADVERSARIAL REVIEW FIX (design note 16a): mask demand_snapshot's own
    -- budget_amount key exactly like the typed column two lines below -- otherwise
    -- a cost-masked caller reads the real amount straight through the snapshot.
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.demand_snapshot else r.demand_snapshot - 'budget_amount' end,
    r.service_type, r.mode, r.origin_lane, r.destination_lane, r.cargo_weight_min, r.cargo_weight_max, r.cargo_volume_min, r.cargo_volume_max,
    r.requested_pickup_at, r.requested_delivery_at, r.currency,
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.budget_amount else null end,
    not app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id),
    r.status, r.owner_user_id, r.sla_due_at, r.closed_reason, r.shortlist_locked_at, r.record_version, r.created_by, r.created_at, r.updated_at
  into v_row
  from app.sourcing_requests r
  where r.id = p_sourcing_request_id;

  return v_row;
end;
$$;

create function app.list_sourcing_requests(p_tenant_id uuid, p_status text, p_actor_auth_user_id uuid, p_limit integer default 50)
returns setof app.sourcing_requests_directory
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
  if p_status is not null and p_status not in ('draft', 'open', 'shortlisted', 'closed_no_source', 'cancelled') then
    raise exception 'invalid_status_filter: %', p_status using errcode = 'check_violation';
  end if;

  return query
  select
    r.id, r.tenant_id, r.org_unit_id, r.source_type, r.source_costing_request_id, r.source_shipment_order_id,
    -- ADVERSARIAL REVIEW FIX (design note 16a): mask demand_snapshot's own
    -- budget_amount key exactly like the typed column two lines below -- otherwise
    -- a cost-masked caller reads the real amount straight through the snapshot.
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.demand_snapshot else r.demand_snapshot - 'budget_amount' end,
    r.service_type, r.mode, r.origin_lane, r.destination_lane, r.cargo_weight_min, r.cargo_weight_max, r.cargo_volume_min, r.cargo_volume_max,
    r.requested_pickup_at, r.requested_delivery_at, r.currency,
    case when app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id) then r.budget_amount else null end,
    not app.has_prc_view_cost(r.tenant_id, p_actor_auth_user_id),
    r.status, r.owner_user_id, r.sla_due_at, r.closed_reason, r.shortlist_locked_at, r.record_version, r.created_by, r.created_at, r.updated_at
  from app.sourcing_requests r
  where r.tenant_id = p_tenant_id and (p_status is null or r.status = p_status)
  order by r.created_at desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_sourcing_requests is 'PRC-256: server-side clamped to <=200 rows regardless of p_limit -- the same disclosed, already-established Phase 6 limitation PRC-255''s own .limit(200) bound records (not true cursor pagination).';

create function app.list_sourcing_candidates(p_sourcing_request_id uuid, p_actor_auth_user_id uuid)
returns setof app.sourcing_candidates_directory
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.sourcing_requests where id = p_sourcing_request_id;
  if v_tenant_id is null then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- app.sourcing_candidates_directory carries no masking (design note 11) -- its
  -- own row filter is still auth.uid()-based, so this RPC (already independently
  -- authorized above via the explicit p_actor_auth_user_id) reads the base table
  -- directly, same reasoning as app.get_sourcing_request above.
  return query
  select c.* from app.sourcing_candidates c
  where c.sourcing_request_id = p_sourcing_request_id
  order by c.eligible desc, c.created_at;
end;
$$;

create function app.get_sourcing_request_history(p_sourcing_request_id uuid, p_actor_auth_user_id uuid)
returns setof app.sourcing_request_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.sourcing_requests where id = p_sourcing_request_id;
  if v_tenant_id is null then
    raise exception 'sourcing_request_not_found: %', p_sourcing_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.sourcing_request_events where sourcing_request_id = p_sourcing_request_id order by occurred_at;
end;
$$;

-- ===========================================================================
-- 8. RLS -- hardened default-deny form, identical shape to every PRC-25x table
--    (design note 11).
-- ===========================================================================

alter table app.sourcing_requests enable row level security;
alter table app.sourcing_request_events enable row level security;
alter table app.sourcing_candidates enable row level security;

create policy sourcing_requests_select_scoped on app.sourcing_requests
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy sourcing_request_events_select_scoped on app.sourcing_request_events
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy sourcing_candidates_select_scoped on app.sourcing_candidates
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 9. Grants (design note 15, ERR-2026-004).
-- ===========================================================================

revoke execute on all functions in schema app from public;

-- Column-restricted grant (mirrors app.vendor_rate_tiers'' own proven technique) --
-- budget_amount withheld from `authenticated`, only reachable through
-- app.sourcing_requests_directory's own has_prc_view_cost mask (the view runs in
-- owner-mode, so it can still read the column-revoked field internally).
grant select (
  id, tenant_id, org_unit_id, source_type, source_costing_request_id, source_shipment_order_id, demand_snapshot,
  service_type, mode, origin_lane, destination_lane, cargo_weight_min, cargo_weight_max, cargo_volume_min, cargo_volume_max,
  requested_pickup_at, requested_delivery_at, currency, status, owner_user_id, sla_due_at, closed_reason, shortlist_locked_at,
  idempotency_key, record_version, created_by, created_at, updated_at
) on app.sourcing_requests to authenticated;
grant select on app.sourcing_requests to service_role;

grant select on app.sourcing_request_events to authenticated, service_role;
grant insert on app.sourcing_request_events to service_role;

grant select on app.sourcing_candidates to authenticated, service_role;

grant select on app.sourcing_requests_directory to authenticated, service_role;
grant select on app.sourcing_candidates_directory to authenticated, service_role;

grant execute on function app.create_sourcing_request_from_costing(uuid, uuid, uuid, timestamptz, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_sourcing_request_from_operational_demand(uuid, uuid, uuid, timestamptz, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_proactive_sourcing_request(uuid, text, text, text, text, numeric, numeric, numeric, numeric, timestamptz, timestamptz, text, numeric, uuid, timestamptz, text, uuid, text) to authenticated, service_role;

grant execute on function app.submit_sourcing_request(uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.override_sourcing_request_constraints(uuid, numeric, numeric, text, text, timestamptz, uuid, text, integer) to authenticated, service_role;
grant execute on function app.evaluate_sourcing_candidate_eligibility(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.shortlist_sourcing_candidate(uuid, boolean, text, uuid, text, integer) to authenticated, service_role;
grant execute on function app.submit_sourcing_shortlist(uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.close_sourcing_request_no_source(uuid, text, uuid, text, integer) to authenticated, service_role;
grant execute on function app.cancel_sourcing_request(uuid, text, uuid, text, integer) to authenticated, service_role;
grant execute on function app.reopen_sourcing_request(uuid, text, uuid, text, integer) to authenticated, service_role;

grant execute on function app.get_sourcing_request(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_sourcing_requests(uuid, text, uuid, integer) to authenticated, service_role;
grant execute on function app.list_sourcing_candidates(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_sourcing_request_history(uuid, uuid) to authenticated, service_role;
