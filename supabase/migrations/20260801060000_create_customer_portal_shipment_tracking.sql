-- Phase 8 capability CPL-305 (CG-S13-CPL-007, Prompt 305, "Tracking").
-- Read ADR-0024, supabase/migrations/20260801010000_create_customer_portal_
-- account_scope.sql (CPL-300), supabase/migrations/20260801050000_create_
-- customer_portal_shipment_order_access.sql (CPL-304), supabase/migrations/
-- 20260727140000_create_operations_milestone_management.sql (OPS-173),
-- supabase/migrations/20260730130000_create_advanced_tms_milestone_
-- exception_telemetry.sql (ATW-228), and supabase/migrations/20260729390000_
-- create_advanced_tms_canonical_telemetry_arbitration.sql (ATW-226F) in full
-- before this migration was written.
--
-- This capability's own database-impact line is absolute and literal (source
-- prompt §13): "Never create raw telemetry tables in Phase 8." This
-- migration creates ZERO tables. It is a pure read-composition capability --
-- one new SECURITY DEFINER RPC plus its own return-shape TYPE, over
-- already-existing, already-VERIFIED canonical data:
--   (a) app.milestone_events / app.milestone_codes (OPS-173/ATW-228)
--   (b) app.get_vehicle_current_position (ATW-226F -- the ONLY sanctioned
--       arbitrated-position read; app.canonical_telemetry_events/app.
--       vehicle_source_health, the raw per-source tables, are never touched)
--   (c) app._compute_shipment_leg_eta (ATW-228 -- internal, no actor, the
--       SAME function app.lookup_public_shipment_tracking, OPS-180, already
--       composes for its own anonymous customer-facing projection)
--   (d) app.is_shipment_tracking_entitled / app.resolve_tenant_tracking_
--       source_policy (ATW-226A -- tenant-level entitlement and the tenant's
--       own configured freshness threshold)
--
-- ===========================================================================
-- Design decisions (cited to the orchestrating task's own explicit list
-- where given; disclosed where this checkpoint had to resolve something
-- itself)
-- ===========================================================================
--
-- 1. **One new RPC, `app.get_customer_shipment_tracking(p_tenant_id,
--    p_actor_auth_user_id, p_shipment_order_id)`** -- SECURITY DEFINER,
--    `app.assert_actor_is_session_identity` first (CPL-300's own Tier C
--    lesson, applied from the first draft here, read RPC included), then the
--    IDENTICAL anti-enumerating scope check `app.get_customer_shipment_order`
--    (CPL-304) already uses against `app.shipment_orders.shipper_account_id`
--    -- "genuinely nonexistent" and "exists but out of scope" collapse into
--    ONE `record_not_found`, never a distinguishable error.
-- 2. **No new list RPC.** `app.list_customer_shipment_orders` (CPL-304)
--    already exists for that; this migration is detail/timeline composition
--    only, exactly as the orchestrating task's own design decision 4
--    specifies.
-- 3. **Return shape is a new named composite TYPE
--    (`app.customer_shipment_tracking_result`), not `returns table(...)`.**
--    CPL-304's own migration disclosed a real, live-caught defect: a
--    `returns table(...)` function's own implicitly-named OUT parameters
--    (`id`, `tenant_id`, ...) become genuinely ambiguous against a
--    same-named column referenced unqualified inside the function body. This
--    function's own OUT-shaped field names (`shipment_order_id`,
--    `tracking_entitled`, ...) do collide with real column names elsewhere
--    in this composition (`app.milestone_events.shipment_order_id`,
--    `app.shipment_leg_tracking_policies.tracking_required`) -- a plain
--    `RETURNS <composite type>` function declares NO implicit OUT
--    parameters at all (a local `v_result` variable must be declared and
--    populated explicitly), which removes this entire defect class
--    structurally rather than by remembering to alias every reference.
-- 4. **Milestone timeline (design decision (a)): replicates app.get_
--    shipment_milestone_timeline's own join/filter/order shape directly**
--    (`join app.milestone_codes mc on mc.code = e.milestone_code ... where
--    mc.is_customer_visible order by event_time asc, received_time asc,
--    sequence_no asc`) rather than calling that function, since it is itself
--    OPS:View-gated (staff-only) and not customer-callable. Projected to an
--    explicit, customer-safe field allowlist inside a `jsonb_build_object`
--    (never `to_jsonb(whole_row)`, C-07 discipline) -- `code`/`name`
--    (`app.milestone_codes.name`)/`category`/`eventTime` only. Confirmed by
--    direct inspection of `app.milestone_events`' own full, ATW-228-widened
--    column list (id, tenant_id, shipment_order_id, milestone_code,
--    event_time, received_time, location, source, reason, corrects_event_id,
--    idempotency_key, sequence_no, created_by, created_at, source_class,
--    source_confidence_score, source_freshness_status, source_candidate_id)
--    that the following are excluded as staff-internal / internal
--    source-conflict detail (source prompt §16): `received_time` (internal
--    ingestion timing), `location` (per-event coordinates -- matches app.
--    lookup_public_shipment_tracking's own identical exclusion, the closest
--    already-adversarially-reviewed customer-facing milestone precedent, in
--    this checkpoint's own deliberately conservative choice), `source`/
--    `reason`/`corrects_event_id` (internal ingestion/correction
--    provenance), `idempotency_key`/`sequence_no`/`created_by` (technical/
--    staff plumbing), and the four ATW-228 `source_class`/
--    `source_confidence_score`/`source_freshness_status`/
--    `source_candidate_id` columns (raw underlying-source classification --
--    source prompt §24's own "underlying source may be shown only as a safe
--    generic label when configured" business rule; no such generic-label
--    configuration exists anywhere in this repository yet, so the safest,
--    most-precedented choice is to omit the raw source class entirely rather
--    than invent a new disclosure surface this checkpoint has no mandate to
--    design).
-- 5. **Milestone visibility is gated ONLY by `app.milestone_codes.
--    is_customer_visible`, independent of tracking-package entitlement.**
--    The orchestrating task's own design decision 6 scopes ONLY "the
--    vehicle-position/ETA portion of the response" to the tenant-level
--    entitlement gate -- the canonical milestone timeline is not raw
--    telemetry and is not named as part of "live map/history" (source
--    prompt §20/§24: "Subscription governs live map/history"). A tenant not
--    entitled to live tracking still shows its own customer-visible
--    milestone history; only the live position/ETA portion below is
--    withheld.
-- 6. **Vehicle position (design decision (b)): composed via app.get_
--    vehicle_current_position only, never a raw table** -- resolves the
--    shipment's own active leg exactly like app.lookup_public_shipment_
--    tracking (OPS-180/ATW-228) already does (`leg_status in ('dispatched',
--    'in_transit')`, earliest by `sequence_no`), then the leg's own current
--    vehicle assignment (`app.resource_assignments`, role='vehicle',
--    is_current, active), then includes the position ONLY if that exact
--    leg's own `app.shipment_leg_tracking_policies.customer_visible` flag is
--    true -- byte-for-byte the same eligibility test the already-
--    adversarially-reviewed public tracking link uses. Exposed fields
--    (`vehicle_position_geojson`, `vehicle_position_updated_at`, `vehicle_
--    position_status`) are the identical field SET app.lookup_public_
--    shipment_tracking already exposes -- no `speed_kmh`/`heading_degrees`
--    (raw telemetry precision beyond what any existing, reviewed customer
--    surface discloses), and no raw `source_type` (source prompt §24's
--    "safe generic label" rule again -- omitted entirely, matching design
--    decision 4 above).
-- 7. **ETA (design decision (c)): app._compute_shipment_leg_eta is the
--    confirmed, real, currently-VERIFIED function** -- grep-confirmed
--    (`app.get_shipment_leg_eta_projection`, ATW-228, is a thin OPS:View +
--    record-scope-gated wrapper around it and is NOT customer-callable, the
--    identical situation as the milestone timeline in decision 4). This
--    migration calls the internal function directly -- the SAME function
--    app.lookup_public_shipment_tracking (OPS-180) already composes for its
--    own anonymous customer-facing projection, granted to `service_role`
--    only but callable here because this SECURITY DEFINER function runs as
--    its own owner, the identical established pattern every other
--    SECURITY DEFINER function in this repository already relies on to read
--    a service_role-only helper. Coarsened to `eta_status`
--    (on_time/delayed/unavailable) + `eta_at`, never a raw
--    `remaining_distance_km`/`delay_minutes` figure -- mirrors app.lookup_
--    public_shipment_tracking's own already-reviewed `live_eta_status`/
--    `live_eta_at` widening (ATW-228 design note 7) exactly, including the
--    identical `<= 30` minutes "still on_time" banding, rather than
--    inventing a second coarsening rule.
-- 8. **Freshness/degraded marker (design decision (d)): `vehicle_position_
--    status`, computed by comparing the position's own `received_at`
--    against the TENANT's own configured `freshness_threshold_seconds`**
--    (`app.resolve_tenant_tracking_source_policy`, ATW-226A -- explicit
--    override if the tenant has published one, else the system default of
--    300 seconds), with the identical 1x/3x healthy/stale-or-delayed/
--    offline-or-unavailable banding `app.get_vehicle_source_health` (ATW-
--    226F) and `app.lookup_public_shipment_tracking` (ATW-228) already use.
--    This is a reused, tenant-configurable, already-governed threshold --
--    never a new hardcoded constant of this migration's own invention.
-- 9. **`position_unavailable_reason` is a disclosed addition beyond the
--    orchestrating task's own literal (a)-(d) list** -- mirrors app._
--    compute_shipment_leg_eta's own "never a fabricated estimate, always a
--    named reason" discipline (ATW-228) and the source prompt's own
--    alternative flow (§22: "when data is stale/incomplete, show last
--    trusted update... do not fabricate live status"). One of
--    `tracking_not_entitled` / `no_active_leg` / `no_vehicle_assigned` /
--    `not_customer_visible` / `no_live_position`, or `null` once a real
--    position is included -- gives the UI one honest, always-present field
--    to render a specific message from, rather than inferring the reason
--    from which other fields happen to be null.
-- 10. **Subscription/package entitlement (design decision 6, disclosed,
--    exactly as the orchestrating task frames it): gates the vehicle-
--    position/ETA portion on the EXISTING tenant-level
--    `app.is_shipment_tracking_entitled`.** No new customer-portal-specific
--    entitlement tier is invented this checkpoint -- `00_EXECUTION_INDEX.md`
--    §3 item 8 names this exact question as a real, deliberately deferred
--    design decision beyond this bounded task's own mandate, and this
--    migration follows that deferral literally: if a tenant is not entitled
--    to live tracking at all, no customer of that tenant is either, and no
--    portal-specific tier is layered on top.
-- 11. **No table this migration touches gains a new RLS policy** (no table
--    is created or altered). `app.shipment_orders`/`app.milestone_events`/
--    `app.vehicle_current_positions`/etc. all stay exactly as their own
--    migrations left them -- this SECURITY DEFINER function reads them
--    directly (as its own owner) with its own explicit scope check in code,
--    the same established pattern every other Phase 8 read RPC uses (ADR-
--    0024 Part A).
-- 12. Per `ERR-2026-004` (docs/runtime/ERROR_LEDGER.md): this migration
--    carries its own explicit `revoke execute on all functions in schema
--    app from public` statement before its final grant.

-- ===========================================================================
-- 1. app.customer_shipment_tracking_result -- the composed return shape
--    (design decision 3)
-- ===========================================================================

create type app.customer_shipment_tracking_result as (
  shipment_order_id uuid,
  milestones jsonb,
  tracking_entitled boolean,
  position_unavailable_reason text,
  vehicle_position_geojson jsonb,
  vehicle_position_updated_at timestamptz,
  vehicle_position_status text,
  eta_status text,
  eta_at timestamptz
);

-- ===========================================================================
-- 2. app.get_customer_shipment_tracking
-- ===========================================================================

create function app.get_customer_shipment_tracking(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_shipment_order_id uuid
)
returns app.customer_shipment_tracking_result
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_result app.customer_shipment_tracking_result;
  v_active_leg_id uuid;
  v_vehicle_master_id uuid;
  v_customer_visible boolean;
  v_position record;
  v_policy record;
  v_eta app.shipment_leg_eta_projection;
begin
  -- CPL-300's own Tier C lesson: every RPC taking an identity parameter --
  -- read RPCs included -- calls this first, before any row is touched.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Anti-enumerating scope check (design decision 1), byte-for-byte the same
  -- shape app.get_customer_shipment_order (CPL-304) already uses.
  select so.* into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id and so.tenant_id = p_tenant_id;
  if not found or not (v_shipment.shipper_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'record_not_found: no permitted shipment order exists for %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_result.shipment_order_id := v_shipment.id;

  -- (a) Customer-visible milestone timeline (design decisions 4/5) --
  -- replicates app.get_shipment_milestone_timeline's own join/filter/order
  -- shape (that function itself is OPS:View-gated, not customer-callable),
  -- projected to an explicit customer-safe field allowlist.
  select coalesce(
    jsonb_agg(
      jsonb_build_object('code', e.milestone_code, 'name', mc.name, 'category', mc.category, 'eventTime', e.event_time)
      order by e.event_time asc, e.received_time asc, e.sequence_no asc
    ),
    '[]'::jsonb
  )
  into v_result.milestones
  from app.milestone_events e
  join app.milestone_codes mc on mc.code = e.milestone_code
  where e.shipment_order_id = v_shipment.id and mc.is_customer_visible;

  -- (f) Tenant-level entitlement (design decisions 6/10) -- gates ONLY the
  -- vehicle-position/ETA portion below, never the milestone timeline above.
  v_result.tracking_entitled := app.is_shipment_tracking_entitled(v_shipment.tenant_id);

  if not v_result.tracking_entitled then
    v_result.position_unavailable_reason := 'tracking_not_entitled';
    return v_result;
  end if;

  -- The shipment's own active leg -- identical resolution to app.lookup_
  -- public_shipment_tracking (OPS-180/ATW-228).
  select sl.id into v_active_leg_id
  from app.shipment_legs sl
  where sl.shipment_order_id = v_shipment.id and sl.leg_status in ('dispatched', 'in_transit')
  order by sl.sequence_no
  limit 1;

  if v_active_leg_id is null then
    v_result.position_unavailable_reason := 'no_active_leg';
    return v_result;
  end if;

  select ra.resource_id into v_vehicle_master_id
  from app.resource_assignments ra
  where ra.shipment_order_id = v_shipment.id and ra.role = 'vehicle' and ra.is_current and ra.status = 'active';

  if v_vehicle_master_id is null then
    v_result.position_unavailable_reason := 'no_vehicle_assigned';
    return v_result;
  end if;

  select p.customer_visible into v_customer_visible from app.shipment_leg_tracking_policies p where p.shipment_leg_id = v_active_leg_id;
  if not coalesce(v_customer_visible, false) then
    v_result.position_unavailable_reason := 'not_customer_visible';
    return v_result;
  end if;

  -- (b) Vehicle position -- the ONLY sanctioned arbitrated-position read
  -- (design decision 6). Never app.vehicle_current_positions/app.canonical_
  -- telemetry_events directly.
  select * into v_position from app.get_vehicle_current_position(v_vehicle_master_id);
  if found then
    select * into v_policy from app.resolve_tenant_tracking_source_policy(v_shipment.tenant_id);
    v_result.vehicle_position_geojson := v_position.location_geojson;
    v_result.vehicle_position_updated_at := v_position.received_at;
    -- (d) Freshness/degraded marker (design decision 8) -- the tenant's own
    -- configured freshness_threshold_seconds, identical 1x/3x banding to
    -- app.get_vehicle_source_health/app.lookup_public_shipment_tracking.
    v_result.vehicle_position_status := case
      when now() - v_position.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval then 'live'
      when now() - v_position.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval * 3 then 'delayed'
      else 'unavailable'
    end;
  else
    v_result.position_unavailable_reason := 'no_live_position';
  end if;

  -- (c) ETA -- app._compute_shipment_leg_eta (design decision 7), coarsened
  -- to eta_status/eta_at exactly like app.lookup_public_shipment_tracking's
  -- own already-reviewed live_eta_status/live_eta_at widening.
  v_eta := app._compute_shipment_leg_eta(v_active_leg_id);
  if v_eta.computable then
    v_result.eta_at := v_eta.estimated_arrival_at;
    v_result.eta_status := case
      when v_eta.delay_minutes is null then 'on_time'
      when v_eta.delay_minutes <= 30 then 'on_time'
      else 'delayed'
    end;
  else
    v_result.eta_status := 'unavailable';
  end if;

  return v_result;
end;
$$;

comment on function app.get_customer_shipment_tracking is
  'CPL-305: anti-enumerating (ADR-0024 Part A, design decision 1), customer-safe composition over already-canonical Operations/Advanced-TMS data -- never a raw telemetry table (source prompt §13, absolute). Composes (a) the customer-visible-only milestone timeline (app.milestone_events/app.milestone_codes, projected to an explicit field allowlist, never the raw row), (b) the arbitrated vehicle position (app.get_vehicle_current_position, the ONLY sanctioned read) gated on the active leg''s own app.shipment_leg_tracking_policies.customer_visible flag, (c) a coarsened ETA (app._compute_shipment_leg_eta, the same internal function app.lookup_public_shipment_tracking already composes), and (d) a tenant-policy-driven freshness/degraded marker. Vehicle-position/ETA are additionally gated on the EXISTING tenant-level app.is_shipment_tracking_entitled (design decision 10, 00_EXECUTION_INDEX.md §3 item 8''s own disclosed deferral) -- the milestone timeline itself is never gated by entitlement, only by mc.is_customer_visible. position_unavailable_reason (design decision 9) names exactly why the live portion is withheld, never silently absent.';

-- ===========================================================================
-- 3. Grants (design decision 12)
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.get_customer_shipment_tracking(uuid, uuid, uuid) to authenticated, service_role;
