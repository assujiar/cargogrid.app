/**
 * Double-Entry Journal mutation primitives (FIN-203, CG-S9-FIN-014). Thin,
 * typed wrappers around app.create_finance_journal_draft /
 * app.submit_finance_journal_for_approval / app.discard_finance_journal_draft /
 * app.approve_finance_journal / app.post_finance_journal
 * (supabase/migrations/20260729170000_create_finance_journal.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateFinanceJournalDraftInputSchema,
  FinanceJournalLifecycleInputSchema,
  DiscardFinanceJournalDraftInputSchema,
  parseFinanceJournal,
  type CreateFinanceJournalDraftInput,
  type FinanceJournalLifecycleInput,
  type DiscardFinanceJournalDraftInput,
  type FinanceJournal,
} from "../contracts/journal/journal.ts";

export type JournalMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const JOURNAL_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "idempotency_key_required",
  "finance_journal_unsupported_currency",
  "finance_journal_insufficient_lines",
  "finance_journal_invalid_direction",
  "finance_journal_invalid_line_amount",
  "finance_journal_unbalanced",
  "finance_journal_account_not_found",
  "finance_journal_inactive_account",
  "finance_journal_not_postable_account",
  "finance_journal_not_found",
  "finance_journal_not_draft",
  "finance_journal_not_submitted",
  "finance_journal_not_approved",
  "finance_journal_not_cancellable",
  "finance_journal_period_not_found",
  "finance_journal_period_not_open",
  "finance_period_locked",
  "finance_idempotency_fingerprint_conflict",
  "finance_idempotency_fingerprint_required",
  "stale_version",
] as const;
type KnownJournalMutationErrorCode = (typeof JOURNAL_KNOWN_MUTATION_ERROR_CODES)[number];
export type JournalMutationErrorCode = KnownJournalMutationErrorCode | "mutation_failed" | "invalid_response";

export class JournalMutationError extends Error {
  readonly code: JournalMutationErrorCode;

  constructor(code: JournalMutationErrorCode, message: string) {
    super(message);
    this.name = "JournalMutationError";
    this.code = code;
  }
}

function classifyError(message: string): JournalMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (JOURNAL_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownJournalMutationErrorCode) : "mutation_failed";
}

async function callAndParseJournal(
  client: JournalMutationRpcClient,
  fn:
    | "create_finance_journal_draft"
    | "submit_finance_journal_for_approval"
    | "discard_finance_journal_draft"
    | "approve_finance_journal"
    | "post_finance_journal",
  args: Record<string, unknown>,
): Promise<FinanceJournal> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new JournalMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new JournalMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseFinanceJournal(data as Record<string, unknown>);
}

/** FIN:Edit-gated, idempotent on (tenantId, idempotencyKey). Requires at least two lines, exact debit=credit balance, and every referenced account active/postable/same-tenant. */
export async function createFinanceJournalDraft(client: JournalMutationRpcClient, input: CreateFinanceJournalDraftInput): Promise<FinanceJournal> {
  const parsedInput = CreateFinanceJournalDraftInputSchema.parse(input);
  return callAndParseJournal(client, "create_finance_journal_draft", {
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_journal_date: parsedInput.journalDate,
    p_currency: parsedInput.currency,
    p_lines: parsedInput.lines.map((line) => ({ accountId: line.accountId, direction: line.direction, amount: line.amount, description: line.description, dimension: line.dimension })),
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated. draft -> submitted. */
export async function submitFinanceJournalForApproval(client: JournalMutationRpcClient, input: FinanceJournalLifecycleInput): Promise<FinanceJournal> {
  const parsedInput = FinanceJournalLifecycleInputSchema.parse(input);
  return callAndParseJournal(client, "submit_finance_journal_for_approval", {
    p_journal_id: parsedInput.journalId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated. draft/submitted -> void. Rejected once approved -- a normal role cannot edit a posted journal; correction is only via a governed reversal (FIN-206). */
export async function discardFinanceJournalDraft(client: JournalMutationRpcClient, input: DiscardFinanceJournalDraftInput): Promise<FinanceJournal> {
  const parsedInput = DiscardFinanceJournalDraftInputSchema.parse(input);
  return callAndParseJournal(client, "discard_finance_journal_draft", {
    p_journal_id: parsedInput.journalId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated. submitted -> approved. */
export async function approveFinanceJournal(client: JournalMutationRpcClient, input: FinanceJournalLifecycleInput): Promise<FinanceJournal> {
  const parsedInput = FinanceJournalLifecycleInputSchema.parse(input);
  return callAndParseJournal(client, "approve_finance_journal", {
    p_journal_id: parsedInput.journalId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated, period-aware, idempotent. approved -> posted; re-validates the stored lines' own balance, generates a real journal_number. A retried call against an already-posted journal returns it unchanged. */
export async function postFinanceJournal(client: JournalMutationRpcClient, input: FinanceJournalLifecycleInput): Promise<FinanceJournal> {
  const parsedInput = FinanceJournalLifecycleInputSchema.parse(input);
  return callAndParseJournal(client, "post_finance_journal", {
    p_journal_id: parsedInput.journalId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}
