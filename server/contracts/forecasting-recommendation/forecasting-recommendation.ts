/**
 * Forecasting and Recommendation Assistance contract (IAE-025, Prompt 353).
 * Mirrors
 * supabase/migrations/20260806400000_create_intelligence_forecasting_recommendation.sql's
 * app.forecast_jobs/app.forecast_job_feedback/app.forecast_job_evaluations
 * shapes and their request/record/feedback/evaluate/get/list RPCs.
 */

import { z } from "zod";

export const FORECAST_TYPES = ["demand", "revenue", "churn", "vendor_recommendation", "predictive_maintenance"] as const;
export const ForecastTypeSchema = z.enum(FORECAST_TYPES);
export type ForecastType = z.infer<typeof ForecastTypeSchema>;

export const FORECAST_JOB_STATUSES = ["pending", "succeeded", "failed", "insufficient_data"] as const;
export const ForecastJobStatusSchema = z.enum(FORECAST_JOB_STATUSES);
export type ForecastJobStatus = z.infer<typeof ForecastJobStatusSchema>;

export const FORECAST_FEEDBACK_VALUES = ["useful", "not_useful", "inaccurate"] as const;
export const ForecastFeedbackSchema = z.enum(FORECAST_FEEDBACK_VALUES);
export type ForecastFeedback = z.infer<typeof ForecastFeedbackSchema>;

/** The raw app.forecast_jobs row shape, as returned by request/record. */
export const ForecastJobSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  forecastType: ForecastTypeSchema,
  scenarioLabel: z.string(),
  scopeSnapshot: z.record(z.string(), z.unknown()),
  featureSnapshot: z.record(z.string(), z.unknown()),
  horizonDays: z.number().int(),
  aiGovernedRequestId: z.string().uuid().nullable(),
  status: ForecastJobStatusSchema,
  predictedValue: z.coerce.number().nullable(),
  cohortSize: z.number().int().nullable(),
  isSmallCohortSuppressed: z.boolean(),
  dataQualityNote: z.string().nullable(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
  completedAt: z.string().nullable(),
});
export type ForecastJob = z.infer<typeof ForecastJobSchema>;

export function parseForecastJob(row: Record<string, unknown>): ForecastJob {
  return ForecastJobSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    forecastType: row.forecast_type,
    scenarioLabel: row.scenario_label,
    scopeSnapshot: row.scope_snapshot,
    featureSnapshot: row.feature_snapshot,
    horizonDays: row.horizon_days,
    aiGovernedRequestId: row.ai_governed_request_id,
    status: row.status,
    predictedValue: row.predicted_value,
    cohortSize: row.cohort_size,
    isSmallCohortSuppressed: row.is_small_cohort_suppressed,
    dataQualityNote: row.data_quality_note,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
    completedAt: row.completed_at,
  });
}

export const ForecastJobFeedbackRecordSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  forecastJobId: z.string().uuid(),
  feedback: ForecastFeedbackSchema,
  planningDecisionNote: z.string().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string(),
});
export type ForecastJobFeedbackRecord = z.infer<typeof ForecastJobFeedbackRecordSchema>;

export function parseForecastJobFeedback(row: Record<string, unknown>): ForecastJobFeedbackRecord {
  return ForecastJobFeedbackRecordSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    forecastJobId: row.forecast_job_id,
    feedback: row.feedback,
    planningDecisionNote: row.planning_decision_note,
    decidedBy: row.decided_by,
    decidedAt: row.decided_at,
  });
}

/** app.get_forecast_job's own wider read-path shape -- joins in the governed request's own (possibly masked) evidence, feedback, and any evaluation. */
export const ForecastJobDetailSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  forecastType: ForecastTypeSchema,
  scenarioLabel: z.string(),
  scopeSnapshot: z.record(z.string(), z.unknown()),
  featureSnapshot: z.record(z.string(), z.unknown()),
  horizonDays: z.number().int(),
  status: ForecastJobStatusSchema,
  predictedValue: z.coerce.number().nullable(),
  cohortSize: z.number().int().nullable(),
  isSmallCohortSuppressed: z.boolean(),
  dataQualityNote: z.string().nullable(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
  completedAt: z.string().nullable(),
  outputPayload: z.record(z.string(), z.unknown()).nullable(),
  outputPayloadMasked: z.boolean(),
  confidenceLabel: z.enum(["high", "medium", "low"]).nullable(),
  modelVersion: z.string().nullable(),
  requestStatus: z.string().nullable(),
  feedback: ForecastFeedbackSchema.nullable(),
  planningDecisionNote: z.string().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  actualOutcomeValue: z.coerce.number().nullable(),
  errorPct: z.coerce.number().nullable(),
});
export type ForecastJobDetail = z.infer<typeof ForecastJobDetailSchema>;

