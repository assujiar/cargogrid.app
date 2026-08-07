-- Procurement capability PRC-260 (Purchase Order, CG-S11-PRC-011).
-- Implements exact, source-linked purchase orders as governed vendor commitments --
-- created ONLY from an approved app.vendor_comparisons selection (PRC-258, status
-- reaching 'submitted' with approval_status in ('approved','not_required') per PRC-259's
-- own documented consumption contract, `20260730660000_create_procurement_approval.sql`
-- migration header: "the gated 'next lifecycle transition' is Prompt 260's own future
-- PO-award RPC, which must check app.vendor_comparisons.approval_status in ('approved',
-- 'not_required') before creating a PO from selected_offer_id"). PO itself then goes
-- through the SAME Platform Approval Engine binding (PRC-259's own shared
-- `app._request_procurement_entity_approval` helper, entity_type='purchase_order',
-- already a registered, valid CHECK-constraint dimension with no table of its own until
-- this migration) before it may be issued.
--
-- Reused, never duplicated: app.vendor_profiles.payment_term_days (PRC-251) for default
-- payment terms (no separate payment-terms config table exists or is created here);
-- app.calculate_finance_tax (FIN-195) only when a caller supplies a tax code (opt-in --
-- it REJECTS rather than defaulting to zero when no approved tax rule covers the date,
-- never worked around); app.vendor_comparison_offers.normalized_amount (PRC-258, already
-- computed via app.calculate_vendor_rate + app.convert_finance_amount + app.apply_
-- finance_rounding, FIN-194) as the PO's own subtotal -- no FX conversion or rounding is
-- reimplemented anywhere in this migration, because none is needed: the comparison has
-- already normalized every offer into one currency before a selection is even possible.
-- app.rfq_requirement_lines (PRC-257) snapshotted into app.purchase_order_lines at draft
-- time -- never re-derived after. PO commitment creates no AP/journal/settlement/cash
-- movement anywhere in this migration (read-only composition with Finance, business rule
-- 24) and does not duplicate Operations execution (fulfillment is tracked as a
-- descriptive status + free-text evidence reference, never a second shipment/task table).
--
-- ===========================================================================
-- Scope boundaries and naming, disclosed rather than left implicit
-- ===========================================================================
--
-- * **No column-name collision** on this migration's one new governed table
--   (app.purchase_orders) -- confirmed by direct inspection (this is a brand-new table,
--   nothing to collide with) -- so this migration uses the literal `approval_status` /
--   `approval_request_id` axis-column names PRC-259's own convention establishes,
--   matching app.vendor_profiles / app.vendor_comparisons / app.procurement_exception_
--   requests (the three of PRC-259's four governed entities with no collision), NOT the
--   `governance_approval_status` / `governance_approval_request_id` rename PRC-259 had to
--   apply only to app.vendor_rate_versions (which already owned a same-named column with
--   a different, wider, pre-existing meaning -- no such pre-existing column exists here).
-- * **C-22 / ISS-2026-045, inherited, not re-introduced or silently worked around.**
--   `app._request_procurement_entity_approval` is called here exactly as PRC-259 built it
--   -- `p_value_amount numeric` with no currency-aware comparison inside `app.evaluate_
--   procurement_approval_requirement` (`p_value_amount >= v_policy.min_value_amount`
--   compares raw numbers regardless of currency, already disclosed as `ISS-2026-045`,
--   HIGH, OPEN). This migration threads `p_currency := v_po.currency` through to the
--   context snapshot (so a reviewer looking at the decision context still SEES the real
--   currency, never silently dropped) but that value is NOT consulted by the threshold
--   comparison itself -- the same known, disclosed gap `rate_version`/`vendor_selection`
--   already carry, now shared by `purchase_order` too. Not fixed here: correcting it is
--   the same genuine architectural decision (per-currency policy rows vs. a single
--   reference currency + FIN-194 conversion) `ISS-2026-045` already registers as requiring
--   a dedicated design task, out of this prompt's own mandate.
-- * **Fulfillment tracking is deliberately a descriptive status + free-text evidence
--   reference, never a second Operations table.** `fulfillment_status` (`not_started` ->
--   `partial` -> `fulfilled`, monotonic, no regression) + `fulfillment_reference` (a
--   polymorphic, application-validated, purely descriptive reference to whatever canonical
--   shipment/service evidence Operations owns -- never re-validated against a foreign
--   table, mirroring `app.procurement_exception_requests.related_entity_type`/
--   `related_entity_id`'s own already-established pattern, PRC-259) -- exactly business
--   rule 24 ("Fulfillment references canonical shipment/service evidence; PO does not
--   duplicate Operations execution"). No Operations shipment/task table is created,
--   altered, or read by this migration.
-- * **Invoice-match readiness is read-only exposure, not a match engine.** A future
--   Finance vendor-bill 3-way-match capability can read `app.purchase_orders`/`app.
--   purchase_order_lines` (already-governed, tenant/PRC-scoped) directly -- no AP,
--   journal, settlement, or cash-movement row is ever written by any function in this
--   migration (business rule 24, verified: zero INSERT/UPDATE anywhere in this file
--   touches any `app.finance_*` table).
-- * **Amendment is a governed re-version, never an in-place rewrite of an issued PO** --
--   `app.amend_purchase_order` marks the current `issued`/`acknowledged` row `superseded`
--   and inserts a brand-new `draft` row (`version + 1`, `revised_from_id` set, same
--   `po_number`), which must independently pass back through `app.submit_purchase_order_
--   for_approval` + `app.issue_purchase_order` before it takes effect -- mirrors `app.
--   revise_rfq` (PRC-257) / `app.revise_vendor_comparison` (PRC-258) exactly. Blocked once
--   `fulfillment_status <> 'not_started'` (business rule: "amendment against matched/
--   closed quantity" is blocked; this repository has no fine-grained per-line match/
--   quantity ledger, so `fulfillment_status` is the disclosed, bounded proxy for "has
--   fulfillment already begun against this commitment").
-- * **No external vendor-facing acknowledgement surface.** Identical reasoning to PRC-257
--   design note 5 (no external vendor-facing RFQ response surface) and PRC-258's own "no
--   vendor identity ever reaches this migration" -- building a live, anonymous, public
--   vendor acknowledgement endpoint would be this repository's first new anonymous entry
--   point since Prompt 251, an `ADR-0021` §3.2 batch-cut trigger on its own, for zero net
--   capability this prompt's own acceptance criteria requires. `app.acknowledge_purchase_
--   order` requires an authenticated INTERNAL actor recording the vendor's acknowledgement
--   (offline/email capture, the same established internal-capture pattern PRC-257's own
--   response capture already uses), with a mandatory `p_acknowledgement_note`.
-- * **No REST/GraphQL surface, no notification/job wiring** -- identical reasoning to
--   every prior Phase 6 checkpoint's own disclosed boundary: no REST/GraphQL adapter
--   exists for any domain yet, and this prompt's own spec text names no concrete
--   notification *event* this capability itself must emit.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
--   its final grants, the standing per-migration convention since `PLT-118`.
--
-- ===========================================================================
-- C-11 applied from the start (batch 257-259's own review, section 3): every cost-bearing
-- column on app.purchase_orders (currency/subtotal_amount/tax_code/tax_amount/total_
-- amount/payment_term_days/commercial_terms) is EXCLUDED from the `authenticated` grant
-- from the very first migration that creates this table -- column-restricted from day
-- one, never a blanket `select` later hardened. `app.purchase_order_events.reason` is
-- masked the same way, mirroring the hardened `app.vendor_comparison_events`.
-- ===========================================================================
--
-- ===========================================================================
-- C-05 applied from the start: every by-id READ RPC below (get_purchase_order, list_
-- purchase_order_lines, get_purchase_order_history) folds `app.has_active_tenant_
-- membership` into its own not-found branch BEFORE any real tenant_id is echoed into a
-- later insufficient_authority error -- the exact pattern `20260730670000_harden_
-- procurement_batch_257_259_review_fixes.sql` section 2 retrofitted onto 13 pre-existing
-- read RPCs, applied here from the start rather than needing a future hardening pass.
-- Write RPCs (submit/issue/acknowledge/amend/cancel/record_fulfillment) intentionally
-- keep this migration's OWN sibling write-RPC shape instead (not-found first with no
-- tenant_id, THEN evaluate_permission which does echo tenant_id) -- the same shape every
-- write RPC across PRC-257/258/259 already uses and which the batch's own C-05 fix left
-- unchanged (its own scope was 13 named READ RPCs, not writes); disclosed here as a
-- deliberate consistency choice, not an oversight.
-- ===========================================================================
--
-- ===========================================================================
-- Lock order (taxonomy C-04/C-21)
-- ===========================================================================
--
-- `app.draft_purchase_order_from_selection` locks the foreign PRC-258 parent row
-- (`app.vendor_comparisons`, `for update`) BEFORE creating brand-new `app.purchase_
-- orders`/`app.purchase_order_lines` rows (new rows need no lock) -- mirrors `app.draft_
-- rfq_from_sourcing`'s own "lock the foreign parent, never touched again" shape exactly.
-- Every OTHER function in this migration (`submit_purchase_order_for_approval`,
-- `issue_purchase_order`, `acknowledge_purchase_order`, `amend_purchase_order`,
-- `cancel_purchase_order`, `record_purchase_order_fulfillment_status`) locks exactly ONE
-- governed table row `for update` -- its own `app.purchase_orders` row -- and never a
-- second governed table row in the same transaction. No two functions in this migration
-- lock the same two tables in different orders, so no new C-21-shaped deadlock is
-- possible within this file. `app.cancel_purchase_order`'s own nested call to `app.
-- cancel_approval_request` (PLT-123, unmodified) touches `app.approval_requests`/`app.
-- approval_request_steps` under that function's own internal, unchanged locking -- not a
-- second lock this migration's own code takes directly.
--
-- ===========================================================================
-- ISS-2026-044 (app.request_approval's own missing unique_violation handler) -- not
-- reintroduced. `app.submit_purchase_order_for_approval` locks its own `app.purchase_
-- orders` row `for update` BEFORE calling `app._request_procurement_entity_approval`
-- (which calls `app.request_approval`), so a concurrent double-submit with the same
-- p_expected_version blocks on the row lock; the loser re-reads the post-commit row
-- (status already 'submitted') and fails cleanly at the pre-existing `status = 'draft'`
-- check before ever reaching the routing call with a colliding key -- the exact fix
-- shape `20260730670000` applied to `app.decide_vendor_profile_review`.
-- ===========================================================================

-- ===========================================================================
-- 1. app.purchase_order_number_counters + app.next_purchase_order_number -- one atomic,
--    tenant-scoped monotonic counter, mirroring app.next_rfq_number (PRC-257) / app.
--    next_quotation_number (COM-151) exactly. Assigned once, at draft time, stable across
--    every later version of the same PO (mirrors app.rfqs.rfq_number).
-- ===========================================================================

create table app.purchase_order_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq bigint not null default 0
);

comment on table app.purchase_order_number_counters is
  'PRC-260: one atomic, tenant-scoped monotonic counter for app.next_purchase_order_number() -- the same bounded, disclosed alternative to the full Configurable Numbering Engine (PLT-125) app.rfq_number_counters (PRC-257) / app.quotation_number_counters (COM-151) already established. Internal bookkeeping only -- no directly-readable row.';

alter table app.purchase_order_number_counters enable row level security;

create policy purchase_order_number_counters_none on app.purchase_order_number_counters
  for all to authenticated
  using (false);

create function app.next_purchase_order_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq bigint;
begin
  insert into app.purchase_order_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.purchase_order_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'PO-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

comment on function app.next_purchase_order_number is 'PRC-260: atomic collision-safe allocation via a single INSERT ... ON CONFLICT ... DO UPDATE ... RETURNING, mirroring app.next_rfq_number (PRC-257) exactly. Never recycled.';

-- ===========================================================================
-- 2. app.purchase_orders -- the PO root/version.
-- ===========================================================================

create table app.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid references app.org_units (id),
  po_number text not null,
  version integer not null default 1,
  revised_from_id uuid references app.purchase_orders (id),
  comparison_id uuid not null references app.vendor_comparisons (id),
  selected_offer_id uuid not null references app.vendor_comparison_offers (id),
  rfq_id uuid not null references app.rfqs (id),
  sourcing_request_id uuid not null references app.sourcing_requests (id),
  vendor_master_id uuid not null references app.master_records (id),
  currency text not null,
  subtotal_amount numeric(14, 2) not null,
  tax_code text,
  tax_amount numeric(14, 2) not null default 0,
  total_amount numeric(14, 2) not null,
  payment_term_days integer,
  expected_delivery_date date,
  service_period_start date,
  service_period_end date,
  commercial_terms text,
  notes text,
  status text not null default 'draft',
  approval_status text not null default 'not_required',
  approval_request_id uuid references app.approval_requests (id),
  fulfillment_status text not null default 'not_started',
  fulfillment_reference text,
  fulfillment_updated_at timestamptz,
  fulfillment_updated_by text,
  submitted_at timestamptz,
  submitted_by text,
  issued_at timestamptz,
  issued_by text,
  acknowledged_at timestamptz,
  acknowledged_by text,
  acknowledgement_note text,
  cancelled_at timestamptz,
  cancel_reason text,
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint purchase_orders_status_check check (status in ('draft', 'submitted', 'issued', 'acknowledged', 'cancelled', 'superseded')),
  constraint purchase_orders_approval_status_check check (approval_status in ('not_required', 'pending', 'approved', 'rejected')),
  constraint purchase_orders_fulfillment_status_check check (fulfillment_status in ('not_started', 'partial', 'fulfilled')),
  constraint purchase_orders_version_check check (version > 0),
  constraint purchase_orders_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint purchase_orders_subtotal_nonneg_check check (subtotal_amount >= 0),
  constraint purchase_orders_tax_amount_nonneg_check check (tax_amount >= 0),
  constraint purchase_orders_total_amount_nonneg_check check (total_amount >= 0),
  constraint purchase_orders_payment_term_check check (payment_term_days is null or payment_term_days >= 0),
  constraint purchase_orders_cancel_reason_check check (status <> 'cancelled' or (cancel_reason is not null and length(trim(cancel_reason)) > 0)),
  constraint purchase_orders_fulfillment_reference_check check (fulfillment_status = 'not_started' or (fulfillment_reference is not null and length(trim(fulfillment_reference)) > 0)),
  constraint purchase_orders_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.purchase_orders is
  'PRC-260: canonical purchase order root/version, created ONLY from an approved, submitted app.vendor_comparisons selection (PRC-258/259). A governed amendment (app.amend_purchase_order) marks the current row superseded and inserts a brand new draft version (version + 1, revised_from_id set, same po_number) -- never an in-place rewrite of an issued/acknowledged PO. approval_status/approval_request_id are the PRC-259 Platform Approval Engine binding axis, independent of status. fulfillment_status/fulfillment_reference are a descriptive proxy for Operations fulfillment progress -- never a second shipment/task table (business rule 24).';

create index purchase_orders_tenant_status_idx on app.purchase_orders (tenant_id, status);
create index purchase_orders_tenant_vendor_idx on app.purchase_orders (tenant_id, vendor_master_id);
create index purchase_orders_tenant_number_idx on app.purchase_orders (tenant_id, po_number);
create index purchase_orders_tenant_created_idx on app.purchase_orders (tenant_id, created_at desc);
create index purchase_orders_revised_from_idx on app.purchase_orders (revised_from_id) where revised_from_id is not null;

-- Business rule: "Block ... duplicate issue" -- at most one non-terminal PO may ever
-- exist for one comparison selection at a time. 'cancelled'/'superseded' are both
-- excluded so a governed amendment chain (each amended version leaves 'superseded'
-- before the next draft version is created) never trips this constraint against itself.
create unique index purchase_orders_comparison_active_unique
  on app.purchase_orders (comparison_id) where status not in ('cancelled', 'superseded');

create function app.touch_purchase_order_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

comment on function app.touch_purchase_order_row is 'PRC-260: shared before-update touch trigger for app.purchase_orders -- record_version += 1, updated_at := now(), mirroring app.touch_vendor_comparison_row (PRC-258) exactly.';

create trigger purchase_orders_touch_row
  before update on app.purchase_orders
  for each row
  execute function app.touch_purchase_order_row();

-- ===========================================================================
-- 3. app.purchase_order_lines -- itemized lines, snapshotted from app.rfq_requirement_
--    lines at draft time (never re-derived after). No per-line unit price: the
--    comparison this PO is drawn from only ever produces one header-level total
--    (app.vendor_comparison_offers.normalized_amount) -- a disclosed, bounded scope
--    boundary mirroring app.rfq_requirement_lines' own "add-at-creation only, no
--    in-place edit" precedent (PRC-257), not a missing capability.
-- ===========================================================================

create table app.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  purchase_order_id uuid not null references app.purchase_orders (id),
  line_no integer not null,
  source_requirement_line_id uuid references app.rfq_requirement_lines (id),
  description text not null,
  quantity numeric(14, 3),
  uom text,
  notes text,
  created_at timestamptz not null default now(),
  constraint purchase_order_lines_line_no_check check (line_no > 0),
  constraint purchase_order_lines_description_check check (length(trim(description)) > 0),
  constraint purchase_order_lines_quantity_nonneg_check check (quantity is null or quantity >= 0),
  constraint purchase_order_lines_unique unique (purchase_order_id, line_no)
);

comment on table app.purchase_order_lines is
  'PRC-260: itemized PO lines, snapshotted from app.rfq_requirement_lines (source_requirement_line_id, lineage only -- never re-read after snapshot) at app.draft_purchase_order_from_selection/app.amend_purchase_order time.';

create index purchase_order_lines_po_idx on app.purchase_order_lines (purchase_order_id);
create index purchase_order_lines_tenant_idx on app.purchase_order_lines (tenant_id);

-- ===========================================================================
-- 4. app.purchase_order_events -- append-only PO-root lifecycle history, mirrors
--    app.vendor_comparison_events (PRC-258) exactly. Fulfillment-status changes are NOT
--    root lifecycle transitions and do not write here (mirrors "offer-level actions
--    don't write to comparison_events" precedent) -- app.capture_audit_event still
--    records every one of those.
-- ===========================================================================

create table app.purchase_order_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  purchase_order_id uuid not null references app.purchase_orders (id),
  from_status text,
  to_status text not null,
  reason text,
  actor_auth_user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now()
);

comment on table app.purchase_order_events is 'PRC-260: append-only PO-root lifecycle history, one row per real status transition, mirroring app.vendor_comparison_events (PRC-258) exactly.';

create index purchase_order_events_po_idx on app.purchase_order_events (purchase_order_id, occurred_at);

-- ===========================================================================
-- 5. app.draft_purchase_order_from_selection (PRC:Create + PRC:View cost, +FIN:View when
--    p_tax_code is supplied). The only creation path -- inherits vendor/demand/quotation
--    exactly, no re-entry.
-- ===========================================================================

create function app.draft_purchase_order_from_selection(
  p_tenant_id uuid,
  p_comparison_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_tax_code text default null,
  p_payment_term_days integer default null,
  p_expected_delivery_date date default null,
  p_service_period_start date default null,
  p_service_period_end date default null,
  p_commercial_terms text default null,
  p_notes text default null
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_decision app.rbac_decision;
  v_comparison app.vendor_comparisons;
  v_offer app.vendor_comparison_offers;
  v_vendor_status text;
  v_existing app.purchase_orders;
  v_tax_result jsonb;
  v_tax_amount numeric := 0;
  v_payment_term_days integer;
  v_number text;
  v_new_po app.purchase_orders;
  v_constraint_name text;
  v_line record;
  v_line_no integer := 0;
begin
  -- Whole-operation authority gates together, before any state-dependent read (C-05
  -- discipline, PRC-258's own established ordering).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View cost');
  if not v_cost_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_cost_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_tax_code is not null and not app.check_finance_tax_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;

  -- design note (lock order, migration header): locks the foreign PRC-258 parent row,
  -- never touched again by this function.
  select * into v_comparison from app.vendor_comparisons where id = p_comparison_id for update;
  if not found then
    raise exception 'vendor_comparison_not_found: %', p_comparison_id using errcode = 'no_data_found';
  end if;
  if v_comparison.tenant_id <> p_tenant_id then
    raise exception 'tenant_mismatch: vendor comparison % does not belong to tenant %', p_comparison_id, p_tenant_id
      using errcode = 'check_violation';
  end if;
  if v_comparison.status <> 'submitted' then
    raise exception 'invalid_source_status: vendor comparison % is % -- a purchase order may only be drafted from a submitted comparison', p_comparison_id, v_comparison.status
      using errcode = 'check_violation';
  end if;
  if v_comparison.approval_status not in ('approved', 'not_required') then
    raise exception 'selection_approval_pending: vendor comparison % approval_status is % (must be approved or not_required)', p_comparison_id, v_comparison.approval_status
      using errcode = 'check_violation';
  end if;
  if v_comparison.selected_offer_id is null then
    raise exception 'no_selected_offer: vendor comparison % has no selected offer', p_comparison_id using errcode = 'check_violation';
  end if;

  select * into v_offer from app.vendor_comparison_offers where id = v_comparison.selected_offer_id and comparison_id = p_comparison_id;
  if not found then
    raise exception 'vendor_comparison_offer_not_found: % does not belong to comparison %', v_comparison.selected_offer_id, p_comparison_id using errcode = 'no_data_found';
  end if;
  if not v_offer.included then
    raise exception 'excluded_offer: selected offer % is excluded and cannot be committed', v_offer.id using errcode = 'check_violation';
  end if;
  if v_offer.normalized_amount is null then
    raise exception 'offer_not_normalized: selected offer % has no normalized amount to commit', v_offer.id using errcode = 'check_violation';
  end if;

  select lifecycle_status into v_vendor_status from app.vendor_profiles where master_record_id = v_offer.vendor_master_id;
  if v_vendor_status is distinct from 'active' then
    raise exception 'vendor_not_active: vendor % is % -- a purchase order cannot be committed to a non-active vendor', v_offer.vendor_master_id, coalesce(v_vendor_status, 'unregistered')
      using errcode = 'check_violation';
  end if;

  -- Resolved BEFORE the idempotency check below (not after) -- the replay comparison
  -- must compare against the RESOLVED value, not the raw caller-supplied parameter, or
  -- a caller who omitted p_payment_term_days (defaulted from the vendor) would see their
  -- own identical-tuple replay incorrectly rejected as idempotency_key_conflict (found
  -- live iterating this migration's own db-test before it was ever declared COMPLETED).
  v_payment_term_days := p_payment_term_days;
  if v_payment_term_days is null then
    select payment_term_days into v_payment_term_days from app.vendor_profiles where master_record_id = v_offer.vendor_master_id;
  end if;

  -- taxonomy C-01: idempotency replay compares the FULL caller-supplied target tuple
  -- (payment_term_days compared as its RESOLVED value -- see comment above).
  select * into v_existing from app.purchase_orders where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.comparison_id is distinct from p_comparison_id
       or v_existing.tax_code is distinct from p_tax_code
       or v_existing.payment_term_days is distinct from v_payment_term_days
       or v_existing.expected_delivery_date is distinct from p_expected_delivery_date
       or v_existing.service_period_start is distinct from p_service_period_start
       or v_existing.service_period_end is distinct from p_service_period_end
       or v_existing.commercial_terms is distinct from p_commercial_terms
       or v_existing.notes is distinct from p_notes then
      raise exception 'idempotency_key_conflict: key % was already used for a different purchase order', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  if p_tax_code is not null then
    v_tax_result := app.calculate_finance_tax(p_tenant_id, p_tax_code, v_offer.normalized_amount, current_date, p_actor_auth_user_id);
    if (v_tax_result ->> 'currency') is distinct from v_comparison.comparison_currency then
      -- C-22-style guard, applied deliberately: app.calculate_finance_tax computes a tax
      -- amount in whatever currency its own resolved rule is denominated in, with no FX
      -- step of its own -- accepting a currency-mismatched tax amount at face value would
      -- silently mix two different currencies into one total_amount. Fail closed instead.
      raise exception 'tax_rule_currency_mismatch: tax rule for % is denominated in % but this purchase order is %', p_tax_code, v_tax_result ->> 'currency', v_comparison.comparison_currency
        using errcode = 'check_violation';
    end if;
    v_tax_amount := (v_tax_result ->> 'taxAmount')::numeric;
  end if;

  v_number := app.next_purchase_order_number(p_tenant_id);

  begin
    insert into app.purchase_orders (
      tenant_id, org_unit_id, po_number, version, comparison_id, selected_offer_id, rfq_id, sourcing_request_id, vendor_master_id,
      currency, subtotal_amount, tax_code, tax_amount, total_amount, payment_term_days,
      expected_delivery_date, service_period_start, service_period_end, commercial_terms, notes,
      status, idempotency_key, created_by
    ) values (
      p_tenant_id, v_comparison.org_unit_id, v_number, 1, p_comparison_id, v_offer.id, v_comparison.rfq_id, v_comparison.sourcing_request_id, v_offer.vendor_master_id,
      v_comparison.comparison_currency, v_offer.normalized_amount, p_tax_code, v_tax_amount, v_offer.normalized_amount + v_tax_amount, v_payment_term_days,
      p_expected_delivery_date, p_service_period_start, p_service_period_end, p_commercial_terms, p_notes,
      'draft', p_idempotency_key, p_actor_label
    )
    returning * into v_new_po;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'purchase_orders_tenant_idempotency_unique' then
        select * into v_existing from app.purchase_orders where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.comparison_id is distinct from p_comparison_id
             or v_existing.tax_code is distinct from p_tax_code
             or v_existing.payment_term_days is distinct from v_payment_term_days
             or v_existing.expected_delivery_date is distinct from p_expected_delivery_date
             or v_existing.service_period_start is distinct from p_service_period_start
             or v_existing.service_period_end is distinct from p_service_period_end
             or v_existing.commercial_terms is distinct from p_commercial_terms
             or v_existing.notes is distinct from p_notes then
            raise exception 'idempotency_key_conflict: key % was already used for a different purchase order', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      elsif v_constraint_name = 'purchase_orders_comparison_active_unique' then
        raise exception 'duplicate_issue: vendor comparison % already has an active purchase order', p_comparison_id
          using errcode = 'check_violation';
      end if;
      raise;
  end;

  for v_line in select * from app.rfq_requirement_lines where rfq_id = v_comparison.rfq_id order by line_no loop
    v_line_no := v_line_no + 1;
    insert into app.purchase_order_lines (tenant_id, purchase_order_id, line_no, source_requirement_line_id, description, quantity, uom, notes)
    values (p_tenant_id, v_new_po.id, v_line_no, v_line.id, v_line.description, v_line.quantity, v_line.uom, v_line.notes);
  end loop;

  insert into app.purchase_order_events (tenant_id, purchase_order_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_new_po.id, null, 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'draft_purchase_order_from_selection',
    'app.purchase_orders', v_new_po.id, 'success', null, null, to_jsonb(v_new_po)
  );

  return v_new_po;
end;
$$;

comment on function app.draft_purchase_order_from_selection is
  'PRC-260: creates (or, on idempotency-key replay, returns the existing) a draft purchase order from an approved, submitted vendor comparison selection -- inherits vendor/demand/quotation exactly, no re-entry. subtotal_amount is the selected offer''s own already-normalized amount (app.vendor_comparison_offers.normalized_amount, PRC-258) verbatim -- never recomputed. tax_amount is 0 unless p_tax_code is supplied, in which case app.calculate_finance_tax (FIN-195) computes it and this function verifies the resolved tax rule''s own currency matches the PO''s currency before accepting it. Lines are snapshotted from app.rfq_requirement_lines at this moment -- never re-derived after.';

-- ===========================================================================
-- 6. app.submit_purchase_order_for_approval (PRC:Edit) -- the routing trigger point.
--    draft -> submitted (terminal within this migration''s own submit/issue split; the
--    gated "next lifecycle transition" is app.issue_purchase_order below).
-- ===========================================================================

create function app.submit_purchase_order_for_approval(
  p_purchase_order_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_po app.purchase_orders;
  v_gov_required boolean;
  v_gov_approval_status text;
  v_gov_approval_request_id uuid;
begin
  -- Locked BEFORE the routing call below -- closes the ISS-2026-044-shaped race
  -- documented in this migration''s own header.
  select * into v_po from app.purchase_orders where id = p_purchase_order_id for update;
  if not found then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_po.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_po.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_po.record_version <> p_expected_version then
    raise exception 'stale_version: purchase order % expected version % but found %', p_purchase_order_id, p_expected_version, v_po.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_po.status <> 'draft' then
    raise exception 'invalid_transition: purchase order % is % and cannot be submitted for approval', p_purchase_order_id, v_po.status
      using errcode = 'check_violation';
  end if;

  select r.required, r.approval_status, r.approval_request_id into v_gov_required, v_gov_approval_status, v_gov_approval_request_id
  from app._request_procurement_entity_approval(
    'purchase_order', v_po.tenant_id, p_purchase_order_id, v_po.total_amount, v_po.currency,
    jsonb_build_object('poNumber', v_po.po_number, 'vendorMasterId', v_po.vendor_master_id, 'comparisonId', v_po.comparison_id),
    p_expected_version + 1, 'purchase_order:' || p_purchase_order_id::text, p_actor_auth_user_id, p_actor_label
  ) r;

  update app.purchase_orders
  set status = 'submitted', submitted_at = now(), submitted_by = p_actor_label,
      approval_status = v_gov_approval_status, approval_request_id = v_gov_approval_request_id
  where id = p_purchase_order_id and record_version = p_expected_version
  returning * into v_po;
  if not found then
    raise exception 'stale_version: purchase order % target row was concurrently modified (expected version %)', p_purchase_order_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.purchase_order_events (tenant_id, purchase_order_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_po.tenant_id, p_purchase_order_id, 'draft', 'submitted', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_po.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_purchase_order_for_approval',
    'app.purchase_orders', v_po.id, 'success', null, null, jsonb_build_object('approval_status', v_gov_approval_status)
  );

  return v_po;
end;
$$;

comment on function app.submit_purchase_order_for_approval is
  'PRC-260: draft -> submitted (PRC:Edit -- Procurement submits, per access rule 26). Routes for platform-engine governance approval when app.procurement_approval_policies has a published purchase_order policy this PO''s total_amount crosses (ISS-2026-045: currency-blind comparison, disclosed in this migration''s own header, not fixed here). app.issue_purchase_order requires approval_status in (approved, not_required) before the PO can actually be issued.';

-- ===========================================================================
-- 7. app.issue_purchase_order (PRC:Edit) -- the gated "next lifecycle transition."
--    submitted -> issued.
-- ===========================================================================

create function app.issue_purchase_order(
  p_purchase_order_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_po app.purchase_orders;
begin
  select * into v_po from app.purchase_orders where id = p_purchase_order_id for update;
  if not found then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_po.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_po.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_po.record_version <> p_expected_version then
    raise exception 'stale_version: purchase order % expected version % but found %', p_purchase_order_id, p_expected_version, v_po.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_po.status <> 'submitted' then
    raise exception 'invalid_transition: purchase order % is % and cannot be issued', p_purchase_order_id, v_po.status
      using errcode = 'check_violation';
  end if;
  if v_po.approval_status not in ('approved', 'not_required') then
    raise exception 'purchase_order_approval_pending: purchase order % approval_status is % (must be approved or not_required)', p_purchase_order_id, v_po.approval_status
      using errcode = 'check_violation';
  end if;

  update app.purchase_orders
  set status = 'issued', issued_at = now(), issued_by = p_actor_label
  where id = p_purchase_order_id and record_version = p_expected_version
  returning * into v_po;
  if not found then
    raise exception 'stale_version: purchase order % target row was concurrently modified (expected version %)', p_purchase_order_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.purchase_order_events (tenant_id, purchase_order_id, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_po.tenant_id, p_purchase_order_id, 'submitted', 'issued', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_po.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_purchase_order',
    'app.purchase_orders', v_po.id, 'success', null, null, '{}'::jsonb
  );

  return v_po;
end;
$$;

comment on function app.issue_purchase_order is 'PRC-260: submitted -> issued, PRC:Edit, additionally gated on approval_status in (approved, not_required) -- see app.submit_purchase_order_for_approval''s own comment.';

-- ===========================================================================
-- 8. app.acknowledge_purchase_order (PRC:Edit) -- internal capture of vendor
--    acknowledgement (no external vendor-facing surface, migration header).
-- ===========================================================================

create function app.acknowledge_purchase_order(
  p_purchase_order_id uuid,
  p_expected_version integer,
  p_acknowledgement_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_po app.purchase_orders;
begin
  if p_acknowledgement_note is null or length(trim(p_acknowledgement_note)) = 0 then
    raise exception 'reason_required: a non-empty acknowledgement note is required' using errcode = 'check_violation';
  end if;

  select * into v_po from app.purchase_orders where id = p_purchase_order_id for update;
  if not found then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_po.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_po.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_po.record_version <> p_expected_version then
    raise exception 'stale_version: purchase order % expected version % but found %', p_purchase_order_id, p_expected_version, v_po.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_po.status <> 'issued' then
    raise exception 'invalid_transition: purchase order % is % and cannot be acknowledged', p_purchase_order_id, v_po.status
      using errcode = 'check_violation';
  end if;

  update app.purchase_orders
  set status = 'acknowledged', acknowledged_at = now(), acknowledged_by = p_actor_label, acknowledgement_note = p_acknowledgement_note
  where id = p_purchase_order_id and record_version = p_expected_version
  returning * into v_po;
  if not found then
    raise exception 'stale_version: purchase order % target row was concurrently modified (expected version %)', p_purchase_order_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.purchase_order_events (tenant_id, purchase_order_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_po.tenant_id, p_purchase_order_id, 'issued', 'acknowledged', p_acknowledgement_note, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_po.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_purchase_order',
    'app.purchase_orders', v_po.id, 'success', p_acknowledgement_note, null, '{}'::jsonb
  );

  return v_po;
end;
$$;

comment on function app.acknowledge_purchase_order is 'PRC-260: issued -> acknowledged, PRC:Edit, mandatory note. Internal capture of the vendor''s own acknowledgement (offline/email, no external vendor-facing surface -- migration header).';

-- ===========================================================================
-- 9. app.record_purchase_order_fulfillment_status (PRC:Edit) -- descriptive, monotonic
--    fulfillment tracking. Never writes to app.purchase_order_events (not a root
--    lifecycle transition) -- app.capture_audit_event records it.
-- ===========================================================================

create function app.record_purchase_order_fulfillment_status(
  p_purchase_order_id uuid,
  p_expected_version integer,
  p_fulfillment_status text,
  p_fulfillment_reference text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_po app.purchase_orders;
  v_rank_current integer;
  v_rank_new integer;
begin
  if p_fulfillment_status not in ('partial', 'fulfilled') then
    raise exception 'invalid_fulfillment_status: % is not a valid target fulfillment status', p_fulfillment_status using errcode = 'check_violation';
  end if;
  if p_fulfillment_reference is null or length(trim(p_fulfillment_reference)) = 0 then
    raise exception 'reason_required: a non-empty fulfillment_reference (canonical shipment/service evidence) is required' using errcode = 'check_violation';
  end if;

  select * into v_po from app.purchase_orders where id = p_purchase_order_id for update;
  if not found then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_po.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_po.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_po.record_version <> p_expected_version then
    raise exception 'stale_version: purchase order % expected version % but found %', p_purchase_order_id, p_expected_version, v_po.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_po.status not in ('issued', 'acknowledged') then
    raise exception 'invalid_transition: purchase order % is % -- fulfillment can only be tracked on an issued or acknowledged PO', p_purchase_order_id, v_po.status
      using errcode = 'check_violation';
  end if;

  v_rank_current := case v_po.fulfillment_status when 'not_started' then 0 when 'partial' then 1 else 2 end;
  v_rank_new := case p_fulfillment_status when 'partial' then 1 else 2 end;
  if v_rank_new <= v_rank_current then
    raise exception 'invalid_fulfillment_transition: fulfillment_status cannot move from % to %', v_po.fulfillment_status, p_fulfillment_status
      using errcode = 'check_violation';
  end if;

  update app.purchase_orders
  set fulfillment_status = p_fulfillment_status, fulfillment_reference = p_fulfillment_reference,
      fulfillment_updated_at = now(), fulfillment_updated_by = p_actor_label
  where id = p_purchase_order_id and record_version = p_expected_version
  returning * into v_po;
  if not found then
    raise exception 'stale_version: purchase order % target row was concurrently modified (expected version %)', p_purchase_order_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_po.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_purchase_order_fulfillment_status',
    'app.purchase_orders', v_po.id, 'success', p_fulfillment_reference, null, jsonb_build_object('fulfillment_status', p_fulfillment_status)
  );

  return v_po;
end;
$$;

comment on function app.record_purchase_order_fulfillment_status is
  'PRC-260: monotonic not_started -> partial -> fulfilled, PRC:Edit, mandatory fulfillment_reference (a polymorphic, application-validated, purely descriptive reference to canonical Operations shipment/service evidence -- never re-validated against a foreign table, mirrors app.procurement_exception_requests'' own related_entity_type/id pattern). Not a root lifecycle transition -- does not write to app.purchase_order_events.';

-- ===========================================================================
-- 10. app.amend_purchase_order (PRC:Edit, mandatory reason) -- governed re-version.
-- ===========================================================================

create function app.amend_purchase_order(
  p_purchase_order_id uuid,
  p_expected_version integer,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_payment_term_days integer default null,
  p_expected_delivery_date date default null,
  p_service_period_start date default null,
  p_service_period_end date default null,
  p_commercial_terms text default null,
  p_notes text default null
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_po app.purchase_orders;
  v_existing app.purchase_orders;
  v_resolved_payment_term integer;
  v_resolved_delivery date;
  v_resolved_service_start date;
  v_resolved_service_end date;
  v_resolved_terms text;
  v_resolved_notes text;
  v_new_po app.purchase_orders;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to amend a purchase order' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: p_idempotency_key must not be empty' using errcode = 'check_violation';
  end if;

  select * into v_po from app.purchase_orders where id = p_purchase_order_id for update;
  if not found then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_po.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_po.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_po.record_version <> p_expected_version then
    raise exception 'stale_version: purchase order % expected version % but found %', p_purchase_order_id, p_expected_version, v_po.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_po.status not in ('issued', 'acknowledged') then
    raise exception 'invalid_transition: purchase order % is % and cannot be amended', p_purchase_order_id, v_po.status
      using errcode = 'check_violation';
  end if;
  if v_po.fulfillment_status <> 'not_started' then
    raise exception 'fulfillment_in_progress: purchase order % has fulfillment_status % -- amendment is blocked once fulfillment has begun', p_purchase_order_id, v_po.fulfillment_status
      using errcode = 'check_violation';
  end if;

  v_resolved_payment_term := coalesce(p_payment_term_days, v_po.payment_term_days);
  v_resolved_delivery := coalesce(p_expected_delivery_date, v_po.expected_delivery_date);
  v_resolved_service_start := coalesce(p_service_period_start, v_po.service_period_start);
  v_resolved_service_end := coalesce(p_service_period_end, v_po.service_period_end);
  v_resolved_terms := coalesce(p_commercial_terms, v_po.commercial_terms);
  v_resolved_notes := coalesce(p_notes, v_po.notes);

  -- taxonomy C-01: idempotency replay compares the resolved override fields, not just
  -- revised_from_id, mirroring app.revise_rfq (PRC-257) / app.revise_vendor_comparison
  -- (PRC-258) exactly.
  select * into v_existing from app.purchase_orders where tenant_id = v_po.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.revised_from_id is distinct from p_purchase_order_id
       or v_existing.payment_term_days is distinct from v_resolved_payment_term
       or v_existing.expected_delivery_date is distinct from v_resolved_delivery
       or v_existing.service_period_start is distinct from v_resolved_service_start
       or v_existing.service_period_end is distinct from v_resolved_service_end
       or v_existing.commercial_terms is distinct from v_resolved_terms
       or v_existing.notes is distinct from v_resolved_notes then
      raise exception 'idempotency_key_conflict: key % was already used for a different amendment', p_idempotency_key
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  update app.purchase_orders
  set status = 'superseded'
  where id = p_purchase_order_id and record_version = p_expected_version
  returning * into v_po;
  if not found then
    raise exception 'stale_version: purchase order % target row was concurrently modified (expected version %)', p_purchase_order_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.purchase_orders (
    tenant_id, org_unit_id, po_number, version, revised_from_id, comparison_id, selected_offer_id, rfq_id, sourcing_request_id, vendor_master_id,
    currency, subtotal_amount, tax_code, tax_amount, total_amount, payment_term_days,
    expected_delivery_date, service_period_start, service_period_end, commercial_terms, notes,
    status, idempotency_key, created_by
  ) values (
    v_po.tenant_id, v_po.org_unit_id, v_po.po_number, v_po.version + 1, v_po.id, v_po.comparison_id, v_po.selected_offer_id, v_po.rfq_id, v_po.sourcing_request_id, v_po.vendor_master_id,
    v_po.currency, v_po.subtotal_amount, v_po.tax_code, v_po.tax_amount, v_po.total_amount, v_resolved_payment_term,
    v_resolved_delivery, v_resolved_service_start, v_resolved_service_end, v_resolved_terms, v_resolved_notes,
    'draft', p_idempotency_key, p_actor_label
  )
  returning * into v_new_po;

  insert into app.purchase_order_lines (tenant_id, purchase_order_id, line_no, source_requirement_line_id, description, quantity, uom, notes)
  select tenant_id, v_new_po.id, line_no, source_requirement_line_id, description, quantity, uom, notes
  from app.purchase_order_lines where purchase_order_id = p_purchase_order_id order by line_no;

  insert into app.purchase_order_events (tenant_id, purchase_order_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_po.tenant_id, p_purchase_order_id, v_po.status, 'superseded', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_po.tenant_id, p_actor_auth_user_id, p_actor_label, 'amend_purchase_order',
    'app.purchase_orders', v_new_po.id, 'success', p_reason, null, jsonb_build_object('revised_from_id', v_po.id)
  );

  return v_new_po;
end;
$$;

comment on function app.amend_purchase_order is
  'PRC-260: only from issued|acknowledged (blocked once fulfillment_status <> not_started), mandatory reason. Marks the current version superseded and inserts a brand new draft version (version + 1, revised_from_id, same po_number, same commercial totals/lines -- only payment_term_days/dates/commercial_terms/notes may change) -- mirrors app.revise_rfq/app.revise_vendor_comparison exactly. The new draft version must independently pass back through app.submit_purchase_order_for_approval + app.issue_purchase_order before it takes effect. Idempotent on (tenant_id, idempotency_key), replay compares the resolved override fields.';

-- ===========================================================================
-- 11. app.cancel_purchase_order (PRC:Edit, mandatory reason) -- cancel-eligible only.
-- ===========================================================================

create function app.cancel_purchase_order(
  p_purchase_order_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_po app.purchase_orders;
  v_from_status text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a purchase order' using errcode = 'check_violation';
  end if;

  select * into v_po from app.purchase_orders where id = p_purchase_order_id for update;
  if not found then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_po.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_po.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_po.record_version <> p_expected_version then
    raise exception 'stale_version: purchase order % expected version % but found %', p_purchase_order_id, p_expected_version, v_po.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_po.status not in ('draft', 'submitted', 'issued', 'acknowledged') then
    raise exception 'invalid_transition: purchase order % is % and cannot be cancelled', p_purchase_order_id, v_po.status
      using errcode = 'check_violation';
  end if;
  if v_po.status in ('issued', 'acknowledged') and v_po.fulfillment_status <> 'not_started' then
    raise exception 'fulfillment_in_progress: purchase order % has fulfillment_status % -- cancel-eligible only while no fulfillment has begun', p_purchase_order_id, v_po.fulfillment_status
      using errcode = 'check_violation';
  end if;

  v_from_status := v_po.status;

  if v_po.approval_request_id is not null and v_po.approval_status = 'pending' then
    -- Nested SECURITY DEFINER call executes with this function's own definer rights --
    -- app.cancel_approval_request (PLT-123) is service_role-only for direct external
    -- callers, but reachable here exactly as app.cancel_procurement_exception_request
    -- (PRC-259) already established.
    perform app.cancel_approval_request(v_po.approval_request_id, p_actor_auth_user_id, p_actor_label, p_reason);
  end if;

  update app.purchase_orders
  set status = 'cancelled', cancelled_at = now(), cancel_reason = p_reason
  where id = p_purchase_order_id and record_version = p_expected_version
  returning * into v_po;
  if not found then
    raise exception 'stale_version: purchase order % target row was concurrently modified (expected version %)', p_purchase_order_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.purchase_order_events (tenant_id, purchase_order_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (v_po.tenant_id, p_purchase_order_id, v_from_status, 'cancelled', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_po.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_purchase_order',
    'app.purchase_orders', v_po.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_po;
end;
$$;

comment on function app.cancel_purchase_order is
  'PRC-260: draft|submitted|issued|acknowledged -> cancelled, PRC:Edit, mandatory reason. Cancel-eligible only -- blocked once fulfillment_status <> not_started on an issued/acknowledged PO. Cancels the bound app.approval_requests row too when one is still pending (mirrors app.cancel_procurement_exception_request, PRC-259).';

-- ===========================================================================
-- 12. app.decide_purchase_order_approval_step -- the one domain-specific sync wrapper
--    over the Approval Engine for purchase orders, mirroring app.decide_vendor_
--    selection_approval_step (PRC-259, as hardened by `20260730670000`) EXACTLY,
--    including: app.assert_actor_is_session_identity as the first statement (C-13),
--    p_reauth_confirmed_at with the 5-minute MFA freshness check (C-18, PRC-254/COM-157
--    pattern), and a typed not-found error (never an all-NULL composite) if the bound
--    entity no longer resolves (batch 257-259's own F8 fix).
-- ===========================================================================

create function app.decide_purchase_order_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reauth_confirmed_at timestamptz,
  p_reason text default null
)
returns app.purchase_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_po app.purchase_orders;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;
  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'purchase_order' or v_request.entity_id is null then
    raise exception 'not_a_purchase_order_approval: approval request % is not a purchase order approval', v_request.id
      using errcode = 'check_violation';
  end if;

  -- The real decision, eligibility/self-approval/idempotency checks and all -- never
  -- re-implemented here (mirrors app.decide_vendor_selection_approval_step, PRC-259).
  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  if v_updated_request.status = 'approved' then
    update app.purchase_orders set approval_status = 'approved'
    where id = v_request.entity_id
    returning * into v_po;
  elsif v_updated_request.status = 'rejected' then
    update app.purchase_orders set approval_status = 'rejected'
    where id = v_request.entity_id
    returning * into v_po;
  else
    select * into v_po from app.purchase_orders where id = v_request.entity_id;
  end if;

  if v_po.id is null then
    raise exception 'purchase_order_target_not_found: approval request % entity % no longer resolves to a purchase order', v_request.id, v_request.entity_id
      using errcode = 'no_data_found';
  end if;

  return v_po;
end;
$$;

comment on function app.decide_purchase_order_approval_step is
  'PRC-260: wraps app.decide_approval_step (PLT-123, unchanged) and syncs app.purchase_orders.approval_status only once the bound request reaches a final state -- app.purchase_orders'' own before-update trigger bumps record_version automatically, no manual increment needed here. Mirrors app.decide_vendor_selection_approval_step (PRC-259, as hardened) exactly: requires p_reauth_confirmed_at (5-minute MFA freshness window) and raises a typed not-found error instead of an all-NULL composite when the bound entity is missing.';

-- ===========================================================================
-- 13. Reads (PRC:View, cost fields masked behind PRC:View cost -- by-id reads fold
--    tenant membership into the not-found branch from the start, C-05).
-- ===========================================================================

create function app.get_purchase_order(p_purchase_order_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, org_unit_id uuid, po_number text, version integer, revised_from_id uuid,
  comparison_id uuid, selected_offer_id uuid, rfq_id uuid, sourcing_request_id uuid, vendor_master_id uuid,
  currency text, subtotal_amount numeric, tax_code text, tax_amount numeric, total_amount numeric, payment_term_days integer,
  cost_masked boolean,
  expected_delivery_date date, service_period_start date, service_period_end date, commercial_terms text, notes text,
  status text, approval_status text, approval_request_id uuid,
  fulfillment_status text, fulfillment_reference text, fulfillment_updated_at timestamptz, fulfillment_updated_by text,
  submitted_at timestamptz, submitted_by text, issued_at timestamptz, issued_by text,
  acknowledged_at timestamptz, acknowledged_by text, acknowledgement_note text,
  cancelled_at timestamptz, cancel_reason text,
  idempotency_key text, record_version integer, created_by text, created_at timestamptz, updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
  v_cost_allowed boolean;
begin
  select po.tenant_id into v_tenant_id from app.purchase_orders po where po.id = p_purchase_order_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_allowed := app.has_prc_view_cost(v_tenant_id, p_actor_auth_user_id);

  return query
  select
    po.id, po.tenant_id, po.org_unit_id, po.po_number, po.version, po.revised_from_id,
    po.comparison_id, po.selected_offer_id, po.rfq_id, po.sourcing_request_id, po.vendor_master_id,
    case when v_cost_allowed then po.currency else null end,
    case when v_cost_allowed then po.subtotal_amount else null end,
    case when v_cost_allowed then po.tax_code else null end,
    case when v_cost_allowed then po.tax_amount else null end,
    case when v_cost_allowed then po.total_amount else null end,
    case when v_cost_allowed then po.payment_term_days else null end,
    not v_cost_allowed,
    po.expected_delivery_date, po.service_period_start, po.service_period_end,
    case when v_cost_allowed then po.commercial_terms else null end,
    po.notes,
    po.status, po.approval_status, po.approval_request_id,
    po.fulfillment_status, po.fulfillment_reference, po.fulfillment_updated_at, po.fulfillment_updated_by,
    po.submitted_at, po.submitted_by, po.issued_at, po.issued_by,
    po.acknowledged_at, po.acknowledged_by, po.acknowledgement_note,
    po.cancelled_at, po.cancel_reason,
    po.idempotency_key, po.record_version, po.created_by, po.created_at, po.updated_at
  from app.purchase_orders po
  where po.id = p_purchase_order_id;
end;
$$;

comment on function app.get_purchase_order is 'PRC-260: single PO read. Masks currency/subtotal_amount/tax_code/tax_amount/total_amount/payment_term_days/commercial_terms behind PRC:View cost, threading p_actor_auth_user_id explicitly into app.has_prc_view_cost -- mirrors app.list_rfq_responses'' own partial-masking shape (not app.get_vendor_comparison''s all-or-nothing shape), since Operations/Finance viewers need non-cost fields (status/dates/fulfillment) without PRC:View cost (access rule 26). Not-found branch folds tenant membership in from the start (C-05).';

create function app.list_purchase_orders(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status_filter text default null,
  p_vendor_master_id uuid default null,
  p_limit integer default 100
)
returns table (
  id uuid, tenant_id uuid, org_unit_id uuid, po_number text, version integer, revised_from_id uuid,
  comparison_id uuid, selected_offer_id uuid, rfq_id uuid, sourcing_request_id uuid, vendor_master_id uuid,
  currency text, subtotal_amount numeric, tax_code text, tax_amount numeric, total_amount numeric, payment_term_days integer,
  cost_masked boolean,
  expected_delivery_date date, service_period_start date, service_period_end date, commercial_terms text, notes text,
  status text, approval_status text, approval_request_id uuid,
  fulfillment_status text, fulfillment_reference text, fulfillment_updated_at timestamptz, fulfillment_updated_by text,
  submitted_at timestamptz, submitted_by text, issued_at timestamptz, issued_by text,
  acknowledged_at timestamptz, acknowledged_by text, acknowledgement_note text,
  cancelled_at timestamptz, cancel_reason text,
  idempotency_key text, record_version integer, created_by text, created_at timestamptz, updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cost_allowed boolean;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_status_filter is not null and p_status_filter not in ('draft', 'submitted', 'issued', 'acknowledged', 'cancelled', 'superseded') then
    raise exception 'invalid_status_filter: % is not a valid purchase order status', p_status_filter using errcode = 'check_violation';
  end if;
  v_cost_allowed := app.has_prc_view_cost(p_tenant_id, p_actor_auth_user_id);

  return query
  select
    po.id, po.tenant_id, po.org_unit_id, po.po_number, po.version, po.revised_from_id,
    po.comparison_id, po.selected_offer_id, po.rfq_id, po.sourcing_request_id, po.vendor_master_id,
    case when v_cost_allowed then po.currency else null end,
    case when v_cost_allowed then po.subtotal_amount else null end,
    case when v_cost_allowed then po.tax_code else null end,
    case when v_cost_allowed then po.tax_amount else null end,
    case when v_cost_allowed then po.total_amount else null end,
    case when v_cost_allowed then po.payment_term_days else null end,
    not v_cost_allowed,
    po.expected_delivery_date, po.service_period_start, po.service_period_end,
    case when v_cost_allowed then po.commercial_terms else null end,
    po.notes,
    po.status, po.approval_status, po.approval_request_id,
    po.fulfillment_status, po.fulfillment_reference, po.fulfillment_updated_at, po.fulfillment_updated_by,
    po.submitted_at, po.submitted_by, po.issued_at, po.issued_by,
    po.acknowledged_at, po.acknowledged_by, po.acknowledgement_note,
    po.cancelled_at, po.cancel_reason,
    po.idempotency_key, po.record_version, po.created_by, po.created_at, po.updated_at
  from app.purchase_orders po
  where po.tenant_id = p_tenant_id
    and (p_status_filter is not null or po.status <> 'superseded')
    and (p_status_filter is null or po.status = p_status_filter)
    and (p_vendor_master_id is null or po.vendor_master_id = p_vendor_master_id)
  order by po.created_at desc
  limit least(coalesce(p_limit, 100), 200);
end;
$$;

comment on function app.list_purchase_orders is 'PRC-260: tenant-scoped PO queue, optionally filtered by status and/or vendor. With no status filter, superseded (historical, amended-away) versions are excluded by default, mirroring app.list_rfqs/app.list_vendor_comparisons. Server-side clamped to <=200 rows.';

create function app.list_purchase_order_lines(p_purchase_order_id uuid, p_actor_auth_user_id uuid)
returns setof app.purchase_order_lines
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
begin
  select po.tenant_id into v_tenant_id from app.purchase_orders po where po.id = p_purchase_order_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.purchase_order_lines where purchase_order_id = p_purchase_order_id order by line_no;
end;
$$;

comment on function app.list_purchase_order_lines is 'PRC-260: no cost data on lines (quantity/UOM only) -- plain, PRC:View alone. Not-found branch folds tenant membership in from the start (C-05).';

create function app.get_purchase_order_history(p_purchase_order_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, purchase_order_id uuid, from_status text, to_status text,
  reason text, cost_masked boolean, actor_auth_user_id uuid, actor_label text, occurred_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tenant_id uuid;
  v_cost_allowed boolean;
begin
  select po.tenant_id into v_tenant_id from app.purchase_orders po where po.id = p_purchase_order_id;
  if v_tenant_id is null or not app.has_active_tenant_membership(v_tenant_id, p_actor_auth_user_id) then
    raise exception 'purchase_order_not_found: %', p_purchase_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_cost_allowed := app.has_prc_view_cost(v_tenant_id, p_actor_auth_user_id);

  return query
  select e.id, e.tenant_id, e.purchase_order_id, e.from_status, e.to_status,
    case when v_cost_allowed then e.reason else null end,
    not v_cost_allowed,
    e.actor_auth_user_id, e.actor_label, e.occurred_at
  from app.purchase_order_events e
  where e.purchase_order_id = p_purchase_order_id
  order by e.occurred_at;
end;
$$;

comment on function app.get_purchase_order_history is 'PRC-260: the full lifecycle timeline (PO-root transitions only -- fulfillment status changes are not root transitions, see app.record_purchase_order_fulfillment_status). reason masked behind PRC:View cost, mirroring the hardened app.get_vendor_comparison_history. Not-found branch folds tenant membership in from the start (C-05).';

-- ===========================================================================
-- 14. Directory views -- defense in depth for the grant surface itself (no TypeScript
--    or db-test caller today, mirrors the hardened vendor_comparison_*_directory
--    precedent exactly, applied here from the start rather than needing a later fix).
-- ===========================================================================

create view app.purchase_orders_directory as
select
  po.id, po.tenant_id, po.org_unit_id, po.po_number, po.version, po.revised_from_id,
  po.comparison_id, po.selected_offer_id, po.rfq_id, po.sourcing_request_id, po.vendor_master_id,
  case when app.has_prc_view_cost(po.tenant_id) then po.currency else null end as currency,
  case when app.has_prc_view_cost(po.tenant_id) then po.subtotal_amount else null end as subtotal_amount,
  case when app.has_prc_view_cost(po.tenant_id) then po.tax_code else null end as tax_code,
  case when app.has_prc_view_cost(po.tenant_id) then po.tax_amount else null end as tax_amount,
  case when app.has_prc_view_cost(po.tenant_id) then po.total_amount else null end as total_amount,
  case when app.has_prc_view_cost(po.tenant_id) then po.payment_term_days else null end as payment_term_days,
  not app.has_prc_view_cost(po.tenant_id) as cost_masked,
  po.expected_delivery_date, po.service_period_start, po.service_period_end,
  case when app.has_prc_view_cost(po.tenant_id) then po.commercial_terms else null end as commercial_terms,
  po.notes, po.status, po.approval_status, po.approval_request_id,
  po.fulfillment_status, po.fulfillment_reference, po.fulfillment_updated_at, po.fulfillment_updated_by,
  po.submitted_at, po.submitted_by, po.issued_at, po.issued_by,
  po.acknowledged_at, po.acknowledged_by, po.acknowledgement_note,
  po.cancelled_at, po.cancel_reason,
  po.idempotency_key, po.record_version, po.created_by, po.created_at, po.updated_at
from app.purchase_orders po
where (app.has_active_tenant_membership(po.tenant_id) and not app.actor_holds_customer_user_layer(po.tenant_id)) or app.is_supreme_admin();

comment on view app.purchase_orders_directory is 'PRC-260: field-masked projection of app.purchase_orders, applied from day one (batch 257-259 review C-11 lesson) -- every cost-bearing column nulled (cost_masked=true) for a caller lacking PRC:View cost.';

create view app.purchase_order_lines_directory as
select l.*
from app.purchase_order_lines l
where (app.has_active_tenant_membership(l.tenant_id) and not app.actor_holds_customer_user_layer(l.tenant_id)) or app.is_supreme_admin();

comment on view app.purchase_order_lines_directory is 'PRC-260: plain -- app.purchase_order_lines carries no cost-bearing column.';

create view app.purchase_order_events_directory as
select
  e.id, e.tenant_id, e.purchase_order_id, e.from_status, e.to_status,
  case when app.has_prc_view_cost(e.tenant_id) then e.reason else null end as reason,
  not app.has_prc_view_cost(e.tenant_id) as cost_masked,
  e.actor_auth_user_id, e.actor_label, e.occurred_at
from app.purchase_order_events e
where (app.has_active_tenant_membership(e.tenant_id) and not app.actor_holds_customer_user_layer(e.tenant_id)) or app.is_supreme_admin();

comment on view app.purchase_order_events_directory is 'PRC-260: field-masked projection of app.purchase_order_events -- reason nulled (cost_masked=true) for a caller lacking PRC:View cost, mirroring the hardened app.vendor_comparison_events_directory.';

-- ===========================================================================
-- 15. RLS + grants.
-- ===========================================================================

alter table app.purchase_orders enable row level security;
alter table app.purchase_order_lines enable row level security;
alter table app.purchase_order_events enable row level security;

create policy purchase_orders_select_scoped on app.purchase_orders
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy purchase_order_lines_select_scoped on app.purchase_order_lines
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy purchase_order_events_select_scoped on app.purchase_order_events
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since PLT-118.
revoke execute on all functions in schema app from public;

-- C-11 applied from the start: column-restricted grant, cost fields excluded from day
-- one (currency/subtotal_amount/tax_code/tax_amount/total_amount/payment_term_days/
-- commercial_terms) -- never a blanket grant later hardened.
grant select (
  id, tenant_id, org_unit_id, po_number, version, revised_from_id,
  comparison_id, selected_offer_id, rfq_id, sourcing_request_id, vendor_master_id,
  expected_delivery_date, service_period_start, service_period_end, notes,
  status, approval_status, approval_request_id,
  fulfillment_status, fulfillment_reference, fulfillment_updated_at, fulfillment_updated_by,
  submitted_at, submitted_by, issued_at, issued_by,
  acknowledged_at, acknowledged_by, acknowledgement_note,
  cancelled_at, cancel_reason,
  idempotency_key, record_version, created_by, created_at, updated_at
) on app.purchase_orders to authenticated;
grant select on app.purchase_orders to service_role;
grant insert, update, delete on app.purchase_orders to service_role;

grant select (id, tenant_id, purchase_order_id, line_no, source_requirement_line_id, description, quantity, uom, notes, created_at) on app.purchase_order_lines to authenticated;
grant select on app.purchase_order_lines to service_role;
grant insert, update, delete on app.purchase_order_lines to service_role;

grant select (id, tenant_id, purchase_order_id, from_status, to_status, actor_auth_user_id, actor_label, occurred_at) on app.purchase_order_events to authenticated;
grant select on app.purchase_order_events to service_role;
grant insert, update, delete on app.purchase_order_events to service_role;

grant select on app.purchase_orders_directory to authenticated, service_role;
grant select on app.purchase_order_lines_directory to authenticated, service_role;
grant select on app.purchase_order_events_directory to authenticated, service_role;

grant execute on function app.next_purchase_order_number(uuid) to service_role;

grant execute on function app.draft_purchase_order_from_selection(uuid, uuid, text, uuid, text, text, integer, date, date, date, text, text) to authenticated, service_role;
grant execute on function app.submit_purchase_order_for_approval(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.issue_purchase_order(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.acknowledge_purchase_order(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_purchase_order_fulfillment_status(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.amend_purchase_order(uuid, integer, text, text, uuid, text, integer, date, date, date, text, text) to authenticated, service_role;
grant execute on function app.cancel_purchase_order(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_purchase_order_approval_step(uuid, text, uuid, text, timestamptz, text) to authenticated, service_role;

grant execute on function app.get_purchase_order(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_purchase_orders(uuid, uuid, text, uuid, integer) to authenticated, service_role;
grant execute on function app.list_purchase_order_lines(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_purchase_order_history(uuid, uuid) to authenticated, service_role;
