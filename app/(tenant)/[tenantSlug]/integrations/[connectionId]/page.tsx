import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { getIntegrationConnectionById, listIntegrationHealthChecks, listIntegrationAdapters, IntegrationHubQueryError } from "../../../../../server/queries/integration-hub.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { IntegrationConnectionDetailPanel } from "./integration-connection-detail-panel.tsx";
import {
  updateIntegrationConnectionConfigAction,
  rotateIntegrationConnectionCredentialAction,
  setIntegrationConnectionStatusAction,
  recordIntegrationHealthCheckAction,
} from "../actions.ts";

/**
 * Integration connection detail page (IAE-008, Prompt 336): non-secret
 * config/owner/runbook editing, credential rotation (write-only -- the
 * current value is never displayed, it cannot be read back), enable/
 * disable/test-mode controls, a "test connection" health-check action, and
 * the real health-check history.
 */
export default async function IntegrationConnectionDetailPage({ params }: { params: Promise<{ tenantSlug: string; connectionId: string }> }) {
  const { tenantSlug, connectionId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  type Loaded = {
    connection: NonNullable<Awaited<ReturnType<typeof getIntegrationConnectionById>>>;
    healthChecks: Awaited<ReturnType<typeof listIntegrationHealthChecks>>;
    adapterName: string;
  };

  let loaded: Loaded | null = null;
  let loadFailed = false;
  try {
    const connection = await getIntegrationConnectionById(supabase, connectionId);
    if (!connection) {
      notFound();
    }
    const [healthChecks, adapters] = await Promise.all([listIntegrationHealthChecks(supabase, connectionId), listIntegrationAdapters(supabase)]);
    loaded = { connection, healthChecks, adapterName: adapters.find((a) => a.code === connection.adapterCode)?.name ?? connection.adapterCode };
  } catch (error) {
    if (!(error instanceof IntegrationHubQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed || !loaded) {
    return <ErrorState description="Something went wrong loading this integration connection. Please try again." />;
  }

  const { connection, healthChecks, adapterName } = loaded;

  return (
    <IntegrationConnectionDetailPanel
      connection={connection}
      adapterName={adapterName}
      healthChecks={healthChecks}
      updateConfigAction={updateIntegrationConnectionConfigAction.bind(null, tenantSlug, connectionId)}
      rotateCredentialAction={rotateIntegrationConnectionCredentialAction.bind(null, tenantSlug, connectionId)}
      setStatusActionFor={(status) => setIntegrationConnectionStatusAction.bind(null, tenantSlug, connectionId, status)}
      recordHealthCheckActionFor={(status) => recordIntegrationHealthCheckAction.bind(null, tenantSlug, connectionId, status)}
    />
  );
}
