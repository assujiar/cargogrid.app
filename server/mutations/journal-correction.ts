/**
 * Reversal and Adjustment mutation primitives (FIN-206, CG-S9-FIN-017).
 * Thin, typed wrappers around app.prepare_finance_journal_reversal /
 * app.prepare_finance_journal_adjustment /
 * app.submit_finance_correction_for_approval /
 * app.discard_finance_correction_draft / app.approve_finance_correction /
 * app.post_finance_correction
 * (supabase/migrations/20260729200000_create_finance_reversal_adjustment.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  PrepareFinanceJournalReversalInputSchema,
  PrepareFinanceJournalAdjustmentInputSchema,
  FinanceCorrectionLifecycleInputSchema,
  DiscardFinanceCorrectionDraftInputSchema,
  parseFinanceJournalCorrection,
  type PrepareFinanceJournalReversalInput,
  type PrepareFinanceJournalAdjustmentInput,
  type FinanceCorrectionLifecycleInput,
  type DiscardFinanceCorrectionDraftInput,
  type FinanceJournalCorrection,
} from "../contracts/journal-correction/journal-correction.ts";

export type JournalCorrectionMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const JOURNAL_CORRECTION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "idempotency_key_required",
  "finance_correction_reason_required",
  "finance_journal_not_found",
  "finance_correction_original_not_posted",
  "finance_correction_duplicate_reversal",
  "finance_journal_insufficient_lines",
  "finance_journal_invalid_direction",
  "finance_journal_invalid_line_amount",
  "finance_journal_unbalanced",
  "finance_journal_account_not_found",
  "finance_journal_not_postable_account",
  "finance_correction_not_found",
  "finance_correction_not_draft",
  "finance_correction_not_submitted",
  "finance_correction_not_approved",
  "finance_correction_not_cancellable",
  "stale_version",
] as const;
type KnownJournalCorrectionMutationErrorCode = (typeof JOURNAL_CORRECTION_KNOWN_MUTATION_ERROR_CODES)[number];
export type JournalCorrectionMutationErrorCode = KnownJournalCorrectionMutationErrorCode | "mutation_failed" | "invalid_response";

export class JournalCorrectionMutationError extends Error {
  readonly code: JournalCorrectionMutationErrorCode;

  constructor(code: JournalCorrectionMutationErrorCode, message: string) {
    super(message);
    this.name = "JournalCorrectionMutationError";
    this.code = code;
  }
}

function classifyError(message: string): JournalCorrectionMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (JOURNAL_CORRECTION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownJournalCorrectionMutationErrorCode) : "mutation_failed";
}

async function callAndParseCorrection(
  client: JournalCorrectionMutationRpcClient,
  fn:
    | "prepare_finance_journal_reversal"
    | "prepare_finance_journal_adjustment"
    | "submit_finance_correction_for_approval"
    | "discard_finance_correction_draft"
    | "approve_finance_correction"
    | "post_finance_correction",
  args: Record<string, unknown>,
): Promise<FinanceJournalCorrection> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new JournalCorrectionMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new JournalCorrectionMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseFinanceJournalCorrection(data as Record<string, unknown>);
}

/** FIN:Edit-gated, idempotent on (tenantId, idempotencyKey). Original journal must be posted; at most one active reversal per original. */
export async function prepareFinanceJournalReversal(client: JournalCorrectionMutationRpcClient, input: PrepareFinanceJournalReversalInput): Promise<FinanceJournalCorrection> {
  const parsedInput = PrepareFinanceJournalReversalInputSchema.parse(input);
  return callAndParseCorrection(client, "prepare_finance_journal_reversal", {
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_original_journal_id: parsedInput.originalJournalId,
    p_correction_date: parsedInput.correctionDate,
    p_reason: parsedInput.reason,
    p_evidence_ref: parsedInput.evidenceRef,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated, idempotent on (tenantId, idempotencyKey). adjustmentLines must already balance (at least two lines, exact debit=credit). */
export async function prepareFinanceJournalAdjustment(client: JournalCorrectionMutationRpcClient, input: PrepareFinanceJournalAdjustmentInput): Promise<FinanceJournalCorrection> {
  const parsedInput = PrepareFinanceJournalAdjustmentInputSchema.parse(input);
  return callAndParseCorrection(client, "prepare_finance_journal_adjustment", {
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_original_journal_id: parsedInput.originalJournalId,
    p_correction_date: parsedInput.correctionDate,
    p_reason: parsedInput.reason,
    p_evidence_ref: parsedInput.evidenceRef,
    p_adjustment_lines: parsedInput.adjustmentLines,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated. draft -> submitted. */
export async function submitFinanceCorrectionForApproval(client: JournalCorrectionMutationRpcClient, input: FinanceCorrectionLifecycleInput): Promise<FinanceJournalCorrection> {
  const parsedInput = FinanceCorrectionLifecycleInputSchema.parse(input);
  return callAndParseCorrection(client, "submit_finance_correction_for_approval", {
    p_correction_id: parsedInput.correctionId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Edit-gated. draft/submitted -> discarded. */
export async function discardFinanceCorrectionDraft(client: JournalCorrectionMutationRpcClient, input: DiscardFinanceCorrectionDraftInput): Promise<FinanceJournalCorrection> {
  const parsedInput = DiscardFinanceCorrectionDraftInputSchema.parse(input);
  return callAndParseCorrection(client, "discard_finance_correction_draft", {
    p_correction_id: parsedInput.correctionId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated. submitted -> approved. */
export async function approveFinanceCorrection(client: JournalCorrectionMutationRpcClient, input: FinanceCorrectionLifecycleInput): Promise<FinanceJournalCorrection> {
  const parsedInput = FinanceCorrectionLifecycleInputSchema.parse(input);
  return callAndParseCorrection(client, "approve_finance_correction", {
    p_correction_id: parsedInput.correctionId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** FIN:Approve-gated, idempotent. approved -> posted; derives reversal lines from the original journal or uses the already-validated adjustment lines, then posts one new linked journal. A retried call against an already-posted correction returns it unchanged. */
export async function postFinanceCorrection(client: JournalCorrectionMutationRpcClient, input: FinanceCorrectionLifecycleInput): Promise<FinanceJournalCorrection> {
  const parsedInput = FinanceCorrectionLifecycleInputSchema.parse(input);
  return callAndParseCorrection(client, "post_finance_correction", {
    p_correction_id: parsedInput.correctionId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}
