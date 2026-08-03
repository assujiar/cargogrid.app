/**
 * Geofence, route deviation, milestone candidate, and exception signal read queries
 * (ATW-226G). Thin, typed wrappers around app.get_shipment_milestone_candidates/
 * app.get_shipment_exception_signals/app.get_shipment_leg_geofence_state/app.get_
 * shipment_leg_route_deviation_state -- every one authority-gated (OPS:View +
 * can_access_record) inside the RPC itself, mirroring OPS-173's own app.get_shipment_
 * milestone_timeline pattern.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseShipmentMilestoneCandidate,
  parseShipmentExceptionSignal,
  parseShipmentLegStopGeofenceState,
  parseShipmentLegRouteDeviationState,
  GetShipmentMilestoneCandidatesInputSchema,
  GetShipmentExceptionSignalsInputSchema,
  GetShipmentLegGeofenceStateInputSchema,
  GetShipmentLegRouteDeviationStateInputSchema,
  type ShipmentMilestoneCandidate,
  type ShipmentExceptionSignal,
  type ShipmentLegStopGeofenceState,
  type ShipmentLegRouteDeviationState,
  type GetShipmentMilestoneCandidatesInput,
  type GetShipmentExceptionSignalsInput,
  type GetShipmentLegGeofenceStateInput,
  type GetShipmentLegRouteDeviationStateInput,
} from "../contracts/geofence-route-deviation-signals/geofence-route-deviation-signals.ts";

export type GeofenceSignalsQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class GeofenceSignalsQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GeofenceSignalsQueryError";
  }
}

/** Defaults to only 'pending' candidates -- pass status: null for every status. */
export async function getShipmentMilestoneCandidates(
  client: GeofenceSignalsQueryRpcClient,
  input: GetShipmentMilestoneCandidatesInput,
): Promise<ShipmentMilestoneCandidate[]> {
  const parsedInput = GetShipmentMilestoneCandidatesInputSchema.parse(input);
  const { data, error } = await client.rpc("get_shipment_milestone_candidates", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_status: parsedInput.status,
  });
  if (error) {
    throw new GeofenceSignalsQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new GeofenceSignalsQueryError("get_shipment_milestone_candidates returned a non-array result");
  }
  return data.map((row: Record<string, unknown>) => parseShipmentMilestoneCandidate(row));
}

/** Defaults to only 'pending' signals -- pass status: null for every status. */
export async function getShipmentExceptionSignals(
  client: GeofenceSignalsQueryRpcClient,
  input: GetShipmentExceptionSignalsInput,
): Promise<ShipmentExceptionSignal[]> {
  const parsedInput = GetShipmentExceptionSignalsInputSchema.parse(input);
  const { data, error } = await client.rpc("get_shipment_exception_signals", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_status: parsedInput.status,
  });
  if (error) {
    throw new GeofenceSignalsQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new GeofenceSignalsQueryError("get_shipment_exception_signals returned a non-array result");
  }
  return data.map((row: Record<string, unknown>) => parseShipmentExceptionSignal(row));
}

/** One row per stop this leg has ever had a geofence dwell-state row for -- a never-approached stop has no row at all. */
export async function getShipmentLegGeofenceState(
  client: GeofenceSignalsQueryRpcClient,
  input: GetShipmentLegGeofenceStateInput,
): Promise<ShipmentLegStopGeofenceState[]> {
  const parsedInput = GetShipmentLegGeofenceStateInputSchema.parse(input);
  const { data, error } = await client.rpc("get_shipment_leg_geofence_state", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new GeofenceSignalsQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new GeofenceSignalsQueryError("get_shipment_leg_geofence_state returned a non-array result");
  }
  return data.map((row: Record<string, unknown>) => parseShipmentLegStopGeofenceState(row));
}

/** At most one row per leg -- a leg that has never deviated has no row at all. */
export async function getShipmentLegRouteDeviationState(
  client: GeofenceSignalsQueryRpcClient,
  input: GetShipmentLegRouteDeviationStateInput,
): Promise<ShipmentLegRouteDeviationState | null> {
  const parsedInput = GetShipmentLegRouteDeviationStateInputSchema.parse(input);
  const { data, error } = await client.rpc("get_shipment_leg_route_deviation_state", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new GeofenceSignalsQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  const row = rows[0];
  return row ? parseShipmentLegRouteDeviationState(row as Record<string, unknown>) : null;
}
