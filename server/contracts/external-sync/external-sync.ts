/**
 * External Accounting and HR Integrations contract (IAE-018, Prompt 346).
 * Mirrors supabase/migrations/
 * 20260805050000_create_intelligence_external_accounting_hr_integrations.sql's
 * app.external_sync_entity_mappings / app.external_sync_entity_links /
 * app.external_sync_records shapes and their mapping/link/ingest/review/
 * list/trigger RPCs.
 */

import { z } from "zod";

export const EXTERNAL_SYNC_ADAPTER_CODES = ["external_accounting_system", "external_hr_system"] as const;
export const ExternalSyncAdapterCodeSchema = z.enum(EXTERNAL_SYNC_ADAPTER_CODES);
export type ExternalSyncAdapterCode = z.infer<typeof ExternalSyncAdapterCodeSchema>;

export const EXTERNAL_SYNC_ENTITY_TYPES = ["employee", "gl_account"] as const;
export const ExternalSyncEntityTypeSchema = z.enum(EXTERNAL_SYNC_ENTITY_TYPES);
export type ExternalSyncEntityType = z.infer<typeof ExternalSyncEntityTypeSchema>;

export const EXTERNAL_SYNC_OWNERSHIP_DIRECTIONS = ["cargogrid_source", "external_source", "bidirectional"] as const;
export const ExternalSyncOwnershipDirectionSchema = z.enum(EXTERNAL_SYNC_OWNERSHIP_DIRECTIONS);
export type ExternalSyncOwnershipDirection = z.infer<typeof ExternalSyncOwnershipDirectionSchema>;

export const EXTERNAL_SYNC_MATCH_STATUSES = ["matched", "unmatched"] as const;
export const ExternalSyncMatchStatusSchema = z.enum(EXTERNAL_SYNC_MATCH_STATUSES);
export type ExternalSyncMatchStatus = z.infer<typeof ExternalSyncMatchStatusSchema>;

export const EXTERNAL_SYNC_CONFLICT_STATUSES = ["no_conflict", "conflicts_detected", "reviewed", "dismissed"] as const;
export const ExternalSyncConflictStatusSchema = z.enum(EXTERNAL_SYNC_CONFLICT_STATUSES);
export type ExternalSyncConflictStatus = z.infer<typeof ExternalSyncConflictStatusSchema>;

export const ExternalSyncEntityMappingSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  adapterCode: ExternalSyncAdapterCodeSchema,
  entityType: ExternalSyncEntityTypeSchema,
  ownershipDirection: ExternalSyncOwnershipDirectionSchema,
  status: z.enum(["active", "inactive"]),
  notes: z.string().nullable(),
  createdAt: z.string(),
});
export type ExternalSyncEntityMapping = z.infer<typeof ExternalSyncEntityMappingSchema>;

export function parseExternalSyncEntityMapping(row: Record<string, unknown>): ExternalSyncEntityMapping {
  return ExternalSyncEntityMappingSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    adapterCode: row.adapter_code,
    entityType: row.entity_type,
    ownershipDirection: row.ownership_direction,
    status: row.status,
    notes: row.notes,
    createdAt: row.created_at,
  });
}

export const ExternalSyncEntityLinkSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  adapterCode: ExternalSyncAdapterCodeSchema,
  entityType: ExternalSyncEntityTypeSchema,
  externalEntityId: z.string(),
  internalRecordId: z.string().uuid(),
  linkedByAuthUserId: z.string().uuid().nullable(),
  linkedBy: z.string().nullable(),
  linkedAt: z.string(),
});
export type ExternalSyncEntityLink = z.infer<typeof ExternalSyncEntityLinkSchema>;

export function parseExternalSyncEntityLink(row: Record<string, unknown>): ExternalSyncEntityLink {
  return ExternalSyncEntityLinkSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    adapterCode: row.adapter_code,
    entityType: row.entity_type,
    externalEntityId: row.external_entity_id,
    internalRecordId: row.internal_record_id,
    linkedByAuthUserId: row.linked_by_auth_user_id,
    linkedBy: row.linked_by,
    linkedAt: row.linked_at,
  });
}

