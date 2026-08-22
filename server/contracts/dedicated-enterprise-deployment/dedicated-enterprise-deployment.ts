/**
 * Dedicated Enterprise Deployment contract (IAE-032, Prompt 360). Mirrors
 * supabase/migrations/20260808000000_create_intelligence_dedicated_enterprise_deployment.sql's
 * app.tenant_deployment_records / app.tenant_deployment_environment_refs
 * shapes, and their request/approve/status/env-ref/read RPCs.
 */

import { z } from "zod";

export const DEPLOYMENT_TYPES = ["dedicated"] as const;
export const DeploymentTypeSchema = z.enum(DEPLOYMENT_TYPES);
export type DeploymentType = z.infer<typeof DeploymentTypeSchema>;

export const DEPLOYMENT_STATUSES = ["pending_qualification", "qualified", "provisioning", "active", "decommissioned"] as const;
export const DeploymentStatusSchema = z.enum(DEPLOYMENT_STATUSES);
export type DeploymentStatus = z.infer<typeof DeploymentStatusSchema>;

export const DEPLOYMENT_ENVIRONMENT_CATEGORIES = ["database", "secrets", "backup", "observability"] as const;
export const DeploymentEnvironmentCategorySchema = z.enum(DEPLOYMENT_ENVIRONMENT_CATEGORIES);
export type DeploymentEnvironmentCategory = z.infer<typeof DeploymentEnvironmentCategorySchema>;

export const RESOLVED_DEPLOYMENT_TYPES = ["shared", "dedicated"] as const;
export const ResolvedDeploymentTypeSchema = z.enum(RESOLVED_DEPLOYMENT_TYPES);
export type ResolvedDeploymentType = z.infer<typeof ResolvedDeploymentTypeSchema>;

export const TenantDeploymentRecordSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  deploymentType: DeploymentTypeSchema,
  status: DeploymentStatusSchema,
  qualificationReason: z.string(),
  contractReference: z.string().nullable(),
  approvedByAuthUserId: z.string().uuid().nullable(),
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  provisionedAt: z.string().nullable(),
  decommissionedAt: z.string().nullable(),
  createdByAuthUserId: z.string().uuid().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  recordVersion: z.number().int(),
});
export type TenantDeploymentRecord = z.infer<typeof TenantDeploymentRecordSchema>;

export function parseTenantDeploymentRecord(row: Record<string, unknown>): TenantDeploymentRecord {
  return TenantDeploymentRecordSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    deploymentType: row.deployment_type,
    status: row.status,
    qualificationReason: row.qualification_reason,
    contractReference: row.contract_reference,
    approvedByAuthUserId: row.approved_by_auth_user_id,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    provisionedAt: row.provisioned_at,
    decommissionedAt: row.decommissioned_at,
    createdByAuthUserId: row.created_by_auth_user_id,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    recordVersion: row.record_version,
  });
}

export const TenantDeploymentEnvironmentRefSchema = z.object({
  id: z.string().uuid(),
  deploymentRecordId: z.string().uuid(),
  environmentCategory: DeploymentEnvironmentCategorySchema,
  referenceValue: z.string(),
  verifiedByAuthUserId: z.string().uuid().nullable(),
  verifiedBy: z.string().nullable(),
  verifiedAt: z.string().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type TenantDeploymentEnvironmentRef = z.infer<typeof TenantDeploymentEnvironmentRefSchema>;

export function parseTenantDeploymentEnvironmentRef(row: Record<string, unknown>): TenantDeploymentEnvironmentRef {
  return TenantDeploymentEnvironmentRefSchema.parse({
    id: row.id,
    deploymentRecordId: row.deployment_record_id,
    environmentCategory: row.environment_category,
    referenceValue: row.reference_value,
    verifiedByAuthUserId: row.verified_by_auth_user_id,
    verifiedBy: row.verified_by,
    verifiedAt: row.verified_at,
    createdBy: row.created_by,
    createdAt: row.created_at,
  });
}

export const RequestDedicatedDeploymentQualificationInputSchema = z.object({
  tenantId: z.string().uuid(),
  qualificationReason: z.string().min(1),
  contractReference: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestDedicatedDeploymentQualificationInput = z.input<typeof RequestDedicatedDeploymentQualificationInputSchema>;

export const ApproveDedicatedDeploymentQualificationInputSchema = z.object({
  deploymentRecordId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ApproveDedicatedDeploymentQualificationInput = z.input<typeof ApproveDedicatedDeploymentQualificationInputSchema>;

export const SetDeploymentProvisioningStatusInputSchema = z.object({
  deploymentRecordId: z.string().uuid(),
  newStatus: DeploymentStatusSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetDeploymentProvisioningStatusInput = z.input<typeof SetDeploymentProvisioningStatusInputSchema>;

export const SetDeploymentEnvironmentRefInputSchema = z.object({
  deploymentRecordId: z.string().uuid(),
  environmentCategory: DeploymentEnvironmentCategorySchema,
  referenceValue: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetDeploymentEnvironmentRefInput = z.input<typeof SetDeploymentEnvironmentRefInputSchema>;
