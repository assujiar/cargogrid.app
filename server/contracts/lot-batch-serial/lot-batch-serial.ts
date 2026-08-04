/**
 * Lot, Batch, Serial and Expiry contract (ATW-016, CG-S10-ATW-016, Prompt 235).
 * Mirrors
 * supabase/migrations/20260730220000_create_advanced_tms_lot_batch_serial_expiry.sql's
 * app.item_control_policy_versions/app.lot_identities/app.serial_identities shapes and
 * their create/publish/register/status/read/trace/candidate RPCs.
 */

import { z } from "zod";

export const ALLOCATION_RULES = ["fifo", "fefo"] as const;
export const AllocationRuleSchema = z.enum(ALLOCATION_RULES);
export type AllocationRule = z.infer<typeof AllocationRuleSchema>;

export const POLICY_VERSION_STATUSES = ["draft", "published", "archived"] as const;
export const PolicyVersionStatusSchema = z.enum(POLICY_VERSION_STATUSES);
export type PolicyVersionStatus = z.infer<typeof PolicyVersionStatusSchema>;

export const IDENTITY_STATUSES = ["active", "held", "quarantined", "expired", "consumed"] as const;
export const IdentityStatusSchema = z.enum(IDENTITY_STATUSES);
export type IdentityStatus = z.infer<typeof IdentityStatusSchema>;

