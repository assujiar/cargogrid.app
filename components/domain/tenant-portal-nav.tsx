/**
 * Cross-module navigation for the Tenant Internal Portal (audit remediation A1,
 * `docs/audit/2026-09-02-independent-launch-readiness-audit.md` finding A1 --
 * "no route exists from any one staff module into any other"). Before this
 * component, `admin/layout.tsx` and `commercial/layout.tsx` each rendered only
 * their own in-module submenu, and the other 14 tenant-internal module
 * layouts (`operations`, `finance`, `hris`, `procurement`, `tickets`,
 * `helpdesk`, `knowledge-base`, `analytics`, `automation-rules`,
 * `integrations`, `reports`, `dashboards`, `saved-views`,
 * `scheduled-reports`) rendered no chrome at all -- a signed-in staff member
 * who landed in one module had no in-product way to reach any other. Every
 * one of those pages already exists and is already reachable by typing its
 * URL; this closes the *discovery* gap, not an authorization one.
 *
 * Same shared, always-rendered-links pattern as the sibling
 * `customer-portal-nav.tsx`: this is presentation only. It never decides who
 * may see a module -- that stays each module's own
 * `resolve<Module>AccessForRequest` guard (`docs/architecture/
 * 09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §2.1: "the route group itself is a UX
 * boundary only, never an authorization boundary"). A staff member who
 * clicks into a module they lack access to sees that module's own
 * access-denied render, exactly as if they had typed the URL directly.
 *
 * Order follows the Tenant Internal Portal information architecture
 * (`docs/blueprint/03_CargoGrid_UX_Data_Access_Design.md` §6): Home first,
 * then the primary business domains (Commercial, Operations, Procurement,
 * Finance, HRIS), then cross-cutting service/reporting surfaces (Tickets,
 * Helpdesk, Knowledge base, Reports, Dashboards, Saved views, Scheduled
 * reports, Analytics, Automation rules, Integrations), then Administration
 * last.
 */

import { Link } from "../ui/link.tsx";

export type TenantPortalNavCurrent =
  | "home"
  | "commercial"
  | "operations"
  | "procurement"
  | "finance"
  | "hris"
  | "tickets"
  | "helpdesk"
  | "knowledge-base"
  | "reports"
  | "dashboards"
  | "saved-views"
  | "scheduled-reports"
  | "analytics"
  | "automation-rules"
  | "integrations"
  | "admin";

const MODULES: ReadonlyArray<{ readonly key: TenantPortalNavCurrent; readonly label: string; readonly path: string }> = [
  { key: "home", label: "Home", path: "" },
  { key: "commercial", label: "Commercial", path: "/commercial/dashboard" },
  { key: "operations", label: "Operations", path: "/operations/dashboard" },
  { key: "procurement", label: "Procurement", path: "/procurement" },
  { key: "finance", label: "Finance", path: "/finance" },
  { key: "hris", label: "HRIS", path: "/hris" },
  { key: "tickets", label: "Tickets", path: "/tickets" },
  { key: "helpdesk", label: "Helpdesk", path: "/helpdesk" },
  { key: "knowledge-base", label: "Knowledge base", path: "/knowledge-base" },
  { key: "reports", label: "Reports", path: "/reports" },
  { key: "dashboards", label: "Dashboards", path: "/dashboards" },
  { key: "saved-views", label: "Saved views", path: "/saved-views" },
  { key: "scheduled-reports", label: "Scheduled reports", path: "/scheduled-reports" },
  { key: "analytics", label: "Analytics", path: "/analytics" },
  { key: "automation-rules", label: "Automation rules", path: "/automation-rules" },
  { key: "integrations", label: "Integrations", path: "/integrations" },
  { key: "admin", label: "Admin", path: "/admin" },
];

export function TenantPortalNav({ tenantSlug, current }: { readonly tenantSlug: string; readonly current: TenantPortalNavCurrent }) {
  return (
    <nav aria-label="Tenant modules" className="flex flex-wrap gap-4 text-sm">
      {MODULES.map((module) =>
        module.key === current ? (
          <span key={module.key} className="font-medium text-text-primary" aria-current="page">
            {module.label}
          </span>
        ) : (
          <Link key={module.key} href={`/${tenantSlug}${module.path}`}>
            {module.label}
          </Link>
        ),
      )}
    </nav>
  );
}
