/**
 * Records an authorization refusal, from outside the transaction that was refused.
 *
 * `ISS-2026-249` kept two producers open for three passes, and the entry's own diagnosis
 * ("needs a new log table plus a volatility change") understated the obstacle by one step. The
 * real one is structural:
 *
 *   **A database function that raises cannot durably record the denial it raises on.** The
 *   INSERT and the RAISE share a transaction, so the raise rolls the record back.
 *
 * That is why `20260827000000_wire_observability_alert_producers.sql` placed every alert call
 * "immediately before that branch's own normal `return`, never before a `raise exception`".
 * Making the step-up assertion volatile would have let it INSERT and still recorded nothing.
 *
 * So the recording happens here, at the boundary that catches the error — a fresh statement,
 * after the rollback, in the one place where the fact "this call was denied" both exists and can
 * be written down. The detection half is `app.run_authority_denial_anomaly_sweep`, which alerts
 * on a burst rather than on each row, because a single denial is the authorization layer working
 * and alerting on it would be noise.
 */

export interface AuthorityDenialRecorderRpcClient {
  rpc(fn: "record_authority_denial", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export type AuthorityDenialKind = "rbac" | "step_up" | "ip";

export interface AuthorityDenialObservation {
  readonly tenantId: string;
  readonly actorAuthUserId: string | null;
  readonly kind: AuthorityDenialKind;
  readonly moduleCode?: string | null;
  readonly action?: string | null;
  readonly reason?: string | null;
  readonly resourceType?: string | null;
  readonly resourceId?: string | null;
  readonly correlationId?: string | null;
}

/**
 * `app.evaluate_permission` returns `mfa_step_up_required` as a decision reason rather than
 * raising (ISS-2026-236), so a step-up refusal reaches the boundary as an ordinary
 * `insufficient_authority` error whose message carries that reason. Classifying on the message
 * is what lets one recorder serve both of the entry's remaining producers.
 */
export function classifyDenial(message: string): AuthorityDenialKind {
  if (message.includes("mfa_step_up_required")) return "step_up";
  if (message.includes("ip_not_allowed") || message.includes("ip_restriction")) return "ip";
  return "rbac";
}

/** True for the error shapes that mean "refused", as opposed to "failed". */
export function isAuthorityDenial(message: string): boolean {
  return (
    message.includes("insufficient_authority") ||
    message.includes("insufficient_privilege") ||
    message.includes("mfa_step_up_required") ||
    message.includes("ip_not_allowed")
  );
}

/**
 * Never throws. A failure to record a denial must not turn a clean "you may not do that" into a
 * 500 — the user's own outcome is already decided, and losing one observability row is strictly
 * better than losing the correct refusal. Returns whether the row was written, so a caller that
 * wants to know can ask.
 */
export async function recordAuthorityDenial(
  client: AuthorityDenialRecorderRpcClient,
  observation: AuthorityDenialObservation,
): Promise<boolean> {
  try {
    const { error } = await client.rpc("record_authority_denial", {
      p_tenant_id: observation.tenantId,
      p_actor_auth_user_id: observation.actorAuthUserId,
      p_denial_kind: observation.kind,
      p_module_code: observation.moduleCode ?? null,
      p_action: observation.action ?? null,
      // Truncated: an exception message can carry a long tail, and this column is evidence that
      // a refusal happened, not a place to store an essay.
      p_reason: observation.reason ? observation.reason.slice(0, 500) : null,
      p_resource_type: observation.resourceType ?? null,
      p_resource_id: observation.resourceId ?? null,
      p_correlation_id: observation.correlationId ?? null,
    });
    return error === null;
  } catch {
    return false;
  }
}

/**
 * The shape a Server Action uses: given the error it just caught, record it if — and only if —
 * it was a refusal rather than an ordinary failure. Returns the original error untouched so the
 * caller's own handling is unchanged; this helper observes, it never swallows.
 */
export async function observeAuthorityDenial(
  client: AuthorityDenialRecorderRpcClient,
  context: { readonly tenantId: string; readonly actorAuthUserId: string | null; readonly moduleCode?: string | null; readonly action?: string | null },
  error: unknown,
): Promise<void> {
  const message = error instanceof Error ? error.message : String(error);
  if (!isAuthorityDenial(message)) return;
  await recordAuthorityDenial(client, {
    tenantId: context.tenantId,
    actorAuthUserId: context.actorAuthUserId,
    kind: classifyDenial(message),
    moduleCode: context.moduleCode ?? null,
    action: context.action ?? null,
    reason: message,
  });
}
