/**
 * Job Order read queries (OPS-168, CG-S8-OPS-002). RPC-backed via app.get_job_order /
 * app.get_job_order_for_handoff / app.list_job_orders (CG-AUDIT-2026-09-02 O1 cluster 3
 * batch 1) -- the app schema is not exposed to PostgREST, so the prior
 * `.from("job_orders_directory")` reads never worked. `authenticated` has no direct
 * column grant on revenue_snapshot/credit_snapshot on the base table app.job_orders --
 * these RPCs reproduce app.job_orders_directory's own masking (has_view_selling_price /
 * has_view_cost) against an explicit actor id.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseJobOrder,
  parseJobOrderConversionReadiness,
  GetJobOrderConversionReadinessInputSchema,
  type JobOrder,
  type JobOrderConversionReadiness,
  type GetJobOrderConversionReadinessInput,
} from "../contracts/job-order/job-order.ts";

export type JobOrderQueryTableClient = Pick<SupabaseClient, "rpc">;

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

export interface ListJobOrdersInput {
  readonly tenantId: string;
  readonly actorAuthUserId: string;
  readonly page: number;
  readonly pageSize?: number;
}

export interface ListJobOrdersResult {
  readonly jobOrders: readonly JobOrder[];
  readonly totalCount: number;
  readonly page: number;
  readonly pageSize: number;
}

export class JobOrderQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "JobOrderQueryError";
  }
}

/** Structural readiness pre-check for one Commercial handoff -- reason codes only, never a dollar figure. */
export async function getJobOrderConversionReadiness(
  client: JobOrderQueryTableClient,
  input: GetJobOrderConversionReadinessInput,
): Promise<JobOrderConversionReadiness> {
  const parsedInput = GetJobOrderConversionReadinessInputSchema.parse(input);
  const { data, error } = await client.rpc("get_job_order_conversion_readiness", {
    p_source_handoff_id: parsedInput.sourceHandoffId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new JobOrderQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new JobOrderQueryError("get_job_order_conversion_readiness returned no row");
  }
  return parseJobOrderConversionReadiness(row as Record<string, unknown>);
}

/** One Job Order by id, if it exists and the caller's record scope admits it -- returns null (never an error) otherwise. */
export async function getJobOrder(client: JobOrderQueryTableClient, jobOrderId: string, actorAuthUserId: string): Promise<JobOrder | null> {
  const { data, error } = await client.rpc("get_job_order", {
    p_job_order_id: jobOrderId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new JobOrderQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseJobOrder(row as Record<string, unknown>) : null;
}

/** The Job Order converted from one Commercial handoff, if one has been prepared -- returns null (never an error) when none exists yet or the caller's record scope excludes it. */
export async function getJobOrderForHandoff(client: JobOrderQueryTableClient, sourceHandoffId: string, actorAuthUserId: string): Promise<JobOrder | null> {
  const { data, error } = await client.rpc("get_job_order_for_handoff", {
    p_source_handoff_id: sourceHandoffId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new JobOrderQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseJobOrder(row as Record<string, unknown>) : null;
}

/** Server-paginated Job Orders for one tenant, most recently created first -- the caller's per-row record scope (app.can_access_record) is the real scope gate, mirroring listLeads' own range()/count shape. */
export async function listJobOrders(client: JobOrderQueryTableClient, input: ListJobOrdersInput): Promise<ListJobOrdersResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);

  const { data, error } = await client.rpc("list_job_orders", {
    p_tenant_id: input.tenantId,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_page: page,
    p_page_size: pageSize,
  });

  if (error) {
    throw new JobOrderQueryError(error.message);
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  const totalCount = rows.length > 0 ? Number(rows[0]?.total_count) : 0;

  return {
    jobOrders: rows.map((row) => parseJobOrder(row)),
    totalCount,
    page,
    pageSize,
  };
}
