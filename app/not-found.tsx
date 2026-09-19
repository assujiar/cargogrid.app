/**
 * Root not-found boundary (CG-AUDIT-2026-09-02 F1: 0 `not-found.tsx` existed anywhere
 * in this repository) -- renders for an unmatched route, or wherever a page calls
 * Next's own `notFound()`. A Server Component (no interactivity needed), unlike
 * `error.tsx`/`global-error.tsx` above.
 */

import { Link } from "../components/ui/link.tsx";

export default function RootNotFound() {
  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-3 px-4 text-center">
      <h1 className="text-xl font-semibold text-neutral-900">Page not found</h1>
      <p className="text-sm text-neutral-600">The page you&rsquo;re looking for doesn&rsquo;t exist or may have moved.</p>
      <Link href="/">Go to home</Link>
    </main>
  );
}
