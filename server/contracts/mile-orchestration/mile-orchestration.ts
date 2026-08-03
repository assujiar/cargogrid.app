/**
 * First-, Middle-, and Last-Mile Orchestration with Tracking Policy contract
 * (ATW-225, CG-S10-ATW-006). Mirrors
 * supabase/migrations/20260729330000_create_advanced_tms_mile_orchestration.sql's
 * app.shipment_leg_tracking_policies / app.shipment_leg_tracking_sessions shapes,
 * their RPCs, and the resolution projection.
 *
 * A "tracking session" here is an intent-level orchestration record (who/what
 * should be the authoritative source) -- never a position, ping, or raw
 * telemetry row. No shape here ever ingests or stores live telemetry.
 */

import { z } from "zod";

export const TRACKING_SOURCE_TYPES = ["driver_mobile", "direct_device", "third_party_platform"] as const;
export const TrackingSourceTypeSchema = z.enum(TRACKING_SOURCE_TYPES);
export type TrackingSourceType = z.infer<typeof TrackingSourceTypeSchema>;

export const TRACKING_RESOURCE_KINDS = ["vehicle", "driver"] as const;
export const TrackingResourceKindSchema = z.enum(TRACKING_RESOURCE_KINDS);
export type TrackingResourceKind = z.infer<typeof TrackingResourceKindSchema>;

export const TRACKING_START_TRIGGERS = ["leg_dispatch", "first_stop_arrival"] as const;
export const TrackingStartTriggerSchema = z.enum(TRACKING_START_TRIGGERS);
export type TrackingStartTrigger = z.infer<typeof TrackingStartTriggerSchema>;

export const TRACKING_END_TRIGGERS = ["last_stop_arrival", "leg_complete"] as const;
export const TrackingEndTriggerSchema = z.enum(TRACKING_END_TRIGGERS);
export type TrackingEndTrigger = z.infer<typeof TrackingEndTriggerSchema>;

export const TRACKING_SESSION_END_REASONS = ["leg_completed", "handoff", "stale_source", "manual_stop", "unauthorized_override"] as const;
export const TrackingSessionEndReasonSchema = z.enum(TRACKING_SESSION_END_REASONS);
export type TrackingSessionEndReason = z.infer<typeof TrackingSessionEndReasonSchema>;

export const ShipmentLegTrackingPolicySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentLegId: z.string().uuid(),
  trackingRequired: z.boolean(),
  allowedSources: z.array(TrackingSourceTypeSchema),
  preferredSource: TrackingSourceTypeSchema.nullable(),
  fallbackOrder: z.array(TrackingSourceTypeSchema),
  freshnessToleranceSeconds: z.number().int().positive().nullable(),
  accuracyToleranceMeters: z.coerce.number().nullable(),
  pingIntervalSeconds: z.number().int().positive().nullable(),
  startTrigger: TrackingStartTriggerSchema,
  endTrigger: TrackingEndTriggerSchema,
  geofencePolicy: z.record(z.string(), z.unknown()).nullable(),
  customerVisible: z.boolean(),
  noSignalEscalationSeconds: z.number().int().positive().nullable(),
  policyVersion: z.number().int().positive(),
  status: z.enum(["active", "disabled"]),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ShipmentLegTrackingPolicy = z.infer<typeof ShipmentLegTrackingPolicySchema>;

export function parseShipmentLegTrackingPolicy(row: Record<string, unknown>): ShipmentLegTrackingPolicy {
  return ShipmentLegTrackingPolicySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentLegId: row.shipment_leg_id,
    trackingRequired: row.tracking_required,
    allowedSources: row.allowed_sources ?? [],
    preferredSource: row.preferred_source ?? null,
    fallbackOrder: row.fallback_order ?? [],
    freshnessToleranceSeconds: row.freshness_tolerance_seconds ?? null,
    accuracyToleranceMeters: row.accuracy_tolerance_meters ?? null,
    pingIntervalSeconds: row.ping_interval_seconds ?? null,
    startTrigger: row.start_trigger,
    endTrigger: row.end_trigger,
    geofencePolicy: row.geofence_policy ?? null,
    customerVisible: row.customer_visible,
    noSignalEscalationSeconds: row.no_signal_escalation_seconds ?? null,
    policyVersion: row.policy_version,
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ShipmentLegTrackingSessionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentLegId: z.string().uuid(),
  policyId: z.string().uuid(),
  sourceType: TrackingSourceTypeSchema,
  resourceKind: TrackingResourceKindSchema,
  resourceMasterId: z.string().uuid(),
  deviceId: z.string().uuid().nullable(),
  trackingEntitledAtStart: z.boolean(),
  status: z.enum(["active", "ended"]),
  startedAt: z.string(),
  endedAt: z.string().nullable(),
  endReason: TrackingSessionEndReasonSchema.nullable(),
  isCurrent: z.boolean(),
  supersededById: z.string().uuid().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type ShipmentLegTrackingSession = z.infer<typeof ShipmentLegTrackingSessionSchema>;

export function parseShipmentLegTrackingSession(row: Record<string, unknown>): ShipmentLegTrackingSession {
  return ShipmentLegTrackingSessionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentLegId: row.shipment_leg_id,
    policyId: row.policy_id,
    sourceType: row.source_type,
    resourceKind: row.resource_kind,
    resourceMasterId: row.resource_master_id,
    deviceId: row.device_id ?? null,
    trackingEntitledAtStart: row.tracking_entitled_at_start,
    status: row.status,
    startedAt: row.started_at,
    endedAt: row.ended_at ?? null,
    endReason: row.end_reason ?? null,
    isCurrent: row.is_current,
    supersededById: row.superseded_by_id ?? null,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
  });
}

