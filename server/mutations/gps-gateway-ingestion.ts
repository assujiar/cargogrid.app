/**
 * Always-on GPS Gateway ingestion mutation primitives (ATW-226D). Thin, typed wrappers
 * around app.resolve_gps_device_for_handshake / app.ingest_direct_device_telemetry_batch
 * -- both service_role-only (see
 * supabase/migrations/20260729370000_create_advanced_tms_gps_gateway_ingestion.sql's own
 * header design note 1). services/gps-gateway's own standalone process is the real
 * caller of both in production; this module exists for the main Next.js app's own
 * ops/testing surfaces and to keep one canonical typed wire contract
 * (server/contracts/gps-gateway-ingestion/) that package's own minimal client mirrors.
 *
 * Unlike ATW-226C's anon-facing app.ingest_driver_mobile_report, both RPCs here raise
 * on a bad caller credential (a broken gateway deployment secret is a real operational
 * incident, not a per-device business outcome) -- resolveGpsDeviceForHandshake only
 * returns a status row for expected per-device outcomes (unknown/foreign IMEI,
 * wrong-tenant device, not-yet-installed device), it still throws for an invalid API
 * key.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ResolveGpsDeviceForHandshakeInputSchema,
  IngestDirectDeviceTelemetryBatchInputSchema,
  parseResolveGpsDeviceForHandshakeResult,
  parseIngestDirectDeviceTelemetryBatchResult,
  type ResolveGpsDeviceForHandshakeInput,
  type IngestDirectDeviceTelemetryBatchInput,
  type ResolveGpsDeviceForHandshakeResult,
  type IngestDirectDeviceTelemetryBatchResult,
} from "../contracts/gps-gateway-ingestion/gps-gateway-ingestion.ts";

export type GpsGatewayIngestionMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const GPS_GATEWAY_INGESTION_KNOWN_MUTATION_ERROR_CODES = [
  "imei_required",
  "api_key_not_found",
  "api_key_revoked",
  "api_key_expired",
  "insufficient_authority",
  "device_id_required",
  "reports_required",
  "device_not_found",
  "tenant_mismatch",
  "device_not_ingestible",
  "invalid_report_type",
  "event_at_required",
  "location_required",
] as const;
type KnownGpsGatewayIngestionMutationErrorCode = (typeof GPS_GATEWAY_INGESTION_KNOWN_MUTATION_ERROR_CODES)[number];
export type GpsGatewayIngestionMutationErrorCode = KnownGpsGatewayIngestionMutationErrorCode | "mutation_failed" | "invalid_response";

export class GpsGatewayIngestionMutationError extends Error {
  readonly code: GpsGatewayIngestionMutationErrorCode;

  constructor(code: GpsGatewayIngestionMutationErrorCode, message: string) {
    super(message);
    this.name = "GpsGatewayIngestionMutationError";
    this.code = code;
  }
}

function classifyError(message: string): GpsGatewayIngestionMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (GPS_GATEWAY_INGESTION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownGpsGatewayIngestionMutationErrorCode)
    : "mutation_failed";
}

/** Called once per TCP connection, immediately after a device presents its IMEI. */
export async function resolveGpsDeviceForHandshake(
  client: GpsGatewayIngestionMutationRpcClient,
  input: ResolveGpsDeviceForHandshakeInput,
): Promise<ResolveGpsDeviceForHandshakeResult> {
  const parsedInput = ResolveGpsDeviceForHandshakeInputSchema.parse(input);
  const { data, error } = await client.rpc("resolve_gps_device_for_handshake", {
    p_raw_api_key: parsedInput.rawApiKey,
    p_imei: parsedInput.imei,
    p_gateway_instance_label: parsedInput.gatewayInstanceLabel,
  });
  if (error) {
    throw new GpsGatewayIngestionMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new GpsGatewayIngestionMutationError("invalid_response", "resolve_gps_device_for_handshake returned no row");
  }
  return parseResolveGpsDeviceForHandshakeResult(row as Record<string, unknown>);
}

/** One AVL data batch on an already-handshaked connection, keyed by the device_id the handshake resolved. */
export async function ingestDirectDeviceTelemetryBatch(
  client: GpsGatewayIngestionMutationRpcClient,
  input: IngestDirectDeviceTelemetryBatchInput,
): Promise<IngestDirectDeviceTelemetryBatchResult> {
  const parsedInput = IngestDirectDeviceTelemetryBatchInputSchema.parse(input);
  const { data, error } = await client.rpc("ingest_direct_device_telemetry_batch", {
    p_raw_api_key: parsedInput.rawApiKey,
    p_device_id: parsedInput.deviceId,
    p_reports: parsedInput.reports.map((report) => ({
      report_type: report.reportType,
      event_at: report.eventAt,
      longitude: report.longitude,
      latitude: report.latitude,
      altitude_meters: report.altitudeMeters,
      heading_degrees: report.headingDegrees,
      speed_kmh: report.speedKmh,
      satellite_count: report.satelliteCount,
      raw_codec_id: report.rawCodecId,
      io_elements: report.ioElements,
    })),
    p_gateway_instance_label: parsedInput.gatewayInstanceLabel,
  });
  if (error) {
    throw new GpsGatewayIngestionMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new GpsGatewayIngestionMutationError("invalid_response", "ingest_direct_device_telemetry_batch returned no row");
  }
  return parseIngestDirectDeviceTelemetryBatchResult(row as Record<string, unknown>);
}
