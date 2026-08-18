import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listLoyaltyExpiryRuns, LoyaltyExpiryFraudQueryError } from "../../../../../server/queries/customer-portal-loyalty-expiry-fraud.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { RunLoyaltyExpirySweepForm, LoyaltyExpiryRunHistoryTable } from "./loyalty-expiry-admin-panel.tsx";

/**
 * Expiry sweep trigger/history (CPL-322, CG-S13-CPL-024). Composes
 * app.expire_loyalty_point_lots (CPL-318) and app.expire_loyalty_benefit_
 * entitlements (CPL-319) via app.run_loyalty_expiry_sweep -- a real app.jobs
 * row tracked through the actual PLT-132 lifecycle, idempotent per calendar
 * day. Gated by each RPC's own LYL:* authority check; this page's own guard
 * (resolveTenantAdminAccessForRequest) only confirms a coarse tenant_admin
 * portal-entry boundary.
 */
export default async function LoyaltyExpiryAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let runs: Awaited<ReturnType<typeof listLoyaltyExpiryRuns>> = [];

  try {
    runs = await listLoyaltyExpiryRuns(supabase, access.tenant.id, access.authUserId, { limit: 50 });
  } catch (error) {
    if (!(error instanceof LoyaltyExpiryFraudQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-text-primary">Expiry sweep</h1>
        <ErrorState description="Something went wrong loading the expiry sweep workbench. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Expiry sweep</h1>
        <p className="text-sm text-text-secondary">Run and review point-lot and benefit-entitlement expiry sweeps for this tenant. Expiry never deletes original earning/redemption history.</p>
      </div>

      <RunLoyaltyExpirySweepForm tenantSlug={tenantSlug} />

      <section aria-labelledby="expiry-history-heading" className="flex flex-col gap-3">
        <h2 id="expiry-history-heading" className="text-lg font-semibold text-text-primary">
          Run history
        </h2>
        <LoyaltyExpiryRunHistoryTable runs={runs} />
      </section>
    </div>
  );
}
