/**
 * Spatial (PostGIS) contract (PLT-134, CG-S6-PLT-031, `ADR-0014`). Mirrors
 * supabase/migrations/20260722090000_enable_postgis_spatial_foundation.sql's
 * governed GeoJSON Point conventions: RFC 7946 axis order (`[longitude, latitude]`),
 * SRID 4326 (WGS84, structural to the database's `geography` type, not a separate
 * check here), and the 500,000-meter (500km) bounded-radius query cap.
 *
 * This module is validation-only, no RPC wrapper — the migration's own functions
 * (`app.geojson_point_to_geography`/`app.geography_to_geojson_point`/
 * `app.bounded_st_dwithin`) have no privileged mutation to wrap; a future domain
 * capability that adds a real `geography` column calls those directly and can reuse
 * `GeoJSONPointSchema` here for its own request-body validation. Client-side
 * pre-validation only — the database function is always the authoritative boundary
 * (Prompt 134 §25: "Validate server and database boundaries").
 */

import { z } from "zod";

/** `ADR-0014` — mirrors `app.postgis_max_query_radius_meters()`. Client-side fail-fast only; the database function is authoritative. */
export const POSTGIS_MAX_QUERY_RADIUS_METERS = 500000;

const LongitudeSchema = z.number().min(-180).max(180);
const LatitudeSchema = z.number().min(-90).max(90);

/** RFC 7946 axis order: `[longitude, latitude]`, matching PostGIS's own `ST_MakePoint(x, y)` convention — no axis translation happens anywhere between this schema and the database. */
export const GeoJSONCoordinatesSchema = z.tuple([LongitudeSchema, LatitudeSchema]);
export type GeoJSONCoordinates = z.infer<typeof GeoJSONCoordinatesSchema>;

export const GeoJSONPointSchema = z.object({
  type: z.literal("Point"),
  coordinates: GeoJSONCoordinatesSchema,
});
export type GeoJSONPoint = z.infer<typeof GeoJSONPointSchema>;

export const BoundedRadiusMetersSchema = z
  .number()
  .positive()
  .max(POSTGIS_MAX_QUERY_RADIUS_METERS, `radius_meters must not exceed the governed maximum of ${POSTGIS_MAX_QUERY_RADIUS_METERS}m (ADR-0014)`);

/** Longitude/latitude as named fields (a common request-body shape) -> a validated GeoJSON Point. Throws a ZodError on an out-of-range or non-finite value — never silently clamps, mirroring `app.geojson_point_to_geography`'s own explicit-rejection design. */
export function toGeoJSONPoint(longitude: number, latitude: number): GeoJSONPoint {
  return GeoJSONPointSchema.parse({ type: "Point", coordinates: [longitude, latitude] });
}

/** A validated GeoJSON Point -> `{ longitude, latitude }`, the inverse of `toGeoJSONPoint`. */
export function fromGeoJSONPoint(point: GeoJSONPoint): { longitude: number; latitude: number } {
  const [longitude, latitude] = point.coordinates;
  return { longitude, latitude };
}
