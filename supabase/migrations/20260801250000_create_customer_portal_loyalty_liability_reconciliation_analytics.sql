-- Phase 8 capability CPL-323 (CG-S13-CPL-025, Prompt 323, "Liability
-- Reconciliation Analytics") -- the EIGHTH Loyalty-domain capability in
-- this repository (ADR-0024 Part D), and the fourth and final prompt of
-- Batch 5 (CPL-320..323). Read in full before writing this file: ADR-0024
-- Part D; supabase/migrations/20260729230000_create_finance_reconciliation.
-- sql (FIN-209, the execute/resolve-then-certify shape this migration
-- mirrors); supabase/migrations/20260729110000_create_finance_invoice.sql's
-- app.prepare_finance_invoice_from_readiness (the HRT-282-family domain-
-- owned-handoff shape, read as precedent, NOT built here -- see the scope
-- boundary below); docs/build-log/phase-08/CPL-316.md through CPL-322.md
-- and their own migrations (20260801180000 through 20260801240000);
-- docs/build-log/phase-08/00_EXECUTION_INDEX.md section 11 (the "Loyalty
-- ledger exactness"/"Liability reconciliation" evidence-unit citations this
-- migration formally, runnably closes); docs/runtime/KNOWN_ISSUES.md
-- ISS-2026-129 item 1 (CPL-319's own explicit disclosure that full
-- liability reconciliation is this checkpoint's own future scope).
--
-- SCOPE BOUNDARY, disclosed up front (per this migration's own business
-- rule 24: "Finance owns official GL/journal posting; Loyalty provides
-- source-linked liability evidence/handoff only unless Finance contract
-- explicitly posts"): this migration does NOT build a Finance-side
-- handoff-batch table, an idempotent generator, or a Finance acknowledgement
-- RPC (the HRT-282-family shape named in ADR-0024 Part D and read above as
-- precedent). No Finance-side liability-handoff contract exists anywhere in
-- this repository for Loyalty to hand off TO yet (grep-confirmed: zero
-- `app.finance_*` table or column anywhere names a Loyalty-liability
-- concept) -- fabricating one here would be inventing a Finance-side
-- contract Finance itself never asked for, the opposite of "domain stays
-- source of truth, Finance handoff is a later, separate step" discipline.
-- This checkpoint instead builds the reconciliation-run/exception/certify
-- evidence layer ENTIRELY WITHIN Loyalty's own already-real tables
-- (app.loyalty_point_ledger_entries/app.loyalty_point_balances/app.
-- loyalty_benefit_entitlements/app.loyalty_benefit_entitlement_events/app.
-- loyalty_rewards/app.loyalty_redemptions) -- a real, complete, certifiable
-- liability-evidence primitive a FUTURE Finance-handoff checkpoint can read
-- from, exactly the same "real primitive shipped now, the next hop wired
-- later" shape CPL-316 (`ISS-2026-126`) through CPL-322 (`ISS-2026-133`)
-- have each already, repeatedly disclosed for their own next-hop gaps.
--
-- ===========================================================================
-- Design decisions (disclosed, not re-derived)
-- ===========================================================================
--
-- 1. **THE point-to-currency design question this task's own brief requires
--    resolving and disclosing (not silently papering over): there is NO
--    point-to-currency conversion rate configured anywhere in this
--    repository's real Loyalty schema (grep-confirmed again at this
--    checkpoint: no "value per point" column exists on app.loyalty_programs
--    or anywhere else). This migration reports points liability as a RAW
--    POINTS total (`points_liability_total numeric`, dimensionless -- a
--    units-based line), NEVER force-summed into any of the currency-
--    denominated lines.** Fabricating a conversion rate would produce a
--    liability NUMBER that LOOKS authoritative but is backed by no real,
--    configured rate anywhere in this tenant's own data -- exactly the
--    "fabricated citation"-class defect this repository's own review
--    discipline treats seriously. `app.loyalty_rewards.internal_cost`
--    (CPL-320) has NO currency column of its own either -- grep-confirmed
--    at this checkpoint, and CPL-321's own design decision 4 already made
--    the identical call once, explicitly, for a discount_voucher
--    entitlement's own minted `value_amount`/`currency`: "currency = the
--    tenant's own resolved default_currency". This migration EXTENDS that
--    SAME already-disclosed assumption (never invents a new one) to value
--    `internal_cost` for the reward-fulfillment-exposure line below (design
--    decision 5) -- disclosed explicitly, not assumed silently.
-- 2. **Mirrors FIN-209's exact three-function execute/resolve-then-certify
--    shape (a run computing exceptions -> a human resolves each exception
--    with a reason -> a final certify BLOCKED while any exception remains
--    open) as this migration's OWN new, Loyalty-owned functions and tables
--    -- never calling FIN-209's own app.execute_finance_reconciliation_run/
--    app.resolve_finance_reconciliation_exception/app.certify_finance_
--    reconciliation_run directly.** FIN-209 operates on Finance's own GL/
--    subledger-vs-open-item tables, a different domain with no natural
--    Loyalty-liability row to reconcile against there -- grep-confirmed
--    zero reference anywhere in this file to any `app.finance_*` table.
--    Unlike FIN-209, this migration does NOT introduce a separate
--    `app.check_loyalty_liability_reconciliation_authority(...)` wrapper
--    function -- every CPL-316..322 function in this domain already
--    inlines `app.evaluate_permission(...)` directly rather than routing
--    through a shared helper; this migration continues that ALREADY-
--    established Loyalty convention rather than blindly re-importing
--    FIN-209's own helper-function shape, a deliberate consistency choice
--    with this domain's own 7 prior capabilities, disclosed rather than
--    silent.
-- 3. **Every liability total is recomputed LIVE from the raw ledger/event
--    tables on every execute call -- never trusted from a cached, mutable
--    snapshot column without independent re-derivation** (this task's own
--    mandatory business rule, applied to ALL FIVE liability lines, not
--    just the first four -- see the Tier C review fix in design decision 5
--    below, which closes the one line that originally departed from this
--    rule). Points liability sums live over app.loyalty_point_ledger_
--    entries.amount per account (never app.loyalty_point_balances.
--    available directly); cashback/discount/voucher liability sums app.
--    loyalty_benefit_entitlements.value_amount only for entitlements whose
--    CURRENT status is independently RE-DERIVED from the append-only app.
--    loyalty_benefit_entitlement_events log (never trusted from app.
--    loyalty_benefit_entitlements.status directly -- see design decision
--    6); reward-fulfillment liability sums app.loyalty_rewards.
--    internal_cost only for physical_item/service_credit redemptions whose
--    CURRENT status is likewise independently RE-DERIVED from the
--    append-only app.loyalty_redemption_events log (never trusted from
--    app.loyalty_redemptions.status directly -- see design decision 5).
--    The cached columns are read ONLY as the comparison target for the
--    exactness cross-check (design decisions 5/7), never as the liability
--    NUMBER itself.
-- 4. **p_as_of is recorded as this run's own point-in-time label (defaults
--    to clock_timestamp() at execute time) but does NOT bound which raw
--    ledger/event rows are included in this checkpoint's own computation --
--    every total is computed against the FULL CURRENT state of the source
--    tables at execution time, disclosed as a real, bounded scope decision,
--    not a silent simplification.** A true point-in-time historical
--    reconciliation (bounding inclusion by created_at <= as_of, mirroring
--    FIN-209's own as_of_date-bounded control/source totals) is not built
--    here: unlike FIN-209's own AR/AP open-item tables (which carry a real
--    business date FIN-209 bounds by), app.loyalty_point_balances/app.
--    loyalty_benefit_entitlements are BOTH current-state-only with no
--    historical-snapshot capability for any date other than "now" -- a
--    genuinely historical as_of would make the exactness cross-check
--    (design decision 7) structurally meaningless (the cached CURRENT
--    balance would legitimately differ from a historical as_of cutoff for
--    a reason that is NOT a defect: more activity posted since). Building
--    full point-in-time reconstruction from the append-only event logs
--    alone is real, additional scope beyond this single capability's own
--    budget -- disclosed as `ISS-2026-134` rather than silently narrowed.
-- 5. **Liability model covers points, cashback, discount, voucher (the
--    brief's own literal 4 example columns) PLUS a 5th, disclosed addition:
--    `reward_fulfillment_liability_total` -- the source prompt's own
--    section 20 literally names "points, cashback, vouchers AND REWARDS."**
--    A physical_item/service_credit redemption (CPL-321) consumes points
--    and reserves stock but never mints an app.loyalty_benefit_
--    entitlements row (only discount_voucher does, CPL-321 design decision
--    3) -- so a committed-but-not-yet-fulfilled physical_item/service_
--    credit redemption (app.loyalty_redemptions.status = 'fulfilling') is a
--    REAL liability with NO representation anywhere in the entitlements
--    total. Valued at the reward's own staff-only app.loyalty_rewards.
--    internal_cost (design decision 1's disclosed tenant-default-currency
--    assumption, extended here); a null internal_cost on an active
--    fulfilling redemption contributes 0 (a disclosed limitation, not a
--    3rd/4th exception type -- ISS-2026-134). **Tier C review fix (Batch 5
--    close): current status is now independently RE-DERIVED from the
--    append-only app.loyalty_redemption_events log (latest event_type ->
--    status), exactly mirroring design decision 7's own entitlement-status
--    derivation, never trusted from app.loyalty_redemptions.status
--    directly.** This checkpoint's own original draft read the cached
--    status column directly, reasoning that app.loyalty_redemptions "IS
--    this domain's own established mutable-current-state row... consistent
--    with how CPL-320/321 already treat that table" -- true of CPL-320/321
--    (which mutate and read that column as their own domain's operational
--    truth), but this reasoning does not extend to a LIABILITY
--    RECONCILIATION run, whose own design decision 3 above states, without
--    qualification, that EVERY total is "never trusted from a cached,
--    mutable snapshot column without independent re-derivation" -- the
--    exact same rule already correctly applied to points and to
--    cashback/discount/voucher. app.loyalty_redemption_events carries
--    enough information (one event per real transition: submitted ->
--    approved -> fulfilled/fulfillment_failed, or rejected/cancelled) to
--    deterministically re-derive current status the identical way, so
--    there was no genuine structural reason to treat this 5th line
--    differently -- fixed for consistency with this migration's own stated
--    mandatory rule, not merely a stylistic preference. A mismatch between
--    the re-derived status and the cached column produces a real
--    `redemption_liability_status_mismatch` exception (mirrors design
--    decision 7's own entitlement-mismatch shape exactly), and the
--    liability total itself uses the RE-DERIVED status, never the
--    (possibly-corrupted) cached one.
-- 6. **Cashback/discount/voucher liability totals are CURRENCY-SCOPED via a
--    required p_currency parameter (my own disclosed addition beyond the
--    brief's own literal 4-parameter execute signature) -- entitlements
--    whose OWN currency column does not equal p_currency are excluded from
--    THIS run entirely, never blended into one fake cross-currency total.**
--    A tenant with multi-currency entitlements needs one run PER currency
--    to get full coverage -- mirrors FIN-209's own per-scope ('ar'/'ap')
--    run precedent exactly (a tenant needing both scopes runs FIN-209's own
--    execute function twice too), the identical "dimension by unit type
--    rather than force-sum into one fake blended number" discipline design
--    decision 1 already applies to points, applied here to currency too.
--    points_liability_total is currency-independent (a raw unit count) and
--    always included regardless of p_currency.
-- 7. **Entitlement CURRENT STATUS is independently re-derived, purely from
--    app.loyalty_benefit_entitlement_events (the append-only log), via a
--    deterministic latest-event-type -> status mapping (issued -> issued,
--    redeemed -> redeemed, reversed -> reversed, expired -> expired, held
--    -> held, released -> issued) -- NEVER trusted from app.loyalty_
--    benefit_entitlements.status directly (design decision 3).** Only
--    `benefit_type`/`currency`/`value_amount` (immutable dimensions, never
--    altered post-issuance by any function in this domain -- grep-
--    confirmed again at this checkpoint against CPL-319's own migration)
--    are read from the entitlements row itself, never its own mutable
--    `status` column. A mismatch between the re-derived status and the
--    entitlements row's own actual `status` column produces a real
--    `entitlement_state_derivation_mismatch` exception -- and, per design
--    decision 3, the LIABILITY TOTAL itself is computed using the RE-
--    DERIVED (event-log) status, never the (possibly-corrupted) cached
--    column, so a corrupted status column cannot silently understate or
--    overstate a certified total.
-- 8. **The formal, runnable closure of 00_EXECUTION_INDEX.md section 11's
--    "Loyalty ledger exactness" evidence unit, for POINTS specifically**:
--    for every loyalty_account_id with any row in app.loyalty_point_ledger_
--    entries, this run asserts live SUM(amount) equals app.loyalty_point_
--    balances.available (the generated column) exactly, recording a real
--    `point_balance_derivation_mismatch` exception (never a silent
--    tolerance/rounding allowance -- points are exact integers/whole units
--    by this domain's own design, CPL-318 design decision 1) for any
--    account where it does not, including the case where no cached balance
--    row exists at all (treated as an implicit mismatch, `actualAvailable:
--    null` in the exception's own detail). This closes `ISS-2026-129`
--    item 1's own disclosed gap and formalizes what CPL-316 through 322
--    each cited informally as "structurally guaranteed" -- this checkpoint
--    is the first to actually PROVE it, runnably, tenant-wide, on demand.
-- 9. **The ledger-insert-before-mutation ordering discipline (CPL-318's own
--    self-found double-counting-race lesson) does NOT directly apply to
--    this checkpoint's own execute function -- disclosed explicitly, not
--    silently omitted, per this task's own instruction.** This is a pure
--    read/aggregate/record operation: it never mutates any OTHER domain's
--    ledger/balance/entitlement row (grep-confirmed zero INSERT/UPDATE/
--    DELETE anywhere in this file against any pre-existing Loyalty table).
--    The SAME underlying discipline this ordering lesson embodies -- "the
--    idempotency-establishing write happens before any dependent write" --
--    is still applied where it DOES matter here: the run row's own INSERT
--    (wrapped in a real `exception when unique_violation` handler,
--    establishing the idempotency claim) always happens BEFORE any
--    exception row is inserted, since exception rows reference the run's
--    own id as a foreign key and cannot exist without it.
-- 10. **Idempotency key defaults to `'liability-recon:' || as_of::date ||
--    ':' || currency` when the caller does not supply one** (mirrors
--    CPL-322's own `run_label`-defaulting-to-calendar-day precedent
--    exactly) -- calendar-day-and-currency-scoped idempotency for free,
--    while an explicit, distinct key still lets a deliberate same-day
--    rerun happen under its own key. `p_idempotency_key` is nullable/
--    optional, another disclosed addition beyond the brief's own literal
--    4-parameter execute signature (design decision 6 already added
--    p_currency; this adds one more optional parameter, not a required
--    one).
-- 11. **Authority mapping: execute + resolve = LYL:Edit (ordinary posting-
--    tier, mirrors every OTHER ordinary Loyalty action -- e.g. app.run_
--    loyalty_expiry_sweep, app.post_loyalty_point_ledger_entry); certify =
--    LYL:Configure (the elevated, governance-grade action this domain
--    already reserves for every OTHER irreversible-in-effect action --
--    app.publish_loyalty_program_rule_version, app.reverse_loyalty_
--    benefit_entitlement, app.decide_loyalty_fraud_review_case).** LYL has
--    NO distinct `Approve` action anywhere in this repository (confirmed
--    again, `20260716103445_create_roles_permissions.sql:71-72`, the
--    identical confirmation CPL-316/318 each already made) -- so
--    `LYL:Configure` is the natural, already-established Loyalty-domain
--    mirror of FIN-209's own distinct `FIN:Approve` certify gate, not a
--    weaker substitute. Running a reconciliation does NOT require the same
--    elevated bar as certifying it (this task's own explicit question) --
--    my own disclosed call, matching FIN-209's own precedent exactly
--    (FIN:Edit executes/resolves, a genuinely higher FIN:Approve certifies).
-- 12. **Double-defended NULL-bypass optimistic concurrency on both app.
--    resolve_loyalty_liability_reconciliation_exception and app.certify_
--    loyalty_liability_reconciliation_run** -- the exact CPL-321/322 shape:
--    `if p_expected_version is null or v_row.record_version <>
--    p_expected_version then raise stale_version` PLUS the identical
--    `record_version = p_expected_version` predicate repeated on the
--    UPDATE statement itself, applied from the start (not a later fix).
-- 13. **Resolving the LAST open exception on a run automatically
--    transitions that run's own status from `exceptions_pending` back to
--    `open` (ready to certify)** -- a disclosed nicety beyond FIN-209's own
--    literal shape (FIN-209's own status vocabulary is `completed`/
--    `certified` only, with no intermediate "has open exceptions" state to
--    auto-clear). Mirrors "reconciliation mismatches block closure until
--    owned or repaired" (this task's own business rule) as a real, live
--    state transition, not merely a computed read-time predicate.
-- 14. **app.certify_loyalty_liability_reconciliation_run carries NO
--    separate `p_reason` parameter, departing from FIN-209's own mandatory
--    certify-reason precedent** -- the brief's own literal 5-parameter
--    signature for this function omits it, and this migration follows that
--    literal signature exactly rather than adding one unasked-for. My own
--    disclosed call: the meaningful gate here is that every exception is
--    ALREADY individually reasoned (app.resolve_loyalty_liability_
--    reconciliation_exception's own mandatory `p_resolution_reason`), so
--    certification itself does not also need a redundant top-level reason
--    -- a future hardening could add one, mirroring FIN-209 exactly, if a
--    concrete governance need for it emerges.
-- 15. **app.get_loyalty_engagement_metrics is Step-13-scope BASIC analytics
--    only** (this task's own business rule: "Step 14 may add advanced
--    analytics; Step 13 must still deliver deterministic liability
--    evidence") -- one tenant-wide AGGREGATE row (active loyalty accounts,
--    points issued/redeemed in period, redemption count/rate, published
--    reward count, distinct rewards with a redemption), structurally
--    incapable of naming a specific customer or exposing internal_cost/
--    vendor_ref/margin (grep-provable: no such column, no per-customer
--    dimension, anywhere in this function's own `returns table` clause or
--    body). LYL:View-gated (staff only) -- a customer_user caller is
--    rejected outright with `insufficient_authority` (no staff RBAC role
--    assignment exists for a customer_user principal under this
--    repository's own current role-assignment discipline, ADR-0024 Part B/
--    `ISS-2026-040`), never merely returning an empty/zeroed row.
-- 16. **app.get_customer_portal_loyalty_summary COMPOSES (never duplicates)
--    the already-existing per-domain customer reads from CPL-317/318/319/
--    321/322 -- app.list_customer_portal_loyalty_tier_cards, app.list_
--    customer_portal_loyalty_point_balances, app.list_customer_portal_
--    loyalty_benefit_entitlements, app.list_customer_portal_loyalty_
--    redemptions, app.list_customer_portal_loyalty_account_hold_status --
--    into one consolidated row for the caller's OWN single loyalty
--    account, scoped down after an explicit ownership check.** Never re-
--    implements any of those functions' own scope/masking/anti-enumeration
--    logic; a SECURITY DEFINER function calling another SECURITY DEFINER
--    function in the same schema needs no additional grant (confirmed
--    again, the identical precedent CPL-319's own app.generate_random_
--    base32_voucher_code helper already established). active_
--    entitlements_summary is grouped by (benefit_type, currency) --
--    design decision 1/6's own "dimension, never force-sum across
--    currencies" discipline applied a third time, for full consistency.
-- 17. `clock_timestamp()`, never `now()`, for every timestamptz column
--    whose ordering matters (the CPL-315 self-found defect class, applied
--    proactively throughout, including both touch-row triggers and every
--    `resolved_at`/`certified_at`/`computed_at` assignment).
-- 18. Every actor-taking function calls `app.assert_actor_is_session_
--    identity` as its own literal FIRST statement; every staff mutate/
--    get-by-id RPC checks `LYL:*` authority BEFORE fetching its target row
--    (C-05, mirrors every prior Loyalty capability's own established
--    precedent).
-- 19. RLS: `authenticated` holds ZERO direct grant on either new table
--    (mirrors CPL-316..322 exactly -- a deliberate departure from FIN-209's
--    own more permissive `grant select ... to authenticated` plus an RLS
--    select-scoped policy, since ADR-0024 Part A governs THIS capability,
--    not FIN-209's own pre-ADR-0024 precedent) -- the RPCs below are the
--    only sanctioned access path. Per `ERR-2026-004`: this migration
--    carries its own explicit `revoke execute on all functions in schema
--    app from public` statement before its final grants.
-- 20. Cursor pagination `(tenant_id, updated_at desc, id desc)` on every
--    list RPC, never `OFFSET`.

-- ===========================================================================
-- 1. app.loyalty_liability_reconciliation_runs -- mirrors app.finance_
-- reconciliation_runs' own shape (FIN-209), Loyalty-owned.
-- ===========================================================================

create table app.loyalty_liability_reconciliation_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  as_of timestamptz not null,
  currency text not null,
  status text not null default 'open',
  points_liability_total numeric not null default 0,
  cashback_liability_total numeric not null default 0,
  discount_liability_total numeric not null default 0,
  voucher_liability_total numeric not null default 0,
  reward_fulfillment_liability_total numeric not null default 0,
  computed_at timestamptz not null default clock_timestamp(),
  config_version integer not null default 1,
  idempotency_key text not null,
  executed_by text,
  certified_by text,
  certified_at timestamptz,
  record_version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint llrr_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint llrr_status_check check (status in ('open', 'exceptions_pending', 'certified')),
  constraint llrr_points_total_check check (points_liability_total >= 0),
  constraint llrr_cashback_total_check check (cashback_liability_total >= 0),
  constraint llrr_discount_total_check check (discount_liability_total >= 0),
  constraint llrr_voucher_total_check check (voucher_liability_total >= 0),
  constraint llrr_reward_total_check check (reward_fulfillment_liability_total >= 0),
  constraint llrr_certified_shape_check check ((status = 'certified') = (certified_by is not null and certified_at is not null)),
  constraint llrr_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.loyalty_liability_reconciliation_runs is
  'CPL-323: one deterministic, reproducible Loyalty-liability reconciliation run, as of a recorded point in time (design decision 4 -- as_of is a label, computation always reads current source-table state). points_liability_total is a RAW POINTS total (design decision 1, no fabricated conversion rate); cashback/discount/voucher/reward_fulfillment totals are currency-scoped to this run''s own currency column (design decision 6). status=certified requires zero open exceptions on this run -- certification never silently forces equality.';

create index llrr_tenant_updated_id_idx on app.loyalty_liability_reconciliation_runs (tenant_id, updated_at desc, id desc);
create index llrr_tenant_currency_asof_idx on app.loyalty_liability_reconciliation_runs (tenant_id, currency, as_of desc);

create function app.touch_loyalty_liability_reconciliation_run_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_liability_reconciliation_runs_touch_row
  before update on app.loyalty_liability_reconciliation_runs
  for each row
  execute function app.touch_loyalty_liability_reconciliation_run_row();

-- ===========================================================================
-- 2. app.loyalty_liability_reconciliation_exceptions -- mirrors app.
-- finance_reconciliation_exceptions' own shape (FIN-209), Loyalty-owned.
-- ===========================================================================

create table app.loyalty_liability_reconciliation_exceptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  run_id uuid not null references app.loyalty_liability_reconciliation_runs (id),
  exception_type text not null,
  detail jsonb not null default '{}'::jsonb,
  status text not null default 'open',
  resolved_by text,
  resolution_reason text,
  resolved_at timestamptz,
  record_version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint llre_exception_type_check check (exception_type in ('point_balance_derivation_mismatch', 'entitlement_state_derivation_mismatch', 'redemption_liability_status_mismatch')),
  constraint llre_status_check check (status in ('open', 'resolved')),
  constraint llre_resolved_shape_check check ((status = 'resolved') = (resolved_by is not null and resolution_reason is not null and resolved_at is not null))
);

comment on table app.loyalty_liability_reconciliation_exceptions is
  'CPL-323: one exception per real derivation mismatch found by app.execute_loyalty_liability_reconciliation_run (design decisions 7/8, plus the Tier C review redemption-status re-derivation fix, Batch 5 close) -- expected/actual carried in `detail` jsonb (this checkpoint''s own disclosed choice over separate expected_value/actual_value columns, since the three exception types carry structurally different detail shapes -- a numeric points mismatch vs. a status-string entitlement/redemption mismatch). Resolution requires an explicit, non-empty reason -- never a silent dismissal.';

create index llre_run_status_idx on app.loyalty_liability_reconciliation_exceptions (run_id, status);
create index llre_tenant_updated_id_idx on app.loyalty_liability_reconciliation_exceptions (tenant_id, updated_at desc, id desc);

create function app.touch_loyalty_liability_reconciliation_exception_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_liability_reconciliation_exceptions_touch_row
  before update on app.loyalty_liability_reconciliation_exceptions
  for each row
  execute function app.touch_loyalty_liability_reconciliation_exception_row();

-- ===========================================================================
-- 3. app.execute_loyalty_liability_reconciliation_run -- staff/system,
-- LYL:Edit (design decision 11). Recomputes every total LIVE from the raw
-- ledger/event tables (design decisions 3/7/8); idempotent on (tenant_id,
-- idempotency_key) (design decision 10).
-- ===========================================================================

create function app.execute_loyalty_liability_reconciliation_run(
  p_tenant_id uuid,
  p_as_of timestamptz,
  p_currency text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_idempotency_key text default null,
  p_config_version integer default 1
)
returns app.loyalty_liability_reconciliation_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_as_of timestamptz := coalesce(p_as_of, clock_timestamp());
  v_idem text;
  v_existing app.loyalty_liability_reconciliation_runs;
  v_run app.loyalty_liability_reconciliation_runs;
  v_points_total numeric := 0;
  v_cashback_total numeric := 0;
  v_discount_total numeric := 0;
  v_voucher_total numeric := 0;
  v_reward_total numeric := 0;
  v_account record;
  v_cached_available numeric;
  v_entitlement record;
  v_derived_status text;
  v_redemption record;
  v_derived_redemption_status text;
  v_point_mismatches jsonb[] := '{}';
  v_entitlement_mismatches jsonb[] := '{}';
  v_redemption_mismatches jsonb[] := '{}';
  v_mismatch jsonb;
  v_exception_count integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a valid ISO currency code' , p_currency using errcode = 'check_violation';
  end if;

  v_idem := coalesce(nullif(trim(p_idempotency_key), ''), 'liability-recon:' || to_char(v_as_of, 'YYYY-MM-DD') || ':' || p_currency);

  -- Idempotent short-circuit AFTER the authority check (mandatory pattern).
  -- Never recomputes on a replay -- a run's own totals/exceptions are
  -- exactly what they were the moment they were first computed.
  select * into v_existing from app.loyalty_liability_reconciliation_runs where tenant_id = p_tenant_id and idempotency_key = v_idem;
  if found then
    return v_existing;
  end if;

  -- =========================================================================
  -- Points: live per-account recomputation from the raw ledger (design
  -- decision 3), cross-checked against the cached derived balance for the
  -- exactness evidence unit (design decisions 7/8). greatest(...,0) is a
  -- defensive clamp only -- the negative-balance guard on app.post_loyalty_
  -- point_ledger_entry already structurally prevents a negative live sum in
  -- a healthy system; it should never actually engage for a legitimate
  -- account.
  -- =========================================================================
  for v_account in
    select le.loyalty_account_id as acct_id, sum(le.amount) as live_available
    from app.loyalty_point_ledger_entries le
    where le.tenant_id = p_tenant_id
    group by le.loyalty_account_id
  loop
    v_points_total := v_points_total + greatest(v_account.live_available, 0);

    select pb.available into v_cached_available
      from app.loyalty_point_balances pb
      where pb.tenant_id = p_tenant_id and pb.loyalty_account_id = v_account.acct_id;

    if not found then
      v_point_mismatches := v_point_mismatches || jsonb_build_object(
        'loyaltyAccountId', v_account.acct_id, 'expectedAvailable', v_account.live_available, 'actualAvailable', null, 'note', 'no cached app.loyalty_point_balances row found for an account with ledger activity'
      );
    elsif v_cached_available is distinct from v_account.live_available then
      v_point_mismatches := v_point_mismatches || jsonb_build_object(
        'loyaltyAccountId', v_account.acct_id, 'expectedAvailable', v_account.live_available, 'actualAvailable', v_cached_available
      );
    end if;
  end loop;

  -- =========================================================================
  -- Cashback/discount/voucher: current status independently re-derived
  -- purely from the append-only event log (design decision 7) -- the
  -- entitlements row's own `status` column is read ONLY as the exactness
  -- comparison target, never trusted for the liability total itself.
  -- =========================================================================
  for v_entitlement in
    select
      e.id as ent_id, e.benefit_type, e.currency, e.value_amount, e.status as cached_status,
      (
        select ev.event_type from app.loyalty_benefit_entitlement_events ev
        where ev.entitlement_id = e.id
        order by ev.created_at desc, ev.id desc
        limit 1
      ) as latest_event_type
    from app.loyalty_benefit_entitlements e
    where e.tenant_id = p_tenant_id
  loop
    v_derived_status := case v_entitlement.latest_event_type
      when 'issued' then 'issued'
      when 'redeemed' then 'redeemed'
      when 'reversed' then 'reversed'
      when 'expired' then 'expired'
      when 'held' then 'held'
      when 'released' then 'issued'
      else null
    end;

    if v_derived_status is distinct from v_entitlement.cached_status then
      v_entitlement_mismatches := v_entitlement_mismatches || jsonb_build_object(
        'entitlementId', v_entitlement.ent_id, 'expectedStatus', v_derived_status, 'actualStatus', v_entitlement.cached_status, 'latestEventType', v_entitlement.latest_event_type
      );
    end if;

    if v_derived_status in ('issued', 'held') and v_entitlement.currency = p_currency then
      if v_entitlement.benefit_type = 'cashback' then
        v_cashback_total := v_cashback_total + v_entitlement.value_amount;
      elsif v_entitlement.benefit_type = 'discount' then
        v_discount_total := v_discount_total + v_entitlement.value_amount;
      elsif v_entitlement.benefit_type = 'voucher' then
        v_voucher_total := v_voucher_total + v_entitlement.value_amount;
      end if;
    end if;
  end loop;

  -- =========================================================================
  -- Reward fulfillment exposure (design decision 5): physical_item/
  -- service_credit redemptions committed but not yet delivered, valued at
  -- the reward's own staff-only internal_cost (tenant-default-currency
  -- assumption, design decision 1). A null internal_cost contributes 0
  -- (disclosed limitation, ISS-2026-134). Tier C review fix (Batch 5
  -- close): current status is independently RE-DERIVED from the append-
  -- only app.loyalty_redemption_events log (latest event_type -> status),
  -- mirroring design decision 7's own entitlement-status derivation
  -- exactly -- the ORIGINAL draft trusted app.loyalty_redemptions.status
  -- directly with no re-derivation and no drift-detection exception,
  -- inconsistent with design decision 3's own literal "every liability
  -- total... never trusted from a cached, mutable snapshot column without
  -- independent re-derivation" rule, which this fix now honors for this
  -- 5th line too. A mismatch produces a real
  -- redemption_liability_status_mismatch exception, and the LIABILITY
  -- TOTAL itself is computed from the RE-DERIVED status, never the
  -- (possibly-corrupted) cached column -- so a direct, RPC-bypassing
  -- corruption of app.loyalty_redemptions.status can no longer silently
  -- understate this line with zero detection.
  -- =========================================================================
  for v_redemption in
    select
      rd.id as rdm_id, rd.status as cached_status, coalesce(r.internal_cost, 0) as internal_cost,
      (
        select ev.event_type from app.loyalty_redemption_events ev
        where ev.redemption_id = rd.id
        order by ev.created_at desc, ev.id desc
        limit 1
      ) as latest_event_type
    from app.loyalty_redemptions rd
    join app.loyalty_rewards r on r.id = rd.reward_id
    where rd.tenant_id = p_tenant_id and rd.reward_type in ('physical_item', 'service_credit')
  loop
    v_derived_redemption_status := case v_redemption.latest_event_type
      when 'submitted' then 'pending_approval'
      when 'approved' then 'fulfilling'
      when 'rejected' then 'rejected'
      when 'cancelled' then 'cancelled'
      when 'fulfilled' then 'fulfilled'
      when 'fulfillment_failed' then 'failed'
      else null
    end;

    if v_derived_redemption_status is distinct from v_redemption.cached_status then
      v_redemption_mismatches := v_redemption_mismatches || jsonb_build_object(
        'redemptionId', v_redemption.rdm_id, 'expectedStatus', v_derived_redemption_status, 'actualStatus', v_redemption.cached_status, 'latestEventType', v_redemption.latest_event_type
      );
    end if;

    if v_derived_redemption_status = 'fulfilling' then
      v_reward_total := v_reward_total + v_redemption.internal_cost;
    end if;
  end loop;

  v_exception_count := coalesce(array_length(v_point_mismatches, 1), 0) + coalesce(array_length(v_entitlement_mismatches, 1), 0) + coalesce(array_length(v_redemption_mismatches, 1), 0);

  -- The run row's own INSERT establishes the idempotency claim FIRST -- a
  -- genuine concurrent duplicate-idempotency-key race is caught by the real
  -- exception handler below, mirroring every other posting-shaped RPC in
  -- this domain (design decision 9).
  begin
    insert into app.loyalty_liability_reconciliation_runs (
      tenant_id, as_of, currency, status,
      points_liability_total, cashback_liability_total, discount_liability_total, voucher_liability_total, reward_fulfillment_liability_total,
      config_version, idempotency_key, executed_by
    ) values (
      p_tenant_id, v_as_of, p_currency, case when v_exception_count > 0 then 'exceptions_pending' else 'open' end,
      v_points_total, v_cashback_total, v_discount_total, v_voucher_total, v_reward_total,
      coalesce(p_config_version, 1), v_idem, p_actor_label
    )
    returning * into v_run;
  exception
    when unique_violation then
      select * into v_run from app.loyalty_liability_reconciliation_runs where tenant_id = p_tenant_id and idempotency_key = v_idem;
      if not found then
        raise;
      end if;
      return v_run;
  end;

  foreach v_mismatch in array v_point_mismatches loop
    insert into app.loyalty_liability_reconciliation_exceptions (tenant_id, run_id, exception_type, detail)
    values (p_tenant_id, v_run.id, 'point_balance_derivation_mismatch', v_mismatch);
  end loop;

  foreach v_mismatch in array v_entitlement_mismatches loop
    insert into app.loyalty_liability_reconciliation_exceptions (tenant_id, run_id, exception_type, detail)
    values (p_tenant_id, v_run.id, 'entitlement_state_derivation_mismatch', v_mismatch);
  end loop;

  foreach v_mismatch in array v_redemption_mismatches loop
    insert into app.loyalty_liability_reconciliation_exceptions (tenant_id, run_id, exception_type, detail)
    values (p_tenant_id, v_run.id, 'redemption_liability_status_mismatch', v_mismatch);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_loyalty_liability_reconciliation_run',
    'app.loyalty_liability_reconciliation_runs', v_run.id, 'success', null, null,
    jsonb_build_object('currency', p_currency, 'exception_count', v_exception_count, 'status', v_run.status)
  );

  return v_run;
end;
$$;

comment on function app.execute_loyalty_liability_reconciliation_run is
  'CPL-323: recomputes every liability total LIVE from the raw ledger/event tables (design decision 3), never from a cached snapshot column trusted without re-derivation -- including reward-fulfillment liability, re-derived from app.loyalty_redemption_events (design decision 5, Tier C review fix, Batch 5 close). Idempotent on (tenant_id, idempotency_key) -- a retry returns the identical row, never recomputes. No row-level lock is taken against any source-domain table during recomputation (mirrors FIN-209''s own unlocked, snapshot-consistent read within one transaction) -- a run reflects a normal MVCC-consistent snapshot, not a hard concurrency barrier against concurrent ledger posting.';

-- ===========================================================================
-- 4. app.resolve_loyalty_liability_reconciliation_exception -- staff,
-- LYL:Edit. Mandatory non-empty reason, double-defended NULL-bypass
-- optimistic concurrency (design decision 12).
-- ===========================================================================

create function app.resolve_loyalty_liability_reconciliation_exception(
  p_tenant_id uuid,
  p_exception_id uuid,
  p_expected_version integer,
  p_resolution_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_liability_reconciliation_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_exception app.loyalty_liability_reconciliation_exceptions;
  v_open_remaining integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Tenant-scoped fetch AFTER authority check (C-05) -- a cross-tenant id
  -- guess and a genuinely nonexistent id both resolve to the identical
  -- not-found error below.
  select * into v_exception from app.loyalty_liability_reconciliation_exceptions where id = p_exception_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_liability_reconciliation_exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;

  -- Double-defended NULL-bypass (design decision 12): explicit up-front
  -- rejection PLUS the identical predicate repeated on the UPDATE itself.
  if p_expected_version is null or v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_resolution_reason is null or length(trim(p_resolution_reason)) = 0 then
    raise exception 'reason_required: a non-empty resolution reason is required' using errcode = 'check_violation';
  end if;

  if v_exception.status <> 'open' then
    raise exception 'invalid_transition: exception % is % not open', p_exception_id, v_exception.status using errcode = 'check_violation';
  end if;

  update app.loyalty_liability_reconciliation_exceptions
    set status = 'resolved', resolved_by = p_actor_label, resolution_reason = p_resolution_reason, resolved_at = clock_timestamp()
    where id = p_exception_id and tenant_id = p_tenant_id and record_version = p_expected_version
    returning * into v_exception;
  if not found then
    raise exception 'stale_version: exception % target row was concurrently modified (expected version %)', p_exception_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Design decision 13: resolving the LAST open exception on a run
  -- automatically transitions the run back to 'open' (ready to certify).
  select count(*) into v_open_remaining from app.loyalty_liability_reconciliation_exceptions where run_id = v_exception.run_id and status = 'open';
  if v_open_remaining = 0 then
    update app.loyalty_liability_reconciliation_runs
      set status = 'open'
      where id = v_exception.run_id and status = 'exceptions_pending';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_loyalty_liability_reconciliation_exception',
    'app.loyalty_liability_reconciliation_exceptions', v_exception.id, 'success', p_resolution_reason, null, to_jsonb(v_exception)
  );

  return v_exception;
end;
$$;

comment on function app.resolve_loyalty_liability_reconciliation_exception is
  'CPL-323: mandatory non-empty resolution_reason -- never a silent dismissal. Double-defended NULL-bypass optimistic concurrency (design decision 12). Auto-clears the parent run from exceptions_pending back to open once its last open exception is resolved (design decision 13).';

-- ===========================================================================
-- 5. app.certify_loyalty_liability_reconciliation_run -- staff,
-- LYL:Configure (governance-grade, design decision 11). BLOCKED while any
-- exception on this run has status='open' -- mirrors FIN-209's own
-- certify-blocked-while-exceptions-open semantics exactly.
-- ===========================================================================

create function app.certify_loyalty_liability_reconciliation_run(
  p_tenant_id uuid,
  p_run_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_liability_reconciliation_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_run app.loyalty_liability_reconciliation_runs;
  v_open_exceptions integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_run from app.loyalty_liability_reconciliation_runs where id = p_run_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_liability_reconciliation_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;

  -- Double-defended NULL-bypass (design decision 12).
  if p_expected_version is null or v_run.record_version <> p_expected_version then
    raise exception 'stale_version: run % expected version % but found %', p_run_id, p_expected_version, v_run.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_run.status = 'certified' then
    return v_run;
  end if;

  select count(*) into v_open_exceptions from app.loyalty_liability_reconciliation_exceptions where run_id = p_run_id and status = 'open';
  if v_open_exceptions > 0 then
    raise exception 'loyalty_liability_reconciliation_unresolved_exceptions: run % has % unresolved exception(s)', p_run_id, v_open_exceptions
      using errcode = 'check_violation';
  end if;

  update app.loyalty_liability_reconciliation_runs
    set status = 'certified', certified_by = p_actor_label, certified_at = clock_timestamp()
    where id = p_run_id and tenant_id = p_tenant_id and record_version = p_expected_version
    returning * into v_run;
  if not found then
    raise exception 'stale_version: run % target row was concurrently modified (expected version %)', p_run_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'certify_loyalty_liability_reconciliation_run',
    'app.loyalty_liability_reconciliation_runs', v_run.id, 'success', null, null, to_jsonb(v_run)
  );

  return v_run;
end;
$$;

comment on function app.certify_loyalty_liability_reconciliation_run is
  'CPL-323: BLOCKED (a real, tested exception, loyalty_liability_reconciliation_unresolved_exceptions) while any exception on this run has status=open -- mirrors FIN-209''s own certify-blocked-while-exceptions-open semantics exactly. Idempotent once certified (a repeat certify call on an already-certified run is a safe no-op, returning the same row).';

-- ===========================================================================
-- 6. Read RPCs -- staff, LYL:View, cursor-paginated.
-- ===========================================================================

create function app.get_loyalty_liability_reconciliation_run(p_tenant_id uuid, p_run_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_liability_reconciliation_runs
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_run app.loyalty_liability_reconciliation_runs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_run from app.loyalty_liability_reconciliation_runs where id = p_run_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_liability_reconciliation_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;

  return v_run;
end;
$$;

create function app.list_loyalty_liability_reconciliation_runs(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_currency text default null,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_liability_reconciliation_runs
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select r.* from app.loyalty_liability_reconciliation_runs r
  where r.tenant_id = p_tenant_id
    and (p_currency is null or r.currency = p_currency)
    and (p_status is null or r.status = p_status)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

create function app.list_loyalty_liability_reconciliation_exceptions(
  p_tenant_id uuid,
  p_run_id uuid,
  p_actor_auth_user_id uuid,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_liability_reconciliation_exceptions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_run app.loyalty_liability_reconciliation_runs;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_run from app.loyalty_liability_reconciliation_runs where id = p_run_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_liability_reconciliation_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select e.* from app.loyalty_liability_reconciliation_exceptions e
  where e.run_id = p_run_id and e.tenant_id = p_tenant_id
    and (p_status is null or e.status = p_status)
    and (p_cursor_id is null or (e.updated_at, e.id) < (p_cursor_updated_at, p_cursor_id))
  order by e.updated_at desc, e.id desc
  limit v_limit;
end;
$$;

-- ===========================================================================
-- 7. app.get_loyalty_engagement_metrics -- staff, LYL:View. Aggregate-only,
-- tenant-wide, Step-13-scope basic analytics only (design decision 15).
-- ===========================================================================

create function app.get_loyalty_engagement_metrics(
  p_tenant_id uuid,
  p_period_start timestamptz,
  p_period_end timestamptz,
  p_actor_auth_user_id uuid
)
returns table (
  period_start timestamptz,
  period_end timestamptz,
  active_loyalty_accounts_count integer,
  points_earned_total numeric,
  points_redeemed_total numeric,
  redemption_count integer,
  redemption_rate numeric,
  published_reward_count integer,
  rewards_with_redemption_count integer,
  computed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_active_accounts integer;
  v_earned numeric;
  v_redeemed numeric;
  v_redemption_count integer;
  v_published_rewards integer;
  v_rewards_with_redemption integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Staff-only, tenant-internal (business rule: "analytics cannot infer or
  -- expose other customers, margins or internal profitability") -- a
  -- customer_user caller is rejected outright here, never merely handed an
  -- empty/zeroed row.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_period_end := coalesce(p_period_end, clock_timestamp());
  v_period_start := p_period_start;
  if v_period_start is null or v_period_start >= v_period_end then
    raise exception 'invalid_period: period_start % must be before period_end %', v_period_start, v_period_end using errcode = 'check_violation';
  end if;

  select count(*) into v_active_accounts from app.loyalty_accounts where tenant_id = p_tenant_id and status = 'active';

  select coalesce(sum(le.amount), 0) into v_earned
    from app.loyalty_point_ledger_entries le
    where le.tenant_id = p_tenant_id and le.event_type = 'earn' and le.created_at >= v_period_start and le.created_at < v_period_end;

  select coalesce(sum(abs(le.amount)), 0) into v_redeemed
    from app.loyalty_point_ledger_entries le
    where le.tenant_id = p_tenant_id and le.event_type = 'redemption' and le.created_at >= v_period_start and le.created_at < v_period_end;

  select count(*) into v_redemption_count
    from app.loyalty_redemptions rd
    where rd.tenant_id = p_tenant_id and rd.created_at >= v_period_start and rd.created_at < v_period_end;

  select count(*) into v_published_rewards from app.loyalty_rewards r where r.tenant_id = p_tenant_id and r.status = 'published';

  select count(distinct rd.reward_id) into v_rewards_with_redemption
    from app.loyalty_redemptions rd
    where rd.tenant_id = p_tenant_id and rd.created_at >= v_period_start and rd.created_at < v_period_end;

  period_start := v_period_start;
  period_end := v_period_end;
  active_loyalty_accounts_count := v_active_accounts;
  points_earned_total := v_earned;
  points_redeemed_total := v_redeemed;
  redemption_count := v_redemption_count;
  redemption_rate := case when v_active_accounts > 0 then round(v_redemption_count::numeric / v_active_accounts, 4) else 0 end;
  published_reward_count := v_published_rewards;
  rewards_with_redemption_count := v_rewards_with_redemption;
  computed_at := clock_timestamp();
  return next;
end;
$$;

comment on function app.get_loyalty_engagement_metrics is
  'CPL-323: aggregate-only, tenant-wide Step-13 basic analytics (design decision 15) -- structurally incapable of naming a specific customer or exposing internal_cost/vendor_ref/margin (no such column or per-customer dimension anywhere in this function). redemption_rate is defined here as redemptions-per-active-account in the period -- one reasonable, disclosed definition, not a funnel-instrumented eligible-view-to-redemption rate (no such instrumentation exists in this domain). Step 14 may add advanced analytics; this remains the deterministic Step-13 floor.';

-- ===========================================================================
-- 8. app.get_customer_portal_loyalty_summary -- customer_user, scoped via
-- app.resolve_customer_account_scope. Composes (never duplicates) the
-- already-existing per-domain customer reads (design decision 16).
-- ===========================================================================

create function app.get_customer_portal_loyalty_summary(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  loyalty_account_id uuid,
  customer_account_id uuid,
  program_id uuid,
  program_name text,
  account_status text,
  enrolled_at timestamptz,
  tier_name text,
  tier_benefits jsonb,
  is_tier_benefits_suspended boolean,
  points_available numeric,
  active_entitlements_count integer,
  active_entitlements_summary jsonb,
  recent_redemptions jsonb,
  is_on_hold boolean,
  hold_notice text,
  generated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_account app.loyalty_accounts;
  v_program_name text;
  v_tier_name text;
  v_tier_benefits jsonb;
  v_tier_suspended boolean;
  v_points_available numeric;
  v_hold boolean;
  v_hold_notice text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    raise exception 'loyalty_account_not_found: % is not visible to this caller', p_loyalty_account_id using errcode = 'no_data_found';
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found or not (v_account.customer_account_id = any (v_scope)) then
    -- Anti-enumeration: a genuinely nonexistent id and a real-but-out-of-
    -- scope id resolve to the identical error, mirroring every other
    -- customer-facing get-by-id RPC in this domain.
    raise exception 'loyalty_account_not_found: % is not visible to this caller', p_loyalty_account_id using errcode = 'no_data_found';
  end if;

  select p.name into v_program_name from app.loyalty_programs p where p.id = v_account.program_id;

  select t.current_tier_name, t.benefits, t.is_benefits_suspended
    into v_tier_name, v_tier_benefits, v_tier_suspended
    from app.list_customer_portal_loyalty_tier_cards(p_tenant_id, p_actor_auth_user_id, v_account.customer_account_id, 200) t
    where t.loyalty_account_id = p_loyalty_account_id
    limit 1;

  select b.available into v_points_available
    from app.list_customer_portal_loyalty_point_balances(p_tenant_id, p_actor_auth_user_id, v_account.customer_account_id, null, null, 200) b
    where b.loyalty_account_id = p_loyalty_account_id
    limit 1;

  select h.is_on_hold, h.hold_notice into v_hold, v_hold_notice
    from app.list_customer_portal_loyalty_account_hold_status(p_tenant_id, p_actor_auth_user_id, v_account.customer_account_id, 200) h
    where h.loyalty_account_id = p_loyalty_account_id
    limit 1;

  loyalty_account_id := v_account.id;
  customer_account_id := v_account.customer_account_id;
  program_id := v_account.program_id;
  program_name := v_program_name;
  account_status := v_account.status;
  enrolled_at := v_account.enrolled_at;
  tier_name := v_tier_name;
  tier_benefits := coalesce(v_tier_benefits, '{}'::jsonb);
  is_tier_benefits_suspended := coalesce(v_tier_suspended, false);
  points_available := coalesce(v_points_available, 0);
  is_on_hold := coalesce(v_hold, false);
  hold_notice := v_hold_notice;
  generated_at := clock_timestamp();

  -- active_entitlements_summary is grouped by (benefit_type, currency) --
  -- never force-summed across currencies (design decision 6/16). Tier C
  -- review fix (Batch 5 close): this checkpoint's own original draft ran
  -- an independent raw query directly against app.loyalty_benefit_
  -- entitlements here, DUPLICATING (not composing) that table's own
  -- scope/masking logic -- directly contradicting design decision 16's own
  -- literal claim ("COMPOSES, never duplicates") and re-introducing
  -- exactly the "second, independently-evolving enforcement point" class
  -- ADR-0024 Part A explicitly warns against. Fixed by genuinely composing
  -- app.list_customer_portal_loyalty_benefit_entitlements (CPL-319) and
  -- filtering/aggregating over ITS OWN already-scoped, already-masked
  -- result set (that function has no p_loyalty_account_id parameter of its
  -- own, only p_customer_account_id, so the account-level filter is
  -- applied here, on its output) -- no live field leak existed either way
  -- (the raw query never selected a masked column), but this closes the
  -- documentation/architecture mismatch at its root rather than leaving it
  -- as a drift risk for a future change to the composed function''s own
  -- masking logic.
  select coalesce(sum(s.cnt), 0)::integer, coalesce(jsonb_agg(jsonb_build_object('benefitType', s.benefit_type, 'currency', s.currency, 'count', s.cnt, 'total', s.total_value) order by s.benefit_type, s.currency), '[]'::jsonb)
    into active_entitlements_count, active_entitlements_summary
    from (
      select be.benefit_type, be.currency, count(*) as cnt, sum(be.value_amount) as total_value
      from app.list_customer_portal_loyalty_benefit_entitlements(p_tenant_id, p_actor_auth_user_id, v_account.customer_account_id, null, null, null, 200) be
      where be.loyalty_account_id = p_loyalty_account_id and be.status in ('issued', 'held')
      group by be.benefit_type, be.currency
    ) s;

  select coalesce(jsonb_agg(jsonb_build_object(
      'redemptionId', r.redemption_id, 'rewardName', r.reward_name, 'rewardType', r.reward_type,
      'status', r.status, 'fulfillmentStatus', r.fulfillment_status, 'pointsConsumed', r.points_consumed,
      'decidedAt', r.decided_at, 'createdAt', r.created_at
    ) order by r.created_at desc), '[]'::jsonb)
    into recent_redemptions
    from (
      select * from app.list_customer_portal_loyalty_redemptions(p_tenant_id, p_actor_auth_user_id, p_loyalty_account_id, null, null, 10)
    ) r;

  return next;
end;
$$;

comment on function app.get_customer_portal_loyalty_summary is
  'CPL-323: composes (never duplicates) app.list_customer_portal_loyalty_tier_cards/..._point_balances/..._benefit_entitlements/..._account_hold_status/..._redemptions -- the already-existing, already-tested per-domain customer reads (design decision 16, Tier C review fix for the entitlements composition, Batch 5 close) -- into one consolidated row for the caller''s own single loyalty account. Anti-enumerating: a nonexistent id and a real-but-out-of-scope id raise the identical loyalty_account_not_found error.';

-- ===========================================================================
-- 9. RLS -- enable, grant service_role only (design decision 19, mirrors
-- CPL-316..322 exactly).
-- ===========================================================================

alter table app.loyalty_liability_reconciliation_runs enable row level security;
alter table app.loyalty_liability_reconciliation_exceptions enable row level security;

grant select, insert, update on app.loyalty_liability_reconciliation_runs to service_role;
grant select, insert, update on app.loyalty_liability_reconciliation_exceptions to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.touch_loyalty_liability_reconciliation_run_row() to service_role;
grant execute on function app.touch_loyalty_liability_reconciliation_exception_row() to service_role;
grant execute on function app.execute_loyalty_liability_reconciliation_run(uuid, timestamptz, text, uuid, text, text, integer) to authenticated, service_role;
grant execute on function app.resolve_loyalty_liability_reconciliation_exception(uuid, uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.certify_loyalty_liability_reconciliation_run(uuid, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_liability_reconciliation_run(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_liability_reconciliation_runs(uuid, uuid, text, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_loyalty_liability_reconciliation_exceptions(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.get_loyalty_engagement_metrics(uuid, timestamptz, timestamptz, uuid) to authenticated, service_role;
grant execute on function app.get_customer_portal_loyalty_summary(uuid, uuid, uuid) to authenticated, service_role;
