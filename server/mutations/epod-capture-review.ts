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
  type StartEpodCaptureInput,
  type SetEpodEvidenceInput,
  type SubmitEpodCaptureInput,
  type ReviewEpodCaptureInput,
  type ReviseEpodCaptureInput,
  type CompleteEpodCaptureInput,
  type EpodCapture,
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
