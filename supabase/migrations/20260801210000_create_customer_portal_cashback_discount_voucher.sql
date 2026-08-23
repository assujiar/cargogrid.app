-- Phase 8 capability CPL-319 (CG-S13-CPL-021, Prompt 319, "Cashback Discount
-- Voucher") -- the FOURTH Loyalty-domain capability in this repository
-- (ADR-0024 Part D), and the fifth and final prompt of Batch 4 (CPL-315..319).
-- Read docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-pattern.md
-- Part D; supabase/migrations/20260730190000_create_advanced_tms_inventory_
-- ledger.sql; docs/build-log/phase-08/CPL-316.md, CPL-317.md, CPL-318.md and
-- their own migrations (20260801180000/190000/200000) IN FULL before writing
-- any of this file. This migration READS app.loyalty_accounts (CPL-316) --
-- it never INSERTs/UPDATEs/DELETEs against it, or against any CPL-317/318
-- table, confirmed by grep before this file was finalized.
--
-- SCOPE BOUNDARY (disclosed, orchestrator-directed -- not a silent omission):
-- ADR-0024 Part D's own general shape for Loyalty-liability-to-Finance
-- names a Loyalty-owned handoff-batch table + idempotent generator + Finance
-- acknowledgement RPC, mirroring HRT-282's prepare_finance_*_from_* shape,
-- plus a FIN-209-shaped execute/resolve-then-certify reconciliation pair.
-- NONE of that is built in this migration -- it is explicitly CPL-323's own
-- future scope ("Liability Reconciliation Analytics"), per this checkpoint's
-- own orchestrating task instruction. This checkpoint's own job is narrower
-- and already complete on its own terms: record entitlement value/currency/
-- status/issued_at/source CLEANLY and ACCURATELY so a future CPL-323 can
-- read app.loyalty_benefit_entitlements/app.loyalty_benefit_entitlement_
-- events and build the handoff-batch/reconciliation layer on top, exactly
-- the same "domain stays source of truth, Finance handoff is a later,
-- separate step" discipline HRT-282 already established, just not built
-- here. Recorded again in docs/runtime/KNOWN_ISSUES.md (ISS-2026-129).
--
-- ===========================================================================
-- Design decisions (disclosed, not re-derived)
-- ===========================================================================
--
-- 1. **Two tables, but NOT the same append-only/mutable split CPL-316/317/318
--    each used for their own "ledger + derived balance" pair.**
--    app.loyalty_benefit_entitlements is the single, MUTABLE, authoritative
--    current-state row per issued benefit -- it already needs direct UPDATEs
--    for its own status lifecycle (issued -> redeemed/reversed/expired/held
--    -> issued), exactly mirroring app.loyalty_point_lots / app.inventory_
--    balances / app.inventory_reservations' own already-established
--    "mutable current-state row, mutated only by its owning function" shape,
--    NOT app.loyalty_point_ledger_entries' append-only shape. There is no
--    separate aggregate "wallet balance" table this checkpoint derives --
--    each entitlement IS its own value/status, a complete unit on its own
--    (the source prompt's own schema never asks for a rolled-up per-account
--    total). app.loyalty_benefit_entitlement_events is the genuinely
--    append-only lifecycle log (no UPDATE/DELETE grant to any role anywhere
--    in this file, mirroring app.loyalty_earning_events/app.loyalty_point_
--    ledger_entries exactly) -- every status transition writes exactly one
--    new event row here, the entitlement row itself is never deleted or
--    rewritten to erase history, only transitioned forward.
-- 2. **Voucher/coupon code generation is a NEW design decision, not a
--    claimed reuse of the repository's existing hashed-bearer-secret
--    pattern** (app.api_keys/app.quotation_acceptance_tokens/app.shipment_
--    tracking_tokens -- grep-confirmed, all three use `encode(gen_random_
--    bytes(24 or 32), 'hex')`, a 48-64 character machine-oriented secret,
--    never intended to be hand-typed). This checkpoint's own voucher code is
--    deliberately SHORTER and human-typeable: `encode(gen_random_bytes(5),
--    'base32')` yields exactly 8 base32 characters with ZERO padding (5
--    bytes = 40 bits = exactly 8 quintets, no partial group), formatted
--    `'CGV-' || first 4 chars || '-' || last 4 chars` (e.g. `CGV-K7M2-QX9B`)
--    -- 40 bits of entropy (~1.1 x 10^12 possible codes), which the same
--    hash-only-storage PRINCIPLE those three precedents established still
--    governs: only `code_hash` (`encode(digest(raw_code, 'sha256'), 'hex')`)
--    is ever stored, globally UNIQUE (never tenant-scoped -- mirrors
--    api_keys.key_hash/quotation_acceptance_tokens.token_hash being global
--    too, so no cross-tenant code collision is even structurally possible),
--    and the raw code is returned exactly once, by app.issue_loyalty_
--    benefit_entitlement's own return row, on a genuine first issuance only
--    -- NEVER on an idempotent replay (design decision 6) and never logged
--    (grep-confirmed: the raw code touches no `capture_audit_event` call,
--    no `raise notice`, nothing but the function's own return row).
--    `app.issue_loyalty_benefit_entitlement`/`app.redeem_loyalty_benefit_
--    entitlement` (the two functions that actually call `gen_random_bytes`/
--    `digest`) each set `search_path = app, public, pg_temp` (not the
--    otherwise-uniform `app, pg_temp` every other function in this file
--    uses) -- `pgcrypto` lives in `public` (`20260716075355_create_tenants.
--    sql`), and this is the identical, already-established precedent
--    `app.issue_shipment_tracking_token` (`20260728130000_create_
--    operations_public_tracking.sql`) already uses for the same reason, not
--    a new or weakened convention.
-- 3. **Fraud hold mirrors CPL-317's own GOVERNING PRINCIPLES, adapted to a
--    different append-only/mutable table boundary, not its literal separate-
--    table MECHANISM copied unconditionally.** CPL-317 built a SEPARATE
--    mutable `app.loyalty_account_tier_holds` table specifically because its
--    own core object (`app.loyalty_account_tier_movements`) is append-only
--    -- an inline hold column there would require mutating a past, already-
--    posted movement row, which CPL-317's own build log explicitly rejected.
--    That constraint does not apply here: `app.loyalty_benefit_entitlements`
--    is ALREADY a mutable, single-row-per-entitlement table (design decision
--    1) -- exactly as mutable as CPL-317's OWN `loyalty_account_tier_holds`
--    itself (never its movements table). This prompt's own literal schema
--    also lists `'held'` as a real `status` value and `is_fraud_hold`/
--    `hold_reason` as columns directly on the entitlement row -- putting a
--    THIRD, independently-drifting hold table beside a status column that
--    can ALSO independently say `'held'` would be exactly the double-
--    bookkeeping CPL-317's own design reasoning warns against ("no other
--    function or direct table write ever changes it" -- one governed state,
--    one column family). This checkpoint therefore keeps CPL-317's real
--    governing rules -- a mandatory non-empty reason, `held_by`/`held_at`/
--    `released_by`/`released_at` provenance, redemption blocked while held,
--    a customer-safe generic notice that NEVER carries the real internal
--    `hold_reason` -- but implements them INLINE on the entitlement row,
--    with a real `CHECK` constraint (`lbe_status_hold_consistency_check`,
--    `(status = 'held') = is_fraud_hold`) as the single source of truth,
--    never two independently-evolving flags. `status = 'held'` structurally
--    IS "not redeemable" (mutually exclusive with `'issued'`), so app.
--    redeem_loyalty_benefit_entitlement's own `status <> 'issued'` check
--    already enforces "blocks usage while held" with no separate lookup.
-- 4. **The CPL-318 ledger-insert-before-mutation ordering lesson has no
--    directly analogous balance/cap mutation step to apply it to here --
--    disclosed explicitly, not silently skipped.** CPL-318's own bug class
--    was: a SEPARATE aggregate-balance table mutated BEFORE the append-only
--    ledger row's own idempotency-establishing INSERT, so a losing
--    concurrent racer's caught INSERT exception left its own EARLIER balance
--    mutation committed, double-counting. This checkpoint has no analogous
--    separate balance table (design decision 1) -- the entitlement row IS
--    the balance. The SAME underlying discipline is still applied
--    defensively throughout: in every function below, the entitlement row's
--    own INSERT/UPDATE (which doubles as BOTH the idempotency claim on
--    issuance, via `unique(tenant_id, idempotency_key)`, AND the atomic
--    status-transition guard on every other mutation, via `where id = ...
--    and status = '<expected>'`) always happens strictly BEFORE the
--    corresponding `app.loyalty_benefit_entitlement_events` INSERT -- a
--    losing racer's own exception or zero-rows-affected no-op fires before
--    any event/audit row is ever written for that specific attempt, so the
--    append-only event log can never contain an event for a transition that
--    did not actually, atomically happen to the entitlement row itself.
-- 5. **Redemption is the FIRST genuinely customer-initiated WRITE anywhere
--    in the Loyalty domain** (CPL-316 §11, CPL-317 §11, CPL-318's own
--    mutations file header all explicitly disclose ZERO customer-initiated
--    writes through this checkpoint). This prompt's own explicit instruction
--    ("customer-facing benefit wallet ... redeem action for vouchers") asks
--    for exactly that. Reasoned as compatible with ADR-0024 Part B, which
--    governs a customer directly calling a STAFF-RBAC-gated CANONICAL
--    mutation of an ALREADY-EXISTING, DIFFERENT domain (Commercial/Finance/
--    Ops quotations/shipments/invoices) -- redeeming one's OWN Loyalty-owned
--    entitlement is this domain's own internal action, authored by this same
--    prompt, not a bypass of another domain's canonical record; every
--    customer-initiated call is still scoped through the SAME real
--    `app.resolve_customer_account_scope` mechanism CPL-316/317/318 already
--    use for every customer-facing READ, extended here (for the first time)
--    to gate a WRITE too. `app.redeem_loyalty_benefit_entitlement` is ONE
--    function (the source prompt's own literal signature,
--    `p_entitlement_id_or_code`), with two lookup shapes:
--      (a) **ID path** (the parameter parses as a `uuid`): reachable by
--          staff (`LYL:Edit`, any entitlement in the tenant) OR by the
--          entitlement's own OWNING customer (`app.resolve_customer_
--          account_scope` includes the entitlement's own loyalty account's
--          `customer_account_id`) -- ordinary, distinguishable errors are
--          fine here, since the caller already legitimately KNOWS this id
--          (from a staff admin listing or from their own already-scoped
--          wallet listing), never a value an attacker could usefully guess
--          (a `uuid` is 122 bits of real randomness).
--      (b) **CODE path** (does not parse as a `uuid`): voucher-only,
--          `code_hash = digest(supplied_code, 'sha256')`, NEVER a plaintext
--          comparison. Reachable by staff OR by ANY authenticated customer_
--          user (their own resolved scope constrains which entitlement a
--          given code may legitimately belong to for them). FULLY anti-
--          enumerating: a forged code, a code belonging to a different
--          tenant, a real voucher code belonging to a DIFFERENT customer
--          than the caller, an already-redeemed/reversed/expired code, a
--          held code, and a stale-version mismatch ALL collapse into the
--          IDENTICAL error text and errcode
--          (`voucher_redemption_failed: this voucher code cannot be
--          redeemed`, `no_data_found`) -- proven live and adversarially in
--          this checkpoint's own db-test (every one of those distinct
--          failure causes asserted to produce byte-identical SQLERRM text).
-- 6. **`p_expected_version` is NULLABLE on redemption specifically -- the
--    ONE deliberate departure from every other real, non-null optimistic-
--    concurrency check in this migration/domain.** A caller redeeming by a
--    bare voucher CODE has, by construction, no visibility into the target
--    row's own current `record_version` (they only ever hold the code
--    itself). The underlying `update ... where id = ... and status =
--    'issued'` transition is ALREADY a complete, race-safe concurrency guard
--    on its own -- PostgreSQL serializes concurrent `UPDATE`s against the
--    identical row at the row level, so a losing concurrent racer's own
--    `WHERE status = 'issued'` re-evaluates against the winner's already-
--    committed `'redeemed'` state and matches zero rows, failing closed
--    (mirrors `app.record_quotation_customer_decision`'s own identical
--    `update ... where status = 'active'` single-use-consumption guard, the
--    closest existing precedent). When a caller DOES know the row's current
--    version (the wallet's own per-row "Redeem" button, which already holds
--    the listed row's own `recordVersion`; any staff admin redemption by
--    id), it is passed and additionally, genuinely checked -- a real
--    defense-in-depth staleness signal, never silently bypassed when
--    supplied.
-- 7. **`value_cap` enforcement (`value_amount` may never exceed `value_cap`
--    when both are set) is BOTH a real table `CHECK` constraint
--    (`lbe_value_cap_bound_check`) AND a procedural guard evaluated inside
--    `app.issue_loyalty_benefit_entitlement` before any write** -- the same
--    "authoritative procedural guard, real `CHECK` constraint as defense-in-
--    depth backstop" dual shape CPL-318 already established for negative-
--    balance prevention, applied here to this checkpoint's own analogous
--    cap-enforcement rule. Proven live, adversarially, in this checkpoint's
--    own db-test.
-- 8. **`clock_timestamp()`, never `now()`**, for every timestamptz column
--    whose ordering matters or whose table could plausibly receive more than
--    one row/update within the same transaction -- the CPL-315 self-found
--    defect class, applied proactively throughout (as CPL-317/318 already
--    did), including every `created_at`/`updated_at`/`held_at`/
--    `released_at` in this file and the touch-row trigger.
-- 9. **Every actor-taking function calls `app.assert_actor_is_session_
--    identity` as its own literal FIRST statement.** Every staff mutate/
--    get-by-id RPC checks `LYL:*` authority BEFORE fetching its target row
--    (C-05, mirrors CPL-316/317/318's own design decision 3/11/10 exactly).
--    `app.redeem_loyalty_benefit_entitlement` resolves BOTH `v_is_staff` and
--    `v_customer_scope` before touching `app.loyalty_benefit_entitlements`
--    at all -- the coarse "does this caller have ANY standing whatsoever"
--    check happens before any row is read, exactly mirroring the same
--    discipline applied to a dual-authority function.
-- 10. **LYL permission mapping, reused from CPL-316/317/318 unchanged** (LYL
--    still has no `Approve` action). Ordinary posting (issuance, the tenant-
--    wide expiry scan) -> `LYL:Edit`. The two governance-grade actions --
--    reversing an already-issued/held/redeemed entitlement, and asserting/
--    releasing a fraud hold -- both map to the elevated `LYL:Configure`,
--    mirroring CPL-316's `publish_loyalty_program_rule_version`/`reverse_
--    loyalty_earning_event` and CPL-317's `publish_loyalty_tier_definition`/
--    hold-benefits mapping exactly. Staff reads -> `LYL:View`. Redemption is
--    the one dual-authority function (design decision 5). Customer-facing
--    reads -> scoped via `app.resolve_customer_account_scope` only, no
--    staff RBAC check, mirroring CPL-316/317/318 exactly.
-- 11. **Never mutate a derived/state field outside its own owning function,
--    never delete or rewrite an existing `app.loyalty_benefit_entitlement_
--    events` row.** No `UPDATE`/`DELETE` grant to `authenticated` on either
--    new table; no function in this migration issues `UPDATE`/`DELETE`
--    against `app.loyalty_benefit_entitlement_events` at all (append-only,
--    insert-only, grep-confirmed).
-- 12. **RLS: `authenticated` holds ZERO direct grant** on either new table,
--    mirroring CPL-316/317/318 exactly -- the RPCs below are the only
--    sanctioned access path, for staff and customer callers alike.
--    `docs/architecture/06_RLS_RBAC_WORKSTREAM.md` §4/§8/§13 (RPD-022)
--    names `cashback_ledger` inside the repository's `append_only_ledger`
--    policy family and calls a per-table Supreme-Admin-exception override
--    policy a release-blocker gate -- acknowledged here explicitly (Tier C
--    review addition; the original text of this migration did not cite it
--    at all, unlike CPL-318's own design decision 13 for `point_ledger`).
--    Not implemented in this checkpoint, for the identical reason CPL-316/
--    317/318 already gave for their own sibling ledger tables: no concrete
--    Supreme-Admin-override mechanism (the FIN-204-shaped trigger pattern)
--    exists anywhere in the Loyalty domain yet, and the closest precedent
--    file this batch was told to read (`app.inventory_movements`,
--    `20260730190000_create_advanced_tms_inventory_ledger.sql`) has none
--    either -- an already-accepted, repository-wide-shaped gap, not a new
--    one this checkpoint introduces. `service_role` itself holds no
--    `UPDATE`/`DELETE` grant on `app.loyalty_benefit_entitlement_events`
--    (append-only, insert-only), so today literally no ordinary
--    application-level role can mutate a posted event row. Disclosed as
--    `ISS-2026-130` (`docs/runtime/KNOWN_ISSUES.md`), covering all four
--    Loyalty ledger tables (`loyalty_earning_events`/`loyalty_account_
--    tier_movements`/`loyalty_point_ledger_entries`/`loyalty_benefit_
--    entitlement_events`) at once, rather than re-registered per table.
-- 13. **Zero reads or writes against CPL-317/318's own tables** -- grep-
--    confirmed before this file was finalized: zero reference at all to
--    `app.loyalty_tier_definitions`/`app.loyalty_account_tier_movements`/
--    `app.loyalty_account_tier_holds`/`app.loyalty_point_lots`/`app.
--    loyalty_point_ledger_entries`/`app.loyalty_point_balances`/`app.
--    loyalty_point_adjustment_requests` anywhere in this file; the only
--    read against `app.loyalty_accounts` (CPL-316) is a plain `select`.
-- 14. Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
--    carries its own explicit `revoke execute on all functions in schema app
--    from public` statement before its final grants.

-- ===========================================================================
-- 1. app.loyalty_benefit_entitlements -- the single, MUTABLE, authoritative
-- current-state row per issued benefit (design decision 1).
-- ===========================================================================

create table app.loyalty_benefit_entitlements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  loyalty_account_id uuid not null references app.loyalty_accounts (id),
  benefit_type text not null,
  value_amount numeric not null,
  value_cap numeric,
  currency text not null,
  status text not null default 'issued',
  code_hash text unique,
  source_type text not null,
  source_id uuid,
  expires_at timestamptz,
  config_version integer not null default 1,
  idempotency_key text not null,
  is_fraud_hold boolean not null default false,
  hold_reason text,
  held_by text,
  held_at timestamptz,
  released_by text,
  released_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint lbe_benefit_type_check check (benefit_type in ('cashback', 'discount', 'voucher')),
  constraint lbe_value_amount_check check (value_amount > 0),
  constraint lbe_value_cap_check check (value_cap is null or value_cap > 0),
  constraint lbe_value_cap_bound_check check (value_cap is null or value_amount <= value_cap),
  constraint lbe_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint lbe_status_check check (status in ('issued', 'redeemed', 'reversed', 'expired', 'held')),
  constraint lbe_code_shape_check check (benefit_type = 'voucher' or code_hash is null),
  constraint lbe_source_type_check check (length(trim(source_type)) > 0),
  constraint lbe_hold_shape_check check ((is_fraud_hold = false) or (hold_reason is not null and held_by is not null and held_at is not null)),
  constraint lbe_status_hold_consistency_check check ((status = 'held') = is_fraud_hold),
  constraint lbe_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.loyalty_benefit_entitlements is
  'CPL-319: one row per issued cashback/discount/voucher benefit. Mutated exclusively by app.issue_loyalty_benefit_entitlement/app.redeem_loyalty_benefit_entitlement/app.reverse_loyalty_benefit_entitlement/app.expire_loyalty_benefit_entitlements/app.hold_loyalty_benefit_entitlement/app.release_loyalty_benefit_entitlement_hold -- no other function or direct table write ever changes it (design decision 1). code_hash is populated for benefit_type=''voucher'' only (design decision 2, code_shape_check) -- the RAW code is never persisted anywhere, returned exactly once by the issuing function. lbe_status_hold_consistency_check keeps status=''held'' and is_fraud_hold perfectly synchronized -- one governed state, never two independently-drifting flags (design decision 3).';

create index lbe_tenant_account_status_idx on app.loyalty_benefit_entitlements (tenant_id, loyalty_account_id, status);
create index lbe_tenant_updated_id_idx on app.loyalty_benefit_entitlements (tenant_id, updated_at desc, id desc);
create index lbe_tenant_expiry_idx on app.loyalty_benefit_entitlements (tenant_id, expires_at) where status = 'issued' and expires_at is not null;

create function app.touch_loyalty_benefit_entitlement_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_benefit_entitlements_touch_row
  before update on app.loyalty_benefit_entitlements
  for each row
  execute function app.touch_loyalty_benefit_entitlement_row();

-- ===========================================================================
-- 2. app.loyalty_benefit_entitlement_events -- APPEND-ONLY lifecycle log
-- (design decision 1). No UPDATE/DELETE grant to any role anywhere in this
-- migration, not even service_role -- mirrors app.loyalty_point_ledger_
-- entries' own identical choice (CPL-318 design decision 13).
-- ===========================================================================

create table app.loyalty_benefit_entitlement_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  entitlement_id uuid not null references app.loyalty_benefit_entitlements (id),
  event_type text not null,
  amount numeric,
  reason text,
  actor_auth_user_id uuid,
  actor_label text,
  created_at timestamptz not null default clock_timestamp(),
  constraint lbee_event_type_check check (event_type in ('issued', 'redeemed', 'reversed', 'expired', 'held', 'released')),
  constraint lbee_reason_check check (event_type not in ('reversed', 'held') or (reason is not null and length(trim(reason)) > 0))
);

comment on table app.loyalty_benefit_entitlement_events is
  'CPL-319: append-only. No UPDATE/DELETE grant to any role anywhere in this migration (mirrors app.loyalty_point_ledger_entries exactly) -- a correction is always a new entitlement status transition (app.reverse_loyalty_benefit_entitlement) posting its own new event row, never an edit or delete of history. amount is a value SNAPSHOT (the entitlement''s own value_amount at the moment of this event), not a running ledger total -- this capability has no aggregate balance to derive (design decision 1).';

create index lbee_tenant_entitlement_created_idx on app.loyalty_benefit_entitlement_events (tenant_id, entitlement_id, created_at desc);
create index lbee_tenant_created_id_idx on app.loyalty_benefit_entitlement_events (tenant_id, created_at desc, id desc);

-- ===========================================================================
-- 2b. app.generate_random_base32_voucher_code -- pure generator helper, no
-- table access, no authority check, no p_actor parameter (not itself an
-- "actor-taking RPC" the mandatory pattern's assert_actor_is_session_
-- identity rule applies to -- it is a private code-generation primitive
-- ONLY app.issue_loyalty_benefit_entitlement calls, never a standalone
-- public API surface: no EXECUTE grant to authenticated/service_role
-- anywhere in this migration, deliberately -- a SECURITY DEFINER caller
-- invoking another SECURITY DEFINER function runs as ITS OWN owner for that
-- nested call, so no explicit grant is required for app.issue_loyalty_
-- benefit_entitlement to call this, and none is offered for any OTHER
-- caller). PostgreSQL core's own encode() has no base32 target (only hex/
-- base64/escape -- confirmed live, the FIRST attempt at this migration's own
-- design used encode(gen_random_bytes(5), 'base32') and failed with
-- "unrecognized encoding: base32" on this checkpoint's own first db-test
-- run) and pgcrypto does not add one either -- this is a real, from-scratch
-- RFC4648 base32 encoder over a fixed 5-byte (40-bit) random draw, computed
-- via bigint bitwise ops (get_byte/<</|/>>/&, all core PostgreSQL, no
-- extension dependency beyond gen_random_bytes itself), not an
-- approximation. The RFC4648 alphabet (`ABCDEFGHIJKLMNOPQRSTUVWXYZ234567`)
-- already excludes the digits 0/1, so it carries no 0/O or 1/I/L visual
-- ambiguity by construction -- no extra filtering needed.
-- ===========================================================================

create function app.generate_random_base32_voucher_code()
returns text
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_bytes bytea := gen_random_bytes(5);
  v_num bigint := 0;
  v_alphabet text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  v_body text := '';
  i integer;
  v_idx integer;
begin
  for i in 0..4 loop
    v_num := (v_num << 8) | get_byte(v_bytes, i);
  end loop;
  for i in 0..7 loop
    v_idx := ((v_num >> ((7 - i) * 5)) & 31)::integer;
    v_body := v_body || substr(v_alphabet, v_idx + 1, 1);
  end loop;
  return 'CGV-' || substr(v_body, 1, 4) || '-' || substr(v_body, 5, 4);
end;
$$;

-- ===========================================================================
-- 3. app.issue_loyalty_benefit_entitlement -- staff/system, LYL:Edit.
-- ===========================================================================

create function app.issue_loyalty_benefit_entitlement(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_benefit_type text,
  p_value_amount numeric,
  p_value_cap numeric,
  p_currency text,
  p_source_type text,
  p_source_id uuid,
  p_expires_at timestamptz,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_config_version integer default 1
)
returns table (
  id uuid, tenant_id uuid, loyalty_account_id uuid, benefit_type text, value_amount numeric, value_cap numeric,
  currency text, status text, code_hash text, source_type text, source_id uuid, expires_at timestamptz,
  config_version integer, idempotency_key text, is_fraud_hold boolean, hold_reason text, held_by text, held_at timestamptz,
  released_by text, released_at timestamptz, record_version integer, created_by text, created_at timestamptz, updated_at timestamptz,
  raw_code text
)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.loyalty_accounts;
  v_existing app.loyalty_benefit_entitlements;
  v_entitlement app.loyalty_benefit_entitlements;
  v_raw_code text;
  v_code_hash text;
begin
  -- Design note: this function's own RETURNS TABLE column list is IDENTICAL
  -- to app.loyalty_benefit_entitlements' own column list plus raw_code
  -- (mirrors app.create_api_key's own flattened-table-plus-secret return
  -- shape) -- that implicitly declares tenant_id/idempotency_key/id/status/
  -- etc as PL/pgSQL variables in THIS function's own scope. Every query
  -- below that reads app.loyalty_benefit_entitlements/app.loyalty_accounts
  -- therefore uses an explicit table alias (`e`/`a`) and qualifies every
  -- column reference through it -- the exact ambiguous-column defect class
  -- CPL-317 self-found and fixed at app.get_loyalty_account_tier_state,
  -- live-caught here during this checkpoint's own first db-test run (a bare
  -- `where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key`
  -- raised a real `column reference "tenant_id" is ambiguous` error), fixed
  -- at the root before this checkpoint reported done, not patched around.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_benefit_type not in ('cashback', 'discount', 'voucher') then
    raise exception 'invalid_benefit_type: % is not one of cashback/discount/voucher', p_benefit_type using errcode = 'check_violation';
  end if;
  if p_value_amount is null or p_value_amount <= 0 then
    raise exception 'invalid_value_amount: value_amount must be greater than zero' using errcode = 'check_violation';
  end if;
  if p_value_cap is not null and p_value_cap <= 0 then
    raise exception 'invalid_value_cap: value_cap must be greater than zero when supplied' using errcode = 'check_violation';
  end if;
  -- Design decision 7: authoritative procedural guard, ahead of the table's
  -- own CHECK constraint backstop.
  if p_value_cap is not null and p_value_amount > p_value_cap then
    raise exception 'value_exceeds_cap: value_amount % exceeds value_cap %', p_value_amount, p_value_cap using errcode = 'check_violation';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter uppercase currency code', p_currency using errcode = 'check_violation';
  end if;
  if p_source_type is null or length(trim(p_source_type)) = 0 then
    raise exception 'invalid_source_type: a non-empty source_type is required' using errcode = 'check_violation';
  end if;
  if p_expires_at is not null and p_expires_at <= clock_timestamp() then
    raise exception 'invalid_expires_at: expires_at must be in the future' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;

  -- Idempotent short-circuit AFTER the authority check (mandatory pattern).
  -- Design decision 2: a replayed voucher issuance NEVER re-mints or re-
  -- returns the raw code -- raw_code is null on every replay, a real,
  -- disclosed, unavoidable consequence of hash-only storage.
  select e.* into v_existing from app.loyalty_benefit_entitlements e where e.tenant_id = p_tenant_id and e.idempotency_key = p_idempotency_key;
  if found then
    return query select v_existing.*, null::text;
    return;
  end if;

  select a.* into v_account from app.loyalty_accounts a where a.id = p_loyalty_account_id and a.tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_account_not_found: % is not a loyalty account of tenant %', p_loyalty_account_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if p_benefit_type = 'voucher' then
    loop
      v_raw_code := app.generate_random_base32_voucher_code();
      v_code_hash := encode(digest(v_raw_code, 'sha256'), 'hex');
      begin
        insert into app.loyalty_benefit_entitlements (
          tenant_id, loyalty_account_id, benefit_type, value_amount, value_cap, currency, status, code_hash,
          source_type, source_id, expires_at, config_version, idempotency_key, created_by
        ) values (
          p_tenant_id, p_loyalty_account_id, p_benefit_type, p_value_amount, p_value_cap, p_currency, 'issued', v_code_hash,
          p_source_type, p_source_id, p_expires_at, coalesce(p_config_version, 1), p_idempotency_key, p_actor_label
        )
        returning * into v_entitlement;
        exit;
      exception
        when unique_violation then
          -- Could be a genuine (tenant_id, idempotency_key) race (another
          -- caller already won) OR, astronomically unlikely, a code_hash
          -- collision -- distinguish by re-checking the idempotency key
          -- first; only regenerate-and-retry when it truly was the code.
          select e.* into v_existing from app.loyalty_benefit_entitlements e where e.tenant_id = p_tenant_id and e.idempotency_key = p_idempotency_key;
          if found then
            return query select v_existing.*, null::text;
            return;
          end if;
          continue;
      end;
    end loop;
  else
    v_raw_code := null;
    begin
      insert into app.loyalty_benefit_entitlements (
        tenant_id, loyalty_account_id, benefit_type, value_amount, value_cap, currency, status, code_hash,
        source_type, source_id, expires_at, config_version, idempotency_key, created_by
      ) values (
        p_tenant_id, p_loyalty_account_id, p_benefit_type, p_value_amount, p_value_cap, p_currency, 'issued', null,
        p_source_type, p_source_id, p_expires_at, coalesce(p_config_version, 1), p_idempotency_key, p_actor_label
      )
      returning * into v_entitlement;
    exception
      when unique_violation then
        select e.* into v_existing from app.loyalty_benefit_entitlements e where e.tenant_id = p_tenant_id and e.idempotency_key = p_idempotency_key;
        if not found then
          raise;
        end if;
        return query select v_existing.*, null::text;
        return;
    end;
  end if;

  -- Design decision 4: the entitlement row's own INSERT (idempotency claim)
  -- happens strictly before this append-only event row.
  insert into app.loyalty_benefit_entitlement_events (tenant_id, entitlement_id, event_type, amount, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_entitlement.id, 'issued', v_entitlement.value_amount, null, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_loyalty_benefit_entitlement',
    'app.loyalty_benefit_entitlements', v_entitlement.id, 'success', null, null,
    jsonb_build_object('benefit_type', p_benefit_type, 'value_amount', p_value_amount, 'currency', p_currency, 'loyalty_account_id', p_loyalty_account_id)
  );

  return query select v_entitlement.*, v_raw_code;
end;
$$;

comment on function app.issue_loyalty_benefit_entitlement is
  'CPL-319: idempotent on (tenant_id, idempotency_key) -- a retry returns the identical entitlement row, never a duplicate. value_cap enforced both procedurally (authoritative) and via lbe_value_cap_bound_check (defense-in-depth, design decision 7). For benefit_type=voucher, generates a real hash-only-stored code (design decision 2) and returns the RAW code exactly once, in this call''s own return row -- raw_code is null on every idempotent replay.';

-- ===========================================================================
-- 4. app.redeem_loyalty_benefit_entitlement -- dual authority (design
-- decision 5): staff (LYL:Edit) via id or code; a customer_user via their
-- own resolved account scope, via id or code. Fully anti-enumerating on the
-- code path.
-- ===========================================================================

create function app.redeem_loyalty_benefit_entitlement(
  p_tenant_id uuid,
  p_entitlement_id_or_code text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_benefit_entitlements
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_is_staff boolean;
  v_customer_scope uuid[];
  v_by_id boolean := false;
  v_id uuid;
  v_hash text;
  v_entitlement app.loyalty_benefit_entitlements;
  v_account app.loyalty_accounts;
  v_updated app.loyalty_benefit_entitlements;
  v_generic_message text := 'voucher_redemption_failed: this voucher code cannot be redeemed';
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Design decision 9: resolve BOTH authority shapes before touching
  -- app.loyalty_benefit_entitlements at all (C-05).
  v_is_staff := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit')).allowed;
  v_customer_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);

  if not v_is_staff and array_length(v_customer_scope, 1) is null then
    raise exception 'insufficient_authority: identity % holds neither LYL:Edit nor any customer_user account scope for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_entitlement_id_or_code is null or length(trim(p_entitlement_id_or_code)) = 0 then
    raise exception 'invalid_entitlement_reference: an entitlement id or voucher code is required' using errcode = 'check_violation';
  end if;

  begin
    v_id := p_entitlement_id_or_code::uuid;
    v_by_id := true;
  exception
    when invalid_text_representation then
      v_by_id := false;
  end;

  if v_by_id then
    -- ID path (design decision 5a): ordinary, distinguishable errors -- the
    -- caller already legitimately knows this id.
    select * into v_entitlement from app.loyalty_benefit_entitlements where id = v_id and tenant_id = p_tenant_id for update;
    if not found then
      raise exception 'loyalty_benefit_entitlement_not_found: %', v_id using errcode = 'no_data_found';
    end if;

    if not v_is_staff then
      select * into v_account from app.loyalty_accounts where id = v_entitlement.loyalty_account_id;
      if v_account.id is null or not (v_account.customer_account_id = any (v_customer_scope)) then
        -- Anti-enumeration for the caller's own standing: identical to
        -- "not found" -- never reveals that a DIFFERENT customer's own
        -- entitlement exists under this id.
        raise exception 'loyalty_benefit_entitlement_not_found: %', v_id using errcode = 'no_data_found';
      end if;
    end if;

    if v_entitlement.status <> 'issued' then
      raise exception 'invalid_transition: entitlement % is % -- only an issued entitlement may be redeemed', v_id, v_entitlement.status using errcode = 'check_violation';
    end if;
    if v_entitlement.expires_at is not null and v_entitlement.expires_at <= clock_timestamp() then
      raise exception 'entitlement_expired: entitlement % expired at %', v_id, v_entitlement.expires_at using errcode = 'check_violation';
    end if;
    if p_expected_version is not null and v_entitlement.record_version <> p_expected_version then
      raise exception 'stale_version: entitlement % expected version % but found %', v_id, p_expected_version, v_entitlement.record_version
        using errcode = 'serialization_failure';
    end if;

    update app.loyalty_benefit_entitlements
      set status = 'redeemed'
      where id = v_entitlement.id and status = 'issued'
      returning * into v_updated;
    if not found then
      raise exception 'stale_version: entitlement % was concurrently modified', v_id using errcode = 'serialization_failure';
    end if;
  else
    -- Code path (design decision 5b): voucher-only, hash lookup, fully
    -- anti-enumerating -- every branch below raises the IDENTICAL message
    -- and errcode, proven live/adversarially in this checkpoint's own
    -- db-test.
    v_hash := encode(digest(p_entitlement_id_or_code, 'sha256'), 'hex');
    select * into v_entitlement from app.loyalty_benefit_entitlements where tenant_id = p_tenant_id and code_hash = v_hash for update;
    if not found then
      raise exception '%', v_generic_message using errcode = 'no_data_found';
    end if;

    if not v_is_staff then
      select * into v_account from app.loyalty_accounts where id = v_entitlement.loyalty_account_id;
      if v_account.id is null or not (v_account.customer_account_id = any (v_customer_scope)) then
        raise exception '%', v_generic_message using errcode = 'no_data_found';
      end if;
    end if;
    if v_entitlement.status <> 'issued' then
      raise exception '%', v_generic_message using errcode = 'no_data_found';
    end if;
    if v_entitlement.expires_at is not null and v_entitlement.expires_at <= clock_timestamp() then
      raise exception '%', v_generic_message using errcode = 'no_data_found';
    end if;
    if p_expected_version is not null and v_entitlement.record_version <> p_expected_version then
      raise exception '%', v_generic_message using errcode = 'no_data_found';
    end if;

    update app.loyalty_benefit_entitlements
      set status = 'redeemed'
      where id = v_entitlement.id and status = 'issued'
      returning * into v_updated;
    if not found then
      raise exception '%', v_generic_message using errcode = 'no_data_found';
    end if;
  end if;

  insert into app.loyalty_benefit_entitlement_events (tenant_id, entitlement_id, event_type, amount, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_updated.id, 'redeemed', v_updated.value_amount, null, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'redeem_loyalty_benefit_entitlement',
    'app.loyalty_benefit_entitlements', v_updated.id, 'success', null,
    jsonb_build_object('status', 'issued'), jsonb_build_object('status', 'redeemed')
  );

  return v_updated;
end;
$$;

comment on function app.redeem_loyalty_benefit_entitlement is
  'CPL-319: dual authority (design decision 5) -- staff LYL:Edit or the entitlement''s own owning customer. ID path: ordinary distinguishable errors. CODE path (voucher only, code_hash lookup, NEVER a plaintext comparison): every failure mode (forged/foreign-tenant/foreign-owner/already-redeemed/expired/held/stale-version) collapses into one identical voucher_redemption_failed error -- no oracle for guessing valid codes. p_expected_version is nullable (design decision 6) -- when supplied, a real staleness check; when null, the atomic status=''issued'' transition alone is the concurrency guard.';

-- ===========================================================================
-- 5. app.reverse_loyalty_benefit_entitlement -- staff, LYL:Configure
-- (governance-grade). Preserves history -- a new transition, never a delete.
-- ===========================================================================

create function app.reverse_loyalty_benefit_entitlement(
  p_tenant_id uuid,
  p_entitlement_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_benefit_entitlements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_entitlement app.loyalty_benefit_entitlements;
  v_updated app.loyalty_benefit_entitlements;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reverse an entitlement' using errcode = 'not_null_violation';
  end if;

  select * into v_entitlement from app.loyalty_benefit_entitlements where id = p_entitlement_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_benefit_entitlement_not_found: %', p_entitlement_id using errcode = 'no_data_found';
  end if;
  if v_entitlement.record_version <> p_expected_version then
    raise exception 'stale_version: entitlement % expected version % but found %', p_entitlement_id, p_expected_version, v_entitlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_entitlement.status not in ('issued', 'held', 'redeemed') then
    raise exception 'invalid_transition: entitlement % is % -- only issued/held/redeemed may be reversed', p_entitlement_id, v_entitlement.status
      using errcode = 'check_violation';
  end if;

  update app.loyalty_benefit_entitlements
    set status = 'reversed', is_fraud_hold = false
    where id = p_entitlement_id and record_version = p_expected_version
    returning * into v_updated;
  if not found then
    raise exception 'stale_version: entitlement % was concurrently modified (expected version %)', p_entitlement_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.loyalty_benefit_entitlement_events (tenant_id, entitlement_id, event_type, amount, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_updated.id, 'reversed', v_updated.value_amount, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'reverse_loyalty_benefit_entitlement',
    'app.loyalty_benefit_entitlements', v_updated.id, 'success', p_reason,
    jsonb_build_object('status', v_entitlement.status), jsonb_build_object('status', 'reversed')
  );

  return v_updated;
end;
$$;

comment on function app.reverse_loyalty_benefit_entitlement is
  'CPL-319: a governed correction, never a delete or in-place erase of history -- transitions status to reversed, preserving the entitlement row and its full app.loyalty_benefit_entitlement_events chain. Reversible from issued/held/redeemed (Alternative flow: "reversed after source transaction cancellation... policy", which may happen even after redemption) -- rejected from already reversed/expired.';

-- ===========================================================================
-- 6. app.expire_loyalty_benefit_entitlements -- staff/system, LYL:Edit.
-- Batch, idempotent per row (mirrors CPL-318's expire_loyalty_point_lots
-- shape exactly).
-- ===========================================================================

create function app.expire_loyalty_benefit_entitlements(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns setof app.loyalty_benefit_entitlements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row record;
  v_updated app.loyalty_benefit_entitlements;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Only status='issued' entitlements are in scope -- a held entitlement
  -- (status='held') must be released (or reversed) by staff first; expiry
  -- must never silently clear an open fraud-hold investigation (disclosed
  -- boundary, mirrors CPL-318's own status='active'-only lot expiry scan).
  for v_row in
    select * from app.loyalty_benefit_entitlements
    where tenant_id = p_tenant_id and status = 'issued' and expires_at is not null and expires_at <= clock_timestamp()
    order by expires_at asc, id asc
  loop
    begin
      update app.loyalty_benefit_entitlements
        set status = 'expired'
        where id = v_row.id and status = 'issued'
        returning * into v_updated;
      if found then
        insert into app.loyalty_benefit_entitlement_events (tenant_id, entitlement_id, event_type, amount, reason, actor_auth_user_id, actor_label)
        values (p_tenant_id, v_updated.id, 'expired', v_updated.value_amount, null, p_actor_auth_user_id, p_actor_label);
        return next v_updated;
      end if;
    exception
      when others then
        -- A concurrent operation may have already touched this row between
        -- this scan's own snapshot and this iteration reaching it -- skip
        -- it; a future call safely picks up whatever, if anything, is still
        -- genuinely due (mirrors CPL-318 design decision 8).
        continue;
    end;
  end loop;

  return;
end;
$$;

comment on function app.expire_loyalty_benefit_entitlements is
  'CPL-319: idempotent per row by construction -- an already-expired entitlement no longer matches this scan''s own predicate on re-run, a safe no-op. Each row is independently fault-isolated so one row racing against a concurrent operation never aborts an otherwise-successful batch for every other due row. On-demand/staff-triggered only in this checkpoint (ISS-2026-129), mirroring ISS-2026-126/127/128''s own identical, already-accepted precedent.';

-- ===========================================================================
-- 7. app.hold_loyalty_benefit_entitlement / app.release_loyalty_benefit_
-- entitlement_hold -- staff, LYL:Configure (governance-grade, design
-- decision 3). Inline on the entitlement row's own status column.
-- ===========================================================================

create function app.hold_loyalty_benefit_entitlement(
  p_tenant_id uuid,
  p_entitlement_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_benefit_entitlements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_entitlement app.loyalty_benefit_entitlements;
  v_updated app.loyalty_benefit_entitlements;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to hold an entitlement' using errcode = 'not_null_violation';
  end if;

  select * into v_entitlement from app.loyalty_benefit_entitlements where id = p_entitlement_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_benefit_entitlement_not_found: %', p_entitlement_id using errcode = 'no_data_found';
  end if;

  if v_entitlement.status = 'held' then
    -- Idempotent: a repeat hold is a safe no-op preserving the ORIGINAL
    -- reason/held_by/held_at, never overwritten by a repeated call (mirrors
    -- CPL-317's own app.hold_loyalty_account_tier_benefits exactly).
    return v_entitlement;
  end if;
  if v_entitlement.status <> 'issued' then
    raise exception 'invalid_transition: entitlement % is % -- only an issued entitlement may be held', p_entitlement_id, v_entitlement.status
      using errcode = 'check_violation';
  end if;

  update app.loyalty_benefit_entitlements
    set status = 'held', is_fraud_hold = true, hold_reason = p_reason, held_by = p_actor_label, held_at = clock_timestamp(),
        released_by = null, released_at = null
    where id = p_entitlement_id
    returning * into v_updated;

  insert into app.loyalty_benefit_entitlement_events (tenant_id, entitlement_id, event_type, amount, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_updated.id, 'held', null, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_loyalty_benefit_entitlement',
    'app.loyalty_benefit_entitlements', v_updated.id, 'success', p_reason,
    jsonb_build_object('status', 'issued'), jsonb_build_object('status', 'held')
  );

  return v_updated;
end;
$$;

comment on function app.hold_loyalty_benefit_entitlement is
  'CPL-319: fraud/dispute hold, mirroring CPL-317''s own governing principles inline on this table''s own mutable status column (design decision 3). Blocks app.redeem_loyalty_benefit_entitlement structurally (status <> issued while held) -- proven live in this checkpoint''s own db-test.';

create function app.release_loyalty_benefit_entitlement_hold(
  p_tenant_id uuid,
  p_entitlement_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_benefit_entitlements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_entitlement app.loyalty_benefit_entitlements;
  v_updated app.loyalty_benefit_entitlements;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_entitlement from app.loyalty_benefit_entitlements where id = p_entitlement_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_benefit_entitlement_not_found: %', p_entitlement_id using errcode = 'no_data_found';
  end if;
  if v_entitlement.status <> 'held' then
    raise exception 'entitlement_not_held: entitlement % is % -- not currently on hold', p_entitlement_id, v_entitlement.status using errcode = 'check_violation';
  end if;

  update app.loyalty_benefit_entitlements
    set status = 'issued', is_fraud_hold = false, released_by = p_actor_label, released_at = clock_timestamp()
    where id = p_entitlement_id
    returning * into v_updated;

  insert into app.loyalty_benefit_entitlement_events (tenant_id, entitlement_id, event_type, amount, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_updated.id, 'released', null, null, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'release_loyalty_benefit_entitlement_hold',
    'app.loyalty_benefit_entitlements', v_updated.id, 'success', null,
    jsonb_build_object('status', 'held'), jsonb_build_object('status', 'issued')
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 8. Staff reads -- LYL:View.
-- ===========================================================================

create function app.get_loyalty_benefit_entitlement(p_tenant_id uuid, p_entitlement_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_benefit_entitlements
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_entitlement app.loyalty_benefit_entitlements;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_entitlement from app.loyalty_benefit_entitlements where id = p_entitlement_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_benefit_entitlement_not_found: %', p_entitlement_id using errcode = 'no_data_found';
  end if;

  return v_entitlement;
end;
$$;

create function app.list_loyalty_benefit_entitlements(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_loyalty_account_id uuid default null,
  p_benefit_type text default null,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_benefit_entitlements
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
  select e.* from app.loyalty_benefit_entitlements e
  where e.tenant_id = p_tenant_id
    and (p_loyalty_account_id is null or e.loyalty_account_id = p_loyalty_account_id)
    and (p_benefit_type is null or e.benefit_type = p_benefit_type)
    and (p_status is null or e.status = p_status)
    and (p_cursor_id is null or (e.updated_at, e.id) < (p_cursor_updated_at, p_cursor_id))
  order by e.updated_at desc, e.id desc
  limit v_limit;
end;
$$;

create function app.list_loyalty_benefit_entitlement_events(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_entitlement_id uuid default null,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_benefit_entitlement_events
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
  select v.* from app.loyalty_benefit_entitlement_events v
  where v.tenant_id = p_tenant_id
    and (p_entitlement_id is null or v.entitlement_id = p_entitlement_id)
    and (p_cursor_id is null or (v.created_at, v.id) < (p_cursor_created_at, p_cursor_id))
  order by v.created_at desc, v.id desc
  limit v_limit;
end;
$$;

comment on function app.list_loyalty_benefit_entitlement_events is
  'CPL-319: keyset-paginated on (created_at desc, id desc) -- app.loyalty_benefit_entitlement_events has no updated_at column (append-only, immutable rows). Full internal projection (includes reason) -- staff-only.';

-- ===========================================================================
-- 9. app.list_customer_portal_loyalty_benefit_entitlements -- customer-
-- facing (Layer 4, ADR-0024 Part A). Deny-by-default. Never exposes
-- code_hash, idempotency_key, source_type/source_id, config_version, or the
-- real hold_reason.
-- ===========================================================================

create function app.list_customer_portal_loyalty_benefit_entitlements(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_customer_account_id uuid default null,
  p_benefit_type text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  loyalty_account_id uuid,
  program_name text,
  benefit_type text,
  value_amount numeric,
  value_cap numeric,
  currency text,
  status text,
  is_on_hold boolean,
  hold_notice text,
  expires_at timestamptz,
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
    e.loyalty_account_id,
    p.name,
    e.benefit_type,
    e.value_amount,
    e.value_cap,
    e.currency,
    e.status,
    e.status = 'held',
    case when e.status = 'held' then 'This benefit is temporarily on hold. Contact your account administrator or support for details.' else null end,
    e.expires_at,
    e.record_version,
    e.created_at,
    e.updated_at
  from app.loyalty_benefit_entitlements e
  join app.loyalty_accounts la on la.id = e.loyalty_account_id
  join app.loyalty_programs p on p.id = la.program_id
  where e.tenant_id = p_tenant_id
    and la.customer_account_id = any (v_scope)
    and (p_customer_account_id is null or la.customer_account_id = p_customer_account_id)
    and (p_benefit_type is null or e.benefit_type = p_benefit_type)
    and (p_cursor_id is null or (e.updated_at, e.id) < (p_cursor_updated_at, p_cursor_id))
  order by e.updated_at desc, e.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_loyalty_benefit_entitlements is
  'CPL-319: customer-safe benefit wallet projection. Never exposes code_hash/idempotency_key/source_type/source_id/config_version/the real hold_reason (structural, not merely a UI omission) -- a held entitlement surfaces is_on_hold=true plus a GENERIC customer-safe hold_notice, never the internal hold_reason. Deny-by-default: an out-of-scope p_customer_account_id or an empty resolved scope both return zero rows, never an error. record_version is included so the wallet''s own per-row redeem action can pass a real p_expected_version.';

-- ===========================================================================
-- 10. RLS -- enable, grant service_role only (design decision 12).
-- ===========================================================================

alter table app.loyalty_benefit_entitlements enable row level security;
alter table app.loyalty_benefit_entitlement_events enable row level security;

grant select, insert, update on app.loyalty_benefit_entitlements to service_role;
grant select, insert on app.loyalty_benefit_entitlement_events to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.issue_loyalty_benefit_entitlement(uuid, uuid, text, numeric, numeric, text, text, uuid, timestamptz, text, uuid, text, integer) to authenticated, service_role;
grant execute on function app.redeem_loyalty_benefit_entitlement(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reverse_loyalty_benefit_entitlement(uuid, uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.expire_loyalty_benefit_entitlements(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.hold_loyalty_benefit_entitlement(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.release_loyalty_benefit_entitlement_hold(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_benefit_entitlement(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_benefit_entitlements(uuid, uuid, uuid, text, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_loyalty_benefit_entitlement_events(uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_portal_loyalty_benefit_entitlements(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
