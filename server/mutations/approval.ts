/**
 * Approval engine mutation primitives (PLT-123, CG-S6-PLT-020). Thin, typed wrappers
 * around app.publish_approval_definition / app.request_approval /
 * app.decide_approval_step / app.cancel_approval_request / app.escalate_approval_step /
 * app.create_approval_delegation / app.revoke_approval_delegation
 * (supabase/migrations/20260719090000_create_approval_engine.sql). All
 * service_role-only (see the migration's own grant comment).
 */

import {
  PublishApprovalDefinitionInputSchema,
  RequestApprovalInputSchema,
  DecideApprovalStepInputSchema,
  CancelApprovalRequestInputSchema,
  EscalateApprovalStepInputSchema,
  CreateApprovalDelegationInputSchema,
  RevokeApprovalDelegationInputSchema,
  ConfigVersionSchema,
  parseApprovalRequest,
  parseApprovalRequestStep,
  parseApprovalDelegation,
  type PublishApprovalDefinitionInput,
  type RequestApprovalInput,
  type DecideApprovalStepInput,
  type CancelApprovalRequestInput,
  type EscalateApprovalStepInput,
  type CreateApprovalDelegationInput,
  type RevokeApprovalDelegationInput,
  type ApprovalRequest,
  type ApprovalRequestStep,
  type ApprovalDelegation,
  type ConfigVersion,
} from "../contracts/approval/approval.ts";
import { parseConfigVersion } from "../contracts/config/config.ts";

export interface ApprovalMutationRpcClient {
  rpc(
    fn:
      | "publish_approval_definition"
      | "request_approval"
      | "decide_approval_step"
      | "cancel_approval_request"
      | "escalate_approval_step"
      | "create_approval_delegation"
      | "revoke_approval_delegation",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const APPROVAL_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "approval_invalid_pattern",
  "approval_missing_steps",
  "approval_invalid_step_order",
  "approval_invalid_approver_type",
  "approval_missing_approver_ref",
  "approval_unknown_role",
  "approval_unknown_user",
  "approval_invalid_required_approvals",
  "approval_invalid_threshold",
  "approval_definition_not_published",
  "approval_no_eligible_approver",
  "approval_request_not_found",
  "approval_request_not_pending",
  "approval_step_not_found",
  "approval_step_not_active",
  "approval_self_approval_denied",
  "approval_decision_already_recorded",
  "approval_invalid_decision",
  "approval_delegation_not_found",
  "approval_delegation_already_revoked",
] as const;
type KnownApprovalMutationErrorCode = (typeof APPROVAL_KNOWN_MUTATION_ERROR_CODES)[number];
export type ApprovalMutationErrorCode = KnownApprovalMutationErrorCode | "mutation_failed" | "invalid_response";

export class ApprovalMutationError extends Error {
  readonly code: ApprovalMutationErrorCode;

  constructor(code: ApprovalMutationErrorCode, message: string) {
    super(message);
    this.name = "ApprovalMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ApprovalMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (APPROVAL_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownApprovalMutationErrorCode)
    : "mutation_failed";
}

/** Runs the structural validation gate, then supersedes the prior published definition (PLT-121's app.publish_config_version() composed underneath). */
export async function publishApprovalDefinition(client: ApprovalMutationRpcClient, input: PublishApprovalDefinitionInput): Promise<ConfigVersion> {
  const parsedInput = PublishApprovalDefinitionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_approval_definition", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_effective_from: parsedInput.effectiveFrom,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ApprovalMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ApprovalMutationError("invalid_response", "publish_approval_definition returned no row");
  }
  return ConfigVersionSchema.parse(parseConfigVersion(data as Record<string, unknown>));
}

/** Idempotent on (tenantId, idempotencyKey). Refuses to create a request against any step with zero currently-eligible approvers (approval_no_eligible_approver). */
export async function requestApproval(client: ApprovalMutationRpcClient, input: RequestApprovalInput): Promise<ApprovalRequest> {
  const parsedInput = RequestApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("request_approval", {
    p_config_version_id: parsedInput.configVersionId,
    p_tenant_id: parsedInput.tenantId,
    p_entity_type: parsedInput.entityType,
    p_entity_id: parsedInput.entityId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_requested_by: parsedInput.requestedBy,
  });
  if (error) {
    throw new ApprovalMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ApprovalMutationError("invalid_response", "request_approval returned no row");
  }
  return parseApprovalRequest(data as Record<string, unknown>);
}

/** Records one approver's decision on one step; a second decision by the same identity on the same step raises approval_decision_already_recorded. */
export async function decideApprovalStep(client: ApprovalMutationRpcClient, input: DecideApprovalStepInput): Promise<ApprovalRequestStep> {
  const parsedInput = DecideApprovalStepInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_approval_step", {
    p_request_step_id: parsedInput.requestStepId,
    p_decision: parsedInput.decision,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_reason: parsedInput.reason,
  });
  if (error) {
    throw new ApprovalMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ApprovalMutationError("invalid_response", "decide_approval_step returned no row");
  }
  return parseApprovalRequestStep(data as Record<string, unknown>);
}

