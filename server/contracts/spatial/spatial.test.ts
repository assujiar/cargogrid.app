import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  GeoJSONPointSchema,
  BoundedRadiusMetersSchema,
  POSTGIS_MAX_QUERY_RADIUS_METERS,
  toGeoJSONPoint,
  fromGeoJSONPoint,
} from "./spatial.ts";

describe("GeoJSONPointSchema", () => {
  test("accepts a well-formed point (Jakarta)", () => {
    const parsed = GeoJSONPointSchema.parse({ type: "Point", coordinates: [106.845599, -6.208763] });
    assert.deepEqual(parsed.coordinates, [106.845599, -6.208763]);
  });

  test("accepts equator/antimeridian/pole boundary values", () => {
    for (const coordinates of [
      [0, 0],
      [180, 0],
      [-180, 0],
      [0, 90],
      [0, -90],
    ] as const) {
      assert.doesNotThrow(() => GeoJSONPointSchema.parse({ type: "Point", coordinates }));
    }
  });

  test("rejects a non-Point type", () => {
    assert.throws(() => GeoJSONPointSchema.parse({ type: "LineString", coordinates: [0, 0] }));
  });

  test("rejects an out-of-range longitude, not silently clamping it", () => {
    assert.throws(() => GeoJSONPointSchema.parse({ type: "Point", coordinates: [181, 0] }));
  });

  test("rejects an out-of-range latitude, not silently clamping it", () => {
    assert.throws(() => GeoJSONPointSchema.parse({ type: "Point", coordinates: [0, 95] }));
  });

  test("rejects a 3-element coordinates array", () => {
    assert.throws(() => GeoJSONPointSchema.parse({ type: "Point", coordinates: [0, 0, 0] }));
  });
});

describe("BoundedRadiusMetersSchema", () => {
  test("accepts a radius within the governed cap", () => {
    assert.equal(BoundedRadiusMetersSchema.parse(100000), 100000);
  });

  test("rejects a radius exceeding the governed cap", () => {
    assert.throws(() => BoundedRadiusMetersSchema.parse(POSTGIS_MAX_QUERY_RADIUS_METERS + 1));
  });

  test("rejects a zero or negative radius", () => {
    assert.throws(() => BoundedRadiusMetersSchema.parse(0));
    assert.throws(() => BoundedRadiusMetersSchema.parse(-5));
  });
});

describe("toGeoJSONPoint / fromGeoJSONPoint", () => {
  test("round-trips longitude/latitude through a GeoJSON Point", () => {
    const point = toGeoJSONPoint(106.845599, -6.208763);
    const { longitude, latitude } = fromGeoJSONPoint(point);
    assert.equal(longitude, 106.845599);
    assert.equal(latitude, -6.208763);
  });

  test("throws rather than clamping an out-of-range latitude", () => {
    assert.throws(() => toGeoJSONPoint(0, 95));
  });
});
