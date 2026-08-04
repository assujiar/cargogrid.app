-- Advanced TMS/WMS capability ATW-023 (CG-S10-ATW-023, Prompt 242, "Customer
-- Inventory Access Contract" -- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md
-- §1). Implements this prompt's own §4 objective: "a secure backend/database contract
-- for customer-scoped inventory visibility while deferring the complete Customer Portal
-- experience to Step 13." Read-only (§24): no count/adjustment/reservation/task
-- mutation is added here.
--
-- The gap this migration closes (verified by direct inspection, not assumed): every
-- existing "owner-scoped" read RPC in this repository (app.get_lot_trace,
-- app.list_lot_identities/app.list_serial_identities, ATW-016;
-- app.get_wms_outbound_order/app.list_wms_outbound_orders, ATW-016A) still gates on
-- app.evaluate_permission(actor, tenant, 'OPS', 'View') before ever reaching its own
-- owner-scope check. OPS is a staff/internal RBAC category (docs/architecture/06_RLS_
-- RBAC_WORKSTREAM.md) -- a genuine customer-portal end user
-- (app.principal_memberships.layer = 'customer_user') holds no OPS role at all and
-- would be rejected outright by every one of those RPCs. There is no 'CST' RBAC
-- category and no app.evaluate_customer_* function anywhere in the repository before
-- this migration (grepped). This migration defines the first genuine customer-facing
-- authorization path that does not depend on staff RBAC.
--
-- Design boundary (disclosed):
--
-- 1. **No new customer-warehouse grant table.** Reuses app.warehouse_customer_
--    eligibility verbatim (ATW-229, supabase/migrations/
--    20260730140000_create_advanced_tms_warehouse_zone.sql) -- that table's own
--    comment already named this migration as its first real consumer ("no consumer
--    yet widens a customer-portal principal's own access from this table ... ATW-242
--    not yet shipped"). Its own grant/revoke_warehouse_customer_eligibility RPCs
--    already audit via app.capture_audit_event (ATW-229) -- not duplicated here, and
--    the existing server/mutations/warehouse-zone.ts wrapper already exposes both to
--    the service layer, so no new grant/revoke wrapper is added by this migration's
--    own service-layer files either (see server/mutations/customer-inventory-
--    access.ts's own header note).
-- 2. **No new customer-owner mapping table.** Reuses app.principal_memberships.
--    customer_account_ref exactly as ATW-016 established (design note 6b,
--    supabase/migrations/20260730220000_create_advanced_tms_lot_batch_serial_
--    expiry.sql, app.resolve_actor_owner_account_scope/app.actor_can_view_owner_
--    scoped_row): a customer_user-layer membership's own customer_account_ref, when
--    syntactically uuid-shaped (`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-
--    [0-9a-f]{12}$`), IS the app.accounts.id (the owner_account_id) that actor may
--    see. app.resolve_actor_owner_account_scope itself is deliberately NOT reused for
--    this migration's own gate -- it returns NULL to mean "unrestricted" for
--    staff/no-membership actors (a correct behavior for its own already-VERIFIED
--    owner-scope-narrowing role layered ON TOP of an OPS:View RBAC gate), which would
--    be an unsafe default if reused as-is inside a customer-only, deny-by-default
--    gate that has no RBAC layer above it at all. This migration therefore defines its
--    own, narrower, self-contained app.resolve_customer_owner_account_scope below,
--    which ALWAYS returns a real (possibly empty) array, never NULL/"unrestricted".
-- 3. **app.evaluate_customer_inventory_access composes exactly two checks, both
--    required, deny-by-default, no staff/OPS bypass.** It is a thin SQL-language
--    wrapper over app.resolve_customer_owner_account_scope (membership+owner check)
--    and the new app.customer_warehouse_eligibility_active helper (eligibility
--    check) -- the same narrow-wrapper-over-a-real-permission-primitive shape app.
--    has_view_personal_data (PLT-114, supabase/migrations/
--    20260716110430_create_field_record_access.sql) already uses, generalized here
--    to two ANDed real primitives instead of one `evaluate_permission` call, since
--    this contract deliberately has no RBAC primitive to wrap.
-- 4. **app.customer_warehouse_eligibility_active is the ONE shared eligibility
--    predicate every RPC below reuses -- never re-derived.** app.evaluate_customer_
--    inventory_access calls it directly for a single already-fetched row (get RPCs
--    reuse app.evaluate_customer_inventory_access itself, per Prompt 242 §24 "list/
--    search/export/aggregate apply identical record and field policy"). Every list/
--    export RPC instead precomputes app.resolve_customer_owner_account_scope(...)
--    ONCE per call (not once per row -- the membership lookup is otherwise identical
--    for every row a single caller can ever see) and calls app.customer_warehouse_
--    eligibility_active(...) per row for the warehouse-eligibility half only, which
--    genuinely varies per row's own warehouse_id/owner_account_id pair and cannot be
--    precomputed into a single array the same way. This is a disclosed decomposition
--    of the identical two-check predicate for per-row query performance (Prompt 242
--    §17), not a second, divergent implementation.
-- 5. **Anti-enumeration (§16/§23): every single-row get RPC below raises the
--    IDENTICAL 'record_not_found: ...' message prefix with errcode no_data_found**
--    whether the target row genuinely does not exist, belongs to a different tenant,
--    or exists but fails the owner/eligibility gate -- never a distinguishable
--    insufficient_authority for this specific customer-facing RPC set. This
--    deliberately diverges from every staff-facing RPC elsewhere in this repository
--    (app.get_lot_identity, app.get_wms_outbound_order, etc.), which DO raise a
--    distinguishable insufficient_authority on a scope failure -- that is fine and
--    expected for an internal-staff caller who already cleared an OPS:* RBAC gate to
--    even attempt the call. It is not fine for the one genuinely external-facing
--    contract in this repository, where a distinguishable error would let a caller
--    enumerate the existence of another customer's record by probing IDs.
-- 6. **RLS on every existing table this migration reads (app.inventory_balances,
--    app.inventory_movements, app.inventory_movement_lines, app.inventory_
--    reservations, app.wms_outbound_orders, app.wms_outbound_order_lines, app.
--    lot_identities, app.serial_identities) is UNCHANGED BY THIS MIGRATION -- not a
--    single ALTER TABLE/CREATE POLICY/DROP POLICY statement below touches any of
--    them.** Prompt 242 §14 ("One service must enforce identical scope, field
--    policy, masking, audit and version semantics") is the reason: granting
--    `authenticated` a SECOND, RLS-level direct-table read path for a customer_user
--    actor would create a second, independently-evolving enforcement point that
--    could silently drift from this migration's own bounded/cursor/audit logic. The
--    ONLY sanctioned read path for a customer-portal actor is through the SECURITY
--    DEFINER RPCs below.
--    Direct inspection of the CURRENT (already-applied, unmodified-by-this-migration)
--    RLS SELECT policies found they are not uniformly "staff-only" already, and this
--    is disclosed here rather than silently assumed:
--      - app.inventory_balances/app.inventory_movements/app.inventory_movement_lines
--        pass `null` as app.can_access_record's own p_customer_account_ref argument
--        -- their RLS SELECT policies have NO owner-scope branch at all and remain
--        genuinely staff-only (org-unit-scope only); a customer_user actor with no
--        org_unit_id is unconditionally blocked at the RLS layer for these three
--        tables today, confirmed by this migration's own db-test below.
--      - app.wms_outbound_orders/app.wms_outbound_order_lines (ATW-016A) and app.
--        lot_identities/app.serial_identities (ATW-016) DO already pass a real
--        owner_account_id/customer_account_ref into app.can_access_record/app.
--        actor_can_view_owner_scoped_row in their own RLS SELECT policies -- a
--        customer_user actor whose own customer_account_ref matches a row's
--        owner_account_id CAN already read that row directly via RLS, bypassing both
--        the OPS:View RPC gate AND (because app.warehouse_customer_eligibility is
--        never referenced by any RLS policy anywhere) this migration's own new
--        eligibility check entirely. This is pre-existing, already-applied-migration
--        behavior this task may not alter directly (AGENTS.md: never edit an applied
--        migration) and is exactly the drift risk design note 6 above warns about --
--        concretely proven, not hypothetical, by this migration's own db-test below
--        (a revoked eligibility grant stops the new RPC layer immediately but does
--        not hide the row from a raw RLS read). **Closed by a companion hardening
--        migration** (supabase/migrations/20260730311000_harden_customer_inventory_
--        access_rls_isolation.sql, added the same checkpoint after adversarial
--        security review live-reproduced this as a real, exploitable gap given that
--        this migration is the first to ever grant a live customer_user principal,
--        ISS-2026-010): that migration narrows (never widens) these four tables' own
--        RLS SELECT policies via DROP POLICY/CREATE POLICY -- the identical technique
--        ATW-017 already used for its own sibling RLS fix -- so a customer_user-layer
--        actor's raw-table read is denied outright, making the "ONLY sanctioned read
--        path is the SECURITY DEFINER RPCs below" claim above actually true rather
--        than aspirational. docs/runtime/KNOWN_ISSUES.md ISS-2026-010 still needs its
--        own ledger update to record this resolution -- that is a documentation
--        change owned by the orchestrating session, not this migration.
-- 7. **Cursor pagination (§17), never OFFSET.** Every list RPC below takes a
--    `(p_cursor_<col> timestamptz default null, p_cursor_id uuid default null)`
--    pair and a `p_limit` hard-capped via `least(greatest(coalesce(p_limit, ...), 1),
--    <cap>)`; `p_cursor_id is null` is the "no cursor" signal (id is the real
--    tiebreaker; a timestamp alone can collide across rows). The timestamp column
--    named in the cursor param matches whichever real column anchors that row's own
--    chronological order: `p_cursor_updated_at` for the mutable balance/lot/serial/
--    outbound-order lists (each has a real, maintained updated_at), `p_cursor_
--    occurred_at` for the movement-lineage summary (a join with no updated_at/
--    created_at column of its own that means anything -- app.inventory_movements.
--    occurred_at is the real chronological anchor there, the same column app.
--    get_lot_trace already orders by). Every cursor-taking list RPC below validates
--    the pair is supplied together: `p_cursor_id is not null and p_cursor_<col> is
--    null` raises `invalid_cursor` rather than silently returning an empty page --
--    fixed by adversarial correctness review, which found that PostgreSQL's row
--    comparison `(not-null, x) < (NULL, y)` evaluates to unknown (filtered out by
--    WHERE) for every row when only p_cursor_id is supplied, which a naive client
--    bug (persisting only half a cursor) would otherwise misread as "no more
--    results" instead of a clear validation error to fix.
-- 8. **Read-only.** No mutation of inventory/order/reservation state is added.
--    app.grant_warehouse_customer_eligibility/app.revoke_warehouse_customer_
--    eligibility (ATW-229) remain the only mutation surface touching this
--    migration's own eligibility table, unchanged.
-- 9. **Audit (§18) -- every get RPC's own denial branch cannot durably self-audit,
--    and is NOT the same thing as "denial goes unaudited."** The original design
--    (mirrored here in an earlier draft, and caught by this migration's own db-test
--    before being shipped) tried to have app.get_customer_inventory_balance/app.get_
--    customer_outbound_order call app.capture_audit_event on their own denial branch
--    and THEN raise the anti-enumerating exception design note 5 requires. That does
--    not work in plain PostgreSQL: an uncaught RAISE EXCEPTION aborts the entire
--    enclosing transaction, and a Supabase RPC call is exactly one such transaction --
--    the audit INSERT performed a moment earlier in the SAME function invocation is
--    rolled back along with everything else, never actually persisting. This
--    migration's own db-test proved it empirically (asserted a real audit row existed
--    after a denial; got zero, confirmed the insert never survived). The one existing
--    precedent in this repository that DOES durably audit a failure, app.ingest_gps_
--    gateway_report (ATW-224/PLT-...), only manages it because that function's own
--    failure paths RETURN a structured `accepted=false` row rather than raising -- the
--    audit write then commits as part of an otherwise-successful call. That escape
--    hatch is not available here: design note 5's anti-enumeration requirement is
--    unconditional (every get RPC must RAISE an identical exception, never return an
--    ambiguous success-shaped value a caller could branch on to distinguish not-found
--    from forbidden). **Resolution (adversarial spec-compliance review against Prompt
--    242 section 18's own explicit "result count/denial" requirement): a genuinely
--    SEPARATE RPC, app.record_customer_inventory_access_denial (defined below,
--    section 14), issued by the TS service layer in a NEW transaction after catching
--    the get RPC's own thrown record_not_found.** This keeps the anti-enumerating
--    RAISE exactly as design note 5 requires (the get RPCs themselves remain pure,
--    side-effect-free, `stable` reads, unchanged) while still durably recording that
--    a denial occurred -- the two goals were only ever in conflict WITHIN one
--    transaction, not across two. The follow-up audit RPC always succeeds
--    identically regardless of the real denial cause, so it introduces no new
--    enumeration surface itself. Wired into server/queries/customer-inventory-
--    access.ts's own getCustomerInventoryBalance/getCustomerOutboundOrder wrappers,
--    the two RPCs this gap concretely names -- app.list_customer_outbound_order_lines
--    (section 9 below) deliberately stays out of this wiring: unlike its 12 siblings
--    it takes no p_tenant_id (already disclosed above), so its own TS wrapper has no
--    tenant id to pass this new RPC without an extra round-trip lookup solely to
--    populate an audit record; its denial (reusing app.get_customer_outbound_order's
--    own gate internally) remains un-self-audited exactly like every plain read RPC
--    here, a narrow, disclosed scope boundary rather than an oversight. app.get_
--    customer_inventory_balance/app.get_customer_outbound_order/app.list_customer_
--    outbound_order_lines all remain pure reads with no side effect of their own and
--    stay marked `stable`, exactly like every other read RPC in this migration.
--    app.export_customer_inventory_snapshot is the
--    one RPC in this migration that durably audits EVERY call (success or
--    zero-result) from within its own single transaction (a filtered-to-zero-rows
--    export is still a normal, successful return, so no RAISE ever rolls it back) --
--    so its audit call needed no such split, and it alone is left un-`stable` and
--    keeps its own `p_actor_label text default null` trailing parameter (app.
--    audit_logs.actor_label is NOT NULL and no existing helper in this repository
--    resolves a display label from an auth_user_id alone; coalesced to a fixed
--    fallback string when a caller omits it, so the prompt's own literal
--    required-positional-argument prefix still works unchanged). app.record_
--    customer_inventory_access_denial reuses that identical fallback convention.
-- 10. **Field policy -- direct inspection confirmed, not assumed.** Read directly:
--     app.inventory_balances/app.inventory_movements/app.inventory_movement_lines
--     (supabase/migrations/20260730190000_create_advanced_tms_inventory_ledger.sql),
--     app.wms_outbound_orders/app.wms_outbound_order_lines (supabase/migrations/
--     20260730230000_create_advanced_tms_wms_outbound_order.sql), app.lot_identities/
--     app.serial_identities (supabase/migrations/
--     20260730220000_create_advanced_tms_lot_batch_serial_expiry.sql). ZERO monetary/
--     cost/rate column exists on any of the eight tables this migration reads --
--     confirmed by reading every `create table` block directly, not assumed. Every
--     read RPC below therefore projects an explicit column list (never `select *`/
--     `returns setof <table>`, per AGENTS.md "never SELECT * in transactional APIs")
--     that includes what a customer plausibly needs about their OWN permitted rows
--     (quantities, status, hold_reason -- Prompt 242's own customer legitimately
--     needs to know why their own stock is held -- item/lot/serial identifiers,
--     dates, warehouse_id, record_version for optimistic-concurrency-aware future
--     clients) and excludes internal-only fields: created_by/posted_by staff labels,
--     idempotency_key, source_type/source_id correlation ids, app.wms_outbound_
--     orders.source_shipment_order_id/source_reason (an internal cross-reference and
--     free-text operational note this migration's own RPC surface gives no way to
--     resolve/act on), app.wms_outbound_order_lines.notes (free-text, potentially
--     staff-internal), app.lot_identities.parent_lot_id (an internal genealogy
--     cross-reference with no RPC here to resolve it into anything meaningful).
--     Exact per-RPC column choice is documented on each function's own `comment on
--     function` below.
-- 11. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants,
--     and grants `authenticated` execute on every function below (including the
--     internal composition helpers) -- every one of these is customer-portal-
--     reachable or a direct building block of one; none is service_role-only.
-- 12. **No REST/GraphQL surface, no UI route -- matches the established boundary
--     every prior WMS/Advanced-TMS checkpoint in this range already discloses**
--     (e.g. app.wms_outbound_orders' own migration design note 11: "No UI route, no
--     REST/GraphQL surface"; app.warehouse_billing_events' own migration: "NO app/
--     route, NO REST/GraphQL surface this checkpoint"). Adversarial spec-compliance
--     review found this migration's own header was silent on the topic rather than
--     explicitly naming the same accepted boundary -- disclosed here rather than left
--     implicit: Prompt 242 section 14's "Shared REST/GraphQL read/list/search/
--     filter/cursor/export-request operations" and section 28's "REST/GraphQL
--     parity... tests" remain Step 13 Portal-consumer scope, exactly like every
--     Prompt 231-241 sibling's own identical read-surface-first precedent. Real,
--     typed service-layer wrappers exist now (server/{contracts,queries,mutations}/
--     customer-inventory-access.ts) for a future REST/GraphQL layer built on top to
--     consume directly without re-deriving scope/field-policy/masking/audit logic a
--     second way -- the actual API surface itself is not built here.
-- 13. **Grant validity (Prompt 242 sections 13/24/27's own literal "expiry")
--     cannot be implemented against the reused app.warehouse_customer_eligibility
--     table (ATW-229) as it stands.** That table's own `status` CHECK constraint
--     (supabase/migrations/20260730140000_create_advanced_tms_warehouse_zone.sql)
--     allows only 'active'/'revoked' -- no `expires_at`/validity-window column
--     exists. This migration's own db-test fixture and design note 1 above already
--     disclose "no new customer-warehouse grant table" as a deliberate reuse
--     decision; adding an expiry column/semantics to ATW-229's own already-applied
--     table is a real, but separate, capability-sized change (a new migration
--     altering that table plus its own grant/revoke RPCs, owned by whichever
--     checkpoint next revisits warehouse-customer eligibility) rather than a bounded
--     fix folded into this one. Flagged here explicitly, not silently assumed
--     covered by "active/revoked" -- revocation is fully implemented and proven
--     (design note above, db-test); time-bounded expiry is not, and cannot be until
--     that separate schema change lands.
-- 14. **Rate limiting (Prompt 242 sections 16/23) is not implemented for these 13
--     customer-facing RPCs, and this is disclosed rather than silently assumed
--     covered by RLS/RBAC alone.** The one precedent in this repository that DOES
--     implement real, queryable rate limiting (app.lookup_public_shipment_tracking,
--     OPS-180, supabase/migrations/20260728130000_create_operations_public_tracking.sql)
--     exists specifically because that surface is reachable by `anon` (genuinely unauthenticated,
--     no session, no account binding) -- its own app.tracking_lookup_attempts table
--     and trailing-window threshold is a purpose-built, capability-sized mechanism
--     for that specific threat model. Every RPC in this migration, by contrast,
--     requires an already-authenticated `authenticated` session resolving to a real,
--     active customer_user membership with a real owner+warehouse-eligibility grant
--     (design decisions 2-4 above) -- deny-by-default authorization already bounds
--     an unauthorized caller to zero rows regardless of request volume, which is a
--     materially different (and already-enforced) defense than anti-enumeration
--     rate limiting for a genuinely authorized-but-abusive caller (e.g. a legitimate
--     customer_user scripting rapid probing of forged IDs within their own scope).
--     That residual gap is real and not addressed here -- reusing OPS-180's own
--     mechanism verbatim is not a like-for-like fit (it is keyed by an anonymous
--     `client_key`, not an authenticated actor id), so a correctly-shaped
--     authenticated-caller rate limiter is left as a dedicated follow-up rather than
--     an under-scoped, rushed adaptation folded into this checkpoint.

-- 1. Shared eligibility predicate (design note 4) -- the one warehouse-eligibility
-- check every RPC below reuses, never re-derived.
create function app.customer_warehouse_eligibility_active(p_tenant_id uuid, p_warehouse_id uuid, p_owner_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1 from app.warehouse_customer_eligibility wce
    where wce.tenant_id = p_tenant_id
      and wce.warehouse_id = p_warehouse_id
      and wce.customer_account_id = p_owner_account_id
      and wce.status = 'active'
  );
$$;

comment on function app.customer_warehouse_eligibility_active is
  'ATW-242: true only if an ACTIVE app.warehouse_customer_eligibility row exists for the exact (tenant, warehouse, owner) triple -- reuses app.warehouse_customer_eligibility (ATW-229) verbatim, no new table. Revocation takes effect immediately: this is a live query against the current row, never a cached/point-in-time snapshot.';

-- 2. Owner-account scope resolver (design decision 4) -- ALWAYS returns a real
-- (possibly empty) array, never NULL/"unrestricted" (contrast with app.resolve_
-- actor_owner_account_scope, ATW-016, design note 2 above).
create function app.resolve_customer_owner_account_scope(p_auth_user_id uuid, p_tenant_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select coalesce(
    array_agg(distinct pm.customer_account_ref::uuid),
    array[]::uuid[]
  )
  from app.principal_memberships pm
  where pm.auth_user_id = p_auth_user_id
    and pm.tenant_id = p_tenant_id
    and pm.layer = 'customer_user'
    and pm.status = 'active'
    and pm.customer_account_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
$$;

comment on function app.resolve_customer_owner_account_scope is
  'ATW-242: every app.accounts.id this actor''s active customer_user membership(s) in this tenant resolve to (design decision 4). A non-uuid-shaped customer_account_ref (e.g. a legacy label from an unrelated capability) is silently excluded, never an error -- mirrors ATW-016''s own disclosed collision-avoidance boundary (design note 2 above). Deliberately narrower than app.resolve_actor_owner_account_scope: no staff/Supreme-Admin/no-membership "unrestricted" (null) branch -- a caller with zero active customer_user membership in this tenant gets an empty array, and every RPC below therefore returns zero rows for them, never an error and never another owner''s data.';

-- 3. The single gate primitive (design decision 3) -- deny-by-default, no OPS/staff
-- bypass, composes exactly the two checks above.
create function app.evaluate_customer_inventory_access(
  p_auth_user_id uuid,
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_owner_account_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    p_owner_account_id = any(app.resolve_customer_owner_account_scope(p_auth_user_id, p_tenant_id))
    and app.customer_warehouse_eligibility_active(p_tenant_id, p_warehouse_id, p_owner_account_id);
$$;

comment on function app.evaluate_customer_inventory_access is
  'ATW-242: true only if BOTH hold -- (a) an ACTIVE app.principal_memberships row for (auth_user_id, tenant_id), layer=customer_user, whose own uuid-shaped customer_account_ref equals p_owner_account_id; (b) an ACTIVE app.warehouse_customer_eligibility row for (tenant_id, warehouse_id, p_owner_account_id). No fallback path, no staff/OPS bypass -- answers exactly one question ("may this specific customer_user actor see this specific owner''s data in this specific warehouse"), the same narrow-wrapper shape app.has_view_personal_data (PLT-114) uses. A single-row get RPC calls this directly against the row it already fetched; a list/export RPC decomposes it (design note 4 above) for per-row performance.';

-- 4. app.get_customer_inventory_balance -- single permitted balance row,
-- anti-enumerating not-found (design note 5). Columns: id/warehouse_id/owner_
-- account_id/item_master_id/location_id/lot_number/serial_number/status/on_hand/
-- reserved/held/available/record_version/updated_at -- the full table (design note
-- 10: app.inventory_balances carries no internal-only field to begin with; every
-- column is safe for the row's own permitted owner to see), but named explicitly
-- rather than `returns app.inventory_balances`/`select *`.
create function app.get_customer_inventory_balance(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_balance_id uuid
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  item_master_id uuid,
  location_id uuid,
  lot_number text,
  serial_number text,
  status text,
  on_hand numeric,
  reserved numeric,
  held numeric,
  available numeric,
  record_version integer,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_balance app.inventory_balances;
begin
  select * into v_balance from app.inventory_balances b where b.id = p_balance_id and b.tenant_id = p_tenant_id;
  if not found then
    raise exception 'record_not_found: no permitted inventory balance exists for %', p_balance_id using errcode = 'no_data_found';
  end if;

  if not app.evaluate_customer_inventory_access(p_actor_auth_user_id, p_tenant_id, v_balance.warehouse_id, v_balance.owner_account_id) then
    raise exception 'record_not_found: no permitted inventory balance exists for %', p_balance_id using errcode = 'no_data_found';
  end if;

  return query
  select v_balance.id, v_balance.warehouse_id, v_balance.owner_account_id, v_balance.item_master_id, v_balance.location_id,
    v_balance.lot_number, v_balance.serial_number, v_balance.status, v_balance.on_hand, v_balance.reserved, v_balance.held,
    v_balance.available, v_balance.record_version, v_balance.updated_at;
end;
$$;

comment on function app.get_customer_inventory_balance is
  'ATW-242: raises the identical record_not_found (errcode no_data_found) whether p_balance_id genuinely does not exist, belongs to a different tenant, or exists but fails app.evaluate_customer_inventory_access -- design note 5. Not self-audited on the denial branch -- an audit insert cannot survive the subsequent RAISE within the same transaction (design note 9); this stays a pure, stable read. The TS service layer durably records the denial via a separate app.record_customer_inventory_access_denial call in a new transaction after catching this RPC''s own error (design note 9).';

-- 5. app.list_customer_inventory_balances -- cursor-paginated (design note 7),
-- excludes all-zero rows exactly as app.list_inventory_balances (ATW-015) already
-- does. Same column projection as the get RPC above.
create function app.list_customer_inventory_balances(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_item_master_id uuid default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  item_master_id uuid,
  location_id uuid,
  lot_number text,
  serial_number text,
  status text,
  on_hand numeric,
  reserved numeric,
  held numeric,
  available numeric,
  record_version integer,
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
  -- A cursor is a (timestamp, id) PAIR (design note 7) -- p_cursor_id supplied alone
  -- would otherwise silently filter out every row (a non-null-vs-null row comparison
  -- evaluates to unknown, which WHERE treats as false), returning an empty page
  -- instead of surfacing the caller's own malformed-cursor bug. Fails loud instead.
  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select b.id, b.warehouse_id, b.owner_account_id, b.item_master_id, b.location_id, b.lot_number, b.serial_number,
    b.status, b.on_hand, b.reserved, b.held, b.available, b.record_version, b.updated_at
  from app.inventory_balances b
  where b.tenant_id = p_tenant_id
    and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
    and (p_item_master_id is null or b.item_master_id = p_item_master_id)
    and (b.on_hand <> 0 or b.reserved <> 0 or b.held <> 0)
    and b.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, b.warehouse_id, b.owner_account_id)
    and (p_cursor_id is null or (b.updated_at, b.id) < (p_cursor_updated_at, p_cursor_id))
  order by b.updated_at desc, b.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_inventory_balances is
  'ATW-242: bounded (p_limit default 50, hard-capped 200), keyset-paginated on (updated_at desc, id desc), never OFFSET (design note 7). Excludes all-zero (on_hand=reserved=held=0) rows, mirroring app.list_inventory_balances (ATW-015). A caller with an empty resolved owner scope (design decision 4) gets zero rows, never an error.';

-- 6. app.list_customer_lot_identities -- owner+warehouse-eligibility-scoped tracked-
-- stock attributes (mirrors ATW-016's own separate-function convention -- not
-- unified with the serial list below). lot_identities carries no warehouse_id of its
-- own (design note 10's own table-by-table read confirmed this); eligibility is
-- therefore proven via an EXISTS against app.inventory_balances -- the same natural-
-- key join app.get_lot_trace (ATW-016) already uses against app.inventory_movement_
-- lines, generalized here to balances since a stable current warehouse presence,
-- not full movement history, is what an eligibility check needs. p_warehouse_id
-- (optional, like every other list RPC here) narrows to one warehouse; omitted, a
-- lot is included if the owner is eligible in ANY warehouse where that lot has real
-- balance presence.
create function app.list_customer_lot_identities(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_item_master_id uuid default null,
  p_owner_account_id uuid default null,
  p_status_filter text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  owner_account_id uuid,
  item_master_id uuid,
  lot_number text,
  manufacture_date date,
  expiry_date date,
  status text,
  hold_reason text,
  record_version integer,
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
  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select l.id, l.owner_account_id, l.item_master_id, l.lot_number, l.manufacture_date, l.expiry_date, l.status,
    l.hold_reason, l.record_version, l.updated_at
  from app.lot_identities l
  where l.tenant_id = p_tenant_id
    and l.owner_account_id = any(v_scope)
    and (p_owner_account_id is null or l.owner_account_id = p_owner_account_id)
    and (p_item_master_id is null or l.item_master_id = p_item_master_id)
    and (p_status_filter is null or l.status = p_status_filter)
    and exists (
      select 1 from app.inventory_balances b
      where b.tenant_id = l.tenant_id
        and b.owner_account_id = l.owner_account_id
        and b.item_master_id = l.item_master_id
        and b.lot_number = l.lot_number
        and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
        and app.customer_warehouse_eligibility_active(p_tenant_id, b.warehouse_id, l.owner_account_id)
    )
    and (p_cursor_id is null or (l.updated_at, l.id) < (p_cursor_updated_at, p_cursor_id))
  order by l.updated_at desc, l.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_lot_identities is
  'ATW-242: owner+warehouse-eligibility-scoped lot list. Columns exclude parent_lot_id/source_type/source_id/created_by (design note 10) and include hold_reason (a customer legitimately needs to know why their own lot is held, Prompt 242 field-policy guidance). Bounded, keyset-paginated on (updated_at desc, id desc).';

-- 7. app.list_customer_serial_identities -- mirrors the lot list above exactly for
-- app.serial_identities (separate function, not unified -- design note above).
create function app.list_customer_serial_identities(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_item_master_id uuid default null,
  p_owner_account_id uuid default null,
  p_status_filter text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  owner_account_id uuid,
  item_master_id uuid,
  serial_number text,
  lot_number text,
  manufacture_date date,
  expiry_date date,
  status text,
  hold_reason text,
  record_version integer,
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
  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select s.id, s.owner_account_id, s.item_master_id, s.serial_number, s.lot_number, s.manufacture_date, s.expiry_date,
    s.status, s.hold_reason, s.record_version, s.updated_at
  from app.serial_identities s
  where s.tenant_id = p_tenant_id
    and s.owner_account_id = any(v_scope)
    and (p_owner_account_id is null or s.owner_account_id = p_owner_account_id)
    and (p_item_master_id is null or s.item_master_id = p_item_master_id)
    and (p_status_filter is null or s.status = p_status_filter)
    and exists (
      select 1 from app.inventory_balances b
      where b.tenant_id = s.tenant_id
        and b.owner_account_id = s.owner_account_id
        and b.item_master_id = s.item_master_id
        and b.serial_number = s.serial_number
        and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
        and app.customer_warehouse_eligibility_active(p_tenant_id, b.warehouse_id, s.owner_account_id)
    )
    and (p_cursor_id is null or (s.updated_at, s.id) < (p_cursor_updated_at, p_cursor_id))
  order by s.updated_at desc, s.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_serial_identities is
  'ATW-242: mirrors app.list_customer_lot_identities exactly (design note above) for app.serial_identities. Excludes source_type/source_id/idempotency_key/created_by (design note 10).';

-- 8. app.get_customer_outbound_order -- order/status view, gated against the order''s
-- own owner_account_id/warehouse_id (design decision "re-check the gate against the
-- row"). Anti-enumerating not-found (design note 5).
create function app.get_customer_outbound_order(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_outbound_order_id uuid
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  outbound_number text,
  source_type text,
  requested_ship_date date,
  status text,
  cancelled_reason text,
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
  v_order app.wms_outbound_orders;
begin
  select * into v_order from app.wms_outbound_orders o where o.id = p_outbound_order_id and o.tenant_id = p_tenant_id;
  if not found then
    raise exception 'record_not_found: no permitted outbound order exists for %', p_outbound_order_id using errcode = 'no_data_found';
  end if;

  if not app.evaluate_customer_inventory_access(p_actor_auth_user_id, p_tenant_id, v_order.warehouse_id, v_order.owner_account_id) then
    raise exception 'record_not_found: no permitted outbound order exists for %', p_outbound_order_id using errcode = 'no_data_found';
  end if;

  return query
  select v_order.id, v_order.warehouse_id, v_order.owner_account_id, v_order.outbound_number, v_order.source_type,
    v_order.requested_ship_date, v_order.status, v_order.cancelled_reason, v_order.record_version, v_order.created_at, v_order.updated_at;
end;
$$;

comment on function app.get_customer_outbound_order is
  'ATW-242: columns exclude source_shipment_order_id/source_reason/idempotency_key/created_by (design note 10 -- internal correlation ids and an operational free-text note this RPC surface gives no way to resolve/act on). Anti-enumerating not-found, not self-audited on the denial branch, mirrors app.get_customer_inventory_balance exactly (design note 9) -- the TS service layer durably records the denial separately.';

-- 9. app.list_customer_outbound_order_lines -- reuses app.get_customer_outbound_order
-- for its own gate rather than duplicating it, exactly as app.list_wms_outbound_
-- order_lines (ATW-016A) already does for its own staff-facing counterpart.
create function app.list_customer_outbound_order_lines(p_outbound_order_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid,
  outbound_order_id uuid,
  line_number integer,
  item_master_id uuid,
  requested_uom_code text,
  requested_quantity numeric,
  lot_controlled boolean,
  serial_controlled boolean,
  expiry_controlled boolean,
  record_version integer,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_order app.wms_outbound_orders;
begin
  select * into v_order from app.wms_outbound_orders o where o.id = p_outbound_order_id;
  if not found then
    raise exception 'record_not_found: no permitted outbound order exists for %', p_outbound_order_id using errcode = 'no_data_found';
  end if;

  -- Re-derives the gate (and its own identically-shaped anti-enumerating denial)
  -- through app.get_customer_outbound_order rather than duplicating it.
  perform app.get_customer_outbound_order(v_order.tenant_id, p_actor_auth_user_id, p_outbound_order_id);

  return query
  select l.id, l.outbound_order_id, l.line_number, l.item_master_id, l.requested_uom_code, l.requested_quantity,
    l.lot_controlled, l.serial_controlled, l.expiry_controlled, l.record_version, l.updated_at
  from app.wms_outbound_order_lines l
  where l.outbound_order_id = p_outbound_order_id
  order by l.line_number;
end;
$$;

comment on function app.list_customer_outbound_order_lines is
  'ATW-242: columns exclude notes (free-text, potentially staff-internal -- design note 10). Reuses app.get_customer_outbound_order for its own authority/scope gate rather than duplicating it (mirrors ATW-016A''s own app.list_wms_outbound_order_lines).';

-- 10. app.list_customer_outbound_orders -- bounded, cursor-paginated list.
create function app.list_customer_outbound_orders(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_status_filter text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  outbound_number text,
  source_type text,
  requested_ship_date date,
  status text,
  cancelled_reason text,
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
  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select o.id, o.warehouse_id, o.owner_account_id, o.outbound_number, o.source_type, o.requested_ship_date, o.status,
    o.cancelled_reason, o.record_version, o.created_at, o.updated_at
  from app.wms_outbound_orders o
  where o.tenant_id = p_tenant_id
    and (p_warehouse_id is null or o.warehouse_id = p_warehouse_id)
    and (p_status_filter is null or o.status = p_status_filter)
    and o.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, o.warehouse_id, o.owner_account_id)
    and (p_cursor_id is null or (o.updated_at, o.id) < (p_cursor_updated_at, p_cursor_id))
  order by o.updated_at desc, o.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_outbound_orders is
  'ATW-242: same column projection and exclusions as app.get_customer_outbound_order. Bounded, keyset-paginated on (updated_at desc, id desc).';

-- 11. app.list_customer_inventory_movement_summary -- permitted movement lineage
-- summary, joined from app.inventory_movement_lines + app.inventory_movements
-- exactly the pattern app.get_lot_trace (ATW-016) already uses, gated by this
-- migration's own customer gate instead of OPS:View.
create function app.list_customer_inventory_movement_summary(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_item_master_id uuid default null,
  p_cursor_occurred_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  movement_id uuid,
  movement_type text,
  occurred_at timestamptz,
  item_master_id uuid,
  warehouse_id uuid,
  signed_quantity numeric,
  lot_number text,
  serial_number text
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
  if p_cursor_id is not null and p_cursor_occurred_at is null then
    raise exception 'invalid_cursor: p_cursor_occurred_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select ml.id, ml.movement_id, m.movement_type, m.occurred_at, ml.item_master_id, ml.warehouse_id, ml.signed_quantity,
    ml.lot_number, ml.serial_number
  from app.inventory_movement_lines ml
  join app.inventory_movements m on m.id = ml.movement_id
  where ml.tenant_id = p_tenant_id
    and (p_warehouse_id is null or ml.warehouse_id = p_warehouse_id)
    and (p_item_master_id is null or ml.item_master_id = p_item_master_id)
    and ml.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, ml.warehouse_id, ml.owner_account_id)
    and (p_cursor_id is null or (m.occurred_at, ml.id) < (p_cursor_occurred_at, p_cursor_id))
  order by m.occurred_at desc, ml.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_inventory_movement_summary is
  'ATW-242: movement_type/occurred_at/item_master_id/warehouse_id/signed_quantity/lot_number/serial_number only -- no internal source_type/posted_by (design note 10, Prompt 242''s own required column list verbatim). Bounded, keyset-paginated on (occurred_at desc, id desc) -- occurred_at, not updated_at/created_at, is the real chronological anchor of this joined read (design note 7).';

-- 12. app.export_customer_inventory_snapshot -- same filters/columns as app.list_
-- customer_inventory_balances, a larger but still bounded single-shot snapshot
-- (never OFFSET, no cursor -- an export, not a list). Always audited (design note
-- 9). A genuinely async/streaming large-volume export pipeline remains Step 13
-- Portal scope -- this is a real, bounded, synchronous RPC only, mirroring ATW-022''s
-- own "structurally ready, not yet populated by a real consumer" disclosure class;
-- no new async job pipeline is built here.
create function app.export_customer_inventory_snapshot(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_item_master_id uuid default null,
  p_limit integer default 500,
  p_actor_label text default null
)
returns table (
  id uuid,
  warehouse_id uuid,
  owner_account_id uuid,
  item_master_id uuid,
  location_id uuid,
  lot_number text,
  serial_number text,
  status text,
  on_hand numeric,
  reserved numeric,
  held numeric,
  available numeric,
  record_version integer,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
  v_matched_count integer;
  v_result_count integer;
begin
  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 500), 1), 1000);

  select count(*) into v_matched_count
  from app.inventory_balances b
  where b.tenant_id = p_tenant_id
    and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
    and (p_item_master_id is null or b.item_master_id = p_item_master_id)
    and (b.on_hand <> 0 or b.reserved <> 0 or b.held <> 0)
    and b.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, b.warehouse_id, b.owner_account_id);
  v_result_count := least(v_matched_count, v_limit);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, coalesce(p_actor_label, 'customer-portal-actor'), 'export_customer_inventory_snapshot',
    'app.inventory_balances', null, 'success', null, null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'item_master_id', p_item_master_id, 'limit', v_limit, 'result_count', v_result_count)
  );

  return query
  select b.id, b.warehouse_id, b.owner_account_id, b.item_master_id, b.location_id, b.lot_number, b.serial_number,
    b.status, b.on_hand, b.reserved, b.held, b.available, b.record_version, b.updated_at
  from app.inventory_balances b
  where b.tenant_id = p_tenant_id
    and (p_warehouse_id is null or b.warehouse_id = p_warehouse_id)
    and (p_item_master_id is null or b.item_master_id = p_item_master_id)
    and (b.on_hand <> 0 or b.reserved <> 0 or b.held <> 0)
    and b.owner_account_id = any(v_scope)
    and app.customer_warehouse_eligibility_active(p_tenant_id, b.warehouse_id, b.owner_account_id)
  order by b.updated_at desc, b.id desc
  limit v_limit;
end;
$$;

comment on function app.export_customer_inventory_snapshot is
  'ATW-242: p_limit default 500, hard-capped 1000 (larger than the plain list RPC''s own 200 cap, still bounded -- design note "export" above). Audits every call (actor, requested scope jsonb, result_count) regardless of outcome -- never the row payload itself (design note 9). No cursor -- a single bounded snapshot, not a list.';

-- 13. app.list_customer_warehouse_eligibility -- lets a customer_user actor see
-- their OWN warehouse eligibility grants (active AND revoked, so they can see why a
-- warehouse disappeared), filtered to their own resolved owner scope, NO OPS RBAC
-- gate at all -- reuses app.warehouse_customer_eligibility directly, no new table.
create function app.list_customer_warehouse_eligibility(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid,
  warehouse_id uuid,
  customer_account_id uuid,
  status text,
  granted_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text,
  record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
begin
  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);

  return query
  select wce.id, wce.warehouse_id, wce.customer_account_id, wce.status, wce.granted_at, wce.revoked_at, wce.revoked_reason, wce.record_version
  from app.warehouse_customer_eligibility wce
  where wce.tenant_id = p_tenant_id
    and wce.customer_account_id = any(v_scope)
  order by wce.granted_at desc;
end;
$$;

comment on function app.list_customer_warehouse_eligibility is
  'ATW-242: no OPS RBAC gate -- purely resolved-owner-scope, matching this being the one contract in the repository with a genuine customer_user-only authorization path. Columns exclude granted_by (a staff label -- design note 10) and include revoked_reason (a customer legitimately needs to know why a warehouse eligibility grant was revoked).';

-- 14. app.record_customer_inventory_access_denial -- durable denial audit (Prompt 242
-- §18: "result count/denial"), resolving design note 9's own disclosed conflict for
-- app.get_customer_inventory_balance/app.get_customer_outbound_order/app.list_
-- customer_outbound_order_lines. A SEPARATE RPC call the TS service layer
-- (server/queries/customer-inventory-access.ts) issues AFTER catching one of those
-- RPCs' own anti-enumerating record_not_found -- a genuinely NEW transaction, unlike
-- attempting to audit inside the same call that raises (which design note 9 already
-- proved empirically cannot survive the subsequent RAISE). Records only the fact and
-- the requested resource id of a denial -- never which of the two indistinguishable
-- causes (not-found vs forbidden) applied, and never any row content -- so callers
-- cannot use THIS rpc's own behavior (it always succeeds identically) to enumerate
-- either, and design note 5's anti-enumeration guarantee is not weakened at all.
create function app.record_customer_inventory_access_denial(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_resource_type text,
  p_resource_id uuid,
  p_actor_label text default null
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, coalesce(p_actor_label, 'customer-portal-actor'), 'customer_inventory_access_denied',
    p_resource_type, p_resource_id, 'failure', null, null, null
  );
end;
$$;

comment on function app.record_customer_inventory_access_denial is
  'ATW-242 hardening (adversarial spec-compliance review, Prompt 242 section 18): durable denial audit written in a fresh transaction after the fact -- never inside the same call as the anti-enumerating RAISE it follows. Always succeeds identically regardless of the real denial cause, so it cannot itself become an enumeration oracle. security definer so it can call app.capture_audit_event (service_role-only) on behalf of an authenticated caller, exactly like app.export_customer_inventory_snapshot already does above.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.customer_warehouse_eligibility_active(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.resolve_customer_owner_account_scope(uuid, uuid) to authenticated, service_role;
grant execute on function app.evaluate_customer_inventory_access(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_customer_inventory_balance(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_inventory_balances(uuid, uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_lot_identities(uuid, uuid, uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_serial_identities(uuid, uuid, uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.get_customer_outbound_order(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_outbound_order_lines(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_outbound_orders(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_inventory_movement_summary(uuid, uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.export_customer_inventory_snapshot(uuid, uuid, uuid, uuid, integer, text) to authenticated, service_role;
grant execute on function app.list_customer_warehouse_eligibility(uuid, uuid) to authenticated, service_role;
grant execute on function app.record_customer_inventory_access_denial(uuid, uuid, text, uuid, text) to authenticated, service_role;
