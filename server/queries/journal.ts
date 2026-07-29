/**
 * Double-Entry Journal read queries (FIN-203, CG-S9-FIN-014). Thin, typed
 * wrappers around app.list_finance_journals / app.get_finance_journal_lines
 * (supabase/migrations/20260729170000_create_finance_journal.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseFinanceJournal, parseFinanceJournalLine, type FinanceJournal, type FinanceJournalLine } from "../contracts/journal/journal.ts";

export type JournalQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class JournalQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "JournalQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered list, most-recent first. */
export async function listFinanceJournals(
  client: JournalQueryRpcClient,
  input: { tenantId: string; companyId: string | null; sourceType: string | null; status: string | null; actorAuthUserId: string },
): Promise<FinanceJournal[]> {
  const { data, error } = await client.rpc("list_finance_journals", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_source_type: input.sourceType,
    p_status: input.status,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new JournalQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceJournal(row as Record<string, unknown>));
}

/** FIN:View-gated. Every debit/credit line for one journal, ordered by line_number. */
export async function getFinanceJournalLines(
  client: JournalQueryRpcClient,
  input: { journalId: string; actorAuthUserId: string },
): Promise<FinanceJournalLine[]> {
  const { data, error } = await client.rpc("get_finance_journal_lines", {
    p_journal_id: input.journalId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new JournalQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceJournalLine(row as Record<string, unknown>));
}
