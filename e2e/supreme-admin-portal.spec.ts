import { test, expect } from "@playwright/test";

/**
 * Supreme Admin portal E2E (PLT-136, CG-S6-PLT-033). Mirrors
 * `e2e/tenant-admin-portal.spec.ts`'s own disclosed scope: no live Supabase project
 * exists anywhere in this repository yet, so this spec proves the guard's fail-safe
 * behavior (redirect, never a 500) against an unreachable backend -- it does not
 * exercise a real Supreme sign-in. Same `NOT_RUN` class as `test:e2e` generally in this
 * sandbox (Playwright browser-binary revision skew, every checkpoint since `PLT-117`).
 */

test.describe("Supreme Admin portal guard", () => {
  test("redirects an unauthenticated visitor to /login rather than rendering the shell or a 500", async ({ page }) => {
    const response = await page.goto("/supreme");
    expect(response?.status()).toBeLessThan(500);
    await expect(page).toHaveURL(/\/login$/);
  });

  test("also fails safe for a nested route (/supreme/tenants), not just the portal root", async ({ page }) => {
    const response = await page.goto("/supreme/tenants");
    expect(response?.status()).toBeLessThan(500);
    await expect(page).toHaveURL(/\/login$/);
  });
});

test.describe("Login page — organization field now optional (PLT-136)", () => {
  test("submits with the organization field left blank (CargoGrid-staff path) without client-side validation blocking it", async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel("Email").fill("staff@example.test");
    await page.getByLabel("Password").fill("not-a-real-password");
    // No network assertion here -- no live Supabase project exists (see this file's
    // own header). This only proves the organization field's own `required` attribute
    // was correctly removed, i.e. the browser lets the submit proceed.
    const [request] = await Promise.all([
      page.waitForRequest((req) => req.method() === "POST", { timeout: 5_000 }).catch(() => null),
      page.getByRole("button", { name: "Sign in" }).click(),
    ]);
    expect(request).not.toBeNull();
  });
});
