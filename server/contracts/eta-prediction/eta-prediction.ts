/**
 * Predictive ETA contract (IAE-022, Prompt 350). Mirrors
 * supabase/migrations/20260806100000_create_intelligence_predictive_eta.sql's
 * app.eta_predictions/app.eta_prediction_evaluations/app.eta_prediction_tenant_settings
 * shapes and their request/record/override/evaluate/get/list/enable RPCs.
 */

import { z } from "zod";

export const ETA_PREDICTION_STATUSES = ["pending", "succeeded", "failed"] as const;
export const EtaPredictionStatusSchema = z.enum(ETA_PREDICTION_STATUSES);
export type EtaPredictionStatus = z.infer<typeof EtaPredictionStatusSchema>;

/** The raw app.eta_predictions row shape, as returned by request/record/override. */
export const EtaPredictionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  aiGovernedRequestId: z.string().uuid().nullable(),
  featureSnapshot: z.record(z.string(), z.unknown()),
  status: EtaPredictionStatusSchema,
  predictedEta: z.string().nullable(),
  predictedEtaEarliest: z.string().nullable(),
  predictedEtaLatest: z.string().nullable(),
  overridden: z.boolean(),
  overrideReason: z.string().nullable(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
  completedAt: z.string().nullable(),
});
export type EtaPrediction = z.infer<typeof EtaPredictionSchema>;

export function parseEtaPrediction(row: Record<string, unknown>): EtaPrediction {
  return EtaPredictionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    aiGovernedRequestId: row.ai_governed_request_id,
    featureSnapshot: row.feature_snapshot,
    status: row.status,
    predictedEta: row.predicted_eta,
    predictedEtaEarliest: row.predicted_eta_earliest,
    predictedEtaLatest: row.predicted_eta_latest,
    overridden: row.overridden,
    overrideReason: row.override_reason,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
    completedAt: row.completed_at,
  });
}

/** app.get_eta_prediction's own wider read-path shape -- joins in the governed request's own evidence plus any evaluation. */
export const EtaPredictionDetailSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  aiGovernedRequestId: z.string().uuid().nullable(),
  status: EtaPredictionStatusSchema,
  predictedEta: z.string().nullable(),
  predictedEtaEarliest: z.string().nullable(),
  predictedEtaLatest: z.string().nullable(),
  overridden: z.boolean(),
  overrideReason: z.string().nullable(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
  completedAt: z.string().nullable(),
  confidenceLabel: z.enum(["high", "medium", "low"]).nullable(),
  modelVersion: z.string().nullable(),
  requestStatus: z.string().nullable(),
  errorMinutes: z.coerce.number().nullable(),
  withinConfidenceBand: z.boolean().nullable(),
  actualArrivalAt: z.string().nullable(),
});
export type EtaPredictionDetail = z.infer<typeof EtaPredictionDetailSchema>;

export function parseEtaPredictionDetail(row: Record<string, unknown>): EtaPredictionDetail {
  return EtaPredictionDetailSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    aiGovernedRequestId: row.ai_governed_request_id,
    status: row.status,
    predictedEta: row.predicted_eta,
    predictedEtaEarliest: row.predicted_eta_earliest,
    predictedEtaLatest: row.predicted_eta_latest,
    overridden: row.overridden,
    overrideReason: row.override_reason,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
    completedAt: row.completed_at,
    confidenceLabel: row.confidence_label,
    modelVersion: row.model_version,
    requestStatus: row.request_status,
    errorMinutes: row.error_minutes,
    withinConfidenceBand: row.within_confidence_band,
    actualArrivalAt: row.actual_arrival_at,
  });
}

/** app.list_eta_predictions_for_shipment's own narrower list-row shape. */
export const EtaPredictionSummarySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  status: EtaPredictionStatusSchema,
  predictedEta: z.string().nullable(),
  predictedEtaEarliest: z.string().nullable(),
  predictedEtaLatest: z.string().nullable(),
  overridden: z.boolean(),
  createdAt: z.string(),
  confidenceLabel: z.enum(["high", "medium", "low"]).nullable(),
  requestStatus: z.string().nullable(),
});
export type EtaPredictionSummary = z.infer<typeof EtaPredictionSummarySchema>;

export function parseEtaPredictionSummary(row: Record<string, unknown>): EtaPredictionSummary {
  return EtaPredictionSummarySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    status: row.status,
    predictedEta: row.predicted_eta,
    predictedEtaEarliest: row.predicted_eta_earliest,
    predictedEtaLatest: row.predicted_eta_latest,
    overridden: row.overridden,
    createdAt: row.created_at,
    confidenceLabel: row.confidence_label,
    requestStatus: row.request_status,
  });
}

export const EtaPredictionTenantSettingSchema = z.object({
  tenantId: z.string().uuid(),
  enabled: z.boolean(),
  disabledReason: z.string().nullable(),
  disabledBy: z.string().nullable(),
  updatedAt: z.string(),
});
export type EtaPredictionTenantSetting = z.infer<typeof EtaPredictionTenantSettingSchema>;

export function parseEtaPredictionTenantSetting(row: Record<string, unknown>): EtaPredictionTenantSetting {
  return EtaPredictionTenantSettingSchema.parse({
    tenantId: row.tenant_id,
    enabled: row.enabled,
    disabledReason: row.disabled_reason,
    disabledBy: row.disabled_by,
    updatedAt: row.updated_at,
  });
}

export const RequestEtaPredictionInputSchema = z.object({
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  featureSnapshot: z.record(z.string(), z.unknown()),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestEtaPredictionInput = z.input<typeof RequestEtaPredictionInputSchema>;

export const RecordEtaPredictionOutcomeInputSchema = z.object({
  predictionId: z.string().uuid(),
  aiGovernedRequestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordEtaPredictionOutcomeInput = z.input<typeof RecordEtaPredictionOutcomeInputSchema>;

export const OverrideEtaPredictionInputSchema = z.object({
  predictionId: z.string().uuid(),
  tenantId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type OverrideEtaPredictionInput = z.input<typeof OverrideEtaPredictionInputSchema>;

export const EvaluateEtaPredictionInputSchema = z.object({
  predictionId: z.string().uuid(),
  tenantId: z.string().uuid(),
  actualArrivalAt: z.string(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type EvaluateEtaPredictionInput = z.input<typeof EvaluateEtaPredictionInputSchema>;

export const SetEtaPredictionEnabledInputSchema = z.object({
  tenantId: z.string().uuid(),
  enabled: z.boolean(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetEtaPredictionEnabledInput = z.input<typeof SetEtaPredictionEnabledInputSchema>;

export const GetEtaPredictionInputSchema = z.object({
  predictionId: z.string().uuid(),
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetEtaPredictionInput = z.input<typeof GetEtaPredictionInputSchema>;

export const ListEtaPredictionsForShipmentInputSchema = z.object({
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  limit: z.number().int().positive().max(200).default(50),
});
export type ListEtaPredictionsForShipmentInput = z.input<typeof ListEtaPredictionsForShipmentInputSchema>;
