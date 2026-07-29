/**
 * Subledger contract (FIN-202, CG-S9-FIN-013). Mirrors
 * supabase/migrations/20260729160000_create_finance_subledger.sql's
 * app.finance_subledger_batches / app.finance_subledger_lines shapes and their RPCs.
 */

import { z } from "zod";

export const FINANCE_SUBLEDGER_SOURCE_TYPES = ["invoice", "receipt_allocation", "vendor_bill", "settlement"] as const;
export const FinanceSubledgerSourceTypeSchema = z.enum(FINANCE_SUBLEDGER_SOURCE_TYPES);
export type FinanceSubledgerSourceType = z.infer<typeof FinanceSubledgerSourceTypeSchema>;

export const FINANCE_SUBLEDGER_BATCH_STATUSES = ["posted", "reversed"] as const;
export const FinanceSubledgerBatchStatusSchema = z.enum(FINANCE_SUBLEDGER_BATCH_STATUSES);
export type FinanceSubledgerBatchStatus = z.infer<typeof FinanceSubledgerBatchStatusSchema>;

export const FinanceSubledgerBatchSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  sourceType: FinanceSubledgerSourceTypeSchema,
  sourceId: z.string().uuid(),
  currency: z.string(),
  totalAmount: z.number(),
  status: FinanceSubledgerBatchStatusSchema,
  postingPeriodId: z.string().uuid().nullable(),
  glJournalId: z.string().uuid().nullable(),
  postedBy: z.string().nullable(),
  postedAt: z.string(),
  createdAt: z.string(),
});
export type FinanceSubledgerBatch = z.infer<typeof FinanceSubledgerBatchSchema>;

export const FinanceSubledgerLineDirectionSchema = z.enum(["debit", "credit"]);
export type FinanceSubledgerLineDirection = z.infer<typeof FinanceSubledgerLineDirectionSchema>;

export const FinanceSubledgerLineSchema = z.object({
  id: z.string().uuid(),
  batchId: z.string().uuid(),
  tenantId: z.string().uuid(),
  lineNumber: z.number().int(),
  accountId: z.string().uuid(),
  postingMapKey: z.string().nullable(),
  direction: FinanceSubledgerLineDirectionSchema,
  amount: z.number(),
  openItemType: z.enum(["ar_open_item", "ap_open_item"]).nullable(),
  openItemId: z.string().uuid().nullable(),
  createdAt: z.string(),
});
export type FinanceSubledgerLine = z.infer<typeof FinanceSubledgerLineSchema>;

export const FinanceSubledgerReconciliationSummarySchema = z.object({
  arControlAccountCode: z.string(),
  arControlSubledgerBalance: z.number(),
  arOpenItemTotal: z.number(),
  arReconciled: z.boolean(),
  apControlAccountCode: z.string(),
  apControlSubledgerBalance: z.number(),
  apOpenItemTotal: z.number(),
  apReconciled: z.boolean(),
});
export type FinanceSubledgerReconciliationSummary = z.infer<typeof FinanceSubledgerReconciliationSummarySchema>;

/** Maps a raw app.finance_subledger_batches row (snake_case) to this contract's camelCase shape. */
export function parseFinanceSubledgerBatch(row: Record<string, unknown>): FinanceSubledgerBatch {
  return FinanceSubledgerBatchSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    sourceType: row.source_type,
    sourceId: row.source_id,
    currency: row.currency,
    totalAmount: typeof row.total_amount === "string" ? Number(row.total_amount) : row.total_amount,
    status: row.status,
    postingPeriodId: row.posting_period_id,
    glJournalId: row.gl_journal_id,
    postedBy: row.posted_by,
    postedAt: row.posted_at,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.finance_subledger_lines row (snake_case) to this contract's camelCase shape. */
export function parseFinanceSubledgerLine(row: Record<string, unknown>): FinanceSubledgerLine {
  return FinanceSubledgerLineSchema.parse({
    id: row.id,
    batchId: row.batch_id,
    tenantId: row.tenant_id,
    lineNumber: row.line_number,
    accountId: row.account_id,
    postingMapKey: row.posting_map_key,
    direction: row.direction,
    amount: typeof row.amount === "string" ? Number(row.amount) : row.amount,
    openItemType: row.open_item_type,
    openItemId: row.open_item_id,
    createdAt: row.created_at,
  });
}

/** Maps the raw jsonb returned by app.get_finance_subledger_reconciliation_summary to this contract's camelCase shape. */
export function parseFinanceSubledgerReconciliationSummary(row: Record<string, unknown>): FinanceSubledgerReconciliationSummary {
  return FinanceSubledgerReconciliationSummarySchema.parse({
    arControlAccountCode: row.arControlAccountCode,
    arControlSubledgerBalance: typeof row.arControlSubledgerBalance === "string" ? Number(row.arControlSubledgerBalance) : row.arControlSubledgerBalance,
    arOpenItemTotal: typeof row.arOpenItemTotal === "string" ? Number(row.arOpenItemTotal) : row.arOpenItemTotal,
    arReconciled: row.arReconciled,
    apControlAccountCode: row.apControlAccountCode,
    apControlSubledgerBalance: typeof row.apControlSubledgerBalance === "string" ? Number(row.apControlSubledgerBalance) : row.apControlSubledgerBalance,
    apOpenItemTotal: typeof row.apOpenItemTotal === "string" ? Number(row.apOpenItemTotal) : row.apOpenItemTotal,
    apReconciled: row.apReconciled,
  });
}
