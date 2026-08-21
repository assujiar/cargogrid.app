/**
 * Enterprise Maps Geocoding and Routing queries (IAE-015, Prompt 343). Thin,
 * typed wrappers around app.list_geocode_requests_for_tenant /
 * app.get_maps_provider_dispatch_info / app.get_maps_provider_credential
 * (supabase/migrations/20260805020000_create_intelligence_maps_gps_telematics_integrations.sql).
 */

import {
  ListGeocodeRequestsForTenantInputSchema,
  parseGeocodeRequest,
  parseMapsProviderDispatchInfo,
  type ListGeocodeRequestsForTenantInput,
  type GeocodeRequest,
  type MapsProviderDispatchInfo,
} from "../contracts/maps-geocoding/maps-geocoding.ts";

export interface MapsGeocodingQueryRpcClient {
  rpc(
    fn: "list_geocode_requests_for_tenant" | "get_maps_provider_dispatch_info" | "get_maps_provider_credential",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class MapsGeocodingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MapsGeocodingQueryError";
  }
}

/** Authority: Supreme or the tenant's own active tenant_admin (app.check_api_webhook_admin_authority). */
export async function listGeocodeRequestsForTenant(client: MapsGeocodingQueryRpcClient, input: ListGeocodeRequestsForTenantInput): Promise<GeocodeRequest[]> {
  const parsedInput = ListGeocodeRequestsForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_geocode_requests_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new MapsGeocodingQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new MapsGeocodingQueryError("list_geocode_requests_for_tenant returned a non-array result");
  }
  return data.map((row) => parseGeocodeRequest(row as Record<string, unknown>));
}

/** IAE-015: the real geocode/route client's own minimal read -- never the raw credential. Returns null if no active maps_geocoding connection exists for this tenant. */
export async function getMapsProviderDispatchInfo(client: MapsGeocodingQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<MapsProviderDispatchInfo | null> {
  const { data, error } = await client.rpc("get_maps_provider_dispatch_info", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new MapsGeocodingQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseMapsProviderDispatchInfo(row as Record<string, unknown>);
}

/** IAE-015: service_role-only. Returns null if the connection has no stored credential. */
export async function getMapsProviderCredential(client: MapsGeocodingQueryRpcClient, connectionId: string): Promise<string | null> {
  const { data, error } = await client.rpc("get_maps_provider_credential", { p_connection_id: connectionId });
  if (error) {
    throw new MapsGeocodingQueryError(error.message);
  }
  return typeof data === "string" ? data : null;
}
