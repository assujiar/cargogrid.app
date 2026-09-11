-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 3
-- (operations-tms-core) batch 4 (FINAL batch of cluster 3): shipment orders,
-- shipment mode profiles, vehicle capacity reservations, and shipment
-- exceptions. Continues the same Design->Verify->Fix adversarial pipeline
-- established by clusters 0-2 and cluster 3 batches 1-3: supabase/config.toml's
-- `schemas = ["public", "graphql_public"]` never exposes the "app" Postgres
-- schema to PostgREST, so every `.from()` read against an `app.*` table/view in
-- server/queries/*.ts has NEVER worked in production.
--
-- Closes the LAST 7 broken .from() call sites in cluster 3
-- (operations-tms-core), completing this cluster in full (20/20 tables,
-- 28/28 call sites):
--
--   server/queries/shipment-order.ts:47        getShipmentOrder
--   server/queries/shipment-order.ts:59        listShipmentOrdersForJobOrder
--   server/queries/shipment-order.ts:74        listShipmentOrders
--   server/queries/shipment-mode-baseline.ts:22  getShipmentModeProfile
--   server/queries/capacity-utilization.ts:36  listCapacityReservationsForLeg
--   server/queries/capacity-utilization.ts:46  listActiveCapacityReservationsForVehicle
--   server/queries/exception-escalation.ts:49  listShipmentExceptions
--
-- 7 new app.*/public.* Option-2 wrapper function pairs (14 functions total),
-- assembled from two independently designed and independently verified
-- scratchpad drafts (PART 1 and PART 2 below), cross-checked before assembly
-- to confirm no function-name collision and 4 distinct target tables/views
-- between them:
--
--   PART 1 (app.shipment_orders / app.shipment_mode_profiles):
--     app.get_shipment_order
--     app.list_shipment_orders_for_job_order
--     app.list_shipment_orders (server-paginated, exact total_count)
--     app.get_shipment_mode_profile
--
--   PART 2 (app.vehicle_capacity_reservations / app.exceptions_directory):
--     app.list_capacity_reservations_for_leg
--     app.list_active_capacity_reservations_for_vehicle
--     app.list_shipment_exceptions
--
-- ===========================================================================
-- SECURITY POSTURE (both parts) -- SECURITY INVOKER, ZERO actor parameter
-- ===========================================================================
-- Both parts independently reached the identical conclusion via this series'
-- own decisive test: trace every REAL call site of the target TS functions and
-- check whether any constructs its Supabase client via
-- createSupabaseServiceRoleClient() to claim an actor DECOUPLED from its own
-- session identity (which would force SECURITY DEFINER + an explicit
-- p_actor_auth_user_id + RULE A guard, as cluster 3 batch 1's dispatch
-- functions required). For all 7 functions in this migration, every real
-- caller (or, for the 3 functions in PART 2 with zero production callers
-- today, every test caller) uses createSupabaseServerClient() only (session-
-- scoped, RLS-subject) or a hand-rolled test fake -- never the service-role
-- client to claim a decoupled actor. Per this series' own decision procedure,
-- that routes to the SECURITY INVOKER conclusion cluster 3 batch 3 already
-- established for a negative decisive-test result:
--   1. No actor parameter is added to any of the 7 functions -- there is no
--      "claimed actor" identity for a RULE A guard to protect, and (per RULE
--      A's own point) an INVOKER function cannot honor an arbitrary actor
--      parameter as a filter anyway, since RLS's own `(select auth.uid())`
--      always resolves to the real calling session under invoker mode.
--   2. `service_role` already holds a DIRECT `select` grant on all 4 target
--      relations, independent of these new functions' existence
--      (app.shipment_orders: 20260727100000:495; app.shipment_mode_profiles:
--      20260727120000:283; app.vehicle_capacity_reservations:
--      20260730120000:375; app.exceptions_directory: 20260727150000:958) --
--      a SECURITY INVOKER function therefore grants the calling role no
--      capability beyond what a bare `select` already gives it.
--   3. `service_role` genuinely has BYPASSRLS in this project
--      (20260716075355_create_tenants.sql:230/242,
--      20260716113048_create_audit_trail.sql:446-451) -- safe here because
--      none of these 7 functions takes an actor parameter for BYPASSRLS to
--      silently defeat, and point 2 above means no new disclosure surface is
--      introduced.
--   4. Live sibling precedent: cluster 3 batch 3's own route-planning
--      functions (20260911030000) are SECURITY INVOKER, zero actor parameter,
--      over table families using the IDENTICAL `app.can_access_record`
--      predicate shape that PART 1's own 2 tables use directly (one hop
--      closer to the source table than batch 3's own precedent, not a
--      different pattern).
--
-- RULE A does not apply to any of the 7 functions below: none takes an actor
-- parameter, so there is no separate identity claim for
-- app.assert_actor_is_session_identity to cross-check.
--
-- ===========================================================================
-- RULE B -- RLS predicate currency (all 4 relations)
-- ===========================================================================
-- PART 1:
--   * shipment_orders_select_scoped (20260727100000_create_operations_
--     shipment_order.sql:481-483, the ORIGINAL and only-ever declaration --
--     repo-wide grep of both "create|alter policy" and the bare policy name
--     finds no rewrite anywhere in the migration set):
--       for select to authenticated
--       using (app.can_access_record((select auth.uid()), tenant_id,
--         owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id),
--         null));
--   * shipment_mode_profiles_select_scoped (20260727120000_create_operations_
--     mode_baseline.sql:271-279, the ORIGINAL and only-ever declaration --
--     same grep methodology, no rewrite found): a one-hop exists-join to
--     app.shipment_orders, using the identical can_access_record(...) gate.
--
-- PART 2:
--   * vehicle_capacity_reservations_select_scoped -- explicitly NOT the
--     can_access_record/owner-org-unit shape above; this is
--     TENANT-MEMBERSHIP-based. Repo-wide grep finds 2 real statements sorted
--     by filename: the ORIGINAL create policy
--     (20260730120000_create_advanced_tms_capacity_utilization.sql:369-371,
--     `(app.has_active_tenant_membership(tenant_id) OR
--     app.is_supreme_admin())`, no customer-layer exclusion yet), superseded
--     by an ALTER POLICY (20260730560000_harden_customer_user_layer_default_
--     deny.sql:337-338, USING clause only, `for select to authenticated`
--     role scope untouched) whose text is the CURRENT predicate:
--       (app.has_active_tenant_membership(tenant_id)
--         AND NOT app.actor_holds_customer_user_layer(tenant_id))
--         OR app.is_supreme_admin()
--     A second, independent grep of the bare policy name alone confirms the
--     same 2 hits, no third occurrence.
--   * app.exceptions_directory is a VIEW (20260727150000_create_operations_
--     exception_escalation.sql:933-947, never later replaced -- repo-wide
--     grep of "view app.exceptions_directory" finds only that one CREATE plus
--     its own COMMENT ON VIEW), not a table with its own RLS policy. Its row-
--     visibility WHERE clause is a plain, self-contained predicate keyed on
--     auth.uid() directly (a per-request GUC set from the caller's own JWT,
--     independent of which Postgres role evaluates it) -- NOT a predicate
--     delegated to RLS pass-through from its base tables. See PART 2's own
--     AUTHORITY SHAPE 2 section below for the full derivation, including the
--     affirmative precedent (app.users_directory/PLT-114,
--     20260716113048_create_audit_trail.sql) for why this distinction
--     matters and why exceptions_directory does not share that prior defect.
--
-- All 4 predicates above are relied on entirely via Postgres's own automatic
-- RLS/view evaluation under SECURITY INVOKER -- never re-implemented in SQL
-- in any function below.
--
-- ===========================================================================
-- SETOF-vs-BARE-COMPOSITE -- standing defect-class check (now checked in
-- every batch since first surfacing 3 batches ago)
-- ===========================================================================
-- app.get_shipment_order and app.get_shipment_mode_profile (both PART 1) are
-- genuine 0-or-1-row lookups -- bounded respectively by app.shipment_orders'
-- own primary key and by app.shipment_mode_profiles' own
-- shipment_mode_profiles_shipment_order_unique constraint -- and are declared
-- `returns setof app.<table>`, NEVER a bare (non-setof) composite return, per
-- the empirical finding first surfaced by
-- 20260911020000_fix_o1_cluster3_batch2_composite_return_null_bug.sql and
-- reused (not re-litigated) by cluster 3 batch 3 and again here: a non-setof
-- composite-returning function invoked via `select * from function(...)` --
-- exactly how each function's own public.* wrapper, and PostgREST/pg RPC's
-- own call machinery, invoke it -- returns ONE row of all-NULL columns on a
-- miss, not zero rows, which would throw an uncaught ZodError against this
-- codebase's own `row ? parse(row) : null` unwrap idiom instead of the
-- promised graceful null.
-- All 3 PART 2 functions are genuine, unbounded list reads (re-confirmed
-- directly against each TS function's own current body and
-- Promise<T[]>-typed signature -- no `.maybeSingle()`/`.single()`/`.limit(1)`
-- anywhere), so the null-on-miss defect class does not apply to them; `returns
-- setof` is used anyway, matching this series' own uniform list-function
-- convention.
--
-- ===========================================================================
-- GRANT PARITY (ISS-2026-309)
-- ===========================================================================
-- Every app.* function below: `revoke execute on function app.X(...) from
-- public;` then `grant execute on function app.X(...) to authenticated,
-- service_role;` -- matching all 4 relations' own direct grants exactly (none
-- grants `anon` anything). Every public.* wrapper below: `revoke execute on
-- function public.X(...) from anon, authenticated, service_role, public;`
-- then `grant execute on function public.X(...) to authenticated,
-- service_role;` -- the full 4-role revoke, per ISS-2026-309 (a bare `revoke
-- ... from public` does not undo this project's own ALTER DEFAULT PRIVILEGES
-- bootstrap grant of EXECUTE to anon/authenticated on every new public schema
-- function).
--
-- ===========================================================================
-- ADDITIONAL DEFECT FOUND (OUT OF SCOPE -- documented, not fixed here)
-- ===========================================================================
-- app.operational_exceptions was widened additively at ATW-228
-- (20260730130000_create_advanced_tms_milestone_exception_telemetry.sql:
-- 383-386) with 4 new nullable columns (source_class, source_confidence_score,
-- source_freshness_status, source_signal_id). app.exceptions_directory's own
-- view body was NEVER updated to project these 4 columns -- a real,
-- PRE-EXISTING data-completeness defect in the view itself, independent of
-- this batch's PostgREST-exposure remediation. It does not break parsing
-- (server/contracts/exception-escalation/exception-escalation.ts's own
-- parseExceptionDirectoryRow reads these via `row.source_class ?? null` etc.,
-- satisfying each field's `.nullable()` schema on a genuinely-missing key) --
-- every row read through this view simply always reports these 4 fields as
-- null, even when the underlying app.operational_exceptions row has real
-- values. This batch's scope is wrapper-only (Option-2: new app.*/public.*
-- functions + .rpc() call-site swap) and explicitly must not edit
-- app.exceptions_directory's own view definition -- app.list_shipment_exceptions
-- below reproduces the view's CURRENT (4-columns-short) output exactly,
-- unchanged. Fixing the view itself (a `create or replace view` adding the 4
-- missing projected columns) is a legitimate, separate follow-up outside this
-- batch's remit.
--
-- Assembled from two independently designed and independently verified
-- scratchpad drafts (shipment_order_and_mode_baseline.sql,
-- capacity_and_exceptions.sql) -- confirmed to share no function-name
-- collisions and to target 4 distinct relations between them before assembly.
-- ===========================================================================

