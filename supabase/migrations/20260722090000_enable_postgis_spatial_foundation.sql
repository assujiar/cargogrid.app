-- Platform Core capability PLT-134 (PostGIS and Spatial Foundation, CG-S6-PLT-031)
-- Enables PostGIS from Platform Core (RPD-015, `01_MODULE_DEPENDENCY_MAP.md:60/119/237` --
-- "PostGIS is enabled from Platform Core, superseding Tech Arch OD-006's 'needed before
-- Advanced TMS' framing") and establishes the governed SRID/geometry-vs-geography/
-- validation/indexing/query-limit conventions every later phase's real spatial column
-- (`shipments`/`shipment_milestones`/`warehouses`, Operations/TMS/WMS, Phase 3+) will
-- build on. Ratifies `ADR-0014` (`ADR-CAND-ARCH-029`, newly minted -- no existing
-- candidate covered SRID/version/query-radius numeric defaults, confirmed via this
-- checkpoint's own research).
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * **No standalone spatial table is created here, structurally, not by omission.**
--   `docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md` §6/line 108 already resolved
--   this exact question: "spatial columns (`geography(Point)`/`geography(LineString)`)
--   added directly to `shipments`/`shipment_milestones`/`warehouses` rather than a
--   separate geo table, since location is an attribute of those entities, not a new
--   canonical entity." Those tables do not exist yet (Operations is Phase 3) -- this
--   migration's own deliverable is the extension plus the reusable validation/
--   serialization/query-limit helper functions a future Phase 3 migration will call
--   when it adds its own `geography` column, not a table of its own. The one
--   representative example Prompt 134 §20 task 3 asks for is proven entirely inside
--   `scripts/db-tests/postgis.sql` using a table created and dropped within that test
--   script alone -- never a permanent migration artifact -- the same "prove it in the
--   db-test, not in permanent schema" discipline `PLT-122`/`124`'s own headers applied,
--   taken one step further here since even a structural example table would contradict
--   `05_*.md`'s own "not a new canonical entity" ruling.
-- * **`geography`, not `geometry`, is the only spatial column type this convention
--   endorses** -- already resolved by `05_*.md` line 108 (quoted above), and confirmed
--   by this checkpoint's own direct testing to be the mechanism that makes SRID drift
--   structurally impossible: casting any geometry with a non-4326 SRID to `geography`
--   raises `Only lon/lat coordinate systems are supported in geography` (proven
--   directly against PostGIS 3.4.2 this checkpoint, not assumed from documentation).
--   Canonical SRID is therefore always `4326` (WGS84) by construction of the type
--   itself -- no separate SRID CHECK constraint is needed on a `geography` column.
-- * **A real, concrete defect class this checkpoint's own testing found and designed
--   around**: PostGIS's own `geometry -> geography` cast does **not** reject an
--   out-of-range latitude/longitude -- it silently *coerces* (clamps) the value into
--   `[-180 -90, 180 90]` (proven directly: `ST_MakePoint(0, 95)::geography` succeeds
--   with a `NOTICE`, not an error). Left unguarded, this is exactly the "silent axis
--   swap" Prompt 134 §19/§23 name as forbidden -- a caller accidentally swapping
--   longitude/latitude would get silently clamped data, not a rejection. This
--   migration's own `app.geojson_point_to_geography()` explicitly range-checks before
--   ever constructing a geography value, the real, tested mitigation, not a
--   documentation-only promise.
-- * **Axis order is GeoJSON's own (RFC 7946): `[longitude, latitude]`.** This matches
--   PostGIS's own `ST_MakePoint(x, y)` = `(longitude, latitude)` convention exactly, so
--   no axis translation ever happens between this migration's GeoJSON helpers and the
--   underlying `geography` value -- one convention, not two reconciled ones.
-- * **The bounded-radius query cap (`app.postgis_max_query_radius_meters()` = 500,000m
--   / 500km) is this checkpoint's own reasoned default**, the same "reasoned default
--   absent blueprint-mandated numbers" class `ADR-0002`/`ADR-0004`/`ADR-0011`/`ADR-0012`/
--   `ADR-0013` already used -- no architecture document names a specific radius limit.
--   500km comfortably covers any real intra-country logistics search (Indonesia's own
--   greatest linear extent is ~5,100km, so this is a per-query search-radius cap, not a
--   coverage-area limit) while structurally preventing the "no unbounded global spatial
--   scan" Prompt 134 §17/§23 forbid.
-- * **No privileged bulk-mutation function exists in this migration** (§18's own
--   "audit impact... where applicable" qualifier) -- every function below is a pure,
--   `stable` validator/serializer with no table to write to yet, so there is nothing to
--   self-audit here. A future migration that adds a real `geography` column to a real
--   tenant-scoped table inherits that table's own RLS/audit posture automatically (a new
--   column, not a new table), the same "mechanism proven, live wiring deferred" posture
--   `PLT-121`'s resolver and `PLT-106`'s entitlement evaluator already carry forward.
-- * **Precision/privacy classification (§16/§26 "sensitive locations masked by
--   policy")**: a future domain column storing a precise individual/customer location
--   is `pii`/`confidential` under the already-ratified
--   `docs/standards/DATA_CLASSIFICATION_STANDARDS.md`/`scripts/data-classification/registry.ts`
--   `pii` category (reused, not a new category invented here) -- disclosed as guidance
--   for that future migration to apply, since no concrete column exists yet to classify.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.

create extension if not exists postgis;

-- Single source of truth for the governed bounded-radius query cap (this migration's
-- own header). A `stable` function, not a bare constant, so any future caller can query
-- the live governed value rather than hard-coding it a second time.
create function app.postgis_max_query_radius_meters()
returns numeric
language sql
immutable
as $$
  select 500000::numeric;
$$;

comment on function app.postgis_max_query_radius_meters is
  'PLT-134: the governed maximum radius (meters) any bounded-radius spatial query may request -- ADR-0014. Enforced by app.bounded_st_dwithin(), not merely documented.';

-- Structural validity of a geography value intended to represent a single point --
-- non-null, a real Point (not a GeometryCollection/empty geometry), and geometrically
-- valid per PostGIS's own ST_IsValid. SRID is not re-checked here: the geography type
-- itself makes a non-4326 value impossible to construct (this migration's own header).
create function app.validate_geography_point(p_geog geography)
returns boolean
language sql
immutable
as $$
  select
    p_geog is not null
    and not ST_IsEmpty(p_geog::geometry)
    and GeometryType(p_geog::geometry) = 'POINT'
    and ST_IsValid(p_geog::geometry);
$$;

comment on function app.validate_geography_point is
  'PLT-134: structural point validity for a governed geography(Point,4326) column -- intended as a CHECK constraint on any future domain table''s own spatial column, e.g. `check (geog is null or app.validate_geography_point(geog))`.';

-- GeoJSON Point -> geography(Point,4326), with explicit, rejecting range validation
-- (this migration''s own header: PostGIS''s own cast silently clamps out-of-range
-- values, it does not reject them -- this function is the real mitigation).
create function app.geojson_point_to_geography(p_geojson jsonb)
returns geography
language plpgsql
immutable
as $$
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
$$;

comment on function app.geojson_point_to_geography is
  'PLT-134: the governed GeoJSON (RFC 7946, [longitude, latitude] axis order) -> geography(Point,4326) parser. Explicitly rejects an out-of-range or malformed input rather than relying on PostGIS''s own silently-clamping cast (this migration''s own header) -- the concrete "no silent axis swap" mechanism Prompt 134 §19/§23 require.';

-- geography(Point) -> GeoJSON, the inverse of app.geojson_point_to_geography -- proven
-- to round-trip within tolerance in scripts/db-tests/postgis.sql.
create function app.geography_to_geojson_point(p_geog geography)
returns jsonb
language sql
immutable
as $$
  select case when p_geog is null then null else ST_AsGeoJSON(p_geog)::jsonb end;
$$;

comment on function app.geography_to_geojson_point is
  'PLT-134: geography -> GeoJSON serialization (RFC 7946, [longitude, latitude] axis order, matching PostGIS''s own ST_MakePoint(x,y) convention -- no axis translation ever happens between this and app.geojson_point_to_geography).';

-- The one governed bounded-radius primitive -- every future distance/proximity query
-- (e.g. "warehouses within N meters of a shipment") must call this, never a bare
-- ST_DWithin, so the radius cap is structurally enforced in exactly one place.
create function app.bounded_st_dwithin(p_a geography, p_b geography, p_radius_meters numeric)
returns boolean
language plpgsql
stable
as $$
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
$$;

comment on function app.bounded_st_dwithin is
  'PLT-134: the governed bounded-radius proximity primitive (ADR-0014, max 500,000m) -- the concrete "no unbounded global spatial scan" mechanism Prompt 134 §17/§23 require. Intended for a future domain query''s WHERE clause, e.g. `where app.bounded_st_dwithin(w.location, :origin, :radius_meters)`, which a GiST index on the domain table''s own geography column (see this migration''s own header and scripts/db-tests/postgis.sql for the proven indexing pattern) makes selective, not a sequential scan.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.postgis_max_query_radius_meters() to authenticated, service_role;
grant execute on function app.validate_geography_point(geography) to authenticated, service_role;
grant execute on function app.geojson_point_to_geography(jsonb) to authenticated, service_role;
grant execute on function app.geography_to_geojson_point(geography) to authenticated, service_role;
grant execute on function app.bounded_st_dwithin(geography, geography, numeric) to authenticated, service_role;
