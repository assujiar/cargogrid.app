/**
 * Multi-Region and Data Residency contract (IAE-033, Prompt 361). Mirrors
 * supabase/migrations/20260808100000_create_intelligence_multi_region_data_residency.sql's
 * app.region_service_capabilities / app.tenant_region_assignments /
 * app.region_capability_exceptions shapes, and their configure/request/
 * approve/status/exception/read RPCs.
 */

import { z } from "zod";

export const REGION_CODES = ["apac", "americas", "emea"] as const;
export const RegionCodeSchema = z.enum(REGION_CODES);
export type RegionCode = z.infer<typeof RegionCodeSchema>;

export const NON_DEFAULT_REGION_CODES = ["americas", "emea"] as const;
export const NonDefaultRegionCodeSchema = z.enum(NON_DEFAULT_REGION_CODES);
export type NonDefaultRegionCode = z.infer<typeof NonDefaultRegionCodeSchema>;

export const REGION_SERVICE_CATEGORIES = ["database", "secrets", "backup", "observability", "ai_provider"] as const;
export const RegionServiceCategorySchema = z.enum(REGION_SERVICE_CATEGORIES);
export type RegionServiceCategory = z.infer<typeof RegionServiceCategorySchema>;

export const REGION_ASSIGNMENT_STATUSES = ["pending_review", "approved", "active", "rejected", "decommissioned"] as const;
export const RegionAssignmentStatusSchema = z.enum(REGION_ASSIGNMENT_STATUSES);
export type RegionAssignmentStatus = z.infer<typeof RegionAssignmentStatusSchema>;

export const RegionServiceCapabilitySchema = z.object({
  id: z.string().uuid(),
  regionCode: RegionCodeSchema,
  serviceCategory: RegionServiceCategorySchema,
  supported: z.boolean(),
  notes: z.string().nullable(),
  updatedByAuthUserId: z.string().uuid().nullable(),
  updatedBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type RegionServiceCapability = z.infer<typeof RegionServiceCapabilitySchema>;

export function parseRegionServiceCapability(row: Record<string, unknown>): RegionServiceCapability {
  return RegionServiceCapabilitySchema.parse({
    id: row.id,
    regionCode: row.region_code,
    serviceCategory: row.service_category,
    supported: row.supported,
    notes: row.notes,
    updatedByAuthUserId: row.updated_by_auth_user_id,
    updatedBy: row.updated_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const TenantRegionAssignmentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  regionCode: NonDefaultRegionCodeSchema,
  status: RegionAssignmentStatusSchema,
  qualificationReason: z.string(),
  contractReference: z.string().nullable(),
  approvedByAuthUserId: z.string().uuid().nullable(),
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  activatedAt: z.string().nullable(),
  decommissionedAt: z.string().nullable(),
  rejectedAt: z.string().nullable(),
  rejectionReason: z.string().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  recordVersion: z.number().int(),
});
export type TenantRegionAssignment = z.infer<typeof TenantRegionAssignmentSchema>;

export function parseTenantRegionAssignment(row: Record<string, unknown>): TenantRegionAssignment {
  return TenantRegionAssignmentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    regionCode: row.region_code,
    status: row.status,
    qualificationReason: row.qualification_reason,
    contractReference: row.contract_reference,
    approvedByAuthUserId: row.approved_by_auth_user_id,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    activatedAt: row.activated_at,
    decommissionedAt: row.decommissioned_at,
    rejectedAt: row.rejected_at,
    rejectionReason: row.rejection_reason,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    recordVersion: row.record_version,
  });
}

export const RegionCapabilityExceptionSchema = z.object({
  id: z.string().uuid(),
  regionAssignmentId: z.string().uuid(),
  serviceCategory: RegionServiceCategorySchema,
  reason: z.string(),
  approvedByAuthUserId: z.string().uuid().nullable(),
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type RegionCapabilityException = z.infer<typeof RegionCapabilityExceptionSchema>;

export function parseRegionCapabilityException(row: Record<string, unknown>): RegionCapabilityException {
  return RegionCapabilityExceptionSchema.parse({
    id: row.id,
    regionAssignmentId: row.region_assignment_id,
    serviceCategory: row.service_category,
    reason: row.reason,
    approvedByAuthUserId: row.approved_by_auth_user_id,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    createdAt: row.created_at,
  });
}

export const SetRegionServiceCapabilityInputSchema = z.object({
  regionCode: RegionCodeSchema,
  serviceCategory: RegionServiceCategorySchema,
  supported: z.boolean(),
  notes: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetRegionServiceCapabilityInput = z.input<typeof SetRegionServiceCapabilityInputSchema>;

export const RequestRegionAssignmentInputSchema = z.object({
  tenantId: z.string().uuid(),
  regionCode: NonDefaultRegionCodeSchema,
  qualificationReason: z.string().min(1),
  contractReference: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestRegionAssignmentInput = z.input<typeof RequestRegionAssignmentInputSchema>;

export const ApproveRegionAssignmentInputSchema = z.object({
  regionAssignmentId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ApproveRegionAssignmentInput = z.input<typeof ApproveRegionAssignmentInputSchema>;

export const RegisterRegionCapabilityExceptionInputSchema = z.object({
  regionAssignmentId: z.string().uuid(),
  serviceCategory: RegionServiceCategorySchema,
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RegisterRegionCapabilityExceptionInput = z.input<typeof RegisterRegionCapabilityExceptionInputSchema>;

export const SetRegionAssignmentStatusInputSchema = z.object({
  regionAssignmentId: z.string().uuid(),
  newStatus: RegionAssignmentStatusSchema,
  rejectionReason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetRegionAssignmentStatusInput = z.input<typeof SetRegionAssignmentStatusInputSchema>;