-- ===========================================================================
-- PART 1: app.shipment_orders / app.shipment_mode_profiles
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. app.get_shipment_order -- replaces server/queries/shipment-order.ts:47
--    (getShipmentOrder)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("shipment_orders").select("*").eq("id", shipmentOrderId).maybeSingle()`.
create function app.get_shipment_order(p_shipment_order_id uuid)
returns setof app.shipment_orders
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.shipment_orders where id = p_shipment_order_id;
$$;

comment on function app.get_shipment_order(uuid) is
  'OPS-169/CG-S8-OPS-003/O1 remediation: one Shipment Order by its own primary key, replacing server/queries/shipment-order.ts:47''s broken .from("shipment_orders").select("*").eq("id", shipmentOrderId).maybeSingle() (app is not exposed to PostgREST). Security invoker, zero actor parameter -- every real call site of getShipmentOrder (route-planning/page.tsx:70, [shipmentOrderId]/page.tsx:121) uses createSupabaseServerClient() only, never the service-role client, and service_role already holds a direct `grant select on app.shipment_orders to service_role` (20260727100000:495) independent of this function -- see this migration''s own SECURITY POSTURE section for the full derivation. Relies entirely on the calling role''s own RLS evaluation of shipment_orders_select_scoped (20260727100000:481-483: app.can_access_record((select auth.uid()), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null)) -- reproduced by the live RLS engine, not re-implemented in this function''s own SQL body; RULE B confirms no rewrite of this policy exists anywhere in the migration set. No RULE A guard: no actor parameter exists to protect. `returns setof app.shipment_orders` (the table''s own composite row type, 31 columns, 1:1 with server/contracts/shipment-order/shipment-order.ts''s own ShipmentOrderSchema), deliberately NOT a bare (non-setof) composite -- see this migration''s own SETOF-vs-BARE-COMPOSITE section. `id uuid primary key` (20260727100000:77) bounds this read to 0-or-1 rows at the database level, independent of RLS. Returns zero rows -- never a row of nulls, never an exception -- for a nonexistent shipment_order_id or an actor who cannot reach that shipment order''s tenant/owner/org-unit scope; the TS caller''s existing `Array.isArray(data) ? data[0] : data` unwrap already treats that as null.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.get_shipment_order with an identical grant set and an identical
-- security mode (invoker, matching its app.* counterpart). `returns setof`,
-- matching app.get_shipment_order's own return shape exactly.
create function public.get_shipment_order(p_shipment_order_id uuid)
returns setof app.shipment_orders
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_shipment_order(p_shipment_order_id);
$wrap$;

comment on function public.get_shipment_order(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_shipment_order with an identical grant set and an identical security mode (invoker), never a reimplementation. Returns setof, not a bare composite -- see app.get_shipment_order''s own comment for why.';

revoke execute on function app.get_shipment_order(uuid) from public;
grant execute on function app.get_shipment_order(uuid) to authenticated, service_role;

revoke execute on function public.get_shipment_order(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_shipment_order(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. app.list_shipment_orders_for_job_order -- replaces server/queries/
--    shipment-order.ts:59 (listShipmentOrdersForJobOrder)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("shipment_orders").select("*").eq("job_order_id", jobOrderId)
-- .order("created_at", { ascending: false })`.
create function app.list_shipment_orders_for_job_order(p_job_order_id uuid)
returns setof app.shipment_orders
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.shipment_orders
  where job_order_id = p_job_order_id
  order by created_at desc;
