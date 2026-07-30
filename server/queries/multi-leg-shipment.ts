/**
 * Multi-Leg and Multimodal Shipment read queries (ATW-221, CG-S10-ATW-002). No
 * masked column exists on any of these four tables, so reads go directly against
 * the base tables (RLS-scoped) except for stops, which go through
 * app.get_shipment_leg_stops to receive a computed GeoJSON projection instead of
 * the raw geography wire format.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseShipmentLeg,
  parseShipmentLegStop,
  parseShipmentLegCargoAllocation,
  parseShipmentLegCustodyEvent,
  LegNetworkAggregateStateSchema,
  type ShipmentLeg,
  type ShipmentLegStop,
  type ShipmentLegCargoAllocation,
  type ShipmentLegCustodyEvent,
  type LegNetworkAggregateState,
} from "../contracts/multi-leg-shipment/multi-leg-shipment.ts";

export type MultiLegShipmentQueryTableClient = Pick<SupabaseClient, "from" | "rpc">;

export class MultiLegShipmentQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MultiLegShipmentQueryError";
  }
}

/** Every non-cancelled-first leg for one Shipment Order, ordered by sequence_no ascending. */
export async function listShipmentLegs(client: MultiLegShipmentQueryTableClient, shipmentOrderId: string): Promise<ShipmentLeg[]> {
  const { data, error } = await client.from("shipment_legs").select("*").eq("shipment_order_id", shipmentOrderId).order("sequence_no", { ascending: true });
  if (error) {
    throw new MultiLegShipmentQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseShipmentLeg(row));
}

/** Every stop for one leg, ordered by stop_sequence ascending, with location serialized as GeoJSON. */
export async function listShipmentLegStops(client: MultiLegShipmentQueryTableClient, shipmentLegId: string): Promise<ShipmentLegStop[]> {
  const { data, error } = await client.rpc("get_shipment_leg_stops", { p_shipment_leg_id: shipmentLegId });
  if (error) {
    throw new MultiLegShipmentQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseShipmentLegStop(row));
}

/** The one cargo allocation for one leg, if any. */
export async function getShipmentLegCargoAllocation(client: MultiLegShipmentQueryTableClient, shipmentLegId: string): Promise<ShipmentLegCargoAllocation | null> {
  const { data, error } = await client.from("shipment_leg_cargo_allocations").select("*").eq("shipment_leg_id", shipmentLegId).maybeSingle();
  if (error) {
    throw new MultiLegShipmentQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseShipmentLegCargoAllocation(data as Record<string, unknown>);
}

/** Every custody event for one leg, ordered oldest first (append-only). */
export async function listShipmentLegCustodyEvents(client: MultiLegShipmentQueryTableClient, shipmentLegId: string): Promise<ShipmentLegCustodyEvent[]> {
  const { data, error } = await client.from("shipment_leg_custody_events").select("*").eq("shipment_leg_id", shipmentLegId).order("sequence_no", { ascending: true });
  if (error) {
    throw new MultiLegShipmentQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseShipmentLegCustodyEvent(row));
}

/** The live-derived aggregate network state for one Shipment Order -- never stored, so it can never drift. */
export async function getShipmentLegNetworkState(client: MultiLegShipmentQueryTableClient, shipmentOrderId: string): Promise<LegNetworkAggregateState> {
  const { data, error } = await client.rpc("get_shipment_leg_network_state", { p_shipment_order_id: shipmentOrderId });
  if (error) {
    throw new MultiLegShipmentQueryError(error.message);
  }
  return LegNetworkAggregateStateSchema.parse(data);
}
