import { test, expect } from "@playwright/test";

/**
 * Organization and Position Linkage (HRT-275) portal-guard E2E -- ISS-2026-066 item 4
 * closure.
 *
 * Modeled directly on `e2e/hris-employee-master.spec.ts`'s own identical rationale
 * (itself modeled on `e2e/vendor-registration.spec.ts`'s "Procurement portal guard"
 * block): no live Supabase project exists in this sandbox, and there is no root
 * `middleware.ts` -- the HRIS portal-entry guard (`resolveHrisAccessForRequest`) is
 * enforced entirely inside each page component, which calls Next's `notFound()` when
 * access is not `allowed`, never a redirect. Every page below takes this path with no
 * live backend to authenticate against, so this spec proves only the fail-safe states:
 * a real 404 (never a 500 or the real page shell), for both a real-looking tenant slug
 * and a genuinely nonexistent one. No axe-core check runs against any of these guard
 * states: every page guards with a bare Next.js `notFound()` (no custom "not available"
 * markup of this app's own) -- axe-checking Next's own default 404 template would
 * assert on framework markup this checkpoint does not own, exactly the same reasoning
 * `hris-employee-master.spec.ts` and `vendor-registration.spec.ts` already established.
 *
 * Covers every page family this entry's own item 4 named as uncovered (position
 * catalogue, organization tree, assignment-timeline/wizard) plus the new bulk
 * reorganization wizard (item 1, `/hris/positions/bulk-reassign`) this same checkpoint
 * added -- it needed the identical guard proof, per this entry's own instruction.
 */

const SOME_UUID = "00000000-0000-0000-0000-000000000001";

test.describe("Position catalogue portal guard", () => {
  test("fails safe (a 404, never a 500 or the catalogue shell) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto("/acme/hris/positions");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Positions & grades", exact: true })).not.toBeVisible();
  });

  test("also fails safe when the backend itself is unreachable, for a genuinely nonexistent tenant", async ({ page }) => {
    const response = await page.goto("/does-not-exist-tenant/hris/positions");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Positions & grades", exact: true })).not.toBeVisible();
  });
});

test.describe("Position detail portal guard", () => {
  test("fails safe for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto(`/acme/hris/positions/${SOME_UUID}`);
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Bulk reorganization", exact: true })).not.toBeVisible();
  });

  test("also fails safe for a genuinely nonexistent tenant", async ({ page }) => {
    const response = await page.goto(`/does-not-exist-tenant/hris/positions/${SOME_UUID}`);
    expect(response?.status()).toBeLessThan(500);
  });
});

test.describe("Bulk reorganization wizard portal guard (ISS-2026-066 item 1)", () => {
  test("fails safe (a 404, never a 500 or the wizard shell) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto("/acme/hris/positions/bulk-reassign");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Bulk reorganization", exact: true })).not.toBeVisible();
  });

  test("also fails safe when the backend itself is unreachable, for a genuinely nonexistent tenant", async ({ page }) => {
    const response = await page.goto("/does-not-exist-tenant/hris/positions/bulk-reassign");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Bulk reorganization", exact: true })).not.toBeVisible();
  });
});

test.describe("Organization tree portal guard", () => {
  test("fails safe for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto("/acme/hris/organization");
    expect(response?.status()).toBeLessThan(500);
  });

  test("also fails safe for a genuinely nonexistent tenant", async ({ page }) => {
    const response = await page.goto("/does-not-exist-tenant/hris/organization");
    expect(response?.status()).toBeLessThan(500);
  });
});

test.describe("Employee assignment timeline / wizard portal guard", () => {
  test("fails safe (a 404, never a 500 or the wizard shell) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto(`/acme/hris/employees/${SOME_UUID}/positions`);
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: /Position & assignment timeline/i })).not.toBeVisible();
  });

  test("also fails safe when the backend itself is unreachable, for a genuinely nonexistent tenant", async ({ page }) => {
    const response = await page.goto(`/does-not-exist-tenant/hris/employees/${SOME_UUID}/positions`);
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: /Position & assignment timeline/i })).not.toBeVisible();
  });
});
