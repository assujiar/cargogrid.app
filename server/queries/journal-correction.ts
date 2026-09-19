/**
 * Reversal and Adjustment read queries (FIN-206, CG-S9-FIN-017). Thin,
 * typed wrappers around app.list_finance_journal_corrections /
 * app.get_finance_correction_chain
 * (supabase/migrations/20260729200000_create_finance_reversal_adjustment.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseFinanceJournalCorrection, type FinanceJournalCorrection } from "../contracts/journal-correction/journal-correction.ts";
import { BOUNDED_LIST_LIMIT } from "./bounded-list.ts";

export type JournalCorrectionQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class JournalCorrectionQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "JournalCorrectionQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered list, most-recent first. */
/** CG-AUDIT-2026-09-02 F3: `afterId`/`limit` optional and additive -- see server/queries/accounts-receivable.ts#listFinanceArOpenItems's own header comment for the full rationale. */
export async function listFinanceJournalCorrections(
  client: JournalCorrectionQueryRpcClient,
  input: { tenantId: string; companyId: string | null; correctionType: string | null; status: string | null; actorAuthUserId: string; limit?: number; afterId?: string | null },
): Promise<FinanceJournalCorrection[]> {
  const limit = input.limit ?? BOUNDED_LIST_LIMIT;
  const { data, error } = await client.rpc("list_finance_journal_corrections", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_correction_type: input.correctionType,
    p_status: input.status,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_limit: limit,
    p_after_id: input.afterId ?? null,
  });
  if (error) {
    throw new JournalCorrectionQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.slice(0, limit).map((row) => parseFinanceJournalCorrection(row as Record<string, unknown>));
}

/** FIN:View-gated. The correction request, its original journal, and its posted correction journal (if any) in one call. */
export async function getFinanceCorrectionChain(
  client: JournalCorrectionQueryRpcClient,
  input: { correctionId: string; actorAuthUserId: string },
): Promise<{ correction: Record<string, unknown>; originalJournal: Record<string, unknown>; correctionJournal: Record<string, unknown> | null }> {
  const { data, error } = await client.rpc("get_finance_correction_chain", {
    p_correction_id: input.correctionId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new JournalCorrectionQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new JournalCorrectionQueryError("get_finance_correction_chain returned no result");
  }
  const shape = data as Record<string, unknown>;
  return {
    correction: shape.correction as Record<string, unknown>,
    originalJournal: shape.originalJournal as Record<string, unknown>,
    correctionJournal: (shape.correctionJournal as Record<string, unknown> | null) ?? null,
  };
}
