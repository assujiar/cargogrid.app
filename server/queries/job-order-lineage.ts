/**
 * Full Lineage into Job Order read queries (COM-160, CG-S7-COM-019). RPC-backed via
 * app.get_job_order_handoff_for_quotation / app.list_job_order_handoffs
 * (CG-AUDIT-2026-09-02 O1 cluster 3 batch 1) -- the app schema is not exposed to
 * PostgREST, so the prior `.from("job_order_handoffs_directory")` reads never worked.
 * `authenticated` has no direct column grant on payload/payload_hash on the base table
 * app.job_order_handoffs -- these RPCs reproduce the view's own masking
 * (has_view_selling_price) against an explicit actor id.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseJobOrderHandoff, type JobOrderHandoff } from "../contracts/job-order-lineage/job-order-lineage.ts";

export type JobOrderLineageQueryTableClient = Pick<SupabaseClient, "rpc">;

export class JobOrderLineageQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "JobOrderLineageQueryError";
  }
}

/** The handoff for one quotation, if one has been prepared -- returns null (never an error) when none exists yet or the caller's record scope excludes it. */
export async function getJobOrderHandoffForQuotation(client: JobOrderLineageQueryTableClient, quotationId: string, actorAuthUserId: string): Promise<JobOrderHandoff | null> {
  const { data, error } = await client.rpc("get_job_order_handoff_for_quotation", {
    p_quotation_id: quotationId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new JobOrderLineageQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseJobOrderHandoff(row as Record<string, unknown>) : null;
}

/** Every handoff for one tenant, most recently prepared first -- the caller's per-row record scope (app.can_access_record) is the real scope gate. */
export async function listJobOrderHandoffs(client: JobOrderLineageQueryTableClient, tenantId: string, actorAuthUserId: string, limit = 50): Promise<JobOrderHandoff[]> {
  const { data, error } = await client.rpc("list_job_order_handoffs", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: limit,
  });
  if (error) {
    throw new JobOrderLineageQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseJobOrderHandoff(row));
}
