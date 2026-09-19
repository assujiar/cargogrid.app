"use client";

/**
 * Root error boundary (CG-AUDIT-2026-09-02 F1: 0 `error.tsx` existed anywhere in this
 * repository -- every uncaught throw in a Server or Client Component under the root
 * layout previously fell through to Next's own unstyled default crash screen instead of
 * a boundary this application controls). Catches anything a route segment's own page
 * doesn't already handle itself (most pages already catch a known query failure and
 * render `<ErrorState>` inline -- this is the safety net for what they don't expect).
 *
 * Per `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §5's Error-state contract:
 * human-readable message + a request id + retry, never the raw exception/stack. `error.
 * digest` is Next's own production-safe correlation id for a Server Component throw
 * (the actual message/stack are deliberately stripped from the client bundle in
 * production) -- shown here exactly as that contract asks, never `error.message` itself.
 *
 * Must be a Client Component (Next.js requirement for `error.tsx`) -- `reset()` re-
 * renders the segment without a full navigation, offered as the "retry" action.
 */

import { useEffect } from "react";
import { ErrorState } from "../components/ui/error-state.tsx";
import { Link } from "../components/ui/link.tsx";

export default function RootErrorBoundary({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    // ISS-2026-245-adjacent posture: no error-tracking/observability plumbing exists in
    // this repository yet (see lib/api-gateway/authenticate.server.ts's own recordApiV1Success
    // header comment) -- this is the one place a genuinely uncaught error is at least
    // visible in server/browser logs during development, not a substitute for real
    // monitoring once that infrastructure exists.
    console.error(error);
  }, [error]);

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-4 px-4 text-center">
      <ErrorState
        title="Something went wrong"
        description="An unexpected error occurred while loading this page. You can try again, or go back to a safe page."
        requestId={error.digest}
        onRetry={reset}
        retryLabel="Try again"
      />
      <Link href="/">Go to home</Link>
    </main>
  );
}
