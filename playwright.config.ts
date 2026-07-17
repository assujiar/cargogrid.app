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
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
