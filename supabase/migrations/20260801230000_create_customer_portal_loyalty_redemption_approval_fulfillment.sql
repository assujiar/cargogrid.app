-- Phase 8 capability CPL-321 (CG-S13-CPL-023, Prompt 321, "Redemption
-- Approval and Fulfillment") -- the SECOND prompt of Batch 5 (CPL-320..323),
-- and the SIXTH Loyalty-domain capability in this repository (ADR-0024 Part
-- D). Read docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-
-- pattern.md (Parts A/B/D) IN FULL; docs/build-log/phase-08/CPL-320.md and
-- its own migration (20260801220000) IN FULL, including app.reserve_
-- loyalty_reward_stock_unit's own function body and app.loyalty_reward_
-- stock_reservations; supabase/migrations/20260801200000 (Points Ledger,
-- app.consume_loyalty_points_fifo/app.post_loyalty_point_ledger_entry);
-- supabase/migrations/20260801210000 (Cashback Discount Voucher, app.issue_
-- loyalty_benefit_entitlement/app.hold_loyalty_benefit_entitlement); and
-- supabase/migrations/20260801190000's own app.hold_loyalty_account_tier_
-- benefits/app.get_loyalty_account_tier_state -- ALL read in full before
-- writing any of this file, per this task's own explicit instruction.
--
-- This migration READS app.loyalty_accounts/app.loyalty_account_tier_
-- movements/app.loyalty_tier_definitions/app.loyalty_account_tier_holds
-- (CPL-316/317), app.loyalty_point_balances/app.loyalty_point_ledger_entries
-- (CPL-318, via app.consume_loyalty_points_fifo/app.post_loyalty_point_
-- ledger_entry), app.loyalty_benefit_entitlements (CPL-319, via app.issue_
-- loyalty_benefit_entitlement), and app.loyalty_rewards/app.loyalty_reward_
-- stock_reservations (CPL-320, via app.reserve_loyalty_reward_stock_unit and
-- this migration's own new app.release_loyalty_reward_stock_reservation) --
-- it never bypasses any of those domains' own owning primitives with a
-- second, parallel mechanism, confirmed by grep before this file was
-- finalized. It ALSO widens ONE existing CPL-320 CHECK constraint via a
-- real, additive ALTER TABLE (design decision 8 below) -- CPL-320's own
-- migration file (20260801220000) is never edited in place.
--
-- ===========================================================================
-- Design decisions (disclosed, not re-derived)
-- ===========================================================================
--
-- 1. **points_cost = min_points_required (the reward's own eligibility
--    threshold doubles as the redemption cost).** CPL-320's own app.loyalty_
--    rewards has min_points_required (an ELIGIBILITY gate, AND-combined with
--    min_tier_id) but NO separate points_cost column -- a real, disclosed
--    gap this checkpoint's own orchestrating task instruction explicitly
--    flags as an unresolved design question. Two readings were considered:
--    (a) consume exactly min_points_required (the natural, simplest
--    reading -- a common real-world loyalty-catalogue pattern: "you need
--    500 points to see/qualify for this reward" and "redeeming it costs 500
--    points" are the SAME number in most programs, since a separate,
--    independently-configured "cost" would let a customer see a reward as
--    eligible yet be unable to actually afford it, or vice versa, a
--    confusing UX CPL-320's own catalogue never surfaces any hint of); (b)
--    a wholly separate, new points_cost column. This checkpoint selects (a)
--    -- it requires NO schema change to CPL-320's own table (additive-
--    migration discipline favors the smaller, sufficient change), matches
--    the eligibility projection the customer ALREADY saw on the catalogue
--    page before checking out (no surprise "spend was more than shown"),
--    and is exactly the reading CPL-320's own catalogue UI text already
--    implies ("Requires 500 points (you have 650)" -- the reward detail
--    page's own describeLoyaltyRewardEligibility copy). A null min_points_
--    required reward costs 0 points to redeem (a fully open/free reward,
--    e.g. gated on tier alone or on nothing).
-- 2. **reward_type -> benefit_type mapping: 'discount_voucher' -> CPL-319
--    'voucher' (mints a real, hash-only-stored, redeemable code), never
--    'discount'.** CPL-320's own design decision 2 left this forward
--    mapping disclosed-but-unenforced, explicitly deferring the choice to
--    this checkpoint ("'discount_voucher' -> CPL-319 'voucher' (or
--    'discount', CPL-321's own call depending on whether a code is
--    minted)"). This checkpoint mints a real code (app.issue_loyalty_
--    benefit_entitlement's own benefit_type='voucher' path, design decision
--    2 of CPL-319's migration) -- a customer redeeming a catalogue reward
--    receives a genuine, presentable voucher code, matching this reward
--    type's own literal name ("discount_voucher") more precisely than the
--    bare 'discount' benefit_type (which carries no code at all in CPL-319's
--    own schema). 'physical_item'/'service_credit' have NO CPL-319
--    benefit_type counterpart at all (CPL-320's own design decision 2,
--    confirmed, not re-derived) -- see design decision 3.
-- 3. **'physical_item'/'service_credit' fulfillment tracking is GENUINELY
--    NEW, first-of-its-kind scope in this repository -- never a claimed
--    reuse of anything.** No shipment/service-credit-application integration
--    exists anywhere in this repository for Loyalty to hook into (grep-
--    confirmed: zero reference to app.loyalty_redemptions/app.loyalty_
--    reward fulfillment anywhere in Operations/WMS/Finance). This checkpoint
--    therefore builds a real, disclosed `fulfillment_status` column directly
--    on its own new app.loyalty_redemptions row (`not_applicable`/
--    `pending`/`in_fulfillment`/`fulfilled`/`failed`), populated and
--    transitioned exclusively by this checkpoint's own new RPCs (app.mark_
--    loyalty_redemption_fulfilled/app.mark_loyalty_redemption_fulfillment_
--    failed) -- no external system is ever called, no shipment/service-
--    credit record is fabricated. `discount_voucher` redemptions are
--    fulfillment_status='not_applicable' ALWAYS -- the entitlement issuance
--    itself IS the fulfillment moment for that type (design decision 5), no
--    separate fulfillment step exists or is needed for it.
-- 4. **Discount-voucher entitlement value/currency: value_amount = the
--    reward's own internal_cost (staff-only, never customer-facing, CPL-
--    320 design decision 8); currency = the tenant's own resolved default_
--    currency (app.resolve_tenant_locale, PLT's real, already-existing
--    tenant currency-preference primitive) -- a genuinely NEW composition,
--    not a claimed reuse of anything.** CPL-320's own app.loyalty_rewards
--    has no dedicated customer-facing monetary "voucher face value" column,
--    and app.issue_loyalty_benefit_entitlement (CPL-319) requires a real,
--    positive value_amount and a real 3-letter currency for EVERY benefit_
--    type, voucher included -- a genuine, disclosed modeling gap this
--    checkpoint must resolve, not silently paper over. internal_cost is the
--    ONLY numeric, monetary-shaped field CPL-320's own reward row carries
--    (representing what the reward is worth internally, whichever reward_
--    type it is), so this checkpoint reuses it as the minted voucher's own
--    face value -- a discount_voucher reward with a null or non-positive
--    internal_cost is genuinely NOT configured for redemption and is
--    rejected with a real, distinct, customer-safe error (`reward_
--    redemption_unavailable`) rather than fabricating a value. Currency is
--    never hardcoded or invented -- app.resolve_tenant_locale (PLT,
--    20260717112000) is this repository's own real, already-shipped tenant-
--    currency-preference primitive, already falling back to a real platform
--    default ('IDR') when a tenant has never published its own locale
--    config, never null.
-- 5. **Approval rule (my own threshold/rule, disclosed): reward_type alone
--    decides ELIGIBILITY for the auto-approve branch (discount_voucher
--    only; physical_item/service_credit ALWAYS require a staff decision),
--    but auto-approval additionally, necessarily requires the SUBMITTING
--    actor to independently hold LYL:Edit authority -- THIS checkpoint's
--    own most consequential architectural resolution, worked out and
--    disclosed in full below, not silently assumed.**
--
--    This checkpoint's own mandatory instruction requires composing app.
--    reserve_loyalty_reward_stock_unit and app.consume_loyalty_points_fifo
--    "at the actual moment of redemption" -- both are REAL, already-shipped,
--    unmodifiable primitives, each independently gated on the ACTING
--    identity holding LYL:Edit (CPL-320/318's own literal "staff/system"
--    authority label). ADR-0024 Part B (docs/adr/ADR-0024-...) is this
--    repository's OWN ratified, binding rule: "canonical mutation RPC...
--    never widened to accept a customer_user caller"; its own rejected
--    Option 2 cites ISS-2026-040 (app.evaluate_permission is layer-blind)
--    as the exact reason NOT to add a customer_user branch to a staff-RBAC-
--    gated canonical mutation's OWN authority check. This checkpoint
--    therefore does NOT widen app.reserve_loyalty_reward_stock_unit/app.
--    consume_loyalty_points_fifo/app.issue_loyalty_benefit_entitlement's own
--    LYL:Edit gate to accept a customer_user caller.
--
--    A genuine `customer_user` identity structurally CANNOT itself satisfy
--    LYL:Edit -- confirmed directly, not assumed: `app.role_assignments`
--    (the table app.evaluate_permission's own role-grant lookup reads) has
--    exactly ONE `insert into app.role_assignments` call site in this
--    entire repository (`app.assign_role_to_user`,
--    20260716103445_create_roles_permissions.sql:504, a staff-only
--    administrative RPC of its own); the customer-portal invite flow (app.
--    invite_customer_portal_user, CPL-300) never touches it -- a customer_
--    user-layer principal (app.principal_memberships) and an RBAC role_
--    assignment are two structurally separate, never-linked provisioning
--    paths in this repository's own current operational discipline (not a
--    hard schema-level impossibility -- nothing stops a future, deliberate
--    misconfiguration from granting both to the same auth_user_id -- but
--    that has never happened anywhere in this repository's own established
--    provisioning flows, confirmed by the single-INSERT-site grep above).
--
--    Also confirmed directly (not assumed): `auth.uid()` (the GUC-backed
--    session identity `app.assert_actor_is_session_identity` cross-checks)
--    is UNCHANGED across nested SECURITY DEFINER calls within the same
--    session/transaction -- live-tested in a disposable database (a nested
--    function call sees the IDENTICAL `auth.uid()` value its own caller
--    saw) -- so passing the SAME actor identity through to a nested
--    composed primitive is safe with respect to the identity crosscheck;
--    the REAL, load-bearing gate a genuine customer_user identity fails is
--    `app.evaluate_permission`'s own role-grant lookup, a pure data check
--    wholly unaffected by connection role or nesting.
--
--    No combination of these two real, unmodifiable, already-shipped
--    primitives can therefore be triggered end-to-end by a raw, un-role-
--    assigned customer_user session without EITHER (a) widening either
--    primitive's own RBAC gate (forbidden -- ADR-0024 Part B, ISS-2026-040),
--    or (b) provisioning a wholly new, tenant-scoped automated "system"
--    identity with its own real role_assignment (a genuinely new, cross-
--    cutting, per-tenant-provisioning capability -- who assigns it, in
--    which tenants, audited how -- well beyond this single prompt's own
--    bounded 5-15-file scope, and not requested by this task's own literal
--    instruction).
--
--    This checkpoint's own resolution: `app.submit_loyalty_redemption` is
--    dual-authority (customer Layer-4 scope OR staff LYL:Edit, mirroring
--    CPL-319's own app.redeem_loyalty_benefit_entitlement design decision 5
--    exactly) for WHO MAY SUBMIT a request. Every submission, regardless of
--    caller, ALWAYS creates the real, portal-owned intent/request record
--    (app.loyalty_redemptions, status='pending_approval') after full
--    server-side re-validation -- consistent with ADR-0024 Part B's own
--    "request/intent record... referencing the canonical [mutation] by ID"
--    shape (here, the SAME Loyalty domain's own internal ledger machinery,
--    not a genuinely different domain's canonical truth, since app.
--    reserve_loyalty_reward_stock_unit was explicitly built BY this same
--    Loyalty domain's own prior checkpoint FOR this checkpoint to compose,
--    CPL-320's own ISS-2026-131 item 2). `app.submit_loyalty_redemption`
--    then ATTEMPTS immediate composition (reserve stock, consume points,
--    and for discount_voucher, issue the entitlement) using the calling
--    actor's own identity, inside a savepoint-scoped attempt: if the actor
--    genuinely holds LYL:Edit (staff, or a future system caller), this
--    succeeds synchronously and, for discount_voucher, the redemption is
--    'fulfilled' before the RPC call even returns -- a REAL, literal "auto-
--    approve inline" outcome, exactly this task's own literal instruction,
--    for the caller class that can legitimately do so. If the actor lacks
--    LYL:Edit -- the realistic case for a genuine, unassisted customer_user
--    self-service submission, of ANY reward_type -- the composition
--    attempt raises `insufficient_authority` (from app.reserve_loyalty_
--    reward_stock_unit's own first authority check, before any write).
--
--    **Tier C review fix (Batch 5 close), corrected from this migration's
--    own original draft: `app.submit_loyalty_redemption` catches EVERY
--    exception the composition attempt can raise, not only
--    `insufficient_authority`.** The original draft filtered the catch by
--    `sqlerrm like 'insufficient_authority%'` and re-raised anything else
--    -- reasoned, at the time, to be safe because the only shipped caller
--    (customer-portal self-service) always fails on exactly that one
--    condition. Live adversarial review proved this false for the OTHER
--    caller class this same design decision explicitly, deliberately
--    supports: a staff/system actor who DOES hold LYL:Edit and whose
--    composition attempt fails for an entirely ordinary, non-authority
--    reason (the reward genuinely out of stock, the account genuinely
--    short on points, or a misconfigured discount_voucher reward's own
--    `reward_redemption_unavailable`) hit the re-raise branch, which
--    aborted the WHOLE `app.submit_loyalty_redemption` call -- rolling
--    back not only the composition's own partial work (correct) but the
--    redemption row's own INSERT and its 'submitted' event too (both
--    happened BEFORE this savepoint-scoped attempt, in the SAME
--    transaction) -- silently losing the request with zero audit trail,
--    directly contradicting the very invariant this paragraph states.
--    Every composition failure, whatever its cause, now leaves the row
--    exactly where it already is -- `pending_approval` -- so a human
--    resolves it via `app.decide_loyalty_redemption`, which independently
--    re-validates the identical business condition (stock, points, reward
--    configuration) at decision time rather than the request having been
--    destroyed outright. This changes nothing about the composition's own
--    atomicity (design decision 13 below still holds exactly as stated for
--    the reserve/consume/issue work itself) -- only the outer redemption-
--    row/event's own survival.
--
--    A real staff `app.decide_loyalty_redemption` call (LYL:Configure,
--    which ALSO explicitly, visibly re-checks LYL:Edit before delegating
--    -- mirrors CPL-318's own design decision 16 precedent exactly)
--    completes the identical composition later, for every reward_type
--    uniformly.
--
--    Consequence, disclosed as `ISS-2026-132`: a genuinely autonomous,
--    zero-staff-involvement instant self-service redemption does not exist
--    for ANY reward_type from a raw, unassisted customer_user session in
--    this checkpoint -- every such submission lands `pending_approval` and
--    requires one real, fast staff `decide_loyalty_redemption(approve)`
--    call to complete. This mirrors the already-established "on-demand/
--    staff-triggered only" precedent family (ISS-2026-126/127/128/129/130/
--    131) this entire Loyalty domain has consistently, honestly disclosed
--    at every prior checkpoint, extended here to this domain's own LAST
--    remaining synchronous-composition gap -- not a new class of gap this
--    checkpoint quietly introduces.
-- 6. **Fraud hold composed via a direct read of app.loyalty_account_tier_
--    holds, never app.get_loyalty_account_tier_state.** The latter is
--    itself LYL:View-gated (staff-only) -- calling it from a customer-
--    initiated composition would reintroduce the identical RBAC-composition
--    problem design decision 5 exists to resolve, for a mere READ this
--    time. This checkpoint instead reads the underlying table directly
--    (`coalesce(is_held, false)`), exactly mirroring how CPL-320's own
--    eligibility projection reads app.loyalty_account_tier_movements/app.
--    loyalty_tier_definitions directly rather than through a staff-gated
--    RPC. A held account's redemption attempt is blocked with a generic,
--    customer-safe message ("this account cannot redeem rewards at this
--    time... contact support") that NEVER reveals the real hold_reason --
--    mirrors CPL-317's own tier-benefit-suppression precedent and CPL-319's
--    own hold_notice precedent exactly (the fact of a hold may be
--    disclosed; the internal reason/investigation detail never is).
-- 7. **Self-approval is structurally impossible for app.decide_loyalty_
--    redemption, confirmed directly (not assumed), mirroring CPL-315's own
--    "checked, not re-derived" role-hierarchy methodology.** app.decide_
--    loyalty_redemption requires LYL:Configure. Design decision 5 above
--    already establishes, via a direct grep of every `insert into app.
--    role_assignments` call site in this repository (exactly one, a staff-
--    only administrative RPC the customer-portal invite flow never
--    touches), that a genuine customer_user identity holds no role_
--    assignment at all in this repository's own established operational
--    discipline -- so a customer_user who submitted their own redemption
--    request can never subsequently reach app.decide_loyalty_redemption's
--    own authority gate to approve/reject it themselves. This is an
--    operational-discipline guarantee (confirmed by this repository's own
--    consistent provisioning history), not an unconditional schema-level
--    CHECK constraint -- disclosed precisely, not overclaimed.
-- 8. **app.loyalty_reward_stock_reservations' own CHECK constraint is
--    WIDENED (never narrowed) via a real, additive ALTER TABLE in THIS
--    migration -- CPL-320's own applied migration file is never edited.**
--    Rejecting/cancelling/failing-fulfillment on a redemption that already
--    reserved a unit must be able to credit that unit back -- but CPL-320's
--    own ledger was deliberately, explicitly scoped as append-only-and-
--    additive-only (`quantity > 0`, "one row per RESERVED unit-quantity"),
--    since no redemption/cancellation concept existed yet to need a release
--    concept when CPL-320 shipped. Two release-mechanism shapes were
--    considered: (a) a wholly SEPARATE "releases" table -- rejected, since
--    CPL-320's own already-shipped stock_available computation (`total_
--    stock - coalesce(sum(quantity), 0)` over app.loyalty_reward_stock_
--    reservations alone) would never see a row in a second table, silently
--    under-reporting available stock forever after any release -- a real,
--    permanent correctness bug this checkpoint refuses to introduce; (b)
--    widen the SAME table's own CHECK constraint (`quantity > 0` ->
--    `quantity <> 0`) so a release posts a NEGATIVE-quantity row into the
--    SAME ledger. This checkpoint selects (b) -- CPL-320's own existing
--    `coalesce(sum(quantity), 0)` aggregate ALREADY nets negative rows out
--    correctly with ZERO change to either of CPL-320's own read RPCs' own
--    function bodies, eliminating the exact "two numbers that could drift"
--    defect class CPL-320's own design decision 7 was built to avoid in the
--    first place. This is a genuine, real, additive `ALTER TABLE ...
--    CHECK` widening (an already-valid positive quantity remains valid; a
--    previously-rejected zero quantity remains rejected; only a negative
--    quantity newly becomes acceptable) -- CPL-320's own db-test (which
--    only ever posts positive reservations) is entirely unaffected and
--    remains fully valid, re-confirmed by this checkpoint's own scratch-
--    database run of CPL-320's own db-test file alongside this one's.
--    app.release_loyalty_reward_stock_reservation (new, this checkpoint) is
--    the ONE new function that ever posts a negative-quantity row --
--    mirrors app.reserve_loyalty_reward_stock_unit's own shape (idempotent
--    on (tenant_id, idempotency_key), staff/system LYL:Edit) exactly,
--    minus the over-subscription check (a release can never oversubscribe).
-- 9. **Re-validation at the CURRENT checkpoint, business rule ("no reward
--    is fulfilled without server-side revalidation at the current
--    checkpoint"), applied literally, twice, independently.** app.submit_
--    loyalty_redemption re-validates reward status/effective-window/tier/
--    points/hold fully at submission. app.decide_loyalty_redemption
--    RE-validates ALL FIVE of the same checks AGAIN, fresh, immediately
--    before composing the approve branch -- time may have genuinely passed
--    between submission and a staff decision (the reward could have been
--    paused, the account could have been newly held, the customer's own
--    points/tier could have changed), and this checkpoint never trusts the
--    submission-time snapshot alone for the actual mutating decision.
-- 10. **NULL-bypass optimistic concurrency, applied from the start** on
--    every one of the four version-checked functions (app.decide_loyalty_
--    redemption's own reject branch, app.cancel_loyalty_redemption, app.
--    mark_loyalty_redemption_fulfilled, app.mark_loyalty_redemption_
--    fulfillment_failed, and app._compose_loyalty_redemption_decision's own
--    internal UPDATE) -- every UPDATE's own WHERE clause repeats `and
--    record_version = p_expected_version`/the freshly-locked row's own
--    record_version, never relying on a preceding SELECT/IF check alone
--    (the Batch 4 Tier C review's own self-found-and-fixed defect class,
--    applied proactively here).
-- 11. **clock_timestamp(), never now(), everywhere in this migration** --
--    including every created_at/updated_at/decided_at, this migration's own
--    touch-row trigger, and every effective-date comparison against app.
--    loyalty_rewards.effective_from/effective_to (the CPL-320 self-found-
--    and-fixed defect class, applied proactively here from the first draft,
--    not discovered by a later review pass).
-- 12. **Idempotency, applied throughout.** app.submit_loyalty_redemption
--    carries a real, caller-supplied, NOT NULL `unique(tenant_id,
--    idempotency_key)` constraint on app.loyalty_redemptions itself, the
--    scope/authority check running BEFORE the idempotent short-circuit
--    SELECT (which also verifies the full target tuple -- loyalty_
--    account_id/reward_id -- on a key match, not only the key, the C-01
--    lesson), a real `exception when unique_violation` handler, and the
--    idempotency-establishing INSERT happens strictly BEFORE any downstream
--    stock/points/entitlement mutation in the same function (the CPL-318
--    ordering lesson, applied proactively since this checkpoint composes
--    THREE mutating primitives in one transaction). Every downstream
--    composed call (reservation, points consumption, entitlement issuance,
--    reversal) derives its OWN deterministic idempotency key from the
--    redemption's own id (`'redemption-stock:' || id`, `'redemption-
--    points:' || id`, `'redemption-entitlement:' || id`, `'redemption-
--    release:' || id`, `'redemption-reversal:' || id || ':lot:' || lot_id`)
--    -- a genuine retry of the SAME logical step is always a safe no-op,
--    never a double-spend.
-- 13. **Atomicity, live-proven adversarially (this checkpoint's own db-
--    test).** Every failure branch inside app._compose_loyalty_redemption_
--    decision (insufficient stock, insufficient points, a misconfigured
--    discount_voucher reward with no internal_cost) is an UNCAUGHT
--    exception that aborts the WHOLE app._compose_loyalty_redemption_
--    decision call -- the stock reservation and the point consumption
--    already made earlier in that SAME composition call are both rolled
--    back together, NOTHING of the composition's own partial work survives
--    a forced mid-composition failure (live-proven with a misconfigured
--    (internal_cost null) discount_voucher reward carrying real finite
--    stock and a real points cost). **Tier C review correction (Batch 5
--    close): the redemption row's own INSERT does NOT also roll back.**
--    This paragraph originally claimed it did, for the specific case where
--    app.submit_loyalty_redemption's own auto-approve attempt (design
--    decision 5) reaches this failure -- true only while that caller
--    re-raised every non-insufficient_authority exception uncaught, which
--    was itself the defect design decision 5 above now discloses and
--    fixes. With that fix applied, app.submit_loyalty_redemption catches
--    every composition failure and the redemption row/event (inserted
--    BEFORE this helper is ever called) correctly survive at
--    pending_approval -- only the composition's own downstream stock/
--    points/entitlement work rolls back, exactly as this helper's own
--    savepoint scoping was always designed to guarantee.
-- 14. **LYL permission mapping, reused from CPL-316/317/318/319/320
--    unchanged.** Ordinary redemption-request lifecycle (submit's own
--    intent-record creation, mark_fulfilled/mark_fulfillment_failed) ->
--    `LYL:Edit` (mirrors CPL-320's own stock-reservation mapping). The
--    governance-grade staff decision (decide_loyalty_redemption, approve/
--    reject) -> the elevated `LYL:Configure`, mirroring CPL-316/317/318's
--    own publish/reverse/decide-adjustment mapping exactly -- and, per
--    design decision 10's own CPL-318 precedent, explicitly, visibly ALSO
--    requires LYL:Edit for the specific branch (approve) that delegates to
--    the LYL:Edit-gated composition primitives. Staff reads -> `LYL:View`.
--    Customer-facing reads/submit/cancel -> scoped via `app.resolve_
--    customer_account_scope`, no staff RBAC check for THAT authority path
--    (submit/cancel are dual-authority, design decision 5/this note).
-- 15. Every actor-taking function in this migration (all 12 public RPCs
--    plus both private helpers) calls `app.assert_actor_is_session_
--    identity` as its own literal FIRST statement; every staff mutate/
--    get-by-id RPC checks `LYL:*` authority BEFORE fetching its target row
--    (C-05).
-- 16. **RLS: `authenticated` holds ZERO direct grant** on either new table,
--    mirroring CPL-316/317/318/319/320 exactly. `app.loyalty_redemption_
--    events` is append-only (no UPDATE/DELETE grant to any role, not even
--    service_role, mirroring app.loyalty_benefit_entitlement_events/app.
--    loyalty_point_ledger_entries exactly) -- per `ISS-2026-130`, this
--    checkpoint does not implement a Supreme-Admin-override mechanism for
--    it either, an already-accepted, standing, repository-wide gap, not a
--    new one this checkpoint introduces.
-- 17. Per `ERR-2026-004`: this migration carries its own explicit `revoke
--    execute on all functions in schema app from public` statement before
--    its final grants.
-- 18. **Cursor pagination**: `(tenant_id, updated_at desc, id desc)` on
--    every list RPC, never `OFFSET`.

-- ===========================================================================
-- 1. app.loyalty_redemptions -- the redemption-request record. A real,
-- MUTABLE, single-row-per-redemption table (design decisions 3/5), not a
-- ledger -- its own lifecycle IS the record; app.loyalty_redemption_events
-- (below) is the append-only audit trail.
-- ===========================================================================

create table app.loyalty_redemptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  loyalty_account_id uuid not null references app.loyalty_accounts (id),
  reward_id uuid not null references app.loyalty_rewards (id),
  reward_version_number integer not null,
  reward_name text not null,
  reward_type text not null,
  points_consumed numeric not null default 0,
  stock_reservation_id uuid references app.loyalty_reward_stock_reservations (id),
  benefit_entitlement_id uuid references app.loyalty_benefit_entitlements (id),
  status text not null default 'pending_approval',
  fulfillment_status text not null default 'pending',
  decision_reason text,
  decided_by text,
  decided_at timestamptz,
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint lrd_reward_type_check check (reward_type in ('discount_voucher', 'physical_item', 'service_credit')),
  constraint lrd_status_check check (status in ('pending_approval', 'approved', 'rejected', 'fulfilling', 'fulfilled', 'cancelled', 'failed')),
  constraint lrd_fulfillment_status_check check (fulfillment_status in ('not_applicable', 'pending', 'in_fulfillment', 'fulfilled', 'failed')),
  constraint lrd_voucher_fulfillment_check check (reward_type <> 'discount_voucher' or fulfillment_status = 'not_applicable'),
  constraint lrd_points_consumed_check check (points_consumed >= 0),
  constraint lrd_decision_shape_check check ((status = 'pending_approval') = (decided_by is null and decided_at is null)),
  constraint lrd_reject_reason_check check (status <> 'rejected' or (decision_reason is not null and length(trim(decision_reason)) > 0)),
  constraint lrd_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.loyalty_redemptions is
  'CPL-321: one row per redemption request, mutated exclusively by app.submit_loyalty_redemption/app.decide_loyalty_redemption/app.cancel_loyalty_redemption/app.mark_loyalty_redemption_fulfilled/app.mark_loyalty_redemption_fulfillment_failed/app._compose_loyalty_redemption_decision (private) -- no other function or direct write ever changes it. reward_version_number/reward_name/reward_type are a point-in-time SNAPSHOT captured at request time (design decision, audit-preserving even if the reward is later republished under a new version). fulfillment_status is genuinely new, first-of-its-kind fulfillment tracking (design decision 3) for physical_item/service_credit only -- discount_voucher is always not_applicable (design decision 3, lrd_voucher_fulfillment_check).';

create index lrd_tenant_updated_id_idx on app.loyalty_redemptions (tenant_id, updated_at desc, id desc);
create index lrd_tenant_account_idx on app.loyalty_redemptions (tenant_id, loyalty_account_id);
create index lrd_tenant_status_idx on app.loyalty_redemptions (tenant_id, status);
create index lrd_reward_idx on app.loyalty_redemptions (reward_id);

create function app.touch_loyalty_redemption_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_redemptions_touch_row
  before update on app.loyalty_redemptions
  for each row
  execute function app.touch_loyalty_redemption_row();

-- ===========================================================================
-- 2. app.loyalty_redemption_events -- APPEND-ONLY lifecycle/audit log,
-- mirroring app.loyalty_benefit_entitlement_events' own shape exactly
-- (design decision 16).
-- ===========================================================================

create table app.loyalty_redemption_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  redemption_id uuid not null references app.loyalty_redemptions (id),
  event_type text not null,
  reason text,
  actor_auth_user_id uuid,
  actor_label text,
  created_at timestamptz not null default clock_timestamp(),
  constraint lrde_event_type_check check (event_type in ('submitted', 'approved', 'rejected', 'cancelled', 'fulfilled', 'fulfillment_failed')),
  constraint lrde_reason_check check (event_type not in ('rejected', 'fulfillment_failed') or (reason is not null and length(trim(reason)) > 0))
);

comment on table app.loyalty_redemption_events is
  'CPL-321: append-only. No UPDATE/DELETE grant to any role anywhere in this migration (mirrors app.loyalty_benefit_entitlement_events/app.loyalty_point_ledger_entries exactly, design decision 16) -- every status transition writes exactly one new event row here, the redemption row itself is never deleted or rewritten to erase history.';

create index lrde_tenant_redemption_created_idx on app.loyalty_redemption_events (tenant_id, redemption_id, created_at desc);
create index lrde_tenant_created_id_idx on app.loyalty_redemption_events (tenant_id, created_at desc, id desc);

-- ===========================================================================
-- 3. Widen app.loyalty_reward_stock_reservations' own CHECK constraint
-- (design decision 8) -- a real, additive ALTER, CPL-320's own applied
-- migration file is never edited in place.
-- ===========================================================================

alter table app.loyalty_reward_stock_reservations drop constraint lrsr_quantity_check;
alter table app.loyalty_reward_stock_reservations add constraint lrsr_quantity_check check (quantity <> 0);

comment on table app.loyalty_reward_stock_reservations is
  'CPL-320/CPL-321: append-only reservation ledger -- one row per reserved (positive quantity, app.reserve_loyalty_reward_stock_unit) or released (negative quantity, app.release_loyalty_reward_stock_reservation, CPL-321 design decision 8) unit-delta against a reward with a finite total_stock. app.loyalty_rewards.stock_available is NEVER a stored/mirrored counter -- every read computes coalesce(sum(quantity), 0) over this table live, which nets a release out correctly with zero change to either read RPC. Race-safety comes from a select...for update lock on the TARGET REWARD ROW (never this table) taken before the aggregate is read.';

-- ===========================================================================
-- 4. app.release_loyalty_reward_stock_reservation -- staff/system, LYL:Edit.
-- The structural inverse of app.reserve_loyalty_reward_stock_unit (design
-- decision 8). Idempotent, no over-subscription check (a release can never
-- oversubscribe).
-- ===========================================================================

create function app.release_loyalty_reward_stock_reservation(
  p_tenant_id uuid,
  p_reward_id uuid,
  p_quantity integer,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.loyalty_reward_stock_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.loyalty_reward_stock_reservations;
  v_reward app.loyalty_rewards;
  v_reservation app.loyalty_reward_stock_reservations;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: quantity must be a positive integer, got %', p_quantity using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;

  -- Idempotent short-circuit AFTER the authority check (mandatory pattern).
  select * into v_existing from app.loyalty_reward_stock_reservations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;

  begin
    insert into app.loyalty_reward_stock_reservations (tenant_id, reward_id, quantity, reason, created_by, idempotency_key)
    values (p_tenant_id, p_reward_id, -p_quantity, p_reason, p_actor_label, p_idempotency_key)
    returning * into v_reservation;
  exception
    when unique_violation then
      select * into v_existing from app.loyalty_reward_stock_reservations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'release_loyalty_reward_stock_reservation',
    'app.loyalty_rewards', p_reward_id, 'success', p_reason, null, jsonb_build_object('released_quantity', p_quantity)
  );

  return v_reservation;
end;
$$;

comment on function app.release_loyalty_reward_stock_reservation is
  'CPL-321: idempotent on (tenant_id, idempotency_key). Posts a NEGATIVE-quantity row (design decision 8) -- app.loyalty_rewards own live stock_available computation nets it out automatically, no change to either CPL-320 read RPC required.';

-- ===========================================================================
-- 5. app._compose_loyalty_redemption_decision -- PRIVATE helper (no EXECUTE
-- grant to authenticated/service_role anywhere in this migration, mirrors
-- app.generate_random_base32_voucher_code, CPL-319, exactly). Performs the
-- actual composition (reserve stock -> consume points -> conditionally
-- issue a voucher entitlement) and finalizes the redemption row's own
-- status. Called from BOTH app.submit_loyalty_redemption's own auto-approve
-- attempt and app.decide_loyalty_redemption's own approve branch.
-- ===========================================================================

create function app._compose_loyalty_redemption_decision(
  p_tenant_id uuid,
  p_redemption_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_decision_reason text default null
)
returns app.loyalty_redemptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_redemption app.loyalty_redemptions;
  v_reward app.loyalty_rewards;
  v_reservation app.loyalty_reward_stock_reservations;
  v_currency text;
  v_entitlement_id uuid;
  v_final_status text;
  v_final_fulfillment_status text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_redemption from app.loyalty_redemptions where id = p_redemption_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_redemption_not_found: %', p_redemption_id using errcode = 'no_data_found';
  end if;

  select * into v_reward from app.loyalty_rewards where id = v_redemption.reward_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', v_redemption.reward_id using errcode = 'no_data_found';
  end if;

  -- Design decision 13: every downstream call below is UNCAUGHT here -- any
  -- failure (insufficient stock, insufficient points, a misconfigured
  -- voucher reward) aborts this WHOLE function, and every caller of this
  -- helper either lets that propagate further (decide_loyalty_redemption)
  -- or catches it and leaves its own already-inserted redemption row
  -- exactly where it is (submit_loyalty_redemption's own graceful
  -- fallback, design decision 5, Tier C review fix -- catches ANY
  -- composition exception, not only insufficient_authority) -- no partial
  -- mutation of the composition's own downstream work is ever left behind.
  v_reservation := app.reserve_loyalty_reward_stock_unit(
    p_tenant_id, v_reward.id, 1, 'redemption-stock:' || p_redemption_id::text,
    p_actor_auth_user_id, p_actor_label, 'redemption ' || p_redemption_id::text
  );

  if v_redemption.points_consumed > 0 then
    perform app.consume_loyalty_points_fifo(
      p_tenant_id, v_redemption.loyalty_account_id, v_redemption.points_consumed,
      'redemption', p_redemption_id, 'redemption-points:' || p_redemption_id::text,
      p_actor_auth_user_id, p_actor_label
    );
  end if;

  if v_reward.reward_type = 'discount_voucher' then
    -- Design decision 4: value_amount = internal_cost, currency = the
    -- tenant's own resolved default_currency.
    if v_reward.internal_cost is null or v_reward.internal_cost <= 0 then
      raise exception 'reward_redemption_unavailable: this reward is not currently configured for redemption -- contact support' using errcode = 'check_violation';
    end if;
    select default_currency into v_currency from app.resolve_tenant_locale(p_tenant_id);
    select ibe.id into v_entitlement_id from app.issue_loyalty_benefit_entitlement(
      p_tenant_id, v_redemption.loyalty_account_id, 'voucher', v_reward.internal_cost, null, coalesce(v_currency, 'USD'),
      'loyalty_redemption', p_redemption_id, null, 'redemption-entitlement:' || p_redemption_id::text,
      p_actor_auth_user_id, p_actor_label
    ) as ibe;
    v_final_status := 'fulfilled';
    v_final_fulfillment_status := 'not_applicable';
  else
    v_final_status := 'fulfilling';
    v_final_fulfillment_status := 'in_fulfillment';
  end if;

  update app.loyalty_redemptions
    set status = v_final_status, fulfillment_status = v_final_fulfillment_status,
        stock_reservation_id = v_reservation.id, benefit_entitlement_id = v_entitlement_id,
        decided_by = coalesce(v_redemption.decided_by, p_actor_label),
        decided_at = coalesce(v_redemption.decided_at, clock_timestamp()),
        decision_reason = coalesce(v_redemption.decision_reason, p_decision_reason, 'approved: eligibility, stock, and points re-validated at decision time')
    -- NULL-bypass fix (design decision 10): the predicate is repeated here.
    where id = p_redemption_id and record_version = v_redemption.record_version
    returning * into v_redemption;
  if not found then
    raise exception 'stale_version: redemption % was concurrently modified', p_redemption_id using errcode = 'serialization_failure';
  end if;

  insert into app.loyalty_redemption_events (tenant_id, redemption_id, event_type, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, p_redemption_id, 'approved', null, p_actor_auth_user_id, p_actor_label);
  if v_final_status = 'fulfilled' then
    insert into app.loyalty_redemption_events (tenant_id, redemption_id, event_type, reason, actor_auth_user_id, actor_label)
    values (p_tenant_id, p_redemption_id, 'fulfilled', null, p_actor_auth_user_id, p_actor_label);
  end if;

  return v_redemption;
end;
$$;

comment on function app._compose_loyalty_redemption_decision is
  'CPL-321: PRIVATE (no EXECUTE grant to authenticated/service_role, mirrors app.generate_random_base32_voucher_code, CPL-319, design decision 2b) -- only app.submit_loyalty_redemption/app.decide_loyalty_redemption call this, nested. Composes app.reserve_loyalty_reward_stock_unit + app.consume_loyalty_points_fifo (+ app.issue_loyalty_benefit_entitlement for discount_voucher) atomically -- an uncaught failure at any step rolls back every prior step in the SAME call (design decision 13). Tier C review fix (Batch 5 close): app.submit_loyalty_redemption now catches EVERY exception this function can raise (not only insufficient_authority), so a failure here never destroys the caller''s own already-inserted redemption row -- only this function''s own downstream stock/points/entitlement work rolls back.';

-- ===========================================================================
-- 6. app._reverse_loyalty_redemption_composition -- PRIVATE helper.
-- Reverses a prior successful composition (release the stock reservation,
-- credit back consumed points) -- called from app.decide_loyalty_
-- redemption's own reject branch, app.cancel_loyalty_redemption, and app.
-- mark_loyalty_redemption_fulfillment_failed.
-- ===========================================================================

create function app._reverse_loyalty_redemption_composition(
  p_tenant_id uuid,
  p_redemption app.loyalty_redemptions,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_entry record;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_redemption.stock_reservation_id is null then
    -- Nothing was ever actually reserved for this redemption (the graceful
    -- pending_approval-without-composition fallback, design decision 5) --
    -- a real, safe no-op, not an error.
    return;
  end if;

  perform app.release_loyalty_reward_stock_reservation(
    p_tenant_id, p_redemption.reward_id, 1, 'redemption-release:' || p_redemption.id::text,
    p_actor_auth_user_id, p_actor_label, 'reversal of redemption ' || p_redemption.id::text
  );

  if p_redemption.points_consumed > 0 then
    -- Design note: app.reverse_loyalty_points_earned (CPL-318) reverses an
    -- EARN event, not a FIFO consumption -- no direct precedent exists for
    -- reversing a REDEMPTION's own consuming entries. This is a genuinely
    -- NEW composition of app.post_loyalty_point_ledger_entry directly
    -- (never a claimed reuse of an existing reversal primitive), posting
    -- one positive 'reversal' entry per original consuming entry, each
    -- linked via corrects_entry_id and restoring its own originating lot
    -- (or crediting the lot-less aggregate balance directly when lot_id is
    -- null, mirroring app.consume_loyalty_points_fifo's own lot-less
    -- final-entry shape).
    for v_entry in
      select * from app.loyalty_point_ledger_entries
      where tenant_id = p_tenant_id and source_type = 'redemption' and source_id = p_redemption.id and event_type = 'redemption'
      order by created_at asc, id asc
    loop
      perform app.post_loyalty_point_ledger_entry(
        p_tenant_id, p_redemption.loyalty_account_id, 'reversal', -v_entry.amount, v_entry.lot_id,
        'redemption', p_redemption.id,
        'redemption-reversal:' || p_redemption.id::text || ':lot:' || coalesce(v_entry.lot_id::text, 'unlotted'),
        'reversal of redemption ' || p_redemption.id::text, v_entry.id,
        p_actor_auth_user_id, p_actor_label
      );
    end loop;
  end if;
end;
$$;

comment on function app._reverse_loyalty_redemption_composition is
  'CPL-321: PRIVATE (no EXECUTE grant). A real, safe no-op when nothing was ever reserved (p_redemption.stock_reservation_id is null -- the graceful pending_approval-without-composition fallback). Otherwise releases the stock reservation and posts a real, new, linked positive reversal entry per originally-consumed point-ledger entry -- never deletes or rewrites history.';

-- ===========================================================================
-- 7. app.submit_loyalty_redemption -- dual authority: customer_user (Layer
-- 4, app.resolve_customer_account_scope) OR staff (LYL:Edit) -- design
-- decision 5. The main flow entry point.
-- ===========================================================================

create function app.submit_loyalty_redemption(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_reward_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_redemptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_is_staff boolean;
  v_scope uuid[];
  v_existing app.loyalty_redemptions;
  v_account app.loyalty_accounts;
  v_reward app.loyalty_rewards;
  v_held boolean;
  v_current_tier_rank integer;
  v_min_tier_rank integer;
  v_current_points numeric;
  v_points_consumed numeric;
  v_redemption_id uuid;
  v_redemption app.loyalty_redemptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Coarse standing check (mandatory pattern: scope/authority check BEFORE
  -- the idempotent short-circuit).
  v_is_staff := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit')).allowed;
  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if not v_is_staff and array_length(v_scope, 1) is null then
    raise exception 'insufficient_authority: identity % holds neither LYL:Edit nor any customer_user account scope for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;

  -- Idempotent short-circuit AFTER the standing check, verifying the FULL
  -- target tuple on a key match (C-01), not only the key.
  select * into v_existing from app.loyalty_redemptions where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.loyalty_account_id <> p_loyalty_account_id or v_existing.reward_id <> p_reward_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different redemption request', p_idempotency_key using errcode = 'check_violation';
    end if;
    return v_existing;
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found or v_account.status <> 'active' or not (v_is_staff or v_account.customer_account_id = any (v_scope)) then
    -- Anti-enumeration for the caller's own standing.
    raise exception 'loyalty_account_not_found: %', p_loyalty_account_id using errcode = 'no_data_found';
  end if;

  -- Re-validate eligibility server-side, at THIS checkpoint, inside THIS
  -- transaction -- never trust a client-supplied "I saw this as eligible"
  -- claim (business rule; design decision 9).
  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id and program_id = v_account.program_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;
  if v_reward.status <> 'published' or v_reward.effective_from > clock_timestamp() or (v_reward.effective_to is not null and v_reward.effective_to <= clock_timestamp()) then
    raise exception 'reward_not_currently_redeemable: reward % is not currently available for redemption', p_reward_id using errcode = 'check_violation';
  end if;

  -- Account-level fraud hold (design decision 6) -- blocks new redemptions
  -- the same way CPL-317 already suppresses tier-benefit display for a
  -- held account; a customer-safe, generic denial, never the real reason.
  select coalesce(is_held, false) into v_held from app.loyalty_account_tier_holds where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id;
  if coalesce(v_held, false) then
    raise exception 'account_on_hold: this account cannot redeem rewards at this time. Contact your account administrator or support for details.' using errcode = 'check_violation';
  end if;

  select td.tier_rank into v_current_tier_rank
  from app.loyalty_account_tier_movements tm
  join app.loyalty_tier_definitions td on td.id = tm.to_tier_id
  where tm.tenant_id = p_tenant_id and tm.loyalty_account_id = v_account.id
  order by tm.created_at desc, tm.id desc
  limit 1;

  if v_reward.min_tier_id is not null then
    select tier_rank into v_min_tier_rank from app.loyalty_tier_definitions where id = v_reward.min_tier_id;
    if v_current_tier_rank is null or v_current_tier_rank < v_min_tier_rank then
      raise exception 'ineligible_reward: this account does not currently meet the tier requirement for this reward' using errcode = 'check_violation';
    end if;
  end if;

  -- Design decision 1: points_cost = min_points_required.
  v_points_consumed := coalesce(v_reward.min_points_required, 0);
  if v_points_consumed > 0 then
    v_current_points := coalesce((select pb.available from app.loyalty_point_balances pb where pb.tenant_id = p_tenant_id and pb.loyalty_account_id = v_account.id), 0);
    if v_current_points < v_points_consumed then
      raise exception 'ineligible_reward: this account does not have enough points for this reward' using errcode = 'check_violation';
    end if;
  end if;

  v_redemption_id := gen_random_uuid();

  -- The idempotency-establishing INSERT happens strictly BEFORE any
  -- downstream stock/points/entitlement mutation (design decision 12).
  begin
    insert into app.loyalty_redemptions (
      id, tenant_id, loyalty_account_id, reward_id, reward_version_number, reward_name, reward_type,
      points_consumed, status, fulfillment_status, idempotency_key, created_by
    ) values (
      v_redemption_id, p_tenant_id, p_loyalty_account_id, p_reward_id, v_reward.version_number, v_reward.reward_name, v_reward.reward_type,
      v_points_consumed, 'pending_approval', case when v_reward.reward_type = 'discount_voucher' then 'not_applicable' else 'pending' end,
      p_idempotency_key, p_actor_label
    )
    returning * into v_redemption;
  exception
    when unique_violation then
      select * into v_existing from app.loyalty_redemptions where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      return v_existing;
  end;

  insert into app.loyalty_redemption_events (tenant_id, redemption_id, event_type, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_redemption_id, 'submitted', null, p_actor_auth_user_id, p_actor_label);

  -- Attempt immediate composition (design decision 5) -- ONLY for
  -- discount_voucher (my own reward_type threshold rule: physical_item/
  -- service_credit ALWAYS require a genuine staff decision, regardless of
  -- who submitted -- deterministic, never actor-dependent for those two
  -- types). Even for discount_voucher, this succeeds synchronously only
  -- when the submitting actor ALSO independently holds LYL:Edit (staff/
  -- system); a genuine, unassisted customer_user actor gracefully falls
  -- back to pending_approval, awaiting a real staff app.decide_loyalty_
  -- redemption call.
  if v_reward.reward_type = 'discount_voucher' then
    begin
      v_redemption := app._compose_loyalty_redemption_decision(p_tenant_id, v_redemption_id, p_actor_auth_user_id, p_actor_label, null);
    exception
      when others then
        -- Tier C review fix (Batch 5 close): catch EVERY composition
        -- failure here, not only insufficient_authority -- a genuine
        -- customer_user actor fails on insufficient_authority (the
        -- originally-anticipated case), but a staff/system actor who DOES
        -- hold LYL:Edit can also reach this branch and have the attempt
        -- fail for a completely ordinary, non-authority reason
        -- (insufficient_reward_stock, insufficient_points_balance, or a
        -- misconfigured discount_voucher reward's own reward_redemption_
        -- unavailable). Filtering the catch by sqlerrm and re-raising
        -- every other exception used to abort this WHOLE function call,
        -- which rolled back the redemption row's own INSERT and its
        -- 'submitted' event too (both happened BEFORE this begin block,
        -- hence before the implicit savepoint it establishes) -- silently
        -- losing the customer's own otherwise-legitimate request with zero
        -- audit trail, directly contradicting this migration's own
        -- documented invariant (design decision 5: "every submission,
        -- regardless of caller, ALWAYS creates the real, portal-owned
        -- intent/request record"). Every composition failure, whatever its
        -- cause, now leaves the row exactly where it already is --
        -- pending_approval, as inserted above -- so a human can resolve it
        -- via app.decide_loyalty_redemption, which independently re-
        -- validates the identical business condition (stock, points,
        -- reward configuration) at decision time rather than destroying
        -- the request outright. The downstream stock/points/entitlement
        -- work attempted inside _compose_loyalty_redemption_decision
        -- itself still correctly and fully rolls back either way (design
        -- decision 13) -- only the OUTER redemption-row/event survival
        -- changes.
        null;
    end;
  end if;

  return v_redemption;
end;
$$;

comment on function app.submit_loyalty_redemption is
  'CPL-321: dual authority (design decision 5) -- customer_user own account scope OR staff LYL:Edit. Idempotent on (tenant_id, idempotency_key), verifying the full target tuple on a key match (C-01). Re-validates reward status/effective-window/hold/tier/points fully, server-side, inside this transaction. Attempts immediate reserve+consume(+issue) composition; gracefully falls back to pending_approval on ANY composition failure (Tier C review fix, Batch 5 close -- not only when the submitting actor lacks LYL:Edit) -- see this migration''s own header design decision 5 for the full, disclosed reasoning.';

-- ===========================================================================
-- 8. app.decide_loyalty_redemption -- staff, LYL:Configure (governance-
-- grade). Mandatory non-empty reason on rejection. Structurally
-- unreachable by any customer_user identity (design decision 7).
-- ===========================================================================

create function app.decide_loyalty_redemption(
  p_tenant_id uuid,
  p_redemption_id uuid,
  p_expected_version integer,
  p_decision text,
  p_decision_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_redemptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_redemption app.loyalty_redemptions;
  v_reward app.loyalty_rewards;
  v_held boolean;
  v_current_tier_rank integer;
  v_min_tier_rank integer;
  v_current_points numeric;
  v_updated app.loyalty_redemptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_decision is null or p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not one of approve/reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'reject' and (p_decision_reason is null or length(trim(p_decision_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a redemption' using errcode = 'not_null_violation';
  end if;

  select * into v_redemption from app.loyalty_redemptions where id = p_redemption_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_redemption_not_found: %', p_redemption_id using errcode = 'no_data_found';
  end if;
  -- NULL-bypass fix: a bare `<>` comparison against a NULL p_expected_
  -- version evaluates to SQL NULL (falsy), silently skipping this check.
  -- The reject branch's own UPDATE below independently repeats this
  -- predicate too (a second, redundant safeguard) -- but the approve
  -- branch delegates its actual mutation to app._compose_loyalty_
  -- redemption_decision, which uses its OWN freshly re-read record_version
  -- (never p_expected_version) for its own UPDATE, so THIS explicit check
  -- is the ONLY place a stale/NULL p_expected_version is ever rejected on
  -- that path -- must not rely on the bare `<>` alone.
  if p_expected_version is null or v_redemption.record_version <> p_expected_version then
    raise exception 'stale_version: redemption % expected version % but found %', p_redemption_id, p_expected_version, v_redemption.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_redemption.status <> 'pending_approval' then
    raise exception 'invalid_transition: redemption % is % -- only a pending_approval redemption may be decided', p_redemption_id, v_redemption.status
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approve' then
    -- Re-validate eligibility/hold/reward status ONE more time, fresh, at
    -- THIS checkpoint (design decision 9) -- time may have passed since
    -- submission.
    select * into v_reward from app.loyalty_rewards where id = v_redemption.reward_id and tenant_id = p_tenant_id;
    if not found or v_reward.status <> 'published' or v_reward.effective_from > clock_timestamp() or (v_reward.effective_to is not null and v_reward.effective_to <= clock_timestamp()) then
      raise exception 'reward_not_currently_redeemable: reward % is no longer available for redemption', v_redemption.reward_id using errcode = 'check_violation';
    end if;

    select coalesce(is_held, false) into v_held from app.loyalty_account_tier_holds where tenant_id = p_tenant_id and loyalty_account_id = v_redemption.loyalty_account_id;
    if coalesce(v_held, false) then
      raise exception 'account_on_hold: this account cannot redeem rewards at this time. Contact your account administrator or support for details.' using errcode = 'check_violation';
    end if;

    select td.tier_rank into v_current_tier_rank
      from app.loyalty_account_tier_movements tm join app.loyalty_tier_definitions td on td.id = tm.to_tier_id
      where tm.tenant_id = p_tenant_id and tm.loyalty_account_id = v_redemption.loyalty_account_id
      order by tm.created_at desc, tm.id desc limit 1;
    if v_reward.min_tier_id is not null then
      select tier_rank into v_min_tier_rank from app.loyalty_tier_definitions where id = v_reward.min_tier_id;
      if v_current_tier_rank is null or v_current_tier_rank < v_min_tier_rank then
        raise exception 'ineligible_reward: this account no longer meets the tier requirement for this reward' using errcode = 'check_violation';
      end if;
    end if;

    if v_redemption.points_consumed > 0 then
      v_current_points := coalesce((select pb.available from app.loyalty_point_balances pb where pb.tenant_id = p_tenant_id and pb.loyalty_account_id = v_redemption.loyalty_account_id), 0);
      if v_current_points < v_redemption.points_consumed then
        raise exception 'ineligible_reward: this account no longer has enough points for this reward' using errcode = 'check_violation';
      end if;
    end if;

    -- Explicit LYL:Edit re-check before delegating (design decision 14,
    -- mirrors CPL-318's own design decision 16 precedent exactly) -- a
    -- Configure-only actor gets a clear, immediate, self-referential
    -- rejection rather than a confusing nested failure.
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant % -- approval delegates to app.reserve_loyalty_reward_stock_unit/app.consume_loyalty_points_fifo, which also require LYL:Edit', p_actor_auth_user_id, v_decision.reason, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;

    v_updated := app._compose_loyalty_redemption_decision(p_tenant_id, p_redemption_id, p_actor_auth_user_id, p_actor_label, p_decision_reason);
  else
    update app.loyalty_redemptions
      set status = 'rejected', fulfillment_status = 'not_applicable', decided_by = p_actor_label, decided_at = clock_timestamp(), decision_reason = p_decision_reason
      -- NULL-bypass fix (design decision 10).
      where id = p_redemption_id and record_version = p_expected_version
      returning * into v_updated;
    if not found then
      raise exception 'stale_version: redemption % was concurrently modified (expected version %)', p_redemption_id, p_expected_version
        using errcode = 'serialization_failure';
    end if;

    -- Reverse whatever was already composed at submit time, if anything
    -- (design decision 8/business rule: rejection reverses stock AND
    -- points together, a real, safe no-op when nothing was reserved).
    perform app._reverse_loyalty_redemption_composition(p_tenant_id, v_redemption, p_actor_auth_user_id, p_actor_label);

    insert into app.loyalty_redemption_events (tenant_id, redemption_id, event_type, reason, actor_auth_user_id, actor_label)
    values (p_tenant_id, p_redemption_id, 'rejected', p_decision_reason, p_actor_auth_user_id, p_actor_label);
  end if;

  return v_updated;
end;
$$;

comment on function app.decide_loyalty_redemption is
  'CPL-321: staff-only, LYL:Configure -- structurally unreachable by any customer_user identity (design decision 7, self-approval impossible). Approve re-validates eligibility/hold/reward-status fresh, explicitly re-checks LYL:Edit before delegating to the composition (design decision 14), and is the ONE place a graceful submit-time fallback (design decision 5) is always completed. Reject requires a mandatory non-empty reason and reverses any prior composition (design decision 8).';

-- ===========================================================================
-- 9. app.cancel_loyalty_redemption -- dual authority (customer own account
-- OR staff), same reversal semantics as reject. Only a still-pending
-- (pending_approval) redemption may be cancelled.
-- ===========================================================================

create function app.cancel_loyalty_redemption(
  p_tenant_id uuid,
  p_redemption_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_redemptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_is_staff boolean;
  v_scope uuid[];
  v_redemption app.loyalty_redemptions;
  v_account app.loyalty_accounts;
  v_updated app.loyalty_redemptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_is_staff := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit')).allowed;
  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if not v_is_staff and array_length(v_scope, 1) is null then
    raise exception 'insufficient_authority: identity % holds neither LYL:Edit nor any customer_user account scope for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_redemption from app.loyalty_redemptions where id = p_redemption_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_redemption_not_found: %', p_redemption_id using errcode = 'no_data_found';
  end if;

  if not v_is_staff then
    select * into v_account from app.loyalty_accounts where id = v_redemption.loyalty_account_id;
    if v_account.id is null or not (v_account.customer_account_id = any (v_scope)) then
      -- Anti-enumeration for the caller's own standing.
      raise exception 'loyalty_redemption_not_found: %', p_redemption_id using errcode = 'no_data_found';
    end if;
  end if;

  -- NULL-bypass fix: checked explicitly and BEFORE the reversal call below
  -- (which has a real side effect -- releasing stock/crediting points) --
  -- a bare `<>` against a NULL p_expected_version would otherwise let that
  -- side effect run before the version-guarded UPDATE's own repeated
  -- predicate ever gets a chance to reject it.
  if p_expected_version is null or v_redemption.record_version <> p_expected_version then
    raise exception 'stale_version: redemption % expected version % but found %', p_redemption_id, p_expected_version, v_redemption.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_redemption.status <> 'pending_approval' then
    raise exception 'invalid_transition: redemption % is % -- only a still-pending redemption may be cancelled', p_redemption_id, v_redemption.status
      using errcode = 'check_violation';
  end if;

  -- Attempt reversal BEFORE the status flip -- if the caller cannot
  -- complete a real reversal this redemption actually needs (a customer
  -- cancelling a rare staff-reserved-on-their-behalf request), the WHOLE
  -- cancellation is refused rather than silently leaving stock/points
  -- reserved under a cancelled status (untracked liability, the business
  -- rule this checkpoint's own source prompt exists to protect against).
  perform app._reverse_loyalty_redemption_composition(p_tenant_id, v_redemption, p_actor_auth_user_id, p_actor_label);

  update app.loyalty_redemptions
    set status = 'cancelled', fulfillment_status = 'not_applicable', decided_by = p_actor_label, decided_at = clock_timestamp(), decision_reason = coalesce(decision_reason, 'cancelled by request')
    -- NULL-bypass fix (design decision 10).
    where id = p_redemption_id and record_version = p_expected_version
    returning * into v_updated;
  if not found then
    raise exception 'stale_version: redemption % was concurrently modified (expected version %)', p_redemption_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.loyalty_redemption_events (tenant_id, redemption_id, event_type, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, p_redemption_id, 'cancelled', null, p_actor_auth_user_id, p_actor_label);

  return v_updated;
end;
$$;

comment on function app.cancel_loyalty_redemption is
  'CPL-321: dual authority (customer own account OR staff), mirrors app.submit_loyalty_redemption''s own gate. Only pending_approval may be cancelled. Reverses any prior composition first (same helper as reject) -- if the caller cannot complete a needed reversal, the whole cancellation is refused rather than leaving stock/points silently stranded.';

-- ===========================================================================
-- 10. app.mark_loyalty_redemption_fulfilled / app.mark_loyalty_redemption_
-- fulfillment_failed -- staff, LYL:Edit. Fulfillment lifecycle for
-- physical_item/service_credit types ONLY (discount_voucher is already
-- 'fulfilled' the moment the entitlement issues -- no separate fulfillment
-- step for that type, design decision 3).
-- ===========================================================================

create function app.mark_loyalty_redemption_fulfilled(
  p_tenant_id uuid,
  p_redemption_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_redemptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_redemption app.loyalty_redemptions;
  v_updated app.loyalty_redemptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_redemption from app.loyalty_redemptions where id = p_redemption_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_redemption_not_found: %', p_redemption_id using errcode = 'no_data_found';
  end if;
  if p_expected_version is null or v_redemption.record_version <> p_expected_version then
    raise exception 'stale_version: redemption % expected version % but found %', p_redemption_id, p_expected_version, v_redemption.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_redemption.reward_type = 'discount_voucher' then
    raise exception 'invalid_transition: redemption % is a discount_voucher -- it is fulfilled automatically at approval, never via this function', p_redemption_id
      using errcode = 'check_violation';
  end if;
  if v_redemption.status <> 'fulfilling' then
    raise exception 'invalid_transition: redemption % is % -- only a fulfilling redemption may be marked fulfilled', p_redemption_id, v_redemption.status
      using errcode = 'check_violation';
  end if;

  update app.loyalty_redemptions
    set status = 'fulfilled', fulfillment_status = 'fulfilled'
    -- NULL-bypass fix (design decision 10).
    where id = p_redemption_id and record_version = p_expected_version
    returning * into v_updated;
  if not found then
    raise exception 'stale_version: redemption % was concurrently modified (expected version %)', p_redemption_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.loyalty_redemption_events (tenant_id, redemption_id, event_type, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, p_redemption_id, 'fulfilled', null, p_actor_auth_user_id, p_actor_label);

  return v_updated;
end;
$$;

create function app.mark_loyalty_redemption_fulfillment_failed(
  p_tenant_id uuid,
  p_redemption_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_redemptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_redemption app.loyalty_redemptions;
  v_updated app.loyalty_redemptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to mark a fulfillment failed' using errcode = 'not_null_violation';
  end if;

  select * into v_redemption from app.loyalty_redemptions where id = p_redemption_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_redemption_not_found: %', p_redemption_id using errcode = 'no_data_found';
  end if;
  if p_expected_version is null or v_redemption.record_version <> p_expected_version then
    raise exception 'stale_version: redemption % expected version % but found %', p_redemption_id, p_expected_version, v_redemption.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_redemption.status <> 'fulfilling' then
    raise exception 'invalid_transition: redemption % is % -- only a fulfilling redemption may be marked failed', p_redemption_id, v_redemption.status
      using errcode = 'check_violation';
  end if;

  update app.loyalty_redemptions
    set status = 'failed', fulfillment_status = 'failed'
    -- NULL-bypass fix (design decision 10).
    where id = p_redemption_id and record_version = p_expected_version
    returning * into v_updated;
  if not found then
    raise exception 'stale_version: redemption % was concurrently modified (expected version %)', p_redemption_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- A fulfillment failure genuinely reverses the earlier composition too
  -- (an extension beyond the literal ask, disclosed -- leaving stock/points
  -- spent for a redemption that ultimately could not be fulfilled would be
  -- a real, untracked-liability bug the source prompt's own business rules
  -- exist to prevent).
  perform app._reverse_loyalty_redemption_composition(p_tenant_id, v_redemption, p_actor_auth_user_id, p_actor_label);

  insert into app.loyalty_redemption_events (tenant_id, redemption_id, event_type, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, p_redemption_id, 'fulfillment_failed', p_reason, p_actor_auth_user_id, p_actor_label);

  return v_updated;
end;
$$;

comment on function app.mark_loyalty_redemption_fulfillment_failed is
  'CPL-321: mandatory non-empty reason. Genuinely reverses the stock reservation and point consumption made at approval time (disclosed extension beyond the literal ask -- a fulfillment failure must not leave real value silently spent for something that was never actually delivered).';

-- ===========================================================================
-- 11. Staff reads -- LYL:View.
-- ===========================================================================

create function app.get_loyalty_redemption(p_tenant_id uuid, p_redemption_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_redemptions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_redemption app.loyalty_redemptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_redemption from app.loyalty_redemptions where id = p_redemption_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_redemption_not_found: %', p_redemption_id using errcode = 'no_data_found';
  end if;

  return v_redemption;
end;
$$;

create function app.list_loyalty_redemptions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status text default null,
  p_loyalty_account_id uuid default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_redemptions
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
  select r.* from app.loyalty_redemptions r
  where r.tenant_id = p_tenant_id
    and (p_status is null or r.status = p_status)
    and (p_loyalty_account_id is null or r.loyalty_account_id = p_loyalty_account_id)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

-- ===========================================================================
-- 12. app.list_customer_portal_loyalty_redemptions / app.get_customer_
-- portal_loyalty_redemption -- customer-facing (Layer 4, ADR-0024 Part A).
-- Deny-by-default, anti-enumerating, cursor-paginated.
-- ===========================================================================

create function app.list_customer_portal_loyalty_redemptions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_loyalty_account_id uuid default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  redemption_id uuid,
  loyalty_account_id uuid,
  reward_id uuid,
  reward_name text,
  reward_type text,
  points_consumed numeric,
  benefit_entitlement_id uuid,
  status text,
  fulfillment_status text,
  decision_reason text,
  decided_at timestamptz,
  record_version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  -- Deny-by-default (ADR-0024 Part A).
  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select
    r.id, r.loyalty_account_id, r.reward_id, r.reward_name, r.reward_type, r.points_consumed, r.benefit_entitlement_id,
    r.status, r.fulfillment_status, r.decision_reason, r.decided_at, r.record_version, r.created_at, r.updated_at
  from app.loyalty_redemptions r
  join app.loyalty_accounts la on la.id = r.loyalty_account_id
  where r.tenant_id = p_tenant_id
    and la.customer_account_id = any (v_scope)
    and (p_loyalty_account_id is null or r.loyalty_account_id = p_loyalty_account_id)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_loyalty_redemptions is
  'CPL-321: customer-safe redemption status/history projection. Deny-by-default: an out-of-scope/empty resolved scope returns zero rows, never an error. record_version is included so the wallet''s own per-row cancel action can pass a real p_expected_version.';

create function app.get_customer_portal_loyalty_redemption(p_tenant_id uuid, p_redemption_id uuid, p_actor_auth_user_id uuid)
returns table (
  redemption_id uuid,
  loyalty_account_id uuid,
  reward_id uuid,
  reward_name text,
  reward_type text,
  points_consumed numeric,
  benefit_entitlement_id uuid,
  status text,
  fulfillment_status text,
  decision_reason text,
  decided_at timestamptz,
  record_version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_row app.loyalty_redemptions;
  v_account app.loyalty_accounts;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    raise exception 'loyalty_redemption_not_found: %', p_redemption_id using errcode = 'no_data_found';
  end if;

  select * into v_row from app.loyalty_redemptions where id = p_redemption_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_redemption_not_found: %', p_redemption_id using errcode = 'no_data_found';
  end if;

  select * into v_account from app.loyalty_accounts where id = v_row.loyalty_account_id;
  if v_account.id is null or not (v_account.customer_account_id = any (v_scope)) then
    -- Anti-enumeration: identical to a genuinely nonexistent redemption.
    raise exception 'loyalty_redemption_not_found: %', p_redemption_id using errcode = 'no_data_found';
  end if;

  return query select
    v_row.id, v_row.loyalty_account_id, v_row.reward_id, v_row.reward_name, v_row.reward_type, v_row.points_consumed, v_row.benefit_entitlement_id,
    v_row.status, v_row.fulfillment_status, v_row.decision_reason, v_row.decided_at, v_row.record_version, v_row.created_at, v_row.updated_at;
end;
$$;

comment on function app.get_customer_portal_loyalty_redemption is
  'CPL-321: anti-enumerating -- a genuinely nonexistent redemption and an out-of-scope loyalty account both raise the identical loyalty_redemption_not_found error.';

-- ===========================================================================
-- 13. RLS -- enable, grant service_role only (design decision 16).
-- ===========================================================================

alter table app.loyalty_redemptions enable row level security;
alter table app.loyalty_redemption_events enable row level security;

grant select, insert, update on app.loyalty_redemptions to service_role;
grant select, insert on app.loyalty_redemption_events to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.release_loyalty_reward_stock_reservation(uuid, uuid, integer, text, uuid, text, text) to authenticated, service_role;
grant execute on function app.submit_loyalty_redemption(uuid, uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_loyalty_redemption(uuid, uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_loyalty_redemption(uuid, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.mark_loyalty_redemption_fulfilled(uuid, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.mark_loyalty_redemption_fulfillment_failed(uuid, uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_redemption(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_redemptions(uuid, uuid, text, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_portal_loyalty_redemptions(uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.get_customer_portal_loyalty_redemption(uuid, uuid, uuid) to authenticated, service_role;

-- app._compose_loyalty_redemption_decision / app._reverse_loyalty_
-- redemption_composition deliberately carry NO grant to authenticated or
-- service_role anywhere in this migration (design decisions 5/6, mirrors
-- app.generate_random_base32_voucher_code, CPL-319) -- only reachable via a
-- nested SECURITY DEFINER call from the functions above.
