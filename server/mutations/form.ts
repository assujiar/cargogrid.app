/**
 * Form and custom-field builder mutation primitives (PLT-126, CG-S6-PLT-023). Thin,
 * typed wrappers around app.register_form / app.publish_form_definition /
 * app.set_custom_field_values
 * (supabase/migrations/20260719120000_create_form_custom_field_builder.sql). All
 * service_role-only (see the migration's own grant comment).
 */

import {
  RegisterFormInputSchema,
  PublishFormDefinitionInputSchema,
  SetCustomFieldValuesInputSchema,
  ConfigVersionSchema,
  parseFormRegistryEntry,
  parseCustomFieldValues,
  type RegisterFormInput,
  type PublishFormDefinitionInput,
  type SetCustomFieldValuesInput,
  type FormRegistryEntry,
  type CustomFieldValues,
  type ConfigVersion,
} from "../contracts/form/form.ts";
import { parseConfigVersion } from "../contracts/config/config.ts";

export interface FormMutationRpcClient {
  rpc(
    fn: "register_form" | "publish_form_definition" | "set_custom_field_values",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const FORM_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "custom_field_missing_fields",
  "custom_field_too_many_fields",
  "custom_field_invalid_code",
  "custom_field_duplicate_code",
  "custom_field_missing_label",
  "custom_field_invalid_type",
  "custom_field_missing_options",
  "custom_field_invalid_validator",
  "custom_field_unknown_condition_operator",
  "custom_field_invalid_condition_reference",
  "custom_field_definition_not_published",
  "custom_field_unknown_field",
  "custom_field_required_missing",
  "custom_field_invalid_value",
  "custom_field_validator_failed",
] as const;
type KnownFormMutationErrorCode = (typeof FORM_KNOWN_MUTATION_ERROR_CODES)[number];
export type FormMutationErrorCode = KnownFormMutationErrorCode | "mutation_failed" | "invalid_response";

export class FormMutationError extends Error {
  readonly code: FormMutationErrorCode;

  constructor(code: FormMutationErrorCode, message: string) {
    super(message);
    this.name = "FormMutationError";
    this.code = code;
  }
}

function classifyError(message: string): FormMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (FORM_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownFormMutationErrorCode)
    : "mutation_failed";
}

/** Idempotent -- Supreme-Admin-only. Also mints a dedicated form:<code> config_type (this migration's own header explains why one shared type cannot host every form's independent tenant presentation). */
export async function registerForm(client: FormMutationRpcClient, input: RegisterFormInput): Promise<FormRegistryEntry> {
  const parsedInput = RegisterFormInputSchema.parse(input);
  const { data, error } = await client.rpc("register_form", {
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_owner_primitive_code: parsedInput.ownerPrimitiveCode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_registered_by: parsedInput.registeredBy,
  });
  if (error) {
    throw new FormMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FormMutationError("invalid_response", "register_form returned no row");
  }
  return parseFormRegistryEntry(data as Record<string, unknown>);
}

/** Runs the structural validation gate (unique field codes, allowlisted types/validators, options required for select/multiselect, condition-cycle-free by construction), then supersedes the prior published definition. */
export async function publishFormDefinition(client: FormMutationRpcClient, input: PublishFormDefinitionInput): Promise<ConfigVersion> {
  const parsedInput = PublishFormDefinitionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_form_definition", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_effective_from: parsedInput.effectiveFrom,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new FormMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FormMutationError("invalid_response", "publish_form_definition returned no row");
  }
  return ConfigVersionSchema.parse(parseConfigVersion(data as Record<string, unknown>));
}

/** Idempotent on (tenantId, idempotencyKey). Upserts the current values row for one entity -- one row per (tenant, entityType, entityId), never one row per field. Runs the real submission-time validation gate before ever writing. */
export async function setCustomFieldValues(client: FormMutationRpcClient, input: SetCustomFieldValuesInput): Promise<CustomFieldValues> {
  const parsedInput = SetCustomFieldValuesInputSchema.parse(input);
  const { data, error } = await client.rpc("set_custom_field_values", {
    p_config_version_id: parsedInput.configVersionId,
    p_tenant_id: parsedInput.tenantId,
    p_entity_type: parsedInput.entityType,
    p_entity_id: parsedInput.entityId,
    p_values: parsedInput.values,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_submitted_by: parsedInput.submittedBy,
  });
  if (error) {
    throw new FormMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FormMutationError("invalid_response", "set_custom_field_values returned no row");
  }
  return parseCustomFieldValues(data as Record<string, unknown>);
}
