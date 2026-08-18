import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import {
  describeLoyaltyEarningBasis,
  type CustomerPortalLoyaltyAccount,
  type CustomerPortalLoyaltyEarningEvent,
  type LoyaltyAccountStatus,
} from "../../../../server/contracts/customer-portal-loyalty-program/customer-portal-loyalty-program.ts";

const ACCOUNT_STATUS_TONE: Record<LoyaltyAccountStatus, StatusTone> = { active: "success", suspended: "warning", closed: "neutral" };

export function CustomerLoyaltyAccountsPanel({ accounts }: { accounts: readonly CustomerPortalLoyaltyAccount[] }) {
  if (accounts.length === 0) {
    return <EmptyState title="Not enrolled in a loyalty program yet" description="Contact your account administrator or your CargoGrid representative to join a loyalty program." />;
  }
  return (
    <div className="flex flex-col gap-3">
      {accounts.map((account) => (
        <div key={account.id} className="rounded-md border border-neutral-200 p-4">
          <div className="flex items-center justify-between gap-2">
            <p className="text-sm font-semibold text-text-primary">{account.programName}</p>
            <StatusBadge tone={ACCOUNT_STATUS_TONE[account.status]} label={account.status} />
          </div>
          <p className="text-xs text-text-secondary">Enrolled {new Date(account.enrolledAt).toLocaleDateString()}</p>
        </div>
      ))}
    </div>
  );
}

function formatAmount(event: CustomerPortalLoyaltyEarningEvent): string {
  const magnitude = event.rewardType === "points" ? `${event.amount} pts` : event.amount.toFixed(2);
  return event.amount < 0 ? `-${magnitude.replace("-", "")}` : magnitude;
}

export function CustomerLoyaltyEarningHistoryPanel({ events }: { events: readonly CustomerPortalLoyaltyEarningEvent[] }) {
  if (events.length === 0) {
    return <EmptyState title="No earning history yet" description="Points and cashback you earn on paid invoices will appear here." />;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">Your loyalty earning history</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">Program</th>
            <th className="p-2 text-right">Amount</th>
            <th className="p-2">Why</th>
            <th className="p-2">Date</th>
          </tr>
        </thead>
        <tbody>
          {events.map((event) => (
            <tr key={event.id} className="border-t border-neutral-100">
              <td className="p-2">{event.programName}</td>
              <td className={`p-2 text-right tabular-nums ${event.amount < 0 ? "text-danger" : "text-success"}`}>{formatAmount(event)}</td>
              <td className="p-2 text-xs text-text-secondary">
                {event.correctsEventId ? (event.reason ?? "A previous earning entry was reversed.") : describeLoyaltyEarningBasis(event.earningBasis, event.rewardType, event.rate)}
              </td>
              <td className="p-2 text-xs text-text-secondary">{new Date(event.createdAt).toLocaleDateString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
