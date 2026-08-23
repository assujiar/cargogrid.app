/**
 * Fraud and Risk Assistance mutation primitives (IAE-024, Prompt 352). Thin,
 * typed wrappers around app.request_risk_signal / app.record_risk_signal_outcome /
 * app.decide_risk_signal / app.hold_risk_signal_entity / app.release_risk_signal_entity
 * (supabase/migrations/20260806300000_create_intelligence_fraud_risk_assistance.sql).
 */

import {
  RequestRiskSignalInputSchema,
  RecordRiskSignalOutcomeInputSchema,
  DecideRiskSignalInputSchema,
  HoldRiskSignalEntityInputSchema,
  ReleaseRiskSignalEntityInputSchema,
  parseRiskSignal,
  parseRiskSignalReview,
  parseRiskSignalAction,
  type RequestRiskSignalInput,
  type RecordRiskSignalOutcomeInput,
  type DecideRiskSignalInput,
  type HoldRiskSignalEntityInput,
  type ReleaseRiskSignalEntityInput,
  type RiskSignal,
  type RiskSignalReview,
  type RiskSignalAction,
} from "../contracts/fraud-risk/fraud-risk.ts";

export interface FraudRiskMutationRpcClient {
  rpc(
    fn: "request_risk_signal" | "record_risk_signal_outcome" | "decide_risk_signal" | "hold_risk_signal_entity" | "release_risk_signal_entity",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const FRAUD_RISK_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "risk_signal_invalid_domain",
  "risk_signal_entity_type_required",
  "idempotency_key_conflict",
  "risk_signal_invalid_input_snapshot",
  "risk_signal_not_found",
  "risk_signal_outcome_already_recorded",
  "risk_signal_not_pending",
  "ai_governed_request_not_found",
  "risk_signal_request_tenant_mismatch",
  "risk_signal_wrong_feature",
  "risk_signal_correlation_mismatch",
  "risk_signal_request_not_completed",
  "risk_signal_invalid_decision",
  "risk_signal_not_reviewable",
  "risk_signal_already_reviewed",
  "risk_signal_not_confirmed",
  "risk_signal_hold_reason_required",
  "risk_signal_customer_safe_reason_required",
  "risk_signal_customer_safe_reason_not_distinct",
  "risk_signal_already_held",
  "risk_signal_release_reason_required",
  "risk_signal_action_not_active",
  "risk_signal_action_not_found",
  "risk_signal_invalid_limit",
] as const;
type KnownFraudRiskMutationErrorCode = (typeof FRAUD_RISK_KNOWN_MUTATION_ERROR_CODES)[number];
export type FraudRiskMutationErrorCode = KnownFraudRiskMutationErrorCode | "mutation_failed" | "invalid_response";

export class FraudRiskMutationError extends Error {
  readonly code: FraudRiskMutationErrorCode;

  constructor(code: FraudRiskMutationErrorCode, message: string) {
    super(message);
    this.name = "FraudRiskMutationError";
    this.code = code;
  }
}

function classifyError(message: string): FraudRiskMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (FRAUD_RISK_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownFraudRiskMutationErrorCode) : "mutation_failed";
}

function parseSignalResponse(fnName: string, data: unknown, error: { message: string } | null): RiskSignal {
  if (error) {
    throw new FraudRiskMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FraudRiskMutationError("invalid_response", `${fnName} returned no row`);
  }
  return parseRiskSignal(data as Record<string, unknown>);
}

/** The entry point the TS orchestration client calls before dispatching a real governed AI request. Idempotent per (tenant, idempotency key). */
export async function requestRiskSignal(client: FraudRiskMutationRpcClient, input: RequestRiskSignalInput): Promise<RiskSignal> {
  const parsedInput = RequestRiskSignalInputSchema.parse(input);
  const { data, error } = await client.rpc("request_risk_signal", {
    p_tenant_id: parsedInput.tenantId,
    p_risk_domain: parsedInput.riskDomain,
    p_entity_type: parsedInput.entityType,
    p_entity_id: parsedInput.entityId,
    p_input_snapshot: parsedInput.inputSnapshot,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseSignalResponse("request_risk_signal", data, error);
}

/** Called by the AI-dispatch orchestration client AFTER a real dispatchAiGovernedRequest round trip, regardless of outcome. Idempotent per (signal, governed request). */
export async function recordRiskSignalOutcome(client: FraudRiskMutationRpcClient, input: RecordRiskSignalOutcomeInput): Promise<RiskSignal> {
  const parsedInput = RecordRiskSignalOutcomeInputSchema.parse(input);
  const { data, error } = await client.rpc("record_risk_signal_outcome", {
    p_signal_id: parsedInput.signalId,
    p_ai_governed_request_id: parsedInput.aiGovernedRequestId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseSignalResponse("record_risk_signal_outcome", data, error);
}

/** The human decision, recorded separately from the AI's own signal. Reviews a signal at most once. */
export async function decideRiskSignal(client: FraudRiskMutationRpcClient, input: DecideRiskSignalInput): Promise<RiskSignalReview> {
  const parsedInput = DecideRiskSignalInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_risk_signal", {
    p_signal_id: parsedInput.signalId,
    p_tenant_id: parsedInput.tenantId,
    p_decision: parsedInput.decision,
    p_reviewer_note: parsedInput.reviewerNote ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FraudRiskMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FraudRiskMutationError("invalid_response", "decide_risk_signal returned no row");
  }
  return parseRiskSignalReview(data as Record<string, unknown>);
}

/** Requires an underlying CONFIRMED review (never a raw AI score alone). Never writes to any existing loyalty/payment/vendor/ticket/API table -- a real, self-contained governance record only. */
export async function holdRiskSignalEntity(client: FraudRiskMutationRpcClient, input: HoldRiskSignalEntityInput): Promise<RiskSignalAction> {
  const parsedInput = HoldRiskSignalEntityInputSchema.parse(input);
  const { data, error } = await client.rpc("hold_risk_signal_entity", {
    p_signal_id: parsedInput.signalId,
    p_tenant_id: parsedInput.tenantId,
    p_reason: parsedInput.reason,
    p_customer_safe_reason: parsedInput.customerSafeReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FraudRiskMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FraudRiskMutationError("invalid_response", "hold_risk_signal_entity returned no row");
  }
  return parseRiskSignalAction(data as Record<string, unknown>);
}

/** Releases an active hold -- a real, atomic state transition, never a permanent block on future holds. */
export async function releaseRiskSignalEntity(client: FraudRiskMutationRpcClient, input: ReleaseRiskSignalEntityInput): Promise<RiskSignalAction> {
  const parsedInput = ReleaseRiskSignalEntityInputSchema.parse(input);
  const { data, error } = await client.rpc("release_risk_signal_entity", {
    p_action_id: parsedInput.actionId,
    p_tenant_id: parsedInput.tenantId,
    p_release_reason: parsedInput.releaseReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FraudRiskMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FraudRiskMutationError("invalid_response", "release_risk_signal_entity returned no row");
  }
  return parseRiskSignalAction(data as Record<string, unknown>);
}
