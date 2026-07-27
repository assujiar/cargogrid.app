/**
 * Milestone Management read queries (OPS-173, CG-S8-OPS-007). Thin, typed wrappers
 * around app.get_shipment_milestone_timeline / app.get_shipment_milestone_projection.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseMilestoneEvent,
  parseShipmentMilestoneProjection,
  parseMilestoneCode,
  GetShipmentMilestoneTimelineInputSchema,
  GetShipmentMilestoneProjectionInputSchema,
  type MilestoneEvent,
  type ShipmentMilestoneProjection,
  type MilestoneCode,
  type GetShipmentMilestoneTimelineInput,
  type GetShipmentMilestoneProjectionInput,
} from "../contracts/milestone-management/milestone-management.ts";

export type MilestoneManagementQueryRpcClient = Pick<SupabaseClient, "rpc">;
export type MilestoneManagementQueryTableClient = Pick<SupabaseClient, "from">;

export class MilestoneManagementQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MilestoneManagementQueryError";
  }
}

/** The full, platform-wide registered milestone code catalogue -- RLS-scoped select to authenticated (reference data, true for every row), no RPC needed. */
export async function listMilestoneCodes(client: MilestoneManagementQueryTableClient): Promise<MilestoneCode[]> {
  const { data, error } = await client.from("milestone_codes").select("*").order("name");
  if (error) {
    throw new MilestoneManagementQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseMilestoneCode(row));
}

/** The full, ordered (oldest-first) event timeline for one Shipment Order -- authority-gated; customerVisibleOnly filters to app.milestone_codes.is_customer_visible codes only. */
export async function getShipmentMilestoneTimeline(
  client: MilestoneManagementQueryRpcClient,
  input: GetShipmentMilestoneTimelineInput,
): Promise<MilestoneEvent[]> {
  const parsedInput = GetShipmentMilestoneTimelineInputSchema.parse(input);
  const { data, error } = await client.rpc("get_shipment_milestone_timeline", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_customer_visible_only: parsedInput.customerVisibleOnly,
  });
  if (error) {
    throw new MilestoneManagementQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new MilestoneManagementQueryError("get_shipment_milestone_timeline returned a non-array result");
  }
  return data.map((row: Record<string, unknown>) => parseMilestoneEvent(row));
}

/** The current deterministic projection (last milestone, ETA, location, delay signal) for one Shipment Order -- authority-gated; null if no event has ever been ingested. */
export async function getShipmentMilestoneProjection(
  client: MilestoneManagementQueryRpcClient,
  input: GetShipmentMilestoneProjectionInput,
): Promise<ShipmentMilestoneProjection | null> {
  const parsedInput = GetShipmentMilestoneProjectionInputSchema.parse(input);
  const { data, error } = await client.rpc("get_shipment_milestone_projection", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new MilestoneManagementQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    return null;
  }
  return parseShipmentMilestoneProjection(data as Record<string, unknown>);
}
