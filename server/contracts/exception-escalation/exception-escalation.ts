/**
 * Exception and Escalation contract (OPS-174, CG-S8-OPS-008). Mirrors
 * supabase/migrations/20260727150000_create_operations_exception_escalation.sql's
 * app.exception_sla_policy_versions/app.operational_exceptions/
 * app.exception_escalations/app.exceptions_directory shapes and their RPCs.
 *
 * Basic operational exception intake, ownership, SLA, escalation and resolution
 * linked to Shipment Order/milestone evidence. Type/severity are a small, fixed,
 * CHECK-constrained taxonomy (mirroring OPS-169's own bounded `mode` enum); SLA/
 * escalation policy is real and versioned, pinned onto each exception as a governed
 * snapshot at creation time. Sensitive fields (internal_notes/damage_loss_details/
 * claim_amount/claim_currency) are masked at read time by app.exceptions_directory --
 * mutation return values carry the real (unmasked) row, the same established
 * precedent OPS-168's own app.confirm_job_order already set for app.job_orders.
 */

import { z } from "zod";

export const EXCEPTION_TYPES = ["delay", "hold", "damage", "loss", "incident"] as const;
export const ExceptionTypeSchema = z.enum(EXCEPTION_TYPES);
export type ExceptionType = z.infer<typeof ExceptionTypeSchema>;

export const EXCEPTION_SEVERITIES = ["low", "medium", "high", "critical"] as const;
export const ExceptionSeveritySchema = z.enum(EXCEPTION_SEVERITIES);
export type ExceptionSeverity = z.infer<typeof ExceptionSeveritySchema>;

export const EXCEPTION_STATUSES = ["open", "acknowledged", "resolved", "reopened", "closed"] as const;
export const ExceptionStatusSchema = z.enum(EXCEPTION_STATUSES);
export type ExceptionStatus = z.infer<typeof ExceptionStatusSchema>;

export const EXCEPTION_SOURCES = ["manual", "system"] as const;
export const ExceptionSourceSchema = z.enum(EXCEPTION_SOURCES);
export type ExceptionSource = z.infer<typeof ExceptionSourceSchema>;

export const EXCEPTION_SLA_POLICY_STATUSES = ["draft", "published", "archived"] as const;
export const ExceptionSlaPolicyStatusSchema = z.enum(EXCEPTION_SLA_POLICY_STATUSES);
export type ExceptionSlaPolicyStatus = z.infer<typeof ExceptionSlaPolicyStatusSchema>;

export const ExceptionSlaPolicyVersionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  type: ExceptionTypeSchema,
  severity: ExceptionSeveritySchema,
  status: ExceptionSlaPolicyStatusSchema,
  slaHours: z.number().nullable(),
  escalationSchedule: z.array(z.number()),
  supersedesVersionId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ExceptionSlaPolicyVersion = z.infer<typeof ExceptionSlaPolicyVersionSchema>;

