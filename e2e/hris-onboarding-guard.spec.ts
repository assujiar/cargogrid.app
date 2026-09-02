import { test, expect } from "@playwright/test";

/**
 * HRT-277 Onboarding/Offboarding portal-guard E2E — `ISS-2026-070` item 5,
 * partial closure.
 *
 * `ISS-2026-070` item 5 names two separate gaps: no `beforeunload` unsaved-change
 * guard on the multi-field case-start/template-authoring forms, and "no
 * Playwright/axe-core E2E spec exists yet for any of the onboarding/offboarding
 * page families". This file closes the "no Playwright spec" half. The
 * `beforeunload` half is closed separately, in the panels themselves, via
 * `components/forms/use-unsaved-change-guard.ts`.
 *
 * Scope, enumerated live against the real `app/(tenant)/[tenantSlug]/hris/
 * onboarding` tree rather than estimated — five distinct `page.tsx` files:
 *
 * - `/{tenant}/hris/onboarding` — the case list (`page.tsx`).
 * - `/{tenant}/hris/onboarding/{caseId}` — the case detail (`[caseId]/page.tsx`).
 * - `/{tenant}/hris/onboarding/my-tasks` — the assignee's own task inbox.
 * - `/{tenant}/hris/onboarding/templates` — the checklist-template list.
 * - `/{tenant}/hris/onboarding/templates/{templateId}/{versionId}` — the
 *   template draft-version authoring page.
 *
 * All five share ONE fail-safe shape, confirmed by direct source read of every
 * file rather than assumed from the route prefix: each calls a bare `notFound()`
 * for any non-`allowed` access status (the two detail routes call it twice — once
 * for the access decision, once for a record the caller may not see). None sits
 * under `app/(tenant)/[tenantSlug]/admin/layout.tsx`, so none of them redirects;
 * the assertions below therefore all mirror `e2e/phase9-admin-guard.spec.ts`'s
 * own "404-guarded" group, never its "Redirect-guarded" one.
 *
 * No axe-core check runs in this file, for the identical reason
 * `e2e/phase9-admin-guard.spec.ts`, `e2e/customer-portal-guard.spec.ts` and
 * `e2e/admin-loyalty-guard.spec.ts` all already give and `ISS-2026-140` records
 * as a structural sandbox constraint: no live Supabase auth backend exists here,
 * so no route behind `resolveCommercialAccessForRequest` can be reached by a real
 * authenticated Playwright session, and a bare `notFound()` renders framework
 * markup this repository does not own. That residual stays OPEN under
 * `ISS-2026-070` item 5 and `ISS-2026-140`, and is not claimed closed here.
 */

test.describe("404-guarded HRIS onboarding/offboarding routes", () => {
  const NOT_FOUND_ROUTES: ReadonlyArray<{ readonly name: string; readonly path: string; readonly heading: string }> = [
    { name: "Onboarding/offboarding case list", path: "/acme/hris/onboarding", heading: "Onboarding & offboarding" },
    {
      name: "Onboarding case detail",
      path: "/acme/hris/onboarding/00000000-0000-0000-0000-000000000070",
      // The case-detail h1 is data-derived (`{employeeFullName} — {caseType}`), so it cannot be
      // asserted by name. Its first static section heading is used instead -- taken verbatim
      // from the panel source, since an `exact: true` locator for a string the page never
      // renders would pass whatever the guard did, proving nothing.
      heading: "Checklist -- access/asset preview and evidence",
    },
    { name: "My assigned onboarding tasks", path: "/acme/hris/onboarding/my-tasks", heading: "My assigned onboarding/offboarding tasks" },
    { name: "Checklist template list", path: "/acme/hris/onboarding/templates", heading: "Onboarding/offboarding checklist templates" },
    {
      name: "Checklist template draft version",
      path: "/acme/hris/onboarding/templates/00000000-0000-0000-0000-000000000071/00000000-0000-0000-0000-000000000072",
      heading: "Tasks",
    },
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
