import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseDriverMobileTrackingSession,
  parseStartDriverMobileSessionResult,
  parseDriverMobilePositionReport,
  parseIngestDriverMobileReportResult,
  StartDriverMobileSessionInputSchema,
  IngestDriverMobileReportInputSchema,
  GeoJsonPointSchema,
} from "./driver-mobile-tracking.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SESSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const SLTS_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseDriverMobileTrackingSession", () => {
  test("maps an active session row", () => {
    const session = parseDriverMobileTrackingSession({
      id: SESSION_ID,
      tenant_id: TENANT_ID,
      shipment_leg_tracking_session_id: SLTS_ID,
      status: "active",
      issued_at: "2026-08-03T00:00:00.000Z",
      expires_at: "2026-08-04T00:00:00.000Z",
      last_seen_at: null,
      revoked_at: null,
      revoked_reason: null,
      created_by: "admin",
      created_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(session.status, "active");
    assert.equal(session.revokedAt, null);
  });
});

describe("parseStartDriverMobileSessionResult", () => {
  test("maps a raw token result", () => {
    const result = parseStartDriverMobileSessionResult({
      driver_mobile_session_id: SESSION_ID,
      raw_token: "dmt_deadbeef",
      expires_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(result.rawToken, "dmt_deadbeef");
  });
});

describe("parseDriverMobilePositionReport", () => {
  test("maps a location report with a GeoJSON point", () => {
    const report = parseDriverMobilePositionReport({
      id: "723e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      driver_mobile_tracking_session_id: SESSION_ID,
      report_type: "location",
      event_at: "2026-08-03T00:00:00.000Z",
      received_at: "2026-08-03T00:00:05.000Z",
      location_geojson: { type: "Point", coordinates: [107.6191, -6.9175] },
      accuracy_meters: 12.5,
      battery_percent: 83,
      location_permission_granted: true,
      background_permission_granted: true,
      raw_payload: {},
      created_at: "2026-08-03T00:00:05.000Z",
    });
    assert.equal(report.latitude, -6.9175);
    assert.equal(report.longitude, 107.6191);
  });

  test("maps a heartbeat report with no location", () => {
    const report = parseDriverMobilePositionReport({
      id: "723e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      driver_mobile_tracking_session_id: SESSION_ID,
      report_type: "heartbeat",
      event_at: "2026-08-03T00:00:00.000Z",
      received_at: "2026-08-03T00:00:00.000Z",
      location_geojson: null,
      accuracy_meters: null,
      battery_percent: 85,
      location_permission_granted: true,
      background_permission_granted: false,
      raw_payload: { appVersion: "1.0.0" },
      created_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(report.latitude, null);
    assert.equal(report.longitude, null);
  });
});

describe("parseIngestDriverMobileReportResult", () => {
  test("maps an ok result", () => {
    const result = parseIngestDriverMobileReportResult({ ingest_status: "ok", report_id: "823e4567-e89b-12d3-a456-426614174000", session_ended: false });
    assert.equal(result.ingestStatus, "ok");
  });

  test("maps an invalid result with a null report_id", () => {
    const result = parseIngestDriverMobileReportResult({ ingest_status: "invalid", report_id: null, session_ended: false });
    assert.equal(result.reportId, null);
  });
});

describe("StartDriverMobileSessionInputSchema", () => {
  test("rejects validityHours outside 1-168", () => {
    assert.throws(() =>
      StartDriverMobileSessionInputSchema.parse({ shipmentLegTrackingSessionId: SLTS_ID, validityHours: 200, actorAuthUserId: ACTOR_ID, actorLabel: "admin" }),
    );
  });
});

describe("GeoJsonPointSchema", () => {
  test("accepts a valid point", () => {
    const parsed = GeoJsonPointSchema.parse({ type: "Point", coordinates: [107.6191, -6.9175] });
    assert.equal(parsed.coordinates[0], 107.6191);
  });

  test("rejects an out-of-range longitude", () => {
    assert.throws(() => GeoJsonPointSchema.parse({ type: "Point", coordinates: [200, -6.9175] }));
  });
});

describe("IngestDriverMobileReportInputSchema", () => {
  test("defaults location to null and rawPayload to an empty object", () => {
    const parsed = IngestDriverMobileReportInputSchema.parse({ rawToken: "dmt_abc", clientKey: "client-1", reportType: "heartbeat", eventAt: "2026-08-03T00:00:00.000Z" });
    assert.equal(parsed.location, null);
    assert.deepEqual(parsed.rawPayload, {});
  });
});
