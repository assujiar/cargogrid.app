/**
 * Shared nav affordance between the sibling customer-portal shell routes
 * (CPL-300's `customer-portal` scope-preview page, CPL-301's own
 * `customer-portal-dashboard`, and CPL-309's own `customer-inventory`) --
 * CPL-301's own instruction: "add a link/nav affordance from the existing
 * customer-portal page... to this new dashboard route, and vice versa...
 * check whether a shared layout.tsx makes sense... but do not over-engineer."
 * A real `layout.tsx` route-group restructuring would require moving CPL-300's
 * own already-`VERIFIED` page file into a new route group folder purely to
 * share links between a handful of sibling routes -- still deferred (CPL-302
 * onward's own routes, e.g. `customer-shipments`/`customer-documents`,
 * deliberately stay standalone and do not carry this nav, per each of their
 * own disclosed precedent, so the route count under this shared shell grows
 * slowly, not per-capability). This small, reusable presentational component
 * gets the de-duplication benefit today without that risk: each page imports
 * it and passes which tab is current -- widening the `current` union and
 * adding one more tab entry (this checkpoint's own change) is a pure
 * addition, so `customer-portal`/`customer-portal-dashboard`'s own page
 * files need no edit to pick up the new "Warehouse inventory" link; they
 * already render whatever this component renders.
 */

import { Link } from "../ui/link.tsx";

export function CustomerPortalNav({ tenantSlug, current }: { readonly tenantSlug: string; readonly current: "scope" | "dashboard" | "inventory" }) {
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