$$;

comment on function app.list_shipment_orders_for_job_order(uuid) is
  'OPS-169/CG-S8-OPS-003/O1 remediation: every Shipment Order under one Job Order, newest first, replacing server/queries/shipment-order.ts:59''s broken .from("shipment_orders").select("*").eq("job_order_id", jobOrderId).order("created_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- same table and identical authority shape as app.get_shipment_order above; the one real call site (operations/shipment-orders/create/page.tsx:60) uses createSupabaseServerClient() only. Relies entirely on the calling role''s own RLS evaluation of shipment_orders_select_scoped (reproduced by citation under app.get_shipment_order''s own comment above). No RULE A guard: no actor parameter exists to protect. `returns setof app.shipment_orders`. `order by created_at desc` reproduces the original call''s own explicit ordering exactly; no id tie-break added -- this call returns its full result in one shot (no pagination in its own TS signature), unlike app.list_shipment_orders below, which does add one. Returns zero rows (never an exception) for a nonexistent job_order_id, a Job Order with no Shipment Orders split against it yet, or an actor who cannot reach any of its own Shipment Orders'' tenant/owner/org-unit scope -- matching the original RLS-filtered .from() call''s own current empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_shipment_orders_for_job_order with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart).
create function public.list_shipment_orders_for_job_order(p_job_order_id uuid)
returns setof app.shipment_orders
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_shipment_orders_for_job_order(p_job_order_id);
$wrap$;

