import { redirect } from "next/navigation";
import type { ReactNode } from "react";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import { resolveSignedInUserLabelForRequest } from "../../../../lib/auth/resolve-signed-in-user-label.server.ts";
import { AccountMenu } from "../../../../components/layout/account-menu.tsx";
import { TenantPortalNav } from "../../../../components/domain/tenant-portal-nav.tsx";
import { Link } from "../../../../components/ui/link.tsx";

/**
 * Commercial portal shell (COM-143, CG-S7-COM-002) -- the first business-domain route
 * segment in this repository (`app/(tenant)/[tenantSlug]/commercial/`, previously
 * confirmed not to exist anywhere in Platform Core). Every request passes through
 * `resolveCommercialAccess` first -- the route group itself is a UX boundary only,
 * never an authorization boundary (`docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md`
 * §2.1's guardrail, restated from `tenant-admin/layout.tsx`); every page nested under
 * this layout still relies on its own query/mutation's own RLS/RBAC, this guard only
 * decides whether the shell renders at all.
 *
 * States rendered here (`docs/standards/DESIGN_SYSTEM.md` §4), identical structure to
 * the Tenant Admin portal's own layout: unauthenticated -> redirect to sign-in;
 * tenant_not_found_or_not_member / tenant_suspended / forbidden -> a distinct denied
 * page, never leaking which case it is beyond what the viewer already knows.
 */
export default async function CommercialLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ tenantSlug: string }>;
}) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <main id="main-content" tabIndex={-1} className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-3 px-4 text-center">
        <h1 className="text-xl font-semibold text-neutral-900">Access denied</h1>
        <p className="text-sm text-neutral-600">
          {access.status === "tenant_suspended"
            ? "This organization's account is currently suspended."
            : "You don't have access to this organization's Commercial workspace."}
        </p>
        <Link href="/login" className="text-sm font-medium text-primary underline">
          Sign in with a different account
        </Link>
      </main>
    );
  }

  /** `ISS-2026-246`: presentation-only, resolved after the guard already allowed the render. */
  const signedInUserLabel = await resolveSignedInUserLabelForRequest();

  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b border-neutral-200 bg-neutral-50">
        <div className="flex items-center justify-between px-6 py-3">
        <span className="text-sm font-semibold text-neutral-900">CargoGrid — {access.tenant.slug} — Commercial</span>
        <div className="flex items-center gap-4">
          <TenantPortalNav tenantSlug={access.tenant.slug} current="commercial" />
          {signedInUserLabel ? <AccountMenu name={signedInUserLabel} /> : null}
        </div>
        </div>
        <nav aria-label="Commercial navigation" className="flex flex-wrap gap-4 border-t border-neutral-200 px-6 py-2 text-sm">
          <Link href={`/${access.tenant.slug}/commercial/dashboard`} className="text-neutral-700 hover:text-neutral-900">
            Dashboard
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/reports`} className="text-neutral-700 hover:text-neutral-900">
            Reports
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/leads`} className="text-neutral-700 hover:text-neutral-900">
            Leads
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/prospects`} className="text-neutral-700 hover:text-neutral-900">
            Prospects
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/contacts`} className="text-neutral-700 hover:text-neutral-900">
            Contacts
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/pipeline`} className="text-neutral-700 hover:text-neutral-900">
            Pipeline
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/opportunities`} className="text-neutral-700 hover:text-neutral-900">
            Opportunities
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/rates`} className="text-neutral-700 hover:text-neutral-900">
            Rates
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/quotations`} className="text-neutral-700 hover:text-neutral-900">
            Quotations
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/accounts`} className="text-neutral-700 hover:text-neutral-900">
            Accounts
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/contracts`} className="text-neutral-700 hover:text-neutral-900">
            Contracts
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/margin-rules`} className="text-neutral-700 hover:text-neutral-900">
            Margin Rules
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/approval-rules`} className="text-neutral-700 hover:text-neutral-900">
            Approval Rules
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/approvals`} className="text-neutral-700 hover:text-neutral-900">
            Approvals
          </Link>
          <Link href={`/${access.tenant.slug}/commercial/credit-approvals`} className="text-neutral-700 hover:text-neutral-900">
            Credit Approvals
          </Link>
        </nav>
      </header>
      <main id="main-content" tabIndex={-1} className="flex-1 px-6 py-6">
        {children}
      </main>
    </div>
  );
}
