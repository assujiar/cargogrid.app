import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listLoyaltyRedemptions, LoyaltyRedemptionQueryError } from "../../../../../server/queries/customer-portal-loyalty-redemptions.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { LoyaltyRedemptionApprovalQueue, LoyaltyRedemptionFulfillmentQueue, LoyaltyRedemptionHistoryTable } from "./loyalty-redemptions-admin-panel.tsx";

/**
 * Redemption Approval and Fulfillment tenant-internal workbench (CPL-321,
 * CG-S13-CPL-023). Three sections, all reading the SAME app.loyalty_
 * redemptions table filtered by status: (1) pending approval queue (LYL:
 * Configure to decide), (2) fulfillment queue -- fulfilling physical_item/
 * service_credit redemptions awaiting a mark-fulfilled/mark-failed decision
 * (LYL:Edit), (3) a recent-history table across every terminal status. All
 * gated by each RPC's own LYL:* authority check; this page's own guard
 * (resolveTenantAdminAccessForRequest) only confirms a coarse tenant_admin
 * portal-entry boundary.
 */
export default async function LoyaltyRedemptionsAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let pending: Awaited<ReturnType<typeof listLoyaltyRedemptions>> = [];
  let fulfilling: Awaited<ReturnType<typeof listLoyaltyRedemptions>> = [];
  let recent: Awaited<ReturnType<typeof listLoyaltyRedemptions>> = [];

  try {
    [pending, fulfilling, recent] = await Promise.all([
      listLoyaltyRedemptions(supabase, access.tenant.id, access.authUserId, { status: "pending_approval", limit: 100 }),
      listLoyaltyRedemptions(supabase, access.tenant.id, access.authUserId, { status: "fulfilling", limit: 100 }),
      listLoyaltyRedemptions(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
    ]);
  } catch (error) {
    if (!(error instanceof LoyaltyRedemptionQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-text-primary">Redemptions</h1>
        <ErrorState description="Something went wrong loading the redemption workbench. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Redemptions</h1>
        <p className="text-sm text-text-secondary">Review and decide submitted redemption requests, and track fulfillment for physical items and service credits. Discount vouchers are fulfilled automatically the moment they&apos;re approved.</p>
      </div>

      <section aria-labelledby="pending-heading" className="flex flex-col gap-3">
        <h2 id="pending-heading" className="text-lg font-semibold text-text-primary">
          Pending approval ({pending.length})
        </h2>
        <LoyaltyRedemptionApprovalQueue tenantSlug={tenantSlug} redemptions={pending} />
      </section>

      <section aria-labelledby="fulfillment-heading" className="flex flex-col gap-3">
        <h2 id="fulfillment-heading" className="text-lg font-semibold text-text-primary">
          Awaiting fulfillment ({fulfilling.length})
        </h2>
        <LoyaltyRedemptionFulfillmentQueue tenantSlug={tenantSlug} redemptions={fulfilling} />
      </section>

      <section aria-labelledby="history-heading" className="flex flex-col gap-3">
        <h2 id="history-heading" className="text-lg font-semibold text-text-primary">
          Recent history
        </h2>
        <LoyaltyRedemptionHistoryTable redemptions={recent} />
      </section>
    </div>
  );
}
