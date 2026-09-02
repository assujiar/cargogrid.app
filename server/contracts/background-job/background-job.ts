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

/**
 * The job_type codes this capability's own generic queue mechanics serve -- import/export
 * keep their own dedicated app.create_import_export_job() entrypoint (PLT-131).
 *
 * SOURCE OF TRUTH: `app.generic_job_types()`
 * (supabase/migrations/20260730410000_harden_job_type_single_source_of_truth.sql, as
 * widened by every subsequent migration that adds a generic job type).
 * ATW-031 (ISS-2026-012) widened this list from eight to ten: `route_load_planning`
 * (ATW-224) and `print_label` (ATW-021) were both accepted by the app.jobs CHECK
 * constraint and by app.enqueue_job, but had never been added here or to
 * app.dispatch_event_as_job -- so a caller using either value failed contract parsing
 * before it could reach a database that would have accepted it.
 *
 * Batch 2 Tier C fix (20260803030000_harden_intelligence_batch2_tier_c_review_fixes.sql,
 * finding 7, cross-prompt-integration): live-verified this array had silently drifted to
 * 10 of 21 real DB-side values -- 10 prior migrations (roster_generation, leave_accrual,
 * leave_carry_forward_expiry, payroll_calculation, training_certificate_expiry(+
 * _reminder), ticket_sla_evaluation, kb_article_expiry, ticket_escalation_evaluation,
 * loyalty_expiry_sweep) plus IAE-007's own automation_action_execution had each widened
 * app.generic_job_types() without ever touching this array, and the OWN regression test
 * (background-job.test.ts) asserted this array against a second hand-copied literal in
 * the SAME file -- structurally incapable of catching drift against the real database.
 * All 11 missing values added here; scripts/db-tests/background-job.sql now also asserts
 * a hardcoded TS-mirror literal against the live app.generic_job_types() output, so a
 * FUTURE SQL-side addition that is not mirrored into both this array and that literal
 * fails `pnpm run db:test`, not only a same-file tautology. Keep this array set-equal to
 * app.generic_job_types(); background-job.test.ts asserts the exact list.
 */
export const GENERIC_JOB_TYPES = [
  "report_generation",
  "notification_batch",
  "webhook_retry",
  "document_generation",
  "dashboard_refresh",
  "loyalty_expiration",
  "recurring_billing",
  "integration_sync",
  "route_load_planning",
  "print_label",
  "roster_generation",
  "leave_accrual",
  "leave_carry_forward_expiry",
  "payroll_calculation",
  "training_certificate_expiry",
  "training_certificate_expiry_reminder",
  "ticket_sla_evaluation",
  "kb_article_expiry",
  "ticket_escalation_evaluation",
  "loyalty_expiry_sweep",
  "automation_action_execution",
  "logistics_partner_sync",
  "finance_bank_feed_sync",
  "external_sync",
  "audit_export",
  "retention_archive",
  "incident_escalation_sweep",
  // ISS-2026-126 / 127 / 128: the three loyalty sweeps that made those entries
  // schedulable -- earning evaluation, tier recalculation, points posting.
  "loyalty_earning_evaluation_sweep",
  "loyalty_tier_recalculation_sweep",
  "loyalty_points_posting_sweep",
  // ISS-2026-129 item 2: the tenant-configured recurring benefit-issuance sweep.
  "loyalty_benefit_issuance_sweep",
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
