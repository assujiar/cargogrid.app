/**
 * Customer Shipment Tracking read query (CPL-305, CG-S13-CPL-007). A thin,
 * typed wrapper around the one RPC in supabase/migrations/20260801060000_
 * create_customer_portal_shipment_tracking.sql, mirroring server/queries/
 * customer-shipment-order.ts's own wrapper shape exactly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseCustomerShipmentTracking, type CustomerShipmentTracking } from "../contracts/customer-shipment-tracking/customer-shipment-tracking.ts";

export type CustomerShipmentTrackingQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["record_not_found", "actor_identity_mismatch"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type CustomerShipmentTrackingQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class CustomerShipmentTrackingQueryError extends Error {
  readonly code: CustomerShipmentTrackingQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerShipmentTrackingQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

/**
 * The composed tracking view for a single permitted shipment order --
 * customer-visible milestone timeline, arbitrated vehicle position (gated on
 * tenant entitlement + the active leg's own customer-visible policy flag),
 * a coarsened ETA, and a freshness/degraded marker. Throws record_not_found
 * (anti-enumerating) whether the id genuinely does not exist, belongs to
 * another tenant, or exists but is outside this identity's resolved scope --
 * identical shape to getCustomerShipmentOrder (CPL-304), never distinguished
 * by the caller.
 */
export async function getCustomerShipmentTracking(client: CustomerShipmentTrackingQueryClient, tenantId: string, actorAuthUserId: string, shipmentOrderId: string): Promise<CustomerShipmentTracking> {
  const { data, error } = await client.rpc("get_customer_shipment_tracking", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_shipment_order_id: shipmentOrderId,
  });
  if (error) {
    throw new CustomerShipmentTrackingQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerShipmentTrackingQueryError("query_failed: get_customer_shipment_tracking returned no row");
  }
  return parseCustomerShipmentTracking(row as Record<string, unknown>);
}
