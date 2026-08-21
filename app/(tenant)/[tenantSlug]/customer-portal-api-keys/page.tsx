import { notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { getCustomerPortalScopeContext, CustomerPortalScopeQueryError } from "../../../../server/queries/customer-portal-scope.ts";
import { listCustomerApiKeysForAccount, CustomerApiQueryError, type CustomerApiQueryRpcClient } from "../../../../server/queries/customer-api.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { Link } from "../../../../components/ui/link.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CreateCustomerApiKeyForm, CustomerApiKeyList } from "./customer-portal-api-keys-panel.tsx";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** See app/(tenant)/[tenantSlug]/admin/api-keys/page.tsx's own toQueryClient() for why this cast is needed. */
function toQueryClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): CustomerApiQueryRpcClient {
  return client as unknown as CustomerApiQueryRpcClient;
}

/**
 * Customer API key self-service (IAE-010, Prompt 338). The account_admin-
 * facing counterpart to customer-portal-users -- manages a different kind of
 * account access (programmatic keys instead of human members). Guarded the
 * same two-layer way every prior Phase 8 mutation surface is: portal-entry
 * gate here, then app.actor_is_active_customer_portal_account_admin on every
 * RPC call itself.
 */
export default async function CustomerPortalApiKeysPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ accountId?: string }>;
}) {
  const { tenantSlug } = await params;
  const { accountId: rawAccountId } = await searchParams;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);

  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let accounts: Awaited<ReturnType<typeof getCustomerPortalScopeContext>> = [];

  try {
    accounts = await getCustomerPortalScopeContext(supabase, access.authUserId, access.tenant.id);
  } catch (error) {
    if (!(error instanceof CustomerPortalScopeQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="api-keys" />
        <ErrorState description="Something went wrong loading your account access. Please try again." />
      </div>
    );
  }

  if (accounts.length === 0) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="api-keys" />
        <PermissionState description="No account is linked to your customer profile yet. Contact your account administrator." />
      </div>
    );
  }

  const requestedAccountId = rawAccountId && UUID_RE.test(rawAccountId) ? rawAccountId : null;
  const selectedAccountId = (requestedAccountId && accounts.some((a) => a.accountId === requestedAccountId) ? requestedAccountId : null) ?? accounts.find((a) => a.isPrimary)?.accountId ?? accounts[0]!.accountId;
  const viewerIsAdmin = accounts.find((a) => a.accountId === selectedAccountId)?.role === "account_admin";

  let detailLoadFailed = false;
  let keys: Awaited<ReturnType<typeof listCustomerApiKeysForAccount>> = [];

  if (viewerIsAdmin) {
    try {
      keys = await listCustomerApiKeysForAccount(toQueryClient(supabase), { tenantId: access.tenant.id, accountId: selectedAccountId, actorAuthUserId: access.authUserId });
    } catch (error) {
      if (!(error instanceof CustomerApiQueryError)) throw error;
      detailLoadFailed = true;
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <CustomerPortalNav tenantSlug={tenantSlug} current="api-keys" />

      <div>
        <h1 className="text-xl font-semibold text-neutral-900">API keys</h1>
        <p className="text-xs text-neutral-500">Create scoped API keys so your own systems can call the CargoGrid Customer API (shipment tracking, bookings) on this account&apos;s own behalf. Only active account admins can manage keys.</p>
      </div>

      {accounts.length > 1 ? (
        <nav aria-label="Account" className="flex flex-wrap gap-2 text-xs">
          {accounts.map((a) => (
            <Link
              key={a.accountId}
              href={`/${tenantSlug}/customer-portal-api-keys?accountId=${a.accountId}`}
              className={a.accountId === selectedAccountId ? "font-semibold text-primary underline" : "text-neutral-500 underline"}
            >
              {a.accountName}
            </Link>
          ))}
        </nav>
      ) : null}

      {!viewerIsAdmin ? (
        <PermissionState description="Only an active account admin can manage API keys on this account. Ask your account administrator if you believe you should have this access." />
      ) : detailLoadFailed ? (
        <ErrorState description="Something went wrong loading this account's API keys. Please try again." />
      ) : (
        <>
          <CreateCustomerApiKeyForm tenantSlug={tenantSlug} accountId={selectedAccountId} />
          <CustomerApiKeyList tenantSlug={tenantSlug} accountId={selectedAccountId} keys={keys} />
        </>
      )}
    </div>
  );
}
