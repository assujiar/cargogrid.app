import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { StatusBadge } from "../../../../components/ui/status-badge.tsx";
import { describeLoyaltyTierProgress, type CustomerPortalLoyaltyTierCard } from "../../../../server/contracts/customer-portal-loyalty-tier/customer-portal-loyalty-tier.ts";

function BenefitsList({ benefits }: { benefits: Record<string, unknown> }) {
  const entries = Object.entries(benefits);
  if (entries.length === 0) {
    return <p className="text-xs text-text-secondary">No benefits configured for this tier.</p>;
  }
  return (
    <ul className="flex flex-col gap-1 text-xs text-text-secondary">
      {entries.map(([key, value]) => (
        <li key={key}>
          <span className="font-medium text-text-primary">{key.replace(/_/g, " ")}</span>: {typeof value === "boolean" ? (value ? "Yes" : "No") : String(value)}
        </li>
      ))}
    </ul>
  );
}

function TierCard({ card }: { card: CustomerPortalLoyaltyTierCard }) {
  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-xs font-medium text-text-secondary">{card.programName}</p>
          <p className="text-lg font-semibold text-text-primary">{card.currentTierName ?? "Not yet evaluated"}</p>
        </div>
        {card.isBenefitsSuspended ? <StatusBadge tone="warning" label="Benefits on hold" /> : null}
      </div>

      <p className="text-sm text-text-secondary">{describeLoyaltyTierProgress(card)}</p>

      {card.nextTierId && !card.isBenefitsSuspended ? (
        <div className="flex flex-col gap-1">
          <div className="h-2 w-full overflow-hidden rounded-full bg-neutral-100" role="progressbar" aria-valuenow={card.computedAmount} aria-valuemin={0} aria-valuemax={card.nextTierThreshold ?? undefined}>
            <div
              className="h-full rounded-full bg-primary"
              style={{ width: `${card.nextTierThreshold && card.nextTierThreshold > 0 ? Math.min(100, (card.computedAmount / card.nextTierThreshold) * 100) : 0}%` }}
            />
          </div>
          <p className="text-xs text-text-secondary">
            {card.computedAmount.toFixed(2)} of {card.nextTierThreshold?.toFixed(2) ?? "—"} toward {card.nextTierName}
          </p>
        </div>
      ) : null}

      {card.isBenefitsSuspended ? (
        <p className="rounded-md bg-warning/10 p-2 text-xs text-warning-strong">{card.benefitsSuspendedReason}</p>
      ) : (
        <div>
          <p className="text-xs font-semibold text-text-primary">Benefits</p>
          <BenefitsList benefits={card.benefits} />
        </div>
      )}

      {card.nextReviewAt ? <p className="text-xs text-text-secondary">Next review: {new Date(card.nextReviewAt).toLocaleDateString()}</p> : null}
      {card.tierSince ? <p className="text-xs text-text-secondary">In this tier since {new Date(card.tierSince).toLocaleDateString()}</p> : null}
    </div>
  );
}

export function CustomerLoyaltyTierCards({ cards }: { cards: readonly CustomerPortalLoyaltyTierCard[] }) {
  if (cards.length === 0) {
    return <EmptyState title="No membership tier yet" description="Enroll in a loyalty program to start tracking your membership tier. Contact your account administrator or your CargoGrid representative." />;
  }
  return (
    <div className="flex flex-col gap-4">
      {cards.map((card) => (
        <TierCard key={card.loyaltyAccountId} card={card} />
      ))}
    </div>
  );
}
