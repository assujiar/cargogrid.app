/**
 * Scale-Up Architecture mutation primitives (IAE-034, Prompt 362). Thin,
 * typed wrappers around app.set_workload_capacity_profile /
 * app.generate_scaling_recommendation / app.set_scaling_recommendation_status
 * (supabase/migrations/20260808200000_create_intelligence_scale_up_architecture.sql).
 * app.evaluate_workload_budget is service_role-only, system-to-system
 * telemetry evaluation with no actor parameter -- intentionally NOT wrapped
 * here, mirroring app.record_observability_signal's own precedent.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  SetWorkloadCapacityProfileInputSchema,
  GenerateScalingRecommendationInputSchema,
  SetScalingRecommendationStatusInputSchema,
  parseWorkloadCapacityProfile,
  parseScalingRecommendation,
  type SetWorkloadCapacityProfileInput,
  type GenerateScalingRecommendationInput,
  type SetScalingRecommendationStatusInput,
  type WorkloadCapacityProfile,
  type ScalingRecommendation,
} from "../contracts/scale-up-architecture/scale-up-architecture.ts";

export type ScaleUpArchitectureMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const SCALE_UP_ARCHITECTURE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "workload_invalid_type",
  "workload_invalid_budget",
  "workload_invalid_window",
  "scaling_recommendation_invalid_type",
  "scaling_recommendation_rationale_required",
  "scaling_recommendation_already_dedicated",
  "scaling_recommendation_not_found",
  "scaling_recommendation_invalid_transition",
  "scaling_recommendation_dismissed_reason_required",
] as const;
type KnownScaleUpArchitectureMutationErrorCode = (typeof SCALE_UP_ARCHITECTURE_KNOWN_MUTATION_ERROR_CODES)[number];
export type ScaleUpArchitectureMutationErrorCode = KnownScaleUpArchitectureMutationErrorCode | "mutation_failed" | "invalid_response";

export class ScaleUpArchitectureMutationError extends Error {
  readonly code: ScaleUpArchitectureMutationErrorCode;

  constructor(code: ScaleUpArchitectureMutationErrorCode, message: string) {
    super(message);
    this.name = "ScaleUpArchitectureMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ScaleUpArchitectureMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (SCALE_UP_ARCHITECTURE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownScaleUpArchitectureMutationErrorCode)
    : "mutation_failed";
}

/** Authority: MON:Configure (tenant-scoped) or Supreme Admin (platform-wide, tenantId null). */
export async function setWorkloadCapacityProfile(client: ScaleUpArchitectureMutationRpcClient, input: SetWorkloadCapacityProfileInput): Promise<WorkloadCapacityProfile> {
  const parsedInput = SetWorkloadCapacityProfileInputSchema.parse(input);
  const { data, error } = await client.rpc("set_workload_capacity_profile", {
    p_tenant_id: parsedInput.tenantId,
    p_workload_type: parsedInput.workloadType,
    p_budget_value: parsedInput.budgetValue,
    p_evaluation_window_minutes: parsedInput.evaluationWindowMinutes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ScaleUpArchitectureMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ScaleUpArchitectureMutationError("invalid_response", "set_workload_capacity_profile returned no row");
  }
  return parseWorkloadCapacityProfile(data as Record<string, unknown>);
}

/** Authority: MON:Configure. A dedicated_deployment recommendation is rejected if the tenant already has an active dedicated deployment (IAE-032). */
export async function generateScalingRecommendation(client: ScaleUpArchitectureMutationRpcClient, input: GenerateScalingRecommendationInput): Promise<ScalingRecommendation> {
  const parsedInput = GenerateScalingRecommendationInputSchema.parse(input);
  const { data, error } = await client.rpc("generate_scaling_recommendation", {
    p_tenant_id: parsedInput.tenantId,
    p_workload_type: parsedInput.workloadType,
    p_recommendation_type: parsedInput.recommendationType,
    p_rationale: parsedInput.rationale,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ScaleUpArchitectureMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ScaleUpArchitectureMutationError("invalid_response", "generate_scaling_recommendation returned no row");
  }
  return parseScalingRecommendation(data as Record<string, unknown>);
}

/** Authority: MON:Configure. Enforces the real, ordered transition graph (open -> acknowledged/dismissed; acknowledged -> dismissed/implemented). */
export async function setScalingRecommendationStatus(client: ScaleUpArchitectureMutationRpcClient, input: SetScalingRecommendationStatusInput): Promise<ScalingRecommendation> {
  const parsedInput = SetScalingRecommendationStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_scaling_recommendation_status", {
    p_recommendation_id: parsedInput.recommendationId,
    p_new_status: parsedInput.newStatus,
    p_dismissed_reason: parsedInput.dismissedReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ScaleUpArchitectureMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ScaleUpArchitectureMutationError("invalid_response", "set_scaling_recommendation_status returned no row");
  }
  return parseScalingRecommendation(data as Record<string, unknown>);
}
