/**
 * Vendor Assignment contract (PRC-263, CG-S11-PRC-014). Mirrors supabase/migrations/
 * 20260730720000_create_procurement_vendor_assignment.sql -- Zod schemas + parse
 * functions for VendorAssignmentInvitation, plus one *InputSchema per mutation, the
 * same shape server/contracts/vendor-capacity/vendor-capacity.ts already establishes
 * for this batch's own template.
 */

import { z } from "zod";

export const VENDOR_ASSIGNMENT_INVITATION_STATUSES = ["invited", "accepted", "declined", "expired", "assigned", "cancelled", "superseded"] as const;
export const VendorAssignmentInvitationStatusSchema = z.enum(VENDOR_ASSIGNMENT_INVITATION_STATUSES);
export type VendorAssignmentInvitationStatus = z.infer<typeof VendorAssignmentInvitationStatusSchema>;

export const VendorAssignmentInvitationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  contractId: z.string().uuid().nullable(),
  poId: z.string().uuid().nullable(),
  rateVersionId: z.string().uuid().nullable(),
  capacityReservationId: z.string().uuid().nullable(),
  eligibilitySnapshot: z.record(z.string(), z.unknown()),
  status: VendorAssignmentInvitationStatusSchema,
  responseDeadline: z.string().nullable(),
  declineReason: z.string().nullable(),
  cancelReason: z.string().nullable(),
  isOverride: z.boolean(),
  overrideReason: z.string().nullable(),
  assignmentId: z.string().uuid().nullable(),
  supersededById: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorAssignmentInvitation = z.infer<typeof VendorAssignmentInvitationSchema>;

export function parseVendorAssignmentInvitation(row: Record<string, unknown>): VendorAssignmentInvitation {
  return VendorAssignmentInvitationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    vendorMasterId: row.vendor_master_id,
    contractId: row.contract_id,
    poId: row.po_id,
    rateVersionId: row.rate_version_id,
    capacityReservationId: row.capacity_reservation_id,
    eligibilitySnapshot: row.eligibility_snapshot ?? {},
    status: row.status,
    responseDeadline: row.response_deadline,
    declineReason: row.decline_reason,
    cancelReason: row.cancel_reason,
    isOverride: row.is_override,
    overrideReason: row.override_reason,
    assignmentId: row.assignment_id,
    supersededById: row.superseded_by_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorAssignmentEligibilityPreviewSchema = z.object({
  eligible: z.boolean(),
  reasons: z.array(z.string()),
});
export type VendorAssignmentEligibilityPreview = z.infer<typeof VendorAssignmentEligibilityPreviewSchema>;

// -- Mutation inputs -------------------------------------------------------

export const ProposeVendorAssignmentInvitationInputSchema = z.object({
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  contractId: z.string().uuid().nullable().default(null),
  poId: z.string().uuid().nullable().default(null),
  rateVersionId: z.string().uuid().nullable().default(null),
  capacityReservationId: z.string().uuid().nullable().default(null),
  responseDeadline: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ProposeVendorAssignmentInvitationInput = z.input<typeof ProposeVendorAssignmentInvitationInputSchema>;

export const AcceptVendorAssignmentInvitationInputSchema = z.object({
  invitationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AcceptVendorAssignmentInvitationInput = z.input<typeof AcceptVendorAssignmentInvitationInputSchema>;

export const DeclineVendorAssignmentInvitationInputSchema = z.object({
  invitationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DeclineVendorAssignmentInvitationInput = z.input<typeof DeclineVendorAssignmentInvitationInputSchema>;

export const CancelVendorAssignmentInvitationInputSchema = z.object({
  invitationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelVendorAssignmentInvitationInput = z.input<typeof CancelVendorAssignmentInvitationInputSchema>;

export const ConfirmVendorAssignmentInputSchema = z.object({
  invitationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ConfirmVendorAssignmentInput = z.input<typeof ConfirmVendorAssignmentInputSchema>;

export const ReassignVendorAssignmentInputSchema = z.object({
  invitationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newVendorMasterId: z.string().uuid(),
  newContractId: z.string().uuid().nullable().default(null),
  newPoId: z.string().uuid().nullable().default(null),
  newRateVersionId: z.string().uuid().nullable().default(null),
  newCapacityReservationId: z.string().uuid().nullable().default(null),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReassignVendorAssignmentInput = z.input<typeof ReassignVendorAssignmentInputSchema>;

export const OverrideVendorAssignmentInputSchema = z.object({
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type OverrideVendorAssignmentInput = z.input<typeof OverrideVendorAssignmentInputSchema>;
