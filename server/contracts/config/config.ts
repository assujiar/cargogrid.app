/**
 * Configuration engine contract (PLT-121, CG-S6-PLT-018). Mirrors
 * supabase/migrations/20260717130000_create_configuration_engine.sql's
 * app.config_types/app.config_objects/app.config_versions/app.config_items shape and
 * the app.register_config_type / app.create_config_draft / app.set_config_items /
 * app.publish_config_version / app.discard_config_draft / app.rollback_config_version /
 * app.resolve_config / app.verify_config_version_current / app.list_config_versions RPCs.
 *
 * `server/contracts/config/` is created in this same Phase-1 slice per
 * docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md §12's resolution of
 * `ADR-CAND-ARCH-010` ("the contracts folder cannot wait past Phase 1").
 */

import { z } from "zod";

export const CONFIG_SCOPE_LEVELS = ["global", "tenant", "company", "branch", "role", "user"] as const;
export const ConfigScopeLevelSchema = z.enum(CONFIG_SCOPE_LEVELS);
export type ConfigScopeLevel = z.infer<typeof ConfigScopeLevelSchema>;

export const CONFIG_VERSION_STATUSES = ["draft", "published", "archived"] as const;
export const ConfigVersionStatusSchema = z.enum(CONFIG_VERSION_STATUSES);
export type ConfigVersionStatus = z.infer<typeof ConfigVersionStatusSchema>;

export const ConfigTypeSchema = z.object({
  code: z.string(),
  name: z.string(),
  ownerPrimitiveCode: z.string(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type ConfigType = z.infer<typeof ConfigTypeSchema>;

/** Structural/injection safety only -- see the migration's own header for why the bounded rule *evaluator* is deliberately deferred. */
export type ConfigValue = string | number | boolean | null | { [key: string]: ConfigValue } | ConfigValue[];
export const ConfigValueSchema: z.ZodType<ConfigValue> = z.lazy(() =>
  z.union([
    z.string().regex(/^[^<>]*$/, "must not contain < or >"),
    z.number(),
    z.boolean(),
    z.null(),
    z.record(z.string(), ConfigValueSchema),
    z.array(ConfigValueSchema),
  ]),
);

export const ConfigVersionSchema = z.object({
  id: z.string().uuid(),
  configObjectId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: ConfigVersionStatusSchema,
  effectiveFrom: z.string().nullable(),
  effectiveTo: z.string().nullable(),
  clonedFromVersionId: z.string().uuid().nullable(),
  rollbackOfVersionId: z.string().uuid().nullable(),
  createdBy: z.string().nullable(),
  publishedBy: z.string().nullable(),
  publishedAt: z.string().nullable(),
  archivedAt: z.string().nullable(),
  archivedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ConfigVersion = z.infer<typeof ConfigVersionSchema>;

export const ConfigItemInputSchema = z.object({
  key: z.string().min(1),
  value: ConfigValueSchema,
  canonicalRef: z.string().nullable().default(null),
});
export type ConfigItemInput = z.input<typeof ConfigItemInputSchema>;

export const RegisterConfigTypeInputSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  ownerPrimitiveCode: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  registeredBy: z.string().min(1),
});
export type RegisterConfigTypeInput = z.infer<typeof RegisterConfigTypeInputSchema>;

const ScopeFieldsSchema = z.object({
  configTypeCode: z.string().min(1),
  tenantId: z.string().uuid().nullable(),
  scopeLevel: ConfigScopeLevelSchema,
  scopeId: z.string().uuid().nullable(),
});

export const CreateConfigDraftInputSchema = ScopeFieldsSchema.extend({
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateConfigDraftInput = z.infer<typeof CreateConfigDraftInputSchema>;

export const SetConfigItemsInputSchema = z.object({
  versionId: z.string().uuid(),
  items: z.array(ConfigItemInputSchema).default([]),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetConfigItemsInput = z.input<typeof SetConfigItemsInputSchema>;

export const PublishConfigVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  effectiveFrom: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type PublishConfigVersionInput = z.input<typeof PublishConfigVersionInputSchema>;

export const DiscardConfigDraftInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type DiscardConfigDraftInput = z.input<typeof DiscardConfigDraftInputSchema>;

export const RollbackConfigVersionInputSchema = z.object({
  targetVersionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type RollbackConfigVersionInput = z.input<typeof RollbackConfigVersionInputSchema>;

const PrecedenceScopeSchema = z.object({
  configTypeCode: z.string().min(1),
  tenantId: z.string().uuid().nullable(),
  companyId: z.string().uuid().nullable().default(null),
  branchId: z.string().uuid().nullable().default(null),
  roleId: z.string().uuid().nullable().default(null),
  userId: z.string().uuid().nullable().default(null),
});

export const ResolveConfigInputSchema = PrecedenceScopeSchema;
export type ResolveConfigInput = z.input<typeof ResolveConfigInputSchema>;

export const VerifyConfigVersionCurrentInputSchema = PrecedenceScopeSchema.extend({
  expectedVersionId: z.string().uuid().nullable(),
});
export type VerifyConfigVersionCurrentInput = z.input<typeof VerifyConfigVersionCurrentInputSchema>;

export const ListConfigVersionsInputSchema = ScopeFieldsSchema.extend({
  actorAuthUserId: z.string().uuid(),
});
export type ListConfigVersionsInput = z.infer<typeof ListConfigVersionsInputSchema>;

export const ResolvedConfigSchema = z.object({
  configTypeCode: z.string(),
  resolvedScopeLevel: ConfigScopeLevelSchema,
  resolvedVersionId: z.string().uuid(),
  effectiveFrom: z.string(),
  items: z.record(z.string(), z.unknown()),
});
export type ResolvedConfig = z.infer<typeof ResolvedConfigSchema>;

/** Maps a raw app.config_types row (snake_case) to this contract's camelCase shape. */
export function parseConfigType(row: Record<string, unknown>): ConfigType {
  return ConfigTypeSchema.parse({
    code: row.code,
    name: row.name,
    ownerPrimitiveCode: row.owner_primitive_code,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.config_versions row (snake_case) to this contract's camelCase shape. */
export function parseConfigVersion(row: Record<string, unknown>): ConfigVersion {
  return ConfigVersionSchema.parse({
    id: row.id,
    configObjectId: row.config_object_id,
    versionNumber: row.version_number,
    status: row.status,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    clonedFromVersionId: row.cloned_from_version_id,
    rollbackOfVersionId: row.rollback_of_version_id,
    createdBy: row.created_by,
    publishedBy: row.published_by,
    publishedAt: row.published_at,
    archivedAt: row.archived_at,
    archivedReason: row.archived_reason,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.resolve_config() row (snake_case) to this contract's camelCase shape. */
export function parseResolvedConfig(row: Record<string, unknown>): ResolvedConfig {
  return ResolvedConfigSchema.parse({
    configTypeCode: row.config_type_code,
    resolvedScopeLevel: row.resolved_scope_level,
    resolvedVersionId: row.resolved_version_id,
    effectiveFrom: row.effective_from,
    items: row.items,
  });
}
