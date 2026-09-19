"use client";

/**
 * Root-layout error boundary (CG-AUDIT-2026-09-02 F1: 0 `global-error.tsx` existed
 * anywhere in this repository). `app/error.tsx` catches a throw in a route segment
 * under the root layout; a throw in the root layout itself (`app/layout.tsx`) bypasses
 * that boundary entirely -- `global-error.tsx` is the one Next.js mechanism that can
 * still catch it, which is why it must render its own `<html>`/`<body>` (it replaces
 * the root layout, rather than rendering inside it) and import global.css directly
 * (the root layout that would normally do so is exactly what failed).
 *
 * Deliberately minimal, unstyled-framework-independent markup -- this is the last
 * resort when the layout itself is broken, not the place to lean on the same design-
 * system primitives `app/error.tsx` uses (a shared primitive failing to render is
 * precisely the class of failure this file exists to survive).
 */

import { useEffect } from "react";
import "./globals.css";

export default function GlobalErrorBoundary({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <html lang="en">
      <body>
        <main style={{ display: "flex", minHeight: "100vh", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "1rem", padding: "1rem", textAlign: "center" }}>
          <h1 style={{ fontSize: "1.25rem", fontWeight: 600 }}>Something went wrong</h1>
          <p style={{ fontSize: "0.875rem", color: "#525252" }}>CargoGrid failed to load. Please try again.</p>
          {error.digest ? <p style={{ fontSize: "0.75rem", color: "#737373" }}>Request ID: {error.digest}</p> : null}
          <button
            type="button"
            onClick={reset}
            style={{ borderRadius: "0.375rem", backgroundColor: "#171717", color: "#fafafa", padding: "0.5rem 1rem", fontSize: "0.875rem", fontWeight: 500 }}
          >
            Try again
          </button>
        </main>
      </body>
    </html>
  );
}
