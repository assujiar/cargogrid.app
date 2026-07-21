/**
 * Master-data registry contract (PLT-120, CG-S6-PLT-017). Mirrors
 * supabase/migrations/20260717120000_create_master_data.sql's
 * app.master_types/app.master_records shape and the app.register_master_type /
 * app.create_master_record / app.update_master_record / app.deactivate_master_record /
 * app.merge_master_records / app.resolve_master_record / app.search_master_records RPCs.
 */

import { z } from "zod";

export const MASTER_TYPE_SCOPES = ["global", "tenant"] as const;
export const MasterTypeScopeSchema = z.enum(MASTER_TYPE_SCOPES);
export type MasterTypeScope = z.infer<typeof MasterTypeScopeSchema>;

export const MASTER_RECORD_STATUSES = ["active", "deactivated", "merged"] as const;
export const MasterRecordStatusSchema = z.enum(MASTER_RECORD_STATUSES);
export type MasterRecordStatus = z.infer<typeof MasterRecordStatusSchema>;

export const MasterTypeSchema = z.object({
  code: z.string(),
  name: z.string(),
  scope: MasterTypeScopeSchema,
  ownerModuleCode: z.string().nullable(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type MasterType = z.infer<typeof MasterTypeSchema>;

/** Structural/injection safety only -- string values, no angle brackets. Real business-field semantics belong to whichever future domain capability defines a master_type's attribute shape. */
export const MasterAttributesSchema = z.record(z.string(), z.union([z.string().regex(/^[^<>]*$/), z.number(), z.boolean(), z.null()]));
export type MasterAttributes = z.infer<typeof MasterAttributesSchema>;

export const MasterAliasesSchema = z.array(z.string().min(1).max(120).regex(/^[^<>]*$/)).max(20);
export type MasterAliases = z.infer<typeof MasterAliasesSchema>;

export const MasterRecordSchema = z.object({
  id: z.string().uuid(),
  masterTypeCode: z.string(),
  tenantId: z.string().uuid().nullable(),
  code: z.string(),
  name: z.string(),
  aliases: z.array(z.unknown()),
  attributes: z.record(z.string(), z.unknown()),
  canonicalStatus: MasterRecordStatusSchema,
  mergedIntoId: z.string().uuid().nullable(),
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable(),
  createdBy: z.string().nullable(),
  deactivatedAt: z.string().nullable(),
  deactivatedBy: z.string().nullable(),
  deactivatedReason: z.string().nullable(),
  mergedAt: z.string().nullable(),
  mergedBy: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type MasterRecord = z.infer<typeof MasterRecordSchema>;

export const RegisterMasterTypeInputSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  scope: MasterTypeScopeSchema,
  ownerModuleCode: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  registeredBy: z.string().min(1),
});
export type RegisterMasterTypeInput = z.infer<typeof RegisterMasterTypeInputSchema>;

export const CreateMasterRecordInputSchema = z.object({
  masterTypeCode: z.string().min(1),
  tenantId: z.string().uuid().nullable(),
  code: z.string().min(1),
  name: z.string().min(1),
  aliases: MasterAliasesSchema.default([]),
  attributes: MasterAttributesSchema.default({}),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateMasterRecordInput = z.input<typeof CreateMasterRecordInputSchema>;

export const UpdateMasterRecordInputSchema = z.object({
  recordId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  name: z.string().min(1).nullable().default(null),
  aliases: MasterAliasesSchema.nullable().default(null),
  attributes: MasterAttributesSchema.nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateMasterRecordInput = z.input<typeof UpdateMasterRecordInputSchema>;

export const DeactivateMasterRecordInputSchema = z.object({
  recordId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  reason: z.string().min(1),
  actorLabel: z.string().min(1),
});
export type DeactivateMasterRecordInput = z.infer<typeof DeactivateMasterRecordInputSchema>;

export const MergeMasterRecordsInputSchema = z.object({
  sourceId: z.string().uuid(),
  targetId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  reason: z.string().min(1),
  actorLabel: z.string().min(1),
});
export type MergeMasterRecordsInput = z.infer<typeof MergeMasterRecordsInputSchema>;

export const ResolveMasterRecordInputSchema = z.object({
  masterTypeCode: z.string().min(1),
  tenantId: z.string().uuid().nullable(),
  codeOrAlias: z.string().min(1),
});
export type ResolveMasterRecordInput = z.infer<typeof ResolveMasterRecordInputSchema>;

export const SearchMasterRecordsInputSchema = z.object({
  masterTypeCode: z.string().min(1),
  tenantId: z.string().uuid().nullable(),
  query: z.string().nullable().default(null),
  limit: z.number().int().positive().max(200).default(50),
  afterCode: z.string().nullable().default(null),
});
export type SearchMasterRecordsInput = z.input<typeof SearchMasterRecordsInputSchema>;

/** Maps a raw app.master_types row (snake_case) to this contract's camelCase shape. */
export function parseMasterType(row: Record<string, unknown>): MasterType {
  return MasterTypeSchema.parse({
    code: row.code,
    name: row.name,
    scope: row.scope,
    ownerModuleCode: row.owner_module_code,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.master_records row (snake_case) to this contract's camelCase shape. */
export function parseMasterRecord(row: Record<string, unknown>): MasterRecord {
  return MasterRecordSchema.parse({
    id: row.id,
    masterTypeCode: row.master_type_code,
    tenantId: row.tenant_id,
    code: row.code,
    name: row.name,
    aliases: row.aliases,
    attributes: row.attributes,
    canonicalStatus: row.canonical_status,
    mergedIntoId: row.merged_into_id,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    createdBy: row.created_by,
    deactivatedAt: row.deactivated_at,
    deactivatedBy: row.deactivated_by,
    deactivatedReason: row.deactivated_reason,
    mergedAt: row.merged_at,
    mergedBy: row.merged_by,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
