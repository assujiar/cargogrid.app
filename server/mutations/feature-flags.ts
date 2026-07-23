/**
 * Feature flag mutation primitives (PLT-133, CG-S6-PLT-030). Thin, typed wrappers
 * around app.register_feature_flag / app.create_feature_flag_draft /
 * app.set_feature_flag_items / app.kill_feature_flag / app.debug_feature_flag
 * (supabase/migrations/20260721090000_create_feature_flags_platform.sql). All
 * service_role-only (see the migration's own grant comment).
 *
 * Publish/discard/rollback of a flag's draft versions are **not** re-declared here --
 * once a draft version_id exists, PLT-121's own publishConfigVersion/discardConfigDraft/
 * rollbackConfigVersion (server/mutations/config.ts) operate on it directly, with no
 * flag-specific parameter at all (the same "shared mechanism, not a fork" discipline
 * the migration's own header established). Every mutation below invalidates the
 * FeatureFlagCache it is given (Prompt 133 §17: "prompt invalidation").
 */

import {
  RegisterFeatureFlagInputSchema,
  CreateFeatureFlagDraftInputSchema,
  SetFeatureFlagItemsInputSchema,
  KillFeatureFlagInputSchema,
  DebugFeatureFlagInputSchema,
  parseFeatureFlag,
  parseFeatureFlagDecision,
  type RegisterFeatureFlagInput,
  type CreateFeatureFlagDraftInput,
  type SetFeatureFlagItemsInput,
  type KillFeatureFlagInput,
  type DebugFeatureFlagInput,
  type FeatureFlag,
  type FeatureFlagDecision,
} from "../contracts/feature-flag/feature-flag.ts";
import type { ConfigVersion } from "../contracts/config/config.ts";
import { parseConfigVersion } from "../contracts/config/config.ts";
import type { FeatureFlagCache } from "../queries/feature-flags.ts";

export interface FeatureFlagMutationRpcClient {
  rpc(
    fn: "register_feature_flag" | "create_feature_flag_draft" | "set_feature_flag_items" | "kill_feature_flag" | "debug_feature_flag",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const FEATURE_FLAG_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "feature_flag_not_found",
  "feature_flag_unknown_module",
  "feature_flag_invalid_scope",
  "feature_flag_global_scope_no_tenant",
  "feature_flag_tenant_scope_requires_tenant",
  "feature_flag_not_a_flag_version",
  "feature_flag_invalid_rollout_percentage",
  "feature_flag_global_scope_no_tenant_state",
  "feature_flag_invalid_environment",
  "feature_flag_tenant_scope_no_kill_switch",
  "feature_flag_invalid_tenant_state",
  "config_version_not_found",
  "config_version_not_draft",
] as const;
type KnownFeatureFlagMutationErrorCode = (typeof FEATURE_FLAG_KNOWN_MUTATION_ERROR_CODES)[number];
export type FeatureFlagMutationErrorCode = KnownFeatureFlagMutationErrorCode | "mutation_failed" | "invalid_response";

export class FeatureFlagMutationError extends Error {
  readonly code: FeatureFlagMutationErrorCode;

  constructor(code: FeatureFlagMutationErrorCode, message: string) {
    super(message);
    this.name = "FeatureFlagMutationError";
    this.code = code;
  }
}

function classifyError(message: string): FeatureFlagMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (FEATURE_FLAG_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownFeatureFlagMutationErrorCode)
    : "mutation_failed";
}

/** Idempotent -- Supreme-Admin-only. */
export async function registerFeatureFlag(client: FeatureFlagMutationRpcClient, input: RegisterFeatureFlagInput): Promise<FeatureFlag> {
  const parsedInput = RegisterFeatureFlagInputSchema.parse(input);
  const { data, error } = await client.rpc("register_feature_flag", {
    p_flag_key: parsedInput.flagKey,
    p_name: parsedInput.name,
    p_description: parsedInput.description,
    p_module_code: parsedInput.moduleCode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_registered_by: parsedInput.registeredBy,
  });
  if (error) {
    throw new FeatureFlagMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FeatureFlagMutationError("invalid_response", "register_feature_flag returned no row");
  }
  return parseFeatureFlag(data as Record<string, unknown>);
}

/** Validating wrapper around app.create_config_draft -- rejects an unknown flag_key or a scope outside {global, tenant} before delegating. */
export async function createFeatureFlagDraft(client: FeatureFlagMutationRpcClient, input: CreateFeatureFlagDraftInput): Promise<ConfigVersion> {
  const parsedInput = CreateFeatureFlagDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_feature_flag_draft", {
    p_flag_key: parsedInput.flagKey,
    p_tenant_id: parsedInput.tenantId,
    p_scope_level: parsedInput.scopeLevel,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
  if (error) {
    throw new FeatureFlagMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FeatureFlagMutationError("invalid_response", "create_feature_flag_draft returned no row");
  }
  return parseConfigVersion(data as Record<string, unknown>);
}

/** Bulk-sets a draft's target dimensions with flag-specific structural validation (kill_switch/environments are global-only, non-overridable). Returns the resulting item count. */
export async function setFeatureFlagItems(
  client: FeatureFlagMutationRpcClient,
  input: SetFeatureFlagItemsInput,
  cache?: FeatureFlagCache,
): Promise<number> {
  const parsedInput = SetFeatureFlagItemsInputSchema.parse(input);
  const { data, error } = await client.rpc("set_feature_flag_items", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_kill_switch: parsedInput.killSwitch,
    p_environments: parsedInput.environments,
    p_rollout_percentage: parsedInput.rolloutPercentage,
    p_cohorts: parsedInput.cohorts,
    p_tenant_state: parsedInput.tenantState,
  });
  if (error) {
    throw new FeatureFlagMutationError(classifyError(error.message), error.message);
  }
  if (typeof data !== "number") {
    throw new FeatureFlagMutationError("invalid_response", "set_feature_flag_items returned a non-numeric result");
  }
  cache?.invalidate();
  return data;
}

/** The panic-button convenience path -- Supreme-Admin-only. Forces kill_switch=true on a fresh global draft while preserving the other currently-published dimensions, then publishes immediately. */
export async function killFeatureFlag(
  client: FeatureFlagMutationRpcClient,
  input: KillFeatureFlagInput,
  cache?: FeatureFlagCache,
): Promise<ConfigVersion> {
  const parsedInput = KillFeatureFlagInputSchema.parse(input);
  const { data, error } = await client.rpc("kill_feature_flag", {
    p_flag_key: parsedInput.flagKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FeatureFlagMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FeatureFlagMutationError("invalid_response", "kill_feature_flag returned no row");
  }
  cache?.invalidate();
  return parseConfigVersion(data as Record<string, unknown>);
}

/** Privileged debug/explain path -- authority mirrors app.check_config_object_authority's own split. Never cached (an operator debugging must always see a live evaluation, not a stale one). */
export async function debugFeatureFlag(client: FeatureFlagMutationRpcClient, input: DebugFeatureFlagInput): Promise<FeatureFlagDecision> {
  const parsedInput = DebugFeatureFlagInputSchema.parse(input);
  const { data, error } = await client.rpc("debug_feature_flag", {
    p_flag_key: parsedInput.flagKey,
    p_tenant_id: parsedInput.tenantId,
    p_environment: parsedInput.environment,
    p_cohorts: parsedInput.cohorts,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FeatureFlagMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FeatureFlagMutationError("invalid_response", "debug_feature_flag returned no decision");
  }
  return parseFeatureFlagDecision(data as Record<string, unknown>);
}
