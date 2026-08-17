-- Phase 8 capability CPL-318 (CG-S13-CPL-020, Prompt 318, "Points Ledger") --
-- the THIRD Loyalty-domain capability in this repository (ADR-0024 Part D),
-- following CPL-316 (Loyalty Program and Earning,
-- 20260801180000_create_customer_portal_loyalty_program_earning.sql) and
-- CPL-317 (Membership Tier,
-- 20260801190000_create_customer_portal_loyalty_membership_tier.sql), both
-- read in full before writing this file. Also mandatory-read before writing
-- this file: docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-
-- pattern.md Part D; supabase/migrations/20260730190000_create_advanced_tms_
-- inventory_ledger.sql (app.post_inventory_movement's ACTUAL body -- the
-- SELECT...FOR UPDATE read-modify-write pattern, never INSERT...ON CONFLICT
-- DO UPDATE); supabase/migrations/20260730740000_create_procurement_vendor_
-- performance.sql's app.request_vendor_kpi_manual_adjustment/app.decide_
-- vendor_kpi_manual_adjustment (the maker-checker precedent); docs/
-- architecture/06_RLS_RBAC_WORKSTREAM.md §8 (RPD-022).
--
-- This migration owns: app.loyalty_point_lots (one lot per points-type
-- earning event, tracking remaining balance for FIFO-by-expiry
-- consumption), app.loyalty_point_ledger_entries (append-only, mirrors
-- app.loyalty_earning_events'/app.inventory_movements' own shape exactly),
-- app.loyalty_point_balances (the ONE derived-balance table, mirrors
-- app.inventory_balances' own generated-`available`-column + record_version
-- shape exactly), and app.loyalty_point_adjustment_requests (a maker-checker
-- pair DIRECTLY mirroring PRC-264's app.vendor_kpi_manual_adjustments).
-- Reads (never writes) CPL-316's app.loyalty_accounts/app.loyalty_earning_
-- events -- grep-confirmed zero insert/update/delete against either
-- anywhere in this file. Does NOT read CPL-317's tier tables (app.loyalty_
-- tier_definitions/app.loyalty_account_tier_movements) -- this prompt's own
-- literal business rules never mention tier-scoped point multipliers;
-- CPL-317's own "recommended next task" text floated that as a maybe, this
-- checkpoint confirms it is not actually required and does not couple to it
-- (per this task's own explicit instruction: "do not couple your own tables
-- to it structurally unless the source prompt genuinely requires it").
--
-- ===========================================================================
-- Design decisions (disclosed, not re-derived)
-- ===========================================================================
--
-- 1. **Signed-amount convention on app.loyalty_point_ledger_entries.amount**:
--    positive amount = increases available balance (earn; a reversal that
--    credits back a previously-consumed lot); negative amount = decreases
--    available balance (redemption; expiry; a reversal that claws back a
--    previously-earned lot; a negative adjustment). app.loyalty_point_
--    balances.total_earned is the running sum of every POSITIVE amount ever
--    posted; total_consumed is the running sum of the ABSOLUTE VALUE of
--    every NEGATIVE amount ever posted; available (generated) = total_earned
--    - total_consumed always equals the arithmetic sum of every posted
--    amount -- a clean, auditable reconciliation invariant. This is my own
--    design call (the source prompt's own literal column list does not fix
--    a sign convention), disclosed rather than silently assumed, and it is
--    what lets ONE posting primitive serve earn/reversal/expiry/adjustment/
--    redemption uniformly (mirrors app.inventory_movement_lines.signed_
--    quantity's own uniform-sign-convention precedent).
-- 2. **The ledger INSERT happens BEFORE the balance/lot mutation inside
--    app.post_loyalty_point_ledger_entry** -- the opposite order from a
--    naive reading of app.post_inventory_movement (which inserts its
--    header first too, for the identical reason, but does not wrap that
--    insert in its own exception handler). This checkpoint's own posting
--    primitive DOES wrap the ledger insert in a real `exception when
--    unique_violation` handler (mandatory pattern), so ordering matters for
--    a subtle, real correctness reason worked out explicitly during this
--    checkpoint's own design pass: if the balance/lot mutation ran BEFORE
--    the ledger insert, a genuine concurrent duplicate-idempotency-key race
--    would let the LOSING transaction's own balance/lot mutation commit
--    (since only the insert's own exception is caught, not anything run
--    before it) while its ledger insert is gracefully swallowed and the
--    WINNER's row returned instead -- silently double-counting the balance
--    for one logical event backed by only one ledger row. Inserting the
--    ledger row FIRST means a losing racer's exception fires before any
--    balance/lot mutation has happened in that losing transaction, so
--    nothing needs rolling back and nothing is double-counted. (A separate,
--    correctly-scoped exception handler, mirroring app.post_inventory_
--    movement's own balance-row first-insert retry loop, still protects the
--    balance row's OWN first-insert-per-account race.)
-- 3. **Negative-balance prevention is BOTH a procedural guard (the
--    authoritative check, evaluated before any write, mirrors app.post_
--    inventory_movement's own "insufficient_stock" precedent exactly) AND a
--    real table CHECK constraint on app.loyalty_point_balances
--    (`lpb_available_nonnegative_check`, total_earned >= total_consumed) as
--    a defense-in-depth backstop that should never actually fire for a
--    legitimate call** -- my own disclosed choice between the two options
--    this task's own instruction offered ("a CHECK constraint... or a
--    procedural guard, your call, disclose it"). Proven live in this
--    checkpoint's own db-test with both a real attempted over-consumption
--    (single-session) and a real two-process concurrent-race attempt
--    (reusing scripts/db-tests/wms-picking-concurrency-helper.sh, ATW-017's
--    own real two-psql-process concurrency proof helper -- a generic tool
--    despite its filename, not WMS-specific).
-- 4. **Lot expiry window is a caller-supplied, bounded parameter
--    (`p_expiry_days`, 1-3650, default 365) on `app.post_loyalty_points_
--    earned`, not a persisted per-(tenant,program) config table.** A real,
--    working, bounded policy -- not a magic hardcoded constant, not an
--    unbounded free-form input -- but a lighter-weight, disclosed scope
--    decision than CPL-317's own persisted `review_period_days` column
--    precedent, since a persisted config table is genuinely more schema
--    surface than this checkpoint's own file/migration budget comfortably
--    affords alongside the maker-checker pair and the FIFO consumption
--    primitive. Disclosed as `ISS-2026-128` (see docs/runtime/KNOWN_
--    ISSUES.md), mirroring `ISS-2026-126`/`ISS-2026-127`'s own established
--    "real primitive shipped, one specific policy knob deliberately kept
--    lightweight" disclosure shape.
-- 5. **`config_version` (literal column from this prompt's own §13 database-
--    impact text: "config/source versions") is a forward-compatible
--    posting-LOGIC-version marker, constant `1` in this checkpoint** (a
--    real parameter on app.post_loyalty_point_ledger_entry, `p_config_
--    version integer default 1`, not merely hardcoded inside the function
--    body) since no persisted, versionable point-earning configuration
--    exists yet (design decision 4) -- mirrors CPL-316's own rule_version_id
--    freezing precedent in spirit: a future checkpoint that adds real
--    configurable posting behavior can pass a real value through this same
--    parameter without a signature change, and every historical row keeps
--    whichever version it was posted under forever.
-- 6. **One lot per points-type ORIGINAL earning event only** (`unique
--    (tenant_id, source_earning_event_id)` on app.loyalty_point_lots) --
--    `app.post_loyalty_points_earned` rejects a reversal-shaped CPL-316
--    earning event (`corrects_event_id is not null` or `source_type =
--    'reversal'`) with a clear `earning_event_is_a_reversal` error pointing
--    the caller at `app.reverse_loyalty_points_earned` instead, which reads
--    the ORIGINAL event via the reversal event's own `corrects_event_id`,
--    finds that original's own lot, and posts a `reversal` ledger entry
--    capped at `least(lot.remaining_amount, abs(reversal_event.amount))` --
--    some of the lot may already have been legitimately spent/expired
--    before the underlying earning event was reversed at the CPL-316 level;
--    this checkpoint claws back only what the lot still actually holds,
--    disclosed explicitly rather than silently over- or under-reversing.
--    CPL-316's own `app.reverse_loyalty_earning_event` already guarantees
--    at most one reversal per original event, so this checkpoint never has
--    to reconcile multiple reversals against the same lot.
-- 7. **`app.consume_loyalty_points_fifo` is a REAL, complete, working FIFO-
--    by-expiry multi-lot consumption primitive** (posts one `redemption`
--    ledger entry per lot touched, oldest-expiring lot first, via app.post_
--    loyalty_point_ledger_entry) -- not merely a documented policy claim.
--    Serialized per loyalty_account_id via `pg_advisory_xact_lock
--    (hashtextextended(p_loyalty_account_id::text, 4))`, mirroring CPL-317's
--    own established `hashtextextended(id::text, salt)` per-entity advisory-
--    lock precedent (design decision 9 there, salt 3; salt 4 here to stay
--    distinct within the same hash domain) -- the whole-redemption
--    idempotency check (by `(source_type, source_id)`, since a single
--    logical redemption fans out into N per-lot ledger rows, each with its
--    own deterministically-derived idempotency key) is only safe against a
--    genuine concurrent double-submit because of this lock. No reward/
--    voucher catalog exists yet in this repository to trigger a real
--    customer-initiated redemption from (that is CPL-319+'s own scope, per
--    CPL-316's own established "discount/voucher issuance is CPL-319's own
--    scope" precedent) -- this checkpoint ships the real ledger-side
--    primitive a future redemption capability will call, exactly mirroring
--    `ISS-2026-126`/`ISS-2026-127`'s own "real primitive exists; nothing
--    calls it automatically/from an end-user surface yet" disclosure shape,
--    disclosed here as `ISS-2026-128` too. Used directly by this
--    checkpoint's own db-test to prove FIFO-by-expiry ordering live.
-- 8. **app.expire_loyalty_point_lots scans (tenant-wide) lots past
--    expires_at with remaining_amount > 0 and status = 'active', posting an
--    `expiry` entry per lot via the posting primitive** -- idempotent per
--    lot by construction (a lot already fully expired no longer matches the
--    scan's own WHERE clause on re-run, a safe no-op). Each lot's own
--    posting call is independently fault-isolated (a nested `begin...
--    exception when others then continue`) so one lot racing against a
--    concurrent expire run or a concurrent consumption does not abort an
--    otherwise-successful batch for every OTHER due lot -- a caller can
--    always safely re-run the whole scan and it will correctly pick up
--    whatever, if anything, is still genuinely due.
-- 9. **app.request_loyalty_point_adjustment/app.decide_loyalty_point_
--    adjustment DIRECTLY mirror PRC-264's app.request_vendor_kpi_manual_
--    adjustment/app.decide_vendor_kpi_manual_adjustment**: mandatory non-
--    empty reason, self-approval blocked (`requested_by_auth_user_id =
--    deciding actor` raises `self_approval_not_allowed`), record_version
--    optimistic concurrency, a partial unique index enforcing at-most-one-
--    pending-adjustment-per-account (`lpar_pending_unique`), both write
--    app.capture_audit_event with a REAL before/after (an improvement over
--    PRC-264's own `decide_vendor_kpi_manual_adjustment`, which uses a
--    `null` before value on its own decide-action audit entry -- this
--    checkpoint captures the request's own original status/the account's
--    own current available balance as genuine before-state). Approval posts
--    a real `adjustment`-typed app.loyalty_point_ledger_entries entry via
--    the posting primitive (design decision 1's negative/positive-amount
--    convention applies identically). **One deliberate improvement beyond
--    PRC-264's own decide-function signature shape**: `app.decide_loyalty_
--    point_adjustment` takes `p_tenant_id` as an explicit first parameter
--    and checks `LYL:Configure` authority BEFORE fetching the target row
--    (C-05 -- this task's own mandatory pattern), rather than PRC-264's own
--    fetch-then-check shape (which the vendor precedent uses only because
--    its own function has no tenant-scoping parameter to check authority
--    against before reading the row) -- mirrors CPL-316/317's own already-
--    established, stricter design decision 3 precedent, applied here to the
--    one function this task explicitly asked to "directly mirror" an OLDER,
--    less strict precedent. A cross-tenant id guess and a genuinely
--    nonexistent id both resolve to the identical `loyalty_point_
--    adjustment_request_not_found` error post-authority-check.
-- 10. **Every actor-taking function in this migration calls `app.assert_
--    actor_is_session_identity` as its own literal FIRST statement**; every
--    staff mutate/get-by-id RPC checks `LYL:*` authority BEFORE fetching its
--    target row (mirrors CPL-316/317's own design decision 3 exactly).
-- 11. **LYL permission mapping, reused from CPL-316/317 unchanged** (LYL has
--    no `Approve` action -- confirmed again this checkpoint, `20260716103445
--    _create_roles_permissions.sql:71-72`). Ordinary ledger posting (the
--    core primitive, the earn/expire/FIFO-consume wrappers, the maker's own
--    `request_loyalty_point_adjustment`) -> `LYL:Edit`. The two governance-
--    grade actions in this capability -- reversing an already-posted lot's
--    worth of points (`reverse_loyalty_points_earned`) and DECIDING a point
--    adjustment (`decide_loyalty_point_adjustment`, the checker) -- both map
--    to the elevated `LYL:Configure`, mirroring CPL-316's own `publish_
--    loyalty_program_rule_version`/`reverse_loyalty_earning_event` mapping
--    exactly. Staff reads -> `LYL:View`. Customer-facing reads -> scoped via
--    `app.resolve_customer_account_scope` (CPL-300), no staff RBAC check.
-- 12. **`clock_timestamp()`, never `now()`, for every timestamptz column
--    whose ordering matters for "most recent X" resolution or whose table
--    could plausibly receive more than one row/update within the same
--    transaction** -- the exact defect class self-found and fixed at
--    CPL-315, applied proactively here (as CPL-317 itself already did)
--    across `loyalty_point_lots.created_at/updated_at`, `loyalty_point_
--    ledger_entries.created_at` (an append-only table that can genuinely
--    receive several rows in one transaction, e.g. every per-lot row a
--    single `app.consume_loyalty_points_fifo` call posts), `loyalty_point_
--    balances.updated_at`, `loyalty_point_adjustment_requests.created_at/
--    updated_at`/`requested_at`/`decided_at`, and this migration's own two
--    touch-row trigger functions. The one deliberate, disclosed exception:
--    `app.expire_loyalty_point_lots`'s own scan predicate (`expires_at <=
--    clock_timestamp()`) intentionally uses a single, transaction-consistent
--    `clock_timestamp()` read per invocation for the comparison itself (not
--    `now()`, which would also be transaction-consistent but is the
--    established convention this migration otherwise deliberately departs
--    from throughout) -- semantically correct either way for a scan
--    predicate; `clock_timestamp()` is used uniformly for consistency with
--    every other timestamp in this file rather than mixing conventions.
-- 13. **RLS: `authenticated` holds ZERO direct grant** on any of the 4 new
--    tables, mirroring CPL-316/317 exactly -- the RPCs below are the only
--    sanctioned access path, for both staff and customer callers.
--    `docs/architecture/06_RLS_RBAC_WORKSTREAM.md` §4/§8 (RPD-022) already
--    explicitly names `point_ledger`/`cashback_ledger` inside the
--    repository's `append_only_ledger` policy family, and requires a
--    distinct Supreme-Admin-exception RLS policy granting `UPDATE`/`DELETE`
--    on every such table (the accountability mechanism is the disclosed,
--    never-tamper-proof audit trail, §8's own "residual risk... RISK-004,
--    never closed" language -- that phrase describes the audit-trail's OWN
--    residual alterability, not an option to skip the override mechanism
--    itself, which §13 separately calls a Phase-8 release-blocker gate;
--    this migration's original text conflated the two, corrected at this
--    batch's own Tier C review). `app.loyalty_point_ledger_entries` is this
--    checkpoint's own concrete realization of the disclosed `point_ledger`
--    family member. Consistent with -- not a new gap beyond -- CPL-316's/
--    CPL-317's own identical choice for their own sibling ledger tables
--    (`loyalty_earning_events`/`loyalty_account_tier_movements`), and the
--    identical, already-accepted choice `app.inventory_movements`
--    (`supabase/migrations/20260730190000_create_advanced_tms_inventory_
--    ledger.sql`, this batch's own required-read precedent file) already
--    makes for its own append-only ledger, this checkpoint does not
--    implement a concrete Supreme-Admin-override mechanism (the kind
--    `supabase/migrations/20260729180000_create_finance_posted_journal_
--    integrity.sql`'s own FIN-204 trigger-based `app.is_supreme_admin`-
--    gated UPDATE/DELETE exception implements for Finance's posted
--    journals) -- `service_role` itself holds no UPDATE/DELETE grant on
--    `app.loyalty_point_ledger_entries` either (select+insert only,
--    mirroring CPL-316's own identical choice for `app.loyalty_earning_
--    events`), so today literally no ordinary application-level role can
--    mutate a posted row. A future, dedicated cross-cutting task may add a
--    concrete Supreme-Admin-exception trigger across every Loyalty ledger
--    table at once (mirroring FIN-204), rather than each Loyalty capability
--    prompt inventing its own ad hoc copy. Disclosed at this batch's own
--    Tier C review as `ISS-2026-130` (`docs/runtime/KNOWN_ISSUES.md`),
--    covering all four Loyalty ledger tables at once (including CPL-319's
--    `loyalty_benefit_entitlement_events`, which had no RPD-022 citation of
--    its own at all before this same review).
-- 14. Per `ERR-2026-004`: this migration carries its own explicit `revoke
--    execute on all functions in schema app from public` statement before
--    its final grants.
-- 15. **Tier C review fix (Critical): a positive manual adjustment's own
--    LOT-LESS credit is now genuinely redeemable, closing a real financial-
--    ledger balance/redeemability defect.** `app.decide_loyalty_point_
--    adjustment` posts a positive `adjustment` entry with `p_lot_id = null`
--    (design decision 6 -- `app.loyalty_point_lots.source_earning_event_id`
--    is `NOT NULL`, and a manual adjustment has no backing earning event,
--    so no lot can be created for it). That correctly increases `app.
--    loyalty_point_balances.total_earned`/`available` -- but before this
--    fix, `app.consume_loyalty_points_fifo`, this repository's own ONLY
--    consumption primitive (today and for any future redemption UI,
--    ISS-2026-128), iterated exclusively over `app.loyalty_point_lots` and
--    raised `insufficient_points_balance` unconditionally the moment active
--    lots ran out -- so a staff-approved positive-adjustment credit was
--    structurally unspendable, a real accounting break between the derived
--    aggregate balance and the only mechanism that can realize it. Fixed IN
--    `app.consume_loyalty_points_fifo` itself (see its own updated comment
--    below), not by giving lots a fictitious backing earning event or by
--    weakening design decision 6's own real constraint: once every active
--    lot is exhausted, the function attempts one final lot-less consuming
--    entry for whatever remains, with `app.post_loyalty_point_ledger_
--    entry`'s own aggregate negative-balance guard (design decision 3, the
--    AUTHORITATIVE check) as the sole arbiter of whether that is genuinely
--    available. Live-reproduced and proven fixed in this checkpoint's own
--    db-test.
-- 16. **Tier C review fix (Low): the `LYL:Configure`-gated `app.decide_
--    loyalty_point_adjustment`/`app.reverse_loyalty_points_earned` now
--    explicitly, visibly require `LYL:Edit` too, for the specific branch
--    that actually delegates to `app.post_loyalty_point_ledger_entry`.**
--    Both functions delegate their real ledger mutation to that shared
--    primitive, which independently re-checks `LYL:Edit` as its own first
--    authority gate -- previously undisclosed, and untested by either
--    manager fixture in this checkpoint's own db-test (both hold the full
--    `View`/`Create`/`Edit`/`Configure` bundle). A `Configure`-only role is
--    a plausible configuration under this repository's dynamic, tenant-
--    configured RBAC model -- such an actor previously reached a confusing
--    failure deep inside a nested call, after already doing row-fetch/lock/
--    validation work, rather than a clear, immediate, self-referential one.
--    Scoped precisely to the delegating branch in each function (the
--    `if p_decision = 'approved' then` branch of `decide_loyalty_point_
--    adjustment`; after the idempotent short-circuit in `reverse_loyalty_
--    points_earned`) so no other behavior changes -- a `Configure`-only
--    actor can still REJECT an adjustment request, and an idempotent replay
--    of an already-reversed event still succeeds, exactly as before.

-- ===========================================================================
-- 1. app.loyalty_point_lots -- one lot per points-type ORIGINAL earning
-- event (design decision 6), tracking remaining balance for FIFO-by-expiry
-- consumption (design decision 7).
-- ===========================================================================

create table app.loyalty_point_lots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  loyalty_account_id uuid not null references app.loyalty_accounts (id),
  source_earning_event_id uuid not null references app.loyalty_earning_events (id),
  original_amount numeric not null,
  remaining_amount numeric not null,
  expires_at timestamptz not null,
  status text not null default 'active',
  record_version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint lpl_status_check check (status in ('active', 'exhausted', 'expired')),
  constraint lpl_original_amount_check check (original_amount > 0),
  constraint lpl_remaining_amount_check check (remaining_amount >= 0 and remaining_amount <= original_amount),
  constraint lpl_tenant_source_earning_event_unique unique (tenant_id, source_earning_event_id)
);

comment on table app.loyalty_point_lots is
  'CPL-318: one lot per points-type ORIGINAL app.loyalty_earning_events row (never a reversal row -- design decision 6). remaining_amount is mutated exclusively by app.post_loyalty_point_ledger_entry, never any other function or direct write. FIFO-by-expiry consumption reads active lots ordered by expires_at asc (app.consume_loyalty_points_fifo, app.expire_loyalty_point_lots).';

create index lpl_tenant_account_status_expiry_idx on app.loyalty_point_lots (tenant_id, loyalty_account_id, status, expires_at);
create index lpl_tenant_expiry_idx on app.loyalty_point_lots (tenant_id, expires_at) where status = 'active';

-- ===========================================================================
-- 2. app.loyalty_point_ledger_entries -- APPEND-ONLY (design decision 1's
-- signed-amount convention). Mirrors app.loyalty_earning_events'/
-- app.inventory_movements' own append-only shape exactly.
-- ===========================================================================

create table app.loyalty_point_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  loyalty_account_id uuid not null references app.loyalty_accounts (id),
  event_type text not null,
  amount numeric not null,
  lot_id uuid references app.loyalty_point_lots (id),
  source_type text not null,
  source_id uuid,
  idempotency_key text not null,
  corrects_entry_id uuid references app.loyalty_point_ledger_entries (id),
  reason text,
  config_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default clock_timestamp(),
  constraint lple_event_type_check check (event_type in ('earn', 'reversal', 'expiry', 'adjustment', 'redemption')),
  constraint lple_amount_check check (amount <> 0),
  constraint lple_reason_check check (event_type <> 'adjustment' or (reason is not null and length(trim(reason)) > 0)),
  constraint lple_source_type_check check (source_type in ('loyalty_earning_event', 'point_lot_expiry', 'manual_adjustment', 'redemption', 'reversal')),
  constraint lple_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.loyalty_point_ledger_entries is
  'CPL-318: append-only. No UPDATE/DELETE grant to any role anywhere in this migration (design decision 13, not even service_role) -- a correction is always a NEW, linked row (corrects_entry_id), mirroring app.inventory_movements.corrects_movement_id / app.loyalty_earning_events.corrects_event_id exactly. amount sign convention: positive increases available balance, negative decreases it (design decision 1) -- total_earned/total_consumed on app.loyalty_point_balances are derived exclusively from this table via app.post_loyalty_point_ledger_entry.';

create index lple_tenant_account_created_idx on app.loyalty_point_ledger_entries (tenant_id, loyalty_account_id, created_at desc);
create index lple_tenant_created_id_idx on app.loyalty_point_ledger_entries (tenant_id, created_at desc, id desc);
create index lple_lot_idx on app.loyalty_point_ledger_entries (lot_id);
create index lple_corrects_entry_idx on app.loyalty_point_ledger_entries (corrects_entry_id);
create index lple_source_idx on app.loyalty_point_ledger_entries (source_type, source_id);

-- ===========================================================================
-- 3. app.loyalty_point_balances -- the ONE derived-balance table (design
-- decision 1). Mirrors app.inventory_balances' own generated `available`
-- column + record_version shape exactly.
-- ===========================================================================

create table app.loyalty_point_balances (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  loyalty_account_id uuid not null references app.loyalty_accounts (id),
  total_earned numeric not null default 0,
  total_consumed numeric not null default 0,
  available numeric generated always as (total_earned - total_consumed) stored,
  record_version integer not null default 1,
  updated_at timestamptz not null default clock_timestamp(),
  constraint lpb_total_earned_check check (total_earned >= 0),
  constraint lpb_total_consumed_check check (total_consumed >= 0),
  constraint lpb_available_nonnegative_check check (total_earned >= total_consumed),
  constraint lpb_tenant_account_unique unique (tenant_id, loyalty_account_id)
);

comment on table app.loyalty_point_balances is
  'CPL-318: one row per loyalty_account_id, created lazily on first posting. available is a real STORED generated column (total_earned - total_consumed), never computed ad hoc by a caller (mirrors app.inventory_balances.available exactly). Written exclusively by app.post_loyalty_point_ledger_entry via a race-safe SELECT...FOR UPDATE read-modify-write -- never INSERT...ON CONFLICT DO UPDATE (design decision 2/3) -- no other function or direct table write ever changes it. lpb_available_nonnegative_check is a defense-in-depth backstop (design decision 3); the procedural guard inside app.post_loyalty_point_ledger_entry is the authoritative, always-checked-first negative-balance prevention.';

create index lpb_tenant_updated_id_idx on app.loyalty_point_balances (tenant_id, updated_at desc, id desc);

-- ===========================================================================
-- 4. app.loyalty_point_adjustment_requests -- maker-checker pair, DIRECTLY
-- mirroring PRC-264's app.vendor_kpi_manual_adjustments (design decision 9).
-- ===========================================================================

create table app.loyalty_point_adjustment_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  loyalty_account_id uuid not null references app.loyalty_accounts (id),
  adjustment_amount numeric not null,
  reason text not null,
  requested_by_auth_user_id uuid not null,
  requested_by text,
  requested_at timestamptz not null default clock_timestamp(),
  status text not null default 'pending_approval',
  decided_by_auth_user_id uuid,
  decided_by text,
  decided_at timestamptz,
  decision_notes text,
  ledger_entry_id uuid references app.loyalty_point_ledger_entries (id),
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint lpar_reason_check check (length(trim(reason)) > 0),
  constraint lpar_amount_check check (adjustment_amount <> 0),
  constraint lpar_status_check check (status in ('pending_approval', 'approved', 'rejected')),
  constraint lpar_decision_shape_check check ((status = 'pending_approval') = (decided_by_auth_user_id is null and decided_at is null)),
  constraint lpar_decision_notes_check check (status = 'pending_approval' or (decision_notes is not null and length(trim(decision_notes)) > 0)),
  constraint lpar_ledger_entry_shape_check check ((status = 'approved') = (ledger_entry_id is not null))
);

comment on table app.loyalty_point_adjustment_requests is
  'CPL-318: reason-required, maker-checker-governed manual point adjustment (mirrors app.vendor_kpi_manual_adjustments, PRC-264, exactly). Self-approval blocked in app.decide_loyalty_point_adjustment. At most one PENDING adjustment per account at a time (lpar_pending_unique). Approval posts a real app.loyalty_point_ledger_entries adjustment entry via app.post_loyalty_point_ledger_entry -- this table itself never mutates a balance/lot directly.';

create unique index lpar_pending_unique on app.loyalty_point_adjustment_requests (loyalty_account_id) where status = 'pending_approval';
create unique index lpar_idempotency_key_unique on app.loyalty_point_adjustment_requests (tenant_id, idempotency_key) where idempotency_key is not null;
create index lpar_tenant_updated_id_idx on app.loyalty_point_adjustment_requests (tenant_id, updated_at desc, id desc);
create index lpar_account_idx on app.loyalty_point_adjustment_requests (loyalty_account_id);

create function app.touch_loyalty_point_adjustment_request_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_point_adjustment_requests_touch_row
  before update on app.loyalty_point_adjustment_requests
  for each row
  execute function app.touch_loyalty_point_adjustment_request_row();

-- ===========================================================================
-- 5. app.post_loyalty_point_ledger_entry -- the single posting primitive
-- every earn/reversal/expiry/adjustment/redemption call goes through
-- (mirrors app.post_inventory_movement being the single choke point).
-- ===========================================================================

create function app.post_loyalty_point_ledger_entry(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_event_type text,
  p_amount numeric,
  p_lot_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_idempotency_key text,
  p_reason text,
  p_corrects_entry_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_config_version integer default 1
)
returns app.loyalty_point_ledger_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.loyalty_accounts;
  v_lot app.loyalty_point_lots;
  v_existing app.loyalty_point_ledger_entries;
  v_entry app.loyalty_point_ledger_entries;
  v_balance_id uuid;
  v_current_earned numeric;
  v_current_consumed numeric;
  v_new_earned numeric;
  v_new_consumed numeric;
  v_new_lot_remaining numeric;
  v_new_lot_status text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_event_type not in ('earn', 'reversal', 'expiry', 'adjustment', 'redemption') then
    raise exception 'invalid_event_type: % is not a recognized point ledger event type', p_event_type using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount = 0 then
    raise exception 'invalid_amount: amount must be non-zero' using errcode = 'check_violation';
  end if;
  if p_event_type = 'adjustment' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'invalid_reason: a non-empty reason is required for an adjustment entry' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;

  -- Idempotent short-circuit AFTER the authority check (mandatory pattern).
  select * into v_existing from app.loyalty_point_ledger_entries where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_account_not_found: % is not a loyalty account of tenant %', p_loyalty_account_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  -- Lock the target lot (if any) BEFORE the ledger insert -- a concurrent
  -- duplicate call targeting the SAME lot blocks here until this
  -- transaction ends, then re-evaluates against fresh, committed data
  -- (design decision 2).
  if p_lot_id is not null then
    select * into v_lot from app.loyalty_point_lots where id = p_lot_id and tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id for update;
    if not found then
      raise exception 'loyalty_point_lot_not_found: % is not a lot of loyalty account %', p_lot_id, p_loyalty_account_id using errcode = 'no_data_found';
    end if;
  end if;

  -- The ledger INSERT establishes the idempotency claim FIRST, before any
  -- balance/lot mutation (design decision 2 -- the specific double-counting
  -- race this ordering exists to prevent, worked out explicitly during this
  -- checkpoint's own design pass, is documented in full at the top of this
  -- file).
  begin
    insert into app.loyalty_point_ledger_entries (
      tenant_id, loyalty_account_id, event_type, amount, lot_id, source_type, source_id,
      idempotency_key, corrects_entry_id, reason, config_version, created_by
    ) values (
      p_tenant_id, p_loyalty_account_id, p_event_type, p_amount, p_lot_id, p_source_type, p_source_id,
      p_idempotency_key, p_corrects_entry_id, p_reason, coalesce(p_config_version, 1), p_actor_label
    )
    returning * into v_entry;
  exception
    when unique_violation then
      select * into v_entry from app.loyalty_point_ledger_entries where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      return v_entry;
  end;

  -- Balance read-modify-write: race-safe SELECT...FOR UPDATE loop, never
  -- INSERT...ON CONFLICT DO UPDATE (mandatory pattern; mirrors app.post_
  -- inventory_movement's own design note 1 exactly). Negative-balance
  -- prevention (design decision 3) is evaluated and enforced HERE, before
  -- any write, for every event type uniformly (design decision 1's signed-
  -- amount convention).
  loop
    select id, total_earned, total_consumed into v_balance_id, v_current_earned, v_current_consumed
      from app.loyalty_point_balances
      where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id
      for update;

    if found then
      if p_amount > 0 then
        v_new_earned := v_current_earned + p_amount;
        v_new_consumed := v_current_consumed;
      else
        v_new_earned := v_current_earned;
        v_new_consumed := v_current_consumed + abs(p_amount);
      end if;

      if v_new_earned - v_new_consumed < 0 then
        raise exception 'insufficient_points_balance: % available but % requested', (v_current_earned - v_current_consumed), abs(p_amount)
          using errcode = 'check_violation';
      end if;

      update app.loyalty_point_balances
        set total_earned = v_new_earned, total_consumed = v_new_consumed, updated_at = clock_timestamp(), record_version = record_version + 1
        where id = v_balance_id;
      exit;
    else
      if p_amount > 0 then
        v_new_earned := p_amount;
        v_new_consumed := 0;
      else
        v_new_earned := 0;
        v_new_consumed := abs(p_amount);
      end if;

      if v_new_earned - v_new_consumed < 0 then
        raise exception 'insufficient_points_balance: 0 available but % requested', abs(p_amount) using errcode = 'check_violation';
      end if;

      begin
        insert into app.loyalty_point_balances (tenant_id, loyalty_account_id, total_earned, total_consumed)
        values (p_tenant_id, p_loyalty_account_id, v_new_earned, v_new_consumed);
        exit;
      exception
        when unique_violation then
          -- Lost a concurrent first-insert race for this account's balance
          -- row; loop back and take the update branch (mirrors app.post_
          -- inventory_movement's own identical retry-on-unique_violation
          -- loop, ATW-015).
          continue;
      end;
    end if;
  end loop;

  -- Lot remaining_amount touch (only when a specific lot is targeted and
  -- this is NOT the lot's own originating 'earn' entry -- an 'earn' entry's
  -- lot is already created at full remaining_amount = original_amount by
  -- the caller BEFORE this primitive is invoked; see app.post_loyalty_
  -- points_earned).
  if p_lot_id is not null and p_event_type <> 'earn' then
    v_new_lot_remaining := v_lot.remaining_amount + p_amount;
    if v_new_lot_remaining < 0 or v_new_lot_remaining > v_lot.original_amount then
      raise exception 'insufficient_lot_remaining: lot % has % remaining, cannot apply %', p_lot_id, v_lot.remaining_amount, p_amount
        using errcode = 'check_violation';
    end if;
    v_new_lot_status := case
      when v_new_lot_remaining = 0 and p_event_type = 'expiry' then 'expired'
      when v_new_lot_remaining = 0 then 'exhausted'
      else 'active'
    end;
    update app.loyalty_point_lots
      set remaining_amount = v_new_lot_remaining, status = v_new_lot_status, updated_at = clock_timestamp(), record_version = record_version + 1
      where id = p_lot_id;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'post_loyalty_point_ledger_entry',
    'app.loyalty_point_ledger_entries', v_entry.id, 'success', p_reason, null,
    jsonb_build_object('event_type', p_event_type, 'amount', p_amount, 'loyalty_account_id', p_loyalty_account_id, 'lot_id', p_lot_id, 'source_type', p_source_type)
  );

  return v_entry;
end;
$$;

comment on function app.post_loyalty_point_ledger_entry is
  'CPL-318: idempotent on (tenant_id, idempotency_key) -- a retry returns the identical row, never re-posts or double-counts. The ledger INSERT happens BEFORE any balance/lot mutation (design decision 2) -- a losing concurrent racer''s exception fires before it has mutated anything. Negative-balance prevention (design decision 3) is a procedural guard evaluated before every write, backed by a real CHECK constraint as a defense-in-depth backstop that should never fire for a legitimate call.';

-- ===========================================================================
-- 6. app.post_loyalty_points_earned -- LYL:Edit. Creates the lot + posts
-- the 'earn' entry for one points-type ORIGINAL app.loyalty_earning_events
-- row (design decision 6).
-- ===========================================================================

create function app.post_loyalty_points_earned(
  p_tenant_id uuid,
  p_earning_event_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expiry_days integer default 365
)
returns app.loyalty_point_ledger_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_expiry_days integer;
  v_idem text;
  v_existing app.loyalty_point_ledger_entries;
  v_event app.loyalty_earning_events;
  v_lot app.loyalty_point_lots;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_expiry_days := coalesce(p_expiry_days, 365);
  if v_expiry_days < 1 or v_expiry_days > 3650 then
    raise exception 'invalid_expiry_days: % must be between 1 and 3650', v_expiry_days using errcode = 'check_violation';
  end if;

  v_idem := 'earning-event:' || p_earning_event_id::text;

  loop
    select * into v_existing from app.loyalty_point_ledger_entries where tenant_id = p_tenant_id and idempotency_key = v_idem;
    if found then
      return v_existing;
    end if;

    select * into v_event from app.loyalty_earning_events where id = p_earning_event_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'loyalty_earning_event_not_found: % is not an earning event of tenant %', p_earning_event_id, p_tenant_id using errcode = 'no_data_found';
    end if;
    if v_event.reward_type <> 'points' then
      raise exception 'not_a_points_earning_event: earning event % has reward_type %, not points', p_earning_event_id, v_event.reward_type using errcode = 'check_violation';
    end if;
    if v_event.corrects_event_id is not null or v_event.source_type = 'reversal' then
      raise exception 'earning_event_is_a_reversal: % is a reversal earning event -- call app.reverse_loyalty_points_earned instead', p_earning_event_id using errcode = 'check_violation';
    end if;
    if v_event.amount <= 0 then
      raise exception 'invalid_earning_event_amount: earning event % has non-positive amount %', p_earning_event_id, v_event.amount using errcode = 'check_violation';
    end if;

    begin
      insert into app.loyalty_point_lots (tenant_id, loyalty_account_id, source_earning_event_id, original_amount, remaining_amount, expires_at, status)
      values (p_tenant_id, v_event.loyalty_account_id, p_earning_event_id, v_event.amount, v_event.amount, clock_timestamp() + make_interval(days => v_expiry_days), 'active')
      returning * into v_lot;
      exit;
    exception
      when unique_violation then
        -- Lost a concurrent lot-creation race for the SAME earning event
        -- (lpl_tenant_source_earning_event_unique); loop back -- the
        -- idempotency check above will see the winner's committed ledger
        -- row once it exists (design decision 2's own PostgreSQL unique-
        -- constraint blocking-then-resolving behavior).
        continue;
    end;
  end loop;

  return app.post_loyalty_point_ledger_entry(
    p_tenant_id, v_event.loyalty_account_id, 'earn', v_event.amount, v_lot.id,
    'loyalty_earning_event', p_earning_event_id, v_idem, null, null,
    p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.post_loyalty_points_earned is
  'CPL-318: idempotent on (tenant_id, ''earning-event:'' || earning_event_id) -- calling this twice for the same earning event is a safe no-op, never a duplicate lot or ledger entry. Rejects a non-points, a reversal-shaped, or a non-positive-amount earning event. p_expiry_days (1-3650, default 365) is a real, bounded, disclosed policy knob (design decision 4, ISS-2026-128) -- not a persisted per-program config.';

-- ===========================================================================
-- 7. app.reverse_loyalty_points_earned -- LYL:Configure (governance-grade,
-- design decision 11). Consumes a CPL-316 reversal earning event and posts
-- a linked 'reversal' entry against the ORIGINAL earning event's own lot.
-- ===========================================================================

create function app.reverse_loyalty_points_earned(
  p_tenant_id uuid,
  p_reversal_earning_event_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_point_ledger_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_idem text;
  v_existing app.loyalty_point_ledger_entries;
  v_reversal_event app.loyalty_earning_events;
  v_lot app.loyalty_point_lots;
  v_earn_entry app.loyalty_point_ledger_entries;
  v_applied_amount numeric;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_idem := 'earning-event-reversal:' || p_reversal_earning_event_id::text;

  select * into v_existing from app.loyalty_point_ledger_entries where tenant_id = p_tenant_id and idempotency_key = v_idem;
  if found then
    return v_existing;
  end if;

  select * into v_reversal_event from app.loyalty_earning_events where id = p_reversal_earning_event_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_earning_event_not_found: % is not an earning event of tenant %', p_reversal_earning_event_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if v_reversal_event.reward_type <> 'points' then
    raise exception 'not_a_points_earning_event: earning event % has reward_type %, not points', p_reversal_earning_event_id, v_reversal_event.reward_type using errcode = 'check_violation';
  end if;
  if v_reversal_event.corrects_event_id is null then
    raise exception 'not_a_reversal_earning_event: % is not a reversal earning event -- call app.post_loyalty_points_earned instead', p_reversal_earning_event_id using errcode = 'check_violation';
  end if;

  select * into v_lot from app.loyalty_point_lots where tenant_id = p_tenant_id and source_earning_event_id = v_reversal_event.corrects_event_id;
  if not found then
    raise exception 'loyalty_point_lot_not_found: no point lot was ever created for the original earning event % (call app.post_loyalty_points_earned for it first)', v_reversal_event.corrects_event_id
      using errcode = 'no_data_found';
  end if;

  select * into v_earn_entry from app.loyalty_point_ledger_entries where tenant_id = p_tenant_id and lot_id = v_lot.id and event_type = 'earn';
  if not found then
    raise exception 'loyalty_point_ledger_entry_not_found: lot % has no earn entry to reverse', v_lot.id using errcode = 'no_data_found';
  end if;

  -- Cap the reversal at whatever the lot still has remaining -- some of it
  -- may already have been legitimately spent/expired before the underlying
  -- earning event was reversed (design decision 6, disclosed).
  v_applied_amount := least(v_lot.remaining_amount, abs(v_reversal_event.amount));
  if v_applied_amount <= 0 then
    raise exception 'lot_already_fully_consumed: lot % has zero remaining points, nothing left to reverse', v_lot.id using errcode = 'check_violation';
  end if;

  -- Tier C review fix (Low): this function delegates its actual ledger
  -- mutation to app.post_loyalty_point_ledger_entry, which independently
  -- re-checks LYL:Edit as ITS OWN first authority gate -- an undisclosed
  -- coupling under this repository's dynamic, tenant-configured RBAC model
  -- (a role holding Configure without Edit is a plausible configuration).
  -- Checked explicitly, with a clear, self-referential message, right
  -- before delegating -- AFTER the idempotent short-circuit above (a
  -- Configure-only replay of an ALREADY-reversed event still succeeds,
  -- unchanged, since it never reaches this point) but before the nested
  -- call would otherwise raise the identical rejection with no context
  -- about why a Configure-holding actor was denied.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant % -- reversal delegates to app.post_loyalty_point_ledger_entry, which also requires LYL:Edit', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.post_loyalty_point_ledger_entry(
    p_tenant_id, v_lot.loyalty_account_id, 'reversal', -v_applied_amount, v_lot.id,
    'loyalty_earning_event', p_reversal_earning_event_id, v_idem,
    'reversal of earning event ' || v_reversal_event.corrects_event_id::text, v_earn_entry.id,
    p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.reverse_loyalty_points_earned is
  'CPL-318: NEVER deletes or edits the original ''earn'' entry -- inserts a NEW, linked row (corrects_entry_id), mirroring app.reverse_loyalty_earning_event/app.reverse_inventory_movement exactly. Idempotent on (tenant_id, ''earning-event-reversal:'' || reversal_earning_event_id).';

-- ===========================================================================
-- 8. app.expire_loyalty_point_lots -- LYL:Edit. Scans lots past expires_at
-- with remaining_amount > 0, posts an 'expiry' entry per lot, idempotent
-- per lot (design decision 8).
-- ===========================================================================

create function app.expire_loyalty_point_lots(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns setof app.loyalty_point_ledger_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_lot record;
  v_entry app.loyalty_point_ledger_entries;
  v_idem text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_lot in
    select * from app.loyalty_point_lots
    where tenant_id = p_tenant_id and status = 'active' and remaining_amount > 0 and expires_at <= clock_timestamp()
    order by expires_at asc, id asc
  loop
    begin
      v_idem := 'lot-expiry:' || v_lot.id::text;
      v_entry := app.post_loyalty_point_ledger_entry(
        p_tenant_id, v_lot.loyalty_account_id, 'expiry', -v_lot.remaining_amount, v_lot.id,
        'point_lot_expiry', v_lot.id, v_idem, null, null,
        p_actor_auth_user_id, p_actor_label
      );
      return next v_entry;
    exception
      when others then
        -- A concurrent expire run or a concurrent consumption may have
        -- already touched this lot between this scan's own snapshot and
        -- this iteration reaching it (design decision 8) -- skip it; a
        -- future call safely picks up whatever, if anything, is still due.
        continue;
    end;
  end loop;

  return;
end;
$$;

comment on function app.expire_loyalty_point_lots is
  'CPL-318: idempotent per lot by construction -- a lot already fully expired no longer matches this function''s own scan predicate on re-run, a safe no-op. Each lot is independently fault-isolated (design decision 8) so one lot racing against a concurrent operation never aborts an otherwise-successful batch for every other due lot.';

-- ===========================================================================
-- 9. app.consume_loyalty_points_fifo -- LYL:Edit. A real, complete FIFO-by-
-- expiry multi-lot consumption primitive (design decision 7); not yet
-- wired to any customer-facing redemption UI (ISS-2026-128).
-- ===========================================================================

create function app.consume_loyalty_points_fifo(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_amount numeric,
  p_source_type text,
  p_source_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns setof app.loyalty_point_ledger_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.loyalty_accounts;
  v_remaining_to_consume numeric;
  v_lot record;
  v_take numeric;
  v_entry app.loyalty_point_ledger_entries;
  v_existing_count integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount: redemption amount must be greater than zero' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_account_not_found: % is not a loyalty account of tenant %', p_loyalty_account_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  -- Serialize concurrent redemption calls for the SAME account (design
  -- decision 7 -- mirrors CPL-317's own established per-entity advisory-
  -- lock precedent, salt 3; salt 4 here to stay distinct).
  perform pg_advisory_xact_lock(hashtextextended(p_loyalty_account_id::text, 4));

  -- Whole-redemption idempotency: a single logical redemption fans out into
  -- N per-lot ledger rows sharing one (source_type, source_id) -- re-running
  -- with the same source returns the SAME already-posted set, never a
  -- second consumption. Safe under a genuine concurrent race only because
  -- of the advisory lock above (the second caller waits for the first to
  -- fully commit, then sees its rows here).
  select count(*) into v_existing_count from app.loyalty_point_ledger_entries
    where tenant_id = p_tenant_id and event_type = 'redemption' and source_type = p_source_type and source_id = p_source_id;
  if v_existing_count > 0 then
    return query
      select * from app.loyalty_point_ledger_entries
      where tenant_id = p_tenant_id and event_type = 'redemption' and source_type = p_source_type and source_id = p_source_id
      order by created_at asc, id asc;
    return;
  end if;

  v_remaining_to_consume := p_amount;

  for v_lot in
    select * from app.loyalty_point_lots
    where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id and status = 'active' and remaining_amount > 0
    order by expires_at asc, id asc
    for update
  loop
    exit when v_remaining_to_consume <= 0;
    v_take := least(v_lot.remaining_amount, v_remaining_to_consume);
    v_entry := app.post_loyalty_point_ledger_entry(
      p_tenant_id, p_loyalty_account_id, 'redemption', -v_take, v_lot.id,
      p_source_type, p_source_id, p_idempotency_key || ':lot:' || v_lot.id::text, null, null,
      p_actor_auth_user_id, p_actor_label
    );
    return next v_entry;
    v_remaining_to_consume := v_remaining_to_consume - v_take;
  end loop;

  if v_remaining_to_consume > 0 then
    -- Tier C review fix (Critical, financial-ledger balance/redeemability
    -- correctness): a LOT-LESS credit -- today, exclusively a POSITIVE
    -- manual adjustment posted via app.decide_loyalty_point_adjustment
    -- (p_lot_id = null, since app.loyalty_point_lots.source_earning_
    -- event_id is NOT NULL and an adjustment has no backing earning event,
    -- design decision 6) -- increases the account's own AGGREGATE balance
    -- (app.loyalty_point_balances) without ever creating a lot. Before this
    -- fix, once every active lot was exhausted, this function raised
    -- insufficient_points_balance unconditionally, even when the aggregate
    -- balance genuinely still had room -- so a legitimately staff-approved
    -- credit became permanently stranded the moment redemption shipped, the
    -- customer-facing wallet showing points that could never actually be
    -- spent via this repository's own ONLY consumption primitive. Fixed by
    -- attempting exactly ONE final, lot-less consuming entry (p_lot_id =
    -- null) for whatever remains once every active lot is exhausted --
    -- app.post_loyalty_point_ledger_entry's own aggregate negative-balance
    -- guard (design decision 3, the AUTHORITATIVE check) is what actually
    -- decides whether this is genuinely available; a truly insufficient
    -- balance still fails here, with the identical insufficient_points_
    -- balance errcode/message prefix this function's own callers already
    -- handle. Live-reproduced and proven fixed in this checkpoint's own
    -- db-test (Gamma's account, whose only balance IS a lot-less adjustment
    -- credit after her one real lot was independently expired earlier in
    -- the same fixture).
    v_entry := app.post_loyalty_point_ledger_entry(
      p_tenant_id, p_loyalty_account_id, 'redemption', -v_remaining_to_consume, null,
      p_source_type, p_source_id, p_idempotency_key || ':unlotted', null, null,
      p_actor_auth_user_id, p_actor_label
    );
    return next v_entry;
    v_remaining_to_consume := 0;
  end if;

  return;
end;
$$;

comment on function app.consume_loyalty_points_fifo is
  'CPL-318: consumes the account''s own active lots in expires_at ASC order (FIFO-by-expiry, design decision 7), posting one redemption entry per lot touched via app.post_loyalty_point_ledger_entry. Once every active lot is exhausted, a single final lot-less entry (p_lot_id = null) consumes whatever remains of the aggregate balance -- Tier C review fix, makes a lot-less credit (a positive manual adjustment) genuinely redeemable rather than permanently stranded. An insufficient aggregate balance rolls back the ENTIRE call (every entry already posted this run included, lot-backed or not) -- never a partial redemption. A real, complete ledger-side primitive; no customer-facing redemption UI/reward catalog exists yet to call it from (ISS-2026-128), mirroring ISS-2026-126/127''s own disclosure shape.';

-- ===========================================================================
-- 10. app.request_loyalty_point_adjustment -- LYL:Edit (maker). DIRECTLY
-- mirrors app.request_vendor_kpi_manual_adjustment (design decision 9).
-- ===========================================================================

create function app.request_loyalty_point_adjustment(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_adjustment_amount numeric,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_point_adjustment_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.loyalty_accounts;
  v_current_balance app.loyalty_point_balances;
  v_existing app.loyalty_point_adjustment_requests;
  v_request app.loyalty_point_adjustment_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request a point adjustment' using errcode = 'check_violation';
  end if;
  if p_adjustment_amount is null or p_adjustment_amount = 0 then
    raise exception 'invalid_amount: adjustment_amount must be non-zero' using errcode = 'check_violation';
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_account_not_found: % is not a loyalty account of tenant %', p_loyalty_account_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.loyalty_point_adjustment_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.loyalty_account_id is distinct from p_loyalty_account_id or v_existing.adjustment_amount is distinct from p_adjustment_amount then
        raise exception 'idempotency_key_conflict: key % was already used for a different point adjustment request', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  select * into v_current_balance from app.loyalty_point_balances where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id;

  begin
    insert into app.loyalty_point_adjustment_requests (
      tenant_id, loyalty_account_id, adjustment_amount, reason, requested_by_auth_user_id, requested_by, idempotency_key, created_by
    ) values (
      p_tenant_id, p_loyalty_account_id, p_adjustment_amount, p_reason, p_actor_auth_user_id, p_actor_label, p_idempotency_key, p_actor_label
    )
    returning * into v_request;
  exception
    -- Nested to scope ONLY this INSERT (taxonomy C-02) -- the pre-check's
    -- own idempotency_key_conflict raise above shares this errcode but
    -- lives OUTSIDE this block, so it is never caught here. A genuine
    -- pending-adjustment race (two concurrent requests against the SAME
    -- account, lpar_pending_unique) is what this handler actually exists
    -- for -- mirrors app.request_vendor_kpi_manual_adjustment exactly.
    when unique_violation then
      raise exception 'adjustment_already_pending: loyalty account % already has a pending point adjustment request', p_loyalty_account_id using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_loyalty_point_adjustment',
    'app.loyalty_point_adjustment_requests', v_request.id, 'success', p_reason,
    jsonb_build_object('available_balance', coalesce(v_current_balance.available, 0)),
    jsonb_build_object('requested_adjustment_amount', p_adjustment_amount)
  );

  return v_request;
end;
$$;

comment on function app.request_loyalty_point_adjustment is
  'CPL-318: maker (LYL:Edit). At most one pending adjustment per account (lpar_pending_unique); a genuine race is translated into the same typed adjustment_already_pending error, never a raw constraint-name leak.';

-- ===========================================================================
-- 11. app.decide_loyalty_point_adjustment -- LYL:Configure (checker).
-- DIRECTLY mirrors app.decide_vendor_kpi_manual_adjustment, with a real
-- before/after audit and a C-05-safe tenant-scoped authority-first check
-- (design decision 9).
-- ===========================================================================

create function app.decide_loyalty_point_adjustment(
  p_tenant_id uuid,
  p_adjustment_id uuid,
  p_expected_version integer,
  p_decision text,
  p_decision_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_point_adjustment_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.loyalty_point_adjustment_requests;
  v_original_status text;
  v_entry app.loyalty_point_ledger_entries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Tenant-scoped fetch AFTER authority check (C-05, design decision 9) --
  -- a cross-tenant id guess and a genuinely nonexistent id both resolve to
  -- the identical not-found error below.
  select * into v_request from app.loyalty_point_adjustment_requests where id = p_adjustment_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_point_adjustment_request_not_found: %', p_adjustment_id using errcode = 'no_data_found';
  end if;
  v_original_status := v_request.status;

  if v_request.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % requested point adjustment % and may not also decide it', p_actor_auth_user_id, p_adjustment_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: point adjustment request % expected version % but found %', p_adjustment_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'pending_approval' then
    raise exception 'invalid_transition: point adjustment request % is % and cannot be decided', p_adjustment_id, v_request.status
      using errcode = 'check_violation';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not one of approved/rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision_notes is null or length(trim(p_decision_notes)) = 0 then
    raise exception 'reason_required: a non-empty decision_notes is required' using errcode = 'check_violation';
  end if;

  if p_decision = 'approved' then
    -- Tier C review fix (Low): approval delegates its actual ledger
    -- mutation to app.post_loyalty_point_ledger_entry, which independently
    -- re-checks LYL:Edit as ITS OWN first authority gate -- an undisclosed
    -- coupling under this repository's dynamic, tenant-configured RBAC
    -- model (a role holding Configure without Edit is a plausible
    -- configuration). Checked explicitly, with a clear, self-referential
    -- message, right before delegating -- scoped to the approval branch
    -- only, so a Configure-only actor can still REJECT a request (which
    -- never touches the posting primitive) exactly as before.
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant % -- approving a point adjustment delegates to app.post_loyalty_point_ledger_entry, which also requires LYL:Edit', p_actor_auth_user_id, v_decision.reason, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;

    v_entry := app.post_loyalty_point_ledger_entry(
      p_tenant_id, v_request.loyalty_account_id, 'adjustment', v_request.adjustment_amount, null,
      'manual_adjustment', v_request.id, 'adjustment:' || v_request.id::text, v_request.reason, null,
      p_actor_auth_user_id, p_actor_label
    );
  end if;

  update app.loyalty_point_adjustment_requests
  set status = p_decision, decided_by_auth_user_id = p_actor_auth_user_id, decided_by = p_actor_label, decided_at = clock_timestamp(),
      decision_notes = p_decision_notes, ledger_entry_id = v_entry.id
  where id = p_adjustment_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: point adjustment request % target row was concurrently modified (expected version %)', p_adjustment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_loyalty_point_adjustment',
    'app.loyalty_point_adjustment_requests', v_request.id, 'success', p_decision_notes,
    jsonb_build_object('status', v_original_status),
    jsonb_build_object('status', v_request.status, 'ledger_entry_id', v_request.ledger_entry_id)
  );

  return v_request;
end;
$$;

comment on function app.decide_loyalty_point_adjustment is
  'CPL-318: checker (LYL:Configure), self-approval blocked (requested_by <> decided_by, live-proven in this checkpoint''s own db-test, not TS-mocked). On approval, posts a real app.loyalty_point_ledger_entries adjustment entry via app.post_loyalty_point_ledger_entry -- this function itself never mutates a balance/lot directly. Real before/after on its own capture_audit_event call (design decision 9), an improvement over PRC-264''s own null-before precedent.';

-- ===========================================================================
-- 12. Staff reads -- LYL:View.
-- ===========================================================================

create function app.get_loyalty_point_adjustment_request(p_tenant_id uuid, p_adjustment_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_point_adjustment_requests
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_request app.loyalty_point_adjustment_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_request from app.loyalty_point_adjustment_requests where id = p_adjustment_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_point_adjustment_request_not_found: %', p_adjustment_id using errcode = 'no_data_found';
  end if;

  return v_request;
end;
$$;

create function app.list_loyalty_point_adjustment_requests(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_loyalty_account_id uuid default null,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_point_adjustment_requests
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
  select r.* from app.loyalty_point_adjustment_requests r
  where r.tenant_id = p_tenant_id
    and (p_loyalty_account_id is null or r.loyalty_account_id = p_loyalty_account_id)
    and (p_status is null or r.status = p_status)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

create function app.get_loyalty_point_balance(p_tenant_id uuid, p_loyalty_account_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_point_balances
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_balance app.loyalty_point_balances;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_balance from app.loyalty_point_balances where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id;
  if not found then
    raise exception 'loyalty_point_balance_not_found: account % has not posted any point activity yet', p_loyalty_account_id using errcode = 'no_data_found';
  end if;

  return v_balance;
end;
$$;

comment on function app.get_loyalty_point_balance is
  'CPL-318: raises loyalty_point_balance_not_found for an account with zero point activity ever posted (no lazily-created row yet) -- the caller (service layer/UI) treats this specific code as a zero-balance state, mirroring CPL-316/317''s own "not yet enrolled"/"not yet evaluated" empty-state handling at the presentation layer rather than synthesizing a fake row in the database.';

create function app.list_loyalty_point_balances(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_point_balances
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
  select b.* from app.loyalty_point_balances b
  where b.tenant_id = p_tenant_id
    and (p_cursor_id is null or (b.updated_at, b.id) < (p_cursor_updated_at, p_cursor_id))
  order by b.updated_at desc, b.id desc
  limit v_limit;
end;
$$;

create function app.get_loyalty_point_lot(p_tenant_id uuid, p_lot_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_point_lots
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_lot app.loyalty_point_lots;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_lot from app.loyalty_point_lots where id = p_lot_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_point_lot_not_found: %', p_lot_id using errcode = 'no_data_found';
  end if;

  return v_lot;
end;
$$;

create function app.list_loyalty_point_lots(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_loyalty_account_id uuid default null,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_point_lots
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
  select l.* from app.loyalty_point_lots l
  where l.tenant_id = p_tenant_id
    and (p_loyalty_account_id is null or l.loyalty_account_id = p_loyalty_account_id)
    and (p_status is null or l.status = p_status)
    and (p_cursor_id is null or (l.updated_at, l.id) < (p_cursor_updated_at, p_cursor_id))
  order by l.updated_at desc, l.id desc
  limit v_limit;
end;
$$;

create function app.list_loyalty_point_ledger_entries(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_loyalty_account_id uuid default null,
  p_event_type text default null,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_point_ledger_entries
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

  if p_cursor_id is not null and p_cursor_created_at is null then
    raise exception 'invalid_cursor: p_cursor_created_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select e.* from app.loyalty_point_ledger_entries e
  where e.tenant_id = p_tenant_id
    and (p_loyalty_account_id is null or e.loyalty_account_id = p_loyalty_account_id)
    and (p_event_type is null or e.event_type = p_event_type)
    and (p_cursor_id is null or (e.created_at, e.id) < (p_cursor_created_at, p_cursor_id))
  order by e.created_at desc, e.id desc
  limit v_limit;
end;
$$;

comment on function app.list_loyalty_point_ledger_entries is
  'CPL-318: keyset-paginated on (created_at desc, id desc) -- app.loyalty_point_ledger_entries has no updated_at column (append-only, immutable rows), mirroring app.list_loyalty_earning_events exactly. Full internal projection (includes reason) -- staff-only.';

-- ===========================================================================
-- 13. Customer-facing (Layer 4, ADR-0024 Part A) -- point balance, ledger
-- history, expiry schedule.
-- ===========================================================================

create function app.list_customer_portal_loyalty_point_balances(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_customer_account_id uuid default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  loyalty_account_id uuid,
  customer_account_id uuid,
  program_id uuid,
  program_name text,
  total_earned numeric,
  total_consumed numeric,
  available numeric,
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

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;
  if p_customer_account_id is not null and not (p_customer_account_id = any (v_scope)) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select b.loyalty_account_id, la.customer_account_id, la.program_id, p.name, b.total_earned, b.total_consumed, b.available, b.updated_at
  from app.loyalty_point_balances b
  join app.loyalty_accounts la on la.id = b.loyalty_account_id
  join app.loyalty_programs p on p.id = la.program_id
  where b.tenant_id = p_tenant_id
    and la.customer_account_id = any (v_scope)
    and (p_customer_account_id is null or la.customer_account_id = p_customer_account_id)
    and (p_cursor_id is null or (b.updated_at, b.loyalty_account_id) < (p_cursor_updated_at, p_cursor_id))
  order by b.updated_at desc, b.loyalty_account_id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_loyalty_point_balances is
  'CPL-318: customer-safe projection of a customer''s own point balance(s). Never exposes any other account''s row. Deny-by-default: an out-of-scope p_customer_account_id or an empty resolved scope both return zero rows, never an error. An account with zero point activity ever posted simply does not appear (no lazily-created balance row) -- the UI renders a zero/empty state for that case, mirroring app.get_loyalty_point_balance''s own not-found-means-zero convention.';

create function app.list_customer_portal_loyalty_point_ledger_entries(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_customer_account_id uuid default null,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  program_name text,
  event_type text,
  amount numeric,
  description text,
  created_at timestamptz
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

  if p_cursor_id is not null and p_cursor_created_at is null then
    raise exception 'invalid_cursor: p_cursor_created_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;
  if p_customer_account_id is not null and not (p_customer_account_id = any (v_scope)) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select
    e.id,
    p.name,
    e.event_type,
    e.amount,
    case e.event_type
      when 'earn' then 'Points earned'
      when 'redemption' then 'Points redeemed'
      when 'expiry' then 'Points expired'
      when 'reversal' then 'Correction'
      when 'adjustment' then 'Account adjustment'
      else 'Points activity'
    end,
    e.created_at
  from app.loyalty_point_ledger_entries e
  join app.loyalty_accounts la on la.id = e.loyalty_account_id
  join app.loyalty_programs p on p.id = la.program_id
  where e.tenant_id = p_tenant_id
    and la.customer_account_id = any (v_scope)
    and (p_customer_account_id is null or la.customer_account_id = p_customer_account_id)
    and (p_cursor_id is null or (e.created_at, e.id) < (p_cursor_created_at, p_cursor_id))
  order by e.created_at desc, e.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_loyalty_point_ledger_entries is
  'CPL-318: customer-safe ledger history. Never projects the internal reason column at all (structural guarantee, not merely UI omission) -- a customer sees a generic, event-type-derived description ("Account adjustment") instead of any real internal investigation note an adjustment''s own reason might carry (business rule: "Ledger history... cannot leak... internal investigation notes"). Never exposes loyalty_account_id/lot_id/source_id/idempotency_key (internal linkage). Deny-by-default, keyset-paginated on (created_at desc, id desc).';

create function app.list_customer_portal_loyalty_point_expiry_schedule(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_customer_account_id uuid default null,
  p_cursor_expires_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  program_name text,
  remaining_amount numeric,
  expires_at timestamptz
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

  if p_cursor_id is not null and p_cursor_expires_at is null then
    raise exception 'invalid_cursor: p_cursor_expires_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;
  if p_customer_account_id is not null and not (p_customer_account_id = any (v_scope)) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select l.id, p.name, l.remaining_amount, l.expires_at
  from app.loyalty_point_lots l
  join app.loyalty_accounts la on la.id = l.loyalty_account_id
  join app.loyalty_programs p on p.id = la.program_id
  where l.tenant_id = p_tenant_id
    and la.customer_account_id = any (v_scope)
    and l.status = 'active'
    and l.remaining_amount > 0
    and (p_customer_account_id is null or la.customer_account_id = p_customer_account_id)
    and (p_cursor_id is null or (l.expires_at, l.id) > (p_cursor_expires_at, p_cursor_id))
  order by l.expires_at asc, l.id asc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_loyalty_point_expiry_schedule is
  'CPL-318: customer-safe FIFO-by-expiry schedule of the customer''s own currently-active, unexhausted lots (soonest-expiring first). Deny-by-default. Keyset-paginated ASCENDING on (expires_at asc, id asc) -- a deliberate, disclosed departure from the general (updated_at desc, id desc) staff-list convention, since "soonest expiring first" is this specific listing''s own natural, customer-meaningful order; still strictly keyset (no OFFSET, using > instead of < in the cursor predicate).';

-- ===========================================================================
-- 14. RLS -- enable, grant service_role only (design decision 13).
-- ===========================================================================

alter table app.loyalty_point_lots enable row level security;
alter table app.loyalty_point_ledger_entries enable row level security;
alter table app.loyalty_point_balances enable row level security;
alter table app.loyalty_point_adjustment_requests enable row level security;

grant select, insert, update on app.loyalty_point_lots to service_role;
grant select, insert on app.loyalty_point_ledger_entries to service_role;
grant select, insert, update on app.loyalty_point_balances to service_role;
grant select, insert, update on app.loyalty_point_adjustment_requests to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.post_loyalty_point_ledger_entry(uuid, uuid, text, numeric, uuid, text, uuid, text, text, uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.post_loyalty_points_earned(uuid, uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.reverse_loyalty_points_earned(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.expire_loyalty_point_lots(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.consume_loyalty_points_fifo(uuid, uuid, numeric, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.request_loyalty_point_adjustment(uuid, uuid, numeric, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_loyalty_point_adjustment(uuid, uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_point_adjustment_request(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_point_adjustment_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.get_loyalty_point_balance(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_point_balances(uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.get_loyalty_point_lot(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_point_lots(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_loyalty_point_ledger_entries(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_portal_loyalty_point_balances(uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_portal_loyalty_point_ledger_entries(uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_portal_loyalty_point_expiry_schedule(uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
