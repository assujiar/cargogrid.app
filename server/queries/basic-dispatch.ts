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

export type BasicDispatchQueryClient = Pick<SupabaseClient, "rpc">;

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

export interface ListDispatchReadyQueueInput {
  readonly tenantId: string;
  readonly actorAuthUserId: string;
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

/**
 * Server-paginated ready queue -- every assigned Shipment Order the caller can access, is_ready/blockers precomputed. RLS-equivalent scope (app.can_access_record, reproduced inside app.list_dispatch_ready_queue) is the real scope gate.
 *
 * RPC-backed via app.count_dispatch_ready_shipment_orders / app.list_dispatch_ready_queue
 * (CG-AUDIT-2026-09-02 O1 cluster 3 batch 1) -- the app schema is not exposed to
 * PostgREST, so the prior `.from()` reads never worked. Kept as two separate RPC calls
 * (count, then list), preserving CG-AUDIT-2026-09-02 F5's own already-shipped fix intent:
 * both app.dispatch_ready_queue and app.dispatch_board_queue cross-join
 * app.evaluate_dispatch_readiness per row, so folding the count into a single
 * `count(*) over()` query would force that function to run once per matching row just to
 * produce a total -- the exact O(N) cost F5 eliminated. app.count_dispatch_ready_shipment_orders
 * has no lateral join at all and can never disagree with a count taken through the view,
 * by the same equivalence argument F5's own migration header makes.
 */
export async function listDispatchReadyQueue(client: BasicDispatchQueryClient, input: ListDispatchReadyQueueInput): Promise<ListDispatchReadyQueueResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);

  const { data: count, error: countError } = await client.rpc("count_dispatch_ready_shipment_orders", {
    p_tenant_id: input.tenantId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });

  if (countError) {
    throw new BasicDispatchQueryError(countError.message);
  }

  const { data, error } = await client.rpc("list_dispatch_ready_queue", {
    p_tenant_id: input.tenantId,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_page: page,
    p_page_size: pageSize,
  });

  if (error) {
    throw new BasicDispatchQueryError(error.message);
  }

  return {
    rows: (data ?? []).map((row: Record<string, unknown>) => parseDispatchReadyQueueRow(row)),
    totalCount: Number(count ?? 0),
    page,
    pageSize,
  };
}
