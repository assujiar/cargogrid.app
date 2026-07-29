/**
 * Period Lock and Governed Reopen contract (FIN-207, CG-S9-FIN-018). Mirrors
 * supabase/migrations/20260729210000_create_finance_period_lock.sql's
 * app.finance_period_locks / app.finance_period_lock_events shapes and RPCs.
 */

import { z } from "zod";

export const FINANCE_PERIOD_LOCK_SCOPES = ["all", "gl", "ar", "ap", "tax"] as const;
export const FinancePeriodLockScopeSchema = z.enum(FINANCE_PERIOD_LOCK_SCOPES);
export type FinancePeriodLockScope = z.infer<typeof FinancePeriodLockScopeSchema>;

export const FINANCE_PERIOD_LOCK_STATUSES = ["locked", "reopen_requested", "reopened"] as const;
export const FinancePeriodLockStatusSchema = z.enum(FINANCE_PERIOD_LOCK_STATUSES);
export type FinancePeriodLockStatus = z.infer<typeof FinancePeriodLockStatusSchema>;

export const FinancePeriodLockSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  periodId: z.string().uuid(),
  lockScope: FinancePeriodLockScopeSchema,
  status: FinancePeriodLockStatusSchema,
  lockReason: z.string(),
  evidenceRef: z.string().nullable(),
  lockedBy: z.string().nullable(),
  lockedAt: z.string(),
  reopenReason: z.string().nullable(),
  reopenRequestedBy: z.string().nullable(),
  reopenRequestedAt: z.string().nullable(),
  reopenApprovedBy: z.string().nullable(),
  reopenWindowExpiresAt: z.string().nullable(),
  reopenedAt: z.string().nullable(),
  relockedBy: z.string().nullable(),
  relockedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinancePeriodLock = z.infer<typeof FinancePeriodLockSchema>;

export const FinancePeriodLockEventSchema = z.object({
  id: z.string().uuid(),
  lockId: z.string().uuid(),
  tenantId: z.string().uuid(),
  action: z.enum(["locked", "reopen_requested", "reopened", "relocked"]),
  reason: z.string().nullable(),
  actorLabel: z.string().nullable(),
  createdAt: z.string(),
});
export type FinancePeriodLockEvent = z.infer<typeof FinancePeriodLockEventSchema>;

export const LockFinancePeriodInputSchema = z.object({
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable().default(null),
  periodId: z.string().uuid(),
  lockScope: FinancePeriodLockScopeSchema,
  reason: z.string().min(1),
  evidenceRef: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type LockFinancePeriodInput = z.input<typeof LockFinancePeriodInputSchema>;

export const FinancePeriodLockLifecycleInputSchema = z.object({
  lockId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type FinancePeriodLockLifecycleInput = z.input<typeof FinancePeriodLockLifecycleInputSchema>;

export const RequestFinancePeriodReopenInputSchema = FinancePeriodLockLifecycleInputSchema.extend({
  reason: z.string().min(1),
});
export type RequestFinancePeriodReopenInput = z.input<typeof RequestFinancePeriodReopenInputSchema>;

export const ApproveFinancePeriodReopenInputSchema = FinancePeriodLockLifecycleInputSchema.extend({
  windowHours: z.number().int().positive().max(720),
});
export type ApproveFinancePeriodReopenInput = z.input<typeof ApproveFinancePeriodReopenInputSchema>;

/** Maps a raw app.finance_period_locks row (snake_case) to this contract's camelCase shape. */
export function parseFinancePeriodLock(row: Record<string, unknown>): FinancePeriodLock {
  return FinancePeriodLockSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    periodId: row.period_id,
    lockScope: row.lock_scope,
    status: row.status,
    lockReason: row.lock_reason,
    evidenceRef: row.evidence_ref,
    lockedBy: row.locked_by,
    lockedAt: row.locked_at,
    reopenReason: row.reopen_reason,
    reopenRequestedBy: row.reopen_requested_by,
    reopenRequestedAt: row.reopen_requested_at,
    reopenApprovedBy: row.reopen_approved_by,
    reopenWindowExpiresAt: row.reopen_window_expires_at,
    reopenedAt: row.reopened_at,
    relockedBy: row.relocked_by,
    relockedAt: row.relocked_at,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.finance_period_lock_events row (snake_case) to this contract's camelCase shape. */
export function parseFinancePeriodLockEvent(row: Record<string, unknown>): FinancePeriodLockEvent {
  return FinancePeriodLockEventSchema.parse({
    id: row.id,
    lockId: row.lock_id,
    tenantId: row.tenant_id,
    action: row.action,
    reason: row.reason,
    actorLabel: row.actor_label,
    createdAt: row.created_at,
  });
}
