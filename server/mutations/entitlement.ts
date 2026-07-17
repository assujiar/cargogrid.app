/**
 * Entitlement assignment/transition service (PLT-106, CG-S6-PLT-003). Thin, typed wrapper
 * around app.assign_entitlement / app.transition_entitlement_status
 * (supabase/migrations/20260716094432_create_entitlements.sql). Every successful write
 * invalidates the caller-supplied EntitlementCache for that tenant (server/queries/entitlement.ts)
 * -- the explicit invalidation Prompt 106 §17/§25 requires, not a TTL-only hope.
 */

import {
  AssignEntitlementInputSchema,
  TransitionEntitlementInputSchema,
  type AssignEntitlementInput,
  type TransitionEntitlementInput,
} from "../contracts/entitlement/entitlement.ts";
import type { EntitlementCache } from "../queries/entitlement.ts";

export interface EntitlementMutationClient {
  rpc(
    fn: "assign_entitlement" | "transition_entitlement_status",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export type EntitlementMutationErrorCode = "assign_failed" | "transition_failed" | "invalid_response";

export class EntitlementMutationError extends Error {
  readonly code: EntitlementMutationErrorCode;

  constructor(code: EntitlementMutationErrorCode, message: string) {
    super(message);
    this.name = "EntitlementMutationError";
    this.code = code;
  }
}

export async function assignEntitlement(
  client: EntitlementMutationClient,
  input: AssignEntitlementInput,
  cache?: EntitlementCache,
): Promise<void> {
  const parsedInput = AssignEntitlementInputSchema.parse(input);

  const { data, error } = await client.rpc("assign_entitlement", {
    p_tenant_id: parsedInput.tenantId,
    p_package_id: parsedInput.packageId,
    p_status: parsedInput.status,
    p_reason: parsedInput.reason,
    p_requested_by: parsedInput.requestedBy,
    p_trial_ends_at: parsedInput.trialEndsAt ?? null,
    p_effective_from: parsedInput.effectiveFrom ?? new Date().toISOString(),
    p_effective_until: parsedInput.effectiveUntil ?? null,
  });

  if (error) {
    throw new EntitlementMutationError("assign_failed", error.message);
  }
  if (!data) {
    throw new EntitlementMutationError("invalid_response", "assign_entitlement returned no row");
  }
  cache?.invalidate(parsedInput.tenantId);
}

export async function transitionEntitlementStatus(
  client: EntitlementMutationClient,
  input: TransitionEntitlementInput,
  cache?: EntitlementCache,
): Promise<void> {
  const parsedInput = TransitionEntitlementInputSchema.parse(input);

  const { data, error } = await client.rpc("transition_entitlement_status", {
    p_tenant_id: parsedInput.tenantId,
    p_new_status: parsedInput.newStatus,
    p_reason: parsedInput.reason,
    p_requested_by: parsedInput.requestedBy,
  });

  if (error) {
    throw new EntitlementMutationError("transition_failed", error.message);
  }
  if (!data) {
    throw new EntitlementMutationError("invalid_response", "transition_entitlement_status returned no row");
  }
  cache?.invalidate(parsedInput.tenantId);
}
