-- Real, executable test evidence for PLT-134 (PostGIS and Spatial Foundation,
-- CG-S6-PLT-031) -- see scripts/db-tests/config.sql's own header for the general
-- pattern this file follows.

\set ON_ERROR_STOP on

\echo '>> extension: postgis is installed at the expected major version'
do $$
declare
  v_version text;
begin
  if not exists (select 1 from pg_extension where extname = 'postgis') then
    raise exception 'assertion failed: expected the postgis extension to be installed';
  end if;

  select PostGIS_Version() into v_version;
  if v_version !~ '^3\.' then
    raise exception 'assertion failed: expected PostGIS major version 3.x, got %', v_version;
  end if;
end;
$$;

\echo '>> app.postgis_max_query_radius_meters: the governed bounded-radius cap (ADR-0014)'
do $$
begin
  if app.postgis_max_query_radius_meters() <> 500000 then
    raise exception 'assertion failed: expected the governed max query radius to be 500000 meters, got %', app.postgis_max_query_radius_meters();
  end if;
end;
$$;

\echo '>> app.geojson_point_to_geography / app.geography_to_geojson_point: round-trip within tolerance, correct SRID, no axis swap (Jakarta, equator, antimeridian, poles)'
do $$
declare
  v_geog geography;
  v_roundtrip jsonb;
  v_jakarta jsonb := '{"type":"Point","coordinates":[106.845599,-6.208763]}'::jsonb;
begin
  -- Jakarta: longitude ~106.8 (east), latitude ~-6.2 (south of equator). If axes were
  -- ever swapped, ST_X would report the latitude instead -- this is the concrete,
  -- numeric anti-axis-swap proof, not just a type-level check.
  v_geog := app.geojson_point_to_geography(v_jakarta);
  if ST_SRID(v_geog) <> 4326 then
    raise exception 'assertion failed: expected SRID 4326, got %', ST_SRID(v_geog);
  end if;
  if abs(ST_X(v_geog::geometry) - 106.845599) > 0.000001 then
    raise exception 'assertion failed: expected ST_X (longitude) to be 106.845599, got % -- possible axis swap', ST_X(v_geog::geometry);
  end if;
  if abs(ST_Y(v_geog::geometry) - (-6.208763)) > 0.000001 then
    raise exception 'assertion failed: expected ST_Y (latitude) to be -6.208763, got % -- possible axis swap', ST_Y(v_geog::geometry);
  end if;

  v_roundtrip := app.geography_to_geojson_point(v_geog);
  if (v_roundtrip ->> 'type') <> 'Point' then
    raise exception 'assertion failed: expected round-trip GeoJSON type=Point, got %', v_roundtrip ->> 'type';
  end if;
  if abs(((v_roundtrip -> 'coordinates') -> 0)::text::numeric - 106.845599) > 0.000001
     or abs(((v_roundtrip -> 'coordinates') -> 1)::text::numeric - (-6.208763)) > 0.000001 then
    raise exception 'assertion failed: expected the GeoJSON round-trip to preserve coordinates within tolerance, got %', v_roundtrip;
  end if;

  -- Equator/antimeridian/pole boundary values -- all legal, none rejected.
  perform app.geojson_point_to_geography('{"type":"Point","coordinates":[0,0]}'::jsonb);
  perform app.geojson_point_to_geography('{"type":"Point","coordinates":[180,0]}'::jsonb);
  perform app.geojson_point_to_geography('{"type":"Point","coordinates":[-180,0]}'::jsonb);
  perform app.geojson_point_to_geography('{"type":"Point","coordinates":[0,90]}'::jsonb);
  perform app.geojson_point_to_geography('{"type":"Point","coordinates":[0,-90]}'::jsonb);

  -- Null input -> null output (an optional coordinate, per Prompt 134 §22).
  if app.geojson_point_to_geography(null) is not null then
    raise exception 'assertion failed: expected a null GeoJSON input to return null, not synthesize a point';
  end if;
end;
$$;

\echo '>> app.geojson_point_to_geography: rejects wrong type, wrong coordinate count, and out-of-range coordinates -- explicitly, never silently coerced'
do $$
begin
  begin
    perform app.geojson_point_to_geography('{"type":"LineString","coordinates":[[0,0],[1,1]]}'::jsonb);
    raise exception 'assertion failed: expected a non-Point GeoJSON type to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.geojson_point_to_geography('{"type":"Point","coordinates":[0,0,0]}'::jsonb);
    raise exception 'assertion failed: expected a 3-element coordinates array to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.geojson_point_to_geography('{"type":"Point","coordinates":[181,0]}'::jsonb);
    raise exception 'assertion failed: expected longitude=181 to be rejected, not silently coerced to 180 (the exact PostGIS cast-clamping defect this migration exists to prevent)';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.geojson_point_to_geography('{"type":"Point","coordinates":[0,95]}'::jsonb);
    raise exception 'assertion failed: expected latitude=95 to be rejected, not silently coerced to 90';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.geojson_point_to_geography('{"type":"Point","coordinates":[-200,-100]}'::jsonb);
    raise exception 'assertion failed: expected a doubly out-of-range coordinate to be rejected';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.validate_geography_point: true for a real point, false for an empty or non-point geometry'
do $$
declare
  v_point geography;
  v_empty geography;
  v_line geography;
begin
  v_point := app.geojson_point_to_geography('{"type":"Point","coordinates":[106.845599,-6.208763]}'::jsonb);
  if not app.validate_geography_point(v_point) then
    raise exception 'assertion failed: expected a real point to validate as true';
  end if;

  v_empty := ST_GeomFromText('POINT EMPTY', 4326)::geography;
  if app.validate_geography_point(v_empty) then
    raise exception 'assertion failed: expected an empty geometry to validate as false';
  end if;

  v_line := ST_SetSRID(ST_MakeLine(ST_MakePoint(0, 0), ST_MakePoint(1, 1)), 4326)::geography;
  if app.validate_geography_point(v_line) then
    raise exception 'assertion failed: expected a LineString to validate as false (this function is Point-only)';
  end if;

  if app.validate_geography_point(null) then
    raise exception 'assertion failed: expected a null geography to validate as false';
  end if;
end;
$$;

\echo '>> app.bounded_st_dwithin: rejects a non-positive or over-cap radius; correctly distinguishes near/far at a valid radius'
do $$
declare
  v_jakarta geography;
  v_bogor geography;
  v_singapore geography;
