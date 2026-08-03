/**
 * Basic Public and Customer Tracking contract (OPS-180, CG-S8-OPS-014). Mirrors
 * supabase/migrations/20260728130000_create_operations_public_tracking.sql's
 * app.shipment_tracking_tokens shape and its RPCs.
 *
 * A minimal, fast, read-only tracking surface: an unguessable per-shipment opaque
 * token resolves to a sanitized status/timeline/ePOD-availability projection --
 * never a live Customer Portal.
 */

import { z } from "zod";

export const IssueShipmentTrackingTokenInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  validityDays: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type IssueShipmentTrackingTokenInput = z.input<typeof IssueShipmentTrackingTokenInputSchema>;

export const IssuedShipmentTrackingTokenSchema = z.object({
  tokenId: z.string().uuid(),
  rawToken: z.string(),
  expiresAt: z.string(),
  shipmentOrderId: z.string().uuid(),
});
export type IssuedShipmentTrackingToken = z.infer<typeof IssuedShipmentTrackingTokenSchema>;

export function parseIssuedShipmentTrackingToken(row: Record<string, unknown>): IssuedShipmentTrackingToken {
  return IssuedShipmentTrackingTokenSchema.parse({
    tokenId: row.token_id,
    rawToken: row.raw_token,
    expiresAt: row.expires_at,
    shipmentOrderId: row.shipment_order_id,
  });
}

export const RevokeShipmentTrackingTokenInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RevokeShipmentTrackingTokenInput = z.input<typeof RevokeShipmentTrackingTokenInputSchema>;

export const ShipmentTrackingTokenSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  status: z.enum(["active", "revoked"]),
  expiresAt: z.string(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type ShipmentTrackingToken = z.infer<typeof ShipmentTrackingTokenSchema>;

export function parseShipmentTrackingToken(row: Record<string, unknown>): ShipmentTrackingToken {
  return ShipmentTrackingTokenSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    status: row.status,
    expiresAt: row.expires_at,
    revokedAt: row.revoked_at ?? null,
    revokedReason: row.revoked_reason ?? null,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
  });
}

export const LOOKUP_STATUSES = ["ok", "not_found", "invalid", "rate_limited"] as const;
export const LookupStatusSchema = z.enum(LOOKUP_STATUSES);
export type LookupStatus = z.infer<typeof LookupStatusSchema>;

export const PublicTrackingMilestoneSchema = z.object({
  code: z.string(),
  eventTime: z.string(),
});
export type PublicTrackingMilestone = z.infer<typeof PublicTrackingMilestoneSchema>;

export const VEHICLE_POSITION_STATUSES = ["live", "delayed", "unavailable"] as const;
export const VehiclePositionStatusSchema = z.enum(VEHICLE_POSITION_STATUSES);
export type VehiclePositionStatus = z.infer<typeof VehiclePositionStatusSchema>;

const PublicTrackingGeoJsonPointSchema = z.object({
  type: z.literal("Point"),
  coordinates: z.tuple([z.number(), z.number()]),
});

export const LIVE_ETA_STATUSES = ["on_time", "delayed", "unavailable"] as const;
export const LiveEtaStatusSchema = z.enum(LIVE_ETA_STATUSES);
export type LiveEtaStatus = z.infer<typeof LiveEtaStatusSchema>;

/**
 * app.lookup_public_shipment_tracking always returns exactly one row -- lookupStatus
 * tells the caller the outcome; every other field is null unless lookupStatus='ok'.
 * Never an exception (a raise would abort the transaction before the attempt-log
 * insert could commit). The three vehiclePosition* fields were added at ATW-226H --
 * always null unless the currently-executing leg's own tracking policy explicitly
 * marked customer_visible, a real position exists, and the shipment carries an
 * assigned vehicle -- never a raw source_type, only a coarse live/delayed/unavailable
 * status (226_*.md §16: "customers see sanitized shipment-level projections"). The
 * two liveEta* fields were added at ATW-228 -- the real, telemetry-based ETA
 * (app._compute_shipment_leg_eta), deliberately distinct from currentEta/isDelayed
 * (OPS-173's own disclosed milestone-only heuristic), gated on the identical
 * customer_visible flag, coarsened to on_time/delayed/unavailable, never a raw
 * distance/delay-minutes figure.
 */
export const PublicShipmentTrackingResultSchema = z.object({
  lookupStatus: LookupStatusSchema,
  shipmentNumber: z.string().nullable(),
  status: z.string().nullable(),
  mode: z.string().nullable(),
  origin: z.string().nullable(),
  destination: z.string().nullable(),
  plannedDeliveryAt: z.string().nullable(),
  currentEta: z.string().nullable(),
  isDelayed: z.boolean().nullable(),
  milestones: z.array(PublicTrackingMilestoneSchema),
  epodAvailable: z.boolean().nullable(),
  vehiclePosition: PublicTrackingGeoJsonPointSchema.nullable(),
  vehiclePositionUpdatedAt: z.string().nullable(),
  vehiclePositionStatus: VehiclePositionStatusSchema.nullable(),
  liveEtaStatus: LiveEtaStatusSchema.nullable(),
  liveEtaAt: z.string().nullable(),
});
export type PublicShipmentTrackingResult = z.infer<typeof PublicShipmentTrackingResultSchema>;

export function parsePublicShipmentTrackingResult(row: Record<string, unknown>): PublicShipmentTrackingResult {
  const rawMilestones = (row.milestones as Array<Record<string, unknown>>) ?? [];
  return PublicShipmentTrackingResultSchema.parse({
    lookupStatus: row.lookup_status,
    shipmentNumber: row.shipment_number ?? null,
    status: row.status ?? null,
    mode: row.mode ?? null,
    origin: row.origin ?? null,
    destination: row.destination ?? null,
    plannedDeliveryAt: row.planned_delivery_at ?? null,
    currentEta: row.current_eta ?? null,
    isDelayed: row.is_delayed ?? null,
    milestones: rawMilestones.map((m) => ({ code: m.code, eventTime: m.eventTime })),
    epodAvailable: row.epod_available ?? null,
    vehiclePosition: row.vehicle_position_geojson ?? null,
    vehiclePositionUpdatedAt: row.vehicle_position_updated_at ?? null,
    vehiclePositionStatus: row.vehicle_position_status ?? null,
    liveEtaStatus: row.live_eta_status ?? null,
    liveEtaAt: row.live_eta_at ?? null,
  });
}

export const LookupPublicShipmentTrackingInputSchema = z.object({
  rawToken: z.string().nullable(),
  clientKey: z.string().min(1),
});
export type LookupPublicShipmentTrackingInput = z.input<typeof LookupPublicShipmentTrackingInputSchema>;
