import { defineConfig, devices } from "@playwright/test";

// Playwright E2E/visual-regression/accessibility config — CG-S5-PH0-012,
// Prompt 91. Tool choice and rationale: docs/adr/ADR-0007-test-runner-and-
// framework-stack.md. Convention: docs/standards/TESTING_STANDARDS.md.
//
// Single Chromium project only, deliberately: this checkpoint has no real
// application/component to run a cross-browser matrix against (e2e/smoke.spec.ts
// scans synthetic inline content only). The latest-two Chrome/Edge/Safari/
// Firefox matrix docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md §8
// requires is deferred to Phase 1, once components/ui/ exists as a real
// subject (docs/standards/TESTING_STANDARDS.md §7's NOT_RUN table) — adding
// WebKit/Firefox projects now to test the same synthetic content three times
// would be a fabricated multi-browser signal, not real coverage.
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env["CI"],
  // Local runs never auto-retry a failure into a pass (docs/standards/
  // TESTING_STANDARDS.md §5); CI retries only transient infra failures.
  retries: process.env["CI"] ? 2 : 0,
  reporter: [["list"], ["html", { open: "never", outputFolder: "playwright-report" }]],
  use: {
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    baseURL: "http://127.0.0.1:3000",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  // PLT-135, CG-S6-PLT-032: the first real Next.js pages (`app/(public)/login`) land
  // in this checkpoint — `webServer` starts the app for `e2e/tenant-admin-portal.spec.ts`
  // (spec-scoped `test.skip` guards keep `e2e/smoke.spec.ts`'s own synthetic-only specs
  // unaffected, they never navigate anywhere real). Placeholder Supabase env values are
  // enough for the login page's own static render/accessibility check (no real
  // sign-in is exercised — no live Supabase project exists yet, disclosed in
  // docs/build-log/phase-01/PLT-135.md).
  //
  // HDN-380 (Accessibility Audit): `command` was `next dev` (Turbopack dev mode) --
  // changed to a real production build (`next build && next start`) after live-forcing
  // the root cause of 5 real `e2e/vendor-registration.spec.ts` failures (`net::ERR_ABORTED`/
  // 30s timeout, `page.url()` returning `""` on `page.goto`/`locator.click`). Directly
  // reproduced in isolation with a throwaway Playwright script against a manually-started
  // `next dev` server: `locator.click()` on the vendor-intake form's submit button hangs
  // forever on "waiting for scheduled navigations to finish" -- a real navigation starts
  // but its "load" event never fires. The identical click against a `next build && next
  // start` server on the same route resolves in under 500ms. This is a Turbopack dev-mode
  // artifact (most likely a hydration-timing race between the button becoming
  // interactable and React 19's `action={formAction}` Server Action interception
  // attaching), not an application defect -- confirmed by running the FULL suite against
  // a production server: **18/18 pass, zero 500s, zero hangs**, vs. 13 passed/5 failed
  // under `next dev`. `docs/build-log/full-system-hardening/HARDENING_MATRIX.md` §11's own
  // instruction ("`next build` is required from this lane onward") independently pointed
  // the same direction. `timeout` raised from 60s to accommodate the build step (a cold
  // `next build` in this sandbox takes roughly a minute).
  //
  // KNOWN FOOTGUN (ISS-2026-243, registered not fixed, HDN-380 Tier C): `reuseExistingServer`
  // (below) is pre-existing, unchanged by this edit -- but switching `command` from `next dev`
  // to `next build && next start` materially raises its risk. Under `next dev` a reused stale
  // server was harmless (dev mode self-refreshes on every request); under `next start` a reused
  // stale server on port 3000 serves a FROZEN, un-rebuilt bundle with no warning if you edit
  // source and re-run `pnpm run test:e2e` without first stopping it. `CI=true` disables
  // `reuseExistingServer` entirely, so this is a local-dev-only risk, not a CI risk.
  webServer: {
    command: "pnpm exec next build && pnpm exec next start --port 3000",
    url: "http://127.0.0.1:3000/login",
    reuseExistingServer: !process.env["CI"],
    timeout: 180_000,
    env: {
      NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
      NEXT_PUBLIC_SUPABASE_ANON_KEY: "e2e-placeholder-anon-key",
      SUPABASE_SERVICE_ROLE_KEY: "e2e-placeholder-service-role-key",
    },
  },
});