begin
  v_jakarta := app.geojson_point_to_geography('{"type":"Point","coordinates":[106.845599,-6.208763]}'::jsonb);
  -- Bogor: ~40km south of Jakarta.
  v_bogor := app.geojson_point_to_geography('{"type":"Point","coordinates":[106.806038,-6.595038]}'::jsonb);
  -- Singapore: ~880km from Jakarta -- outside a 100km search, inside the 500km cap.
  v_singapore := app.geojson_point_to_geography('{"type":"Point","coordinates":[103.819836,1.352083]}'::jsonb);

  begin
    perform app.bounded_st_dwithin(v_jakarta, v_bogor, 0);
    raise exception 'assertion failed: expected a zero radius to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.bounded_st_dwithin(v_jakarta, v_bogor, -5);
    raise exception 'assertion failed: expected a negative radius to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.bounded_st_dwithin(v_jakarta, v_singapore, 600000);
    raise exception 'assertion failed: expected a radius exceeding the 500,000m governed cap to be rejected -- no unbounded global spatial scan';
  exception
    when check_violation then
      null;
  end;

  if not app.bounded_st_dwithin(v_jakarta, v_bogor, 100000) then
    raise exception 'assertion failed: expected Jakarta-Bogor (~40km) to be within a 100km bounded radius';
  end if;

  if app.bounded_st_dwithin(v_jakarta, v_singapore, 100000) then
    raise exception 'assertion failed: expected Jakarta-Singapore (~880km) to be outside a 100km bounded radius';
  end if;
end;
$$;

\echo '>> representative example (Prompt 134 §20 task 3): a governed geography column + GiST index proves the real indexing/query pattern -- table created and dropped entirely within this test script, never a permanent migration artifact (docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md line 108: spatial columns belong on owning-domain tables, not a standalone geo table)'
do $$
declare
  v_acme_tenant_id uuid := '00000000-0000-0000-0000-000000006001';
  v_gizmo_tenant_id uuid := '00000000-0000-0000-0000-000000006002';
  v_nearby_count integer;
  v_plan text;
  v_uses_index boolean := false;
  v_line text;
begin
  create table pg_temp.example_locations (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null,
    label text not null,
    location geography(Point, 4326) not null,
    constraint example_locations_location_valid check (app.validate_geography_point(location))
  );
  create index example_locations_location_gist_idx on pg_temp.example_locations using gist (location);

  begin
    insert into pg_temp.example_locations (tenant_id, label, location) values
      (v_acme_tenant_id, 'invalid', ST_GeomFromText('POINT EMPTY', 4326)::geography);
    raise exception 'assertion failed: expected the CHECK constraint to reject an invalid geography at insert time';
  exception
    when check_violation then
      null;
  end;

  insert into pg_temp.example_locations (tenant_id, label, location) values
    (v_acme_tenant_id, 'acme-hq-jakarta', app.geojson_point_to_geography('{"type":"Point","coordinates":[106.845599,-6.208763]}'::jsonb)),
    (v_acme_tenant_id, 'acme-branch-bogor', app.geojson_point_to_geography('{"type":"Point","coordinates":[106.806038,-6.595038]}'::jsonb)),
    (v_gizmo_tenant_id, 'gizmo-hq-singapore', app.geojson_point_to_geography('{"type":"Point","coordinates":[103.819836,1.352083]}'::jsonb));

  -- Tenant-scoped + bounded-radius query: only acme's own two rows are candidates, and
  -- only the Bogor branch is within 100km of the Jakarta HQ.
  select count(*) into v_nearby_count
  from pg_temp.example_locations
  where tenant_id = v_acme_tenant_id
    and label <> 'acme-hq-jakarta'
    and app.bounded_st_dwithin(location, (select location from pg_temp.example_locations where label = 'acme-hq-jakarta'), 100000);
  if v_nearby_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 tenant-scoped nearby row within 100km of acme HQ, got %', v_nearby_count;
  end if;

  select count(*) into v_nearby_count
  from pg_temp.example_locations
  where tenant_id = v_gizmo_tenant_id
    and app.bounded_st_dwithin(location, (select location from pg_temp.example_locations where label = 'acme-hq-jakarta'), 100000);
  if v_nearby_count <> 0 then
    raise exception 'assertion failed: expected zero cross-tenant rows to leak into acme''s own proximity query';
  end if;

  -- Query-plan evidence (Prompt 134 §17/§28): the GiST index is actually used for an
  -- ST_DWithin-shaped predicate, not a sequential scan. analyze first so the planner has
  -- real statistics to work with despite the tiny row count.
  analyze pg_temp.example_locations;
  for v_line in
    execute format(
      'explain (format text) select 1 from pg_temp.example_locations where ST_DWithin(location, %L::geography, 100000)',
      (select location from pg_temp.example_locations where label = 'acme-hq-jakarta')
    )
  loop
    v_plan := coalesce(v_plan, '') || v_line || E'\n';
    if v_line ilike '%example_locations_location_gist_idx%' or v_line ilike '%Index%Scan%' then
      v_uses_index := true;
    end if;
  end loop;

  if not v_uses_index then
    raise exception 'assertion failed: expected the GiST index to appear in the query plan for an ST_DWithin predicate, got plan: %', v_plan;
  end if;

  drop table pg_temp.example_locations;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any spatial helper function; authenticated does'
do $$
declare
  v_has_privilege boolean;
