/**
 * Advanced Audit and Impersonation contract (IAE-029, Prompt 357). Mirrors
 * supabase/migrations/20260807300000_create_intelligence_advanced_audit_impersonation.sql's
 * app.audit_logs (widened with support_access_grant_id) and
 * app.audit_export_requests shapes, and their search/list/request/record/get
 * RPCs.
 */

import { z } from "zod";

export const AuditLogSchema = z.object({
  id: z.string().uuid(),
  correlationId: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string(),
  action: z.string(),
  resourceType: z.string(),
  resourceId: z.string().uuid().nullable(),
  result: z.enum(["success", "failure"]),
  reason: z.string().nullable(),
  beforeValue: z.record(z.string(), z.unknown()).nullable(),
  afterValue: z.record(z.string(), z.unknown()).nullable(),
  occurredAt: z.string(),
  legalHold: z.boolean(),
  legalHoldReason: z.string().nullable(),
  supportAccessGrantId: z.string().uuid().nullable(),
});
export type AuditLog = z.infer<typeof AuditLogSchema>;

export function parseAuditLog(row: Record<string, unknown>): AuditLog {
  return AuditLogSchema.parse({
    id: row.id,
    correlationId: row.correlation_id,
    tenantId: row.tenant_id,
    actorAuthUserId: row.actor_auth_user_id,
    actorLabel: row.actor_label,
    action: row.action,
    resourceType: row.resource_type,
    resourceId: row.resource_id,
    result: row.result,
    reason: row.reason,
    beforeValue: row.before_value,
    afterValue: row.after_value,
    occurredAt: row.occurred_at,
    legalHold: row.legal_hold,
    legalHoldReason: row.legal_hold_reason,
    supportAccessGrantId: row.support_access_grant_id,
  });
}

export const AUDIT_EXPORT_STATUSES = ["pending", "processing", "ready", "failed", "expired"] as const;
export const AuditExportStatusSchema = z.enum(AUDIT_EXPORT_STATUSES);
export type AuditExportStatus = z.infer<typeof AuditExportStatusSchema>;

export const AuditExportRequestSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  requestedByAuthUserId: z.string().uuid(),
  requestedBy: z.string().nullable(),
  filters: z.record(z.string(), z.unknown()),
  status: AuditExportStatusSchema,
  resultRowCount: z.number().int().nullable(),
  resultPayload: z.unknown().nullable(),
  failureReason: z.string().nullable(),
  requestedAt: z.string(),
  completedAt: z.string().nullable(),
  expiresAt: z.string().nullable(),
});
export type AuditExportRequest = z.infer<typeof AuditExportRequestSchema>;

export function parseAuditExportRequest(row: Record<string, unknown>): AuditExportRequest {
  return AuditExportRequestSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestedBy: row.requested_by,
    filters: row.filters,
    status: row.status,
    resultRowCount: row.result_row_count,
    resultPayload: row.result_payload,
    failureReason: row.failure_reason,
    requestedAt: row.requested_at,
    completedAt: row.completed_at,
    expiresAt: row.expires_at,
  });
}

export const SearchAuditLogsInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserIdFilter: z.string().uuid().nullable(),
  actionFilter: z.string().nullable(),
  resourceTypeFilter: z.string().nullable(),
  resultFilter: z.enum(["success", "failure"]).nullable(),
  supportAccessGrantIdFilter: z.string().uuid().nullable(),
  occurredAfter: z.string().nullable(),
  occurredBefore: z.string().nullable(),
  requesterAuthUserId: z.string().uuid(),
  limit: z.number().int().min(1).max(200).optional(),
});
export type SearchAuditLogsInput = z.input<typeof SearchAuditLogsInputSchema>;

export const RequestAuditExportInputSchema = z.object({
  tenantId: z.string().uuid(),
  filters: z.record(z.string(), z.unknown()),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestAuditExportInput = z.input<typeof RequestAuditExportInputSchema>;

export const RecordAuditExportOutcomeInputSchema = z.object({
  requestId: z.string().uuid(),
  status: z.enum(["ready", "failed"]),
  resultRowCount: z.number().int().nullable(),
  resultPayload: z.unknown().nullable(),
  failureReason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordAuditExportOutcomeInput = z.input<typeof RecordAuditExportOutcomeInputSchema>;
