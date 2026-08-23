/**
 * Enterprise Monitoring and Observability mutation primitives (IAE-030,
 * Prompt 358). Thin, typed wrappers around app.set_slo_definition /
 * app.record_observability_signal / app.set_alert_route /
 * app.raise_observability_alert / app.acknowledge_incident /
 * app.resolve_incident
 * (supabase/migrations/20260807400000_create_intelligence_enterprise_monitoring_observability.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  SetSloDefinitionInputSchema,
  RecordObservabilitySignalInputSchema,
  SetAlertRouteInputSchema,
  RaiseObservabilityAlertInputSchema,
  AcknowledgeIncidentInputSchema,
  ResolveIncidentInputSchema,
  parseSloDefinition,
  parseObservabilitySignal,
  parseAlertRoute,
  parseIncident,
  type SetSloDefinitionInput,
  type RecordObservabilitySignalInput,
  type SetAlertRouteInput,
  type RaiseObservabilityAlertInput,
  type AcknowledgeIncidentInput,
  type ResolveIncidentInput,
  type SloDefinition,
  type ObservabilitySignal,
  type AlertRoute,
  type Incident,
} from "../contracts/enterprise-monitoring/enterprise-monitoring.ts";

export type EnterpriseMonitoringMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ENTERPRISE_MONITORING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "slo_invalid_metric_type",
  "slo_invalid_window",
  "observability_signal_invalid_source_type",
  "observability_signal_invalid_signal_type",
  "alert_route_invalid_dedupe_window",
  "incident_invalid_severity",
  "incident_not_open",
] as const;
type KnownEnterpriseMonitoringMutationErrorCode = (typeof ENTERPRISE_MONITORING_KNOWN_MUTATION_ERROR_CODES)[number];
export type EnterpriseMonitoringMutationErrorCode = KnownEnterpriseMonitoringMutationErrorCode | "mutation_failed" | "invalid_response";

export class EnterpriseMonitoringMutationError extends Error {
  readonly code: EnterpriseMonitoringMutationErrorCode;

  constructor(code: EnterpriseMonitoringMutationErrorCode, message: string) {
    super(message);
    this.name = "EnterpriseMonitoringMutationError";
    this.code = code;
  }
}

function classifyError(message: string): EnterpriseMonitoringMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ENTERPRISE_MONITORING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownEnterpriseMonitoringMutationErrorCode)
    : "mutation_failed";
}

export async function setSloDefinition(client: EnterpriseMonitoringMutationRpcClient, input: SetSloDefinitionInput): Promise<SloDefinition> {
  const parsedInput = SetSloDefinitionInputSchema.parse(input);
  const { data, error } = await client.rpc("set_slo_definition", {
    p_tenant_id: parsedInput.tenantId,
    p_service_name: parsedInput.serviceName,
    p_metric_type: parsedInput.metricType,
    p_target_value: parsedInput.targetValue,
    p_evaluation_window_minutes: parsedInput.evaluationWindowMinutes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseMonitoringMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMonitoringMutationError("invalid_response", "set_slo_definition returned no row");
  }
  return parseSloDefinition(data as Record<string, unknown>);
}

/** service_role-only -- a system-to-system telemetry write, mirroring app.capture_audit_event's own "trusts its caller" shape. */
export async function recordObservabilitySignal(client: EnterpriseMonitoringMutationRpcClient, input: RecordObservabilitySignalInput): Promise<ObservabilitySignal> {
  const parsedInput = RecordObservabilitySignalInputSchema.parse(input);
  const { data, error } = await client.rpc("record_observability_signal", {
    p_tenant_id: parsedInput.tenantId,
    p_source_type: parsedInput.sourceType,
    p_source_reference: parsedInput.sourceReference,
    p_signal_type: parsedInput.signalType,
    p_value: parsedInput.value,
  });
  if (error) {
    throw new EnterpriseMonitoringMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMonitoringMutationError("invalid_response", "record_observability_signal returned no row");
  }
  return parseObservabilitySignal(data as Record<string, unknown>);
}

export async function setAlertRoute(client: EnterpriseMonitoringMutationRpcClient, input: SetAlertRouteInput): Promise<AlertRoute> {
  const parsedInput = SetAlertRouteInputSchema.parse(input);
  const { data, error } = await client.rpc("set_alert_route", {
    p_tenant_id: parsedInput.tenantId,
    p_source_type: parsedInput.sourceType,
    p_signal_type: parsedInput.signalType,
    p_owner_team: parsedInput.ownerTeam,
    p_owner_email: parsedInput.ownerEmail,
    p_dedupe_window_minutes: parsedInput.dedupeWindowMinutes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseMonitoringMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMonitoringMutationError("invalid_response", "set_alert_route returned no row");
  }
  return parseAlertRoute(data as Record<string, unknown>);
}

/** service_role-only -- real deduplication against the matching route's own dedupe_window_minutes (falls back to a disclosed 30-minute default with no matching route). */
export async function raiseObservabilityAlert(client: EnterpriseMonitoringMutationRpcClient, input: RaiseObservabilityAlertInput): Promise<Incident> {
  const parsedInput = RaiseObservabilityAlertInputSchema.parse(input);
  const { data, error } = await client.rpc("raise_observability_alert", {
    p_tenant_id: parsedInput.tenantId,
    p_source_type: parsedInput.sourceType,
    p_signal_type: parsedInput.signalType,
    p_title: parsedInput.title,
    p_severity: parsedInput.severity,
    p_detail: parsedInput.detail,
  });
  if (error) {
    throw new EnterpriseMonitoringMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMonitoringMutationError("invalid_response", "raise_observability_alert returned no row");
  }
  return parseIncident(data as Record<string, unknown>);
}

export async function acknowledgeIncident(client: EnterpriseMonitoringMutationRpcClient, input: AcknowledgeIncidentInput): Promise<Incident> {
  const parsedInput = AcknowledgeIncidentInputSchema.parse(input);
  const { data, error } = await client.rpc("acknowledge_incident", {
    p_incident_id: parsedInput.incidentId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseMonitoringMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMonitoringMutationError("invalid_response", "acknowledge_incident returned no row");
  }
  return parseIncident(data as Record<string, unknown>);
}

export async function resolveIncident(client: EnterpriseMonitoringMutationRpcClient, input: ResolveIncidentInput): Promise<Incident> {
  const parsedInput = ResolveIncidentInputSchema.parse(input);
  const { data, error } = await client.rpc("resolve_incident", {
    p_incident_id: parsedInput.incidentId,
    p_resolution_note: parsedInput.resolutionNote,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new EnterpriseMonitoringMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMonitoringMutationError("invalid_response", "resolve_incident returned no row");
  }
  return parseIncident(data as Record<string, unknown>);
}
