/**
 * Geofence, route deviation, milestone candidate, and exception signal contract
 * (ATW-226G, Prompt 226 decomposition child). Mirrors supabase/migrations/
 * 20260730090000_create_advanced_tms_geofence_route_deviation_signals.sql's
 * app.shipment_leg_stop_geofence_states/app.shipment_leg_route_deviation_states/
 * app.shipment_milestone_candidates/app.shipment_exception_signals shapes and their
 * confirm/dismiss/read RPCs.
 *
 * Every derived signal here is staged and reviewed -- app.confirm_milestone_candidate/
 * app.confirm_exception_signal are the only paths that ever produce a real
 * app.milestone_events/app.operational_exceptions row, each requiring a real,
 * RBAC-checked actor (never an automated/system bypass -- see the migration's own
 * design note 1 for why that is a structural requirement, not a policy choice).
 */

import { z } from "zod";

export const GEOFENCE_STATES = ["outside", "entered_pending_dwell", "confirmed_inside", "exited"] as const;
export const GeofenceStateEnumSchema = z.enum(GEOFENCE_STATES);
export type GeofenceStateEnum = z.infer<typeof GeofenceStateEnumSchema>;

export const ROUTE_DEVIATION_STATES = ["on_corridor", "off_corridor"] as const;
export const RouteDeviationStateEnumSchema = z.enum(ROUTE_DEVIATION_STATES);
export type RouteDeviationStateEnum = z.infer<typeof RouteDeviationStateEnumSchema>;

export const CANDIDATE_STATUSES = ["pending", "confirmed", "dismissed"] as const;
export const CandidateStatusSchema = z.enum(CANDIDATE_STATUSES);
export type CandidateStatus = z.infer<typeof CandidateStatusSchema>;

export const SIGNAL_STATUSES = ["pending", "confirmed", "dismissed"] as const;
export const SignalStatusSchema = z.enum(SIGNAL_STATUSES);
export type SignalStatus = z.infer<typeof SignalStatusSchema>;

/** tracking_health_no_signal was added at ATW-228 (app.detect_shipment_leg_tracking_health_signals) -- reuses this same table/confirm/dismiss path, never a second staging table. */
export const EXCEPTION_SIGNAL_TYPES = ["route_deviation", "overdue_geofence_arrival", "tracking_health_no_signal"] as const;
export const ExceptionSignalTypeSchema = z.enum(EXCEPTION_SIGNAL_TYPES);
export type ExceptionSignalType = z.infer<typeof ExceptionSignalTypeSchema>;

const GeoJsonPointSchema = z.object({
  type: z.literal("Point"),
  coordinates: z.tuple([z.number(), z.number()]),
});

export const ShipmentLegStopGeofenceStateSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentLegStopId: z.string().uuid(),
  shipmentLegId: z.string().uuid(),
  radiusMeters: z.number(),
  dwellSecondsBeforeConfirm: z.number(),
  state: GeofenceStateEnumSchema,
  firstEnteredAt: z.string().nullable(),
  confirmedAt: z.string().nullable(),
  lastEvaluatedAt: z.string(),
  lastEvaluatedLocation: GeoJsonPointSchema.nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ShipmentLegStopGeofenceState = z.infer<typeof ShipmentLegStopGeofenceStateSchema>;

export function parseShipmentLegStopGeofenceState(row: Record<string, unknown>): ShipmentLegStopGeofenceState {
  return ShipmentLegStopGeofenceStateSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentLegStopId: row.shipment_leg_stop_id,
    shipmentLegId: row.shipment_leg_id,
    radiusMeters: Number(row.radius_meters),
    dwellSecondsBeforeConfirm: Number(row.dwell_seconds_before_confirm),
    state: row.state,
    firstEnteredAt: row.first_entered_at ?? null,
    confirmedAt: row.confirmed_at ?? null,
    lastEvaluatedAt: row.last_evaluated_at,
    lastEvaluatedLocation: row.last_evaluated_location_geojson ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ShipmentLegRouteDeviationStateSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentLegId: z.string().uuid(),
  state: RouteDeviationStateEnumSchema,
  firstOffCorridorAt: z.string().nullable(),
  confirmedAt: z.string().nullable(),
  lastEvaluatedAt: z.string(),
  lastDistanceMeters: z.number().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ShipmentLegRouteDeviationState = z.infer<typeof ShipmentLegRouteDeviationStateSchema>;

export function parseShipmentLegRouteDeviationState(row: Record<string, unknown>): ShipmentLegRouteDeviationState {
  return ShipmentLegRouteDeviationStateSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentLegId: row.shipment_leg_id,
    state: row.state,
    firstOffCorridorAt: row.first_off_corridor_at ?? null,
    confirmedAt: row.confirmed_at ?? null,
    lastEvaluatedAt: row.last_evaluated_at,
    lastDistanceMeters: row.last_distance_meters === null || row.last_distance_meters === undefined ? null : Number(row.last_distance_meters),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ShipmentMilestoneCandidateSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  shipmentLegId: z.string().uuid(),
  shipmentLegStopId: z.string().uuid(),
  milestoneCode: z.string(),
  candidateEventTime: z.string(),
  detectedAt: z.string(),
  sourceCanonicalEventId: z.string().uuid().nullable(),
  location: GeoJsonPointSchema.nullable(),
  status: CandidateStatusSchema,
  dedupKey: z.string(),
  resultingMilestoneEventId: z.string().uuid().nullable(),
  reviewedByUserId: z.string().uuid().nullable(),
  reviewedAt: z.string().nullable(),
  reviewNote: z.string().nullable(),
  createdAt: z.string(),
});
export type ShipmentMilestoneCandidate = z.infer<typeof ShipmentMilestoneCandidateSchema>;

