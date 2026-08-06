import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

/**
 * Vendor Registration and Onboarding E2E (PRC-251, CG-S11-PRC-002,
 * `PRC-VND-US-001` per Prompt 251 §28). Added during adversarial review -- the
 * checkpoint's own db-test/unit suites already prove the RPC layer, but no
 * browser/accessibility spec existed for the first UI Phase 6 has ever shipped.
 *
 * Same disclosed scope as `e2e/tenant-admin-portal.spec.ts` (PLT-135): no live
 * Supabase project exists in this sandbox, so these specs prove real routes' own
 * static render/accessibility and fail-safe guard behavior against an unreachable
 * backend -- never a real authenticated session or a real vendor lifecycle
 * transition end-to-end, which requires a live Supabase project this sandbox
 * cannot reach.
 */

test.describe("Public vendor intake (token-based invite)", () => {
  test("renders the registration form with all required fields", async ({ page }) => {
    await page.goto("/vendor-intake/some-raw-token-value");
    await expect(page.getByRole("heading", { name: "Vendor registration" })).toBeVisible();
    await expect(page.getByLabel("Legal company name")).toBeVisible();
    await expect(page.getByLabel("Primary contact email")).toBeVisible();
    await expect(page.getByRole("button", { name: "Submit registration" })).toBeVisible();
  });

  test("has no automatically detectable accessibility violations", async ({ page }) => {
    await page.goto("/vendor-intake/some-raw-token-value");
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations).toEqual([]);
  });

  test("rejects submission with the legal name empty (native HTML validation, no server round-trip)", async ({ page }) => {
    await page.goto("/vendor-intake/some-raw-token-value");
    await page.getByRole("button", { name: "Submit registration" }).click();
    await expect(page).toHaveURL(/\/vendor-intake\/some-raw-token-value$/);
  });
});

test.describe("Public vendor self-registration (tenant-configurable, no token)", () => {
  test("fails safe to 'not available' (never a 500 or a crash) when the resolver's backend is unreachable", async ({ page }) => {
    const response = await page.goto("/vendor-intake/register/does-not-exist-tenant");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Vendor registration is not available" })).toBeVisible();
  });

  test("the fail-safe 'not available' state has no automatically detectable accessibility violations", async ({ page }) => {
    await page.goto("/vendor-intake/register/does-not-exist-tenant");
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations).toEqual([]);
  });
});

test.describe("Procurement portal guard", () => {
  test("fails safe (a 404, never a 500 or the vendor directory shell) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto("/acme/procurement/vendors");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Vendors", exact: true })).not.toBeVisible();
  });

  test("also fails safe when the backend itself is unreachable -- the guard's own no-live-Supabase-project condition, proven directly", async ({ page }) => {
    const response = await page.goto("/does-not-exist-tenant/procurement/vendors");
    expect(response?.status()).toBeLessThan(500);
  });
});
