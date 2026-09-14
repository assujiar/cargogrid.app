import { redirect } from "next/navigation";
import type { ReactNode } from "react";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import { resolveSignedInUserLabelForRequest } from "../../../../lib/auth/resolve-signed-in-user-label.server.ts";
import { AccountMenu } from "../../../../components/layout/account-menu.tsx";
import { TenantPortalNav } from "../../../../components/domain/tenant-portal-nav.tsx";
import { TenantMain } from "../../../../components/layout/tenant-main.tsx";

/**
 * Scheduled reports module shell (audit remediation A1). Was a bare
 * `<TenantMain>` pass-through with no access check and no way to reach any
 * other module from here; now matches the guard-then-chrome shape
 * `admin/layout.tsx` and `commercial/layout.tsx` already established
 * (`docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §2.1: the route
 * group is a UX boundary only, every page nested below still enforces its
 * own RLS/RBAC independently of this guard). Reuses
 * `resolveCommercialAccessForRequest`, the same domain-agnostic "any active
 * tenant member" guard `scheduled-reports/page.tsx` itself already uses.
 */
export default async function ScheduledReportsModuleLayout({
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
            : "You don't have access to this organization's Scheduled reports workspace."}
        </p>
        <a href="/login" className="text-sm font-medium text-primary underline">
          Sign in with a different account
        </a>
      </main>
    );
  }

  const signedInUserLabel = await resolveSignedInUserLabelForRequest();

  return (
    <div className="flex min-h-screen flex-col">
      <header className="flex items-center justify-between border-b border-neutral-200 bg-neutral-50 px-6 py-3">
        <span className="text-sm font-semibold text-neutral-900">CargoGrid — {access.tenant.slug} — Scheduled reports</span>
        <div className="flex items-center gap-4">
          <TenantPortalNav tenantSlug={access.tenant.slug} current="scheduled-reports" />
          {signedInUserLabel ? <AccountMenu name={signedInUserLabel} /> : null}
        </div>
      </header>
      <TenantMain>{children}</TenantMain>
    </div>
  );
}
