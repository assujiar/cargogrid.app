/**
 * Settlement mutation primitives (FIN-201, CG-S9-FIN-012). Thin, typed
 * wrappers around app.prepare_finance_settlement / app.submit_finance_settlement_for_approval /
 * app.discard_finance_settlement_draft / app.approve_finance_settlement /
 * app.execute_finance_settlement / app.post_finance_settlement /
 * app.request_finance_settlement_reversal
 * (supabase/migrations/20260729150000_create_finance_settlement.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  PrepareFinanceSettlementInputSchema,
  FinanceSettlementLifecycleInputSchema,
  DiscardFinanceSettlementDraftInputSchema,
  ExecuteFinanceSettlementInputSchema,
  RequestFinanceSettlementReversalInputSchema,
  parseFinanceSettlement,
  type PrepareFinanceSettlementInput,
  type FinanceSettlementLifecycleInput,
  type DiscardFinanceSettlementDraftInput,
  type ExecuteFinanceSettlementInput,
  type RequestFinanceSettlementReversalInput,
  type FinanceSettlement,
} from "../contracts/settlement/settlement.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type SettlementMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const SETTLEMENT_KNOWN_MUTATION_ERROR_CODES = [
  // ATW-032: an executed settlement whose AP open item was consumed by a competitor can
  // now be voided under FIN:Approve with a mandatory reason -- these are its two new codes.
  "finance_settlement_void_reason_required",
  "insufficient_authority",
  "idempotency_key_required",
  "finance_settlement_vendor_not_found",
  "finance_settlement_unsupported_currency",
  "finance_settlement_invalid_fee",
  "finance_settlement_empty_allocation",
  "finance_settlement_invalid_allocation_amount",
  "finance_settlement_open_item_not_found",
  "finance_settlement_vendor_mismatch",
  "finance_settlement_currency_mismatch",
  "finance_settlement_open_item_held",
  "finance_settlement_open_item_already_settled",
  "finance_settlement_over_allocation",
  "finance_settlement_not_found",
  "finance_settlement_not_draft",
  "finance_settlement_not_submitted",
  "finance_settlement_not_approved",
  "finance_settlement_not_executed",
  "finance_settlement_not_posted",
  "finance_settlement_not_cancellable",
  "finance_settlement_reversal_reason_required",
  "finance_settlement_period_not_found",
  "finance_settlement_period_not_open",
  "stale_version",
] as const;
type KnownSettlementMutationErrorCode = (typeof SETTLEMENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type SettlementMutationErrorCode = KnownSettlementMutationErrorCode | "mutation_failed" | "invalid_response";

export class SettlementMutationError extends Error {
  readonly code: SettlementMutationErrorCode;

  constructor(code: SettlementMutationErrorCode, message: string) {
    super(message);
    this.name = "SettlementMutationError";
    this.code = code;
  }
}

function classifyError(message: string): SettlementMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (SETTLEMENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownSettlementMutationErrorCode) : "mutation_failed";
}

async function callAndParseSettlement(
  client: SettlementMutationRpcClient,
  fn:
    | "prepare_finance_settlement"
    | "submit_finance_settlement_for_approval"
    | "discard_finance_settlement_draft"
    | "approve_finance_settlement"
    | "execute_finance_settlement"
    | "post_finance_settlement"
    | "request_finance_settlement_reversal",
  args: Record<string, unknown>,
): Promise<FinanceSettlement> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new SettlementMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new SettlementMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseFinanceSettlement(data as Record<string, unknown>);
}

/** FIN:Edit-gated, idempotent on (tenantId, idempotencyKey). Validates vendor/currency/held/settled/over-allocation for a fixed set of AP allocation lines decided once. */
export async function prepareFinanceSettlement(client: SettlementMutationRpcClient, input: PrepareFinanceSettlementInput): Promise<FinanceSettlement> {
  const parsedInput = PrepareFinanceSettlementInputSchema.parse(input);
  return callAndParseSettlement(client, "prepare_finance_settlement", {
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_vendor_master_id: parsedInput.vendorMasterId,
    p_payment_reference: parsedInput.paymentReference,
    p_bank_account_label: parsedInput.bankAccountLabel,
    p_currency: parsedInput.currency,
    p_settlement_date: parsedInput.settlementDate,
    p_allocations: parsedInput.allocations.map((line) => ({ apOpenItemId: line.apOpenItemId, amount: line.amount })),
    p_fee_amount: parsedInput.feeAmount,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated. draft -> submitted. */
export async function submitFinanceSettlementForApproval(client: SettlementMutationRpcClient, input: FinanceSettlementLifecycleInput): Promise<FinanceSettlement> {
  const parsedInput = FinanceSettlementLifecycleInputSchema.parse(input);
  return callAndParseSettlement(client, "submit_finance_settlement_for_approval", {
    p_settlement_id: parsedInput.settlementId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated. draft/submitted -> void. Rejected once approved -- correction past that point is only via a governed reversal after posting. */
export async function discardFinanceSettlementDraft(client: SettlementMutationRpcClient, input: DiscardFinanceSettlementDraftInput): Promise<FinanceSettlement> {
  const parsedInput = DiscardFinanceSettlementDraftInputSchema.parse(input);
  return callAndParseSettlement(client, "discard_finance_settlement_draft", {
    p_settlement_id: parsedInput.settlementId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}

/** FIN:Approve-gated. submitted -> approved. */
export async function approveFinanceSettlement(client: SettlementMutationRpcClient, input: FinanceSettlementLifecycleInput): Promise<FinanceSettlement> {
  const parsedInput = FinanceSettlementLifecycleInputSchema.parse(input);
  return callAndParseSettlement(client, "approve_finance_settlement", {
    p_settlement_id: parsedInput.settlementId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}

/** FIN:Approve-gated. approved -> executed. Records that the payment instruction actually left the bank/payment channel -- a distinct canonical state from posting, carrying zero AP/cash effect by itself. */
export async function executeFinanceSettlement(client: SettlementMutationRpcClient, input: ExecuteFinanceSettlementInput): Promise<FinanceSettlement> {
  const parsedInput = ExecuteFinanceSettlementInputSchema.parse(input);
  return callAndParseSettlement(client, "execute_finance_settlement", {
    p_settlement_id: parsedInput.settlementId,
    p_expected_version: parsedInput.expectedVersion,
    p_execution_reference: parsedInput.executionReference,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}

/** FIN:Approve-gated, period-aware, idempotent. executed -> posted; generates a real settlement_number and applies FIN-199's own app.apply_finance_ap_settlement once per allocation line. A retried call against an already-posted settlement returns it unchanged. */
export async function postFinanceSettlement(client: SettlementMutationRpcClient, input: FinanceSettlementLifecycleInput): Promise<FinanceSettlement> {
  const parsedInput = FinanceSettlementLifecycleInputSchema.parse(input);
  return callAndParseSettlement(client, "post_finance_settlement", {
    p_settlement_id: parsedInput.settlementId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}

/** FIN:Approve-gated, mandatory reason. posted -> reversed; reverses every allocation line via FIN-199's own app.reverse_finance_ap_settlement, restoring the AP balance -- never a direct edit. */
export async function requestFinanceSettlementReversal(client: SettlementMutationRpcClient, input: RequestFinanceSettlementReversalInput): Promise<FinanceSettlement> {
  const parsedInput = RequestFinanceSettlementReversalInputSchema.parse(input);
  return callAndParseSettlement(client, "request_finance_settlement_reversal", {
    p_settlement_id: parsedInput.settlementId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}
