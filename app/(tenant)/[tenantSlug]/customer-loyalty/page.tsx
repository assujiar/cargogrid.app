import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listCustomerPortalLoyaltyAccounts, listCustomerPortalLoyaltyEarningEvents, LoyaltyProgramQueryError } from "../../../../server/queries/customer-portal-loyalty-program.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerLoyaltyAccountsPanel, CustomerLoyaltyEarningHistoryPanel } from "./customer-loyalty-panel.tsx";

/**
 * Loyalty earning-history projection (CPL-316, CG-S13-CPL-018). Read-only
 * customer-safe view over Loyalty-owned app.loyalty_accounts/app.loyalty_
 * earning_events (ADR-0024 Part A) -- cites the evaluated rule version's own
 * human-readable earning_basis/rate, never internal eligibility_config JSON
 * verbatim. There is no customer-initiated action on this page (ADR-0024
 * Part B) -- enrollment, program config and earning evaluation/reversal are
 * all staff-side (app/(tenant)/[tenantSlug]/admin/loyalty).
 */
export default async function CustomerLoyaltyPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <PermissionState
        description={access.status === "tenant_suspended" ? "This organization's customer portal is currently unavailable." : "You don't have access to this organization's loyalty program. Contact your account administrator if you believe this is a mistake."}
      />
    );
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let accounts: Awaited<ReturnType<typeof listCustomerPortalLoyaltyAccounts>> = [];
  let events: Awaited<ReturnType<typeof listCustomerPortalLoyaltyEarningEvents>> = [];

  try {
    [accounts, events] = await Promise.all([
      listCustomerPortalLoyaltyAccounts(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
      listCustomerPortalLoyaltyEarningEvents(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
    ]);
  } catch (error) {
    if (!(error instanceof LoyaltyProgramQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="loyalty" />
        <ErrorState description="Something went wrong loading your loyalty program. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <CustomerPortalNav tenantSlug={tenantSlug} current="loyalty" />

      <div>
        <h1 className="text-xl font-semibold text-text-primary">Loyalty program</h1>
        <p className="text-xs text-text-secondary">Your own enrollment and earning history. Points and cashback are earned only from eligible paid invoices, never manually adjusted.</p>
      </div>

      <section aria-labelledby="loyalty-accounts-heading" className="flex flex-col gap-2">
        <h2 id="loyalty-accounts-heading" className="text-sm font-semibold text-text-primary">
          Your enrollment
        </h2>
        <CustomerLoyaltyAccountsPanel accounts={accounts} />
      </section>

      <section aria-labelledby="loyalty-history-heading" className="flex flex-col gap-2">
        <h2 id="loyalty-history-heading" className="text-sm font-semibold text-text-primary">
          Earning history
        </h2>
        <CustomerLoyaltyEarningHistoryPanel events={events} />
      </section>
    </div>
  );
}
