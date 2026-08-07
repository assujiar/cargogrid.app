/**
 * Vendor Comparison contract (PRC-258, CG-S11-PRC-009). Mirrors
 * supabase/migrations/20260730650000_create_procurement_vendor_comparison.sql
 * -- Zod schemas + parse functions for every entity (VendorComparison,
 * VendorComparisonOffer, VendorComparisonOfferScore, VendorComparisonEvent)
 * plus one *InputSchema per mutation (camelCase field names,
 * actorAuthUserId/actorLabel/expectedVersion/idempotencyKey included where
 * the corresponding RPC needs them), the same shape
 * server/contracts/rfq/rfq.ts already establishes for this checkpoint's own
 * template.
 *
 * The whole capability gates on PRC:View cost alone (migration design
 * note 8, mirroring app.calculate_vendor_rate's own ADR-0020 directed
 * reuse) -- there is no masked/unmasked shape to reconcile the way
 * rfq.ts's RfqResponseSchema has to (costMasked).
 */

import { z } from "zod";

export const VENDOR_COMPARISON_STATUSES = ["draft", "recommended", "submitted", "cancelled", "superseded"] as const;
export const VendorComparisonStatusSchema = z.enum(VENDOR_COMPARISON_STATUSES);
export type VendorComparisonStatus = z.infer<typeof VendorComparisonStatusSchema>;

export const ComparisonCriterionSchema = z.object({
  key: z.string().min(1),
  label: z.string().min(1),
  weight: z.number().min(0).max(100),
});
export type ComparisonCriterion = z.infer<typeof ComparisonCriterionSchema>;

export const VendorComparisonSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  rfqId: z.string().uuid(),
  sourcingRequestId: z.string().uuid(),
  version: z.number().int().positive(),
  revisedFromId: z.string().uuid().nullable(),
  comparisonCurrency: z.string(),
  basisWeight: z.coerce.number().nullable(),
  basisVolume: z.coerce.number().nullable(),
  basisQuantity: z.coerce.number().nullable(),
  criteriaSnapshot: z.array(ComparisonCriterionSchema),
  status: VendorComparisonStatusSchema,
  recommendedOfferId: z.string().uuid().nullable(),
  recommendedReason: z.string().nullable(),
  recommendedAt: z.string().nullable(),
  selectedOfferId: z.string().uuid().nullable(),
  selectionReason: z.string().nullable(),
  submittedAt: z.string().nullable(),
  submittedBy: z.string().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorComparison = z.infer<typeof VendorComparisonSchema>;

export function parseVendorComparison(row: Record<string, unknown>): VendorComparison {
  return VendorComparisonSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    orgUnitId: row.org_unit_id,
    rfqId: row.rfq_id,
    sourcingRequestId: row.sourcing_request_id,
    version: row.version,
    revisedFromId: row.revised_from_id,
    comparisonCurrency: row.comparison_currency,
    basisWeight: row.basis_weight,
    basisVolume: row.basis_volume,
    basisQuantity: row.basis_quantity,
    criteriaSnapshot: row.criteria_snapshot ?? [],
    status: row.status,
    recommendedOfferId: row.recommended_offer_id,
    recommendedReason: row.recommended_reason,
    recommendedAt: row.recommended_at,
    selectedOfferId: row.selected_offer_id,
    selectionReason: row.selection_reason,
    submittedAt: row.submitted_at,
    submittedBy: row.submitted_by,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorComparisonOfferSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  comparisonId: z.string().uuid(),
  rfqResponseId: z.string().uuid(),
  rfqInvitationId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  rateVersionId: z.string().uuid().nullable(),
  sourceCurrency: z.string(),
  sourceTotalAmount: z.coerce.number(),
  engineComputedAmount: z.coerce.number().nullable(),
  engineCurrency: z.string().nullable(),
  engineBreakdown: z.record(z.string(), z.unknown()).nullable(),
  normalizedAmount: z.coerce.number().nullable(),
  normalizationLineage: z.record(z.string(), z.unknown()),
  included: z.boolean(),
  exclusionReason: z.string().nullable(),
  priceScore: z.coerce.number().nullable(),
  nonPriceScore: z.coerce.number().nullable(),
  compositeScore: z.coerce.number().nullable(),
  rank: z.number().int().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorComparisonOffer = z.infer<typeof VendorComparisonOfferSchema>;

export function parseVendorComparisonOffer(row: Record<string, unknown>): VendorComparisonOffer {
  return VendorComparisonOfferSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    comparisonId: row.comparison_id,
    rfqResponseId: row.rfq_response_id,
    rfqInvitationId: row.rfq_invitation_id,
    vendorMasterId: row.vendor_master_id,
    rateVersionId: row.rate_version_id,
    sourceCurrency: row.source_currency,
    sourceTotalAmount: row.source_total_amount,
    engineComputedAmount: row.engine_computed_amount,
    engineCurrency: row.engine_currency,
    engineBreakdown: row.engine_breakdown ?? null,
    normalizedAmount: row.normalized_amount,
    normalizationLineage: row.normalization_lineage ?? {},
    included: row.included,
    exclusionReason: row.exclusion_reason,
    priceScore: row.price_score,
    nonPriceScore: row.non_price_score,
    compositeScore: row.composite_score,
    rank: row.rank,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorComparisonOfferScoreSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  comparisonOfferId: z.string().uuid(),
  criterionKey: z.string(),
  criterionWeight: z.coerce.number(),
  score: z.coerce.number(),
  notes: z.string().nullable(),
  scoredBy: z.string().nullable(),
  scoredAt: z.string(),
});
export type VendorComparisonOfferScore = z.infer<typeof VendorComparisonOfferScoreSchema>;

