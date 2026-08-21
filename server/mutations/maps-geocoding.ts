/**
 * Enterprise Maps Geocoding and Routing mutation primitives (IAE-015, Prompt
 * 343). Thin, typed wrapper around app.record_geocode_request
 * (supabase/migrations/20260805020000_create_intelligence_maps_gps_telematics_integrations.sql)
 * -- the real outbound client's own bounded adapter interface.
 */

import { RecordGeocodeRequestInputSchema, parseGeocodeRequest, type RecordGeocodeRequestInput, type GeocodeRequest } from "../contracts/maps-geocoding/maps-geocoding.ts";

export interface MapsGeocodingMutationRpcClient {
  rpc(fn: "record_geocode_request", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const MAPS_GEOCODING_KNOWN_MUTATION_ERROR_CODES = ["insufficient_authority", "geocode_invalid_cost_amount"] as const;
type KnownMapsGeocodingMutationErrorCode = (typeof MAPS_GEOCODING_KNOWN_MUTATION_ERROR_CODES)[number];
export type MapsGeocodingMutationErrorCode = KnownMapsGeocodingMutationErrorCode | "mutation_failed" | "invalid_response";

export class MapsGeocodingMutationError extends Error {
  readonly code: MapsGeocodingMutationErrorCode;

  constructor(code: MapsGeocodingMutationErrorCode, message: string) {
    super(message);
    this.name = "MapsGeocodingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): MapsGeocodingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (MAPS_GEOCODING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownMapsGeocodingMutationErrorCode) : "mutation_failed";
}

/** The bounded adapter interface a real outbound maps-provider call reports its outcome to. billed_amount is computed server-side, never trusted from the caller. */
export async function recordGeocodeRequest(client: MapsGeocodingMutationRpcClient, input: RecordGeocodeRequestInput): Promise<GeocodeRequest> {
  const parsedInput = RecordGeocodeRequestInputSchema.parse(input);
  const { data, error } = await client.rpc("record_geocode_request", {
    p_tenant_id: parsedInput.tenantId,
    p_connection_id: parsedInput.connectionId,
    p_request_type: parsedInput.requestType,
    p_query_payload: parsedInput.queryPayload,
    p_status: parsedInput.status,
    p_result_payload: parsedInput.resultPayload,
    p_provider_unit_cost_amount: parsedInput.providerUnitCostAmount,
    p_currency: parsedInput.currency,
    p_error_message: parsedInput.errorMessage,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new MapsGeocodingMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new MapsGeocodingMutationError("invalid_response", "record_geocode_request returned no row");
  }
  return parseGeocodeRequest(data as Record<string, unknown>);
}
