/**
 * Shipment Order read queries (OPS-169, CG-S8-OPS-003). CG-AUDIT-2026-09-02 O1
 * remediation (cluster 3 batch 4,
 * 20260911040000_close_o1_query_layer_cluster3_batch4_shipment_order_capacity_exceptions.sql):
 * reads go through thin, security-invoker RPC wrappers (app is not exposed to
 * PostgREST, so a `.from()` call against app.shipment_orders has never worked
 * in production) -- no masked column exists on this table (cost/selling data
 * stays in app.job_orders' own revenue_snapshot/credit_snapshot, never
 * duplicated here), so each function is a plain, RLS-scoped passthrough
 * (shipment_orders_select_scoped).
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
  const { data, error } = await client.rpc("get_shipment_order", { p_shipment_order_id: shipmentOrderId });
  if (error) {
    throw new ShipmentOrderQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseShipmentOrder(row as Record<string, unknown>);
}

/** Every Shipment Order for one Job Order, most recently created first -- RLS is the real scope gate. */
export async function listShipmentOrdersForJobOrder(client: ShipmentOrderQueryTableClient, jobOrderId: string): Promise<ShipmentOrder[]> {
  const { data, error } = await client.rpc("list_shipment_orders_for_job_order", { p_job_order_id: jobOrderId });
  if (error) {
    throw new ShipmentOrderQueryError(error.message);
  }
  return ((data ?? []) as Record<string, unknown>[]).map((row) => parseShipmentOrder(row));
}

/** Server-paginated Shipment Orders for one tenant, most recently created first. */
export async function listShipmentOrders(client: ShipmentOrderQueryTableClient, input: ListShipmentOrdersInput): Promise<ListShipmentOrdersResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);

  const { data, error } = await client.rpc("list_shipment_orders", {
    p_tenant_id: input.tenantId,
    p_page: page,
    p_page_size: pageSize,
  });

  if (error) {
    throw new ShipmentOrderQueryError(error.message);
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  const totalCount = rows.length > 0 ? Number(rows[0]?.total_count) : 0;

  return {
    shipmentOrders: rows.map((row) => parseShipmentOrder(row)),
    totalCount,
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
