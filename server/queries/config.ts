/**
 * Configuration resolution read queries (PLT-121, CG-S6-PLT-018). Thin, typed wrappers
 * around app.resolve_config / app.verify_config_version_current
 * (supabase/migrations/20260717130000_create_configuration_engine.sql), plus a cache
 * with the same explicit-invalidation shape PLT-106/117/118/119's caches already
 * established (Tech Arch §13.6, docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md
 * §9: "Published configuration is cached by tenant_id + config_type + scope + version;
 * draft config is never globally cached; cache is invalidated on publish/rollback").
 */

import {
  ResolveConfigInputSchema,
  VerifyConfigVersionCurrentInputSchema,
  parseResolvedConfig,
  type ResolveConfigInput,
  type ResolvedConfig,
  type VerifyConfigVersionCurrentInput,
} from "../contracts/config/config.ts";

export interface ConfigQueryRpcClient {
  rpc(
    fn: "resolve_config" | "verify_config_version_current",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class ConfigQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigQueryError";
  }
}

function cacheKey(input: ResolveConfigInput): string {
  return [input.configTypeCode, input.tenantId ?? "", input.companyId ?? "", input.branchId ?? "", input.roleId ?? "", input.userId ?? ""].join("::");
}

interface CacheEntry {
  readonly resolved: ResolvedConfig | null;
  readonly expiresAt: number;
}

/** Draft config is never cached (this module never sees draft rows at all -- app.resolve_config() only ever returns published data). `invalidate()` drops every cached entry -- a publish/rollback anywhere should call it, since a single scope key change can shift resolution for every narrower scope beneath it. */
export class ConfigResolutionCache {
  private readonly byKey = new Map<string, CacheEntry>();
  private readonly ttlMs: number;

  constructor(ttlMs: number) {
    this.ttlMs = ttlMs;
  }

  get(input: ResolveConfigInput, now: number): { hit: true; resolved: ResolvedConfig | null } | { hit: false } {
    const entry = this.byKey.get(cacheKey(input));
    if (!entry || entry.expiresAt <= now) return { hit: false };
    return { hit: true, resolved: entry.resolved };
  }

  set(input: ResolveConfigInput, resolved: ResolvedConfig | null, now: number): void {
    this.byKey.set(cacheKey(input), { resolved, expiresAt: now + this.ttlMs });
  }

  invalidate(): void {
    this.byKey.clear();
  }
}

/** Resolves the effective configuration for a config_type via the real 6-level precedence walk (user -> role -> branch -> company -> tenant -> global). Returns null if no level -- not even global -- currently has an effective published version. */
export async function resolveConfig(
  client: ConfigQueryRpcClient,
  input: ResolveConfigInput,
  cache?: ConfigResolutionCache,
  now: number = Date.now(),
): Promise<ResolvedConfig | null> {
  const parsedInput = ResolveConfigInputSchema.parse(input);

  if (cache) {
    const cached = cache.get(parsedInput, now);
    if (cached.hit) return cached.resolved;
  }

  const { data, error } = await client.rpc("resolve_config", {
    p_config_type_code: parsedInput.configTypeCode,
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_branch_id: parsedInput.branchId,
    p_role_id: parsedInput.roleId,
    p_user_id: parsedInput.userId,
  });

  if (error) {
    throw new ConfigQueryError(error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  const resolved = row && typeof row === "object" ? parseResolvedConfig(row as Record<string, unknown>) : null;
  cache?.set(parsedInput, resolved, now);
  return resolved;
}

/** EXC-CFG-001's real check: re-resolves precedence right now and compares against a previously-resolved version_id, catching a publish/rollback that happened in between. */
export async function verifyConfigVersionCurrent(client: ConfigQueryRpcClient, input: VerifyConfigVersionCurrentInput): Promise<boolean> {
  const parsedInput = VerifyConfigVersionCurrentInputSchema.parse(input);
  const { data, error } = await client.rpc("verify_config_version_current", {
    p_config_type_code: parsedInput.configTypeCode,
    p_tenant_id: parsedInput.tenantId,
    p_expected_version_id: parsedInput.expectedVersionId,
    p_company_id: parsedInput.companyId,
    p_branch_id: parsedInput.branchId,
    p_role_id: parsedInput.roleId,
    p_user_id: parsedInput.userId,
  });

  if (error) {
    throw new ConfigQueryError(error.message);
  }
  if (typeof data !== "boolean") {
    throw new ConfigQueryError("verify_config_version_current returned a non-boolean result");
  }
  return data;
}
