/**
 * ePOD Capture and Review contract (OPS-177, CG-S8-OPS-011). Mirrors
 * supabase/migrations/20260728100000_create_operations_epod_capture_review.sql's
 * app.epod_captures shape and its RPCs.
 *
 * Online-first, versioned electronic proof-of-delivery capture (receiver, signature,
 * photo, geolocation, timestamp), review/revision, and completion -- a thin wrapper
 * over OPS-170's own already-shipped `delivered -> epod` transition, never a second
 * parallel status machine. delivery_geog is exposed as a GeoJSON Point (RFC 7946),
 * the same shape PLT-134's own app.geography_to_geojson_point produces.
 */

import { z } from "zod";

export const GeoJsonPointSchema = z.object({
  type: z.literal("Point"),
  coordinates: z.tuple([z.number().min(-180).max(180), z.number().min(-90).max(90)]),
});
export type GeoJsonPoint = z.infer<typeof GeoJsonPointSchema>;

export const EpodCaptureSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  milestoneEventId: z.string().uuid().nullable(),
  versionGroupId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  isLatestVersion: z.boolean(),
  status: z.enum(["draft", "submitted", "approved", "revision_requested", "completed"]),
  receiverName: z.string().nullable(),
  receiverPosition: z.string().nullable(),
  signatureFileId: z.string().uuid().nullable(),
  photoFileIds: z.array(z.string().uuid()),
  deliveryGeog: GeoJsonPointSchema.nullable(),
  capturedAt: z.string().nullable(),
  serverReceivedAt: z.string(),
  reviewedByAuthUserId: z.string().uuid().nullable(),
  reviewedAt: z.string().nullable(),
  reviewNotes: z.string().nullable(),
  recordVersion: z.number().int(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type EpodCapture = z.infer<typeof EpodCaptureSchema>;

/** PostgREST automatically serializes geography/geometry output columns as GeoJSON (no client-side WKB parsing needed) -- row.delivery_geog therefore arrives as a GeoJSON Point object or null. */
export function parseEpodCapture(row: Record<string, unknown>): EpodCapture {
  return EpodCaptureSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    milestoneEventId: row.milestone_event_id ?? null,
    versionGroupId: row.version_group_id,
    versionNumber: row.version_number,
    isLatestVersion: row.is_latest_version,
    status: row.status,
    receiverName: row.receiver_name ?? null,
    receiverPosition: row.receiver_position ?? null,
    signatureFileId: row.signature_file_id ?? null,
    photoFileIds: row.photo_file_ids ?? [],
    deliveryGeog: row.delivery_geog ?? null,
    capturedAt: row.captured_at ?? null,
    serverReceivedAt: row.server_received_at,
    reviewedByAuthUserId: row.reviewed_by_auth_user_id ?? null,
    reviewedAt: row.reviewed_at ?? null,
    reviewNotes: row.review_notes ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const StartEpodCaptureInputSchema = z.object({
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  milestoneEventId: z.string().uuid().nullable().optional(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type StartEpodCaptureInput = z.input<typeof StartEpodCaptureInputSchema>;

export const SetEpodEvidenceInputSchema = z.object({
  captureId: z.string().uuid(),
  receiverName: z.string().nullable(),
  receiverPosition: z.string().nullable().optional(),
  signatureFileId: z.string().uuid().nullable().optional(),
  photoFileIds: z.array(z.string().uuid()).optional(),
  deliveryGeojson: GeoJsonPointSchema.nullable().optional(),
  capturedAt: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetEpodEvidenceInput = z.input<typeof SetEpodEvidenceInputSchema>;

export const SubmitEpodCaptureInputSchema = z.object({
  captureId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitEpodCaptureInput = z.input<typeof SubmitEpodCaptureInputSchema>;

export const ReviewEpodCaptureInputSchema = z.object({
  captureId: z.string().uuid(),
  decision: z.enum(["approved", "revision_requested"]),
  notes: z.string().nullable().optional(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReviewEpodCaptureInput = z.input<typeof ReviewEpodCaptureInputSchema>;

export const ReviseEpodCaptureInputSchema = z.object({
  previousCaptureId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReviseEpodCaptureInput = z.input<typeof ReviseEpodCaptureInputSchema>;

export const CompleteEpodCaptureInputSchema = z.object({
  captureId: z.string().uuid(),
  expectedCaptureVersion: z.number().int().positive(),
  shipmentExpectedVersion: z.number().int().positive(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CompleteEpodCaptureInput = z.input<typeof CompleteEpodCaptureInputSchema>;

export const GetEpodCaptureHistoryInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetEpodCaptureHistoryInput = z.input<typeof GetEpodCaptureHistoryInputSchema>;
