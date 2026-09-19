/**
 * Multi-Leg and Multimodal Shipment read queries (ATW-221, CG-S10-ATW-002). No
 * masked column exists on any of these four tables. Stops go through
 * app.get_shipment_leg_stops to receive a computed GeoJSON projection instead of
 * the raw geography wire format; legs, cargo allocations, and custody events are
 * RPC-backed via app.list_shipment_legs / app.get_shipment_leg_cargo_allocation /
 * app.list_shipment_leg_custody_events (CG-AUDIT-2026-09-02 O1 cluster 3 batch 2)
 * -- the app schema is not exposed to PostgREST, so a direct table read never
 * worked for any of the four.
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

export type MultiLegShipmentQueryTableClient = Pick<SupabaseClient, "rpc">;

export class MultiLegShipmentQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MultiLegShipmentQueryError";
  }
}

/** Every leg for one Shipment Order, ordered by sequence_no ascending -- including a cancelled leg, which permanently reserves its own sequence_no (never reordered or excluded). */
export async function listShipmentLegs(client: MultiLegShipmentQueryTableClient, shipmentOrderId: string, actorAuthUserId: string): Promise<ShipmentLeg[]> {
  const { data, error } = await client.rpc("list_shipment_legs", {
    p_shipment_order_id: shipmentOrderId,
    p_actor_auth_user_id: actorAuthUserId,
  });
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
export async function getShipmentLegCargoAllocation(client: MultiLegShipmentQueryTableClient, shipmentLegId: string, actorAuthUserId: string): Promise<ShipmentLegCargoAllocation | null> {
  const { data, error } = await client.rpc("get_shipment_leg_cargo_allocation", {
    p_shipment_leg_id: shipmentLegId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new MultiLegShipmentQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseShipmentLegCargoAllocation(row as Record<string, unknown>) : null;
}

/** Every custody event for one leg, ordered oldest first (append-only). */
export async function listShipmentLegCustodyEvents(client: MultiLegShipmentQueryTableClient, shipmentLegId: string, actorAuthUserId: string): Promise<ShipmentLegCustodyEvent[]> {
  const { data, error } = await client.rpc("list_shipment_leg_custody_events", {
    p_shipment_leg_id: shipmentLegId,
    p_actor_auth_user_id: actorAuthUserId,
  });
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
