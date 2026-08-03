/**
 * Driver Mobile GPS session and HTTPS ingestion contract (ATW-226C, CG-S10-ATW-006's
 * family, Prompt 226 decomposition child). Mirrors
 * supabase/migrations/20260729360000_create_advanced_tms_driver_mobile_tracking.sql's
 * app.driver_mobile_tracking_sessions/app.driver_mobile_position_reports shapes and the
 * app.start_driver_mobile_session / app.revoke_driver_mobile_session /
 * app.ingest_driver_mobile_report RPCs.
 *
 * app.shipment_leg_tracking_sessions (ATW-225) itself is not re-declared here -- see
 * server/contracts/mile-orchestration/mile-orchestration.ts.
 */

import { z } from "zod";

export const DRIVER_MOBILE_SESSION_STATUSES = ["active", "revoked", "expired"] as const;
export const DriverMobileSessionStatusSchema = z.enum(DRIVER_MOBILE_SESSION_STATUSES);
export type DriverMobileSessionStatus = z.infer<typeof DriverMobileSessionStatusSchema>;

export const DRIVER_MOBILE_REPORT_TYPES = ["heartbeat", "location", "pause", "resume", "stop"] as const;
export const DriverMobileReportTypeSchema = z.enum(DRIVER_MOBILE_REPORT_TYPES);
export type DriverMobileReportType = z.infer<typeof DriverMobileReportTypeSchema>;

export const DriverMobileTrackingSessionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentLegTrackingSessionId: z.string().uuid(),
  status: DriverMobileSessionStatusSchema,
  issuedAt: z.string(),
  expiresAt: z.string(),
  lastSeenAt: z.string().nullable(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type DriverMobileTrackingSession = z.infer<typeof DriverMobileTrackingSessionSchema>;

export function parseDriverMobileTrackingSession(row: Record<string, unknown>): DriverMobileTrackingSession {
  return DriverMobileTrackingSessionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentLegTrackingSessionId: row.shipment_leg_tracking_session_id,
    status: row.status,
    issuedAt: row.issued_at,
    expiresAt: row.expires_at,
    lastSeenAt: row.last_seen_at ?? null,
    revokedAt: row.revoked_at ?? null,
    revokedReason: row.revoked_reason ?? null,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
  });
}

/** Result shape of app.start_driver_mobile_session -- rawToken is disclosed exactly once, here, and never stored server-side beyond this response. */
export const StartDriverMobileSessionResultSchema = z.object({
  driverMobileSessionId: z.string().uuid(),
  rawToken: z.string(),
  expiresAt: z.string(),
});
export type StartDriverMobileSessionResult = z.infer<typeof StartDriverMobileSessionResultSchema>;

export function parseStartDriverMobileSessionResult(row: Record<string, unknown>): StartDriverMobileSessionResult {
  return StartDriverMobileSessionResultSchema.parse({
    driverMobileSessionId: row.driver_mobile_session_id,
    rawToken: row.raw_token,
    expiresAt: row.expires_at,
  });
}

export const StartDriverMobileSessionInputSchema = z.object({
  shipmentLegTrackingSessionId: z.string().uuid(),
  validityHours: z.number().int().min(1).max(168),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type StartDriverMobileSessionInput = z.infer<typeof StartDriverMobileSessionInputSchema>;

export const RevokeDriverMobileSessionInputSchema = z.object({
  shipmentLegTrackingSessionId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RevokeDriverMobileSessionInput = z.infer<typeof RevokeDriverMobileSessionInputSchema>;

export const DriverMobilePositionReportSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  driverMobileTrackingSessionId: z.string().uuid(),
  reportType: DriverMobileReportTypeSchema,
  eventAt: z.string(),
  receivedAt: z.string(),
  latitude: z.number().nullable(),
  longitude: z.number().nullable(),
  accuracyMeters: z.number().nullable(),
  batteryPercent: z.number().int().nullable(),
  locationPermissionGranted: z.boolean().nullable(),
  backgroundPermissionGranted: z.boolean().nullable(),
  rawPayload: z.record(z.string(), z.unknown()),
  createdAt: z.string(),
});
export type DriverMobilePositionReport = z.infer<typeof DriverMobilePositionReportSchema>;

/** location arrives from PostGIS as GeoJSON (via ST_AsGeoJSON in the selecting query) or null -- never a raw WKB string surfaced to a caller. */
export function parseDriverMobilePositionReport(row: Record<string, unknown>): DriverMobilePositionReport {
  const location = row.location_geojson as { coordinates?: [number, number] } | null | undefined;
  return DriverMobilePositionReportSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    driverMobileTrackingSessionId: row.driver_mobile_tracking_session_id,
    reportType: row.report_type,
    eventAt: row.event_at,
    receivedAt: row.received_at,
    latitude: location?.coordinates ? location.coordinates[1] : null,
    longitude: location?.coordinates ? location.coordinates[0] : null,
    accuracyMeters: row.accuracy_meters ?? null,
    batteryPercent: row.battery_percent ?? null,
    locationPermissionGranted: row.location_permission_granted ?? null,
    backgroundPermissionGranted: row.background_permission_granted ?? null,
    rawPayload: (row.raw_payload as Record<string, unknown>) ?? {},
    createdAt: row.created_at,
  });
}

export const IngestDriverMobileReportResultSchema = z.object({
  ingestStatus: z.enum(["ok", "invalid", "rate_limited"]),
  reportId: z.string().uuid().nullable(),
  sessionEnded: z.boolean(),
});
export type IngestDriverMobileReportResult = z.infer<typeof IngestDriverMobileReportResultSchema>;

export function parseIngestDriverMobileReportResult(row: Record<string, unknown>): IngestDriverMobileReportResult {
  return IngestDriverMobileReportResultSchema.parse({
    ingestStatus: row.ingest_status,
    reportId: row.report_id ?? null,
    sessionEnded: row.session_ended,
  });
}

/** The GeoJSON Point shape app.geojson_point_to_geography (PLT-134) accepts -- longitude first, per the GeoJSON spec. */
export const GeoJsonPointSchema = z.object({
  type: z.literal("Point"),
  coordinates: z.tuple([z.number().min(-180).max(180), z.number().min(-90).max(90)]),
});
export type GeoJsonPoint = z.infer<typeof GeoJsonPointSchema>;

export const IngestDriverMobileReportInputSchema = z.object({
  rawToken: z.string().min(1),
  clientKey: z.string().min(1),
  reportType: DriverMobileReportTypeSchema,
  eventAt: z.string(),
  location: GeoJsonPointSchema.nullable().default(null),
  accuracyMeters: z.number().nonnegative().nullable().default(null),
  batteryPercent: z.number().int().min(0).max(100).nullable().default(null),
  locationPermissionGranted: z.boolean().nullable().default(null),
  backgroundPermissionGranted: z.boolean().nullable().default(null),
  rawPayload: z.record(z.string(), z.unknown()).default({}),
});
export type IngestDriverMobileReportInput = z.input<typeof IngestDriverMobileReportInputSchema>;
