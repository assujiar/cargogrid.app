/**
 * Advanced Dispatch Board read queries (ATW-222, CG-S10-ATW-003). Thin, typed
 * wrapper around app.dispatch_board_queue -- no masked column exists on this view,
 * so reads go directly against it, RLS-scoped identically to app.dispatch_ready_queue.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseDispatchBoardRow, type DispatchBoardRow } from "../contracts/dispatch-board/dispatch-board.ts";

export type DispatchBoardQueryClient = Pick<SupabaseClient, "from">;

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

export interface ListDispatchBoardInput {
  readonly tenantId: string;
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
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const { data, error, count } = await client
    .from("dispatch_board_queue")
    .select("*", { count: "exact" })
    .eq("tenant_id", input.tenantId)
    .order("planned_pickup_at", { ascending: true, nullsFirst: false })
    .range(from, to);

  if (error) {
    throw new DispatchBoardQueryError(error.message);
  }

  return {
    rows: (data ?? []).map((row: Record<string, unknown>) => parseDispatchBoardRow(row)),
    totalCount: count ?? 0,
    page,
    pageSize,
  };
}
