/**
 * Vendor Capacity and Availability contract (PRC-262, CG-S11-PRC-013). Mirrors
 * supabase/migrations/20260730710000_create_procurement_vendor_capacity.sql -- Zod
 * schemas + parse functions for VendorCapacityOffer, VendorCapacityBlackout and
 * VendorCapacityReservation, plus one *InputSchema per mutation, the same shape
 * server/contracts/vendor-contract/vendor-contract.ts already establishes for this
 * checkpoint's own template. No cost masking in this capability (migration design
 * note 7 -- nothing here is commercial/cost-shaped).
 */

import { z } from "zod";

export const VENDOR_CAPACITY_OFFER_STATUSES = ["draft", "published", "archived"] as const;
export const VendorCapacityOfferStatusSchema = z.enum(VENDOR_CAPACITY_OFFER_STATUSES);
export type VendorCapacityOfferStatus = z.infer<typeof VendorCapacityOfferStatusSchema>;

export const VENDOR_CAPACITY_RESOURCE_TYPES = ["vehicle", "warehouse", "driver", "general"] as const;
export const VendorCapacityResourceTypeSchema = z.enum(VENDOR_CAPACITY_RESOURCE_TYPES);
export type VendorCapacityResourceType = z.infer<typeof VendorCapacityResourceTypeSchema>;

export const VENDOR_CAPACITY_RESERVATION_STATUSES = ["held", "accepted", "declined", "consumed", "released"] as const;
export const VendorCapacityReservationStatusSchema = z.enum(VENDOR_CAPACITY_RESERVATION_STATUSES);
export type VendorCapacityReservationStatus = z.infer<typeof VendorCapacityReservationStatusSchema>;

export const VendorCapacityOfferSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  contractId: z.string().uuid().nullable(),
  serviceType: z.string(),
  mode: z.string().nullable(),
  originLane: z.string().nullable(),
  destinationLane: z.string().nullable(),
  resourceType: VendorCapacityResourceTypeSchema,
  resourceMasterId: z.string().uuid().nullable(),
  quantity: z.coerce.number(),
  uom: z.string(),
  windowStart: z.string(),
  windowEnd: z.string(),
  status: VendorCapacityOfferStatusSchema,
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorCapacityOffer = z.infer<typeof VendorCapacityOfferSchema>;

export function parseVendorCapacityOffer(row: Record<string, unknown>): VendorCapacityOffer {
  return VendorCapacityOfferSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterId: row.vendor_master_id,
    contractId: row.contract_id,
    serviceType: row.service_type,
    mode: row.mode,
    originLane: row.origin_lane,
    destinationLane: row.destination_lane,
    resourceType: row.resource_type,
    resourceMasterId: row.resource_master_id,
    quantity: row.quantity,
    uom: row.uom,
    windowStart: row.window_start,
    windowEnd: row.window_end,
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorCapacityBlackoutSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  offerId: z.string().uuid(),
  windowStart: z.string(),
  windowEnd: z.string(),
  reason: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type VendorCapacityBlackout = z.infer<typeof VendorCapacityBlackoutSchema>;

export function parseVendorCapacityBlackout(row: Record<string, unknown>): VendorCapacityBlackout {
  return VendorCapacityBlackoutSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    offerId: row.offer_id,
    windowStart: row.window_start,
    windowEnd: row.window_end,
    reason: row.reason,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
  });
}

export const VendorCapacityReservationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  offerId: z.string().uuid(),
  requestedQuantity: z.coerce.number(),
  windowStart: z.string(),
  windowEnd: z.string(),
  status: VendorCapacityReservationStatusSchema,
  sourceReferenceType: z.string().nullable(),
  sourceReferenceId: z.string().uuid().nullable(),
  declineReason: z.string().nullable(),
  releasedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorCapacityReservation = z.infer<typeof VendorCapacityReservationSchema>;

