import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

/**
 * Tenant Admin portal E2E (PLT-135, CG-S6-PLT-032). Unlike `e2e/smoke.spec.ts`
 * (synthetic inline content only), this spec navigates the real `app/(public)/login`
 * and `app/(tenant)/[tenantSlug]/admin` routes via `playwright.config.ts`'s own
 * `webServer` (a real `next dev`, placeholder Supabase env values).
 *
 * **Scope, disclosed rather than left implicit**: no live Supabase project exists
 * anywhere in this repository yet (`preflight` correctly fails closed, every prior
 * checkpoint's own disclosure) -- this spec proves the login page's own static
 * render/accessibility and the guard's fail-safe behavior against an unreachable
 * backend (a real, meaningful assertion: `resolveTenantAdminAccess` must redirect to
 * `/login`, never throw a 500, when `auth.getUser()` cannot reach any Supabase
 * instance at all). It does not exercise a real sign-in or a real `allowed` guard
 * result -- that requires a live Supabase project, out of this sandbox's reach, the
 * same class of `NOT_RUN` disclosure `test:e2e` itself already carries in this
 * environment (sandbox Playwright browser-binary revision skew, every checkpoint
 * since `PLT-117`).
 */

test.describe("Login page", () => {
  test("renders the sign-in form with all required fields", async ({ page }) => {
    await page.goto("/login");
    await expect(page.getByRole("heading", { name: "Sign in to CargoGrid" })).toBeVisible();
    await expect(page.getByLabel("Organization")).toBeVisible();
    await expect(page.getByLabel("Email")).toBeVisible();
    await expect(page.getByLabel("Password")).toBeVisible();
    await expect(page.getByRole("button", { name: "Sign in" })).toBeVisible();
  });

  test("has no automatically detectable accessibility violations", async ({ page }) => {
    await page.goto("/login");
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations).toEqual([]);
  });

  test("rejects submission with required fields empty (native HTML validation, no server round-trip)", async ({ page }) => {
    await page.goto("/login");
    await page.getByRole("button", { name: "Sign in" }).click();
    // The browser's own required-field validation blocks submission -- still on /login, not redirected anywhere.
    await expect(page).toHaveURL(/\/login$/);
  });
});

test.describe("Tenant Admin portal guard", () => {
  test("redirects an unauthenticated visitor to /login rather than rendering the shell or a 500", async ({ page }) => {
    const response = await page.goto("/acme/admin");
    expect(response?.status()).toBeLessThan(500);
    await expect(page).toHaveURL(/\/login$/);
  });

  test("also fails safe (redirect, not a crash) when the backend itself is unreachable -- the guard's own no-live-Supabase-project condition, proven directly rather than assumed", async ({ page }) => {
    const response = await page.goto("/does-not-exist-tenant/admin");
    expect(response?.status()).toBeLessThan(500);
    await expect(page).toHaveURL(/\/login$/);
  });
});
