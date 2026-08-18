import { randomUUID } from "node:crypto";
import { notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { getCustomerPortalScopeContext, CustomerPortalScopeQueryError } from "../../../../server/queries/customer-portal-scope.ts";
import { listCustomerBookingRequests, CustomerBookingRequestQueryError } from "../../../../server/queries/customer-booking-request.ts";
import { getCustomerQuoteRequest, listCustomerQuoteRequests, CustomerQuoteRequestQueryError } from "../../../../server/queries/customer-quote-request.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerBookingsPanel } from "./customer-bookings-panel.tsx";
import { createCustomerBookingRequestDraftAction } from "./actions.ts";

/**
 * Customer booking request list/create view (CPL-303, CG-S13-CPL-005). Uses
 * lib/portal/customer-portal-guard.ts (CPL-300's general-purpose Layer 4
 * portal entry guard), mirroring app/(tenant)/[tenantSlug]/customer-quotes/
 * page.tsx's own structure exactly. Every account/request shown here is
 * already scoped server-side by the owning RPC (app.resolve_customer_
 * account_scope) -- this page never applies its own additional filtering.
 *
 * Supports pre-filling the create form from an already-accepted (converted)
 * quote request via ?fromQuoteRequestId=<id> (source prompt §15's own "quote
 * selection... optionally pre-filling" allowance) -- a picker of every
 * converted quote request in scope is also always shown, so a query param is
 * one convenience entry point, never the only one.
 */
export default async function CustomerBookingsPage({ params, searchParams }: { params: Promise<{ tenantSlug: string }>; searchParams: Promise<{ fromQuoteRequestId?: string }> }) {
  const { tenantSlug } = await params;
  const { fromQuoteRequestId } = await searchParams;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let accounts: Awaited<ReturnType<typeof getCustomerPortalScopeContext>> = [];
  let bookings: Awaited<ReturnType<typeof listCustomerBookingRequests>> = [];
  let acceptedQuoteRequests: Awaited<ReturnType<typeof listCustomerQuoteRequests>> = [];
  let prefill: Awaited<ReturnType<typeof getCustomerQuoteRequest>> | null = null;

  try {
    [accounts, bookings, acceptedQuoteRequests] = await Promise.all([
      getCustomerPortalScopeContext(supabase, access.authUserId, access.tenant.id),
      listCustomerBookingRequests(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
      listCustomerQuoteRequests(supabase, access.tenant.id, access.authUserId, { status: "converted", limit: 50 }),
    ]);
    if (fromQuoteRequestId) {
      try {
        prefill = await getCustomerQuoteRequest(supabase, access.tenant.id, fromQuoteRequestId, access.authUserId);
      } catch (error) {
        if (!(error instanceof CustomerQuoteRequestQueryError) || error.code !== "record_not_found") throw error;
        // A stale/forged/out-of-scope fromQuoteRequestId is silently ignored -- the create
        // form still renders normally with no pre-fill, never an error state for this alone.
      }
    }
  } catch (error) {
    if (!(error instanceof CustomerPortalScopeQueryError) && !(error instanceof CustomerBookingRequestQueryError) && !(error instanceof CustomerQuoteRequestQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your bookings. Please try again." />;
  }

  // Fresh per render, not regenerated per submit -- Tier C fix
  // (spec-compliance), mirrors customer-quotes/page.tsx's own identical fix.
  const createIdempotencyKey = randomUUID();

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Bookings</h1>
        <p className="text-xs text-neutral-500">
          Book a shipment from an accepted quote or as a direct service request, then track it through Operations acceptance. A booking becomes an operational shipment only after Operations confirms it.
        </p>
      </div>

      <CustomerBookingsPanel
        tenantSlug={tenantSlug}
        accounts={accounts}
        bookings={bookings}
        acceptedQuoteRequests={acceptedQuoteRequests}
        prefill={prefill}
        createAction={createCustomerBookingRequestDraftAction.bind(null, tenantSlug, createIdempotencyKey)}
      />
    </div>
  );
}
