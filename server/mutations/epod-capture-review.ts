/**
 * ePOD Capture and Review mutation primitives (OPS-177, CG-S8-OPS-011). Thin, typed
 * wrappers around the RPCs in
 * supabase/migrations/20260728100000_create_operations_epod_capture_review.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  StartEpodCaptureInputSchema,
  SetEpodEvidenceInputSchema,
  SubmitEpodCaptureInputSchema,
  ReviewEpodCaptureInputSchema,
  ReviseEpodCaptureInputSchema,
  CompleteEpodCaptureInputSchema,
  parseEpodCapture,
  parseEpodEvidenceDownloadSource,
  type StartEpodCaptureInput,
  type SetEpodEvidenceInput,
  type SubmitEpodCaptureInput,
  type ReviewEpodCaptureInput,
  type ReviseEpodCaptureInput,
  type CompleteEpodCaptureInput,
  type EpodCapture,
  type EpodEvidenceSignedDownload,
} from "../contracts/epod-capture-review/epod-capture-review.ts";

export type EpodCaptureReviewMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const EPOD_CAPTURE_REVIEW_KNOWN_MUTATION_ERROR_CODES = [
  "shipment_order_not_found",
  "epod_shipment_not_delivered",
  "epod_capture_not_found",
  "epod_evidence_file_mismatch",
  "spatial_invalid_geojson_type",
  "spatial_invalid_coordinate_count",
  "spatial_coordinate_out_of_range",
  "concurrent_modification",
  "invalid_transition",
  "epod_missing_receiver",
  "epod_missing_evidence",
  "epod_unsafe_evidence",
  "epod_invalid_decision",
  "epod_revision_reason_required",
  "epod_not_latest_version",
  "insufficient_authority",
  "epod_evidence_file_not_found",
  "epod_evidence_file_not_linked",
] as const;
type KnownEpodCaptureReviewMutationErrorCode = (typeof EPOD_CAPTURE_REVIEW_KNOWN_MUTATION_ERROR_CODES)[number];
export type EpodCaptureReviewMutationErrorCode = KnownEpodCaptureReviewMutationErrorCode | "mutation_failed" | "invalid_response";

export class EpodCaptureReviewMutationError extends Error {
  readonly code: EpodCaptureReviewMutationErrorCode;

  constructor(code: EpodCaptureReviewMutationErrorCode, message: string) {
    super(message);
    this.name = "EpodCaptureReviewMutationError";
    this.code = code;
  }
}

function classifyError(message: string): EpodCaptureReviewMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (EPOD_CAPTURE_REVIEW_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownEpodCaptureReviewMutationErrorCode)
    : "mutation_failed";
}

export async function startEpodCapture(client: EpodCaptureReviewMutationRpcClient, input: StartEpodCaptureInput): Promise<EpodCapture> {
  const parsedInput = StartEpodCaptureInputSchema.parse(input);
  const { data, error } = await client.rpc("start_epod_capture", {
    p_tenant_id: parsedInput.tenantId,
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_milestone_event_id: parsedInput.milestoneEventId ?? null,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EpodCaptureReviewMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EpodCaptureReviewMutationError("invalid_response", "start_epod_capture returned no row");
  }
  return parseEpodCapture(data as Record<string, unknown>);
}

/** Only mutates a draft or revision-requested capture -- never submitted/approved/completed (app.set_epod_evidence's own invalid_transition gate). */
export async function setEpodEvidence(client: EpodCaptureReviewMutationRpcClient, input: SetEpodEvidenceInput): Promise<EpodCapture> {
  const parsedInput = SetEpodEvidenceInputSchema.parse(input);
  const { data, error } = await client.rpc("set_epod_evidence", {
    p_capture_id: parsedInput.captureId,
    p_receiver_name: parsedInput.receiverName,
    p_receiver_position: parsedInput.receiverPosition ?? null,
    p_signature_file_id: parsedInput.signatureFileId ?? null,
    p_photo_file_ids: parsedInput.photoFileIds ?? [],
    p_delivery_geojson: parsedInput.deliveryGeojson ?? null,
    p_captured_at: parsedInput.capturedAt ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EpodCaptureReviewMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EpodCaptureReviewMutationError("invalid_response", "set_epod_evidence returned no row");
  }
  return parseEpodCapture(data as Record<string, unknown>);
}

/** Requires a receiver name, at least one of signature/photo evidence, and every referenced file to have already resolved malware_scan_status='clean'. */
export async function submitEpodCapture(client: EpodCaptureReviewMutationRpcClient, input: SubmitEpodCaptureInput): Promise<EpodCapture> {
  const parsedInput = SubmitEpodCaptureInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_epod_capture", {
    p_capture_id: parsedInput.captureId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EpodCaptureReviewMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EpodCaptureReviewMutationError("invalid_response", "submit_epod_capture returned no row");
  }
  return parseEpodCapture(data as Record<string, unknown>);
}

