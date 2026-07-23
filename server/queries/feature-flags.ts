/**
 * Feature flag evaluation query (PLT-133, CG-S6-PLT-030). Thin, typed wrapper around
 * app.evaluate_feature_flag
 * (supabase/migrations/20260721090000_create_feature_flags_platform.sql), plus a cache
 * keyed by environment/tenant/cohort (Prompt 133 §17: "Compiled/cache evaluation by
 * environment/tenant/module/cohort/version with prompt invalidation") with *explicit*
 * invalidation -- the same shape PLT-106/117/118/119/121's own caches already
 * established. Module is not a separate cache dimension: it is baked into the flag's
 * own registration (server-side, immutable per flag_key), not a per-call parameter.
 *
 * Read-only (server/queries/, not server/mutations/) per
 * docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8's queries-vs-mutations split.
 */

import {
  EvaluateFeatureFlagInputSchema,
  parseFeatureFlagDecision,
  type EvaluateFeatureFlagInput,
  type FeatureFlagDecision,
} from "../contracts/feature-flag/feature-flag.ts";

export interface FeatureFlagRpcClient {
  rpc(fn: "evaluate_feature_flag", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class FeatureFlagQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FeatureFlagQueryError";
  }
}

function cacheKey(input: EvaluateFeatureFlagInput): string {
  return [input.flagKey, input.tenantId ?? "", input.environment, [...(input.cohorts ?? [])].sort().join(",")].join("::");
}

interface CacheEntry {
  readonly decision: FeatureFlagDecision;
  readonly expiresAt: number;
}

/**
 * A resolved decision is cached by its own (flag, tenant, environment, cohort) key,
 * bounded by a TTL as defense in depth. `invalidate()` drops every cached entry --
 * the mutation layer (server/mutations/feature-flags.ts) calls this after every
 * register/set/publish/discard/rollback/kill, so a stale decision (in particular a
 * just-issued kill) never outlives the write that changed it, regardless of the TTL.
 * The resolved version_id inside each cached FeatureFlagDecision is itself a natural
 * staleness signal a caller can additionally compare against, mirroring
 * PLT-121's app.verify_config_version_current pattern -- no separate verify RPC exists
 * for flags since a fresh evaluate_feature_flag call is already cheap and authoritative.
 */
export class FeatureFlagCache {
  private readonly byKey = new Map<string, CacheEntry>();
  private readonly ttlMs: number;

  constructor(ttlMs: number) {
    this.ttlMs = ttlMs;
  }

  get(input: EvaluateFeatureFlagInput, now: number): FeatureFlagDecision | undefined {
    const entry = this.byKey.get(cacheKey(input));
    if (!entry || entry.expiresAt <= now) return undefined;
    return entry.decision;
  }

  set(input: EvaluateFeatureFlagInput, decision: FeatureFlagDecision, now: number): void {
    this.byKey.set(cacheKey(input), { decision, expiresAt: now + this.ttlMs });
  }

  invalidate(): void {
    this.byKey.clear();
  }
}

export async function evaluateFeatureFlag(
  client: FeatureFlagRpcClient,
  input: EvaluateFeatureFlagInput,
  cache?: FeatureFlagCache,
  now: number = Date.now(),
): Promise<FeatureFlagDecision> {
  const parsedInput = EvaluateFeatureFlagInputSchema.parse(input);

  if (cache) {
    const cached = cache.get(parsedInput, now);
    if (cached) return cached;
  }

  const { data, error } = await client.rpc("evaluate_feature_flag", {
    p_flag_key: parsedInput.flagKey,
    p_tenant_id: parsedInput.tenantId,
    p_environment: parsedInput.environment,
    p_cohorts: parsedInput.cohorts,
    p_now: parsedInput.now ?? new Date(now).toISOString(),
  });

  if (error) {
    throw new FeatureFlagQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FeatureFlagQueryError("evaluate_feature_flag returned no decision");
  }

  const decision = parseFeatureFlagDecision(data as Record<string, unknown>);
  cache?.set(parsedInput, decision, now);
  return decision;
}
