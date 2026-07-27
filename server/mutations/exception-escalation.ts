/**
 * Exception and Escalation mutation primitives (OPS-174, CG-S8-OPS-008). Thin, typed
 * wrappers around the report/assign/acknowledge/escalate/resolve/close/reopen/
 * sensitive-fields RPCs plus SLA policy draft/terms/publish
 * (supabase/migrations/20260727150000_create_operations_exception_escalation.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateExceptionSlaPolicyDraftInputSchema,
  SetExceptionSlaPolicyTermsInputSchema,
  PublishExceptionSlaPolicyVersionInputSchema,
  ReportExceptionInputSchema,
  AssignExceptionOwnerInputSchema,
  AcknowledgeExceptionInputSchema,
  EscalateExceptionInputSchema,
  ResolveExceptionInputSchema,
  CloseExceptionInputSchema,
  ReopenExceptionInputSchema,
  SetExceptionSensitiveFieldsInputSchema,
  parseExceptionSlaPolicyVersion,
  parseOperationalException,
  type CreateExceptionSlaPolicyDraftInput,
  type SetExceptionSlaPolicyTermsInput,
  type PublishExceptionSlaPolicyVersionInput,
  type ReportExceptionInput,
  type AssignExceptionOwnerInput,
  type AcknowledgeExceptionInput,
  type EscalateExceptionInput,
  type ResolveExceptionInput,
  type CloseExceptionInput,
  type ReopenExceptionInput,
  type SetExceptionSensitiveFieldsInput,
  type ExceptionSlaPolicyVersion,
  type OperationalException,
} from "../contracts/exception-escalation/exception-escalation.ts";

export type ExceptionEscalationMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const EXCEPTION_ESCALATION_KNOWN_MUTATION_ERROR_CODES = [
  "exception_invalid_type",
  "exception_invalid_severity",
  "exception_invalid_source",
  "exception_invalid_sla_hours",
  "exception_invalid_escalation_schedule",
  "exception_invalid_claim_amount",
  "exception_sla_policy_not_found",
  "exception_not_found",
  "shipment_order_not_found",
  "milestone_event_not_found",
  "invalid_transition",
  "stale_version",
  "reason_required",
  "evidence_required",
  "insufficient_authority",
] as const;
type KnownExceptionEscalationMutationErrorCode = (typeof EXCEPTION_ESCALATION_KNOWN_MUTATION_ERROR_CODES)[number];
export type ExceptionEscalationMutationErrorCode = KnownExceptionEscalationMutationErrorCode | "mutation_failed" | "invalid_response";

export class ExceptionEscalationMutationError extends Error {
  readonly code: ExceptionEscalationMutationErrorCode;

  constructor(code: ExceptionEscalationMutationErrorCode, message: string) {
    super(message);
    this.name = "ExceptionEscalationMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ExceptionEscalationMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (EXCEPTION_ESCALATION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownExceptionEscalationMutationErrorCode)
    : "mutation_failed";
}

function parseRpcPolicyVersion(data: unknown, rpcName: string): ExceptionSlaPolicyVersion {
  if (!data || typeof data !== "object") {
    throw new ExceptionEscalationMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseExceptionSlaPolicyVersion(data as Record<string, unknown>);
}

function parseRpcException(data: unknown, rpcName: string): OperationalException {
  if (!data || typeof data !== "object") {
    throw new ExceptionEscalationMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseOperationalException(data as Record<string, unknown>);
}

/** Idempotent: a repeated call while a draft already exists for this (tenant, type, severity) returns that same draft. */
export async function createExceptionSlaPolicyDraft(
  client: ExceptionEscalationMutationRpcClient,
  input: CreateExceptionSlaPolicyDraftInput,
): Promise<ExceptionSlaPolicyVersion> {
  const parsedInput = CreateExceptionSlaPolicyDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_exception_sla_policy_draft", {
    p_tenant_id: parsedInput.tenantId,
    p_type: parsedInput.type,
    p_severity: parsedInput.severity,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExceptionEscalationMutationError(classifyError(error.message), error.message);
  }
  return parseRpcPolicyVersion(data, "create_exception_sla_policy_draft");
}

export async function setExceptionSlaPolicyTerms(
  client: ExceptionEscalationMutationRpcClient,
  input: SetExceptionSlaPolicyTermsInput,
): Promise<ExceptionSlaPolicyVersion> {
  const parsedInput = SetExceptionSlaPolicyTermsInputSchema.parse(input);
  const { data, error } = await client.rpc("set_exception_sla_policy_terms", {
    p_version_id: parsedInput.versionId,
    p_sla_hours: parsedInput.slaHours,
    p_escalation_schedule: parsedInput.escalationSchedule,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExceptionEscalationMutationError(classifyError(error.message), error.message);
  }
  return parseRpcPolicyVersion(data, "set_exception_sla_policy_terms");
}

export async function publishExceptionSlaPolicyVersion(
  client: ExceptionEscalationMutationRpcClient,
  input: PublishExceptionSlaPolicyVersionInput,
): Promise<ExceptionSlaPolicyVersion> {
  const parsedInput = PublishExceptionSlaPolicyVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_exception_sla_policy_version", {
    p_version_id: parsedInput.versionId,
    p_expected_version: parsedInput.expectedVersion,
    p_supersedes_version_id: parsedInput.supersedesVersionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExceptionEscalationMutationError(classifyError(error.message), error.message);
  }
  return parseRpcPolicyVersion(data, "publish_exception_sla_policy_version");
}

