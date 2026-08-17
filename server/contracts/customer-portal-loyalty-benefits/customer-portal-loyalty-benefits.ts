/**
 * Cashback, Discount and Voucher contract (CPL-319, CG-S13-CPL-021). Mirrors
 * supabase/migrations/20260801210000_create_customer_portal_cashback_
 * discount_voucher.sql's own two RPC surfaces: (a) tenant-internal,
 * staff-gated (LYL:*) entitlement issuance/reversal/expiry/hold/release and
 * reads; and (b) the dual-authority redemption RPC plus customer-facing
 * (Layer 4) reads of a customer's own benefit wallet.
 *
 * The FOURTH Loyalty-domain contract in this repository (ADR-0024 Part D).
 * Depends on server/contracts/customer-portal-loyalty-program/ (CPL-316) for
 * LoyaltyAccount-shaped context where useful, but does not re-export it --
 * callers that need both import each contract directly.
 */

import { z } from "zod";

// ===========================================================================
// Shared enums
// ===========================================================================

export const LOYALTY_BENEFIT_TYPES = ["cashback", "discount", "voucher"] as const;
export const LoyaltyBenefitTypeSchema = z.enum(LOYALTY_BENEFIT_TYPES);
export type LoyaltyBenefitType = z.infer<typeof LoyaltyBenefitTypeSchema>;

export const LOYALTY_BENEFIT_STATUSES = ["issued", "redeemed", "reversed", "expired", "held"] as const;
export const LoyaltyBenefitStatusSchema = z.enum(LOYALTY_BENEFIT_STATUSES);
export type LoyaltyBenefitStatus = z.infer<typeof LoyaltyBenefitStatusSchema>;

export const LOYALTY_BENEFIT_EVENT_TYPES = ["issued", "redeemed", "reversed", "expired", "held", "released"] as const;
export const LoyaltyBenefitEventTypeSchema = z.enum(LOYALTY_BENEFIT_EVENT_TYPES);
export type LoyaltyBenefitEventType = z.infer<typeof LoyaltyBenefitEventTypeSchema>;

function coerceNumber(value: unknown): number {
  return typeof value === "string" ? Number(value) : (value as number);
}
function coerceNullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : coerceNumber(value);
}

// ===========================================================================
// Staff-facing: app.loyalty_benefit_entitlements (full internal projection)
// ===========================================================================

export const LoyaltyBenefitEntitlementSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  benefitType: LoyaltyBenefitTypeSchema,
  valueAmount: z.number(),
  valueCap: z.number().nullable(),
  currency: z.string(),
  status: LoyaltyBenefitStatusSchema,
  codeHash: z.string().nullable(),
  sourceType: z.string(),
  sourceId: z.string().uuid().nullable(),
  expiresAt: z.string().nullable(),
  configVersion: z.number().int().positive(),
  idempotencyKey: z.string(),
  isFraudHold: z.boolean(),
  holdReason: z.string().nullable(),
  heldBy: z.string().nullable(),
  heldAt: z.string().nullable(),
  releasedBy: z.string().nullable(),
  releasedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LoyaltyBenefitEntitlement = z.infer<typeof LoyaltyBenefitEntitlementSchema>;

