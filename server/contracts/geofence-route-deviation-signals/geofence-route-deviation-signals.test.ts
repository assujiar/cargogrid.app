import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseShipmentLegStopGeofenceState,
  parseShipmentLegRouteDeviationState,
  parseShipmentMilestoneCandidate,
  parseShipmentExceptionSignal,
  ConfirmMilestoneCandidateInputSchema,
  DismissMilestoneCandidateInputSchema,
  ConfirmExceptionSignalInputSchema,
  DismissExceptionSignalInputSchema,
} from "./geofence-route-deviation-signals.ts";

const TENANT_ID = "823e4567-e89b-12d3-a456-426614174000";
const LEG_ID = "923e4567-e89b-12d3-a456-426614174000";
const STOP_ID = "a23e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "b23e4567-e89b-12d3-a456-426614174000";
const CANDIDATE_ID = "c23e4567-e89b-12d3-a456-426614174000";
const SIGNAL_ID = "d23e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "e23e4567-e89b-12d3-a456-426614174000";

test("parseShipmentLegStopGeofenceState maps a real row with a projected GeoJSON location", () => {
  const state = parseShipmentLegStopGeofenceState({
    id: STOP_ID,
    tenant_id: TENANT_ID,
    shipment_leg_stop_id: STOP_ID,
    shipment_leg_id: LEG_ID,
    radius_meters: "500",
    dwell_seconds_before_confirm: "60",
    state: "confirmed_inside",
    first_entered_at: "2026-08-03T00:00:00Z",
    confirmed_at: "2026-08-03T00:02:00Z",
    last_evaluated_at: "2026-08-03T00:02:00Z",
    last_evaluated_location_geojson: { type: "Point", coordinates: [106.8456, -6.2088] },
    created_at: "2026-08-03T00:00:00Z",
    updated_at: "2026-08-03T00:02:00Z",
  });
  assert.equal(state.state, "confirmed_inside");
  assert.equal(state.radiusMeters, 500);
  assert.deepEqual(state.lastEvaluatedLocation, { type: "Point", coordinates: [106.8456, -6.2088] });
});

test("parseShipmentLegStopGeofenceState handles a null location", () => {
  const state = parseShipmentLegStopGeofenceState({
    id: STOP_ID,
    tenant_id: TENANT_ID,
    shipment_leg_stop_id: STOP_ID,
    shipment_leg_id: LEG_ID,
    radius_meters: 500,
    dwell_seconds_before_confirm: 60,
    state: "outside",
    first_entered_at: null,
    confirmed_at: null,
    last_evaluated_at: "2026-08-03T00:00:00Z",
    last_evaluated_location_geojson: null,
    created_at: "2026-08-03T00:00:00Z",
    updated_at: "2026-08-03T00:00:00Z",
  });
  assert.equal(state.lastEvaluatedLocation, null);
});

test("parseShipmentLegRouteDeviationState maps a real off-corridor row", () => {
  const state = parseShipmentLegRouteDeviationState({
    id: LEG_ID,
    tenant_id: TENANT_ID,
    shipment_leg_id: LEG_ID,
    state: "off_corridor",
    first_off_corridor_at: "2026-08-03T00:00:00Z",
    confirmed_at: "2026-08-03T00:03:00Z",
    last_evaluated_at: "2026-08-03T00:03:00Z",
    last_distance_meters: "16234.5",
    created_at: "2026-08-03T00:00:00Z",
    updated_at: "2026-08-03T00:03:00Z",
  });
  assert.equal(state.state, "off_corridor");
  assert.equal(state.lastDistanceMeters, 16234.5);
});

test("parseShipmentMilestoneCandidate maps a real pending row", () => {
  const candidate = parseShipmentMilestoneCandidate({
    id: CANDIDATE_ID,
    tenant_id: TENANT_ID,
    shipment_order_id: SHIPMENT_ID,
    shipment_leg_id: LEG_ID,
    shipment_leg_stop_id: STOP_ID,
    milestone_code: "pickup_arrival",
    candidate_event_time: "2026-08-03T00:02:00Z",
    detected_at: "2026-08-03T00:02:00Z",
    source_canonical_event_id: null,
    location_geojson: null,
    status: "pending",
    dedup_key: `geofence_arrival:${STOP_ID}`,
    resulting_milestone_event_id: null,
    reviewed_by_user_id: null,
    reviewed_at: null,
    review_note: null,
    created_at: "2026-08-03T00:02:00Z",
  });
  assert.equal(candidate.status, "pending");
  assert.equal(candidate.milestoneCode, "pickup_arrival");
  assert.equal(candidate.dedupKey, `geofence_arrival:${STOP_ID}`);
});

test("parseShipmentExceptionSignal maps a real confirmed row", () => {
  const signal = parseShipmentExceptionSignal({
    id: SIGNAL_ID,
    tenant_id: TENANT_ID,
    shipment_order_id: SHIPMENT_ID,
    shipment_leg_id: LEG_ID,
    signal_type: "route_deviation",
    exception_type: "delay",
    severity: "medium",
    detected_at: "2026-08-03T00:00:00Z",
    source_canonical_event_id: null,
    location_geojson: { type: "Point", coordinates: [107.38, -6.56] },
    description: "Vehicle is 16234 meters off the planned route corridor",
    correlation_key: `route_deviation:${LEG_ID}:20260803000000`,
    status: "confirmed",
    resulting_exception_id: SIGNAL_ID,
    reviewed_by_user_id: ACTOR_ID,
    reviewed_at: "2026-08-03T00:05:00Z",
    review_note: null,
    created_at: "2026-08-03T00:00:00Z",
  });
  assert.equal(signal.signalType, "route_deviation");
  assert.equal(signal.status, "confirmed");
  assert.equal(signal.resultingExceptionId, SIGNAL_ID);
});

test("ConfirmMilestoneCandidateInputSchema defaults overrideConflict to false and overrideEventTime to null", () => {
  const parsed = ConfirmMilestoneCandidateInputSchema.parse({ candidateId: CANDIDATE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin" });
  assert.equal(parsed.overrideConflict, false);
  assert.equal(parsed.overrideEventTime, null);
});

test("DismissMilestoneCandidateInputSchema requires a non-empty reviewNote", () => {
  assert.throws(() => DismissMilestoneCandidateInputSchema.parse({ candidateId: CANDIDATE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin", reviewNote: "" }));
});

test("ConfirmExceptionSignalInputSchema parses a minimal valid input", () => {
  const parsed = ConfirmExceptionSignalInputSchema.parse({ signalId: SIGNAL_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin" });
  assert.equal(parsed.signalId, SIGNAL_ID);
});

test("DismissExceptionSignalInputSchema requires a non-empty reviewNote", () => {
  assert.throws(() => DismissExceptionSignalInputSchema.parse({ signalId: SIGNAL_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin", reviewNote: "" }));
});
