import { redirect } from "next/navigation";
import type { ReactNode } from "react";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";

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
      <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-3 px-4 text-center">
        <h1 className="text-xl font-semibold text-neutral-900">Access denied</h1>
        <p className="text-sm text-neutral-600">
          {access.status === "tenant_suspended"
            ? "This organization's account is currently suspended."
            : "You don't have access to this organization's Commercial workspace."}
        </p>
        <a href="/login" className="text-sm font-medium text-primary underline">
          Sign in with a different account
        </a>
      </main>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <header className="flex items-center justify-between border-b border-neutral-200 bg-neutral-50 px-6 py-3">
        <span className="text-sm font-semibold text-neutral-900">CargoGrid — {access.tenant.slug} — Commercial</span>
        <nav aria-label="Commercial navigation" className="flex gap-4 text-sm">
          <a href={`/${access.tenant.slug}/commercial/leads`} className="text-neutral-700 hover:text-neutral-900">
            Leads
          </a>
          <a href={`/${access.tenant.slug}/commercial/prospects`} className="text-neutral-700 hover:text-neutral-900">
            Prospects
          </a>
          <a href={`/${access.tenant.slug}/commercial/contacts`} className="text-neutral-700 hover:text-neutral-900">
            Contacts
          </a>
          <a href={`/${access.tenant.slug}/commercial/pipeline`} className="text-neutral-700 hover:text-neutral-900">
            Pipeline
          </a>
          <a href={`/${access.tenant.slug}/commercial/opportunities`} className="text-neutral-700 hover:text-neutral-900">
            Opportunities
          </a>
        </nav>
      </header>
      <main className="flex-1 px-6 py-6">{children}</main>
    </div>
  );
}
