import { test, expect } from "@playwright/test";

/**
 * Browser and Device Compatibility E2E (HDN-381, CG-S15-HDN-013). Runs on 4
 * `playwright.config.ts` projects: `chromium` (desktop baseline, matching every other
 * e2e spec's own default project), `mobile-chrome` (`devices["Pixel 5"]`),
 * `tablet-chrome` (`devices["iPad Pro 11"]`), and `iphone-chrome`
 * (`devices["iPhone 13"]`) -- all 4 are the single pre-installed Chromium binary with a
 * different viewport/UA/touch emulation layer, not 4 separate browser engines
 * (`RECURRING_DEFECT_TAXONOMY.md` doesn't need a new class for this -- it's the
 * documented, live-verified Playwright `devices[...]` pattern). Real Safari (WebKit)
 * and Firefox remain untestable in this sandbox -- `KNOWN_ISSUES.md` `ISS-2026-244`.
 *
 * Converts this checkpoint's own throwaway investigation-lens verification (16/16
 * route x device combinations, live-tested, zero horizontal overflow found) into a
 * permanent regression guard, rather than leaving that evidence to rot in a
 * conversation transcript. `iphone-chrome` added at Tier C review to close a real
 * completeness gap: the original 3-project setup only automated 12 of the 16 route x
 * device combinations the investigation actually manually verified.
 *
 * Same disclosed scope as the other real-route specs (`e2e/tenant-admin-portal.spec.ts`,
 * `e2e/vendor-registration.spec.ts`): no live Supabase project exists in this sandbox,
 * so the guarded-route checks below prove fail-safe behavior against an unreachable
 * backend, never a real authenticated session.
 */

async function expectNoHorizontalOverflow(page: import("@playwright/test").Page) {
  const viewport = page.viewportSize();
  expect(viewport).not.toBeNull();
  const width = viewport?.width ?? 0;
  const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
  // A few px of tolerance for scrollbar-gutter/subpixel rounding across viewport sizes --
  // still tight enough to catch a real overflowing element (a fixed-width table/sidebar),
  // the exact class of defect this spec exists to guard against.
  expect(scrollWidth).toBeLessThanOrEqual(width + 4);

  // HDN-381 Tier C: `document.documentElement.scrollWidth` does NOT reflect overflow from
  // a `position: fixed` element (live-verified during Tier C review -- a 600px-wide fixed
  // element on a 320px viewport measured `scrollWidth === 320`, reporting zero overflow
  // while visually overflowing 296px past the left edge). This is exactly the element type
  // `components/ui/toast.tsx`'s `RadixToast.Viewport` uses, so the check above alone would
  // silently pass a regression of that same fix. Independently walk every fixed/sticky
  // element's own real bounding box against the viewport instead.
  const fixedOverflowPx = await page.evaluate(() => {
    let maxOverflow = 0;
    for (const el of document.querySelectorAll("*")) {
      const style = getComputedStyle(el);
      if (style.position !== "fixed" && style.position !== "sticky") continue;
      const rect = el.getBoundingClientRect();
      if (rect.width === 0 && rect.height === 0) continue; // not actually rendered
      const overflowLeft = Math.max(0, -rect.left);
      const overflowRight = Math.max(0, rect.right - window.innerWidth);
      maxOverflow = Math.max(maxOverflow, overflowLeft, overflowRight);
    }
    return maxOverflow;
  });
  expect(fixedOverflowPx).toBeLessThanOrEqual(4);
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
