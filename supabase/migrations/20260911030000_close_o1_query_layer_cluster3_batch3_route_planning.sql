-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 3
-- (operations-tms-core) batch 3: route/load planning scenarios, constraints,
-- candidate plans, score components, selections, and replan events. Continues
-- the same Design->Verify->Fix adversarial pipeline established by clusters
-- 0-2 and cluster 3 batches 1-2: supabase/config.toml's `schemas = ["public",
-- "graphql_public"]` never exposes the "app" Postgres schema to PostgREST, so
-- every `.from()` read against an `app.*` table in server/queries/*.ts has
-- NEVER worked in production.
--
-- Closes 8 broken .from() call sites, all in server/queries/route-load-planning.ts
-- (ATW-224, CG-S10-ATW-005), all against tables created by
-- 20260729320000_create_advanced_tms_route_load_planning.sql:
--
--   route-load-planning.ts:40-46   listRoutePlanningScenarios
--   route-load-planning.ts:48-57   getRoutePlanningScenario
--   route-load-planning.ts:69-75   listRoutePlanningConstraints
--   route-load-planning.ts:78-84   listRoutePlanningCandidatePlans
--   route-load-planning.ts:88      listRoutePlanningScoreComponents
--   route-load-planning.ts:97      getCurrentRoutePlanningSelection
--   route-load-planning.ts:109     listRoutePlanningSelections
--   route-load-planning.ts:118     listRoutePlanningReplanEvents
--
-- This file's other 2 functions, listRoutePlanningStops
-- (app.get_route_planning_stops) and getCanonicalPositionForPlanning
-- (app.get_canonical_position_for_planning), are already RPC-backed and
-- untouched here -- both served as this batch's own live authority-pattern
-- precedent (see PART 1 below). RouteLoadPlanningQueryTableClient therefore
-- keeps BOTH "from" and "rpc" in its Pick<SupabaseClient, ...> type: this
-- migration closes all 8 remaining broken call sites in the file, but the
-- client type itself is left general per both source drafts' own TS
-- INTEGRATION notes (no other function in this file remains .from()-backed
-- after this migration, but narrowing the type is left to the TS-conversion
-- step, not this SQL migration).
--
-- 8 new app.*/public.* Option-2 wrapper function pairs (16 functions total),
-- assembled from two independently designed and independently verified
-- drafts:
--
--   PART 1 (app.route_planning_scenarios / app.route_planning_constraints /
--   app.route_planning_candidate_plans):
--     app.list_route_planning_scenarios
--     app.get_route_planning_scenario
--     app.list_route_planning_constraints
--     app.list_route_planning_candidate_plans
--
--   PART 2 (app.route_planning_score_components / app.route_planning_selected_plans /
--   app.route_planning_replan_events):
--     app.list_route_planning_score_components
--     app.get_current_route_planning_selection
--     app.list_route_planning_selections
--     app.list_route_planning_replan_events
--
-- ===========================================================================
-- SECURITY POSTURE (both parts) -- SECURITY INVOKER, ZERO actor parameter
-- ===========================================================================
-- Both parts independently re-derived the identical conclusion for their own
-- table families, rather than one copying the other's or cluster 3 batch 2's
-- analogous conclusion for a different table family:
--
--   * This exact table family's own two already-existing, already-live
--     sibling read functions in the SAME 20260729320000 migration --
--     app.get_route_planning_stops (lines 1447-1476) and
--     app.get_canonical_position_for_planning (lines 384-418) -- are BOTH
--     `security invoker` with ZERO actor parameter (RULE C: repo-wide
--     case-insensitive grep of `create or replace function
--     app\.(get_route_planning_stops|get_canonical_position_for_planning)`
--     across every migration, sorted by filename, finds no redefinition of
--     either anywhere -- each cited body IS the current body). Both are
--     plain filtered reads over an RLS-scoped base table, exactly the shape
--     of all 8 functions this migration adds.
--   * All 6 target tables already carry a direct `grant select ... to
--     authenticated, service_role` (20260729320000:1568/1572/1574/1576/
--     1578/1580) with no later grant/revoke narrowing any of them anywhere
--     in supabase/migrations (repo-wide grep) -- a SECURITY INVOKER function
--     therefore grants the calling role no capability it did not already
--     have via a bare `select`.
--   * `service_role` genuinely has BYPASSRLS in this project
--     (20260716075355_create_tenants.sql:230,
--     20260716113048_create_audit_trail.sql:446-447) -- safe here because (a)
--     none of these 8 functions takes an actor parameter, so there is no
--     "claimed actor" identity for BYPASSRLS to silently defeat, and (b)
--     `service_role` already holds a direct grant select on all 6 tables
--     independent of these functions' existence, so exposing that same
--     access through a public.* wrapper adds no new attack surface.
--   * The decisive test, independently applied by each part: does any REAL
--     caller of these functions resemble cluster 3 batch 1's dispatch
--     functions (a service-role-authenticated backend route claiming an
--     actor DECOUPLED from its own session identity)? Every real call site
--     for this file's functions uses `createSupabaseServerClient()`
--     (session-scoped, RLS-subject) -- no code path anywhere in this
--     repository calls any of these functions via
--     createSupabaseServiceRoleClient() to claim a decoupled actor. This is
--     the actual reason INVOKER is safe here, not merely an appeal to a
--     sibling function sharing the same security mode.
--   * Precedent-wrapper composability was independently re-checked for both
--     parts (not merely cited): app.get_route_planning_stops' and
--     app.get_canonical_position_for_planning's own public.* wrappers
--     (20260826000000_create_public_api_data_wrappers.sql:16645, 13282) are
--     ALSO security invoker end-to-end (no `security definer` in either
--     CREATE statement, despite each one's own comment mislabeling it a
--     "security-definer pass-through" -- a pre-existing, unrelated cosmetic
--     bug in that migration, out of scope here) -- unlike
--     app.get_shipment_leg_stops, which cluster 3 batch 2's own verify pass
--     found UNSAFE to imitate because its own public.* wrapper genuinely IS
--     security definer. No such composability defect exists in either part's
--     precedent.
--
-- RULE A does not apply to any of the 8 functions below: none takes an actor
-- parameter, so there is no separate identity claim for
-- app.assert_actor_is_session_identity to cross-check.
--
-- ===========================================================================
-- RULE B -- RLS predicate currency (all 6 tables, both parts)
-- ===========================================================================
-- Repo-wide case-insensitive grep of each policy name below (sorted by
-- filename) finds ONLY the original declaration statement in
-- 20260729320000_create_advanced_tms_route_load_planning.sql for all 6 --
-- zero later alteration of any of them anywhere in supabase/migrations. The
-- predicates quoted below ARE the current predicates; each function body
-- below relies on these being evaluated automatically by Postgres under
-- SECURITY INVOKER, never re-implemented in SQL here.
--
--   PART 1:
--   * route_planning_scenarios_select_scoped (lines 1487-1495): ONE hop --
--     exists-join directly to app.shipment_orders (shipment_order_id lives
--     on this table directly), gated by app.can_access_record((select
--     auth.uid()), so.tenant_id, so.owner_user_id,
--     app.lead_record_scope_org_unit_ids(so.org_unit_id), null).
--   * route_planning_constraints_select_scoped (lines 1508-1517): TWO hops --
--     exists-join through app.route_planning_scenarios to
--     app.shipment_orders (this table carries scenario_id, not
--     shipment_order_id directly), same can_access_record(...) gate.
--   * route_planning_candidate_plans_select_scoped (lines 1519-1528):
--     identical two-hop shape to the constraints policy, substituting
--     route_planning_candidate_plans.scenario_id for the exists()
--     correlation.
--
--   PART 2:
--   * route_planning_score_components_select_scoped (lines 1530-1540): THREE
--     hops -- exists-join through app.route_planning_candidate_plans ->
--     app.route_planning_scenarios -> app.shipment_orders, same
--     can_access_record(...) gate. One hop deeper than the other 5 tables in
--     this migration, confirmed directly from the policy body.
--   * route_planning_selected_plans_select_scoped (lines 1542-1551): TWO
--     hops -- exists-join through app.route_planning_scenarios to
--     app.shipment_orders (this table carries scenario_id directly), same
--     gate.
--   * route_planning_replan_events_select_scoped (lines 1553-1562):
--     identical two-hop shape, joining through app.route_planning_scenarios
--     on route_planning_replan_events.scenario_id (the freshly created
--     replan target, NOT previous_scenario_id -- see function 8's own
--     comment below for the column-semantics derivation), same gate.
--
-- ===========================================================================
-- CONTRACT FIDELITY -- physical column shape, all 6 tables
-- ===========================================================================
-- Every table's own `create table app.<name>` (20260729320000) was read
-- directly and cross-checked against server/contracts/route-load-planning/
-- route-load-planning.ts's own Zod schemas -- exact 1:1 match on every
-- column for all 6 tables, no drift, and no later `alter table ... add
-- column` exists on any of them anywhere in supabase/migrations (repo-wide
-- grep; the only later route_planning-prefixed migrations are mutation
-- FUNCTION BODY rewrites for tenant-id-disclosure hardening --
-- 20260903110000, 20260903120000, 20260907100000 -- none of which touches a
-- column or RLS policy on any of these 6 tables). Because every function
-- below `returns setof` the table's own composite row type rather than a
-- hand-typed `returns table (...)` column list, there is structurally zero
-- risk of a manual column-list/order mismatch.
--
--   app.route_planning_scenarios (15 columns): id, tenant_id,
--     shipment_order_id, idempotency_key, status, requested_weight_kg,
--     requested_volume_cbm, job_id, canonical_position_snapshot,
--     canonical_position_captured_at, owner_user_id, record_version,
--     created_by, created_at, updated_at.
--   app.route_planning_constraints (8 columns): id, tenant_id, scenario_id,
--     constraint_type, constraint_key, constraint_value, created_by,
--     created_at. (parseRoutePlanningConstraint deliberately never reads
--     created_by -- an existing, unrelated parser omission, not something
--     this function's own return shape should also drop.)
--   app.route_planning_candidate_plans (13 columns): id, tenant_id,
--     scenario_id, plan_rank, algorithm_version, feasible,
--     infeasibility_reasons, vehicle_master_id, driver_master_id,
--     total_distance_km, estimated_duration_minutes,
--     capacity_utilization_pct, generated_at.
--   app.route_planning_score_components (6 columns): id, tenant_id,
--     candidate_plan_id, component_key, component_value, created_at.
--     route_planning_score_components_tenant_candidate_key_unique bounds a
--     given candidate_plan_id to at most 3 rows.
--   app.route_planning_selected_plans (10 columns): id, tenant_id,
--     scenario_id, candidate_plan_id, is_current, superseded_by_id,
--     is_override, override_reason, selected_by, selected_at. Partial unique
--     index route_planning_selected_plans_current_scenario_unique ON
--     (scenario_id) WHERE is_current bounds a scenario to at most one
--     is_current=true row at the database level.
--   app.route_planning_replan_events (8 columns): id, tenant_id,
--     scenario_id, previous_scenario_id, trigger_reason,
--     canonical_position_snapshot, triggered_by, triggered_at. No unique
--     constraint bounds row count per scenario_id -- genuinely multi-row
--     shaped; `returns setof` used, matching the original TS function's own
--     array-returning signature exactly.
--
-- Column-semantics confirmation for app.route_planning_replan_events (RULE
-- C): the table links an OLD scenario to a NEW one via TWO different uuid
-- columns -- `scenario_id` (the freshly created replan target) and
-- `previous_scenario_id` (the OLD scenario being replaced). Repo-wide
-- case-insensitive grep of `create or replace function
-- app.replan_route_planning_scenario` finds a later redefinition,
-- 20260903110000_harden_tenant_id_disclosure_tms_tracking.sql:964-1053,
-- which sorts after the original 20260729320000:1348-1440 and is the
-- function's true current body. Independently re-read in full: that later
-- body's own insert (lines 1042-1043) is semantically unchanged on this
-- point -- v_new.id (the NEW scenario) is bound to `scenario_id`, and
-- p_scenario_id (the OLD/prior scenario) is bound to `previous_scenario_id`.
-- The original `.eq("scenario_id", scenarioId)` call
-- (route-load-planning.ts:118) filters on `scenario_id`, matching its own TS
-- comment's framing ("rows where THIS scenario is the freshly created
-- one") -- reproduced verbatim below.
--
-- ===========================================================================
-- SETOF-vs-BARE-COMPOSITE -- the defect class this migration deliberately
-- avoids, in both 0-or-1-row lookups
-- ===========================================================================
-- app.get_route_planning_scenario and app.get_current_route_planning_selection
-- are both 0-or-1-row lookups (bounded respectively by
-- app.route_planning_scenarios' own primary key and by
-- route_planning_selected_plans_current_scenario_unique's partial unique
-- index). Both are declared `returns setof app.<table>`, NOT a bare
-- (non-setof) `returns app.<table>` composite. This is a deliberate,
-- empirically-justified choice, not the original shape either underlying
-- draft started from:
--
-- Live-verified against a disposable Postgres 16 database (not merely
-- reasoned about): a non-setof, composite-returning SQL function invoked via
-- `select * from function(...)` -- exactly how each function's own public.*
-- wrapper body invokes it, and how PostgREST/pg RPC's own call machinery
-- invokes EVERY function it exposes, setof or not -- returns ONE row with
-- every column NULL on a miss, not zero rows (`select count(*) from
-- wrapper_over_a_bare_composite_function(<nonexistent id>)` = 1, confirmed
-- empirically; row_to_json/to_jsonb serialize it as `{"id": null, ...}`,
-- never a bare JSON `null`). Against this codebase's own TS unwrap idiom
-- (`const row = Array.isArray(data) ? data[0] : data; return row ? parse(row)
-- : null;`), that all-NULL object is truthy, so the parser would be invoked
-- on it -- throwing an uncaught ZodError instead of the promised graceful
-- `null`-on-miss/RLS-denial return. This is strictly worse than the
-- original (never-reachable) `.maybeSingle()` call's own null-on-miss
-- contract.
--
-- Both underlying drafts caught this independently by cross-referencing
-- cluster 3 batch 2's own corrective migration,
-- 20260911020000_fix_o1_cluster3_batch2_composite_return_null_bug.sql, which
-- fixed the identical defect class in app.get_shipment_leg_tracking_policy /
-- app.get_current_shipment_leg_tracking_session AFTER that batch's own
-- migration had already been committed and pushed. Because this discovery
-- happened before batch 3's own migration was ever written (this file, first
-- committed here), no corrective follow-up migration is needed for batch 3 --
-- both defects were fixed directly in the source drafts before assembly:
--   * app.get_route_planning_scenario: found and fixed by that draft's own
--     adversarial verify pass (see the PRIMARY KEY BOUND-equivalent
--     reasoning inlined in that function's own comment below).
--   * app.get_current_route_planning_selection: the PART 2 draft's own
--     verify pass initially MISSED this despite the sibling draft's verify
--     catching the analogous case in the same batch -- found and fixed
--     directly during final cross-draft review before this migration was
--     assembled (see that function's own comment below, marked "POST-DRAFT
--     CORRECTION").
-- `app.get_route_planning_stops`/`app.get_canonical_position_for_planning`
-- (this migration's own cited precedent) never had this defect: both use
-- `returns table (...)`, Postgres syntax for an IMPLICITLY SETOF function --
-- a genuinely different, safe return shape from a bare composite type name.
--
-- ===========================================================================
-- SEARCH_PATH -- app, pg_temp (not app, public, pg_temp)
-- ===========================================================================
-- All 8 new app.* functions use `set search_path = app, pg_temp`, matching
-- app.get_canonical_position_for_planning's own choice, NOT
-- app.get_route_planning_stops' own `app, public, pg_temp` (which includes
-- `public` only because its body calls app.geography_to_geojson_point, a
-- GeoJSON projection over a `geography` column -- none of these 8 new
-- functions touches geography/PostGIS at all).
--
-- ===========================================================================
-- RAISE-vs-silent-zero-rows (all 8 functions)
-- ===========================================================================
-- All 8 functions are record-scoped reads. None RAISEs for a denied or
-- nonexistent record -- a nonexistent id/scenario_id/candidate_plan_id, or an
-- actor whose session cannot pass the underlying table's own RLS predicate,
-- yields silent zero rows for all 8, matching the original `.from()` reads'
-- own current (never-actually-reachable) behavior exactly. This is a direct
-- consequence of the SECURITY INVOKER design, not a separate choice.
--
-- list_route_planning_replan_events' lack of a DB-level 0-or-1 bound is
-- correct "list" behavior, not a defect, and NOT analogous to cluster 3
-- batch 1's job-order-handoff ambiguous_context finding: the original call
-- (route-load-planning.ts:118) has no `.maybeSingle()`/`.limit()` and its TS
-- return type is `Promise<RoutePlanningReplanEvent[]>` (not `| null`) -- it
-- never claimed single-row semantics, so there is no masked ambiguity for a
-- multi-row match to expose (every row already belongs to the one
-- scenario_id requested, itself tenant-scoped via
-- route_planning_replan_events_select_scoped). No RAISE/ambiguity guard is
-- needed here.
--
-- Ordering fidelity: listRoutePlanningScenarios (created_at desc) and
-- listRoutePlanningCandidatePlans (plan_rank asc) reproduce their original
-- calls' own explicit .order() clauses; listRoutePlanningConstraints,
-- listRoutePlanningScoreComponents, and listRoutePlanningReplanEvents
-- reproduce their original calls' own lack of any .order() clause (no ORDER
-- BY added) -- verified directly against server/queries/route-load-planning.ts,
-- not assumed; listRoutePlanningSelections reproduces its own explicit
-- `.order("selected_at", { ascending: false })`.
--
-- ===========================================================================
-- GRANT PARITY (ISS-2026-309)
-- ===========================================================================
-- Every app.* function below: `revoke execute on function app.X(...) from
-- public;` then `grant execute on function app.X(...) to authenticated,
-- service_role;` -- matching all 6 tables' own direct grants exactly (no
-- `anon` anywhere in this table family's own grants). Every public.* wrapper
-- below: `revoke execute on function public.X(...) from anon, authenticated,
-- service_role, public;` then `grant execute on function public.X(...) to
-- authenticated, service_role;` -- the full 4-role revoke is required per
-- ISS-2026-309 (a bare `revoke ... from public` does not undo this project's
-- own ALTER DEFAULT PRIVILEGES bootstrap grant of EXECUTE to
-- anon/authenticated on every new public schema function).
--
-- Assembled from two independently designed and independently verified
-- scratchpad drafts (scenarios_constraints_candidates.sql,
-- scores_selections_replan.sql) -- confirmed to share no function-name
-- collisions and to target 6 distinct base tables between them before
-- assembly.
-- ===========================================================================

-- ===========================================================================
-- PART 1: app.route_planning_scenarios / app.route_planning_constraints /
--         app.route_planning_candidate_plans
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. app.list_route_planning_scenarios -- replaces server/queries/
--    route-load-planning.ts:40-46 (listRoutePlanningScenarios)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("route_planning_scenarios").select("*")
-- .eq("shipment_order_id", shipmentOrderId).order("created_at", { ascending: false })`.
create function app.list_route_planning_scenarios(p_shipment_order_id uuid)
returns setof app.route_planning_scenarios
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.route_planning_scenarios
  where shipment_order_id = p_shipment_order_id
  order by created_at desc;
