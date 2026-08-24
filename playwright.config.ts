import { defineConfig, devices } from "@playwright/test";

// Playwright E2E/visual-regression/accessibility config — CG-S5-PH0-012,
// Prompt 91. Tool choice and rationale: docs/adr/ADR-0007-test-runner-and-
// framework-stack.md. Convention: docs/standards/TESTING_STANDARDS.md.
//
// Single Chromium project only, deliberately, for the pre-existing spec files: this
// checkpoint has no real application/component to run a cross-browser matrix against
// (e2e/smoke.spec.ts scans synthetic inline content only) — adding WebKit/Firefox
// projects to test the same synthetic content three times would be a fabricated
// multi-browser signal, not real coverage.
//
// HDN-381 (Browser and Device Compatibility): `mobile-chrome`/`tablet-chrome` added
// below, scoped via `testMatch` to only `e2e/browser-device-compat.spec.ts` (the other
// 4 spec files never opted into device/viewport testing and running them 3x would add
// execution time with no new signal). Real Safari (WebKit) and Firefox remain
// untestable in this sandbox — no binary exists at `/opt/pw-browsers` and this
// environment's own setup instructions say not to fetch more; TRACKED_GAP, see
// `KNOWN_ISSUES.md` `ISS-2026-244`. Mobile/tablet viewport + touch emulation, by
// contrast, works fully on the pre-installed Chromium binary via `devices[...]` (no
// separate browser needed) — live-verified before adopting this pattern.
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
    {
      name: "mobile-chrome",
      use: { ...devices["Pixel 5"] },
      // HDN-381 Tier C: end-anchored (`\/...$`) rather than a bare substring match -- an
      // unanchored regex would also silently scope in a future differently-named file
      // whose path merely contains this substring (e.g. a hypothetical
      // `browser-device-compat-v2.spec.ts`), which is not this project's intent. NOT
      // start-anchored: Playwright's own `testMatch` matcher runs the regex against each
      // candidate file's full ABSOLUTE filesystem path (`packages/playwright/src/runner/
      // index.js`'s `collectFiles`/`createFileMatcher`), not a `testDir`-relative path --
      // two earlier attempts at a `^...$`-anchored pattern (with and without an `e2e/`
      // prefix) both silently matched zero files for exactly this reason (live-verified:
      // `pnpm exec playwright test --list` dropped from 34 to 22 total tests) before this
      // end-anchored form was confirmed correct.
      testMatch: /\/browser-device-compat\.spec\.ts$/,
    },
    {
      // `devices["iPad Pro 11"]`'s own `defaultBrowserType` is `webkit` (a real iPad runs
      // Safari) -- overridden to `chromium` last, after the spread, since no WebKit binary
      // exists in this sandbox (see the file-level comment above). This project borrows the
      // preset's viewport/UA/touch-emulation fields only, not its browser engine choice --
      // live-verified this actually launches Chromium, not attempt a WebKit download.
      name: "tablet-chrome",
      use: { ...devices["iPad Pro 11"], defaultBrowserType: "chromium" },
      testMatch: /\/browser-device-compat\.spec\.ts$/,
    },
    {
      // HDN-381 Tier C: added to close a real completeness gap Tier C review found -- the
      // checkpoint's own live-testing lens manually verified 4 device profiles (iPhone 13,
      // Pixel 5, iPad Pro 11, plus a plain 375x667 non-touch context), but only 2 of those
      // 4 (Pixel 5, iPad Pro 11) had a permanent project wired up, so 8 of the 16 originally
      // claimed "converted to a permanent regression guard" route x device combinations
      // had no actual automated re-check. `devices["iPhone 13"]`'s own `defaultBrowserType`
      // is also `webkit` (verified the same way as iPad Pro 11 above) -- overridden to
      // `chromium` for the same reason.
      name: "iphone-chrome",
      use: { ...devices["iPhone 13"], defaultBrowserType: "chromium" },
      testMatch: /\/browser-device-compat\.spec\.ts$/,
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
