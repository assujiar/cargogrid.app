/**
 * Driver Mobile GPS session and HTTPS ingestion mutation primitives (ATW-226C). Thin,
 * typed wrappers around app.start_driver_mobile_session / app.revoke_driver_mobile_session
 * (dispatcher-facing, authenticated/service_role) and app.ingest_driver_mobile_report
 * (the one anon-callable RPC in this capability -- see
 * supabase/migrations/20260729360000_create_advanced_tms_driver_mobile_tracking.sql's
 * own header design note 3 for why this is safe).
 *
 * app.ingest_driver_mobile_report never raises for an auth/validation failure -- every
 * outcome is a returned ingestStatus, so ingestDriverMobileReport below never throws
 * for a bad token/rate limit either, unlike every other mutation wrapper in this
 * repository. Callers (the HTTPS route handler) branch on ingestStatus directly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  StartDriverMobileSessionInputSchema,
  RevokeDriverMobileSessionInputSchema,
  IngestDriverMobileReportInputSchema,
  parseStartDriverMobileSessionResult,
  parseDriverMobileTrackingSession,
  parseIngestDriverMobileReportResult,
  type StartDriverMobileSessionInput,
  type RevokeDriverMobileSessionInput,
  type IngestDriverMobileReportInput,
  type StartDriverMobileSessionResult,
  type DriverMobileTrackingSession,
  type IngestDriverMobileReportResult,
} from "../contracts/driver-mobile-tracking/driver-mobile-tracking.ts";

export type DriverMobileTrackingMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const DRIVER_MOBILE_TRACKING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "tracking_session_not_found",
  "not_a_driver_mobile_session",
  "tracking_session_not_active",
  "driver_mobile_session_already_issued",
  "invalid_validity_hours",
  "driver_mobile_session_not_found",
  "revoke_reason_required",
] as const;
type KnownDriverMobileTrackingMutationErrorCode = (typeof DRIVER_MOBILE_TRACKING_KNOWN_MUTATION_ERROR_CODES)[number];
export type DriverMobileTrackingMutationErrorCode = KnownDriverMobileTrackingMutationErrorCode | "mutation_failed" | "invalid_response";

export class DriverMobileTrackingMutationError extends Error {
  readonly code: DriverMobileTrackingMutationErrorCode;

  constructor(code: DriverMobileTrackingMutationErrorCode, message: string) {
    super(message);
    this.name = "DriverMobileTrackingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): DriverMobileTrackingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (DRIVER_MOBILE_TRACKING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownDriverMobileTrackingMutationErrorCode)
    : "mutation_failed";
}

/** Dispatcher-initiated (OPS:Edit). Returns the raw bearer token exactly once -- the caller is responsible for transmitting it to the driver out-of-band and never logging/persisting it beyond this response. */
export async function startDriverMobileSession(
  client: DriverMobileTrackingMutationRpcClient,
  input: StartDriverMobileSessionInput,
): Promise<StartDriverMobileSessionResult> {
  const parsedInput = StartDriverMobileSessionInputSchema.parse(input);
  const { data, error } = await client.rpc("start_driver_mobile_session", {
    p_shipment_leg_tracking_session_id: parsedInput.shipmentLegTrackingSessionId,
    p_validity_hours: parsedInput.validityHours,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DriverMobileTrackingMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new DriverMobileTrackingMutationError("invalid_response", "start_driver_mobile_session returned no row");
  }
  return parseStartDriverMobileSessionResult(row as Record<string, unknown>);
}

/** Dispatcher-initiated revocation (e.g. lost phone). */
export async function revokeDriverMobileSession(
  client: DriverMobileTrackingMutationRpcClient,
  input: RevokeDriverMobileSessionInput,
): Promise<DriverMobileTrackingSession> {
  const parsedInput = RevokeDriverMobileSessionInputSchema.parse(input);
  const { data, error } = await client.rpc("revoke_driver_mobile_session", {
    p_shipment_leg_tracking_session_id: parsedInput.shipmentLegTrackingSessionId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DriverMobileTrackingMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DriverMobileTrackingMutationError("invalid_response", "revoke_driver_mobile_session returned no row");
  }
  return parseDriverMobileTrackingSession(data as Record<string, unknown>);
}

/** The Driver PWA's own ingestion entry point. Never throws for a bad token/malformed report/rate limit -- see this module's own header. Only a genuine transport/serialization error throws. */
export async function ingestDriverMobileReport(
  client: DriverMobileTrackingMutationRpcClient,
  input: IngestDriverMobileReportInput,
): Promise<IngestDriverMobileReportResult> {
  const parsedInput = IngestDriverMobileReportInputSchema.parse(input);
  const { data, error } = await client.rpc("ingest_driver_mobile_report", {
    p_raw_token: parsedInput.rawToken,
    p_client_key: parsedInput.clientKey,
    p_report_type: parsedInput.reportType,
    p_event_at: parsedInput.eventAt,
    p_location: parsedInput.location,
    p_accuracy_meters: parsedInput.accuracyMeters,
    p_battery_percent: parsedInput.batteryPercent,
    p_location_permission_granted: parsedInput.locationPermissionGranted,
    p_background_permission_granted: parsedInput.backgroundPermissionGranted,
    p_raw_payload: parsedInput.rawPayload,
  });
  if (error) {
    throw new DriverMobileTrackingMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new DriverMobileTrackingMutationError("invalid_response", "ingest_driver_mobile_report returned no row");
  }
  return parseIngestDriverMobileReportResult(row as Record<string, unknown>);
}
