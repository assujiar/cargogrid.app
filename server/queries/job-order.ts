/**
 * Job Order read queries (OPS-168, CG-S8-OPS-002). Thin, typed wrapper around
 * app.job_orders_directory -- the field-masked projection. `authenticated` has no
 * direct column grant on revenue_snapshot/credit_snapshot on the base table, so
 * every read goes through this view.
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

export type JobOrderQueryTableClient = Pick<SupabaseClient, "from" | "rpc">;

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

export interface ListJobOrdersInput {
  readonly tenantId: string;
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

/** One Job Order by id, if it exists and RLS admits it -- returns null (never an error) otherwise. */
export async function getJobOrder(client: JobOrderQueryTableClient, jobOrderId: string): Promise<JobOrder | null> {
  const { data, error } = await client.from("job_orders_directory").select("*").eq("id", jobOrderId).maybeSingle();
  if (error) {
    throw new JobOrderQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseJobOrder(data as Record<string, unknown>);
}

/** The Job Order converted from one Commercial handoff, if one has been prepared -- returns null (never an error) when none exists yet or RLS excludes it. */
export async function getJobOrderForHandoff(client: JobOrderQueryTableClient, sourceHandoffId: string): Promise<JobOrder | null> {
  const { data, error } = await client.from("job_orders_directory").select("*").eq("source_handoff_id", sourceHandoffId).maybeSingle();
  if (error) {
    throw new JobOrderQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseJobOrder(data as Record<string, unknown>);
}

/** Server-paginated Job Orders for one tenant, most recently created first -- RLS (job_orders_select_scoped) is the real scope gate, mirroring listLeads' own range()/count shape. */
export async function listJobOrders(client: JobOrderQueryTableClient, input: ListJobOrdersInput): Promise<ListJobOrdersResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const { data, error, count } = await client
    .from("job_orders_directory")
    .select("*", { count: "exact" })
    .eq("tenant_id", input.tenantId)
    .order("created_at", { ascending: false })
    .range(from, to);

  if (error) {
    throw new JobOrderQueryError(error.message);
  }

  return {
    jobOrders: (data ?? []).map((row: Record<string, unknown>) => parseJobOrder(row)),
    totalCount: count ?? 0,
    page,
    pageSize,
  };
}
