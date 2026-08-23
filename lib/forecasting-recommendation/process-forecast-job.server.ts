/**
 * Forecasting and Recommendation Assistance orchestration (IAE-025,
 * Prompt 353). The SIXTH and final Group-6 consumer of IAE-019's own
 * `dispatchAiGovernedRequest` -- reused completely unmodified (migration
 * design decision 6). This module's only job is to dispatch a real,
 * governed request over the caller-supplied scope/feature snapshot and
 * sync the linked app.forecast_jobs row to the real outcome either way,
 * mirroring processOcrDocumentJob (IAE-021)/processEtaPrediction
 * (IAE-022)/processOptimizationScenario (IAE-023)/processRiskSignal
 * (IAE-024)'s own "always sync, success or failure" shape.
 *
 * Must be called with a service-role client: dispatchAiGovernedRequest's own
 * internal record_ai_governed_request_outcome call is granted to
 * service_role only (IAE-019).
 */

import { recordForecastJobOutcome, type ForecastingRecommendationMutationRpcClient } from "../../server/mutations/forecasting-recommendation.ts";
import type { ForecastJob } from "../../server/contracts/forecasting-recommendation/forecasting-recommendation.ts";
import { dispatchAiGovernedRequest, type DispatchAiGovernedRequestRpcClient, type AiGovernanceDispatchUrlSafetyChecker } from "../ai-governance/dispatch-ai-governed-request.server.ts";

export type ProcessForecastJobClient = DispatchAiGovernedRequestRpcClient & ForecastingRecommendationMutationRpcClient;

export interface ProcessForecastJobOptions {
  readonly tenantId: string;
  readonly jobId: string;
  readonly scopeSnapshot: Record<string, unknown>;
  readonly featureSnapshot: Record<string, unknown>;
  readonly horizonDays: number;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
}

export interface ProcessForecastJobResult {
  readonly requestId: string;
  readonly success: boolean;
  readonly job: ForecastJob;
  readonly errorMessage: string | null;
}

/**
 * Real, synchronous end-to-end flow: dispatch the caller-supplied scope/
 * feature snapshot -> sync the job's own status either way. Never throws
 * for a delivery-side failure -- dispatchAiGovernedRequest itself already
 * turns those into a real, recorded `failed` outcome and a `success: false`
 * result, which this function passes through after syncing the job to its
 * own terminal `failed` status (predicted_value stays null). Throws only
 * for whatever dispatchAiGovernedRequest itself still throws for (no active
 * connection configured at all) or a genuine precondition failure surfaced
 * by record_forecast_job_outcome.
 */
export async function processForecastJob(client: ProcessForecastJobClient, options: ProcessForecastJobOptions, checkUrlSafety?: AiGovernanceDispatchUrlSafetyChecker): Promise<ProcessForecastJobResult> {
  const { tenantId, jobId, scopeSnapshot, featureSnapshot, horizonDays, actorAuthUserId, actorLabel } = options;

  const dispatch = await dispatchAiGovernedRequest(
    client,
    {
      tenantId,
      actorAuthUserId,
      actorLabel,
      featureCode: "forecasting_recommendation",
      correlationRecordType: "forecast_job",
      correlationRecordId: jobId,
      promptPayload: { scopeSnapshot, featureSnapshot, horizonDays },
    },
    checkUrlSafety,
  );

  const job = await recordForecastJobOutcome(client, {
    jobId,
    aiGovernedRequestId: dispatch.requestId,
    actorAuthUserId,
    actorLabel,
  });

  return { requestId: dispatch.requestId, success: dispatch.success, job, errorMessage: dispatch.errorMessage };
}
