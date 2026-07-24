import { redirect } from "next/navigation";
import type { ReactNode } from "react";
import { resolveSupremeAdminAccessForRequest } from "../../../lib/portal/resolve-supreme-admin-access.server.ts";
import { Banner } from "../../../components/ui/banner.tsx";

/**
 * Supreme Admin portal shell (PLT-136, CG-S6-PLT-033). Every request through this
 * route segment passes through `resolveSupremeAdminAccessForRequest` first -- the
 * route group itself is a UX boundary only, never an authorization boundary
 * (`docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §2.1's guardrail).
 *
 * The persistent banner below is the real, structural RPD-022 disclosure Prompt 136
 * §18/§24 require -- "disclosing Supreme can also alter audit itself," "must not
 * pretend immutable/tamper-proof evidence" (the same exception `AGENTS.md`'s own
 * "Supreme Admin risk rule" names): rendered on every page in this portal, not a
 * one-time dismissible notice a returning Supreme Admin would stop seeing.
 *
 * Deliberately CargoGrid-branded only, never tenant-branded (CargoGrid Design System
 * Expansion, `docs/adr/ADR-0017` §4) -- this shell must NOT import `lib/theme/
 * resolve-portal-theme.ts` or any tenant-brand resolution. Tenant branding may only
 * appear in a future tenant-scoped preview/detail context nested inside this portal
 * (not built yet, see `docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md`), never in
 * this file's own chrome.
 */
export default async function SupremeLayout({ children }: { children: ReactNode }) {
  const access = await resolveSupremeAdminAccessForRequest();

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-3 px-4 text-center">
        <h1 className="text-xl font-semibold text-neutral-900">Access denied</h1>
        <p className="text-sm text-neutral-600">You don&apos;t have access to the CargoGrid control plane.</p>
        <a href="/login" className="text-sm font-medium text-primary underline">
          Sign in with a different account
        </a>
      </main>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <header className="flex items-center justify-between border-b border-neutral-200 bg-neutral-50 px-6 py-3">
        <span className="text-sm font-semibold text-neutral-900">CargoGrid — Control Plane</span>
        <nav aria-label="Supreme navigation" className="flex gap-4 text-sm">
          <a href="/supreme" className="text-neutral-700 hover:text-neutral-900">
            Home
          </a>
          <a href="/supreme/tenants" className="text-neutral-700 hover:text-neutral-900">
            Tenants
          </a>
        </nav>
      </header>
      <Banner variant="warning">
        Supreme Admin holds absolute CRUD authority, including over audit and ledger records (RPD-022). No action in this
        portal is tamper-proof or immutable — every privileged view, change, and override is still attributed and recorded.
      </Banner>
      <main className="flex-1 px-6 py-6">{children}</main>
    </div>
  );
}
