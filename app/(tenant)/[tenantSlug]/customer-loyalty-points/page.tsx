import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listCustomerPortalLoyaltyPointBalances, listCustomerPortalLoyaltyPointLedgerEntries, listCustomerPortalLoyaltyPointExpirySchedule, LoyaltyPointsQueryError } from "../../../../server/queries/customer-portal-loyalty-points.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerLoyaltyPointsPanel } from "./customer-loyalty-points-panel.tsx";

/**
 * Points Ledger balance/history/expiry-schedule (CPL-318, CG-S13-CPL-020).
 * Read-only customer-safe view over Loyalty-owned app.loyalty_point_
 * balances/app.loyalty_point_ledger_entries/app.loyalty_point_lots
 * (ADR-0024 Part A) -- current point balance, ledger history (never the
 * real internal reason on an adjustment entry), and the customer's own
 * currently-active lots' expiry schedule (soonest first). There is no
 * customer-initiated action on this page (ADR-0024 Part B) -- earning
 * conversion, expiry, and manual adjustments are all staff-side
 * (app/(tenant)/[tenantSlug]/admin/loyalty-points).
 */
export default async function CustomerLoyaltyPointsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <PermissionState
        description={access.status === "tenant_suspended" ? "This organization's customer portal is currently unavailable." : "You don't have access to this organization's points balance. Contact your account administrator if you believe this is a mistake."}
      />
    );
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let balances: Awaited<ReturnType<typeof listCustomerPortalLoyaltyPointBalances>> = [];
  let ledgerEntries: Awaited<ReturnType<typeof listCustomerPortalLoyaltyPointLedgerEntries>> = [];
  let expirySchedule: Awaited<ReturnType<typeof listCustomerPortalLoyaltyPointExpirySchedule>> = [];

  try {
    [balances, ledgerEntries, expirySchedule] = await Promise.all([
      listCustomerPortalLoyaltyPointBalances(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
      listCustomerPortalLoyaltyPointLedgerEntries(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
      listCustomerPortalLoyaltyPointExpirySchedule(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
    ]);
  } catch (error) {
    if (!(error instanceof LoyaltyPointsQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="points" />
        <ErrorState description="Something went wrong loading your points balance. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <CustomerPortalNav tenantSlug={tenantSlug} current="points" />

      <div>
        <h1 className="text-xl font-semibold text-text-primary">Points balance</h1>
        <p className="text-xs text-text-secondary">Your current point balance, ledger history, and upcoming point expirations. Points are derived exclusively from your own ledger history -- never edited directly.</p>
      </div>

      <CustomerLoyaltyPointsPanel balances={balances} ledgerEntries={ledgerEntries} expirySchedule={expirySchedule} />
    </div>
  );
}
