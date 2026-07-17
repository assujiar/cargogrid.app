/**
 * Shared authorization guard (PLT-112, CG-S6-PLT-009). This is the exact module path
 * docs/architecture/06_RLS_RBAC_WORKSTREAM.md §3 already names as the shared kernel every
 * REST/GraphQL/server-action/job entry point calls for stages 3-8 of the access flow --
 * "the same underlying stages 3-8 ... via the shared server/policies/permission-check.ts
 * module" -- reused here, not reinvented under a new name.
 *
 * assertPermission() either returns a granted app.rbac_decision or throws
 * RbacDenialError -- there is no "denied but proceed" path, matching the fail-closed
 * discipline every evaluator in this repository has followed since PLT-106.
 *
 * Wiring this guard into a live REST/GraphQL/server-action/job entry point remains
 * disclosed NOT_RUN -- no such surface exists yet in this repository (Phase 1 has not
 * reached PLT-129-132, API/Jobs, or PLT-135/136, the Admin portals). This is the
 * "representative adapter" Prompt 112 §11 calls for, proven against injected structural
 * clients today exactly as PLT-108's resolveAccessContext() was.
 */

import type { RbacDecision } from "../contracts/rbac/rbac.ts";
import { evaluatePermission, type RbacDecisionCache, type RbacRpcClient } from "../queries/rbac.ts";

export type PermissionCheckInput = {
  authUserId: string;
  tenantId: string;
  resourceModuleCode: string;
  action: string;
};

/** Denial reasons from app.evaluate_permission (Prompt 112 §18: audited without leaking resource existence beyond the permission the caller already named). */
export const RBAC_DENIAL_REASONS = ["unknown_permission", "no_granting_role", "no_active_assignment"] as const;
export type RbacDenialReason = (typeof RBAC_DENIAL_REASONS)[number] | string;

export class RbacDenialError extends Error {
  readonly reason: RbacDenialReason;
  readonly input: PermissionCheckInput;

  constructor(reason: RbacDenialReason, input: PermissionCheckInput) {
    super(`permission denied: ${input.resourceModuleCode}:${input.action} (${reason})`);
    this.name = "RbacDenialError";
    this.reason = reason;
    this.input = input;
  }
}

/**
 * The base guard: resolves a decision (cached if a cache is supplied) and throws
 * RbacDenialError unless allowed. Callers that just performed a PLT-111 mutation on this
 * identity's roles/assignments must call `cache.invalidate(tenantId, authUserId)` first,
 * or pass no cache at all for a guaranteed-fresh check.
 */
export async function assertPermission(
  client: RbacRpcClient,
  input: PermissionCheckInput,
  cache?: RbacDecisionCache,
): Promise<RbacDecision> {
  const decision = await evaluatePermission(
    client,
    {
      authUserId: input.authUserId,
      tenantId: input.tenantId,
      resourceModuleCode: input.resourceModuleCode,
      action: input.action,
    },
    cache,
  );

  if (!decision.allowed) {
    throw new RbacDenialError(decision.reason, input);
  }
  return decision;
}
