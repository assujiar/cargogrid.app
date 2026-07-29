/**
 * Vendor Bill mutation primitives (FIN-200, CG-S9-FIN-011). Thin, typed
 * wrappers around app.prepare_finance_vendor_bill_from_actual_cost /
 * app.submit_finance_vendor_bill_for_approval / app.discard_finance_vendor_bill_draft /
 * app.approve_finance_vendor_bill / app.post_finance_vendor_bill
 * (supabase/migrations/20260729140000_create_finance_vendor_bill.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  PrepareFinanceVendorBillFromActualCostInputSchema,
  FinanceVendorBillLifecycleInputSchema,
  DiscardFinanceVendorBillDraftInputSchema,
  parseFinanceVendorBill,
  type PrepareFinanceVendorBillFromActualCostInput,
  type FinanceVendorBillLifecycleInput,
  type DiscardFinanceVendorBillDraftInput,
  type FinanceVendorBill,
} from "../contracts/vendor-bill/vendor-bill.ts";

export type VendorBillMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const VENDOR_BILL_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "finance_vendor_bill_actual_cost_not_found",
  "finance_vendor_bill_actual_cost_not_approved",
  "finance_vendor_bill_vendor_not_found",
  "finance_vendor_bill_no_matching_components",
  "finance_vendor_bill_not_found",
  "finance_vendor_bill_not_draft",
  "finance_vendor_bill_not_submitted",
  "finance_vendor_bill_not_approved",
  "finance_vendor_bill_not_cancellable",
  "finance_vendor_bill_period_not_found",
  "finance_vendor_bill_period_not_open",
  "finance_tax_rule_missing",
  "stale_version",
] as const;
type KnownVendorBillMutationErrorCode = (typeof VENDOR_BILL_KNOWN_MUTATION_ERROR_CODES)[number];
export type VendorBillMutationErrorCode = KnownVendorBillMutationErrorCode | "mutation_failed" | "invalid_response";

export class VendorBillMutationError extends Error {
  readonly code: VendorBillMutationErrorCode;

  constructor(code: VendorBillMutationErrorCode, message: string) {
    super(message);
    this.name = "VendorBillMutationError";
    this.code = code;
  }
}

function classifyError(message: string): VendorBillMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (VENDOR_BILL_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownVendorBillMutationErrorCode) : "mutation_failed";
}

async function callAndParseVendorBill(
  client: VendorBillMutationRpcClient,
  fn: "prepare_finance_vendor_bill_from_actual_cost" | "submit_finance_vendor_bill_for_approval" | "discard_finance_vendor_bill_draft" | "approve_finance_vendor_bill" | "post_finance_vendor_bill",
  args: Record<string, unknown>,
): Promise<FinanceVendorBill> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new VendorBillMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new VendorBillMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseFinanceVendorBill(data as Record<string, unknown>);
}

/** FIN:Edit-gated, idempotent on (tenantId, actualCostId, vendorMasterId). Sums only the requested vendor's own approved actual-cost components; an optional vendorStatedAmount sets basic-match variance; an optional tax code calls FIN-195's own calculation service. */
export async function prepareFinanceVendorBillFromActualCost(
  client: VendorBillMutationRpcClient,
  input: PrepareFinanceVendorBillFromActualCostInput,
): Promise<FinanceVendorBill> {
  const parsedInput = PrepareFinanceVendorBillFromActualCostInputSchema.parse(input);
  return callAndParseVendorBill(client, "prepare_finance_vendor_bill_from_actual_cost", {
    p_tenant_id: parsedInput.tenantId,
    p_actual_cost_id: parsedInput.actualCostId,
    p_vendor_master_id: parsedInput.vendorMasterId,
    p_vendor_reference: parsedInput.vendorReference,
    p_bill_date: parsedInput.billDate,
    p_payment_term_days: parsedInput.paymentTermDays,
    p_vendor_stated_amount: parsedInput.vendorStatedAmount,
    p_tax_code: parsedInput.taxCode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated. draft -> submitted. */
export async function submitFinanceVendorBillForApproval(client: VendorBillMutationRpcClient, input: FinanceVendorBillLifecycleInput): Promise<FinanceVendorBill> {
  const parsedInput = FinanceVendorBillLifecycleInputSchema.parse(input);
  return callAndParseVendorBill(client, "submit_finance_vendor_bill_for_approval", {
    p_bill_id: parsedInput.billId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated. draft/submitted -> void. Rejected once approved or posted -- a normal role cannot edit a posted bill; correction is only via a governed reversal. */
export async function discardFinanceVendorBillDraft(client: VendorBillMutationRpcClient, input: DiscardFinanceVendorBillDraftInput): Promise<FinanceVendorBill> {
  const parsedInput = DiscardFinanceVendorBillDraftInputSchema.parse(input);
  return callAndParseVendorBill(client, "discard_finance_vendor_bill_draft", {
    p_bill_id: parsedInput.billId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated. submitted -> approved. A requires_approval variance discloses to the approver but does not itself block approval. */
export async function approveFinanceVendorBill(client: VendorBillMutationRpcClient, input: FinanceVendorBillLifecycleInput): Promise<FinanceVendorBill> {
  const parsedInput = FinanceVendorBillLifecycleInputSchema.parse(input);
  return callAndParseVendorBill(client, "approve_finance_vendor_bill", {
    p_bill_id: parsedInput.billId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated, period-aware, idempotent. approved -> posted; generates a real bill_number and posts exactly one FIN-199 AP open item. A retried call against an already-posted bill returns it unchanged. */
export async function postFinanceVendorBill(client: VendorBillMutationRpcClient, input: FinanceVendorBillLifecycleInput): Promise<FinanceVendorBill> {
  const parsedInput = FinanceVendorBillLifecycleInputSchema.parse(input);
  return callAndParseVendorBill(client, "post_finance_vendor_bill", {
    p_bill_id: parsedInput.billId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}
