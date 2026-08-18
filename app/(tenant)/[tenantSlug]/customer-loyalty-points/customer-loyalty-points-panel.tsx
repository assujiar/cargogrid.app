import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { StatusBadge } from "../../../../components/ui/status-badge.tsx";
import { describeLoyaltyPointExpiry, type CustomerPortalLoyaltyPointBalance, type CustomerPortalLoyaltyPointLedgerEntry, type CustomerPortalLoyaltyPointExpiryScheduleEntry } from "../../../../server/contracts/customer-portal-loyalty-points/customer-portal-loyalty-points.ts";

const EVENT_TONE = {
  earn: "success",
  reversal: "neutral",
  expiry: "warning",
  adjustment: "neutral",
  redemption: "neutral",
} as const;

function BalanceCard({ balance }: { balance: CustomerPortalLoyaltyPointBalance }) {
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <p className="text-xs font-medium text-text-secondary">{balance.programName}</p>
      <p className="text-2xl font-semibold text-text-primary">{balance.available.toFixed(0)} points</p>
      <p className="text-xs text-text-secondary">
        {balance.totalEarned.toFixed(0)} earned lifetime, {balance.totalConsumed.toFixed(0)} used
      </p>
    </div>
  );
}

function LedgerHistory({ entries }: { entries: readonly CustomerPortalLoyaltyPointLedgerEntry[] }) {
  if (entries.length === 0) {
    return <p className="text-xs text-text-secondary">No point activity yet.</p>;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">Point ledger history</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">Program</th>
            <th className="p-2">Type</th>
            <th className="p-2">Description</th>
            <th className="p-2 text-right">Points</th>
            <th className="p-2">Date</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((entry) => (
            <tr key={entry.id} className="border-t border-neutral-100">
              <td className="p-2">{entry.programName}</td>
              <td className="p-2">
                <StatusBadge tone={EVENT_TONE[entry.eventType] ?? "neutral"} label={entry.eventType} />
              </td>
              <td className="p-2 text-text-secondary">{entry.description}</td>
              <td className={`p-2 text-right tabular-nums ${entry.amount >= 0 ? "text-success" : "text-text-secondary"}`}>
                {entry.amount >= 0 ? "+" : ""}
                {entry.amount.toFixed(0)}
              </td>
              <td className="p-2 text-xs text-text-secondary">{new Date(entry.createdAt).toLocaleDateString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function ExpirySchedule({ schedule }: { schedule: readonly CustomerPortalLoyaltyPointExpiryScheduleEntry[] }) {
  if (schedule.length === 0) {
    return <p className="text-xs text-text-secondary">No points currently scheduled to expire.</p>;
  }
  return (
    <ul className="flex flex-col gap-1 text-sm text-text-secondary">
      {schedule.map((entry) => (
        <li key={entry.id}>{describeLoyaltyPointExpiry(entry)}</li>
      ))}
    </ul>
  );
}

export function CustomerLoyaltyPointsPanel({
  balances,
  ledgerEntries,
  expirySchedule,
}: {
  balances: readonly CustomerPortalLoyaltyPointBalance[];
  ledgerEntries: readonly CustomerPortalLoyaltyPointLedgerEntry[];
  expirySchedule: readonly CustomerPortalLoyaltyPointExpiryScheduleEntry[];
}) {
  if (balances.length === 0) {
    return <EmptyState title="No points balance yet" description="Enroll in a loyalty program to start earning points. Contact your account administrator or your CargoGrid representative." />;
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-4 sm:flex-row">
        {balances.map((balance) => (
          <BalanceCard key={balance.loyaltyAccountId} balance={balance} />
        ))}
      </div>

      <section aria-labelledby="points-expiry-heading" className="flex flex-col gap-2">
        <h2 id="points-expiry-heading" className="text-sm font-semibold text-text-primary">
          Upcoming expirations
        </h2>
        <ExpirySchedule schedule={expirySchedule} />
      </section>

      <section aria-labelledby="points-history-heading" className="flex flex-col gap-2">
        <h2 id="points-history-heading" className="text-sm font-semibold text-text-primary">
          Ledger history
        </h2>
        <LedgerHistory entries={ledgerEntries} />
      </section>
    </div>
  );
}
