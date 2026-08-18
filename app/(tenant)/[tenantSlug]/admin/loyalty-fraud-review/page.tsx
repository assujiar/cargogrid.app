import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listLoyaltyFraudReviewCases, listLoyaltyFraudReviewSuppressions, LoyaltyExpiryFraudQueryError } from "../../../../../server/queries/customer-portal-loyalty-expiry-fraud.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import {
  OpenLoyaltyFraudReviewCaseForm,
  LoyaltyFraudReviewCaseQueue,
  LoyaltyFraudReviewCaseHistoryTable,
  SuppressLoyaltyFraudReviewForm,
  LoyaltyFraudReviewSuppressionList,
} from "./loyalty-fraud-review-admin-panel.tsx";

/**
 * Fraud review-case workbench (CPL-322, CG-S13-CPL-024). Open/under_review
 * cases queue (confirm/clear with a mandatory reason), a decided-case
 * history table, and suppression/cooldown management. Governed, auditable
 * controls -- opening a case applies a provisional hold; only a human
 * reviewer's own confirm/clear call is a lasting outcome (no autonomous
 * punitive action). All gated by each RPC's own LYL:* authority check; this
 * page's own guard (resolveTenantAdminAccessForRequest) only confirms a
 * coarse tenant_admin portal-entry boundary.
 */
export default async function LoyaltyFraudReviewAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let openCases: Awaited<ReturnType<typeof listLoyaltyFraudReviewCases>> = [];
  let underReviewCases: Awaited<ReturnType<typeof listLoyaltyFraudReviewCases>> = [];
  let decidedCases: Awaited<ReturnType<typeof listLoyaltyFraudReviewCases>> = [];
  let activeSuppressions: Awaited<ReturnType<typeof listLoyaltyFraudReviewSuppressions>> = [];

  try {
    const [open, underReview, recent, suppressions] = await Promise.all([
      listLoyaltyFraudReviewCases(supabase, access.tenant.id, access.authUserId, { status: "open", limit: 100 }),
      listLoyaltyFraudReviewCases(supabase, access.tenant.id, access.authUserId, { status: "under_review", limit: 100 }),
      listLoyaltyFraudReviewCases(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
      listLoyaltyFraudReviewSuppressions(supabase, access.tenant.id, access.authUserId, { activeOnly: true, limit: 100 }),
    ]);
    openCases = open;
    underReviewCases = underReview;
    decidedCases = recent.filter((c) => c.status === "confirmed" || c.status === "cleared");
    activeSuppressions = suppressions;
  } catch (error) {
    if (!(error instanceof LoyaltyExpiryFraudQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-text-primary">Fraud review</h1>
        <ErrorState description="Something went wrong loading the fraud review workbench. Please try again." />
      </div>
    );
  }

  const openQueue = [...openCases, ...underReviewCases];

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Fraud review</h1>
        <p className="text-sm text-text-secondary">Governed, auditable fraud review controls. Opening a case applies a provisional account hold; only a human reviewer&apos;s own confirm/clear decision is a lasting outcome.</p>
      </div>

      <OpenLoyaltyFraudReviewCaseForm tenantSlug={tenantSlug} />

      <section aria-labelledby="queue-heading" className="flex flex-col gap-3">
        <h2 id="queue-heading" className="text-lg font-semibold text-text-primary">
          Open cases ({openQueue.length})
        </h2>
        <LoyaltyFraudReviewCaseQueue tenantSlug={tenantSlug} cases={openQueue} />
      </section>

      <section aria-labelledby="fraud-history-heading" className="flex flex-col gap-3">
        <h2 id="fraud-history-heading" className="text-lg font-semibold text-text-primary">
          Recent decisions
        </h2>
        <LoyaltyFraudReviewCaseHistoryTable cases={decidedCases} />
      </section>

      <SuppressLoyaltyFraudReviewForm tenantSlug={tenantSlug} />

      <section aria-labelledby="suppression-heading" className="flex flex-col gap-3">
        <h2 id="suppression-heading" className="text-lg font-semibold text-text-primary">
          Active suppressions
        </h2>
        <LoyaltyFraudReviewSuppressionList tenantSlug={tenantSlug} suppressions={activeSuppressions} />
      </section>
    </div>
  );
}
