import type { ReactNode } from "react";
import type { AlertRoute, Incident, IncidentSeverity, IncidentStatus } from "../../../../../server/contracts/enterprise-monitoring/enterprise-monitoring.ts";

/**
 * Presentational half of the monitoring and incident console (`ISS-2026-250`).
 *
 * Deliberately server-rendered with no client interactivity: this console's job is to make the
 * alerting backend *visible*, which is the gap `ISS-2026-250` records. Acknowledging and
 * resolving incidents already have their own audited RPCs with their own authority checks; adding
 * a second, weaker write path from a dashboard would widen the surface without adding evidence.
 * Read-only is the honest scope, and it is stated on the page rather than left to be discovered.
 */

const SEVERITY_ORDER: Record<IncidentSeverity, number> = { critical: 0, high: 1, medium: 2, low: 3 };

/** Severity styling. Critical and high are visually distinct, not merely differently worded. */
const SEVERITY_STYLE: Record<IncidentSeverity, string> = {
  critical: "bg-status-danger-subtle text-status-danger-strong",
  high: "bg-status-warning-subtle text-status-warning-strong",
  medium: "bg-status-info-subtle text-status-info-strong",
  low: "bg-surface-muted text-text-secondary",
};

const STATUS_LABEL: Record<IncidentStatus, string> = {
  open: "Open",
  acknowledged: "Acknowledged",
  resolved: "Resolved",
};

function formatTimestamp(value: string | null): string {
  if (!value) return "—";
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? value : parsed.toISOString().replace("T", " ").slice(0, 16) + " UTC";
}

