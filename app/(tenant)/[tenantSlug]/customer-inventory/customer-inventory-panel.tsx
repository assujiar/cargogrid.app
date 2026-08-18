import { Link } from "../../../../components/ui/link.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { CustomerPortalInventoryBalance, CustomerPortalWarehouseEligibility } from "../../../../server/contracts/customer-portal-inventory/customer-portal-inventory.ts";
import type { CustomerPortalScopeContextRow } from "../../../../server/contracts/customer-portal-scope/customer-portal-scope.ts";

const BALANCE_STATUS_TONE: Record<string, StatusTone> = {
  on_hand: "success",
  held: "warning",
  damaged: "danger",
  expired: "danger",
};

const BALANCE_STATUS_LABEL: Record<string, string> = {
  on_hand: "On hand",
  held: "Held",
  damaged: "Damaged",
  expired: "Expired",
};

const ELIGIBILITY_STATUS_TONE: Record<string, StatusTone> = {
  active: "success",
  revoked: "danger",
};

/**
 * `warehouse_id`/`location_id`/`item_master_id` carry no customer-facing name
 * anywhere in this migration's own projection (mirrors ATW-023's identical
 * column set -- design decision 3 of the migration's own header). Showing the
 * raw id, shortened for readability, is the deliberate, safe choice here, not
 * a placeholder: Business rule 3 ("Location detail must not expose internal
 * warehouse layout beyond approved customer-safe level") means a raw opaque
 * id is exactly the right amount of detail -- resolving it to a real rack/bin
 * code or warehouse name is out of this capability's own bounded scope (no
 * such name-lookup RPC exists yet for a customer-portal caller).
 */
function shortId(id: string): string {
  return id.slice(0, 8);
}

/**
 * Aging/freshness (source prompt §22 Alternative flow), derived entirely from
 * the row's own real `updatedAt` -- never a fabricated separate source-version
 * field. `nowIso` is the SAME timestamp the page's own freshness banner uses
 * (both computed once, server-side, at request time), so a row's own "just
 * now" and the banner's own "as of" never drift relative to each other.
 */
function formatAge(updatedAt: string, nowIso: string): string {
  const updated = new Date(updatedAt).getTime();
  const now = new Date(nowIso).getTime();
  if (Number.isNaN(updated) || Number.isNaN(now)) return "—";
  const diffMs = Math.max(0, now - updated);
  const minutes = Math.floor(diffMs / 60_000);
  if (minutes < 1) return "Just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  const months = Math.floor(days / 30);
  return `${months}mo ago`;
}

function BalanceRow({ balance, accountName, nowIso }: { balance: CustomerPortalInventoryBalance; accountName: string; nowIso: string }) {
  return (
    <tr className="border-t border-neutral-100">
      <td className="p-2 font-mono text-xs text-neutral-900" title={balance.itemMasterId}>
        {shortId(balance.itemMasterId)}
      </td>
      <td className="p-2 text-xs text-neutral-500">{balance.lotNumber ?? balance.serialNumber ?? "—"}</td>
      <td className="p-2 text-xs text-neutral-500">{accountName}</td>
      <td className="p-2 font-mono text-xs text-neutral-500" title={balance.warehouseId}>
        {shortId(balance.warehouseId)}
      </td>
      <td className="p-2 font-mono text-xs text-neutral-500" title={balance.locationId}>
        {shortId(balance.locationId)}
      </td>
      <td className="p-2 text-sm">
        <StatusBadge tone={BALANCE_STATUS_TONE[balance.status] ?? "neutral"} label={BALANCE_STATUS_LABEL[balance.status] ?? balance.status} />
      </td>
      <td className="p-2 text-right text-sm tabular-nums">{balance.onHand}</td>
      <td className="p-2 text-right text-sm tabular-nums">{balance.reserved}</td>
      <td className="p-2 text-right text-sm tabular-nums">{balance.held}</td>
      <td className="p-2 text-right text-sm font-medium tabular-nums">{balance.available}</td>
      <td className="p-2 text-xs text-neutral-500">{formatAge(balance.updatedAt, nowIso)}</td>
    </tr>
  );
}

