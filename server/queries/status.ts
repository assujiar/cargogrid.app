/**
 * Status resolution read queries (PLT-124, CG-S6-PLT-021). Thin, typed wrappers around
 * app.resolve_legacy_status / app.get_status_set_registry /
 * app.resolve_status_presentation
 * (supabase/migrations/20260719100000_create_status_engine.sql), plus a cache with the
 * same explicit-invalidation shape PLT-106/117/118/119/121's caches already
 * established.
 */

import {
  ResolveLegacyStatusInputSchema,
  GetStatusSetRegistryInputSchema,
  ResolveStatusPresentationInputSchema,
  parseCanonicalStatus,
  parseResolvedStatusPresentation,
  type ResolveLegacyStatusInput,
  type GetStatusSetRegistryInput,
  type ResolveStatusPresentationInput,
  type CanonicalStatus,
  type ResolvedStatusPresentation,
} from "../contracts/status/status.ts";

export interface StatusQueryRpcClient {
  rpc(
    fn: "resolve_legacy_status" | "get_status_set_registry" | "resolve_status_presentation",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class StatusQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "StatusQueryError";
  }
}

/** Raises status_legacy_value_unmapped if no mapping exists for this legacy value in this set. */
export async function resolveLegacyStatus(client: StatusQueryRpcClient, input: ResolveLegacyStatusInput): Promise<CanonicalStatus> {
  const parsedInput = ResolveLegacyStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("resolve_legacy_status", {
    p_status_set_code: parsedInput.statusSetCode,
    p_legacy_value: parsedInput.legacyValue,
  });
  if (error) {
    throw new StatusQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new StatusQueryError("resolve_legacy_status returned no row");
  }
  return parseCanonicalStatus(data as Record<string, unknown>);
}

/** Every canonical status in a set, ordered by sort_order -- the reusable registry view model for building status pickers/filters. */
export async function getStatusSetRegistry(client: StatusQueryRpcClient, input: GetStatusSetRegistryInput): Promise<CanonicalStatus[]> {
  const parsedInput = GetStatusSetRegistryInputSchema.parse(input);
  const { data, error } = await client.rpc("get_status_set_registry", {
    p_status_set_code: parsedInput.statusSetCode,
  });
  if (error) {
    throw new StatusQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new StatusQueryError("get_status_set_registry returned a non-array result");
  }
  return data.map((row) => parseCanonicalStatus(row as Record<string, unknown>));
}

function cacheKey(input: ResolveStatusPresentationInput): string {
  return [
    input.statusSetCode,
    input.canonicalStatusCode,
    input.tenantId,
    input.companyId ?? "",
    input.branchId ?? "",
    input.roleId ?? "",
    input.userId ?? "",
  ].join("::");
}

interface CacheEntry {
  readonly resolved: ResolvedStatusPresentation;
  readonly expiresAt: number;
}

/** Never caches a null/missing result (resolve_status_presentation always resolves a real canonical status or throws -- there is no "no result" case to cache). `invalidate()` drops every cached entry -- a presentation publish/rollback anywhere should call it. */
export class StatusPresentationCache {
  private readonly byKey = new Map<string, CacheEntry>();
  private readonly ttlMs: number;

  constructor(ttlMs: number) {
    this.ttlMs = ttlMs;
  }

  get(input: ResolveStatusPresentationInput, now: number): { hit: true; resolved: ResolvedStatusPresentation } | { hit: false } {
    const entry = this.byKey.get(cacheKey(input));
    if (!entry || entry.expiresAt <= now) return { hit: false };
    return { hit: true, resolved: entry.resolved };
  }

  set(input: ResolveStatusPresentationInput, resolved: ResolvedStatusPresentation, now: number): void {
    this.byKey.set(cacheKey(input), { resolved, expiresAt: now + this.ttlMs });
  }

  invalidate(): void {
    this.byKey.clear();
  }
}

/** Resolves a canonical status's effective tenant presentation via the real 6-level precedence walk, falling back to a structural, code-derived label/neutral icon (never a fabricated tenant-specific color) when nothing has published yet. Raises status_unknown_code only if the canonical code itself was never registered. */
export async function resolveStatusPresentation(
  client: StatusQueryRpcClient,
  input: ResolveStatusPresentationInput,
  cache?: StatusPresentationCache,
  now: number = Date.now(),
): Promise<ResolvedStatusPresentation> {
  const parsedInput = ResolveStatusPresentationInputSchema.parse(input);

  if (cache) {
    const cached = cache.get(parsedInput, now);
    if (cached.hit) return cached.resolved;
  }

  const { data, error } = await client.rpc("resolve_status_presentation", {
    p_status_set_code: parsedInput.statusSetCode,
    p_canonical_status_code: parsedInput.canonicalStatusCode,
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_branch_id: parsedInput.branchId,
    p_role_id: parsedInput.roleId,
    p_user_id: parsedInput.userId,
  });

  if (error) {
    throw new StatusQueryError(error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new StatusQueryError("resolve_status_presentation returned no row");
  }
  const resolved = parseResolvedStatusPresentation(row as Record<string, unknown>);
  cache?.set(parsedInput, resolved, now);
  return resolved;
}
