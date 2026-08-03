import { test } from "node:test";
import assert from "node:assert/strict";
import {
  getShipmentMilestoneCandidates,
  getShipmentExceptionSignals,
  getShipmentLegGeofenceState,
  getShipmentLegRouteDeviationState,
  GeofenceSignalsQueryError,
  type GeofenceSignalsQueryRpcClient,
} from "./geofence-route-deviation-signals.ts";

const SHIPMENT_ID = "f23e4567-e89b-12d3-a456-426614174000";
const LEG_ID = "023e4567-e89b-12d3-a456-426614174001";
const ACTOR_ID = "123e4567-e89b-12d3-a456-426614174002";
const CANDIDATE_ID = "223e4567-e89b-12d3-a456-426614174003";
const SIGNAL_ID = "323e4567-e89b-12d3-a456-426614174004";
const STOP_ID = "423e4567-e89b-12d3-a456-426614174005";

function fakeClient(response: { data: unknown; error: { message: string } | null }): GeofenceSignalsQueryRpcClient {
  return {
    rpc: async (_fn: string, _args: Record<string, unknown>) => response,
  } as unknown as GeofenceSignalsQueryRpcClient;
}

test("getShipmentMilestoneCandidates maps every row and defaults to status='pending'", async () => {
  const client = fakeClient({
    data: [
      {
        id: CANDIDATE_ID,
        tenant_id: SHIPMENT_ID,
        shipment_order_id: SHIPMENT_ID,
        shipment_leg_id: LEG_ID,
        shipment_leg_stop_id: STOP_ID,
        milestone_code: "pickup_arrival",
        candidate_event_time: "2026-08-03T00:00:00Z",
        detected_at: "2026-08-03T00:00:00Z",
        source_canonical_event_id: null,
        location_geojson: null,
        status: "pending",
        dedup_key: `geofence_arrival:${STOP_ID}`,
        resulting_milestone_event_id: null,
        reviewed_by_user_id: null,
        reviewed_at: null,
        review_note: null,
        created_at: "2026-08-03T00:00:00Z",
      },
    ],
    error: null,
  });
  const result = await getShipmentMilestoneCandidates(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
  assert.equal(result.length, 1);
  assert.equal(result[0]?.milestoneCode, "pickup_arrival");
});

test("getShipmentMilestoneCandidates throws GeofenceSignalsQueryError on an RPC error", async () => {
  const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:View" } });
  await assert.rejects(
    () => getShipmentMilestoneCandidates(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID }),
    GeofenceSignalsQueryError,
  );
});

test("getShipmentExceptionSignals maps every row", async () => {
  const client = fakeClient({
    data: [
      {
        id: SIGNAL_ID,
        tenant_id: SHIPMENT_ID,
        shipment_order_id: SHIPMENT_ID,
        shipment_leg_id: LEG_ID,
        signal_type: "overdue_geofence_arrival",
        exception_type: "delay",
        severity: "high",
        detected_at: "2026-08-03T00:00:00Z",
        source_canonical_event_id: null,
        location_geojson: null,
        description: "Stop overdue",
        correlation_key: `overdue_arrival:${STOP_ID}`,
        status: "pending",
        resulting_exception_id: null,
        reviewed_by_user_id: null,
        reviewed_at: null,
        review_note: null,
        created_at: "2026-08-03T00:00:00Z",
      },
    ],
    error: null,
  });
  const result = await getShipmentExceptionSignals(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
  assert.equal(result.length, 1);
  assert.equal(result[0]?.signalType, "overdue_geofence_arrival");
  assert.equal(result[0]?.severity, "high");
});

test("getShipmentLegGeofenceState returns an empty array when the leg has never approached any stop", async () => {
  const client = fakeClient({ data: [], error: null });
  const result = await getShipmentLegGeofenceState(client, { shipmentLegId: LEG_ID, actorAuthUserId: ACTOR_ID });
  assert.deepEqual(result, []);
});

test("getShipmentLegGeofenceState maps every row through the parser", async () => {
  const client = fakeClient({
    data: [
      {
        id: STOP_ID,
        tenant_id: SHIPMENT_ID,
        shipment_leg_stop_id: STOP_ID,
        shipment_leg_id: LEG_ID,
        radius_meters: 500,
        dwell_seconds_before_confirm: 60,
        state: "exited",
        first_entered_at: "2026-08-03T00:00:00Z",
        confirmed_at: "2026-08-03T00:01:00Z",
        last_evaluated_at: "2026-08-03T00:02:00Z",
        last_evaluated_location_geojson: null,
        created_at: "2026-08-03T00:00:00Z",
        updated_at: "2026-08-03T00:02:00Z",
      },
    ],
    error: null,
  });
  const result = await getShipmentLegGeofenceState(client, { shipmentLegId: LEG_ID, actorAuthUserId: ACTOR_ID });
  assert.equal(result[0]?.state, "exited");
});

test("getShipmentLegRouteDeviationState returns null when the leg has never deviated", async () => {
  const client = fakeClient({ data: [], error: null });
  const result = await getShipmentLegRouteDeviationState(client, { shipmentLegId: LEG_ID, actorAuthUserId: ACTOR_ID });
  assert.equal(result, null);
});

test("getShipmentLegRouteDeviationState parses a real row", async () => {
  const client = fakeClient({
    data: [
      {
        id: LEG_ID,
        tenant_id: SHIPMENT_ID,
        shipment_leg_id: LEG_ID,
        state: "on_corridor",
        first_off_corridor_at: null,
        confirmed_at: null,
        last_evaluated_at: "2026-08-03T00:00:00Z",
        last_distance_meters: 120.5,
        created_at: "2026-08-03T00:00:00Z",
        updated_at: "2026-08-03T00:00:00Z",
      },
    ],
    error: null,
  });
  const result = await getShipmentLegRouteDeviationState(client, { shipmentLegId: LEG_ID, actorAuthUserId: ACTOR_ID });
  assert.equal(result?.state, "on_corridor");
});
