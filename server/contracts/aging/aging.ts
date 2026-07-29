/**
 * AR and AP Aging contract (FIN-210, CG-S9-FIN-021). Mirrors
 * supabase/migrations/20260729240000_create_finance_aging.sql's
 * app.finance_aging_bucket_configs shape and its report/summary/config RPCs.
 */

import { z } from "zod";

export const FINANCE_AGING_ENTITY_TYPES = ["ar", "ap"] as const;
export const FinanceAgingEntityTypeSchema = z.enum(FINANCE_AGING_ENTITY_TYPES);
export type FinanceAgingEntityType = z.infer<typeof FinanceAgingEntityTypeSchema>;

export const FinanceAgingBucketSchema = z.object({
  label: z.string().min(1),
  minDays: z.number().int(),
  maxDays: z.number().int().nullable(),
});
export type FinanceAgingBucket = z.infer<typeof FinanceAgingBucketSchema>;

export const FinanceAgingBucketConfigSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  entityType: FinanceAgingEntityTypeSchema,
  version: z.number().int(),
  buckets: z.array(FinanceAgingBucketSchema),
  isActive: z.boolean(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type FinanceAgingBucketConfig = z.infer<typeof FinanceAgingBucketConfigSchema>;

export const FinanceAgingReportRowSchema = z.object({
  openItemId: z.string().uuid(),
  partyId: z.string().uuid(),
  currency: z.string(),
  originalAmount: z.number(),
  openAmount: z.number(),
  documentDate: z.string(),
  dueDate: z.string(),
  daysOverdue: z.number().int(),
  bucketLabel: z.string(),
  isHeld: z.boolean(),
  sourceDocumentType: z.string(),
  sourceDocumentId: z.string().uuid(),
});
export type FinanceAgingReportRow = z.infer<typeof FinanceAgingReportRowSchema>;

export const FinanceAgingSummaryRowSchema = z.object({
  bucketLabel: z.string(),
  currency: z.string(),
  openAmount: z.number(),
  itemCount: z.number().int(),
});
export type FinanceAgingSummaryRow = z.infer<typeof FinanceAgingSummaryRowSchema>;

export const SetFinanceAgingBucketConfigInputSchema = z.object({
  tenantId: z.string().uuid(),
  entityType: FinanceAgingEntityTypeSchema,
  buckets: z.array(FinanceAgingBucketSchema).min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetFinanceAgingBucketConfigInput = z.input<typeof SetFinanceAgingBucketConfigInputSchema>;

/** Maps a raw app.finance_aging_bucket_configs row (snake_case) to this contract's camelCase shape. */
export function parseFinanceAgingBucketConfig(row: Record<string, unknown>): FinanceAgingBucketConfig {
  return FinanceAgingBucketConfigSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    entityType: row.entity_type,
    version: row.version,
    buckets: row.buckets,
    isActive: row.is_active,
    createdBy: row.created_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.get_finance_aging_report row (snake_case) to this contract's camelCase shape. */
export function parseFinanceAgingReportRow(row: Record<string, unknown>): FinanceAgingReportRow {
  const numeric = (value: unknown) => (typeof value === "string" ? Number(value) : value);
  return FinanceAgingReportRowSchema.parse({
    openItemId: row.open_item_id,
    partyId: row.party_id,
    currency: row.currency,
    originalAmount: numeric(row.original_amount),
    openAmount: numeric(row.open_amount),
    documentDate: row.document_date,
    dueDate: row.due_date,
    daysOverdue: row.days_overdue,
    bucketLabel: row.bucket_label,
    isHeld: row.is_held,
    sourceDocumentType: row.source_document_type,
    sourceDocumentId: row.source_document_id,
  });
}

/** Maps a raw app.get_finance_aging_summary row (snake_case) to this contract's camelCase shape. */
export function parseFinanceAgingSummaryRow(row: Record<string, unknown>): FinanceAgingSummaryRow {
  const numeric = (value: unknown) => (typeof value === "string" ? Number(value) : value);
  return FinanceAgingSummaryRowSchema.parse({
    bucketLabel: row.bucket_label,
    currency: row.currency,
    openAmount: numeric(row.open_amount),
    itemCount: typeof row.item_count === "string" ? Number(row.item_count) : row.item_count,
  });
}
