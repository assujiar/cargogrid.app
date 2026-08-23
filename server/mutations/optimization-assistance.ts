/**
 * Optimization Assistance mutation primitives (IAE-023, Prompt 351). Thin,
 * typed wrappers around app.request_optimization_scenario /
 * app.record_optimization_scenario_outcome / app.mark_optimization_scenario_stale /
 * app.decide_optimization_scenario / app.acknowledge_optimization_recommendation_applied
 * (supabase/migrations/20260806200000_create_intelligence_optimization_assistance.sql).
 */

import {
  RequestOptimizationScenarioInputSchema,
  RecordOptimizationScenarioOutcomeInputSchema,
  MarkOptimizationScenarioStaleInputSchema,
  DecideOptimizationScenarioInputSchema,
  AcknowledgeOptimizationRecommendationAppliedInputSchema,
  parseOptimizationScenario,
  parseOptimizationScenarioDecision,
  type RequestOptimizationScenarioInput,
  type RecordOptimizationScenarioOutcomeInput,
  type MarkOptimizationScenarioStaleInput,
  type DecideOptimizationScenarioInput,
  type AcknowledgeOptimizationRecommendationAppliedInput,
  type OptimizationScenario,
  type OptimizationScenarioDecision,
} from "../contracts/optimization-assistance/optimization-assistance.ts";

export interface OptimizationAssistanceMutationRpcClient {
  rpc(
    fn:
      | "request_optimization_scenario"
      | "record_optimization_scenario_outcome"
      | "mark_optimization_scenario_stale"
      | "decide_optimization_scenario"
      | "acknowledge_optimization_recommendation_applied",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const OPTIMIZATION_ASSISTANCE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "optimization_scenario_invalid_scope_type",
  "idempotency_key_conflict",
  "optimization_scenario_invalid_input_snapshot",
  "optimization_scenario_invalid_constraint_set",
  "optimization_scenario_not_found",
  "optimization_scenario_outcome_already_recorded",
  "optimization_scenario_not_pending",
  "ai_governed_request_not_found",
  "optimization_scenario_request_tenant_mismatch",
  "optimization_scenario_wrong_feature",
  "optimization_scenario_correlation_mismatch",
  "optimization_scenario_request_not_completed",
  "optimization_scenario_stale_reason_required",
  "optimization_scenario_invalid_decision",
  "optimization_scenario_not_decidable",
  "optimization_scenario_stale",
  "optimization_scenario_already_decided",
  "optimization_scenario_invalid_option_index",
  "optimization_scenario_option_index_not_allowed",
  "optimization_scenario_decision_not_found",
  "optimization_scenario_decision_not_accepted",
  "optimization_scenario_decision_already_applied",
  "optimization_scenario_applied_reference_required",
  "optimization_scenario_invalid_limit",
] as const;
type KnownOptimizationAssistanceMutationErrorCode = (typeof OPTIMIZATION_ASSISTANCE_KNOWN_MUTATION_ERROR_CODES)[number];
export type OptimizationAssistanceMutationErrorCode = KnownOptimizationAssistanceMutationErrorCode | "mutation_failed" | "invalid_response";

export class OptimizationAssistanceMutationError extends Error {
  readonly code: OptimizationAssistanceMutationErrorCode;

  constructor(code: OptimizationAssistanceMutationErrorCode, message: string) {
    super(message);
    this.name = "OptimizationAssistanceMutationError";
    this.code = code;
  }
}

function classifyError(message: string): OptimizationAssistanceMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (OPTIMIZATION_ASSISTANCE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownOptimizationAssistanceMutationErrorCode) : "mutation_failed";
}

function parseScenarioResponse(fnName: string, data: unknown, error: { message: string } | null): OptimizationScenario {
  if (error) {
    throw new OptimizationAssistanceMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new OptimizationAssistanceMutationError("invalid_response", `${fnName} returned no row`);
  }
  return parseOptimizationScenario(data as Record<string, unknown>);
}

