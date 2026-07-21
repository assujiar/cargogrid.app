/**
 * Effective tenant brand evaluation query (PLT-117, CG-S6-PLT-014). Thin, typed wrapper
 * around app.evaluate_tenant_brand
 * (supabase/migrations/20260717090512_create_white_label.sql) plus a per-tenant cache
 * with the same explicit-invalidation shape PLT-106's EntitlementCache already
 * established (server/queries/entitlement.ts). Unlike entitlement, a fresh
 * publish/rollback always produces a new version_id (PLT-111/117's "never mutate a
 * historical snapshot" discipline), so a cached decision can never silently point at
 * stale token content even past its TTL -- invalidate() is still provided for symmetry
 * and immediate freshness after a mutation, but is not load-bearing correctness the way
 * PLT-106's own cache invalidation is (Prompt 117 §14, disclosed here rather than
 * implied).
 *
 * Read-only (server/queries/, not server/mutations/) per
 * docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8's queries-vs-mutations split.
 * Callable by anon as well as authenticated -- see the migration's own comment on
 * app.evaluate_tenant_brand for why (public, pre-authentication presentation data).
 */

import {
  EvaluateTenantBrandInputSchema,
  parseEffectiveTenantBrand,
  type EffectiveTenantBrand,
  type EvaluateTenantBrandInput,
} from "../contracts/white-label/white-label.ts";

export interface WhiteLabelQueryRpcClient {
  rpc(
    fn: "evaluate_tenant_brand",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class WhiteLabelQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WhiteLabelQueryError";
  }
}

interface CacheEntry {
  readonly brand: EffectiveTenantBrand;
  readonly expiresAt: number;
}

/** Per-tenant effective-brand cache. `invalidate(tenantId)` drops the cached entry immediately -- see this module's header for why it is a freshness optimization here, not the sole correctness mechanism. */
export class WhiteLabelBrandCache {
  private readonly byTenant = new Map<string, CacheEntry>();
  private readonly ttlMs: number;

  constructor(ttlMs: number) {
    this.ttlMs = ttlMs;
  }

  get(tenantId: string, now: number): EffectiveTenantBrand | undefined {
    const entry = this.byTenant.get(tenantId);
    if (!entry || entry.expiresAt <= now) return undefined;
    return entry.brand;
  }

  set(tenantId: string, brand: EffectiveTenantBrand, now: number): void {
    this.byTenant.set(tenantId, { brand, expiresAt: now + this.ttlMs });
  }

  invalidate(tenantId: string): void {
    this.byTenant.delete(tenantId);
  }
}

/** Resolves a tenant's effective white-label brand: the current published version, or the accessible CargoGrid default (Prompt 117 §22) if the tenant has none, is inactive, or does not exist. */
export async function evaluateTenantBrand(
  client: WhiteLabelQueryRpcClient,
  input: EvaluateTenantBrandInput,
  cache?: WhiteLabelBrandCache,
  now: number = Date.now(),
): Promise<EffectiveTenantBrand> {
  const parsedInput = EvaluateTenantBrandInputSchema.parse(input);

  if (cache) {
    const cached = cache.get(parsedInput.tenantId, now);
    if (cached) return cached;
  }

  const { data, error } = await client.rpc("evaluate_tenant_brand", {
    p_tenant_id: parsedInput.tenantId,
  });

  if (error) {
    throw new WhiteLabelQueryError(error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new WhiteLabelQueryError("evaluate_tenant_brand returned no row");
  }

  const brand = parseEffectiveTenantBrand(row as Record<string, unknown>);
  cache?.set(parsedInput.tenantId, brand, now);
  return brand;
}