export const ExternalSyncRecordSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  entityType: ExternalSyncEntityTypeSchema,
  externalEntityId: z.string(),
  internalRecordId: z.string().uuid().nullable(),
  matchStatus: ExternalSyncMatchStatusSchema,
  rawPayload: z.record(z.string(), z.unknown()),
  fieldDiffs: z.record(z.string(), z.unknown()).nullable(),
  conflictStatus: ExternalSyncConflictStatusSchema,
  reviewNotes: z.string().nullable(),
  reviewedByAuthUserId: z.string().uuid().nullable(),
  reviewedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type ExternalSyncRecord = z.infer<typeof ExternalSyncRecordSchema>;

export function parseExternalSyncRecord(row: Record<string, unknown>): ExternalSyncRecord {
  return ExternalSyncRecordSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    connectionId: row.connection_id,
    entityType: row.entity_type,
    externalEntityId: row.external_entity_id,
    internalRecordId: row.internal_record_id,
    matchStatus: row.match_status,
    rawPayload: row.raw_payload,
    fieldDiffs: row.field_diffs,
    conflictStatus: row.conflict_status,
    reviewNotes: row.review_notes,
    reviewedByAuthUserId: row.reviewed_by_auth_user_id,
    reviewedAt: row.reviewed_at,
    createdAt: row.created_at,
  });
}

export const SetExternalSyncEntityMappingInputSchema = z.object({
  tenantId: z.string().uuid(),
  adapterCode: ExternalSyncAdapterCodeSchema,
  entityType: ExternalSyncEntityTypeSchema,
  ownershipDirection: ExternalSyncOwnershipDirectionSchema,
  notes: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetExternalSyncEntityMappingInput = z.input<typeof SetExternalSyncEntityMappingInputSchema>;

export const LinkExternalSyncEntityInputSchema = z.object({
  tenantId: z.string().uuid(),
  adapterCode: ExternalSyncAdapterCodeSchema,
  entityType: ExternalSyncEntityTypeSchema,
  externalEntityId: z.string().min(1),
  internalRecordId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type LinkExternalSyncEntityInput = z.input<typeof LinkExternalSyncEntityInputSchema>;

export const RecordExternalSyncSnapshotInputSchema = z.object({
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  adapterCode: ExternalSyncAdapterCodeSchema,
  entityType: ExternalSyncEntityTypeSchema,
  externalEntityId: z.string().min(1),
  rawPayload: z.record(z.string(), z.unknown()),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordExternalSyncSnapshotInput = z.input<typeof RecordExternalSyncSnapshotInputSchema>;

export const ReviewExternalSyncConflictInputSchema = z.object({
  recordId: z.string().uuid(),
  decision: z.enum(["reviewed", "dismissed"]),
  notes: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReviewExternalSyncConflictInput = z.input<typeof ReviewExternalSyncConflictInputSchema>;

export const ListExternalSyncRecordsForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  entityType: ExternalSyncEntityTypeSchema.nullable().default(null),
  conflictStatus: ExternalSyncConflictStatusSchema.nullable().default(null),
  limit: z.number().int().positive().max(200).default(50),
});
export type ListExternalSyncRecordsForTenantInput = z.input<typeof ListExternalSyncRecordsForTenantInputSchema>;

export const TriggerExternalSyncInputSchema = z.object({
  tenantId: z.string().uuid(),
  connectionId: z.string().uuid(),
  entityType: ExternalSyncEntityTypeSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type TriggerExternalSyncInput = z.input<typeof TriggerExternalSyncInputSchema>;

/** The real poll worker's own connection read -- no actor authority check (already-authorized background job). */
export const ExternalSyncConnectionForSyncSchema = z.object({
  tenantId: z.string().uuid(),
  adapterCode: z.string(),
  connectionStatus: z.string(),
  connectionConfig: z.record(z.string(), z.unknown()),
});
export type ExternalSyncConnectionForSync = z.infer<typeof ExternalSyncConnectionForSyncSchema>;

export function parseExternalSyncConnectionForSync(row: Record<string, unknown>): ExternalSyncConnectionForSync {
  return ExternalSyncConnectionForSyncSchema.parse({
    tenantId: row.tenant_id,
    adapterCode: row.adapter_code,
    connectionStatus: row.connection_status,
    connectionConfig: row.connection_config,
  });
}
