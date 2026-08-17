/**
 * Customer Shipment Alert contract (CPL-306, CG-S13-CPL-008, Prompt 306).
 * Mirrors supabase/migrations/20260801070000_create_customer_portal_
 * shipment_monitoring.sql's RPC surface: app.subscribe_customer_shipment_
 * alert / app.unsubscribe_customer_shipment_alert / app.list_customer_
 * shipment_alert_subscriptions (the new, portal-owned preference table) and
 * app.list_customer_shipment_alerts (a thin wrapper over PLT-127's own
 * app.list_notifications_for_recipient -- reuses server/contracts/
 * notification/notification.ts's own Notification type/parser rather than
 * duplicating that row shape).
 *
 * Emission (the actual queuing of an alert against a real milestone/
 * exception/tracking-health event) is explicitly out of scope this
 * checkpoint (migration header decision 8) -- this contract only covers
 * subscription CRUD and alert-history read.
 */

import { z } from "zod";
import { NotificationSchema, parseNotification, type Notification } from "../notification/notification.ts";

export const CUSTOMER_SHIPMENT_ALERT_TYPES = ["milestone_delay", "exception", "no_fresh_position", "tracking_restored", "delivery", "document_available"] as const;
export const CustomerShipmentAlertTypeSchema = z.enum(CUSTOMER_SHIPMENT_ALERT_TYPES);
export type CustomerShipmentAlertType = z.infer<typeof CustomerShipmentAlertTypeSchema>;

export const CUSTOMER_SHIPMENT_ALERT_SUBSCRIPTION_STATUSES = ["active", "unsubscribed"] as const;
export const CustomerShipmentAlertSubscriptionStatusSchema = z.enum(CUSTOMER_SHIPMENT_ALERT_SUBSCRIPTION_STATUSES);
export type CustomerShipmentAlertSubscriptionStatus = z.infer<typeof CustomerShipmentAlertSubscriptionStatusSchema>;

/**
 * The full notification_type_code registered for each alert_type by this
 * migration's own bootstrap insert (design decision 7) -- 'shipment_alert_'
 * prefix, e.g. 'milestone_delay' -> 'shipment_alert_milestone_delay'.
 */
export function customerShipmentAlertNotificationTypeCode(alertType: CustomerShipmentAlertType): string {
  return `shipment_alert_${alertType}`;
}

export const CustomerShipmentAlertSubscriptionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  authUserId: z.string().uuid(),
  alertType: CustomerShipmentAlertTypeSchema,
  status: CustomerShipmentAlertSubscriptionStatusSchema,
  createdAt: z.string(),
  updatedAt: z.string(),
  recordVersion: z.number().int().positive(),
});
export type CustomerShipmentAlertSubscription = z.infer<typeof CustomerShipmentAlertSubscriptionSchema>;

export function parseCustomerShipmentAlertSubscription(row: Record<string, unknown>): CustomerShipmentAlertSubscription {
  return CustomerShipmentAlertSubscriptionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    accountId: row.account_id,
    shipmentOrderId: row.shipment_order_id,
    authUserId: row.auth_user_id,
    alertType: row.alert_type,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    recordVersion: row.record_version,
  });
}

export const CustomerShipmentAlertSubscriptionCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerShipmentAlertSubscriptionCursor = z.input<typeof CustomerShipmentAlertSubscriptionCursorSchema>;

export const CustomerShipmentAlertCursorSchema = z
  .object({
    cursorCreatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorCreatedAt, {
    message: "cursorCreatedAt is required when cursorId is supplied",
    path: ["cursorCreatedAt"],
  });
export type CustomerShipmentAlertCursor = z.input<typeof CustomerShipmentAlertCursorSchema>;

// --- Mutation input schemas ---

export const SubscribeCustomerShipmentAlertInputSchema = z.object({
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  alertType: CustomerShipmentAlertTypeSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubscribeCustomerShipmentAlertInput = z.input<typeof SubscribeCustomerShipmentAlertInputSchema>;

export const UnsubscribeCustomerShipmentAlertInputSchema = SubscribeCustomerShipmentAlertInputSchema;
export type UnsubscribeCustomerShipmentAlertInput = z.input<typeof UnsubscribeCustomerShipmentAlertInputSchema>;

/** Re-exported so callers of listCustomerShipmentAlerts don't need a separate import from ../notification/notification.ts. */
export { NotificationSchema, parseNotification };
export type { Notification };
