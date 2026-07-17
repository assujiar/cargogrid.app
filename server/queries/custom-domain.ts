/**
 * Tenant custom-domain read queries (PLT-118, CG-S6-PLT-015). Thin, typed wrappers
 * around app.list_tenant_domains (authority-gated, service_role) and
 * app.resolve_tenant_by_domain (public, anon-callable) --
 * supabase/migrations/20260717103015_create_custom_domain.sql. Both are "queries" in
 * this repository's server/queries/-vs-server/mutations/ split
 * (docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md §8) since neither mutates state.
 */

import {
  ListTenantDomainsInputSchema,
  ResolveTenantByDomainInputSchema,
  parseTenantCustomDomain,
  parseResolvedTenantDomain,
  type ListTenantDomainsInput,
  type ResolveTenantByDomainInput,
  type ResolvedTenantDomain,
  type TenantCustomDomain,
} from "../contracts/custom-domain/custom-domain.ts";

export interface CustomDomainQueryRpcClient {
  rpc(
    fn: "list_tenant_domains" | "resolve_tenant_by_domain",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const CUSTOM_DOMAIN_KNOWN_QUERY_ERROR_CODES = ["insufficient_authority"] as const;
type KnownCustomDomainQueryErrorCode = (typeof CUSTOM_DOMAIN_KNOWN_QUERY_ERROR_CODES)[number];
export type CustomDomainQueryErrorCode = KnownCustomDomainQueryErrorCode | "query_failed";

export class CustomDomainQueryError extends Error {
  readonly code: CustomDomainQueryErrorCode;

  constructor(code: CustomDomainQueryErrorCode, message: string) {
    super(message);
    this.name = "CustomDomainQueryError";
    this.code = code;
  }
}

function classifyError(message: string): CustomDomainQueryErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CUSTOM_DOMAIN_KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownCustomDomainQueryErrorCode)
    : "query_failed";
}

/** Every one of a tenant's domains, any lifecycle status -- the admin view-model read path (Prompt 118 §15). */
export async function listTenantDomains(client: CustomDomainQueryRpcClient, input: ListTenantDomainsInput): Promise<TenantCustomDomain[]> {
  const parsedInput = ListTenantDomainsInputSchema.parse(input);
  const { data, error } = await client.rpc("list_tenant_domains", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });

  if (error) {
    throw new CustomDomainQueryError(classifyError(error.message), error.message);
  }
  if (!Array.isArray(data)) {
    throw new CustomDomainQueryError("query_failed", "list_tenant_domains returned a non-array result");
  }
  return data.map((row) => parseTenantCustomDomain(row as Record<string, unknown>));
}

interface CacheEntry {
  readonly resolved: ResolvedTenantDomain | null;
  readonly expiresAt: number;
}

/**
 * Per-hostname resolution cache -- the hot-path lookup every inbound request needs
 * (Prompt 118 §17: "Cache domain->tenant safely with invalidation; resolution on hot
 * path bounded"). Caches a negative (`null`) result too, deliberately short-lived via
 * the same TTL as a positive one -- a freshly-activated domain must become resolvable
 * without waiting out a long negative-cache window. `invalidate(hostname)` gives
 * immediate freshness after any lifecycle mutation (activate/disable), the same
 * explicit-invalidation shape PLT-106's EntitlementCache and PLT-117's
 * WhiteLabelBrandCache already established.
 */
export class DomainResolutionCache {
  private readonly byHostname = new Map<string, CacheEntry>();
  private readonly ttlMs: number;

  constructor(ttlMs: number) {
    this.ttlMs = ttlMs;
  }

  get(hostname: string, now: number): { hit: true; resolved: ResolvedTenantDomain | null } | { hit: false } {
    const entry = this.byHostname.get(hostname);
    if (!entry || entry.expiresAt <= now) return { hit: false };
    return { hit: true, resolved: entry.resolved };
  }

  set(hostname: string, resolved: ResolvedTenantDomain | null, now: number): void {
    this.byHostname.set(hostname, { resolved, expiresAt: now + this.ttlMs });
  }

  invalidate(hostname: string): void {
    this.byHostname.delete(hostname);
  }
}

/** Resolves a hostname to its live tenant, or null if no domain is currently active for it (or its tenant is not). Never an authorization decision -- routing/presentation context only, see the migration's own header. */
export async function resolveTenantByDomain(
  client: CustomDomainQueryRpcClient,
  input: ResolveTenantByDomainInput,
  cache?: DomainResolutionCache,
  now: number = Date.now(),
): Promise<ResolvedTenantDomain | null> {
  const parsedInput = ResolveTenantByDomainInputSchema.parse(input);
  const hostname = parsedInput.hostname.toLowerCase();

  if (cache) {
    const cached = cache.get(hostname, now);
    if (cached.hit) return cached.resolved;
  }

  const { data, error } = await client.rpc("resolve_tenant_by_domain", { p_hostname: hostname });

  if (error) {
    throw new CustomDomainQueryError("query_failed", error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  const resolved = row && typeof row === "object" ? parseResolvedTenantDomain(row as Record<string, unknown>) : null;
  cache?.set(hostname, resolved, now);
  return resolved;
}
