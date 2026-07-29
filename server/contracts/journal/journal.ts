/**
 * Double-Entry Journal contract (FIN-203, CG-S9-FIN-014). Mirrors
 * supabase/migrations/20260729170000_create_finance_journal.sql's
 * app.finance_journals / app.finance_journal_lines shapes and their RPCs.
 */

import { z } from "zod";

export const FINANCE_JOURNAL_SOURCE_TYPES = ["manual", "subledger"] as const;
export const FinanceJournalSourceTypeSchema = z.enum(FINANCE_JOURNAL_SOURCE_TYPES);
export type FinanceJournalSourceType = z.infer<typeof FinanceJournalSourceTypeSchema>;

export const FINANCE_JOURNAL_STATUSES = ["draft", "submitted", "approved", "posted", "void"] as const;
export const FinanceJournalStatusSchema = z.enum(FINANCE_JOURNAL_STATUSES);
export type FinanceJournalStatus = z.infer<typeof FinanceJournalStatusSchema>;

export const FinanceJournalSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  journalNumber: z.string().nullable(),
  sourceType: FinanceJournalSourceTypeSchema,
  sourceId: z.string().uuid().nullable(),
  idempotencyKey: z.string(),
  currency: z.string(),
  totalAmount: z.number(),
  journalDate: z.string(),
  status: FinanceJournalStatusSchema,
  postingPeriodId: z.string().uuid().nullable(),
  submittedBy: z.string().nullable(),
  submittedAt: z.string().nullable(),
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  postedBy: z.string().nullable(),
  postedAt: z.string().nullable(),
  voidReason: z.string().nullable(),
  voidedBy: z.string().nullable(),
  voidedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceJournal = z.infer<typeof FinanceJournalSchema>;

export const FinanceJournalLineDirectionSchema = z.enum(["debit", "credit"]);
export type FinanceJournalLineDirection = z.infer<typeof FinanceJournalLineDirectionSchema>;

export const FinanceJournalLineSchema = z.object({
  id: z.string().uuid(),
  journalId: z.string().uuid(),
  tenantId: z.string().uuid(),
  lineNumber: z.number().int(),
  accountId: z.string().uuid(),
  dimension: z.record(z.string(), z.unknown()).nullable(),
  direction: FinanceJournalLineDirectionSchema,
  amount: z.number(),
  description: z.string().nullable(),
  createdAt: z.string(),
});
export type FinanceJournalLine = z.infer<typeof FinanceJournalLineSchema>;

export const FinanceJournalManualLineSchema = z.object({
  accountId: z.string().uuid(),
  direction: FinanceJournalLineDirectionSchema,
  amount: z.number().positive(),
  description: z.string().nullable().default(null),
  dimension: z.record(z.string(), z.unknown()).nullable().default(null),
});
export type FinanceJournalManualLine = z.infer<typeof FinanceJournalManualLineSchema>;

export const CreateFinanceJournalDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable().default(null),
  journalDate: z.string(),
  currency: z.string().regex(/^[A-Z]{3}$/),
  lines: z.array(FinanceJournalManualLineSchema).min(2),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateFinanceJournalDraftInput = z.input<typeof CreateFinanceJournalDraftInputSchema>;

export const FinanceJournalLifecycleInputSchema = z.object({
  journalId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type FinanceJournalLifecycleInput = z.input<typeof FinanceJournalLifecycleInputSchema>;

export const DiscardFinanceJournalDraftInputSchema = FinanceJournalLifecycleInputSchema.extend({
  reason: z.string().nullable().default(null),
});
export type DiscardFinanceJournalDraftInput = z.input<typeof DiscardFinanceJournalDraftInputSchema>;

/** Maps a raw app.finance_journals row (snake_case) to this contract's camelCase shape. */
export function parseFinanceJournal(row: Record<string, unknown>): FinanceJournal {
  return FinanceJournalSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    journalNumber: row.journal_number,
    sourceType: row.source_type,
    sourceId: row.source_id,
    idempotencyKey: row.idempotency_key,
    currency: row.currency,
    totalAmount: typeof row.total_amount === "string" ? Number(row.total_amount) : row.total_amount,
    journalDate: row.journal_date,
    status: row.status,
    postingPeriodId: row.posting_period_id,
    submittedBy: row.submitted_by,
    submittedAt: row.submitted_at,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    postedBy: row.posted_by,
    postedAt: row.posted_at,
    voidReason: row.void_reason,
    voidedBy: row.voided_by,
    voidedAt: row.voided_at,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.finance_journal_lines row (snake_case) to this contract's camelCase shape. */
export function parseFinanceJournalLine(row: Record<string, unknown>): FinanceJournalLine {
  return FinanceJournalLineSchema.parse({
    id: row.id,
    journalId: row.journal_id,
    tenantId: row.tenant_id,
    lineNumber: row.line_number,
    accountId: row.account_id,
    dimension: row.dimension,
    direction: row.direction,
    amount: typeof row.amount === "string" ? Number(row.amount) : row.amount,
    description: row.description,
    createdAt: row.created_at,
  });
}