/** The one path that creates an exception -- idempotent (dedup) on (tenant, shipmentOrderId, correlationKey) when source='system'. Pins the tenant's own published SLA policy for (type, severity), if any. */
export async function reportException(client: ExceptionEscalationMutationRpcClient, input: ReportExceptionInput): Promise<OperationalException> {
  const parsedInput = ReportExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("report_exception", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_milestone_event_id: parsedInput.milestoneEventId,
    p_type: parsedInput.type,
    p_severity: parsedInput.severity,
    p_description: parsedInput.description,
    p_source: parsedInput.source,
    p_correlation_key: parsedInput.correlationKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExceptionEscalationMutationError(classifyError(error.message), error.message);
  }
  return parseRpcException(data, "report_exception");
}

/** Reason is mandatory only when reassigning an already-owned exception. */
export async function assignExceptionOwner(client: ExceptionEscalationMutationRpcClient, input: AssignExceptionOwnerInput): Promise<OperationalException> {
  const parsedInput = AssignExceptionOwnerInputSchema.parse(input);
  const { data, error } = await client.rpc("assign_exception_owner", {
    p_exception_id: parsedInput.exceptionId,
    p_owner_user_id: parsedInput.ownerUserId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExceptionEscalationMutationError(classifyError(error.message), error.message);
  }
  return parseRpcException(data, "assign_exception_owner");
}

export async function acknowledgeException(client: ExceptionEscalationMutationRpcClient, input: AcknowledgeExceptionInput): Promise<OperationalException> {
  const parsedInput = AcknowledgeExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("acknowledge_exception", {
    p_exception_id: parsedInput.exceptionId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExceptionEscalationMutationError(classifyError(error.message), error.message);
  }
  return parseRpcException(data, "acknowledge_exception");
}

/** Orthogonal to status -- increments escalationLevel and appends a real history row. Reason mandatory; blocked once resolved/closed. */
export async function escalateException(client: ExceptionEscalationMutationRpcClient, input: EscalateExceptionInput): Promise<OperationalException> {
  const parsedInput = EscalateExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("escalate_exception", {
    p_exception_id: parsedInput.exceptionId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExceptionEscalationMutationError(classifyError(error.message), error.message);
  }
  return parseRpcException(data, "escalate_exception");
}

export async function resolveException(client: ExceptionEscalationMutationRpcClient, input: ResolveExceptionInput): Promise<OperationalException> {
  const parsedInput = ResolveExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("resolve_exception", {
    p_exception_id: parsedInput.exceptionId,
    p_expected_version: parsedInput.expectedVersion,
    p_resolution_evidence: parsedInput.resolutionEvidence,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExceptionEscalationMutationError(classifyError(error.message), error.message);
  }
  return parseRpcException(data, "resolve_exception");
}

export async function closeException(client: ExceptionEscalationMutationRpcClient, input: CloseExceptionInput): Promise<OperationalException> {
  const parsedInput = CloseExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("close_exception", {
    p_exception_id: parsedInput.exceptionId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExceptionEscalationMutationError(classifyError(error.message), error.message);
  }
  return parseRpcException(data, "close_exception");
}

/** Resolution evidence is never cleared or deleted by a reopen -- only status/reopenedAt change. */
export async function reopenException(client: ExceptionEscalationMutationRpcClient, input: ReopenExceptionInput): Promise<OperationalException> {
  const parsedInput = ReopenExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("reopen_exception", {
    p_exception_id: parsedInput.exceptionId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExceptionEscalationMutationError(classifyError(error.message), error.message);
  }
  return parseRpcException(data, "reopen_exception");
}

/** Requires both OPS:Edit and OPS:View cost -- an actor who cannot see this masked data cannot blindly write it either. */
export async function setExceptionSensitiveFields(
  client: ExceptionEscalationMutationRpcClient,
  input: SetExceptionSensitiveFieldsInput,
): Promise<OperationalException> {
  const parsedInput = SetExceptionSensitiveFieldsInputSchema.parse(input);
  const { data, error } = await client.rpc("set_exception_sensitive_fields", {
    p_exception_id: parsedInput.exceptionId,
    p_internal_notes: parsedInput.internalNotes,
    p_damage_loss_details: parsedInput.damageLossDetails,
    p_claim_amount: parsedInput.claimAmount,
    p_claim_currency: parsedInput.claimCurrency,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ExceptionEscalationMutationError(classifyError(error.message), error.message);
  }
  return parseRpcException(data, "set_exception_sensitive_fields");
}
