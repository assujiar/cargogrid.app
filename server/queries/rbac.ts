/**
 * RBAC evaluation query (PLT-112, CG-S6-PLT-009). Thin, typed wrapper around
 * app.evaluate_permission (supabase/migrations/20260716104519_create_rbac_evaluator.sql)
 * plus a per-tenant-and-identity cache with *explicit* invalidation -- the same
 * discipline PLT-106's EntitlementCache established, deliberately a separate cache
 * instance (RBAC role/permission decisions are a distinct concept from TEN-IAM
 * entitlement, per the same reasoning that already kept FlagCache and EntitlementCache
 * apart at Phase 0/PLT-106). Callers must invalidate(tenantId, authUserId) after any
 * PLT-111 mutation affecting that identity's role assignments or role versions
 * (assign/revoke/publish) -- this checkpoint does not modify PLT-111's own files to wire
 * that call automatically (see PLT-112.md §3.3 for the disclosed caller contract).
 *
 * Read-only (server/queries/, per docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8).
 */

import {
  EvaluatePermissionInputSchema,
  parseRbacDecision,
  type EvaluatePermissionInput,
  type RbacDecision,
} from "../contracts/rbac/rbac.ts";

export interface RbacRpcClient {
  rpc(
    fn: "evaluate_permission",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class RbacEvaluationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RbacEvaluationError";
  }
}

interface CacheEntry {
  readonly decision: RbacDecision;
  readonly expiresAt: number;
}

/**
 * Per-(tenant, identity) RBAC decision cache. `invalidate(tenantId, authUserId)` drops
 * every cached decision for that identity in that tenant in one call. The TTL is
 * defense-in-depth only, matching PLT-106's EntitlementCache -- explicit invalidation is
 * the real freshness guarantee, not the timer.
 */
export class RbacDecisionCache {
  private readonly byIdentity = new Map<string, Map<string, CacheEntry>>();
  private readonly ttlMs: number;

  constructor(ttlMs: number) {
    this.ttlMs = ttlMs;
  }

  private identityKey(tenantId: string, authUserId: string): string {
    return `${tenantId}::${authUserId}`;
  }

  private permissionKey(resourceModuleCode: string, action: string): string {
    return `${resourceModuleCode}:${action}`;
  }

  get(tenantId: string, authUserId: string, resourceModuleCode: string, action: string, now: number): RbacDecision | undefined {
    const identityEntries = this.byIdentity.get(this.identityKey(tenantId, authUserId));
    if (!identityEntries) return undefined;
    const entry = identityEntries.get(this.permissionKey(resourceModuleCode, action));
    if (!entry || entry.expiresAt <= now) return undefined;
    return entry.decision;
  }

  set(tenantId: string, authUserId: string, resourceModuleCode: string, action: string, decision: RbacDecision, now: number): void {
    const key = this.identityKey(tenantId, authUserId);
    let identityEntries = this.byIdentity.get(key);
    if (!identityEntries) {
      identityEntries = new Map();
      this.byIdentity.set(key, identityEntries);
    }
    identityEntries.set(this.permissionKey(resourceModuleCode, action), { decision, expiresAt: now + this.ttlMs });
  }

  invalidate(tenantId: string, authUserId: string): void {
    this.byIdentity.delete(this.identityKey(tenantId, authUserId));
  }
}

export async function evaluatePermission(
  client: RbacRpcClient,
  input: EvaluatePermissionInput,
  cache?: RbacDecisionCache,
  now: number = Date.now(),
): Promise<RbacDecision> {
  const parsedInput = EvaluatePermissionInputSchema.parse(input);

  if (cache) {
    const cached = cache.get(parsedInput.tenantId, parsedInput.authUserId, parsedInput.resourceModuleCode, parsedInput.action, now);
    if (cached) return cached;
  }

  const { data, error } = await client.rpc("evaluate_permission", {
    p_auth_user_id: parsedInput.authUserId,
    p_tenant_id: parsedInput.tenantId,
    p_resource_module_code: parsedInput.resourceModuleCode,
    p_action: parsedInput.action,
    p_as_of: parsedInput.asOf ?? new Date(now).toISOString(),
  });

  if (error) {
    throw new RbacEvaluationError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new RbacEvaluationError("evaluate_permission returned no decision");
  }

  const decision = parseRbacDecision(data as Record<string, unknown>);
  cache?.set(parsedInput.tenantId, parsedInput.authUserId, parsedInput.resourceModuleCode, parsedInput.action, decision, now);
  return decision;
}
