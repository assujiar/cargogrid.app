/**
 * Enterprise Monitoring and Observability read queries (IAE-030, Prompt 358).
 * Thin, typed wrappers around app.list_incidents_for_tenant /
 * app.get_incident_timeline / app.list_alert_routes_for_tenant /
 * app.compute_job_queue_backlog
 * (supabase/migrations/20260807400000_create_intelligence_enterprise_monitoring_observability.sql).
 */

import { parseIncident, parseAlertRoute, parseIncidentTimelineEvent, type Incident, type AlertRoute, type IncidentTimelineEvent } from "../contracts/enterprise-monitoring/enterprise-monitoring.ts";

export interface EnterpriseMonitoringQueryRpcClient {
  rpc(
    fn: "list_incidents_for_tenant" | "get_incident_timeline" | "list_alert_routes_for_tenant" | "compute_job_queue_backlog",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class EnterpriseMonitoringQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EnterpriseMonitoringQueryError";
  }
}

function asRows(data: unknown): Record<string, unknown>[] {
  if (!data) {
    return [];
  }
  return Array.isArray(data) ? (data as Record<string, unknown>[]) : [data as Record<string, unknown>];
}

/** Authority: MON:View in tenantId, or Supreme Admin when tenantId is null (a platform-wide listing). */
export async function listIncidentsForTenant(client: EnterpriseMonitoringQueryRpcClient, tenantId: string | null, actorAuthUserId: string): Promise<Incident[]> {
  const { data, error } = await client.rpc("list_incidents_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new EnterpriseMonitoringQueryError(error.message);
  }
  return asRows(data).map(parseIncident);
}

/** Authority: MON:View against the incident's own tenant (or Supreme Admin for a platform-wide incident). Chronological, oldest first. */
export async function getIncidentTimeline(client: EnterpriseMonitoringQueryRpcClient, incidentId: string, actorAuthUserId: string): Promise<IncidentTimelineEvent[]> {
  const { data, error } = await client.rpc("get_incident_timeline", { p_incident_id: incidentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new EnterpriseMonitoringQueryError(error.message);
  }
  return asRows(data).map(parseIncidentTimelineEvent);
}

/** Authority: same as listIncidentsForTenant. */
export async function listAlertRoutesForTenant(client: EnterpriseMonitoringQueryRpcClient, tenantId: string | null, actorAuthUserId: string): Promise<AlertRoute[]> {
  const { data, error } = await client.rpc("list_alert_routes_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new EnterpriseMonitoringQueryError(error.message);
  }
  return asRows(data).map(parseAlertRoute);
}

/** Authority: Supreme Admin only -- app.jobs is not tenant-scoped in this reading (a job_type's backlog spans every tenant's own queued work), so this is a genuinely platform-wide metric. */
export async function computeJobQueueBacklog(client: EnterpriseMonitoringQueryRpcClient, jobType: string, olderThanMinutes: number, actorAuthUserId: string): Promise<number> {
  const { data, error } = await client.rpc("compute_job_queue_backlog", { p_job_type: jobType, p_older_than_minutes: olderThanMinutes, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new EnterpriseMonitoringQueryError(error.message);
  }
  if (typeof data !== "number") {
    throw new EnterpriseMonitoringQueryError("compute_job_queue_backlog returned a non-numeric result");
  }
  return data;
}
