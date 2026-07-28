/**
 * Actual Cost read queries (OPS-178, CG-S8-OPS-012). Thin, typed wrappers around
 * app.evaluate_actual_cost_variance / app.list_actual_cost_components plus a direct
 * read of the field-masked app.shipment_actual_costs_directory view.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseActualCostVariance,
  parseShipmentActualCostComponent,
  parseShipmentActualCostDirectoryRow,
  ActualCostRecordInputSchema,
  type ActualCostVariance,
  type ShipmentActualCostComponent,
  type ShipmentActualCostDirectoryRow,
  type ActualCostRecordInput,
} from "../contracts/actual-cost/actual-cost.ts";

export type ActualCostQueryClient = Pick<SupabaseClient, "from" | "rpc">;

export class ActualCostQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ActualCostQueryError";
  }
}

/** Direct RLS-scoped read of the field-masked directory view -- total_amount/estimated_amount are null for an actor lacking OPS:View cost. */
export async function getShipmentActualCost(client: ActualCostQueryClient, shipmentOrderId: string): Promise<ShipmentActualCostDirectoryRow | null> {
  const { data, error } = await client.from("shipment_actual_costs_directory").select("*").eq("shipment_order_id", shipmentOrderId).eq("is_current", true).maybeSingle();
  if (error) {
    throw new ActualCostQueryError(error.message);
  }
  return data ? parseShipmentActualCostDirectoryRow(data as Record<string, unknown>) : null;
}

/** Denies outright (no partial result) to an actor lacking OPS:View cost -- every column of a cost component is itself cost-shaped. */
export async function listActualCostComponents(client: ActualCostQueryClient, input: ActualCostRecordInput): Promise<ShipmentActualCostComponent[]> {
  const parsedInput = ActualCostRecordInputSchema.parse(input);
  const { data, error } = await client.rpc("list_actual_cost_components", {
    p_actual_cost_id: parsedInput.actualCostId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ActualCostQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new ActualCostQueryError("list_actual_cost_components returned a non-array result");
  }
  return data.map((row: Record<string, unknown>) => parseShipmentActualCostComponent(row));
}

/** Pure, side-effect-free variance evaluation. variance_available is false whenever no estimated_amount was ever supplied. */
export async function evaluateActualCostVariance(client: ActualCostQueryClient, input: ActualCostRecordInput): Promise<ActualCostVariance> {
  const parsedInput = ActualCostRecordInputSchema.parse(input);
  const { data, error } = await client.rpc("evaluate_actual_cost_variance", {
    p_actual_cost_id: parsedInput.actualCostId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ActualCostQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new ActualCostQueryError("evaluate_actual_cost_variance returned no row");
  }
  return parseActualCostVariance(row as Record<string, unknown>);
}
