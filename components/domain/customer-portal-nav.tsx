/**
 * Shared nav affordance between the two sibling customer-portal shell routes
 * (CPL-300's `customer-portal` scope-preview page and CPL-301's own
 * `customer-portal-dashboard`) -- CPL-301's own instruction: "add a link/nav
 * affordance from the existing customer-portal page... to this new dashboard
 * route, and vice versa... check whether a shared layout.tsx makes sense...
 * but do not over-engineer." A real `layout.tsx` route-group restructuring
 * would require moving CPL-300's own already-`VERIFIED` page file into a new
 * route group folder purely to share two links between exactly two sibling
 * routes -- deferred until a third Phase 8 route under this same directory
 * tree makes a real shared shell clearly worth the structural change (Prompt
 * 309 onward will add more). This small, reusable presentational component
 * gets the de-duplication benefit today without that risk: both pages import
 * it and pass which tab is current.
 */

import { Link } from "../ui/link.tsx";

export function CustomerPortalNav({ tenantSlug, current }: { readonly tenantSlug: string; readonly current: "scope" | "dashboard" }) {
  return (
    <nav aria-label="Customer portal" className="flex gap-4 border-b border-neutral-200 pb-2 text-sm">
      {current === "dashboard" ? (
        <span className="font-medium text-text-primary" aria-current="page">
          Dashboard
        </span>
      ) : (
        <Link href={`/${tenantSlug}/customer-portal-dashboard`}>Dashboard</Link>
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
