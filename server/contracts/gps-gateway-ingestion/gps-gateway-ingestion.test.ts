import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseDirectDeviceTelemetryReport,
  parseResolveGpsDeviceForHandshakeResult,
  parseIngestDirectDeviceTelemetryBatchResult,
  ResolveGpsDeviceForHandshakeInputSchema,
  IngestDirectDeviceTelemetryBatchInputSchema,
} from "./gps-gateway-ingestion.ts";

test("parseDirectDeviceTelemetryReport extracts longitude/latitude from a GeoJSON projection", () => {
  const parsed = parseDirectDeviceTelemetryReport({
    id: "723e4567-e89b-12d3-a456-426614174001",
    tenant_id: "723e4567-e89b-12d3-a456-426614174002",
    device_id: "723e4567-e89b-12d3-a456-426614174003",
    report_type: "location",
    event_at: "2026-08-03T00:00:00Z",
    received_at: "2026-08-03T00:00:01Z",
    location_geojson: { type: "Point", coordinates: [106.845599, -6.208763] },
    altitude_meters: 12.5,
    heading_degrees: 87.3,
    speed_kmh: 42,
    satellite_count: 9,
    raw_codec_id: "8E",
    io_elements: { "239": 1 },
    created_at: "2026-08-03T00:00:01Z",
  });
  assert.equal(parsed.longitude, 106.845599);
  assert.equal(parsed.latitude, -6.208763);
  assert.equal(parsed.ioElements["239"], 1);
});

test("parseDirectDeviceTelemetryReport handles a null location (heartbeat report)", () => {
  const parsed = parseDirectDeviceTelemetryReport({
    id: "723e4567-e89b-12d3-a456-426614174001",
    tenant_id: "723e4567-e89b-12d3-a456-426614174002",
    device_id: "723e4567-e89b-12d3-a456-426614174003",
    report_type: "heartbeat",
    event_at: "2026-08-03T00:00:00Z",
    received_at: "2026-08-03T00:00:01Z",
    location_geojson: null,
    altitude_meters: null,
    heading_degrees: null,
    speed_kmh: null,
    satellite_count: null,
    raw_codec_id: "8E",
    io_elements: {},
    created_at: "2026-08-03T00:00:01Z",
  });
  assert.equal(parsed.longitude, null);
  assert.equal(parsed.latitude, null);
});

test("parseResolveGpsDeviceForHandshakeResult defaults nullable fields", () => {
  const parsed = parseResolveGpsDeviceForHandshakeResult({ accepted: false, device_id: null, tenant_id: null, rejection_reason: "imei_not_registered" });
  assert.equal(parsed.accepted, false);
  assert.equal(parsed.deviceId, null);
  assert.equal(parsed.rejectionReason, "imei_not_registered");
});

test("parseIngestDirectDeviceTelemetryBatchResult maps snake_case columns", () => {
  const parsed = parseIngestDirectDeviceTelemetryBatchResult({
    device_id: "723e4567-e89b-12d3-a456-426614174003",
    tenant_id: "723e4567-e89b-12d3-a456-426614174002",
    accepted_count: 3,
    device_status: "active",
  });
  assert.equal(parsed.acceptedCount, 3);
  assert.equal(parsed.deviceStatus, "active");
});

test("ResolveGpsDeviceForHandshakeInputSchema defaults gatewayInstanceLabel to null", () => {
  const parsed = ResolveGpsDeviceForHandshakeInputSchema.parse({ rawApiKey: "cgk_abc", imei: "868712345600001" });
  assert.equal(parsed.gatewayInstanceLabel, null);
});

test("IngestDirectDeviceTelemetryBatchInputSchema rejects an empty reports array", () => {
  assert.throws(() =>
    IngestDirectDeviceTelemetryBatchInputSchema.parse({
      rawApiKey: "cgk_abc",
      deviceId: "723e4567-e89b-12d3-a456-426614174003",
      reports: [],
    }),
  );
});

test("IngestDirectDeviceTelemetryBatchInputSchema accepts a heartbeat report with no coordinates", () => {
  const parsed = IngestDirectDeviceTelemetryBatchInputSchema.parse({
    rawApiKey: "cgk_abc",
    deviceId: "723e4567-e89b-12d3-a456-426614174003",
    reports: [{ reportType: "heartbeat", eventAt: "2026-08-03T00:00:00Z" }],
  });
  assert.equal(parsed.reports[0]?.longitude, null);
});

test("IngestDirectDeviceTelemetryBatchInputSchema rejects an out-of-range longitude", () => {
  assert.throws(() =>
    IngestDirectDeviceTelemetryBatchInputSchema.parse({
      rawApiKey: "cgk_abc",
      deviceId: "723e4567-e89b-12d3-a456-426614174003",
      reports: [{ reportType: "location", eventAt: "2026-08-03T00:00:00Z", longitude: 200, latitude: 0 }],
    }),
  );
});