export function CustomerInventoryPanel({
  tenantSlug,
  accounts,
  eligibility,
  balances,
  warehouseId,
  generatedAt,
}: {
  tenantSlug: string;
  accounts: readonly CustomerPortalScopeContextRow[];
  eligibility: readonly CustomerPortalWarehouseEligibility[];
  balances: readonly CustomerPortalInventoryBalance[];
  warehouseId: string;
  generatedAt: string;
}) {
  const accountNameById = new Map(accounts.map((a) => [a.accountId, a.accountName]));
  const distinctWarehouseIds = Array.from(new Set(eligibility.map((e) => e.warehouseId)));

  return (
    <div className="flex flex-col gap-4">
      {/* Freshness banner (source prompt §22 Alternative flow): every RPC below
          reads app.inventory_balances live, on every request -- there is no
          persisted cache to go "stale," so the honest freshness signal is the
          request's own timestamp plus each row's own real updated_at (aging),
          never a fabricated separate source-version field. */}
      <div role="status" className="rounded-md border border-info/30 bg-info/10 p-3 text-xs text-neutral-700">
        Live WMS data as of {new Date(generatedAt).toLocaleString()}. Revoking warehouse access takes effect immediately on your next view.
      </div>

      <form method="get" className="flex flex-wrap items-end gap-3 rounded-md border border-neutral-200 p-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="warehouseId" className="text-xs font-medium text-neutral-600">
            Warehouse
          </label>
          <select id="warehouseId" name="warehouseId" defaultValue={warehouseId} className="rounded border border-neutral-300 px-2 py-1 text-sm">
            <option value="">All eligible warehouses</option>
            {distinctWarehouseIds.map((id) => (
              <option key={id} value={id}>
                WH-{shortId(id)}
              </option>
            ))}
          </select>
        </div>
        <button type="submit" className="rounded bg-primary px-3 py-1.5 text-sm font-medium text-neutral-50">
          Apply filter
        </button>
        <Link href={`/${tenantSlug}/customer-inventory`} className="text-xs text-neutral-500 underline">
          Clear filter
        </Link>
      </form>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Your warehouse access</h2>
        {eligibility.length === 0 ? (
          <EmptyState title="No warehouse access yet" description="Once your account is granted access to a warehouse, it will appear here and its stock will become visible below." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Warehouse</th>
                  <th className="p-2">Account</th>
                  <th className="p-2">Status</th>
                  <th className="p-2">Granted</th>
                  <th className="p-2">Revoked reason</th>
                </tr>
              </thead>
              <tbody>
                {eligibility.map((grant) => (
                  <tr key={grant.id} className="border-t border-neutral-100">
                    <td className="p-2 font-mono text-xs text-neutral-900" title={grant.warehouseId}>
                      WH-{shortId(grant.warehouseId)}
                    </td>
                    <td className="p-2 text-xs text-neutral-500">{accountNameById.get(grant.customerAccountId) ?? "—"}</td>
                    <td className="p-2 text-sm">
                      <StatusBadge tone={ELIGIBILITY_STATUS_TONE[grant.status] ?? "neutral"} label={grant.status === "active" ? "Active" : "Revoked"} />
                    </td>
                    <td className="p-2 text-xs text-neutral-500">{new Date(grant.grantedAt).toLocaleDateString()}</td>
                    <td className="p-2 text-xs text-neutral-500">{grant.revokedReason ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Stock on hand</h2>
        {balances.length === 0 ? (
          <EmptyState
            title="No inventory found"
            description={
              warehouseId
                ? "No stock matches this warehouse filter right now. It may have zero balance, or your access to it may have been revoked."
                : "Stock WMS reports for your own accounts, in warehouses you're eligible to view, will appear here."
            }
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Item</th>
                  <th className="p-2">Lot / serial</th>
                  <th className="p-2">Account</th>
                  <th className="p-2">Warehouse</th>
                  <th className="p-2">Location</th>
                  <th className="p-2">Status</th>
                  <th className="p-2 text-right">On hand</th>
                  <th className="p-2 text-right">Reserved</th>
                  <th className="p-2 text-right">Held</th>
                  <th className="p-2 text-right">Available</th>
                  <th className="p-2">Updated</th>
                </tr>
              </thead>
              <tbody>
                {balances.map((balance) => (
                  <BalanceRow key={balance.id} balance={balance} accountName={accountNameById.get(balance.ownerAccountId) ?? "—"} nowIso={generatedAt} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