$$;

comment on function app.list_route_planning_scenarios(uuid) is
  'ATW-224/CG-S10-ATW-005/O1 remediation: every planning scenario for one Shipment Order, newest first, replacing server/queries/route-load-planning.ts:40-46''s broken .from("route_planning_scenarios").select("*").eq("shipment_order_id", shipmentOrderId).order("created_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- mirrors this exact table family''s own already-live sibling reads app.get_route_planning_stops/app.get_canonical_position_for_planning (20260729320000, both security invoker with no actor parameter; see this migration''s own header for the full derivation and the BYPASSRLS safety argument). Relies entirely on the calling role''s own RLS evaluation of route_planning_scenarios_select_scoped (same file, line 1487-1495: an exists-join through app.shipment_orders scoped via app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null), one hop since shipment_order_id lives directly on this table) -- reproduced by the live RLS engine, not re-implemented in this function''s own SQL body; confirmed via repo-wide grep that no rewrite of this policy exists anywhere in the migration set (RULE B). The real calling role already holds a direct `grant select on app.route_planning_scenarios to authenticated, service_role` (same file, line 1568). No RULE A guard: no actor parameter exists to protect -- invoker mode means the policy''s own (select auth.uid()) already resolves to the real caller. `returns setof app.route_planning_scenarios` (the table''s own composite row type, not a hand-typed column list) so the returned shape can never drift from the table''s own current definition; independently cross-checked against server/contracts/route-load-planning/route-load-planning.ts''s own RoutePlanningScenarioSchema (15 fields, 1:1). Returns zero rows, never an exception, for a nonexistent shipment_order_id or an actor who cannot reach that shipment order''s tenant/owner/org-unit scope -- matching the original RLS-filtered read''s own silent-empty-result posture, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_route_planning_scenarios with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart -- never a
