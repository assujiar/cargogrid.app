/**
 * Land, Air and Sea Baseline read queries (OPS-171, CG-S8-OPS-005). Thin, typed
 * wrapper around app.shipment_mode_profiles -- no masked column exists (this is
 * canonical operational data captured first-hand, never a re-entered Commercial
 * figure), so reads go directly against the base table, RLS-scoped.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseShipmentModeProfile, type ShipmentModeProfile } from "../contracts/shipment-mode-baseline/shipment-mode-baseline.ts";

export type ShipmentModeBaselineQueryTableClient = Pick<SupabaseClient, "from">;

export class ShipmentModeBaselineQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ShipmentModeBaselineQueryError";
  }
}

/** The one mode profile for a Shipment Order, if one has been set and RLS admits it -- returns null (never an error) otherwise. */
export async function getShipmentModeProfile(client: ShipmentModeBaselineQueryTableClient, shipmentOrderId: string): Promise<ShipmentModeProfile | null> {
  const { data, error } = await client.from("shipment_mode_profiles").select("*").eq("shipment_order_id", shipmentOrderId).maybeSingle();
  if (error) {
    throw new ShipmentModeBaselineQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseShipmentModeProfile(data as Record<string, unknown>);
}
