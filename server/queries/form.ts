/**
 * Custom-field read/validation queries (PLT-126, CG-S6-PLT-023). Thin, typed wrappers
 * around app.get_custom_field_values / app.validate_custom_field_values
 * (supabase/migrations/20260719120000_create_form_custom_field_builder.sql).
 */

import {
  GetCustomFieldValuesInputSchema,
  parseCustomFieldValues,
  type GetCustomFieldValuesInput,
  type CustomFieldValues,
} from "../contracts/form/form.ts";

export interface FormQueryRpcClient {
  rpc(
    fn: "get_custom_field_values" | "validate_custom_field_values",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class FormQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FormQueryError";
  }
}

/** Sensitive-field-gated read: readable by any active tenant member unless the bound definition has a sensitive field, in which case only the original submitter or a definition-admin-grade authority may read it (raises insufficient_authority otherwise). */
export async function getCustomFieldValues(client: FormQueryRpcClient, input: GetCustomFieldValuesInput): Promise<CustomFieldValues> {
  const parsedInput = GetCustomFieldValuesInputSchema.parse(input);
  const { data, error } = await client.rpc("get_custom_field_values", {
    p_tenant_id: parsedInput.tenantId,
    p_entity_type: parsedInput.entityType,
    p_entity_id: parsedInput.entityId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new FormQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new FormQueryError("get_custom_field_values returned no row");
  }
  return parseCustomFieldValues(data as Record<string, unknown>);
}

/** Client-side pre-validation preview: runs the exact same server-side validation gate app.set_custom_field_values() itself enforces, without writing anything -- lets a form UI surface field errors before submit. Returns true, or throws with the same distinct error codes a real submit would raise. */
export async function validateCustomFieldValuesPreview(
  client: FormQueryRpcClient,
  configVersionId: string,
  values: Record<string, unknown>,
): Promise<boolean> {
  const { data, error } = await client.rpc("validate_custom_field_values", {
    p_config_version_id: configVersionId,
    p_values: values,
  });
  if (error) {
    throw new FormQueryError(error.message);
  }
  if (typeof data !== "boolean") {
    throw new FormQueryError("validate_custom_field_values returned a non-boolean result");
  }
  return data;
}