-- reimplementation, and never a privilege upgrade the app.* function itself
-- does not have).
create function public.list_route_planning_scenarios(p_shipment_order_id uuid)
returns setof app.route_planning_scenarios
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_route_planning_scenarios(p_shipment_order_id);
$wrap$;

comment on function public.list_route_planning_scenarios(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_route_planning_scenarios with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_route_planning_scenarios(uuid) from public;
grant execute on function app.list_route_planning_scenarios(uuid) to authenticated, service_role;

-- Option-2 wrapper grant, per ISS-2026-309 (a bare `revoke ... from public` does
-- not undo this project's own default-privileges bootstrap grant of EXECUTE to
-- anon/authenticated on every new public schema function).
revoke execute on function public.list_route_planning_scenarios(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_route_planning_scenarios(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. app.get_route_planning_scenario -- replaces server/queries/
--    route-load-planning.ts:48-57 (getRoutePlanningScenario)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("route_planning_scenarios").select("*")
-- .eq("id", scenarioId).maybeSingle()`.
create function app.get_route_planning_scenario(p_scenario_id uuid)
returns setof app.route_planning_scenarios
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.route_planning_scenarios where id = p_scenario_id;
$$;

comment on function app.get_route_planning_scenario(uuid) is
  'ATW-224/CG-S10-ATW-005/O1 remediation: one planning scenario by its own primary key, replacing server/queries/route-load-planning.ts:48-57''s broken .from("route_planning_scenarios").select("*").eq("id", scenarioId).maybeSingle() (app is not exposed to PostgREST). Security invoker, zero actor parameter -- same table and identical authority shape as app.list_route_planning_scenarios above (this is that same read narrowed to one row by primary key, not a different authority pattern). Relies entirely on the calling role''s own RLS evaluation of route_planning_scenarios_select_scoped (20260729320000:1487-1495, reproduced by the live RLS engine, not re-implemented here; RULE B: confirmed no rewrite exists). app.route_planning_scenarios'' own `id uuid primary key` (20260729320000:182) bounds this read to 0-or-1 rows at the database level, independent of RLS. `returns setof app.route_planning_scenarios`, deliberately NOT a bare (non-setof) `returns app.route_planning_scenarios` composite: live-verified against a disposable Postgres 16 database that a non-setof composite-returning function invoked via `select * from function(...)` -- exactly how the public.* wrapper below, and PostgREST/pg RPC''s own call machinery, invoke it -- returns ONE row of all-NULL columns on a miss, not zero rows, defeating the intended null-on-miss contract (this migration''s own header has the full empirical derivation). SETOF avoids this: a genuinely empty result on a miss or RLS denial, one row on a hit, matching the replaced `.maybeSingle()` call''s own current null-on-miss/single-row semantics exactly. No RULE A guard: no actor parameter exists to protect. Returns zero rows -- never a row of nulls, never an exception -- for a nonexistent scenario_id or an actor who cannot reach that scenario''s shipment order''s tenant/owner/org-unit scope; the TS caller''s `Array.isArray(data) ? data[0] : data` unwrap already treats that as null.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.get_route_planning_scenario with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart). `returns
-- setof`, matching app.get_route_planning_scenario's own return shape exactly.
create function public.get_route_planning_scenario(p_scenario_id uuid)
returns setof app.route_planning_scenarios
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_route_planning_scenario(p_scenario_id);
$wrap$;

comment on function public.get_route_planning_scenario(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_route_planning_scenario with an identical grant set and an identical security mode (invoker), never a reimplementation. Returns setof, not a bare composite -- see app.get_route_planning_scenario''s own comment / this migration''s SETOF-vs-BARE-COMPOSITE section for why.';

revoke execute on function app.get_route_planning_scenario(uuid) from public;
grant execute on function app.get_route_planning_scenario(uuid) to authenticated, service_role;

revoke execute on function public.get_route_planning_scenario(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_route_planning_scenario(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. app.list_route_planning_constraints -- replaces server/queries/
--    route-load-planning.ts:69-75 (listRoutePlanningConstraints)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("route_planning_constraints").select("*")
-- .eq("scenario_id", scenarioId)`.
create function app.list_route_planning_constraints(p_scenario_id uuid)
returns setof app.route_planning_constraints
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.route_planning_constraints where scenario_id = p_scenario_id;
$$;

comment on function app.list_route_planning_constraints(uuid) is
  'ATW-224/CG-S10-ATW-005/O1 remediation: every constraint for one scenario, replacing server/queries/route-load-planning.ts:69-75''s broken .from("route_planning_constraints").select("*").eq("scenario_id", scenarioId) (app is not exposed to PostgREST) -- no ordering applied, matching the original call exactly (it carries no .order()). Security invoker, zero actor parameter -- mirrors this exact table family''s own already-live sibling reads (see this migration''s own header). Relies entirely on the calling role''s own RLS evaluation of route_planning_constraints_select_scoped (same file, line 1508-1517: a TWO-hop exists-join through app.route_planning_scenarios to app.shipment_orders, since this table is scoped by scenario_id, not shipment_order_id, scoped via app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)) -- reproduced by the live RLS engine, not re-implemented in this function''s own SQL body; confirmed via repo-wide grep that no rewrite of this policy exists anywhere in the migration set (RULE B). The real calling role already holds a direct `grant select on app.route_planning_constraints to authenticated, service_role` (same file, line 1572). No RULE A guard: no actor parameter exists to protect. `returns setof app.route_planning_constraints` (the table''s own composite row type): 8 physical columns including created_by, which server/contracts/route-load-planning/route-load-planning.ts''s own parseRoutePlanningConstraint deliberately never reads (an existing, unrelated parser omission, not something this function''s own return shape should also drop -- see this migration''s own CONTRACT FIDELITY section). Returns zero rows, never an exception, for a nonexistent scenario_id or an actor who cannot reach that scenario''s shipment order''s tenant/owner/org-unit scope -- matching the original RLS-filtered read''s own silent-empty-result posture, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_route_planning_constraints with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart).
create function public.list_route_planning_constraints(p_scenario_id uuid)
returns setof app.route_planning_constraints
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_route_planning_constraints(p_scenario_id);
$wrap$;

comment on function public.list_route_planning_constraints(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_route_planning_constraints with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_route_planning_constraints(uuid) from public;
grant execute on function app.list_route_planning_constraints(uuid) to authenticated, service_role;

revoke execute on function public.list_route_planning_constraints(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_route_planning_constraints(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. app.list_route_planning_candidate_plans -- replaces server/queries/
--    route-load-planning.ts:78-84 (listRoutePlanningCandidatePlans)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("route_planning_candidate_plans").select("*")
-- .eq("scenario_id", scenarioId).order("plan_rank", { ascending: true })`.
create function app.list_route_planning_candidate_plans(p_scenario_id uuid)
returns setof app.route_planning_candidate_plans
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.route_planning_candidate_plans
  where scenario_id = p_scenario_id
  order by plan_rank asc;
$$;

comment on function app.list_route_planning_candidate_plans(uuid) is
  'ATW-224/CG-S10-ATW-005/O1 remediation: every candidate plan for one scenario, ranked best-first, replacing server/queries/route-load-planning.ts:78-84''s broken .from("route_planning_candidate_plans").select("*").eq("scenario_id", scenarioId).order("plan_rank", { ascending: true }) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- mirrors this exact table family''s own already-live sibling reads (see this migration''s own header). Relies entirely on the calling role''s own RLS evaluation of route_planning_candidate_plans_select_scoped (same file, line 1519-1528: an identical TWO-hop exists-join through app.route_planning_scenarios to app.shipment_orders as route_planning_constraints_select_scoped, substituting route_planning_candidate_plans.scenario_id for the exists() correlation, scoped via app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)) -- reproduced by the live RLS engine, not re-implemented in this function''s own SQL body; confirmed via repo-wide grep that no rewrite of this policy exists anywhere in the migration set (RULE B). The real calling role already holds a direct `grant select on app.route_planning_candidate_plans to authenticated, service_role` (same file, line 1574). No RULE A guard: no actor parameter exists to protect. `returns setof app.route_planning_candidate_plans` (the table''s own composite row type, 13 columns, matching RoutePlanningCandidatePlanSchema''s 13 fields 1:1 -- see this migration''s own CONTRACT FIDELITY section). route_planning_candidate_plans_tenant_scenario_rank_unique (20260729320000:291, unique on (tenant_id, scenario_id, plan_rank)) means plan_rank is itself unique within one scenario, so `order by plan_rank asc` alone (no id tie-break needed) yields a fully deterministic ordering. Returns zero rows, never an exception, for a nonexistent scenario_id, a scenario with no candidates generated yet, or an actor who cannot reach that scenario''s shipment order''s tenant/owner/org-unit scope -- matching the original RLS-filtered read''s own silent-empty-result posture, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_route_planning_candidate_plans with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart).
create function public.list_route_planning_candidate_plans(p_scenario_id uuid)
returns setof app.route_planning_candidate_plans
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_route_planning_candidate_plans(p_scenario_id);
$wrap$;

comment on function public.list_route_planning_candidate_plans(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_route_planning_candidate_plans with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_route_planning_candidate_plans(uuid) from public;
grant execute on function app.list_route_planning_candidate_plans(uuid) to authenticated, service_role;

revoke execute on function public.list_route_planning_candidate_plans(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_route_planning_candidate_plans(uuid) to authenticated, service_role;

-- ===========================================================================
-- PART 2: app.route_planning_score_components / app.route_planning_selected_plans
--         / app.route_planning_replan_events
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 5. app.list_route_planning_score_components -- replaces server/queries/
--    route-load-planning.ts:88 (listRoutePlanningScoreComponents)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("route_planning_score_components").select("*")
-- .eq("candidate_plan_id", candidatePlanId)`.
create function app.list_route_planning_score_components(p_candidate_plan_id uuid)
returns setof app.route_planning_score_components
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.route_planning_score_components where candidate_plan_id = p_candidate_plan_id;
$$;

comment on function app.list_route_planning_score_components(uuid) is
  'ATW-224/O1 remediation: the explainability score breakdown for one candidate plan, replacing server/queries/route-load-planning.ts:88''s broken .from("route_planning_score_components").select("*").eq("candidate_plan_id", candidatePlanId) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- mirrors this exact table family''s own 2 pre-existing sibling read functions in the same migration, app.get_route_planning_stops and app.get_canonical_position_for_planning (20260729320000_create_advanced_tms_route_load_planning.sql:1447-1476, 384-418), both security invoker with no actor parameter; see this migration''s own header for the full 4-point justification (grants already direct, RLS already live, service_role BYPASSRLS grants no new capability, no decoupled-actor use case exists for this read). Relies entirely on the calling role''s own RLS evaluation of route_planning_score_components_select_scoped (same file, lines 1530-1540: an EXISTS join through app.route_planning_candidate_plans -> app.route_planning_scenarios -> app.shipment_orders, scoped via app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)) -- reproduced by citation, not re-implemented in this function''s own body, and confirmed via repo-wide grep of the policy name that no later alteration of it exists anywhere in supabase/migrations. The real calling role already holds a direct grant select on app.route_planning_score_components to authenticated, service_role (same file, line 1576). No RULE A guard: no actor parameter exists to protect -- invoker mode means the policy''s own (select auth.uid()) already resolves to the real caller. route_planning_score_components_tenant_candidate_key_unique (same file, line 307) bounds this read to at most 3 rows (one per component_key: total_distance_km, estimated_duration_minutes, capacity_utilization_pct), never unbounded. Returns zero rows (never an exception) for a nonexistent candidate_plan_id or an actor who cannot reach that candidate''s scenario''s shipment order''s tenant/owner/org-unit scope -- matching the original RLS-filtered .from() call''s own current (never-actually-reachable) empty-array-on-miss behavior, unchanged. No ORDER BY added: the original call itself carries no .order() clause (route-load-planning.ts:88) -- this function reproduces that exact (already nondeterministic) row order rather than introducing a new default ordering contract.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_route_planning_score_components with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart -- never a
-- reimplementation, and never a privilege upgrade the app.* function itself does
-- not have).
create function public.list_route_planning_score_components(p_candidate_plan_id uuid)
returns setof app.route_planning_score_components
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_route_planning_score_components(p_candidate_plan_id);
$wrap$;

comment on function public.list_route_planning_score_components(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_route_planning_score_components with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_route_planning_score_components(uuid) from public;
grant execute on function app.list_route_planning_score_components(uuid) to authenticated, service_role;

-- Option-2 wrapper grant, corrected per ISS-2026-309 (a bare `revoke ... from
-- public` does not undo this project's own ALTER DEFAULT PRIVILEGES ... GRANT
-- EXECUTE ON FUNCTIONS TO anon, authenticated bootstrap grant on the public
-- schema).
revoke execute on function public.list_route_planning_score_components(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_route_planning_score_components(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. app.get_current_route_planning_selection -- replaces server/queries/
--    route-load-planning.ts:97 (getCurrentRoutePlanningSelection)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("route_planning_selected_plans").select("*")
-- .eq("scenario_id", scenarioId).eq("is_current", true).maybeSingle()`.
create function app.get_current_route_planning_selection(p_scenario_id uuid)
returns setof app.route_planning_selected_plans
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.route_planning_selected_plans where scenario_id = p_scenario_id and is_current = true;
$$;

comment on function app.get_current_route_planning_selection(uuid) is
  'ATW-224/O1 remediation: the current (is_current) human selection decision for one scenario, if any, replacing server/queries/route-load-planning.ts:97''s broken .from("route_planning_selected_plans").select("*").eq("scenario_id", scenarioId).eq("is_current", true).maybeSingle() (app is not exposed to PostgREST). Security invoker, zero actor parameter -- same justification as app.list_route_planning_score_components above (see this migration''s own header), mirroring this exact table family''s own pre-existing app.get_route_planning_stops/app.get_canonical_position_for_planning precedent and cluster 3 batch 2''s own identical shape for app.get_current_shipment_leg_tracking_session. Relies entirely on the calling role''s own RLS evaluation of route_planning_selected_plans_select_scoped (20260729320000_create_advanced_tms_route_load_planning.sql:1542-1551: an EXISTS join through app.route_planning_scenarios -> app.shipment_orders, scoped via app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)) -- reproduced by citation, not re-implemented, confirmed via repo-wide grep of the policy name that no later alteration of it exists anywhere in supabase/migrations. The real calling role already holds a direct grant select on app.route_planning_selected_plans to authenticated, service_role (same file, line 1578). No RULE A guard: no actor parameter exists to protect. The partial unique index route_planning_selected_plans_current_scenario_unique ON (scenario_id) WHERE is_current (same file, line 333) bounds this read to 0-or-1 rows at the database level -- confirming the TS function''s own header framing ("never overwritten in place -- is_current/superseded_by_id") is backed by a real constraint, independently verified rather than assumed. Declared `returns setof app.route_planning_selected_plans`, NOT a bare (non-setof) composite return: live-verified against a disposable Postgres 16 database that a non-setof SQL function whose body query matches zero rows returns ONE row with every column NULL, not zero rows, which the TS layer''s `row ? parse(row) : null` unwrap would treat as truthy and throw an uncaught ZodError instead of returning null for the ordinary "no current selection yet" case (this migration''s own SETOF-vs-BARE-COMPOSITE section has the full empirical derivation and cites cluster 3 batch 2''s own corrective migration 20260911020000 as the precedent that first surfaced this defect class). `returns setof` correctly yields zero rows on a miss; the TS layer''s existing `Array.isArray(data) ? data[0] : data` unwrap already handles this correctly, no TS change needed. Returns zero rows (never an exception) for a scenario with no current selection yet, a nonexistent scenario_id, or an actor who cannot reach that scenario''s shipment order''s tenant/owner/org-unit scope -- matching the original RLS-filtered .maybeSingle() call''s own current null-on-miss behavior via the TS layer''s existing empty-array check, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.get_current_route_planning_selection with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart). `returns
-- setof`, matching app.get_current_route_planning_selection's own return shape
-- exactly -- see that function's own comment for why a bare non-setof composite
-- return is unsafe here.
create function public.get_current_route_planning_selection(p_scenario_id uuid)
returns setof app.route_planning_selected_plans
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_current_route_planning_selection(p_scenario_id);
$wrap$;

comment on function public.get_current_route_planning_selection(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_current_route_planning_selection with an identical grant set and an identical security mode (invoker), never a reimplementation. Returns setof, not a bare composite -- see app.get_current_route_planning_selection''s own comment for why.';

revoke execute on function app.get_current_route_planning_selection(uuid) from public;
grant execute on function app.get_current_route_planning_selection(uuid) to authenticated, service_role;

revoke execute on function public.get_current_route_planning_selection(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_current_route_planning_selection(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. app.list_route_planning_selections -- replaces server/queries/
--    route-load-planning.ts:109 (listRoutePlanningSelections)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("route_planning_selected_plans").select("*")
-- .eq("scenario_id", scenarioId).order("selected_at", { ascending: false })`.
create function app.list_route_planning_selections(p_scenario_id uuid)
returns setof app.route_planning_selected_plans
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.route_planning_selected_plans where scenario_id = p_scenario_id order by selected_at desc;
$$;

comment on function app.list_route_planning_selections(uuid) is
  'ATW-224/O1 remediation: the full selection history for one scenario, newest first, replacing server/queries/route-load-planning.ts:109''s broken .from("route_planning_selected_plans").select("*").eq("scenario_id", scenarioId).order("selected_at", { ascending: false }) (app is not exposed to PostgREST). Security invoker, zero actor parameter, same table and same authority shape as app.get_current_route_planning_selection above (this is that same table''s history-shaped sibling read, not a different authority pattern) -- see this migration''s own header for the full justification. Relies entirely on the calling role''s own RLS evaluation of route_planning_selected_plans_select_scoped (20260729320000_create_advanced_tms_route_load_planning.sql:1542-1551, reproduced by citation under app.get_current_route_planning_selection''s own comment above) -- confirmed via repo-wide grep of the policy name that no later alteration of it exists anywhere in supabase/migrations. The real calling role already holds a direct grant select on app.route_planning_selected_plans to authenticated, service_role (same file, line 1578). No RULE A guard: no actor parameter exists to protect. `order by selected_at desc` reproduces the original call''s own explicit `.order("selected_at", { ascending: false })` exactly (newest-first -- every selection ever made for this scenario is returned, current and superseded alike). Returns zero rows (never an exception) for a scenario with no selection made yet, a nonexistent scenario_id, or an actor who cannot reach that scenario''s shipment order''s tenant/owner/org-unit scope -- matching the original RLS-filtered .from() call''s own current empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_route_planning_selections with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart).
create function public.list_route_planning_selections(p_scenario_id uuid)
returns setof app.route_planning_selected_plans
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_route_planning_selections(p_scenario_id);
$wrap$;

comment on function public.list_route_planning_selections(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_route_planning_selections with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_route_planning_selections(uuid) from public;
grant execute on function app.list_route_planning_selections(uuid) to authenticated, service_role;

revoke execute on function public.list_route_planning_selections(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_route_planning_selections(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8. app.list_route_planning_replan_events -- replaces server/queries/
--    route-load-planning.ts:118 (listRoutePlanningReplanEvents)
-- ---------------------------------------------------------------------------
-- Replaces: `.from("route_planning_replan_events").select("*")
-- .eq("scenario_id", scenarioId)`.
create function app.list_route_planning_replan_events(p_scenario_id uuid)
returns setof app.route_planning_replan_events
language sql
stable
security invoker
set search_path = app, pg_temp
as $$
  select * from app.route_planning_replan_events where scenario_id = p_scenario_id;
$$;

comment on function app.list_route_planning_replan_events(uuid) is
  'ATW-224/O1 remediation: the replan lineage row(s) where p_scenario_id is the freshly created (replan target) scenario, replacing server/queries/route-load-planning.ts:118''s broken .from("route_planning_replan_events").select("*").eq("scenario_id", scenarioId) (app is not exposed to PostgREST). Security invoker, zero actor parameter -- same justification as the other functions in this migration (see this migration''s own header). Relies entirely on the calling role''s own RLS evaluation of route_planning_replan_events_select_scoped (20260729320000_create_advanced_tms_route_load_planning.sql:1553-1562: an EXISTS join through app.route_planning_scenarios ON sc.id = route_planning_replan_events.scenario_id -> app.shipment_orders, scoped via app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)) -- reproduced by citation, not re-implemented, confirmed via repo-wide grep of the policy name that no later alteration of it exists anywhere in supabase/migrations. The real calling role already holds a direct grant select on app.route_planning_replan_events to authenticated, service_role (same file, line 1580). No RULE A guard: no actor parameter exists to protect. Column-semantics note (independently confirmed against app.replan_route_planning_scenario''s own TRUE CURRENT body -- RULE C: repo-wide grep of "create or replace function app.replan_route_planning_scenario" finds a later redefinition at 20260903110000_harden_tenant_id_disclosure_tms_tracking.sql:964-1053, which sorts after the original 20260729320000:1348-1440 and supersedes it; that later body''s own insert, lines 1042-1043, is semantically unchanged from the original on this point): this table links an OLD scenario to a NEW one via two DIFFERENT uuid columns -- `scenario_id` is the freshly created replan target (bound to v_new.id at insert time) and `previous_scenario_id` is the scenario being replaced (bound to p_scenario_id at insert time). This function filters on `scenario_id`, matching the original call''s own `.eq("scenario_id", scenarioId)` (route-load-planning.ts:118) and its own header comment''s framing ("rows where THIS scenario is the freshly created one") exactly -- NOT `previous_scenario_id`, which would instead answer "what did this scenario get replanned INTO". No unique constraint bounds this read to 0-or-1 rows (unlike the other tables in this migration) -- only app.replan_route_planning_scenario''s own current single-writer call pattern makes more than one row per scenario_id unlikely in practice today; `returns setof` is used regardless, matching the original TS function''s own Promise<RoutePlanningReplanEvent[]> array-returning signature exactly rather than assuming a bound the schema does not actually enforce. No ORDER BY added: the original call carries no .order() clause (route-load-planning.ts:118) -- reproduced as-is. Returns zero rows (never an exception) for a scenario that was never created via replan, a nonexistent scenario_id, or an actor who cannot reach that scenario''s shipment order''s tenant/owner/org-unit scope -- matching the original RLS-filtered .from() call''s own current empty-array-on-miss behavior, unchanged.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through
-- to app.list_route_planning_replan_events with an identical grant set and an
-- identical security mode (invoker, matching its app.* counterpart).
create function public.list_route_planning_replan_events(p_scenario_id uuid)
returns setof app.route_planning_replan_events
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_route_planning_replan_events(p_scenario_id);
$wrap$;

comment on function public.list_route_planning_replan_events(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_route_planning_replan_events with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_route_planning_replan_events(uuid) from public;
grant execute on function app.list_route_planning_replan_events(uuid) to authenticated, service_role;

revoke execute on function public.list_route_planning_replan_events(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_route_planning_replan_events(uuid) to authenticated, service_role;
