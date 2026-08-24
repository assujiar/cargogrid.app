import { test, expect } from "@playwright/test";

/**
 * Browser and Device Compatibility E2E (HDN-381, CG-S15-HDN-013). Runs on 3
 * `playwright.config.ts` projects: `chromium` (desktop baseline, matching every other
 * e2e spec's own default project), `mobile-chrome` (`devices["Pixel 5"]`), and
 * `tablet-chrome` (`devices["iPad Pro 11"]`) -- all 3 are the single pre-installed
 * Chromium binary with a different viewport/UA/touch emulation layer, not 3 separate
 * browser engines (`RECURRING_DEFECT_TAXONOMY.md` doesn't need a new class for this --
 * it's the documented, live-verified Playwright `devices[...]` pattern). Real Safari
 * (WebKit) and Firefox remain untestable in this sandbox -- `KNOWN_ISSUES.md`
 * `ISS-2026-244`.
 *
 * Converts this checkpoint's own throwaway investigation-lens verification (16/16
 * route x device combinations, live-tested, zero horizontal overflow found) into a
 * permanent regression guard, rather than leaving that evidence to rot in a
 * conversation transcript.
 *
 * Same disclosed scope as the other real-route specs (`e2e/tenant-admin-portal.spec.ts`,
 * `e2e/vendor-registration.spec.ts`): no live Supabase project exists in this sandbox,
 * so the guarded-route checks below prove fail-safe behavior against an unreachable
 * backend, never a real authenticated session.
 */

async function expectNoHorizontalOverflow(page: import("@playwright/test").Page) {
  const viewport = page.viewportSize();
  expect(viewport).not.toBeNull();
  const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
  // A few px of tolerance for scrollbar-gutter/subpixel rounding across viewport sizes --
  // still tight enough to catch a real overflowing element (a fixed-width table/toast/
  // sidebar), the exact class of defect this spec exists to guard against.
  expect(scrollWidth).toBeLessThanOrEqual((viewport?.width ?? 0) + 4);
}

test.describe("Public login page", () => {
  test("renders with no horizontal overflow and every field reachable", async ({ page }) => {
    await page.goto("/login");
    await expectNoHorizontalOverflow(page);
    await expect(page.getByLabel("Organization")).toBeVisible();
    await expect(page.getByLabel("Email")).toBeVisible();
    await expect(page.getByLabel("Password")).toBeVisible();
    await expect(page.getByRole("button", { name: "Sign in" })).toBeVisible();
  });
});

test.describe("Public vendor intake form", () => {
  test("renders with no horizontal overflow and every field reachable", async ({ page }) => {
    await page.goto("/vendor-intake/some-raw-token-value");
    await expectNoHorizontalOverflow(page);
    await expect(page.getByLabel("Legal company name")).toBeVisible();
    await expect(page.getByLabel("Primary contact email")).toBeVisible();
    await expect(page.getByRole("button", { name: "Submit registration" })).toBeVisible();
  });
});

test.describe("Guarded route fail-safe rendering", () => {
  test("Supreme Admin portal guard redirect renders with no horizontal overflow", async ({ page }) => {
    const response = await page.goto("/supreme");
    expect(response?.status()).toBeLessThan(500);
    await expect(page).toHaveURL(/\/login$/);
    await expectNoHorizontalOverflow(page);
  });

  test("Procurement portal guard fail-safe (404) renders with no horizontal overflow", async ({ page }) => {
    const response = await page.goto("/acme/procurement/vendors");
    expect(response?.status()).toBeLessThan(500);
    await expectNoHorizontalOverflow(page);
  });
});
