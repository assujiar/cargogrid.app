/**
 * AI Governance Provider Boundary mutation primitives (IAE-019, Prompt 347).
 * Thin, typed wrappers around app.request_ai_governed_action /
 * app.record_ai_governed_request_outcome / app.request_ai_output_approval /
 * app.decide_ai_output_approval
 * (supabase/migrations/20260805060000_create_intelligence_ai_governance_provider_boundary.sql).
 */

import {
  RequestAiGovernedActionInputSchema,
  parseAiGovernedRequest,
  RecordAiGovernedRequestOutcomeInputSchema,
  RequestAiOutputApprovalInputSchema,
  DecideAiOutputApprovalInputSchema,
  type RequestAiGovernedActionInput,
  type AiGovernedRequest,
  type RecordAiGovernedRequestOutcomeInput,
  type RequestAiOutputApprovalInput,
  type DecideAiOutputApprovalInput,
} from "../contracts/ai-governance/ai-governance.ts";

export interface AiGovernanceMutationRpcClient {
  rpc(
    fn: "request_ai_governed_action" | "record_ai_governed_request_outcome" | "request_ai_output_approval" | "decide_ai_output_approval",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const AI_GOVERNANCE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "ai_governed_request_feature_code_required",
  "ai_governed_request_secret_shaped_key",
  "ai_governed_request_not_found",
  "ai_governed_request_invalid_status",
  "ai_governed_request_not_pending",
  "ai_governed_request_invalid_cost_amount",
  "ai_governed_request_invalid_limit",
  "ai_governed_request_not_succeeded",
  "ai_governed_request_approval_already_requested",
  "ai_output_acceptance_approval_not_configured",
  "ai_output_approval_step_not_found",
  "ai_output_approval_wrong_domain",
] as const;
type KnownAiGovernanceMutationErrorCode = (typeof AI_GOVERNANCE_KNOWN_MUTATION_ERROR_CODES)[number];
export type AiGovernanceMutationErrorCode = KnownAiGovernanceMutationErrorCode | "mutation_failed" | "invalid_response";

export class AiGovernanceMutationError extends Error {
  readonly code: AiGovernanceMutationErrorCode;

  constructor(code: AiGovernanceMutationErrorCode, message: string) {
    super(message);
    this.name = "AiGovernanceMutationError";
    this.code = code;
  }
}

function classifyError(message: string): AiGovernanceMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (AI_GOVERNANCE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownAiGovernanceMutationErrorCode) : "mutation_failed";
}

/** The entry point every AI-assisted capability calls to register a real, governed AI request BEFORE dispatching it. Never writes to any table outside this migration's own schema. */
export async function requestAiGovernedAction(client: AiGovernanceMutationRpcClient, input: RequestAiGovernedActionInput): Promise<AiGovernedRequest> {
  const parsedInput = RequestAiGovernedActionInputSchema.parse(input);
  const { data, error } = await client.rpc("request_ai_governed_action", {
    p_tenant_id: parsedInput.tenantId,
    p_connection_id: parsedInput.connectionId,
    p_feature_code: parsedInput.featureCode,
    p_correlation_record_type: parsedInput.correlationRecordType,
    p_correlation_record_id: parsedInput.correlationRecordId,
    p_prompt_payload: parsedInput.promptPayload,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AiGovernanceMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AiGovernanceMutationError("invalid_response", "request_ai_governed_action returned no row");
  }
  return parseAiGovernedRequest(data as Record<string, unknown>);
}

/** The real dispatch client's own bounded write. billed_amount computed server-side (RPD-028), never trusted from the caller. */
export async function recordAiGovernedRequestOutcome(client: AiGovernanceMutationRpcClient, input: RecordAiGovernedRequestOutcomeInput): Promise<AiGovernedRequest> {
  const parsedInput = RecordAiGovernedRequestOutcomeInputSchema.parse(input);
  const { data, error } = await client.rpc("record_ai_governed_request_outcome", {
    p_request_id: parsedInput.requestId,
    p_status: parsedInput.status,
    p_output_payload: parsedInput.outputPayload,
    p_confidence_label: parsedInput.confidenceLabel,
    p_model_version: parsedInput.modelVersion,
    p_provider_unit_cost_amount: parsedInput.providerUnitCostAmount,
    p_currency: parsedInput.currency,
    p_error_message: parsedInput.errorMessage,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AiGovernanceMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AiGovernanceMutationError("invalid_response", "record_ai_governed_request_outcome returned no row");
  }
  return parseAiGovernedRequest(data as Record<string, unknown>);
}

export interface RequestAiOutputApprovalResult {
  readonly approvalRequestId: string;
  readonly status: string;
}

/** A domain-scoped proxy to app.request_approval (PLT-123). Only a real, succeeded output may be sent for approval, and only once per request. */
export async function requestAiOutputApproval(client: AiGovernanceMutationRpcClient, input: RequestAiOutputApprovalInput): Promise<RequestAiOutputApprovalResult> {
  const parsedInput = RequestAiOutputApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("request_ai_output_approval", {
    p_request_id: parsedInput.requestId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AiGovernanceMutationError(classifyError(error.message), error.message);
  }
  const row = data as Record<string, unknown> | null;
  if (!row || typeof row.id !== "string" || typeof row.status !== "string") {
    throw new AiGovernanceMutationError("invalid_response", "request_ai_output_approval returned no row");
  }
  return { approvalRequestId: row.id, status: row.status };
}

export interface DecideAiOutputApprovalResult {
  readonly stepId: string;
  readonly status: string;
}

/** A domain-scoped proxy to app.decide_approval_step (PLT-123). */
export async function decideAiOutputApproval(client: AiGovernanceMutationRpcClient, input: DecideAiOutputApprovalInput): Promise<DecideAiOutputApprovalResult> {
  const parsedInput = DecideAiOutputApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_ai_output_approval", {
    p_request_step_id: parsedInput.requestStepId,
    p_decision: parsedInput.decision,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_reason: parsedInput.reason,
    p_client_ip: parsedInput.clientIp ?? null,
  });
  if (error) {
    throw new AiGovernanceMutationError(classifyError(error.message), error.message);
  }
  const row = data as Record<string, unknown> | null;
  if (!row || typeof row.id !== "string" || typeof row.status !== "string") {
    throw new AiGovernanceMutationError("invalid_response", "decide_ai_output_approval returned no row");
  }
  return { stepId: row.id, status: row.status };
}