export function parseShipmentMilestoneCandidate(row: Record<string, unknown>): ShipmentMilestoneCandidate {
  return ShipmentMilestoneCandidateSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    shipmentLegId: row.shipment_leg_id,
    shipmentLegStopId: row.shipment_leg_stop_id,
    milestoneCode: row.milestone_code,
    candidateEventTime: row.candidate_event_time,
    detectedAt: row.detected_at,
    sourceCanonicalEventId: row.source_canonical_event_id ?? null,
    location: row.location_geojson ?? null,
    status: row.status,
    dedupKey: row.dedup_key,
    resultingMilestoneEventId: row.resulting_milestone_event_id ?? null,
    reviewedByUserId: row.reviewed_by_user_id ?? null,
    reviewedAt: row.reviewed_at ?? null,
    reviewNote: row.review_note ?? null,
    createdAt: row.created_at,
  });
}

export const ShipmentExceptionSignalSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  shipmentLegId: z.string().uuid(),
  signalType: ExceptionSignalTypeSchema,
  exceptionType: z.string(),
  severity: z.string(),
  detectedAt: z.string(),
  sourceCanonicalEventId: z.string().uuid().nullable(),
  location: GeoJsonPointSchema.nullable(),
  description: z.string(),
  correlationKey: z.string(),
  status: SignalStatusSchema,
  resultingExceptionId: z.string().uuid().nullable(),
  reviewedByUserId: z.string().uuid().nullable(),
  reviewedAt: z.string().nullable(),
  reviewNote: z.string().nullable(),
  createdAt: z.string(),
});
export type ShipmentExceptionSignal = z.infer<typeof ShipmentExceptionSignalSchema>;

export function parseShipmentExceptionSignal(row: Record<string, unknown>): ShipmentExceptionSignal {
  return ShipmentExceptionSignalSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    shipmentLegId: row.shipment_leg_id,
    signalType: row.signal_type,
    exceptionType: row.exception_type,
    severity: row.severity,
    detectedAt: row.detected_at,
    sourceCanonicalEventId: row.source_canonical_event_id ?? null,
    location: row.location_geojson ?? null,
    description: row.description,
    correlationKey: row.correlation_key,
    status: row.status,
    resultingExceptionId: row.resulting_exception_id ?? null,
    reviewedByUserId: row.reviewed_by_user_id ?? null,
    reviewedAt: row.reviewed_at ?? null,
    reviewNote: row.review_note ?? null,
    createdAt: row.created_at,
  });
}

export const ConfirmMilestoneCandidateInputSchema = z.object({
  candidateId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  overrideEventTime: z.string().nullable().default(null),
  overrideConflict: z.boolean().default(false),
});
export type ConfirmMilestoneCandidateInput = z.input<typeof ConfirmMilestoneCandidateInputSchema>;

export const DismissMilestoneCandidateInputSchema = z.object({
  candidateId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reviewNote: z.string().min(1),
});
export type DismissMilestoneCandidateInput = z.input<typeof DismissMilestoneCandidateInputSchema>;

export const ConfirmExceptionSignalInputSchema = z.object({
  signalId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ConfirmExceptionSignalInput = z.input<typeof ConfirmExceptionSignalInputSchema>;

export const DismissExceptionSignalInputSchema = z.object({
  signalId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
  reviewNote: z.string().min(1),
});
export type DismissExceptionSignalInput = z.input<typeof DismissExceptionSignalInputSchema>;

export const GetShipmentMilestoneCandidatesInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  status: CandidateStatusSchema.nullable().default("pending"),
});
export type GetShipmentMilestoneCandidatesInput = z.input<typeof GetShipmentMilestoneCandidatesInputSchema>;

export const GetShipmentExceptionSignalsInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  status: SignalStatusSchema.nullable().default("pending"),
});
export type GetShipmentExceptionSignalsInput = z.input<typeof GetShipmentExceptionSignalsInputSchema>;

export const GetShipmentLegGeofenceStateInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetShipmentLegGeofenceStateInput = z.input<typeof GetShipmentLegGeofenceStateInputSchema>;

export const GetShipmentLegRouteDeviationStateInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetShipmentLegRouteDeviationStateInput = z.input<typeof GetShipmentLegRouteDeviationStateInputSchema>;
