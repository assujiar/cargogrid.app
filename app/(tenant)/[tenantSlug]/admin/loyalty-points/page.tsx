import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listLoyaltyAccounts, LoyaltyProgramQueryError } from "../../../../../server/queries/customer-portal-loyalty-program.ts";
import { listLoyaltyPointBalances, listLoyaltyPointLots, listLoyaltyPointAdjustmentRequests, LoyaltyPointsQueryError } from "../../../../../server/queries/customer-portal-loyalty-points.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { PostPointsEarnedForm, ReversePointsEarnedForm, ExpireLotsForm, RequestAdjustmentForm, AdjustmentRequestRow, AccountBalanceRow } from "./loyalty-points-admin-panel.tsx";

/**
 * Points Ledger tenant-internal admin screen (CPL-318, CG-S13-CPL-020).
 * Earning-event-to-point-lot conversion, governed reversal, tenant-wide
 * expiry scan, and the point-adjustment maker-checker (request/decide) --
 * all gated by each RPC's own LYL:* authority check, this page's own guard
 * (resolveTenantAdminAccessForRequest) only confirms a coarse tenant_admin
 * portal-entry boundary. Reuses CPL-316's own account query (never
 * re-derives it).
 */
export default async function LoyaltyPointsAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let accounts: Awaited<ReturnType<typeof listLoyaltyAccounts>> = [];
  let balances: Awaited<ReturnType<typeof listLoyaltyPointBalances>> = [];
  let lots: Awaited<ReturnType<typeof listLoyaltyPointLots>> = [];
  let adjustmentRequests: Awaited<ReturnType<typeof listLoyaltyPointAdjustmentRequests>> = [];

  try {
    [accounts, balances, lots, adjustmentRequests] = await Promise.all([
      listLoyaltyAccounts(supabase, access.tenant.id, access.authUserId, { status: "active", limit: 100 }),
      listLoyaltyPointBalances(supabase, access.tenant.id, access.authUserId, { limit: 100 }),
      listLoyaltyPointLots(supabase, access.tenant.id, access.authUserId, { status: "active", limit: 200 }),
      listLoyaltyPointAdjustmentRequests(supabase, access.tenant.id, access.authUserId, { limit: 100 }),
    ]);
  } catch (error) {
    if (!(error instanceof LoyaltyProgramQueryError) && !(error instanceof LoyaltyPointsQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-text-primary">Points Ledger</h1>
        <ErrorState description="Something went wrong loading the points ledger. Please try again." />
      </div>
    );
  }

  const balanceByAccount = new Map(balances.map((balance) => [balance.loyaltyAccountId, balance]));
  const lotsByAccount = new Map<string, typeof lots>();
  for (const lot of lots) {
    lotsByAccount.set(lot.loyaltyAccountId, [...(lotsByAccount.get(lot.loyaltyAccountId) ?? []), lot]);
  }
  const pendingRequests = adjustmentRequests.filter((request) => request.status === "pending_approval");
  const decidedRequests = adjustmentRequests.filter((request) => request.status !== "pending_approval");

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Points Ledger</h1>
        <p className="text-sm text-text-secondary">Exact point ledger accounting -- append-only entries, one derived balance per account, FIFO-by-expiry lots, and a governed maker-checker adjustment workflow.</p>
      </div>

      <section aria-labelledby="points-sync-heading" className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 id="points-sync-heading" className="text-sm font-semibold text-text-primary">
          Earning event actions
        </h2>
        <p className="text-xs text-text-secondary">Convert a CPL-316 points-type earning event into a point lot, or reverse points for an already-reversed earning event. Find event IDs in Loyalty admin&apos;s own earning-history view.</p>
        <div className="flex flex-col gap-4 sm:flex-row">
          <PostPointsEarnedForm tenantSlug={tenantSlug} />
          <ReversePointsEarnedForm tenantSlug={tenantSlug} />
        </div>
      </section>

      <section aria-labelledby="points-expiry-heading" className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 id="points-expiry-heading" className="text-sm font-semibold text-text-primary">
          Expiry scan
        </h2>
        <p className="text-xs text-text-secondary">Scans every active, past-expiry lot tenant-wide and posts a real expiry entry per lot. Idempotent -- safe to re-run.</p>
        <ExpireLotsForm tenantSlug={tenantSlug} />
      </section>

      <section aria-labelledby="points-balances-heading" className="flex flex-col gap-3">
        <h2 id="points-balances-heading" className="text-sm font-semibold text-text-primary">
          Account balances
        </h2>
        {accounts.length === 0 ? (
          <EmptyState title="No active enrolled accounts" description="Enroll a customer account in Loyalty admin first." />
        ) : (
          <div className="flex flex-col gap-3">
            {accounts.map((account) => (
              <AccountBalanceRow key={account.id} tenantSlug={tenantSlug} account={account} balance={balanceByAccount.get(account.id) ?? null} lots={lotsByAccount.get(account.id) ?? []} />
            ))}
          </div>
        )}
      </section>

      <section aria-labelledby="points-adjustment-request-heading" className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 id="points-adjustment-request-heading" className="text-sm font-semibold text-text-primary">
          Request a point adjustment
        </h2>
        <p className="text-xs text-text-secondary">Maker-checker governed. A different Loyalty Manager must decide this request -- the requester may not approve their own request.</p>
        <RequestAdjustmentForm tenantSlug={tenantSlug} accounts={accounts} />
      </section>

      <section aria-labelledby="points-pending-heading" className="flex flex-col gap-3">
        <h2 id="points-pending-heading" className="text-sm font-semibold text-text-primary">
          Pending adjustment requests
        </h2>
        {pendingRequests.length === 0 ? (
          <p className="text-xs text-text-secondary">No pending adjustment requests.</p>
        ) : (
          <div className="flex flex-col gap-3">
            {pendingRequests.map((request) => (
              <AdjustmentRequestRow key={request.id} tenantSlug={tenantSlug} request={request} />
            ))}
          </div>
        )}
      </section>

      <section aria-labelledby="points-decided-heading" className="flex flex-col gap-3">
        <h2 id="points-decided-heading" className="text-sm font-semibold text-text-primary">
          Decided adjustment requests
        </h2>
        {decidedRequests.length === 0 ? (
          <p className="text-xs text-text-secondary">No decided adjustment requests yet.</p>
        ) : (
          <div className="flex flex-col gap-3">
            {decidedRequests.map((request) => (
              <AdjustmentRequestRow key={request.id} tenantSlug={tenantSlug} request={request} />
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
