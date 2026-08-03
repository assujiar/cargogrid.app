import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseThirdPartyProviderConnection,
  parseRegisterThirdPartyProviderConnectionResult,
  parseRotateThirdPartyProviderWebhookSecretResult,
  parseThirdPartyTelemetryReport,
  parseIngestThirdPartyProviderWebhookEventResult,
  ThirdPartyProviderReferenceWebhookPayloadSchema,
  IngestThirdPartyProviderWebhookEventInputSchema,
} from "./third-party-provider-adapter.ts";

const CONN_ID = "723e4567-e89b-12d3-a456-426614174001";
const TENANT_ID = "723e4567-e89b-12d3-a456-426614174002";
const VEHICLE_ID = "723e4567-e89b-12d3-a456-426614174003";

test("parseThirdPartyProviderConnection defaults a null poll_cursor", () => {
  const parsed = parseThirdPartyProviderConnection({
    id: CONN_ID,
    tenant_id: TENANT_ID,
    provider_code: "acmegps",
    integration_mode: "webhook",
    poll_cursor: null,
    status: "active",
    consecutive_failure_count: 0,
    last_successful_ingest_at: null,
    created_at: "2026-08-03T00:00:00Z",
    updated_at: "2026-08-03T00:00:00Z",
  });
  assert.equal(parsed.pollCursor, null);
  assert.equal(parsed.integrationMode, "webhook");
});

test("parseRegisterThirdPartyProviderConnectionResult defaults a null raw_webhook_secret (idempotent re-register)", () => {
  const parsed = parseRegisterThirdPartyProviderConnectionResult({
    connection_id: CONN_ID,
    provider_code: "acmegps",
    integration_mode: "webhook",
    raw_webhook_secret: null,
    status: "active",
  });
  assert.equal(parsed.rawWebhookSecret, null);
});

test("parseRotateThirdPartyProviderWebhookSecretResult maps snake_case columns", () => {
  const parsed = parseRotateThirdPartyProviderWebhookSecretResult({ connection_id: CONN_ID, raw_webhook_secret: "tpws_abc" });
  assert.equal(parsed.rawWebhookSecret, "tpws_abc");
});

test("parseThirdPartyTelemetryReport extracts longitude/latitude from a GeoJSON projection", () => {
  const parsed = parseThirdPartyTelemetryReport({
    id: CONN_ID,
    tenant_id: TENANT_ID,
    connection_id: CONN_ID,
    vehicle_master_id: VEHICLE_ID,
    provider_event_id: "evt-001",
    report_type: "location",
    event_at: "2026-08-03T00:00:00Z",
    received_at: "2026-08-03T00:00:01Z",
    location_geojson: { type: "Point", coordinates: [106.845599, -6.208763] },
    speed_kmh: 42,
    heading_degrees: 87.3,
    raw_fields: { event_id: "evt-001" },
    created_at: "2026-08-03T00:00:01Z",
  });
  assert.equal(parsed.longitude, 106.845599);
  assert.equal(parsed.latitude, -6.208763);
});

test("parseThirdPartyTelemetryReport handles a null location (heartbeat report)", () => {
  const parsed = parseThirdPartyTelemetryReport({
    id: CONN_ID,
    tenant_id: TENANT_ID,
    connection_id: CONN_ID,
    vehicle_master_id: VEHICLE_ID,
    provider_event_id: "evt-002",
    report_type: "heartbeat",
    event_at: "2026-08-03T00:00:00Z",
    received_at: "2026-08-03T00:00:01Z",
    location_geojson: null,
    speed_kmh: null,
    heading_degrees: null,
    raw_fields: {},
    created_at: "2026-08-03T00:00:01Z",
  });
  assert.equal(parsed.longitude, null);
});

test("parseIngestThirdPartyProviderWebhookEventResult maps every ingest_status value", () => {
  for (const status of ["ok", "invalid", "rate_limited", "duplicate", "quarantined"]) {
    const parsed = parseIngestThirdPartyProviderWebhookEventResult({ ingest_status: status, report_id: status === "ok" ? CONN_ID : null });
    assert.equal(parsed.ingestStatus, status);
  }
});

test("ThirdPartyProviderReferenceWebhookPayloadSchema accepts a well-formed location payload", () => {
  const parsed = ThirdPartyProviderReferenceWebhookPayloadSchema.parse({
    event_id: "evt-001",
    vehicle_id: "EXT-VEH-001",
    event_type: "location",
    timestamp: "2026-08-03T00:00:00Z",
    latitude: -6.208763,
    longitude: 106.845599,
    speed_kmh: 42,
    heading_degrees: 87.3,
  });
  assert.equal(parsed.event_id, "evt-001");
});

test("ThirdPartyProviderReferenceWebhookPayloadSchema rejects an unsupported event_type", () => {
  assert.throws(() =>
    ThirdPartyProviderReferenceWebhookPayloadSchema.parse({
      event_id: "evt-001",
      vehicle_id: "EXT-VEH-001",
      event_type: "not_a_real_type",
      timestamp: "2026-08-03T00:00:00Z",
    }),
  );
});

test("IngestThirdPartyProviderWebhookEventInputSchema requires a non-empty rawPayload/signature", () => {
  assert.throws(() =>
    IngestThirdPartyProviderWebhookEventInputSchema.parse({
      connectionId: CONN_ID,
      clientKey: "client-a",
      rawPayload: "",
      timestamp: 1_754_000_000,
      signature: "abc",
    }),
  );
});
