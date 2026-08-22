/**
 * Data Retention and Archival contract (IAE-031, Prompt 359). Mirrors
 * supabase/migrations/20260807500000_create_intelligence_data_retention_archival.sql's
 * app.retention_policies / app.legal_holds / app.retention_archive_requests
 * shapes, and their configure/hold/request/outcome/list RPCs.
 */

import { z } from "zod";

export const RETENTION_RECORD_CLASSES = ["finance_tax", "audit_security", "operational"] as const;
export const RetentionRecordClassSchema = z.enum(RETENTION_RECORD_CLASSES);
export type RetentionRecordClass = z.infer<typeof RetentionRecordClassSchema>;

export const LEGAL_HOLD_STATUSES = ["active", "released"] as const;
export const LegalHoldStatusSchema = z.enum(LEGAL_HOLD_STATUSES);
export type LegalHoldStatus = z.infer<typeof LegalHoldStatusSchema>;

export const RETENTION_ARCHIVE_REQUEST_STATUSES = [
  "dry_run_completed", "blocked_within_retention", "blocked_legal_hold", "pending", "archived", "failed",
] as const;
export const RetentionArchiveRequestStatusSchema = z.enum(RETENTION_ARCHIVE_REQUEST_STATUSES);
export type RetentionArchiveRequestStatus = z.infer<typeof RetentionArchiveRequestStatusSchema>;

export const RetentionPolicySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  recordClass: RetentionRecordClassSchema,
  retentionDays: z.number().int(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  recordVersion: z.number().int(),
});
export type RetentionPolicy = z.infer<typeof RetentionPolicySchema>;

export function parseRetentionPolicy(row: Record<string, unknown>): RetentionPolicy {
  return RetentionPolicySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    recordClass: row.record_class,
    retentionDays: row.retention_days,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    recordVersion: row.record_version,
  });
}

export const LegalHoldSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  recordClass: RetentionRecordClassSchema,
  scopeRecordTable: z.string().nullable(),
  scopeRecordId: z.string().uuid().nullable(),
  reason: z.string(),
  status: LegalHoldStatusSchema,
  placedByAuthUserId: z.string().uuid(),
  placedBy: z.string().nullable(),
  placedAt: z.string(),
  releasedByAuthUserId: z.string().uuid().nullable(),
  releasedBy: z.string().nullable(),
  releasedAt: z.string().nullable(),
  releaseReason: z.string().nullable(),
});
export type LegalHold = z.infer<typeof LegalHoldSchema>;

export function parseLegalHold(row: Record<string, unknown>): LegalHold {
  return LegalHoldSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    recordClass: row.record_class,
    scopeRecordTable: row.scope_record_table,
    scopeRecordId: row.scope_record_id,
    reason: row.reason,
    status: row.status,
    placedByAuthUserId: row.placed_by_auth_user_id,
    placedBy: row.placed_by,
    placedAt: row.placed_at,
    releasedByAuthUserId: row.released_by_auth_user_id,
    releasedBy: row.released_by,
    releasedAt: row.released_at,
    releaseReason: row.release_reason,
  });
}

export const RetentionArchiveRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  recordClass: RetentionRecordClassSchema,
  sourceTable: z.string(),
  sourceRecordId: z.string().uuid(),
  recordReferenceDate: z.string(),
  dryRun: z.boolean(),
  eligibleForArchiveAt: z.string(),
  legalHoldBlocking: z.boolean(),
  status: RetentionArchiveRequestStatusSchema,
  requestedByAuthUserId: z.string().uuid(),
  requestedBy: z.string().nullable(),
  requestedAt: z.string(),
  completedAt: z.string().nullable(),
  resultNote: z.string().nullable(),
});
export type RetentionArchiveRequest = z.infer<typeof RetentionArchiveRequestSchema>;

export function parseRetentionArchiveRequest(row: Record<string, unknown>): RetentionArchiveRequest {
  return RetentionArchiveRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    recordClass: row.record_class,
    sourceTable: row.source_table,
    sourceRecordId: row.source_record_id,
    recordReferenceDate: row.record_reference_date,
    dryRun: row.dry_run,
    eligibleForArchiveAt: row.eligible_for_archive_at,
    legalHoldBlocking: row.legal_hold_blocking,
    status: row.status,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestedBy: row.requested_by,
    requestedAt: row.requested_at,
    completedAt: row.completed_at,
    resultNote: row.result_note,
  });
}

export const SetRetentionPolicyInputSchema = z.object({
  tenantId: z.string().uuid().nullable(),
  recordClass: RetentionRecordClassSchema,
  retentionDays: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetRetentionPolicyInput = z.input<typeof SetRetentionPolicyInputSchema>;

export const RequestLegalHoldInputSchema = z.object({
  tenantId: z.string().uuid(),
  recordClass: RetentionRecordClassSchema,
  scopeRecordTable: z.string().nullable(),
  scopeRecordId: z.string().uuid().nullable(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestLegalHoldInput = z.input<typeof RequestLegalHoldInputSchema>;

export const ReleaseLegalHoldInputSchema = z.object({
  holdId: z.string().uuid(),
  releaseReason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReleaseLegalHoldInput = z.input<typeof ReleaseLegalHoldInputSchema>;

export const RequestRetentionArchiveInputSchema = z.object({
  tenantId: z.string().uuid(),
  recordClass: RetentionRecordClassSchema,
  sourceTable: z.string().min(1),
  sourceRecordId: z.string().uuid(),
  recordReferenceDate: z.string(),
  dryRun: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestRetentionArchiveInput = z.input<typeof RequestRetentionArchiveInputSchema>;

export const RecordRetentionArchiveOutcomeInputSchema = z.object({
  requestId: z.string().uuid(),
  status: z.enum(["archived", "failed"]),
  resultNote: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordRetentionArchiveOutcomeInput = z.input<typeof RecordRetentionArchiveOutcomeInputSchema>;
