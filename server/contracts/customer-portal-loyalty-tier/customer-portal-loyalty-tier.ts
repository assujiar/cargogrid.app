/**
 * Membership Tier contract (CPL-317, CG-S13-CPL-019). Mirrors
 * supabase/migrations/20260801190000_create_customer_portal_loyalty_
 * membership_tier.sql's own two RPC surfaces: (a) tenant-internal,
 * staff-gated (LYL:*) tier-definition draft/publish/supersede admin CRUD,
 * account tier-state read, tier-movement history, recalculation, and
 * fraud-hold/release; and (b) customer-facing (Layer 4) reads of a
 * customer's own loyalty tier card(s) (current tier, progress toward the
 * next tier, benefits, review date).
 *
 * Depends on CPL-316's own contract (server/contracts/customer-portal-
 * loyalty-program/) for LoyaltyAccountStatus etc where useful, but does not
 * re-export it -- callers that need both import each contract directly.
 */

import { z } from "zod";

// ===========================================================================
// Shared enums
// ===========================================================================

export const LOYALTY_TIER_DEFINITION_STATUSES = ["draft", "published", "superseded"] as const;
export const LoyaltyTierDefinitionStatusSchema = z.enum(LOYALTY_TIER_DEFINITION_STATUSES);
export type LoyaltyTierDefinitionStatus = z.infer<typeof LoyaltyTierDefinitionStatusSchema>;

export const LOYALTY_TIER_MOVEMENT_TYPES = ["initial", "upgrade", "downgrade"] as const;
export const LoyaltyTierMovementTypeSchema = z.enum(LOYALTY_TIER_MOVEMENT_TYPES);
export type LoyaltyTierMovementType = z.infer<typeof LoyaltyTierMovementTypeSchema>;

/** The only threshold_dimension this checkpoint's own recalculation RPC implements (migration design decision 7). Others are structurally valid but rejected at evaluation time (unsupported_threshold_dimension). */
export const SUPPORTED_LOYALTY_TIER_THRESHOLD_DIMENSIONS = ["earning_amount_ytd"] as const;

function coerceNumber(value: unknown): number {
  return typeof value === "string" ? Number(value) : (value as number);
}

// ===========================================================================
// Staff-facing: app.loyalty_tier_definitions
// ===========================================================================

export const LoyaltyTierDefinitionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  programId: z.string().uuid(),
  tierName: z.string(),
  tierRank: z.number().int().positive(),
  thresholdDimension: z.string(),
  thresholdValue: z.number(),
  benefits: z.record(z.string(), z.unknown()),
  reviewPeriodDays: z.number().int().min(0),
  versionNumber: z.number().int().positive(),
  status: LoyaltyTierDefinitionStatusSchema,
  effectiveFrom: z.string().nullable(),
  effectiveTo: z.string().nullable(),
  publishedBy: z.string().nullable(),
  publishedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LoyaltyTierDefinition = z.infer<typeof LoyaltyTierDefinitionSchema>;

