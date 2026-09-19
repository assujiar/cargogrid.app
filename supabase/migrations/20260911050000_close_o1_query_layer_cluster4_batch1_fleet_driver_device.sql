-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 4
-- (telematics-tracking) batch 1: Fleet, Vehicle, Driver, Device and SIM
-- Operational Baseline reads (ATW-223, CG-S10-ATW-004).
--
-- supabase/config.toml's `schemas = ["public", "graphql_public"]` never exposes
-- the "app" Postgres schema to PostgREST, so every `.from()` read against an
-- app.* table in server/queries/*.ts has NEVER worked in production. This
-- migration closes ALL 7 broken .from() call sites in this cluster's first
-- batch, all in one file:
--
--   server/queries/fleet-driver-device.ts:37   listVehicleOperationalProfiles
--   server/queries/fleet-driver-device.ts:46   listDriverOperationalProfiles
--   server/queries/fleet-driver-device.ts:55   listGpsDevices
--   server/queries/fleet-driver-device.ts:64   listSimCards
--   server/queries/fleet-driver-device.ts:73   listDeviceVehicleAssignmentHistory
--   server/queries/fleet-driver-device.ts:82   listProviderVehicleMappings
--   server/queries/fleet-driver-device.ts:91   listVehicleTrackingSourcePriorities
--
-- All 7 target tables are declared in ONE prior migration
-- (20260729310000_create_advanced_tms_fleet_driver_device.sql), so this batch
-- is a single self-contained unit.
--
-- ===========================================================================
-- KEY FINDING -- device_vehicle_assignments/provider_vehicle_mappings/
-- vehicle_tracking_source_priorities are NOT join-derived authority
-- ===========================================================================
-- The 3 tables filtered by device_id/vehicle_master_id (not tenant_id) might
-- appear to derive their authority via a join to a device/vehicle-master
-- record. Independently verified false: reading each table's own `create
-- table` statement (20260729310000:206-278) shows all 3 carry their OWN
-- `tenant_id uuid not null references app.tenants (id)` column, physically
-- independent of the device_id/vehicle_master_id column the TS query happens
-- to filter by. Their SELECT policies (20260729310000:1054/1058/1062, later
-- ALTER POLICY'd by 20260730560000:118/292/352) are the IDENTICAL plain
-- tenant_id-column shape as the other 4 tables in this same migration --
-- `(app.has_active_tenant_membership(tenant_id) AND NOT
-- app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()`
-- -- no EXISTS/join to app.master_records, app.gps_devices, or
-- app.vehicle_operational_profiles appears anywhere in any of the 14 policy
-- statements (7 original CREATE POLICY + 7 later ALTER POLICY) across both
-- migrations. The TS query's own filter column and the RLS policy's own
-- authority column are simply two different, independent columns on the
-- same row -- there is no join-based derivation to find. Functions 5-7 below
-- were written accordingly.
--
-- ===========================================================================
-- SECURITY POSTURE -- SECURITY INVOKER, ZERO actor parameter, all 7 functions
-- ===========================================================================
-- Applied this series' own decisive test to every one of the 7 TS functions:
-- trace every REAL call site and check whether any constructs its Supabase
-- client via createSupabaseServiceRoleClient() to claim an actor DECOUPLED from
-- its own session identity (which would force SECURITY DEFINER + an explicit
-- p_actor_auth_user_id + a RULE A app.assert_actor_is_session_identity guard).
--
--   * listVehicleOperationalProfiles, listDriverOperationalProfiles,
--     listGpsDevices, listSimCards, listProviderVehicleMappings,
--     listVehicleTrackingSourcePriorities: exactly ONE real production caller
--     each, all in the SAME file, app/(tenant)/[tenantSlug]/operations/fleet/
--     page.tsx (lines 74-77 for the first 4, lines 92-93 for the last 2), which
--     constructs its client via `const supabase = await
--     createSupabaseServerClient()` (page.tsx:3,52) -- session-scoped, RLS-
--     subject, never the service-role client. No other production call site
--     exists for any of these 6.
--   * listDeviceVehicleAssignmentHistory: ZERO real callers anywhere in this
--     repository -- not in any page/action/component, and not even in
--     server/queries/fleet-driver-device.test.ts (whose imports list only
--     listVehicleOperationalProfiles and listGpsDevices). This function is
--     genuinely dead/unwired code today -- see ADDITIONAL DEFECT FOUND below.
--     With no caller of any kind, there is a fortiori no service-role caller,
--     so the decisive test returns the same negative result as the other 6 by
--     the absence of any positive case to the contrary.
--
-- Per this series' own decision procedure, a negative decisive-test result
-- across every real (or, absent a real caller, every conceivable) caller
-- routes to SECURITY INVOKER, zero actor parameter, for all 7 functions:
--   1. No actor parameter is added to any of the 7 -- there is no "claimed
--      actor" identity for a RULE A guard to protect, and an INVOKER function
--      cannot honor an arbitrary actor parameter as a filter anyway, since
--      RLS's own `(select auth.uid())`/`auth.uid()` always resolves to the
--      real calling session under invoker mode.
--   2. `service_role` already holds a DIRECT `grant select` on all 7 target
--      relations, independent of these new functions' existence
--      (20260729310000:1068/1070/1072/1074/1076/1078/1080 -- one grant per
--      table, `to authenticated, service_role`) -- a SECURITY INVOKER function
--      therefore grants the calling role no capability beyond what a bare
--      `select` already gives it.
--   3. `service_role` genuinely has BYPASSRLS in this project
--      (20260716075355_create_tenants.sql:230/242,
--      20260716113048_create_audit_trail.sql:446-451) -- safe here because none
--      of these 7 functions takes an actor parameter for BYPASSRLS to silently
--      defeat, and point 2 above means no new disclosure surface is
--      introduced.
--   4. Live sibling precedent: cluster 3 batch 3's route-planning functions
--      (20260911030000) and cluster 3 batch 4's PART 2 functions
--      (20260911040000, over app.vehicle_capacity_reservations -- itself
--      governed by the IDENTICAL `(has_active_tenant_membership(tenant_id) AND
--      NOT actor_holds_customer_user_layer(tenant_id)) OR is_supreme_admin()`
--      predicate shape as all 7 tables in this batch, both altered by the same
--      20260730560000 hardening migration) are SECURITY INVOKER, zero actor
--      parameter, over a table family using this exact tenant-membership
--      predicate shape -- not a new pattern being introduced here.
--
-- RULE A does not apply to any of the 7 functions below: none takes an actor
-- parameter, so there is no separate identity claim for
-- app.assert_actor_is_session_identity to cross-check.
--
-- ===========================================================================
-- RULE B -- RLS predicate currency (all 7 relations)
-- ===========================================================================
-- All 7 tables share the IDENTICAL authority shape and the IDENTICAL 2-hit
-- history: an ORIGINAL `create policy ..._select_scoped` in
-- 20260729310000_create_advanced_tms_fleet_driver_device.sql, later rewritten
-- (USING clause only -- `for select to authenticated` role scope untouched in
-- every case) by exactly one `alter policy` in
-- 20260730560000_harden_customer_user_layer_default_deny.sql:
--
--   vehicle_operational_profiles_select_scoped:
--     CREATE 20260729310000:1038-1040; ALTER 20260730560000:343-344
--   driver_operational_profiles_select_scoped:
--     CREATE 20260729310000:1042-1044; ALTER 20260730560000:133-134
--   gps_devices_select_scoped:
--     CREATE 20260729310000:1046-1048; ALTER 20260730560000:250-251
--   sim_cards_select_scoped:
--     CREATE 20260729310000:1050-1052; ALTER 20260730560000:310-311
--   device_vehicle_assignments_select_scoped:
--     CREATE 20260729310000:1054-1056; ALTER 20260730560000:118-119
--   provider_vehicle_mappings_select_scoped:
--     CREATE 20260729310000:1058-1060; ALTER 20260730560000:292-293
--   vehicle_tracking_source_priorities_select_scoped:
--     CREATE 20260729310000:1062-1064; ALTER 20260730560000:352-353
--
-- The CURRENT (post-ALTER) predicate, identical in shape for all 7 tables,
-- differing only in which table's own tenant_id column is read:
--
--   (app.has_active_tenant_membership(tenant_id)
--     AND NOT app.actor_holds_customer_user_layer(tenant_id))
--     OR app.is_supreme_admin()
--
-- All 7 predicates are relied on entirely via Postgres's own automatic RLS
-- evaluation under SECURITY INVOKER -- never re-implemented in SQL in any
-- function below.
--
-- ===========================================================================
-- RULE C -- no pre-existing app.* function is cited or reproduced by value
-- ===========================================================================
-- No function below calls or re-implements the body of any other app.*
-- function. The 3 predicate helpers named above (app.has_active_tenant_
-- membership, app.actor_holds_customer_user_layer, app.is_supreme_admin) are
-- invoked ONLY by the live RLS engine automatically under SECURITY INVOKER --
-- never called directly from any function body below.
--
-- ===========================================================================
-- SETOF-vs-BARE-COMPOSITE -- standing defect-class check (not applicable here)
-- ===========================================================================
-- All 7 functions below are genuine, unbounded list reads -- confirmed
-- directly against each TS function's own current Promise<T[]>-typed
-- signature and `(data ?? []).map(...)` body (no `.maybeSingle()`/`.single()`/
-- `.limit(1)` anywhere) -- so the null-on-miss defect class first surfaced by
-- 20260911020000_fix_o1_cluster3_batch2_composite_return_null_bug.sql does not
-- apply to any of them. `returns setof app.<table>` is used on all 7 anyway,
-- matching this series' own uniform list-function convention.
--
-- ===========================================================================
-- COLUMN MASKING -- independently verified, not merely trusted
-- ===========================================================================
-- fleet-driver-device.ts's own file header claims "No masked column exists on
-- any of these tables." Verified directly, table by table, by diffing each
-- table's own physical column list (20260729310000) against its own parse*()
-- function in server/contracts/fleet-driver-device/fleet-driver-device.ts --
-- an exact 1:1 match on all 7, column-for-column:
--   vehicle_operational_profiles (14 cols) <-> parseVehicleOperationalProfile (14)
--   driver_operational_profiles (12 cols)  <-> parseDriverOperationalProfile (12)
--   gps_devices (10 cols)                  <-> parseGpsDevice (10)
--   sim_cards (11 cols)                    <-> parseSimCard (11)
--   device_vehicle_assignments (11 cols)   <-> parseDeviceVehicleAssignment (11)
--   provider_vehicle_mappings (10 cols)    <-> parseProviderVehicleMapping (10)
--   vehicle_tracking_source_priorities (10 cols) <-> parseVehicleTrackingSourcePriority (10)
-- The claim is genuine for this batch -- every function below uses `select *`
-- against its own table, never an explicit column list that could silently
-- drift from this parity.
--
-- ===========================================================================
-- GRANT PARITY (ISS-2026-309)
-- ===========================================================================
-- Every app.* function below: `revoke execute on function app.X(...) from
-- public;` then `grant execute on function app.X(...) to authenticated,
-- service_role;` -- matching all 7 relations' own direct grants exactly (none
-- grants `anon` anything). Every public.* wrapper below: the full 4-role
-- revoke per ISS-2026-309 (`revoke execute on function public.X(...) from
-- anon, authenticated, service_role, public;`) then `grant execute on
-- function public.X(...) to authenticated, service_role;`.
--
-- ===========================================================================
-- ADDITIONAL DEFECT FOUND (OUT OF SCOPE -- documented, not fixed here)
-- ===========================================================================
-- server/queries/fleet-driver-device.ts:72's listDeviceVehicleAssignmentHistory
-- is dead code today: zero real callers, and zero test callers, anywhere in
-- this repository. This migration still adds a wrapper for it
-- (app.list_device_vehicle_assignment_history), matching this batch's own
-- explicit scope (all 7 named call sites), and because a future caller wiring
-- this function up is entirely plausible -- but flagging the current dead-code
-- status here so it is not mistaken for a live regression fix.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. app.list_vehicle_operational_profiles -- replaces server/queries/
--    fleet-driver-device.ts:37 (listVehicleOperationalProfiles)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("vehicle_operational_profiles").select("*")
-- .eq("tenant_id", tenantId).order("created_at", { ascending: false })`.
create function app.list_vehicle_operational_profiles(p_tenant_id uuid)
returns setof app.vehicle_operational_profiles
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.vehicle_operational_profiles
  where tenant_id = p_tenant_id
  order by created_at desc;
$$;

comment on function app.list_vehicle_operational_profiles(uuid) is
  'ATW-223/CG-S10-ATW-004/O1 remediation: every vehicle operational profile for one tenant, newest first, replacing server/queries/fleet-driver-device.ts:37''s broken .from("vehicle_operational_profiles").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- the one real call site (app/(tenant)/[tenantSlug]/operations/fleet/page.tsx:74) uses createSupabaseServerClient() only, never the service-role client, and service_role already holds a direct `grant select on app.vehicle_operational_profiles to authenticated, service_role` (20260729310000:1068) independent of this function -- see this migration''s own SECURITY POSTURE section for the full derivation. Relies entirely on the calling role''s own RLS evaluation of vehicle_operational_profiles_select_scoped -- CURRENT text (post 20260730560000:343-344 ALTER POLICY, RULE B confirms no later rewrite): `(app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()` -- reproduced by the live RLS engine, never re-implemented in this function''s own SQL body. No RULE A guard: no actor parameter exists to protect. `returns setof app.vehicle_operational_profiles` (14 columns, 1:1 with server/contracts/fleet-driver-device/fleet-driver-device.ts''s own parseVehicleOperationalProfile -- independently column-diffed, no masking). A genuine unbounded list read (a tenant may register arbitrarily many vehicle profiles; no unique constraint bounds this tenant-scoped read to 0-or-1 rows) -- confirmed directly against the TS function''s own current Promise<VehicleOperationalProfile[]> signature and body (no .maybeSingle()/.single()/.limit(1)); setof used anyway per this series'' own uniform list-function convention. `order by created_at desc` reproduces the original call''s own explicit ordering exactly; no id tie-break added, matching the original call''s own behavior (this function has no pagination in its own TS signature). Returns zero rows -- never an exception -- for a tenant with no vehicle profiles yet or an actor whose session cannot pass the predicate above, matching the original RLS-filtered .from() read''s own current empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_vehicle_operational_profiles with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart), never a
-- reimplementation.
create function public.list_vehicle_operational_profiles(p_tenant_id uuid)
returns setof app.vehicle_operational_profiles
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_vehicle_operational_profiles(p_tenant_id);
$wrap$;

comment on function public.list_vehicle_operational_profiles(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_vehicle_operational_profiles with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_vehicle_operational_profiles(uuid) from public;
grant execute on function app.list_vehicle_operational_profiles(uuid) to authenticated, service_role;

revoke execute on function public.list_vehicle_operational_profiles(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_vehicle_operational_profiles(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. app.list_driver_operational_profiles -- replaces server/queries/
--    fleet-driver-device.ts:46 (listDriverOperationalProfiles)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("driver_operational_profiles").select("*")
-- .eq("tenant_id", tenantId).order("created_at", { ascending: false })`.
create function app.list_driver_operational_profiles(p_tenant_id uuid)
returns setof app.driver_operational_profiles
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.driver_operational_profiles
  where tenant_id = p_tenant_id
  order by created_at desc;
$$;

comment on function app.list_driver_operational_profiles(uuid) is
  'ATW-223/CG-S10-ATW-004/O1 remediation: every driver operational profile for one tenant, newest first, replacing server/queries/fleet-driver-device.ts:46''s broken .from("driver_operational_profiles").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- same table family, same authority shape, and same decisive-test outcome as app.list_vehicle_operational_profiles above; the one real call site (app/(tenant)/[tenantSlug]/operations/fleet/page.tsx:75) uses createSupabaseServerClient() only. Relies entirely on the calling role''s own RLS evaluation of driver_operational_profiles_select_scoped -- CURRENT text (post 20260730560000:133-134 ALTER POLICY, RULE B confirms no later rewrite): `(app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()` -- reproduced by the live RLS engine, never re-implemented here. The real calling role already holds a direct `grant select on app.driver_operational_profiles to authenticated, service_role` (20260729310000:1070). No RULE A guard: no actor parameter exists to protect. `returns setof app.driver_operational_profiles` (12 columns, 1:1 with parseDriverOperationalProfile -- independently column-diffed, no masking). A genuine unbounded list read (confirmed against the TS function''s own current Promise<DriverOperationalProfile[]> signature and body; no .maybeSingle()/.single()/.limit(1)); setof used anyway per this series'' own uniform convention. `order by created_at desc` reproduces the original call''s own explicit ordering exactly. Returns zero rows -- never an exception -- for a tenant with no driver profiles yet or an actor whose session cannot pass the predicate above, matching the original RLS-filtered .from() read''s own current empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_driver_operational_profiles with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart), never a
-- reimplementation.
create function public.list_driver_operational_profiles(p_tenant_id uuid)
returns setof app.driver_operational_profiles
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_driver_operational_profiles(p_tenant_id);
$wrap$;

comment on function public.list_driver_operational_profiles(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_driver_operational_profiles with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_driver_operational_profiles(uuid) from public;
grant execute on function app.list_driver_operational_profiles(uuid) to authenticated, service_role;

revoke execute on function public.list_driver_operational_profiles(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_driver_operational_profiles(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. app.list_gps_devices -- replaces server/queries/fleet-driver-device.ts:55
--    (listGpsDevices)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("gps_devices").select("*").eq("tenant_id", tenantId)
-- .order("created_at", { ascending: false })`.
create function app.list_gps_devices(p_tenant_id uuid)
returns setof app.gps_devices
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.gps_devices
  where tenant_id = p_tenant_id
  order by created_at desc;
$$;

comment on function app.list_gps_devices(uuid) is
  'ATW-223/CG-S10-ATW-004/O1 remediation: every GPS device in one tenant''s inventory, newest first, replacing server/queries/fleet-driver-device.ts:55''s broken .from("gps_devices").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- same authority shape and same decisive-test outcome as app.list_vehicle_operational_profiles above; the one real call site (app/(tenant)/[tenantSlug]/operations/fleet/page.tsx:76) uses createSupabaseServerClient() only. Relies entirely on the calling role''s own RLS evaluation of gps_devices_select_scoped -- CURRENT text (post 20260730560000:250-251 ALTER POLICY, RULE B confirms no later rewrite): `(app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()` -- reproduced by the live RLS engine, never re-implemented here. The real calling role already holds a direct `grant select on app.gps_devices to authenticated, service_role` (20260729310000:1072). No RULE A guard: no actor parameter exists to protect. `returns setof app.gps_devices` (10 columns, 1:1 with parseGpsDevice -- independently column-diffed, no masking; no service-role key or provider credential is ever stored on this row, so this list read carries no secret-disclosure risk). A genuine unbounded list read (confirmed against the TS function''s own current Promise<GpsDevice[]> signature and body; no .maybeSingle()/.single()/.limit(1)); setof used anyway per this series'' own uniform convention. `order by created_at desc` reproduces the original call''s own explicit ordering exactly. Returns zero rows -- never an exception -- for a tenant with no devices yet or an actor whose session cannot pass the predicate above, matching the original RLS-filtered .from() read''s own current empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_gps_devices with an identical grant set and an identical security
-- mode (invoker, matching its app.* counterpart), never a reimplementation.
create function public.list_gps_devices(p_tenant_id uuid)
returns setof app.gps_devices
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_gps_devices(p_tenant_id);
$wrap$;

comment on function public.list_gps_devices(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_gps_devices with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_gps_devices(uuid) from public;
grant execute on function app.list_gps_devices(uuid) to authenticated, service_role;

revoke execute on function public.list_gps_devices(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_gps_devices(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. app.list_sim_cards -- replaces server/queries/fleet-driver-device.ts:64
--    (listSimCards)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("sim_cards").select("*").eq("tenant_id", tenantId)
-- .order("created_at", { ascending: false })`.
create function app.list_sim_cards(p_tenant_id uuid)
returns setof app.sim_cards
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.sim_cards
  where tenant_id = p_tenant_id
  order by created_at desc;
$$;

comment on function app.list_sim_cards(uuid) is
  'ATW-223/CG-S10-ATW-004/O1 remediation: every SIM card in one tenant''s inventory, newest first, replacing server/queries/fleet-driver-device.ts:64''s broken .from("sim_cards").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- same authority shape and same decisive-test outcome as app.list_vehicle_operational_profiles above; the one real call site (app/(tenant)/[tenantSlug]/operations/fleet/page.tsx:77) uses createSupabaseServerClient() only. Relies entirely on the calling role''s own RLS evaluation of sim_cards_select_scoped -- CURRENT text (post 20260730560000:310-311 ALTER POLICY, RULE B confirms no later rewrite): `(app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()` -- reproduced by the live RLS engine, never re-implemented here. The real calling role already holds a direct `grant select on app.sim_cards to authenticated, service_role` (20260729310000:1074). No RULE A guard: no actor parameter exists to protect. `returns setof app.sim_cards` (11 columns including current_device_id, a mutable pointer, 1:1 with parseSimCard -- independently column-diffed, no masking). A genuine unbounded list read (confirmed against the TS function''s own current Promise<SimCard[]> signature and body; no .maybeSingle()/.single()/.limit(1)); setof used anyway per this series'' own uniform convention. `order by created_at desc` reproduces the original call''s own explicit ordering exactly. Returns zero rows -- never an exception -- for a tenant with no SIM cards yet or an actor whose session cannot pass the predicate above, matching the original RLS-filtered .from() read''s own current empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_sim_cards with an identical grant set and an identical security
-- mode (invoker, matching its app.* counterpart), never a reimplementation.
create function public.list_sim_cards(p_tenant_id uuid)
returns setof app.sim_cards
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_sim_cards(p_tenant_id);
$wrap$;

comment on function public.list_sim_cards(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_sim_cards with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_sim_cards(uuid) from public;
grant execute on function app.list_sim_cards(uuid) to authenticated, service_role;

revoke execute on function public.list_sim_cards(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_sim_cards(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. app.list_device_vehicle_assignment_history -- replaces server/queries/
--    fleet-driver-device.ts:73 (listDeviceVehicleAssignmentHistory)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("device_vehicle_assignments").select("*")
-- .eq("device_id", deviceId).order("created_at", { ascending: false })`.
--
-- NOT a tenant_id-column-filtered read (filtered by device_id instead) -- see
-- this migration's own KEY FINDING and RULE B sections above for the full
-- derivation of why this table's own RLS authority is STILL a plain,
-- independent tenant_id-column check, not a join through device_id to
-- app.gps_devices.
create function app.list_device_vehicle_assignment_history(p_device_id uuid)
returns setof app.device_vehicle_assignments
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.device_vehicle_assignments
  where device_id = p_device_id
  order by created_at desc;
$$;

comment on function app.list_device_vehicle_assignment_history(uuid) is
  'ATW-223/CG-S10-ATW-004/O1 remediation: the full, never-overwritten device-to-vehicle assignment history for one device, newest first, replacing server/queries/fleet-driver-device.ts:73''s broken .from("device_vehicle_assignments").select("*").eq("device_id", deviceId).order("created_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter: this function has ZERO real callers anywhere in this repository today -- not in any page/action/component, and not in server/queries/fleet-driver-device.test.ts either (see this migration''s own SECURITY POSTURE and ADDITIONAL DEFECT FOUND sections) -- so there is no service-role caller to trigger the decoupled-actor SECURITY DEFINER path, and this function is designed with the same posture as its 6 siblings in this file for consistency. FILTERED BY device_id, NOT tenant_id -- but app.device_vehicle_assignments still carries its OWN, independent `tenant_id uuid not null references app.tenants (id)` column (20260729310000:208), and its SELECT policy is a PLAIN check on that column, NOT a join/EXISTS through device_id to app.gps_devices or through vehicle_operational_profile_id to app.vehicle_operational_profiles -- re-derived directly from this table''s own `create table`/`create policy`/`alter policy` statements, not assumed (see this migration''s own KEY FINDING section). Relies entirely on the calling role''s own RLS evaluation of device_vehicle_assignments_select_scoped -- CURRENT text (post 20260730560000:118-119 ALTER POLICY, RULE B confirms no later rewrite): `(app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()` -- reproduced by the live RLS engine, never re-implemented here. The real calling role already holds a direct `grant select on app.device_vehicle_assignments to authenticated, service_role` (20260729310000:1076). No RULE A guard: no actor parameter exists to protect. `returns setof app.device_vehicle_assignments` (11 columns, 1:1 with parseDeviceVehicleAssignment -- independently column-diffed, no masking). A genuine unbounded list read by design (Prompt 223 §24''s own "historical assignments are preserved" requirement, 20260729310000:220-221) -- the table''s only unique constraint touching device_id is a PARTIAL index (device_vehicle_assignments_current_device_unique, on device_id WHERE is_current), which bounds only the CURRENT row to one per device and does not apply to this unfiltered, full-history read; confirmed directly against the TS function''s own current Promise<DeviceVehicleAssignment[]> signature and body (no .maybeSingle()/.single()/.limit(1) -- the docstring itself says "full history, never overwritten"). setof used anyway per this series'' own uniform convention. `order by created_at desc` reproduces the original call''s own explicit ordering exactly. Returns zero rows -- never an exception -- for a nonexistent device_id, a device with no assignment history yet, or an actor whose session cannot pass the predicate above, matching the original RLS-filtered .from() read''s own current empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_device_vehicle_assignment_history with an identical grant set and
-- an identical security mode (invoker, matching its app.* counterpart), never a
-- reimplementation.
create function public.list_device_vehicle_assignment_history(p_device_id uuid)
returns setof app.device_vehicle_assignments
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_device_vehicle_assignment_history(p_device_id);
$wrap$;

comment on function public.list_device_vehicle_assignment_history(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_device_vehicle_assignment_history with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_device_vehicle_assignment_history(uuid) from public;
grant execute on function app.list_device_vehicle_assignment_history(uuid) to authenticated, service_role;

revoke execute on function public.list_device_vehicle_assignment_history(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_device_vehicle_assignment_history(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. app.list_provider_vehicle_mappings -- replaces server/queries/
--    fleet-driver-device.ts:82 (listProviderVehicleMappings)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("provider_vehicle_mappings").select("*")
-- .eq("vehicle_master_id", vehicleMasterId).order("created_at", { ascending: false })`.
--
-- NOT a tenant_id-column-filtered read (filtered by vehicle_master_id instead)
-- -- see this migration's own KEY FINDING and RULE B sections above for the
-- full derivation of why this table's own RLS authority is STILL a plain,
-- independent tenant_id-column check, not a join through vehicle_master_id to
-- app.master_records.
create function app.list_provider_vehicle_mappings(p_vehicle_master_id uuid)
returns setof app.provider_vehicle_mappings
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.provider_vehicle_mappings
  where vehicle_master_id = p_vehicle_master_id
  order by created_at desc;
$$;

comment on function app.list_provider_vehicle_mappings(uuid) is
  'ATW-223/CG-S10-ATW-004/O1 remediation: every third-party provider''s external-ID mapping for one vehicle master record, newest first, replacing server/queries/fleet-driver-device.ts:82''s broken .from("provider_vehicle_mappings").select("*").eq("vehicle_master_id", vehicleMasterId).order("created_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- the one real call site (app/(tenant)/[tenantSlug]/operations/fleet/page.tsx:92, called once per vehicle profile via Promise.all) uses createSupabaseServerClient() only, never the service-role client. FILTERED BY vehicle_master_id, NOT tenant_id -- but app.provider_vehicle_mappings still carries its OWN, independent `tenant_id uuid not null references app.tenants (id)` column (20260729310000:229), and its SELECT policy is a PLAIN check on that column, NOT a join/EXISTS through vehicle_master_id to app.master_records -- re-derived directly from this table''s own `create table`/`create policy`/`alter policy` statements, not assumed (see this migration''s own KEY FINDING section). Relies entirely on the calling role''s own RLS evaluation of provider_vehicle_mappings_select_scoped -- CURRENT text (post 20260730560000:292-293 ALTER POLICY, RULE B confirms no later rewrite): `(app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()` -- reproduced by the live RLS engine, never re-implemented here. The real calling role already holds a direct `grant select on app.provider_vehicle_mappings to authenticated, service_role` (20260729310000:1078). No RULE A guard: no actor parameter exists to protect. `returns setof app.provider_vehicle_mappings` (10 columns, 1:1 with parseProviderVehicleMapping -- independently column-diffed, no masking). A genuine multi-row list read by design -- this table''s own unique constraints are (tenant_id, vehicle_master_id, provider_code) and (tenant_id, provider_code, external_vehicle_id), NEITHER of which bounds vehicle_master_id alone to 0-or-1 rows (one vehicle may be mapped under several distinct providers); confirmed directly against the TS function''s own current Promise<ProviderVehicleMapping[]> signature and body (no .maybeSingle()/.single()/.limit(1)). setof used anyway per this series'' own uniform convention. `order by created_at desc` reproduces the original call''s own explicit ordering exactly. Returns zero rows -- never an exception -- for a nonexistent vehicle_master_id, a vehicle with no provider mappings yet, or an actor whose session cannot pass the predicate above, matching the original RLS-filtered .from() read''s own current empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_provider_vehicle_mappings with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart), never a
-- reimplementation.
create function public.list_provider_vehicle_mappings(p_vehicle_master_id uuid)
returns setof app.provider_vehicle_mappings
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_provider_vehicle_mappings(p_vehicle_master_id);
$wrap$;

comment on function public.list_provider_vehicle_mappings(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_provider_vehicle_mappings with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_provider_vehicle_mappings(uuid) from public;
grant execute on function app.list_provider_vehicle_mappings(uuid) to authenticated, service_role;

revoke execute on function public.list_provider_vehicle_mappings(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_provider_vehicle_mappings(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. app.list_vehicle_tracking_source_priorities -- replaces server/queries/
--    fleet-driver-device.ts:91 (listVehicleTrackingSourcePriorities)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("vehicle_tracking_source_priorities").select("*")
-- .eq("vehicle_master_id", vehicleMasterId).order("priority_rank", { ascending: true })`.
--
-- NOT a tenant_id-column-filtered read (filtered by vehicle_master_id instead)
-- -- see this migration's own KEY FINDING and RULE B sections above for the
-- full derivation of why this table's own RLS authority is STILL a plain,
-- independent tenant_id-column check, not a join through vehicle_master_id to
-- app.master_records.
create function app.list_vehicle_tracking_source_priorities(p_vehicle_master_id uuid)
returns setof app.vehicle_tracking_source_priorities
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.vehicle_tracking_source_priorities
  where vehicle_master_id = p_vehicle_master_id
  order by priority_rank asc;
$$;

comment on function app.list_vehicle_tracking_source_priorities(uuid) is
  'ATW-223/CG-S10-ATW-004/O1 remediation: every declared primary/fallback tracking-source-priority row for one vehicle master record, ranked ascending, replacing server/queries/fleet-driver-device.ts:91''s broken .from("vehicle_tracking_source_priorities").select("*").eq("vehicle_master_id", vehicleMasterId).order("priority_rank", { ascending: true }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- the one real call site (app/(tenant)/[tenantSlug]/operations/fleet/page.tsx:93, called once per vehicle profile via Promise.all) uses createSupabaseServerClient() only, never the service-role client. FILTERED BY vehicle_master_id, NOT tenant_id -- but app.vehicle_tracking_source_priorities still carries its OWN, independent `tenant_id uuid not null references app.tenants (id)` column (20260729310000:266), and its SELECT policy is a PLAIN check on that column, NOT a join/EXISTS through vehicle_master_id to app.master_records -- re-derived directly from this table''s own `create table`/`create policy`/`alter policy` statements, not assumed (see this migration''s own KEY FINDING section). Relies entirely on the calling role''s own RLS evaluation of vehicle_tracking_source_priorities_select_scoped -- CURRENT text (post 20260730560000:352-353 ALTER POLICY, RULE B confirms no later rewrite): `(app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()` -- reproduced by the live RLS engine, never re-implemented here. The real calling role already holds a direct `grant select on app.vehicle_tracking_source_priorities to authenticated, service_role` (20260729310000:1080). No RULE A guard: no actor parameter exists to protect. `returns setof app.vehicle_tracking_source_priorities` (10 columns, 1:1 with parseVehicleTrackingSourcePriority -- independently column-diffed, no masking). A genuine multi-row list read by design -- this table''s own unique constraint is (vehicle_master_id, source_type), NOT vehicle_master_id alone, so up to 3 rows (one per source_type: driver_mobile/direct_device/third_party_platform) are legitimately returned per vehicle; confirmed directly against the TS function''s own current Promise<VehicleTrackingSourcePriority[]> signature and body (no .maybeSingle()/.single()/.limit(1)). setof used anyway per this series'' own uniform convention. `order by priority_rank asc` reproduces the original call''s own explicit ordering exactly -- the one function in this batch NOT ordered by created_at. Returns zero rows -- never an exception -- for a nonexistent vehicle_master_id, a vehicle with no declared source-priority policy yet, or an actor whose session cannot pass the predicate above, matching the original RLS-filtered .from() read''s own current empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_vehicle_tracking_source_priorities with an identical grant set
-- and an identical security mode (invoker, matching its app.* counterpart),
-- never a reimplementation.
create function public.list_vehicle_tracking_source_priorities(p_vehicle_master_id uuid)
returns setof app.vehicle_tracking_source_priorities
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_vehicle_tracking_source_priorities(p_vehicle_master_id);
$wrap$;

comment on function public.list_vehicle_tracking_source_priorities(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_vehicle_tracking_source_priorities with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_vehicle_tracking_source_priorities(uuid) from public;
grant execute on function app.list_vehicle_tracking_source_priorities(uuid) to authenticated, service_role;

revoke execute on function public.list_vehicle_tracking_source_priorities(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_vehicle_tracking_source_priorities(uuid) to authenticated, service_role;