export function parseVendorCapacityReservation(row: Record<string, unknown>): VendorCapacityReservation {
  return VendorCapacityReservationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    offerId: row.offer_id,
    requestedQuantity: row.requested_quantity,
    windowStart: row.window_start,
    windowEnd: row.window_end,
    status: row.status,
    sourceReferenceType: row.source_reference_type,
    sourceReferenceId: row.source_reference_id,
    declineReason: row.decline_reason,
    releasedReason: row.released_reason,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

// -- Mutation inputs -------------------------------------------------------

export const CreateVendorCapacityOfferDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  contractId: z.string().uuid().nullable().default(null),
  serviceType: z.string().min(1),
  mode: z.string().nullable().default(null),
  originLane: z.string().nullable().default(null),
  destinationLane: z.string().nullable().default(null),
  resourceType: VendorCapacityResourceTypeSchema.default("general"),
  resourceMasterId: z.string().uuid().nullable().default(null),
  quantity: z.coerce.number().positive(),
  uom: z.string().min(1),
  windowStart: z.string().min(1),
  windowEnd: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateVendorCapacityOfferDraftInput = z.input<typeof CreateVendorCapacityOfferDraftInputSchema>;

// contractId/mode/originLane/destinationLane/resourceMasterId are preserve-by-null
// (the RPC's own coalesce shape, PRC-261's own Tier B lesson applied from the start);
// quantity/uom/window are always-required direct assignment.
export const UpdateVendorCapacityOfferDraftInputSchema = z.object({
  offerId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  contractId: z.string().uuid().nullable().default(null),
  mode: z.string().nullable().default(null),
  originLane: z.string().nullable().default(null),
  destinationLane: z.string().nullable().default(null),
  resourceMasterId: z.string().uuid().nullable().default(null),
  quantity: z.coerce.number().positive(),
  uom: z.string().min(1),
  windowStart: z.string().min(1),
  windowEnd: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateVendorCapacityOfferDraftInput = z.input<typeof UpdateVendorCapacityOfferDraftInputSchema>;

export const PublishVendorCapacityOfferInputSchema = z.object({
  offerId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishVendorCapacityOfferInput = z.input<typeof PublishVendorCapacityOfferInputSchema>;

export const ArchiveVendorCapacityOfferInputSchema = z.object({
  offerId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ArchiveVendorCapacityOfferInput = z.input<typeof ArchiveVendorCapacityOfferInputSchema>;

export const AddVendorCapacityBlackoutInputSchema = z.object({
  offerId: z.string().uuid(),
  windowStart: z.string().min(1),
  windowEnd: z.string().min(1),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AddVendorCapacityBlackoutInput = z.input<typeof AddVendorCapacityBlackoutInputSchema>;

export const RemoveVendorCapacityBlackoutInputSchema = z.object({
  blackoutId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RemoveVendorCapacityBlackoutInput = z.input<typeof RemoveVendorCapacityBlackoutInputSchema>;

export const ReserveVendorCapacityInputSchema = z.object({
  offerId: z.string().uuid(),
  requestedQuantity: z.coerce.number().positive(),
  windowStart: z.string().min(1),
  windowEnd: z.string().min(1),
  sourceReferenceType: z.enum(["sourcing_request", "assignment", "manual"]).nullable().default(null),
  sourceReferenceId: z.string().uuid().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReserveVendorCapacityInput = z.input<typeof ReserveVendorCapacityInputSchema>;

export const AcceptVendorCapacityReservationInputSchema = z.object({
  reservationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AcceptVendorCapacityReservationInput = z.input<typeof AcceptVendorCapacityReservationInputSchema>;

export const DeclineVendorCapacityReservationInputSchema = z.object({
  reservationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DeclineVendorCapacityReservationInput = z.input<typeof DeclineVendorCapacityReservationInputSchema>;

export const ReleaseVendorCapacityReservationInputSchema = z.object({
  reservationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReleaseVendorCapacityReservationInput = z.input<typeof ReleaseVendorCapacityReservationInputSchema>;

export const ConsumeVendorCapacityReservationInputSchema = z.object({
  reservationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ConsumeVendorCapacityReservationInput = z.input<typeof ConsumeVendorCapacityReservationInputSchema>;
