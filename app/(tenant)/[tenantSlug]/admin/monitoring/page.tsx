import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listIncidentsForTenant,
  listAlertRoutesForTenant,
  computeJobQueueBacklog,
  EnterpriseMonitoringQueryError,
  type EnterpriseMonitoringQueryRpcClient,
} from "../../../../../server/queries/enterprise-monitoring.ts";
import type { AlertRoute, Incident } from "../../../../../server/contracts/enterprise-monitoring/enterprise-monitoring.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { IncidentSummaryTiles, IncidentTable, AlertRouteTable } from "./monitoring-admin-panel.tsx";

/**
 * Monitoring and incident console — closes `ISS-2026-250`.
 *
 * `ISS-2026-250` (High) recorded that "no monitoring/incident dashboard UI consumes the alerting
 * backend": `server/queries/enterprise-monitoring.ts` and its RPCs existed and worked, and
 * nothing ever called them. Alerts could be raised into a store no human ever looked at, which is
 * indistinguishable from not alerting at all. This page is the missing consumer.
 *
 * It composes `app.list_incidents_for_tenant`, `app.list_alert_routes_for_tenant` and
 * `app.compute_job_queue_backlog`. Each RPC keeps its own authority check; this page's guard
 * (`resolveTenantAdminAccessForRequest`) only confirms the coarse tenant-admin portal boundary,
 * exactly as every sibling admin page does.
 *
 * **Read-only by design, not by omission.** Acknowledging and resolving incidents already have
 * audited RPCs with their own authority rules. Adding a second write path here would widen the
 * surface without adding evidence, so the page says what it does not do rather than leaving a
 * reader to infer it.
 *
 * Sections load independently (the `loadSection` pattern established by the api-keys console):
 * a failure in the backlog probe must not blank the incident list, which is the part someone
 * opens this page to see during an incident.
 */

function toQueryClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): EnterpriseMonitoringQueryRpcClient {
  return client as unknown as EnterpriseMonitoringQueryRpcClient;
}

async function loadSection<T>(promise: Promise<T>): Promise<{ readonly data: T | null; readonly failed: boolean }> {
  try {
    return { data: await promise, failed: false };
  } catch (error) {
    if (!(error instanceof EnterpriseMonitoringQueryError)) throw error;
    return { data: null, failed: true };
  }
}

/** Jobs older than this are treated as backlog. Matches the observability runbook's own threshold. */
const BACKLOG_THRESHOLD_MINUTES = 15;

export default async function MonitoringAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const client = toQueryClient(await createSupabaseServerClient());

  const [incidentsResult, routesResult, backlogResult] = await Promise.all([
    loadSection<Incident[]>(listIncidentsForTenant(client, access.tenant.id, access.authUserId)),
    loadSection<AlertRoute[]>(listAlertRoutesForTenant(client, access.tenant.id, access.authUserId)),
    loadSection<number>(computeJobQueueBacklog(client, "external_sync", BACKLOG_THRESHOLD_MINUTES, access.authUserId)),
  ]);

  const incidents = incidentsResult.data ?? [];
  const routes = routesResult.data ?? [];

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Monitoring &amp; incidents</h1>
        <p className="text-sm text-text-secondary">
          Live view of every incident the alerting backend has raised, and of the routes that decide who gets told. This
          console is <strong>read-only</strong>: acknowledging and resolving incidents go through their own audited
          operations, so nothing here can change an incident&rsquo;s state without that audit trail.
        </p>
      </div>

      {incidentsResult.failed ? (
        <ErrorState description="Something went wrong loading incidents. The alerting backend may still be recording them — do not read this as an all-clear." />
      ) : (
        <>
          <section aria-labelledby="summary-heading" className="flex flex-col gap-3">
            <h2 id="summary-heading" className="sr-only">
              Summary
            </h2>
            <IncidentSummaryTiles incidents={incidents} queueBacklog={backlogResult.failed ? null : backlogResult.data} />
          </section>

          <section aria-labelledby="incidents-heading" className="flex flex-col gap-3">
            <h2 id="incidents-heading" className="text-lg font-semibold text-text-primary">
              Incidents ({incidents.filter((i) => i.status !== "resolved").length} unresolved of {incidents.length})
            </h2>
            <IncidentTable incidents={incidents} />
          </section>
        </>
      )}

      <section aria-labelledby="routes-heading" className="flex flex-col gap-3">
        <h2 id="routes-heading" className="text-lg font-semibold text-text-primary">
          Alert routes
        </h2>
        <p className="text-xs text-text-secondary">
          A route maps a signal to the team and address notified when it fires. A signal with no route, or a route with no
          address, still raises an incident — but nobody is told about it.
        </p>
        {routesResult.failed ? (
          <ErrorState description="Something went wrong loading alert routes. Whether anyone is notified on an incident could not be confirmed from this page." />
        ) : (
          <AlertRouteTable routes={routes} />
        )}
      </section>
    </div>
  );
}
