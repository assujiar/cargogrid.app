/**
 * White-label brand-version mutation primitives (PLT-117, CG-S6-PLT-014). Thin, typed
 * wrappers around app.create_tenant_brand_draft / app.set_tenant_brand_tokens /
 * app.publish_tenant_brand_version / app.discard_tenant_brand_draft /
 * app.rollback_tenant_brand_version
 * (supabase/migrations/20260717090512_create_white_label.sql). All five RPCs are
 * service_role-only (see the migration's own grant comment) -- callers of this module
 * must already have authenticated and authorized the acting session themselves.
 */

import {
  CreateTenantBrandDraftInputSchema,
  SetTenantBrandTokensInputSchema,
  PublishTenantBrandVersionInputSchema,
  DiscardTenantBrandDraftInputSchema,
  RollbackTenantBrandVersionInputSchema,
  parseTenantBrandVersion,
  type CreateTenantBrandDraftInput,
  type SetTenantBrandTokensInput,
  type PublishTenantBrandVersionInput,
  type DiscardTenantBrandDraftInput,
  type RollbackTenantBrandVersionInput,
  type TenantBrandVersion,
} from "../contracts/white-label/white-label.ts";

type WhiteLabelMutationRpcFn =
  | "create_tenant_brand_draft"
  | "set_tenant_brand_tokens"
  | "publish_tenant_brand_version"
  | "discard_tenant_brand_draft"
  | "rollback_tenant_brand_version";

export interface WhiteLabelMutationRpcClient {
  rpc(
    fn: WhiteLabelMutationRpcFn,
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const WHITE_LABEL_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "brand_version_not_found",
  "brand_version_not_draft",
  "insufficient_contrast",
  "cannot_rollback_draft",
] as const;
type KnownWhiteLabelMutationErrorCode = (typeof WHITE_LABEL_KNOWN_MUTATION_ERROR_CODES)[number];
export type WhiteLabelMutationErrorCode = KnownWhiteLabelMutationErrorCode | "mutation_failed" | "invalid_response";

export class WhiteLabelMutationError extends Error {
  readonly code: WhiteLabelMutationErrorCode;

  constructor(code: WhiteLabelMutationErrorCode, message: string) {
    super(message);
    this.name = "WhiteLabelMutationError";
    this.code = code;
  }
}

function classifyError(message: string): WhiteLabelMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (WHITE_LABEL_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownWhiteLabelMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseRow(
  client: WhiteLabelMutationRpcClient,
  fn: WhiteLabelMutationRpcFn,
  args: Record<string, unknown>,
): Promise<TenantBrandVersion> {
  const { data, error } = await client.rpc(fn, args);

  if (error) {
    throw new WhiteLabelMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new WhiteLabelMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseTenantBrandVersion(data as Record<string, unknown>);
}

/** Idempotent draft creation -- a repeated call while a draft already exists returns that draft rather than raising, matching PLT-111's app.create_role_version precedent. */
export async function createTenantBrandDraft(
  client: WhiteLabelMutationRpcClient,
  input: CreateTenantBrandDraftInput,
): Promise<TenantBrandVersion> {
  const parsedInput = CreateTenantBrandDraftInputSchema.parse(input);
  return callAndParseRow(client, "create_tenant_brand_draft", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** Replaces a draft's full token/asset/template set. Contrast is computed as preview evidence only here -- the enforced gate is at publish/rollback time. */
export async function setTenantBrandTokens(
  client: WhiteLabelMutationRpcClient,
  input: SetTenantBrandTokensInput,
): Promise<TenantBrandVersion> {
  const parsedInput = SetTenantBrandTokensInputSchema.parse(input);
  return callAndParseRow(client, "set_tenant_brand_tokens", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_tokens: parsedInput.tokens,
    p_logo_asset_url: parsedInput.logoAssetUrl,
    p_email_sender_name: parsedInput.emailSenderName,
    p_email_logo_asset_url: parsedInput.emailLogoAssetUrl,
    p_document_template_refs: parsedInput.documentTemplateRefs,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Publishes a draft (archiving the tenant's previously published version). Rejects a primary color below the 4.5:1 WCAG AA contrast minimum. */
export async function publishTenantBrandVersion(
  client: WhiteLabelMutationRpcClient,
  input: PublishTenantBrandVersionInput,
): Promise<TenantBrandVersion> {
  const parsedInput = PublishTenantBrandVersionInputSchema.parse(input);
  return callAndParseRow(client, "publish_tenant_brand_version", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_effective_from: parsedInput.effectiveFrom,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Discards a draft (draft -> archived) without ever publishing it. */
export async function discardTenantBrandDraft(
  client: WhiteLabelMutationRpcClient,
  input: DiscardTenantBrandDraftInput,
): Promise<TenantBrandVersion> {
  const parsedInput = DiscardTenantBrandDraftInputSchema.parse(input);
  return callAndParseRow(client, "discard_tenant_brand_draft", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Clones a published/archived version's snapshot into a brand-new version and publishes it immediately -- never mutates historical rows. */
export async function rollbackTenantBrandVersion(
  client: WhiteLabelMutationRpcClient,
  input: RollbackTenantBrandVersionInput,
): Promise<TenantBrandVersion> {
  const parsedInput = RollbackTenantBrandVersionInputSchema.parse(input);
  return callAndParseRow(client, "rollback_tenant_brand_version", {
    p_target_version_id: parsedInput.targetVersionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_label: parsedInput.actorLabel,
  });
}
