/**
 * Procurement Approval mutation primitives (PRC-259, CG-S11-PRC-010). Thin, typed
 * wrappers around app.create_procurement_approval_policy_version /
 * app.publish_procurement_approval_policy_version /
 * app.decide_vendor_activation_approval_step / app.decide_rate_version_approval_step /
 * app.decide_vendor_selection_approval_step /
 * app.decide_procurement_exception_approval_step /
 * app.create_procurement_exception_request / app.cancel_procurement_exception_request
 * (supabase/migrations/20260730660000_create_procurement_approval.sql). Delegation/
 * escalation/cancel-approval-request keep going straight through the already-existing
 * Approval Engine mutations (server/mutations/approval.ts, PLT-123) -- none of them
 * needs a procurement-specific wrapper (mirrors server/mutations/quotation-approval.ts's
 * own header). Each governed entity's own submit/transition RPC
 * (app.decide_vendor_profile_review / app.activate_vendor_profile /
 * app.create_rate_version / app.approve_rate_version /
 * app.submit_vendor_comparison_for_approval) is unchanged in shape -- still wrapped by
 * its own existing server/mutations/*.ts file; routing now simply happens inside those
 * same RPCs server-side.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateProcurementApprovalPolicyVersionInputSchema,
  PublishProcurementApprovalPolicyVersionInputSchema,
  DecideProcurementApprovalStepInputSchema,
  CreateProcurementExceptionRequestInputSchema,
  CancelProcurementExceptionRequestInputSchema,
  parseProcurementApprovalPolicyVersion,
  parseVendorActivationApprovalSyncResult,
  parseRateVersionApprovalSyncResult,
  parseVendorSelectionApprovalSyncResult,
  parsePurchaseOrderApprovalSyncResult,
  parseProcurementExceptionRequest,
  type CreateProcurementApprovalPolicyVersionInput,
  type PublishProcurementApprovalPolicyVersionInput,
  type DecideProcurementApprovalStepInput,
  type CreateProcurementExceptionRequestInput,
  type CancelProcurementExceptionRequestInput,
  type ProcurementApprovalPolicyVersion,
  type VendorActivationApprovalSyncResult,
  type RateVersionApprovalSyncResult,
  type VendorSelectionApprovalSyncResult,
  type PurchaseOrderApprovalSyncResult,
  type ProcurementExceptionRequest,
} from "../contracts/procurement-approval/procurement-approval.ts";

export type ProcurementApprovalMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const PROCUREMENT_APPROVAL_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_entity_type",
  "procurement_approval_policy_not_found",
  "stale_version",
  "invalid_transition",
  "superseded_policy_not_found",
  "invalid_supersede",
  "active_policy_exists",
  "approval_definition_not_configured",
  "approval_step_not_found",
  "not_a_vendor_activation_approval",
  "not_a_rate_version_approval",
  "not_a_vendor_selection_approval",
  "not_a_procurement_exception_approval",
  // PRC-260: the purchase_order entity_type's own domain sync wrapper, following the
  // exact pattern PRC-259's own migration header documented as this prompt's own future
  // work.
  "not_a_purchase_order_approval",
  "approval_request_not_pending",
  "approval_step_not_active",
  "approval_self_approval_denied",
  "approval_decision_already_recorded",
  "approval_invalid_decision",
  "reason_required",
  "exception_type_required",
  "idempotency_key_conflict",
  "procurement_exception_request_not_found",
  "idempotency_key_required",
  // Batch 257-259 review (C-18, HIGH): MFA reauth-freshness gate on all four
  // decide_*_approval_step wrappers (mirrors CREDIT_MUTATION_KNOWN_ERROR_CODES'
  // own "reauth_required").
  "reauth_required",
  // Batch 257-259 review (F8 defense-in-depth, HIGH): a bound entity that no
  // longer resolves now raises a typed error instead of an all-NULL composite.
  "vendor_activation_target_not_found",
  "rate_version_target_not_found",
  "vendor_selection_target_not_found",
  "procurement_exception_target_not_found",
  // PRC-260
  "purchase_order_target_not_found",
] as const;
type KnownProcurementApprovalMutationErrorCode = (typeof PROCUREMENT_APPROVAL_KNOWN_MUTATION_ERROR_CODES)[number];
export type ProcurementApprovalMutationErrorCode = KnownProcurementApprovalMutationErrorCode | "mutation_failed" | "invalid_response";

export class ProcurementApprovalMutationError extends Error {
  readonly code: ProcurementApprovalMutationErrorCode;

  constructor(code: ProcurementApprovalMutationErrorCode, message: string) {
    super(message);
    this.name = "ProcurementApprovalMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ProcurementApprovalMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (PROCUREMENT_APPROVAL_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownProcurementApprovalMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: ProcurementApprovalMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new ProcurementApprovalMutationError(classifyError(error.message), error.message);
  }
  return data;
}

/** Draft creation, gated by PRC:Create. At least one of minValueAmount/alwaysRequired is required (contract-level refine, mirrored by the migration's own procurement_approval_policies_at_least_one_threshold CHECK; minValueAmount is additionally restricted to rate_version/vendor_selection/purchase_order by procurement_approval_policies_value_dimension_check). */
export async function createProcurementApprovalPolicyVersion(client: ProcurementApprovalMutationRpcClient, input: CreateProcurementApprovalPolicyVersionInput): Promise<ProcurementApprovalPolicyVersion> {
  const parsedInput = CreateProcurementApprovalPolicyVersionInputSchema.parse(input);
  const data = await callRpc(client, "create_procurement_approval_policy_version", {
    p_tenant_id: parsedInput.tenantId,
    p_entity_type: parsedInput.entityType,
    p_min_value_amount: parsedInput.minValueAmount,
    p_always_required: parsedInput.alwaysRequired,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
  if (!data || typeof data !== "object") {
    throw new ProcurementApprovalMutationError("invalid_response", "create_procurement_approval_policy_version returned no row");
  }
  return parseProcurementApprovalPolicyVersion(data as Record<string, unknown>);
}

/** draft -> published, gated by PRC:Approve. Supplying supersedesVersionId archives the tenant's prior published policy for the SAME entity_type first (at most one published policy per (tenant, entity_type)). */
export async function publishProcurementApprovalPolicyVersion(client: ProcurementApprovalMutationRpcClient, input: PublishProcurementApprovalPolicyVersionInput): Promise<ProcurementApprovalPolicyVersion> {
  const parsedInput = PublishProcurementApprovalPolicyVersionInputSchema.parse(input);
  const data = await callRpc(client, "publish_procurement_approval_policy_version", {
    p_policy_version_id: parsedInput.policyVersionId,
    p_expected_version: parsedInput.expectedVersion,
    p_supersedes_version_id: parsedInput.supersedesVersionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (!data || typeof data !== "object") {
    throw new ProcurementApprovalMutationError("invalid_response", "publish_procurement_approval_policy_version returned no row");
  }
  return parseProcurementApprovalPolicyVersion(data as Record<string, unknown>);
}

function decideStepArgs(input: DecideProcurementApprovalStepInput) {
  const parsedInput = DecideProcurementApprovalStepInputSchema.parse(input);
  return {
    p_request_step_id: parsedInput.requestStepId,
    p_decision: parsedInput.decision,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_reauth_confirmed_at: parsedInput.reauthConfirmedAt,
    p_reason: parsedInput.reason,
  };
}

/** Records one approver's decision on one step of a vendor activation's bound approval request, then syncs app.vendor_profiles.approvalStatus once the request reaches a final state -- never itself calls app.activate_vendor_profile (that stays a separate, explicit action once approvalStatus clears). */
export async function decideVendorActivationApprovalStep(client: ProcurementApprovalMutationRpcClient, input: DecideProcurementApprovalStepInput): Promise<VendorActivationApprovalSyncResult> {
  const data = await callRpc(client, "decide_vendor_activation_approval_step", decideStepArgs(input));
  if (!data || typeof data !== "object") {
    throw new ProcurementApprovalMutationError("invalid_response", "decide_vendor_activation_approval_step returned no row");
  }
  return parseVendorActivationApprovalSyncResult(data as Record<string, unknown>);
}

/** Records one approver's decision on one step of a rate version's bound approval request, then syncs app.vendor_rate_versions.governanceApprovalStatus (never the pre-existing approvalStatus column) once the request reaches a final state. */
export async function decideRateVersionApprovalStep(client: ProcurementApprovalMutationRpcClient, input: DecideProcurementApprovalStepInput): Promise<RateVersionApprovalSyncResult> {
  const data = await callRpc(client, "decide_rate_version_approval_step", decideStepArgs(input));
  if (!data || typeof data !== "object") {
    throw new ProcurementApprovalMutationError("invalid_response", "decide_rate_version_approval_step returned no row");
  }
  return parseRateVersionApprovalSyncResult(data as Record<string, unknown>);
}

/** Records one approver's decision on one step of a vendor selection's bound approval request, then syncs app.vendor_comparisons.approvalStatus once the request reaches a final state -- status stays submitted throughout (the release gate is Prompt 260's own future PO-award RPC, not this capability). */
export async function decideVendorSelectionApprovalStep(client: ProcurementApprovalMutationRpcClient, input: DecideProcurementApprovalStepInput): Promise<VendorSelectionApprovalSyncResult> {
  const data = await callRpc(client, "decide_vendor_selection_approval_step", decideStepArgs(input));
  if (!data || typeof data !== "object") {
    throw new ProcurementApprovalMutationError("invalid_response", "decide_vendor_selection_approval_step returned no row");
  }
  return parseVendorSelectionApprovalSyncResult(data as Record<string, unknown>);
}

/** Records one approver's decision on one step of a purchase order's bound approval request, then syncs app.purchase_orders.approvalStatus once the request reaches a final state -- never itself calls app.issue_purchase_order (that stays a separate, explicit Procurement action once approvalStatus clears). PRC-260. */
export async function decidePurchaseOrderApprovalStep(client: ProcurementApprovalMutationRpcClient, input: DecideProcurementApprovalStepInput): Promise<PurchaseOrderApprovalSyncResult> {
  const data = await callRpc(client, "decide_purchase_order_approval_step", decideStepArgs(input));
  if (!data || typeof data !== "object") {
    throw new ProcurementApprovalMutationError("invalid_response", "decide_purchase_order_approval_step returned no row");
  }
  return parsePurchaseOrderApprovalSyncResult(data as Record<string, unknown>);
}

/** Records one approver's decision on one step of an exception/override request's bound approval request. Unlike the other three, this ALSO syncs status (not just approvalStatus) -- the governance outcome IS the terminal domain status for this entity. */
export async function decideProcurementExceptionApprovalStep(client: ProcurementApprovalMutationRpcClient, input: DecideProcurementApprovalStepInput): Promise<ProcurementExceptionRequest> {
  const data = await callRpc(client, "decide_procurement_exception_approval_step", decideStepArgs(input));
  if (!data || typeof data !== "object") {
    throw new ProcurementApprovalMutationError("invalid_response", "decide_procurement_exception_approval_step returned no row");
  }
  return parseProcurementExceptionRequest(data as Record<string, unknown>);
}

/** PRC:Override, mandatory reason. Auto-approved immediately (status=approved) when no exception_override policy is published for this tenant; routed for real (status=submitted, approvalStatus=pending) when one is. */
export async function createProcurementExceptionRequest(client: ProcurementApprovalMutationRpcClient, input: CreateProcurementExceptionRequestInput): Promise<ProcurementExceptionRequest> {
  const parsedInput = CreateProcurementExceptionRequestInputSchema.parse(input);
  const data = await callRpc(client, "create_procurement_exception_request", {
    p_tenant_id: parsedInput.tenantId,
    p_related_entity_type: parsedInput.relatedEntityType,
    p_related_entity_id: parsedInput.relatedEntityId,
    p_exception_type: parsedInput.exceptionType,
    p_reason: parsedInput.reason,
    p_requested_outcome: parsedInput.requestedOutcome,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (!data || typeof data !== "object") {
    throw new ProcurementApprovalMutationError("invalid_response", "create_procurement_exception_request returned no row");
  }
  return parseProcurementExceptionRequest(data as Record<string, unknown>);
}

/** PRC:Edit, mandatory reason. Only a still-submitted (not yet finally decided) exception request may be withdrawn -- cancels the bound approval request too, when one exists. */
export async function cancelProcurementExceptionRequest(client: ProcurementApprovalMutationRpcClient, input: CancelProcurementExceptionRequestInput): Promise<ProcurementExceptionRequest> {
  const parsedInput = CancelProcurementExceptionRequestInputSchema.parse(input);
  const data = await callRpc(client, "cancel_procurement_exception_request", {
    p_id: parsedInput.id,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (!data || typeof data !== "object") {
    throw new ProcurementApprovalMutationError("invalid_response", "cancel_procurement_exception_request returned no row");
  }
  return parseProcurementExceptionRequest(data as Record<string, unknown>);
}
