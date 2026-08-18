-- Phase 8 capability CPL-320 (CG-S13-CPL-022, Prompt 320, "Reward
-- Catalogue") -- the FIRST prompt of Batch 5 (CPL-320..323), and the FIFTH
-- Loyalty-domain capability in this repository (ADR-0024 Part D). Read
-- docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-pattern.md
-- Part D; docs/build-log/phase-08/CPL-316.md, CPL-317.md, CPL-318.md,
-- CPL-319.md and their own migrations (20260801180000/190000/200000/210000)
-- IN FULL; supabase/migrations/20260719140000_create_document_file_engine.sql
-- (PLT-128, private/scanned-file pattern) before writing any of this file.
-- This migration READS app.loyalty_accounts (CPL-316), app.loyalty_tier_
-- definitions/app.loyalty_account_tier_movements (CPL-317, for tier-based
-- eligibility), app.loyalty_point_balances (CPL-318, for points-based
-- eligibility), and app.files/app.file_access_logs (PLT-128) -- it never
-- INSERTs/UPDATEs/DELETEs against any of those tables, confirmed by grep
-- before this file was finalized. It never reads or writes any CPL-319
-- table at all (voucher/cashback redemption is a sibling capability, not an
-- upstream dependency of a reward catalogue).
--
-- ===========================================================================
-- SCOPE BOUNDARY (disclosed, per this checkpoint's own orchestrating task
-- instruction -- mirrors CPL-319's own identical disclosure shape for its
-- Finance-handoff boundary)
-- ===========================================================================
--
-- This migration builds the CATALOGUE only: reward definitions, eligibility
-- criteria, stock/availability CONFIGURATION, effective-dated scheduling,
-- terms, and customer-safe presentation (eligible/locked/out_of_stock/
-- unavailable states). It does NOT build a redemption/consume-stock
-- transaction that decrements stock or creates a redemption record against
-- a customer's own loyalty account -- that is explicitly CPL-321's own
-- future scope ("Redemption Approval and Fulfillment"), per the source
-- prompt's own downstream note (section 10) and this checkpoint's own
-- orchestrating task instruction. This checkpoint's own job is narrower and
-- complete on its own terms: model stock as a real, race-safe primitive
-- (design decision 6) so CPL-321 has something real to compose from, and
-- compute a live, correctly-computed "is this reward currently in stock"
-- read for catalogue display -- the actual decrement-on-redeem transaction
-- itself, and any real trigger that calls it from a genuine customer
-- checkout action, belongs to CPL-321. Recorded again in docs/runtime/
-- KNOWN_ISSUES.md (a new sequential entry after ISS-2026-130).
--
-- ===========================================================================
-- Design decisions (disclosed, not re-derived)
-- ===========================================================================
--
-- 1. **Table naming: `app.loyalty_rewards`** (my own call, disclosed, per
--    this prompt's own "your own naming call, disclosed" latitude) -- the
--    shorter of the two names the source prompt itself offered as an
--    example ("app.loyalty_rewards or app.loyalty_reward_catalogue_items").
-- 2. **`reward_type` vocabulary: `('discount_voucher', 'physical_item',
--    'service_credit')`** -- exactly the source prompt's own literal
--    example, grounded in what CPL-319's `app.loyalty_benefit_entitlements.
--    benefit_type` already models on the redemption side (`'cashback',
--    'discount', 'voucher'`), since a published reward here should be
--    redeemable into one of CPL-319's own benefit_type values later by
--    CPL-321. The forward mapping (disclosed, not enforced by a database
--    constraint in THIS checkpoint -- CPL-321's own job to actually compose
--    it): `'discount_voucher'` -> CPL-319 `'voucher'` (or `'discount'`,
--    CPL-321's own call depending on whether a code is minted);
--    `'service_credit'` -> CPL-319 `'cashback'` (a service credit is,
--    functionally, a cashback-shaped credit toward a future service);
--    `'physical_item'` has NO CPL-319 `benefit_type` counterpart at all --
--    physical merchandise fulfillment is out-of-band (shipped, not an
--    entitlement-ledger event), a real, disclosed boundary CPL-321 will need
--    its own fulfillment-tracking shape for, not a gap this checkpoint
--    silently papers over.
-- 3. **Eligibility criteria: typed columns (`min_tier_id`, `min_points_
--    required`), not a jsonb `eligibility_config`** -- the source prompt's
--    own literal first option, chosen over CPL-316's own `eligibility_
--    config jsonb` precedent because both eligibility DIMENSIONS this
--    checkpoint's own business rules actually need (a tier gate, a points
--    gate) are already precisely modeled, typed columns elsewhere in this
--    same domain (`app.loyalty_tier_definitions.tier_rank`, `app.loyalty_
--    point_balances.available`) -- a jsonb bag would only re-introduce the
--    "parse and hope" indirection those precedents were built specifically
--    to avoid. Both may be null (a fully open reward, gated on nothing but
--    enrollment/stock) or both set at once (AND-combined -- a customer must
--    meet BOTH thresholds to be "eligible"; OR-combined eligibility was
--    considered and rejected as unneeded complexity beyond what this
--    checkpoint's own literal ask or db-test requirement -- "tier-gated AND
--    points-gated cases" -- ever calls for; a future capability could add an
--    explicit `eligibility_mode` column if a real OR need ever arises).
-- 4. **`min_tier_id` references a SPECIFIC `app.loyalty_tier_definitions`
--    row (the source prompt's own literal FK target), but eligibility is
--    evaluated by comparing `tier_rank`, never by exact tier-identity
--    match.** `app.loyalty_tier_definitions` rows are immutable once created
--    except their own `status`/`effective_to` (CPL-317's own established
--    invariant -- `tier_rank`/`threshold_value`/etc are NEVER updated in
--    place) -- so a `min_tier_id` reference stays a stable, permanently
--    valid rank anchor even after CPL-317's own publish workflow supersedes
--    that specific row with a newer version of the SAME tier_name. A
--    customer's own CURRENT tier_rank (derived exactly as CPL-317's own
--    `app.list_customer_portal_loyalty_tier_cards` derives it -- latest
--    `app.loyalty_account_tier_movements` row, joined to its own `to_tier_
--    id`'s `tier_rank`) must be `>=` the referenced row's own `tier_rank`
--    to pass the tier gate. Fraud holds (`app.loyalty_account_tier_holds`)
--    are DELIBERATELY not read or composed here at all -- a hold suppresses
--    BENEFIT DISPLAY at the tier-card layer (CPL-317's own domain), it does
--    not retroactively change what tier rank a customer has actually
--    attained, and reward eligibility is about attained standing, not about
--    whether tier benefits happen to be currently suspended for an
--    unrelated fraud investigation.
-- 5. **Effective-dated draft/published/paused/archived lifecycle, ONE
--    lineage per `(program_id, reward_name)`** -- mirrors CPL-317's own
--    `(program_id, tier_name)` versioning shape exactly, one level wider
--    (five real status values instead of three: `draft -> published ->
--    superseded`, PLUS `paused`/`archived` as real, first-class status
--    values covering this prompt's own "admin pauses it" alternative flow,
--    per this checkpoint's own task instruction). `pause_loyalty_reward`/
--    `resume_loyalty_reward`/`archive_loyalty_reward` are all plain STATUS
--    FLIPS on the SAME published row (never a new version) -- mirrors
--    CPL-317's own `publish_loyalty_tier_definition` already flipping the
--    PRIOR published row's own `status` to `'superseded'` in place, so
--    mutating a published row's own `status` column post-publish is already
--    an established pattern in this exact table shape, not a new one. A
--    second partial unique index, `lr_single_live_per_reward`, on
--    `(program_id, reward_name) where status in ('published', 'paused')`,
--    guarantees at most ONE "live" (published-or-paused) row per lineage at
--    a time -- publishing a new draft supersedes whichever row (published
--    OR paused) currently holds that slot, so a lineage can never fork into
--    two simultaneously-live versions.
-- 6. **`app.resume_loyalty_reward` is a disclosed 6th function, beyond the
--    5 this checkpoint's own task text names literally
--    (`create_loyalty_reward_draft`/`update_loyalty_reward_draft`/`publish_
--    loyalty_reward`/`pause_loyalty_reward`/`archive_loyalty_reward`).**
--    Mirrors CPL-317's own `review_period_days` precedent and CPL-318's own
--    `p_expiry_days` precedent -- the literal ask under-specifies a real
--    business requirement ("admin ... pauses it," source prompt section 22)
--    that is meaningless unless reversible: a reward an admin merely wants
--    to temporarily take off the shelf (e.g. a seasonal promotion, a
--    supply-chain pause) must be resumable without republishing a whole new
--    version (which `publish_loyalty_reward` cannot do from `'paused'` --
--    it requires `status = 'draft'`). `resume_loyalty_reward` is the exact
--    structural inverse of `pause_loyalty_reward` (`'paused' -> 'published'`,
--    same optimistic-concurrency shape, same LYL:Configure gate) -- never
--    touches `published_by`/`published_at` (the original publish event is
--    not re-authored, only availability is restored).
-- 7. **Stock mechanism (this checkpoint's own most consequential design
--    call, item 2 of the task's own explicit instruction) -- a real,
--    race-safe, append-only reservation ledger PLUS a live computed
--    aggregate, never a cached/mirrored counter column on `app.loyalty_
--    rewards` itself.** The task's own instruction offered two named shapes
--    (an append-only `app.loyalty_reward_stock_ledger` this prompt itself
--    never writes to except in its own db-test's concurrent-reservation
--    proof, OR simply exposing `total_stock` with a disclosed note that
--    live consumption tracking is CPL-321's own scope) and explicitly
--    warned against "a fake redemption-count column that nothing
--    populates." A bare `total_stock` column alone would not be "a real
--    primitive... to consume from later" (the scope boundary's own literal
--    requirement) -- it is pure configuration, not a mechanism. This
--    checkpoint therefore builds `app.loyalty_reward_stock_reservations`
--    (append-only, `unique(tenant_id, idempotency_key)`, one row per
--    reservation of `quantity` units) plus ONE real posting primitive,
--    `app.reserve_loyalty_reward_stock_unit` -- race-safety comes from a
--    `select ... for update` row lock on the TARGET REWARD ROW itself
--    (never on the ledger table), taken BEFORE the current-reservation-total
--    aggregate is read and BEFORE the new ledger row is inserted: since
--    EVERY call to this function for the SAME reward serializes on that
--    row's own lock, two concurrent callers can never both observe the same
--    stale "still have room" total and both succeed in oversubscribing it --
--    live-proven with a genuine two-process race in this checkpoint's own
--    db-test (mirrors CPL-318's own real two-psql-process negative-balance
--    race proof, reusing the SAME `scripts/db-tests/wms-picking-
--    concurrency-helper.sh` generic helper). `stock_available` is NEVER a
--    stored/generated column on `app.loyalty_rewards` -- it is always a
--    LIVE, computed `total_stock - coalesce(sum(quantity), 0)` aggregate
--    over the reservation ledger, evaluated fresh on every catalogue read
--    (list/get) -- this eliminates the whole "two independently-mutable
--    numbers that could silently drift" defect class CPL-318's own ledger-
--    insert-before-mutation lesson exists to guard against, structurally,
--    rather than merely by discipline (there is no second number to keep in
--    sync in the first place). `app.reserve_loyalty_reward_stock_unit` is
--    NEVER called by any production code path in this checkpoint (no real
--    redemption event exists yet to trigger it from) -- disclosed exactly
--    like CPL-318's own `app.consume_loyalty_points_fifo` precedent ("a
--    real, complete, live-proven ledger-side primitive, but no customer-
--    facing redemption UI or reward/voucher catalog exists yet to call it
--    from") -- only this checkpoint's own db-test calls it, proving the
--    primitive itself is genuinely correct and race-safe, ready for CPL-321
--    to compose. It deliberately does NOT re-validate a caller's own
--    tier/points eligibility or the reward's own effective-date window --
--    those are CPL-321's own job to check BEFORE composing this primitive,
--    exactly as `app.consume_loyalty_points_fifo` (CPL-318) is a pure
--    ledger-arithmetic primitive that never re-validates the redemption's
--    own surrounding business context either.
-- 8. **Internal cost/vendor fulfillment data is hidden from customers --
--    STRUCTURALLY, grep-provably, not merely a query-level projection
--    choice (business rule, source prompt section 24).**
--    `app.loyalty_rewards.internal_cost`/`vendor_ref` exist ONLY on the
--    staff-facing row shape (`app.get_loyalty_reward`/`app.list_loyalty_
--    rewards`, both `returns app.loyalty_rewards`/`setof app.loyalty_
--    rewards` -- the full table shape). Both customer-facing RPCs (`app.
--    list_customer_portal_loyalty_rewards`/`app.get_customer_portal_
--    loyalty_reward`) declare their own explicit `returns table (...)`
--    column list that never once names `internal_cost` or `vendor_ref` --
--    there is no code path in either function that could leak them even by
--    accident, grep-confirmed and directly asserted in this checkpoint's
--    own db-test via `to_jsonb(...) ? 'internal_cost'`.
-- 9. **Reward media/terms document reuses `app.files`/`app.file_access_
--    logs` directly (PLT-128) -- never a second file/upload table** (source
--    prompt sections 15/24). Mirrors CPL-307/CPL-308's own established
--    "no signed-URL primitive exists in this repository, never fabricate
--    one" discipline exactly: `app.get_customer_portal_loyalty_reward`
--    writes ONE `app.file_access_logs` row per call when `file_id` is set
--    (`access_type = 'metadata_view'`, never `'signed_url_issued'`), grants
--    a clean file's own customer-safe METADATA (filename/mime/size, never
--    `storage_path`), and returns a non-clean file's own real, honest
--    `malware_scan_status` (never hidden or defaulted to `clean` -- CPL-308
--    design decision 5's own "malware/quarantine states must be honestly
--    surfaced" rule, applied here identically) with no metadata attached.
--    `app.list_customer_portal_loyalty_rewards` (the LIST surface) does not
--    touch `app.files`/`app.file_access_logs` at all -- mirrors CPL-308's
--    own "only the per-document access action carries the audit discipline,
--    never the list" precedent exactly, to avoid a file_access_logs write
--    per catalogue row on every browse.
-- 10. **`clock_timestamp()`, never `now()`, EVERYWHERE in this migration --
--    including the two customer-facing read RPCs' own effective-dated
--    visibility filters, a real, self-found-and-fixed defect, not an
--    a-priori design choice.** This migration's own first draft used `now()`
--    for `effective_from <= now()`/`effective_to > now()`, reasoned (wrongly)
--    as a "single-statement, as-of-this-instant boundary comparison" outside
--    the CPL-315 defect class. Live-caught during this checkpoint's own
--    db-test authoring: `app.publish_loyalty_reward` stamps `effective_from`
--    via `clock_timestamp()` (design decision 5's own status-flip shape),
--    which ADVANCES in real time; `now()` (`= transaction_timestamp()`) is
--    FROZEN at the enclosing transaction's own start. A caller that
--    publishes a reward and then lists the catalogue WITHIN THE SAME
--    transaction (this checkpoint's own db-test batches both inside one
--    `do $$ ... $$` block, but nothing rules out a real future caller doing
--    the same for atomicity) would see `effective_from` (stamped moments
--    INTO that transaction) land AFTER the transaction's own frozen `now()`
--    -- `effective_from <= now()` then spuriously evaluates false, hiding a
--    reward the SAME transaction just published. Separate transactions
--    (the ordinary case -- publish and list as two distinct RPC calls from
--    two distinct requests) never hit this, since a later transaction's own
--    `now()` is necessarily after an earlier, already-committed transaction's
--    `effective_from` -- but a same-transaction caller is a real, live-
--    reproduced correctness gap, not a hypothetical. Fixed at the root by
--    switching both filters to `clock_timestamp()` in both `app.list_
--    customer_portal_loyalty_rewards` and `app.get_customer_portal_loyalty_
--    reward` -- `clock_timestamp()` advances within a transaction exactly
--    like the `effective_from` value it is compared against, so the
--    comparison is correct regardless of same-transaction or
--    cross-transaction timing. This checkpoint's own db-test carries the
--    live regression proof (publish immediately followed by a list/get call
--    inside the identical transaction, reward correctly visible).
-- 11. **Optimistic concurrency: the NULL-bypass fix, double-defended, on
--    every one of the five version-checked functions** (`app.update_
--    loyalty_reward_draft`/`app.publish_loyalty_reward`/`app.pause_loyalty_
--    reward`/`app.resume_loyalty_reward`/`app.archive_loyalty_reward`) --
--    the Batch 4 Tier C review's own self-found-and-fixed defect class
--    (CPL-316/317 §14): a bare `if v_row.record_version <> p_expected_
--    version then raise` evaluates to SQL NULL (falsy) when `p_expected_
--    version` is NULL, silently bypassing the check unless the UPDATE
--    statement's own WHERE clause ALSO repeats `and record_version =
--    p_expected_version` (which correctly matches zero rows for a NULL
--    input, falling through to the same `stale_version` error). Every
--    UPDATE in this migration carries that repeated predicate from its
--    first draft, proven with a live regression assertion per function in
--    this checkpoint's own db-test (§ below), not discovered by a later
--    review pass. **Tier C review hardening (Batch 5 close):** this
--    checkpoint's own original draft relied on the UPDATE-repeats-the-
--    predicate half ALONE (no explicit up-front `p_expected_version is
--    null or` rejection), unlike CPL-321/322/323's own siblings, which all
--    double-defend both halves. Not live-exploitable as shipped (the final
--    UPDATE's own repeated predicate still correctly rejects a NULL input
--    in every one of the five functions, live-verified by re-running this
--    checkpoint's own db-test unmodified after the fix below), but
--    `app.publish_loyalty_reward` specifically performs a real, genuine
--    side-effect write (superseding any prior live version of the same
--    reward lineage) BEFORE that late rejection is ever reached -- safe
--    only because Postgres's own statement/savepoint atomicity rolls that
--    premature write back together with the eventual `stale_version` raise
--    (no partial state was ever observable to a concurrent reader), but a
--    latent inconsistency with this batch's own hardened double-defense
--    convention. Fixed for consistency: every one of the five functions'
--    own early check now reads `if p_expected_version is null or
--    v_reward.record_version <> p_expected_version then`, matching the
--    sibling migrations exactly -- a cheap, zero-behavior-change hardening,
--    not a live-exploitability fix.
-- 12. **LYL permission mapping, reused from CPL-316/317/318/319
--    unchanged.** Draft CRUD -> `Create`/`Edit` (mirrors CPL-317's tier-
--    definition draft mapping exactly). Publishing, pausing, resuming, and
--    archiving a reward (all four change what is customer-visible/
--    redeemable -- governance-grade) -> the elevated `LYL:Configure`,
--    mirroring CPL-317's own `publish_loyalty_tier_definition`/hold-release
--    mapping. Ordinary stock-reservation posting -> `LYL:Edit`, mirroring
--    CPL-318's own `post_loyalty_point_ledger_entry` mapping. Staff reads
--    -> `LYL:View`. Customer-facing reads -> scoped via `app.resolve_
--    customer_account_scope` only, no staff RBAC check, mirroring
--    CPL-316/317/318/319 exactly -- zero customer-initiated WRITE exists in
--    this checkpoint (this is a catalogue, not a redemption capability;
--    ADR-0024 Part B has nothing to say here since nothing customer-owned
--    is written).
-- 13. Every actor-taking function calls `app.assert_actor_is_session_
--    identity` as its own literal FIRST statement; every staff mutate/
--    get-by-id RPC checks `LYL:*` authority BEFORE fetching its target row
--    (C-05, mirrors CPL-316/317/318/319's own identical design decision).
-- 14. **Zero reads or writes against any CPL-319 table, and zero WRITES
--    (plain `select` only) against CPL-316/317/318's own tables** --
--    grep-confirmed before this file was finalized: zero `insert`/`update`/
--    `delete` anywhere in this file against `app.loyalty_accounts`, `app.
--    loyalty_tier_definitions`, `app.loyalty_account_tier_movements`, `app.
--    loyalty_account_tier_holds`, `app.loyalty_point_balances`, `app.
--    loyalty_point_lots`, `app.loyalty_point_ledger_entries`, `app.loyalty_
--    benefit_entitlements`, or `app.loyalty_benefit_entitlement_events`.
-- 15. **RLS: `authenticated` holds ZERO direct grant** on either new table,
--    mirroring CPL-316/317/318/319 exactly -- the RPCs below are the only
--    sanctioned access path, for staff and customer callers alike. `app.
--    loyalty_reward_stock_reservations` is append-only (no `UPDATE`/
--    `DELETE` grant to any role, not even `service_role`, mirroring `app.
--    loyalty_benefit_entitlement_events`'s own identical choice).
-- 16. Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
--    carries its own explicit `revoke execute on all functions in schema
--    app from public` statement before its final grants.
-- 17. **Cursor pagination**: `(tenant_id, updated_at desc, id desc)` on
--    every list RPC, never `OFFSET`.

-- ===========================================================================
-- 1. app.loyalty_rewards -- draft -> published -> superseded, PER
-- (program_id, reward_name) lineage, plus paused/archived (design decision
-- 5). The single, staff-facing row shape (includes internal_cost/vendor_ref
-- -- design decision 8).
-- ===========================================================================

create table app.loyalty_rewards (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  program_id uuid not null references app.loyalty_programs (id),
  reward_name text not null,
  reward_type text not null,
  description text,
  terms_text text,
  min_tier_id uuid references app.loyalty_tier_definitions (id),
  min_points_required numeric,
  total_stock integer,
  internal_cost numeric,
  vendor_ref text,
  file_id uuid references app.files (id),
  version_number integer not null,
  status text not null default 'draft',
  effective_from timestamptz,
  effective_to timestamptz,
  published_by text,
  published_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint lr_reward_name_check check (length(trim(reward_name)) > 0),
  constraint lr_reward_type_check check (reward_type in ('discount_voucher', 'physical_item', 'service_credit')),
  constraint lr_status_check check (status in ('draft', 'published', 'paused', 'superseded', 'archived')),
  constraint lr_min_points_required_check check (min_points_required is null or min_points_required >= 0),
  constraint lr_total_stock_check check (total_stock is null or total_stock >= 0),
  constraint lr_internal_cost_check check (internal_cost is null or internal_cost >= 0),
  constraint lr_published_shape_check check (
    (status = 'draft' and published_by is null and published_at is null and effective_from is null)
    or (status in ('published', 'paused', 'superseded') and published_by is not null and published_at is not null and effective_from is not null)
    or (status = 'archived')
  ),
  constraint lr_superseded_shape_check check (status <> 'superseded' or effective_to is not null),
  constraint lr_program_reward_name_version_unique unique (program_id, reward_name, version_number)
);

comment on table app.loyalty_rewards is
  'CPL-320: NEVER mutate a published version''s own config in place -- a reward config change publishes a NEW version (app.publish_loyalty_reward); pause/resume/archive (app.pause_loyalty_reward/app.resume_loyalty_reward/app.archive_loyalty_reward) are plain status flips on the SAME row, never a new version (design decision 5, mirrors CPL-317''s own publish-time supersede-in-place pattern). At most one draft and at most one "live" (published or paused) row per (program_id, reward_name) at a time (partial unique indexes below). internal_cost/vendor_ref are staff-only -- structurally absent from every customer-facing RPC''s own RETURNS TABLE shape (design decision 8), not merely a query-level omission.';

create index lr_program_idx on app.loyalty_rewards (program_id);
create index lr_tenant_updated_id_idx on app.loyalty_rewards (tenant_id, updated_at desc, id desc);
create unique index lr_single_draft_per_reward on app.loyalty_rewards (program_id, reward_name) where status = 'draft';
create unique index lr_single_live_per_reward on app.loyalty_rewards (program_id, reward_name) where status in ('published', 'paused');

create function app.touch_loyalty_reward_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_rewards_touch_row
  before update on app.loyalty_rewards
  for each row
  execute function app.touch_loyalty_reward_row();

-- ===========================================================================
-- 2. app.loyalty_reward_stock_reservations -- APPEND-ONLY reservation
-- ledger (design decision 7). No UPDATE/DELETE grant to any role anywhere
-- in this migration, not even service_role -- mirrors app.loyalty_benefit_
-- entitlement_events' own identical choice. Only ever written by app.
-- reserve_loyalty_reward_stock_unit (production-uncalled in this
-- checkpoint -- design decision 7), plus this checkpoint's own db-test.
-- ===========================================================================

create table app.loyalty_reward_stock_reservations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  reward_id uuid not null references app.loyalty_rewards (id),
  quantity integer not null,
  reason text,
  created_by text,
  idempotency_key text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint lrsr_quantity_check check (quantity > 0),
  constraint lrsr_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.loyalty_reward_stock_reservations is
  'CPL-320: append-only reservation ledger -- one row per reserved unit-quantity against a reward with a finite total_stock. app.loyalty_rewards.stock_available is NEVER a stored/mirrored counter -- every read computes coalesce(sum(quantity), 0) over this table live (design decision 7), eliminating the "two numbers that could drift" defect class structurally. Race-safety comes from app.reserve_loyalty_reward_stock_unit''s own select...for update lock on the TARGET REWARD ROW (never on this table) taken before the aggregate is read -- live-proven under a real two-process race in this checkpoint''s own db-test.';

create index lrsr_tenant_reward_idx on app.loyalty_reward_stock_reservations (tenant_id, reward_id);

-- ===========================================================================
-- 3. app.create_loyalty_reward_draft -- staff, LYL:Create
-- ===========================================================================

create function app.create_loyalty_reward_draft(
  p_tenant_id uuid,
  p_program_id uuid,
  p_reward_name text,
  p_reward_type text,
  p_description text,
  p_terms_text text,
  p_min_tier_id uuid,
  p_min_points_required numeric,
  p_total_stock integer,
  p_internal_cost numeric,
  p_vendor_ref text,
  p_file_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_rewards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_program app.loyalty_programs;
  v_next_version integer;
  v_reward app.loyalty_rewards;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reward_name is null or length(trim(p_reward_name)) = 0 then
    raise exception 'invalid_reward_name: a non-empty reward name is required' using errcode = 'check_violation';
  end if;
  if p_reward_type is null or p_reward_type not in ('discount_voucher', 'physical_item', 'service_credit') then
    raise exception 'invalid_reward_type: % is not one of discount_voucher/physical_item/service_credit', p_reward_type using errcode = 'check_violation';
  end if;
  if p_min_points_required is not null and p_min_points_required < 0 then
    raise exception 'invalid_min_points_required: min_points_required must be non-negative, got %', p_min_points_required using errcode = 'check_violation';
  end if;
  if p_total_stock is not null and p_total_stock < 0 then
    raise exception 'invalid_total_stock: total_stock must be non-negative, got %', p_total_stock using errcode = 'check_violation';
  end if;
  if p_internal_cost is not null and p_internal_cost < 0 then
    raise exception 'invalid_internal_cost: internal_cost must be non-negative, got %', p_internal_cost using errcode = 'check_violation';
  end if;

  select * into v_program from app.loyalty_programs where id = p_program_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_program_not_found: %', p_program_id using errcode = 'no_data_found';
  end if;

  if p_min_tier_id is not null and not exists (
    select 1 from app.loyalty_tier_definitions where id = p_min_tier_id and tenant_id = p_tenant_id and program_id = p_program_id
  ) then
    raise exception 'invalid_min_tier_id: % is not a tier definition of program % in tenant %', p_min_tier_id, p_program_id, p_tenant_id using errcode = 'check_violation';
  end if;

  if p_file_id is not null and not exists (select 1 from app.files where id = p_file_id and tenant_id = p_tenant_id) then
    raise exception 'invalid_file_id: % is not a file of tenant %', p_file_id, p_tenant_id using errcode = 'check_violation';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version
    from app.loyalty_rewards where program_id = p_program_id and reward_name = trim(p_reward_name);

  begin
    insert into app.loyalty_rewards (
      tenant_id, program_id, reward_name, reward_type, description, terms_text, min_tier_id, min_points_required,
      total_stock, internal_cost, vendor_ref, file_id, version_number, created_by
    ) values (
      p_tenant_id, p_program_id, trim(p_reward_name), p_reward_type, p_description, p_terms_text, p_min_tier_id, p_min_points_required,
      p_total_stock, p_internal_cost, nullif(trim(coalesce(p_vendor_ref, '')), ''), p_file_id, v_next_version, p_actor_label
    )
    returning * into v_reward;
  exception
    when unique_violation then
      raise exception 'draft_already_exists: program % reward % already has an open draft version', p_program_id, trim(p_reward_name) using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_loyalty_reward_draft',
    'app.loyalty_rewards', v_reward.id, 'success', null, null, to_jsonb(v_reward)
  );

  return v_reward;
end;
$$;

comment on function app.create_loyalty_reward_draft is
  'CPL-320: at most one draft per (program, reward_name) at a time (lr_single_draft_per_reward) -- a real exception-handler-backed check, not a pre-check-only pattern.';

-- ===========================================================================
-- 4. app.update_loyalty_reward_draft -- staff, LYL:Edit, draft-only
-- ===========================================================================

create function app.update_loyalty_reward_draft(
  p_tenant_id uuid,
  p_reward_id uuid,
  p_expected_version integer,
  p_reward_name text,
  p_reward_type text,
  p_description text,
  p_terms_text text,
  p_min_tier_id uuid,
  p_min_points_required numeric,
  p_total_stock integer,
  p_internal_cost numeric,
  p_vendor_ref text,
  p_file_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_rewards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reward app.loyalty_rewards;
  v_updated app.loyalty_rewards;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reward_name is null or length(trim(p_reward_name)) = 0 then
    raise exception 'invalid_reward_name: a non-empty reward name is required' using errcode = 'check_violation';
  end if;
  if p_reward_type is null or p_reward_type not in ('discount_voucher', 'physical_item', 'service_credit') then
    raise exception 'invalid_reward_type: % is not one of discount_voucher/physical_item/service_credit', p_reward_type using errcode = 'check_violation';
  end if;
  if p_min_points_required is not null and p_min_points_required < 0 then
    raise exception 'invalid_min_points_required: min_points_required must be non-negative, got %', p_min_points_required using errcode = 'check_violation';
  end if;
  if p_total_stock is not null and p_total_stock < 0 then
    raise exception 'invalid_total_stock: total_stock must be non-negative, got %', p_total_stock using errcode = 'check_violation';
  end if;
  if p_internal_cost is not null and p_internal_cost < 0 then
    raise exception 'invalid_internal_cost: internal_cost must be non-negative, got %', p_internal_cost using errcode = 'check_violation';
  end if;

  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;

  -- NULL-bypass fix (design decision 11, Tier C review hardening, Batch 5
  -- close): explicit up-front rejection, not only the UPDATE's own
  -- repeated predicate -- a bare `<>` against a NULL p_expected_version
  -- evaluates to SQL NULL (falsy) and would otherwise silently fall
  -- through this check.
  if p_expected_version is null or v_reward.record_version <> p_expected_version then
    raise exception 'stale_version: reward % expected version % but found %', p_reward_id, p_expected_version, v_reward.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_reward.status <> 'draft' then
    raise exception 'invalid_transition: reward % is % -- only a draft may be edited', p_reward_id, v_reward.status
      using errcode = 'check_violation';
  end if;

  if p_min_tier_id is not null and not exists (
    select 1 from app.loyalty_tier_definitions where id = p_min_tier_id and tenant_id = p_tenant_id and program_id = v_reward.program_id
  ) then
    raise exception 'invalid_min_tier_id: % is not a tier definition of program % in tenant %', p_min_tier_id, v_reward.program_id, p_tenant_id using errcode = 'check_violation';
  end if;

  if p_file_id is not null and not exists (select 1 from app.files where id = p_file_id and tenant_id = p_tenant_id) then
    raise exception 'invalid_file_id: % is not a file of tenant %', p_file_id, p_tenant_id using errcode = 'check_violation';
  end if;

  begin
    update app.loyalty_rewards
    set reward_name = trim(p_reward_name), reward_type = p_reward_type, description = p_description, terms_text = p_terms_text,
        min_tier_id = p_min_tier_id, min_points_required = p_min_points_required, total_stock = p_total_stock,
        internal_cost = p_internal_cost, vendor_ref = nullif(trim(coalesce(p_vendor_ref, '')), ''), file_id = p_file_id
    -- NULL-bypass fix (design decision 11): the predicate is repeated here,
    -- not only in the preceding record_version <> p_expected_version check
    -- above -- a NULL p_expected_version correctly matches zero rows.
    where id = p_reward_id and record_version = p_expected_version
    returning * into v_updated;
  exception
    when unique_violation then
      raise exception 'draft_already_exists: program % reward % already has a different open draft version', v_reward.program_id, trim(p_reward_name) using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: reward % was concurrently modified (expected version %)', p_reward_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_loyalty_reward_draft',
    'app.loyalty_rewards', v_updated.id, 'success', null, null, to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 5. app.publish_loyalty_reward -- staff, LYL:Configure. Supersedes the
-- SAME (program_id, reward_name)'s own prior LIVE (published or paused)
-- version, if any, in the SAME transaction (design decision 5).
-- ===========================================================================

create function app.publish_loyalty_reward(
  p_tenant_id uuid,
  p_reward_id uuid,
  p_expected_version integer,
  p_effective_from timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_rewards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reward app.loyalty_rewards;
  v_prior_live app.loyalty_rewards;
  v_effective_from timestamptz;
  v_published app.loyalty_rewards;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;

  -- NULL-bypass fix (design decision 11, Tier C review hardening, Batch 5
  -- close): explicit up-front rejection, not only the UPDATE's own
  -- repeated predicate -- a bare `<>` against a NULL p_expected_version
  -- evaluates to SQL NULL (falsy) and would otherwise silently fall
  -- through this check.
  if p_expected_version is null or v_reward.record_version <> p_expected_version then
    raise exception 'stale_version: reward % expected version % but found %', p_reward_id, p_expected_version, v_reward.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_reward.status <> 'draft' then
    raise exception 'invalid_transition: reward % is % -- only a draft may be published', p_reward_id, v_reward.status
      using errcode = 'check_violation';
  end if;

  v_effective_from := coalesce(p_effective_from, clock_timestamp());

  select * into v_prior_live from app.loyalty_rewards
    where program_id = v_reward.program_id and reward_name = v_reward.reward_name and status in ('published', 'paused') for update;
  if found then
    update app.loyalty_rewards
      set status = 'superseded', effective_to = v_effective_from
      where id = v_prior_live.id;
  end if;

  begin
    update app.loyalty_rewards
      set status = 'published', published_by = p_actor_label, published_at = clock_timestamp(), effective_from = v_effective_from
      -- NULL-bypass fix (design decision 11).
      where id = p_reward_id and record_version = p_expected_version
      returning * into v_published;
  exception
    when unique_violation then
      raise exception 'reward_publish_conflict: program % reward % already has a live version', v_reward.program_id, v_reward.reward_name using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: reward % was concurrently modified (expected version %)', p_reward_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_published.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_loyalty_reward',
    'app.loyalty_rewards', v_published.id, 'success', null,
    case when v_prior_live.id is not null then jsonb_build_object('supersedes_reward_id', v_prior_live.id) else null end,
    to_jsonb(v_published)
  );

  return v_published;
end;
$$;

-- ===========================================================================
-- 6. app.pause_loyalty_reward / app.resume_loyalty_reward -- staff, LYL:
-- Configure. Plain status flips on the SAME row (design decisions 5, 6).
-- ===========================================================================

create function app.pause_loyalty_reward(
  p_tenant_id uuid,
  p_reward_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_rewards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reward app.loyalty_rewards;
  v_updated app.loyalty_rewards;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;

  -- NULL-bypass fix (design decision 11, Tier C review hardening, Batch 5
  -- close): explicit up-front rejection, not only the UPDATE's own
  -- repeated predicate -- a bare `<>` against a NULL p_expected_version
  -- evaluates to SQL NULL (falsy) and would otherwise silently fall
  -- through this check.
  if p_expected_version is null or v_reward.record_version <> p_expected_version then
    raise exception 'stale_version: reward % expected version % but found %', p_reward_id, p_expected_version, v_reward.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_reward.status <> 'published' then
    raise exception 'invalid_transition: reward % is % -- only a published reward may be paused', p_reward_id, v_reward.status
      using errcode = 'check_violation';
  end if;

  update app.loyalty_rewards
    set status = 'paused'
    -- NULL-bypass fix (design decision 11).
    where id = p_reward_id and record_version = p_expected_version
    returning * into v_updated;
  if not found then
    raise exception 'stale_version: reward % was concurrently modified (expected version %)', p_reward_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'pause_loyalty_reward',
    'app.loyalty_rewards', v_updated.id, 'success', p_reason, jsonb_build_object('status', 'published'), jsonb_build_object('status', 'paused')
  );

  return v_updated;
end;
$$;

comment on function app.pause_loyalty_reward is
  'CPL-320: reason is OPTIONAL (unlike CPL-317''s fraud-hold, which mandates one) -- pausing a reward is an ordinary merchandising/availability decision, not a governance/fraud action, disclosed as a deliberate departure from CPL-317''s own hold-reason-mandatory precedent.';

create function app.resume_loyalty_reward(
  p_tenant_id uuid,
  p_reward_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_rewards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reward app.loyalty_rewards;
  v_updated app.loyalty_rewards;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;

  -- NULL-bypass fix (design decision 11, Tier C review hardening, Batch 5
  -- close): explicit up-front rejection, not only the UPDATE's own
  -- repeated predicate -- a bare `<>` against a NULL p_expected_version
  -- evaluates to SQL NULL (falsy) and would otherwise silently fall
  -- through this check.
  if p_expected_version is null or v_reward.record_version <> p_expected_version then
    raise exception 'stale_version: reward % expected version % but found %', p_reward_id, p_expected_version, v_reward.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_reward.status <> 'paused' then
    raise exception 'invalid_transition: reward % is % -- only a paused reward may be resumed', p_reward_id, v_reward.status
      using errcode = 'check_violation';
  end if;

  update app.loyalty_rewards
    set status = 'published'
    -- NULL-bypass fix (design decision 11).
    where id = p_reward_id and record_version = p_expected_version
    returning * into v_updated;
  if not found then
    raise exception 'stale_version: reward % was concurrently modified (expected version %)', p_reward_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'resume_loyalty_reward',
    'app.loyalty_rewards', v_updated.id, 'success', null, jsonb_build_object('status', 'paused'), jsonb_build_object('status', 'published')
  );

  return v_updated;
end;
$$;

comment on function app.resume_loyalty_reward is
  'CPL-320: disclosed 6th function, the structural inverse of app.pause_loyalty_reward -- design decision 6. published_by/published_at are never touched (the original publish event is not re-authored, only availability is restored).';

-- ===========================================================================
-- 7. app.archive_loyalty_reward -- staff, LYL:Configure. Terminal from any
-- non-archived status.
-- ===========================================================================

create function app.archive_loyalty_reward(
  p_tenant_id uuid,
  p_reward_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_rewards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reward app.loyalty_rewards;
  v_updated app.loyalty_rewards;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;

  -- NULL-bypass fix (design decision 11, Tier C review hardening, Batch 5
  -- close): explicit up-front rejection, not only the UPDATE's own
  -- repeated predicate -- a bare `<>` against a NULL p_expected_version
  -- evaluates to SQL NULL (falsy) and would otherwise silently fall
  -- through this check.
  if p_expected_version is null or v_reward.record_version <> p_expected_version then
    raise exception 'stale_version: reward % expected version % but found %', p_reward_id, p_expected_version, v_reward.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_reward.status = 'archived' then
    raise exception 'invalid_transition: reward % is already archived', p_reward_id using errcode = 'check_violation';
  end if;

  update app.loyalty_rewards
    set status = 'archived'
    -- NULL-bypass fix (design decision 11).
    where id = p_reward_id and record_version = p_expected_version
    returning * into v_updated;
  if not found then
    raise exception 'stale_version: reward % was concurrently modified (expected version %)', p_reward_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_loyalty_reward',
    'app.loyalty_rewards', v_updated.id, 'success', p_reason, jsonb_build_object('status', v_reward.status), jsonb_build_object('status', 'archived')
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 8. app.reserve_loyalty_reward_stock_unit -- staff/system, LYL:Edit. The
-- real, race-safe stock primitive (design decision 7). Never called by any
-- production path in this checkpoint -- only this checkpoint's own db-test,
-- ready for CPL-321 to compose.
-- ===========================================================================

create function app.reserve_loyalty_reward_stock_unit(
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
  v_reserved integer;
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

  -- Design decision 7: locking the TARGET REWARD ROW (never the ledger
  -- table) is what makes this primitive genuinely race-safe -- every call
  -- for the SAME reward serializes here, before the aggregate below is
  -- read, so two concurrent callers can never both observe the same stale
  -- "still have room" total.
  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;

  if v_reward.status <> 'published' then
    raise exception 'reward_not_available_for_reservation: reward % is % -- only a published reward accepts stock reservations', p_reward_id, v_reward.status
      using errcode = 'check_violation';
  end if;

  select coalesce(sum(quantity), 0) into v_reserved from app.loyalty_reward_stock_reservations where tenant_id = p_tenant_id and reward_id = p_reward_id;

  if v_reward.total_stock is not null and v_reserved + p_quantity > v_reward.total_stock then
    raise exception 'insufficient_reward_stock: reward % has % of % units already reserved, cannot reserve % more', p_reward_id, v_reserved, v_reward.total_stock, p_quantity
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.loyalty_reward_stock_reservations (tenant_id, reward_id, quantity, reason, created_by, idempotency_key)
    values (p_tenant_id, p_reward_id, p_quantity, p_reason, p_actor_label, p_idempotency_key)
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
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'reserve_loyalty_reward_stock_unit',
    'app.loyalty_rewards', p_reward_id, 'success', p_reason, jsonb_build_object('reserved_before', v_reserved),
    jsonb_build_object('reserved_after', v_reserved + p_quantity, 'total_stock', v_reward.total_stock)
  );

  return v_reservation;
end;
$$;

comment on function app.reserve_loyalty_reward_stock_unit is
  'CPL-320: idempotent on (tenant_id, idempotency_key). Never re-validates a caller''s own tier/points eligibility or the reward''s own effective-date window -- CPL-321''s own future redemption RPC is responsible for both, BEFORE composing this primitive (mirrors app.consume_loyalty_points_fifo, CPL-318, a pure ledger-arithmetic primitive with the identical boundary). Not called by any production path in this checkpoint -- design decision 7.';

-- ===========================================================================
-- 9. app.get_loyalty_reward / app.list_loyalty_rewards -- staff, LYL:View.
-- Full internal projection (includes internal_cost/vendor_ref).
-- ===========================================================================

create function app.get_loyalty_reward(p_tenant_id uuid, p_reward_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_rewards
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reward app.loyalty_rewards;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;

  return v_reward;
end;
$$;

create function app.list_loyalty_rewards(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_program_id uuid default null,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_rewards
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
  select r.* from app.loyalty_rewards r
  where r.tenant_id = p_tenant_id
    and (p_program_id is null or r.program_id = p_program_id)
    and (p_status is null or r.status = p_status)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

comment on function app.list_loyalty_rewards is
  'CPL-320: p_program_id is OPTIONAL (unlike CPL-317''s own required-per-program list) -- a staff catalogue browse benefits from an all-programs view, disclosed departure from CPL-317''s own convention.';

-- ===========================================================================
-- 10. app.list_customer_portal_loyalty_rewards -- customer-facing (Layer 4,
-- ADR-0024 Part A). Deny-by-default. Never exposes internal_cost/vendor_ref
-- (design decision 8, structural). Computes eligible/locked/out_of_stock/
-- unavailable per row (source prompt section 21/22).
-- ===========================================================================

create function app.list_customer_portal_loyalty_rewards(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_actor_auth_user_id uuid,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  reward_id uuid,
  program_id uuid,
  program_name text,
  reward_name text,
  reward_type text,
  description text,
  display_state text,
  min_tier_name text,
  min_points_required numeric,
  customer_current_points numeric,
  total_stock integer,
  stock_available integer,
  effective_from timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_account app.loyalty_accounts;
  v_current_tier_rank integer;
  v_current_points numeric;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  -- Deny-by-default (ADR-0024 Part A): an out-of-scope/nonexistent/
  -- non-active loyalty account all short-circuit to an empty result, never
  -- an error -- mirrors every other Phase 8 customer-facing list RPC.
  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;

  select a.* into v_account from app.loyalty_accounts a where a.id = p_loyalty_account_id and a.tenant_id = p_tenant_id;
  if not found or v_account.status <> 'active' or not (v_account.customer_account_id = any (v_scope)) then
    return;
  end if;

  -- Design decision 4: current tier rank derived exactly as CPL-317's own
  -- app.list_customer_portal_loyalty_tier_cards derives it -- latest
  -- app.loyalty_account_tier_movements row, joined to its own to_tier_id's
  -- tier_rank. Never reads app.loyalty_account_tier_holds (design
  -- decision 4).
  select td.tier_rank into v_current_tier_rank
  from app.loyalty_account_tier_movements tm
  join app.loyalty_tier_definitions td on td.id = tm.to_tier_id
  where tm.tenant_id = p_tenant_id and tm.loyalty_account_id = v_account.id
  order by tm.created_at desc, tm.id desc
  limit 1;

  v_current_points := coalesce((select pb.available from app.loyalty_point_balances pb where pb.tenant_id = p_tenant_id and pb.loyalty_account_id = v_account.id), 0);

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select
    r.id,
    r.program_id,
    p.name,
    r.reward_name,
    r.reward_type,
    r.description,
    case
      when r.status = 'paused' then 'unavailable'
      when (r.min_tier_id is not null and (v_current_tier_rank is null or v_current_tier_rank < mt.tier_rank))
        or (r.min_points_required is not null and v_current_points < r.min_points_required) then 'locked'
      when r.total_stock is not null and coalesce(res.reserved, 0) >= r.total_stock then 'out_of_stock'
      else 'eligible'
    end,
    mt.tier_name,
    r.min_points_required,
    v_current_points,
    r.total_stock,
    case when r.total_stock is null then null else r.total_stock - coalesce(res.reserved, 0) end,
    r.effective_from,
    r.updated_at
  from app.loyalty_rewards r
  join app.loyalty_programs p on p.id = r.program_id
  left join app.loyalty_tier_definitions mt on mt.id = r.min_tier_id
  left join lateral (
    select coalesce(sum(lrsr.quantity), 0)::integer as reserved from app.loyalty_reward_stock_reservations lrsr where lrsr.tenant_id = p_tenant_id and lrsr.reward_id = r.id
  ) res on true
  where r.tenant_id = p_tenant_id
    and r.program_id = v_account.program_id
    and r.status in ('published', 'paused')
    and r.effective_from <= clock_timestamp()
    and (r.effective_to is null or r.effective_to > clock_timestamp())
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_loyalty_rewards is
  'CPL-320: customer-safe catalogue projection -- never exposes internal_cost/vendor_ref (design decision 8, structural). A reward not yet effective, already expired, archived, superseded, or in draft simply does not appear at all; a PAUSED reward surfaces as display_state=''unavailable'' rather than being hidden entirely (source prompt: "customers see safe unavailable state without stale redemption paths," this checkpoint''s own disclosed choice). Deny-by-default: an out-of-scope/nonexistent/non-active loyalty account returns zero rows, never an error.';

-- ===========================================================================
-- 11. app.get_customer_portal_loyalty_reward -- customer-facing reward
-- detail. Same eligibility/stock projection as above for ONE reward, plus a
-- malware-scan-gated reference to the reward's own terms file (design
-- decision 9).
-- ===========================================================================

create function app.get_customer_portal_loyalty_reward(
  p_tenant_id uuid,
  p_reward_id uuid,
  p_loyalty_account_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  reward_id uuid,
  program_id uuid,
  program_name text,
  reward_name text,
  reward_type text,
  description text,
  terms_text text,
  display_state text,
  min_tier_name text,
  min_points_required numeric,
  customer_current_points numeric,
  total_stock integer,
  stock_available integer,
  effective_from timestamptz,
  has_terms_file boolean,
  terms_file_scan_status text,
  terms_file_name text,
  terms_file_mime_type text,
  terms_file_size_bytes bigint,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_account app.loyalty_accounts;
  v_reward app.loyalty_rewards;
  v_program app.loyalty_programs;
  v_min_tier app.loyalty_tier_definitions;
  v_current_tier_rank integer;
  v_current_points numeric;
  v_reserved integer;
  v_display_state text;
  v_file app.files;
  v_scan_status text;
  v_file_name text;
  v_file_mime text;
  v_file_size bigint;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;

  select a.* into v_account from app.loyalty_accounts a where a.id = p_loyalty_account_id and a.tenant_id = p_tenant_id;
  if not found or v_account.status <> 'active' or not (v_account.customer_account_id = any (v_scope)) then
    -- Anti-enumeration: an out-of-scope account and a genuinely nonexistent
    -- reward collapse into the IDENTICAL error, never a distinguishable
    -- signal about which reason applies.
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;

  select r.* into v_reward
  from app.loyalty_rewards r
  where r.id = p_reward_id and r.tenant_id = p_tenant_id and r.program_id = v_account.program_id
    and r.status in ('published', 'paused') and r.effective_from <= clock_timestamp() and (r.effective_to is null or r.effective_to > clock_timestamp());
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;

  select * into v_program from app.loyalty_programs where id = v_reward.program_id;

  if v_reward.min_tier_id is not null then
    select * into v_min_tier from app.loyalty_tier_definitions where id = v_reward.min_tier_id;
  end if;

  select td.tier_rank into v_current_tier_rank
  from app.loyalty_account_tier_movements tm
  join app.loyalty_tier_definitions td on td.id = tm.to_tier_id
  where tm.tenant_id = p_tenant_id and tm.loyalty_account_id = v_account.id
  order by tm.created_at desc, tm.id desc
  limit 1;

  v_current_points := coalesce((select pb.available from app.loyalty_point_balances pb where pb.tenant_id = p_tenant_id and pb.loyalty_account_id = v_account.id), 0);

  select coalesce(sum(lrsr.quantity), 0) into v_reserved from app.loyalty_reward_stock_reservations lrsr where lrsr.tenant_id = p_tenant_id and lrsr.reward_id = v_reward.id;

  v_display_state := case
    when v_reward.status = 'paused' then 'unavailable'
    when (v_reward.min_tier_id is not null and (v_current_tier_rank is null or v_current_tier_rank < v_min_tier.tier_rank))
      or (v_reward.min_points_required is not null and v_current_points < v_reward.min_points_required) then 'locked'
    when v_reward.total_stock is not null and v_reserved >= v_reward.total_stock then 'out_of_stock'
    else 'eligible'
  end;

  -- Design decision 9: mirrors CPL-307/CPL-308's own established private-
  -- file access pattern -- app.file_access_logs, access_type=
  -- 'metadata_view' (never a fabricated 'signed_url_issued', no live
  -- signed-URL primitive exists in this repository). Only this DETAIL RPC
  -- writes a file_access_logs row -- never the LIST RPC (design decision 9).
  if v_reward.file_id is not null then
    select * into v_file from app.files where id = v_reward.file_id and tenant_id = p_tenant_id;
    if found then
      v_scan_status := v_file.malware_scan_status;
      insert into app.file_access_logs (tenant_id, file_id, accessed_by_auth_user_id, access_type, result, reason, correlation_id)
      values (
        p_tenant_id, v_file.id, p_actor_auth_user_id, 'metadata_view',
        case when v_scan_status = 'clean' then 'granted' else 'denied' end,
        case
          when v_scan_status = 'clean' then null
          when v_scan_status = 'infected' then 'document_infected_quarantined'
          else 'document_not_yet_scanned'
        end,
        null
      );
      if v_scan_status = 'clean' then
        v_file_name := v_file.original_filename;
        v_file_mime := v_file.mime_type;
        v_file_size := v_file.size_bytes;
      end if;
    end if;
  end if;

  return query
  select
    v_reward.id, v_reward.program_id, v_program.name, v_reward.reward_name, v_reward.reward_type, v_reward.description, v_reward.terms_text,
    v_display_state, v_min_tier.tier_name, v_reward.min_points_required, v_current_points,
    v_reward.total_stock, case when v_reward.total_stock is null then null else v_reward.total_stock - v_reserved end,
    v_reward.effective_from,
    v_reward.file_id is not null, v_scan_status, v_file_name, v_file_mime, v_file_size,
    v_reward.updated_at;
end;
$$;

comment on function app.get_customer_portal_loyalty_reward is
  'CPL-320: same eligibility/stock projection as app.list_customer_portal_loyalty_rewards for ONE reward. Anti-enumerating: a genuinely nonexistent reward, an out-of-scope loyalty account, a cross-program reward, and a not-yet-effective/expired/archived/superseded/draft reward all collapse into the identical loyalty_reward_not_found error. terms_file_* fields are populated only when malware_scan_status=''clean'' -- a non-clean file still reports its own real scan status (never hidden or defaulted) but never its metadata (design decision 9).';

-- ===========================================================================
-- 12. RLS -- enable, grant service_role only (design decision 15).
-- ===========================================================================

alter table app.loyalty_rewards enable row level security;
alter table app.loyalty_reward_stock_reservations enable row level security;

grant select, insert, update on app.loyalty_rewards to service_role;
grant select, insert on app.loyalty_reward_stock_reservations to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.create_loyalty_reward_draft(uuid, uuid, text, text, text, text, uuid, numeric, integer, numeric, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.update_loyalty_reward_draft(uuid, uuid, integer, text, text, text, text, uuid, numeric, integer, numeric, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.publish_loyalty_reward(uuid, uuid, integer, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.pause_loyalty_reward(uuid, uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.resume_loyalty_reward(uuid, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.archive_loyalty_reward(uuid, uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.reserve_loyalty_reward_stock_unit(uuid, uuid, integer, text, uuid, text, text) to authenticated, service_role;
grant execute on function app.get_loyalty_reward(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_rewards(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_portal_loyalty_rewards(uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.get_customer_portal_loyalty_reward(uuid, uuid, uuid, uuid) to authenticated, service_role;
