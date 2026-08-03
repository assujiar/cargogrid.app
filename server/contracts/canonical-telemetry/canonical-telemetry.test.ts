import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseVehicleCurrentPosition,
  parseCanonicalTelemetryEvent,
  parseVehicleSourceHealth,
  parseVehicleSourceSwitch,
} from "./canonical-telemetry.ts";

const VEHICLE_ID = "723e4567-e89b-12d3-a456-426614174001";
const TENANT_ID = "723e4567-e89b-12d3-a456-426614174002";
const EVENT_ID = "723e4567-e89b-12d3-a456-426614174003";

test("parseVehicleCurrentPosition extracts longitude/latitude from a GeoJSON projection", () => {
  const parsed = parseVehicleCurrentPosition({
    vehicle_master_id: VEHICLE_ID,
    tenant_id: TENANT_ID,
    source_type: "direct_device",
    location_geojson: { type: "Point", coordinates: [106.845599, -6.208763] },
    speed_kmh: 42,
    heading_degrees: 87.3,
    event_at: "2026-08-03T00:00:00Z",
    received_at: "2026-08-03T00:00:01Z",
    updated_at: "2026-08-03T00:00:01Z",
  });
  assert.equal(parsed.longitude, 106.845599);
  assert.equal(parsed.latitude, -6.208763);
  assert.equal(parsed.sourceType, "direct_device");
});

test("parseCanonicalTelemetryEvent handles a null location (heartbeat/rejected event)", () => {
  const parsed = parseCanonicalTelemetryEvent({
    id: EVENT_ID,
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
    rejection_reason: "heartbeat_no_location",
  });
  assert.equal(parsed.longitude, null);
  assert.equal(parsed.appliedToCurrentPosition, false);
  assert.equal(parsed.rejectionReason, "heartbeat_no_location");
});

test("parseCanonicalTelemetryEvent extracts coordinates from a real location event", () => {
  const parsed = parseCanonicalTelemetryEvent({
    id: EVENT_ID,
    tenant_id: TENANT_ID,
    vehicle_master_id: VEHICLE_ID,
    source_type: "third_party_platform",
    event_at: "2026-08-03T00:00:00Z",
    received_at: "2026-08-03T00:00:01Z",
    location_geojson: { type: "Point", coordinates: [106.8, -6.2] },
    speed_kmh: 10,
    heading_degrees: 90,
    accuracy_meters: null,
    applied_to_current_position: true,
    rejection_reason: null,
  });
  assert.equal(parsed.longitude, 106.8);
  assert.equal(parsed.appliedToCurrentPosition, true);
  assert.equal(parsed.rejectionReason, null);
});

test("parseVehicleSourceHealth defaults null last-seen timestamps", () => {
  const parsed = parseVehicleSourceHealth({ source_type: "third_party_platform", last_seen_event_at: null, last_seen_received_at: null, status: "unknown" });
  assert.equal(parsed.status, "unknown");
  assert.equal(parsed.lastSeenEventAt, null);
});

test("parseVehicleSourceSwitch defaults a null from_source_type (bootstrap)", () => {
  const parsed = parseVehicleSourceSwitch({
    id: EVENT_ID,
    tenant_id: TENANT_ID,
    vehicle_master_id: VEHICLE_ID,
    from_source_type: null,
    to_source_type: "direct_device",
    reason: "bootstrap",
    canonical_telemetry_event_id: EVENT_ID,
    evidence: { incoming_rank: 2 },
    switched_at: "2026-08-03T00:00:00Z",
  });
  assert.equal(parsed.fromSourceType, null);
  assert.equal(parsed.reason, "bootstrap");
  assert.equal(parsed.evidence.incoming_rank, 2);
});

test("parseVehicleSourceSwitch parses a real cross-source switch with evidence", () => {
  const parsed = parseVehicleSourceSwitch({
    id: EVENT_ID,
    tenant_id: TENANT_ID,
    vehicle_master_id: VEHICLE_ID,
    from_source_type: "direct_device",
    to_source_type: "third_party_platform",
    reason: "current_source_stale_fallback",
    canonical_telemetry_event_id: EVENT_ID,
    evidence: { current_is_stale: true },
    switched_at: "2026-08-03T00:00:00Z",
  });
  assert.equal(parsed.fromSourceType, "direct_device");
  assert.equal(parsed.evidence.current_is_stale, true);
});
