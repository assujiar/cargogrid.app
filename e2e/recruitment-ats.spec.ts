import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

/**
 * Recruitment, Job Portal and ATS (HRT-276) E2E -- ISS-2026-067 item 6 closure.
 *
 * Modeled directly on `e2e/hris-employee-master.spec.ts`'s own "portal guard" pattern
 * (itself modeled on `e2e/vendor-registration.spec.ts`, the established pattern for a
 * first-real-page-but-no-live-backend spec in this repository) for the four
 * staff-facing pages, and on `e2e/vendor-registration.spec.ts`'s own public-page halves
 * for the two genuinely public careers pages. No live Supabase project exists in this
 * sandbox, and there is no root `middleware.ts` -- every staff-facing page below is
 * guarded entirely inside the page component via `resolveHrisAccessForRequest` /
 * `lib/portal/hris-guard.ts`, which calls Next's `notFound()` when access is not
 * `allowed`, never a redirect. This spec proves only the fail-safe states: a real 404
 * (never a 500 or the real shell) for the staff pages, and the real "no rows" / "not
 * available" collapse states the two public careers pages themselves render when their
 * own backend call fails -- never a real authenticated session or a real recruitment
 * pipeline transition end to end, which requires a live Supabase project this sandbox
 * cannot reach. No axe-core check runs against the four staff-page guard states: all
 * four guard with a bare Next.js `notFound()` (no custom "not available" markup of this
 * app's own), exactly why `e2e/hris-employee-master.spec.ts`'s own guard blocks carry
 * no axe check either -- axe-checking Next's own default 404 template would assert on
 * framework markup this checkpoint does not own. The two public careers pages DO carry
 * axe checks, mirroring `e2e/vendor-registration.spec.ts`'s own public-page halves,
 * because both render this app's own markup (never a bare `notFound()`).
 */

test.describe("Recruitment pipeline (vacancy list) portal guard", () => {
  test("fails safe (a 404, never a 500 or the recruitment shell) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto("/acme/hris/recruitment");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Recruitment", exact: true })).not.toBeVisible();
  });

  test("also fails safe when the backend itself is unreachable, for a genuinely nonexistent tenant", async ({ page }) => {
    const response = await page.goto("/does-not-exist-tenant/hris/recruitment");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Recruitment", exact: true })).not.toBeVisible();
  });
});

test.describe("Vacancy detail portal guard", () => {
  const SOME_VACANCY_ID = "00000000-0000-0000-0000-000000000001";

  test("fails safe (a 404, never a 500 or the vacancy pipeline table) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto(`/acme/hris/recruitment/${SOME_VACANCY_ID}`);
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Pipeline", exact: true })).not.toBeVisible();
  });

  test("also fails safe when the backend itself is unreachable, for a genuinely nonexistent tenant", async ({ page }) => {
    const response = await page.goto(`/does-not-exist-tenant/hris/recruitment/${SOME_VACANCY_ID}`);
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Pipeline", exact: true })).not.toBeVisible();
  });
});

test.describe("Application detail portal guard", () => {
  const SOME_APPLICATION_ID = "00000000-0000-0000-0000-000000000002";

  test("fails safe (a 404, never a 500 or the application detail shell) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto(`/acme/hris/recruitment/applications/${SOME_APPLICATION_ID}`);
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Stage history", exact: true })).not.toBeVisible();
  });

  test("also fails safe when the backend itself is unreachable, for a genuinely nonexistent tenant", async ({ page }) => {
    const response = await page.goto(`/does-not-exist-tenant/hris/recruitment/applications/${SOME_APPLICATION_ID}`);
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Stage history", exact: true })).not.toBeVisible();
  });
});

test.describe("My assigned interviews portal guard", () => {
  test("fails safe (a 404, never a 500 or the interviewer self-service shell) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto("/acme/hris/recruitment/my-interviews");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "My assigned interviews", exact: true })).not.toBeVisible();
  });

  test("also fails safe when the backend itself is unreachable, for a genuinely nonexistent tenant", async ({ page }) => {
    const response = await page.goto("/does-not-exist-tenant/hris/recruitment/my-interviews");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "My assigned interviews", exact: true })).not.toBeVisible();
  });
});

test.describe("Candidate directory and profile portal guard (ISS-2026-067 item 5, new this checkpoint)", () => {
  const SOME_CANDIDATE_ID = "00000000-0000-0000-0000-000000000003";

  test("candidate directory fails safe (a 404, never a 500) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto("/acme/hris/recruitment/candidates");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Candidates", exact: true })).not.toBeVisible();
  });

  test("candidate profile fails safe (a 404, never a 500) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto(`/acme/hris/recruitment/candidates/${SOME_CANDIDATE_ID}`);
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Duplicate review", exact: true })).not.toBeVisible();
  });
});

test.describe("Public careers listing (/careers/[tenantSlug])", () => {
  test("renders the real collapse state ('no open positions') when the backend is unreachable, never a 500", async ({ page }) => {
    const response = await page.goto("/careers/does-not-exist-tenant");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Open positions" })).toBeVisible();
    await expect(page.getByText("No open positions right now.")).toBeVisible();
  });

  test("has no automatically detectable accessibility violations", async ({ page }) => {
    await page.goto("/careers/does-not-exist-tenant");
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations).toEqual([]);
  });
});

test.describe("Public careers posting detail (/careers/[tenantSlug]/[postingToken])", () => {
  test("renders the real 'not available' collapse state when the backend is unreachable, never a 500", async ({ page }) => {
    const response = await page.goto("/careers/does-not-exist-tenant/some-raw-posting-token");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "This job posting is not available" })).toBeVisible();
  });

  test("has no automatically detectable accessibility violations", async ({ page }) => {
    await page.goto("/careers/does-not-exist-tenant/some-raw-posting-token");
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations).toEqual([]);
  });
});
