import type {
  IntegrationAdapter,
  IntegrationConnection,
  IntegrationHealthCheck,
} from "../../../../../server/contracts/integration-hub/integration-hub.ts";

/**
 * Presentational half of the integrations console.
 *
 * This is the surface the owner asked for: a place to plug in third-party API credentials and see
 * whether each connection is actually working, so an integration is a configuration task rather
 * than a code change. The adapter catalogue, connection registry, credential store and health
 * checks all already existed (`app.integration_adapters`, `app.integration_connections`,
 * `app.integration_connection_credentials`, `app.integration_health_checks`) — with no UI.
 *
 * Read-only. Creating a connection and rotating a credential have their own audited RPCs
 * (`app.create_integration_connection`, `app.rotate_integration_connection_credential`), and
 * credential *values* are never returned by any read path — only whether one is configured. A
 * dashboard that could read back a secret would be a worse thing to have than a missing page.
 */

const CONNECTION_STATUS_STYLE: Record<string, string> = {
  active: "bg-status-success-subtle text-status-success-strong",
  testing: "bg-status-info-subtle text-status-info-strong",
  disabled: "bg-surface-muted text-text-secondary",
};

const HEALTH_STYLE: Record<string, string> = {
  healthy: "bg-status-success-subtle text-status-success-strong",
  unhealthy: "bg-status-danger-subtle text-status-danger-strong",
};

function formatTimestamp(value: string | null): string {
  if (!value) return "never";
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? value : parsed.toISOString().replace("T", " ").slice(0, 16) + " UTC";
}

