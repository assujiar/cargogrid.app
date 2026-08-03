import { test } from "node:test";
import assert from "node:assert/strict";
import {
  getVehicleCurrentPosition,
  listVehicleTelemetryHistory,
  listVehicleSourceHealth,
  listVehicleSourceSwitches,
  CanonicalTelemetryQueryError,
  type CanonicalTelemetryQueryClient,
} from "./canonical-telemetry.ts";

const VEHICLE_ID = "723e4567-e89b-12d3-a456-426614174001";
const TENANT_ID = "723e4567-e89b-12d3-a456-426614174002";

function fakeClient(response: { data: unknown; error: { message: string } | null }): CanonicalTelemetryQueryClient {
  return {
    rpc: async (_fn: string, _args: Record<string, unknown>) => response,
  } as unknown as CanonicalTelemetryQueryClient;
}

test("getVehicleCurrentPosition returns null when the vehicle has never had a canonical position applied", async () => {
  const client = fakeClient({ data: [], error: null });
  const result = await getVehicleCurrentPosition(client, VEHICLE_ID);
  assert.equal(result, null);
});

test("getVehicleCurrentPosition parses a real row", async () => {
  const client = fakeClient({
    data: [
      {
        vehicle_master_id: VEHICLE_ID,
        tenant_id: TENANT_ID,
        source_type: "driver_mobile",
        location_geojson: { type: "Point", coordinates: [106.8, -6.2] },
        speed_kmh: 40,
        heading_degrees: 90,
        event_at: "2026-08-03T00:00:00Z",
        received_at: "2026-08-03T00:00:01Z",
        updated_at: "2026-08-03T00:00:01Z",
      },
    ],
    error: null,
  });
  const result = await getVehicleCurrentPosition(client, VEHICLE_ID);
  assert.equal(result?.sourceType, "driver_mobile");
});

test("getVehicleCurrentPosition throws CanonicalTelemetryQueryError on an RPC error", async () => {
  const client = fakeClient({ data: null, error: { message: "boom" } });
  await assert.rejects(() => getVehicleCurrentPosition(client, VEHICLE_ID), CanonicalTelemetryQueryError);
});

test("listVehicleTelemetryHistory returns an empty array for null data", async () => {
  const client = fakeClient({ data: null, error: null });
  const result = await listVehicleTelemetryHistory(client, VEHICLE_ID);
  assert.deepEqual(result, []);
});

test("listVehicleTelemetryHistory maps every row through the parser", async () => {
  const client = fakeClient({
    data: [
      {
        id: "723e4567-e89b-12d3-a456-426614174003",
        tenant_id: TENANT_ID,
        vehicle_master_id: VEHICLE_ID,
        source_type: "direct_device",
        event_at: "2026-08-03T00:00:00Z",
        received_at: "2026-08-03T00:00:01Z",
        location_geojson: null,
        speed_kmh: null,
        heading_degrees: null,
        accuracy_meters: null,
        applied_to_current_position: false,
        rejection_reason: "stale_event_time",
      },
    ],
    error: null,
  });
  const result = await listVehicleTelemetryHistory(client, VEHICLE_ID);
  assert.equal(result.length, 1);
  assert.equal(result[0]?.rejectionReason, "stale_event_time");
});

test("listVehicleSourceHealth maps every row through the parser", async () => {
  const client = fakeClient({ data: [{ source_type: "direct_device", last_seen_event_at: "2026-08-03T00:00:00Z", last_seen_received_at: "2026-08-03T00:00:01Z", status: "healthy" }], error: null });
  const result = await listVehicleSourceHealth(client, TENANT_ID, VEHICLE_ID);
  assert.equal(result[0]?.status, "healthy");
});

test("listVehicleSourceSwitches maps every row through the parser", async () => {
  const client = fakeClient({
    data: [
      {
        id: "723e4567-e89b-12d3-a456-426614174003",
        tenant_id: TENANT_ID,
        vehicle_master_id: VEHICLE_ID,
        from_source_type: null,
        to_source_type: "direct_device",
        reason: "bootstrap",
        canonical_telemetry_event_id: "723e4567-e89b-12d3-a456-426614174003",
        evidence: {},
        switched_at: "2026-08-03T00:00:00Z",
      },
    ],
    error: null,
  });
  const result = await listVehicleSourceSwitches(client, VEHICLE_ID);
  assert.equal(result[0]?.reason, "bootstrap");
});
