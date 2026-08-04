/**
 * WMS Outbound (ship-execution) contract (ATW-019, CG-S10-ATW-019, Prompt 238 --
 * the remainder of Prompt 238's own scope, layered on top of ATW-016A's own
 * "wms-outbound-order" demand contract). Mirrors
 * supabase/migrations/20260730260000_create_advanced_tms_wms_outbound.sql's
 * app.wms_outbound_shipments/app.wms_shipment_packages/app.wms_shipment_issue_lines/
 * app.wms_billing_eligibility_events shapes and their
 * create-shipment/add-package/remove-package/set-vehicle/set-dock/load/ship-confirm/
 * cancel/read RPCs.
 *
 * Distinct, sibling directory from server/contracts/wms-outbound-order/ (ATW-016A) --
 * that capability owns the demand/lines/draft-confirmed-cancelled lifecycle; this one
 * owns staging/dock/load/custody/ship-confirm/inventory-issue/billing-eligibility.
 */

import { z } from "zod";

export const WMS_OUTBOUND_SHIPMENT_STATUSES = ["staging", "loaded", "shipped", "cancelled"] as const;
export const WmsOutboundShipmentStatusSchema = z.enum(WMS_OUTBOUND_SHIPMENT_STATUSES);
export type WmsOutboundShipmentStatus = z.infer<typeof WmsOutboundShipmentStatusSchema>;

export const WmsOutboundShipmentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  outboundOrderId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  shipmentNumber: z.string(),
  idempotencyKey: z.string(),
  status: WmsOutboundShipmentStatusSchema,
  dockLocationId: z.string().uuid().nullable(),
  vehicleRef: z.string().nullable(),
  loadedAt: z.string().nullable(),
  loadedByAuthUserId: z.string().uuid().nullable(),
  loadedByLabel: z.string().nullable(),
  loadMovementId: z.string().uuid().nullable(),
  custodyConfirmedByLabel: z.string().nullable(),
  custodyConfirmedReason: z.string().nullable(),
  custodyConfirmedAt: z.string().nullable(),
  shippedAt: z.string().nullable(),
  shippedByAuthUserId: z.string().uuid().nullable(),
  shippedByLabel: z.string().nullable(),
  consumptionMovementId: z.string().uuid().nullable(),
  isPartialFulfillment: z.boolean(),
  partialFulfillmentReason: z.string().nullable(),
  cancelledAt: z.string().nullable(),
  cancelledByAuthUserId: z.string().uuid().nullable(),
  cancelledByLabel: z.string().nullable(),
  cancelledReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WmsOutboundShipment = z.infer<typeof WmsOutboundShipmentSchema>;

export function parseWmsOutboundShipment(row: Record<string, unknown>): WmsOutboundShipment {
  return WmsOutboundShipmentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    outboundOrderId: row.outbound_order_id,
    ownerAccountId: row.owner_account_id,
    shipmentNumber: row.shipment_number,
    idempotencyKey: row.idempotency_key,
    status: row.status,
    dockLocationId: row.dock_location_id ?? null,
    vehicleRef: row.vehicle_ref ?? null,
    loadedAt: row.loaded_at ?? null,
    loadedByAuthUserId: row.loaded_by_auth_user_id ?? null,
    loadedByLabel: row.loaded_by_label ?? null,
    loadMovementId: row.load_movement_id ?? null,
    custodyConfirmedByLabel: row.custody_confirmed_by_label ?? null,
    custodyConfirmedReason: row.custody_confirmed_reason ?? null,
    custodyConfirmedAt: row.custody_confirmed_at ?? null,
    shippedAt: row.shipped_at ?? null,
    shippedByAuthUserId: row.shipped_by_auth_user_id ?? null,
    shippedByLabel: row.shipped_by_label ?? null,
    consumptionMovementId: row.consumption_movement_id ?? null,
    isPartialFulfillment: row.is_partial_fulfillment,
    partialFulfillmentReason: row.partial_fulfillment_reason ?? null,
    cancelledAt: row.cancelled_at ?? null,
    cancelledByAuthUserId: row.cancelled_by_auth_user_id ?? null,
    cancelledByLabel: row.cancelled_by_label ?? null,
    cancelledReason: row.cancelled_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WmsShipmentPackageSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentId: z.string().uuid(),
  packageId: z.string().uuid(),
  idempotencyKey: z.string(),
  addedAt: z.string(),
  addedByAuthUserId: z.string().uuid().nullable(),
  addedByLabel: z.string().nullable(),
});
export type WmsShipmentPackage = z.infer<typeof WmsShipmentPackageSchema>;

