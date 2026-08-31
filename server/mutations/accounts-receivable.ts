/**
 * Accounts Receivable mutation primitives (FIN-196, CG-S9-FIN-007). Thin,
 * typed wrappers around app.post_finance_ar_open_item /
 * app.place_finance_ar_hold / app.release_finance_ar_hold /
 * app.apply_finance_ar_allocation / app.reverse_finance_ar_allocation
 * (supabase/migrations/20260729100000_create_finance_accounts_receivable.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  PostFinanceArOpenItemInputSchema,
  PlaceFinanceArHoldInputSchema,
  ReleaseFinanceArHoldInputSchema,
  ApplyFinanceArAllocationInputSchema,
  ReverseFinanceArAllocationInputSchema,
  parseFinanceArOpenItem,
  type PostFinanceArOpenItemInput,
  type PlaceFinanceArHoldInput,
  type ReleaseFinanceArHoldInput,
  type ApplyFinanceArAllocationInput,
  type ReverseFinanceArAllocationInput,
  type FinanceArOpenItem,
} from "../contracts/accounts-receivable/accounts-receivable.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type AccountsReceivableMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ACCOUNTS_RECEIVABLE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "finance_ar_unsupported_source_type",
  "finance_ar_customer_not_found",
  "finance_ar_unsupported_currency",
  "finance_ar_invalid_amount",
  "finance_ar_invalid_due_date",
  "finance_ar_period_not_found",
  "finance_ar_period_not_open",
  "finance_ar_open_item_not_found",
  "finance_ar_hold_reason_required",
  "finance_ar_already_held",
  "finance_ar_not_held",
  "finance_ar_invalid_allocation_amount",
  "finance_ar_over_allocation",
  "finance_ar_over_reversal",
  "finance_ar_deallocation_reason_required",
  "stale_version",
] as const;
type KnownAccountsReceivableMutationErrorCode = (typeof ACCOUNTS_RECEIVABLE_KNOWN_MUTATION_ERROR_CODES)[number];
export type AccountsReceivableMutationErrorCode = KnownAccountsReceivableMutationErrorCode | "mutation_failed" | "invalid_response";

export class AccountsReceivableMutationError extends Error {
  readonly code: AccountsReceivableMutationErrorCode;

  constructor(code: AccountsReceivableMutationErrorCode, message: string) {
    super(message);
    this.name = "AccountsReceivableMutationError";
    this.code = code;
  }
}

function classifyError(message: string): AccountsReceivableMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ACCOUNTS_RECEIVABLE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownAccountsReceivableMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseItem(
  client: AccountsReceivableMutationRpcClient,
  fn: "post_finance_ar_open_item" | "place_finance_ar_hold" | "release_finance_ar_hold" | "apply_finance_ar_allocation" | "reverse_finance_ar_allocation",
  args: Record<string, unknown>,
): Promise<FinanceArOpenItem> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new AccountsReceivableMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AccountsReceivableMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseFinanceArOpenItem(data as Record<string, unknown>);
}

/**
 * Idempotent on (tenantId, sourceDocumentType, sourceDocumentId) -- a
 * retried call for the same source document returns the existing open item
 * rather than raising a duplicate error. `invoice` requires FIN:Edit;
 * `opening_balance` requires FIN:Approve (Prompt 196's own "approved
 * migration/opening balance" exception).
 */
export async function postFinanceArOpenItem(
  client: AccountsReceivableMutationRpcClient,
  input: PostFinanceArOpenItemInput,
): Promise<FinanceArOpenItem> {
  const parsedInput = PostFinanceArOpenItemInputSchema.parse(input);
  return callAndParseItem(client, "post_finance_ar_open_item", {
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_customer_account_id: parsedInput.customerAccountId,
    p_source_document_type: parsedInput.sourceDocumentType,
    p_source_document_id: parsedInput.sourceDocumentId,
    p_currency: parsedInput.currency,
    p_original_amount: parsedInput.originalAmount,
    p_invoice_date: parsedInput.invoiceDate,
    p_due_date: parsedInput.dueDate,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated. Requires a non-empty reason. Rejected if already held. */
export async function placeFinanceArHold(
  client: AccountsReceivableMutationRpcClient,
  input: PlaceFinanceArHoldInput,
): Promise<FinanceArOpenItem> {
  const parsedInput = PlaceFinanceArHoldInputSchema.parse(input);
  return callAndParseItem(client, "place_finance_ar_hold", {
    p_open_item_id: parsedInput.openItemId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated (governed release, distinct authority from placing a hold). Rejected if not currently held. */
export async function releaseFinanceArHold(
  client: AccountsReceivableMutationRpcClient,
  input: ReleaseFinanceArHoldInput,
): Promise<FinanceArOpenItem> {
  const parsedInput = ReleaseFinanceArHoldInputSchema.parse(input);
  return callAndParseItem(client, "release_finance_ar_hold", {
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

/**
 * FIN:Edit-gated, row-locked, idempotent on idempotencyKey. Rejected if the
 * amount exceeds the open item's own current open amount (never allows
 * over-allocation, even under concurrency).
 */
export async function applyFinanceArAllocation(
  client: AccountsReceivableMutationRpcClient,
  input: ApplyFinanceArAllocationInput,
): Promise<FinanceArOpenItem> {
  const parsedInput = ApplyFinanceArAllocationInputSchema.parse(input);
  return callAndParseItem(client, "apply_finance_ar_allocation", {
    p_open_item_id: parsedInput.openItemId,
    p_amount: parsedInput.amount,
    p_source_type: parsedInput.sourceType,
    p_source_id: parsedInput.sourceId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated (governed reversal, never a direct edit). Requires a non-empty reason. Rejected if the amount exceeds the item's own currently-allocated amount. */
export async function reverseFinanceArAllocation(
  client: AccountsReceivableMutationRpcClient,
  input: ReverseFinanceArAllocationInput,
): Promise<FinanceArOpenItem> {
  const parsedInput = ReverseFinanceArAllocationInputSchema.parse(input);
  return callAndParseItem(client, "reverse_finance_ar_allocation", {
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