export function parseVendorComparisonOfferScore(row: Record<string, unknown>): VendorComparisonOfferScore {
  return VendorComparisonOfferScoreSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    comparisonOfferId: row.comparison_offer_id,
    criterionKey: row.criterion_key,
    criterionWeight: row.criterion_weight,
    score: row.score,
    notes: row.notes,
    scoredBy: row.scored_by,
    scoredAt: row.scored_at,
  });
}

export const VendorComparisonEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  comparisonId: z.string().uuid(),
  fromStatus: z.string(),
  toStatus: z.string(),
  reason: z.string().nullable(),
  evidenceRef: z.string().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type VendorComparisonEvent = z.infer<typeof VendorComparisonEventSchema>;

export function parseVendorComparisonEvent(row: Record<string, unknown>): VendorComparisonEvent {
  return VendorComparisonEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    comparisonId: row.comparison_id,
    fromStatus: row.from_status,
    toStatus: row.to_status,
    reason: row.reason,
    evidenceRef: row.evidence_ref,
    actorAuthUserId: row.actor_auth_user_id,
    actorLabel: row.actor_label,
    occurredAt: row.occurred_at,
  });
}

// -- Mutation inputs -------------------------------------------------------

export const CreateVendorComparisonInputSchema = z.object({
  tenantId: z.string().uuid(),
  rfqId: z.string().uuid(),
  comparisonCurrency: z.string().min(1),
  basisWeight: z.number().nonnegative().nullable().default(null),
  basisVolume: z.number().nonnegative().nullable().default(null),
  basisQuantity: z.number().nonnegative().nullable().default(null),
  criteria: z.array(ComparisonCriterionSchema).nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateVendorComparisonInput = z.input<typeof CreateVendorComparisonInputSchema>;

export const ReviseVendorComparisonInputSchema = z.object({
  comparisonId: z.string().uuid(),
  comparisonCurrency: z.string().nullable().default(null),
  basisWeight: z.number().nonnegative().nullable().default(null),
  basisVolume: z.number().nonnegative().nullable().default(null),
  basisQuantity: z.number().nonnegative().nullable().default(null),
  criteria: z.array(ComparisonCriterionSchema).nullable().default(null),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReviseVendorComparisonInput = z.input<typeof ReviseVendorComparisonInputSchema>;

export const LinkVendorComparisonOfferRateInputSchema = z.object({
  comparisonOfferId: z.string().uuid(),
  rateVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type LinkVendorComparisonOfferRateInput = z.input<typeof LinkVendorComparisonOfferRateInputSchema>;

export const SetVendorComparisonOfferInclusionInputSchema = z.object({
  comparisonOfferId: z.string().uuid(),
  included: z.boolean(),
  reason: z.string().nullable().default(null),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetVendorComparisonOfferInclusionInput = z.input<typeof SetVendorComparisonOfferInclusionInputSchema>;

export const ScoreVendorComparisonOfferCriterionInputSchema = z.object({
  comparisonOfferId: z.string().uuid(),
  criterionKey: z.string().min(1),
  score: z.number().min(0).max(100),
  notes: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ScoreVendorComparisonOfferCriterionInput = z.input<typeof ScoreVendorComparisonOfferCriterionInputSchema>;

export const RecommendVendorComparisonOfferInputSchema = z.object({
  comparisonId: z.string().uuid(),
  comparisonOfferId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecommendVendorComparisonOfferInput = z.input<typeof RecommendVendorComparisonOfferInputSchema>;

export const SubmitVendorComparisonForApprovalInputSchema = z.object({
  comparisonId: z.string().uuid(),
  selectedOfferId: z.string().uuid(),
  selectionReason: z.string().nullable().default(null),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitVendorComparisonForApprovalInput = z.input<typeof SubmitVendorComparisonForApprovalInputSchema>;

export const CancelVendorComparisonInputSchema = z.object({
  comparisonId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelVendorComparisonInput = z.input<typeof CancelVendorComparisonInputSchema>;
