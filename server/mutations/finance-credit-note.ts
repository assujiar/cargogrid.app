/**
 * Finance Credit Note mutation primitives (CG-AUDIT-2026-09-02 B3). Thin,
 * typed wrapper around app.issue_finance_credit_note (supabase/migrations/
 * 20260919020000_b3_finance_credit_note.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  IssueFinanceCreditNoteInputSchema,
  parseFinanceCreditNote,
  type IssueFinanceCreditNoteInput,
  type FinanceCreditNote,
} from "../contracts/finance-credit-note/finance-credit-note.ts";

export type FinanceCreditNoteMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const FINANCE_CREDIT_NOTE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "finance_credit_note_idempotency_key_required",
  "finance_credit_note_reason_required",
  "finance_credit_note_invalid_amount",
  "finance_invoice_not_found",
  "finance_credit_note_invoice_not_issued",
  "finance_credit_note_ar_item_not_found",
  "finance_credit_note_exceeds_invoice",
] as const;
type KnownFinanceCreditNoteMutationErrorCode = (typeof FINANCE_CREDIT_NOTE_KNOWN_MUTATION_ERROR_CODES)[number];
export type FinanceCreditNoteMutationErrorCode = KnownFinanceCreditNoteMutationErrorCode | "mutation_failed" | "invalid_response";

export class FinanceCreditNoteMutationError extends Error {
  readonly code: FinanceCreditNoteMutationErrorCode;

  constructor(code: FinanceCreditNoteMutationErrorCode, message: string) {
    super(message);
    this.name = "FinanceCreditNoteMutationError";
    this.code = code;
  }
}

function classifyError(message: string): FinanceCreditNoteMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (FINANCE_CREDIT_NOTE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownFinanceCreditNoteMutationErrorCode) : "mutation_failed";
}

/** FIN:Edit-gated, idempotent on (tenantId, idempotencyKey), mandatory reason. Only an already-ISSUED invoice may be credited; cumulative credits on the same invoice are capped at its own original AR amount. */
export async function issueFinanceCreditNote(client: FinanceCreditNoteMutationRpcClient, input: IssueFinanceCreditNoteInput): Promise<FinanceCreditNote> {
  const parsedInput = IssueFinanceCreditNoteInputSchema.parse(input);
  const { data, error } = await client.rpc("issue_finance_credit_note", {
    p_tenant_id: parsedInput.tenantId,
    p_invoice_id: parsedInput.invoiceId,
    p_amount: parsedInput.amount,
    p_reason: parsedInput.reason,
    p_credit_date: parsedInput.creditDate,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FinanceCreditNoteMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FinanceCreditNoteMutationError("invalid_response", "issue_finance_credit_note returned no row");
  }
  return parseFinanceCreditNote(data as Record<string, unknown>);
}