comment on function public.list_shipment_orders_for_job_order(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_shipment_orders_for_job_order with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_shipment_orders_for_job_order(uuid) from public;
grant execute on function app.list_shipment_orders_for_job_order(uuid) to authenticated, service_role;

revoke execute on function public.list_shipment_orders_for_job_order(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_shipment_orders_for_job_order(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. app.list_shipment_orders -- replaces server/queries/shipment-order.ts:74
--    (listShipmentOrders)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("shipment_orders").select("*", { count: "exact" })
-- .eq("tenant_id", input.tenantId).order("created_at", { ascending: false })
-- .range(from, to)`.
--
-- `returns table (...)` column list transcribed directly, column-by-column,
-- from app.shipment_orders' own physical column order (20260727100000:76-116
-- plus the 2 additive columns held_from_status/leg_network_status): id,
-- tenant_id, job_order_id, shipment_number, idempotency_key, status,
-- shipper_account_id, consignee_snapshot, notify_party_snapshot,
-- cargo_service_snapshot, service_type, mode, origin, destination,
-- planned_pickup_at, planned_delivery_at, basis_quantity, basis_weight_kg,
-- basis_volume_cbm, allocated_quantity, allocated_weight_kg,
-- allocated_volume_cbm, split_reason, owner_user_id, org_unit_id,
-- record_version, created_by, created_at, updated_at, held_from_status,
-- leg_network_status, then the appended total_count.
create function app.list_shipment_orders(
  p_tenant_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  shipment_number text,
  idempotency_key text,
  status text,
  shipper_account_id uuid,
  consignee_snapshot jsonb,
  notify_party_snapshot jsonb,
  cargo_service_snapshot jsonb,
  service_type text,
  mode text,
  origin text,
  destination text,
  planned_pickup_at timestamptz,
  planned_delivery_at timestamptz,
  basis_quantity numeric,
  basis_weight_kg numeric,
  basis_volume_cbm numeric,
  allocated_quantity numeric,
  allocated_weight_kg numeric,
  allocated_volume_cbm numeric,
  split_reason text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  held_from_status text,
  leg_network_status text,
  total_count bigint
)
language plpgsql
stable
security invoker
set search_path = app, pg_temp
as $$
declare
  v_limit integer;
  v_page integer;
begin
  -- Defense in depth for a directly-callable RPC, mirroring the TS layer's own
  -- existing MAX_PAGE_SIZE=100/DEFAULT_PAGE_SIZE=50 clamp
  -- (server/queries/shipment-order.ts:22-23) and this series' own established
  -- app.list_portal_users clamp shape exactly.
  v_limit := least(greatest(coalesce(p_page_size, 50), 1), 100);
  v_page := greatest(coalesce(p_page, 1), 1);

  return query
    select
      so.id, so.tenant_id, so.job_order_id, so.shipment_number, so.idempotency_key,
      so.status, so.shipper_account_id, so.consignee_snapshot, so.notify_party_snapshot,
      so.cargo_service_snapshot, so.service_type, so.mode, so.origin, so.destination,
      so.planned_pickup_at, so.planned_delivery_at, so.basis_quantity,
      so.basis_weight_kg, so.basis_volume_cbm, so.allocated_quantity,
      so.allocated_weight_kg, so.allocated_volume_cbm, so.split_reason,
      so.owner_user_id, so.org_unit_id, so.record_version, so.created_by,
      so.created_at, so.updated_at, so.held_from_status, so.leg_network_status,
      count(*) over() as total_count
    from app.shipment_orders so
    where so.tenant_id = p_tenant_id
    order by so.created_at desc, so.id desc
    limit v_limit
    offset (v_page - 1) * v_limit;
end;
$$;

comment on function app.list_shipment_orders(uuid, integer, integer) is
  'OPS-169/CG-S8-OPS-003/O1 remediation: server-paginated Shipment Orders for one tenant with an exact total count, replacing server/queries/shipment-order.ts:74''s broken .from("shipment_orders").select("*", { count: "exact" }).eq("tenant_id", input.tenantId).order("created_at", { ascending: false }).range(from, to) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- the one real call site (operations/shipment-orders/page.tsx:41) uses createSupabaseServerClient() only, and service_role already holds a direct select grant on this table independent of this function. Relies entirely on the calling role''s own RLS evaluation of shipment_orders_select_scoped (reproduced by citation under app.get_shipment_order''s own comment above). No RULE A guard: no actor parameter exists to protect. Pagination + exact-count shape mirrors app.list_portal_users'' own established idiom exactly (declare/begin block, least/greatest clamp, `count(*) over()`, `returns table (...)`) rather than the two-function count/list split cluster 3 batch 1 used for its own dispatch screens -- that split exists there specifically to avoid re-running a per-row LATERAL function under an exact count; this query has no lateral join and no per-row function call of any kind, so that O(N) concern does not apply here, and the single-function established idiom is the correct choice. KNOWN, DISCLOSED CHARACTERISTIC inherited unchanged from that same idiom (not a new defect): `count(*) over()` is computed per SURVIVING row, so a page request whose OFFSET lands past the last matching row returns ZERO rows, and with zero rows there is no row to read total_count off of -- an out-of-range page therefore reports totalCount 0 rather than the true total (server/queries/portal-users.ts:80''s own already-shipped handling of this identical case is reproduced verbatim on the TS side). The ORIGINAL `.range()` + `count: ''exact''` PostgREST call this replaces did NOT have this limitation -- a disclosed behavior narrowing versus the never-actually-reachable original contract, inherited from this series'' own established pagination idiom rather than inventing a range-independent alternative. p_page/p_page_size are clamped server-side (1-100), mirroring the TS layer''s own existing clamp as defense in depth for a directly-callable RPC. `order by created_at desc, id desc` reproduces the original call''s own explicit ordering plus an id tie-break for determinism across page fetches, matching app.list_portal_users''/cluster 3 batch 1''s own established discipline for this exact arbitrary-page-jump shape. Returns an empty page (rows=[], total_count 0) -- never an exception -- for a tenant with zero visible Shipment Orders or a page past the last row.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_shipment_orders with an identical grant set and an identical
-- security mode (invoker, matching its app.* counterpart). `returns table (...)`,
-- an exact column-for-column copy of app.list_shipment_orders' own OUT
-- parameter list -- never a reimplementation or a re-derivation of the column
-- list from any other source.
create function public.list_shipment_orders(
  p_tenant_id uuid,
  p_page integer default 1,
  p_page_size integer default 50
)
returns table (
  id uuid,
  tenant_id uuid,
  job_order_id uuid,
  shipment_number text,
  idempotency_key text,
  status text,
  shipper_account_id uuid,
  consignee_snapshot jsonb,
  notify_party_snapshot jsonb,
  cargo_service_snapshot jsonb,
  service_type text,
  mode text,
  origin text,
  destination text,
  planned_pickup_at timestamptz,
  planned_delivery_at timestamptz,
  basis_quantity numeric,
  basis_weight_kg numeric,
  basis_volume_cbm numeric,
  allocated_quantity numeric,
  allocated_weight_kg numeric,
  allocated_volume_cbm numeric,
  split_reason text,
  owner_user_id uuid,
  org_unit_id uuid,
  record_version integer,
  created_by text,
  created_at timestamptz,
  updated_at timestamptz,
  held_from_status text,
  leg_network_status text,
  total_count bigint
)
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_shipment_orders(p_tenant_id, p_page, p_page_size);
$wrap$;

comment on function public.list_shipment_orders(uuid, integer, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_shipment_orders with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_shipment_orders(uuid, integer, integer) from public;
grant execute on function app.list_shipment_orders(uuid, integer, integer) to authenticated, service_role;

revoke execute on function public.list_shipment_orders(uuid, integer, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_shipment_orders(uuid, integer, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. app.get_shipment_mode_profile -- replaces server/queries/
--    shipment-mode-baseline.ts:22 (getShipmentModeProfile)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("shipment_mode_profiles").select("*")
-- .eq("shipment_order_id", shipmentOrderId).maybeSingle()`.
create function app.get_shipment_mode_profile(p_shipment_order_id uuid)
returns setof app.shipment_mode_profiles
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.shipment_mode_profiles where shipment_order_id = p_shipment_order_id;
$$;

comment on function app.get_shipment_mode_profile(uuid) is
  'OPS-171/CG-S8-OPS-005/O1 remediation: the one mode profile for a Shipment Order, if any, replacing server/queries/shipment-mode-baseline.ts:22''s broken .from("shipment_mode_profiles").select("*").eq("shipment_order_id", shipmentOrderId).maybeSingle() (app is not exposed to PostgREST). Security invoker, zero actor parameter -- the one real call site ([shipmentOrderId]/page.tsx:155) uses createSupabaseServerClient() only, and service_role already holds a direct `grant select on app.shipment_mode_profiles to authenticated, service_role` (20260727120000:283) independent of this function -- same 4-point reasoning as app.get_shipment_order above, independently re-applied to this table. Relies entirely on the calling role''s own RLS evaluation of shipment_mode_profiles_select_scoped (20260727120000:271-279: a one-hop exists-join to app.shipment_orders, `exists (select 1 from app.shipment_orders so where so.id = shipment_mode_profiles.shipment_order_id and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null))`) -- reproduced by the live RLS engine, not re-implemented in this function''s own SQL body. No RULE A guard: no actor parameter exists to protect. `returns setof app.shipment_mode_profiles` (the table''s own composite row type, 23 columns, 1:1 with server/contracts/shipment-mode-baseline/shipment-mode-baseline.ts''s own discriminated-union schema), deliberately NOT a bare (non-setof) composite -- identical empirical justification to app.get_shipment_order above (see this migration''s own SETOF-vs-BARE-COMPOSITE section): a bare composite return would yield one all-NULL row on a miss instead of zero rows, and `row.mode` on that all-NULL row would be NULL, matching none of parseShipmentModeProfile''s three discriminant branches -- throwing an uncaught ZodError (the z.discriminatedUnion itself failing to match any variant) rather than the promised graceful null. `constraint shipment_mode_profiles_shipment_order_unique unique (shipment_order_id)` (20260727120000:56) bounds this read to 0-or-1 rows at the database level, independent of RLS. Returns zero rows -- never a row of nulls, never an exception -- for a Shipment Order with no mode profile set yet, a nonexistent shipment_order_id, or an actor who cannot reach that shipment order''s tenant/owner/org-unit scope; the TS caller''s existing `Array.isArray(data) ? data[0] : data` unwrap already treats that as null.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.get_shipment_mode_profile with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart). `returns
-- setof`, matching app.get_shipment_mode_profile's own return shape exactly.
create function public.get_shipment_mode_profile(p_shipment_order_id uuid)
returns setof app.shipment_mode_profiles
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_shipment_mode_profile(p_shipment_order_id);
$wrap$;

comment on function public.get_shipment_mode_profile(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_shipment_mode_profile with an identical grant set and an identical security mode (invoker), never a reimplementation. Returns setof, not a bare composite -- see app.get_shipment_mode_profile''s own comment for why.';

revoke execute on function app.get_shipment_mode_profile(uuid) from public;
grant execute on function app.get_shipment_mode_profile(uuid) to authenticated, service_role;

revoke execute on function public.get_shipment_mode_profile(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_shipment_mode_profile(uuid) to authenticated, service_role;

-- ===========================================================================
-- PART 2: app.vehicle_capacity_reservations / app.exceptions_directory
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 5. app.list_capacity_reservations_for_leg -- replaces server/queries/
--    capacity-utilization.ts:36 (listCapacityReservationsForLeg)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("vehicle_capacity_reservations").select("*")
-- .eq("shipment_leg_id", shipmentLegId).order("created_at", { ascending: false })`.
create function app.list_capacity_reservations_for_leg(p_shipment_leg_id uuid)
returns setof app.vehicle_capacity_reservations
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.vehicle_capacity_reservations
  where shipment_leg_id = p_shipment_leg_id
  order by created_at desc;
$$;

comment on function app.list_capacity_reservations_for_leg(uuid) is
  'ATW-227/CG-S10-ATW-008/O1 remediation: the full reservation history (any status -- held/consumed/released) for one shipment leg, newest first, replacing server/queries/capacity-utilization.ts:36''s broken .from("vehicle_capacity_reservations").select("*").eq("shipment_leg_id", shipmentLegId).order("created_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter: no real caller anywhere in this repository invokes this via createSupabaseServiceRoleClient() to claim a decoupled actor -- both existing callers are unit tests using a hand-rolled fake client. Relies entirely on the calling role''s own live RLS evaluation of vehicle_capacity_reservations_select_scoped -- CURRENT text: the original 20260730120000:369-371 declaration was later rewritten by 20260730560000_harden_customer_user_layer_default_deny.sql:337 (ALTER POLICY, USING clause only -- the original `for select to authenticated` role scope is untouched), and that later text is genuinely current (repo-wide grep of both "create|alter policy ... vehicle_capacity_reservations" and the bare policy name both return the same 2 hits, nothing later). The live predicate is `(app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()` -- a tenant-membership shape, deliberately NOT the can_access_record/owner/org-unit-scoped shape used almost everywhere else in this series -- reproduced by the live RLS engine automatically, never re-implemented in this function''s own SQL body, so a future ALTER POLICY here needs no matching wrapper-function edit. The real calling role already holds a direct `grant select on app.vehicle_capacity_reservations to authenticated, service_role` (20260730120000:375) -- this function grants no capability beyond that bare select. No RULE A guard: no actor parameter exists to protect. `returns setof app.vehicle_capacity_reservations` (15 columns, matching server/contracts/capacity-utilization/capacity-utilization.ts''s own VehicleCapacityReservationSchema 1:1) -- a genuine unbounded list read (re-confirmed directly against the TS function''s own current Promise<VehicleCapacityReservation[]> signature and body -- no .maybeSingle()/.single()/.limit(1) anywhere in it), not a 0-or-1-row lookup, so the setof-vs-bare-composite null-on-miss defect class does not apply here, though setof is used anyway per this series'' own uniform list-function convention. Returns zero rows, never an exception, for a nonexistent shipment_leg_id or an actor whose session cannot pass the live predicate above -- matching the original RLS-filtered .from() read''s own current (never-actually-reachable) empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_capacity_reservations_for_leg with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart -- never a
-- reimplementation, and never a privilege upgrade the app.* function itself
-- does not have).
create function public.list_capacity_reservations_for_leg(p_shipment_leg_id uuid)
returns setof app.vehicle_capacity_reservations
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_capacity_reservations_for_leg(p_shipment_leg_id);
$wrap$;

comment on function public.list_capacity_reservations_for_leg(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_capacity_reservations_for_leg with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_capacity_reservations_for_leg(uuid) from public;
grant execute on function app.list_capacity_reservations_for_leg(uuid) to authenticated, service_role;

revoke execute on function public.list_capacity_reservations_for_leg(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_capacity_reservations_for_leg(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. app.list_active_capacity_reservations_for_vehicle -- replaces
--    server/queries/capacity-utilization.ts:46
--    (listActiveCapacityReservationsForVehicle)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("vehicle_capacity_reservations").select("*")
-- .eq("vehicle_master_id", vehicleMasterId).in("status", ["held", "consumed"])
-- .order("window_start", { ascending: true })`.
create function app.list_active_capacity_reservations_for_vehicle(p_vehicle_master_id uuid)
returns setof app.vehicle_capacity_reservations
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.vehicle_capacity_reservations
  where vehicle_master_id = p_vehicle_master_id
    and status in ('held', 'consumed')
  order by window_start asc;
$$;

comment on function app.list_active_capacity_reservations_for_vehicle(uuid) is
  'ATW-227/CG-S10-ATW-008/O1 remediation: every currently held/consumed (never released) reservation against one vehicle, earliest window first -- for a dispatcher checking a vehicle''s own committed schedule before assigning another leg -- replacing server/queries/capacity-utilization.ts:46''s broken .from("vehicle_capacity_reservations").select("*").eq("vehicle_master_id", vehicleMasterId).in("status", ["held","consumed"]).order("window_start", { ascending: true }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- same table, same authority shape, and same decisive-test outcome as app.list_capacity_reservations_for_leg above; no real caller of listActiveCapacityReservationsForVehicle exists anywhere in the repository besides a unit test using a hand-rolled fake client. Relies entirely on the calling role''s own live RLS evaluation of vehicle_capacity_reservations_select_scoped -- the identical CURRENT predicate cited under function 5 above, not re-implemented here. The real calling role already holds the same direct `grant select on app.vehicle_capacity_reservations to authenticated, service_role` (20260730120000:375). No RULE A guard: no actor parameter exists to protect. `returns setof app.vehicle_capacity_reservations` -- a genuine unbounded list read (a vehicle can hold many simultaneous held/consumed reservations across different legs; vehicle_capacity_reservations_active_leg_unique bounds ACTIVE status to at most one row per LEG, not per vehicle, so no row-count bound applies to this vehicle-scoped read) -- confirmed directly against the TS function''s own current Promise<VehicleCapacityReservation[]> signature and body (no .maybeSingle()/.single()/.limit(1)); setof used anyway per this series'' own uniform convention. `status in (''held'', ''consumed'')` reproduces the original call''s own `.in("status", ["held", "consumed"])` exactly -- released reservations are deliberately excluded. Returns zero rows, never an exception, for a nonexistent vehicle_master_id, a vehicle with no active reservations, or an actor whose session cannot pass the live predicate above -- matching the original RLS-filtered .from() read''s own current empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_active_capacity_reservations_for_vehicle with an identical grant
-- set and an identical security mode (invoker, matching its app.* counterpart).
create function public.list_active_capacity_reservations_for_vehicle(p_vehicle_master_id uuid)
returns setof app.vehicle_capacity_reservations
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_active_capacity_reservations_for_vehicle(p_vehicle_master_id);
$wrap$;

comment on function public.list_active_capacity_reservations_for_vehicle(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_active_capacity_reservations_for_vehicle with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_active_capacity_reservations_for_vehicle(uuid) from public;
grant execute on function app.list_active_capacity_reservations_for_vehicle(uuid) to authenticated, service_role;

revoke execute on function public.list_active_capacity_reservations_for_vehicle(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_active_capacity_reservations_for_vehicle(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. app.list_shipment_exceptions -- replaces server/queries/
--    exception-escalation.ts:49 (listShipmentExceptions)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("exceptions_directory").select("*")
-- .eq("shipment_order_id", shipmentOrderId).order("created_at", { ascending: false })`.
--
-- AUTHORITY SHAPE 2 (why SECURITY INVOKER is safe here, in more depth than the
-- table-based functions above): app.exceptions_directory's own row-visibility
-- WHERE clause (20260727150000:947: `where app.can_access_record(auth.uid(),
-- so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id),
-- null)`) is a plain, self-contained predicate keyed on auth.uid() -- a
-- per-request GUC set from the caller's own JWT, independent of which Postgres
-- ROLE evaluates it. That means this view's own scoping produces the
-- identical, correct result regardless of whether the SQL querying it runs as
-- SECURITY INVOKER (the real caller's role) or SECURITY DEFINER (the function
-- owner's role) -- unlike a view whose scoping is DELEGATED to base-table RLS
-- policies, where the executing role matters a great deal. This is not a
-- hypothetical distinction: 20260716113048_create_audit_trail.sql's own
-- comment documents that app.users_directory (PLT-114) "never actually
-- enforced tenant isolation" because it was a plain view that relied on the
-- UNDERLYING table's RLS policy for scoping while the view owner has
-- BYPASSRLS -- silently returning every tenant's rows to any authenticated
-- caller. app.exceptions_directory does NOT have this shape: its access
-- control is written directly into the view's own WHERE clause, not delegated
-- to RLS pass-through -- whether the view owner has BYPASSRLS is irrelevant to
-- this view's correctness.
create function app.list_shipment_exceptions(p_shipment_order_id uuid)
returns setof app.exceptions_directory
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.exceptions_directory
  where shipment_order_id = p_shipment_order_id
  order by created_at desc;
$$;

comment on function app.list_shipment_exceptions(uuid) is
  'OPS-174/CG-S8-OPS-008/O1 remediation: the field-masked list of exceptions for one Shipment Order, newest first, replacing server/queries/exception-escalation.ts:49''s broken .from("exceptions_directory").select("*").eq("shipment_order_id", shipmentOrderId).order("created_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter: no real caller anywhere in this repository invokes this via createSupabaseServiceRoleClient() to claim a decoupled actor -- the only existing caller is a unit test using a hand-rolled fake client. Selects directly from app.exceptions_directory itself -- never re-deriving the app.operational_exceptions/app.shipment_orders join, the can_access_record scoping, or the has_view_exception_cost-gated column masking by hand -- because doing so preserves both the view''s masking AND its access scoping exactly, with zero risk of the copy drifting from the view''s own current definition. This is safe under SECURITY INVOKER specifically because app.exceptions_directory''s own row-visibility WHERE clause is a plain, self-contained predicate keyed on auth.uid() -- see this migration''s own AUTHORITY SHAPE 2 note above for the full derivation, including the affirmative app.users_directory/PLT-114 precedent for why this distinction matters. `authenticated`/`service_role` already hold `grant select on app.exceptions_directory` directly (20260727150000:958) -- this function grants no capability beyond that bare select. No RULE A guard: no actor parameter exists to protect. `returns setof app.exceptions_directory` (the view''s own composite row type) -- a genuine unbounded list read (one Shipment Order can have arbitrarily many exceptions; no unique constraint bounds this read to 0-or-1 rows) -- confirmed directly against the TS function''s own current Promise<ExceptionDirectoryRow[]> signature and body (no .maybeSingle()/.single()/.limit(1)); setof used anyway per this series'' own uniform convention. NOTE (out of scope, not fixed by this function): app.exceptions_directory''s own column list was never widened to include the 4 provenance columns (source_class/source_confidence_score/source_freshness_status/source_signal_id) added to app.operational_exceptions at ATW-228 (20260730130000) -- this function''s `select *` therefore reproduces the view''s CURRENT output exactly, including that pre-existing omission; see this migration''s own ADDITIONAL DEFECT FOUND section. Returns zero rows, never an exception, for a nonexistent shipment_order_id or an actor who cannot pass can_access_record for that shipment order''s tenant/owner/org-unit scope -- matching the original RLS-filtered .from() read''s own current empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_shipment_exceptions with an identical grant set and an identical
-- security mode (invoker, matching its app.* counterpart -- never a
-- reimplementation, and never a privilege upgrade the app.* function itself
-- does not have).
create function public.list_shipment_exceptions(p_shipment_order_id uuid)
returns setof app.exceptions_directory
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_shipment_exceptions(p_shipment_order_id);
$wrap$;

comment on function public.list_shipment_exceptions(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_shipment_exceptions with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_shipment_exceptions(uuid) from public;
grant execute on function app.list_shipment_exceptions(uuid) to authenticated, service_role;

revoke execute on function public.list_shipment_exceptions(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_shipment_exceptions(uuid) to authenticated, service_role;
