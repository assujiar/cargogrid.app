/**
 * Finance Account Ledger contract (CG-AUDIT-2026-09-02 B2, GL detail report
 * half). Mirrors supabase/migrations/20260922020000_b2_finance_account_
 * ledger.sql's app.get_finance_account_ledger row shape -- one row per
 * posted journal line plus one synthetic "Opening balance" row per
 * currency (journalId/journalNumber/sourceType/direction/amount all null
 * on that row; entryDate/runningBalance/currency are always present).
 */

import { z } from "zod";

export const FinanceAccountLedgerEntrySchema = z.object({
  entryDate: z.string(),
  journalId: z.string().uuid().nullable(),
  journalNumber: z.string().nullable(),
  sourceType: z.string().nullable(),
  description: z.string().nullable(),
  direction: z.enum(["debit", "credit"]).nullable(),
  amount: z.coerce.number().nullable(),
  runningBalance: z.coerce.number(),
  currency: z.string(),
});
export type FinanceAccountLedgerEntry = z.infer<typeof FinanceAccountLedgerEntrySchema>;

export function parseFinanceAccountLedgerEntry(row: Record<string, unknown>): FinanceAccountLedgerEntry {
  return FinanceAccountLedgerEntrySchema.parse({
    entryDate: row.entry_date,
    journalId: row.journal_id ?? null,
    journalNumber: row.journal_number ?? null,
    sourceType: row.source_type ?? null,
    description: row.description ?? null,
    direction: row.direction ?? null,
    amount: row.amount ?? null,
    runningBalance: row.running_balance,
    currency: row.currency,
  });
}

export const GetFinanceAccountLedgerInputSchema = z.object({
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  accountId: z.string().uuid(),
  dateFrom: z.string().min(1),
  dateTo: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
});
export type GetFinanceAccountLedgerInput = z.input<typeof GetFinanceAccountLedgerInputSchema>;
