/**
 * Receipt and Payment Allocation mutation primitives (FIN-198, CG-S9-FIN-009).
 * Thin, typed wrappers around app.capture_finance_receipt /
 * app.allocate_finance_receipt / app.request_finance_receipt_deallocation
 * (supabase/migrations/20260729120000_create_finance_receipt_allocation.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CaptureFinanceReceiptInputSchema,
  AllocateFinanceReceiptInputSchema,
  RequestFinanceReceiptDeallocationInputSchema,
  parseFinanceReceipt,
  type CaptureFinanceReceiptInput,
  type AllocateFinanceReceiptInput,
  type RequestFinanceReceiptDeallocationInput,
  type FinanceReceipt,
} from "../contracts/receipt-allocation/receipt-allocation.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type ReceiptAllocationMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const RECEIPT_ALLOCATION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "idempotency_key_required",
  "finance_receipt_customer_not_found",
  "finance_receipt_unsupported_currency",
  "finance_receipt_invalid_amount",
  "finance_receipt_period_not_found",
  "finance_receipt_period_not_open",
  "finance_receipt_duplicate_reference",
  "finance_receipt_not_found",
  "finance_receipt_empty_allocation",
  "finance_receipt_invalid_allocation_amount",
  "finance_receipt_over_allocation",
  "finance_receipt_open_item_not_found",
  "finance_receipt_customer_mismatch",
  "finance_receipt_currency_mismatch",
  "finance_receipt_allocation_not_found",
  "finance_receipt_deallocation_reason_required",
  "finance_receipt_allocation_not_applied",
  "stale_version",
] as const;
type KnownReceiptAllocationMutationErrorCode = (typeof RECEIPT_ALLOCATION_KNOWN_MUTATION_ERROR_CODES)[number];
export type ReceiptAllocationMutationErrorCode = KnownReceiptAllocationMutationErrorCode | "mutation_failed" | "invalid_response";

export class ReceiptAllocationMutationError extends Error {
  readonly code: ReceiptAllocationMutationErrorCode;

  constructor(code: ReceiptAllocationMutationErrorCode, message: string) {
    super(message);
    this.name = "ReceiptAllocationMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ReceiptAllocationMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (RECEIPT_ALLOCATION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownReceiptAllocationMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseReceipt(
  client: ReceiptAllocationMutationRpcClient,
  fn: "capture_finance_receipt" | "allocate_finance_receipt" | "request_finance_receipt_deallocation",
  args: Record<string, unknown>,
): Promise<FinanceReceipt> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new ReceiptAllocationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ReceiptAllocationMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseFinanceReceipt(data as Record<string, unknown>);
}

/** FIN:Edit-gated, idempotent on idempotencyKey. Rejects an unknown customer, unsupported currency, non-positive amount, a closed fiscal period, or a duplicate bank reference. */
export async function captureFinanceReceipt(client: ReceiptAllocationMutationRpcClient, input: CaptureFinanceReceiptInput): Promise<FinanceReceipt> {
  const parsedInput = CaptureFinanceReceiptInputSchema.parse(input);
  return callAndParseReceipt(client, "capture_finance_receipt", {
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_customer_account_id: parsedInput.customerAccountId,
    p_receipt_reference: parsedInput.receiptReference,
    p_receipt_date: parsedInput.receiptDate,
    p_payer_name: parsedInput.payerName,
    p_bank_account_label: parsedInput.bankAccountLabel,
    p_currency: parsedInput.currency,
    p_amount: parsedInput.amount,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/**
 * FIN:Edit-gated, idempotent on idempotencyKey, row-locked. Rejects when the
 * total allocation exceeds the receipt's own current unapplied amount, or
 * when any line targets an AR open item outside the receipt's own
 * customer/currency scope. Delegates every balance mutation to FIN-196's own
 * app.apply_finance_ar_allocation.
 */
export async function allocateFinanceReceipt(client: ReceiptAllocationMutationRpcClient, input: AllocateFinanceReceiptInput): Promise<FinanceReceipt> {
  const parsedInput = AllocateFinanceReceiptInputSchema.parse(input);
  return callAndParseReceipt(client, "allocate_finance_receipt", {
    p_receipt_id: parsedInput.receiptId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_allocations: parsedInput.allocations.map((line) => ({ arOpenItemId: line.arOpenItemId, amount: line.amount })),
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated (governed reversal, never a direct edit). Requires a non-empty reason. Rejected once the allocation is already reversed. Delegates to FIN-196's own app.reverse_finance_ar_allocation. */
export async function requestFinanceReceiptDeallocation(client: ReceiptAllocationMutationRpcClient, input: RequestFinanceReceiptDeallocationInput): Promise<FinanceReceipt> {
  const parsedInput = RequestFinanceReceiptDeallocationInputSchema.parse(input);
  return callAndParseReceipt(client, "request_finance_receipt_deallocation", {
    p_allocation_id: parsedInput.allocationId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}
