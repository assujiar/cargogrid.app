/**
 * WMS Outbound (ship-execution) read queries (ATW-019, CG-S10-ATW-019). Thin, typed
 * wrappers around app.get_wms_outbound_shipment/app.list_wms_outbound_shipments/
 * app.list_wms_shipment_packages/app.list_wms_shipment_issue_lines/
 * app.get_wms_billing_eligibility_event/app.list_wms_billing_eligibility_events
 * (supabase/migrations/20260730260000_create_advanced_tms_wms_outbound.sql).
 *
 * Distinct filename from server/queries/wms-outbound-order.ts (ATW-016A).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseWmsOutboundShipment,
  parseWmsShipmentPackage,
  parseWmsShipmentIssueLine,
  parseWmsBillingEligibilityEvent,
  type WmsOutboundShipment,
  type WmsShipmentPackage,
  type WmsShipmentIssueLine,
  type WmsBillingEligibilityEvent,
  type WmsOutboundShipmentStatus,
} from "../contracts/wms-outbound/wms-outbound.ts";

export type WmsOutboundQueryClient = Pick<SupabaseClient, "rpc">;

export class WmsOutboundQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WmsOutboundQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Single-row read by id, RBAC- and record/owner-scope-gated. */
export async function getWmsOutboundShipment(client: WmsOutboundQueryClient, shipmentId: string, actorAuthUserId: string): Promise<WmsOutboundShipment> {
  const { data, error } = await client.rpc("get_wms_outbound_shipment", { p_shipment_id: shipmentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsOutboundQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WmsOutboundQueryError("get_wms_outbound_shipment returned no row");
  }
  return parseWmsOutboundShipment(row);
}

/** Bounded (default 50, hard-capped 200 server-side), record- and owner-scoped, optionally narrowed to one outbound order/warehouse/owner/status. */
export async function listWmsOutboundShipments(
  client: WmsOutboundQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: {
    outboundOrderId?: string | null;
    warehouseId?: string | null;
    ownerAccountId?: string | null;
    statusFilter?: WmsOutboundShipmentStatus | null;
    limit?: number;
  },
): Promise<WmsOutboundShipment[]> {
  const { data, error } = await client.rpc("list_wms_outbound_shipments", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_outbound_order_id: options?.outboundOrderId ?? null,
    p_warehouse_id: options?.warehouseId ?? null,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new WmsOutboundQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsOutboundShipment);
}

/** Every package staged on one shipment, ordered by added_at. */
export async function listWmsShipmentPackages(client: WmsOutboundQueryClient, shipmentId: string, actorAuthUserId: string): Promise<WmsShipmentPackage[]> {
  const { data, error } = await client.rpc("list_wms_shipment_packages", { p_shipment_id: shipmentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsOutboundQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsShipmentPackage);
}

/** The real traceability read -- one row per issued package line, carrying pick_task_id/reservation_id back to ATW-017's own allocation. */
export async function listWmsShipmentIssueLines(client: WmsOutboundQueryClient, shipmentId: string, actorAuthUserId: string): Promise<WmsShipmentIssueLine[]> {
  const { data, error } = await client.rpc("list_wms_shipment_issue_lines", { p_shipment_id: shipmentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsOutboundQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsShipmentIssueLine);
}

/** Single-row read by id, RBAC- and record/owner-scope-gated. Staff-facing only -- a future Finance-domain capability is the intended real consumer. */
export async function getWmsBillingEligibilityEvent(client: WmsOutboundQueryClient, eventId: string, actorAuthUserId: string): Promise<WmsBillingEligibilityEvent> {
  const { data, error } = await client.rpc("get_wms_billing_eligibility_event", { p_event_id: eventId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new WmsOutboundQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new WmsOutboundQueryError("get_wms_billing_eligibility_event returned no row");
  }
  return parseWmsBillingEligibilityEvent(row);
}

/** Bounded (default 50, hard-capped 200 server-side), record- and owner-scoped, optionally narrowed to one outbound order/owner. */
export async function listWmsBillingEligibilityEvents(
  client: WmsOutboundQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { outboundOrderId?: string | null; ownerAccountId?: string | null; limit?: number },
): Promise<WmsBillingEligibilityEvent[]> {
  const { data, error } = await client.rpc("list_wms_billing_eligibility_events", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_outbound_order_id: options?.outboundOrderId ?? null,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new WmsOutboundQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseWmsBillingEligibilityEvent);
}
