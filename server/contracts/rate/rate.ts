/**
 * Rate and Cost Lookup contract (COM-149, CG-S7-COM-008). Mirrors
 * supabase/migrations/20260724150000_create_commercial_rate_cost_lookup.sql's
 * app.vendor_rate_versions/app.rate_selections/app.vendor_rate_versions_directory/
 * app.v_active_vendor_rates/app.rate_selections_directory shape and their RPCs.
 */

import { z } from "zod";

export const RATE_VERSION_APPROVAL_STATUSES = ["pending_approval", "approved", "rejected", "withdrawn", "superseded"] as const;
export const RateVersionApprovalStatusSchema = z.enum(RATE_VERSION_APPROVAL_STATUSES);
export type RateVersionApprovalStatus = z.infer<typeof RateVersionApprovalStatusSchema>;

/** Maps a raw app.vendor_rate_versions_directory / app.v_active_vendor_rates row (snake_case) to this contract's camelCase shape. */
export const RateVersionSchema = z.object({
  rateVersionId: z.string().uuid(),
  tenantId: z.string().uuid(),
  masterRecordId: z.string().uuid(),
  vendorCode: z.string(),
  vendorName: z.string(),
  serviceType: z.string(),
  mode: z.string().nullable(),
  originLane: z.string(),
  destinationLane: z.string(),
  equipmentType: z.string().nullable(),
  cargoWeightMin: z.coerce.number().nullable(),
  cargoWeightMax: z.coerce.number().nullable(),
  cargoVolumeMin: z.coerce.number().nullable(),
  cargoVolumeMax: z.coerce.number().nullable(),
  currency: z.string().nullable(),
  baseAmount: z.coerce.number().nullable(),
  minimumAmount: z.coerce.number().nullable(),
  surchargeComponents: z.array(z.record(z.string(), z.unknown())).nullable(),
  costMasked: z.boolean(),
  approvalStatus: RateVersionApprovalStatusSchema,
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable(),
  supersedesVersionId: z.string().uuid().nullable(),
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  rejectedReason: z.string().nullable(),
  withdrawnReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type RateVersion = z.infer<typeof RateVersionSchema>;

export function parseRateVersion(row: Record<string, unknown>): RateVersion {
  return RateVersionSchema.parse({
    rateVersionId: row.rate_version_id,
    tenantId: row.tenant_id,
    masterRecordId: row.master_record_id,
    vendorCode: row.vendor_code,
    vendorName: row.vendor_name,
    serviceType: row.service_type,
    mode: row.mode,
    originLane: row.origin_lane,
    destinationLane: row.destination_lane,
    equipmentType: row.equipment_type,
    cargoWeightMin: row.cargo_weight_min,
    cargoWeightMax: row.cargo_weight_max,
    cargoVolumeMin: row.cargo_volume_min,
    cargoVolumeMax: row.cargo_volume_max,
    currency: row.currency,
    baseAmount: row.base_amount,
    minimumAmount: row.minimum_amount,
    surchargeComponents: row.surcharge_components,
    costMasked: row.cost_masked,
    approvalStatus: row.approval_status,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    supersedesVersionId: row.supersedes_version_id,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    rejectedReason: row.rejected_reason,
    withdrawnReason: row.withdrawn_reason,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/**
 * Maps a raw app.vendor_rate_versions base-table row (snake_case) -- the shape
 * app.create_rate_version/app.approve_rate_version/app.reject_rate_version/
 * app.withdraw_rate_version all return -- to a camelCase shape. Deliberately a distinct,
 * smaller schema from RateVersionSchema: the base table has no vendor_code/vendor_name
 * (those live on the joined app.master_records row the *_directory/v_active_vendor_rates
 * views add) and no cost_masked flag (a mutation caller who successfully created/
 * approved/rejected/withdrew a rate version already passed app.is_support_grant_authority,
 * so the returned figures are never masked).
 */
export const RateVersionRecordSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  masterRecordId: z.string().uuid(),
  serviceType: z.string(),
  mode: z.string().nullable(),
  originLane: z.string(),
  destinationLane: z.string(),
  equipmentType: z.string().nullable(),
  cargoWeightMin: z.coerce.number().nullable(),
  cargoWeightMax: z.coerce.number().nullable(),
  cargoVolumeMin: z.coerce.number().nullable(),
  cargoVolumeMax: z.coerce.number().nullable(),
  currency: z.string(),
  baseAmount: z.coerce.number(),
  minimumAmount: z.coerce.number().nullable(),
  surchargeComponents: z.array(z.record(z.string(), z.unknown())),
  approvalStatus: RateVersionApprovalStatusSchema,
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable(),
  supersedesVersionId: z.string().uuid().nullable(),
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  rejectedReason: z.string().nullable(),
  withdrawnReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type RateVersionRecord = z.infer<typeof RateVersionRecordSchema>;

export function parseRateVersionRecord(row: Record<string, unknown>): RateVersionRecord {
  return RateVersionRecordSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    masterRecordId: row.master_record_id,
    serviceType: row.service_type,
    mode: row.mode,
    originLane: row.origin_lane,
    destinationLane: row.destination_lane,
    equipmentType: row.equipment_type,
    cargoWeightMin: row.cargo_weight_min,
    cargoWeightMax: row.cargo_weight_max,
    cargoVolumeMin: row.cargo_volume_min,
    cargoVolumeMax: row.cargo_volume_max,
    currency: row.currency,
    baseAmount: row.base_amount,
    minimumAmount: row.minimum_amount,
    surchargeComponents: row.surcharge_components,
    approvalStatus: row.approval_status,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    supersedesVersionId: row.supersedes_version_id,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    rejectedReason: row.rejected_reason,
    withdrawnReason: row.withdrawn_reason,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.rate_selections / app.rate_selections_directory row (snake_case) to this contract's camelCase shape. */
export const RateSelectionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  costingRequestId: z.string().uuid(),
  rateVersionId: z.string().uuid().nullable(),
  isAdhoc: z.boolean(),
  currency: z.string().nullable(),
  amount: z.coerce.number().nullable(),
  snapshot: z.record(z.string(), z.unknown()).nullable(),
  costMasked: z.boolean().nullable().optional(),
  overrideReason: z.string().nullable(),
  selectedBy: z.string().nullable(),
  createdAt: z.string(),
});
export type RateSelection = z.infer<typeof RateSelectionSchema>;

export function parseRateSelection(row: Record<string, unknown>): RateSelection {
  return RateSelectionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    costingRequestId: row.costing_request_id,
    rateVersionId: row.rate_version_id,
    isAdhoc: row.is_adhoc,
    currency: row.currency,
    amount: row.amount,
    snapshot: row.snapshot,
    costMasked: row.cost_masked ?? null,
    overrideReason: row.override_reason,
    selectedBy: row.selected_by,
    createdAt: row.created_at,
  });
}

export const CreateRateVersionInputSchema = z.object({
  tenantId: z.string().uuid(),
  vendorCode: z.string().min(1),
  vendorName: z.string().min(1),
  serviceType: z.string().min(1),
  mode: z.string().nullable().default(null),
  originLane: z.string().min(1),
  destinationLane: z.string().min(1),
  equipmentType: z.string().nullable().default(null),
  cargoWeightMin: z.number().nonnegative().nullable().default(null),
  cargoWeightMax: z.number().nonnegative().nullable().default(null),
  cargoVolumeMin: z.number().nonnegative().nullable().default(null),
  cargoVolumeMax: z.number().nonnegative().nullable().default(null),
  currency: z.string().regex(/^[A-Z]{3}$/),
  baseAmount: z.number().nonnegative(),
  minimumAmount: z.number().nonnegative().nullable().default(null),
  surchargeComponents: z.array(z.record(z.string(), z.unknown())).default([]),
  effectiveFrom: z.string().nullable().default(null),
  effectiveTo: z.string().nullable().default(null),
  supersedesVersionId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateRateVersionInput = z.input<typeof CreateRateVersionInputSchema>;

export const ApproveRateVersionInputSchema = z.object({
  rateVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ApproveRateVersionInput = z.input<typeof ApproveRateVersionInputSchema>;

export const RejectRateVersionInputSchema = z.object({
  rateVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RejectRateVersionInput = z.input<typeof RejectRateVersionInputSchema>;

export const WithdrawRateVersionInputSchema = RejectRateVersionInputSchema;
export type WithdrawRateVersionInput = z.input<typeof WithdrawRateVersionInputSchema>;

export const SearchVendorRatesInputSchema = z.object({
  tenantId: z.string().uuid(),
  serviceType: z.string().nullable().default(null),
  originLane: z.string().nullable().default(null),
  destinationLane: z.string().nullable().default(null),
  mode: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  limit: z.number().int().positive().max(200).default(20),
});
export type SearchVendorRatesInput = z.input<typeof SearchVendorRatesInputSchema>;

export const SelectVendorRateInputSchema = z.object({
  costingRequestId: z.string().uuid(),
  rateVersionId: z.string().uuid().nullable().default(null),
  isAdhoc: z.boolean().default(false),
  adhocCurrency: z.string().regex(/^[A-Z]{3}$/).nullable().default(null),
  adhocAmount: z.number().nonnegative().nullable().default(null),
  overrideReason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SelectVendorRateInput = z.input<typeof SelectVendorRateInputSchema>;
