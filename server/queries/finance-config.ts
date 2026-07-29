/**
 * Finance Configuration read queries (FIN-191, CG-S9-FIN-002). Thin, typed
 * wrappers around app.resolve_finance_config / app.preview_finance_config_impact
 * (supabase/migrations/20260728200000_create_finance_configuration.sql), plus a
 * direct read of the reference app.finance_rounding_modes table and the
 * generic app.list_config_versions RPC (scoped to a Finance config_type_code).
 *
 * Reuses PLT-121's own resolution-cache shape (server/queries/config.ts) --
 * "Published configuration is cached by tenant_id + config_type + scope +
 * version; draft config is never globally cached; cache is invalidated on
 * publish/rollback" (docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md §9),
 * the same contract Finance Configuration inherits unchanged.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ResolveFinanceConfigInputSchema,
  parseResolvedFinanceConfig,
  parseFinanceConfigImpactPreview,
  parseFinanceRoundingModeInfo,
  parseConfigVersion,
  type ResolveFinanceConfigInput,
  type ResolvedFinanceConfig,
  type FinanceConfigImpactPreview,
  type FinanceRoundingModeInfo,
  type FinanceConfigClass,
  type ConfigVersion,
} from "../contracts/finance-config/finance-config.ts";

export type FinanceConfigQueryRpcClient = Pick<SupabaseClient, "rpc">;
export type FinanceRoundingModesTableClient = Pick<SupabaseClient, "from">;

export class FinanceConfigQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FinanceConfigQueryError";
  }
}

function cacheKey(input: ResolveFinanceConfigInput): string {
  return [input.configTypeCode, input.tenantId ?? "", input.companyId ?? "", input.branchId ?? "", input.roleId ?? "", input.userId ?? ""].join("::");
}

interface CacheEntry {
  readonly resolved: ResolvedFinanceConfig | null;
  readonly expiresAt: number;
}

/** Draft config is never cached (app.resolve_finance_config, like app.resolve_config, only ever returns published data). `invalidate()` drops every cached entry -- a publish/rollback anywhere should call it. */
export class FinanceConfigResolutionCache {
  private readonly byKey = new Map<string, CacheEntry>();
  private readonly ttlMs: number;

  constructor(ttlMs: number) {
    this.ttlMs = ttlMs;
  }

  get(input: ResolveFinanceConfigInput, now: number): { hit: true; resolved: ResolvedFinanceConfig | null } | { hit: false } {
    const entry = this.byKey.get(cacheKey(input));
    if (!entry || entry.expiresAt <= now) return { hit: false };
    return { hit: true, resolved: entry.resolved };
  }

  set(input: ResolveFinanceConfigInput, resolved: ResolvedFinanceConfig | null, now: number): void {
    this.byKey.set(cacheKey(input), { resolved, expiresAt: now + this.ttlMs });
  }

  invalidate(): void {
    this.byKey.clear();
  }
}

/** Resolves the effective Finance Configuration for a config_type via the real 6-level precedence walk (user -> role -> branch -> company -> tenant -> global), scoped to the six Finance Configuration classes only. Returns null if no level currently has an effective published version. */
export async function resolveFinanceConfig(
  client: FinanceConfigQueryRpcClient,
  input: ResolveFinanceConfigInput,
  cache?: FinanceConfigResolutionCache,
  now: number = Date.now(),
): Promise<ResolvedFinanceConfig | null> {
  const parsedInput = ResolveFinanceConfigInputSchema.parse(input);

  if (cache) {
    const cached = cache.get(parsedInput, now);
    if (cached.hit) return cached.resolved;
  }

  const { data, error } = await client.rpc("resolve_finance_config", {
    p_config_type_code: parsedInput.configTypeCode,
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_branch_id: parsedInput.branchId,
    p_role_id: parsedInput.roleId,
    p_user_id: parsedInput.userId,
  });

  if (error) {
    throw new FinanceConfigQueryError(error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  const resolved = row && typeof row === "object" ? parseResolvedFinanceConfig(row as Record<string, unknown>) : null;
  cache?.set(parsedInput, resolved, now);
  return resolved;
}

/** Preview-impact: structural validation result plus, for finance_posting_map, the account-code references not yet resolvable against a Chart of Accounts (FIN-192). */
export async function previewFinanceConfigImpact(client: FinanceConfigQueryRpcClient, versionId: string): Promise<FinanceConfigImpactPreview> {
  const { data, error } = await client.rpc("preview_finance_config_impact", { p_version_id: versionId });
  if (error) {
    throw new FinanceConfigQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FinanceConfigQueryError("preview_finance_config_impact returned no result");
  }
  return parseFinanceConfigImpactPreview(data as Record<string, unknown>);
}

/** Admin view-model read path: every draft/published/archived version for one Finance config_object, newest first. */
export async function listFinanceConfigVersions(
  client: FinanceConfigQueryRpcClient,
  input: { configTypeCode: FinanceConfigClass; tenantId: string | null; scopeLevel: string; scopeId: string | null; actorAuthUserId: string },
): Promise<ConfigVersion[]> {
  const { data, error } = await client.rpc("list_config_versions", {
    p_config_type_code: input.configTypeCode,
    p_tenant_id: input.tenantId,
    p_scope_level: input.scopeLevel,
    p_scope_id: input.scopeId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new FinanceConfigQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseConfigVersion(row as Record<string, unknown>));
}

/** The one read path for a not-yet-published draft's own current item set (FIN:Edit-gated -- draft content is deliberately not exposed by the generic engine's own resolve_config). */
export async function getFinanceConfigVersionItems(client: FinanceConfigQueryRpcClient, versionId: string, actorAuthUserId: string): Promise<Record<string, unknown>> {
  const { data, error } = await client.rpc("get_finance_config_version_items", { p_version_id: versionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new FinanceConfigQueryError(error.message);
  }
  return (data ?? {}) as Record<string, unknown>;
}

/** The bounded reference catalogue of rounding conventions (never a tax/legal rate) -- reused directly by FIN-194's own exchange-rate conversion rounding. */
export async function listFinanceRoundingModes(client: FinanceRoundingModesTableClient): Promise<FinanceRoundingModeInfo[]> {
  const { data, error } = await client.from("finance_rounding_modes").select("code, name, description");
  if (error) {
    throw new FinanceConfigQueryError(error.message);
  }
  return (data ?? []).map((row) => parseFinanceRoundingModeInfo(row as Record<string, unknown>));
}
