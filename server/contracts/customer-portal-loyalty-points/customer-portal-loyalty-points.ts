/**
 * Points Ledger contract (CPL-318, CG-S13-CPL-020). Mirrors
 * supabase/migrations/20260801200000_create_customer_portal_loyalty_points_
 * ledger.sql's own two RPC surfaces: (a) tenant-internal, staff-gated
 * (LYL:*) point balance/lot/ledger reads, the earn/reversal/expiry posting
 * wrappers, the FIFO consumption primitive, and the point-adjustment maker-
 * checker pair; and (b) customer-facing (Layer 4) reads of a customer's own
 * point balance, ledger history, and expiry schedule.
 *
 * The THIRD Loyalty-domain contract in this repository (ADR-0024 Part D).
 * Depends on server/contracts/customer-portal-loyalty-program/ (CPL-316) for
 * LoyaltyAccount-shaped context where useful, but does not re-export it --
 * callers that need both import each contract directly.
 */

import { z } from "zod";

// ===========================================================================
// Shared enums
// ===========================================================================

export const LOYALTY_POINT_LOT_STATUSES = ["active", "exhausted", "expired"] as const;
export const LoyaltyPointLotStatusSchema = z.enum(LOYALTY_POINT_LOT_STATUSES);
export type LoyaltyPointLotStatus = z.infer<typeof LoyaltyPointLotStatusSchema>;

export const LOYALTY_POINT_LEDGER_EVENT_TYPES = ["earn", "reversal", "expiry", "adjustment", "redemption"] as const;
export const LoyaltyPointLedgerEventTypeSchema = z.enum(LOYALTY_POINT_LEDGER_EVENT_TYPES);
export type LoyaltyPointLedgerEventType = z.infer<typeof LoyaltyPointLedgerEventTypeSchema>;

export const LOYALTY_POINT_ADJUSTMENT_STATUSES = ["pending_approval", "approved", "rejected"] as const;
export const LoyaltyPointAdjustmentStatusSchema = z.enum(LOYALTY_POINT_ADJUSTMENT_STATUSES);
export type LoyaltyPointAdjustmentStatus = z.infer<typeof LoyaltyPointAdjustmentStatusSchema>;

function coerceNumber(value: unknown): number {
  return typeof value === "string" ? Number(value) : (value as number);
}

// ===========================================================================
// Staff-facing: app.loyalty_point_lots
// ===========================================================================

export const LoyaltyPointLotSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  sourceEarningEventId: z.string().uuid(),
  originalAmount: z.number(),
  remainingAmount: z.number(),
  expiresAt: z.string(),
  status: LoyaltyPointLotStatusSchema,
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LoyaltyPointLot = z.infer<typeof LoyaltyPointLotSchema>;

export function parseLoyaltyPointLot(row: Record<string, unknown>): LoyaltyPointLot {
  return LoyaltyPointLotSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    loyaltyAccountId: row.loyalty_account_id,
    sourceEarningEventId: row.source_earning_event_id,
    originalAmount: coerceNumber(row.original_amount),
    remainingAmount: coerceNumber(row.remaining_amount),
    expiresAt: row.expires_at,
    status: row.status,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

// ===========================================================================
// Staff-facing: app.loyalty_point_ledger_entries (full internal projection,
// includes reason -- staff-only)
// ===========================================================================

export const LoyaltyPointLedgerEntrySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  eventType: LoyaltyPointLedgerEventTypeSchema,
  amount: z.number(),
  lotId: z.string().uuid().nullable(),
  sourceType: z.string(),
  sourceId: z.string().uuid().nullable(),
  idempotencyKey: z.string(),
  correctsEntryId: z.string().uuid().nullable(),
  reason: z.string().nullable(),
  configVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type LoyaltyPointLedgerEntry = z.infer<typeof LoyaltyPointLedgerEntrySchema>;

export function parseLoyaltyPointLedgerEntry(row: Record<string, unknown>): LoyaltyPointLedgerEntry {
  return LoyaltyPointLedgerEntrySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    loyaltyAccountId: row.loyalty_account_id,
    eventType: row.event_type,
    amount: coerceNumber(row.amount),
    lotId: (row.lot_id as string | null) ?? null,
    sourceType: row.source_type,
    sourceId: (row.source_id as string | null) ?? null,
    idempotencyKey: row.idempotency_key,
    correctsEntryId: (row.corrects_entry_id as string | null) ?? null,
    reason: (row.reason as string | null) ?? null,
    configVersion: row.config_version,
    createdBy: (row.created_by as string | null) ?? null,
    createdAt: row.created_at,
  });
}

