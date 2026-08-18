/**
 * Customer Shipment Alert read queries (CPL-306, CG-S13-CPL-008). Thin,
 * typed wrappers around every read RPC in supabase/migrations/
 * 20260801070000_create_customer_portal_shipment_monitoring.sql, mirroring
 * server/queries/customer-shipment-order.ts's own wrapper shape exactly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCustomerShipmentAlertSubscription,
  parseNotification,
  type CustomerShipmentAlertSubscription,
  type Notification,
} from "../contracts/customer-shipment-alert/customer-shipment-alert.ts";

export type CustomerShipmentAlertQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["actor_identity_mismatch", "invalid_cursor"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type CustomerShipmentAlertQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class CustomerShipmentAlertQueryError extends Error {
  readonly code: CustomerShipmentAlertQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerShipmentAlertQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

/**
 * Self-only, live-rescoped on every row against this identity's CURRENT
 * account scope (never an error for zero scope or an out-of-scope filter --
 * deny-by-default, an empty array).
 */
export async function listCustomerShipmentAlertSubscriptions(
  client: CustomerShipmentAlertQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { shipmentOrderId?: string | null; cursorUpdatedAt?: string | null; cursorId?: string | null; limit?: number },
): Promise<CustomerShipmentAlertSubscription[]> {
  const { data, error } = await client.rpc("list_customer_shipment_alert_subscriptions", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_shipment_order_id: options?.shipmentOrderId ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerShipmentAlertQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerShipmentAlertSubscription);
}

/**
 * A thin, self-only wrapper over app.list_notifications_for_recipient
 * (PLT-127), filtered to this capability's own 6 notification_type_code
 * values, keyset-paginated (created_at desc, id desc) by the RPC itself.
 * Returns app.notifications rows (server/contracts/notification/
 * notification.ts's own Notification shape) -- never a bespoke alert row
 * type, since this capability composes the existing engine rather than
 * re-modeling its output.
 */
export async function listCustomerShipmentAlerts(
  client: CustomerShipmentAlertQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { shipmentOrderId?: string | null; unreadOnly?: boolean; cursorCreatedAt?: string | null; cursorId?: string | null; limit?: number },
): Promise<Notification[]> {
  const { data, error } = await client.rpc("list_customer_shipment_alerts", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_shipment_order_id: options?.shipmentOrderId ?? null,
    p_unread_only: options?.unreadOnly ?? false,
    p_cursor_created_at: options?.cursorCreatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerShipmentAlertQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseNotification);
}
