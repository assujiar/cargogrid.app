import { randomUUID } from "node:crypto";
import { notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { getCustomerPortalScopeContext, CustomerPortalScopeQueryError } from "../../../../server/queries/customer-portal-scope.ts";
import { listCustomerQuoteRequests, CustomerQuoteRequestQueryError } from "../../../../server/queries/customer-quote-request.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerQuotesPanel } from "./customer-quotes-panel.tsx";
import { createCustomerQuoteRequestDraftAction } from "./actions.ts";

/**
 * Customer quote request list/create view (CPL-302, CG-S13-CPL-004). Uses
 * lib/portal/customer-portal-guard.ts (CPL-300's general-purpose Layer 4
 * portal entry guard, not the Phase-7-specific customer-ticket-guard.ts),
 * mirroring app/(tenant)/[tenantSlug]/customer-tickets/page.tsx's own
 * structure. Every account/request shown here is already scoped
 * server-side by the owning RPC (app.resolve_customer_account_scope) --
 * this page never applies its own additional filtering.
 */
export default async function CustomerQuotesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let accounts: Awaited<ReturnType<typeof getCustomerPortalScopeContext>> = [];
  let requests: Awaited<ReturnType<typeof listCustomerQuoteRequests>> = [];

  try {
    [accounts, requests] = await Promise.all([
      getCustomerPortalScopeContext(supabase, access.authUserId, access.tenant.id),
      listCustomerQuoteRequests(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
    ]);
  } catch (error) {
    if (!(error instanceof CustomerPortalScopeQueryError) && !(error instanceof CustomerQuoteRequestQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your quote requests. Please try again." />;
  }

  // Fresh per render, not regenerated per submit -- a genuine retry of the
  // SAME rendered create form (double-click, network retry before the
  // button's disabled state takes effect) reuses this same key; a
  // successful create triggers revalidatePath(listPath), which re-renders
  // this Server Component and mints a fresh key for the NEXT draft.
  // Tier C fix (spec-compliance) -- previously generated inside the Server
  // Action body from Date.now(), which produced a different key on every
  // physical re-invocation and defeated double-submit protection. Mirrors
  // customer-quotes/[requestId]/page.tsx's own established convention.
  const createIdempotencyKey = randomUUID();

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Quote requests</h1>
        <p className="text-xs text-neutral-500">
          Request a quotation for a new shipment and track it through Commercial review. A submitted request is not a rated quote or price commitment until Commercial approves it.
        </p>
      </div>

      <CustomerQuotesPanel
        tenantSlug={tenantSlug}
        accounts={accounts}
        requests={requests}
        createAction={createCustomerQuoteRequestDraftAction.bind(null, tenantSlug, createIdempotencyKey)}
      />
    </div>
  );
}
