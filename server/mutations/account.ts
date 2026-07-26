/**
 * Customer/Account mutation primitives (COM-155, CG-S7-COM-014). Thin, typed wrapper
 * around app.convert_quotation_to_account
 * (supabase/migrations/20260724290000_create_commercial_customer_account_conversion.sql)
 * -- the one atomic, idempotent create-or-link operation.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { ConvertQuotationToAccountInputSchema, parseAccount, type ConvertQuotationToAccountInput, type Account } from "../contracts/account/account.ts";

export type AccountMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ACCOUNT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "quotation_not_found",
  "quotation_not_accepted",
  "missing_legal_name",
  "target_account_not_found",
] as const;
type KnownAccountMutationErrorCode = (typeof ACCOUNT_KNOWN_MUTATION_ERROR_CODES)[number];
export type AccountMutationErrorCode = KnownAccountMutationErrorCode | "mutation_failed" | "invalid_response";

export class AccountMutationError extends Error {
  readonly code: AccountMutationErrorCode;

  constructor(code: AccountMutationErrorCode, message: string) {
    super(message);
    this.name = "AccountMutationError";
    this.code = code;
  }
}

function classifyError(message: string): AccountMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ACCOUNT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownAccountMutationErrorCode) : "mutation_failed";
}

/** Idempotent on quotationId (unique(quotation_id) on app.account_conversions) -- a repeated call for an already-converted quotation returns the same account, never a duplicate. targetAccountId set = link to an existing account (after duplicate review); null = create a brand-new one, optionally under parentAccountId. */
export async function convertQuotationToAccount(client: AccountMutationRpcClient, input: ConvertQuotationToAccountInput): Promise<Account> {
  const parsedInput = ConvertQuotationToAccountInputSchema.parse(input);
  const { data, error } = await client.rpc("convert_quotation_to_account", {
    p_quotation_id: parsedInput.quotationId,
    p_target_account_id: parsedInput.targetAccountId,
    p_parent_account_id: parsedInput.parentAccountId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AccountMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AccountMutationError("invalid_response", "convert_quotation_to_account returned no row");
  }
  return parseAccount(data as Record<string, unknown>);
}
