/**
 * Sourcing contract (PRC-256, CG-S11-PRC-007). Mirrors
 * supabase/migrations/20260730630000_create_procurement_sourcing.sql -- Zod
 * schemas + parse functions for the three new entities (SourcingRequest,
 * SourcingRequestEvent, SourcingCandidate) plus one *InputSchema per mutation
 * (camelCase field names, actorAuthUserId/actorLabel/expectedVersion/
 * idempotencyKey included where the corresponding RPC needs them), the same
 * shape server/contracts/procurement-rate/procurement-rate.ts already
 * establishes for this checkpoint's own template.
 *
 * SourcingRequest's costMasked/budgetAmount fields are populated from EITHER
 * app.sourcing_requests (base table -- every write RPC returns this shape,
 * budget_amount always present/unmasked, cost_masked absent) OR
 * app.sourcing_requests_directory (masked read RPC shape, both present) --
 * parseSourcingRequest normalizes both into the same camelCase contract,
 * defaulting costMasked to false when the row carries no such column (a write
 * RPC's own base-table return is never masked from the actor who just
 * performed the write).
 */

import { z } from "zod";

export const SOURCING_REQUEST_SOURCE_TYPES = ["costing_request", "operational_demand", "proactive"] as const;
export const SourcingRequestSourceTypeSchema = z.enum(SOURCING_REQUEST_SOURCE_TYPES);
export type SourcingRequestSourceType = z.infer<typeof SourcingRequestSourceTypeSchema>;

export const SOURCING_REQUEST_STATUSES = ["draft", "open", "shortlisted", "closed_no_source", "cancelled"] as const;
export const SourcingRequestStatusSchema = z.enum(SOURCING_REQUEST_STATUSES);
export type SourcingRequestStatus = z.infer<typeof SourcingRequestStatusSchema>;

export const SOURCING_CANDIDATE_EXCLUSION_REASONS = ["vendor_not_active", "service_mismatch", "coverage_mismatch", "compliance_ineligible"] as const;
export const SourcingCandidateExclusionReasonSchema = z.enum(SOURCING_CANDIDATE_EXCLUSION_REASONS);
export type SourcingCandidateExclusionReason = z.infer<typeof SourcingCandidateExclusionReasonSchema>;

export const SourcingRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  sourceType: SourcingRequestSourceTypeSchema,
  sourceCostingRequestId: z.string().uuid().nullable(),
  sourceShipmentOrderId: z.string().uuid().nullable(),
  demandSnapshot: z.record(z.string(), z.unknown()),
  serviceType: z.string(),
  mode: z.string().nullable(),
  originLane: z.string(),
  destinationLane: z.string(),
  cargoWeightMin: z.coerce.number().nullable(),
  cargoWeightMax: z.coerce.number().nullable(),
  cargoVolumeMin: z.coerce.number().nullable(),
  cargoVolumeMax: z.coerce.number().nullable(),
  requestedPickupAt: z.string().nullable(),
  requestedDeliveryAt: z.string().nullable(),
  currency: z.string().nullable(),
  budgetAmount: z.coerce.number().nullable(),
  costMasked: z.boolean(),
  status: SourcingRequestStatusSchema,
  ownerUserId: z.string().uuid().nullable(),
  slaDueAt: z.string().nullable(),
  closedReason: z.string().nullable(),
  shortlistLockedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type SourcingRequest = z.infer<typeof SourcingRequestSchema>;

export function parseSourcingRequest(row: Record<string, unknown>): SourcingRequest {
  return SourcingRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    orgUnitId: row.org_unit_id,
    sourceType: row.source_type,
    sourceCostingRequestId: row.source_costing_request_id,
    sourceShipmentOrderId: row.source_shipment_order_id,
    demandSnapshot: row.demand_snapshot ?? {},
    serviceType: row.service_type,
    mode: row.mode,
    originLane: row.origin_lane,
    destinationLane: row.destination_lane,
    cargoWeightMin: row.cargo_weight_min,
    cargoWeightMax: row.cargo_weight_max,
    cargoVolumeMin: row.cargo_volume_min,
    cargoVolumeMax: row.cargo_volume_max,
    requestedPickupAt: row.requested_pickup_at,
    requestedDeliveryAt: row.requested_delivery_at,
    currency: row.currency,
    budgetAmount: row.budget_amount,
    costMasked: Boolean(row.cost_masked),
    status: row.status,
    ownerUserId: row.owner_user_id,
    slaDueAt: row.sla_due_at,
    closedReason: row.closed_reason,
    shortlistLockedAt: row.shortlist_locked_at,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const SourcingRequestEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  sourcingRequestId: z.string().uuid(),
  fromStatus: z.string(),
  toStatus: z.string(),
  reason: z.string().nullable(),
  evidenceRef: z.string().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type SourcingRequestEvent = z.infer<typeof SourcingRequestEventSchema>;

export function parseSourcingRequestEvent(row: Record<string, unknown>): SourcingRequestEvent {
  return SourcingRequestEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    sourcingRequestId: row.sourcing_request_id,
    fromStatus: row.from_status,
    toStatus: row.to_status,
    reason: row.reason,
    evidenceRef: row.evidence_ref,
    actorAuthUserId: row.actor_auth_user_id,
    actorLabel: row.actor_label,
    occurredAt: row.occurred_at,
  });
}

