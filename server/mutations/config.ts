/**
 * Configuration engine mutation primitives (PLT-121, CG-S6-PLT-018). Thin, typed
 * wrappers around app.register_config_type / app.create_config_draft /
 * app.set_config_items / app.publish_config_version / app.discard_config_draft /
 * app.rollback_config_version
 * (supabase/migrations/20260717130000_create_configuration_engine.sql). All
 * service_role-only (see the migration's own grant comment).
 */

import {
  RegisterConfigTypeInputSchema,
  CreateConfigDraftInputSchema,
  SetConfigItemsInputSchema,
  PublishConfigVersionInputSchema,
  DiscardConfigDraftInputSchema,
  RollbackConfigVersionInputSchema,
  parseConfigType,
  parseConfigVersion,
  type RegisterConfigTypeInput,
  type CreateConfigDraftInput,
  type SetConfigItemsInput,
  type PublishConfigVersionInput,
  type DiscardConfigDraftInput,
  type RollbackConfigVersionInput,
  type ConfigType,
  type ConfigVersion,
} from "../contracts/config/config.ts";

export interface ConfigMutationRpcClient {
  rpc(
    fn:
      | "register_config_type"
      | "create_config_draft"
      | "set_config_items"
      | "publish_config_version"
      | "discard_config_draft"
      | "rollback_config_version",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const CONFIG_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "config_version_not_found",
  "config_version_not_draft",
  "cannot_rollback_draft",
  "circular_config_dependency",
] as const;
type KnownConfigMutationErrorCode = (typeof CONFIG_KNOWN_MUTATION_ERROR_CODES)[number];
export type ConfigMutationErrorCode = KnownConfigMutationErrorCode | "mutation_failed" | "invalid_response";

export class ConfigMutationError extends Error {
  readonly code: ConfigMutationErrorCode;

  constructor(code: ConfigMutationErrorCode, message: string) {
    super(message);
    this.name = "ConfigMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ConfigMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CONFIG_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownConfigMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseVersion(
  client: ConfigMutationRpcClient,
  fn: "create_config_draft" | "publish_config_version" | "discard_config_draft" | "rollback_config_version",
  args: Record<string, unknown>,
): Promise<ConfigVersion> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new ConfigMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ConfigMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseConfigVersion(data as Record<string, unknown>);
}

/** Idempotent -- Supreme-Admin-only. */
export async function registerConfigType(client: ConfigMutationRpcClient, input: RegisterConfigTypeInput): Promise<ConfigType> {
  const parsedInput = RegisterConfigTypeInputSchema.parse(input);
  const { data, error } = await client.rpc("register_config_type", {
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_owner_primitive_code: parsedInput.ownerPrimitiveCode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_registered_by: parsedInput.registeredBy,
  });
  if (error) {
    throw new ConfigMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ConfigMutationError("invalid_response", "register_config_type returned no row");
  }
  return parseConfigType(data as Record<string, unknown>);
}

/** Idempotent -- auto-creates the config_object if it does not exist yet, then a draft version if none is already pending. Authority: Supreme Admin for scopeLevel='global', Tenant Admin of tenantId (or Supreme) otherwise. */
export async function createConfigDraft(client: ConfigMutationRpcClient, input: CreateConfigDraftInput): Promise<ConfigVersion> {
  const parsedInput = CreateConfigDraftInputSchema.parse(input);
  return callAndParseVersion(client, "create_config_draft", {
    p_config_type_code: parsedInput.configTypeCode,
    p_tenant_id: parsedInput.tenantId,
    p_scope_level: parsedInput.scopeLevel,
    p_scope_id: parsedInput.scopeId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** Bulk-replaces a draft's full item set. Returns the resulting item count. */
export async function setConfigItems(client: ConfigMutationRpcClient, input: SetConfigItemsInput): Promise<number> {
  const parsedInput = SetConfigItemsInputSchema.parse(input);
  const { data, error } = await client.rpc("set_config_items", {
    p_version_id: parsedInput.versionId,
    p_items: parsedInput.items.map((item) => ({ key: item.key, value: item.value, canonical_ref: item.canonicalRef })),
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ConfigMutationError(classifyError(error.message), error.message);
  }
  if (typeof data !== "number") {
    throw new ConfigMutationError("invalid_response", "set_config_items returned a non-numeric result");
  }
  return data;
}

/** Publishes a draft after a dependency-cycle validation gate; supersedes the object's previously published version. */
export async function publishConfigVersion(client: ConfigMutationRpcClient, input: PublishConfigVersionInput): Promise<ConfigVersion> {
  const parsedInput = PublishConfigVersionInputSchema.parse(input);
  return callAndParseVersion(client, "publish_config_version", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_effective_from: parsedInput.effectiveFrom,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Discards a draft (draft -> archived) without ever publishing it. */
export async function discardConfigDraft(client: ConfigMutationRpcClient, input: DiscardConfigDraftInput): Promise<ConfigVersion> {
  const parsedInput = DiscardConfigDraftInputSchema.parse(input);
  return callAndParseVersion(client, "discard_config_draft", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Clones a published/archived version's item set into a brand-new version and publishes it immediately -- never mutates the target. */
export async function rollbackConfigVersion(client: ConfigMutationRpcClient, input: RollbackConfigVersionInput): Promise<ConfigVersion> {
  const parsedInput = RollbackConfigVersionInputSchema.parse(input);
  return callAndParseVersion(client, "rollback_config_version", {
    p_target_version_id: parsedInput.targetVersionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_label: parsedInput.actorLabel,
  });
}
