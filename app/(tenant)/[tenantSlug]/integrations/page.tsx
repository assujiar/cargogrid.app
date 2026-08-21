import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listIntegrationAdapters, listIntegrationConnections, IntegrationHubQueryError } from "../../../../server/queries/integration-hub.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { IntegrationHubManagementPanel } from "./integration-hub-management-panel.tsx";
import { createIntegrationConnectionAction } from "./actions.ts";

/**
 * Integration Hub (IAE-008, Prompt 336 §15): the adapter catalog
 * ("marketplace") plus this tenant's own configured connections. A
 * governance layer only -- no adapter protocol is implemented here
 * (`ADR-0025` Part C).
 */
export default async function IntegrationsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let adapters: Awaited<ReturnType<typeof listIntegrationAdapters>> = [];
  let connections: Awaited<ReturnType<typeof listIntegrationConnections>> = [];
  let loadFailed = false;
  try {
    [adapters, connections] = await Promise.all([listIntegrationAdapters(supabase), listIntegrationConnections(supabase, access.tenant.id)]);
  } catch (error) {
    if (!(error instanceof IntegrationHubQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading integrations. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Integrations</h1>
        <p className="text-xs text-neutral-500">Case-by-case third-party adapters, governed centrally -- no tenant-specific fork. Credentials are stored in a fully isolated table no session can ever read directly.</p>
      </div>

      <IntegrationHubManagementPanel tenantSlug={tenantSlug} adapters={adapters} connections={connections} createAction={createIntegrationConnectionAction.bind(null, tenantSlug)} />
    </div>
  );
}
