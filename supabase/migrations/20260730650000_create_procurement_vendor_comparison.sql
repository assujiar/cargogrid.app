-- Procurement capability PRC-258 (Vendor Comparison, CG-S11-PRC-009). The
-- eighth Phase 6 checkpoint, built directly on the already-COMPLETED PRC-257
-- (RFQ). Implements exact, explainable comparison of eligible vendor RFQ
-- responses across cost and configured non-price criteria: a comparison
-- root/version, per-vendor normalized offers, non-price scoring, ranking,
-- a governed recommendation, and a human selection/submission handoff ready
-- for the approval engine (Prompt 259 -- not called from here; this
-- checkpoint only reaches a "submitted" state for 259 to read). Reads (never
-- re-derives): app.rfqs / app.rfq_invitations / app.rfq_responses (PRC-257,
-- migration 20260730640000) -- the eligible-vendor-response universe for
-- comparison is exactly PRC-257's own `comparison_eligible = true`,
-- `status = 'submitted'` responses on a `closed` RFQ, never re-computed.
--
-- Composes, never reimplements, the two canonical calculation authorities
-- this prompt's own instructions name: `app.calculate_vendor_rate` (PRC-255/
-- FIN-194, migration 20260730620000) per vendor RFQ response when an
-- approved vendor rate version is linked, and `app.convert_finance_amount`
-- (FIN-194, migration 20260728230000, hardened 20260730500000) for
-- cross-currency normalization -- both always feeding `app.apply_finance_
-- rounding` (FIN-194), the one rounding authority, via those two functions'
-- own internal use of it. This migration never rounds money with a bespoke
-- `round()`/`trunc()` call of its own; every money figure this migration
-- produces originates from one of those two composed functions or is passed
-- through `app.apply_finance_rounding` directly (score fields only -- see
-- design note 6).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Comparison root/version.** `app.vendor_comparisons` mirrors `app.rfqs`'
--    own root/version shape (PRC-257 design note 2) exactly: a "recalculate"
--    (business rule, Prompt 258 section 24: "a comparison cannot rewrite the
--    underlying vendor response/rate; revisions create a new comparison
--    version") is `app.revise_vendor_comparison` -- marks the current row
--    `superseded` and inserts a brand new row (`version` + 1,
--    `revised_from_id` set), never an in-place rewrite. This also serves the
--    "alternative flow: compare scenarios by volume/date/service" (section
--    22) -- a different `basis_weight`/`basis_volume`/`basis_quantity` is a
--    new comparison version, listed alongside prior versions in the queue.
-- 2. **A comparison may only be created/revised from a `closed` RFQ**
--    (`app.rfqs.status = 'closed'`) -- PRC-257's own migration comment on
--    `app.close_rfq_for_comparison` names this exact hand-off point
--    ("Comparison reads app.list_rfq_responses for this RFQ once closed").
--    The parent RFQ row is locked `for update` before this decision even
--    though `closed` is a terminal RFQ status no PRC-257 function can
--    transition away from (defense in depth, matching this repository's
--    standing C-04 convention regardless of whether a live race is
--    currently reachable).
-- 3. **Which responses become offers.** For every `app.rfq_invitations` row
--    on the target RFQ, the LATEST `app.rfq_responses` version with
--    `status = 'submitted'` and `comparison_eligible = true` (PRC-257 already
--    computes this flag -- never re-derived: a late-captured response is
--    never `comparison_eligible`, business rule). If the latest version for
--    an invitation is withdrawn or late, that invitation contributes no
--    offer -- a withdrawal cancels participation even if an earlier version
--    was once eligible, a disclosed, defensible design choice (current state
--    governs, not history).
-- 4. **Exact common basis, exact currency/UOM.** `calculate_vendor_rate`
--    itself is already normalized to kg/cbm/unit (no UOM conversion needed,
--    per this prompt's own instructions) -- `app.link_vendor_comparison_
--    offer_rate` lets an authorized reviewer attach an approved
--    `app.vendor_rate_versions` row (belonging to the SAME vendor and
--    tenant, `approval_status = 'approved'`) to one offer, which then
--    REPLACES that offer's flat vendor-quoted `total_amount` with the rate
--    engine's own exact tier/surcharge/minimum-applied `computed_amount`
--    (in the rate's own currency) as the normalization source -- "exact
--    component/currency/UOM/tax/rounding comparison using the canonical rate
--    engine" (section 20). An offer with no rate linked is still normalized
--    for cross-currency comparison (never left unconverted) using its own
--    vendor-quoted `total_amount` as the normalization source -- so
--    `convert_finance_amount` composition is real and unconditional for
--    every offer, while `calculate_vendor_rate` composition is real
--    whenever a reviewer has an approved rate to link (per-offer, on
--    demand -- RFQ responses carry no rate-version link of their own to
--    consume automatically, see design note 4a).
-- 4a. **Why linking is a separate, per-offer action, not automatic.**
--    `app.rfq_responses` (PRC-257) carries no `rate_version_id` column --
--    a vendor's free-text commercial offer has no necessary relationship to
--    any previously negotiated `app.vendor_rate_versions` row, and guessing
--    a match (by vendor + lane + service_type) would silently substitute an
--    unrelated rate for a vendor's own quoted price. A human reviewer
--    attaches the correct rate, if one exists and applies, explicitly.
-- 5. **Auto-exclusion is real but narrowly scoped, never a blanket catch.**
--    `app._normalize_vendor_comparison_currency` wraps ONLY the single
--    `app.convert_finance_amount` call in a `begin/exception` block scoped to
--    exactly the two condition names that function's own header documents as
--    real, expected per-offer outcomes (`no_data_found` for a missing FX
--    rate, `check_violation` for an unsupported currency) -- both degrade
--    that ONE offer to `included = false`, `exclusion_reason = 'auto:...'`
--    (exception flow: "block ... stale FX", section 23) without aborting the
--    whole comparison. Any other exception (including `insufficient_
--    privilege`, i.e. the ACTOR lacks FIN:View) is never caught here --
--    that is a whole-operation authority failure, checked explicitly and
--    proactively via `app.check_finance_exchange_rate_authority('View', ...)`
--    before any offer loop begins (design note 7), never discovered as a
--    per-offer side effect and never silently swallowed (taxonomy C-09's own
--    "does the handler discriminate on what it's really catching" concern,
--    applied here to condition names rather than constraint names since no
--    unique_violation is involved in this particular narrow catch).
-- 6. **Score/rank fields are computed, not vendor-quoted commercial
--    figures** -- `price_score`/`non_price_score`/`composite_score` are
--    0-100 comparison-internal numbers, never a currency amount. They are
--    still rounded through `app.apply_finance_rounding(value, 2,
--    'round_half_up')` rather than a bespoke `round()` call -- reusing the
--    one rounding authority for every deterministic decimal this migration
--    produces, money or not, rather than drawing an arbitrary line.
-- 7. **FIN:View is a genuine, proactive, whole-operation gate**, checked via
--    the already-proven `app.check_finance_exchange_rate_authority('View',
--    p_tenant_id, p_actor_auth_user_id)` (FIN-194) immediately after the PRC
--    gates and before any per-offer work, in every RPC that can reach
--    `app.convert_finance_amount` (create/revise/link-rate) -- because
--    `convert_finance_amount` itself checks FIN:View as its OWN first
--    statement, unconditionally, even on its same-currency identity
--    short-circuit. Checking it once, early, with a clear message, is
--    strictly better than letting the first per-offer conversion attempt
--    surface a confusing `insufficient_authority` deep inside a loop.
-- 8. **The entire comparison surface gates on `PRC:View cost` alone for
--    reads, and `PRC:View cost` IN ADDITION TO the routine action gate for
--    every write** -- the identical directed reuse `app.calculate_vendor_
--    rate`'s own header already established under ADR-0020 ("the entire
--    return shape of this function is cost data ... there is no separate
--    non-cost View tier to also require"). A vendor comparison's entire
--    purpose is exposing normalized cost for a selection decision; there is
--    no non-cost-masked variant of "the comparison" the way `app.rfqs`
--    (which carries no cost column at all, PRC-257 design note 3) has one.
--    Gate cost-bearing reads on `PRC:View cost` specifically (this prompt's
--    own explicit instruction), not the generic `PRC:View`.
-- 9. **Lock order, stated once here per ground rule 2 (`docs/standards/
--    RECURRING_DEFECT_TAXONOMY.md` C-04): every function that touches both
--    a child row (offer) and its parent `app.vendor_comparisons` row locks
--    the CHILD first, then the PARENT** -- the identical order PRC-257's own
--    design note 8 established for exactly the same non-deadlock reason.
--    `app.create_vendor_comparison`/`app.revise_vendor_comparison` are the
--    one exception -- they lock a foreign PRC-257 parent (`app.rfqs`),
--    never touched again afterward in the same function, before creating
--    a brand new `app.vendor_comparisons` row.
-- 10. **Idempotency-key replay compares every load-bearing INPUT field, not
--     a subset** (ground rule 4): `create_vendor_comparison` compares
--     rfq_id/comparison_currency/basis_weight/basis_volume/basis_quantity/
--     the fully-normalized criteria_snapshot; `revise_vendor_comparison`
--     compares the same five resolved fields against `revised_from_id`.
--     Every nested `unique_violation` race-recovery handler is scoped by
--     `get stacked diagnostics constraint_name` (ground rule 5), never a
--     bare catch-all.
-- 11. **`app.score_vendor_comparison_offer_criterion` is an upsert with no
--     `p_expected_version` parameter -- a deliberate, disclosed exception to
--     this repository's usual optimistic-concurrency convention (taxonomy
--     C-03), not an oversight.** A criterion score is a collaborative
--     annotation keyed by `(comparison_offer_id, criterion_key)`, not a
--     read-then-conditionally-write transition on a row the caller
--     previously fetched a version for -- the same shape
--     `app.record_rfq_clarification` (PRC-257, a create, not an update) is
--     exempt from version-checking for. Every OTHER per-offer mutation in
--     this migration (`link_vendor_comparison_offer_rate`, `set_vendor_
--     comparison_offer_inclusion`) DOES carry `p_expected_version` and the
--     mandatory post-UPDATE applied-check, because those genuinely are
--     read-then-conditionally-write transitions on an existing row's own
--     state. Note also: `app._recompute_vendor_comparison_rankings` only
--     issues an UPDATE for an offer whose own computed fields actually
--     changed (never an unconditional pass), so an unrelated offer's
--     `record_version` is never bumped as a side effect of scoring or
--     excluding a DIFFERENT offer in the same comparison -- a genuine rank
--     shift for that specific row is the only thing that bumps it, which is
--     the correct, intended optimistic-concurrency signal.
-- 12. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE
--     EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
--     its final grants, the standing per-migration convention since
--     `PLT-118`.
-- 13. **No external vendor-facing surface, no notification/job wiring** --
--     identical reasoning to PRC-257 design notes 5/"No notification/job
--     dependency is wired": no vendor identity ever reaches this migration
--     (vendors cannot access comparison -- section 26, structurally true by
--     the same absence of any vendor-facing read path), and no concrete
--     notification event is named by this prompt's own spec text.
-- 14. **No export/watermark surface.** Section 16 names "exports are
--     watermarked/audited where supported" -- no PRC-25x capability in this
--     repository has built an export surface yet (confirmed by direct
--     inspection before writing this migration), so there is no established
--     watermarking pattern to compose against. Disclosed as a residual,
--     bounded limitation rather than a fabricated one-off. Every read RPC
--     this migration adds still supports full drilldown (`normalization_
--     lineage`, `engine_breakdown`) for on-screen "explain," which is the
--     acceptance-critical half of this requirement.
-- 15. **No dedicated criteria-configuration engine.** Non-price criteria
--     (key/label/weight) are supplied directly at comparison creation/
--     revision time and snapshotted onto `criteria_snapshot` (validated:
--     exactly one `price` entry, weights sum to 100) -- a bounded, disclosed
--     alternative to building a new Configuration-Engine-backed criteria
--     type, the same class of proportionate-effort decision PRC-257's own
--     `app.next_rfq_number` (vs. the full Numbering Engine) and COM-151's
--     own numbering counter already made and disclosed for themselves. No
--     capability in this repository has adopted a criteria-configuration
--     engine either.
-- 16. **"Request best-and-final revision" (section 22) and "exclude an
--     invalid response" (section 22) reuse PRC-257's own mechanisms rather
--     than duplicating them** -- a best-and-final request is `app.extend_
--     rfq_deadline` / a fresh `app.submit_rfq_response` version on the same
--     RFQ (PRC-257, unchanged), never a second request/response surface
--     here; an "invalid response" is excluded via `app.set_vendor_
--     comparison_offer_inclusion` (this migration) with a mandatory reason,
--     which does not touch the underlying `app.rfq_responses` row at all
--     (business rule: "a comparison cannot rewrite the underlying vendor
--     response").

-- ===========================================================================
-- 1. app.vendor_comparisons -- the comparison root/version (design notes
--    1-2, 8-10).
-- ===========================================================================

create table app.vendor_comparisons (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid references app.org_units (id),
  rfq_id uuid not null references app.rfqs (id),
  sourcing_request_id uuid not null references app.sourcing_requests (id),
  version integer not null default 1,
  revised_from_id uuid references app.vendor_comparisons (id),
  comparison_currency text not null,
  basis_weight numeric(14, 3),
  basis_volume numeric(14, 3),
  basis_quantity numeric(14, 3),
  criteria_snapshot jsonb not null default '[]'::jsonb,
  status text not null default 'draft',
  recommended_offer_id uuid,
  recommended_reason text,
  recommended_at timestamptz,
  selected_offer_id uuid,
  selection_reason text,
  submitted_at timestamptz,
  submitted_by text,
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_comparisons_status_check check (status in ('draft', 'recommended', 'submitted', 'cancelled', 'superseded')),
  constraint vendor_comparisons_version_check check (version > 0),
  constraint vendor_comparisons_currency_check check (comparison_currency ~ '^[A-Z]{3}$'),
  constraint vendor_comparisons_basis_weight_nonneg_check check (basis_weight is null or basis_weight >= 0),
  constraint vendor_comparisons_basis_volume_nonneg_check check (basis_volume is null or basis_volume >= 0),
  constraint vendor_comparisons_basis_quantity_nonneg_check check (basis_quantity is null or basis_quantity >= 0),
  constraint vendor_comparisons_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.vendor_comparisons is
  'PRC-258: canonical vendor comparison root/version, built from a closed app.rfqs (PRC-257). A "recalculate" (app.revise_vendor_comparison) marks the current row superseded and inserts a brand new version -- never an in-place rewrite (design note 1). comparison_currency is the normalization target every offer converts into via app.convert_finance_amount.';

create index vendor_comparisons_tenant_status_idx on app.vendor_comparisons (tenant_id, status);
create index vendor_comparisons_tenant_rfq_idx on app.vendor_comparisons (tenant_id, rfq_id);
create index vendor_comparisons_tenant_created_idx on app.vendor_comparisons (tenant_id, created_at desc);
create index vendor_comparisons_revised_from_idx on app.vendor_comparisons (revised_from_id) where revised_from_id is not null;

create function app.touch_vendor_comparison_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

comment on function app.touch_vendor_comparison_row is 'PRC-258: shared before-update touch trigger for app.vendor_comparisons/app.vendor_comparison_offers -- record_version += 1, updated_at := now(), mirroring app.touch_rfq_row (PRC-257) exactly (defined fresh per this repository''s own standing per-migration convention -- every PRC-25x capability defines its own identically-shaped touch trigger rather than reaching for a differently-named one, see PRC-257 design note re: app.touch_sourcing_row).';

create trigger vendor_comparisons_touch_row
  before update on app.vendor_comparisons
  for each row
  execute function app.touch_vendor_comparison_row();

-- ===========================================================================
-- 2. app.vendor_comparison_offers -- one normalized offer per (comparison,
--    rfq_response) (design notes 3-6, 9, 11).
-- ===========================================================================

create table app.vendor_comparison_offers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  comparison_id uuid not null references app.vendor_comparisons (id),
  rfq_response_id uuid not null references app.rfq_responses (id),
  rfq_invitation_id uuid not null references app.rfq_invitations (id),
  vendor_master_id uuid not null references app.master_records (id),
  rate_version_id uuid references app.vendor_rate_versions (id),
  source_currency text not null,
  source_total_amount numeric(14, 2) not null,
  engine_computed_amount numeric(14, 2),
  engine_currency text,
  engine_breakdown jsonb,
  normalized_amount numeric(14, 2),
  normalization_lineage jsonb not null default '{}'::jsonb,
  included boolean not null default true,
  exclusion_reason text,
  price_score numeric(6, 2),
  non_price_score numeric(6, 2),
  composite_score numeric(6, 2),
  rank integer,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_comparison_offers_source_amount_nonneg_check check (source_total_amount >= 0),
  constraint vendor_comparison_offers_engine_amount_nonneg_check check (engine_computed_amount is null or engine_computed_amount >= 0),
  constraint vendor_comparison_offers_normalized_amount_nonneg_check check (normalized_amount is null or normalized_amount >= 0),
  constraint vendor_comparison_offers_exclusion_reason_check check (included or (exclusion_reason is not null and length(trim(exclusion_reason)) > 0)),
  constraint vendor_comparison_offers_price_score_range_check check (price_score is null or (price_score >= 0 and price_score <= 100)),
  constraint vendor_comparison_offers_non_price_score_range_check check (non_price_score is null or (non_price_score >= 0 and non_price_score <= 100)),
  constraint vendor_comparison_offers_composite_score_range_check check (composite_score is null or (composite_score >= 0 and composite_score <= 100)),
  constraint vendor_comparison_offers_rank_positive_check check (rank is null or rank > 0),
  constraint vendor_comparison_offers_unique unique (comparison_id, rfq_response_id)
);

comment on table app.vendor_comparison_offers is
  'PRC-258: one row per (comparison, rfq_response) snapshotted at create/revise time (design note 3). source_currency/source_total_amount preserve the vendor''s own quoted offer verbatim for lineage; normalized_amount is always produced by app.convert_finance_amount (never a bespoke conversion), optionally fed by app.calculate_vendor_rate when rate_version_id is linked (design note 4). included=false + exclusion_reason covers both a reviewer-driven exclusion and an auto-exclusion (exclusion_reason prefixed auto:, design note 5).';

create index vendor_comparison_offers_comparison_idx on app.vendor_comparison_offers (comparison_id);
create index vendor_comparison_offers_tenant_idx on app.vendor_comparison_offers (tenant_id);
create index vendor_comparison_offers_response_idx on app.vendor_comparison_offers (rfq_response_id);
create index vendor_comparison_offers_rate_idx on app.vendor_comparison_offers (rate_version_id) where rate_version_id is not null;

create trigger vendor_comparison_offers_touch_row
  before update on app.vendor_comparison_offers
  for each row
  execute function app.touch_vendor_comparison_row();

alter table app.vendor_comparisons
  add constraint vendor_comparisons_recommended_offer_fk foreign key (recommended_offer_id) references app.vendor_comparison_offers (id);
alter table app.vendor_comparisons
  add constraint vendor_comparisons_selected_offer_fk foreign key (selected_offer_id) references app.vendor_comparison_offers (id);

-- ===========================================================================
-- 3. app.vendor_comparison_offer_scores -- non-price criterion scores
--    (design note 11).
-- ===========================================================================

create table app.vendor_comparison_offer_scores (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  comparison_offer_id uuid not null references app.vendor_comparison_offers (id),
  criterion_key text not null,
  criterion_weight numeric(5, 2) not null,
  score numeric(5, 2) not null,
  notes text,
  scored_by text,
  scored_at timestamptz not null default now(),
  constraint vendor_comparison_offer_scores_score_range_check check (score >= 0 and score <= 100),
  constraint vendor_comparison_offer_scores_weight_range_check check (criterion_weight >= 0 and criterion_weight <= 100),
  constraint vendor_comparison_offer_scores_key_check check (length(trim(criterion_key)) > 0),
  constraint vendor_comparison_offer_scores_unique unique (comparison_offer_id, criterion_key)
);

comment on table app.vendor_comparison_offer_scores is
  'PRC-258: one row per (comparison_offer, criterion_key), upserted by app.score_vendor_comparison_offer_criterion -- a collaborative annotation, deliberately not optimistic-concurrency-guarded (design note 11). criterion_weight is copied from the comparison''s own criteria_snapshot at scoring time for drilldown/explanation even if the comparison is later revised.';

create index vendor_comparison_offer_scores_offer_idx on app.vendor_comparison_offer_scores (comparison_offer_id);
create index vendor_comparison_offer_scores_tenant_idx on app.vendor_comparison_offer_scores (tenant_id);

-- ===========================================================================
-- 4. app.vendor_comparison_events -- append-only lifecycle history (mirrors
--    app.rfq_events exactly).
-- ===========================================================================

create table app.vendor_comparison_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  comparison_id uuid not null references app.vendor_comparisons (id),
  from_status text not null,
  to_status text not null,
  reason text,
  evidence_ref text,
  actor_auth_user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now()
);

comment on table app.vendor_comparison_events is
  'PRC-258: append-only comparison-root lifecycle transition history, mirrors app.rfq_events (PRC-257) exactly. Offer-level actions (link rate, include/exclude, score) are NOT comparison-root transitions and do not write here -- app.capture_audit_event still records every one of those.';

create index vendor_comparison_events_comparison_idx on app.vendor_comparison_events (comparison_id, occurred_at);
create index vendor_comparison_events_tenant_idx on app.vendor_comparison_events (tenant_id);

-- ===========================================================================
-- 5. Directory views -- plain (design note 8: the whole surface gates on
--    PRC:View cost inside the RPCs, never row/field-masked at the view
--    level; kept only for the "always read through a directory view"
--    convention, PRC-257's own precedent for a table with nothing to mask).
-- ===========================================================================

create view app.vendor_comparisons_directory as
select c.* from app.vendor_comparisons c
where (app.has_active_tenant_membership(c.tenant_id) and not app.actor_holds_customer_user_layer(c.tenant_id)) or app.is_supreme_admin();

create view app.vendor_comparison_offers_directory as
select o.* from app.vendor_comparison_offers o
where (app.has_active_tenant_membership(o.tenant_id) and not app.actor_holds_customer_user_layer(o.tenant_id)) or app.is_supreme_admin();

create view app.vendor_comparison_offer_scores_directory as
select s.* from app.vendor_comparison_offer_scores s
where (app.has_active_tenant_membership(s.tenant_id) and not app.actor_holds_customer_user_layer(s.tenant_id)) or app.is_supreme_admin();

create view app.vendor_comparison_events_directory as
select e.* from app.vendor_comparison_events e
where (app.has_active_tenant_membership(e.tenant_id) and not app.actor_holds_customer_user_layer(e.tenant_id)) or app.is_supreme_admin();

-- ===========================================================================
-- 6. Private helpers (design notes 3-6; unqualified `language plpgsql`, no
--    `security definer`, no grant -- mirrors app._compute_vendor_rate_amount
--    (PRC-255) exactly: executes under the calling SECURITY DEFINER RPC's
--    own already-elevated context, callable only from within this schema).
-- ===========================================================================

create function app._normalize_vendor_comparison_criteria(p_criteria jsonb)
returns jsonb
language plpgsql
as $$
declare
  v_criteria jsonb;
  v_item jsonb;
  v_weight_sum numeric := 0;
  v_price_count integer := 0;
  v_keys text[] := array[]::text[];
begin
  v_criteria := coalesce(p_criteria, '[]'::jsonb);
  if jsonb_typeof(v_criteria) is distinct from 'array' or jsonb_array_length(v_criteria) = 0 then
    v_criteria := jsonb_build_array(jsonb_build_object('key', 'price', 'label', 'Price', 'weight', 100));
  end if;

  for v_item in select * from jsonb_array_elements(v_criteria) loop
    if not (v_item ? 'key') or not (v_item ? 'label') or not (v_item ? 'weight') then
      raise exception 'invalid_criteria: every criterion requires key/label/weight' using errcode = 'check_violation';
    end if;
    if (v_item ->> 'key') = any (v_keys) then
      raise exception 'invalid_criteria: duplicate criterion key %', v_item ->> 'key' using errcode = 'check_violation';
    end if;
    v_keys := v_keys || (v_item ->> 'key');
    if (v_item ->> 'key') = 'price' then
      v_price_count := v_price_count + 1;
    end if;
    if (v_item ->> 'weight')::numeric < 0 or (v_item ->> 'weight')::numeric > 100 then
      raise exception 'invalid_criteria: weight for % must be between 0 and 100', v_item ->> 'key' using errcode = 'check_violation';
    end if;
    v_weight_sum := v_weight_sum + (v_item ->> 'weight')::numeric;
  end loop;

  if v_price_count <> 1 then
    raise exception 'invalid_criteria: criteria must include exactly one "price" entry' using errcode = 'check_violation';
  end if;
  if abs(v_weight_sum - 100) > 0.01 then
    raise exception 'invalid_criteria: criterion weights must sum to 100, got %', v_weight_sum using errcode = 'check_violation';
  end if;

  return v_criteria;
end;
$$;

comment on function app._normalize_vendor_comparison_criteria is 'PRC-258: validates/defaults criteria_snapshot (design note 15) -- exactly one "price" entry, weights sum to 100. Null/empty input defaults to a single 100%% price criterion (price-only comparison).';

create function app._normalize_vendor_comparison_currency(
  p_tenant_id uuid,
  p_comparison_currency text,
  p_source_currency text,
  p_source_amount numeric,
  p_actor_auth_user_id uuid
)
returns table (normalized_amount numeric, ok boolean, failure_code text, lineage jsonb)
language plpgsql
as $$
declare
  v_result jsonb;
begin
  begin
    v_result := app.convert_finance_amount(p_tenant_id, p_source_amount, p_source_currency, p_comparison_currency, 'spot', now(), p_actor_auth_user_id);
  exception
    -- Self-caught during this checkpoint's own Tier B walk: a bare `when
    -- check_violation` would ALSO swallow app.apply_finance_rounding's own
    -- check_violation (finance_rounding_invalid_precision/_mode, raised if a
    -- tenant's finance_rounding config ever holds a corrupted value) inside
    -- app.convert_finance_amount's own rounding step -- silently
    -- mischaracterizing a config data-integrity bug as an ordinary
    -- per-offer "unsupported currency" outcome. Verifying the SQLERRM
    -- prefix before treating it as the expected condition (and re-raising
    -- anything else) is the same "discriminate before recovering" discipline
    -- C-09 demands for constraint names, applied here to condition text
    -- since PL/pgSQL cannot catch by a custom condition alone.
    when no_data_found then
      if sqlerrm not like 'finance_exchange_rate_missing:%' then
        raise;
      end if;
      return query select null::numeric, false, 'fx_rate_missing', jsonb_build_object('sourceCurrency', p_source_currency, 'targetCurrency', p_comparison_currency, 'error', sqlerrm);
      return;
    when check_violation then
      if sqlerrm not like 'finance_exchange_rate_unsupported_currency:%' then
        raise;
      end if;
      return query select null::numeric, false, 'fx_conversion_invalid', jsonb_build_object('sourceCurrency', p_source_currency, 'targetCurrency', p_comparison_currency, 'error', sqlerrm);
      return;
  end;
  return query select (v_result ->> 'convertedAmount')::numeric, true, null::text, v_result;
end;
$$;

comment on function app._normalize_vendor_comparison_currency is 'PRC-258 design note 5: the ONE call site for app.convert_finance_amount composition. Narrowly catches only no_data_found (missing FX rate) and check_violation (unsupported currency) -- both real, expected per-offer outcomes -- and reports them as a structured failure rather than aborting. insufficient_privilege (actor lacks FIN:View) is never caught here -- it propagates, because that is a whole-operation authority failure the caller already checks proactively (design note 7) before this is ever invoked.';

create function app._snapshot_vendor_comparison_offers(p_comparison app.vendor_comparisons, p_actor_auth_user_id uuid)
returns void
language plpgsql
as $$
declare
  v_response record;
  v_norm record;
  v_included boolean;
  v_reason text;
  v_normalized numeric;
  v_lineage jsonb;
begin
  for v_response in
    select distinct on (i.id) r.*, i.id as invitation_id
    from app.rfq_invitations i
    join app.rfq_responses r on r.rfq_invitation_id = i.id
    where i.rfq_id = p_comparison.rfq_id
      and r.status = 'submitted'
      and r.comparison_eligible = true
    order by i.id, r.version desc
  loop
    v_included := true;
    v_reason := null;
    v_normalized := null;
    v_lineage := '{}'::jsonb;

    if v_response.validity_until is not null and v_response.validity_until < now() then
      v_included := false;
      v_reason := 'auto:offer_expired';
    else
      select * into v_norm from app._normalize_vendor_comparison_currency(
        p_comparison.tenant_id, p_comparison.comparison_currency, v_response.currency, v_response.total_amount, p_actor_auth_user_id
      );
      if v_norm.ok then
        v_normalized := v_norm.normalized_amount;
        v_lineage := v_norm.lineage || jsonb_build_object('sourceAmount', v_response.total_amount, 'sourceCurrency', v_response.currency, 'basis', 'response_total_amount');
      else
        v_included := false;
        v_reason := 'auto:' || v_norm.failure_code;
      end if;
    end if;

    insert into app.vendor_comparison_offers (
      tenant_id, comparison_id, rfq_response_id, rfq_invitation_id, vendor_master_id,
      source_currency, source_total_amount, normalized_amount, normalization_lineage, included, exclusion_reason
    ) values (
      p_comparison.tenant_id, p_comparison.id, v_response.id, v_response.invitation_id, v_response.vendor_master_id,
      v_response.currency, v_response.total_amount, v_normalized, v_lineage, v_included, v_reason
    );
  end loop;
end;
$$;

comment on function app._snapshot_vendor_comparison_offers is 'PRC-258 design note 3: for every rfq_invitation on the target RFQ, snapshots the LATEST submitted+comparison_eligible app.rfq_responses version as one offer, auto-excluding an expired or FX-unconvertible offer (design note 5) rather than failing the whole comparison. Shared by app.create_vendor_comparison and app.revise_vendor_comparison.';

create function app._recompute_vendor_comparison_rankings(p_comparison_id uuid)
returns void
language plpgsql
as $$
declare
  v_comparison app.vendor_comparisons;
  v_min_amount numeric;
  v_offer record;
  v_criterion jsonb;
  v_price_weight numeric := 0;
  v_non_price_weight_total numeric := 0;
  v_composite numeric;
  v_price_score numeric;
  v_non_price_score numeric;
  v_non_price_weighted_sum numeric;
  v_criterion_score numeric;
  v_rank integer := 0;
begin
  select * into v_comparison from app.vendor_comparisons where id = p_comparison_id;
  if not found then
    return;
  end if;

  select min(normalized_amount) into v_min_amount
  from app.vendor_comparison_offers
  where comparison_id = p_comparison_id and included = true and normalized_amount is not null;

  for v_criterion in select * from jsonb_array_elements(v_comparison.criteria_snapshot) loop
    if v_criterion ->> 'key' = 'price' then
      v_price_weight := coalesce((v_criterion ->> 'weight')::numeric, 0);
    else
      v_non_price_weight_total := v_non_price_weight_total + coalesce((v_criterion ->> 'weight')::numeric, 0);
    end if;
  end loop;

  for v_offer in select * from app.vendor_comparison_offers where comparison_id = p_comparison_id loop
    if not v_offer.included or v_offer.normalized_amount is null then
      update app.vendor_comparison_offers
      set price_score = null, non_price_score = null, composite_score = null, rank = null
      where id = v_offer.id
        and (price_score is not null or non_price_score is not null or composite_score is not null or rank is not null);
      continue;
    end if;

    v_price_score := case
      when v_min_amount is null then null
      when v_offer.normalized_amount = 0 then 100
      else app.apply_finance_rounding(100 * v_min_amount / v_offer.normalized_amount, 2, 'round_half_up')
    end;

    v_composite := 0;
    v_non_price_weighted_sum := 0;
    for v_criterion in select * from jsonb_array_elements(v_comparison.criteria_snapshot) loop
      if v_criterion ->> 'key' = 'price' then
        v_composite := v_composite + coalesce((v_criterion ->> 'weight')::numeric, 0) / 100.0 * coalesce(v_price_score, 0);
      else
        select score into v_criterion_score from app.vendor_comparison_offer_scores
          where comparison_offer_id = v_offer.id and criterion_key = v_criterion ->> 'key';
        v_criterion_score := coalesce(v_criterion_score, 0);
        v_composite := v_composite + coalesce((v_criterion ->> 'weight')::numeric, 0) / 100.0 * v_criterion_score;
        v_non_price_weighted_sum := v_non_price_weighted_sum + coalesce((v_criterion ->> 'weight')::numeric, 0) * v_criterion_score;
      end if;
    end loop;

    v_non_price_score := case when v_non_price_weight_total > 0 then app.apply_finance_rounding(v_non_price_weighted_sum / v_non_price_weight_total, 2, 'round_half_up') else null end;
    v_composite := app.apply_finance_rounding(v_composite, 2, 'round_half_up');

    -- Design note 11: an UPDATE only fires (and only then bumps record_version
    -- via the shared touch trigger) when a computed field genuinely changed --
    -- never an unconditional pass over every offer on every recompute.
    update app.vendor_comparison_offers
    set price_score = v_price_score, non_price_score = v_non_price_score, composite_score = v_composite
    where id = v_offer.id
      and (price_score is distinct from v_price_score or non_price_score is distinct from v_non_price_score or composite_score is distinct from v_composite);
  end loop;

  v_rank := 0;
  for v_offer in
    select id, rank as current_rank from app.vendor_comparison_offers
    where comparison_id = p_comparison_id and included = true and normalized_amount is not null
    order by composite_score desc nulls last, normalized_amount asc
  loop
    v_rank := v_rank + 1;
    if v_offer.current_rank is distinct from v_rank then
      update app.vendor_comparison_offers set rank = v_rank where id = v_offer.id;
    end if;
  end loop;
end;
$$;

comment on function app._recompute_vendor_comparison_rankings is 'PRC-258: recomputes price_score (100 * lowest normalized_amount / this offer''s normalized_amount, rounded via app.apply_finance_rounding -- design note 6), non_price_score (weighted average of scored non-price criteria, unscored=0), composite_score (full weighted sum across criteria_snapshot) and rank (1..n among included, normalized offers) for one comparison. Called after every offer-shaping mutation (snapshot/link-rate/inclusion/score).';

-- ===========================================================================
-- 7. Creation RPCs (PRC:Create + PRC:View cost + FIN:View, design notes 1-2,
--    7-10).
-- ===========================================================================

create function app.create_vendor_comparison(
  p_tenant_id uuid,
  p_rfq_id uuid,
  p_comparison_currency text,
  p_basis_weight numeric,
  p_basis_volume numeric,
  p_basis_quantity numeric,
  p_criteria jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_rfq app.rfqs;
  v_existing app.vendor_comparisons;
  v_criteria jsonb;
  v_comparison app.vendor_comparisons;
  v_offer_count integer;
  v_constraint_name text;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant % -- building a comparison computes and exposes cost data', p_actor_auth_user_id, v_cost_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_exchange_rate_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant % -- required to normalize cross-currency comparison amounts', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;
  if p_comparison_currency is null or not app.validate_currency_code(p_comparison_currency) then
    raise exception 'invalid_currency: % is not a registered, active currency', p_comparison_currency using errcode = 'check_violation';
  end if;

  -- design note 2: locks a foreign PRC-257 parent row, never touched again in
  -- this function -- no ordering conflict with any comparison-internal lock.
  select * into v_rfq from app.rfqs where id = p_rfq_id for update;
  if not found then
    raise exception 'rfq_not_found: %', p_rfq_id using errcode = 'no_data_found';
  end if;
  if v_rfq.tenant_id <> p_tenant_id then
    raise exception 'tenant_mismatch: rfq % does not belong to tenant %', p_rfq_id, p_tenant_id using errcode = 'check_violation';
  end if;
  if v_rfq.status <> 'closed' then
    raise exception 'invalid_source_status: rfq % is % -- a comparison may only be created from a closed rfq', p_rfq_id, v_rfq.status
      using errcode = 'check_violation';
  end if;

  v_criteria := app._normalize_vendor_comparison_criteria(p_criteria);

  select * into v_existing from app.vendor_comparisons where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.rfq_id is distinct from p_rfq_id or v_existing.comparison_currency is distinct from p_comparison_currency
      or v_existing.basis_weight is distinct from p_basis_weight or v_existing.basis_volume is distinct from p_basis_volume
      or v_existing.basis_quantity is distinct from p_basis_quantity or v_existing.criteria_snapshot is distinct from v_criteria
    then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor comparison', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  begin
    insert into app.vendor_comparisons (
      tenant_id, org_unit_id, rfq_id, sourcing_request_id, version, comparison_currency,
      basis_weight, basis_volume, basis_quantity, criteria_snapshot, status, idempotency_key, created_by
    ) values (
      p_tenant_id, v_rfq.org_unit_id, p_rfq_id, v_rfq.sourcing_request_id, 1, p_comparison_currency,
      p_basis_weight, p_basis_volume, p_basis_quantity, v_criteria, 'draft', p_idempotency_key, p_actor_label
    )
    returning * into v_comparison;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_comparisons_tenant_idempotency_unique' then
        select * into v_existing from app.vendor_comparisons where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.rfq_id is distinct from p_rfq_id or v_existing.comparison_currency is distinct from p_comparison_currency
            or v_existing.basis_weight is distinct from p_basis_weight or v_existing.basis_volume is distinct from p_basis_volume
            or v_existing.basis_quantity is distinct from p_basis_quantity or v_existing.criteria_snapshot is distinct from v_criteria
          then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor comparison', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise;
  end;

  perform app._snapshot_vendor_comparison_offers(v_comparison, p_actor_auth_user_id);

  select count(*) into v_offer_count from app.vendor_comparison_offers where comparison_id = v_comparison.id;
  if v_offer_count = 0 then
    raise exception 'no_comparable_responses: rfq % has no submitted, comparison-eligible responses to compare', p_rfq_id
      using errcode = 'check_violation';
  end if;

  perform app._recompute_vendor_comparison_rankings(v_comparison.id);

  insert into app.vendor_comparison_events (tenant_id, comparison_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_comparison.id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_comparison',
    'app.vendor_comparisons', v_comparison.id, 'success', null, null, jsonb_build_object('rfq_id', p_rfq_id, 'offer_count', v_offer_count)
  );

  select * into v_comparison from app.vendor_comparisons where id = v_comparison.id;
  return v_comparison;
end;
$$;

comment on function app.create_vendor_comparison is 'PRC-258: idempotent on (tenant_id, idempotency_key), replay compares rfq_id/comparison_currency/basis_weight/basis_volume/basis_quantity/criteria_snapshot. Requires a closed rfq with at least one comparison-eligible response. status=draft.';

create function app.revise_vendor_comparison(
  p_comparison_id uuid,
  p_comparison_currency text,
  p_basis_weight numeric,
  p_basis_volume numeric,
  p_basis_quantity numeric,
  p_criteria jsonb,
  p_reason text,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_old app.vendor_comparisons;
  v_from_status text;
  v_existing app.vendor_comparisons;
  v_new app.vendor_comparisons;
  v_new_currency text;
  v_new_weight numeric;
  v_new_volume numeric;
  v_new_quantity numeric;
  v_new_criteria jsonb;
  v_constraint_name text;
  v_offer_count integer;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to revise a vendor comparison' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;

  select * into v_old from app.vendor_comparisons where id = p_comparison_id for update;
  if not found then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;
  v_from_status := v_old.status;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_old.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_old.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_exchange_rate_authority('View', v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_new_currency := coalesce(nullif(trim(p_comparison_currency), ''), v_old.comparison_currency);
  if not app.validate_currency_code(v_new_currency) then
    raise exception 'invalid_currency: % is not a registered, active currency', v_new_currency using errcode = 'check_violation';
  end if;
  v_new_weight := coalesce(p_basis_weight, v_old.basis_weight);
  v_new_volume := coalesce(p_basis_volume, v_old.basis_volume);
  v_new_quantity := coalesce(p_basis_quantity, v_old.basis_quantity);
  v_new_criteria := app._normalize_vendor_comparison_criteria(coalesce(p_criteria, v_old.criteria_snapshot));

  select * into v_existing from app.vendor_comparisons where tenant_id = v_old.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.revised_from_id is distinct from p_comparison_id or v_existing.comparison_currency is distinct from v_new_currency
      or v_existing.basis_weight is distinct from v_new_weight or v_existing.basis_volume is distinct from v_new_volume
      or v_existing.basis_quantity is distinct from v_new_quantity or v_existing.criteria_snapshot is distinct from v_new_criteria
    then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor comparison revision', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if v_old.record_version <> p_expected_version then
    raise exception 'stale_version: vendor comparison % expected version % but found %', p_comparison_id, p_expected_version, v_old.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_old.status not in ('draft', 'recommended') then
    raise exception 'invalid_transition: vendor comparison % is % -- only a draft or recommended comparison may be revised', p_comparison_id, v_old.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_comparisons
  set status = 'superseded'
  where id = p_comparison_id and record_version = p_expected_version
  returning * into v_old;
  if not found then
    raise exception 'stale_version: vendor comparison % target row was concurrently modified (expected version %)', p_comparison_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  begin
    insert into app.vendor_comparisons (
      tenant_id, org_unit_id, rfq_id, sourcing_request_id, version, revised_from_id, comparison_currency,
      basis_weight, basis_volume, basis_quantity, criteria_snapshot, status, idempotency_key, created_by
    ) values (
      v_old.tenant_id, v_old.org_unit_id, v_old.rfq_id, v_old.sourcing_request_id, v_old.version + 1, v_old.id, v_new_currency,
      v_new_weight, v_new_volume, v_new_quantity, v_new_criteria, 'draft', p_idempotency_key, p_actor_label
    )
    returning * into v_new;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'vendor_comparisons_tenant_idempotency_unique' then
        select * into v_existing from app.vendor_comparisons where tenant_id = v_old.tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.revised_from_id is distinct from p_comparison_id or v_existing.comparison_currency is distinct from v_new_currency
            or v_existing.basis_weight is distinct from v_new_weight or v_existing.basis_volume is distinct from v_new_volume
            or v_existing.basis_quantity is distinct from v_new_quantity or v_existing.criteria_snapshot is distinct from v_new_criteria
          then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vendor comparison revision', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      raise;
  end;

  perform app._snapshot_vendor_comparison_offers(v_new, p_actor_auth_user_id);

  select count(*) into v_offer_count from app.vendor_comparison_offers where comparison_id = v_new.id;
  if v_offer_count = 0 then
    raise exception 'no_comparable_responses: rfq % has no submitted, comparison-eligible responses to compare', v_new.rfq_id
      using errcode = 'check_violation';
  end if;

  perform app._recompute_vendor_comparison_rankings(v_new.id);

  insert into app.vendor_comparison_events (tenant_id, comparison_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_old.tenant_id, v_old.id, v_from_status, 'superseded', p_reason, p_actor_auth_user_id, p_actor_label);
  insert into app.vendor_comparison_events (tenant_id, comparison_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_new.tenant_id, v_new.id, 'none', 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_new.tenant_id, p_actor_auth_user_id, p_actor_label, 'revise_vendor_comparison',
    'app.vendor_comparisons', v_new.id, 'success', p_reason, to_jsonb(v_old), to_jsonb(v_new)
  );

  return v_new;
end;
$$;

comment on function app.revise_vendor_comparison is 'PRC-258: only from status draft|recommended, mandatory reason. Marks the current version superseded and inserts a brand new draft version (version+1, revised_from_id), re-snapshotting offers fresh from the current rfq responses -- also serves scenario comparison (different basis_weight/volume/quantity). Idempotent on (tenant_id, idempotency_key).';

-- ===========================================================================
-- 8. Offer-level RPCs (PRC:Edit + PRC:View cost, design notes 4, 9, 11).
-- ===========================================================================

create function app.link_vendor_comparison_offer_rate(
  p_comparison_offer_id uuid,
  p_rate_version_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparison_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_offer app.vendor_comparison_offers;
  v_comparison app.vendor_comparisons;
  v_rate app.vendor_rate_versions;
  v_calc record;
  v_norm record;
begin
  select * into v_offer from app.vendor_comparison_offers where id = p_comparison_offer_id for update;
  if not found then
    raise exception 'vendor_comparison_offer_not_found: %', p_comparison_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  -- Design note 7 consistency: every whole-operation authority gate (PRC:Edit,
  -- PRC:View cost, FIN:View) runs together, before any state-dependent check
  -- (record_version/comparison.status/basis_quantity) can disclose anything
  -- beyond this row's bare existence -- mirrors app.create_vendor_comparison/
  -- app.revise_vendor_comparison's own gate ordering exactly, rather than
  -- letting the FIN:View gate surface after state has already been read.
  if not app.check_finance_exchange_rate_authority('View', v_offer.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: vendor comparison offer % expected version % but found %', p_comparison_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;

  -- design note 9: child (offer) already locked above, parent (comparison)
  -- locked here, second.
  select * into v_comparison from app.vendor_comparisons where id = v_offer.comparison_id for update;
  if v_comparison.status not in ('draft', 'recommended') then
    raise exception 'invalid_transition: vendor comparison % is % -- offers may only be edited while draft or recommended', v_comparison.id, v_comparison.status
      using errcode = 'check_violation';
  end if;
  if v_comparison.basis_quantity is null or v_comparison.basis_quantity <= 0 then
    raise exception 'invalid_basis_quantity: comparison % has no positive basis_quantity -- the rate engine requires one to compute an amount', v_comparison.id
      using errcode = 'check_violation';
  end if;

  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;
  if v_rate.tenant_id <> v_comparison.tenant_id then
    raise exception 'tenant_mismatch: rate version % does not belong to tenant %', p_rate_version_id, v_comparison.tenant_id
      using errcode = 'check_violation';
  end if;
  -- Self-caught during this checkpoint's own Tier B walk (RECURRING_DEFECT_
  -- TAXONOMY.md class-C-19-adjacent "wrong scope tuple" shape, fixed in place
  -- before this migration was ever applied anywhere): app.vendor_rate_
  -- versions.master_record_id is the vendor_rate-TYPED identity row
  -- (app.create_master_record('vendor_rate', ...), COM-149) -- a SEPARATE
  -- identity from the real canonical Procurement vendor
  -- (app.vendor_profiles.master_record_id, master_type_code='vendor') that
  -- app.vendor_comparison_offers.vendor_master_id always carries. Comparing
  -- against master_record_id would reject every real link attempt (the two
  -- id spaces never coincide). PRC-255's own ADR-0020 widening added the
  -- correctly-typed, correctly-named app.vendor_rate_versions.vendor_master_id
  -- column (nullable, optionally supplied at app.create_rate_version time)
  -- for exactly this comparison -- reused here, never re-derived.
  if v_rate.vendor_master_id is distinct from v_offer.vendor_master_id then
    raise exception 'vendor_mismatch: rate version % does not belong to the offer''s own vendor %', p_rate_version_id, v_offer.vendor_master_id
      using errcode = 'check_violation';
  end if;
  if v_rate.approval_status <> 'approved' then
    raise exception 'invalid_rate_status: rate version % is % -- only an approved rate may be linked', p_rate_version_id, v_rate.approval_status
      using errcode = 'check_violation';
  end if;

  -- design note 4: the ONE call site for app.calculate_vendor_rate composition.
  select * into v_calc from app.calculate_vendor_rate(p_rate_version_id, v_comparison.basis_weight, v_comparison.basis_volume, v_comparison.basis_quantity, p_actor_auth_user_id);

  select * into v_norm from app._normalize_vendor_comparison_currency(
    v_comparison.tenant_id, v_comparison.comparison_currency, v_calc.currency, v_calc.computed_amount, p_actor_auth_user_id
  );
  if not v_norm.ok then
    raise exception 'fx_conversion_failed: could not normalize the rate-engine amount from % to % (%)', v_calc.currency, v_comparison.comparison_currency, v_norm.failure_code
      using errcode = 'no_data_found';
  end if;

  update app.vendor_comparison_offers
  set rate_version_id = p_rate_version_id,
      engine_computed_amount = v_calc.computed_amount,
      engine_currency = v_calc.currency,
      engine_breakdown = to_jsonb(v_calc),
      normalized_amount = v_norm.normalized_amount,
      normalization_lineage = v_norm.lineage || jsonb_build_object('basis', 'rate_engine', 'rateVersionId', p_rate_version_id)
  where id = p_comparison_offer_id and record_version = p_expected_version
  returning * into v_offer;
  if not found then
    raise exception 'stale_version: vendor comparison offer % target row was concurrently modified (expected version %)', p_comparison_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app._recompute_vendor_comparison_rankings(v_comparison.id);

  perform app.capture_audit_event(
    v_comparison.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_vendor_comparison_offer_rate',
    'app.vendor_comparison_offers', v_offer.id, 'success', null, null, jsonb_build_object('rate_version_id', p_rate_version_id, 'normalized_amount', v_offer.normalized_amount)
  );

  select * into v_offer from app.vendor_comparison_offers where id = p_comparison_offer_id;
  return v_offer;
end;
$$;

comment on function app.link_vendor_comparison_offer_rate is 'PRC-258: attaches an approved, same-vendor app.vendor_rate_versions row to one offer. Composes app.calculate_vendor_rate (design note 4) to derive engine_computed_amount, then app.convert_finance_amount to normalize it into the comparison currency -- REPLACES the offer''s vendor-quoted total_amount as the normalization source. Only while the comparison is draft|recommended.';

create function app.set_vendor_comparison_offer_inclusion(
  p_comparison_offer_id uuid,
  p_included boolean,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparison_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_offer app.vendor_comparison_offers;
  v_comparison app.vendor_comparisons;
begin
  if not coalesce(p_included, true) and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to exclude a comparison offer' using errcode = 'check_violation';
  end if;

  select * into v_offer from app.vendor_comparison_offers where id = p_comparison_offer_id for update;
  if not found then
    raise exception 'vendor_comparison_offer_not_found: %', p_comparison_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_offer.record_version <> p_expected_version then
    raise exception 'stale_version: vendor comparison offer % expected version % but found %', p_comparison_offer_id, p_expected_version, v_offer.record_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_comparison from app.vendor_comparisons where id = v_offer.comparison_id for update;
  if v_comparison.status not in ('draft', 'recommended') then
    raise exception 'invalid_transition: vendor comparison % is % -- offers may only be edited while draft or recommended', v_comparison.id, v_comparison.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_comparison_offers
  set included = p_included, exclusion_reason = case when p_included then null else p_reason end
  where id = p_comparison_offer_id and record_version = p_expected_version
  returning * into v_offer;
  if not found then
    raise exception 'stale_version: vendor comparison offer % target row was concurrently modified (expected version %)', p_comparison_offer_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app._recompute_vendor_comparison_rankings(v_comparison.id);

  perform app.capture_audit_event(
    v_comparison.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_vendor_comparison_offer_inclusion',
    'app.vendor_comparison_offers', v_offer.id, 'success', p_reason, null, jsonb_build_object('included', v_offer.included)
  );

  select * into v_offer from app.vendor_comparison_offers where id = p_comparison_offer_id;
  return v_offer;
end;
$$;

comment on function app.set_vendor_comparison_offer_inclusion is 'PRC-258: reviewer-driven include/exclude of one offer (exception flow: "exclude an invalid response," design note 16) -- mandatory reason to exclude, never touches the underlying app.rfq_responses row. Only while the comparison is draft|recommended.';

create function app.score_vendor_comparison_offer_criterion(
  p_comparison_offer_id uuid,
  p_criterion_key text,
  p_score numeric,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparison_offer_scores
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_offer app.vendor_comparison_offers;
  v_comparison app.vendor_comparisons;
  v_criterion jsonb;
  v_weight numeric;
  v_row app.vendor_comparison_offer_scores;
begin
  if p_criterion_key is null or length(trim(p_criterion_key)) = 0 then
    raise exception 'criterion_key_required: p_criterion_key must not be empty' using errcode = 'check_violation';
  end if;
  if p_criterion_key = 'price' then
    raise exception 'invalid_criterion: price is system-computed and cannot be manually scored' using errcode = 'check_violation';
  end if;
  if p_score is null or p_score < 0 or p_score > 100 then
    raise exception 'invalid_score: score must be between 0 and 100' using errcode = 'check_violation';
  end if;

  select * into v_offer from app.vendor_comparison_offers where id = p_comparison_offer_id for update;
  if not found then
    raise exception 'vendor_comparison_offer_not_found: %', p_comparison_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_offer.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_offer.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_comparison from app.vendor_comparisons where id = v_offer.comparison_id for update;
  if v_comparison.status not in ('draft', 'recommended') then
    raise exception 'invalid_transition: vendor comparison % is % -- offers may only be scored while draft or recommended', v_comparison.id, v_comparison.status
      using errcode = 'check_violation';
  end if;

  select elem into v_criterion
  from jsonb_array_elements(v_comparison.criteria_snapshot) as elem
  where elem ->> 'key' = p_criterion_key
  limit 1;
  if not found then
    raise exception 'unknown_criterion: % is not a configured criterion for this comparison', p_criterion_key using errcode = 'check_violation';
  end if;
  v_weight := (v_criterion ->> 'weight')::numeric;

  insert into app.vendor_comparison_offer_scores (tenant_id, comparison_offer_id, criterion_key, criterion_weight, score, notes, scored_by)
  values (v_offer.tenant_id, p_comparison_offer_id, p_criterion_key, v_weight, p_score, p_notes, p_actor_label)
  on conflict (comparison_offer_id, criterion_key)
  do update set score = excluded.score, notes = excluded.notes, scored_by = excluded.scored_by, scored_at = now(), criterion_weight = excluded.criterion_weight
  returning * into v_row;

  perform app._recompute_vendor_comparison_rankings(v_comparison.id);

  perform app.capture_audit_event(
    v_comparison.tenant_id, p_actor_auth_user_id, p_actor_label, 'score_vendor_comparison_offer_criterion',
    'app.vendor_comparison_offer_scores', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.score_vendor_comparison_offer_criterion is 'PRC-258: upserts one non-price criterion score (0-100) for one offer, keyed by criterion_key against the comparison''s own criteria_snapshot. Deliberately no p_expected_version (design note 11). Only while the comparison is draft|recommended.';

-- ===========================================================================
-- 9. Comparison-root decision RPCs (recommend/submit/cancel, design note 8).
-- ===========================================================================

create function app.recommend_vendor_comparison_offer(
  p_comparison_id uuid,
  p_comparison_offer_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_comparison app.vendor_comparisons;
  v_offer app.vendor_comparison_offers;
  v_lowest_id uuid;
  v_from_status text;
begin
  select * into v_comparison from app.vendor_comparisons where id = p_comparison_id for update;
  if not found then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;
  v_from_status := v_comparison.status;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_comparison.record_version <> p_expected_version then
    raise exception 'stale_version: vendor comparison % expected version % but found %', p_comparison_id, p_expected_version, v_comparison.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_comparison.status not in ('draft', 'recommended') then
    raise exception 'invalid_transition: vendor comparison % is % -- only a draft or recommended comparison accepts a recommendation', p_comparison_id, v_comparison.status
      using errcode = 'check_violation';
  end if;

  select * into v_offer from app.vendor_comparison_offers where id = p_comparison_offer_id and comparison_id = p_comparison_id;
  if not found then
    raise exception 'vendor_comparison_offer_not_found: % does not belong to comparison %', p_comparison_offer_id, p_comparison_id using errcode = 'no_data_found';
  end if;
  if not v_offer.included then
    raise exception 'excluded_offer: offer % is excluded and cannot be recommended', p_comparison_offer_id using errcode = 'check_violation';
  end if;

  -- Business rule: lowest price is not automatic selection, but a reviewer
  -- who recommends anything OTHER than the lowest normalized cost among
  -- included offers must state why.
  select id into v_lowest_id
  from app.vendor_comparison_offers
  where comparison_id = p_comparison_id and included = true and normalized_amount is not null
  order by normalized_amount asc
  limit 1;

  if v_lowest_id is distinct from p_comparison_offer_id and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to recommend an offer other than the lowest normalized cost' using errcode = 'check_violation';
  end if;

  update app.vendor_comparisons
  set status = 'recommended', recommended_offer_id = p_comparison_offer_id, recommended_reason = p_reason, recommended_at = now()
  where id = p_comparison_id and record_version = p_expected_version
  returning * into v_comparison;
  if not found then
    raise exception 'stale_version: vendor comparison % target row was concurrently modified (expected version %)', p_comparison_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_comparison_events (tenant_id, comparison_id, from_status, to_status, reason, evidence_ref, actor_auth_user_id, actor_label)
  values (v_comparison.tenant_id, p_comparison_id, v_from_status, 'recommended', p_reason, p_comparison_offer_id::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_comparison.tenant_id, p_actor_auth_user_id, p_actor_label, 'recommend_vendor_comparison_offer',
    'app.vendor_comparisons', v_comparison.id, 'success', p_reason, null, jsonb_build_object('recommended_offer_id', p_comparison_offer_id)
  );

  return v_comparison;
end;
$$;

comment on function app.recommend_vendor_comparison_offer is 'PRC-258: draft|recommended -> recommended. Mandatory reason whenever the recommended offer is not the lowest normalized_amount among included offers (business rule: lowest price is not automatic selection). Re-recommending before submission is allowed (changes the recommendation).';

create function app.submit_vendor_comparison_for_approval(
  p_comparison_id uuid,
  p_selected_offer_id uuid,
  p_selection_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_comparison app.vendor_comparisons;
  v_offer app.vendor_comparison_offers;
begin
  select * into v_comparison from app.vendor_comparisons where id = p_comparison_id for update;
  if not found then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_comparison.record_version <> p_expected_version then
    raise exception 'stale_version: vendor comparison % expected version % but found %', p_comparison_id, p_expected_version, v_comparison.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_comparison.status <> 'recommended' then
    raise exception 'invalid_transition: vendor comparison % is % -- only a recommended comparison may be submitted', p_comparison_id, v_comparison.status
      using errcode = 'check_violation';
  end if;

  select * into v_offer from app.vendor_comparison_offers where id = p_selected_offer_id and comparison_id = p_comparison_id;
  if not found then
    raise exception 'vendor_comparison_offer_not_found: % does not belong to comparison %', p_selected_offer_id, p_comparison_id using errcode = 'no_data_found';
  end if;
  if not v_offer.included then
    raise exception 'excluded_offer: offer % is excluded and cannot be selected', p_selected_offer_id using errcode = 'check_violation';
  end if;

  if p_selected_offer_id is distinct from v_comparison.recommended_offer_id and (p_selection_reason is null or length(trim(p_selection_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to select an offer other than the recommended one' using errcode = 'check_violation';
  end if;

  update app.vendor_comparisons
  set status = 'submitted', selected_offer_id = p_selected_offer_id, selection_reason = p_selection_reason,
      submitted_at = now(), submitted_by = p_actor_label
  where id = p_comparison_id and record_version = p_expected_version
  returning * into v_comparison;
  if not found then
    raise exception 'stale_version: vendor comparison % target row was concurrently modified (expected version %)', p_comparison_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_comparison_events (tenant_id, comparison_id, from_status, to_status, reason, evidence_ref, actor_auth_user_id, actor_label)
  values (v_comparison.tenant_id, p_comparison_id, 'recommended', 'submitted', p_selection_reason, p_selected_offer_id::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_comparison.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_vendor_comparison_for_approval',
    'app.vendor_comparisons', v_comparison.id, 'success', p_selection_reason, null, jsonb_build_object('selected_offer_id', p_selected_offer_id)
  );

  return v_comparison;
end;
$$;

comment on function app.submit_vendor_comparison_for_approval is 'PRC-258: recommended -> submitted, gated on PRC:Approve ("management approves," access rule) -- the human selection/override-with-reason handoff this checkpoint reaches for the approval engine to pick up next (Prompt 259, not called from here). Mandatory reason when the selected offer differs from the recommended one (business rule: human selection and override are auditable). Terminal -- no further offer edits once submitted.';

create function app.cancel_vendor_comparison(
  p_comparison_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_comparison app.vendor_comparisons;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a vendor comparison' using errcode = 'check_violation';
  end if;

  select * into v_comparison from app.vendor_comparisons where id = p_comparison_id for update;
  if not found then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;
  v_from_status := v_comparison.status;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, v_comparison.tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, v_comparison.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_comparison.record_version <> p_expected_version then
    raise exception 'stale_version: vendor comparison % expected version % but found %', p_comparison_id, p_expected_version, v_comparison.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_comparison.status not in ('draft', 'recommended') then
    raise exception 'invalid_transition: vendor comparison % is % and cannot be cancelled', p_comparison_id, v_comparison.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_comparisons
  set status = 'cancelled'
  where id = p_comparison_id and record_version = p_expected_version
  returning * into v_comparison;
  if not found then
    raise exception 'stale_version: vendor comparison % target row was concurrently modified (expected version %)', p_comparison_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.vendor_comparison_events (tenant_id, comparison_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_comparison.tenant_id, p_comparison_id, v_from_status, 'cancelled', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_comparison.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_vendor_comparison',
    'app.vendor_comparisons', v_comparison.id, 'success', p_reason, null, jsonb_build_object('status', v_comparison.status)
  );

  return v_comparison;
end;
$$;

-- ===========================================================================
-- 10. Read RPCs (PRC:View cost alone, design note 8). Every one selects
--     directly from the base table, never a directory view whose own row
--     filter resolves auth.uid() implicitly -- PRC-256/PRC-257's own C-06
--     lesson, applied here from the start.
-- ===========================================================================

create function app.get_vendor_comparison(p_comparison_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
  v_row app.vendor_comparisons;
begin
  select tenant_id into v_tenant_id from app.vendor_comparisons where id = p_comparison_id;
  if v_tenant_id is null then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View cost');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app.vendor_comparisons where id = p_comparison_id;
  return v_row;
end;
$$;

create function app.list_vendor_comparisons(p_tenant_id uuid, p_rfq_id uuid, p_status text, p_actor_auth_user_id uuid, p_limit integer default 50)
returns setof app.vendor_comparisons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View cost');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_status is not null and p_status not in ('draft', 'recommended', 'submitted', 'cancelled', 'superseded') then
    raise exception 'invalid_status_filter: %', p_status using errcode = 'check_violation';
  end if;

  return query
  select * from app.vendor_comparisons
  where tenant_id = p_tenant_id
    and (p_rfq_id is null or rfq_id = p_rfq_id)
    and ((p_status is not null and status = p_status) or (p_status is null and status <> 'superseded'))
  order by created_at desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

comment on function app.list_vendor_comparisons is 'PRC-258: server-side clamped to <=200 rows. With no p_status filter, superseded (historical) versions are excluded by default. Mirrors app.list_rfqs (PRC-257) exactly.';

create function app.list_vendor_comparison_offers(p_comparison_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_comparison_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.vendor_comparisons where id = p_comparison_id;
  if v_tenant_id is null then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View cost');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_comparison_offers where comparison_id = p_comparison_id order by rank nulls last, normalized_amount nulls last;
end;
$$;

create function app.list_vendor_comparison_offer_scores(p_comparison_offer_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_comparison_offer_scores
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.vendor_comparison_offers where id = p_comparison_offer_id;
  if v_tenant_id is null then
    raise exception 'vendor_comparison_offer_not_found: %', p_comparison_offer_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View cost');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_comparison_offer_scores where comparison_offer_id = p_comparison_offer_id order by criterion_key;
end;
$$;

create function app.get_vendor_comparison_history(p_comparison_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_comparison_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from app.vendor_comparisons where id = p_comparison_id;
  if v_tenant_id is null then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View cost');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_comparison_events where comparison_id = p_comparison_id order by occurred_at;
end;
$$;

-- ===========================================================================
-- 11. RLS -- hardened default-deny form, identical shape to every PRC-25x
--     table.
-- ===========================================================================

alter table app.vendor_comparisons enable row level security;
alter table app.vendor_comparison_offers enable row level security;
alter table app.vendor_comparison_offer_scores enable row level security;
alter table app.vendor_comparison_events enable row level security;

create policy vendor_comparisons_select_scoped on app.vendor_comparisons
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_comparison_offers_select_scoped on app.vendor_comparison_offers
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_comparison_offer_scores_select_scoped on app.vendor_comparison_offer_scores
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_comparison_events_select_scoped on app.vendor_comparison_events
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 12. Grants (design note 12, ERR-2026-004). Private helpers (section 6)
--     carry no grant of their own -- unreachable except from within this
--     schema's own SECURITY DEFINER functions.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.vendor_comparisons to authenticated, service_role;
grant select on app.vendor_comparison_offers to authenticated, service_role;
grant select on app.vendor_comparison_offer_scores to authenticated, service_role;
grant select on app.vendor_comparison_events to authenticated, service_role;

grant select on app.vendor_comparisons_directory to authenticated, service_role;
grant select on app.vendor_comparison_offers_directory to authenticated, service_role;
grant select on app.vendor_comparison_offer_scores_directory to authenticated, service_role;
grant select on app.vendor_comparison_events_directory to authenticated, service_role;

grant execute on function app.create_vendor_comparison(uuid, uuid, text, numeric, numeric, numeric, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app.revise_vendor_comparison(uuid, text, numeric, numeric, numeric, jsonb, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.link_vendor_comparison_offer_rate(uuid, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.set_vendor_comparison_offer_inclusion(uuid, boolean, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.score_vendor_comparison_offer_criterion(uuid, text, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.recommend_vendor_comparison_offer(uuid, uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.submit_vendor_comparison_for_approval(uuid, uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_vendor_comparison(uuid, text, integer, uuid, text) to authenticated, service_role;

grant execute on function app.get_vendor_comparison(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_comparisons(uuid, uuid, text, uuid, integer) to authenticated, service_role;
grant execute on function app.list_vendor_comparison_offers(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_comparison_offer_scores(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_vendor_comparison_history(uuid, uuid) to authenticated, service_role;