export const SourcingCandidateSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  sourcingRequestId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  eligible: z.boolean(),
  exclusionReasons: z.array(z.string()),
  evaluationSnapshot: z.record(z.string(), z.unknown()),
  shortlisted: z.boolean(),
  shortlistReason: z.string().nullable(),
  shortlistedBy: z.string().nullable(),
  shortlistedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type SourcingCandidate = z.infer<typeof SourcingCandidateSchema>;

export function parseSourcingCandidate(row: Record<string, unknown>): SourcingCandidate {
  return SourcingCandidateSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    sourcingRequestId: row.sourcing_request_id,
    vendorMasterId: row.vendor_master_id,
    eligible: row.eligible,
    exclusionReasons: row.exclusion_reasons ?? [],
    evaluationSnapshot: row.evaluation_snapshot ?? {},
    shortlisted: row.shortlisted,
    shortlistReason: row.shortlist_reason,
    shortlistedBy: row.shortlisted_by,
    shortlistedAt: row.shortlisted_at,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

// -- Mutation inputs -------------------------------------------------------

export const CreateSourcingRequestFromCostingInputSchema = z.object({
  tenantId: z.string().uuid(),
  costingRequestId: z.string().uuid(),
  ownerUserId: z.string().uuid().nullable().default(null),
  slaDueAt: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateSourcingRequestFromCostingInput = z.input<typeof CreateSourcingRequestFromCostingInputSchema>;

export const CreateSourcingRequestFromOperationalDemandInputSchema = z.object({
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  ownerUserId: z.string().uuid().nullable().default(null),
  slaDueAt: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateSourcingRequestFromOperationalDemandInput = z.input<typeof CreateSourcingRequestFromOperationalDemandInputSchema>;

export const CreateProactiveSourcingRequestInputSchema = z.object({
  tenantId: z.string().uuid(),
  serviceType: z.string().min(1),
  mode: z.string().nullable().default(null),
  originLane: z.string().min(1),
  destinationLane: z.string().min(1),
  cargoWeightMin: z.number().nonnegative().nullable().default(null),
  cargoWeightMax: z.number().nonnegative().nullable().default(null),
  cargoVolumeMin: z.number().nonnegative().nullable().default(null),
  cargoVolumeMax: z.number().nonnegative().nullable().default(null),
  requestedPickupAt: z.string().nullable().default(null),
  requestedDeliveryAt: z.string().nullable().default(null),
  currency: z.string().nullable().default(null),
  budgetAmount: z.number().nonnegative().nullable().default(null),
  ownerUserId: z.string().uuid().nullable().default(null),
  slaDueAt: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateProactiveSourcingRequestInput = z.input<typeof CreateProactiveSourcingRequestInputSchema>;

export const SubmitSourcingRequestInputSchema = z.object({
  sourcingRequestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitSourcingRequestInput = z.input<typeof SubmitSourcingRequestInputSchema>;

export const OverrideSourcingRequestConstraintsInputSchema = z.object({
  sourcingRequestId: z.string().uuid(),
  cargoWeightMax: z.number().nonnegative().nullable().default(null),
  cargoVolumeMax: z.number().nonnegative().nullable().default(null),
  destinationLane: z.string().nullable().default(null),
  reason: z.string().min(1),
  overrideExpiresAt: z.string().nullable().default(null),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type OverrideSourcingRequestConstraintsInput = z.input<typeof OverrideSourcingRequestConstraintsInputSchema>;

export const EvaluateSourcingCandidateEligibilityInputSchema = z.object({
  sourcingRequestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type EvaluateSourcingCandidateEligibilityInput = z.input<typeof EvaluateSourcingCandidateEligibilityInputSchema>;

export const ShortlistSourcingCandidateInputSchema = z.object({
  candidateId: z.string().uuid(),
  shortlisted: z.boolean(),
  reason: z.string().nullable().default(null),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ShortlistSourcingCandidateInput = z.input<typeof ShortlistSourcingCandidateInputSchema>;

export const SubmitSourcingShortlistInputSchema = z.object({
  sourcingRequestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitSourcingShortlistInput = z.input<typeof SubmitSourcingShortlistInputSchema>;

export const CloseSourcingRequestNoSourceInputSchema = z.object({
  sourcingRequestId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CloseSourcingRequestNoSourceInput = z.input<typeof CloseSourcingRequestNoSourceInputSchema>;

export const CancelSourcingRequestInputSchema = z.object({
  sourcingRequestId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelSourcingRequestInput = z.input<typeof CancelSourcingRequestInputSchema>;

export const ReopenSourcingRequestInputSchema = z.object({
  sourcingRequestId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReopenSourcingRequestInput = z.input<typeof ReopenSourcingRequestInputSchema>;
