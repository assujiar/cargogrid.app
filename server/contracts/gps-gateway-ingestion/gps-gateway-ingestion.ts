/**
 * Always-on GPS Gateway direct-device telemetry ingestion contract (ATW-226D,
 * CG-S10-ATW-006's family, Prompt 226 decomposition child). Mirrors
 * supabase/migrations/20260729370000_create_advanced_tms_gps_gateway_ingestion.sql's
 * app.direct_device_telemetry_reports shape and the
 * app.resolve_gps_device_for_handshake / app.ingest_direct_device_telemetry_batch /
 * app.get_direct_device_telemetry_reports RPCs.
 *
 * Unlike ATW-226C's driver-mobile contract, every RPC here is service_role-only -- the
 * GPS Gateway is a trusted backend process (services/gps-gateway), never an
 * unauthenticated browser session. This module is consumed both by the main Next.js
 * app (dispatcher/administration reads via getDirectDeviceTelemetryReports) and,
 * independently, by services/gps-gateway's own minimal RPC client (that standalone
 * package does not import from server/ -- see its own README for why -- but the wire
 * shape it produces must stay identical to what these Zod schemas accept).
 */

import { z } from "zod";

export const DIRECT_DEVICE_REPORT_TYPES = ["location", "heartbeat"] as const;
export const DirectDeviceReportTypeSchema = z.enum(DIRECT_DEVICE_REPORT_TYPES);
export type DirectDeviceReportType = z.infer<typeof DirectDeviceReportTypeSchema>;

export const DirectDeviceTelemetryReportSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  deviceId: z.string().uuid(),
  reportType: DirectDeviceReportTypeSchema,
  eventAt: z.string(),
  receivedAt: z.string(),
  latitude: z.number().nullable(),
  longitude: z.number().nullable(),
  altitudeMeters: z.number().nullable(),
  headingDegrees: z.number().nullable(),
  speedKmh: z.number().nullable(),
  satelliteCount: z.number().int().nullable(),
  rawCodecId: z.string(),
  ioElements: z.record(z.string(), z.unknown()),
  createdAt: z.string(),
});
export type DirectDeviceTelemetryReport = z.infer<typeof DirectDeviceTelemetryReportSchema>;

/** location arrives from PostGIS as GeoJSON (via ST_AsGeoJSON in app.get_direct_device_telemetry_reports) or null -- never a raw WKB string surfaced to a caller. */
export function parseDirectDeviceTelemetryReport(row: Record<string, unknown>): DirectDeviceTelemetryReport {
  const location = row.location_geojson as { coordinates?: [number, number] } | null | undefined;
  return DirectDeviceTelemetryReportSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    deviceId: row.device_id,
    reportType: row.report_type,
    eventAt: row.event_at,
    receivedAt: row.received_at,
    latitude: location?.coordinates ? location.coordinates[1] : null,
    longitude: location?.coordinates ? location.coordinates[0] : null,
    altitudeMeters: row.altitude_meters ?? null,
    headingDegrees: row.heading_degrees ?? null,
    speedKmh: row.speed_kmh ?? null,
    satelliteCount: row.satellite_count ?? null,
    rawCodecId: row.raw_codec_id,
    ioElements: (row.io_elements as Record<string, unknown>) ?? {},
    createdAt: row.created_at,
  });
}

export const ResolveGpsDeviceForHandshakeResultSchema = z.object({
  accepted: z.boolean(),
  deviceId: z.string().uuid().nullable(),
  tenantId: z.string().uuid().nullable(),
  rejectionReason: z.string().nullable(),
});
export type ResolveGpsDeviceForHandshakeResult = z.infer<typeof ResolveGpsDeviceForHandshakeResultSchema>;

export function parseResolveGpsDeviceForHandshakeResult(row: Record<string, unknown>): ResolveGpsDeviceForHandshakeResult {
  return ResolveGpsDeviceForHandshakeResultSchema.parse({
    accepted: row.accepted,
    deviceId: row.device_id ?? null,
    tenantId: row.tenant_id ?? null,
    rejectionReason: row.rejection_reason ?? null,
  });
}

export const ResolveGpsDeviceForHandshakeInputSchema = z.object({
  rawApiKey: z.string().min(1),
  imei: z.string().min(1),
  gatewayInstanceLabel: z.string().nullable().default(null),
});
export type ResolveGpsDeviceForHandshakeInput = z.input<typeof ResolveGpsDeviceForHandshakeInputSchema>;

/** The decoded per-record shape services/gps-gateway's own Codec 8E parser produces, before it is batched into app.ingest_direct_device_telemetry_batch's own p_reports jsonb array. */
export const DirectDeviceTelemetryReportInputSchema = z.object({
  reportType: DirectDeviceReportTypeSchema,
  eventAt: z.string(),
  longitude: z.number().min(-180).max(180).nullable().default(null),
  latitude: z.number().min(-90).max(90).nullable().default(null),
  altitudeMeters: z.number().nullable().default(null),
  headingDegrees: z.number().min(0).max(360).nullable().default(null),
  speedKmh: z.number().nonnegative().nullable().default(null),
  satelliteCount: z.number().int().nonnegative().nullable().default(null),
  rawCodecId: z.string().nullable().default(null),
  ioElements: z.record(z.string(), z.unknown()).default({}),
});
export type DirectDeviceTelemetryReportInput = z.input<typeof DirectDeviceTelemetryReportInputSchema>;

export const IngestDirectDeviceTelemetryBatchInputSchema = z.object({
  rawApiKey: z.string().min(1),
  deviceId: z.string().uuid(),
  reports: z.array(DirectDeviceTelemetryReportInputSchema).min(1),
  gatewayInstanceLabel: z.string().nullable().default(null),
});
export type IngestDirectDeviceTelemetryBatchInput = z.input<typeof IngestDirectDeviceTelemetryBatchInputSchema>;

export const IngestDirectDeviceTelemetryBatchResultSchema = z.object({
  deviceId: z.string().uuid(),
  tenantId: z.string().uuid(),
  acceptedCount: z.number().int(),
  deviceStatus: z.string(),
});
export type IngestDirectDeviceTelemetryBatchResult = z.infer<typeof IngestDirectDeviceTelemetryBatchResultSchema>;

export function parseIngestDirectDeviceTelemetryBatchResult(row: Record<string, unknown>): IngestDirectDeviceTelemetryBatchResult {
  return IngestDirectDeviceTelemetryBatchResultSchema.parse({
    deviceId: row.device_id,
    tenantId: row.tenant_id,
    acceptedCount: row.accepted_count,
    deviceStatus: row.device_status,
  });
}