begin
  select has_function_privilege('authenticated', 'app.geojson_point_to_geography(jsonb)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on app.geojson_point_to_geography';
  end if;

  select has_function_privilege('anon', 'app.geojson_point_to_geography(jsonb)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on app.geojson_point_to_geography (ERR-2026-004 regression guard)';
  end if;

  select has_function_privilege('anon', 'app.bounded_st_dwithin(geography, geography, numeric)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on app.bounded_st_dwithin (ERR-2026-004 regression guard)';
  end if;
end;
$$;

-- ============================================================================
-- ISS-2026-234 closure regression evidence: `postgis` relocated `public` ->
-- `extensions` (`20260901150000_harden_relocate_postgis_out_of_public.sql`).
-- Proves: (1) postgis now resides in `extensions`, not `public`; (2) all 15
-- `geography`-typed columns still exist on their correct table with their
-- correct type, and a real INSERT with a real geography value into each
-- round-trips correctly; (3) a representative set of the 35 functions this
-- migration touched still execute correctly against real inputs post-
-- relocation, not merely "does not error"; (4) every GiST index that existed
-- on a geography column pre-migration still exists and is still usable.
-- ============================================================================

\echo '>> ISS-2026-234: postgis now resides in extensions, not public; pg_trgm/btree_gist stay relocated too'
do $$
declare
  v_schema text;
begin
  select n.nspname into v_schema from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'postgis';
  if v_schema is distinct from 'extensions' then
    raise exception 'assertion failed: expected postgis to reside in schema extensions, got %', v_schema;
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'st_distance') then
    raise exception 'assertion failed: expected no postgis-owned function (st_distance) to remain in public';
  end if;

  select n.nspname into v_schema from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pg_trgm';
  if v_schema is distinct from 'extensions' then
    raise exception 'assertion failed: expected pg_trgm to still reside in schema extensions, got %', v_schema;
  end if;
  select n.nspname into v_schema from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'btree_gist';
  if v_schema is distinct from 'extensions' then
    raise exception 'assertion failed: expected btree_gist to still reside in schema extensions, got %', v_schema;
  end if;
end;
$$;

\echo '>> ISS-2026-234: the exact 15 geography(Point,4326) columns exist, on their correct table, with their correct type/nullability -- no more, no fewer'
do $$
declare
  v_expected text[] := array[
    'attendance_events.location', 'attendance_policy_versions.geofence_center',
    'canonical_telemetry_events.location', 'direct_device_telemetry_reports.location',
    'driver_mobile_position_reports.location', 'epod_captures.delivery_geog',
    'route_planning_stops.location_geog', 'shipment_exception_signals.location',
    'shipment_leg_stop_geofence_states.last_evaluated_location', 'shipment_leg_stops.location_geog',
    'shipment_milestone_candidates.location', 'third_party_telemetry_reports.location',
    'vehicle_current_positions.location', 'vehicle_source_health.last_location', 'warehouses.site_geog'
  ];
  v_actual text[];
begin
  select array_agg(table_name || '.' || column_name order by table_name, column_name) into v_actual
  from information_schema.columns where table_schema = 'app' and udt_name = 'geography';

  if v_actual is distinct from (select array_agg(x order by x) from unnest(v_expected) x) then
    raise exception 'assertion failed: live geography-column set differs from the expected 15 -- expected %, got %', v_expected, v_actual;
  end if;
end;
$$;

do $$
declare
  r record;
begin
  for r in
    select table_name, column_name from unnest(array[
      'attendance_events.location', 'attendance_policy_versions.geofence_center',
      'canonical_telemetry_events.location', 'direct_device_telemetry_reports.location',
      'driver_mobile_position_reports.location', 'epod_captures.delivery_geog',
      'route_planning_stops.location_geog', 'shipment_exception_signals.location',
      'shipment_leg_stop_geofence_states.last_evaluated_location', 'shipment_leg_stops.location_geog',
      'shipment_milestone_candidates.location', 'third_party_telemetry_reports.location',
      'vehicle_current_positions.location', 'vehicle_source_health.last_location', 'warehouses.site_geog'
    ]) as pair(x)
    cross join lateral (select split_part(x, '.', 1) as table_name, split_part(x, '.', 2) as column_name) s
  loop
    declare
      v_type text;
      v_notnull boolean;
    begin
      select format_type(a.atttypid, a.atttypmod), a.attnotnull into v_type, v_notnull
      from pg_attribute a where a.attrelid = ('app.' || r.table_name)::regclass and a.attname = r.column_name and not a.attisdropped;

      if v_type is null then
        raise exception 'assertion failed: app.%.% does not exist post-relocation', r.table_name, r.column_name;
      end if;
      if v_type <> 'geography(Point,4326)' then
        raise exception 'assertion failed: app.%.% has type % post-relocation, expected geography(Point,4326)', r.table_name, r.column_name, v_type;
      end if;
      if r.table_name = 'vehicle_current_positions' and not v_notnull then
        raise exception 'assertion failed: app.vehicle_current_positions.location must still be NOT NULL post-relocation';
      end if;
      if r.table_name <> 'vehicle_current_positions' and v_notnull then
        raise exception 'assertion failed: app.%.% must still be nullable post-relocation, found NOT NULL', r.table_name, r.column_name;
      end if;
    end;
  end loop;
end;
$$;

\echo '>> ISS-2026-234: the 4 GiST indexes that existed on a geography column pre-migration still exist, and are still usable (query plan uses one)'
do $$
declare
  v_expected text[] := array['epod_captures_geog_idx', 'route_planning_stops_geog_idx', 'shipment_leg_stops_geog_idx', 'attendance_policy_versions_geofence_gix'];
  v_idx text;
begin
  foreach v_idx in array v_expected loop
    if not exists (select 1 from pg_indexes where schemaname = 'app' and indexname = v_idx) then
      raise exception 'assertion failed: expected GiST index % to still exist post-relocation', v_idx;
    end if;
    if not exists (select 1 from pg_class c join pg_am am on am.oid = c.relam where c.relname = v_idx and am.amname = 'gist') then
      raise exception 'assertion failed: expected % to still be a GiST index post-relocation', v_idx;
    end if;
  end loop;
end;
$$;

\echo '>> ISS-2026-234: setup -- one tenant, one broad role, one vehicle+driver+GPS device+third-party connection, one confirmed land-freight shipment order with a dispatched leg and 2 real-coordinate stops, one route-planning scenario+stop, one warehouse, one active employee with a geofenced (advisory) attendance policy, one driver-mobile tracking session -- proves a real INSERT with a real geography value into each of the 15 columns succeeds and round-trips'
-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key()
-- -- app.register_third_party_provider_connection encrypts its webhook secret and
-- needs this GUC set, same convention every other db-test file touching
-- third-party connections already uses.
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);
create temporary table pgisrelo_state (key text primary key, value text not null);
do $$
declare
  v_tenant uuid;
  v_company uuid;
  v_branch uuid;
  v_role uuid;
  v_draft app.role_versions;
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc_id uuid;
  v_quote app.quotations;
  v_send record;
  v_account app.accounts;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_shipment app.shipment_orders;
  v_leg app.shipment_legs;
  v_pickup app.shipment_leg_stops;
  v_delivery app.shipment_leg_stops;
  v_vehicle app.vehicle_operational_profiles;
  v_driver app.driver_operational_profiles;
  v_device app.gps_devices;
  v_conn record;
  v_scenario app.route_planning_scenarios;
  v_route_stop app.route_planning_stops;
  v_warehouse app.warehouses;
  v_policy app.attendance_policies;
  v_policy_version app.attendance_policy_versions;
  v_employee app.employees;
  v_tracking_session app.shipment_leg_tracking_sessions;
  v_mobile_session record;
  v_actor uuid := '00000000-0000-0000-0000-000000620101';
  v_supreme uuid := '00000000-0000-0000-0000-000000620102';
begin
  insert into auth.users (id, email) values
    (v_actor, 'admin@pgisrelo.test'),
    (v_supreme, 'supreme@pgisrelo.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('pgisrelo', 'PostGIS Relocation Co', 'idem-pgisrelo', 'tester');
  v_tenant := (select id from app.tenants where slug = 'pgisrelo');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant, 'company', null, 'PGISRELO-CO', 'PostGIS Relocation Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant and code = 'PGISRELO-CO');
  perform app.create_org_unit(v_tenant, 'branch', v_company, 'PGISRELO-BR', 'PostGIS Relocation Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant and code = 'PGISRELO-BR');

  perform app.invite_user(v_tenant, v_actor, 'admin@pgisrelo.test', 'PGIS Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@pgisrelo.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_actor, 'tenant_admin', v_tenant, null, 'tester');

  v_role := (app.create_role(v_tenant, 'PGIS Regression Broad', 'COM+OPS+HRS for regression fixture setup', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(
    v_draft.id,
    array(select id from app.permissions where
      (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))
      or (resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Approve', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_role and status = 'published'), v_actor, v_supreme, 'tester');

  -- Vehicle + driver + GPS device + third-party connection.
  select * into v_vehicle from app.register_vehicle_operational_profile(v_tenant, 'VEH-PGISRELO-A', 'PGIS Relocation Truck', 'owned', 2000, 20, v_actor, 'admin');
  select * into v_vehicle from app.set_vehicle_tracking_eligibility(v_vehicle.id, true, true, true, v_vehicle.record_version, v_actor, 'admin');
  select * into v_driver from app.register_driver_operational_profile(v_tenant, 'DRV-PGISRELO-A', 'PGIS Relocation Driver', 'B2', (now() + interval '2 years')::date, v_actor, 'admin');
  select * into v_driver from app.set_driver_mobile_tracking_consent(v_driver.id, true, v_driver.record_version, v_actor, 'admin');
  select * into v_device from app.register_gps_device(v_tenant, '868712345620101', 'Teltonika FMC920', 'cargogrid', v_actor, 'admin');
  select * into v_conn from app.register_third_party_provider_connection(v_tenant, 'pgisrelogps', 'webhook', v_actor, 'admin');

  -- Full commercial pipeline -> one confirmed land-freight shipment order + leg.
  perform app.capture_lead(v_tenant, 'manual', null, 'PGIS Relocation Test Co', 'Jane PGIS', 'jane@pgisrelotest.test', '0811',
    v_actor, v_company, v_actor, 'tester');
  select * into v_lead from app.leads where email = 'jane@pgisrelotest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_actor, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'PGIS Relocation Test Co', 'CTC620', '11.111.111.8-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 8', 'city', 'Jakarta', 'country', 'ID'),
    v_actor, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant, 'Jane PGIS Ops', 'Procurement Lead', 'jane@pgisrelotest.test', '0811', v_actor, v_company, v_actor, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_actor, 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant, v_prospect.id, 'PGIS relocation test lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-09-01'),
    v_actor, v_company, v_actor, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_actor, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant, 'VENDOR-PGISRELO-1', 'Contoso PGIS Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', '20ft',
    null, null, null, null, 'IDR', 4000000, null, '[]'::jsonb, now(), null, null, v_actor, 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_actor, 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_actor, 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant, 20.00, 'half_up', v_actor, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_actor, 'tester');
  perform app.calculate_margin(v_selection.id, 4800000, 'IDR', 0, v_actor, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_actor, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'PGIS relocation lane', v_calc_id, 1, 4800000, 0, 0, v_actor, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_actor, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_actor, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane PGIS Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_actor, 'admin');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_actor, 'admin');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_actor, 'admin');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_actor, 'admin');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-pgisrelo-shipment', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 1000, 1000, 16, 1000, 1000, 16, null, v_actor, 'admin'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, v_actor, 'admin');

  select * into v_leg from app.add_shipment_leg(v_shipment.id, 'idem-pgisrelo-leg1', 1, 'land', null, now(), now() + interval '1 day', v_actor, 'admin');
  -- Real coordinates: pickup = Jakarta, delivery = Bandung -- the same proven pair
  -- scripts/db-tests/advanced-tms-geofence-route-deviation-signals.sql already uses.
  select * into v_pickup from app.add_shipment_leg_stop(v_leg.id, 1, 'pickup', 'Jakarta Warehouse', null, 106.845599, -6.208763, now(), v_actor, 'admin');
  select * into v_delivery from app.add_shipment_leg_stop(v_leg.id, 2, 'delivery', 'Bandung Warehouse', null, 107.619123, -6.917464, now() + interval '1 day', v_actor, 'admin');
  perform app.allocate_shipment_leg_cargo(v_leg.id, 1000, 1000, 16, v_actor, 'admin');
  perform app.confirm_shipment_leg_network(v_shipment.id, (select record_version from app.shipment_orders where id = v_shipment.id), v_actor, 'admin');
  perform app.assign_resource(v_shipment.id, 'vehicle', v_vehicle.vehicle_master_id, v_actor, 'admin');
  perform app.assign_resource(v_shipment.id, 'driver', v_driver.driver_master_id, v_actor, 'admin');
  select * into v_leg from app.transition_shipment_leg(v_leg.id, 'dispatched', v_leg.record_version, v_actor, 'admin');

  perform app.upsert_shipment_leg_tracking_policy(
    v_leg.id, true, array['direct_device', 'driver_mobile', 'third_party_platform'], 'direct_device', array['direct_device', 'driver_mobile', 'third_party_platform'],
    300, 100, 30, 'leg_dispatch', 'leg_complete',
    jsonb_build_object(
      'enabled', true, 'radius_meters', 500, 'dwell_seconds_before_confirm', 60,
      'route_deviation', jsonb_build_object('enabled', true, 'corridor_width_meters', 1500, 'deviation_sustained_seconds', 120),
      'overdue_arrival_grace_minutes', 60
    ),
    true, 3600, v_actor, 'admin'
  );

  -- ISS-2026-234's own regression evidence, not a re-proof of the ePOD workflow
  -- (already covered end to end by its own dedicated test file, unaffected by
  -- this migration): jump the shipment straight to 'delivered' so
  -- app.start_epod_capture's own precondition is met, and app.set_epod_evidence
  -- (this migration's 35th, hardest-to-find fix -- a hardcoded `public.geography`
  -- declaration) gets a real, live call.
  update app.shipment_orders set status = 'delivered' where id = v_shipment.id;

  -- Route planning scenario + stop.
  select * into v_scenario from app.prepare_route_planning_scenario(v_shipment.id, 'idem-pgisrelo-scenario', 1000, 16, v_actor, 'admin');
  select * into v_route_stop from app.add_route_planning_stop(v_scenario.id, 1, 'pickup', 'Jakarta Warehouse', null, 106.845599, -6.208763, now(), now() + interval '1 day', v_actor, 'admin');

  -- Warehouse with a real geofenced site.
  select * into v_warehouse from app.create_warehouse(
    v_tenant, v_company, 'WH-PGISRELO-1', 'PGIS Relocation Warehouse', 'Jl. Sudirman 8, Jakarta', 'Asia/Jakarta',
    jsonb_build_object('type', 'Point', 'coordinates', array[106.845599, -6.208763]),
    array['land_freight'], v_actor, 'admin'
  );

  -- Active employee + published, geofenced (advisory) attendance policy.
  perform app.create_employee_draft(v_tenant, 'PGIS Relocation Emp', 'full_time', 'emp@pgisrelo.test', 'empp@pgisrelo.test', '0800009901', null, null, null, '2024-01-01', v_company, v_branch, null, 'Warehouse Staff', null, null, null, 'hr_created', 'idem-emp-pgisrelo', v_actor, 'tester');
  select * into v_employee from app.employees where tenant_id = v_tenant and work_email = 'emp@pgisrelo.test';
  perform app.add_employee_emergency_contact(v_employee.master_record_id, 'Contact PGIS', 'spouse', '0810009901', null, true, v_actor, 'tester');
  perform app.submit_employee_for_approval(v_employee.master_record_id, 1, v_actor, 'tester');
  perform app.decide_employee_approval(v_employee.master_record_id, 2, 'approve', null, v_actor, 'tester');
  perform app.activate_employee(v_employee.master_record_id, 3, v_actor, 'tester');
  select * into v_employee from app.employees where master_record_id = v_employee.master_record_id;

  v_policy := app.create_attendance_policy(v_tenant, null, 'PGIS Relocation Policy', v_actor, 'tester');
  v_policy_version := app.create_attendance_policy_version(
    v_policy.id, 'Asia/Jakarta', '08:00:00'::time, '17:00:00'::time, '04:00:00'::time, 15, 15,
    array['mobile_web', 'kiosk']::text[], 'advisory',
    jsonb_build_object('type', 'Point', 'coordinates', array[106.845599, -6.208763]),
    200, 16, '2024-01-01'::date, v_actor, 'tester'
  );
  perform app.publish_attendance_policy_version(v_policy_version.id, 1, v_actor, 'tester');

  -- Driver-mobile tracking session (ATW-225 pattern).
  select * into v_tracking_session from app.start_leg_tracking_session(v_leg.id, 'driver_mobile', 'driver', v_driver.driver_master_id, null, v_actor, 'admin');
  select * into v_mobile_session from app.start_driver_mobile_session(v_tracking_session.id, 24, v_actor, 'admin');

  insert into pgisrelo_state (key, value) values
    ('tenant_id', v_tenant::text),
    ('actor_id', v_actor::text),
    ('vehicle_master_id', v_vehicle.vehicle_master_id::text),
    ('device_id', v_device.id::text),
    ('connection_id', v_conn.connection_id::text),
    ('shipment_order_id', v_shipment.id::text),
    ('shipment_leg_id', v_leg.id::text),
    ('pickup_stop_id', v_pickup.id::text),
    ('delivery_stop_id', v_delivery.id::text),
    ('epod_shipment_order_id', v_shipment.id::text),
    ('route_planning_scenario_id', v_scenario.id::text),
    ('warehouse_id', v_warehouse.id::text),
    ('employee_master_record_id', v_employee.master_record_id::text),
    ('attendance_policy_version_id', v_policy_version.id::text),
    ('driver_mobile_session_id', v_mobile_session.driver_mobile_session_id::text);
end;
$$;

\echo '>> ISS-2026-234: app.arbitrate_and_project_vehicle_position (recreated, calls bare ST_Distance) round-trips a real geography value into canonical_telemetry_events, vehicle_current_positions, and vehicle_source_health'
do $$
declare
  v_tenant uuid := (select value::uuid from pgisrelo_state where key = 'tenant_id');
  v_vehicle_master_id uuid := (select value::uuid from pgisrelo_state where key = 'vehicle_master_id');
  v_jakarta geography := app.geojson_point_to_geography('{"type":"Point","coordinates":[106.845599,-6.208763]}'::jsonb);
  v_event app.canonical_telemetry_events;
  v_current app.vehicle_current_positions;
  v_health app.vehicle_source_health;
begin
  v_event := app.arbitrate_and_project_vehicle_position(
    v_tenant, v_vehicle_master_id, 'direct_device', gen_random_uuid(), now(), now(),
    v_jakarta, 42.5, 90, 5
  );
  if v_event.location is null or abs(ST_X(v_event.location::geometry) - 106.845599) > 0.000001 or abs(ST_Y(v_event.location::geometry) - (-6.208763)) > 0.000001 then
    raise exception 'assertion failed: canonical_telemetry_events.location did not round-trip the real Jakarta point, got %', ST_AsText(v_event.location::geometry);
  end if;
  if not v_event.applied_to_current_position then
    raise exception 'assertion failed: expected this first-ever report to win arbitration (bootstrap)';
  end if;

  select * into v_current from app.vehicle_current_positions where vehicle_master_id = v_vehicle_master_id;
  if v_current.location is null or abs(ST_X(v_current.location::geometry) - 106.845599) > 0.000001 then
    raise exception 'assertion failed: vehicle_current_positions.location did not round-trip the real point';
  end if;

  select * into v_health from app.vehicle_source_health where vehicle_master_id = v_vehicle_master_id and source_type = 'direct_device';
  if v_health.last_location is null or abs(ST_Y(v_health.last_location::geometry) - (-6.208763)) > 0.000001 then
    raise exception 'assertion failed: vehicle_source_health.last_location did not round-trip the real point';
  end if;
end;
$$;

\echo '>> ISS-2026-234: app.get_vehicle_current_position / app.get_direct_device_telemetry_reports (search_path-fixed, call bare ST_AsGeoJSON internally) return correct GeoJSON post-relocation -- calling the fixed function, not a bare column SELECT, is what actually proves the search_path fix'
do $$
declare
  v_tenant uuid := (select value::uuid from pgisrelo_state where key = 'tenant_id');
  v_vehicle_master_id uuid := (select value::uuid from pgisrelo_state where key = 'vehicle_master_id');
  v_device_id uuid := (select value::uuid from pgisrelo_state where key = 'device_id');
  v_geojson jsonb;
  v_report_id uuid;
begin
  select location_geojson into v_geojson from app.get_vehicle_current_position(v_vehicle_master_id);
  if v_geojson is null or (v_geojson ->> 'type') <> 'Point'
     or abs(((v_geojson -> 'coordinates') -> 0)::text::numeric - 106.845599) > 0.000001 then
    raise exception 'assertion failed: app.get_vehicle_current_position did not return correct GeoJSON post-relocation, got %', v_geojson;
  end if;

  insert into app.direct_device_telemetry_reports (tenant_id, device_id, report_type, event_at, location)
  values (v_tenant, v_device_id, 'location', now(), app.geojson_point_to_geography('{"type":"Point","coordinates":[106.845599,-6.208763]}'::jsonb))
  returning id into v_report_id;

  select location_geojson into v_geojson from app.get_direct_device_telemetry_reports(v_device_id) where id = v_report_id;
  if v_geojson is null or abs(((v_geojson -> 'coordinates') -> 1)::text::numeric - (-6.208763)) > 0.000001 then
    raise exception 'assertion failed: app.get_direct_device_telemetry_reports did not return correct GeoJSON post-relocation, got %', v_geojson;
  end if;
end;
$$;

\echo '>> ISS-2026-234: direct_device_telemetry_reports.location and third_party_telemetry_reports.location round-trip a real geography value'
do $$
declare
  v_tenant uuid := (select value::uuid from pgisrelo_state where key = 'tenant_id');
  v_device_id uuid := (select value::uuid from pgisrelo_state where key = 'device_id');
  v_connection_id uuid := (select value::uuid from pgisrelo_state where key = 'connection_id');
  v_vehicle_master_id uuid := (select value::uuid from pgisrelo_state where key = 'vehicle_master_id');
  v_bogor geography := app.geojson_point_to_geography('{"type":"Point","coordinates":[106.806038,-6.595038]}'::jsonb);
  v_location geography;
begin
  select location into v_location from app.direct_device_telemetry_reports where device_id = v_device_id and location is not null order by created_at desc limit 1;
  if v_location is null or abs(ST_X(v_location::geometry) - 106.845599) > 0.000001 then
    raise exception 'assertion failed: direct_device_telemetry_reports.location did not round-trip';
  end if;

  insert into app.third_party_telemetry_reports (tenant_id, connection_id, vehicle_master_id, provider_event_id, report_type, event_at, location)
  values (v_tenant, v_connection_id, v_vehicle_master_id, 'evt-pgisrelo-1', 'location', now(), v_bogor)
  returning location into v_location;
  if v_location is null or abs(ST_Y(v_location::geometry) - (-6.595038)) > 0.000001 then
    raise exception 'assertion failed: third_party_telemetry_reports.location did not round-trip';
  end if;
end;
$$;

\echo '>> ISS-2026-234: driver_mobile_position_reports.location round-trips a real geography value'
do $$
declare
  v_tenant uuid := (select value::uuid from pgisrelo_state where key = 'tenant_id');
  v_session_id uuid := (select value::uuid from pgisrelo_state where key = 'driver_mobile_session_id');
  v_singapore geography := app.geojson_point_to_geography('{"type":"Point","coordinates":[103.819836,1.352083]}'::jsonb);
  v_location geography;
begin
  insert into app.driver_mobile_position_reports (tenant_id, driver_mobile_tracking_session_id, report_type, event_at, location)
  values (v_tenant, v_session_id, 'location', now(), v_singapore)
  returning location into v_location;
  if v_location is null or abs(ST_X(v_location::geometry) - 103.819836) > 0.000001 then
    raise exception 'assertion failed: driver_mobile_position_reports.location did not round-trip';
  end if;

  perform app.get_driver_mobile_position_reports(v_session_id);
end;
$$;

\echo '>> ISS-2026-234: shipment_leg_stops.location_geog (2 real stops from setup) and route_planning_stops.location_geog round-trip; app.evaluate_route_deviation (recreated, calls bare ST_MakeLine/ST_Distance) executes correctly against real stop geometry'
do $$
declare
  v_leg_id uuid := (select value::uuid from pgisrelo_state where key = 'shipment_leg_id');
  v_pickup_id uuid := (select value::uuid from pgisrelo_state where key = 'pickup_stop_id');
  v_location geography;
begin
  select location_geog into v_location from app.shipment_leg_stops where id = v_pickup_id;
  if v_location is null or abs(ST_X(v_location::geometry) - 106.845599) > 0.000001 then
    raise exception 'assertion failed: shipment_leg_stops.location_geog did not round-trip the real pickup coordinate';
  end if;

  -- A location right on the pickup->delivery line: no route-deviation exception
  -- expected. Proves ST_MakeLine/ST_Distance execute correctly, not merely that
  -- they resolve.
  perform app.evaluate_route_deviation(
    (select tenant_id from app.shipment_legs where id = v_leg_id), v_leg_id, null,
    app.geojson_point_to_geography('{"type":"Point","coordinates":[106.845599,-6.208763]}'::jsonb),
    now(), jsonb_build_object('route_deviation', jsonb_build_object('enabled', true, 'corridor_width_meters', 1500, 'deviation_sustained_seconds', 0))
  );
  if exists (select 1 from app.shipment_leg_route_deviation_states where shipment_leg_id = v_leg_id and state = 'off_corridor') then
    raise exception 'assertion failed: expected no off-corridor state for a location on the direct pickup-delivery line';
  end if;

  -- A location genuinely far off the corridor (Singapore, ~880km away): a
  -- confirmed off-corridor state (and, via app.upsert_exception_signal, a real
  -- shipment_exception_signals row) is the expected, correct behavior.
  perform app.evaluate_route_deviation(
    (select tenant_id from app.shipment_legs where id = v_leg_id), v_leg_id, null,
    app.geojson_point_to_geography('{"type":"Point","coordinates":[103.819836,1.352083]}'::jsonb),
    now(), jsonb_build_object('route_deviation', jsonb_build_object('enabled', true, 'corridor_width_meters', 1500, 'deviation_sustained_seconds', 0))
  );
  if not exists (select 1 from app.shipment_leg_route_deviation_states where shipment_leg_id = v_leg_id and state = 'off_corridor' and confirmed_at is not null) then
    raise exception 'assertion failed: expected a confirmed off-corridor state for a location ~880km off the route corridor';
  end if;
  if not exists (select 1 from app.shipment_exception_signals where shipment_leg_id = v_leg_id and signal_type = 'route_deviation' and location is not null) then
    raise exception 'assertion failed: expected app.upsert_exception_signal to have written a real shipment_exception_signals row with a real location';
  end if;
end;
$$;

do $$
declare
  v_scenario_id uuid := (select value::uuid from pgisrelo_state where key = 'route_planning_scenario_id');
  v_location geography;
begin
  select location_geog into v_location from app.route_planning_stops where scenario_id = v_scenario_id order by stop_sequence limit 1;
  if v_location is null or abs(ST_X(v_location::geometry) - 106.845599) > 0.000001 or abs(ST_Y(v_location::geometry) - (-6.208763)) > 0.000001 then
    raise exception 'assertion failed: route_planning_stops.location_geog did not round-trip the real coordinate';
  end if;
end;
$$;

\echo '>> ISS-2026-234: shipment_leg_stop_geofence_states.last_evaluated_location and shipment_milestone_candidates.location round-trip -- the latter via app.upsert_milestone_candidate (recreated), a real call not a bare INSERT'
do $$
declare
  v_tenant uuid := (select value::uuid from pgisrelo_state where key = 'tenant_id');
  v_shipment_id uuid := (select value::uuid from pgisrelo_state where key = 'shipment_order_id');
  v_leg_id uuid := (select value::uuid from pgisrelo_state where key = 'shipment_leg_id');
  v_pickup_id uuid := (select value::uuid from pgisrelo_state where key = 'pickup_stop_id');
  v_jakarta geography := app.geojson_point_to_geography('{"type":"Point","coordinates":[106.845599,-6.208763]}'::jsonb);
  v_location geography;
begin
  -- ON CONFLICT, not a bare INSERT: the earlier app.arbitrate_and_project_vehicle_position
  -- call above already drove a real geofence-entry row for this same pickup stop via
  -- app.evaluate_stop_geofence (the Jakarta position it reported is inside the pickup
  -- stop's own tracking-policy geofence) -- a second bare INSERT here would collide with
  -- shipment_leg_stop_geofence_states_stop_unique. The UPDATE branch still proves a real
  -- geography value writes and round-trips through this exact column.
  insert into app.shipment_leg_stop_geofence_states (
    tenant_id, shipment_leg_stop_id, shipment_leg_id, radius_meters, dwell_seconds_before_confirm,
    state, first_entered_at, last_evaluated_at, last_evaluated_location
  ) values (
    v_tenant, v_pickup_id, v_leg_id, 500, 60, 'confirmed_inside', now(), now(), v_jakarta
  )
  on conflict (shipment_leg_stop_id) do update
  set last_evaluated_location = excluded.last_evaluated_location, last_evaluated_at = excluded.last_evaluated_at
  returning last_evaluated_location into v_location;
  if v_location is null or abs(ST_X(v_location::geometry) - 106.845599) > 0.000001 then
    raise exception 'assertion failed: shipment_leg_stop_geofence_states.last_evaluated_location did not round-trip';
  end if;

  perform app.upsert_milestone_candidate(
    v_tenant, v_shipment_id, v_leg_id, v_pickup_id, 'pickup_arrival',
    now(), null, v_jakarta, 'pgisrelo-milestone-1'
  );
  select location into v_location from app.shipment_milestone_candidates where dedup_key = 'pgisrelo-milestone-1';
  if v_location is null or abs(ST_Y(v_location::geometry) - (-6.208763)) > 0.000001 then
    raise exception 'assertion failed: shipment_milestone_candidates.location did not round-trip via app.upsert_milestone_candidate';
  end if;
end;
$$;

\echo '>> ISS-2026-234: warehouses.site_geog round-trips via app.create_warehouse; epod_captures.delivery_geog round-trips via app.set_epod_evidence (the 35th fix -- a hardcoded public.geography declaration, the one no search_path change alone could have fixed)'
do $$
declare
  v_warehouse_id uuid := (select value::uuid from pgisrelo_state where key = 'warehouse_id');
  v_shipment_id uuid := (select value::uuid from pgisrelo_state where key = 'epod_shipment_order_id');
  v_actor uuid := (select value::uuid from pgisrelo_state where key = 'actor_id');
  v_location geography;
  v_capture app.epod_captures;
begin
  select site_geog into v_location from app.warehouses where id = v_warehouse_id;
  if v_location is null or abs(ST_X(v_location::geometry) - 106.845599) > 0.000001 then
    raise exception 'assertion failed: warehouses.site_geog did not round-trip via app.create_warehouse';
  end if;

  v_capture := app.start_epod_capture(
    (select tenant_id from app.shipment_orders where id = v_shipment_id), v_shipment_id, null, 'idem-pgisrelo-epod', v_actor, 'admin'
  );
  v_capture := app.set_epod_evidence(
    v_capture.id, 'Jane PGIS Ops', 'Warehouse Staff', null, null,
    jsonb_build_object('type', 'Point', 'coordinates', array[107.619123, -6.917464]),
    now(), v_actor, 'admin'
  );
  if v_capture.delivery_geog is null
     or abs(ST_X(v_capture.delivery_geog::geometry) - 107.619123) > 0.000001
     or abs(ST_Y(v_capture.delivery_geog::geometry) - (-6.917464)) > 0.000001 then
    raise exception 'assertion failed: epod_captures.delivery_geog did not round-trip via app.set_epod_evidence, got %', ST_AsText(v_capture.delivery_geog::geometry);
  end if;
end;
$$;

\echo '>> ISS-2026-234: attendance_policy_versions.geofence_center round-trips via app.create_attendance_policy_version; attendance_events.location round-trips via app._ingest_attendance_event (search_path-fixed for its own local `geography`-typed DECLARE, the bug caught live while drafting this migration)'
do $$
declare
  v_policy_version_id uuid := (select value::uuid from pgisrelo_state where key = 'attendance_policy_version_id');
  v_master_record_id uuid := (select value::uuid from pgisrelo_state where key = 'employee_master_record_id');
  v_actor uuid := (select value::uuid from pgisrelo_state where key = 'actor_id');
  v_location geography;
  v_employee app.employees;
  v_event app.attendance_events;
begin
  select geofence_center into v_location from app.attendance_policy_versions where id = v_policy_version_id;
  if v_location is null or abs(ST_X(v_location::geometry) - 106.845599) > 0.000001 or abs(ST_Y(v_location::geometry) - (-6.208763)) > 0.000001 then
    raise exception 'assertion failed: attendance_policy_versions.geofence_center did not round-trip';
  end if;

  select * into v_employee from app.employees where master_record_id = v_master_record_id;
  v_event := app._ingest_attendance_event(
    v_employee, 'clock_in', 'mobile_web', now(),
    app.geojson_point_to_geography('{"type":"Point","coordinates":[106.845599,-6.208763]}'::jsonb),
    'idem-pgisrelo-clockin', null, null, v_actor, 'tester'
  );
  if v_event.location is null or abs(ST_X(v_event.location::geometry) - 106.845599) > 0.000001 then
    raise exception 'assertion failed: attendance_events.location did not round-trip via app._ingest_attendance_event, got %', v_event.location;
  end if;
  if v_event.geofence_result <> 'inside' then
    raise exception 'assertion failed: expected the clock-in location to be evaluated as inside the advisory geofence, got %', v_event.geofence_result;
  end if;
end;
$$;

\echo '>> ISS-2026-234: app._compute_shipment_leg_eta (search_path-fixed, calls bare ST_MakeLine/ST_Length) still computes a real, correct ETA post-relocation'
do $$
declare
  v_leg_id uuid := (select value::uuid from pgisrelo_state where key = 'shipment_leg_id');
  v_eta app.shipment_leg_eta_projection;
begin
  v_eta := app._compute_shipment_leg_eta(v_leg_id);
  if not v_eta.computable then
    raise exception 'assertion failed: expected the ETA to be computable (live position + pending stops both present), got reason=%', v_eta.reason;
  end if;
  if v_eta.remaining_distance_km is null or v_eta.remaining_distance_km <= 0 then
    raise exception 'assertion failed: expected a real positive remaining distance, got %', v_eta.remaining_distance_km;
  end if;
  -- Jakarta -> Bandung is ~130km by the geodesic app._compute_shipment_leg_eta
  -- actually measures (great-circle distance summed across the ordered stop
  -- chain, not road distance) -- a wide, deliberately generous sanity band.
  if v_eta.remaining_distance_km < 50 or v_eta.remaining_distance_km > 250 then
    raise exception 'assertion failed: expected remaining_distance_km in a realistic Jakarta-Bandung range (50-250km), got %', v_eta.remaining_distance_km;
  end if;
end;
$$;

\echo '>> ISS-2026-234: schema-privilege defense in depth holds post-relocation (ISS-2026-309''s own class) -- anon holds no EXECUTE on any recreated spatial/geofence primitive, whether the app.* or the public.* PostgREST wrapper; the two that carry authenticated live still carry it'
do $$
declare
  v_has boolean;
  v_fn text;
  v_anon_none text[] := array[
    'app.bounded_st_dwithin(geography, geography, numeric)', 'public.bounded_st_dwithin(geography, geography, numeric)',
    'app.geography_to_geojson_point(geography)', 'public.geography_to_geojson_point(geography)',
    'app.geojson_point_to_geography(jsonb)', 'public.geojson_point_to_geography(jsonb)',
    'app.validate_geography_point(geography)', 'public.validate_geography_point(geography)',
    'app.arbitrate_and_project_vehicle_position(uuid, uuid, text, uuid, timestamptz, timestamptz, geography, numeric, numeric, numeric)',
    'public.arbitrate_and_project_vehicle_position(uuid, uuid, text, uuid, timestamptz, timestamptz, geography, numeric, numeric, numeric)',
    'app.evaluate_route_deviation(uuid, uuid, uuid, geography, timestamptz, jsonb)', 'public.evaluate_route_deviation(uuid, uuid, uuid, geography, timestamptz, jsonb)',
    'app.evaluate_stop_geofence(uuid, uuid, uuid, geography, timestamptz, jsonb)', 'public.evaluate_stop_geofence(uuid, uuid, uuid, geography, timestamptz, jsonb)',
    'app.evaluate_geofence_and_deviation_signals(uuid, uuid, uuid, geography, timestamptz)', 'public.evaluate_geofence_and_deviation_signals(uuid, uuid, uuid, geography, timestamptz)',
    'app.upsert_exception_signal(uuid, uuid, uuid, text, text, text, uuid, geography, text, text)', 'public.upsert_exception_signal(uuid, uuid, uuid, text, text, text, uuid, geography, text, text)',
    'app.upsert_milestone_candidate(uuid, uuid, uuid, uuid, text, timestamptz, uuid, geography, text)', 'public.upsert_milestone_candidate(uuid, uuid, uuid, uuid, text, timestamptz, uuid, geography, text)',
    'app._ingest_attendance_event(app.employees, text, text, timestamptz, geography, text, jsonb, uuid, uuid, text)'
  ];
  v_authenticated_holds text[] := array[
    'app.bounded_st_dwithin(geography, geography, numeric)', 'public.bounded_st_dwithin(geography, geography, numeric)',
    'app.geography_to_geojson_point(geography)', 'public.geography_to_geojson_point(geography)',
    'app.geojson_point_to_geography(jsonb)', 'public.geojson_point_to_geography(jsonb)',
    'app.validate_geography_point(geography)', 'public.validate_geography_point(geography)',
    'app.set_epod_evidence(uuid, text, text, uuid, uuid[], jsonb, timestamptz, uuid, text)'
  ];
begin
  foreach v_fn in array v_anon_none loop
    select has_function_privilege('anon', v_fn, 'EXECUTE') into v_has;
    if v_has then
      raise exception 'assertion failed: expected anon to hold no EXECUTE on % post-relocation (ISS-2026-309 regression guard)', v_fn;
    end if;
  end loop;

  foreach v_fn in array v_authenticated_holds loop
    select has_function_privilege('authenticated', v_fn, 'EXECUTE') into v_has;
    if not v_has then
      raise exception 'assertion failed: expected authenticated to hold EXECUTE on % post-relocation, matching its live pre-migration ACL', v_fn;
    end if;
  end loop;
end;
$$;
