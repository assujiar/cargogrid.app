/**
 * Reward Catalogue contract (CPL-320, CG-S13-CPL-022). Mirrors
 * supabase/migrations/20260801220000_create_customer_portal_loyalty_
 * reward_catalogue.sql's own two RPC surfaces: (a) tenant-internal,
 * staff-gated (LYL:*) reward draft/publish/pause/resume/archive lifecycle,
 * stock reservation, and reads; and (b) customer-facing (Layer 4) reads of
 * the eligible/locked/out_of_stock/unavailable catalogue and a single
 * reward's own detail.
 *
 * The FIFTH Loyalty-domain contract in this repository (ADR-0024 Part D),
 * the first of Batch 5 (CPL-320..323). This is a CATALOGUE-only capability
 * -- no redemption/consume-stock mutation exists here (CPL-321's own future
 * scope, disclosed in the migration's own header). Depends on
 * server/contracts/customer-portal-loyalty-tier/ (CPL-317) for tier-name
 * context where useful, but does not re-export it -- callers that need both
 * import each contract directly.
 */

import { z } from "zod";

// ===========================================================================
// Shared enums
// ===========================================================================

export const LOYALTY_REWARD_TYPES = ["discount_voucher", "physical_item", "service_credit"] as const;
export const LoyaltyRewardTypeSchema = z.enum(LOYALTY_REWARD_TYPES);
export type LoyaltyRewardType = z.infer<typeof LoyaltyRewardTypeSchema>;

export const LOYALTY_REWARD_STATUSES = ["draft", "published", "paused", "superseded", "archived"] as const;
export const LoyaltyRewardStatusSchema = z.enum(LOYALTY_REWARD_STATUSES);
export type LoyaltyRewardStatus = z.infer<typeof LoyaltyRewardStatusSchema>;

export const CUSTOMER_PORTAL_LOYALTY_REWARD_DISPLAY_STATES = ["eligible", "locked", "out_of_stock", "unavailable"] as const;
export const CustomerPortalLoyaltyRewardDisplayStateSchema = z.enum(CUSTOMER_PORTAL_LOYALTY_REWARD_DISPLAY_STATES);
export type CustomerPortalLoyaltyRewardDisplayState = z.infer<typeof CustomerPortalLoyaltyRewardDisplayStateSchema>;

function coerceNumber(value: unknown): number {
  return typeof value === "string" ? Number(value) : (value as number);
}
function coerceNullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : coerceNumber(value);
}

// ===========================================================================
// Staff-facing: app.loyalty_rewards (full internal projection -- includes
// internal_cost/vendor_ref, structurally absent from every customer-facing
// schema below).
// ===========================================================================

export const LoyaltyRewardSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  programId: z.string().uuid(),
  rewardName: z.string(),
  rewardType: LoyaltyRewardTypeSchema,
  description: z.string().nullable(),
  termsText: z.string().nullable(),
  minTierId: z.string().uuid().nullable(),
  minPointsRequired: z.number().nullable(),
  totalStock: z.number().int().nullable(),
  internalCost: z.number().nullable(),
  vendorRef: z.string().nullable(),
  fileId: z.string().uuid().nullable(),
  versionNumber: z.number().int().positive(),
  status: LoyaltyRewardStatusSchema,
  effectiveFrom: z.string().nullable(),
  effectiveTo: z.string().nullable(),
  publishedBy: z.string().nullable(),
  publishedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LoyaltyReward = z.infer<typeof LoyaltyRewardSchema>;

export function parseLoyaltyReward(row: Record<string, unknown>): LoyaltyReward {
  return LoyaltyRewardSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    programId: row.program_id,
    rewardName: row.reward_name,
    rewardType: row.reward_type,
    description: (row.description as string | null) ?? null,
    termsText: (row.terms_text as string | null) ?? null,
    minTierId: (row.min_tier_id as string | null) ?? null,
    minPointsRequired: coerceNullableNumber(row.min_points_required),
    totalStock: (row.total_stock as number | null) ?? null,
    internalCost: coerceNullableNumber(row.internal_cost),
    vendorRef: (row.vendor_ref as string | null) ?? null,
    fileId: (row.file_id as string | null) ?? null,
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

// ===========================================================================
// app.loyalty_reward_stock_reservations -- the real, race-safe stock
// primitive (design decision 7). Never called by any production path in
// this checkpoint (CPL-321's own scope) -- wrapped here for completeness/
// future use, mirroring CPL-318's own consumeLoyaltyPointsFifo precedent.
// ===========================================================================

export const LoyaltyRewardStockReservationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  rewardId: z.string().uuid(),
  quantity: z.number().int().positive(),
  reason: z.string().nullable(),
  createdBy: z.string().nullable(),
  idempotencyKey: z.string(),
  createdAt: z.string(),
});
export type LoyaltyRewardStockReservation = z.infer<typeof LoyaltyRewardStockReservationSchema>;

