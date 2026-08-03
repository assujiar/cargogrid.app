/**
 * First-, Middle-, and Last-Mile Orchestration read queries (ATW-225,
 * CG-S10-ATW-006). No masked column exists on either table, so reads go
 * directly against the base tables (RLS-scoped) except for session history
 * (app.get_shipment_leg_tracking_sessions) and policy resolution
 * (app.resolve_leg_tracking_policy, a computed projection requiring an actor
 * parameter, not a plain table read).
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

export type MileOrchestrationQueryTableClient = Pick<SupabaseClient, "from" | "rpc">;

export class MileOrchestrationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MileOrchestrationQueryError";
  }
}

/** The one tracking policy for a leg, if defined yet. */
export async function getShipmentLegTrackingPolicy(client: MileOrchestrationQueryTableClient, shipmentLegId: string): Promise<ShipmentLegTrackingPolicy | null> {
  const { data, error } = await client.from("shipment_leg_tracking_policies").select("*").eq("shipment_leg_id", shipmentLegId).maybeSingle();
  if (error) {
    throw new MileOrchestrationQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseShipmentLegTrackingPolicy(data as Record<string, unknown>);
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
  const { data, error } = await client.from("shipment_leg_tracking_sessions").select("*").eq("shipment_leg_id", shipmentLegId).eq("is_current", true).maybeSingle();
  if (error) {
    throw new MileOrchestrationQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseShipmentLegTrackingSession(data as Record<string, unknown>);
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
