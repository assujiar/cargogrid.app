/**
 * Forecasting and Recommendation Assistance mutation primitives (IAE-025,
 * Prompt 353). Thin, typed wrappers around app.request_forecast_job /
 * app.record_forecast_job_outcome / app.record_forecast_planning_decision /
 * app.evaluate_forecast_job
 * (supabase/migrations/20260806400000_create_intelligence_forecasting_recommendation.sql).
 */

import {
  RequestForecastJobInputSchema,
  RecordForecastJobOutcomeInputSchema,
  RecordForecastPlanningDecisionInputSchema,
  EvaluateForecastJobInputSchema,
  parseForecastJob,
  parseForecastJobFeedback,
  type RequestForecastJobInput,
  type RecordForecastJobOutcomeInput,
  type RecordForecastPlanningDecisionInput,
  type EvaluateForecastJobInput,
  type ForecastJob,
  type ForecastJobFeedbackRecord,
} from "../contracts/forecasting-recommendation/forecasting-recommendation.ts";

export interface ForecastingRecommendationMutationRpcClient {
  rpc(
    fn: "request_forecast_job" | "record_forecast_job_outcome" | "record_forecast_planning_decision" | "evaluate_forecast_job",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const FORECASTING_RECOMMENDATION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "forecast_job_invalid_type",
  "forecast_job_invalid_horizon",
  "idempotency_key_conflict",
  "forecast_job_invalid_scope_snapshot",
  "forecast_job_invalid_feature_snapshot",
  "forecast_job_not_found",
  "forecast_job_outcome_already_recorded",
  "forecast_job_not_pending",
  "ai_governed_request_not_found",
  "forecast_job_request_tenant_mismatch",
  "forecast_job_wrong_feature",
  "forecast_job_correlation_mismatch",
  "forecast_job_request_not_completed",
  "forecast_job_invalid_feedback",
  "forecast_job_not_feedback_eligible",
  "forecast_job_already_has_feedback",
  "forecast_job_not_evaluable",
  "forecast_job_already_evaluated",
  "forecast_job_invalid_limit",
] as const;
type KnownForecastingRecommendationMutationErrorCode = (typeof FORECASTING_RECOMMENDATION_KNOWN_MUTATION_ERROR_CODES)[number];
export type ForecastingRecommendationMutationErrorCode = KnownForecastingRecommendationMutationErrorCode | "mutation_failed" | "invalid_response";

export class ForecastingRecommendationMutationError extends Error {
  readonly code: ForecastingRecommendationMutationErrorCode;

  constructor(code: ForecastingRecommendationMutationErrorCode, message: string) {
    super(message);
    this.name = "ForecastingRecommendationMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ForecastingRecommendationMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (FORECASTING_RECOMMENDATION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownForecastingRecommendationMutationErrorCode) : "mutation_failed";
}

function parseJobResponse(fnName: string, data: unknown, error: { message: string } | null): ForecastJob {
  if (error) {
    throw new ForecastingRecommendationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ForecastingRecommendationMutationError("invalid_response", `${fnName} returned no row`);
  }
  return parseForecastJob(data as Record<string, unknown>);
}

/** The entry point the TS orchestration client calls before dispatching a real governed AI request. Idempotent per (tenant, idempotency key). */
export async function requestForecastJob(client: ForecastingRecommendationMutationRpcClient, input: RequestForecastJobInput): Promise<ForecastJob> {
  const parsedInput = RequestForecastJobInputSchema.parse(input);
  const { data, error } = await client.rpc("request_forecast_job", {
    p_tenant_id: parsedInput.tenantId,
    p_forecast_type: parsedInput.forecastType,
    p_scenario_label: parsedInput.scenarioLabel ?? "",
    p_scope_snapshot: parsedInput.scopeSnapshot,
    p_feature_snapshot: parsedInput.featureSnapshot,
    p_horizon_days: parsedInput.horizonDays,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseJobResponse("request_forecast_job", data, error);
}

/** Called by the AI-dispatch orchestration client AFTER a real dispatchAiGovernedRequest round trip, regardless of outcome. Idempotent per (job, governed request). */
export async function recordForecastJobOutcome(client: ForecastingRecommendationMutationRpcClient, input: RecordForecastJobOutcomeInput): Promise<ForecastJob> {
  const parsedInput = RecordForecastJobOutcomeInputSchema.parse(input);
  const { data, error } = await client.rpc("record_forecast_job_outcome", {
    p_job_id: parsedInput.jobId,
    p_ai_governed_request_id: parsedInput.aiGovernedRequestId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseJobResponse("record_forecast_job_outcome", data, error);
}

/** A manager's own usefulness judgment plus a free-text planning-decision note -- never a write into any commitment/budget/vendor-award/maintenance-order table. Recorded at most once per job. */
export async function recordForecastPlanningDecision(client: ForecastingRecommendationMutationRpcClient, input: RecordForecastPlanningDecisionInput): Promise<ForecastJobFeedbackRecord> {
  const parsedInput = RecordForecastPlanningDecisionInputSchema.parse(input);
  const { data, error } = await client.rpc("record_forecast_planning_decision", {
    p_job_id: parsedInput.jobId,
    p_tenant_id: parsedInput.tenantId,
    p_feedback: parsedInput.feedback,
    p_planning_decision_note: parsedInput.planningDecisionNote ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ForecastingRecommendationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ForecastingRecommendationMutationError("invalid_response", "record_forecast_planning_decision returned no row");
  }
  return parseForecastJobFeedback(data as Record<string, unknown>);
}

export interface ForecastJobEvaluationResult {
  readonly id: string;
  readonly tenantId: string;
  readonly forecastJobId: string;
  readonly actualOutcomeValue: number;
  readonly errorPct: number | null;
  readonly createdAt: string;
}

/** Records real observed-outcome accuracy/drift evidence -- at most once per job. */
export async function evaluateForecastJob(client: ForecastingRecommendationMutationRpcClient, input: EvaluateForecastJobInput): Promise<ForecastJobEvaluationResult> {
  const parsedInput = EvaluateForecastJobInputSchema.parse(input);
  const { data, error } = await client.rpc("evaluate_forecast_job", {
    p_job_id: parsedInput.jobId,
    p_tenant_id: parsedInput.tenantId,
    p_actual_outcome_value: parsedInput.actualOutcomeValue,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ForecastingRecommendationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ForecastingRecommendationMutationError("invalid_response", "evaluate_forecast_job returned no row");
  }
  const row = data as Record<string, unknown>;
  return {
    id: row.id as string,
    tenantId: row.tenant_id as string,
    forecastJobId: row.forecast_job_id as string,
    actualOutcomeValue: Number(row.actual_outcome_value),
    errorPct: row.error_pct === null ? null : Number(row.error_pct),
    createdAt: row.created_at as string,
  };
}
