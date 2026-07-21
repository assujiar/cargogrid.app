/**
 * Background job framework contract (PLT-132, CG-S6-PLT-029). Mirrors
 * supabase/migrations/20260719180000_create_background_job_framework.sql's
 * app.event_logs shape and the app.enqueue_job / app.claim_next_job /
 * app.heartbeat_job / app.complete_job / app.append_event_log /
 * app.dispatch_event_as_job / app.mark_event_dispatch_failed RPCs, plus
 * app.compute_job_backoff_seconds().
 *
 * app.jobs itself is one table, one row shape, regardless of job_type -- this
 * capability deliberately reuses ../import-export/import-export.ts's
 * ImportExportJobSchema/ImportExportJob/parseImportExportJob/ImportExportJobTypeSchema
 * directly for generic (non-import/export) job rows too, rather than forking an
 * identically-shaped duplicate contract under a new name (see that file's own header
 * for the reciprocal disclosure of this reuse).
 */

import { z } from "zod";
import { ImportExportJobTypeSchema, type ImportExportJobType } from "../import-export/import-export.ts";

/** The eight job_type codes this capability's own generic queue mechanics serve -- import/export keep their own dedicated app.create_import_export_job() entrypoint (PLT-131). */
export const GENERIC_JOB_TYPES = [
  "report_generation",
  "notification_batch",
  "webhook_retry",
  "document_generation",
  "dashboard_refresh",
  "loyalty_expiration",
  "recurring_billing",
  "integration_sync",
] as const;
export const GenericJobTypeSchema = z.enum(GENERIC_JOB_TYPES);
export type GenericJobType = z.infer<typeof GenericJobTypeSchema>;

export const EVENT_DISPATCH_STATUSES = ["pending", "dispatched", "failed"] as const;
export const EventDispatchStatusSchema = z.enum(EVENT_DISPATCH_STATUSES);
export type EventDispatchStatus = z.infer<typeof EventDispatchStatusSchema>;

export const EventLogSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  eventType: z.string(),
  resourceType: z.string(),
  resourceId: z.string().uuid().nullable(),
  payload: z.record(z.string(), z.unknown()),
  dispatchStatus: EventDispatchStatusSchema,
  relatedJobId: z.string().uuid().nullable(),
  occurredAt: z.string(),
  dispatchedAt: z.string().nullable(),
  error: z.string().nullable(),
  createdBy: z.string().nullable(),
});
export type EventLog = z.infer<typeof EventLogSchema>;

export const EnqueueJobInputSchema = z.object({
  tenantId: z.string().uuid(),
  jobType: GenericJobTypeSchema,
  payload: z.record(z.string(), z.unknown()).default({}),
  priority: z.number().int().default(0),
  idempotencyKey: z.string().nullable().default(null),
  maxAttempts: z.number().int().positive().default(3),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type EnqueueJobInput = z.input<typeof EnqueueJobInputSchema>;

export const ClaimNextJobInputSchema = z.object({
  workerId: z.string().min(1),
  jobTypes: z.array(ImportExportJobTypeSchema).min(1),
  leaseDurationSeconds: z.number().int().positive().default(300),
});
export type ClaimNextJobInput = z.input<typeof ClaimNextJobInputSchema>;

export const HeartbeatJobInputSchema = z.object({
  jobId: z.string().uuid(),
  workerId: z.string().min(1),
  leaseDurationSeconds: z.number().int().positive().default(300),
});
export type HeartbeatJobInput = z.input<typeof HeartbeatJobInputSchema>;

export const CompleteJobInputSchema = z.object({
  jobId: z.string().uuid(),
  workerId: z.string().min(1),
  resultUrl: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type CompleteJobInput = z.input<typeof CompleteJobInputSchema>;

export const AppendEventLogInputSchema = z.object({
  tenantId: z.string().uuid(),
  eventType: z.string().min(1),
  resourceType: z.string().min(1),
  resourceId: z.string().uuid().nullable().default(null),
  payload: z.record(z.string(), z.unknown()).default({}),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AppendEventLogInput = z.input<typeof AppendEventLogInputSchema>;

export const DispatchEventAsJobInputSchema = z.object({
  eventId: z.string().uuid(),
  jobType: GenericJobTypeSchema,
  priority: z.number().int().default(0),
  idempotencyKey: z.string().nullable().default(null),
  maxAttempts: z.number().int().positive().default(3),
  actorLabel: z.string().min(1),
});
export type DispatchEventAsJobInput = z.input<typeof DispatchEventAsJobInputSchema>;

export const MarkEventDispatchFailedInputSchema = z.object({
  eventId: z.string().uuid(),
  error: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type MarkEventDispatchFailedInput = z.input<typeof MarkEventDispatchFailedInputSchema>;

export function parseEventLog(row: Record<string, unknown>): EventLog {
  return EventLogSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    eventType: row.event_type,
    resourceType: row.resource_type,
    resourceId: row.resource_id,
    payload: row.payload,
    dispatchStatus: row.dispatch_status,
    relatedJobId: row.related_job_id,
    occurredAt: row.occurred_at,
    dispatchedAt: row.dispatched_at,
    error: row.error,
    createdBy: row.created_by,
  });
}

export type { ImportExportJobType as JobType };
