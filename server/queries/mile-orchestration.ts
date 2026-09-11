/**
 * First-, Middle-, and Last-Mile Orchestration read queries (ATW-225,
 * CG-S10-ATW-006). Reads go through app.get_shipment_leg_tracking_policy /
 * app.get_current_shipment_leg_tracking_session (plain, security-invoker,
 * RLS-scoped single-row reads), app.get_shipment_leg_tracking_sessions (session
 * history), or app.resolve_leg_tracking_policy (a computed projection requiring
 * an actor parameter) -- app is not exposed to PostgREST, so none of these are
 * reachable via .from() (CG-AUDIT-2026-09-02 O1 cluster 3 batch 2 for the first
 * two).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ResolveLegTrackingPolicyInputSchema,
  parseShipmentLegTrackingPolicy,
  parseShipmentLegTrackingSession,
  parseResolvedLegTrackingPolicy,
  type ResolveLegTrackingPolicyInput,
  type ShipmentLegTrackingPolicy,
  type ShipmentLegTrackingSession,
  type ResolvedLegTrackingPolicy,
} from "../contracts/mile-orchestration/mile-orchestration.ts";

export type MileOrchestrationQueryTableClient = Pick<SupabaseClient, "rpc">;

export class MileOrchestrationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MileOrchestrationQueryError";
  }
}

/** The one tracking policy for a leg, if defined yet. */
export async function getShipmentLegTrackingPolicy(client: MileOrchestrationQueryTableClient, shipmentLegId: string): Promise<ShipmentLegTrackingPolicy | null> {
  const { data, error } = await client.rpc("get_shipment_leg_tracking_policy", { p_shipment_leg_id: shipmentLegId });
  if (error) {
    throw new MileOrchestrationQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseShipmentLegTrackingPolicy(row as Record<string, unknown>) : null;
}

/** Full chronological tracking-session history for one leg. */
export async function listShipmentLegTrackingSessions(client: MileOrchestrationQueryTableClient, shipmentLegId: string): Promise<ShipmentLegTrackingSession[]> {
  const { data, error } = await client.rpc("get_shipment_leg_tracking_sessions", { p_shipment_leg_id: shipmentLegId });
  if (error) {
    throw new MileOrchestrationQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseShipmentLegTrackingSession(row));
}

/** The current (is_current) tracking session for a leg, if any. */
export async function getCurrentShipmentLegTrackingSession(client: MileOrchestrationQueryTableClient, shipmentLegId: string): Promise<ShipmentLegTrackingSession | null> {
  const { data, error } = await client.rpc("get_current_shipment_leg_tracking_session", { p_shipment_leg_id: shipmentLegId });
  if (error) {
    throw new MileOrchestrationQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseShipmentLegTrackingSession(row as Record<string, unknown>) : null;
}

/** Real ATW-223 eligibility resolved against the leg's own policy and shipment-level resource assignment; tracking_entitled is disclosed alongside, never gating resolution. */
export async function resolveLegTrackingPolicy(client: MileOrchestrationQueryTableClient, input: ResolveLegTrackingPolicyInput): Promise<ResolvedLegTrackingPolicy> {
  const parsedInput = ResolveLegTrackingPolicyInputSchema.parse(input);
  const { data, error } = await client.rpc("resolve_leg_tracking_policy", {
    p_shipment_leg_id: parsedInput.shipmentLegId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new MileOrchestrationQueryError(error.message);
  }
  const rows = (data ?? []) as Record<string, unknown>[];
  const row = rows[0];
  if (!row) {
    throw new MileOrchestrationQueryError("resolve_leg_tracking_policy returned no row");
  }
  return parseResolvedLegTrackingPolicy(row);
}
