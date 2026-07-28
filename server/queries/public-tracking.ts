/**
 * Basic Public and Customer Tracking read queries (OPS-180, CG-S8-OPS-014). A thin,
 * typed wrapper around the one public RPC, app.lookup_public_shipment_tracking, plus
 * a direct RLS-scoped read of app.shipment_tracking_tokens for the internal management
 * panel (never exposes raw_token -- that is returned exactly once, at issuance).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parsePublicShipmentTrackingResult,
  parseShipmentTrackingToken,
  LookupPublicShipmentTrackingInputSchema,
  type PublicShipmentTrackingResult,
  type LookupPublicShipmentTrackingInput,
  type ShipmentTrackingToken,
} from "../contracts/public-tracking/public-tracking.ts";

export type PublicTrackingQueryClient = Pick<SupabaseClient, "rpc" | "from">;

export class PublicTrackingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PublicTrackingQueryError";
  }
}

/** The current active token's metadata (status/expiry), if any -- for the Operations management panel. Never the raw token. */
export async function getActiveShipmentTrackingToken(client: PublicTrackingQueryClient, shipmentOrderId: string): Promise<ShipmentTrackingToken | null> {
  const { data, error } = await client.from("shipment_tracking_tokens").select("*").eq("shipment_order_id", shipmentOrderId).eq("status", "active").maybeSingle();
  if (error) {
    throw new PublicTrackingQueryError(error.message);
  }
  return data ? parseShipmentTrackingToken(data as Record<string, unknown>) : null;
}

/**
 * The one public, unauthenticated read this repository exposes -- authorization is
 * the token itself. Always resolves to a row (never throws for a bad/expired/revoked
 * token or a rate-limited client) -- callers must branch on result.lookupStatus.
 */
export async function lookupPublicShipmentTracking(client: PublicTrackingQueryClient, input: LookupPublicShipmentTrackingInput): Promise<PublicShipmentTrackingResult> {
  const parsedInput = LookupPublicShipmentTrackingInputSchema.parse(input);
  const { data, error } = await client.rpc("lookup_public_shipment_tracking", {
    p_raw_token: parsedInput.rawToken,
    p_client_key: parsedInput.clientKey,
  });
  if (error) {
    throw new PublicTrackingQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new PublicTrackingQueryError("lookup_public_shipment_tracking returned no row");
  }
  return parsePublicShipmentTrackingResult(row as Record<string, unknown>);
}
