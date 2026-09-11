/**
 * Land, Air and Sea Baseline read queries (OPS-171, CG-S8-OPS-005).
 * CG-AUDIT-2026-09-02 O1 remediation (cluster 3 batch 4,
 * 20260911040000_close_o1_query_layer_cluster3_batch4_shipment_order_capacity_exceptions.sql):
 * reads go through a thin, security-invoker RPC wrapper (app is not exposed to
 * PostgREST, so a `.from()` call against app.shipment_mode_profiles has never
 * worked in production) -- no masked column exists (this is canonical
 * operational data captured first-hand, never a re-entered Commercial
 * figure), so the wrapper is a plain, RLS-scoped passthrough.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseShipmentModeProfile, type ShipmentModeProfile } from "../contracts/shipment-mode-baseline/shipment-mode-baseline.ts";

export type ShipmentModeBaselineQueryTableClient = Pick<SupabaseClient, "rpc">;

export class ShipmentModeBaselineQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ShipmentModeBaselineQueryError";
  }
}

/** The one mode profile for a Shipment Order, if one has been set and RLS admits it -- returns null (never an error) otherwise. */
export async function getShipmentModeProfile(client: ShipmentModeBaselineQueryTableClient, shipmentOrderId: string): Promise<ShipmentModeProfile | null> {
  const { data, error } = await client.rpc("get_shipment_mode_profile", { p_shipment_order_id: shipmentOrderId });
  if (error) {
    throw new ShipmentModeBaselineQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseShipmentModeProfile(row as Record<string, unknown>);
}
