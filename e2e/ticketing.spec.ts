import { test, expect } from "@playwright/test";

/**
 * Ticketing (HRT-286) portal-guard E2E -- ISS-2026-087 closure.
 *
 * Modeled directly on `e2e/hris-employee-master.spec.ts`'s own identical "portal
 * guard" `describe` blocks (itself modeled on `e2e/vendor-registration.spec.ts`'s
 * "Procurement portal guard" block, the established pattern in this repository for a
 * first-real-page-but-no-live-backend spec) and `e2e/tenant-admin-portal.spec.ts`'s
 * own identical disclosed scope: no live Supabase project exists in this sandbox, and
 * there is no root `middleware.ts` -- the ticketing portal-entry guard
 * (`resolveTicketAccessForRequest` / `lib/portal/ticket-guard.ts`) is enforced
 * entirely inside each page component, which calls Next's `notFound()` when access is
 * not `allowed`, never a redirect. Both the ticket list
 * (`app/(tenant)/[tenantSlug]/tickets/page.tsx`) and the ticket detail page
 * (`app/(tenant)/[tenantSlug]/tickets/[ticketId]/page.tsx`) take this path with no
 * live backend to authenticate against, so this spec proves only the fail-safe
 * states: a real non-5xx response (never a 500 or the real shell), for both a real-
 * looking tenant slug and a genuinely nonexistent one. No axe-core check runs against
 * the fail-safe state itself: both pages guard with a bare Next.js `notFound()` (no
 * custom "not available" markup of this app's own) -- axe-checking Next's own default
 * 404 template would assert on framework markup this checkpoint does not own, exactly
 * why `e2e/hris-employee-master.spec.ts`'s own identical guard specs carry no axe
 * check either. Mirrored here rather than deviated from. The detail page's own reply
 * form (with its new ISS-2026-087 file-attachment input, `ticket-detail-panel.tsx`)
 * is reached only past this same guard -- there is no live Supabase project in this
 * sandbox to authenticate a real requester/staff session against, so its actual
 * upload/reply behavior is proven by `scripts/db-tests/ticketing-internal.sql`
 * (DB-layer, real Postgres) instead, never claimed here.
 */

test.describe("Ticket list portal guard", () => {
  test("fails safe (never a 500 or the ticket list shell) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto("/acme/tickets");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Tickets", exact: true })).not.toBeVisible();
  });

  test("also fails safe when the backend itself is unreachable, for a genuinely nonexistent tenant", async ({ page }) => {
    const response = await page.goto("/does-not-exist-tenant/tickets");
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Tickets", exact: true })).not.toBeVisible();
  });
});

test.describe("Ticket detail portal guard (covers the reply form's new attachment input, ISS-2026-087)", () => {
  const SOME_TICKET_ID = "00000000-0000-0000-0000-000000000001";

  test("fails safe (never a 500 or the ticket detail shell) for an unauthenticated visitor", async ({ page }) => {
    const response = await page.goto(`/acme/tickets/${SOME_TICKET_ID}`);
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Post a message", exact: true })).not.toBeVisible();
    await expect(page.locator('input[type="file"][name="attachments"]')).toHaveCount(0);
  });

  test("also fails safe when the backend itself is unreachable, for a genuinely nonexistent tenant", async ({ page }) => {
    const response = await page.goto(`/does-not-exist-tenant/tickets/${SOME_TICKET_ID}`);
    expect(response?.status()).toBeLessThan(500);
    await expect(page.getByRole("heading", { name: "Post a message", exact: true })).not.toBeVisible();
    await expect(page.locator('input[type="file"][name="attachments"]')).toHaveCount(0);
  });
});