export function parseLoyaltyRewardStockReservation(row: Record<string, unknown>): LoyaltyRewardStockReservation {
  return LoyaltyRewardStockReservationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    rewardId: row.reward_id,
    quantity: row.quantity,
    reason: (row.reason as string | null) ?? null,
    createdBy: (row.created_by as string | null) ?? null,
    idempotencyKey: row.idempotency_key,
    createdAt: row.created_at,
  });
}

// ===========================================================================
// Mutation inputs
// ===========================================================================

const rewardDraftFieldsSchema = {
  tenantId: z.string().uuid(),
  rewardName: z.string().min(1),
  rewardType: LoyaltyRewardTypeSchema,
  description: z.string().nullable().default(null),
  termsText: z.string().nullable().default(null),
  minTierId: z.string().uuid().nullable().default(null),
  minPointsRequired: z.number().min(0).nullable().default(null),
  totalStock: z.number().int().min(0).nullable().default(null),
  internalCost: z.number().min(0).nullable().default(null),
  vendorRef: z.string().nullable().default(null),
  fileId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
};

export const CreateLoyaltyRewardDraftInputSchema = z.object({
  ...rewardDraftFieldsSchema,
  programId: z.string().uuid(),
});
export type CreateLoyaltyRewardDraftInput = z.input<typeof CreateLoyaltyRewardDraftInputSchema>;

export const UpdateLoyaltyRewardDraftInputSchema = z.object({
  ...rewardDraftFieldsSchema,
  rewardId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
});
export type UpdateLoyaltyRewardDraftInput = z.input<typeof UpdateLoyaltyRewardDraftInputSchema>;

