import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listIntegrationAdapters,
  listIntegrationConnections,
  listIntegrationHealthChecks,
  IntegrationHubQueryError,
  type IntegrationHubQueryClient,
} from "../../../../../server/queries/integration-hub.ts";
import type {
  IntegrationAdapter,
  IntegrationConnection,
  IntegrationHealthCheck,
} from "../../../../../server/contracts/integration-hub/integration-hub.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { ConnectionSummaryTiles, ConnectionTable, AdapterCatalogue } from "./integrations-admin-panel.tsx";

/**
 * Integrations and API console.
 *
 * The Integration Hub already had everything except a way to look at it: `app.integration_adapters`
 * (the catalogue of providers this system can talk to), `app.integration_connections` (a tenant's
 * configured connections), `app.integration_connection_credentials` (encrypted at rest), and
 * `app.integration_health_checks`. Nothing rendered any of it, so "is our carrier API actually
 * working?" had no answer short of querying the database.
 *
 * With this console, adding a third-party provider is a configuration task — pick an adapter that
 * already exists, record a connection and its credentials — rather than a code change.
 *
 * **Read-only, and deliberately so on one specific point:** credential *values* are never returned
 * by any read path here, only whether a connection exists and whether it is healthy. A dashboard
 * that could read back a secret would be a worse thing to have than a missing page. Creating a
 * connection and rotating a credential go through `app.create_integration_connection` and
 * `app.rotate_integration_connection_credential`, which carry their own authority checks and audit
 * trail.
 *
 * Sections load independently: a health-history read failing for one connection must not blank the
 * connection list.
 */

function toQueryClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): IntegrationHubQueryClient {
  return client as unknown as IntegrationHubQueryClient;
}

async function loadSection<T>(promise: Promise<T>): Promise<{ readonly data: T | null; readonly failed: boolean }> {
  try {
    return { data: await promise, failed: false };
  } catch (error) {
    if (!(error instanceof IntegrationHubQueryError)) throw error;
    return { data: null, failed: true };
  }
}

export default async function IntegrationsAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const client = toQueryClient(await createSupabaseServerClient());

  const [adaptersResult, connectionsResult] = await Promise.all([
    loadSection<IntegrationAdapter[]>(listIntegrationAdapters(client)),
    loadSection<IntegrationConnection[]>(listIntegrationConnections(client, access.tenant.id)),
  ]);

  const adapters = adaptersResult.data ?? [];
  const connections = connectionsResult.data ?? [];

  // Health history per connection. A failure here degrades only the "N checks recorded" hint —
  // the connection's own last-known health comes from the connection row itself.
  const healthByConnection = new Map<string, IntegrationHealthCheck[]>();
  const histories = await Promise.all(
    connections.map((connection) =>
      loadSection<IntegrationHealthCheck[]>(listIntegrationHealthChecks(client, connection.id, 25)).then((result) => ({
        connectionId: connection.id,
        checks: result.data ?? [],
      })),
    ),
  );
  for (const { connectionId, checks } of histories) {
    healthByConnection.set(connectionId, checks);
  }

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Integrations &amp; API</h1>
        <p className="text-sm text-text-secondary">
          Third-party connections and their health. Adding a provider that already has an adapter needs no code change —
          only a connection and its credentials. This console is <strong>read-only</strong>, and credential values are
          never shown: you can see that a connection is configured and whether it is working, never the secret itself.
        </p>
      </div>

      {connectionsResult.failed ? (
        <ErrorState description="Something went wrong loading integration connections. Do not read this as confirmation that the integrations are healthy." />
      ) : (
        <>
          <section aria-labelledby="summary-heading" className="flex flex-col gap-3">
            <h2 id="summary-heading" className="sr-only">
              Summary
            </h2>
            <ConnectionSummaryTiles connections={connections} />
          </section>

          <section aria-labelledby="connections-heading" className="flex flex-col gap-3">
            <h2 id="connections-heading" className="text-lg font-semibold text-text-primary">
              Connections ({connections.length})
            </h2>
            <p className="text-xs text-text-secondary">
              Production connections and unhealthy ones are listed first. A connection that has never been health-checked
              shows as <strong>unknown</strong> rather than healthy — an unverified integration is not a working one.
            </p>
            <ConnectionTable connections={connections} healthByConnection={healthByConnection} />
          </section>
        </>
      )}

      <section aria-labelledby="adapters-heading" className="flex flex-col gap-3">
        <h2 id="adapters-heading" className="text-lg font-semibold text-text-primary">
          Available adapters ({adapters.length})
        </h2>
        {adaptersResult.failed ? (
          <ErrorState description="Something went wrong loading the adapter catalogue." />
        ) : (
          <AdapterCatalogue adapters={adapters} connections={connections} />
        )}
      </section>
    </div>
  );
}
