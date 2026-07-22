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
