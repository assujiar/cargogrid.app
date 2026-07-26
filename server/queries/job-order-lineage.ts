/**
 * Full Lineage into Job Order read queries (COM-160, CG-S7-COM-019). Thin, typed
 * wrapper around app.job_order_handoffs_directory -- the field-masked projection.
 * `authenticated` has no direct column grant on payload/payload_hash on the base
 * table, so every read goes through this view.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseJobOrderHandoff, type JobOrderHandoff } from "../contracts/job-order-lineage/job-order-lineage.ts";

export type JobOrderLineageQueryTableClient = Pick<SupabaseClient, "from">;

export class JobOrderLineageQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "JobOrderLineageQueryError";
  }
}

/** The handoff for one quotation, if one has been prepared -- returns null (never an error) when none exists yet or RLS excludes it. */
export async function getJobOrderHandoffForQuotation(client: JobOrderLineageQueryTableClient, quotationId: string): Promise<JobOrderHandoff | null> {
  const { data, error } = await client.from("job_order_handoffs_directory").select("*").eq("quotation_id", quotationId).maybeSingle();
  if (error) {
    throw new JobOrderLineageQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseJobOrderHandoff(data as Record<string, unknown>);
}

/** Every handoff for one tenant, most recently prepared first -- RLS (job_order_handoffs_select_scoped) is the real scope gate. */
export async function listJobOrderHandoffs(client: JobOrderLineageQueryTableClient, tenantId: string, limit = 50): Promise<JobOrderHandoff[]> {
  const { data, error } = await client
    .from("job_order_handoffs_directory")
    .select("*")
    .eq("tenant_id", tenantId)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) {
    throw new JobOrderLineageQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseJobOrderHandoff(row));
}