export function parseExceptionSlaPolicyVersion(row: Record<string, unknown>): ExceptionSlaPolicyVersion {
  return ExceptionSlaPolicyVersionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    type: row.type,
    severity: row.severity,
    status: row.status,
    slaHours: row.sla_hours === null || row.sla_hours === undefined ? null : Number(row.sla_hours),
    escalationSchedule: row.escalation_schedule,
    supersedesVersionId: row.supersedes_version_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const EXCEPTION_SOURCE_CLASSES = ["driver_mobile", "direct_device", "third_party_platform"] as const;
export const ExceptionSourceClassSchema = z.enum(EXCEPTION_SOURCE_CLASSES);
export type ExceptionSourceClass = z.infer<typeof ExceptionSourceClassSchema>;

export const EXCEPTION_FRESHNESS_STATUSES = ["healthy", "stale", "offline"] as const;
export const ExceptionFreshnessStatusSchema = z.enum(EXCEPTION_FRESHNESS_STATUSES);
export type ExceptionFreshnessStatus = z.infer<typeof ExceptionFreshnessStatusSchema>;

export const OperationalExceptionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  milestoneEventId: z.string().uuid().nullable(),
  type: ExceptionTypeSchema,
  severity: ExceptionSeveritySchema,
  status: ExceptionStatusSchema,
  ownerUserId: z.string().uuid().nullable(),
  slaPolicyVersionId: z.string().uuid().nullable(),
  slaHours: z.number().nullable(),
  dueAt: z.string().nullable(),
  escalationLevel: z.number().int().nonnegative(),
  source: ExceptionSourceSchema,
  correlationKey: z.string().nullable(),
  description: z.string(),
  internalNotes: z.string().nullable(),
  damageLossDetails: z.record(z.string(), z.unknown()).nullable(),
  claimAmount: z.number().nullable(),
  claimCurrency: z.string().nullable(),
  resolutionEvidence: z.string().nullable(),
  resolvedAt: z.string().nullable(),
  reopenedAt: z.string().nullable(),
  closedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  sourceClass: ExceptionSourceClassSchema.nullable(),
  sourceConfidenceScore: z.coerce.number().min(0).max(1).nullable(),
  sourceFreshnessStatus: ExceptionFreshnessStatusSchema.nullable(),
  sourceSignalId: z.string().uuid().nullable(),
});
export type OperationalException = z.infer<typeof OperationalExceptionSchema>;

/** sourceClass/sourceConfidenceScore/sourceFreshnessStatus/sourceSignalId were added at ATW-228 -- always null for a manual exception, a historical row predating this widening, or a tracking_health_no_signal signal (whose premise is the absence of a telemetry event). */
function baseExceptionFields(row: Record<string, unknown>) {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    milestoneEventId: row.milestone_event_id ?? null,
    type: row.type,
    severity: row.severity,
    status: row.status,
    ownerUserId: row.owner_user_id ?? null,
    slaPolicyVersionId: row.sla_policy_version_id ?? null,
    slaHours: row.sla_hours === null || row.sla_hours === undefined ? null : Number(row.sla_hours),
    dueAt: row.due_at ?? null,
    escalationLevel: row.escalation_level,
    source: row.source,
    correlationKey: row.correlation_key ?? null,
    description: row.description,
    resolutionEvidence: row.resolution_evidence ?? null,
    resolvedAt: row.resolved_at ?? null,
    reopenedAt: row.reopened_at ?? null,
    closedAt: row.closed_at ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    sourceClass: row.source_class ?? null,
    sourceConfidenceScore: row.source_confidence_score ?? null,
    sourceFreshnessStatus: row.source_freshness_status ?? null,
    sourceSignalId: row.source_signal_id ?? null,
  };
}

/** Maps a raw app.operational_exceptions row (full, unmasked -- the shape every mutation RPC returns). */
export function parseOperationalException(row: Record<string, unknown>): OperationalException {
  return OperationalExceptionSchema.parse({
    ...baseExceptionFields(row),
    internalNotes: row.internal_notes ?? null,
    damageLossDetails: row.damage_loss_details ?? null,
    claimAmount: row.claim_amount === null || row.claim_amount === undefined ? null : Number(row.claim_amount),
    claimCurrency: row.claim_currency ?? null,
  });
}

export const ExceptionDirectoryRowSchema = OperationalExceptionSchema.extend({
  sensitiveMasked: z.boolean(),
});
export type ExceptionDirectoryRow = z.infer<typeof ExceptionDirectoryRowSchema>;