export function ConnectionSummaryTiles({ connections }: { connections: IntegrationConnection[] }) {
  const active = connections.filter((c) => c.status === "active");
  const unhealthy = connections.filter((c) => c.lastHealthStatus === "unhealthy");
  const autoDisabled = connections.filter((c) => c.autoDisabledAt !== null);
  const neverChecked = connections.filter((c) => c.lastHealthCheckAt === null);

  const tiles: { label: string; value: number; tone: "danger" | "warning" | "neutral"; hint?: string }[] = [
    { label: "Connections", value: connections.length, tone: "neutral" },
    { label: "Active", value: active.length, tone: "neutral" },
    { label: "Unhealthy", value: unhealthy.length, tone: unhealthy.length > 0 ? "danger" : "neutral" },
    {
      label: "Auto-disabled",
      value: autoDisabled.length,
      tone: autoDisabled.length > 0 ? "danger" : "neutral",
      hint: autoDisabled.length > 0 ? "Turned off after repeated failures" : undefined,
    },
    {
      label: "Never health-checked",
      value: neverChecked.length,
      tone: neverChecked.length > 0 ? "warning" : "neutral",
      hint: neverChecked.length > 0 ? "Status is unknown, not good" : undefined,
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-5">
      {tiles.map((tile) => (
        <div key={tile.label} className="flex flex-col gap-1 rounded-lg border border-border-subtle bg-surface-raised p-4">
          <span className="text-xs font-medium uppercase tracking-wide text-text-secondary">{tile.label}</span>
          <span
            className={`text-2xl font-semibold tabular-nums ${
              tile.tone === "danger" ? "text-status-danger-strong" : tile.tone === "warning" ? "text-status-warning-strong" : "text-text-primary"
            }`}
          >
            {tile.value}
          </span>
          {tile.hint ? <span className="text-xs text-text-secondary">{tile.hint}</span> : null}
        </div>
      ))}
    </div>
  );
}

export function ConnectionTable({
  connections,
  healthByConnection,
}: {
  connections: IntegrationConnection[];
  healthByConnection: Map<string, IntegrationHealthCheck[]>;
}) {
  if (connections.length === 0) {
    return (
      <p className="rounded-lg border border-border-subtle bg-surface-raised p-4 text-sm text-text-secondary">
        No integration connections are configured for this tenant yet. Connections are created through the audited
        integration operations; once one exists it appears here with its health history.
      </p>
    );
  }

  // Production connections first, then anything unhealthy, so the rows that can affect real
  // customers are at the top rather than sorted by name.
  const ordered = [...connections].sort((a, b) => {
    const envDelta = Number(b.environment === "production") - Number(a.environment === "production");
    if (envDelta !== 0) return envDelta;
    const healthDelta = Number(b.lastHealthStatus === "unhealthy") - Number(a.lastHealthStatus === "unhealthy");
    if (healthDelta !== 0) return healthDelta;
    return a.name.localeCompare(b.name);
  });

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[72rem] border-collapse text-sm">
        <caption className="sr-only">Integration connections, production and unhealthy first</caption>
        <thead>
          <tr className="border-b border-border-subtle text-left text-xs uppercase tracking-wide text-text-secondary">
            <th scope="col" className="py-2 pr-4 font-medium">Name</th>
            <th scope="col" className="py-2 pr-4 font-medium">Adapter</th>
            <th scope="col" className="py-2 pr-4 font-medium">Environment</th>
            <th scope="col" className="py-2 pr-4 font-medium">Status</th>
            <th scope="col" className="py-2 pr-4 font-medium">Health</th>
            <th scope="col" className="py-2 pr-4 font-medium">Last checked</th>
            <th scope="col" className="py-2 pr-4 font-medium">Consecutive failures</th>
            <th scope="col" className="py-2 pr-4 font-medium">Owner</th>
          </tr>
        </thead>
        <tbody>
          {ordered.map((connection) => {
            const history = healthByConnection.get(connection.id) ?? [];
            return (
              <tr key={connection.id} className="border-b border-border-subtle last:border-0 align-top">
                <td className="py-2 pr-4 font-medium text-text-primary">
                  {connection.name}
                  {connection.autoDisabledAt ? (
                    <div className="mt-1 text-xs text-status-danger-strong">
                      auto-disabled {formatTimestamp(connection.autoDisabledAt)}
                      {connection.disabledReason ? ` — ${connection.disabledReason}` : ""}
                    </div>
                  ) : null}
                </td>
                <td className="py-2 pr-4 text-text-secondary">{connection.adapterCode}</td>
                <td className="py-2 pr-4">
                  <span
                    className={`inline-flex rounded px-2 py-0.5 text-xs font-medium ${
                      connection.environment === "production" ? "bg-status-warning-subtle text-status-warning-strong" : "bg-surface-muted text-text-secondary"
                    }`}
                  >
                    {connection.environment}
                  </span>
                </td>
                <td className="py-2 pr-4">
                  <span className={`inline-flex rounded px-2 py-0.5 text-xs font-medium ${CONNECTION_STATUS_STYLE[connection.status] ?? ""}`}>
                    {connection.status}
                  </span>
                </td>
                <td className="py-2 pr-4">
                  {connection.lastHealthStatus ? (
                    <span className={`inline-flex rounded px-2 py-0.5 text-xs font-medium ${HEALTH_STYLE[connection.lastHealthStatus] ?? ""}`}>
                      {connection.lastHealthStatus}
                    </span>
                  ) : (
                    <span className="text-status-warning-strong">unknown</span>
                  )}
                  {history.length > 0 ? (
                    <div className="mt-1 text-xs text-text-secondary">{history.length} checks recorded</div>
                  ) : null}
                </td>
                <td className="py-2 pr-4 tabular-nums text-text-secondary">{formatTimestamp(connection.lastHealthCheckAt)}</td>
                <td className="py-2 pr-4 tabular-nums text-text-secondary">
                  {connection.consecutiveFailureCount > 0 ? (
                    <span className="text-status-warning-strong">{connection.consecutiveFailureCount}</span>
                  ) : (
                    0
                  )}
                </td>
                <td className="py-2 pr-4 text-text-secondary">
                  {connection.ownerTeam ?? "unassigned"}
                  {connection.ownerEmail ? <div className="text-xs">{connection.ownerEmail}</div> : null}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

export function AdapterCatalogue({ adapters, connections }: { adapters: IntegrationAdapter[]; connections: IntegrationConnection[] }) {
  if (adapters.length === 0) {
    return (
      <p className="rounded-lg border border-border-subtle bg-surface-raised p-4 text-sm text-text-secondary">
        No integration adapters are registered.
      </p>
    );
  }

  const usedCodes = new Set(connections.map((c) => c.adapterCode));
  const byCategory = new Map<string, IntegrationAdapter[]>();
  for (const adapter of adapters) {
    const list = byCategory.get(adapter.category);
    if (list) list.push(adapter);
    else byCategory.set(adapter.category, [adapter]);
  }

  return (
    <div className="flex flex-col gap-4">
      <p className="text-xs text-text-secondary">
        Every provider this system can already talk to. An adapter listed here needs no new code to use — only a
        connection with its credentials.
      </p>
      {[...byCategory.entries()]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([category, list]) => (
          <div key={category} className="flex flex-col gap-2">
            <h3 className="text-sm font-semibold text-text-primary">{category}</h3>
            <ul className="flex flex-wrap gap-2">
              {list
                .slice()
                .sort((a, b) => a.name.localeCompare(b.name))
                .map((adapter) => (
                  <li
                    key={adapter.code}
                    className={`rounded border px-2 py-1 text-xs ${
                      usedCodes.has(adapter.code)
                        ? "border-status-success-subtle bg-status-success-subtle text-status-success-strong"
                        : "border-border-subtle bg-surface-raised text-text-secondary"
                    }`}
                  >
                    {adapter.name}
                    <span className="ml-1 opacity-70">({adapter.code})</span>
                    {usedCodes.has(adapter.code) ? <span className="ml-1">· connected</span> : null}
                  </li>
                ))}
            </ul>
          </div>
        ))}
    </div>
  );
}