export function parseWmsShipmentPackage(row: Record<string, unknown>): WmsShipmentPackage {
  return WmsShipmentPackageSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentId: row.shipment_id,
    packageId: row.package_id,
    idempotencyKey: row.idempotency_key,
    addedAt: row.added_at,
    addedByAuthUserId: row.added_by_auth_user_id ?? null,
    addedByLabel: row.added_by_label ?? null,
  });
}

export const WmsShipmentIssueLineSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentId: z.string().uuid(),
  packageId: z.string().uuid(),
  packageLineId: z.string().uuid(),
  pickTaskId: z.string().uuid(),
  reservationId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  uomCode: z.string(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  expiryDate: z.string().nullable(),
  quantity: z.coerce.number(),
  movementId: z.string().uuid(),
  createdAt: z.string(),
});
export type WmsShipmentIssueLine = z.infer<typeof WmsShipmentIssueLineSchema>;

export function parseWmsShipmentIssueLine(row: Record<string, unknown>): WmsShipmentIssueLine {
  return WmsShipmentIssueLineSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentId: row.shipment_id,
    packageId: row.package_id,
    packageLineId: row.package_line_id,
    pickTaskId: row.pick_task_id,
    reservationId: row.reservation_id,
    itemMasterId: row.item_master_id,
    ownerAccountId: row.owner_account_id,
    uomCode: row.uom_code,
    lotNumber: row.lot_number ?? null,
    serialNumber: row.serial_number ?? null,
    expiryDate: row.expiry_date ?? null,
    quantity: row.quantity,
    movementId: row.movement_id,
    createdAt: row.created_at,
  });
}

export const WmsBillingEligibilityEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  outboundOrderId: z.string().uuid(),
  shipmentId: z.string().uuid(),
  idempotencyKey: z.string(),
  packageCount: z.coerce.number().int(),
  lineCount: z.coerce.number().int(),
  totalQuantity: z.coerce.number(),
  weightByUom: z.record(z.string(), z.coerce.number()),
  shippedAt: z.string(),
  createdAt: z.string(),
});
export type WmsBillingEligibilityEvent = z.infer<typeof WmsBillingEligibilityEventSchema>;

export function parseWmsBillingEligibilityEvent(row: Record<string, unknown>): WmsBillingEligibilityEvent {
  return WmsBillingEligibilityEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    ownerAccountId: row.owner_account_id,
    outboundOrderId: row.outbound_order_id,
    shipmentId: row.shipment_id,
    idempotencyKey: row.idempotency_key,
    packageCount: row.package_count,
    lineCount: row.line_count,
    totalQuantity: row.total_quantity,
    weightByUom: row.weight_by_uom ?? {},
    shippedAt: row.shipped_at,
    createdAt: row.created_at,
  });
}

// --- Mutation input schemas ---

export const CreateWmsOutboundShipmentInputSchema = z.object({
  outboundOrderId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateWmsOutboundShipmentInput = z.input<typeof CreateWmsOutboundShipmentInputSchema>;

export const AddPackageToShipmentInputSchema = z.object({
  shipmentId: z.string().uuid(),
  packageId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddPackageToShipmentInput = z.input<typeof AddPackageToShipmentInputSchema>;

export const RemovePackageFromShipmentInputSchema = z.object({
  shipmentId: z.string().uuid(),
  packageId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RemovePackageFromShipmentInput = z.input<typeof RemovePackageFromShipmentInputSchema>;

export const SetWmsShipmentVehicleRefInputSchema = z.object({
  shipmentId: z.string().uuid(),
  vehicleRef: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetWmsShipmentVehicleRefInput = z.input<typeof SetWmsShipmentVehicleRefInputSchema>;

export const SetWmsShipmentDockLocationInputSchema = z.object({
  shipmentId: z.string().uuid(),
  dockLocationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetWmsShipmentDockLocationInput = z.input<typeof SetWmsShipmentDockLocationInputSchema>;

export const LoadWmsOutboundShipmentInputSchema = z.object({
  shipmentId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type LoadWmsOutboundShipmentInput = z.input<typeof LoadWmsOutboundShipmentInputSchema>;

export const ShipConfirmWmsOutboundShipmentInputSchema = z.object({
  shipmentId: z.string().uuid(),
  custodyConfirmedByLabel: z.string().min(1),
  custodyConfirmedReason: z.string().min(1),
  isPartialFulfillment: z.boolean(),
  partialFulfillmentReason: z.string().nullable(),
  idempotencyKey: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ShipConfirmWmsOutboundShipmentInput = z.input<typeof ShipConfirmWmsOutboundShipmentInputSchema>;

export const CancelWmsOutboundShipmentInputSchema = z.object({
  shipmentId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelWmsOutboundShipmentInput = z.input<typeof CancelWmsOutboundShipmentInputSchema>;