export function parseLoyaltyBenefitEntitlement(row: Record<string, unknown>): LoyaltyBenefitEntitlement {
  return LoyaltyBenefitEntitlementSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    loyaltyAccountId: row.loyalty_account_id,
    benefitType: row.benefit_type,
    valueAmount: coerceNumber(row.value_amount),
    valueCap: coerceNullableNumber(row.value_cap),
    currency: row.currency,
    status: row.status,
    codeHash: (row.code_hash as string | null) ?? null,
    sourceType: row.source_type,
    sourceId: (row.source_id as string | null) ?? null,
    expiresAt: (row.expires_at as string | null) ?? null,
    configVersion: row.config_version,
    idempotencyKey: row.idempotency_key,
    isFraudHold: row.is_fraud_hold,
    holdReason: (row.hold_reason as string | null) ?? null,
    heldBy: (row.held_by as string | null) ?? null,
    heldAt: (row.held_at as string | null) ?? null,
    releasedBy: (row.released_by as string | null) ?? null,
    releasedAt: (row.released_at as string | null) ?? null,
    recordVersion: row.record_version,
    createdBy: (row.created_by as string | null) ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.issue_loyalty_benefit_entitlement's own return row -- the entitlement's own columns plus raw_code, which is null on every idempotent replay (design decision 2/6 -- never recoverable after the first, real issuance). */
export const IssueLoyaltyBenefitEntitlementResultSchema = LoyaltyBenefitEntitlementSchema.extend({
  rawCode: z.string().nullable(),
});
export type IssueLoyaltyBenefitEntitlementResult = z.infer<typeof IssueLoyaltyBenefitEntitlementResultSchema>;

export function parseIssueLoyaltyBenefitEntitlementResult(row: Record<string, unknown>): IssueLoyaltyBenefitEntitlementResult {
  return IssueLoyaltyBenefitEntitlementResultSchema.parse({
    ...parseLoyaltyBenefitEntitlement(row),
    rawCode: (row.raw_code as string | null) ?? null,
  });
}

// ===========================================================================
// Staff-facing: app.loyalty_benefit_entitlement_events (append-only)
// ===========================================================================

export const LoyaltyBenefitEntitlementEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  entitlementId: z.string().uuid(),
  eventType: LoyaltyBenefitEventTypeSchema,
  amount: z.number().nullable(),
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  createdAt: z.string(),
});
export type LoyaltyBenefitEntitlementEvent = z.infer<typeof LoyaltyBenefitEntitlementEventSchema>;

export function parseLoyaltyBenefitEntitlementEvent(row: Record<string, unknown>): LoyaltyBenefitEntitlementEvent {
  return LoyaltyBenefitEntitlementEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    entitlementId: row.entitlement_id,
    eventType: row.event_type,
    amount: coerceNullableNumber(row.amount),
    reason: (row.reason as string | null) ?? null,
    actorAuthUserId: (row.actor_auth_user_id as string | null) ?? null,
    actorLabel: (row.actor_label as string | null) ?? null,
    createdAt: row.created_at,
  });
}

// ===========================================================================
// Mutation inputs
// ===========================================================================

export const IssueLoyaltyBenefitEntitlementInputSchema = z
  .object({
    tenantId: z.string().uuid(),
    loyaltyAccountId: z.string().uuid(),
    benefitType: LoyaltyBenefitTypeSchema,
    valueAmount: z.number().positive(),
    valueCap: z.number().positive().nullable().default(null),
    currency: z.string().regex(/^[A-Z]{3}$/, "currency must be a 3-letter uppercase ISO code"),
    sourceType: z.string().min(1),
    sourceId: z.string().uuid().nullable().default(null),
    expiresAt: z.string().nullable().default(null),
    idempotencyKey: z.string().min(1),
    actorAuthUserId: z.string().uuid(),
    actorLabel: z.string().min(1),
    configVersion: z.number().int().positive().default(1),
  })
  .refine((v) => v.valueCap === null || v.valueAmount <= v.valueCap, {
    message: "valueAmount must not exceed valueCap",
    path: ["valueAmount"],
  });
export type IssueLoyaltyBenefitEntitlementInput = z.input<typeof IssueLoyaltyBenefitEntitlementInputSchema>;

