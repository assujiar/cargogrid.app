/**
 * Tracking entitlement and tenant source policy contract (ATW-226A, CG-S10-ATW-006's
 * own child, Prompt 226 decomposition). Mirrors
 * supabase/migrations/20260729340000_create_advanced_tms_tracking_entitlement_source_policy.sql's
 * app.tracking_package_resolution composite type, app.tenant_tracking_source_policies
 * shape, and the app.resolve_tenant_tracking_package / app.is_shipment_tracking_entitled /
 * app.upsert_tenant_tracking_source_policy / app.resolve_tenant_tracking_source_policy RPCs.
 *
 * Entitlement/package/limits are Configuration Engine (PLT-121) data, not a new
 * schema -- assigning a tenant's tracking package reuses PLT-121's own
 * createConfigDraft/setConfigItems/publishConfigVersion mutations directly
 * (server/mutations/config.ts, configTypeCode = "feature", scopeLevel = "tenant"),
 * not re-declared here.
 */

import { z } from "zod";

export const TRACKING_SOURCE_TYPES = ["driver_mobile", "direct_device", "third_party_platform"] as const;
export const TrackingSourceTypeSchema = z.enum(TRACKING_SOURCE_TYPES);
export type TrackingSourceType = z.infer<typeof TrackingSourceTypeSchema>;

export const TrackingPackageResolutionSchema = z.object({
  enabled: z.boolean(),
  packageCode: z.string().nullable(),
  maxTrackedVehicles: z.number().int().nullable(),
  maxMobileSessions: z.number().int().nullable(),
  historyRetentionDays: z.number().int().nullable(),
  resolvedVersionId: z.string().uuid().nullable(),
});
export type TrackingPackageResolution = z.infer<typeof TrackingPackageResolutionSchema>;

/** Maps a raw app.tracking_package_resolution row (snake_case) to this contract's camelCase shape. */
export function parseTrackingPackageResolution(row: Record<string, unknown>): TrackingPackageResolution {
  return TrackingPackageResolutionSchema.parse({
    enabled: row.enabled,
    packageCode: row.package_code ?? null,
    maxTrackedVehicles: row.max_tracked_vehicles ?? null,
    maxMobileSessions: row.max_mobile_sessions ?? null,
    historyRetentionDays: row.history_retention_days ?? null,
    resolvedVersionId: row.resolved_version_id ?? null,
  });
}

export const TenantTrackingSourcePolicySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  defaultSourcePriority: z.array(TrackingSourceTypeSchema),
  freshnessThresholdSeconds: z.number().int().positive(),
  accuracyThresholdMeters: z.number().positive(),
  switchHysteresisSeconds: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type TenantTrackingSourcePolicy = z.infer<typeof TenantTrackingSourcePolicySchema>;

/** Maps a raw app.tenant_tracking_source_policies row (snake_case) to this contract's camelCase shape. */
export function parseTenantTrackingSourcePolicy(row: Record<string, unknown>): TenantTrackingSourcePolicy {
  return TenantTrackingSourcePolicySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    defaultSourcePriority: row.default_source_priority,
    freshnessThresholdSeconds: row.freshness_threshold_seconds,
    accuracyThresholdMeters: row.accuracy_threshold_meters,
    switchHysteresisSeconds: row.switch_hysteresis_seconds,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Resolution shape from app.resolve_tenant_tracking_source_policy -- always present, is_explicit discloses whether it reflects a real tenant override or the system default. */
export const ResolvedTenantTrackingSourcePolicySchema = z.object({
  tenantId: z.string().uuid(),
  defaultSourcePriority: z.array(TrackingSourceTypeSchema),
  freshnessThresholdSeconds: z.number().int().positive(),
  accuracyThresholdMeters: z.number().positive(),
  switchHysteresisSeconds: z.number().int().nonnegative(),
  isExplicit: z.boolean(),
});
export type ResolvedTenantTrackingSourcePolicy = z.infer<typeof ResolvedTenantTrackingSourcePolicySchema>;

export function parseResolvedTenantTrackingSourcePolicy(row: Record<string, unknown>): ResolvedTenantTrackingSourcePolicy {
  return ResolvedTenantTrackingSourcePolicySchema.parse({
    tenantId: row.tenant_id,
    defaultSourcePriority: row.default_source_priority,
    freshnessThresholdSeconds: row.freshness_threshold_seconds,
    accuracyThresholdMeters: row.accuracy_threshold_meters,
    switchHysteresisSeconds: row.switch_hysteresis_seconds,
    isExplicit: row.is_explicit,
  });
}

export const UpsertTenantTrackingSourcePolicyInputSchema = z.object({
  tenantId: z.string().uuid(),
  defaultSourcePriority: z.array(TrackingSourceTypeSchema).min(1),
  freshnessThresholdSeconds: z.number().int().positive(),
  accuracyThresholdMeters: z.number().positive(),
  switchHysteresisSeconds: z.number().int().nonnegative(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpsertTenantTrackingSourcePolicyInput = z.infer<typeof UpsertTenantTrackingSourcePolicyInputSchema>;