export const PublishLoyaltyRewardInputSchema = z.object({
  tenantId: z.string().uuid(),
  rewardId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  effectiveFrom: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishLoyaltyRewardInput = z.input<typeof PublishLoyaltyRewardInputSchema>;

export const PauseLoyaltyRewardInputSchema = z.object({
  tenantId: z.string().uuid(),
  rewardId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PauseLoyaltyRewardInput = z.input<typeof PauseLoyaltyRewardInputSchema>;

export const ResumeLoyaltyRewardInputSchema = z.object({
  tenantId: z.string().uuid(),
  rewardId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ResumeLoyaltyRewardInput = z.input<typeof ResumeLoyaltyRewardInputSchema>;

export const ArchiveLoyaltyRewardInputSchema = z.object({
  tenantId: z.string().uuid(),
  rewardId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ArchiveLoyaltyRewardInput = z.input<typeof ArchiveLoyaltyRewardInputSchema>;

/** app.reserve_loyalty_reward_stock_unit's own input -- design decision 7, never called from any production path in this checkpoint. */
export const ReserveLoyaltyRewardStockUnitInputSchema = z.object({
  tenantId: z.string().uuid(),
  rewardId: z.string().uuid(),
  quantity: z.number().int().positive(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reason: z.string().nullable().default(null),
});
export type ReserveLoyaltyRewardStockUnitInput = z.input<typeof ReserveLoyaltyRewardStockUnitInputSchema>;

// ===========================================================================
// Cursor pagination
// ===========================================================================

export const LoyaltyRewardUpdatedAtCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type LoyaltyRewardUpdatedAtCursor = z.input<typeof LoyaltyRewardUpdatedAtCursorSchema>;

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A) -- never carries
// internalCost/vendorRef (structural, design decision 8).
// ===========================================================================

export const CustomerPortalLoyaltyRewardSchema = z.object({
  rewardId: z.string().uuid(),
  programId: z.string().uuid(),
  programName: z.string(),
  rewardName: z.string(),
  rewardType: LoyaltyRewardTypeSchema,
  description: z.string().nullable(),
  displayState: CustomerPortalLoyaltyRewardDisplayStateSchema,
  minTierName: z.string().nullable(),
  minPointsRequired: z.number().nullable(),
  customerCurrentPoints: z.number(),
  totalStock: z.number().int().nullable(),
  stockAvailable: z.number().int().nullable(),
  effectiveFrom: z.string().nullable(),
  updatedAt: z.string(),
});
export type CustomerPortalLoyaltyReward = z.infer<typeof CustomerPortalLoyaltyRewardSchema>;

export function parseCustomerPortalLoyaltyReward(row: Record<string, unknown>): CustomerPortalLoyaltyReward {
  return CustomerPortalLoyaltyRewardSchema.parse({
    rewardId: row.reward_id,
    programId: row.program_id,
    programName: row.program_name,
    rewardName: row.reward_name,
    rewardType: row.reward_type,
    description: (row.description as string | null) ?? null,
    displayState: row.display_state,
    minTierName: (row.min_tier_name as string | null) ?? null,
    minPointsRequired: coerceNullableNumber(row.min_points_required),
    customerCurrentPoints: coerceNumber(row.customer_current_points),
    totalStock: (row.total_stock as number | null) ?? null,
    stockAvailable: (row.stock_available as number | null) ?? null,
    effectiveFrom: (row.effective_from as string | null) ?? null,
    updatedAt: row.updated_at,
  });
}

/** app.get_customer_portal_loyalty_reward's own richer detail row -- adds termsText and the malware-scan-gated terms file reference (design decision 9). */
export const CustomerPortalLoyaltyRewardDetailSchema = CustomerPortalLoyaltyRewardSchema.omit({ updatedAt: true }).extend({
  termsText: z.string().nullable(),
  hasTermsFile: z.boolean(),
  termsFileScanStatus: z.string().nullable(),
  termsFileName: z.string().nullable(),
  termsFileMimeType: z.string().nullable(),
  termsFileSizeBytes: z.number().nullable(),
  updatedAt: z.string(),
});
export type CustomerPortalLoyaltyRewardDetail = z.infer<typeof CustomerPortalLoyaltyRewardDetailSchema>;

export function parseCustomerPortalLoyaltyRewardDetail(row: Record<string, unknown>): CustomerPortalLoyaltyRewardDetail {
  return CustomerPortalLoyaltyRewardDetailSchema.parse({
    rewardId: row.reward_id,
    programId: row.program_id,
    programName: row.program_name,
    rewardName: row.reward_name,
    rewardType: row.reward_type,
    description: (row.description as string | null) ?? null,
    termsText: (row.terms_text as string | null) ?? null,
    displayState: row.display_state,
    minTierName: (row.min_tier_name as string | null) ?? null,
    minPointsRequired: coerceNullableNumber(row.min_points_required),
    customerCurrentPoints: coerceNumber(row.customer_current_points),
    totalStock: (row.total_stock as number | null) ?? null,
    stockAvailable: (row.stock_available as number | null) ?? null,
    effectiveFrom: (row.effective_from as string | null) ?? null,
    hasTermsFile: row.has_terms_file,
    termsFileScanStatus: (row.terms_file_scan_status as string | null) ?? null,
    termsFileName: (row.terms_file_name as string | null) ?? null,
    termsFileMimeType: (row.terms_file_mime_type as string | null) ?? null,
    termsFileSizeBytes: (row.terms_file_size_bytes as number | null) ?? null,
    updatedAt: row.updated_at,
  });
}

/** Customer-safe, plain-language rendering of a reward's own eligibility gate -- never raw internal config. */
export function describeLoyaltyRewardEligibility(reward: Pick<CustomerPortalLoyaltyReward, "displayState" | "minTierName" | "minPointsRequired" | "customerCurrentPoints">): string {
  if (reward.displayState === "unavailable") {
    return "This reward is temporarily unavailable.";
  }
  if (reward.displayState === "out_of_stock") {
    return "This reward is currently out of stock.";
  }
  if (reward.displayState === "locked") {
    const parts: string[] = [];
    if (reward.minTierName) parts.push(`the ${reward.minTierName} tier`);
    if (reward.minPointsRequired !== null) parts.push(`${reward.minPointsRequired} points (you have ${reward.customerCurrentPoints})`);
    return parts.length > 0 ? `Requires ${parts.join(" and ")}.` : "You are not yet eligible for this reward.";
  }
  return "You can redeem this reward.";
}