export const RedeemLoyaltyBenefitEntitlementInputSchema = z.object({
  tenantId: z.string().uuid(),
  entitlementIdOrCode: z.string().min(1),
  expectedVersion: z.number().int().positive().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RedeemLoyaltyBenefitEntitlementInput = z.input<typeof RedeemLoyaltyBenefitEntitlementInputSchema>;

export const ReverseLoyaltyBenefitEntitlementInputSchema = z.object({
  tenantId: z.string().uuid(),
  entitlementId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReverseLoyaltyBenefitEntitlementInput = z.input<typeof ReverseLoyaltyBenefitEntitlementInputSchema>;

export const ExpireLoyaltyBenefitEntitlementsInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ExpireLoyaltyBenefitEntitlementsInput = z.input<typeof ExpireLoyaltyBenefitEntitlementsInputSchema>;

export const HoldLoyaltyBenefitEntitlementInputSchema = z.object({
  tenantId: z.string().uuid(),
  entitlementId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type HoldLoyaltyBenefitEntitlementInput = z.input<typeof HoldLoyaltyBenefitEntitlementInputSchema>;

export const ReleaseLoyaltyBenefitEntitlementHoldInputSchema = z.object({
  tenantId: z.string().uuid(),
  entitlementId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReleaseLoyaltyBenefitEntitlementHoldInput = z.input<typeof ReleaseLoyaltyBenefitEntitlementHoldInputSchema>;

// ===========================================================================
// Cursor pagination
// ===========================================================================

export const LoyaltyBenefitUpdatedAtCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type LoyaltyBenefitUpdatedAtCursor = z.input<typeof LoyaltyBenefitUpdatedAtCursorSchema>;

/** app.loyalty_benefit_entitlement_events has no updated_at column (append-only) -- keyed on created_at instead. */
export const LoyaltyBenefitCreatedAtCursorSchema = z
  .object({
    cursorCreatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorCreatedAt, {
    message: "cursorCreatedAt is required when cursorId is supplied",
    path: ["cursorCreatedAt"],
  });
export type LoyaltyBenefitCreatedAtCursor = z.input<typeof LoyaltyBenefitCreatedAtCursorSchema>;

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A)
// ===========================================================================

/** Never carries code_hash/idempotency_key/source_type/source_id/config_version/the real hold_reason (structural, not merely a UI omission). */
export const CustomerPortalLoyaltyBenefitEntitlementSchema = z.object({
  id: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  programName: z.string(),
  benefitType: LoyaltyBenefitTypeSchema,
  valueAmount: z.number(),
  valueCap: z.number().nullable(),
  currency: z.string(),
  status: LoyaltyBenefitStatusSchema,
  isOnHold: z.boolean(),
  holdNotice: z.string().nullable(),
  expiresAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CustomerPortalLoyaltyBenefitEntitlement = z.infer<typeof CustomerPortalLoyaltyBenefitEntitlementSchema>;

export function parseCustomerPortalLoyaltyBenefitEntitlement(row: Record<string, unknown>): CustomerPortalLoyaltyBenefitEntitlement {
  return CustomerPortalLoyaltyBenefitEntitlementSchema.parse({
    id: row.id,
    loyaltyAccountId: row.loyalty_account_id,
    programName: row.program_name,
    benefitType: row.benefit_type,
    valueAmount: coerceNumber(row.value_amount),
    valueCap: coerceNullableNumber(row.value_cap),
    currency: row.currency,
    status: row.status,
    isOnHold: row.is_on_hold,
    holdNotice: (row.hold_notice as string | null) ?? null,
    expiresAt: (row.expires_at as string | null) ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Customer-safe, plain-language rendering of a benefit's own value/currency -- never raw internal config. */
export function formatLoyaltyBenefitValue(entitlement: Pick<CustomerPortalLoyaltyBenefitEntitlement, "valueAmount" | "currency">): string {
  return `${entitlement.currency} ${entitlement.valueAmount.toFixed(2)}`;
}

/** Customer-safe, plain-language expiry description -- mirrors describeLoyaltyPointExpiry's own shape (CPL-318). */
export function describeLoyaltyBenefitExpiry(entitlement: Pick<CustomerPortalLoyaltyBenefitEntitlement, "expiresAt">): string | null {
  if (!entitlement.expiresAt) return null;
  const days = Math.ceil((new Date(entitlement.expiresAt).getTime() - Date.now()) / (1000 * 60 * 60 * 24));
  if (days < 0) return "Expired";
  if (days === 0) return "Expires today";
  return `Expires in ${days} day${days === 1 ? "" : "s"}`;
}
