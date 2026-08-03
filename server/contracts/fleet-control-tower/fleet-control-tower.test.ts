import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseTenantVehicleTrackingOverviewRow,
  parseTenantPendingMilestoneCandidateRow,
  parseTenantPendingExceptionSignalRow,
} from "./fleet-control-tower.ts";

const VEHICLE_ID = "f23e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "023e4567-e89b-12d3-a456-426614174001";
const LEG_ID = "123e4567-e89b-12d3-a456-426614174002";
const STOP_ID = "223e4567-e89b-12d3-a456-426614174003";
const CANDIDATE_ID = "323e4567-e89b-12d3-a456-426614174004";
const SIGNAL_ID = "423e4567-e89b-12d3-a456-426614174005";

test("parseTenantVehicleTrackingOverviewRow maps a tracked vehicle with a real position", () => {
  const row = parseTenantVehicleTrackingOverviewRow({
    vehicle_master_id: VEHICLE_ID,
    vehicle_code: "VEH-A",
    vehicle_name: "Truck A",
    mobile_tracking_eligible: true,
    direct_device_tracking_eligible: true,
    third_party_tracking_eligible: false,
    current_source_type: "direct_device",
    current_location_geojson: { type: "Point", coordinates: [106.8456, -6.2088] },
    current_speed_kmh: "42.5",
    current_heading_degrees: "90",
    current_event_at: "2026-08-03T00:00:00Z",
    current_received_at: "2026-08-03T00:00:01Z",
  });
  assert.equal(row.currentSourceType, "direct_device");
  assert.equal(row.currentSpeedKmh, 42.5);
  assert.deepEqual(row.currentLocation, { type: "Point", coordinates: [106.8456, -6.2088] });
});

test("parseTenantVehicleTrackingOverviewRow maps a never-tracked vehicle with null position fields", () => {
  const row = parseTenantVehicleTrackingOverviewRow({
    vehicle_master_id: VEHICLE_ID,
    vehicle_code: "VEH-B",
    vehicle_name: "Truck B",
    mobile_tracking_eligible: false,
    direct_device_tracking_eligible: false,
    third_party_tracking_eligible: false,
    current_source_type: null,
    current_location_geojson: null,
    current_speed_kmh: null,
    current_heading_degrees: null,
    current_event_at: null,
    current_received_at: null,
  });
  assert.equal(row.currentSourceType, null);
  assert.equal(row.currentLocation, null);
});

test("parseTenantPendingMilestoneCandidateRow maps a real row", () => {
  const row = parseTenantPendingMilestoneCandidateRow({
    id: CANDIDATE_ID,
    shipment_order_id: SHIPMENT_ID,
    shipment_number: "SO-0001",
    shipment_leg_id: LEG_ID,
    shipment_leg_stop_id: STOP_ID,
    milestone_code: "pickup_arrival",
    candidate_event_time: "2026-08-03T00:00:00Z",
    detected_at: "2026-08-03T00:00:00Z",
    location_geojson: null,
  });
  assert.equal(row.shipmentNumber, "SO-0001");
  assert.equal(row.milestoneCode, "pickup_arrival");
});

test("parseTenantPendingExceptionSignalRow maps a real row", () => {
  const row = parseTenantPendingExceptionSignalRow({
    id: SIGNAL_ID,
    shipment_order_id: SHIPMENT_ID,
    shipment_number: "SO-0001",
    shipment_leg_id: LEG_ID,
    signal_type: "route_deviation",
    exception_type: "delay",
    severity: "medium",
    detected_at: "2026-08-03T00:00:00Z",
    description: "off corridor",
    location_geojson: { type: "Point", coordinates: [107.38, -6.56] },
  });
  assert.equal(row.signalType, "route_deviation");
  assert.equal(row.severity, "medium");
  assert.deepEqual(row.location, { type: "Point", coordinates: [107.38, -6.56] });
});
