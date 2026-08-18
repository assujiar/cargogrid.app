/**
 * Redemption Approval and Fulfillment contract (CPL-321, CG-S13-CPL-023).
 * Mirrors supabase/migrations/20260801230000_create_customer_portal_
 * loyalty_redemption_approval_fulfillment.sql's own two RPC surfaces: (a)
 * tenant-internal, staff-gated (LYL:*) approval/fulfillment workbench
 * reads/mutations; and (b) the dual-authority submit/cancel RPCs plus
 * customer-facing (Layer 4) reads of a customer's own redemption status and
 * history.
 *
 * The SIXTH Loyalty-domain contract in this repository (ADR-0024 Part D).
 * Depends on server/contracts/customer-portal-loyalty-rewards/ (CPL-320) for
 * LoyaltyRewardType-shaped context where useful, but does not re-export it
 * -- callers that need both import each contract directly.
 */

import { z } from "zod";

// ===========================================================================
// Shared enums
// ===========================================================================

export const LOYALTY_REDEMPTION_REWARD_TYPES = ["discount_voucher", "physical_item", "service_credit"] as const;
export const LoyaltyRedemptionRewardTypeSchema = z.enum(LOYALTY_REDEMPTION_REWARD_TYPES);
export type LoyaltyRedemptionRewardType = z.infer<typeof LoyaltyRedemptionRewardTypeSchema>;

export const LOYALTY_REDEMPTION_STATUSES = ["pending_approval", "approved", "rejected", "fulfilling", "fulfilled", "cancelled", "failed"] as const;
export const LoyaltyRedemptionStatusSchema = z.enum(LOYALTY_REDEMPTION_STATUSES);
export type LoyaltyRedemptionStatus = z.infer<typeof LoyaltyRedemptionStatusSchema>;

export const LOYALTY_REDEMPTION_FULFILLMENT_STATUSES = ["not_applicable", "pending", "in_fulfillment", "fulfilled", "failed"] as const;
export const LoyaltyRedemptionFulfillmentStatusSchema = z.enum(LOYALTY_REDEMPTION_FULFILLMENT_STATUSES);
export type LoyaltyRedemptionFulfillmentStatus = z.infer<typeof LoyaltyRedemptionFulfillmentStatusSchema>;

export const LOYALTY_REDEMPTION_EVENT_TYPES = ["submitted", "approved", "rejected", "cancelled", "fulfilled", "fulfillment_failed"] as const;
export const LoyaltyRedemptionEventTypeSchema = z.enum(LOYALTY_REDEMPTION_EVENT_TYPES);
export type LoyaltyRedemptionEventType = z.infer<typeof LoyaltyRedemptionEventTypeSchema>;

function coerceNumber(value: unknown): number {
  return typeof value === "string" ? Number(value) : (value as number);
}

// ===========================================================================
// Staff-facing: app.loyalty_redemptions (full internal projection)
// ===========================================================================

export const LoyaltyRedemptionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  rewardId: z.string().uuid(),
  rewardVersionNumber: z.number().int().positive(),
  rewardName: z.string(),
  rewardType: LoyaltyRedemptionRewardTypeSchema,
  pointsConsumed: z.number(),
  stockReservationId: z.string().uuid().nullable(),
  benefitEntitlementId: z.string().uuid().nullable(),
  status: LoyaltyRedemptionStatusSchema,
  fulfillmentStatus: LoyaltyRedemptionFulfillmentStatusSchema,
  decisionReason: z.string().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LoyaltyRedemption = z.infer<typeof LoyaltyRedemptionSchema>;

export function parseLoyaltyRedemption(row: Record<string, unknown>): LoyaltyRedemption {
  return LoyaltyRedemptionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    loyaltyAccountId: row.loyalty_account_id,
    rewardId: row.reward_id,
    rewardVersionNumber: row.reward_version_number,
    rewardName: row.reward_name,
    rewardType: row.reward_type,
    pointsConsumed: coerceNumber(row.points_consumed),
    stockReservationId: (row.stock_reservation_id as string | null) ?? null,
    benefitEntitlementId: (row.benefit_entitlement_id as string | null) ?? null,
    status: row.status,
    fulfillmentStatus: row.fulfillment_status,
    decisionReason: (row.decision_reason as string | null) ?? null,
    decidedBy: (row.decided_by as string | null) ?? null,
    decidedAt: (row.decided_at as string | null) ?? null,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdBy: (row.created_by as string | null) ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

// ===========================================================================
// Staff-facing: app.loyalty_redemption_events (append-only)
// ===========================================================================

export const LoyaltyRedemptionEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  redemptionId: z.string().uuid(),
  eventType: LoyaltyRedemptionEventTypeSchema,
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  createdAt: z.string(),
});
export type LoyaltyRedemptionEvent = z.infer<typeof LoyaltyRedemptionEventSchema>;

