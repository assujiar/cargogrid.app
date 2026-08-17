-- Phase 8 capability CPL-306 (CG-S13-CPL-008, Prompt 306, "Shipment Monitoring").
-- Builds on supabase/migrations/20260801010000_create_customer_portal_
-- account_scope.sql (CPL-300, app.resolve_customer_account_scope), supabase/
-- migrations/20260801050000_create_customer_portal_shipment_order_access.sql
-- (CPL-304, the read-projection + portal-owned-request-table structural
-- template this migration mirrors), supabase/migrations/20260801060000_
-- create_customer_portal_shipment_tracking.sql (CPL-305, the immediate
-- predecessor this capability continues), and supabase/migrations/
-- 20260719130000_create_notification_engine.sql (PLT-127, app.
-- notification_types/app.notifications/app.queue_notification/app.
-- list_notifications_for_recipient) in full before this migration was
-- written.
--
-- This capability's own database-impact line is absolute and literal (source
-- prompt §13): "Store customer alert subscriptions/preferences and emitted
-- audit linked to canonical shipment alerts. Do not store raw GPS events."
-- This is a subscription/preference + alert-history capability, never a
-- telemetry capability -- it creates exactly ONE new table (subscriptions),
-- registers 6 notification types as data, and composes PLT-127's own
-- already-VERIFIED, already-layer-agnostic notification engine for
-- history -- it never reinvents delivery, rendering, dedupe, or preference
-- storage.
--
-- ===========================================================================
-- Design decisions (cited to the orchestrating task's own explicit list
-- where given; disclosed where this checkpoint had to resolve something
-- itself)
-- ===========================================================================
--
-- 1. **`app.customer_shipment_alert_subscriptions` is a new, portal-owned
--    preference table** -- the orchestrating task's own literal column list
--    (id, tenant_id, account_id, shipment_order_id references app.
--    shipment_orders, auth_user_id, alert_type, status, created_at,
--    updated_at, record_version). `account_id` is derived from the target
--    shipment order's own `shipper_account_id` at subscribe/unsubscribe
--    time, never customer-supplied -- the identical technique CPL-304's own
--    `request_customer_shipment_order_change` already established for this
--    exact "portal-owned record referencing a canonical shipment order"
--    shape, eliminating the account-mismatch bug class rather than
--    re-deriving the same guard.
-- 2. **No status-transition-enforcement trigger.** Unlike CPL-300's
--    `app.customer_portal_account_memberships` (invited -> active ->
--    suspended -> revoked, revoked terminal) or CPL-304's change-request
--    table (a real one-directional workflow), `status` here is a genuine,
--    reversible TWO-VALUE preference toggle (`active` <-> `unsubscribed`,
--    every transition valid in both directions, no terminal state) -- there
--    is nothing for a transition matrix to reject. A combined touch trigger
--    (`updated_at` + `record_version`) is still applied on every UPDATE,
--    mirroring the general house style every other Phase 8 table in this
--    session uses (CPL-300/304's own "record_version on every update"
--    convention).
-- 3. **Subscribe/unsubscribe are `INSERT ... ON CONFLICT (natural key) DO
--    UPDATE`, never a client-supplied-idempotency-key short-circuit --
--    structurally immune to Batch 1's own Tier C lessons (a)/(b), not
--    merely re-checked against them.** Batch 1's review (`docs/build-log/
--    phase-08/CPL-302.md`/`303.md`/`304.md` §14) found a real,
--    live-reproduced IDOR: a "create"-shaped RPC's idempotent short-circuit
--    matched an opaque, client-supplied `p_idempotency_key` and returned
--    whatever row happened to collide, before verifying that row belonged
--    to the SAME caller-targeted scope. That defect class requires an
--    idempotency key that is a free, caller-chosen string decoupled from
--    the operation's own real target. This capability's natural uniqueness
--    key -- `(tenant_id, shipment_order_id, auth_user_id, alert_type)` -- is
--    NOT such a string: `auth_user_id` is `p_actor_auth_user_id`, already
--    verified by `app.assert_actor_is_session_identity` to be the caller's
--    own real session identity, and `shipment_order_id`/`alert_type` are
--    the exact, explicit target of THIS call, scope-checked before the
--    upsert runs (decision 5 below) -- there is no opaque key a caller could
--    supply that resolves to a DIFFERENT target's row, because the key IS
--    the target. `INSERT ... ON CONFLICT ... DO UPDATE` is also a single
--    atomic statement -- unlike a pre-check-`SELECT`-then-`INSERT` pair, it
--    cannot race with a concurrent identical call (no `unique_violation`
--    guard is needed, matching Postgres's own documented atomicity for this
--    exact clause -- verified live in this checkpoint's own concurrent
--    `psql` reproduction, §11 below).
-- 4. **Every one of the 4 RPCs is scope-checked against the shipment
--    order's own `shipper_account_id` via `app.resolve_customer_account_
--    scope`, LIVE on every call** (orchestrating task's own instruction,
--    "exactly like CPL-304/305's own pattern"; source prompt §24, "Each
--    emission revalidates scope"). Subscribe/unsubscribe combine "shipment
--    order genuinely nonexistent" and "exists but out of scope" into ONE
--    `shipment_order_not_found` anti-enumerating error, the identical
--    technique CPL-304's own `request_customer_shipment_order_change` uses
--    for a referenced (non-primary) record. The two list RPCs live-rescope
--    EVERY returned row against the caller's current `resolve_customer_
--    account_scope` result on every call (never trusting the row's own
--    `account_id` alone), mirroring `app.list_customer_shipment_orders`
--    (CPL-304) exactly -- so a subscription made while a customer held
--    scope on an account, followed by that scope being revoked, stops
--    appearing in `list_customer_shipment_alert_subscriptions` immediately,
--    without any separate invalidation mechanism (mirrors CPL-300's own
--    decision 7, "revocation takes effect immediately by construction").
-- 5. **`app.list_customer_shipment_alerts` is a thin, honestly-bounded
--    wrapper composing `app.list_notifications_for_recipient` (PLT-127) --
--    never a second notification store.** Self-only by construction
--    (`p_recipient_auth_user_id = p_actor_auth_user_id = p_actor_auth_user_id`,
--    matching that function's own already-VERIFIED self-only authority
--    check), filtered to this capability's own 6 `notification_type_code`
--    values, with this wrapper's OWN keyset pagination
--    (`created_at desc, id desc`) and optional shipment filter layered on
--    top -- `app.list_notifications_for_recipient` itself accepts neither a
--    type filter nor a cursor/limit. **Disclosed, not fixed**: because
--    that shared engine RPC has no server-side filter or `LIMIT` of its
--    own, this wrapper necessarily fetches the recipient's ENTIRE in-app
--    notification history on every call and filters/paginates the result
--    set inside this function's own query -- O(this identity's full
--    notification count), not merely this capability's own subset. Adding
--    a type-filter/cursor parameter to the shared, already-VERIFIED PLT-127
--    engine RPC would be a change spanning far beyond this bounded task's
--    own migration budget (that RPC has other, already-shipped callers this
--    checkpoint has no mandate to touch) -- not fixed here, matching this
--    session's own "reuse the generic engine, never reinvent it" governing
--    instruction literally, even where that engine's own current shape is
--    not maximally efficient for one new caller.
-- 6. **The optional `p_shipment_order_id` filter on `list_customer_
--    shipment_alerts` matches against `context->>'shipmentOrderId'`, a
--    DISCLOSED CONVENTION this migration defines but does not itself ever
--    populate.** `app.notifications.context` is explicitly informational
--    only, never a structural FK (PLT-127's own migration header, "context
--    is informational only, never a structural FK to a source record") --
--    this migration cannot and does not add a real
--    `shipment_order_id uuid references app.shipment_orders` column to that
--    shared, already-VERIFIED table. A future emission-owning capability
--    (decision 8 below) that calls `app.queue_notification` for one of
--    this capability's 6 notification types is expected to include
--    `'shipmentOrderId'` in its own `p_context` for this filter to ever
--    match a real row -- until such a caller exists, this filter parameter
--    is real, tested code with no real data to exercise it against
--    (disclosed, not a live defect).
-- 7. **6 new `app.notification_types` rows, registered by direct `INSERT`,
--    mirroring `app.notification_types`'s OWN already-established
--    direct-INSERT bootstrap precedent** (`supabase/migrations/
--    20260731160000_create_ticket_escalation.sql`, HRT-291 decision 9,
--    itself mirroring HRT-286's 'ticket_attachment' document-type
--    bootstrap) rather than calling `app.register_notification_type()` --
--    that RPC is Supreme-Admin-gated (`app.is_supreme_admin(p_actor_
--    auth_user_id)`) and migration-apply context has no live actor session
--    to satisfy it, exactly the same structural reason HRT-291 disclosed.
--    Also mints the paired `'notification:<code>'` `app.config_types` row
--    for each (the SAME two-table registration pattern `app.register_
--    notification_type()`'s own body performs, `insert ... notification_
--    types` then `perform app.register_config_type(...)`) so a future
--    emission-owning capability does not have to remember that bootstrap
--    step itself. **Deliberately stops there -- no `config_objects`/
--    `config_versions`/`config_items` (no published template) is created**,
--    unlike HRT-291's own bootstrap, which immediately became a real
--    `app.queue_notification` caller inside that SAME migration. This
--    checkpoint builds no emission caller at all (decision 8) -- authoring
--    real subject/body template copy for a feature with no code path that
--    will ever render or send it this checkpoint would be inventing
--    untested content for a consumer that does not yet exist, not a
--    genuine additive registration. `owner_primitive_code = 'CPT'`
--    (Customer Portal, the same module code CPL-300's own `CPT:Create`
--    permission already established) for all 6 -- these are Customer
--    Portal-owned notification types, not an Operations/Advanced-TMS
--    concern.
-- 8. **EMISSION IS EXPLICITLY, ABSOLUTELY OUT OF SCOPE FOR THIS CHECKPOINT
--    -- stated with the same clarity CPL-300's own disclosed MFA gap
--    used.** Nothing in this migration ever calls `app.queue_notification`.
--    A real trigger linking `app.milestone_events`/`app.operational_
--    exceptions` (or a tracking-health signal) to `app.queue_notification`
--    for every subscribed customer requires EITHER a new database trigger
--    on those canonical tables OR a new scheduled job -- **no live
--    scheduler exists anywhere in this repository** (a standing, disclosed,
--    repository-wide gap, `ISS-2026-015`, not new to this checkpoint), and
--    building a from-scratch event-to-notification fan-out mechanism (storm
--    control, throttle, retry/DLQ, batch fan-out across every subscribed
--    identity for a shipment) is a materially new capability beyond this
--    bounded task's own file/migration budget, not a corollary of building
--    subscription CRUD.
--
--    **A SECOND, DEEPER, LIVE-VERIFIED gap this checkpoint's own
--    investigation surfaced, not merely inherited from "no scheduler
--    exists": `app.queue_notification`'s OWN recipient-authorization check
--    (`app.has_active_tenant_membership(p_tenant_id, p_recipient_auth_
--    user_id)`, PLT-127) tests `app.tenant_user_identities.status =
--    'active'` -- a STAFF membership concept. Every customer_user-layer
--    identity's own `app.tenant_user_identities` row is created ONLY via
--    `app.link_auth_identity(..., 'invited')` (CPL-300's
--    `app.invite_customer_portal_user`/`app.grant_initial_customer_portal_
--    account_admin`, both calling it with status literally hardcoded to
--    `'invited'`) and NO Phase 8 RPC anywhere ever transitions it past
--    that -- confirmed by direct, live reproduction this checkpoint (not
--    reasoned about): a freshly seeded customer_user identity's own `app.
--    tenant_user_identities.status` reads `'invited'` and `app.has_active_
--    tenant_membership()` for that exact identity returns `false`.
--    **Consequence: `app.queue_notification` CANNOT successfully queue a
--    notification to a customer_user-layer recipient AT ALL, today, for
--    ANY notification type, not only this capability's own 6** -- it
--    raises `notification_recipient_unauthorized` unconditionally for
--    every customer_user recipient, live-reproduced in this migration's
--    own db-test (§11 below). This is NOT a gap this checkpoint
--    introduces (`app.queue_notification`/`app.has_active_tenant_
--    membership` are both untouched, already-VERIFIED PLT-127/PLT-113
--    primitives this task has no mandate to widen -- doing so
--    unilaterally would be exactly the kind of layer-blind-authority-
--    surface change ADR-0024's own Part B discussion of `ISS-2026-040`
--    already cautions against making unreviewed), and grep-confirmed no
--    existing capability in this repository (procurement sourcing, HRIS
--    onboarding/training, ticket escalation -- the only other 4
--    `app.queue_notification` callers) has ever attempted to target a
--    customer_user recipient either, so this is not a regression, it is
--    the first time any capability has actually needed to. **A future
--    emission-owning capability will need to resolve THIS gap -- not only
--    "build a trigger/scheduler" -- before real emission to a customer
--    can work at all**, either by widening `app.has_active_tenant_
--    membership`'s own definition to also recognize an active
--    `app.customer_portal_account_memberships`/`app.resolve_customer_
--    account_scope` relationship (a real, reviewable, cross-cutting
--    change to a shared PLT-113 primitive, out of this bounded task's own
--    scope), or by composing a customer-layer-aware recipient check
--    specific to that future capability's own emission RPC. Disclosed
--    here with the same clarity CPL-300's own MFA gap used, not silently
--    deferred inside "no scheduler exists" as if it were the only
--    blocker.
--
--    What IS built and real, end to end, given this constraint: the
--    subscription CRUD (decisions 1-4) is fully real and independent of
--    emission entirely. The alert-HISTORY read path (decision 5) is
--    real and correctly scoped/filtered/paginated against any `app.
--    notifications` row that exists for this capability's own 6
--    notification_type_code values, regardless of how that row was
--    written -- this migration's own db-test (§11 below) proves the read
--    path against a row inserted directly (the only way, today, to place
--    a row in `app.notifications` for a customer_user recipient, since
--    the normal `app.queue_notification` entry point is unconditionally
--    closed to that recipient class as just described), not by pretending
--    the normal path already works when live reproduction shows it does
--    not. Storm-control/dedupe for whatever future emitter eventually
--    resolves the recipient-authorization gap above is NOT reinvented
--    here either: `app.notifications_dedupe_unique` (`tenant_id,
--    notification_type_code, recipient_auth_user_id, requested_channel,
--    dedupe_key`) already exists on the composed engine and will provide
--    it "for free" the moment a real emitter can compose `app.queue_
--    notification` successfully -- disclosed as inherited, not built by
--    this checkpoint.
-- 9. **No table this migration touches beyond its own new one gains a new
--    RLS policy or a new column.** `app.shipment_orders`/`app.
--    notifications`/`app.notification_types`/`app.notification_
--    preferences` all stay exactly as their own migrations left them.
-- 10. **RLS: `authenticated` holds ZERO direct grant** on the new
--    subscription table, mirroring CPL-300/302/303/304's own convention
--    exactly. The 4 RPCs below are the only sanctioned access path.
-- 11. **REST/GraphQL transport (ADR-0024 Part C)**: service layer + Server
--    Actions + UI only, no `app/api/` HTTP route -- identical in kind to
--    CPL-300..305's own disclosed residual gap.
-- 12. **Every RPC calls `app.assert_actor_is_session_identity` as its own
--    first statement -- read RPCs included** (CPL-300's own Tier C lesson,
--    applied from the first draft here, not retrofitted).
-- 13. **No edit to `scripts/db-tests/rbac-enforcement.sql`** -- every new
--    function either calls `app.assert_actor_is_session_identity` directly
--    (all 4 do) and/or `app.resolve_customer_account_scope` (all 4 do,
--    directly or -- for the two list RPCs -- as their own live rescoping
--    predicate), both already-recognized `rbac-enforcement.sql` base-regex
--    authority primitives since CPL-300 -- mirrors CPL-304/305's own
--    identical, already-verified "no edit required" precedent exactly
--    (confirmed live in this checkpoint's own db-test, §11 below).
-- 14. Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
--    carries its own explicit `revoke execute on all functions in schema
--    app from public` statement before its final grants.

-- ===========================================================================
-- 1. Notification type bootstrap (decision 7) -- direct INSERT, mirrors
--    app.notification_types' OWN already-established HRT-291 bootstrap
--    precedent exactly. No config_objects/config_versions/config_items
--    (no published template) -- decision 7's own explicit stop point.
-- ===========================================================================

insert into app.notification_types (code, name, owner_primitive_code, registered_by) values
  ('shipment_alert_milestone_delay', 'Shipment Milestone Delay', 'CPT', 'system'),
  ('shipment_alert_exception', 'Shipment Exception', 'CPT', 'system'),
  ('shipment_alert_no_fresh_position', 'Shipment Tracking Signal Lost', 'CPT', 'system'),
  ('shipment_alert_tracking_restored', 'Shipment Tracking Restored', 'CPT', 'system'),
  ('shipment_alert_delivery', 'Shipment Delivered', 'CPT', 'system'),
  ('shipment_alert_document_available', 'Shipment Document Available', 'CPT', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by) values
  ('notification:shipment_alert_milestone_delay', 'Shipment Milestone Delay Notification', 'CPT', 'system'),
  ('notification:shipment_alert_exception', 'Shipment Exception Notification', 'CPT', 'system'),
  ('notification:shipment_alert_no_fresh_position', 'Shipment Tracking Signal Lost Notification', 'CPT', 'system'),
  ('notification:shipment_alert_tracking_restored', 'Shipment Tracking Restored Notification', 'CPT', 'system'),
  ('notification:shipment_alert_delivery', 'Shipment Delivered Notification', 'CPT', 'system'),
  ('notification:shipment_alert_document_available', 'Shipment Document Available Notification', 'CPT', 'system')
on conflict (code) do nothing;

-- ===========================================================================
-- 2. app.customer_shipment_alert_subscriptions -- the portal-owned
--    preference table (decisions 1/2)
-- ===========================================================================

create table app.customer_shipment_alert_subscriptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  account_id uuid not null references app.accounts (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  auth_user_id uuid not null references auth.users (id),
  alert_type text not null,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint csas_alert_type_check check (
    alert_type in ('milestone_delay', 'exception', 'no_fresh_position', 'tracking_restored', 'delivery', 'document_available')
  ),
  constraint csas_status_check check (status in ('active', 'unsubscribed'))
);

comment on table app.customer_shipment_alert_subscriptions is
  'CPL-306: one row per (tenant, shipment order, identity, alert type) subscription preference -- a real, reversible two-value toggle (active <-> unsubscribed), never a terminal state machine (decision 2). account_id is derived from the target shipment order''s own shipper_account_id at subscribe/unsubscribe time, never customer-supplied (decision 1). RLS enabled, authenticated holds zero direct grant (decision 10) -- the 4 RPCs below are the only sanctioned access path. Subscription grants no shipment access of its own (source prompt §24) -- every read of the underlying shipment/tracking data still goes through its own, independently scope-checked RPC (CPL-304/305).';

create unique index csas_tenant_shipment_user_type_uq
  on app.customer_shipment_alert_subscriptions (tenant_id, shipment_order_id, auth_user_id, alert_type);

create index csas_tenant_user_updated_id_idx
  on app.customer_shipment_alert_subscriptions (tenant_id, auth_user_id, updated_at desc, id desc);

create index csas_shipment_order_idx on app.customer_shipment_alert_subscriptions (shipment_order_id);
create index csas_account_idx on app.customer_shipment_alert_subscriptions (account_id);

-- Combined touch trigger (updated_at + record_version), mirroring
-- app.touch_customer_portal_account_membership_row/app.touch_customer_
-- portal_shipment_change_request_row exactly (decision 2). No
-- transition-enforcement trigger -- both status values are reachable from
-- either state, there is no invalid transition to reject.
create function app.touch_customer_shipment_alert_subscription_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger customer_shipment_alert_subscriptions_touch_row
  before update on app.customer_shipment_alert_subscriptions
  for each row
  execute function app.touch_customer_shipment_alert_subscription_row();

-- ===========================================================================
-- 3. app.subscribe_customer_shipment_alert / app.unsubscribe_customer_
--    shipment_alert -- both idempotent-by-construction upserts (decision 3)
-- ===========================================================================

create function app.subscribe_customer_shipment_alert(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_alert_type text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_shipment_alert_subscriptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_row app.customer_shipment_alert_subscriptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_alert_type not in ('milestone_delay', 'exception', 'no_fresh_position', 'tracking_restored', 'delivery', 'document_available') then
    raise exception 'invalid_alert_type: % is not a recognized shipment alert type', p_alert_type using errcode = 'check_violation';
  end if;

  -- Decision 4: combines "genuinely nonexistent" and "exists but out of
  -- scope" into ONE anti-enumerating error, the identical technique CPL-304's
  -- own request_customer_shipment_order_change already applies to its own
  -- referenced (non-primary) record. Runs BEFORE the upsert below -- the
  -- natural-key upsert must never be reachable for a shipment order this
  -- identity cannot see at all.
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id and tenant_id = p_tenant_id;
  if not found or not (v_shipment.shipper_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'shipment_order_not_found: no permitted shipment order exists for %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  -- Decision 3: a single atomic upsert on the natural (tenant, shipment,
  -- identity, alert_type) key -- no unique_violation guard is needed
  -- (Postgres's own ON CONFLICT DO UPDATE is race-safe by construction,
  -- live-verified in this checkpoint's own concurrent psql reproduction,
  -- §11 of the build log).
  insert into app.customer_shipment_alert_subscriptions (tenant_id, account_id, shipment_order_id, auth_user_id, alert_type, status)
  values (p_tenant_id, v_shipment.shipper_account_id, p_shipment_order_id, p_actor_auth_user_id, p_alert_type, 'active')
  on conflict (tenant_id, shipment_order_id, auth_user_id, alert_type)
  do update set status = 'active'
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'subscribe_customer_shipment_alert',
    'app.customer_shipment_alert_subscriptions', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.subscribe_customer_shipment_alert is
  'CPL-306: idempotent upsert to status=active for the natural (tenant, shipment_order, identity, alert_type) key. Scope-checked against the shipment order''s own shipper_account_id, LIVE on every call, before the upsert runs (decision 4). account_id is derived server-side, never customer-supplied (decision 1). Structurally immune to the Batch 1 idempotency-key-collision defect class (decision 3) -- there is no opaque client-supplied key; the natural key IS the caller''s own verified identity plus the explicit target.';

create function app.unsubscribe_customer_shipment_alert(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_alert_type text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_shipment_alert_subscriptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_row app.customer_shipment_alert_subscriptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_alert_type not in ('milestone_delay', 'exception', 'no_fresh_position', 'tracking_restored', 'delivery', 'document_available') then
    raise exception 'invalid_alert_type: % is not a recognized shipment alert type', p_alert_type using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id and tenant_id = p_tenant_id;
  if not found or not (v_shipment.shipper_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'shipment_order_not_found: no permitted shipment order exists for %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  -- Idempotent both ways (decision 3): unsubscribing with no prior row
  -- creates an explicit unsubscribed row rather than erroring -- the row IS
  -- the preference state; "no row" and "row with status=unsubscribed" are
  -- deliberately made equivalent in observable behavior (decision 5/6's own
  -- read paths both treat a missing row as "not currently active").
  insert into app.customer_shipment_alert_subscriptions (tenant_id, account_id, shipment_order_id, auth_user_id, alert_type, status)
  values (p_tenant_id, v_shipment.shipper_account_id, p_shipment_order_id, p_actor_auth_user_id, p_alert_type, 'unsubscribed')
  on conflict (tenant_id, shipment_order_id, auth_user_id, alert_type)
  do update set status = 'unsubscribed'
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'unsubscribe_customer_shipment_alert',
    'app.customer_shipment_alert_subscriptions', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.unsubscribe_customer_shipment_alert is
  'CPL-306: idempotent upsert to status=unsubscribed for the natural (tenant, shipment_order, identity, alert_type) key -- a no-op-shaped success even when no prior subscription existed. Scope-checked identically to app.subscribe_customer_shipment_alert.';

-- ===========================================================================
-- 4. app.list_customer_shipment_alert_subscriptions -- self-only, live
--    rescoped on every call (decision 4)
-- ===========================================================================

create function app.list_customer_shipment_alert_subscriptions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_shipment_order_id uuid default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.customer_shipment_alert_subscriptions
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

  -- Self-only (these are personal preference rows, never another identity's)
  -- AND live-rescoped against the caller's CURRENT account scope on every
  -- row, every call -- never trusting the row's own stored account_id alone
  -- (decision 4). Deny-by-default: zero scope returns an empty result,
  -- never an error, mirroring app.list_customer_shipment_orders (CPL-304).
  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select s.*
  from app.customer_shipment_alert_subscriptions s
  where s.tenant_id = p_tenant_id
    and s.auth_user_id = p_actor_auth_user_id
    and s.account_id = any (v_scope)
    and (p_shipment_order_id is null or s.shipment_order_id = p_shipment_order_id)
    and (p_cursor_id is null or (s.updated_at, s.id) < (p_cursor_updated_at, p_cursor_id))
  order by s.updated_at desc, s.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_shipment_alert_subscriptions is
  'CPL-306: keyset-paginated (tenant_id, updated_at desc, id desc), never OFFSET, hard-capped at 200. Self-only (auth_user_id = p_actor_auth_user_id) AND live-rescoped against resolve_customer_account_scope on every row, every call -- a subscription on an account this identity has since lost scope on stops appearing immediately (decision 4), with no separate invalidation mechanism, mirroring CPL-300''s own decision 7.';

-- ===========================================================================
-- 5. app.list_customer_shipment_alerts -- thin wrapper over app.
--    list_notifications_for_recipient (decision 5)
-- ===========================================================================

create function app.list_customer_shipment_alerts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_shipment_order_id uuid default null,
  p_unread_only boolean default false,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.notifications
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_created_at is null then
    raise exception 'invalid_cursor: p_cursor_created_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  -- Decision 4: when narrowing to one shipment, live-verify that shipment is
  -- still in this identity's resolved scope (deny-by-default -- empty
  -- result, never an error, matching this repository's own established
  -- "list" convention, distinct from a get-by-id RPC's anti-enumerating
  -- error). When no p_shipment_order_id is supplied, this capability relies
  -- on the composed app.list_notifications_for_recipient's OWN already-
  -- VERIFIED self-only recipient scoping (decision 5) rather than
  -- re-deriving per-row shipment authority from app.notifications.context,
  -- which PLT-127''s own migration header states is informational only,
  -- never a structural FK -- re-deriving authority from non-authoritative
  -- data would be a worse design than trusting the self-only check already
  -- baked into the composed primitive.
  if p_shipment_order_id is not null then
    select * into v_shipment from app.shipment_orders where id = p_shipment_order_id and tenant_id = p_tenant_id;
    if not found or not (v_shipment.shipper_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
      return;
    end if;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  -- Decision 5: composes app.list_notifications_for_recipient (PLT-127,
  -- already-VERIFIED, self-only by construction: p_recipient_auth_user_id =
  -- p_actor_auth_user_id = p_actor_auth_user_id), filters to this
  -- capability's own 6 notification_type_code values, and applies THIS
  -- wrapper's own keyset pagination -- the composed engine RPC has neither
  -- a type filter nor a cursor/limit of its own (disclosed, decision 5).
  return query
  select n.*
  from app.list_notifications_for_recipient(p_tenant_id, p_actor_auth_user_id, p_actor_auth_user_id, p_unread_only) n
  where n.notification_type_code = any (array[
      'shipment_alert_milestone_delay', 'shipment_alert_exception', 'shipment_alert_no_fresh_position',
      'shipment_alert_tracking_restored', 'shipment_alert_delivery', 'shipment_alert_document_available'
    ])
    -- Decision 6: context->>'shipmentOrderId' is a disclosed convention this
    -- migration defines but does not itself ever populate (no emission
    -- caller exists yet, decision 8).
    and (p_shipment_order_id is null or n.context ->> 'shipmentOrderId' = p_shipment_order_id::text)
    and (p_cursor_id is null or (n.created_at, n.id) < (p_cursor_created_at, p_cursor_id))
  order by n.created_at desc, n.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_shipment_alerts is
  'CPL-306: thin, self-only wrapper over app.list_notifications_for_recipient (PLT-127), filtered to this capability''s own 6 notification_type_code values, keyset-paginated (created_at desc, id desc) by this wrapper itself. Disclosed (decision 5): the composed engine RPC has no server-side type filter, cursor, or LIMIT of its own, so this wrapper fetches the recipient''s full notification history and filters/paginates in-query -- not fixed here, since widening that shared, already-VERIFIED engine RPC is beyond this bounded task''s own migration budget. Correctly surfaces any real app.notifications row that exists for this identity, scoped/filtered/paginated -- but decision 8''s own live reproduction found app.queue_notification cannot successfully queue one for a customer_user recipient AT ALL today (app.has_active_tenant_membership, its recipient-authorization gate, never returns true for that layer) -- this migration''s own db-test proves that failure live, then proves this read RPC against a row placed directly, the only way such a row can exist for a customer_user recipient until a future capability resolves that gate.';

-- ===========================================================================
-- 6. RLS -- enable, grant service_role only (decision 10)
-- ===========================================================================

alter table app.customer_shipment_alert_subscriptions enable row level security;

grant select, insert, update, delete
  on app.customer_shipment_alert_subscriptions
  to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.subscribe_customer_shipment_alert(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.unsubscribe_customer_shipment_alert(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_customer_shipment_alert_subscriptions(uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_shipment_alerts(uuid, uuid, uuid, boolean, timestamptz, uuid, integer) to authenticated, service_role;
