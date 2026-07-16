/**
 * Audit trail contract (PLT-116, CG-S6-PLT-013). Mirrors
 * supabase/migrations/20260716113048_create_audit_trail.sql's app.audit_logs shape and
 * the app.capture_audit_event / app.supreme_admin_mutate_audit_log /
 * app.supreme_admin_delete_audit_log / app.query_audit_logs / app.export_audit_logs
 * RPCs.
 */

import { z } from "zod";

export const AUDIT_RESULTS = ["success", "failure"] as const;
export const AuditResultSchema = z.enum(AUDIT_RESULTS);
export type AuditResult = z.infer<typeof AuditResultSchema>;

export const AuditLogSchema = z.object({
  id: z.string().uuid(),
  correlationId: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string(),
  action: z.string(),
  resourceType: z.string(),
  resourceId: z.string().uuid().nullable(),
  result: AuditResultSchema,
  reason: z.string().nullable(),
  beforeValue: z.record(z.string(), z.unknown()).nullable(),
  afterValue: z.record(z.string(), z.unknown()).nullable(),
  occurredAt: z.string(),
  legalHold: z.boolean(),
  legalHoldReason: z.string().nullable(),
});
export type AuditLog = z.infer<typeof AuditLogSchema>;

export const CaptureAuditEventInputSchema = z.object({
  tenantId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().min(1),
  action: z.string().min(1),
  resourceType: z.string().min(1),
  resourceId: z.string().uuid().nullable(),
  result: AuditResultSchema,
  reason: z.string().nullable().default(null),
  beforeValue: z.record(z.string(), z.unknown()).nullable().default(null),
  afterValue: z.record(z.string(), z.unknown()).nullable().default(null),
  correlationId: z.string().uuid().nullable().default(null),
});
export type CaptureAuditEventInput = z.input<typeof CaptureAuditEventInputSchema>;

export const SupremeAdminMutateAuditLogInputSchema = z.object({
  actorAuthUserId: z.string().uuid(),
  targetId: z.string().uuid(),
  newReason: z.string().nullable().default(null),
  newLegalHold: z.boolean().nullable().default(null),
  newLegalHoldReason: z.string().nullable().default(null),
  mutationReason: z.string().min(1),
});
export type SupremeAdminMutateAuditLogInput = z.input<typeof SupremeAdminMutateAuditLogInputSchema>;

export const SupremeAdminDeleteAuditLogInputSchema = z.object({
  actorAuthUserId: z.string().uuid(),
  targetId: z.string().uuid(),
  reason: z.string().min(1),
});
export type SupremeAdminDeleteAuditLogInput = z.infer<typeof SupremeAdminDeleteAuditLogInputSchema>;

export const QueryAuditLogsInputSchema = z.object({
  requesterAuthUserId: z.string().uuid(),
  tenantId: z.string().uuid(),
  limit: z.number().int().positive().default(50),
  beforeOccurredAt: z.string().nullable().default(null),
  beforeId: z.string().uuid().nullable().default(null),
});
export type QueryAuditLogsInput = z.input<typeof QueryAuditLogsInputSchema>;

/** Maps a raw app.audit_logs row (snake_case) to this contract's camelCase shape. */
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
  });
}