/** Whole hours/minutes since a timestamp, for "how long has this been open". */
function formatAge(from: string): string {
  const started = new Date(from).getTime();
  if (Number.isNaN(started)) return "—";
  const minutes = Math.max(0, Math.floor((Date.now() - started) / 60000));
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ${minutes % 60}m`;
  return `${Math.floor(hours / 24)}d ${hours % 24}h`;
}

function Tile({ label, value, tone, hint }: { label: string; value: ReactNode; tone?: "danger" | "warning" | "neutral"; hint?: string }) {
  const toneClass =
    tone === "danger" ? "text-status-danger-strong" : tone === "warning" ? "text-status-warning-strong" : "text-text-primary";
  return (
    <div className="flex flex-col gap-1 rounded-lg border border-border-subtle bg-surface-raised p-4">
      <span className="text-xs font-medium uppercase tracking-wide text-text-secondary">{label}</span>
      <span className={`text-2xl font-semibold tabular-nums ${toneClass}`}>{value}</span>
      {hint ? <span className="text-xs text-text-secondary">{hint}</span> : null}
    </div>
  );
}

export function IncidentSummaryTiles({ incidents, queueBacklog }: { incidents: Incident[]; queueBacklog: number | null }) {
  const unresolved = incidents.filter((i) => i.status !== "resolved");
  const critical = unresolved.filter((i) => i.severity === "critical").length;
  const high = unresolved.filter((i) => i.severity === "high").length;
  const unacknowledged = unresolved.filter((i) => i.status === "open").length;

  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <Tile label="Unresolved" value={unresolved.length} tone={unresolved.length > 0 ? "warning" : "neutral"} />
      <Tile label="Critical open" value={critical} tone={critical > 0 ? "danger" : "neutral"} hint={critical > 0 ? "Needs an owner now" : "None"} />
      <Tile label="High open" value={high} tone={high > 0 ? "warning" : "neutral"} />
      <Tile
        label="Unacknowledged"
        value={unacknowledged}
        tone={unacknowledged > 0 ? "warning" : "neutral"}
        hint="Opened, nobody has picked it up"
      />
      <Tile
        label="Job queue backlog"
        value={queueBacklog === null ? "unavailable" : queueBacklog}
        tone={queueBacklog !== null && queueBacklog > 0 ? "warning" : "neutral"}
        hint={queueBacklog === null ? "Backlog probe did not return" : "Jobs older than 15 minutes"}
      />
    </div>
  );
}

export function IncidentTable({ incidents }: { incidents: Incident[] }) {
  if (incidents.length === 0) {
    return (
      <p className="rounded-lg border border-border-subtle bg-surface-raised p-4 text-sm text-text-secondary">
        No incidents recorded. This means the alerting backend has raised none — not that monitoring is switched off.
      </p>
    );
  }

  // Unresolved first, then by severity, then oldest first: the thing that has been broken
  // longest and matters most sits at the top.
  const ordered = [...incidents].sort((a, b) => {
    const resolvedDelta = Number(a.status === "resolved") - Number(b.status === "resolved");
    if (resolvedDelta !== 0) return resolvedDelta;
    const severityDelta = SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity];
    if (severityDelta !== 0) return severityDelta;
    return new Date(a.openedAt).getTime() - new Date(b.openedAt).getTime();
  });

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[64rem] border-collapse text-sm">
        <caption className="sr-only">Incidents raised by the alerting backend, unresolved first</caption>
        <thead>
          <tr className="border-b border-border-subtle text-left text-xs uppercase tracking-wide text-text-secondary">
            <th scope="col" className="py-2 pr-4 font-medium">Severity</th>
            <th scope="col" className="py-2 pr-4 font-medium">Title</th>
            <th scope="col" className="py-2 pr-4 font-medium">Source / signal</th>
            <th scope="col" className="py-2 pr-4 font-medium">Status</th>
            <th scope="col" className="py-2 pr-4 font-medium">Owner team</th>
            <th scope="col" className="py-2 pr-4 font-medium">Opened</th>
            <th scope="col" className="py-2 pr-4 font-medium">Age</th>
          </tr>
        </thead>
        <tbody>
          {ordered.map((incident) => (
            <tr key={incident.id} className="border-b border-border-subtle last:border-0">
              <td className="py-2 pr-4">
                <span className={`inline-flex rounded px-2 py-0.5 text-xs font-medium ${SEVERITY_STYLE[incident.severity]}`}>
                  {incident.severity}
                </span>
              </td>
              <td className="py-2 pr-4 text-text-primary">{incident.title}</td>
              <td className="py-2 pr-4 text-text-secondary">
                {incident.sourceType} / {incident.signalType}
              </td>
              <td className="py-2 pr-4 text-text-secondary">{STATUS_LABEL[incident.status]}</td>
              <td className="py-2 pr-4 text-text-secondary">{incident.ownerTeam ?? "unassigned"}</td>
              <td className="py-2 pr-4 tabular-nums text-text-secondary">{formatTimestamp(incident.openedAt)}</td>
              <td className="py-2 pr-4 tabular-nums text-text-secondary">
                {incident.status === "resolved" ? "—" : formatAge(incident.openedAt)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function AlertRouteTable({ routes }: { routes: AlertRoute[] }) {
  if (routes.length === 0) {
    return (
      <p className="rounded-lg border border-status-warning-subtle bg-status-warning-subtle p-4 text-sm text-status-warning-strong">
        <strong>No alert routes are configured.</strong> Signals can still raise incidents, but nobody is notified when they
        do — an incident would only be seen by someone who opens this page. Configure at least one route with an owner team
        and address.
      </p>
    );
  }

  // A route with no owner email notifies nobody. Surfacing that is the whole point of the table.
  const unroutable = routes.filter((r) => !r.ownerEmail).length;

  return (
    <div className="flex flex-col gap-2">
      {unroutable > 0 ? (
        <p className="rounded-lg border border-status-warning-subtle bg-status-warning-subtle p-3 text-sm text-status-warning-strong">
          {unroutable} of {routes.length} routes have no owner address — those signals raise an incident but notify nobody.
        </p>
      ) : null}
      <div className="overflow-x-auto">
        <table className="w-full min-w-[52rem] border-collapse text-sm">
          <caption className="sr-only">Configured alert routes</caption>
          <thead>
            <tr className="border-b border-border-subtle text-left text-xs uppercase tracking-wide text-text-secondary">
              <th scope="col" className="py-2 pr-4 font-medium">Source</th>
              <th scope="col" className="py-2 pr-4 font-medium">Signal</th>
              <th scope="col" className="py-2 pr-4 font-medium">Owner team</th>
              <th scope="col" className="py-2 pr-4 font-medium">Notifies</th>
              <th scope="col" className="py-2 pr-4 font-medium">Dedupe window</th>
            </tr>
          </thead>
          <tbody>
            {routes.map((route) => (
              <tr key={route.id} className="border-b border-border-subtle last:border-0">
                <td className="py-2 pr-4 text-text-primary">{route.sourceType}</td>
                <td className="py-2 pr-4 text-text-secondary">{route.signalType}</td>
                <td className="py-2 pr-4 text-text-secondary">{route.ownerTeam ?? "unassigned"}</td>
                <td className="py-2 pr-4 text-text-secondary">
                  {route.ownerEmail ?? <span className="text-status-warning-strong">nobody</span>}
                </td>
                <td className="py-2 pr-4 tabular-nums text-text-secondary">{route.dedupeWindowMinutes}m</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
