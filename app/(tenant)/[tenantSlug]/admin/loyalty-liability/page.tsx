import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listLoyaltyLiabilityReconciliationRuns,
  listLoyaltyLiabilityReconciliationExceptions,
  getLoyaltyEngagementMetrics,
  LoyaltyLiabilityQueryError,
} from "../../../../../server/queries/customer-portal-loyalty-liability.ts";
import type { LoyaltyLiabilityReconciliationRun, LoyaltyLiabilityReconciliationException, LoyaltyEngagementMetrics } from "../../../../../server/contracts/customer-portal-loyalty-liability/customer-portal-loyalty-liability.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { ExecuteLoyaltyLiabilityReconciliationRunForm, LoyaltyLiabilityReconciliationRunHistoryTable, LoyaltyLiabilityReconciliationExceptionQueue, LoyaltyEngagementMetricsWidgets } from "./loyalty-liability-admin-panel.tsx";

/**
 * Liability and Reconciliation tenant-internal dashboard (CPL-323,
 * CG-S13-CPL-025). Composes app.execute_loyalty_liability_reconciliation_run
 * (recomputes every liability total LIVE from the raw ledger/event tables --
 * CPL-318's points ledger, CPL-319's benefit entitlements, CPL-320/321's
 * reward/redemption tables), app.resolve_loyalty_liability_reconciliation_
 * exception, app.certify_loyalty_liability_reconciliation_run (BLOCKED while
 * any exception remains open), and app.get_loyalty_engagement_metrics
 * (Step-13-scope basic analytics only). Gated by each RPC's own LYL:*
 * authority check; this page's own guard (resolveTenantAdminAccessForRequest)
 * only confirms a coarse tenant_admin portal-entry boundary.
 */
export default async function LoyaltyLiabilityAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let runs: LoyaltyLiabilityReconciliationRun[] = [];
  let metrics: LoyaltyEngagementMetrics | null = null;
  const exceptionEntries: { run: LoyaltyLiabilityReconciliationRun; exception: LoyaltyLiabilityReconciliationException }[] = [];

  try {
    const periodEnd = new Date();
    const periodStart = new Date(periodEnd.getTime() - 30 * 24 * 60 * 60 * 1000);

    [runs, metrics] = await Promise.all([
      listLoyaltyLiabilityReconciliationRuns(supabase, access.tenant.id, access.authUserId, { limit: 20 }),
      getLoyaltyEngagementMetrics(supabase, { tenantId: access.tenant.id, periodStart: periodStart.toISOString(), periodEnd: periodEnd.toISOString(), actorAuthUserId: access.authUserId }),
    ]);

    const pendingRuns = runs.filter((run) => run.status === "exceptions_pending");
    const exceptionsByRun = await Promise.all(
      pendingRuns.map((run) => listLoyaltyLiabilityReconciliationExceptions(supabase, access.tenant.id, run.id, access.authUserId, { status: "open", limit: 50 }).then((exceptions) => ({ run, exceptions }))),
    );
    for (const { run, exceptions } of exceptionsByRun) {
      for (const exception of exceptions) {
        exceptionEntries.push({ run, exception });
      }
    }
  } catch (error) {
    if (!(error instanceof LoyaltyLiabilityQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-text-primary">Liability &amp; reconciliation</h1>
        <ErrorState description="Something went wrong loading the liability reconciliation dashboard. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Liability &amp; reconciliation</h1>
        <p className="text-sm text-text-secondary">
          Deterministic Loyalty liability evidence over points, cashback, discount, voucher, and open reward-fulfillment exposure -- recomputed live from the raw ledger/event tables on every run, never trusted from a cached snapshot.
          Certification is blocked while any exception remains unresolved.
        </p>
      </div>

      <section aria-labelledby="engagement-heading" className="flex flex-col gap-3">
        <h2 id="engagement-heading" className="text-lg font-semibold text-text-primary">
          Engagement (last 30 days)
        </h2>
        <p className="text-xs text-text-secondary">Aggregate, tenant-wide only -- Step 13 basic analytics (Step 14 may add advanced analytics). Never a per-customer breakdown or internal cost/margin figure.</p>
        <LoyaltyEngagementMetricsWidgets metrics={metrics} />
      </section>

      <ExecuteLoyaltyLiabilityReconciliationRunForm tenantSlug={tenantSlug} />

      <section aria-labelledby="exceptions-heading" className="flex flex-col gap-3">
        <h2 id="exceptions-heading" className="text-lg font-semibold text-text-primary">
          Open exceptions ({exceptionEntries.length})
        </h2>
        <LoyaltyLiabilityReconciliationExceptionQueue tenantSlug={tenantSlug} entries={exceptionEntries} />
      </section>

      <section aria-labelledby="runs-heading" className="flex flex-col gap-3">
        <h2 id="runs-heading" className="text-lg font-semibold text-text-primary">
          Run history
        </h2>
        <LoyaltyLiabilityReconciliationRunHistoryTable tenantSlug={tenantSlug} runs={runs} />
      </section>
    </div>
  );
}
