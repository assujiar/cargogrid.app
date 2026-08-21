/**
 * The real enterprise geocoding client (IAE-015, Prompt 343) -- the THIRD
 * real outbound HTTP client in this repository, after IAE-012's webhook
 * worker and IAE-014's notification worker. Unlike those two, this is NOT an
 * `app.jobs` consumer -- geocoding is a live, synchronous request/response
 * call (address in, coordinates out), so there is no queue/retry/DLQ shape
 * here; the caller awaits a real result directly.
 *
 * GPS/telematics provider INGESTION itself is unchanged by this checkpoint
 * (`ADR-0025` Part B) -- `app/api/webhooks/third-party-gps/[connectionId]/route.ts`
 * remains the sole inbound receiver; this module is the new, genuinely
 * distinct OUTBOUND direction (CargoGrid calling OUT to a maps provider).
 *
 * Reuses ../webhooks/ssrf-guard.server.ts's checkWebhookDispatchUrlIsSafe
 * directly, the same proactive reuse IAE-014 already established.
 */

import { getMapsProviderDispatchInfo, getMapsProviderCredential, type MapsGeocodingQueryRpcClient } from "../../server/queries/maps-geocoding.ts";
import { recordGeocodeRequest, type MapsGeocodingMutationRpcClient } from "../../server/mutations/maps-geocoding.ts";
import { checkWebhookDispatchUrlIsSafe, type SsrfCheckResult } from "../webhooks/ssrf-guard.server.ts";

const REQUEST_TIMEOUT_MS = 10_000;

export type MapsProviderDispatchUrlSafetyChecker = (rawUrl: string) => Promise<SsrfCheckResult>;

export type GeocodeAddressRpcClient = MapsGeocodingQueryRpcClient & MapsGeocodingMutationRpcClient;

export interface GeocodeAddressResult {
  readonly success: boolean;
  readonly latitude: number | null;
  readonly longitude: number | null;
  readonly formattedAddress: string | null;
  readonly errorMessage: string | null;
}

interface GeocodeAddressOptions {
  readonly tenantId: string;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
  readonly address: string;
}

function placeholderCost(payloadLength: number): number {
  return Math.round((0.002 + payloadLength * 0.000005) * 10000) / 10000;
}

/**
 * Real, synchronous geocode dispatch. Never throws for a delivery-side
 * failure (no connection configured, HTTP error, timeout, unsafe URL) --
 * those are real, expected outcomes reported back to app.record_geocode_request
 * and returned to the caller as `success: false`.
 */
export async function geocodeAddress(client: GeocodeAddressRpcClient, options: GeocodeAddressOptions, checkUrlSafety: MapsProviderDispatchUrlSafetyChecker = checkWebhookDispatchUrlIsSafe): Promise<GeocodeAddressResult> {
  const { tenantId, actorAuthUserId, actorLabel, address } = options;
  const queryPayload = { address };

  const dispatchInfo = await getMapsProviderDispatchInfo(client, tenantId, actorAuthUserId);
  if (!dispatchInfo || dispatchInfo.connectionStatus !== "active") {
    const errorMessage = "no active maps_geocoding provider connection configured for this tenant";
    await recordGeocodeRequest(client, { tenantId, connectionId: dispatchInfo?.connectionId ?? "00000000-0000-0000-0000-000000000000", requestType: "geocode", queryPayload, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { success: false, latitude: null, longitude: null, formattedAddress: null, errorMessage };
  }

  const apiUrl = typeof dispatchInfo.connectionConfig.apiUrl === "string" ? dispatchInfo.connectionConfig.apiUrl : null;
  if (!apiUrl) {
    const errorMessage = "maps_geocoding provider connection has no apiUrl configured";
    await recordGeocodeRequest(client, { tenantId, connectionId: dispatchInfo.connectionId, requestType: "geocode", queryPayload, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { success: false, latitude: null, longitude: null, formattedAddress: null, errorMessage };
  }

  const urlSafety = await checkUrlSafety(apiUrl);
  if (!urlSafety.safe) {
    const errorMessage = `refusing to dispatch: ${urlSafety.reason ?? "provider apiUrl failed the delivery-time safety check"}`;
    await recordGeocodeRequest(client, { tenantId, connectionId: dispatchInfo.connectionId, requestType: "geocode", queryPayload, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { success: false, latitude: null, longitude: null, formattedAddress: null, errorMessage };
  }

  const credential = await getMapsProviderCredential(client, dispatchInfo.connectionId);
  if (!credential) {
    const errorMessage = "maps_geocoding provider connection has no stored credential";
    await recordGeocodeRequest(client, { tenantId, connectionId: dispatchInfo.connectionId, requestType: "geocode", queryPayload, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { success: false, latitude: null, longitude: null, formattedAddress: null, errorMessage };
  }

  const requestPayload = JSON.stringify({ address });
  const controller = new AbortController();
  const timeoutHandle = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetch(apiUrl, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${credential}` },
      body: requestPayload,
      signal: controller.signal,
      redirect: "manual",
    });
  } catch (error) {
    const errorMessage = error instanceof Error && error.name === "AbortError" ? `request timed out after ${REQUEST_TIMEOUT_MS}ms` : error instanceof Error ? error.message : "unknown fetch error";
    await recordGeocodeRequest(client, { tenantId, connectionId: dispatchInfo.connectionId, requestType: "geocode", queryPayload, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { success: false, latitude: null, longitude: null, formattedAddress: null, errorMessage };
  } finally {
    clearTimeout(timeoutHandle);
  }

  if (response.status < 200 || response.status >= 300) {
    const errorMessage = `maps provider responded with HTTP ${response.status}`;
    await recordGeocodeRequest(client, { tenantId, connectionId: dispatchInfo.connectionId, requestType: "geocode", queryPayload, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { success: false, latitude: null, longitude: null, formattedAddress: null, errorMessage };
  }

  let body: { latitude?: unknown; longitude?: unknown; formattedAddress?: unknown };
  try {
    body = await response.json();
  } catch {
    const errorMessage = "maps provider returned a non-JSON response body";
    await recordGeocodeRequest(client, { tenantId, connectionId: dispatchInfo.connectionId, requestType: "geocode", queryPayload, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { success: false, latitude: null, longitude: null, formattedAddress: null, errorMessage };
  }

  const latitude = typeof body.latitude === "number" ? body.latitude : null;
  const longitude = typeof body.longitude === "number" ? body.longitude : null;
  const formattedAddress = typeof body.formattedAddress === "string" ? body.formattedAddress : null;
  if (latitude === null || longitude === null) {
    const errorMessage = "maps provider response is missing latitude/longitude";
    await recordGeocodeRequest(client, { tenantId, connectionId: dispatchInfo.connectionId, requestType: "geocode", queryPayload, status: "failed", errorMessage, actorAuthUserId, actorLabel });
    return { success: false, latitude: null, longitude: null, formattedAddress: null, errorMessage };
  }

  await recordGeocodeRequest(client, {
    tenantId,
    connectionId: dispatchInfo.connectionId,
    requestType: "geocode",
    queryPayload,
    status: "success",
    resultPayload: { latitude, longitude, formattedAddress },
    providerUnitCostAmount: placeholderCost(requestPayload.length),
    currency: "USD",
    actorAuthUserId,
    actorLabel,
  });

  return { success: true, latitude, longitude, formattedAddress, errorMessage: null };
}