export function parseForecastJobDetail(row: Record<string, unknown>): ForecastJobDetail {
  return ForecastJobDetailSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    forecastType: row.forecast_type,
    scenarioLabel: row.scenario_label,
    scopeSnapshot: row.scope_snapshot,
    featureSnapshot: row.feature_snapshot,
    horizonDays: row.horizon_days,
    status: row.status,
    predictedValue: row.predicted_value,
    cohortSize: row.cohort_size,
    isSmallCohortSuppressed: row.is_small_cohort_suppressed,
    dataQualityNote: row.data_quality_note,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
    completedAt: row.completed_at,
    outputPayload: row.output_payload,
    outputPayloadMasked: row.output_payload_masked,
    confidenceLabel: row.confidence_label,
    modelVersion: row.model_version,
    requestStatus: row.request_status,
    feedback: row.feedback,
    planningDecisionNote: row.planning_decision_note,
    decidedBy: row.decided_by,
    decidedAt: row.decided_at,
    actualOutcomeValue: row.actual_outcome_value,
    errorPct: row.error_pct,
  });
}

export const ForecastJobSummarySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  forecastType: ForecastTypeSchema,
  scenarioLabel: z.string(),
  status: ForecastJobStatusSchema,
  predictedValue: z.coerce.number().nullable(),
  isSmallCohortSuppressed: z.boolean(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
  confidenceLabel: z.enum(["high", "medium", "low"]).nullable(),
  feedback: ForecastFeedbackSchema.nullable(),
});
export type ForecastJobSummary = z.infer<typeof ForecastJobSummarySchema>;

export function parseForecastJobSummary(row: Record<string, unknown>): ForecastJobSummary {
  return ForecastJobSummarySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    forecastType: row.forecast_type,
    scenarioLabel: row.scenario_label,
    status: row.status,
    predictedValue: row.predicted_value,
    isSmallCohortSuppressed: row.is_small_cohort_suppressed,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
    confidenceLabel: row.confidence_label,
    feedback: row.feedback,
  });
}

export const RequestForecastJobInputSchema = z.object({
  tenantId: z.string().uuid(),
  forecastType: ForecastTypeSchema,
  scenarioLabel: z.string().nullable().default(null),
  scopeSnapshot: z.record(z.string(), z.unknown()),
  featureSnapshot: z.record(z.string(), z.unknown()),
  horizonDays: z.number().int().positive().max(1095),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestForecastJobInput = z.input<typeof RequestForecastJobInputSchema>;

export const RecordForecastJobOutcomeInputSchema = z.object({
  jobId: z.string().uuid(),
  aiGovernedRequestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordForecastJobOutcomeInput = z.input<typeof RecordForecastJobOutcomeInputSchema>;

export const RecordForecastPlanningDecisionInputSchema = z.object({
  jobId: z.string().uuid(),
  tenantId: z.string().uuid(),
  feedback: ForecastFeedbackSchema,
  planningDecisionNote: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordForecastPlanningDecisionInput = z.input<typeof RecordForecastPlanningDecisionInputSchema>;

export const EvaluateForecastJobInputSchema = z.object({
  jobId: z.string().uuid(),
  tenantId: z.string().uuid(),
  actualOutcomeValue: z.number(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type EvaluateForecastJobInput = z.input<typeof EvaluateForecastJobInputSchema>;

export const GetForecastJobInputSchema = z.object({
  jobId: z.string().uuid(),
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetForecastJobInput = z.input<typeof GetForecastJobInputSchema>;

export const ListForecastJobsForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  forecastType: ForecastTypeSchema.nullable().default(null),
  status: ForecastJobStatusSchema.nullable().default(null),
  limit: z.number().int().positive().max(200).default(50),
});
export type ListForecastJobsForTenantInput = z.input<typeof ListForecastJobsForTenantInputSchema>;
