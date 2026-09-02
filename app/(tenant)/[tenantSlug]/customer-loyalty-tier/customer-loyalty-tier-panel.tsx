import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { Progress } from "../../../../components/ui/progress.tsx";
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

/**
 * Progress toward the next tier (`ISS-2026-246`).
 *
 * This was a hand-rolled `role="progressbar"` div with an inline `style={{ width }}` fill and a
 * separate caption below it. `Progress` is that exact shape as a native `<progress>`, so the
 * bar is now real form-control semantics rather than two divs wearing an ARIA role.
 *
 * A previous pass rejected the swap on two grounds; only the first survives, and only for a case
 * that never drew a bar anyway.
 *
 *  - `max` must be a number, and `nextTierThreshold` is `number | null`. True -- but the old
 *    markup could not draw a meaningful bar in that case either: it fell through to `width: 0%`
 *    with `aria-valuemax={undefined}`, an empty rail carrying no information. So the null (and
 *    non-positive) case keeps the caption alone and no longer pretends to have a bar; every case
 *    that could ever fill produces a real `<progress>`.
 *  - "`Progress` renders its own label that would duplicate the page's more specific caption."
 *    That is an argument against rendering both, not against the component: the caption *is* the
 *    label, so it is passed as `label` and the duplicate `<p>` is gone. `Progress` adds the
 *    percentage on the right, which the hand-rolled bar encoded only in pixels.
 *
 * Reading the caption straight from the card (rather than `describeLoyaltyTierProgress`) is
 * deliberate: that helper renders the *remaining* amount in the sentence above this bar, while
 * this line has always shown progress-so-far against the threshold.
 */
function TierProgress({ card }: { card: CustomerPortalLoyaltyTierCard }) {
  // `?? ""` for the name, not `?? "the next tier"`: JSX rendered a null `nextTierName` as nothing,
  // and this string has to say what that markup said, not an improved version of it.
  const caption = `${card.computedAmount.toFixed(2)} of ${card.nextTierThreshold?.toFixed(2) ?? "—"} toward ${card.nextTierName ?? ""}`;

  if (card.nextTierThreshold === null || card.nextTierThreshold <= 0) {
    return <p className="text-xs text-text-secondary">{caption}</p>;
  }

  return <Progress value={card.computedAmount} max={card.nextTierThreshold} label={caption} />;
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

      {card.nextTierId && !card.isBenefitsSuspended ? <TierProgress card={card} /> : null}

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