export function parseLoyaltyRedemptionEvent(row: Record<string, unknown>): LoyaltyRedemptionEvent {
  return LoyaltyRedemptionEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    redemptionId: row.redemption_id,
    eventType: row.event_type,
    reason: (row.reason as string | null) ?? null,
    actorAuthUserId: (row.actor_auth_user_id as string | null) ?? null,
    actorLabel: (row.actor_label as string | null) ?? null,
    createdAt: row.created_at,
  });
}

// ===========================================================================
// Mutation inputs
// ===========================================================================

export const SubmitLoyaltyRedemptionInputSchema = z.object({
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  rewardId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitLoyaltyRedemptionInput = z.input<typeof SubmitLoyaltyRedemptionInputSchema>;

export const DecideLoyaltyRedemptionInputSchema = z
  .object({
    tenantId: z.string().uuid(),
    redemptionId: z.string().uuid(),
    expectedVersion: z.number().int().positive(),
    decision: z.enum(["approve", "reject"]),
    decisionReason: z.string().nullable().default(null),
    actorAuthUserId: z.string().uuid(),
    actorLabel: z.string().min(1),
  })
  .refine((v) => v.decision !== "reject" || (!!v.decisionReason && v.decisionReason.trim().length > 0), {
    message: "decisionReason is required to reject a redemption",
    path: ["decisionReason"],
  });
export type DecideLoyaltyRedemptionInput = z.input<typeof DecideLoyaltyRedemptionInputSchema>;

export const CancelLoyaltyRedemptionInputSchema = z.object({
  tenantId: z.string().uuid(),
  redemptionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelLoyaltyRedemptionInput = z.input<typeof CancelLoyaltyRedemptionInputSchema>;

export const MarkLoyaltyRedemptionFulfilledInputSchema = z.object({
  tenantId: z.string().uuid(),
  redemptionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type MarkLoyaltyRedemptionFulfilledInput = z.input<typeof MarkLoyaltyRedemptionFulfilledInputSchema>;

export const MarkLoyaltyRedemptionFulfillmentFailedInputSchema = z.object({
  tenantId: z.string().uuid(),
  redemptionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type MarkLoyaltyRedemptionFulfillmentFailedInput = z.input<typeof MarkLoyaltyRedemptionFulfillmentFailedInputSchema>;

// ===========================================================================
// Cursor pagination
// ===========================================================================

export const LoyaltyRedemptionUpdatedAtCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type LoyaltyRedemptionUpdatedAtCursor = z.input<typeof LoyaltyRedemptionUpdatedAtCursorSchema>;

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A) -- never carries
// idempotencyKey/createdBy/stockReservationId (internal ledger refs).
// ===========================================================================

export const CustomerPortalLoyaltyRedemptionSchema = z.object({
  redemptionId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  rewardId: z.string().uuid(),
  rewardName: z.string(),
  rewardType: LoyaltyRedemptionRewardTypeSchema,
  pointsConsumed: z.number(),
  benefitEntitlementId: z.string().uuid().nullable(),
  status: LoyaltyRedemptionStatusSchema,
  fulfillmentStatus: LoyaltyRedemptionFulfillmentStatusSchema,
  decisionReason: z.string().nullable(),
  decidedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CustomerPortalLoyaltyRedemption = z.infer<typeof CustomerPortalLoyaltyRedemptionSchema>;

export function parseCustomerPortalLoyaltyRedemption(row: Record<string, unknown>): CustomerPortalLoyaltyRedemption {
  return CustomerPortalLoyaltyRedemptionSchema.parse({
    redemptionId: row.redemption_id,
    loyaltyAccountId: row.loyalty_account_id,
    rewardId: row.reward_id,
    rewardName: row.reward_name,
    rewardType: row.reward_type,
    pointsConsumed: coerceNumber(row.points_consumed),
    benefitEntitlementId: (row.benefit_entitlement_id as string | null) ?? null,
    status: row.status,
    fulfillmentStatus: row.fulfillment_status,
    decisionReason: (row.decision_reason as string | null) ?? null,
    decidedAt: (row.decided_at as string | null) ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Customer-safe, plain-language status label -- never the raw enum value verbatim. */
export function describeLoyaltyRedemptionStatus(redemption: Pick<CustomerPortalLoyaltyRedemption, "status" | "fulfillmentStatus">): string {
  switch (redemption.status) {
    case "pending_approval":
      return "Awaiting review";
    case "approved":
      return "Approved";
    case "rejected":
      return "Not approved";
    case "fulfilling":
      return redemption.fulfillmentStatus === "in_fulfillment" ? "Being prepared" : "Approved, preparing to fulfill";
    case "fulfilled":
      return "Completed";
    case "cancelled":
      return "Cancelled";
    case "failed":
      return "Could not be fulfilled";
    default:
      return redemption.status;
  }
}

/** Whether the caller's own redemption may still be cancelled -- mirrors app.cancel_loyalty_redemption's own state-machine gate (pending_approval only). */
export function canCancelLoyaltyRedemption(redemption: Pick<CustomerPortalLoyaltyRedemption, "status">): boolean {
  return redemption.status === "pending_approval";
}