export function parseLoyaltyTierDefinition(row: Record<string, unknown>): LoyaltyTierDefinition {
  return LoyaltyTierDefinitionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    programId: row.program_id,
    tierName: row.tier_name,
    tierRank: row.tier_rank,
    thresholdDimension: row.threshold_dimension,
    thresholdValue: coerceNumber(row.threshold_value),
    benefits: (row.benefits as Record<string, unknown>) ?? {},
    reviewPeriodDays: row.review_period_days,
    versionNumber: row.version_number,
    status: row.status,
    effectiveFrom: (row.effective_from as string | null) ?? null,
    effectiveTo: (row.effective_to as string | null) ?? null,
    publishedBy: (row.published_by as string | null) ?? null,
    publishedAt: (row.published_at as string | null) ?? null,
    recordVersion: row.record_version,
    createdBy: (row.created_by as string | null) ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const CreateLoyaltyTierDefinitionInputSchema = z.object({
  tenantId: z.string().uuid(),
  programId: z.string().uuid(),
  tierName: z.string().min(1),
  tierRank: z.number().int().positive(),
  thresholdDimension: z.string().min(1),
  thresholdValue: z.number().min(0),
  benefits: z.record(z.string(), z.unknown()).default({}),
  reviewPeriodDays: z.number().int().min(0).default(0),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateLoyaltyTierDefinitionInput = z.input<typeof CreateLoyaltyTierDefinitionInputSchema>;

export const UpdateLoyaltyTierDefinitionDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  tierDefinitionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  tierName: z.string().min(1),
  tierRank: z.number().int().positive(),
  thresholdDimension: z.string().min(1),
  thresholdValue: z.number().min(0),
  benefits: z.record(z.string(), z.unknown()).default({}),
  reviewPeriodDays: z.number().int().min(0).default(0),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateLoyaltyTierDefinitionDraftInput = z.input<typeof UpdateLoyaltyTierDefinitionDraftInputSchema>;

export const PublishLoyaltyTierDefinitionInputSchema = z.object({
  tenantId: z.string().uuid(),
  tierDefinitionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  effectiveFrom: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishLoyaltyTierDefinitionInput = z.input<typeof PublishLoyaltyTierDefinitionInputSchema>;

// ===========================================================================
// Staff-facing: app.loyalty_account_tier_movements (full internal projection)
// ===========================================================================

export const LoyaltyAccountTierMovementSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  fromTierId: z.string().uuid().nullable(),
  toTierId: z.string().uuid(),
  movementType: LoyaltyTierMovementTypeSchema,
  tierDefinitionVersionId: z.string().uuid(),
  evaluationSnapshot: z.record(z.string(), z.unknown()),
  reason: z.string().nullable(),
  nextReviewAt: z.string(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type LoyaltyAccountTierMovement = z.infer<typeof LoyaltyAccountTierMovementSchema>;

export function parseLoyaltyAccountTierMovement(row: Record<string, unknown>): LoyaltyAccountTierMovement {
  return LoyaltyAccountTierMovementSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    loyaltyAccountId: row.loyalty_account_id,
    fromTierId: (row.from_tier_id as string | null) ?? null,
    toTierId: row.to_tier_id,
    movementType: row.movement_type,
    tierDefinitionVersionId: row.tier_definition_version_id,
    evaluationSnapshot: (row.evaluation_snapshot as Record<string, unknown>) ?? {},
    reason: (row.reason as string | null) ?? null,
    nextReviewAt: row.next_review_at,
    createdBy: (row.created_by as string | null) ?? null,
    createdAt: row.created_at,
  });
}

export const RecalculateCustomerLoyaltyTierInputSchema = z.object({
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecalculateCustomerLoyaltyTierInput = z.input<typeof RecalculateCustomerLoyaltyTierInputSchema>;

// ===========================================================================
// Staff-facing: app.loyalty_account_tier_holds
// ===========================================================================

export const LoyaltyAccountTierHoldSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  isHeld: z.boolean(),
  holdReason: z.string().nullable(),
  heldBy: z.string().nullable(),
  heldAt: z.string().nullable(),
  releasedBy: z.string().nullable(),
  releasedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LoyaltyAccountTierHold = z.infer<typeof LoyaltyAccountTierHoldSchema>;

export function parseLoyaltyAccountTierHold(row: Record<string, unknown>): LoyaltyAccountTierHold {
  return LoyaltyAccountTierHoldSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    loyaltyAccountId: row.loyalty_account_id,
    isHeld: row.is_held,
    holdReason: (row.hold_reason as string | null) ?? null,
    heldBy: (row.held_by as string | null) ?? null,
    heldAt: (row.held_at as string | null) ?? null,
    releasedBy: (row.released_by as string | null) ?? null,
    releasedAt: (row.released_at as string | null) ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const HoldLoyaltyAccountTierBenefitsInputSchema = z.object({
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type HoldLoyaltyAccountTierBenefitsInput = z.input<typeof HoldLoyaltyAccountTierBenefitsInputSchema>;

export const ReleaseLoyaltyAccountTierBenefitsInputSchema = z.object({
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReleaseLoyaltyAccountTierBenefitsInput = z.input<typeof ReleaseLoyaltyAccountTierBenefitsInputSchema>;

// ===========================================================================
// Staff-facing: app.get_loyalty_account_tier_state (combined projection)
// ===========================================================================

export const LoyaltyAccountTierStateSchema = z.object({
  loyaltyAccountId: z.string().uuid(),
  currentTierId: z.string().uuid().nullable(),
  currentTierName: z.string().nullable(),
  currentTierRank: z.number().int().nullable(),
  movementType: LoyaltyTierMovementTypeSchema.nullable(),
  nextReviewAt: z.string().nullable(),
  tierSince: z.string().nullable(),
  isHeld: z.boolean(),
  holdReason: z.string().nullable(),
  heldBy: z.string().nullable(),
  heldAt: z.string().nullable(),
});
export type LoyaltyAccountTierState = z.infer<typeof LoyaltyAccountTierStateSchema>;

export function parseLoyaltyAccountTierState(row: Record<string, unknown>): LoyaltyAccountTierState {
  return LoyaltyAccountTierStateSchema.parse({
    loyaltyAccountId: row.loyalty_account_id,
    currentTierId: (row.current_tier_id as string | null) ?? null,
    currentTierName: (row.current_tier_name as string | null) ?? null,
    currentTierRank: (row.current_tier_rank as number | null) ?? null,
    movementType: (row.movement_type as LoyaltyTierMovementType | null) ?? null,
    nextReviewAt: (row.next_review_at as string | null) ?? null,
    tierSince: (row.tier_since as string | null) ?? null,
    isHeld: row.is_held,
    holdReason: (row.hold_reason as string | null) ?? null,
    heldBy: (row.held_by as string | null) ?? null,
    heldAt: (row.held_at as string | null) ?? null,
  });
}

// ===========================================================================
// Cursor pagination
// ===========================================================================

export const LoyaltyTierUpdatedAtCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type LoyaltyTierUpdatedAtCursor = z.input<typeof LoyaltyTierUpdatedAtCursorSchema>;

/** app.list_loyalty_account_tier_movements has no updated_at column (append-only) -- keyed on created_at instead. */
export const LoyaltyTierCreatedAtCursorSchema = z
  .object({
    cursorCreatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorCreatedAt, {
    message: "cursorCreatedAt is required when cursorId is supplied",
    path: ["cursorCreatedAt"],
  });
export type LoyaltyTierCreatedAtCursor = z.input<typeof LoyaltyTierCreatedAtCursorSchema>;

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A): app.list_customer_portal_
// loyalty_tier_cards
// ===========================================================================

export const CustomerPortalLoyaltyTierCardSchema = z.object({
  loyaltyAccountId: z.string().uuid(),
  customerAccountId: z.string().uuid(),
  programId: z.string().uuid(),
  programName: z.string(),
  currentTierId: z.string().uuid().nullable(),
  currentTierName: z.string().nullable(),
  currentTierRank: z.number().int().nullable(),
  benefits: z.record(z.string(), z.unknown()),
  isBenefitsSuspended: z.boolean(),
  benefitsSuspendedReason: z.string().nullable(),
  computedAmount: z.number(),
  nextTierId: z.string().uuid().nullable(),
  nextTierName: z.string().nullable(),
  nextTierThreshold: z.number().nullable(),
  amountToNextTier: z.number().nullable(),
  nextReviewAt: z.string().nullable(),
  tierSince: z.string().nullable(),
});
export type CustomerPortalLoyaltyTierCard = z.infer<typeof CustomerPortalLoyaltyTierCardSchema>;

export function parseCustomerPortalLoyaltyTierCard(row: Record<string, unknown>): CustomerPortalLoyaltyTierCard {
  return CustomerPortalLoyaltyTierCardSchema.parse({
    loyaltyAccountId: row.loyalty_account_id,
    customerAccountId: row.customer_account_id,
    programId: row.program_id,
    programName: row.program_name,
    currentTierId: (row.current_tier_id as string | null) ?? null,
    currentTierName: (row.current_tier_name as string | null) ?? null,
    currentTierRank: (row.current_tier_rank as number | null) ?? null,
    benefits: (row.benefits as Record<string, unknown>) ?? {},
    isBenefitsSuspended: row.is_benefits_suspended,
    benefitsSuspendedReason: (row.benefits_suspended_reason as string | null) ?? null,
    computedAmount: coerceNumber(row.computed_amount),
    nextTierId: (row.next_tier_id as string | null) ?? null,
    nextTierName: (row.next_tier_name as string | null) ?? null,
    nextTierThreshold: row.next_tier_threshold === null || row.next_tier_threshold === undefined ? null : coerceNumber(row.next_tier_threshold),
    amountToNextTier: row.amount_to_next_tier === null || row.amount_to_next_tier === undefined ? null : coerceNumber(row.amount_to_next_tier),
    nextReviewAt: (row.next_review_at as string | null) ?? null,
    tierSince: (row.tier_since as string | null) ?? null,
  });
}

/** Customer-safe, plain-language rendering of a tier card's own progress -- never raw internal config. */
export function describeLoyaltyTierProgress(card: CustomerPortalLoyaltyTierCard): string {
  if (card.currentTierId === null) {
    return "Your tier has not been evaluated yet. Contact your account administrator if you believe this is a mistake.";
  }
  if (card.nextTierId === null) {
    return `You are at ${card.currentTierName ?? "your current tier"}, the highest available tier in this program.`;
  }
  return `You are ${(card.amountToNextTier ?? 0).toFixed(2)} away from ${card.nextTierName ?? "the next tier"}.`;
}
