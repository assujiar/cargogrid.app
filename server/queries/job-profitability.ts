/**
 * Basic Job Profitability read queries (OPS-179, CG-S8-OPS-013). A direct RLS-scoped
 * read of the field-masked app.job_profitability_directory view.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseJobProfitabilityDirectoryRow, type JobProfitabilityDirectoryRow } from "../contracts/job-profitability/job-profitability.ts";

export type JobProfitabilityQueryClient = Pick<SupabaseClient, "from">;

export class JobProfitabilityQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "JobProfitabilityQueryError";
  }
}

/** revenue/cost/margin amounts and source_cost_version_ids are null/empty (marginMasked=true) for an actor lacking OPS:View margin -- status/version/blockedReason remain visible. */
export async function getJobProfitability(client: JobProfitabilityQueryClient, jobOrderId: string): Promise<JobProfitabilityDirectoryRow | null> {
  const { data, error } = await client.from("job_profitability_directory").select("*").eq("job_order_id", jobOrderId).eq("is_current", true).maybeSingle();
  if (error) {
    throw new JobProfitabilityQueryError(error.message);
  }
  return data ? parseJobProfitabilityDirectoryRow(data as Record<string, unknown>) : null;
}
