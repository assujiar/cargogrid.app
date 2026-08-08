/**
 * Vendor Invoice Matching mutation primitives (PRC-265, CG-S11-PRC-016). Thin, typed
 * wrappers around the write RPCs supabase/migrations/20260730750000_create_
 * procurement_vendor_invoice_matching.sql adds -- the same KNOWN_MUTATION_ERROR_CODES /
 * classifyError / callRpc shape server/mutations/vendor-contract.ts already establishes
 * for this checkpoint's own template.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateVendorBillMatchTolerancePolicyDraftInputSchema,
  UpdateVendorBillMatchTolerancePolicyDraftInputSchema,
  ActivateVendorBillMatchTolerancePolicyInputSchema,
  CreateVendorBillMatchCaseInputSchema,
  ReEvaluateVendorBillMatchCaseInputSchema,
  MapVendorBillMatchLineInputSchema,
  AcceptVendorBillMatchWithinToleranceInputSchema,
  RaiseVendorBillMatchDisputeInputSchema,
  RecordVendorBillMatchDisputeResponseInputSchema,
  ResolveVendorBillMatchDisputeInputSchema,
  RequestVendorBillMatchExceptionApprovalInputSchema,
  DecideVendorBillMatchExceptionApprovalInputSchema,
  CancelVendorBillMatchCaseInputSchema,
  parseVendorBillMatchTolerancePolicy,
  parseVendorBillMatchCase,
  parseVendorBillMatchLine,
  parseVendorBillMatchDispute,
  parseVendorBillMatchExceptionApproval,
  type CreateVendorBillMatchTolerancePolicyDraftInput,
  type UpdateVendorBillMatchTolerancePolicyDraftInput,
  type ActivateVendorBillMatchTolerancePolicyInput,
  type CreateVendorBillMatchCaseInput,
  type ReEvaluateVendorBillMatchCaseInput,
  type MapVendorBillMatchLineInput,
  type AcceptVendorBillMatchWithinToleranceInput,
  type RaiseVendorBillMatchDisputeInput,
  type RecordVendorBillMatchDisputeResponseInput,
  type ResolveVendorBillMatchDisputeInput,
  type RequestVendorBillMatchExceptionApprovalInput,
  type DecideVendorBillMatchExceptionApprovalInput,
  type CancelVendorBillMatchCaseInput,
  type VendorBillMatchTolerancePolicy,
  type VendorBillMatchCase,
  type VendorBillMatchLine,
  type VendorBillMatchDispute,
  type VendorBillMatchExceptionApproval,
} from "../contracts/vendor-invoice-matching/vendor-invoice-matching.ts";

export type VendorInvoiceMatchingMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const VENDOR_INVOICE_MATCHING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "self_approval_not_allowed",
  "vendor_bill_match_tolerance_policy_not_found",
  "vendor_bill_match_case_not_found",
  "vendor_bill_match_line_not_found",
  "vendor_bill_match_dispute_not_found",
  "vendor_bill_match_exception_approval_not_found",
  "finance_vendor_bill_not_found",
  "finance_vendor_bill_void",
  "match_case_already_exists",
  "match_case_lookup_required",
  "line_inputs_required",
  "vendor_stated_amount_required",
  "purchase_order_not_found",
  "po_vendor_mismatch",
  "po_not_committed",
  "po_currency_mismatch",
  "po_line_scope_mismatch",
  "rate_version_scope_mismatch",
  "evidence_file_not_found",
  "dispute_evidence_file_mismatch",
  "dispute_unsafe_evidence",
  "dispute_already_open",
  "exception_approval_already_pending",
  "invalid_decision",
  "reason_required",
  "stale_version",
  "invalid_transition",
] as const;
type KnownVendorInvoiceMatchingMutationErrorCode = (typeof VENDOR_INVOICE_MATCHING_KNOWN_MUTATION_ERROR_CODES)[number];
export type VendorInvoiceMatchingMutationErrorCode = KnownVendorInvoiceMatchingMutationErrorCode | "mutation_failed" | "invalid_response";

export class VendorInvoiceMatchingMutationError extends Error {
  readonly code: VendorInvoiceMatchingMutationErrorCode;

  constructor(code: VendorInvoiceMatchingMutationErrorCode, message: string) {
    super(message);
    this.name = "VendorInvoiceMatchingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): VendorInvoiceMatchingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (VENDOR_INVOICE_MATCHING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownVendorInvoiceMatchingMutationErrorCode) : "mutation_failed";
}

async function callRpc(client: VendorInvoiceMatchingMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new VendorInvoiceMatchingMutationError(classifyError(error.message), error.message);
  }
  return data;
}

function requireRow<T>(data: unknown, fn: string, parse: (row: Record<string, unknown>) => T): T {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorInvoiceMatchingMutationError("invalid_response", `${fn} returned no row`);
  }
  return parse(row as Record<string, unknown>);
}

// -- Tolerance policy --------------------------------------------------------

export async function createVendorBillMatchTolerancePolicyDraft(client: VendorInvoiceMatchingMutationRpcClient, input: CreateVendorBillMatchTolerancePolicyDraftInput): Promise<VendorBillMatchTolerancePolicy> {
  const parsed = CreateVendorBillMatchTolerancePolicyDraftInputSchema.parse(input);
  const data = await callRpc(client, "create_vendor_bill_match_tolerance_policy_draft", {
    p_tenant_id: parsed.tenantId,
    p_name: parsed.name,
    p_quantity_tolerance_pct: parsed.quantityTolerancePct,
    p_rate_tolerance_pct: parsed.rateTolerancePct,
    p_tax_tolerance_pct: parsed.taxTolerancePct,
    p_line_amount_tolerance_abs: parsed.lineAmountToleranceAbs,
    p_auto_clear_enabled: parsed.autoClearEnabled,
    p_duplicate_window_days: parsed.duplicateWindowDays,
    p_notes: parsed.notes,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRow(data, "create_vendor_bill_match_tolerance_policy_draft", parseVendorBillMatchTolerancePolicy);
}

export async function updateVendorBillMatchTolerancePolicyDraft(client: VendorInvoiceMatchingMutationRpcClient, input: UpdateVendorBillMatchTolerancePolicyDraftInput): Promise<VendorBillMatchTolerancePolicy> {
  const parsed = UpdateVendorBillMatchTolerancePolicyDraftInputSchema.parse(input);
  const data = await callRpc(client, "update_vendor_bill_match_tolerance_policy_draft", {
    p_policy_id: parsed.policyId,
    p_expected_version: parsed.expectedVersion,
    p_name: parsed.name,
    p_quantity_tolerance_pct: parsed.quantityTolerancePct,
    p_rate_tolerance_pct: parsed.rateTolerancePct,
    p_tax_tolerance_pct: parsed.taxTolerancePct,
    p_line_amount_tolerance_abs: parsed.lineAmountToleranceAbs,
    p_auto_clear_enabled: parsed.autoClearEnabled,
    p_duplicate_window_days: parsed.duplicateWindowDays,
    p_notes: parsed.notes,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRow(data, "update_vendor_bill_match_tolerance_policy_draft", parseVendorBillMatchTolerancePolicy);
}

export async function activateVendorBillMatchTolerancePolicy(client: VendorInvoiceMatchingMutationRpcClient, input: ActivateVendorBillMatchTolerancePolicyInput): Promise<VendorBillMatchTolerancePolicy> {
  const parsed = ActivateVendorBillMatchTolerancePolicyInputSchema.parse(input);
  const data = await callRpc(client, "activate_vendor_bill_match_tolerance_policy", {
    p_policy_id: parsed.policyId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRow(data, "activate_vendor_bill_match_tolerance_policy", parseVendorBillMatchTolerancePolicy);
}

// -- Match case ----------------------------------------------------------------

export async function createVendorBillMatchCase(client: VendorInvoiceMatchingMutationRpcClient, input: CreateVendorBillMatchCaseInput): Promise<VendorBillMatchCase> {
  const parsed = CreateVendorBillMatchCaseInputSchema.parse(input);
  const data = await callRpc(client, "create_vendor_bill_match_case", {
    p_tenant_id: parsed.tenantId,
    p_bill_id: parsed.billId,
    p_purchase_order_id: parsed.purchaseOrderId,
    p_is_partial_invoice: parsed.isPartialInvoice,
    p_is_consolidated_invoice: parsed.isConsolidatedInvoice,
    p_line_inputs: parsed.lineInputs.map((l) => ({ billLineId: l.billLineId, vendorStatedQuantity: l.vendorStatedQuantity, vendorStatedUom: l.vendorStatedUom, vendorStatedRate: l.vendorStatedRate, vendorStatedAmount: l.vendorStatedAmount })),
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRow(data, "create_vendor_bill_match_case", parseVendorBillMatchCase);
}

export async function reEvaluateVendorBillMatchCase(client: VendorInvoiceMatchingMutationRpcClient, input: ReEvaluateVendorBillMatchCaseInput): Promise<VendorBillMatchCase> {
  const parsed = ReEvaluateVendorBillMatchCaseInputSchema.parse(input);
  const data = await callRpc(client, "re_evaluate_vendor_bill_match_case", {
    p_match_case_id: parsed.matchCaseId,
    p_expected_version: parsed.expectedVersion,
    p_purchase_order_id: parsed.purchaseOrderId,
    p_line_inputs: parsed.lineInputs.map((l) => ({ billLineId: l.billLineId, vendorStatedQuantity: l.vendorStatedQuantity, vendorStatedUom: l.vendorStatedUom, vendorStatedRate: l.vendorStatedRate, vendorStatedAmount: l.vendorStatedAmount })),
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRow(data, "re_evaluate_vendor_bill_match_case", parseVendorBillMatchCase);
}

export async function mapVendorBillMatchLine(client: VendorInvoiceMatchingMutationRpcClient, input: MapVendorBillMatchLineInput): Promise<VendorBillMatchLine> {
  const parsed = MapVendorBillMatchLineInputSchema.parse(input);
  const data = await callRpc(client, "map_vendor_bill_match_line", {
    p_match_line_id: parsed.matchLineId,
    p_expected_case_version: parsed.expectedCaseVersion,
    p_po_line_id: parsed.poLineId,
    p_rate_version_id: parsed.rateVersionId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRow(data, "map_vendor_bill_match_line", parseVendorBillMatchLine);
}

export async function acceptVendorBillMatchWithinTolerance(client: VendorInvoiceMatchingMutationRpcClient, input: AcceptVendorBillMatchWithinToleranceInput): Promise<VendorBillMatchCase> {
  const parsed = AcceptVendorBillMatchWithinToleranceInputSchema.parse(input);
  const data = await callRpc(client, "accept_vendor_bill_match_within_tolerance", {
    p_match_case_id: parsed.matchCaseId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRow(data, "accept_vendor_bill_match_within_tolerance", parseVendorBillMatchCase);
}

export async function cancelVendorBillMatchCase(client: VendorInvoiceMatchingMutationRpcClient, input: CancelVendorBillMatchCaseInput): Promise<VendorBillMatchCase> {
  const parsed = CancelVendorBillMatchCaseInputSchema.parse(input);
  const data = await callRpc(client, "cancel_vendor_bill_match_case", {
    p_match_case_id: parsed.matchCaseId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRow(data, "cancel_vendor_bill_match_case", parseVendorBillMatchCase);
}

// -- Disputes -------------------------------------------------------------------

export async function raiseVendorBillMatchDispute(client: VendorInvoiceMatchingMutationRpcClient, input: RaiseVendorBillMatchDisputeInput): Promise<VendorBillMatchDispute> {
  const parsed = RaiseVendorBillMatchDisputeInputSchema.parse(input);
  const data = await callRpc(client, "raise_vendor_bill_match_dispute", {
    p_match_case_id: parsed.matchCaseId,
    p_match_line_id: parsed.matchLineId,
    p_reason: parsed.reason,
    p_disputed_amount: parsed.disputedAmount,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRow(data, "raise_vendor_bill_match_dispute", parseVendorBillMatchDispute);
}

export async function recordVendorBillMatchDisputeResponse(client: VendorInvoiceMatchingMutationRpcClient, input: RecordVendorBillMatchDisputeResponseInput): Promise<VendorBillMatchDispute> {
  const parsed = RecordVendorBillMatchDisputeResponseInputSchema.parse(input);
  const data = await callRpc(client, "record_vendor_bill_match_dispute_response", {
    p_dispute_id: parsed.disputeId,
    p_expected_version: parsed.expectedVersion,
    p_vendor_response: parsed.vendorResponse,
    p_vendor_response_file_id: parsed.vendorResponseFileId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRow(data, "record_vendor_bill_match_dispute_response", parseVendorBillMatchDispute);
}

export async function resolveVendorBillMatchDispute(client: VendorInvoiceMatchingMutationRpcClient, input: ResolveVendorBillMatchDisputeInput): Promise<VendorBillMatchDispute> {
  const parsed = ResolveVendorBillMatchDisputeInputSchema.parse(input);
  const data = await callRpc(client, "resolve_vendor_bill_match_dispute", {
    p_dispute_id: parsed.disputeId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_resolution_note: parsed.resolutionNote,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRow(data, "resolve_vendor_bill_match_dispute", parseVendorBillMatchDispute);
}

// -- Exception approvals ---------------------------------------------------------

export async function requestVendorBillMatchExceptionApproval(client: VendorInvoiceMatchingMutationRpcClient, input: RequestVendorBillMatchExceptionApprovalInput): Promise<VendorBillMatchExceptionApproval> {
  const parsed = RequestVendorBillMatchExceptionApprovalInputSchema.parse(input);
  const data = await callRpc(client, "request_vendor_bill_match_exception_approval", {
    p_match_case_id: parsed.matchCaseId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRow(data, "request_vendor_bill_match_exception_approval", parseVendorBillMatchExceptionApproval);
}

export async function decideVendorBillMatchExceptionApproval(client: VendorInvoiceMatchingMutationRpcClient, input: DecideVendorBillMatchExceptionApprovalInput): Promise<VendorBillMatchExceptionApproval> {
  const parsed = DecideVendorBillMatchExceptionApprovalInputSchema.parse(input);
  const data = await callRpc(client, "decide_vendor_bill_match_exception_approval", {
    p_approval_id: parsed.approvalId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_decision_note: parsed.decisionNote,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireRow(data, "decide_vendor_bill_match_exception_approval", parseVendorBillMatchExceptionApproval);
}
