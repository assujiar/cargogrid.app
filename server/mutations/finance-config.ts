/**
 * Finance Configuration mutation primitives (FIN-191, CG-S9-FIN-002). Thin,
 * typed wrappers around app.create_finance_config_draft /
 * app.set_finance_config_items / app.publish_finance_config_version /
 * app.discard_finance_config_draft / app.rollback_finance_config_version
 * (supabase/migrations/20260728200000_create_finance_configuration.sql).
 *
 * Authority note (disclosed, matching the migration's own header): drafting
 * requires FIN:Edit AND tenant_admin/Supreme (inherited from the reused
 * Configuration Engine's own app.check_config_object_authority); publishing/
 * rolling back requires FIN:Approve AND tenant_admin/Supreme the same way --
 * a deliberate two-factor gate, never a weakening of either layer.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateFinanceConfigDraftInputSchema,
  SetFinanceConfigItemsInputSchema,
  PublishFinanceConfigVersionInputSchema,
  DiscardFinanceConfigDraftInputSchema,
  RollbackFinanceConfigVersionInputSchema,
  parseConfigVersion,
  type CreateFinanceConfigDraftInput,
  type SetFinanceConfigItemsInput,
  type PublishFinanceConfigVersionInput,
  type DiscardFinanceConfigDraftInput,
  type RollbackFinanceConfigVersionInput,
  type ConfigVersion,
} from "../contracts/finance-config/finance-config.ts";

export type FinanceConfigMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const FINANCE_CONFIG_KNOWN_MUTATION_ERROR_CODES = [
  "not_finance_config_type",
  "insufficient_authority",
  "config_version_not_found",
  "config_version_not_draft",
  "cannot_rollback_draft",
  "circular_config_dependency",
  "finance_config_empty",
  "finance_dimension_invalid_code",
  "finance_dimension_missing_name",
  "finance_dimension_invalid_required",
  "finance_numbering_missing_format",
  "finance_numbering_invalid_seq_token_count",
  "finance_numbering_unknown_token",
  "finance_numbering_invalid_reset_period",
  "finance_numbering_invalid_padding",
  "finance_posting_map_invalid_account_ref",
  "finance_rounding_invalid_mode",
  "finance_rounding_invalid_precision",
  "finance_rounding_invalid_order",
  "finance_recognition_shape",
  "finance_recognition_invalid_budget_control_mode",
  "finance_recognition_invalid_accrual_method",
  "finance_recognition_invalid_revenue_method",
  "finance_recognition_invalid_cost_method",
  "finance_close_policy_missing_label",
  "finance_close_policy_invalid_required",
] as const;
type KnownFinanceConfigMutationErrorCode = (typeof FINANCE_CONFIG_KNOWN_MUTATION_ERROR_CODES)[number];
export type FinanceConfigMutationErrorCode = KnownFinanceConfigMutationErrorCode | "mutation_failed" | "invalid_response";

export class FinanceConfigMutationError extends Error {
  readonly code: FinanceConfigMutationErrorCode;

  constructor(code: FinanceConfigMutationErrorCode, message: string) {
    super(message);
    this.name = "FinanceConfigMutationError";
    this.code = code;
  }
}

function classifyError(message: string): FinanceConfigMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (FINANCE_CONFIG_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownFinanceConfigMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseVersion(
  client: FinanceConfigMutationRpcClient,
  fn: "create_finance_config_draft" | "publish_finance_config_version" | "discard_finance_config_draft" | "rollback_finance_config_version",
  args: Record<string, unknown>,
): Promise<ConfigVersion> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new FinanceConfigMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FinanceConfigMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseConfigVersion(data as Record<string, unknown>);
}

/** Idempotent (auto-vivifies the config_object if needed, or returns the existing draft) -- requires FIN:Edit and tenant_admin/Supreme authority for the object's scope. */
export async function createFinanceConfigDraft(client: FinanceConfigMutationRpcClient, input: CreateFinanceConfigDraftInput): Promise<ConfigVersion> {
  const parsedInput = CreateFinanceConfigDraftInputSchema.parse(input);
  return callAndParseVersion(client, "create_finance_config_draft", {
    p_config_type_code: parsedInput.configTypeCode,
    p_tenant_id: parsedInput.tenantId,
    p_scope_level: parsedInput.scopeLevel,
    p_scope_id: parsedInput.scopeId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** Bulk-replaces a draft's full item set. Returns the resulting item count. Requires FIN:Edit and tenant_admin/Supreme authority. */
export async function setFinanceConfigItems(client: FinanceConfigMutationRpcClient, input: SetFinanceConfigItemsInput): Promise<number> {
  const parsedInput = SetFinanceConfigItemsInputSchema.parse(input);
  const { data, error } = await client.rpc("set_finance_config_items", {
    p_version_id: parsedInput.versionId,
    p_items: parsedInput.items.map((item) => ({ key: item.key, value: item.value })),
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FinanceConfigMutationError(classifyError(error.message), error.message);
  }
  if (typeof data !== "number") {
    throw new FinanceConfigMutationError("invalid_response", "set_finance_config_items returned a non-numeric result");
  }
  return data;
}

/** Publishes a draft after per-class structural validation (bounded enums/format-token rules only, never a tax/legal rate) and the generic engine's own dependency-cycle gate; supersedes the object's previously published version. Requires FIN:Approve and tenant_admin/Supreme authority. */
export async function publishFinanceConfigVersion(client: FinanceConfigMutationRpcClient, input: PublishFinanceConfigVersionInput): Promise<ConfigVersion> {
  const parsedInput = PublishFinanceConfigVersionInputSchema.parse(input);
  return callAndParseVersion(client, "publish_finance_config_version", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_effective_from: parsedInput.effectiveFrom,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Discards a draft (draft -> archived) without ever publishing it. Requires FIN:Edit and tenant_admin/Supreme authority. */
export async function discardFinanceConfigDraft(client: FinanceConfigMutationRpcClient, input: DiscardFinanceConfigDraftInput): Promise<ConfigVersion> {
  const parsedInput = DiscardFinanceConfigDraftInputSchema.parse(input);
  return callAndParseVersion(client, "discard_finance_config_draft", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Clones a published/archived version's item set into a brand-new version and publishes it immediately -- never mutates the target. Requires FIN:Approve and tenant_admin/Supreme authority. */
export async function rollbackFinanceConfigVersion(client: FinanceConfigMutationRpcClient, input: RollbackFinanceConfigVersionInput): Promise<ConfigVersion> {
  const parsedInput = RollbackFinanceConfigVersionInputSchema.parse(input);
  return callAndParseVersion(client, "rollback_finance_config_version", {
    p_target_version_id: parsedInput.targetVersionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_label: parsedInput.actorLabel,
  });
}