export const ResolvedLegTrackingPolicySchema = z.object({
  policyId: z.string().uuid().nullable(),
  trackingRequired: z.boolean().nullable(),
  trackingEntitled: z.boolean(),
  eligibleSources: z.array(TrackingSourceTypeSchema),
  resolvedSource: TrackingSourceTypeSchema.nullable(),
  resolvedVehicleMasterId: z.string().uuid().nullable(),
  resolvedDriverMasterId: z.string().uuid().nullable(),
  resolvedDeviceId: z.string().uuid().nullable(),
  blockedReason: z.string().nullable(),
});
export type ResolvedLegTrackingPolicy = z.infer<typeof ResolvedLegTrackingPolicySchema>;

export function parseResolvedLegTrackingPolicy(row: Record<string, unknown>): ResolvedLegTrackingPolicy {
  return ResolvedLegTrackingPolicySchema.parse({
    policyId: row.policy_id ?? null,
    trackingRequired: row.tracking_required ?? null,
    trackingEntitled: row.tracking_entitled,
    eligibleSources: row.eligible_sources ?? [],
    resolvedSource: row.resolved_source ?? null,
    resolvedVehicleMasterId: row.resolved_vehicle_master_id ?? null,
    resolvedDriverMasterId: row.resolved_driver_master_id ?? null,
    resolvedDeviceId: row.resolved_device_id ?? null,
    blockedReason: row.blocked_reason ?? null,
  });
}

// --- Mutation input schemas ---

export const UpsertShipmentLegTrackingPolicyInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  trackingRequired: z.boolean(),
  allowedSources: z.array(TrackingSourceTypeSchema),
  preferredSource: TrackingSourceTypeSchema.nullable(),
  fallbackOrder: z.array(TrackingSourceTypeSchema),
  freshnessToleranceSeconds: z.number().int().positive().nullable(),
  accuracyToleranceMeters: z.number().min(0).nullable(),
  pingIntervalSeconds: z.number().int().positive().nullable(),
  startTrigger: TrackingStartTriggerSchema,
  endTrigger: TrackingEndTriggerSchema,
  geofencePolicy: z.record(z.string(), z.unknown()).nullable(),
  customerVisible: z.boolean(),
  noSignalEscalationSeconds: z.number().int().positive().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpsertShipmentLegTrackingPolicyInput = z.input<typeof UpsertShipmentLegTrackingPolicyInputSchema>;

export const ResolveLegTrackingPolicyInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type ResolveLegTrackingPolicyInput = z.input<typeof ResolveLegTrackingPolicyInputSchema>;

export const StartLegTrackingSessionInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  sourceType: TrackingSourceTypeSchema,
  resourceKind: TrackingResourceKindSchema,
  resourceMasterId: z.string().uuid(),
  deviceId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type StartLegTrackingSessionInput = z.input<typeof StartLegTrackingSessionInputSchema>;

export const HandoffLegTrackingSessionInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  sourceType: TrackingSourceTypeSchema,
  resourceKind: TrackingResourceKindSchema,
  resourceMasterId: z.string().uuid(),
  deviceId: z.string().uuid().nullable(),
  handoffReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type HandoffLegTrackingSessionInput = z.input<typeof HandoffLegTrackingSessionInputSchema>;

export const EndLegTrackingSessionInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  endReason: z.enum(["leg_completed", "manual_stop", "unauthorized_override"]),
  reasonNote: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type EndLegTrackingSessionInput = z.input<typeof EndLegTrackingSessionInputSchema>;

export const EvaluateLegNoSignalEscalationInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type EvaluateLegNoSignalEscalationInput = z.input<typeof EvaluateLegNoSignalEscalationInputSchema>;
