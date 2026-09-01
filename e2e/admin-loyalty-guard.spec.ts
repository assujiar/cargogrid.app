import { test, expect } from "@playwright/test";

/**
 * Admin Loyalty (CPL-316..320-ish, Phase 8) portal-guard E2E -- ISS-2026-140
 * partial closure (the admin-Loyalty half of the entry's two named scopes; the
 * Customer Portal half is `e2e/customer-portal-guard.spec.ts`).
 *
 * All 9 admin Loyalty routes below live under
 * `app/(tenant)/[tenantSlug]/admin/loyalty*`, nested under the single shared
 * `app/(tenant)/[tenantSlug]/admin/layout.tsx` (PLT-135) -- confirmed by direct
 * read that no `admin/loyalty*` subdirectory carries its own `layout.tsx`
 * override. That shared layout resolves `resolveTenantAdminAccessForRequest`
 * itself and calls `redirect('/login')` on `status === "unauthenticated"` (or
 * renders its own real "Access denied" markup for `tenant_suspended`/`forbidden`
 * -- never reachable in this sandbox, since there is no live Supabase project for
 * any auth check to succeed against) *before* any nested page component's own
 * body runs -- each individual admin/loyalty-prefixed `page.tsx` also carries its own
 * defense-in-depth `notFound()` guard, but that code path is unreachable via a
 * real browser navigation, since the parent layout already redirected. This spec
 * therefore mirrors `e2e/tenant-admin-portal.spec.ts`'s own "Tenant Admin portal
 * guard" `describe` block exactly (redirect assertion, not a 404 assertion), one
 * `describe` per route, live-verified against the real nested-layout behavior
 * rather than assumed from the page component's own code alone.
 *
 * No axe-core check runs here, for the identical reason
 * `e2e/tenant-admin-portal.spec.ts` itself declines one for `/acme/admin` and
 * `/does-not-exist-tenant/admin`: the redirect target (`/login`) is already
 * axe-scanned once, thoroughly, in that file -- rescanning the same shared
 * markup 9 more times adds zero new signal.
 */

const ADMIN_LOYALTY_ROUTES: ReadonlyArray<{ readonly name: string; readonly path: string }> = [
  { name: "Loyalty Program admin", path: "/acme/admin/loyalty" },
  { name: "Loyalty Benefits admin", path: "/acme/admin/loyalty-benefits" },
  { name: "Loyalty Points admin", path: "/acme/admin/loyalty-points" },
  { name: "Loyalty Redemptions admin", path: "/acme/admin/loyalty-redemptions" },
  { name: "Loyalty Fraud Review admin", path: "/acme/admin/loyalty-fraud-review" },
  { name: "Loyalty Expiry admin", path: "/acme/admin/loyalty-expiry" },
  { name: "Loyalty Tiers admin", path: "/acme/admin/loyalty-tiers" },
  { name: "Loyalty Liability admin", path: "/acme/admin/loyalty-liability" },
  { name: "Loyalty Rewards admin", path: "/acme/admin/loyalty-rewards" },
];

for (const route of ADMIN_LOYALTY_ROUTES) {
  test.describe(`${route.name} portal guard`, () => {
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
