/**
 * Customer Shipment Order contract (CPL-304, CG-S13-CPL-006, Prompt 304).
 * Mirrors supabase/migrations/20260801050000_create_customer_portal_
 * shipment_order_access.sql's RPC surface: app.get_customer_shipment_order/
 * app.list_customer_shipment_orders (a customer-safe PROJECTION over the
 * Operations-owned app.shipment_orders -- never the base table's own full
 * column set) and app.request_customer_shipment_order_change/app.list_
 * customer_shipment_order_change_requests/app.respond_to_customer_shipment_
 * order_change_request (the portal-owned "request a change" table).
 *
 * `consigneeSnapshot`/`notifyPartySnapshot`/`cargoServiceSnapshot` are
 * bounded free-form jsonb SNAPSHOTS taken verbatim from the migration's own
 * projection (no canonical address/contact master exists yet, the same
 * shape server/contracts/customer-booking-request's own BookingLocationSchema
 * already established for a sibling capability).
 */

import { z } from "zod";

export const SHIPMENT_ORDER_STATUSES = ["draft", "confirmed", "cancelled"] as const;
export const ShipmentOrderStatusSchema = z.enum(SHIPMENT_ORDER_STATUSES);
export type ShipmentOrderStatus = z.infer<typeof ShipmentOrderStatusSchema>;

// --- Customer-safe shipment order projection row schema ---

export const CustomerShipmentOrderSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  jobOrderId: z.string().uuid(),
  shipmentNumber: z.string(),
  status: ShipmentOrderStatusSchema,
  shipperAccountId: z.string().uuid(),
  consigneeSnapshot: z.record(z.string(), z.unknown()),
  notifyPartySnapshot: z.record(z.string(), z.unknown()).nullable(),
  cargoServiceSnapshot: z.record(z.string(), z.unknown()),
  serviceType: z.string(),
  mode: z.string(),
  origin: z.string(),
  destination: z.string(),
  plannedPickupAt: z.string().nullable(),
  plannedDeliveryAt: z.string().nullable(),
  allocatedQuantity: z.number().nullable(),
  allocatedWeightKg: z.number().nullable(),
  allocatedVolumeCbm: z.number().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CustomerShipmentOrder = z.infer<typeof CustomerShipmentOrderSchema>;

export function parseCustomerShipmentOrder(row: Record<string, unknown>): CustomerShipmentOrder {
  return CustomerShipmentOrderSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    jobOrderId: row.job_order_id,
    shipmentNumber: row.shipment_number,
    status: row.status,
    shipperAccountId: row.shipper_account_id,
    consigneeSnapshot: row.consignee_snapshot ?? {},
    notifyPartySnapshot: row.notify_party_snapshot ?? null,
    cargoServiceSnapshot: row.cargo_service_snapshot ?? {},
    serviceType: row.service_type,
    mode: row.mode,
    origin: row.origin,
    destination: row.destination,
    plannedPickupAt: row.planned_pickup_at ?? null,
    plannedDeliveryAt: row.planned_delivery_at ?? null,
    allocatedQuantity: row.allocated_quantity === null || row.allocated_quantity === undefined ? null : Number(row.allocated_quantity),
    allocatedWeightKg: row.allocated_weight_kg === null || row.allocated_weight_kg === undefined ? null : Number(row.allocated_weight_kg),
    allocatedVolumeCbm: row.allocated_volume_cbm === null || row.allocated_volume_cbm === undefined ? null : Number(row.allocated_volume_cbm),
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const CustomerShipmentOrderCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerShipmentOrderCursor = z.input<typeof CustomerShipmentOrderCursorSchema>;

// --- Change request ---

export const SHIPMENT_CHANGE_REQUEST_TYPES = ["reschedule", "cancel", "other"] as const;
export const ShipmentChangeRequestTypeSchema = z.enum(SHIPMENT_CHANGE_REQUEST_TYPES);
export type ShipmentChangeRequestType = z.infer<typeof ShipmentChangeRequestTypeSchema>;

export const SHIPMENT_CHANGE_REQUEST_STATUSES = ["submitted", "acknowledged", "resolved", "rejected"] as const;
export const ShipmentChangeRequestStatusSchema = z.enum(SHIPMENT_CHANGE_REQUEST_STATUSES);
export type ShipmentChangeRequestStatus = z.infer<typeof ShipmentChangeRequestStatusSchema>;

export const CustomerShipmentChangeRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  requestedByAuthUserId: z.string().uuid(),
  requestType: ShipmentChangeRequestTypeSchema,
  details: z.string().nullable(),
  status: ShipmentChangeRequestStatusSchema,
  idempotencyKey: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
  staffResponse: z.string().nullable(),
  staffRespondedBy: z.string().nullable(),
  staffRespondedAt: z.string().nullable(),
});
export type CustomerShipmentChangeRequest = z.infer<typeof CustomerShipmentChangeRequestSchema>;

export function parseCustomerShipmentChangeRequest(row: Record<string, unknown>): CustomerShipmentChangeRequest {
  return CustomerShipmentChangeRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    accountId: row.account_id,
    shipmentOrderId: row.shipment_order_id,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestType: row.request_type,
    details: row.details ?? null,
    status: row.status,
    idempotencyKey: row.idempotency_key ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    staffResponse: row.staff_response ?? null,
    staffRespondedBy: row.staff_responded_by ?? null,
    staffRespondedAt: row.staff_responded_at ?? null,
  });
}

export const CustomerShipmentChangeRequestCursorSchema = CustomerShipmentOrderCursorSchema;
export type CustomerShipmentChangeRequestCursor = z.input<typeof CustomerShipmentChangeRequestCursorSchema>;

// --- Mutation input schemas ---

export const RequestCustomerShipmentOrderChangeInputSchema = z.object({
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  requestType: ShipmentChangeRequestTypeSchema,
  details: z.string().min(1),
  idempotencyKey: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestCustomerShipmentOrderChangeInput = z.input<typeof RequestCustomerShipmentOrderChangeInputSchema>;

export const RespondToCustomerShipmentOrderChangeRequestInputSchema = z.object({
  changeRequestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  toStatus: z.enum(["acknowledged", "resolved", "rejected"]),
  staffResponse: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RespondToCustomerShipmentOrderChangeRequestInput = z.input<typeof RespondToCustomerShipmentOrderChangeRequestInputSchema>;
