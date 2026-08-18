import { StatusBadge } from "../../../../components/ui/status-badge.tsx";
import { Link } from "../../../../components/ui/link.tsx";
import type { CustomerPortalLoyaltySummary } from "../../../../server/contracts/customer-portal-loyalty-liability/customer-portal-loyalty-liability.ts";

function formatAmount(value: number): string {
  return new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 }).format(value);
}

export function CustomerLoyaltySummaryCard({ tenantSlug, summary }: { tenantSlug: string; summary: CustomerPortalLoyaltySummary }) {
  return (
    <section aria-label={`${summary.programName ?? "Loyalty"} summary`} className="flex flex-col gap-4 rounded-md border border-neutral-200 p-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="text-sm font-semibold text-text-primary">{summary.programName ?? "Loyalty program"}</p>
          <p className="text-xs text-text-secondary">Enrolled {new Date(summary.enrolledAt).toLocaleDateString()}</p>
        </div>
        <StatusBadge tone={summary.accountStatus === "active" ? "success" : "neutral"} label={summary.accountStatus} />
      </div>

      {summary.isOnHold ? (
        <div role="alert" className="rounded-md border border-warning/40 bg-warning/10 p-3 text-xs text-warning">
          {summary.holdNotice ?? "This account is currently on hold."}
        </div>
      ) : null}

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <div>
          <span className="block text-xs text-text-secondary">Points available</span>
          <span className="text-lg font-semibold text-text-primary">{formatAmount(summary.pointsAvailable)}</span>
        </div>
        <div>
          <span className="block text-xs text-text-secondary">Tier</span>
          <span className="text-lg font-semibold text-text-primary">{summary.tierName ?? "—"}</span>
        </div>
        <div>
          <span className="block text-xs text-text-secondary">Active cashback / discounts / vouchers</span>
          <span className="text-lg font-semibold text-text-primary">{summary.activeEntitlementsCount}</span>
        </div>
      </div>

      {summary.isTierBenefitsSuspended ? <p className="text-xs text-warning">Tier benefits are temporarily suspended on this account.</p> : null}

      {summary.activeEntitlementsSummary.length > 0 ? (
        <div>
          <span className="block text-xs font-medium text-text-secondary">By type</span>
          <ul className="mt-1 flex flex-col gap-1 text-xs text-text-secondary">
            {summary.activeEntitlementsSummary.map((line) => (
              <li key={`${line.benefitType}-${line.currency}`}>
                {line.count} {line.benefitType} · {formatAmount(line.total)} {line.currency}
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      {summary.recentRedemptions.length > 0 ? (
        <div>
          <span className="block text-xs font-medium text-text-secondary">Recent redemptions</span>
          <ul className="mt-1 flex flex-col gap-1 text-xs text-text-secondary">
            {summary.recentRedemptions.map((redemption) => (
              <li key={redemption.redemptionId}>
                {redemption.rewardName} · {redemption.status} · {formatAmount(redemption.pointsConsumed)} pts
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      <div className="flex flex-wrap gap-3 text-xs">
        <Link href={`/${tenantSlug}/customer-loyalty-points`}>Points detail</Link>
        <Link href={`/${tenantSlug}/customer-loyalty-tier`}>Tier detail</Link>
        <Link href={`/${tenantSlug}/customer-loyalty-benefits`}>Cashback &amp; vouchers</Link>
        <Link href={`/${tenantSlug}/customer-loyalty-redemptions`}>Redemption history</Link>
      </div>
    </section>
  );
}
