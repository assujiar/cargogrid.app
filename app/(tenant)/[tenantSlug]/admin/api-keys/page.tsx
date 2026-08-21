import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listApiKeysForTenant, ApiKeyWebhookQueryError, type ApiKeyWebhookQueryRpcClient } from "../../../../../server/queries/api-key-webhook.ts";
import { listApiVersions, listWebhookEventTypes, listApiLogsForTenant, PublicApiPlatformQueryError, type PublicApiPlatformQueryRpcClient } from "../../../../../server/queries/public-api-platform.ts";
import { listVendorApiKeysForTenant, VendorApiQueryError, type VendorApiQueryRpcClient } from "../../../../../server/queries/vendor-api.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { CreateApiKeyForm, ApiKeyList, ApiVersionList, WebhookEventTypeList, ApiLogList, CreateVendorApiKeyForm, VendorApiKeyList } from "./api-keys-admin-panel.tsx";

/**
 * `SupabaseClient.rpc()` returns a `PostgrestFilterBuilder` (thenable, but not
 * structurally a `Promise`), so it never satisfies a narrow `Promise<{data,error}>`-
 * returning RPC client interface by direct structural assignment -- the same cast
 * `app/(tenant)/[tenantSlug]/procurement/compliance/vendors/actions.ts`'s own
 * `toDocumentClient()` already established for this exact class of mismatch.
 */
function toQueryClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): ApiKeyWebhookQueryRpcClient & PublicApiPlatformQueryRpcClient & VendorApiQueryRpcClient {
  return client as unknown as ApiKeyWebhookQueryRpcClient & PublicApiPlatformQueryRpcClient & VendorApiQueryRpcClient;
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
  let loadFailed = false;
  let keys: Awaited<ReturnType<typeof listApiKeysForTenant>> = [];
  let versions: Awaited<ReturnType<typeof listApiVersions>> = [];
  let eventTypes: Awaited<ReturnType<typeof listWebhookEventTypes>> = [];
  let logs: Awaited<ReturnType<typeof listApiLogsForTenant>> = [];
  let vendorKeys: Awaited<ReturnType<typeof listVendorApiKeysForTenant>> = [];

  try {
    [keys, versions, eventTypes, logs, vendorKeys] = await Promise.all([
      listApiKeysForTenant(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId }),
      listApiVersions(supabase),
      listWebhookEventTypes(supabase),
      listApiLogsForTenant(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId, limit: 20, before: null }),
      listVendorApiKeysForTenant(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId }),
    ]);
  } catch (error) {
    if (!(error instanceof ApiKeyWebhookQueryError) && !(error instanceof PublicApiPlatformQueryError) && !(error instanceof VendorApiQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-text-primary">API Keys</h1>
        <ErrorState description="Something went wrong loading your API platform data. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">API Keys</h1>
        <p className="text-sm text-text-secondary">Public API developer console -- scoped keys, rate limits, versioning and deprecation notices, the webhook event catalog, and recent request activity for /api/v1.</p>
      </div>

      <CreateApiKeyForm tenantSlug={tenantSlug} />

      <section aria-labelledby="keys-heading" className="flex flex-col gap-2">
        <h2 id="keys-heading" className="text-sm font-semibold text-text-primary">
          Your API keys
        </h2>
        <ApiKeyList tenantSlug={tenantSlug} keys={keys} />
      </section>

      <CreateVendorApiKeyForm tenantSlug={tenantSlug} />

      <section aria-labelledby="vendor-keys-heading" className="flex flex-col gap-2">
        <h2 id="vendor-keys-heading" className="text-sm font-semibold text-text-primary">
          Vendor API keys
        </h2>
        <VendorApiKeyList tenantSlug={tenantSlug} keys={vendorKeys} />
      </section>

      <section aria-labelledby="versions-heading" className="flex flex-col gap-2">
        <h2 id="versions-heading" className="text-sm font-semibold text-text-primary">
          API versions
        </h2>
        <ApiVersionList versions={versions} />
      </section>

      <section aria-labelledby="event-types-heading" className="flex flex-col gap-2">
        <h2 id="event-types-heading" className="text-sm font-semibold text-text-primary">
          Webhook event types
        </h2>
        <WebhookEventTypeList eventTypes={eventTypes} />
      </section>

      <section aria-labelledby="logs-heading" className="flex flex-col gap-2">
        <h2 id="logs-heading" className="text-sm font-semibold text-text-primary">
          Recent API requests
        </h2>
        <ApiLogList logs={logs} />
      </section>
    </div>
  );
}
