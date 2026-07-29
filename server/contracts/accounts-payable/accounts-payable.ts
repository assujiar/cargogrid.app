/**
 * Accounts Payable contract (FIN-199, CG-S9-FIN-010). Mirrors
 * supabase/migrations/20260729130000_create_finance_accounts_payable.sql's
 * app.finance_ap_open_items / app.finance_ap_open_item_events shapes and
 * their RPCs -- the vendor-side mirror of FIN-196's own accounts-receivable
 * contract.
 */

import { z } from "zod";

export const FINANCE_AP_OPEN_ITEM_STATUSES = ["open", "partial", "settled"] as const;
export const FinanceApOpenItemStatusSchema = z.enum(FINANCE_AP_OPEN_ITEM_STATUSES);
export type FinanceApOpenItemStatus = z.infer<typeof FinanceApOpenItemStatusSchema>;

export const FinanceApSourceDocumentTypeSchema = z.enum(["vendor_bill", "opening_balance"]);
export type FinanceApSourceDocumentType = z.infer<typeof FinanceApSourceDocumentTypeSchema>;

export const FinanceApOpenItemSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  vendorMasterId: z.string().uuid(),
  sourceDocumentType: FinanceApSourceDocumentTypeSchema,
  sourceDocumentId: z.string().uuid(),
  currency: z.string(),
  originalAmount: z.number(),
  settledAmount: z.number(),
  openAmount: z.number(),
  status: FinanceApOpenItemStatusSchema,
  isHeld: z.boolean(),
  holdReason: z.string().nullable(),
  heldBy: z.string().nullable(),
  heldAt: z.string().nullable(),
  releasedBy: z.string().nullable(),
  releasedAt: z.string().nullable(),
  billDate: z.string(),
  dueDate: z.string(),
  postingPeriodId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceApOpenItem = z.infer<typeof FinanceApOpenItemSchema>;

export const FinanceApOpenItemEventTypeSchema = z.enum(["created", "settled", "unsettled", "hold_placed", "hold_released"]);
export type FinanceApOpenItemEventType = z.infer<typeof FinanceApOpenItemEventTypeSchema>;

export const FinanceApOpenItemEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  openItemId: z.string().uuid(),
  eventType: FinanceApOpenItemEventTypeSchema,
  amountDelta: z.number().nullable(),
  reason: z.string().nullable(),
  sourceType: z.string().nullable(),
  sourceId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  createdAt: z.string(),
});
export type FinanceApOpenItemEvent = z.infer<typeof FinanceApOpenItemEventSchema>;

export const FinanceApExposureSummarySchema = z.object({
  totalOpen: z.number(),
  openCount: z.number().int(),
  overdueOpen: z.number(),
  overdueCount: z.number().int(),
});
export type FinanceApExposureSummary = z.infer<typeof FinanceApExposureSummarySchema>;

export const PostFinanceApOpenItemInputSchema = z.object({
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable().default(null),
  vendorMasterId: z.string().uuid(),
  sourceDocumentType: FinanceApSourceDocumentTypeSchema,
  sourceDocumentId: z.string().uuid(),
  currency: z.string().regex(/^[A-Z]{3}$/),
  originalAmount: z.number().positive(),
  billDate: z.string(),
  dueDate: z.string(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PostFinanceApOpenItemInput = z.input<typeof PostFinanceApOpenItemInputSchema>;

export const PlaceFinanceApHoldInputSchema = z.object({
  openItemId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PlaceFinanceApHoldInput = z.input<typeof PlaceFinanceApHoldInputSchema>;

export const ReleaseFinanceApHoldInputSchema = z.object({
  openItemId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReleaseFinanceApHoldInput = z.input<typeof ReleaseFinanceApHoldInputSchema>;

export const ApplyFinanceApSettlementInputSchema = z.object({
  openItemId: z.string().uuid(),
  amount: z.number().positive(),
  sourceType: z.string().min(1),
  sourceId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ApplyFinanceApSettlementInput = z.input<typeof ApplyFinanceApSettlementInputSchema>;

export const ReverseFinanceApSettlementInputSchema = z.object({
  openItemId: z.string().uuid(),
  amount: z.number().positive(),
  reason: z.string().min(1),
  sourceType: z.string().min(1),
  sourceId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReverseFinanceApSettlementInput = z.input<typeof ReverseFinanceApSettlementInputSchema>;

/** Maps a raw app.finance_ap_open_items row (snake_case) to this contract's camelCase shape. */
export function parseFinanceApOpenItem(row: Record<string, unknown>): FinanceApOpenItem {
  return FinanceApOpenItemSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    vendorMasterId: row.vendor_master_id,
    sourceDocumentType: row.source_document_type,
    sourceDocumentId: row.source_document_id,
    currency: row.currency,
    originalAmount: typeof row.original_amount === "string" ? Number(row.original_amount) : row.original_amount,
    settledAmount: typeof row.settled_amount === "string" ? Number(row.settled_amount) : row.settled_amount,
    openAmount: typeof row.open_amount === "string" ? Number(row.open_amount) : row.open_amount,
    status: row.status,
    isHeld: row.is_held,
    holdReason: row.hold_reason,
    heldBy: row.held_by,
    heldAt: row.held_at,
    releasedBy: row.released_by,
    releasedAt: row.released_at,
    billDate: row.bill_date,
    dueDate: row.due_date,
    postingPeriodId: row.posting_period_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.finance_ap_open_item_events row (snake_case) to this contract's camelCase shape. */
export function parseFinanceApOpenItemEvent(row: Record<string, unknown>): FinanceApOpenItemEvent {
  return FinanceApOpenItemEventSchema.parse({
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

/** Maps a raw app.get_finance_ap_exposure_summary() jsonb result to this contract's camelCase shape. */
export function parseFinanceApExposureSummary(row: Record<string, unknown>): FinanceApExposureSummary {
  return FinanceApExposureSummarySchema.parse({
    totalOpen: typeof row.totalOpen === "string" ? Number(row.totalOpen) : row.totalOpen,
    openCount: row.openCount,
    overdueOpen: typeof row.overdueOpen === "string" ? Number(row.overdueOpen) : row.overdueOpen,
    overdueCount: row.overdueCount,
  });
}