// ===========================================================================
// Staff-facing: app.loyalty_point_balances
// ===========================================================================

export const LoyaltyPointBalanceSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  totalEarned: z.number(),
  totalConsumed: z.number(),
  available: z.number(),
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
});
export type LoyaltyPointBalance = z.infer<typeof LoyaltyPointBalanceSchema>;

export function parseLoyaltyPointBalance(row: Record<string, unknown>): LoyaltyPointBalance {
  return LoyaltyPointBalanceSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    loyaltyAccountId: row.loyalty_account_id,
    totalEarned: coerceNumber(row.total_earned),
    totalConsumed: coerceNumber(row.total_consumed),
    available: coerceNumber(row.available),
    recordVersion: row.record_version,
    updatedAt: row.updated_at,
  });
}

// ===========================================================================
// Posting wrapper inputs (LYL:Edit/Configure -- staff/system only)
// ===========================================================================

export const PostLoyaltyPointsEarnedInputSchema = z.object({
  tenantId: z.string().uuid(),
  earningEventId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  expiryDays: z.number().int().min(1).max(3650).default(365),
});
export type PostLoyaltyPointsEarnedInput = z.input<typeof PostLoyaltyPointsEarnedInputSchema>;

export const ReverseLoyaltyPointsEarnedInputSchema = z.object({
  tenantId: z.string().uuid(),
  reversalEarningEventId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReverseLoyaltyPointsEarnedInput = z.input<typeof ReverseLoyaltyPointsEarnedInputSchema>;

export const ExpireLoyaltyPointLotsInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ExpireLoyaltyPointLotsInput = z.input<typeof ExpireLoyaltyPointLotsInputSchema>;

// ===========================================================================
// Staff-facing: app.loyalty_point_adjustment_requests (maker-checker)
// ===========================================================================

export const LoyaltyPointAdjustmentRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  adjustmentAmount: z.number(),
  reason: z.string(),
  requestedByAuthUserId: z.string().uuid(),
  requestedBy: z.string().nullable(),
  requestedAt: z.string(),
  status: LoyaltyPointAdjustmentStatusSchema,
  decidedByAuthUserId: z.string().uuid().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  decisionNotes: z.string().nullable(),
  ledgerEntryId: z.string().uuid().nullable(),
  idempotencyKey: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LoyaltyPointAdjustmentRequest = z.infer<typeof LoyaltyPointAdjustmentRequestSchema>;

export function parseLoyaltyPointAdjustmentRequest(row: Record<string, unknown>): LoyaltyPointAdjustmentRequest {
  return LoyaltyPointAdjustmentRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    loyaltyAccountId: row.loyalty_account_id,
    adjustmentAmount: coerceNumber(row.adjustment_amount),
    reason: row.reason,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestedBy: (row.requested_by as string | null) ?? null,
    requestedAt: row.requested_at,
    status: row.status,
    decidedByAuthUserId: (row.decided_by_auth_user_id as string | null) ?? null,
    decidedBy: (row.decided_by as string | null) ?? null,
    decidedAt: (row.decided_at as string | null) ?? null,
    decisionNotes: (row.decision_notes as string | null) ?? null,
    ledgerEntryId: (row.ledger_entry_id as string | null) ?? null,
    idempotencyKey: (row.idempotency_key as string | null) ?? null,
    recordVersion: row.record_version,
    createdBy: (row.created_by as string | null) ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const RequestLoyaltyPointAdjustmentInputSchema = z.object({
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  adjustmentAmount: z.number().refine((v) => v !== 0, "adjustmentAmount must be non-zero"),
  reason: z.string().min(1),
  idempotencyKey: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestLoyaltyPointAdjustmentInput = z.input<typeof RequestLoyaltyPointAdjustmentInputSchema>;

export const DecideLoyaltyPointAdjustmentInputSchema = z.object({
  tenantId: z.string().uuid(),
  adjustmentId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: z.enum(["approved", "rejected"]),
  decisionNotes: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DecideLoyaltyPointAdjustmentInput = z.input<typeof DecideLoyaltyPointAdjustmentInputSchema>;

// ===========================================================================
// Cursor pagination
// ===========================================================================

export const LoyaltyPointUpdatedAtCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type LoyaltyPointUpdatedAtCursor = z.input<typeof LoyaltyPointUpdatedAtCursorSchema>;

/** app.loyalty_point_ledger_entries has no updated_at column (append-only) -- keyed on created_at instead. */
export const LoyaltyPointCreatedAtCursorSchema = z
  .object({
    cursorCreatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorCreatedAt, {
    message: "cursorCreatedAt is required when cursorId is supplied",
    path: ["cursorCreatedAt"],
  });
export type LoyaltyPointCreatedAtCursor = z.input<typeof LoyaltyPointCreatedAtCursorSchema>;

/** app.list_customer_portal_loyalty_point_expiry_schedule paginates ASCENDING by expires_at (soonest first) -- a deliberate departure from the general descending convention. */
export const LoyaltyPointExpiresAtCursorSchema = z
  .object({
    cursorExpiresAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorExpiresAt, {
    message: "cursorExpiresAt is required when cursorId is supplied",
    path: ["cursorExpiresAt"],
  });
export type LoyaltyPointExpiresAtCursor = z.input<typeof LoyaltyPointExpiresAtCursorSchema>;

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A)
// ===========================================================================

export const CustomerPortalLoyaltyPointBalanceSchema = z.object({
  loyaltyAccountId: z.string().uuid(),
  customerAccountId: z.string().uuid(),
  programId: z.string().uuid(),
  programName: z.string(),
  totalEarned: z.number(),
  totalConsumed: z.number(),
  available: z.number(),
  updatedAt: z.string(),
});
export type CustomerPortalLoyaltyPointBalance = z.infer<typeof CustomerPortalLoyaltyPointBalanceSchema>;

export function parseCustomerPortalLoyaltyPointBalance(row: Record<string, unknown>): CustomerPortalLoyaltyPointBalance {
  return CustomerPortalLoyaltyPointBalanceSchema.parse({
    loyaltyAccountId: row.loyalty_account_id,
    customerAccountId: row.customer_account_id,
    programId: row.program_id,
    programName: row.program_name,
    totalEarned: coerceNumber(row.total_earned),
    totalConsumed: coerceNumber(row.total_consumed),
    available: coerceNumber(row.available),
    updatedAt: row.updated_at,
  });
}

/** Never carries a reason/internal-linkage field of any kind (structural, not merely a UI omission -- business rule: "cannot leak... internal investigation notes"). */
export const CustomerPortalLoyaltyPointLedgerEntrySchema = z.object({
  id: z.string().uuid(),
  programName: z.string(),
  eventType: LoyaltyPointLedgerEventTypeSchema,
  amount: z.number(),
  description: z.string(),
  createdAt: z.string(),
});
export type CustomerPortalLoyaltyPointLedgerEntry = z.infer<typeof CustomerPortalLoyaltyPointLedgerEntrySchema>;

export function parseCustomerPortalLoyaltyPointLedgerEntry(row: Record<string, unknown>): CustomerPortalLoyaltyPointLedgerEntry {
  return CustomerPortalLoyaltyPointLedgerEntrySchema.parse({
    id: row.id,
    programName: row.program_name,
    eventType: row.event_type,
    amount: coerceNumber(row.amount),
    description: row.description,
    createdAt: row.created_at,
  });
}

export const CustomerPortalLoyaltyPointExpiryScheduleEntrySchema = z.object({
  id: z.string().uuid(),
  programName: z.string(),
  remainingAmount: z.number(),
  expiresAt: z.string(),
});
export type CustomerPortalLoyaltyPointExpiryScheduleEntry = z.infer<typeof CustomerPortalLoyaltyPointExpiryScheduleEntrySchema>;

export function parseCustomerPortalLoyaltyPointExpiryScheduleEntry(row: Record<string, unknown>): CustomerPortalLoyaltyPointExpiryScheduleEntry {
  return CustomerPortalLoyaltyPointExpiryScheduleEntrySchema.parse({
    id: row.id,
    programName: row.program_name,
    remainingAmount: coerceNumber(row.remaining_amount),
    expiresAt: row.expires_at,
  });
}

/** Customer-safe, plain-language rendering of an expiry-schedule row -- never raw internal config. */
export function describeLoyaltyPointExpiry(entry: CustomerPortalLoyaltyPointExpiryScheduleEntry): string {
  const days = Math.max(0, Math.ceil((new Date(entry.expiresAt).getTime() - Date.now()) / (1000 * 60 * 60 * 24)));
  if (days === 0) {
    return `${entry.remainingAmount.toFixed(0)} points from ${entry.programName} expire today.`;
  }
  return `${entry.remainingAmount.toFixed(0)} points from ${entry.programName} expire in ${days} day${days === 1 ? "" : "s"}.`;
}
