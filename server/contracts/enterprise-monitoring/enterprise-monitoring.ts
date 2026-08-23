/**
 * Enterprise Monitoring and Observability contract (IAE-030, Prompt 358).
 * Mirrors supabase/migrations/20260807400000_create_intelligence_enterprise_monitoring_observability.sql's
 * app.slo_definitions / app.observability_signals / app.alert_routes /
 * app.incidents / app.incident_timeline_events shapes, and their
 * configure/ingest/alert/acknowledge/resolve/list RPCs.
 */

import { z } from "zod";

export const MON_METRIC_TYPES = ["availability", "latency_p95", "error_rate", "queue_backlog"] as const;
export const MonMetricTypeSchema = z.enum(MON_METRIC_TYPES);
export type MonMetricType = z.infer<typeof MonMetricTypeSchema>;

export const MON_SOURCE_TYPES = ["job", "webhook", "api", "integration", "ai"] as const;
export const MonSourceTypeSchema = z.enum(MON_SOURCE_TYPES);
export type MonSourceType = z.infer<typeof MonSourceTypeSchema>;

export const MON_SIGNAL_TYPES = ["error", "latency_ms", "backlog_depth", "success"] as const;
export const MonSignalTypeSchema = z.enum(MON_SIGNAL_TYPES);
export type MonSignalType = z.infer<typeof MonSignalTypeSchema>;

export const INCIDENT_SEVERITIES = ["low", "medium", "high", "critical"] as const;
export const IncidentSeveritySchema = z.enum(INCIDENT_SEVERITIES);
export type IncidentSeverity = z.infer<typeof IncidentSeveritySchema>;

export const INCIDENT_STATUSES = ["open", "acknowledged", "resolved"] as const;
export const IncidentStatusSchema = z.enum(INCIDENT_STATUSES);
export type IncidentStatus = z.infer<typeof IncidentStatusSchema>;

export const INCIDENT_TIMELINE_EVENT_TYPES = ["opened", "duplicate_signal", "acknowledged", "resolved"] as const;
export const IncidentTimelineEventTypeSchema = z.enum(INCIDENT_TIMELINE_EVENT_TYPES);
export type IncidentTimelineEventType = z.infer<typeof IncidentTimelineEventTypeSchema>;

export const SloDefinitionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  serviceName: z.string(),
  metricType: MonMetricTypeSchema,
  targetValue: z.number(),
  evaluationWindowMinutes: z.number().int(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  recordVersion: z.number().int(),
});
export type SloDefinition = z.infer<typeof SloDefinitionSchema>;

export function parseSloDefinition(row: Record<string, unknown>): SloDefinition {
  return SloDefinitionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    serviceName: row.service_name,
    metricType: row.metric_type,
    targetValue: row.target_value,
    evaluationWindowMinutes: row.evaluation_window_minutes,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    recordVersion: row.record_version,
  });
}

export const ObservabilitySignalSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  sourceType: MonSourceTypeSchema,
  sourceReference: z.string().nullable(),
  signalType: MonSignalTypeSchema,
  value: z.number(),
  occurredAt: z.string(),
});
export type ObservabilitySignal = z.infer<typeof ObservabilitySignalSchema>;

export function parseObservabilitySignal(row: Record<string, unknown>): ObservabilitySignal {
  return ObservabilitySignalSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    sourceType: row.source_type,
    sourceReference: row.source_reference,
    signalType: row.signal_type,
    value: row.value,
    occurredAt: row.occurred_at,
  });
}

export const AlertRouteSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  sourceType: MonSourceTypeSchema,
  signalType: MonSignalTypeSchema,
  ownerTeam: z.string().nullable(),
  ownerEmail: z.string().nullable(),
  dedupeWindowMinutes: z.number().int(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type AlertRoute = z.infer<typeof AlertRouteSchema>;

export function parseAlertRoute(row: Record<string, unknown>): AlertRoute {
  return AlertRouteSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    sourceType: row.source_type,
    signalType: row.signal_type,
    ownerTeam: row.owner_team,
    ownerEmail: row.owner_email,
    dedupeWindowMinutes: row.dedupe_window_minutes,
    createdBy: row.created_by,
    createdAt: row.created_at,
  });
}

