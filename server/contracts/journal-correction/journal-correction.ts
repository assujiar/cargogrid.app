/**
 * Reversal and Adjustment contract (FIN-206, CG-S9-FIN-017). Mirrors
 * supabase/migrations/20260729200000_create_finance_reversal_adjustment.sql's
 * app.finance_journal_corrections shape and its RPCs.
 */

import { z } from "zod";

export const FINANCE_CORRECTION_TYPES = ["reversal", "adjustment"] as const;
export const FinanceCorrectionTypeSchema = z.enum(FINANCE_CORRECTION_TYPES);
export type FinanceCorrectionType = z.infer<typeof FinanceCorrectionTypeSchema>;

export const FINANCE_CORRECTION_STATUSES = ["draft", "submitted", "approved", "posted", "discarded"] as const;
export const FinanceCorrectionStatusSchema = z.enum(FINANCE_CORRECTION_STATUSES);
export type FinanceCorrectionStatus = z.infer<typeof FinanceCorrectionStatusSchema>;

export const FinanceJournalCorrectionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  originalJournalId: z.string().uuid(),
  correctionType: FinanceCorrectionTypeSchema,
  correctionDate: z.string(),
  reason: z.string(),
  evidenceRef: z.string().nullable(),
  adjustmentLines: z.array(z.record(z.string(), z.unknown())).nullable(),
  status: FinanceCorrectionStatusSchema,
  idempotencyKey: z.string(),
  correctionJournalId: z.string().uuid().nullable(),
  submittedBy: z.string().nullable(),
  submittedAt: z.string().nullable(),
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  postedBy: z.string().nullable(),
  postedAt: z.string().nullable(),
  discardReason: z.string().nullable(),
  discardedBy: z.string().nullable(),
  discardedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceJournalCorrection = z.infer<typeof FinanceJournalCorrectionSchema>;

export const FinanceAdjustmentLineSchema = z.object({
  accountId: z.string().uuid(),
  direction: z.enum(["debit", "credit"]),
  amount: z.number().positive(),
  dimension: z.record(z.string(), z.unknown()).nullable().default(null),
});
export type FinanceAdjustmentLine = z.infer<typeof FinanceAdjustmentLineSchema>;

export const PrepareFinanceJournalReversalInputSchema = z.object({
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable().default(null),
  originalJournalId: z.string().uuid(),
  correctionDate: z.string(),
  reason: z.string().min(1),
  evidenceRef: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PrepareFinanceJournalReversalInput = z.input<typeof PrepareFinanceJournalReversalInputSchema>;

export const PrepareFinanceJournalAdjustmentInputSchema = PrepareFinanceJournalReversalInputSchema.extend({
  adjustmentLines: z.array(FinanceAdjustmentLineSchema).min(2),
});
export type PrepareFinanceJournalAdjustmentInput = z.input<typeof PrepareFinanceJournalAdjustmentInputSchema>;

export const FinanceCorrectionLifecycleInputSchema = z.object({
  correctionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type FinanceCorrectionLifecycleInput = z.input<typeof FinanceCorrectionLifecycleInputSchema>;

export const DiscardFinanceCorrectionDraftInputSchema = FinanceCorrectionLifecycleInputSchema.extend({
  reason: z.string().nullable().default(null),
});
export type DiscardFinanceCorrectionDraftInput = z.input<typeof DiscardFinanceCorrectionDraftInputSchema>;

/** Maps a raw app.finance_journal_corrections row (snake_case) to this contract's camelCase shape. */
export function parseFinanceJournalCorrection(row: Record<string, unknown>): FinanceJournalCorrection {
  return FinanceJournalCorrectionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    originalJournalId: row.original_journal_id,
    correctionType: row.correction_type,
    correctionDate: row.correction_date,
    reason: row.reason,
    evidenceRef: row.evidence_ref,
    adjustmentLines: row.adjustment_lines,
    status: row.status,
    idempotencyKey: row.idempotency_key,
    correctionJournalId: row.correction_journal_id,
    submittedBy: row.submitted_by,
    submittedAt: row.submitted_at,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    postedBy: row.posted_by,
    postedAt: row.posted_at,
    discardReason: row.discard_reason,
    discardedBy: row.discarded_by,
    discardedAt: row.discarded_at,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
