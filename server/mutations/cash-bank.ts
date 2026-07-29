/**
 * Cash and Bank Baseline mutation primitives (FIN-211, CG-S9-FIN-022).
 * Thin, typed wrappers around app.create_finance_bank_account /
 * app.import_finance_bank_statement / app.match_finance_bank_transaction /
 * app.unmatch_finance_bank_transaction
 * (supabase/migrations/20260729250000_create_finance_cash_bank.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateFinanceBankAccountInputSchema,
  ImportFinanceBankStatementInputSchema,
  MatchFinanceBankTransactionInputSchema,
  UnmatchFinanceBankTransactionInputSchema,
  parseFinanceBankAccount,
  parseFinanceBankStatementBatch,
  parseFinanceBankTransaction,
  type CreateFinanceBankAccountInput,
  type ImportFinanceBankStatementInput,
  type MatchFinanceBankTransactionInput,
  type UnmatchFinanceBankTransactionInput,
  type FinanceBankAccount,
  type FinanceBankStatementBatch,
  type FinanceBankTransaction,
} from "../contracts/cash-bank/cash-bank.ts";

export type CashBankMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CASH_BANK_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "finance_cash_unsupported_currency",
  "finance_cash_gl_account_not_found",
  "finance_cash_gl_account_not_postable",
  "finance_cash_source_reference_required",
  "finance_cash_bank_account_not_found",
  "finance_cash_empty_statement",
  "finance_cash_invalid_direction",
  "finance_cash_invalid_amount",
  "finance_cash_transaction_not_found",
  "finance_cash_invalid_match_source_type",
  "finance_cash_transaction_not_unmatched",
  "finance_cash_unmatch_reason_required",
  "finance_cash_transaction_not_matched",
  "stale_version",
] as const;
type KnownCashBankMutationErrorCode = (typeof CASH_BANK_KNOWN_MUTATION_ERROR_CODES)[number];
export type CashBankMutationErrorCode = KnownCashBankMutationErrorCode | "mutation_failed" | "invalid_response";

export class CashBankMutationError extends Error {
  readonly code: CashBankMutationErrorCode;

  constructor(code: CashBankMutationErrorCode, message: string) {
    super(message);
    this.name = "CashBankMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CashBankMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CASH_BANK_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownCashBankMutationErrorCode) : "mutation_failed";
}

/** FIN:Approve-gated. Validates the GL account is active/postable; stores only a masked (last 1-4 char) account number. */
export async function createFinanceBankAccount(client: CashBankMutationRpcClient, input: CreateFinanceBankAccountInput): Promise<FinanceBankAccount> {
  const parsedInput = CreateFinanceBankAccountInputSchema.parse(input);
  const { data, error } = await client.rpc("create_finance_bank_account", {
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_account_name: parsedInput.accountName,
    p_bank_name: parsedInput.bankName,
    p_account_number_last4: parsedInput.accountNumberLast4,
    p_currency: parsedInput.currency,
    p_gl_account_id: parsedInput.glAccountId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CashBankMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CashBankMutationError("invalid_response", "create_finance_bank_account returned no row");
  }
  return parseFinanceBankAccount(data as Record<string, unknown>);
}

/** FIN:Edit-gated, idempotent on (tenantId, bankAccountId, sourceReference). Every line is deduplicated by the database's own unique index. */
export async function importFinanceBankStatement(client: CashBankMutationRpcClient, input: ImportFinanceBankStatementInput): Promise<FinanceBankStatementBatch> {
  const parsedInput = ImportFinanceBankStatementInputSchema.parse(input);
  const { data, error } = await client.rpc("import_finance_bank_statement", {
    p_tenant_id: parsedInput.tenantId,
    p_bank_account_id: parsedInput.bankAccountId,
    p_source_reference: parsedInput.sourceReference,
    p_lines: parsedInput.lines,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CashBankMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CashBankMutationError("invalid_response", "import_finance_bank_statement returned no row");
  }
  return parseFinanceBankStatementBatch(data as Record<string, unknown>);
}

/** FIN:Edit-gated. unmatched -> matched. */
export async function matchFinanceBankTransaction(client: CashBankMutationRpcClient, input: MatchFinanceBankTransactionInput): Promise<FinanceBankTransaction> {
  const parsedInput = MatchFinanceBankTransactionInputSchema.parse(input);
  const { data, error } = await client.rpc("match_finance_bank_transaction", {
    p_transaction_id: parsedInput.transactionId,
    p_expected_version: parsedInput.expectedVersion,
    p_matched_source_type: parsedInput.matchedSourceType,
    p_matched_source_id: parsedInput.matchedSourceId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CashBankMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CashBankMutationError("invalid_response", "match_finance_bank_transaction returned no row");
  }
  return parseFinanceBankTransaction(data as Record<string, unknown>);
}

/** FIN:Approve-gated. Requires a non-empty reason. matched -> unmatched. */
export async function unmatchFinanceBankTransaction(client: CashBankMutationRpcClient, input: UnmatchFinanceBankTransactionInput): Promise<FinanceBankTransaction> {
  const parsedInput = UnmatchFinanceBankTransactionInputSchema.parse(input);
  const { data, error } = await client.rpc("unmatch_finance_bank_transaction", {
    p_transaction_id: parsedInput.transactionId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CashBankMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CashBankMutationError("invalid_response", "unmatch_finance_bank_transaction returned no row");
  }
  return parseFinanceBankTransaction(data as Record<string, unknown>);
}
