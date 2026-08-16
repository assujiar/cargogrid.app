import { Card } from "../../../../components/ui/card.tsx";
import { StatusBadge } from "../../../../components/ui/status-badge.tsx";
import { Link } from "../../../../components/ui/link.tsx";
import {
  parseAccountsCardSummary,
  parseWarehouseInventoryCardSummary,
  parseTicketsCardSummary,
  type CustomerPortalDashboardCard,
  type DashboardCardKey,
} from "../../../../server/contracts/customer-portal-dashboard/customer-portal-dashboard.ts";

/**
 * The dashboard card grid (CPL-301). Every card renders independently from
 * its OWN already-fetched row -- one card's own `available: false` or
 * `degraded: true` never affects how any sibling card renders (source
 * prompt §22: "preserving other cards"). No card here ever fetches its own
 * data client-side; the entire 9-row summary already arrived as one atomic,
 * server-side RPC call (the page's own job), so there is no per-card
 * network "loading" state to model here -- the route's own `loading.tsx`
 * covers the single page-level load.
 */

const CARD_TITLES: Record<DashboardCardKey, string> = {
  accounts: "Your accounts",
  warehouse_inventory: "Warehouse & inventory",
  tickets: "Support tickets",
  bookings: "Bookings",
  shipments: "Shipments",
  invoices: "Invoices",
  payments: "Payments",
  loyalty: "Loyalty",
  alerts: "Alerts",
};

/** Fixed, deliberate display order -- independent of whatever order the RPC's own VALUES list happens to return (never assumed stable). */
const CARD_ORDER: DashboardCardKey[] = ["accounts", "bookings", "shipments", "warehouse_inventory", "invoices", "payments", "tickets", "loyalty", "alerts"];

function formatCount(count: number, capped: boolean): string {
  return capped ? `${count}+` : `${count}`;
}

function formatAsOf(sourceUpdatedAt: string | null): string | null {
  if (!sourceUpdatedAt) return null;
  const parsed = new Date(sourceUpdatedAt);
  if (Number.isNaN(parsed.getTime())) return null;
  return `As of ${parsed.toLocaleString()}`;
}

function DetailLink({ tenantSlug, card }: { readonly tenantSlug: string; readonly card: CustomerPortalDashboardCard }) {
  // Business rule (source prompt §24/§15): a dashboard card never renders a
  // dead action. When no real route exists yet (detailPath === null), this
  // renders nothing at all -- never a disabled-looking link and never a
  // link to a route that does not exist.
  if (!card.detailPath) return null;
  return (
    <Link href={`/${tenantSlug}/${card.detailPath}`} className="text-xs font-medium">
      View details
    </Link>
  );
}

function AccountsCardBody({ card }: { readonly card: CustomerPortalDashboardCard }) {
  const summary = parseAccountsCardSummary(card.summary);
  return (
    <div className="flex flex-col gap-1">
      <p className="text-2xl font-semibold text-text-primary">{summary.activeAccountCount}</p>
      <p className="text-xs text-text-secondary">active account{summary.activeAccountCount === 1 ? "" : "s"} you can act within</p>
      {summary.primaryAccountName ? <p className="text-xs text-text-secondary">Primary: {summary.primaryAccountName}</p> : null}
    </div>
  );
}

function WarehouseInventoryCardBody({ card }: { readonly card: CustomerPortalDashboardCard }) {
  const summary = parseWarehouseInventoryCardSummary(card.summary);
  return (
    <div className="flex flex-col gap-2">
      <div>
        <p className="text-2xl font-semibold text-text-primary">{formatCount(summary.openOutboundOrderCount, summary.openOutboundOrderCountCapped)}</p>
        <p className="text-xs text-text-secondary">open outbound order{summary.openOutboundOrderCount === 1 && !summary.openOutboundOrderCountCapped ? "" : "s"}</p>
      </div>
      <div>
        <p className="text-lg font-semibold text-text-primary">{formatCount(summary.activeInventoryBalanceCount, summary.activeInventoryBalanceCountCapped)}</p>
        <p className="text-xs text-text-secondary">active inventory balance{summary.activeInventoryBalanceCount === 1 && !summary.activeInventoryBalanceCountCapped ? "" : "s"}</p>
      </div>
    </div>
  );
}

function TicketsCardBody({ card }: { readonly card: CustomerPortalDashboardCard }) {
  const summary = parseTicketsCardSummary(card.summary);
  return (
    <div className="flex flex-col gap-1">
      <p className="text-2xl font-semibold text-text-primary">{formatCount(summary.openTicketCount, summary.openTicketCountCapped)}</p>
      <p className="text-xs text-text-secondary">open support ticket{summary.openTicketCount === 1 && !summary.openTicketCountCapped ? "" : "s"}</p>
    </div>
  );
}

const REAL_CARD_BODIES: Partial<Record<DashboardCardKey, (props: { card: CustomerPortalDashboardCard }) => React.JSX.Element>> = {
  accounts: AccountsCardBody,
  warehouse_inventory: WarehouseInventoryCardBody,
  tickets: TicketsCardBody,
};

function DashboardCardTile({ tenantSlug, card }: { readonly tenantSlug: string; readonly card: CustomerPortalDashboardCard }) {
  const asOf = formatAsOf(card.sourceUpdatedAt);
  const Body = REAL_CARD_BODIES[card.cardKey];

  return (
    <Card
      title={
        <div className="flex items-center justify-between gap-2">
          <span>{CARD_TITLES[card.cardKey]}</span>
          {card.degraded ? <StatusBadge tone="warning" label="Degraded" /> : null}
        </div>
      }
      className="flex flex-col gap-3"
    >
      {!card.available ? (
        <div className="flex flex-col gap-1">
          <p className="text-sm text-text-secondary">This area is launching soon.</p>
        </div>
      ) : card.degraded ? (
        <div className="flex flex-col gap-2">
          <p className="text-sm text-text-secondary">This section could not load just now. The rest of your dashboard is unaffected -- try again shortly.</p>
        </div>
      ) : Body ? (
        <Body card={card} />
      ) : null}

      <div className="mt-auto flex items-center justify-between gap-2">
        {asOf && card.available && !card.degraded ? <span className="text-xs text-text-secondary">{asOf}</span> : <span />}
        <DetailLink tenantSlug={tenantSlug} card={card} />
      </div>
    </Card>
  );
}

export function CustomerPortalDashboardCards({ tenantSlug, cards }: { readonly tenantSlug: string; readonly cards: readonly CustomerPortalDashboardCard[] }) {
  const byKey = new Map(cards.map((card) => [card.cardKey, card]));

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {CARD_ORDER.map((key) => {
        const card = byKey.get(key);
        // Defense in depth only -- app.get_customer_portal_dashboard_summary
        // always returns exactly these 9 card_keys (db-tested), so this
        // branch is not expected to be reached in production. If a future
        // migration ever changes the card set without this UI being
        // updated in lockstep, degrade to the same honest "launching soon"
        // shape rather than a blank grid cell.
        const fallback: CustomerPortalDashboardCard = { cardKey: key, available: false, sourceUpdatedAt: null, degraded: false, summary: {}, detailPath: null };
        return <DashboardCardTile key={key} tenantSlug={tenantSlug} card={card ?? fallback} />;
      })}
    </div>
  );
}