/** pending -> cancelled; every still-open step is marked skipped. */
export async function cancelApprovalRequest(client: ApprovalMutationRpcClient, input: CancelApprovalRequestInput): Promise<ApprovalRequest> {
  const parsedInput = CancelApprovalRequestInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_approval_request", {
    p_request_id: parsedInput.requestId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_reason: parsedInput.reason,
  });
  if (error) {
    throw new ApprovalMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ApprovalMutationError("invalid_response", "cancel_approval_request returned no row");
  }
  return parseApprovalRequest(data as Record<string, unknown>);
}

/** Manual reassignment of an active step's approver target by an authorized override actor (definition-admin-grade authority, not the looser instance-level requester/approver authority). */
export async function escalateApprovalStep(client: ApprovalMutationRpcClient, input: EscalateApprovalStepInput): Promise<ApprovalRequestStep> {
  const parsedInput = EscalateApprovalStepInputSchema.parse(input);
  const { data, error } = await client.rpc("escalate_approval_step", {
    p_request_step_id: parsedInput.requestStepId,
    p_new_approver_type: parsedInput.newApproverType,
    p_new_role_id: parsedInput.newRoleId,
    p_new_specific_user_id: parsedInput.newSpecificUserId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_reason: parsedInput.reason,
  });
  if (error) {
    throw new ApprovalMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ApprovalMutationError("invalid_response", "escalate_approval_step returned no row");
  }
  return parseApprovalRequestStep(data as Record<string, unknown>);
}

/** Bounded (<=90 days) delegation; callable by the delegator themselves or a tenant_admin/Supreme on their behalf. */
export async function createApprovalDelegation(client: ApprovalMutationRpcClient, input: CreateApprovalDelegationInput): Promise<ApprovalDelegation> {
  const parsedInput = CreateApprovalDelegationInputSchema.parse(input);
  const { data, error } = await client.rpc("create_approval_delegation", {
    p_tenant_id: parsedInput.tenantId,
    p_delegator_auth_user_id: parsedInput.delegatorAuthUserId,
    p_delegate_auth_user_id: parsedInput.delegateAuthUserId,
    p_scope: parsedInput.scope,
    p_role_id: parsedInput.roleId,
    p_starts_at: parsedInput.startsAt,
    p_expires_at: parsedInput.expiresAt,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
  if (error) {
    throw new ApprovalMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ApprovalMutationError("invalid_response", "create_approval_delegation returned no row");
  }
  return parseApprovalDelegation(data as Record<string, unknown>);
}

/** Callable by the delegator themselves or a tenant_admin/Supreme; a second revoke on an already-revoked delegation raises approval_delegation_already_revoked. */
export async function revokeApprovalDelegation(client: ApprovalMutationRpcClient, input: RevokeApprovalDelegationInput): Promise<ApprovalDelegation> {
  const parsedInput = RevokeApprovalDelegationInputSchema.parse(input);
  const { data, error } = await client.rpc("revoke_approval_delegation", {
    p_delegation_id: parsedInput.delegationId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_reason: parsedInput.reason,
  });
  if (error) {
    throw new ApprovalMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ApprovalMutationError("invalid_response", "revoke_approval_delegation returned no row");
  }
  return parseApprovalDelegation(data as Record<string, unknown>);
}