export const IncidentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  sourceType: MonSourceTypeSchema,
  signalType: MonSignalTypeSchema,
  title: z.string(),
  severity: IncidentSeveritySchema,
  status: IncidentStatusSchema,
  ownerTeam: z.string().nullable(),
  openedAt: z.string(),
  acknowledgedAt: z.string().nullable(),
  acknowledgedBy: z.string().nullable(),
  resolvedAt: z.string().nullable(),
  resolvedBy: z.string().nullable(),
  resolutionNote: z.string().nullable(),
});
export type Incident = z.infer<typeof IncidentSchema>;

export function parseIncident(row: Record<string, unknown>): Incident {
  return IncidentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    sourceType: row.source_type,
    signalType: row.signal_type,
    title: row.title,
    severity: row.severity,
    status: row.status,
    ownerTeam: row.owner_team,
    openedAt: row.opened_at,
    acknowledgedAt: row.acknowledged_at,
    acknowledgedBy: row.acknowledged_by,
    resolvedAt: row.resolved_at,
    resolvedBy: row.resolved_by,
    resolutionNote: row.resolution_note,
  });
}

export const IncidentTimelineEventSchema = z.object({
  id: z.string().uuid(),
  incidentId: z.string().uuid(),
  eventType: IncidentTimelineEventTypeSchema,
  detail: z.string().nullable(),
  occurredAt: z.string(),
});
export type IncidentTimelineEvent = z.infer<typeof IncidentTimelineEventSchema>;

export function parseIncidentTimelineEvent(row: Record<string, unknown>): IncidentTimelineEvent {
  return IncidentTimelineEventSchema.parse({
    id: row.id,
    incidentId: row.incident_id,
    eventType: row.event_type,
    detail: row.detail,
    occurredAt: row.occurred_at,
  });
}

export const SetSloDefinitionInputSchema = z.object({
  tenantId: z.string().uuid().nullable(),
  serviceName: z.string().min(1),
  metricType: MonMetricTypeSchema,
  targetValue: z.number(),
  evaluationWindowMinutes: z.number().int().min(1).max(10080),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetSloDefinitionInput = z.input<typeof SetSloDefinitionInputSchema>;

export const RecordObservabilitySignalInputSchema = z.object({
  tenantId: z.string().uuid().nullable(),
  sourceType: MonSourceTypeSchema,
  sourceReference: z.string().nullable(),
  signalType: MonSignalTypeSchema,
  value: z.number(),
});
export type RecordObservabilitySignalInput = z.input<typeof RecordObservabilitySignalInputSchema>;

export const SetAlertRouteInputSchema = z.object({
  tenantId: z.string().uuid().nullable(),
  sourceType: MonSourceTypeSchema,
  signalType: MonSignalTypeSchema,
  ownerTeam: z.string().nullable(),
  ownerEmail: z.string().nullable(),
  dedupeWindowMinutes: z.number().int().min(1).max(1440),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetAlertRouteInput = z.input<typeof SetAlertRouteInputSchema>;

export const RaiseObservabilityAlertInputSchema = z.object({
  tenantId: z.string().uuid().nullable(),
  sourceType: MonSourceTypeSchema,
  signalType: MonSignalTypeSchema,
  title: z.string().min(1),
  severity: IncidentSeveritySchema,
  detail: z.string().nullable(),
});
export type RaiseObservabilityAlertInput = z.input<typeof RaiseObservabilityAlertInputSchema>;

export const AcknowledgeIncidentInputSchema = z.object({
  incidentId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AcknowledgeIncidentInput = z.input<typeof AcknowledgeIncidentInputSchema>;

export const ResolveIncidentInputSchema = z.object({
  incidentId: z.string().uuid(),
  resolutionNote: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ResolveIncidentInput = z.input<typeof ResolveIncidentInputSchema>;
