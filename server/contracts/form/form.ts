/**
 * Form and custom-field builder contract (PLT-126, CG-S6-PLT-023). Mirrors
 * supabase/migrations/20260719120000_create_form_custom_field_builder.sql's
 * app.form_registry/app.custom_field_values shape and the app.register_form /
 * app.publish_form_definition / app.set_custom_field_values /
 * app.get_custom_field_values RPCs.
 *
 * A form *definition* is not modeled here as its own row type -- it is PLT-121's own
 * ConfigVersion/config_items (config_type_code='form:<code>'), reused directly (this
 * migration's own header). `publishFormDefinition` therefore still returns a
 * `ConfigVersion` (server/contracts/config/config.ts), not a bespoke type.
 */

import { z } from "zod";
import { ConfigVersionSchema, type ConfigVersion } from "../config/config.ts";

export const CUSTOM_FIELD_TYPES = ["text", "textarea", "number", "boolean", "date", "select", "multiselect", "email"] as const;
export const CustomFieldTypeSchema = z.enum(CUSTOM_FIELD_TYPES);
export type CustomFieldType = z.infer<typeof CustomFieldTypeSchema>;

export const CUSTOM_FIELD_VALIDATOR_TYPES = ["min_length", "max_length", "min", "max", "pattern"] as const;
export const CustomFieldValidatorTypeSchema = z.enum(CUSTOM_FIELD_VALIDATOR_TYPES);
export type CustomFieldValidatorType = z.infer<typeof CustomFieldValidatorTypeSchema>;

export const CONDITION_OPERATORS = ["equals", "not_equals"] as const;
export const ConditionOperatorSchema = z.enum(CONDITION_OPERATORS);
export type ConditionOperator = z.infer<typeof ConditionOperatorSchema>;

export const CustomFieldValidatorSchema = z.object({
  type: CustomFieldValidatorTypeSchema,
  value: z.union([z.string(), z.number()]),
});
export type CustomFieldValidator = z.infer<typeof CustomFieldValidatorSchema>;

export const FieldConditionSchema = z.object({
  fieldCode: z.string().min(1),
  operator: ConditionOperatorSchema,
  value: z.unknown(),
});
export type FieldCondition = z.infer<typeof FieldConditionSchema>;

export const CustomFieldDefinitionSchema = z.object({
  code: z.string().min(1),
  label: z.string().min(1),
  type: CustomFieldTypeSchema,
  required: z.boolean().default(false),
  sensitive: z.boolean().default(false),
  options: z.array(z.string()).nullable().default(null),
  validators: z.array(CustomFieldValidatorSchema).default([]),
  condition: FieldConditionSchema.nullable().default(null),
});
export type CustomFieldDefinition = z.input<typeof CustomFieldDefinitionSchema>;

export const FormRegistrySchema = z.object({
  code: z.string(),
  name: z.string(),
  ownerPrimitiveCode: z.string(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type FormRegistryEntry = z.infer<typeof FormRegistrySchema>;

export const CustomFieldValuesSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  configVersionId: z.string().uuid(),
  entityType: z.string(),
  entityId: z.string().uuid(),
  values: z.record(z.string(), z.unknown()),
  submittedByAuthUserId: z.string().uuid().nullable(),
  submittedBy: z.string().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CustomFieldValues = z.infer<typeof CustomFieldValuesSchema>;

export const RegisterFormInputSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  ownerPrimitiveCode: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  registeredBy: z.string().min(1),
});
export type RegisterFormInput = z.input<typeof RegisterFormInputSchema>;

export const PublishFormDefinitionInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  effectiveFrom: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type PublishFormDefinitionInput = z.input<typeof PublishFormDefinitionInputSchema>;

export const SetCustomFieldValuesInputSchema = z.object({
  configVersionId: z.string().uuid(),
  tenantId: z.string().uuid(),
  entityType: z.string().min(1).default("generic"),
  entityId: z.string().uuid(),
  values: z.record(z.string(), z.unknown()),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  submittedBy: z.string().min(1),
});
export type SetCustomFieldValuesInput = z.input<typeof SetCustomFieldValuesInputSchema>;

export const GetCustomFieldValuesInputSchema = z.object({
  tenantId: z.string().uuid(),
  entityType: z.string().min(1).default("generic"),
  entityId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetCustomFieldValuesInput = z.input<typeof GetCustomFieldValuesInputSchema>;

/** Re-exported so callers of publishFormDefinition don't need a separate import from ../config/config.ts. */
export { ConfigVersionSchema };
export type { ConfigVersion };

/** Maps a raw app.form_registry row (snake_case) to this contract's camelCase shape. */
export function parseFormRegistryEntry(row: Record<string, unknown>): FormRegistryEntry {
  return FormRegistrySchema.parse({
    code: row.code,
    name: row.name,
    ownerPrimitiveCode: row.owner_primitive_code,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.custom_field_values row (snake_case) to this contract's camelCase shape. */
export function parseCustomFieldValues(row: Record<string, unknown>): CustomFieldValues {
  return CustomFieldValuesSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    configVersionId: row.config_version_id,
    entityType: row.entity_type,
    entityId: row.entity_id,
    values: row.values,
    submittedByAuthUserId: row.submitted_by_auth_user_id,
    submittedBy: row.submitted_by,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
