/**
 * Predictive ETA mutation primitives (IAE-022, Prompt 350). Thin, typed
 * wrappers around app.request_eta_prediction / app.record_eta_prediction_outcome /
 * app.override_eta_prediction / app.evaluate_eta_prediction / app.set_eta_prediction_enabled
 * (supabase/migrations/20260806100000_create_intelligence_predictive_eta.sql).
 */

import {
  RequestEtaPredictionInputSchema,
  RecordEtaPredictionOutcomeInputSchema,
  OverrideEtaPredictionInputSchema,
  EvaluateEtaPredictionInputSchema,
  SetEtaPredictionEnabledInputSchema,
  parseEtaPrediction,
  parseEtaPredictionTenantSetting,
  type RequestEtaPredictionInput,
  type RecordEtaPredictionOutcomeInput,
  type OverrideEtaPredictionInput,
  type EvaluateEtaPredictionInput,
  type SetEtaPredictionEnabledInput,
  type EtaPrediction,
  type EtaPredictionTenantSetting,
} from "../contracts/eta-prediction/eta-prediction.ts";

export interface EtaPredictionMutationRpcClient {
  rpc(
    fn: "request_eta_prediction" | "record_eta_prediction_outcome" | "override_eta_prediction" | "evaluate_eta_prediction" | "set_eta_prediction_enabled",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const ETA_PREDICTION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "eta_prediction_disabled_for_tenant",
  "idempotency_key_conflict",
  "eta_prediction_shipment_not_found",
  "eta_prediction_shipment_not_eligible",
  "eta_prediction_shipment_already_delivered",
  "eta_prediction_invalid_feature_snapshot",
  "eta_prediction_not_found",
  "eta_prediction_outcome_already_recorded",
  "eta_prediction_not_pending",
  "ai_governed_request_not_found",
  "eta_prediction_request_tenant_mismatch",
  "eta_prediction_wrong_feature",
  "eta_prediction_correlation_mismatch",
  "eta_prediction_request_not_completed",
  "eta_prediction_override_reason_required",
  "eta_prediction_already_overridden",
  "eta_prediction_not_evaluable",
  "eta_prediction_already_evaluated",
  "eta_prediction_disable_reason_required",
  "eta_prediction_invalid_limit",
] as const;
type KnownEtaPredictionMutationErrorCode = (typeof ETA_PREDICTION_KNOWN_MUTATION_ERROR_CODES)[number];
export type EtaPredictionMutationErrorCode = KnownEtaPredictionMutationErrorCode | "mutation_failed" | "invalid_response";

export class EtaPredictionMutationError extends Error {
  readonly code: EtaPredictionMutationErrorCode;

  constructor(code: EtaPredictionMutationErrorCode, message: string) {
    super(message);
    this.name = "EtaPredictionMutationError";
    this.code = code;
  }
}

function classifyError(message: string): EtaPredictionMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ETA_PREDICTION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownEtaPredictionMutationErrorCode) : "mutation_failed";
}

function parsePredictionResponse(fnName: string, data: unknown, error: { message: string } | null): EtaPrediction {
  if (error) {
    throw new EtaPredictionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EtaPredictionMutationError("invalid_response", `${fnName} returned no row`);
  }
  return parseEtaPrediction(data as Record<string, unknown>);
}

/** The entry point the TS orchestration client calls before dispatching a real governed AI request. Idempotent per (tenant, idempotency key). */
export async function requestEtaPrediction(client: EtaPredictionMutationRpcClient, input: RequestEtaPredictionInput): Promise<EtaPrediction> {
  const parsedInput = RequestEtaPredictionInputSchema.parse(input);
  const { data, error } = await client.rpc("request_eta_prediction", {
    p_tenant_id: parsedInput.tenantId,
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_feature_snapshot: parsedInput.featureSnapshot,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parsePredictionResponse("request_eta_prediction", data, error);
}

/** Called by the AI-dispatch orchestration client AFTER a real dispatchAiGovernedRequest round trip, regardless of outcome. Idempotent per (prediction, governed request). */
export async function recordEtaPredictionOutcome(client: EtaPredictionMutationRpcClient, input: RecordEtaPredictionOutcomeInput): Promise<EtaPrediction> {
  const parsedInput = RecordEtaPredictionOutcomeInputSchema.parse(input);
  const { data, error } = await client.rpc("record_eta_prediction_outcome", {
    p_prediction_id: parsedInput.predictionId,
    p_ai_governed_request_id: parsedInput.aiGovernedRequestId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parsePredictionResponse("record_eta_prediction_outcome", data, error);
}

/** A one-way, human-authored distrust flag -- never edits predicted_eta itself. */
export async function overrideEtaPrediction(client: EtaPredictionMutationRpcClient, input: OverrideEtaPredictionInput): Promise<EtaPrediction> {
  const parsedInput = OverrideEtaPredictionInputSchema.parse(input);
  const { data, error } = await client.rpc("override_eta_prediction", {
    p_prediction_id: parsedInput.predictionId,
    p_tenant_id: parsedInput.tenantId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parsePredictionResponse("override_eta_prediction", data, error);
}

export interface EtaPredictionEvaluationResult {
  readonly id: string;
  readonly tenantId: string;
  readonly etaPredictionId: string;
  readonly actualArrivalAt: string;
  readonly errorMinutes: number | null;
  readonly withinConfidenceBand: boolean | null;
  readonly createdAt: string;
}

/** Records real accuracy/drift evidence -- at most once per prediction. */
export async function evaluateEtaPrediction(client: EtaPredictionMutationRpcClient, input: EvaluateEtaPredictionInput): Promise<EtaPredictionEvaluationResult> {
  const parsedInput = EvaluateEtaPredictionInputSchema.parse(input);
  const { data, error } = await client.rpc("evaluate_eta_prediction", {
    p_prediction_id: parsedInput.predictionId,
    p_tenant_id: parsedInput.tenantId,
    p_actual_arrival_at: parsedInput.actualArrivalAt,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EtaPredictionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EtaPredictionMutationError("invalid_response", "evaluate_eta_prediction returned no row");
  }
  const row = data as Record<string, unknown>;
  return {
    id: row.id as string,
    tenantId: row.tenant_id as string,
    etaPredictionId: row.eta_prediction_id as string,
    actualArrivalAt: row.actual_arrival_at as string,
    errorMinutes: row.error_minutes === null ? null : Number(row.error_minutes),
    withinConfidenceBand: row.within_confidence_band as boolean | null,
    createdAt: row.created_at as string,
  };
}

/** A real, persisted tenant-wide governance action (AI:Approve-gated) -- never a soft client-side flag. */
export async function setEtaPredictionEnabled(client: EtaPredictionMutationRpcClient, input: SetEtaPredictionEnabledInput): Promise<EtaPredictionTenantSetting> {
  const parsedInput = SetEtaPredictionEnabledInputSchema.parse(input);
  const { data, error } = await client.rpc("set_eta_prediction_enabled", {
    p_tenant_id: parsedInput.tenantId,
    p_enabled: parsedInput.enabled,
    p_reason: parsedInput.reason ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EtaPredictionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EtaPredictionMutationError("invalid_response", "set_eta_prediction_enabled returned no row");
  }
  return parseEtaPredictionTenantSetting(data as Record<string, unknown>);
}
