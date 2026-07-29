/**
 * Accounts Receivable contract (FIN-196, CG-S9-FIN-007). Mirrors
 * supabase/migrations/20260729100000_create_finance_accounts_receivable.sql's
 * app.finance_ar_open_items / app.finance_ar_open_item_events shapes and their RPCs.
 */

import { z } from "zod";

export const FINANCE_AR_OPEN_ITEM_STATUSES = ["open", "partial", "paid"] as const;
export const FinanceArOpenItemStatusSchema = z.enum(FINANCE_AR_OPEN_ITEM_STATUSES);
export type FinanceArOpenItemStatus = z.infer<typeof FinanceArOpenItemStatusSchema>;

export const FinanceArSourceDocumentTypeSchema = z.enum(["invoice", "opening_balance"]);
export type FinanceArSourceDocumentType = z.infer<typeof FinanceArSourceDocumentTypeSchema>;

export const FinanceArOpenItemSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  customerAccountId: z.string().uuid(),
  sourceDocumentType: FinanceArSourceDocumentTypeSchema,
  sourceDocumentId: z.string().uuid(),
  currency: z.string(),
  originalAmount: z.number(),
  allocatedAmount: z.number(),
  openAmount: z.number(),
  status: FinanceArOpenItemStatusSchema,
  isHeld: z.boolean(),
  holdReason: z.string().nullable(),
  heldBy: z.string().nullable(),
  heldAt: z.string().nullable(),
  releasedBy: z.string().nullable(),
  releasedAt: z.string().nullable(),
  invoiceDate: z.string(),
  dueDate: z.string(),
  postingPeriodId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceArOpenItem = z.infer<typeof FinanceArOpenItemSchema>;

export const FinanceArOpenItemEventTypeSchema = z.enum(["created", "allocated", "deallocated", "hold_placed", "hold_released"]);
export type FinanceArOpenItemEventType = z.infer<typeof FinanceArOpenItemEventTypeSchema>;

export const FinanceArOpenItemEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  openItemId: z.string().uuid(),
  eventType: FinanceArOpenItemEventTypeSchema,
  amountDelta: z.number().nullable(),
  reason: z.string().nullable(),
  sourceType: z.string().nullable(),
  sourceId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  createdAt: z.string(),
});
export type FinanceArOpenItemEvent = z.infer<typeof FinanceArOpenItemEventSchema>;

export const FinanceArExposureSummarySchema = z.object({
  totalOpen: z.number(),
  openCount: z.number().int(),
  overdueOpen: z.number(),
  overdueCount: z.number().int(),
});
export type FinanceArExposureSummary = z.infer<typeof FinanceArExposureSummarySchema>;

export const PostFinanceArOpenItemInputSchema = z.object({
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable().default(null),
  customerAccountId: z.string().uuid(),
  sourceDocumentType: FinanceArSourceDocumentTypeSchema,
  sourceDocumentId: z.string().uuid(),
  currency: z.string().regex(/^[A-Z]{3}$/),
  originalAmount: z.number().positive(),
  invoiceDate: z.string(),
  dueDate: z.string(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PostFinanceArOpenItemInput = z.input<typeof PostFinanceArOpenItemInputSchema>;

export const PlaceFinanceArHoldInputSchema = z.object({
  openItemId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PlaceFinanceArHoldInput = z.input<typeof PlaceFinanceArHoldInputSchema>;

export const ReleaseFinanceArHoldInputSchema = z.object({
  openItemId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReleaseFinanceArHoldInput = z.input<typeof ReleaseFinanceArHoldInputSchema>;

export const ApplyFinanceArAllocationInputSchema = z.object({
  openItemId: z.string().uuid(),
  amount: z.number().positive(),
  sourceType: z.string().min(1),
  sourceId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ApplyFinanceArAllocationInput = z.input<typeof ApplyFinanceArAllocationInputSchema>;

export const ReverseFinanceArAllocationInputSchema = z.object({
  openItemId: z.string().uuid(),
  amount: z.number().positive(),
  reason: z.string().min(1),
  sourceType: z.string().min(1),
  sourceId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReverseFinanceArAllocationInput = z.input<typeof ReverseFinanceArAllocationInputSchema>;

/** Maps a raw app.finance_ar_open_items row (snake_case) to this contract's camelCase shape. */
export function parseFinanceArOpenItem(row: Record<string, unknown>): FinanceArOpenItem {
  return FinanceArOpenItemSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    customerAccountId: row.customer_account_id,
    sourceDocumentType: row.source_document_type,
    sourceDocumentId: row.source_document_id,
    currency: row.currency,
    originalAmount: typeof row.original_amount === "string" ? Number(row.original_amount) : row.original_amount,
    allocatedAmount: typeof row.allocated_amount === "string" ? Number(row.allocated_amount) : row.allocated_amount,
    openAmount: typeof row.open_amount === "string" ? Number(row.open_amount) : row.open_amount,
    status: row.status,
    isHeld: row.is_held,
    holdReason: row.hold_reason,
    heldBy: row.held_by,
    heldAt: row.held_at,
    releasedBy: row.released_by,
    releasedAt: row.released_at,
    invoiceDate: row.invoice_date,
    dueDate: row.due_date,
    postingPeriodId: row.posting_period_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.finance_ar_open_item_events row (snake_case) to this contract's camelCase shape. */
export function parseFinanceArOpenItemEvent(row: Record<string, unknown>): FinanceArOpenItemEvent {
  return FinanceArOpenItemEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    openItemId: row.open_item_id,
    eventType: row.event_type,
    amountDelta: row.amount_delta === null || row.amount_delta === undefined ? null : Number(row.amount_delta),
    reason: row.reason,
    sourceType: row.source_type,
    sourceId: row.source_id,
    actorLabel: row.actor_label,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.get_finance_ar_exposure_summary() jsonb result to this contract's camelCase shape. */
export function parseFinanceArExposureSummary(row: Record<string, unknown>): FinanceArExposureSummary {
  return FinanceArExposureSummarySchema.parse({
    totalOpen: typeof row.totalOpen === "string" ? Number(row.totalOpen) : row.totalOpen,
    openCount: row.openCount,
    overdueOpen: typeof row.overdueOpen === "string" ? Number(row.overdueOpen) : row.overdueOpen,
    overdueCount: row.overdueCount,
  });
}