export const ItemControlPolicyVersionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  allocationRule: AllocationRuleSchema,
  holdOnUnknownLot: z.boolean(),
  nearExpiryWarningDays: z.number().int().nullable(),
  status: PolicyVersionStatusSchema,
  supersedesVersionId: z.string().uuid().nullable(),
  effectiveFrom: z.string(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ItemControlPolicyVersion = z.infer<typeof ItemControlPolicyVersionSchema>;

export function parseItemControlPolicyVersion(row: Record<string, unknown>): ItemControlPolicyVersion {
  return ItemControlPolicyVersionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    itemMasterId: row.item_master_id,
    ownerAccountId: row.owner_account_id,
    allocationRule: row.allocation_rule,
    holdOnUnknownLot: row.hold_on_unknown_lot,
    nearExpiryWarningDays: row.near_expiry_warning_days ?? null,
    status: row.status,
    supersedesVersionId: row.supersedes_version_id ?? null,
    effectiveFrom: row.effective_from,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const LotIdentitySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  lotNumber: z.string(),
  manufactureDate: z.string().nullable(),
  expiryDate: z.string().nullable(),
  status: IdentityStatusSchema,
  holdReason: z.string().nullable(),
  parentLotId: z.string().uuid().nullable(),
  sourceType: z.enum(["receipt", "manual", "split"]),
  sourceId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LotIdentity = z.infer<typeof LotIdentitySchema>;

export function parseLotIdentity(row: Record<string, unknown>): LotIdentity {
  return LotIdentitySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    ownerAccountId: row.owner_account_id,
    itemMasterId: row.item_master_id,
    lotNumber: row.lot_number,
    manufactureDate: row.manufacture_date ?? null,
    expiryDate: row.expiry_date ?? null,
    status: row.status,
    holdReason: row.hold_reason ?? null,
    parentLotId: row.parent_lot_id ?? null,
    sourceType: row.source_type,
    sourceId: row.source_id ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const SerialIdentitySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  serialNumber: z.string(),
  lotNumber: z.string().nullable(),
  manufactureDate: z.string().nullable(),
  expiryDate: z.string().nullable(),
  status: IdentityStatusSchema,
  holdReason: z.string().nullable(),
  sourceType: z.enum(["receipt", "manual"]),
  sourceId: z.string().uuid().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type SerialIdentity = z.infer<typeof SerialIdentitySchema>;

export function parseSerialIdentity(row: Record<string, unknown>): SerialIdentity {
  return SerialIdentitySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    ownerAccountId: row.owner_account_id,
    itemMasterId: row.item_master_id,
    serialNumber: row.serial_number,
    lotNumber: row.lot_number ?? null,
    manufactureDate: row.manufacture_date ?? null,
    expiryDate: row.expiry_date ?? null,
    status: row.status,
    holdReason: row.hold_reason ?? null,
    sourceType: row.source_type,
    sourceId: row.source_id ?? null,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const TraceEventSchema = z.object({
  movementId: z.string().uuid(),
  movementType: z.string(),
  sourceType: z.string(),
  sourceId: z.string().uuid().nullable(),
  occurredAt: z.string(),
  warehouseId: z.string().uuid(),
  locationId: z.string().uuid(),
  signedQuantity: z.coerce.number(),
  lineStatus: z.string(),
});
export type TraceEvent = z.infer<typeof TraceEventSchema>;

export function parseTraceEvent(row: Record<string, unknown>): TraceEvent {
  return TraceEventSchema.parse({
    movementId: row.movement_id,
    movementType: row.movement_type,
    sourceType: row.source_type,
    sourceId: row.source_id ?? null,
    occurredAt: row.occurred_at,
    warehouseId: row.warehouse_id,
    locationId: row.location_id,
    signedQuantity: row.signed_quantity,
    lineStatus: row.line_status,
  });
}

export const AllocationCandidateSchema = z.object({
  balanceId: z.string().uuid(),
  locationId: z.string().uuid(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  manufactureDate: z.string().nullable(),
  expiryDate: z.string().nullable(),
  available: z.coerce.number(),
  lotStatus: IdentityStatusSchema.nullable(),
  serialStatus: IdentityStatusSchema.nullable(),
  nearExpiry: z.boolean(),
});
export type AllocationCandidate = z.infer<typeof AllocationCandidateSchema>;

export function parseAllocationCandidate(row: Record<string, unknown>): AllocationCandidate {
  return AllocationCandidateSchema.parse({
    balanceId: row.balance_id,
    locationId: row.location_id,
    lotNumber: row.lot_number ?? null,
    serialNumber: row.serial_number ?? null,
    manufactureDate: row.manufacture_date ?? null,
    expiryDate: row.expiry_date ?? null,
    available: row.available,
    lotStatus: row.lot_status ?? null,
    serialStatus: row.serial_status ?? null,
    nearExpiry: row.near_expiry,
  });
}

// --- Mutation input schemas ---

export const CreateItemControlPolicyVersionDraftInputSchema = z.object({
  itemMasterId: z.string().uuid(),
  allocationRule: AllocationRuleSchema.nullable(),
  holdOnUnknownLot: z.boolean().nullable(),
  nearExpiryWarningDays: z.number().int().nonnegative().nullable(),
  effectiveFrom: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateItemControlPolicyVersionDraftInput = z.input<typeof CreateItemControlPolicyVersionDraftInputSchema>;

export const PublishItemControlPolicyVersionInputSchema = z.object({
  policyVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  supersedesVersionId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishItemControlPolicyVersionInput = z.input<typeof PublishItemControlPolicyVersionInputSchema>;

export const RegisterLotIdentityInputSchema = z.object({
  itemMasterId: z.string().uuid(),
  lotNumber: z.string().min(1),
  manufactureDate: z.string().nullable(),
  expiryDate: z.string().nullable(),
  sourceType: z.enum(["receipt", "manual", "split"]).nullable(),
  sourceId: z.string().uuid().nullable(),
  parentLotId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RegisterLotIdentityInput = z.input<typeof RegisterLotIdentityInputSchema>;

export const RegisterSerialIdentityInputSchema = z.object({
  itemMasterId: z.string().uuid(),
  serialNumber: z.string().min(1),
  lotNumber: z.string().nullable(),
  manufactureDate: z.string().nullable(),
  expiryDate: z.string().nullable(),
  sourceType: z.enum(["receipt", "manual"]).nullable(),
  sourceId: z.string().uuid().nullable(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RegisterSerialIdentityInput = z.input<typeof RegisterSerialIdentityInputSchema>;

export const SetLotIdentityStatusInputSchema = z.object({
  lotIdentityId: z.string().uuid(),
  newStatus: IdentityStatusSchema,
  reason: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetLotIdentityStatusInput = z.input<typeof SetLotIdentityStatusInputSchema>;

export const SetSerialIdentityStatusInputSchema = z.object({
  serialIdentityId: z.string().uuid(),
  newStatus: IdentityStatusSchema,
  reason: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetSerialIdentityStatusInput = z.input<typeof SetSerialIdentityStatusInputSchema>;
