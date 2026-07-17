/**
 * Entitlement evaluation query (PLT-106, CG-S6-PLT-003). Thin, typed wrapper around
 * app.evaluate_entitlement (supabase/migrations/20260716094432_create_entitlements.sql)
 * plus a per-tenant cache with *explicit* invalidation (Prompt 106 §17/§25: "Cache
 * invalidates on assignment/version/lifecycle change" -- not merely a TTL hope). The TTL
 * below is defense-in-depth only, matching the same bounded-freshness discipline
 * scripts/feature-flags/flags.ts's FlagCache already established at Phase 0 -- a
 * deliberately separate, tenant-keyed cache, not a reuse of that module (a different
 * concept: FLAG is release/rollout control, TEN-IAM entitlement is subscription/package
 * business access -- docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md line 73).
 *
 * Read-only (server/queries/, not server/mutations/) per
 * docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8's queries-vs-mutations split.
 */

import {
  EvaluateEntitlementInputSchema,
  parseEntitlementDecision,
  type EntitlementDecision,
  type EvaluateEntitlementInput,
} from "../contracts/entitlement/entitlement.ts";

export interface EntitlementRpcClient {
  rpc(
    fn: "evaluate_entitlement",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class EntitlementServiceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EntitlementServiceError";
  }
}

interface CacheEntry {
  readonly decision: EntitlementDecision;
  readonly expiresAt: number;
}

/**
 * Per-tenant entitlement decision cache. `invalidate(tenantId)` drops every cached
 * decision for that tenant in one call -- the mutation layer (server/mutations/entitlement.ts)
 * calls this after every assignment/transition/override write, so a stale decision never
 * outlives the write that changed it, regardless of the TTL.
 */
export class EntitlementCache {
  private readonly byTenant = new Map<string, Map<string, CacheEntry>>();
  private readonly ttlMs: number;

  constructor(ttlMs: number) {
    this.ttlMs = ttlMs;
  }

  private key(moduleCode: string, featureCode: string | undefined): string {
    return `${moduleCode}::${featureCode ?? ""}`;
  }

  get(tenantId: string, moduleCode: string, featureCode: string | undefined, now: number): EntitlementDecision | undefined {
    const tenantEntries = this.byTenant.get(tenantId);
    if (!tenantEntries) return undefined;
    const entry = tenantEntries.get(this.key(moduleCode, featureCode));
    if (!entry || entry.expiresAt <= now) return undefined;
    return entry.decision;
  }

  set(tenantId: string, moduleCode: string, featureCode: string | undefined, decision: EntitlementDecision, now: number): void {
    let tenantEntries = this.byTenant.get(tenantId);
    if (!tenantEntries) {
      tenantEntries = new Map();
      this.byTenant.set(tenantId, tenantEntries);
    }
    tenantEntries.set(this.key(moduleCode, featureCode), { decision, expiresAt: now + this.ttlMs });
  }

  invalidate(tenantId: string): void {
    this.byTenant.delete(tenantId);
  }
}

export async function evaluateEntitlement(
  client: EntitlementRpcClient,
  input: EvaluateEntitlementInput,
  cache?: EntitlementCache,
  now: number = Date.now(),
): Promise<EntitlementDecision> {
  const parsedInput = EvaluateEntitlementInputSchema.parse(input);

  if (cache) {
    const cached = cache.get(parsedInput.tenantId, parsedInput.moduleCode, parsedInput.featureCode, now);
    if (cached) return cached;
  }

  const { data, error } = await client.rpc("evaluate_entitlement", {
    p_tenant_id: parsedInput.tenantId,
    p_module_code: parsedInput.moduleCode,
    p_feature_code: parsedInput.featureCode ?? null,
    p_as_of: parsedInput.asOf ?? new Date(now).toISOString(),
  });

  if (error) {
    throw new EntitlementServiceError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EntitlementServiceError("evaluate_entitlement returned no decision");
  }

  const decision = parseEntitlementDecision(data as Record<string, unknown>);
  cache?.set(parsedInput.tenantId, parsedInput.moduleCode, parsedInput.featureCode, decision, now);
  return decision;
}
