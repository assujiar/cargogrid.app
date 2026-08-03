import { test } from "node:test";
import assert from "node:assert/strict";
import {
  getTenantVehicleTrackingOverview,
  getTenantPendingMilestoneCandidates,
  getTenantPendingExceptionSignals,
  FleetControlTowerQueryError,
  type FleetControlTowerQueryRpcClient,
} from "./fleet-control-tower.ts";

const TENANT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174001";
const VEHICLE_ID = "723e4567-e89b-12d3-a456-426614174002";

function fakeClient(response: { data: unknown; error: { message: string } | null }): FleetControlTowerQueryRpcClient {
  return {
    rpc: async (_fn: string, _args: Record<string, unknown>) => response,
  } as unknown as FleetControlTowerQueryRpcClient;
}

test("getTenantVehicleTrackingOverview maps every row and returns an empty array for null data", async () => {
  const client = fakeClient({ data: null, error: null });
  const result = await getTenantVehicleTrackingOverview(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
  assert.deepEqual(result, []);
});

test("getTenantVehicleTrackingOverview maps a real row", async () => {
  const client = fakeClient({
    data: [
      {
        vehicle_master_id: VEHICLE_ID,
        vehicle_code: "VEH-A",
        vehicle_name: "Truck A",
        mobile_tracking_eligible: true,
        direct_device_tracking_eligible: true,
        third_party_tracking_eligible: false,
        current_source_type: "direct_device",
        current_location_geojson: { type: "Point", coordinates: [106.8456, -6.2088] },
        current_speed_kmh: 40,
        current_heading_degrees: 90,
        current_event_at: "2026-08-03T00:00:00Z",
        current_received_at: "2026-08-03T00:00:01Z",
      },
    ],
    error: null,
  });
  const result = await getTenantVehicleTrackingOverview(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
  assert.equal(result.length, 1);
  assert.equal(result[0]?.vehicleCode, "VEH-A");
});

test("getTenantVehicleTrackingOverview throws FleetControlTowerQueryError on an RPC error", async () => {
  const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:View" } });
  await assert.rejects(() => getTenantVehicleTrackingOverview(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }), FleetControlTowerQueryError);
});

test("getTenantPendingMilestoneCandidates maps every row and defaults limit to 50", async () => {
  const client = fakeClient({
    data: [
      {
        id: VEHICLE_ID,
        shipment_order_id: TENANT_ID,
        shipment_number: "SO-0001",
        shipment_leg_id: TENANT_ID,
        shipment_leg_stop_id: TENANT_ID,
        milestone_code: "pickup_arrival",
        candidate_event_time: "2026-08-03T00:00:00Z",
        detected_at: "2026-08-03T00:00:00Z",
        location_geojson: null,
      },
    ],
    error: null,
  });
  const result = await getTenantPendingMilestoneCandidates(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
  assert.equal(result.length, 1);
  assert.equal(result[0]?.milestoneCode, "pickup_arrival");
});

test("getTenantPendingExceptionSignals maps every row", async () => {
  const client = fakeClient({
    data: [
      {
        id: VEHICLE_ID,
        shipment_order_id: TENANT_ID,
        shipment_number: "SO-0001",
        shipment_leg_id: TENANT_ID,
        signal_type: "overdue_geofence_arrival",
        exception_type: "delay",
        severity: "high",
        detected_at: "2026-08-03T00:00:00Z",
        description: "overdue",
        location_geojson: null,
      },
    ],
    error: null,
  });
  const result = await getTenantPendingExceptionSignals(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, limit: 10 });
  assert.equal(result.length, 1);
  assert.equal(result[0]?.severity, "high");
});

test("getTenantPendingExceptionSignals throws FleetControlTowerQueryError on an RPC error", async () => {
  const client = fakeClient({ data: null, error: { message: "boom" } });
  await assert.rejects(() => getTenantPendingExceptionSignals(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }), FleetControlTowerQueryError);
});