export async function reviewEpodCapture(client: EpodCaptureReviewMutationRpcClient, input: ReviewEpodCaptureInput): Promise<EpodCapture> {
  const parsedInput = ReviewEpodCaptureInputSchema.parse(input);
  const { data, error } = await client.rpc("review_epod_capture", {
    p_capture_id: parsedInput.captureId,
    p_decision: parsedInput.decision,
    p_notes: parsedInput.notes ?? null,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EpodCaptureReviewMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EpodCaptureReviewMutationError("invalid_response", "review_epod_capture returned no row");
  }
  return parseEpodCapture(data as Record<string, unknown>);
}

/** revision_requested -> a brand-new draft version; the prior rejected version is preserved unmutated, never deleted. */
export async function reviseEpodCapture(client: EpodCaptureReviewMutationRpcClient, input: ReviseEpodCaptureInput): Promise<EpodCapture> {
  const parsedInput = ReviseEpodCaptureInputSchema.parse(input);
  const { data, error } = await client.rpc("revise_epod_capture", {
    p_previous_capture_id: parsedInput.previousCaptureId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EpodCaptureReviewMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EpodCaptureReviewMutationError("invalid_response", "revise_epod_capture returned no row");
  }
  return parseEpodCapture(data as Record<string, unknown>);
}

/** approved -> completed; a thin wrapper that also transitions the shipment delivered -> epod through OPS-170's own existing app.transition_shipment_order. */
export async function completeEpodCapture(client: EpodCaptureReviewMutationRpcClient, input: CompleteEpodCaptureInput): Promise<EpodCapture> {
  const parsedInput = CompleteEpodCaptureInputSchema.parse(input);
  const { data, error } = await client.rpc("complete_epod_capture", {
    p_capture_id: parsedInput.captureId,
    p_expected_capture_version: parsedInput.expectedCaptureVersion,
    p_shipment_expected_version: parsedInput.shipmentExpectedVersion,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EpodCaptureReviewMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EpodCaptureReviewMutationError("invalid_response", "complete_epod_capture returned no row");
  }
  return parseEpodCapture(data as Record<string, unknown>);
}

/**
 * Widens EpodCaptureReviewMutationRpcClient with the one extra capability
 * this single function needs: minting a signed URL against the real Storage
 * bucket. Only ever satisfied by a service-role client -- the underlying RPC
 * this calls is granted to service_role only.
 */
export type EpodEvidenceDownloadClient = EpodCaptureReviewMutationRpcClient & {
  storage: {
    from(bucket: string): {
      createSignedUrl(path: string, expiresInSeconds: number): Promise<{ data: { signedUrl: string } | null; error: { message: string } | null }>;
    };
  };
};

const SIGNED_DOWNLOAD_URL_TTL_SECONDS = 300;

/**
 * CG-AUDIT-2026-09-02 A6: mints a short-lived signed URL for one ePOD
 * signature/photo evidence file. Calls the service_role-only
 * app.access_epod_evidence_for_download RPC first (OPS:Download + the
 * parent shipment order's own app.can_access_record scope, then the
 * malware-scan/classification gate); only once that RPC reports
 * accessResult='granted' does this function call Storage at all.
 * storage_path/bucketId never leave this function -- the caller only ever
 * sees the already-signed URL. Mirrors getShipmentDocumentChecklistItemSignedDownloadUrl/
 * getTicketAttachmentSignedDownloadUrl exactly.
 */
export async function getEpodEvidenceSignedDownloadUrl(
  client: EpodEvidenceDownloadClient,
  fileId: string,
  actorAuthUserId: string,
  actorLabel: string,
): Promise<EpodEvidenceSignedDownload> {
  const { data, error } = await client.rpc("access_epod_evidence_for_download", {
    p_file_id: fileId,
    p_actor_auth_user_id: actorAuthUserId,
    p_actor_label: actorLabel,
    p_correlation_id: null,
  });
  if (error) {
    throw new EpodCaptureReviewMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new EpodCaptureReviewMutationError("invalid_response", "access_epod_evidence_for_download returned no row");
  }
  const source = parseEpodEvidenceDownloadSource(row as Record<string, unknown>);

  if (source.accessResult !== "granted" || !source.bucketId || !source.storagePath) {
    return { accessResult: source.accessResult, accessReason: source.accessReason, signedUrl: null, originalFilename: null };
  }

  const { data: signed, error: signError } = await client.storage.from(source.bucketId).createSignedUrl(source.storagePath, SIGNED_DOWNLOAD_URL_TTL_SECONDS);
  if (signError || !signed) {
    throw new EpodCaptureReviewMutationError("invalid_response", `could not mint a signed download URL: ${signError?.message ?? "no data returned"}`);
  }

  return { accessResult: "granted", accessReason: null, signedUrl: signed.signedUrl, originalFilename: source.originalFilename };
}
