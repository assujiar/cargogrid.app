-- Security/hardening: relocate `postgis` out of the `public` schema, closing the
-- remaining half of ISS-2026-234 (`pg_trgm`/`btree_gist` were already relocated at
-- `20260815200000_harden_relocate_pg_trgm_btree_gist_out_of_public.sql`, using the
-- simple `ALTER EXTENSION ... SET SCHEMA` path -- that path is NOT available here).
--
-- WHY THIS COULD NOT BE A SIMPLE `ALTER EXTENSION` (re-verified live before writing
-- this migration): `select extname, extrelocatable from pg_extension where extname =
-- 'postgis'` returns `extrelocatable = false` on the live project (`postgis` 3.3.7).
-- This is PostGIS's own packaging decision (its control file), not a permissions
-- problem -- `ALTER EXTENSION postgis SET SCHEMA extensions` fails outright. The only
-- real way to move an already-installed PostGIS is `DROP EXTENSION postgis CASCADE`
-- followed by `CREATE EXTENSION postgis SCHEMA extensions`, which drops every object
-- that depends on a postgis-owned type (`geography`/`geometry`/...) -- every
-- `geography`-typed column, every index on one, every CHECK constraint that mentions
-- one, and every function whose OWN SIGNATURE (not merely its body) takes or returns
-- `geography`.
--
-- SAFETY, RE-VERIFIED LIVE IMMEDIATELY BEFORE WRITING THIS MIGRATION (2026-09-01):
-- `ISS-2026-234`'s own entry named this destructive precisely because it would
-- CASCADE-drop 15 live `geography(Point,4326)` columns it assumed held real
-- production data. Re-queried every one of them directly against the live project,
-- both `select count(*)` (whole table) and `select count(*) where <col> is not null`
-- (the column specifically): all 15 are genuinely empty -- 0 rows, not merely 0
-- non-null geography values. This is a pre-launch system with no real tenant data
-- yet, so the CASCADE drop below loses nothing. This migration must never be copied
-- as a template for a relocation performed after real tenant data exists -- it would
-- need a real backfill strategy, which this one deliberately does not build because
-- it does not need to.
--
-- CORRECTED COUNT: ISS-2026-234's own text said "15 columns across 12 tables" (and,
-- separately, a stale "3 extension_in_public warnings" already corrected 2026-08-28).
-- Re-derived directly from `information_schema.columns` (`udt_name = 'geography'`)
-- rather than trusting either prior figure: it is **15 columns across 15 tables**,
-- exactly one `geography(Point,4326)` column per table, every one in schema `app`:
-- `attendance_events.location`, `attendance_policy_versions.geofence_center`,
-- `canonical_telemetry_events.location`, `direct_device_telemetry_reports.location`,
-- `driver_mobile_position_reports.location`, `epod_captures.delivery_geog`,
-- `route_planning_stops.location_geog`, `shipment_exception_signals.location`,
-- `shipment_leg_stop_geofence_states.last_evaluated_location`,
-- `shipment_leg_stops.location_geog`, `shipment_milestone_candidates.location`,
-- `third_party_telemetry_reports.location`, `vehicle_current_positions.location`
-- (the one NOT NULL column of the 15 -- every other is nullable),
-- `vehicle_source_health.last_location`, `warehouses.site_geog`.
--
-- EXACT CASCADE FOOTPRINT (derived from live `pg_depend`, not guessed): besides the
-- 15 columns above, `DROP EXTENSION postgis CASCADE` also drops:
--   * 4 GiST indexes on those columns: `epod_captures_geog_idx`,
--     `route_planning_stops_geog_idx`, `shipment_leg_stops_geog_idx`,
--     `attendance_policy_versions_geofence_gix` (a partial index, `WHERE
--     geofence_center IS NOT NULL`).
--   * 20 CHECK constraints that reference one of the 15 columns (whether via
--     `app.validate_geography_point(...)` or a bare `IS [NOT] NULL` on the column
--     itself -- a constraint depends on every column it mentions, not only the ones
--     it calls a postgis function on).
--   * 11 `app.*` functions whose own SIGNATURE (a parameter or return type) is
--     `geography`, each with an identical `public.*` PostgREST wrapper that is
--     ALSO dropped (the wrapper's signature is `geography` too): `bounded_st_dwithin`,
--     `geography_to_geojson_point`, `geojson_point_to_geography`,
--     `validate_geography_point`, `arbitrate_and_project_vehicle_position`,
--     `evaluate_geofence_and_deviation_signals`, `evaluate_route_deviation`,
--     `evaluate_stop_geofence`, `upsert_exception_signal`,
--     `upsert_milestone_candidate` (10 pairs), plus `app._ingest_attendance_event`
--     (an `OUT`-parameter function with no `public.*` wrapper -- 11th, unpaired).
--     All 21 dropped function objects are rebuilt below from the LIVE
--     `pg_get_functiondef` body captured immediately before drafting this migration
--     (never from an on-disk migration file, which can be stale -- `ISS-2026-308`
--     paid for that mistake once already) -- byte-identical body/signature, with
--     `search_path` gaining `extensions` wherever the body calls a bare `ST_*()`.
--     Every other existing attribute (`language`, `security definer`/`invoker`,
--     every other `set` clause) is restated explicitly, never left to a
--     `CREATE OR REPLACE` default -- `ISS-2026-308`'s own second defect (rebuilding
--     `app.enqueue_job` from a stale copy silently reverted its `SECURITY DEFINER` +
--     pinned `search_path`, caught only by `public-api-wrapper-regression.sql`'s own
--     definer/invoker parity check) is the exact failure shape this restates against.
--     Because `DROP EXTENSION ... CASCADE` genuinely DROPS these objects (not merely
--     replaces them), their grants are gone too -- each is re-granted below to
--     exactly its own live ACL, captured before the drop. Two of the 11 (`app.
--     evaluate_geofence_and_deviation_signals`'s siblings `evaluate_route_deviation`/
--     `evaluate_stop_geofence`) and `arbitrate_and_project_vehicle_position` also
--     call a bare `ST_*()` in their own body and so need `extensions` in
--     `search_path` regardless of the signature-driven rebuild.
--   * `public.geometry_columns` (a postgis system view) and postgis's own internal
--     composite types (`geometry_dump`, `valid_detail`) -- these are the
--     extension's own objects, recreated automatically by `CREATE EXTENSION postgis`
--     itself; nothing below rebuilds them by hand.
--
-- `ISS-2026-309` (grants dropped-and-recreated in `public` land back on `anon`/
-- `authenticated` by default), and a second, distinct grant-defaulting trap this
-- migration's own local `db:test` run caught live while drafting it (not merely
-- reasoned about): Supabase's own `ALTER DEFAULT PRIVILEGES` rule for schema
-- `public` grants `EXECUTE` to `anon`+`authenticated`+`service_role` automatically
-- on every new function created there (confirmed live via `pg_default_acl` before
-- drafting this migration -- schema `app` carries no such CUSTOM rule). But
-- Postgres's own INNATE default -- independent of any `ALTER DEFAULT PRIVILEGES`
-- customization, and not schema-specific -- separately grants `EXECUTE` to the
-- `PUBLIC` pseudo-role on every genuinely NEW function object, in every schema.
-- `CREATE OR REPLACE FUNCTION` on a function that still exists preserves its
-- existing ACL untouched (this is what the pg_trgm/btree_gist migration's own
-- `CREATE OR REPLACE` calls relied on, safely -- none of its 3 functions were ever
-- dropped). But the 11 `app.*` functions this migration's own section 6 rebuilds
-- were genuinely DROPPED by CASCADE first -- their `CREATE OR REPLACE` is really a
-- fresh CREATE with a new OID, and PUBLIC was silently granted a role never
-- intended to hold one: `pg_proc.proacl` for the first draft of this migration's
-- own `app.geojson_point_to_geography` read `{=X/postgres,postgres=X/postgres,
-- authenticated=X/postgres,service_role=X/postgres}` -- that leading `=X/postgres`
-- (an empty role name before `=`) is PUBLIC, and `has_function_privilege('anon',
-- ...)` returns true through it even with no direct `anon` grant, exactly the
-- `ERR-2026-004` regression this file's own pre-existing schema-privilege-defense
-- test (below) already guards -- and that guard is what caught this, live, before
-- this migration was ever proposed for the live project. Every one of the 11
-- CASCADE-dropped `app.*` functions therefore gets an explicit `revoke ... from
-- public` immediately before its own re-grant, exactly mirroring the `public.*`
-- wrapper treatment below (which needed it for the OTHER reason -- Supabase's own
-- custom default-privileges rule -- but the fix shape is identical either way:
-- never trust a freshly (re)created function's ACL, always state it explicitly).
-- `app.set_epod_evidence` (section 8) needed neither treatment -- CASCADE never
-- dropped it (no `geography` in its own signature), so its `CREATE OR REPLACE`
-- preserves its existing, already-correct ACL untouched, same as the pg_trgm/
-- btree_gist precedent.
--
-- 13 further functions are NOT touched by CASCADE at all (their signature has no
-- `geography` parameter/return -- they only read a `geography` column inside a
-- query, or call a bare `ST_*()`/postgis function in their body) but their pinned
-- `search_path` (`app, public, pg_temp`) stops including postgis's objects once it
-- leaves `public`, so each is rebuilt with `extensions` added to that list, body
-- otherwise byte-identical: `_compute_shipment_leg_eta`,
-- `generate_route_planning_candidates`, `get_direct_device_telemetry_reports`,
-- `get_driver_mobile_position_reports`, `get_shipment_exception_signals`,
-- `get_shipment_leg_geofence_state`, `get_shipment_milestone_candidates`,
-- `get_tenant_pending_exception_signals`, `get_tenant_pending_milestone_candidates`,
-- `get_tenant_vehicle_tracking_overview`, `get_third_party_telemetry_reports`,
-- `get_vehicle_current_position`, `get_vehicle_telemetry_history`. (One live function
-- that also calls a bare `ST_*()`, `app.lookup_public_shipment_tracking`, already
-- carries `extensions` on its own `search_path` from an earlier migration -- verified
-- live, left untouched.) This mirrors the exact technique the `pg_trgm`/`btree_gist`
-- migration already established for its own 3 affected functions (`search_path`
-- gains `extensions`, added before `pg_temp`, body/signature otherwise unchanged) --
-- same convention, applied to postgis's own larger call-site surface.
--
-- A 35th function, found only by a SEPARATE sweep (a literal `public\.(geography|
-- geometry|st_[a-z_]+|...)` grep across every live `app`-schema function body, not
-- the "calls a bare ST_*()" sweep above): `app.set_epod_evidence` declares `v_geog
-- public.geography;` -- an EXPLICIT schema qualification, not a bare name relying on
-- `search_path`. Adding `extensions` to `search_path` would not fix this: PL/pgSQL
-- resolves an explicitly qualified type name exactly where it points, and
-- `public.geography` stops existing the moment the extension moves. This one
-- genuinely needs a body-text change (`public.geography` -> `geography`, matching
-- every other function in this schema's own convention of an unqualified type name
-- resolved via `search_path`), not merely a `search_path` addition -- the other 34
-- functions in this migration needed no such change because none of them hardcode a
-- schema-qualified postgis name anywhere in their body.
--
-- Combined true count: 35 functions touched by this migration (21 rebuilt because
-- CASCADE dropped them outright, 13 because their pinned `search_path` needs
-- `extensions`, 1 because of the hardcoded `public.geography` above) -- correcting
-- ISS-2026-234's own "~18 functions" estimate, which only ever counted the "calls a
-- bare ST_*()" class (19 of these 35 functions fall in that class; the other 16 are
-- signature-driven-only or the one hardcoded-qualification case).
--
-- Additive only: no applied migration is edited. `extensions` schema already exists
-- (created by `20260815200000`). Column physical order changes (`ALTER TABLE ADD
-- COLUMN` always appends; there is no way to reinsert a column at its original
-- ordinal position without a full table rebuild, which would be a materially larger,
-- higher-risk change for a purely cosmetic property) -- every column is still
-- reachable by name, which is the only access pattern this schema's own functions
-- ever use (`select col_a, col_b, ...` or `select * into v_row from app.sometable`
-- where `v_row` is declared as that same table's row type, which always reflects the
-- table's CURRENT physical column order and so is never affected by a reordering);
-- grepped the whole `app`-schema function corpus for a positional `insert into
-- app.<one of these 15 tables> values (...)` with no explicit column list -- zero
-- hits, so no code path silently assumes column position for these 15 tables.

-- Plain (non-LOCAL) SET: this migration is applied as its own psql/API connection
-- (one file = one session, never shared with another migration file), and
-- `psql -f` does not wrap a script lacking explicit BEGIN/COMMIT in a single
-- transaction -- `SET LOCAL` would reset after the first autocommitted statement
-- and leave every later `geography`-typed column/function/grant in this same file
-- unable to resolve the bare type name. A session-level `SET` persists for the
-- rest of THIS file's connection (whichever path applies it) without ever
-- surviving into a later migration file or the live database's own default.
set search_path to app, public, extensions, pg_temp;

create schema if not exists extensions;

-- ============================================================================
-- 1. Relocate the extension itself.
-- ============================================================================

drop extension postgis cascade;

create extension postgis schema extensions;

-- ============================================================================
-- 2. Restore the 15 dropped geography columns, exactly as they were (type,
--    nullability -- `app.vehicle_current_positions.location` is the one NOT NULL
--    column of the 15, re-added `not null` directly since the table is empty).
-- ============================================================================

alter table app.attendance_events add column location geography(Point, 4326);
alter table app.attendance_policy_versions add column geofence_center geography(Point, 4326);
alter table app.canonical_telemetry_events add column location geography(Point, 4326);
alter table app.direct_device_telemetry_reports add column location geography(Point, 4326);
alter table app.driver_mobile_position_reports add column location geography(Point, 4326);
alter table app.epod_captures add column delivery_geog geography(Point, 4326);
alter table app.route_planning_stops add column location_geog geography(Point, 4326);
alter table app.shipment_exception_signals add column location geography(Point, 4326);
alter table app.shipment_leg_stop_geofence_states add column last_evaluated_location geography(Point, 4326);
alter table app.shipment_leg_stops add column location_geog geography(Point, 4326);
alter table app.shipment_milestone_candidates add column location geography(Point, 4326);
alter table app.third_party_telemetry_reports add column location geography(Point, 4326);
alter table app.vehicle_current_positions add column location geography(Point, 4326) not null;
alter table app.vehicle_source_health add column last_location geography(Point, 4326);
alter table app.warehouses add column site_geog geography(Point, 4326);

-- ============================================================================
-- 2b. Restore COLUMN-LEVEL grants on the 15 re-added columns. Caught live, the
--    hard way, by this migration's own `db:test` run: `GRANT`/`REVOKE` in this
--    schema is not only table-level (`grant select on app.t to role`) -- this
--    codebase also grants column-level privileges extensively (`grant select
--    (col_a, col_b, ...) on app.t to authenticated`, the exact pattern the
--    field/record-access model at `20260716110430_create_field_record_access.sql`
--    establishes and dozens of later migrations reuse). A column-level grant is
--    tied to the COLUMN, not the table -- exactly like a function's own grant is
--    tied to the function object (section 6's own header) -- so `DROP EXTENSION
--    postgis CASCADE` dropping a column silently dropped whatever column-level
--    grant existed on it too, and re-adding the column via `ALTER TABLE ADD
--    COLUMN` creates a column with NO column-level grant, table-level grants
--    being a completely separate, orthogonal privilege axis that this migration's
--    section 1-2 left untouched and therefore never noticed was insufficient.
--    `scripts/db-tests/hris-attendance.sql` (a pre-existing, unrelated file this
--    migration never touched) caught this: a plain `select p.* ... join app.
--    attendance_policy_versions p ...` run as role `authenticated` raised
--    `permission denied for table attendance_policy_versions` post-relocation,
--    identical grants otherwise (table-level, function-level) -- diffing
--    `information_schema.column_privileges` between a disposable database built
--    WITHOUT this migration and one built WITH it, column by column, was what
--    isolated it to exactly one missing column-level grant
--    (`geofence_center`, `authenticated`, `SELECT`) -- and the same diff, re-run
--    against all 15 columns, is the exhaustive list below: every column-level
--    grant any of the 15 columns held pre-migration (`service_role` always gets
--    `SELECT, INSERT, UPDATE`; `authenticated` gets `SELECT` only where it
--    already held it live -- `attendance_events.location`,
--    `shipment_exception_signals.location`,
--    `shipment_leg_stop_geofence_states.last_evaluated_location`, and
--    `shipment_milestone_candidates.location` never granted `authenticated`
--    anything, and still do not here).
-- ============================================================================

grant select (location), insert (location), update (location) on app.attendance_events to service_role;

grant select (geofence_center) on app.attendance_policy_versions to authenticated;
grant select (geofence_center) on app.attendance_policy_versions to service_role;

grant select (location) on app.canonical_telemetry_events to authenticated;
grant select (location), insert (location), update (location) on app.canonical_telemetry_events to service_role;

grant select (location) on app.direct_device_telemetry_reports to authenticated;
grant select (location), insert (location), update (location) on app.direct_device_telemetry_reports to service_role;

grant select (location) on app.driver_mobile_position_reports to authenticated;
grant select (location), insert (location), update (location) on app.driver_mobile_position_reports to service_role;

grant select (delivery_geog) on app.epod_captures to authenticated;
grant select (delivery_geog), insert (delivery_geog), update (delivery_geog) on app.epod_captures to service_role;

grant select (location_geog) on app.route_planning_stops to authenticated;
grant select (location_geog), insert (location_geog), update (location_geog) on app.route_planning_stops to service_role;

grant select (location), insert (location), update (location) on app.shipment_exception_signals to service_role;

grant select (last_evaluated_location), insert (last_evaluated_location), update (last_evaluated_location) on app.shipment_leg_stop_geofence_states to service_role;

grant select (location_geog) on app.shipment_leg_stops to authenticated;
grant select (location_geog), insert (location_geog), update (location_geog) on app.shipment_leg_stops to service_role;

grant select (location), insert (location), update (location) on app.shipment_milestone_candidates to service_role;

grant select (location) on app.third_party_telemetry_reports to authenticated;
grant select (location), insert (location), update (location) on app.third_party_telemetry_reports to service_role;

grant select (location) on app.vehicle_current_positions to authenticated;
grant select (location), insert (location), update (location) on app.vehicle_current_positions to service_role;

grant select (last_location) on app.vehicle_source_health to authenticated;
grant select (last_location), insert (last_location), update (last_location) on app.vehicle_source_health to service_role;

grant select (site_geog) on app.warehouses to authenticated;
grant select (site_geog), insert (site_geog), update (site_geog) on app.warehouses to service_role;

-- ============================================================================
-- 3. Recreate app.validate_geography_point (and its public.* wrapper) FIRST --
--    several of the CHECK constraints restored in section 4 call it, and
--    `ALTER TABLE ... ADD CONSTRAINT` resolves the function at constraint-creation
--    time, not lazily. Byte-identical to the live pre-drop body; only `search_path`
--    gains `extensions` (it calls bare ST_IsEmpty/GeometryType/ST_IsValid).
-- ============================================================================

create or replace function app.validate_geography_point(p_geog geography)
 returns boolean
 language sql
 immutable
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
  select
    p_geog is not null
    and not ST_IsEmpty(p_geog::geometry)
    and GeometryType(p_geog::geometry) = 'POINT'
    and ST_IsValid(p_geog::geometry);
$function$;

revoke execute on function app.validate_geography_point(geography) from public;
grant execute on function app.validate_geography_point(geography) to authenticated, service_role;

create or replace function public.validate_geography_point(p_geog geography)
 returns boolean
 language sql
 immutable
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select app.validate_geography_point(p_geog);
$function$;

revoke execute on function public.validate_geography_point(geography) from public, anon, authenticated;
grant execute on function public.validate_geography_point(geography) to authenticated, service_role;

-- ============================================================================
-- 4. Restore the 20 CHECK constraints that referenced one of the 15 columns
--    (byte-identical `pg_get_constraintdef` text captured live before the drop).
-- ============================================================================

alter table app.attendance_events
  add constraint attendance_events_location_shape_check check (((location is null) = (location_source = 'none'::text))),
  add constraint attendance_events_location_valid_check check (((location is null) or app.validate_geography_point(location)));

alter table app.attendance_policy_versions
  add constraint attendance_policy_versions_geofence_shape_check check (((location_enforcement_mode = 'none'::text) or ((geofence_center is not null) and (geofence_radius_meters is not null) and (geofence_radius_meters > (0)::numeric)))),
  add constraint attendance_policy_versions_geofence_valid_check check (((geofence_center is null) or app.validate_geography_point(geofence_center)));

alter table app.canonical_telemetry_events
  add constraint canonical_telemetry_events_location_valid_check check (((location is null) or app.validate_geography_point(location)));

alter table app.direct_device_telemetry_reports
  add constraint direct_device_telemetry_reports_location_check check (((report_type <> 'location'::text) or (location is not null))),
  add constraint direct_device_telemetry_reports_location_valid_check check (((location is null) or app.validate_geography_point(location)));

alter table app.driver_mobile_position_reports
  add constraint driver_mobile_position_reports_location_check check (((report_type <> 'location'::text) or (location is not null))),
  add constraint driver_mobile_position_reports_location_valid_check check (((location is null) or app.validate_geography_point(location)));

alter table app.epod_captures
  add constraint epod_captures_delivery_geog_check check (((delivery_geog is null) or app.validate_geography_point(delivery_geog)));

alter table app.route_planning_stops
  add constraint route_planning_stops_geog_check check (((location_geog is null) or app.validate_geography_point(location_geog)));

alter table app.shipment_exception_signals
  add constraint shipment_exception_signals_location_valid_check check (((location is null) or app.validate_geography_point(location)));

alter table app.shipment_leg_stop_geofence_states
  add constraint shipment_leg_stop_geofence_states_location_valid_check check (((last_evaluated_location is null) or app.validate_geography_point(last_evaluated_location)));

alter table app.shipment_leg_stops
  add constraint shipment_leg_stops_geog_check check (((location_geog is null) or app.validate_geography_point(location_geog)));

alter table app.shipment_milestone_candidates
  add constraint shipment_milestone_candidates_location_valid_check check (((location is null) or app.validate_geography_point(location)));

alter table app.third_party_telemetry_reports
  add constraint third_party_telemetry_reports_location_check check (((report_type <> 'location'::text) or (location is not null))),
  add constraint third_party_telemetry_reports_location_valid_check check (((location is null) or app.validate_geography_point(location)));

alter table app.vehicle_current_positions
  add constraint vehicle_current_positions_location_valid_check check (app.validate_geography_point(location));

alter table app.vehicle_source_health
  add constraint vehicle_source_health_last_location_valid_check check (((last_location is null) or app.validate_geography_point(last_location)));

alter table app.warehouses
  add constraint warehouses_site_geog_check check (((site_geog is null) or app.validate_geography_point(site_geog)));

-- ============================================================================
-- 5. Restore the 4 GiST indexes on geography columns (byte-identical `pg_indexes`
--    definitions captured live before the drop -- operator classes bind by OID at
--    index-creation time, so this is a plain, unremarkable index build).
-- ============================================================================

create index epod_captures_geog_idx on app.epod_captures using gist (delivery_geog);
create index route_planning_stops_geog_idx on app.route_planning_stops using gist (location_geog);
create index shipment_leg_stops_geog_idx on app.shipment_leg_stops using gist (location_geog);
create index attendance_policy_versions_geofence_gix on app.attendance_policy_versions using gist (geofence_center) where (geofence_center is not null);

-- ============================================================================
-- 6. Recreate the remaining 10 CASCADE-dropped `app.*` functions with
--    `geography` in their own signature, each immediately followed by its
--    `public.*` PostgREST wrapper. Bodies are byte-identical to the live
--    pre-drop `pg_get_functiondef` capture; `search_path` gains `extensions`
--    wherever the body itself calls a bare `ST_*()` (bounded_st_dwithin,
--    geography_to_geojson_point, geojson_point_to_geography,
--    arbitrate_and_project_vehicle_position, evaluate_route_deviation);
--    evaluate_geofence_and_deviation_signals/evaluate_stop_geofence/
--    upsert_exception_signal/upsert_milestone_candidate/
--    app._ingest_attendance_event call no bare postgis function themselves (they
--    only pass a `geography` value through to another already-fixed function or a
--    table column) and so need no `search_path` change beyond what they already
--    had -- restated verbatim including their existing `search_path`.
-- ============================================================================

-- app.bounded_st_dwithin -- calls bare ST_DWithin; previously had NO search_path
-- pin at all (relied on the caller's own in-effect search_path, or the database's
-- own default of `"$user", public, extensions` when called at top level -- both
-- already fragile). Pinned here for the first time, matching every sibling
-- function's own convention, rather than left relying on caller context.
create or replace function app.bounded_st_dwithin(p_a geography, p_b geography, p_radius_meters numeric)
 returns boolean
 language plpgsql
 stable
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
begin
  if p_radius_meters is null or p_radius_meters <= 0 then
    raise exception 'spatial_radius_out_of_range: radius_meters must be a positive number, got %', p_radius_meters
      using errcode = 'check_violation';
  end if;
  if p_radius_meters > app.postgis_max_query_radius_meters() then
    raise exception 'spatial_radius_out_of_range: radius_meters % exceeds the governed maximum of %', p_radius_meters, app.postgis_max_query_radius_meters()
      using errcode = 'check_violation';
  end if;

  return ST_DWithin(p_a, p_b, p_radius_meters);
end;
$function$;

comment on function app.bounded_st_dwithin is
  'PLT-134: the governed bounded-radius proximity primitive (ADR-0014, max 500,000m) -- the concrete "no unbounded global spatial scan" mechanism Prompt 134 §17/§23 require. Intended for a future domain query''s WHERE clause, e.g. `where app.bounded_st_dwithin(w.location, :origin, :radius_meters)`, which a GiST index on the domain table''s own geography column (see this migration''s own header and scripts/db-tests/postgis.sql for the proven indexing pattern) makes selective, not a sequential scan.';

revoke execute on function app.bounded_st_dwithin(geography, geography, numeric) from public;
grant execute on function app.bounded_st_dwithin(geography, geography, numeric) to authenticated, service_role;

create or replace function public.bounded_st_dwithin(p_a geography, p_b geography, p_radius_meters numeric)
 returns boolean
 language sql
 stable
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select app.bounded_st_dwithin(p_a, p_b, p_radius_meters);
$function$;

revoke execute on function public.bounded_st_dwithin(geography, geography, numeric) from public, anon, authenticated;
grant execute on function public.bounded_st_dwithin(geography, geography, numeric) to authenticated, service_role;

-- app.geography_to_geojson_point -- calls bare ST_AsGeoJSON.
create or replace function app.geography_to_geojson_point(p_geog geography)
 returns jsonb
 language sql
 immutable
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
  select case when p_geog is null then null else ST_AsGeoJSON(p_geog)::jsonb end;
$function$;

comment on function app.geography_to_geojson_point is
  'PLT-134: geography -> GeoJSON serialization (RFC 7946, [longitude, latitude] axis order, matching PostGIS''s own ST_MakePoint(x,y) convention -- no axis translation ever happens between this and app.geojson_point_to_geography).';

revoke execute on function app.geography_to_geojson_point(geography) from public;
grant execute on function app.geography_to_geojson_point(geography) to authenticated, service_role;

create or replace function public.geography_to_geojson_point(p_geog geography)
 returns jsonb
 language sql
 immutable
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select app.geography_to_geojson_point(p_geog);
$function$;

revoke execute on function public.geography_to_geojson_point(geography) from public, anon, authenticated;
grant execute on function public.geography_to_geojson_point(geography) to authenticated, service_role;

-- app.geojson_point_to_geography -- calls bare ST_SetSRID/ST_MakePoint.
create or replace function app.geojson_point_to_geography(p_geojson jsonb)
 returns geography
 language plpgsql
 immutable
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_coordinates jsonb;
  v_lon numeric;
  v_lat numeric;
begin
  if p_geojson is null then
    return null;
  end if;

  if p_geojson ->> 'type' is distinct from 'Point' then
    raise exception 'spatial_invalid_geojson_type: expected GeoJSON type "Point", got %', p_geojson ->> 'type'
      using errcode = 'check_violation';
  end if;

  v_coordinates := p_geojson -> 'coordinates';
  if v_coordinates is null or jsonb_typeof(v_coordinates) <> 'array' or jsonb_array_length(v_coordinates) <> 2 then
    raise exception 'spatial_invalid_coordinate_count: expected a 2-element [longitude, latitude] coordinates array'
      using errcode = 'check_violation';
  end if;

  v_lon := (v_coordinates -> 0)::text::numeric;
  v_lat := (v_coordinates -> 1)::text::numeric;

  if v_lon < -180 or v_lon > 180 or v_lat < -90 or v_lat > 90 then
    raise exception 'spatial_coordinate_out_of_range: longitude % / latitude % is outside [-180,180]/[-90,90] -- rejected, never silently coerced', v_lon, v_lat
      using errcode = 'check_violation';
  end if;

  return ST_SetSRID(ST_MakePoint(v_lon, v_lat), 4326)::geography;
end;
$function$;

comment on function app.geojson_point_to_geography is
  'PLT-134: GeoJSON Point -> geography(Point,4326), strict RFC 7946 [longitude, latitude] axis order, no silent coordinate clamping (out-of-range longitude/latitude is rejected, never wrapped).';

revoke execute on function app.geojson_point_to_geography(jsonb) from public;
grant execute on function app.geojson_point_to_geography(jsonb) to authenticated, service_role;

create or replace function public.geojson_point_to_geography(p_geojson jsonb)
 returns geography
 language sql
 immutable
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select app.geojson_point_to_geography(p_geojson);
$function$;

revoke execute on function public.geojson_point_to_geography(jsonb) from public, anon, authenticated;
grant execute on function public.geojson_point_to_geography(jsonb) to authenticated, service_role;

-- app.upsert_exception_signal -- no bare postgis call of its own (passes p_location
-- straight into an INSERT); search_path restated verbatim (unchanged).
create or replace function app.upsert_exception_signal(p_tenant_id uuid, p_shipment_order_id uuid, p_shipment_leg_id uuid, p_signal_type text, p_exception_type text, p_severity text, p_source_canonical_event_id uuid, p_location geography, p_description text, p_correlation_key text)
 returns void
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'pg_temp'
as $function$
begin
  insert into app.shipment_exception_signals (
    tenant_id, shipment_order_id, shipment_leg_id, signal_type, exception_type, severity,
    source_canonical_event_id, location, description, correlation_key
  ) values (
    p_tenant_id, p_shipment_order_id, p_shipment_leg_id, p_signal_type, p_exception_type, p_severity,
    p_source_canonical_event_id, p_location, p_description, p_correlation_key
  )
  on conflict (tenant_id, correlation_key) where status = 'pending' do update
  set description = excluded.description,
      source_canonical_event_id = excluded.source_canonical_event_id,
      location = excluded.location,
      detected_at = now();
end;
$function$;

revoke execute on function app.upsert_exception_signal(uuid, uuid, uuid, text, text, text, uuid, geography, text, text) from public;
grant execute on function app.upsert_exception_signal(uuid, uuid, uuid, text, text, text, uuid, geography, text, text) to service_role;

create or replace function public.upsert_exception_signal(p_tenant_id uuid, p_shipment_order_id uuid, p_shipment_leg_id uuid, p_signal_type text, p_exception_type text, p_severity text, p_source_canonical_event_id uuid, p_location geography, p_description text, p_correlation_key text)
 returns void
 language sql
 security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select app.upsert_exception_signal(p_tenant_id, p_shipment_order_id, p_shipment_leg_id, p_signal_type, p_exception_type, p_severity, p_source_canonical_event_id, p_location, p_description, p_correlation_key);
$function$;

revoke execute on function public.upsert_exception_signal(uuid, uuid, uuid, text, text, text, uuid, geography, text, text) from public, anon, authenticated;
grant execute on function public.upsert_exception_signal(uuid, uuid, uuid, text, text, text, uuid, geography, text, text) to service_role;

-- app.upsert_milestone_candidate -- same shape as upsert_exception_signal above.
create or replace function app.upsert_milestone_candidate(p_tenant_id uuid, p_shipment_order_id uuid, p_shipment_leg_id uuid, p_shipment_leg_stop_id uuid, p_milestone_code text, p_candidate_event_time timestamp with time zone, p_source_canonical_event_id uuid, p_location geography, p_dedup_key text)
 returns void
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'pg_temp'
as $function$
begin
  insert into app.shipment_milestone_candidates (
    tenant_id, shipment_order_id, shipment_leg_id, shipment_leg_stop_id, milestone_code,
    candidate_event_time, source_canonical_event_id, location, dedup_key
  ) values (
    p_tenant_id, p_shipment_order_id, p_shipment_leg_id, p_shipment_leg_stop_id, p_milestone_code,
    p_candidate_event_time, p_source_canonical_event_id, p_location, p_dedup_key
  )
  on conflict (tenant_id, dedup_key) where status = 'pending' do update
  set candidate_event_time = excluded.candidate_event_time,
      source_canonical_event_id = excluded.source_canonical_event_id,
      location = excluded.location,
      detected_at = now();
end;
$function$;

revoke execute on function app.upsert_milestone_candidate(uuid, uuid, uuid, uuid, text, timestamptz, uuid, geography, text) from public;
grant execute on function app.upsert_milestone_candidate(uuid, uuid, uuid, uuid, text, timestamptz, uuid, geography, text) to service_role;

create or replace function public.upsert_milestone_candidate(p_tenant_id uuid, p_shipment_order_id uuid, p_shipment_leg_id uuid, p_shipment_leg_stop_id uuid, p_milestone_code text, p_candidate_event_time timestamp with time zone, p_source_canonical_event_id uuid, p_location geography, p_dedup_key text)
 returns void
 language sql
 security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select app.upsert_milestone_candidate(p_tenant_id, p_shipment_order_id, p_shipment_leg_id, p_shipment_leg_stop_id, p_milestone_code, p_candidate_event_time, p_source_canonical_event_id, p_location, p_dedup_key);
$function$;

revoke execute on function public.upsert_milestone_candidate(uuid, uuid, uuid, uuid, text, timestamptz, uuid, geography, text) from public, anon, authenticated;
grant execute on function public.upsert_milestone_candidate(uuid, uuid, uuid, uuid, text, timestamptz, uuid, geography, text) to service_role;

-- app.evaluate_stop_geofence -- calls app.bounded_st_dwithin/app.upsert_milestone_candidate
-- (both already recreated above), no bare postgis call of its own.
create or replace function app.evaluate_stop_geofence(p_tenant_id uuid, p_shipment_leg_id uuid, p_canonical_event_id uuid, p_location geography, p_event_at timestamp with time zone, p_geofence_policy jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'pg_temp'
as $function$
declare
  v_stop app.shipment_leg_stops;
  v_state app.shipment_leg_stop_geofence_states;
  v_has_state boolean;
  v_radius_meters numeric;
  v_dwell_seconds numeric;
  v_inside boolean;
  v_shipment_order_id uuid;
  v_milestone_code text;
  v_dedup_key text;
begin
  select ls.* into v_stop
  from app.shipment_leg_stops ls
  left join app.shipment_leg_stop_geofence_states gs on gs.shipment_leg_stop_id = ls.id
  where ls.shipment_leg_id = p_shipment_leg_id and ls.location_geog is not null and (gs.id is null or gs.state <> 'exited')
  order by ls.stop_sequence
  limit 1;
  if not found then
    return;
  end if;

  select sl.shipment_order_id into v_shipment_order_id from app.shipment_legs sl where sl.id = p_shipment_leg_id;

  v_radius_meters := app.safe_jsonb_numeric(p_geofence_policy, 'radius_meters', 300);
  if v_radius_meters <= 0 or v_radius_meters > app.postgis_max_query_radius_meters() then
    v_radius_meters := 300;
  end if;
  v_dwell_seconds := app.safe_jsonb_numeric(p_geofence_policy, 'dwell_seconds_before_confirm', 120);
  if v_dwell_seconds < 0 then
    v_dwell_seconds := 120;
  end if;

  select * into v_state from app.shipment_leg_stop_geofence_states where shipment_leg_stop_id = v_stop.id;
  v_has_state := found;

  v_inside := app.bounded_st_dwithin(p_location, v_stop.location_geog, v_radius_meters);

  if v_inside then
    if not v_has_state then
      insert into app.shipment_leg_stop_geofence_states (
        tenant_id, shipment_leg_stop_id, shipment_leg_id, radius_meters, dwell_seconds_before_confirm,
        state, first_entered_at, last_evaluated_at, last_evaluated_location
      ) values (
        p_tenant_id, v_stop.id, p_shipment_leg_id, v_radius_meters, v_dwell_seconds,
        'entered_pending_dwell', p_event_at, p_event_at, p_location
      )
      returning * into v_state;
    elsif v_state.state = 'outside' then
      update app.shipment_leg_stop_geofence_states
      set state = 'entered_pending_dwell', first_entered_at = p_event_at, last_evaluated_at = p_event_at, last_evaluated_location = p_location, updated_at = now()
      where id = v_state.id
      returning * into v_state;
    else
      update app.shipment_leg_stop_geofence_states
      set last_evaluated_at = p_event_at, last_evaluated_location = p_location, updated_at = now()
      where id = v_state.id
      returning * into v_state;
    end if;

    if v_state.state = 'entered_pending_dwell' and v_state.confirmed_at is null
       and extract(epoch from (p_event_at - v_state.first_entered_at)) >= v_dwell_seconds then
      update app.shipment_leg_stop_geofence_states
      set state = 'confirmed_inside', confirmed_at = p_event_at, updated_at = now()
      where id = v_state.id;

      v_milestone_code := coalesce(p_geofence_policy #>> array['milestone_code_map', v_stop.stop_type || '_arrival'], v_stop.stop_type || '_arrival');
      v_dedup_key := 'geofence_arrival:' || v_stop.id;
      perform app.upsert_milestone_candidate(
        p_tenant_id, v_shipment_order_id, p_shipment_leg_id, v_stop.id, v_milestone_code,
        p_event_at, p_canonical_event_id, p_location, v_dedup_key
      );
    end if;
  else
    if v_has_state and v_state.state = 'entered_pending_dwell' then
      update app.shipment_leg_stop_geofence_states
      set state = 'outside', first_entered_at = null, last_evaluated_at = p_event_at, last_evaluated_location = p_location, updated_at = now()
      where id = v_state.id;
    elsif v_has_state and v_state.state = 'confirmed_inside' then
      update app.shipment_leg_stop_geofence_states
      set state = 'exited', last_evaluated_at = p_event_at, last_evaluated_location = p_location, updated_at = now()
      where id = v_state.id;

      v_milestone_code := coalesce(p_geofence_policy #>> array['milestone_code_map', v_stop.stop_type || '_departure'], v_stop.stop_type || '_departure');
      v_dedup_key := 'geofence_departure:' || v_stop.id;
      perform app.upsert_milestone_candidate(
        p_tenant_id, v_shipment_order_id, p_shipment_leg_id, v_stop.id, v_milestone_code,
        p_event_at, p_canonical_event_id, p_location, v_dedup_key
      );
    end if;
  end if;
end;
$function$;

revoke execute on function app.evaluate_stop_geofence(uuid, uuid, uuid, geography, timestamptz, jsonb) from public;
grant execute on function app.evaluate_stop_geofence(uuid, uuid, uuid, geography, timestamptz, jsonb) to service_role;

create or replace function public.evaluate_stop_geofence(p_tenant_id uuid, p_shipment_leg_id uuid, p_canonical_event_id uuid, p_location geography, p_event_at timestamp with time zone, p_geofence_policy jsonb)
 returns void
 language sql
 security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select app.evaluate_stop_geofence(p_tenant_id, p_shipment_leg_id, p_canonical_event_id, p_location, p_event_at, p_geofence_policy);
$function$;

revoke execute on function public.evaluate_stop_geofence(uuid, uuid, uuid, geography, timestamptz, jsonb) from public, anon, authenticated;
grant execute on function public.evaluate_stop_geofence(uuid, uuid, uuid, geography, timestamptz, jsonb) to service_role;

-- app.evaluate_route_deviation -- calls bare ST_MakeLine/ST_Distance.
create or replace function app.evaluate_route_deviation(p_tenant_id uuid, p_shipment_leg_id uuid, p_canonical_event_id uuid, p_location geography, p_event_at timestamp with time zone, p_geofence_policy jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_deviation_policy jsonb;
  v_enabled boolean;
  v_corridor_width_meters numeric;
  v_sustained_seconds numeric;
  v_ref_line geography;
  v_stop_count integer;
  v_distance_meters numeric;
  v_state app.shipment_leg_route_deviation_states;
  v_has_state boolean;
  v_shipment_order_id uuid;
  v_correlation_key text;
begin
  v_deviation_policy := p_geofence_policy -> 'route_deviation';
  v_enabled := app.safe_jsonb_boolean(v_deviation_policy, 'enabled', true);
  if not v_enabled then
    return;
  end if;

  select count(*) into v_stop_count from app.shipment_leg_stops where shipment_leg_id = p_shipment_leg_id and location_geog is not null;
  if v_stop_count < 2 then
    return;
  end if;

  select ST_MakeLine(location_geog::geometry order by stop_sequence)::geography
  into v_ref_line
  from app.shipment_leg_stops
  where shipment_leg_id = p_shipment_leg_id and location_geog is not null;

  v_corridor_width_meters := app.safe_jsonb_numeric(v_deviation_policy, 'corridor_width_meters', 1500);
  if v_corridor_width_meters <= 0 or v_corridor_width_meters > app.postgis_max_query_radius_meters() then
    v_corridor_width_meters := 1500;
  end if;
  v_sustained_seconds := app.safe_jsonb_numeric(v_deviation_policy, 'deviation_sustained_seconds', 300);
  if v_sustained_seconds < 0 then
    v_sustained_seconds := 300;
  end if;

  v_distance_meters := ST_Distance(p_location, v_ref_line);

  select sl.shipment_order_id into v_shipment_order_id from app.shipment_legs sl where sl.id = p_shipment_leg_id;

  select * into v_state from app.shipment_leg_route_deviation_states where shipment_leg_id = p_shipment_leg_id;
  v_has_state := found;

  if v_distance_meters > v_corridor_width_meters then
    if not v_has_state then
      insert into app.shipment_leg_route_deviation_states (
        tenant_id, shipment_leg_id, state, first_off_corridor_at, last_evaluated_at, last_distance_meters
      ) values (
        p_tenant_id, p_shipment_leg_id, 'off_corridor', p_event_at, p_event_at, v_distance_meters
      )
      returning * into v_state;
    elsif v_state.state = 'on_corridor' then
      update app.shipment_leg_route_deviation_states
      set state = 'off_corridor', first_off_corridor_at = p_event_at, confirmed_at = null, last_evaluated_at = p_event_at, last_distance_meters = v_distance_meters, updated_at = now()
      where id = v_state.id
      returning * into v_state;
    else
      update app.shipment_leg_route_deviation_states
      set last_evaluated_at = p_event_at, last_distance_meters = v_distance_meters, updated_at = now()
      where id = v_state.id
      returning * into v_state;
    end if;

    if v_state.state = 'off_corridor' and v_state.confirmed_at is null
       and extract(epoch from (p_event_at - v_state.first_off_corridor_at)) >= v_sustained_seconds then
      update app.shipment_leg_route_deviation_states set confirmed_at = p_event_at, updated_at = now() where id = v_state.id;

      v_correlation_key := 'route_deviation:' || p_shipment_leg_id || ':' || to_char(v_state.first_off_corridor_at, 'YYYYMMDDHH24MISSUS');
      perform app.upsert_exception_signal(
        p_tenant_id, v_shipment_order_id, p_shipment_leg_id, 'route_deviation', 'delay', 'medium',
        p_canonical_event_id, p_location,
        format('Vehicle is %s meters off the planned route corridor (limit %s meters), sustained for at least %s seconds.', round(v_distance_meters), v_corridor_width_meters, v_sustained_seconds),
        v_correlation_key
      );
    end if;
  else
    if v_has_state and v_state.state = 'off_corridor' then
      update app.shipment_leg_route_deviation_states
      set state = 'on_corridor', first_off_corridor_at = null, confirmed_at = null, last_evaluated_at = p_event_at, last_distance_meters = v_distance_meters, updated_at = now()
      where id = v_state.id;
    end if;
  end if;
end;
$function$;

revoke execute on function app.evaluate_route_deviation(uuid, uuid, uuid, geography, timestamptz, jsonb) from public;
grant execute on function app.evaluate_route_deviation(uuid, uuid, uuid, geography, timestamptz, jsonb) to service_role;

create or replace function public.evaluate_route_deviation(p_tenant_id uuid, p_shipment_leg_id uuid, p_canonical_event_id uuid, p_location geography, p_event_at timestamp with time zone, p_geofence_policy jsonb)
 returns void
 language sql
 security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select app.evaluate_route_deviation(p_tenant_id, p_shipment_leg_id, p_canonical_event_id, p_location, p_event_at, p_geofence_policy);
$function$;

revoke execute on function public.evaluate_route_deviation(uuid, uuid, uuid, geography, timestamptz, jsonb) from public, anon, authenticated;
grant execute on function public.evaluate_route_deviation(uuid, uuid, uuid, geography, timestamptz, jsonb) to service_role;

-- app.evaluate_geofence_and_deviation_signals -- calls the two functions above,
-- no bare postgis call of its own. Note its own search_path has never included
-- `public` (only `app, pg_temp`) -- restated verbatim, unchanged.
create or replace function app.evaluate_geofence_and_deviation_signals(p_tenant_id uuid, p_vehicle_master_id uuid, p_canonical_event_id uuid, p_location geography, p_event_at timestamp with time zone)
 returns void
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_leg app.shipment_legs;
  v_policy app.shipment_leg_tracking_policies;
begin
  if p_location is null then
    return;
  end if;

  for v_leg in
    select sl.*
    from app.resource_assignments ra
    join app.shipment_legs sl on sl.shipment_order_id = ra.shipment_order_id and sl.leg_status in ('dispatched', 'in_transit')
    where ra.role = 'vehicle' and ra.resource_id = p_vehicle_master_id and ra.is_current and ra.status = 'active'
    order by sl.shipment_order_id, sl.sequence_no, sl.id
  loop
    select * into v_policy from app.shipment_leg_tracking_policies where shipment_leg_id = v_leg.id;
    if found and v_policy.status = 'active' and v_policy.tracking_required and v_policy.geofence_policy is not null
       and app.safe_jsonb_boolean(v_policy.geofence_policy, 'enabled', true) then
      perform app.evaluate_stop_geofence(p_tenant_id, v_leg.id, p_canonical_event_id, p_location, p_event_at, v_policy.geofence_policy);
      perform app.evaluate_route_deviation(p_tenant_id, v_leg.id, p_canonical_event_id, p_location, p_event_at, v_policy.geofence_policy);
    end if;
  end loop;
end;
$function$;

revoke execute on function app.evaluate_geofence_and_deviation_signals(uuid, uuid, uuid, geography, timestamptz) from public;
grant execute on function app.evaluate_geofence_and_deviation_signals(uuid, uuid, uuid, geography, timestamptz) to service_role;

create or replace function public.evaluate_geofence_and_deviation_signals(p_tenant_id uuid, p_vehicle_master_id uuid, p_canonical_event_id uuid, p_location geography, p_event_at timestamp with time zone)
 returns void
 language sql
 security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select app.evaluate_geofence_and_deviation_signals(p_tenant_id, p_vehicle_master_id, p_canonical_event_id, p_location, p_event_at);
$function$;

revoke execute on function public.evaluate_geofence_and_deviation_signals(uuid, uuid, uuid, geography, timestamptz) from public, anon, authenticated;
grant execute on function public.evaluate_geofence_and_deviation_signals(uuid, uuid, uuid, geography, timestamptz) to service_role;

-- app.arbitrate_and_project_vehicle_position -- calls bare ST_Distance, and calls
-- app.evaluate_geofence_and_deviation_signals (already recreated above).
create or replace function app.arbitrate_and_project_vehicle_position(p_tenant_id uuid, p_vehicle_master_id uuid, p_source_type text, p_source_report_id uuid, p_event_at timestamp with time zone, p_received_at timestamp with time zone, p_location geography, p_speed_kmh numeric, p_heading_degrees numeric, p_accuracy_meters numeric)
 returns app.canonical_telemetry_events
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_existing app.canonical_telemetry_events;
  v_event app.canonical_telemetry_events;
  v_current app.vehicle_current_positions;
  v_has_current boolean;
  v_source_health app.vehicle_source_health;
  v_integrity_rejected boolean := false;
  v_has_source_history boolean;
  v_policy record;
  v_incoming_rank integer;
  v_current_rank integer;
  v_apply boolean := false;
  v_reason text;
  v_switch_reason text;
  v_distance_meters numeric;
  v_elapsed_seconds numeric;
  v_implied_speed_kmh numeric;
  v_evidence jsonb;
  v_th_shipment_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_vehicle_master_id::text, 0));

  select * into v_existing from app.canonical_telemetry_events where source_type = p_source_type and source_report_id = p_source_report_id;
  if found then
    return v_existing;
  end if;

  select * into v_current from app.vehicle_current_positions where vehicle_master_id = p_vehicle_master_id;
  v_has_current := found;

  select * into v_source_health from app.vehicle_source_health where vehicle_master_id = p_vehicle_master_id and source_type = p_source_type;
  v_has_source_history := found;

  select * into v_policy from app.resolve_tenant_tracking_source_policy(p_tenant_id);

  v_incoming_rank := app.resolve_vehicle_source_priority_rank(p_tenant_id, p_vehicle_master_id, p_source_type);

  if v_incoming_rank is null then
    v_reason := 'source_disabled';
  elsif p_location is null then
    v_reason := 'heartbeat_no_location';
  elsif p_event_at > clock_timestamp() + interval '24 hours' then
    v_reason := 'event_time_implausible_future';
  elsif p_accuracy_meters is not null and p_accuracy_meters > v_policy.accuracy_threshold_meters then
    v_reason := 'accuracy_below_threshold';
  elsif v_has_current and p_event_at <= v_current.event_at then
    v_reason := 'stale_event_time';
  elsif v_has_source_history and v_source_health.last_location is not null and v_source_health.last_seen_event_at is not null then
    v_distance_meters := ST_Distance(v_source_health.last_location, p_location);
    v_elapsed_seconds := extract(epoch from (p_event_at - v_source_health.last_seen_event_at));
    if v_elapsed_seconds > 0 then
      v_implied_speed_kmh := (v_distance_meters / 1000) / (v_elapsed_seconds / 3600);
      if v_implied_speed_kmh > 200 then
        v_reason := 'impossible_movement';
      end if;
    end if;
  end if;

  if v_reason is null and v_has_current and v_current.source_type <> p_source_type then
    v_current_rank := coalesce(app.resolve_vehicle_source_priority_rank(p_tenant_id, p_vehicle_master_id, v_current.source_type), 999999);
    declare
      v_is_higher_priority boolean := v_incoming_rank < v_current_rank;
      v_current_is_stale boolean := (p_received_at - v_current.received_at) > (v_policy.freshness_threshold_seconds::text || ' seconds')::interval;
      v_recent_switch boolean;
    begin
      select exists (
        select 1 from app.vehicle_source_switches
        where vehicle_master_id = p_vehicle_master_id and switched_at > now() - (v_policy.switch_hysteresis_seconds::text || ' seconds')::interval
      ) into v_recent_switch;

      if (v_is_higher_priority or v_current_is_stale) and not v_recent_switch then
        v_apply := true;
        v_switch_reason := case when v_is_higher_priority then 'higher_priority_source_available' else 'current_source_stale_fallback' end;
        v_evidence := jsonb_build_object(
          'incoming_rank', v_incoming_rank, 'current_rank', v_current_rank,
          'is_higher_priority', v_is_higher_priority, 'current_is_stale', v_current_is_stale,
          'freshness_threshold_seconds', v_policy.freshness_threshold_seconds
        );
      else
        v_reason := 'switch_suppressed';
      end if;
    end;
  elsif v_reason is null then
    v_apply := true;
    if not v_has_current then
      v_switch_reason := 'bootstrap';
      v_evidence := jsonb_build_object('incoming_rank', v_incoming_rank);
    end if;
  end if;

  v_integrity_rejected := v_reason in (
    'impossible_movement', 'event_time_implausible_future', 'accuracy_below_threshold'
  );

  insert into app.canonical_telemetry_events (
    tenant_id, vehicle_master_id, source_type, source_report_id, event_at, received_at,
    location, speed_kmh, heading_degrees, accuracy_meters, applied_to_current_position, rejection_reason
  ) values (
    p_tenant_id, p_vehicle_master_id, p_source_type, p_source_report_id, p_event_at, p_received_at,
    p_location, p_speed_kmh, p_heading_degrees, p_accuracy_meters, v_apply, case when v_apply then null else v_reason end
  )
  returning * into v_event;

  if v_apply then
    insert into app.vehicle_current_positions (tenant_id, vehicle_master_id, source_type, canonical_telemetry_event_id, location, speed_kmh, heading_degrees, event_at, received_at)
    values (p_tenant_id, p_vehicle_master_id, p_source_type, v_event.id, p_location, p_speed_kmh, p_heading_degrees, p_event_at, p_received_at)
    on conflict (vehicle_master_id) do update
      set source_type = excluded.source_type, canonical_telemetry_event_id = excluded.canonical_telemetry_event_id,
          location = excluded.location, speed_kmh = excluded.speed_kmh, heading_degrees = excluded.heading_degrees,
          event_at = excluded.event_at, received_at = excluded.received_at;

    if v_switch_reason is not null then
      insert into app.vehicle_source_switches (tenant_id, vehicle_master_id, from_source_type, to_source_type, reason, canonical_telemetry_event_id, evidence)
      values (p_tenant_id, p_vehicle_master_id, case when v_has_current then v_current.source_type else null end, p_source_type, v_switch_reason, v_event.id, coalesce(v_evidence, '{}'::jsonb));
    end if;
  end if;

  insert into app.vehicle_source_health (tenant_id, vehicle_master_id, source_type, last_seen_event_at, last_seen_received_at, last_location)
  values (p_tenant_id, p_vehicle_master_id, p_source_type, p_event_at, p_received_at, p_location)
  on conflict (vehicle_master_id, source_type) do update
    set last_seen_event_at = case
          when v_integrity_rejected then app.vehicle_source_health.last_seen_event_at
          else greatest(app.vehicle_source_health.last_seen_event_at, excluded.last_seen_event_at)
        end,
        last_seen_received_at = greatest(app.vehicle_source_health.last_seen_received_at, excluded.last_seen_received_at),
        last_location = case
          when v_integrity_rejected then app.vehicle_source_health.last_location
          when excluded.last_location is not null and (app.vehicle_source_health.last_seen_event_at is null or p_event_at >= app.vehicle_source_health.last_seen_event_at)
          then excluded.last_location
          else app.vehicle_source_health.last_location
        end,
        updated_at = now();

  if v_apply then
    perform app.evaluate_geofence_and_deviation_signals(p_tenant_id, p_vehicle_master_id, v_event.id, p_location, p_event_at);
  end if;

  begin
    for v_th_shipment_id in
      select ra.shipment_order_id
      from app.resource_assignments ra
      where ra.resource_id = p_vehicle_master_id and ra.role = 'vehicle' and ra.is_current and ra.status = 'active'
    loop
      perform app.recalculate_shipment_tracking_health(v_th_shipment_id);
    end loop;
  exception
    when others then
      null;
  end;

  return v_event;
end;
$function$;

revoke execute on function app.arbitrate_and_project_vehicle_position(uuid, uuid, text, uuid, timestamptz, timestamptz, geography, numeric, numeric, numeric) from public;
grant execute on function app.arbitrate_and_project_vehicle_position(uuid, uuid, text, uuid, timestamptz, timestamptz, geography, numeric, numeric, numeric) to service_role;

create or replace function public.arbitrate_and_project_vehicle_position(p_tenant_id uuid, p_vehicle_master_id uuid, p_source_type text, p_source_report_id uuid, p_event_at timestamp with time zone, p_received_at timestamp with time zone, p_location geography, p_speed_kmh numeric, p_heading_degrees numeric, p_accuracy_meters numeric)
 returns app.canonical_telemetry_events
 language sql
 security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select app.arbitrate_and_project_vehicle_position(p_tenant_id, p_vehicle_master_id, p_source_type, p_source_report_id, p_event_at, p_received_at, p_location, p_speed_kmh, p_heading_degrees, p_accuracy_meters);
$function$;

revoke execute on function public.arbitrate_and_project_vehicle_position(uuid, uuid, text, uuid, timestamptz, timestamptz, geography, numeric, numeric, numeric) from public, anon, authenticated;
grant execute on function public.arbitrate_and_project_vehicle_position(uuid, uuid, text, uuid, timestamptz, timestamptz, geography, numeric, numeric, numeric) to service_role;

-- app._ingest_attendance_event -- calls no bare postgis function itself, but DOES
-- declare a local `v_stored_location geography` variable -- unlike a parameter or
-- return type (resolved once, from the calling session's search_path, at
-- CREATE-time signature parsing), a PL/pgSQL local variable's type is resolved
-- using the FUNCTION'S OWN `search_path` (Postgres validates a plpgsql body's
-- DECLARE section against its own `SET search_path` at CREATE time when
-- `check_function_bodies` is on, which it is by default) -- caught live, the hard
-- way, mid-drafting this migration: rebuilding this function with its original
-- `app, public, pg_temp` search_path (no `extensions`) made its own `CREATE OR
-- REPLACE FUNCTION` statement fail outright with `type "geography" does not
-- exist`, not merely a later call. `extensions` is added here for that reason,
-- not because this function calls a bare `ST_*()` (it does not). No public.*
-- wrapper exists for this one (an OUT-parameter internal primitive, never
-- PostgREST-exposed).
create or replace function app._ingest_attendance_event(p_employee app.employees, p_event_type text, p_source_channel text, p_client_reported_at timestamp with time zone, p_location geography, p_idempotency_key text, p_raw_payload jsonb, p_source_staging_row_id uuid, p_actor_auth_user_id uuid, p_actor_label text, OUT v_event app.attendance_events)
 returns app.attendance_events
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_existing app.attendance_events;
  v_policy app.attendance_policy_versions;
  v_work_date date;
  v_session app.attendance_sessions;
  v_now timestamptz := clock_timestamp();
  v_effective_at timestamptz;
  v_geofence_result text := 'not_evaluated';
  v_stored_location geography;
  v_location_source text := 'none';
  v_inside boolean;
  v_schedule_assignment_id uuid;
begin
  if p_employee.master_record_id is null then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;
  if p_employee.lifecycle_status <> 'active' then
    raise exception 'employee_not_active: employee % is %, only an active employee may record attendance', p_employee.master_record_id, p_employee.lifecycle_status
      using errcode = 'check_violation';
  end if;

  v_effective_at := case
    when p_source_channel in ('manual_hr', 'device_import') and p_client_reported_at is not null
      then p_client_reported_at
    else v_now
  end;

  if p_idempotency_key is not null then
    select * into v_existing from app.attendance_events where tenant_id = p_employee.tenant_id and employee_id = p_employee.master_record_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.event_type = p_event_type and v_existing.source_channel = p_source_channel and v_existing.client_reported_at is not distinct from p_client_reported_at then
        v_event := v_existing;
        return;
      else
        raise exception 'idempotency_key_conflict: key % was already used for a different attendance event', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
    end if;
  end if;

  select * into v_policy from app.resolve_effective_attendance_policy_version(p_employee.tenant_id, p_employee.branch_org_unit_id, (v_now at time zone 'UTC')::date) limit 1;
  if not found then
    raise exception 'no_eligible_policy: no published attendance policy is effective for employee % as of %', p_employee.master_record_id, v_now
      using errcode = 'check_violation';
  end if;

  if p_source_channel <> 'manual_hr' and not (p_source_channel = any (v_policy.allowed_channels)) then
    raise exception 'channel_not_permitted: channel % is not permitted by the effective attendance policy', p_source_channel
      using errcode = 'check_violation';
  end if;

  if p_source_channel not in ('manual_hr', 'device_import') and v_policy.location_enforcement_mode <> 'none' then
    if p_location is null then
      if v_policy.location_enforcement_mode = 'required' then
        raise exception 'location_required: the effective attendance policy requires a real, evaluated location' using errcode = 'check_violation';
      end if;
    else
      v_inside := app.bounded_st_dwithin(p_location, v_policy.geofence_center, v_policy.geofence_radius_meters);
      v_geofence_result := case when v_inside then 'inside' else 'outside' end;
      v_stored_location := p_location;
      v_location_source := 'gps';
      if not v_inside and v_policy.location_enforcement_mode = 'required' then
        raise exception 'outside_geofence: location is outside the effective policy''s governed geofence -- never a fake success' using errcode = 'check_violation';
      end if;
    end if;
  end if;

  v_work_date := app.resolve_attendance_workday(v_effective_at, v_policy.timezone, v_policy.day_boundary_local_time);

  if p_event_type = 'clock_in' then
    if exists (select 1 from app.attendance_sessions where tenant_id = p_employee.tenant_id and employee_id = p_employee.master_record_id and status = 'open' for update) then
      raise exception 'duplicate_open_session: employee % already has an open attendance session -- clock out first', p_employee.master_record_id
        using errcode = 'check_violation';
    end if;
    if exists (select 1 from app.attendance_sessions where tenant_id = p_employee.tenant_id and employee_id = p_employee.master_record_id and work_date = v_work_date) then
      raise exception 'duplicate_workday_session: employee % already has an attendance session for %', p_employee.master_record_id, v_work_date
        using errcode = 'check_violation';
    end if;

    insert into app.attendance_events (
      tenant_id, employee_id, event_type, source_channel, client_reported_at, server_received_at,
      location, location_source, geofence_result, policy_version_id, raw_payload, source_import_staging_row_id, idempotency_key, created_by
    ) values (
      p_employee.tenant_id, p_employee.master_record_id, p_event_type, p_source_channel, p_client_reported_at, v_now,
      v_stored_location, v_location_source, v_geofence_result, v_policy.id, p_raw_payload, p_source_staging_row_id, p_idempotency_key, p_actor_label
    ) returning * into v_event;

    select id into v_schedule_assignment_id from app.resolve_effective_schedule_assignment(p_employee.tenant_id, p_employee.master_record_id, v_work_date) limit 1;

    insert into app.attendance_sessions (
      tenant_id, employee_id, work_date, timezone, policy_version_id, status, clock_in_event_id, raw_clock_in_at, schedule_assignment_id
    ) values (
      p_employee.tenant_id, p_employee.master_record_id, v_work_date, v_policy.timezone, v_policy.id, 'open', v_event.id, v_effective_at, v_schedule_assignment_id
    ) returning * into v_session;

    update app.attendance_events set session_id = v_session.id where id = v_event.id;
    v_event.session_id := v_session.id;

  elsif p_event_type = 'clock_out' then
    select * into v_session from app.attendance_sessions where tenant_id = p_employee.tenant_id and employee_id = p_employee.master_record_id and status = 'open' for update;
    if not found then
      raise exception 'no_open_session: employee % has no open attendance session to clock out of', p_employee.master_record_id
        using errcode = 'check_violation';
    end if;
    if v_effective_at < v_session.raw_clock_in_at then
      raise exception 'impossible_ordering: clock-out time precedes clock-in time for session %', v_session.id
        using errcode = 'check_violation';
    end if;

    insert into app.attendance_events (
      tenant_id, employee_id, event_type, source_channel, client_reported_at, server_received_at,
      location, location_source, geofence_result, policy_version_id, session_id, raw_payload, source_import_staging_row_id, idempotency_key, created_by
    ) values (
      p_employee.tenant_id, p_employee.master_record_id, p_event_type, p_source_channel, p_client_reported_at, v_now,
      v_stored_location, v_location_source, v_geofence_result, v_policy.id, v_session.id, p_raw_payload, p_source_staging_row_id, p_idempotency_key, p_actor_label
    ) returning * into v_event;

    update app.attendance_sessions
    set status = 'closed', clock_out_event_id = v_event.id, raw_clock_out_at = v_effective_at
    where id = v_session.id
    returning * into v_session;
  else
    raise exception 'invalid_event_type: % is not a recognized attendance event type', p_event_type using errcode = 'check_violation';
  end if;

  if v_geofence_result = 'outside' then
    insert into app.attendance_exceptions (tenant_id, employee_id, session_id, exception_type, severity, detail)
    values (p_employee.tenant_id, p_employee.master_record_id, v_session.id, 'out_of_geofence', 'medium', jsonb_build_object('event_id', v_event.id, 'event_type', p_event_type))
    on conflict (session_id, exception_type) where status in ('open', 'acknowledged')
    do update set detail = excluded.detail;
  end if;

  perform app._recalculate_session_exceptions(v_session.id);

  perform app.capture_audit_event(
    p_employee.tenant_id, p_actor_auth_user_id, p_actor_label, 'ingest_attendance_event',
    'app.attendance_events', v_event.id, 'success', null, null,
    jsonb_build_object('event_type', p_event_type, 'source_channel', p_source_channel, 'session_id', v_session.id, 'geofence_result', v_geofence_result, 'schedule_assignment_id', v_schedule_assignment_id)
  );
end;
$function$;

revoke execute on function app._ingest_attendance_event(app.employees, text, text, timestamptz, geography, text, jsonb, uuid, uuid, text) from public;
grant execute on function app._ingest_attendance_event(app.employees, text, text, timestamptz, geography, text, jsonb, uuid, uuid, text) to service_role;

-- ============================================================================
-- 7. 13 functions NOT dropped by CASCADE (no `geography` in their own signature)
--    whose pinned `search_path` needs `extensions` added because their body calls
--    a bare `ST_*()`. Body/signature otherwise byte-identical to the live
--    pre-drop capture.
-- ============================================================================

create or replace function app._compute_shipment_leg_eta(p_shipment_leg_id uuid)
 returns app.shipment_leg_eta_projection
 language plpgsql
 stable security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_leg app.shipment_legs;
  v_result app.shipment_leg_eta_projection;
  v_vehicle_master_id uuid;
  v_position app.vehicle_current_positions;
  v_policy record;
  v_freshness text;
  v_ref_line geography;
  v_stop_count integer;
  v_distance_meters numeric;
begin
  v_result.shipment_leg_id := p_shipment_leg_id;
  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    v_result.computable := false;
    v_result.reason := 'leg_not_found';
    return v_result;
  end if;
  v_result.planned_arrival_at := v_leg.planned_arrival_at;

  select count(*) into v_result.downstream_leg_count
  from app.shipment_legs
  where shipment_order_id = v_leg.shipment_order_id and sequence_no > v_leg.sequence_no and leg_status <> 'cancelled';

  if v_leg.leg_status not in ('dispatched', 'in_transit') then
    v_result.computable := false;
    v_result.reason := 'leg_not_active';
    return v_result;
  end if;

  select resource_id into v_vehicle_master_id from app.resource_assignments
    where shipment_order_id = v_leg.shipment_order_id and role = 'vehicle' and is_current and status = 'active';
  if v_vehicle_master_id is null then
    v_result.computable := false;
    v_result.reason := 'vehicle_not_assigned';
    return v_result;
  end if;

  select * into v_position from app.vehicle_current_positions where vehicle_master_id = v_vehicle_master_id;
  if not found then
    v_result.computable := false;
    v_result.reason := 'no_live_position';
    return v_result;
  end if;

  select * into v_policy from app.resolve_tenant_tracking_source_policy(v_leg.tenant_id);
  if now() - v_position.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval then
    v_freshness := 'healthy';
  elsif now() - v_position.received_at <= (v_policy.freshness_threshold_seconds::text || ' seconds')::interval * 3 then
    v_freshness := 'stale';
  else
    v_freshness := 'offline';
  end if;
  v_result.position_status := v_freshness;
  if v_freshness = 'offline' then
    v_result.computable := false;
    v_result.reason := 'position_stale';
    return v_result;
  end if;

  select count(*) into v_stop_count from app.shipment_leg_stops where shipment_leg_id = p_shipment_leg_id and stop_status = 'pending' and location_geog is not null;
  if v_stop_count = 0 then
    v_result.computable := false;
    v_result.reason := 'no_remaining_stops';
    return v_result;
  end if;

  select ST_MakeLine(pt::geometry order by seq)::geography into v_ref_line
  from (
    select 0 as seq, v_position.location as pt
    union all
    select stop_sequence, location_geog from app.shipment_leg_stops where shipment_leg_id = p_shipment_leg_id and stop_status = 'pending' and location_geog is not null
  ) points;

  v_distance_meters := ST_Length(v_ref_line);
  v_result.remaining_distance_km := round((v_distance_meters / 1000.0)::numeric, 2);
  v_result.estimated_arrival_at := now() + (v_result.remaining_distance_km / app.route_planning_default_speed_kmh()) * interval '1 hour';
  if v_leg.planned_arrival_at is not null then
    v_result.delay_minutes := round(extract(epoch from (v_result.estimated_arrival_at - v_leg.planned_arrival_at)) / 60, 1);
  end if;
  v_result.computable := true;
  v_result.reason := null;
  return v_result;
end;
$function$;

create or replace function app.generate_route_planning_candidates(p_scenario_id uuid, p_actor_label text)
 returns SETOF app.route_planning_candidate_plans
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_scenario app.route_planning_scenarios;
  v_total_distance_km numeric;
  v_distance_known boolean := true;
  v_prev_geog geography;
  v_cur_geog geography;
  v_first_stop app.route_planning_stops;
  v_last_stop app.route_planning_stops;
  v_max_weight numeric;
  v_max_volume numeric;
  v_max_distance numeric;
  v_required_vehicle uuid;
  v_required_driver uuid;
  v_earliest_departure timestamptz;
  v_latest_arrival timestamptz;
  v_effective_weight numeric;
  v_effective_volume numeric;
  v_reasons jsonb := '[]'::jsonb;
  v_vehicle record;
  v_drivers uuid[];
  v_driver_count integer;
  v_rank integer := 0;
  v_candidate app.route_planning_candidate_plans;
  v_duration numeric;
  v_utilization numeric;
  v_vehicle_exists boolean;
  r record;
begin
  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  delete from app.route_planning_score_components where candidate_plan_id in (
    select id from app.route_planning_candidate_plans where scenario_id = p_scenario_id
  );
  delete from app.route_planning_candidate_plans where scenario_id = p_scenario_id;

  v_total_distance_km := 0;
  v_prev_geog := null;
  for r in select * from app.route_planning_stops where scenario_id = p_scenario_id order by stop_sequence asc
  loop
    if v_prev_geog is not null then
      if r.location_geog is null then
        v_distance_known := false;
      else
        v_total_distance_km := v_total_distance_km + (ST_Distance(v_prev_geog, r.location_geog) / 1000.0);
      end if;
    end if;
    v_prev_geog := r.location_geog;
  end loop;
  if not v_distance_known then
    v_total_distance_km := null;
  end if;

  select * into v_first_stop from app.route_planning_stops where scenario_id = p_scenario_id order by stop_sequence asc limit 1;
  select * into v_last_stop from app.route_planning_stops where scenario_id = p_scenario_id order by stop_sequence desc limit 1;

  select (constraint_value ->> 'value')::numeric into v_max_weight from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'max_weight_kg' and constraint_type = 'hard';
  select (constraint_value ->> 'value')::numeric into v_max_volume from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'max_volume_cbm' and constraint_type = 'hard';
  select (constraint_value ->> 'value')::numeric into v_max_distance from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'max_distance_km' and constraint_type = 'hard';
  select (constraint_value ->> 'master_id')::uuid into v_required_vehicle from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'required_vehicle_master_id' and constraint_type = 'hard';
  select (constraint_value ->> 'master_id')::uuid into v_required_driver from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'required_driver_master_id' and constraint_type = 'hard';
  select (constraint_value ->> 'at')::timestamptz into v_earliest_departure from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'earliest_departure_at' and constraint_type = 'hard';
  select (constraint_value ->> 'at')::timestamptz into v_latest_arrival from app.route_planning_constraints where scenario_id = p_scenario_id and constraint_key = 'latest_arrival_at' and constraint_type = 'hard';

  v_effective_weight := coalesce(v_max_weight, v_scenario.requested_weight_kg);
  v_effective_volume := coalesce(v_max_volume, v_scenario.requested_volume_cbm);

  if v_max_distance is not null and v_total_distance_km is not null and v_total_distance_km > v_max_distance then
    v_reasons := v_reasons || jsonb_build_array('max_distance_exceeded');
  end if;
  if v_earliest_departure is not null and v_first_stop.time_window_start is not null and v_first_stop.time_window_start < v_earliest_departure then
    v_reasons := v_reasons || jsonb_build_array('earliest_departure_violated');
  end if;
  if v_latest_arrival is not null and v_last_stop.time_window_end is not null and v_last_stop.time_window_end > v_latest_arrival then
    v_reasons := v_reasons || jsonb_build_array('latest_arrival_violated');
  end if;

  select array_agg(driver_master_id order by driver_master_id) into v_drivers
  from app.driver_operational_profiles
  where tenant_id = v_scenario.tenant_id and status = 'active'
    and (v_required_driver is null or driver_master_id = v_required_driver);
  v_driver_count := coalesce(array_length(v_drivers, 1), 0);

  if v_driver_count = 0 then
    v_reasons := v_reasons || jsonb_build_array(case when v_required_driver is not null then 'required_driver_unavailable' else 'no_eligible_driver' end);
  end if;

  select exists (
    select 1 from app.vehicle_operational_profiles
    where tenant_id = v_scenario.tenant_id and status = 'active'
      and (v_required_vehicle is null or vehicle_master_id = v_required_vehicle)
      and (v_effective_weight is null or capacity_weight_kg is null or capacity_weight_kg >= v_effective_weight)
      and (v_effective_volume is null or capacity_volume_cbm is null or capacity_volume_cbm >= v_effective_volume)
  ) into v_vehicle_exists;

  if not v_vehicle_exists then
    v_reasons := v_reasons || jsonb_build_array(case when v_required_vehicle is not null then 'required_vehicle_unavailable' else 'no_eligible_vehicle' end);
  end if;

  if jsonb_array_length(v_reasons) > 0 then
    insert into app.route_planning_candidate_plans (tenant_id, scenario_id, plan_rank, feasible, infeasibility_reasons, total_distance_km)
    values (v_scenario.tenant_id, p_scenario_id, 1, false, v_reasons, v_total_distance_km)
    returning * into v_candidate;

    insert into app.route_planning_score_components (tenant_id, candidate_plan_id, component_key, component_value)
    values (v_scenario.tenant_id, v_candidate.id, 'total_distance_km', v_total_distance_km);

    update app.route_planning_scenarios set status = 'ready' where id = p_scenario_id;

    perform app.capture_audit_event(
      v_scenario.tenant_id, null, p_actor_label, 'generate_route_planning_candidates',
      'app.route_planning_scenarios', p_scenario_id, 'success', null, null,
      jsonb_build_object('feasible_count', 0)
    );

    return query select * from app.route_planning_candidate_plans where scenario_id = p_scenario_id;
    return;
  end if;

  for v_vehicle in
    select * from app.vehicle_operational_profiles
    where tenant_id = v_scenario.tenant_id and status = 'active'
      and (v_required_vehicle is null or vehicle_master_id = v_required_vehicle)
      and (v_effective_weight is null or capacity_weight_kg is null or capacity_weight_kg >= v_effective_weight)
      and (v_effective_volume is null or capacity_volume_cbm is null or capacity_volume_cbm >= v_effective_volume)
    order by capacity_weight_kg asc nulls last, vehicle_master_id asc
    limit 3
  loop
    v_rank := v_rank + 1;

    v_duration := case when v_total_distance_km is not null then round(v_total_distance_km / app.route_planning_default_speed_kmh() * 60, 1) else null end;
    v_utilization := case when v_effective_weight is not null and v_vehicle.capacity_weight_kg is not null and v_vehicle.capacity_weight_kg > 0
      then round(v_effective_weight / v_vehicle.capacity_weight_kg * 100, 1) else null end;

    insert into app.route_planning_candidate_plans (
      tenant_id, scenario_id, plan_rank, feasible, vehicle_master_id, driver_master_id,
      total_distance_km, estimated_duration_minutes, capacity_utilization_pct
    ) values (
      v_scenario.tenant_id, p_scenario_id, v_rank, true, v_vehicle.vehicle_master_id, v_drivers[1 + ((v_rank - 1) % v_driver_count)],
      v_total_distance_km, v_duration, v_utilization
    )
    returning * into v_candidate;

    insert into app.route_planning_score_components (tenant_id, candidate_plan_id, component_key, component_value) values
      (v_scenario.tenant_id, v_candidate.id, 'total_distance_km', v_total_distance_km),
      (v_scenario.tenant_id, v_candidate.id, 'estimated_duration_minutes', v_duration),
      (v_scenario.tenant_id, v_candidate.id, 'capacity_utilization_pct', v_utilization);
  end loop;

  update app.route_planning_scenarios set status = 'ready' where id = p_scenario_id;

  perform app.capture_audit_event(
    v_scenario.tenant_id, null, p_actor_label, 'generate_route_planning_candidates',
    'app.route_planning_scenarios', p_scenario_id, 'success', null, null,
    jsonb_build_object('feasible_count', v_rank)
  );

  return query select * from app.route_planning_candidate_plans where scenario_id = p_scenario_id order by plan_rank asc;
end;
$function$;

create or replace function app.get_direct_device_telemetry_reports(p_device_id uuid)
 returns TABLE(id uuid, tenant_id uuid, device_id uuid, report_type text, event_at timestamp with time zone, received_at timestamp with time zone, location_geojson jsonb, altitude_meters numeric, heading_degrees numeric, speed_kmh numeric, satellite_count integer, raw_codec_id text, io_elements jsonb, created_at timestamp with time zone)
 language sql
 stable
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
  select
    r.id, r.tenant_id, r.device_id, r.report_type,
    r.event_at, r.received_at,
    case when r.location is not null then ST_AsGeoJSON(r.location)::jsonb else null end,
    r.altitude_meters, r.heading_degrees, r.speed_kmh, r.satellite_count,
    r.raw_codec_id, r.io_elements, r.created_at
  from app.direct_device_telemetry_reports r
  where r.device_id = p_device_id
  order by r.received_at desc;
$function$;

create or replace function app.get_driver_mobile_position_reports(p_driver_mobile_tracking_session_id uuid)
 returns TABLE(id uuid, tenant_id uuid, driver_mobile_tracking_session_id uuid, report_type text, event_at timestamp with time zone, received_at timestamp with time zone, location_geojson jsonb, accuracy_meters numeric, battery_percent integer, location_permission_granted boolean, background_permission_granted boolean, raw_payload jsonb, created_at timestamp with time zone)
 language sql
 stable
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
  select
    r.id, r.tenant_id, r.driver_mobile_tracking_session_id, r.report_type,
    r.event_at, r.received_at,
    case when r.location is not null then ST_AsGeoJSON(r.location)::jsonb else null end,
    r.accuracy_meters, r.battery_percent,
    r.location_permission_granted, r.background_permission_granted,
    r.raw_payload, r.created_at
  from app.driver_mobile_position_reports r
  where r.driver_mobile_tracking_session_id = p_driver_mobile_tracking_session_id
  order by r.received_at desc;
$function$;

create or replace function app.get_shipment_exception_signals(p_shipment_order_id uuid, p_actor_auth_user_id uuid, p_status text DEFAULT 'pending'::text)
 returns TABLE(id uuid, tenant_id uuid, shipment_order_id uuid, shipment_leg_id uuid, signal_type text, exception_type text, severity text, detected_at timestamp with time zone, source_canonical_event_id uuid, location_geojson jsonb, description text, correlation_key text, status text, resulting_exception_id uuid, reviewed_by_user_id uuid, reviewed_at timestamp with time zone, review_note text, created_at timestamp with time zone)
 language plpgsql
 stable security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    s.id, s.tenant_id, s.shipment_order_id, s.shipment_leg_id, s.signal_type,
    s.exception_type, s.severity, s.detected_at, s.source_canonical_event_id,
    case when s.location is not null then ST_AsGeoJSON(s.location)::jsonb else null end,
    s.description, s.correlation_key, s.status,
    s.resulting_exception_id, s.reviewed_by_user_id, s.reviewed_at, s.review_note, s.created_at
  from app.shipment_exception_signals s
  where s.shipment_order_id = p_shipment_order_id and (p_status is null or s.status = p_status)
  order by s.detected_at desc;
end;
$function$;

create or replace function app.get_shipment_leg_geofence_state(p_shipment_leg_id uuid, p_actor_auth_user_id uuid)
 returns TABLE(id uuid, tenant_id uuid, shipment_leg_stop_id uuid, shipment_leg_id uuid, radius_meters numeric, dwell_seconds_before_confirm numeric, state text, first_entered_at timestamp with time zone, confirmed_at timestamp with time zone, last_evaluated_at timestamp with time zone, last_evaluated_location_geojson jsonb, created_at timestamp with time zone, updated_at timestamp with time zone)
 language plpgsql
 stable security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_leg from app.shipment_legs sl where sl.id = p_shipment_leg_id;
  if not found then
    raise exception 'shipment_leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_leg.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment leg %', p_actor_auth_user_id, p_shipment_leg_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    g.id, g.tenant_id, g.shipment_leg_stop_id, g.shipment_leg_id,
    g.radius_meters, g.dwell_seconds_before_confirm, g.state,
    g.first_entered_at, g.confirmed_at, g.last_evaluated_at,
    case when g.last_evaluated_location is not null then ST_AsGeoJSON(g.last_evaluated_location)::jsonb else null end,
    g.created_at, g.updated_at
  from app.shipment_leg_stop_geofence_states g
  where g.shipment_leg_id = p_shipment_leg_id
  order by g.created_at;
end;
$function$;

create or replace function app.get_shipment_milestone_candidates(p_shipment_order_id uuid, p_actor_auth_user_id uuid, p_status text DEFAULT 'pending'::text)
 returns TABLE(id uuid, tenant_id uuid, shipment_order_id uuid, shipment_leg_id uuid, shipment_leg_stop_id uuid, milestone_code text, candidate_event_time timestamp with time zone, detected_at timestamp with time zone, source_canonical_event_id uuid, location_geojson jsonb, status text, dedup_key text, resulting_milestone_event_id uuid, reviewed_by_user_id uuid, reviewed_at timestamp with time zone, review_note text, created_at timestamp with time zone)
 language plpgsql
 stable security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    c.id, c.tenant_id, c.shipment_order_id, c.shipment_leg_id, c.shipment_leg_stop_id,
    c.milestone_code, c.candidate_event_time, c.detected_at,
    c.source_canonical_event_id, case when c.location is not null then ST_AsGeoJSON(c.location)::jsonb else null end,
    c.status, c.dedup_key, c.resulting_milestone_event_id, c.reviewed_by_user_id, c.reviewed_at, c.review_note, c.created_at
  from app.shipment_milestone_candidates c
  where c.shipment_order_id = p_shipment_order_id and (p_status is null or c.status = p_status)
  order by c.detected_at desc;
end;
$function$;

create or replace function app.get_tenant_pending_exception_signals(p_tenant_id uuid, p_actor_auth_user_id uuid, p_limit integer DEFAULT 50)
 returns TABLE(id uuid, shipment_order_id uuid, shipment_number text, shipment_leg_id uuid, signal_type text, exception_type text, severity text, detected_at timestamp with time zone, description text, location_geojson jsonb)
 language plpgsql
 stable security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    s.id, s.shipment_order_id, so.shipment_number, s.shipment_leg_id,
    s.signal_type, s.exception_type, s.severity, s.detected_at, s.description,
    case when s.location is not null then ST_AsGeoJSON(s.location)::jsonb else null end
  from app.shipment_exception_signals s
  join app.shipment_orders so on so.id = s.shipment_order_id
  where s.tenant_id = p_tenant_id and s.status = 'pending'
    and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id,
          app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  order by s.detected_at desc
  limit least(coalesce(p_limit, 50), 200);
end;
$function$;

create or replace function app.get_tenant_pending_milestone_candidates(p_tenant_id uuid, p_actor_auth_user_id uuid, p_limit integer DEFAULT 50)
 returns TABLE(id uuid, shipment_order_id uuid, shipment_number text, shipment_leg_id uuid, shipment_leg_stop_id uuid, milestone_code text, candidate_event_time timestamp with time zone, detected_at timestamp with time zone, location_geojson jsonb)
 language plpgsql
 stable security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    c.id, c.shipment_order_id, so.shipment_number, c.shipment_leg_id, c.shipment_leg_stop_id,
    c.milestone_code, c.candidate_event_time, c.detected_at,
    case when c.location is not null then ST_AsGeoJSON(c.location)::jsonb else null end
  from app.shipment_milestone_candidates c
  join app.shipment_orders so on so.id = c.shipment_order_id
  where c.tenant_id = p_tenant_id and c.status = 'pending'
    and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id,
          app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  order by c.detected_at desc
  limit least(coalesce(p_limit, 50), 200);
end;
$function$;

create or replace function app.get_tenant_vehicle_tracking_overview(p_tenant_id uuid, p_actor_auth_user_id uuid)
 returns TABLE(vehicle_master_id uuid, vehicle_code text, vehicle_name text, mobile_tracking_eligible boolean, direct_device_tracking_eligible boolean, third_party_tracking_eligible boolean, current_source_type text, current_location_geojson jsonb, current_speed_kmh numeric, current_heading_degrees numeric, current_event_at timestamp with time zone, current_received_at timestamp with time zone)
 language plpgsql
 stable security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    vop.vehicle_master_id, mr.code, mr.name,
    vop.mobile_tracking_eligible, vop.direct_device_tracking_eligible, vop.third_party_tracking_eligible,
    vcp.source_type,
    case when vcp.location is not null then ST_AsGeoJSON(vcp.location)::jsonb else null end,
    vcp.speed_kmh, vcp.heading_degrees, vcp.event_at, vcp.received_at
  from app.vehicle_operational_profiles vop
  join app.master_records mr on mr.id = vop.vehicle_master_id
  left join app.vehicle_current_positions vcp on vcp.vehicle_master_id = vop.vehicle_master_id
  where vop.tenant_id = p_tenant_id and vop.status = 'active'
  order by mr.code;
end;
$function$;

create or replace function app.get_third_party_telemetry_reports(p_connection_id uuid)
 returns TABLE(id uuid, tenant_id uuid, connection_id uuid, vehicle_master_id uuid, provider_event_id text, report_type text, event_at timestamp with time zone, received_at timestamp with time zone, location_geojson jsonb, speed_kmh numeric, heading_degrees numeric, raw_fields jsonb, created_at timestamp with time zone)
 language sql
 stable
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
  select
    r.id, r.tenant_id, r.connection_id, r.vehicle_master_id, r.provider_event_id,
    r.report_type, r.event_at, r.received_at,
    case when r.location is not null then ST_AsGeoJSON(r.location)::jsonb else null end,
    r.speed_kmh, r.heading_degrees, r.raw_fields, r.created_at
  from app.third_party_telemetry_reports r
  where r.connection_id = p_connection_id
  order by r.received_at desc;
$function$;

create or replace function app.get_vehicle_current_position(p_vehicle_master_id uuid)
 returns TABLE(vehicle_master_id uuid, tenant_id uuid, source_type text, location_geojson jsonb, speed_kmh numeric, heading_degrees numeric, event_at timestamp with time zone, received_at timestamp with time zone, updated_at timestamp with time zone)
 language sql
 stable
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
  select
    p.vehicle_master_id, p.tenant_id, p.source_type, ST_AsGeoJSON(p.location)::jsonb,
    p.speed_kmh, p.heading_degrees, p.event_at, p.received_at, p.updated_at
  from app.vehicle_current_positions p
  where p.vehicle_master_id = p_vehicle_master_id;
$function$;

create or replace function app.get_vehicle_telemetry_history(p_vehicle_master_id uuid, p_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 200)
 returns TABLE(id uuid, tenant_id uuid, vehicle_master_id uuid, source_type text, event_at timestamp with time zone, received_at timestamp with time zone, location_geojson jsonb, speed_kmh numeric, heading_degrees numeric, accuracy_meters numeric, applied_to_current_position boolean, rejection_reason text)
 language sql
 stable
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
  select
    e.id, e.tenant_id, e.vehicle_master_id, e.source_type, e.event_at, e.received_at,
    case when e.location is not null then ST_AsGeoJSON(e.location)::jsonb else null end,
    e.speed_kmh, e.heading_degrees, e.accuracy_meters, e.applied_to_current_position, e.rejection_reason
  from app.canonical_telemetry_events e
  where e.vehicle_master_id = p_vehicle_master_id and (p_since is null or e.event_at >= p_since)
  order by e.event_at desc
  limit least(coalesce(p_limit, 200), 500);
$function$;

-- ============================================================================
-- 8. app.set_epod_evidence -- the 35th and last function, found only by the
--    literal `public\.geography` sweep, not the "calls a bare ST_*()" sweep (it
--    calls no ST_* function directly, it only holds a `geography` value fetched
--    from app.geojson_point_to_geography). Its `declare v_geog public.geography;`
--    is an EXPLICIT schema qualification that stops resolving once postgis moves
--    -- `search_path` cannot fix this on its own. Fixed by dropping the "public."
--    qualifier (`v_geog geography;`, matching every sibling function's own
--    convention) AND adding `extensions` to search_path (defense in depth, in
--    case a future edit to this function ever adds a bare ST_*() call of its own).
--    Every other line is byte-identical to the live pre-fix body.
-- ============================================================================

create or replace function app.set_epod_evidence(p_capture_id uuid, p_receiver_name text, p_receiver_position text, p_signature_file_id uuid, p_photo_file_ids uuid[], p_delivery_geojson jsonb, p_captured_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.epod_captures
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_capture app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_file app.files;
  v_photo_id uuid;
  v_geog geography;
  v_updated app.epod_captures;
begin
  select * into v_capture from app.epod_captures where id = p_capture_id;
  if not found then
    raise exception 'epod_capture_not_found: %', p_capture_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_capture.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_capture.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_capture.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_capture.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_capture.status not in ('draft', 'revision_requested') then
    raise exception 'invalid_transition: ePOD capture % is % and its evidence can no longer be edited', p_capture_id, v_capture.status
      using errcode = 'check_violation';
  end if;

  if p_signature_file_id is not null then
    select * into v_file from app.files where id = p_signature_file_id;
    if not found or v_file.tenant_id <> v_capture.tenant_id or v_file.record_type <> 'shipment_order' or v_file.record_id <> v_capture.shipment_order_id then
      raise exception 'epod_evidence_file_mismatch: signature file % does not belong to shipment order %', p_signature_file_id, v_capture.shipment_order_id
        using errcode = 'check_violation';
    end if;
  end if;

  if p_photo_file_ids is not null then
    foreach v_photo_id in array p_photo_file_ids loop
      select * into v_file from app.files where id = v_photo_id;
      if not found or v_file.tenant_id <> v_capture.tenant_id or v_file.record_type <> 'shipment_order' or v_file.record_id <> v_capture.shipment_order_id then
        raise exception 'epod_evidence_file_mismatch: photo file % does not belong to shipment order %', v_photo_id, v_capture.shipment_order_id
          using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  if p_delivery_geojson is not null then
    v_geog := app.geojson_point_to_geography(p_delivery_geojson);
  end if;

  update app.epod_captures
  set receiver_name = p_receiver_name,
      receiver_position = p_receiver_position,
      signature_file_id = p_signature_file_id,
      photo_file_ids = coalesce(p_photo_file_ids, '{}'::uuid[]),
      delivery_geog = v_geog,
      captured_at = p_captured_at,
      status = 'draft'
  where id = p_capture_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_capture.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_epod_evidence',
    'app.epod_captures', v_updated.id, 'success', null, to_jsonb(v_capture), to_jsonb(v_updated)
  );

  return v_updated;
end;
$function$;

grant execute on function app.set_epod_evidence(uuid, text, text, uuid, uuid[], jsonb, timestamptz, uuid, text) to authenticated, service_role;

-- ============================================================================
-- 9. 8 further functions, found only by re-running this migration's own
--    `db:test` suite locally against a fresh disposable Postgres (never merely
--    reasoned about from the earlier sweeps) -- the true, complete criterion for
--    "needs `extensions` in search_path" is broader than "calls a bare `ST_*()`
--    in its own body" (section 7's sweep) or "has `geography` in its own
--    signature" (section 6's CASCADE-driven list): it also includes any function
--    with a `geography`-typed LOCAL VARIABLE in its own `declare` block. Unlike a
--    parameter or return type (resolved once, from the calling session's
--    search_path, when the surrounding `CREATE FUNCTION` statement is itself
--    parsed), a PL/pgSQL local variable's type is resolved against the
--    FUNCTION'S OWN `search_path` -- either at `CREATE FUNCTION` time if
--    `check_function_bodies` is on (Postgres's default, and what caught this
--    migration's own `app._ingest_attendance_event` omission in section 6, live,
--    while first drafting it), or lazily on that function's first call in a
--    session if the function's own definition was never touched. These 8 were
--    never touched by sections 6-8 (no `geography` in their own signature, no
--    bare `ST_*()` call in their own body -- each only calls
--    `app.geojson_point_to_geography`/`app.geojson_point_to_geography`-family
--    helpers and assigns the result to a local `geography` variable), so their
--    live, pre-migration `search_path` (`app, public, pg_temp`) was never
--    revisited by anything above -- and would have kept "existing" post-
--    relocation while failing the FIRST time anything actually called them
--    (`scripts/db-tests/postgis.sql`'s own new ISS-2026-234 regression section
--    caught exactly this: `app.add_shipment_leg_stop`'s first real call after a
--    from-scratch migration replay raised `type "geography" does not exist`
--    against a function this migration had not even listed). A `search_path ~*
--    '(geography|geometry)\s*;''` sweep of every `plpgsql` function schema-wide,
--    re-run against the live project as a closing check (not merely against this
--    local reproduction), found exactly these 8 and no others beyond what
--    sections 6-8 already cover. None of the 8 has `geography` in its own
--    signature (parameter or return type), so CASCADE never dropped any of
--    them -- each keeps its live, pre-migration ACL automatically (`CREATE OR
--    REPLACE` on a function that still exists never resets its grants; only a
--    genuinely dropped-and-recreated object risks the PUBLIC-default trap
--    section 6's own header describes) -- no `revoke`/`grant` needed for any of
--    these 8, body/signature otherwise byte-identical to their live pre-fix
--    capture.
-- ============================================================================

create or replace function app.add_route_planning_stop(p_scenario_id uuid, p_stop_sequence integer, p_stop_type text, p_location_name text, p_address text, p_longitude numeric, p_latitude numeric, p_time_window_start timestamp with time zone, p_time_window_end timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.route_planning_stops
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_scenario app.route_planning_scenarios;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_stop app.route_planning_stops;
  v_geog geography;
begin
  if p_stop_type not in ('pickup', 'transfer', 'delivery') then
    raise exception 'invalid_stop_type: % is not a supported stop type', p_stop_type using errcode = 'check_violation';
  end if;

  if p_stop_sequence is null or p_stop_sequence <= 0 then
    raise exception 'invalid_sequence: stop_sequence must be a positive integer' using errcode = 'check_violation';
  end if;

  if p_location_name is null or length(trim(p_location_name)) = 0 then
    raise exception 'location_name_required: a non-empty location_name is required' using errcode = 'check_violation';
  end if;

  select * into v_scenario from app.route_planning_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_scenario.shipment_order_id;

  if v_scenario.status <> 'draft' then
    raise exception 'scenario_not_mutable: scenario % is % and its stops can only be edited while draft', p_scenario_id, v_scenario.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_scenario.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_longitude is not null and p_latitude is not null then
    v_geog := app.geojson_point_to_geography(jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(p_longitude, p_latitude)));
  end if;

  insert into app.route_planning_stops (
    tenant_id, scenario_id, stop_sequence, stop_type, location_name, address, location_geog, time_window_start, time_window_end, created_by
  ) values (
    v_scenario.tenant_id, p_scenario_id, p_stop_sequence, p_stop_type, p_location_name, p_address, v_geog, p_time_window_start, p_time_window_end, p_actor_label
  )
  returning * into v_stop;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_route_planning_stop',
    'app.route_planning_stops', v_stop.id, 'success', null, null,
    jsonb_build_object('scenario_id', p_scenario_id, 'stop_sequence', p_stop_sequence, 'stop_type', p_stop_type)
  );

  return v_stop;
end;
$function$;

create or replace function app.add_shipment_leg_stop(p_shipment_leg_id uuid, p_stop_sequence integer, p_stop_type text, p_location_name text, p_address text, p_longitude numeric, p_latitude numeric, p_planned_at timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.shipment_leg_stops
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_stop app.shipment_leg_stops;
  v_geog geography;
begin
  if p_stop_type not in ('pickup', 'transfer', 'delivery') then
    raise exception 'invalid_stop_type: % is not a supported stop type', p_stop_type using errcode = 'check_violation';
  end if;

  if p_stop_sequence is null or p_stop_sequence <= 0 then
    raise exception 'invalid_sequence: stop_sequence must be a positive integer' using errcode = 'check_violation';
  end if;

  if p_location_name is null or length(trim(p_location_name)) = 0 then
    raise exception 'location_name_required: a non-empty location_name is required' using errcode = 'check_violation';
  end if;

  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id;

  if v_leg.leg_status <> 'planned' then
    raise exception 'leg_not_mutable: leg % is % and its stops can only be edited while planned', p_shipment_leg_id, v_leg.leg_status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_longitude is not null and p_latitude is not null then
    v_geog := app.geojson_point_to_geography(jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(p_longitude, p_latitude)));
  end if;

  insert into app.shipment_leg_stops (
    tenant_id, shipment_leg_id, stop_sequence, stop_type, location_name, address, location_geog, planned_at, created_by
  ) values (
    v_leg.tenant_id, p_shipment_leg_id, p_stop_sequence, p_stop_type, p_location_name, p_address, v_geog, p_planned_at, p_actor_label
  )
  returning * into v_stop;

  perform app.capture_audit_event(
    v_leg.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_shipment_leg_stop',
    'app.shipment_leg_stops', v_stop.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'stop_sequence', p_stop_sequence, 'stop_type', p_stop_type)
  );

  return v_stop;
end;
$function$;

create or replace function app.create_attendance_policy_version(p_policy_id uuid, p_timezone text, p_workday_start_time time without time zone, p_workday_end_time time without time zone, p_day_boundary_local_time time without time zone, p_grace_late_minutes integer, p_grace_early_minutes integer, p_allowed_channels text[], p_location_enforcement_mode text, p_geofence_center_geojson jsonb, p_geofence_radius_meters numeric, p_max_session_hours numeric, p_effective_from date, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.attendance_policy_versions
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_decision app.rbac_decision;
  v_policy app.attendance_policies;
  v_next_version integer;
  v_version app.attendance_policy_versions;
  v_geofence geography;
begin
  select * into v_policy from app.attendance_policies where id = p_policy_id;
  if not found or not app.has_active_tenant_membership(v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'policy_not_found: %', p_policy_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_policy.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_policy.status = 'archived' then
    raise exception 'invalid_transition: policy % is archived, cannot author a new version', p_policy_id using errcode = 'check_violation';
  end if;

  if not app.validate_iana_timezone(p_timezone) then
    raise exception 'invalid_timezone: % is not a recognized IANA timezone', p_timezone using errcode = 'check_violation';
  end if;

  if p_geofence_center_geojson is not null then
    v_geofence := app.geojson_point_to_geography(p_geofence_center_geojson);
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.attendance_policy_versions where policy_id = p_policy_id;

  insert into app.attendance_policy_versions (
    policy_id, tenant_id, version_number, effective_from, timezone, workday_start_time, workday_end_time,
    day_boundary_local_time, grace_late_minutes, grace_early_minutes, allowed_channels, location_enforcement_mode,
    geofence_center, geofence_radius_meters, max_session_hours, created_by
  ) values (
    p_policy_id, v_policy.tenant_id, v_next_version, p_effective_from, p_timezone, p_workday_start_time, p_workday_end_time,
    coalesce(p_day_boundary_local_time, '00:00:00'::time), coalesce(p_grace_late_minutes, 0), coalesce(p_grace_early_minutes, 0),
    coalesce(p_allowed_channels, array['mobile_web', 'kiosk']::text[]), coalesce(p_location_enforcement_mode, 'none'),
    v_geofence, p_geofence_radius_meters, coalesce(p_max_session_hours, 16), p_actor_label
  ) returning * into v_version;

  perform app.capture_audit_event(
    v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_attendance_policy_version',
    'app.attendance_policy_versions', v_version.id, 'success', null, null, jsonb_build_object('policy_id', p_policy_id, 'version_number', v_next_version)
  );

  return v_version;
end;
$function$;

create or replace function app.create_warehouse(p_tenant_id uuid, p_company_org_unit_id uuid, p_code text, p_name text, p_site_address text, p_timezone text, p_site_geojson jsonb, p_service_type_eligibility text[], p_actor_auth_user_id uuid, p_actor_label text)
 returns app.warehouses
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_decision app.rbac_decision;
  v_org_unit app.org_units;
  v_existing app.warehouses;
  v_warehouse app.warehouses;
  v_geog geography;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'invalid_code: code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_org_unit from app.org_units where id = p_company_org_unit_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'org_unit_not_found: % is not an org unit of tenant %', p_company_org_unit_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(p_company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot create a warehouse under org unit %', p_actor_auth_user_id, p_company_org_unit_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_timezone is null or not app.validate_timezone_name(p_timezone) then
    raise exception 'invalid_timezone: % is not a recognized timezone', p_timezone using errcode = 'check_violation';
  end if;

  if p_site_geojson is not null then
    v_geog := app.geojson_point_to_geography(p_site_geojson);
  end if;

  select * into v_existing from app.warehouses where tenant_id = p_tenant_id and code = p_code;
  if found then
    if v_existing.company_org_unit_id <> p_company_org_unit_id then
      raise exception 'warehouse_code_conflict: code % already exists for tenant % under a different company org unit', p_code, p_tenant_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  begin
    insert into app.warehouses (
      tenant_id, company_org_unit_id, code, name, site_address, timezone, site_geog, service_type_eligibility, created_by
    ) values (
      p_tenant_id, p_company_org_unit_id, p_code, p_name, p_site_address, p_timezone, v_geog, coalesce(p_service_type_eligibility, '{}'::text[]), p_actor_label
    )
    returning * into v_warehouse;
  exception
    when unique_violation then
      select * into v_warehouse from app.warehouses where tenant_id = p_tenant_id and code = p_code;
      if found then
        return v_warehouse;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_warehouse',
    'app.warehouses', v_warehouse.id, 'success', null, null,
    jsonb_build_object('code', p_code, 'name', p_name, 'company_org_unit_id', p_company_org_unit_id)
  );

  return v_warehouse;
end;
$function$;

create or replace function app.update_warehouse(p_warehouse_id uuid, p_name text, p_site_address text, p_timezone text, p_site_geojson jsonb, p_service_type_eligibility text[], p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.warehouses
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_geog geography;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id for update;
  if not found then
    raise exception 'warehouse_not_found: %', p_warehouse_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_warehouse.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_warehouse.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_warehouse.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  if v_warehouse.record_version <> p_expected_version then
    raise exception 'stale_version: warehouse % expected version % but found %', p_warehouse_id, p_expected_version, v_warehouse.record_version
      using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: name is required' using errcode = 'check_violation';
  end if;
  if p_timezone is null or not app.validate_timezone_name(p_timezone) then
    raise exception 'invalid_timezone: % is not a recognized timezone', p_timezone using errcode = 'check_violation';
  end if;

  if p_site_geojson is not null then
    v_geog := app.geojson_point_to_geography(p_site_geojson);
  end if;

  update app.warehouses set
    name = p_name,
    site_address = p_site_address,
    timezone = p_timezone,
    site_geog = v_geog,
    service_type_eligibility = coalesce(p_service_type_eligibility, '{}'::text[])
  where id = p_warehouse_id
  returning * into v_warehouse;

  perform app.capture_audit_event(
    v_warehouse.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_warehouse',
    'app.warehouses', v_warehouse.id, 'success', null, null,
    jsonb_build_object('name', p_name, 'timezone', p_timezone)
  );

  return v_warehouse;
end;
$function$;

create or replace function app.ingest_direct_device_telemetry_batch(p_raw_api_key text, p_device_id uuid, p_reports jsonb, p_gateway_instance_label text)
 returns TABLE(device_id uuid, tenant_id uuid, accepted_count integer, device_status text)
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_auth record;
  v_device app.gps_devices;
  v_report jsonb;
  v_report_type text;
  v_event_at timestamptz;
  v_lon numeric;
  v_lat numeric;
  v_geojson jsonb;
  v_geog geography;
  v_accepted integer := 0;
  v_max_event_at timestamptz;
  v_new_status text;
  v_label text;
  v_report_id uuid;
  v_received_at timestamptz;
  v_vehicle_master_id uuid;
begin
  if p_device_id is null then
    raise exception 'device_id_required: a device_id is required' using errcode = 'check_violation';
  end if;
  if p_reports is null or jsonb_typeof(p_reports) <> 'array' or jsonb_array_length(p_reports) = 0 then
    raise exception 'reports_required: at least one report is required' using errcode = 'check_violation';
  end if;

  select * into v_auth from app.authenticate_api_key(p_raw_api_key);

  if not app.api_key_has_scope(v_auth.api_key_id, 'OPS:Edit') then
    raise exception 'insufficient_authority: presented API key lacks OPS:Edit scope required for GPS gateway operation'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_device from app.gps_devices where id = p_device_id;
  if not found then
    raise exception 'device_not_found: %', p_device_id using errcode = 'no_data_found';
  end if;
  if v_device.tenant_id <> v_auth.tenant_id then
    raise exception 'tenant_mismatch: device % belongs to a different tenant than the presented API key', p_device_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_device.status not in ('installed', 'active', 'offline') then
    raise exception 'device_not_ingestible: device % is % and cannot accept telemetry', p_device_id, v_device.status
      using errcode = 'check_violation';
  end if;

  v_label := coalesce(p_gateway_instance_label, 'gps-gateway') || ':' || v_device.imei;
  v_max_event_at := v_device.last_telemetry_at;
  v_vehicle_master_id := app.resolve_vehicle_for_gps_device(v_device.id);

  for v_report in select * from jsonb_array_elements(p_reports)
  loop
    v_report_type := v_report ->> 'report_type';
    if v_report_type not in ('location', 'heartbeat') then
      raise exception 'invalid_report_type: % is not a supported report type', v_report_type using errcode = 'check_violation';
    end if;

    v_event_at := (v_report ->> 'event_at')::timestamptz;
    if v_event_at is null then
      raise exception 'event_at_required: every report requires event_at' using errcode = 'check_violation';
    end if;

    v_geog := null;
    if v_report_type = 'location' then
      v_lon := (v_report ->> 'longitude')::numeric;
      v_lat := (v_report ->> 'latitude')::numeric;
      if v_lon is null or v_lat is null then
        raise exception 'location_required: a location report requires longitude and latitude' using errcode = 'check_violation';
      end if;
      v_geojson := jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(v_lon, v_lat));
      v_geog := app.geojson_point_to_geography(v_geojson);
    end if;

    if exists (
      select 1 from app.direct_device_telemetry_reports r
      where r.device_id = v_device.id and r.event_at = v_event_at and r.report_type = v_report_type
    ) then
      continue;
    end if;

    v_received_at := clock_timestamp();
    insert into app.direct_device_telemetry_reports (
      tenant_id, device_id, report_type, event_at, received_at, location,
      altitude_meters, heading_degrees, speed_kmh, satellite_count, raw_codec_id, io_elements
    ) values (
      v_device.tenant_id, v_device.id, v_report_type, v_event_at, v_received_at, v_geog,
      (v_report ->> 'altitude_meters')::numeric, (v_report ->> 'heading_degrees')::numeric,
      (v_report ->> 'speed_kmh')::numeric, (v_report ->> 'satellite_count')::integer,
      coalesce(v_report ->> 'raw_codec_id', '8E'), coalesce(v_report -> 'io_elements', '{}'::jsonb)
    )
    returning id into v_report_id;

    v_accepted := v_accepted + 1;
    if v_max_event_at is null or v_event_at > v_max_event_at then
      v_max_event_at := v_event_at;
    end if;

    if v_vehicle_master_id is not null then
      perform app.arbitrate_and_project_vehicle_position(
        v_device.tenant_id, v_vehicle_master_id, 'direct_device', v_report_id, v_event_at, v_received_at,
        v_geog, (v_report ->> 'speed_kmh')::numeric, (v_report ->> 'heading_degrees')::numeric, null::numeric
      );
    end if;
  end loop;

  v_new_status := v_device.status;
  if v_device.status in ('installed', 'offline') then
    v_new_status := 'active';
  end if;

  update app.gps_devices
  set last_telemetry_at = v_max_event_at,
      status = v_new_status
  where id = v_device.id
  returning * into v_device;

  perform app.capture_audit_event(
    v_device.tenant_id, null, v_label, 'ingest_direct_device_telemetry_batch',
    'app.gps_devices', v_device.id, 'success', null, null,
    jsonb_build_object('device_id', v_device.id, 'accepted_count', v_accepted, 'device_status', v_new_status)
  );

  return query select v_device.id, v_device.tenant_id, v_accepted, v_device.status;
end;
$function$;

create or replace function app.ingest_third_party_provider_webhook_event(p_connection_id uuid, p_client_key text, p_raw_payload text, p_timestamp bigint, p_signature text)
 returns TABLE(ingest_status text, report_id uuid)
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_recent_bad_count integer;
  v_conn app.third_party_provider_connections;
  v_payload jsonb;
  v_event_id text;
  v_vehicle_external_id text;
  v_report_type text;
  v_event_at timestamptz;
  v_lat numeric;
  v_lon numeric;
  v_speed numeric;
  v_heading numeric;
  v_mapping app.provider_vehicle_mappings;
  v_geojson jsonb;
  v_geog geography;
  v_report app.third_party_telemetry_reports;
  v_new_failure_count integer;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'tracking_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent_bad_count
  from app.third_party_provider_ingestion_attempts
  where result = 'invalid' and occurred_at > now() - interval '15 minutes'
    and (connection_id = p_connection_id or client_key = p_client_key);
  if v_recent_bad_count >= 10 then
    insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'rate_limited', 'rate_limited');
    return query select 'rate_limited'::text, null::uuid;
    return;
  end if;

  select * into v_conn from app.third_party_provider_connections where id = p_connection_id;
  if not found or v_conn.integration_mode <> 'webhook' or v_conn.status <> 'active' then
    insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (v_conn.id, p_client_key, 'invalid', 'connection_not_active');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  if not app.verify_third_party_provider_webhook_signature(p_connection_id, p_raw_payload, p_timestamp, p_signature) then
    v_new_failure_count := v_conn.consecutive_failure_count + 1;
    update app.third_party_provider_connections
    set consecutive_failure_count = v_new_failure_count,
        status = case when v_new_failure_count >= 10 then 'disabled' else status end,
        auto_disabled_at = case when v_new_failure_count >= 10 and status <> 'disabled' then now() else auto_disabled_at end,
        disabled_reason = case when v_new_failure_count >= 10 and status <> 'disabled' then 'consecutive_failure_threshold_exceeded' else disabled_reason end
    where id = v_conn.id;

    insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'signature_verification_failed');
    perform app.raise_observability_alert(
      v_conn.tenant_id, 'webhook', 'error',
      format('webhook signature verification failed: connection %s (third_party_provider)', p_connection_id),
      'high', format('connection_id=%s client_key=%s', p_connection_id, p_client_key)
    );
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  begin
    v_payload := p_raw_payload::jsonb;
  exception
    when others then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'malformed_json');
      return query select 'invalid'::text, null::uuid;
      return;
  end;

  begin
    v_event_id := v_payload ->> 'event_id';
    v_vehicle_external_id := v_payload ->> 'vehicle_id';
    v_report_type := v_payload ->> 'event_type';
    v_event_at := (v_payload ->> 'timestamp')::timestamptz;

    if v_event_id is null or v_vehicle_external_id is null or v_report_type not in ('location', 'heartbeat') or v_event_at is null then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'invalid', 'schema_validation_failed', v_payload);
      return query select 'invalid'::text, null::uuid;
      return;
    end if;

    if exists (select 1 from app.third_party_telemetry_reports where connection_id = p_connection_id and provider_event_id = v_event_id) then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'duplicate', 'provider_event_id_already_ingested');
      return query select 'duplicate'::text, null::uuid;
      return;
    end if;

    select * into v_mapping
    from app.provider_vehicle_mappings
    where tenant_id = v_conn.tenant_id and provider_code = v_conn.provider_code and external_vehicle_id = v_vehicle_external_id and status = 'active';
    if not found then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'quarantined', 'unmapped_external_vehicle_id', v_payload);
      return query select 'quarantined'::text, null::uuid;
      return;
    end if;

    v_lat := (v_payload ->> 'latitude')::numeric;
    v_lon := (v_payload ->> 'longitude')::numeric;
    v_speed := (v_payload ->> 'speed_kmh')::numeric;
    v_heading := (v_payload ->> 'heading_degrees')::numeric;

    if v_report_type = 'location' and (v_lat is null or v_lon is null) then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'invalid', 'location_report_missing_coordinates', v_payload);
      return query select 'invalid'::text, null::uuid;
      return;
    end if;

    v_geog := null;
    if v_report_type = 'location' then
      v_geojson := jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(v_lon, v_lat));
      v_geog := app.geojson_point_to_geography(v_geojson);
    end if;

    insert into app.third_party_telemetry_reports (
      tenant_id, connection_id, vehicle_master_id, provider_event_id, report_type, event_at, location, speed_kmh, heading_degrees, raw_fields
    ) values (
      v_conn.tenant_id, v_conn.id, v_mapping.vehicle_master_id, v_event_id, v_report_type, v_event_at, v_geog, v_speed, v_heading, v_payload
    )
    returning * into v_report;
  exception
    when others then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'invalid', 'malformed_field_value', v_payload);
      return query select 'invalid'::text, null::uuid;
      return;
  end;

  update app.third_party_provider_connections set last_successful_ingest_at = now(), consecutive_failure_count = 0 where id = v_conn.id;

  insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result) values (p_connection_id, p_client_key, 'success');

  perform app.arbitrate_and_project_vehicle_position(
    v_conn.tenant_id, v_mapping.vehicle_master_id, 'third_party_platform', v_report.id, v_event_at, v_report.received_at,
    v_geog, v_speed, v_heading, null::numeric
  );

  return query select 'ok'::text, v_report.id;
end;
$function$;

create or replace function app.record_attendance_clock_event(p_tenant_id uuid, p_event_type text, p_source_channel text, p_client_reported_at timestamp with time zone, p_location_geojson jsonb, p_device_label text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
 returns app.attendance_events
 language plpgsql
 security definer
 set search_path to 'app', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_self app.employees;
  v_location geography;
  v_result app.attendance_events;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;

  if p_source_channel not in ('mobile_web', 'kiosk') then
    raise exception 'invalid_source_channel: self-service clock events must use mobile_web or kiosk' using errcode = 'check_violation';
  end if;

  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if p_location_geojson is not null then
    v_location := app.geojson_point_to_geography(p_location_geojson);
  end if;

  v_result := app._ingest_attendance_event(
    v_self, p_event_type, p_source_channel, p_client_reported_at, v_location,
    p_idempotency_key, null, null, p_actor_auth_user_id, p_actor_label
  );

  if p_device_label is not null then
    update app.attendance_events set device_label = p_device_label where id = v_result.id;
    v_result.device_label := p_device_label;
  end if;

  return v_result;
end;
$function$;
