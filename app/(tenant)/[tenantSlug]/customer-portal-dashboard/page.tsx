import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { getCustomerPortalDashboardSummary, CustomerPortalDashboardQueryError } from "../../../../server/queries/customer-portal-dashboard.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerPortalDashboardCards } from "./customer-portal-dashboard-cards.tsx";

/**
 * Customer portal dashboard (CPL-301, CG-S13-CPL-003) -- the full dashboard
 * card grid CPL-300's own build log named as "Prompt 301's own job." A NEW
 * route, sibling to `customer-portal/` (the scope-preview page), not merged
 * into it -- each has its own job, linked to each other via
 * `CustomerPortalNav`.
 *
 * Reuses `resolveCustomerPortalAccessForRequest` -- the SAME general-purpose
 * Layer-4 portal entry guard `customer-portal/page.tsx` uses -- for entry
 * gating only. The dashboard itself grants nothing: every card's own "view
 * details" deep-link goes to a route that re-authorizes itself
 * independently server-side (its own guard, e.g. `customer-tickets/`'s own
 * `resolveCustomerTicketAccessForRequest`) -- this page never treats
 * dashboard visibility as authorization for anything downstream (source
 * prompt §24).
 *
 * State handling mirrors `customer-portal/page.tsx` exactly: unauthenticated
 * -> redirect to sign-in (never a page render); tenant_not_found/
 * tenant_suspended/forbidden -> a distinct denied state. Per-card
 * available/degraded/unavailable states are handled independently inside
 * `CustomerPortalDashboardCards` from the single already-fetched summary
 * row set -- only a full RPC-call failure (network/auth, not a single
 * card's own source failing) reaches this page-level `ErrorState`.
 */
export default async function CustomerPortalDashboardPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <PermissionState
        description={
          access.status === "tenant_suspended"
            ? "This organization's customer portal is currently unavailable."
            : "You don't have access to this organization's customer portal. Contact your account administrator if you believe this is a mistake."
        }
      />
    );
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let cards: Awaited<ReturnType<typeof getCustomerPortalDashboardSummary>> = [];

  try {
    cards = await getCustomerPortalDashboardSummary(supabase, access.authUserId, access.tenant.id);
  } catch (error) {
    if (!(error instanceof CustomerPortalDashboardQueryError)) throw error;
    loadFailed = true;
  }

  return (
    <div className="flex flex-col gap-4">
      <CustomerPortalNav tenantSlug={tenantSlug} current="dashboard" />

      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Dashboard</h1>
        <p className="text-xs text-neutral-500">A scoped summary of your account -- every count below is resolved server-side from your own active membership grants, never from a URL, filter, or payload. Areas not yet available show an honest &ldquo;launching soon&rdquo; state, never sample data.</p>
      </div>

      {loadFailed ? (
        <ErrorState description="Something went wrong loading your dashboard. Please try again." />
      ) : (
        <CustomerPortalDashboardCards tenantSlug={tenantSlug} cards={cards} />
      )}
    </div>
  );
}
