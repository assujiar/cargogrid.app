import type { ReactNode } from "react";
import { SkipToContentLink } from "../../../components/layout/skip-to-content-link.tsx";
import { ToastProvider } from "../../../components/ui/toast.tsx";

/**
 * The shared tenant shell.
 *
 * Deliberately thin: it owns the skip link, the toast viewport, and nothing else.
 *
 * `ToastProvider` (`ISS-2026-246`) is mounted here because a toast has to outlive the form that
 * raised it -- a provider inside any one panel would unmount its own confirmation the moment
 * that panel re-rendered on `revalidatePath`. This is the shallowest node that every
 * toast-raising client component in the tenant tree sits under, and it is a pure context +
 * fixed-position viewport: it renders no chrome, adds no landmark, and leaves the `<main>`
 * reasoning below exactly as it was. Public (`app/(public)/`) and Supreme (`app/(supreme)/`)
 * route groups are deliberately outside it -- neither has a consumer, and mounting a provider
 * with no caller is the orphan this issue exists to remove.
 *
 * It does **not** own a `<main>`,
 * even though `ISS-2026-241` suggests one shared `<main>` here — Next.js nests layouts
 * parent-first, so a `<main>` at this level would wrap the `<header>`/`<nav>` that
 * `admin/layout.tsx` and `commercial/layout.tsx` render for their own modules, putting site
 * navigation inside the very landmark that exists to let you skip past it. Each module owns
 * its own `<main>` instead, via `components/layout/tenant-main.tsx`, placed after that
 * module's own chrome. See that component's header for the full reasoning.
 *
 * It also does **no authorization**. Every route below this point already resolves its own
 * access (`resolveTenantAdminAccessForRequest`, `resolveCustomerPortalScope`, or its own
 * query's RLS), and adding a second, weaker check here would invite the assumption that this
 * layout is the boundary — which it is not. The route group is a UX boundary only, the
 * guardrail `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §2.1 states and every
 * module layout in this tree already restates.
 */
export default function TenantShellLayout({ children }: { children: ReactNode }) {
  return (
    <div className="relative flex min-h-screen flex-col">
      <SkipToContentLink />
      <ToastProvider>{children}</ToastProvider>
    </div>
  );
}
