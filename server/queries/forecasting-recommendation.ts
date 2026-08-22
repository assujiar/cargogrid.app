/**
 * Forecasting and Recommendation Assistance queries (IAE-025, Prompt 353).
 * Thin, typed wrappers around app.get_forecast_job / app.list_forecast_jobs_for_tenant
 * (supabase/migrations/20260806400000_create_intelligence_forecasting_recommendation.sql).
 */

import {
  GetForecastJobInputSchema,
  ListForecastJobsForTenantInputSchema,
  parseForecastJobDetail,
  parseForecastJobSummary,
  type GetForecastJobInput,
  type ListForecastJobsForTenantInput,
  type ForecastJobDetail,
  type ForecastJobSummary,
} from "../contracts/forecasting-recommendation/forecasting-recommendation.ts";

export interface ForecastingRecommendationQueryRpcClient {
  rpc(fn: "get_forecast_job" | "list_forecast_jobs_for_tenant", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class ForecastingRecommendationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ForecastingRecommendationQueryError";
  }
}

/** Authority: AI:View. Small-cohort-suppressed jobs mask customer-identifying fields (at any nesting depth) unless the actor also holds AI:Approve. */
export async function getForecastJob(client: ForecastingRecommendationQueryRpcClient, input: GetForecastJobInput): Promise<ForecastJobDetail | null> {
  const parsedInput = GetForecastJobInputSchema.parse(input);
  const { data, error } = await client.rpc("get_forecast_job", {
    p_job_id: parsedInput.jobId,
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ForecastingRecommendationQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseForecastJobDetail(row as Record<string, unknown>);
}

/** Authority: AI:View. */
export async function listForecastJobsForTenant(client: ForecastingRecommendationQueryRpcClient, input: ListForecastJobsForTenantInput): Promise<ForecastJobSummary[]> {
  const parsedInput = ListForecastJobsForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_forecast_jobs_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_forecast_type: parsedInput.forecastType,
    p_status: parsedInput.status,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new ForecastingRecommendationQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ForecastingRecommendationQueryError("list_forecast_jobs_for_tenant returned a non-array result");
  }
  return data.map((row) => parseForecastJobSummary(row as Record<string, unknown>));
}
