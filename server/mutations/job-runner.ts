/**
 * Typed client helpers for the two database entry points a background worker drives:
 * `app.run_due_jobs` and `app.run_due_scheduled_tasks` (`ISS-2026-015`).
 *
 * Both are `service_role`-only by design. Driving the job queue or the scheduler is a server-side
 * act performed by a process nobody is signed in to, never something a browser session does — so
 * these helpers are only ever reachable from `scripts/jobs/`, and the underlying `public.*`
 * wrappers carry no `authenticated` grant at all.
 *
 * Kept deliberately thin. Every decision that matters — which jobs are claimable, whether a
 * failure retries or dead-letters, how long the backoff is, whether a scheduled task's authorizing
 * identity still holds its rights — belongs to the database functions and is re-checked there on
 * every run. A worker that re-implemented any of that would be a second source of truth for the
 * authority model, which is precisely what this architecture avoids.
 */

export interface JobRunnerRpcClient {
  rpc(
    fn: "run_due_jobs" | "run_due_scheduled_tasks",
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message: string } | null }>;
}

/** One job the worker attempted this tick. `outcome` is the database's verdict, not the worker's. */
export interface JobRunOutcome {
  readonly jobId: string;
  readonly tenantId: string;
  readonly jobType: string;
  readonly outcome: "completed" | "failed";
  readonly detail: string | null;
}

/** One scheduled task the dispatcher fired this tick. */
export interface ScheduledTaskRunOutcome {
  readonly scheduledTaskId: string;
  readonly status: string;
  readonly detail: string | null;
}

export class JobRunnerError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "JobRunnerError";
  }
}

function asRows(data: unknown, fn: string): Record<string, unknown>[] {
  // A set-returning RPC with no rows comes back as `[]`, and PostgREST returns `null` rather than
  // `[]` in some shapes. Both mean "nothing was due", which is the normal case on a quiet tick and
  // must never be an error.
  if (data === null || data === undefined) return [];
  if (!Array.isArray(data)) {
    throw new JobRunnerError(`${fn} returned a non-array result`);
  }
  return data as Record<string, unknown>[];
}

function requiredString(row: Record<string, unknown>, key: string, fn: string): string {
  const value = row[key];
  if (typeof value !== "string" || value.length === 0) {
    throw new JobRunnerError(`${fn} row is missing a string ${key}`);
  }
  return value;
}

function optionalString(row: Record<string, unknown>, key: string): string | null {
  const value = row[key];
  return typeof value === "string" && value.length > 0 ? value : null;
}

/**
 * Claim, execute and settle up to `limit` due jobs. Returns one entry per job attempted, so the
 * caller can log what actually happened rather than a bare count — a worker that reports "3 jobs
 * processed" without saying that two of them failed is worse than one that says nothing.
 *
 * Never throws for "no work available": an empty tick returns `[]`.
 */
export async function runDueJobs(
  client: JobRunnerRpcClient,
  input: { readonly workerId: string; readonly limit?: number; readonly leaseSeconds?: number },
): Promise<JobRunOutcome[]> {
  const { data, error } = await client.rpc("run_due_jobs", {
    p_worker_id: input.workerId,
    p_limit: input.limit ?? 10,
    p_lease_seconds: input.leaseSeconds ?? 300,
  });
  if (error) {
    throw new JobRunnerError(error.message);
  }
  return asRows(data, "run_due_jobs").map((row) => {
    const outcome = requiredString(row, "outcome", "run_due_jobs");
    if (outcome !== "completed" && outcome !== "failed") {
      throw new JobRunnerError(`run_due_jobs returned an unrecognised outcome ${outcome}`);
    }
    return {
      jobId: requiredString(row, "job_id", "run_due_jobs"),
      tenantId: requiredString(row, "tenant_id", "run_due_jobs"),
      jobType: requiredString(row, "job_type", "run_due_jobs"),
      outcome,
      detail: optionalString(row, "detail"),
    };
  });
}

/**
 * Fire every tenant-configured scheduled task whose next run is due. The database decides what is
 * due and re-checks each schedule's authorizing identity; this call only supplies the clock and a
 * batch ceiling.
 */
export async function runDueScheduledTasks(
  client: JobRunnerRpcClient,
  input: { readonly now: string; readonly limit?: number },
): Promise<ScheduledTaskRunOutcome[]> {
  const { data, error } = await client.rpc("run_due_scheduled_tasks", {
    p_now: input.now,
    p_limit: input.limit ?? 50,
  });
  if (error) {
    throw new JobRunnerError(error.message);
  }
  return asRows(data, "run_due_scheduled_tasks").map((row) => ({
    scheduledTaskId: requiredString(row, "scheduled_task_id", "run_due_scheduled_tasks"),
    status: requiredString(row, "status", "run_due_scheduled_tasks"),
    detail: optionalString(row, "detail"),
  }));
}
