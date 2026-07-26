import { notFound } from "next/navigation";
import type { ReactNode } from "react";
import { isNonProductionEnvironment } from "../../../../lib/design-system/environment.ts";
import { resolveSupremeAdminAccessForRequest } from "../../../../lib/portal/resolve-supreme-admin-access.server.ts";
import { ShowcaseChromeProvider } from "./chrome-context.tsx";
import { ShowcaseNav } from "./showcase-nav.tsx";

/**
 * CargoGrid Design System Showcase (CargoGrid UI Modernization checkpoint 3) --
 * `/internal/design-system`, a new, isolated route group. Deliberately NOT nested under
 * `(supreme)`: that portal's own layout (`app/(supreme)/supreme/layout.tsx`)
 * unconditionally requires an authenticated, allowed Supreme Admin session for every
 * route beneath it, with no development-environment bypass -- reusing it here would
 * either (a) require editing that already-`VERIFIED` PLT-136 shell's own gate (a
 * behavior change to a shipped capability, out of this checkpoint's bounded scope), or
 * (b) block a local engineer with no seeded Supreme Admin account from ever seeing the
 * showcase. This layout implements exactly the access rule this checkpoint's own
 * instruction specifies instead: "only available to authorized internal users or in
 * development environments" -- reachable by anyone outside a production deployment,
 * and reachable by an authorized Supreme Admin even in production.
 *
 * Renders `notFound()` rather than a friendly "access denied" page when blocked --
 * this route's own existence is itself development-only information this checkpoint's
 * instruction says not to expose publicly, so a 404 (not a "this exists but you can't
 * see it" page) is the correct response, mirroring `resolveCommercialAccessForRequest`'s
 * own not-found convention on real tenant routes.
 *
 * Read-only, additive, and self-contained: no business logic, API, or database schema
 * changed by this checkpoint. Every business-looking value the showcase renders is
 * literal mock data (`lib/design-system/mock-business-data.ts`), never a live query.
 */
export default async function DesignSystemShowcaseLayout({ children }: { children: ReactNode }) {
  if (!isNonProductionEnvironment()) {
    const access = await resolveSupremeAdminAccessForRequest();
    if (access.status !== "allowed") {
      notFound();
    }
  }

  return (
    <ShowcaseChromeProvider>
      <header className="border-b border-[var(--ds-border)] bg-[var(--ds-surface)] px-6 py-3">
        <p className="text-sm font-semibold">CargoGrid Design System Showcase</p>
        <p className="text-xs text-[var(--ds-text-secondary)]">
          Internal reference only — real shared components, mock business data, never connected to production data.
        </p>
      </header>
      <div className="flex flex-1 flex-col gap-6 p-6 lg:flex-row">
        <ShowcaseNav />
        <main className="min-w-0 flex-1">{children}</main>
      </div>
    </ShowcaseChromeProvider>
  );
}
