/**
 * Tenant locale/terminology mutation primitives (PLT-119, CG-S6-PLT-016). Thin, typed
 * wrappers around app.create_tenant_locale_draft / app.set_tenant_locale_config /
 * app.publish_tenant_locale_version / app.discard_tenant_locale_draft /
 * app.rollback_tenant_locale_version
 * (supabase/migrations/20260717112000_create_localization.sql). All five RPCs are
 * service_role-only (see the migration's own grant comment).
 */

import {
  CreateTenantLocaleDraftInputSchema,
  SetTenantLocaleConfigInputSchema,
  PublishTenantLocaleVersionInputSchema,
  DiscardTenantLocaleDraftInputSchema,
  RollbackTenantLocaleVersionInputSchema,
  parseTenantLocaleVersion,
  type CreateTenantLocaleDraftInput,
  type SetTenantLocaleConfigInput,
  type PublishTenantLocaleVersionInput,
  type DiscardTenantLocaleDraftInput,
  type RollbackTenantLocaleVersionInput,
  type TenantLocaleVersion,
} from "../contracts/localization/localization.ts";

type LocalizationMutationRpcFn =
  | "create_tenant_locale_draft"
  | "set_tenant_locale_config"
  | "publish_tenant_locale_version"
  | "discard_tenant_locale_draft"
  | "rollback_tenant_locale_version";

export interface LocalizationMutationRpcClient {
  rpc(
    fn: LocalizationMutationRpcFn,
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const LOCALIZATION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "locale_version_not_found",
  "locale_version_not_draft",
  "cannot_rollback_draft",
  "invalid_terminology_overrides",
] as const;
type KnownLocalizationMutationErrorCode = (typeof LOCALIZATION_KNOWN_MUTATION_ERROR_CODES)[number];
export type LocalizationMutationErrorCode = KnownLocalizationMutationErrorCode | "mutation_failed" | "invalid_response";

export class LocalizationMutationError extends Error {
  readonly code: LocalizationMutationErrorCode;

  constructor(code: LocalizationMutationErrorCode, message: string) {
    super(message);
    this.name = "LocalizationMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LocalizationMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (LOCALIZATION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownLocalizationMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseRow(
  client: LocalizationMutationRpcClient,
  fn: LocalizationMutationRpcFn,
  args: Record<string, unknown>,
): Promise<TenantLocaleVersion> {
  const { data, error } = await client.rpc(fn, args);

  if (error) {
    throw new LocalizationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new LocalizationMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseTenantLocaleVersion(data as Record<string, unknown>);
}

/** Idempotent draft creation -- a repeated call while a draft already exists returns that draft. */
export async function createTenantLocaleDraft(
  client: LocalizationMutationRpcClient,
  input: CreateTenantLocaleDraftInput,
): Promise<TenantLocaleVersion> {
  const parsedInput = CreateTenantLocaleDraftInputSchema.parse(input);
  return callAndParseRow(client, "create_tenant_locale_draft", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** Replaces a draft's full locale/timezone/currency/terminology-overrides set. */
export async function setTenantLocaleConfig(
  client: LocalizationMutationRpcClient,
  input: SetTenantLocaleConfigInput,
): Promise<TenantLocaleVersion> {
  const parsedInput = SetTenantLocaleConfigInputSchema.parse(input);
  return callAndParseRow(client, "set_tenant_locale_config", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_default_locale: parsedInput.defaultLocale,
    p_default_timezone: parsedInput.defaultTimezone,
    p_default_currency: parsedInput.defaultCurrency,
    p_terminology_overrides: parsedInput.terminologyOverrides,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Publishes a draft, archiving the tenant's previously published version. */
export async function publishTenantLocaleVersion(
  client: LocalizationMutationRpcClient,
  input: PublishTenantLocaleVersionInput,
): Promise<TenantLocaleVersion> {
  const parsedInput = PublishTenantLocaleVersionInputSchema.parse(input);
  return callAndParseRow(client, "publish_tenant_locale_version", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_effective_from: parsedInput.effectiveFrom,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Discards a draft (draft -> archived) without ever publishing it. */
export async function discardTenantLocaleDraft(
  client: LocalizationMutationRpcClient,
  input: DiscardTenantLocaleDraftInput,
): Promise<TenantLocaleVersion> {
  const parsedInput = DiscardTenantLocaleDraftInputSchema.parse(input);
  return callAndParseRow(client, "discard_tenant_locale_draft", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Clones a published/archived version's snapshot into a brand-new version and publishes it immediately. */
export async function rollbackTenantLocaleVersion(
  client: LocalizationMutationRpcClient,
  input: RollbackTenantLocaleVersionInput,
): Promise<TenantLocaleVersion> {
  const parsedInput = RollbackTenantLocaleVersionInputSchema.parse(input);
  return callAndParseRow(client, "rollback_tenant_locale_version", {
    p_target_version_id: parsedInput.targetVersionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_label: parsedInput.actorLabel,
  });
}
