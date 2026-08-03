/**
 * GPS device installation evidence mutation primitives (ATW-226B). Thin, typed
 * wrappers around app.record_gps_device_installation / app.verify_gps_device_installation
 * (supabase/migrations/20260729350000_create_advanced_tms_device_installation_evidence.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RecordGpsDeviceInstallationInputSchema,
  VerifyGpsDeviceInstallationInputSchema,
  parseGpsDeviceInstallation,
  type RecordGpsDeviceInstallationInput,
  type VerifyGpsDeviceInstallationInput,
  type GpsDeviceInstallation,
} from "../contracts/gps-device-installation/gps-device-installation.ts";

export type GpsDeviceInstallationMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const GPS_DEVICE_INSTALLATION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "assignment_not_found",
  "assignment_not_current",
  "installation_already_recorded",
  "technician_label_required",
  "evidence_file_not_found",
  "installation_evidence_file_mismatch",
  "installation_unsafe_evidence",
  "installation_not_found",
  "stale_version",
  "invalid_device_status_transition",
] as const;
type KnownGpsDeviceInstallationMutationErrorCode = (typeof GPS_DEVICE_INSTALLATION_KNOWN_MUTATION_ERROR_CODES)[number];
export type GpsDeviceInstallationMutationErrorCode = KnownGpsDeviceInstallationMutationErrorCode | "mutation_failed" | "invalid_response";

export class GpsDeviceInstallationMutationError extends Error {
  readonly code: GpsDeviceInstallationMutationErrorCode;

  constructor(code: GpsDeviceInstallationMutationErrorCode, message: string) {
    super(message);
    this.name = "GpsDeviceInstallationMutationError";
    this.code = code;
  }
}

function classifyError(message: string): GpsDeviceInstallationMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (GPS_DEVICE_INSTALLATION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownGpsDeviceInstallationMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: GpsDeviceInstallationMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<Record<string, unknown>> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new GpsDeviceInstallationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new GpsDeviceInstallationMutationError("invalid_response", `${fn} returned no row`);
  }
  return data as Record<string, unknown>;
}

export async function recordGpsDeviceInstallation(
  client: GpsDeviceInstallationMutationRpcClient,
  input: RecordGpsDeviceInstallationInput,
): Promise<GpsDeviceInstallation> {
  const parsedInput = RecordGpsDeviceInstallationInputSchema.parse(input);
  const row = await callRpc(client, "record_gps_device_installation", {
    p_device_vehicle_assignment_id: parsedInput.deviceVehicleAssignmentId,
    p_evidence_file_id: parsedInput.evidenceFileId,
    p_technician_label: parsedInput.technicianLabel,
    p_installation_notes: parsedInput.installationNotes,
    p_expected_device_version: parsedInput.expectedDeviceVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseGpsDeviceInstallation(row);
}

export async function verifyGpsDeviceInstallation(
  client: GpsDeviceInstallationMutationRpcClient,
  input: VerifyGpsDeviceInstallationInput,
): Promise<GpsDeviceInstallation> {
  const parsedInput = VerifyGpsDeviceInstallationInputSchema.parse(input);
  const row = await callRpc(client, "verify_gps_device_installation", {
    p_installation_id: parsedInput.installationId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseGpsDeviceInstallation(row);
}
