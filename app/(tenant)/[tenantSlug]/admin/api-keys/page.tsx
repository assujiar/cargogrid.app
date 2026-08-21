import { notFound } from "next/navigation";
import type { ReactNode } from "react";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listApiKeysForTenant, listWebhookEndpointsForTenant, ApiKeyWebhookQueryError, type ApiKeyWebhookQueryRpcClient } from "../../../../../server/queries/api-key-webhook.ts";
import { listApiVersions, listWebhookEventTypes, listApiLogsForTenant, PublicApiPlatformQueryError, type PublicApiPlatformQueryRpcClient } from "../../../../../server/queries/public-api-platform.ts";
import { listVendorApiKeysForTenant, VendorApiQueryError, type VendorApiQueryRpcClient } from "../../../../../server/queries/vendor-api.ts";
import { listWebhookDeliveriesForTenant, WebhookManagementQueryError, type WebhookManagementQueryRpcClient } from "../../../../../server/queries/webhook-management.ts";
import { listN8nConnectorsForTenant, listN8nActionAllowlist, N8nIntegrationQueryError, type N8nIntegrationQueryRpcClient } from "../../../../../server/queries/n8n-integration.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { CreateApiKeyForm, ApiKeyList, ApiVersionList, WebhookEventTypeList, ApiLogList, CreateVendorApiKeyForm, VendorApiKeyList, RegisterWebhookEndpointForm, WebhookEndpointList, WebhookDeliveryList, CreateN8nConnectorForm, N8nConnectorList } from "./api-keys-admin-panel.tsx";

/**
 * `SupabaseClient.rpc()` returns a `PostgrestFilterBuilder` (thenable, but not
 * structurally a `Promise`), so it never satisfies a narrow `Promise<{data,error}>`-
 * returning RPC client interface by direct structural assignment -- the same cast
 * `app/(tenant)/[tenantSlug]/procurement/compliance/vendors/actions.ts`'s own
 * `toDocumentClient()` already established for this exact class of mismatch.
 */
function toQueryClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): ApiKeyWebhookQueryRpcClient & PublicApiPlatformQueryRpcClient & VendorApiQueryRpcClient & WebhookManagementQueryRpcClient & N8nIntegrationQueryRpcClient {
  return client as unknown as ApiKeyWebhookQueryRpcClient & PublicApiPlatformQueryRpcClient & VendorApiQueryRpcClient & WebhookManagementQueryRpcClient & N8nIntegrationQueryRpcClient;
}

function isKnownApiKeysConsoleQueryError(error: unknown): boolean {
  return (
    error instanceof ApiKeyWebhookQueryError ||
    error instanceof PublicApiPlatformQueryError ||
    error instanceof VendorApiQueryError ||
    error instanceof WebhookManagementQueryError ||
    error instanceof N8nIntegrationQueryError
  );
}

/**
 * Tier C Batch 3 fix: this page renders nine independent sections spanning
 * five capabilities. The original single `Promise.all` + one shared
 * `loadFailed` boolean meant a transient failure in ANY ONE query (e.g. API
 * request-log pagination) blanked the entire page, including the eight
 * sections that loaded fine. Each query is now isolated -- a genuinely
 * unexpected error still re-throws (Next.js's own error boundary), but a
 * known `*QueryError` degrades ONLY its own section.
 */
async function loadSection<T>(promise: Promise<T>): Promise<{ readonly data: T | null; readonly failed: boolean }> {
  try {
    return { data: await promise, failed: false };
  } catch (error) {
    if (!isKnownApiKeysConsoleQueryError(error)) throw error;
    return { data: null, failed: true };
  }
}

function Section({ id, title, description, failed, children }: { id: string; title: string; description?: string; failed: boolean; children: ReactNode }) {
  return (
    <section aria-labelledby={`${id}-heading`} className="flex flex-col gap-2">
      <h2 id={`${id}-heading`} className="text-sm font-semibold text-text-primary">
        {title}
      </h2>
      {description ? <p className="text-xs text-text-secondary">{description}</p> : null}
      {failed ? <ErrorState description="Something went wrong loading this section. Please try again." /> : children}
    </section>
  );
}

