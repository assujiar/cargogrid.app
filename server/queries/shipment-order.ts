/**
 * Shipment Order read queries (OPS-169, CG-S8-OPS-003). Thin, typed wrapper around
 * app.shipment_orders -- no masked column exists on this table (cost/selling data
 * stays in app.job_orders' own revenue_snapshot/credit_snapshot, never duplicated
 * here), so reads go directly against the base table, RLS-scoped
 * (shipment_orders_select_scoped), matching app.leads'/app.opportunities' own
 * established convention for a table with nothing sensitive to carve out.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseShipmentOrder,
  parseJobShipmentAllocationBalance,
  GetJobShipmentAllocationBalanceInputSchema,
  type ShipmentOrder,
  type JobShipmentAllocationBalance,
  type GetJobShipmentAllocationBalanceInput,
} from "../contracts/shipment-order/shipment-order.ts";

export type ShipmentOrderQueryTableClient = Pick<SupabaseClient, "from" | "rpc">;

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

export interface ListShipmentOrdersInput {
  readonly tenantId: string;
  readonly page: number;
  readonly pageSize?: number;
}

export interface ListShipmentOrdersResult {
  readonly shipmentOrders: readonly ShipmentOrder[];
  readonly totalCount: number;
  readonly page: number;
  readonly pageSize: number;
}

export class ShipmentOrderQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ShipmentOrderQueryError";
  }
}

/** One Shipment Order by id, if it exists and RLS admits it -- returns null (never an error) otherwise. */
export async function getShipmentOrder(client: ShipmentOrderQueryTableClient, shipmentOrderId: string): Promise<ShipmentOrder | null> {
  const { data, error } = await client.from("shipment_orders").select("*").eq("id", shipmentOrderId).maybeSingle();
  if (error) {
    throw new ShipmentOrderQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseShipmentOrder(data as Record<string, unknown>);
}

/** Every Shipment Order for one Job Order, most recently created first -- RLS is the real scope gate. */
export async function listShipmentOrdersForJobOrder(client: ShipmentOrderQueryTableClient, jobOrderId: string): Promise<ShipmentOrder[]> {
  const { data, error } = await client.from("shipment_orders").select("*").eq("job_order_id", jobOrderId).order("created_at", { ascending: false });
  if (error) {
    throw new ShipmentOrderQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseShipmentOrder(row));
}

/** Server-paginated Shipment Orders for one tenant, most recently created first. */
export async function listShipmentOrders(client: ShipmentOrderQueryTableClient, input: ListShipmentOrdersInput): Promise<ListShipmentOrdersResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const { data, error, count } = await client
    .from("shipment_orders")
    .select("*", { count: "exact" })
    .eq("tenant_id", input.tenantId)
    .order("created_at", { ascending: false })
    .range(from, to);

  if (error) {
    throw new ShipmentOrderQueryError(error.message);
  }

  return {
    shipmentOrders: (data ?? []).map((row: Record<string, unknown>) => parseShipmentOrder(row)),
    totalCount: count ?? 0,
    page,
    pageSize,
  };
}

/** The governed allocation balance for one Job Order -- basis/allocated/remaining per dimension, a null basis dimension is advisory-only. */
export async function getJobShipmentAllocationBalance(
  client: ShipmentOrderQueryTableClient,
  input: GetJobShipmentAllocationBalanceInput,
): Promise<JobShipmentAllocationBalance> {
  const parsedInput = GetJobShipmentAllocationBalanceInputSchema.parse(input);
  const { data, error } = await client.rpc("get_job_shipment_allocation_balance", {
    p_job_order_id: parsedInput.jobOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ShipmentOrderQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new ShipmentOrderQueryError("get_job_shipment_allocation_balance returned no row");
  }
  return parseJobShipmentAllocationBalance(row as Record<string, unknown>);
}
