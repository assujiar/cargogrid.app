/**
 * Vendor Contract mutation primitives (PRC-261, CG-S11-PRC-012). Thin, typed wrappers
 * around the write RPCs supabase/migrations/20260730700000_create_procurement_vendor_
 * contract.sql adds -- the same KNOWN_MUTATION_ERROR_CODES / classifyError / callRpc
 * shape server/mutations/purchase-order.ts already establishes for this checkpoint's
 * own template. The approval-decision step itself
 * (app.decide_vendor_contract_approval_step) is wrapped by server/mutations/procurement-
 * approval.ts, not here -- it is dispatched from the shared /procurement/approvals
 * inbox, mirroring purchase_order's own identical split.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateVendorContractDraftInputSchema,
  UpdateVendorContractDraftInputSchema,
  SubmitVendorContractForApprovalInputSchema,
  RecordVendorContractSignatureInputSchema,
  ActivateVendorContractInputSchema,
  AmendVendorContractInputSchema,
  RenewVendorContractInputSchema,
  SuspendVendorContractInputSchema,
  ReactivateVendorContractInputSchema,
  TerminateVendorContractInputSchema,
  CancelVendorContractDraftInputSchema,
  parseVendorContract,
  type CreateVendorContractDraftInput,
  type UpdateVendorContractDraftInput,
  type SubmitVendorContractForApprovalInput,
  type RecordVendorContractSignatureInput,
  type ActivateVendorContractInput,
  type AmendVendorContractInput,
  type RenewVendorContractInput,
  type SuspendVendorContractInput,
  type ReactivateVendorContractInput,
  type TerminateVendorContractInput,
  type CancelVendorContractDraftInput,
  type VendorContract,
} from "../contracts/vendor-contract/vendor-contract.ts";

export type VendorContractMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const VENDOR_CONTRACT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "vendor_contract_not_found",
  "vendor_profile_not_found",
  "rate_version_not_found",
  "rate_version_scope_mismatch",
  "evidence_file_not_found",
  "contract_evidence_file_mismatch",
  "contract_unsafe_evidence",
  "invalid_contract_type",
  "missing_effective_end",
  "invalid_effective_range",
  "invalid_payment_term",
  "approval_incomplete",
  "signature_incomplete",
  "signed_by_required",
  "reason_required",
  "evidence_required",
  "stale_version",
  "invalid_transition",
] as const;
type KnownVendorContractMutationErrorCode = (typeof VENDOR_CONTRACT_KNOWN_MUTATION_ERROR_CODES)[number];
export type VendorContractMutationErrorCode = KnownVendorContractMutationErrorCode | "mutation_failed" | "invalid_response";

export class VendorContractMutationError extends Error {
  readonly code: VendorContractMutationErrorCode;

  constructor(code: VendorContractMutationErrorCode, message: string) {
    super(message);
    this.name = "VendorContractMutationError";
    this.code = code;
  }
}

function classifyError(message: string): VendorContractMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (VENDOR_CONTRACT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownVendorContractMutationErrorCode) : "mutation_failed";
}

async function callRpc(client: VendorContractMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new VendorContractMutationError(classifyError(error.message), error.message);
  }
  return data;
}

function requireVendorContractRow(data: unknown, fn: string): VendorContract {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorContractMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseVendorContract(row as Record<string, unknown>);
}

/** Creates (or, on idempotency-key replay, returns the existing) a draft vendor contract. status=draft, version_no=1, version_kind=initial. */
export async function createVendorContractDraft(client: VendorContractMutationRpcClient, input: CreateVendorContractDraftInput): Promise<VendorContract> {
  const parsed = CreateVendorContractDraftInputSchema.parse(input);
  const data = await callRpc(client, "create_vendor_contract_draft", {
    p_tenant_id: parsed.tenantId,
    p_vendor_master_id: parsed.vendorMasterId,
    p_contract_type: parsed.contractType,
    p_effective_start: parsed.effectiveStart,
    p_effective_end: parsed.effectiveEnd,
    p_rate_version_id: parsed.rateVersionId,
    p_payment_term_days: parsed.paymentTermDays,
    p_tax_terms: parsed.taxTerms,
    p_sla_terms: parsed.slaTerms,
    p_capacity_terms: parsed.capacityTerms,
    p_coverage_terms: parsed.coverageTerms,
    p_compliance_required: parsed.complianceRequired,
    p_signature_required: parsed.signatureRequired,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireVendorContractRow(data, "create_vendor_contract_draft");
}

/** Edits draft-only terms fields (effective range, linked rate, payment terms, tax/SLA/capacity/coverage terms, required compliance). draft status only. */
export async function updateVendorContractDraft(client: VendorContractMutationRpcClient, input: UpdateVendorContractDraftInput): Promise<VendorContract> {
  const parsed = UpdateVendorContractDraftInputSchema.parse(input);
  const data = await callRpc(client, "update_vendor_contract_draft", {
    p_contract_id: parsed.contractId,
    p_expected_version: parsed.expectedVersion,
    p_effective_start: parsed.effectiveStart,
    p_effective_end: parsed.effectiveEnd,
    p_rate_version_id: parsed.rateVersionId,
    p_payment_term_days: parsed.paymentTermDays,
    p_tax_terms: parsed.taxTerms,
    p_sla_terms: parsed.slaTerms,
    p_capacity_terms: parsed.capacityTerms,
    p_coverage_terms: parsed.coverageTerms,
    p_compliance_required: parsed.complianceRequired,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireVendorContractRow(data, "update_vendor_contract_draft");
}

/** draft -> pending_approval. Routes through app._request_procurement_entity_approval (entity_type=vendor_contract) when the tenant's published policy requires it. */
export async function submitVendorContractForApproval(client: VendorContractMutationRpcClient, input: SubmitVendorContractForApprovalInput): Promise<VendorContract> {
  const parsed = SubmitVendorContractForApprovalInputSchema.parse(input);
  const data = await callRpc(client, "submit_vendor_contract_for_approval", {
    p_contract_id: parsed.contractId,
    p_expected_version: parsed.expectedVersion,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireVendorContractRow(data, "submit_vendor_contract_for_approval");
}

/** Attaches signature evidence (re-validated tenant/record_type/record_id/malware_scan_status=clean when a file is supplied). draft or pending_approval only. */
export async function recordVendorContractSignature(client: VendorContractMutationRpcClient, input: RecordVendorContractSignatureInput): Promise<VendorContract> {
  const parsed = RecordVendorContractSignatureInputSchema.parse(input);
  const data = await callRpc(client, "record_vendor_contract_signature", {
    p_contract_id: parsed.contractId,
    p_expected_version: parsed.expectedVersion,
    p_signed_by: parsed.signedBy,
    p_signed_at: parsed.signedAt,
    p_evidence_file_id: parsed.evidenceFileId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireVendorContractRow(data, "record_vendor_contract_signature");
}

/** pending_approval -> active. Requires approvalStatus in (approved, not_required) AND (signature not required OR signatureStatus=signed). Marks any superseded predecessor (renewal branch only -- amendment already superseded its predecessor at amend time). */
export async function activateVendorContract(client: VendorContractMutationRpcClient, input: ActivateVendorContractInput): Promise<VendorContract> {
  const parsed = ActivateVendorContractInputSchema.parse(input);
  const data = await callRpc(client, "activate_vendor_contract", {
    p_contract_id: parsed.contractId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireVendorContractRow(data, "activate_vendor_contract");
}

/** active -> immediately superseded; returns a brand-new draft (version_no+1, version_kind=amendment) that must independently pass back through submit/decide/sign/activate. */
export async function amendVendorContract(client: VendorContractMutationRpcClient, input: AmendVendorContractInput): Promise<VendorContract> {
  const parsed = AmendVendorContractInputSchema.parse(input);
  const data = await callRpc(client, "amend_vendor_contract", {
    p_contract_id: parsed.contractId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_effective_end: parsed.effectiveEnd,
    p_rate_version_id: parsed.rateVersionId,
    p_payment_term_days: parsed.paymentTermDays,
    p_sla_terms: parsed.slaTerms,
    p_capacity_terms: parsed.capacityTerms,
    p_coverage_terms: parsed.coverageTerms,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireVendorContractRow(data, "amend_vendor_contract");
}

/** active (stays active) -> a brand-new draft (version_no+1, version_kind=renewal) with new effective dates; supersedes its predecessor only once IT activates (no coverage gap). */
export async function renewVendorContract(client: VendorContractMutationRpcClient, input: RenewVendorContractInput): Promise<VendorContract> {
  const parsed = RenewVendorContractInputSchema.parse(input);
  const data = await callRpc(client, "renew_vendor_contract", {
    p_contract_id: parsed.contractId,
    p_expected_version: parsed.expectedVersion,
    p_new_effective_start: parsed.newEffectiveStart,
    p_new_effective_end: parsed.newEffectiveEnd,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireVendorContractRow(data, "renew_vendor_contract");
}

/** active -> suspended, PRC:Override, mandatory reason. */
export async function suspendVendorContract(client: VendorContractMutationRpcClient, input: SuspendVendorContractInput): Promise<VendorContract> {
  const parsed = SuspendVendorContractInputSchema.parse(input);
  const data = await callRpc(client, "suspend_vendor_contract", {
    p_contract_id: parsed.contractId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireVendorContractRow(data, "suspend_vendor_contract");
}

/** suspended -> active, PRC:Override. */
export async function reactivateVendorContract(client: VendorContractMutationRpcClient, input: ReactivateVendorContractInput): Promise<VendorContract> {
  const parsed = ReactivateVendorContractInputSchema.parse(input);
  const data = await callRpc(client, "reactivate_vendor_contract", {
    p_contract_id: parsed.contractId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireVendorContractRow(data, "reactivate_vendor_contract");
}

/** active|suspended -> terminated, PRC:Override, mandatory reason+evidenceRef. */
export async function terminateVendorContract(client: VendorContractMutationRpcClient, input: TerminateVendorContractInput): Promise<VendorContract> {
  const parsed = TerminateVendorContractInputSchema.parse(input);
  const data = await callRpc(client, "terminate_vendor_contract", {
    p_contract_id: parsed.contractId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_evidence_ref: parsed.evidenceRef,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireVendorContractRow(data, "terminate_vendor_contract");
}

/** draft|pending_approval -> cancelled (cancel-eligible only, never an active contract), PRC:Edit, mandatory reason. Cancels the bound approval request too when one is still pending. */
export async function cancelVendorContractDraft(client: VendorContractMutationRpcClient, input: CancelVendorContractDraftInput): Promise<VendorContract> {
  const parsed = CancelVendorContractDraftInputSchema.parse(input);
  const data = await callRpc(client, "cancel_vendor_contract_draft", {
    p_contract_id: parsed.contractId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireVendorContractRow(data, "cancel_vendor_contract_draft");
}
