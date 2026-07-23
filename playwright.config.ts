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
  webServer: {
    command: "pnpm exec next dev --port 3000",
    url: "http://127.0.0.1:3000/login",
    reuseExistingServer: !process.env["CI"],
    timeout: 60_000,
    env: {
      NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
      NEXT_PUBLIC_SUPABASE_ANON_KEY: "e2e-placeholder-anon-key",
      SUPABASE_SERVICE_ROLE_KEY: "e2e-placeholder-service-role-key",
    },
  },
});
