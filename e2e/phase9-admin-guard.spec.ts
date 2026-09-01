import { test, expect } from "@playwright/test";

/**
 * Phase 9 (Intelligence, Automation and Enterprise) admin/reporting/automation/
 * integration portal-guard E2E -- ISS-2026-153 partial closure.
 *
 * `ISS-2026-153` originally named 9 routes (`/automation-rules`, `/dashboards`,
 * `/integrations`, `/scheduled-reports`, `/reports`, `/saved-views`,
 * `/analytics`, `/admin/api-keys`, `/customer-portal-api-keys`). Re-enumerated
 * live against the actual `app/(tenant)/[tenantSlug]` tree for this checkpoint
 * rather than trusting that count, per instruction:
 *
 * - `/customer-portal-api-keys` is a `customer-*`-prefixed, Customer-Portal-guard
 *   route -- it is covered by `e2e/customer-portal-guard.spec.ts`'s own
 *   "404-guarded Customer Portal routes" group (`ISS-2026-140`'s scope), not
 *   duplicated here.
 * - Each of the other 7 named route groups (`automation-rules`, `dashboards`,
 *   `integrations`, `saved-views`, `scheduled-reports`, `reports`, `analytics`)
 *   actually resolves to MORE than one live `page.tsx`: 5 of the 7 also carry
 *   their own `[id]`-shaped detail route, for 12 real distinct routes total
 *   (confirmed by direct `app/` tree read, not the original "~9" estimate).
 * - `/admin/api-keys` is a real, single route (`IAE-009`, Prompt 337).
 * - 3 further admin routes exist that were never named in `ISS-2026-153`'s own
 *   text, because they were built in later checkpoints (`git log`-confirmed,
 *   2026-08-30/31 commits, after `ISS-2026-153`'s own 2026-08-22 discovery
 *   date): `/admin/monitoring` (`ISS-2026-250`, Enterprise Monitoring/`IAE-030`
 *   console), `/admin/integrations` (`ISS-2026-249`, Integration Hub/`IAE-008`
 *   health console -- a DIFFERENT route from the already-in-scope
 *   `/integrations`), and `/admin/scheduler` (the tenant-configurable task
 *   scheduler's own admin console, explicitly self-described in its own header
 *   as "Automation console"). All three are admin/reporting/automation/
 *   integration-shaped in exactly the sense `ISS-2026-153`'s own title
 *   describes, so included here rather than left undisclosed a second time.
 *
 * True total in this file's own scope: 12 (the 7 named groups, detail routes
 * included) + 1 (`/admin/api-keys`) + 3 (the undisclosed later additions) = 16.
 *
 * Two distinct fail-safe shapes, confirmed by direct source read of every file:
 *
 * - The 12 `resolveCommercialAccessForRequest`-guarded routes call bare
 *   `notFound()` for any non-`allowed` status (mirroring
 *   `e2e/hris-employee-master.spec.ts`'s own guard blocks) -- "404-guarded"
 *   group below.
 * - The 4 `/admin/*`-nested routes sit under the same shared
 *   `app/(tenant)/[tenantSlug]/admin/layout.tsx` `e2e/admin-loyalty-guard.spec.ts`
 *   already documents in full: the layout's own `resolveTenantAdminAccessForRequest`
 *   redirects to `/login` before any nested page body runs, making each page's own
 *   `notFound()` unreachable defense-in-depth. Mirrors
 *   `e2e/tenant-admin-portal.spec.ts`'s own "Tenant Admin portal guard" block --
 *   "Redirect-guarded" group below.
 *
 * No axe-core check runs anywhere in this file, for the identical reasons
 * `e2e/customer-portal-guard.spec.ts`/`e2e/admin-loyalty-guard.spec.ts` already
 * give: a bare `notFound()` renders framework markup this checkpoint does not
 * own, and the shared `/login` redirect target is already axe-scanned once in
 * `e2e/tenant-admin-portal.spec.ts`.
 */

test.describe("404-guarded Phase 9 routes", () => {
  const NOT_FOUND_ROUTES: ReadonlyArray<{ readonly name: string; readonly path: string; readonly heading: string }> = [
    { name: "Automation rules list", path: "/acme/automation-rules", heading: "Automation rules" },
    { name: "Automation rule detail", path: "/acme/automation-rules/00000000-0000-0000-0000-000000000011", heading: "Dry run" },
    { name: "Dashboards list", path: "/acme/dashboards", heading: "Dashboards" },
    { name: "Dashboard detail", path: "/acme/dashboards/00000000-0000-0000-0000-000000000012", heading: "Published widgets" },
    { name: "Integrations list", path: "/acme/integrations", heading: "Integrations" },
    { name: "Integration connection detail", path: "/acme/integrations/00000000-0000-0000-0000-000000000013", heading: "Credential" },
    { name: "Saved views list", path: "/acme/saved-views", heading: "Saved views" },
    { name: "Saved view detail", path: "/acme/saved-views/00000000-0000-0000-0000-000000000014", heading: "Export" },
    { name: "Scheduled reports list", path: "/acme/scheduled-reports", heading: "Scheduled reports" },
    { name: "Scheduled report detail", path: "/acme/scheduled-reports/00000000-0000-0000-0000-000000000015", heading: "Controls" },
    { name: "Report Library", path: "/acme/reports", heading: "Report Library" },
    { name: "Analytics", path: "/acme/analytics", heading: "Analytics" },
  ];

  for (const route of NOT_FOUND_ROUTES) {
    test.describe(route.name, () => {
      test(`fails safe (never a 500 or the "${route.heading}" shell) for an unauthenticated visitor`, async ({ page }) => {
        const response = await page.goto(route.path);
        expect(response?.status()).toBeLessThan(500);
        await expect(page.getByRole("heading", { name: route.heading, exact: true })).not.toBeVisible();
      });

      test("also fails safe when the backend itself is unreachable, for a genuinely nonexistent tenant", async ({ page }) => {
        const response = await page.goto(route.path.replace("/acme/", "/does-not-exist-tenant/"));
        expect(response?.status()).toBeLessThan(500);
        await expect(page.getByRole("heading", { name: route.heading, exact: true })).not.toBeVisible();
      });
    });
  }
});

test.describe("Redirect-guarded Phase 9 admin routes", () => {
  const REDIRECT_ROUTES: ReadonlyArray<{ readonly name: string; readonly path: string }> = [
    { name: "Public API developer console (admin/api-keys)", path: "/acme/admin/api-keys" },
    { name: "Monitoring and incident console (admin/monitoring, ISS-2026-250)", path: "/acme/admin/monitoring" },
    { name: "Integration health console (admin/integrations, ISS-2026-249)", path: "/acme/admin/integrations" },
    { name: "Task scheduler automation console (admin/scheduler)", path: "/acme/admin/scheduler" },
  ];

  for (const route of REDIRECT_ROUTES) {
    test.describe(route.name, () => {
      test("redirects an unauthenticated visitor to /login rather than rendering the shell or a 500", async ({ page }) => {
        const response = await page.goto(route.path);
        expect(response?.status()).toBeLessThan(500);
        await expect(page).toHaveURL(/\/login$/);
      });

      test("also fails safe (redirect, not a crash) when the backend itself is unreachable, for a genuinely nonexistent tenant", async ({ page }) => {
        const response = await page.goto(route.path.replace("/acme/", "/does-not-exist-tenant/"));
        expect(response?.status()).toBeLessThan(500);
        await expect(page).toHaveURL(/\/login$/);
      });
    });
  }
});