function parseDecisionResponse(fnName: string, data: unknown, error: { message: string } | null): OptimizationScenarioDecision {
  if (error) {
    throw new OptimizationAssistanceMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new OptimizationAssistanceMutationError("invalid_response", `${fnName} returned no row`);
  }
  return parseOptimizationScenarioDecision(data as Record<string, unknown>);
}

/** The entry point the TS orchestration client calls before dispatching a real governed AI request. Idempotent per (tenant, idempotency key). */
export async function requestOptimizationScenario(client: OptimizationAssistanceMutationRpcClient, input: RequestOptimizationScenarioInput): Promise<OptimizationScenario> {
  const parsedInput = RequestOptimizationScenarioInputSchema.parse(input);
  const { data, error } = await client.rpc("request_optimization_scenario", {
    p_tenant_id: parsedInput.tenantId,
    p_scope_type: parsedInput.scopeType,
    p_input_snapshot: parsedInput.inputSnapshot,
    p_constraint_set: parsedInput.constraintSet,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseScenarioResponse("request_optimization_scenario", data, error);
}

/** Called by the AI-dispatch orchestration client AFTER a real dispatchAiGovernedRequest round trip, regardless of outcome. Idempotent per (scenario, governed request). */
export async function recordOptimizationScenarioOutcome(client: OptimizationAssistanceMutationRpcClient, input: RecordOptimizationScenarioOutcomeInput): Promise<OptimizationScenario> {
  const parsedInput = RecordOptimizationScenarioOutcomeInputSchema.parse(input);
  const { data, error } = await client.rpc("record_optimization_scenario_outcome", {
    p_scenario_id: parsedInput.scenarioId,
    p_ai_governed_request_id: parsedInput.aiGovernedRequestId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseScenarioResponse("record_optimization_scenario_outcome", data, error);
}

/** A real, auditable mechanism marking a scenario's own results expired -- blocks any future decide_optimization_scenario call. */
export async function markOptimizationScenarioStale(client: OptimizationAssistanceMutationRpcClient, input: MarkOptimizationScenarioStaleInput): Promise<OptimizationScenario> {
  const parsedInput = MarkOptimizationScenarioStaleInputSchema.parse(input);
  const { data, error } = await client.rpc("mark_optimization_scenario_stale", {
    p_scenario_id: parsedInput.scenarioId,
    p_tenant_id: parsedInput.tenantId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseScenarioResponse("mark_optimization_scenario_stale", data, error);
}

/** The human decision, recorded separately from the AI's own recommendations. Decides a scenario at most once. */
export async function decideOptimizationScenario(client: OptimizationAssistanceMutationRpcClient, input: DecideOptimizationScenarioInput): Promise<OptimizationScenarioDecision> {
  const parsedInput = DecideOptimizationScenarioInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_optimization_scenario", {
    p_scenario_id: parsedInput.scenarioId,
    p_tenant_id: parsedInput.tenantId,
    p_decision: parsedInput.decision,
    p_selected_option_index: parsedInput.selectedOptionIndex ?? null,
    p_decision_note: parsedInput.decisionNote ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseDecisionResponse("decide_optimization_scenario", data, error);
}

/** Records that a human carried out the recommendation through the EXISTING, UNMODIFIED TMS/WMS mechanism -- never creates or mutates that record itself. */
export async function acknowledgeOptimizationRecommendationApplied(client: OptimizationAssistanceMutationRpcClient, input: AcknowledgeOptimizationRecommendationAppliedInput): Promise<OptimizationScenarioDecision> {
  const parsedInput = AcknowledgeOptimizationRecommendationAppliedInputSchema.parse(input);
  const { data, error } = await client.rpc("acknowledge_optimization_recommendation_applied", {
    p_decision_id: parsedInput.decisionId,
    p_tenant_id: parsedInput.tenantId,
    p_applied_reference: parsedInput.appliedReference,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseDecisionResponse("acknowledge_optimization_recommendation_applied", data, error);
}
