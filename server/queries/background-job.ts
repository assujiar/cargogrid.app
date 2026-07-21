/**
 * Background job framework read queries (PLT-132, CG-S6-PLT-029). Thin, typed wrapper
 * around app.compute_job_backoff_seconds()
 * (supabase/migrations/20260719180000_create_background_job_framework.sql) --
 * service_role-only, matching this capability's server-mediated design.
 *
 * app.jobs' own status/result is read directly by an authenticated caller through its
 * already-established direct-table RLS policy (PLT-131's jobs_select_scoped) -- no
 * dedicated read function exists for that here, since RLS is the real access boundary
 * already in place, not something this checkpoint needs to duplicate.
 */

export interface BackgroundJobQueryRpcClient {
  rpc(fn: "compute_job_backoff_seconds", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class BackgroundJobQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BackgroundJobQueryError";
  }
}

/** ADR-0013: equal-jitter exponential backoff (base 30s, 2x multiplier, capped at 3600s). Volatile (uses random()) -- calling it twice with the same attempts count returns different values within the same bounded range. */
export async function computeJobBackoffSeconds(client: BackgroundJobQueryRpcClient, attempts: number): Promise<number> {
  const { data, error } = await client.rpc("compute_job_backoff_seconds", { p_attempts: attempts });
  if (error) {
    throw new BackgroundJobQueryError(error.message);
  }
  if (typeof data !== "number") {
    throw new BackgroundJobQueryError("compute_job_backoff_seconds returned a non-numeric result");
  }
  return data;
}