/** Maps a raw app.exceptions_directory row -- internal_notes/damage_loss_details/claim_amount/claim_currency are already nulled by the view itself when sensitiveMasked. */
export function parseExceptionDirectoryRow(row: Record<string, unknown>): ExceptionDirectoryRow {
  return ExceptionDirectoryRowSchema.parse({
    ...baseExceptionFields(row),
    internalNotes: row.internal_notes ?? null,
    damageLossDetails: row.damage_loss_details ?? null,
    claimAmount: row.claim_amount === null || row.claim_amount === undefined ? null : Number(row.claim_amount),
    claimCurrency: row.claim_currency ?? null,
    sensitiveMasked: row.sensitive_masked,
  });
}

export const ExceptionEscalationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  exceptionId: z.string().uuid(),
  escalationLevel: z.number().int().positive(),
  reason: z.string(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  escalatedAt: z.string(),
});
export type ExceptionEscalation = z.infer<typeof ExceptionEscalationSchema>;

export function parseExceptionEscalation(row: Record<string, unknown>): ExceptionEscalation {
  return ExceptionEscalationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    exceptionId: row.exception_id,
    escalationLevel: row.escalation_level,
    reason: row.reason,
    actorAuthUserId: row.actor_auth_user_id ?? null,
    actorLabel: row.actor_label ?? null,
    escalatedAt: row.escalated_at,
  });
}

export const CreateExceptionSlaPolicyDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  type: ExceptionTypeSchema,
  severity: ExceptionSeveritySchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateExceptionSlaPolicyDraftInput = z.input<typeof CreateExceptionSlaPolicyDraftInputSchema>;

export const SetExceptionSlaPolicyTermsInputSchema = z.object({
  versionId: z.string().uuid(),
  slaHours: z.number().positive(),
  escalationSchedule: z.array(z.number()).default([]),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetExceptionSlaPolicyTermsInput = z.input<typeof SetExceptionSlaPolicyTermsInputSchema>;

export const PublishExceptionSlaPolicyVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  supersedesVersionId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishExceptionSlaPolicyVersionInput = z.input<typeof PublishExceptionSlaPolicyVersionInputSchema>;

export const ReportExceptionInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  milestoneEventId: z.string().uuid().nullable().default(null),
  type: ExceptionTypeSchema,
  severity: ExceptionSeveritySchema,
  description: z.string().min(1),
  source: ExceptionSourceSchema,
  correlationKey: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReportExceptionInput = z.input<typeof ReportExceptionInputSchema>;

export const AssignExceptionOwnerInputSchema = z.object({
  exceptionId: z.string().uuid(),
  ownerUserId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AssignExceptionOwnerInput = z.input<typeof AssignExceptionOwnerInputSchema>;

export const AcknowledgeExceptionInputSchema = z.object({
  exceptionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AcknowledgeExceptionInput = z.input<typeof AcknowledgeExceptionInputSchema>;

export const EscalateExceptionInputSchema = z.object({
  exceptionId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type EscalateExceptionInput = z.input<typeof EscalateExceptionInputSchema>;

export const ResolveExceptionInputSchema = z.object({
  exceptionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  resolutionEvidence: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ResolveExceptionInput = z.input<typeof ResolveExceptionInputSchema>;

export const CloseExceptionInputSchema = z.object({
  exceptionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CloseExceptionInput = z.input<typeof CloseExceptionInputSchema>;

export const ReopenExceptionInputSchema = z.object({
  exceptionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReopenExceptionInput = z.input<typeof ReopenExceptionInputSchema>;

export const SetExceptionSensitiveFieldsInputSchema = z.object({
  exceptionId: z.string().uuid(),
  internalNotes: z.string().nullable().default(null),
  damageLossDetails: z.record(z.string(), z.unknown()).nullable().default(null),
  claimAmount: z.number().nonnegative().nullable().default(null),
  claimCurrency: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetExceptionSensitiveFieldsInput = z.input<typeof SetExceptionSensitiveFieldsInputSchema>;

export const GetExceptionEscalationHistoryInputSchema = z.object({
  exceptionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetExceptionEscalationHistoryInput = z.input<typeof GetExceptionEscalationHistoryInputSchema>;
