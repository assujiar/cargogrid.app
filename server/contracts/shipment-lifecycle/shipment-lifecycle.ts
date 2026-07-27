/**
 * Shipment Lifecycle contract (OPS-170, CG-S8-OPS-004). Mirrors
 * supabase/migrations/20260727110000_create_operations_shipment_lifecycle.sql's
 * app.shipment_status_transitions shape and its RPCs.
 *
 * The canonical Shipment Order state machine: draft -> confirmed -> planned ->
 * assigned -> dispatched -> in_transit -> delivered -> epod -> closed, plus held
 * (suspends from any active state, resumes only into its own held_from_status) and
 * cancelled (terminal). Reopening a closed shipment (-> delivered/epod) is a Supreme
 * Admin-only correction (RPD-022), never an ordinary transition.
 */

import { z } from "zod";

export const SHIPMENT_LIFECYCLE_STATUSES = [
  "draft",
  "confirmed",
  "planned",
  "assigned",
  "dispatched",
  "in_transit",
  "delivered",
  "epod",
  "closed",
  "held",
  "cancelled",
] as const;
export const ShipmentLifecycleStatusSchema = z.enum(SHIPMENT_LIFECYCLE_STATUSES);
export type ShipmentLifecycleStatus = z.infer<typeof ShipmentLifecycleStatusSchema>;

/** States a caller may request a transition into via app.transition_shipment_order -- excludes 'draft' (never a transition target) and 'confirmed' (owned by app.confirm_shipment_order, OPS-169). */
export const TRANSITIONABLE_STATUSES = [
  "planned",
  "assigned",
  "dispatched",
  "in_transit",
  "delivered",
  "epod",
  "closed",
  "held",
  "cancelled",
] as const;
export const TransitionableStatusSchema = z.enum(TRANSITIONABLE_STATUSES);
export type TransitionableStatus = z.infer<typeof TransitionableStatusSchema>;

export const ShipmentStatusTransitionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  fromStatus: ShipmentLifecycleStatusSchema,
  toStatus: ShipmentLifecycleStatusSchema,
  reason: z.string().nullable(),
  evidenceRef: z.string().nullable(),
  idempotencyKey: z.string(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type ShipmentStatusTransition = z.infer<typeof ShipmentStatusTransitionSchema>;

export function parseShipmentStatusTransition(row: Record<string, unknown>): ShipmentStatusTransition {
  return ShipmentStatusTransitionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    fromStatus: row.from_status,
    toStatus: row.to_status,
    reason: row.reason ?? null,
    evidenceRef: row.evidence_ref ?? null,
    idempotencyKey: row.idempotency_key,
    actorAuthUserId: row.actor_auth_user_id ?? null,
    actorLabel: row.actor_label ?? null,
    occurredAt: row.occurred_at,
  });
}

export const TransitionShipmentOrderInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  toStatus: TransitionableStatusSchema,
  expectedVersion: z.number().int().positive(),
  reason: z.string().nullable().default(null),
  evidenceRef: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type TransitionShipmentOrderInput = z.input<typeof TransitionShipmentOrderInputSchema>;

export const GetShipmentStatusHistoryInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetShipmentStatusHistoryInput = z.input<typeof GetShipmentStatusHistoryInputSchema>;
