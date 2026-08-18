/**
 * Shared nav affordance between the sibling customer-portal shell routes
 * (CPL-300's `customer-portal` scope-preview page, CPL-301's own
 * `customer-portal-dashboard`, CPL-309's own `customer-inventory`, and
 * CPL-310's own `customer-warehouse-orders`) -- CPL-301's own instruction:
 * "add a link/nav affordance from the existing customer-portal page... to
 * this new dashboard route, and vice versa... check whether a shared
 * layout.tsx makes sense... but do not over-engineer." A real `layout.tsx`
 * route-group restructuring would require moving CPL-300's own already-
 * `VERIFIED` page file into a new route group folder purely to share links
 * between a handful of sibling routes -- still deferred (CPL-302 onward's own
 * routes, e.g. `customer-shipments`/`customer-documents`, deliberately stay
 * standalone and do not carry this nav, per each of their own disclosed
 * precedent, so the route count under this shared shell grows slowly, not
 * per-capability). This small, reusable presentational component gets the
 * de-duplication benefit today without that risk: each page imports it and
 * passes which tab is current -- widening the `current` union and adding one
 * more tab entry (this checkpoint's own change, CPL-310) is a pure addition,
 * so `customer-portal`/`customer-portal-dashboard`/`customer-inventory`'s own
 * page files need no edit to pick up the new "Warehouse orders" link; they
 * already render whatever this component renders. CPL-310's own route
 * carries this shared nav for the same reason CPL-309's did: it is a natural
 * sibling of the account-access/dashboard/inventory screens this nav already
 * links between, not a standalone route family like customer-shipments.
 *
 * CPL-311 (`customer-invoices`, Invoice and Billing Visibility) widens the
 * `current` union again, the identical pure-addition shape CPL-310 already
 * established -- Finance's own first customer-facing surface is a natural
 * sibling of the account-access/dashboard/inventory/warehouse-orders screens
 * this nav already links between, not a standalone route family.
 *
 * CPL-312 (`customer-receipts`, Payment Visibility) widens `current` again,
 * the identical pure-addition shape -- a receipts list is a natural sibling
 * of the invoices screen it already sits beside (payment allocation/receipt
 * detail for a SPECIFIC invoice lives on that invoice's own detail page, per
 * this checkpoint's own §21 main flow, not a separate nav destination).
 *
 * CPL-313 (`customer-tickets`, Complaint and Ticket) widens `current` again,
 * the identical pure-addition shape -- HRT-287's own `customer-tickets`
 * route family already existed as a standalone route (Phase 7), but this
 * task's own explicit instruction is to "wire the customer portal nav... to
 * the existing ticket center," so this checkpoint is the FIRST to carry this
 * shared nav onto it, mirroring CPL-309..312's own "natural sibling of the
 * account-access/dashboard screens" reasoning.
 *
 * CPL-314 (`customer-profile`, Customer Profile) widens `current` again, the
 * identical pure-addition shape -- a company-profile screen is a natural
 * sibling of "Your account access" (CPL-300's own `customer-portal` scope
 * page), which this nav already links to.
 *
 * CPL-315 (`customer-portal-users`, Customer User Management) widens
 * `current` again, the identical pure-addition shape -- the "manage users"
 * screen (invite/role-change/revoke/pending-invites/access-review) is the
 * account_admin-facing counterpart to CPL-300's own `customer-portal` scope
 * page (which shows the SIGNED-IN identity's own access; this one manages
 * OTHER identities' access on the same account), so it sits beside it in the
 * same shared shell rather than becoming a standalone route family.
 *
 * CPL-316 (`customer-loyalty`, Loyalty Program and Earning) widens `current`
 * again, the identical pure-addition shape -- the FIRST-EVER Loyalty-domain
 * customer-facing screen (own enrollment + earning history), a natural
 * sibling of the account-access/dashboard/invoices screens this nav already
 * links between.
 *
 * CPL-317 (`customer-loyalty-tier`, Membership Tier) widens `current` again,
 * the identical pure-addition shape -- current tier/progress/benefits is a
 * natural sibling of CPL-316's own loyalty enrollment/earning-history screen
 * (reads the SAME app.loyalty_accounts scope, a distinct derived view over
 * it), not a standalone route family.
 *
 * CPL-318 (`customer-loyalty-points`, Points Ledger) widens `current` again,
 * the identical pure-addition shape -- point balance/ledger-history/expiry-
 * schedule is a natural sibling of CPL-316/317's own loyalty screens (reads
 * the SAME app.loyalty_accounts scope, a distinct derived view over it), not
 * a standalone route family.
 *
 * CPL-319 (`customer-loyalty-benefits`, Cashback Discount Voucher) widens
 * `current` again, the identical pure-addition shape -- the cashback/
 * discount/voucher benefit wallet is a natural sibling of CPL-316/317/318's
 * own loyalty screens (reads app.loyalty_accounts-scoped entitlements, a
 * distinct benefit type from points), not a standalone route family. The
 * FIRST route under this shared nav to carry a genuine customer-initiated
 * write (redeeming one's own voucher), still just a read-plus-action screen
 * like every sibling here.
 */

import { Link } from "../ui/link.tsx";

export function CustomerPortalNav({
  tenantSlug,
  current,
}: {
  readonly tenantSlug: string;
  readonly current: "scope" | "dashboard" | "inventory" | "warehouse-orders" | "invoices" | "receipts" | "tickets" | "profile" | "users" | "loyalty" | "loyalty-tier" | "points" | "benefits";
}) {
  return (
    <nav aria-label="Customer portal" className="flex gap-4 border-b border-neutral-200 pb-2 text-sm">
      {current === "dashboard" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Dashboard
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-portal-dashboard`}>Dashboard</Link>
      )}
      {current === "inventory" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Warehouse inventory
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-inventory`}>Warehouse inventory</Link>
      )}
      {current === "warehouse-orders" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Warehouse orders
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-warehouse-orders`}>Warehouse orders</Link>
      )}
      {current === "invoices" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Invoices &amp; billing
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-invoices`}>Invoices &amp; billing</Link>
      )}
      {current === "receipts" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Receipts
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-receipts`}>Receipts</Link>
      )}
      {current === "tickets" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Support tickets
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-tickets`}>Support tickets</Link>
      )}
      {current === "profile" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Company profile
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-profile`}>Company profile</Link>
      )}
      {current === "users" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Manage users
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-portal-users`}>Manage users</Link>
      )}
      {current === "loyalty" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Loyalty program
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-loyalty`}>Loyalty program</Link>
      )}
      {current === "loyalty-tier" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Membership tier
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-loyalty-tier`}>Membership tier</Link>
      )}
      {current === "points" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Points balance
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-loyalty-points`}>Points balance</Link>
      )}
      {current === "benefits" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Cashback &amp; vouchers
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-loyalty-benefits`}>Cashback &amp; vouchers</Link>
      )}
      {current === "scope" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Your account access
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-portal`}>Your account access</Link>
      )}
    </nav>
  );
}
