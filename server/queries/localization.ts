/**
 * Locale-context read queries (PLT-119, CG-S6-PLT-016). Thin, typed wrapper around
 * app.resolve_locale_context (supabase/migrations/20260717112000_create_localization.sql)
 * plus a per-(tenant,user) cache with the same explicit-invalidation shape PLT-106/117/118's
 * caches already established. Read-only (server/queries/), callable by anon as well as
 * authenticated -- a tenant's login page must render in the correct language/timezone/
 * currency format before a session exists.
 */

import {
  ResolveLocaleContextInputSchema,
  parseLocaleContext,
  type LocaleContext,
  type ResolveLocaleContextInput,
} from "../contracts/localization/localization.ts";

export interface LocalizationQueryRpcClient {
  rpc(
    fn: "resolve_locale_context",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class LocalizationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LocalizationQueryError";
  }
}

interface CacheEntry {
  readonly context: LocaleContext;
  readonly expiresAt: number;
}

function cacheKey(tenantId: string, userAuthUserId: string | null): string {
  return `${tenantId}::${userAuthUserId ?? ""}`;
}

/** Per-(tenant,user) locale-context cache. `invalidate(tenantId)` drops every cached entry for that tenant -- a fresh publish/rollback always produces a new source/version, so this is a freshness optimization, not the sole correctness mechanism (same disclosure as WhiteLabelBrandCache/DomainResolutionCache). */
export class LocaleContextCache {
  private readonly byKey = new Map<string, { readonly tenantId: string } & CacheEntry>();
  private readonly ttlMs: number;

  constructor(ttlMs: number) {
    this.ttlMs = ttlMs;
  }

  get(tenantId: string, userAuthUserId: string | null, now: number): LocaleContext | undefined {
    const entry = this.byKey.get(cacheKey(tenantId, userAuthUserId));
    if (!entry || entry.expiresAt <= now) return undefined;
    return entry.context;
  }

  set(tenantId: string, userAuthUserId: string | null, context: LocaleContext, now: number): void {
    this.byKey.set(cacheKey(tenantId, userAuthUserId), { tenantId, context, expiresAt: now + this.ttlMs });
  }

  invalidate(tenantId: string): void {
    for (const [key, entry] of this.byKey) {
      if (entry.tenantId === tenantId) this.byKey.delete(key);
    }
  }
}

/** Resolves the real three-tier locale/timezone/currency/terminology context (user -> tenant -> platform default, Prompt 119 §22). */
export async function resolveLocaleContext(
  client: LocalizationQueryRpcClient,
  input: ResolveLocaleContextInput,
  cache?: LocaleContextCache,
  now: number = Date.now(),
): Promise<LocaleContext> {
  const parsedInput = ResolveLocaleContextInputSchema.parse(input);

  if (cache) {
    const cached = cache.get(parsedInput.tenantId, parsedInput.userAuthUserId, now);
    if (cached) return cached;
  }

  const { data, error } = await client.rpc("resolve_locale_context", {
    p_tenant_id: parsedInput.tenantId,
    p_user_auth_user_id: parsedInput.userAuthUserId,
  });

  if (error) {
    throw new LocalizationQueryError(error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new LocalizationQueryError("resolve_locale_context returned no row");
  }

  const context = parseLocaleContext(row as Record<string, unknown>);
  cache?.set(parsedInput.tenantId, parsedInput.userAuthUserId, context, now);
  return context;
}
