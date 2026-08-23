/**
 * Scale-Up Architecture contract (IAE-034, Prompt 362). Mirrors
 * supabase/migrations/20260808200000_create_intelligence_scale_up_architecture.sql's
 * app.workload_capacity_profiles / app.workload_backpressure_events /
 * app.scaling_recommendations shapes, and their configure/evaluate/
 * recommend/status/read RPCs.
 */

import { z } from "zod";

export const WORKLOAD_TYPES = ["oltp", "analytics", "reports", "ai", "webhooks", "import_export", "notifications"] as const;
export const WorkloadTypeSchema = z.enum(WORKLOAD_TYPES);
export type WorkloadType = z.infer<typeof WorkloadTypeSchema>;

export const BACKPRESSURE_ACTIONS = ["within_budget", "backpressure_applied", "no_budget_configured"] as const;
export const BackpressureActionSchema = z.enum(BACKPRESSURE_ACTIONS);
export type BackpressureAction = z.infer<typeof BackpressureActionSchema>;

export const SCALING_RECOMMENDATION_TYPES = ["dedicated_deployment", "read_model", "partitioning", "architecture_review"] as const;
export const ScalingRecommendationTypeSchema = z.enum(SCALING_RECOMMENDATION_TYPES);
export type ScalingRecommendationType = z.infer<typeof ScalingRecommendationTypeSchema>;

export const SCALING_RECOMMENDATION_STATUSES = ["open", "acknowledged", "dismissed", "implemented"] as const;
export const ScalingRecommendationStatusSchema = z.enum(SCALING_RECOMMENDATION_STATUSES);
export type ScalingRecommendationStatus = z.infer<typeof ScalingRecommendationStatusSchema>;

export const WorkloadCapacityProfileSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  workloadType: WorkloadTypeSchema,
  budgetValue: z.number(),
  evaluationWindowMinutes: z.number().int(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  recordVersion: z.number().int(),
});
export type WorkloadCapacityProfile = z.infer<typeof WorkloadCapacityProfileSchema>;

export function parseWorkloadCapacityProfile(row: Record<string, unknown>): WorkloadCapacityProfile {
  return WorkloadCapacityProfileSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    workloadType: row.workload_type,
    budgetValue: row.budget_value,
    evaluationWindowMinutes: row.evaluation_window_minutes,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    recordVersion: row.record_version,
  });
}

export const WorkloadBackpressureEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  workloadType: WorkloadTypeSchema,
  observedValue: z.number(),
  budgetValue: z.number().nullable(),
  actionTaken: BackpressureActionSchema,
  alertIncidentId: z.string().uuid().nullable(),
  occurredAt: z.string(),
});
export type WorkloadBackpressureEvent = z.infer<typeof WorkloadBackpressureEventSchema>;

export function parseWorkloadBackpressureEvent(row: Record<string, unknown>): WorkloadBackpressureEvent {
  return WorkloadBackpressureEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    workloadType: row.workload_type,
    observedValue: row.observed_value,
    budgetValue: row.budget_value,
    actionTaken: row.action_taken,
    alertIncidentId: row.alert_incident_id,
    occurredAt: row.occurred_at,
  });
}

export const ScalingRecommendationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  workloadType: WorkloadTypeSchema,
  recommendationType: ScalingRecommendationTypeSchema,
  rationale: z.string(),
  status: ScalingRecommendationStatusSchema,
  acknowledgedByAuthUserId: z.string().uuid().nullable(),
  acknowledgedBy: z.string().nullable(),
  acknowledgedAt: z.string().nullable(),
  dismissedReason: z.string().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  recordVersion: z.number().int(),
});
export type ScalingRecommendation = z.infer<typeof ScalingRecommendationSchema>;

export function parseScalingRecommendation(row: Record<string, unknown>): ScalingRecommendation {
  return ScalingRecommendationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    workloadType: row.workload_type,
    recommendationType: row.recommendation_type,
    rationale: row.rationale,
    status: row.status,
    acknowledgedByAuthUserId: row.acknowledged_by_auth_user_id,
    acknowledgedBy: row.acknowledged_by,
    acknowledgedAt: row.acknowledged_at,
    dismissedReason: row.dismissed_reason,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    recordVersion: row.record_version,
  });
}

export const SetWorkloadCapacityProfileInputSchema = z.object({
  tenantId: z.string().uuid().nullable(),
  workloadType: WorkloadTypeSchema,
  budgetValue: z.number().positive(),
  evaluationWindowMinutes: z.number().int().min(1).max(10080),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetWorkloadCapacityProfileInput = z.input<typeof SetWorkloadCapacityProfileInputSchema>;

export const GenerateScalingRecommendationInputSchema = z.object({
  tenantId: z.string().uuid(),
  workloadType: WorkloadTypeSchema,
  recommendationType: ScalingRecommendationTypeSchema,
  rationale: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type GenerateScalingRecommendationInput = z.input<typeof GenerateScalingRecommendationInputSchema>;

export const SetScalingRecommendationStatusInputSchema = z.object({
  recommendationId: z.string().uuid(),
  newStatus: ScalingRecommendationStatusSchema,
  dismissedReason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetScalingRecommendationStatusInput = z.input<typeof SetScalingRecommendationStatusInputSchema>;
