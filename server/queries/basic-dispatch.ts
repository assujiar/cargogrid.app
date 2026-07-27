/**
 * Basic Dispatch read queries (OPS-175, CG-S8-OPS-009). A thin, typed wrapper around
 * app.get_dispatch_readiness plus a server-paginated, RLS-scoped
 * app.dispatch_ready_queue table read (the same page/pageSize/range convention
 * OPS-169's own listShipmentOrders established).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseDispatchReadiness,
  parseDispatchReadyQueueRow,
  GetDispatchReadinessInputSchema,
  type DispatchReadiness,
  type DispatchReadyQueueRow,
  type GetDispatchReadinessInput,
} from "../contracts/basic-dispatch/basic-dispatch.ts";

export type BasicDispatchQueryClient = Pick<SupabaseClient, "from" | "rpc">;

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

export interface ListDispatchReadyQueueInput {
  readonly tenantId: string;
  readonly page: number;
  readonly pageSize?: number;
}

export interface ListDispatchReadyQueueResult {
  readonly rows: readonly DispatchReadyQueueRow[];
  readonly totalCount: number;
  readonly page: number;
  readonly pageSize: number;
}

export class BasicDispatchQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BasicDispatchQueryError";
  }
}

/** Authority-gated (OPS:View + record scope) single-shipment readiness check, for the dispatch panel's own "why not ready" display. */
export async function getDispatchReadiness(client: BasicDispatchQueryClient, input: GetDispatchReadinessInput): Promise<DispatchReadiness> {
  const parsedInput = GetDispatchReadinessInputSchema.parse(input);
  const { data, error } = await client.rpc("get_dispatch_readiness", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new BasicDispatchQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new BasicDispatchQueryError("get_dispatch_readiness returned no row");
  }
  return parseDispatchReadiness(row as Record<string, unknown>);
}

/** Server-paginated ready queue -- every assigned Shipment Order the caller can access, is_ready/blockers precomputed. RLS (dispatch_ready_queue's own can_access_record predicate) is the real scope gate. */
export async function listDispatchReadyQueue(client: BasicDispatchQueryClient, input: ListDispatchReadyQueueInput): Promise<ListDispatchReadyQueueResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const { data, error, count } = await client
    .from("dispatch_ready_queue")
    .select("*", { count: "exact" })
    .eq("tenant_id", input.tenantId)
    .order("planned_pickup_at", { ascending: true, nullsFirst: false })
    .range(from, to);

  if (error) {
    throw new BasicDispatchQueryError(error.message);
  }

  return {
    rows: (data ?? []).map((row: Record<string, unknown>) => parseDispatchReadyQueueRow(row)),
    totalCount: count ?? 0,
    page,
    pageSize,
  };
}
