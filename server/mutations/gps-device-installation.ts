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
import { parseFile, type File as PlatformFile } from "../contracts/document/document.ts";

export type GpsDeviceInstallationMutationRpcClient = Pick<SupabaseClient, "rpc">;

export interface UploadGpsDeviceInstallationEvidenceFileInput {
  readonly tenantId: string;
  readonly deviceId: string;
  readonly originalFilename: string;
  readonly mimeType: string;
  readonly sizeBytes: number;
  readonly idempotencyKey: string;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
}

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
  // CG-AUDIT-2026-09-02 E5: uploadGpsDeviceInstallationEvidenceFile calls the
  // shared app.initiate_file_upload (PLT-128) primitive directly, making that
  // primitive's own validation error prefixes reachable through this service
  // layer for the first time -- mirrors this array's own established
  // "widen when a fix makes a new code reachable" pattern (see
  // server/mutations/document-requirement.ts's identical set for the same
  // primitive, reused verbatim here).
  "document_type_not_configured",
  "document_unsafe_filename",
  "document_mime_type_not_allowed",
  "document_file_too_large",
  "document_invalid_classification",
  "document_classification_too_weak",
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

/**
 * CG-AUDIT-2026-09-02 E5: stages the evidence photo app.record_gps_device_
 * installation itself requires before it will ever transition a device
 * assigned -> installed. Calls the shared app.initiate_file_upload (PLT-128)
 * primitive directly (service_role only), mirroring
 * uploadShipmentDocumentFile's own identical shape -- record_type/
 * document_type_code are fixed to 'gps_device'/'gps_device_installation'
 * server-side, never caller-supplied, matching app.record_gps_device_
 * installation's own hard-coded expectation
 * (v_file.record_type <> 'gps_device' or v_file.record_id <> v_assignment.device_id).
 * Unlike the narrower authenticated-callable *_upload RPCs this session built
 * for ticket/shipment-checklist evidence, this raw primitive already returns
 * the file's real storage_path (it is service_role-only itself), so no
 * separate storage-path lookup is needed before storeFileBytesAndEnqueueScan.
 */
export async function uploadGpsDeviceInstallationEvidenceFile(
  client: GpsDeviceInstallationMutationRpcClient,
  input: UploadGpsDeviceInstallationEvidenceFileInput,
): Promise<PlatformFile> {
  const { data, error } = await client.rpc("initiate_file_upload", {
    p_tenant_id: input.tenantId,
    p_document_type_code: "gps_device_installation",
    p_record_type: "gps_device",
    p_record_id: input.deviceId,
    p_original_filename: input.originalFilename,
    p_mime_type: input.mimeType,
    p_size_bytes: input.sizeBytes,
    p_classification: null,
    p_legal_hold: false,
    p_legal_hold_reason: null,
    p_shared_org_unit_ids: [],
    p_customer_account_ref: null,
    p_idempotency_key: input.idempotencyKey,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_actor_label: input.actorLabel,
  });
  if (error) {
    throw new GpsDeviceInstallationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new GpsDeviceInstallationMutationError("invalid_response", "initiate_file_upload returned no row");
  }
  return parseFile(data as Record<string, unknown>);
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
