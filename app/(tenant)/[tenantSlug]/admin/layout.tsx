import { redirect } from "next/navigation";
import type { ReactNode } from "react";
import { resolveTenantAdminAccessForRequest } from "../../../../lib/portal/resolve-tenant-admin-access.server.ts";

/**
 * Tenant Admin portal shell (PLT-135, CG-S6-PLT-032). Every request through this route
 * segment passes through `resolveTenantAdminAccess` first -- the route group itself is
 * a UX boundary only, never an authorization boundary
 * (`docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §2.1's guardrail, restated);
 * every page nested under this layout still relies on its own query/mutation's own
 * RLS/RBAC, this guard only decides whether the shell renders at all.
 *
 * States rendered here (Prompt 135 §23, `docs/standards/DESIGN_SYSTEM.md` §4):
 * unauthenticated -> redirect to sign-in (not a page render); tenant_not_found_or_not_member
 * / tenant_suspended / forbidden -> a distinct denied page, never leaking which case it
 * is beyond what the viewer is already entitled to know (§16: "no hidden impersonation
 * or client authorization," extended here to not confirming/denying tenant existence).
 */
export default async function TenantAdminLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ tenantSlug: string }>;
}) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);

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
            : "You don't have access to this organization's admin area."}
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
        <span className="text-sm font-semibold text-neutral-900">CargoGrid — {access.tenant.slug}</span>
        <nav aria-label="Admin navigation" className="flex gap-4 text-sm">
          <a href={`/${access.tenant.slug}/admin`} className="text-neutral-700 hover:text-neutral-900">
            Home
          </a>
          <a href={`/${access.tenant.slug}/admin/users`} className="text-neutral-700 hover:text-neutral-900">
            Users
          </a>
        </nav>
      </header>
      <main className="flex-1 px-6 py-6">{children}</main>
    </div>
  );
}
