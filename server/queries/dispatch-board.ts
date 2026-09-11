/**
 * Advanced Dispatch Board read queries (ATW-222, CG-S10-ATW-003). RPC-backed via
 * app.count_dispatch_board_shipment_orders / app.list_dispatch_board (CG-AUDIT-2026-09-02
 * O1 cluster 3 batch 1) -- the app schema is not exposed to PostgREST, so the prior
 * `.from("dispatch_board_queue")` read never worked. No masked column exists on this
 * view; the record-scope predicate (app.can_access_record, reproduced inside
 * app.list_dispatch_board) is the real scope gate, identical to app.dispatch_ready_queue.
 * Kept as two separate RPC calls (count, then list) for the same O(N)-lateral-join-cost
 * reason as basic-dispatch.ts's listDispatchReadyQueue -- see that function's own comment.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseDispatchBoardRow, type DispatchBoardRow } from "../contracts/dispatch-board/dispatch-board.ts";

export type DispatchBoardQueryClient = Pick<SupabaseClient, "rpc">;

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

export interface ListDispatchBoardInput {
  readonly tenantId: string;
  readonly actorAuthUserId: string;
  readonly page: number;
  readonly pageSize?: number;
}

export interface ListDispatchBoardResult {
  readonly rows: readonly DispatchBoardRow[];
  readonly totalCount: number;
  readonly page: number;
  readonly pageSize: number;
}

export class DispatchBoardQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DispatchBoardQueryError";
  }
}

/** Server-paginated assigned/dispatched/in_transit Shipment Orders for one tenant, planned pickup ascending. */
export async function listDispatchBoard(client: DispatchBoardQueryClient, input: ListDispatchBoardInput): Promise<ListDispatchBoardResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);

  const { data: count, error: countError } = await client.rpc("count_dispatch_board_shipment_orders", {
    p_tenant_id: input.tenantId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });

  if (countError) {
    throw new DispatchBoardQueryError(countError.message);
  }

  const { data, error } = await client.rpc("list_dispatch_board", {
    p_tenant_id: input.tenantId,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_page: page,
    p_page_size: pageSize,
  });

  if (error) {
    throw new DispatchBoardQueryError(error.message);
  }

  return {
    rows: (data ?? []).map((row: Record<string, unknown>) => parseDispatchBoardRow(row)),
    totalCount: Number(count ?? 0),
    page,
    pageSize,
  };
}
