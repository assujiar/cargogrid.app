/**
 * Carrier, Port, Airport and Customs Integrations queries (IAE-016, Prompt
 * 344). Thin, typed wrappers around app.list_logistics_partner_events_for_tenant /
 * app.get_logistics_partner_dispatch_info / app.get_logistics_partner_credential /
 * app.get_logistics_partner_connection_for_sync
 * (supabase/migrations/20260805030000_create_intelligence_carrier_port_airport_customs_integrations.sql).
 */

import {
  ListLogisticsPartnerEventsForTenantInputSchema,
  parseLogisticsPartnerEvent,
  parseLogisticsPartnerDispatchInfo,
  parseLogisticsPartnerConnectionForSync,
  type ListLogisticsPartnerEventsForTenantInput,
  type LogisticsPartnerEvent,
  type LogisticsPartnerDispatchInfo,
  type LogisticsPartnerConnectionForSync,
} from "../contracts/logistics-partner/logistics-partner.ts";

export interface LogisticsPartnerQueryRpcClient {
  rpc(
    fn: "list_logistics_partner_events_for_tenant" | "get_logistics_partner_dispatch_info" | "get_logistics_partner_credential" | "get_logistics_partner_connection_for_sync",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class LogisticsPartnerQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LogisticsPartnerQueryError";
  }
}

/** Authority: OPS:View for the tenant. */
export async function listLogisticsPartnerEventsForTenant(client: LogisticsPartnerQueryRpcClient, input: ListLogisticsPartnerEventsForTenantInput): Promise<LogisticsPartnerEvent[]> {
  const parsedInput = ListLogisticsPartnerEventsForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_logistics_partner_events_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new LogisticsPartnerQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new LogisticsPartnerQueryError("list_logistics_partner_events_for_tenant returned a non-array result");
  }
  return data.map((row) => parseLogisticsPartnerEvent(row as Record<string, unknown>));
}

/** The real outbound client's own minimal read -- never the raw credential. Returns null if no active connection exists for this adapter. */
export async function getLogisticsPartnerDispatchInfo(client: LogisticsPartnerQueryRpcClient, tenantId: string, actorAuthUserId: string, adapterCode: string): Promise<LogisticsPartnerDispatchInfo | null> {
  const { data, error } = await client.rpc("get_logistics_partner_dispatch_info", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_adapter_code: adapterCode });
  if (error) {
    throw new LogisticsPartnerQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseLogisticsPartnerDispatchInfo(row as Record<string, unknown>);
}

/** service_role-only. Returns null if the connection has no stored credential. */
export async function getLogisticsPartnerCredential(client: LogisticsPartnerQueryRpcClient, connectionId: string): Promise<string | null> {
  const { data, error } = await client.rpc("get_logistics_partner_credential", { p_connection_id: connectionId });
  if (error) {
    throw new LogisticsPartnerQueryError(error.message);
  }
  return typeof data === "string" ? data : null;
}

/** The real poll worker's own read -- no actor authority check (an already-authorized background job). Returns null if the connection does not exist. */
export async function getLogisticsPartnerConnectionForSync(client: LogisticsPartnerQueryRpcClient, connectionId: string): Promise<LogisticsPartnerConnectionForSync | null> {
  const { data, error } = await client.rpc("get_logistics_partner_connection_for_sync", { p_connection_id: connectionId });
  if (error) {
    throw new LogisticsPartnerQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseLogisticsPartnerConnectionForSync(row as Record<string, unknown>);
}
