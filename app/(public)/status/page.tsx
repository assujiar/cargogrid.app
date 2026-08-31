import type { Metadata } from "next";
import { StatusPanel } from "./status-panel.tsx";

/**
 * Public service-status page (ISS-2026-304). Unauthenticated, and deliberately STATIC.
 *
 * `force-static` is the load-bearing line in this file. The page must render at build time and
 * be served from the CDN, so that it neither calls the database nor needs the application to
 * be healthy in order to load. A status page that server-renders is unavailable in exactly the
 * incident it exists to describe.
 *
 * Every check happens in the browser, against the two unauthenticated probes this repository
 * already ships (`/api/health` liveness, `/api/ready` readiness). No session, no tenant
 * context, and no application data is involved -- the page reveals nothing an anonymous
 * visitor could not learn by trying to load CargoGrid and watching it fail.
 */
export const dynamic = "force-static";

export const metadata: Metadata = {
  title: "CargoGrid status",
  description: "Live availability of the CargoGrid application and its database.",
};

export default function StatusPage() {
  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col gap-8 px-4 py-16">
      <header>
        <h1 className="text-2xl font-semibold text-neutral-900">CargoGrid status</h1>
        <p className="mt-2 text-sm text-neutral-600">
          Checked live from your browser each time this page loads, and every 30 seconds after that.
        </p>
      </header>

      <StatusPanel />

      <footer className="text-sm text-neutral-600">
        <a href="/login" className="font-medium text-neutral-900 underline">
          Back to sign in
        </a>
      </footer>
    </main>
  );
}
