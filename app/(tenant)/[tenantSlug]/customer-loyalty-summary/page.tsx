import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listCustomerPortalLoyaltyAccounts, LoyaltyProgramQueryError } from "../../../../server/queries/customer-portal-loyalty-program.ts";
import { getCustomerPortalLoyaltySummary, LoyaltyLiabilityQueryError } from "../../../../server/queries/customer-portal-loyalty-liability.ts";
import type { CustomerPortalLoyaltySummary } from "../../../../server/contracts/customer-portal-loyalty-liability/customer-portal-loyalty-liability.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerLoyaltySummaryCard } from "./customer-loyalty-summary-panel.tsx";

/**
 * Consolidated loyalty summary (CPL-323, CG-S13-CPL-025). Composes (never
 * duplicates) the already-existing per-domain customer reads from CPL-316
 * (enrollment) through CPL-322 (hold status) into one card per loyalty
 * account: points balance, tier, active entitlements, recent redemptions,
 * hold status. Every already-shipped per-domain route
 * (customer-loyalty/-tier/-points/-benefits/-rewards/-redemptions) remains
 * the place for the FULL detail behind each of these figures -- this page
 * is deliberately a single-glance overview, not a replacement.
 */
export default async function CustomerLoyaltySummaryPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <PermissionState
        description={access.status === "tenant_suspended" ? "This organization's customer portal is currently unavailable." : "You don't have access to this organization's loyalty summary. Contact your account administrator if you believe this is a mistake."}
      />
    );
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let summaries: CustomerPortalLoyaltySummary[] = [];

  try {
    const accounts = await listCustomerPortalLoyaltyAccounts(supabase, access.tenant.id, access.authUserId, { limit: 50 });
    summaries = await Promise.all(accounts.map((account) => getCustomerPortalLoyaltySummary(supabase, { tenantId: access.tenant.id, loyaltyAccountId: account.id, actorAuthUserId: access.authUserId })));
  } catch (error) {
    if (!(error instanceof LoyaltyProgramQueryError) && !(error instanceof LoyaltyLiabilityQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="summary" />
        <ErrorState description="Something went wrong loading your loyalty summary. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <CustomerPortalNav tenantSlug={tenantSlug} current="summary" />

      <div>
        <h1 className="text-xl font-semibold text-text-primary">Loyalty summary</h1>
        <p className="text-xs text-text-secondary">A single-glance view of your points, tier, cashback/vouchers, and redemptions. See the sibling pages in the nav above for full detail and history.</p>
      </div>

      {summaries.length === 0 ? (
        <EmptyState title="No loyalty enrollment yet" description="You are not currently enrolled in a loyalty program for this organization." />
      ) : (
        <div className="flex flex-col gap-4">
          {summaries.map((summary) => (
            <CustomerLoyaltySummaryCard key={summary.loyaltyAccountId} tenantSlug={tenantSlug} summary={summary} />
          ))}
        </div>
      )}
    </div>
  );
}
