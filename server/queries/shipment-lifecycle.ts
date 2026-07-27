/**
 * Shipment Lifecycle read queries (OPS-170, CG-S8-OPS-004). Thin, typed wrapper
 * around app.get_shipment_status_history.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseShipmentStatusTransition,
  GetShipmentStatusHistoryInputSchema,
  type ShipmentStatusTransition,
  type GetShipmentStatusHistoryInput,
} from "../contracts/shipment-lifecycle/shipment-lifecycle.ts";

export type ShipmentLifecycleQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class ShipmentLifecycleQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ShipmentLifecycleQueryError";
  }
}

/** The full, ordered (oldest-first) transition history for one Shipment Order -- authority-gated, mirrors app.get_workflow_instance_history's own established shape. */
export async function getShipmentStatusHistory(
  client: ShipmentLifecycleQueryRpcClient,
  input: GetShipmentStatusHistoryInput,
): Promise<ShipmentStatusTransition[]> {
  const parsedInput = GetShipmentStatusHistoryInputSchema.parse(input);
  const { data, error } = await client.rpc("get_shipment_status_history", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ShipmentLifecycleQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ShipmentLifecycleQueryError("get_shipment_status_history returned a non-array result");
  }
  return data.map((row: Record<string, unknown>) => parseShipmentStatusTransition(row));
}
