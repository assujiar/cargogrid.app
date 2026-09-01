/**
 * Records that one `app.calculate_payroll_run` attempt genuinely failed, from outside the
 * transaction that failed.
 *
 * `ISS-2026-079` found that `app.calculate_payroll_run`'s claimed multi-transaction
 * crash-resumability is not real -- the whole job lifecycle runs inside one function
 * invocation/transaction, so a crash mid-run rolls everything back and leaves zero durable trace
 * for any monitoring surface to pick up. The owner's explicit scope for closing it is alerting
 * only, not a redesign of that transaction model -- see
 * `supabase/migrations/20260902010000_alert_on_payroll_run_calculation_failure_iss2026079.sql`.
 *
 * That migration hits the same structural wall `ISS-2026-249` already named:
 *
 *   **A database function that rolls back cannot durably record the failure it rolled back on.**
 *
 * So recording happens here, mirroring `server/policies/authority-denial-recorder.ts` exactly: a
 * fresh statement, after the rollback, called by the Server Action that just caught the error.
 */

export interface PayrollRunFailureRecorderRpcClient {
  // PromiseLike, not Promise: SupabaseClient's real `rpc(...)` returns a thenable
  // PostgrestFilterBuilder (no `.catch`/`.finally`), and this interface exists to be satisfied by
  // that real client directly -- `await`ing either shape works identically.
  rpc(fn: "record_payroll_run_calculation_failure", args: Record<string, unknown>): PromiseLike<{ data: unknown; error: { message: string } | null }>;
}

export interface PayrollRunCalculationFailureContext {
  readonly runId: string;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
}

/**
 * True for an error that means the calculation attempt genuinely failed or crashed, as opposed
 * to an expected, already-classified business-rule rejection (`stale_version`,
 * `insufficient_authority`, `payroll_run_not_found`, `payroll_period_inputs_not_frozen`,
 * `invalid_transition`, `idempotency_key_conflict`, ...) that `app.calculate_payroll_run` raises
 * before doing any real work. Those are the authorization/validation layer working correctly, not
 * a crash -- alerting on each one would be exactly the false-positive flood `ISS-2026-249`'s own
 * ruling warned against. A `PayrollMutationError` this repository's own
 * `PAYROLL_KNOWN_MUTATION_ERROR_CODES` cannot classify (`code === "unknown"`), or any error that
 * is not a `PayrollMutationError` at all (a network failure, a dropped connection), is the shape
 * a genuine mid-calculation crash actually takes once it reaches the caller.
 */
export function isGenuinePayrollRunCalculationFailure(error: unknown): boolean {
  if (error && typeof error === "object" && "code" in error) {
    const code = (error as { code: unknown }).code;
    if (typeof code === "string" && code !== "unknown") return false;
  }
  return true;
}

/**
 * Never throws. A failure to record the alert must not turn an already-failed calculation
 * attempt into a second, unrelated 500 for the caller -- the user's own outcome is already
 * decided, and losing one observability row is strictly better than losing the correct error
 * report. Returns whether the row was written.
 */
export async function recordPayrollRunCalculationFailure(
  client: PayrollRunFailureRecorderRpcClient,
  context: PayrollRunCalculationFailureContext,
  errorDetail: string,
): Promise<boolean> {
  try {
    const { error } = await client.rpc("record_payroll_run_calculation_failure", {
      p_run_id: context.runId,
      p_actor_auth_user_id: context.actorAuthUserId,
      p_actor_label: context.actorLabel,
      // Truncated: this column is evidence a crash happened and enough detail to investigate it,
      // not a place to store an unbounded stack trace.
      p_error_detail: errorDetail.slice(0, 2000),
    });
    return error === null;
  } catch {
    return false;
  }
}

/**
 * The shape a Server Action uses: given the error it just caught from `calculatePayrollRun`,
 * record and alert on it if -- and only if -- it looks like a genuine crash rather than a
 * routine, already-classified rejection. Returns nothing and never throws; the caller's own
 * error handling (returning a `PayrollAdminActionState`, or re-throwing) is unchanged by this
 * call -- it observes, it never swallows.
 */
export async function observePayrollRunCalculationFailure(
  client: PayrollRunFailureRecorderRpcClient,
  context: PayrollRunCalculationFailureContext,
  error: unknown,
): Promise<void> {
  if (!isGenuinePayrollRunCalculationFailure(error)) return;
  const message = error instanceof Error ? error.message : String(error);
  await recordPayrollRunCalculationFailure(client, context, message);
}
