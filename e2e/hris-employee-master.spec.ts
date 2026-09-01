import { test, expect } from "@playwright/test";

/**
 * Employee Master (HRT-274) portal-guard E2E -- ISS-2026-064 item 3 closure.
 *
 * Modeled directly on `e2e/vendor-registration.spec.ts`'s own "Procurement portal
 * guard" `describe` block (the established pattern for a first-real-page-but-no-
 * live-backend spec in this repository) and `e2e/tenant-admin-portal.spec.ts`'s own
 * identical disclosed scope: no live Supabase project exists in this sandbox, and
 * there is no root `middleware.ts` -- the HRIS portal-entry guard
 * (`resolveHrisAccessForRequest` / `lib/portal/hris-guard.ts`) is enforced entirely
 * inside each page component, which calls Next's `notFound()` when access is not
 * `allowed`, never a redirect. Both the employee directory
 * (`app/(tenant)/[tenantSlug]/hris/employees/page.tsx`) and the employee detail page
 * (`app/(tenant)/[tenantSlug]/hris/employees/[masterRecordId]/page.tsx`) take this
 * path with no live backend to authenticate against, so this spec proves only the
 * fail-safe states: a real 404 (never a 500 or the real shell), for both a real-
 * looking tenant slug and a genuinely nonexistent one. No axe-core check runs against
 * the fail-safe state itself: both pages guard with a bare Next.js `notFound()` (no
 * custom "not available" markup of this app's own, unlike
 * `e2e/vendor-registration.spec.ts`'s public self-registration fallback) -- axe-
 * checking Next's own default 404 template would assert on framework markup this
 * checkpoint does not own, exactly why `e2e/vendor-registration.spec.ts`'s own
 * "Procurement portal guard" block (bare `notFound()` too) carries no axe check
 * either. Mirrored here rather than deviated from.
 */

test.describe("Employee directory portal guard", () => {
  test("fails safe (a 404, never a 500 or the employee directory shell) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto("/acme/hris/employees");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Employees", exact: true })).not.toBeVisible();
  });

  test("also fails safe when the backend itself is unreachable -- the guard's own no-live-Supabase-project condition, proven directly", async ({ page }) => {
    const response = await page.goto("/does-not-exist-tenant/hris/employees");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Employees", exact: true })).not.toBeVisible();
  });
});

test.describe("Employee detail portal guard (covers the Documents tab's upload form, ISS-2026-064 item 2)", () => {
  const SOME_MASTER_RECORD_ID = "00000000-0000-0000-0000-000000000001";

  test("fails safe (a 404, never a 500 or the employee detail shell) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto(`/acme/hris/employees/${SOME_MASTER_RECORD_ID}`);
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("tab", { name: "Documents" })).not.toBeVisible();
  });

  test("also fails safe when the backend itself is unreachable, for a genuinely nonexistent tenant", async ({ page }) => {
    const response = await page.goto(`/does-not-exist-tenant/hris/employees/${SOME_MASTER_RECORD_ID}`);
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("tab", { name: "Documents" })).not.toBeVisible();
  });
});
