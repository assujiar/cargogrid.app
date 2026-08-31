/**
 * Accounts Payable mutation primitives (FIN-199, CG-S9-FIN-010). Thin, typed
 * wrappers around app.post_finance_ap_open_item / app.place_finance_ap_hold /
 * app.release_finance_ap_hold / app.apply_finance_ap_settlement /
 * app.reverse_finance_ap_settlement
 * (supabase/migrations/20260729130000_create_finance_accounts_payable.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  PostFinanceApOpenItemInputSchema,
  PlaceFinanceApHoldInputSchema,
  ReleaseFinanceApHoldInputSchema,
  ApplyFinanceApSettlementInputSchema,
  ReverseFinanceApSettlementInputSchema,
  parseFinanceApOpenItem,
  type PostFinanceApOpenItemInput,
  type PlaceFinanceApHoldInput,
  type ReleaseFinanceApHoldInput,
  type ApplyFinanceApSettlementInput,
  type ReverseFinanceApSettlementInput,
  type FinanceApOpenItem,
} from "../contracts/accounts-payable/accounts-payable.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type AccountsPayableMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ACCOUNTS_PAYABLE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "finance_ap_unsupported_source_type",
  "finance_ap_vendor_not_found",
  "finance_ap_unsupported_currency",
  "finance_ap_invalid_amount",
  "finance_ap_invalid_due_date",
  "finance_ap_period_not_found",
  "finance_ap_period_not_open",
  "finance_ap_open_item_not_found",
  "finance_ap_hold_reason_required",
  "finance_ap_already_held",
  "finance_ap_not_held",
  "finance_ap_invalid_settlement_amount",
  "finance_ap_over_settlement",
  "finance_ap_over_reversal",
  "finance_ap_unsettlement_reason_required",
  "stale_version",
] as const;
type KnownAccountsPayableMutationErrorCode = (typeof ACCOUNTS_PAYABLE_KNOWN_MUTATION_ERROR_CODES)[number];
export type AccountsPayableMutationErrorCode = KnownAccountsPayableMutationErrorCode | "mutation_failed" | "invalid_response";

export class AccountsPayableMutationError extends Error {
  readonly code: AccountsPayableMutationErrorCode;

  constructor(code: AccountsPayableMutationErrorCode, message: string) {
    super(message);
    this.name = "AccountsPayableMutationError";
    this.code = code;
  }
}

function classifyError(message: string): AccountsPayableMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ACCOUNTS_PAYABLE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownAccountsPayableMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseItem(
  client: AccountsPayableMutationRpcClient,
  fn: "post_finance_ap_open_item" | "place_finance_ap_hold" | "release_finance_ap_hold" | "apply_finance_ap_settlement" | "reverse_finance_ap_settlement",
  args: Record<string, unknown>,
): Promise<FinanceApOpenItem> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new AccountsPayableMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AccountsPayableMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseFinanceApOpenItem(data as Record<string, unknown>);
}

/**
 * Idempotent on (tenantId, sourceDocumentType, sourceDocumentId) -- a
 * retried call for the same source document returns the existing open item
 * rather than raising a duplicate error. `vendor_bill` requires FIN:Edit;
 * `opening_balance` requires FIN:Approve.
 */
export async function postFinanceApOpenItem(client: AccountsPayableMutationRpcClient, input: PostFinanceApOpenItemInput): Promise<FinanceApOpenItem> {
  const parsedInput = PostFinanceApOpenItemInputSchema.parse(input);
  return callAndParseItem(client, "post_finance_ap_open_item", {
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_vendor_master_id: parsedInput.vendorMasterId,
    p_source_document_type: parsedInput.sourceDocumentType,
    p_source_document_id: parsedInput.sourceDocumentId,
    p_currency: parsedInput.currency,
    p_original_amount: parsedInput.originalAmount,
    p_bill_date: parsedInput.billDate,
    p_due_date: parsedInput.dueDate,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated. Requires a non-empty reason. Rejected if already held. */
export async function placeFinanceApHold(client: AccountsPayableMutationRpcClient, input: PlaceFinanceApHoldInput): Promise<FinanceApOpenItem> {
  const parsedInput = PlaceFinanceApHoldInputSchema.parse(input);
  return callAndParseItem(client, "place_finance_ap_hold", {
    p_open_item_id: parsedInput.openItemId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated (governed release, distinct authority from placing a hold). Rejected if not currently held. */
export async function releaseFinanceApHold(client: AccountsPayableMutationRpcClient, input: ReleaseFinanceApHoldInput): Promise<FinanceApOpenItem> {
  const parsedInput = ReleaseFinanceApHoldInputSchema.parse(input);
  return callAndParseItem(client, "release_finance_ap_hold", {
    p_open_item_id: parsedInput.openItemId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}

/** FIN:Edit-gated, row-locked, idempotent on idempotencyKey. Rejected if the amount exceeds the open item's own current open amount. */
export async function applyFinanceApSettlement(client: AccountsPayableMutationRpcClient, input: ApplyFinanceApSettlementInput): Promise<FinanceApOpenItem> {
  const parsedInput = ApplyFinanceApSettlementInputSchema.parse(input);
  return callAndParseItem(client, "apply_finance_ap_settlement", {
    p_open_item_id: parsedInput.openItemId,
    p_amount: parsedInput.amount,
    p_source_type: parsedInput.sourceType,
    p_source_id: parsedInput.sourceId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated (governed reversal, never a direct edit). Requires a non-empty reason. Rejected if the amount exceeds the item's own currently-settled amount. */
export async function reverseFinanceApSettlement(client: AccountsPayableMutationRpcClient, input: ReverseFinanceApSettlementInput): Promise<FinanceApOpenItem> {
  const parsedInput = ReverseFinanceApSettlementInputSchema.parse(input);
  return callAndParseItem(client, "reverse_finance_ap_settlement", {
    p_open_item_id: parsedInput.openItemId,
    p_amount: parsedInput.amount,
    p_reason: parsedInput.reason,
    p_source_type: parsedInput.sourceType,
    p_source_id: parsedInput.sourceId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}
