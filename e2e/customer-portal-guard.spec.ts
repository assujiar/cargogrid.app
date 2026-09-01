import { test, expect } from "@playwright/test";

/**
 * Customer Portal (CPL-300..325, Phase 8) portal-guard E2E -- ISS-2026-140 partial
 * closure (the Customer Portal half of the entry's two named scopes; the admin
 * Loyalty half is `e2e/admin-loyalty-guard.spec.ts`).
 *
 * Modeled directly on `e2e/hris-employee-master.spec.ts`'s and
 * `e2e/tenant-admin-portal.spec.ts`'s own "portal guard" pattern (itself modeled on
 * `e2e/vendor-registration.spec.ts`, the established pattern for a
 * first-real-page-but-no-live-backend spec in this repository). No live Supabase
 * project exists in this sandbox, so every one of these 28 routes is reached only
 * as far as its own portal-entry guard (`lib/portal/customer-portal-guard.ts`,
 * `resolveCustomerPortalAccessForRequest`) can resolve without a real auth backend
 * -- which is always the `unauthenticated` outcome (`auth.getUser()` cannot reach
 * any Supabase instance). This spec proves only the fail-safe states it is
 * possible to prove here: a real non-5xx response, and never the real
 * authenticated shell, for every Customer Portal route this checkpoint could find
 * live in `app/(tenant)/[tenantSlug]/customer-*` (excluding `customer-tickets`,
 * which is `HRT-287`/Phase 7's own pre-existing, already-covered-elsewhere
 * ticketing surface -- a different guard, a different phase, out of this entry's
 * own "Phase 8" scope).
 *
 * Two distinct fail-safe shapes exist across these 28 pages, confirmed by direct
 * source read of every file rather than assumed uniform:
 *
 * - 16 pages call `redirect('/login')` themselves on `status === "unauthenticated"`
 *   (mirroring `e2e/tenant-admin-portal.spec.ts`'s own "Tenant Admin portal guard"
 *   block) -- this "Redirect-guarded" `describe` group below.
 * - 12 pages call bare `notFound()` for any non-`allowed` status, including
 *   `unauthenticated` (mirroring `e2e/hris-employee-master.spec.ts`'s own guard
 *   blocks) -- this "404-guarded" `describe` group below.
 *
 * No axe-core check runs anywhere in this file, mirroring both source patterns'
 * own established reasoning: a redirect target (`/login`) is already axe-scanned
 * once, thoroughly, in `e2e/tenant-admin-portal.spec.ts` -- rescanning the
 * identical shared markup here 16 more times would add zero new signal; a bare
 * `notFound()` renders Next's own default 404 template, framework markup this
 * checkpoint does not own, exactly why every 404-guarded spec in this repository
 * already declines to axe-check it.
 */

test.describe("Redirect-guarded Customer Portal routes", () => {
  const REDIRECT_ROUTES: ReadonlyArray<{ readonly name: string; readonly path: string }> = [
    { name: "Warehouse inventory orders list", path: "/acme/customer-warehouse-orders" },
    { name: "Receipts list", path: "/acme/customer-receipts" },
    { name: "Profile", path: "/acme/customer-profile" },
    { name: "Portal scope-preview", path: "/acme/customer-portal" },
    { name: "Portal users", path: "/acme/customer-portal-users" },
    { name: "Portal dashboard", path: "/acme/customer-portal-dashboard" },
    { name: "Loyalty earning history", path: "/acme/customer-loyalty" },
    { name: "Loyalty tier", path: "/acme/customer-loyalty-tier" },
    { name: "Loyalty summary", path: "/acme/customer-loyalty-summary" },
    { name: "Loyalty reward detail", path: "/acme/customer-loyalty-rewards/00000000-0000-0000-0000-000000000001" },
    { name: "Loyalty rewards catalogue", path: "/acme/customer-loyalty-rewards" },
    { name: "Loyalty redemptions", path: "/acme/customer-loyalty-redemptions" },
    { name: "Loyalty points", path: "/acme/customer-loyalty-points" },
    { name: "Loyalty benefits", path: "/acme/customer-loyalty-benefits" },
    { name: "Invoices list", path: "/acme/customer-invoices" },
    { name: "Inventory", path: "/acme/customer-inventory" },
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

test.describe("404-guarded Customer Portal routes", () => {
  const NOT_FOUND_ROUTES: ReadonlyArray<{ readonly name: string; readonly path: string; readonly heading: string }> = [
    { name: "Alerts list", path: "/acme/customer-alerts", heading: "Alerts" },
    { name: "Bookings list", path: "/acme/customer-bookings", heading: "Bookings" },
    { name: "Booking detail", path: "/acme/customer-bookings/00000000-0000-0000-0000-000000000002", heading: "Request a reschedule" },
    { name: "Documents list", path: "/acme/customer-documents", heading: "Documents" },
    { name: "Invoice detail", path: "/acme/customer-invoices/00000000-0000-0000-0000-000000000003", heading: "Charges & tax lines" },
    { name: "Portal API keys", path: "/acme/customer-portal-api-keys", heading: "API keys" },
    { name: "Quote requests list", path: "/acme/customer-quotes", heading: "Quote requests" },
    { name: "Quote request detail", path: "/acme/customer-quotes/00000000-0000-0000-0000-000000000004", heading: "Attachments" },
    { name: "Shipments list", path: "/acme/customer-shipments", heading: "Shipments" },
    { name: "Shipment detail", path: "/acme/customer-shipments/00000000-0000-0000-0000-000000000005", heading: "Request a change" },
    { name: "Outbound warehouse order detail", path: "/acme/customer-warehouse-orders/00000000-0000-0000-0000-000000000006", heading: "Fulfillment progress" },
    { name: "Inbound warehouse order detail", path: "/acme/customer-warehouse-orders/inbound/00000000-0000-0000-0000-000000000007", heading: "Receiving progress" },
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