/**
 * Public API Platform developer console (IAE-009, Prompt 337): keys/scopes, rate
 * usage/limit, API version/deprecation notices, the webhook event-type catalog, and
 * recent request audit -- all gated by resolveTenantAdminAccessForRequest (a coarse
 * tenant_admin portal-entry check); each underlying RPC still enforces its own
 * Supreme-or-tenant_admin authority independently (app.check_api_webhook_admin_authority,
 * PLT-129).
 */
export default async function ApiKeysAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = toQueryClient(await createSupabaseServerClient());

  const [keysResult, versionsResult, eventTypesResult, logsResult, vendorKeysResult, endpointsResult, deliveriesResult, connectorsResult, n8nAllowlistResult] = await Promise.all([
    loadSection(listApiKeysForTenant(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId })),
    loadSection(listApiVersions(supabase)),
    loadSection(listWebhookEventTypes(supabase)),
    loadSection(listApiLogsForTenant(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId, limit: 20, before: null })),
    loadSection(listVendorApiKeysForTenant(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId })),
    loadSection(listWebhookEndpointsForTenant(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId })),
    loadSection(listWebhookDeliveriesForTenant(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId })),
    loadSection(listN8nConnectorsForTenant(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId })),
    loadSection(listN8nActionAllowlist(supabase)),
  ]);

  const keys = keysResult.data ?? [];
  const versions = versionsResult.data ?? [];
  const eventTypes = eventTypesResult.data ?? [];
  const logs = logsResult.data ?? [];
  const vendorKeys = vendorKeysResult.data ?? [];
  const endpoints = endpointsResult.data ?? [];
  const deliveries = deliveriesResult.data ?? [];
  const connectors = connectorsResult.data ?? [];
  const n8nAllowlist = n8nAllowlistResult.data ?? [];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">API Keys</h1>
        <p className="text-sm text-text-secondary">Public API developer console -- scoped keys, rate limits, versioning and deprecation notices, the webhook event catalog, and recent request activity for /api/v1.</p>
      </div>

      <CreateApiKeyForm tenantSlug={tenantSlug} />

      <Section id="keys" title="Your API keys" failed={keysResult.failed}>
        <ApiKeyList tenantSlug={tenantSlug} keys={keys} />
      </Section>

      <CreateVendorApiKeyForm tenantSlug={tenantSlug} />

      <Section id="vendor-keys" title="Vendor API keys" failed={vendorKeysResult.failed}>
        <VendorApiKeyList tenantSlug={tenantSlug} keys={vendorKeys} />
      </Section>

      <Section id="versions" title="API versions" failed={versionsResult.failed}>
        <ApiVersionList versions={versions} />
      </Section>

      <Section id="event-types" title="Webhook event types" failed={eventTypesResult.failed}>
        <WebhookEventTypeList eventTypes={eventTypes} />
      </Section>

      <RegisterWebhookEndpointForm tenantSlug={tenantSlug} />

      <Section id="endpoints" title="Webhook endpoints" failed={endpointsResult.failed}>
        <WebhookEndpointList tenantSlug={tenantSlug} endpoints={endpoints} />
      </Section>

      <Section
        id="deliveries"
        title="Webhook deliveries"
        description="Most recent deliveries across every endpoint, including dead-lettered ones. A dead-lettered delivery may be replayed once its receiving endpoint is fixed."
        failed={deliveriesResult.failed}
      >
        <WebhookDeliveryList tenantSlug={tenantSlug} deliveries={deliveries} />
      </Section>

      <CreateN8nConnectorForm tenantSlug={tenantSlug} allowlist={n8nAllowlist} />

      <Section
        id="n8n"
        title="n8n connectors"
        description="n8n calls the SAME /api/v1 API and receives events through the SAME webhook endpoints as any other integration. Register a webhook endpoint above pointed at your n8n workflow's own webhook trigger URL to receive events, and use this connector's key as a Bearer token in your workflow's HTTP Request node to call /api/v1."
        failed={connectorsResult.failed}
      >
        <N8nConnectorList tenantSlug={tenantSlug} connectors={connectors} />
      </Section>

      <Section id="logs" title="Recent API requests" failed={logsResult.failed}>
        <ApiLogList logs={logs} />
      </Section>
    </div>
  );
}
